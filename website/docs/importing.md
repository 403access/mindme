---
title: Importing conversations
description: Supported export formats, the OpenCode library, and MINDME's generic JSON schema.
---

# Importing conversations

MINDME normalizes every source into one local library. Drag files or whole folders onto the
window, use **File → Import** (⌘I), or drop a database file directly. On iPhone, use the import
button in the top bar and pick the same files or a whole folder from the Files app.

| Source | Where to get it | File to import |
| --- | --- | --- |
| ChatGPT | Settings → Data controls → Export data | `conversations.json` |
| Gemini | Google Takeout → My Activity → Gemini Apps | `My Activity.json` (or the Takeout folder) |
| Claude | Settings → Privacy → Export data | `conversations.json` |
| OpenCode | Already on this Mac (or pick the `.db` on iPhone) | File → Import OpenCode Sessions (⌘⇧O), or drop `opencode.db` |
| Any tool | MINDME generic schema | a `.json` file with a `threads` array |

Small synthetic exports for every format live in
[`MindMap/Samples`](https://github.com/403access/mindme/tree/main/MindMap/Samples) — drag one
onto the app to try the importer without sharing your own data.

## How each format is read

- **ChatGPT** — follows the active branch from `current_node` through parents, skipping
  hidden/system nodes. Abandoned regenerations are not imported.
- **Gemini activity** — prompts are grouped by their conversation URL, falling back to a
  per-day bucket. Takeout generally contains prompts but not model responses, so these
  threads are prompt-only.
- **Gemini HTML** — parsed best-effort; the JSON export is more reliable.
- **Claude** — reads the standard `conversations.json` export.
- **Generic** — a documented schema you can produce from any tool.
- **OpenCode** — read-only access to the local SQLite library.

## OpenCode

OpenCode stores its history in `~/.local/share/opencode/opencode.db`. MINDME opens that
database **read-only in place** (nothing is copied) and normalizes the **150 most recently
active top-level sessions**, including human prompts and assistant text.

Subagent sessions, reasoning traces, tool calls, patches, and snapshots are intentionally
excluded. The import takes under a second for a typical library; import again with **⌘⇧O**
to merge newer sessions.

The importer reads the `session_v2` / `session_message` schema used by current OpenCode
releases. The session limit is `OpenCodeImporter.defaultSessionLimit`, and per-thread message
caps live alongside it in `Core/Sources/MindMapCore/Import/OpenCodeImporter.swift`.

## Generic schema

```json
{
  "threads": [
    {
      "id": "conversation-123",
      "provider": "gemini",
      "title": "Designing a solar punk transit map",
      "createdAt": "2026-03-01T10:00:00Z",
      "model": "gemini-3-pro",
      "messages": [
        { "role": "user", "text": "How do I start?", "timestamp": "2026-03-01T10:00:00Z" },
        { "role": "assistant", "text": "Start from topology…" }
      ]
    }
  ]
}
```

`provider` accepts `chatgpt`, `gemini`, `claude`, `opencode`, or anything else (shown as
*Other*). If `provider` is omitted, MINDME infers it from the filename when possible.

## Where the library lives

Imported data is normalized into
`~/Library/Application Support/MindMap/library.json`. Use **File → Reveal Library in Finder**
to inspect or delete it. There is no networking code in the app.

## Import limits

- OpenCode imports the 150 most recent top-level sessions. Very large coding sessions are
  trimmed to the first 10 + last 50 messages, and individual messages are capped at 5,000
  characters so the library stays responsive.
- The map renders at most 420 conversations at once. Use source/time/search filters for very
  large archives.
- Importing real data clears the demo dataset automatically. **File → Load Demo Dataset**
  restores it at any time.
