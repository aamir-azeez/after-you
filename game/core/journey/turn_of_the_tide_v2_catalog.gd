extends RefCounted
## turn-of-the-tide@2: turn-of-the-tide@1's harbour on the tide rules (10,
## simulation.gd TIDE_RULES_VERSION). Nothing stays open because it once was:
## no crossing is kept on entry, a finished stage keeps no routes, a crossing
## whose gate stops holding shuts after `closing_ticks` while its water rises,
## and a spirit still on it then drowns.
##
## Set the Tide is @1's stage without its entry latches. Slack Water reads the
## first stage's crossings and steps through gates of its own, against the
## controls and levers the first stage left, so the second spirit still walks
## home over the crossing its branch opened. Every accepted stage-one end
## leaves it a way home: the far jetty needs only high water (the gangway may
## never have been pulled), and the lock's two gates stand open, since the lock
## wheel sits between them. Three gates change so the ways need no kept
## crossing: the mole steps read the outer sea, the sea lock lets out when the
## chamber stands at the sea's level, and the gate catwalk needs only an open
## sea.
const Earlier = preload("res://core/journey/turn_of_the_tide_catalog.gd")
## How long a closing crossing keeps its floor: 1.5 s, enough to walk off the
## longest one from its middle with a second to spare.
const CLOSING_TICKS := 45
const SLACK_HINT_B := "Fetch the pin, key or line at the mill. Let your friend reach home before you turn the tide, then take the tides in order and light the lantern."

static func definition() -> Dictionary:
	var level: Dictionary = Earlier.definition()
	level.version = 2
	level.simulation_version = 10
	level["closing_ticks"] = CLOSING_TICKS
	for stage: Dictionary in level.stages:
		stage.entry_latch_routes = []
	var slack: Dictionary = level.stages[1]
	slack.hint_b = SLACK_HINT_B
	var gates: Array = slack.gates
	_replace(gates, "mole-steps", {"all": [{"lever_id": "boom-pin"}, {"control_id": "basin", "value": "half"}]})
	_replace(gates, "sea-gate-out", {"all": [{"lever_id": "gate-bar"}, {"lever_id": "sea-bar"}, {"lever_id": "sea-key"}, _level_with_sea("chamber")]})
	_replace(gates, "gate-catwalk", {"any": [{"control_id": "basin", "value": "low"}, {"control_id": "basin", "value": "half"}, {"control_id": "basin", "value": "high"}]})
	_replace(gates, "lock-west", {})
	_replace(gates, "lock-east", {})
	# The first stage's crossings and steps, read against what it left.
	gates.append_array([
		{"route_id": "slipway", "when": {"all": [{"control_id": "tide", "value": "low"}, {"control_id": "winch", "value": "slip"}]}},
		{"route_id": "stones-3", "when": {"all": [{"control_id": "tide", "value": "half"}, {"lever_id": "sluice"}]}},
		{"route_id": "jetty-3", "when": {"control_id": "tide", "value": "high"}},
		{"route_id": "wheel-step", "when": {"all": [{"control_id": "tide", "value": "low"}, {"control_id": "winch", "value": "slip"}, {"lever_id": "sluice"}]}},
		{"route_id": "quay-step", "when": {"all": [{"control_id": "tide", "value": "half"}, {"lever_id": "sluice"}]}},
		{"route_id": "bollard-step", "when": {"all": [{"control_id": "tide", "value": "high"}, {"lever_id": "line"}]}}])
	return level

## The gate for route_id now holds on `when`; {} leaves it always open.
static func _replace(gates: Array, route_id: String, when: Dictionary) -> void:
	for gate: Dictionary in gates:
		if gate.route_id == route_id:
			if when.is_empty(): gate.erase("when")
			else: gate.when = when
			return
	assert(false, "No gate for " + route_id)

## The control stands at the same water as the outer sea.
static func _level_with_sea(control: String) -> Dictionary:
	var matches: Array = []
	for water: String in ["low", "half", "high"]:
		matches.append({"all": [{"control_id": control, "value": water}, {"control_id": "basin", "value": water}]})
	return {"any": matches}
