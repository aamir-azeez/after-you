extends RefCounted
## The keepsakes in Explore: what a step of the pip sets off and the stays it
## walks in and out of. A part of Home's keepsake layer
## (presentation/home_keepsake_layer.gd), which owns the props, the plays and
## the ground, and hands each step here. Everything runs per step, never per
## frame: a pip standing still asks nothing.
##
## A builder says how it is set off (keepsake_builder.gd): a trigger area plays
## it once as the pip walks in (again only after it has walked out), a trigger
## line plays it when a step crosses it, and a stay runs arrive(), follow() and
## depart() as the pip walks in, along and out.

var _layer: Node3D
## The pip that walks, the triggers it stands in, and the stay it is in
## ({"id", "visit"}).
var _walker: Node3D
## Where the pip's last step ended.
var _last := Vector3.ZERO
var _in_trigger: Dictionary = {}
var _stay: Dictionary = {}

func _init(layer: Node3D) -> void:
	_layer = layer

## A step from `from` to `to`: sets off what it walked into or through (never
## while another keepsake plays: it waits for the pip to walk in again; a tap
## or the Explore action still can), then walks the stays.
func walked(from: Vector3, to: Vector3, walker: Node3D) -> void:
	_walker = walker
	_last = to
	if _layer.riding(): return
	var a2 := Vector2(to.x, to.z)
	var b2 := Vector2(from.x, from.z)
	for id: String in _layer._shown:
		var frame: Dictionary = _layer._frames[id]
		var reach: Array = frame.reach
		if (reach[0] as Vector2).distance_to(a2) > float(reach[1]) and (reach[0] as Vector2).distance_to(b2) > float(reach[1]):
			_in_trigger.erase(id)
			continue
		var trigger: Dictionary = frame.trigger
		if trigger.is_empty() or not _layer.playable(id): continue
		var inverse: Transform3D = frame.inverse
		var start := inverse * Vector3(from.x, 0, from.z)
		var end := inverse * Vector3(to.x, 0, to.z)
		var fire := false
		if trigger.has("line"):
			fire = Geometry2D.segment_intersects_segment(Vector2(start.x, start.z), Vector2(end.x, end.z), trigger.line[0], trigger.line[1]) != null
		elif trigger.has("area"):
			var inside: bool = (trigger.area as Rect2).has_point(Vector2(end.x, end.z))
			fire = inside and not _in_trigger.get(id, false)
			_in_trigger[id] = inside
		if fire and not _layer.playing(): _layer.play(id, walker)
	update_stay(to)

## Walks the pip in, along or out of a stay at `at`. `quiet`: no sound (the
## same stay found again in a rebuilt set).
func update_stay(at: Vector3, quiet: bool = false) -> void:
	var inside := ""
	var local := Vector2.ZERO
	for id: String in _layer._shown:
		var stay: Rect2 = _layer._frames[id].stay
		if not stay.has_area() or not _layer.playable(id): continue
		var point: Vector3 = _layer._frames[id].inverse * Vector3(at.x, 0, at.z)
		if stay.has_point(Vector2(point.x, point.z)):
			inside = id
			local = Vector2(point.x, point.z)
			break
	if staying() != inside: leave_stay()
	if inside.is_empty(): return
	var prop: Dictionary = _layer.current_props()[inside]
	var builder: RefCounted = _layer._builders[inside]
	var state: Dictionary = prop.state.duplicate()
	state.sounds = _layer._entry(inside).keepsake.get("sounds", {})
	if _stay.is_empty():
		var holder: Node3D = _layer.prop_node(inside)
		if holder == null: return
		var visit := Node3D.new()
		visit.name = "Visit"
		holder.add_child(visit)
		_stay = {"id": inside, "visit": visit}
		_sound(builder.arrive(visit, prop.parts, state), quiet)
	_sound(builder.follow(_stay.visit, prop.parts, state, local), quiet)

func _sound(name: String, quiet: bool) -> void:
	if not quiet and not name.is_empty() and _layer.cue.is_valid(): _layer.cue.call(name)

## The pip left its stay (or Explore ended): the keepsake is put back as it was.
func leave_stay() -> void:
	if _stay.is_empty(): return
	var id: String = _stay.id
	var prop: Dictionary = _layer.current_props().get(id, {})
	if not prop.is_empty(): _layer._builders[id].depart(prop.parts, prop.state)
	var visit: Variant = _stay.visit
	if is_instance_valid(visit):
		if (visit as Node).get_parent() != null: (visit as Node).get_parent().remove_child(visit)
		(visit as Node).queue_free()
	_stay = {}

## The set changed under the pip: its old stay went with the old set, and the
## pip walks on inside the new one without a sound.
func set_swapped() -> void:
	var was := staying()
	_stay = {}
	if not was.is_empty() and is_instance_valid(_walker): update_stay(_last, true)

## The stay the pip is in, or "".
func staying() -> String:
	return str(_stay.get("id", ""))

## How high the pip stands at `at`: a stay's floor (a raised house), else 0.
func ground_height(at: Vector3) -> float:
	if _stay.is_empty(): return 0.0
	var id: String = _stay.id
	var point: Vector3 = _layer._frames[id].inverse * Vector3(at.x, 0, at.z)
	return float(_layer._builders[id].floor(_layer.current_props()[id].state, Vector2(point.x, point.z)))

## Explore ended: any stay is left and nothing is half set off.
func end() -> void:
	leave_stay()
	_in_trigger.clear()
	_walker = null
