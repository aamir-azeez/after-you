/**
 * Every deploy var the worker reads, and one accessor per feature flag.
 *
 * A flag is on when String(var) is exactly "true", or when its var name is an
 * item of the comma-separated FEATURES var (see featureNames). Absent, "false",
 * "TRUE", "1", "" and any other value of the dedicated var are off. (A boolean
 * true, as tests pass it, also reads on, because String(true) is "true".)
 *
 * FEATURES folds flags into one var to free var slots: a flag listed there is on
 * whatever its dedicated var says, so turning a folded flag off means taking it
 * out of FEATURES. A row whose doc ends "Set only through FEATURES." has no var of
 * its own in production: FEATURES is its one switch. That marker is the list the
 * deploy tools and tests read; every new flag carries it.
 */
export const FLAG_VARS = Object.freeze({
  /** Friend presence (online dots and the presence endpoints). Set only through FEATURES. */
  presence: "PRESENCE_ENABLED",
  /** Tester-code redemption. Set only through FEATURES. */
  testerAccess: "TESTER_ACCESS_ENABLED",
  /** Safety terms acceptance before interaction and photo routes. Set only through FEATURES. */
  safetyEnforcement: "SAFETY_ENFORCEMENT_ENABLED",
  /** RevenueCat customer deletion during account erasure. Set only through FEATURES. */
  revenuecatDeletion: "REVENUECAT_DELETION_ENABLED",
  /** Turn, redo and friend-room push notifications. Set only through FEATURES. */
  notifications: "NOTIFICATIONS_ENABLED",
  /** APNs alerts for iOS registrations. Off sends every token the data-only message. */
  iosPush: "IOS_PUSH_ENABLED",
  /** Friend room events (hosting alerts and their inbox). Set only through FEATURES. */
  friendRoomEvents: "FRIEND_ROOM_EVENTS_ENABLED",
  /** Relay (v2) room mutations. Set only through FEATURES. */
  v2Rooms: "V2_ROOMS_ENABLED",
  /** Creating First Steps rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  firstStepsChapter: "FIRST_STEPS_ENABLED",
  /** Creating High and Low and Rolling Home rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  coopChapters: "COOP_CHAPTERS_ENABLED",
  /** Creating A House for Two rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  houseChapter: "HOUSE_CHAPTER_ENABLED",
  /** Creating Conservatory and Long Way Home rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  journeyChapters: "JOURNEY_CHAPTERS_ENABLED",
  /** Creating The Wishing Well rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  wishingWellChapter: "WISHING_WELL_CHAPTER_ENABLED",
  /** Creating Long Way Home @2 rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  longWayHomeV2Chapter: "LONG_WAY_HOME_V2_CHAPTER_ENABLED",
  /** Creating Turn of the Tide rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  turnOfTheTideChapter: "TURN_OF_THE_TIDE_CHAPTER_ENABLED",
  /** Creating Sleeping Lighthouse @2 rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  lighthouseV2Chapter: "LIGHTHOUSE_V2_CHAPTER_ENABLED",
  /** Creating Turn of the Tide @2 rooms, read through the CHAPTERS table in v2/chapters.ts. Set only through FEATURES. */
  turnOfTheTideV2Chapter: "TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED",
  /** Campaign creation and its capability. */
  campaignCreation: "CAMPAIGN_CREATION_ENABLED",
  /** Campaign control and redo mutations. */
  campaignMutations: "CAMPAIGN_MUTATIONS_ENABLED",
  /** The operator-only Story data count and erase routes under /operator/story/. */
  storyDrain: "STORY_DRAIN_ENABLED",
  /** Relay photo uploads (also needs v2Rooms). Set only through FEATURES. */
  relayPhotos: "RELAY_PHOTOS_ENABLED",
  /** Preset pair reactions (also needs v2Rooms). Set only through FEATURES. */
  presetReactions: "PRESET_REACTIONS_ENABLED",
  /** Relay photo delivery acknowledgements. Set only through FEATURES. */
  photoDelivery: "PHOTO_DELIVERY_ENABLED",
  /** Account photo transfer uploads. Set only through FEATURES. */
  photoTransfer: "PHOTO_TRANSFER_ENABLED",
  /** Replay transfer acknowledgements and its capability version. Set only through FEATURES. */
  replayTransfer: "REPLAY_TRANSFER_ENABLED",
  /** Room history offload. Set only through FEATURES. */
  historyOffload: "HISTORY_OFFLOAD_ENABLED",
  /** The required-update gate, GET /v1/app-status. Set only through FEATURES. */
  updateGate: "UPDATE_GATE_ENABLED",
  /** The Story boundary answer for 0.6.0 and older clients on a transferred room. Set only through FEATURES. */
  legacyTransferredRoomUnblock: "LEGACY_TRANSFERRED_ROOM_UNBLOCK",
  /** The Play plus App Store hosting check in place of the Play-only one. */
  appStoreEntitlements: "APP_STORE_ENTITLEMENTS_ENABLED",
  /** Leaving a finished room (POST .../leave with leave_finished) and its capability. Set only through FEATURES. */
  finishedRoomLeave: "FINISHED_ROOM_LEAVE_ENABLED",
  /** Room pushes into each member's room index, indexed lists and the 500-link bound. Set only through FEATURES. */
  roomIndex: "ROOM_INDEX_ENABLED",
  /** The live socket (GET /v1/live), its capability and the hints room and friend changes send to it. Set only through FEATURES. */
  liveConnection: "LIVE_CONNECTION_ENABLED",
  /** Turn try counts: the capability and GET .../tries. Turns may carry a count whatever the flag. Set only through FEATURES. */
  turnTries: "TURN_TRIES_ENABLED",
  /** End-of-run reactions: the capability, faces on room reads and GET .../end-reactions. Turns may carry a face whatever the flag. Set only through FEATURES. */
  endReactions: "END_REACTIONS_ENABLED",
  /** Reactions during a run (v2/run-reactions.ts): the capability, the friend's tracks on room reads, turn replies and the end reactions list. Turns may carry a track whatever the flag. Replays read every track through the end reactions list, so they also need endReactions on. Set only through FEATURES. */
  inRunReactions: "IN_RUN_REACTIONS_ENABLED",
  /** Hard rooms: the capability, creating one, and the reset and read routes of rooms that are not hard yet (v2/hard-mode.ts). Set only through FEATURES. */
  hardMode: "HARD_MODE_ENABLED",
  /** Play Games sign-in as a way back to a friend identity (link, unlink, restore) and its capability. Set only through FEATURES. */
  playGames: "PLAY_GAMES_ENABLED",
  /** Game Center identity verification for the same link, unlink and restore routes. */
  gameCenter: "GAME_CENTER_ENABLED",
  /** The iOS launch waitlist for the friend link page: /v1/waitlist/ios and its confirm route (waitlist.ts). Set only through FEATURES. */
  iosWaitlist: "IOS_WAITLIST_ENABLED",
  /** Display names: PUT /v1/profile/name, names on friends pages and room reads, writes into rooms and the capability (display-names.ts). Set only through FEATURES. */
  displayNames: "DISPLAY_NAMES_ENABLED",
  /** Pollen earned from accepted turns and first clears, the wallet routes and the turn reply field (pollen/). Set only through FEATURES. */
  pollenEarn: "POLLEN_EARN",
  /** The wardrobe (pollen/wardrobe.ts, pollen/earned.ts): owned and earned items and the look on the wallet read, wearing and taking off, and the replay job delivering board rewards. Every Hard is recorded while earning is on. Needs POLLEN_EARN. Set only through FEATURES. */
  pollenWardrobe: "POLLEN_WARDROBE",
  /** The shop (pollen/spend.ts): buying, prices and the catalogue on the wallet read, and the name change price. Needs POLLEN_WARDROBE. Set only through FEATURES. */
  pollenShop: "POLLEN_SHOP",
  /** Looks in rooms (pollen/room-looks.ts): each member's look and each turn's look, served to phones that send X-AfterYou-Looks. Set only through FEATURES. */
  pollenLooks: "POLLEN_LOOKS",
  /** Item blooms (pollen/item-blooms.ts): the second roll on a free-chapter bank turn may drop a shop item. Needs POLLEN_SHOP. Set only through FEATURES. */
  pollenItemBlooms: "POLLEN_ITEM_BLOOMS",
  /** The Full Journey monthly grant (pollen/grant.ts): instalments on the wallet read and the PollenClaims check. Needs POLLEN_EARN. Set only through FEATURES. */
  pollenGrant: "POLLEN_GRANT",
  /** Leaderboards (leaderboards/): board reads, posting finished together runs, the name choice, reports and the replay check routes. Set only through FEATURES. */
  leaderboards: "LEADERBOARDS",
} as const);

export type FlagName = keyof typeof FLAG_VARS;
export type FlagVar = typeof FLAG_VARS[FlagName];

/**
 * Every var and secret the worker reads, all optional. The generated Env shares
 * some of these keys, so Env, a test's partial object and a narrow config are
 * all assignable to it without a cast.
 */
export type ServerVars = { [V in FlagVar]?: string } & {
  /** Comma list of FlagVar names that are on (featureNames). Unknown names are ignored. */
  FEATURES?: string;
  /** Secret. The Pollen root key: HKDF in pollen/keys.ts derives the bloom keys from it; at least 32 characters. */
  POLLEN_SECRET?: string;
  ENVIRONMENT?: string;
  REVENUECAT_VERIFICATION_MODE?: string;
  REVENUECAT_API_VERSION?: string;
  REVENUECAT_ENTITLEMENT?: string;
  REVENUECAT_SECRET_KEY?: string;
  REVENUECAT_PROJECT_ID?: string;
  REVENUECAT_ENTITLEMENT_LOOKUP_ID?: string;
  REVENUECAT_PLAY_ENVIRONMENT?: string;
  REVENUECAT_PLAY_ENTITLEMENT_LOOKUP_ID?: string;
  REVENUECAT_PLAY_PRODUCT_ID?: string;
  /** Comma list of RevenueCat `prod…` IDs for the Play Full Journey subscriptions. Unset keeps one-time-only admission. */
  REVENUECAT_PLAY_SUBSCRIPTION_PRODUCT_IDS?: string;
  /** Comma list of reviewer player IDs. */
  REVENUECAT_REVIEWER_IDS?: string;
  /** Comma list of RevenueCat `prod…` IDs for the App Store Full Journey subscriptions. Required while appStoreEntitlements is on. */
  REVENUECAT_APP_STORE_SUBSCRIPTION_PRODUCT_IDS?: string;
  /** `production`, `sandbox` or `both` (the default when unset). Real buyers are production; App Review,
   * TestFlight and developer sandbox testers are sandbox, which only Apple accounts can make. */
  REVENUECAT_APP_STORE_ENVIRONMENT?: string;
  /** Optional opaque `entl…` ID when the App Store products sit on a separate entitlement. Unset reuses the Play lookup ID. */
  REVENUECAT_APP_STORE_ENTITLEMENT_LOOKUP_ID?: string;
  MIN_CLIENT_VERSION_PLAY?: string;
  MIN_CLIENT_VERSION_GITHUB?: string;
  MIN_CLIENT_VERSION_APP_STORE?: string;
  /** JSON object of alias -> player id, parsed in friend-aliases.ts. */
  FRIEND_ALIASES?: string;
  /** Firebase service account JSON, parsed in notifications.ts. */
  FCM_SERVICE_ACCOUNT_JSON?: string;
  TESTER_CODE_SHA256?: string;
  /** Public Play Games Services project (application) id, digits only. */
  PLAY_GAMES_APP_ID?: string;
  /** Public OAuth web client id the phone asks Google for a server auth code with. */
  PLAY_GAMES_WEB_CLIENT_ID?: string;
  /** Secret: that web client's OAuth client secret, set with wrangler secret put. */
  PLAY_GAMES_CLIENT_SECRET?: string;
  /** Optional: the iOS bundle id Game Center signs; com.aamirazeez.afteryou when unset. */
  GAME_CENTER_BUNDLE_ID?: string;
  SAFETY_OPERATOR_TOKEN?: string;
  /** Secret. A Resend API key; Resend's only key that can add contacts is full access. */
  RESEND_API_KEY?: string;
  /** The Resend segment (formerly audience) that waitlist contacts join. */
  RESEND_SEGMENT_ID?: string;
  /** Secret. The Turnstile widget's secret key for siteverify. */
  TURNSTILE_SECRET_KEY?: string;
  /** The Turnstile widget's public site key, handed to the link page. */
  TURNSTILE_SITE_KEY?: string;
  /** Secret. Signs the waitlist confirm links (waitlist-token.ts); at least 32 characters. */
  WAITLIST_CONFIRM_SECRET?: string;
  /** The reply-to address on waitlist emails. */
  WAITLIST_REPLY_TO?: string;
  /** The address waitlist emails come from, on a domain verified in Resend; shown as "After You". */
  WAITLIST_FROM?: string;
};

/** The one flag rule, by var name: its own var is exactly "true", or FEATURES lists it. */
export function flagOn(env: ServerVars, name: FlagVar): boolean { return String(env[name]) === "true" || featureNames(env.FEATURES).has(name); }

/** A comma-separated var as trimmed, non-empty items. Unset gives []. */
export function commaList(raw: string | undefined): string[] {
  return (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
}

const KNOWN_VARS: ReadonlySet<string> = new Set(Object.values(FLAG_VARS));
/** The last FEATURES value read and its names, so a request parses it once, not once per flag. */
let lastFeatures: { raw: unknown; names: ReadonlySet<FlagVar> } = { raw: undefined, names: new Set() };
/**
 * The flags a FEATURES value turns on: its comma-separated items, trimmed, that exactly
 * match a FlagVar (case counts). Unknown items and a value that is not a string turn nothing on.
 */
export function featureNames(raw: unknown): ReadonlySet<FlagVar> {
  if (raw === lastFeatures.raw) return lastFeatures.names;
  const names = new Set(typeof raw === "string" ? commaList(raw).filter(item => KNOWN_VARS.has(item)) as FlagVar[] : []);
  lastFeatures = { raw, names };
  return names;
}

/** One accessor per flag: `flags.v2Rooms(env)`. */
export const flags: { readonly [K in FlagName]: (env: ServerVars) => boolean } = Object.freeze(Object.fromEntries(
  (Object.entries(FLAG_VARS) as [FlagName, FlagVar][]).map(([name, variable]) => [name, (env: ServerVars) => flagOn(env, variable)])
) as { [K in FlagName]: (env: ServerVars) => boolean });

