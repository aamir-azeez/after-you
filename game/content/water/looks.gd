extends RefCounted
## How every body of water looks (presentation/kit/water_look.gd), the owner's
## pick from the water looks board (2026-11-17): soft ripples with a soft foam
## band where the water meets walls, stones and posts and a shade darker as it
## deepens, plus three add-ons: the seabed showing through thin water, rings
## spreading from what floats or stands at the water, and a few glints. Visual
## only: nothing here reaches a simulation, a recording or a checkpoint.
##
## A water block (content/water/<chapter>.gd) switches add-ons off in its
## "look" ({"rings": false}); a body may switch one for itself with the same
## key ({"id": "sea", ..., "floor": false}: open sea that reads deep).
## Anything not named stays on.
## The seabed's look is the dressing's "seabed" pick (a look slot in
## content/dressing/prop_styles.gd, so a theme picks it for its levels).

## Every add-on and whether it is on when a block and its body say nothing.
const SWITCHES := {"floor": true, "rings": true, "sparkles": true}

## How far each body's colour leans toward the soft sea green, so every water
## reads light and pastel while deeper water still reads darker.
const PASTEL := 0.55
const PASTEL_TINT := Color(0.50, 0.78, 0.80)
## Water this deep or more (metres above the seabed) shows only its tint; from
## CLEAR_FROM and shallower it shows the floor most.
const CLEAR_FROM := 0.15
const CLEAR_TO := 1.30
## How see-through the water is at its clearest, and at its deepest at least.
const CLEAR_ALPHA := 0.24
const DEEP_ALPHA := 0.90

## Rings spread from a thing at the water within this many metres of open
## water: a pip standing this far above or below its level, a float (a boat, a
## raft) this close to it.
const RING_REACH := 0.45
const RING_HEIGHT := 0.75
const FLOAT_HEIGHT := 0.2
## Spots closer than this (metres) share one set of rings.
const RING_MERGE := 0.30

## The seabed styles. A tile of the floor spans TILE_M metres: "ground" and
## "light" mottle it, "lines" (if any) draw a tiled edge, and "pebbles" lie on
## it (count of them and their colours).
const TILE_M := 0.64
const SEABEDS := {
	# Pale sandy tiles (Turn of the Tide's harbour).
	"sand": {"ground": Color("ead9b4"), "light": Color("f3e6c8"), "lines": Color("d4bd92"),
		"pebbles": 4, "pebble_colors": [Color("c9b28a"), Color("bfd2c4"), Color("d8c39c"), Color("c7b9a0")]},
	# A stream bed of round grey and brown pebbles on grit, no tiles.
	"pebbles": {"ground": Color("a9a491"), "light": Color("c4bfaa"),
		"pebbles": 18, "pebble_colors": [Color("8e8a7c"), Color("b7ae96"), Color("7d7466"), Color("cfc7b0"), Color("9a8f78")]},
	# Dark soft mud with a few darker clods.
	"mud": {"ground": Color("5b5142"), "light": Color("6d6250"),
		"pebbles": 5, "pebble_colors": [Color("4b4336"), Color("625846")]},
}
## The seabed when the dressing picks none.
const DEFAULT_SEABED := "sand"
