extends RefCounted
## What the level tools' rendered runs share: their arguments, the chapter or
## bare layout they draw, rendering a Control into an image and writing files
## only under the --out folder. A rendered run needs a real renderer (never
## --headless: every frame would come back empty) and is only ever started on
## an invisible TEMP copy of the game with its own user folder; see the private
## level tools how-to. Nothing here reads or writes user://.
const Registry = preload("res://services/chapter_registry.gd")

## The run's arguments after `--`: {"out": dir, "key": ..., ...}; a bare flag
## maps to "true".
static func args() -> Dictionary:
	var result: Dictionary = {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--"): continue
		var body := argument.trim_prefix("--")
		var cut := body.find("=")
		if cut < 0: result[body] = "true"
		else: result[body.substr(0, cut)] = body.substr(cut + 1)
	return result

## The layout to draw: a registered chapter (--key), or a bare definition no
## chapter registers yet (--catalog=res://path.gd [--method=definition]
## [--family=journey|cooperative]; else the family is read from the catalog's
## core/<family>/ folder). {} with an "error" when neither loads.
static func layout(options: Dictionary) -> Dictionary:
	var key := str(options.get("key", ""))
	if not key.is_empty():
		if key not in Registry.keys(): return {"error": "No chapter %s" % key}
		return {"key": key, "name": key.replace("@", "-v"), "level": Registry.definition(key), "journey": Registry.is_journey(key), "registered": true}
	var path := str(options.get("catalog", ""))
	if path.is_empty(): return {"error": "Give --key=<chapter key> or --catalog=res://<catalog>.gd"}
	var script: Variant = load(path)
	var method := str(options.get("method", "definition"))
	if not script is Script or not (script as Script).has_method(method): return {"error": "No static %s() in %s" % [method, path]}
	var level: Variant = (script as Script).call(method)
	if not level is Dictionary or (level as Dictionary).get("stages", []).is_empty(): return {"error": "%s.%s() gives no stages" % [path, method]}
	# The family's folder names it (the scaffold writes core/<family>/); --family overrides.
	var journey := str(options.get("family", "journey" if path.begins_with("res://core/journey/") else "cooperative")) == "journey"
	return {"key": "", "name": "%s-v%d" % [level.get("id", path.get_file().get_basename()), int(level.get("version", 1))], "level": level, "journey": journey, "registered": false}

## The stages asked for (--stages=a,b; all by default), as authored.
static func chosen_stages(level: Dictionary, options: Dictionary) -> Array:
	var wanted := str(options.get("stages", ""))
	if wanted.is_empty(): return level.stages
	var ids := wanted.split(",", false)
	return level.stages.filter(func(stage: Dictionary) -> bool: return str(stage.id) in ids)

## Draws `control` (sized `size`) on its own viewport and returns the image.
## Await it. The control is freed afterwards.
static func render(tree: SceneTree, control: Control, size: Vector2i) -> Image:
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)
	control.size = Vector2(size)
	viewport.add_child(control)
	for _frame in range(2): await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	return image

## Saves `image` as `name` under `folder`, which it creates. Returns the path.
static func save(image: Image, folder: String, name: String) -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	var path := folder.path_join(name)
	var error := image.save_png(path)
	print("SAVED %s" % path if error == OK else "NOTE could not save %s (%d)" % [path, error])
	return path
