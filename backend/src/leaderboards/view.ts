/**
 * What anyone may read of a board, the same bytes for every reader, so it can
 * be cached. It never carries a player id, a pair key or a room id:
 * - top: the ranked runs, at most 10. `names` is the two display names only
 *   when both players chose to show theirs, else null ("A pair").
 *   `gold_leaf` marks a first place that earned the Gold leaf.
 * - checking: opaque ids of runs waiting for the replay check or a person.
 *   A member works out their own run's id (run.ts entryId) to find it here.
 */
export type BoardRow = { rank: number; entry_id: string; ticks: number; finished_on: string; names: string[] | null; gold_leaf: boolean };
export type BoardView = { schema_version: 1; board: string; top: BoardRow[]; checking: string[] };

export function emptyView(board: string): BoardView { return { schema_version: 1, board, top: [], checking: [] }; }

/** Whether a run of `ticks` could still place: true unless ten ranked runs are all strictly faster. Ties go to the board, which knows when each finished. */
export function mightPlace(view: BoardView, ticks: number, places: number): boolean {
  return view.top.length < places || ticks <= view.top[places - 1].ticks;
}
