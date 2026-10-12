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

## {cues, sources} for one tick's events; unmapped names pass through and stay
## silent unless the soundscape has a clip of that name.
static func cues(chapter_key: String, state: Dictionary) -> Dictionary:
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
