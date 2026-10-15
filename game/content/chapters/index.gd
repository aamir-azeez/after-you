extends RefCounted
## Every registered chapter, in order, with its descriptor: one data file per
## chapter in this folder. Order is behaviour (the pickers, Home's browsing and
## the archived Story read it), so a new chapter is one line at the end of KEYS
## and one row in FILES. The family's shared facts are in
## services/chapter_families.gd.
##
## Not read by the game yet: tests/test_chapter_descriptors.gd proves every
## descriptor equals what the registry and the menu, Home and look tables give
## today, so the readers can move over one at a time.
##
## A descriptor declares `const DATA := {...}`. Pure data: scripts and scenes are
## resource path strings, and the only preload allowed is
## res://presentation/player_copy.gd, so copy is referenced, never repeated.
##   "key":          "<level id>@<version>"
##   "family":       a row of services/chapter_families.gd
##   "definition":   [catalog script, static method, arguments...] giving the hashed definition
##   "world", "scene": the world script and the solo scene
##   "local_path":   the solo journey save. Never change it for a published chapter.
##   "released":     false keeps a loadable chapter out of the pickers
##   "superseded_by": the newer version offered in its place, or ""
##   "version_of":   the earlier version whose keepsake places this one earns, or ""
##   "copy":         title, summary, completion, checkpoint_title, checkpoint_text.
##                   No title = the definition's title; no checkpoint copy = the family's.
##   "stage_copy":   journey stages' {stage_id: {title, hint_a, hint_b}}
##   "thumbnail":    the picker image
##   "keepsake_scale": "small" or "big"; "" for a version that shares its earlier keepsakes
##   "keepsakes":    the chapter's Home places in browse order: {stage_id, title,
##                   slot [x, z, yaw degrees], optional tweak {plinth, scale, ...}}
##   "dressing":     the scenery file under content/dressing/, or ""
##   "fold_static":  true to fold the world's static scenery
##   "server":       {flag: the backend var gating creation ("" = always), max_branches}
##   "golden":       {replay, fingerprint}: the golden suites that pin it

const KEYS: Array[String] = [
	"first-steps@1",
	"relay-isles@2",
	"high-and-low@1",
	"rolling-home@1",
	"a-house-for-two@1",
	"conservatory@1",
	"long-way-home@1",
	"the-wishing-well@1",
	"long-way-home@2",
	"turn-of-the-tide@1",
	"sleeping-lighthouse@2",
]

const FILES := {
	"first-steps@1": preload("res://content/chapters/first_steps.gd"),
	"relay-isles@2": preload("res://content/chapters/relay_isles.gd"),
	"high-and-low@1": preload("res://content/chapters/high_and_low.gd"),
	"rolling-home@1": preload("res://content/chapters/rolling_home.gd"),
	"a-house-for-two@1": preload("res://content/chapters/a_house_for_two.gd"),
	"conservatory@1": preload("res://content/chapters/conservatory.gd"),
	"long-way-home@1": preload("res://content/chapters/long_way_home.gd"),
	"the-wishing-well@1": preload("res://content/chapters/the_wishing_well.gd"),
	"long-way-home@2": preload("res://content/chapters/long_way_home_v2.gd"),
	"turn-of-the-tide@1": preload("res://content/chapters/turn_of_the_tide.gd"),
	"sleeping-lighthouse@2": preload("res://content/chapters/sleeping_lighthouse_v2.gd"),
}

static func data(key: String) -> Dictionary:
	var file: Script = FILES.get(key)
	return file.DATA if file != null else {}
