extends RefCounted
## Keeps one Saved Games slot and this phone's side of it joined: the progress slot
## (cloud_save_bundle.gd, cloud_save_sources.gd), and each replay slot (cloud_replay_bundle.gd,
## cloud_replay_sources.gd) with its own codec, slot name and bookkeeping keys.
##
## When: never per frame or per tap. note() marks progress as possibly changed and waits
## DEBOUNCE_MS for things to settle (a chapter finished, Settings closed); flush() runs as soon as
## Home is showing (the app going to the background, sign-in). A run only happens at Home, where no
## chapter is open, and a run that finds nothing changed since the last sync (by the sources' cheap
## stamp) does no work at all. Offline, failures back off up to BACKOFF_CAP_MS; "unavailable" and
## "not_configured" wait for the next sign-in.
##
## How: open the slot, join the cloud copy, any conflicting copy and the local copy, apply what
## the phone lacks, then write the joined copy back only if the cloud lacks something. Decoding,
## joining, fingerprints and encoding run on a worker thread. A cloud copy this version cannot
## read (a newer app) is left untouched, so an older build never overwrites it. Progress made
## while a run waits on the network is not marked synced: the run is due again.
const Bundle = preload("res://services/platform_games/cloud_save_bundle.gd")
const Reaper = preload("res://services/worker_reaper.gd")

const SLOT := "after-you-progress"
const DEBOUNCE_MS := 20000
const BACKOFF_CAP_MS := 30 * 60 * 1000
## A conflict resolution can itself meet a newer conflict; give up after this many rounds.
const MAX_RESOLVE_ROUNDS := 3

## The slot's description in the platform's saved games list.
var description := ""
var slot := SLOT
## decode, merge, encode, fingerprint, adds_to and warm, as cloud_save_bundle.gd has them.
var codec: GDScript = Bundle
## Prefix of this slot's keys in the platform games state ("" for the progress slot).
var key_prefix := ""
var busy := false
var last_code := ""
## Tests set this to drive time.
var clock_ms: Callable = Time.get_ticks_msec
var _provider: RefCounted
var _sources: RefCounted
var _state: RefCounted
var _due_at := -1
var _force := false
var _failures := 0

## sources: ready(), at_home(), stamp(), collect() and apply(merged) (see cloud_save_sources.gd).
func _init(provider: RefCounted, sources: RefCounted, state: RefCounted, slot_name: String = SLOT, slot_codec: GDScript = Bundle, prefix: String = "") -> void:
	_provider = provider
	_sources = sources
	_state = state
	slot = slot_name
	codec = slot_codec
	key_prefix = prefix
	codec.warm()
	# Workers start later; the reaper is in the tree before any can be running at quit.
	Reaper.ensure()

func set_sources(sources: RefCounted) -> void:
	_sources = sources

## Progress may have changed: sync after a quiet moment.
func note() -> void:
	_due_at = int(clock_ms.call()) + DEBOUNCE_MS
	if _state != null: _state.set_cloud({key_prefix + "dirty": true})

## Sync as soon as possible. pull: also read the cloud when nothing changed here (another phone
## may have played); a pull also ends a wait for the next sign-in.
func flush(pull: bool = false) -> void:
	_due_at = int(clock_ms.call())
	_force = _force or pull
	if pull: _failures = 0

## Signed out or no longer offered: nothing is due until the next flush or note.
func stop() -> void:
	_due_at = -1
	_force = false

## Whether this slot ever finished a run on this install (a replay slot pulls only until it has).
func synced_once() -> bool:
	return _state != null and _state.cloud(key_prefix + "source_stamp") != null

func due() -> bool:
	return _due_at >= 0 and int(clock_ms.call()) >= _due_at and not busy

## Called by the owner's timer; runs a sync when one is due.
func poll() -> void:
	if due(): await run()

## One sync. {"ok", "code"?, "wrote", "applied"}. Never raises; a failure leaves the sync due.
func run() -> Dictionary:
	if busy: return {"ok": false, "code": "busy"}
	var sources := _sources
	if sources == null or not sources.ready() or not sources.at_home():
		return _later("not_ready", DEBOUNCE_MS)
	_due_at = -1
	var stamp: String = sources.stamp()
	if not _force and stamp == str(_state.cloud(key_prefix + "source_stamp", "")) and not bool(_state.cloud(key_prefix + "dirty", true)):
		return {"ok": true, "wrote": false, "applied": false}
	var forced := _force
	_force = false
	busy = true
	var outcome := await _sync(sources, stamp)
	busy = false
	last_code = str(outcome.get("code", ""))
	if outcome.ok:
		_failures = 0
	elif last_code in ["unavailable", "not_configured", "cloud_unreadable"]:
		_force = false # Until the next sign-in (flush with pull) or a new note.
	elif last_code in ["not_ready", "changed"]:
		_force = _force or forced
		_later(last_code, DEBOUNCE_MS)
	else:
		_failures += 1
		_force = _force or forced
		_later(last_code, mini(BACKOFF_CAP_MS, DEBOUNCE_MS * 3 * (1 << mini(_failures - 1, 6))))
	return outcome

func _later(code: String, delay_ms: int) -> Dictionary:
	last_code = code
	_due_at = int(clock_ms.call()) + delay_ms
	return {"ok": false, "code": code}

## Runs `work` on a worker thread and waits for it frame by frame (the SceneTree, not Main, which
## may be freed meanwhile). The work touches only its own copies. The shared reaper owns the
## worker, so an app closing mid-sync joins it before scripts are freed; a pool task still
## running a lambda at quit crashed the exit.
static func _offload(work: Callable) -> Variant:
	return await Reaper.run(work, true)

func _sync(sources: RefCounted, stamp: String) -> Dictionary:
	var local: Dictionary = await sources.collect()
	if local.is_empty(): return {"ok": false, "code": "not_ready"}
	var opened: Dictionary = await _provider.snapshot_open(slot)
	var codec_script := codec
	if not opened.ok: return opened
	var handle: String = opened.handle
	var first_bytes: PackedByteArray = opened.data
	var joined: Dictionary = await _offload(func() -> Dictionary:
		var copy: Dictionary = codec_script.decode(first_bytes)
		return {"cloud": copy, "merged": codec_script.merge(local, copy) if not copy.is_empty() else {}})
	var cloud: Dictionary = joined.cloud
	if cloud.is_empty():
		await _provider.snapshot_discard(handle)
		return {"ok": false, "code": "cloud_unreadable"}
	var merged: Dictionary = joined.merged
	var rounds := 0
	while opened.has("conflict"):
		var conflict_data: PackedByteArray = opened.conflict.data
		var held := merged
		var resolved: Dictionary = await _offload(func() -> Dictionary:
			var other: Dictionary = codec_script.decode(conflict_data)
			if other.is_empty(): return {}
			var next: Dictionary = codec_script.merge(held, other)
			return {"merged": next, "bytes": codec_script.encode(next)})
		if resolved.is_empty():
			# Never resolve over a copy this build cannot read: leave the conflict for a newer build.
			await _provider.snapshot_discard(handle)
			return {"ok": false, "code": "cloud_unreadable"}
		merged = resolved.merged
		rounds += 1
		if rounds > MAX_RESOLVE_ROUNDS:
			await _provider.snapshot_discard(handle)
			return {"ok": false, "code": "conflict_unresolved"}
		opened = await _provider.snapshot_resolve(handle, resolved.bytes)
		if not opened.ok: return opened
		handle = opened.handle
		var next_bytes: PackedByteArray = opened.data
		var held_next := merged
		var again: Dictionary = await _offload(func() -> Dictionary:
			var copy: Dictionary = codec_script.decode(next_bytes)
			return {"cloud": copy, "merged": codec_script.merge(held_next, copy) if not copy.is_empty() else {}})
		cloud = again.cloud
		if cloud.is_empty():
			await _provider.snapshot_discard(handle)
			return {"ok": false, "code": "cloud_unreadable"}
		merged = again.merged
	var final_merged := merged
	var final_cloud := cloud
	var resolved_any := rounds > 0
	var plan: Dictionary = await _offload(func() -> Dictionary:
		var writes: bool = resolved_any or codec_script.fingerprint(final_merged) != codec_script.fingerprint(final_cloud)
		return {"adds": codec_script.adds_to(final_merged, local), "writes": writes, "bytes": codec_script.encode(final_merged) if writes else PackedByteArray()})
	# Progress saved while this run waited is not in `local`: apply nothing over it now, still write
	# the joined copy (it holds nothing older than the cloud had), and come back for the rest.
	var changed_meanwhile: bool = sources != _sources or not sources.ready() or sources.stamp() != stamp
	var applied := false
	if plan.adds and not changed_meanwhile and sources.at_home():
		applied = await sources.apply(merged)
	var after: String = sources.stamp() if sources.ready() else ""
	var wrote := false
	if plan.writes:
		var committed: Dictionary = await _provider.snapshot_commit(handle, plan.bytes, description)
		if not committed.ok: return committed
		wrote = true
	else:
		await _provider.snapshot_discard(handle)
	var settled: bool = not changed_meanwhile and (applied or not plan.adds)
	_state.set_cloud({key_prefix + "source_stamp": after if settled else stamp, key_prefix + "dirty": not settled})
	if not settled: return {"ok": false, "code": "changed", "wrote": wrote, "applied": applied}
	return {"ok": true, "wrote": wrote, "applied": applied}
