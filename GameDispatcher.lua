--[[
    Game Dispatcher — PlaceId -> script mapping.
    Hosted on GitHub, fetched by UniversalKeyGate.lua after a key passes
    validation. Kept as a separate file (not embedded in the key gate) so
    the map can be updated by pushing to the repo, with no client-side
    script edits needed.

    STATUS: placeholder — ScriptMap is empty until the real library is
    populated. Shape matches the mapping table pattern already used
    elsewhere in this project's loaders (PlaceId -> filename, resolved
    against a base URL).

    Hosted at:
        https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/GameDispatcher.lua
]]

local ScriptMap = {
    -- [PlaceId] = "filename.lua",
}

local BASE_URL = "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/scripts/"

local placeId = game.PlaceId
local target  = ScriptMap[placeId]

if target then
    loadstring(game:HttpGet(BASE_URL .. target))()
else
    warn("[GameDispatcher] No script mapped for PlaceId " .. tostring(placeId))
end
