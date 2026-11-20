extends RefCounted
## How anything that floats sits on its water: the moored rowboats, a float
## nobody carries, the keepsake's toy boat and every float to come. Its
## waterline sits on the outside of its hull, `draft` above its keel, so it
## shows the same small freeboard at every water level, and the water never
## reaches its inside floor, at the bottom of its bob too, so the water can
## never show inside it.
##
## Each float's builder lays its keel at its node's origin (y 0) and takes its
## numbers here rather than setting its height by hand (the dressing's "boat"
## props and the Lighthouse keepsake's pond boat still stand where placed).
## The heave moves the freeboard by `bob` either way against the flat water;
## the floor stays dry through it. Per kind, metres above the keel:
##   draft: where still water meets the hull
##   bob:   how far it heaves either way (none under Reduce motion), at
##          `rate` radians a second
##   floor: the top of what fills the inside (floorboards, a raft's deck): it
##          stays at least MARGIN over the water through the whole bob
##   top:   the rim (a rowboat's gunwale; a raft's deck)
## A Blender float model (agent-docs/MODELS.md) meets the same numbers: its
## keel at its origin and its inside floor at least `draft + bob + MARGIN` up.
const MARGIN := 0.01
## A float whose style has no kind of its own (a parcel, a pinned style) sits
## low and flat, as the code-built log raft did.
const DEFAULT_KIND := "flat"
const KINDS := {
	"flat": {"draft": 0.03, "bob": 0.015, "rate": 2.2, "floor": 0.06, "top": 0.06},
	"rowboat": {"draft": 0.035, "bob": 0.015, "rate": 1.4, "floor": 0.065, "top": 0.15},
	"raft": {"draft": 0.075, "bob": 0.015, "rate": 2.2, "floor": 0.134, "top": 0.169},
	# A solid painted hull: its floor is its own top.
	"toy_boat": {"draft": 0.04, "bob": 0.0, "rate": 0.0, "floor": 0.103, "top": 0.115},
}

static func kind(name: String) -> Dictionary:
	return KINDS.get(name, KINDS[DEFAULT_KIND])

## Where a float's keel stands on water whose surface is at `level`: its
## draft under it, heaved by its bob at `clock` seconds from `phase` (radians)
## unless `still` (Reduce motion, a held frame).
static func keel(name: String, level: float, clock: float = 0.0, phase: float = 0.0, still: bool = true) -> float:
	var spec := kind(name)
	var heave := 0.0 if still else sin(clock * float(spec.rate) + phase) * float(spec.bob)
	return level - float(spec.draft) + heave

## The freeboard at the bottom of the bob: rim over the water.
static func least_freeboard(name: String) -> float:
	var spec := kind(name)
	return float(spec.top) - float(spec.draft) - float(spec.bob)

## Whether a kind keeps the rule: its keel wet at the top of the bob, its
## inside floor MARGIN over the water at the bottom, its rim at or over the floor.
static func keeps_rule(name: String) -> bool:
	var spec := kind(name)
	return float(spec.draft) - float(spec.bob) > 0.0 and float(spec.floor) >= float(spec.draft) + float(spec.bob) + MARGIN and float(spec.top) >= float(spec.floor)
