use std::io::{self, BufRead, Write};
use std::path::PathBuf;
use std::process::Command;

use serde_json::{Value, json};

fn main() {
    let scope = scope();
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    for line in stdin.lock().lines().map_while(Result::ok) {
        if line.trim().is_empty() {
            continue;
        }
        let Ok(message) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let Some(id) = message.get("id").cloned() else {
            continue;
        };
        let method = message.get("method").and_then(Value::as_str).unwrap_or("");

        let response = match method {
            "initialize" => success(&id, initialize(&message, scope.as_deref())),
            "tools/list" => success(&id, json!({ "tools": tools() })),
            "tools/call" => match call_tool(&message, scope.as_deref()) {
                Ok(text) => success(&id, content(&text, false)),
                Err(text) => success(&id, content(&text, true)),
            },
            "ping" => success(&id, json!({})),
            _ => error(&id, -32601, "method not found"),
        };

        let _ = writeln!(stdout, "{response}");
        let _ = stdout.flush();
    }
}

fn scope() -> Option<String> {
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        if arg == "--deck" {
            return args.next().filter(|value| !value.is_empty());
        }
        if let Some(value) = arg.strip_prefix("--deck=")
            && !value.is_empty()
        {
            return Some(value.to_string());
        }
    }
    std::env::var("DECKS_DECK")
        .ok()
        .filter(|value| !value.is_empty())
}

fn initialize(message: &Value, scope: Option<&str>) -> Value {
    let version = message
        .get("params")
        .and_then(|params| params.get("protocolVersion"))
        .and_then(Value::as_str)
        .unwrap_or("2025-06-18");
    let mut result = json!({
        "protocolVersion": version,
        "capabilities": { "tools": {} },
        "serverInfo": { "name": "decks", "version": env!("CARGO_PKG_VERSION") }
    });
    if let Some(deck) = scope {
        result["instructions"] = json!(format!(
            "This session is scoped to the \"{deck}\" deck only. Every tool operates on \"{deck}\". \
             You have no access to any other deck or context and must never reference, infer or reveal one."
        ));
    }
    result
}

fn tools() -> Value {
    let text = |description: &str| json!({ "type": "string", "description": description });
    let schema = |properties: Value, required: Value| json!({ "type": "object", "properties": properties, "required": required });
    json!([
        {
            "name": "list_decks",
            "description": "List decks with their open to-do counts.",
            "inputSchema": { "type": "object", "properties": {} }
        },
        {
            "name": "show_deck",
            "description": "Show a deck's to-dos, links, daily log, notes, and AI instructions. The instructions field defines how to write for this deck (language, daily format, tone) — follow it when drafting dailies or notes.",
            "inputSchema": schema(json!({ "slug": text("Deck slug") }), json!(["slug"]))
        },
        {
            "name": "create_deck",
            "description": "Create a deck from a name. Disabled in a scoped session.",
            "inputSchema": schema(json!({ "name": text("Deck name") }), json!(["name"]))
        },
        {
            "name": "add_todo",
            "description": "Add a to-do to a deck.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "text": text("To-do text") }),
                json!(["slug", "text"]),
            )
        },
        {
            "name": "complete_todo",
            "description": "Toggle a to-do done or undone by its position.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "index": { "type": "integer", "description": "To-do position" } }),
                json!(["slug", "index"]),
            )
        },
        {
            "name": "append_note",
            "description": "Append a line to a deck's notes.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "text": text("Note text") }),
                json!(["slug", "text"]),
            )
        },
        {
            "name": "add_daily_entry",
            "description": "Add a dated entry to a deck's daily log.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "text": text("Daily entry text") }),
                json!(["slug", "text"]),
            )
        },
        {
            "name": "add_link",
            "description": "Add a link to a deck.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "url": text("Link URL"), "label": text("Optional label") }),
                json!(["slug", "url"]),
            )
        },
        {
            "name": "remove_link",
            "description": "Remove a link from a deck by its position.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "index": { "type": "integer", "description": "Link position" } }),
                json!(["slug", "index"]),
            )
        },
        {
            "name": "remove_todo",
            "description": "Remove a to-do from a deck by its position.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "index": { "type": "integer", "description": "To-do position" } }),
                json!(["slug", "index"]),
            )
        },
        {
            "name": "rename_deck",
            "description": "Rename a deck.",
            "inputSchema": schema(
                json!({ "slug": text("Deck slug"), "name": text("New name") }),
                json!(["slug", "name"]),
            )
        },
        {
            "name": "archive_deck",
            "description": "Archive a deck.",
            "inputSchema": schema(json!({ "slug": text("Deck slug") }), json!(["slug"]))
        },
        {
            "name": "unarchive_deck",
            "description": "Unarchive a deck.",
            "inputSchema": schema(json!({ "slug": text("Deck slug") }), json!(["slug"]))
        },
        {
            "name": "delete_deck",
            "description": "Delete a deck and all its data.",
            "inputSchema": schema(json!({ "slug": text("Deck slug") }), json!(["slug"]))
        },
        {
            "name": "worklog",
            "description": "Summarize today's git activity in the deck's repos into its daily log.",
            "inputSchema": schema(json!({ "slug": text("Deck slug") }), json!(["slug"]))
        }
    ])
}

fn call_tool(message: &Value, scope: Option<&str>) -> Result<String, String> {
    let params = message.get("params").cloned().unwrap_or(Value::Null);
    let name = params.get("name").and_then(Value::as_str).unwrap_or("");
    let args = params
        .get("arguments")
        .cloned()
        .unwrap_or_else(|| json!({}));
    let arg = |key: &str| {
        args.get(key)
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string()
    };

    let resolve = |provided: String| -> Result<String, String> {
        match scope {
            Some(deck) if !provided.is_empty() && provided != deck => Err(format!(
                "this session is scoped to \"{deck}\"; access to \"{provided}\" is not allowed"
            )),
            Some(deck) => Ok(deck.to_string()),
            None if provided.is_empty() => Err("slug is required".to_string()),
            None => Ok(provided),
        }
    };

    match name {
        "list_decks" => {
            let listing = run(&["list", "--json"])?;
            match scope {
                Some(deck) => Ok(only_deck(&listing, deck)),
                None => Ok(listing),
            }
        }
        "show_deck" => {
            let slug = resolve(arg("slug"))?;
            run(&["show", slug.as_str(), "--json"])
        }
        "create_deck" => {
            if scope.is_some() {
                return Err("creating decks is disabled in a scoped session".to_string());
            }
            let name = arg("name");
            run(&["new", name.as_str()]).map(|_| "Deck created.".to_string())
        }
        "add_todo" => {
            let slug = resolve(arg("slug"))?;
            let text = arg("text");
            run(&["add", slug.as_str(), text.as_str()]).map(|_| "To-do added.".to_string())
        }
        "complete_todo" => {
            let slug = resolve(arg("slug"))?;
            let index = args
                .get("index")
                .and_then(Value::as_i64)
                .unwrap_or(-1)
                .to_string();
            run(&["done", slug.as_str(), index.as_str()]).map(|_| "To-do toggled.".to_string())
        }
        "append_note" => {
            let slug = resolve(arg("slug"))?;
            let text = arg("text");
            run(&["note", slug.as_str(), text.as_str()]).map(|_| "Note added.".to_string())
        }
        "add_daily_entry" => {
            let slug = resolve(arg("slug"))?;
            let text = arg("text");
            run(&["daily", slug.as_str(), text.as_str()]).map(|_| "Daily entry added.".to_string())
        }
        "add_link" => {
            let slug = resolve(arg("slug"))?;
            let url = arg("url");
            let label = arg("label");
            if label.is_empty() {
                run(&["link", slug.as_str(), url.as_str()]).map(|_| "Link added.".to_string())
            } else {
                run(&["link", slug.as_str(), url.as_str(), label.as_str()])
                    .map(|_| "Link added.".to_string())
            }
        }
        "remove_link" => {
            let slug = resolve(arg("slug"))?;
            let index = args
                .get("index")
                .and_then(Value::as_i64)
                .unwrap_or(-1)
                .to_string();
            run(&["unlink", slug.as_str(), index.as_str()]).map(|_| "Link removed.".to_string())
        }
        "remove_todo" => {
            let slug = resolve(arg("slug"))?;
            let index = args
                .get("index")
                .and_then(Value::as_i64)
                .unwrap_or(-1)
                .to_string();
            run(&["remove", slug.as_str(), index.as_str()]).map(|_| "To-do removed.".to_string())
        }
        "rename_deck" => {
            let slug = resolve(arg("slug"))?;
            let name = arg("name");
            run(&["rename", slug.as_str(), name.as_str()]).map(|_| "Deck renamed.".to_string())
        }
        "archive_deck" => {
            let slug = resolve(arg("slug"))?;
            run(&["archive", slug.as_str()]).map(|_| "Deck archived.".to_string())
        }
        "unarchive_deck" => {
            let slug = resolve(arg("slug"))?;
            run(&["unarchive", slug.as_str()]).map(|_| "Deck unarchived.".to_string())
        }
        "delete_deck" => {
            let slug = resolve(arg("slug"))?;
            run(&["delete", slug.as_str()]).map(|_| "Deck deleted.".to_string())
        }
        "worklog" => {
            let slug = resolve(arg("slug"))?;
            run(&["worklog", slug.as_str()])
        }
        other => Err(format!("unknown tool: {other}")),
    }
}

fn only_deck(listing: &str, deck: &str) -> String {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(listing) else {
        return "[]".to_string();
    };
    let kept: Vec<Value> = items
        .into_iter()
        .filter(|item| item.get("slug").and_then(Value::as_str) == Some(deck))
        .collect();
    serde_json::to_string_pretty(&kept).unwrap_or_else(|_| "[]".to_string())
}

fn run(args: &[&str]) -> Result<String, String> {
    let output = Command::new(decks_bin())
        .args(args)
        .output()
        .map_err(|err| format!("failed to run decks: {err}"))?;
    if output.status.success() {
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&output.stderr).trim().to_string())
    }
}

fn decks_bin() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|exe| exe.parent().map(|dir| dir.join("decks")))
        .filter(|path| path.exists())
        .unwrap_or_else(|| PathBuf::from("decks"))
}

fn content(text: &str, is_error: bool) -> Value {
    json!({ "content": [{ "type": "text", "text": text }], "isError": is_error })
}

fn success(id: &Value, result: Value) -> String {
    json!({ "jsonrpc": "2.0", "id": id, "result": result }).to_string()
}

fn error(id: &Value, code: i64, message: &str) -> String {
    json!({ "jsonrpc": "2.0", "id": id, "error": { "code": code, "message": message } }).to_string()
}
