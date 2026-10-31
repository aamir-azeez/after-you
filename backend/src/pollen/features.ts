import { flags, type ServerVars } from "../flags";
import { pollenSecret } from "./keys";
import { APP_STORE_BUNDLES_READY } from "./bundles";

/**
 * Which Pollen parts are on. Earning needs POLLEN_EARN and a usable POLLEN_SECRET (no turn is paid
 * without its bloom roll). The wardrobe needs earning: it shows the balance earning keeps, and Every
 * Hard comes from the Hard clears it records. The shop needs the wardrobe: what it sells is owned and
 * worn there, and a Special unlocks from the first clears earning records. Looks need only POLLEN_LOOKS.
 * Item blooms need the shop: a dropped item is one the shop sells. The monthly grant needs earning:
 * it pays into the same wallet. Refund checks need the shop, and bundles need refund checks, so bought
 * Pollen is never sold without a refund taking it back, and refunds keep being taken back after bundles stop.
 * Bundles sell per store: POLLEN_BUNDLES on Google Play, POLLEN_BUNDLES_APP_STORE on the App Store once its four
 * products are in bundles.json. Either one opens the claim route and the wallet read's `bundles` part. Settling
 * itself pays any counted production purchase from either store (bundle-provider.ts), so a purchase made just
 * before a store switches off is still paid by the next claim while either store sells, or by the daily refund
 * check for a player who bought a bundle before. A first-time buyer whose store switched off before the claim
 * landed waits until a store sells again (the same for Play). On iPhone the app also shows bundles only while the
 * server admits App Store subscribers (entitlement.ts storeCapability), so POLLEN_BUNDLES_APP_STORE sells there
 * only beside APP_STORE_ENTITLEMENTS_ENABLED.
 */
export function earningOn(env: ServerVars): boolean { return flags.pollenEarn(env) && pollenSecret(env) !== null; }
export function wardrobeOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenWardrobe(env); }
export function shopOn(env: ServerVars): boolean { return wardrobeOn(env) && flags.pollenShop(env); }
export function looksOn(env: ServerVars): boolean { return flags.pollenLooks(env); }
export function itemBloomsOn(env: ServerVars): boolean { return shopOn(env) && flags.pollenItemBlooms(env); }
export function grantOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenGrant(env); }
export function refundsOn(env: ServerVars): boolean { return shopOn(env) && flags.pollenRefunds(env); }
export function bundlesOn(env: ServerVars): boolean { return refundsOn(env) && flags.pollenBundles(env); }
export function appStoreBundlesOn(env: ServerVars): boolean { return refundsOn(env) && flags.pollenBundlesAppStore(env) && APP_STORE_BUNDLES_READY; }
/** Whether a turn's credit may drop an item: item blooms on, for an app offered the shop (routes.ts pollenShopClient). */
export function itemDropsOn(env: ServerVars, shopClient: boolean): boolean { return shopClient === true && itemBloomsOn(env); }
/** Bundles sell in at least one store: the claim route and the wallet read's `bundles` part. */
export function anyBundlesOn(env: ServerVars): boolean { return bundlesOn(env) || appStoreBundlesOn(env); }

/** What the wallet read carries: nothing more, the wardrobe (owned items and the look), or the wardrobe with the shop. */
export type WardrobeMode = "off" | "wardrobe" | "shop";
export function wardrobeMode(env: ServerVars): WardrobeMode { return shopOn(env) ? "shop" : wardrobeOn(env) ? "wardrobe" : "off"; }
