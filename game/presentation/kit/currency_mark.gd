extends RefCounted
## The mark for a currency, and the one way a surface gets one: every chip,
## card, sheet and line that shows an amount of Pollen or Fruits asks here,
## so a currency's mark is chosen in one place and drawn in its own
## (kit/pollen_mark.gd, kit/fruit_mark.gd).
##
## Currencies are named as the server names them ("pollen", "fruits"). Any
## other name, or none, is Pollen: the same rule as the cosmetics' tiers
## (content/cosmetics/index.gd TIER_CURRENCY), where an absent currency is Pollen.
const PollenMark = preload("res://presentation/kit/pollen_mark.gd")
const FruitMark = preload("res://presentation/kit/fruit_mark.gd")

const POLLEN := "pollen"
const FRUITS := "fruits"

## A mark for `currency` sized for an amount set at `font_size`, to sit in the same row.
static func beside(currency: String, font_size: int) -> Control:
	return FruitMark.beside(font_size) if currency == FRUITS else PollenMark.beside(font_size)

## A mark for `currency`, `side` pixels square.
static func make(currency: String, side: float) -> Control:
	return FruitMark.make(side) if currency == FRUITS else PollenMark.make(side)
