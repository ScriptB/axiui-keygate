--[[
    AxiUI — ThemeManager v1.0.0
    Requires AxiUI_Framework to be loaded first.

    Usage:
        local ThemeManager = loadstring(game:HttpGet("...AxiUI_ThemeManager.lua"))()
        ThemeManager:Apply("Ocean")
        ThemeManager:ApplyToTab(tab)
        ThemeManager:ApplyToGroupbox(gb)
]]

local _env  = (typeof(getgenv) == "function" and getgenv()) or _G
local AxiUI = _env.AxiUI
assert(AxiUI, "[AxiUI] ThemeManager: AxiUI_Framework must be loaded first.")

local RunSvc  = game:GetService("RunService")
local HttpSvc = game:GetService("HttpService")
local T       = AxiUI.Theme

-- Keys that can be swapped by a theme (colors only — translucency stack stays fixed)
local COLOR_KEYS = {
    "WindowBg", "Accent", "AccentStrong",
    "TextPrimary", "TextSecondary", "TextMuted",
}
local ALPHA_KEYS = { "WindowBgAlpha", "AccentAlpha" }

-- ═══════════════════════════════════════════════════════════════
--  BUILT-IN THEMES
-- ═══════════════════════════════════════════════════════════════
local Themes = {}

Themes.Default = {
    WindowBg      = Color3.fromRGB(14,  16,  26),   WindowBgAlpha  = 0.82,
    Accent        = Color3.fromRGB(160, 130, 255),  AccentAlpha    = 0.35,
    AccentStrong  = Color3.fromRGB(200, 185, 255),
    TextPrimary   = Color3.fromRGB(220, 215, 255),
    TextSecondary = Color3.fromRGB(140, 130, 160),
    TextMuted     = Color3.fromRGB(80,  75,  100),
}

Themes.Ocean = {
    WindowBg      = Color3.fromRGB(6,   14,  22),   WindowBgAlpha  = 0.84,
    Accent        = Color3.fromRGB(50,  200, 180),  AccentAlpha    = 0.35,
    AccentStrong  = Color3.fromRGB(90,  230, 210),
    TextPrimary   = Color3.fromRGB(210, 230, 235),
    TextSecondary = Color3.fromRGB(100, 140, 155),
    TextMuted     = Color3.fromRGB(55,  80,  95),
}

Themes.Rose = {
    WindowBg      = Color3.fromRGB(22,  10,  18),   WindowBgAlpha  = 0.84,
    Accent        = Color3.fromRGB(255, 110, 160),  AccentAlpha    = 0.38,
    AccentStrong  = Color3.fromRGB(255, 150, 190),
    TextPrimary   = Color3.fromRGB(240, 220, 230),
    TextSecondary = Color3.fromRGB(160, 110, 140),
    TextMuted     = Color3.fromRGB(90,  55,  80),
}

Themes.Midnight = {
    WindowBg      = Color3.fromRGB(4,   8,   22),   WindowBgAlpha  = 0.86,
    Accent        = Color3.fromRGB(115, 155, 255),  AccentAlpha    = 0.38,
    AccentStrong  = Color3.fromRGB(160, 195, 255),
    TextPrimary   = Color3.fromRGB(218, 228, 255),
    TextSecondary = Color3.fromRGB(125, 145, 200),
    TextMuted     = Color3.fromRGB(65,  82,  130),
}

Themes.Emerald = {
    WindowBg      = Color3.fromRGB(6,   14,  10),   WindowBgAlpha  = 0.84,
    Accent        = Color3.fromRGB(48,  218, 138),  AccentAlpha    = 0.35,
    AccentStrong  = Color3.fromRGB(88,  255, 168),
    TextPrimary   = Color3.fromRGB(212, 240, 222),
    TextSecondary = Color3.fromRGB(118, 162, 138),
    TextMuted     = Color3.fromRGB(62,  98,  78),
}

Themes.Neon = {
    WindowBg      = Color3.fromRGB(8,   8,   14),   WindowBgAlpha  = 0.84,
    Accent        = Color3.fromRGB(180, 80,  255),  AccentAlpha    = 0.38,
    AccentStrong  = Color3.fromRGB(210, 120, 255),
    TextPrimary   = Color3.fromRGB(230, 220, 255),
    TextSecondary = Color3.fromRGB(140, 120, 190),
    TextMuted     = Color3.fromRGB(75,  60,  110),
}

Themes.Carbon = {
    WindowBg      = Color3.fromRGB(12,  12,  12),   WindowBgAlpha  = 0.88,
    Accent        = Color3.fromRGB(228, 228, 228),  AccentAlpha    = 0.32,
    AccentStrong  = Color3.fromRGB(248, 248, 250),  -- near-white; pure white collides with translucent overlay repaint
    TextPrimary   = Color3.fromRGB(235, 235, 235),
    TextSecondary = Color3.fromRGB(155, 155, 155),
    TextMuted     = Color3.fromRGB(88,  88,  88),
}

Themes.Sunset = {
    WindowBg      = Color3.fromRGB(22,  10,  8),    WindowBgAlpha  = 0.84,
    Accent        = Color3.fromRGB(255, 130, 60),   AccentAlpha    = 0.38,
    AccentStrong  = Color3.fromRGB(255, 175, 100),
    TextPrimary   = Color3.fromRGB(255, 235, 220),
    TextSecondary = Color3.fromRGB(180, 130, 110),
    TextMuted     = Color3.fromRGB(100, 65,  55),
}

-- ═══════════════════════════════════════════════════════════════
--  REPAINT  (scans descendant tree and swaps matched Color3s)
-- ═══════════════════════════════════════════════════════════════
local function c2s(c)
    return math.floor(c.R*255+.5)..","..math.floor(c.G*255+.5)..","..math.floor(c.B*255+.5)
end

local function repaintTree(root, oldMap, newTheme)
    local props = { "BackgroundColor3", "TextColor3", "ImageColor3" }
    local stack = { root }
    while #stack > 0 do
        local inst = table.remove(stack)
        pcall(function()
            for _, p in ipairs(props) do
                local ok, v = pcall(function() return inst[p] end)
                if ok and typeof(v) == "Color3" then
                    local key = oldMap[c2s(v)]
                    if key and newTheme[key] then
                        pcall(function() inst[p] = newTheme[key] end)
                    end
                end
            end
            local sk = inst:FindFirstChildOfClass("UIStroke")
            if sk then
                local ok, v = pcall(function() return sk.Color end)
                if ok and typeof(v) == "Color3" then
                    local key = oldMap[c2s(v)]
                    if key and newTheme[key] then
                        pcall(function() sk.Color = newTheme[key] end)
                    end
                end
            end
        end)
        for _, child in ipairs(inst:GetChildren()) do
            stack[#stack+1] = child
        end
    end
end

local function scanAndRepaint(oldMap, newTheme)
    -- Repaint open windows
    for _, win in ipairs(AxiUI.Windows) do
        pcall(repaintTree, win.Gui, oldMap, newTheme)
    end
    -- Repaint floating ScreenGuis (Notifs, Watermark, etc.)
    local function tryParent(p)
        if not p then return end
        for _, c in ipairs(p:GetChildren()) do
            if c.Name:sub(1, 5) == "AxiUI" then
                pcall(repaintTree, c, oldMap, newTheme)
            end
        end
    end
    pcall(tryParent, typeof(gethui) == "function" and gethui() or nil)
    pcall(tryParent, game:GetService("CoreGui"))
    pcall(function()
        local lp = game:GetService("Players").LocalPlayer
        if lp then tryParent(lp.PlayerGui) end
    end)
end

-- ═══════════════════════════════════════════════════════════════
--  THEME MANAGER
-- ═══════════════════════════════════════════════════════════════
local ThemeManager         = {}
ThemeManager._themes       = Themes
ThemeManager._current      = "Default"
ThemeManager._listeners    = {}
ThemeManager._rainbowConn  = nil

function ThemeManager:GetNames()
    local n = {}
    for k in pairs(self._themes) do n[#n+1] = k end
    table.sort(n)
    return n
end

function ThemeManager:AddTheme(name, themeTable)
    self._themes[name] = themeTable
end

function ThemeManager:GetCurrent()
    return self._current
end

function ThemeManager:Apply(name)
    local t = self._themes[name]
    if not t then return end

    -- Build reverse map from current COLOR_KEYS in AxiUI.Theme
    local oldMap = {}
    for _, k in ipairs(COLOR_KEYS) do
        local v = T[k]
        if typeof(v) == "Color3" then oldMap[c2s(v)] = k end
    end

    -- Mutate AxiUI.Theme in-place (T is a reference so Framework picks it up automatically)
    for _, k in ipairs(COLOR_KEYS) do
        if t[k] then T[k] = t[k] end
    end
    for _, k in ipairs(ALPHA_KEYS) do
        if t[k] then T[k] = t[k] end
    end

    -- Repaint existing GUI
    scanAndRepaint(oldMap, T)

    self._current = name
    for _, fn in ipairs(self._listeners) do pcall(fn, name) end
end

function ThemeManager:OnChanged(fn)
    table.insert(self._listeners, fn)
end

-- ─── RAINBOW ACCENT ─────────────────────────────────────────────
function ThemeManager:SetRainbow(enabled, speed)
    if self._rainbowConn then
        self._rainbowConn:Disconnect()
        self._rainbowConn = nil
    end
    if not enabled then return end
    speed = speed or 0.4
    local clock = 0
    self._rainbowConn = RunSvc.Heartbeat:Connect(function(dt)
        clock = (clock + dt * speed) % 1
        T.Accent       = Color3.fromHSV(clock, 0.78, 1)
        T.AccentStrong = Color3.fromHSV(clock, 0.55, 1)
    end)
end

-- ─── CUSTOM THEME FILE I/O ──────────────────────────────────────
function ThemeManager:SaveCustom(name)
    local data = {}
    for _, k in ipairs(COLOR_KEYS) do
        local v = T[k]
        if typeof(v) == "Color3" then data[k] = { r = v.R, g = v.G, b = v.B } end
    end
    for _, k in ipairs(ALPHA_KEYS) do
        if T[k] then data[k] = T[k] end
    end
    pcall(function()
        if typeof(makefolder) == "function" then
            if not isfolder("AxiUI_Themes") then makefolder("AxiUI_Themes") end
        end
        writefile("AxiUI_Themes/" .. name .. ".json", HttpSvc:JSONEncode(data))
    end)
end

function ThemeManager:LoadCustom(name)
    local path = "AxiUI_Themes/" .. name .. ".json"
    if typeof(isfile) == "function" and not isfile(path) then return false end
    local ok, raw = pcall(readfile, path)
    if not ok then return false end
    local ok2, data = pcall(function() return HttpSvc:JSONDecode(raw) end)
    if not ok2 then return false end
    local t = {}
    for k, v in pairs(data) do
        if type(v) == "table" and v.r ~= nil then
            t[k] = Color3.new(v.r, v.g, v.b)
        elseif type(v) == "number" then
            t[k] = v
        end
    end
    local n = "_custom_" .. name
    self._themes[n] = t
    self:Apply(n)
    return true
end

-- ─── UI BUILDERS ────────────────────────────────────────────────
function ThemeManager:BuildUI(gb)
    gb:AddDropdown("TM_Theme", {
        Text    = "Theme",
        Items   = self:GetNames(),
        Default = self._current,
        Callback = function(v) self:Apply(v) end,
    })
    gb:AddToggle("TM_Rainbow", {
        Text    = "Rainbow Accent",
        Default = false,
        Callback = function(on) self:SetRainbow(on) end,
    })
    gb:AddButton({ Text = "Save as Custom", Callback = function()
        self:SaveCustom("custom")
        AxiUI:Notify("Theme", "Current theme saved as 'custom'", 3)
    end })
    gb:AddButton({ Text = "Load Custom", Callback = function()
        local ok = self:LoadCustom("custom")
        AxiUI:Notify("Theme", ok and "Loaded 'custom' theme" or "No custom theme found", 3)
    end })
end

function ThemeManager:ApplyToTab(tab)
    if not tab then return end
    self:BuildUI(tab:AddGroupbox("Theme"))
end

function ThemeManager:ApplyToGroupbox(gb)
    if gb then self:BuildUI(gb) end
end

-- ─── ATTACH ─────────────────────────────────────────────────────
AxiUI.ThemeManager = ThemeManager
return ThemeManager
