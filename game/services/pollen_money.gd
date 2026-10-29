extends RefCounted
## How Pollen amounts read on screen: grouped digits ("24,000") and the small
## "about $X" line beside a price (POLLEN-RULES.md "Money"). The about figure
## uses the Pinch rate, 5,000 Pollen for the Pinch's price, which is the
## cautious rate. Until the Pinch is on sale (Phase 6) its price is the US one;
## pinch_price is the hook for the store's local price then.
const PINCH_POLLEN := 5000
const PINCH_PRICE_USD := 0.99

## The Pinch's price and how to write it: the store's local price once bundles
## sell (`symbol` before the amount), else US dollars.
static var pinch_price := PINCH_PRICE_USD
static var symbol := "$"

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
	var value := float(maxi(amount, 0)) * pinch_price / float(PINCH_POLLEN)
	return symbol + "%.2f" % snappedf(value, 0.01)

## US cents as the server keeps money spent (Google Play's US figure): 399 -> "$3.99".
static func usd(cents: int) -> String:
	var whole := maxi(cents, 0)
	return "$%d.%02d" % [floori(whole / 100.0), whole % 100]
