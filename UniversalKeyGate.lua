--[[
    Universal Key Gate — Dashboard edition

    THE loader every script (Finite included) should load from — not a
    per-script loader. Enter a key, and the finite-log-proxy Worker (1)
    checks the key, (2) resolves game.PlaceId to whichever script that game
    maps to, (3) returns that script only if the key is valid for it. No
    PlaceId -> script table exists anywhere in this file, or in any client
    code at all — that mapping lives entirely server-side.

    All Worker communication is delegated to the shared keyauth.lua module
    — this file only builds the UI around it. No local HTTP bridge, no
    local JSON handling, no local validity decision.

    AxiUI is now a FORK (axiui-keygate/AxiUI/, not ScriptB/Universal-Scripts)
    edited directly rather than worked around from outside. The previous
    approach hid the built-in macOS dots and hand-built a parallel sidebar
    system from outside the library, fighting its internals at every step
    -- fragile, and the actual root cause of the "shadow permanently
    visible" bug (a shadow built externally as a one-time position snapshot
    has no way to track the real window moving/hiding). This fork instead:
      - removes the macOS dots at the source (gone, not hidden)
      - makes a native left sidebar the framework's actual tab layout, with
        icon-badge tabs built in (see AxiUI_Framework.lua's AddTab/_SelectTab)
      - adds AxiUI:AddShadow(target), a shadow wired to the target's own
        Position/Size/Visible via GetPropertyChangedSignal so it can never
        desync from what it's shadowing
      - adds CreateWindow's HeaderHeight/SidebarWidth options so a custom
        header reserves its space natively instead of being repositioned
        into existence after the fact

    Lifecycle: on a valid key (fresh entry OR a still-valid cached one from
    a previous run in THIS game), the License tab switches from the key
    field to an "Authenticated" state with a live expiry countdown, the
    script loads in the background, and the window closes itself with an
    animation — leaving a small draggable orb behind that reopens it. A
    still-valid cached key skips straight to that closed/orb state with no
    key-entry UI ever shown. A DIFFERENT game always prompts fresh, even
    with a valid cached key from elsewhere (see TrySilentLoad).

    Visual style: glassmorphism (translucent layered panels, soft gradient
    sheen, light border, real drop shadows) plus a genuine background blur
    (DepthOfFieldEffect, confirmed against Roblox's own docs -- see SetBlur)
    while the window itself is open, matching how Fluent's own "Acrylic"
    effect actually works. Panel opacity is calibrated well above a typical
    CSS glassmorphism example (there's no real blur *behind a single panel*
    the way CSS relies on, so low-opacity panels just read as invisible in
    Roblox rather than "glassy").

    Content is organized as an actual dashboard (Dashboard/License/Settings/
    Performance/Info in a left sidebar), not a single settings-style list --
    Dashboard is a real landing page with status cards, not another tab of
    stacked rows.

    Entire construction is wrapped in pcall so a future bug fails loud (a
    warn() and nothing built) instead of silently killing the whole script
    partway through with no UI and no explanation, which is what "UI not
    loading" looks like from a real user's side when nothing is defensive.

    Load:
        loadstring(game:HttpGet(
            "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/UniversalKeyGate.lua"
        ))()
]]

local ok, err = pcall(function()

local Players     = game:GetService("Players")
local TweenSvc     = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local StatsSvc     = game:GetService("Stats")
local Lighting     = game:GetService("Lighting")
local LocalPlayer = Players.LocalPlayer

-- Real background blur (DepthOfFieldEffect), not a fake -- confirmed
-- against Roblox's own docs: FocusDistance sets where the sharp zone sits
-- (in studs from camera), InFocusRadius is the buffer around it that stays
-- sharp, NearIntensity/FarIntensity control blur strength on either side.
-- A small FocusDistance + tight InFocusRadius + FarIntensity up and
-- NearIntensity at 0 blurs the game world beyond that near point. Toggled
-- on only while the actual window is open -- minimized-to-orb shouldn't
-- blur the game the player is trying to get back to.
local BlurEffect = Instance.new("DepthOfFieldEffect")
BlurEffect.Name          = "UniversalKeyGate_Blur"
BlurEffect.FocusDistance = 2
BlurEffect.InFocusRadius = 1
BlurEffect.NearIntensity = 0
BlurEffect.FarIntensity  = 0
BlurEffect.Enabled       = false
BlurEffect.Parent        = Lighting

local function SetBlur(on)
    TweenSvc:Create(BlurEffect, TweenInfo.new(0.35, Enum.EasingStyle.Exponential), {
        FarIntensity = on and 0.6 or 0,
    }):Play()
    if on then
        BlurEffect.Enabled = true
    else
        task.delay(0.35, function() BlurEffect.Enabled = false end)
    end
end

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
local CACHE_FILE = "universalkeygate_place_" .. tostring(PlaceId) .. ".json"

local function RunPayload(source)
    local runOk, runErr = pcall(function()
        loadstring(source)()
    end)
    if not runOk then
        warn("[UniversalKeyGate] Script exec failed: " .. tostring(runErr))
    end
end

-- ══════════════════════════════════════════════════════════════
--  LOAD AXIUI (fork) + THEME
-- ══════════════════════════════════════════════════════════════
local AXIUI_BASE = "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/AxiUI/"

local AxiUI = loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_Framework.lua"))()
local ThemeManager = loadstring(game:HttpGet(AXIUI_BASE .. "AxiUI_ThemeManager.lua"))()

-- Structural glass properties. Raised substantially from an earlier pass
-- (~5% GroupboxBgAlpha/ElementBgAlpha, ~70-80% WindowBgAlpha) that read as
-- "everything unreadable" -- there's no real blur *behind an individual
-- panel* the way CSS glassmorphism examples rely on, so low opacity just
-- looks like nothing is there. This pass prioritizes actual legibility.
AxiUI:SetTheme({
    GroupboxBg      = Color3.fromRGB(255, 255, 255),  GroupboxBgAlpha = 0.55,
    ElementBg       = Color3.fromRGB(255, 255, 255),  ElementBgAlpha  = 0.42,
    Border          = Color3.fromRGB(255, 255, 255),  BorderAlpha     = 0.30,
})

ThemeManager:AddTheme("Glass", {
    WindowBg      = Color3.fromRGB(18,  21,  28),   WindowBgAlpha  = 0.93,
    Accent        = Color3.fromRGB(150, 178, 205),  AccentAlpha    = 0.38,
    AccentStrong  = Color3.fromRGB(205, 222, 238),
    TextPrimary   = Color3.fromRGB(244, 247, 250),
    TextSecondary = Color3.fromRGB(188, 197, 209),
    TextMuted     = Color3.fromRGB(138, 148, 163),
})
ThemeManager:Apply("Glass")

local T = AxiUI.Theme

-- ══════════════════════════════════════════════════════════════
--  WINDOW
-- ══════════════════════════════════════════════════════════════
local SIDEBAR_W  = 110
local CONTENT_W  = 460
local HEADER_H   = 64
local WIDTH      = CONTENT_W + SIDEBAR_W
local HEIGHT     = 560

local Window = AxiUI:CreateWindow({
    Title        = "Access",
    Width        = WIDTH,
    Height       = HEIGHT,
    HeaderHeight = HEADER_H,
    SidebarWidth = SIDEBAR_W,
})
Window.Frame.AnchorPoint = Vector2.new(0.5, 0.5)
do
    local vp = workspace.CurrentCamera.ViewportSize
    Window.Frame.Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2))
end

-- Real drop shadow, self-tracking (see AxiUI_Framework.lua's AddShadow) --
-- this is the actual fix for "shadow permanently visible no matter UI
-- location or state": it's wired to Window.Frame's own Position/Size/
-- Visible, not a one-time snapshot.
Window:AddShadow(Window.Frame)

-- Subtle diagonal glass sheen -- a soft light streak across the panel.
-- Paired with the real DepthOfFieldEffect blur above (SetBlur) while the
-- window is open, plus the drop shadow, for actual layered depth rather
-- than one flat translucent rectangle.
do
    local sheen = Instance.new("UIGradient")
    sheen.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(190, 205, 220)),
    })
    sheen.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.90),
        NumberSequenceKeypoint.new(0.5, 0.97),
        NumberSequenceKeypoint.new(1,   0.90),
    })
    sheen.Rotation = 105
    sheen.Parent = Window.Frame
end

-- ══════════════════════════════════════════════════════════════
--  CUSTOM HEADER — avatar + time-of-day greeting, in the space
--  CreateWindow's HeaderHeight reserved natively.
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
AvatarImg.BackgroundTransparency = 0.85
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

task.spawn(function()
    local thumbOk, content = pcall(function()
        return Players:GetUserThumbnailAsync(
            LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
    end)
    if thumbOk and content and content ~= "" then
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
SubLbl.TextColor3             = T.TextSecondary
SubLbl.TextXAlignment         = Enum.TextXAlignment.Left
SubLbl.TextTruncate           = Enum.TextTruncate.AtEnd
SubLbl.Text                   = "Game ID " .. tostring(PlaceId)
SubLbl.Parent                 = HeaderRow

-- ══════════════════════════════════════════════════════════════
--  CARD HELPER — small bordered stat panels, laid out in a row. This is
--  what actually makes Dashboard/Performance read as a dashboard rather
--  than a settings-style stacked list.
-- ══════════════════════════════════════════════════════════════
local function AddCardRow(groupbox, cardSpecs)
    local row = Instance.new("Frame")
    row.Size                   = UDim2.new(1, -16, 0, 62)
    row.BackgroundTransparency = 1
    row.BorderSizePixel        = 0
    row.Parent                 = groupbox.Body

    local list = Instance.new("UIListLayout")
    list.FillDirection = Enum.FillDirection.Horizontal
    list.Padding        = UDim.new(0, 8)
    list.SortOrder       = Enum.SortOrder.LayoutOrder
    list.Parent          = row

    local cardW = math.floor((CONTENT_W - 16 - 16 - (#cardSpecs - 1) * 8) / #cardSpecs)
    local cards = {}

    for _, spec in ipairs(cardSpecs) do
        local card = Instance.new("Frame")
        card.Size                   = UDim2.fromOffset(cardW, 62)
        card.BackgroundColor3       = T.ElementBg
        card.BackgroundTransparency = 1 - T.ElementBgAlpha
        card.BorderSizePixel        = 0
        card.Parent                 = row
        local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = card
        local s = Instance.new("UIStroke")
        s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = card

        local titleLbl = Instance.new("TextLabel")
        titleLbl.Size                   = UDim2.new(1, -12, 0, 14)
        titleLbl.Position               = UDim2.fromOffset(8, 6)
        titleLbl.BackgroundTransparency = 1
        titleLbl.Font                   = Enum.Font.Gotham
        titleLbl.TextSize               = 10
        titleLbl.TextColor3             = T.TextSecondary
        titleLbl.TextXAlignment         = Enum.TextXAlignment.Left
        titleLbl.Text                   = spec.Title
        titleLbl.Parent                 = card

        local valueLbl = Instance.new("TextLabel")
        valueLbl.Size                   = UDim2.new(1, -12, 0, 28)
        valueLbl.Position               = UDim2.fromOffset(8, 24)
        valueLbl.BackgroundTransparency = 1
        valueLbl.Font                   = Enum.Font.GothamBold
        valueLbl.TextSize               = 17
        valueLbl.TextColor3             = T.TextPrimary
        valueLbl.TextXAlignment         = Enum.TextXAlignment.Left
        valueLbl.Text                   = spec.Value or "--"
        valueLbl.Parent                 = card

        cards[spec.Key or spec.Title] = valueLbl
    end

    return cards
end

-- ══════════════════════════════════════════════════════════════
--  DASHBOARD TAB — a real landing page, not another settings list: status
--  cards giving an at-a-glance summary, matching what an actual dashboard
--  looks like rather than a box with tabs.
-- ══════════════════════════════════════════════════════════════
local TabDashboard = Window:AddTab("Dashboard", { Icon = "D" })
local BoxOverview = TabDashboard:AddGroupbox("Overview")
local overviewCards = AddCardRow(BoxOverview, {
    { Key = "Status", Title = "LICENSE",  Value = "Checking…" },
    { Key = "Game",   Title = "GAME",     Value = tostring(PlaceId) },
    { Key = "FPS",    Title = "FPS",      Value = "--" },
})
BoxOverview:AddLabel(
    "Head to the License tab to authenticate, or Info to see every game currently supported.",
    { Color = T.TextMuted }
)

-- ══════════════════════════════════════════════════════════════
--  LICENSE TAB — two states: key entry, or authenticated + live expiry
-- ══════════════════════════════════════════════════════════════
local TabLicense = Window:AddTab("License", { Icon = "L" })

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
local AuthedStatusLabel = AuthedBox:AddLabel("Authenticated", { Color = Color3.fromRGB(140, 205, 165) })
local AuthedTimerLabel  = AuthedBox:AddLabel("", { Color = T.TextSecondary })

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
    overviewCards.Status.Text = "Active"
    overviewCards.Status.TextColor3 = Color3.fromRGB(140, 205, 165)
end

-- ══════════════════════════════════════════════════════════════
--  SETTINGS TAB
-- ══════════════════════════════════════════════════════════════
local TabSettings = Window:AddTab("Settings", { Icon = "S" })
ThemeManager:ApplyToTab(TabSettings)

-- ══════════════════════════════════════════════════════════════
--  PERFORMANCE TAB — stat cards, not a plain list.
-- ══════════════════════════════════════════════════════════════
local TabPerf = Window:AddTab("Performance", { Icon = "P" })
local BoxPerf = TabPerf:AddGroupbox("Live Stats")
local perfCards = AddCardRow(BoxPerf, {
    { Key = "FPS",    Title = "FPS",    Value = "--" },
    { Key = "Ping",   Title = "PING",   Value = "--" },
    { Key = "Memory", Title = "MEMORY", Value = "--" },
})

-- FrameTime is Roblox's own per-frame render time in seconds (Stats
-- service) -- FPS = 1/FrameTime. GetNetworkPing() returns seconds, so *1000
-- for ms. GetTotalMemoryUsageMb() is already in MB. All three are official
-- engine APIs, not hand-rolled measurements.
task.spawn(function()
    while true do
        local statOk = pcall(function()
            local frameTime = StatsSvc.FrameTime
            local fps = frameTime > 0 and (1 / frameTime) or 0
            local fpsText = tostring(math.floor(fps + 0.5))
            perfCards.FPS.Text = fpsText
            overviewCards.FPS.Text = fpsText

            local pingMs = LocalPlayer:GetNetworkPing() * 1000
            perfCards.Ping.Text = string.format("%d ms", math.floor(pingMs + 0.5))

            local memMb = StatsSvc:GetTotalMemoryUsageMb()
            perfCards.Memory.Text = string.format("%d MB", math.floor(memMb + 0.5))
        end)
        if not statOk then break end
        task.wait(1)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  INFO TAB — live from the Worker, never a hardcoded/phantom list.
-- ══════════════════════════════════════════════════════════════
local TabInfo = Window:AddTab("Info", { Icon = "I" })
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
        InfoStatusLabel.TextColor3 = Color3.fromRGB(210, 120, 108)
        overviewCards.Game.Text = tostring(PlaceId)
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
local ReopenWindow -- forward-declared: BuildReopenOrb's click handler closes
                    -- over this local and calls it once assigned below.

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
    Window:AddShadow(orb, { CornerRadius = 22, Layers = {
        { pad = 3, alpha = 0.14 }, { pad = 7, alpha = 0.08 }, { pad = 12, alpha = 0.04 },
    } })

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
        TweenSvc:Create(orb, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 - T.WindowBgAlpha - 0.1 }):Play()
    end)
    orb.MouseLeave:Connect(function()
        TweenSvc:Create(orb, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 - T.WindowBgAlpha }):Play()
    end)

    -- Draggable, same technique AxiUI's own window uses internally.
    local dragging, dragInput, mouseStart, orbStart = false, nil, nil, nil
    local dragDistance = 0
    orb.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1 and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging  = true
        dragDistance = 0
        mouseStart = inp.Position
        orbStart   = orb.Position
        inp.Changed:Connect(function()
            if inp.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end)
    orb.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
            if dragging then dragDistance = dragDistance + 1 end
        end
    end)
    UIS.InputChanged:Connect(function(inp)
        if inp ~= dragInput or not dragging then return end
        local delta = inp.Position - mouseStart
        orb.Position = UDim2.fromOffset(orbStart.X.Offset + delta.X, orbStart.Y.Offset + delta.Y)
    end)
    orb.MouseButton1Click:Connect(function()
        if dragDistance < 4 then
            ReopenWindow()
        end
    end)

    ReopenOrb = orb
    return orb
end

local OPEN_CLOSE_TWEEN = TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out)

ReopenWindow = function()
    if not ReopenOrb then return end
    local vp = workspace.CurrentCamera.ViewportSize
    Window.Frame.Visible = true
    Window.Frame.Size = UDim2.fromOffset(WIDTH * 0.9, HEIGHT * 0.9)
    Window.Frame.BackgroundTransparency = 1
    Window.Frame.Position = UDim2.fromOffset(math.floor(vp.X / 2), math.floor(vp.Y / 2))
    SetBlur(true)
    TweenSvc:Create(Window.Frame, OPEN_CLOSE_TWEEN, {
        Size = UDim2.fromOffset(WIDTH, HEIGHT),
        BackgroundTransparency = 1 - T.WindowBgAlpha,
    }):Play()
    TweenSvc:Create(ReopenOrb, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 }):Play()
    task.delay(0.3, function() ReopenOrb.Visible = false end)
end

local function CloseToOrb()
    BuildReopenOrb()
    local frame = Window.Frame
    SetBlur(false)
    TweenSvc:Create(frame, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.In), {
        Size = UDim2.fromOffset(WIDTH * 0.9, HEIGHT * 0.9),
        BackgroundTransparency = 1,
    }):Play()
    task.delay(0.4, function()
        frame.Visible = false
        local vp = workspace.CurrentCamera.ViewportSize
        ReopenOrb.Position = UDim2.fromOffset(vp.X - 74, vp.Y - 94)
        ReopenOrb.BackgroundTransparency = 1
        ReopenOrb.Visible = true
        TweenSvc:Create(ReopenOrb, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), { BackgroundTransparency = 1 - T.WindowBgAlpha }):Play()
    end)
end

-- ══════════════════════════════════════════════════════════════
--  AUTH SUCCESS — shared by fresh key entry and the silent cached path.
-- ══════════════════════════════════════════════════════════════
local function OnLoadStage(key)
    local fetchOk, source = KeyAuth.FetchScriptForPlace(PlaceId, key)
    if not fetchOk then
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
        StatusLabel.TextColor3 = Color3.fromRGB(210, 120, 108)
        Shake(Window.Frame)
        return
    end

    validating = true
    ValidateBtn.Button.Text = "Validating..."
    StatusLabel.Text = "Checking key..."
    StatusLabel.TextColor3 = T.TextMuted

    local verifyOk, reason, resolvedScript, expiresAt = KeyAuth.VerifyForPlace(PlaceId, key)

    validating = false
    if verifyOk then
        AxiUI:Notify("Access", "Key accepted.", 2)
        OnAuthenticated(key, resolvedScript, expiresAt, false)
    else
        ValidateBtn.Button.Text = "Validate"
        StatusLabel.Text = reason or "Invalid key — try again."
        StatusLabel.TextColor3 = Color3.fromRGB(210, 120, 108)
        overviewCards.Status.Text = "Invalid"
        overviewCards.Status.TextColor3 = Color3.fromRGB(210, 120, 108)
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
    local verifyOk, _, resolvedScript, expiresAt = KeyAuth.VerifyForPlace(PlaceId, cachedKey)
    if not verifyOk then
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
    Window.Frame.Visible = true
    local frame = Window.Frame
    local targetSize  = frame.Size
    local targetAlpha = frame.BackgroundTransparency

    frame.Size = UDim2.fromOffset(targetSize.X.Offset * 0.9, targetSize.Y.Offset * 0.9)
    frame.BackgroundTransparency = 1

    SetBlur(true)
    TweenSvc:Create(frame, OPEN_CLOSE_TWEEN, {
        Size = targetSize,
        BackgroundTransparency = targetAlpha,
    }):Play()
end

overviewCards.Status.Text = overviewCards.Status.Text == "Checking…" and "Enter a key" or overviewCards.Status.Text

end)

if not ok then
    warn("[UniversalKeyGate] Failed to build UI: " .. tostring(err))
end
