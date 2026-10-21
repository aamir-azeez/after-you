extends SceneTree
## The chapter thumbnail shelf (presentation/chapter_thumbnail_shelf.gd): a
## card's picture loads off the main thread and fills in, a kept one shows at
## once, idle Home warms the page's pictures ahead, and nothing is left on the
## loader when a card or the shelf goes. The room hub's pictures come
## through it the same way.
const Shelf = preload("res://presentation/chapter_thumbnail_shelf.gd")
const Catalog = preload("res://services/chapter_thumbnail_catalog.gd")
const Hub = preload("res://presentation/room_hub_screen.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)

## A card picture filled through the shelf, not yet in a tree.
func _picture(path: String) -> TextureRect:
	var rect := TextureRect.new()
	Shelf.fill(rect, path)
	return rect

## Waits a frame at a time, at most five seconds, until condition holds.
func _until(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await process_frame
	return condition.call()

func _gone_from_loader(path: String) -> bool:
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE

func _run() -> void:
	var paths: Array[String] = []
	for key: String in Catalog.keys(): paths.append(Catalog.path(key))
	_check(paths.size() >= 8, "The catalog has pictures enough for these checks")
	var holder := Control.new()
	root.add_child(holder)

	# With no shelf in the tree, a card loads its picture as it joins, as before.
	var plain := _picture(paths[0])
	_check(plain.texture == null, "A card's picture waits for its tree")
	holder.add_child(plain)
	_check(plain.texture != null, "With no shelf in the tree, the picture loads as the card joins it")
	plain.free()

	var shelf := Shelf.new()
	shelf.idle = func() -> bool: return false
	# A long fade, so a slow frame cannot finish it before it is checked.
	shelf.fade_seconds = 1.0
	root.add_child(shelf)
	var first := _picture(paths[1])
	holder.add_child(first)
	_check(first.texture == null and shelf.busy(), "A card never loads its picture in the frame it joins")
	_check(await _until(func() -> bool: return first.texture != null), "The picture arrives from the loader's threads")
	_check(first.modulate.a < 1.0, "and fades in rather than popping")
	_check(await _until(func() -> bool: return first.modulate.a == 1.0), "up to full")
	_check(shelf.keeps(paths[1]) and _gone_from_loader(paths[1]), "The shelf keeps it and the loader holds nothing more")
	var again := _picture(paths[1])
	holder.add_child(again)
	_check(again.texture == first.texture and again.modulate.a == 1.0, "A kept picture shows at once, with no fade")

	# A card freed while its picture loads.
	var dropped := _picture(paths[2])
	holder.add_child(dropped)
	dropped.free()
	_check(await _until(func() -> bool: return not shelf.busy()), "A load whose card has gone still finishes")
	_check(shelf.keeps(paths[2]) and _gone_from_loader(paths[2]), "and is collected from the loader")

	# Two cards waiting: both fill, one load at a time.
	var one := _picture(paths[3])
	var two := _picture(paths[4])
	holder.add_child(one)
	holder.add_child(two)
	var overlap := [false]
	var watch := func():
		if not _gone_from_loader(paths[3]) and not _gone_from_loader(paths[4]): overlap[0] = true
	process_frame.connect(watch)
	_check(await _until(func() -> bool: return one.texture != null and two.texture != null), "Every waiting card fills")
	process_frame.disconnect(watch)
	_check(not overlap[0], "The shelf loads one picture at a time")

	# The shelf leaving while a picture loads.
	var leaving := _picture(paths[5])
	holder.add_child(leaving)
	_check(await _until(func() -> bool: return shelf._loading == paths[5]), "The shelf starts the next picture")
	root.remove_child(shelf)
	_check(_gone_from_loader(paths[5]), "A shelf that leaves mid load collects it, so the loader keeps nothing")
	_check(leaving.texture == null, "and its card stays an empty frame")
	shelf.free()
	leaving.free()

	# Warming ahead while Home is idle.
	var warm := Shelf.new()
	var state := {"idle": false, "paused": false, "playing": false}
	warm.idle = func() -> bool: return state.idle
	warm.paused = func() -> bool: return state.paused
	warm.playing = func() -> bool: return state.playing
	warm.warm_paths = func() -> Array: return [paths[6], paths[7]]
	warm.idle_seconds = 0.05
	root.add_child(warm)
	await create_timer(0.15).timeout
	_check(not warm.keeps(paths[6]) and _gone_from_loader(paths[6]), "Nothing is warmed while Home is not idle")
	state.idle = true
	state.paused = true
	await create_timer(0.15).timeout
	_check(not warm.keeps(paths[6]) and _gone_from_loader(paths[6]), "Nothing starts while a chapter opens")
	state.paused = false
	_check(await _until(func() -> bool: return warm.keeps(paths[6]) and warm.keeps(paths[7])), "Idle Home loads the page's pictures ahead")
	var warmed := _picture(paths[7])
	holder.add_child(warmed)
	_check(warmed.texture != null and warmed.modulate.a == 1.0, "A card for a warmed picture shows it on its first frame")

	# A world playing inside the owner (an online chapter): every picture goes.
	state.playing = true
	_check(await _until(func() -> bool: return not warm.keeps(paths[6]) and not warm.keeps(paths[7])), "While a chapter plays inside Main, the shelf keeps no picture")
	var during := _picture(paths[6])
	holder.add_child(during)
	await create_timer(0.15).timeout
	_check(during.texture == null and _gone_from_loader(paths[6]), "and loads none")
	state.playing = false
	_check(await _until(func() -> bool: return during.texture != null), "A card that waited through it fills once play ends")
	_check(await _until(func() -> bool: return warm.keeps(paths[7])), "and idle Home warms the page again")

	# The room hub's hero and room card pictures, through the same shelf.
	var keys := Catalog.keys()
	_check(Catalog.has_picture(keys[0]) and not Catalog.has_picture("no-such-chapter"), "The catalog says which chapters have a picture without loading one")
	warm.fade_seconds = 1.0
	var hub := Hub.new()
	hub.thumbnail_for = func(key: String) -> String: return Catalog.path(key)
	var offered: Array[Dictionary] = [{"key": keys[0], "title": "First"}, {"key": keys[1], "title": "Second"}, {"key": "no-such-chapter", "title": "Bare"}]
	hub.set_chapters(offered)
	root.add_child(hub)
	_check(hub._hero.texture == null and warm.busy(), "The hub never loads its picture in the frame it opens")
	_check(await _until(func() -> bool: return hub._hero.texture != null), "The hub's picture arrives from the loader's threads")
	_check(hub._hero.modulate.a < 1.0 and hub._hero.texture == warm._kept.get(paths[0]), "and fades in, as a card's does")
	hub._selected_key = keys[1]
	hub._update_hero()
	hub._selected_key = "no-such-chapter"
	hub._update_hero()
	_check(await _until(func() -> bool: return not warm.busy()), "The last chapter's picture finishes loading")
	_check(hub._hero.texture == null, "but never shows on a chapter with none")
	hub._selected_key = keys[0]
	hub._update_hero()
	_check(hub._hero.texture == warm._kept.get(paths[0]), "A kept picture shows on the hub at once")
	var card_picture: Control = hub._room_picture(keys[2], Vector2(154, 96))
	_check(hub._room_picture("no-such-chapter", Vector2(154, 96)) == null, "A room for a chapter with no picture gets no frame")
	holder.add_child(card_picture)
	var card_image := card_picture.get_child(0) as TextureRect
	_check(card_image.texture == null, "A room card never loads its picture in the frame it joins")
	_check(await _until(func() -> bool: return card_image.texture != null), "and it fills in through the shelf")
	hub.free()

	holder.free()
	warm.free()
	print("CHAPTER THUMBNAIL SHELF: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
