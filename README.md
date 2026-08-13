# axiui-keygate

Two-file key-gate + dispatcher pair, built on [AxiUI](https://github.com/ScriptB/Universal-Scripts/tree/main/AxiUI).

| File | Role |
|---|---|
| `UniversalKeyGate.lua` | Renders the key-entry window, runs `ValidateKey`, and on success hands off to the dispatcher. Never decides what gets loaded. |
| `GameDispatcher.lua` | Owns the `PlaceId -> script` map. Fetched and executed only after a key validates. |
| `scripts/` | Per-game payload files referenced by `GameDispatcher.lua`'s map. Empty for now. |

## Entry point

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/UniversalKeyGate.lua"
))()
```

## Current status — both files are placeholders

- `UniversalKeyGate.lua`'s `ValidateKey` is `MockValidateKey` (accepts any 6+ char string). Swap the single `ValidateKey` assignment for a real backend call when ready — no other code needs to change.
- `GameDispatcher.lua`'s `ScriptMap` is empty. Add entries as `[PlaceId] = "filename.lua"`, drop the matching file in `scripts/`, push.
- Neither file contains a secret. If a real validator is wired in, keep the same rule the rest of this project's key systems follow: no static key, no admin secret, no webhook URL client-side — the client only ever calls an authenticated backend endpoint and trusts its answer.

## Obfuscation

Left plain on purpose. Nothing client-side here is a secret yet (mock validator, empty map), so obfuscating placeholder code would only make it harder to keep editing. Revisit once the real validation call and a populated `ScriptMap` are actually going out to end users — plan is to run it through a premium obfuscator at that point, not before.

## Cache / versioning note

`raw.githubusercontent.com` is CDN-cached (~5 min). Append `?v=N` to a URL to bust the cache immediately, or pin a commit SHA/tag instead of `main` once this stabilizes, so a mid-edit push can't hand a half-updated file to someone loading it at that exact moment.
