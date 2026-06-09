use std::path::{Path, PathBuf};
use std::process::Command;

fn temp_dir(tag: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let dir = std::env::temp_dir().join(format!("decks-it-{tag}-{nanos}"));
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

fn run(dir: &Path, args: &[&str]) -> String {
    let output = Command::new(env!("CARGO_BIN_EXE_decks"))
        .args(args)
        .env("DECKS_DIR", dir)
        .output()
        .expect("run decks");
    assert!(
        output.status.success(),
        "decks {args:?} failed: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn full_flow() {
    let dir = temp_dir("flow");

    run(&dir, &["new", "Acme", "Corp"]);
    run(&dir, &["add", "acme-corp", "review", "PR", "214"]);
    run(&dir, &["daily", "acme-corp", "shipped", "auth"]);
    run(&dir, &["note", "acme-corp", "use", "sqlite"]);

    let list = run(&dir, &["list", "--json"]);
    assert!(list.contains("\"slug\": \"acme-corp\""), "{list}");
    assert!(list.contains("\"openTodos\": 1"), "{list}");

    let show = run(&dir, &["show", "acme-corp", "--json"]);
    assert!(show.contains("review PR 214"), "{show}");
    assert!(show.contains("shipped auth"), "{show}");
    assert!(show.contains("use sqlite"), "{show}");

    run(&dir, &["done", "acme-corp", "0"]);
    let after = run(&dir, &["list", "--json"]);
    assert!(after.contains("\"openTodos\": 0"), "{after}");

    std::fs::remove_dir_all(&dir).ok();
}

#[test]
fn worklog_collects_today_commits() {
    let dir = temp_dir("worklog");
    let repo = dir.join("repo");
    std::fs::create_dir_all(&repo).unwrap();

    let git = |args: &[&str]| {
        Command::new("git")
            .arg("-C")
            .arg(&repo)
            .args(args)
            .output()
            .expect("git");
    };
    git(&["init", "-q"]);
    git(&["config", "user.email", "me@acme.dev"]);
    git(&["config", "user.name", "Me"]);
    git(&["commit", "--allow-empty", "-q", "-m", "ship the thing"]);

    run(&dir, &["new", "Acme"]);
    let profile = format!(
        r#"{{"gitProvider":"other","authorEmail":"me@acme.dev","repos":["{}"]}}"#,
        repo.display()
    );
    std::fs::write(dir.join("acme").join("profile.json"), profile).unwrap();

    run(&dir, &["worklog", "acme"]);
    let daily = std::fs::read_to_string(dir.join("acme").join("daily.md")).unwrap();
    assert!(daily.contains("Worklog"), "{daily}");
    assert!(daily.contains("ship the thing"), "{daily}");

    std::fs::remove_dir_all(&dir).ok();
}
