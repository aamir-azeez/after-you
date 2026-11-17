/** One stored row. Rows live in Durable Object SQLite, which caps a row at 2 MB;
 * the widest Turn of the Tide pair row is about 823 KB. */
export const MAX_ROW_BYTES = 1536 * 1024;
/** A finished room's whole replay archive (replay-transfer.ts), as canonical JSON. */
export const MAX_REPLAY_ARCHIVE_BYTES = 16 * 1024 * 1024;
/** The most turn rows and pair rows one room holds (room.ts). */
export const MAX_ROOM_TURNS = 128, MAX_ROOM_PAIRS = 64;
