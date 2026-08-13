--[[
    Universal Key Gate — Dashboard edition (Superdesign port)

    THE loader every script (Finite included) should load from — not a
    per-script loader. Enter a key, and the finite-log-proxy Worker (1)
    checks the key, (2) resolves game.PlaceId to whichever script that game
    maps to, (3) returns that script only if the key is valid for it. No
    PlaceId -> script table exists anywhere in this file, or in any client
    code at all — that mapping lives entirely server-side.

    All Worker communication is delegated to the shared keyauth.lua module
    — this file only builds the UI around it. No local HTTP bridge, no
    local JSON handling, no local validity decision.

    Visual layout is a faithful port of the approved Superdesign draft
    (project a5fec5c4-e974-4aa2-bd8d-b515445af6bc, draft
    3b670ab9-0f77-4b59-b00f-18d2bd4e7078, "Optimized Compact Dashboard UI"):
    near-black glass window, per-tab colored badges (not one shared accent),
    a Dashboard landing tab built from clickable status cards, a License tab
    with two mutually-exclusive states (never both at once), Performance as
    icon-rows, and a live Info list with copy-to-clipboard. Adapted, not
    pixel-copied, where Roblox UI primitives don't have a CSS/Tailwind
    equivalent (no icon font, so colored circles/letters stand in for
    lucide icons; Settings keeps AxiUI's own real ThemeManager functionality
    rather than the mockup's illustrative, non-functional Save/Reset).

    AxiUI is a fork (axiui-keygate/AxiUI/, not ScriptB/Universal-Scripts),
    edited directly: macOS dots removed at the source, a native left
    sidebar with per-tab badge colors, a self-tracking AxiUI:AddShadow so a
    shadow can never desync from the window it's shadowing, and
    CreateWindow's HeaderHeight/SidebarWidth options so this file doesn't
    have to reposition TabRow/ContentArea by hand.

    Entire construction is wrapped in pcall so a future bug fails loud (one
    warn(), nothing built) instead of silently killing the whole script
    partway through with no explanation.

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

local setclipboard = setclipboard or function(text) print("[Clipboard]", text) end

-- Real background blur (DepthOfFieldEffect), confirmed against Roblox's own
-- docs. Toggled on only while the window itself is open, not while
-- minimized to the orb.
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
--  LOAD KEYAUTH
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

AxiUI:SetTheme({
    GroupboxBg      = Color3.fromRGB(255, 255, 255),  GroupboxBgAlpha = 0.05,
    ElementBg       = Color3.fromRGB(255, 255, 255),  ElementBgAlpha  = 0.05,
    Border          = Color3.fromRGB(255, 255, 255),  BorderAlpha     = 0.08,
})

-- Near-black glass, matching the approved design's dark gradient window
-- (rgba(15,15,25,.97) -> rgba(5,5,10,.99)) approximated as a flat near-black
-- at high opacity -- Roblox panels don't support a gradient window
-- background directly, the UIGradient sheen below adds the diagonal light
-- variation instead.
ThemeManager:AddTheme("Glass", {
    WindowBg      = Color3.fromRGB(10, 10, 16),     WindowBgAlpha  = 0.97,
    Accent        = Color3.fromRGB(150, 178, 205),  AccentAlpha    = 0.30,
    AccentStrong  = Color3.fromRGB(205, 222, 238),
    TextPrimary   = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(200, 200, 210),
    TextMuted     = Color3.fromRGB(140, 140, 155),
})
ThemeManager:Apply("Glass")

local T = AxiUI.Theme

-- Per-tab accent colors, matching the approved design (each tab keeps its
-- own hue rather than one shared accent) -- also reused for Dashboard/Info
-- card icon tints so the same color language carries through the whole UI.
local COLOR_DASH  = Color3.fromRGB(96,  165, 250)  -- blue-400
local COLOR_LIC   = Color3.fromRGB(52,  211, 153)  -- emerald-400
local COLOR_SET   = Color3.fromRGB(192, 132, 252)  -- purple-400
local COLOR_PERF  = Color3.fromRGB(251, 146, 60)   -- orange-400
local COLOR_INFO  = Color3.fromRGB(34,  211, 238)  -- cyan-400
local COLOR_BAD   = Color3.fromRGB(220, 120, 108)

-- ══════════════════════════════════════════════════════════════
--  WINDOW
-- ══════════════════════════════════════════════════════════════
local SIDEBAR_W  = 90
local CONTENT_W  = 760
local HEADER_H   = 50
local WIDTH      = CONTENT_W + SIDEBAR_W
local HEIGHT     = 550

local Window = AxiUI:CreateWindow({
    Title        = "Universal Key Gate Dashboard",
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

-- Self-tracking drop shadow (see AxiUI_Framework.lua's AddShadow) -- wired
-- to Window.Frame's own Position/Size/Visible, cannot desync from it.
Window:AddShadow(Window.Frame)

-- Diagonal glass sheen, approximating the reference gradient window
-- background's light variation.
do
    local sheen = Instance.new("UIGradient")
    sheen.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(190, 205, 220)),
    })
    sheen.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.94),
        NumberSequenceKeypoint.new(0.5, 0.985),
        NumberSequenceKeypoint.new(1,   0.94),
    })
    sheen.Rotation = 105
    sheen.Parent = Window.Frame
end

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

local AVATAR_SIZE = 36
local AvatarImg = Instance.new("ImageLabel")
AvatarImg.Name                  = "Avatar"
AvatarImg.Size                  = UDim2.fromOffset(AVATAR_SIZE, AVATAR_SIZE)
AvatarImg.Position              = UDim2.fromOffset(16, (HEADER_H - AVATAR_SIZE) / 2)
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
GreetingLbl.Size                   = UDim2.new(1, -(16 + AVATAR_SIZE + 10 + 12), 0, 16)
GreetingLbl.Position               = UDim2.fromOffset(16 + AVATAR_SIZE + 10, HEADER_H / 2 - 16)
GreetingLbl.BackgroundTransparency = 1
GreetingLbl.Font                   = Enum.Font.GothamBold
GreetingLbl.TextSize               = 13
GreetingLbl.TextColor3             = T.TextPrimary
GreetingLbl.TextXAlignment         = Enum.TextXAlignment.Left
GreetingLbl.TextTruncate           = Enum.TextTruncate.AtEnd
GreetingLbl.Text                   = GetGreeting()
GreetingLbl.Parent                 = HeaderRow

local SubLbl = Instance.new("TextLabel")
SubLbl.Size                   = GreetingLbl.Size
SubLbl.Position               = UDim2.fromOffset(16 + AVATAR_SIZE + 10, HEADER_H / 2 + 1)
SubLbl.BackgroundTransparency = 1
SubLbl.Font                   = Enum.Font.Gotham
SubLbl.TextSize               = 10
SubLbl.TextColor3             = T.TextMuted
SubLbl.TextXAlignment         = Enum.TextXAlignment.Left
SubLbl.TextTruncate           = Enum.TextTruncate.AtEnd
SubLbl.Text                   = "Current Session ID: " .. tostring(PlaceId)
SubLbl.Parent                 = HeaderRow

-- ══════════════════════════════════════════════════════════════
--  SMALL VISUAL HELPERS
-- ══════════════════════════════════════════════════════════════
local function Panel(parent, size, position)
    local p = Instance.new("Frame")
    p.Size                   = size
    p.Position               = position or UDim2.fromOffset(0, 0)
    p.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
    p.BackgroundTransparency = 0.96
    p.BorderSizePixel        = 0
    p.Parent                 = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = p
    local s = Instance.new("UIStroke")
    s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = p
    return p
end

-- A clickable status card: icon square (or dot) + label + value, optional
-- tint color and click-through to another tab. Used across Dashboard/Info.
local function StatCard(parent, opts)
    local card = Instance.new(opts.Href and "TextButton" or "Frame")
    if opts.Href then card.Text = "" ; card.AutoButtonColor = false end
    card.Size                   = opts.Size
    card.Position               = opts.Position or UDim2.fromOffset(0, 0)
    card.BackgroundColor3       = Color3.fromRGB(255, 255, 255)
    card.BackgroundTransparency = opts.Tint and 0.94 or 0.96
    card.BorderSizePixel        = 0
    card.Parent                 = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = card
    local strokeColor = opts.Tint or T.Border
    local s = Instance.new("UIStroke")
    s.Color = strokeColor; s.Transparency = opts.Tint and 0.75 or (1 - T.BorderAlpha); s.Thickness = 1; s.Parent = card

    if opts.Href then
        card.MouseEnter:Connect(function()
            TweenSvc:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = (opts.Tint and 0.90 or 0.92) }):Play()
        end)
        card.MouseLeave:Connect(function()
            TweenSvc:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = opts.Tint and 0.94 or 0.96 }):Play()
        end)
        card.MouseButton1Click:Connect(opts.Href)
    end

    return card
end

local function AddIconSquare(parent, color, letter, size, pos)
    local sq = Instance.new("Frame")
    sq.Size                   = UDim2.fromOffset(size, size)
    sq.Position               = pos
    sq.BackgroundColor3       = color
    sq.BackgroundTransparency = 0.88
    sq.BorderSizePixel        = 0
    sq.Parent                 = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, math.floor(size * 0.3)); c.Parent = sq
    local s = Instance.new("UIStroke")
    s.Color = color; s.Transparency = 0.75; s.Thickness = 1; s.Parent = sq
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = math.floor(size * 0.4)
    lbl.TextColor3             = color
    lbl.Text                   = letter
    lbl.Parent                 = sq
    return sq
end

local function Label(parent, text, size, color, pos, sz, font, align)
    local l = Instance.new("TextLabel")
    l.Size                   = sz
    l.Position               = pos
    l.BackgroundTransparency = 1
    l.Font                   = font or Enum.Font.Gotham
    l.TextSize               = size
    l.TextColor3             = color
    l.TextXAlignment          = align or Enum.TextXAlignment.Left
    l.TextTruncate            = Enum.TextTruncate.AtEnd
    l.Text                   = text
    l.Parent                 = parent
    return l
end

-- ══════════════════════════════════════════════════════════════
--  TOAST — small bottom-center popup, anchored to the window (not the
--  whole screen), for copy-to-clipboard feedback.
-- ══════════════════════════════════════════════════════════════
local Toast = Instance.new("TextLabel")
Toast.Size                   = UDim2.fromOffset(180, 34)
Toast.AnchorPoint             = Vector2.new(0.5, 1)
Toast.Position                = UDim2.new(0.5, 0, 1, 40)
Toast.BackgroundColor3        = Color3.fromRGB(255, 255, 255)
Toast.BackgroundTransparency  = 0.85
Toast.BorderSizePixel         = 0
Toast.Font                    = Enum.Font.GothamBold
Toast.TextSize                = 12
Toast.TextColor3              = T.TextPrimary
Toast.Text                    = ""
Toast.ZIndex                  = 40
Toast.Parent                  = Window.Frame
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = Toast
    local s = Instance.new("UIStroke")
    s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = Toast
end

local function ShowToast(msg)
    Toast.Text = msg
    TweenSvc:Create(Toast, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 1, -16),
    }):Play()
    task.delay(2, function()
        TweenSvc:Create(Toast, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 1, 40),
        }):Play()
    end)
end

-- Forward-declared: Dashboard's cards (built below) link to License/
-- Performance/Info, all defined later in the file. A click handler
-- closure resolves a free variable lexically at the point it's DEFINED --
-- without this, TabLicense/TabPerf/TabInfo wouldn't exist as locals yet
-- when these closures are created, so they'd silently capture globals
-- (nil) instead of the real tab objects, and clicking those cards would
-- throw inside Window:_SelectTab(nil).
local TabDashboard, TabLicense, TabSettings, TabPerf, TabInfo

-- ══════════════════════════════════════════════════════════════
--  DASHBOARD TAB
-- ══════════════════════════════════════════════════════════════
TabDashboard = Window:AddTab("Dash", { Icon = "D", BadgeColor = COLOR_DASH })

local dashRow1 = Instance.new("Frame")
dashRow1.Size = UDim2.new(1, 0, 0, 84)
dashRow1.BackgroundTransparency = 1
dashRow1.BorderSizePixel = 0
dashRow1.Parent = TabDashboard.Scroll

local dashCardW = math.floor((CONTENT_W - 20 - 20 - 10) * 2 / 3)
local dashCardW2 = (CONTENT_W - 20 - 20 - 10) - dashCardW

local dashLicenseCard = StatCard(dashRow1, {
    Size = UDim2.fromOffset(dashCardW, 84), Tint = COLOR_LIC,
    Href = function() Window:_SelectTab(TabLicense) end,
})
Label(dashLicenseCard, "SESSION LICENSE", 9, Color3.fromRGB(
    math.floor(COLOR_LIC.R*255*0.7), math.floor(COLOR_LIC.G*255*0.7), math.floor(COLOR_LIC.B*255*0.7)),
    UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 12), Enum.Font.GothamBold)
local dashStatusDot = Instance.new("Frame")
dashStatusDot.Size = UDim2.fromOffset(8, 8)
dashStatusDot.Position = UDim2.fromOffset(12, 32)
dashStatusDot.BackgroundColor3 = COLOR_BAD
dashStatusDot.BorderSizePixel = 0
dashStatusDot.Parent = dashLicenseCard
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = dashStatusDot end
local dashStatusLbl = Label(dashLicenseCard, "Enter a key", 13, T.TextPrimary,
    UDim2.fromOffset(26, 26), UDim2.new(1, -38, 0, 18), Enum.Font.GothamBold)
local dashKeyHintLbl = Label(dashLicenseCard, "", 8, T.TextMuted,
    UDim2.fromOffset(12, 50), UDim2.new(1, -24, 0, 12), Enum.Font.Code)

local dashFpsCard = StatCard(dashRow1, {
    Size = UDim2.fromOffset(dashCardW2, 84), Position = UDim2.fromOffset(dashCardW + 10, 0),
    Href = function() Window:_SelectTab(TabPerf) end,
})
Label(dashFpsCard, "FPS RATE", 8, T.TextMuted, UDim2.fromOffset(0, 10), UDim2.new(1,0,0,10), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
local dashFpsValue = Label(dashFpsCard, "--", 16, T.TextPrimary, UDim2.fromOffset(0, 26), UDim2.new(1,0,0,20), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
Label(dashFpsCard, "LIVE", 8, COLOR_PERF, UDim2.fromOffset(0, 50), UDim2.new(1,0,0,10), Enum.Font.GothamBold, Enum.TextXAlignment.Center)

local dashRow2 = Instance.new("Frame")
dashRow2.Size = UDim2.new(1, 0, 0, 60)
dashRow2.BackgroundTransparency = 1
dashRow2.BorderSizePixel = 0
dashRow2.Parent = TabDashboard.Scroll

local dashHalfW = math.floor((CONTENT_W - 20 - 10) / 2)
local dashGameCard = StatCard(dashRow2, { Size = UDim2.fromOffset(dashHalfW, 60), Href = function() Window:_SelectTab(TabInfo) end })
AddIconSquare(dashGameCard, COLOR_DASH, "G", 32, UDim2.fromOffset(12, 14))
Label(dashGameCard, "RESOLVED GAME", 8, T.TextMuted, UDim2.fromOffset(54, 14), UDim2.new(1, -66, 0, 10), Enum.Font.GothamBold)
local dashGameValue = Label(dashGameCard, "--", 11, T.TextPrimary, UDim2.fromOffset(54, 28), UDim2.new(1, -66, 0, 16), Enum.Font.GothamBold)

local dashPerfCard = StatCard(dashRow2, { Size = UDim2.fromOffset(dashHalfW, 60), Position = UDim2.fromOffset(dashHalfW + 10, 0), Href = function() Window:_SelectTab(TabPerf) end })
AddIconSquare(dashPerfCard, COLOR_PERF, "P", 32, UDim2.fromOffset(12, 14))
Label(dashPerfCard, "PERFORMANCE", 8, T.TextMuted, UDim2.fromOffset(54, 14), UDim2.new(1, -66, 0, 10), Enum.Font.GothamBold)
local dashPerfValue = Label(dashPerfCard, "--", 11, T.TextPrimary, UDim2.fromOffset(54, 28), UDim2.new(1, -66, 0, 16), Enum.Font.GothamBold)

local dashOverview = Panel(TabDashboard.Scroll, UDim2.new(1, 0, 0, 100))
Label(dashOverview, "Quick Overview", 12, T.TextSecondary, UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 16), Enum.Font.GothamBold)
Label(dashOverview, "Enter a key on the License tab to unlock the loaded script. Live performance and the full game library are in the sidebar.",
    10, T.TextMuted, UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 34))
local dashLicLink = Instance.new("TextButton")
dashLicLink.Size = UDim2.fromOffset(130, 16)
dashLicLink.Position = UDim2.fromOffset(14, 74)
dashLicLink.BackgroundTransparency = 1
dashLicLink.Font = Enum.Font.GothamBold
dashLicLink.TextSize = 10
dashLicLink.TextColor3 = COLOR_DASH
dashLicLink.TextXAlignment = Enum.TextXAlignment.Left
dashLicLink.Text = "MANAGE LICENSE"
dashLicLink.AutoButtonColor = false
dashLicLink.Parent = dashOverview
local dashInfoLink = Instance.new("TextButton")
dashInfoLink.Size = UDim2.fromOffset(110, 16)
dashInfoLink.Position = UDim2.fromOffset(150, 74)
dashInfoLink.BackgroundTransparency = 1
dashInfoLink.Font = Enum.Font.GothamBold
dashInfoLink.TextSize = 10
dashInfoLink.TextColor3 = COLOR_INFO
dashInfoLink.TextXAlignment = Enum.TextXAlignment.Left
dashInfoLink.Text = "SYSTEM INFO"
dashInfoLink.AutoButtonColor = false
dashInfoLink.Parent = dashOverview

-- ══════════════════════════════════════════════════════════════
--  LICENSE TAB — two states: key entry, or authenticated + live expiry.
--  Never both visible at once.
-- ══════════════════════════════════════════════════════════════
TabLicense = Window:AddTab("License", { Icon = "L", BadgeColor = COLOR_LIC })
dashLicLink.MouseButton1Click:Connect(function() Window:_SelectTab(TabLicense) end)
dashInfoLink.MouseButton1Click:Connect(function() Window:_SelectTab(TabInfo) end)

local licenseWrap = Instance.new("Frame")
licenseWrap.Size = UDim2.new(1, 0, 1, 0)
licenseWrap.BackgroundTransparency = 1
licenseWrap.BorderSizePixel = 0
licenseWrap.Parent = TabLicense.Scroll

local LIC_CARD_W = 300

local EntryView = Panel(licenseWrap, UDim2.fromOffset(LIC_CARD_W, 220), UDim2.fromOffset((CONTENT_W - 40 - LIC_CARD_W) / 2, 20))
do
    local iconCircle = Instance.new("Frame")
    iconCircle.Size = UDim2.fromOffset(48, 48)
    iconCircle.Position = UDim2.new(0.5, -24, 0, 20)
    iconCircle.BackgroundColor3 = COLOR_DASH
    iconCircle.BackgroundTransparency = 0.88
    iconCircle.BorderSizePixel = 0
    iconCircle.Parent = EntryView
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = iconCircle
    Label(iconCircle, "K", 18, COLOR_DASH, UDim2.fromOffset(0,0), UDim2.new(1,0,1,0), Enum.Font.GothamBold, Enum.TextXAlignment.Center)

    Label(EntryView, "Activate License", 13, T.TextPrimary, UDim2.fromOffset(0, 76), UDim2.new(1,0,0,16), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    Label(EntryView, "Enter your key below to unlock the system features.", 10, T.TextMuted, UDim2.fromOffset(16, 96), UDim2.new(1,-32,0,26), Enum.Font.Gotham, Enum.TextXAlignment.Center)
end

local StatusLabel = Label(EntryView, "Press Validate to check the library.", 9, T.TextMuted, UDim2.fromOffset(16, 122), UDim2.new(1,-32,0,14), Enum.Font.Gotham, Enum.TextXAlignment.Center)

local KeyInputBox = Instance.new("TextBox")
KeyInputBox.Size = UDim2.new(1, -32, 0, 34)
KeyInputBox.Position = UDim2.fromOffset(16, 142)
KeyInputBox.BackgroundColor3 = Color3.fromRGB(255,255,255)
KeyInputBox.BackgroundTransparency = 0.94
KeyInputBox.BorderSizePixel = 0
KeyInputBox.Font = Enum.Font.GothamMedium
KeyInputBox.TextSize = 11
KeyInputBox.TextColor3 = T.TextPrimary
KeyInputBox.PlaceholderText = "Enter activation key..."
KeyInputBox.PlaceholderColor3 = T.TextMuted
KeyInputBox.Text = ""
KeyInputBox.ClearTextOnFocus = false
KeyInputBox.Parent = EntryView
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = KeyInputBox
    local s = Instance.new("UIStroke"); s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = KeyInputBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.PaddingRight = UDim.new(0,10); p.Parent = KeyInputBox
end

local ValidateBtnFrame = Instance.new("TextButton")
ValidateBtnFrame.Size = UDim2.new(1, -32, 0, 36)
ValidateBtnFrame.Position = UDim2.fromOffset(16, 180)
ValidateBtnFrame.BackgroundColor3 = COLOR_DASH
ValidateBtnFrame.BackgroundTransparency = 0.8
ValidateBtnFrame.BorderSizePixel = 0
ValidateBtnFrame.AutoButtonColor = false
ValidateBtnFrame.Font = Enum.Font.GothamBold
ValidateBtnFrame.TextSize = 11
ValidateBtnFrame.TextColor3 = COLOR_DASH
ValidateBtnFrame.Text = "VALIDATE LICENSE"
ValidateBtnFrame.Parent = EntryView
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = ValidateBtnFrame
    local s = Instance.new("UIStroke"); s.Color = COLOR_DASH; s.Transparency = 0.65; s.Thickness = 1; s.Parent = ValidateBtnFrame
end

local AuthedView = Instance.new("Frame")
AuthedView.Size = UDim2.fromOffset(LIC_CARD_W, 240)
AuthedView.Position = UDim2.fromOffset((CONTENT_W - 40 - LIC_CARD_W) / 2, 20)
AuthedView.BackgroundTransparency = 1
AuthedView.BorderSizePixel = 0
AuthedView.Visible = false
AuthedView.Parent = licenseWrap

Label(AuthedView, "TIME REMAINING", 8, T.TextMuted, UDim2.fromOffset(0, 0), UDim2.new(1,0,0,10), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
local AuthedTimerLabel = Label(AuthedView, "", 22, T.TextPrimary, UDim2.fromOffset(0, 12), UDim2.new(1,0,0,30), Enum.Font.Code, Enum.TextXAlignment.Center)

local DetailsCard = Panel(AuthedView, UDim2.new(1, 0, 0, 110), UDim2.fromOffset(0, 54))
local AuthedStatusLabel = Label(DetailsCard, "Session Details", 11, COLOR_LIC, UDim2.fromOffset(14, 12), UDim2.new(1,-28,0,16), Enum.Font.GothamBold)
Label(DetailsCard, "SCRIPT TARGET", 8, T.TextMuted, UDim2.fromOffset(14, 36), UDim2.new(0.5,-14,0,12), Enum.Font.GothamBold)
local AuthedScriptValue = Label(DetailsCard, "--", 10, T.TextSecondary, UDim2.fromOffset(14, 52), UDim2.new(0.5,-14,0,14), Enum.Font.GothamMedium)
Label(DetailsCard, "GAME ID", 8, T.TextMuted, UDim2.fromOffset(0, 36), UDim2.new(0.5,-14,0,12), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
Label(DetailsCard, tostring(PlaceId), 10, T.TextSecondary, UDim2.fromOffset(0, 52), UDim2.new(1,-14,0,14), Enum.Font.GothamMedium, Enum.TextXAlignment.Right)

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
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function StartTimer(expiresAt)
    StopTimer()
    if expiresAt == nil then
        AuthedTimerLabel.Text = "∞"
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
    EntryView.Visible = false
    AuthedView.Visible = true
    AuthedScriptValue.Text = resolvedScript or "unknown"
    StartTimer(expiresAt)
    dashStatusDot.BackgroundColor3 = COLOR_LIC
    dashStatusLbl.Text = "Authenticated"
    dashKeyHintLbl.Text = resolvedScript and ("Script: " .. resolvedScript) or ""
    dashGameValue.Text = resolvedScript or tostring(PlaceId)
end

-- ══════════════════════════════════════════════════════════════
--  SETTINGS TAB — real ThemeManager functionality (dropdown, rainbow
--  accent, save/load custom), not the mockup's illustrative buttons.
-- ══════════════════════════════════════════════════════════════
TabSettings = Window:AddTab("Settings", { Icon = "S", BadgeColor = COLOR_SET })
ThemeManager:ApplyToTab(TabSettings)

-- ══════════════════════════════════════════════════════════════
--  PERFORMANCE TAB — icon rows (FPS / Ping / Memory)
-- ══════════════════════════════════════════════════════════════
TabPerf = Window:AddTab("Perf", { Icon = "P", BadgeColor = COLOR_PERF })

local function PerfRow(color, letter)
    local row = Panel(TabPerf.Scroll, UDim2.new(1, 0, 0, 58))
    AddIconSquare(row, color, letter, 40, UDim2.fromOffset(12, 9))
    local valueLbl = Label(row, "--", 15, T.TextPrimary, UDim2.fromOffset(64, 12), UDim2.new(1,-76,0,20), Enum.Font.GothamBold)
    local labelLbl = Label(row, "", 8, T.TextMuted, UDim2.fromOffset(64, 32), UDim2.new(1,-76,0,12), Enum.Font.GothamBold)
    return valueLbl, labelLbl
end

local fpsValueLbl, fpsLabelLbl = PerfRow(COLOR_PERF, "F")
fpsLabelLbl.Text = "FPS RATE"
local pingValueLbl, pingLabelLbl = PerfRow(COLOR_DASH, "N")
pingLabelLbl.Text = "ENGINE LATENCY"
local memValueLbl, memLabelLbl = PerfRow(COLOR_SET, "M")
memLabelLbl.Text = "ALLOCATED MEMORY"

task.spawn(function()
    while true do
        local statOk = pcall(function()
            local frameTime = StatsSvc.FrameTime
            local fps = frameTime > 0 and (1 / frameTime) or 0
            local fpsText = string.format("%.1f", fps)
            fpsValueLbl.Text = fpsText
            dashFpsValue.Text = tostring(math.floor(fps + 0.5))

            local pingMs = LocalPlayer:GetNetworkPing() * 1000
            pingValueLbl.Text = string.format("%d ms", math.floor(pingMs + 0.5))
            dashPerfValue.Text = string.format("%d ms", math.floor(pingMs + 0.5))

            local memMb = StatsSvc:GetTotalMemoryUsageMb()
            memValueLbl.Text = string.format("%.1f MB", memMb)
        end)
        if not statOk then break end
        task.wait(1)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  INFO TAB — live from the Worker, never a hardcoded/phantom list.
-- ══════════════════════════════════════════════════════════════
TabInfo = Window:AddTab("Info", { Icon = "I", BadgeColor = COLOR_INFO })

Label(TabInfo.Scroll, "Supported Games", 12, T.TextPrimary, UDim2.fromOffset(0,0), UDim2.new(1,0,0,16), Enum.Font.GothamBold)

local InfoStatusLabel = Label(TabInfo.Scroll, "Loading…", 10, T.TextMuted, UDim2.fromOffset(0,0), UDim2.new(1,0,0,16))
local infoEntryRows = {}

local function ClearInfoEntries()
    for _, row in ipairs(infoEntryRows) do
        pcall(function() row:Destroy() end)
    end
    infoEntryRows = {}
end

local function AddInfoRow(place)
    local label = place.displayName or ("PlaceId " .. tostring(place.placeId))
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = Color3.fromRGB(255,255,255)
    row.BackgroundTransparency = 0.96
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = TabInfo.Scroll
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = row
    local s = Instance.new("UIStroke"); s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = row

    AddIconSquare(row, COLOR_INFO, label:sub(1,1):upper(), 30, UDim2.fromOffset(10, 9))
    Label(row, label, 11, T.TextPrimary, UDim2.fromOffset(50, 8), UDim2.new(1, -130, 0, 14), Enum.Font.GothamBold)
    Label(row, "ID: " .. tostring(place.placeId), 8, T.TextMuted, UDim2.fromOffset(50, 24), UDim2.new(1, -130, 0, 12), Enum.Font.Code)

    local liveTag = Instance.new("TextLabel")
    liveTag.Size = UDim2.fromOffset(38, 14)
    liveTag.Position = UDim2.new(1, -80, 0, 17)
    liveTag.BackgroundColor3 = COLOR_INFO
    liveTag.BackgroundTransparency = 0.85
    liveTag.BorderSizePixel = 0
    liveTag.Font = Enum.Font.GothamBold
    liveTag.TextSize = 8
    liveTag.TextColor3 = COLOR_INFO
    liveTag.Text = "LIVE"
    liveTag.Parent = row
    do local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,4); c2.Parent = liveTag end

    local copyLbl = Label(row, "Copy ID", 9, T.TextMuted, UDim2.new(1, -34, 0, 17), UDim2.fromOffset(30, 14), Enum.Font.GothamBold, Enum.TextXAlignment.Right)

    row.MouseEnter:Connect(function()
        TweenSvc:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.92 }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenSvc:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.96 }):Play()
    end)
    row.MouseButton1Click:Connect(function()
        pcall(setclipboard, tostring(place.placeId))
        ShowToast("Copied Place ID: " .. tostring(place.placeId))
    end)

    table.insert(infoEntryRows, row)
end

local function RefreshInfo()
    InfoStatusLabel.Text = "Loading…"
    InfoStatusLabel.TextColor3 = T.TextMuted
    ClearInfoEntries()

    local places, truncatedOrReason = KeyAuth.ListPlaces()
    if not places then
        InfoStatusLabel.Text = "Couldn't reach the server: " .. tostring(truncatedOrReason)
        InfoStatusLabel.TextColor3 = COLOR_BAD
        return
    end

    if #places == 0 then
        InfoStatusLabel.Text = "No games currently supported yet."
        return
    end

    InfoStatusLabel.Text = tostring(#places) .. " game" .. (#places == 1 and "" or "s") .. " currently supported:"
    for _, place in ipairs(places) do
        AddInfoRow(place)
    end
end

task.spawn(RefreshInfo)

-- ══════════════════════════════════════════════════════════════
--  CLOSE / REOPEN — closes with an animation to a small draggable orb.
-- ══════════════════════════════════════════════════════════════
local ReopenOrb = nil
local ReopenWindow

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
    dot.BackgroundColor3        = COLOR_LIC
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
--  AUTH SUCCESS
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

    local key = CleanKey(KeyInputBox.Text)
    if key == "" then
        StatusLabel.Text = "Enter a key first."
        StatusLabel.TextColor3 = COLOR_BAD
        Shake(Window.Frame)
        return
    end

    validating = true
    ValidateBtnFrame.Text = "VALIDATING..."
    StatusLabel.Text = "Checking key..."
    StatusLabel.TextColor3 = T.TextMuted

    local verifyOk, reason, resolvedScript, expiresAt = KeyAuth.VerifyForPlace(PlaceId, key)

    validating = false
    if verifyOk then
        AxiUI:Notify("Access", "Key accepted.", 2)
        OnAuthenticated(key, resolvedScript, expiresAt, false)
    else
        ValidateBtnFrame.Text = "VALIDATE LICENSE"
        StatusLabel.Text = reason or "Invalid key — try again."
        StatusLabel.TextColor3 = COLOR_BAD
        dashStatusDot.BackgroundColor3 = COLOR_BAD
        dashStatusLbl.Text = "Invalid key"
        Shake(Window.Frame)
    end
end

ValidateBtnFrame.MouseButton1Click:Connect(SubmitKey)

-- ══════════════════════════════════════════════════════════════
--  SILENT PATH — a cached key from a previous validated run in THIS exact
--  game, still valid right now.
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
-- real network round-trip, and without this the raw window would flash on
-- screen for that duration before OnAuthenticated ever gets a chance to
-- hide it.
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

end)

if not ok then
    warn("[UniversalKeyGate] Failed to build UI: " .. tostring(err))
end
