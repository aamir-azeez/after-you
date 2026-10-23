extends SceneTree
## Every room action (presentation/room_actions.gd) resolves on every screen
## that draws room actions (its _room_action_hooks): a plain row's handler takes
## the arguments the row gives it, a widget row's builder, Room options wiring
## and drawn hook exist with their arguments, a subclass's override answers,
## and nothing else hosts room actions unchecked.
const RoomActions = preload("res://presentation/room_actions.gd")
## The screens that draw room actions: relay_preview.gd and every script that
## extends it. lighthouse_preview.gd (Lighthouse @1) draws its own cards.
const HOSTS := ["res://relay_preview.gd", "res://cooperative_preview.gd"]
const KINDS := ["run", "widget", "option", "drawn"]

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_hosts()
	for path: String in HOSTS: _resolves(path)
	_override_answers()
	print("ROOM ACTION HOOKS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

## The game scripts that extend the room screen are exactly HOSTS.
func _hosts() -> void:
	var parents := {}
	var sources := {}
	for path: String in _scripts("res://"):
		var source := FileAccess.get_file_as_string(path)
		sources[path] = source
		var found := RegEx.create_from_string("(?m)^extends \"(res://[^\"]+)\"").search(source)
		if found != null: parents[path] = found.get_string(1)
	var hosts: Array[String] = ["res://relay_preview.gd"]
	var grew := true
	while grew:
		grew = false
		for path: String in parents:
			if parents[path] in hosts and not path in hosts:
				hosts.append(path)
				grew = true
	hosts.sort()
	var expected: Array[String] = []
	expected.assign(HOSTS)
	expected.sort()
	_check(hosts == expected, "The room screens are relay_preview.gd and its subclasses: " + str(hosts))
	_check(sources.has("res://lighthouse_preview.gd") and not sources["res://lighthouse_preview.gd"].contains("room_actions.gd"), "Lighthouse @1 draws no room actions")

func _scripts(dir: String) -> Array[String]:
	var found: Array[String] = []
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".gd"): found.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub in ["tests", "addons", "android"]: continue
		found.append_array(_scripts(dir.path_join(sub)))
	return found

## Each row's hooks on `screen`, by kind.
func _hooks(screen: Object) -> Dictionary:
	return screen._room_action_hooks()

func _resolves(path: String) -> void:
	var screen: Object = load(path).new()
	var methods := {}
	# A subclass's override comes first in the list.
	for method: Dictionary in screen.get_method_list():
		if not methods.has(method.name): methods[method.name] = method
	var hooks := _hooks(screen)
	for id: String in hooks:
		_check(RoomActions.ACTIONS.has(id), "A hook belongs to a room action: %s on %s" % [id, path.get_file()])
		_check(hooks[id].keys().all(func(kind: String): return kind in KINDS), "A hook is run, widget, option or drawn: %s on %s" % [id, path.get_file()])
	var in_options := {}
	for state: String in RoomActions.LAYOUT:
		for id: String in RoomActions.LAYOUT[state].get("options", []): in_options[id] = true
	for id: String in RoomActions.ACTIONS:
		var row: Dictionary = RoomActions.ACTIONS[id]
		var hook: Dictionary = hooks.get(id, {})
		var where := "%s on %s" % [id, path.get_file()]
		_check(hook.has("run") != hook.has("widget"), "A row has a handler or a widget, not both: " + where)
		_check(not hook.has("widget") or row.get("bind", []).is_empty() and not row.get("with_receipt", false), "A widget row is wired only by its widget: " + where)
		_check(not hook.has("option") or hook.has("widget"), "Only a widget row wires its own Room options row: " + where)
		_check(not hook.has("widget") or not in_options.has(id) or hook.has("option"), "A widget row in Room options wires its sheet row: " + where)
		for kind: String in hook:
			var callable: Callable = hook[kind]
			_check(callable.is_valid() and callable.get_object() == screen, "The %s hook resolves on the screen: %s" % [kind, where])
			var method: Dictionary = methods.get(str(callable.get_method()), {})
			if method.is_empty(): continue
			var most: int = method.args.size()
			var least: int = most - method.default_args.size()
			var takes: int = {"widget": 4, "option": 2, "drawn": 1}.get(kind, row.get("bind", []).size() + (1 if row.get("with_receipt", false) else 0))
			_check(takes >= least and takes <= most, "The %s hook %s takes the %d arguments it is given: %s" % [kind, callable.get_method(), takes, where])
	screen.free()

## A subclass's override of a handler is what the row runs.
func _override_answers() -> void:
	var subclass := GDScript.new()
	subclass.source_code = "extends \"res://relay_preview.gd\"\nvar answered := \"\"\nfunc _show_local_replays() -> void:\n\tanswered = \"override\"\n"
	_check(subclass.reload() == OK, "A room screen subclass compiles")
	var screen: Object = subclass.new()
	screen._room_action_handler("local_replays").call()
	_check(screen.answered == "override", "A row runs the subclass's override of its handler")
	screen.free()

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAILED: " + description)
