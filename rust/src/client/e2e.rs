// SPDX-License-Identifier: MIT
//! End-to-end encrypted mail (RFC 0006, 4–5) over kernoid's extension `https://kernoid.dev/jmap/openpgp`, after the
//! terminal app's `jmap/e2e.rs` and the web app's key setup: the account's key made here with a recovery code (and
//! the tenant's copy when its policy asks for one); the protected copies of secret keys unlocked here and kept only in
//! memory; the public keys of others looked up once per run; summaries of encrypted emails for lists; encrypted emails
//! downloaded, decrypted and read here – never through the server's `Email/parse` –; and messages built, encrypted and
//! signed here, imported into Drafts with their summary and submitted with an envelope, so that the server sees
//! neither text nor attachments. The cryptography is all `kernoid-e2e`'s.

use std::collections::BTreeMap;

use base64::{Engine, engine::general_purpose::STANDARD};
use std::time::{SystemTime, UNIX_EPOCH};

use kernoid_e2e::{
    Kind, PublicKey, SecretKey,
    compose::{self, Mailbox as Address},
    keys::{normalize_recovery_code, recovery_code},
    mime,
};
use serde::Deserialize;
use serde_json::{Value, json};

use super::mail::{self, Email, EmailAddress, Identity, Summary};
use super::{Client, Error, MAIL, Result, SUBMISSION, set_error};

pub const OPENPGP: &str = "https://kernoid.dev/jmap/openpgp";

/// A protected copy of a secret key (RFC 0006, 4.2), base64.
#[derive(Debug, Clone, Deserialize)]
pub struct KeyCopy {
    #[serde(default)]
    pub protected: String,
}

/// One of the account's keys (`OpenPgpKey/get`).
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Key {
    /// The fingerprint.
    pub id: String,
    #[serde(default)]
    pub kind: String,
    #[serde(default)]
    pub retired: Option<String>,
    #[serde(default)]
    pub copies: BTreeMap<String, KeyCopy>,
}

/// The account's and its tenant's settings (`E2eSettings/get`, RFC 0006, 8).
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    /// Mail is encrypted on arrival (5.1).
    #[serde(default)]
    pub mail: bool,
    #[serde(default)]
    pub policy: Policy,
    #[serde(default)]
    pub recovery_key: Option<RecoveryKey>,
}

#[derive(Debug, Clone, Default, Deserialize)]
pub struct Policy {
    /// `allowed`, `required` or `forbidden`.
    #[serde(default)]
    pub mail: String,
    /// The tenant can recover the account's keys (8.2).
    #[serde(default)]
    pub recovery: bool,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecoveryKey {
    #[serde(default)]
    pub public_key: String,
}

/// How a message goes out.
#[derive(Debug, Clone)]
pub enum Plan {
    /// End-to-end encrypted to these keys – every recipient's and the sender's own – and signed.
    Sealed(Vec<PublicKey>),
    /// As before, with the reason it is not encrypted.
    Plain(String),
}

/// An encrypted email after reading: decrypted, or locked with why.
#[derive(Debug, Clone)]
pub struct Opened {
    pub email: Email,
    /// Not decrypted: the key is locked, or the email is encrypted to a key not unlocked here.
    pub locked: bool,
    pub signed: bool,
    /// The signature is valid and by a key of the sender.
    pub verified: bool,
    /// Attachments of the decrypted message: name, type, size and index in `inner`.
    pub parts: Vec<compose::Part>,
    /// The decrypted message, for saving its attachments.
    pub inner: Option<Vec<u8>>,
}

/// What this run knows of end-to-end encryption: whether the server has it, the account's keys and settings, the
/// keys unlocked here, and the public keys of others looked up so far.
#[derive(Default)]
pub struct E2e {
    pub available: bool,
    pub keys: Vec<Key>,
    pub settings: Settings,
    current: Option<SecretKey>,
    /// Every key unlocked: the one in use and retired ones, for mail encrypted to them before.
    unlocked: Vec<SecretKey>,
    /// Public keys by address (lower case); an address without any has none.
    known: BTreeMap<String, Vec<PublicKey>>,
}

impl std::fmt::Debug for E2e {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("E2e")
            .field("available", &self.available)
            .field("keys", &self.keys.len())
            .field("unlocked", &self.current.is_some())
            .finish_non_exhaustive()
    }
}

fn base64(bytes: &[u8]) -> String {
    STANDARD.encode(bytes)
}

fn unbase64(text: &str) -> Result<Vec<u8>> {
    STANDARD.decode(text.trim()).map_err(|_| Error::Protocol("not base64".into()))
}

fn list<T: serde::de::DeserializeOwned>(result: Option<&Value>) -> Result<Vec<T>> {
    serde_json::from_value(result.and_then(|r| r.get("list")).cloned().unwrap_or(json!([])))
        .map_err(|error| Error::Protocol(error.to_string()))
}

impl E2e {
    /// Reads the account's keys and settings – nothing if the server has no end-to-end extension.
    pub async fn load(client: &Client) -> Result<E2e> {
        let Some(account) = client.session.primary(OPENPGP) else { return Ok(E2e::default()) };
        let responses = client
            .request(
                &[OPENPGP],
                vec![
                    ("OpenPgpKey/get", json!({ "accountId": account }), "k"),
                    ("E2eSettings/get", json!({ "accountId": account }), "s"),
                ],
            )
            .await?;
        let settings = list::<Settings>(responses.get("s"))?.into_iter().next().unwrap_or_default();
        Ok(E2e { available: true, keys: list(responses.get("k"))?, settings, ..E2e::default() })
    }

    /// Reads keys and settings again, keeping what is unlocked.
    pub async fn refresh(&mut self, client: &Client) -> Result<()> {
        let fresh = E2e::load(client).await?;
        self.available = fresh.available;
        self.keys = fresh.keys;
        self.settings = fresh.settings;
        Ok(())
    }

    /// The key in use (not retired).
    pub fn current_key(&self) -> Option<&Key> {
        self.keys.iter().find(|key| key.retired.is_none())
    }

    pub fn is_unlocked(&self) -> bool {
        self.current.is_some()
    }

    /// Makes the account's key here (RFC 0006, 4.2) for the addresses it sends from, stores it with a copy protected by
    /// a new recovery code – and the tenant's copy when its policy recovers keys (8.2) – and keeps it unlocked. Returns
    /// the recovery code, to be shown once.
    pub async fn setup(&mut self, client: &Client, kind: Kind) -> Result<String> {
        if !self.available {
            return Err(Error::E2e("the server has no end-to-end encryption".into()));
        }
        if self.current_key().is_some() {
            return Err(Error::E2e("the account has a key already".into()));
        }
        let account = client.session.primary(OPENPGP).unwrap_or_default().to_owned();
        let mail_account = client.session.primary(MAIL).unwrap_or(&account).to_owned();
        let mut addresses: Vec<String> = match client
            .request(&[MAIL, SUBMISSION], vec![("Identity/get", json!({ "accountId": mail_account }), "i")])
            .await
        {
            Ok(responses) => {
                list::<Identity>(responses.get("i"))?.into_iter().map(|i| i.email.to_lowercase()).collect()
            }
            Err(_) => Vec::new(),
        };
        addresses.push(client.session.username.to_lowercase());
        addresses.sort();
        addresses.dedup();
        addresses.retain(|a| a.contains('@'));
        // Making a post-quantum key takes a moment; it does not hold the runtime's other work.
        let secret = tokio::task::spawn_blocking(move || {
            let names: Vec<&str> = addresses.iter().map(String::as_str).collect();
            SecretKey::generate(kind, &names)
        })
        .await
        .map_err(|error| Error::E2e(error.to_string()))??;
        let code = recovery_code();
        let mut copies = json!({ "recovery": { "protected": base64(&secret.protect(&normalize_recovery_code(&code))?), "salt": null } });
        if self.settings.policy.recovery
            && let Some(recovery) = &self.settings.recovery_key
        {
            let tenant = PublicKey::parse(&unbase64(&recovery.public_key)?)?;
            let armored = secret.export()?;
            let sealed = kernoid_e2e::message::encrypt(armored.as_bytes(), &[&tenant], None, false)?;
            copies["tenant"] = json!({ "protected": base64(&sealed), "salt": null });
        }
        let public = secret.public().to_bytes()?;
        let responses = client
            .request(
                &[OPENPGP],
                vec![(
                    "OpenPgpKey/set",
                    json!({ "accountId": account, "create": { "key": { "publicKey": base64(&public), "copies": copies } } }),
                    "s",
                )],
            )
            .await?;
        set_error(responses.get("s").unwrap_or(&Value::Null))?;
        self.refresh(client).await?;
        self.unlocked = vec![secret.clone()];
        self.current = Some(secret);
        Ok(code)
    }

    /// Unlocks the key in use with the recovery code (as typed: separators and case do not matter) – and retired keys
    /// whose copy the same code opens. They stay in this process's memory only.
    pub fn unlock(&mut self, code: &str) -> Result<()> {
        let key = self.current_key().ok_or_else(|| Error::E2e("this account has no key".into()))?;
        let copy =
            key.copies.get("recovery").ok_or_else(|| Error::E2e("the key has no copy for a recovery code".into()))?;
        let code = normalize_recovery_code(code);
        let current = SecretKey::unlock(&unbase64(&copy.protected)?, &code)?;
        if !current.fingerprint().eq_ignore_ascii_case(&key.id) {
            return Err(Error::E2e("the copy is not of the key in use".into()));
        }
        let mut unlocked = vec![current.clone()];
        for key in self.keys.iter().filter(|key| key.retired.is_some()) {
            let Some(copy) = key.copies.get("recovery") else { continue };
            if let Ok(secret) = unbase64(&copy.protected).and_then(|p| Ok(SecretKey::unlock(&p, &code)?)) {
                unlocked.push(secret);
            }
        }
        self.unlocked = unlocked;
        self.current = Some(current);
        Ok(())
    }

    /// Forgets the unlocked keys.
    pub fn lock(&mut self) {
        self.current = None;
        self.unlocked.clear();
    }

    /// The public keys of `addresses` (asked once per run).
    pub async fn lookup(&mut self, client: &Client, addresses: &[String]) -> Result<BTreeMap<String, Vec<PublicKey>>> {
        let mut wanted: Vec<String> = addresses.iter().map(|a| a.to_lowercase()).collect();
        wanted.sort();
        wanted.dedup();
        wanted.retain(|address| !self.known.contains_key(address));
        if !wanted.is_empty() {
            #[derive(Deserialize)]
            #[serde(rename_all = "camelCase")]
            struct Found {
                public_key: String,
            }
            #[derive(Deserialize)]
            struct Entry {
                email: String,
                #[serde(default)]
                keys: Vec<Found>,
            }
            let account = client.session.primary(OPENPGP).unwrap_or_default().to_owned();
            let responses = client
                .request(
                    &[OPENPGP],
                    vec![("OpenPgpKey/lookup", json!({ "accountId": account, "emails": wanted }), "l")],
                )
                .await?;
            for entry in list::<Entry>(responses.get("l"))? {
                // Keys this app cannot use are left out.
                let keys = entry
                    .keys
                    .iter()
                    .filter_map(|key| PublicKey::parse(&unbase64(&key.public_key).ok()?).ok())
                    .collect();
                self.known.insert(entry.email.to_lowercase(), keys);
            }
            for address in wanted {
                self.known.entry(address).or_default();
            }
        }
        Ok(addresses
            .iter()
            .map(|a| (a.to_lowercase(), self.known.get(&a.to_lowercase()).cloned().unwrap_or_default()))
            .collect())
    }

    fn secrets(&self) -> Vec<&SecretKey> {
        self.unlocked.iter().collect()
    }

    /// Subject, preview and attachments of an encrypted email from its summary, once the key is unlocked – `None` if it
    /// stays locked.
    pub fn open_summary(&self, email: &mut Summary) -> bool {
        if !email.encrypted {
            return true;
        }
        if self.unlocked.is_empty() {
            return false;
        }
        let Some(sealed) = email.encrypted_summary.as_deref().and_then(|s| unbase64(s).ok()) else { return false };
        match mime::decrypt_summary(&sealed, &self.secrets()) {
            Ok(summary) => {
                email.subject = summary.subject;
                email.preview = summary.preview;
                email.has_attachment = summary.has_attachment;
                true
            }
            Err(_) => false,
        }
    }

    /// An email to read: an encrypted one downloaded, decrypted and read into its parts here, its signature checked
    /// against its sender's keys – locked if the key is not unlocked or does not open it. Other emails as they are.
    pub async fn open(&mut self, client: &Client, account: &str, mut email: Email) -> Result<Opened> {
        let mut opened = Opened {
            email: email.clone(),
            locked: false,
            signed: false,
            verified: false,
            parts: Vec::new(),
            inner: None,
        };
        if !email.encrypted {
            return Ok(opened);
        }
        opened.locked = true;
        opened.email.text_body.clear();
        opened.email.html_body.clear();
        opened.email.attachments.clear();
        opened.email.body_values.clear();
        if let Some(sealed) = email.encrypted_summary.as_deref().and_then(|s| unbase64(s).ok())
            && let Ok(summary) = mime::decrypt_summary(&sealed, &self.secrets())
        {
            opened.email.subject = summary.subject;
            opened.email.preview = summary.preview;
        }
        let Some(blob) = email.blob_id.clone().filter(|_| self.is_unlocked()) else { return Ok(opened) };
        let raw = client.download(account, &blob, "message.eml", "message/rfc822").await?;
        let senders: Vec<String> = email.from.iter().flatten().map(|a| a.email.clone()).collect();
        let senders: Vec<PublicKey> = if senders.is_empty() {
            Vec::new()
        } else {
            self.lookup(client, &senders).await.map(|found| found.into_values().flatten().collect()).unwrap_or_default()
        };
        let senders: Vec<&PublicKey> = senders.iter().collect();
        let Ok(decrypted) = mime::decrypt_message(&raw, &self.secrets(), &senders) else { return Ok(opened) };
        let Ok(parsed) = compose::parse(&decrypted.data) else { return Ok(opened) };
        let addresses = |list: Vec<Address>| -> Option<Vec<EmailAddress>> {
            Some(list.into_iter().map(|a| EmailAddress { name: a.name, email: a.email }).collect())
        };
        email.subject = parsed.subject;
        if !parsed.from.is_empty() {
            email.from = addresses(parsed.from);
        }
        if !parsed.to.is_empty() {
            email.to = addresses(parsed.to);
        }
        email.cc = addresses(parsed.cc);
        email.text_body.clear();
        email.html_body.clear();
        email.attachments.clear();
        email.body_values.clear();
        let part = |id: &str, kind: &str| mail::BodyPart {
            part_id: Some(id.to_owned()),
            blob_id: None,
            name: None,
            media_type: kind.to_owned(),
            size: 0,
        };
        if let Some(text) = parsed.text {
            email.text_body.push(part("text", "text/plain"));
            email.body_values.insert("text".into(), mail::BodyValue { value: text });
        }
        if let Some(html) = parsed.html {
            email.html_body.push(part("html", "text/html"));
            email.body_values.insert("html".into(), mail::BodyValue { value: html });
        }
        Ok(Opened {
            email,
            locked: false,
            signed: decrypted.signed,
            verified: decrypted.verified_by.is_some(),
            parts: parsed.attachments.into_iter().filter(|p| !p.inline || p.name.is_some()).collect(),
            inner: Some(decrypted.data),
        })
    }

    /// The key a message from `identity` in `account` is encrypted and signed with: the unlocked key in use, if the
    /// account is the user's own and the key has the address – else why not.
    fn own_key(&self, client: &Client, account: &str, identity: &Identity) -> std::result::Result<&SecretKey, String> {
        if !self.available {
            return Err("the server has no end-to-end encryption".into());
        }
        let Some(current) = &self.current else {
            return Err(if self.current_key().is_some() {
                "your key is locked".into()
            } else {
                "your account has no key yet".into()
            });
        };
        if client.session.primary(MAIL) != Some(account) {
            return Err("it is not sent from your own account".into());
        }
        if !current.public().addresses().iter().any(|a| a.eq_ignore_ascii_case(&identity.email)) {
            return Err(format!("your key is not for {}", identity.email));
        }
        Ok(current)
    }

    /// How a message goes out: end-to-end encrypted if the key is unlocked, it is sent from the user's own account as
    /// an address of the key, and every recipient has a key (RFC 0006, 5.3) – else as before.
    pub async fn plan(&mut self, client: &Client, account: &str, identity: &Identity, to: &[String]) -> Plan {
        let own = match self.own_key(client, account, identity) {
            Ok(key) => key.public(),
            Err(reason) => return Plan::Plain(reason),
        };
        if to.is_empty() {
            return Plan::Plain("it has no recipients".into());
        }
        let found = match self.lookup(client, to).await {
            Ok(found) => found,
            Err(error) => return Plan::Plain(format!("the keys could not be looked up: {error}")),
        };
        let mut keys = Vec::new();
        for (address, list) in found {
            let usable: Vec<PublicKey> = list.into_iter().filter(PublicKey::can_encrypt).collect();
            if usable.is_empty() {
                return Plan::Plain(format!("{address} has no key"));
            }
            keys.extend(usable);
        }
        keys.push(own);
        Plan::Sealed(keys)
    }

    /// Sends end-to-end encrypted to `recipients` (from `plan`): the message built, encrypted and signed here, uploaded
    /// as it is, imported into Drafts with its summary encrypted to the sender, submitted with an envelope, and moved
    /// to Sent once sent.
    pub async fn send(
        &self,
        client: &Client,
        account: &str,
        identity: &Identity,
        message: Outgoing<'_>,
        recipients: &[PublicKey],
    ) -> Result<()> {
        let own = self.own_key(client, account, identity).map_err(Error::E2e)?;
        let boxes = mail::mailboxes(client, account).await?;
        let by_role = |role: &str| boxes.iter().find(|b| b.role.as_deref() == Some(role)).map(|b| b.id.clone());
        let drafts = by_role("drafts").ok_or_else(|| Error::Protocol("there is no Drafts mailbox".into()))?;
        let domain = identity.email.rsplit_once('@').map(|(_, d)| d).unwrap_or("localhost");
        let draft = compose::Draft {
            from: Some(Address {
                name: (!identity.name.is_empty()).then(|| identity.name.clone()),
                email: identity.email.clone(),
            }),
            to: message.to.iter().map(|a| Address { name: None, email: a.clone() }).collect(),
            subject: message.subject.to_owned(),
            message_id: format!("{}@{domain}", random_id()),
            date: message.date.to_owned(),
            text: message.text.to_owned(),
            ..compose::Draft::default()
        };
        let raw = compose::build(&draft)?;
        let recipients: Vec<&PublicKey> = recipients.iter().collect();
        let encrypted = mime::encrypt_message(&raw, &recipients, Some(own))?;
        let summary = mime::encrypted_summary(&raw, &[&own.public()])?;
        let blob = client.upload(account, "message/rfc822", encrypted).await?;
        let mut update = json!({ "keywords/$draft": null });
        if let Some(sent) = by_role("sent") {
            update["mailboxIds"] = json!({ sent: true });
        }
        let rcpt: Vec<Value> = message.to.iter().map(|a| json!({ "email": a, "parameters": null })).collect();
        let responses = client
            .request(
                &[MAIL, SUBMISSION, OPENPGP],
                vec![
                    (
                        "Email/import",
                        json!({ "accountId": account, "emails": { "draft": {
                            "blobId": blob, "mailboxIds": { drafts: true },
                            "keywords": { "$draft": true, "$seen": true },
                            "kernoid:encryptedSummary": base64(&summary),
                        } } }),
                        "e",
                    ),
                    (
                        "EmailSubmission/set",
                        json!({
                            "accountId": account,
                            "create": { "send": {
                                "identityId": identity.id, "emailId": "#draft",
                                "envelope": { "mailFrom": { "email": identity.email, "parameters": null }, "rcptTo": rcpt },
                            } },
                            "onSuccessUpdateEmail": { "#send": update },
                        }),
                        "s",
                    ),
                ],
            )
            .await?;
        for (_, result, _) in &responses.0 {
            set_error(result)?;
        }
        Ok(())
    }
}

/// A plain-text message to send encrypted.
#[derive(Debug, Clone, Copy)]
pub struct Outgoing<'a> {
    pub to: &'a [String],
    pub subject: &'a str,
    pub text: &'a str,
    /// `Date`, RFC 5322 – the app knows the time and its zone.
    pub date: &'a str,
}

/// 128 bits for a `Message-ID` – unique, not secret: the standard library's per-process random hash keys over the
/// time.
fn random_id() -> String {
    use std::hash::{BuildHasher, Hasher};
    let state = std::collections::hash_map::RandomState::new();
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_nanos()).unwrap_or_default();
    let half = |n: u8| {
        let mut hasher = state.build_hasher();
        hasher.write_u128(now);
        hasher.write_u32(std::process::id());
        hasher.write_u8(n);
        hasher.finish()
    };
    format!("{:016x}{:016x}", half(0), half(1))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn base64_goes_both_ways() {
        for bytes in [&b""[..], b"f", b"fo", b"foo", b"foob", b"fooba", b"foobar", &[0, 255, 128, 7]] {
            assert_eq!(unbase64(&base64(bytes)).unwrap(), bytes);
        }
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert!(unbase64("Zm9v!").is_err());
    }
}
