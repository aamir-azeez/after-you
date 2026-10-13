extends RefCounted
## Which sound cue each simulation event plays in a registry chapter, and who
## caused it (Soundscape.event_source). Shared by the chapter screen and shared
## replays, so a turn sounds the same wherever it is watched. Presentation only.

const Registry = preload("res://services/chapter_registry.gd")
const Soundscape = preload("res://services/soundscape.gd")

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

## Cues for the Lighthouse's mirrors, lens and beacon (both versions).
const LIGHTHOUSE := {"mirror_rotated": "switch_set", "route_selected": "switch_set", "lens_taken": "seed_caught", "lens_offered": "handoff_offered", "lens_fitted": "seed_landed", "beacon_lit": "bell_rung", "court_activated": "bell_rung"}

## {cues, sources} for one tick's events; unmapped names pass through and stay
## silent unless the soundscape has a clip of that name. `seen` is the caller's
## per-turn memory, used only by the Lighthouse (see lighthouse()).
static func cues(chapter_key: String, state: Dictionary, seen: Dictionary = {}) -> Dictionary:
	if Registry.is_lighthouse(chapter_key): return lighthouse(state, seen)
	var sounds: Array = []
	var sources: Array = []
	var physical := Registry.is_cooperative(chapter_key)
	for event: String in state.get("events", []):
		if event.begins_with("bridge_opened:"):
			sounds.append("bridge_opened")
		elif event == "relay_filled":
			sounds.append("garden_opened")
		elif event == "garden_bloomed":
			sounds.append("island_bloomed")
		elif physical and PHYSICAL.has(event):
			sounds.append(PHYSICAL[event])
		elif physical and event.begins_with("selector:"):
			sounds.append("switch_set")
		elif chapter_key == Registry.FIRST_STEPS and FIRST_STEPS.has(event):
			sounds.append(FIRST_STEPS[event])
		else:
			sounds.append(event)
		sources.append(Soundscape.event_source(event, str(state.get("role", ""))))
	return {"cues": sounds, "sources": sources}

## The Lighthouse's events. Its engine says only "bridge_open", so a bridge that
## opens is named by its id, found against `seen` (the bridges at the previous
## tick, kept by the caller and updated here in place), and the memory's bridge
## sounds the same in both turns. Other events are silent.
static func lighthouse(state: Dictionary, seen: Dictionary) -> Dictionary:
	var sounds: Array = []
	var sources: Array = []
	var bridges: Dictionary = state.get("bridges", {})
	var opened: Array = []
	for id: Variant in bridges:
		if bool(bridges[id]) and not bool(seen.get(id, false)): opened.append(str(id))
		seen[id] = bridges[id]
	for event: String in state.get("events", []):
		var named := event
		if event == "bridge_open":
			sounds.append("bridge_opened")
			if not opened.is_empty(): named = "bridge_open:" + str(opened.pop_front())
		elif event == "stage_complete": sounds.append("island_bloomed")
		elif LIGHTHOUSE.has(event): sounds.append(LIGHTHOUSE[event])
		else: continue
		sources.append(Soundscape.event_source(named, str(state.get("role", ""))))
	return {"cues": sounds, "sources": sources}
