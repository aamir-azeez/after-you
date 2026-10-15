extends RefCounted
## A stop request an owner shares with its worker: the owner asks, the worker
## checks between its own steps and ends early. Safe from either thread.
## Extend it for a worker that also reports progress.

var _mutex := Mutex.new()
var _stopped := false

func stop() -> void:
	_mutex.lock()
	_stopped = true
	_mutex.unlock()

func stopped() -> bool:
	_mutex.lock()
	var value := _stopped
	_mutex.unlock()
	return value
