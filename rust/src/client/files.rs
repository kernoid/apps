// SPDX-License-Identifier: MIT
//! JMAP for files (`FileNode`, draft-ietf-jmap-filenode, as kernoid implements it – RFC 0005): the stores the
//! session reaches and the nodes of a directory.

use serde::Deserialize;
use serde_json::json;

use super::{Client, FILES, Result, ids_of, list};

const PROPERTIES: [&str; 8] = ["id", "parentId", "name", "role", "blobId", "size", "mediaType", "modified"];

/// A store of files the session reaches: the account's own, a drive, or one shared with it.
#[derive(Debug, Clone)]
pub struct Store {
    pub account_id: String,
    pub name: String,
    pub is_personal: bool,
}

pub fn stores(client: &Client) -> Vec<Store> {
    let mut stores: Vec<Store> = client
        .session
        .accounts
        .iter()
        .filter(|(_, account)| account.account_capabilities.contains_key(FILES))
        .map(|(id, account)| Store {
            account_id: id.clone(),
            name: account.name.clone(),
            is_personal: account.is_personal,
        })
        .collect();
    let primary = client.session.primary(FILES).map(str::to_owned);
    stores.sort_by(|a, b| {
        (Some(&b.account_id) == primary.as_ref())
            .cmp(&(Some(&a.account_id) == primary.as_ref()))
            .then(a.name.cmp(&b.name))
    });
    stores
}

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileNode {
    pub id: String,
    #[serde(default)]
    pub parent_id: Option<String>,
    pub name: String,
    #[serde(default)]
    pub role: Option<String>,
    /// Absent for directories.
    #[serde(default)]
    pub blob_id: Option<String>,
    #[serde(default)]
    pub size: u64,
    #[serde(default)]
    pub media_type: Option<String>,
    #[serde(default)]
    pub modified: Option<String>,
}

impl FileNode {
    pub fn is_directory(&self) -> bool {
        self.blob_id.is_none()
    }
}

/// The nodes of a directory – or of the top of a store, for `None` – directories first, then by name.
pub async fn children(client: &Client, account: &str, parent: Option<&str>) -> Result<Vec<FileNode>> {
    let filter = match parent {
        Some(parent) => json!({ "parentId": parent }),
        None => json!({ "isTopLevel": true }),
    };
    let responses = client
        .request(
            &[FILES],
            vec![
                ("FileNode/query", json!({ "accountId": account, "filter": filter }), "q"),
                (
                    "FileNode/get",
                    json!({ "accountId": account, "properties": PROPERTIES, "#ids": ids_of("q", "FileNode/query") }),
                    "g",
                ),
            ],
        )
        .await?;
    let mut nodes: Vec<FileNode> = list(responses.get("g"))?;
    nodes.sort_by(|a, b| {
        b.is_directory().cmp(&a.is_directory()).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(nodes)
}
