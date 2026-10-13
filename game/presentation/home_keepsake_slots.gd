extends RefCounted
## Where each keepsake stands at Home, how big it is and how it looks once
## finished. One row per catalog place: keepsake id -> [x, z, yaw degrees] in
## island metres. A new chapter adds its rows here (and its size in
## CHAPTER_SCALE); test_home_keepsake_display fails for any place without one.
##
## The spirits walk the left island. The free chapters stand on the right
## island (x 1.0..5.6, z -2.9..2.9) in a ring around a flower bed. The Sleeping
## Lighthouse and the turn of the tide stand on an island behind the left one,
## the premium chapters on one behind the right, and the original islands on
## one beside the right (ISLANDS), each joined by a bridge. Home opens on the
## spirits and the ring; panning, zooming out or exploring shows the rest. The
## tests check every slot stays on its island, off the spirits, clear of the
## trees, the box, the header buttons and its neighbours, and that the whole
## collection fits the screen at the widest zoom.
## Row order is the browsing order and the order chapters are offered in.
const SMALL := 0.95
const BIG := 1.3
## Keepsake size by chapter. The free chapters are small; the Sleeping
## Lighthouse, the turn of the tide and the premium chapters are big. A chapter
## missing here is big.
const CHAPTER_SCALE := {
	"first-steps": SMALL, "relay-isles": SMALL, "high-and-low": SMALL, "the-wishing-well": SMALL, "earlier": SMALL,
	"sleeping-lighthouse": BIG, "turn-of-the-tide": BIG, "rolling-home": BIG, "a-house-for-two": BIG,
	"conservatory": BIG, "long-way-home": BIG,
}
## How many untouched chapters, after any with progress, show their outlines.
const NEXT_CHAPTERS := 1
## The finished look every keepsake gets once done solo and with a friend: a
## stone plinth with a gold rim and a few sparkles, in the keepsake's own units.
const UPGRADE := {"plinth": 0.5, "height": 0.09, "sparkles": 3}
## Optional per-keepsake changes to the size ("scale") or the upgrade.
const TWEAKS := {
	"earlier/after-you": {"plinth": 0.56}, "earlier/long-way-home": {"plinth": 0.56},
	"long-way-home/a-place-beside-you": {"plinth": 0.56}, "relay-isles/garden": {"plinth": 0.56},
}
## Home-only islands for keepsakes, each shown once one of its keepsakes is:
## centre [x, z], size along x and z, and a plank bridge [[start x, z],
## [direction]] from a Home island that runs until it reaches this one.
const ISLANDS := {
	"behind_left": {"center": [-3.3, -8.0], "length": 4.6, "depth": 8.1, "yaw": 0.0, "bridge": [[-3.4, -2.9], [0.0, -1.0]]},
	"behind_right": {"center": [3.3, -8.0], "length": 4.6, "depth": 8.1, "yaw": 0.0, "bridge": [[4.95, -2.9], [0.0, -1.0]]},
	"beside_right": {"center": [8.5, 0.0], "length": 4.0, "depth": 5.8, "yaw": 0.0, "bridge": [[5.6, -0.02], [1.0, 0.0]]},
}
const SLOTS := {
	# Right island: the free chapters on a ring around a flower bed, First Steps
	# nearest the bridge.
	"first-steps/a-little-lift": [1.78, 1.00, 30],
	"first-steps/a-place-to-grow": [1.78, -0.30, 36],
	"relay-isles/relay": [2.70, -1.22, 33],
	"relay-isles/garden": [4.00, -1.22, 39],
	"high-and-low/upper-path": [4.92, -0.30, 31],
	"high-and-low/down-and-around": [4.92, 1.00, 37],
	"the-wishing-well/go-on-ahead": [4.00, 1.92, 34],
	"the-wishing-well/back-for-you": [2.70, 1.92, 28],
	# Behind the left island: the Sleeping Lighthouse, then the turn of the tide.
	"sleeping-lighthouse/borrowed-light": [-4.35, -5.45, 33],
	"sleeping-lighthouse/missing-piece": [-2.24, -5.39, 39],
	"sleeping-lighthouse/two-promises": [-3.20, -6.85, 31],
	"sleeping-lighthouse/after-the-first-bell": [-4.40, -8.30, 37],
	"sleeping-lighthouse/what-carried-you": [-2.20, -8.21, 34],
	"sleeping-lighthouse/a-welcome-left-on": [-3.40, -9.65, 28],
	"turn-of-the-tide/set-the-tide": [-4.55, -11.00, 30],
	"turn-of-the-tide/slack-water": [-2.25, -11.09, 36],
	# Behind the right island: the premium chapters.
	"rolling-home/weight-of-a-friend": [2.25, -5.45, 33],
	"rolling-home/bring-it-home": [4.36, -5.39, 39],
	"a-house-for-two/open-the-house": [3.40, -6.85, 31],
	"a-house-for-two/the-room-below": [2.20, -8.30, 37],
	"conservatory/a-light-above": [4.34, -8.21, 34],
	"conservatory/the-way-light-returns": [3.20, -9.65, 28],
	"long-way-home/the-path-you-leave": [2.24, -11.00, 30],
	"long-way-home/a-place-beside-you": [4.35, -11.09, 36],
	# Beside the right island: the original islands.
	"earlier/first-light": [7.55, -2.10, 37],
	"earlier/long-way-home": [9.46, -2.04, 34],
	"earlier/patient-garden": [7.60, -0.70, 28],
	"earlier/rising-together": [9.50, -0.75, 30],
	"earlier/across-the-blue": [7.44, 0.74, 36],
	"earlier/lantern-crossing": [9.40, 0.70, 33],
	"earlier/two-beats": [7.54, 2.15, 39],
	"earlier/after-you": [9.45, 2.06, 31],
}

static func has_slot(id: String) -> bool:
	return SLOTS.has(id)

static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in SLOTS: result.append(id)
	return result

static func tweak(id: String) -> Dictionary:
	return TWEAKS.get(id, {})

static func scale_of(id: String) -> float:
	return float(tweak(id).get("scale", CHAPTER_SCALE.get(id.get_slice("/", 0), BIG)))

## The upgrade for one keepsake: the shared treatment with its tweaks applied.
static func upgrade(id: String) -> Dictionary:
	var result := UPGRADE.duplicate()
	for key: String in tweak(id):
		if result.has(key): result[key] = tweak(id)[key]
	return result

## The slot's transform on the island floor, at its keepsake's size.
static func transform(id: String) -> Transform3D:
	var row: Array = SLOTS[id]
	var basis := Basis(Vector3.UP, deg_to_rad(float(row[2]))).scaled(Vector3.ONE * scale_of(id))
	return Transform3D(basis, Vector3(float(row[0]), 0.0, float(row[1])))

static func island_transform(island: String) -> Transform3D:
	var spec: Dictionary = ISLANDS[island]
	var middle: Array = spec.center
	return Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec.yaw))), Vector3(float(middle[0]), 0.0, float(middle[1])))

## An island in its own flat coordinates, centred on zero.
static func island_rect(island: String) -> Rect2:
	var spec: Dictionary = ISLANDS[island]
	return Rect2(-float(spec.length) / 2.0, -float(spec.depth) / 2.0, float(spec.length), float(spec.depth))

## A world point in an island's own flat coordinates.
static func island_local(island: String, point: Vector3) -> Vector2:
	var local := island_transform(island).affine_inverse() * point
	return Vector2(local.x, local.z)

## The Home-only island a slot stands on, or "" for the right island.
static func island_of(id: String) -> String:
	var origin := transform(id).origin
	for island: String in ISLANDS:
		if island_rect(island).has_point(island_local(island, origin)): return island
	return ""
