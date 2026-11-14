extends RefCounted
## Piece styles: how a puzzle piece looks, apart from what it does. A lever, a
## selector, a pad and a goal behave the same in every chapter (the rules
## engines and core/blocks/stage_blocks.gd); only their look changes, and the
## look is picked here, never by a world keyed on piece ids.
##
## A piece's style, first found wins:
##   1. a pin: the chapter descriptor's "piece_styles" {piece id: style}
##      (content/chapters/index.gd), filled from blocks that name a "style"
##      (content/blocks/defaults.gd)
##   2. the dressing's pick for the slot: its own field ("goal": "crest"),
##      else its "picks", else its theme's picks, which content/dressing/
##      catalog.gd resolve() writes into that field like every look slot's
##   3. DEFAULT_PICKS (content/dressing/prop_styles.gd): the plain look
## A name the slot does not offer (prop_styles.gd SLOTS) is passed over, so a
## lever pinned "valve" falls back to the next step instead of breaking.
##
## Pure data: static, no state, nothing from presentation. The worlds
## (presentation/cooperative_world.gd) and the sound map
## (services/chapter_sound_map.gd) both ask here, so a piece looks and sounds
## the same style. Each style is built by one kit under presentation/kit/pieces/.

const Styles = preload("res://content/dressing/prop_styles.gd")
## The descriptor field holding the pins.
const PINS := "piece_styles"
## The piece slots, each a LOOK_SLOTS entry of prop_styles.gd.
const SLOTS := ["lever", "selector", "pad", "goal"]

## The style of piece `id` in slot `slot` for a chapter `descriptor` (or {})
## and its resolved `dressing` (DressingCatalog.for_key, or {}).
static func style(slot: String, id: String, descriptor: Dictionary, dressing: Dictionary) -> String:
	var pin := str(descriptor.get(PINS, {}).get(id, ""))
	if Styles.has_style(slot, pin): return pin
	var pick := str(dressing.get(slot, ""))
	if Styles.has_style(slot, pick): return pick
	return str(Styles.DEFAULT_PICKS[slot])

## The slot a placed control fills: a selector's, else a lever's.
static func control_slot(control: Dictionary) -> String:
	return "selector" if str(control.get("kind", "")) == "selector" else "lever"

## Pins that name no style of any piece slot, as messages; empty when none.
static func problems(descriptor: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var pins: Dictionary = descriptor.get(PINS, {})
	for id: String in pins:
		if not SLOTS.any(func(slot: String) -> bool: return Styles.has_style(slot, str(pins[id]))):
			found.append("No piece style %s for %s" % [pins[id], id])
	return found
