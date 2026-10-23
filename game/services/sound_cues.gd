extends RefCounted
## Every sound the game plays, as data: cues, footsteps, the meetup greeting,
## loops, calls and beds, with their levels, pitch spans and haptics. Each sound is
## one entry here plus its asset; the synthesised assets come from
## scripts/generate_cues.py. Which simulation event plays which cue is
## services/chapter_sound_map.gd. The soundscape (services/soundscape.gd)
## holds only players and the rules that pick a pitch.

const Index = preload("res://content/chapters/index.gd")
## A place with no bed: shared and never written.
const NO_BEDS := []

const BRIDGE := preload("res://assets/audio/bridge.wav")
const READY := preload("res://assets/audio/ready.wav")
const THROW := preload("res://assets/audio/throw.wav")
const LAND := preload("res://assets/audio/land.wav")
const MISS := preload("res://assets/audio/miss.wav")
const CATCH := preload("res://assets/audio/catch.wav")
const BLOOM := preload("res://assets/audio/bloom.wav")
const BELL := preload("res://assets/audio/bell.wav")
const WELL_PLUNK := preload("res://assets/audio/well-plunk.wav")
const WATER_SURGE := preload("res://assets/audio/water-surge.wav")
const REEL := preload("res://assets/audio/reel.wav")
const SPOUT := preload("res://assets/audio/spout.wav")
const WATER_LAP := preload("res://assets/audio/water-lap.wav")
const BIRDS_1 := preload("res://assets/audio/birds-1.wav")
const BIRDS_2 := preload("res://assets/audio/birds-2.wav")
const BIRDS_3 := preload("res://assets/audio/birds-3.wav")
const BIRDS_FAR := preload("res://assets/audio/birds-far.wav")
const AMBIENCE := preload("res://assets/audio/ambience.wav")
const FOOTSTEP_1 := preload("res://assets/audio/footstep-1.wav")
const FOOTSTEP_2 := preload("res://assets/audio/footstep-2.wav")
const GREETING := preload("res://assets/audio/reunion.wav")
const POP := preload("res://assets/audio/pop.wav")
const WINCH := preload("res://assets/audio/winch.wav")
const BOLT := preload("res://assets/audio/bolt.wav")
const VALVE := preload("res://assets/audio/valve.wav")

## The level every cue plays at (dB), and how far its gain wanders unless its
## entry sets "gain".
const CUE_DB := -8.0
const CUE_GAIN := Vector2(-1.0, 1.0)

## One-shot cues of a recorded turn. Each event's pitch slides inside `range`
## (semitones) from the event's identity, so it sounds the same live, as the
## memory, on a retry and in a replay.
##   db:        level against the shared cue level (soundscape CUE_DB), default 0
##   gain:      dB span the event's gain wanders in, default CUE_GAIN
##   voice:     "long" for a ringing tail that a burst of short cues must not
##              cut; everything else shares the short-cue voices
##   haptic_ms: a live press vibrates the phone this long
## Tonal cues sit around the C-major ambience bed and favour upward shifts that
## small phone speakers still reproduce. A miss never rises above its source
## pitch, and a catch never falls below it.
const CUES := {
	"bridge_opened": {"clip": BRIDGE, "range": Vector2(0.0, 5.0)},
	"garden_opened": {"clip": READY, "range": Vector2(-3.0, 2.0)},
	"lift_ready": {"clip": READY, "range": Vector2(-3.0, 2.0)},
	"seed_thrown": {"clip": THROW, "range": Vector2(-2.0, 4.0)},
	"seed_landed": {"clip": LAND, "range": Vector2(0.0, 7.0)},
	# A miss is never louder than its source.
	"seed_missed": {"clip": MISS, "range": Vector2(-3.0, 0.0), "gain": Vector2(-1.0, 0.0)},
	"seed_caught": {"clip": CATCH, "range": Vector2(0.0, 5.0), "haptic_ms": 35},
	"island_bloomed": {"clip": BLOOM, "range": Vector2(0.0, 7.0), "haptic_ms": 85},
	"bell_rung": {"clip": BELL, "range": Vector2(0.0, 4.0), "voice": "long"},
	"lever_pulled": {"clip": CATCH, "range": Vector2(-5.0, -2.0)},
	"switch_set": {"clip": CATCH, "range": Vector2(2.0, 5.0)},
	"handoff_offered": {"clip": THROW, "range": Vector2(-2.0, 2.0)},
	# The Lighthouse tower bell: the same bell, a fourth or so lower.
	"tower_bell": {"clip": BELL, "range": Vector2(-5.0, -3.0), "voice": "long"},
	"bridge_closed": {"clip": BRIDGE, "range": Vector2(-5.0, -2.0), "db": -4.0},
	"ball_home": {"clip": READY, "range": Vector2(0.0, 3.0)},
	"receivers_joined": {"clip": READY, "range": Vector2(5.0, 9.0), "db": -2.0},
	"waypoint": {"clip": READY, "range": Vector2(-5.0, -1.0), "db": -10.0},
	"well_plunk": {"clip": WELL_PLUNK, "range": Vector2(-1.0, 1.0)},
	"water_rise": {"clip": WATER_SURGE, "range": Vector2(0.0, 2.0), "db": -4.0},
	"water_fall": {"clip": WATER_SURGE, "range": Vector2(-5.0, -3.0), "db": -5.0},
	# A crossing has started to close: the water rises over it before it shuts.
	"crossing_closing": {"clip": WATER_SURGE, "range": Vector2(2.0, 6.0), "db": -3.0},
	"spirit_drowned": {"clip": WELL_PLUNK, "range": Vector2(-7.0, -3.0)},
	# Controls drawn as machines (LOOK_CUES): a winch's pawl ticking as the chain
	# winds, lower as it pays out; a bolt sliding home into its catch, lower as it
	# draws back; a valve wheel's iron creak to its value.
	"winch_wound": {"clip": WINCH, "range": Vector2(-1.5, 1.5)},
	"winch_unwound": {"clip": WINCH, "range": Vector2(-4.5, -2.5)},
	"bolt_shot": {"clip": BOLT, "range": Vector2(-1.0, 1.5)},
	"bolt_drawn": {"clip": BOLT, "range": Vector2(-4.0, -2.0)},
	"valve_turned": {"clip": VALVE, "range": Vector2(-1.5, 1.5), "db": -1.0},
}

## A lever or selector drawn as a presentation/kit/lever_looks.gd kind (a
## chapter descriptor's "lever_looks") -> its cues: [pulled or set, let go].
## Any control with that look sounds like it; a control with no look keeps the
## shared lever and switch cues.
const LOOK_CUES := {
	"winch": ["winch_wound", "winch_unwound"],
	"bolt": ["bolt_shot", "bolt_drawn"],
	"valve": ["valve_turned", "valve_turned"],
}

## A spirit's foot contacts: each spirit alternates the clips; the step's
## identity picks a detune in `detune` (semitones) at least `min_move` from the
## spirit's last one, and a gain in `gain` around `db`.
const FOOTSTEPS := {"clips": [FOOTSTEP_1, FOOTSTEP_2], "db": -23.0, "gain": Vector2(-1.5, 1.5), "detune": Vector2(-1.0, 1.0), "min_move": 0.3}
## Two spirits meeting: one greeting, each meetup at least `min_move`
## semitones from the last inside `range` (random on Home, fixed in a turn).
const REUNION := {"clip": GREETING, "db": -8.0, "gain": Vector2(-0.75, 0.75), "range": Vector2(-2.0, 7.0), "min_move": 1.5}

## An end-of-run reaction (presentation/end_reactions.gd): a soft pop whose
## pitch (`range`, semitones) and gain come from the reaction alone, so the
## same reaction sounds the same picked, on the friend's card and in a rewatch.
const REACTION := {"clip": POP, "db": -4.0, "gain": Vector2(-0.75, 0.75), "range": Vector2(-2.0, 5.0)}

## Loops started and stopped by what the world shows. `db` is the player's
## own level (not relative), `pitch` a fixed shift; no loop varies its pitch.
const LOOPS := {
	# The calm C-major bed under every screen while sound is on.
	"ambience": {"clip": AMBIENCE, "db": -12.0},
	"reel": {"clip": REEL, "db": -20.0},
	"spout": {"clip": SPOUT, "db": -24.0},
	"water_near": {"clip": WATER_LAP, "db": -30.0},
	"water_far": {"clip": WATER_LAP, "db": -36.0},
}

## Sparse calls over a place's bed: one-shots on the one call voice, never a
## loop. Each call is a variant other than the last, pitched inside `pitch`
## (semitones, plus the variant's own "pitch") at least `min_move` from the
## last call, at `db` plus the variant's "db" plus a gain inside `gain`. The
## next call waits for this one to end and then a gap inside `gap` (seconds);
## the first waits inside `first` once the place shows. Calls are ambience,
## not recorded events, so they draw on the soundscape's private random
## generator and never touch a turn's cue identities.
const CALLS := {
	# The garden songbird the owner chose (03a): its three phrases and the far
	# bird's tsip. -39 dB keeps each call about 10 dB under the old loop and
	# the calm bed; the pitch span lowers it into a softer register.
	"birds": {
		"variants": [
			{"clip": BIRDS_1}, {"clip": BIRDS_2}, {"clip": BIRDS_3},
			{"clip": BIRDS_FAR, "db": -12.0, "pitch": -2.0},
		],
		"db": -39.0, "gain": Vector2(-2.0, 0.0), "pitch": Vector2(-4.0, -2.0), "min_move": 0.75,
		"gap": Vector2(6.0, 14.0), "first": Vector2(2.0, 8.0),
	},
}

## A world mechanism that moves (island_world.gd mechanism_moving) -> its
## loop and pitch in semitones; `rise` is added while it moves up or out.
## One shared reel serves every winch, so a new one is one line here.
const MOTION := {
	"bucket": {"loop": "reel", "pitch": 0.0, "rise": 2.0},
	"ladder": {"loop": "reel", "pitch": 4.0, "rise": 2.0},
	"fold": {"loop": "reel", "pitch": 7.0, "rise": 2.0},
	"lift": {"loop": "reel", "pitch": -3.0, "rise": 0.0},
	"drawbridge": {"loop": "reel", "pitch": 2.0, "rise": 2.0},
	"spout": {"loop": "spout", "pitch": 0.0, "rise": 0.0},
}

## Background layers under the shared ambience (a LOOPS or a CALLS name), per
## place that is not a registered chapter: "home" for the Home island, and the Lighthouse @1. A
## registered chapter's are its descriptor's "beds" (content/chapters/index.gd).
## They play only while that world is on screen.
const BEDS := {
	"sleeping-lighthouse@1": ["water_far"],
	"home": ["birds"],
}

## The cue of a control drawn as `look` (LOOK_CUES), else `fallback`.
## `released`: a lever let go rather than pulled.
static func look_cue(look: String, fallback: String, released: bool = false) -> String:
	if not LOOK_CUES.has(look): return fallback
	return str(LOOK_CUES[look][1 if released else 0])

## True for a name a bed may list: a loop, or a set of calls.
static func is_bed(name: String) -> bool:
	return LOOPS.has(name) or CALLS.has(name)

## The bed layers of a place: a chapter key or "home".
static func beds(place: String) -> Array:
	var chapter := Index.data(place)
	return chapter.beds if not chapter.is_empty() else BEDS.get(place, NO_BEDS)

## Problems with the tables, for the soundscape test.
static func problems() -> Array[String]:
	var found: Array[String] = []
	for key: String in CUES:
		var cue: Dictionary = CUES[key]
		if not (cue.get("clip") is AudioStream): found.append("Cue %s has no clip" % key)
		if not (cue.get("range") is Vector2) or cue.range.x > cue.range.y: found.append("Cue %s has no pitch range" % key)
		if cue.has("voice") and cue.voice != "long": found.append("Cue %s names an unknown voice" % key)
		if cue.has("gain") and not (cue.gain is Vector2): found.append("Cue %s has a bad gain span" % key)
	for look: String in LOOK_CUES:
		var pair: Variant = LOOK_CUES[look]
		if not (pair is Array and pair.size() == 2 and CUES.has(pair[0]) and CUES.has(pair[1])): found.append("Look %s needs a pulled and a let-go cue" % look)
	if not (REACTION.clip is AudioStream) or REACTION.range.x > REACTION.range.y or REACTION.gain.x > REACTION.gain.y: found.append("The reaction pop has a bad clip or span")
	for key: String in LOOPS:
		if not (LOOPS[key].get("clip") is AudioStreamWAV): found.append("Loop %s has no WAV clip" % key)
	for key: String in CALLS:
		found.append_array(call_problems(key, CALLS[key]))
	for kind: String in MOTION:
		if not LOOPS.has(MOTION[kind].get("loop", "")): found.append("Motion %s names an unknown loop" % kind)
	for key: String in CALLS:
		if LOOPS.has(key): found.append("%s is both a loop and a set of calls" % key)
	for place: String in BEDS:
		for problem: String in bed_problems(BEDS[place]): found.append("Bed %s: %s" % [place, problem])
	return found

## Problems with one place's bed list (BEDS or a chapter descriptor's "beds"):
## every name a loop or calls, and at most one set of calls for the one call voice.
static func bed_problems(beds: Array) -> Array[String]:
	var found: Array[String] = []
	var calls := 0
	for bed: Variant in beds:
		if not is_bed(str(bed)): found.append("%s is not a loop or calls" % bed)
		if CALLS.has(str(bed)): calls += 1
	if calls > 1: found.append("more than one set of calls")
	return found

static func call_problems(key: String, spec: Dictionary) -> Array[String]:
	var found: Array[String] = []
	var variants: Variant = spec.get("variants")
	if not (variants is Array) or variants.size() < 2: found.append("Calls %s need two variants or more" % key)
	else:
		for variant: Variant in variants:
			if not (variant is Dictionary and variant.get("clip") is AudioStreamWAV): found.append("Calls %s have a variant with no WAV clip" % key)
	for span: String in ["gain", "pitch", "gap", "first"]:
		if not (spec.get(span) is Vector2) or spec[span].x > spec[span].y: found.append("Calls %s have a bad %s span" % [key, span])
	if spec.get("gap") is Vector2 and spec.gap.x <= 0.0: found.append("Calls %s need a gap between calls" % key)
	if not (spec.get("db") is float): found.append("Calls %s have no level" % key)
	if not (spec.get("min_move") is float) or spec.min_move < 0.0: found.append("Calls %s have no pitch move" % key)
	return found
