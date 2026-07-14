// Emby 客户端:登录、取媒体库(Views)、列条目、解析直连播放地址。
use crate::http::{device_name, APP_VERSION, CLIENT_NAME};
use serde::{Deserialize, Serialize};

/// X-Emby-Authorization 头:身份用真实应用标识(非 PoC 名),DeviceId 用持久化设备 ID。
fn auth_header(device_id: &str) -> String {
    format!(
        "MediaBrowser Client=\"{CLIENT_NAME}\", Device=\"{}\", DeviceId=\"{device_id}\", Version=\"{APP_VERSION}\"",
        device_name()
    )
}

#[derive(Clone)]
pub struct Session {
    pub server: String, // 归一化后不带尾斜杠
    pub token: String,
    pub user_id: String,
    pub device_id: String,
}

#[derive(Serialize)]
pub struct LoginResult {
    pub server: String,
    pub token: String,
    pub user_id: String,
    pub user_name: String,
}

#[derive(Deserialize)]
struct AuthResponse {
    #[serde(rename = "AccessToken")]
    access_token: String,
    #[serde(rename = "User")]
    user: AuthUser,
}
#[derive(Deserialize)]
struct AuthUser {
    #[serde(rename = "Id")]
    id: String,
    #[serde(rename = "Name")]
    name: String,
}

#[derive(Deserialize)]
struct ItemsResponse {
    #[serde(rename = "Items")]
    items: Vec<RawItem>,
}
#[derive(Deserialize)]
struct RawItem {
    #[serde(rename = "Id")]
    id: String,
    #[serde(rename = "Name")]
    name: Option<String>,
    #[serde(rename = "Type")]
    type_: Option<String>,
    #[serde(rename = "IsFolder")]
    is_folder: Option<bool>,
    #[serde(rename = "CollectionType")]
    collection_type: Option<String>,
    #[serde(rename = "ImageTags")]
    image_tags: Option<serde_json::Value>,
    #[serde(rename = "RunTimeTicks")]
    runtime_ticks: Option<i64>,
    #[serde(rename = "UserData")]
    user_data: Option<UserData>,
}
#[derive(Deserialize)]
struct UserData {
    #[serde(rename = "PlaybackPositionTicks")]
    position_ticks: Option<i64>,
}

#[derive(Serialize)]
pub struct Item {
    pub id: String,
    pub name: String,
    pub type_: String,
    pub is_folder: bool,
    pub has_primary: bool,
    pub runtime_secs: f64,
    pub resume_secs: f64,
}

impl From<RawItem> for Item {
    fn from(r: RawItem) -> Self {
        let has_primary = r
            .image_tags
            .as_ref()
            .and_then(|v| v.get("Primary"))
            .is_some();
        let is_folder = r.is_folder.unwrap_or(false) || r.collection_type.is_some();
        Item {
            id: r.id,
            name: r.name.unwrap_or_default(),
            type_: r.type_.unwrap_or_default(),
            is_folder,
            has_primary,
            runtime_secs: r.runtime_ticks.unwrap_or(0) as f64 / 1e7,
            resume_secs: r.user_data.and_then(|u| u.position_ticks).unwrap_or(0) as f64 / 1e7,
        }
    }
}

fn norm(server: &str) -> String {
    server.trim().trim_end_matches('/').to_string()
}

pub async fn login(
    http: &reqwest::Client,
    server: &str,
    username: &str,
    password: &str,
    device_id: &str,
) -> Result<(Session, LoginResult), String> {
    let server = norm(server);
    let url = format!("{server}/Users/AuthenticateByName");
    let body = serde_json::json!({ "Username": username, "Pw": password });
    let resp = http
        .post(&url)
        .header("X-Emby-Authorization", auth_header(device_id))
        .json(&body)
        .send()
        .await
        .map_err(|e| format!("网络错误: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("登录失败: HTTP {}", resp.status()));
    }
    let auth: AuthResponse = resp.json().await.map_err(|e| format!("解析失败: {e}"))?;
    let session = Session {
        server: server.clone(),
        token: auth.access_token,
        user_id: auth.user.id.clone(),
        device_id: device_id.to_string(),
    };
    let result = LoginResult {
        server,
        token: session.token.clone(),
        user_id: auth.user.id,
        user_name: auth.user.name,
    };
    Ok((session, result))
}

pub async fn views(http: &reqwest::Client, s: &Session) -> Result<Vec<Item>, String> {
    let url = format!("{}/Users/{}/Views", s.server, s.user_id);
    fetch_items(http, s, &url).await
}

pub async fn items(
    http: &reqwest::Client,
    s: &Session,
    parent_id: &str,
) -> Result<Vec<Item>, String> {
    let url = format!(
        "{}/Users/{}/Items?ParentId={}&SortBy=SortName&SortOrder=Ascending&Fields=PrimaryImageAspectRatio&Limit=200",
        s.server, s.user_id, parent_id
    );
    fetch_items(http, s, &url).await
}

async fn fetch_items(http: &reqwest::Client, s: &Session, url: &str) -> Result<Vec<Item>, String> {
    let resp = http
        .get(url)
        .header("X-Emby-Token", &s.token)
        .send()
        .await
        .map_err(|e| format!("网络错误: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("请求失败: HTTP {}", resp.status()));
    }
    let data: ItemsResponse = resp.json().await.map_err(|e| format!("解析失败: {e}"))?;
    Ok(data.items.into_iter().map(Item::from).collect())
}

#[derive(Deserialize)]
struct PlaybackInfoResp {
    #[serde(rename = "MediaSources")]
    media_sources: Vec<MediaSource>,
}
#[derive(Deserialize)]
struct MediaSource {
    #[serde(rename = "Id")]
    id: String,
    #[serde(rename = "Container")]
    container: Option<String>,
    #[serde(rename = "DirectStreamUrl")]
    direct_stream_url: Option<String>,
    #[serde(rename = "TranscodingUrl")]
    transcoding_url: Option<String>,
}

/// 补全 server 前缀与 api_key。
fn abs_url(s: &Session, path: &str) -> String {
    let mut u = if path.starts_with("http") {
        path.to_string()
    } else {
        format!("{}{}", s.server, path)
    };
    if !u.contains("api_key=") {
        u.push(if u.contains('?') { '&' } else { '?' });
        u.push_str(&format!("api_key={}", s.token));
    }
    u
}

/// 正确解析播放地址:POST PlaybackInfo -> 用服务器给的 DirectStreamUrl/TranscodingUrl。
pub async fn resolve_stream(
    http: &reqwest::Client,
    s: &Session,
    item_id: &str,
) -> Result<String, String> {
    let url = format!(
        "{}/Items/{}/PlaybackInfo?UserId={}",
        s.server, item_id, s.user_id
    );
    // 宽松 DeviceProfile:声明啥都能直连,促使服务器返回 DirectStreamUrl
    let profile = serde_json::json!({
        "DeviceProfile": {
            "MaxStreamingBitrate": 120000000i64,
            "MaxStaticBitrate": 100000000i64,
            "DirectPlayProfiles": [ { "Type": "Video" }, { "Type": "Audio" } ],
            "TranscodingProfiles": [],
            "ContainerProfiles": [],
            "CodecProfiles": [],
            "SubtitleProfiles": []
        }
    });
    let resp = http
        .post(&url)
        .header("X-Emby-Token", &s.token)
        .header("X-Emby-Authorization", auth_header(&s.device_id))
        .json(&profile)
        .send()
        .await
        .map_err(|e| format!("PlaybackInfo 网络错误: {e}"))?;
    if !resp.status().is_success() {
        return Err(format!("PlaybackInfo 失败: HTTP {}", resp.status()));
    }
    let info: PlaybackInfoResp = resp
        .json()
        .await
        .map_err(|e| format!("PlaybackInfo 解析失败: {e}"))?;
    let ms = info
        .media_sources
        .into_iter()
        .next()
        .ok_or("该条目无可播放源")?;
    if let Some(d) = ms.direct_stream_url.filter(|x| !x.is_empty()) {
        return Ok(abs_url(s, &d));
    }
    if let Some(t) = ms.transcoding_url.filter(|x| !x.is_empty()) {
        return Ok(abs_url(s, &t));
    }
    // 兜底:用真实 mediaSourceId + container 直拼
    let container = ms.container.unwrap_or_default();
    let ext = if container.is_empty() {
        String::new()
    } else {
        format!(".{container}")
    };
    Ok(format!(
        "{}/Videos/{}/stream{}?static=true&mediaSourceId={}&api_key={}",
        s.server, item_id, ext, ms.id, s.token
    ))
}

/// 海报地址(前端展示用)。
pub fn image_url(s: &Session, item_id: &str) -> String {
    format!(
        "{}/Items/{}/Images/Primary?maxHeight=360&api_key={}",
        s.server, item_id, s.token
    )
}
