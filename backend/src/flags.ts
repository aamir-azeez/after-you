/**
 * Every deploy var the worker reads, and one accessor per feature flag.
 *
 * A flag is on only when String(var) is exactly "true". Absent, "false", "TRUE",
 * "1", "" and any other value are off. (A boolean true, as tests pass it, also
 * reads on, because String(true) is "true".)
 */
export const FLAG_VARS = Object.freeze({
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
  turnOfTheTideV2Chapter: "TURN_OF_THE_TIDE_V2_CHAPTER_ENABLED",
  /** Campaign creation and its capability. */
  campaignCreation: "CAMPAIGN_CREATION_ENABLED",
  /** Campaign control and redo mutations. */
  campaignMutations: "CAMPAIGN_MUTATIONS_ENABLED",
  /** The operator-only Story data count and erase routes under /operator/story/. */
  storyDrain: "STORY_DRAIN_ENABLED",
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
  /** Leaving a finished room (POST .../leave with leave_finished) and its capability. */
  finishedRoomLeave: "FINISHED_ROOM_LEAVE_ENABLED",
  /** Room pushes into each member's room index, indexed lists and the 500-link bound. */
  roomIndex: "ROOM_INDEX_ENABLED",
  /** The live socket (GET /v1/live), its capability and the hints room and friend changes send to it. */
  liveConnection: "LIVE_CONNECTION_ENABLED",
  /** Turn try counts: the capability and GET .../tries. Turns may carry a count whatever the flag. */
  turnTries: "TURN_TRIES_ENABLED",
  /** End-of-run reactions: the capability, faces on room reads and GET .../end-reactions. Turns may carry a face whatever the flag. */
  endReactions: "END_REACTIONS_ENABLED",
  /** Hard rooms: the capability, creating one, and the reset and read routes of rooms that are not hard yet (v2/hard-mode.ts). */
  hardMode: "HARD_MODE_ENABLED",
  /** Play Games sign-in as a way back to a friend identity (link, unlink, restore) and its capability. */
  playGames: "PLAY_GAMES_ENABLED",
  /** Game Center identity verification for the same link, unlink and restore routes. */
  gameCenter: "GAME_CENTER_ENABLED",
  /** The iOS launch waitlist for the friend link page: /v1/waitlist/ios and its confirm route (waitlist.ts). */
  iosWaitlist: "IOS_WAITLIST_ENABLED",
} as const);

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
};

/** The one flag rule, by var name. */
export function flagOn(env: ServerVars, name: FlagVar): boolean { return String(env[name]) === "true"; }

/** A comma-separated var as trimmed, non-empty items. Unset gives []. */
export function commaList(raw: string | undefined): string[] {
  return (raw ?? "").split(",").map(value => value.trim()).filter(Boolean);
}

/** One accessor per flag: `flags.v2Rooms(env)`. */
export const flags: { readonly [K in FlagName]: (env: ServerVars) => boolean } = Object.freeze(Object.fromEntries(
  (Object.entries(FLAG_VARS) as [FlagName, FlagVar][]).map(([name, variable]) => [name, (env: ServerVars) => flagOn(env, variable)])
) as { [K in FlagName]: (env: ServerVars) => boolean });

