extends RefCounted
## Opens and closes the shared replay viewer (presentation/shared_replay_view.gd)
## as Main's full-screen shared_replay_child. While it plays, Home's world hides
## and its sound pauses; Main paces frames, routes Back and passes identity
## changes by that slot, and keeps 3D drawing on while it is up
## (_service_world_cover). Replays (replays_flow.gd) and the leaderboards
## (friends_flow.gd) both open it here.
##
## Host contract: saves (settings), api, _relay_identity, _set_world_visible,
## soundscape, application_backgrounded, shared_replay_child, add_child.
const SharedReplayView = preload("res://presentation/shared_replay_view.gd")

## A viewer for `entries` with the host's settings and identity, not yet shown;
## the caller sets anything else it needs, then calls show().
static func make(host: Node, entries: Array) -> Node3D:
	var view: Node3D = SharedReplayView.new()
	view.entry = entries[0]
	view.sequence = entries
	view.settings = host.saves.data.settings.duplicate(true)
	view.api = host.api
	view.identity = host._relay_identity
	return view

static func show(host: Node, view: Node3D) -> void:
	host._set_world_visible(false)
	host.soundscape.set_backgrounded(true)
	host.shared_replay_child = view
	host.add_child(view)

## Removes the host's viewer and brings Home's world and sound back.
static func close(host: Node) -> void:
	var view: Node = host.shared_replay_child
	if is_instance_valid(view):
		host.remove_child(view)
		view.queue_free()
	host.shared_replay_child = null
	host._set_world_visible(true)
	host.soundscape.set_backgrounded(host.application_backgrounded)
