import { adapter } from "./protocol-cooperative";
import { journeyAdapter } from "./protocol-journey";
import { lighthouseAdapter } from "./protocol-lighthouse";
import type { ChapterAdapter } from "./chapter-types";
import highDefinition from "./legacy/high-and-low.json";
import highInitial from "./legacy/high-and-low-initial.json";
import rollingDefinition from "./legacy/rolling-home.json";
import rollingInitial from "./legacy/rolling-home-initial.json";
import houseDefinition from "./legacy/a-house-for-two.json";
import houseInitial from "./legacy/a-house-for-two-initial.json";
import wellDefinition from "./legacy/the-wishing-well.json";
import wellInitial from "./legacy/the-wishing-well-initial.json";
import conservatoryDefinition from "./legacy/conservatory.json";
import conservatoryInitial from "./legacy/conservatory-initial.json";
import homeDefinition from "./legacy/long-way-home.json";
import homeInitial from "./legacy/long-way-home-initial.json";
import homeV2Definition from "./legacy/long-way-home-v2.json";
import homeV2Initial from "./legacy/long-way-home-v2-initial.json";
import tideDefinition from "./legacy/turn-of-the-tide.json";
import tideInitial from "./legacy/turn-of-the-tide-initial.json";
import tideV2Definition from "./legacy/turn-of-the-tide-v2.json";
import tideV2Initial from "./legacy/turn-of-the-tide-v2-initial.json";
import lighthouseDefinition from "./legacy/sleeping-lighthouse-v2.json";
import lighthouseInitial from "./legacy/sleeping-lighthouse-v2-initial.json";

/** Published chapters as older apps hold them, from before every lever, switch,
 * selector and mirror became solid with a longer reach (owner, 2026-11-20; the game's
 * core/solid_footprint.gd with_hands). Each keeps its old definition hash, so an older
 * app keeps starting, joining and finishing its own rooms, and a room made before the
 * change keeps verifying (chapters.ts finds them and advertises them on room level 2,
 * after the rows). A newer app knows only the new hashes, so the two never share a room.
 * Retire these once CONFIG min_client_version reaches the release with the change.
 * Byte copies of the published files at origin/main b7789880; never edit them. */
type Cooperative = Parameters<typeof adapter>;
type Journey = Parameters<typeof journeyAdapter>;
export const LEGACY_CHAPTERS: readonly ChapterAdapter[] = Object.freeze([
  adapter(highDefinition as Cooperative[0], highInitial as Cooperative[1], "6aa907e802c92445745a6452c6ec0850dd8e98724e689b58a8ec82915fb08956"),
  adapter(rollingDefinition as Cooperative[0], rollingInitial as Cooperative[1], "d6aaa6006597dd5e4ce4dbc641d94c81c2ab17c55bd80b50c6a240e0e91cff87"),
  adapter(houseDefinition as Cooperative[0], houseInitial as Cooperative[1], "b868745e7bc025bb8fe5a49b698b15dfb0d428ea9fe905ce46fa46dd27d79867"),
  adapter(wellDefinition as Cooperative[0], wellInitial as Cooperative[1], "4418a6f1ad6bdc3f1adee6d07d48184d03867a56a1b2d1d42c189584cfec5a94"),
  journeyAdapter(conservatoryDefinition as Journey[0], conservatoryInitial as Journey[1], "fd9fce12c4facd5fd659eedd5a510ea6b0ad796925458ccb73b4b37a893530d5"),
  journeyAdapter(homeDefinition as Journey[0], homeInitial as Journey[1], "bce3ddd36386ebb32f011b8d6afe95316992809030ea828b473bbbc3e1c6bb7f"),
  journeyAdapter(homeV2Definition as Journey[0], homeV2Initial as Journey[1], "4541bd920062e244f202fbe6ee95363a1f53ae5afc490ad600112af9f01a8c77"),
  journeyAdapter(tideDefinition as Journey[0], tideInitial as Journey[1], "3a6d111455aa69e60c440cc6f04a0656292ed9c40b31c66a7f999c85cd2a911a", 7),
  journeyAdapter(tideV2Definition as Journey[0], tideV2Initial as Journey[1], "1f88aabb592fbf14640b50dd0644755d6afe522cae39d844524ac68b491f0a43", 7),
  // Sleeping Lighthouse @2 before its mirrors and selector went solid (origin/main d1c90b6c).
  lighthouseAdapter(lighthouseDefinition, lighthouseInitial, "0f5a41aa23b53d9f97d47851740a1bdd484371bc128f8b319bed9f509a9e8149"),
]);
