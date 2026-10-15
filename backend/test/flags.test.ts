import { env } from "cloudflare:workers";
import { describe, expect, it, vi } from "vitest";

const production = vi.hoisted(() => ({ on: false }));
vi.mock("../src/v2/campaign-production", () => ({
  campaignProductionEnabled: () => production.on,
  requireCampaignProduction: () => { if (!production.on) throw new Error("campaign_unavailable"); }
}));

import { commaList, flags, flagOn, type FlagName, type ServerVars } from "../src/flags";
import { productList, reviewer } from "../src/play-entitlement";
import { MAX_JOIN_VERSIONS, routeV2 } from "../src/v2/routes";
import { advertisedChapters } from "../src/v2/chapters";
import { advertisedCampaigns } from "../src/v2/campaign-registry";
import { campaignProductionEnabled } from "../src/v2/campaign-production";
import { MAX_ROOM_STAGES } from "../src/v2/chapter-types";
import { HISTORY_HEADER } from "../src/v2/history";

type Loose = Record<string, unknown>;
// Frozen copies of every flag read before flags.ts, one per accessor, with the file it came from.
const OLD: Record<FlagName, (env: Loose) => boolean> = {
  presence: e => String(e.PRESENCE_ENABLED) === "true", // presence.ts presenceEnabled
  testerAccess: e => String(e.TESTER_ACCESS_ENABLED) === "true", // tester-access.ts
  safetyEnforcement: e => String(e.SAFETY_ENFORCEMENT_ENABLED) === "true", // safety-routes.ts safetyEnabled, v2/room.ts
  revenuecatDeletion: e => String(e.REVENUECAT_DELETION_ENABLED) === "true", // account-erasure.ts
  notifications: e => String(e.NOTIFICATIONS_ENABLED) === "true", // notifications.ts, notification-storage.ts
  iosPush: e => String(e.IOS_PUSH_ENABLED) === "true", // notifications.ts iosPushEnabled
  friendRoomEvents: e => String(e.FRIEND_ROOM_EVENTS_ENABLED) === "true", // friend-room-events.ts FRIEND_ROOM_EVENTS_ENABLED
  v2Rooms: e => String(e.V2_ROOMS_ENABLED) === "true", // v2/routes.ts, campaign-bindings.ts, campaign-redo.ts
  firstStepsChapter: e => String(e.FIRST_STEPS_ENABLED) === "true", // v2/chapters.ts creatable
  coopChapters: e => String(e.COOP_CHAPTERS_ENABLED) === "true",
  houseChapter: e => String(e.HOUSE_CHAPTER_ENABLED) === "true",
  journeyChapters: e => String(e.JOURNEY_CHAPTERS_ENABLED) === "true",
  wishingWellChapter: e => String(e.WISHING_WELL_CHAPTER_ENABLED) === "true",
  longWayHomeV2Chapter: e => String(e.LONG_WAY_HOME_V2_CHAPTER_ENABLED) === "true",
  turnOfTheTideChapter: e => String(e.TURN_OF_THE_TIDE_CHAPTER_ENABLED) === "true",
  lighthouseV2Chapter: e => String(e.LIGHTHOUSE_V2_CHAPTER_ENABLED) === "true",
  campaignCreation: e => String(e.CAMPAIGN_CREATION_ENABLED) === "true", // campaign-registry.ts, v2/routes.ts
  campaignMutations: e => String(e.CAMPAIGN_MUTATIONS_ENABLED) === "true", // campaign-bindings.ts, campaign-redo.ts, v2/routes.ts
  relayPhotos: e => String(e.RELAY_PHOTOS_ENABLED) === "true", // v2/routes.ts
  presetReactions: e => String(e.PRESET_REACTIONS_ENABLED) === "true", // v2/routes.ts
  photoDelivery: e => String(e.PHOTO_DELIVERY_ENABLED) === "true", // v2/routes.ts
  photoTransfer: e => String(e.PHOTO_TRANSFER_ENABLED) === "true", // photo-transfer-routes.ts
  replayTransfer: e => String(e.REPLAY_TRANSFER_ENABLED) === "true", // v2/routes.ts (three casts)
  historyOffload: e => String(e.HISTORY_OFFLOAD_ENABLED) === "true", // v2/history.ts historyEnabled
  updateGate: e => String(e.UPDATE_GATE_ENABLED) === "true", // app-status.ts updateGateEnabled
  legacyTransferredRoomUnblock: e => String(e.LEGACY_TRANSFERRED_ROOM_UNBLOCK) === "true", // v2/routes.ts legacyTransferredUnblock
  appStoreEntitlements: e => String(e.APP_STORE_ENTITLEMENTS_ENABLED) === "true", // entitlement.ts
};
const OLD_VARS: Record<FlagName, string> = {
  presence: "PRESENCE_ENABLED", testerAccess: "TESTER_ACCESS_ENABLED", safetyEnforcement: "SAFETY_ENFORCEMENT_ENABLED",
  revenuecatDeletion: "REVENUECAT_DELETION_ENABLED", notifications: "NOTIFICATIONS_ENABLED", iosPush: "IOS_PUSH_ENABLED",
  friendRoomEvents: "FRIEND_ROOM_EVENTS_ENABLED", v2Rooms: "V2_ROOMS_ENABLED", firstStepsChapter: "FIRST_STEPS_ENABLED",
  coopChapters: "COOP_CHAPTERS_ENABLED", houseChapter: "HOUSE_CHAPTER_ENABLED", journeyChapters: "JOURNEY_CHAPTERS_ENABLED",
  wishingWellChapter: "WISHING_WELL_CHAPTER_ENABLED", longWayHomeV2Chapter: "LONG_WAY_HOME_V2_CHAPTER_ENABLED",
  turnOfTheTideChapter: "TURN_OF_THE_TIDE_CHAPTER_ENABLED", lighthouseV2Chapter: "LIGHTHOUSE_V2_CHAPTER_ENABLED",
  campaignCreation: "CAMPAIGN_CREATION_ENABLED", campaignMutations: "CAMPAIGN_MUTATIONS_ENABLED", relayPhotos: "RELAY_PHOTOS_ENABLED",
  presetReactions: "PRESET_REACTIONS_ENABLED", photoDelivery: "PHOTO_DELIVERY_ENABLED", photoTransfer: "PHOTO_TRANSFER_ENABLED",
  replayTransfer: "REPLAY_TRANSFER_ENABLED", historyOffload: "HISTORY_OFFLOAD_ENABLED", updateGate: "UPDATE_GATE_ENABLED",
  legacyTransferredRoomUnblock: "LEGACY_TRANSFERRED_ROOM_UNBLOCK", appStoreEntitlements: "APP_STORE_ENTITLEMENTS_ENABLED",
};
const NAMES = Object.keys(OLD) as FlagName[];
/** Every shape a var takes today: wrangler strings, near misses, test booleans, null, an undefined value and (separately) a missing key. */
const VALUES: readonly unknown[] = ["true", "false", "TRUE", "True", " true", "true ", "1", "yes", "on", "", true, false, 1, 0, null, undefined, ["true"]];
const loose = (value: Loose) => value as ServerVars;

describe("flags", () => {
  it("has exactly one accessor per old flag read", () => {
    expect(Object.keys(flags).sort()).toEqual([...NAMES].sort());
  });
  it("reads each var exactly like the old expression, for every value, with every other var unset", () => {
    for (const set of NAMES) {
      for (const value of VALUES) {
        const vars: Loose = { [OLD_VARS[set]]: value };
        for (const name of NAMES) {
          expect(flags[name](loose(vars)), `${name} with ${OLD_VARS[set]}=${JSON.stringify(value)}`).toBe(OLD[name](vars));
          expect(flagOn(loose(vars), OLD_VARS[name] as never), `flagOn ${name}`).toBe(OLD[name](vars));
        }
      }
    }
    for (const name of NAMES) expect(flags[name](loose({})), `${name} missing`).toBe(false);
  });
  it("matches the old reads on the configured worker env and on every flag on", () => {
    const all: Loose = { ...env };
    for (const name of NAMES) all[OLD_VARS[name]] = "true";
    for (const name of NAMES) {
      expect(flags[name](env)).toBe(OLD[name](env as unknown as Loose));
      expect(flags[name](loose(all))).toBe(true);
    }
  });
});

// A frozen copy of the /v2/capabilities body before flags.ts.
function oldCapabilities(request: Request, env: Env): unknown {
  const roomLevel = request.headers.get("X-AfterYou-Room-Level") === "2" ? 2 : 1;
  return { api_version: 2,
    mutations_enabled: String(env.V2_ROOMS_ENABLED) === "true", recording_version: 2, simulation_version: 2,
    photo_uploads_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.RELAY_PHOTOS_ENABLED) === "true",
    preset_reactions_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.PRESET_REACTIONS_ENABLED) === "true",
    photo_delivery_enabled: String(env.PHOTO_DELIVERY_ENABLED) === "true",
    replay_transfer_version: String((env as Env & { REPLAY_TRANSFER_ENABLED?: string }).REPLAY_TRANSFER_ENABLED) === "true" ? 1 : 0,
    ...(campaignProductionEnabled() ? { campaign_control_version: 2, campaign_redo_version: 1 } : {}),
    campaign_creation_enabled: String(env.V2_ROOMS_ENABLED) === "true" && String(env.CAMPAIGN_CREATION_ENABLED) === "true" && advertisedCampaigns(env).length > 0,
    campaign_mutations_enabled: campaignProductionEnabled() && String(env.V2_ROOMS_ENABLED) === "true" && String(env.CAMPAIGN_MUTATIONS_ENABLED) === "true",
    campaign_definitions: advertisedCampaigns(env),
    chapters: advertisedChapters(env, roomLevel),
    ...(roomLevel >= 2 ? { room_level: 2, max_join_versions: MAX_JOIN_VERSIONS, max_stages: MAX_ROOM_STAGES } : {}),
    ...(request.headers.get(HISTORY_HEADER) === "1" ? { history_version: 1, history_offload_enabled: String((env as Env & { HISTORY_OFFLOAD_ENABLED?: string }).HISTORY_OFFLOAD_ENABLED) === "true" } : {}),
    validation: "structural_client_replay_required" };
}
const CAPABILITY_VARS = ["V2_ROOMS_ENABLED", "RELAY_PHOTOS_ENABLED", "PRESET_REACTIONS_ENABLED", "PHOTO_DELIVERY_ENABLED",
  "REPLAY_TRANSFER_ENABLED", "CAMPAIGN_CREATION_ENABLED", "CAMPAIGN_MUTATIONS_ENABLED", "HISTORY_OFFLOAD_ENABLED"];
const CHAPTER_VARS = ["FIRST_STEPS_ENABLED", "COOP_CHAPTERS_ENABLED", "HOUSE_CHAPTER_ENABLED", "JOURNEY_CHAPTERS_ENABLED"];

describe("/v2/capabilities", () => {
  it("answers byte for byte as before for every combination of the flags it reads", async () => {
    const player = "c".repeat(22), seen = new Set<string>();
    for (const productionOn of [false, true]) {
      production.on = productionOn;
      for (const [on, off] of [["true", "false"], [true, undefined], ["TRUE", ""]] as const) {
        for (let mask = 0; mask < 1 << CAPABILITY_VARS.length; mask++) {
          const vars: Loose = { ...env };
          CAPABILITY_VARS.forEach((name, bit) => { vars[name] = mask & (1 << bit) ? on : off; });
          // Campaign creation also needs every campaign chapter creatable; follow the lowest bit.
          for (const name of CHAPTER_VARS) vars[name] = mask & 1 ? "true" : "false";
          for (const headers of [{}, { "X-AfterYou-Room-Level": "2" }, { [HISTORY_HEADER]: "1" }, { "X-AfterYou-Room-Level": "2", [HISTORY_HEADER]: "1" }] as Record<string, string>[]) {
            const request = new Request("https://after-you.test/v2/capabilities", { headers });
            const response = await routeV2(request, "/v2/capabilities", player, vars as unknown as Env);
            const label = `production ${productionOn} on ${JSON.stringify(on)} mask ${mask} ${JSON.stringify(headers)}`;
            expect(response.status, label).toBe(200);
            const body = await response.text();
            expect(body, label).toBe(JSON.stringify(oldCapabilities(request, vars as unknown as Env)));
            const parsed = JSON.parse(body) as Record<string, unknown>;
            for (const key of ["mutations_enabled", "photo_uploads_enabled", "preset_reactions_enabled", "photo_delivery_enabled", "campaign_creation_enabled", "campaign_mutations_enabled", "history_offload_enabled"])
              if (parsed[key] === true) seen.add(key);
            if (parsed.replay_transfer_version === 1) seen.add("replay_transfer_version");
          }
        }
      }
    }
    production.on = false;
    // The matrix reaches every capability's on state, so each comparison above is not vacuous.
    expect([...seen].sort()).toEqual(["campaign_creation_enabled", "campaign_mutations_enabled", "history_offload_enabled", "mutations_enabled",
      "photo_delivery_enabled", "photo_uploads_enabled", "preset_reactions_enabled", "replay_transfer_version"]);
  });
});

// Frozen copies of the comma-list reads in play-entitlement.ts and store-entitlement.ts before commaList.
function oldPlayProducts(raw: string | undefined): string[] | null {
  const subscriptionProducts = (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
  if ((raw ?? "").trim() && (subscriptionProducts.length > 8 || !subscriptionProducts.every(value => /^prod[A-Za-z0-9_-]+$/.test(value)))) return null;
  return subscriptionProducts;
}
function oldStoreProducts(raw: string | undefined): string[] | null {
  const values = (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
  if ((raw ?? "").trim() && (values.length > 8 || !values.every(value => /^prod[A-Za-z0-9_-]+$/.test(value)))) return null;
  return values;
}
function oldReviewer(raw: string | undefined, playerId: string): boolean {
  const reviewers = (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
  return reviewers.length <= 16 && reviewers.every(value => /^[A-Za-z0-9_-]{22}$/.test(value)) && reviewers.includes(playerId);
}
const ID = "r".repeat(22);
const LISTS: readonly (string | undefined)[] = [undefined, "", " ", ",", " , ", "prodA", " prodA ", "prodA,prodB", "prodA, prodB", "prodA,,prodB", "prodA,", ",prodA",
  "prodA,bad", "bad", "PRODA", "prod", "prod-x_9", Array.from({ length: 8 }, (_, i) => "prod" + i).join(","), Array.from({ length: 9 }, (_, i) => "prod" + i).join(","),
  ID, ` ${ID} `, `${ID},${"s".repeat(22)}`, `${ID},short`, Array.from({ length: 16 }, (_, i) => i === 0 ? ID : String(i).padStart(22, "x")).join(","),
  Array.from({ length: 17 }, (_, i) => i === 0 ? ID : String(i).padStart(22, "x")).join(","), "r".repeat(23), "\tprodA\n"];

describe("comma-list vars", () => {
  it("split, validate and match exactly as the old Play and store copies", () => {
    for (const raw of LISTS) {
      expect(commaList(raw), JSON.stringify(raw)).toEqual((raw ?? "").split(",").map(value => value.trim()).filter(Boolean));
      expect(productList(raw), JSON.stringify(raw)).toEqual(oldPlayProducts(raw));
      expect(productList(raw), JSON.stringify(raw)).toEqual(oldStoreProducts(raw));
      for (const player of [ID, "s".repeat(22), "x"]) expect(reviewer({ REVENUECAT_REVIEWER_IDS: raw }, player), `${JSON.stringify(raw)} ${player}`).toBe(oldReviewer(raw, player));
    }
  });
});
