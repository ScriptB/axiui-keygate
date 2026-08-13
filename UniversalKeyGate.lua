--[[
    Universal Key Gate — AxiUI edition
    Renders an AxiUI key-entry window backed by the real finite-log-proxy
    Worker (https://finite-log-proxy.asuneteric.workers.dev). On success it
    fetches this game's script directly from the Worker's KV-gated
    /api/script/fetch endpoint and loadstring()s the response body — the
    payload itself is never reachable by a plain URL; the Worker independently
    re-verifies the key server-side before ever touching the KV store.

    This file never embeds a payload and never trusts a client-side check —
    every decision (is this key valid, is it valid for THIS script) is made
    by the Worker, the same way keyauth.lua (this project's existing Fluent-
    based key client) already does it. This is the same pattern, same
    Worker, just with AxiUI's look instead of Fluent's, plus the KV script
    fetch step keyauth.lua doesn't need (Finite.lua distributes differently).

    See Documentation/KV-Script-Hosting-Plan.md for the full architecture.

    Load:
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/UniversalKeyGate.lua"
        ))()
]]

-- ══════════════════════════════════════════════════════════════
--  LOAD AXIUI
-- ══════════════════════════════════════════════════════════════
local AXIUI_BASE = "https://raw.githubusercontent.com/ScriptB/Universal-Scripts/main/AxiUI/"

local AxiUI = loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_Framework.lua"))()
loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_ThemeManager.lua"))()

local Players     = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenSvc    = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer

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

-- ══════════════════════════════════════════════════════════════
--  1. INITIALIZATION — current Game ID
-- ══════════════════════════════════════════════════════════════
local PlaceId = game.PlaceId

-- ══════════════════════════════════════════════════════════════
--  2. SCRIPT LIBRARY — PlaceId -> script id. This mapping is NOT
--  sensitive (it only says "this game runs the script named X"); the
--  actual protected content lives server-side in SCRIPTS_KV, keyed by
--  the same script id, and is never served without a valid key for it.
--  This replaces the old GameDispatcher.lua (retired — it was a plain
--  public GitHub file, which defeated the point of a key gate).
-- ══════════════════════════════════════════════════════════════
local ScriptMap = {
    -- [PlaceId] = "script-id",   -- script-id must match a key's `scripts`
    --                               list on the Worker (or the key must be
    --                               scoped "*") and a SCRIPTS_KV entry
    --                               uploaded via /api/admin/script/upload.
}

-- ══════════════════════════════════════════════════════════════
--  3. WORKER — real key verify + KV-gated script fetch. Same Worker
--  keyauth.lua already uses; both endpoints re-check the key
--  server-side, this file holds no secret and makes no local decision.
-- ══════════════════════════════════════════════════════════════
local WORKER_BASE = "https://finite-log-proxy.asuneteric.workers.dev"
local VERIFY_URL  = WORKER_BASE .. "/api/key/verify"
local FETCH_URL   = WORKER_BASE .. "/api/script/fetch"

-- Executors expose their own HTTP bypass under different names (and plain
-- HttpService:RequestAsync is still bound by the game's domain allowlist on
-- some of them) -- prefer the executor's own request function when present,
-- same fallback chain keyauth.lua uses.
local HttpRequest = syn and syn.request or http_request or request or (fluxus and fluxus.request) or (http and http.request) or nil

local function PostJSON(url, jsonBody)
    if HttpRequest then
        local ok, res = pcall(HttpRequest, {
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonBody,
        })
        if not ok then return false, nil, tostring(res) end
        local status = res and (res.StatusCode or res.Status)
        return (type(status) == "number" and status >= 200 and status < 300), status, res and res.Body
    end

    local ok, res = pcall(function()
        return HttpService:RequestAsync({
            Url = url,
            Method = "POST",
            Headers = { ["Content-Type"] = "application/json" },
            Body = jsonBody,
        })
    end)
    if not ok then return false, nil, tostring(res) end
    return res.Success == true, res.StatusCode, res.Body
end

-- Pasting into a Roblox TextBox commonly drags in invisible characters
-- (trailing newline, stray spaces, zero-width space U+200B) that don't show
-- visually but would otherwise get sent as part of the key.
local function CleanKey(s)
    s = tostring(s or "")
    s = s:gsub("\226\128\139", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

-- Returns valid(bool), reason-or-nil. Server-authoritative: this never
-- decides validity itself, only relays what the Worker said.
local function ValidateKey(key, scriptId)
    local _, status, body = PostJSON(VERIFY_URL, HttpService:JSONEncode({
        key    = key,
        userId = tostring(LocalPlayer.UserId),
        script = scriptId,
    }))
    if body then
        local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
        if ok and type(data) == "table" and data.valid ~= nil then
            return data.valid == true, data.reason
        end
    end
    return false, "Could not reach the key server (HTTP " .. tostring(status) .. ")."
end

-- Fetches the actual protected payload. The Worker independently re-runs
-- the same key check ValidateKey above triggered -- this call cannot
-- succeed with a key that failed (or was never sent through) that check.
-- Returns ok(bool), sourceOrReason(string).
local function FetchScript(key, scriptId)
    local ok, status, body = PostJSON(FETCH_URL, HttpService:JSONEncode({
        key    = key,
        userId = tostring(LocalPlayer.UserId),
        script = scriptId,
    }))
    if ok and body then
        return true, body
    end
    if body then
        local decodeOk, data = pcall(function() return HttpService:JSONDecode(body) end)
        if decodeOk and type(data) == "table" and (data.error or data.reason) then
            return false, tostring(data.error or data.reason)
        end
        -- 404 body from /api/script/fetch is plain text, not JSON.
        return false, tostring(body)
    end
    return false, "Could not reach the script server (HTTP " .. tostring(status) .. ")."
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

local ScriptId = ScriptMap[PlaceId]

local StatusLabel = Box:AddLabel(
    ScriptId
        and ("Game ID " .. tostring(PlaceId) .. " — matched to \"" .. ScriptId .. "\".")
        or ("Game ID " .. tostring(PlaceId) .. " — not yet in the library."),
    { Color = AxiUI.Theme.TextMuted }
)

local KeyInput = Box:AddInput("KeyInput", {
    Text        = "License Key",
    Placeholder = "Enter your key",
})

local ValidateBtn = Box:AddButton({ Text = "Validate" })

-- ══════════════════════════════════════════════════════════════
--  4. KEY VALIDATION — submit, animate, resolve
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
    local ok, source = FetchScript(key, ScriptId)
    if not ok then
        warn("[UniversalKeyGate] Script fetch failed: " .. tostring(source))
        return
    end
    local runOk, err = pcall(function()
        loadstring(source)()
    end)
    if not runOk then
        warn("[UniversalKeyGate] Script exec failed: " .. tostring(err))
    end
end

local function SubmitKey()
    if validating then return end

    if not ScriptId then
        StatusLabel.Text = "This game isn't in the library yet — nothing to load."
        StatusLabel.TextColor3 = FLAT_ERROR
        Shake(Window.Frame)
        return
    end

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

    local ok, reason = ValidateKey(key, ScriptId)

    validating = false
    if ok then
        ValidateBtn.Button.Text = "Validated"
        StatusLabel.Text = "Access granted."
        StatusLabel.TextColor3 = FLAT_SUCCESS
        AxiUI:Notify("Access", "Key accepted.", 2)
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
--  5. ENTRANCE ANIMATION
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
