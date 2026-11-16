extends RefCounted
## A chapter screen's ending scene (services/ending_scene.gd): the descriptor's
## "ending" played in the screen's own world once its last turn is done, before
## the completion card. The first time on this phone it plays through with no
## skip (services/ending_seen.gd); after that a tap skips it, and the finished
## chapter's card offers it again (room action "ending"). Hard runs, replays
## and a finished chapter reopened later never start it by themselves.
##
## Host (relay_preview.gd) members it uses: chapter (the descriptor),
## chapter_key, world, sim, overlay, hud, soundscape, settings, controls
## (title_font), mode, _hard_on().
const EndingScene = preload("res://services/ending_scene.gd")
const EndingSeen = preload("res://services/ending_seen.gd")
const EndingPlayer = preload("res://presentation/ending_player.gd")
const MODE := "ending"

var host: Node
## The watched list; tests give it their own file.
var seen := EndingSeen.new()
var _player: Node
var _then: Callable
var _mode_before := ""
var _snapshot: Dictionary = {}

func _init(screen: Node) -> void:
	host = screen

## The chapter's scene data, or {} when it has none (or it does not load).
func scene() -> Dictionary:
	var name := str(host.chapter.get("ending", ""))
	if name.is_empty(): return {}
	var path := "res://content/endings/%s.gd" % name
	if not ResourceLoader.exists(path): return {}
	var script: Variant = load(path)
	var data: Variant = script.get_script_constant_map().get("DATA", {}) if script is Script else {}
	return data if data is Dictionary and EndingScene.check(data).is_empty() else {}

func level() -> String:
	return str(host.chapter_key).get_slice("@", 0)

## Whether the finished chapter's card offers the scene again.
func offered() -> bool:
	return not host._hard_on() and not scene().is_empty()

func playing() -> bool:
	return is_instance_valid(_player) and _player.playing

## Plays the scene, then calls `then`. False (and `then` is not called) when
## there is nothing to play: the caller goes on at once.
func play(then: Callable) -> bool:
	if playing() or host._hard_on() or not is_instance_valid(host.world): return false
	var data := scene()
	if data.is_empty(): return false
	_snapshot = host.sim.snapshot() if host.sim != null else {}
	var player: Node = EndingPlayer.new()
	player.name = "EndingPlayer"
	player.skippable = seen.seen(level())
	player.reduced_motion = bool(host.settings.get("reduced_motion", false))
	player.soundscape = host.soundscape
	if is_instance_valid(host.controls) and host.controls.get("title_font") is Font: player.caption_font = host.controls.title_font
	host.add_child(player)
	for child: Node in host.overlay.get_children():
		host.overlay.remove_child(child)
		child.queue_free()
	host.hud.visible = false
	if not player.start(host.world, data, _snapshot, host.overlay):
		player.queue_free()
		return false
	_player = player
	_then = then
	_mode_before = host.mode
	host.mode = MODE
	player.finished.connect(_finished, CONNECT_ONE_SHOT)
	return true

## Back during the scene: ends it where it is (a first viewing is not marked
## seen, so it stays a must-watch). True when a scene was playing.
func back() -> bool:
	if not playing(): return false
	_player.stop()
	return true

func _finished(watched: bool) -> void:
	if watched: seen.mark(level())
	var player := _player
	_player = null
	if is_instance_valid(player): player.queue_free()
	host.mode = _mode_before
	host.overlay.visible = false
	if is_instance_valid(host.world) and not _snapshot.is_empty(): host.world.present(_snapshot, true)
	var then := _then
	_then = Callable()
	if then.is_valid(): then.call()
