extends "res://presentation/journey_world.gd"
## The Falls's world: the journey family's world, with no scenery of its own
## yet. Everything here is presentation; movement and gates come from the snapshot.

## The Falls is a long strip along x (its floors stay within z +-4.5 m), longer
## than the journey family's fixed camera band, so the camera scrolls over all
## of its floors.
func _follow_limits() -> Array[Vector2]:
	return _floors_follow_limits()
