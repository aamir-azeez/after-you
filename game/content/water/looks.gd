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
## Water whose level moves (a tide, a lock's pool) reads deep at every level:
## its floor lies at least this far (m) under its lowest level and is not
## drawn, so neither the floor nor the foot of anything standing in it (a
## stepping log, a pile, a sunk deck) shows as the water rises and falls: the
## water only covers more or less of what stands in it.
const MOVING_DEPTH := CLEAR_TO

## Rings spread from a float (a boat, a raft) within this many metres of open
## water and this close to its level.
const RING_REACH := 0.45
const FLOAT_HEIGHT := 0.2
## A pip spreads rings only in or on the water, judged at its own spot: it
## wades where open water lies under it and its feet stand at most
## PIP_SURFACE above the level (a punt's deck stands 6 cm over the shut sea),
## or it stands on the top of a round thing standing in the water (a stepping
## or sinking stone), its feet within PIP_FOOTING of that top and the top at
## most PIP_RISE above the level (Turn of the Tide's stones stand 24 cm proud
## at half, 70 cm at low). Floors, decks, quays, stairs and bridges never
## count: what stands in the water under them is walls, or piles and posts
## whose tops stand 4 to 12 cm under the walk.
const PIP_SURFACE := 0.04
const PIP_FOOTING := 0.015
const PIP_RISE := 0.30
## Spots closer than this (metres) share one set of rings.
const RING_MERGE := 0.30

## The seabed styles (presentation/kit/seabed.gdshader draws them from the
## spot's place in the plan, never a repeating tile): "ground" and "light"
## mottle the bed, "stones" colour its pebbles, "density" is the share of the
## pebble grids' cells that hold one where the ground is stony, "patchiness"
## how much the wide patches swing that between bare and full, and "ripples"
## soft sand ripples on the bare patches.
const SEABEDS := {
	# Pale sand in soft ripples with a few shells and pebbles (Turn of the Tide's harbour).
	"sand": {"ground": Color("e6d3ab"), "light": Color("f3e6c8"), "density": 0.16, "patchiness": 0.8, "ripples": 1.0,
		"stones": [Color("c9b28a"), Color("bfd2c4"), Color("d8c39c"), Color("c7b9a0")]},
	# A stream bed of round grey and brown pebbles on grit, in drifts with bare silt between.
	"pebbles": {"ground": Color("a29d89"), "light": Color("c4bfaa"), "density": 0.62, "patchiness": 0.7, "ripples": 0.0,
		"stones": [Color("8e8a7c"), Color("b7ae96"), Color("7d7466"), Color("cfc7b0"), Color("9a8f78")]},
	# Dark soft mud with a few darker clods.
	"mud": {"ground": Color("5b5142"), "light": Color("6d6250"), "density": 0.12, "patchiness": 0.9, "ripples": 0.0,
		"stones": [Color("4b4336"), Color("625846")]},
}
## The seabed when the dressing picks none.
const DEFAULT_SEABED := "sand"
