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

    Visual layout is adapted from the approved Superdesign draft (project
    a5fec5c4-e974-4aa2-bd8d-b515445af6bc, draft
    3b670ab9-0f77-4b59-b00f-18d2bd4e7078, "Optimized Compact Dashboard UI"):
    near-black glass window, a Dashboard landing tab that also hosts the
    Authorization Overview (key entry, or once authenticated, a live
    tier/expiry readout -- two mutually-exclusive states, never both at
    once), Performance as icon-rows, and a live Info list with
    copy-to-clipboard. There is no separate License tab -- consolidating
    onto Dashboard keeps the sidebar to functional categories only and
    removes any chance of it highlighting a tab that doesn't match what's
    on screen. Adapted, not pixel-copied, where Roblox UI primitives don't
    have a CSS/Tailwind equivalent (no icon font, so colored circles/
    letters stand in for lucide icons; Settings keeps AxiUI's own real
    ThemeManager functionality rather than the mockup's illustrative,
    non-functional Save/Reset).

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
local Marketplace  = game:GetService("MarketplaceService")
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
        FarIntensity = on and 0.78 or 0,
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

-- Transparency capped at 60% everywhere (Alpha = 1 - Transparency, so
-- Alpha >= 0.4 throughout this file) -- an earlier pass here regressed
-- back down to the mockup's raw, uncapped CSS opacity values (0.05/0.05/
-- 0.08 = 92-95% see-through) while porting the Superdesign draft, undoing
-- an already-fixed "everything unreadable" correction from before that.
-- GroupboxBg/ElementBg (used by AxiUI's own native Groupbox/Element
-- rendering, e.g. the Settings tab's ThemeManager UI) are a DARK tint, not
-- white -- same reasoning as PANEL_TINT below: white fill under white text
-- washes out, dark fill doesn't. Border stays white/light on purpose --
-- that's the correct "light border" half of the look, only the FILL was
-- the wrong tone.
AxiUI:SetTheme({
    GroupboxBg      = Color3.fromRGB(27, 26, 24),      GroupboxBgAlpha = 0.60,
    ElementBg       = Color3.fromRGB(27, 26, 24),      ElementBgAlpha  = 0.60,
    Border          = Color3.fromRGB(255, 255, 255),   BorderAlpha     = 0.40,
})

-- Near-black glass, matching the approved design's dark gradient window,
-- but shifted neutral-warm rather than blue-black -- same reasoning as
-- COLOR_DASH/PANEL_TINT above: a blue-cast dark theme plus a blue Accent
-- (toggles/sliders/dropdown highlights all read off Accent/AccentStrong,
-- so this is the framework-wide default, not just one card) is exactly
-- the generic-AI-dark-mode look, not a deliberate choice.
ThemeManager:AddTheme("Glass", {
    WindowBg      = Color3.fromRGB(16, 15, 13),     WindowBgAlpha  = 0.97,
    Accent        = Color3.fromRGB(190, 160, 110),  AccentAlpha    = 0.30,
    AccentStrong  = Color3.fromRGB(225, 205, 165),
    TextPrimary   = Color3.fromRGB(255, 255, 255),
    TextSecondary = Color3.fromRGB(214, 212, 206),
    TextMuted     = Color3.fromRGB(176, 172, 164),
})
ThemeManager:Apply("Glass")

local T = AxiUI.Theme

-- Subtle text-shadow (Roblox TextLabel/TextButton/TextBox's own built-in
-- TextStroke, not a separate UIStroke Instance -- cheaper and this is
-- literally what it's for) applied everywhere text renders, so readability
-- holds regardless of what's behind the glass at any given moment.
-- Deliberately restrained (mostly-transparent, no glow/thick outline) --
-- a readability aid, not a visual effect of its own.
local TEXT_STROKE_TRANSPARENCY = 0.72
local TEXT_STROKE_COLOR = Color3.new(0, 0, 0)

-- Per-tab accent colors, matching the approved design (each tab keeps its
-- own hue rather than one shared accent) -- also reused for Dashboard/Info
-- card icon tints so the same color language carries through the whole UI.
--
-- These used to be Tailwind's stock blue-400/purple-400/cyan-400/etc --
-- researched afterward and confirmed that exact trio (blue/purple/cyan
-- neon-on-dark) is *the* most commonly cited "this is AI-generated" tell,
-- traced directly to those same Tailwind defaults saturating design-tool
-- training data. Replaced with a muted, warm/neutral "material" palette
-- (brass, sage, clay, slate, sand) -- no blue, no purple, no cyan, and
-- desaturated rather than the punchy stock swatch values.
local COLOR_DASH  = Color3.fromRGB(198, 165, 96)   -- brass/gold
local COLOR_LIC   = Color3.fromRGB(133, 163, 120)  -- sage
local COLOR_SET   = Color3.fromRGB(178, 108, 92)   -- clay/terracotta
local COLOR_PERF  = Color3.fromRGB(139, 152, 168)  -- slate
local COLOR_INFO  = Color3.fromRGB(168, 154, 132)  -- sand
local COLOR_BAD   = Color3.fromRGB(220, 120, 108)

-- Panel fill tint. Researched glassmorphism guidance is explicit that the
-- glass tint has to match the text tone: light text (our theme) needs a
-- DARK glass tint, not a white one -- a white fill at any opacity high
-- enough to be legible with no real blur behind it (Roblox has none, see
-- SetBlur's own comment) just washes out into a milky haze, which is
-- exactly what pure-white panel fills at raised opacity were doing here.
-- Dark base, slightly lighter than the window itself so panels still read
-- as a distinct raised surface. Neutral-warm charcoal, not a blue-black --
-- the old (26,29,39) had a cool blue cast (B > G > R) that reinforced the
-- same generic-AI-dark-mode look the accent colors above just moved away
-- from.
local PANEL_TINT = Color3.fromRGB(27, 26, 24)

-- Blends PANEL_TINT toward an accent color by `amount` -- a subtly colored
-- DARK glass (the "colored tint" variant the research calls out) rather
-- than a plain neutral dark panel, for tinted cards like the License
-- status card.
local function DarkTint(color, amount)
    amount = amount or 0.18
    return Color3.new(
        PANEL_TINT.R + (color.R - PANEL_TINT.R) * amount,
        PANEL_TINT.G + (color.G - PANEL_TINT.G) * amount,
        PANEL_TINT.B + (color.B - PANEL_TINT.B) * amount
    )
end

-- ══════════════════════════════════════════════════════════════
--  WINDOW
-- ══════════════════════════════════════════════════════════════
local SIDEBAR_W  = 160
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

-- Diagonal glass sheen -- a UIGradient modulates Window.Frame's OWN
-- background, so it's only actually visible in the plain gaps between
-- cards (any card sitting on top masks it there), which is exactly the
-- "glass effect on the non-text, non-box parts" being asked for. Nudged
-- more visible than the original near-invisible pass (94-98.5%
-- transparent), still restrained -- a highlight, not a strong effect.
do
    local sheen = Instance.new("UIGradient")
    sheen.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 255, 255)),
        ColorSequenceKeypoint.new(1,   Color3.fromRGB(215, 200, 175)),
    })
    sheen.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0,   0.86),
        NumberSequenceKeypoint.new(0.5, 0.95),
        NumberSequenceKeypoint.new(1,   0.86),
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
AvatarImg.BackgroundColor3      = PANEL_TINT
AvatarImg.BackgroundTransparency = 0.40
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
GreetingLbl.TextStrokeColor3       = TEXT_STROKE_COLOR
GreetingLbl.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
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
SubLbl.Text                   = "Loading game…"
SubLbl.TextStrokeColor3       = TEXT_STROKE_COLOR
SubLbl.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
SubLbl.Parent                 = HeaderRow

-- The actual game name, not the raw PlaceId -- MarketplaceService's
-- GetProductInfo works for a PlaceId (a place is an asset in Roblox's
-- catalog system), confirmed against the DevForum's own accepted answer
-- before using it here. Yields (real HTTP call), so it runs on its own
-- thread same as the avatar fetch above, and is pcall-wrapped since it
-- can rate-limit/fail like any other MarketplaceService call.
task.spawn(function()
    local nameOk, info = pcall(Marketplace.GetProductInfo, Marketplace, PlaceId)
    if nameOk and info and info.Name and info.Name ~= "" then
        SubLbl.Text = info.Name
    else
        SubLbl.Text = "Place " .. tostring(PlaceId)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  SMALL VISUAL HELPERS
-- ══════════════════════════════════════════════════════════════
local function Panel(parent, size, position)
    local p = Instance.new("Frame")
    p.Size                   = size
    p.Position               = position or UDim2.fromOffset(0, 0)
    p.BackgroundColor3       = PANEL_TINT
    p.BackgroundTransparency = 0.40
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
    card.BackgroundColor3       = opts.Tint and DarkTint(opts.Tint) or PANEL_TINT
    card.BackgroundTransparency = 0.40
    card.BorderSizePixel        = 0
    card.Parent                 = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = card
    local strokeColor = opts.Tint or T.Border
    local s = Instance.new("UIStroke")
    s.Color = strokeColor; s.Transparency = opts.Tint and 0.55 or (1 - T.BorderAlpha); s.Thickness = 1; s.Parent = card

    if opts.Href then
        card.MouseEnter:Connect(function()
            TweenSvc:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.28 }):Play()
        end)
        card.MouseLeave:Connect(function()
            TweenSvc:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.40 }):Play()
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
    sq.BackgroundTransparency = 0.55
    sq.BorderSizePixel        = 0
    sq.Parent                 = parent
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, math.floor(size * 0.3)); c.Parent = sq
    local s = Instance.new("UIStroke")
    s.Color = color; s.Transparency = 0.5; s.Thickness = 1; s.Parent = sq
    local lbl = Instance.new("TextLabel")
    lbl.Size                   = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font                   = Enum.Font.GothamBold
    lbl.TextSize               = math.floor(size * 0.4)
    lbl.TextColor3             = color
    lbl.Text                   = letter
    lbl.TextStrokeColor3       = TEXT_STROKE_COLOR
    lbl.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
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
    l.TextStrokeColor3       = TEXT_STROKE_COLOR
    l.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
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
Toast.BackgroundColor3        = PANEL_TINT
Toast.BackgroundTransparency  = 0.35
Toast.BorderSizePixel         = 0
Toast.Font                    = Enum.Font.GothamBold
Toast.TextSize                = 12
Toast.TextColor3              = T.TextPrimary
Toast.Text                    = ""
Toast.TextStrokeColor3        = TEXT_STROKE_COLOR
Toast.TextStrokeTransparency  = TEXT_STROKE_TRANSPARENCY
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

-- Forward-declared: Dashboard's cards (built below) link to Performance/
-- Info, defined later in the file. A click handler closure resolves a
-- free variable lexically at the point it's DEFINED -- without this,
-- TabPerf/TabInfo wouldn't exist as locals yet when these closures are
-- created, so they'd silently capture globals (nil) instead of the real
-- tab objects, and clicking those cards would throw inside
-- Window:_SelectTab(nil).
local TabDashboard, TabSettings, TabPerf, TabInfo

-- ══════════════════════════════════════════════════════════════
--  DASHBOARD TAB — also houses the Authorization Overview (key entry /
--  live session + timer) directly, so all session telemetry lives on the
--  landing view. There is no separate License tab: one fewer sidebar
--  entry, and no risk of the sidebar highlighting a tab that doesn't
--  match what's on screen.
--
--  Every row below is full-width (UDim2.new(1,0,...)) so it lines up
--  edge-to-edge with every other row -- no row is ever narrower than the
--  content area and centered inside leftover space.
-- ══════════════════════════════════════════════════════════════
TabDashboard = Window:AddTab("Dashboard")

-- ── Authorization Overview: one full-width compact row, two mutually
-- exclusive states (icon + status text on the left, the state-specific
-- controls anchored to the right edge via Scale so they stay flush
-- regardless of exact width).
local licenseWrap = Instance.new("Frame")
licenseWrap.Size = UDim2.new(1, 0, 0, 76)
licenseWrap.BackgroundTransparency = 1
licenseWrap.BorderSizePixel = 0
licenseWrap.Parent = TabDashboard.Scroll

local EntryView = Panel(licenseWrap, UDim2.new(1, 0, 1, 0))
do
    local icon = Instance.new("Frame")
    icon.Size = UDim2.fromOffset(36, 36)
    icon.Position = UDim2.fromOffset(14, 20)
    icon.BackgroundColor3 = COLOR_DASH
    icon.BackgroundTransparency = 0.55
    icon.BorderSizePixel = 0
    icon.Parent = EntryView
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = icon
    Label(icon, "K", 14, COLOR_DASH, UDim2.fromOffset(0,0), UDim2.new(1,0,1,0), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
end
Label(EntryView, "Activate License", 12, T.TextPrimary, UDim2.fromOffset(60, 14), UDim2.fromOffset(220, 16), Enum.Font.GothamBold)
local StatusLabel = Label(EntryView, "Enter your key to unlock the system.", 9, T.TextMuted, UDim2.fromOffset(60, 32), UDim2.fromOffset(220, 14), Enum.Font.Gotham)

local KeyInputBox = Instance.new("TextBox")
KeyInputBox.Size = UDim2.new(1, -440, 0, 34)
KeyInputBox.Position = UDim2.fromOffset(290, 21)
KeyInputBox.BackgroundColor3 = PANEL_TINT
KeyInputBox.BackgroundTransparency = 0.35
KeyInputBox.BorderSizePixel = 0
KeyInputBox.Font = Enum.Font.GothamMedium
KeyInputBox.TextSize = 11
KeyInputBox.TextColor3 = T.TextPrimary
KeyInputBox.PlaceholderText = "Enter activation key..."
KeyInputBox.PlaceholderColor3 = T.TextMuted
KeyInputBox.Text = ""
KeyInputBox.TextStrokeColor3 = TEXT_STROKE_COLOR
KeyInputBox.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
KeyInputBox.ClearTextOnFocus = false
KeyInputBox.Parent = EntryView
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = KeyInputBox
    local s = Instance.new("UIStroke"); s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = KeyInputBox
    local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0,10); p.PaddingRight = UDim.new(0,10); p.Parent = KeyInputBox
end

-- The one true primary action in this view -- deliberately NOT the same
-- passive glass treatment as every card/panel around it (that uniform
-- translucency-on-everything is a known generic-AI-design tell). Solid,
-- dark-tinted fill + plain high-contrast text reads as a committed button
-- instead of another floating glass tile.
local ValidateBtnFrame = Instance.new("TextButton")
ValidateBtnFrame.Size = UDim2.fromOffset(122, 34)
ValidateBtnFrame.Position = UDim2.new(1, -136, 0, 21)
ValidateBtnFrame.BackgroundColor3 = DarkTint(COLOR_DASH, 0.45)
ValidateBtnFrame.BackgroundTransparency = 0.12
ValidateBtnFrame.BorderSizePixel = 0
ValidateBtnFrame.AutoButtonColor = false
ValidateBtnFrame.Font = Enum.Font.GothamBold
ValidateBtnFrame.TextSize = 11
ValidateBtnFrame.TextColor3 = T.TextPrimary
ValidateBtnFrame.Text = "VALIDATE"
ValidateBtnFrame.TextStrokeColor3 = TEXT_STROKE_COLOR
ValidateBtnFrame.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
ValidateBtnFrame.Parent = EntryView
do
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = ValidateBtnFrame
    local s = Instance.new("UIStroke"); s.Color = COLOR_DASH; s.Transparency = 0.35; s.Thickness = 1; s.Parent = ValidateBtnFrame
end

local AuthedView = Panel(licenseWrap, UDim2.new(1, 0, 1, 0))
AuthedView.Visible = false
do
    local icon = Instance.new("Frame")
    icon.Size = UDim2.fromOffset(36, 36)
    icon.Position = UDim2.fromOffset(14, 20)
    icon.BackgroundColor3 = COLOR_LIC
    icon.BackgroundTransparency = 0.55
    icon.BorderSizePixel = 0
    icon.Parent = AuthedView
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1,0); c.Parent = icon
    Label(icon, "K", 14, COLOR_LIC, UDim2.fromOffset(0,0), UDim2.new(1,0,1,0), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
end
Label(AuthedView, "Active License", 12, T.TextPrimary, UDim2.fromOffset(60, 14), UDim2.fromOffset(220, 16), Enum.Font.GothamBold)
-- Authorization tier -- this system is single-tier today, so the label is
-- a constant, not fetched data; still surfaced explicitly so the
-- authenticated view always shows what level of access is active.
Label(AuthedView, "BASIC ACCESS", 9, COLOR_LIC, UDim2.fromOffset(60, 32), UDim2.fromOffset(220, 14), Enum.Font.GothamBold)
Label(AuthedView, "TIME REMAINING", 8, T.TextMuted, UDim2.new(1, -180, 0, 16), UDim2.fromOffset(166, 10), Enum.Font.GothamBold, Enum.TextXAlignment.Right)
local AuthedTimerLabel = Label(AuthedView, "", 20, T.TextPrimary, UDim2.new(1, -180, 0, 28), UDim2.fromOffset(166, 28), Enum.Font.Code, Enum.TextXAlignment.Right)

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

-- Converts raw remaining milliseconds into HH:MM:SS, flipping to
-- "EXPIRED" once the deadline has passed.
local function FormatRemaining(msRemaining)
    if msRemaining <= 0 then return "EXPIRED" end
    local totalSeconds = math.floor(msRemaining / 1000)
    local h = math.floor(totalSeconds / 3600)
    local m = math.floor((totalSeconds % 3600) / 60)
    local s = totalSeconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Lightweight background loop: recomputes remaining = expiresAt - now
-- every second and refreshes the label, rather than counting down a
-- locally-cached duration (which would drift/desync from the server).
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
    StartTimer(expiresAt)
end

-- ── Stats row: FPS / Ping / Memory as three equal columns via a real
-- UIListLayout (Scale-sized children), not manually computed pixel
-- offsets -- so the row always divides evenly regardless of width.
local dashStatsRow = Instance.new("Frame")
dashStatsRow.Size = UDim2.new(1, 0, 0, 74)
dashStatsRow.BackgroundTransparency = 1
dashStatsRow.BorderSizePixel = 0
dashStatsRow.Parent = TabDashboard.Scroll
do
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding = UDim.new(0, 10)
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = dashStatsRow
end

-- Three real, already-computed metrics -- same color per metric as the
-- Performance tab's own rows (orange/blue/purple), not arbitrary or
-- decorative. Values are filled in by the Performance tab's task.spawn
-- loop below (dashFpsValue/dashPingValue/dashMemValue), the same pattern
-- already used for FPS.
local dashFpsCard = StatCard(dashStatsRow, { Size = UDim2.new(1/3, -7, 1, 0), Href = function() Window:_SelectTab(TabPerf) end })
AddIconSquare(dashFpsCard, COLOR_PERF, "F", 32, UDim2.fromOffset(12, 14))
Label(dashFpsCard, "FPS", 8, T.TextMuted, UDim2.fromOffset(54, 14), UDim2.new(1, -66, 0, 10), Enum.Font.GothamBold)
local dashFpsValue = Label(dashFpsCard, "--", 11, T.TextPrimary, UDim2.fromOffset(54, 28), UDim2.new(1, -66, 0, 16), Enum.Font.GothamBold)

local dashPingCard = StatCard(dashStatsRow, { Size = UDim2.new(1/3, -7, 1, 0), Href = function() Window:_SelectTab(TabPerf) end })
AddIconSquare(dashPingCard, COLOR_DASH, "N", 32, UDim2.fromOffset(12, 14))
Label(dashPingCard, "LATENCY", 8, T.TextMuted, UDim2.fromOffset(54, 14), UDim2.new(1, -66, 0, 10), Enum.Font.GothamBold)
local dashPingValue = Label(dashPingCard, "--", 11, T.TextPrimary, UDim2.fromOffset(54, 28), UDim2.new(1, -66, 0, 16), Enum.Font.GothamBold)

local dashMemCard = StatCard(dashStatsRow, { Size = UDim2.new(1/3, -7, 1, 0), Href = function() Window:_SelectTab(TabPerf) end })
AddIconSquare(dashMemCard, COLOR_SET, "M", 32, UDim2.fromOffset(12, 14))
Label(dashMemCard, "MEMORY", 8, T.TextMuted, UDim2.fromOffset(54, 14), UDim2.new(1, -66, 0, 10), Enum.Font.GothamBold)
local dashMemValue = Label(dashMemCard, "--", 11, T.TextPrimary, UDim2.fromOffset(54, 28), UDim2.new(1, -66, 0, 16), Enum.Font.GothamBold)

local dashOverview = Panel(TabDashboard.Scroll, UDim2.new(1, 0, 0, 100))
Label(dashOverview, "Quick Overview", 12, T.TextSecondary, UDim2.fromOffset(14, 12), UDim2.new(1, -28, 0, 16), Enum.Font.GothamBold)
-- Live library count -- set by RefreshInfo (Info tab, built later) off the
-- same GET /api/places/list result the Info tab itself lists, not a
-- second guess at the number.
local dashLibraryCountLbl = Label(dashOverview, "Loading library…", 10, COLOR_INFO, UDim2.fromOffset(14, 32), UDim2.new(1, -28, 0, 14), Enum.Font.GothamBold)
Label(dashOverview, "Live performance stats are on the Performance tab.", 10, T.TextMuted, UDim2.fromOffset(14, 48), UDim2.new(1, -28, 0, 14))
local dashInfoLink = Instance.new("TextButton")
dashInfoLink.Size = UDim2.fromOffset(110, 16)
dashInfoLink.Position = UDim2.fromOffset(14, 74)
dashInfoLink.BackgroundTransparency = 1
dashInfoLink.Font = Enum.Font.GothamBold
dashInfoLink.TextSize = 10
dashInfoLink.TextColor3 = COLOR_INFO
dashInfoLink.TextXAlignment = Enum.TextXAlignment.Left
dashInfoLink.Text = "SYSTEM INFO"
dashInfoLink.AutoButtonColor = false
dashInfoLink.Parent = dashOverview
dashInfoLink.MouseButton1Click:Connect(function() Window:_SelectTab(TabInfo) end)

-- ══════════════════════════════════════════════════════════════
--  SETTINGS TAB — real ThemeManager functionality (dropdown, rainbow
--  accent, save/load custom), not the mockup's illustrative buttons.
-- ══════════════════════════════════════════════════════════════
TabSettings = Window:AddTab("Settings")
ThemeManager:ApplyToTab(TabSettings)

-- ══════════════════════════════════════════════════════════════
--  PERFORMANCE TAB — icon rows (FPS / Ping / Memory)
-- ══════════════════════════════════════════════════════════════
TabPerf = Window:AddTab("Performance")

local function PerfRow(color, letter)
    local row = Panel(TabPerf.Scroll, UDim2.new(1, 0, 0, 58))
    AddIconSquare(row, color, letter, 40, UDim2.fromOffset(12, 9))
    local valueLbl = Label(row, "--", 15, T.TextPrimary, UDim2.fromOffset(64, 12), UDim2.new(1,-76,0,20), Enum.Font.GothamBold)
    local labelLbl = Label(row, "", 8, T.TextMuted, UDim2.fromOffset(64, 32), UDim2.new(1,-76,0,12), Enum.Font.GothamBold)
    return valueLbl, labelLbl
end

local fpsValueLbl, fpsLabelLbl = PerfRow(COLOR_PERF, "F")
fpsLabelLbl.Text = "FPS"
local pingValueLbl, pingLabelLbl = PerfRow(COLOR_DASH, "N")
pingLabelLbl.Text = "LATENCY"
local memValueLbl, memLabelLbl = PerfRow(COLOR_SET, "M")
memLabelLbl.Text = "MEMORY"

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
            dashPingValue.Text = string.format("%d ms", math.floor(pingMs + 0.5))

            local memMb = StatsSvc:GetTotalMemoryUsageMb()
            memValueLbl.Text = string.format("%.1f MB", memMb)
            dashMemValue.Text = string.format("%.1f MB", memMb)
        end)
        if not statOk then break end
        task.wait(1)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  INFO TAB — live from the Worker, never a hardcoded/phantom list.
-- ══════════════════════════════════════════════════════════════
TabInfo = Window:AddTab("Info")

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
    -- Never permanently shows a raw PlaceId as the name -- if the Worker
    -- has no admin-set displayName for this mapping, fetch the real game
    -- name via MarketplaceService (a Place is an asset in Roblox's
    -- catalog, so GetProductInfo works on a PlaceId; confirmed against
    -- the DevForum's accepted answer before using it). "Place <id>" is
    -- only ever a brief placeholder while that fetch is in flight.
    local hasDisplayName = place.displayName ~= nil
    local label = place.displayName or ("Place " .. tostring(place.placeId))
    local row = Instance.new("TextButton")
    row.Size = UDim2.new(1, 0, 0, 48)
    row.BackgroundColor3 = PANEL_TINT
    row.BackgroundTransparency = 0.40
    row.BorderSizePixel = 0
    row.Text = ""
    row.AutoButtonColor = false
    row.Parent = TabInfo.Scroll
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = row
    local s = Instance.new("UIStroke"); s.Color = T.Border; s.Transparency = 1 - T.BorderAlpha; s.Thickness = 1; s.Parent = row

    AddIconSquare(row, COLOR_INFO, label:sub(1,1):upper(), 30, UDim2.fromOffset(10, 9))
    local nameLbl = Label(row, label, 11, T.TextPrimary, UDim2.fromOffset(50, 8), UDim2.new(1, -130, 0, 14), Enum.Font.GothamBold)
    Label(row, "ID: " .. tostring(place.placeId), 8, T.TextMuted, UDim2.fromOffset(50, 24), UDim2.new(1, -130, 0, 12), Enum.Font.Code)

    if not hasDisplayName then
        task.spawn(function()
            local nameOk, info = pcall(Marketplace.GetProductInfo, Marketplace, place.placeId)
            if nameOk and info and info.Name and info.Name ~= "" then
                nameLbl.Text = info.Name
            end
        end)
    end

    local liveTag = Instance.new("TextLabel")
    liveTag.Size = UDim2.fromOffset(38, 14)
    liveTag.Position = UDim2.new(1, -80, 0, 17)
    liveTag.BackgroundColor3 = COLOR_INFO
    liveTag.BackgroundTransparency = 0.5
    liveTag.BorderSizePixel = 0
    liveTag.Font = Enum.Font.GothamBold
    liveTag.TextSize = 8
    liveTag.TextColor3 = COLOR_INFO
    liveTag.Text = "LIVE"
    liveTag.TextStrokeColor3 = TEXT_STROKE_COLOR
    liveTag.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
    liveTag.Parent = row
    do local c2 = Instance.new("UICorner"); c2.CornerRadius = UDim.new(0,4); c2.Parent = liveTag end

    local copyLbl = Label(row, "Copy ID", 9, T.TextMuted, UDim2.new(1, -34, 0, 17), UDim2.fromOffset(30, 14), Enum.Font.GothamBold, Enum.TextXAlignment.Right)

    row.MouseEnter:Connect(function()
        TweenSvc:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.28 }):Play()
    end)
    row.MouseLeave:Connect(function()
        TweenSvc:Create(row, TweenInfo.new(0.15, Enum.EasingStyle.Exponential), { BackgroundTransparency = 0.40 }):Play()
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
        dashLibraryCountLbl.Text = "Library unavailable right now."
        return
    end

    if #places == 0 then
        InfoStatusLabel.Text = "No games currently supported yet."
        dashLibraryCountLbl.Text = "No games in the library yet."
        return
    end

    local countPhrase = tostring(#places) .. " game" .. (#places == 1 and "" or "s")
    InfoStatusLabel.Text = countPhrase .. " currently supported:"
    dashLibraryCountLbl.Text = countPhrase .. " supported in the library."
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

-- Wires the title bar's close button (added at the fork level) to the
-- same minimize-to-orb animation used everywhere else the window closes
-- -- without this, removing the macOS dots left no way to close the
-- window at all once it's been reopened from the orb (the auto-close
-- only ever fires once, right after a fresh key validates).
Window.OnClose = CloseToOrb

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
        ValidateBtnFrame.Text = "VALIDATE"
        StatusLabel.Text = reason or "Invalid key — try again."
        StatusLabel.TextColor3 = COLOR_BAD
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
