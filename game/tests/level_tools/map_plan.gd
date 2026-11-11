extends SceneTree
## Flat map plans: every stage of a chapter (or of a layout no chapter
## registers yet) drawn top down from its definition (map_plan_model.gd,
## map_plan_view.gd), one PNG per stage and a sheet of them all. A rendered
## run on an invisible TEMP copy only (render_kit.gd); never headless.
##   --key=<chapter key> | --catalog=res://<catalog>.gd [--method=definition] [--family=journey|cooperative]
##   --out=<folder> [--stages=<id,id>] [--no-world]
## With a registered chapter the world is built unseen once, only to read the
## pair tags it leaves out (pair_tags.skips()), so the letters match the
## game's; --no-world (or a bare layout) letters every wired control.
const Kit = preload("res://tests/level_tools/render_kit.gd")
const Stages = preload("res://tests/level_tools/level_stages.gd")
const Model = preload("res://tests/level_tools/map_plan_model.gd")
const MapView = preload("res://tests/level_tools/map_plan_view.gd")
const Sheet = preload("res://tests/level_tools/contact_sheet.gd")
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")
const Registry = preload("res://services/chapter_registry.gd")

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var options := Kit.args()
	var layout := Kit.layout(options)
	if layout.has("error") or not options.has("out"):
		print("NOTE %s" % layout.get("error", "Give --out=<folder>"))
		quit(2)
		return
	if DisplayServer.get_name() == "headless":
		print("NOTE the map plan needs a rendered run")
		quit(2)
		return
	var level: Dictionary = layout.level
	var out := str(options.out)
	var skips := await _skips(layout, options)
	var frames: Array = []
	for stage: Dictionary in Kit.chosen_stages(level, options):
		var index: int = level.stages.find(stage)
		var checkpoint := Stages.checkpoint_before(str(layout.key), level, index) if layout.registered else (Stages.starts_checkpoint(level) if index == 0 else {})
		var view := CooperativeCatalog.stage_definition(level, str(stage.id))
		var drawer: Control = MapView.new()
		drawer.plan = Model.build(level, view, checkpoint, layout.journey, skips.get(str(stage.id), []))
		var image: Image = await Kit.render(self, drawer, drawer.canvas_size())
		Kit.save(image, out, "%s-%s-map.png" % [layout.name, stage.id])
		frames.append({"image": image, "caption": "Stage %d: %s" % [index + 1, stage.get("title", stage.id)]})
	if frames.size() > 1:
		var sheet: Control = Sheet.new()
		sheet.title = "%s: flat map plans" % level.get("title", layout.name)
		sheet.note = "Every stage from its definition: floors by height, crossings, controls, pairs, goal and starts."
		sheet.groups = [{"heading": "Stages", "frames": frames}]
		sheet.columns = 1
		sheet.frame_width = minf(1600.0, float((frames[0].image as Image).get_width()))
		Kit.save(await Kit.render(self, sheet, sheet.canvas_size()), out, "%s-map-sheet.png" % layout.name)
	print("DONE")
	quit(0)

## {stage id: the pair tags its world leaves out}, from the world built unseen;
## {} for a bare layout or with --no-world.
func _skips(layout: Dictionary, options: Dictionary) -> Dictionary:
	if not layout.registered or options.has("no-world"): return {}
	var holder := SubViewport.new()
	holder.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(holder)
	var world: Node3D = Registry.world_script(str(layout.key)).new()
	holder.add_child(world)
	world.set_process(false)
	var result: Dictionary = {}
	if "pair_tags" in world:
		await world.load_level(layout.level)
		for stage: Dictionary in layout.level.stages:
			await world.show_stage(stage)
			result[str(stage.id)] = world.pair_tags.skips()
	holder.queue_free()
	await process_frame
	return result
