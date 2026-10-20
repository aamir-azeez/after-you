extends RefCounted
## The verified-checkpoint memo behind room_proof.gd, shared by every proof. It
## lives in a script that extends an engine class: a static var in a subclass of
## a project script can crash the exit (tests/test_subclass_statics.gd).
static var memo: Dictionary = {}
static var mutex := Mutex.new()
## Pair replays run since the last clear; for tests and timing.
static var pair_replays := 0
