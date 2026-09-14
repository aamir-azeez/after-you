class_name AfterYouLevels
extends RefCounted

## Versioned, authored puzzle definitions. Coordinates are integer centimetres.
## Versions are immutable: change the version when changing puzzle behavior.
const IDS := ["first-light", "long-way-home", "patient-garden", "rising-together", "across-the-blue", "lantern-crossing", "two-beats", "after-you"]

static func all_levels() -> Array:
	return [
		_make(0, "First Light", "Catch something your friend threw yesterday.", 0, 180, [-430, 100], [-240, -120], [-330, 0], [330, 0], [470, 120], 75,
			"Stand on the glowing plate. Tap Throw, then stay there for your friend.", "Cross the bridge. Catch the seed near its landing ring, then bring it to the garden.", {"palette": ["#819e8d", "#f0bc7c", "#cee5db"]}),
		_make(1, "Long Way Home", "A little detour is still a way together.", -120, 140, [-470, 80], [-270, 130], [-340, -120], [340, -120], [470, 180], 90,
			"Find the plate by the upper bridge. Throw from the plate and hold the way open.", "Find the upper crossing before running for the landing ring.", {"palette": ["#819cb5", "#eac393", "#d7e5ea"]}),
		_make(2, "Patient Garden", "An invitation can wait for you.", -150, 150, [-460, -220], [-260, -150], [-340, -150], [300, 140], [480, 210], 120,
			"Your seed takes a long, gentle arc. Hold the bridge and watch it travel.", "Cross first, then follow the landing marker down to the garden.", {"palette": ["#91a880", "#f0a991", "#e4e7c5"]}),
		_make(3, "Rising Together", "Some friends lift the whole world.", 0, 170, [-440, 100], [-250, -100], [-340, 0], [340, 0], [480, 100], 120,
			"Keep the plate held after your throw. It also raises your friend's garden.", "Ride the rising garden, catch the seed, then plant it when the lift reaches the top.", {"lift": {"zone": [230, -180, 560, 210], "height": 130, "rise_ticks": 85}, "palette": ["#a2a3bb", "#e6bddd", "#dddcef"]}),
		_make(4, "Across the Blue", "Leave a path, then open another door.", -130, 150, [-460, -210], [-270, -130], [-340, -130], [320, -130], [470, 150], 100,
			"Throw from the first plate, then walk onto the second plate. Your throw keeps the bridge open.", "Catch the seed while your friend's ghost opens the garden with the second plate.", {"gate": {"plate": [-340, 170]}, "palette": ["#6e9eaa", "#efbe89", "#b9dce5"]}),
		_make(5, "Lantern Crossing", "A patient light makes a narrow way.", 120, 110, [-430, -100], [-270, -100], [-330, 120], [330, 120], [470, -140], 110,
			"Hold the plate until the lantern fills, then throw. The narrow bridge opens when charged.", "Wait for the bridge's light, cross near its center, then carry the seed back to the garden.", {"bridge_charge_ticks": 45, "palette": ["#92859e", "#f0bd7e", "#dcd1e5"]}),
		_make(6, "Two Beats", "First a crossing. Then a welcome.", 0, 140, [-460, 140], [-260, -160], [-350, 0], [330, 0], [460, 170], 110,
			"Charge the plate, throw, then move to the second plate. Both steps become your friend's welcome.", "Cross on the first beat, catch the seed, and wait for the second plate to open the garden.", {"bridge_charge_ticks": 30, "gate": {"plate": [-350, 220]}, "palette": ["#a3a87a", "#e8c893", "#e5e6c8"]}),
		_make(7, "After You", "You were here. I was here. We made this.", -70, 140, [-470, -200], [-270, -70], [-350, -70], [340, -70], [480, 170], 120,
			"Charge the bridge and let the lift rise. Throw, then open the garden from the second plate.", "Follow your friend's path through the bridge and rising garden. Plant your last seed together.", {"bridge_charge_ticks": 60, "gate": {"plate": [-350, 200]}, "lift": {"zone": [240, -190, 560, 210], "height": 160, "rise_ticks": 60}, "palette": ["#91a395", "#eebeaa", "#e6ecdd"]})
	]

static func get_level(id: Variant) -> Dictionary:
	var levels: Array = all_levels()
	if typeof(id) == TYPE_INT:
		return levels[clampi(int(id), 0, levels.size() - 1)].duplicate(true)
	for level: Dictionary in levels:
		if level.id == str(id):
			return level.duplicate(true)
	return {}

static func _make(index: int, title: String, subtitle: String, bridge_z: int, width: int, start_a: Array, start_b: Array, plate: Array, landing: Array, goal: Array, flight_ticks: int, hint_a: String, hint_b: String, extras: Dictionary) -> Dictionary:
	var result := {
		"id": IDS[index], "version": 1, "index": index, "number": index + 1,
		"title": title, "subtitle": subtitle, "premium": index >= 3,
		"mechanic": "bridge_seed", "starts": {"a": start_a, "b": start_b},
		"plate": plate, "landing": landing, "goal": goal,
		"bounds": [-560, -290, 560, 290], "gap": [-100, 100],
		"bridge": {"z": bridge_z, "width": width}, "bridge_charge_ticks": 1,
		"flight_ticks": flight_ticks, "seed_wait_ticks": 180,
		"plate_radius": 65, "catch_radius": 105, "goal_radius": 75,
		"hint_a": hint_a, "hint_b": hint_b,
	}
	result.merge(extras, true)
	return result
