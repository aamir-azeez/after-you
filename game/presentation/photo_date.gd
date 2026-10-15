extends RefCounted
## The handwritten date on a polaroid's bottom strip, such as "15th Oct '26": the day with
## its ordinal, the short English month, and the year as an apostrophe plus two digits.
## The app is English only. The date is the player's local date for a UTC capture time.
const MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
## Every character a date can use. The bundled pen font is subset to exactly these.
const CHARACTERS := "0123456789 'stndrhJanFebMrApyuJlgSOcoNvDe"

## 1st 2nd 3rd 4th ... 11th 12th 13th ... 21st 22nd 23rd ... 31st.
static func ordinal(day: int) -> String:
	if day % 100 in [11, 12, 13]: return "%dth" % day
	match day % 10:
		1: return "%dst" % day
		2: return "%dnd" % day
		3: return "%drd" % day
	return "%dth" % day

## The date for a UTC capture time in a time zone bias_minutes east of UTC. Empty without a time.
static func format(taken_at: int, bias_minutes: int) -> String:
	if taken_at <= 0: return ""
	var local := Time.get_datetime_dict_from_unix_time(taken_at + bias_minutes * 60)
	return "%s %s '%02d" % [ordinal(int(local.day)), MONTHS[int(local.month) - 1], int(local.year) % 100]

## The date in the phone's own time zone.
static func local(taken_at: int) -> String:
	return format(taken_at, int(Time.get_time_zone_from_system().get("bias", 0)))
