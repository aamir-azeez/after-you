extends SceneTree
const Preferences = preload("res://services/hosting_notification_preferences.gd")
var checks := 0
var failures := 0
func _check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)
func _initialize() -> void:
	var path := "user://hosting-preferences-test-%d.cfg" % Time.get_ticks_usec()
	var service := Preferences.new(path)
	_check(service.read().is_empty(),"Hosting consent starts empty")
	var peer := "AAAAAAAAAAAAAAAAAAAAAA"
	var request := "BBBBBBBBBBBBBBBBBBBBBB"
	var owner := "CCCCCCCCCCCCCCCCCCCCCC"
	var scope := "https://synthetic.invalid:" + owner + ":" + "a".repeat(64)
	var preferences := {scope:{peer:request}}
	_check(service.save(preferences),"Consent saved outside gameplay settings")
	_check(Preferences.new(path).read() == preferences,"Consent survives restart")
	var invalid := {scope:{peer:"bad"}}
	_check(not service.save(invalid) and service.read() == preferences,"Invalid friendship token does not replace consent")
	_check(service.clear_owner(owner,"https://other.invalid") and service.read() == preferences,"Different server consent is preserved")
	_check(service.clear_owner(owner,"https://synthetic.invalid"),"Local account deletion clears matching scopes")
	_check(Preferences.new(path).read().is_empty(),"Deletion survives restart")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("HOSTING PREFERENCES: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
