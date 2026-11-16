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
ROOT_ADMIN_APP = Path("admin-playam-staging.html")
CATALOGUE_PAGE = Path("site/game-catalogue.html")
FLOW_APP = Path("site/flow.html")
LANDING_PAGE = Path("site/index.html")
MESSAGE_IDEMPOTENCY_MIGRATION = Path("supabase/migrations/20261116081500_idempotent_private_message_delivery.sql")
LOBBY_CONCURRENCY_MIGRATION = Path("supabase/migrations/20261116121500_serialize_playam_lobby_ready_updates.sql")
if not PUBLISHED_APP.exists():
    raise SystemExit("FAIL: published Staging game page is missing")
if PUBLISHED_APP.read_text(encoding="utf-8") != source:
    raise SystemExit("FAIL: published game page is not identical to the reviewed root app")
if not ADMIN_APP.exists() or not ROOT_ADMIN_APP.exists():
    raise SystemExit("FAIL: existing Staging admin dashboard is missing")
if not CATALOGUE_PAGE.exists():
    raise SystemExit("FAIL: Staging game catalogue is missing")
if not FLOW_APP.exists():
    raise SystemExit("FAIL: PLAYAM Flow Staging interface is missing")
if not LANDING_PAGE.exists():
    raise SystemExit("FAIL: Staging landing page is missing")
if not MESSAGE_IDEMPOTENCY_MIGRATION.exists():
    raise SystemExit("FAIL: private-message idempotency migration is missing")
if not LOBBY_CONCURRENCY_MIGRATION.exists():
    raise SystemExit("FAIL: lobby concurrency migration is missing")
lobby_migration = LOBBY_CONCURRENCY_MIGRATION.read_text(encoding="utf-8")
for marker in ("FOR UPDATE OF r", "r.code=upper(btrim(coalesce(p_code,'')))", "GRANT EXECUTE ON FUNCTION public.set_playam_ready(boolean,text) TO authenticated"):
    if marker not in lobby_migration:
        raise SystemExit("FAIL: lobby readiness concurrency protection missing: " + marker)



# Withdrawal retries must match the original amount and payout destination.
WITHDRAWAL_IDEMPOTENCY_MIGRATION = Path("supabase/migrations/20261116134500_bind_withdrawal_idempotency_to_request_payload.sql")
if not WITHDRAWAL_IDEMPOTENCY_MIGRATION.exists():
    raise SystemExit("FAIL: withdrawal idempotency migration is missing")
withdrawal_sql = WITHDRAWAL_IDEMPOTENCY_MIGRATION.read_text(encoding="utf-8")
for marker in (
    "v_existing_amount<>p_amount_minor",
    "v_existing_destination IS DISTINCT FROM p_destination_id",
    "ON CONFLICT(idempotency_key) DO NOTHING",
    "FOR UPDATE",
    "withdrawal-reserve:",
    "withdrawal_requested_and_reserved",
    "Recheck after acquiring the wallet lock",
):
    if marker.lower() not in withdrawal_sql.lower():
        raise SystemExit("FAIL: withdrawal idempotency invariant missing: " + marker)

# Verify financial ledger idempotency is safe under concurrent retries.
FINANCIAL_IDEMPOTENCY_MIGRATION = Path("supabase/migrations/20261116133000_make_financial_entry_idempotency_concurrency_safe.sql")
if not FINANCIAL_IDEMPOTENCY_MIGRATION.exists():
    raise SystemExit("FAIL: financial idempotency migration is missing")
financial_sql = FINANCIAL_IDEMPOTENCY_MIGRATION.read_text(encoding="utf-8")
for marker in (
    "ON CONFLICT (idempotency_key) DO NOTHING",
    "RETURNING id INTO v_id",
    "Idempotency key already used for a different financial entry",
    "Verified administrator MFA (aal2) is required",
    "Finance administrator permission required",
    "SET search_path=''",
):
    if marker.lower() not in financial_sql.lower():
        raise SystemExit("FAIL: financial idempotency invariant missing: " + marker)

# Verify the readiness lock coordinates with the existing join/start room locks.
# These function definitions are in the earlier Staging RPC migration.
GAME_RPC_MIGRATION = Path("supabase/migrations/20261113151913_scope_game_actions_and_enforce_level_eligibility.sql")
if not GAME_RPC_MIGRATION.exists():
    raise SystemExit("FAIL: room-scoped gameplay RPC migration is missing")
game_rpc_migration = GAME_RPC_MIGRATION.read_text(encoding="utf-8")
def function_definition(sql, function_name):
    match = re.search(
        r"create\s+or\s+replace\s+function\s+public\." + re.escape(function_name) + r"\b.*?\$\$;",
        sql, re.I | re.S
    )
    if not match:
        raise SystemExit("FAIL: required database function definition missing: " + function_name)
    return match.group(0)
join_rpc = function_definition(game_rpc_migration, "join_playam_room")
start_rpc = function_definition(game_rpc_migration, "start_playam_game")
for function_name, definition, marker in (
    ("join_playam_room", join_rpc, "for update"),
    ("start_playam_game", start_rpc, "for update of r"),
):
    if marker not in definition.lower():
        raise SystemExit("FAIL: " + function_name + " does not serialize on the room row")
for marker in (
    "p.auth_user_id=v_uid",
    "coalesce(r.game_status,r.status)='waiting'",
    "FOR UPDATE OF r",
    "UPDATE public.players",
    "WHERE id=v_player_id AND room_id=v_room_id",
    "SECURITY DEFINER",
    "SET search_path=''",
):
    if marker.lower() not in lobby_migration.lower():
        raise SystemExit("FAIL: lobby readiness authorization/locking invariant missing: " + marker)

message_migration = MESSAGE_IDEMPOTENCY_MIGRATION.read_text(encoding="utf-8")
for marker in ("ON CONFLICT(sender_auth_user_id,idempotency_key)", "v_existing_conversation_id IS DISTINCT FROM p_conversation_id", "v_existing_body IS DISTINCT FROM v_body", "Idempotency key was already used for a different message"):
    if marker not in message_migration:
        raise SystemExit("FAIL: private-message idempotency protection missing: " + marker)
landing_source = LANDING_PAGE.read_text(encoding="utf-8")
for link in ('href="game.html"', 'href="admin-playam-staging.html"', 'href="game-catalogue.html"'):
    if link not in landing_source:
        raise SystemExit("FAIL: Staging landing page is missing a required link: " + link)
admin_source = ADMIN_APP.read_text(encoding="utf-8")
root_admin_source = ROOT_ADMIN_APP.read_text(encoding="utf-8")
for page_name, page_source in (("published admin", admin_source), ("root admin", root_admin_source)):
    if "pwnjrdedeoxbmtfywhkk" not in page_source or "erjxmesxmmmaxivvmbsi" in page_source:
        raise SystemExit("FAIL: " + page_name + " dashboard is not isolated to Staging")
for page_name, page_source in (("published admin", admin_source), ("root admin", root_admin_source)):
    for marker in ("mfa.verify", "get_playam_admin_overview", "admin_list_player_reports", "admin_review_player_report"):
        if marker not in page_source:
            raise SystemExit("FAIL: " + page_name + " dashboard is missing a required protected workflow: " + marker)
flow_source = FLOW_APP.read_text(encoding="utf-8")
if "pwnjrdedeoxbmtfywhkk" not in flow_source or "erjxmesxmmmaxivvmbsi" in flow_source:
    raise SystemExit("FAIL: Flow interface is not isolated to Staging")
if re.search(r"service_role|sb_secret_[A-Za-z0-9_-]+|sk_(live|test)_[A-Za-z0-9]+", flow_source, re.I):
    raise SystemExit("FAIL: server-only credential marker found in Flow interface")
for page_name, page_source in (("game", source), ("admin", admin_source), ("root admin", root_admin_source), ("flow", flow_source)):
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

# Cover the critical phone layouts, including compact screens and safe-area spacing.
mobile_markers = (
    "#bottomNav{position:fixed",
    ".main{padding:14px 13px calc(105px + env(safe-area-inset-bottom))",
    "@media(max-width:380px)",
    "@media(max-width:360px)",
    ".dm-layout{grid-template-columns:1fr}",
    ".dm-thread{min-height:360px}",
    ".video-post video{height:min(68dvh,680px)",
    "#profileScreen,#walletScreen{padding:17px",
    "#homeScreen .hero{padding:22px 18px",
    "env(safe-area-inset-bottom)",
    "@media(prefers-reduced-motion:reduce)",
)
missing_mobile = [marker for marker in mobile_markers if marker not in source]
if missing_mobile:
    raise SystemExit("FAIL: mobile layout regression marker(s) missing: " + ", ".join(missing_mobile))

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
if "@media(max-width:520px)" not in admin_source or "PLAYAM admin mobile workspace" not in admin_source:
    raise SystemExit("FAIL: admin mobile layout breakpoint is missing")
root_admin_source = ROOT_ADMIN_APP.read_text(encoding="utf-8")
if "PLAYAM admin mobile workspace" not in root_admin_source or "@media(max-width:760px)" not in root_admin_source:
    raise SystemExit("FAIL: root admin mobile layout regression marker is missing")
catalogue_source = CATALOGUE_PAGE.read_text(encoding="utf-8")
if "PLAYAM game catalogue mobile layout" not in catalogue_source or "@media(max-width:760px)" not in catalogue_source:
    raise SystemExit("FAIL: game catalogue mobile layout regression marker is missing")
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

# Parse and syntax-check inline JavaScript in every interactive Staging page,
# not only the main game page.
checked_script_count = 0
for page_name, page_source in (
    ("game", source),
    ("admin", admin_source),
    ("root admin", root_admin_source),
    ("Flow", flow_source),
):
    parser = InlineScripts()
    parser.feed(page_source)
    if not parser.scripts:
        raise SystemExit("FAIL: no inline application JavaScript found in Staging " + page_name + " page")
    for index, js in enumerate(parser.scripts, start=1):
        with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8") as handle:
            handle.write(js)
            handle.flush()
            result = subprocess.run(["node", "--check", handle.name], capture_output=True, text=True)
            if result.returncode:
                raise SystemExit(
                    f"FAIL: Staging {page_name} inline JavaScript block {index} has a syntax error:\\n{result.stderr}"
                )
        checked_script_count += 1

# Keep responsive-layout regression coverage on every published Staging surface.
for page_name, page_source, marker in (
    ("admin", admin_source, "PLAYAM admin mobile workspace"),
    ("Flow", flow_source, "PLAYAM Flow mobile workspace"),
    ("catalogue", catalogue_source, "PLAYAM game catalogue mobile layout"),
):
    if marker not in page_source or "@media(max-width:760px)" not in page_source:
        raise SystemExit("FAIL: mobile responsive regression marker missing from Staging " + page_name + " page")

print(
    f"PASS: Staging-only configuration, {len(required)} required features, room-scoped gameplay calls, "
    f"mobile layout markers, and {checked_script_count} inline JavaScript block(s) across all interactive pages."
)
