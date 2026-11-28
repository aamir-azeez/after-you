extends SceneTree
## Item spots and goal pedestals, every level that has them:
## - snap: an item put down anywhere in a spot's counted ring (the whole disc of
##   a plain spot, the band round a solid one) rests exactly in the spot, its
##   place and height the spot's, from every angle; the nearest spot wins when
##   rings overlap;
## - spot over hand over: with the partner within hand reach, a put down in a
##   spot's ring still goes to the spot; away from every spot it is a hand over;
## - the dotted outline: ink on a light top, cream on a dark one, drawn after the
##   see-through things with the depth test on (a pip in front hides it),
##   pulsing while the item is missing and steady under Reduce motion;
## - Fog Marsh's stamp desk is in the settled dressing, on the desk spot.
const CarriedItems = preload("res://core/physical/carried_items.gd")
const Solid = preload("res://core/solid_footprint.gd")
const SocketKit = preload("res://presentation/kit/pieces/socket.gd")
const Simulation = preload("res://core/journey/simulation.gd")
const DressingCatalog = preload("res://content/dressing/catalog.gd")
const CATALOGS := {
	"first-steps-v2": "res://core/journey/first_steps_v2_catalog.gd",
	"fog-marsh": "res://core/journey/fog_marsh_catalog.gd",
	"relay-isles-v3": "res://core/journey/relay_isles_v3_catalog.gd",
	"sleeping-lighthouse-v3": "res://core/journey/sleeping_lighthouse_v3_catalog.gd",
	"the-falls": "res://core/journey/the_falls_catalog.gd",
	"the-wishing-well-v2": "res://core/journey/the_wishing_well_v2_catalog.gd"}
const CHECKPOINT := "res://tests/fixtures/journey/catch-the-pipsport-checkpoint.json"
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var spots := 0
	for name: String in CATALOGS:
		var definition: Dictionary = load(CATALOGS[name]).definition()
		spots += _snap(name, definition)
	_check(spots >= 20, "Every catalog's item spots were swept (%d)" % spots)
	_overlap()
	_hand_over()
	_outline()
	_desk_dressing()
	print("ITEM SPOT POLISH: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## Every spot on an island: from every angle and from the middle to the edge of the
## counted ring, standing level with it, the put down rests exactly in it.
func _snap(name: String, definition: Dictionary) -> int:
	var islands: Dictionary = {}
	for island: Dictionary in definition.get("islands", []): islands[str(island.id)] = island
	var swept := 0
	for spot: Dictionary in definition.get("item_spots", []):
		var surface := str(spot.get("surface_id", ""))
		if not islands.has(surface): continue
		swept += 1
		var label := "%s %s" % [name, spot.id]
		_check(int(islands[surface].get("height_cm", 0)) == int(spot.get("height_cm", 0)), "%s rests level with its floor" % label)
		var solid := Solid.of(spot)
		var centre := Vector2i(int(spot.position_cm[0]), int(spot.position_cm[1]))
		var inner := 0 if solid.is_empty() else int(solid.radius_cm) + Solid.BODY_CM
		var outer: int = int(spot.get("radius_cm", CarriedItems.SPOT_RADIUS_CM)) if solid.is_empty() else inner + int(solid.get("reach_cm", 0))
		var wrong := 0
		for angle in range(0, 360, 10):
			for step in range(0, 5):
				var radius := inner + (outer - inner) * step / 4
				var player := {"x": centre.x + roundi(cos(deg_to_rad(angle)) * radius), "z": centre.y + roundi(sin(deg_to_rad(angle)) * radius), "height": int(spot.get("height_cm", 0)), "surface_id": surface}
				# Rounding to whole cm may step a hair past either edge: keep inside.
				var away := Vector2i(player.x, player.z).distance_to(centre)
				if away > float(outer) or away < float(inner): continue
				if CarriedItems.lay(definition, player) != CarriedItems.at_spot(spot): wrong += 1
		_check(wrong == 0, "%s takes a put down from every side and every distance in its ring (%d missed)" % [label, wrong])
	return swept

## Two spots whose rings overlap: the nearer one takes it.
func _overlap() -> void:
	var level := {"islands": [{"id": "a", "rect_cm": [0, 0, 500, 500], "height_cm": 0}], "item_spots": [
		{"id": "far", "surface_id": "a", "position_cm": [100, 100], "height_cm": 0, "radius_cm": 60},
		{"id": "near", "surface_id": "a", "position_cm": [140, 100], "height_cm": 0, "radius_cm": 60}]}
	var player := {"x": 130, "z": 100, "height": 0, "surface_id": "a"}
	_check(str(CarriedItems.lay(level, player).spot) == "near", "Where two rings overlap the nearer spot takes the item")
	player.x = 112
	_check(str(CarriedItems.lay(level, player).spot) == "far", "And the other when the pip stands nearer that one")

## A carrier with the partner in hand reach: in a spot's ring it puts down at the
## spot; off every spot it hands over.
func _hand_over() -> void:
	var definition: Dictionary = load(CATALOGS["fog-marsh"]).definition()
	var checkpoint: Variant = JSON.parse_string(FileAccess.get_file_as_string(CHECKPOINT))
	var desk := CarriedItems.spot(definition, "desk")
	var mid: int = int(desk.solid.radius_cm) + Solid.BODY_CM + int(desk.solid.reach_cm) / 2
	var ring := Vector2i(int(desk.position_cm[0]) + mid, int(desk.position_cm[1]))
	var sim := _start(definition, checkpoint, ring, ring + Vector2i(0, -30))
	_check(CarriedItems.can_hand(definition, {}, sim._players[sim.active_slot], sim._players[sim._other(sim.active_slot)], {}), "The partner stands within hand reach")
	_check(sim.context_action().id == "put", "In the desk's ring a put down wins over a hand over (%s)" % str(sim.context_action()))
	sim.step({})
	sim.step({"interact": true})
	var rested: Dictionary = sim._mechanisms.items.pipsport
	_check(rested == CarriedItems.at_spot(desk), "The item rests exactly in the desk spot: %s" % [rested])
	var away := _start(definition, checkpoint, Vector2i(11110, 620), Vector2i(11110, 590))
	_check(away.context_action().id == "give", "Off every spot, with the partner near, it is still a hand over (%s)" % str(away.context_action()))

## A sim of the carry-it-home stage, the live pip (carrying the pipsport) at `at`, the other at `other`, on the office floor.
func _start(definition: Dictionary, checkpoint: Dictionary, at: Vector2i, other: Vector2i) -> RefCounted:
	var sim := Simulation.new()
	sim.simulation_version = int(definition.simulation_version)
	sim.packed_recordings = true
	sim._reset_trusted(definition, "carry-it-home", checkpoint, {}, "a", [])
	for pair: Array in [[sim.active_slot, at], [sim._other(sim.active_slot), other]]:
		var player: Dictionary = sim._players[pair[0]]
		player.x = pair[1].x
		player.z = pair[1].y
		player.height = 192
		player.surface_id = "office"
	sim._mechanisms.items.pipsport = CarriedItems.held(str(sim.active_slot))
	return sim

func _outline() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var pedestal := Node3D.new()
	holder.add_child(pedestal)
	var outline := SocketKit.item_spot("pedestal", pedestal, {"id": "p", "radius_cm": 36, "solid": {"radius_cm": 28, "reach_cm": 20}}, "pipsport")
	_check(outline != null and outline.get_child_count() >= 8, "A pedestal wanting the pipsport draws its dotted outline")
	var material := outline.get_meta(SocketKit.OUTLINE_MATERIAL_META) as StandardMaterial3D
	var dash := outline.get_child(0) as MeshInstance3D
	_check(dash.material_override == material and not material.no_depth_test, "The dashes use the outline's one material, with the depth test on")
	_check(material.render_priority >= SocketKit.OUTLINE_PRIORITY and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and material.depth_draw_mode == BaseMaterial3D.DEPTH_DRAW_DISABLED, "It draws after the see-through things and writes no depth")
	_check(_luminance(SocketKit.OUTLINE_INK) < 0.2 and _luminance(Color("f4ecd8")) > 0.8, "The ink is dark enough against the cream cap")
	_check(SocketKit.DASH.z >= 0.03 and SocketKit.DASH.y >= 0.01, "The dashes are thick")
	var planter := Node3D.new()
	holder.add_child(planter)
	var light := SocketKit.item_spot("planter", planter, {"id": "q", "radius_cm": 48}, "pipsport")
	_check((light.get_meta(SocketKit.OUTLINE_MATERIAL_META) as StandardMaterial3D).albedo_color.is_equal_approx(SocketKit.OUTLINE_CREAM), "On a dark planter it is cream")
	var seen: Array = []
	for step in range(40):
		SocketKit.pulse(outline, float(step) * 0.1, false)
		seen.append(material.albedo_color.a)
	_check(seen.min() >= SocketKit.OUTLINE_PULSE.x - 0.001 and seen.max() <= SocketKit.OUTLINE_PULSE.y + 0.001 and seen.max() - seen.min() > 0.3, "While the item is missing the outline pulses in its band")
	for step in range(10):
		SocketKit.pulse(outline, float(step) * 0.37, true)
		_check(is_equal_approx(material.albedo_color.a, SocketKit.OUTLINE_PULSE.y), "Under Reduce motion it holds steady")
	holder.free()

func _desk_dressing() -> void:
	var found := false
	for stage: Variant in DressingCatalog.for_key("fog-marsh@1").props.values():
		for spec: Dictionary in stage:
			if str(spec.get("kind", "")) == "stamp_desk" and spec.get("at", []) == [11160, 540]: found = true
	_check(found, "Fog Marsh's stamp desk stands in the settled dressing, on the desk spot")

func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", label)
