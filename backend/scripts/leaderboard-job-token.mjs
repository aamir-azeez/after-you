#!/usr/bin/env node
// Prints the leaderboard replay job's credential, derived from the Worker's
// SAFETY_OPERATOR_TOKEN exactly as src/leaderboards/job-token.ts derives it.
// Read the operator token from stdin and pipe the result straight into GitHub,
// so neither value lands in a command line, a file or the terminal:
//   Get-Content <private token file> | node scripts/leaderboard-job-token.mjs | gh secret set LEADERBOARD_JOB_TOKEN --repo <owner>/<repo>
import { createHmac } from "node:crypto";

const LABEL = "after-you leaderboard replay job v1";
const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const operator = Buffer.concat(chunks).toString("utf8").trim();
if (!/^[A-Za-z0-9_-]{43}$/.test(operator)) { console.error("stdin must be the 43 character operator token"); process.exit(2); }
process.stdout.write(createHmac("sha256", operator).update(LABEL).digest("base64url"));
