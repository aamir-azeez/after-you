#!/usr/bin/env node
// The leaderboard replay job's network steps (.github/workflows/leaderboard-check.yml).
//   node scripts/leaderboard-check.mjs pull <base-url> <pending.json>
//   node scripts/leaderboard-check.mjs push <base-url> <verdicts.json>
// The credential comes only from the LEADERBOARD_JOB_TOKEN environment variable
// and is never printed. pull exits 0 and writes no entries when the server says
// leaderboards are off (503 leaderboards_disabled), so the job then does nothing.
// Godot (tests/leaderboard_replay_job.gd) does the checking in between.
import { readFile, writeFile } from "node:fs/promises";

const [mode, base, file] = process.argv.slice(2);
const token = process.env.LEADERBOARD_JOB_TOKEN ?? "";
if (!["pull", "push"].includes(mode) || !/^https:\/\/[a-z0-9.-]+$/.test(base ?? "") || !file) {
  console.error("usage: leaderboard-check.mjs pull|push https://<worker host> <file>");
  process.exit(2);
}
if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
  console.error("LEADERBOARD_JOB_TOKEN is missing or malformed; nothing to do.");
  process.exit(mode === "pull" ? 0 : 2);
}

async function post(action, body) {
  const response = await fetch(`${base}/operator/leaderboards/${action}`, {
    method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` }, body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000)
  });
  const text = await response.text();
  let parsed = null;
  try { parsed = JSON.parse(text); } catch { parsed = null; }
  return { status: response.status, body: parsed };
}

if (mode === "pull") {
  const answer = await post("pending", { schema_version: 1 });
  if (answer.status === 503 && answer.body?.error?.code === "leaderboards_disabled") {
    await writeFile(file, JSON.stringify({ schema_version: 1, entries: [] }));
    console.log("Leaderboards are off on the server; nothing to check.");
    process.exit(0);
  }
  if (answer.status !== 200 || !Array.isArray(answer.body?.entries)) { console.error(`pending: HTTP ${answer.status} ${answer.body?.error?.code ?? ""}`); process.exit(1); }
  await writeFile(file, JSON.stringify(answer.body));
  console.log(`Runs to check: ${answer.body.entries.length}`);
} else {
  const verdicts = JSON.parse(await readFile(file, "utf8"));
  if (verdicts?.schema_version !== 1 || !Array.isArray(verdicts.verdicts)) { console.error("verdicts file is malformed"); process.exit(1); }
  for (let start = 0; start < verdicts.verdicts.length; start += 64) {
    const answer = await post("verdicts", { schema_version: 1, verdicts: verdicts.verdicts.slice(start, start + 64) });
    if (answer.status !== 200) { console.error(`verdicts: HTTP ${answer.status} ${answer.body?.error?.code ?? ""}`); process.exit(1); }
    console.log(`Verdicts posted: ${Math.min(start + 64, verdicts.verdicts.length)}; ranked now: ${answer.body.ranked.length}`);
  }
  if (!verdicts.verdicts.length) console.log("No verdicts to post.");
}
