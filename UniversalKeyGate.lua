--[[
    Universal Key Gate — AxiUI edition

    THE loader every script (Finite included) should load from — not a
    per-script loader. Enter a key, and the finite-log-proxy Worker (1)
    checks the key, (2) resolves game.PlaceId to whichever script that game
    maps to, (3) returns that script only if the key is valid for it. No
    PlaceId -> script table exists anywhere in this file, or in any client
    code at all — that mapping lives entirely server-side (SCRIPTS_KV's
    "place:<PlaceId>" entries, set via POST /api/admin/place/map). A future
    game/script needs zero changes here; just a new place mapping + a
    SCRIPTS_KV upload on the Worker side.

    All Worker communication is delegated to the shared keyauth.lua module
    (same one Finite uses) via KeyAuth.VerifyForPlace / FetchScriptForPlace
    — this file only builds the AxiUI window around it. No local HTTP
    bridge, no local JSON handling, no local validity decision: every
    "is this allowed" answer comes from the Worker.

    A key that already validated for THIS game is cached per-PlaceId (via
    KeyAuth.SaveCachedKey/LoadCachedKey) — rejoining the same game with a
    still-valid key skips this UI entirely and loads straight through.
    Joining a DIFFERENT game always prompts once, even with an existing
    cached key from elsewhere, since the cache file is namespaced per
    PlaceId on purpose (see TrySilentLoad below).

    See Documentation/KV-Script-Hosting-Plan.md for the full architecture.

    Load:
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/UniversalKeyGate.lua"
        ))()
]]

local Players     = game:GetService("Players")
local TweenSvc    = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

-- ══════════════════════════════════════════════════════════════
--  LOAD KEYAUTH — shared Worker-communication module. Loaded before AxiUI
--  so a still-valid cached key can skip straight to loading without ever
--  building a window at all.
-- ══════════════════════════════════════════════════════════════
local KEYAUTH_MODULE_URL = "https://finite-log-proxy.asuneteric.workers.dev/keyauth.lua"

local KeyAuth = loadstring(game:HttpGet(KEYAUTH_MODULE_URL))()
if type(KeyAuth) ~= "table"
    or type(KeyAuth.VerifyForPlace) ~= "function"
    or type(KeyAuth.FetchScriptForPlace) ~= "function"
    or type(KeyAuth.LoadCachedKey) ~= "function"
    or type(KeyAuth.SaveCachedKey) ~= "function"
then
    warn("[UniversalKeyGate] Failed to load KeyAuth module from " .. KEYAUTH_MODULE_URL .. " -- aborting")
    return
end

local PlaceId = game.PlaceId

-- Namespaced per-PlaceId (not global) so returning to an already-validated
-- game skips this UI entirely, but a new game still prompts once -- even
-- though the same underlying key would likely work there too (keys are
-- usually scoped "*"), that first-time prompt per game is deliberate.
local CACHE_FILE = "universalkeygate_place_" .. tostring(PlaceId) .. ".json"

local function RunPayload(source)
    local runOk, err = pcall(function()
        loadstring(source)()
    end)
    if not runOk then
        warn("[UniversalKeyGate] Script exec failed: " .. tostring(err))
    end
end

-- Silent path: a cached key from a previous validated run in THIS exact
-- game, still valid right now. Returns true if it successfully loaded
-- (caller should stop here, no UI needed) -- false means fall through to
-- the normal AxiUI gate window (no cache, wrong account, expired/revoked,
-- or this game's mapping changed since the cache was written).
local function TrySilentLoad()
    local cachedKey, cachedUserId = KeyAuth.LoadCachedKey(CACHE_FILE)
    if not cachedKey or cachedUserId ~= tostring(LocalPlayer.UserId) then
        return false
    end

    local ok = KeyAuth.VerifyForPlace(PlaceId, cachedKey)
    if not ok then
        return false
    end

    local fetchOk, payload = KeyAuth.FetchScriptForPlace(PlaceId, cachedKey)
    if not fetchOk then
        warn("[UniversalKeyGate] Cached-key script fetch failed: " .. tostring(payload))
        return false
    end

    RunPayload(payload)
    return true
end

if TrySilentLoad() then
    return
end

-- ══════════════════════════════════════════════════════════════
--  LOAD AXIUI — only reached if the silent path above didn't apply.
-- ══════════════════════════════════════════════════════════════
local AXIUI_BASE = "https://raw.githubusercontent.com/ScriptB/Universal-Scripts/main/AxiUI/"

local AxiUI = loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_Framework.lua"))()
loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_ThemeManager.lua"))()

-- ══════════════════════════════════════════════════════════════
--  FLAT, SOLID THEME  (no gradients, no glow, no neon purple/blue/green)
-- ══════════════════════════════════════════════════════════════
AxiUI:SetTheme({
    WindowBg        = Color3.fromRGB(26,  24,  22),   WindowBgAlpha   = 1,
    GroupboxBg      = Color3.fromRGB(255, 255, 255),   GroupboxBgAlpha = 0.045,
    ElementBg       = Color3.fromRGB(255, 255, 255),   ElementBgAlpha  = 0.035,
    Accent          = Color3.fromRGB(196, 158, 92),    AccentAlpha     = 0.4,
    AccentStrong    = Color3.fromRGB(214, 180, 122),
    Border          = Color3.fromRGB(255, 255, 255),   BorderAlpha     = 0.09,
    TextPrimary     = Color3.fromRGB(236, 231, 224),
    TextSecondary   = Color3.fromRGB(158, 151, 142),
    TextMuted       = Color3.fromRGB(96,  90,  83),
})

local FLAT_SUCCESS = Color3.fromRGB(126, 158, 110)
local FLAT_ERROR    = Color3.fromRGB(196, 96,  84)

-- Pasting into a Roblox TextBox commonly drags in invisible characters
-- (trailing newline, stray spaces, zero-width space U+200B) that don't show
-- visually but would otherwise get sent as part of the key.
local function CleanKey(s)
    s = tostring(s or "")
    s = s:gsub("\226\128\139", "") -- zero-width space (U+200B)
    -- Strip whitespace ANYWHERE, not just at the ends -- a real key is a
    -- plain dash-separated hex string and never legitimately contains
    -- whitespace, so this is safe, and it's what actually catches a hidden
    -- line break from a source that word-wrapped the key when it was
    -- copied (trim-only misses this: it only strips at the string's ends).
    s = s:gsub("%s+", "")
    return s
end

-- ══════════════════════════════════════════════════════════════
--  WINDOW
-- ══════════════════════════════════════════════════════════════
local Window = AxiUI:CreateWindow({
    Title  = "Access",
    Width  = 360,
    Height = 250,
})

do
    local vp = workspace.CurrentCamera.ViewportSize
    Window.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
    Window.Frame.Position    = UDim2.fromOffset(vp.X / 2, vp.Y / 2)
end

local Tab = Window:AddTab("License")
local Box = Tab:AddGroupbox("Authentication")

local StatusLabel = Box:AddLabel(
    "Game ID " .. tostring(PlaceId) .. " — press Validate to check the library.",
    { Color = AxiUI.Theme.TextMuted }
)

local KeyInput = Box:AddInput("KeyInput", {
    Text        = "License Key",
    Placeholder = "Enter your key",
})

local ValidateBtn = Box:AddButton({ Text = "Validate" })

-- ══════════════════════════════════════════════════════════════
--  KEY VALIDATION — submit, animate, resolve
-- ══════════════════════════════════════════════════════════════
local validating = false

local function Shake(frame)
    local base = frame.Position
    local seq = {
        base + UDim2.fromOffset(-8, 0), base + UDim2.fromOffset(8, 0),
        base + UDim2.fromOffset(-5, 0), base + UDim2.fromOffset(5, 0), base,
    }
    for _, pos in ipairs(seq) do
        TweenSvc:Create(frame, TweenInfo.new(0.05, Enum.EasingStyle.Sine), { Position = pos }):Play()
        task.wait(0.05)
    end
end

local function PlayExit(onDone)
    local frame = Window.Frame
    TweenSvc:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(frame.Size.X.Offset * 0.9, frame.Size.Y.Offset * 0.9),
        BackgroundTransparency = 1,
    }):Play()
    task.delay(0.26, function()
        Window.Gui:Destroy()
        if onDone then onDone() end
    end)
end

local function OnLoadStage(key)
    local ok, source = KeyAuth.FetchScriptForPlace(PlaceId, key)
    if not ok then
        warn("[UniversalKeyGate] Script fetch failed: " .. tostring(source))
        return
    end
    RunPayload(source)
end

local function SubmitKey()
    if validating then return end

    local key = CleanKey(AxiUI.Flags["KeyInput"])
    if key == "" then
        StatusLabel.Text = "Enter a key first."
        StatusLabel.TextColor3 = FLAT_ERROR
        Shake(Window.Frame)
        return
    end

    validating = true
    ValidateBtn.Button.Text = "Validating..."
    StatusLabel.Text = "Checking key..."
    StatusLabel.TextColor3 = AxiUI.Theme.TextMuted

    -- The Worker does everything here: is this key valid, is it valid for
    -- THIS game (resolved from PlaceId, not anything this file knows), all
    -- in one call. `resolvedScript` is purely for the status message below.
    local ok, reason, resolvedScript = KeyAuth.VerifyForPlace(PlaceId, key)

    validating = false
    if ok then
        ValidateBtn.Button.Text = "Validated"
        StatusLabel.Text = "Access granted" .. (resolvedScript and (" — \"" .. resolvedScript .. "\".") or ".")
        StatusLabel.TextColor3 = FLAT_SUCCESS
        AxiUI:Notify("Access", "Key accepted.", 2)
        -- Cached per-PlaceId -- a future run in THIS game will skip this
        -- whole UI via TrySilentLoad above, as long as this key is still
        -- valid then. A different game still prompts fresh.
        KeyAuth.SaveCachedKey(CACHE_FILE, key)
        task.wait(0.4)
        PlayExit(function() OnLoadStage(key) end)
    else
        ValidateBtn.Button.Text = "Validate"
        StatusLabel.Text = reason or "Invalid key — try again."
        StatusLabel.TextColor3 = FLAT_ERROR
        Shake(Window.Frame)
    end
end

ValidateBtn.Button.MouseButton1Click:Connect(SubmitKey)

-- ══════════════════════════════════════════════════════════════
--  ENTRANCE ANIMATION
-- ══════════════════════════════════════════════════════════════
do
    local frame = Window.Frame
    local targetSize  = frame.Size
    local targetAlpha = frame.BackgroundTransparency

    frame.Size = UDim2.fromOffset(targetSize.X.Offset * 0.85, targetSize.Y.Offset * 0.85)
    frame.BackgroundTransparency = 1

    TweenSvc:Create(frame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = targetSize,
        BackgroundTransparency = targetAlpha,
    }):Play()
end
