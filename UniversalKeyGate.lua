--[[
    Universal Key Gate — Glassmorphism edition

    THE loader every script (Finite included) should load from — not a
    per-script loader. Enter a key, and the finite-log-proxy Worker (1)
    checks the key, (2) resolves game.PlaceId to whichever script that game
    maps to, (3) returns that script only if the key is valid for it. No
    PlaceId -> script table exists anywhere in this file, or in any client
    code at all — that mapping lives entirely server-side.

    All Worker communication is delegated to the shared keyauth.lua module
    — this file only builds the AxiUI window around it. No local HTTP
    bridge, no local JSON handling, no local validity decision.

    Lifecycle: on a valid key (fresh entry OR a still-valid cached one from
    a previous run in THIS game), the License tab switches from the key
    field to an "Authenticated" state with a live expiry countdown, the
    script loads in the background, and the window closes itself with an
    animation — leaving a small draggable orb behind that reopens it. A
    still-valid cached key skips straight to that closed/orb state with no
    key-entry UI ever shown. A DIFFERENT game always prompts fresh, even
    with a valid cached key from elsewhere (see TrySilentLoad).

    Visual style: glassmorphism (translucent layered panels, soft gradient
    sheen, light border) via BackgroundTransparency + UIGradient + UIStroke
    — Roblox has no native per-panel background blur (BlurEffect only
    blurs the whole 3D viewport behind ALL UI), so "frosted glass" here
    means the same layered-transparency technique every Roblox UI library
    uses for this look, not literal optical blur.

    Reference: only AxiUI/ from ScriptB/Universal-Scripts was read for
    component/styling reference, per instruction — no other part of that
    repo was browsed.

    See Documentation/KV-Script-Hosting-Plan.md for the full architecture.

    Load:
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/UniversalKeyGate.lua"
        ))()
]]

local Players     = game:GetService("Players")
local TweenSvc     = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local StatsSvc     = game:GetService("Stats")
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
    or type(KeyAuth.ListPlaces) ~= "function"
then
    warn("[UniversalKeyGate] Failed to load KeyAuth module from " .. KEYAUTH_MODULE_URL .. " -- aborting")
    return
end

local PlaceId = game.PlaceId

-- Namespaced per-PlaceId (not global) so returning to an already-validated
-- game skips this UI entirely, but a new game still prompts once.
local CACHE_FILE = "universalkeygate_place_" .. tostring(PlaceId) .. ".json"

local function RunPayload(source)
    local runOk, err = pcall(function()
        loadstring(source)()
    end)
    if not runOk then
        warn("[UniversalKeyGate] Script exec failed: " .. tostring(err))
    end
end

-- ══════════════════════════════════════════════════════════════
--  LOAD AXIUI + THEME
-- ══════════════════════════════════════════════════════════════
local AXIUI_BASE = "https://raw.githubusercontent.com/ScriptB/Universal-Scripts/main/AxiUI/"

local AxiUI = loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_Framework.lua"))()
local ThemeManager = loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_ThemeManager.lua"))()

-- Structural glass properties -- NOT part of ThemeManager's swappable key
-- set (it only swaps WindowBg/Accent/AccentStrong/Text*), these are the
-- fixed "this is a glass panel" look: heavy transparency, a light border,
-- tight corners. Any theme picked in Settings still layers on top of this.
AxiUI:SetTheme({
    GroupboxBg      = Color3.fromRGB(255, 255, 255),  GroupboxBgAlpha = 0.055,
    ElementBg       = Color3.fromRGB(255, 255, 255),  ElementBgAlpha  = 0.045,
    Border          = Color3.fromRGB(255, 255, 255),  BorderAlpha     = 0.14,
})

-- Registered as a selectable theme (not just AxiUI:SetTheme'd directly) so
-- it shows up in the Settings tab's theme dropdown alongside the built-ins,
-- and switching away from it and back still works correctly.
ThemeManager:AddTheme("Glass", {
    WindowBg      = Color3.fromRGB(20,  24,  32),   WindowBgAlpha  = 0.70,
    Accent        = Color3.fromRGB(150, 178, 205),  AccentAlpha    = 0.30,
    AccentStrong  = Color3.fromRGB(200, 220, 238),
    TextPrimary   = Color3.fromRGB(240, 244, 248),
    TextSecondary = Color3.fromRGB(172, 183, 197),
    TextMuted     = Color3.fromRGB(112, 122, 138),
})
ThemeManager:Apply("Glass")

local T = AxiUI.Theme

-- ══════════════════════════════════════════════════════════════
--  WINDOW
-- ══════════════════════════════════════════════════════════════
local WIDTH      = 460
local BASE_HEIGHT = 520   -- content height AxiUI lays out under its own title(34)+tabrow(30) formula
local HEADER_H    = 64    -- extra row inserted below the title bar for greeting + avatar

local Window = AxiUI:CreateWindow({
    Title  = "Access",
    Width  = WIDTH,
    Height = BASE_HEIGHT,
})

-- Grow the frame to make room for the custom header WITHOUT shrinking the
-- content area AxiUI already laid out -- then recenter using the same
-- formula CreateWindow used, since the size just changed out from under it.
do
    local vp = workspace.CurrentCamera.ViewportSize
    local newHeight = BASE_HEIGHT + HEADER_H
    Window.Frame.Size = UDim2.fromOffset(WIDTH, newHeight)
    Window.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
    Window.Frame.Position    = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2))
end

-- Subtle diagonal glass sheen -- a soft light streak across the panel,
-- heavily transparent. This plus the layered BackgroundTransparency +
-- UIStroke border is the actual "frosted glass" look; there is no true
-- background blur to add on top of it (see file header).
do
    local sheen = Instance.new("UIGradient")
    sheen.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(190, 205, 220)),
    })
    sheen.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.93),
        NumberSequenceKeypoint.new(0.5, 0.985),
        NumberSequenceKeypoint.new(1,   0.93),
    })
    sheen.Rotation = 105
    sheen.Parent = Window.Frame
end

-- Suppress the macOS-style traffic-light dots the default title bar always
-- adds (no exposed option to disable them at CreateWindow) -- explicitly
-- not the aesthetic asked for. They're the only Frame child of TitleBar
-- with exactly 3 children (the 3 dots); nothing else in the title bar
-- matches that shape, so this is a safe, specific heuristic rather than a
-- fragile positional guess.
for _, child in ipairs(Window.TitleBar:GetChildren()) do
    if child:IsA("Frame") and #child:GetChildren() == 3 then
        child.Visible = false
    end
end

-- Reposition the tab row / its divider / the content area down by
-- HEADER_H to make room for the custom header between the title bar and
-- the tabs. TabRow and ContentArea are both exposed on the window object;
-- the tab row's bottom divider is named "TabRowDivider" specifically so it
-- can be found and moved the same way (everything else inside TabRow is
-- unnamed/positional and left alone).
Window.TabRow.Position = UDim2.fromOffset(0, 34 + HEADER_H)
local tabRowDivider = Window.Frame:FindFirstChild("TabRowDivider")
if tabRowDivider then
    tabRowDivider.Position = UDim2.new(0, 0, 0, 34 + HEADER_H + 30 - 1)
end
Window.ContentArea.Position = UDim2.fromOffset(0, 34 + HEADER_H + 30)
Window.ContentArea.Size     = UDim2.new(1, 0, 1, -(34 + HEADER_H + 30))

-- ══════════════════════════════════════════════════════════════
--  CUSTOM HEADER — avatar + time-of-day greeting
-- ══════════════════════════════════════════════════════════════
local function GetGreeting()
    local hour = DateTime.now():ToLocalTime().Hour
    local part
    if hour < 5 then part = "Good night"
    elseif hour < 12 then part = "Good morning"
    elseif hour < 17 then part = "Good afternoon"
    elseif hour < 22 then part = "Good evening"
    else part = "Good night" end
    return part .. ", " .. LocalPlayer.DisplayName .. "!"
end

local HeaderRow = Instance.new("Frame")
HeaderRow.Name                   = "Header"
HeaderRow.Size                   = UDim2.new(1, 0, 0, HEADER_H)
HeaderRow.Position               = UDim2.fromOffset(0, 34)
HeaderRow.BackgroundTransparency = 1
HeaderRow.BorderSizePixel        = 0
HeaderRow.Parent                 = Window.Frame

local headerDiv = Instance.new("Frame")
headerDiv.Size                   = UDim2.new(1, 0, 0, 1)
headerDiv.Position               = UDim2.new(0, 0, 1, -1)
headerDiv.BackgroundColor3       = T.Border
headerDiv.BackgroundTransparency = 1 - T.BorderAlpha
headerDiv.BorderSizePixel        = 0
headerDiv.Parent                 = HeaderRow

local AVATAR_SIZE = 44
local AvatarImg = Instance.new("ImageLabel")
AvatarImg.Name                  = "Avatar"
AvatarImg.Size                  = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
AvatarImg.Position              = UDim2.fromOffset(14, (HEADER_H - AVATAR_SIZE) / 2)
AvatarImg.BackgroundColor3      = Color3.fromRGB(255, 255, 255)
AvatarImg.BackgroundTransparency = 0.9
AvatarImg.BorderSizePixel       = 0
AvatarImg.Image                 = ""
AvatarImg.ScaleType             = Enum.ScaleType.Crop
AvatarImg.Parent                = HeaderRow
do
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(1, 0)
    c.Parent = AvatarImg
    local s = Instance.new("UIStroke")
    s.Color = T.Border
    s.Transparency = 1 - T.BorderAlpha
    s.Thickness = 1
    s.Parent = AvatarImg
end

-- GetUserThumbnailAsync yields, so this runs on its own thread rather than
-- blocking window construction. content is a rbxthumb:// content id,
-- assignable straight to Image.
task.spawn(function()
    local ok, content = pcall(function()
        return Players:GetUserThumbnailAsync(
            LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
    end)
    if ok and content and content ~= "" then
        AvatarImg.Image = content
    end
end)

local GreetingLbl = Instance.new("TextLabel")
GreetingLbl.Size                   = UDim2.new(1, -(14 + AVATAR_SIZE + 12 + 12), 0, 18)
GreetingLbl.Position               = UDim2.fromOffset(14 + AVATAR_SIZE + 12, HEADER_H / 2 - 19)
GreetingLbl.BackgroundTransparency = 1
GreetingLbl.Font                   = Enum.Font.GothamBold
GreetingLbl.TextSize               = 14
GreetingLbl.TextColor3             = T.TextPrimary
GreetingLbl.TextXAlignment         = Enum.TextXAlignment.Left
GreetingLbl.TextTruncate           = Enum.TextTruncate.AtEnd
GreetingLbl.Text                   = GetGreeting()
GreetingLbl.Parent                 = HeaderRow

local SubLbl = Instance.new("TextLabel")
SubLbl.Size                   = GreetingLbl.Size
SubLbl.Position               = UDim2.fromOffset(14 + AVATAR_SIZE + 12, HEADER_H / 2 + 2)
SubLbl.BackgroundTransparency = 1
SubLbl.Font                   = Enum.Font.Gotham
SubLbl.TextSize               = 11
SubLbl.TextColor3             = T.TextMuted
SubLbl.TextXAlignment         = Enum.TextXAlignment.Left
SubLbl.TextTruncate           = Enum.TextTruncate.AtEnd
SubLbl.Text                   = "Game ID " .. tostring(PlaceId)
SubLbl.Parent                 = HeaderRow

-- ══════════════════════════════════════════════════════════════
--  LICENSE TAB — two states: key entry, or authenticated + live expiry
-- ══════════════════════════════════════════════════════════════
local TabLicense = Window:AddTab("License")

local EntryBox = TabLicense:AddGroupbox("Authentication")
local StatusLabel = EntryBox:AddLabel(
    "Press Validate to check the library.",
    { Color = T.TextMuted }
)
local KeyInput = EntryBox:AddInput("KeyInput", {
    Text        = "License Key",
    Placeholder = "Enter your key",
})
local ValidateBtn = EntryBox:AddButton({ Text = "Validate" })

local AuthedBox = TabLicense:AddGroupbox("Authentication")
AuthedBox.Container.Visible = false
local AuthedStatusLabel = AuthedBox:AddLabel("Authenticated", { Color = Color3.fromRGB(126, 190, 150) })
local AuthedTimerLabel  = AuthedBox:AddLabel("", { Color = T.TextSecondary })

-- Pasting into a Roblox TextBox commonly drags in invisible characters
-- (trailing newline, stray spaces, zero-width space U+200B) that don't show
-- visually but would otherwise get sent as part of the key.
local function CleanKey(s)
    s = tostring(s or "")
    s = s:gsub("\226\128\139", "") -- zero-width space (U+200B)
    s = s:gsub("%s+", "")
    return s
end

local timerThread = nil
local function StopTimer()
    if timerThread then
        task.cancel(timerThread)
        timerThread = nil
    end
end

local function FormatRemaining(msRemaining)
    if msRemaining <= 0 then return "Expired" end
    local totalSeconds = math.floor(msRemaining / 1000)
    local h = math.floor(totalSeconds / 3600)
    local m = math.floor((totalSeconds % 3600) / 60)
    local s = totalSeconds % 60
    return string.format("Expires in %02d:%02d:%02d", h, m, s)
end

local function StartTimer(expiresAt)
    StopTimer()
    if expiresAt == nil then
        AuthedTimerLabel.Text = "Lifetime access — never expires."
        return
    end
    timerThread = task.spawn(function()
        while true do
            local remaining = expiresAt - DateTime.now().UnixTimestampMillis
            AuthedTimerLabel.Text = FormatRemaining(remaining)
            if remaining <= 0 then break end
            task.wait(1)
        end
    end)
end

local function ShowAuthenticatedState(resolvedScript, expiresAt)
    EntryBox.Container.Visible  = false
    AuthedBox.Container.Visible = true
    AuthedStatusLabel.Text = resolvedScript
        and ("Authenticated — \"" .. resolvedScript .. "\".")
        or "Authenticated."
    StartTimer(expiresAt)
end

-- ══════════════════════════════════════════════════════════════
--  SETTINGS TAB — theme management comes almost entirely from AxiUI's own
--  ThemeManager (dropdown, rainbow accent, save/load custom).
-- ══════════════════════════════════════════════════════════════
local TabSettings = Window:AddTab("Settings")
ThemeManager:ApplyToTab(TabSettings)

-- ══════════════════════════════════════════════════════════════
--  PERFORMANCE TAB — live FPS / ping / memory
-- ══════════════════════════════════════════════════════════════
local TabPerf = Window:AddTab("Performance")
local BoxPerf = TabPerf:AddGroupbox("Live Stats")
local FpsLabel    = BoxPerf:AddLabel("FPS: --",    { Color = T.TextSecondary })
local PingLabel   = BoxPerf:AddLabel("Ping: --",   { Color = T.TextSecondary })
local MemoryLabel = BoxPerf:AddLabel("Memory: --", { Color = T.TextSecondary })

-- FrameTime is Roblox's own per-frame render time in seconds (Stats
-- service) -- FPS = 1/FrameTime. GetNetworkPing() returns seconds, so *1000
-- for ms. GetTotalMemoryUsageMb() is already in MB. All three are official
-- engine APIs, not hand-rolled measurements.
task.spawn(function()
    while true do
        local ok = pcall(function()
            local frameTime = StatsSvc.FrameTime
            local fps = frameTime > 0 and (1 / frameTime) or 0
            FpsLabel.Text = string.format("FPS: %d", math.floor(fps + 0.5))

            local pingMs = LocalPlayer:GetNetworkPing() * 1000
            PingLabel.Text = string.format("Ping: %d ms", math.floor(pingMs + 0.5))

            local memMb = StatsSvc:GetTotalMemoryUsageMb()
            MemoryLabel.Text = string.format("Memory: %d MB", math.floor(memMb + 0.5))
        end)
        if not ok then break end
        task.wait(1)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  INFO TAB — live from the Worker, never a hardcoded/phantom list.
-- ══════════════════════════════════════════════════════════════
local TabInfo = Window:AddTab("Info")
local BoxInfo = TabInfo:AddGroupbox("Supported Games")
local InfoStatusLabel = BoxInfo:AddLabel("Loading…", { Color = T.TextMuted })
local infoEntryLabels = {}

local function ClearInfoEntries()
    for _, lbl in ipairs(infoEntryLabels) do
        pcall(function() lbl:Destroy() end)
    end
    infoEntryLabels = {}
end

local function RefreshInfo()
    InfoStatusLabel.Text = "Loading…"
    InfoStatusLabel.TextColor3 = T.TextMuted
    ClearInfoEntries()

    local places, truncatedOrReason = KeyAuth.ListPlaces()
    if not places then
        InfoStatusLabel.Text = "Couldn't reach the server: " .. tostring(truncatedOrReason)
        InfoStatusLabel.TextColor3 = Color3.fromRGB(196, 96, 84)
        return
    end

    if #places == 0 then
        InfoStatusLabel.Text = "No games currently supported yet."
        return
    end

    InfoStatusLabel.Text = tostring(#places) .. " game" .. (#places == 1 and "" or "s") .. " currently supported:"
    for _, place in ipairs(places) do
        local label = place.displayName and (place.displayName)
            or ("PlaceId " .. tostring(place.placeId))
        local lbl = BoxInfo:AddLabel("• " .. label, { Color = T.TextSecondary })
        table.insert(infoEntryLabels, lbl)
    end
end

BoxInfo:AddButton({ Text = "Refresh", Callback = RefreshInfo })
task.spawn(RefreshInfo)

-- ══════════════════════════════════════════════════════════════
--  CLOSE / REOPEN — closes with an animation to a small draggable orb
--  instead of destroying the window; the orb reopens it, now showing the
--  Authenticated state instead of the key field.
-- ══════════════════════════════════════════════════════════════
local ReopenOrb = nil
local ReopenWindow -- forward-declared: BuildReopenOrb's click handler closes over
                    -- this local and calls it once assigned below, rather than
                    -- creating an implicit global function.

local function BuildReopenOrb()
    if ReopenOrb then return ReopenOrb end

    local orb = Instance.new("TextButton")
    orb.Name                   = "AxiUI_ReopenOrb"
    orb.Size                   = UDim2.fromOffset(44, 44)
    orb.BackgroundColor3       = T.WindowBg
    orb.BackgroundTransparency = 1 - T.WindowBgAlpha
    orb.BorderSizePixel        = 0
    orb.Text                   = ""
    orb.AutoButtonColor        = false
    orb.Visible                = false
    orb.ZIndex                 = 50
    orb.Parent                 = Window.Gui
    do
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(1, 0)
        c.Parent = orb
        local s = Instance.new("UIStroke")
        s.Color = T.Border
        s.Transparency = 1 - T.BorderAlpha
        s.Thickness = 1
        s.Parent = orb
    end

    local dot = Instance.new("Frame")
    dot.Size                   = UDim2.fromOffset(10, 10)
    dot.AnchorPoint             = Vector2.new(0.5, 0.5)
    dot.Position                = UDim2.new(0.5, 0, 0.5, 0)
    dot.BackgroundColor3        = T.AccentStrong
    dot.BorderSizePixel         = 0
    dot.Parent                  = orb
    local dc = Instance.new("UICorner")
    dc.CornerRadius = UDim.new(1, 0)
    dc.Parent = dot

    orb.MouseEnter:Connect(function()
        TweenSvc:Create(orb, TweenInfo.new(0.12), { BackgroundTransparency = 1 - T.WindowBgAlpha - 0.1 }):Play()
    end)
    orb.MouseLeave:Connect(function()
        TweenSvc:Create(orb, TweenInfo.new(0.12), { BackgroundTransparency = 1 - T.WindowBgAlpha }):Play()
    end)

    -- Draggable, same technique AxiUI's own window uses internally (that
    -- helper isn't exposed for reuse, so this is a small self-contained copy).
    local dragging, dragInput, mouseStart, orbStart = false, nil, nil, nil
    orb.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1 and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging  = true
        mouseStart = inp.Position
        orbStart   = orb.Position
        inp.Changed:Connect(function()
            if inp.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end)
    orb.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if inp ~= dragInput or not dragging then return end
        local delta = inp.Position - mouseStart
        orb.Position = UDim2.fromOffset(orbStart.X.Offset + delta.X, orbStart.Y.Offset + delta.Y)
    end)

    local dragDistance = 0
    orb.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
            dragDistance = 0
        end
    end)
    orb.InputChanged:Connect(function(inp)
        if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
            dragDistance = dragDistance + 1
        end
    end)
    orb.MouseButton1Click:Connect(function()
        if dragDistance < 4 then
            ReopenWindow()
        end
    end)

    ReopenOrb = orb
    return orb
end

ReopenWindow = function()
    if not ReopenOrb then return end
    local vp = workspace.CurrentCamera.ViewportSize
    Window.Frame.Visible = true
    Window.Frame.Size = UDim2.fromOffset(WIDTH * 0.85, (BASE_HEIGHT + HEADER_H) * 0.85)
    Window.Frame.BackgroundTransparency = 1
    Window.Frame.Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2))
    TweenSvc:Create(Window.Frame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Size = UDim2.fromOffset(WIDTH, BASE_HEIGHT + HEADER_H),
        BackgroundTransparency = 1 - T.WindowBgAlpha,
    }):Play()
    TweenSvc:Create(ReopenOrb, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
    task.delay(0.2, function() ReopenOrb.Visible = false end)
end

local function CloseToOrb()
    BuildReopenOrb()
    local frame = Window.Frame
    TweenSvc:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(WIDTH * 0.85, (BASE_HEIGHT + HEADER_H) * 0.85),
        BackgroundTransparency = 1,
    }):Play()
    task.delay(0.26, function()
        frame.Visible = false
        local vp = workspace.CurrentCamera.ViewportSize
        ReopenOrb.Position = UDim2.fromOffset(vp.X - 74, vp.Y - 94)
        ReopenOrb.BackgroundTransparency = 1
        ReopenOrb.Visible = true
        TweenSvc:Create(ReopenOrb, TweenInfo.new(0.2), { BackgroundTransparency = 1 - T.WindowBgAlpha }):Play()
    end)
end

-- ══════════════════════════════════════════════════════════════
--  AUTH SUCCESS — shared by fresh key entry and the silent cached path.
--  skipOpenAnimation is true for the cached path: the window is never
--  actually shown before collapsing to the orb.
-- ══════════════════════════════════════════════════════════════
local function OnLoadStage(key)
    local ok, source = KeyAuth.FetchScriptForPlace(PlaceId, key)
    if not ok then
        warn("[UniversalKeyGate] Script fetch failed: " .. tostring(source))
        return
    end
    RunPayload(source)
end

local function OnAuthenticated(key, resolvedScript, expiresAt, skipOpenAnimation)
    ShowAuthenticatedState(resolvedScript, expiresAt)
    KeyAuth.SaveCachedKey(CACHE_FILE, key)
    OnLoadStage(key)

    if skipOpenAnimation then
        BuildReopenOrb()
        Window.Frame.Visible = false
        local vp = workspace.CurrentCamera.ViewportSize
        ReopenOrb.Position = UDim2.fromOffset(vp.X - 74, vp.Y - 94)
        ReopenOrb.BackgroundTransparency = 1 - T.WindowBgAlpha
        ReopenOrb.Visible = true
    else
        task.wait(0.4)
        CloseToOrb()
    end
end

-- ══════════════════════════════════════════════════════════════
--  KEY VALIDATION — fresh entry path
-- ══════════════════════════════════════════════════════════════
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

local validating = false
local function SubmitKey()
    if validating then return end

    local key = CleanKey(AxiUI.Flags["KeyInput"])
    if key == "" then
        StatusLabel.Text = "Enter a key first."
        StatusLabel.TextColor3 = Color3.fromRGB(196, 96, 84)
        Shake(Window.Frame)
        return
    end

    validating = true
    ValidateBtn.Button.Text = "Validating..."
    StatusLabel.Text = "Checking key..."
    StatusLabel.TextColor3 = T.TextMuted

    local ok, reason, resolvedScript, expiresAt = KeyAuth.VerifyForPlace(PlaceId, key)

    validating = false
    if ok then
        AxiUI:Notify("Access", "Key accepted.", 2)
        OnAuthenticated(key, resolvedScript, expiresAt, false)
    else
        ValidateBtn.Button.Text = "Validate"
        StatusLabel.Text = reason or "Invalid key — try again."
        StatusLabel.TextColor3 = Color3.fromRGB(196, 96, 84)
        Shake(Window.Frame)
    end
end

ValidateBtn.Button.MouseButton1Click:Connect(SubmitKey)

-- ══════════════════════════════════════════════════════════════
--  SILENT PATH — a cached key from a previous validated run in THIS exact
--  game, still valid right now. Jumps straight to the closed/orb state
--  with the Authenticated view underneath, no key-entry UI ever shown.
-- ══════════════════════════════════════════════════════════════
local function TrySilentLoad()
    local cachedKey, cachedUserId = KeyAuth.LoadCachedKey(CACHE_FILE)
    if not cachedKey or cachedUserId ~= tostring(LocalPlayer.UserId) then
        return false
    end
    local ok, _, resolvedScript, expiresAt = KeyAuth.VerifyForPlace(PlaceId, cachedKey)
    if not ok then
        return false
    end
    OnAuthenticated(cachedKey, resolvedScript, expiresAt, true)
    return true
end

-- Invisible from the very start -- TrySilentLoad's VerifyForPlace call is a
-- real network round-trip, and without this the raw window (key-entry tab
-- and all) would flash on screen for that entire duration before
-- OnAuthenticated ever gets a chance to hide it, defeating the whole point
-- of "no key-entry UI ever shown" for a cached-key rejoin.
Window.Frame.Visible = false

if not TrySilentLoad() then
    -- ══════════════════════════════════════════════════════════════
    --  ENTRANCE ANIMATION — only for the fresh-entry path.
    -- ══════════════════════════════════════════════════════════════
    Window.Frame.Visible = true
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
