extends "res://tests/test_level_view.gd"
## The level view of Turn of the Tide @1 and @2 (the Tide's world);
## test_level_view_tide_3 walks @3. See test_level_view.gd.
const TIDE_WORLD := "res://presentation/tide_world.gd"

func _runs(key: String) -> bool:
	return Registry.world_script(key).resource_path == TIDE_WORLD and key not in LATER

## The Tide versions test_level_view_tide_3 walks instead, so each suite
## stays well inside CI's 120 s limit.
const LATER := ["turn-of-the-tide@3"]

## The KNOWN entries that are @3's, answered by test_level_view_tide_3.
const LATER_KNOWN := ["turn-of-the-tide bar-catwalk", "turn-of-the-tide boom-post", "turn-of-the-tide gate-catwalk", "turn-of-the-tide gate-post", "turn-of-the-tide punt-post"]

func _answers(prefix: String) -> bool:
	return super(prefix) and prefix not in LATER_KNOWN

func _runs_shared() -> bool:
	return false

func _least() -> Dictionary:
	return {"spots": 40, "bubbles": 110, "cut": 1, "boats": 5, "stones": 0, "cover": 3000, "wall_spots": 1000, "walls": 10, "water_edges": 35000}
