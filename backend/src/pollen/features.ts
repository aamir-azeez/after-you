import { flags, type ServerVars } from "../flags";
import { pollenSecret } from "./keys";

/**
 * Which Pollen parts are on. Earning needs POLLEN_EARN and a usable POLLEN_SECRET (no turn is paid
 * without its bloom roll). The wardrobe needs earning: it shows the balance earning keeps, and Every
 * Hard comes from the Hard clears it records. The shop needs the wardrobe: what it sells is owned and
 * worn there, and a Special unlocks from the first clears earning records. Looks need only POLLEN_LOOKS.
 * Item blooms need the shop: a dropped item is one the shop sells. The monthly grant needs earning:
 * it pays into the same wallet.
 */
export function earningOn(env: ServerVars): boolean { return flags.pollenEarn(env) && pollenSecret(env) !== null; }
export function wardrobeOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenWardrobe(env); }
export function shopOn(env: ServerVars): boolean { return wardrobeOn(env) && flags.pollenShop(env); }
export function looksOn(env: ServerVars): boolean { return flags.pollenLooks(env); }
export function itemBloomsOn(env: ServerVars): boolean { return shopOn(env) && flags.pollenItemBlooms(env); }
export function grantOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenGrant(env); }

/** What the wallet read carries: nothing more, the wardrobe (owned items and the look), or the wardrobe with the shop. */
export type WardrobeMode = "off" | "wardrobe" | "shop";
export function wardrobeMode(env: ServerVars): WardrobeMode { return shopOn(env) ? "shop" : wardrobeOn(env) ? "wardrobe" : "off"; }
