extends RefCounted
## The player's reaction slots, as the Wardrobe's Reactions chip shows and
## edits them (presentation/wardrobe_reactions.gd), and the faces it lists.
## Pure rules over the kept wardrobe (services/wardrobe.gd view): no saves, no
## server, no nodes. The server's rules are backend src/pollen/reaction-loadout.ts:
## SLOT_COUNT places, the first FREE_SLOTS everyone's, one more open per
## reaction slot item owned (UNLOCKS, bought in this order); a face in one
## place at most; the heart stays outside the slots. The slots exist only while
## the server keeps them (the view's "reactions": FACE_SINGLES on).
const ReactionCatalog = preload("res://services/reaction_catalog.gd")
const FacePacks = preload("res://services/face_packs.gd")
const Catalog = preload("res://services/cosmetic_catalog.gd")
const Wardrobe = preload("res://services/wardrobe.gd")

const SLOT_COUNT := 6
const FREE_SLOTS := 4
## The reaction slot items, in the order they open places 5 and 6.
const UNLOCKS: Array[String] = ["reaction_slot_5", "reaction_slot_6"]
## The tier the everyday faces list under (no price, everyone's).
const FREE_TIER := "free"

## Whether the server keeps slots for this player (the Reactions chip shows).
static func kept(view: Dictionary) -> bool:
	return view.get("reactions") is Array

## How many places are open (FREE_SLOTS to SLOT_COUNT).
static func open_count(view: Dictionary) -> int:
	return clampi(int(view.get("reaction_slots", FREE_SLOTS)), FREE_SLOTS, SLOT_COUNT)

## The next reaction slot item to buy, or "" once every place is open.
static func next_unlock(view: Dictionary) -> String:
	var owned: Array = view.get("items", [])
	for id: String in UNLOCKS:
		if not id in owned: return id
	return ""

## `slots` with `face` put at `index`: the face that sat there goes to the
## place `face` came from (a swap), or out of the slots when `face` was in none.
static func placed(slots: Array, face: String, index: int) -> Array:
	var result := slots.duplicate()
	if index < 0 or index >= result.size(): return result
	var from := result.find(face)
	if from == index: return result
	if from >= 0: result[from] = result[index]
	result[index] = face
	return result

## Every face the Reactions chip lists, in collection order (services/
## reaction_catalog.gd collection): the everyday faces, then each single and
## pack face the player owns or the server sells now. Each entry: {id, name,
## tier, slot ("reaction"), price, currency, owned, sold, worn (false), locked
## (false), in_slot (its place in `slots`, or -1), moving, face (true)}.
## `selling`: the shop shows, so prices do.
static func faces(view: Dictionary, slots: Array, selling: bool) -> Array:
	var owned := FacePacks.owned_faces(view)
	var offered: Array = view.get("offered", [])
	var result: Array = []
	for face: String in ReactionCatalog.collection():
		var free := not ReactionCatalog.is_paid_face(face)
		var mine := free or face in owned
		var sale: Dictionary = Wardrobe.sale(view, face) if selling and not free else {}
		var sold := not mine and not sale.is_empty() and face in offered
		if not mine and not sold: continue
		result.append({"id": face, "name": ReactionCatalog.face_name(face), "tier": FREE_TIER if free else Catalog.tier(face), "slot": "reaction",
			"price": int(sale.get("price", 0)), "currency": "pollen", "owned": mine, "sold": sold, "worn": false, "locked": false, "unlock_name": "", "earn": "",
			"in_slot": slots.find(face), "moving": Catalog.moving(face), "face": true})
	return result

## The next reaction slot as a Wardrobe entry (bought like an item), or {} when
## every place is open or it is not sold now.
static func unlock_entry(view: Dictionary, selling: bool) -> Dictionary:
	var id := next_unlock(view)
	if id.is_empty(): return {}
	var sale: Dictionary = Wardrobe.sale(view, id) if selling else {}
	var sold: bool = not sale.is_empty() and id in view.get("offered", [])
	return {"id": id, "name": Catalog.display_name(id), "tier": Catalog.tier(id), "slot": "reaction_slot", "price": int(sale.get("price", 0)), "currency": "pollen",
		"owned": false, "sold": sold, "worn": false, "locked": false, "unlock_name": "", "earn": "", "unlock": true}
