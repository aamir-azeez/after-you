/**
 * Strangers in a public duel's room never see each other's ids (PLAN 1). Inside the server every room reply keeps the
 * real ids, since the duel, the boards and the turn hooks all need them; a public duel's room only adds
 * `duel_masks` beside them: the stand-in for each member and the id it stands for. On the way out to a phone the
 * Worker swaps every copy of the other member's id for its stand-in and drops the masks and the partner's room name
 * (maskedResponse). A reply without masks is passed through untouched, unread past a substring check.
 *
 * Scope: an object holding `duel_masks`, or holding a direct child that does (a turn reply's `room`), is masked as a
 * whole, so a beside field next to the room (partner_name) goes too. Nothing outside that object changes, so a list
 * of rooms masks each entry by its own room.
 */
export type DuelMasks = { host: string; guest: string; host_id: string; guest_id: string | null };
const MARK = "\"duel_masks\"";

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === "object" && value !== null && !Array.isArray(value);

function validMasks(value: unknown): value is DuelMasks {
  return isRecord(value) && typeof value.host === "string" && typeof value.guest === "string" && typeof value.host_id === "string" && (value.guest_id === null || typeof value.guest_id === "string");
}

/** The masks this object holds, or a direct child holds. */
function masksOf(value: Record<string, unknown>): DuelMasks | null {
  if (validMasks(value.duel_masks)) return value.duel_masks;
  for (const child of Object.values(value)) if (isRecord(child) && validMasks(child.duel_masks)) return child.duel_masks;
  return null;
}

/** Every string equal to an id in `swap` becomes its stand-in; masks and partner names go. */
function swapAll(value: unknown, swap: ReadonlyMap<string, string>): unknown {
  if (typeof value === "string") return swap.get(value) ?? value;
  if (Array.isArray(value)) return value.map(item => swapAll(item, swap));
  if (!isRecord(value)) return value;
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) {
    if (key === "duel_masks" || key === "partner_name") continue;
    out[key] = swapAll(item, swap);
  }
  return out;
}

/** The value as `viewer`'s phone may see it. */
export function maskPublicRooms(value: unknown, viewer: string): unknown {
  if (Array.isArray(value)) return value.map(item => maskPublicRooms(item, viewer));
  if (!isRecord(value)) return value;
  const masks = masksOf(value);
  if (masks) {
    const swap = new Map<string, string>();
    if (masks.host_id !== viewer) swap.set(masks.host_id, masks.host);
    if (masks.guest_id !== null && masks.guest_id !== viewer) swap.set(masks.guest_id, masks.guest);
    return swapAll(value, swap);
  }
  const out: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(value)) out[key] = maskPublicRooms(item, viewer);
  return out;
}

/** A JSON reply as `viewer`'s phone may see it; any other reply, or one with no public room in it, unchanged. */
export async function maskedResponse(response: Response, viewer: string): Promise<Response> {
  if (!(response.headers.get("Content-Type") ?? "").includes("application/json")) return response;
  const text = await response.text();
  const body = text.includes(MARK) ? JSON.stringify(maskPublicRooms(JSON.parse(text), viewer)) : text;
  return new Response(body, { status: response.status, statusText: response.statusText, headers: response.headers });
}

/** A phone's redo body names players by what it was shown: their stand-ins become the ids again (v2/room.ts redo). */
export function unmaskRedo(value: unknown, masks: DuelMasks | null): unknown {
  if (!masks || !isRecord(value) || !isRecord(value.source)) return value;
  const back = new Map<string, string>([[masks.host, masks.host_id], ...(masks.guest_id ? [[masks.guest, masks.guest_id] as [string, string]] : [])]);
  const source = Object.fromEntries(Object.entries(value.source).map(([key, item]) => [key, typeof item === "string" ? back.get(item) ?? item : item]));
  return { ...value, source };
}
