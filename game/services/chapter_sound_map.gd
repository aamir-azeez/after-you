extends RefCounted
## Which sound cue each tick of a registry chapter plays, and who caused it
## (the cue's identity, so its pitch is the same live, as the memory, on a
## retry and in a replay). Shared by the chapter screens, shared replays and
## the memory wait. Presentation only: it reads snapshots, never the engines.
##
## Cues come from the tick's events and from what changed since the previous
## tick. `seen` is the caller's per-turn memory of the snapshot: start it with
## remember() wherever the simulation resets. A changed lever, switch, mirror,
## water level or hand-off is named by its object, which is how the memory
## spirit's own actions in the second turn sound: its engine replays them into
## the snapshot without their events. With no memory yet (or a snapshot that
## lacks the field) the events alone decide, as before.
## Cue names and their sounds are services/sound_cues.gd.

const Registry = preload("res://services/chapter_registry.gd")
## A chapter's own cues and water levels are in its descriptor
## (content/chapters/index.gd).
const Index = preload("res://content/chapters/index.gd")
const Soundscape = preload("res://services/soundscape.gd")
## A control drawn as a machine (descriptor "lever_looks") plays its look's cue.
const SoundCues = preload("res://services/sound_cues.gd")
## Read for its walking step only: a tick walks at most MOVE_PER_TICK 1 cm
## steps, and the engine calls a fall of more than 2 cm in one step a drop.
const Runtime = preload("res://core/physical/runtime.gd")
const DROP_FALL_CM := 2 * Runtime.MOVE_PER_TICK

## Cues for the physical and journey chapters' own events.
const PHYSICAL := {
	"stage_complete": "island_bloomed",
	"lever": "lever_pulled",
	# A drop through a hatch or a well mouth lands with the same soft thud.
	"drop": "seed_landed",
	"bell": "bell_rung",
	"handoff_offer": "handoff_offered",
	"handoff_claim": "seed_caught",
}
## Cues for First Steps' lift and loft.
const FIRST_STEPS := {
	"lift_arrived": "lift_ready",
	"loft_opened": "bell_rung",
}
## Cues for the Lighthouse's mirrors, lens, bells and route (both versions).
const LIGHTHOUSE := {"mirror_rotated": "switch_set", "route_selected": "switch_set", "lens_taken": "seed_caught", "lens_offered": "handoff_offered",
	"lens_fitted": "seed_landed", "beacon_lit": "bell_rung", "court_activated": "bell_rung", "tower_anchored": "tower_bell",
	"receivers_joined": "receivers_joined", "path_kept": "waypoint", "rest_reached": "waypoint", "tower_reached": "waypoint",
	# The second turn's stand-in for the memory's offer: the same cue and identity.
	"lens_available": "handoff_offered"}
## Events whose cue takes another event's identity, so both turns agree.
const LIGHTHOUSE_SOURCES := {"lens_available": "a|lens_offered"}
## No chapter cues or water levels: shared and never written.
const NO_TABLE := {}
## A tick with no cue, and a diff with no change: shared and never written.
const NO_CUES := {"cues": [], "sources": []}
const NONE := []
## A field whose ids appear only once set: an id missing so far had this value
## (an engine adds a lever the first time it is pulled).
const UNSET := {"levers": false}
const NO_TURNS := [[], []]

## A fresh per-turn memory from the snapshot at tick zero.
static func remember(state: Dictionary) -> Dictionary:
	var seen := {}
	_track(seen, state)
	return seen

## {cues, sources} for one tick; unmapped events pass through and stay silent
## unless the soundscape has a cue of that name. Updates `seen` in place.
static func cues(chapter_key: String, state: Dictionary, seen: Dictionary = {}) -> Dictionary:
	if Registry.is_lighthouse(chapter_key): return lighthouse(state, seen)
	var role := str(state.get("role", ""))
	var cooperative := Registry.is_cooperative(chapter_key)
	var journey := Registry.is_journey(chapter_key)
	# Known before this tick, in a chapter that diffs it: then the change, not
	# the event, names the cue. (remember() tracks every field it sees.)
	var levers_known := cooperative and seen.has("levers")
	var controls_known := journey and seen.has("controls")
	var levers := _changed(seen, "levers", state) if cooperative else NONE
	var controls := _changed(seen, "controls", state) if journey else NONE
	var props := _changed(seen, "props", state) if cooperative else NONE
	var closed: Array = _bridge_changes(seen, state)[1]
	var ghost_drop := _ghost_dropped(seen, state) if cooperative else false
	var events: Array = state.get("events", [])
	if events.is_empty() and levers.is_empty() and controls.is_empty() and props.is_empty() and closed.is_empty() and not ghost_drop: return NO_CUES
	var chapter := Index.data(chapter_key)
	var overrides: Dictionary = chapter.get("sound_cues", NO_TABLE)
	var looks: Dictionary = chapter.get("lever_looks", NO_TABLE)
	var out := {"cues": [], "sources": []}
	for event: String in events:
		# Lever and switch cues come from the change itself, named by the object.
		if event == "lever" and levers_known: continue
		if event.begins_with("selector:") and controls_known: continue
		var cue := event
		if overrides.has(event): cue = overrides[event]
		elif event.begins_with("bridge_opened:"): cue = "bridge_opened"
		# Tide rules: a crossing starts to close under rising water; a spirit
		# caught on one as it shuts.
		elif event.begins_with("closing:"): cue = "crossing_closing"
		elif event.begins_with("drowned:"): cue = "spirit_drowned"
		elif event == "relay_filled": cue = "garden_opened"
		elif event == "garden_bloomed": cue = "island_bloomed"
		elif cooperative and PHYSICAL.has(event): cue = PHYSICAL[event]
		elif cooperative and event.begins_with("selector:"): cue = SoundCues.look_cue(str(looks.get(event.trim_prefix("selector:"), "")), "switch_set")
		elif chapter_key == Registry.FIRST_STEPS and FIRST_STEPS.has(event): cue = FIRST_STEPS[event]
		_add(out, cue, Soundscape.event_source(event, role))
	for id: String in levers:
		var released := not bool(state.levers[id])
		_add(out, SoundCues.look_cue(str(looks.get(id, "")), "lever_pulled", released), "lever:%s|lever:%s" % [id, id])
	var water_moved := false
	for id: String in controls:
		_add(out, SoundCues.look_cue(str(looks.get(id, "")), "switch_set"), "selector:%s|selector:%s" % [id, id])
		var levels: Array = chapter.get("water_levels", NO_TABLE).get(id, NONE)
		if not levels.is_empty():
			var rising := levels.find(str(state.controls[id])) > levels.find(str(seen.previous_controls.get(id, "")))
			_add(out, "water_rise" if rising else "water_fall", "water:%s|water" % id)
			water_moved = true
	for id: String in props:
		var status := str(state.props[id].get("status", ""))
		# The memory's offer replays without its event in the second turn.
		if status == "offered" and not events.has("handoff_offer"): _add(out, "handoff_offered", "a|handoff_offer")
		elif status == "fitted" and overrides.has("prop_fitted"): _add(out, overrides.prop_fitted, "b|prop_fitted")
	if ghost_drop: _add(out, overrides.get("drop", PHYSICAL.drop), "a|drop")
	# Crossings the water just covered go under with the water's own sound.
	if not water_moved:
		for id: String in closed: _add(out, "bridge_closed", "bridge_opened:%s|bridge_closed" % id)
	return out

## The Lighthouse's ticks. Its engine says only "bridge_open" and
## "bridge_closed", so each is named by the bridge that changed, found against
## `seen`; mirrors and routes are named by the control that turned.
static func lighthouse(state: Dictionary, seen: Dictionary) -> Dictionary:
	var role := str(state.get("role", ""))
	var turned := _bridge_changes(seen, state)
	var opened: Array = turned[0]
	var closed: Array = turned[1]
	var mirrors_known := seen.has("mirrors")
	var selectors_known := seen.has("selectors")
	var mirrors := _changed(seen, "mirrors", state)
	var selectors := _changed(seen, "selectors", state)
	var props := _changed(seen, "props", state)
	var events: Array = state.get("events", [])
	if events.is_empty() and mirrors.is_empty() and selectors.is_empty() and props.is_empty(): return NO_CUES
	var out := {"cues": [], "sources": []}
	for event: String in events:
		var named := event
		if event == "bridge_open":
			if not opened.is_empty(): named = "bridge_open:" + str(opened.pop_front())
			_add(out, "bridge_opened", Soundscape.event_source(named, role))
		elif event == "bridge_closed":
			if not closed.is_empty(): named = "bridge_open:%s|bridge_closed" % str(closed.pop_front())
			_add(out, "bridge_closed", named if named.contains("|") else Soundscape.event_source(named, role))
		elif event == "stage_complete": _add(out, "island_bloomed", Soundscape.event_source(event, role))
		elif event == "mirror_rotated" and mirrors_known: continue
		elif event == "route_selected" and selectors_known: continue
		elif LIGHTHOUSE.has(event): _add(out, LIGHTHOUSE[event], LIGHTHOUSE_SOURCES.get(event, Soundscape.event_source(event, role)))
	# A selector turns its own mirror too (they share an id): one cue for both.
	for id: String in mirrors:
		if not selectors.has(id): _add(out, "switch_set", "mirror:%s|mirror:%s" % [id, id])
	for id: String in selectors: _add(out, "switch_set", "route:%s|route:%s" % [id, id])
	# The memory taking the lens replays without its event in the second turn.
	for id: String in props:
		var prop: Dictionary = state.props[id]
		if str(prop.get("status", "")) == "carried" and _is_ghost(state, str(prop.get("holder_slot", ""))) and not events.has("lens_taken"):
			_add(out, "seed_caught", "a|lens_taken")
	return out

static func _add(out: Dictionary, cue: String, source: String) -> void:
	out.cues.append(cue)
	out.sources.append(source)

## Starts remembering every field a diff reads.
static func _track(seen: Dictionary, state: Dictionary) -> void:
	for field: String in ["levers", "controls", "mirrors", "selectors", "props", "bridges"]:
		if state.get(field) is Dictionary: _track_field(seen, field, state[field])
	var heights := {}
	var players: Variant = state.get("players")
	if players is Dictionary:
		for slot: Variant in players:
			if _ghost(players[slot]): heights[slot] = int(players[slot].get("height", 0))
	seen["ghost_heights"] = heights

static func _track_field(seen: Dictionary, field: String, now: Dictionary) -> void:
	if field == "props":
		var statuses := {}
		for id: Variant in now: statuses[id] = _status(now[id])
		seen[field] = statuses
	else: seen[field] = now.duplicate()

## Ids whose value changed since the last tick, in snapshot order; `seen` is
## updated in place. A field seen for the first time is only remembered.
static func _changed(seen: Dictionary, field: String, state: Dictionary) -> Array:
	var now: Variant = state.get(field)
	if not now is Dictionary: return NONE
	if not seen.has(field):
		_track_field(seen, field, now)
		return NONE
	var before: Dictionary = seen[field]
	var changed: Array = NONE
	var unset: Variant = UNSET.get(field)
	for id: Variant in now:
		var value: Variant = _status(now[id]) if field == "props" else now[id]
		var was: Variant = before.get(id, unset)
		if was == value: continue
		if was != null:
			if changed.is_read_only(): changed = []
			changed.append(str(id))
			if field == "controls":
				# The water cue compares the new level with the one before.
				if not seen.has("previous_controls"): seen["previous_controls"] = {}
				seen.previous_controls[str(id)] = was
		before[id] = value
	return changed

static func _status(prop: Variant) -> String:
	return str(prop.get("status", "")) if prop is Dictionary else str(prop)

## [opened, closed]: bridge ids that opened and closed since the last tick.
## A bridge missing from the memory counts as closed. Updates `seen`.
static func _bridge_changes(seen: Dictionary, state: Dictionary) -> Array:
	var bridges: Variant = state.get("bridges")
	if not bridges is Dictionary: return NO_TURNS
	if not seen.has("bridges"): seen["bridges"] = {}
	var before: Dictionary = seen.bridges
	var opened: Array = NONE
	var closed: Array = NONE
	for id: Variant in bridges:
		var open := bool(bridges[id])
		if open == bool(before.get(id, false)):
			before[id] = open
			continue
		if open:
			if opened.is_read_only(): opened = []
			opened.append(str(id))
		elif before.has(id):
			if closed.is_read_only(): closed = []
			closed.append(str(id))
		before[id] = open
	return NO_TURNS if opened.is_empty() and closed.is_empty() else [opened, closed]

## The memory spirit fell further since the last tick than any walk can
## (DROP_FALL_CM): the drop its engine plays only for the live spirit.
static func _ghost_dropped(seen: Dictionary, state: Dictionary) -> bool:
	var players: Variant = state.get("players")
	if not players is Dictionary: return false
	if not seen.has("ghost_heights"): seen["ghost_heights"] = {}
	var before: Dictionary = seen.ghost_heights
	var dropped := false
	for slot: Variant in players:
		var player: Variant = players[slot]
		if not _ghost(player): continue
		var height := int(player.get("height", 0))
		if before.has(slot) and int(before[slot]) > height + DROP_FALL_CM: dropped = true
		before[slot] = height
	return dropped

static func _ghost(player: Variant) -> bool:
	return player is Dictionary and bool(player.get("ghost", false))

static func _is_ghost(state: Dictionary, slot: String) -> bool:
	return _ghost(state.get("players", {}).get(slot))
