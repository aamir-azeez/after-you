extends SceneTree
## Each cross-cutting concern has one shared path, and every surface that
## touches the concern goes through it. A feature built on one screen and missed
## on the next (a pip without its look, a wallet read that dropped its grant, a
## Home row waiting on a read nobody made, a server button live while offline)
## fails here, at the new surface, before a player sees it.
##
## The scans read every game script with its comment lines taken out, so a
## comment naming the shared path never counts as using it:
## (a) pips: PipAvatar with `own`, or a look source; worlds through wear_slots;
## (b) wallet replies and spend receipts: services/wallet_reply.gd alone feeds the stores, the Fruit store too;
## (c) feature switches: capability fields are read in relay_online_session.gd;
## (d) offline: a screen that reaches the server holds its buttons (offline_hold.gd);
## (e) names: FriendNicknames.display_name, the leaderboard pair title, and in a public
##     duel's room services/room_partner_names.gd (its partner id is a stand-in, and it gates partner presence);
## (f) Pollen amounts: PollenMoney.grouped beside every amount;
## (g) saves: services/atomic_file.gd writes every file;
## (h) server writes: each one is classed, keyed or safe to repeat;
## (i) button ticks and first taps: button_ticks.gd and touch_input.gd alone;
## (j) cutout bleed: test_full_screen_bleed.gd, which must stay in CI;
## (k) the recovery code: services/recovery_guard.gd alone copies it and works the screen
##     lock and private screen; each screen that reads it is in RECOVERY_SURFACES;
## (l) the leaderboard icon: presentation/kit/icons.gd LEADERBOARD alone names the
##     trophy, and each screen that shows a leaderboard icon is in LEADERBOARD_ICON_SURFACES;
## (m) duel times: services/duel_model.gd lane() alone gives a duel lane its time and dots (the
##     pair ahead set beside the pair behind after as many turns), and each screen that shows a
##     duel time is in DUEL_TIME_SURFACES.
##
## Every allow-list entry says why. An entry that no longer matches anything
## fails, so the lists shrink as code moves. KNOWN_FAILURES holds the checks
## that fail on main today, each with the branch or audit item that fixes it; a
## known check that passes fails too ("delete it from KNOWN_FAILURES"), so the
## guard tightens as each fix lands.

## Check id -> who fixes it and what is wrong.
const KNOWN_FAILURES := {
	"capabilities:res://presentation/reaction_photo_flow.gd": "unowned (shared-paths audit): photo_uploads_enabled is read raw; give it an accessor",
	"capabilities:res://presentation/replays_flow.gd": "unowned (shared-paths audit): replay_transfer_version is read raw; give it an accessor",
	"offline:res://presentation/duels/duels_flow.gd": "unowned (shared-paths audit): Challenge, Race, Party and the duel answers stay live offline",
	"offline:res://presentation/room_hub_flow.gd": "unowned (shared-paths audit): room hub actions (leave, close, invite lookup) never grey offline",
	"offline:res://presentation/room_hub_screen.gd": "unowned (shared-paths audit): greys from its own list state, a second offline system",
	"offline:res://presentation/photo_transfer_screen.gd": "unowned (shared-paths audit): the transfer screen's buttons stay live offline",
	"offline:res://presentation/platform_games_flow.gd": "unowned (shared-paths audit): the Settings row and its link and restore buttons never grey",
	"offline:res://presentation/account_flow.gd": "unowned (shared-paths audit): recovery and delete confirmations stay live offline",
	"offline:res://presentation/safety_screen.gd": "unowned (shared-paths audit): unblock and report buttons stay live offline",
	"offline:res://presentation/shared_replay_view.gd": "unowned (shared-paths audit): report and block in a replay stay live offline",
	"offline:res://presentation/legacy_room_flow.gd": "unowned (shared-paths audit): legacy room create, join, fork and advance stay live offline",
	"offline:res://presentation/notification_flow.gd": "unowned (shared-paths audit): a room alert tapped offline says the room could not be opened on every retry",
	"offline:res://relay_preview.gd": "unowned (shared-paths audit): New room on the end card and redo requests stay live offline (turns themselves are kept)",
}

## (a) The scripts that draw a pip.
const PIP_SCRIPTS := ["res://presentation/kit/pip_avatar.gd", "res://presentation/kit/spirit_preview.gd", "res://presentation/spirit_visual.gd", "res://presentation/kit/pip_stage.gd"]
## Every script that makes a pip, and how it is dressed:
## own: each pip it makes is the player's own (PipAvatar's `own` argument);
## dressed: it reads a look (OwnLook, TurnLooks, SlotLooks, an outfit it is given);
## kit: the shared pip itself; preview: a plain pip showing an item, on purpose;
## unshown: never on a player's screen.
const PIP_MAKERS := {
	"res://presentation/kit/pip_avatar.gd": ["kit", "the one pip for screens"],
	"res://presentation/kit/spirit_preview.gd": ["kit", "PipAvatar's live view"],
	"res://presentation/kit/pip_stage.gd": ["kit", "the studio every pip view shares"],
	"res://presentation/kit/pip_snapshots.gd": ["kit", "PipAvatar's still renderer, drawing the outfit it is asked for"],
	"res://presentation/island_world.gd": ["dressed", "each slot's pip wears slot_looks (wear_slots)"],
	"res://presentation/settings_spirit.gd": ["own", "the Settings header pip"],
	"res://presentation/display_name_chip.gd": ["own", "the name chip's pip"],
	"res://presentation/display_name_prompt.gd": ["own", "the name prompt's pip"],
	"res://presentation/home_menu.gd": ["own", "the Wardrobe row's pip"],
	"res://presentation/pollen_play_spare.gd": ["own", "the Pollen from play page's pip"],
	"res://presentation/leaderboard_rows.gd": ["dressed", "the player's own pip and the partner's look from the run"],
	"res://presentation/leaderboard_celebration.gd": ["dressed", "OwnLook beside the partner's TurnLooks"],
	"res://presentation/duels/duel_kit.gd": ["dressed", "both pairs in every duel page"],
	"res://presentation/race_ghost_view.gd": ["dressed", "the raced player in the look the race kept, on the turn and its timer"],
	"res://presentation/wardrobe_page.gd": ["preview", "shows each item on the plain pip"],
	"res://presentation/wardrobe_sheets.gd": ["preview", "the buy sheet shows the item on the plain pip"],
	"res://presentation/pollen_result_line.gd": ["preview", "owner 2026-11-02: the dropped item shows alone on a plain pip"],
	"res://presentation/story_memory_world.gd": ["unshown", "Story was removed; only tests load it"],
}
## A script that reads a player's look.
const LOOK_SOURCE := "OwnLook\\.|TurnLooks|SlotLooks|slot_looks|Outfit\\.from\\(|\\.wear\\(|\\.outfit\\s*="
## Scripts that build a chapter world: shown worlds dress their pips (wear_slots).
const WORLD_RUNNERS := {
	"res://main.gd": "home",
	"res://relay_preview.gd": "dressed",
	"res://lighthouse_preview.gd": "dressed",
	"res://presentation/shared_replay_view.gd": "dressed",
	"res://services/world_prewarm.gd": "unseen: built off screen to warm a chapter, never shown",
}

## (b) The wallet reply.
const WALLET_REPLY := "res://services/wallet_reply.gd"

## (c) The one reader of capability fields.
const SWITCH_READER := "res://services/relay_online_session.gd"

## (d) Online clients: a screen that preloads one reaches the server.
const ONLINE_CLIENTS := ["duels_client", "public_duels_client", "friends_client", "leaderboard_client", "wardrobe_client", "pollen_client", "safety_client", "display_name_client", "bundle_claims", "redo_client", "hard_room_client", "photo_transfer_client", "tester_access", "platform_link_client", "friend_room_events_client", "replay_transfer", "history_sync", "turn_photo_controller", "rooms_api", "relay_online_session", "room_inbox_client"]
## Screens that reach the server without holding a button, and why that is fine.
const OFFLINE_EXEMPT := {
	"res://presentation/board_feedback_flow.gd": "no button: Home's background board watch",
	"res://presentation/friends_flow.gd": "opens Friends, whose buttons hold (friends_screen.gd); its board read runs in the background",
	"res://presentation/bundle_purchase.gd": "refuses offline itself before a purchase starts; the store page holds its buttons",
	"res://presentation/settings_rows.gd": "declares rows online: true; settings_flow.gd holds each one",
	"res://presentation/turn_flow.gd": "a turn is kept as pending_turn and sent again later, offline included",
}

## (e) The name resolver and the scripts allowed under it.
const NAME_EXEMPT := {
	"res://services/friend_nicknames.gd": "the one resolver",
	"res://services/display_names.gd": "the name store",
	"res://presentation/friends_screen.gd": "edits nicknames and shows a friend's chosen name under one",
	"res://presentation/display_name_flow.gd": "the player's own anonymous name",
}

## The room surfaces that name a room's partner: each asks room_partner_names.gd first.
const ROOM_NAME_SURFACES := ["res://relay_preview.gd", "res://presentation/room_hub_flow.gd", "res://presentation/replays_flow.gd"]
## The room surfaces that read or show a partner's presence: each asks room_partner_names.gd presence_shown first, so a
## public duel's room neither shows it nor spends a read on it.
const ROOM_PRESENCE_SURFACES := ["res://main.gd", "res://relay_preview.gd"]

## (f) Constants holding a count that is never Pollen, though they read like an amount.
const POLLEN_COUNTS := {"POLLEN_BANK_REFILL": "turns the bank gains each Monday"}
## Constants holding a Pollen amount that the "%s Pollen" or "+%s" shape misses.
const POLLEN_AMOUNTS := ["POLLEN_TAIL_FIRST", "POLLEN_TAIL_STEP"]

## (g) Scripts that write a file without AtomicFile, and why.
const SAVE_EXEMPT := {
	"res://services/atomic_file.gd": "the shared path",
	"res://core/lighthouse/room_proof.gd": "core never loads services; it keeps its own verified temp file and rename",
	"res://services/gl_warmup.gd": "a stamp: a torn one only warms the shaders again",
	"res://presentation/chapter_loading_card.gd": "a timing cache: a torn one is read as empty",
	"res://services/backup_plan.gd": "the backup agent's list, written again on every call",
	"res://main.gd": "the capture tool's png",
}

## (h) Every script that sends a server write: [how many, why each is safe].
## A reason starting "keyed" means the script sends idempotency keys.
const WRITES := {
	"res://main.gd": [3, "keyed: room reactions; POST /v1/identity has none (audit: check one lost answer never makes two identities)"],
	"res://presentation/account_flow.gd": [2, "keyed: identity recovery; DELETE /v1/identity removes one thing"],
	"res://presentation/legacy_room_flow.gd": [4, "keyed: room create, fork and advance; a join names one invite"],
	"res://presentation/room_hub_flow.gd": [5, "unkeyed: close, leave and invite lookups end in the same state when repeated"],
	"res://presentation/turn_flow.gd": [1, "keyed: the pending turn's key"],
	"res://services/bundle_claims.gd": [1, "unkeyed: claims every purchase the store reports; each purchase token pays once"],
	"res://services/deleted_identity_ack.gd": [1, "unkeyed: an acknowledgement"],
	"res://services/display_name_client.gd": [2, "unkeyed: PUT sets the whole name"],
	"res://services/duels_client.gd": [5, "keyed: challenge and ghost race, one key per tap; answers, acks and party moves name what they change"],
	"res://services/public_duels_client.gd": [4, "keyed: a public post, join and report each carry their attempt's key; the switch sets a state; block and Add friend name a seat and end the same when repeated"],
	"res://services/friend_presence.gd": [2, "unkeyed: sets online or offline"],
	"res://services/friend_room_events_client.gd": [3, "unkeyed: the publication keeps its own id across launches; acks and alert switches set a state"],
	"res://services/friends_client.gd": [5, "unkeyed: each names the request or friend code it acts on"],
	"res://services/hard_room_client.gd": [1, "keyed: the hard reset"],
	"res://services/history_sync.gd": [3, "unkeyed: parts go by room and position; acks and wants repeat safely"],
	"res://services/leaderboard_client.gd": [3, "unkeyed: PUT sets the name switch; a report names its entry; a room's run post names its room and the board takes a run once (known)"],
	"res://services/photo_transfer_client.gd": [3, "keyed: sessions and restore acks"],
	"res://services/platform_games/platform_link_client.gd": [5, "keyed: link and restore; unlink sets a state"],
	"res://services/pollen_client.gd": [2, "unkeyed: each claim names its room and recording, which pay once"],
	"res://services/redo_client.gd": [2, "keyed: fork and redo"],
	"res://services/relay_online_session.gd": [1, "keyed: room create and duel rooms"],
	"res://services/relay_room_coordinator.gd": [1, "keyed: turns and stage moves"],
	"res://services/replay_transfer.gd": [2, "unkeyed: ack and restore name their manifest"],
	"res://services/safety_client.gd": [6, "keyed: reports; terms, room block, Friends row block, unblock and a public duel unblock set a state"],
	"res://services/tester_access.gd": [1, "unkeyed: redeeming a code again keeps one grant"],
	"res://services/turn_notifications.gd": [4, "unkeyed: registration and categories carry a binding epoch"],
	"res://services/turn_photo_controller.gd": [2, "keyed: photo upload and delete"],
	"res://services/wardrobe_client.gd": [1, "keyed: spend and equip, the same key on a retry"],
}
const SEND := "(?:request_json(?:_with_headers)?|_request|_net|_call|_mutation|_transport\\.call)(?:\\.bind)?\\(\\s*(?:[\\w.]+,\\s*)?HTTPClient\\.METHOD_(?:POST|PUT|PATCH|DELETE)"

## (k) The one gate in front of the recovery code, and each screen that reads the code with
## how it goes through that gate.
const RECOVERY_GUARD := "res://services/recovery_guard.gd"
const RECOVERY_SURFACES := {
	"res://presentation/account_flow.gd": "shows, copies and imports it through its guard",
	"res://presentation/platform_games_flow.gd": "copies it through account_flow.copy_recovery_details",
}

## (l) The one leaderboard icon, and each screen that shows it with where.
const ICONS := "res://presentation/kit/icons.gd"
const LEADERBOARD_ICON_FILE := "trophy.svg"
## The star leaderboards wore before the owner picked the trophy (2026-11-03); What's new loads it by name only.
const OLD_LEADERBOARD_ICON := "whats_new/star.svg"
const LEADERBOARD_ICON_SURFACES := {
	"res://presentation/friends_screen.gd": "the Leaderboards button in the Friends header",
	"res://presentation/settings_rows.gd": "the Show my name on leaderboards row",
	"res://presentation/duels/duels_screen.gd": "the lobby's Race a recorded run row, which picks from the board",
	"res://presentation/duels/duel_ghost_page.gd": "each chapter's Top 10 button",
	"res://presentation/duels/duel_race_picker.gd": "the top 10 picker's heading",
	"res://presentation/whats_new_kit.gd": "What's new highlights about the board (icon trophy)",
}

## (m) The one path to a duel lane's time and dots, and the screens that show one.
const DUEL_MODEL := "res://services/duel_model.gd"
const DUEL_TIME_SURFACES := {
	"res://presentation/duels/duels_screen.gd": "the lobby tile's two lanes",
	"res://presentation/duels/duel_page.gd": "the duel page's two side cards",
	"res://presentation/duels/duel_result_page.gd": "the result page's two side cards",
}
## Scripts that read a duel view's or list row's steps or ticks for something other than a lane's time and dots.
const RAW_DUEL_TIME_EXEMPT := {
	"res://services/duel_model.gd": "the shared path itself (lane, steps, ticks)",
	"res://presentation/duels/public_sheets.gd": "a public list row's steps, to word the join sheet; list rows carry no times",
	"res://services/race_ghost.gd": "the developers' run is picked by the race's ghost ticks, never shown as a time",
}
## A side's or the ghost's time or steps read straight off a duel view.
const RAW_DUEL_TIME := "\\.(?:sides\\[[^\\]]+\\]|ghost)\\.(?:ticks|steps)\\b|\\.(?:sides\\[[^\\]]+\\]|ghost)\\.get\\(\"(?:ticks|steps|splits)\""

## Suites that guard a shared path on their own and must stay in CI.
const GUARD_SUITES := ["shared_paths", "full_screen_bleed", "pollen_mark", "connectivity"]

var checks := 0
var failures := 0
var known := 0
var _known_seen := {}
var _sources := {}

func _initialize() -> void:
	_self_checks()
	var paths := _scripts("res://")
	_check(paths.size() > 300 and paths.has("res://main.gd") and paths.has("res://relay_preview.gd") and paths.has("res://presentation/home_menu.gd"), "The scan reads the game's scripts: %d" % paths.size())
	for path: String in paths: _sources[path] = _code(FileAccess.get_file_as_string(path))
	_pips()
	_wallet()
	_switches()
	_offline()
	_names()
	_pollen()
	_saves()
	_writes()
	_taps()
	_recovery()
	_leaderboard_icon()
	_duel_times()
	_suites()
	for id: String in KNOWN_FAILURES:
		_check(_known_seen.has(id), "KNOWN_FAILURES names '%s', which no check reached: delete it" % id)
	print("SHARED PATHS: %d checks, %d failures, %d known (KNOWN_FAILURES)" % [checks, failures, known])
	quit(1 if failures else 0)

## The scans find what they should in small sources first.
func _self_checks() -> void:
	_check(_alias("const Icons = preload(\"res://presentation/kit/icons.gd\")\n", ICONS) == "Icons" and _found("\\bIcons\\.LEADERBOARD\\b", "x.icon = Icons.LEADERBOARD\n") == 1, "A leaderboard icon through the shared module is found")
	_check(_code("a\n\t## OwnLook.color()\n# x\nb") == "a\n\n\nb", "Comment lines are taken out, line numbers kept")
	_check(_makers("const P = preload(\"res://presentation/kit/pip_avatar.gd\")\nvar p := P.new(true, P.PEACH, S, true, true)\n").size() == 1, "A pip made through an alias is found")
	_check(_makers("var x := SpiritVisual.GREETING\n").is_empty(), "A pip script's constant is no pip")
	_check(_own_args("P.new(true, C, Vector2(1, 2), true, true)", "P.new(") == [true], "A pip made with own is own")
	_check(_own_args("P.new(true, C, Vector2(1, 2), true)", "P.new(") == [false], "A pip made without own is not")
	_check(_own_args("P.new(true, C, S, true, own and i == 0)", "P.new(") == [true], "A pip whose own is decided by the caller counts as own")
	_check(_found(SEND, "await _api.request_json(HTTPClient.METHOD_POST, PATH, body)") == 1 and _found(SEND, "await _net(ticket, HTTPClient.METHOD_DELETE, p)") == 1, "Sends are found, with a leading ticket too")
	_check(_found(SEND, "if method == HTTPClient.METHOD_POST and path in []") == 0 and _found(SEND, "request_json(HTTPClient.METHOD_GET, p)") == 0, "A method test or a read is no send")
	_check(_found(_capability_read(), "capabilities.get(\"x\")") == 1 and _found(_capability_read(), "if session.capabilities.is_empty(): await session.load_capabilities()") == 0, "A raw capability read is found; an emptiness test is not")
	_check(_found(RAW_DUEL_TIME, "Kit.text(time_text(view.sides[index].ticks))") == 1 and _found(RAW_DUEL_TIME, "var t := view.ghost.get(\"splits\")") == 1 and _found(RAW_DUEL_TIME, "row.sides[side].seats") == 0, "A duel time read off the view is found; a seat is not")
	_check(_writers("var c := ConfigFile.new()\nc.save(PATH)\n") == [2] and _writers("var c := ConfigFile.new()\nAtomicFile.write_text(PATH, c.encode_to_text())\n").is_empty(), "A ConfigFile saved by itself is a write; one through AtomicFile is not")

# (a) Pips -------------------------------------------------------------------

func _pips() -> void:
	var reached := {}
	for path: String in _sources:
		var made := _makers(_sources[path])
		if made.is_empty(): continue
		reached[path] = true
		if not PIP_MAKERS.has(path):
			_check(false, "%s makes a pip (line %d): dress it (PipAvatar own, or a look from OwnLook, TurnLooks or SlotLooks) and add it to PIP_MAKERS" % [path, made[0].line])
			continue
		var kind: String = PIP_MAKERS[path][0]
		if kind == "own":
			var all_own := true
			for at: Dictionary in made:
				if not at.own: all_own = false
			_rule("pips:" + path, all_own, "%s makes a pip that is not the player's own: pass own (PipAvatar's fifth argument)" % path)
		elif kind == "dressed":
			_rule("pips:" + path, _found(LOOK_SOURCE, _sources[path]) > 0, "%s makes pips but reads no look (OwnLook, TurnLooks, SlotLooks or a given outfit)" % path)
	for path: String in PIP_MAKERS:
		_check(reached.has(path), "PIP_MAKERS names %s, which makes no pip now: delete it" % path)
	var worlds := {}
	var made_world := RegEx.create_from_string("\\b\\w*World\\.new\\(\\)|world_script\\([^)]*\\)\\.new\\(\\)")
	for path: String in _sources:
		if made_world.search(_sources[path]) == null: continue
		worlds[path] = true
		if not WORLD_RUNNERS.has(path):
			_check(false, "%s builds a chapter world: dress its pips with wear_slots (presentation/slot_looks.gd) and add it to WORLD_RUNNERS" % path)
			continue
		var kind: String = WORLD_RUNNERS[path]
		if kind == "dressed": _check(_sources[path].contains("wear_slots("), "%s builds a world but never calls wear_slots: its pips miss the players' looks" % path)
		elif kind == "home": _rule("home_pips_dressed", _sources[path].contains("wear_slots(") or str(_sources.get("res://presentation/home_stage.gd", "")).contains("wear_slots("), "Home's world pips never wear the player's look (wear_slots)")
	for path: String in WORLD_RUNNERS:
		_check(worlds.has(path), "WORLD_RUNNERS names %s, which builds no world now: delete it" % path)

## Each pip `source` makes: [{line, own}].
func _makers(source: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var aliases := RegEx.create_from_string("(?m)^const\\s+(\\w+)\\s*:?=\\s*preload\\(\"(res://[\\w/]+\\.gd)\"\\)")
	# The names the game gives the pip scripts, which a script also inherits from its base.
	var calls: Array[String] = ["PipAvatar.new(", "SpiritVisual.new("]
	for match: RegExMatch in aliases.search_all(source):
		var script := match.get_string(2)
		if script not in PIP_SCRIPTS: continue
		var call := match.get_string(1) + (".pip(" if script.ends_with("pip_stage.gd") else ".new(")
		if call not in calls: calls.append(call)
	for call: String in calls:
		var own := _own_args(source, call)
		var at := 0
		for index in range(own.size()):
			at = _call_at(source, call, at)
			found.append({"line": source.substr(0, at).count("\n") + 1, "own": own[index]})
			at += call.length()
	var extended := RegEx.create_from_string("(?m)^extends\\s+\"(res://[\\w/]+\\.gd)\"").search(source)
	if extended != null and extended.get_string(1) in PIP_SCRIPTS:
		found.append({"line": 1, "own": _own_args(source, "super(").all(func(value: bool) -> bool: return value) and source.contains("super(")})
	return found

## For each `call` in `source` (a name followed by "("), whether its fifth argument says own.
func _own_args(source: String, call: String) -> Array[bool]:
	var result: Array[bool] = []
	var at := _call_at(source, call, 0)
	while at >= 0:
		var args := _arguments(source, at + call.length())
		result.append(args.size() >= 5 and args[4] != "false")
		at = _call_at(source, call, at + call.length())
	return result

## The next `call` at or after `from` that is not part of a longer name.
static func _call_at(source: String, call: String, from: int) -> int:
	var at := source.find(call, from)
	while at > 0 and (source[at - 1] == "_" or source[at - 1].is_valid_identifier() or source[at - 1].is_valid_int()):
		at = source.find(call, at + 1)
	return at

## The top-level arguments of a call whose "(" ends just before `start`.
static func _arguments(source: String, start: int) -> Array[String]:
	var args: Array[String] = []
	var depth := 0
	var current := ""
	for index in range(start, source.length()):
		var c := source[index]
		if c in ["(", "[", "{"]: depth += 1
		elif c in [")", "]", "}"]:
			if depth == 0:
				if not current.strip_edges().is_empty(): args.append(current.strip_edges())
				return args
			depth -= 1
		elif c == "," and depth == 0:
			args.append(current.strip_edges())
			current = ""
			continue
		current += c
	return args

# (b) Wallet replies ---------------------------------------------------------

func _wallet() -> void:
	var readers := 0
	for path: String in _sources:
		var source: String = _sources[path]
		var alias := _alias(source, WALLET_REPLY)
		if path != WALLET_REPLY:
			_check(_found("\\.note_wallet\\(", source) == 0, "%s keeps a wallet answer itself: go through services/wallet_reply.gd, which feeds the wallet, wardrobe, grant and Fruits together" % path)
			_check(_found("\\.note_view\\(", source) == 0, "%s keeps a wardrobe, grant or Fruits part of a wallet answer itself: go through services/wallet_reply.gd" % path)
			var through := 0 if alias.is_empty() else _found("\\b" + alias + "\\.note_spend\\(", source)
			_check(_found("\\.note_spend\\(", source) == through, "%s keeps a spend receipt itself: go through services/wallet_reply.gd note_spend, which feeds the wardrobe and both balances" % path)
		# Every wallet reply and spend receipt names the Fruit store too (its last argument), so no read drops the Fruits part.
		if not alias.is_empty():
			for call: String in [alias + ".note(", alias + ".note_spend("]:
				var at := _call_at(source, call, 0)
				while at >= 0:
					var args := _arguments(source, at + call.length())
					_check(args.size() == (7 if call.ends_with(".note(") else 6) and args.back() != "null", "%s calls %s without the Fruit store (services/fruit_wallet.gd) as its last argument: %s" % [path, call, args])
					at = _call_at(source, call, at + call.length())
		if not source.contains("\"/v1/pollen\""): continue
		readers += 1
		_check(not alias.is_empty() and source.contains(alias + ".note("), "%s reads the wallet (GET /v1/pollen) without services/wallet_reply.gd note()" % path)
	_check(readers >= 2, "The wallet readers are found: %d" % readers)

# (c) Feature switches -------------------------------------------------------

func _switches() -> void:
	for path: String in _sources:
		if path == SWITCH_READER: continue
		var count := _found(_capability_read(), _sources[path])
		_rule("capabilities:" + path, count == 0, "%s reads a capability field itself: add an accessor in relay_online_session.gd (the *_supported() functions) and call that" % path)
	var duels: String = _sources.get("res://presentation/duels/duels_flow.gd", "")
	var board: String = _sources.get("res://presentation/board_feedback_flow.gd", "")
	var rows: String = _sources.get("res://presentation/settings_rows.gd", "")
	_rule("home_switches", duels.contains("ServerSwitches") and board.contains("ServerSwitches") and (rows.contains("_leaderboards_offered") or rows.contains("ServerSwitches")), "Home's Duels row, board watch and leaderboard name row follow the switches kept from launch (services/server_switches.gd)")

static func _capability_read() -> String:
	return "capabilities(?:\\.get\\(|\\[|\\.(?!is_empty\\(|duplicate\\(|clear\\(|is_valid\\(|call\\()\\w)"

# (d) Offline ----------------------------------------------------------------

func _offline() -> void:
	var anchors := 0
	var exempt_seen := {}
	var clients := RegEx.create_from_string("preload\\(\"res://services/(?:\\w+/)?(" + "|".join(ONLINE_CLIENTS) + ")\\.gd\"\\)")
	for path: String in _sources:
		if not (path.begins_with("res://presentation/") or path in ["res://main.gd", "res://relay_preview.gd"]): continue
		var source: String = _sources[path]
		if clients.search(source) == null and _found(SEND, source) == 0: continue
		anchors += 1
		var held := source.contains("OfflineHold.")
		if OFFLINE_EXEMPT.has(path):
			exempt_seen[path] = true
			_check(not held, "%s holds its buttons now: delete it from OFFLINE_EXEMPT" % path)
			continue
		_rule("offline:" + path, held, "%s reaches the server from the screen but greys nothing offline: OfflineHold.hold its server buttons (presentation/offline_hold.gd), or OfflineHold.refuse a route with no button" % path)
	_check(anchors >= 15, "The screens that reach the server are found: %d" % anchors)
	for path: String in OFFLINE_EXEMPT:
		_check(exempt_seen.has(path), "OFFLINE_EXEMPT names %s, which no longer reaches the server: delete it" % path)

# (e) Names ------------------------------------------------------------------

func _names() -> void:
	for path: String in _sources:
		if NAME_EXEMPT.has(path) or path == "res://presentation/player_copy.gd": continue
		var source: String = _sources[path]
		_check(_found("\\.nickname\\(", source) == 0, "%s names a friend by their nickname alone: use FriendNicknames.display_name (nickname, then chosen name, then 'a friend')" % path)
		var names := _alias(source, "res://services/display_names.gd")
		if not names.is_empty():
			_check(_found(names + "\\.shared\\(\\)\\.(?:shown|chosen)\\(", source) == 0, "%s reads another player's name from DisplayNames: use FriendNicknames.display_name" % path)
			_check(_found(names + "\\.anonymous_name\\(", source) == 0, "%s makes an anonymous name itself: use FriendNicknames.display_name" % path)
		_check(not source.contains("\"a friend\"") and not source.contains("\"A friend\""), "%s writes the friend fallback itself: use FriendNicknames.FALLBACK or sentence_start" % path)
		_check(not source.contains("\"A pair\""), "%s writes 'A pair' itself: use PlayerCopy.LEADERBOARD_A_PAIR through leaderboard_rows.gd pair_title" % path)
		if path != "res://presentation/leaderboard_rows.gd":
			_check(_found("LEADERBOARD_A_PAIR|LEADERBOARD_NAMES\\b", source) == 0, "%s builds a leaderboard pair's name itself: use leaderboard_rows.gd pair_title" % path)
	for path: String in NAME_EXEMPT:
		_check(_sources.has(path), "NAME_EXEMPT names %s, which is gone: delete it" % path)
	for path: String in ROOM_NAME_SURFACES:
		_check(str(_sources.get(path, "")).contains("RoomPartnerNames.public_partner("), "%s names a room's partner without services/room_partner_names.gd: in a public duel's room it would call a stranger 'a friend'" % path)
	for path: String in ROOM_PRESENCE_SURFACES:
		_check(str(_sources.get(path, "")).contains("RoomPartnerNames.presence_shown("), "%s reads or shows a room partner's presence without services/room_partner_names.gd presence_shown: a public duel's room would read a stranger's" % path)
	# Every presence badge the room screen builds is behind its gate, on the same line or the one before.
	var lines: PackedStringArray = str(_sources.get("res://relay_preview.gd", "")).split("\n")
	for index in lines.size():
		if lines[index].contains("_presence_badge()") and not lines[index].strip_edges().begins_with("func "):
			_check(lines[index].contains("_presence_available()") or (index > 0 and lines[index - 1].contains("_presence_available()")), "relay_preview.gd builds a presence badge without _presence_available(): a public duel's room would show a stranger's status (line %d)" % (index + 1))

# (f) Pollen amounts ---------------------------------------------------------

func _pollen() -> void:
	var copy: String = _sources.get("res://presentation/player_copy.gd", "")
	var amounts: Array[String] = []
	var counted := {}
	for match: RegExMatch in RegEx.create_from_string("(?m)^const (\\w+)\\s*:?=\\s*\"([^\"\\n]*)\"").search_all(copy):
		var name := match.get_string(1)
		var text := match.get_string(2)
		if _found("%d Pollen|\\+%d(?!%)", text) > 0:
			if POLLEN_COUNTS.has(name):
				counted[name] = true
				continue
			_check(false, "PlayerCopy.%s puts a Pollen amount in with %%d: use %%s and PollenMoney.grouped (\"24,000\")" % name)
		if _found("%s Pollen|\\+%s", text) > 0: amounts.append(name)
	_check(amounts.size() >= 10, "The Pollen amount lines are found: %d" % amounts.size())
	for name: String in POLLEN_COUNTS:
		_check(counted.has(name), "POLLEN_COUNTS names %s, which holds no %%d now: delete it" % name)
	for name: String in POLLEN_AMOUNTS:
		_check(copy.contains("const " + name + " "), "POLLEN_AMOUNTS names %s, which PlayerCopy no longer has: delete it" % name)
		if name not in amounts: amounts.append(name)
	# Each constant on its own, so a second one on the same line is checked too.
	var used := RegEx.create_from_string("PlayerCopy\\.(" + "|".join(amounts) + ")\\b")
	for path: String in _sources:
		if path == "res://presentation/player_copy.gd": continue
		var source: String = _sources[path]
		for match: RegExMatch in used.search_all(source):
			var start := source.rfind("\n", match.get_start()) + 1
			var end := source.find("\n", match.get_end())
			if end < 0: end = source.length()
			if not source.substr(match.get_end(), end - match.get_end()).contains("%"): continue
			var line := source.substr(start, end - start)
			_check(line.contains("grouped("), "%s fills PlayerCopy.%s without PollenMoney.grouped: %s" % [path, match.get_string(1), line.strip_edges().left(120)])

# (g) Saves ------------------------------------------------------------------

func _saves() -> void:
	var seen := {}
	for path: String in _sources:
		var lines := _writers(_sources[path])
		if lines.is_empty(): continue
		if SAVE_EXEMPT.has(path):
			seen[path] = true
			continue
		_check(false, "%s writes a file itself (line %d): write it through services/atomic_file.gd (write_text, or ConfigFile.encode_to_text into write_text)" % [path, lines[0]])
	for path: String in SAVE_EXEMPT:
		_check(seen.has(path), "SAVE_EXEMPT names %s, which writes nothing itself now: delete it" % path)

## Lines where `source` writes a file without AtomicFile.
static func _writers(source: String) -> Array[int]:
	var found: Array[int] = []
	var patterns := ["FileAccess\\.open\\([^\\n]*FileAccess\\.(?:WRITE|READ_WRITE|WRITE_READ)", "\\.save_(?:png|jpg|webp|exr)\\(", "ResourceSaver\\.save\\(", "\\.store_(?:string|buffer|line|var)\\("]
	for match: RegExMatch in RegEx.create_from_string("var (\\w+)\\s*:?=\\s*ConfigFile\\.new\\(\\)").search_all(source):
		patterns.append("\\b" + match.get_string(1) + "\\.save\\(")
	for pattern: String in patterns:
		for match: RegExMatch in RegEx.create_from_string(pattern).search_all(source):
			var line := source.substr(0, match.get_start()).count("\n") + 1
			if line not in found: found.append(line)
	found.sort()
	return found

# (h) Server writes ----------------------------------------------------------

func _writes() -> void:
	var seen := {}
	for path: String in _sources:
		var count := _found(SEND, _sources[path])
		if count == 0: continue
		seen[path] = true
		if not WRITES.has(path):
			_check(false, "%s sends %d server write(s): add it to WRITES with why each is safe to retry (an idempotency key, or a write that repeats safely)" % [path, count])
			continue
		_check(int(WRITES[path][0]) == count, "%s sends %d server write(s), WRITES says %d: class the new one (idempotency key, or why it repeats safely) and update the count" % [path, count, int(WRITES[path][0])])
		if str(WRITES[path][1]).begins_with("keyed"): _check(_sources[path].contains("idempotency_key"), "%s is keyed in WRITES but sends no idempotency_key" % path)
	for path: String in WRITES:
		_check(seen.has(path), "WRITES names %s, which sends nothing now: delete it" % path)

# (i) Button ticks and first taps ------------------------------------------

func _taps() -> void:
	for path: String in _sources:
		var source: String = _sources[path]
		if path not in ["res://presentation/button_ticks.gd", "res://services/sound_cues.gd"]:
			_check(not source.contains("\"ui_tap\""), "%s plays the button tick itself: presentation/button_ticks.gd ticks every button once (quiet() a button with its own sound)" % path)
		if path != "res://main.gd": _check(_found("ButtonTicks\\.install\\(", source) == 0, "%s installs the button ticks again: Main installs them once" % path)
		if path != "res://presentation/touch_input.gd": _check(_found("scroll_deadzone\\s*=[^=]", source) == 0, "%s sets a list's scroll slop itself: presentation/touch_input.gd gives every list the same slop, so a first tap registers" % path)
	_check(str(_sources.get("res://main.gd", "")).contains("ButtonTicks.install(") and str(_sources.get("res://main.gd", "")).contains("TouchInput.install("), "Main installs the button ticks and the touch slop")

# (k) The recovery code ------------------------------------------------------

func _recovery() -> void:
	var seen := {}
	for path: String in _sources:
		var source: String = _sources[path]
		if path != RECOVERY_GUARD:
			_check(_found("\\.copy_recovery\\(|\\.confirm_device\\(|\\.set_private_screen\\(", source) == 0, "%s copies the recovery code or works the screen lock itself: go through services/recovery_guard.gd" % path)
		if not path.begins_with("res://presentation/") or not source.contains("\"recovery_code\""): continue
		if not RECOVERY_SURFACES.has(path):
			_check(false, "%s reads the recovery code on a screen: show and copy it through account_flow's guard (services/recovery_guard.gd), then add it to RECOVERY_SURFACES" % path)
			continue
		seen[path] = true
		_check(source.contains("guard.") or source.contains("copy_recovery_details("), "%s is in RECOVERY_SURFACES but goes through no guard" % path)
	for path: String in RECOVERY_SURFACES:
		_check(seen.has(path), "RECOVERY_SURFACES names %s, which no longer reads the code: delete it" % path)

# (l) The leaderboard icon ----------------------------------------------------

func _leaderboard_icon() -> void:
	var seen := {}
	for path: String in _sources:
		var source: String = _sources[path]
		if path != ICONS: _check(not source.contains(LEADERBOARD_ICON_FILE), "%s names the leaderboard trophy itself: use presentation/kit/icons.gd LEADERBOARD, so every screen shows the same icon" % path)
		_check(not source.contains(OLD_LEADERBOARD_ICON), "%s loads the old leaderboard star: a leaderboard shows presentation/kit/icons.gd LEADERBOARD (the trophy)" % path)
		var alias := _alias(source, ICONS)
		if alias.is_empty() or _found("\\b" + alias + "\\.LEADERBOARD\\b", source) == 0: continue
		seen[path] = true
		_check(LEADERBOARD_ICON_SURFACES.has(path), "%s shows the leaderboard icon: add it to LEADERBOARD_ICON_SURFACES with where" % path)
	for path: String in LEADERBOARD_ICON_SURFACES:
		_check(seen.has(path), "LEADERBOARD_ICON_SURFACES names %s, which shows no leaderboard icon through presentation/kit/icons.gd now" % path)
	_check(str(_sources.get(ICONS, "")).contains("const LEADERBOARD = preload(\"res://assets/ui/social/" + LEADERBOARD_ICON_FILE + "\")"), "presentation/kit/icons.gd LEADERBOARD is the Phosphor trophy")

# (m) Duel times --------------------------------------------------------------

func _duel_times() -> void:
	var seen := {}
	var raw := {}
	for path: String in _sources:
		var source: String = _sources[path]
		if _found(RAW_DUEL_TIME, source) > 0:
			raw[path] = true
			_check(RAW_DUEL_TIME_EXEMPT.has(path), "%s reads a duel time or steps off a view: show it through DuelModel.lane(), or add it to RAW_DUEL_TIME_EXEMPT with why" % path)
		if path == DUEL_MODEL: continue
		var alias := _alias(source, DUEL_MODEL)
		if alias.is_empty(): continue
		_check(_found("\\b" + alias + "\\.(?:ticks|steps)\\(", source) == 0, "%s reads a duel side's time or steps itself: show them through DuelModel.lane(), which sets the pair ahead beside the pair behind" % path)
		if _found("\\b" + alias + "\\.lane\\(", source) == 0: continue
		seen[path] = true
		_check(DUEL_TIME_SURFACES.has(path), "%s shows a duel time: add it to DUEL_TIME_SURFACES with where" % path)
	for path: String in DUEL_TIME_SURFACES:
		_check(seen.has(path), "DUEL_TIME_SURFACES names %s, which shows no duel time through DuelModel.lane() now: delete it" % path)
	for path: String in RAW_DUEL_TIME_EXEMPT:
		_check(raw.has(path), "RAW_DUEL_TIME_EXEMPT names %s, which reads no duel time off a view now: delete it" % path)

# (j) and the guard suites ---------------------------------------------------

func _suites() -> void:
	var shards := {}
	for line: String in FileAccess.get_file_as_string("res://tests/ci_shards.txt").split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() >= 2 and not parts[0].begins_with("#"): shards[parts[0]] = parts[1]
	for suite: String in GUARD_SUITES:
		_check(shards.get(suite, "skip") in ["1", "2", "3"], "test_%s.gd guards a shared path and runs in CI (tests/ci_shards.txt)" % suite)

# Helpers --------------------------------------------------------------------

## A check that may be on KNOWN_FAILURES.
func _rule(id: String, ok: bool, message: String) -> void:
	if not KNOWN_FAILURES.has(id):
		_check(ok, message)
		return
	_known_seen[id] = true
	if ok:
		_check(false, "'%s' passes now (%s): delete it from KNOWN_FAILURES" % [id, KNOWN_FAILURES[id]])
		return
	known += 1
	print("KNOWN: %s: %s" % [id, KNOWN_FAILURES[id]])

## `text` with every comment line emptied, so line numbers stay.
static func _code(text: String) -> String:
	var lines := text.replace("\r\n", "\n").split("\n")
	for index in range(lines.size()):
		if lines[index].strip_edges().begins_with("#"): lines[index] = ""
	return "\n".join(lines)

## The const name `source` preloads `script` under, or "".
static func _alias(source: String, script: String) -> String:
	var match := RegEx.create_from_string("(?m)^const\\s+(\\w+)\\s*:?=\\s*preload\\(\"" + script + "\"\\)").search(source)
	return "" if match == null else match.get_string(1)

static func _found(pattern: String, source: String) -> int:
	return RegEx.create_from_string(pattern).search_all(source).size()

static func _scripts(directory: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(directory)
	if dir == null: return found
	for name: String in dir.get_directories():
		if name.begins_with(".") or (directory == "res://" and name in ["addons", "tests"]): continue
		found.append_array(_scripts(directory.path_join(name)))
	for name: String in dir.get_files():
		if name.ends_with(".gd"): found.append(directory.path_join(name))
	return found

func _check(condition: bool, message: String) -> void:
	checks += 1
	if condition: return
	failures += 1
	push_error(message)
