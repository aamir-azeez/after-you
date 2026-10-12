extends RefCounted
## Where each keepsake stands on the Home island. One row per catalog place:
## keepsake id -> [x, z, yaw degrees] in island metres. A new chapter adds its
## rows here; test_home_keepsake_display fails for any catalog place without one.
##
## Every Home island shares bounds [-560,-290,560,290] and gap [-100,100]. The
## spirits walk the left island, so all keepsakes stand on the right one
## (x 1.0..5.6, z -2.9..2.9), in six columns of three chapter pairs that step
## away from the bridge as the journey goes on. A pair stands 0.67 apart, with a
## wider gap before the next pair. The back edge keeps clear of the two trees
## and the front right corner of the keepsake box.
## Row order is the browsing order, and the first unfinished row is shown first.
const SCALE := 0.5
const SLOTS := {
	# Column 1, by the bridge: the two opening chapters and High and Low.
	"first-steps/a-little-lift": [1.54, -1.94, 30],
	"first-steps/a-place-to-grow": [1.66, -1.28, 36],
	"relay-isles/relay": [1.54, -0.33, 33],
	"relay-isles/garden": [1.66, 0.33, 38],
	"high-and-low/upper-path": [1.54, 1.28, 31],
	"high-and-low/down-and-around": [1.66, 1.94, 35],
	# Column 2: the Sleeping Lighthouse's six places.
	"sleeping-lighthouse/borrowed-light": [2.24, -1.80, 36],
	"sleeping-lighthouse/missing-piece": [2.36, -1.14, 33],
	"sleeping-lighthouse/two-promises": [2.24, -0.19, 38],
	"sleeping-lighthouse/after-the-first-bell": [2.36, 0.47, 31],
	"sleeping-lighthouse/what-carried-you": [2.24, 1.42, 35],
	"sleeping-lighthouse/a-welcome-left-on": [2.36, 2.08, 30],
	# Column 3: Rolling Home, A House for Two and the Conservatory.
	"rolling-home/weight-of-a-friend": [2.94, -1.94, 33],
	"rolling-home/bring-it-home": [3.06, -1.28, 38],
	"a-house-for-two/open-the-house": [2.94, -0.33, 31],
	"a-house-for-two/the-room-below": [3.06, 0.33, 35],
	"conservatory/a-light-above": [2.94, 1.28, 30],
	"conservatory/the-way-light-returns": [3.06, 1.94, 36],
	# Column 4: the latest chapters.
	"long-way-home/the-path-you-leave": [3.64, -1.80, 38],
	"long-way-home/a-place-beside-you": [3.76, -1.14, 31],
	"the-wishing-well/go-on-ahead": [3.64, -0.19, 35],
	"the-wishing-well/back-for-you": [3.76, 0.47, 30],
	"turn-of-the-tide/set-the-tide": [3.64, 1.42, 36],
	"turn-of-the-tide/slack-water": [3.76, 2.08, 33],
	# Columns 5 and 6: the original islands. Column 6 has room for four more.
	"earlier/first-light": [4.34, -1.94, 31],
	"earlier/long-way-home": [4.46, -1.28, 35],
	"earlier/patient-garden": [4.34, -0.33, 30],
	"earlier/rising-together": [4.46, 0.33, 36],
	"earlier/across-the-blue": [4.34, 1.28, 33],
	"earlier/lantern-crossing": [4.46, 1.94, 38],
	"earlier/two-beats": [5.04, -1.80, 35],
	"earlier/after-you": [5.16, -1.14, 30],
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
