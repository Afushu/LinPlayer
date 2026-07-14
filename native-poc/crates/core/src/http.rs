// 统一 HTTP 客户端与应用身份(UA/Device)。
// 对应 Dart 侧 app_identity:所有请求(含图片/播放流)走同一 UA,避免 CDN 因 UA 空白返回空白图/流。

pub const APP_VERSION: &str = env!("CARGO_PKG_VERSION");
pub const CLIENT_NAME: &str = "LinPlayer";

/// 统一 User-Agent。
pub fn user_agent() -> String {
    format!("{CLIENT_NAME}/{APP_VERSION}")
}

/// 本机设备名(Emby X-Emby-Authorization 的 Device 字段用)。
pub fn device_name() -> String {
    std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_else(|_| "PC".to_string())
}

/// 全局 HTTP 客户端。
/// ponytail: 测试期 accept_invalid_certs 放行自签名 Emby;上线前收紧成可配置项。
pub fn client() -> reqwest::Client {
    reqwest::Client::builder()
        .user_agent(user_agent())
        .danger_accept_invalid_certs(true)
        .build()
        .expect("build reqwest client")
}
