/** A backstop only, for a block whose token change was lost. */
export const UNBLOCKED_MEMO_MS = 10 * 60_000;

/**
 * One room's memory that its two players are not blocking each other, so the check before a room
 * request does not ask both SafetyProfiles each time.
 *
 * It keeps, per player, the safety token that player's request carried when the check last passed
 * (Player.safetyToken, read by auth() in the same call that checks the device). A block stores itself
 * and then gives both players a new random token before it answers, so from then on every request by
 * either player carries a token this room has not seen and is checked afresh. A blocked result forgets
 * everything, so a blocked pair is never remembered.
 */
export class UnblockedPairMemo {
  private pair: string | null = null;
  private until = 0;
  private readonly tokens = new Map<string, string>();
  async blocked(requester: string, token: string, a: string, b: string | null, check: () => Promise<boolean>): Promise<boolean> {
    if (!b) return check();
    const pair = a < b ? `${a}:${b}` : `${b}:${a}`;
    if (this.pair === pair && this.tokens.get(requester) === token && Date.now() < this.until) return false;
    const blocked = await check();
    if (blocked) { this.pair = null; this.tokens.clear(); return true; }
    if (this.pair !== pair || Date.now() >= this.until) { this.pair = pair; this.tokens.clear(); this.until = Date.now() + UNBLOCKED_MEMO_MS; }
    this.tokens.set(requester, token);
    return false;
  }
}
