use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command as Process;

use clap::{Parser, Subcommand};
use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Parser)]
#[command(
    name = "decks",
    version,
    about = "Per-project notes, shared with the Decks app"
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
    /// Summarize today's git activity in the deck's repos into its daily log
    Worklog { slug: String },
    /// Print the deck slug that owns a repository path
    Which { path: String },
    /// Add a link to a deck
    Link {
        slug: String,
        url: String,
        label: Vec<String>,
    },
    /// Remove a link by its position
    Unlink { slug: String, index: usize },
    /// Remove a to-do by its position
    Remove { slug: String, index: usize },
    /// Replace a to-do's text by its position
    Edit {
        slug: String,
        index: usize,
        text: Vec<String>,
    },
    /// Set the sidebar order of decks, most important first
    Reorder { slugs: Vec<String> },
    /// Set or clear a deck's parent (use - to clear)
    SetParent { slug: String, parent: String },
    /// Rename a deck
    Rename { slug: String, name: Vec<String> },
    /// Archive a deck
    Archive { slug: String },
    /// Unarchive a deck
    Unarchive { slug: String },
    /// Delete a deck and all its data
    Delete { slug: String },
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Deck {
    slug: String,
    name: String,
    created_at: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    archived: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    parent: Option<String>,
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

#[derive(Deserialize, Default)]
#[serde(rename_all = "camelCase")]
struct Profile {
    #[serde(default)]
    git_provider: String,
    #[serde(default)]
    author_email: String,
    #[serde(default)]
    folders: Vec<String>,
    #[serde(default)]
    instructions: String,
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
        Command::Worklog { slug } => worklog(&slug),
        Command::Which { path } => which(&path),
        Command::Link { slug, url, label } => link(&slug, &url, label.join(" ")),
        Command::Unlink { slug, index } => unlink(&slug, index),
        Command::Remove { slug, index } => remove(&slug, index),
        Command::Edit { slug, index, text } => edit(&slug, index, text.join(" ")),
        Command::Reorder { slugs } => write_order(&slugs),
        Command::SetParent { slug, parent } => set_parent(&slug, &parent),
        Command::Rename { slug, name } => rename(&slug, name.join(" ")),
        Command::Archive { slug } => set_archived(&slug, true),
        Command::Unarchive { slug } => set_archived(&slug, false),
        Command::Delete { slug } => delete(&slug),
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

fn worklog(slug: &str) {
    let profile = effective_profile(slug);
    if profile.folders.is_empty() {
        eprintln!("no folders configured for this deck");
        return;
    }
    let mut repos: Vec<String> = Vec::new();
    for folder in &profile.folders {
        repos.extend(repos_in(folder));
    }
    repos.sort();
    repos.dedup();

    let mut sections = Vec::new();
    for repo in &repos {
        if remote_ok(repo, &profile.git_provider) == Some(false) {
            eprintln!(
                "skipping {repo}: remote does not match provider \"{}\"",
                profile.git_provider
            );
            continue;
        }
        let commits = today_commits(repo, &profile.author_email);
        if commits.is_empty() {
            continue;
        }
        let name = Path::new(repo)
            .file_name()
            .and_then(|component| component.to_str())
            .unwrap_or(repo);
        sections.push(format!("{name}\n{commits}"));
    }
    if sections.is_empty() {
        eprintln!("no commits today in this deck's folders");
        return;
    }
    daily(slug, format!("### Worklog\n\n{}", sections.join("\n\n")));
    println!("added worklog to {slug}");
}

fn repos_in(folder: &str) -> Vec<String> {
    let mut repos = Vec::new();
    let path = Path::new(folder);
    if is_git_repo(path) {
        repos.push(folder.to_string());
    }
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let child = entry.path();
            if child.is_dir() && is_git_repo(&child) {
                repos.push(child.display().to_string());
            }
        }
    }
    repos
}

fn is_git_repo(path: &Path) -> bool {
    path.join(".git").exists()
}

fn which(path: &str) {
    let target = canonical(path);
    for deck in read_decks() {
        let profile = read_profile(&deck.slug);
        let owned = profile.folders.iter().any(|folder| {
            let root = canonical(folder);
            target == root || target.starts_with(&format!("{root}/"))
        });
        if owned {
            println!("{}", deck.slug);
            return;
        }
    }
}

fn set_parent(slug: &str, parent: &str) {
    let Some(mut deck) = read_deck(slug) else {
        eprintln!("no deck \"{slug}\"");
        return;
    };
    if parent == "-" || parent.is_empty() {
        deck.parent = None;
        write_deck(&deck);
        return;
    }
    if parent == slug {
        eprintln!("a deck cannot be its own parent");
        return;
    }
    let Some(target) = read_deck(parent) else {
        eprintln!("no deck \"{parent}\"");
        return;
    };
    if target.parent.is_some() {
        eprintln!("\"{parent}\" is already a sub-deck; nesting is one level deep");
        return;
    }
    if read_decks()
        .iter()
        .any(|d| d.parent.as_deref() == Some(slug))
    {
        eprintln!("\"{slug}\" has sub-decks; it cannot become one");
        return;
    }
    deck.parent = Some(parent.to_string());
    write_deck(&deck);
}

fn effective_profile(slug: &str) -> Profile {
    let mut profile = read_profile(slug);
    if let Some(parent) = read_deck(slug).and_then(|deck| deck.parent) {
        let inherited = read_profile(&parent);
        if profile.git_provider.is_empty() {
            profile.git_provider = inherited.git_provider;
        }
        if profile.author_email.is_empty() {
            profile.author_email = inherited.author_email;
        }
        if profile.instructions.is_empty() {
            profile.instructions = inherited.instructions;
        }
    }
    profile
}

fn read_profile(slug: &str) -> Profile {
    fs::read_to_string(root().join(slug).join("profile.json"))
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}

fn remote_ok(repo: &str, provider: &str) -> Option<bool> {
    let url = git(repo, &["remote", "get-url", "origin"])?;
    host_matches(provider, &url)
}

fn host_matches(provider: &str, url: &str) -> Option<bool> {
    match provider {
        "github" => Some(url.contains("github.com")),
        "gitlab" => Some(url.contains("gitlab.com")),
        _ => None,
    }
}

fn today_commits(repo: &str, author: &str) -> String {
    let mut args: Vec<String> = vec![
        "log".into(),
        "--since=midnight".into(),
        "--no-merges".into(),
        "--pretty=format:- %h %s".into(),
    ];
    if !author.is_empty() {
        args.push(format!("--author={author}"));
    }
    let refs: Vec<&str> = args.iter().map(String::as_str).collect();
    git(repo, &refs).unwrap_or_default()
}

fn git(repo: &str, args: &[&str]) -> Option<String> {
    let output = Process::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    (!text.is_empty()).then_some(text)
}

fn canonical(path: &str) -> String {
    fs::canonicalize(path)
        .map(|resolved| resolved.display().to_string())
        .unwrap_or_else(|_| path.to_string())
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
        #[serde(rename_all = "camelCase")]
        struct View {
            todos: Vec<Todo>,
            links: Vec<Link>,
            daily: String,
            notes: String,
            instructions: String,
            #[serde(skip_serializing_if = "Option::is_none")]
            parent: Option<String>,
            #[serde(skip_serializing_if = "Vec::is_empty")]
            shared_links: Vec<Link>,
        }
        let parent = read_deck(slug).and_then(|deck| deck.parent);
        let shared_links = parent.as_deref().map(read_links).unwrap_or_default();
        print_json(&View {
            todos,
            links: read_links(slug),
            daily: read_text(slug, "daily.md"),
            notes: read_text(slug, "notes.md"),
            instructions: effective_profile(slug).instructions,
            parent,
            shared_links,
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
        archived: None,
        parent: None,
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

fn edit(slug: &str, index: usize, text: String) {
    let text = text.trim();
    if text.is_empty() {
        eprintln!("nothing to set");
        return;
    }
    let mut todos = read_todos(slug);
    match todos.get_mut(index) {
        Some(todo) => {
            todo.text = text.to_string();
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
    let header = format!("## {date}\n\n");
    let next = if let Some(rest) = current.strip_prefix(&header) {
        format!("{header}{text}\n\n{rest}")
    } else if current.is_empty() {
        format!("{header}{text}\n\n")
    } else {
        format!("{header}{text}\n\n{current}")
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
    let order = read_order();
    if !order.is_empty() {
        decks.sort_by_key(|deck| {
            order
                .iter()
                .position(|s| s == &deck.slug)
                .unwrap_or(usize::MAX)
        });
    }
    decks
}

fn read_order() -> Vec<String> {
    fs::read_to_string(root().join("order.json"))
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}

fn write_order(slugs: &[String]) {
    if let Ok(json) = serde_json::to_string_pretty(slugs) {
        let _ = fs::write(root().join("order.json"), json);
    }
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

fn write_links(slug: &str, links: &[Link]) {
    if let Ok(json) = serde_json::to_string_pretty(links) {
        let _ = fs::write(root().join(slug).join("links.json"), json);
    }
}

fn link(slug: &str, url: &str, label: String) {
    let url = url.trim();
    if url.is_empty() {
        eprintln!("a url is required");
        return;
    }
    let label = label.trim();
    let label = if label.is_empty() {
        url.to_string()
    } else {
        label.to_string()
    };
    let mut links = read_links(slug);
    links.push(Link {
        id: Uuid::new_v4().to_string().to_uppercase(),
        label,
        url: url.to_string(),
        note: String::new(),
    });
    write_links(slug, &links);
}

fn unlink(slug: &str, index: usize) {
    let mut links = read_links(slug);
    if index < links.len() {
        links.remove(index);
        write_links(slug, &links);
    } else {
        eprintln!("no link at index {index}");
    }
}

fn remove(slug: &str, index: usize) {
    let mut todos = read_todos(slug);
    if index < todos.len() {
        todos.remove(index);
        write_todos(slug, &todos);
    } else {
        eprintln!("no to-do at index {index}");
    }
}

fn rename(slug: &str, name: String) {
    let name = name.trim();
    if name.is_empty() {
        eprintln!("a name is required");
        return;
    }
    match read_deck(slug) {
        Some(mut deck) => {
            deck.name = name.to_string();
            write_deck(&deck);
        }
        None => eprintln!("no deck \"{slug}\""),
    }
}

fn set_archived(slug: &str, archived: bool) {
    match read_deck(slug) {
        Some(mut deck) => {
            deck.archived = archived.then_some(true);
            write_deck(&deck);
        }
        None => eprintln!("no deck \"{slug}\""),
    }
}

fn delete(slug: &str) {
    let _ = fs::remove_dir_all(root().join(slug));
    for mut child in read_decks() {
        if child.parent.as_deref() == Some(slug) {
            child.parent = None;
            write_deck(&child);
        }
    }
    let order = read_order();
    if order.iter().any(|s| s == slug) {
        let pruned: Vec<String> = order.into_iter().filter(|s| s != slug).collect();
        write_order(&pruned);
    }
    let state_path = root().join("state.json");
    if let Ok(data) = fs::read_to_string(&state_path)
        && let Ok(mut state) = serde_json::from_str::<serde_json::Value>(&data)
        && state.get("active").and_then(serde_json::Value::as_str) == Some(slug)
    {
        state["active"] = serde_json::Value::Null;
        if let Ok(json) = serde_json::to_string_pretty(&state) {
            let _ = fs::write(&state_path, json);
        }
    }
}

fn read_deck(slug: &str) -> Option<Deck> {
    fs::read_to_string(root().join(slug).join("deck.json"))
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
}

fn write_deck(deck: &Deck) {
    if let Ok(json) = serde_json::to_string_pretty(deck) {
        let _ = fs::write(root().join(&deck.slug).join("deck.json"), json);
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

    #[test]
    fn host_matches_respects_provider() {
        assert_eq!(
            host_matches("github", "git@github.com-personal:me/x.git"),
            Some(true)
        );
        assert_eq!(
            host_matches("github", "https://gitlab.com/me/x.git"),
            Some(false)
        );
        assert_eq!(
            host_matches("gitlab", "git@gitlab.com:me/x.git"),
            Some(true)
        );
        assert_eq!(host_matches("other", "anything"), None);
    }

    #[test]
    fn profile_parses_swift_keys() {
        let json = r#"{"gitProvider":"gitlab","authorEmail":"me@equo.dev","folders":["/a","/b"],"accountID":"X"}"#;
        let profile: Profile = serde_json::from_str(json).unwrap();
        assert_eq!(profile.git_provider, "gitlab");
        assert_eq!(profile.author_email, "me@equo.dev");
        assert_eq!(profile.folders.len(), 2);
    }
}
