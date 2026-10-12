extends RefCounted
## Where each keepsake stands at Home. One row per catalog place:
## keepsake id -> [x, z, yaw degrees] in island metres. A new chapter adds its
## rows here; test_home_keepsake_display fails for any catalog place without one.
##
## Every Home island shares bounds [-560,-290,560,290] and gap [-100,100]. The
## spirits walk the left island. The first chapters stand on the right island
## (x 1.0..5.6, z -2.9..2.9) in a loose four by four planting about a metre
## apart, starting by the bridge and clear of the two back trees and the
## keepsake box. The latest chapters and most original islands stand on the
## keepsake garden (GARDEN), a long two-row terrace floating behind both
## islands, low enough to clear the header buttons and high enough on screen
## that no Home tree hides it. It appears once one of its keepsakes is shown.
## To add a chapter, lengthen GARDEN toward -x and add a column. The tests check
## every slot stays on an island, off the spirits, clear of the trees, the box,
## the header buttons and its neighbours.
## Row order is the browsing order and the order chapters are offered in.
const SCALE := 0.75
## How many untouched chapters, after any with progress, show their outlines.
const NEXT_CHAPTERS := 1
## The keepsake garden island: [min x, min z, max x, max z] in metres.
const GARDEN := [-5.8, -7.7, 1.62, -5.4]
const SLOTS := {
	# Right island, by the bridge: First Steps, with the Relay and High and Low in front.
	"first-steps/a-little-lift": [1.74, -0.58, 28],
	"first-steps/a-place-to-grow": [2.70, -0.51, 40],
	"relay-isles/relay": [1.73, 0.54, 34],
	"relay-isles/garden": [2.71, 0.47, 36],
	# Along the back, clear of the two trees: the Sleeping Lighthouse's six places.
	"sleeping-lighthouse/borrowed-light": [1.75, -1.58, 30],
	"sleeping-lighthouse/missing-piece": [2.73, -1.64, 26],
	"sleeping-lighthouse/two-promises": [3.84, -1.57, 32],
	"sleeping-lighthouse/after-the-first-bell": [4.80, -1.59, 38],
	"sleeping-lighthouse/what-carried-you": [3.84, -0.58, 28],
	"sleeping-lighthouse/a-welcome-left-on": [4.80, -0.51, 40],
	# Toward the front: High and Low, Rolling Home and A House for Two.
	"high-and-low/upper-path": [1.73, 1.59, 34],
	"high-and-low/down-and-around": [2.71, 1.52, 36],
	"rolling-home/weight-of-a-friend": [3.85, 0.52, 30],
	"rolling-home/bring-it-home": [4.83, 0.46, 26],
	"a-house-for-two/open-the-house": [3.84, 1.51, 32],
	"a-house-for-two/the-room-below": [4.80, 1.49, 38],
	# The keepsake garden, a long terrace in two rows. Front: the Conservatory,
	# Long Way Home and the Wishing Well.
	"conservatory/a-light-above": [-5.26, -6.13, 28],
	"conservatory/the-way-light-returns": [-4.30, -6.06, 40],
	"long-way-home/the-path-you-leave": [-3.17, -6.06, 34],
	"long-way-home/a-place-beside-you": [-2.19, -6.13, 36],
	"the-wishing-well/go-on-ahead": [-1.05, -6.08, 30],
	"the-wishing-well/back-for-you": [-0.07, -6.14, 26],
	"turn-of-the-tide/set-the-tide": [-5.35, -7.11, 32],
	"turn-of-the-tide/slack-water": [-4.22, -7.11, 38],
	# The original islands: three along the right island's front, the low Long
	# Way Home bridge at the garden's front right where a Home tree is nearest on
	# screen, and the rest along the garden's back after the turn of the tide.
	"earlier/first-light": [1.79, 2.33, 28],
	"earlier/long-way-home": [1.04, -6.07, 40],
	"earlier/after-you": [2.72, 2.36, 34],
	"earlier/patient-garden": [3.86, 2.38, 36],
	"earlier/rising-together": [-3.24, -7.18, 30],
	"earlier/across-the-blue": [-2.10, -7.13, 26],
	"earlier/lantern-crossing": [-1.12, -7.19, 32],
	"earlier/two-beats": [-0.01, -7.12, 38],
}

static func has_slot(id: String) -> bool:
	return SLOTS.has(id)

## The slot's transform on the island floor, at the shared keepsake scale.
static func transform(id: String) -> Transform3D:
	var row: Array = SLOTS[id]
	var basis := Basis(Vector3.UP, deg_to_rad(float(row[2]))).scaled(Vector3.ONE * SCALE)
	return Transform3D(basis, Vector3(float(row[0]), 0.0, float(row[1])))

static func ids() -> Array[String]:
	var result: Array[String] = []
	for id: String in SLOTS: result.append(id)
	return result

static func garden_rect() -> Rect2:
	return Rect2(GARDEN[0], GARDEN[1], GARDEN[2] - GARDEN[0], GARDEN[3] - GARDEN[1])

## True when the slot stands on the keepsake garden rather than the right island.
static func in_garden(id: String) -> bool:
	var row: Array = SLOTS[id]
	return garden_rect().has_point(Vector2(float(row[0]), float(row[1])))
