use std::io::Write;
use std::process::{Command, Stdio};

#[test]
fn mcp_handshake_and_list_decks() {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("decks-mcp-it-{nanos}"));
    std::fs::create_dir_all(&dir).unwrap();

    Command::new(env!("CARGO_BIN_EXE_decks"))
        .args(["new", "Acme"])
        .env("DECKS_DIR", &dir)
        .output()
        .expect("create deck");

    let mut child = Command::new(env!("CARGO_BIN_EXE_decks-mcp"))
        .env("DECKS_DIR", &dir)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("spawn decks-mcp");

    let input = concat!(
        r#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
        "\n",
        r#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
        "\n",
        r#"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_decks","arguments":{}}}"#,
        "\n",
    );
    child
        .stdin
        .take()
        .unwrap()
        .write_all(input.as_bytes())
        .unwrap();

    let output = child.wait_with_output().expect("wait decks-mcp");
    let stdout = String::from_utf8(output.stdout).unwrap();

    assert!(stdout.contains("\"serverInfo\""), "{stdout}");
    assert!(stdout.contains("add_daily_entry"), "{stdout}");
    assert!(stdout.contains("acme"), "{stdout}");

    std::fs::remove_dir_all(&dir).ok();
}
