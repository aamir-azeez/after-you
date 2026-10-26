/**
 * Weeks as Pollen counts them: they start Monday 00:00 UTC (the bank refill) and are named by
 * their ISO 8601 week ("2026-W44"), which the bloom roll hashes. Server time only.
 */
export const WEEK_MS = 7 * 86_400_000;
/** Monday 5 January 1970, 00:00 UTC: week index 0. */
const FIRST_MONDAY_MS = Date.UTC(1970, 0, 5);

/** Whole weeks since the first Monday of 1970, so two times in the same Monday-start week share one index. */
export function weekIndex(ms: number): number { return Math.floor((ms - FIRST_MONDAY_MS) / WEEK_MS); }

/** The ISO 8601 week of a time, as "YYYY-Www": the year is the one its Thursday falls in. */
export function isoWeek(ms: number): string {
  const day = new Date(ms);
  const thursday = Date.UTC(day.getUTCFullYear(), day.getUTCMonth(), day.getUTCDate()) + (3 - (day.getUTCDay() + 6) % 7) * 86_400_000;
  const year = new Date(thursday).getUTCFullYear();
  const week = 1 + Math.floor((thursday - Date.UTC(year, 0, 1)) / WEEK_MS);
  return `${year}-W${String(week).padStart(2, "0")}`;
}

export const ISO_WEEK_PATTERN = /^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$/;
