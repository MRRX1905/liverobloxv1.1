# TikTok LIVE Interactive Stage

A Rojo-compatible Roblox experience plus a TypeScript relay. The relay normalizes public TikTok LIVE events and exposes them to Roblox over authenticated polling or newline-delimited WebStream. Roblox owns all spawn, tier, moderation, and admin decisions.

## Project layout

```text
.
├── default.project.json
├── package.json
├── tsconfig.json
├── .env.example
├── src/
│   ├── relay/
│   │   ├── config.ts
│   │   ├── events.ts
│   │   └── index.ts
│   └── roblox/
│       ├── ReplicatedStorage/
│       │   ├── Inputs/AdminConsoleContext/ToggleConsole/Keyboard/
│       │   └── LiveStageShared/Types.lua
│       ├── ServerScriptService/LiveStage/
│       │   ├── Bootstrap.server.lua
│       │   ├── AdminService.lua
│       │   ├── AnimationRegistry.lua
│       │   ├── AuraService.lua
│       │   ├── CameraService.lua
│       │   ├── ConfigService.lua
│       │   ├── DanceService.lua
│       │   ├── EventBridge.lua
│       │   ├── LaneService.lua
│       │   ├── ProfileService.lua
│       │   ├── SpawnService.lua
│       │   └── TierService.lua
│       └── ReplicatedStorage/LiveStageClient.client.lua
└── README.md
```

## Setup

1. Install Node.js 22 or newer and Rojo. From this folder, run `npm install`.
2. Set `TIKTOK_USERNAME` to the streamer handle without `@`; generate a random `RELAY_SECRET` of at least 32 characters. Keep `.env` private. A local `.env` for `shakhai1` was prepared during the Studio test.
3. Run `npm run build` to compile the relay. Use `npm run dev` while developing or `npm start` after building.
4. Host the relay on a public HTTPS endpoint. A Roblox live server cannot reach a relay at `localhost`; use a VPS, Cloudflare Tunnel, or ngrok. Set `relay.baseUrl` in the in-game Admin Console to this public URL. The default is deliberately unusable until replaced.
5. In Roblox Creator Hub, add a Secret named `TIKTOK_RELAY_SECRET` with the exact same value as `RELAY_SECRET`. Never put the secret in a LocalScript, a published ModuleScript, or the relay URL.
6. In Roblox Studio, set up a test place and run `rojo serve default.project.json` from this folder. Connect the Rojo Studio plugin, then sync the project. Check that `ReplicatedStorage/Inputs/AdminConsoleContext/ToggleConsole`, `ReplicatedStorage/LiveStageClient`, and `ServerScriptService/LiveStage/Bootstrap` appear.
7. Edit `ConfigService.lua`'s `admin.userIds` (or `admin.groupId` and `minimumGroupRank`) to include the streamer/admin account. The current test configuration whitelists the connected Studio account. Open the console with **F2** or the **LIVE STAGE** button.
8. Enable HTTP requests for the experience and allowlist the relay host in Roblox security settings. Enable Studio API access for DataStore testing. Publish the place before relying on persistent settings or animation registry saves.
9. In Studio, set `Workspace.PlayerScriptsUseInputActionSystem` to **Enabled**. The IAS action is authored under `ReplicatedStorage/Inputs`; inspect and rebind it in **Window → Input → Input Action Manager**. The visible console button also works on touch screens.

### Local mock flow

Set `MOCK_MODE=true` in `.env` and run `npm run mock`. Mock mode does not connect to TikTok and emits sample comments, Rose streaks, and a Donut. Expose the local relay through an HTTPS tunnel and use that public URL in the place, including Studio play sessions. The protected `POST /mock` endpoint can also inject one event using `x-stage-secret`; it returns 404 unless mock mode is enabled.

## Event transport

`relay.transport` is `polling` by default. The Roblox server requests `GET /events?since=<cursor>` once per second and advances the cursor only from validated batches. Set it to `webstream` to use Roblox `HttpService:CreateWebStreamClient` with the relay's authenticated `/stream` NDJSON endpoint. Both paths use the same secret header, bounded queue, and cursor behavior. The relay retries TikTok connections with exponential backoff and keeps the stage running while TikTok or the relay is offline.

The relay uses `tiktok-live-connector`, an unofficial client for TikTok's Webcast stream. TikTok may change that protocol, and the connector is distributed under AGPL-3.0-only; review its terms before distributing the relay. For streak gifts, the relay discards in-progress combo updates and only sends the final `repeatCount` when `repeatEnd` is true. Roblox then keeps per-viewer session coin totals, so 10 Roses accumulated over separate streaks can upgrade to Giant.

## Admin console and configuration

Only whitelisted user IDs or users meeting the configured group rank can call admin actions; the server checks every request. The JSON editor applies recognized settings from the selected tab and persists them in a versioned DataStore. Animation registry changes are validated, saved separately, and can be added or removed without a server restart. Roblox `ConfigService` published values are read as live defaults for selected tunables; DataStore overrides and console edits take precedence.

Gift IDs, thresholds, tier scales/durations, row capacities, reset behavior, camera, profile distance, and VFX are in `ConfigService.lua`. Adjust gift IDs against the current room gift catalog. The Rose and Donut IDs in the default config are starting examples, not a substitute for checking the stream's catalog.

## Test checklist

- In mock mode, check that a normal comment creates one NPC and later comments react without creating duplicates.
- Comment a Roblox username directly (for example `mrafiumri`) to load that avatar. Try an invalid handle to confirm the viewer still spawns with a generic avatar.
- Send one Rose: verify skip-to-front. Send ten Roses across multiple streaks: verify Giant. Send the configured King gift: verify King Giant. Confirm tiers never downgrade and Fans title remains visible.
- Confirm normal, Giant, and King rows remain ordered front-to-back; exercise per-row and global capacity, reset-all, and remove-oldest modes.
- Try `!dance`, a named `!dance`, and `!emote`; add/remove an animation from the console and confirm invalid IDs are rejected.
- In the console, check dashboard relay/viewer/character state, settings save/reset, camera modes, VFX toggle, moderation lists, test spawn, and clear stage.
- Stop the relay, reconnect it, restart the Roblox server, and confirm stage behavior, admin persistence, and event cursor recovery.
- Verify comment and profile text is filtered; confirm failed filtering hides the submitted text. Confirm appearance costs still display a fallback when private/off-sale items or marketplace calls fail.

## Operational notes

- Use one Roblox live server for a single shared stage; session gift totals are local to a Roblox server. Multi-server shared stages need cross-server coordination before launch.
- Marketplace appearance totals are best-effort, cached estimates of currently listed asset prices. Off-sale/free items and unavailable catalog data count as zero; this is not a historical purchase total.
- Creator Hub HTTP allowlists, Secrets, DataStore access, and published animation permissions are experience-specific setup requirements.
