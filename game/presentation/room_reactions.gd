extends RefCounted
## Preset text and participant-scoped presentation for legacy island rooms.
## No account names, arbitrary message text or credentials enter the display.
const PRESETS := {"love": "Beautiful!", "sparkles": "We did it!", "again": "Again soon"}
const MAX_NOTICES := 128

static func code_for_label(label: String) -> String:
	for code: String in PRESETS:
		if PRESETS[code] == label:
			return code
	return ""

static func rows(room: Dictionary, viewer: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var host: String = room.get("host_id", "") if room.get("host_id") is String else ""
	var guest: String = room.get("guest_id", "") if room.get("guest_id") is String else ""
	var reactions: Variant = room.get("reactions", {})
	if viewer.is_empty() or viewer not in [host, guest] or room.get("active_role") != "complete" or not reactions is Dictionary:
		return result
	# Put the friend's response first; do not expose player identifiers as labels.
	var partner: String = guest if viewer == host else host
	for player: String in [partner, viewer]:
		if player.is_empty() or (player == viewer and partner == viewer):
			continue
		var code: Variant = reactions.get(player)
		if code is String and PRESETS.has(code):
			result.append({"own": player == viewer, "code": code, "text": ("Your reaction: " if player == viewer else "Your friend reacted: ") + PRESETS[code]})
	return result

static func same_completed_room(first: Dictionary, second: Dictionary) -> bool:
	return not str(first.get("room_id", "")).is_empty() and first.get("room_id") == second.get("room_id") \
		and first.get("active_role") == "complete" and second.get("active_role") == "complete" \
		and int(first.get("attempt", -1)) == int(second.get("attempt", -2)) \
		and first.get("level_id") == second.get("level_id") \
		and int(first.get("level_index", -1)) == int(second.get("level_index", -2)) \
		and first.get("host_id") == second.get("host_id") and first.get("guest_id") == second.get("guest_id")

static func new_partner_notice(previous: Dictionary, current: Dictionary, viewer: String, seen: Dictionary) -> String:
	# First opening a room renders its existing reactions without announcing old
	# messages as new. Fresh changes in the same completed attempt may notify.
	if not same_completed_room(previous, current):
		return ""
	var before: String = ""
	for row: Dictionary in rows(previous, viewer):
		if not row.own:
			before = row.code
	for row: Dictionary in rows(current, viewer):
		if row.own or row.code == before:
			continue
		var notice_key := JSON.stringify([viewer, current.room_id, int(current.attempt), current.level_id, int(current.level_index), current.host_id, current.guest_id, row.code]).sha256_text()
		if seen.has(notice_key):
			return ""
		while seen.size() >= MAX_NOTICES:
			seen.erase(seen.keys()[0])
		seen[notice_key] = true
		return row.text
	return ""
