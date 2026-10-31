extends Node
## Every button's soft tick: one hook on the scene tree for the whole app, so no
## screen wires its own. Main installs it once under the tree's root, where it
## outlives every scene change (chapters open with change_scene).
##
## A button that enters the tree anywhere gets its confirmed press ("pressed":
## a release over the button or an accepted key, never hover, focus or the
## press going down) played as the fixed cue CUE on the soundscape of the
## nearest screen above it that is still in the tree, a node with a
## `soundscape` (Main, a chapter screen, a shared replay). A screen's own
## handler runs first, so a Back or Leave that took its screen away ticks on
## the screen left showing (the tree's current scene). The Sound setting and
## backgrounding apply, and two presses in one frame (Android Back pressing a
## card's Back, a slip forwarding to Watch) tick once (soundscape play_fixed_cue).
##
## quiet() a button or a container to keep it silent:
## - the controls a run is played with (action, finish, fast forward, its
##   reactions; Main's throw and finish), whose presses make the run's own cues.
##   Pause, Reset view and Skip wait still tick: they make no cue of their own;
## - a button whose press plays its own sound instead (Wear, the Wardrobe's Buy,
##   a keepsake, a reaction face).
## Adding a node costs one type check; only a press walks up the tree.
const CUE := "ui_tap"
const NODE_NAME := "ButtonTicks"
const QUIET := "button_tick_quiet"
## Set once a button's press is hooked, so a button moved in the tree is hooked once.
const HOOKED := "button_tick_hooked"

## Adds the hook under `tree`'s root once; later calls change nothing.
static func install(tree: SceneTree) -> void:
	# Marked at once: the hook itself joins the root only at the next idle.
	if tree == null or tree.root.has_meta(NODE_NAME): return
	tree.root.set_meta(NODE_NAME, true)
	var ticks: Node = load("res://presentation/button_ticks.gd").new()
	ticks.name = NODE_NAME
	# The root may be busy setting up its children (Main's _ready): add it next.
	tree.root.add_child.call_deferred(ticks)

## Keeps `node` and every button under it silent (`on` false lets it tick again).
static func quiet(node: Node, on: bool = true) -> void:
	if node == null: return
	if on: node.set_meta(QUIET, true)
	elif node.has_meta(QUIET): node.remove_meta(QUIET)

## The soundscape a press of `button` ticks on: the nearest screen's still in
## the tree; for a button its press took out of the tree, the current scene's.
## Null when the button or a container above it is quiet, or no screen has sound.
static func soundscape_for(button: Node) -> Node:
	if not is_instance_valid(button): return null
	var node := button
	while node != null:
		if node.has_meta(QUIET): return null
		var sound: Variant = node.get("soundscape")
		if is_instance_valid(sound) and sound is Node and (sound as Node).is_inside_tree() and sound.has_method("play_fixed_cue"): return sound
		node = node.get_parent()
	if button.is_inside_tree(): return null
	var tree := Engine.get_main_loop() as SceneTree
	var scene: Node = tree.current_scene if tree != null else null
	return soundscape_for(scene) if is_instance_valid(scene) and scene.is_inside_tree() else null

func _ready() -> void:
	get_tree().node_added.connect(_hook)
	# Buttons already in the tree when the hook arrives (Main's first screen).
	for button: Node in get_tree().root.find_children("*", "BaseButton", true, false): _hook(button)

func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_hook): get_tree().node_added.disconnect(_hook)
	get_tree().root.remove_meta(NODE_NAME)

func _hook(node: Node) -> void:
	if not node is BaseButton or node.has_meta(HOOKED): return
	node.set_meta(HOOKED, true)
	(node as BaseButton).pressed.connect(_tick.bind(node))

func _tick(button: Node) -> void:
	var sound := soundscape_for(button)
	if sound != null: sound.play_fixed_cue(CUE)
