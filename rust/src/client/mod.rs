// SPDX-License-Identifier: MIT
//! An async JMAP client for kernoid (RFC 8620): the session, method calls with back-references, downloads. Written
//! after the terminal app's protocol layer; it moves into `kernoid-client` of kernoid's Rust SDK once that exists
//! (docs/plan.md, 3).

pub mod e2e;
pub mod files;
pub mod mail;

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::time::Duration;

use reqwest::header::{ACCEPT, CONTENT_TYPE};
use serde::Deserialize;
use serde_json::{Value, json};

pub const CORE: &str = "urn:ietf:params:jmap:core";
pub const MAIL: &str = "urn:ietf:params:jmap:mail";
pub const SUBMISSION: &str = "urn:ietf:params:jmap:submission";
pub const FILES: &str = "urn:ietf:params:jmap:filenode";

/// What can go wrong talking to kernoid. The message is for people; details of the server stay with the server.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("address or app password is wrong")]
    Unauthorized,
    #[error("{0}")]
    Network(String),
    #[error("{0}")]
    Protocol(String),
    #[error("{0}")]
    Refused(String),
    /// End-to-end encryption: a key is missing or locked, or a message cannot be opened.
    #[error("{0}")]
    E2e(String),
}

impl From<kernoid_e2e::Error> for Error {
    fn from(error: kernoid_e2e::Error) -> Self {
        Error::E2e(error.to_string())
    }
}

impl From<reqwest::Error> for Error {
    fn from(error: reqwest::Error) -> Self {
        Error::Network(error.to_string())
    }
}

pub type Result<T> = std::result::Result<T, Error>;

/// The session object (RFC 8620, 2), as far as the apps need it.
#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Session {
    pub username: String,
    pub api_url: String,
    pub download_url: String,
    pub upload_url: String,
    #[serde(default)]
    pub accounts: std::collections::BTreeMap<String, SessionAccount>,
    #[serde(default)]
    pub primary_accounts: std::collections::BTreeMap<String, String>,
    #[serde(default)]
    pub capabilities: std::collections::BTreeMap<String, Value>,
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionAccount {
    pub name: String,
    #[serde(default)]
    pub is_personal: bool,
    #[serde(default)]
    pub account_capabilities: std::collections::BTreeMap<String, Value>,
}

impl Session {
    /// The account for a capability: the primary one.
    pub fn primary(&self, capability: &str) -> Option<&str> {
        self.primary_accounts.get(capability).map(String::as_str)
    }
}

/// The scheme and authority of a URL (`https://host:port`) and the rest.
pub fn split_origin(url: &str) -> Option<(&str, &str)> {
    let scheme = url.split_once("://")?.0;
    let after = &url[scheme.len() + 3..];
    let end = after.find(['/', '?', '#']).unwrap_or(after.len());
    if end == 0 {
        return None;
    }
    let origin = &url[..scheme.len() + 3 + end];
    let rest = &url[origin.len()..];
    Some((origin, if rest.is_empty() { "/" } else { rest }))
}

/// The host of an origin, without port and brackets.
fn host(origin: &str) -> &str {
    let authority = origin.split_once("://").map_or(origin, |(_, rest)| rest);
    if let Some(rest) = authority.strip_prefix('[') {
        return rest.split(']').next().unwrap_or(rest);
    }
    authority.rsplit_once(':').map_or(authority, |(host, _)| host)
}

/// Whether plain HTTP to this origin stays on this machine: loopback addresses, `localhost` and `*.localhost`.
pub fn is_local(origin: &str) -> bool {
    let host = host(origin).to_ascii_lowercase();
    host == "localhost"
        || host.ends_with(".localhost")
        || host.parse::<IpAddr>().is_ok_and(|address| address.is_loopback())
}

/// A logged-in client: the session and the credentials, sent only to the origin the session came from.
#[derive(Clone)]
pub struct Client {
    http: reqwest::Client,
    origin: String,
    username: String,
    password: String,
    pub session: Session,
}

impl std::fmt::Debug for Client {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Client").field("origin", &self.origin).field("username", &self.username).finish()
    }
}

impl Client {
    /// Logs in to `server` (`https://host` or a URL of its session) with an address and an app password. Plain HTTP
    /// only to this machine – the password would travel readable.
    pub async fn login(server: &str, username: &str, password: &str) -> Result<Client> {
        let server = server.trim().trim_end_matches('/');
        let server = if server.contains("://") { server.to_owned() } else { format!("https://{server}") };
        let (origin, path) = split_origin(&server).ok_or_else(|| Error::Protocol(format!("not a URL: {server}")))?;
        let origin = origin.to_owned();
        if !origin.starts_with("https://") && !is_local(&origin) {
            return Err(Error::Refused(format!("{origin} is not HTTPS; the password would travel readable")));
        }
        let mut builder = reqwest::Client::builder()
            .connect_timeout(Duration::from_secs(15))
            .timeout(Duration::from_secs(60))
            .redirect(reqwest::redirect::Policy::none())
            .user_agent(concat!("kernoid-app/", env!("CARGO_PKG_VERSION")));
        // `*.localhost` is this machine (RFC 6761), but not every system's resolver knows it.
        let name = host(&origin);
        if name.ends_with(".localhost") {
            builder = builder.resolve(name, SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 0));
        }
        let http = builder.build()?;
        let session_path = if path == "/" { "/.well-known/jmap" } else { path };
        let mut client = Client {
            http,
            origin,
            username: username.trim().to_owned(),
            password: password.to_owned(),
            session: Session {
                username: String::new(),
                api_url: String::new(),
                download_url: String::new(),
                upload_url: String::new(),
                accounts: Default::default(),
                primary_accounts: Default::default(),
                capabilities: Default::default(),
            },
        };
        client.session = client.fetch_session(session_path).await?;
        Ok(client)
    }

    /// The origin this client talks to.
    pub fn origin(&self) -> &str {
        &self.origin
    }

    /// A URL of the session on the origin the session came from – the credentials go nowhere else. A server that
    /// names another host (or no port, behind a proxy) is still asked here.
    fn on_origin(&self, url: &str) -> String {
        match split_origin(url) {
            Some((_, rest)) => format!("{}{rest}", self.origin),
            None if url.starts_with('/') => format!("{}{url}", self.origin),
            None => format!("{}/{url}", self.origin),
        }
    }

    async fn fetch_session(&self, path: &str) -> Result<Session> {
        let mut url = self.on_origin(path);
        // `/.well-known/jmap` redirects to the session; follow it on this origin only.
        for _ in 0..5 {
            let response = self
                .http
                .get(&url)
                .basic_auth(&self.username, Some(&self.password))
                .header(ACCEPT, "application/json")
                .send()
                .await?;
            let status = response.status();
            if status.is_redirection() {
                let location = response
                    .headers()
                    .get(reqwest::header::LOCATION)
                    .and_then(|value| value.to_str().ok())
                    .ok_or_else(|| Error::Protocol("a redirect without a location".into()))?;
                url = self.on_origin(location);
                continue;
            }
            return match status.as_u16() {
                200 => response.json::<Session>().await.map_err(|error| Error::Protocol(error.to_string())),
                _ => Err(status_error(&response, "the session")),
            };
        }
        Err(Error::Protocol("too many redirects".into()))
    }

    /// Sends one request with several method calls (RFC 8620, 3.3); each call is `(name, arguments, call id)`.
    /// Returns the responses by call id; a method-level error becomes `Error::Protocol`.
    pub async fn request(&self, using: &[&str], calls: Vec<(&str, Value, &str)>) -> Result<Responses> {
        let mut capabilities = vec![CORE];
        capabilities.extend(using.iter().copied().filter(|c| *c != CORE));
        let calls: Vec<Value> = calls.into_iter().map(|(name, arguments, id)| json!([name, arguments, id])).collect();
        let body = json!({ "using": capabilities, "methodCalls": calls });
        let response = self
            .http
            .post(self.on_origin(&self.session.api_url))
            .basic_auth(&self.username, Some(&self.password))
            .header(CONTENT_TYPE, "application/json")
            .json(&body)
            .send()
            .await?;
        match response.status().as_u16() {
            200 => {}
            _ => return Err(status_error(&response, "the request")),
        }
        let value: Value = response.json().await?;
        let mut responses = Vec::new();
        for item in value.get("methodResponses").and_then(Value::as_array).into_iter().flatten() {
            let (Some(name), Some(arguments), Some(id)) =
                (item.get(0).and_then(Value::as_str), item.get(1), item.get(2).and_then(Value::as_str))
            else {
                continue;
            };
            if name == "error" {
                let kind = arguments.get("type").and_then(Value::as_str).unwrap_or("serverFail");
                let description = arguments.get("description").and_then(Value::as_str).unwrap_or("");
                return Err(Error::Protocol(format!("{kind} {description}").trim().to_owned()));
            }
            responses.push((name.to_owned(), arguments.clone(), id.to_owned()));
        }
        Ok(Responses(responses))
    }

    /// Uploads bytes as a blob (RFC 8620, 6.1) and returns its id. **OPEN**: large files in pieces (RFC 9404), as
    /// `kernoid-sync` will.
    pub async fn upload(&self, account: &str, media_type: &str, bytes: Vec<u8>) -> Result<String> {
        let url = self.session.upload_url.replace("{accountId}", &encode(account));
        let response = self
            .http
            .post(self.on_origin(&url))
            .basic_auth(&self.username, Some(&self.password))
            .header(CONTENT_TYPE, media_type)
            .body(bytes)
            .send()
            .await?;
        match response.status().as_u16() {
            200 | 201 => {}
            _ => return Err(status_error(&response, "the upload")),
        }
        let value: Value = response.json().await?;
        value
            .get("blobId")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| Error::Protocol("the upload has no blobId".into()))
    }

    /// Downloads a blob into memory (RFC 8620, 6.2).
    pub async fn download(&self, account: &str, blob: &str, name: &str, media_type: &str) -> Result<Vec<u8>> {
        let url = self
            .session
            .download_url
            .replace("{accountId}", &encode(account))
            .replace("{blobId}", &encode(blob))
            .replace("{name}", &encode(name))
            .replace("{type}", &encode(media_type));
        let response =
            self.http.get(self.on_origin(&url)).basic_auth(&self.username, Some(&self.password)).send().await?;
        match response.status().as_u16() {
            200 => Ok(response.bytes().await?.to_vec()),
            _ => Err(status_error(&response, "the download")),
        }
    }
}

/// The error a status other than success means: a wrong login, too many attempts (with the wait the server names in
/// `Retry-After`), or anything else.
fn status_error(response: &reqwest::Response, what: &str) -> Error {
    match response.status().as_u16() {
        401 | 403 => Error::Unauthorized,
        429 => {
            let wait = response
                .headers()
                .get(reqwest::header::RETRY_AFTER)
                .and_then(|v| v.to_str().ok())
                .and_then(|v| v.parse::<u64>().ok());
            Error::Refused(match wait {
                Some(seconds) => format!("too many attempts; try again in {} minutes", seconds.div_ceil(60)),
                None => "too many attempts; try again later".into(),
            })
        }
        code => Error::Protocol(format!("the server answered {code} for {what}")),
    }
}

/// Percent-encodes a value for a URL template; ids and names of kernoid are mostly safe, names of files are not.
fn encode(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || b"-._~".contains(&byte) {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

/// The responses of a request: `(method name, arguments, call id)`.
#[derive(Debug)]
pub struct Responses(pub Vec<(String, Value, String)>);

impl Responses {
    /// The arguments of the response to a call id.
    pub fn get(&self, id: &str) -> Option<&Value> {
        self.0.iter().find(|(_, _, call)| call == id).map(|(_, arguments, _)| arguments)
    }
}

/// A back-reference to the ids a query found (RFC 8620, 3.7).
pub fn ids_of(call: &str, name: &str) -> Value {
    json!({ "resultOf": call, "name": name, "path": "/ids" })
}

/// The `list` of a `/get` response, typed.
pub fn list<T: serde::de::DeserializeOwned>(value: Option<&Value>) -> Result<Vec<T>> {
    let items = value.and_then(|v| v.get("list")).cloned().unwrap_or(json!([]));
    serde_json::from_value(items).map_err(|error| Error::Protocol(error.to_string()))
}

/// The first `SetError` of a `/set` response, if any (RFC 8620, 5.3).
pub fn set_error(result: &Value) -> Result<()> {
    for key in ["notCreated", "notUpdated", "notDestroyed"] {
        if let Some(errors) = result.get(key).and_then(Value::as_object)
            && let Some(error) = errors.values().next()
        {
            let kind = error.get("type").and_then(Value::as_str).unwrap_or("serverFail");
            let description = error.get("description").and_then(Value::as_str).unwrap_or("");
            return Err(Error::Refused(format!("{kind} {description}").trim().to_owned()));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn origins_are_split_and_local_ones_found() {
        assert_eq!(split_origin("https://a.example/jmap"), Some(("https://a.example", "/jmap")));
        assert_eq!(split_origin("http://apps.localhost:18190"), Some(("http://apps.localhost:18190", "/")));
        assert_eq!(split_origin("https://"), None);
        assert!(is_local("http://apps.localhost:18190"));
        assert!(is_local("http://127.0.0.1:8080"));
        assert!(is_local("http://[::1]:8080"));
        assert!(!is_local("http://kernoid.example"));
    }

    #[test]
    fn urls_of_the_session_stay_on_the_origin() {
        let client = Client {
            http: reqwest::Client::new(),
            origin: "http://apps.localhost:18190".into(),
            username: String::new(),
            password: String::new(),
            session: serde_json::from_value(json!({
                "username": "a", "apiUrl": "http://apps.localhost/jmap/api",
                "downloadUrl": "", "uploadUrl": ""
            }))
            .unwrap(),
        };
        assert_eq!(client.on_origin("http://apps.localhost/jmap/api"), "http://apps.localhost:18190/jmap/api");
        assert_eq!(client.on_origin("https://elsewhere.example/x"), "http://apps.localhost:18190/x");
        assert_eq!(client.on_origin("/jmap/session"), "http://apps.localhost:18190/jmap/session");
    }

    #[test]
    fn names_are_encoded_for_templates() {
        assert_eq!(encode("Bericht 2026.pdf"), "Bericht%202026.pdf");
        assert_eq!(encode("ü/x"), "%C3%BC%2Fx");
    }
}
