#!/usr/bin/env python3
"""Convert a Google Takeout "My Activity > Gemini Apps" JSON export into
per-conversation Markdown files plus a JSONL dump.

Usage:
    python3 scripts/gemini_takeout_export.py "<path to My Activity.json>" [outdir]
"""

import json
import os
import re
import shutil
import sys
import unicodedata
from collections import defaultdict
from urllib.parse import urlparse

from bs4 import BeautifulSoup, NavigableString, Tag

CONV_RE = re.compile(r"gemini\.google\.com/app/([0-9a-z]+)")


# --------------------------------------------------------------------------
# HTML -> Markdown
# --------------------------------------------------------------------------

BLOCK_TAGS = {
    "p", "div", "section", "article", "header", "footer", "ul", "ol", "pre",
    "table", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6", "hr",
}


def _inline(node, ctx):
    """Serialize mixed content to markdown, preserving inline formatting."""
    out = []
    for child in node.children:
        if isinstance(child, NavigableString):
            out.append(str(child))
            continue
        if not isinstance(child, Tag):
            continue
        name = child.name.lower()
        if name == "br":
            out.append("  \n")
        elif name in ("strong", "b"):
            out.append(f"**{_inline(child, ctx).strip()}**")
        elif name in ("em", "i"):
            out.append(f"*{_inline(child, ctx).strip()}*")
        elif name in ("del", "s", "strike"):
            out.append(f"~~{_inline(child, ctx).strip()}~~")
        elif name == "code":
            text = child.get_text()
            tick = "``" if "`" in text else "`"
            out.append(f"{tick}{text}{tick}")
        elif name == "a":
            text = _inline(child, ctx).strip()
            href = child.get("href", "")
            out.append(f"[{text}]({href})" if href else text)
        elif name == "img":
            src = child.get("src", "")
            alt = (child.get("alt") or "").strip() or "image"
            out.append(f"![{alt}]({src})" if src else "")
        elif name in BLOCK_TAGS:
            out.append(_block(child, ctx))
        else:
            out.append(_inline(child, ctx))
    return "".join(out)


def _table(node, ctx):
    rows = []
    for tr in node.find_all("tr"):
        cells = [
            _inline(td, ctx).replace("\n", " ").strip()
            for td in tr.find_all(["th", "td"])
        ]
        if cells:
            rows.append(cells)
    if not rows:
        return ""
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    lines = ["| " + " | ".join(rows[0]) + " |",
             "| " + " | ".join(["---"] * width) + " |"]
    for r in rows[1:]:
        lines.append("| " + " | ".join(r) + " |")
    return "\n" + "\n".join(lines) + "\n\n"


def _block(node, ctx):
    name = node.name.lower()
    if name == "pre":
        code = node.find("code") if node.find("code") else node
        text = code.get_text().rstrip("\n")
        lang = ""
        for cls in (code.get("class") or []):
            if cls.startswith("language-"):
                lang = cls[len("language-"):]
        fence = "```"
        while fence in text:
            fence += "`"
        return f"\n{fence}{lang}\n{text}\n{fence}\n\n"
    if name == "hr":
        return "\n---\n\n"
    if name in ("h1", "h2", "h3", "h4", "h5", "h6"):
        level = int(name[1]) + ctx["heading_offset"]
        level = min(level, 6)
        return f"\n{'#' * level} {_inline(node, ctx).strip()}\n\n"
    if name in ("ul", "ol"):
        lines = []
        ordered = name == "ol"
        for i, li in enumerate(node.find_all("li", recursive=False), 1):
            body = _inline(li, ctx).strip()
            body = re.sub(r"\n{3,}", "\n\n", body)
            body = body.replace("\n", "\n" + "  " * (ctx["indent"] + 1))
            bullet = f"{i}." if ordered else "-"
            lines.append(f"{'  ' * ctx['indent']}{bullet} {body}")
        return "\n" + "\n".join(lines) + "\n\n"
    if name == "blockquote":
        body = _block_content(node, ctx).strip()
        quoted = "\n".join("> " + line for line in body.splitlines())
        return f"\n{quoted}\n\n"
    if name == "table":
        return _table(node, ctx)
    if name in ("p", "div", "section", "article"):
        body = _block_content(node, ctx).strip()
        return f"\n\n{body}\n\n" if body else "\n\n"
    return _block_content(node, ctx)


def _block_content(node, ctx):
    out = []
    for child in node.children:
        if isinstance(child, NavigableString):
            text = str(child)
            if text.strip():
                out.append(text.replace("\n", " "))
            continue
        if isinstance(child, Tag):
            out.append(_block(child, ctx))
    return "".join(out)


def html_to_md(html, heading_offset=2):
    if not html or not html.strip():
        return ""
    soup = BeautifulSoup(html, "html.parser")
    ctx = {"heading_offset": heading_offset, "indent": 0}
    md = _block_content(soup, ctx)
    md = re.sub(r"[ \t]+\n", "\n", md)
    md = re.sub(r"\n{3,}", "\n\n", md)
    return md.strip()


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def slugify(text, max_len=60):
    text = text.split("|")[0]
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii").lower()
    text = re.sub(r"`{1,}", "", text)
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    if len(text) > max_len:
        cut = text[:max_len]
        text = cut.rsplit("-", 1)[0] if "-" in cut else cut
    return text or "conversation"


def looks_like_code(text):
    lines = text.splitlines()
    if len(lines) < 2:
        return text.lstrip().startswith("<") and text.rstrip().endswith(">")
    marked = sum(1 for ln in lines if ln.lstrip().startswith(("<", "}", "*/", "@")))
    return marked >= max(2, len(lines) // 4)


def fence(text, lang=""):
    body = text.rstrip("\n")
    f = "````"
    while f in body:
        f += "`"
    return f"{f}{lang}\n{body}\n{f}"


def conv_id_of(record):
    for detail in record.get("details", []):
        m = CONV_RE.search(detail.get("name", ""))
        if m:
            return m.group(1)
    return None


# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------

def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = os.path.abspath(sys.argv[1])
    outroot = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else "gemini-export")
    media_src = os.path.dirname(src)

    with open(src, encoding="utf-8") as fh:
        records = json.load(fh)

    conversations = defaultdict(list)
    turns_by_conv = defaultdict(list)
    orphans = []
    skipped_events = []

    for rec in records:
        title = rec.get("title", "")
        kind = title.split(" ", 1)[0]
        if kind != "Prompted":
            skipped_events.append(rec)
            continue
        cid = conv_id_of(rec)
        if not cid:
            orphans.append(rec)
            continue
        conversations[cid].append(rec)

    conv_dir = os.path.join(outroot, "conversations")
    files_dir = os.path.join(outroot, "attachments")
    os.makedirs(conv_dir, exist_ok=True)

    # Move (not copy) media next to the markdown so links stay relative.
    moved = 0
    if os.path.isdir(media_src) and not os.path.isdir(files_dir):
        os.makedirs(files_dir, exist_ok=True)
        for entry in os.listdir(media_src):
            if entry == os.path.basename(src):
                continue
            path = os.path.join(media_src, entry)
            if os.path.isfile(path):
                shutil.move(path, os.path.join(files_dir, entry))
                moved += 1

    index_rows = []
    jsonl_path = os.path.join(outroot, "conversations.jsonl")

    with open(jsonl_path, "w", encoding="utf-8") as jsonl:
        for cid, recs in conversations.items():
            recs.sort(key=lambda r: r["time"])
            first = recs[0]
            prompt0 = first["title"][len("Prompted "):] if first["title"].startswith("Prompted ") else first["title"]
            slug = slugify(prompt0)
            date = first["time"][:10]
            fname = f"{date}-{slug}-{cid[:8]}.md"

            linked = []
            md = []
            md.append("---")
            md.append(f"conversation_id: {cid}")
            md.append(f"started: {first['time']}")
            md.append(f"last_activity: {recs[-1]['time']}")
            md.append(f"turns: {len(recs)}")
            md.append(f"url: https://gemini.google.com/app/{cid}")
            md.append("---")
            md.append("")
            md.append(f"# {prompt0.splitlines()[0][:120]}")
            md.append("")

            for rec in recs:
                prompt = rec["title"][len("Prompted "):] if rec["title"].startswith("Prompted ") else rec["title"]
                response_html = "".join(item.get("html", "") for item in rec.get("safeHtmlItem", []))
                response_md = html_to_md(response_html, heading_offset=2)

                attachments = []
                for sub in rec.get("subtitles", []):
                    url = sub.get("url")
                    if url:
                        attachments.append(url)
                for name in rec.get("attachedFiles", []):
                    if name not in attachments:
                        attachments.append(name)
                img = rec.get("imageFile")
                if img and img not in attachments:
                    attachments.append(img)

                md.append(f"### 🧑 User — {rec['time'][:19].replace('T', ' ')} UTC")
                md.append("")
                if looks_like_code(prompt):
                    md.append(fence(prompt))
                else:
                    md.append(prompt.strip())
                md.append("")
                if attachments:
                    md.append("**Attachments**")
                    md.append("")
                    for name in attachments:
                        target = f"../attachments/{name}"
                        linked.append(name)
                        if name.lower().endswith((".png", ".jpg", ".jpeg", ".gif", ".webp", ".heic")):
                            md.append(f"![{name}](<{target}>)")
                        else:
                            md.append(f"- [{name}](<{target}>)")
                    md.append("")
                md.append("### ✨ Gemini")
                md.append("")
                md.append(response_md if response_md else "_(no response recorded)_")
                md.append("")

                jsonl.write(json.dumps({
                    "conversation_id": cid,
                    "conversation_url": f"https://gemini.google.com/app/{cid}",
                    "time": rec["time"],
                    "prompt": prompt,
                    "response_markdown": response_md,
                    "attachments": attachments,
                }, ensure_ascii=False) + "\n")

            with open(os.path.join(conv_dir, fname), "w", encoding="utf-8") as fh:
                fh.write("\n".join(md))

            index_rows.append({
                "date": date,
                "last": recs[-1]["time"][:10],
                "turns": len(recs),
                "title": prompt0.splitlines()[0][:110],
                "file": f"conversations/{fname}",
            })

    index_rows.sort(key=lambda r: r["last"], reverse=True)

    with open(os.path.join(outroot, "index.md"), "w", encoding="utf-8") as fh:
        fh.write("# Gemini conversation export\n\n")
        fh.write(f"- Conversations: **{len(conversations)}**\n")
        fh.write(f"- Prompt/response turns: **{sum(len(v) for v in conversations.values())}**\n")
        fh.write(f"- First activity: {min(r['time'] for r in records)}\n")
        fh.write(f"- Last activity: {max(r['time'] for r in records)}\n")
        fh.write(f"- Media/files: {moved}\n\n")
        fh.write("| Last activity | Turns | Conversation |\n|---|---|---|\n")
        for row in index_rows:
            title = row["title"].replace("|", "\\|")
            fh.write(f"| {row['last']} | {row['turns']} | [{title}]({row['file']}) |\n")

    print(f"conversations: {len(conversations)}")
    print(f"turns:         {sum(len(v) for v in conversations.values())}")
    print(f"media moved:   {moved}")
    print(f"skipped events (non-prompt): {len(skipped_events)}")
    print(f"prompts without conversation id: {len(orphans)}")
    print(f"output:        {outroot}")


if __name__ == "__main__":
    main()
