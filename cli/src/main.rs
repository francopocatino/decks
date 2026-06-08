use std::fs;
use std::path::{Path, PathBuf};

use clap::{Parser, Subcommand};
use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Parser)]
#[command(name = "decks", version, about = "Per-company notes, shared with the Decks app")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// List every deck with its open to-do count
    List,
    /// Print a deck's to-dos
    Show { slug: String },
    /// Add a to-do to a deck
    Add { slug: String, text: Vec<String> },
    /// Toggle a to-do by its position
    Done { slug: String, index: usize },
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

fn main() {
    match Cli::parse().command {
        Command::List => list(),
        Command::Show { slug } => show(&slug),
        Command::Add { slug, text } => add(&slug, text.join(" ")),
        Command::Done { slug, index } => done(&slug, index),
    }
}

fn list() {
    for deck in read_decks() {
        let open = read_todos(&deck.slug).iter().filter(|todo| !todo.done).count();
        println!("{:<18} {:>2} open  ({})", deck.name, open, deck.slug);
    }
}

fn show(slug: &str) {
    for todo in read_todos(slug) {
        let mark = if todo.done { "x" } else { " " };
        println!("[{mark}] {}", todo.text);
    }
}

fn add(slug: &str, text: String) {
    if text.trim().is_empty() {
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

fn read_decks() -> Vec<Deck> {
    let mut decks = Vec::new();
    let Ok(entries) = fs::read_dir(root()) else {
        return decks;
    };
    for entry in entries.flatten() {
        let meta = entry.path().join("deck.json");
        if let Ok(data) = fs::read_to_string(&meta) {
            if let Ok(deck) = serde_json::from_str::<Deck>(&data) {
                decks.push(deck);
            }
        }
    }
    decks.sort_by(|a, b| a.created_at.cmp(&b.created_at));
    decks
}

fn todos_path(slug: &str) -> PathBuf {
    root().join(slug).join("todos.json")
}

fn read_todos(slug: &str) -> Vec<Todo> {
    fs::read_to_string(todos_path(slug))
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}

fn write_todos(slug: &str, todos: &[Todo]) {
    if let Ok(json) = serde_json::to_string_pretty(todos) {
        let _ = fs::write(todos_path(slug), json);
    }
}
