extends SceneTree
## The one-command preview: every stage of a chapter rendered by its own world
## at 800x360 (a phone held sideways), in the moments a level is judged by:
## both pips' starting views, every pair tag faint, each selector at each of
## its values (the water follows its own selectors), each lever and pad with a
## pip near and then worked, and the goal; the label bubbles show as the
## world places them. One PNG per moment and a contact sheet per stage, under
## --out. A rendered run on an invisible TEMP copy only (render_kit.gd).
##   --key=<chapter key> | --catalog=res://<catalog>.gd [--method=definition] [--family=...]
##   --out=<folder> [--stages=<id,id>] [--only=start,faint,selector,lever,pad,goal]
## A bare layout (--catalog) is shown in the world of --world=<chapter key>
## (default the family's first chapter), so a new layout can be seen before its
## own world exists. The states come from tests/level_tools/stage_shots.gd,
## shared with the view checks.
const Kit = preload("res://tests/level_tools/render_kit.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Shots = preload("res://tests/level_tools/stage_shots.gd")
const Sheet = preload("res://tests/level_tools/contact_sheet.gd")
const Registry = preload("res://services/chapter_registry.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const SIZE := Vector2i(800, 360)
## Frames a moment settles for before it is taken (water, tags, bubbles).
const SETTLE_FRAMES := 8
## Pips this far away (cm) leave every tag faint.
const AWAY := 4000
const KINDS := ["start", "faint", "selector", "lever", "pad", "goal"]

var _only: Array = KINDS
var _count := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var options := Kit.args()
	var layout := Kit.layout(options)
	if layout.has("error") or not options.has("out"):
		print("NOTE %s" % layout.get("error", "Give --out=<folder>"))
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("NOTE the preview needs a rendered run")
		quit(2)
		return
	if options.has("only"): _only = Array(str(options.only).split(",", false))
	root.size = SIZE
	var key := str(layout.key) if layout.registered else str(options.get("world", _family_world(layout.journey)))
	var level: Dictionary = layout.level
	var world: Node3D = Registry.world_script(key).new()
	root.add_child(world)
	world.configure_camera_exploration(func() -> bool: return false, func(_point: Vector2) -> bool: return false)
	await world.load_level(level)
	for stage: Dictionary in Kit.chosen_stages(level, options):
		var index: int = level.stages.find(stage)
		var checkpoint := Stages.checkpoint_before(str(layout.key), level, index) if layout.registered else (Stages.starts_checkpoint(level) if index == 0 else {})
		if checkpoint.is_empty():
			print("NOTE %s: no checkpoint to open from (write the chapter's fixtures)" % stage.id)
			continue
		var frames := await _stage(world, key, level, stage, checkpoint, layout.journey, str(options.out).path_join(str(stage.id)))
		if frames.is_empty(): continue
		var sheet: Control = Sheet.new()
		sheet.title = "%s, stage %d: %s" % [level.get("title", layout.name), index + 1, stage.get("title", stage.id)]
		sheet.note = "Rendered by the game at 800x360. Gold and teal are the two pips; letters are the pair tags."
		sheet.groups = frames
		Kit.save(await Kit.render(self, sheet, sheet.canvas_size()), str(options.out), "%s-%s-sheet.png" % [layout.name, stage.id])
	world.queue_free()
	print("SHOTS %d" % _count)
	print("DONE")
	quit(0)

## The first chapter of the family, whose world shows a bare layout.
static func _family_world(journey: bool) -> String:
	for key: String in Registry.keys():
		if Stages.floor_chapter(key) and Registry.is_journey(key) == journey: return key
	return ""

## Every moment of one stage; returns the sheet's groups.
func _stage(world: Node3D, key: String, level: Dictionary, stage: Dictionary, checkpoint: Dictionary, journey: bool, folder: String) -> Array:
	var view := CooperativeCatalog.stage_definition(level, str(stage.id))
	await world.show_stage(stage)
	world.present_history(checkpoint)
	var base := Shots.opening(key, level, str(stage.id), checkpoint)
	if base.is_empty():
		print("NOTE %s: the engine has no such stage" % stage.id)
		return []
	world.present(base, true)
	var guard := 0
	while world.scenery_folding() and guard < 600:
		await process_frame
		guard += 1
	var groups: Array = []
	if "start" in _only:
		var shots: Array = []
		for slot: String in ["p0", "p1"]:
			var state := base.duplicate(true)
			state.active_slot = slot
			shots.append(await _take(world, state, folder, "start-%s" % _pip(slot), "%s pip's start%s" % [_pip(slot).capitalize(), ", plays first" if slot == str(stage.first_player_slot) else ""]))
		groups.append({"heading": "Starting views", "frames": shots})
	if "faint" in _only and "pair_tags" in world:
		groups.append({"heading": "Pair tags, no pip near", "frames": [await _faint(world, base, folder)]})
	var spots := Shots.spots(view)
	for kind: Array in [["selector", "Selectors at each value"], ["lever", "Levers: a pip near, then pulled"], ["pad", "Pads: a pip near, then held"], ["goal", "The goal"]]:
		if kind[0] not in _only: continue
		var shots: Array = []
		for spot: Dictionary in spots.filter(func(s: Dictionary) -> bool: return s.kind == kind[0]):
			var near := Shots.beside(base, view, journey, spot.entity, spot.slot)
			match str(kind[0]):
				"selector":
					for value: Variant in spot.entity.get("values", []):
						shots.append(await _take(world, Shots.worked(near, view, journey, spot, str(value)), folder, "%s-%s" % [spot.id, value], "%s at %s" % [spot.id, str(value).to_upper()]))
				"lever", "pad":
					shots.append(await _take(world, near, folder, "%s-near" % spot.id, "%s, a pip near" % spot.id))
					shots.append(await _take(world, Shots.worked(near, view, journey, spot), folder, "%s-%s" % [spot.id, "pulled" if kind[0] == "lever" else "held"], "%s, %s" % [spot.id, "pulled" if kind[0] == "lever" else "held"]))
				"goal":
					shots.append(await _take(world, near, folder, "goal-%s" % spot.id, "%s, its pip beside it" % spot.id))
		if not shots.is_empty(): groups.append({"heading": kind[1], "frames": shots})
	return groups

## One moment: presented, settled, saved. Returns its sheet frame.
func _take(world: Node3D, state: Dictionary, folder: String, slug: String, caption: String) -> Dictionary:
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.present(state, true)
	for _frame in range(SETTLE_FRAMES): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_count += 1
	Kit.save(image, folder, "%02d-%s.png" % [_count, slug])
	return {"image": image, "caption": caption}

## Every tag faint: both pips far away, the camera held over the tags' middle.
func _faint(world: Node3D, base: Dictionary, folder: String) -> Dictionary:
	var state := base.duplicate(true)
	for slot: String in state.players:
		state.players[slot].x = int(state.players[slot].x) + AWAY
		state.players[slot].z = int(state.players[slot].z) + AWAY
	world.process_mode = Node.PROCESS_MODE_INHERIT
	world.present(state, true)
	for _frame in range(SETTLE_FRAMES): await process_frame
	var tiles: Array = world.pair_tags.placed()
	if not tiles.is_empty():
		var centre := Vector3.ZERO
		for tile: Dictionary in tiles: centre += world.terrain.to_global(tile.at)
		centre /= float(tiles.size())
		world.process_mode = Node.PROCESS_MODE_DISABLED
		var camera: Camera3D = world.get_viewport().get_camera_3d()
		var forward := -camera.global_basis.z
		camera.global_position += centre - (camera.global_position + forward * ((centre.y - camera.global_position.y) / forward.y))
	for _frame in range(3): await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	world.process_mode = Node.PROCESS_MODE_INHERIT
	_count += 1
	Kit.save(image, folder, "%02d-faint.png" % _count)
	return {"image": image, "caption": "Every pair tag faint, held over their middle"}

static func _pip(slot: String) -> String:
	return "gold" if slot == "p0" else "teal"
