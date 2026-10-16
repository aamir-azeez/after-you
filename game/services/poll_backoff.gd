extends RefCounted
## The wait before a poller's next read. For the first minute after a reset
## every read waits the base (3 s for a room), so play stays quick right after
## a move. After that, a read that found nothing new waits half as long again
## as the one before, up to a cap: 4.5, 6.75, 10.125, then 15 s. A change, a
## tap, a resume or the player's own action resets it. Pure integer math over
## the waits it hands out, with no clock and no randomness.

const BASE_MS := 3000
const CAP_MS := 15000
const STEADY_MS := 60000

var base_ms := BASE_MS
var cap_ms := CAP_MS
var steady_ms := STEADY_MS
var _delay_ms := BASE_MS
var _steady_spent := 0
var _seen := 0
var _has_seen := false


func _init(base: int = BASE_MS, cap: int = CAP_MS, steady: int = STEADY_MS) -> void:
	base_ms = maxi(1, base)
	cap_ms = maxi(base_ms, cap)
	steady_ms = maxi(base_ms, steady)
	_delay_ms = base_ms


## The wait after a successful read.
func next_ms(changed: bool) -> int:
	if changed: reset()
	if _steady_spent < steady_ms:
		_delay_ms = base_ms
		_steady_spent += base_ms
	else:
		_delay_ms = mini(cap_ms, _delay_ms * 3 / 2)
	return _delay_ms


## A change, tap, resume, own action or new room: reads wait the base again
## for the next minute.
func reset() -> void:
	_delay_ms = base_ms
	_steady_spent = 0


## True when `value` differs from what the last call saw (always true the
## first time). For pollers whose reply carries no change signal of its own.
func observe(value: Variant) -> bool:
	var fingerprint := hash(value)
	var changed := not _has_seen or fingerprint != _seen
	_seen = fingerprint
	_has_seen = true
	return changed
