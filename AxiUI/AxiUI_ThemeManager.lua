

local _env  = (typeof(getgenv) == "function" and getgenv()) or _G
local AxiUI = _env.AxiUI
assert(AxiUI, "[AxiUI] ThemeManager: AxiUI_Framework must be loaded first.")

local RunSvc  = game:GetService("RunService")
local HttpSvc = game:GetService("HttpService")
local T       = AxiUI.Theme

local COLOR_KEYS = {
    "WindowBg", "GroupboxBg", "ElementBg", "SubBoxBg",
    "Accent", "AccentStrong",
    "Border",
    "TextPrimary", "TextSecondary", "TextMuted",
}
local ALPHA_KEYS = { "WindowBgAlpha", "AccentAlpha" }

-- Built-In Themes
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

local function applyBindings(newTheme)
    local bindings = AxiUI._themeBindings
    local i = 1
    while i <= #bindings do
        local b = bindings[i]
        local alive = pcall(function() return b.inst.Parent end)
        if alive and b.inst.Parent ~= nil then
            local v = newTheme[b.key]
            if v then pcall(function() b.inst[b.prop] = v end) end
            i = i + 1
        else
            table.remove(bindings, i)
        end
    end
end

-- Theme Manager
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

    for _, k in ipairs(COLOR_KEYS) do
        if t[k] then T[k] = t[k] end
    end
    for _, k in ipairs(ALPHA_KEYS) do
        if t[k] then T[k] = t[k] end
    end

    applyBindings(T)

    self._current = name
    for _, fn in ipairs(self._listeners) do pcall(fn, name) end
end

function ThemeManager:OnChanged(fn)
    table.insert(self._listeners, fn)
end

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

AxiUI.ThemeManager = ThemeManager
return ThemeManager
