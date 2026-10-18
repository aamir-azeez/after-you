extends RefCounted
## Why a crossing the live spirit has done its part for is still shut: the
## memory's part is not there yet. Shared by every journey world
## (journey_world.gd); a chapter turns it on with data alone, its descriptor's
## "wait_hints" (content/chapters/index.gd):
##   "reasons":   {mechanism id: phrase}. A control listed in the descriptor's
##                "water_levels" may give {"too_low": phrase, "too_high": phrase}
##                instead, picked by which side of the wanted level it stands.
##   "fallback":  the phrase for a reason with no phrase of its own.
##   "never":     the phrase once the memory has ended without its part.
##   "crossings": {route id: what to call it}; otherwise `crossing`.
## A phrase may name the crossing with {crossing}.
##
## A gate can give a hint when its condition is one term or an "all" of single
## terms (a gate with an "any" in it is left out: no single term is the
## reason), at least one term is the live spirit's own lever or selector and
## at least one is the memory's.
## In the live spirit's turn it shows while the crossing is shut, every one of
## the live spirit's terms holds, at least one of them is its doing (a lever
## it pulled, or a selector it turned from where the turn began) and a
## memory's term does not hold. The reason is the memory's first such term in
## the gate's order. Once the memory has ended (its recording is that many
## ticks long), what it left is final: a memory term still unmet then keeps
## the crossing shut for the rest of the turn, "never". Until then the memory
## may still get there, so the reason is said as a wait. One hint per lever or
## selector: the first gate in order.
##
## Pure: reads the snapshot, the stage and the descriptor data through the
## same gate check the simulation uses (seven_mechanisms.gd), and feeds
## nothing back. It works out the hints again only when a mechanism, a
## crossing or a step the hints read has changed, or the memory has just
## ended (`evaluations` counts it).
const Seven = preload("res://core/journey/seven_mechanisms.gd")
const TERM_KEYS: Array[String] = ["control_id", "lever_id", "pad_id", "signal_id"]
const NO_TABLE := {}

## What the hints say now, one per lever or selector:
## [{"route", "anchor" (the live spirit's lever or selector id), "text"}].
var shown: Array = []
## How many times the hints were worked out (tests count it).
var evaluations := 0

var _stage: Dictionary = {}
var _phrases: Dictionary = {}
var _water: Dictionary = {}
var _default_crossing := ""
## Per hint-able gate: {"route", "anchor", "live": [terms], "memory": [terms],
## "doing": [the live levers' and selectors' terms]}.
var _candidates: Array = []
## Pads the candidates read, and the selectors' values where the turn began
## (the checkpoint's, over the stage's initial ones).
var _pads: Array = []
var _pad_bits := PackedByteArray()
var _start_controls: Dictionary = {}
var _checkpoint_controls: Dictionary = {}
## The memory's length in ticks (MemoryWait.prior_ticks), or -1 unknown.
var _memory_ticks := -1
var _live_slot := ""
## The last snapshot's parts the hints read, by reference, and whether they
## must be worked out again whatever those say.
var _seen_levers: Variant = null
var _seen_controls: Variant = null
var _seen_bridges: Variant = null
var _seen_signals: Variant = null
var _seen_role := ""
var _seen_over := false
var _dirty := true

## The stage being shown and the chapter's descriptor (or any Dictionary with
## its "wait_hints" and "water_levels"). default_crossing: what a crossing
## with no name of its own is called.
func setup(stage: Dictionary, descriptor: Dictionary, default_crossing: String) -> void:
	_stage = stage
	_phrases = descriptor.get("wait_hints", {})
	_water = descriptor.get("water_levels", {})
	_default_crossing = default_crossing
	_candidates = []
	_pads = []
	shown = []
	_dirty = true
	var first := str(stage.get("first_player_slot", ""))
	_live_slot = "p1" if first == "p0" else "p0"
	if _phrases.is_empty() or first.is_empty(): return
	var owners: Dictionary = {}
	var kinds: Dictionary = {}
	for key: String in ["controls", "levers", "pressure_pads"]:
		for item: Dictionary in stage.get(key, []):
			owners[str(item.id)] = str(item.get("owner_slot", ""))
			kinds[str(item.id)] = key
	for gate: Dictionary in stage.get("gates", []):
		var when: Dictionary = gate.get("when", {})
		if when.is_empty() or when.has("any"): continue
		var terms: Array = when.all if when.has("all") else [when]
		var live: Array = []
		var memory: Array = []
		var doing: Array = []
		var anchor := ""
		var usable := true
		for term: Dictionary in terms:
			var id := term_id(term)
			if id.is_empty() or not owners.has(id):
				usable = false
				break
			if owners[id] == _live_slot:
				live.append(term)
				if kinds[id] in ["levers", "controls"]:
					doing.append(term)
					# The first lever, else the first selector.
					if anchor.is_empty() or (kinds[id] == "levers" and kinds[anchor] != "levers"): anchor = id
			elif owners[id] == first: memory.append(term)
			else: usable = false
		if not usable or doing.is_empty() or memory.is_empty(): continue
		for term: Dictionary in memory:
			if term.has("pad_id") and str(term.pad_id) not in _pads: _pads.append(str(term.pad_id))
		for term: Dictionary in live:
			if term.has("pad_id") and str(term.pad_id) not in _pads: _pads.append(str(term.pad_id))
		_candidates.append({"route": str(gate.route_id), "anchor": anchor, "live": live, "memory": memory, "doing": doing})
	_pad_bits.resize(_pads.size())
	_apply_start()

## Whether this stage has a crossing that can give a hint.
func has_candidates() -> bool:
	return not _candidates.is_empty()

## Each crossing that can give a hint and the live spirit's lever or selector
## its hint stands over: [{"route", "anchor"}].
func candidates() -> Array:
	return _candidates.map(func(candidate: Dictionary) -> Dictionary: return {"route": candidate.route, "anchor": candidate.anchor})

## What this stage's hints can ever say: {"reasons": {mechanism id: the sides
## a water control can be on ("too_low", "too_high"), or [""] for any other},
## "crossings": [route ids]}. A descriptor lists nothing outside it.
func reachable() -> Dictionary:
	var reasons: Dictionary = {}
	var routes: Array = []
	for candidate: Dictionary in _candidates:
		routes.append(candidate.route)
		for term: Dictionary in candidate.memory:
			var id := term_id(term)
			var sides: Array = reasons.get(id, [])
			var levels: Array = _water.get(id, [])
			var wanted := levels.find(str(term.get("value", "")))
			var reachable_sides: Array = [""] if wanted < 0 else []
			if wanted > 0: reachable_sides.append("too_low")
			if wanted >= 0 and wanted < levels.size() - 1: reachable_sides.append("too_high")
			for side: String in reachable_sides:
				if side not in sides: sides.append(side)
			reasons[id] = sides
	return {"reasons": reasons, "crossings": routes}

## Where the turn began (the checkpoint shown as history): selectors turned
## from these values count as the live spirit's doing.
func set_start(checkpoint: Dictionary) -> void:
	var controls: Variant = checkpoint.get("mechanisms", {}).get("controls")
	_checkpoint_controls = controls if controls is Dictionary else {}
	_apply_start()
	_dirty = true

func _apply_start() -> void:
	_start_controls = {}
	for control: Dictionary in _stage.get("controls", []):
		_start_controls[str(control.id)] = str(_checkpoint_controls.get(control.id, control.get("initial", "")))

## The memory's length in ticks; -1 when unknown, which never says "never".
func set_memory_ticks(ticks: int) -> void:
	_memory_ticks = ticks
	_dirty = true

## Works the hints out again if what they read has changed since the last
## call. Returns whether `shown` may have changed.
func update(state: Dictionary) -> bool:
	if _candidates.is_empty() or not state.has("players"):
		if shown.is_empty(): return false
		shown = []
		return true
	# Read without defaults: an unchanged tick allocates nothing.
	var held: Variant = state.get("mechanisms")
	var mechanisms: Dictionary = held if held is Dictionary else NO_TABLE
	var optics: Variant = state.get("optics")
	var signals: Variant = optics.get("signals") if optics is Dictionary else null
	var role := str(state.get("role", ""))
	var over := _memory_ticks >= 0 and int(state.get("tick", 0)) >= _memory_ticks
	var changed := _dirty or role != _seen_role or over != _seen_over or not _same(mechanisms.get("levers"), _seen_levers) or not _same(mechanisms.get("controls"), _seen_controls) \
		or not _same(state.get("bridges"), _seen_bridges) or not _same(signals, _seen_signals)
	for index in range(_pads.size()):
		var bit := 1 if _pad_held(state.players, _pads[index]) else 0
		if _pad_bits[index] != bit:
			_pad_bits[index] = bit
			changed = true
	if not changed: return false
	_dirty = false
	_seen_role = role
	_seen_over = over
	_seen_levers = mechanisms.get("levers")
	_seen_controls = mechanisms.get("controls")
	_seen_bridges = state.get("bridges")
	_seen_signals = signals
	evaluations += 1
	var before := shown
	shown = _evaluate(state, mechanisms, signals if signals is Dictionary else NO_TABLE, over) if role == "b" and not bool(state.get("finished", false)) else []
	return shown != before

func _evaluate(state: Dictionary, mechanisms: Dictionary, signals: Dictionary, over: bool) -> Array:
	var result: Array = []
	var used: Dictionary = {}
	var routes: Dictionary = state.get("bridges", {})
	for candidate: Dictionary in _candidates:
		if used.has(candidate.anchor) or bool(routes.get(candidate.route, false)): continue
		var ready := true
		for term: Dictionary in candidate.live:
			if not Seven.predicate(term, _stage, state.players, mechanisms, signals):
				ready = false
				break
		if not ready or not _did_something(candidate.doing, mechanisms): continue
		var reason: Dictionary = {}
		for term: Dictionary in candidate.memory:
			if not Seven.predicate(term, _stage, state.players, mechanisms, signals):
				reason = term
				break
		if reason.is_empty(): continue
		used[candidate.anchor] = true
		result.append({"route": candidate.route, "anchor": candidate.anchor, "text": _text(candidate, reason, mechanisms, over)})
	return result

## A lever pulled, or a selector turned from where the turn began.
func _did_something(doing: Array, mechanisms: Dictionary) -> bool:
	for term: Dictionary in doing:
		if term.has("lever_id"): return true
		if str(mechanisms.get("controls", {}).get(term.control_id, "")) != str(_start_controls.get(str(term.control_id), "")): return true
	return false

## over: the memory has ended, so its unmet term stays unmet this turn.
func _text(candidate: Dictionary, reason: Dictionary, mechanisms: Dictionary, over: bool) -> String:
	var phrase := str(_phrases.get("never", "")) if over else phrase_for(reason, mechanisms)
	var crossing := str(_phrases.get("crossings", {}).get(candidate.route, _default_crossing))
	return phrase.replace("{crossing}", crossing)

## The descriptor's phrase for an unmet term, as the snapshot now stands.
func phrase_for(term: Dictionary, mechanisms: Dictionary) -> String:
	var fallback := str(_phrases.get("fallback", ""))
	var phrase: Variant = _phrases.get("reasons", {}).get(term_id(term), fallback)
	if phrase is Dictionary and term.has("control_id"):
		var levels: Array = _water.get(str(term.control_id), [])
		var wanted := levels.find(str(term.value))
		var now := levels.find(str(mechanisms.get("controls", {}).get(term.control_id, "")))
		if wanted < 0 or now < 0: return str(phrase.get("too_low", fallback))
		phrase = phrase.get("too_low" if now < wanted else "too_high", fallback)
	return str(phrase)

static func term_id(term: Dictionary) -> String:
	for key: String in TERM_KEYS:
		if term.has(key): return str(term[key])
	return ""

func _pad_held(players: Dictionary, pad_id: String) -> bool:
	for pad: Dictionary in _stage.get("pressure_pads", []):
		if str(pad.id) == pad_id: return players.has(pad.owner_slot) and Seven.near(players[pad.owner_slot], pad)
	return false

## Dictionaries compare by value; anything else (absent) only to itself.
static func _same(now: Variant, before: Variant) -> bool:
	if now is Dictionary and before is Dictionary: return now == before
	return typeof(now) == typeof(before)
