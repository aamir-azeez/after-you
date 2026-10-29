import { describe, expect, it } from "vitest";

/**
 * Architecture check: recording, checkpoint and replay bodies are stored and
 * served in the shared blob format (src/blob-codec.ts: encodeBlob, decodeBlob,
 * bytesDigest; game/services/blob_codec.gd on the phone). A static scan of
 * src/ flags, line by line:
 * - STORE: an SQL INSERT or UPDATE into a table that holds bodies (BODY_TABLES),
 *   or one whose line names a checkpoint or recording (hash fields aside);
 * - SERVE: a json(), new Response() or JSON.stringify() line that names a
 *   checkpoint or recording.
 * It reads lines, so it catches the direct forms, not a body passed along
 * under another name. Every raw use that exists is listed in RAW_ALLOWED with
 * how many lines and why; anything else fails with what to use instead.
 */
const sources = import.meta.glob<string>("../src/**/*.ts", { query: "?raw", import: "default", eager: true });

/** Tables that hold a body as it is. lb_replays, lb_proof_blobs and duel_proofs hold only tagged blob bodies, so they are not listed; lb_proofs is the old raw form, read and emptied only (leaderboards/proofs.ts). */
const BODY_TABLES = /\b(?:INSERT(?:\s+OR\s+\w+)?\s+INTO|UPDATE|REPLACE\s+INTO)\s+(?:turns|pairs|room|lb_proofs|replay_transfer)\b/i;
const NAMES_BODY = /checkpoint|recording|JSON\.stringify\(\s*(?:pair|turn|archive|blob)\b/i;
const WRITE = /\b(?:INSERT|UPDATE|REPLACE)\b/;
const SERVE = /\bjson\(|new Response\(|JSON\.stringify\(/;
/** recording_hash, checkpointHash and the like name a hash, not a body. */
const HASH_NAMES = /\b\w*(?:recording|checkpoint)\w*hash\w*\b|\b\w*Hash\b/gi;

/** file (under src/) -> [lines flagged, why that raw use stays]. */
const RAW_ALLOWED: Record<string, [number, string]> = {
  "room.ts": [4, "legacy v1 room state, read and written whole"],
  "storage-schema.ts": [1, "operator snapshot export and import of v1 tables as plain rows"],
  "v2/storage-schema.ts": [4, "operator snapshot export and import of v2 tables as plain rows"],
  "v2/room.ts": [6, "the live room tables (room, turns, pairs) a turn writes; room history offloads finished attempts as blobs later (history-room.ts)"],
  "v2/history-room.ts": [6, "restoring an offloaded attempt's rows from its decoded blob, and stubbing them when it is offloaded"],
  "v2/replay-transfer.ts": [7, "the replay transfer's own archive and the room rows it stubs and restores"],
  "v2/campaign-root.ts": [2, "a campaign root's room state"],
  "v2/campaign-target.ts": [1, "a campaign chapter room's first state"],
  "v2/campaign-deletion.ts": [1, "a deleted campaign room's marker"],
  "v2/routes.ts": [1, "a member's read of one pair's recordings (room.pairRecording)"]
};

function rawUses(): Map<string, string[]> {
  const found = new Map<string, string[]>();
  for (const [path, text] of Object.entries(sources)) {
    const file = path.replace(/^\.\.\/src\//, "");
    text.split(/\r?\n/).forEach((raw, index) => {
      const line = raw.replace(HASH_NAMES, "");
      const store = /sql\.exec|insert:/.test(line) && WRITE.test(line) && (BODY_TABLES.test(line) || NAMES_BODY.test(line));
      const serve = !store && SERVE.test(line) && /checkpoint|recording/i.test(line);
      if (store || serve) found.set(file, [...(found.get(file) ?? []), `${file}:${index + 1} ${store ? "stores" : "serves"}: ${raw.trim().slice(0, 140)}`]);
    });
  }
  return found;
}

describe("stored and served bodies", () => {
  it("scans the whole source", () => {
    expect(Object.keys(sources)).toContain("../src/blob-codec.ts");
    expect(Object.keys(sources).length).toBeGreaterThan(50);
  });
  it("go through the shared blob format, apart from the listed raw uses", () => {
    const problems: string[] = [];
    for (const [file, lines] of rawUses()) {
      const allowed = RAW_ALLOWED[file];
      if (!allowed) problems.push(...lines);
      else if (allowed[0] !== lines.length) problems.push(`${file}: ${lines.length} raw uses, RAW_ALLOWED lists ${allowed[0]}:`, ...lines);
    }
    for (const file of Object.keys(RAW_ALLOWED)) if (!rawUses().has(file)) problems.push(`${file}: listed in RAW_ALLOWED but has no raw use now; remove it`);
    expect(problems, problems.length ? [
      "A recording, checkpoint or replay body is stored or served raw.",
      "Use src/blob-codec.ts instead: encodeBlob() the canonical bytes, keep or send the tagged body with its byte_length and bytesDigest(),",
      "and decodeBlob() it back (see leaderboards/board.ts lb_replays and leaderboards/replays.ts). The phone reads it with game/services/blob_codec.gd.",
      "If this raw use is meant to stay, add it to RAW_ALLOWED in test/blob-format.test.ts with the reason.",
      ...problems].join("\n") : undefined).toEqual([]);
  });
});
