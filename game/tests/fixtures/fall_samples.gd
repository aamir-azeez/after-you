extends RefCounted
## Sample falling recipes (presentation/kit/fall_effect.gd) for skins nobody
## wears yet: what test_fall_effect.gd checks besides each shape alone, and
## what the private shapes capture draws. Not in the catalog; a skin that
## takes one copies it into its own art script.
const SAMPLES := {
	"autumn_leaves": {"id": "sample:autumn_leaves", "shape": &"leaf", "colors": [Color("e8893a"), Color("c9542f")], "spin": 0.9, "sway_size": Vector2(0.18, 0.26)},
	"snow": {"id": "sample:snow", "shape": &"snowflake", "size": Vector3(0.05, 0.004, 0.05), "colors": [Color("ffffff"), Color("d6ecff")], "slots": Vector2i(4, 5), "fall_time": Vector2(5.0, 6.0), "spin": 0.25, "glow": 0.7},
	"rain": {"id": "sample:rain", "shape": &"raindrop", "size": Vector3(0.05, 0.008, 0.05), "colors": [Color("9fd3f5"), Color("6fb4e8")], "count": 12, "slots": Vector2i(8, 9), "fall_time": Vector2(1.6, 2.2), "sway_size": Vector2(0.02, 0.05), "sways": Vector2(0.5, 1.0), "spin": 0.0, "lean": 1.5, "rock": Vector2(0.0, 0.08), "tip": Vector2(0.0, 0.05), "glow": 0.5},
	"stars": {"id": "sample:stars", "shape": &"star", "size": Vector3(0.05, 0.008, 0.05), "colors": [Color("ffe27a"), Color("ffc94a")], "spin": 0.3, "glow": 0.8},
	"dandelion": {"id": "sample:dandelion", "shape": &"seed_fluff", "size": Vector3(0.055, 0.004, 0.055), "colors": [Color("fbfbf4"), Color("ece9d8")], "slots": Vector2i(4, 5), "fall_time": Vector2(5.2, 6.0), "sways": Vector2(0.5, 1.0), "spin": 0.15, "lean": 1.4, "rock": Vector2(0.05, 0.2), "glow": 0.6},
}

