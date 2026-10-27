extends SceneTree
## The cosmetic manifest: the slots, the tier prices and one row per item with
## the facts the server must agree on, written from content/cosmetics/ into
## tests/fixtures/golden/cosmetic_manifest.json. The server's catalog is to be
## checked against the same file once it exists, so an item whose game and
## server facts drift apart fails CI instead of being sold at the wrong price.
## Regenerate like any golden (tests/golden_support.gd) when an item is added
## or one of these facts changes on purpose.
const Golden = preload("res://tests/golden_support.gd")
const Index = preload("res://content/cosmetics/index.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const GOLDEN := "cosmetic_manifest.json"

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
	return value

func _run() -> void:
	var items: Dictionary = {}
	for id: String in Catalog.ids():
		var data := Index.data(id)
		items[id] = {
			"id": id,
			"slot": Catalog.slot(id),
			"tier": str(data.tier),
			"price": Catalog.price(id),
			"sold": Catalog.sold(id),
			"released": Catalog.released(id),
			"unlock": str(data.unlock),
			"set": str(data.set),
		}
	var result := Golden.check(GOLDEN, {"ids": Catalog.ids(), "slots": Catalog.slots(), "tier_prices": Index.TIER_PRICES, "items": items})
	for message: String in result.messages:
		push_error(message)
	_check(result.ok, "Cosmetic manifest matches golden " + GOLDEN)
	print("COSMETIC MANIFEST: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
