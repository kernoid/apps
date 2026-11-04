// SPDX-License-Identifier: MIT
//! The core of the system's file shells (docs/plan.md, 5): the File Provider extensions on Apple's systems, the
//! DocumentsProvider on Android, the Cloud Files provider on Windows. They show kernoid's stores in the system's file
//! manager; what they ask – which items there are, what changed, the content of one, a new or changed or removed one –
//! is answered here, on kernoid's Rust SDK, so that each shell only translates for its system.
//!
//! The boundary is messages, as between omaflake's Swift app and its Rust core: a request is a JSON object with an
//! `op`, the answer a JSON object with `ok` or `error` (`message`, `unauthorized`). Swift calls [`kernoid_provider_call`]
//! and frees the answer with [`kernoid_provider_free`] (a C boundary of two functions); Kotlin calls
//! `dev.kernoid.kernoid.ProviderCore.call` (JNI, `provider/jni.rs`); the Windows shell is Rust and calls [`call`]
//! itself.
//!
//! A shell has a login of its own (`open` with what the app kept for it): kernoid rotates refresh tokens, and two
//! processes renewing one login would end it. Its renewals come back as `kept` in the next answer – in `ok` or in
//! `error` – and the shell keeps the newest. Vaults stay locked in the shells (**OPEN**: the account's key from a `device:` copy in the platform's
//! key store, plan section 6).
//!
//! Operations: `open {kept}` (or `{server, address, password}` with an app password) → `{session, kept}`; `close {session}`; `stores {session}`; `list {session, store,
//! parent}`; `changes {session, store, since}` → `{items, deleted, anchor, more}` (no `since`: everything); `item
//! {session, store, id}`; `fetch {session, store, id, to}` (the content into a file); `create {session, store, parent,
//! name, directory, from}`; `modify {session, store, id, name, parent, from}` (each optional; `parent: null` is the
//! top); `delete {session, store, id}` (into the store's Trash).

use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char};
use std::sync::{LazyLock, Mutex};

use kernoid_client::{Client, FILENODE, files};
use serde_json::{Value, json};

use crate::api::kernoid::{Kernoid, KernoidError, RUNTIME};

#[cfg(target_os = "android")]
mod jni;

/// Changes asked for at once.
const MAX_CHANGES: u64 = 500;

/// The open sessions of this process, by number.
static SESSIONS: LazyLock<Mutex<HashMap<u64, Session>>> = LazyLock::new(Mutex::default);

struct Session {
    account: Kernoid,
    /// The login as last handed to the shell; a renewal differs from it.
    kept: Option<String>,
}

/// Answers one request (JSON) with one answer (JSON). Never panics across the boundary.
pub fn call(request: &str) -> String {
    let answer = std::panic::catch_unwind(|| match serde_json::from_str::<Value>(request) {
        Ok(request) => RUNTIME.block_on(dispatch(&request)),
        Err(e) => (Err(error(&format!("not JSON: {e}"))), None),
    });
    let (mut answer, kept) = match answer {
        Ok((Ok(value), kept)) => (json!({ "ok": value }), kept),
        Ok((Err(error), kept)) => {
            (json!({ "error": { "message": error.message, "unauthorized": error.unauthorized } }), kept)
        }
        Err(_) => (json!({ "error": { "message": "the core failed", "unauthorized": false } }), None),
    };
    // A renewal goes with every answer, an error too: the login before it is used up.
    if let Some(kept) = kept
        && let Some(inner) = answer.as_object_mut().and_then(|a| a.values_mut().next()).and_then(Value::as_object_mut)
    {
        inner.insert("kept".into(), json!(kept));
    }
    answer.to_string()
}

/// [`call`] for C: `request` is UTF-8 ending in NUL; the answer is to be given back to [`kernoid_provider_free`].
///
/// # Safety
/// `request` must point to a NUL-terminated string that stays valid during the call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kernoid_provider_call(request: *const c_char) -> *mut c_char {
    let request = if request.is_null() {
        String::new()
    } else {
        // SAFETY: the caller passes a NUL-terminated string valid for the call.
        unsafe { CStr::from_ptr(request) }.to_string_lossy().into_owned()
    };
    let answer = call(&request).replace('\0', "");
    CString::new(answer).unwrap_or_default().into_raw()
}

/// Frees an answer of [`kernoid_provider_call`].
///
/// # Safety
/// `answer` must come from [`kernoid_provider_call`] and be freed only once.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn kernoid_provider_free(answer: *mut c_char) {
    if !answer.is_null() {
        // SAFETY: made by `CString::into_raw` in `kernoid_provider_call`, freed once.
        drop(unsafe { CString::from_raw(answer) });
    }
}

fn error(message: &str) -> KernoidError {
    KernoidError { unauthorized: false, message: message.to_owned() }
}

fn text<'a>(request: &'a Value, key: &str) -> Result<&'a str, KernoidError> {
    request.get(key).and_then(Value::as_str).ok_or_else(|| error(&format!("`{key}` is missing")))
}

fn optional<'a>(request: &'a Value, key: &str) -> Option<&'a str> {
    request.get(key).and_then(Value::as_str)
}

/// Answers a request, with the session's login if it was renewed since the last answer.
async fn dispatch(request: &Value) -> (Result<Value, KernoidError>, Option<String>) {
    let result = answer(request).await;
    (result, request.get("session").and_then(Value::as_u64).and_then(renewal))
}

/// The session's login when it differs from the one last handed to the shell.
fn renewal(id: u64) -> Option<String> {
    let mut sessions = SESSIONS.lock().ok()?;
    let session = sessions.get_mut(&id)?;
    let now = session.account.kept_login();
    let renewed = (now != session.kept).then(|| now.clone()).flatten();
    session.kept = now;
    renewed
}

async fn answer(request: &Value) -> Result<Value, KernoidError> {
    let op = text(request, "op")?;
    if op == "open" {
        // The login kept for the shell; or an address with an app password (tests, and systems without a browser).
        let account = match optional(request, "kept") {
            Some(kept) => Kernoid::resume(kept.to_owned()).await?,
            None => {
                let (server, address) = (text(request, "server")?, text(request, "address")?);
                Kernoid::login(server.into(), address.into(), text(request, "password")?.into()).await?
            }
        };
        let kept = account.kept_login();
        let mut sessions = SESSIONS.lock().map_err(|_| error("the sessions are broken"))?;
        let id = sessions.keys().max().map_or(1, |n| n + 1);
        sessions.insert(id, Session { account, kept: kept.clone() });
        return Ok(json!({ "session": id, "kept": kept }));
    }
    let id = request.get("session").and_then(Value::as_u64).ok_or_else(|| error("`session` is missing"))?;
    if op == "close" {
        SESSIONS.lock().map_err(|_| error("the sessions are broken"))?.remove(&id);
        return Ok(json!({}));
    }
    let client = {
        let sessions = SESSIONS.lock().map_err(|_| error("the sessions are broken"))?;
        sessions.get(&id).ok_or_else(|| error("no such session"))?.account.sdk_client()
    };
    Ok(match op {
        "stores" => stores(&client),
        "list" => {
            let store = text(request, "store")?;
            let nodes = files::children(&client, store, optional(request, "parent")).await?;
            json!({ "items": nodes.iter().map(item).collect::<Vec<_>>() })
        }
        "changes" => changes(&client, text(request, "store")?, optional(request, "since")).await?,
        "item" => json!({ "item": item(&node(&client, text(request, "store")?, text(request, "id")?).await?) }),
        "fetch" => fetch(&client, request).await?,
        "create" => create(&client, request).await?,
        "modify" => modify(&client, request).await?,
        "delete" => {
            let (store, id) = (text(request, "store")?, text(request, "id")?);
            match files::trash(&client, store).await?.map(|trash| trash.id) {
                Some(trash) => files::move_to(&client, store, id, Some(&trash)).await?,
                None => files::destroy(&client, store, id).await?,
            }
            json!({})
        }
        other => return Err(error(&format!("no operation `{other}`"))),
    })
}

fn stores(client: &Client) -> Value {
    let stores = files::stores(client);
    json!({ "stores": stores.iter().map(|s| json!({
        "id": s.id,
        "name": s.name,
        "kind": format!("{:?}", s.kind).to_lowercase(),
    })).collect::<Vec<_>>() })
}

/// An item as the shells see it: its version changes with its content, name or place – what the File Provider and
/// Cloud Files compare.
fn item(n: &files::FileNode) -> Value {
    let r = n.rights();
    json!({
        "id": n.id,
        "parent": n.parent_id,
        "name": n.name,
        "directory": n.is_directory(),
        "size": n.size.unwrap_or_default(),
        "modified": n.modified,
        "mediaType": n.media_type,
        "role": n.role,
        "version": format!("{}|{}|{}", n.blob_id.as_deref().unwrap_or("-"), n.parent_id.as_deref().unwrap_or("-"), n.name),
        "rights": { "read": r.may_read, "add": r.may_add_children, "rename": r.may_rename, "delete": r.may_delete,
                    "write": r.may_modify_content },
        "vault": n.vault,
        // In a vault the name is an id and the content ciphertext: shown as locked, not opened (OPEN).
        "locked": n.vault.is_some(),
    })
}

async fn node(client: &Client, store: &str, id: &str) -> Result<files::FileNode, KernoidError> {
    let result = client.call(&[FILENODE], "FileNode/get", json!({ "accountId": store, "ids": [id] })).await?;
    let found = result.get("list").and_then(Value::as_array).and_then(|list| list.first()).cloned();
    let found = found.ok_or_else(|| error("no such item"))?;
    serde_json::from_value(found).map_err(|e| error(&format!("an item the core cannot read: {e}")))
}

async fn changes(client: &Client, store: &str, since: Option<&str>) -> Result<Value, KernoidError> {
    let Some(since) = since.filter(|s| !s.is_empty()) else {
        let snapshot = files::snapshot(client, store).await?;
        let items: Vec<Value> = snapshot.nodes.iter().map(item).collect();
        return Ok(json!({ "items": items, "deleted": [], "anchor": snapshot.state, "more": false, "reset": true }));
    };
    match files::changes(client, store, since, MAX_CHANGES).await {
        Ok(changes) => Ok(json!({
            "items": changes.changed.iter().map(item).collect::<Vec<_>>(),
            "deleted": changes.destroyed,
            "anchor": changes.new_state,
            "more": changes.has_more_changes,
            "reset": false,
        })),
        // Too old: the shell starts over with everything.
        Err(kernoid_client::Error::Method { kind, .. }) if kind == "cannotCalculateChanges" => {
            Ok(json!({ "items": [], "deleted": [], "anchor": "", "more": false, "reset": true, "expired": true }))
        }
        Err(other) => Err(other.into()),
    }
}

async fn fetch(client: &Client, request: &Value) -> Result<Value, KernoidError> {
    let (store, id, to) = (text(request, "store")?, text(request, "id")?, text(request, "to")?);
    let n = node(client, store, id).await?;
    if n.vault.is_some() {
        return Err(error("the item lies in a vault, which the file manager cannot open yet"));
    }
    let blob = n.blob_id.as_deref().ok_or_else(|| error("a folder has no content"))?;
    let mut file = tokio::fs::File::create(to).await.map_err(|e| error(&e.to_string()))?;
    let kind = n.media_type.as_deref().unwrap_or("application/octet-stream");
    client.download(store, blob, &n.name, kind, &mut file, &mut |_, _| {}).await?;
    Ok(json!({ "item": item(&n) }))
}

async fn create(client: &Client, request: &Value) -> Result<Value, KernoidError> {
    let (store, name) = (text(request, "store")?, text(request, "name")?);
    let parent = optional(request, "parent");
    if request.get("directory").and_then(Value::as_bool).unwrap_or(false) {
        files::create_directory(client, store, parent, name).await?;
    } else {
        let from = text(request, "from")?;
        let local = std::path::Path::new(from);
        // Uploaded under the name asked for, wherever the system put the content.
        let staged = local.with_file_name(name);
        let path = if local.file_name() == staged.file_name() { local.to_path_buf() } else { staged };
        if path != local {
            tokio::fs::copy(local, &path).await.map_err(|e| error(&e.to_string()))?;
        }
        let result = files::upload_file(client, store, parent, &path, None, |_, _| {}).await;
        if path != local {
            let _ = tokio::fs::remove_file(&path).await;
        }
        result?;
    }
    let made = files::children(client, store, parent)
        .await?
        .into_iter()
        .find(|n| n.name == name)
        .ok_or_else(|| error("the item was not made"))?;
    Ok(json!({ "item": item(&made) }))
}

async fn modify(client: &Client, request: &Value) -> Result<Value, KernoidError> {
    let (store, id) = (text(request, "store")?, text(request, "id")?);
    let mut n = node(client, store, id).await?;
    if n.vault.is_some() {
        return Err(error("the item lies in a vault, which the file manager cannot change yet"));
    }
    let mut update = serde_json::Map::new();
    if let Some(name) = optional(request, "name").filter(|name| *name != n.name) {
        update.insert("name".into(), json!(name));
    }
    if let Some(parent) = request.get("parent")
        && parent.as_str() != n.parent_id.as_deref()
    {
        update.insert("parentId".into(), parent.clone());
    }
    if let Some(from) = optional(request, "from") {
        let size = tokio::fs::metadata(from).await.map_err(|e| error(&e.to_string()))?.len();
        let file = tokio::fs::File::open(from).await.map_err(|e| error(&e.to_string()))?;
        let kind = files::media_type(optional(request, "name").unwrap_or(&n.name));
        let upload = client.upload(store, kind, file, size, |_, _| {}).await?;
        update.insert("blobId".into(), json!(upload.blob_id));
        update.insert("mediaType".into(), json!(kind));
    }
    if !update.is_empty() {
        let change = json!({ "update": { id: Value::Object(update) } });
        client.set(&[FILENODE], "FileNode", store, change, json!({})).await?;
        n = node(client, store, id).await?;
    }
    Ok(json!({ "item": item(&n) }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requests_that_cannot_be_answered_say_why() {
        let answer: Value = serde_json::from_str(&call("not json")).unwrap();
        assert!(answer["error"]["message"].as_str().unwrap().starts_with("not JSON"));
        let answer: Value = serde_json::from_str(&call(r#"{"op":"list","session":99}"#)).unwrap();
        assert_eq!(answer["error"]["message"], "no such session");
        let answer: Value = serde_json::from_str(&call(r#"{"op":"open","kept":"{}"}"#)).unwrap();
        assert_eq!(answer["error"]["unauthorized"], true);
    }

    #[test]
    fn the_c_boundary_gives_and_takes_back() {
        let request = CString::new(r#"{"op":"close","session":1}"#).unwrap();
        // SAFETY: a NUL-terminated string valid for the call; the answer freed once.
        unsafe {
            let answer = kernoid_provider_call(request.as_ptr());
            assert_eq!(CStr::from_ptr(answer).to_str().unwrap(), r#"{"ok":{}}"#);
            kernoid_provider_free(answer);
        }
    }
}
