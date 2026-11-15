extends RefCounted
## The cooperative and journey families' plan (services/level_layout.gd): a
## stage merged over its level is already floors, crossings, gates and owned
## spots, exactly as the engines and worlds read it.
const CooperativeCatalog = preload("res://core/cooperative/stage_catalog.gd")

static func plan(level: Dictionary, stage_id: String) -> Dictionary:
	return CooperativeCatalog.stage_definition(level, stage_id)
