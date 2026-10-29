extends RefCounted
## What every Home keepsake builder does (presentation/keepsakes/*.gd extend
## this). A chapter names its builder in its descriptor's home_keepsake
## (content/chapters/index.gd); the layer (presentation/home_keepsake_layer.gd)
## places, folds, plays and resets it, so a builder is geometry and timing only.
##
## - build(root, state) adds plain geometry under root (no scripts) and returns
##   its moving parts by name (and any plain values play() needs). Everything
##   else is still and folds into Home's shared batches, so a still node is
##   never returned. A moving part may be a container: its own still pieces
##   fold into a batch under it, so a cutaway, a row of bells or a set of
##   windows moves, fades or lights as one part. Parts made for a tap go under
##   anim.fx, in root's frame. `state` holds the earned upgrades: "together",
##   "hard", "top" (bools), and for the Lantern Walk "lanterns" (one bool per
##   island). An empty state is the base look. Each keepsake puts its upgrades
##   where its board draws them; a Hard plinth is a node named "Footing".
## - beats(state) is the tap's timeline: the base beat, then one per earned
##   upgrade, each {"beat", "time"}. The base takes at most BASE_MAX seconds and
##   each upgrade at most UPGRADE_MAX. The layer then eases every part back to
##   its rest pose over SETTLE seconds.
## - play(beat, anim, parts, state) adds one beat to the tap through anim
##   (presentation/keepsakes/keepsake_anim.gd), times from the beat's start.
##   When the pip set it off in Explore, anim.rider is the pip and play() may
##   carry it (anim.carry); a tap from the menu has no rider.
## - materials() lists every look it draws, the tap's and the stay's included,
##   for the GL warm-up's coverage (services/gl_warmup.gd).
## - footprint() is the ground it covers with every upgrade (x and z in its own
##   frame), for taps, naming it in Explore and the layout checks.
##
## How the pip sets it off in Explore, all in its own frame and metres. The
## layer checks these only on a step the pip takes, never at rest:
## - trigger(): {"area": Rect2} plays it when the pip walks in (once, until it
##   has walked out again); {"line": [Vector2, Vector2]} plays it when a step
##   crosses that segment (an arch walked through); {} for none (the Explore
##   action and a tap still play it).
## - stay(): a Rect2 the pip can be inside of (a house, a path under lanterns);
##   arrive(), follow() and depart() run as it walks in, along and out.
##   Rect2() for none. floor() is the height the pip stands at in there.
## - solids(state): what the pip may not walk into; walkways(): extra ground
##   off the islands (a jetty).
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Anim = preload("res://presentation/keepsakes/keepsake_anim.gd")
const BASE_MAX := 2.5
const UPGRADE_MAX := 0.8
## The layer's ease back to rest after the last beat.
const SETTLE := 0.3
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

## Every look the keepsake draws with every upgrade on, at rest, through a
## whole tap with a rider and through a stay: built and played once, unseen,
## without a Tween.
func materials() -> Array[Material]:
	var state := full_state()
	var root := Node3D.new()
	var parts := build(root, state)
	var anim := Anim.new()
	anim.fx = Node3D.new()
	root.add_child(anim.fx)
	anim.rider = Node3D.new()
	root.add_child(anim.rider)
	for beat: Dictionary in beats(state): play(str(beat.beat), anim, parts, state)
	var result: Array[Material] = []
	if stay().has_area():
		var visit := Node3D.new()
		root.add_child(visit)
		arrive(visit, parts, state)
		follow(visit, parts, state, stay().get_center())
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

## The ground it covers, every upgrade on.
func footprint() -> Rect2:
	return Rect2(-0.5, -0.5, 1.0, 1.0)

# --- in Explore ---------------------------------------------------------------------

func trigger() -> Dictionary:
	return {}

func stay() -> Rect2:
	return Rect2()

## The pip walked into the stay: make what it shows under `visit` (freed when
## the pip leaves) and change any part it needs (put back in depart()).
## Returns a cue to play now ("" for none; `state` holds its "sounds").
func arrive(_visit: Node3D, _parts: Dictionary, _state: Dictionary) -> String:
	return ""

## The pip took a step inside the stay, now at `at`. Returns a cue, as arrive().
func follow(_visit: Node3D, _parts: Dictionary, _state: Dictionary, _at: Vector2) -> String:
	return ""

## The pip walked out (or Explore ended): put back what arrive() changed.
func depart(_parts: Dictionary, _state: Dictionary) -> void:
	pass

## The height the pip stands at, at `at` inside the stay.
func floor(_state: Dictionary, _at: Vector2) -> float:
	return 0.0

func solids(_state: Dictionary) -> Array[Rect2]:
	var result: Array[Rect2] = [footprint()]
	return result

func walkways() -> Array[Rect2]:
	return []

## How large a chapter's corner draws its first look (island_world.gd).
func landmark_scale() -> float:
	var size := footprint().size
	return minf(0.62, 1.1 / maxf(0.01, maxf(size.x, size.y)))
