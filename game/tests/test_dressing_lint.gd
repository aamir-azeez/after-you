extends SceneTree
## Scenery lint. Every prop in content/dressing, on every stage it shows on:
##  - stands off every walkable route, island, stair and drop whose walking
##    space it would share (flat decals excepted),
##  - stays clear of every pad, lever, switch, goal and start,
##  - never hides a spirit or a control from the chapter camera: a prop of
##    height h at base b hides ground at y0 behind it, swept along the view
##    direction (-3, -10)/13 per metre of height between b - y0 - spirit and
##    b + h - y0 (every chapter camera sits at offset (3, 13, 10)),
##  - and the built dressing has no collision or physics bodies.
const Registry = preload("res://services/chapter_registry.gd")
const Catalog = preload("res://content/dressing/catalog.gd")
const Props = preload("res://presentation/kit/props.gd")
const Primitives = preload("res://presentation/kit/primitives.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const LightCatalog = preload("res://core/lighthouse/stage_catalog.gd")
const LighthouseWorld = preload("res://presentation/lighthouse_world.gd")
const LIGHTHOUSE := "sleeping-lighthouse@1"
const SPIRIT := 1.0
## About a spirit's body radius beyond the rectangle its centre walks in.
const MARGIN := 0.12
const VIEW := Vector2(-3.0, -10.0) / 13.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	for key: String in Catalog.keys():
		_check(key == LIGHTHOUSE or key in Registry.keys(), "Dressing is filed under a registered chapter key: " + key)
		var data := Catalog.for_key(key)
		for stage: Variant in data.get("props", {}).keys():
			_check(stage == "*" or stage in _stage_ids(key), "Dressing stage exists in %s: %s" % [key, stage])
		for stage_id: String in _stage_ids(key):
			_lint(key, stage_id, _stage_view(key, stage_id), data)
	_check_built_worlds()
	print("DRESSING LINT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _stage_ids(key: String) -> Array:
	if key == LIGHTHOUSE: return LightCatalog.STAGE_IDS.duplicate()
	var result: Array = []
	for stage: Dictionary in Registry.definition(key).stages: result.append(str(stage.id))
	return result

func _stage_view(key: String, stage_id: String) -> Dictionary:
	if key == LIGHTHOUSE: return LightCatalog.definition(stage_id)
	return CooperativeCatalog.stage_definition(Registry.definition(key), stage_id)

func _rect(r: Array) -> Rect2:
	return Rect2(Vector2(float(r[0]), float(r[1])) / 100.0, Vector2(float(r[2] - r[0]), float(r[3] - r[1])) / 100.0)

func _heights(view: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for island: Dictionary in view.get("islands", []): result[str(island.id)] = float(island.get("height_cm", 0)) / 100.0
	return result

## Walking spaces: {rect, y, rise, name}. Stairs span their whole rise.
func _walkable(view: Dictionary) -> Array:
	var spaces: Array = []
	for island: Dictionary in view.get("islands", []):
		spaces.append({"rect": _rect(island.rect_cm), "y": float(island.get("height_cm", 0)) / 100.0, "rise": 0.0, "name": "island " + str(island.id)})
	for bridge: Dictionary in view.get("bridges", []):
		spaces.append({"rect": _rect(bridge.rect_cm), "y": float(bridge.get("height_cm", 0)) / 100.0, "rise": 0.0, "name": "route " + str(bridge.id)})
	for stair: Dictionary in view.get("stairs", []):
		var low := minf(float(stair.from_height_cm), float(stair.to_height_cm)) / 100.0
		spaces.append({"rect": _rect(stair.rect_cm), "y": low, "rise": absf(float(stair.to_height_cm - stair.from_height_cm)) / 100.0, "name": "stair " + str(stair.id)})
	return spaces

## Interactive places: pads, levers, switches, goals, starts, drops, optics.
func _controls(view: Dictionary, heights: Dictionary) -> Array:
	var found: Array = []
	_collect(view, heights, found, "")
	for drop: Dictionary in view.get("drops", []):
		found.append({"rect": _rect(drop.rect_cm), "y": float(heights.get(str(drop.get("surface_id", "")), 0.0)), "name": "drop " + str(drop.get("id", ""))})
	var starts: Dictionary = view.get("starts", {}) if view.get("starts") is Dictionary else {}
	for slot: String in starts:
		var start: Variant = starts[slot]
		var at: Array = start.position_cm if start is Dictionary else start
		found.append({"rect": Rect2(Vector2(float(at[0]), float(at[1])) / 100.0 - Vector2.ONE * 0.3, Vector2.ONE * 0.6), "y": float(heights.get(str(start.get("surface_id", "")), 0.0)) if start is Dictionary else 0.0, "name": "start " + slot})
	return found

func _collect(value: Variant, heights: Dictionary, found: Array, path: String) -> void:
	if value is Dictionary:
		if value.has("position_cm") and value.position_cm is Array and value.position_cm.size() == 2:
			var radius := float(value.get("radius_cm", 30)) / 100.0
			var at := Vector2(float(value.position_cm[0]), float(value.position_cm[1])) / 100.0
			found.append({"rect": Rect2(at - Vector2.ONE * radius, Vector2.ONE * radius * 2.0), "y": float(heights.get(str(value.get("surface_id", "")), 0.0)), "name": "%s %s" % [path, value.get("id", "")]})
		for child: Variant in value:
			if str(child) != "starts": _collect(value[child], heights, found, str(child))
	elif value is Array:
		for item: Variant in value: _collect(item, heights, found, path)

func _lint(key: String, stage_id: String, view: Dictionary, data: Dictionary) -> void:
	var heights := _heights(view)
	var spaces := _walkable(view)
	var controls := _controls(view, heights)
	for spec: Dictionary in Props.expand(Catalog.stage_props(data, stage_id)):
		var label := "%s %s %s at %s" % [key, stage_id, spec.get("kind", "?"), spec.get("at", spec.get("from", spec.get("rect", "")))]
		if not _check(_known(spec), "Dressing prop kind exists: " + label): continue
		var extent := Props.extent(spec)
		var surface := str(spec.get("surface", ""))
		_check(surface.is_empty() or heights.has(surface), "Dressing surface exists on this stage: %s (%s)" % [label, surface])
		var base := float(heights.get(surface, 0.0)) + float(extent.base)
		var top := base + float(extent.height)
		var footprint: Rect2 = extent.rect
		var inner := footprint.grow(-0.01)
		if not bool(extent.flat):
			for space: Dictionary in spaces:
				if bool(extent.get("wall", false)) and _on_back_wall(footprint, base, space): continue
				var shares := top > float(space.y) + 0.02 and base < float(space.y) + float(space.rise) + SPIRIT
				_check(not (shares and inner.intersects(space.rect)), "Prop stands on a walkable %s: %s" % [space.name, label])
		for item: Dictionary in controls:
			_check(not (top > float(item.y) and base < float(item.y) + SPIRIT and inner.intersects(item.rect.grow(0.1))), "Prop covers %s: %s" % [item.name, label])
		if top - float(heights.get(surface, 0.0)) <= Props.LOW or bool(extent.flat): continue
		for target: Dictionary in spaces + controls:
			# A wall-hung prop sits above head height against its own room's back wall.
			if bool(extent.get("wall", false)) and _on_back_wall(footprint, base, target): continue
			if _hides(footprint, base, top, target):
				_check(false, "Prop hides %s from the camera: %s" % [target.name, label])
				break

func _on_back_wall(footprint: Rect2, base: float, target: Dictionary) -> bool:
	var rect: Rect2 = target.rect
	return base >= float(target.y) + 1.1 and footprint.position.x >= rect.position.x - 0.05 and footprint.end.x <= rect.end.x + 0.05 and footprint.position.y <= rect.position.y + 0.25

## The prop's view shadow at the target's height overlaps the target.
func _hides(footprint: Rect2, base: float, top: float, target: Dictionary) -> bool:
	var y0 := float(target.y)
	var near := maxf(0.0, base - y0 - SPIRIT - float(target.get("rise", 0.0)))
	var far := top - y0
	if far <= 0.0: return false
	var goal: Rect2 = target.rect.grow(MARGIN)
	var step := near
	while step <= far + 0.001:
		if Rect2(footprint.position + VIEW * step, footprint.size).grow(-0.01).intersects(goal): return true
		step += 0.05
	return false

func _known(spec: Dictionary) -> bool:
	var holder := Node3D.new()
	var prop := Props.build(spec, holder, 0.0, true)
	var known := prop != null
	holder.free()
	return known

## Builds each dressed world and proves the scenery has no physics.
func _check_built_worlds() -> void:
	for key: String in Catalog.keys():
		var world: Node3D = LighthouseWorld.new() if key == LIGHTHOUSE else Registry.world_script(key).new()
		root.add_child(world)
		world.set_process(false)
		for stage_id: String in _stage_ids(key):
			if key == LIGHTHOUSE: world.load_level(LightCatalog.definition(stage_id))
			else:
				if world.chapter_definition.is_empty(): world.load_level(Registry.definition(key))
				for stage: Dictionary in Registry.definition(key).stages:
					if stage.id == stage_id: world.show_stage(stage)
			var dressed: Array = world.terrain.find_children("*", "Node3D", true, false).filter(func(node: Node) -> bool: return node.has_meta("dressing_kind"))
			var expected := Props.expand(Catalog.stage_props(Catalog.for_key(key), stage_id)).size()
			_check(dressed.size() == expected, "Every dressing prop is built: %s %s (%d of %d)" % [key, stage_id, dressed.size(), expected])
			var bodies: Array = world.terrain.find_children("*", "CollisionObject3D", true, false) + world.terrain.find_children("*", "CollisionShape3D", true, false)
			_check(bodies.is_empty(), "Dressing adds no collision: %s %s" % [key, stage_id])
			# Fading every floor and restoring it must never reach a shared material.
			if world.has_method("_set_cutaway"):
				var before := _shared_looks()
				world._set_cutaway(world.terrain, true)
				world._set_cutaway(world.terrain, false)
				_check(_shared_looks() == before, "Cutaway leaves shared scenery materials unchanged: %s %s" % [key, stage_id])
		world.free()

func _shared_looks() -> Array:
	var looks: Array = []
	for mat: StandardMaterial3D in Primitives.shared_materials():
		looks.append([mat.albedo_color, mat.transparency, mat.emission_enabled, mat.emission, mat.emission_energy_multiplier])
	return looks
