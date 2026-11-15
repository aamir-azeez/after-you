extends RefCounted
## Home's two islands: where the bridge, plate, landing ring, garden and both
## pips stand when Main builds the Home world (presentation/island_world.gd
## load_level), and the world's opening look (present): the gold pip holds the
## seed by the plate, the bridge rests down and the teal pip waits unseen.
## Coordinates are integer centimetres.
const LEVEL := {
	"id": "home", "index": 0,
	"starts": {"a": [-430, 100], "b": [-240, -120]},
	"plate": [-330, 0], "landing": [330, 0], "goal": [470, 120],
	"bounds": [-560, -290, 560, 290], "gap": [-100, 100],
	"bridge": {"z": 0, "width": 180},
}

static func opening() -> Dictionary:
	var a: Array = LEVEL.starts.a
	var b: Array = LEVEL.starts.b
	return {
		"role": "a", "complete": false,
		"players": {
			"a": {"x": a[0], "z": a[1], "height": 0, "holding": true, "ghost": false},
			"b": {"x": b[0], "z": b[1], "height": 0, "holding": false, "ghost": false},
		},
		"seed": {"x": a[0], "z": a[1], "height": 75, "status": "held_a"},
		"plate_active": false, "bridge_open": false, "gate_open": true, "lift_height": 0, "lift_ready": true,
	}
