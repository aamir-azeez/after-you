extends SceneTree
const Nicknames = preload("res://services/friend_nicknames.gd")
const PATH := "user://friend_nicknames_test.json"
const SERVER := "https://example.test"
const OWNER := "aaaaaaaaaaaaaaaaaaaaaa"
const FRIEND := "bbbbbbbbbbbbbbbbbbbbbb"
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, label: String) -> void:
	if not value: failures += 1; push_error(label)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var names := Nicknames.new(PATH)
	check(names.nickname(SERVER,OWNER,FRIEND).is_empty(),"No nickname defaults to the friend code")
	check(names.set_nickname(SERVER,OWNER,FRIEND,"  Sunny  "),"A trimmed nickname saves")
	check(names.nickname(SERVER,OWNER,FRIEND) == "Sunny","The local nickname is returned")
	check(names.display_name(SERVER,OWNER,FRIEND,FRIEND.substr(0,8)) == "Sunny","The display helper prefers the saved nickname")
	check(names.display_name(SERVER,OWNER,"ffffffffffffffffffffff","Ally") == "Ally","The display helper falls back to the supplied label")
	check(names.display_name(SERVER,OWNER,"ffffffffffffffffffffff") == "ffffffff","The display helper falls back to a short friend code")
	check(names.nickname("https://other.test",OWNER,FRIEND).is_empty(),"Nicknames are scoped to their server")
	check(names.nickname(SERVER,"cccccccccccccccccccccc",FRIEND).is_empty(),"Nicknames are scoped to their owner")
	var restarted := Nicknames.new(PATH)
	check(restarted.nickname(SERVER,OWNER,FRIEND) == "Sunny","Nicknames persist across service restart")
	check(not restarted.set_nickname(SERVER,OWNER,FRIEND,"x".repeat(33)),"Nicknames over 32 Unicode characters are rejected")
	check(not restarted.set_nickname(SERVER,OWNER,FRIEND,"bad\nname"),"Control characters are rejected")
	check(restarted.set_nickname(SERVER,OWNER,FRIEND,"é🙂".repeat(16)),"A nickname with 32 Unicode characters is accepted")
	check(not restarted.set_nickname(SERVER,OWNER,FRIEND,"é🙂".repeat(17)),"Unicode length is measured in characters")
	check(restarted.set_nickname(SERVER,OWNER,FRIEND,"   "),"An empty nickname resets to the friend code")
	check(restarted.nickname(SERVER,OWNER,FRIEND).is_empty(),"Reset removes the saved nickname")
	check(restarted.set_nickname(SERVER,OWNER,FRIEND,"Sunny"),"Nickname can be restored")
	restarted.clear_friend(SERVER,OWNER,FRIEND)
	check(restarted.nickname(SERVER,OWNER,FRIEND).is_empty(),"Removing a friend clears its nickname")
	check(restarted.set_nickname(SERVER,OWNER,FRIEND,"Sunny"),"Nickname can be set before account cleanup")
	restarted.clear_owner(OWNER)
	check(restarted.nickname(SERVER,OWNER,FRIEND).is_empty(),"Owner cleanup removes local nicknames")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("Friend nicknames: ",failures," failures")
	quit(0 if failures == 0 else 1)
