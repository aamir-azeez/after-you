extends RefCounted
## Stage numbers in room ids. A chapter has 1 to MAX_STAGES stages, fixed by its
## bundled, hashed definition; turn, pair and photo ids carry the stage as one
## digit (t<branch>-<stage>-<a|b>, p<branch>-<stage>). Grammars with no chapter
## in reach accept any digit below MAX_STAGES. Wherever the room's chapter is
## known, count() bounds it: a stage index past the chapter's last stage is
## refused there, exactly as a published two-stage chapter refused "2" before.

const MAX_STAGES := 8
## The stage digit for id grammars.
const DIGIT := "[0-7]"
## A turn id with any branch 0-31.
const TURN_ID := "^t(?:[0-9]|[12][0-9]|3[01])-" + DIGIT + "-[ab]$"

## The chapter's own stage count; 0 for an unknown (empty) definition.
static func count(level: Dictionary) -> int:
	var stages: Variant = level.get("stages")
	return stages.size() if stages is Array else 0

## True for an integral stage index of this chapter (0 .. count - 1).
static func within(value: Variant, level: Dictionary) -> bool:
	return (value is int or (value is float and is_finite(value) and value == floor(value))) and value >= 0 and value < count(level)

## The stage digit of a turn or pair id, or -1.
static func of_id(id: String) -> int:
	var digit := id.get_slice("-", 1)
	return int(digit) if digit.length() == 1 and digit.is_valid_int() else -1
