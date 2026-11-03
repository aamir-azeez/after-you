extends RefCounted
## The one place that finds the native plugin. Android's AfterYouAndroid and iOS's
## AfterYouIOS share method names, arguments and signals for the services both have, so
## each wrapper asks here for its service and stays the same on both platforms.
## Android JNI methods dispatch through callv and iOS methods are bound, so callv works on both.

const ANDROID := "AfterYouAndroid"
const IOS := "AfterYouIOS"
## What the iOS plugin provides. Photo capture is Android only for now.
const IOS_SERVICES := ["secure_store", "share", "invite_link", "purchases", "notifications", "games"]

## The singleton serving this service, or null when the build has none.
static func singleton(service: String) -> Object:
	if Engine.has_singleton(ANDROID): return Engine.get_singleton(ANDROID)
	if service in IOS_SERVICES and Engine.has_singleton(IOS): return Engine.get_singleton(IOS)
	return null

## Whether `native` answers `method`, for a method one platform has before the other.
## Android's JNI methods cannot be listed (has_method does not see them), and its plugin
## and these wrappers ship together, so Android always does; iOS binds its methods, so
## has_method tells.
static func has_method_on(native: Object, method: String) -> bool:
	if native == null: return false
	return Engine.has_singleton(ANDROID) or native.has_method(method)
