# axiui-keygate

**THE loader every script in this project should load from** — not a per-script loader. Backed by the real `finite-log-proxy` Cloudflare Worker (same one [`keyauth.lua`](https://github.com/ScriptB/finite-log-proxy/blob/main/public/keyauth.lua) uses — this file delegates all Worker communication to it, same as Finite does).

| File | Role |
|---|---|
| `UniversalKeyGate.lua` | Renders the dashboard window. On submit: `KeyAuth.VerifyForPlace(game.PlaceId, key)` — the Worker resolves PlaceId to a script **server-side** and checks the key against it in one call. On success: `KeyAuth.FetchScriptForPlace(game.PlaceId, key)` fetches and runs the actual payload. Never decides anything itself — the Worker does, and this file has no PlaceId → script table anywhere in it. |
| `AxiUI/` | A **fork** of [AxiUI](https://github.com/ScriptB/Universal-Scripts/tree/main/AxiUI), edited directly (not the shared upstream `ScriptB/Universal-Scripts` copy) to fix issues that couldn't be reasonably worked around from outside — see "Why a fork" below. |

There is no `scripts/` folder, no `GameDispatcher.lua`, and no local `ScriptMap` — anything that decides "which script for which game" client-side is either a public-URL bypass waiting to happen (`GameDispatcher.lua`) or unnecessary duplication now that the Worker does it authoritatively (`ScriptMap`). See `Documentation/KV-Script-Hosting-Plan.md` in the main project repo for the full writeup.

## How it actually works

```
UniversalKeyGate.lua
  → POST /api/key/verify   { key, userId, placeId }   → { valid, reason, script, expiresAt }
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

Neither step touches this repo. `UniversalKeyGate.lua` itself never needs to change for a new game — every addition is purely server-side.

## Why a fork, not the shared AxiUI

The window used to be built by working around AxiUI from *outside* it: hiding the built-in macOS-style title-bar dots after the fact, hand-building a whole parallel sidebar system alongside the library's own (unused, hidden) horizontal tab row, and snapshotting a drop shadow's position once at creation time. Every one of those was fragile, and one of them was the actual root cause of a real bug: **a shadow built as a one-time position/visibility snapshot has no way to know when the real window moves or hides** — it just sits there forever, exactly as reported ("shadow permanently visible no matter UI location or state").

Forking `AxiUI/` into this repo and editing it directly fixes these at the source instead of patching around them:
- **macOS dots removed entirely** from `_BuildTitleBar` — not hidden after the fact, gone.
- **Left sidebar is the framework's actual tab layout now** (`_BuildTabRow`/`_BuildContentArea` rewritten for a vertical `SidebarWidth`-wide rail; `AddTab`/`_SelectTab` rewritten for full-width rows with a built-in letter-badge icon), not a second system built alongside a hidden original.
- **`AxiUI:AddShadow(target, options)`** — a shadow wired directly to `target`'s own `Position`/`Size`/`Visible`/`AnchorPoint` via `GetPropertyChangedSignal`, so it is structurally incapable of desyncing from what it's shadowing. This is the actual fix for the permanent-shadow bug, not a patch on top of the broken version.
- **`CreateWindow` gained `HeaderHeight`/`SidebarWidth` options** so a custom header (greeting + avatar) reserves its space natively, instead of the consumer script repositioning `TabRow`/`ContentArea`/dividers by hand after the fact — the previous approach was exactly the kind of fragile, easy-to-get-subtly-wrong code that risked silently breaking the whole window.

## UI — a real dashboard, ported from an approved Superdesign draft

The layout is a direct Lua/AxiUI port of an approved design draft (Superdesign project `a5fec5c4-e974-4aa2-bd8d-b515445af6bc`, draft `3b670ab9-0f77-4b59-b00f-18d2bd4e7078`, "Optimized Compact Dashboard UI") — designed on canvas first, iterated against `Documentation/Key-System-UI-Dashboard-Spec.md`, then translated into Roblox UI primitives. Not pixel-copied where Roblox has no equivalent: no icon font, so colored circles/letters stand in for lucide icons; Settings keeps AxiUI's own real `ThemeManager` functionality rather than the mockup's illustrative, non-functional Save/Reset buttons.

Left sidebar (plain full-width text rows, no icon badge), a custom header below the title bar with a time-of-day greeting (`DateTime.now():ToLocalTime().Hour`) and the player's Roblox headshot (`Players:GetUserThumbnailAsync`, `Enum.ThumbnailType.HeadShot`), near-black glass window, and content organized as clickable **stat cards**, not a single settings-style stacked list.

**Tabs:** Dashboard, Settings, Performance, Info — kept to functional categories only. There is no separate License tab: the Authorization Overview (key entry, or once authenticated, tier + live expiry) lives directly at the top of Dashboard instead, so session/key telemetry never depends on navigating to a different tab, and the sidebar can't highlight one tab while unrelated content is on screen.

- **Dashboard** — the landing page: the Authorization Overview at top (see below), an FPS card, a resolved-game card, a performance card, and a Quick Overview panel with a jump link to Info. All cards update live as state changes elsewhere.
  - **Authorization Overview** — two states, never both visible: key entry (icon + input + Validate button), or once authenticated, a `BASIC` tier pill, a live `HH:MM:SS` countdown (`"∞"` for an infinite key, `"EXPIRED"` once it lapses) refreshed every second by a lightweight `task.spawn` loop, plus a Session Details card. Computed server-side from `expiresAt`, not client-estimated.
- **Settings** — theme switching/customization via AxiUI's own `ThemeManager:ApplyToTab`, including a registered `"Glass"` theme.
- **Performance** — FPS/ping/memory as icon rows, refreshed every second. `Stats.FrameTime`, `Player:GetNetworkPing()`, `Stats:GetTotalMemoryUsageMb()` — official Roblox engine APIs, confirmed against docs before use, not hand-rolled measurements.
- **Info** — every game currently in the library, fetched live from the Worker's public `GET /api/places/list` (no admin secret needed) — a "LIVE" tag and a copy-to-clipboard action (`setclipboard`, guarded with the same no-op fallback `keyauth.lua` uses on executors without it) per entry, with a bottom-anchored toast for copy feedback. Never a hardcoded list — an empty or single-entry result is shown exactly as the Worker reports it.

**Lifecycle:** on a valid key (fresh entry or a still-valid cached one from a prior run in *this* game — cached per-PlaceId, see `TrySilentLoad`), the Authorization Overview switches to the Authenticated/timer view, the script loads in the background, and the window closes itself with an animation — leaving a small draggable orb that reopens it later, straight into the Authenticated view (Dashboard is always the tab shown on open). A cached-key rejoin skips the window entirely, no key-entry UI ever shown, not even briefly during the verify round-trip. A *different* game always prompts fresh.

**Visual style:** translucent layered panels + a soft diagonal gradient sheen + a light border + a real drop shadow, plus a genuine background blur (`DepthOfFieldEffect`, confirmed against Roblox's own docs — small `FocusDistance`/`InFocusRadius`, `FarIntensity` up, `NearIntensity` at 0) toggled on only while the window itself is open, matching how Fluent's own "Acrylic" effect actually works — not while minimized to the orb, since blurring the game to show a small button would be intrusive. Panel opacity is calibrated well above a typical CSS glassmorphism example: there's no real blur *behind an individual panel* the way CSS relies on, so low opacity just reads as invisible in Roblox rather than "glassy." Animation timing/curve was benchmarked against Rayfield's actual source (overwhelmingly `Enum.EasingStyle.Exponential` at 0.4–0.7s) rather than the much shorter/sharper Sine/Quart/Back tweens used originally.

**Deliberately skipped:** a noise/grain texture layer (Fluent's acrylic panels have one) — it requires a specific external image asset, and reusing another project's uploaded asset id isn't something to do casually. A "Deactivate Key" button appeared in one design iteration and was explicitly removed before this port — there is no client-triggered revoke flow in the real system.

## Status

Both the key check and the script fetch are real. Nothing client-side here is a secret: no static key, no admin secret, no webhook URL. The client only ever calls the Worker's authenticated endpoints and trusts its answer, same rule every other key system in this project follows. The entire window build is wrapped in `pcall` — a future bug fails loud (one `warn()`, nothing built) instead of silently killing the whole script partway through with no explanation, which is what "UI not loading" looks like from a real user's side when nothing is defensive.

## Obfuscation

Left plain for now — this file holds no secret (the Worker URL is meant to be public; hitting it directly still goes through the same key check and rate limits as everyone else). Revisit with a premium obfuscator only if there's a reason to make casual reading harder, not because it changes the actual security boundary.

## Cache / versioning note

`raw.githubusercontent.com` is CDN-cached (~5 min). Append `?v=N` to a URL to bust the cache immediately, or pin a commit SHA/tag instead of `main` once this stabilizes, so a mid-edit push can't hand a half-updated file to someone loading it at that exact moment. This now applies to `AxiUI/AxiUI_Framework.lua` and `AxiUI_ThemeManager.lua` too, not just the loader itself.
