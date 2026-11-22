extends RefCounted
## Shared checks for a world's pressure pads (presentation/kit/pieces/pad.gd):
## every pressure pad of the stage on show is drawn at exactly the pad's
## radius_cm (a board's rim a square frame just inside its edge, a pan's a
## ring), on the pad's own point, lit by the world; the goal beacon's ring
## breathes on the board inside the outline; and a pad shows held
## (sunk, its rim lit) exactly when the snapshot's hold_pads says the pad
## counts. Each returns failure messages ([] passes).
const PadKit = preload("res://presentation/kit/pieces/pad.gd")
const GoalBeacon = preload("res://presentation/kit/goal_beacon.gd")

## The pads' shapes on `stage`'s pads in `world`.
static func shapes(world: Node3D, stage: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for pad: Dictionary in stage.get("pressure_pads", []):
		var id := str(pad.id)
		var radius := float(pad.radius_cm) / 100.0
		var piece: RefCounted = world.pad_pieces.get(id)
		if piece == null:
			found.append("Pad %s is built" % id)
			continue
		if not outline_fits(piece) or not is_equal_approx(piece.radius, radius):
			found.append("Pad %s's outline is drawn exactly at its radius_cm %d" % [id, pad.radius_cm])
		if world._physical_pads.get(id) != piece.rim: found.append("Pad %s's lit outline is its rim" % id)
		var at: Vector3 = world._at(pad)
		if not (piece.at.is_equal_approx(at) and piece.root.position.is_equal_approx(at)):
			found.append("Pad %s stands on the pad's own point and floor" % id)
	return found

## Whether `piece`'s rim is its style's outline at its size: a board's a
## square-cornered frame just inside the board's edge (none of it inside the
## frame's clear room, PadKit.frame_inside), a pan's a round ring of its radius.
static func outline_fits(piece: RefCounted) -> bool:
	if piece.style == "pan":
		var ring := piece.rim.mesh as TorusMesh
		return ring != null and is_equal_approx(ring.outer_radius, piece.radius + PadKit.RIM_TUBE)
	var half: Vector2 = piece.half_size
	var inside := PadKit.frame_inside(half)
	if piece.rim.mesh is TorusMesh or inside.x <= 0.0 or inside.y <= 0.0 or not piece.rim.basis.is_equal_approx(Basis()): return false
	var box: AABB = piece.rim.mesh.get_aabb()
	var outer := half - Vector2.ONE * PadKit.RIM_EDGE
	if not (is_equal_approx(box.end.x, outer.x) and is_equal_approx(box.end.z, outer.y) and is_equal_approx(-box.position.x, outer.x) and is_equal_approx(-box.position.z, outer.y)): return false
	var reaches_inside := false
	for corner: Vector3 in piece.rim.mesh.get_faces():
		if absf(corner.x) < inside.x - 0.0001 and absf(corner.z) < inside.y - 0.0001: return false
		if is_equal_approx(absf(corner.x), inside.x) or is_equal_approx(absf(corner.z), inside.y): reaches_inside = true
	return reaches_inside

## The goal beacon's rings on pads breathe on the board inside the outline.
static func beacon_rings(world: Node3D, stage: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var beacon: GoalBeacon = world._goal_beacon
	if beacon == null: return found
	var radii: Dictionary = {}
	for pad: Dictionary in stage.get("pressure_pads", []):
		radii[Vector2(world._at(pad).x, world._at(pad).z)] = PadKit.rim_inside(world._piece_style("pad", str(pad.id)), float(pad.radius_cm) / 100.0)
	var checked := 0
	for role: String in beacon._beacons:
		for index in range(beacon._beacons[role].size()):
			var spot: Dictionary = beacon._spots[role][index]
			var key := Vector2(spot.at.x, spot.at.z)
			# Round a goal its ring lies on the floor past the goal's disc, which
			# the plate fills (kit/pieces/goal.gd outer_radius).
			if spot.has("around"):
				var outside := (beacon._beacons[role][index].nodes[GoalBeacon.RING] as MeshInstance3D).mesh as TorusMesh
				if outside.inner_radius <= float(spot.around): found.append("A beacon ring round a goal lies past its disc (%s)" % [key])
			if not radii.has(key): continue
			checked += 1
			var ring := (beacon._beacons[role][index].nodes[GoalBeacon.RING] as MeshInstance3D).mesh as TorusMesh
			var seated := false
			for pad: Dictionary in stage.get("pressure_pads", []):
				if Vector2(world._at(pad).x, world._at(pad).z) == key: seated = world._seated(str(pad.id))
			# A seat fills its pad: that beacon draws no floor ring at all.
			if seated != (not bool(beacon._beacons[role][index].ring)) or (seated and beacon._beacons[role][index].nodes[GoalBeacon.RING].visible):
				found.append("A beacon draws no ring exactly on a seated pad (%s)" % [key])
			if not is_equal_approx(float(spot.get("inside", 0.0)), float(radii[key])):
				found.append("A beacon on a pad knows the room inside the pad's outline (%s)" % [key])
			elif ring.outer_radius * (1.0 + GoalBeacon.BREATH) > float(radii[key]) - GoalBeacon.INSIDE_CLEAR + 0.0001:
				found.append("A beacon ring on a pad breathes inside the pad's outline at its widest (%s)" % [key])
			if beacon._beacons[role][index].nodes[GoalBeacon.RING].position.y <= PadKit.BOARD_TOP:
				found.append("A beacon ring on a pad lies on the pad's board (%s)" % [key])
	if checked == 0 and not stage.get("pressure_pads", []).is_empty() and str(stage.get("source_policy", {}).get("kind", "")) == "choice_pad":
		found.append("The stage's pad beacons were found")
	return found

## Each pad shows held exactly when `state`'s hold_pads counts it.
static func held(world: Node3D, stage: Dictionary, state: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for pad: Dictionary in stage.get("pressure_pads", []):
		var id := str(pad.id)
		var piece: RefCounted = world.pad_pieces.get(id)
		if piece == null: continue
		var counts := bool(state.get("hold_pads", {}).get(id, false))
		var look := piece.rim.material_override as StandardMaterial3D
		var lit: bool = look.emission_enabled and look.emission == world.LIGHT_COLOR
		var sunk: bool = piece._dish.position.y < -PadKit.BOARD_SINK * 0.5
		if piece.held() != counts or lit != counts or sunk != counts:
			found.append("Pad %s shows %s exactly when the pad %s" % [id, "held" if counts else "free", "counts" if counts else "does not count"])
	return found
