extends SceneTree
## Outfit rules (services/outfit.gd): one item per known slot, anything else
## dropped, and a digest that covers every slot and ignores entry order.
const Outfit = preload("res://services/outfit.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")

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
	_cleaning()
	_digest()
	_combinations()
	_facts()
	print("OUTFIT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _cleaning() -> void:
	_check(not Outfit.show_unreleased, "The game never shows unreleased items")
	_check(Outfit.from(null).is_empty() and Outfit.from("daisy").is_empty() and Outfit.from([]).is_empty(), "Anything not a Dictionary is the default look")
	_check(Outfit.from({}).is_empty() and Outfit.is_empty(Outfit.EMPTY), "{} is the default look")
	_check(Outfit.from({"hat": "daisy"}).is_empty(), "An unreleased item is dropped for a player's pip")
	_check(Outfit.from({"hat": "daisy"}, true) == {"hat": "daisy"}, "and kept when asked (art tools, tests)")
	_check(Outfit.from({"hat": "nothing", "body": "tide"}, true) == {"body": "tide"}, "An unknown id is dropped, the rest kept")
	_check(Outfit.from({"badge": "daisy", "hat": "lantern"}, true) == {"hat": "lantern"}, "A slot it does not know is dropped")
	_check(Outfit.from({"body": "daisy", "leaf": "tide", "hat": "gold_leaf"}, true).is_empty(), "An item in another item's slot is dropped")
	_check(Outfit.from({"hat": 3, "body": ["tide"], "leaf": &"gold_leaf"}, true) == {"leaf": "gold_leaf"}, "Non text ids are dropped; a StringName reads as text")
	_check(Outfit.of("tide", true) == {"body": "tide"} and Outfit.of("nothing", true).is_empty(), "of() puts one item in its own slot")
	var source := {"hat": "daisy"}
	var clean := Outfit.from(source, true)
	clean["hat"] = "lantern"
	_check(source.hat == "daisy", "from() makes a new Dictionary")

func _digest() -> void:
	var a := Outfit.from({"hat": "daisy", "body": "tide", "leaf": "gold_leaf"}, true)
	var b := Outfit.from({"leaf": "gold_leaf", "body": "tide", "hat": "daisy"}, true)
	_check(Outfit.digest(a) == Outfit.digest(b), "Entry order never changes the digest")
	_check(Outfit.digest({}) == "hat=;body=;leaf=", "The digest names every slot, empty ones too: " + Outfit.digest({}))
	_check(Outfit.digest({"hat": "tide"}) != Outfit.digest({"body": "tide"}), "The same id in two slots gives two digests")
	_check(Outfit.items(a) == ["daisy", "tide", "gold_leaf"], "Items come in slot order")

## Every combination of the three slots (each slot empty or any of its items).
func _combinations() -> void:
	var by_slot: Dictionary = {}
	for slot: String in Catalog.slots(): by_slot[slot] = [""]
	for id: String in Catalog.ids():
		var slot := Catalog.slot(id)
		if not slot.is_empty(): by_slot[slot].append(id)
	var digests: Dictionary = {}
	var count := 0
	var all_ok := true
	for hat: String in by_slot.hat:
		for body: String in by_slot.body:
			for leaf: String in by_slot.leaf:
				var raw := {}
				if not hat.is_empty(): raw.hat = hat
				if not body.is_empty(): raw.body = body
				if not leaf.is_empty(): raw.leaf = leaf
				var clean := Outfit.from(raw, true)
				all_ok = all_ok and clean == raw and Outfit.items(clean).size() == raw.size()
				digests[Outfit.digest(clean)] = true
				count += 1
	_check(count == by_slot.hat.size() * by_slot.body.size() * by_slot.leaf.size() and count >= 36, "Every combination is tried: %d" % count)
	_check(all_ok, "Every combination keeps one item in each filled slot")
	_check(digests.size() == count, "Every combination has its own digest")

func _facts() -> void:
	_check(Outfit.tall(Outfit.of("lighthouse_lamp", true)) and not Outfit.tall(Outfit.of("daisy", true)) and not Outfit.tall({}), "Only a tall item pulls the view back")
	_check(is_equal_approx(Outfit.leaf_lift(Outfit.from({"hat": "straw_hat", "leaf": "gold_leaf"}, true)), 0.075) and Outfit.leaf_lift({}) == 0.0, "The leaf lifts for the Straw hat, whatever leaf is worn")
