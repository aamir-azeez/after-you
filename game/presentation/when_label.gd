extends RefCounted
## One short, local date and time for lists: "Today, 9:42 PM", "Yesterday,
## 9:42 PM", "Mon, 9:42 PM" within the week, "Oct 3, 9:42 PM" this year and
## "Oct 3, 2025" before that. Pure, so callers and tests pass the clock and the
## time zone; text() reads both from the system.
const MONTHS := ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
const WEEKDAYS := ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]

## "" for an unknown time (0 or less).
static func text(unix_utc: int) -> String:
	return compact(unix_utc, int(Time.get_unix_time_from_system()), int(Time.get_time_zone_from_system().get("bias", 0)))

static func compact(unix_utc: int, now_utc: int, bias_minutes: int) -> String:
	if unix_utc <= 0: return ""
	var local := unix_utc + bias_minutes * 60
	var today := now_utc + bias_minutes * 60
	var when := Time.get_datetime_dict_from_unix_time(local)
	var days := floori(today / 86400.0) - floori(local / 86400.0)
	var hour := int(when.hour) % 12
	var clock := "%d:%02d %s" % [12 if hour == 0 else hour, int(when.minute), "AM" if int(when.hour) < 12 else "PM"]
	var date := "%s %d" % [MONTHS[int(when.month) - 1], int(when.day)]
	if days == 0: return "Today, " + clock
	if days == 1: return "Yesterday, " + clock
	if days > 1 and days < 7: return WEEKDAYS[int(when.weekday)] + ", " + clock
	if int(when.year) == int(Time.get_datetime_dict_from_unix_time(today).year): return date + ", " + clock
	return "%s, %d" % [date, int(when.year)]

## Seconds since the epoch for a server ISO time such as "2026-10-13T21:42:00.000Z", or 0.
static func parse_iso(value: Variant) -> int:
	if not value is String or value.length() < 19 or value.length() > 40: return 0
	var parsed := int(Time.get_unix_time_from_datetime_string(value.substr(0, 19)))
	return parsed if parsed > 0 else 0
