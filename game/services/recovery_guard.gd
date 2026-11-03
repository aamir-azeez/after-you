extends RefCounted
## The one gate in front of the recovery code, for every screen that shows or copies it
## (presentation/account_flow.gd owns it; presentation/platform_games_flow.gd copies through it):
## - the phone's screen lock before the code shows or is copied. A phone with no screen lock
##   has nothing to ask, and a build whose plugin has no check yet (iOS, desktop) skips it;
## - Android's private screen (no screenshots, a blank app switcher picture) while any
##   protected control is on screen;
## - after a paste import, the details taken back off the clipboard.
## An unlock lasts until the app goes to the background, or UNLOCK_MS at most.
##
## Host contract (Main): secrets, _await_secret, application_backgrounded, get_tree.

const Typed = preload("res://services/typed_values.gd")
const SecretStore = preload("res://services/secure_store.gd")
const UNLOCK_MS := 300000
## unlock()'s answers: show the code; say it stays hidden; or say nothing, because a
## screen lock prompt is already open and its answer is still coming.
enum { ALLOWED, REFUSED, WAITING }
## The phone answered that it cannot show its lock check at all. The code shows then:
## it may be the only copy of a new code (the recovery storage failure screen), and
## nobody holding the phone can bring this answer about.
const OPEN_ON := ["device_check_unavailable"]
## The native side still has a prompt open.
const WAIT_ON := ["device_check_busy"]
## copy()'s answers when the player did not unlock, when a prompt is already open, and
## when the details changed meanwhile.
const NOT_CONFIRMED := "not_confirmed"
const WAITING_CODE := "waiting"
const NOT_CURRENT := "not_current"

var host: Node
var _unlocked_at := -1
var _confirming := false
## instance id -> WeakRef of each protected control.
var _protected: Dictionary = {}
var _private := false
var _settling := false

func _init(main: Node = null) -> void:
	host = main

func _secrets() -> Object:
	return host.secrets if host != null else null

## The build can ask for the screen lock. Test doubles without the method count as no check.
func check_supported() -> bool:
	var secrets := _secrets()
	return secrets != null and secrets.has_method("device_check_supported") and secrets.device_check_supported()

func unlocked() -> bool:
	return _unlocked_at >= 0 and Time.get_ticks_msec() - _unlocked_at < UNLOCK_MS

## ALLOWED when the code may show or be copied now, REFUSED when the player cancelled
## (or the check failed or timed out), WAITING when a prompt is already open: one prompt
## at a time, so a second tap asks nothing more.
func unlock() -> int:
	if unlocked() or not check_supported(): return ALLOWED
	if _confirming: return WAITING
	_confirming = true
	var result: Dictionary = await host._await_secret(_secrets().confirm_device(), SecretStore.CONFIRM_TIMEOUT_MS + 1000)
	_confirming = false
	var payload: Variant = result.get("payload")
	if result.get("ok", false) and payload is Dictionary and Typed.equal(payload.get("confirmed"), true):
		_unlocked_at = Time.get_ticks_msec()
		return ALLOWED
	var code := str(result.get("code", ""))
	if code in OPEN_ON: return ALLOWED
	return WAITING if code in WAIT_ON else REFUSED

## The app went to the background: the next look asks again.
func lock() -> void:
	_unlocked_at = -1

## Copies the details once the screen lock allows it. The secure store's answer, or
## {"ok": false, "code": NOT_CONFIRMED} when the player did not unlock, WAITING_CODE when a
## prompt is already open, or NOT_CURRENT when `still_current` (asked again after the
## prompt) says the details changed meanwhile.
func copy(player: String, code: String, still_current: Callable = Callable()) -> Dictionary:
	var answer: int = await unlock()
	if answer == WAITING: return {"ok": false, "code": WAITING_CODE}
	if answer != ALLOWED: return {"ok": false, "code": NOT_CONFIRMED}
	if still_current.is_valid() and still_current.call() != true: return {"ok": false, "code": NOT_CURRENT}
	return await host._await_secret(_secrets().copy_recovery(player, code))

## After a paste import: the details come off the clipboard when they are still there.
func clear_clip(code: String) -> void:
	var secrets := _secrets()
	if secrets != null and secrets.has_method("clear_recovery_clip"): secrets.clear_recovery_clip(code)

## Keeps the private screen on while `control` is in the tree and visible. Freeing or hiding
## it is enough to let the block go; no close call is needed on any path.
func protect(control: Control) -> void:
	if control == null: return
	var id := control.get_instance_id()
	if not _protected.has(id):
		_protected[id] = weakref(control)
		control.visibility_changed.connect(_update)
		control.tree_exited.connect(_update)
	_update()

## Main calls this when the app is in front again: a block held over the background lets go now.
func resumed() -> void:
	_update()

func private_screen() -> bool:
	return _private

func _update() -> void:
	if _shown(): _set_private(true)
	elif _private: _settle()

## Any protected control on screen; forgets the ones that left the tree.
func _shown() -> bool:
	var shown := false
	for id: int in _protected.keys():
		var control := _protected[id].get_ref() as Control
		if control == null or not control.is_inside_tree(): _protected.erase(id)
		elif control.is_visible_in_tree(): shown = true
	return shown

## The block lets go only once the app is in front and the hidden screen has been drawn,
## so the app switcher never keeps a picture of the details.
func _settle() -> void:
	if _settling: return
	_settling = true
	if is_instance_valid(host) and host.is_inside_tree():
		var tree := host.get_tree()
		await tree.process_frame
		await tree.process_frame
	_settling = false
	if not is_instance_valid(host) or bool(host.get("application_backgrounded")): return
	if not _shown(): _set_private(false)

func _set_private(on: bool) -> void:
	if on == _private: return
	_private = on
	var secrets := _secrets()
	if secrets != null and secrets.has_method("set_private_screen"): secrets.set_private_screen(on)
