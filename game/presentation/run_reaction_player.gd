extends RefCounted
## Reactions made during a run, recorded and shown over a chapter world. Every
## screen that steps a turn holds one: the chapter screen (relay_preview.gd),
## live, on retry and in its replays, and the shared replay view. It records the
## live turn's own reactions and plays recorded tracks back on their spirits, at
## the tick each was made, so the friend's memory, a retry and a replay make
## the same face, bubble and sound. Presentation only: it reads ticks and never
## touches the simulation, its recording, timers or goal credit.
##
## A reaction shows as the spirit's face for FACE_SECONDS (SpiritVisual's timed
## expression, which a doze gives way to), a bubble just above its name for
## BUBBLE_SECONDS, and the reaction's pop (Soundscape.play_run_reaction, pitched
## from the track alone). Rules and tracks: services/run_reaction_track.gd.
##
## The screen sets world, hud, soundscape and settings, then per turn:
##   begin(live_slot)                 a live turn on tick zero (or "" for none)
##   play(recording, track, caption)  a recorded turn stepped alongside it
##   step(tick)                       after each shown tick
##   react(tick, face)                the player's own reaction now
const Track = preload("res://services/run_reaction_track.gd")
const Catalog = preload("res://services/reaction_catalog.gd")
const Look = preload("res://presentation/spirit_look.gd")
const EndReactions = preload("res://presentation/end_reactions.gd")
## The bubble's tail points this far above the spirit's feet: just over its name.
const BUBBLE_HEIGHT := 2.0

var world: Node
var hud: Control
var soundscape: Node
var settings: Dictionary = {}
## The live turn's own track, and the slot of the spirit it belongs to.
var live := Track.new()
var live_slot := ""
## Recorded turns being played: {slot, track, cursor, caption}.
var _runs: Array = []

## A turn starts on tick zero: what was recorded or played before is dropped.
## `slot` is the live spirit's ("p0" or "p1"), or "" when nothing is played live.
func begin(slot: String = "") -> void:
	live = Track.new()
	live_slot = slot
	_runs.clear()

## A recorded turn (its `player_slot` names its spirit) plays `track` back as the
## turn is stepped. `caption` goes over each bubble (a friend's turn).
func play(recording: Dictionary, track: Array, caption: String = "") -> void:
	var slot := str(recording.get("player_slot", ""))
	if track.is_empty() or not Look.SLOT_COLOR_NAMES.has(slot): return
	_runs.append({"slot": slot, "track": track, "cursor": Track.Cursor.new(track), "caption": caption})

## After each tick that is shown: every recorded reaction that falls on it.
func step(tick: int) -> void:
	for run: Dictionary in _runs:
		for index: int in run.cursor.due(tick): show_reaction(run.slot, run.track, index, run.caption)

## The player's own reaction on `tick`: recorded in the live track and shown.
## False when the rules refuse it (the cooldown, the cap, no live spirit).
func react(tick: int, face: String) -> bool:
	if live_slot.is_empty(): return false
	var index := live.add(tick, face)
	if index < 0: return false
	show_reaction(live_slot, live.entries, index)
	if is_instance_valid(soundscape) and soundscape.has_method("tap_haptic"): soundscape.tap_haptic()
	return true

## Shows the reaction at `index` of `track` on the spirit in `slot`.
func show_reaction(slot: String, track: Array, index: int, caption: String = "") -> void:
	var face := str(track[index].get("id", ""))
	if not Catalog.is_face(face) or not is_instance_valid(world): return
	var actors: Variant = world.get("actors")
	var actor: Variant = actors.get(slot) if actors is Dictionary else null
	if actor is Node3D and is_instance_valid(actor) and actor.has_method("show_expression"):
		actor.show_expression(Catalog.spirit_expression(face), Track.FACE_SECONDS)
	var camera: Variant = world.get("camera")
	if actor is Node3D and camera is Camera3D and is_instance_valid(hud):
		var at: Variant = EndReactions.point_above(camera, actor, hud, BUBBLE_HEIGHT)
		if at is Vector2:
			var refs := [weakref(camera), weakref(actor), weakref(hud)]
			var follow := func() -> Variant: return EndReactions.point_above(refs[0], refs[1], refs[2], BUBBLE_HEIGHT)
			EndReactions.pop(hud, at, face, str(Look.SLOT_COLOR_NAMES.get(slot, "peach")), settings, Track.BUBBLE_SECONDS, follow, caption)
	if is_instance_valid(soundscape) and soundscape.has_method("play_run_reaction"): soundscape.play_run_reaction(slot, track, index)
