extends "res://presentation/water_world.gd"
## The Falls's world: the water world (presentation/water_world.gd) with the
## chapter's water and dressing; its scenery is data (content/water/the_falls.gd,
## content/dressing/the_falls.gd). Everything here is presentation; movement and gates
## come from the snapshot.

## The Falls is a long strip along x (its floors stay within z +-4.5 m), longer
## than the journey family's fixed camera band, so the camera scrolls over all
## of its floors.
func _follow_limits() -> Array[Vector2]:
	return _floors_follow_limits()
