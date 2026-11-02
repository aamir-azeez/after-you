extends RefCounted
## How Pollen amounts read on screen (grouped digits, "24,000") and how money
## the server recorded for a real purchase reads ("$3.99").

## 24000 -> "24,000"; negative amounts keep their sign.
static func grouped(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out

## US cents as the server keeps money spent (Google Play's US figure): 399 -> "$3.99".
static func usd(cents: int) -> String:
	var whole := maxi(cents, 0)
	return "$%d.%02d" % [floori(whole / 100.0), whole % 100]
