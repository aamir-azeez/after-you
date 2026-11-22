extends RefCounted
## World kit: the both-hands sign. A crossing that needs both hands ("hands":
## a ladder, a rope ladder, the wheel ride, a rope bridge, a leap;
## core/physical/carried_items.gd): a pip that steps onto it carrying
## something drops it and the turn ends. So a small bubble with two hands in
## it (assets/ui/hands.svg, in the one label bubble, kit/label_bubble.gd icon
## mode) stands at each foot of such a crossing while it is open and a pip
## carrying something stands near that foot, level with it, and only then. A
## one-way stair (a pull-up rope ladder) has its foot only.
##
## Built from the stage's data alone, so a level author writes nothing; shown
## from the snapshot alone (players' "carrying", the open "bridges"), so live
## play, the memory and every replay show the same. Presentation only. The
## journey world hosts it (_build_items, present); its bubbles join the
## world's own, so they bob, settle under Reduce motion and lift clear of
## spirits like every label.
const LabelBubble = preload("res://presentation/kit/label_bubble.gd")
const CarriedItems = preload("res://core/physical/carried_items.gd")
const ICON = preload("res://assets/ui/hands.svg")
## A carrier within this far (cm, across the floor) of a foot, and within
## LEVEL_CM of its height, shows that foot's sign.
const NEAR_CM := 150
const LEVEL_CM := 24
## The tail's tip stands this far (m) over the foot, on the crossing's first rung.
const RISE := 0.1

## One per foot: {route (the crossing's id), end ({x, z, height}, cm), bubble}.
var signs: Array[Dictionary] = []

## The feet of crossing `route` a pip steps on from: both ends, or a one-way
## stair's lower end only.
static func feet(route: Dictionary) -> Array:
	var ends := CarriedItems.route_ends(route)
	if not route.has("one_way"): return ends
	return [ends[0] if int(ends[0].height) <= int(ends[1].height) else ends[1]]

## Builds a hidden sign at each foot of each both-hands crossing of `view`
## under `parent` (the terrain: cm over 100 are its metres). Returns the
## bubbles, for the world to place and bob with its own.
func build(view: Dictionary, parent: Node3D) -> Array:
	signs.clear()
	var bubbles: Array = []
	var hands := CarriedItems.hands_routes(view)
	for route: Dictionary in view.get("bridges", []) + view.get("stairs", []):
		if not hands.has(str(route.id)): continue
		for end: Dictionary in feet(route):
			var bubble := LabelBubble.new()
			bubble.build_icon(parent, Vector3(float(end.x), float(end.height), float(end.z)) / 100.0 + Vector3(0, RISE, 0), ICON)
			bubble.name = "HandsSign_" + str(route.id)
			bubble.visible = false
			signs.append({"route": str(route.id), "end": end, "bubble": bubble})
			bubbles.append(bubble)
	return bubbles

## Shows each sign whose crossing is open in `state` while a pip carrying
## something stands near its foot; hides the rest. True when any changed.
func present(state: Dictionary) -> bool:
	if signs.is_empty(): return false
	var routes: Dictionary = state.get("bridges", {})
	var players: Variant = state.get("players")
	var changed := false
	for entry: Dictionary in signs:
		var bubble: Node3D = entry.bubble
		if not is_instance_valid(bubble): continue
		var shown := bool(routes.get(entry.route, false)) and players is Dictionary and carrier_near(players, entry.end)
		if bubble.visible != shown:
			bubble.visible = shown
			changed = true
	return changed

## Whether a pip of `players` carrying something stands near `end`, level with it.
static func carrier_near(players: Dictionary, end: Dictionary) -> bool:
	for slot: Variant in players:
		var player: Variant = players[slot]
		if not player is Dictionary or str(player.get("carrying", "")).is_empty(): continue
		if absi(int(player.get("height", 0)) - int(end.height)) > LEVEL_CM: continue
		if Vector2(float(player.x), float(player.z)).distance_to(Vector2(float(end.x), float(end.z))) <= NEAR_CM: return true
	return false

## The signs shown now (by crossing id), for tests and the world.
func shown() -> Array:
	var found: Array = []
	for entry: Dictionary in signs:
		if is_instance_valid(entry.bubble) and (entry.bubble as Node3D).visible: found.append(entry.route)
	return found
