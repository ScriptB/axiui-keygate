--[[
    AxiUI — Semi-Translucent Nested UI Library v1.0.0
    A clean, professional Roblox executor UI framework.

    Load order (each is optional beyond Framework):
        local AxiUI  = loadstring(game:HttpGet("...AxiUI_Framework.lua"))()
        -- optionally:
        loadstring(game:HttpGet("...AxiUI_ThemeManager.lua"))()
        loadstring(game:HttpGet("...AxiUI_InterfaceManager.lua"))()

    Usage:
        local Window = AxiUI:CreateWindow({ Title = "MyScript", Width = 420 })
        local Tab    = Window:AddTab("Combat")
        local Box    = Tab:AddGroupbox("Aimbot")
        Box:AddToggle("SilentAim", { Text = "Silent Aim", Default = false,
            Callback = function(v) print("Silent Aim:", v) end })
        Box:AddSlider("FOV", { Text = "FOV", Default = 120, Min = 10, Max = 300 })
]]

local AxiUI       = {}
AxiUI.__index     = AxiUI
AxiUI.Windows     = {}
AxiUI.Flags       = {}
AxiUI.Connections = {}
AxiUI.Version     = "1.0.0"

-- ═══════════════════════════════════════════════════════════════
--  DEFAULT THEME
--  Translucency stack (bottom → top):
--    Game world → Window (82% opaque) → Groupbox (3.5% tint)
--    → Element row (3% tint) → SubBox (2.5% tint)
--  One accent colour (soft lavender). Everything else is neutral.
-- ═══════════════════════════════════════════════════════════════
AxiUI.Theme = {
    WindowBg        = Color3.fromRGB(14,  16,  26),   WindowBgAlpha   = 0.82,
    GroupboxBg      = Color3.fromRGB(255, 255, 255),   GroupboxBgAlpha = 0.035,
    ElementBg       = Color3.fromRGB(255, 255, 255),   ElementBgAlpha  = 0.03,
    SubBoxBg        = Color3.fromRGB(255, 255, 255),   SubBoxBgAlpha   = 0.025,
    Accent          = Color3.fromRGB(160, 130, 255),   AccentAlpha     = 0.35,
    AccentStrong    = Color3.fromRGB(200, 185, 255),
    Border          = Color3.fromRGB(255, 255, 255),   BorderAlpha     = 0.08,
    TextPrimary     = Color3.fromRGB(220, 215, 255),
    TextSecondary   = Color3.fromRGB(140, 130, 160),
    TextMuted       = Color3.fromRGB(80,  75,  100),
    RadiusWindow    = UDim.new(0, 12),
    RadiusGroupbox  = UDim.new(0, 8),
    RadiusElement   = UDim.new(0, 6),
    RadiusSubBox    = UDim.new(0, 6),
    RadiusPill      = UDim.new(1, 0),
}

-- ═══════════════════════════════════════════════════════════════
--  SERVICES
-- ═══════════════════════════════════════════════════════════════
local TweenSvc  = game:GetService("TweenService")
local UIS       = game:GetService("UserInputService")
local HttpSvc   = game:GetService("HttpService")
local Players   = game:GetService("Players")
local RunSvc    = game:GetService("RunService")

-- ═══════════════════════════════════════════════════════════════
--  INTERNAL HELPERS
-- ═══════════════════════════════════════════════════════════════
local T = AxiUI.Theme  -- live reference; mutates with SetTheme

local function Tween(obj, props, t, style)
    TweenSvc:Create(obj,
        TweenInfo.new(t or 0.15, style or Enum.EasingStyle.Quart),
        props):Play()
end

local function AddCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = radius or T.RadiusElement
    c.Parent = parent
    return c
end

local function AddStroke(parent, color, alpha, thickness)
    local s = Instance.new("UIStroke")
    s.Color           = color or T.Border
    s.Transparency    = 1 - (alpha or T.BorderAlpha)
    s.Thickness       = thickness or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent          = parent
    return s
end

local function AddList(parent, pad, dir)
    local l = Instance.new("UIListLayout")
    l.Padding       = UDim.new(0, pad or 4)
    l.SortOrder     = Enum.SortOrder.LayoutOrder
    l.FillDirection = dir or Enum.FillDirection.Vertical
    l.Parent        = parent
    return l
end

local function AddPad(parent, all, t, b, l, r)
    local p = Instance.new("UIPadding")
    if all then
        p.PaddingTop = UDim.new(0,all); p.PaddingBottom = UDim.new(0,all)
        p.PaddingLeft = UDim.new(0,all); p.PaddingRight = UDim.new(0,all)
    else
        if t then p.PaddingTop    = UDim.new(0,t) end
        if b then p.PaddingBottom = UDim.new(0,b) end
        if l then p.PaddingLeft   = UDim.new(0,l) end
        if r then p.PaddingRight  = UDim.new(0,r) end
    end
    p.Parent = parent
    return p
end

local function MakeLabel(parent, text, size, color, xAlign, font)
    local l = Instance.new("TextLabel")
    l.Text                  = text or ""
    l.Font                  = font or Enum.Font.GothamMedium
    l.TextSize              = size or 11
    l.TextColor3            = color or T.TextSecondary
    l.BackgroundTransparency = 1
    l.BorderSizePixel       = 0
    l.TextXAlignment        = xAlign or Enum.TextXAlignment.Left
    l.TextTruncate          = Enum.TextTruncate.AtEnd
    l.Parent                = parent
    return l
end

local function MakeElementRow(parent, height)
    local row = Instance.new("Frame")
    row.BackgroundColor3      = T.ElementBg
    row.BackgroundTransparency = 1 - T.ElementBgAlpha
    row.BorderSizePixel       = 0
    row.Size                  = UDim2.new(1, 0, 0, height or 30)
    row.Parent                = parent
    AddCorner(row, T.RadiusElement)
    AddStroke(row)
    return row
end

local function TrackConn(conn)
    table.insert(AxiUI.Connections, conn)
    return conn
end

-- Safe gui parent (executor → CoreGui → PlayerGui)
local function SafeParent(gui)
    local ok = pcall(function()
        if typeof(gethui) == "function" then
            gui.Parent = gethui()
        else
            gui.Parent = game:GetService("CoreGui")
        end
    end)
    if not ok or not gui.Parent then
        gui.Parent = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
            or Players.LocalPlayer.PlayerGui
    end
end

-- ═══════════════════════════════════════════════════════════════
--  POPUP LAYER  (dropdown lists, colour pickers)
--  One ScreenGui above everything; each popup manages itself.
-- ═══════════════════════════════════════════════════════════════
local _popupSG
local function GetPopupSG()
    if _popupSG and _popupSG.Parent then return _popupSG end
    _popupSG = Instance.new("ScreenGui")
    _popupSG.Name           = "AxiUI_Popups"
    _popupSG.ResetOnSpawn   = false
    _popupSG.IgnoreGuiInset = true
    _popupSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _popupSG.DisplayOrder   = 10100
    SafeParent(_popupSG)
    return _popupSG
end

local function MakeOverlay(onClose)
    local sg  = GetPopupSG()
    local ov  = Instance.new("TextButton")
    ov.Size   = UDim2.new(1,0,1,0)
    ov.BackgroundTransparency = 1
    ov.Text   = ""
    ov.ZIndex = 98
    ov.BorderSizePixel = 0
    ov.Parent = sg
    ov.MouseButton1Click:Connect(function()
        ov:Destroy()
        if onClose then onClose() end
    end)
    return ov
end

-- ═══════════════════════════════════════════════════════════════
--  COLOUR PICKER POPUP
-- ═══════════════════════════════════════════════════════════════
local function BuildColourPopup(anchor, initColor, onChange, onClose)
    local sg = GetPopupSG()
    local h, s, v = initColor:ToHSV()
    local W, SVH, HUEH = 188, 132, 12

    local obj  -- forward-declared so overlay click can call obj:Destroy()
    local ov = MakeOverlay(function()
        if obj then obj:Destroy() end
    end)

    local ap = anchor.AbsolutePosition
    local as = anchor.AbsoluteSize

    local popup = Instance.new("Frame")
    popup.BackgroundColor3      = T.WindowBg
    popup.BackgroundTransparency = 0.04
    popup.BorderSizePixel       = 0
    popup.Size                  = UDim2.fromOffset(W, SVH + HUEH + 46)
    popup.Position              = UDim2.fromOffset(ap.X, ap.Y + as.Y + 4)
    popup.ZIndex                = 99
    popup.Parent                = sg
    AddCorner(popup, UDim.new(0,8))
    AddStroke(popup, T.Border, 0.12)
    AddPad(popup, 8)
    AddList(popup, 6)

    -- SV square
    local svBase = Instance.new("Frame")
    svBase.BackgroundColor3 = Color3.fromHSV(h,1,1)
    svBase.BorderSizePixel  = 0
    svBase.Size             = UDim2.new(1,0,0,SVH)
    svBase.ZIndex           = 100
    svBase.Parent           = popup
    AddCorner(svBase, UDim.new(0,4))

    local whiteOv = Instance.new("Frame")
    whiteOv.BackgroundColor3 = Color3.new(1,1,1)
    whiteOv.BorderSizePixel  = 0
    whiteOv.Size             = UDim2.new(1,0,1,0)
    whiteOv.ZIndex           = 101
    whiteOv.Parent           = svBase
    AddCorner(whiteOv, UDim.new(0,4))
    do
        local g = Instance.new("UIGradient")
        g.Color        = ColorSequence.new(Color3.new(1,1,1))
        g.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 1),
        })
        g.Rotation = 0
        g.Parent   = whiteOv
    end

    local blackOv = Instance.new("Frame")
    blackOv.BackgroundColor3 = Color3.new(0,0,0)
    blackOv.BorderSizePixel  = 0
    blackOv.Size             = UDim2.new(1,0,1,0)
    blackOv.ZIndex           = 102
    blackOv.Parent           = svBase
    AddCorner(blackOv, UDim.new(0,4))
    do
        local g = Instance.new("UIGradient")
        g.Color        = ColorSequence.new(Color3.new(0,0,0))
        g.Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(1, 0),
        })
        g.Rotation = 90
        g.Parent   = blackOv
    end

    local svKnob = Instance.new("Frame")
    svKnob.BackgroundColor3 = Color3.new(1,1,1)
    svKnob.BorderSizePixel  = 0
    svKnob.Size             = UDim2.fromOffset(10,10)
    svKnob.AnchorPoint      = Vector2.new(0.5,0.5)
    svKnob.Position         = UDim2.new(s, 0, 1-v, 0)
    svKnob.ZIndex           = 104
    svKnob.Parent           = svBase
    AddCorner(svKnob, UDim.new(1,0))
    AddStroke(svKnob, Color3.new(0,0,0), 0.25, 1)

    -- Hue bar
    local hueBar = Instance.new("Frame")
    hueBar.BackgroundColor3 = Color3.new(1,1,1)
    hueBar.BorderSizePixel  = 0
    hueBar.Size             = UDim2.new(1,0,0,HUEH)
    hueBar.ZIndex           = 100
    hueBar.Parent           = popup
    AddCorner(hueBar, UDim.new(1,0))
    do
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0,   Color3.fromRGB(255,0,0)),
            ColorSequenceKeypoint.new(1/6, Color3.fromRGB(255,255,0)),
            ColorSequenceKeypoint.new(2/6, Color3.fromRGB(0,255,0)),
            ColorSequenceKeypoint.new(3/6, Color3.fromRGB(0,255,255)),
            ColorSequenceKeypoint.new(4/6, Color3.fromRGB(0,0,255)),
            ColorSequenceKeypoint.new(5/6, Color3.fromRGB(255,0,255)),
            ColorSequenceKeypoint.new(1,   Color3.fromRGB(255,0,0)),
        })
        g.Parent = hueBar
    end
    local hueKnob = Instance.new("Frame")
    hueKnob.BackgroundColor3 = Color3.new(1,1,1)
    hueKnob.BorderSizePixel  = 0
    hueKnob.Size             = UDim2.fromOffset(HUEH, HUEH)
    hueKnob.AnchorPoint      = Vector2.new(0.5,0.5)
    hueKnob.Position         = UDim2.new(h, 0, 0.5, 0)
    hueKnob.ZIndex           = 101
    hueKnob.Parent           = hueBar
    AddCorner(hueKnob, UDim.new(1,0))
    AddStroke(hueKnob, Color3.new(0,0,0), 0.25, 1)

    -- Hex row
    local hexRow = Instance.new("Frame")
    hexRow.BackgroundTransparency = 1
    hexRow.BorderSizePixel        = 0
    hexRow.Size                   = UDim2.new(1,0,0,22)
    hexRow.ZIndex                 = 100
    hexRow.Parent                 = popup
    AddList(hexRow, 6, Enum.FillDirection.Horizontal)

    local hexBox = Instance.new("TextBox")
    hexBox.Size             = UDim2.new(1,-32,1,0)
    hexBox.Font             = Enum.Font.Code
    hexBox.TextSize         = 10
    hexBox.TextColor3       = T.TextPrimary
    hexBox.PlaceholderColor3 = T.TextMuted
    hexBox.PlaceholderText  = "RRGGBB"
    hexBox.BackgroundColor3 = Color3.fromRGB(255,255,255)
    hexBox.BackgroundTransparency = 0.95
    hexBox.BorderSizePixel  = 0
    hexBox.ClearTextOnFocus = false
    hexBox.ZIndex           = 101
    hexBox.Parent           = hexRow
    AddCorner(hexBox, UDim.new(0,4)); AddPad(hexBox, nil,0,0,6,0)

    local swatch = Instance.new("Frame")
    swatch.BackgroundColor3 = Color3.fromHSV(h,s,v)
    swatch.BorderSizePixel  = 0
    swatch.Size             = UDim2.fromOffset(24, 22)
    swatch.ZIndex           = 101
    swatch.Parent           = hexRow
    AddCorner(swatch, UDim.new(0,4))
    AddStroke(swatch, T.Border, 0.12)

    local function refreshUI()
        local c = Color3.fromHSV(h,s,v)
        svBase.BackgroundColor3 = Color3.fromHSV(h,1,1)
        svKnob.Position  = UDim2.new(s, 0, 1-v, 0)
        hueKnob.Position = UDim2.new(h, 0, 0.5, 0)
        swatch.BackgroundColor3 = c
        hexBox.Text = string.format("%02X%02X%02X",
            math.floor(c.R*255+.5), math.floor(c.G*255+.5), math.floor(c.B*255+.5))
        pcall(onChange, c)
    end

    local svDrag, hueDrag = false, false
    svBase.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        svDrag = true
        s = math.clamp((i.Position.X - svBase.AbsolutePosition.X) / svBase.AbsoluteSize.X, 0, 1)
        v = 1 - math.clamp((i.Position.Y - svBase.AbsolutePosition.Y) / svBase.AbsoluteSize.Y, 0, 1)
        refreshUI()
    end)
    hueBar.InputBegan:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        hueDrag = true
        h = math.clamp((i.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
        refreshUI()
    end)
    local mc = UIS.InputChanged:Connect(function(i)
        if i.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if svDrag then
            s = math.clamp((i.Position.X - svBase.AbsolutePosition.X) / svBase.AbsoluteSize.X, 0, 1)
            v = 1 - math.clamp((i.Position.Y - svBase.AbsolutePosition.Y) / svBase.AbsoluteSize.Y, 0, 1)
            refreshUI()
        elseif hueDrag then
            h = math.clamp((i.Position.X - hueBar.AbsolutePosition.X) / hueBar.AbsoluteSize.X, 0, 1)
            refreshUI()
        end
    end)
    local me = UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            svDrag = false; hueDrag = false
        end
    end)
    hexBox.FocusLost:Connect(function()
        local hex = hexBox.Text:match("^#?(%x%x%x%x%x%x)$")
        if not hex then return end
        local r2,g2,b2 = tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255, tonumber(hex:sub(5,6),16)/255
        h,s,v = Color3.new(r2,g2,b2):ToHSV()
        refreshUI()
    end)

    refreshUI()

    obj = {}
    local _destroyed = false
    function obj:Destroy()
        if _destroyed then return end
        _destroyed = true
        mc:Disconnect(); me:Disconnect()
        pcall(function() popup:Destroy() end)
        pcall(function() ov:Destroy() end)
        onClose()
    end
    function obj:SetColor(c) h,s,v = c:ToHSV(); refreshUI() end
    return obj
end

-- ═══════════════════════════════════════════════════════════════
--  NOTIFICATION SYSTEM
--  Floating bottom-right, outside the window so they show
--  even when the menu is hidden.
-- ═══════════════════════════════════════════════════════════════
local _notifSG, _notifHolder
local function EnsureNotifSG()
    if _notifSG and _notifSG.Parent then return end
    _notifSG = Instance.new("ScreenGui")
    _notifSG.Name           = "AxiUI_Notifs"
    _notifSG.ResetOnSpawn   = false
    _notifSG.IgnoreGuiInset = true
    _notifSG.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    _notifSG.DisplayOrder   = 10050
    SafeParent(_notifSG)

    _notifHolder = Instance.new("Frame")
    _notifHolder.AnchorPoint           = Vector2.new(1,1)
    _notifHolder.Position              = UDim2.new(1,-12, 1,-12)
    _notifHolder.Size                  = UDim2.fromOffset(260, 0)
    _notifHolder.AutomaticSize         = Enum.AutomaticSize.Y
    _notifHolder.BackgroundTransparency = 1
    _notifHolder.BorderSizePixel       = 0
    _notifHolder.Parent                = _notifSG
    AddList(_notifHolder, 5)
end

function AxiUI:Notify(title, message, duration)
    EnsureNotifSG()
    duration = duration or 4

    local card = Instance.new("Frame")
    card.BackgroundColor3       = T.WindowBg
    card.BackgroundTransparency = 1 - 0.88
    card.BorderSizePixel        = 0
    card.Size                   = UDim2.new(1, 0, 0, 0)
    card.AutomaticSize          = Enum.AutomaticSize.Y
    card.Parent                 = _notifHolder
    AddCorner(card, UDim.new(0, 7))
    local stroke = AddStroke(card, T.Accent, 0.22)

    -- accentBar uses NO Scale Y — avoids circular AutomaticSize dependency
    local accentBar = Instance.new("Frame")
    accentBar.BackgroundColor3 = T.AccentStrong
    accentBar.BorderSizePixel  = 0
    accentBar.Size             = UDim2.fromOffset(3, 0)
    accentBar.Position         = UDim2.fromOffset(0, 5)
    accentBar.Parent           = card
    AddCorner(accentBar, UDim.new(1, 0))

    -- body drives AutomaticSize; accentBar is an absolute overlay, not in layout flow
    local body = Instance.new("Frame")
    body.BackgroundTransparency = 1
    body.BorderSizePixel        = 0
    body.Size                   = UDim2.new(1, -10, 0, 0)
    body.Position               = UDim2.fromOffset(10, 6)
    body.AutomaticSize          = Enum.AutomaticSize.Y
    body.Parent                 = card
    AddList(body, 2)
    AddPad(body, 0, 6, 0, 0)

    local titleL = MakeLabel(body, title or "Notification", 11, T.AccentStrong,
        Enum.TextXAlignment.Left, Enum.Font.GothamBold)
    titleL.Size = UDim2.new(1, 0, 0, 14)

    local msgL = MakeLabel(body, message or "", 10, T.TextSecondary)
    msgL.Size         = UDim2.new(1, 0, 0, 0)
    msgL.AutomaticSize = Enum.AutomaticSize.Y
    msgL.TextWrapped  = true

    -- Sync accentBar height to card height once card has been laid out
    card:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
        accentBar.Size = UDim2.fromOffset(3, math.max(0, card.AbsoluteSize.Y - 10))
    end)

    task.delay(duration, function()
        if not card.Parent then return end
        Tween(card,      { BackgroundTransparency = 1 }, 0.3)
        Tween(stroke,    { Transparency = 1 }, 0.3)
        Tween(accentBar, { BackgroundTransparency = 1 }, 0.3)
        Tween(titleL,    { TextTransparency = 1 }, 0.3)
        Tween(msgL,      { TextTransparency = 1 }, 0.3)
        task.wait(0.32)
        pcall(function() card:Destroy() end)
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  WINDOW
-- ═══════════════════════════════════════════════════════════════
function AxiUI:CreateWindow(options)
    options    = options or {}
    local win  = setmetatable({}, { __index = self })
    win.Tabs      = {}
    win.ActiveTab = nil
    win.Title     = options.Title or "AxiUI"
    win._closed   = false
    -- HeaderHeight reserves space below the title bar for consumer-built
    -- content (a greeting/avatar header, branding, whatever) -- the
    -- framework positions the sidebar/content area around it correctly
    -- instead of a consumer having to reposition everything by hand after
    -- the fact (the previous, fragile way this was done).
    win.HeaderHeight = options.HeaderHeight or 0
    win.SidebarWidth = options.SidebarWidth or 110

    local gui = Instance.new("ScreenGui")
    gui.Name           = "AxiUI_" .. win.Title:gsub("%s+","")
    gui.ResetOnSpawn   = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.IgnoreGuiInset = true
    gui.DisplayOrder   = 999
    SafeParent(gui)

    local w = options.Width  or 420
    local h = options.Height or 480

    local _vp = workspace.CurrentCamera.ViewportSize
    local frame = Instance.new("Frame")
    frame.Name                   = "AxiWindow"
    frame.Size                   = UDim2.fromOffset(w, h)
    frame.AnchorPoint            = Vector2.new(0, 0)
    frame.Position               = options.Position or UDim2.fromOffset(
        math.floor(_vp.X / 2 - w / 2), math.floor(_vp.Y / 2 - h / 2)
    )
    frame.BackgroundColor3       = T.WindowBg
    frame.BackgroundTransparency = 1 - T.WindowBgAlpha
    frame.BorderSizePixel        = 0
    frame.ClipsDescendants       = true
    frame.Parent                 = gui
    AddCorner(frame, T.RadiusWindow)
    AddStroke(frame, T.Border, 0.10, 1)

    win.Frame = frame
    win.Gui   = gui

    win:_BuildTitleBar()
    win:_BuildTabRow()
    win:_BuildContentArea()
    win:_MakeDraggable()
    win:_BindToggleKey(options.ToggleKey or Enum.KeyCode.RightShift)

    table.insert(AxiUI.Windows, win)
    return win
end

-- Self-tracking soft drop shadow -- stacked, progressively larger/fainter
-- Frames (no external image asset dependency), wired directly to target's
-- own Position/Size/Visible/AnchorPoint via GetPropertyChangedSignal so it
-- can never visually desync from what it's shadowing. A prior version of
-- this (built outside the framework, in the consumer script) was a
-- one-time snapshot taken at creation -- it silently stopped tracking the
-- moment the target moved (dragged) or was hidden, leaving a shadow
-- floating in place forever. This is the actual fix, not a patch:
-- ownership and sync live in one place, permanently connected.
function AxiUI:AddShadow(target, options)
    options = options or {}
    local layers = options.Layers or {
        { pad = 5,  alpha = 0.16 },
        { pad = 11, alpha = 0.10 },
        { pad = 19, alpha = 0.06 },
        { pad = 30, alpha = 0.03 },
    }
    local baseRadius = options.CornerRadius or 12

    -- Zero-size, zero-position wrapper at the shared parent's origin --
    -- its children then use plain offset coordinates equivalent to
    -- target.Position directly, without needing scale-relative math
    -- against a degenerate (zero-size) container.
    local holder = Instance.new("Frame")
    holder.Name                   = "Shadow"
    holder.BackgroundTransparency = 1
    holder.BorderSizePixel        = 0
    holder.Size                   = UDim2.fromOffset(0, 0)
    holder.ZIndex                 = math.max((target.ZIndex or 1) - 1, 0)
    holder.Parent                 = target.Parent

    local frames = {}
    for i, layer in ipairs(layers) do
        local s = Instance.new("Frame")
        s.Name                   = "Layer" .. i
        s.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
        s.BackgroundTransparency = 1 - layer.alpha
        s.BorderSizePixel        = 0
        s.Parent                 = holder
        local c = Instance.new("UICorner")
        c.CornerRadius = UDim.new(0, baseRadius + layer.pad * 0.6)
        c.Parent = s
        frames[i] = { inst = s, pad = layer.pad }
    end

    local function sync()
        holder.Visible = target.Visible
        local pos, size, anchor = target.Position, target.Size, target.AnchorPoint
        for _, f in ipairs(frames) do
            f.inst.AnchorPoint = anchor
            f.inst.Position = pos + UDim2.fromOffset(0, f.pad * 0.4)
            f.inst.Size = UDim2.new(
                size.X.Scale, size.X.Offset + f.pad * 2,
                size.Y.Scale, size.Y.Offset + f.pad * 2
            )
        end
    end

    sync()
    TrackConn(target:GetPropertyChangedSignal("Position"):Connect(sync))
    TrackConn(target:GetPropertyChangedSignal("Size"):Connect(sync))
    TrackConn(target:GetPropertyChangedSignal("Visible"):Connect(sync))
    TrackConn(target:GetPropertyChangedSignal("AnchorPoint"):Connect(sync))

    return holder
end

function AxiUI:_BuildTitleBar()
    local bar = Instance.new("Frame")
    bar.Name                   = "TitleBar"
    bar.Size                   = UDim2.new(1,0,0,34)
    bar.BackgroundColor3       = Color3.fromRGB(255,255,255)
    bar.BackgroundTransparency = 0.97
    bar.BorderSizePixel        = 0
    bar.Parent                 = self.Frame

    -- bottom divider
    local div = Instance.new("Frame")
    div.Size                   = UDim2.new(1,0,0,1)
    div.Position               = UDim2.new(0,0,1,-1)
    div.BackgroundColor3       = T.Border
    div.BackgroundTransparency = 1 - T.BorderAlpha
    div.BorderSizePixel        = 0
    div.Parent                 = bar

    -- (macOS-style traffic-light dots removed here on purpose -- not the
    -- aesthetic this fork is for. Previously worked around at the consumer
    -- level by hiding them after the fact; removed at the source instead
    -- now that this is a dedicated fork, not a shared upstream library.)

    -- Small uppercase left-aligned label, not a centered title + version --
    -- matches the reference design's understated title bar.
    local title = MakeLabel(bar, self.Title:upper(), 9, T.TextMuted,
        Enum.TextXAlignment.Left, Enum.Font.GothamMedium)
    title.Size     = UDim2.new(1, -28, 1, 0)
    title.Position = UDim2.fromOffset(14, 0)

    self.TitleBar = bar
end

function AxiUI:_BuildTabRow()
    -- Left sidebar, not a horizontal top strip -- this fork exists
    -- specifically for a dashboard-style layout, not the original chip-row.
    local topY = 34 + self.HeaderHeight
    local row = Instance.new("ScrollingFrame")
    row.Name                      = "TabRow"
    row.Size                      = UDim2.new(0, self.SidebarWidth, 1, -topY)
    row.Position                  = UDim2.fromOffset(0, topY)
    row.BackgroundColor3          = T.GroupboxBg
    row.BackgroundTransparency    = 1 - T.GroupboxBgAlpha
    row.BorderSizePixel           = 0
    row.ScrollBarThickness        = 0
    row.CanvasSize                = UDim2.new(0,0,0,0)
    row.AutomaticCanvasSize       = Enum.AutomaticSize.Y
    row.Parent                    = self.Frame

    AddList(row, 4, Enum.FillDirection.Vertical)
    AddPad(row, 8, 10, 10, 8, 8)

    self.TabRow = row

    -- Right-edge divider, parented to the window frame (not the
    -- ScrollingFrame) so it doesn't enter the vertical UIListLayout.
    local div = Instance.new("Frame")
    div.Name                   = "TabRowDivider"
    div.Size                   = UDim2.new(0, 1, 1, -topY)
    div.Position               = UDim2.new(0, self.SidebarWidth, 0, topY)
    div.BackgroundColor3       = T.Border
    div.BackgroundTransparency = 1 - T.BorderAlpha
    div.BorderSizePixel        = 0
    div.Parent                 = self.Frame
end

function AxiUI:_BuildContentArea()
    local topY = 34 + self.HeaderHeight
    local area = Instance.new("Frame")
    area.Name                   = "ContentArea"
    area.Size                   = UDim2.new(1, -self.SidebarWidth, 1, -topY)
    area.Position               = UDim2.fromOffset(self.SidebarWidth, topY)
    area.BackgroundTransparency = 1
    area.BorderSizePixel        = 0
    area.Parent                 = self.Frame
    self.ContentArea = area
end

function AxiUI:_MakeDraggable()
    local bar    = self.TitleBar
    local frame  = self.Frame
    local dragging  = false
    local dragInput = nil
    local mousePos
    local startPos

    TrackConn(bar.InputBegan:Connect(function(inp)
        if inp.UserInputType ~= Enum.UserInputType.MouseButton1
            and inp.UserInputType ~= Enum.UserInputType.Touch then return end
        dragging  = true
        mousePos  = inp.Position
        startPos  = frame.Position  -- stored UDim2 offsets; reliable regardless of AnchorPoint
        inp.Changed:Connect(function()
            if inp.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end))

    TrackConn(bar.InputChanged:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseMovement
            or inp.UserInputType == Enum.UserInputType.Touch then
            dragInput = inp
        end
    end))

    TrackConn(UIS.InputChanged:Connect(function(inp)
        if inp ~= dragInput or not dragging then return end
        local delta = inp.Position - mousePos
        frame.Position = UDim2.fromOffset(
            startPos.X.Offset + delta.X,
            startPos.Y.Offset + delta.Y
        )
    end))
end

function AxiUI:_BindToggleKey(key)
    TrackConn(UIS.InputBegan:Connect(function(inp, gpe)
        if gpe or inp.KeyCode ~= key then return end
        for _, w in ipairs(AxiUI.Windows) do
            w.Frame.Visible = not w.Frame.Visible
        end
    end))
end

-- ═══════════════════════════════════════════════════════════════
--  TAB
-- ═══════════════════════════════════════════════════════════════
local Tab = {}
Tab.__index = Tab

-- options.Icon: single character shown in a small colored badge to the
-- left of the label. Defaults to the tab name's first letter. A plain
-- letter badge, not a Unicode/emoji glyph or an external icon asset --
-- Roblox TextLabels don't reliably render full emoji, and this needs no
-- icon-sprite dependency.
function AxiUI:AddTab(name, options)
    options = options or {}
    local tab      = setmetatable({}, Tab)
    tab.Name       = name
    tab.Window     = self
    tab.Groupboxes = {}

    -- Tab button -- full-width row in the vertical sidebar, not an
    -- auto-width horizontal chip.
    local btn = Instance.new("TextButton")
    btn.Text                   = ""
    btn.BackgroundColor3       = T.ElementBg
    btn.BackgroundTransparency = 1
    btn.AutoButtonColor        = false
    btn.BorderSizePixel        = 0
    btn.Size                   = UDim2.new(1, 0, 0, 36)
    btn.Parent                 = self.TabRow
    AddCorner(btn, UDim.new(0, 6))

    -- BadgeColor: each tab keeps its own fixed color (not toggled by
    -- selection state) -- matches the reference design, where only the
    -- button's own background/label dim with selection, not the badge hue.
    local badgeColor = options.BadgeColor or T.Accent
    local badgeAlpha = options.BadgeAlpha or T.AccentAlpha

    local badge = Instance.new("Frame")
    badge.Size                   = UDim2.fromOffset(22, 22)
    badge.Position               = UDim2.fromOffset(6, 7)
    badge.BackgroundColor3       = badgeColor
    badge.BackgroundTransparency = 1 - badgeAlpha
    badge.BorderSizePixel        = 0
    badge.Parent                 = btn
    AddCorner(badge, UDim.new(1, 0))
    AddStroke(badge, badgeColor, badgeAlpha + 0.15, 1)

    local badgeLbl = MakeLabel(badge, (options.Icon or name:sub(1,1)):upper(), 11,
        badgeColor, Enum.TextXAlignment.Center, Enum.Font.GothamBold)
    badgeLbl.Size = UDim2.new(1,0,1,0)

    local nameLbl = MakeLabel(btn, name, 12, T.TextMuted,
        Enum.TextXAlignment.Left, Enum.Font.GothamMedium)
    nameLbl.Size     = UDim2.new(1, -40, 1, 0)
    nameLbl.Position = UDim2.fromOffset(36, 0)

    -- Scrollable content frame
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size                     = UDim2.new(1,0,1,0)
    scroll.BackgroundTransparency   = 1
    scroll.BorderSizePixel          = 0
    scroll.ScrollBarThickness       = 3
    scroll.ScrollBarImageColor3     = T.Accent
    scroll.ScrollBarImageTransparency = 0.55
    scroll.CanvasSize               = UDim2.new(0,0,0,0)
    scroll.Visible                  = false
    scroll.Parent                   = self.ContentArea

    local layout = AddList(scroll, 8)
    AddPad(scroll, 10)

    layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 20)
    end)

    tab.Button   = btn
    tab.NameLbl  = nameLbl
    tab.Badge    = badge
    tab.Scroll   = scroll

    btn.MouseButton1Click:Connect(function() self:_SelectTab(tab) end)
    btn.MouseEnter:Connect(function()
        if self.ActiveTab ~= tab then
            Tween(btn, { BackgroundTransparency = 1 - 0.08 }, 0.15)
        end
    end)
    btn.MouseLeave:Connect(function()
        if self.ActiveTab ~= tab then
            Tween(btn, { BackgroundTransparency = 1 }, 0.15)
        end
    end)

    table.insert(self.Tabs, tab)
    if #self.Tabs == 1 then self:_SelectTab(tab) end
    return tab
end

-- Badge color/opacity is fixed per-tab (set once in AddTab) and never
-- toggled here -- only the button's own background and the label dim with
-- selection, matching the reference design.
function AxiUI:_SelectTab(tab)
    for _, t in ipairs(self.Tabs) do
        Tween(t.Button,  { BackgroundTransparency = 1 }, 0.15)
        Tween(t.NameLbl, { TextColor3 = T.TextMuted }, 0.15)
        t.Scroll.Visible = false
    end
    Tween(tab.Button,  { BackgroundTransparency = 1 - 0.10 }, 0.15)
    Tween(tab.NameLbl, { TextColor3 = T.TextPrimary }, 0.15)
    tab.Scroll.Visible = true
    self.ActiveTab = tab
end

-- ═══════════════════════════════════════════════════════════════
--  GROUPBOX
-- ═══════════════════════════════════════════════════════════════
local Groupbox = {}
Groupbox.__index = Groupbox

local function BuildGroupbox(parent, name, bgColor, bgAlpha, radius, strokeAlpha)
    local gb        = setmetatable({}, Groupbox)
    gb.Open         = true

    local container = Instance.new("Frame")
    container.Name                  = "GB_" .. (name or "sub")
    container.Size                  = UDim2.new(1,0,0,0)
    container.AutomaticSize         = Enum.AutomaticSize.Y
    container.BackgroundColor3      = bgColor
    container.BackgroundTransparency = 1 - bgAlpha
    container.BorderSizePixel       = 0
    container.Parent                = parent
    AddCorner(container, radius)
    AddStroke(container, T.Border, strokeAlpha or T.BorderAlpha)

    -- Header
    local header = Instance.new("TextButton")
    header.Name                   = "Header"
    header.Size                   = UDim2.new(1,0,0,28)
    header.BackgroundColor3       = Color3.fromRGB(255,255,255)
    header.BackgroundTransparency = 0.98
    header.Text                   = ""
    header.AutoButtonColor        = false
    header.BorderSizePixel        = 0
    header.Parent                 = container
    AddCorner(header, radius)  -- top corners only illusion via same radius

    -- square-off lower half of header so body butts up cleanly
    local hdrFill = Instance.new("Frame")
    hdrFill.BackgroundColor3       = Color3.fromRGB(255,255,255)
    hdrFill.BackgroundTransparency = 0.98
    hdrFill.BorderSizePixel        = 0
    hdrFill.Size                   = UDim2.new(1,0,0.5,0)
    hdrFill.Position               = UDim2.new(0,0,0.5,0)
    hdrFill.Parent                 = header

    local hdrLbl = MakeLabel(header, (name or ""):upper(), 10, T.TextMuted,
        Enum.TextXAlignment.Left, Enum.Font.GothamBold)
    hdrLbl.Size     = UDim2.new(1,-28,1,0)
    hdrLbl.Position = UDim2.fromOffset(10,0)

    local chevron = MakeLabel(header, "−", 13, T.TextMuted, Enum.TextXAlignment.Center)
    chevron.Size     = UDim2.fromOffset(20,28)
    chevron.Position = UDim2.new(1,-24,0,0)

    local hdrDiv = Instance.new("Frame")
    hdrDiv.Size                   = UDim2.new(1,0,0,1)
    hdrDiv.Position               = UDim2.new(0,0,1,-1)
    hdrDiv.BackgroundColor3       = T.Border
    hdrDiv.BackgroundTransparency = 1 - (strokeAlpha or T.BorderAlpha)
    hdrDiv.BorderSizePixel        = 0
    hdrDiv.Parent                 = header

    -- Body
    local body = Instance.new("Frame")
    body.Name                   = "Body"
    body.Size                   = UDim2.new(1,0,0,0)
    body.AutomaticSize          = Enum.AutomaticSize.Y
    body.BackgroundTransparency = 1
    body.BorderSizePixel        = 0
    body.Position               = UDim2.fromOffset(0,28)
    body.Parent                 = container
    AddList(body, 4)
    AddPad(body, 7)

    header.MouseButton1Click:Connect(function()
        gb.Open  = not gb.Open
        body.Visible = gb.Open
        Tween(chevron, { TextTransparency = 0 }, 0.08)
        chevron.Text = gb.Open and "−" or "+"
    end)

    gb.Container = container
    gb.Body      = body
    gb.Header    = header
    return gb
end

function Tab:AddGroupbox(name, options)
    options = options or {}
    local gb = BuildGroupbox(self.Scroll, name,
        T.GroupboxBg, T.GroupboxBgAlpha, T.RadiusGroupbox)
    table.insert(self.Groupboxes, gb)
    return gb
end

-- ═══════════════════════════════════════════════════════════════
--  ELEMENTS
-- ═══════════════════════════════════════════════════════════════

-- ── TOGGLE ─────────────────────────────────────────────────────
function Groupbox:AddToggle(key, opts)
    opts = opts or {}
    AxiUI.Flags[key] = opts.Default == true

    local row = MakeElementRow(self.Body)
    -- Label (left)
    local lFrame = Instance.new("Frame")
    lFrame.BackgroundTransparency = 1
    lFrame.BorderSizePixel        = 0
    lFrame.Size                   = UDim2.new(1,-54,1,0)
    lFrame.Position               = UDim2.fromOffset(9,0)
    lFrame.Parent                 = row
    AddList(lFrame, 1)

    local lbl = MakeLabel(lFrame, opts.Text or key, 11, T.TextSecondary)
    lbl.Size = UDim2.new(1,0,0,16)
    if opts.Tooltip then
        local sub = MakeLabel(lFrame, opts.Tooltip, 9, T.TextMuted)
        sub.Size = UDim2.new(1,0,0,11)
    end

    -- Pill (right)
    local pill = Instance.new("Frame")
    pill.Size             = UDim2.fromOffset(32,17)
    pill.AnchorPoint      = Vector2.new(1,0.5)
    pill.Position         = UDim2.new(1,-9,0.5,0)
    pill.BackgroundColor3 = Color3.fromRGB(60,55,80)
    pill.BackgroundTransparency = 0.1
    pill.BorderSizePixel  = 0
    pill.Parent           = row
    AddCorner(pill, T.RadiusPill)
    AddStroke(pill, T.Border, 0.12)

    local thumb = Instance.new("Frame")
    thumb.Size             = UDim2.fromOffset(11,11)
    thumb.Position         = UDim2.fromOffset(2,3)
    thumb.BackgroundColor3 = Color3.fromRGB(100,95,120)
    thumb.BorderSizePixel  = 0
    thumb.Parent           = pill
    AddCorner(thumb, T.RadiusPill)

    local function SetToggle(val, silent)
        AxiUI.Flags[key] = val == true
        if val then
            Tween(pill,  { BackgroundColor3 = T.Accent,
                           BackgroundTransparency = 1 - T.AccentAlpha })
            Tween(thumb, { Position = UDim2.fromOffset(19,3),
                           BackgroundColor3 = T.AccentStrong })
        else
            Tween(pill,  { BackgroundColor3 = Color3.fromRGB(60,55,80),
                           BackgroundTransparency = 0.1 })
            Tween(thumb, { Position = UDim2.fromOffset(2,3),
                           BackgroundColor3 = Color3.fromRGB(100,95,120) })
        end
        if not silent and opts.Callback then pcall(opts.Callback, AxiUI.Flags[key]) end
    end
    SetToggle(opts.Default == true, true)

    -- Transparent click layer on top
    local clickBtn = Instance.new("TextButton")
    clickBtn.Size = UDim2.new(1,0,1,0); clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""; clickBtn.BorderSizePixel = 0; clickBtn.Parent = row
    clickBtn.MouseButton1Click:Connect(function() SetToggle(not AxiUI.Flags[key]) end)
    clickBtn.MouseEnter:Connect(function() Tween(row, { BackgroundTransparency = 1 - T.ElementBgAlpha * 2.2 }, 0.1) end)
    clickBtn.MouseLeave:Connect(function() Tween(row, { BackgroundTransparency = 1 - T.ElementBgAlpha }, 0.1) end)

    local obj = { Set = SetToggle }
    AxiUI.Flags[key .. "_obj"] = obj
    return obj
end

-- ── BUTTON ──────────────────────────────────────────────────────
function Groupbox:AddButton(opts)
    opts = type(opts) == "string" and { Text = opts } or (opts or {})
    local row = MakeElementRow(self.Body)

    local btn = Instance.new("TextButton")
    btn.Size                  = UDim2.new(1,-16,1,-8)
    btn.Position              = UDim2.fromOffset(8,4)
    btn.Font                  = Enum.Font.GothamMedium
    btn.TextSize              = 11
    btn.TextColor3            = T.TextSecondary
    btn.Text                  = opts.Text or "Button"
    btn.BackgroundColor3      = Color3.fromRGB(255,255,255)
    btn.BackgroundTransparency = 0.945
    btn.BorderSizePixel       = 0
    btn.AutoButtonColor       = false
    btn.Parent                = row
    AddCorner(btn, UDim.new(0,5))
    AddStroke(btn, T.Border, 0.09)

    btn.MouseEnter:Connect(function()
        Tween(btn, { BackgroundTransparency = 0.88, TextColor3 = T.TextPrimary }, 0.1)
    end)
    btn.MouseLeave:Connect(function()
        Tween(btn, { BackgroundTransparency = 0.945, TextColor3 = T.TextSecondary }, 0.1)
    end)
    btn.MouseButton1Click:Connect(function()
        if opts.Callback then pcall(opts.Callback) end
    end)

    return { Button = btn, Row = row }
end

-- ── SLIDER ──────────────────────────────────────────────────────
function Groupbox:AddSlider(key, opts)
    opts = opts or {}
    local min, max = opts.Min or 0, opts.Max or 100
    local rounding = opts.Rounding ~= false
    local suffix   = opts.Suffix or ""
    local def      = math.clamp(opts.Default or min, min, max)
    AxiUI.Flags[key] = def

    local row = MakeElementRow(self.Body)

    local lbl = MakeLabel(row, opts.Text or key, 11, T.TextSecondary)
    lbl.Size     = UDim2.new(0.55,-10,1,0)
    lbl.Position = UDim2.fromOffset(9,0)

    local valLbl = MakeLabel(row, tostring(def) .. suffix, 10, T.Accent,
        Enum.TextXAlignment.Right)
    valLbl.Size     = UDim2.fromOffset(30,30)
    valLbl.Position = UDim2.new(1,-38,0,0)

    -- Transparent hit zone — full row height makes it easy to click anywhere near the bar
    local track = Instance.new("Frame")
    track.Size                  = UDim2.fromOffset(88, 28)
    track.AnchorPoint           = Vector2.new(1, 0.5)
    track.Position              = UDim2.new(1, -72, 0.5, 0)
    track.BackgroundTransparency = 1
    track.BorderSizePixel       = 0
    track.Parent                = row

    -- Visual bar (3 px tall, centred inside the hit zone)
    local trackBar = Instance.new("Frame")
    trackBar.Size             = UDim2.new(1, 0, 0, 3)
    trackBar.AnchorPoint      = Vector2.new(0, 0.5)
    trackBar.Position         = UDim2.new(0, 0, 0.5, 0)
    trackBar.BackgroundColor3 = Color3.fromRGB(50, 45, 70)
    trackBar.BackgroundTransparency = 0.18
    trackBar.BorderSizePixel  = 0
    trackBar.Parent           = track
    AddCorner(trackBar, UDim.new(1, 0))

    local fill = Instance.new("Frame")
    fill.BackgroundColor3       = T.Accent
    fill.BackgroundTransparency = 1 - 0.62
    fill.BorderSizePixel        = 0
    fill.Size                   = UDim2.fromScale(0, 1)
    fill.Parent                 = trackBar
    AddCorner(fill, UDim.new(1, 0))

    -- Thumb sits in the hit zone so it's centred on the bar visually
    local thumb = Instance.new("Frame")
    thumb.Size             = UDim2.fromOffset(11, 11)
    thumb.AnchorPoint      = Vector2.new(0.5, 0.5)
    thumb.Position         = UDim2.new(0, 0, 0.5, 0)
    thumb.BackgroundColor3 = T.AccentStrong
    thumb.BorderSizePixel  = 0
    thumb.Parent           = track
    AddCorner(thumb, UDim.new(1, 0))
    AddStroke(thumb, T.Border, 0.2)

    local function SetSlider(val)
        if rounding then val = math.round(val) end
        val = math.clamp(val, min, max)
        AxiUI.Flags[key] = val
        local pct = (val - min) / (max - min)
        fill.Size        = UDim2.fromScale(pct,1)
        thumb.Position   = UDim2.new(pct,0,0.5,0)
        valLbl.Text      = tostring(val) .. suffix
        if opts.Callback then pcall(opts.Callback, val) end
    end
    SetSlider(def)

    local dragging = false
    local function FromMouseX(x)
        local pct = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        SetSlider(min + pct * (max - min))
    end
    TrackConn(track.InputBegan:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true; FromMouseX(inp.Position.X)
        end
    end))
    TrackConn(UIS.InputChanged:Connect(function(inp)
        if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
            FromMouseX(inp.Position.X)
        end
    end))
    TrackConn(UIS.InputEnded:Connect(function(inp)
        if inp.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
    end))

    local obj = { Set = SetSlider }
    AxiUI.Flags[key .. "_obj"] = obj
    return obj
end

-- ── DROPDOWN ────────────────────────────────────────────────────
function Groupbox:AddDropdown(key, opts)
    opts = opts or {}
    local items   = opts.Items or {}
    local default = opts.Default or items[1] or ""
    AxiUI.Flags[key] = default

    local row = MakeElementRow(self.Body)

    local lbl = MakeLabel(row, opts.Text or key, 11, T.TextSecondary)
    lbl.Size     = UDim2.new(0.48,0,1,0)
    lbl.Position = UDim2.fromOffset(9,0)

    local selLbl = MakeLabel(row, default, 10, T.Accent, Enum.TextXAlignment.Right)
    selLbl.Size     = UDim2.new(0.44,0,1,0)
    selLbl.Position = UDim2.new(0.5,0,0,0)

    local chevLbl = MakeLabel(row, "▾", 11, T.TextMuted, Enum.TextXAlignment.Center)
    chevLbl.Size     = UDim2.fromOffset(16,30)
    chevLbl.Position = UDim2.new(1,-18,0,0)

    local popupFrame, overlayBtn
    local open = false

    local function SetValue(v)
        AxiUI.Flags[key] = v
        selLbl.Text = tostring(v)
        if opts.Callback then pcall(opts.Callback, v) end
    end

    local function CloseDD()
        if popupFrame then popupFrame:Destroy(); popupFrame = nil end
        if overlayBtn then overlayBtn:Destroy(); overlayBtn = nil end
        chevLbl.Text = "▾"
        open = false
    end

    local function OpenDD()
        if open then CloseDD(); return end
        open = true
        chevLbl.Text = "▴"
        local ap = row.AbsolutePosition
        local as = row.AbsoluteSize
        local sg = GetPopupSG()

        overlayBtn = MakeOverlay(CloseDD)

        popupFrame = Instance.new("Frame")
        popupFrame.BackgroundColor3      = T.WindowBg
        popupFrame.BackgroundTransparency = 0.04
        popupFrame.BorderSizePixel       = 0
        popupFrame.Size                  = UDim2.fromOffset(as.X, 0)
        popupFrame.AutomaticSize         = Enum.AutomaticSize.Y
        popupFrame.Position              = UDim2.fromOffset(ap.X, ap.Y + as.Y + 2)
        popupFrame.ZIndex                = 99
        popupFrame.Parent                = sg
        AddCorner(popupFrame, UDim.new(0,6))
        AddStroke(popupFrame, T.Border, 0.12)

        local listScroll = Instance.new("ScrollingFrame")
        listScroll.BackgroundTransparency = 1
        listScroll.BorderSizePixel        = 0
        listScroll.ScrollBarThickness     = 2
        listScroll.ScrollBarImageColor3   = T.Accent
        listScroll.CanvasSize             = UDim2.new(0,0,0,0)
        listScroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
        listScroll.Size                   = UDim2.new(1,0,0, math.min(#items * 26 + 8, 160))
        listScroll.ZIndex                 = 100
        listScroll.Parent                 = popupFrame
        AddList(listScroll, 2)
        AddPad(listScroll, 4)

        for _, item in ipairs(items) do
            local iBtn = Instance.new("TextButton")
            iBtn.Text                  = tostring(item)
            iBtn.Font                  = Enum.Font.GothamMedium
            iBtn.TextSize              = 10
            iBtn.TextColor3            = item == AxiUI.Flags[key] and T.AccentStrong or T.TextSecondary
            iBtn.TextXAlignment        = Enum.TextXAlignment.Left
            iBtn.BackgroundTransparency = 1
            iBtn.BorderSizePixel       = 0
            iBtn.Size                  = UDim2.new(1,0,0,24)
            iBtn.ZIndex                = 101
            iBtn.Parent                = listScroll
            AddPad(iBtn, nil,0,0,8,0)
            iBtn.MouseEnter:Connect(function() Tween(iBtn, { TextColor3 = T.AccentStrong }, 0.1) end)
            iBtn.MouseLeave:Connect(function()
                Tween(iBtn, { TextColor3 = item == AxiUI.Flags[key] and T.AccentStrong or T.TextSecondary }, 0.1)
            end)
            iBtn.MouseButton1Click:Connect(function() SetValue(item); CloseDD() end)
        end
    end

    local clickBtn = Instance.new("TextButton")
    clickBtn.Size = UDim2.new(1,0,1,0); clickBtn.BackgroundTransparency = 1
    clickBtn.Text = ""; clickBtn.BorderSizePixel = 0; clickBtn.Parent = row
    clickBtn.MouseButton1Click:Connect(OpenDD)

    local obj = {
        Set      = SetValue,
        SetItems = function(self, newItems)
            items = newItems
            SetValue(newItems[1] or "")
            if open then CloseDD() end
        end,
    }
    AxiUI.Flags[key .. "_obj"] = obj
    return obj
end

-- ── INPUT ───────────────────────────────────────────────────────
function Groupbox:AddInput(key, opts)
    opts = opts or {}
    AxiUI.Flags[key] = opts.Default or ""

    local row = MakeElementRow(self.Body, 44)  -- MakeElementRow already adds UIStroke

    local lbl = MakeLabel(row, opts.Text or key, 11, T.TextSecondary)
    lbl.Size     = UDim2.new(1,-16,0,16)
    lbl.Position = UDim2.fromOffset(9,4)

    local box = Instance.new("TextBox")
    box.Size              = UDim2.new(1,-18,0,18)
    box.Position          = UDim2.fromOffset(9,21)
    box.Text              = opts.Default or ""
    box.PlaceholderText   = opts.Placeholder or "..."
    box.Font              = Enum.Font.GothamMedium
    box.TextSize          = 10
    box.TextColor3        = T.TextPrimary
    box.PlaceholderColor3 = T.TextMuted
    box.BackgroundColor3  = Color3.fromRGB(255,255,255)
    box.BackgroundTransparency = 0.955
    box.BorderSizePixel   = 0
    box.TextXAlignment    = Enum.TextXAlignment.Left
    box.ClearTextOnFocus  = false
    box.Parent            = row
    AddCorner(box, UDim.new(0,4))
    AddStroke(box, T.Border, 0.12)
    AddPad(box, nil, 0,0, 6,0)

    local numeric  = opts.Numeric == true
    local finished = opts.Finished == true

    if numeric then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            local clean = box.Text:match("^-?%d*%.?%d*") or ""
            if clean ~= box.Text then box.Text = clean end
        end)
    end

    if not finished then
        box:GetPropertyChangedSignal("Text"):Connect(function()
            AxiUI.Flags[key] = box.Text
            if opts.Callback then pcall(opts.Callback, box.Text) end
        end)
    end

    box.FocusLost:Connect(function(enter)
        AxiUI.Flags[key] = box.Text
        if finished and enter and opts.Callback then pcall(opts.Callback, box.Text) end
    end)

    local obj = {
        Set = function(self, v)
            box.Text = tostring(v)
            AxiUI.Flags[key] = box.Text
        end,
    }
    AxiUI.Flags[key .. "_obj"] = obj
    return obj
end

-- ── KEYBIND ─────────────────────────────────────────────────────
function Groupbox:AddKeybind(key, opts)
    opts = opts or {}
    local currentKey = opts.Default or Enum.KeyCode.Unknown
    AxiUI.Flags[key] = currentKey

    local row = MakeElementRow(self.Body)

    local lbl = MakeLabel(row, opts.Text or key, 11, T.TextSecondary)
    lbl.Size     = UDim2.new(0.58,0,1,0)
    lbl.Position = UDim2.fromOffset(9,0)

    local pill = Instance.new("TextButton")
    pill.Size                  = UDim2.fromOffset(54,18)
    pill.AnchorPoint           = Vector2.new(1,0.5)
    pill.Position              = UDim2.new(1,-9,0.5,0)
    pill.Font                  = Enum.Font.GothamMedium
    pill.TextSize              = 9
    pill.TextColor3            = T.Accent
    pill.Text                  = currentKey == Enum.KeyCode.Unknown and "None" or currentKey.Name
    pill.BackgroundColor3      = Color3.fromRGB(50,45,70)
    pill.BackgroundTransparency = 0.2
    pill.BorderSizePixel       = 0
    pill.AutoButtonColor       = false
    pill.Parent                = row
    AddCorner(pill, UDim.new(0,4))
    AddStroke(pill, T.Accent, 0.42)

    local listening = false
    pill.MouseButton1Click:Connect(function()
        if listening then return end
        listening = true
        pill.Text      = "..."
        pill.TextColor3 = T.TextMuted
        local conn
        conn = TrackConn(UIS.InputBegan:Connect(function(inp, gpe)
            if gpe then return end
            local newKey
            if inp.UserInputType == Enum.UserInputType.Keyboard then
                if inp.KeyCode == Enum.KeyCode.Escape then
                    listening = false
                    pill.Text = currentKey == Enum.KeyCode.Unknown and "None" or currentKey.Name
                    pill.TextColor3 = T.Accent
                    conn:Disconnect(); return
                end
                newKey = inp.KeyCode
            else return end
            currentKey = newKey
            AxiUI.Flags[key] = newKey
            pill.Text      = newKey.Name
            pill.TextColor3 = T.Accent
            listening = false
            conn:Disconnect()
            if opts.Callback then pcall(opts.Callback, newKey) end
        end))
    end)

    return { Get = function() return AxiUI.Flags[key] end }
end

-- ── COLOUR PICKER ───────────────────────────────────────────────
function Groupbox:AddColorPicker(key, opts)
    opts = opts or {}
    local initColor = opts.Default or Color3.fromRGB(255,255,255)
    AxiUI.Flags[key] = initColor

    local row = MakeElementRow(self.Body)

    local lbl = MakeLabel(row, opts.Text or key, 11, T.TextSecondary)
    lbl.Size     = UDim2.new(1,-54,1,0)
    lbl.Position = UDim2.fromOffset(9,0)

    local swatch = Instance.new("TextButton")
    swatch.Size             = UDim2.fromOffset(38,20)
    swatch.AnchorPoint      = Vector2.new(1,0.5)
    swatch.Position         = UDim2.new(1,-9,0.5,0)
    swatch.BackgroundColor3 = initColor
    swatch.Text             = ""
    swatch.AutoButtonColor  = false
    swatch.BorderSizePixel  = 0
    swatch.Parent           = row
    AddCorner(swatch, UDim.new(0,4))
    AddStroke(swatch, T.Border, 0.14)

    local popup = nil
    swatch.MouseButton1Click:Connect(function()
        if popup then popup:Destroy(); popup = nil; return end
        popup = BuildColourPopup(swatch, AxiUI.Flags[key],
            function(c)
                AxiUI.Flags[key] = c
                swatch.BackgroundColor3 = c
                if opts.Callback then pcall(opts.Callback, c) end
            end,
            function() popup = nil end
        )
    end)

    local obj = {
        Set = function(self, c)
            AxiUI.Flags[key] = c
            swatch.BackgroundColor3 = c
            if popup then popup:SetColor(c) end
        end,
    }
    AxiUI.Flags[key .. "_obj"] = obj
    return obj
end

-- ── LABEL ───────────────────────────────────────────────────────
function Groupbox:AddLabel(text, opts)
    opts = opts or {}
    local row = Instance.new("Frame")
    row.BackgroundTransparency = 1
    row.BorderSizePixel        = 0
    row.Size                   = UDim2.new(1,0,0,0)
    row.AutomaticSize          = Enum.AutomaticSize.Y
    row.Parent                 = self.Body

    local lbl = MakeLabel(row, text, opts.Size or 10,
        opts.Color or T.TextMuted,
        opts.Align or Enum.TextXAlignment.Left)
    lbl.Size        = UDim2.new(1,-16,0,0)
    lbl.Position    = UDim2.fromOffset(8,0)
    lbl.TextWrapped = true
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    return lbl
end

-- ── DIVIDER ─────────────────────────────────────────────────────
function Groupbox:AddDivider()
    local div = Instance.new("Frame")
    div.BackgroundColor3      = T.Border
    div.BackgroundTransparency = 1 - T.BorderAlpha
    div.BorderSizePixel        = 0
    div.Size                   = UDim2.new(1,-16,0,1)
    div.Position               = UDim2.fromOffset(8,0)
    div.Parent                 = self.Body
end

-- ── SUBBOX ──────────────────────────────────────────────────────
function Groupbox:AddSubBox(name)
    return BuildGroupbox(self.Body, name,
        T.SubBoxBg, T.SubBoxBgAlpha, T.RadiusSubBox, 0.055)
end

-- ═══════════════════════════════════════════════════════════════
--  THEME  (partial override — takes effect immediately for future
--  elements; call before CreateWindow for clean results)
-- ═══════════════════════════════════════════════════════════════
function AxiUI:SetTheme(overrides)
    for k, v in pairs(overrides) do
        AxiUI.Theme[k] = v
    end
    -- T is a reference to AxiUI.Theme, so it updates automatically.
end

-- ═══════════════════════════════════════════════════════════════
--  CONFIG  SAVE / LOAD
-- ═══════════════════════════════════════════════════════════════
function AxiUI:SaveConfig(name)
    local data = {}
    for k, v in pairs(self.Flags) do
        -- skip _obj entries and non-primitive types
        if not k:find("_obj$") then
            local t = type(v)
            if t == "boolean" or t == "number" or t == "string" then
                data[k] = v
            elseif typeof(v) == "EnumItem" then
                data[k] = { __enum = tostring(v) }
            elseif typeof(v) == "Color3" then
                data[k] = { __col = true, r = v.R, g = v.G, b = v.B }
            end
        end
    end
    local ok, err = pcall(writefile, "axiui_" .. name .. ".json",
        HttpSvc:JSONEncode(data))
    if not ok then warn("[AxiUI] SaveConfig failed:", err) end
end

function AxiUI:LoadConfig(name)
    if not (typeof(isfile) == "function" and isfile("axiui_" .. name .. ".json")) then
        return false
    end
    local ok, raw = pcall(readfile, "axiui_" .. name .. ".json")
    if not ok then return false end
    local data = HttpSvc:JSONDecode(raw)
    for k, v in pairs(data) do
        local obj = self.Flags[k .. "_obj"]
        if obj and obj.Set then
            if type(v) == "table" and v.__col then
                pcall(obj.Set, obj, Color3.new(v.r, v.g, v.b))
            elseif type(v) == "table" and v.__enum then
                local parts = v.__enum:split(".")
                pcall(function()
                    pcall(obj.Set, obj, (Enum :: any)[parts[2]][parts[3]])
                end)
            else
                pcall(obj.Set, obj, v)
            end
        end
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════
--  UNLOAD
-- ═══════════════════════════════════════════════════════════════
function AxiUI:Unload()
    for _, conn in ipairs(self.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    for _, win in ipairs(self.Windows) do
        pcall(function() win.Gui:Destroy() end)
    end
    if _popupSG  then pcall(function() _popupSG:Destroy()  end); _popupSG  = nil end
    if _notifSG  then pcall(function() _notifSG:Destroy()  end); _notifSG  = nil end
    self.Windows     = {}
    self.Flags       = {}
    self.Connections = {}
    if self.OnUnload then pcall(self.OnUnload) end
end

-- Publish to global env so ThemeManager / InterfaceManager can find this instance
pcall(function()
    local _genv = typeof(getgenv) == "function" and getgenv() or _G
    _genv.AxiUI = AxiUI
end)

return AxiUI
