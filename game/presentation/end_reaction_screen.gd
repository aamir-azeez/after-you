extends RefCounted
## What a chapter screen (relay_preview.gd and the screens built on it) shows
## of end-of-run reactions, so the screen itself only calls in:
##   attach_ending(screen, card, recording, kept)  a review or ending card
##   attach_completed(screen, card)                the chapter-finish card
##   attach_friend_latest(screen, strip)           the room panel's friend strip
##   face_to_send(screen, recording)               the face Save turn sends
##   keep_solo(recording)                          after a solo Save turn
##   pop_replay(screen, runs)                      a rewatched turn's end
## The picker and bubbles are presentation/end_reactions.gd; the faces and what
## this phone keeps are services/end_reaction_store.gd. A room shows reactions
## only while its server takes them (end_reactions_supported); solo always.
const EndReactions = preload("res://presentation/end_reactions.gd")
const Store = preload("res://services/end_reaction_store.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const FriendNicknames = preload("res://services/friend_nicknames.gd")
const Typed = preload("res://services/typed_values.gd")
## Each spirit's colour, as the world draws them (turn_endings.gd SLOT_COLORS).
const SLOT_COLORS := {"p0": "peach", "p1": "mint"}
## How long a rewatched turn holds on its reactions before going on.
const REPLAY_HOLD := 1.4
const REPLAY_HOLD_REDUCED := 0.9

static func available(screen: Node) -> bool:
	var session: Variant = screen.get("online_session")
	if session == null: return true
	return session.has_method("end_reactions_supported") and session.end_reactions_supported()

static func online(screen: Node) -> bool:
	return screen.get("online_session") != null

## A review or ending card's row: the player's pick for this run, and in a room
## the friend's face on the turn this one was played alongside. `kept`: the
## turn can be saved or sent (a drowning cannot; its face is for the moment).
static func attach_ending(screen: Node, card: Container, recording: Dictionary, kept: bool) -> Control:
	if not available(screen) or recording.is_empty(): return null
	var locked := ""
	var journey: Variant = screen.get("journey")
	if online(screen) and journey != null and journey.has_method("pending_reaction"): locked = journey.pending_reaction()
	var note := PlayerCopy.END_REACTIONS_MOMENT_NOTE if not kept else PlayerCopy.END_REACTIONS_ROOM_NOTE if online(screen) else PlayerCopy.END_REACTIONS_SOLO_NOTE
	return EndReactions.attach(card, {"run": str(recording.get("recording_hash", "")), "pick": true, "locked": locked,
		"color": color_of(screen, recording), "friend": _alongside(screen, recording), "note": note,
		"settings": _settings(screen), "sound": sound_for(screen, recording)})

## The chapter-finish card: both players' faces on the last part (yours only,
## solo), shown and not changeable.
static func attach_completed(screen: Node, card: Container) -> Control:
	if not available(screen) or not screen.has_method("_pairs"): return null
	var pairs: Array = screen._pairs()
	if pairs.is_empty() or not pairs[-1] is Dictionary: return null
	var last: Dictionary = pairs[-1]
	var store := Store.new()
	var first := Typed.as_dict(last.get("a"))
	var second := Typed.as_dict(last.get("b"))
	# Solo, both turns are the player's: the last one is the chapter's end.
	var mine := second
	var theirs: Dictionary = {}
	if online(screen):
		var mine_first := slot_of(screen, first) == _viewer_slot(screen)
		mine = first if mine_first else second
		theirs = second if mine_first else first
	var friend := {}
	var their_face := store.kept(str(theirs.get("recording_hash", "")))
	if Store.is_face(their_face): friend = {"face": their_face, "color": color_of(screen, theirs), "name": _friend_name(screen), "sound": sound_for(screen, theirs)}
	return EndReactions.attach(card, {"run": str(mine.get("recording_hash", "")), "locked": store.kept(str(mine.get("recording_hash", ""))),
		"color": color_of(screen, mine), "friend": friend, "settings": _settings(screen)})

## The friend's face on their latest turn, beside their name on the room panel.
static func attach_friend_latest(screen: Node, strip: Container) -> Control:
	if not online(screen) or not available(screen): return null
	var room: Dictionary = screen.journey.snapshot() if screen.get("journey") != null else {}
	var face := Store.new().partner(str(room.get("room_id", "")))
	if not Store.is_face(face): return null
	var slot := _viewer_slot(screen)
	return EndReactions.attach(strip, {"friend": {"face": face, "color": SLOT_COLORS.get(_other(slot), "mint"), "name": _friend_name(screen)},
		"compact": true, "settings": _settings(screen)})

## The face Save turn sends with this turn, or "" (none picked, or the room's
## server does not take them).
static func face_to_send(screen: Node, recording: Dictionary) -> String:
	return Store.picked(str(recording.get("recording_hash", ""))) if available(screen) else ""

## A solo turn was saved: its pick is kept with it.
static func keep_solo(recording: Dictionary) -> void:
	var run := str(recording.get("recording_hash", ""))
	if not Store.picked(run).is_empty(): Store.new().keep(run, Store.picked(run))

## A rewatched turn reached its end: each of `runs` (the turn and the memory it
## was played alongside) that carries a face pops it above its spirit, with its
## sound. Returns how long the screen should hold before going on (0: none).
static func pop_replay(screen: Node, runs: Array) -> float:
	if not available(screen): return 0.0
	var world: Variant = screen.get("world")
	var hud: Variant = screen.get("hud")
	if not is_instance_valid(world) or not is_instance_valid(hud) or not world.get("camera") is Camera3D or not world.get("actors") is Dictionary: return 0.0
	var store := Store.new()
	var shown := 0
	var settings := _settings(screen)
	for run: Variant in runs:
		if not run is Dictionary or run.is_empty(): continue
		var face := store.kept(str(run.get("recording_hash", "")))
		if face.is_empty(): face = Store.picked(str(run.get("recording_hash", "")))
		if not Store.is_face(face): continue
		var actor: Variant = world.actors.get(slot_of(screen, run))
		if not actor is Node3D or not (actor as Node3D).is_inside_tree(): continue
		var camera: Camera3D = world.camera
		var above := (actor as Node3D).global_position + Vector3(0, 1.5, 0)
		if camera.is_position_behind(above): continue
		var at: Vector2 = (hud as Control).get_global_transform_with_canvas().affine_inverse() * camera.unproject_position(above)
		var hold := REPLAY_HOLD_REDUCED if bool(settings.get("reduced_motion", false)) else REPLAY_HOLD
		if EndReactions.pop(hud, at, face, color_of(screen, run), settings, hold + 0.2) != null:
			shown += 1
			var sound := sound_for(screen, run)
			if sound.is_valid(): sound.call(face)
	if shown == 0: return 0.0
	return REPLAY_HOLD_REDUCED if bool(settings.get("reduced_motion", false)) else REPLAY_HOLD

## The slot ("p0" or "p1") that played `recording`: its stage's first slot for
## a first turn, the other for a second.
static func slot_of(screen: Node, recording: Dictionary) -> String:
	var first := "p0"
	var definition: Variant = screen.get("definition")
	if definition is Dictionary:
		for item: Variant in definition.get("stages", []):
			if item is Dictionary and str(item.get("id", "")) == str(recording.get("stage_id", "")): first = str(item.get("first_player_slot", "p0"))
	return first if str(recording.get("role", "a")) == "a" else _other(first)

static func color_of(screen: Node, recording: Dictionary) -> String:
	return SLOT_COLORS.get(slot_of(screen, recording), "peach")

## The reaction's pop, pitched from the reaction alone (soundscape.play_reaction):
## the same run and face sound the same picked, on the friend's card and in a rewatch.
static func sound_for(screen: Node, recording: Dictionary) -> Callable:
	var soundscape: Variant = screen.get("soundscape")
	if not is_instance_valid(soundscape): return Callable()
	var parts := [str(screen.get("chapter_key")), str(recording.get("stage_id", "")), str(recording.get("role", "")), str(recording.get("recording_hash", ""))]
	var weak: WeakRef = weakref(soundscape)
	return func(face: String) -> void:
		var target: Variant = weak.get_ref()
		if is_instance_valid(target): target.play_reaction(parts + [face])

## In a room, the second turn's memory is the friend's first turn: its face.
static func _alongside(screen: Node, recording: Dictionary) -> Dictionary:
	if not online(screen) or str(recording.get("role", "")) != "b": return {}
	var prior: Variant = screen.get("prior")
	if not prior is Dictionary or prior.is_empty(): return {}
	var face := Store.new().kept(str(prior.get("recording_hash", "")))
	if not Store.is_face(face): return {}
	return {"face": face, "color": color_of(screen, prior), "name": _friend_name(screen), "sound": sound_for(screen, prior)}

static func _friend_name(screen: Node) -> String:
	if not screen.has_method("_waiting_partner_name") or screen.get("journey") == null: return ""
	return FriendNicknames.sentence_start(screen._waiting_partner_name(screen.journey.snapshot()))

static func _viewer_slot(screen: Node) -> String:
	var journey: Variant = screen.get("journey")
	var room: Dictionary = journey.snapshot() if journey != null and journey.has_method("snapshot") else {}
	return str(room.get("player_slot", "p0"))

static func _settings(screen: Node) -> Dictionary:
	var settings: Variant = screen.get("settings")
	return settings if settings is Dictionary else {}

static func _other(slot: String) -> String:
	return "p1" if slot == "p0" else "p0"
