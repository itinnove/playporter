mod aab;
mod auth;
mod secrets;

#[tauri::command]
fn inspect_aab(path: String) -> Result<aab::AabInfo, String> {
    aab::inspect(&path)
}

#[tauri::command]
async fn sign_in() -> Result<String, String> {
    match tauri::async_runtime::spawn_blocking(auth::sign_in_blocking).await {
        Ok(res) => res,
        Err(e) => Err(format!("Tâche interrompue : {e}")),
    }
}

#[tauri::command]
fn is_signed_in() -> bool {
    auth::is_signed_in()
}

#[tauri::command]
fn user_email() -> Option<String> {
    auth::user_email()
}

#[tauri::command]
fn sign_out() {
    auth::sign_out()
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            inspect_aab,
            sign_in,
            is_signed_in,
            user_email,
            sign_out
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
