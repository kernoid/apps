// SPDX-License-Identifier: MIT
//! JMAP Mail (RFC 8621): mailboxes, a page of a mailbox, one message, sending.

use serde::Deserialize;
use serde_json::{Value, json};

use super::{Client, Error, MAIL, Result, SUBMISSION, e2e::OPENPGP, ids_of, list, set_error};

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Mailbox {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub parent_id: Option<String>,
    #[serde(default)]
    pub role: Option<String>,
    #[serde(default)]
    pub sort_order: u32,
    #[serde(default)]
    pub total_emails: u64,
    #[serde(default)]
    pub unread_emails: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EmailAddress {
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default)]
    pub email: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Summary {
    pub id: String,
    #[serde(default)]
    pub from: Option<Vec<EmailAddress>>,
    #[serde(default)]
    pub subject: Option<String>,
    #[serde(default)]
    pub preview: String,
    #[serde(default)]
    pub received_at: String,
    #[serde(default)]
    pub keywords: std::collections::BTreeMap<String, bool>,
    #[serde(default)]
    pub has_attachment: bool,
    /// End-to-end encrypted (RFC 0006, 5): subject and preview are the summary's, once it is decrypted here.
    #[serde(default, rename = "kernoid:encrypted")]
    pub encrypted: bool,
    /// The summary, encrypted to the account's key (base64).
    #[serde(default, rename = "kernoid:encryptedSummary")]
    pub encrypted_summary: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BodyPart {
    #[serde(default)]
    pub part_id: Option<String>,
    #[serde(default)]
    pub blob_id: Option<String>,
    #[serde(default)]
    pub name: Option<String>,
    #[serde(default, rename = "type")]
    pub media_type: String,
    #[serde(default)]
    pub size: u64,
}

#[derive(Debug, Clone, Deserialize)]
pub struct BodyValue {
    #[serde(default)]
    pub value: String,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Email {
    pub id: String,
    /// The raw message – for an end-to-end encrypted one, downloaded and decrypted here.
    #[serde(default)]
    pub blob_id: Option<String>,
    #[serde(default, rename = "kernoid:encrypted")]
    pub encrypted: bool,
    #[serde(default, rename = "kernoid:encryptedSummary")]
    pub encrypted_summary: Option<String>,
    #[serde(default)]
    pub from: Option<Vec<EmailAddress>>,
    #[serde(default)]
    pub to: Option<Vec<EmailAddress>>,
    #[serde(default)]
    pub cc: Option<Vec<EmailAddress>>,
    #[serde(default)]
    pub subject: Option<String>,
    #[serde(default)]
    pub received_at: String,
    #[serde(default)]
    pub preview: String,
    #[serde(default)]
    pub text_body: Vec<BodyPart>,
    #[serde(default)]
    pub html_body: Vec<BodyPart>,
    #[serde(default)]
    pub attachments: Vec<BodyPart>,
    #[serde(default)]
    pub body_values: std::collections::BTreeMap<String, BodyValue>,
    #[serde(default)]
    pub keywords: std::collections::BTreeMap<String, bool>,
}

impl Email {
    /// The text to read: the text parts, or – for mail with HTML only – its text without tags.
    pub fn text(&self) -> String {
        let values = |parts: &[BodyPart]| -> Vec<String> {
            parts
                .iter()
                .filter_map(|part| part.part_id.as_ref().and_then(|id| self.body_values.get(id)))
                .map(|value| value.value.clone())
                .collect()
        };
        let text = values(&self.text_body);
        let html = self.text_body.iter().all(|part| part.media_type == "text/html");
        if !text.is_empty() && !html {
            return text.join("\n\n");
        }
        let html = values(&self.html_body);
        if html.is_empty() { self.preview.clone() } else { strip_tags(&html.join("\n")) }
    }
}

/// A rough text of HTML, enough to read a message until the apps render HTML safely (**OPEN**).
fn strip_tags(html: &str) -> String {
    let mut out = String::with_capacity(html.len());
    let mut in_tag = false;
    let mut tag = String::new();
    let mut skip = false;
    for ch in html.chars() {
        match ch {
            '<' => {
                in_tag = true;
                tag.clear();
            }
            '>' if in_tag => {
                in_tag = false;
                let name = tag.trim_start_matches('/').split_whitespace().next().unwrap_or("").to_ascii_lowercase();
                if name == "style" || name == "script" {
                    skip = !tag.starts_with('/');
                }
                if matches!(name.as_str(), "br" | "p" | "div" | "tr" | "li" | "h1" | "h2" | "h3") {
                    out.push('\n');
                }
            }
            _ if in_tag => tag.push(ch),
            _ if skip => {}
            _ => out.push(ch),
        }
    }
    let out = out.replace("&nbsp;", " ").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"");
    let out = out.replace("&#39;", "'").replace("&amp;", "&");
    let mut lines: Vec<&str> = out.lines().map(str::trim_end).collect();
    lines.dedup_by(|a, b| a.is_empty() && b.is_empty());
    lines.join("\n").trim().to_owned()
}

const SUMMARY: [&str; 7] = ["id", "from", "subject", "preview", "receivedAt", "keywords", "hasAttachment"];
const MESSAGE: [&str; 13] = [
    "id",
    "blobId",
    "from",
    "to",
    "cc",
    "subject",
    "receivedAt",
    "preview",
    "textBody",
    "htmlBody",
    "attachments",
    "bodyValues",
    "keywords",
];

/// The capabilities and properties of a mail request: with kernoid's end-to-end properties where the server has them.
fn with_e2e<'a>(client: &Client, properties: &[&'a str]) -> (Vec<&'static str>, Vec<&'a str>) {
    let mut properties = properties.to_vec();
    if client.session.capabilities.contains_key(OPENPGP) {
        properties.extend(["kernoid:encrypted", "kernoid:encryptedSummary"]);
        (vec![MAIL, OPENPGP], properties)
    } else {
        (vec![MAIL], properties)
    }
}

pub async fn mailboxes(client: &Client, account: &str) -> Result<Vec<Mailbox>> {
    let responses = client.request(&[MAIL], vec![("Mailbox/get", json!({ "accountId": account }), "m")]).await?;
    let mut boxes: Vec<Mailbox> = list(responses.get("m"))?;
    boxes.sort_by(|a, b| {
        role_rank(a).cmp(&role_rank(b)).then(a.sort_order.cmp(&b.sort_order)).then(a.name.cmp(&b.name))
    });
    Ok(boxes)
}

/// The order of the special mailboxes, as mail programs show them.
fn role_rank(mailbox: &Mailbox) -> u8 {
    match mailbox.role.as_deref() {
        Some("inbox") => 0,
        Some("drafts") => 1,
        Some("sent") => 2,
        Some("archive") => 3,
        Some("junk") => 4,
        Some("trash") => 5,
        Some(_) => 6,
        None => 7,
    }
}

/// A page of a mailbox, newest first, and how many there are.
pub async fn page(
    client: &Client,
    account: &str,
    mailbox: &str,
    position: u32,
    limit: u32,
) -> Result<(Vec<Summary>, u64)> {
    let (using, properties) = with_e2e(client, &SUMMARY);
    let responses = client
        .request(
            &using,
            vec![
                (
                    "Email/query",
                    json!({
                        "accountId": account, "filter": { "inMailbox": mailbox }, "position": position,
                        "limit": limit, "sort": [{ "property": "receivedAt", "isAscending": false }],
                        "calculateTotal": true,
                    }),
                    "q",
                ),
                (
                    "Email/get",
                    json!({ "accountId": account, "#ids": ids_of("q", "Email/query"), "properties": properties }),
                    "g",
                ),
            ],
        )
        .await?;
    let total = responses.get("q").and_then(|q| q.get("total")).and_then(Value::as_u64).unwrap_or(0);
    Ok((list(responses.get("g"))?, total))
}

/// One message to read; marks it as seen.
pub async fn email(client: &Client, account: &str, id: &str) -> Result<Email> {
    let (using, properties) = with_e2e(client, &MESSAGE);
    let responses = client
        .request(
            &using,
            vec![
                (
                    "Email/get",
                    json!({
                        "accountId": account, "ids": [id],
                        "properties": properties,
                        "fetchTextBodyValues": true, "fetchHTMLBodyValues": true, "maxBodyValueBytes": 4_000_000,
                    }),
                    "g",
                ),
                ("Email/set", json!({ "accountId": account, "update": { id: { "keywords/$seen": true } } }), "s"),
            ],
        )
        .await?;
    list::<Email>(responses.get("g"))?.into_iter().next().ok_or_else(|| Error::Protocol("the message is gone".into()))
}

#[derive(Debug, Clone, Deserialize)]
pub struct Identity {
    pub id: String,
    #[serde(default)]
    pub name: String,
    pub email: String,
}

/// The identity to send as: the account's first.
pub async fn identity(client: &Client, account: &str) -> Result<Identity> {
    let responses =
        client.request(&[MAIL, SUBMISSION], vec![("Identity/get", json!({ "accountId": account }), "i")]).await?;
    list::<Identity>(responses.get("i"))?
        .into_iter()
        .next()
        .ok_or_else(|| Error::Protocol("the account has no identity to send as".into()))
}

/// Sends a plain-text message as the account's first identity: stored in Drafts, submitted, then moved to Sent
/// (RFC 8621, 7.5).
pub async fn send(client: &Client, account: &str, to: &[String], subject: &str, text: &str) -> Result<()> {
    let boxes = mailboxes(client, account).await?;
    let by_role = |role: &str| boxes.iter().find(|b| b.role.as_deref() == Some(role)).map(|b| b.id.clone());
    let drafts = by_role("drafts").ok_or_else(|| Error::Protocol("there is no Drafts mailbox".into()))?;
    let identity = identity(client, account).await?;
    let mut update = json!({ "keywords/$draft": null });
    if let Some(sent) = by_role("sent") {
        update["mailboxIds"] = json!({ sent: true });
    }
    let from = json!([{ "name": (!identity.name.is_empty()).then_some(&identity.name), "email": identity.email }]);
    let to: Vec<Value> = to.iter().map(|address| json!({ "email": address.trim() })).collect();
    let draft = json!({
        "mailboxIds": { drafts: true }, "keywords": { "$draft": true, "$seen": true },
        "from": from, "to": to, "subject": subject,
        "bodyValues": { "t": { "value": text } }, "textBody": [{ "partId": "t", "type": "text/plain" }],
    });
    let responses = client
        .request(
            &[MAIL, SUBMISSION],
            vec![
                ("Email/set", json!({ "accountId": account, "create": { "draft": draft } }), "e"),
                (
                    "EmailSubmission/set",
                    json!({
                        "accountId": account,
                        "create": { "send": { "identityId": identity.id, "emailId": "#draft" } },
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn html_becomes_readable_text() {
        let html = "<html><style>p{}</style><p>Hallo&nbsp;Welt</p><p>a &amp; b</p><script>x()</script></html>";
        assert_eq!(strip_tags(html), "Hallo Welt\n\na & b");
    }
}
