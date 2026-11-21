extends RefCounted
## World kit: the cutaway that fades a raised floor while a spirit is under it.
## Raised floors are Node3D roots carrying a "bounds" rect_cm meta, positioned
## at their height. Fading never changes movement, only how the floor is drawn.

const Primitives = preload("res://presentation/kit/primitives.gd")
const FADED_ALPHA := 0.10
## A mesh a world marks with this meta stays solid while its floor fades,
## like the beams of the Conservatory's balcony on posts, so a faded deck
## keeps its timber and never reads as a box.
const KEEP := "cutaway_keep"
## A mesh a world marks with this meta hides while its floor fades instead
## (a floor's baked shade, kit/contact_shadows.gd), so it never hangs over a
## see-through floor.
const HIDE := "cutaway_hide"

## Fades (or restores) every mesh under node. Shared scenery materials are
## copied first, so fading one floor never fades the same prop elsewhere.
static func set_faded(node: Node, faded: bool) -> void:
	if hides(node, faded): return
	if node is MeshInstance3D and node.material_override is StandardMaterial3D:
		if not fade_mesh(node, faded): return
	for child: Node in node.get_children(): set_faded(child, faded)

## Hides (or shows) node when it is marked HIDE; false for any other node.
static func hides(node: Node, faded: bool) -> bool:
	if not node is GeometryInstance3D or not node.has_meta(HIDE): return false
	(node as GeometryInstance3D).visible = not faded
	return true

## Fades one mesh. Returns false when it already shows that state, in which
## case its subtree is already in that state too.
static func fade_mesh(node: MeshInstance3D, faded: bool) -> bool:
	if node.get_meta(KEEP, false): return true
	if node.get_meta("cutaway", false) == faded: return false
	node.set_meta("cutaway", faded)
	var mat := Primitives.own_material(node)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
	mat.albedo_color.a = FADED_ALPHA if faded else 1.0
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true

## A player stands under this raised floor's span.
static func below_raised(raised: Node3D, player: Dictionary) -> bool:
	var bounds: Array = raised.get_meta("bounds")
	return float(player.height)/100.0 < raised.position.y-0.5 and int(player.x) >= int(bounds[0])-200 and int(player.x) <= int(bounds[2])+100

## During the shared celebration both spirits stay visible: fade the floor if
## either one is under it.
static func anyone_below(raised: Node3D, state: Dictionary) -> bool:
	for player: Dictionary in state.players.values():
		if below_raised(raised, player): return true
	return false
