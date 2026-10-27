import { flags, type ServerVars } from "../flags";
import { pollenSecret } from "./keys";

/**
 * Which Pollen parts are on. Earning needs POLLEN_EARN and a usable POLLEN_SECRET (no turn is paid
 * without its bloom roll). The shop needs earning too: it spends from the wallet earning keeps,
 * and a Special unlocks from the first clears it records. Looks need only POLLEN_LOOKS.
 * Item blooms need the shop: a dropped item is owned and worn through the wardrobe. The monthly
 * grant needs earning: it pays into the same wallet.
 */
export function earningOn(env: ServerVars): boolean { return flags.pollenEarn(env) && pollenSecret(env) !== null; }
export function shopOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenShop(env); }
export function looksOn(env: ServerVars): boolean { return flags.pollenLooks(env); }
export function itemBloomsOn(env: ServerVars): boolean { return shopOn(env) && flags.pollenItemBlooms(env); }
export function grantOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenGrant(env); }
