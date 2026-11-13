extends RefCounted
## Soft ring (foot ring): a quiet dashed mint ring on the floor round the
## pip's feet, 1.1 pip widths across (the board's little extras). Its
## descriptor's "places" keep it to room and result pages and the Wardrobe,
## never a chapter or Home, so it can't be taken for a pad or a target. Flat
## and still: no pulse, no light. One quad with a drawn ring texture (made
## once, small), on the pip's own node, which never turns.
const Kit = preload("res://presentation/kit/pip_wear_kit.gd")
const Look = preload("res://presentation/spirit_look.gd")

const DASH := Color("b2d6c2")
const GLOW := Color("dce9d4")
## Its width across (metres), the dashes' width (metres, the board's chunky
## dashes) and how many dashes go round.
const WIDTH := 1.1 * Look.HEAD_HALF.x * 2.0
const LINE := 0.045
const DASHES := 18
## Just above the floor, under the pip's feet.
const LIFT := 0.004
const TEXTURE_SIZE := 128

static func wear(look: RefCounted) -> void:
	var node: MeshInstance3D = look.mesh(look.root(), Kit.cached_mesh("soft_ring", _quad), Kit.cached_material("soft_ring", _material), Transform3D(Basis.IDENTITY, Vector3(0, LIFT, 0)))
	node.name = "SoftRing"

static func _quad() -> Mesh:
	var quad := PlaneMesh.new()
	quad.size = Vector2(WIDTH + LINE, WIDTH + LINE)
	return quad

static func _material() -> Material:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = ImageTexture.create_from_image(ring_image(TEXTURE_SIZE))
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return material

## The ring drawn into a square image `size` across: a faint full ring in the
## pale mint and the dashes over it, soft edged.
static func ring_image(size: int) -> Image:
	var image := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var scale := (WIDTH + LINE) / size
	var radius := WIDTH * 0.5
	var half_line := LINE * 0.5
	for y in range(size):
		for x in range(size):
			var p := (Vector2(x, y) + Vector2(0.5, 0.5)) * scale - Vector2.ONE * (WIDTH + LINE) * 0.5
			var off := absf(p.length() - radius)
			var band := clampf((half_line - off) / scale + 0.5, 0.0, 1.0)
			if band <= 0.0:
				image.set_pixel(x, y, Color(GLOW, 0.0))
				continue
			var turn := fposmod(atan2(p.y, p.x) / TAU * DASHES, 1.0)
			var dash := clampf((0.32 - absf(turn - 0.5)) * radius * TAU / DASHES / scale + 0.5, 0.0, 1.0)
			var color := GLOW.lerp(DASH, dash)
			image.set_pixel(x, y, Color(color, band * lerpf(0.35, 0.9, dash)))
	image.generate_mipmaps()
	return image
