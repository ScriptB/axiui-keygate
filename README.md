# axiui-keygate

Universal key gate for AxiAuth. One loader, every supported game.

## Loadstring

```lua
loadstring(game:HttpGet("https://auth.833s.net/gate"))()
```

## Files

| File | Role |
|---|---|
| `UniversalKeyGate.lua` | Gate window — verifies the key via the Worker, fetches and runs the payload on success. No PlaceId → script table here; the Worker resolves it. |
| `AxiUI/` | Forked UI framework with vertical sidebar layout, header support, and proper shadow binding. |

## Adding a game

No changes to this repo needed. Everything is server-side:

```bash
# Map a PlaceId to a script
curl -X POST https://auth.833s.net/api/admin/place/map \
  -H "X-Admin-Secret: <secret>" \
  -H "Content-Type: application/json" \
  -d '{"placeId":"<PlaceId>","script":"myscript","displayName":"My Game"}'

# Upload the script source (if not already there)
curl -X POST https://auth.833s.net/api/admin/script/upload \
  -H "X-Admin-Secret: <secret>" \
  -H "Content-Type: application/json" \
  -d '{"script":"myscript","source":"<lua source>"}'
```
