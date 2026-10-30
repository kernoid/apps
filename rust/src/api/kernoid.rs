// SPDX-License-Identifier: MIT
//! The API of a logged-in account, as Dart sees it: plain records in, plain records out. Every call runs on one tokio
//! runtime of the process; Dart awaits it. Secret keys stay here – Dart sees whether a key is unlocked, never the key.

use std::collections::HashMap;
use std::future::Future;
use std::sync::{Arc, LazyLock};

use flutter_rust_bridge::frb;

use crate::frb_generated::StreamSink;
use tokio::sync::Mutex;

use kernoid_client::e2e::{E2e, Outgoing, Plan};
use kernoid_client::{self as client, Client, calendars, contacts, files, mail, reply};

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
    /// For a login with OpenID Connect: its tokens and the task that renews them before the access token expires.
    login: Option<Arc<Login>>,
}

/// A login with OpenID Connect while the app runs: the server, the tokens – renewed in the background –, and who
/// hears of each renewal (to keep the new refresh token).
struct Login {
    server: String,
    tokens: std::sync::Mutex<client::oidc::Tokens>,
    watcher: std::sync::Mutex<Option<StreamSink<String>>>,
    renewal: std::sync::Mutex<Option<tokio::task::JoinHandle<()>>>,
}

impl std::fmt::Debug for Login {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Login").field("server", &self.server).finish_non_exhaustive()
    }
}

/// What the app keeps in the system's key store to stay signed in: the server and the SDK's saved login (the refresh
/// token, never the access token).
#[derive(serde::Serialize, serde::Deserialize)]
struct Kept {
    server: String,
    login: client::oidc::Saved,
}

impl Login {
    fn kept(&self) -> Option<String> {
        let saved = self.tokens.lock().ok()?.saved()?;
        serde_json::to_string(&Kept { server: self.server.clone(), login: saved }).ok()
    }
}

impl Drop for Kernoid {
    fn drop(&mut self) {
        if let Some(login) = &self.login
            && let Ok(mut renewal) = login.renewal.lock()
            && let Some(task) = renewal.take()
        {
            task.abort();
        }
    }
}

/// A login with OpenID Connect begun: the URL to open in the system's browser, and what finishing it needs.
#[frb(opaque)]
#[derive(Debug)]
pub struct OidcLogin {
    login: client::oidc::Login,
    server: String,
}

impl OidcLogin {
    #[frb(sync, getter)]
    pub fn url(&self) -> String {
        self.login.url.clone()
    }
}

fn options() -> client::Options {
    client::Options { allow_http: false, user_agent: concat!("kernoid-app/", env!("CARGO_PKG_VERSION")).into() }
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

/// A message being written: to whom, about what, the text, the thread it answers, and what is attached – files of
/// another message (forwarding) and files of the device.
#[derive(Debug, Clone)]
pub struct EmailDraft {
    /// Addresses as people type them: `Name <a@b>, c@d`.
    pub to: String,
    pub cc: String,
    pub bcc: String,
    pub subject: String,
    pub text: String,
    pub in_reply_to: Vec<String>,
    pub references: Vec<String>,
    /// On the server already: the attachments of a message forwarded.
    pub attachments: Vec<DraftAttachment>,
    /// Paths of files on the device.
    pub files: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct DraftAttachment {
    pub blob_id: String,
    pub name: String,
    pub media_type: String,
    pub size: i64,
}

/// The words around a quote, in the user's language: `{date}` and `{who}` are filled in.
#[derive(Debug, Clone)]
pub struct ReplyPhrases {
    pub wrote: String,
    pub forwarded: String,
    pub from: String,
    pub date: String,
    pub subject: String,
    pub to: String,
    /// chrono's format of a date, e.g. `%d.%m.%Y %H:%M`.
    pub date_format: String,
}

/// A calendar the account reaches: its own or one shared with it.
#[derive(Debug, Clone)]
pub struct Calendar {
    pub id: String,
    pub account_id: String,
    pub name: String,
    /// Events can be made and changed in it.
    pub writable: bool,
    /// CSS colour, if the calendar has one.
    pub color: Option<String>,
    /// The owner's name, for a calendar shared with the account.
    pub shared_by: Option<String>,
}

#[derive(Debug, Clone)]
pub struct Participant {
    pub name: Option<String>,
    pub email: Option<String>,
    /// `needs-action`, `accepted`, `tentative` or `declined`.
    pub status: Option<String>,
}

/// An event, or one instance of a recurring one.
#[derive(Debug, Clone)]
pub struct Event {
    pub id: String,
    /// The event changes go to: for an instance, the recurring event it is of.
    pub event_id: String,
    pub account_id: String,
    pub calendar_ids: Vec<String>,
    pub title: String,
    /// RFC 3339, UTC; for an all-day event its first day, `YYYY-MM-DD`, in no time zone.
    pub start: Option<String>,
    /// RFC 3339, UTC; for an all-day event the day after its last, `YYYY-MM-DD`.
    pub end: Option<String>,
    pub all_day: bool,
    pub location: Option<String>,
    pub description: Option<String>,
    /// The organizer called it off.
    pub cancelled: bool,
    pub recurring: bool,
    pub participants: Vec<Participant>,
    /// The account is invited (not the organizer): its key among the participants and its answer so far.
    pub invitation_key: Option<String>,
    pub my_status: Option<String>,
    /// The account organizes it (or nobody does): it may change and delete it.
    pub editable: bool,
}

/// An event as the user writes it – to make one, or to change one (a recurring event as a whole).
#[derive(Debug, Clone)]
pub struct EventDraft {
    pub calendar_id: String,
    pub account_id: String,
    pub title: String,
    pub all_day: bool,
    /// Local times, `YYYY-MM-DDTHH:MM:SS`, in the device's time zone; for an all-day event the end is its last day.
    pub start: String,
    pub end: String,
    pub location: String,
    pub description: String,
    /// Addresses of the people invited – they get an invitation by email.
    pub participants: Vec<String>,
    /// `daily`, `weekly`, `monthly`, `yearly` or none.
    pub repeat: Option<String>,
}

/// A contact as the user writes it.
#[derive(Debug, Clone)]
pub struct ContactDraft {
    pub name: String,
    pub organization: String,
    pub emails: Vec<String>,
    pub phones: Vec<String>,
    pub note: String,
}

/// A contact card of one of the account's address books.
#[derive(Debug, Clone)]
pub struct Contact {
    pub id: String,
    pub account_id: String,
    pub name: String,
    pub organization: Option<String>,
    pub emails: Vec<String>,
    pub phones: Vec<String>,
    pub notes: Vec<String>,
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

/// The width HTML is set to as text: wide, so that the app wraps it, not html2text.
const TEXT_WIDTH: usize = 10_000;

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

/// A plain-text message to `to`.
fn draft(to: &[String], subject: &str, text: &str) -> mail::Draft {
    mail::Draft {
        from: None,
        to: recipients(to).into_iter().map(|email| mail::EmailAddress { name: None, email }).collect(),
        cc: Vec::new(),
        bcc: Vec::new(),
        subject: subject.to_owned(),
        body: text.to_owned(),
        in_reply_to: Vec::new(),
        references: Vec::new(),
        attachments: Vec::new(),
    }
}

/// The identity the account sends as: the one of its own address, else the first.
async fn identity(client: &Client, account: &str) -> client::Result<mail::Identity> {
    let identities = mail::identities(client, account).await?;
    let own = client.session.username.to_lowercase();
    identities
        .iter()
        .find(|identity| identity.email.to_lowercase() == own)
        .or(identities.first())
        .cloned()
        .ok_or_else(|| client::Error::Protocol("the account has no identity to send as".into()))
}

impl Kernoid {
    /// Logs in with an address and an app password (**OPEN**: OpenID Connect with PKCE, tokens in the system's
    /// key store – docs/plan.md, 7).
    pub async fn login(server: String, address: String, password: String) -> Result<Kernoid, KernoidError> {
        let (client, e2e) = run(async move {
            let url = client::session_url(Some(server.trim()), address.trim())?;
            let client = Client::connect(&url, address.trim(), &password, &options()).await?;
            // A server without the extension, or one that fails to answer it, is mail without end-to-end encryption.
            let e2e = E2e::load(&client).await.unwrap_or_default();
            Ok((client, e2e))
        })
        .await?;
        Ok(Kernoid { client, e2e: Arc::new(Mutex::new(e2e)), opened: Arc::default(), login: None })
    }

    /// Begins a login with OpenID Connect at `server`: kernoid's login page in the system's browser, with a passkey,
    /// a password or a second factor – whatever the account and its tenant use. `redirect_uri` is where the browser
    /// comes back: `dev.kernoid.kernoid:/oauth` on Apple's systems and Android, `http://127.0.0.1:<port>/oauth` on
    /// desktops.
    pub async fn begin_login(
        server: String,
        redirect_uri: String,
        address: Option<String>,
    ) -> Result<OidcLogin, KernoidError> {
        run(async move {
            let login = client::oidc::begin(server.trim(), &redirect_uri, address.as_deref(), &options()).await?;
            Ok(OidcLogin { login, server: server.trim().to_owned() })
        })
        .await
    }

    /// Finishes a login with the URL the browser came back to. The access token is renewed in the background before
    /// it expires; [`Kernoid::kept_login`] and [`Kernoid::watch_login`] give what to keep to stay signed in.
    pub async fn finish_login(login: &OidcLogin, callback: String) -> Result<Kernoid, KernoidError> {
        let (inner, server) = (login.login.clone(), login.server.clone());
        let tokens = run(async move { client::oidc::finish(&inner, &callback, &options()).await }).await?;
        Kernoid::signed_in(server, tokens).await
    }

    /// Signs in again with what [`Kernoid::kept_login`] gave – after a restart. The refresh token is used up by it:
    /// keep the new one ([`Kernoid::kept_login`]). A login that ended is `unauthorized`: forget what was kept.
    pub async fn resume(kept: String) -> Result<Kernoid, KernoidError> {
        let kept: Kept = serde_json::from_str(&kept)
            .map_err(|_| KernoidError { unauthorized: true, message: "the kept login is unreadable".into() })?;
        let saved = kept.login.tokens();
        let tokens = run(async move { client::oidc::refresh(&saved, &options()).await }).await?;
        Kernoid::signed_in(kept.server, tokens).await
    }

    async fn signed_in(server: String, tokens: client::oidc::Tokens) -> Result<Kernoid, KernoidError> {
        let (access, url_server) = (tokens.access_token.clone(), server.clone());
        let (client, e2e) = run(async move {
            let url = client::session_url(Some(&url_server), "")?;
            let client = Client::connect_with_token(&url, &access, &options()).await?;
            let e2e = E2e::load(&client).await.unwrap_or_default();
            Ok((client, e2e))
        })
        .await?;
        let login = Arc::new(Login {
            server,
            tokens: std::sync::Mutex::new(tokens),
            watcher: std::sync::Mutex::new(None),
            renewal: std::sync::Mutex::new(None),
        });
        let task = RUNTIME.spawn(renew(client.clone(), login.clone()));
        if let Ok(mut renewal) = login.renewal.lock() {
            *renewal = Some(task);
        }
        Ok(Kernoid { client, e2e: Arc::new(Mutex::new(e2e)), opened: Arc::default(), login: Some(login) })
    }

    /// What to keep in the system's key store to stay signed in – none for a login with an app password.
    #[frb(sync)]
    pub fn kept_login(&self) -> Option<String> {
        self.login.as_ref()?.kept()
    }

    /// Hears of every renewal with what to keep from then on: kernoid rotates refresh tokens, and one used before
    /// would end the login at the next start.
    pub fn watch_login(&self, sink: StreamSink<String>) {
        if let Some(login) = &self.login
            && let Ok(mut watcher) = login.watcher.lock()
        {
            *watcher = Some(sink);
        }
    }

    /// Signs out: a login with OpenID Connect is revoked at the server – the browser's session there stays.
    pub async fn sign_out(&self) -> Result<(), KernoidError> {
        let Some(login) = self.login.clone() else { return Ok(()) };
        if let Ok(mut renewal) = login.renewal.lock()
            && let Some(task) = renewal.take()
        {
            task.abort();
        }
        let tokens = login
            .tokens
            .lock()
            .map(|t| t.clone())
            .map_err(|_| KernoidError { unauthorized: false, message: "the login is broken".into() })?;
        run(async move { client::oidc::revoke(&tokens, &options()).await }).await
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
            let (emails, total) =
                mail::emails(&client, &account, Some(&mailbox_id), "", u64::from(position), u64::from(limit)).await?;
            let e2e = e2e.lock().await;
            let emails = emails
                .into_iter()
                .map(|mut e| {
                    e2e.open_summary(&mut e);
                    let opened = e.opened;
                    EmailSummary {
                        seen: e.is_seen(),
                        flagged: e.is_flagged(),
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
            let email = mail::full(&client, &account, &[id.as_str()])
                .await?
                .into_iter()
                .next()
                .ok_or_else(|| client::Error::Protocol("the email is gone".into()))?;
            let encrypted = email.summary.encrypted;
            let e = e2e.lock().await.open(&client, &account, email).await?;
            let sealed = e.sealed.unwrap_or_default();
            let attachments: Vec<Attachment> = e
                .attachments
                .iter()
                .filter(|part| part.blob_id.is_some() || part.inner.is_some())
                .map(|part| Attachment {
                    blob_id: part.blob_id.clone(),
                    part_index: part.inner.and_then(|index| u32::try_from(index).ok()),
                    name: part.name.clone().unwrap_or_else(|| "attachment".into()),
                    media_type: part.kind.clone(),
                    size: count(part.size),
                })
                .collect();
            if let Some(inner) = &e.inner {
                opened.lock().await.insert(e.summary.id.clone(), inner.0.clone());
            }
            Ok(Email {
                text: if sealed.locked { String::new() } else { e.text(TEXT_WIDTH) },
                attachments,
                encrypted,
                locked: sealed.locked,
                signed: sealed.signed,
                verified: sealed.verified,
                id: e.summary.id,
                from: addresses(e.summary.from),
                to: addresses(e.summary.to),
                cc: addresses(e.cc),
                subject: e.summary.subject.unwrap_or_default(),
                received_at: e.summary.received_at,
            })
        })
        .await
    }

    /// How a message to `to` (every recipient, Cc and Bcc as well) would go out: end-to-end encrypted when the key is
    /// unlocked and every recipient has a key, else as before – with the reason.
    pub async fn send_plan(&self, to: Vec<String>) -> Result<SendPlan, KernoidError> {
        let (client, account, e2e) = (self.client.clone(), self.account(client::MAIL)?, self.e2e.clone());
        run(async move {
            let identity = identity(&client, &account).await?;
            Ok(match e2e.lock().await.plan(&client, &account, &identity, &draft(&to, "", "")).await {
                Plan::Sealed(_) => SendPlan { encrypted: true, reason: None },
                Plan::Plain(reason) => SendPlan { encrypted: false, reason: Some(reason) },
            })
        })
        .await
    }

    /// A reply (`reply`, `replyAll`) to or a forward (`forward`) of an email: recipients, `Re:`/`Fwd:`, the text quoted
    /// – an encrypted email's decrypted text, when the key is unlocked –, the thread, the attachments forwarded.
    pub async fn reply_draft(
        &self,
        email_id: String,
        kind: String,
        phrases: ReplyPhrases,
    ) -> Result<EmailDraft, KernoidError> {
        let (client, account, e2e) = (self.client.clone(), self.account(client::MAIL)?, self.e2e.clone());
        run(async move {
            let kind = match kind.as_str() {
                "reply" => reply::Kind::Reply,
                "replyAll" => reply::Kind::ReplyAll,
                "forward" => reply::Kind::Forward,
                other => return Err(client::Error::Protocol(format!("not a kind of reply: {other}"))),
            };
            let email = mail::full(&client, &account, &[email_id.as_str()])
                .await?
                .into_iter()
                .next()
                .ok_or_else(|| client::Error::Protocol("the email is gone".into()))?;
            let email = e2e.lock().await.open(&client, &account, email).await?;
            let text = email.text(TEXT_WIDTH);
            let identities = mail::identities(&client, &account).await?;
            let phrases = reply::Phrases {
                wrote: phrases.wrote,
                forwarded: phrases.forwarded,
                from: phrases.from,
                date: phrases.date,
                subject: phrases.subject,
                to: phrases.to,
                date_format: phrases.date_format,
            };
            let draft = reply::start(kind, Some((&email, &text)), &identities, &phrases);
            Ok(EmailDraft {
                to: mail::format_addresses(&draft.to),
                cc: mail::format_addresses(&draft.cc),
                bcc: String::new(),
                subject: draft.subject,
                text: draft.body,
                in_reply_to: draft.in_reply_to,
                references: draft.references,
                attachments: draft
                    .attachments
                    .into_iter()
                    .map(|a| DraftAttachment {
                        blob_id: a.blob_id,
                        name: a.name,
                        media_type: a.kind,
                        size: count(a.size),
                    })
                    .collect(),
                files: Vec::new(),
            })
        })
        .await
    }

    /// Sends a message – end-to-end encrypted and signed whenever it can be (RFC 0006, 5.3): then the files go inside
    /// the encrypted message and nothing of them reaches the server as it is; else they are uploaded and attached.
    /// Returns whether it went encrypted.
    pub async fn send_draft(&self, draft: EmailDraft) -> Result<bool, KernoidError> {
        let (client, account, e2e) = (self.client.clone(), self.account(client::MAIL)?, self.e2e.clone());
        run(async move {
            let mut message = mail::Draft {
                from: None,
                to: mail::parse_addresses(&draft.to),
                cc: mail::parse_addresses(&draft.cc),
                bcc: mail::parse_addresses(&draft.bcc),
                subject: draft.subject.trim().to_owned(),
                body: draft.text,
                in_reply_to: draft.in_reply_to,
                references: draft.references,
                attachments: draft
                    .attachments
                    .into_iter()
                    .map(|a| mail::Attachment {
                        blob_id: a.blob_id,
                        kind: a.media_type,
                        name: a.name,
                        size: u64::try_from(a.size).unwrap_or_default(),
                    })
                    .collect(),
            };
            if message.to.is_empty() && message.cc.is_empty() && message.bcc.is_empty() {
                return Err(client::Error::Protocol("the message has no recipient".into()));
            }
            let files: Vec<std::path::PathBuf> = draft.files.iter().map(std::path::PathBuf::from).collect();
            let identity = identity(&client, &account).await?;
            let boxes = mail::mailboxes(&client, &account).await?;
            let mut e2e = e2e.lock().await;
            match e2e.plan(&client, &account, &identity, &message).await {
                Plan::Sealed(keys) => {
                    let outgoing = Outgoing {
                        account: &account,
                        identity: &identity,
                        draft: &message,
                        files: &files,
                        boxes: &boxes,
                    };
                    e2e.send(&client, outgoing, &keys).await?;
                    Ok(true)
                }
                Plan::Plain(_) => {
                    for path in &files {
                        message.attachments.push(mail::attach(&client, &account, path).await?);
                    }
                    mail::send(&client, &account, &identity, &message, &boxes).await?;
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
            .map(|s| FileStore { is_personal: s.kind == files::StoreKind::Own, account_id: s.id, name: s.name })
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
                size: count(n.size.unwrap_or_default()),
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
            let path = unique_path(std::path::Path::new(&directory), &name).await;
            let mut file = tokio::fs::File::create(&path).await?;
            let result = client.download(&account_id, &blob_id, &name, &media_type, &mut file, &mut |_, _| {}).await;
            if let Err(error) = result {
                drop(file);
                let _ = tokio::fs::remove_file(&path).await;
                return Err(error);
            }
            Ok(path.to_string_lossy().into_owned())
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
            let bytes = kernoid_e2e::compose::part(&inner, part_index as usize).map_err(client::Error::from)?;
            write(&directory, &name, bytes).await
        })
        .await
    }
}

/// Renews the access token a minute before it expires, as long as the refresh token is good, and tells the watcher
/// what to keep from then on.
async fn renew(client: Client, login: Arc<Login>) {
    loop {
        let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
        let Ok(tokens) = login.tokens.lock().map(|t| t.clone()) else { return };
        let wait = tokens.expires_at.saturating_sub(now).saturating_sub(60).max(10);
        tokio::time::sleep(std::time::Duration::from_secs(wait)).await;
        match client::oidc::refresh(&tokens, &options()).await {
            Ok(new) => {
                client.set_access_token(&new.access_token);
                if let Ok(mut kept) = login.tokens.lock() {
                    *kept = new;
                }
                if let (Some(text), Ok(watcher)) = (login.kept(), login.watcher.lock())
                    && let Some(sink) = watcher.as_ref()
                {
                    let _ = sink.add(text);
                }
            }
            // Signed out elsewhere, or the refresh token revoked: calls fail with "unauthorized", and the app asks again.
            Err(client::Error::Unauthorized) => return,
            // Offline for now: try again shortly.
            Err(_) => {
                if let Ok(mut kept) = login.tokens.lock() {
                    kept.expires_at = now + 120;
                }
            }
        }
    }
}

/// The addresses that are the user: the login and the addresses the account sends from.
async fn own_addresses(client: &Client) -> Vec<String> {
    let mut own = vec![client.session.username.clone()];
    if let Some(account) = client.session.primary(client::MAIL)
        && let Ok(identities) = mail::identities(client, account).await
    {
        own.extend(identities.into_iter().map(|identity| identity.email));
    }
    own
}

fn event(e: calendars::Event, own: &[String]) -> Event {
    let invitation = if e.organized_by(own) { None } else { e.me(own).map(|(key, p)| (key.to_owned(), p.clone())) };
    let rfc3339 = |time: chrono::DateTime<chrono::Utc>| time.to_rfc3339_opts(chrono::SecondsFormat::Secs, true);
    // An all-day event is days, not times: its local start date and as many days as its duration says.
    let (start, end) = if e.show_without_time {
        let first = e.start.as_deref().and_then(|s| chrono::NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok());
        let days = e.duration.as_deref().and_then(calendars::parse_duration).map_or(1, |s| (s / 86_400).max(1));
        (
            first.map(|d| d.to_string()),
            first.and_then(|d| d.checked_add_days(chrono::Days::new(days as u64))).map(|d| d.to_string()),
        )
    } else {
        (e.starts().map(rfc3339), e.ends().map(rfc3339))
    };
    Event {
        event_id: e.event_id().to_owned(),
        start,
        end,
        cancelled: e.is_cancelled(),
        location: e.location(),
        recurring: e.base_event_id.is_some() || e.recurrence_rule.is_some(),
        editable: e.organized_by(own),
        invitation_key: invitation.as_ref().map(|(key, _)| key.clone()),
        my_status: invitation.and_then(|(_, p)| p.participation_status),
        participants: e
            .participants
            .iter()
            .flat_map(|map| map.values())
            .map(|p| Participant {
                name: p.name.clone(),
                email: p.calendar_address.as_deref().map(|a| a.strip_prefix("mailto:").unwrap_or(a).to_owned()),
                status: p.participation_status.clone(),
            })
            .collect(),
        calendar_ids: e.calendar_ids.keys().cloned().collect(),
        title: e.title.unwrap_or_default(),
        all_day: e.show_without_time,
        description: e.description.filter(|d| !d.trim().is_empty()),
        account_id: e.account,
        id: e.id,
    }
}

impl Kernoid {
    /// The calendars of every account with calendars – the own ones first.
    pub async fn calendars(&self) -> Result<Vec<Calendar>, KernoidError> {
        let client = self.client.clone();
        let list = run(async move { calendars::calendars(&client).await }).await?;
        Ok(list
            .into_iter()
            .map(|c| Calendar {
                writable: c.writable(),
                id: c.id,
                account_id: c.account,
                name: c.name,
                color: c.color,
                shared_by: c.shared,
            })
            .collect())
    }

    /// The events of the visible calendars between `from` and `to` (RFC 3339) – recurring ones as their instances,
    /// by start.
    pub async fn events(&self, from: String, to: String) -> Result<Vec<Event>, KernoidError> {
        let client = self.client.clone();
        run(async move {
            let parse = |text: &str| {
                chrono::DateTime::parse_from_rfc3339(text)
                    .map(|time| time.with_timezone(&chrono::Utc))
                    .map_err(|_| client::Error::Protocol(format!("not a time: {text}")))
            };
            let (after, before) = (parse(&from)?, parse(&to)?);
            let list = calendars::calendars(&client).await?;
            let mut found = calendars::instances(&client, &list, after, before).await?;
            found.sort_by_key(|e| e.starts());
            let own = own_addresses(&client).await;
            Ok(found.into_iter().map(|e| event(e, &own)).collect())
        })
        .await
    }

    /// Answers an invitation: `accepted`, `tentative` or `declined`; the organizer hears of it by email.
    pub async fn answer_event(
        &self,
        account_id: String,
        event_id: String,
        invitation_key: String,
        status: String,
    ) -> Result<(), KernoidError> {
        let client = self.client.clone();
        run(async move { calendars::answer(&client, &account_id, &event_id, &invitation_key, &status).await }).await
    }

    /// An event as a draft, to change it: for an instance of a recurring event, the event as a whole.
    pub async fn event_draft(&self, account_id: String, event_id: String) -> Result<EventDraft, KernoidError> {
        let client = self.client.clone();
        run(async move {
            let own = own_addresses(&client).await;
            let event = calendars::event(&client, &account_id, &event_id)
                .await?
                .ok_or_else(|| client::Error::Protocol("the event is gone".into()))?;
            let form = calendars::EventForm::of(&event, &own)
                .ok_or_else(|| client::Error::Protocol("the event has no start".into()))?;
            let local = |time: chrono::NaiveDateTime| time.format("%Y-%m-%dT%H:%M:%S").to_string();
            Ok(EventDraft {
                calendar_id: event.calendar_ids.keys().next().cloned().unwrap_or_default(),
                account_id,
                title: form.title,
                all_day: form.all_day,
                start: local(form.start),
                end: local(form.end),
                location: form.location,
                description: form.description,
                participants: form.participants,
                repeat: form.repeat,
            })
        })
        .await
    }

    /// Makes an event, or – with `event_id` – changes one; the people invited hear of it by email. The time zone is the
    /// device's.
    pub async fn save_event(&self, event_id: Option<String>, draft: EventDraft) -> Result<(), KernoidError> {
        let client = self.client.clone();
        run(async move {
            let calendar = calendars::calendars(&client)
                .await?
                .into_iter()
                .find(|c| c.id == draft.calendar_id && c.account == draft.account_id)
                .ok_or_else(|| client::Error::Protocol("the calendar is gone".into()))?;
            let time = |text: &str| {
                chrono::NaiveDateTime::parse_from_str(text, "%Y-%m-%dT%H:%M:%S")
                    .map_err(|_| client::Error::Protocol(format!("not a time: {text}")))
            };
            let own = own_addresses(&client).await;
            // A change keeps the answers given, as long as the time stays (RFC 5546, 2.1.4).
            let earlier = match &event_id {
                Some(id) => calendars::event(&client, &calendar.account, id)
                    .await?
                    .and_then(|event| calendars::EventForm::of(&event, &own)),
                None => None,
            };
            let form = calendars::EventForm {
                title: draft.title.trim().to_owned(),
                all_day: draft.all_day,
                start: time(&draft.start)?,
                end: time(&draft.end)?,
                time_zone: if draft.all_day { None } else { calendars::local_time_zone() },
                location: draft.location.trim().to_owned(),
                description: draft.description,
                participants: draft
                    .participants
                    .iter()
                    .map(|a| a.trim().to_owned())
                    .filter(|a| a.contains('@'))
                    .collect(),
                repeat: draft.repeat.filter(|r| !r.is_empty()),
                answers: earlier.as_ref().map(|form| form.answers.clone()).unwrap_or_default(),
                was: earlier.map(|form| (form.start, form.end, form.all_day)),
            };
            if form.end < form.start {
                return Err(client::Error::Protocol("the end is before the start".into()));
            }
            let organizer = client.session.username.clone();
            match event_id {
                Some(id) => calendars::update(&client, &calendar, &id, &form, &organizer).await,
                None => calendars::create(&client, &calendar, &form, &organizer).await.map(|_| ()),
            }
        })
        .await
    }

    /// Deletes an event – a recurring one as a whole; the people invited hear of it by email.
    pub async fn delete_event(&self, account_id: String, event_id: String) -> Result<(), KernoidError> {
        let client = self.client.clone();
        run(async move { calendars::destroy(&client, &account_id, &event_id).await }).await
    }

    /// Makes a contact in the account's default address book, or – with `account_id` and `contact_id` – changes one.
    /// Addresses and numbers that stay keep their labels (work, home, mobile …).
    pub async fn save_contact(
        &self,
        account_id: Option<String>,
        contact_id: Option<String>,
        draft: ContactDraft,
    ) -> Result<(), KernoidError> {
        let client = self.client.clone();
        run(async move {
            let books = contacts::address_books(&client).await?;
            let earlier = match (&account_id, &contact_id) {
                (Some(account), Some(id)) => contacts::cards(&client, "")
                    .await?
                    .into_iter()
                    .find(|c| &c.account == account && &c.id == id)
                    .map(|card| (contacts::CardForm::of(&card), card.address_book_ids.keys().next().cloned())),
                _ => None,
            };
            let labelled = |values: &[String], before: Option<&Vec<contacts::Labelled>>| -> Vec<contacts::Labelled> {
                values
                    .iter()
                    .map(|v| v.trim())
                    .filter(|v| !v.is_empty())
                    .map(|value| {
                        let labels = before
                            .and_then(|list| list.iter().find(|l| l.value == value))
                            .map(|l| l.labels.clone())
                            .unwrap_or_default();
                        contacts::Labelled { value: value.to_owned(), labels }
                    })
                    .collect()
            };
            let form = contacts::CardForm {
                name: draft.name.trim().to_owned(),
                emails: labelled(&draft.emails, earlier.as_ref().map(|(form, _)| &form.emails)),
                phones: labelled(&draft.phones, earlier.as_ref().map(|(form, _)| &form.phones)),
                organizations: Some(draft.organization.trim().to_owned())
                    .filter(|o| !o.is_empty())
                    .into_iter()
                    .collect(),
                note: draft.note.trim().to_owned(),
            };
            match (account_id, contact_id, earlier) {
                (Some(account), Some(id), Some((_, book))) => {
                    let book = books
                        .iter()
                        .find(|b| b.account == account && Some(&b.id) == book.as_ref())
                        .ok_or_else(|| client::Error::Protocol("the address book is gone".into()))?;
                    contacts::update(&client, book, &id, &form).await
                }
                (Some(_), Some(_), None) => Err(client::Error::Protocol("the contact is gone".into())),
                _ => {
                    let own = client.session.primary(client::CONTACTS);
                    let book = books
                        .iter()
                        .filter(|b| b.writable())
                        .find(|b| Some(b.account.as_str()) == own && b.is_default)
                        .or_else(|| books.iter().find(|b| b.writable()))
                        .ok_or_else(|| client::Error::Protocol("there is no address book to write to".into()))?;
                    contacts::create(&client, book, &form).await
                }
            }
        })
        .await
    }

    pub async fn delete_contact(&self, account_id: String, contact_id: String) -> Result<(), KernoidError> {
        let client = self.client.clone();
        run(async move { contacts::destroy(&client, &account_id, &contact_id).await }).await
    }

    /// The contacts of every address book, `search` searching them; by name.
    pub async fn contacts(&self, search: String) -> Result<Vec<Contact>, KernoidError> {
        let client = self.client.clone();
        let cards = run(async move { contacts::cards(&client, search.trim()).await }).await?;
        Ok(cards
            .into_iter()
            .map(|c| Contact {
                name: c.full_name(),
                organization: c.organization(),
                emails: c.emails(),
                phones: c.phones(),
                notes: c.notes().into_iter().filter(|n| !n.trim().is_empty()).collect(),
                account_id: c.account,
                id: c.id,
            })
            .collect())
    }
}

async fn write(directory: &str, name: &str, bytes: Vec<u8>) -> client::Result<String> {
    let path = unique_path(std::path::Path::new(directory), name).await;
    tokio::fs::write(&path, bytes).await?;
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
