extends RefCounted
## Scenery as data. One dressing file per chapter key, kept apart from the
## hashed chapter definitions: nothing here reaches a simulation, a recording
## or a checkpoint. A chapter without a file keeps its world exactly as built.
##
## A dressing file declares `const DATA := {...}` with optional fields:
##   "look":   kit/look.gd preset name
##   "ground": {island_id or "*": kit/surfaces.gd style}
##   "stairs": "timber" for wooden steps, "bridges": "timber" for plank decks
##   "obstacles": "flowerbed" for timber flower beds on obstacle rectangles
##   "cables": "floor" to draw gate links only along a shared floor
##   "props":  {"*" or stage_id: [kit/props.gd specs]}
##   "fireflies": count of drifting lights near the props (dusk looks)
## tests/test_dressing_lint.gd checks every prop against every route, pad,
## lever, goal, start and drop, including the camera's view of them.

const Index = preload("res://content/chapters/index.gd")
## Dressing for keys that are not registered chapters. A registered chapter
## names its file in its descriptor ("dressing").
const OTHER_FILES := {
	"sleeping-lighthouse@1": preload("res://content/dressing/sleeping_lighthouse.gd"),
}
## Key -> dressing script, loaded once with this file, then only read.
static var FILES: Dictionary = _files()

static func _files() -> Dictionary:
	var result: Dictionary = OTHER_FILES.duplicate()
	for key: String in Index.keys():
		var path: String = Index.data(key).dressing
		if not path.is_empty(): result[key] = load(path)
	result.make_read_only()
	return result

static func for_key(key: String) -> Dictionary:
	var file: Script = FILES.get(key)
	return file.DATA if file != null else {}

static func keys() -> Array:
	return FILES.keys()

## Every prop spec shown on one stage, rows expanded by the caller.
static func stage_props(data: Dictionary, stage_id: String) -> Array:
	var props: Dictionary = data.get("props", {})
	return props.get("*", []) + props.get(stage_id, [])
