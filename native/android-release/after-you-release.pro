# Godot calls Java classes, constructors and methods through JNI and reflection.
# Its export-template AAR does not include consumer rules. Preserve that boundary
# while permitting optimization inside the retained methods.
-keep,allowoptimization class org.godotengine.godot.** { *; }
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault
