extends RefCounted
## What a chapter screen shows of end-of-run reactions, so the screen itself
## only builds one context and calls in:
##   attach_ending(ctx, card, recording, kept)  a review or ending card
##   attach_completed(ctx, card)                the chapter-finish card
##   attach_friend_latest(ctx, strip)           the room panel's friend strip
##   face_to_send(ctx, recording)               the face Save turn sends
##   keep_solo(recording)                       after a solo Save turn
##   pop_replay(ctx, runs)                      a rewatched turn's end
##   attach_hard(extras, hard)                  a hard run's end card (the
##                                              hook below, installed on load)
## The context is the screen's explicit answer (relay_preview.gd
## _end_reaction_context), every key optional:
##   online        a room, not solo
##   available     reactions are on here: solo always, a room only while its
##                 server takes them (end_reactions_supported)
##   pending       a room send is waiting; pending_face is the face it carries
##   viewer_slot   the player's slot in the room ("p0" host, "p1" guest)
##   room_id, chapter_key, definition (its stages' first slots), prior (the
##   memory this turn was played alongside), settings, soundscape, world, hud
##   pairs         Callable() -> Array: the chapter's saved parts
##   friend_name   Callable() -> String: the friend's display name
## The picker and bubbles are presentation/end_reactions.gd; the faces and what
## this phone keeps are services/end_reaction_store.gd.
const EndReactions = preload("res://presentation/end_reactions.gd")
const Store = preload("res://services/end_reaction_store.gd")
const PlayerCopy = preload("res://presentation/player_copy.gd")
const Look = preload("res://presentation/spirit_look.gd")
const Typed = preload("res://services/typed_values.gd")
const HardModeView = preload("res://presentation/hard_mode_view.gd")
## How long a rewatched turn holds on its reactions before going on.
const REPLAY_HOLD := 1.4
const REPLAY_HOLD_REDUCED := 0.9

## Every hard run end card (presentation/hard_mode_view.gd) carries the row.
static func _static_init() -> void:
	HardModeView.ending_extras_provider = attach_hard

## A review or ending card's row: the player's pick for this run, and in a room
## the friend's face on the turn this one was played alongside. `kept`: the
## turn can be saved or sent (a drowning cannot; its face is for the moment).
## While a room send waits, the pill is fixed to the face that send carries.
static func attach_ending(ctx: Dictionary, card: Container, recording: Dictionary, kept: bool) -> Control:
	if not bool(ctx.get("available", false)) or recording.is_empty(): return null
	var online := bool(ctx.get("online", false))
	var waiting := online and bool(ctx.get("pending", false))
	var note := PlayerCopy.END_REACTIONS_MOMENT_NOTE if not kept else PlayerCopy.END_REACTIONS_ROOM_NOTE if online else PlayerCopy.END_REACTIONS_SOLO_NOTE
	return EndReactions.attach(card, {"run": str(recording.get("recording_hash", "")), "pick": not waiting, "locked": str(ctx.get("pending_face", "")) if waiting else "",
		"color": color_of(ctx, recording), "friend": _alongside(ctx, recording), "note": note,
		"settings": _settings(ctx), "sound": sound_for(ctx, recording)})

## The chapter-finish card: both players' faces on the last part (yours only,
## solo), shown and not changeable.
static func attach_completed(ctx: Dictionary, card: Container) -> Control:
	var pairs_of: Variant = ctx.get("pairs")
	if not bool(ctx.get("available", false)) or not pairs_of is Callable or not (pairs_of as Callable).is_valid(): return null
	var pairs: Array = (pairs_of as Callable).call()
	if pairs.is_empty() or not pairs[-1] is Dictionary: return null
	var store := Store.new()
	var first := Typed.as_dict(pairs[-1].get("a"))
	var second := Typed.as_dict(pairs[-1].get("b"))
	# Solo, both turns are the player's: the last one is the chapter's end.
	var mine := second
	var theirs: Dictionary = {}
	if bool(ctx.get("online", false)):
		var mine_first := slot_of(ctx, first) == str(ctx.get("viewer_slot", "p0"))
		mine = first if mine_first else second
		theirs = second if mine_first else first
	var friend := {}
	var their_face := store.kept(str(theirs.get("recording_hash", "")))
	if Store.is_face(their_face): friend = {"face": their_face, "color": color_of(ctx, theirs), "name": _friend_name(ctx), "sound": sound_for(ctx, theirs)}
	return EndReactions.attach(card, {"run": str(mine.get("recording_hash", "")), "locked": store.kept(str(mine.get("recording_hash", ""))),
		"color": color_of(ctx, mine), "friend": friend, "settings": _settings(ctx)})

## The friend's face on their latest turn, beside their name on the room panel.
static func attach_friend_latest(ctx: Dictionary, strip: Container) -> Control:
	if not bool(ctx.get("online", false)) or not bool(ctx.get("available", false)): return null
	var face := Store.new().partner(str(ctx.get("room_id", "")))
	if not Store.is_face(face): return null
	var friend_slot := "p1" if str(ctx.get("viewer_slot", "p0")) == "p0" else "p0"
	return EndReactions.attach(strip, {"friend": {"face": face, "color": Look.SLOT_COLOR_NAMES[friend_slot], "name": _friend_name(ctx)},
		"compact": true, "settings": _settings(ctx)})

## The face Save turn sends with this turn, or "" (none picked, or the room's
## server does not take them).
static func face_to_send(ctx: Dictionary, recording: Dictionary) -> String:
	return Store.picked(str(recording.get("recording_hash", ""))) if bool(ctx.get("available", false)) else ""

## A hard run's end card: `hard` is the hook's context, its "reactions" the
## screen's reaction context (Callable() -> Dictionary).
## - complete: the finish card's faces, as attach_completed. The last turn's
##   face went with its Save turn, as in any run.
## - failed, your slip with a recording: the pick is kept with the slip's
##   recording on this phone (the failed run keeps that recording), so it pops
##   when the run is watched. It stays on this phone: a room has taken the
##   slip's reset before the card shows, and sending a face would take a
##   request of its own.
## - failed otherwise (the friend's slip, or a slip with no recording): a pick
##   for the moment, never kept, so it never shows over the friend's spirit.
static func attach_hard(extras: Container, hard: Dictionary) -> Control:
	var context_of: Variant = hard.get("reactions")
	if not context_of is Callable or not (context_of as Callable).is_valid(): return null
	var ctx: Dictionary = (context_of as Callable).call()
	if str(hard.get("kind", "")) == "complete": return attach_completed(ctx, extras)
	if not bool(ctx.get("available", false)): return null
	var run := Typed.as_dict(hard.get("run"))
	var slip := Typed.as_dict(Typed.as_dict(run.get("slip")).get("recording"))
	var run_hash := str(slip.get("recording_hash", ""))
	var kept := str(run.get("by", "")) == "you" and run_hash.length() == 64 and run_hash.is_valid_hex_number()
	var key := run_hash if kept else "hard:%s:%s:%s" % [str(hard.get("chapter_key", "")), str(hard.get("room_id", "")), str(run.get("id", hard.get("number", 0)))]
	# Whose spirit picks: the slip's own, else this phone's in a room.
	var played := slip if not slip.is_empty() else {"stage_id": _stage_id(ctx, int(run.get("stage_index", 0))), "role": str(run.get("role", "a"))}
	var color := color_of(ctx, played) if kept or not bool(ctx.get("online", false)) else str(Look.SLOT_COLOR_NAMES.get(str(ctx.get("viewer_slot", "p0")), "peach"))
	var on_pick := Callable()
	if kept:
		var store := Store.new()
		# A card drawn again shows the kept face as its pick; a pick this run
		# already had (a review card before the slip) is kept with it.
		var face := store.face(key)
		if Store.is_face(face):
			if store.kept(key) != face: store.keep(key, face)
			Store.pick(key, face)
		on_pick = func(face: String) -> void:
			Store.new().keep(key, face)
			Store.pick(key, face)
	return EndReactions.attach(extras, {"run": key, "pick": true, "color": color, "note": PlayerCopy.END_REACTIONS_SOLO_NOTE if kept else PlayerCopy.END_REACTIONS_MOMENT_NOTE,
		"settings": _settings(ctx), "sound": sound_for(ctx, played), "on_pick": on_pick})

static func _stage_id(ctx: Dictionary, index: int) -> String:
	var stages: Variant = Typed.as_dict(ctx.get("definition")).get("stages", [])
	return str(stages[index].get("id", "")) if stages is Array and index >= 0 and index < stages.size() and stages[index] is Dictionary else ""

## A solo turn was saved: its pick is kept with it.
static func keep_solo(recording: Dictionary) -> void:
	var run := str(recording.get("recording_hash", ""))
	if not Store.picked(run).is_empty(): Store.new().keep(run, Store.picked(run))

## A rewatched turn reached its end: each of `runs` (the turn and the memory it
## was played alongside) that carries a face pops it above its spirit, with its
## sound. Returns how long the screen should hold before going on (0: none).
static func pop_replay(ctx: Dictionary, runs: Array) -> float:
	if not bool(ctx.get("available", false)): return 0.0
	var world: Variant = ctx.get("world")
	var hud: Variant = ctx.get("hud")
	if not is_instance_valid(world) or not hud is Control or not is_instance_valid(hud) or not world.get("camera") is Camera3D or not world.get("actors") is Dictionary: return 0.0
	var store := Store.new()
	var settings := _settings(ctx)
	var hold := REPLAY_HOLD_REDUCED if bool(settings.get("reduced_motion", false)) else REPLAY_HOLD
	var shown := 0
	for run: Variant in runs:
		if not run is Dictionary or run.is_empty(): continue
		var face := store.face(str(run.get("recording_hash", "")))
		if not Store.is_face(face): continue
		var actor: Variant = world.actors.get(slot_of(ctx, run))
		if not actor is Node3D or not (actor as Node3D).is_inside_tree(): continue
		var at: Variant = _above(world.camera, actor, hud)
		if not at is Vector2: continue
		# The bubble stays over its spirit while the camera settles.
		var refs := [weakref(world.camera), weakref(actor), weakref(hud)]
		var follow := func() -> Variant: return _above(refs[0], refs[1], refs[2])
		if EndReactions.pop(hud, at, face, color_of(ctx, run), settings, hold + 0.2, follow) == null: continue
		shown += 1
		var sound := sound_for(ctx, run)
		if sound.is_valid(): sound.call(face)
	return hold if shown > 0 else 0.0

## The screen point just above a spirit's head in `hud`, or null when it
## cannot show (behind the camera, or anything gone). Takes the nodes or
## weak references to them.
static func _above(camera_ref: Variant, actor_ref: Variant, hud_ref: Variant) -> Variant:
	var camera: Variant = camera_ref.get_ref() if camera_ref is WeakRef else camera_ref
	var actor: Variant = actor_ref.get_ref() if actor_ref is WeakRef else actor_ref
	var hud: Variant = hud_ref.get_ref() if hud_ref is WeakRef else hud_ref
	if not camera is Camera3D or not actor is Node3D or not hud is Control or not (actor as Node3D).is_inside_tree() or not (camera as Camera3D).is_inside_tree(): return null
	var above := (actor as Node3D).global_position + Vector3(0, 1.5, 0)
	if (camera as Camera3D).is_position_behind(above): return null
	return (hud as Control).get_global_transform_with_canvas().affine_inverse() * (camera as Camera3D).unproject_position(above)

## The slot ("p0" or "p1") that played `recording`: its stage's first slot for
## a first turn, the other for a second.
static func slot_of(ctx: Dictionary, recording: Dictionary) -> String:
	var first := "p0"
	for item: Variant in Typed.as_dict(ctx.get("definition")).get("stages", []):
		if item is Dictionary and str(item.get("id", "")) == str(recording.get("stage_id", "")): first = str(item.get("first_player_slot", "p0"))
	if str(recording.get("role", "a")) == "a": return first
	return "p1" if first == "p0" else "p0"

static func color_of(ctx: Dictionary, recording: Dictionary) -> String:
	return Look.SLOT_COLOR_NAMES.get(slot_of(ctx, recording), "peach")

## The reaction's pop, pitched from the reaction alone (soundscape.play_reaction):
## the same run and face sound the same picked, on the friend's card and in a rewatch.
static func sound_for(ctx: Dictionary, recording: Dictionary) -> Callable:
	var soundscape: Variant = ctx.get("soundscape")
	if not is_instance_valid(soundscape): return Callable()
	var parts := [str(ctx.get("chapter_key", "")), str(recording.get("stage_id", "")), str(recording.get("role", "")), str(recording.get("recording_hash", ""))]
	var weak: WeakRef = weakref(soundscape)
	return func(face: String) -> void:
		var target: Variant = weak.get_ref()
		if is_instance_valid(target): target.play_reaction(parts + [face])

## In a room, the second turn's memory is the friend's first turn: its face.
static func _alongside(ctx: Dictionary, recording: Dictionary) -> Dictionary:
	if not bool(ctx.get("online", false)) or str(recording.get("role", "")) != "b": return {}
	var prior := Typed.as_dict(ctx.get("prior"))
	var face := Store.new().kept(str(prior.get("recording_hash", "")))
	if not Store.is_face(face): return {}
	return {"face": face, "color": color_of(ctx, prior), "name": _friend_name(ctx), "sound": sound_for(ctx, prior)}

static func _friend_name(ctx: Dictionary) -> String:
	var name_of: Variant = ctx.get("friend_name")
	return str((name_of as Callable).call()) if name_of is Callable and (name_of as Callable).is_valid() else ""

static func _settings(ctx: Dictionary) -> Dictionary:
	return Typed.as_dict(ctx.get("settings"))
