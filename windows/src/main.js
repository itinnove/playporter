const { invoke } = window.__TAURI__.core;
const { listen } = window.__TAURI__.event;

const $ = (sel) => document.querySelector(sel);

// ---- AAB drop ----

async function handlePath(path) {
  const el = $("#result");
  el.hidden = false;
  if (!path.toLowerCase().endsWith(".aab")) {
    el.className = "result error";
    el.textContent = "Ce fichier n'est pas un .aab";
    return;
  }
  el.className = "result";
  el.textContent = "Lecture de l'AAB…";
  try {
    const info = await invoke("inspect_aab", { path });
    const version = [info.version_name, info.version_code ? `(${info.version_code})` : ""]
      .filter(Boolean)
      .join(" ");
    el.className = "result ok";
    el.innerHTML =
      `<div class="row"><span>Package</span><b>${info.application_id}</b></div>` +
      `<div class="row"><span>Version</span><b>${version || "—"}</b></div>`;
  } catch (e) {
    el.className = "result error";
    el.textContent = "Erreur : " + e;
  }
}

// ---- Auth ----

async function refreshAuth() {
  const signin = $("#signin");
  const account = $("#account");
  const signed = await invoke("is_signed_in");
  if (signed) {
    const email = await invoke("user_email");
    account.hidden = false;
    account.textContent = "✅ " + (email || "Connecté");
    account.title = "Cliquer pour se déconnecter";
    signin.hidden = true;
  } else {
    account.hidden = true;
    signin.hidden = false;
    signin.disabled = false;
    signin.textContent = "Se connecter avec Google";
  }
}

async function signIn() {
  const signin = $("#signin");
  signin.disabled = true;
  signin.textContent = "Connexion…";
  try {
    await invoke("sign_in");
  } catch (e) {
    const el = $("#result");
    el.hidden = false;
    el.className = "result error";
    el.textContent = "Connexion échouée : " + e;
  }
  await refreshAuth();
}

async function signOut() {
  await invoke("sign_out");
  await refreshAuth();
}

window.addEventListener("DOMContentLoaded", () => {
  // Drag & drop
  listen("tauri://drag-enter", () => $("#drop").classList.add("over"));
  listen("tauri://drag-leave", () => $("#drop").classList.remove("over"));
  listen("tauri://drag-drop", (event) => {
    $("#drop").classList.remove("over");
    const paths = event.payload && event.payload.paths;
    if (paths && paths.length) handlePath(paths[0]);
  });

  // Auth
  $("#signin").addEventListener("click", signIn);
  $("#account").addEventListener("click", signOut);
  refreshAuth();
});
