use std::fs;
use std::path::{Path, PathBuf};

use clap::{Parser, Subcommand};
use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Parser)]
#[command(
    name = "decks",
    version,
    about = "Per-company notes, shared with the Decks app"
)]
struct Cli {
    /// Print machine-readable JSON instead of text
    #[arg(long, global = true)]
    json: bool,

    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// List every deck with its open to-do count
    List,
    /// Show a deck's to-dos and links
    Show { slug: String },
    /// Create a deck
    New { name: Vec<String> },
    /// Add a to-do to a deck
    Add { slug: String, text: Vec<String> },
    /// Toggle a to-do by its position
    Done { slug: String, index: usize },
    /// Append a note to a deck
    Note { slug: String, text: Vec<String> },
    /// Prepend a dated entry to a deck's daily log
    Daily { slug: String, text: Vec<String> },
    /// Print Claude MCP config for a server scoped to one deck
    McpConfig { slug: String },
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Deck {
    slug: String,
    name: String,
    created_at: String,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Todo {
    id: String,
    text: String,
    done: bool,
    created_at: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    done_at: Option<String>,
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Link {
    id: String,
    label: String,
    url: String,
    #[serde(default)]
    note: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DeckSummary {
    slug: String,
    name: String,
    open_todos: usize,
}

fn main() {
    let cli = Cli::parse();
    match cli.command {
        Command::List => list(cli.json),
        Command::Show { slug } => show(&slug, cli.json),
        Command::New { name } => new(name.join(" ")),
        Command::Add { slug, text } => add(&slug, text.join(" ")),
        Command::Done { slug, index } => done(&slug, index),
        Command::Note { slug, text } => note(&slug, text.join(" ")),
        Command::Daily { slug, text } => daily(&slug, text.join(" ")),
        Command::McpConfig { slug } => mcp_config(&slug),
    }
}

fn mcp_config(slug: &str) {
    let bin = mcp_bin().display().to_string();
    print_json(&mcp_config_value(slug, &bin));
    eprintln!("\nClaude Code: claude mcp add decks-{slug} -- {bin} --deck {slug}");
}

fn mcp_config_value(slug: &str, bin: &str) -> serde_json::Value {
    let mut servers = serde_json::Map::new();
    servers.insert(
        format!("decks-{slug}"),
        serde_json::json!({ "command": bin, "args": ["--deck", slug] }),
    );
    serde_json::json!({ "mcpServers": serde_json::Value::Object(servers) })
}

fn mcp_bin() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("decks-mcp")))
        .unwrap_or_else(|| PathBuf::from("decks-mcp"))
}

fn list(json: bool) {
    let summaries: Vec<DeckSummary> = read_decks()
        .into_iter()
        .map(|deck| {
            let open = read_todos(&deck.slug)
                .iter()
                .filter(|todo| !todo.done)
                .count();
            DeckSummary {
                slug: deck.slug,
                name: deck.name,
                open_todos: open,
            }
        })
        .collect();

    if json {
        print_json(&summaries);
        return;
    }
    for summary in &summaries {
        println!(
            "{:<18} {:>2} open  ({})",
            summary.name, summary.open_todos, summary.slug
        );
    }
}

fn show(slug: &str, json: bool) {
    let todos = read_todos(slug);
    if json {
        #[derive(Serialize)]
        struct View {
            todos: Vec<Todo>,
            links: Vec<Link>,
            daily: String,
            notes: String,
        }
        print_json(&View {
            todos,
            links: read_links(slug),
            daily: read_text(slug, "daily.md"),
            notes: read_text(slug, "notes.md"),
        });
        return;
    }
    for todo in &todos {
        let mark = if todo.done { "x" } else { " " };
        println!("[{mark}] {}", todo.text);
    }
}

fn new(name: String) {
    let name = name.trim().to_string();
    if name.is_empty() {
        eprintln!("a name is required");
        return;
    }
    let slug = slugify(&name);
    if slug.is_empty() {
        eprintln!("a name with letters or numbers is required");
        return;
    }
    let dir = root().join(&slug);
    if dir.join("deck.json").exists() {
        return;
    }
    let _ = fs::create_dir_all(&dir);
    let deck = Deck {
        slug,
        name,
        created_at: now(),
    };
    if let Ok(json) = serde_json::to_string_pretty(&deck) {
        let _ = fs::write(dir.join("deck.json"), json);
    }
}

fn add(slug: &str, text: String) {
    let text = text.trim().to_string();
    if text.is_empty() {
        eprintln!("nothing to add");
        return;
    }
    let mut todos = read_todos(slug);
    todos.insert(
        0,
        Todo {
            id: Uuid::new_v4().to_string().to_uppercase(),
            text,
            done: false,
            created_at: now(),
            done_at: None,
        },
    );
    write_todos(slug, &todos);
}

fn done(slug: &str, index: usize) {
    let mut todos = read_todos(slug);
    match todos.get_mut(index) {
        Some(todo) => {
            todo.done = !todo.done;
            todo.done_at = todo.done.then(now);
            write_todos(slug, &todos);
        }
        None => eprintln!("no to-do at index {index}"),
    }
}

fn note(slug: &str, text: String) {
    let text = text.trim();
    if text.is_empty() {
        eprintln!("nothing to add");
        return;
    }
    let path = root().join(slug).join("notes.md");
    let mut current = fs::read_to_string(&path).unwrap_or_default();
    if !current.is_empty() && !current.ends_with('\n') {
        current.push('\n');
    }
    current.push_str(text);
    current.push('\n');
    let _ = fs::write(path, current);
}

fn daily(slug: &str, text: String) {
    let text = text.trim();
    if text.is_empty() {
        eprintln!("nothing to add");
        return;
    }
    let date = &now()[..10];
    let path = root().join(slug).join("daily.md");
    let current = fs::read_to_string(&path).unwrap_or_default();
    let entry = format!("## {date}\n\n{text}\n\n");
    let next = if current.is_empty() {
        entry
    } else {
        format!("{entry}{current}")
    };
    let _ = fs::write(path, next);
}

fn root() -> PathBuf {
    match std::env::var("DECKS_DIR") {
        Ok(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => {
            let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
            Path::new(&home).join(".decks")
        }
    }
}

fn now() -> String {
    Timestamp::now().strftime("%Y-%m-%dT%H:%M:%SZ").to_string()
}

fn slugify(name: &str) -> String {
    let mut slug = String::new();
    let mut prev_dash = false;
    for ch in name.to_lowercase().chars() {
        if ch.is_alphanumeric() {
            slug.push(ch);
            prev_dash = false;
        } else if !prev_dash {
            slug.push('-');
            prev_dash = true;
        }
    }
    slug.trim_matches('-').to_string()
}

fn print_json<T: Serialize>(value: &T) {
    match serde_json::to_string_pretty(value) {
        Ok(json) => println!("{json}"),
        Err(error) => eprintln!("{error}"),
    }
}

fn read_decks() -> Vec<Deck> {
    let mut decks = Vec::new();
    let Ok(entries) = fs::read_dir(root()) else {
        return decks;
    };
    for entry in entries.flatten() {
        let meta = entry.path().join("deck.json");
        if let Ok(data) = fs::read_to_string(&meta)
            && let Ok(deck) = serde_json::from_str::<Deck>(&data)
        {
            decks.push(deck);
        }
    }
    decks.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    decks
}

fn read_todos(slug: &str) -> Vec<Todo> {
    fs::read_to_string(root().join(slug).join("todos.json"))
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}

fn read_links(slug: &str) -> Vec<Link> {
    fs::read_to_string(root().join(slug).join("links.json"))
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}

fn read_text(slug: &str, file: &str) -> String {
    fs::read_to_string(root().join(slug).join(file)).unwrap_or_default()
}

fn write_todos(slug: &str, todos: &[Todo]) {
    if let Ok(json) = serde_json::to_string_pretty(todos) {
        let _ = fs::write(root().join(slug).join("todos.json"), json);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn todo_uses_camel_case_and_omits_missing_done_at() {
        let todo = Todo {
            id: "ID".into(),
            text: "review".into(),
            done: false,
            created_at: "2026-06-08T20:00:00Z".into(),
            done_at: None,
        };
        let json = serde_json::to_string(&todo).unwrap();
        assert!(json.contains("\"createdAt\""));
        assert!(!json.contains("doneAt"));
    }

    #[test]
    fn todo_reads_back_without_done_at() {
        let json = r#"{"id":"ID","text":"review","done":true,"createdAt":"2026-06-08T20:00:00Z"}"#;
        let todo: Todo = serde_json::from_str(json).unwrap();
        assert!(todo.done);
        assert!(todo.done_at.is_none());
    }

    #[test]
    fn now_is_second_precision_utc() {
        let stamp = now();
        assert_eq!(stamp.len(), 20);
        assert!(stamp.ends_with('Z'));
    }

    #[test]
    fn slugify_matches_app_rules() {
        assert_eq!(slugify("Acme Corp"), "acme-corp");
        assert_eq!(slugify("  Hello!!  World  "), "hello-world");
        assert_eq!(slugify("---"), "");
    }

    #[test]
    fn mcp_config_targets_the_deck() {
        let value = mcp_config_value("nexus", "/bin/decks-mcp");
        assert_eq!(
            value["mcpServers"]["decks-nexus"]["command"],
            "/bin/decks-mcp"
        );
        assert_eq!(
            value["mcpServers"]["decks-nexus"]["args"],
            serde_json::json!(["--deck", "nexus"])
        );
    }
}
