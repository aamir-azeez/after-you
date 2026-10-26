extends RefCounted
## The little studio a lone pip is drawn in, shared by the live preview
## (kit/spirit_preview.gd) and the still snapshots (kit/pip_snapshots.gd), so a
## still pip looks exactly like a live one at rest: a warm ambient light, one
## sun, a narrow camera on a three-quarter view, and the real SpiritVisual
## without its ground ring or shadow. A tall item (its descriptor's "tall")
## pulls the camera back a little so it stays in frame.
const SpiritVisual = preload("res://presentation/spirit_visual.gd")
const Outfit = preload("res://services/outfit.gd")

const CAMERA_AT := Vector3(0.0, 0.66, 2.45)
const LOOK_AT := Vector3(0.0, 0.53, 0.0)
const FOV := 24.0
## With a tall item: how much farther the camera stands, and how much higher
## it looks.
const TALL_PULL := 1.15
const TALL_LIFT := 0.04

## Lights `view` and adds `pip` and a camera framed for `outfit`; returns the
## camera.
static func build(view: SubViewport, pip: Node3D, outfit: Dictionary) -> Camera3D:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("ffe6c8")
	environment.ambient_light_energy = 0.42
	var world := WorldEnvironment.new()
	world.environment = environment
	view.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.8
	sun.light_color = Color("ffeedd")
	sun.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(28.0), 0.0)
	view.add_child(sun)
	view.add_child(pip)
	var camera := Camera3D.new()
	camera.fov = FOV
	view.add_child(camera)
	frame(camera, outfit)
	camera.current = true
	return camera

## A pip for the studio, in `color`, wearing `outfit`.
static func pip(color: Color, outfit: Dictionary) -> SpiritVisual:
	var made := SpiritVisual.new(color)
	made.ground_ring.visible = false
	made.ground_shadow.visible = false
	made.set_expression_role("a")
	made.wear(outfit)
	return made

## Points the camera at the pip, pulled back for a tall outfit.
static func frame(camera: Camera3D, outfit: Dictionary) -> void:
	if not Outfit.tall(outfit):
		camera.look_at_from_position(CAMERA_AT, LOOK_AT)
		return
	var target := LOOK_AT + Vector3(0, TALL_LIFT, 0)
	camera.look_at_from_position(target + (CAMERA_AT - LOOK_AT) * TALL_PULL, target)
