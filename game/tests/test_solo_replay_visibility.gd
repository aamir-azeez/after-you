extends SceneTree
const Visibility = preload("res://services/solo_replay_visibility.gd")
var checks := 0
var failures := 0
var path := "user://solo-replay-visibility-%d.json" % Time.get_ticks_usec()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var row := {"visibility_key":"relay:attempt:part-0:abc","content_id":"a".repeat(64)}
	var visibility := Visibility.new(path)
	_check(not visibility.is_hidden(row), "A replay is visible before removal")
	_check(visibility.hide(row) and visibility.is_hidden(row), "Removing a replay hides its exact verified content")
	var next := Visibility.new(path)
	_check(next.is_hidden(row), "Replay visibility persists after restart")
	var replacement := row.duplicate(true)
	replacement.content_id = "b".repeat(64)
	_check(not next.is_hidden(replacement), "A different content identity remains visible")
	_check(not next.hide({"visibility_key":"bad","content_id":"not-a-digest"}), "Invalid rows cannot be removed")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("Solo replay visibility: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
