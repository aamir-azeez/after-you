extends RefCounted
## Faces beyond the everyday ones on this phone: which pack faces (services/
## reaction_catalog.gd PACKS) and single faces the player may pick now, and the
## reaction slots the React card shows.
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
##
## While the server serves every face (face version 2, FACE_SINGLES), a face is
## picked as owned (the wardrobe's `faces`: bought alone or in a pack), with or
## without the shop, and the React card shows the player's reaction slots
## (slots()) in place of the free faces and pack tabs.
const Catalog = preload("res://services/reaction_catalog.gd")
const PollenSurfaces = preload("res://services/pollen_surfaces.gd")
const Typed = preload("res://services/typed_values.gd")

## () -> {"version": int, "view": Dictionary, "slots": Array}: the faces the
## signed-in player's server takes (RelayOnlineSession.face_version), their
## wardrobe (services/wardrobe.gd view) and the reaction slots shown on this
## phone (services/wardrobe.gd effective_slots). Main sets it; until then no
## pack can be picked. An older test source's {"server": bool} reads as 1 or 0.
static var source: Callable

## The packs whose faces the player may pick now, in PACKS order. `local`: the
## pick stays on this phone, so the server's support does not matter.
static func pickable_packs(local: bool = false) -> Array:
	if not source.is_valid(): return []
	var state: Variant = source.call()
	if not state is Dictionary: return []
	return packs_for(local or version_of(state) >= 1, state.get("view"), PollenSurfaces.shared())

static func _state() -> Dictionary:
	if not source.is_valid(): return {}
	var state: Variant = source.call()
	return state if state is Dictionary else {}

## The face version a source state says (0, 1 or 2).
static func version_of(state: Dictionary) -> int:
	if state.has("version"): return clampi(Typed.as_int(state.get("version"), 0), 0, 2)
	return 1 if Typed.equal(state.get("server"), true) else 0

## The reaction faces the player owns: the wardrobe's `faces` while the server
## sends them, else the faces of each owned pack.
static func owned_faces(view: Variant) -> Array:
	if not view is Dictionary: return []
	if view.get("faces") is Array: return (view.faces as Array).duplicate()
	var faces: Array = []
	var packs: Variant = view.get("packs")
	if packs is Array:
		for pack: String in Catalog.PACKS:
			if pack in packs: faces.append_array(Catalog.PACKS[pack])
	return faces

## The React card's faces in slot order ("" for an empty place), each face the
## player may pick now; [] while the server keeps no slots, so the card shows
## the free faces and pack tabs as before.
static func slots(local: bool = false) -> Array:
	var state := _state()
	var shown: Variant = state.get("slots")
	if not shown is Array or (shown as Array).is_empty() or (not local and version_of(state) < 2): return []
	return (shown as Array).map(func(face: Variant) -> String: return str(face) if face is String and can_pick(str(face), local) else "")

## pickable_packs from its parts (tests call it directly).
static func packs_for(server_takes_packs: bool, view: Variant, surfaces: RefCounted) -> Array:
	if not server_takes_packs or surfaces == null or not surfaces.shop_visible() or not view is Dictionary: return []
	var owned: Variant = view.get("packs")
	if not owned is Array: return []
	return Catalog.PACKS.keys().filter(func(pack: String) -> bool: return pack in owned)

## Whether `face` may be picked now: an everyday face always; a single or pack
## face while it is owned and the server takes it (version 2), or a pack face
## while its pack is pickable (version 1).
static func can_pick(face: String, local: bool = false) -> bool:
	if not Catalog.is_paid_face(face): return Catalog.is_face(face)
	var state := _state()
	var view: Variant = state.get("view")
	# Owned faces as the server listed them (version 2); a pack-only wardrobe keeps the pack rule below.
	if (local or version_of(state) >= 2) and view is Dictionary and view.get("faces") is Array and face in view.faces: return true
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
