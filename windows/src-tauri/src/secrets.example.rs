// Copy this file to `secrets.rs` and fill in your Google Cloud OAuth
// "Desktop" client (APIs & Services → Clients). `secrets.rs` is gitignored.

pub const CLIENT_ID: &str = "YOUR_CLIENT_ID.apps.googleusercontent.com";
pub const CLIENT_SECRET: &str = "YOUR_CLIENT_SECRET";
pub const AUTH_URI: &str = "https://accounts.google.com/o/oauth2/auth";
pub const TOKEN_URI: &str = "https://oauth2.googleapis.com/token";
pub const SCOPE: &str = "openid email https://www.googleapis.com/auth/androidpublisher";
