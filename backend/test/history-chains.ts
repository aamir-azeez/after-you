import { env } from "cloudflare:workers";
import type { Outcome } from "../src/protocol";
import type { RoomSnapshotV2, RoomV2 } from "../src/v2/room";
import relayA from "../../game/tests/fixtures/v2/relay-a.json";
import relayB from "../../game/tests/fixtures/v2/relay-b.json";
import relayMiddle from "../../game/tests/fixtures/v2/relay-checkpoint.json";
import gardenA from "../../game/tests/fixtures/v2/garden-a.json";
import gardenB from "../../game/tests/fixtures/v2/garden-b.json";
import relayFinal from "../../game/tests/fixtures/v2/final-checkpoint.json";
import liftA from "../../game/tests/fixtures/first_steps/a-little-lift-a.json";
import liftB from "../../game/tests/fixtures/first_steps/a-little-lift-b.json";
import liftMiddle from "../../game/tests/fixtures/first_steps/lift-checkpoint.json";
import growA from "../../game/tests/fixtures/first_steps/a-place-to-grow-a.json";
import growB from "../../game/tests/fixtures/first_steps/a-place-to-grow-b.json";
import stepsFinal from "../../game/tests/fixtures/first_steps/final-checkpoint.json";
import upperA from "../../game/tests/fixtures/cooperative/upper-path-a.json";
import upperB from "../../game/tests/fixtures/cooperative/upper-path-b.json";
import upperMiddle from "../../game/tests/fixtures/cooperative/upper-path-checkpoint.json";
import downA from "../../game/tests/fixtures/cooperative/down-and-around-a.json";
import downB from "../../game/tests/fixtures/cooperative/down-and-around-b.json";
import highFinal from "../../game/tests/fixtures/cooperative/high-and-low-final-checkpoint.json";
import tideA from "../../game/tests/fixtures/journey/set-the-tide-a.json";
import tideB from "../../game/tests/fixtures/journey/set-the-tide-b.json";
import tideMiddle from "../../game/tests/fixtures/journey/set-the-tide-checkpoint.json";
import slackA from "../../game/tests/fixtures/journey/slack-water-a.json";
import slackB from "../../game/tests/fixtures/journey/slack-water-b.json";
import tideFinal from "../../game/tests/fixtures/journey/slack-water-checkpoint.json";
import lighthouse from "../../game/tests/fixtures/lighthouse/v2-chain.json";

/** One played-through lineage of a chapter: each stage's records and the checkpoint they reach. */
export type Json = Record<string, any>;
export type Stage = { a: Json; b: Json; checkpoint: Json };
export type Chain = { name: string; key: { level_id: string; level_version: number; definition_hash: string }; stages: Stage[] };
const chain = (name: string, stages: Stage[]): Chain => ({ name, key: { level_id: stages[0].a.level_id, level_version: stages[0].a.level_version, definition_hash: stages[0].a.definition_hash }, stages });
const light = lighthouse as Json;
/** Every adapter family: relay, First Steps, cooperative, journey, and the six-stage Lighthouse. */
export const CHAINS: Chain[] = [
  chain("relay-isles", [{ a: relayA, b: relayB, checkpoint: relayMiddle }, { a: gardenA, b: gardenB, checkpoint: relayFinal }]),
  chain("first-steps", [{ a: liftA, b: liftB, checkpoint: liftMiddle }, { a: growA, b: growB, checkpoint: stepsFinal }]),
  chain("high-and-low", [{ a: upperA, b: upperB, checkpoint: upperMiddle }, { a: downA, b: downB, checkpoint: highFinal }]),
  chain("turn-of-the-tide", [{ a: tideA, b: tideB, checkpoint: tideMiddle }, { a: slackA, b: slackB, checkpoint: tideFinal }]),
  chain("sleeping-lighthouse", (light.pairs as Json[]).map((pair, index) => ({ a: pair.a, b: pair.b, checkpoint: light.checkpoints[index + 1] })))
];
export const HOST = "H".repeat(22), GUEST = "G".repeat(22), ROOM = "R".repeat(22), INVITE = "AB".repeat(10);
export const JOIN_VERSIONS = Array.from({ length: 16 }, (_, index) => index + 1);
export type Room = DurableObjectStub<RoomV2>;
export const newRoom = (): Room => env.ROOMS_V2.get(env.ROOMS_V2.newUniqueId());
export function value<T>(outcome: Outcome<T>): T { if (!outcome.ok) throw new Error(`${outcome.status} ${outcome.code}`); return outcome.value; }
export type Players = { host: string; guest: string };
const DEFAULT_PLAYERS: Players = { host: HOST, guest: GUEST };
export const owner = (recording: Json, players = DEFAULT_PLAYERS) => recording.player_slot === "p0" ? players.host : players.guest;
export async function open(room: Room, selected: Chain, roomId = ROOM): Promise<RoomSnapshotV2> {
  value(await room.initialize(roomId, HOST, INVITE, selected.key));
  return value(await room.join(GUEST, INVITE, JOIN_VERSIONS));
}
export async function playA(room: Room, state: RoomSnapshotV2, stage: Stage, players = DEFAULT_PLAYERS): Promise<RoomSnapshotV2> {
  return value(await room.commit(owner(stage.a, players), { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: stage.a })).room;
}
export async function playB(room: Room, state: RoomSnapshotV2, stage: Stage, players = DEFAULT_PLAYERS): Promise<RoomSnapshotV2> {
  return value(await room.commit(owner(stage.b, players), { base_revision: state.revision, branch: state.branch, idempotency_key: crypto.randomUUID(), recording: stage.b, checkpoint: stage.checkpoint })).room;
}
/** Plays stages [from, to) from the room's current stage. */
export async function play(room: Room, state: RoomSnapshotV2, selected: Chain, from: number, to = selected.stages.length, players = DEFAULT_PLAYERS): Promise<RoomSnapshotV2> {
  for (let index = from; index < to; index++) state = await playB(room, await playA(room, state, selected.stages[index], players), selected.stages[index], players);
  return state;
}
export async function fork(room: Room, state: RoomSnapshotV2, stageIndex: number, player = HOST): Promise<RoomSnapshotV2> {
  return value(await room.fork(player, { base_revision: state.revision, branch: state.branch, stage_index: stageIndex, idempotency_key: crypto.randomUUID() })).room;
}
