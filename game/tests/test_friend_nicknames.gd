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

func _write(file_path: String, text: String) -> void:
	var file := FileAccess.open(file_path,FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _cut_off_writes() -> void:
	var tmp := PATH + ".tmp"
	var names := Nicknames.new(PATH)
	check(names.set_nickname(SERVER,OWNER,FRIEND,"Sunny"),"A nickname saves before the cut-off write")
	check(not FileAccess.file_exists(tmp),"A finished save leaves no tmp file")
	var whole := FileAccess.get_file_as_string(PATH)
	# A write cut off part way only ever reaches the tmp file.
	_write(tmp,whole.substr(0,whole.length() / 2))
	check(Nicknames.new(PATH).nickname(SERVER,OWNER,FRIEND) == "Sunny","A cut-off tmp write keeps every saved nickname")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# Between removing the old file and renaming the new one, the tmp is the only copy.
	DirAccess.rename_absolute(PATH,tmp)
	check(Nicknames.new(PATH).nickname(SERVER,OWNER,FRIEND) == "Sunny","A whole tmp file is read when the primary is missing")
	DirAccess.rename_absolute(tmp,PATH)
	_write(PATH,whole.substr(0,whole.length() / 2))
	_write(tmp,whole)
	check(Nicknames.new(PATH).nickname(SERVER,OWNER,FRIEND) == "Sunny","A whole tmp file is read when the primary is damaged")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	_write(PATH,whole)
	DirAccess.make_dir_absolute(ProjectSettings.globalize_path(tmp))
	var blocked := Nicknames.new(PATH)
	check(not blocked.set_nickname(SERVER,OWNER,FRIEND,"Rain"),"A save that cannot write its tmp file reports failure")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	check(Nicknames.new(PATH).nickname(SERVER,OWNER,FRIEND) == "Sunny","A failed save leaves the previous file untouched")
	names.clear_owner(OWNER)

func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var names := Nicknames.new(PATH)
	check(names.nickname(SERVER,OWNER,FRIEND).is_empty(),"No nickname defaults to the friend code")
	check(names.set_nickname(SERVER,OWNER,FRIEND,"  Sunny  "),"A trimmed nickname saves")
	check(names.nickname(SERVER,OWNER,FRIEND) == "Sunny","The local nickname is returned")
	check(names.display_name(SERVER,OWNER,FRIEND,FRIEND.substr(0,8)) == "Sunny","The display helper prefers the saved nickname")
	check(names.display_name(SERVER,OWNER,"ffffffffffffffffffffff","Ally") == "Ally","The display helper falls back to the supplied label")
	check(names.display_name(SERVER,OWNER,"ffffffffffffffffffffff") == "a friend","Without a nickname the display helper says 'a friend', never a raw id")
	check(Nicknames.sentence_start(Nicknames.FALLBACK) == "A friend" and Nicknames.sentence_start("sunny") == "sunny","Only the fallback is capitalised at a sentence start; a nickname keeps its case")
	check(names.nickname("https://other.test",OWNER,FRIEND).is_empty(),"Nicknames are scoped to their server")
	var saved := FileAccess.get_file_as_string(PATH)
	for version: Variant in ["1", [1], {}, true]:
		_write(PATH, JSON.stringify({"schema_version": version, "entries": []}))
		var odd := FileAccess.get_file_as_string(PATH)
		check(Nicknames.new(PATH).nickname(SERVER,OWNER,FRIEND).is_empty() and FileAccess.get_file_as_string(PATH) == odd,"A nickname file whose version is not a number is read as none and left unchanged")
	_write(PATH, saved)
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
	_cut_off_writes()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH + ".tmp"))
	print("Friend nicknames: ",failures," failures")
	quit(0 if failures == 0 else 1)
