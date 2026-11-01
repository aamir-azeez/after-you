extends Logger
## Counts engine and script errors whose text holds one of the watched phrases,
## so a suite can check its log stays clean. A plain ERROR line never fails a
## suite on its own (the isolated runner fails only on script errors and
## reported failures). Errors may come from worker threads, hence the lock.
## start() installs it, stop() removes it; always stop before quitting.

var _phrases: Array = []
var _hits: Dictionary = {}
var _lock := Mutex.new()

static func start(phrases: Array):
	var watch = load("res://tests/log_watch.gd").new()
	watch._phrases = phrases
	OS.add_logger(watch)
	return watch

func stop() -> void:
	OS.remove_logger(self)

## How many watched errors held `phrase` so far.
func count(phrase: String) -> int:
	_lock.lock()
	var seen: int = _hits.get(phrase, 0)
	_lock.unlock()
	return seen

func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	var text := code + " " + rationale
	_lock.lock()
	for phrase: String in _phrases:
		if text.contains(phrase): _hits[phrase] = int(_hits.get(phrase, 0)) + 1
	_lock.unlock()
