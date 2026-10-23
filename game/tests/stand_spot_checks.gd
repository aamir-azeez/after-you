extends RefCounted
## Shared checks for a world whose descriptor has "stand_spots"
## (presentation/kit/stand_spot.gd): every pressure pad of the stage on show is
## a stand spot drawn exactly at the pad's radius_cm, its mark and the goal
## beacon's ring stay inside it, and it shows held exactly when the snapshot's
## hold_pads says the pad counts. Each returns failure messages ([] passes).
const StandSpot = preload("res://presentation/kit/stand_spot.gd")
const GoalBeacon = preload("res://presentation/kit/goal_beacon.gd")
const SpiritVisual = preload("res://presentation/spirit_visual.gd")

## The spots' shapes on `stage`'s pads in `world`.
static func shapes(world: Node3D, stage: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for pad: Dictionary in stage.get("pressure_pads", []):
		var id := str(pad.id)
		var radius := float(pad.radius_cm) / 100.0
		var spot: StandSpot = world._stand_spots.get(id)
		if spot == null:
			found.append("Pad %s has a stand spot" % id)
			continue
		var disc := spot.disc.mesh as CylinderMesh
		if disc == null or not is_equal_approx(disc.top_radius, radius) or not is_equal_approx(disc.bottom_radius, radius):
			found.append("Pad %s's disc is drawn at exactly its radius_cm %d" % [id, pad.radius_cm])
		var rim := spot.rim.mesh as TorusMesh
		if rim == null or not is_equal_approx(rim.outer_radius, radius):
			found.append("Pad %s's rim ends at exactly its radius_cm %d" % [id, pad.radius_cm])
		if world._physical_pads.get(id) != spot.rim: found.append("Pad %s's lit outline is its spot's rim" % id)
		var at: Vector3 = world._at(pad)
		if not (is_equal_approx(spot.position.x, at.x) and is_equal_approx(spot.position.z, at.z) and is_equal_approx(spot._rest_y, at.y)):
			found.append("Pad %s's spot stands on the pad's own point and floor" % id)
		var inner := radius - StandSpot.RIM_WIDTH
		var mark_reach: float = (spot.mark.mesh as BoxMesh).size.x * 0.7072 if spot.mark.mesh is BoxMesh else (spot.mark.mesh as TorusMesh).outer_radius
		if mark_reach > inner: found.append("Pad %s's owner mark stays inside its rim" % id)
		var mark_top: float = spot.mark.position.y + StandSpot.MARK_THICKNESS * 0.5
		if StandSpot.DISC_HEIGHT > SpiritVisual.SHADOW_TOP or mark_top > SpiritVisual.SHADOW_TOP + 0.0001:
			found.append("Pad %s's disc and mark stay under a spirit's ground shadow" % id)
		if (spot.mark.material_override == null) or (spot.disc.material_override == null): found.append("Pad %s's spot pieces have a look" % id)
	return found

## The goal beacon's rings on stand spots breathe inside them at their widest.
static func beacon_rings(world: Node3D, stage: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var beacon: GoalBeacon = world._goal_beacon
	if beacon == null: return found
	var radii: Dictionary = {}
	for pad: Dictionary in stage.get("pressure_pads", []):
		radii[Vector2(world._at(pad).x, world._at(pad).z)] = float(pad.radius_cm) / 100.0
	var checked := 0
	for role: String in beacon._beacons:
		for index in range(beacon._beacons[role].size()):
			var spot: Dictionary = beacon._spots[role][index]
			var key := Vector2(spot.at.x, spot.at.z)
			if not radii.has(key): continue
			checked += 1
			var ring := (beacon._beacons[role][index].nodes[GoalBeacon.RING] as MeshInstance3D).mesh as TorusMesh
			var seated := false
			for pad: Dictionary in stage.get("pressure_pads", []):
				if Vector2(world._at(pad).x, world._at(pad).z) == key: seated = world._seated(str(pad.id))
			# A seat fills its spot: that beacon draws no floor ring at all.
			if seated != (not bool(beacon._beacons[role][index].ring)) or (seated and beacon._beacons[role][index].nodes[GoalBeacon.RING].visible):
				found.append("A beacon draws no ring exactly on a seated pad (%s)" % [key])
			if not is_equal_approx(float(spot.get("inside", 0.0)), float(radii[key])):
				found.append("A beacon on a pad knows the pad's radius (%s)" % [key])
			elif ring.outer_radius * (1.0 + GoalBeacon.BREATH) > float(radii[key]) - StandSpot.RIM_WIDTH + 0.0001:
				found.append("A beacon ring on a pad breathes inside the spot's rim at its widest (%s)" % [key])
			if beacon._beacons[role][index].nodes[GoalBeacon.RING].position.y <= StandSpot.DISC_HEIGHT:
				found.append("A beacon ring on a pad rides above the spot's disc (%s)" % [key])
	if checked == 0 and not stage.get("pressure_pads", []).is_empty() and str(stage.get("source_policy", {}).get("kind", "")) == "choice_pad":
		found.append("The stage's pad beacons were found")
	return found

## Each spot shows held exactly when `state`'s hold_pads counts its pad.
static func held(world: Node3D, stage: Dictionary, state: Dictionary) -> Array[String]:
	var found: Array[String] = []
	for pad: Dictionary in stage.get("pressure_pads", []):
		var id := str(pad.id)
		var spot: StandSpot = world._stand_spots.get(id)
		if spot == null: continue
		var counts := bool(state.get("hold_pads", {}).get(id, false))
		var look := spot.disc.material_override as StandardMaterial3D
		var lit: bool = look.emission_enabled and look.emission == world.LIGHT_COLOR
		var sunk: bool = spot.position.y < world._at(pad).y - StandSpot.PRESS_DEPTH * 0.5
		if spot.held != counts or lit != counts or sunk != counts:
			found.append("Pad %s's spot shows %s exactly when the pad %s" % [id, "held" if counts else "free", "counts" if counts else "does not count"])
	return found
