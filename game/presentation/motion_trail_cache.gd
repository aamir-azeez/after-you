extends RefCounted
## Shared materials and meshes for the object_motion_trail subclasses, built once.
## They live in a script that extends an engine class: a static var in a subclass
## of a project script can crash the exit (tests/test_subclass_statics.gd).
static var spin_material: ShaderMaterial
static var band_material: ShaderMaterial
static var tube_mesh: ArrayMesh
