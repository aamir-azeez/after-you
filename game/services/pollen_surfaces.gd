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
## - bundles_visible: the Pollen store and its bundles, the + on the balance
##   chip and the short card's "Get Pollen" link. Only a Google Play build or an
##   App Store build with its store key sells them: real Pollen comes only from
##   real store purchases, so the Test Store build and a free iOS build never
##   show them. The server decides per store (services/relay_online_session.gd
##   bundles_supported).
## - full_journey_visible: Pollen words that name Full Journey. The monthly
##   grant card, the Full Journey boost lines after a turn and the odds note's
##   paid chapter sentence.
## - fruits_visible: every Fruit surface (the Fruit amount on the chip, the
##   Orchard, the Fruits page with its achievements, Sunshine and converting,
##   Fruit lines on results and in the monthly card). Fruits buy only, so a build
##   that sells nothing shows none, and the server decides per player
##   (services/fruit_wallet.gd enabled: capabilities pollen_fruits_version).
## - fruit_packs_visible: the Fruit packs, the Fruits tab of the store and the
##   Fruit short card's "Get Fruits": a build that sells bundles, Fruits on, and
##   the server selling Fruit packs in this phone's store (fruit_wallet.gd packs).
##   Each pack shows only while RevenueCat's "fruits" offering has its product
##   (services/pollen_bundles.gd packages with "fruits").
##
## A build that sells nothing (Purchases.paid_content_hidden: iOS without a
## store it can use) earns, holds a balance and wears what it owns, but shows no
## shop, no price and no Full Journey. Android, desktop and an iOS build with a
## store show every part. The server still decides whether each part is on for
## the player; on iPhone, Main also hides the shop and Full Journey while the
## server says it takes no App Store purchases (services/store_support.gd).
const Purchases = preload("res://services/purchases.gd")
const PlatformSupport = preload("res://services/platform_support.gd")
const StoreSupport = preload("res://services/store_support.gd")
const PATH := "res://services/pollen_surfaces.gd"

var _sells := true
var _bundles := false
## () -> bool: true while the server hides this build's paid parts (an iOS store build: StoreSupport.hides_paid).
var _held := Callable()

func _init(build_sells: bool = true, build_bundles: bool = false) -> void:
	_sells = build_sells
	_bundles = build_sells and build_bundles

## The surfaces for a build `configuration` (app_config.json).
static func for_configuration(configuration: Dictionary) -> RefCounted:
	var sells := not Purchases.paid_content_hidden(configuration)
	var mode := str(configuration.get("purchase_mode", ""))
	var store := mode in ["google_play", "app_store"] and Purchases.store_enabled(configuration) and not str(configuration.get("revenuecat_public_key", "")).is_empty()
	var surfaces: RefCounted = load(PATH).new(sells, store)
	if sells and PlatformSupport.is_ios(): surfaces._held = func() -> bool: return StoreSupport.shared().hides_paid()
	return surfaces

func _selling() -> bool:
	return _sells and not (_held.is_valid() and _held.call())

## Read once: the build's configuration never changes while the app runs.
static var _shared: RefCounted = null

static func shared() -> RefCounted:
	if _shared == null: _shared = for_configuration(Purchases.read_configuration())
	return _shared

## Tests pick a build: true sells, false sells nothing, null reads the configuration again;
## `build_bundles` also sells Pollen bundles.
static func set_shared_for_tests(build_sells: Variant, build_bundles: bool = false) -> void:
	_shared = null if build_sells == null else load(PATH).new(bool(build_sells), build_bundles)

func earning_visible() -> bool:
	return true

func wallet_visible() -> bool:
	return true

func wardrobe_visible() -> bool:
	return true

func shop_visible() -> bool:
	return _selling()

func bundles_visible() -> bool:
	return _bundles and _selling()

## The one "the Pollen store can sell now" gate (the store, the chip's plus and
## the short card's bundle): this build sells bundles and `store`
## (services/wardrobe.gd) says the server has them on for the player of `scope`
## (never without the shop).
func store_sells(store: RefCounted, scope: Dictionary) -> bool:
	return bundles_visible() and store != null and not scope.is_empty() and store.bundles(str(scope.server), str(scope.owner))

func full_journey_visible() -> bool:
	return _selling()

## The one "Fruits show" gate: this build sells and `fruits` (services/fruit_wallet.gd)
## says the server has Fruits on for the player of `scope`. Every Fruit surface hides otherwise.
func fruits_visible(fruits: RefCounted, scope: Dictionary) -> bool:
	return shop_visible() and fruits != null and not scope.is_empty() and fruits.enabled(str(scope.server), str(scope.owner))

## The one "Fruit packs sell now" gate: this build sells bundles and `fruits` says the
## server sells Fruit packs in this phone's store for the player of `scope` (never without Fruits).
func fruit_packs_visible(fruits: RefCounted, scope: Dictionary) -> bool:
	return bundles_visible() and fruits_visible(fruits, scope) and fruits.packs(str(scope.server), str(scope.owner))
