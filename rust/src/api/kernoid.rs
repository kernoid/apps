// SPDX-License-Identifier: MIT
//! The API of a logged-in account, as Dart sees it: plain records in, plain records out. Every call runs on one tokio
//! runtime of the process; Dart awaits it. Secret keys stay here – Dart sees whether a key is unlocked, never the key.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, LazyLock};

use flutter_rust_bridge::frb;
use tokio::sync::Mutex;

use crate::client::e2e::{self, E2e, Plan};
use crate::client::{self, Client, files, mail};

static RUNTIME: LazyLock<tokio::runtime::Runtime> = LazyLock::new(|| {
    tokio::runtime::Builder::new_multi_thread()
        .worker_threads(2)
        .thread_name("kernoid")
        .enable_all()
        .build()
        .expect("a tokio runtime")
});

/// Runs a future on the runtime, whichever executor awaits it.
async fn run<T: Send + 'static>(
    future: impl Future<Output = client::Result<T>> + Send + 'static,
) -> Result<T, KernoidError> {
    match RUNTIME.spawn(future).await {
        Ok(result) => result.map_err(KernoidError::from),
        Err(error) => Err(KernoidError { unauthorized: false, message: error.to_string() }),
    }
}

/// An error for people: the message is shown as it is.
#[derive(Debug, Clone)]
pub struct KernoidError {
    /// The address or the app password is wrong – ask again.
    pub unauthorized: bool,
    pub message: String,
}

impl From<client::Error> for KernoidError {
    fn from(error: client::Error) -> Self {
        KernoidError { unauthorized: matches!(error, client::Error::Unauthorized), message: error.to_string() }
    }
}

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

/// A logged-in account and the stores it reaches.
#[frb(opaque)]
#[derive(Debug)]
pub struct Kernoid {
    client: Client,
    e2e: Arc<Mutex<E2e>>,
    /// Decrypted messages by email id, for saving their attachments; forgotten when the key is locked.
    opened: Arc<Mutex<HashMap<String, Vec<u8>>>>,
}

#[derive(Debug, Clone)]
pub struct Mailbox {
    pub id: String,
    pub name: String,
    pub parent_id: Option<String>,
    pub role: Option<String>,
    pub total: i64,
    pub unread: i64,
}

#[derive(Debug, Clone)]
pub struct Address {
    pub name: Option<String>,
    pub email: String,
}

#[derive(Debug, Clone)]
pub struct EmailSummary {
    pub id: String,
    pub from: Vec<Address>,
    pub subject: String,
    pub preview: String,
    /// RFC 3339, UTC.
    pub received_at: String,
    pub seen: bool,
    pub flagged: bool,
    pub has_attachment: bool,
    /// End-to-end encrypted.
    pub encrypted: bool,
    /// Encrypted, and the key that opens it is not unlocked here: subject and preview are not known.
    pub locked: bool,
}

#[derive(Debug, Clone)]
pub struct EmailPage {
    pub emails: Vec<EmailSummary>,
    pub total: i64,
}

/// A file attached to an email: on the server (`blob_id`), or inside a decrypted message (`part_index`).
#[derive(Debug, Clone)]
pub struct Attachment {
    pub blob_id: Option<String>,
    pub part_index: Option<u32>,
    pub name: String,
    pub media_type: String,
    pub size: i64,
}

#[derive(Debug, Clone)]
pub struct Email {
    pub id: String,
    pub from: Vec<Address>,
    pub to: Vec<Address>,
    pub cc: Vec<Address>,
    pub subject: String,
    pub received_at: String,
    pub text: String,
    pub attachments: Vec<Attachment>,
    pub encrypted: bool,
    pub locked: bool,
    pub signed: bool,
    /// The signature is valid and by a key of the sender.
    pub verified: bool,
}

#[derive(Debug, Clone)]
pub struct FileStore {
    pub account_id: String,
    pub name: String,
    pub is_personal: bool,
}

#[derive(Debug, Clone)]
pub struct FileNode {
    pub id: String,
    pub name: String,
    pub is_directory: bool,
    pub role: Option<String>,
    pub blob_id: Option<String>,
    pub size: i64,
    pub media_type: Option<String>,
    pub modified: Option<String>,
}

/// Where end-to-end encryption stands for this account (RFC 0006).
#[derive(Debug, Clone)]
pub struct E2eStatus {
    /// The server has kernoid's end-to-end extension.
    pub available: bool,
    pub has_key: bool,
    pub unlocked: bool,
    pub fingerprint: Option<String>,
    /// `pqc` or `compatible`.
    pub kind: Option<String>,
    /// Mail is encrypted on arrival as well (an account setting for other software, RFC 0006, 5.1).
    pub mail_on_arrival: bool,
    /// The tenant can recover the key (RFC 0006, 8.2).
    pub tenant_recovers: bool,
}

/// How a message to these recipients would go out.
#[derive(Debug, Clone)]
pub struct SendPlan {
    pub encrypted: bool,
    /// Why not, when it is not.
    pub reason: Option<String>,
}

fn addresses(list: Option<Vec<mail::EmailAddress>>) -> Vec<Address> {
    list.unwrap_or_default().into_iter().map(|a| Address { name: a.name, email: a.email }).collect()
}

fn count(n: u64) -> i64 {
    i64::try_from(n).unwrap_or(i64::MAX)
}

fn status(e2e: &E2e) -> E2eStatus {
    let key = e2e.current_key();
    E2eStatus {
        available: e2e.available,
        has_key: key.is_some(),
        unlocked: e2e.is_unlocked(),
        fingerprint: key.map(|k| k.id.clone()),
        kind: key.map(|k| k.kind.clone()),
        mail_on_arrival: e2e.settings.mail,
        tenant_recovers: e2e.settings.policy.recovery,
    }
}

fn recipients(to: &[String]) -> Vec<String> {
    to.iter().map(|a| a.trim().to_owned()).filter(|a| a.contains('@')).collect()
}

impl Kernoid {
    /// Logs in with an address and an app password (**OPEN**: OpenID Connect with PKCE, tokens in the system's
    /// key store – docs/plan.md, 7).
    pub async fn login(server: String, address: String, password: String) -> Result<Kernoid, KernoidError> {
        let (client, e2e) = run(async move {
            let client = Client::login(&server, &address, &password).await?;
            // A server without the extension, or one that fails to answer it, is mail without end-to-end encryption.
            let e2e = E2e::load(&client).await.unwrap_or_default();
            Ok((client, e2e))
        })
        .await?;
        Ok(Kernoid { client, e2e: Arc::new(Mutex::new(e2e)), opened: Arc::default() })
    }

    #[frb(sync, getter)]
    pub fn username(&self) -> String {
        self.client.session.username.clone()
    }

    #[frb(sync, getter)]
    pub fn server(&self) -> String {
        self.client.origin().to_owned()
    }

    fn account(&self, capability: &str) -> Result<String, KernoidError> {
        self.client
            .session
            .primary(capability)
            .map(str::to_owned)
            .ok_or_else(|| KernoidError { unauthorized: false, message: format!("the account has no {capability}") })
    }

    pub async fn mailboxes(&self) -> Result<Vec<Mailbox>, KernoidError> {
        let (client, account) = (self.client.clone(), self.account(client::MAIL)?);
        let boxes = run(async move { mail::mailboxes(&client, &account).await }).await?;
        Ok(boxes
            .into_iter()
            .map(|b| Mailbox {
                id: b.id,
                name: b.name,
                parent_id: b.parent_id,
                role: b.role,
                total: count(b.total_emails),
                unread: count(b.unread_emails),
            })
            .collect())
    }

    /// A page of a mailbox; encrypted emails with their summary decrypted, when the key is unlocked.
    pub async fn emails(&self, mailbox_id: String, position: u32, limit: u32) -> Result<EmailPage, KernoidError> {
        let (client, account, e2e) = (self.client.clone(), self.account(client::MAIL)?, self.e2e.clone());
        run(async move {
            let (emails, total) = mail::page(&client, &account, &mailbox_id, position, limit).await?;
            let e2e = e2e.lock().await;
            let emails = emails
                .into_iter()
                .map(|mut e| {
                    let opened = e2e.open_summary(&mut e);
                    EmailSummary {
                        seen: e.keywords.get("$seen").copied().unwrap_or(false),
                        flagged: e.keywords.get("$flagged").copied().unwrap_or(false),
                        encrypted: e.encrypted,
                        locked: e.encrypted && !opened,
                        id: e.id,
                        from: addresses(e.from),
                        subject: e.subject.unwrap_or_default(),
                        preview: if e.encrypted && !opened { String::new() } else { e.preview },
                        received_at: e.received_at,
                        has_attachment: e.has_attachment,
                    }
                })
                .collect();
            Ok(EmailPage { emails, total: count(total) })
        })
        .await
    }

    /// One message to read – an encrypted one decrypted here, with its signature checked.
    pub async fn email(&self, id: String) -> Result<Email, KernoidError> {
        let (client, account) = (self.client.clone(), self.account(client::MAIL)?);
        let (e2e, opened) = (self.e2e.clone(), self.opened.clone());
        run(async move {
            let email = mail::email(&client, &account, &id).await?;
            let encrypted = email.encrypted;
            let o = e2e.lock().await.open(&client, &account, email).await?;
            let e = o.email;
            let mut attachments: Vec<Attachment> = e
                .attachments
                .iter()
                .filter_map(|part| {
                    Some(Attachment {
                        blob_id: Some(part.blob_id.clone()?),
                        part_index: None,
                        name: part.name.clone().unwrap_or_else(|| "attachment".into()),
                        media_type: part.media_type.clone(),
                        size: count(part.size),
                    })
                })
                .collect();
            attachments.extend(o.parts.iter().map(|p| Attachment {
                blob_id: None,
                part_index: u32::try_from(p.index).ok(),
                name: p.name.clone().unwrap_or_else(|| "attachment".into()),
                media_type: p.media_type.clone(),
                size: count(p.size as u64),
            }));
            if let Some(inner) = o.inner {
                opened.lock().await.insert(e.id.clone(), inner);
            }
            Ok(Email {
                text: if o.locked { String::new() } else { e.text() },
                attachments,
                encrypted,
                locked: o.locked,
                signed: o.signed,
                verified: o.verified,
                id: e.id,
                from: addresses(e.from),
                to: addresses(e.to),
                cc: addresses(e.cc),
                subject: e.subject.unwrap_or_default(),
                received_at: e.received_at,
            })
        })
        .await
    }

    /// How a message to `to` would go out: end-to-end encrypted when the key is unlocked and every recipient has a
    /// key, else as before – with the reason.
    pub async fn send_plan(&self, to: Vec<String>) -> Result<SendPlan, KernoidError> {
        let (client, account, e2e) = (self.client.clone(), self.account(client::MAIL)?, self.e2e.clone());
        run(async move {
            let identity = mail::identity(&client, &account).await?;
            Ok(match e2e.lock().await.plan(&client, &account, &identity, &recipients(&to)).await {
                Plan::Sealed(_) => SendPlan { encrypted: true, reason: None },
                Plan::Plain(reason) => SendPlan { encrypted: false, reason: Some(reason) },
            })
        })
        .await
    }

    /// Sends a plain-text message – end-to-end encrypted and signed whenever it can be (RFC 0006, 5.3). `date` is the
    /// app's time for the `Date` field (RFC 5322). Returns whether it went encrypted.
    pub async fn send(
        &self,
        to: Vec<String>,
        subject: String,
        text: String,
        date: String,
    ) -> Result<bool, KernoidError> {
        let (client, account, e2e) = (self.client.clone(), self.account(client::MAIL)?, self.e2e.clone());
        run(async move {
            let to = recipients(&to);
            let identity = mail::identity(&client, &account).await?;
            let mut e2e = e2e.lock().await;
            match e2e.plan(&client, &account, &identity, &to).await {
                Plan::Sealed(keys) => {
                    let message = e2e::Outgoing { to: &to, subject: &subject, text: &text, date: &date };
                    e2e.send(&client, &account, &identity, message, &keys).await?;
                    Ok(true)
                }
                Plan::Plain(_) => {
                    mail::send(&client, &account, &to, &subject, &text).await?;
                    Ok(false)
                }
            }
        })
        .await
    }

    pub async fn key_status(&self) -> E2eStatus {
        status(&*self.e2e.lock().await)
    }

    /// Makes the account's key here and returns its recovery code – to be shown once.
    pub async fn make_key(&self) -> Result<String, KernoidError> {
        let (client, e2e) = (self.client.clone(), self.e2e.clone());
        run(async move { e2e.lock().await.setup(&client, kernoid_e2e::Kind::Pqc).await }).await
    }

    /// Unlocks the key with the recovery code; it stays in this process's memory only.
    pub async fn unlock_key(&self, code: String) -> Result<E2eStatus, KernoidError> {
        let (client, e2e) = (self.client.clone(), self.e2e.clone());
        run(async move {
            let mut e2e = e2e.lock().await;
            e2e.refresh(&client).await?;
            // Argon2 takes a moment; it does not hold the runtime's other work.
            tokio::task::block_in_place(|| e2e.unlock(&code))?;
            Ok(status(&e2e))
        })
        .await
    }

    /// Forgets the unlocked key and every message decrypted with it.
    pub async fn lock_key(&self) -> E2eStatus {
        let mut e2e = self.e2e.lock().await;
        e2e.lock();
        self.opened.lock().await.clear();
        status(&e2e)
    }

    #[frb(sync)]
    pub fn file_stores(&self) -> Vec<FileStore> {
        files::stores(&self.client)
            .into_iter()
            .map(|s| FileStore { account_id: s.account_id, name: s.name, is_personal: s.is_personal })
            .collect()
    }

    /// The nodes of a directory, or of the top of the store for `None`.
    pub async fn files(&self, account_id: String, parent_id: Option<String>) -> Result<Vec<FileNode>, KernoidError> {
        let client = self.client.clone();
        let nodes = run(async move { files::children(&client, &account_id, parent_id.as_deref()).await }).await?;
        Ok(nodes
            .into_iter()
            .map(|n| FileNode {
                is_directory: n.is_directory(),
                id: n.id,
                name: n.name,
                role: n.role,
                blob_id: n.blob_id,
                size: count(n.size),
                media_type: n.media_type,
                modified: n.modified,
            })
            .collect())
    }

    /// Downloads a blob of a store – or of the mail account, for `None` – into `directory` under `name` (made unique)
    /// and returns the path.
    pub async fn download(
        &self,
        account_id: Option<String>,
        blob_id: String,
        name: String,
        media_type: String,
        directory: String,
    ) -> Result<String, KernoidError> {
        let account_id = match account_id {
            Some(id) => id,
            None => self.account(client::MAIL)?,
        };
        let client = self.client.clone();
        run(async move {
            let bytes = client.download(&account_id, &blob_id, &name, &media_type).await?;
            write(&directory, &name, bytes).await
        })
        .await
    }

    /// Saves an attachment of a decrypted message – read from the message decrypted here, never from the server.
    pub async fn save_part(
        &self,
        email_id: String,
        part_index: u32,
        name: String,
        directory: String,
    ) -> Result<String, KernoidError> {
        let opened = self.opened.clone();
        run(async move {
            let inner = opened
                .lock()
                .await
                .get(&email_id)
                .cloned()
                .ok_or_else(|| client::Error::E2e("open the message again: the key was locked".into()))?;
            let bytes = kernoid_e2e::compose::part(&inner, part_index as usize)?;
            write(&directory, &name, bytes).await
        })
        .await
    }
}

async fn write(directory: &str, name: &str, bytes: Vec<u8>) -> client::Result<String> {
    let path = unique_path(std::path::Path::new(directory), name).await;
    tokio::fs::write(&path, bytes).await.map_err(|error| client::Error::Network(error.to_string()))?;
    Ok(path.to_string_lossy().into_owned())
}

/// `name` in `directory`, or `name (2)`, `name (3)` … if taken. Only the last part of `name` counts, so a name from
/// the server cannot leave the directory.
async fn unique_path(directory: &std::path::Path, name: &str) -> std::path::PathBuf {
    let name = std::path::Path::new(name).file_name().and_then(|n| n.to_str()).unwrap_or("download");
    let name = if name.is_empty() || name == ".." { "download" } else { name };
    let (stem, extension) = match name.rsplit_once('.') {
        Some((stem, extension)) if !stem.is_empty() => (stem.to_owned(), format!(".{extension}")),
        _ => (name.to_owned(), String::new()),
    };
    let mut path = directory.join(name);
    let mut n = 2;
    while tokio::fs::try_exists(&path).await.unwrap_or(false) {
        path = directory.join(format!("{stem} ({n}){extension}"));
        n += 1;
    }
    path
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn downloads_stay_in_their_directory_and_do_not_overwrite() {
        let dir = std::env::temp_dir().join(format!("kernoid-test-{}", std::process::id()));
        tokio::fs::create_dir_all(&dir).await.unwrap();
        assert_eq!(unique_path(&dir, "../../etc/passwd").await, dir.join("passwd"));
        tokio::fs::write(dir.join("a.txt"), b"x").await.unwrap();
        assert_eq!(unique_path(&dir, "a.txt").await, dir.join("a (2).txt"));
        assert_eq!(unique_path(&dir, "..").await, dir.join("download"));
        tokio::fs::remove_dir_all(&dir).await.unwrap();
    }

    #[test]
    fn only_addresses_are_recipients() {
        assert_eq!(recipients(&[" a@x ".into(), "".into(), "nope".into()]), vec!["a@x".to_owned()]);
    }
}
