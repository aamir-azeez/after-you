extends SceneTree
## The pip cosmetic catalog (content/cosmetics/, services/cosmetic_catalog.gd):
## every descriptor is valid data, prices come only from tiers, earned items
## are never sold, a Special names a real chapter to clear, the Orchard is
## sold in Fruits with the server's slots, tiers and set, and in this phase
## nothing is released, so only the default look shows.
const Index = preload("res://content/cosmetics/index.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Registry = preload("res://services/chapter_registry.gd")
const OwnLook = preload("res://services/own_look.gd")
const Outfit = preload("res://services/outfit.gd")

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
	_descriptors()
	_prices()
	_rules()
	_phase_one()
	print("COSMETIC CATALOG: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _descriptors() -> void:
	var known: Array = Index.REQUIRED + Index.OPTIONAL.keys()
	var names: Array = load("res://presentation/player_copy.gd").get_script_constant_map().values()
	var id_shape := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	var level_ids: Array[String] = []
	for key: String in Registry.keys(): level_ids.append(key.split("@")[0])
	_check(Index.ids().size() == Index.ITEMS.size() and not Index.ids().is_empty(), "Every descriptor is listed once")
	for file: Script in Index.ITEMS:
		var raw: Dictionary = file.DATA
		var id := str(raw.get("id", ""))
		for field: String in Index.REQUIRED: _check(raw.has(field), "%s names its %s" % [id, field])
		for field: String in raw: _check(field in known, "%s has only known fields, not %s" % [id, field])
		_check(not raw.has("price"), "%s stores no price: its tier does" % id)
		_check(id_shape.search(id) != null, "%s is a lower case id" % id)
		var data := Index.data(id)
		_check(data.slot == "" or data.slot in Index.SLOTS, "%s is worn in a known slot or none yet" % id)
		_check(Index.TIER_PRICES.has(data.tier), "%s has a known tier" % id)
		_check(data.name is String and not str(data.name).is_empty() and data.name in names, "%s's name is a PlayerCopy constant" % id)
		_check(not str(data.name).contains("-") and not str(data.name).contains("—"), "%s's name has no dashes" % id)
		var art := str(data.art)
		_check(art.is_empty() or (art.begins_with("res://presentation/pip_wear/") and ResourceLoader.exists(art)), "%s's art is a pip_wear script that exists" % id)
		if not art.is_empty(): _check(load(art).has_method("wear"), "%s's art has wear()" % id)
		_check(data.released is bool and data.tall is bool and data.wide is bool and data.unlock is String and (data.leaf_lift is float or data.leaf_lift is int), "%s's optional fields have their types" % id)
		_check(data.unlock == "" or data.unlock in level_ids, "%s unlocks after a registered level: %s" % [id, data.unlock])
		if data.tier == Catalog.EARNED:
			_check(data.earn is String and not str(data.earn).is_empty() and data.earn in names and not str(data.earn).contains("-") and not str(data.earn).contains("—") and Catalog.earn(id) == data.earn, "%s (earned) says how it is earned, a PlayerCopy line with no dashes" % id)
		else: _check(str(data.earn).is_empty() and Catalog.earn(id).is_empty(), "%s (sold) has no earn line" % id)
		_check(data.is_read_only(), "%s's descriptor is read only" % id)
	_check(Index.data("nothing").is_empty() and not Catalog.has("nothing"), "An unknown id has no descriptor")
	_check(Index.SLOTS == ["hat", "body", "leaf"], "The slots are the hat, the body and the leaf")

func _prices() -> void:
	_check(Index.TIER_PRICES == {"common": 1000, "uncommon": 5000, "rare": 20000, "epic": 50000, "special": 100000, "earned": 0, "sprig": 10, "fruit_small": 25, "fruit_hat": 50, "fruit_body": 100}, "Tier prices follow the ramp, earned costs nothing because it is never sold, and the Orchard tiers are priced in Fruits")
	_check(Index.TIER_CURRENCY == {"sprig": "fruits", "fruit_small": "fruits", "fruit_hat": "fruits", "fruit_body": "fruits"}, "Only the Orchard tiers are sold in Fruits; every other tier is Pollen")
	for tier: String in Index.TIER_CURRENCY: _check(Index.TIER_PRICES.has(tier), "The Fruit tier %s has a price" % tier)
	for id: String in Catalog.ids():
		var tier := str(Catalog.item(id).tier)
		_check(Catalog.price(id) == int(Index.TIER_PRICES[tier]), "%s costs its tier's price" % id)
		_check(Catalog.sold(id) == (tier != "earned"), "%s is sold exactly when it is not earned" % id)
		if tier == "special": _check(not str(Catalog.item(id).unlock).is_empty(), "%s (Special) opens only after a chapter is cleared" % id)
	_check(Catalog.price("nothing") == 0 and not Catalog.sold("nothing"), "An unknown id costs nothing and is not sold")

func _rules() -> void:
	var expect := {
		"daisy": ["hat", "common"], "seashell": ["hat", "common"], "straw_hat": ["hat", "uncommon"],
		"tide": ["body", "rare"], "lantern": ["hat", "epic"], "lighthouse_lamp": ["hat", "special"],
		"gold_leaf": ["leaf", "earned"], "every_hard": ["leaf", "earned"], "top_ten_ribbon": ["hat", "earned"],
		# The Orchard, as the server's catalogue sells it (FRUITS contract).
		"apple_hood": ["hat", "fruit_hat"], "blueberry_hood": ["hat", "fruit_hat"], "blossom_crown": ["hat", "fruit_hat"], "orchard_skin": ["body", "fruit_body"], "apple_leaf": ["leaf", "fruit_small"],
		"sprig_coral": ["leaf", "sprig"], "sprig_plum": ["leaf", "sprig"], "sprig_sun": ["leaf", "sprig"], "sprig_sky": ["leaf", "sprig"],
	}
	_check(Array(Catalog.ids()) == expect.keys(), "The approved items, in shop order: %s" % [Catalog.ids()])
	for id: String in expect:
		_check(Catalog.slot(id) == expect[id][0] and str(Catalog.item(id).tier) == expect[id][1], "%s is a %s %s" % [id, expect[id][1], expect[id][0]])
	_check(Catalog.item("lighthouse_lamp").unlock == "sleeping-lighthouse" and Catalog.tall("lighthouse_lamp"), "The Lighthouse lamp opens after Sleeping Lighthouse and pulls the view back")
	_check(Catalog.wide("lantern") and not Catalog.wide("daisy") and not Catalog.wide("nothing"), "Only the Lantern, hanging on the far side, pulls the view back further")
	_check(is_equal_approx(Catalog.leaf_lift("straw_hat"), 0.075), "The Straw hat lifts the leaf 7.5 cm through its brim")
	for id: String in Catalog.ids(): _check(not Catalog.art(id).is_empty() and not Catalog.slot(id).is_empty(), "%s has its art and its slot" % id)
	var orchard: Array[String] = []
	for id: String in Catalog.ids():
		if str(Catalog.item(id).set) == "orchard": orchard.append(id)
	_check(orchard == ["apple_hood", "orchard_skin", "apple_leaf"], "The Orchard set is the Apple hood, the Orchard skin and the Apple leaf: %s" % [orchard])
	for id: String in ["blueberry_hood", "blossom_crown", "sprig_coral", "sprig_plum", "sprig_sun", "sprig_sky"]: _check(str(Catalog.item(id).set).is_empty(), "%s is in no set" % id)

func _phase_one() -> void:
	# Phase 1 ships the catalog unreleased: only the default look shows.
	_check(Catalog.released_ids().is_empty(), "Nothing is released yet")
	_check(OwnLook.outfit().is_empty() and OwnLook.color() == Color("f4c38d"), "The player's own pip is the default peach look")
	for id: String in Catalog.ids():
		_check(Outfit.of(id).is_empty(), "%s is not worn by a player's pip while unreleased" % id)
