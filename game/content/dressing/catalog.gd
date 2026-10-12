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

const FILES := {
	"sleeping-lighthouse@1": preload("res://content/dressing/sleeping_lighthouse.gd"),
	"high-and-low@1": preload("res://content/dressing/high_and_low.gd"),
	"rolling-home@1": preload("res://content/dressing/rolling_home.gd"),
	"a-house-for-two@1": preload("res://content/dressing/house.gd"),
	"conservatory@1": preload("res://content/dressing/conservatory.gd"),
	"long-way-home@1": preload("res://content/dressing/long_way_home.gd"),
	"long-way-home@2": preload("res://content/dressing/long_way_home_v2.gd"),
}

static func for_key(key: String) -> Dictionary:
	var file: Script = FILES.get(key)
	return file.DATA if file != null else {}

static func keys() -> Array:
	return FILES.keys()

## Every prop spec shown on one stage, rows expanded by the caller.
static func stage_props(data: Dictionary, stage_id: String) -> Array:
	var props: Dictionary = data.get("props", {})
	return props.get("*", []) + props.get(stage_id, [])
