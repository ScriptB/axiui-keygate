# axiui-keygate

A single-file key-gate, built on [AxiUI](https://github.com/ScriptB/Universal-Scripts/tree/main/AxiUI), backed by the real `finite-log-proxy` Cloudflare Worker (the same one [`keyauth.lua`](https://github.com/ScriptB/finite-log-proxy/blob/main/public/keyauth.lua) uses, just with AxiUI's look instead of Fluent's).

| File | Role |
|---|---|
| `UniversalKeyGate.lua` | Renders the key-entry window, verifies the key against the Worker's `/api/key/verify`, and on success fetches the actual protected script from the Worker's `/api/script/fetch` and runs it. Never decides validity itself — the Worker does. |

There is no `scripts/` folder and no `GameDispatcher.lua` here — those were retired. A plain GitHub-hosted "dispatcher" file that gets fetched and run after a key check is a dead end: anyone who has its URL can `game:HttpGet` + `loadstring` it directly and skip the key check entirely, the same way `raw.githubusercontent.com` payloads always can. See `Documentation/KV-Script-Hosting-Plan.md` in the main project repo for the full writeup of why this moved server-side.

## How it actually works now

```
UniversalKeyGate.lua
  → POST /api/key/verify   { key, userId, script }   → { valid, reason }
  → on valid: POST /api/script/fetch   { key, userId, script }
      Worker re-verifies the SAME key server-side, looks up the script
      in a KV namespace no plain URL can reach, returns its source
  → client loadstring()s the response body directly
```

`script` here is a small identifier (e.g. `"myscript"`) — not the PlaceId itself. `UniversalKeyGate.lua`'s local `ScriptMap` table maps `PlaceId -> script id`; that mapping is not sensitive (it only says "this game runs the script named X"), only the script *source* is protected, and that never touches GitHub or any plain URL.

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
3. Add `[PlaceId] = "myscript"` to `ScriptMap` in `UniversalKeyGate.lua`, commit, push.

No `git push` is needed to update the script itself going forward — only step 2 (a KV write) is required to change what a game actually loads. `ScriptMap` only needs a push when a *new* game is added.

## Status

Both the key check and the script fetch are real — this is not a mock anymore. Nothing client-side here is a secret: no static key, no admin secret, no webhook URL. The client only ever calls the Worker's authenticated endpoints and trusts its answer, same rule every other key system in this project follows.

## Obfuscation

Left plain for now — this file holds no secret (the Worker URL is meant to be public; hitting it directly still goes through the same key check and rate limits as everyone else). Revisit with a premium obfuscator only if there's a reason to make casual reading harder, not because it changes the actual security boundary.

## Cache / versioning note

`raw.githubusercontent.com` is CDN-cached (~5 min). Append `?v=N` to a URL to bust the cache immediately, or pin a commit SHA/tag instead of `main` once this stabilizes, so a mid-edit push can't hand a half-updated file to someone loading it at that exact moment.
