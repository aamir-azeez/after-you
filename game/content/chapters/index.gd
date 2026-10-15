extends RefCounted
## Every registered chapter, in order: one descriptor file per chapter in this
## folder. Order is behaviour (the pickers, Home's browsing and the archived
## Story read it), so a new chapter is one line at the end of CHAPTERS. The
## family's shared facts are in services/chapter_families.gd.
##
## A descriptor declares `const DATA := {...}`. Pure data: scripts and scenes are
## resource path strings, and the only preload allowed is
## res://presentation/player_copy.gd, so copy is referenced, never repeated.
## Required fields:
##   "key":          "<level id>@<version>"
##   "family":       a row of services/chapter_families.gd
##   "definition":   [catalog script, static method, arguments...] giving the hashed definition
##   "world", "scene": the world script and the solo scene
##   "local_path":   the solo journey save. Never change it for a published chapter.
##   "copy":         title, summary, completion, checkpoint_title, checkpoint_text.
##                   No title = the definition's title; no checkpoint copy = the family's.
##   "thumbnail":    the picker image
##   "server":       {flag: the backend var gating creation, max_branches}. Only
##                   Relay may have flag "" (always creatable).
## Home places each keepsake by hand in presentation/home_keepsake_slots.gd
## (position, size, browse order); tests/test_home_keepsake_display.gd fails for
## a place without a slot.
## Optional fields, with the value a descriptor gets when it leaves one out:
const OPTIONAL := {
	## false keeps a loadable chapter out of the pickers.
	"released": true,
	## The newer version offered in this one's place.
	"superseded_by": "",
	## The earlier version whose keepsake places this one earns.
	"version_of": "",
	## Journey stages' {stage_id: {title, hint_a, hint_b}}.
	"stage_copy": {},
	## The chapter's Home places in order: {stage_id, title}.
	"keepsakes": [],
	## The scenery file under content/dressing/.
	"dressing": "",
	## Fold the world's static scenery into a few batches.
	"fold_static": true,
}
const REQUIRED := ["key", "family", "definition", "world", "scene", "local_path", "copy", "thumbnail", "server"]

const CHAPTERS := [
	preload("res://content/chapters/first_steps.gd"),
	preload("res://content/chapters/relay_isles.gd"),
	preload("res://content/chapters/high_and_low.gd"),
	preload("res://content/chapters/rolling_home.gd"),
	preload("res://content/chapters/a_house_for_two.gd"),
	preload("res://content/chapters/conservatory.gd"),
	preload("res://content/chapters/long_way_home.gd"),
	preload("res://content/chapters/the_wishing_well.gd"),
	preload("res://content/chapters/long_way_home_v2.gd"),
	preload("res://content/chapters/turn_of_the_tide.gd"),
	preload("res://content/chapters/sleeping_lighthouse_v2.gd"),
]

## Worked out once when this file loads, then only read (workers read it too).
static var _keys: Array[String] = _ordered_keys()
static var _data: Dictionary = _by_key()

## Registered keys in order. A copy: callers may change it.
static func keys() -> Array[String]:
	return _keys.duplicate()

## One chapter's descriptor with every optional field filled in, or {} if it is
## not registered. Read-only.
static func data(key: String) -> Dictionary:
	return _data.get(key, {})

static func _ordered_keys() -> Array[String]:
	var result: Array[String] = []
	for file: Script in CHAPTERS: result.append(str(file.DATA.get("key", "")))
	return result

static func _by_key() -> Dictionary:
	var result: Dictionary = {}
	for file: Script in CHAPTERS:
		var data: Dictionary = OPTIONAL.duplicate(true)
		data.merge(file.DATA, true)
		assert(not result.has(data.get("key")), "Two chapter descriptors share the key %s" % data.get("key"))
		data.make_read_only()
		result[str(data.get("key", ""))] = data
	return result
