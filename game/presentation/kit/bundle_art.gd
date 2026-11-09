extends TextureRect
## The packs' art, and the one path to it: every store card, confirm and
## receipt card, short-of card and purchase row that shows a pack gets its
## picture here, by the pack's key (pollen_bundles.json). The pictures are
## the game's own renders (the world kit's timber, grass and leaf, the
## carried seed in the Fruit's tint, Home's day light), as the owner's
## Pollen and Fruits store boards draw them (Fruits boards 3 and 9): the
## Pollen packs are golden powder and the Fruit packs ripe Fruits.
##
## Each picture is a PNG in assets/store/, scaled to the largest size a store
## board draws it at, with mipmaps for the smaller cards. It is loaded on
## demand through the resource cache and drawn keeping its shape, centred in
## the art's box. The art takes no input and never redraws by itself.
const SCRIPT_PATH := "res://presentation/kit/bundle_art.gd"
const DIR := "res://assets/store/"

## Each pack key's picture. The keys never change once sold; two Pollen packs
## show other names than their keys (the jar is shown as the Basket and the
## basket as the Wheelbarrow), so their pictures follow the names.
const PICTURES := {
	"pinch": "pollen-pinch.png",
	"pouch": "pollen-pouch.png",
	"jar": "pollen-basket.png",
	"basket": "pollen-wheelbarrow.png",
	"handful": "pack-handful.png",
	"bowl": "pack-bowl.png",
	"crate": "pack-crate.png",
	"barrel": "pack-barrel.png",
	"pouch_pair": "pollen-pouch-pair.png",
	"bowl_pair": "pack-bowl-pair.png",
}
## The first pack card's pair of each currency: the pack it suggests, twice
## (its first purchase pays it again).
const FIRST_PACK := {"pollen": "pouch_pair", "fruits": "bowl_pair"}

var bundle := ""

## The art for pack `bundle_id` in a `side` pixels square box.
func _init(bundle_id: String = "pinch", side: float = 96.0) -> void:
	bundle = bundle_id
	name = "BundleArt"
	texture = picture(bundle_id)
	custom_minimum_size = Vector2(side, side)
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER

## The art for `bundle_id` in a box of its own shape (a wide pair).
static func boxed(bundle_id: String, box: Vector2) -> Control:
	var art: Control = load(SCRIPT_PATH).new(bundle_id, 0.0)
	art.custom_minimum_size = box
	return art

## The first pack card's pair for `currency` ("pollen" or "fruits"; any other is Pollen).
static func first_pack(currency: String) -> String:
	return str(FIRST_PACK.get(currency, FIRST_PACK.pollen))

## The art faded to `alpha` (a refunded purchase). One picture, so it fades whole.
static func faded(bundle_id: String, side: float, alpha: float) -> Control:
	var art: Control = load(SCRIPT_PATH).new(bundle_id, side)
	art.self_modulate.a = alpha
	return art

## The picture's path for `bundle_id`, or "" for a key with no picture.
static func path(bundle_id: String) -> String:
	return DIR + str(PICTURES[bundle_id]) if PICTURES.has(bundle_id) else ""

## The picture for `bundle_id`, or null for a key with no picture (the art
## then draws nothing).
static func picture(bundle_id: String) -> Texture2D:
	var found := path(bundle_id)
	return load(found) as Texture2D if not found.is_empty() else null
