/**
 * Every deploy var the worker reads, and one accessor per feature flag.
 *
 * A flag is on only when String(var) is exactly "true". Absent, "false", "TRUE",
 * "1", "" and any other value are off. (A boolean true, as tests pass it, also
 * reads on, because String(true) is "true".)
 */
const FLAG_VARS = {
  /** Friend presence (online dots and the presence endpoints). */
  presence: "PRESENCE_ENABLED",
  /** Tester-code redemption. */
  testerAccess: "TESTER_ACCESS_ENABLED",
  /** Safety terms acceptance before interaction and photo routes. */
  safetyEnforcement: "SAFETY_ENFORCEMENT_ENABLED",
  /** RevenueCat customer deletion during account erasure. */
  revenuecatDeletion: "REVENUECAT_DELETION_ENABLED",
  /** Turn, redo and friend-room push notifications. */
  notifications: "NOTIFICATIONS_ENABLED",
  /** APNs alerts for iOS registrations. Off sends every token the data-only message. */
  iosPush: "IOS_PUSH_ENABLED",
  /** Friend room events (hosting alerts and their inbox). */
  friendRoomEvents: "FRIEND_ROOM_EVENTS_ENABLED",
  /** Relay (v2) room mutations. */
  v2Rooms: "V2_ROOMS_ENABLED",
  /** Chapter creation flags, read through the CHAPTERS table in v2/chapters.ts. */
  firstStepsChapter: "FIRST_STEPS_ENABLED",
  coopChapters: "COOP_CHAPTERS_ENABLED",
  houseChapter: "HOUSE_CHAPTER_ENABLED",
  journeyChapters: "JOURNEY_CHAPTERS_ENABLED",
  wishingWellChapter: "WISHING_WELL_CHAPTER_ENABLED",
  longWayHomeV2Chapter: "LONG_WAY_HOME_V2_CHAPTER_ENABLED",
  turnOfTheTideChapter: "TURN_OF_THE_TIDE_CHAPTER_ENABLED",
  lighthouseV2Chapter: "LIGHTHOUSE_V2_CHAPTER_ENABLED",
  /** Campaign creation and its capability. */
  campaignCreation: "CAMPAIGN_CREATION_ENABLED",
  /** Campaign control and redo mutations. */
  campaignMutations: "CAMPAIGN_MUTATIONS_ENABLED",
  /** Relay photo uploads (also needs v2Rooms). */
  relayPhotos: "RELAY_PHOTOS_ENABLED",
  /** Preset pair reactions (also needs v2Rooms). */
  presetReactions: "PRESET_REACTIONS_ENABLED",
  /** Relay photo delivery acknowledgements. */
  photoDelivery: "PHOTO_DELIVERY_ENABLED",
  /** Account photo transfer uploads. */
  photoTransfer: "PHOTO_TRANSFER_ENABLED",
  /** Replay transfer acknowledgements and its capability version. */
  replayTransfer: "REPLAY_TRANSFER_ENABLED",
  /** Room history offload. */
  historyOffload: "HISTORY_OFFLOAD_ENABLED",
  /** The required-update gate, GET /v1/app-status. */
  updateGate: "UPDATE_GATE_ENABLED",
  /** The Story boundary answer for 0.6.0 and older clients on a transferred room. */
  legacyTransferredRoomUnblock: "LEGACY_TRANSFERRED_ROOM_UNBLOCK",
  /** The Play plus App Store hosting check in place of the Play-only one. */
  appStoreEntitlements: "APP_STORE_ENTITLEMENTS_ENABLED",
} as const;

export type FlagName = keyof typeof FLAG_VARS;
export type FlagVar = typeof FLAG_VARS[FlagName];

/**
 * Every var and secret the worker reads, all optional. The generated Env shares
 * some of these keys, so Env, a test's partial object and a narrow config are
 * all assignable to it without a cast.
 */
export type ServerVars = { [V in FlagVar]?: string } & {
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
  SAFETY_OPERATOR_TOKEN?: string;
};

/** The one flag rule, by var name. */
export function flagOn(env: ServerVars, name: FlagVar): boolean { return String(env[name]) === "true"; }

/** One accessor per flag: `flags.v2Rooms(env)`. */
export const flags: { readonly [K in FlagName]: (env: ServerVars) => boolean } = Object.freeze(Object.fromEntries(
  (Object.entries(FLAG_VARS) as [FlagName, FlagVar][]).map(([name, variable]) => [name, (env: ServerVars) => flagOn(env, variable)])
) as { [K in FlagName]: (env: ServerVars) => boolean });

