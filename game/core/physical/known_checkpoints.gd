extends RefCounted
## Open turns fingerprints: the stage checkpoints this phone has proved, by
## checkpoint_hash. The server keeps an open turns checkpoint flat (no `proof`,
## its turns as turn_hashes), so a phone checks an earlier stage by hash only:
## two_pair_proof.gd takes a flat checkpoint when its hash is kept here. It is
## kept when a nested checkpoint verifies or one is derived from its turns, and
## services/open_turn_store.gd keeps them again from the checkpoints it stored
## once proved. Only open turns rules read it. Bounded, shared by every thread.
## Static vars live here, in a script that extends an engine class
## (tests/test_subclass_statics.gd).
const MAX_KNOWN := 4096
static var _known: Dictionary = {}
static var _lock := Mutex.new()

static func keep(checkpoint_hash: String) -> void:
	if checkpoint_hash.length() != 64: return
	_lock.lock()
	_known.erase(checkpoint_hash)
	_known[checkpoint_hash] = true
	while _known.size() > MAX_KNOWN: _known.erase(_known.keys()[0])
	_lock.unlock()

static func known(checkpoint_hash: String) -> bool:
	_lock.lock()
	var found := _known.has(checkpoint_hash)
	_lock.unlock()
	return found

static func clear() -> void:
	_lock.lock()
	_known.clear()
	_lock.unlock()

## `checkpoint` without its proof: the form the server keeps and sends.
static func flat(checkpoint: Dictionary) -> Dictionary:
	var value := checkpoint.duplicate(true)
	value.erase("proof")
	return value
