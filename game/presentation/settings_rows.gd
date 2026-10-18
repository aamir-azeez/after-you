extends RefCounted
## Everything Settings holds, as data: the categories in the rail and one row
## per setting. presentation/settings_flow.gd draws a category's rows with the
## shared builders in presentation/settings_kit.gd and saves through Main.
##
## A new setting is one row here (and, for a runtime effect, a line in Main's
## _apply_settings). A new category is one entry in categories(); its rows
## name it. The rail's live summaries come from the same rows.
##
## A row:
## - id: unique; the name of its control on the page.
## - category: a category id.
## - kind: TOGGLE (on/off, drawn as a tile with its "icon" in a two-column
##   grid above the category's other rows), CHOICE (one of "options": [[value, label], ...]),
##   LINK (opens another screen: "open"), ACTION (acts in place: "run", or
##   "inline" which gets the row's Detail box and the row) or INFO (text only).
## - label, note: PlayerCopy text, or a Callable for text that changes.
## - key: the saved setting it reads and writes (host.saves settings), or
##   "get" and "set" (returns whether it was kept) for a value of its own.
## - visible_if, enabled_if: Callables; shown and enabled when absent.
## - on_change: called with the new value once it is saved.
## - summary: the name it goes by in its category's summary ("Notifications").
## - danger: a destructive action, drawn apart in coral.
## - expand: a Callable returning more rows to draw in its place (licences).
const PlayerCopy = preload("res://presentation/player_copy.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const GraphicsPolicy = preload("res://services/graphics_policy.gd")
const Licenses = preload("res://services/licenses.gd")
const RoomsApi = preload("res://services/rooms_api.gd")
const HistoryStore = preload("res://services/history_store.gd")
const Changelog = preload("res://services/changelog.gd")

const EVERYDAY := "everyday"
const PLAY := "play"
const GRAPHICS := "graphics"
const FRIENDS := "friends"
const ACCOUNT := "account"
const ABOUT := "about"

const TOGGLE := "toggle"
const CHOICE := "choice"
const LINK := "link"
const ACTION := "action"
const INFO := "info"

## The rail, top to bottom. summary: a fixed line, or summary_rows: the rows
## whose values make it ("Balanced · 60 fps"). reset: rows the title row's
## Reset puts back to their defaults. on_open: called when the category shows.
static func categories(host: Node) -> Array[Dictionary]:
	return [
		{"id": EVERYDAY, "title": PlayerCopy.SETTINGS_EVERYDAY, "icon": preload("res://assets/ui/whats_new/leaf.svg"), "summary": PlayerCopy.SETTINGS_EVERYDAY_SUMMARY},
		{"id": PLAY, "title": PlayerCopy.SETTINGS_PLAY, "icon": preload("res://assets/ui/settings/play.svg"), "summary": PlayerCopy.SETTINGS_PLAY_SUMMARY},
		{"id": GRAPHICS, "title": PlayerCopy.SETTINGS_GRAPHICS, "icon": preload("res://assets/ui/settings/monitor.svg"), "summary_rows": ["graphics_quality", "frame_rate"],
			"reset": {"rows": ["graphics_quality", "frame_rate"], "label": PlayerCopy.SETTINGS_RESET_GRAPHICS, "confirm": PlayerCopy.SETTINGS_RESET_GRAPHICS_CONFIRM}},
		{"id": FRIENDS, "title": PlayerCopy.SETTINGS_FRIENDS, "icon": preload("res://assets/ui/whats_new/people.svg"), "summary_rows": ["turn_notifications"],
			"on_open": func(): host.notification_flow.reconcile()},
		{"id": ACCOUNT, "title": PlayerCopy.SETTINGS_ACCOUNT, "icon": preload("res://assets/ui/settings/user.svg"), "summary": PlayerCopy.SETTINGS_ACCOUNT_SUMMARY},
		{"id": ABOUT, "title": PlayerCopy.SETTINGS_ABOUT, "icon": preload("res://assets/ui/settings/info.svg"), "summary": PlayerCopy.SETTINGS_ABOUT_SUMMARY},
	]

## Every row, in order. Callables read Main through `host` when they run.
static func rows(host: Node) -> Array[Dictionary]:
	var notices: Node = host.notification_flow
	var account: Node = host.account_flow
	var state := func(names: Array) -> Callable: return func() -> bool: return account.panel_state() in names
	return [
		{"id": "sound", "icon": preload("res://assets/ui/settings/sound.svg"), "category": EVERYDAY, "kind": TOGGLE, "label": PlayerCopy.SETTINGS_SOUND, "note": PlayerCopy.SETTINGS_SOUND_NOTE, "key": "sound"},
		{"id": "haptics", "icon": preload("res://assets/ui/settings/haptics.svg"), "category": EVERYDAY, "kind": TOGGLE, "label": PlayerCopy.SETTINGS_HAPTICS, "note": PlayerCopy.SETTINGS_HAPTICS_NOTE, "key": "haptics"},
		{"id": "skip_waits", "icon": preload("res://assets/ui/settings/skip.svg"), "category": EVERYDAY, "kind": TOGGLE, "label": PlayerCopy.SETTINGS_SKIP_WAITS, "note": PlayerCopy.SETTINGS_SKIP_WAITS_NOTE, "key": "skip_waits"},
		{"id": "reduced_motion", "icon": preload("res://assets/ui/settings/calm.svg"), "category": EVERYDAY, "kind": TOGGLE, "label": PlayerCopy.SETTINGS_REDUCED_MOTION, "note": PlayerCopy.SETTINGS_REDUCED_MOTION_NOTE, "key": "reduced_motion"},

		{"id": "assistance", "icon": preload("res://assets/ui/settings/catch.svg"), "category": PLAY, "kind": TOGGLE, "label": PlayerCopy.SETTINGS_ASSISTANCE, "note": PlayerCopy.SETTINGS_ASSISTANCE_NOTE, "key": "assistance"},
		{"id": "left_handed", "icon": preload("res://assets/ui/settings/swap.svg"), "category": PLAY, "kind": TOGGLE, "label": PlayerCopy.MAIN_A1E007823FF0, "note": PlayerCopy.SETTINGS_LEFT_HANDED_NOTE, "key": "left_handed"},
		{"id": "photo_prompts", "icon": preload("res://assets/ui/settings/camera.svg"), "category": PLAY, "kind": TOGGLE, "label": PlayerCopy.MAIN_289D745F1246, "note": PlayerCopy.SETTINGS_PHOTO_PROMPTS_NOTE, "key": "photo_prompts"},

		{"id": "graphics_quality", "category": GRAPHICS, "kind": CHOICE, "label": PlayerCopy.SETTINGS_QUALITY, "note": PlayerCopy.SETTINGS_QUALITY_NOTE, "key": "graphics_quality",
			"options": GraphicsPolicy.QUALITIES.map(func(quality: String) -> Array: return [quality, quality.capitalize()])},
		{"id": "frame_rate", "category": GRAPHICS, "kind": CHOICE, "label": PlayerCopy.SETTINGS_FRAME_RATE, "note": PlayerCopy.SETTINGS_FRAME_RATE_NOTE, "key": "frame_rate",
			"options": [["30", PlayerCopy.SETTINGS_FPS_30], ["60", PlayerCopy.SETTINGS_FPS_60], ["unlimited", PlayerCopy.SETTINGS_FPS_UNLIMITED]]},

		{"id": "share_online_status", "icon": preload("res://assets/ui/whats_new/people.svg"), "category": FRIENDS, "kind": TOGGLE, "label": PlayerCopy.SETTINGS_ONLINE_STATUS, "note": PlayerCopy.SETTINGS_ONLINE_STATUS_NOTE, "key": "share_online_status"},
		{"id": "notifications_about", "category": FRIENDS, "kind": INFO, "label": PlayerCopy.SETTINGS_NOTIFICATIONS,
			"note": PlayerCopy.for_platform(PlayerCopy.MAIN_EF43E19393E4, PlayerCopy.MAIN_EF43E19393E4_IOS)},
		{"id": "turn_notifications", "icon": preload("res://assets/ui/whats_new/bell.svg"), "category": FRIENDS, "kind": TOGGLE, "label": PlayerCopy.MAIN_C4B947AAAE59, "note": notices.status_line,
			"get": notices.turn_notifications_on, "set": notices.set_turn_notifications, "summary": PlayerCopy.SETTINGS_NOTIFICATIONS},
		{"id": "turn_requests", "icon": preload("res://assets/ui/settings/reset.svg"), "category": FRIENDS, "kind": TOGGLE, "label": PlayerCopy.TURN_REQUEST_NOTIFICATIONS,
			"note": func() -> String: return "" if notices.turn_notifications_on() else PlayerCopy.TURN_REQUEST_NOTIFICATIONS_NEEDS_TURNS,
			"get": notices.turn_requests_on, "set": notices.set_turn_requests, "enabled_if": notices.turn_notifications_on},
		{"id": "notifications_off", "category": FRIENDS, "kind": ACTION, "label": PlayerCopy.SETTINGS_TURN_OFF, "run": notices.turn_off, "enabled_if": notices.turn_notifications_on},

		{"id": "account_intro", "category": ACCOUNT, "kind": INFO, "label": "", "visible_if": state.call(["pending", "restart", "ready", "missing", "unread", "offline"]),
			"note": PlayerCopy.for_platform(PlayerCopy.MAIN_F890477C65DE, PlayerCopy.MAIN_F890477C65DE_IOS)},
		{"id": "cleanup_note", "category": ACCOUNT, "kind": INFO, "label": "", "note": PlayerCopy.MAIN_EC79109D7607, "visible_if": state.call(["cleanup"])},
		{"id": "retry_cleanup", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_RETRY_CLEANUP, "run": account.clear_deleted_identity, "visible_if": state.call(["cleanup"])},
		{"id": "check_deleted_identity", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_CHECK_IDENTITY, "run": account.retry_deleted_identity_read,
			"visible_if": func() -> bool: return account.panel_state() == "cleanup" and account.identity_unread()},
		{"id": "pending_note", "category": ACCOUNT, "kind": INFO, "label": "", "note": PlayerCopy.MAIN_93BF3A28C6F9, "visible_if": state.call(["pending"])},
		{"id": "finish_recovery", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_FINISH_RECOVERY, "run": account.resume_pending_recovery, "visible_if": state.call(["pending"])},
		{"id": "restart_note", "category": ACCOUNT, "kind": INFO, "label": "", "note": PlayerCopy.MAIN_5BC549F4B951, "visible_if": state.call(["restart"])},
		{"id": "recovery_details", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_RECOVERY_DETAILS, "note": PlayerCopy.SETTINGS_RECOVERY_DETAILS_NOTE,
			"inline": account.toggle_recovery_details, "visible_if": func() -> bool: return account.panel_state() == "ready" or (account.panel_state() == "restart" and not host.identity_data.is_empty())},
		{"id": "close_app", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_CLOSE_APP, "run": func(): host.get_tree().quit(), "visible_if": state.call(["restart"])},
		{"id": "hosting_access", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_HOSTING_ACCESS, "note": PlayerCopy.SETTINGS_HOSTING_ACCESS_NOTE,
			"inline": func(detail: VBoxContainer, _row: Control): account.check_hosting_access(detail), "visible_if": state.call(["ready"]),
			"enabled_if": func() -> bool: return not account.hosting_check_busy},
		{"id": "restore_purchases", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_RESTORE, "note": PlayerCopy.SETTINGS_RESTORE_NOTE,
			"run": host.store_flow.restore_purchases, "visible_if": func() -> bool: return account.panel_state() == "ready" and host._play_store_enabled()},
		{"id": "tester_code", "category": ACCOUNT, "kind": LINK, "label": PlayerCopy.SETTINGS_TESTER, "note": PlayerCopy.SETTINGS_TESTER_NOTE,
			"open": host.store_flow.show_tester_access, "visible_if": func() -> bool: return PlatformSupport.tester_code_offered()},
		# Subscribers reach Manage subscription and Restore here once Home hides the offer.
		{"id": "full_journey", "category": ACCOUNT, "kind": LINK, "label": PlayerCopy.SETTINGS_FULL_JOURNEY, "note": PlayerCopy.SETTINGS_FULL_JOURNEY_NOTE,
			"open": host.store_flow.show_store_from_settings, "visible_if": host._play_store_enabled},
		{"id": "photo_transfer", "category": ACCOUNT, "kind": LINK, "label": PlayerCopy.SETTINGS_PHOTO_TRANSFER, "note": PlayerCopy.SETTINGS_PHOTO_TRANSFER_NOTE,
			"open": account.open_photo_transfer, "visible_if": state.call(["ready"])},
		# Room history is never removed automatically, so show what it takes.
		{"id": "room_history", "category": ACCOUNT, "kind": INFO, "note": "",
			"label": func() -> String: return PlayerCopy.MAIN_ROOM_HISTORY_SPACE % HistoryStore.size_text(HistoryStore.new().usage_bytes()),
			"visible_if": func() -> bool: return account.panel_state() == "ready" and RoomsApi.history_supported},
		{"id": "safety_reports", "category": ACCOUNT, "kind": LINK, "label": PlayerCopy.SETTINGS_REPORTS, "note": PlayerCopy.SETTINGS_REPORTS_NOTE,
			"open": account.open_safety, "visible_if": state.call(["ready"])},
		{"id": "create_identity", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_CREATE_IDENTITY, "run": account.create_identity, "visible_if": state.call(["missing"])},
		{"id": "unread_note", "category": ACCOUNT, "kind": INFO, "label": "", "note": PlayerCopy.MAIN_3E50EF2B7ECB, "visible_if": state.call(["unread"])},
		{"id": "check_identity", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_CHECK_IDENTITY, "run": account.retry_saved_identity, "visible_if": state.call(["unread"])},
		{"id": "offline_note", "category": ACCOUNT, "kind": INFO, "label": "", "visible_if": state.call(["offline"]),
			"note": PlayerCopy.for_platform(PlayerCopy.MAIN_570EC629872D, PlayerCopy.MAIN_570EC629872D_IOS)},
		{"id": "recover_identity", "category": ACCOUNT, "kind": LINK, "label": PlayerCopy.SETTINGS_RECOVER, "note": PlayerCopy.SETTINGS_RECOVER_NOTE,
			"open": account.show_recovery_form, "visible_if": func() -> bool: return account.panel_state() in ["ready", "missing", "unread"] and host.api.configured() and host.secrets.is_available()},
		{"id": "delete_identity", "category": ACCOUNT, "kind": ACTION, "label": PlayerCopy.SETTINGS_DELETE_IDENTITY, "danger": true,
			"run": func(): account.confirm_delete_identity(), "visible_if": state.call(["ready"])},

		{"id": "community", "category": ABOUT, "kind": LINK, "label": PlayerCopy.SETTINGS_COMMUNITY, "note": PlayerCopy.SETTINGS_COMMUNITY_NOTE, "open": func(): host._open_safety()},
		{"id": "whats_new", "category": ABOUT, "kind": LINK, "label": PlayerCopy.WHATS_NEW, "note": PlayerCopy.WHATS_NEW_VERSION % Changelog.current_version(),
			"open": func(): host._open_whats_new_card()},
		{"id": "licenses", "category": ABOUT, "kind": INFO, "label": PlayerCopy.SETTINGS_LICENSES, "note": PlayerCopy.MAIN_0A022EF54291, "expand": func() -> Array: return license_rows(host)},
	]

## One row per bundled licence; each opens its full text.
static func license_rows(host: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var entries: Array[Dictionary] = Licenses.entries()
	for index: int in range(entries.size()):
		var entry: Dictionary = entries[index]
		result.append({"id": license_id(index), "category": ABOUT, "kind": LINK, "label": str(entry.title), "open": func(): host.settings_flow.show_license(entry, license_id(index))})
	return result

static func license_id(index: int) -> String:
	return "license_%d" % index

## What a row's value reads as in a summary: On or Off, or the option's label.
static func value_text(row: Dictionary, value: Variant) -> String:
	if row.kind == CHOICE:
		for option: Array in row.options:
			if str(option[0]) == str(value): return str(option[1])
		return ""
	var text := PlayerCopy.SETTINGS_ON if value == true else PlayerCopy.SETTINGS_OFF
	return PlayerCopy.SETTINGS_SUMMARY_NAMED % [row.summary, text] if row.has("summary") else text

## A category's line under its name in the rail. value_of reads a row's value.
static func summary(category: Dictionary, all_rows: Array[Dictionary], value_of: Callable) -> String:
	if not category.has("summary_rows"): return str(category.get("summary", ""))
	var parts: PackedStringArray = []
	for id: String in category.summary_rows:
		var row := find(all_rows, id)
		if not row.is_empty(): parts.append(value_text(row, value_of.call(row)))
	return " · ".join(parts)

static func find(all_rows: Array[Dictionary], id: String) -> Dictionary:
	for row: Dictionary in all_rows:
		if row.id == id: return row
	return {}

static func category(all_categories: Array[Dictionary], id: String) -> Dictionary:
	for entry: Dictionary in all_categories:
		if entry.id == id: return entry
	return {}

## A row's text that may change: a Callable is read now.
static func text(value: Variant) -> String:
	return str(value.call()) if value is Callable else str(value)

static func shown(row: Dictionary) -> bool:
	return not row.has("visible_if") or bool(row.visible_if.call())

static func enabled(row: Dictionary) -> bool:
	return not row.has("enabled_if") or bool(row.enabled_if.call())

## The rows a category draws, in order, with expanded rows in place.
static func in_category(all_rows: Array[Dictionary], id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in all_rows:
		if row.category != id or not shown(row): continue
		result.append(row)
		if row.has("expand"): result.append_array(row.expand.call())
	return result
