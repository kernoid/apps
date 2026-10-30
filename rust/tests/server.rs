// SPDX-License-Identifier: MIT
//! Against a real kernoid, when one is named: `KERNOID_TEST_SERVER` (e.g. `http://apps.localhost:18190`),
//! `KERNOID_TEST_ADDRESS` and `KERNOID_TEST_PASSWORD` (an app password). Without them the test does nothing. The
//! protocols are kernoid's Rust SDK (`kernoid-client`), tested in kernoid's repository as well; these tests check what
//! the apps rely on.
//!
//! Sent mail goes through the queue and the recipient's MX, which a development server's domain does not have – so the
//! test sends to itself and finds the message in Sent, and puts a message into the inbox with `Email/import`.

use kernoid_client::{
    Client, FILENODE, MAIL, Options,
    e2e::{E2e, Outgoing, Plan},
    files,
    mail::{self, Draft, EmailAddress, Identity},
    set_error,
};
use serde_json::json;

async fn login(server: &str, address: &str, password: &str) -> kernoid_client::Result<Client> {
    let url = kernoid_client::session_url(Some(server), address)?;
    Client::connect(&url, address, password, &Options::default()).await
}

fn draft(to: &str, subject: &str, text: &str) -> Draft {
    Draft {
        from: None,
        to: vec![EmailAddress { name: None, email: to.to_owned() }],
        cc: Vec::new(),
        bcc: Vec::new(),
        subject: subject.to_owned(),
        body: text.to_owned(),
        in_reply_to: Vec::new(),
        references: Vec::new(),
        attachments: Vec::new(),
    }
}

async fn identity(client: &Client, account: &str) -> Identity {
    mail::identities(client, account).await.expect("identities").into_iter().next().expect("an identity")
}

#[tokio::test]
async fn mail_is_sent_and_read_and_files_are_listed() {
    let (Ok(server), Ok(address), Ok(password)) = (
        std::env::var("KERNOID_TEST_SERVER"),
        std::env::var("KERNOID_TEST_ADDRESS"),
        std::env::var("KERNOID_TEST_PASSWORD"),
    ) else {
        eprintln!("no KERNOID_TEST_SERVER: skipped");
        return;
    };
    assert!(login(&server, &address, "wrong").await.is_err());
    let client = login(&server, &address, &password).await.expect("login");
    assert_eq!(client.session.username, address);
    let account = client.primary(MAIL).expect("mail");
    let boxes = mail::mailboxes(&client, &account).await.expect("mailboxes");
    let by_role = |role: &str| boxes.iter().find(|b| b.role.as_deref() == Some(role)).expect(role).id.clone();

    let subject = format!("Sent {}", std::process::id());
    let identity = identity(&client, &account).await;
    mail::send(&client, &account, &identity, &draft(&address, &subject, "Hallo von der App."), &boxes)
        .await
        .expect("send");
    let (sent, _) = mail::emails(&client, &account, Some(&by_role("sent")), "", 0, 50).await.expect("sent");
    assert!(sent.iter().any(|e| e.subject.as_deref() == Some(subject.as_str())));

    let subject = format!("Imported {}", std::process::id());
    let raw = format!(
        "From: Bob <bob@example.org>\r\nTo: {address}\r\nSubject: {subject}\r\nDate: Thu, 29 Oct 2026 10:00:00 +0000\r\n\
         Content-Type: text/html; charset=utf-8\r\n\r\n<p>Hallo&nbsp;Alice</p>\r\n"
    );
    let size = raw.len() as u64;
    let blob = client
        .upload(&account, "message/rfc822", std::io::Cursor::new(raw.into_bytes()), size, |_, _| {})
        .await
        .expect("upload");
    let inbox = by_role("inbox");
    let responses = client
        .request(
            &[MAIL],
            vec![(
                "Email/import",
                json!({ "accountId": account, "emails": { "m": { "blobId": blob.blob_id, "mailboxIds": { &inbox: true } } } }),
                "i",
            )],
        )
        .await
        .expect("import");
    set_error(responses.get("i").expect("import")).expect("imported");
    let (page, total) = mail::emails(&client, &account, Some(&inbox), "", 0, 50).await.expect("page");
    assert!(total >= 1);
    let found = page.into_iter().find(|e| e.subject.as_deref() == Some(subject.as_str())).expect("imported");
    let email = mail::full(&client, &account, &[found.id.as_str()]).await.expect("email").remove(0);
    // HTML as text; `&nbsp;` stays a non-breaking space.
    assert_eq!(email.text(10_000).trim().replace('\u{a0}', " "), "Hallo Alice");

    let stores = files::stores(&client);
    let own = stores.iter().find(|s| Some(s.id.as_str()) == client.session.primary(FILENODE)).expect("files");
    files::children(&client, &own.id, None).await.expect("files");
}

/// End-to-end encrypted mail (RFC 0006, 5): the account's key made here – or, if it has one, unlocked with the recovery
/// code kept in `KERNOID_TEST_RECOVERY_FILE` by an earlier run –, a message sent to itself encrypted and signed, found
/// in Sent with its summary, decrypted and verified; locked again, it stays closed.
#[tokio::test]
async fn mail_is_encrypted_end_to_end() {
    let (Ok(server), Ok(address), Ok(password), Ok(file)) = (
        std::env::var("KERNOID_TEST_SERVER"),
        std::env::var("KERNOID_TEST_ADDRESS"),
        std::env::var("KERNOID_TEST_PASSWORD"),
        std::env::var("KERNOID_TEST_RECOVERY_FILE"),
    ) else {
        eprintln!("no KERNOID_TEST_SERVER or KERNOID_TEST_RECOVERY_FILE: skipped");
        return;
    };
    let client = login(&server, &address, &password).await.expect("login");
    let account = client.primary(MAIL).expect("mail");
    let mut e2e = E2e::load(&client).await.expect("keys");
    assert!(e2e.available, "the server has no end-to-end extension");
    if e2e.current_key().is_none() {
        let code = e2e.setup(&client, kernoid_e2e::Kind::Pqc).await.expect("setup");
        std::fs::write(&file, code).expect("recovery file");
    } else {
        let code = std::fs::read_to_string(&file).expect("the account has a key: its recovery code in the file");
        e2e.unlock(&code).expect("unlock");
    }
    assert!(e2e.is_unlocked());

    let identity = identity(&client, &account).await;
    let subject = format!("Sealed {}", std::process::id());
    let message = draft(&address, &subject, "Nur für mich.");
    let Plan::Sealed(keys) = e2e.plan(&client, &account, &identity, &message).await else { panic!("not sealed") };
    let boxes = mail::mailboxes(&client, &account).await.expect("mailboxes");
    let outgoing = Outgoing { account: &account, identity: &identity, draft: &message, files: &[], boxes: &boxes };
    e2e.send(&client, outgoing, &keys).await.expect("send");

    let sent = boxes.iter().find(|b| b.role.as_deref() == Some("sent")).expect("sent").id.clone();
    let (page, _) = mail::emails(&client, &account, Some(&sent), "", 0, 50).await.expect("page");
    let mut found = None;
    for mut summary in page.into_iter().filter(|e| e.encrypted) {
        e2e.open_summary(&mut summary);
        if summary.opened && summary.subject.as_deref() == Some(subject.as_str()) {
            found = Some(summary);
        }
    }
    let found = found.expect("the encrypted message in Sent, its summary decrypted");
    let email = mail::full(&client, &account, &[found.id.as_str()]).await.expect("email").remove(0);
    assert!(email.summary.encrypted);
    let opened = e2e.open(&client, &account, email.clone()).await.expect("open");
    let sealed = opened.sealed.expect("sealed");
    assert!(!sealed.locked && sealed.signed && sealed.verified);
    assert_eq!(opened.text(10_000).trim(), "Nur für mich.");

    e2e.lock();
    let locked = e2e.open(&client, &account, email).await.expect("open locked");
    assert!(locked.sealed.expect("sealed").locked && locked.text_body.is_empty());
}
