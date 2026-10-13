/** One stored row. Rows live in Durable Object SQLite, which caps a row at 2 MB;
 * the widest Turn of the Tide pair row is about 823 KB. */
export const MAX_ROW_BYTES = 1536 * 1024;
