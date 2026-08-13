# axiui-keygate

**THE loader every script in this project should load from** — not a per-script loader. Built on [AxiUI](https://github.com/ScriptB/Universal-Scripts/tree/main/AxiUI), backed by the real `finite-log-proxy` Cloudflare Worker (same one [`keyauth.lua`](https://github.com/ScriptB/finite-log-proxy/blob/main/public/keyauth.lua) uses — this file delegates all Worker communication to it, same as Finite does).

| File | Role |
|---|---|
| `UniversalKeyGate.lua` | Renders the key-entry window. On submit: `KeyAuth.VerifyForPlace(game.PlaceId, key)` — the Worker resolves PlaceId to a script **server-side** and checks the key against it in one call. On success: `KeyAuth.FetchScriptForPlace(game.PlaceId, key)` fetches and runs the actual payload. Never decides anything itself — the Worker does, and this file has no PlaceId → script table anywhere in it. |

There is no `scripts/` folder, no `GameDispatcher.lua`, and — as of this version — no local `ScriptMap` either. All three were retired for the same reason: anything that decides "which script for which game" client-side is either a public-URL bypass waiting to happen (`GameDispatcher.lua`) or just unnecessary duplication now that the Worker does it authoritatively (`ScriptMap`). See `Documentation/KV-Script-Hosting-Plan.md` in the main project repo for the full writeup.

## How it actually works now

```
UniversalKeyGate.lua
  → POST /api/key/verify   { key, userId, placeId }   → { valid, reason, script }
      Worker resolves place:<placeId> -> script id, checks the key against
      THAT script id -- this file never sends or knows a script id itself
  → on valid: POST /api/script/fetch   { key, userId, placeId }
      Worker re-verifies the SAME key server-side, resolves the same
      placeId -> script id again, returns its source from SCRIPTS_KV
  → client loadstring()s the response body directly
```

Both calls happen through `keyauth.lua`'s `VerifyForPlace`/`FetchScriptForPlace` — this file has zero local HTTP/JSON handling.

## Entry point

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/UniversalKeyGate.lua"
))()
```

## Setting up a new game

1. Mint or reuse a key scoped to the script id you're about to add (via the Worker's `/api/admin/generate`, `scripts: ["*"]` or a list including that id — see `finite-log-proxy`'s README).
2. Upload the script's source:
   ```bash
   curl -X POST https://finite-log-proxy.asuneteric.workers.dev/api/admin/script/upload \
     -H "X-Admin-Secret: <secret>" -H "Content-Type: application/json" \
     -d '{"script":"myscript","source":"<lua source as a JSON string>"}'
   ```
3. Map the PlaceId to that script id (optionally with a display name, shown on the Info tab):
   ```bash
   curl -X POST https://finite-log-proxy.asuneteric.workers.dev/api/admin/place/map \
     -H "X-Admin-Secret: <secret>" -H "Content-Type: application/json" \
     -d '{"placeId":"<PlaceId>","script":"myscript","displayName":"My Game"}'
   ```

Neither step touches this repo. **`UniversalKeyGate.lua` itself never needs to change or be pushed again for a new game** — every game/script addition is purely server-side (an upload + a place mapping). This file only changes if the loader's own behavior changes.

## UI — glassmorphism, left-sidebar tabs, four tabs, persistent orb

The window itself is translucent layered panels + a soft diagonal gradient sheen + a light border (`BackgroundTransparency` + `UIGradient` + `UIStroke`) — the standard way "frosted glass" gets done in Roblox UI, since there's no native per-panel background blur (`BlurEffect` only blurs the whole 3D viewport behind *all* UI, not one panel). Panel opacity (`GroupboxBgAlpha`/`ElementBgAlpha`) is calibrated well above what a typical CSS glassmorphism example uses (~35%/26%, not ~5%) — with no real blur behind it to lean on for visual structure, low-opacity panels just read as invisible in Roblox rather than "glassy."

The default AxiUI title bar's macOS-style traffic-light dots are suppressed — matched on their exact hardcoded `Size`/`Position` from AxiUI's own source, not a child-count heuristic (a first attempt at that heuristic silently never fired, since `AddList()` parents an extra `UIListLayout` into that same container, making it 4 children, not 3). A custom header sits below the title bar showing a time-of-day greeting ("Good evening, {Name}!", via `DateTime.now():ToLocalTime().Hour`) and the player's Roblox headshot (`Players:GetUserThumbnailAsync`, `Enum.ThumbnailType.HeadShot`).

**Tabs live in a left sidebar, not AxiUI's default horizontal top row.** AxiUI's tab row has a fixed horizontal `FillDirection` baked in at creation — not something a resize can turn vertical — so the default row is hidden entirely (`Window.TabRow.Visible = false`) and a genuinely separate sidebar drives the *same* underlying tab-switch state (`Window:_SelectTab(tab)`, `Window.ActiveTab`) instead of replacing it. `AddSidebarTab(name)` wraps `Window:AddTab(name)` and adds the matching sidebar button (with a letter-badge icon — plain Unicode/emoji glyphs don't reliably render in Roblox `TextLabel`s, so a colored circle + first letter is used instead, no icon-asset dependency needed).

**Benchmarked against Fluent and Rayfield's actual source** (not just impression) after the first pass read as flat/lack-luster, which surfaced four concrete gaps, all now fixed:
- **Real shadows** — every panel in both libraries has an explicit drop-shadow layer; the first pass had none. Built from stacked, progressively larger/fainter `Frame`s (not an external image asset — reusing another project's specific uploaded asset id isn't something to do casually) rather than a single flat translucent panel.
- **Animation curve/speed** — Rayfield's transitions are overwhelmingly `Enum.EasingStyle.Exponential` at 0.4–0.7s; the first pass used short Sine/Quart/Back tweens at 0.1–0.35s, which reads as an abrupt snap by comparison. Macro transitions (open/close, tab switch) now use `Enum.EasingStyle.Exponential` at ~0.4–0.5s; hover feedback stays quick (~0.15s) but on the same curve.
- **Real background blur** — Fluent's "Acrylic" effect genuinely blurs the game world behind the UI via a `DepthOfFieldEffect`, not a fake. Added the same idea (confirmed against Roblox's own `DepthOfFieldEffect` docs: small `FocusDistance` + tight `InFocusRadius`, `FarIntensity` up, `NearIntensity` at 0), toggled on only while the actual window is open — not while minimized to the floating orb, since blurring the game just to show a small orb would be intrusive.
- *(Noise/grain texture was the one gap left unaddressed — Fluent layers two tiled noise textures on its acrylic panels, but that requires a specific external image asset; skipped rather than casually reusing someone else's uploaded asset id.)*

**Tabs:**
- **License** — key entry, or once authenticated, a live `HH:MM:SS` countdown to expiry (`"Lifetime access"` for an infinite key) computed from `expiresAt` in the verify response.
- **Settings** — theme switching/customization via AxiUI's own `ThemeManager:ApplyToTab` (dropdown, rainbow accent, save/load custom), including a registered `"Glass"` theme.
- **Performance** — live FPS (`Stats.FrameTime`), ping (`Player:GetNetworkPing()`), memory (`Stats:GetTotalMemoryUsageMb()`), refreshed every second. All three are official Roblox engine APIs, not hand-rolled measurements.
- **Info** — every game currently in the library, fetched live from the Worker's public `GET /api/places/list` (no admin secret needed). Never a hardcoded list — an empty or single-entry result is shown exactly as the Worker reports it, with a manual Refresh button.

**Lifecycle:** on a valid key (fresh entry or a still-valid cached one from a prior run in *this* game — cached per-PlaceId, see `TrySilentLoad`), the License tab switches to the Authenticated/timer view, the script loads in the background, and the window closes itself with an animation — leaving a small draggable orb that reopens it later, straight into the Authenticated view (the key field is gone once authenticated, not just hidden behind a tab). A cached-key rejoin skips the window entirely — no key-entry UI is ever shown, not even briefly during the verify round-trip. A *different* game always prompts fresh, even with a valid cached key from elsewhere.

## Status

Both the key check and the script fetch are real — this is not a mock anymore. Nothing client-side here is a secret: no static key, no admin secret, no webhook URL. The client only ever calls the Worker's authenticated endpoints and trusts its answer, same rule every other key system in this project follows.

## Obfuscation

Left plain for now — this file holds no secret (the Worker URL is meant to be public; hitting it directly still goes through the same key check and rate limits as everyone else). Revisit with a premium obfuscator only if there's a reason to make casual reading harder, not because it changes the actual security boundary.

## Cache / versioning note

`raw.githubusercontent.com` is CDN-cached (~5 min). Append `?v=N` to a URL to bust the cache immediately, or pin a commit SHA/tag instead of `main` once this stabilizes, so a mid-edit push can't hand a half-updated file to someone loading it at that exact moment.
