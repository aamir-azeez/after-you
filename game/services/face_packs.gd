extends RefCounted
## Faces beyond the everyday ones on this phone: which pack faces (services/
## reaction_catalog.gd PACKS) and single faces the player may pick now, and the
## reaction slots every faces card shows (the end card's, the in-run pill's
## and Home's, presentation/end_reactions.gd FacesCard).
## The server owns everything here: what is owned, offered and slotted comes
## from the wardrobe it last sent (services/wardrobe.gd), and it refuses a face
## the sender does not own (backend src/v2/face-packs.ts). Nothing here grants
## or prices anything.
##
## One source for every screen: the signed-in player's wardrobe as the shared
## store keeps it (Wardrobe.active_view and active_slots), which outlives Main,
## so a solo chapter (a scene of its own) reads the same slots as Home and a
## room. The server's face version comes from its capabilities read
## (note_version, RelayOnlineSession.load_capabilities).
##
## While the wardrobe keeps reaction slots (its `reactions`, sent only while
## the server serves every face to this app: FACE_SINGLES, face version 2),
## every card shows the player's open slots in their order (slots()) and a
## face is picked as owned (the wardrobe's `faces`: bought alone or in a pack),
## with or without the shop. The wardrobe's own answer decides it, never a
## capabilities read that may be older than it.
##
## Before that (no slots kept), a pack's faces can be picked when all of these hold:
## - this build shows the shop (services/pollen_surfaces.gd shop_visible), so
##   an iPhone build without Apple purchases shows no pack;
## - the player owns the pack;
## - the face goes nowhere (a solo pick kept on this phone), or the server
##   says it takes pack faces (face version 1 or more): an older server
##   refuses a turn whose face it does not know.
## A friend's face is drawn on every phone all the same.
const Catalog = preload("res://services/reaction_catalog.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Typed = preload("res://services/typed_values.gd")
const Wardrobe = preload("res://services/wardrobe.gd")
const ReactionSlots = preload("res://services/reaction_slots.gd")

## Tests only: () -> {"version": int, "view": Dictionary, "slots": Array} in
## place of the shared stores. An older test source's {"server": bool} reads as
## version 1 or 0.
static var source: Callable
## Scope key (Wardrobe.scope_key) -> the face version its server last said.
static var _versions: Dictionary = {}

## The face version the server serves this phone (0, 1 or 2), from its
## capabilities read; forgotten for a scope whose read failed.
static func note_version(server: String, owner: String, version: int) -> void:
	_versions[Wardrobe.scope_key(server, owner)] = clampi(version, 0, 2)

## The packs whose faces the player may pick now, in PACKS order. `local`: the
## pick stays on this phone, so the server's support does not matter.
static func pickable_packs(local: bool = false) -> Array:
	var state := _state()
	if state.is_empty(): return []
	return packs_for(local or version_of(state) >= 1, state.get("view"), PollenSurfaces.shared())

static func _state() -> Dictionary:
	if source.is_valid():
		var given: Variant = source.call()
		return given if given is Dictionary else {}
	var store := Wardrobe.shared()
	var key: String = store.active_key()
	if key.is_empty(): return {}
	return {"version": int(_versions.get(key, 0)), "view": store.active_view(), "slots": store.active_slots()}

## The face version a source state says (0, 1 or 2).
static func version_of(state: Dictionary) -> int:
	if state.has("version"): return clampi(Typed.as_int(state.get("version"), 0), 0, 2)
	return 1 if Typed.equal(state.get("server"), true) else 0

## The reaction faces the player owns (services/reaction_slots.gd owned_faces).
static func owned_faces(view: Variant) -> Array:
	return ReactionSlots.owned_faces(view)

## The faces card's places: the player's open reaction slots in order (4, 5 or
## 6), each its face, or "" for an empty place or a face the player may not
## pick now; [] while the wardrobe keeps no slots, so the card shows the free
## faces and pack tabs as before. `local` is kept for callers; the wardrobe's
## own answer already says the server takes every face.
static func slots(local: bool = false) -> Array:
	var state := _state()
	var view: Variant = state.get("view")
	var shown: Variant = state.get("slots")
	if not view is Dictionary or not shown is Array: return []
	return ReactionSlots.open_places(view, shown).map(func(face: Variant) -> String: return str(face) if face is String and can_pick(str(face), local) else "")

## pickable_packs from its parts (tests call it directly).
static func packs_for(server_takes_packs: bool, view: Variant, surfaces: RefCounted) -> Array:
	if not server_takes_packs or surfaces == null or not surfaces.shop_visible() or not view is Dictionary: return []
	var owned: Variant = view.get("packs")
	if not owned is Array: return []
	return Catalog.PACKS.keys().filter(func(pack: String) -> bool: return pack in owned)

## Whether `face` may be picked now: an everyday face always; a single or pack
## face while the wardrobe lists it owned (it lists `faces` only while the
## server takes every face), or a pack face while its pack is pickable.
static func can_pick(face: String, local: bool = false) -> bool:
	if not Catalog.is_paid_face(face): return Catalog.is_face(face)
	var view: Variant = _state().get("view")
	if view is Dictionary and view.get("faces") is Array and ReactionSlots.kept(view) and face in view.faces: return true
	return Catalog.is_pack_face(face) and Catalog.pack_of(face) in pickable_packs(local)

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
