mod mpv;

use linplayer_core::config::{Account, AppConfig};
use linplayer_core::emby::{self, Item, LoginResult, Session};
use linplayer_core::http;
use mpv::{Player, Status, Track};
use raw_window_handle::{HasWindowHandle, RawWindowHandle};
use std::sync::Mutex;
use tauri::{Manager, State, WindowEvent};

struct AppState {
    http: reqwest::Client,
    config: Mutex<AppConfig>,
    session: Mutex<Option<Session>>,
    player: Mutex<Option<Player>>,
}

fn poclog(msg: &str) {
    use std::io::Write;
    let path = std::env::temp_dir().join("linplayer_poc.log");
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(f, "{msg}");
    }
}

/// 把 mpv 视频窗口对齐到 Tauri 窗口客户区。
fn sync_video(window: &tauri::WebviewWindow, parent: isize, state: &AppState) {
    let video = state.player.lock().unwrap().as_ref().map(|p| p.video_hwnd);
    if let Some(v) = video {
        if let (Ok(pos), Ok(size)) = (window.inner_position(), window.inner_size()) {
            mpv::sync_overlay(v, parent, pos.x, pos.y, size.width as i32, size.height as i32);
        }
    }
}

fn hwnd_of(window: &tauri::WebviewWindow) -> Result<isize, String> {
    let handle = window.window_handle().map_err(|e| e.to_string())?;
    match handle.as_raw() {
        RawWindowHandle::Win32(h) => Ok(h.hwnd.get()),
        _ => Err("非 Win32 窗口".into()),
    }
}

fn session_of(state: &State<'_, AppState>) -> Result<Session, String> {
    state
        .session
        .lock()
        .unwrap()
        .clone()
        .ok_or_else(|| "未登录".to_string())
}

// ---------- Emby 命令 ----------
#[tauri::command]
async fn login(
    state: State<'_, AppState>,
    server: String,
    username: String,
    password: String,
) -> Result<LoginResult, String> {
    let device_id = state.config.lock().unwrap().device_id.clone();
    let (session, result) =
        emby::login(&state.http, &server, &username, &password, &device_id).await?;
    // 持久化账号 -> 重启免登
    {
        let mut cfg = state.config.lock().unwrap();
        cfg.upsert(Account {
            server: result.server.clone(),
            token: result.token.clone(),
            user_id: result.user_id.clone(),
            user_name: result.user_name.clone(),
        });
        cfg.save();
    }
    *state.session.lock().unwrap() = Some(session);
    Ok(result)
}

/// 已登录账号(用于启动时跳过登录页直接进库);无则 None。
#[tauri::command]
fn current_session(state: State<'_, AppState>) -> Option<LoginResult> {
    state.config.lock().unwrap().active_account().map(|a| LoginResult {
        server: a.server.clone(),
        token: a.token.clone(),
        user_id: a.user_id.clone(),
        user_name: a.user_name.clone(),
    })
}

#[tauri::command]
async fn views(state: State<'_, AppState>) -> Result<Vec<Item>, String> {
    let s = session_of(&state)?;
    emby::views(&state.http, &s).await
}

#[tauri::command]
async fn list_items(state: State<'_, AppState>, parent_id: String) -> Result<Vec<Item>, String> {
    let s = session_of(&state)?;
    emby::items(&state.http, &s, &parent_id).await
}

#[tauri::command]
fn image_url(state: State<'_, AppState>, item_id: String) -> Result<String, String> {
    let s = session_of(&state)?;
    Ok(emby::image_url(&s, &item_id))
}

// ---------- 播放命令 ----------
#[tauri::command]
async fn play(state: State<'_, AppState>, item_id: String) -> Result<String, String> {
    let s = session_of(&state)?;
    let url = emby::resolve_stream(&state.http, &s, &item_id).await?;
    poclog(&format!("PLAY item={item_id} url={url}"));
    let guard = state.player.lock().unwrap();
    let p = guard.as_ref().ok_or_else(|| {
        poclog("PLAY 失败: 播放器未就绪(mpv 初始化没成功)");
        "播放器未就绪".to_string()
    })?;
    match p.load(&url) {
        Ok(_) => {
            p.set_pause(false);
            poclog("load OK");
            Ok(url)
        }
        Err(e) => {
            poclog(&format!("load ERR: {e}"));
            Err(e)
        }
    }
}

#[tauri::command]
fn set_pause(state: State<'_, AppState>, paused: bool) -> Result<(), String> {
    let guard = state.player.lock().unwrap();
    guard.as_ref().ok_or("播放器未就绪")?.set_pause(paused);
    Ok(())
}

#[tauri::command]
fn seek(state: State<'_, AppState>, pos: f64) -> Result<(), String> {
    let guard = state.player.lock().unwrap();
    guard.as_ref().ok_or("播放器未就绪")?.seek_abs(pos)
}

#[tauri::command]
fn status(state: State<'_, AppState>) -> Result<Status, String> {
    let guard = state.player.lock().unwrap();
    Ok(guard.as_ref().ok_or("播放器未就绪")?.status())
}

#[tauri::command]
fn tracks(state: State<'_, AppState>) -> Result<Vec<Track>, String> {
    let guard = state.player.lock().unwrap();
    Ok(guard.as_ref().ok_or("播放器未就绪")?.tracks())
}

#[tauri::command]
fn set_track(state: State<'_, AppState>, kind: String, id: String) -> Result<(), String> {
    let guard = state.player.lock().unwrap();
    guard.as_ref().ok_or("播放器未就绪")?.set_track(&kind, &id);
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let config = AppConfig::load();
    let http = http::client();

    // 有活跃账号 -> 用存盘凭据重建会话(重启免登)
    let session = config.active_account().map(|a| Session {
        server: a.server.clone(),
        token: a.token.clone(),
        user_id: a.user_id.clone(),
        device_id: config.device_id.clone(),
    });

    // 清旧诊断日志
    let _ = std::fs::remove_file(std::env::temp_dir().join("linplayer_poc.log"));
    let _ = std::fs::remove_file(mpv::mpv_log_path());

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(AppState {
            http,
            config: Mutex::new(config),
            session: Mutex::new(session),
            player: Mutex::new(None),
        })
        .setup(|app| {
            let window = app.get_webview_window("main").expect("main window");
            let parent = match hwnd_of(&window) {
                Ok(p) => {
                    poclog(&format!("hwnd OK parent={p}"));
                    Some(p)
                }
                Err(e) => {
                    poclog(&format!("hwnd ERR: {e}"));
                    None
                }
            };
            match Player::new() {
                Ok(p) => {
                    poclog(&format!("player init OK video_hwnd={}", p.video_hwnd));
                    *app.state::<AppState>().player.lock().unwrap() = Some(p);
                }
                Err(e) => poclog(&format!("player init ERR: {e}")),
            }
            if let Some(parent) = parent {
                sync_video(&window, parent, &app.state::<AppState>());
            }

            // 窗口移动/缩放/激活 -> 重新对齐视频窗口
            let app_handle = app.handle().clone();
            let win2 = window.clone();
            window.on_window_event(move |ev| {
                if matches!(
                    ev,
                    WindowEvent::Resized(_) | WindowEvent::Moved(_) | WindowEvent::Focused(true)
                ) {
                    if let Some(parent) = parent {
                        sync_video(&win2, parent, &app_handle.state::<AppState>());
                    }
                }
            });
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            login,
            current_session,
            views,
            list_items,
            image_url,
            play,
            set_pause,
            seek,
            status,
            tracks,
            set_track
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
