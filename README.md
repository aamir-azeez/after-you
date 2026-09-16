![After You: two spirits on a floating island beside the game's title and main menu.](docs/screenshots/home-close.png)

*Home island — desktop capture.*

# After You

**Catch something your friend threw yesterday.**

After You is an Android cooperative puzzle game for two people playing at different
times. Leave a short recording in a floating world; your friend returns later to
move beside your ghost and finish what you started.

Begin with **First Steps**, two connected tasks in one world. Power a lift so your
friend can ride to the loft and ring its bell. Then swap roles: pass a glowing seed
downstairs and open the garden for your partner to plant it. A checkpoint keeps both
spirits where they finished. Solo practice lets one person play both parts.

![The second spirit rides the lift beside the first spirit's recording, with the bell action disabled until it is in reach.](docs/screenshots/first-steps-lift.png)

*First Steps — desktop capture.*

Screenshots show the Android app running in an emulator unless a caption says otherwise.

## Play

[Download an APK from the test releases](https://github.com/aamir-azeez/after-you/releases),
or browse the [release notes and earlier builds](https://github.com/aamir-azeez/after-you/releases).
Each release includes a SHA-256 checksum. Both players install the app. The source
targets Android 7.0/API 24 and later, with arm64 and x86-64 builds.
See each release's notes for its included features.

1. Choose **Find your first island → Start First Steps** to practice both parts.
2. Move with the thumbstick. The action button names the nearby action and becomes
   available when you can use it.
3. Record up to 20 seconds, preview your contribution, then save it. The next
   spirit plays beside that recording. Saving both parts completes a stage.
4. To play together, choose **First Steps with a friend** on the journey screen.
   Create a room and share its invitation code. Your friend enters it under
   **Play with a friend → Join a chapter**.

Neither player needs to stay online while the other records. Saved stages can be
revisited as combined replays. **Play with a friend → Choose an online chapter**
also offers First Steps and Relay Isles.

Forgiving catches are enabled initially. Settings include reduced motion,
left-handed controls, sound and haptics. Desktop development uses WASD/arrow keys,
Space for the context action and Escape to pause; the player build is Android.

### Optional photo memories

After saving an online First Steps or Relay Isles contribution, you can add a tiny
photo. Take or retake it, choose **Use photo**, then **Share photo with this room**.
Use keeps the image on your device; Share sends it to your friend. After confirmation,
choose **Done — continue playing**. **Keep on device & continue** saves the photo
in app-private storage without uploading it. Kept and downloaded photos no longer
expire from the camera cache.
**Continue without a photo** lets you skip it.

Each contribution keeps its own photo. During a combined replay, the bubble above
each spirit changes to the photo for that person's contribution in the current
stage, including when the recording roles swap. A turn without a photo has no
bubble; it does not borrow that person's latest photo. Shared photos are saved on
your phone for offline replays. The app checks for replacements and removals.
Once both phones confirm they have saved a photo, its server copy is removed.
Deleting a photo, room or account can also remove server copies.

**Shared replays** on the home screen collects cooperative memories separately
from **Your replays**. Open a room and choose a completed stage to watch both
contributions together. Previously cached memories can be viewed offline; opening
an older uncached memory requires a connection.

Before changing phones, open **Settings → Account & recovery → Photo transfer**.
Preparing a transfer explicitly uploads up to the newest 1,000 saved photos,
including unshared photos, to temporary private account storage. Recover the same
account on the other phone, then choose **Receive photos**. Each server copy is
removed after the receiving phone confirms it has saved the photo.
Temporary copies expire after 14 days; a new transfer can be prepared once every
24 hours. Temporary storage retains up to the newest 1,000 photos. Interrupted
requests retain their progress. Capacity limits can stop a transfer before all
selected photos upload; the app explains when to retry, and local photos are kept.
Reinstalling or clearing app data
removes local photos, so prepare a transfer before doing so.

New captures are square, at most 160 × 160 pixels and 24 KiB. Older photos remain
readable. You can reopen your contribution's photo to share or remove it without
changing the recorded turn. Disable prompts with **Don't ask after each turn**, or
change **Offer a photo after each shared turn** in Settings.

![A photo bubble follows the golden spirit during the partner's Relay Isles replay.](docs/screenshots/photo-memory-android.png)

*Shared photo memory on an Android emulator, using its virtual camera.*

The Android robot in the virtual-camera image is artwork by Google, reproduced
under the [Creative Commons Attribution 3.0 license](https://creativecommons.org/licenses/by/3.0/).
See [Android's attribution guidelines](https://developer.android.com/distribute/marketing-tools/brand-guidelines).
Android is a trademark of Google LLC.

### Relay Isles

Three islands, two bridges and a relay socket make a longer crossing. Save the
first pair of contributions at the middle island, swap roles, then carry the seed
to the far garden. Both stages replay as one memory. Rehearsals and checkpoints
survive closing the app.

Choose **Relay Isles · Solo** or **Relay Isles · Together** on the journey screen.
The two spirits keep their colors when their recording roles swap. Solo saves and
shared chapter rooms remain separate from the earlier eight-island journey.

![Relay Isles on Android: the second spirit collects the seed at the saved middle-island checkpoint, with the far garden still ahead.](docs/screenshots/relay-isles.png)

*The same three-island world continues after the checkpoint. Left-handed controls
are shown.*

<details>
<summary>After the online handoff</summary>

![The golden spirit plants the seed on the far island while the earlier teal recording holds the middle bridge open.](docs/screenshots/relay-online-android.png)

*An Android emulator capture of the completed online handoff.*

</details>

### The Sleeping Lighthouse · Solo

Six saved stages connect a group of islands: redirect a beam, replace a missing
lens, align two signals, leave timed crossings, hand off the same lens and wake
the lighthouse together. Each stage alternates the two contributions and keeps
a checkpoint. Rehearse either part, preview it before saving, and replay the
completed chapter. This solo chapter is included in the one-time **Full Journey**
unlock. Choose it from the journey screen to see the current store price, purchase
or restore access. Previously saved Lighthouse progress is kept.

![Both spirits leave the lighthouse lit at the end of the six-stage solo chapter.](docs/screenshots/lighthouse-ending.png)

*Desktop Godot capture. The ending stays visible until the player chooses to review
the turn.*

### Earlier islands

The original eight islands remain under **Earlier islands**, including their saved
progress and replays. They introduce charged bridges, a second plate and rising
gardens. Use **Earlier islands · online** or **Join an earlier island** for these
older shared rooms; chapter invitations use **Join a chapter** instead. Existing
rooms and recordings keep their original versions.

![Two spirits complete Across the Blue, with flowers blooming around the shared garden.](docs/screenshots/across-the-blue.png)

*Across the Blue: leave the crossing open, move to the second plate, and let your
friend return to finish the garden.*

<details>
<summary>Revisit your shared journey</summary>

![The online replay collection lists completed islands, including After You, Two Beats and Lantern Crossing.](docs/screenshots/shared-replays.png)

Both players can return to completed islands and watch their contributions together.

</details>

### Access, purchases and multiplayer

First Steps and Relay Isles are free chapters. **Full Journey** is a one-time
unlock for all six solo Lighthouse stages and the five premium earlier islands.
The first three earlier islands are also free. A friend joining the purchaser's
hosted earlier-island room does not need a second purchase; Lighthouse is solo.
Development APKs labelled **Test Store** use RevenueCat's simulated checkout.
Google Play builds use Google Play Billing through RevenueCat.

Invited testers can redeem an access code under **Settings → Tester code**.
Redeemed access remains available offline. After recovering the same game account
on another device, choose **Restore tester access**.

Waiting rooms check for updates about every three seconds while open, with manual
refresh and longer intervals after connection failures. Configured Android builds
offer optional **Settings → Notifications** for a nudge when a friend leaves a turn.
Notification delivery requires Android permission and a connection; manual refresh
remains available. Opening a notification checks the shared room and preserves any
unfinished rehearsal before switching rooms. Completed earlier-island rooms offer
preset reaction messages. First Steps and Relay Isles support optional turn photos;
preset messages are not yet available in those chapters. The Sleeping Lighthouse
is a solo chapter.

## Tech stack

| Layer | Technology | Role |
| --- | --- | --- |
| Game | **Godot 4.7.2**, GDScript, Compatibility renderer | Native 3D scenes, touch controls, animation and a deterministic 30 Hz puzzle simulation. |
| Android integration | **Kotlin 2.1.20**, custom Godot plugin | Camera capture, haptics, notifications and secure device storage. |
| Purchases | **RevenueCat Android SDK 10.15.1**, Google Play Billing 8.3.0 | Full Journey offerings, one-time purchase, restore and entitlement updates. The backend checks premium hosting access. |
| Backend | **Cloudflare Workers**, TypeScript 5.9.3 | HTTPS JSON API for anonymous accounts, invitations, turn submissions and synchronization. |
| Server storage | **SQLite-backed Durable Objects** | Persistent player and room state, recording receipts, photo delivery, temporary photo transfers and safety controls. |
| Push notifications | **Firebase Cloud Messaging 25.1.3** | The Worker sends turn alerts through FCM's HTTP v1 API; the Android plugin opens the relevant room. |
| On-device storage | **JSON saves, JPEG files, Android Keystore** | Local drafts, replays and photo caches; device credentials are encrypted with AES-GCM using a Keystore key. |
| Build tooling | **JDK 17**, Gradle 8.11.1, Android Gradle Plugin 8.9.2, PowerShell, Wrangler 4.131.2 | Android packaging and Worker development. Android compiles and targets API 36, with API 24 as the minimum. |
| Verification | **Godot headless tests, Vitest 4.1.11, JUnit, GitHub Actions** | Simulation and save tests, backend tests in the Workers runtime, native plugin tests and continuous integration. |
| Art and sound | **Godot 3D meshes, original sound effects, Fredoka and Nunito fonts** | Floating islands, spirit characters, sound effects and interface typography. |

The Android app runs the puzzle simulation locally and exchanges compact recordings
with the Worker. A Durable Object stores each room's state and coordinates turns.
RevenueCat handles purchase state, while FCM delivers turn notifications when the
other player is away. Saved recordings and downloaded photos can be replayed offline.

Dependency versions are pinned in the [Android build](native/plugin/build.gradle.kts),
[Gradle lockfile](native/plugin/gradle.lockfile) and
[backend package manifest](backend/package.json).

## Development

Open `game/project.godot` in **Godot 4.7.2 stable** to run the game on desktop.
Android builds use JDK 17, SDK 36 and the native RevenueCat plugin.

- [Android integration and build reference](native/README.md)
- [Backend API and local development](backend/README.md)
- [Automated checks](.github/workflows/verify.yml)

## How it works

- `game/core` owns the 30 Hz integer simulation, versioned islands and replay validation.
- `game/presentation` owns 3D scenery, animation and touch controls.
- `game/services` owns durable local saves, purchase integration, encrypted identity
  access and room transport.
- `native` wraps the official RevenueCat Android SDK and Android Keystore.
- `backend` uses Cloudflare Workers and SQLite Durable Objects for players, rooms,
  private photo transfers and a shared transfer-admission ledger.

Recordings contain compact actions and state checkpoints, not screen video.
Critical puzzle objects use scripted trajectories rather than unrestricted physics.
Earlier contributions are immutable; a new attempt invalidates dependent later turns.
Read [the core guide](game/core/README.md) before changing recording or simulation versions.

Online identities are anonymous. Invitation codes admit a friend to a room; recovery
codes recover the identity and must be kept private. Device credentials stay in
encrypted, non-backed-up Android storage. Identity deletion removes associated shared
rooms for both participants. It does not refund a store purchase. Local solo progress
remains on the device.

Drafts and pending submissions are saved before network requests. An uncertain request
keeps its exact body and idempotency key until a receipt is reconciled. Conflicting
recordings are preserved for review instead of silently overwriting the partner's turn.

## License

Application source is available under the [MIT license](LICENSE). External libraries,
fonts and other attributed assets retain their own licenses; retain those notices
when redistributing the app.

The original scenery and sound effects are covered by the same MIT license.
The bundled Fredoka and Nunito fonts retain their OFL
licenses. **Settings → Licenses** contains the engine, font and library notices
and is available offline.
