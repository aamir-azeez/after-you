extends "res://tests/test_turn_of_the_tide_settled.gd"
## turn-of-the-tide@2's settled source in stage 2: every way after every
## history, the receiver never waiting on the way; see
## test_turn_of_the_tide_settled.gd.

func _title() -> String:
	return "TURN OF THE TIDE SETTLED WAYS"

func _parts(_v1: Dictionary, v2: Dictionary) -> void:
	_timed(_stage_two.bind(v2))

## The three histories, each from @1's own stage-1 routes. LOW, the main
## chain, proves its checkpoint and its sea-lock way in full; the rest replay
## to their recorded states.
func _stage_two(v2: Dictionary) -> void:
	var start := Catalog.initial_checkpoint(v2)
	for history: String in ["low", "half", "high"]:
		var first := Tide.pair(v2, Tide.SET, start, Tide.a_routes()[history], Tide.b_routes()[history], history == "low")
		if not _check(first.error.is_empty(), "Stage 1 %s plays under @2: %s" % [history, first.error]): continue
		for way: String in ["boom", "sea-lock", "punt"]:
			var proved: bool = history + "/" + way == "low/sea-lock"
			var pair := Tide.pair(v2, Tide.SLACK, first.checkpoint, Tide.p1_route(first.checkpoint, way), Tide.p0_way(history, way), proved)
			if not _check(pair.error.is_empty(), "Stage 2 %s/%s plays under @2: %s" % [history, way, pair.error]): continue
			_receiver_checks(v2, first.checkpoint, pair, "Stage 2 %s/%s" % [history, way])
