extends RefCounted
## One answer to "does phone behaviour apply here" for every screen and service.
## Android and iOS are both phones: display safe areas, touch wording, haptics and
## store-gated paid chapters. Only Android has the native plugin so far; services that
## need it still check for the singleton and stay unavailable without it.

static func is_phone() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios")

## Paid chapters wait for a tester grant or a store purchase on a phone, even when no
## store is configured. Only desktop development builds open them directly.
static func store_gated() -> bool:
	return is_phone()
