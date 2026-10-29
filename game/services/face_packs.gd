extends RefCounted
## Reaction packs on this phone (services/reaction_catalog.gd PACKS): which
## pack faces the player may pick now, and what the Wardrobe's Faces tab lists.
## The server owns everything here: what is owned and offered comes from the
## wardrobe it last sent (services/wardrobe.gd), and it refuses a pack face
## whose pack is not owned (backend src/v2/face-packs.ts). Nothing here grants
## or prices anything.
##
## A pack's faces can be picked when all of these hold:
## - this build shows the shop (services/pollen_surfaces.gd shop_visible), so
##   an iPhone build without Apple purchases shows no pack;
## - the player owns the pack;
## - the face goes nowhere (a solo pick kept on this phone), or the server
##   says it takes pack faces (relay_online_session.gd face_packs_supported):
##   an older server refuses a turn whose face it does not know.
## A friend's pack face is drawn on every phone all the same.
const Catalog = preload("res://services/reaction_catalog.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Typed = preload("res://services/typed_values.gd")

## () -> {"server": bool, "view": Dictionary}: whether the signed-in player's
## server takes pack faces, and their wardrobe (services/wardrobe.gd view).
## Main sets it; until then no pack can be picked.
static var source: Callable

## The packs whose faces the player may pick now, in PACKS order. `local`: the
## pick stays on this phone, so the server's support does not matter.
static func pickable_packs(local: bool = false) -> Array:
	if not source.is_valid(): return []
	var state: Variant = source.call()
	if not state is Dictionary: return []
	return packs_for(local or Typed.equal(state.get("server"), true), state.get("view"), PollenSurfaces.shared())

## pickable_packs from its parts (tests call it directly).
static func packs_for(server_takes_packs: bool, view: Variant, surfaces: RefCounted) -> Array:
	if not server_takes_packs or surfaces == null or not surfaces.shop_visible() or not view is Dictionary: return []
	var owned: Variant = view.get("packs")
	if not owned is Array: return []
	return Catalog.PACKS.keys().filter(func(pack: String) -> bool: return pack in owned)

## Whether `face` may be picked now: an everyday face always, a pack face while
## its pack is pickable.
static func can_pick(face: String, local: bool = false) -> bool:
	if not Catalog.is_pack_face(face): return Catalog.is_face(face)
	return Catalog.pack_of(face) in pickable_packs(local)

# --- The Wardrobe's Faces tab (presentation/wardrobe_page.gd calls these) -----

## Whether the Faces tab shows: this build shows the shop and the server
## offers a pack this build can draw, or the player owns one.
static func faces_tab_visible(view: Variant, surfaces: RefCounted) -> bool:
	return surfaces != null and surfaces.shop_visible() and not pack_rows(view).is_empty()

## The Faces tab's pack rows, in PACKS order: each pack the server offers or
## the player owns, as {"id", "name", "faces": [face ids], "owned": bool,
## "price": Pollen (the server's pack_price), "offered": bool}. The free
## faces row (Catalog.FACES) is the page's own. Buying is
## services/wardrobe_client.gd buy("pack", id, price).
static func pack_rows(view: Variant) -> Array:
	if not view is Dictionary: return []
	var owned: Variant = view.get("packs")
	var offered: Variant = view.get("offered_packs")
	var rows: Array = []
	for pack: String in Catalog.PACKS:
		var mine: bool = owned is Array and pack in owned
		var sold: bool = offered is Array and pack in offered
		if not mine and not sold: continue
		rows.append({"id": pack, "name": Catalog.pack_name(pack), "faces": (Catalog.PACKS[pack] as Array).duplicate(),
			"owned": mine, "offered": sold, "price": Typed.as_int(view.get("pack_price"), 0)})
	return rows
