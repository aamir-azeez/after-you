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
