extends RefCounted
## How Pollen amounts read on screen: grouped digits ("24,000") and the small
## "about $X" line beside a price (POLLEN-RULES.md "Money"). The about figure
## uses the Pinch rate, 5,000 Pollen for the Pinch's price, which is the
## cautious rate. The price is this phone's store's US one from the bundle table
## ($0.99 on Google Play, $1.49 on the App Store); pinch_price is the hook for the
## store's local price.
const Bundles = preload("res://services/pollen_bundles.gd")
const PINCH_POLLEN := 5000

## The Pinch's price and how to write it (`symbol` before the amount). A
## pinch_price of 0 reads this phone's store's US price from the table, each time.
static var pinch_price := 0.0
static var symbol := "$"

## The Pinch's price the about figure uses.
static func pinch() -> float:
	return pinch_price if pinch_price > 0.0 else Bundles.usd_cents("pinch") / 100.0

## 24000 -> "24,000"; negative amounts keep their sign.
static func grouped(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if amount < 0 else "") + digits + out

## The money an amount of Pollen is about worth at the Pinch rate: 20000 -> "$3.96".
static func about(amount: int) -> String:
	var value := float(maxi(amount, 0)) * pinch() / float(PINCH_POLLEN)
	return symbol + "%.2f" % snappedf(value, 0.01)

## US cents as the server keeps money spent (Google Play's US figure): 399 -> "$3.99".
static func usd(cents: int) -> String:
	var whole := maxi(cents, 0)
	return "$%d.%02d" % [floori(whole / 100.0), whole % 100]
