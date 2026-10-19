extends Node
## Presentation-only sound. Consume events once per simulation step, never snapshot.
## In a recorded turn, pitch and gain derive from the event identity
## (chapter, stage, cause, kind, ordinal). Home meetups stay random.

const PlatformSupport = preload("res://services/platform_support.gd")
const SoundCues = preload("res://services/sound_cues.gd")
## Cue name -> clip and pitch range (semitones), both from sound_cues.gd.
static var CLIPS: Dictionary = _cue_table("clip")
static var CUE_RANGES: Dictionary = _cue_table("range")
# A cause's consecutive cues on one clip are at least this far apart.
const CUE_MIN_MOVE := 0.5
# Levels, spans and clips are sound_cues.gd's; these names read them.
const CUE_DB: float = SoundCues.CUE_DB
const STEP_DB: float = SoundCues.FOOTSTEPS.db
const STEP_JITTER_DB: float = SoundCues.FOOTSTEPS.gain.y
# Footstep detune in semitones: +/-1.0 is about +/-6%; consecutive contacts
# of one spirit always differ by at least STEP_MIN_MOVE.
const STEP_DETUNE: float = SoundCues.FOOTSTEPS.detune.y
const STEP_MIN_MOVE: float = SoundCues.FOOTSTEPS.min_move
# Each meetup slides to a pitch at least REUNION_MIN_MOVE from the last one.
const REUNION_RANGE: Vector2 = SoundCues.REUNION.range
const REUNION_MIN_MOVE: float = SoundCues.REUNION.min_move
const REUNION_DB: float = SoundCues.REUNION.db
const REUNION_JITTER_DB: float = SoundCues.REUNION.gain.y
## No previous pitch yet: every pitch in the range is allowed.
const NO_PITCH := INF
## Chapter name for the earlier islands, which have no registry key.
const ISLANDS_CHAPTER := "earlier-islands"
## Events caused by the first spirit (the replayed memory) and by the second.
## Any other event belongs to the live role.
const FIRST_SPIRIT_EVENTS := ["seed_taken", "seed_thrown", "seed_landed", "seed_missed", "garden_opened", "lift_ready", "handoff_offer"]
const SECOND_SPIRIT_EVENTS := ["seed_caught", "island_bloomed", "garden_bloomed", "relay_filled", "stage_complete", "lift_boarded", "lift_arrived", "loft_opened", "bell", "handoff_claim", "beacon_lit", "court_activated"]
## A bridge or switch is named by itself. Levers, mirrors, routes and water
## levels are named by their object from the snapshot (chapter_sound_map.gd),
## so either spirit's use sounds the same; other events keep the live role.

## Short-cue voices, loop voices (moving mechanisms) and bed layers. A full pool
## drops the newest loop instead of cutting one that plays. A place's calls
## (birds) share one more voice, so two calls never overlap.
const CUE_VOICES := 5
const LOOP_VOICES := 3
const BED_VOICES := 2
## More cues than this in one rendered frame (a hitch that ran several
## simulation ticks at once) are counted but not played, so they never stack
## and never take a voice another cue started in the same frame.
const MAX_CUES_PER_FRAME := CUE_VOICES
## Loops and beds fade in and out instead of clicking.
const LOOP_FADE := 0.15
const SILENT_DB := -60.0
## How often a listened world is checked for being on screen and moving.
const WORLD_CHECK_SECONDS := 0.25

var sound_enabled := true
var haptics_enabled := true
var backgrounded := false
var ambience: AudioStreamPlayer
var voices: Array[AudioStreamPlayer] = []
var next_voice := 0
const FOOTSTEPS: Array = SoundCues.FOOTSTEPS.clips
const REUNION: AudioStream = SoundCues.REUNION.clip
var step_voices: Array[AudioStreamPlayer] = []
var next_step := 0
var reunion_voice: AudioStreamPlayer
# Private generator for Home meetups and ambient calls; never reads or advances
# the global RNG.
var variation := RandomNumberGenerator.new()
var reunion_pitch := NO_PITCH
# The turn whose events are playing, and its per-spirit identity state.
var turn_chapter := ""
var turn_stage := ""
var last_steps := {}
var _ordinals := {}
var _step_detunes := {}
var _turn_reunion := NO_PITCH
var _sources: Array = []
var _hold := PackedInt32Array()
## Cues a turn held back (presentation/memory_wait.gd): each keeps the pitch
## and gain it got on its own tick and sounds when released.
var _held_cues: Array[Dictionary] = []
## Bells and other ringing tails: never taken by a burst of short cues.
var long_voice: AudioStreamPlayer
var max_cues_per_frame := MAX_CUES_PER_FRAME
var _cue_frame := -1
var _frame_cues := 0
## Loop players, and the looping copy of each LOOPS clip (built once).
var loop_voices: Array[AudioStreamPlayer] = []
var bed_voices: Array[AudioStreamPlayer] = []
var _looped: Dictionary = {}
## Mechanisms the world says are moving: id -> {kind, direction}.
var _motions: Dictionary = {}
## Which loop voice plays which mechanism or bed: id -> voice.
var _sounding: Dictionary = {}
var _world: Node3D
## The place whose bed plays outside a recorded turn ("home" on Home).
var idle_place := ""
var _world_check: Timer
## The calls (SoundCues.CALLS) of the place on screen, the one voice they sing
## on, the timer to the next call, and the last call's variant and pitch.
var call_voice: AudioStreamPlayer
var calling := ""
var _call_timer: Timer
var _last_call := -1
var _call_pitch := NO_PITCH

func _init() -> void:
	variation.randomize()

static func _cue_table(field: String) -> Dictionary:
	var table := {}
	for key: String in SoundCues.CUES: table[key] = SoundCues.CUES[key][field]
	return table

func _ready() -> void:
	reunion_voice=AudioStreamPlayer.new()
	reunion_voice.stream=REUNION
	reunion_voice.volume_db=REUNION_DB
	add_child(reunion_voice)
	for i in range(3):
		var voice := AudioStreamPlayer.new()
		voice.volume_db=STEP_DB
		add_child(voice)
		step_voices.append(voice)
	for i in range(CUE_VOICES):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = CUE_DB
		add_child(voice)
		voices.append(voice)
	long_voice = AudioStreamPlayer.new()
	add_child(long_voice)
	for i in range(LOOP_VOICES):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		loop_voices.append(voice)
	for i in range(BED_VOICES):
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		bed_voices.append(voice)
	ambience = AudioStreamPlayer.new()
	ambience.stream = _looped_clip("ambience")
	ambience.volume_db = float(SoundCues.LOOPS.ambience.db)
	add_child(ambience)
	_world_check = Timer.new()
	_world_check.wait_time = WORLD_CHECK_SECONDS
	_world_check.timeout.connect(_sync_loops)
	add_child(_world_check)
	call_voice = AudioStreamPlayer.new()
	add_child(call_voice)
	_call_timer = Timer.new()
	_call_timer.one_shot = true
	_call_timer.timeout.connect(_on_call_due)
	add_child(_call_timer)
	_update_ambience()

## A looping copy of an imported clip, across its full length.
static func _looping(clip: AudioStreamWAV) -> AudioStreamWAV:
	var looped: AudioStreamWAV = clip.duplicate()
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	# Imported WAVs may be QOA-compressed; encoded bytes are not PCM frames.
	looped.loop_end = roundi(looped.get_length() * looped.mix_rate)
	return looped

func configure(settings: Dictionary) -> void:
	sound_enabled = bool(settings.get("sound", true))
	haptics_enabled = bool(settings.get("haptics", true))
	if not sound_enabled:
		_stop_effects()
	_update_ambience()

func set_backgrounded(value: bool) -> void:
	backgrounded = value
	if value:
		_stop_effects()
	_update_ambience()

## Plays the world's moving mechanisms and its place's bed while that world is
## on screen. `place` names the bed outside a recorded turn ("home").
func listen_to(world: Node3D, place: String = "") -> void:
	if is_instance_valid(_world) and _world.has_signal("mechanism_moving") and _world.mechanism_moving.is_connected(_on_mechanism_moving):
		_world.mechanism_moving.disconnect(_on_mechanism_moving)
	_world = world
	idle_place = place
	_motions.clear()
	if is_instance_valid(world) and world.has_signal("mechanism_moving"):
		world.mechanism_moving.connect(_on_mechanism_moving)
	_sync_loops()

## Starts a recorded turn: call wherever its simulation resets to tick zero.
func begin_turn(chapter: String, stage: String) -> void:
	var place_changed := chapter != turn_chapter
	turn_chapter = chapter
	turn_stage = stage
	last_steps.clear()
	_ordinals.clear()
	_step_detunes.clear()
	_turn_reunion = NO_PITCH
	_held_cues.clear()
	if place_changed: _sync_loops()

## Leaves recorded play, e.g. for Home, where meetups are random again.
func clear_turn() -> void:
	begin_turn("", "")

func in_turn() -> bool:
	return not turn_chapter.is_empty()

## "cause|event" for a simulation event. Bridges are keyed by the bridge itself.
static func event_source(event: String, live_role: String) -> String:
	# Named by what moved, whoever played it: the same crossing, spirit or control
	# sounds the same live, in memory, on retry and in replay.
	if event.begins_with("bridge_open") or event.begins_with("selector:") or event.begins_with("closing:") or event.begins_with("drowned:"): return event + "|" + event
	if event in FIRST_SPIRIT_EVENTS: return "a|" + event
	if event in SECOND_SPIRIT_EVENTS: return "b|" + event
	return live_role + "|" + event

## Plays one tick of a recorded turn; sources[i] comes from event_source.
## Cues at the `hold` indices get their identity now but wait for
## release_held_cues().
func consume_turn_events(events: Array, sources: Array, live_play: bool, hold: PackedInt32Array = PackedInt32Array()) -> void:
	_sources = sources
	_hold = hold
	consume_events(events, live_play)
	_sources = []
	_hold = PackedInt32Array()

## Counts events replayed silently (a resumed draft) so later cues keep their
## identity. Cues at the `hold` indices are kept for release_held_cues().
func note_turn_events(events: Array, sources: Array, hold: PackedInt32Array = PackedInt32Array()) -> void:
	for index in range(events.size()):
		var key := str(events[index])
		if not CLIPS.has(key): continue
		var cue := _cue_variation(key, _source_at(sources, index))
		if index in hold: _held_cues.append({"key": key, "step": cue.step, "gain": cue.gain, "live": false})

## Sounds every held cue in the order it was held, at its own pitch.
func release_held_cues() -> int:
	var held := _held_cues.duplicate()
	_held_cues.clear()
	for cue: Dictionary in held: _play_cue(str(cue.key), float(cue.step), float(cue.gain), bool(cue.live))
	return held.size()

func drop_held_cues() -> void:
	_held_cues.clear()

func held_cue_count() -> int:
	return _held_cues.size()

func consume_events(events: Array, live_play: bool) -> void:
	var sources := _sources
	for index in range(events.size()):
		var event: Variant = events[index]
		var key := str(event)
		if not CLIPS.has(key):
			continue
		# Identity advances even when muted, so unmuting keeps later pitches.
		var cue := _cue_variation(key, _source_at(sources, index))
		if index in _hold:
			_held_cues.append({"key": key, "step": cue.step, "gain": cue.gain, "live": live_play})
			continue
		_play_cue(key, float(cue.step), float(cue.gain), live_play)

func _play_cue(key: String, step: float, gain: float, live_play: bool) -> void:
	if backgrounded:
		return
	if sound_enabled and not voices.is_empty() and _frame_allows_cue():
		var cue: Dictionary = SoundCues.CUES[key]
		var voice: AudioStreamPlayer = long_voice if cue.get("voice", "") == "long" else voices[next_voice]
		voice.stream = cue.clip
		voice.pitch_scale = semitones_to_pitch(step)
		voice.volume_db = CUE_DB + float(cue.get("db", 0.0)) + gain
		voice.play()
		if voice != long_voice: next_voice = (next_voice + 1) % voices.size()
	var haptic := int(SoundCues.CUES[key].get("haptic_ms", 0))
	if live_play and haptics_enabled and haptic > 0: _emit_haptic(haptic)

## True for the first max_cues_per_frame cues of this rendered frame.
func _frame_allows_cue() -> bool:
	var frame := Engine.get_process_frames()
	if frame != _cue_frame:
		_cue_frame = frame
		_frame_cues = 0
	if max_cues_per_frame > 0 and _frame_cues >= max_cues_per_frame: return false
	_frame_cues += 1
	return true

static func semitones_to_pitch(semitones: float) -> float:
	return pow(2.0, semitones / 12.0)

## A stable 32-bit digest of an identity; the same on every install.
static func identity_hash(parts: Array) -> int:
	var text := PackedStringArray()
	for part: Variant in parts: text.append(str(part))
	return "|".join(text).md5_text().substr(0, 8).hex_to_int()

static func identity_unit(parts: Array) -> float:
	return float(identity_hash(parts)) / 4294967295.0

## A pitch in `span` (semitones, inclusive) at least `gap` from `previous`.
## `unit` in [0, 1] walks the allowed pitches evenly, low to high, so the
## same unit always gives the same pitch. If nothing is far enough from
## `previous`, the whole span is allowed.
static func spread_pitch(span: Vector2, previous: float, gap: float, unit: float) -> float:
	var below := maxf(0.0, minf(previous - gap, span.y) - span.x)
	var above_start := maxf(previous + gap, span.x)
	var above := maxf(0.0, span.y - above_start)
	if below + above <= 0.0:
		return lerpf(span.x, span.y, unit)
	var at := unit * (below + above)
	return span.x + at if below > 0.0 and at <= below else above_start + (at - below)

func _source_at(sources: Array, index: int) -> String:
	return str(sources[index]) if index < sources.size() else ""

func _next_ordinal(key: String) -> int:
	var ordinal: int = _ordinals.get(key, 0)
	_ordinals[key] = ordinal + 1
	return ordinal

## Pitch (semitones) and gain from the cue identity. Each cause keeps its
## consecutive cues on one clip apart; that state is never shared between
## the live player and the memory.
func _cue_variation(key: String, source: String) -> Dictionary:
	var cause := source.get_slice("|", 0)
	var kind := source.get_slice("|", 1) if source.contains("|") else key
	var id := [turn_chapter, turn_stage, cause, kind, key, _next_ordinal(cause + "|" + kind + "|" + key)]
	var chain: String = cause + "|" + CLIPS[key].resource_path
	var step := spread_pitch(CUE_RANGES.get(key, Vector2.ZERO), float(last_steps.get(chain, NO_PITCH)), CUE_MIN_MOVE, identity_unit(id + ["step"]))
	last_steps[chain] = step
	var span: Vector2 = SoundCues.CUES[key].get("gain", SoundCues.CUE_GAIN)
	return {"step": step, "gain": lerpf(span.x, span.y, identity_unit(id + ["gain"]))}

## The light tick a tapped control gives (a Settings tile), when haptics are on.
const TAP_HAPTIC_MS := 12
func tap_haptic() -> void:
	if haptics_enabled and not backgrounded: _emit_haptic(TAP_HAPTIC_MS)

func _emit_haptic(duration_ms: int) -> void:
	if PlatformSupport.is_phone():
		Input.vibrate_handheld(duration_ms)

## One contact of a spirit's foot; `spirit` is its slot or role in this world.
func play_footstep(spirit: String = "") -> void:
	var ordinal := _next_ordinal(spirit + "|footstep")
	var id := [turn_chapter, turn_stage, spirit, "footstep", ordinal]
	# Neighbouring steps of one spirit never share a pitch.
	var detune := spread_pitch(SoundCues.FOOTSTEPS.detune, float(_step_detunes.get(spirit, NO_PITCH)), STEP_MIN_MOVE, identity_unit(id + ["pitch"]))
	_step_detunes[spirit] = detune
	if not sound_enabled or backgrounded or step_voices.is_empty():
		return
	var voice := step_voices[next_step % step_voices.size()]
	# Each spirit alternates its own two contacts; the second spirit starts on
	# the other one, so both stepping together still use both samples.
	voice.stream=FOOTSTEPS[(ordinal + (1 if spirit in ["p1", "b"] else 0)) % FOOTSTEPS.size()]
	voice.pitch_scale = semitones_to_pitch(detune)
	var span: Vector2 = SoundCues.FOOTSTEPS.gain
	voice.volume_db = STEP_DB + lerpf(span.x, span.y, identity_unit(id + ["gain"]))
	voice.play()
	next_step+=1

func _stop_effects() -> void:
	stop_reunion()
	for voice in voices:
		voice.stop()
	if is_instance_valid(long_voice): long_voice.stop()
	for voice in step_voices:
		voice.stop()
	if is_instance_valid(call_voice): call_voice.stop()

## In a turn the n-th meetup plays a fixed pitch; on Home it is random. Either
## way it slides at least REUNION_MIN_MOVE away from the last meetup.
func play_reunion() -> void:
	var pitch := NO_PITCH
	var gain := 0.0
	if in_turn():
		var id := [turn_chapter, turn_stage, "", "reunion", _next_ordinal("|reunion")]
		pitch = spread_pitch(REUNION_RANGE, _turn_reunion, REUNION_MIN_MOVE, identity_unit(id + ["note"]))
		_turn_reunion = pitch
		gain = lerpf(SoundCues.REUNION.gain.x, SoundCues.REUNION.gain.y, identity_unit(id + ["gain"]))
	if not sound_enabled or backgrounded or not is_instance_valid(reunion_voice): return
	if pitch == NO_PITCH:
		reunion_pitch = spread_pitch(REUNION_RANGE, reunion_pitch, REUNION_MIN_MOVE, variation.randf())
		pitch = reunion_pitch
		gain = variation.randf_range(SoundCues.REUNION.gain.x, SoundCues.REUNION.gain.y)
	reunion_voice.pitch_scale = semitones_to_pitch(pitch)
	reunion_voice.volume_db = REUNION_DB + gain
	reunion_voice.play()

func stop_reunion() -> void:
	if is_instance_valid(reunion_voice): reunion_voice.stop()

func _update_ambience() -> void:
	if not is_instance_valid(ambience):
		return
	if not sound_enabled or backgrounded:
		ambience.stop()
	elif not ambience.playing:
		ambience.play()
	_sync_loops()

# --- Loops: moving mechanisms and place beds ---------------------------------

## The world's mechanism started (1 up or out, -1 down or in) or stopped (0).
func _on_mechanism_moving(kind: String, id: String, direction: int) -> void:
	if direction == 0: _motions.erase(id)
	elif SoundCues.MOTION.has(kind): _motions[id] = {"kind": kind, "direction": direction}
	_sync_loops()

## The bed of the place on screen: the turn's chapter, else the idle place.
func place() -> String:
	return turn_chapter if in_turn() else idle_place

## Brings every loop and bed in line with what should sound now. Beds play
## while the world is on screen; mechanism loops only while it also moves.
func _sync_loops() -> void:
	if loop_voices.is_empty(): return
	var audible := sound_enabled and not backgrounded and is_instance_valid(_world) and _world.is_visible_in_tree()
	var moving := audible and _world.is_processing()
	var wanted := {}
	var calls := ""
	if audible:
		for bed: String in SoundCues.beds(place()):
			if SoundCues.CALLS.has(bed): calls = bed
			else: wanted["bed:" + bed] = {"loop": bed, "pitch": 0.0, "bed": true}
	if moving:
		for id: String in _motions:
			var motion: Dictionary = SoundCues.MOTION[_motions[id].kind]
			wanted[id] = {"loop": motion.loop, "pitch": float(motion.pitch) + (float(motion.rise) if int(_motions[id].direction) > 0 else 0.0), "bed": false}
	var instant := not sound_enabled or backgrounded
	_set_calls(calls, instant)
	for id: String in _sounding.keys():
		if not wanted.has(id): _release(_sounding[id], id, instant)
	for id: String in wanted:
		var spec: Dictionary = wanted[id]
		var voice: AudioStreamPlayer = _sounding.get(id)
		if voice == null:
			voice = _free_voice(bed_voices if spec.bed else loop_voices)
			if voice == null: continue
			_sounding[id] = voice
			voice.set_meta("sounding", id)
			voice.stream = _looped_clip(spec.loop)
			voice.volume_db = SILENT_DB
			voice.play()
		voice.pitch_scale = semitones_to_pitch(spec.pitch)
		_fade(voice, float(SoundCues.LOOPS[spec.loop].db))
	# Only a listened world with something to play needs watching.
	var watch := is_instance_valid(_world) and not instant and (not _motions.is_empty() or not SoundCues.beds(place()).is_empty())
	if is_instance_valid(_world_check) and _world_check.is_inside_tree():
		if watch and _world_check.is_stopped(): _world_check.start()
		elif not watch and not _world_check.is_stopped(): _world_check.stop()

# --- Calls: sparse one-shots over a bed (SoundCues.CALLS) ---------------------

## Starts or stops the place's calls. A new set waits its `first` span before
## singing; leaving fades a call that is still singing. A set whose timer has
## stopped (a call was due while its world hid) is armed again.
func _set_calls(key: String, instant: bool) -> void:
	if not is_instance_valid(_call_timer): return
	if key == calling and (key.is_empty() or not _call_timer.is_stopped()): return
	if key != calling:
		calling = key
		_call_timer.stop()
		if is_instance_valid(call_voice) and call_voice.playing: _release(call_voice, "", instant)
		_last_call = -1
		_call_pitch = NO_PITCH
	if key.is_empty() or not _call_timer.is_inside_tree(): return
	var first: Vector2 = SoundCues.CALLS[key].first
	_call_timer.start(variation.randf_range(first.x, first.y))

## Sings the next call and sets the timer for the one after it.
func _on_call_due() -> void:
	if calling.is_empty() or not sound_enabled or backgrounded or not is_instance_valid(call_voice): return
	if not is_instance_valid(_world) or not _world.is_visible_in_tree(): return
	var spec: Dictionary = SoundCues.CALLS[calling]
	var pick := next_call(spec, variation, _last_call, _call_pitch)
	_last_call = pick.variant
	_call_pitch = pick.pitch
	var variant: Dictionary = spec.variants[pick.variant]
	_kill_fade(call_voice)
	call_voice.stream = variant.clip
	call_voice.pitch_scale = semitones_to_pitch(pick.pitch + float(variant.get("pitch", 0.0)))
	call_voice.volume_db = float(spec.db) + float(variant.get("db", 0.0)) + pick.gain
	call_voice.play()
	_call_timer.start(variant.clip.get_length() / call_voice.pitch_scale + pick.gap)

## The next call of a set: a variant other than `last`, a pitch at least
## min_move from `last_pitch`, a gain, and the quiet gap after it ends. Draws
## the same four numbers from `rng` every time.
static func next_call(spec: Dictionary, rng: RandomNumberGenerator, last: int, last_pitch: float) -> Dictionary:
	var count: int = spec.variants.size()
	var repeat_free := last >= 0 and last < count and count > 1
	var variant := rng.randi_range(0, count - (2 if repeat_free else 1))
	if repeat_free and variant >= last: variant += 1
	var pitch := spread_pitch(spec.pitch, last_pitch, float(spec.min_move), rng.randf())
	var gain := rng.randf_range(spec.gain.x, spec.gain.y)
	var gap := rng.randf_range(spec.gap.x, spec.gap.y)
	return {"variant": variant, "pitch": pitch, "gain": gain, "gap": gap}

func _free_voice(pool: Array[AudioStreamPlayer]) -> AudioStreamPlayer:
	for voice: AudioStreamPlayer in pool:
		if str(voice.get_meta("sounding", "")).is_empty(): return voice
	return null

func _looped_clip(loop: String) -> AudioStreamWAV:
	if not _looped.has(loop): _looped[loop] = _looping(SoundCues.LOOPS[loop].clip)
	return _looped[loop]

func _fade(voice: AudioStreamPlayer, target_db: float) -> void:
	if is_equal_approx(float(voice.get_meta("target_db", SILENT_DB)), target_db): return
	voice.set_meta("target_db", target_db)
	_kill_fade(voice)
	if not voice.is_inside_tree():
		voice.volume_db = target_db
		return
	var tween := voice.create_tween()
	tween.tween_property(voice, "volume_db", target_db, LOOP_FADE)
	voice.set_meta("fade", tween)

## Frees the voice; it fades out first unless sound just went off.
func _release(voice: AudioStreamPlayer, id: String, instant: bool) -> void:
	_sounding.erase(id)
	voice.set_meta("sounding", "")
	voice.set_meta("target_db", SILENT_DB)
	_kill_fade(voice)
	if instant or not voice.is_inside_tree() or not voice.playing:
		voice.stop()
		return
	var tween := voice.create_tween()
	tween.tween_property(voice, "volume_db", SILENT_DB, LOOP_FADE)
	# A voice taken again during the fade keeps playing.
	tween.tween_callback(func(): if str(voice.get_meta("sounding", "")).is_empty(): voice.stop())
	voice.set_meta("fade", tween)

func _kill_fade(voice: AudioStreamPlayer) -> void:
	if not voice.has_meta("fade"): return
	var tween: Variant = voice.get_meta("fade")
	if tween is Tween and (tween as Tween).is_valid(): (tween as Tween).kill()
