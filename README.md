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
3. Map the PlaceId to that script id:
   ```bash
   curl -X POST https://finite-log-proxy.asuneteric.workers.dev/api/admin/place/map \
     -H "X-Admin-Secret: <secret>" -H "Content-Type: application/json" \
     -d '{"placeId":"<PlaceId>","script":"myscript"}'
   ```

Neither step touches this repo. **`UniversalKeyGate.lua` itself never needs to change or be pushed again for a new game** — every game/script addition is purely server-side (an upload + a place mapping). This file only changes if the loader's own behavior changes.

## Status

Both the key check and the script fetch are real — this is not a mock anymore. Nothing client-side here is a secret: no static key, no admin secret, no webhook URL. The client only ever calls the Worker's authenticated endpoints and trusts its answer, same rule every other key system in this project follows.

## Obfuscation

Left plain for now — this file holds no secret (the Worker URL is meant to be public; hitting it directly still goes through the same key check and rate limits as everyone else). Revisit with a premium obfuscator only if there's a reason to make casual reading harder, not because it changes the actual security boundary.

## Cache / versioning note

`raw.githubusercontent.com` is CDN-cached (~5 min). Append `?v=N` to a URL to bust the cache immediately, or pin a commit SHA/tag instead of `main` once this stabilizes, so a mid-edit push can't hand a half-updated file to someone loading it at that exact moment.
