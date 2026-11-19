extends RefCounted
## World kit: a gorge round a water world's floors, from its dressing's
## "gorge" (presentation only; nothing reaches the simulation):
##   "wall": {"from": x_cm, "to": x_cm, "front": z_cm, "rise": cm,
##            "open": [[x0_cm, x1_cm], ...]}
##       the back wall: the Blender gorge rock (assets/models/gorge_rock.glb,
##       gorge_wall_a and _b in turn) tiled along x from `from` to `to`, its
##       front face at z `front`, each stretch standing on the bed of the
##       pool behind it (WaterBodies.bed_at) and rising `rise` above the
##       highest floor near it, so every tier has rock behind it; left open
##       where a waterfall pours through (`open`).
##   "base": true
##       solid rock under every pool that has its own bed above the block's
##       seabed (the water kit's "bed"), from the seabed up to that bed, so a
##       climb of pools stands on rock seen from any zoom, not on hollow water.
##   "rainbows": [{"at": [x_cm, y_cm, z_cm], "radius": cm}]
##       soft arcs in a falls' spray, turned to face the world's camera
##       (camera_from), so they read from the level's own angle.
## The rock folds into the scenery batches (Models.still), so it costs no
## draw call of its own; the rainbows are one mesh each.
const Models = preload("res://presentation/kit/models.gd")
const Props = preload("res://presentation/kit/props.gd")
const MODEL := "res://assets/models/gorge_rock.glb"
## One stretch of wall: its width and height as modelled (m).
const WALL_WIDE := 4.0
const WALL_TALL := 5.0
## Each stretch is laid this many times as wide as modelled: the strata read
## as long ledges and the wall costs a third fewer triangles.
const STRETCH := 1.5
const BANDS := [Color(0.95, 0.42, 0.38), Color(0.98, 0.72, 0.36), Color(0.98, 0.93, 0.48), Color(0.52, 0.86, 0.52), Color(0.45, 0.66, 0.95), Color(0.62, 0.48, 0.88)]
## How see-through a rainbow is at its brightest.
const RAINBOW_ALPHA := 0.42

## Builds the dressing's gorge under the world's terrain.
static func build(world: Node3D, data: Dictionary) -> void:
	if data.is_empty(): return
	var holder := Node3D.new()
	holder.name = "Gorge"
	world.terrain.add_child(holder)
	if data.has("wall"): _wall(world, data.wall, holder)
	if bool(data.get("base", false)): _base(world, holder)
	for rainbow: Dictionary in data.get("rainbows", []):
		var at: Array = rainbow.at
		_rainbow(holder, Vector3(float(at[0]), float(at[1]), float(at[2])) / 100.0, float(rainbow.radius) / 100.0, world.camera_from())

static func _wall(world: Node3D, wall: Dictionary, holder: Node3D) -> void:
	var front := float(wall.front) / 100.0
	var rise := float(wall.get("rise", 500)) / 100.0
	var x := float(wall.from) / 100.0
	var end := float(wall.to) / 100.0
	var index := 0
	while x < end:
		var wide := WALL_WIDE * STRETCH * (0.92 + 0.16 * fposmod(float(index) * 0.618, 1.0))
		var middle := x + wide * 0.5
		var open: bool = (wall.get("open", []) as Array).any(func(gap: Array) -> bool: return middle * 100.0 > float(gap[0]) and middle * 100.0 < float(gap[1]))
		if not open:
			var foot: float = world.waters.bed_at(Vector2(middle * 100.0, 0.0))
			var top := _floor_top(world, middle) + rise
			var rock := Models.still(MODEL, "gorge_wall_a" if index % 2 == 0 else "gorge_wall_b", Props.FALLS_COLORS, holder)
			rock.position = Vector3(middle, foot, front - 0.4 * fposmod(float(index) * 0.37, 1.0))
			rock.scale = Vector3(wide / WALL_WIDE, maxf(top - foot, 1.0) / WALL_TALL, 1.0)
		x += wide
		index += 1

## Rock from the seabed up to each raised pool's own bed, under its rects.
static func _base(world: Node3D, holder: Node3D) -> void:
	var seabed: float = world.waters.seabed()
	var Primitives: Script = load("res://presentation/kit/primitives.gd")
	for body: Dictionary in world.waters.water.get("bodies", []):
		var bed := float(body.get("bed", seabed))
		if bed <= seabed + 0.05: continue
		for r: Array in body.get("rects", []):
			var size := Vector3(float(r[2] - r[0]) / 100.0, bed - 0.02 - seabed, float(r[3] - r[1]) / 100.0)
			var at := Vector3(float(r[0] + r[2]) / 200.0, seabed + size.y * 0.5, float(r[1] + r[3]) / 200.0)
			Primitives.mesh_node(Primitives.box_mesh(size), Primitives.shared_material(Props.FALLS_COLORS.stone_dark), at, holder).name = "PoolBase"

## The highest floor (m) within a stretch of wall either side of `x` (m).
static func _floor_top(world: Node3D, x: float) -> float:
	var top := 0.0
	for island: Dictionary in world.current_level.get("islands", []):
		var r: Array = island.rect_cm
		if float(r[0]) / 100.0 - WALL_WIDE < x and float(r[2]) / 100.0 + WALL_WIDE > x: top = maxf(top, float(island.get("height_cm", 0)) / 100.0)
	return top

## A soft rainbow arc of `radius` (m) standing at `centre`, facing `from`.
static func _rainbow(parent: Node3D, centre: Vector3, radius: float, from: Vector3) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := radius * 0.035
	var segments := 28
	for band in range(BANDS.size()):
		var r0 := radius - width * band
		var r1 := r0 - width
		var color: Color = BANDS[band]
		for index in range(segments):
			var a0 := PI * (0.1 + 0.8 * float(index) / segments)
			var a1 := PI * (0.1 + 0.8 * float(index + 1) / segments)
			var fade0 := sin((float(index) / segments) * PI) * RAINBOW_ALPHA
			var fade1 := sin((float(index + 1) / segments) * PI) * RAINBOW_ALPHA
			var quad := [Vector3(cos(a0) * r0, sin(a0) * r0, 0), Vector3(cos(a1) * r0, sin(a1) * r0, 0), Vector3(cos(a1) * r1, sin(a1) * r1, 0), Vector3(cos(a0) * r1, sin(a0) * r1, 0)]
			var fades := [fade0, fade1, fade1, fade0]
			for corner: int in [0, 1, 2, 0, 2, 3]:
				tool.set_color(Color(color.r, color.g, color.b, fades[corner]))
				tool.add_vertex(quad[corner])
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.render_priority = 2
	var arc := MeshInstance3D.new()
	arc.name = "Rainbow"
	arc.mesh = tool.commit()
	arc.material_override = mat
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arc.position = centre
	# Turned to the camera across and tipped back toward it: the arc's face
	# (+z) points along the view, back toward where the camera stands.
	arc.basis = Basis.looking_at(-from.normalized(), Vector3.UP)
	parent.add_child(arc)
