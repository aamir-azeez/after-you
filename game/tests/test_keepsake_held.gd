extends SceneTree
## Keepsakes that hold what their tap leaves (presentation/home_keepsake_layer.gd,
## keepsake_anim.gd keep and spin), in every look: the Conservatory's flower
## stays grown with the roof open until the pump is pushed again, when it
## starts small and grows again; the Sleeping Lighthouse stays on, its beam
## turning slowly, until it is pressed again, when it fades off and sleeps.
## Held is not playing (Home stays calm), turns only while Home runs, never
## under Reduce motion or behind a screen, and is gone after a rebuild.
const World = preload("res://presentation/island_world.gd")
const Stage = preload("res://presentation/home_stage.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
const Parts = preload("res://presentation/keepsakes/keepsake_parts.gd")
const Glasshouse = preload("res://presentation/keepsakes/glasshouse.gd")
const Lighthouse = preload("res://presentation/keepsakes/lighthouse.gd")
const Builder = preload("res://presentation/keepsakes/keepsake_builder.gd")
const GLASS := "conservatory"
const LIGHT := "sleeping-lighthouse"
## The looks: [name, with a friend, Hard solo, Hard together].
const LOOKS := [["base", false, false, false], ["together", true, false, false], ["hard", false, true, false], ["together hard", true, true, true]]
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for look: Array in LOOKS:
		await _check_glasshouse(look)
		await _check_lighthouse(look)
	await _check_running()
	await _check_cost()
	print("KEEPSAKE HELD: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## A world and a Home stage showing the two keepsakes in one look.
func _home(look: Array) -> Dictionary:
	Stage._retained_view.clear()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var world := World.new()
	viewport.add_child(world)
	world.load_level(Levels.get_level("first-light"))
	world.set_process(false)
	var stage := Stage.new()
	var theme_source := Main.new()
	theme_source._build_theme()
	stage.theme = theme_source.ui_theme
	theme_source.free()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var items: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		if not item.family in [GLASS, LIGHT]: continue
		var earned := item.duplicate(true)
		earned.solo = true
		earned.friend = bool(look[1]) and item.friend_available
		items.append(earned)
	var hard := {}
	if look[2]:
		for key: String in HardMode.eligible_keys(): hard[key] = {"solo": true, "together": bool(look[3])}
	stage.configure(world, func() -> bool: return true, items)
	stage.set_hard(hard, true)
	viewport.add_child(stage)
	stage.set_process(false)
	for frame in range(6):
		await process_frame
		stage._process(0)
	var layer: Node3D = stage._keepsake_layer
	var until := Time.get_ticks_msec() + 8000
	while layer.settling() and Time.get_ticks_msec() < until: await process_frame
	return {"viewport": viewport, "world": world, "stage": stage, "layer": layer}

func _close(home: Dictionary) -> void:
	if is_instance_valid(home.stage): home.stage.free()
	home.viewport.free()
	await process_frame

## Steps the tap (and its ease back) to its end.
func _finish(layer: Node3D) -> void:
	for guard in range(8):
		if not layer.playing(): return
		(layer._play.tween as Tween).custom_step(10.0)

func _petals(flower: Node3D) -> int:
	return flower.get_children().filter(func(child: Node) -> bool: return child is MeshInstance3D and (child as Node3D).visible and not child.is_queued_for_deletion()).size()

func _check_glasshouse(look: Array) -> void:
	var home := await _home(look)
	var layer: Node3D = home.layer
	var stage: Control = home.stage
	var label := "Conservatory (%s)" % look[0]
	var parts: Dictionary = layer.parts_of(GLASS)
	var flower: Node3D = parts.flower
	var roof: Node3D = parts.roof_left
	var rest_roof := roof.transform
	var buds := _petals(flower)
	_check(stage.play_keepsake(GLASS), "%s plays" % label)
	await _finish(layer)
	await process_frame
	_check(not layer.playing() and not stage.keepsake_playing() and layer.holding(GLASS), "%s ends holding, not playing, so Home stays calm" % label)
	_check(flower.scale.is_equal_approx(Vector3.ONE * Glasshouse.GROWN) and roof.transform != rest_roof, "%s leaves the flower grown under the open roof: %s" % [label, flower.scale])
	_check(_petals(flower) == buds + 6 + int(look[3]), "%s leaves the bloom's petals%s open" % [label, " and its gold middle" if look[3] else ""])
	var tap: Node3D = layer.prop_node(GLASS).get_node_or_null("Tap")
	var blooms := 0 if tap == null else tap.get_children().filter(func(child: Node) -> bool: return (child as Node3D).visible).size()
	_check(tap != null and blooms == (2 if look[2] else 0), "%s keeps only what stays: %d vine flowers open" % [label, blooms])
	if parts.has("can"): _check((parts.can as Node3D).position.y < 0.01, "%s puts the watering can back down" % label)
	_check(is_equal_approx((parts.handle as Node3D).rotation.z, 0.5), "%s puts the pump handle back up" % label)
	_check(not layer.is_processing() and layer._spins.is_empty(), "%s held runs nothing per frame" % label)
	# Pushed again: it starts small and grows again, with one bloom.
	_check(stage.play_keepsake(GLASS) and flower.scale == Vector3.ONE and roof.transform == rest_roof and _petals(flower) == buds, "%s pushed again starts from the small flower under a shut roof" % label)
	await _finish(layer)
	await process_frame
	_check(layer.holding(GLASS) and flower.scale.is_equal_approx(Vector3.ONE * Glasshouse.GROWN) and _petals(flower) == buds + 6 + int(look[3]), "%s grows again to one bloom" % label)
	# Another keepsake tapped as it eases back to rest still leaves it grown.
	stage.play_keepsake(GLASS)
	(layer._play.tween as Tween).custom_step(10.0)
	var easing: bool = layer.playing()
	stage.play_keepsake(LIGHT)
	_check(layer.holding(GLASS) and flower.scale.is_equal_approx(Vector3.ONE * Glasshouse.GROWN) and _petals(flower) == buds + 6 + int(look[3]), "%s tapped away from as it eases back stays grown (easing %s)" % [label, easing])
	layer.stop_play()
	# The pump walked up to in Explore does the same.
	stage._explore_button.pressed.emit()
	var spirit: Node3D = home.world.actors.a
	var inside: Vector3 = layer.trigger_point(GLASS)
	spirit.position = inside
	layer.walked(inside + Vector3(0, 0, 4.0), inside, spirit)
	_check(layer.playing() and flower.scale == Vector3.ONE, "%s walked up to again starts small and grows" % label)
	layer.stop_play()
	_check(not layer.holding(GLASS) and flower.scale == Vector3.ONE and layer.prop_node(GLASS).get_node_or_null("Tap") == null, "%s cut off mid tap goes back to rest, holding nothing" % label)
	stage._explore_back.pressed.emit()
	# Reduce motion: the grown flower at once, and it stays.
	home.world.reduced_motion = true
	stage.play_keepsake(GLASS)
	_check(flower.scale.is_equal_approx(Vector3.ONE * Glasshouse.GROWN), "%s with Reduce motion shows the grown flower at once" % label)
	await _finish(layer)
	_check(layer.holding(GLASS) and flower.scale.is_equal_approx(Vector3.ONE * Glasshouse.GROWN), "%s with Reduce motion stays grown" % label)
	home.world.reduced_motion = false
	# A rebuilt set (the lighthouse gone from the marks) holds nothing.
	var fewer: Array[Dictionary] = []
	fewer.assign(stage._keepsakes.filter(func(item: Dictionary) -> bool: return item.family == GLASS))
	stage.set_hard({}, true)
	stage.set_keepsakes(fewer)
	var until := Time.get_ticks_msec() + 8000
	await process_frame
	while layer.settling() and Time.get_ticks_msec() < until: await process_frame
	var regrown: Node3D = layer.parts_of(GLASS).flower
	_check(layer.playable(GLASS) and not layer.holding(GLASS) and layer._kept.is_empty() and regrown.scale == Vector3.ONE, "%s: a rebuilt Home holds nothing, its flower small" % label)
	await _close(home)

func _check_lighthouse(look: Array) -> void:
	var home := await _home(look)
	var layer: Node3D = home.layer
	var stage: Control = home.stage
	var label := "Lighthouse (%s)" % look[0]
	var parts: Dictionary = layer.parts_of(LIGHT)
	var lamp: MeshInstance3D = parts.lamp
	var lamp_rest := lamp.material_override
	_check(stage.play_keepsake(LIGHT), "%s wakes" % label)
	var tween: Tween = layer._play.tween
	tween.custom_step(0.1)
	var beam: Dictionary = layer._play.anim.made.beam
	var turn: Node3D = beam.turn
	var arm: Node3D = beam.arms[0]
	tween.custom_step(0.4)
	_check(arm.scale.x > Lighthouse.REACH_FROM.x and arm.scale.x < 1.0, "%s's beam reaches out of the lamp: %.2f" % [label, arm.scale.x])
	await _finish(layer)
	await process_frame
	_check(not layer.playing() and not stage.keepsake_playing() and layer.holding(LIGHT), "%s stays on, held, not playing, so Home stays calm" % label)
	_check(lamp.material_override != lamp_rest and turn.is_visible_in_tree() and arm.scale.is_equal_approx(Vector3.ONE), "%s keeps the lamp lit and the beam out" % label)
	_check(beam.arms.size() == (2 if look[2] else 1) and beam.arms.all(func(each: Node3D) -> bool: return each.is_visible_in_tree() and each.scale.is_equal_approx(Vector3.ONE)), "%s keeps %d beam(s) out" % [label, beam.arms.size()])
	var gold: Material = Parts.clear(Lighthouse.BEAM_GOLD, Lighthouse.BEAM_ALPHA, 1.2)
	_check(beam.cones.all(func(cone: MeshInstance3D) -> bool: return (cone.material_override == gold) == bool(look[3])), "%s's beams are %s" % [label, "gold" if look[3] else "plain"])
	_check(not layer.is_processing(), "%s turns without the layer's own frame callback" % label)
	# It turns slowly and steadily, one turn every SWEEP seconds.
	var rate := TAU / Lighthouse.SWEEP
	var angle := turn.rotation.y
	layer.advance_held(0.5)
	_check(is_equal_approx(angle_difference(angle, turn.rotation.y), rate * 0.5), "%s's beam turns a full turn every %.0f s" % [label, Lighthouse.SWEEP])
	# Through Home's stage: only while it runs, never behind a screen or with Reduce motion.
	angle = turn.rotation.y
	stage._process(0.05)
	_check(not is_equal_approx(turn.rotation.y, angle), "%s turns as Home's stage runs" % label)
	angle = turn.rotation.y
	stage._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	stage._process(0.05)
	_check(turn.rotation.y == angle, "%s stands still while the app is in the background" % label)
	stage._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	home.viewport.disable_3d = true
	layer.advance_held(0.5)
	_check(turn.rotation.y == angle, "%s stands still while a screen covers Home" % label)
	home.viewport.disable_3d = false
	home.world.reduced_motion = true
	layer.advance_held(0.5)
	_check(turn.rotation.y == angle, "%s stands still with Reduce motion" % label)
	home.world.reduced_motion = false
	if parts.has("boat_lamp"):
		var boat: MeshInstance3D = parts.boat_lamp
		var bearing := atan2(-Lighthouse.POND.z, Lighthouse.POND.x)
		turn.rotation.y = fposmod(bearing - 0.1, TAU)
		layer.advance_held(0.0)
		var lit := boat.material_override
		turn.rotation.y = fposmod(bearing + PI * 0.5, TAU)
		layer.advance_held(0.0)
		_check(lit == Parts.glow(Parts.LAMP, 2.0) and boat.material_override == Parts.mat(Parts.LAMP_OFF), "%s's boat lamp lights as the beam passes and goes out after" % label)
	# Pressed again: the beams fade back into the lamp as they turn, and it sleeps.
	_check(stage.play_keepsake(LIGHT) and stage.keepsake_playing() and not layer.holding(LIGHT), "%s pressed again plays its fade off" % label)
	angle = turn.rotation.y
	layer.advance_held(0.2)
	_check(not is_equal_approx(turn.rotation.y, angle), "%s keeps turning as it fades" % label)
	(layer._play.tween as Tween).custom_step(0.4)
	_check(arm.scale.x < 1.0, "%s's beam draws back in" % label)
	await _finish(layer)
	await process_frame
	_check(not layer.playing() and not layer.holding(LIGHT) and lamp.material_override == lamp_rest and layer._spins.is_empty(), "%s ends asleep with its lamp out" % label)
	_check(layer.prop_node(LIGHT).get_node_or_null("Tap") == null and not is_instance_valid(turn), "%s frees its beam" % label)
	if parts.has("boat_lamp"): _check((parts.boat_lamp as MeshInstance3D).material_override == Parts.mat(Parts.LAMP_OFF), "%s's boat lamp is out" % label)
	# And on again from the start.
	_check(stage.play_keepsake(LIGHT) and not layer.holding(LIGHT), "%s pressed a third time wakes again" % label)
	await _finish(layer)
	_check(layer.holding(LIGHT), "%s is on again" % label)
	# Another keepsake's tap leaves it on; cut off mid wake it goes back to sleep.
	stage.play_keepsake(GLASS)
	await _finish(layer)
	_check(layer.holding(LIGHT) and layer.holding(GLASS), "%s stays on while the Conservatory plays and holds" % label)
	stage.play_keepsake(LIGHT)
	await _finish(layer)
	stage.play_keepsake(LIGHT)
	(layer._play.tween as Tween).custom_step(0.5)
	stage.play_keepsake(GLASS)
	_check(not layer.holding(LIGHT) and lamp.material_override == lamp_rest, "%s cut off as it wakes goes back to sleep" % label)
	await _finish(layer)
	# Reduce motion: a steady beam, on at once, that never turns.
	home.world.reduced_motion = true
	stage.play_keepsake(LIGHT)
	var still: Dictionary = layer._play.anim.made.beam
	_check((still.arms[0] as Node3D).scale == Vector3.ONE and (still.turn as Node3D).visible, "%s with Reduce motion is on at once" % label)
	await _finish(layer)
	angle = (still.turn as Node3D).rotation.y
	stage._process(0.5)
	_check(layer.holding(LIGHT) and (still.turn as Node3D).rotation.y == angle, "%s with Reduce motion holds a steady beam" % label)
	if parts.has("boat_lamp"): _check((parts.boat_lamp as MeshInstance3D).material_override == Parts.mat(Parts.LAMP_OFF), "%s with Reduce motion lights the boat lamp only with the beam on it" % label)
	stage.play_keepsake(LIGHT)
	await _finish(layer)
	_check(not layer.holding(LIGHT) and lamp.material_override == lamp_rest, "%s with Reduce motion switches off" % label)
	home.world.reduced_motion = false
	# Leaving Home with it on leaves no Tween and nothing turning.
	stage.play_keepsake(LIGHT)
	await _finish(layer)
	stage.free()
	await process_frame
	await process_frame
	_check(get_processed_tweens().is_empty() and not is_instance_valid(layer) and not is_instance_valid(lamp), "%s: leaving Home with it on leaves no Tween and nothing turning" % label)
	home.viewport.free()
	await process_frame

## The wake's turn eases in and hands over at the held speed: the angle a
## frame before the end and the held step after differ by about one held step.
func _check_running() -> void:
	var home := await _home(LOOKS[3])
	var layer: Node3D = home.layer
	layer.play(LIGHT)
	var tween: Tween = layer._play.tween
	var total := 0.0
	for beat: Dictionary in Lighthouse.new().beats(layer.current_props()[LIGHT].state): total += float(beat.time)
	tween.custom_step(total - 0.05)
	var turn: Node3D = layer._play.anim.made.beam.turn
	var before := turn.rotation.y
	tween.custom_step(0.05)
	var eased := turn.rotation.y - before
	await _finish(layer)
	var held := turn.rotation.y
	layer.advance_held(0.05)
	var step := angle_difference(held, turn.rotation.y)
	_check(absf(eased - step) < step * 0.15, "The wake's turn hands over to the held turn at its speed: %.4f then %.4f a twentieth" % [eased, step])
	_check(Lighthouse.new().off_time() <= Builder.UPGRADE_MAX and Lighthouse.new().press_again() == Builder.SWITCH and Glasshouse.new().press_again() == Builder.REPLAY, "The lighthouse switches off within an upgrade beat's time; the Conservatory replays")
	await _close(home)

## What a held keepsake costs a frame: one rotation and a light check.
func _check_cost() -> void:
	var home := await _home(LOOKS[3])
	var layer: Node3D = home.layer
	const CALLS := 20000
	var start := Time.get_ticks_usec()
	for index in range(CALLS): layer.advance_held(1.0 / 30.0)
	var idle := float(Time.get_ticks_usec() - start) / CALLS
	layer.play(LIGHT)
	await _finish(layer)
	layer.play(GLASS)
	await _finish(layer)
	start = Time.get_ticks_usec()
	for index in range(CALLS): layer.advance_held(1.0 / 30.0)
	var held := float(Time.get_ticks_usec() - start) / CALLS
	print("KEEPSAKE HELD COST: %.2f us a frame with nothing held, %.2f us with the lighthouse (two beams, boat lamp) and the flower held" % [idle, held])
	_check(held < 200.0, "Holding them costs well under a frame's budget: %.2f us" % held)
	await _close(home)
