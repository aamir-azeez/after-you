extends Node
## The race ghost on a live turn (race-picker board 4A, cue 5C): the raced
## run's player as a see-through pip at half strength, a little paler than the
## live pips, with a faint name above it, walking its own turn beside yours,
## and a small still pip on the turn timer where that turn finished. Only the
## pip shows: the raced run's lifts, seed and doors stay in its own world, so
## the ghost may walk through things or stand on a lift that is down for you.
## It never blocks, takes no input and makes no sound.
##
## relay_preview.gd makes one for a turn of a ghost race (services/race_ghost.gd
## gives the track) and frees it when the turn stops; nothing exists otherwise.
## The pip moves only when the live turn's tick moves (at_tick), and eases there
## each frame as the world's own pips do; no simulation runs here.
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Badges = preload("res://presentation/kit/badges.gd")
const PipAvatar = preload("res://presentation/kit/pip_avatar.gd")
const Track = preload("res://services/race_ghost_track.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
## The pip's strength (board 4A: half), its name's, and how much paler it is than a live pip.
const VEIL := 0.5
const NAME_ALPHA := 0.55
const PALER := 0.18
## The timer mark's pip.
const MARK_SIZE := Vector2(18, 24)
const MARK_ALPHA := 0.75
## The worlds' pips by slot (presentation/island_world.gd GOLD and TEAL).
const FIRST_PIP := Color("f4c38d")
const SECOND_PIP := Color("91d6c6")

var spirit: Node3D
var name_badge: Label3D
var _track: Dictionary = {}
var _target := Vector3.ZERO
var _reduced := false
var _timer: Control

## Shows the ghost of `track` (services/race_ghost.gd turn) in `world`, beside
## the pip of its slot, and its finish on `timer` (presentation/seed_timer_bar.gd)
## for a turn `duration_ticks` long.
func show_track(world: Node3D, track: Dictionary, timer: Control, duration_ticks: int, reduced_motion: bool) -> bool:
	var actors: Dictionary = world.get("actors") if world.get("actors") is Dictionary else {}
	var beside: Variant = actors.get(str(track.slot), actors.values()[0] if not actors.is_empty() else null)
	if not beside is Node3D or not (beside as Node3D).get_parent() is Node3D: return false
	_track = track
	_reduced = reduced_motion
	var color := SECOND_PIP if str(track.slot) == "p1" else FIRST_PIP
	spirit = SpiritVisual.new(color.lerp(Color.WHITE, PALER))
	spirit.name = "RaceGhost"
	spirit.wear(track.get("look", {}))
	(beside as Node3D).get_parent().add_child(spirit)
	_veil(spirit)
	name_badge = Badges.make(spirit)
	name_badge.name = "RaceGhostName"
	var shown := str(track.get("name", ""))
	name_badge.text = shown if not shown.is_empty() else PlayerCopy.RACE_GHOST_RECORDED
	name_badge.modulate.a = NAME_ALPHA
	name_badge.outline_modulate.a = NAME_ALPHA * 0.6
	at_tick(0, true)
	if is_instance_valid(timer) and timer.has_method("set_race_mark") and duration_ticks > 0:
		var mark := PipAvatar.new(true, color, MARK_SIZE, true)
		mark.name = "RaceGhostMark"
		mark.outfit = track.get("look", {})
		mark.modulate.a = MARK_ALPHA
		timer.set_race_mark(float(track.duration_ticks) / float(duration_ticks), mark)
		_timer = timer
	set_process(true)
	return true

## The live turn reached `tick`: the ghost goes where its run stood then (`immediate`: at once).
func at_tick(tick: int, immediate: bool = false) -> void:
	if not is_instance_valid(spirit): return
	_target = Track.point(_track, tick) / 100.0
	if immediate:
		spirit.position = _target
		spirit.reset_motion()

## Takes the ghost and its timer mark away.
func release() -> void:
	set_process(false)
	if is_instance_valid(_timer) and _timer.has_method("clear_race_mark"): _timer.clear_race_mark()
	_timer = null
	if is_instance_valid(spirit): spirit.queue_free()
	spirit = null
	name_badge = null

func _ready() -> void:
	set_process(is_instance_valid(spirit))

func _exit_tree() -> void:
	release()

func _process(delta: float) -> void:
	if not is_instance_valid(spirit): return
	var previous := spirit.position
	spirit.position = previous.lerp(_target, minf(delta * 14.0, 1.0))
	spirit.advance_motion(spirit.position - previous, delta, _reduced)

## Half strength on every part, its outfit too; its ground shadow would read as solid, so it goes.
static func _veil(node: Node) -> void:
	for part: Node in node.find_children("*", "GeometryInstance3D", true, false):
		(part as GeometryInstance3D).transparency = 1.0 - VEIL
		(part as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shadow: Variant = node.get("ground_shadow")
	if shadow is Node3D: (shadow as Node3D).visible = false
	var ring: Variant = node.get("ground_ring")
	if ring is Node3D: (ring as Node3D).visible = false
