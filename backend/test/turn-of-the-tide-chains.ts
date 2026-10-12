// Native stage-1 and stage-2 contract chains for turn-of-the-tide@1 beyond
// the LOW history: HALF and HIGH (test_turn_of_the_tide_ways.gd) and two
// stage-1 variants (test_turn_of_the_tide_variants.gd). Each chain: the
// stage-1 a, b and checkpoint, then a, b and checkpoint for every way.
import halfSetA from "../../game/tests/fixtures/journey/set-the-tide-half-a.json";
import halfSetB from "../../game/tests/fixtures/journey/set-the-tide-half-b.json";
import halfSetCheckpoint from "../../game/tests/fixtures/journey/set-the-tide-half-checkpoint.json";
import halfBoomA from "../../game/tests/fixtures/journey/slack-water-half-boom-a.json";
import halfBoomB from "../../game/tests/fixtures/journey/slack-water-half-boom-b.json";
import halfBoomCheckpoint from "../../game/tests/fixtures/journey/slack-water-half-boom-checkpoint.json";
import halfSeaLockA from "../../game/tests/fixtures/journey/slack-water-half-sea-lock-a.json";
import halfSeaLockB from "../../game/tests/fixtures/journey/slack-water-half-sea-lock-b.json";
import halfSeaLockCheckpoint from "../../game/tests/fixtures/journey/slack-water-half-sea-lock-checkpoint.json";
import halfPuntA from "../../game/tests/fixtures/journey/slack-water-half-punt-a.json";
import halfPuntB from "../../game/tests/fixtures/journey/slack-water-half-punt-b.json";
import halfPuntCheckpoint from "../../game/tests/fixtures/journey/slack-water-half-punt-checkpoint.json";
import highSetA from "../../game/tests/fixtures/journey/set-the-tide-high-a.json";
import highSetB from "../../game/tests/fixtures/journey/set-the-tide-high-b.json";
import highSetCheckpoint from "../../game/tests/fixtures/journey/set-the-tide-high-checkpoint.json";
import highBoomA from "../../game/tests/fixtures/journey/slack-water-high-boom-a.json";
import highBoomB from "../../game/tests/fixtures/journey/slack-water-high-boom-b.json";
import highBoomCheckpoint from "../../game/tests/fixtures/journey/slack-water-high-boom-checkpoint.json";
import highSeaLockA from "../../game/tests/fixtures/journey/slack-water-high-sea-lock-a.json";
import highSeaLockB from "../../game/tests/fixtures/journey/slack-water-high-sea-lock-b.json";
import highSeaLockCheckpoint from "../../game/tests/fixtures/journey/slack-water-high-sea-lock-checkpoint.json";
import highPuntA from "../../game/tests/fixtures/journey/slack-water-high-punt-a.json";
import highPuntB from "../../game/tests/fixtures/journey/slack-water-high-punt-b.json";
import highPuntCheckpoint from "../../game/tests/fixtures/journey/slack-water-high-punt-checkpoint.json";
import lowHalfFirstStonesSetA from "../../game/tests/fixtures/journey/set-the-tide-low-half-first-stones-a.json";
import lowHalfFirstStonesSetB from "../../game/tests/fixtures/journey/set-the-tide-low-half-first-stones-b.json";
import lowHalfFirstStonesSetCheckpoint from "../../game/tests/fixtures/journey/set-the-tide-low-half-first-stones-checkpoint.json";
import lowHalfFirstStonesBoomA from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-boom-a.json";
import lowHalfFirstStonesBoomB from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-boom-b.json";
import lowHalfFirstStonesBoomCheckpoint from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-boom-checkpoint.json";
import lowHalfFirstStonesSeaLockA from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-sea-lock-a.json";
import lowHalfFirstStonesSeaLockB from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-sea-lock-b.json";
import lowHalfFirstStonesSeaLockCheckpoint from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-sea-lock-checkpoint.json";
import lowHalfFirstStonesPuntA from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-punt-a.json";
import lowHalfFirstStonesPuntB from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-punt-b.json";
import lowHalfFirstStonesPuntCheckpoint from "../../game/tests/fixtures/journey/slack-water-low-half-first-stones-punt-checkpoint.json";
import halfWinchSetA from "../../game/tests/fixtures/journey/set-the-tide-half-winch-a.json";
import halfWinchSetB from "../../game/tests/fixtures/journey/set-the-tide-half-winch-b.json";
import halfWinchSetCheckpoint from "../../game/tests/fixtures/journey/set-the-tide-half-winch-checkpoint.json";
import halfWinchBoomA from "../../game/tests/fixtures/journey/slack-water-half-winch-boom-a.json";
import halfWinchBoomB from "../../game/tests/fixtures/journey/slack-water-half-winch-boom-b.json";
import halfWinchBoomCheckpoint from "../../game/tests/fixtures/journey/slack-water-half-winch-boom-checkpoint.json";
import halfWinchSeaLockA from "../../game/tests/fixtures/journey/slack-water-half-winch-sea-lock-a.json";
import halfWinchSeaLockB from "../../game/tests/fixtures/journey/slack-water-half-winch-sea-lock-b.json";
import halfWinchSeaLockCheckpoint from "../../game/tests/fixtures/journey/slack-water-half-winch-sea-lock-checkpoint.json";
import halfWinchPuntA from "../../game/tests/fixtures/journey/slack-water-half-winch-punt-a.json";
import halfWinchPuntB from "../../game/tests/fixtures/journey/slack-water-half-winch-punt-b.json";
import halfWinchPuntCheckpoint from "../../game/tests/fixtures/journey/slack-water-half-winch-punt-checkpoint.json";

export type Chain = { set: unknown[]; ways: Record<string, unknown[]> };
export const TIDE_CHAINS: Record<string, Chain> = {
  "half": { set: [halfSetA, halfSetB, halfSetCheckpoint], ways: { "boom": [halfBoomA, halfBoomB, halfBoomCheckpoint], "sea-lock": [halfSeaLockA, halfSeaLockB, halfSeaLockCheckpoint], "punt": [halfPuntA, halfPuntB, halfPuntCheckpoint] } },
  "high": { set: [highSetA, highSetB, highSetCheckpoint], ways: { "boom": [highBoomA, highBoomB, highBoomCheckpoint], "sea-lock": [highSeaLockA, highSeaLockB, highSeaLockCheckpoint], "punt": [highPuntA, highPuntB, highPuntCheckpoint] } },
  "low-half-first-stones": { set: [lowHalfFirstStonesSetA, lowHalfFirstStonesSetB, lowHalfFirstStonesSetCheckpoint], ways: { "boom": [lowHalfFirstStonesBoomA, lowHalfFirstStonesBoomB, lowHalfFirstStonesBoomCheckpoint], "sea-lock": [lowHalfFirstStonesSeaLockA, lowHalfFirstStonesSeaLockB, lowHalfFirstStonesSeaLockCheckpoint], "punt": [lowHalfFirstStonesPuntA, lowHalfFirstStonesPuntB, lowHalfFirstStonesPuntCheckpoint] } },
  "half-winch": { set: [halfWinchSetA, halfWinchSetB, halfWinchSetCheckpoint], ways: { "boom": [halfWinchBoomA, halfWinchBoomB, halfWinchBoomCheckpoint], "sea-lock": [halfWinchSeaLockA, halfWinchSeaLockB, halfWinchSeaLockCheckpoint], "punt": [halfWinchPuntA, halfWinchPuntB, halfWinchPuntCheckpoint] } },
};
