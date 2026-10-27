import { flags, type ServerVars } from "../flags";
import { pollenSecret } from "./keys";

/**
 * Which Pollen parts are on. Earning needs POLLEN_EARN and a usable POLLEN_SECRET (no turn is paid
 * without its bloom roll). The shop needs earning too: it spends from the wallet earning keeps,
 * and a Special unlocks from the first clears it records. Looks need only POLLEN_LOOKS.
 */
export function earningOn(env: ServerVars): boolean { return flags.pollenEarn(env) && pollenSecret(env) !== null; }
export function shopOn(env: ServerVars): boolean { return earningOn(env) && flags.pollenShop(env); }
export function looksOn(env: ServerVars): boolean { return flags.pollenLooks(env); }
