extends "res://tests/chapter_witness.gd"
## turn-of-the-tide@2 played through with real inputs: the LOW history won
## through the sea lock, @1's main chain, by @1's own routes
## (turn_of_the_tide_witness.gd). The settled source means each partner term
## those routes wait for ("u" steps) already holds, so no tick is spent there.
const KEY := "turn-of-the-tide@2"
const Tide = preload("res://tests/turn_of_the_tide_witness.gd")

func chapter() -> Dictionary:
	var level := Registry.definition(KEY)
	var checkpoint := Registry.initial_checkpoint(KEY)
	var result := {"definition": level, "checkpoints": [checkpoint], "pairs": [], "error": ""}
	var routes := [[Tide.a_routes()["low"], Tide.b_routes()["low"]],
		[Tide.p1_home("low") + Tide.p1_way("low", "sea-lock"), Tide.p0_way("low", "sea-lock")]]
	for index in range(level.stages.size()):
		var pair := Tide.pair(level, str(level.stages[index].id), checkpoint, routes[index][0], routes[index][1], true)
		if not pair.error.is_empty():
			result.error = "%s: %s" % [level.stages[index].id, pair.error]
			return result
		result.pairs.append({"a": pair.a, "b": pair.b})
		checkpoint = pair.checkpoint
		result.checkpoints.append(checkpoint)
	return result
