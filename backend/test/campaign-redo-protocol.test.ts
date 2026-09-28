import { expect, it } from "vitest";
import { canonicalJson, digest } from "../src/protocol";
import { campaignRedoFork, campaignRedoInput, campaignRedoReceipt, type CampaignRedoBinding } from "../src/v2/campaign-redo";
import type { ReceiptV2 } from "../src/v2/room";
import wire from "../../game/tests/fixtures/campaign/redo-v1.json";

it("matches the client fixture's parent envelope and unchanged child fork hash", async () => {
  const binding = wire.accept.binding as CampaignRedoBinding;
  const input = await campaignRedoInput(wire.accept, binding, true), fork = campaignRedoFork(input);
  expect(fork).toEqual(wire.fork_body);
  expect(await digest(canonicalJson({ operation: "fork", ...fork }))).toBe(wire.fork_request_hash);
  expect({ schema_version: 1, binding, receipt: campaignRedoReceipt(wire.response.receipt as ReceiptV2, binding, input.idempotency_key) })
    .toEqual(wire.response);
  // The request ID binds the entire accepted A source, including its actual author.
  await expect(campaignRedoInput({ ...wire.accept, source: { ...wire.accept.source, revision: wire.accept.source.revision + 1 } }, binding, true))
    .rejects.toMatchObject({ status: 400, code: "invalid_redo_request" });
});
