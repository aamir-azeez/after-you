extends RefCounted
## tide_world.gd's wall layouts, built once per layout key and shared. They live
## in a script that extends an engine class: a static var in a subclass of a
## project script can crash the exit (tests/test_subclass_statics.gd).
static var layouts: Dictionary = {}
