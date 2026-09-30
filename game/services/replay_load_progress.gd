extends RefCounted
## A worker reports completed checks; only the main thread updates controls.
var _mutex := Mutex.new()
var _checked := 0
var _total := 0
var _phase := "entries"
var _cancelled := false

func cancel() -> void:
	_mutex.lock()
	_cancelled=true
	_mutex.unlock()

func cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value

func set_total(count: int) -> void:
	_mutex.lock()
	_total=maxi(0,count)
	_checked=0
	_mutex.unlock()

func advance() -> void:
	_mutex.lock()
	_checked=mini(_checked+1,_total)
	_mutex.unlock()

func set_phase(value: String) -> void:
	_mutex.lock()
	_phase=value
	_mutex.unlock()

func snapshot() -> Dictionary:
	_mutex.lock()
	var result := {"checked":_checked,"total":_total,"phase":_phase}
	_mutex.unlock()
	return result
