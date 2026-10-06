// Google OAuth 2.0 (PKCE) with a loopback redirect. The refresh token is stored
// in the OS secure store (Windows Credential Manager / macOS Keychain) via keyring.

use base64::Engine;
use keyring::Entry;
use rand::RngCore;
use sha2::{Digest, Sha256};
use std::io::{Read, Write};
use std::net::TcpListener;

use crate::secrets;

const SERVICE: &str = "com.itinnove.playporter";
const ACCOUNT_REFRESH: &str = "google.refreshToken";
const ACCOUNT_EMAIL: &str = "google.email";

fn entry(account: &str) -> Result<Entry, String> {
    Entry::new(SERVICE, account).map_err(|e| e.to_string())
}
fn store(account: &str, value: &str) -> Result<(), String> {
    entry(account)?.set_password(value).map_err(|e| e.to_string())
}
fn load(account: &str) -> Option<String> {
    entry(account).ok()?.get_password().ok()
}
fn clear(account: &str) {
    if let Ok(e) = entry(account) {
        let _ = e.delete_credential();
    }
}

pub fn is_signed_in() -> bool {
    load(ACCOUNT_REFRESH).is_some()
}
pub fn user_email() -> Option<String> {
    load(ACCOUNT_EMAIL)
}
pub fn sign_out() {
    clear(ACCOUNT_REFRESH);
    clear(ACCOUNT_EMAIL);
}

fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}
fn random_url_safe(n: usize) -> String {
    let mut buf = vec![0u8; n];
    rand::thread_rng().fill_bytes(&mut buf);
    b64url(&buf)
}
fn challenge(verifier: &str) -> String {
    let mut h = Sha256::new();
    h.update(verifier.as_bytes());
    b64url(&h.finalize())
}

/// Full interactive sign-in. Blocking — call via spawn_blocking. Returns the email.
pub fn sign_in_blocking() -> Result<String, String> {
    let verifier = random_url_safe(32);
    let chal = challenge(&verifier);
    let state = random_url_safe(16);

    let listener =
        TcpListener::bind("127.0.0.1:0").map_err(|e| format!("Serveur local impossible : {e}"))?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let redirect = format!("http://127.0.0.1:{port}");

    let auth_url = format!(
        "{}?response_type=code&client_id={}&redirect_uri={}&scope={}&code_challenge={}&code_challenge_method=S256&access_type=offline&prompt=consent&state={}",
        secrets::AUTH_URI,
        urlencoding::encode(secrets::CLIENT_ID),
        urlencoding::encode(&redirect),
        urlencoding::encode(secrets::SCOPE),
        urlencoding::encode(&chal),
        urlencoding::encode(&state),
    );
    webbrowser::open(&auth_url).map_err(|e| format!("Ouverture du navigateur : {e}"))?;

    // Wait for the browser redirect.
    let (mut stream, _) = listener.accept().map_err(|e| e.to_string())?;
    let mut buf = [0u8; 8192];
    let n = stream.read(&mut buf).map_err(|e| e.to_string())?;
    let request = String::from_utf8_lossy(&buf[..n]);
    let first = request.lines().next().unwrap_or("");
    let path = first.split_whitespace().nth(1).unwrap_or("");
    let query = path.splitn(2, '?').nth(1).unwrap_or("");

    let (mut code, mut got_state, mut err) =
        (Option::<String>::None, Option::<String>::None, Option::<String>::None);
    for pair in query.split('&') {
        let mut it = pair.splitn(2, '=');
        let k = it.next().unwrap_or("");
        let raw = it.next().unwrap_or("");
        let v = urlencoding::decode(raw).map(|c| c.into_owned()).unwrap_or_default();
        match k {
            "code" => code = Some(v),
            "state" => got_state = Some(v),
            "error" => err = Some(v),
            _ => {}
        }
    }

    let page = "<!doctype html><meta charset=utf-8><body style='font-family:sans-serif;text-align:center;padding-top:64px;color:#1d1d1f'><h2>\u{2705} Playporter connect\u{e9}</h2><p>Vous pouvez fermer cet onglet.</p></body>";
    let response = format!(
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
        page.len(),
        page
    );
    let _ = stream.write_all(response.as_bytes());

    if let Some(e) = err {
        return Err(format!("Autorisation refusée : {e}"));
    }
    if got_state.as_deref() != Some(state.as_str()) {
        return Err("state invalide".into());
    }
    let code = code.ok_or("code manquant")?;

    let resp: serde_json::Value = ureq::post(secrets::TOKEN_URI)
        .send_form(&[
            ("code", code.as_str()),
            ("client_id", secrets::CLIENT_ID),
            ("client_secret", secrets::CLIENT_SECRET),
            ("code_verifier", verifier.as_str()),
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirect.as_str()),
        ])
        .map_err(|e| format!("Échange de tokens : {e}"))?
        .into_json()
        .map_err(|e| e.to_string())?;

    let refresh = resp["refresh_token"].as_str().ok_or("refresh_token manquant")?;
    store(ACCOUNT_REFRESH, refresh)?;

    if let Some(access) = resp["access_token"].as_str() {
        if let Ok(info) = ureq::get("https://openidconnect.googleapis.com/v1/userinfo")
            .set("Authorization", &format!("Bearer {access}"))
            .call()
        {
            if let Ok(j) = info.into_json::<serde_json::Value>() {
                if let Some(email) = j["email"].as_str() {
                    let _ = store(ACCOUNT_EMAIL, email);
                }
            }
        }
    }

    Ok(user_email().unwrap_or_default())
}

/// Fresh access token from the stored refresh token. Blocking.
pub fn access_token() -> Result<String, String> {
    let refresh = load(ACCOUNT_REFRESH).ok_or("Non connecté à Google")?;
    let resp: serde_json::Value = ureq::post(secrets::TOKEN_URI)
        .send_form(&[
            ("client_id", secrets::CLIENT_ID),
            ("client_secret", secrets::CLIENT_SECRET),
            ("refresh_token", refresh.as_str()),
            ("grant_type", "refresh_token"),
        ])
        .map_err(|e| format!("Rafraîchissement du token : {e}"))?
        .into_json()
        .map_err(|e| e.to_string())?;
    resp["access_token"]
        .as_str()
        .map(|s| s.to_string())
        .ok_or_else(|| "access_token manquant".into())
}
