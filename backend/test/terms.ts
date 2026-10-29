import { env } from "cloudflare:workers";
import { runInDurableObject } from "./room-objects";
import { TERMS_VERSION } from "../src/public-policy";

/**
 * Photo uploads always need the owner's accepted safety terms, in the room too. Tests that drive rooms with synthetic
 * players, who have no identity to accept with, record the acceptance on each owner's profile as accepting does.
 */
export async function acceptTerms(...owners: string[]): Promise<void> {
  for (const owner of owners) await runInDurableObject(env.SAFETY_PROFILES.getByName(owner), instance => {
    const profile = instance as unknown as { read(owner: string): { terms_version: string | null; accepted_at: string | null }; write(state: unknown): void };
    const state = profile.read(owner); state.terms_version = TERMS_VERSION; state.accepted_at = new Date().toISOString(); profile.write(state);
  });
}
