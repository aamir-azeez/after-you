extends RefCounted
## The one seed every world draws, shaped like the seed in the app icon: a
## rounded cream pebble, a short curved stem and one leaf to the side, with a
## soft glow around the body. Callers keep their own size, colour states and
## emission; only this builder decides the shape.
const LEAF := Color("a2bd81")
const WHITE := Color("f6f4ea")
const META := "seed_visual"
const LEAF_COUNT := 1
## Icon proportions in keepsake units: the body is 0.576 tall and a little narrower.
const BODY_HALF_HEIGHT := 0.288
const BODY_RADIUS := 0.27
const STEM := {"radius": 0.024, "height": 0.2, "at": Vector3(-0.015, 0.36, 0), "tilt": 0.2}
const LEAF_RADIUS := 0.16
const LEAF_AT := Vector3(0.12, 0.5, 0)
const LEAF_SCALE := Vector3(1.0, 0.45, 0.35)
const LEAF_TILT := 0.45
## The glow is a soft camera-facing halo behind the body; it follows the body colour.
const GLOW_SIZE := 3.6
const GLOW_ALPHA := 0.7

## Returns the seed body. `radius` is its vertical half extent, so a carried,
## resting or flying seed sits where the old round seed of that radius sat.
## The body owns its material; stem, leaf and glow are children with their own.
static func create(world: Node3D, radius: float, color: Color, at: Vector3, parent: Node3D) -> MeshInstance3D:
	var scale := radius / BODY_HALF_HEIGHT
	var shape := SphereMesh.new()
	shape.radius = BODY_RADIUS * scale
	shape.height = BODY_HALF_HEIGHT * 2.0 * scale
	shape.radial_segments = 16
	shape.rings = 8
	var body: MeshInstance3D = world.mesh_node(shape, color, at, parent)
	body.name = "Seed"
	body.set_meta(META, true)
	var stem: MeshInstance3D = world.cylinder(STEM.radius * scale, STEM.height * scale, LEAF, STEM.at * scale, body)
	stem.name = "SeedStem"
	stem.rotation.z = STEM.tilt
	var leaf: MeshInstance3D = world.sphere(LEAF_RADIUS * scale, LEAF, LEAF_AT * scale, body)
	leaf.name = "SeedLeaf0"
	leaf.scale = LEAF_SCALE
	leaf.rotation.z = LEAF_TILT
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * shape.radius * GLOW_SIZE
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var halo := GradientTexture2D.new()
	halo.gradient = fade
	halo.fill = GradientTexture2D.FILL_RADIAL
	halo.fill_from = Vector2(0.5, 0.5)
	halo.fill_to = Vector2(0.5, 0.0)
	halo.width = 64
	halo.height = 64
	var glow := MeshInstance3D.new()
	glow.name = "SeedGlow"
	glow.mesh = quad
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	glow_material.no_depth_test = false
	glow_material.render_priority = -1
	glow_material.albedo_texture = halo
	glow_material.albedo_color = Color(color, GLOW_ALPHA)
	glow.material_override = glow_material
	body.add_child(glow)
	return body

static func leaves(body: Node) -> Array[Node]:
	var found: Array[Node] = []
	if body == null: return found
	for child: Node in body.get_children():
		if child.name.begins_with("SeedLeaf"): found.append(child)
	return found

## Tints the glow to match the body after a carry colour change.
static func tint_glow(body: Node, color: Color) -> void:
	var glow := body.get_node_or_null("SeedGlow") as MeshInstance3D if body != null else null
	if glow != null: (glow.material_override as StandardMaterial3D).albedo_color = Color(color, GLOW_ALPHA)
