extends RefCounted
## Piece kit: the path behind the falls (the "falls_path" deck). A rock lip
## overhangs the path's back edge for good; while the path is shut a curtain
## of the falls' running water pours off it, arcs over the path and lands in
## foam on the path and in the pool in front, so a shut path reads as "behind
## the falls". The water stays within the path's own length, a little short
## of each end, so a pip on the floor beside it is never covered, and the
## mist hangs low along its foot. A path along x pours toward +z; one along z
## toward +x.
const Models = preload("res://presentation/kit/models.gd")
const SoftMist = preload("res://presentation/kit/soft_mist.gd")
const MODEL := "res://assets/models/gorge_rock.glb"
## The lip's height over the path and how far it reaches out over it (m).
const LIP := 1.25
const OVERHANG := 0.3
## How far short of each end of the path the water stops (m).
const INSET := 0.3
## The rock lip model's width as modelled (m, gorge_rock.glb rock_lip).
const LIP_WIDE := 2.0
const MIST := Color(0.97, 0.99, 0.99, 0.45)

## The lip (static) and the curtain (returned: shown while the path is shut)
## for path `rect` (m, plan) at `height` (m), under `parent`.
static func build(rect: Rect2, height: float, parent: Node3D) -> Node3D:
	var long := rect.size.x >= rect.size.y
	var span := rect.size.x if long else rect.size.y
	var deep := rect.size.y if long else rect.size.x
	var place := Node3D.new()
	place.name = "FallsPath"
	place.position = Vector3(rect.get_center().x, height, rect.get_center().y)
	if not long: place.rotation.y = PI * 0.5
	parent.add_child(place)
	var back := -deep * 0.5
	var Props: Script = load("res://presentation/kit/props.gd")
	var count := maxi(1, ceili(span / LIP_WIDE))
	for index in range(count):
		var rock := Models.still(MODEL, "rock_lip", Props.FALLS_COLORS, place)
		rock.position = Vector3((float(index) + 0.5) * span / float(count) - span * 0.5, LIP, back + OVERHANG)
		rock.scale = Vector3(span / float(count) / LIP_WIDE * 1.02, 1.0, 1.0)
	var curtain := Node3D.new()
	curtain.name = "FallsCurtain"
	place.add_child(curtain)
	var wide := maxf(span - INSET * 2.0, 0.4)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge := back + OVERHANG
	var points := [Vector3(0, LIP, edge - 0.5), Vector3(0, LIP, edge), Vector3(0, LIP - 0.12, edge + 0.1)]
	var falling := [0.0, 0.0, 0.5]
	var reach := deep + 0.25
	for step in range(1, 8):
		var t := float(step) / 7.0
		points.append(Vector3(0, LIP - 0.12 - (LIP + 0.45) * t, edge + 0.1 + reach * sqrt(t)))
		falling.append(1.0)
	Props._falls_strip(tool, wide, points, falling)
	Props._falls_foam(tool, Vector3(0, 0.04, 0.1), Vector2(wide * 0.5, deep * 0.4))
	Props._falls_foam(tool, Vector3(0, -0.4, deep * 0.5 + 0.35), Vector2(wide * 0.5, 0.35))
	var flow := MeshInstance3D.new()
	flow.name = "Flow"
	flow.mesh = tool.commit()
	flow.material_override = Props._falls_material()
	flow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	curtain.add_child(flow)
	var blots: Array = []
	var puffs := maxi(1, roundi(wide / 2.5))
	for index in range(puffs):
		var x := ((float(index) + 0.5) / float(puffs) - 0.5) * wide
		blots.append([Vector3(x, 0.2, deep * 0.5 + 0.35), Vector2(minf(2.6, wide / float(puffs)), 0.7), "front"])
	SoftMist.build(blots, MIST, curtain)
	return curtain
