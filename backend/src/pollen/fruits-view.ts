import { purse } from "./currency";
import { FRUIT_RULES, type FruitRules } from "./fruits";
import { BUNDLES } from "./bundles";
import { hasBundles } from "./bundle-settle";
import { achievementsView, settleAchievements, type AchievementView } from "./achievements";
import { fruitGrantView, type FruitGrantView } from "./grant-settle";
import { fruitHistory, type FruitEntry } from "./fruit-ops";
import { levelsView, type LevelsView } from "./level-unlocks";

/**
 * What GET /v1/pollen adds while Fruits are on (`fruits`), and the history's Fruit lines (`fruit_entries`). Every number
 * the phone shows comes from here, never from a copy in the app. Reads only, except the one-time achievement sweep on a
 * player's first Fruits read (achievements.ts), which pays what their records already earned.
 */
export type FruitsView = {
  schema_version: 1; balance: number; earned: number;
  sunshine: { left: number; turns: number; price: number };
  convert: { pollen_per_fruit: number; step: number };
  first_pack_gift: boolean; first_pack_percent: number;
  achievements: AchievementView[];
  /** The Full Journey Fruit ladder for everyone (the Full Journey card shows it before a player subscribes). */
  ladder: { first: number; step: number; every: number; top: number; welcome: number };
  grant?: FruitGrantView;
  /** While LEVEL_UNLOCKS is on for the app: the levels sold for Fruits and the ones this player opened (level-unlocks.ts). */
  levels?: LevelsView;
};

/** The wallet read's Fruits part. The caller runs it inside a transaction (the sweep may write). `levels`: LEVEL_UNLOCKS is on for the app. */
export function fruitsView(storage: DurableObjectStorage, now: number, rules: FruitRules = FRUIT_RULES, levels = false): FruitsView {
  settleAchievements(storage, now, {}, rules);
  const fruits = purse(storage, "fruits"), percent = BUNDLES.first_bonus_percent.fruits, grant = fruitGrantView(storage, rules);
  return {
    schema_version: 1, balance: fruits.balance, earned: fruits.earned,
    sunshine: { left: Math.max(0, purse(storage, "sunshine").balance), turns: rules.sunshine.turns, price: rules.sunshine.price },
    convert: { pollen_per_fruit: rules.convert.pollen_per_fruit, step: rules.convert.step },
    first_pack_gift: percent > 0 && !hasBundles(storage, "fruits"), first_pack_percent: percent,
    achievements: achievementsView(storage, rules),
    ladder: { ...rules.grant },
    ...(grant ? { grant } : {}),
    ...(levels ? { levels: levelsView(storage) } : {})
  };
}

/** The history read's Fruit lines. */
export function fruitHistoryView(storage: DurableObjectStorage): { fruit_entries: FruitEntry[] } {
  return { fruit_entries: fruitHistory(storage) };
}
