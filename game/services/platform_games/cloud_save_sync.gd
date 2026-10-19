extends RefCounted
## Keeps one Saved Games slot and this phone's progress joined (see cloud_save_bundle.gd).
##
## When: never per frame or per tap. note() marks progress as possibly changed and waits
## DEBOUNCE_MS for things to settle (a chapter finished, Settings closed); flush() runs at
## once (the app going to the background). A run that finds nothing changed since the last
## sync (by the sources' cheap stamp) does no work at all. Offline or signed out, the run
## stops and stays due; the next sign-in or note() tries again.
##
## How: open the slot, join the cloud copy, any conflicting copy and the local copy, apply what
## the phone lacks (only where the sources allow it right now), then write the joined copy back
## only if the cloud lacks something. A cloud copy this version cannot read (a newer app) is
## left untouched, so an older build never overwrites it.
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")

const SLOT := "after-you-progress"
const DEBOUNCE_MS := 20000
## A conflict resolution can itself meet a newer conflict; give up after this many rounds.
const MAX_RESOLVE_ROUNDS := 3

## The slot's description in the platform's saved games list.
var description := ""
var busy := false
var last_code := ""
## Tests set this to drive time.
var clock_ms: Callable = Time.get_ticks_msec
var _provider: RefCounted
var _sources: RefCounted
var _state: RefCounted
var _due_at := -1
var _force := false

## sources: ready(), stamp(), settings_stamp(), collect() and apply(merged) (see cloud_save_sources.gd).
func _init(provider: RefCounted, sources: RefCounted, state: RefCounted) -> void:
	_provider = provider
	_sources = sources
	_state = state

func set_sources(sources: RefCounted) -> void:
	_sources = sources

## Progress may have changed: sync after a quiet moment.
func note() -> void:
	_due_at = int(clock_ms.call()) + DEBOUNCE_MS
	if _state != null: _state.set_cloud({"dirty": true})

## Sync as soon as possible (the app is going to the background, or sign-in just finished).
## pull: also read the cloud when nothing changed here (another phone may have played).
func flush(pull: bool = false) -> void:
	_due_at = int(clock_ms.call())
	_force = _force or pull

func due() -> bool:
	return _due_at >= 0 and int(clock_ms.call()) >= _due_at and not busy

## Called by the owner's timer; runs a sync when one is due.
func poll() -> void:
	if due(): await run()

## One sync. {"ok", "code"?, "wrote", "applied"}. Never raises; a failure leaves the sync due.
func run() -> Dictionary:
	if busy: return {"ok": false, "code": "busy"}
	_due_at = -1
	if _sources == null or not _sources.ready():
		return _stop("not_ready")
	var stamp: String = _sources.stamp()
	if not _force and stamp == str(_state.cloud("source_stamp", "")) and not bool(_state.cloud("dirty", true)):
		return {"ok": true, "wrote": false, "applied": false}
	var forced := _force
	_force = false
	busy = true
	var outcome := await _sync(stamp)
	busy = false
	last_code = str(outcome.get("code", ""))
	if not outcome.ok and last_code not in ["cloud_unreadable"]:
		_due_at = int(clock_ms.call()) + DEBOUNCE_MS * 3
		_force = _force or forced
	return outcome

func _stop(code: String) -> Dictionary:
	last_code = code
	# Not now (a chapter is open, or the save is held): stay due and look again later.
	_due_at = int(clock_ms.call()) + DEBOUNCE_MS
	return {"ok": false, "code": code}

func _sync(stamp: String) -> Dictionary:
	var local: Dictionary = await _sources.collect()
	if local.is_empty(): return {"ok": false, "code": "not_ready"}
	var opened: Dictionary = await _provider.snapshot_open(SLOT)
	if not opened.ok: return opened
	var handle: String = opened.handle
	var cloud := Bundle.decode(opened.data)
	if cloud.is_empty():
		await _provider.snapshot_discard(handle)
		return {"ok": false, "code": "cloud_unreadable"}
	var rounds := 0
	var merged := Bundle.merge(local, cloud)
	while opened.has("conflict"):
		var other := Bundle.decode(opened.conflict.data)
		if other.is_empty():
			# Never resolve over a copy we cannot read: leave the conflict for a newer build.
			await _provider.snapshot_discard(handle)
			return {"ok": false, "code": "cloud_unreadable"}
		merged = Bundle.merge(merged, other)
		rounds += 1
		if rounds > MAX_RESOLVE_ROUNDS:
			await _provider.snapshot_discard(handle)
			return {"ok": false, "code": "conflict_unresolved"}
		opened = await _provider.snapshot_resolve(handle, Bundle.encode(merged))
		if not opened.ok: return opened
		handle = opened.handle
		cloud = Bundle.decode(opened.data)
		if cloud.is_empty():
			await _provider.snapshot_discard(handle)
			return {"ok": false, "code": "cloud_unreadable"}
		merged = Bundle.merge(merged, cloud)
	var applied := false
	if Bundle.adds_to(merged, local):
		applied = await _sources.apply(merged)
	var wrote := false
	# After a resolution the slot is open on the resolved copy: commit it so the platform keeps it.
	if rounds > 0 or Bundle.fingerprint(merged) != Bundle.fingerprint(cloud):
		var committed: Dictionary = await _provider.snapshot_commit(handle, Bundle.encode(merged), description)
		if not committed.ok: return committed
		wrote = true
	else:
		await _provider.snapshot_discard(handle)
	# Settled only when this phone now holds everything: otherwise the rest applies at a later run.
	var settled := applied or not Bundle.adds_to(merged, local)
	_state.set_cloud({"source_stamp": _sources.stamp() if settled else stamp, "dirty": not settled})
	return {"ok": true, "wrote": wrote, "applied": applied}
