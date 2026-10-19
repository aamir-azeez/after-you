extends RefCounted
## The shared colours of After You's controls, pages and Home, named once.
## Constants only, and it preloads nothing, so any script can use it.
## Scripts keep their own short names as aliases (const CREAM := UiTokens.CREAM).

## Text on cream, and cream itself: the primary button and most light text.
const INK := Color("193d39")
const CREAM := Color("eceddb")
## A cream button's hover fill.
const CREAM_HOVER := Color("ffffff")
## Focus rings, a pressed cream button and small mint headings.
const MINT := Color("a6d9c4")
## Secondary text: captions, chevrons and the version badge.
const MUTED := Color("9dbeb4")
## Unselected tab text and an empty list's body text.
const SOFT := Color("afc6be")
## Home's gesture hint and the keepsake box's status line.
const HINT := Color("a6c6b8")
## The teal secondary button and its edge.
const SECONDARY := Color("254b45")
const SECONDARY_BORDER := Color("54766a")
## The selected tab, and a pressed row or secondary button.
const SELECTED := Color("3a6b5f")
## A disabled button's fill and text.
const DISABLED_FILL := Color("3e5e55")
const DISABLED_TEXT := Color("9aaaa3")
## The keepsake box's paging buttons: fill, edge and pressed fill.
const PAGE_FILL := Color("2f5d52")
const PAGE_BORDER := Color("466e63")
const PAGE_PRESSED := Color("4a7c6f")
## The spirits' colours: solo (peach) and together (mint).
const SOLO := Color("f4c38d")
const TOGETHER := Color("91d6c6")
## Home's solid menu panel, its right edge, and the rules inside it.
const PANEL := Color("0e3033")
const PANEL_EDGE := Color("1d4a48")
const RULE := Color("2a5552")
## The keepsake box over the island.
const BOX := Color(0.055, 0.19, 0.20, 0.96)
## Full Journey's outlined pill keeps a little of the night behind it.
const NIGHT_GLASS := Color(0.07, 0.227, 0.239, 0.6)
## A flat row's hover tint on the dark panel.
const ROW_HOVER := Color(1, 1, 1, 0.06)

## Home's layout A: the menu panel's width, measured from the safe left edge.
const HOME_PANEL_WIDTH := 480.0
## Where Home's camera stage begins, from the safe left edge. It keeps the
## island's long-standing framing; gestures still start only right of the panel.
const HOME_STAGE_LEFT := 470.0
## Home's controls over the island sit this far below the safe top edge, and
## Explore this far right of the panel.
const HOME_TOP := 32.0
const HOME_STAGE_GAP := 40.0
