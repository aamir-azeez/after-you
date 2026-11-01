extends RefCounted
## Main's online room open builds the room's world over frames behind the
## room screen's own loading card (relay_preview.gd staged_room_open), so a
## test that opens a room and then reads its view waits for that build first.

## The room screen Main holds, once its world is built (null when there is none).
static func built(tree: SceneTree, app: Node) -> Node:
	var screen: Node = app.relay_child
	var guard := 0
	while is_instance_valid(screen) and screen.building() and guard < 900:
		await tree.process_frame
		guard += 1
	return app.relay_child if is_instance_valid(app.relay_child) else null

## Main's _enter_online_relay, then the room screen once built.
static func enter(tree: SceneTree, app: Node) -> Node:
	app._enter_online_relay()
	return await built(tree, app)
