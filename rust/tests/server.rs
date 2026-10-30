// SPDX-License-Identifier: MIT
//! Against a real kernoid, when one is named: `KERNOID_TEST_SERVER` (e.g. `http://apps.localhost:18190`),
//! `KERNOID_TEST_ADDRESS` and `KERNOID_TEST_PASSWORD` (an app password). Without them the test does nothing.
//!
//! Sent mail goes through the queue and the recipient's MX, which a development server's domain does not have – so the
//! test sends to itself and finds the message in Sent, and puts a message into the inbox with `Email/import`.

use kernoid_bridge::client::{Client, FILES, MAIL, files, mail};
use serde_json::json;

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
    assert!(Client::login(&server, &address, "wrong").await.is_err());
    let client = Client::login(&server, &address, &password).await.expect("login");
    assert_eq!(client.session.username, address);
    let account = client.session.primary(MAIL).expect("mail").to_owned();
    let boxes = mail::mailboxes(&client, &account).await.expect("mailboxes");
    let by_role = |role: &str| boxes.iter().find(|b| b.role.as_deref() == Some(role)).expect(role).id.clone();

    let subject = format!("Sent {}", std::process::id());
    mail::send(&client, &account, std::slice::from_ref(&address), &subject, "Hallo von der App.").await.expect("send");
    let (sent, _) = mail::page(&client, &account, &by_role("sent"), 0, 50).await.expect("sent");
    assert!(sent.iter().any(|e| e.subject.as_deref() == Some(subject.as_str())));

    let subject = format!("Imported {}", std::process::id());
    let raw = format!(
        "From: Bob <bob@example.org>\r\nTo: {address}\r\nSubject: {subject}\r\nDate: Thu, 29 Oct 2026 10:00:00 +0000\r\n\
         Content-Type: text/html; charset=utf-8\r\n\r\n<p>Hallo&nbsp;Alice</p>\r\n"
    );
    let blob = client.upload(&account, "message/rfc822", raw.into_bytes()).await.expect("upload");
    let inbox = by_role("inbox");
    let responses = client
        .request(
            &[MAIL],
            vec![(
                "Email/import",
                json!({ "accountId": account, "emails": { "m": { "blobId": blob, "mailboxIds": { &inbox: true } } } }),
                "i",
            )],
        )
        .await
        .expect("import");
    kernoid_bridge::client::set_error(responses.get("i").expect("import")).expect("imported");
    let (page, total) = mail::page(&client, &account, &inbox, 0, 50).await.expect("page");
    assert!(total >= 1);
    let found = page.into_iter().find(|e| e.subject.as_deref() == Some(subject.as_str())).expect("imported");
    let email = mail::email(&client, &account, &found.id).await.expect("email");
    assert_eq!(email.text(), "Hallo Alice");

    let stores = files::stores(&client);
    let own = stores.iter().find(|s| Some(s.account_id.as_str()) == client.session.primary(FILES)).expect("files");
    files::children(&client, &own.account_id, None).await.expect("files");
}

/// End-to-end encrypted mail (RFC 0006, 5): the account's key made here – or, if it has one, unlocked with the recovery
/// code kept in `KERNOID_TEST_RECOVERY_FILE` by an earlier run –, a message sent to itself encrypted and signed, found
/// in Sent with its summary, decrypted and verified; locked again, it stays closed.
#[tokio::test]
async fn mail_is_encrypted_end_to_end() {
    use kernoid_bridge::client::e2e::{E2e, Outgoing, Plan};
    let (Ok(server), Ok(address), Ok(password), Ok(file)) = (
        std::env::var("KERNOID_TEST_SERVER"),
        std::env::var("KERNOID_TEST_ADDRESS"),
        std::env::var("KERNOID_TEST_PASSWORD"),
        std::env::var("KERNOID_TEST_RECOVERY_FILE"),
    ) else {
        eprintln!("no KERNOID_TEST_SERVER or KERNOID_TEST_RECOVERY_FILE: skipped");
        return;
    };
    let client = Client::login(&server, &address, &password).await.expect("login");
    let account = client.session.primary(MAIL).expect("mail").to_owned();
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

    let identity = mail::identity(&client, &account).await.expect("identity");
    let to = vec![address.clone()];
    let Plan::Sealed(keys) = e2e.plan(&client, &account, &identity, &to).await else { panic!("not sealed") };
    let subject = format!("Sealed {}", std::process::id());
    let message =
        Outgoing { to: &to, subject: &subject, text: "Nur für mich.", date: "Fri, 30 Oct 2026 17:00:00 +0100" };
    e2e.send(&client, &account, &identity, message, &keys).await.expect("send");

    let boxes = mail::mailboxes(&client, &account).await.expect("mailboxes");
    let sent = boxes.iter().find(|b| b.role.as_deref() == Some("sent")).expect("sent").id.clone();
    let (page, _) = mail::page(&client, &account, &sent, 0, 50).await.expect("page");
    let mut found = None;
    for mut summary in page.into_iter().filter(|e| e.encrypted) {
        if e2e.open_summary(&mut summary) && summary.subject.as_deref() == Some(subject.as_str()) {
            found = Some(summary);
        }
    }
    let found = found.expect("the encrypted message in Sent, its summary decrypted");
    let email = mail::email(&client, &account, &found.id).await.expect("email");
    assert!(email.encrypted);
    let opened = e2e.open(&client, &account, email.clone()).await.expect("open");
    assert!(!opened.locked && opened.signed && opened.verified);
    assert_eq!(opened.email.text().trim(), "Nur für mich.");

    e2e.lock();
    let locked = e2e.open(&client, &account, email).await.expect("open locked");
    assert!(locked.locked && locked.email.text_body.is_empty());
}
