#include <gdextension_interface.h>

#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#import "AYAppHooks.h"
#include "after_you_ios.h"

using namespace godot;

static AfterYouIOS *singleton = nullptr;

// Godot starts extensions inside Main::setup2, at the first rendered frame. A cold-start
// invite link and a notification tap arrive earlier, during launch and scene connection,
// so the app delegate hooks are installed from a static constructor. The Objective-C
// runtime runs every +load in this image (Godot's app delegate list included) before C++
// static constructors, and this object file is always linked: it holds the entry symbol.
__attribute__((constructor)) static void after_you_ios_early_hooks() {
	AYInstallAppHooks();
}

static void initialize_after_you_ios(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
		return;
	}
	GDREGISTER_CLASS(AfterYouIOS);
	singleton = memnew(AfterYouIOS);
	Engine::get_singleton()->register_singleton("AfterYouIOS", singleton);
}

static void uninitialize_after_you_ios(ModuleInitializationLevel p_level) {
	if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE || singleton == nullptr) {
		return;
	}
	Engine::get_singleton()->unregister_singleton("AfterYouIOS");
	memdelete(singleton);
	singleton = nullptr;
}

extern "C" {
GDExtensionBool GDE_EXPORT after_you_ios_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address, GDExtensionClassLibraryPtr p_library, GDExtensionInitialization *r_initialization) {
	GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
	init_obj.register_initializer(initialize_after_you_ios);
	init_obj.register_terminator(uninitialize_after_you_ios);
	init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_obj.init();
}
}
