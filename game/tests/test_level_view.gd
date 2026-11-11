extends SceneTree
## The level checker's view half: every stage of every chapter laid out as
## floors and crossings, built as its world on an 800x360 view (a phone held
## sideways), with a pip standing at each control, lever, pad and goal in turn
## (tests/level_tools/stage_shots.gd), the camera framed by the world's own
## follow rule and the bubbles placed by its own placement. A failure names
## the chapter, the stage, the spot and what went wrong:
##  - the spot itself lies outside the view (or within EDGE_PX of its edge);
##  - a selector's own bubble is cut off by the view's edge while its pip
##    stands at it;
##  - two bubbles on the view overlap.
## KNOWN lists what fails on purpose, by the start of its message, with why;
## an entry that stops failing fails the suite. The definitions-only half is
## tests/test_level_checker.gd.
const Registry = preload("res://services/chapter_registry.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const VIEW := Vector2i(800, 360)
## A spot this close to the view's edge (px) counts as outside it.
const EDGE_PX := 16.0
## Bubbles overlapping by less than this (px squared) only touch.
const OVERLAP_PX2 := 16.0
## Known failures, matched by the start of the failure id: {prefix: why}.
const KNOWN := {}
var checks := 0
var failures := 0
var _found: Dictionary = {}
var _spots := 0
var _bubbles_seen := 0
## Spots off the view while the pip stands at its start: proof the framing
## check can fail at all.
var _off_view := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = VIEW
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(viewport)
	for key: String in _keys():
		var started := Time.get_ticks_msec()
		await _chapter(viewport, key)
		print("LEVEL VIEW: %s in %d ms" % [key, Time.get_ticks_msec() - started])
	_check(_spots > 80 and _bubbles_seen > 100, "The view checks stand a pip at every spot (%d), with bubbles in view (%d)" % [_spots, _bubbles_seen])
	_check(_off_view > 0, "From the starts, some spots lie off the view, so the framing check can fail (%d)" % _off_view)
	for prefix: String in KNOWN:
		_check(_found.has(prefix), "Known failure still fails, or comes off the list: %s (%s)" % [prefix, KNOWN[prefix]])
	print("LEVEL VIEW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The chapters this suite walks; a split suite narrows it.
func _keys() -> Array[String]:
	return Registry.keys().filter(func(key: String) -> bool: return Stages.floor_chapter(key))

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

func _expect(ok: bool, id: String, message: String) -> void:
	if not ok:
		for prefix: String in KNOWN:
			if id.begins_with(prefix):
				_found[prefix] = true
				print("KNOWN: %s (%s)" % [message, KNOWN[prefix]])
				ok = true
				break
	_check(ok, message)

func _chapter(viewport: SubViewport, key: String) -> void:
	var level := Registry.definition(key)
	var journey := Registry.is_journey(key)
	var world: Node3D = Registry.world_script(key).new()
	viewport.add_child(world)
	world.set_process(false)
	world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)
	await world.load_level(level)
	for item: Dictionary in Stages.stages(key, level):
		var view: Dictionary = item.view
		var where := "%s %s" % [key, view.stage_id]
		if item.checkpoint.is_empty(): continue
		await world.show_stage(item.stage)
		world.present_history(item.checkpoint)
		var base := Shots.opening(key, level, str(view.stage_id), item.checkpoint)
		_check(not base.is_empty(), "%s: the engine opens the stage" % where)
		if base.is_empty(): continue
		world.present(base, true)
		for spot: Dictionary in Shots.spots(view):
			if not _inside(world, spot.entity): _off_view += 1
		for spot: Dictionary in Shots.spots(view):
			world.present(Shots.beside(base, view, journey, spot.entity, spot.slot), true)
			_look(world, where, spot)
			_spots += 1
	world.queue_free()
	await process_frame

## Where the entity's floor point lands on the view (px).
static func _shown(world: Node3D, entity: Dictionary) -> Vector2:
	return world.camera.unproject_position(world.terrain.to_global(world._at(entity)))

static func _inside(world: Node3D, entity: Dictionary) -> bool:
	return Rect2(Vector2.ZERO, Vector2(VIEW)).grow(-EDGE_PX).has_point(_shown(world, entity))

func _look(world: Node3D, where: String, spot: Dictionary) -> void:
	var camera: Camera3D = world.camera
	var screen := Rect2(Vector2.ZERO, Vector2(VIEW))
	var label := "%s %s" % [spot.kind, spot.id]
	_expect(_inside(world, spot.entity), "%s %s framing" % [where, label], "%s: with its pip at the %s, it lies outside the view at %s px" % [where, label, _shown(world, spot.entity).round()])
	if not "_bubbles" in world: return
	var boxes: Array = []
	for bubble: Node in world._bubbles:
		if not is_instance_valid(bubble) or not (bubble as Node3D).is_visible_in_tree(): continue
		var box: Rect2 = (bubble as LabelBubble).screen_rect(camera)
		if box.has_area() and box.intersects(screen): boxes.append([bubble, box])
	_bubbles_seen += boxes.size()
	if spot.kind == "selector" and world._journey_switches.has(spot.id):
		var own: LabelBubble = world._journey_switches[spot.id].bubble
		var box := own.screen_rect(camera)
		_expect(screen.encloses(box), "%s %s bubble cut" % [where, label], "%s: with its pip at the %s, its bubble is cut off by the view's edge at %s" % [where, label, _px(box)])
	for a in range(boxes.size()):
		for b in range(a + 1, boxes.size()):
			var meet: Rect2 = (boxes[a][1] as Rect2).intersection(boxes[b][1])
			_expect(meet.get_area() < OVERLAP_PX2, "%s %s bubbles overlap" % [where, label], "%s: with a pip at the %s, the bubbles of %s and %s overlap (%s)" % [where, label, _name(world, boxes[a][0]), _name(world, boxes[b][0]), _px(meet)])

## A bubble's name for a message: its selector, else what it says.
static func _name(world: Node3D, bubble: LabelBubble) -> String:
	for id: String in world._journey_switches:
		if world._journey_switches[id].bubble == bubble: return "the %s selector" % id
	return "\"%s\"" % bubble.labels[0].text if not bubble.labels.is_empty() else "a bubble"

static func _px(box: Rect2) -> String:
	return "(%d, %d) to (%d, %d) px" % [roundi(box.position.x), roundi(box.position.y), roundi(box.end.x), roundi(box.end.y)]
