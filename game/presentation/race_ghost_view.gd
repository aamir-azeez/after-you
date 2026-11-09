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
const Primitives = preload("res://presentation/kit/primitives.gd")
const SessionRelease = preload("res://presentation/kit/session_release.gd")
const GHOST_FACE = preload("res://presentation/spirit_face_ghost.gdshader")
## The pip's strength (board 4A: half), its name's, and how much paler it is than a live pip.
const VEIL := 0.5
## A part's meta naming the instance uniform its own shader fades it by.
const VEIL_UNIFORM := &"veil_uniform"
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
var _tick := 0
var _color := FIRST_PIP
var _reduced := false
var _timer: Control
## See-through copies of the kit's shared materials (Primitives SHARED_META), made
## once each and let go at shutdown (SessionRelease); any other material is
## copied for its ghost alone and goes with it.
static var _veils: Dictionary = {}

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
	_color = color.lerp(Color.WHITE, PALER)
	spirit = SpiritVisual.new(_color)
	spirit.name = "RaceGhost"
	spirit.wear(track.get("look", {}))
	(beside as Node3D).get_parent().add_child(spirit)
	_veil(spirit, _color)
	name_badge = Badges.make(spirit)
	name_badge.name = "RaceGhostName"
	var shown := str(track.get("name", ""))
	name_badge.text = PlayerCopy.DUELS_GHOST_DEVELOPERS if track.get("developer", false) else shown if not shown.is_empty() else PlayerCopy.RACE_GHOST_RECORDED
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

## The live turn reached `tick`: the ghost goes where its run stood then. At
## once when `immediate`, or when the turn jumped ahead (a memory wait skipped
## steps the turn without drawing it), so the ghost never slides across.
func at_tick(tick: int, immediate: bool = false) -> void:
	if not is_instance_valid(spirit): return
	_target = Track.point(_track, tick) / 100.0
	var jumped := absi(tick - _tick) > 1
	_tick = tick
	if immediate or jumped:
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

## Half strength on every part, its outfit too: the face draws with its
## see-through variant (spirit_face_ghost.gdshader, so its eyes still move) and
## every other part with a see-through copy of its material. A part whose own
## shader places it names the instance uniform that fades it (meta
## VEIL_UNIFORM: the Orchard skin's falling petals) and keeps its shader at
## VEIL strength. A part a body cosmetic draws with its own shader (the Tide
## torso) shows as the plain body, and the face loses that cosmetic's pattern: the ghost shows the outfit's
## shape, never a second solid pip. Its ground shadow and ring would read as
## solid, so they go.
static func _veil(node: Node, body: Color) -> void:
	var face: Variant = node.get("face_art")
	var face_material: Material = face.material if face != null else null
	if face != null: face.set_shader(GHOST_FACE, {"veil": VEIL})
	for part: Node in node.find_children("*", "MeshInstance3D", true, false):
		var mesh_part := part as MeshInstance3D
		mesh_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material: Material = mesh_part.material_override if mesh_part.material_override != null else mesh_part.get_active_material(0)
		if material == face_material: continue
		if mesh_part.has_meta(VEIL_UNIFORM):
			mesh_part.set_instance_shader_parameter(mesh_part.get_meta(VEIL_UNIFORM), VEIL)
			continue
		if material is ShaderMaterial: material = Primitives.shared_material(body, 0.9)
		if material is BaseMaterial3D: mesh_part.material_override = _veiled(material)
	var shadow: Variant = node.get("ground_shadow")
	if shadow is Node3D: (shadow as Node3D).visible = false
	var ring: Variant = node.get("ground_ring")
	if ring is Node3D: (ring as Node3D).visible = false

static func _veiled(material: BaseMaterial3D) -> BaseMaterial3D:
	var shared := material.has_meta(Primitives.SHARED_META)
	if shared and _veils.has(material): return _veils[material]
	var veiled: BaseMaterial3D = material.duplicate()
	if veiled.has_meta(Primitives.SHARED_META): veiled.remove_meta(Primitives.SHARED_META)
	# Plain alpha: a depth pre-pass draws nothing below full strength, so it would only add a pass.
	veiled.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veiled.albedo_color.a = material.albedo_color.a * VEIL
	if shared:
		if _veils.is_empty(): SessionRelease.on_exit(Callable(load("res://presentation/race_ghost_view.gd"), "release_cached"))
		_veils[material] = veiled
	return veiled

## Lets go of the see-through copies (SessionRelease calls this).
static func release_cached() -> void:
	_veils.clear()
