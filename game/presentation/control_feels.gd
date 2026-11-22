extends RefCounted
## Haptics for the controls a pip works: a short, light buzz of the phone when
## the screen's own live pip presses a pad down or steps off it, pulls a lever,
## turns a crank or a wheel a step, sets a selector, rings a bell, takes, puts
## down, gives, throws or catches an item, or opens a gate or a bridge by what
## it holds or pulls.
##
## Each action has a kind ("pad", "lever", "selector:valve", "bell", ...) and
## each kind a feel (KINDS), one of a few named FEELS. A kind KINDS does not
## name feels like its slot ("lever:teapot" like "lever"), else DEFAULT_FEEL,
## so a new piece style needs no code here. The actions are the simulation's
## events in ACTIONS (the pip's own presses, core/physical/runtime.gd
## _interact), plus a pad the pip stands on held and a gate or bridge opening
## while it acts or holds a pad.
##
## Only the live pip's own actions: MemoryWait.step, the one stepper every
## chapter screen feeds its ticks through, asks with `live` only for a tick of
## live play shown as it happens, so a memory, a replay, the friend's turn, a
## seek and a skipped tick never buzz. Within a live tick a memory's presses
## replay into the snapshot without events, an item counts as caught only in
## the live pip's hands, and a pad only under the live pip's feet (the world's
## pad_spots()). A tick buzzes once at most, with its strongest feel, and not
## at all when one of its cues buzzes already (services/sound_cues.gd
## haptic_ms). The soundscape buzzes only a phone, only with Settings'
## Haptics on (Soundscape.haptic).
##
## Presentation only: it reads snapshots and the world's pads, never the engines.

## Named feels: how long (ms) and how strong (0 to 1) the buzz is; a tick
## with several feels plays the one of the highest rank.
const FEELS := {
	# Stepping off a pad: the lightest.
	"release": {"ms": 8, "amplitude": 0.15, "rank": 0},
	# One step of a crank or a wheel.
	"step": {"ms": 8, "amplitude": 0.22, "rank": 1},
	# A light tick: a selector set, an item taken, put down, given or thrown.
	"tap": {"ms": 10, "amplitude": 0.25, "rank": 1},
	# A pad pressed down, a lever pulled, an item caught.
	"press": {"ms": 16, "amplitude": 0.35, "rank": 2},
	# A bell rung, a gate or a bridge opened.
	"thud": {"ms": 24, "amplitude": 0.45, "rank": 3},
}
const DEFAULT_FEEL := "tap"
## Kind -> feel. A styled kind is "<slot>:<style>" (content/dressing/
## prop_styles.gd): a winch is a crank, a valve or a rope wheel a wheel.
const KINDS := {
	"pad": "press", "pad_release": "release", "gate": "thud",
	"lever": "press", "lever:winch": "step",
	"selector": "tap", "selector:valve": "step", "selector:rope_wheel": "step",
	"bell": "thud", "loft_opened": "thud", "court_activated": "thud", "beacon_lit": "thud", "tower_anchored": "thud",
	"item_caught": "press", "handoff_claim": "press", "lens_fitted": "press",
	"mirror_rotated": "step",
}
## The simulation events (their part before any ":") that are the live pip's
## own presses, each its own kind; "lever" and "selector" add their style.
const ACTIONS := ["lever", "selector", "bell", "loft_opened", "court_activated", "beacon_lit", "tower_anchored",
	"item_taken", "item_put", "item_given", "item_thrown", "item_caught", "seed_taken", "seed_thrown",
	"handoff_offer", "handoff_claim", "lens_taken", "lens_offered", "lens_fitted", "mirror_rotated", "route_selected"]
## Events of a gate or a bridge opening.
const OPENINGS := ["bridge_opened", "bridge_open"]
## A pip counts as on a pad this far past its radius (m), at most this far
## above or below its floor (m).
const PAD_SLACK := 0.02
const PAD_HEIGHT := 0.3
const SoundCues = preload("res://services/sound_cues.gd")
const PadKit = preload("res://presentation/kit/pieces/pad.gd")

## The pads the live pip stood on held, and the levers, at the last tick.
var _on_pads: Dictionary = {}
var _levers: Dictionary = {}

## The feel of a kind: its own, else its slot's, else DEFAULT_FEEL.
static func feel(kind: String) -> String:
	return str(KINDS.get(kind, KINDS.get(kind.get_slice(":", 0), DEFAULT_FEEL)))

## The buzz of the strongest of `kinds`' feels ({} for none).
static func strongest(kinds: Array) -> Dictionary:
	var best: Dictionary = {}
	for kind: String in kinds:
		var found: Dictionary = FEELS[feel(kind)]
		if best.is_empty() or int(found.rank) > int(best.rank): best = found
	return best

## A new turn: nothing is remembered.
func reset() -> void:
	_on_pads = {}
	_levers = {}

## The buzz the live pip's own actions in `state` give ({} for none), with
## `world` showing it (pads, piece styles) and `sounds` its cues; remembered
## either way, so a tick that may not buzz still moves the memory on.
func tick(state: Dictionary, world: Object, sounds: Dictionary, live: bool) -> Dictionary:
	var kinds := kinds_of(state, world)
	if not live or kinds.is_empty() or _cue_buzzes(sounds): return {}
	return strongest(kinds)

## The kinds of the live pip's own actions in `state` since the last tick.
func kinds_of(state: Dictionary, world: Object) -> Array[String]:
	var kinds: Array[String] = []
	var players: Variant = state.get("players")
	var me: Variant = players.get(str(state.get("active_slot", ""))) if players is Dictionary else null
	if not me is Dictionary or bool(me.get("ghost", false)): me = {}
	var on := _pads_under(me, world)
	for id: String in on:
		if not _on_pads.has(id): kinds.append("pad")
	for id: String in _on_pads:
		if not on.has(id): kinds.append("pad_release")
	_on_pads = on
	var pulled := _changed_levers(state)
	var opened := false
	for event: Variant in state.get("events", []):
		var text := str(event)
		var head := text.get_slice(":", 0)
		if head in OPENINGS: opened = true
		if head not in ACTIONS or (me as Dictionary).is_empty(): continue
		if head == "lever": kinds.append(_styled(world, "lever", pulled[0] if not pulled.is_empty() else ""))
		elif head == "selector": kinds.append(_styled(world, "selector", text.get_slice(":", 1)))
		elif head == "item_caught" and str(me.get("carrying", "")) != text.get_slice(":", 1): continue
		else: kinds.append(head)
	if opened and (kinds.any(func(kind: String) -> bool: return kind != "pad_release") or not on.is_empty()): kinds.append("gate")
	return kinds

## The held pads `me` stands on: {id: true}.
func _pads_under(me: Dictionary, world: Object) -> Dictionary:
	var on: Dictionary = {}
	if me.is_empty() or world == null or not world.has_method("pad_spots"): return on
	var at := Vector3(float(me.get("x", 0)), float(me.get("height", 0)), float(me.get("z", 0))) / 100.0
	for pad: Dictionary in world.pad_spots():
		var spot: Vector3 = pad.at
		if bool(pad.held) and PadKit.covers(spot, float(pad.radius), pad.get("half", Vector2.ZERO), at, PAD_SLACK, PAD_HEIGHT): on[str(pad.id)] = true
	return on

## Lever ids whose state changed since the last tick, in snapshot order.
func _changed_levers(state: Dictionary) -> Array:
	var now: Variant = state.get("levers")
	if not now is Dictionary: return []
	var changed: Array = []
	for id: Variant in now:
		if bool(now[id]) != bool(_levers.get(id, false)): changed.append(str(id))
	_levers = (now as Dictionary).duplicate()
	return changed

## "<slot>:<style>" for piece `id`'s style in `world`, else the slot.
static func _styled(world: Object, slot: String, id: String) -> String:
	if id.is_empty() or world == null or not world.has_method("piece_style"): return slot
	return "%s:%s" % [slot, world.piece_style(slot, id)]

## Whether a cue of the tick buzzes by itself (sound_cues.gd haptic_ms).
static func _cue_buzzes(sounds: Dictionary) -> bool:
	for cue: Variant in sounds.get("cues", []):
		if int(SoundCues.CUES.get(str(cue), {}).get("haptic_ms", 0)) > 0: return true
	return false
