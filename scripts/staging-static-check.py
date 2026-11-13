#!/usr/bin/env python3
"""Static safety checks for the isolated PLAYAM Staging browser app."""
from html.parser import HTMLParser
from pathlib import Path
import re
import subprocess
import tempfile

APP = Path("index.html")
if not APP.exists():
    raise SystemExit("FAIL: index.html is missing")

source = APP.read_text(encoding="utf-8")
required = [
    "pwnjrdedeoxbmtfywhkk",
    "create_playam_room",
    "join_playam_room",
    "get_playam_lobby",
    "set_playam_ready",
    "start_playam_game",
    "submit_playam_answer",
    "advance_playam_round",
    "has_playam_submitted",
    "list_room_report_targets",
    "submit_player_report",
]
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit("FAIL: required Staging configuration/features missing: " + ", ".join(missing))

if "erjxmesxmmmaxivvmbsi" in source:
    raise SystemExit("FAIL: Production Supabase project reference found in Staging app")

if re.search(r"service_role|sb_secret_[A-Za-z0-9_-]+", source, re.I):
    raise SystemExit("FAIL: server-only Supabase credential marker found in browser app")

scoped_calls = [
    r'rpc\(["\']set_playam_ready["\']\s*,\s*\{[^}]*p_code\s*:\s*currentRoomCode',
    r'rpc\(["\']start_playam_game["\']\s*,\s*\{[^}]*p_code\s*:\s*currentRoomCode',
    r'rpc\(["\']submit_playam_answer["\']\s*,\s*\{[^}]*p_code\s*:\s*currentRoomCode',
    r'rpc\(["\']advance_playam_round["\']\s*,\s*\{[^}]*p_code\s*:\s*currentRoomCode',
]
for pattern in scoped_calls:
    if not re.search(pattern, source):
        raise SystemExit("FAIL: a gameplay RPC is not scoped to the active room")

class InlineScripts(HTMLParser):
    def __init__(self):
        super().__init__()
        self.capture = False
        self.current = []
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "script":
            attrs = dict(attrs)
            self.capture = "src" not in attrs and attrs.get("type", "").lower() not in ("application/json", "application/ld+json")
            self.current = []

    def handle_data(self, data):
        if self.capture:
            self.current.append(data)

    def handle_endtag(self, tag):
        if tag.lower() == "script":
            if self.capture:
                self.scripts.append("".join(self.current))
            self.capture = False
            self.current = []

parser = InlineScripts()
parser.feed(source)
if not parser.scripts:
    raise SystemExit("FAIL: no inline application JavaScript found")

for index, js in enumerate(parser.scripts, start=1):
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as handle:
        handle.write(js)
        handle.flush()
        result = subprocess.run(["node", "--check", handle.name], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(f"FAIL: inline JavaScript block {index} has a syntax error:\\n{result.stderr}")

print(f"PASS: Staging-only configuration, {len(required)} required features, room-scoped gameplay calls, and {len(parser.scripts)} inline JavaScript block(s).")
