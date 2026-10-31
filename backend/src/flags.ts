import { serverConfig } from "./config";

/**
 * The server flags: one accessor per flag, all read from CONFIG's `features` list (config.ts).
 *
 * A flag is on exactly when CONFIG lists its name; absent, unknown and malformed all read off. Every flag here is a
 * switch the owner may really use: a kill switch for cost, abuse or an outside service, or a part not launched yet.
 * Behaviour that must stay on is code, not a flag (RETIRED_FLAGS).
 */
export const FLAG_VARS = Object.freeze({
  /** Tester-code redemption. */
  testerAccess: "TESTER_ACCESS_ENABLED",
  /** Turn, redo and friend-room push notifications. */
  notifications: "NOTIFICATIONS_ENABLED",
  /** APNs alerts for iOS registrations. Off sends every token the data-only message. */
  iosPush: "IOS_PUSH_ENABLED",
  /** Friend room events (hosting alerts and their inbox). */
  friendRoomEvents: "FRIEND_ROOM_EVENTS_ENABLED",
  /** Campaign creation and its capability. */
  campaignCreation: "CAMPAIGN_CREATION_ENABLED",
  /** Campaign control and redo mutations. */
  campaignMutations: "CAMPAIGN_MUTATIONS_ENABLED",
  /** The operator-only Story data count and erase routes under /operator/story/. */
  storyDrain: "STORY_DRAIN_ENABLED",
  /** Relay photo uploads. */
  relayPhotos: "RELAY_PHOTOS_ENABLED",
  /** Account photo transfer uploads. */
  photoTransfer: "PHOTO_TRANSFER_ENABLED",
  /** The Play plus App Store hosting check in place of the Play-only one. */
  appStoreEntitlements: "APP_STORE_ENTITLEMENTS_ENABLED",
  /** The live socket (GET /v1/live), its capability and the hints room and friend changes send to it. */
  liveConnection: "LIVE_CONNECTION_ENABLED",
  /** Play Games sign-in as a way back to a friend identity (link, unlink, restore) and its capability. */
  playGames: "PLAY_GAMES_ENABLED",
  /** Game Center identity verification for the same link, unlink and restore routes. */
  gameCenter: "GAME_CENTER_ENABLED",
  /** The iOS launch waitlist for the friend link page: /v1/waitlist/ios and its confirm route (waitlist.ts). */
  iosWaitlist: "IOS_WAITLIST_ENABLED",
  /** Display names: PUT /v1/profile/name, names on friends pages and room reads, writes into rooms and the capability (display-names.ts). */
  displayNames: "DISPLAY_NAMES_ENABLED",
  /** Pollen earned from accepted turns and first clears, the wallet routes and the turn reply field (pollen/). */
  pollenEarn: "POLLEN_EARN",
  /** The wardrobe (pollen/wardrobe.ts, pollen/earned.ts): owned and earned items and the look on the wallet read, wearing and taking off, and the replay job delivering board rewards. Every Hard is recorded while earning is on. Needs POLLEN_EARN. */
  pollenWardrobe: "POLLEN_WARDROBE",
  /** The shop (pollen/spend.ts): buying, prices and the catalogue on the wallet read, and the name change price. Needs POLLEN_WARDROBE. */
  pollenShop: "POLLEN_SHOP",
  /** Looks in rooms (pollen/room-looks.ts): each member's look and each turn's look, served to phones that send X-AfterYou-Looks, and each pair's looks on public leaderboard rows (leaderboards/run-looks.ts). */
  pollenLooks: "POLLEN_LOOKS",
  /** Item blooms (pollen/item-blooms.ts): the second roll on a free-chapter bank turn may drop a shop item. Needs POLLEN_SHOP. */
  pollenItemBlooms: "POLLEN_ITEM_BLOOMS",
  /** The Full Journey monthly grant (pollen/grant.ts): instalments on the wallet read and the PollenClaims check. Needs POLLEN_EARN. */
  pollenGrant: "POLLEN_GRANT",
  /** Pollen bundle refunds (pollen/bundle-settle.ts): the wallet read's daily check that takes back a refunded bundle, kept on after bundles stop selling. Needs POLLEN_SHOP. Set only through FEATURES. */
  pollenRefunds: "POLLEN_REFUNDS",
  /** Pollen bundles on Google Play (pollen/bundle-settle.ts): the bundle claim route, the wallet read's `bundles` part and the capability. Needs POLLEN_REFUNDS, so bundles never sell without refunds being taken back. Set only through FEATURES. */
  pollenBundles: "POLLEN_BUNDLES",
  /** Pollen bundles on the App Store (pollen/bundle-settle.ts): the same claim route, wallet read part and its own capability for iPhone, once the App Store's four products are in bundles.json. Needs POLLEN_REFUNDS, not POLLEN_BUNDLES, so each store switches on and off by itself. Set only through FEATURES. */
  pollenBundlesAppStore: "POLLEN_BUNDLES_APP_STORE",
  /** Leaderboards (leaderboards/): board reads, posting finished together runs, the name choice, reports and the replay check routes. */
  leaderboards: "LEADERBOARDS",
} as const);

/**
 * Flags whose behaviour is now always on, retired 2026-10-29 while every one was on live. Their names are never
 * reused, and CONFIG must not list them (the deploy runners refuse it; the Worker ignores unknown names).
 */
export const RETIRED_FLAGS = Object.freeze(["PRESENCE_ENABLED", "SAFETY_ENFORCEMENT_ENABLED", "REVENUECAT_DELETION_ENABLED", "V2_ROOMS_ENABLED",
  "FIRST_STEPS_ENABLED", "COOP_CHAPTERS_ENABLED", "HOUSE_CHAPTER_ENABLED", "JOURNEY_CHAPTERS_ENABLED", "WISHING_WELL_CHAPTER_ENABLED",
  "LONG_WAY_HOME_V2_CHAPTER_ENABLED", "TURN_OF_THE_TIDE_CHAPTER_ENABLED", "LIGHTHOUSE_V2_CHAPTER_ENABLED", "TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED",
  "PRESET_REACTIONS_ENABLED", "PHOTO_DELIVERY_ENABLED", "REPLAY_TRANSFER_ENABLED", "HISTORY_OFFLOAD_ENABLED", "UPDATE_GATE_ENABLED",
  "LEGACY_TRANSFERRED_ROOM_UNBLOCK", "FINISHED_ROOM_LEAVE_ENABLED", "ROOM_INDEX_ENABLED", "TURN_TRIES_ENABLED", "END_REACTIONS_ENABLED",
  "IN_RUN_REACTIONS_ENABLED", "HARD_MODE_ENABLED"] as const);

export type FlagName = keyof typeof FLAG_VARS;
export type FlagVar = typeof FLAG_VARS[FlagName];
export const FLAG_NAMES: ReadonlySet<string> = new Set(Object.values(FLAG_VARS));

/**
 * Every var and secret the worker reads, all optional, so Env, a test's partial object and a narrow config are all
 * assignable to it without a cast. Public fixed values are APP in config.ts; everything else that is not secret is CONFIG.
 */
export type ServerVars = {
  /** The JSON object config.ts parses: flags, minimum app versions, friend aliases, RevenueCat ids. */
  CONFIG?: string;
  /** Secret. The Pollen root key: HKDF in pollen/keys.ts derives the bloom keys from it; at least 32 characters. */
  POLLEN_SECRET?: string;
  /** Secret. RevenueCat's v2 secret API key. */
  REVENUECAT_SECRET_KEY?: string;
  /** Secret. Firebase service account JSON, parsed in notifications.ts. */
  FCM_SERVICE_ACCOUNT_JSON?: string;
  /** Secret. SHA-256 of the tester code (tester-access.ts). */
  TESTER_CODE_SHA256?: string;
  /** Secret. The Play Games web client's OAuth client secret. */
  PLAY_GAMES_CLIENT_SECRET?: string;
  /** Secret. The operator credential for every /operator/ route. */
  SAFETY_OPERATOR_TOKEN?: string;
  /** Secret. A Resend API key; Resend's only key that can add contacts is full access. */
  RESEND_API_KEY?: string;
  /** Secret. The Turnstile widget's secret key for siteverify. */
  TURNSTILE_SECRET_KEY?: string;
  /** Secret. Signs the waitlist confirm links (waitlist-token.ts); at least 32 characters. */
  WAITLIST_CONFIRM_SECRET?: string;
};

/** The one flag rule: CONFIG lists the flag. */
export function flagOn(env: ServerVars, name: FlagVar): boolean { return serverConfig(env).features.has(name); }

/** One accessor per flag: `flags.notifications(env)`. */
export const flags: { readonly [K in FlagName]: (env: ServerVars) => boolean } = Object.freeze(Object.fromEntries(
  (Object.entries(FLAG_VARS) as [FlagName, FlagVar][]).map(([name, variable]) => [name, (env: ServerVars) => flagOn(env, variable)])
) as { [K in FlagName]: (env: ServerVars) => boolean });
