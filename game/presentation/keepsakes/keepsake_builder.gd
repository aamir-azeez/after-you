extends RefCounted
## What every Home keepsake builder does (presentation/keepsakes/*.gd extend
## this). A chapter names its builder in its descriptor's home_keepsake
## (content/chapters/index.gd); the layer (presentation/home_keepsake_layer.gd)
## places, folds, plays and resets it, so a builder is geometry and timing only.
##
## - build(root, state) adds plain geometry under root (no scripts) and returns
##   its moving parts by name (and any plain values play() needs). Everything
##   else is still and folds into Home's shared batches, so a still node is
##   never returned. Parts made for a tap go under anim.fx, in root's frame. `state` holds the earned upgrades: "together", "hard",
##   "top" (bools), and for the Lantern Line "lit" and "lanterns" (ints). An
##   empty state is the base look. Upgrades always go in the same places:
##   together beside it on the grass (KeepsakeParts.BESIDE), Hard under it (the
##   footing), Together Hard on top.
## - beats(state) is the tap's timeline: the base beat, then one per earned
##   upgrade, each {"beat", "time"}. The base takes at most BASE_MAX seconds and
##   each upgrade at most UPGRADE_MAX.
## - play(beat, anim, parts, state) adds one beat to the tap through anim
##   (presentation/keepsakes/keepsake_anim.gd), times from the beat's start.
## - materials() lists every look it draws, the tap's included, for the GL
##   warm-up's coverage (services/gl_warmup.gd).
## - footing_size() and footprint() give its Hard footing and the ground it
##   covers with every upgrade (x and z in its own frame), for walking and taps.
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const BASE_MAX := 2.5
const UPGRADE_MAX := 0.8
const UPGRADES := ["together", "hard", "top"]

func build(root: Node3D, state: Dictionary) -> Dictionary:
	return {}

## The base beat's length, and each upgrade beat's.
func base_time() -> float:
	return 2.2

func upgrade_time(_beat: String) -> float:
	return 0.7

func beats(state: Dictionary) -> Array:
	var result: Array = [{"beat": "base", "time": base_time()}]
	for beat: String in UPGRADES:
		if state.get(beat, false): result.append({"beat": beat, "time": upgrade_time(beat)})
	return result

func play(_beat: String, _anim: RefCounted, _parts: Dictionary, _state: Dictionary) -> void:
	pass

## Every upgrade on, for the warm-up and the budget checks.
func full_state() -> Dictionary:
	return {"together": true, "hard": true, "top": true}

## Every look the keepsake draws with every upgrade on, at rest and through a
## whole tap: built and played once, unseen, without a Tween.
func materials() -> Array[Material]:
	var state := full_state()
	var root := Node3D.new()
	var parts := build(root, state)
	var anim := Anim.new()
	anim.fx = Node3D.new()
	root.add_child(anim.fx)
	for beat: Dictionary in beats(state): play(str(beat.beat), anim, parts, state)
	var result: Array[Material] = []
	for found: Node in root.find_children("*", "MeshInstance3D", true, false):
		var look := (found as MeshInstance3D).material_override
		if look != null and not result.has(look): result.append(look)
	for look: Material in anim.looks:
		if not result.has(look): result.append(look)
	root.free()
	return result

## Lights a gold piece's gold parts brightly from `at`; the rest pose puts
## them back.
func brighten(anim: RefCounted, piece: Node3D, at: float) -> void:
	for found: Node in piece.get_children():
		if found is MeshInstance3D and (found as MeshInstance3D).material_override == Parts.gold(): anim.set_at(found, "material_override", Parts.gold(true), at)

## How far the keepsake's own parts stand above the ground: the footing's height with Hard.
static func lift(state: Dictionary) -> float:
	return Parts.FOOT_HEIGHT if state.get("hard", false) else 0.0

func footing_size() -> Vector2:
	return Vector2(0.9, 0.74)

## The ground it covers, every upgrade on: from the footing's left edge to the
## together piece's right edge.
func footprint() -> Rect2:
	var foot := footing_size()
	var right := Parts.BESIDE.x + 0.3
	return Rect2(-foot.x * 0.5, -foot.y * 0.5, right + foot.x * 0.5, foot.y)
