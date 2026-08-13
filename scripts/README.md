# scripts/

Per-game payload scripts referenced by `GameDispatcher.lua`'s `ScriptMap`
(`[PlaceId] = "filename.lua"`, resolved against this folder's raw URL).

Empty until the real script library goes live — add a file here, then add
its matching `[PlaceId] = "filename.lua"` entry to `ScriptMap` in
`../GameDispatcher.lua` and push.
