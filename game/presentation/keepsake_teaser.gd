extends TextureRect
## A strip of real catalog keepsakes drawn once into a small transparent view: locked
## silhouettes in one flat muted colour, or (silhouette = false) earned ones in their
## own colours. Presentation only: it never reads or awards progress.
const Visual = preload("res://presentation/keepsake_visual.gd")
const SILHOUETTE := Color("4a7a6d")
const CELL_UNITS := 1.4
# Rendered at twice the shown size so edges stay clean after UI scaling.
const SUPERSAMPLE := 2
var items: Array[Dictionary] = []
var silhouette := true
var _viewport: SubViewport

func configure(world: Node3D, shown: Array[Dictionary], cell: float, as_silhouettes: bool = true) -> void:
	items = shown.duplicate(true)
	silhouette = as_silhouettes
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(cell * items.size(), cell)
	_viewport = SubViewport.new()
	_viewport.name = "SilhouetteView"
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.size = Vector2i(maxi(1, roundi(cell * items.size() * SUPERSAMPLE)), maxi(1, roundi(cell * SUPERSAMPLE)))
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flat.albedo_color = SILHOUETTE
	for index in range(items.size()):
		var prop := Visual.create(world, items[index], false)
		prop.position = Vector3((index - (items.size() - 1) * 0.5) * CELL_UNITS, 0, 0)
		prop.rotation.y = -0.5
		prop.set_meta("keepsake_id", items[index].id)
		_viewport.add_child(prop)
		if not silhouette: continue
		for mesh: Node in prop.find_children("*", "MeshInstance3D", true, false):
			(mesh as MeshInstance3D).material_override = flat
	if not silhouette:
		# Its own world has no light; give earned keepsakes a soft key light and fill.
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-50, -35, 0)
		light.light_energy = 0.9
		_viewport.add_child(light)
		var environment := WorldEnvironment.new()
		environment.environment = Environment.new()
		environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color = Color.WHITE
		environment.environment.ambient_light_energy = 0.55
		_viewport.add_child(environment)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CELL_UNITS
	var eye := Vector3(0, 1.5, 4.0)
	var target := Vector3(0, 0.52, 0)
	camera.transform = Transform3D(Basis.looking_at(target - eye, Vector3.UP), eye)
	_viewport.add_child(camera)
	camera.current = true
	texture = _viewport.get_texture()
