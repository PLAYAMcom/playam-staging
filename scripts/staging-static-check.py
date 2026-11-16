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
PUBLISHED_APP = Path("site/game.html")
ADMIN_APP = Path("site/admin-playam-staging.html")
FLOW_APP = Path("site/flow.html")
LANDING_PAGE = Path("site/index.html")
if not PUBLISHED_APP.exists():
    raise SystemExit("FAIL: published Staging game page is missing")
if PUBLISHED_APP.read_text(encoding="utf-8") != source:
    raise SystemExit("FAIL: published game page is not identical to the reviewed root app")
if not ADMIN_APP.exists():
    raise SystemExit("FAIL: existing Staging admin dashboard is missing")
if not FLOW_APP.exists():
    raise SystemExit("FAIL: PLAYAM Flow Staging interface is missing")
if not LANDING_PAGE.exists():
    raise SystemExit("FAIL: Staging landing page is missing")
landing_source = LANDING_PAGE.read_text(encoding="utf-8")
for link in ('href="game.html"', 'href="admin-playam-staging.html"', 'href="game-catalogue.html"'):
    if link not in landing_source:
        raise SystemExit("FAIL: Staging landing page is missing a required link: " + link)
admin_source = ADMIN_APP.read_text(encoding="utf-8")
if "pwnjrdedeoxbmtfywhkk" not in admin_source or "erjxmesxmmmaxivvmbsi" in admin_source:
    raise SystemExit("FAIL: admin dashboard is not isolated to Staging")
for marker in ("mfa.verify", "get_playam_admin_overview", "admin_list_player_reports", "admin_review_player_report"):
    if marker not in admin_source:
        raise SystemExit("FAIL: admin dashboard is missing a required protected workflow: " + marker)
flow_source = FLOW_APP.read_text(encoding="utf-8")
if "pwnjrdedeoxbmtfywhkk" not in flow_source or "erjxmesxmmmaxivvmbsi" in flow_source:
    raise SystemExit("FAIL: Flow interface is not isolated to Staging")
if re.search(r"service_role|sb_secret_[A-Za-z0-9_-]+|sk_(live|test)_[A-Za-z0-9]+", flow_source, re.I):
    raise SystemExit("FAIL: server-only credential marker found in Flow interface")
for page_name, page_source in (("game", source), ("admin", admin_source), ("flow", flow_source)):
    if "erjxmesxmmmaxivvmbsi" in page_source:
        raise SystemExit("FAIL: Production project reference found in Staging " + page_name + " page")
    if re.search(r"service_role|sb_secret_[A-Za-z0-9_-]+|sk_(live|test)_[A-Za-z0-9]+", page_source, re.I):
        raise SystemExit("FAIL: server-only credential marker found in Staging " + page_name + " page")

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
    "playam_get_available_markets_v1",
    "playam_set_user_market_preference_v1",
    "playamMarketCountry",
    "savePlayamMarketPreference",
]
missing = [item for item in required if item not in source]
if missing:
    raise SystemExit("FAIL: required Staging configuration/features missing: " + ", ".join(missing))

if "erjxmesxmmmaxivvmbsi" in source:
    raise SystemExit("FAIL: Production Supabase project reference found in Staging app")

# Keep responsive desktop and mobile layouts covered by the Staging gate.
desktop_markers = (
    "PLAYAM desktop and wide-screen experience",
    "@media(min-width:761px)",
    "#gamesScreen .catalogue-grid",
    "#videoScreen #videoFeed",
    "#videoScreen .video-feed{max-width:none}",
    ".dm-layout",
    ".sidebar{\n  position:sticky",
    "#videoScreen .video-feed{max-width:none}",
    "#bottomNav{display:none}",
    "#bottomNav{position:fixed",
    "#videoScreen #videoFeed{grid-template-columns:repeat(3,minmax(0,1fr))",
)
missing_desktop = [marker for marker in desktop_markers if marker not in source]
if missing_desktop:
    raise SystemExit("FAIL: desktop layout regression marker(s) missing: " + ", ".join(missing_desktop))
if "@media(max-width:760px)" not in source:
    raise SystemExit("FAIL: mobile responsive layout breakpoint is missing")

# The separately published Staging admin and Flow workspaces also need desktop rules.
for page_path, marker in (
    (ADMIN_APP, "PLAYAM admin desktop workspace"),
    (FLOW_APP, "PLAYAM Flow desktop workspace"),
):
    page_text = page_path.read_text(encoding="utf-8")
    if marker not in page_text or "@media(min-width:900px)" not in page_text:
        raise SystemExit("FAIL: published desktop workspace rules missing from " + str(page_path))
    if "@media(min-width:1450px)" not in page_text:
        raise SystemExit("FAIL: wide-screen workspace rules missing from " + str(page_path))
if "@media(max-width:520px)" not in admin_source:
    raise SystemExit("FAIL: admin mobile layout breakpoint is missing")
if "max-width:1440px" not in admin_source or "max-width:1200px" not in flow_source:
    raise SystemExit("FAIL: desktop workspace content widths are missing")

if re.search(r"service_role|sb_secret_[A-Za-z0-9_-]+", source, re.I):
    raise SystemExit("FAIL: server-only Supabase credential marker found in browser app")

scoped_calls = [
    r'rpc\(["\']set_playam_ready["\']\s*,\s*\{[^}]*p_code\s*:\s*(?:currentRoomCode|requestedRoomCode)',
    r'rpc\(["\']start_playam_game["\']\s*,\s*\{[^}]*p_code\s*:\s*(?:currentRoomCode|requestedRoomCode)',
    r'rpc\(["\']submit_playam_answer["\']\s*,\s*\{[^}]*p_code\s*:\s*(?:currentRoomCode|requestedRoomCode)',
    r'rpc\(["\']advance_playam_round["\']\s*,\s*\{[^}]*p_code\s*:\s*(?:currentRoomCode|requestedRoomCode)',
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
