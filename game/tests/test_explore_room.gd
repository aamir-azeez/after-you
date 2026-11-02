extends SceneTree
## Room to walk in Explore on Home (presentation/home_keepsake_layer.gd): the
## pip never has to squeeze between the keepsakes, slides along what it walks
## into, and goes into the Little House only through its door once it opens.
## - Room: the ground the pip's middle may stand on (walkable()) is laid on a
##   CELL grid, and each cell's room is how far it is from ground the middle
##   may not stand on. From the explorer's start, every way across the islands,
##   over each bridge and up to each keepsake keeps ROUTE_ROOM on both sides of
##   the pip's middle; a way into a stay (the house's door) keeps DOOR_ROOM.
##   Ground with that room that is reached only through less, a squeeze, fails
##   and is named by where it lies. Checked with no upgrades, each upgrade on
##   its own and all of them, since Hard plinths and Together pieces add solids.
## - Sliding: pushed at a slant into a turned keepsake's flat side or a round
##   one, the pip runs along it and never walks in; pushed straight in, it
##   stands still.
## - The door: shut, it stops the pip; walking up to it, from the path or from
##   inside, opens it before the pip gets there; the Explore action opens it
##   too; a pip inside or in the doorway when it shuts always walks out.
const World = preload("res://presentation/island_world.gd")
const Stage = preload("res://presentation/home_stage.gd")
const Layer = preload("res://presentation/home_keepsake_layer.gd")
const Catalog = preload("res://services/home_keepsake_catalog.gd")
const HardMode = preload("res://services/hard_mode.gd")
const Isles = preload("res://presentation/keepsakes/home_isles.gd")
const House = preload("res://presentation/keepsakes/little_house.gd")
const TidePool = preload("res://presentation/keepsakes/tide_pool.gd")
const Levels = preload("res://core/levels.gd")
const Main = preload("res://main.gd")
## Room each side of the pip's middle along every way: two solids stand at
## least 2 x (ROUTE_ROOM + Layer.WALK_CLEARANCE) = 0.64 m apart, wider than
## the pip is drawn (0.6 m across its shadow), so no way needs careful steering.
const ROUTE_ROOM := 0.2
## Room each side of the pip's middle through a keepsake's door. The Little
## House's doorway is drawn 0.55 m wide (its chapter draws the same house),
## which leaves the middle about 0.15 m each side; the grid reads a little
## under that through a turned house, so the check asks for 0.1.
const DOOR_ROOM := 0.1
const CELL := 0.05
## Ground with room smaller than this (square metres) is a sliver, not a place.
const POCKET := 0.05
const HOUSE_ID := "a-house-for-two"
const OPEN := -1.45

## Room checks the Home layout still fails, by key ("look|what"). Each still
## runs: it prints as KNOWN while it fails, and fails the suite once it
## passes, until it is taken off this list. None: this layout clears them all.
const KNOWN_SQUEEZES: Array[String] = []

var checks := 0
var failures := 0
## Every room key checked, so a listed squeeze that no check reaches fails too.
var room_keys := {}

func _initialize() -> void: _run.call_deferred()

func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
		print("FAIL: " + message)

## A room check, by `key`: a known squeeze is reported, never hidden.
func _room(ok: bool, key: String, message: String) -> void:
	room_keys[key] = true
	if not KNOWN_SQUEEZES.has(key):
		_check(ok, "%s [%s]" % [message, key])
		return
	checks += 1
	if ok:
		failures += 1
		push_error("%s now has room: take it off KNOWN_SQUEEZES" % key)
	else:
		print("KNOWN: %s [%s]" % [message, key])

func _run() -> void:
	await _check_room("no upgrades", false, {})
	await _check_room("Together", true, {})
	await _check_room("Hard", false, _hard(false))
	await _check_room("every upgrade", true, _hard(true))
	await _check_slide()
	await _check_arch_walks()
	for key: String in KNOWN_SQUEEZES: _check(room_keys.has(key), "%s is listed as a known squeeze but no check reaches it: take it off KNOWN_SQUEEZES" % key)
	await _check_door()
	print("EXPLORE ROOM: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

# --- Home ----------------------------------------------------------------------------

func _items(friend: bool) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for item: Dictionary in Catalog.all():
		var earned := item.duplicate(true)
		earned.solo = true
		earned.friend = friend and item.friend_available
		all.append(earned)
	return all

func _hard(together: bool) -> Dictionary:
	var hard := {}
	for key: String in HardMode.eligible_keys(): hard[key] = {"solo": true, "together": together}
	return hard

func _home(friend: bool, hard: Dictionary) -> Dictionary:
	Stage._retained_view.clear()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1560, 720)
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
	stage.configure(world, func() -> bool: return true, _items(friend), false)
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
	home.stage.free()
	home.viewport.free()
	await process_frame

## The Home bridge drawn up, as Explore raises it for a pip walking over.
func _raise_bridge(world: Node3D) -> void:
	world.home_bridge_raised = true
	for frame in range(120):
		if world.bridge_parts.all(func(plank: Node3D) -> bool: return plank.position.y >= World.BRIDGE_RAISED_Y - Layer.DECK_TOLERANCE): return
		world._process(0.1)

func _frames(stage: Control, count: int) -> void:
	for frame in range(count): stage._process(1.0 / 30.0)

## The stick push that walks the pip along `direction` on the ground.
func _push_toward(direction: Vector3) -> Vector2:
	var across := Vector3(0.832, 0, -0.555)
	var away := Vector3(-0.555, 0, -0.832)
	return Vector2(direction.dot(across), -direction.dot(away)).normalized()

# --- room ------------------------------------------------------------------------------

func _check_room(name: String, friend: bool, hard: Dictionary) -> void:
	var home := await _home(friend, hard)
	var layer: Node3D = home.layer
	var world: Node3D = home.world
	_raise_bridge(world)
	# The house as its door leaves it open.
	var door: Node3D = layer.parts_of(HOUSE_ID).get("door")
	_check(door != null, "%s: the house has its door" % name)
	if door != null: door.rotation.y = OPEN
	var grid := _grid(layer)
	var start: Vector3 = world.actors.a.position
	var route := _reach(grid, start, ROUTE_ROOM)
	var door_reach := _reach(grid, start, DOOR_ROOM)
	# Every piece of ground with room is reached with that room, or (a stay) through its door.
	# One check per island and nearest keepsake: all ground there with room is reached.
	var squeezed := {}
	for pocket: Dictionary in _pockets(grid, route):
		var inside := ""
		for id: String in layer.shown_ids():
			if (layer._frames[id].stay as Rect2).has_area() and (layer._frames[id].stay as Rect2).has_point(layer._local(id, pocket.at)): inside = id
		var by_door := not inside.is_empty() and _any(pocket.cells, door_reach)
		if by_door: continue
		var key := "%s|squeeze on %s by %s" % [name, _island_of(layer, pocket.at), layer.nearest(pocket.at, INF)]
		var line := "%s: ground with room round %s (%.2f m2) is reached only through a squeeze" % [name, _where(pocket.at), pocket.area]
		squeezed[key] = line if not squeezed.has(key) else "%s; %s" % [squeezed[key], line]
	for key: String in squeezed: _room(false, key, squeezed[key])
	for key: String in KNOWN_SQUEEZES:
		if key.begins_with(name + "|squeeze on ") and not squeezed.has(key): _room(true, key, "")
	# Each bridge and each keepsake is reached with room.
	var crossings: Array = [[Vector2(0, 0), "Home"]]
	for id: String in Isles.ISLES: crossings.append([(Isles.ISLES[id].bridge[0] as Vector2).lerp(Isles.ISLES[id].bridge[1], 0.5), id])
	for crossing: Array in crossings:
		var cell := _cell(grid, Vector3(crossing[0].x, 0, crossing[0].y))
		_room(cell >= 0 and route.has(cell), "%s|bridge %s" % [name, crossing[1]], "%s: the %s bridge is reached with room" % [name, crossing[1]])
	for id: String in layer.shown_ids():
		var frame: Dictionary = layer._frames[id]
		var trigger: Dictionary = frame.trigger
		var near := false
		var in_trigger := not trigger.has("area")
		var in_stay := not (frame.stay as Rect2).has_area()
		var reach: Array = frame.reach
		for cell: int in door_reach:
			var at := _point(grid, cell)
			if Vector2(at.x, at.z).distance_to(reach[0]) > float(reach[1]) + Stage.EXPLORE_NOTICE: continue
			var local: Vector2 = layer._local(id, at)
			if route.has(cell):
				near = near or layer.distance(id, at) <= Stage.EXPLORE_NOTICE
				in_trigger = in_trigger or (trigger.area as Rect2).has_point(local)
			in_stay = in_stay or (frame.stay as Rect2).has_point(local)
		_room(near, "%s|near %s" % [name, id], "%s: the pip reaches %s with room, near enough for its action" % [name, id])
		_room(in_trigger, "%s|trigger %s" % [name, id], "%s: the pip reaches %s's trigger with room" % [name, id])
		_room(in_stay, "%s|stay %s" % [name, id], "%s: the pip reaches into %s's stay" % [name, id])
		if trigger.has("line"):
			# An arch: the middle of the way through it has room.
			var middle: Vector3 = layer.slot_transform(id) * Vector3((trigger.line[0].x + trigger.line[1].x) * 0.5, 0, (trigger.line[0].y + trigger.line[1].y) * 0.5)
			var cell := _cell(grid, middle)
			_room(cell >= 0 and route.has(cell), "%s|way through %s" % [name, id], "%s: the way through %s has room" % [name, id])
	await _close(home)

## The ground on a CELL grid round every island: {"origin", "size", "room"},
## room per cell in metres (0 where the pip's middle may not stand).
func _grid(layer: Node3D) -> Dictionary:
	var bounds := Rect2()
	for id: Variant in layer.island_ids():
		var floor: Rect2 = layer.island_floor(str(id))
		bounds = floor if not bounds.has_area() else bounds.merge(floor)
	bounds = bounds.grow(1.2)
	var size := Vector2i(ceili(bounds.size.x / CELL), ceili(bounds.size.y / CELL))
	# Chamfer distance in fifths of a cell (5, 7, 11): within 2% of the true distance.
	var far := 1 << 20
	var room := PackedInt32Array()
	room.resize(size.x * size.y)
	for y in range(size.y):
		for x in range(size.x):
			var at := Vector3(bounds.position.x + (x + 0.5) * CELL, 0, bounds.position.y + (y + 0.5) * CELL)
			room[y * size.x + x] = far if layer._ground(at) and layer.walkable(at) else 0
	var forward: Array[Vector3i] = [Vector3i(-1, 0, 5), Vector3i(0, -1, 5), Vector3i(-1, -1, 7), Vector3i(1, -1, 7), Vector3i(-1, -2, 11), Vector3i(1, -2, 11), Vector3i(-2, -1, 11), Vector3i(2, -1, 11)]
	for pass_index in range(2):
		var sign := 1 if pass_index == 0 else -1
		var ys := range(size.y) if sign == 1 else range(size.y - 1, -1, -1)
		var xs := range(size.x) if sign == 1 else range(size.x - 1, -1, -1)
		for y: int in ys:
			for x: int in xs:
				var index := y * size.x + x
				var best: int = room[index]
				if best == 0: continue
				for offset: Vector3i in forward:
					var ox := x + offset.x * sign
					var oy := y + offset.y * sign
					var other := 0 if ox < 0 or oy < 0 or ox >= size.x or oy >= size.y else room[oy * size.x + ox]
					best = mini(best, other + offset.z)
				room[index] = best
	var metres := PackedFloat32Array()
	metres.resize(room.size())
	for index in range(room.size()): metres[index] = maxf(0.0, room[index] * CELL / 5.0 - CELL * 0.5)
	return {"origin": bounds.position, "size": size, "room": metres}

func _cell(grid: Dictionary, at: Vector3) -> int:
	var x := floori((at.x - grid.origin.x) / CELL)
	var y := floori((at.z - grid.origin.y) / CELL)
	if x < 0 or y < 0 or x >= grid.size.x or y >= grid.size.y: return -1
	return y * grid.size.x + x

func _point(grid: Dictionary, cell: int) -> Vector3:
	return Vector3(grid.origin.x + (cell % grid.size.x + 0.5) * CELL, 0, grid.origin.y + (cell / grid.size.x + 0.5) * CELL)

## Every cell the pip's middle reaches from `start` keeping `need` room: {cell: true}.
func _reach(grid: Dictionary, start: Vector3, need: float) -> Dictionary:
	var room: PackedFloat32Array = grid.room
	var first := _cell(grid, start)
	# The start may stand nearer something; begin from the nearest cell with room.
	var seen := {first: true}
	var queue: Array[int] = [first]
	var head := 0
	while head < queue.size() and room[queue[head]] < need:
		var cell := queue[head]
		head += 1
		for next: int in _around(grid, cell):
			if not seen.has(next) and room[next] > 0.0:
				seen[next] = true
				queue.append(next)
	var reached := {}
	if head >= queue.size(): return reached
	queue = [queue[head]]
	reached[queue[0]] = true
	head = 0
	while head < queue.size():
		var cell := queue[head]
		head += 1
		for next: int in _around(grid, cell):
			if not reached.has(next) and room[next] >= need:
				reached[next] = true
				queue.append(next)
	return reached

func _around(grid: Dictionary, cell: int) -> Array[int]:
	var width: int = grid.size.x
	var x := cell % width
	var result: Array[int] = []
	if x > 0: result.append(cell - 1)
	if x < width - 1: result.append(cell + 1)
	if cell >= width: result.append(cell - width)
	if cell + width < (grid.room as PackedFloat32Array).size(): result.append(cell + width)
	return result

## Pieces of ground with ROUTE_ROOM that `reached` misses, each {"at", "area", "cells"}.
func _pockets(grid: Dictionary, reached: Dictionary) -> Array[Dictionary]:
	var room: PackedFloat32Array = grid.room
	var seen := {}
	var result: Array[Dictionary] = []
	for cell in range(room.size()):
		if room[cell] < ROUTE_ROOM or reached.has(cell) or seen.has(cell): continue
		var cells: Array[int] = [cell]
		seen[cell] = true
		var head := 0
		var middle := Vector3.ZERO
		while head < cells.size():
			var at := cells[head]
			head += 1
			middle += _point(grid, at)
			for next: int in _around(grid, at):
				if room[next] >= ROUTE_ROOM and not seen.has(next):
					seen[next] = true
					cells.append(next)
		var area := cells.size() * CELL * CELL
		if area >= POCKET: result.append({"at": middle / cells.size(), "area": area, "cells": cells})
	return result

## The island or isle a point stands on, for naming a squeeze.
func _island_of(layer: Node3D, at: Vector3) -> String:
	for id: Variant in layer.island_ids():
		if layer.island_floor(str(id)).grow(0.3).has_point(Vector2(at.x, at.z)): return str(id)
	return "a walkway"

func _any(cells: Array[int], reached: Dictionary) -> bool:
	for cell: int in cells:
		if reached.has(cell): return true
	return false

func _where(at: Vector3) -> String:
	return "(%.2f, %.2f)" % [at.x, at.z]

# --- sliding ---------------------------------------------------------------------------

## Pushed into the Conservatory's side at a slant, the pip runs along it.
func _check_slide() -> void:
	var home := await _home(true, _hard(true))
	var stage: Control = home.stage
	var layer: Node3D = home.layer
	var spirit: Node3D = home.world.actors.a
	stage._explore_button.pressed.emit()
	var placed: Transform3D = layer.slot_transform("conservatory")
	var solid: Rect2 = layer.current_props()["conservatory"].solids[0]
	var start := placed * Vector3(solid.get_center().x - 0.4, 0, solid.end.y + Layer.WALK_CLEARANCE + 0.02)
	spirit.position = start
	stage._explore_last = start
	_check(layer.walkable(start), "The pip starts on open ground in front of the Conservatory")
	# Into the front face, slanted along it.
	stage._stick.value = _push_toward(placed.basis * Vector3(0.5, 0, -1.0).normalized())
	var never_in := true
	for frame in range(20):
		_frames(stage, 1)
		never_in = never_in and not layer.blocks(spirit.position, Layer.WALK_CLEARANCE - 0.005)
	stage._stick.value = Vector2.ZERO
	var moved: Vector3 = placed.affine_inverse() * spirit.position - placed.affine_inverse() * start
	_check(never_in, "Sliding along the Conservatory never walks the pip into it")
	_check(moved.x > 0.25 and absf(moved.z) < 0.05, "Pushed at a slant into the Conservatory's side, the pip slides along it: %s" % moved)
	# Straight in, it stands still: no creeping back and snapping forward.
	var held := spirit.position
	stage._stick.value = _push_toward(placed.basis * Vector3(0, 0, -1))
	var drift := 0.0
	for frame in range(30):
		_frames(stage, 1)
		drift = maxf(drift, spirit.position.distance_to(held))
	stage._stick.value = Vector2.ZERO
	_check(drift < 0.01, "Pushed straight into the Conservatory, the pip stands still: %.3f" % drift)
	# Round the Turn of the Tide's round rim.
	var pool: Transform3D = layer.slot_transform("turn-of-the-tide")
	var rim := TidePool.RADIUS + 0.08 + Layer.WALK_CLEARANCE + 0.03
	# From its left, clear of its weight, slanting in and back.
	start = pool * Vector3(-rim, 0, 0)
	spirit.position = start
	stage._explore_last = start
	stage._stick.value = _push_toward(pool.basis * Vector3(1, 0, -0.6).normalized())
	never_in = true
	for frame in range(20):
		_frames(stage, 1)
		never_in = never_in and not layer.blocks(spirit.position, Layer.WALK_CLEARANCE - 0.005)
	stage._stick.value = Vector2.ZERO
	_check(never_in and spirit.position.distance_to(start) > 0.3, "Pushed at a slant into the round tide pool, the pip runs round it: %.2f" % spirit.position.distance_to(start))
	stage._explore_back.pressed.emit()
	await _close(home)

## The owner's walk: off the Home bridge through the Bell Arch, a push aimed
## at the tide bridge and at the Journey bridge gets there, sliding round
## whatever stands in the way, with every upgrade on.
func _check_arch_walks() -> void:
	var home := await _home(true, _hard(true))
	var stage: Control = home.stage
	var layer: Node3D = home.layer
	var world: Node3D = home.world
	var spirit: Node3D = world.actors.a
	stage._explore_button.pressed.emit()
	for walk: Array in [["the tide bridge", Vector3(6.2, 0, 0)], ["the Journey bridge", Vector3(3.2, 0, -3.6)]]:
		var start := Vector3(0.8, 0, 0)
		spirit.position = start
		stage._explore_last = start
		_raise_bridge(world)
		var goal: Vector3 = walk[1]
		var arrived := -1
		var never_in := true
		for frame in range(200):
			var toward := goal - spirit.position
			toward.y = 0
			if toward.length() < 0.3:
				arrived = frame
				break
			# A thumb on the stick aimed at the bridge.
			stage._stick.value = _push_toward(toward.normalized())
			_tick(stage, layer)
			never_in = never_in and not layer.blocks(spirit.position, Layer.WALK_CLEARANCE - 0.005)
		stage._stick.value = Vector2.ZERO
		layer.stop_play()
		_check(never_in, "Walking through the Bell Arch toward %s never walks the pip into a keepsake" % walk[0])
		_room(arrived >= 0, "walk|%s" % walk[0], "A push aimed through the Bell Arch reaches %s: frame %d, at %s" % [walk[0], arrived, spirit.position])
	stage._explore_back.pressed.emit()
	await _close(home)

# --- the door ---------------------------------------------------------------------------

## One frame of Explore, the keepsake playing stepped along with it.
func _tick(stage: Control, layer: Node3D) -> void:
	stage._process(1.0 / 30.0)
	var tween: Variant = layer._play.get("tween")
	if tween is Tween and (tween as Tween).is_valid(): (tween as Tween).custom_step(1.0 / 30.0)

## Walks the pip from `from` metres out of the house's doorway (inside when
## negative) straight through it: {"crossed", "early": crossed while it was shut}.
func _through(stage: Control, layer: Node3D, from: float, frames: int) -> Dictionary:
	var spirit: Node3D = stage._actors.a
	var placed: Transform3D = layer.slot_transform(HOUSE_ID)
	var door: Node3D = layer.parts_of(HOUSE_ID).door
	var front := House.D * 0.5 * House.SIZE
	spirit.position = placed * Vector3((House.DOOR_X + House.DOOR_W * 0.5) * House.SIZE, 0, front + from)
	stage._explore_last = spirit.position
	stage._stick.value = _push_toward(placed.basis * Vector3(0, 0, -signf(from)))
	var result := {"crossed": false, "early": false}
	for frame in range(frames):
		_tick(stage, layer)
		var out := (placed.affine_inverse() * spirit.position).z - front
		if signf(out) != signf(from):
			result.early = result.early or absf(door.rotation.y) < House.OPEN_ENOUGH
			result.crossed = true
			if absf(out) > 0.35: break
	stage._stick.value = Vector2.ZERO
	return result

func _check_door() -> void:
	var builder := House.new()
	var front := House.D * 0.5 * House.SIZE
	var mid := (House.DOOR_X + House.DOOR_W * 0.5) * House.SIZE
	_check(builder.gates({}, {}, Vector2(mid, front + 0.3)).size() == 1, "An unearned house's door never opens")
	_check(builder.gates({}, {}, Vector2(mid, front - 0.3)).is_empty(), "A pip inside is never shut in")
	var home := await _home(true, _hard(true))
	var stage: Control = home.stage
	var world: Node3D = home.world
	var layer: Node3D = home.layer
	var spirit: Node3D = world.actors.a
	stage._explore_button.pressed.emit()
	var placed: Transform3D = layer.slot_transform(HOUSE_ID)
	var door: Node3D = layer.parts_of(HOUSE_ID).door
	var at := func(out: float) -> Vector3: return placed * Vector3(mid, 0, front + out)
	var inward := placed.basis * Vector3(0, 0, -1)
	_check(not layer.can_step(at.call(0.21), at.call(0.15)), "The shut door stops the pip")
	# Walking up the path: the door opens before the pip reaches it, and in it goes.
	var went := _through(stage, layer, 1.4, 60)
	_check(went.crossed and not went.early, "Walking up the path opens the door first, then the pip walks in: %s" % went)
	_check(layer.staying() == HOUSE_ID, "and is in the house")
	# The door shuts on a pip just inside, still in the doorway's trigger: it walks out all the same.
	layer.stop_play()
	_check(absf(door.rotation.y) < House.OPEN_ENOUGH, "The door shuts again once its play ends")
	spirit.position = at.call(-0.3)
	stage._explore_last = spirit.position
	stage._stick.value = _push_toward(-inward)
	for frame in range(30): _tick(stage, layer)
	stage._stick.value = Vector2.ZERO
	var out := (placed.affine_inverse() * spirit.position).z - front
	_check(out > 0.3, "A pip inside when the door shuts is never shut in: %.2f" % out)
	layer.stop_play()
	# Walking up to the door from deep inside opens it as the pip comes.
	var left := _through(stage, layer, -1.6, 90)
	_check(left.crossed and not left.early, "Walking up to the door from inside opens it before the pip goes out: %s" % left)
	layer.stop_play()
	# Shut on a pip in the doorway: it steps out either way.
	var doorway: Vector3 = at.call(0.02)
	_check(layer.can_step(doorway, doorway + inward * 0.05) and layer.can_step(doorway, doorway - inward * 0.05), "A pip in the doorway when the door shuts steps out either way")
	# The Explore action opens it as well.
	spirit.position = at.call(1.0)
	stage._explore_last = spirit.position
	layer.select_id(HOUSE_ID)
	stage._update_explore_action()
	_check(stage._explore_action.visible, "Standing at the house offers its action")
	stage._explore_action.pressed.emit()
	for frame in range(10): _tick(stage, layer)
	_check(absf(door.rotation.y) >= House.OPEN_ENOUGH and layer.can_step(at.call(0.21), at.call(0.15)), "The Explore action opens the door, and the pip may walk in")
	layer.stop_play()
	# Waiting at the door until its play is over, the pip pushes it open again.
	_through(stage, layer, 1.4, 11)
	layer.stop_play()
	var waited := _through(stage, layer, 0.5, 40)
	_check(waited.crossed and not waited.early, "A pip that waited at the door past its play pushes it open: %s" % waited)
	layer.stop_play()
	# Walking up while another keepsake plays: the door opens once that one ends.
	layer.play("the-wishing-well")
	var after := _through(stage, layer, 1.4, 240)
	_check(after.crossed and not after.early, "A pip that came while another keepsake played gets in once it ends: %s" % after)
	layer.stop_play()
	# Reduce motion: the door stands open the moment the pip walks up.
	world.reduced_motion = true
	var reduced := _through(stage, layer, 1.4, 60)
	_check(reduced.crossed and not reduced.early, "With Reduce motion the door opens as the pip walks up, and in it goes: %s" % reduced)
	world.reduced_motion = false
	layer.stop_play()
	stage._explore_back.pressed.emit()
	await _close(home)
