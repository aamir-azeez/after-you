extends RefCounted
## Facts every chapter of one family shares, one row per family. A chapter's
## descriptor (content/chapters/<chapter>.gd) names its family; this table says
## how that family runs. Pure data: scripts are resource path strings, and the
## only preload is the player copy, so reading this never loads an engine.
##
## services/chapter_registry.gd reads this table; tests/fixtures/golden/registry.json
## pins what it gives for every chapter.
##
## Fields:
##   "cooperative":  ChapterRegistry.is_cooperative() (journeys included)
##   "simulation":   the engine script
##   "initial":      [catalog script, true if its initial_checkpoint() takes the definition]
##   "rules":        supported rules versions
##   "pinned_rules": true if a definition may pin later rules instead
##                   (the simulation's pinned_rules(definition) > 0 means [pinned])
##   "checkpoint_field": where a checkpoint's proof keeps the previous checkpoint
##   "stage_hud":    where in-play stage titles and hints come from:
##                   "authored" = the definition's stage, "stage_copy" = the
##                   descriptor's stage_copy (else the stage), "native" = the
##                   hashed stage's own native title and hints
##   "checkpoint_copy": the descriptor copy a chapter gets unless it names its own
##   "catch_assistance": the catch assistance setting applies to its turns
##   "fixture_dir":  folder under tests/fixtures/ for the chapter's fixtures
const PlayerCopy = preload("res://presentation/player_copy.gd")

const ROWS := {
	"relay": {"cooperative": false, "simulation": "res://core/v2/simulation_v2.gd",
		"initial": ["res://core/v2/stage_catalog.gd", true], "rules": [2, 8], "pinned_rules": false,
		"checkpoint_field": "previous_checkpoint", "stage_hud": "authored", "checkpoint_copy": {}, "fixture_dir": "v2",
		"catch_assistance": true},
	"first-steps": {"cooperative": false, "simulation": "res://core/first_steps/simulation.gd",
		"initial": ["res://core/first_steps/stage_catalog.gd", false], "rules": [4, 5, 8], "pinned_rules": false,
		"checkpoint_field": "checkpoint", "stage_hud": "authored", "checkpoint_copy": {}, "fixture_dir": "first_steps",
		"catch_assistance": true},
	"cooperative": {"cooperative": true, "simulation": "res://core/cooperative/simulation.gd",
		"initial": ["res://core/cooperative/stage_catalog.gd", true], "rules": [6, 8], "pinned_rules": true,
		"checkpoint_field": "checkpoint", "stage_hud": "authored",
		"checkpoint_copy": {"checkpoint_title": "A path kept", "checkpoint_text": PlayerCopy.COOPERATIVE_CHECKPOINT}, "fixture_dir": "cooperative",
		"catch_assistance": true},
	"journey": {"cooperative": true, "simulation": "res://core/journey/simulation.gd",
		"initial": ["res://core/journey/stage_catalog.gd", true], "rules": [7, 8], "pinned_rules": true,
		"checkpoint_field": "checkpoint", "stage_hud": "stage_copy",
		"checkpoint_copy": {"checkpoint_title": "A path kept", "checkpoint_text": PlayerCopy.COOPERATIVE_CHECKPOINT}, "fixture_dir": "journey",
		"catch_assistance": true},
	"lighthouse-room": {"cooperative": false, "simulation": "res://core/lighthouse/room_simulation.gd",
		"initial": ["res://core/lighthouse/room_catalog.gd", true], "rules": [11], "pinned_rules": false,
		"checkpoint_field": "checkpoint", "stage_hud": "native",
		"checkpoint_copy": {"checkpoint_title": "A path kept", "checkpoint_text": PlayerCopy.COOPERATIVE_CHECKPOINT}, "fixture_dir": "lighthouse",
		# The Lighthouse has no catch to assist; its records always say false.
		"catch_assistance": false},
}

static func row(family: String) -> Dictionary:
	return ROWS.get(family, {})
