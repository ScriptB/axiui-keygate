--[[
    Universal Key Gate — AxiUI edition
    Renders an AxiUI key-entry window with a mock validator. On success it
    hands off to GameDispatcher.lua (hosted separately on GitHub), which
    owns the actual PlaceId -> script matching and does the real loadstring.
    This file never decides what gets loaded — only whether the key holder
    is allowed to trigger the dispatcher at all.

    STATUS: ValidateKey below is a mock (see "MOCK VALIDATION" section) —
    swap it for the real backend call later without touching the UI/
    animation code. DISPATCHER_URL is a placeholder until GameDispatcher.lua
    is actually pushed to a repo.

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

local TweenSvc = game:GetService("TweenService")

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
--  2. SCRIPT LIBRARY — the PlaceId -> script matching itself lives in
--  a separate, GitHub-hosted dispatcher file (see GameDispatcher.lua),
--  not in this gate. This file only knows the dispatcher's URL and
--  hands off to it once a key validates.
-- ══════════════════════════════════════════════════════════════
local DISPATCHER_URL = "https://raw.githubusercontent.com/ScriptB/axiui-keygate/main/GameDispatcher.lua"

-- ══════════════════════════════════════════════════════════════
--  3. MOCK VALIDATION — swap this for a real backend call later
--  (e.g. this project's existing KeyAuth.Verify) without touching
--  any UI/animation code below.
-- ══════════════════════════════════════════════════════════════
local function MockValidateKey(key)
    task.wait(0.7)
    return #key >= 6
end
local ValidateKey = MockValidateKey

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
    "Game ID " .. tostring(PlaceId) .. " — library match resolved after validation.",
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

local function OnLoadStage()
    local ok, err = pcall(function()
        loadstring(game:HttpGet(DISPATCHER_URL))()
    end)
    if not ok then
        warn("[UniversalKeyGate] Dispatcher fetch/exec failed: " .. tostring(err))
    end
end

local function SubmitKey()
    if validating then return end
    local key = AxiUI.Flags["KeyInput"] or ""
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

    local ok = ValidateKey(key)

    validating = false
    if ok then
        ValidateBtn.Button.Text = "Validated"
        StatusLabel.Text = "Access granted."
        StatusLabel.TextColor3 = FLAT_SUCCESS
        AxiUI:Notify("Access", "Key accepted.", 2)
        task.wait(0.4)
        PlayExit(OnLoadStage)
    else
        ValidateBtn.Button.Text = "Validate"
        StatusLabel.Text = "Invalid key — try again."
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
