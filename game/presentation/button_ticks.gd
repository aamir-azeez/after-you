extends Node
## Every button's soft tick: one hook on the scene tree for the whole app, so no
## screen wires its own. Main installs it once under the tree's root, where it
## outlives every scene change (chapters open with change_scene).
##
## A button that enters the tree anywhere gets its confirmed press ("pressed":
## a release over the button or an accepted key, never hover, focus or the
## press going down) played as the fixed cue CUE on the soundscape of the
## nearest screen above it, a node with a `soundscape` (Main, a chapter screen,
## a shared replay). So the Sound setting and backgrounding apply, and two ticks
## in one frame (a press that also opens a card of buttons) sound once
## (soundscape play_fixed_cue).
##
## quiet() a button or a container to keep it silent:
## - the in-run controls (presentation/chapter_controls.gd's HUD, Main's throw
##   and finish), whose presses make the run's own cues;
## - a button whose press plays its own sound instead (Wear, the Wardrobe's Buy,
##   a keepsake, a reaction face).
## A button entering the tree walks up once (FOUND); a press walks up again.
const CUE := "ui_tap"
const NODE_NAME := "ButtonTicks"
const QUIET := "button_tick_quiet"
## Set once a button's press is hooked, so a button moved in the tree is hooked once.
const HOOKED := "button_tick_hooked"
## The soundscape a button found when it entered the tree (a weakref), for a
## press whose own handler ran first and took the button out of the tree (a
## card that closes itself).
const FOUND := "button_tick_soundscape"

## Adds the hook under `tree`'s root once; later calls change nothing.
static func install(tree: SceneTree) -> void:
	if tree == null or tree.root.get_node_or_null(NODE_NAME) != null: return
	var ticks: Node = load("res://presentation/button_ticks.gd").new()
	ticks.name = NODE_NAME
	# The root may be busy setting up its children (Main's _ready): add it next.
	tree.root.add_child.call_deferred(ticks)

## Keeps `node` and every button under it silent.
static func quiet(node: Node) -> void:
	if node != null: node.set_meta(QUIET, true)

## The soundscape a press of `button` ticks on: the nearest screen's, or null
## when the button or a container above it is quiet, or no screen has sound.
static func soundscape_for(button: Node) -> Node:
	var node := button
	while node != null:
		if node.has_meta(QUIET): return null
		var sound: Variant = node.get("soundscape")
		if is_instance_valid(sound) and sound is Node and sound.has_method("play_fixed_cue"): return sound
		node = node.get_parent()
	return null

func _ready() -> void:
	get_tree().node_added.connect(_hook)
	# Buttons already in the tree when the hook arrives (Main's first screen).
	for button: Node in get_tree().root.find_children("*", "BaseButton", true, false): _hook(button)

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_hook): get_tree().node_added.disconnect(_hook)

func _hook(node: Node) -> void:
	if not node is BaseButton: return
	var found := soundscape_for(node)
	node.set_meta(FOUND, weakref(found) if found != null else null)
	if node.has_meta(HOOKED): return
	node.set_meta(HOOKED, true)
	(node as BaseButton).pressed.connect(_tick.bind(node))

func _tick(button: Node) -> void:
	var sound: Node = soundscape_for(button)
	if not button.is_inside_tree():
		var found: Variant = button.get_meta(FOUND, null)
		sound = found.get_ref() if found is WeakRef else null
	if is_instance_valid(sound): sound.play_fixed_cue(CUE)
