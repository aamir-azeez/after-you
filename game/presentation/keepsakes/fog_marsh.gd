extends "res://presentation/keepsakes/keepsake_builder.gd"
## Fog Marsh's keepsake, the Fog Lantern, from the Blender kit model
## keepsake_fog_lantern (claude-20261010/tools/blender/models/): a reedy pond
## under the marsh's own low mist (kit/fog.gd's look), a boardwalk out into it
## and a lantern on a crooked post over the boardwalk's end. Walking up to the
## boardwalk sets it off: the pip walks out along its planks, the lantern
## lights, the mist rolls back off the water to the far bank and the frog hops
## from its stone onto a lily pad; the pip walks back to the grass as the mist
## drifts in again, the frog hops home and the lantern dims. A tap lights it
## without the pip. The pip keeps to the planks' middle (they are DECK high)
## and only steps down onto the grass.
## Together: a mint raft drifts out over the cleared water. Hard: a firefly jar
## on a slate plinth; the fireflies rise out and circle the lantern. Together
## Hard: a gold moon on the post top, and its glint on the pond.
const P = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Models = preload("res://presentation/kit/models.gd")
const SoftMist = preload("res://presentation/kit/soft_mist.gd")
const Fog = preload("res://presentation/kit/fog.gd")
const MODEL := "res://assets/models/keepsake_fog_lantern.glb"
const COLORS := {"bank": Color("8a9a72"), "water": P.WATER, "pad": Color("7fae6a"), "reed": P.LEAF, "reed_head": P.POT,
	"plank": P.PLANK, "post": P.POST, "wood": P.WOOD, "iron": P.SLATE_DARK, "lamp": P.LAMP_OFF, "trim": P.PEACH,
	"frog": Color("8fbf6a"), "eye": P.SNOW, "stone": P.STONE_LIGHT, "mint": P.MINT, "mint_deep": P.MINT_DEEP,
	"rope": Color("d1b98c"), "glass": P.GLASS}
## The model's measures (keepsake_fog_lantern.py): the pond and its bank's
## outer edge, the water, the boardwalk's planks' top and its ends, the post,
## the lantern's glass, the frog's stone and the lily pad it hops to, the raft,
## the jar.
const POND := Vector3(0, 0, -0.3)
const BANK := 1.38
const WATER := 0.06
const DECK := 0.27
const WALK_SHORE := 1.55
const POST := Vector3(-0.5, 0, -0.32)
const LAMP := Vector3(0.05, 1.82, -0.32)
const FROG := Vector3(0.66, WATER + 0.12, -0.86)
const PAD := Vector3(0.32, WATER + 0.03, -0.9)
const RAFT := Vector3(0.55, WATER, 0.05)
const RAFT_OUT := Vector3(0.6, WATER, -0.08)
const JAR := Vector3(-0.95, 0, 1.2)
## The pip's walk: off the grass onto the planks, out to near the far end.
const FOOT := Vector3(0, 0, 1.8)
const ON_DECK := Vector3(0, DECK, 1.38)
const OUT := Vector3(0, DECK, 0.05)
## The mist's blots over the water: [middle, size (long, deep)], two heights
## as the marsh's (kit/fog.gd LAYERS) over the water.
const MIST: Array = [[Vector3(-0.55, 0, -0.75), Vector2(1.0, 0.6)], [Vector3(0.5, 0, -0.85), Vector2(1.1, 0.6)], [Vector3(0.0, 0, -1.1), Vector2(1.2, 0.5)],
	[Vector3(-0.6, 0, 0.0), Vector2(0.9, 0.7)], [Vector3(0.6, 0, -0.1), Vector2(1.0, 0.7)], [Vector3(-0.42, 0, 0.5), Vector2(0.8, 0.5)],
	[Vector3(0.48, 0, 0.45), Vector2(0.8, 0.5)]]
## Where the mist gathers as it rolls back: toward the far bank.
const ROLLED := Vector3(0, 0, -0.95)
const ROLLED_SIZE := Vector3(0.5, 1.0, 0.3)

func build(root: Node3D, state: Dictionary) -> Dictionary:
	for part: String in ["marsh_pond", "marsh_walk", "marsh_post"]: Models.still(MODEL, part, COLORS, root)
	var glass := Models.moving(MODEL, "marsh_glass", COLORS, root)
	var frog := _on_pond(root, "marsh_frog", "Frog")
	var parts := {"glass": glass, "frog": frog, "fog": _mist(root), "glass_look": glass.material_override}
	if state.get("together", false):
		parts.raft = _on_pond(root, "marsh_raft", "Raft")
	if state.get("hard", false):
		P.plinth(root, 0.5, 0.5, JAR)
		Models.still(MODEL, "marsh_jar", COLORS, root)
		var flies := P.pivot(root, JAR + Vector3(0, P.PLINTH_TOP + 0.14, 0), "Flies")
		for index in range(6):
			var angle := index * TAU / 6.0
			P.node(flies, P.low_sphere(0.025), P.glow(P.LAMP, 2.4), Vector3(cos(angle) * 0.06, 0.05 * (index % 3) - 0.05, sin(angle) * 0.06))
		parts.flies = flies
	if state.get("top", false):
		var moon := P.pivot(root, POST + Vector3(0.02, 2.42, 0), "Moon")
		P.node(moon, P.Primitives.shared_mesh("cylinder", 0.17, 0.05, 0.17), P.gold(), Vector3.ZERO, Vector3(PI / 2, 0, 0))
		P.node(moon, P.Primitives.shared_mesh("cylinder", 0.135, 0.06, 0.135), P.mat(Color("17393a")), Vector3(0.08, 0.05, 0.005), Vector3(PI / 2, 0, 0))
		P.box(root, Vector3(0.03, 0.1, 0.03), P.GOLD_DEEP, POST + Vector3(0.02, 2.23, 0))
		parts.top = moon
	return parts

## A piece out on the pond (the frog, the raft), held from the pond's middle
## as the mist is, so it moves as the pond's own: its play moves it by how far
## it goes from where it was modelled.
func _on_pond(root: Node3D, part: String, label: String) -> Node3D:
	var pivot := P.pivot(root, POND, label)
	Models.moving(MODEL, part, COLORS, pivot).position -= POND
	return pivot

## The mist: long flat blots of the marsh's own haze lying low over the water,
## in its look (kit/fog.gd COLOR), one mesh. It moves as one from the pond's
## middle.
func _mist(root: Node3D) -> Node3D:
	var mist := P.pivot(root, POND, "Mist")
	var blots: Array = []
	for index in range(MIST.size()):
		var blot: Array = MIST[index]
		var layer: float = Fog.LAYERS[index % Fog.LAYERS.size()]
		blots.append([(blot[0] as Vector3) - POND + Vector3(0, WATER + layer, 0), blot[1], "up"])
	SoftMist.build(blots, Fog.COLOR, mist)
	return mist

func base_time() -> float:
	return 3.45

func upgrade_time(_beat: String) -> float:
	return 0.6

## The pip's walk out along the planks and back to the grass, each piece
## [callable, seconds, hop].
static func walk(from: Vector3) -> Array:
	return [[func(t: float) -> Vector3: return from.lerp(FOOT, t), 0.2, false], [Anim.hop_leg(FOOT, ON_DECK, 0.12), 0.3, true],
		[func(t: float) -> Vector3: return ON_DECK.lerp(OUT, t), 0.75, false], [func(_t: float) -> Vector3: return OUT, 1.05, false],
		[func(t: float) -> Vector3: return OUT.lerp(ON_DECK, t), 0.7, false], [Anim.hop_leg(ON_DECK, FOOT, 0.12), 0.3, true]]

func play(beat: String, anim: RefCounted, parts: Dictionary, state: Dictionary) -> void:
	var sounds: Dictionary = state.get("sounds", {})
	match beat:
		"base":
			var t := 0.0
			for leg: Array in walk(anim.rider_from):
				anim.carry(leg[0], t, leg[1])
				if leg[2]: anim.rider_call(&"play_hop", [leg[1], Anim.HOP_CONTACT], t)
				t += float(leg[1])
			# The lantern lights as the pip nears the end, and its light glows round it.
			anim.set_at(parts.glass, "material_override", P.glow(P.LAMP, 2.4), 1.0)
			var glow: MeshInstance3D = anim.spawn(anim.fx, SoftMist.cluster([[Vector3.ZERO, Vector2(1.3, 1.3), "front"]]), SoftMist.look(Color(1.0, 0.85, 0.5, 0.55), false, true), LAMP)
			anim.set_at(glow, "visible", true, 1.0)
			anim.sound(str(sounds.get("base", "")), 1.0)
			# The mist rolls back off the water to the far bank.
			var mist: Node3D = parts.fog
			anim.move(mist, "position", ROLLED, 1.1, 0.9, Tween.TRANS_QUAD, Tween.EASE_OUT)
			anim.move(mist, "scale", ROLLED_SIZE, 1.1, 0.9, Tween.TRANS_QUAD, Tween.EASE_OUT)
			# The frog hops onto a lily pad, and home again as the mist comes back.
			anim.path(parts.frog, func(u: float) -> Vector3: return POND + (PAD - FROG) * u + Vector3(0, sin(u * PI) * 0.3, 0), 1.9, 0.45)
			anim.sound("drip", 2.3)
			anim.move(mist, "position", POND, 2.45, 0.95)
			anim.move(mist, "scale", Vector3.ONE, 2.45, 0.95)
			anim.path(parts.frog, func(u: float) -> Vector3: return POND + (PAD - FROG) * (1.0 - u) + Vector3(0, sin(u * PI) * 0.25, 0), 2.95, 0.4)
			anim.set_at(glow, "visible", false, 3.2)
			anim.set_at(parts.glass, "material_override", parts.glass_look, 3.2)
		"together":
			var raft: Node3D = parts.raft
			var out := POND + RAFT_OUT - RAFT
			anim.move(raft, "position", out, 0.0, 0.45)
			anim.move(raft, "position:y", out.y + 0.02, 0.45, 0.1)
			anim.move(raft, "position:y", out.y, 0.55, 0.05)
			anim.sound(str(sounds.get("together", "")), 0.0)
		"hard":
			# They rise straight out of the jar, then fly up round the lantern.
			var flies: Node3D = parts.flies
			var rest := flies.position
			var above := Vector3(rest.x, 1.3, rest.z)
			anim.path(flies, func(u: float) -> Vector3: return rest.lerp(above, u / 0.4) if u < 0.4 else above.lerp(LAMP, (u - 0.4) / 0.6), 0.0, 0.45)
			anim.move(flies, "scale", Vector3.ONE * 4.0, 0.2, 0.25)
			anim.move(flies, "rotation:y", TAU, 0.0, 0.6, Tween.TRANS_LINEAR)
			anim.sound(str(sounds.get("hard", "")), 0.0)
		"top":
			brighten(anim, parts.top, 0.0)
			var glint: MeshInstance3D = anim.spawn(anim.fx, SoftMist.cluster([[Vector3.ZERO, Vector2(0.4, 0.3), "up"]]), SoftMist.look(Color(1.0, 0.8, 0.35, 0.8), false, true), Vector3(0.0, WATER + 0.015, -0.75))
			anim.set_at(glint, "visible", true, 0.1)
			anim.sound(str(sounds.get("top", "")), 0.0)

## Walking up to the boardwalk's shore end.
func trigger() -> Dictionary:
	return {"area": Rect2(-0.28, 1.66, 0.56, 0.34)}

## Set off from beside or behind the pond, the pip goes round to the boardwalk first.
func ride_start(_state: Dictionary, from: Vector3) -> Variant:
	return start_in(trigger().area, from)

## The pond and its bank, the boardwalk out over it (the pip only walks it on
## its ride), and Hard's firefly jar.
func solids(state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = round_solid(Vector2(POND.x, POND.z), BANK)
	result.append(Rect2(-0.32, -0.3, 0.64, WALK_SHORE + 0.33))
	if state.get("hard", false): result.append(Rect2(JAR.x - 0.25, JAR.z - 0.25, 0.5, 0.5))
	return result

func footprint() -> Rect2:
	return Rect2(-1.4, -1.7, 2.8, 3.75)
