// node --test scripts/leaderboard-job-token.test.mjs
// The script derives the same job credential the Worker does
// (test/leaderboards.test.ts pins the same value against src/leaderboards/job-token.ts).
import { test } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const script = fileURLToPath(new URL("./leaderboard-job-token.mjs", import.meta.url));
test("derives the job credential from the operator token on stdin", () => {
  const run = spawnSync(process.execPath, [script], { input: "o".repeat(43) + "\n", encoding: "utf8" });
  assert.equal(run.status, 0);
  assert.equal(run.stdout, "fuUHqWRoTemuAoI-8DEgp8eiGMj_zGBq6GzaHBLQRqs");
});
test("refuses anything but a 43 character token", () => {
  const run = spawnSync(process.execPath, [script], { input: "short", encoding: "utf8" });
  assert.equal(run.status, 2);
  assert.equal(run.stdout, "");
});
