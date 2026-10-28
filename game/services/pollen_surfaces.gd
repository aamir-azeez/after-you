extends RefCounted
## Which Pollen parts this build shows. Every Pollen screen asks one question
## here instead of the paid content rule, so the split between the two builds
## lives in one place:
## - earning_visible: the Pollen line after a turn and the bloom odds note.
## - wallet_visible: the balance (the Wardrobe header).
## - wardrobe_visible: the Wardrobe, for wearing what the player owns: earned
##   items and item bloom drops.
## - shop_visible: anything sold or priced. Items on sale, the shelf of the
##   week, Buy and its cards, prices in Pollen or money, bundles, and the name
##   change price.
## - full_journey_visible: Pollen words that name Full Journey. The monthly
##   grant card, the Full Journey boost lines after a turn and the odds note's
##   paid chapter sentence.
##
## A build that sells nothing (Purchases.paid_content_hidden: iOS without a
## store it can use) earns, holds a balance and wears what it owns, but shows no
## shop, no price and no Full Journey until it sells through Apple. Android,
## desktop and an iOS build with a store show every part. The server still
## decides whether each part is on for the player.
const Purchases = preload("res://services/purchases.gd")
const PATH := "res://services/pollen_surfaces.gd"

var _sells := true

func _init(build_sells: bool = true) -> void:
	_sells = build_sells

## The surfaces for a build `configuration` (app_config.json).
static func for_configuration(configuration: Dictionary) -> RefCounted:
	return load(PATH).new(not Purchases.paid_content_hidden(configuration))

## Read once: the build's configuration never changes while the app runs.
static var _shared: RefCounted = null

static func shared() -> RefCounted:
	if _shared == null: _shared = for_configuration(Purchases.read_configuration())
	return _shared

## Tests pick a build: true sells, false sells nothing, null reads the configuration again.
static func set_shared_for_tests(build_sells: Variant) -> void:
	_shared = null if build_sells == null else load(PATH).new(bool(build_sells))

func earning_visible() -> bool:
	return true

func wallet_visible() -> bool:
	return true

func wardrobe_visible() -> bool:
	return true

func shop_visible() -> bool:
	return _sells

func full_journey_visible() -> bool:
	return _sells
