extends "res://tests/test_gl_warmup_coverage.gd"
## The GL warm-up coverage (test_gl_warmup_coverage.gd) for the physical and
## journey chapters, split off to stay inside CI's 120 s.

func _suite() -> String:
	return "gl_warmup_coverage_journey"

func _owns_the_rest() -> bool:
	return false
