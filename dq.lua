-- moseeri dungeon (dq) - farm + limit test for the dungeon game (GameId 4201418016)
-- lobby place 11872917490, dungeon place 14928194914
-- Load:  loadstring(game:HttpGet("https://raw.githubusercontent.com/moseeri01/dqhub/main/dq.lua"))()
-- Owner (local build):  loadstring(readfile("dq/dq.lua"))()
local VERSION = "dq_192"
local G = (getgenv and getgenv()) or _G
if G.__dq_stop then pcall(G.__dq_stop) end
-- one copy only: every load takes a new number and older copies stop themselves
-- (after a teleport several queued copies start at once - 3 copies fought over the character on 11-21)
G.__dq_seq = (G.__dq_seq or 0) + 1
local SEQ = G.__dq_seq

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
while not LP do task.wait(0.2) LP = Players.LocalPlayer end
if G.__dq_seq ~= SEQ then return end -- a newer copy started while we waited

local LOBBY_PLACE = 11872917490
local IN_LOBBY = (game.PlaceId == LOBBY_PLACE)
local DIR = "dq"
-- owner's PC with Volt multi-instance (11-21): a second account gets its own folder (log, cfg, cmd, state)
-- so two copies never write over each other. Friends' devices have no dev.flag and keep "dq".
pcall(function()
    if isfile and isfile("dq/dev.flag") and LP.Name ~= "Exitta" then
        DIR = "dq/acc_" .. tostring(LP.UserId)
        if isfolder and not isfolder(DIR) then makefolder(DIR) end
        if not isfile(DIR .. "/dev.flag") then writefile(DIR .. "/dev.flag", "") end
    end
end)

local F = { alive = true, conns = {}, logLines = {} }
local S = { -- live stats (this server only; totals kept in cfg)
    target = "-", wp = 0, phase = "idle", runStart = nil, pullBacks = 0, deaths = 0, errors = 0,
    lastRun = nil, swings = 0, limitMsg = "-",
}

local function ensureFolder() pcall(function() if isfolder and not isfolder(DIR) then makefolder(DIR) end end) end
ensureFolder()

-- DEV = the owner's PC (dq/dev.flag). Friends (Delta on phones) got load time + lag from file writes:
-- there the log stays in memory only (Log tab), no state file, no command file polling.
local DEV = false
pcall(function() DEV = isfile and isfile(DIR .. "/dev.flag") or false end)
local logBuf = {}
local function log(msg)
    local line = os.date("%H:%M:%S") .. " " .. tostring(msg)
    table.insert(F.logLines, line)
    if #F.logLines > 60 then table.remove(F.logLines, 1) end
    if DEV then logBuf[#logBuf + 1] = line end
end
-- one file write every 3 s instead of one per line
task.spawn(function()
    while F.alive do
        task.wait(3)
        if #logBuf > 0 then
            local chunk = table.concat(logBuf, "\n") .. "\n"
            logBuf = {}
            pcall(function() appendfile(DIR .. "/log.txt", chunk) end)
        end
    end
end)

-- every thread goes through go(): one uncaught error is never left to the game's error reporter
local function go(name, fn, ...)
    local args = { ... }
    return task.spawn(function()
        local ok, err = pcall(fn, unpack(args))
        if not ok then S.errors = S.errors + 1 log("ERR " .. name .. ": " .. tostring(err)) end
    end)
end

-- config (saved)
local DEFAULT = {
    farm = false, map = "Raided Village", difficulty = "Normal", hardcore = false,
    move = "Teleport", tpStep = 60, tpWait = 0.12, tweenSpeed = 60, swingRate = 10, standDist = 4, hover = 10,
    autoQE = true, bossFirst = true, endAction = "Retry", stuckTimeout = 480, lobbyWait = 8,
    totalRuns = 0, bestRun = 0, totalSeconds = 0,
    autoBest = true, retry = true, dodge = false, dodgeLight = true, dodgeOn = "auto", dodgeMode = "auto", autoPortal = true, standOff = 0, exactZones = true, carrySpots = {}, noHit = false, impTry = "Lunar", impBox = false, exploreHits = {}, keyFail = {}, keyBlock = {}, pendingRun = "", rejoins = {}, -- auto = work out from dodge/dodgeLight once (dq_106) -- owner 11-21: farming without dodge is faster even with deaths
    sellRarity = { common = true, uncommon = true, rare = true }, sellTypes = { weapons = true, armors = true, helmets = true, legs = true },
    badRoute = {}, deathStreak = 0, lastPlayed = "", lastPlayedAt = 0, autoJoin = false, dangerAnims = {}, bossCells = {}, mobHeight = {}, zoneDmg = {}, watchdog = true, stuckMin = 3, wd = {}, autoFree = true, gameRetry = false, lowGfx = false, autoUpgrade = false, upgSlots = { weapons = true, armors = true, helmets = true, legs = true, rings = true }, upgLevels = 5, timingLog = false, sellAt = 80, mode = "Dungeons", modeTier = {}, recordRoute = false, tuneSet = 0,
    autoSell = false, autoSP = true, spStat = "physical", autoEquipBest = true, autoDaily = true, autoQuests = true,
}
local cfg = {}
for k, v in pairs(DEFAULT) do cfg[k] = v end
pcall(function()
    if isfile and isfile(DIR .. "/cfg.json") then
        local t = HttpService:JSONDecode(readfile(DIR .. "/cfg.json"))
        for k, v in pairs(t) do if DEFAULT[k] ~= nil then cfg[k] = v end end
    end
end)
local function saveCfg() pcall(function() writefile(DIR .. "/cfg.json", HttpService:JSONEncode(cfg)) end) end
-- 11-21 (dq_91): one friend keeps getting kicked #101, the owner never: put everyone once on the owner's movement settings
if (tonumber(cfg.tuneSet) or 0) < 91 then
    cfg.move, cfg.tpStep, cfg.tpWait, cfg.tweenSpeed, cfg.hover, cfg.swingRate, cfg.standDist = "Teleport", 60, 0.12, 60, 10, 10, 4
    cfg.tuneSet = 91
    saveCfg()
end
-- a fresh join (the owner ran the loader by hand) starts with Auto farm OFF; only our own teleports (Retry,
-- lobby trips) and reloads carry on farming (11-21: joining the game walked straight into a dungeon)
do
    local carryOn = G.dq_continue == true
    G.dq_continue = nil
    -- owner 11-21: Auto farm (fight in the dungeon) and Auto join (start a dungeon from the lobby) are separate;
    -- a fresh join never starts a dungeon by itself
    if not carryOn and cfg.autoJoin then cfg.autoJoin = false saveCfg() end
end

-- reload this file after every teleport (Retry / Return / PlaySolo move us to new servers)
pcall(function()
    if G.__dq_queued then return end -- queue once per server, not once per copy
    local q = queue_on_teleport or (syn and syn.queue_on_teleport)
    -- the owner's PC has dq/dev.flag: load the local build; everyone else loads the GitHub copy
    if q then
        q('getgenv().dq_continue = true local ok = pcall(function() if isfile and isfile("dq/dev.flag") then loadstring(readfile("dq/dq.lua"))() else error("web") end end) ' ..
          'if not ok then loadstring(game:HttpGet("https://raw.githubusercontent.com/moseeri01/dqhub/main/dq.lua"))() end')
        G.__dq_queued = true
    end
end)


local UIS = game:GetService("UserInputService")
local T = {
    bg = Color3.fromRGB(11, 11, 13), headBg = Color3.fromRGB(4, 4, 5), card = Color3.fromRGB(17, 17, 21),
    line = Color3.fromRGB(30, 30, 37), text = Color3.fromRGB(212, 212, 218), value = Color3.fromRGB(180, 180, 190),
    mute = Color3.fromRGB(138, 138, 148), faint = Color3.fromRGB(88, 88, 98), accent = Color3.fromRGB(138, 180, 255),
    onAccent = Color3.fromRGB(11, 11, 13), off = Color3.fromRGB(44, 44, 52), good = Color3.fromRGB(143, 209, 158),
    bad = Color3.fromRGB(232, 104, 104), white = Color3.fromRGB(236, 236, 242),
}
local UI = { pages = {}, tabs = {}, refreshers = {} }

local function new(class, props, parent)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    if parent then o.Parent = parent end
    return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o) end
local function stroke(o, c) new("UIStroke", { Color = c or T.line, Thickness = 1 }, o) end
local function label(parent, text, size, color, font, props)
    local l = new("TextLabel", {
        BackgroundTransparency = 1, Text = text, TextSize = size or 13, TextColor3 = color or T.text,
        Font = font or Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
    for k, v in pairs(props or {}) do l[k] = v end
    return l
end

local guiParent = (type(gethui) == "function" and gethui()) or game:GetService("CoreGui")
pcall(function() local o = guiParent:FindFirstChild("MoseeriDungeon") if o then o:Destroy() end end)
pcall(function() local o = guiParent:FindFirstChild("MoseeriDungeonToggle") if o then o:Destroy() end end)
local gui = new("ScreenGui", { Name = "MoseeriDungeon", ResetOnSpawn = false, DisplayOrder = 998, IgnoreGuiInset = true })
local WIN_W, HEAD_H, TAB_H = 780, 92, 40
local win = new("Frame", { Size = UDim2.fromOffset(WIN_W, 300), Position = UDim2.new(0.5, -WIN_W / 2, 0, 150),
    BackgroundColor3 = T.bg, BorderSizePixel = 0, Active = true }, gui)
corner(win, 12)
stroke(win)
-- (11-14 test: a tap on an empty part of the window went through to the game and opened its Events page.
-- An invisible button under everything takes those taps)
new("TextButton", { Name = "Sink", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, ZIndex = 0 }, win)
local scale = new("UIScale", { Scale = 1 }, win)
pcall(function()
    local vp = workspace.CurrentCamera.ViewportSize
    scale.Scale = math.clamp(math.min(vp.X * 0.62 / WIN_W, vp.Y * 0.8 / 460), 0.55, 1.2)
end)

-- header: spaced title, subtitle, a few stars, the ··· button hides the window
local head = new("Frame", { Size = UDim2.new(1, 0, 0, HEAD_H), BackgroundColor3 = T.headBg, BorderSizePixel = 0 }, win)
corner(head, 12)
new("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = T.headBg, BorderSizePixel = 0 }, head)
label(head, "M O S E E R I   D U N G E O N", 26, T.white, Enum.Font.GothamMedium, { Position = UDim2.fromOffset(28, 22), Size = UDim2.new(1, -120, 0, 32) })
label(head, "dungeon farm · limit test", 12, T.mute, Enum.Font.Gotham, { Position = UDim2.fromOffset(28, 56), Size = UDim2.new(1, -120, 0, 16) })
local rng = Random.new(7)
for _ = 1, 26 do
    local s = rng:NextInteger(1, 2)
    new("Frame", { Size = UDim2.fromOffset(s, s), Position = UDim2.new(rng:NextNumber(0.35, 0.98), 0, rng:NextNumber(0.1, 0.9), 0),
        BackgroundColor3 = T.white, BackgroundTransparency = rng:NextNumber(0.3, 0.8), BorderSizePixel = 0 }, head)
end
local dots = new("TextButton", { Size = UDim2.fromOffset(40, 28), Position = UDim2.new(1, -56, 0, 18), BackgroundTransparency = 1,
    Text = "···", TextSize = 20, TextColor3 = T.mute, Font = Enum.Font.GothamBold }, head)

-- drag by the header (mouse and touch)
do
    local dragging, start, startPos
    -- (11-14 test: the window slid on later taps - the drag only ends when THIS touch ends, and only the same
    -- touch moves it)
    local dragInput
    head.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, start, startPos, dragInput = true, input.Position, win.Position, input
            local c
            c = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false dragInput = nil c:Disconnect() end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local same = (input == dragInput) or (input.UserInputType == Enum.UserInputType.MouseMovement and dragInput and dragInput.UserInputType == Enum.UserInputType.MouseButton1)
        if same then
            local d = (input.Position - start) / scale.Scale
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if input == dragInput or input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false dragInput = nil end
    end)
end

-- tabs
local tabBar = new("Frame", { Size = UDim2.new(1, -40, 0, TAB_H), Position = UDim2.fromOffset(20, HEAD_H), BackgroundTransparency = 1 }, win)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)
new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.fromOffset(0, HEAD_H + TAB_H), BackgroundColor3 = T.line, BorderSizePixel = 0 }, win)
local body = new("Frame", { Size = UDim2.new(1, -36, 0, 10), Position = UDim2.fromOffset(18, HEAD_H + TAB_H + 10), BackgroundTransparency = 1 }, win)

local function fitHeight(page)
    local h = 0
    for _, col in ipairs(page.cols) do
        local ch = 0
        for _, c in ipairs(col:GetChildren()) do
            if c:IsA("Frame") then ch = ch + c.AbsoluteSize.Y / scale.Scale + 10 end
        end
        if ch > h then h = ch end
    end
    win.Size = UDim2.fromOffset(WIN_W, HEAD_H + TAB_H + 20 + h)
end
function UI.show(name)
    for n, p in pairs(UI.pages) do p.frame.Visible = (n == name) end
    for n, t in pairs(UI.tabs) do
        t.btn.TextColor3 = (n == name) and T.white or T.mute
        t.bar.Visible = (n == name)
    end
    UI.current = name
    task.delay(0.15, function() pcall(fitHeight, UI.pages[name]) end)
end
function UI.page(name, order)
    local btn = new("TextButton", { AutoButtonColor = false, BackgroundTransparency = 1, Text = name, TextSize = 14,
        Font = Enum.Font.GothamMedium, TextColor3 = T.mute, LayoutOrder = order, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X }, tabBar)
    local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = T.accent, BorderSizePixel = 0, Visible = false }, btn)
    UI.tabs[name] = { btn = btn, bar = bar }
    local frame = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false }, body)
    local cols = {}
    for i = 1, 2 do
        local col = new("Frame", { Size = UDim2.new(0.5, -6, 1, 0), Position = UDim2.new((i - 1) * 0.5, (i - 1) * 6, 0, 0), BackgroundTransparency = 1 }, frame)
        new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, col)
        cols[i] = col
    end
    local page = { frame = frame, cols = cols }
    UI.pages[name] = page
    btn.MouseButton1Click:Connect(function() UI.show(name) end)
    return page
end

-- a card: title + rows with a hairline between them
local cardN = 0
function UI.card(page, side, title)
    cardN = cardN + 1
    local c = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.card,
        BorderSizePixel = 0, LayoutOrder = cardN }, page.cols[side])
    corner(c, 10)
    new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 8) }, c)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, c)
    label(c, title, 14, T.white, Enum.Font.GothamMedium, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0 })
    return { frame = c, n = 0 }
end
local function row(card, text, h)
    card.n = card.n + 1
    local r = new("Frame", { Size = UDim2.new(1, 0, 0, h or 38), BackgroundTransparency = 1, LayoutOrder = card.n }, card.frame)
    if card.n > 1 then new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.line, BorderSizePixel = 0 }, r) end
    label(r, text, 13, T.text, Enum.Font.Gotham, { Size = UDim2.new(0.62, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
    return r
end

-- switch
function UI.toggle(card, text, get, setv)
    local r = row(card, text)
    local word = label(r, "", 11, T.faint, Enum.Font.GothamMedium, { Size = UDim2.fromOffset(30, 20), Position = UDim2.new(1, -84, 0.5, -10), TextXAlignment = Enum.TextXAlignment.Right })
    local sw = new("TextButton", { AutoButtonColor = false, Text = "", Size = UDim2.fromOffset(46, 24), Position = UDim2.new(1, -46, 0.5, -12),
        BackgroundColor3 = T.off, BorderSizePixel = 0 }, r)
    corner(sw, 12)
    local knob = new("Frame", { Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(3, 3), BackgroundColor3 = T.white, BorderSizePixel = 0 }, sw)
    corner(knob, 8)
    local function paint()
        local on = get() and true or false
        sw.BackgroundColor3 = on and T.accent or T.off
        knob.Position = on and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3)
        word.Text = on and "ON" or "OFF"
        word.TextColor3 = on and T.accent or T.faint
    end
    sw.MouseButton1Click:Connect(function() pcall(setv, not get()) paint() end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end
-- choice: the value on the right, a tap goes to the next option
function UI.choice(card, text, options, get, setv)
    local r = row(card, text)
    local b = new("TextButton", { AutoButtonColor = false, BackgroundColor3 = T.off, BorderSizePixel = 0, Size = UDim2.new(0.45, 0, 0, 26), Position = UDim2.new(0.55, 0, 0.5, -13),
        Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = T.white, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd }, r)
    corner(b, 6)
    local function paint() b.Text = tostring(get()) .. "  ›" end
    b.MouseButton1Click:Connect(function()
        local cur, i = tostring(get()), 0
        for k, o in ipairs(options) do if tostring(o) == cur then i = k end end
        pcall(setv, options[i % #options + 1])
        paint()
    end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end
-- number with - and +
function UI.stepper(card, text, lo, hi, get, setv, step)
    local r = row(card, text)
    local box = new("Frame", { Size = UDim2.fromOffset(104, 26), Position = UDim2.new(1, -104, 0.5, -13), BackgroundTransparency = 1 }, r)
    local v = label(box, "", 13, T.value, Enum.Font.GothamMedium, { Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center })
    local function btn(txt, x, d)
        local b = new("TextButton", { AutoButtonColor = false, Text = txt, TextSize = 15, Font = Enum.Font.GothamMedium, TextColor3 = T.text,
            BackgroundColor3 = T.off, Size = UDim2.fromOffset(26, 26), Position = UDim2.new(x, x == 0 and 0 or -26, 0, 0), BorderSizePixel = 0 }, box)
        corner(b, 6)
        b.MouseButton1Click:Connect(function() pcall(setv, math.clamp((tonumber(get()) or lo) + d, lo, hi)) v.Text = tostring(get()) end)
    end
    btn("−", 0, -(step or 1))
    btn("+", 1, (step or 1))
    v.Text = tostring(get())
    UI.refreshers[#UI.refreshers + 1] = function() v.Text = tostring(get()) end
end
-- outlined accent button, like AA "Setup ›"
function UI.button(card, text, btnText, fn)
    local r = row(card, text)
    local b = new("TextButton", { AutoButtonColor = false, Text = btnText .. "  ›", TextSize = 13, Font = Enum.Font.Gotham, TextColor3 = T.accent,
        BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 28), Position = UDim2.new(1, -110, 0.5, -14) }, r)
    corner(b, 7)
    stroke(b, T.accent)
    b.MouseButton1Click:Connect(function() task.spawn(function() pcall(fn) end) end)
end
-- label + live value
function UI.info(card, text, getText)
    local r = row(card, text)
    local v = label(r, "", 13, T.value, Enum.Font.Gotham, { Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.new(0.4, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
    UI.refreshers[#UI.refreshers + 1] = function() local ok, s = pcall(getText) v.Text = ok and tostring(s) or "-" end
end
function UI.note(card, text)
    card.n = card.n + 1
    label(card.frame, text, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        TextWrapped = true, LayoutOrder = card.n, TextYAlignment = Enum.TextYAlignment.Top })
end

-- pills: several on/off choices in one row (wraps)
function UI.pills(card, options, isOn, toggleOne)
    card.n = card.n + 1
    local holder = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = card.n }, card.frame)
    new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, holder)
    new("UIGridLayout", { CellSize = UDim2.fromOffset(84, 26), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, holder)
    local paints = {}
    for i, o in ipairs(options) do
        local b = new("TextButton", { AutoButtonColor = false, Text = o, TextSize = 12, Font = Enum.Font.GothamMedium, LayoutOrder = i, BorderSizePixel = 0 }, holder)
        corner(b, 13)
        local function paint()
            local on = isOn(o)
            b.BackgroundColor3 = on and T.accent or T.off
            b.TextColor3 = on and T.onAccent or T.mute
        end
        b.MouseButton1Click:Connect(function() pcall(toggleOne, o) paint() end)
        paint()
        paints[#paints + 1] = paint
    end
    UI.refreshers[#UI.refreshers + 1] = function() for _, p in ipairs(paints) do p() end end
end
-- text box on the right of a row
function UI.input(card, text, placeholder, get, setv)
    local r = row(card, text)
    local box = new("TextBox", { Size = UDim2.new(0.5, 0, 0, 26), Position = UDim2.new(0.5, 0, 0.5, -13), BackgroundColor3 = T.off, BorderSizePixel = 0,
        Text = tostring(get() or ""), PlaceholderText = placeholder, PlaceholderColor3 = T.faint, TextColor3 = T.text, Font = Enum.Font.Gotham,
        TextSize = 12, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left }, r)
    corner(box, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
    box.FocusLost:Connect(function() pcall(setv, box.Text) end)
end

local function notify(msg)
    log(msg)
    pcall(function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "moseeri dungeon", Text = tostring(msg), Duration = 4 }) end)
end
-- dropdown: label on the left, the picked item on the right; a click opens the list under the row, a pick closes it
-- multi (optional) = { isOn = function(key), summary = function() } : several picks, the list stays open
function UI.dropdown(card, text, height, getItems, getKey, onPick, multi)
    local r = row(card, text)
    local b = new("TextButton", { AutoButtonColor = false, BackgroundColor3 = T.off, BorderSizePixel = 0, Size = UDim2.new(0.78, 0, 0, 28), Position = UDim2.new(0.22, 0, 0.5, -14),
        Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = T.white, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" }, r)
    corner(b, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 24) }, b)
    local arrow = label(b, "v", 12, T.mute, Enum.Font.GothamBold, { Size = UDim2.fromOffset(14, 28), Position = UDim2.new(1, 6, 0, 0) })
    -- the list floats over the window under the button (owner 11-21: opening must not push the rows below down)
    local sf = new("ScrollingFrame", { Size = UDim2.fromOffset(200, height), BackgroundColor3 = T.card, BorderSizePixel = 0, Visible = false, ZIndex = 50,
        ScrollBarThickness = 4, ScrollBarImageColor3 = T.faint, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y }, win)
    corner(sf, 8)
    stroke(sf, T.accent)
    new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, sf)
    new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, sf)
    local rows, sig = {}, ""
    local paint
    local setOpen
    setOpen = function(on)
        if on then
            if UI.openDD and UI.openDD ~= setOpen then pcall(UI.openDD, false) end -- one list open at a time
            UI.openDD = setOpen
            local s = scale.Scale
            local ap = (b.AbsolutePosition - win.AbsolutePosition) / s
            sf.Size = UDim2.fromOffset(b.AbsoluteSize.X / s + 8, height)
            sf.Position = UDim2.fromOffset(ap.X - 4, ap.Y + b.AbsoluteSize.Y / s + 3)
        elseif UI.openDD == setOpen then
            UI.openDD = nil
        end
        sf.Visible = on
        arrow.Text = on and "^" or "v"
    end
    local lastKey = {}
    paint = function()
        -- closed and nothing picked since last time: skip rebuilding the list (ran every second, heavy on phones)
        if not sf.Visible and sig ~= "" and getKey() == lastKey then return end
        lastKey = getKey()
        local items = getItems()
        local cur = getKey()
        local s = {}
        -- (v2_39) an item may be a group header ({ header = true, text = }) or carry sub (a second small line),
        -- right (text at the right edge), dim (greyed) and short (the text shown in the closed row)
        for i, it in ipairs(items) do s[i] = it.text .. "~" .. tostring(it.sub) .. "~" .. tostring(it.right) .. "~" .. tostring(it.dim) end
        s = table.concat(s, "|")
        if s ~= sig then
            sig = s
            for _, x in ipairs(rows) do x.btn:Destroy() end
            rows = {}
            for i, it in ipairs(items) do
                if it.header then
                    local hd = label(sf, it.text, 11, T.mute, Enum.Font.GothamBold, { Size = UDim2.new(1, -8, 0, 22), LayoutOrder = i })
                    new("UIPadding", { PaddingLeft = UDim.new(0, 4) }, hd)
                    rows[#rows + 1] = { btn = hd }
                else
                    local x = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = T.off, BorderSizePixel = 0,
                        Size = UDim2.new(1, -8, 0, it.sub and 42 or 26), LayoutOrder = i }, sf)
                    corner(x, 5)
                    local main = label(x, it.text, 13, it.dim and T.mute or T.text, Enum.Font.GothamMedium, { Size = UDim2.new(1, -20, 0, 20),
                        Position = UDim2.new(0, 10, 0, 3), TextTruncate = Enum.TextTruncate.AtEnd })
                    local sub, right = nil, nil
                    if it.sub then
                        sub = label(x, it.sub, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(0.6, -10, 0, 16), Position = UDim2.new(0, 10, 0, 22),
                            TextTruncate = Enum.TextTruncate.AtEnd })
                    end
                    if it.right then
                        right = label(x, it.right, 12, T.mute, Enum.Font.Gotham, { Size = UDim2.new(0.4, -10, 0, 16), Position = UDim2.new(0.6, 0, 0, it.sub and 22 or 5),
                            TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd })
                    end
                    x.MouseButton1Click:Connect(function() pcall(onPick, it.key) if not multi then setOpen(false) end lastKey = {} paint() end)
                    rows[#rows + 1] = { btn = x, key = it.key, main = main, sub = sub, right = right, dim = it.dim }
                end
            end
        end
        -- the list floats at ZIndex 50: its rows must draw above it (Global z order hid them, 11-21)
        for _, dsc in ipairs(sf:GetDescendants()) do if dsc:IsA("GuiObject") and dsc.ZIndex < 52 then dsc.ZIndex = 52 end end
        local shown = "-"
        for _, it in ipairs(items) do if not it.header and it.key == cur then shown = it.short or it.text end end
        if multi then pcall(function() shown = multi.summary() end) end
        b.Text = shown
        for _, x in ipairs(rows) do
            if x.main then
                local on = (multi and multi.isOn(x.key)) or (not multi and x.key == cur)
                x.btn.BackgroundColor3 = on and T.accent or T.off
                x.main.TextColor3 = on and T.onAccent or (x.dim and T.mute or T.text)
                if x.sub then x.sub.TextColor3 = on and T.onAccent or T.mute end
                if x.right then x.right.TextColor3 = on and T.onAccent or T.mute end
            end
        end
    end
    UI.dropdowns = UI.dropdowns or {}
    UI.dropdowns[text] = setOpen      -- (remote: open <label>, for screenshots)
    b.MouseButton1Click:Connect(function() setOpen(not sf.Visible) end)
    paint()
    UI.refreshers[#UI.refreshers + 1] = paint
end

-- owner 11-21: "pick in a dropdown, not tap to cycle" - every choice row is now a dropdown
UI.choice = function(card, text, options, get, setv)
    UI.dropdown(card, text, math.min(160, #options * 29 + 6), function()
        local out = {}
        for _, o in ipairs(options) do out[#out + 1] = { key = o, text = tostring(o) } end
        return out
    end, get, setv)
end
-- switching tabs closes an open list
do
    local oldShow = UI.show
    UI.show = function(name)
        if UI.openDD then pcall(UI.openDD, false) end
        return oldShow(name)
    end
end

local MSafe = (function()
-- msafe: shared "safety kick" for the moseeri hubs (dq, aa, gpo, nexus). 2026-11-21.
-- The hub tells msafe what is going on; msafe decides when to leave and kicks with
--   "<name>: please rejoin for safety [Sxx] <reason>"
-- Codes:
--   S01 stuck      : hub is active and reported no progress for cfg.stuckMin minutes. First time -> hub's onStuck
--                    (e.g. back to the lobby); again within 10 minutes (kept across servers) -> kick.
--   S02 pull-backs : more than cfg.pullbackMax server position corrections in 60 s (the hub reports them).
--   S03 staff      : a player whose role in the game's group (or cfg.groupId) contains a staff word joins.
--   S04 errors     : more than cfg.errorMax script errors in 5 minutes (the hub reports them).
-- Usage (hub):
--   local Safe = MSafe.start({ name = "moseeri dungeon", onLog = log, onStuck = function() ... end })
--   Safe.active = true / false      -- farming right now?
--   Safe.progress()                 -- something moved forward (damage, run start / end, new server)
--   Safe.pullback()  Safe.error()   -- report events
--   Safe.cfg.enabled = false        -- the hub's on/off switch
-- Light on purpose (phones): one check every 5 s, a file is written only when stuck or kicking.
local M = {}
M.cfg = {
    enabled = true, name = "moseeri", stuckMin = 3, pullbackMax = 10, errorMax = 50, staffCheck = true, groupId = nil,
    -- whole words only ("dev" must not hit "Devoted", "mod" not "Model"); no "creator" (content creators are fans)
    staffWords = { "mod", "mods", "moderator", "admin", "administrator", "dev", "developer", "owner", "co-owner", "staff", "manager", "tester" },
    file = "msafe_state.json",
}
M.active = false
local lastProgress = os.clock()
local pulls, errs = {}, {}
local onLog, onStuck = function() end, nil
local HttpService = game:GetService("HttpService")

local function readState()
    local ok, t = pcall(function()
        if isfile and isfile(M.cfg.file) then return HttpService:JSONDecode(readfile(M.cfg.file)) end
    end)
    return (ok and type(t) == "table") and t or {}
end
local function writeState(t) pcall(function() if writefile then writefile(M.cfg.file, HttpService:JSONEncode(t)) end end) end
local function say(s) pcall(onLog, s) end
local function countSince(list, secs)
    local now, n = os.clock(), 0
    for i = #list, 1, -1 do
        if now - list[i] <= secs then n = n + 1 else table.remove(list, i) end
    end
    return n
end

function M.kick(code, reason)
    if not M.running then return end
    local msg = string.format("%s: please rejoin for safety [%s] %s", M.cfg.name, code, reason or "")
    local st = readState()
    st.lastKick = { code = code, reason = reason, at = os.date("%Y-%m-%d %H:%M:%S"), t = os.time(), hub = M.cfg.name }
    writeState(st)
    say("SAFETY KICK " .. msg)
    M.running = false
    task.wait(0.5)
    pcall(function() game:GetService("Players").LocalPlayer:Kick(msg) end)
end
-- the hub calls this when it shuts down (reload / second copy): the watcher must not outlive it
function M.stop() M.running = false M.active = false end
function M.progress() lastProgress = os.clock() end
-- at most one pull-back per 0.5 s: a hub that reports every frame must not trip S02 (dq 11-21: 686 in 60 s)
function M.pullback()
    local now = os.clock()
    if pulls[#pulls] and now - pulls[#pulls] < 0.5 then return end
    pulls[#pulls + 1] = now
end
function M.error()
    local now = os.clock()
    if errs[#errs] and now - errs[#errs] < 0.2 then return end
    errs[#errs + 1] = now
end

function M.start(opts)
    for k, v in pairs(opts or {}) do
        if k == "onLog" then onLog = v elseif k == "onStuck" then onStuck = v else M.cfg[k] = v end
    end
    if M.running then return M end
    M.running = true
    lastProgress = os.clock()
    -- tell the hub why we left last time (once, within a day)
    local st = readState()
    if st.lastKick and os.time() - (tonumber(st.lastKick.t) or 0) < 86400 and not st.lastKick.shown then
        say(string.format("SAFETY last kick %s [%s] %s (%s)", tostring(st.lastKick.at), tostring(st.lastKick.code), tostring(st.lastKick.reason), tostring(st.lastKick.hub)))
        st.lastKick.shown = true
        writeState(st)
    end
    local Players = game:GetService("Players")
    local LP = Players.LocalPlayer
    if not M.cfg.groupId then
        pcall(function() if game.CreatorType == Enum.CreatorType.Group then M.cfg.groupId = game.CreatorId end end)
    end
    local function staffCheck(p)
        if p == LP or not M.cfg.groupId then return end
        task.spawn(function()
            local ok, role = pcall(function() return p:GetRoleInGroup(M.cfg.groupId) end)
            if not (ok and type(role) == "string") or not (M.cfg.enabled and M.cfg.staffCheck and M.running) then return end
            local r = role:lower()
            for word in r:gmatch("[%a%-]+") do
                for _, w in ipairs(M.cfg.staffWords) do
                    if word == w then M.kick("S03", "staff in server: " .. p.Name .. " (" .. role .. ")") return end
                end
            end
        end)
    end
    for _, p in ipairs(Players:GetPlayers()) do staffCheck(p) end
    Players.PlayerAdded:Connect(staffCheck)
    task.spawn(function()
        while M.running do
            task.wait(5)
            if M.cfg.enabled then
                local np = countSince(pulls, 60)
                if np > M.cfg.pullbackMax then M.kick("S02", "position pulled back " .. np .. " times in 60 s") return end
                local ne = countSince(errs, 300)
                if ne > M.cfg.errorMax then M.kick("S04", "script errors: " .. ne .. " in 5 min") return end
                if M.active and os.clock() - lastProgress > M.cfg.stuckMin * 60 then
                    lastProgress = os.clock()
                    local s2 = readState()
                    local again = os.time() - (tonumber(s2.stuckAt) or 0) < 600
                    -- stuckKick = false (dq 11-23): never kick for S01, the hub recovers (rejoins) every time
                    if (again and M.cfg.stuckKick ~= false) or not onStuck then
                        s2.stuckAt = 0 writeState(s2)
                        M.kick("S01", "no progress for " .. M.cfg.stuckMin .. " min" .. (again and " (twice in 10 min)" or ""))
                        return
                    end
                    s2.stuckAt = os.time() writeState(s2)
                    say("SAFETY no progress for " .. M.cfg.stuckMin .. " min - trying the hub's recovery first")
                    pcall(onStuck)
                end
            else
                lastProgress = os.clock()
            end
            if not M.active then lastProgress = os.clock() end
        end
    end)
    return M
end

return M

end)()

--------------------------------------------------------------------------------
-- game access
--------------------------------------------------------------------------------
local function R(name) return RS:FindFirstChild(name) end
-- ask the server with a time limit: a RemoteFunction that never answers used to freeze the lobby jobs (11-21 16:25)
local function ask(name, ...)
    local rem = RS:FindFirstChild(name)
    if not rem then return nil end
    local args = table.pack(...)
    local done, res = false, nil
    task.spawn(function()
        local ok, r = pcall(function() return rem:InvokeServer(table.unpack(args, 1, args.n)) end)
        res = ok and r or nil
        done = true
    end)
    local t0 = os.clock()
    while not done and os.clock() - t0 < 6 do task.wait(0.1) end
    if not done then log("SLOW " .. name .. ": no answer in 6 s, moving on") end
    return res
end
local function char() return LP.Character end
local function hrp() local c = char() return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char() return c and c:FindFirstChildOfClass("Humanoid") end
local function flat(v) return Vector3.new(v.X, 0, v.Z) end
local function v3s(v) return string.format("%.0f,%.0f,%.0f", v.X, v.Y, v.Z) end
local function num(v) return (v and v.Value) or 0 end

local function mobRoot(m) if not m:IsA("Model") then return nil end return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart end
local function enemies()
    local out = {}
    local folder = workspace:FindFirstChild("Enemies")
    if not folder then return out end
    for _, m in ipairs(folder:GetChildren()) do
        local h = m:IsA("Model") and m:FindFirstChildOfClass("Humanoid")
        local r = mobRoot(m)
        -- dummies in the lobby have ~1e25 hp: never a target (11-22: cap was 1e12, lvl 185 boss Pale Bloodmaiden has 1.75e12 and was skipped)
        if h and r and h.Health > 0 and h.MaxHealth < 1e20 then out[#out + 1] = { m = m, h = h, r = r } end
    end
    return out
end
local function pickTarget()
    local me = hrp()
    if not me then return nil end
    local best, bestScore
    for _, e in ipairs(enemies()) do
        local d = (flat(e.r.Position) - flat(me.Position)).Magnitude
        local score = d
        if cfg.bossFirst then score = score - e.h.MaxHealth / 50 end -- big hp pool = boss = first
        -- orbs / gems / totems next to a boss (Sunken Fortress: Barbed Orb Sentry beside Fortress Shaman, 11-21 one-hit death): before the boss
        -- 11-23 lvl 260: the game carried us to the next room and we flew back to a mob 900 studs behind, again and again
        -- for a minute (time lost, hits on the way). After a carry, mobs more than 400 studs away wait 20 s.
        if S.carriedUntil and os.clock() < S.carriedUntil and d > 400 then score = score + 1e9 end
        local nm = e.m.Name:lower()
        if nm:find("orb") or nm:find("sentry") or nm:find("crystal") or nm:find("gem") or nm:find("totem") or nm:find("pylon") or nm:find("statue") or nm:find("powered") or nm:find("pillar") or nm:find("generator") or nm:find("obelisk") or nm:find("tower") then score = score - 2000 end
        -- healers first of all: Fortress Shaman carries a "heal" Beam (dq mobs scan 11-21) and keeps the others alive
        if e.m:FindFirstChild("heal") or nm:find("shaman") or nm:find("cleric") or nm:find("healer") then score = score - 3000 end
        -- the game marks real bosses with attribute Boss = true (seen on Blightwyrm): those first among big mobs
        if e.m:GetAttribute("Boss") == true then score = score - 1500 end
        -- dq_166: two bosses with the same hp (Lifeless + Soulless): take the tall one first - we can swing it from over
        -- every attack box of that room (S.hoverFor 29), the other only gets Q / E while zones are up
        if S.hoverFor and S.hoverFor(e.m) >= 28 then score = score - 200 end
        -- dq_162 owner 11-24 lvl 275 Calamity: Lifeless Flower (2.25B) sits by Lifeless + Soulless, they swap immunity and heal back
        -- while it lives; the hp/50 boss bonus (3e14 there) buried the -2000 bonuses, so the flower never got hit. Flower first, always.
        if nm:find("flower") or nm:find("lotus") or nm:find("bloom") then score = score - 1e16 end
        -- a mob whose hp did not move while we hit it (decoy / immune phase, owner 11-21: lvl 80 boss copies): skip it a while
        -- 11-21 lvl 80 Electro Elemental: immune at 50% until Powered Statue (8.26M) dies; +100000 lost to the -hp/50 boss bonus -> +1e9 = only when nothing else is left
        if S.decoy and S.decoy[e.m] and (os.clock() < S.decoy[e.m] or (S.decoyHp and S.decoyHp[e.m] and e.h.Health >= S.decoyHp[e.m] - e.h.MaxHealth * 0.002)) then score = score + 1e18 end -- dq_162: 1e18 so an immune flower (-1e16) still waits
        -- 11-21 lvl 80: 12 mobs with the same 11M hp -> the pick flipped several times a second and nothing died.
        -- Stick to the current target (worth 60 studs) and among equals finish the most hurt one first.
        if e.m == S.stickTo then score = score - 60 end
        score = score + (e.h.Health / math.max(e.h.MaxHealth, 1)) * 30
        if not bestScore or score < bestScore then best, bestScore = e, score end
    end
    S.stickTo = best and best.m or nil
    return best
end

-- Swing or Bolt, the same rule the game's spellHandler uses
local function attack()
    local data = LP:FindFirstChild("data")
    local useBolt = data and data:FindFirstChild("physicalSP") and data:FindFirstChild("spellSP")
        and data.physicalSP.Value < data.spellSP.Value
    local r = R(useBolt and "Bolt" or "Swing")
    if r then r:FireServer() S.swings = S.swings + 1 end
end
local function castReady(key)
    local v = LP:FindFirstChild("cooldown" .. key)
    return v and v.Value <= 0
end
local function cast(key) local r = R("useSpell") if r then r:FireServer(key) end end
-- backup spell slots (hotbar 1 / 2 = SpellSwap1 / SpellSwap2 -> UseBackup("Slot1"/"Slot2")). Test 11-21: does swapping
-- a backup spell in give extra casts while Q / E cool down? While S.useSwap is on: Q cooling -> swap Slot1 + cast Q,
-- E cooling -> swap Slot2 + cast E (each slot at most every 1.2 s). Cooldown values before/after are logged.
local lastSwap = { Slot1 = 0, Slot2 = 0 }
local function cdv(key) local v = LP:FindFirstChild("cooldown" .. key) return v and v.Value or -1 end
local function trySwap()
    if not S.useSwap then return end
    local ub = R("UseBackup")
    if not ub then return end
    for slot, key in pairs({ Slot1 = "Q", Slot2 = "E" }) do
        if cdv(key) > 0.3 and os.clock() - lastSwap[slot] > 1.2 then
            lastSwap[slot] = os.clock()
            local before = cdv(key)
            ub:FireServer(slot)
            task.delay(0.25, function()
                local mid = cdv(key)
                cast(key)
                task.delay(0.25, function()
                    S.swapN = (S.swapN or 0) + 1
                    if S.swapN <= 12 then log(string.format("SWAP %s: cd%s %.1f -> after swap %.1f -> after cast %.1f", slot, key, before, mid, cdv(key))) end
                end)
            end)
        end
    end
end

-- way back to the lobby when the game's own ReturnLobby does nothing (dead in Calamity hardcore, 11-21)
local TeleportService = game:GetService("TeleportService")
local function toLobby()
    local ok, err = pcall(function() TeleportService:Teleport(LOBBY_PLACE, LP) end)
    log("TELEPORT to lobby -> " .. (ok and "sent" or tostring(err)))
end
-- a teleport that fails leaves the loading screen up forever: try again
pcall(function()
    F.conns[#F.conns + 1] = LP.OnTeleport:Connect(function(state)
        if state == Enum.TeleportState.Failed then
            log("TELEPORT failed - lobby in 5 s")
            task.delay(5, function() if F.alive then toLobby() end end)
        end
    end)
end)
pcall(function()
    F.conns[#F.conns + 1] = TeleportService.TeleportInitFailed:Connect(function(_, res, msg)
        log("TELEPORT init failed " .. tostring(res) .. " " .. tostring(msg) .. " - lobby in 5 s")
        task.delay(5, function() if F.alive then toLobby() end end)
    end)
end)

-- press a game button the way a click would
local function press(btn)
    if not btn then return false end
    local done = false
    pcall(function()
        if firesignal then firesignal(btn.MouseButton1Click) done = true end
    end)
    if not done then
        pcall(function()
            for _, c in ipairs(getconnections(btn.MouseButton1Click)) do c:Fire() done = true end
            for _, c in ipairs(getconnections(btn.Activated)) do c:Fire() done = true end
        end)
    end
    return done
end
local function pgui(path)
    local o = LP:FindFirstChild("PlayerGui")
    for name in string.gmatch(path, "[^%.]+") do
        if not o then return nil end
        o = o:FindFirstChild(name)
    end
    return o
end
local function shown(o)
    if not o then return false end
    if o:IsA("ScreenGui") then return o.Enabled end
    while o and o:IsA("GuiObject") do
        if not o.Visible then return false end
        o = o.Parent
    end
    if o and o:IsA("ScreenGui") then return o.Enabled end
    return true
end

--------------------------------------------------------------------------------
-- moving (Teleport / Tween / Walk) + pull-back watch
--------------------------------------------------------------------------------
local hold = nil -- hover hold {cf, t}, see engage
local lastSet = nil -- {pos, t}
-- movement budget (11-21 DQKICK numbers: the kicked friend moved 630 studs in 10 s, 35 of 59 quarter-seconds over
-- 12 studs; the owner, never kicked, 300-400). Our own moves are counted; above ~40 studs/s over 5 s we slow down.
local moveLog = {}
local MOVE_BUDGET = 200 -- studs per 5 s
local function movedRecently()
    local now, sum = os.clock(), 0
    for i = #moveLog, 1, -1 do
        if now - moveLog[i].t > 5 then table.remove(moveLog, i) else sum = sum + moveLog[i].d end
    end
    return sum
end
S.movedRecently = movedRecently
local function setCF(cf)
    local r = hrp()
    if not r then return end
    local d = (cf.Position - r.Position).Magnitude
    if d > 1 then moveLog[#moveLog + 1] = { t = os.clock(), d = d } end
    -- 11-22 lvl 185: a spot the game keeps pushing us out of (wall / big boss body) -> go where it puts us instead
    if S.blockedSpots then
        local now = os.clock()
        for i = #S.blockedSpots, 1, -1 do
            local b = S.blockedSpots[i]
            if now > b.untilT then table.remove(S.blockedSpots, i)
            elseif (flat(cf.Position) - flat(b.set)).Magnitude < 5 then cf = CFrame.new(b.now) * (cf - cf.Position) break end
        end
    end
    r.AssemblyLinearVelocity = Vector3.zero
    r.CFrame = cf
    S.ownSetT = os.clock() -- dq_184: for the dev flight recorder (who moved us?)
    S.floatY = cf.Position.Y -- dq_161: keep this height until the next move
    hold = nil -- a real move ends any hover hold (old hold pulled us back to the last mob)
    lastSet = { pos = cf.Position, t = os.clock() }
end
-- after our own CFrame set the character must stay there; a jump of >10 studs within 0.6 s = the server pulled us back
F.conns[#F.conns + 1] = RunService.Heartbeat:Connect(function()
    if not lastSet then return end
    local r = hrp()
    if not r then return end
    local dt = os.clock() - lastSet.t
    if dt > 0.6 then lastSet = nil return end
    -- sideways only: falling after a hover is gravity, not the server
    if (flat(r.Position) - flat(lastSet.pos)).Magnitude > 10 then
        local now = os.clock()
        local h = hum()
        -- 11-22 S02 kick lvl 185: dying / respawning moves the body; that is not the server pulling us back
        if not h or h.Health <= 0 or now - (S.deathT or -99) < 5 then lastSet = nil return end
        -- the same set spot pushed to the same place again = blocked spot (wall / boss body), not a server rollback:
        -- count it once, then stop asking for that spot for 20 s (setCF swaps it for where the game puts us)
        local same = S.lastPb and now - S.lastPb.t < 10 and (S.lastPb.set - lastSet.pos).Magnitude < 4 and (S.lastPb.now - r.Position).Magnitude < 4
        -- 11-23 lvl 260 (S02 kick 22:07): the body was being CARRIED - each "pull" put us further along one line (680 studs
        -- in 2 s), the next set went back and the carry went on. A server rollback puts us back, not further ahead.
        -- Same direction as the last pull, within 1 s, and further on = carried: not counted, and we let it finish (1.5 s).
        local carried = false
        if S.lastPb and now - S.lastPb.t < 1 then
            local a = flat(S.lastPb.now) - flat(S.lastPb.set)
            local b = flat(r.Position) - flat(lastSet.pos)
            -- dq_178: and this pull is at least 25 studs. Two 13-16 stud pushes the same way when we landed among the
            -- mobs of room 6 counted as a carry (11-24 12:27): everything paused 1.5 s between 6 mobs -> 2 hits, dead.
            if a.Magnitude > 1 and b.Magnitude >= 25 and a.Unit:Dot(b.Unit) > 0.8 and (flat(r.Position) - flat(S.lastPb.now)).Magnitude > 3 then carried = true end
        end
        local prevPb = S.lastPb
        S.lastPb = { set = lastSet.pos, now = r.Position, t = now, carried = carried }
        -- dq_182: first pull of a chain (none in the 4 s before it) = where the game picked us up
        if not S.pbFirst or not prevPb or now - prevPb.t > 4 then S.pbFirst = { set = lastSet.pos, t = now } end
        if carried then
            -- dq_169: remember where this carry picked us up. dq_182: the chain's first pull, not the pull before this one -
            -- that one was already 400 studs down the carry path (11-24 13:27: keep-out noted mid-path, we flew back into
            -- the real trigger, were carried a second time and died on the way).
            if prevPb and not prevPb.carried and S.noteCarry then pcall(S.noteCarry, (S.pbFirst and S.pbFirst.set) or prevPb.set) end
            S.movingUntil = now + 1.5
            S.carriedUntil = now + 20
            hold = nil
            if now - (S.carryLogT or 0) > 3 then S.carryLogT = now log(string.format("CARRIED to %s - letting the game move us, not counted as a pull-back", v3s(r.Position))) end
        elseif same then
            S.blockedSpots = S.blockedSpots or {}
            table.insert(S.blockedSpots, { set = lastSet.pos, now = r.Position, untilT = now + 20 })
            log(string.format("BLOCKED SPOT %s (pushed to %s again) - avoided 20 s, not counted", v3s(lastSet.pos), v3s(r.Position)))
        else
            S.pullBacks = S.pullBacks + 1
            if MSafe then MSafe.pullback() end
            log(string.format("PULLBACK set %s now %s", v3s(lastSet.pos), v3s(r.Position)))
        end
        lastSet = nil
    end
end)

local function faceCF(pos, lookAt)
    local l = Vector3.new(lookAt.X, pos.Y, lookAt.Z)
    if (l - pos).Magnitude < 0.1 then return CFrame.new(pos) end
    return CFrame.lookAt(pos, l)
end

-- move to pos; returns when there (or after a timeout). lookAt optional.
local function moveTo(pos, lookAt, mode)
    mode = mode or cfg.move
    hold = nil
    -- dq_166: one mover at a time. A dodge that started while the fight loop was still stepping to the boss (or a second
    -- dodge while the first was in flight) left two loops pulling opposite ways: 120 "pull-backs" in 10 s in the Mindless
    -- room (11-24 10:06:50), a hair under our own S02 safety kick. The newest move wins, an older one stops.
    S.moveId = (S.moveId or 0) + 1
    local myId = S.moveId
    local r = hrp()
    if not r then return end
    lookAt = lookAt or pos
    if mode == "Teleport" then
        local step = math.max(5, tonumber(cfg.tpStep) or 60)
        for _ = 1, 60 do
            r = hrp()
            if not r or not F.alive or S.moveId ~= myId then return end
            local d = pos - r.Position
            if d.Magnitude <= step then setCF(faceCF(pos, lookAt)) return end
            setCF(faceCF(r.Position + d.Unit * step, lookAt))
            task.wait(tonumber(cfg.tpWait) or 0.12)
        end
    elseif mode == "Tween" then
        local speed = math.max(10, tonumber(cfg.tweenSpeed) or 60)
        local t0 = os.clock()
        while F.alive and os.clock() - t0 < 30 do
            r = hrp()
            if not r or S.moveId ~= myId then return end
            local d = pos - r.Position
            local dt = RunService.Heartbeat:Wait()
            local move = speed * dt
            if d.Magnitude <= move then setCF(faceCF(pos, lookAt)) return end
            r.AssemblyLinearVelocity = Vector3.zero
            r.CFrame = faceCF(r.Position + d.Unit * move, lookAt)
        end
    else
        local h = hum()
        if not h then return end
        h:MoveTo(pos)
        local t0 = os.clock()
        while F.alive and os.clock() - t0 < 8 do
            r = hrp()
            if not r or (flat(r.Position) - flat(pos)).Magnitude < 4 then return end
            task.wait(0.1)
        end
    end
end

--------------------------------------------------------------------------------
-- route (Raided Village, from the owner's hand run 2026-11-21; rooms open when you walk in)
--------------------------------------------------------------------------------
local ROUTES = {
    ["Raided Village"] = {
        {1731,6,-720},{1699,6,-668},{1670,6,-621},{1674,6,-551},{1714,6,-504},{1735,6,-444},{1757,6,-418},
        {1712,6,-452},{1682,6,-404},{1661,18,-387},{1644,23,-375},{1611,28,-354},{1575,31,-315},{1575,38,-288},
        {1554,34,-256},{1523,50,-233},{1489,63,-208},{1465,63,-192},{1473,63,-166},{1491,63,-121},{1486,63,-85},
        {1520,63,-78},{1568,71,-63},{1610,60,-53},{1655,60,-37},{1715,60,-16},{1707,60,10},{1743,60,51},
        {1764,60,86},{1785,60,108},{1781,60,138},{1774,67,171},{1757,74,235},{1748,81,274},{1725,81,320},{1715,81,360},
    },
}
-- route does not fit these (another map than the recorded run); cfg.badRoute adds what runs find
local KNOWN_BAD = { ["Raided Village|Calamity"] = true }
-- routes the owner recorded with the Record route switch: dq/routes.json, key "Map|Difficulty"
local SAVED = {}
pcall(function()
    if isfile and isfile(DIR .. "/routes.json") then SAVED = HttpService:JSONDecode(readfile(DIR .. "/routes.json")) or {} end
end)
local function saveRoutes() pcall(function() writefile(DIR .. "/routes.json", HttpService:JSONEncode(SAVED)) end) end
-- the route for "Map|Difficulty": a recorded one first, else the built-in one for that map (unless it is known not to fit)
local function routeFor(key)
    if type(SAVED[key]) == "table" and #SAVED[key] > 1 then return SAVED[key] end
    local map = key:match("^(.-)|") or key
    if ROUTES[map] and not KNOWN_BAD[key] and not cfg.badRoute[key] then return ROUTES[map] end
    return nil
end
local function curKey() return (cfg.lastPlayed ~= "" and cfg.lastPlayed) or (cfg.map .. "|" .. cfg.difficulty) end
-- which map are we really on? The run may not be the one we last started (owner entered Sunken Fortress by hand on
-- 11-21 and the Raided Village route got marked bad). Pick the route whose waypoints are near us: the expected one first,
-- then every recorded / built-in one. Decided once per run (S.routePick).
local function nearest(rt, pos)
    local best = math.huge
    for _, p in ipairs(rt) do best = math.min(best, (Vector3.new(p[1], p[2] + 3, p[3]) - pos).Magnitude) end
    return best
end
local function pickRoute()
    if S.routePick ~= nil then return S.routePick end
    local r = hrp()
    if not r then return nil end
    local cands = { { curKey(), routeFor(curKey()) } }
    for k, v in pairs(SAVED) do cands[#cands + 1] = { k, v } end
    for k, v in pairs(ROUTES) do cands[#cands + 1] = { k .. "|built-in", v } end
    for _, c in ipairs(cands) do
        if c[2] and nearest(c[2], r.Position) < 150 then
            S.routePick, S.routeName = c[2], c[1]
            log("ROUTE " .. c[1] .. (c[1] == curKey() and "" or " (not the one we started: " .. curKey() .. ")"))
            return c[2]
        end
    end
    S.routePick, S.routeName = false, nil
    -- only blame the expected route when we started this run ourselves just now (Calamity = other map)
    if routeFor(curKey()) and os.time() - (tonumber(cfg.lastPlayedAt) or 0) < 180 then
        cfg.badRoute[curKey()] = true saveCfg()
        log("ROUTE none fits this map - marked " .. curKey() .. " (we started it), fight only")
    else
        log("ROUTE none fits this map (unknown dungeon) - fight only")
    end
    return false
end
local function route()
    local r = pickRoute()
    if not r then return nil end
    local out = {}
    for i, p in ipairs(r) do out[i] = Vector3.new(p[1], p[2] + 3, p[3]) end
    return out
end

-- Record route: the owner plays one run by hand; every ~18 studs of the walk is kept, saved when the run ends
local rec = { on = false, pts = nil, key = nil }
local function recPoint()
    local r = hrp()
    if not r or not rec.pts then return end
    local p = r.Position
    local last = rec.pts[#rec.pts]
    if not last or (Vector3.new(last[1], last[2], last[3]) - p).Magnitude > 18 then
        rec.pts[#rec.pts + 1] = { math.floor(p.X + 0.5), math.floor(p.Y - 3 + 0.5), math.floor(p.Z + 0.5) }
    end
end
local function recSave(why)
    if not rec.pts or #rec.pts < 3 then log("RECORD " .. tostring(rec.key) .. " too short, not saved (" .. why .. ")") return end
    SAVED[rec.key] = rec.pts
    saveRoutes()
    cfg.badRoute[rec.key] = nil
    cfg.recordRoute = false saveCfg()
    log("RECORD saved " .. rec.key .. ": " .. #rec.pts .. " points (" .. why .. ")")
    rec.pts = nil
end
-- next waypoint: one past the furthest waypoint we have reached (never walks backwards)
local reached = 0
-- (RV Normal + Chaos are seen to fit; a wrong mark from the 11-21 Sunken Fortress run is undone here)
cfg.badRoute["Raided Village|Chaos"] = nil cfg.badRoute["Raided Village|Normal"] = nil cfg.badRoute["Raided Village|Expert"] = nil

local function nextWaypoint()
    local rt = route()
    local r = hrp()
    if not rt or not r then return nil end
    for i, p in ipairs(rt) do
        if i > reached and (flat(p) - flat(r.Position)).Magnitude < 14 then reached = i end
    end
    S.wp = reached
    return rt[reached + 1], reached + 1, #rt
end

--------------------------------------------------------------------------------
-- fight loop pieces
--------------------------------------------------------------------------------
local swingOn = false
local function swingLoop()
    while F.alive do
        if swingOn then
            attack()
            task.wait(1 / math.clamp(tonumber(cfg.swingRate) or 10, 1, 60))
        else
            task.wait(0.1)
        end
    end
end
go("swing", swingLoop)

-- hover: hold the character over the mob every frame (refreshed by engage; lapses after 0.5 s)
F.conns[#F.conns + 1] = RunService.Heartbeat:Connect(function()
    if not hold then return end
    if os.clock() - hold.t > 0.5 then hold = nil return end
    local r = hrp()
    if not r then return end
    -- (a gap here is our own hold fighting our own moves, not the server: never counted - it set off a false
    -- safety kick [S02] "686 pull-backs in 60 s" on 11-21 16:13)
    if S.movingUntil and os.clock() < S.movingUntil then return end
    -- 11-21 party kick #101: snapping back to the hold spot after the server / a knockback / a respawn moved us far
    -- looks like a teleport hack to the game. Far from the hold = drop it; engage walks us back in steps.
    if (r.Position - hold.cf.Position).Magnitude > 12 then hold = nil return end
    lastSet = nil -- this move is ours (review 11-21: a dodge followed by a hold on another spot looked like a pull-back)
    r.AssemblyLinearVelocity = Vector3.zero
    r.CFrame = hold.cf
end)
-- dq_161 owner 11-24 "it still drops, make it float all the time": the hold above ends after 0.5 s, then gravity
-- pulled us down to the floor between moves. Keep the height of our last own move (no sideways snap, small lift only).
F.conns[#F.conns + 1] = RunService.Heartbeat:Connect(function()
    if not cfg.farm or IN_LOBBY or not S.floatY or hold then return end
    if S.movingUntil and os.clock() < S.movingUntil then return end
    local r = hrp() local h = hum()
    if not r or not h or h.Health <= 0 then return end
    local dy = S.floatY - r.Position.Y
    if dy > 12 or dy < -12 then S.floatY = nil return end -- game moved / respawned us: not ours to undo
    local v = r.AssemblyLinearVelocity
    if v.Y < 0 then r.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z) end
    if dy > 0.3 then r.CFrame = r.CFrame + Vector3.new(0, dy, 0) end
end)
-- dq_184 dev PC only: flight recorder. Twice a run or so something flies us ~500 studs a second away from a pack we
-- just reached and the mobs' chase boxes kill us on the way (11-24 12:27, 13:43). The last 3 s of our position (own
-- move or not, nearest Spawn / Teleport part) go to dq/flight.txt on every death and whenever we travel 150+ studs in
-- 0.6 s without a move of our own.
if DEV then
    local buf = {}
    S.dumpFlight = function(tag)
        local L = { os.date("%H:%M:%S") .. " " .. tag }
        local parts = {}
        for _, nm in ipairs({ "Spawns", "Teleports" }) do
            local f = workspace:FindFirstChild(nm)
            for _, d in ipairs(f and f:GetDescendants() or {}) do if d:IsA("BasePart") then parts[#parts + 1] = d end end
        end
        local function near(q)
            local best, bd
            for _, d in ipairs(parts) do local x = (d.Position - q).Magnitude if not bd or x < bd then best, bd = d, x end end
            return best and string.format("%s %.0f", best.Name, bd) or "-"
        end
        local t1 = buf[#buf] and buf[#buf].t or os.clock()
        for i = 1, #buf, 3 do
            local b, prev = buf[i], buf[math.max(1, i - 3)]
            L[#L + 1] = string.format("  %.2f %s step %.0f %s | near %s", b.t - t1, v3s(b.p), (b.p - prev.p).Magnitude, b.own and "OWN" or "ext", near(b.p))
        end
        pcall(appendfile, DIR .. "/flight.txt", table.concat(L, "\n") .. "\n\n")
        log("FLIGHT recorded (" .. tag .. ") -> dq/flight.txt")
    end
    F.conns[#F.conns + 1] = RunService.Heartbeat:Connect(function()
        if IN_LOBBY then return end
        local r = hrp()
        if not r then return end
        local now = os.clock()
        buf[#buf + 1] = { t = now, p = r.Position, own = (S.ownSetT and now - S.ownSetT < 0.2) and true or false }
        if #buf > 200 then table.remove(buf, 1) end
        if #buf > 40 and now - (S.flightDumpT or 0) > 6 then
            local a = buf[#buf - 36]
            if (r.Position - a.p).Magnitude > 150 then
                local own = 0
                for i = #buf - 36, #buf do if buf[i].own then own = own + 1 end end
                if own == 0 then
                    S.flightDumpT = now
                    pcall(S.dumpFlight, "moved " .. math.floor((r.Position - a.p).Magnitude) .. " studs in 0.6 s with no move of ours")
                end
            end
        end
    end)
end

--------------------------------------------------------------------------------
-- dodge: mobs build a red Indicator + a Hitbox part before a skill lands (Aftershock, rapidfire, TargetBeam,
-- plain Hitbox). Stand outside every live one; if no nearby spot is clear (map-wide AoE) go to a safe spot.
--------------------------------------------------------------------------------
local dangers = {} -- part -> born time
local function isDanger(p)
    if not p:IsA("BasePart") then return false end
    -- (DeadlyWhirl / DeadlyVortex are OUR spells - they appear on us when Q/E is used; not dangers. 11-21 14:03)
    -- 11-23 lvl 260 pre-hit recordings: Lifeless marks its hit 1.8 s ahead with a plain workspace "Part" column (50x104x56 +
    -- a 4-thick plate); a pizza attack uses "hitbox1".."hitbox8". Both were never dodged (8 + several hits a run).
    local nm = p.Name
    local column = nm == "Part" and p.Parent == workspace and not p.CanCollide and p.Size.Y >= 90 and p.Size.Y <= 130 and math.max(p.Size.X, p.Size.Z) <= 400 and math.min(p.Size.X, p.Size.Z) <= 60 -- dq_164: lvl 275 columns are up to 183 long (130 limit missed them: 9 "in zone: none" hits in one run)
    if nm ~= "Hitbox" and nm ~= "Indicator" and not column and not nm:match("^[Hh]itbox%d+$") then return false end
    -- 11-23 lvl 250 First Sanctuary: boss Zuriel puts a Safezone model (Hitbox 50 ball + Indicator 386 disc) on the floor,
    -- 5 s later a nuke one-shots everyone outside it (every death on Zuriel). Its parts are the SAFE spot, never a danger.
    if p.Parent and p.Parent.Name:lower():find("safezone") then return false end
    -- dq_171 lvl 270 Formless PlayerRing: a marker glued to the player (it catches up within 0.05 s of every move) that
    -- never does damage itself - 24 rings recorded at 20 Hz (dq/ring.txt 11-24), we stood in the middle of each and every
    -- hit in that time came from another zone (pizza slice, BigSword). Treated as a 20-stud zone it made us hop twice a
    -- second for the whole fight (60-74 dodges per 30 s): no swings, drifting off the boss, "no clear spot" stalls.
    if p.Parent and p.Parent.Name == "PlayerRing" then return false end
    -- players' own skills carry OwnerUserId (our Q made 30x30 Hitboxes: 1206 dodges from our own skills on 11-21)
    if p:GetAttribute("OwnerUserId") ~= nil or (p.Parent and p.Parent:GetAttribute("OwnerUserId") ~= nil) then return false end
    local c = char()
    if c and p:IsDescendantOf(c) then return false end
    local en = workspace:FindFirstChild("Enemies")
    if p.Parent and p.Parent:IsA("Model") and p.Parent:FindFirstChildOfClass("Humanoid") then return false end -- a mob's own body hitbox
    -- arena-sized parts are not attacks (11-21 Sunken Fortress: 2 such zones sent us to the spawn every second)
    -- (lvl 260 Formless ArenaLine 853x73x18: a real line attack, shown ~1.5 s before 500M; dq_154 dodges it again, now with
    -- the least-bad spot fallback - dq_150 froze with "no clear spot" and lost 4 runs)
    -- dq_156: only parts big in two directions are arena parts; long thin lines (ArenaLine 853x73x18, EmberwingLingerLine
    -- 858x34x36 - 4 hits in a row on 11-23) are attacks
    local sz = { p.Size.X, p.Size.Y, p.Size.Z }
    table.sort(sz)
    if sz[3] > 700 and sz[2] > 300 then
        if not S.hugeSeen then S.hugeSeen = {} end
        local id = p:GetFullName()
        if not S.hugeSeen[id] then S.hugeSeen[id] = true log(string.format("ZONE ignored (too big) %s %.0fx%.0fx%.0f", id, p.Size.X, p.Size.Y, p.Size.Z)) end
        return false
    end
    return true
end
-- timing study (owner 11-21: "is there a delay?"): when a Hitbox appears, how long after the red Indicator at the
-- same spot? Logged per attack name as TIMING lines; the hit log adds each zone's age in ms.
local recentInd = {} -- {part, t, pos, name}
local function attackName(p) return (p.Parent and p.Parent ~= workspace) and p.Parent.Name or "plain" end
F.conns[#F.conns + 1] = workspace.DescendantAdded:Connect(function(p)
    if not isDanger(p) then
        -- a plain Part may get its size a moment after it is parented
        if p.Name == "Part" and p.Parent == workspace then
            task.delay(0.1, function() pcall(function() if p.Parent and isDanger(p) then dangers[p] = os.clock() end end) end)
        end
        return
    end
    local now = os.clock()
    dangers[p] = now
    pcall(function()
        if p.Name == "Indicator" then
            recentInd[#recentInd + 1] = { t = now, pos = p.Position, name = attackName(p) }
            if #recentInd > 40 then table.remove(recentInd, 1) end
        elseif p.Name == "Hitbox" then
            local best, bd = nil, 30
            for _, ind in ipairs(recentInd) do
                local d = (flat(ind.pos) - flat(p.Position)).Magnitude
                if now - ind.t < 5 and d < bd then best, bd = ind, d end
            end
            local r = hrp()
            local me = r and string.format(" | me %.0f studs away", (flat(p.Position) - flat(r.Position)).Magnitude) or ""
            if best then
                if cfg.timingLog then log(string.format("TIMING %s: red ring -> damage box %.0f ms (box %.0fx%.0fx%.0f)%s", attackName(p), (now - best.t) * 1000, p.Size.X, p.Size.Y, p.Size.Z, me)) end
            else
                if cfg.timingLog then log(string.format("TIMING %s: damage box with NO red ring before it (box %.0fx%.0fx%.0f)%s", attackName(p), p.Size.X, p.Size.Y, p.Size.Z, me)) end
            end
        end
    end)
end)
for _, p in ipairs(workspace:GetChildren()) do if isDanger(p) then dangers[p] = os.clock() end end
-- a zone counts as long as it exists (held beams last many seconds: with a 4 s limit we teleported back into a
-- channelled beam again and again, 11-21), capped at 15 s. Built once per 0.05 s - dangerAt runs many times a frame.
local liveCache, liveAt = {}, 0
local function liveDangers()
    local now = os.clock()
    if now - liveAt < 0.05 then return liveCache end
    local out = {}
    for p, t in pairs(dangers) do
        if not p.Parent or now - t > 15 then dangers[p] = nil
        -- dq_172 Formless BigSword: it strikes once, 2.1-2.2 s after it shows (all 4 recorded hits). Its red lane (Indicator)
        -- stays for many seconds after that and, with the wide box the sword needs, left "no clear spot" for 9 s in a row
        -- (we sat still there and the lingering fire line hit twice). The lane alone is not a zone; the sword box ends at 2.8 s.
        elseif p.Parent.Name == "BigSword" and (p.Name ~= "Hitbox" or now - t > 2.8) then
        else out[#out + 1] = p end
    end
    liveCache, liveAt = out, now
    return out
end
-- 11-23 lvl 260 Formless EmberwingPizza: 16 slices, each a 22.5 degree wedge ~400 long from the arena centre. Their
-- boxes (152x398 etc) overlap and covered the whole arena: "no clear spot", we stood still and the PlayerRing + BigSword
-- killed us. A slice is tested as a wedge: centre = middle of all slice boxes, inside = within the slice's angle + reach.
local inSlice
do
local sliceCentre = setmetatable({}, { __mode = "k" })
local function pizzaCentre(folder)
    local c = sliceCentre[folder]
    if c and os.clock() - c.t < 2 then return c.v end
    local sum, n = Vector3.zero, 0
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA("BasePart") and d.Name == "Hitbox" then sum, n = sum + d.Position, n + 1 end
    end
    local v = n >= 6 and sum / n or nil
    sliceCentre[folder] = { v = v, t = os.clock() }
    return v
end
S.pizzaCentreOf = pizzaCentre
inSlice = function(pos, p, margin)
    local folder = p.Parent and p.Parent.Parent
    if not folder or folder.Name ~= "Slices" then return nil end
    -- dq_169: all 16 Hitboxes exist for the whole attack, but a slice only goes off while its own plate (the MeshPart
    -- the Hitbox sits in) is lit: even and odd slices take turns, each set shows ~4 s before it hits (dq/pizza.txt
    -- 11-24). Counting all 16 left no clear angle: we fled 400 studs from Formless for the 25-30 s of every pizza -
    -- the time the lvl 270 run was short of. The boss stays ~40 studs from the centre: wait in a dark slice near it.
    if p.Parent:IsA("BasePart") and p.Parent.Transparency >= 0.7 then return false end
    -- dq_175: the angle model below takes "slice direction = box centre - pizza centre". For the 12 slices that do not
    -- lie on an axis or a diagonal the box centre is 7-10 degrees off the wedge's middle, so we stood on slice edges and
    -- three second-wave detonations (9.2 s) hit us there. The Hitbox is a precise mesh: ask it directly.
    if cfg.exactZones ~= false and S.exactIn and p.CanQuery then
        local ok, res = pcall(S.exactIn, pos, p, math.min(margin, 6), false)
        if ok then return res end
    end
    local c = pizzaCentre(folder)
    if not c then return nil end
    local v = Vector3.new(pos.X - c.X, 0, pos.Z - c.Z)
    local b = Vector3.new(p.Position.X - c.X, 0, p.Position.Z - c.Z)
    local d, bd = v.Magnitude, b.Magnitude
    if bd < 20 then return nil end
    if d < 15 + margin then return true end
    if d > bd * 2.1 + margin then return false end
    local cosA = v:Dot(b) / (d * bd)
    local ang = math.deg(math.acos(math.clamp(cosA, -1, 1)))
    -- dq_171: pad 4 deg + margin -> 2 deg + 4 studs (with the old pad no dark slice had a clear strip within 70 studs of
    -- the centre, where Formless stands)
    return ang <= 11.25 + 4 + math.deg(math.atan(margin / d)) -- dq_174: back to 4 deg + margin (dq_171's small pad: slice edge hit near the centre)
end
end
-- dq_168: the real footprint of mesh / union zones. Their boxes are far bigger than what hits: the Mindless StaticRing
-- (90x103x90) is a ring 9 thick with an empty middle, its Nuke (421x553x373) a disc ~240 wide, SlamLines a set of lines,
-- shock waves thin rings (dq/shapes.txt, measured 11-24). With boxes we fled or hovered over them all the time and lost
-- the swings (Mindless: 0.16 swings a second instead of 1.1). A ray straight down through the one part (Include filter)
-- tells whether the part really is over / under a point and how high it reaches there.
do
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    local cache, cacheT = setmetatable({}, { __mode = "k" }), os.clock()
    S.exactRays = 0
    S.exactIn = function(pos, p, m, tall)
        local now = os.clock()
        if now - cacheT > 0.3 then cache, cacheT = setmetatable({}, { __mode = "k" }), now end
        local pp = p.Position
        local e = cache[p]
        if not e or (e.pos - pp).Magnitude > 0.5 then e = { pos = pp, map = {} } cache[p] = e end
        local k = (math.floor(pos.X / 2 + 0.5) * 100003 + math.floor(pos.Z / 2 + 0.5)) * 4 + (m <= 0 and 0 or (m >= 15 and 2 or 1))
        local top = e.map[k]
        if top == nil then
            local cf, sz = p.CFrame, p.Size
            local ry = math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
            local from, len = pp.Y + ry + 2, 2 * ry + 4
            params.FilterDescendantsInstances = { p }
            -- dq_182: devices without dq/dev.flag (friends' phones): at most 300 rays per 0.1 s; over that the zone counts
            -- as "inside" like the old box test (the lvl 270 pizza asks for up to 14000 rays a second)
            if not DEV then
                if now - (S.rayWinT or 0) > 0.1 then S.rayWinT, S.rayWinN = now, 0 end
                if (S.rayWinN or 0) > 300 then return true end
            end
            local function ray(x, z)
                S.rayWinN = (S.rayWinN or 0) + 1
                S.exactRays = S.exactRays + 1
                local res = workspace:Raycast(Vector3.new(x, from, z), Vector3.new(0, -len, 0), params)
                return res and res.Position.Y or nil
            end
            local x, z = pos.X, pos.Z
            top = ray(x, z)
            if not top and m > 0 then
                top = ray(x + m, z) or ray(x - m, z) or ray(x, z + m) or ray(x, z - m)
                if not top then
                    local d = m * 0.7
                    top = ray(x + d, z + d) or ray(x - d, z + d) or ray(x + d, z - d) or ray(x - d, z - d)
                end
            end
            e.map[k] = top or false
        end
        if not top then return false end
        -- dq_177: the ray decides the footprint only; for the height take the top of the part's box. The Mindless
        -- StaticRing mesh has a low lip (ray top 6 over its centre) next to a 52-tall wall: standing over the lip the
        -- "top here" said clear and the pulse hit us (3 runs in a row, one hit each, 1.5 s after the ring showed).
        local cf, sz = p.CFrame, p.Size
        local boxTop = pp.Y + math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
        return pos.Y <= math.max(top, boxTop) + (tall and 60 or m)
    end
end
-- inside the part's box (+ margin); flat red discs (Indicator) count as a tall column
local function inZone(pos, p, margin)
    do local w = inSlice(pos, p, margin or 6) if w ~= nil then return w end end
    local lp = p.CFrame:PointToObjectSpace(pos)
    local m = margin or 6
    local hx, hy, hz = p.Size.X / 2 + m, p.Size.Y / 2 + m, p.Size.Z / 2 + m
    -- a flat ring / disc is a tall column of damage. Its thin axis is not always Y: round rings are cylinders lying
    -- on their side (thin axis X, e.g. the 1x214x214 ring that one-shot us on 11-21 while we hovered over it).
    local sx, sy, sz = p.Size.X, p.Size.Y, p.Size.Z
    local thin = math.min(sx, sy, sz)
    -- 11-22 lvl 220 Mue no Ikari FloorLava: the 1x444x528 Indicator came with its real Hitbox (50 thick, top 25 over
    -- the floor) already there. As a 60 column the red plane blocked every spot up to 60 over the floor, no dodge spot
    -- was clear and we sat in the lava. When the damage box is already there and thick, the red plane is not a column.
    local sib = (thin <= 2.5 and p.Name == "Indicator" and p.Parent and p.Parent ~= workspace) and p.Parent:FindFirstChild("Hitbox")
    if sib and sib:IsA("BasePart") and math.min(sib.Size.X, sib.Size.Y, sib.Size.Z) >= 20 then thin = 99 end
    if thin <= 2.5 then -- flat rings only; a 5-thick slash box is not a column (it blocked every spot, 11-21 13:43)
        if thin == sx then hx = math.max(hx, 60) elseif thin == sy then hy = math.max(hy, 60) else hz = math.max(hz, 60) end
    end
    -- dq_166 lvl 270 Formless BigSword (Hitbox 47x58x559): it hit us twice 21 studs over the top of that part, 2.2 s
    -- after it showed (ZONEMISS "out x-11 y21 z-100"). The blade comes down from above: its whole height counts.
    -- (dq_171: and 9 studs outside the lane's width, ZONEMISS "out x9 y21" - 15 more on each side)
    -- dq_179 Formless BigSword: what hits is a ball of ~54 studs around the model's Primary (where the sword comes down),
    -- 2.1-2.2 s after it shows - not the lane. Recorded 11-24 (dq/form.txt + dq/imperium.txt): every hit was within 54
    -- studs (3D) of the Primary; hovering 53 right over it (dq_176) = on the edge, hit 3 times in 10; 17 swords at 54+: 0.
    -- Outside 60 (+ margin) = clear; the lane box itself still counts for the floor.
    -- dq_180: not a ball either (hit again 67 studs over the Primary). 42 swords recorded with dq_176-179: standing
    -- straight over the Primary (within 6 studs sideways, 53-74 up) = hit 4 times in 15; anywhere else around the boss
    -- (8-58 studs sideways from it) = 0 in 27. The sword comes down on its Primary, a point ~20 studs behind the boss -
    -- right where our favourite boss spot is. So: a column of 12 studs (+ margin) around the Primary, at any height.
    -- dq_183: 58 swords recorded now (dq/form.txt): all 6 hits were with us exactly on the lane's middle line ("lane x 0":
    -- right behind the boss over the Primary, or right in front of it), at any height (21-74 over the lane box);
    -- 8 or more studs to the side of that line: 0 hits in 22. The sword cuts along the vertical plane through the lane's
    -- axis. So: 6 studs (+ margin) to each side of that plane, the whole lane long, at any height.
    -- dq_185: 190 swords since the plane rule (dq/form.txt, 13:42-15:36): beside the line (8-19 studs off it) at the
    -- usual hover = 5 hits in 78; the same spots but 40+ studs over the lane box = 0 in 49; 20+ studs off the line = 0 in 22.
    -- So next to the lane (within 20 studs of its middle line) only a spot 40+ over the lane box is clear.
    if p.Parent and p.Parent.Name == "BigSword" and math.abs(lp.Z) <= p.Size.Z / 2 + m then
        if math.abs(lp.X) <= 6 + m then return true end
        if math.abs(lp.X) <= 20 + m and lp.Y - p.Size.Y / 2 < 40 + m then return true end
    end
    -- dq_172 Formless EmberwingLingerLine (Hitbox 858x34x36, Indicator 858x12x36): two 37 % hits 24 studs over the top of
    -- the Indicator, 11 s after it showed (ZONEMISS 11-24 11:05) - the line keeps burning and reaches higher than its parts
    if p.Parent and p.Parent.Name == "EmberwingLingerLine" then hy = math.max(hy, 50) end
    if not (math.abs(lp.X) <= hx and math.abs(lp.Z) <= hz and math.abs(lp.Y) <= hy) then return false end
    -- dq_168: inside the box - for a mesh / union ask its real shape ("set exactZones false" = boxes as before)
    if cfg.exactZones ~= false and p.CanQuery and (p:IsA("MeshPart") or p:IsA("UnionOperation")) then
        local ok, res = pcall(S.exactIn, pos, p, m, thin <= 2.5)
        if ok then return res end
    end
    return true
end
-- 11-23 lvl 260: Lifeless / Illusive Swordsman hit us with "in zone: none" - travelling boxes (Bladewave, slashes)
-- reached us after the check. Each box's speed is measured; a moving one is also tested 0.3 and 0.6 s ahead.
local zoneVel = {}
go("zonevel", function()
    local zoneLast = {}
    while F.alive do
        task.wait(0.1)
        local now = os.clock()
        for p in pairs(zoneLast) do if not dangers[p] then zoneLast[p], zoneVel[p] = nil, nil end end
        for p in pairs(dangers) do
            if p.Parent then
                local l = zoneLast[p]
                local pos = p.Position
                if l and now > l.t then
                    local v = (pos - l.pos) / (now - l.t)
                    zoneVel[p] = (v.Magnitude > 8 and v.Magnitude < 400) and v or nil
                end
                zoneLast[p] = { pos = pos, t = now }
            end
        end
    end
end)
local function dangerAt(pos)
    for _, p in ipairs(liveDangers()) do
        -- lvl 260 PlayerRing follows us and hit at 2 s old from 12 studs off: keep 20 studs from it
        -- dq_175: Mindless StaticRing hit us 7 studs outside its box (52 from its centre, ring mesh ends at 45): 16 around it
        -- dq_181: the Illusive chase boxes (plain workspace Hitbox 50x30x30) hit 8 studs outside their part (74 % of our
        -- hp, 11-24 13:03, ZONEMISS "out x-3 y8 z-13 age 1.2s"): 12 around them instead of 6
        local mg = nil
        -- dq_188: 12 -> 20. No Hit attempt 3 (11-24 16:01) died 4 s after reaching the room-7 pack: three small dodges
        -- (28 up, 32 and 47 sideways) in 0.8 s, the last one 0.09 s before the box struck - too little, too late for the
        -- server. 20 studs of margin makes the first dodge a real one (45+ studs from the box centre).
        if p.Parent and p.Parent.Name == "StaticRing" then mg = 16 elseif p.Parent == workspace and p.Name == "Hitbox" then mg = 20 end
        if inZone(pos, p, mg) then return p end
        local v = zoneVel[p]
        if v and (inZone(pos - v * 0.3, p) or inZone(pos - v * 0.6, p)) then return p end
    end
    return nil
end

-- 11-21: dodging to a spot over a cliff dropped us off the map. A spot needs solid floor within 80 studs below.
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
local function hasFloor(p, depth)
    local ex = { workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Waste") }
    for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then ex[#ex + 1] = pl.Character end end
    floorParams.FilterDescendantsInstances = ex
    local dep = depth or 80 -- dq_179: liftOver asks for 115 (over the BigSword ball we are ~90 over the arena floor)
    local hit = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -dep, 0), floorParams)
    for _ = 1, 10 do
        if not hit then return false end
        if hit.Instance.CanCollide or hit.Instance:IsA("Terrain") then return true end
        -- see-through effect parts (zones, beams): look below them
        hit = workspace:Raycast(hit.Position - Vector3.new(0, 0.1, 0), Vector3.new(0, -dep, 0), floorParams)
    end
    return false
end
-- dq_179: can we still fight the mob from spot q? Q / E reach 62 studs from its root; a tall boss (Formless: Hitbox top
-- 58 over its root) is also in reach from just over its Hitbox, even when that is further than 62 from the root.
S.reachOK = function(q, root)
    if (q - root.Position).Magnitude < 62 then return true end
    local hb = root.Parent and root.Parent:FindFirstChild("Hitbox")
    if hb and hb:IsA("BasePart") then
        local top = hb.Position.Y + hb.Size.Y / 2
        return q.Y - top < 16 and (Vector3.new(q.X, 0, q.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude < 35
    end
    return false
end
-- 11-21: two bots in one dungeon = one of them kicked #101 within ~30 s, every time (one bot + a hand player: never).
-- Both bots CFrame-held onto the same spot over the same mob: the characters push each other apart (fling).
-- Never stand within 8 studs of another player.
-- dq_169 lvl 270 room 9: a trigger near the exit carries the player to the last boss. The mobs stand next to it, so
-- we were carried away 4 times in one fight and flew back each time (40 s lost and a death on the way, 11-24 10:30).
-- Where a carry picked us up we do not stand again: 30 studs around it for 90 s; after a second carry from the same
-- place it stays for good and is kept per map in cfg.carrySpots, so later runs never step in.
S.noStand = {}
S.noteCarry = function(pos)
    for _, z in ipairs(S.noStand) do
        if (flat(z.pos) - flat(pos)).Magnitude < 40 then
            z.n = z.n + 1
            z.untilT = math.huge
            if z.n == 2 then
                local ds = workspace:FindFirstChild("DungeonSettings")
                local sn = ds and ds:FindFirstChild("SessionName")
                local map = sn and tostring(sn.Value) or tostring(cfg.map)
                cfg.carrySpots = type(cfg.carrySpots) == "table" and cfg.carrySpots or {}
                local list = type(cfg.carrySpots[map]) == "table" and cfg.carrySpots[map] or {}
                if #list < 6 then list[#list + 1] = string.format("%.0f,%.0f,%.0f", z.pos.X, z.pos.Y, z.pos.Z) end
                cfg.carrySpots[map] = list
                saveCfg()
                log("CARRY TRIGGER at " .. v3s(z.pos) .. " picked us up twice - kept for this map, never standing within 30 studs of it")
            end
            return
        end
    end
    S.noStand[#S.noStand + 1] = { pos = pos, r = 30, n = 1, untilT = os.clock() + 90 }
    log("CARRY TRIGGER near " .. v3s(pos) .. " - not standing within 30 studs of it for 90 s")
end
-- a spot inside a keep-out zone -> the same spot pushed out to the zone's edge (nil when it is not inside one)
S.edgeSpot = function(p)
    local nowT = os.clock()
    for _, z in ipairs(S.noStand) do
        if nowT < z.untilT and (flat(z.pos) - flat(p)).Magnitude < z.r and math.abs(z.pos.Y - p.Y) < 60 then
            local d = flat(p) - flat(z.pos)
            local me = hrp()
            if d.Magnitude < 1 and me then d = flat(me.Position) - flat(z.pos) end
            if d.Magnitude < 1 then d = Vector3.new(1, 0, 0) end
            return Vector3.new(z.pos.X + d.Unit.X * (z.r + 3), p.Y, z.pos.Z + d.Unit.Z * (z.r + 3))
        end
    end
    return nil
end
-- dq_192 Pan Ku (Boss Rush 11-24, dq/yinyang.txt): the floor is a turning yin-yang (Workspace.YinYangArena: YinHitbox /
-- YangHitbox, 248 wide meshes) and the player carries an "Alignment" attribute (Yin / Yang). Over the half of our own
-- alignment nothing happens (8-10 s stretches, 0 ticks); over the other half the game takes 25% of max hp every
-- second (13 ticks seen, every one within a second of being over the wrong half) - 4 ticks = dead, 9 deaths in 3 runs.
-- The halves turn ~12-17 degrees a second, so the spot has to follow. A ray straight down at one half's hitbox mesh
-- tells which half a point is over.
do
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    local cache, cacheT, cacheH = {}, 0, nil
    -- our half's hitbox while the arena is up (nil = no arena / no alignment)
    S.yy = function()
        local ya = workspace:FindFirstChild("YinYangArena")
        if not ya then return nil end
        local al = LP:GetAttribute("Alignment")
        if al ~= "Yin" and al ~= "Yang" then return nil end
        local h = ya:FindFirstChild(al .. "Hitbox")
        return (h and h:IsA("BasePart")) and h or nil
    end
    S.yyOver = function(h, x, z)
        local now = os.clock()
        if now - cacheT > 0.1 or cacheH ~= h then cache, cacheT, cacheH = {}, now, h end
        local k = math.floor(x / 2 + 0.5) * 100003 + math.floor(z / 2 + 0.5)
        local v = cache[k]
        if v == nil then
            params.FilterDescendantsInstances = { h }
            v = workspace:Raycast(Vector3.new(x, h.Position.Y + 200, z), Vector3.new(0, -400, 0), params) ~= nil
            cache[k] = v
            S.exactRays = (S.exactRays or 0) + 1
        end
        return v
    end
    -- over our half with m studs to spare on every side
    S.yyOk = function(h, p, m)
        if not S.yyOver(h, p.X, p.Z) then return false end
        if m and m > 0 then
            return S.yyOver(h, p.X + m, p.Z) and S.yyOver(h, p.X - m, p.Z) and S.yyOver(h, p.X, p.Z + m) and S.yyOver(h, p.X, p.Z - m)
        end
        return true
    end
end
local function crowded(p)
    do -- dq_192: yin-yang floor - a spot over the other half is no spot
        local h = S.yy()
        if h and not S.yyOk(h, p, 8) then return true end
    end
    do -- dq_190: inside the reach of a keep-off boss
        local k = S.keepOff
        if k and k.r.Parent and (flat(k.r.Position) - flat(p)).Magnitude < k.d - 4 then return true end
    end
    if not S.noStandLoaded then
        local ds = workspace:FindFirstChild("DungeonSettings")
        local sn = ds and ds:FindFirstChild("SessionName")
        if sn and tostring(sn.Value) ~= "" then
            S.noStandLoaded = true
            local list = type(cfg.carrySpots) == "table" and cfg.carrySpots[tostring(sn.Value)]
            for _, str in ipairs(type(list) == "table" and list or {}) do
                local x, y, z = tostring(str):match("^(-?[%d.]+),(-?[%d.]+),(-?[%d.]+)$")
                if x then S.noStand[#S.noStand + 1] = { pos = Vector3.new(tonumber(x), tonumber(y), tonumber(z)), r = 30, n = 2, untilT = math.huge } end
            end
            -- dq_182: Subliminal Dreamscape room 9 - the trigger that carries the player to the last boss. Picked up at
            -- -3437,-124,4544 and -3454,-124,4563 (11-24); a second carry with mobs left behind killed us twice.
            if tostring(sn.Value) == "Subliminal Dreamscape" then
                S.noStand[#S.noStand + 1] = { pos = Vector3.new(-3446, -130, 4553), r = 45, n = 2, untilT = math.huge }
            end
            if #S.noStand > 0 then log("CARRY TRIGGERS known on this map: " .. #S.noStand) end
        end
    end
    do
        local nowT = os.clock()
        for _, z in ipairs(S.noStand) do
            if nowT < z.untilT and (flat(z.pos) - flat(p)).Magnitude < z.r and math.abs(z.pos.Y - p.Y) < 60 then return true end
        end
    end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= LP and pl.Character then
            local o = pl.Character:FindFirstChild("HumanoidRootPart")
            if o and (o.Position - p).Magnitude < 8 then return true end
        end
    end
    return false
end
-- dq_187: solo the floor may be up to 130 under the spot (was 80). Lifted beside the BigSword lane we are ~95 over the
-- arena floor: every sideways spot failed the 80-stud floor check = "no clear spot with floor", we could not leave a lit
-- pizza slice and both first No Hit attempts died there (11-24 15:48, 15:56).
local function okSpot(p) return not dangerAt(p) and hasFloor(p, (#Players:GetPlayers() <= 1) and 130 or 80) and not crowded(p) end
-- dq_189 Formless pizza: a clear place = the middle of a dark slice. Walk a circle of radius R round the pizza centre
-- in 4 degree steps from angle a0 and take the middle of the nearest arc of 3+ clear samples (okSpot = no lit slice,
-- no other zone, floor below).
S.pizzaSpot = function(c, a0, R, y)
    local clear = {}
    for k = 0, 89 do
        local a = a0 + k * math.rad(4)
        local q = Vector3.new(c.X + math.cos(a) * R, y, c.Z + math.sin(a) * R)
        clear[k] = okSpot(q) and q or false
    end
    local best, bd
    local k = 0
    while k <= 89 do
        if clear[k] then
            local j = k
            while j + 1 <= 89 and clear[j + 1] do j = j + 1 end
            if j - k + 1 >= 3 then
                local mid = math.floor((k + j) / 2)
                local d = math.min(mid, 90 - mid)
                if not bd or d < bd then best, bd = clear[mid], d end
            end
            k = j + 1
        else
            k = k + 1
        end
    end
    return best
end
-- 11-22 lvl 220 Master Ryuken: KickLanding circles are up to 323 wide (no way out sideways within 45 studs) but only
-- reach ~53 over their centre. Go straight up over the zone's top instead: at most 45 studs up, floor still below.
local function zoneTop(p)
    local cf, s = p.CFrame, p.Size
    local top = p.Position.Y + math.abs(cf.RightVector.Y) * s.X / 2 + math.abs(cf.UpVector.Y) * s.Y / 2 + math.abs(cf.LookVector.Y) * s.Z / 2
    -- dq_176 Formless BigSword: the Sword mesh (35x98x4) that sweeps the lane stands 32 studs over the lane box. Every
    -- hit (6 recorded) came 21 studs over that box, at any side distance up to 39 outside the lane: sideways is no way
    -- out, over the blade is - and that is only ~20 studs above where we hover.
    -- dq_185: beside the BigSword's middle line a spot 40+ over the lane box is clear (see inZone); on the line nothing is
    if p.Parent and p.Parent.Name == "BigSword" then top = top + 40 end
    return top
end
local function liftOver(pos, test)
    local q = pos
    -- dq_182: the high lifts (70 up, floor up to 115 below) are for solo runs; with other players in the dungeon the old
    -- limits stay (45 up, floor within 80) - party runs were kicked #101 after high hovering, solo runs never
    local solo = #Players:GetPlayers() <= 1
    local lim, dep = solo and 70 or 45, solo and 115 or 80
    for _ = 1, 4 do
        local z = test(q)
        if not z then
            if q == pos or q.Y - pos.Y > lim or not hasFloor(q, dep) or crowded(q) then return nil end
            return q
        end
        q = Vector3.new(q.X, math.max(q.Y, zoneTop(z)) + 7, q.Z)
        if q.Y - pos.Y > lim then return nil end -- dq_164: 45 -> 70 (floor 240, attack tops 295 on lvl 275)
    end
    return nil
end
-- fall guard: remember the last spot with floor under it; if we end up far below it with nothing under us, go back
do
    local lastSafe
    go("fallguard", function()
        while F.alive do
            task.wait(0.3)
            if cfg.farm and not IN_LOBBY and not S.runCleared then
                local r = hrp()
                local h = hum()
                if r and h and h.Health > 0 then
                    -- a real fall only: dropping fast (our own teleports zero the speed) with no floor under us
                    -- (dq_40 pulled us up again and again when we teleported down to a mob on a lower floor)
                    local falling = r.AssemblyLinearVelocity.Y < -60
                    if not falling and hasFloor(r.Position) then
                        lastSafe = r.Position
                    elseif falling and lastSafe and r.Position.Y < lastSafe.Y - 30 and not hasFloor(r.Position) then
                        log(string.format("FALL at %s - back to %s", v3s(r.Position), v3s(lastSafe)))
                        hold = nil
                        setCF(CFrame.new(lastSafe + Vector3.new(0, 3, 0)))
                    end
                end
            end
        end
    end)
end
-- owner 11-21: step to the side of the skill and keep hitting, don't run away.
-- 1) a clear spot 5-11 studs from the mob we fight (still in swing reach), the one closest to us;
-- 2) else a clear spot near us; 3) else the map start / high above.
local curTarget = nil -- mob root part we fight
-- dq_164: hover height over a mob's root. Learned value (16-24) as before, but a tall boss can be swung from 11 over
-- the top of its Hitbox part (measured lvl 275: swings land on Lifeless from 12 over its 60-tall Hitbox) - and from
-- there we sit over every attack box of that room (tops 284-295, we are at 303). Never more than 32 over the root.
S.hoverFor = function(m)
    local h = math.max(16, math.min(24, tonumber(m and cfg.mobHeight[m.Name]) or 20))
    local hb = m and m:FindFirstChild("Hitbox")
    local rt = m and m:FindFirstChild("HumanoidRootPart")
    if hb and rt and hb:IsA("BasePart") and rt:IsA("BasePart") then
        local t = hb.Position.Y + hb.Size.Y / 2 + 11 - rt.Position.Y
        if t > h and #Players:GetPlayers() <= 1 then h = math.min(t, 32) end -- dq_182: solo only (party keeps the 24 cap, #101 history)
    end
    return h
end
-- dq_190 Boss Rush (top tier, 11-24): every boss hit there takes the whole hp bar and a run has 3 lives. Addonis
-- kills everything within ~60 studs of it every 22.5 s, 0.35 s after its floor disc (Indicator 2x120x116) shows -
-- also 64 studs up (3 deaths in 3 tries, hovering over it). Such bosses are fought from outside that reach with Q / E.
-- S.bossKeep[name] = studs to keep from the boss (flat); only bosses whose reach was measured.
S.bossKeep = { Addonis = 67 }
S.soFor = function(name)
    local so = tonumber(cfg.standOff) or 0
    local k = name and cfg.mode == "Boss Rush" and S.bossKeep[name]
    if k and k > so then so = k end
    return so
end
local function sideSpot(from)
    if curTarget and curTarget.Parent then
        local tp = curTarget.Position
        local best, bestD
        local so = S.soFor(curTarget.Parent.Name)
        for _, rad in ipairs(so > 0 and { so, so + 6, math.max(5, so - 6) } or { 5, 8, 11 }) do
            for k = 0, 15 do
                local a = k * math.pi / 8
                local hov = (cfg.move ~= "Walk") and (tonumber(cfg.hover) or 0) > 0 and ((curTarget and curTarget.Parent) and S.hoverFor(curTarget.Parent) or 24) or 0 -- stay up: melee swings miss us
                local p = Vector3.new(tp.X + math.cos(a) * rad, tp.Y + hov, tp.Z + math.sin(a) * rad)
                local dd = (p - from).Magnitude
                -- 11-22 friend #101 (lvl 185 party): target switched to a mob ~280 studs away and the dodge flew to it
                -- (1123 studs in 10 s). A dodge stays within 45 studs, like the fallback in safeSpot.
                if dd <= 45 and okSpot(p) then
                    if not bestD or dd < bestD then best, bestD = p, dd end
                end
            end
            if best then return best end
        end
    end
    return nil
end
-- owner 11-21: "dodge to a place it can still hit from - dodging without damage wastes more time".
-- Order: 1) beside the target (5-11 studs) 2) a little further but still in swing reach (14-22)
-- 3) only for a big attack (a ring wider than 60 = a wipe) leave the area; a small zone with no clear spot
--    in reach = stay and keep hitting.
local function safeSpot(from, zone)
    -- dq_164 (lvl 275 Lifeless + Soulless room): every attack there is arena-wide (SlamLines 378x373, BigSlash 89x361,
    -- HoleInWall 395 long, shock rings up to 234) but none reaches more than ~55 over the floor. Sideways there was no
    -- clear spot: we took the "least bad" one and stayed inside BigSlash for its whole 2.9 s (7 hits a run), or stood
    -- 140 studs from the flower for 14 s. Over the top there always is a clear spot, and Q / E still reach from there
    -- (measured: full 578T hit on the flower from 58 studs over it). So: a wide zone -> over its top first.
    local function liftSpot()
        local up = liftOver(from, dangerAt)
        if up and (not (curTarget and curTarget.Parent) or S.reachOK(up, curTarget)) then return up end
        return nil
    end
    if zone and zone.Parent and #Players:GetPlayers() <= 1 and math.max(zone.Size.X, zone.Size.Y, zone.Size.Z) >= 60 then -- (dq_182: lift-first only solo)
        local up = liftSpot()
        if up then return up end
    end
    local s = sideSpot(from)
    if s then return s end
    if curTarget and curTarget.Parent then
        local tp = curTarget.Position
        local hov = (cfg.move ~= "Walk") and (tonumber(cfg.hover) or 0) > 0 and ((curTarget and curTarget.Parent) and S.hoverFor(curTarget.Parent) or 24) or 0
        local best, bestD
        for _, rad in ipairs({ 14, 18, 22 }) do
            for k = 0, 15 do
                local a = k * math.pi / 8
                local p = Vector3.new(tp.X + math.cos(a) * rad, tp.Y + hov, tp.Z + math.sin(a) * rad)
                local dd = (p - from).Magnitude
                -- 11-22 friend #101 (lvl 185 party): target switched to a mob ~280 studs away and the dodge flew to it
                -- (1123 studs in 10 s). A dodge stays within 45 studs, like the fallback in safeSpot.
                if dd <= 45 and okSpot(p) then
                    if not bestD or dd < bestD then best, bestD = p, dd end
                end
            end
            if best then return best end
        end
    end
    -- no clear spot in reach: get out anyway (11-21 Cursed Marshes: stayed in a 50-wide zone and took -2040)
    -- 11-21 15:54 kick "Abnormal player behaviour #101" came right after a 420-stud instant dodge: stay within 45 studs
    -- 11-23 lvl 260: this ring used our own height - after a respawn on the floor every dodge stayed on the floor
    -- (Formless PlayerRing / BigSword / slices all reach the floor). Use the hover height over the target when we fight.
    local baseY = from.Y
    if curTarget and curTarget.Parent and cfg.move ~= "Walk" then
        baseY = math.max(from.Y, curTarget.Position.Y + S.hoverFor(curTarget.Parent))
    end
    -- dq_186 (first No Hit attempt, 11-24 15:48: "no clear spot" twice during the pizza, we stayed in a lit slice and
    -- it went off). The fallback ring below samples 12 directions around us and can miss the dark slices' strips
    -- (12 studs wide at 60 from the centre). For a pizza slice look along circles around the pizza centre instead:
    -- every 5 degrees, at 70+ / 100 / 135 studs out, and take the middle of the nearest clear arc (3+ samples wide).
    if zone and zone.Parent and zone.Parent.Parent and zone.Parent.Parent.Name == "Slices" and S.pizzaCentreOf then
        local c = S.pizzaCentreOf(zone.Parent.Parent)
        if c then
            local v = Vector3.new(from.X - c.X, 0, from.Z - c.Z)
            local a0 = math.atan2(v.Z, v.X)
            for _, R in ipairs({ math.clamp(v.Magnitude, 100, 380), 130, 160 }) do
                local q = S.pizzaSpot(c, a0, R, baseY)
                if q then return q end
            end
        end
    end
    local base = Vector3.new(from.X, baseY, from.Z)
    -- dq_170: this ring took the first clear spot (always tried +X first), so a fight full of zones walked us away from
    -- the boss: lvl 270 Formless, 93-283 studs off for the whole 17-25 s of each pizza = no Q / E, no damage, run lost
    -- on time. Of the clear spots at one radius take the one nearest the mob we fight.
    local tgt = (curTarget and curTarget.Parent) and curTarget.Position or nil
    -- (dq_174: + 60 and 75 - from the middle of the BigSword lane 45 studs did not reach a clear spot: "no clear spot"
    -- for 2 s on the floor after a TeleportSlash put us there, then the sword. Moves over 40 studs go in steps.)
    for _, rad in ipairs({ 8, 14, 22, 32, 45, 60, 75 }) do
        local best, bd
        for k = 0, 11 do
            local a = k * math.pi / 6
            local p = base + Vector3.new(math.cos(a) * rad, 0, math.sin(a) * rad)
            if okSpot(p) then
                if not tgt then return p end
                local d = (flat(p) - flat(tgt)).Magnitude
                if not bd or d < bd then best, bd = p, d end
            end
        end
        if best then return best end
    end
    -- dq_164: over the top before the "least bad" spot (that one is still inside a zone)
    do
        local up = liftSpot()
        if up then return up end
    end
    -- nothing fully clear (lvl 260 Formless: lines + slices + sword at once): standing still is the worst choice - the
    -- PlayerRing follows us. Take the spot inside the fewest zones, if that is fewer than where we are.
    do
        local function count(p)
            local n = 0
            for _, z in ipairs(liveDangers()) do if inZone(p, z) then n = n + 1 end end
            return n
        end
        local here = count(from)
        local best, bn, bd
        for _, rad in ipairs({ 14, 22, 32, 45 }) do
            for k = 0, 11 do
                local a = k * math.pi / 6
                local p = base + Vector3.new(math.cos(a) * rad, 0, math.sin(a) * rad)
                if hasFloor(p) and not crowded(p) then
                    local n = count(p)
                    if n < here and (not bn or n < bn or (n == bn and rad < bd)) then best, bn, bd = p, n, rad end
                end
            end
        end
        if best then return best end
    end
    -- 11-23 lvl 220 Neokaze hologram phase: the lift put us 40-50 over the boss for 20 s - no swings, and still hit there.
    -- Lift only to a spot still in reach of the target (same 40 as bossSpot); else stay and keep hitting.
    -- nowhere clear within 110 studs: stay and keep hitting (the old jump to the map start bounced us
    -- 350 studs back and forth every second on 11-21; flying up dropped us into the void)
    return nil
end
--------------------------------------------------------------------------------
-- safe zone (Zyrtas, Sunken Fortress - found 11-21): every ~20 s the boss kills everyone outside
-- Workspace.SafeZoneHitbox / SafeZoneIndicator (29x32), shown ~5 s before. While one exists: stand in its middle.
--------------------------------------------------------------------------------
local safeParts = {}
local function isSafePart(p)
    if not p:IsA("BasePart") then return false end
    -- 11-23 lvl 260 Formless: SafezoneFloor (whole floor) + SafezonePlayer (sits on us) are NOT safe spots. Going down
    -- into them and standing still let the following PlayerRing + BigSword kill us ~5 s later, every time (17 deaths).
    local pn = p.Parent and p.Parent.Name:lower() or ""
    if pn == "safezonefloor" or pn == "safezoneplayer" then return false end
    if p.Name:lower():find("safezone") then return true end
    -- 11-23 lvl 250: the Zuriel Safezone is a Model holding Hitbox / Indicator / Primary parts
    return p.Parent ~= nil and p.Parent:IsA("Model") and p.Parent.Name:lower():find("safezone") ~= nil and (p.Name == "Indicator" or p.Name == "Hitbox")
end
F.conns[#F.conns + 1] = workspace.DescendantAdded:Connect(function(p)
    if isSafePart(p) then
        safeParts[p] = os.clock()
        log(string.format("SAFE ZONE %s %.0fx%.0fx%.0f at %s - going in", p.Name, p.Size.X, p.Size.Y, p.Size.Z, v3s(p.Position)))
    end
end)
for _, p in ipairs(workspace:GetChildren()) do if isSafePart(p) then safeParts[p] = os.clock() end end
local function safeZone()
    -- several zones can be up at once (4 seen): take the nearest one
    local ind, any, bi, ba
    local me = hrp()
    for p in pairs(safeParts) do
        if not p.Parent then safeParts[p] = nil
        -- 11-23 owner: stay up top and only go down when the mechanic needs it. The Zuriel nuke lands ~5 s after its
        -- Safezone shows: wait in the air for the first 3.2 s, then drop into the circle.
        elseif p.Parent:IsA("Model") and p.Parent.Name:lower():find("safezone") and os.clock() - (safeParts[p] or 0) < 3.2 then
        else
            local d = me and (flat(p.Position) - flat(me.Position)).Magnitude or 0
            if not ba or d < ba then any, ba = p, d end
            if p.Name:lower():find("indicator") and (not bi or d < bi) then ind, bi = p, d end
        end
    end
    local p = ind or any
    if not p then return nil end
    -- stand on the floor in the middle: the indicator lies on the floor, the hitbox is a tall box around it
    local y = ind and (ind.Position.Y + 3) or (p.Position.Y - p.Size.Y / 2 + 4)
    -- 11-23 owner (lvl 255 Zuriel): on the floor the floor moves (SwordFall, BigLine, SwordIndicator) kill us while we
    -- wait. The Zuriel Safezone is a 50 ball (Hitbox) centred on the floor: float 15 up, still well inside the ball.
    local m = p.Parent
    if m and m:IsA("Model") and m.Name:lower():find("safezone") then
        local ball = m:FindFirstChild("Hitbox")
        if ball and ball:IsA("BasePart") and cfg.safeFloat then y = ball.Position.Y + math.min(15, ball.Size.Y / 2 - 6) end -- 17:30 test: floating 15 up died 7x to Zuriel (floor: 0) - off by default
    end
    return Vector3.new(p.Position.X, y, p.Position.Z), p
end
S.safeGo = 0
-- new things in the dungeon (boss mechanics like rune rings): log each new name once with class, size, children
do
    local known, seenNew = { Hitbox = true, Indicator = true, Part = true, Warrior = true, SwingHitboxAgony = true, Sword = true,
        DeadlyWhirl = true, DeadlyVortex = true, DropEffectPart = true, CoinEffectPart = true, SpikeParticles = true }
    seenNew = {}
    F.conns[#F.conns + 1] = workspace.ChildAdded:Connect(function(o)
        if not DEV or IN_LOBBY or known[o.Name] or seenNew[o.Name] then return end
        if Players:FindFirstChild(o.Name) then return end
        seenNew[o.Name] = true
        task.delay(0.3, function()
            pcall(function()
                local kids, n = {}, 0
                for _, d in ipairs(o:GetDescendants()) do
                    n = n + 1
                    if #kids < 10 and (d:IsA("BillboardGui") or d:IsA("ImageLabel") or d:IsA("Decal") or d:IsA("BasePart") or d:IsA("Beam") or d:IsA("ParticleEmitter")) then
                        kids[#kids + 1] = d.Name .. ":" .. d.ClassName .. ((d:IsA("ImageLabel") or d:IsA("Decal")) and ("=" .. tostring(d.Image or d.Texture)) or "")
                    end
                end
                local p = o:IsA("BasePart") and o or (o:IsA("Model") and o:FindFirstChildWhichIsA("BasePart", true))
                local r = hrp()
                log(string.format("NEWOBJ %s (%s)%s%s | %d parts: %s", o.Name, o.ClassName,
                    p and string.format(" size %.0fx%.0fx%.0f", p.Size.X, p.Size.Y, p.Size.Z) or "",
                    (p and r) and string.format(" %.0f studs", (p.Position - r.Position).Magnitude) or "", n, table.concat(kids, ",")))
            end)
        end)
    end)
    -- 11-22 DEV: lvl 185 Pale Bloodmaiden "Rose" flowers (boss looked immune while they were up): full dump + boss hp each second
    F.conns[#F.conns + 1] = workspace.ChildAdded:Connect(function(o)
        if not DEV or IN_LOBBY or o.Name ~= "Rose" then return end
        go("rosewatch", function()
            task.wait(0.5)
            local function at(x) local a = {} for k, v in pairs(x:GetAttributes()) do a[#a + 1] = k .. "=" .. tostring(v) end return table.concat(a, ",") end
            local r = hrp()
            local L = { os.date("%H:%M:%S") .. " ROSE attrs {" .. at(o) .. "} me " .. (r and v3s(r.Position) or "?") }
            pcall(function()
                for _, d in ipairs(o:GetDescendants()) do
                    local s = d:GetFullName():gsub("^.-Rose%.", "") .. " " .. d.ClassName
                    if d:IsA("BasePart") then s = s .. string.format(" size %s pos %s collide %s touch %s query %s transp %.2f", v3s(d.Size), v3s(d.Position), tostring(d.CanCollide), tostring(d.CanTouch), tostring(d.CanQuery), d.Transparency) end
                    if d:IsA("ValueBase") then s = s .. " = " .. tostring(d.Value) end
                    if d:IsA("Beam") then s = s .. " a0 " .. tostring(d.Attachment0 and d.Attachment0:GetFullName()) .. " a1 " .. tostring(d.Attachment1 and d.Attachment1:GetFullName()) end
                    if d:IsA("ProximityPrompt") then s = s .. " PROMPT " .. d.ActionText .. " dist " .. d.MaxActivationDistance end
                    local a = at(d) if a ~= "" then s = s .. " {" .. a .. "}" end
                    L[#L + 1] = "  " .. s
                end
            end)
            for _, e in ipairs(enemies()) do L[#L + 1] = string.format("  mob %s %.0fB/%.0fB {%s} at %s", e.m.Name, e.h.Health / 1e9, e.h.MaxHealth / 1e9, at(e.m), v3s(e.r.Position)) end
            pcall(appendfile, DIR .. "/roses.txt", table.concat(L, "\n") .. "\n")
            log("ROSE up -> dq/roses.txt")
            local t0 = os.clock()
            while F.alive and o.Parent and os.clock() - t0 < 90 do
                local s = {}
                for _, e in ipairs(enemies()) do if e.m:GetAttribute("Boss") then s[#s + 1] = string.format("%s %.1fB", e.m.Name, e.h.Health / 1e9) end end
                local n = 0 for _, c in ipairs(workspace:GetChildren()) do if c.Name == "Rose" then n = n + 1 end end
                local me = hrp()
                pcall(appendfile, DIR .. "/roses.txt", string.format("  %.0fs roses %d boss %s me %s target %s\n", os.clock() - t0, n, table.concat(s, ","), me and v3s(me.Position) or "?", tostring(S.target)))
                task.wait(1)
            end
            pcall(appendfile, DIR .. "/roses.txt", string.format("  rose gone after %.0fs\n\n", os.clock() - t0))
            log(string.format("ROSE gone after %.0fs", os.clock() - t0))
        end)
    end)
    -- 11-23 DEV: lvl 250 boss Ephrath one-shots us once a run: Ring -> ImperiumAttack (Solar / Lunar parts, 187x166)
    -- + MiddleCircle + Line -> ~4 s later full hp hit "in zone: none". Record every part of it and where we stand.
    F.conns[#F.conns + 1] = workspace.ChildAdded:Connect(function(o)
        if not DEV or IN_LOBBY or not ({ ImperiumAttack = 1, MiddleCircle = 1, PlayerRing = 1, BigSword = 1, HoleInWall = 1 })[o.Name] or (o.Name ~= "ImperiumAttack" and o.Name ~= "MiddleCircle" and (S.recCount or 0) > 12) then return end
        -- 13:16 record: 4 boxes 187x20x166 around the boss, Solar / Lunar in a checkerboard, a red MiddleCircle Hitbox
        -- in the centre; hovering above the centre = dead at 5.0 s. Try standing on the floor inside one kind of box;
        -- died -> try the other kind next time (cfg.impTry), survived -> keep it.
        if o.Name == "ImperiumAttack" then go("imperiumGo", function()
            task.wait(0.1)
            local want = cfg.impTry == "Solar" and "Solar" or "Lunar"
            local mark = ""
            pcall(function()
                local c = char()
                for k, v in pairs(c and c:GetAttributes() or {}) do mark = mark .. k .. "=" .. tostring(v) .. " " end
                for _, d in ipairs(c and c:GetDescendants() or {}) do
                    local n = d.Name:lower() if n:find("solar") or n:find("lunar") or n:find("sun") or n:find("moon") then mark = mark .. "[" .. d.Name .. "] " end
                end
            end)
            local r = hrp()
            local best, bd
            for _, b in ipairs(o:GetChildren()) do
                if b:IsA("BasePart") and b.Name == want and r then
                    local d = (flat(b.Position) - flat(r.Position)).Magnitude
                    if not bd or d < bd then best, bd = b, d end
                end
            end
            -- owner 13:20 (his brother): this is an event - mash Q and E. Press the real keys like a player for 6 s,
            -- and log what the screen says. The box move stays off (cfg.impBox) so we learn which one saves us.
            go("imperiumKeys", function()
                local vim = game:GetService("VirtualInputManager")
                local t1 = os.clock()
                local n = 0
                while F.alive and o.Parent and os.clock() - t1 < 6 do
                    for _, k in ipairs({ Enum.KeyCode.Q, Enum.KeyCode.E }) do
                        pcall(function() vim:SendKeyEvent(true, k, false, game) vim:SendKeyEvent(false, k, false, game) end)
                        n = n + 1
                    end
                    if n == 20 then pcall(function()
                        local t = {}
                        for _, d in ipairs(LP.PlayerGui:GetDescendants()) do
                            if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Visible and #d.Text > 0 and #d.Text < 60 then
                                local g = d:FindFirstAncestorWhichIsA("ScreenGui")
                                if g and g.Enabled and not ({ QuestUi = 1, Inventory = 1, cosmeticsGui = 1, ItemIndex = 1, NewSettings = 1, HowToPlay = 1, PlayNew = 1, Portals = 1, Loading = 1, InfiniteRejoin = 1, CompletionScreen = 1 })[g.Name] then
                                    t[#t + 1] = g.Name .. ":" .. d.Text
                                end
                            end
                            if #t > 25 then break end
                        end
                        log("IMPERIUM screen: " .. table.concat(t, " | "))
                    end) end
                    task.wait(0.06)
                end
                log("IMPERIUM mashed Q/E " .. n .. " times")
            end)
            -- 13:41 record: the MiddleCircle.Circle (light blue, ~73 wide, on the floor under the boss) fades IN during
            -- the move (tr 1 -> 0.75 -> 0.30) = the spot the game shows. Boxes: Lunar died, Solar died (hit at 3 s and 5 s).
            -- 13:48: middle circle = dead at 2.8 s (Line beams + MiddleCircle hitbox). Every spot inside the 4 boxes
            -- took the 5 s hit -> try outside them: 4 spots just past the boxes' outer edge, on a floor found by raycast.
            if cfg.impTry == "Out" and cfg.impBox then
                local bmin, bmax
                for _, b in ipairs(o:GetChildren()) do
                    if b:IsA("BasePart") then
                        local lo, hi = b.Position - b.Size / 2, b.Position + b.Size / 2
                        bmin = bmin and Vector3.new(math.min(bmin.X, lo.X), 0, math.min(bmin.Z, lo.Z)) or Vector3.new(lo.X, 0, lo.Z)
                        bmax = bmax and Vector3.new(math.max(bmax.X, hi.X), 0, math.max(bmax.Z, hi.Z)) or Vector3.new(hi.X, 0, hi.Z)
                    end
                end
                local r0 = hrp()
                if bmin and r0 then
                    local cx, cz, y0 = (bmin.X + bmax.X) / 2, (bmin.Z + bmax.Z) / 2, r0.Position.Y
                    local cands = { Vector3.new(bmax.X + 20, y0, cz), Vector3.new(bmin.X - 20, y0, cz), Vector3.new(cx, y0, bmax.Z + 20), Vector3.new(cx, y0, bmin.Z - 20) }
                    local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Exclude
                    rp.FilterDescendantsInstances = { char(), o, workspace:FindFirstChild("Enemies") }
                    local spot
                    for _, c in ipairs(cands) do
                        local hit = workspace:Raycast(c + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), rp)
                        if hit and hit.Instance and hit.Instance.CanCollide then spot = hit.Position + Vector3.new(0, 3, 0) break end
                    end
                    if spot then
                        S.impSpot = spot
                        log(string.format("IMPERIUM try outside the boxes at %s (boxes %s..%s)", v3s(spot), v3s(bmin), v3s(bmax)))
                        local died = false
                        local h = hum()
                        local c1 = h and h.Died:Connect(function() died = true end)
                        local t0 = os.clock()
                        while F.alive and o.Parent and os.clock() - t0 < 9 do task.wait(0.2) end
                        S.impSpot = nil
                        if c1 then c1:Disconnect() end
                        log("IMPERIUM outside the boxes: " .. (died and "DIED" or "SURVIVED"))
                        return
                    end
                    log("IMPERIUM outside: no floor past any box edge")
                end
            end
            if cfg.impTry == "Middle" and cfg.impBox then
                local mc = workspace:FindFirstChild("MiddleCircle") or workspace:WaitForChild("MiddleCircle", 1.5)
                local circ = mc and (mc:FindFirstChild("Circle") or mc:FindFirstChild("Hitbox"))
                if circ then
                    S.impSpot = Vector3.new(circ.Position.X, circ.Position.Y + 4, circ.Position.Z)
                    log(string.format("IMPERIUM try the middle circle at %s", v3s(S.impSpot)))
                    local died = false
                    local h = hum()
                    local c1 = h and h.Died:Connect(function() died = true end)
                    local t0 = os.clock()
                    while F.alive and o.Parent and os.clock() - t0 < 9 do task.wait(0.2) end
                    S.impSpot = nil
                    if c1 then c1:Disconnect() end
                    log("IMPERIUM middle circle: " .. (died and "DIED" or "SURVIVED"))
                    return
                end
            end
            if not best or not cfg.impBox then best = nil end
            if not best then
                local died = false
                local h = hum()
                local c1 = h and h.Died:Connect(function() died = true end)
                local t0 = os.clock()
                while F.alive and o.Parent and os.clock() - t0 < 9 do task.wait(0.2) end
                if c1 then c1:Disconnect() end
                log("IMPERIUM with Q/E mashing: " .. (died and "DIED" or "SURVIVED"))
                return
            end
            local ind = best:FindFirstChild("Indicator")
            -- inner corner side of the box would be next to the boss; aim at the box centre on the floor
            S.impSpot = Vector3.new(best.Position.X, (ind and ind.Position.Y or best.Position.Y - 9) + 3, best.Position.Z)
            log(string.format("IMPERIUM try %s box at %s (char marks: %s)", want, v3s(S.impSpot), mark ~= "" and mark or "none"))
            local died = false
            local h = hum()
            local c1 = h and h.Died:Connect(function() died = true end)
            local t0 = os.clock()
            while F.alive and o.Parent and os.clock() - t0 < 9 do task.wait(0.2) end
            S.impSpot = nil
            if c1 then c1:Disconnect() end
            if died then
                cfg.impTry = (want == "Lunar") and "Solar" or "Lunar" saveCfg()
                log("IMPERIUM died in the " .. want .. " box - next time " .. cfg.impTry)
            else
                cfg.impTry = want saveCfg()
                log("IMPERIUM survived in the " .. want .. " box - keep it")
            end
        end) end
        go("imperium", function()
            task.wait(0.2)
            local t0 = os.clock()
            local L = { os.date("%H:%M:%S") .. " " .. o.Name }
            local function dump(tag)
                for _, d in ipairs(o:GetDescendants()) do
                    if d:IsA("BasePart") then
                        L[#L + 1] = string.format("  %s %s %s size %s pos %s up %s tr %.2f col %s", tag, d:GetFullName():gsub("^Workspace%.", ""), d.ClassName, v3s(d.Size), v3s(d.Position), v3s(d.CFrame.UpVector * 10), d.Transparency, tostring(d.Color))
                    end
                end
                for k, v in pairs(o:GetAttributes()) do L[#L + 1] = "  attr " .. k .. "=" .. tostring(v) end
            end
            dump("t0")
            local dumped = {}
            while F.alive and o.Parent and os.clock() - t0 < 8 do
                for _, ts in ipairs({ 2, 4, 4.8 }) do
                    if not dumped[ts] and os.clock() - t0 >= ts then dumped[ts] = true dump("t" .. ts) end
                end
                local r, h = hrp(), hum()
                local boss
                for _, e in ipairs(enemies()) do if e.m.Name == "Ephrath" then boss = e.r.Position end end
                L[#L + 1] = string.format("  %.1fs me %s hp %.0fM | Ephrath %s", os.clock() - t0, r and v3s(r.Position) or "-", h and h.Health / 1e6 or -1, boss and v3s(boss) or "-")
                task.wait(0.5)
            end
            L[#L + 1] = string.format("  gone after %.1fs", os.clock() - t0)
            pcall(appendfile, DIR .. "/imperium.txt", table.concat(L, "\n") .. "\n\n")
            S.recCount = (S.recCount or 0) + 1 log("IMPERIUM recorded " .. o.Name .. " -> dq/imperium.txt")
        end)
    end)
    -- 11-22 DEV: lvl 220 Neon District last boss Mue no Ikari - FloorLava (Hitbox 50x444x528) covers the whole arena,
    -- no dodge spot is ever clear and we die 6+ times. Record the zone's frame, the floor under us and the boss each second.
    F.conns[#F.conns + 1] = workspace.DescendantAdded:Connect(function(o)
        if not DEV or IN_LOBBY or not o:IsA("BasePart") or not isDanger(o) then return end
        local s = o.Size
        local big = 0 for _, v in ipairs({ s.X, s.Y, s.Z }) do if v >= 300 then big = big + 1 end end
        if big < 2 or S.lavaRec then return end
        S.lavaRec = true
        go("lavawatch", function()
            local L = { os.date("%H:%M:%S") .. " FLOORZONE " .. o:GetFullName() .. " size " .. v3s(o.Size) .. " pos " .. v3s(o.Position)
                .. " right " .. v3s(o.CFrame.RightVector * 10) .. " up " .. v3s(o.CFrame.UpVector * 10) .. " look " .. v3s(o.CFrame.LookVector * 10) }
            pcall(function()
                for _, d in ipairs(o.Parent:GetDescendants()) do
                    if d:IsA("BasePart") then L[#L + 1] = string.format("  part %s size %s pos %s up %s collide %s", d.Name, v3s(d.Size), v3s(d.Position), v3s(d.CFrame.UpVector * 10), tostring(d.CanCollide)) end
                end
            end)
            pcall(appendfile, DIR .. "/lava.txt", table.concat(L, "\n") .. "\n")
            log("FLOORZONE " .. o:GetFullName() .. " " .. v3s(o.Size) .. " -> dq/lava.txt")
            local t0 = os.clock()
            while F.alive and o.Parent and os.clock() - t0 < 60 do
                local me = hrp()
                local fl = "none"
                if me then
                    local hit = workspace:Raycast(me.Position, Vector3.new(0, -200, 0), floorParams)
                    if hit then fl = string.format("%s y%.0f collide %s", hit.Instance:GetFullName(), hit.Position.Y, tostring(hit.Instance.CanCollide)) end
                end
                local b = {}
                for _, e in ipairs(enemies()) do b[#b + 1] = string.format("%s %s", e.m.Name, v3s(e.r.Position)) end
                local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                pcall(appendfile, DIR .. "/lava.txt", string.format("  %.0fs me %s hp %.0fM inLava %s floor %s | %s\n", os.clock() - t0, me and v3s(me.Position) or "?",
                    hum and hum.Health / 1e6 or -1, tostring(me and inZone(me.Position, o, 0) or false), fl, table.concat(b, ", ")))
                task.wait(1)
            end
            pcall(appendfile, DIR .. "/lava.txt", string.format("  floor zone gone after %.0fs\n\n", os.clock() - t0))
            S.lavaRec = nil
        end)
    end)
end
S.dodges = 0
local lastDodge = 0
local zoneWorthDodging -- set further down (needs the learned threat table)
local function dodgeCheck()
    if IN_LOBBY then return false end
    do -- safe zone beats everything else, red zones included
        local sp = safeZone() or S.impSpot
        if sp then
            local r0 = hrp()
            if r0 and (flat(r0.Position) - flat(sp)).Magnitude > 5 then
                local look = (curTarget and curTarget.Parent) and curTarget.Position or (sp + r0.CFrame.LookVector)
                setCF(faceCF(sp, look))
                S.safeGo = S.safeGo + 1
            end
            return true
        end
    end
    if not cfg.dodge and not cfg.dodgeLight then return false end
    local r = hrp()
    if not r then return false end
    -- 11-21 DQKICK: a friend (not the party host) got #101 after 40 dodges in 27 s, 20-50 studs each. The host never does,
    -- so in a party: at most one dodge a second and only short ones (25 studs); otherwise stay and take the hit.
    -- (dq_90 slowed party dodges to 1/s, 25 studs: the friend was still kicked with only 8 dodges - back to the old rule)
    if os.clock() - lastDodge < 0.25 then return false end
    -- dq_166: a stepped dodge (or the game carrying us) is still moving us - a second one now would pull against it
    if S.dodgeFlight and os.clock() < S.dodgeFlight then return true end -- dq_178: own stepped dodge only (was S.movingUntil = also carry pauses)
    -- (dq_92 skipped dodges over the move budget; owner 11-21: dodge as before - only the travel is slowed)
    local zone = dangerAt(r.Position)
    -- Light: let small zones hit us, leave only the big area attacks
    if zone and not zoneWorthDodging(zone) then
        -- the zone we are in is harmless by experience; still dodge if another one here is not
        zone = nil
        for _, p in ipairs(liveDangers()) do if inZone(r.Position, p) and zoneWorthDodging(p) then zone = p break end end
    end
    if zone then
        S.zoneSeen = S.zoneSeen or {}
        if cfg.timingLog and not S.zoneSeen[zone] then
            S.zoneSeen[zone] = true
            log(string.format("ZONE %s %.0fx%.0fx%.0f age %.1fs", zone:GetFullName():gsub("^Workspace%.", ""), zone.Size.X, zone.Size.Y, zone.Size.Z,
                os.clock() - (dangers[zone] or os.clock())))
        end
        local to = safeSpot(r.Position, zone)
        if not to then
            if os.clock() - (S.noSpotT or 0) > 3 then S.noSpotT = os.clock() log(string.format("DODGE no clear spot with floor near %s (zone %s %.0fx%.0fx%.0f)", v3s(r.Position), zone.Name, zone.Size.X, zone.Size.Y, zone.Size.Z)) end
            return false
        end
        lastDodge = os.clock()
        local look = (curTarget and curTarget.Parent) and curTarget.Position or (to + r.CFrame.LookVector)
        -- never one instant jump of more than 40 studs (anti-cheat #101): longer dodges go in steps
        if (to - r.Position).Magnitude > 40 then
            -- while this stepped move runs, the hover hold must not drag us back to the old spot
            S.movingUntil = os.clock() + 3
            S.dodgeFlight = os.clock() + 3
            task.spawn(function() moveTo(to, look) S.movingUntil = nil S.dodgeFlight = nil end)
        else
            setCF(faceCF(to, look)) -- face the mob: the swing loop keeps hitting from the side
        end
        S.dodges = S.dodges + 1
        local zn = ((zone.Parent and zone.Parent ~= workspace) and (zone.Parent.Name .. ".") or "") .. zone.Name
        if zone.Parent and zone.Parent.Parent and zone.Parent.Parent.Name == "Slices" then zn = "PizzaSlice" end
        S.dodgeBy = S.dodgeBy or {}
        S.dodgeBy[zn] = (S.dodgeBy[zn] or 0) + 1
        if os.clock() - (S.lastDodgeLog or 0) > 3 then S.lastDodgeLog = os.clock() log(string.format("DODGE -> %s (%s, %d live zones, %d dodges)", v3s(to), zn, #liveDangers(), S.dodges)) end
        return true
    end
    return false
end
-- 10 checks a second is enough (every frame was 60 a second, heavy on phones)
local lastDodgeCheck = 0
F.conns[#F.conns + 1] = RunService.Heartbeat:Connect(function()
    local now = os.clock()
    if now - lastDodgeCheck < 0.1 then return end
    lastDodgeCheck = now
    if cfg.farm and not S.limitBusy then
        local ok, err = pcall(dodgeCheck)
        if not ok and os.clock() - (S.dodgeErrT or 0) > 10 then S.dodgeErrT = os.clock() log("ERR dodge: " .. tostring(err)) end
    end
end)
-- what hit us: nearest mob (and how high we are over it) + any red zone we stand in or next to
local function hitWhy()
    local r = hrp()
    if not r then return "-" end
    local near, nd = nil, math.huge
    for _, e in ipairs(enemies()) do
        local d = (e.r.Position - r.Position).Magnitude
        if d < nd then near, nd = e, d end
    end
    local zin, znear = {}, 0
    for _, p in ipairs(liveDangers()) do
        local nm = (p.Parent and p.Parent ~= workspace and p.Parent.Name .. "." or "") .. p.Name
        if inZone(r.Position, p, 0) then zin[#zin + 1] = nm .. string.format("(%.0fx%.0fx%.0f, %.0f ms old)", p.Size.X, p.Size.Y, p.Size.Z, (os.clock() - (dangers[p] or os.clock())) * 1000)
        elseif (p.Position - r.Position).Magnitude < 40 then znear = znear + 1 end
    end
    return string.format("mob %s %.0f studs, %.0f up | in zone: %s | zones near %d",
        near and near.m.Name or "-", nd, near and (r.Position.Y - near.r.Position.Y) or 0,
        #zin > 0 and table.concat(zin, ",") or "none", znear)
end
--------------------------------------------------------------------------------
-- learn the wind-ups: red rings come 0-0.2 s before the damage (measured 11-21), too late to react to.
-- Every mob animation start is noted; when we get hit, the animations started by mobs near us in the 1.6 s
-- before count as "hit" for that animation. An animation with 2+ hits that hits on 30 %+ of its plays is a
-- wind-up: next time a mob starts it near us we leave its reach first, then come back and hit.
-- Learned table survives runs in cfg.dangerAnims[id] = {p = plays, h = hits, r = reach}.
--------------------------------------------------------------------------------
local animLog = {} -- {mob = model, root = part, id = string, t = clock}
local recentDeaths = {} -- {name, t, pos}
S.avoid = nil -- {root, radius, untilT, id}
-- learned threat (owner 11-21: "dodge smarter"): every hit taken inside zones adds that hit's share of our max hp to
-- each zone shape we stood in (cfg.zoneDmg[sig] = {n, d}); Light mode dodges a zone only when its shape has hurt
-- (12 %+ of max hp per hit) or, unknown yet, when it is wide (40+). Small known-harmless zones: stay and hit.
local function zoneSig(p)
    local nm = (p.Parent and p.Parent ~= workspace) and p.Parent.Name or p.Name
    local function r5(v) return math.floor(v / 5 + 0.5) * 5 end
    return nm .. ":" .. r5(p.Size.X) .. "x" .. r5(p.Size.Z)
end
local function zoneThreat(p)
    local z = cfg.zoneDmg[zoneSig(p)]
    if z and (z.n or 0) >= 1 then return (z.d or 0) / z.n, z.n end
    return nil, 0
end
zoneWorthDodging = function(p)
    if cfg.dodge then return true end
    -- lvl 260 Formless: the following ring and the big sword hit for 25-50% each - always leave them
    if p.Name == "Part" and p.Parent == workspace then return true end
    if p.Parent and (p.Parent.Name == "PlayerRing" or p.Parent.Name == "BigSword" or p.Parent.Name == "ArenaLine" or p.Parent.Name == "EmberwingLingerLine" or p.Parent.Name == "TeleportSlash") then return true end
    -- lingering pools (Heldeir 50x50, 11-21): each tick is small (~6%) but they add up - leave once this zone took 10%
    if S.zoneHits and (S.zoneHits[p] or 0) >= 0.10 then return true end
    local avg = zoneThreat(p)
    if avg then return avg >= 0.12 end
    return math.max(p.Size.X, p.Size.Z) >= 40
end
local function animWarn(id)
    local a = cfg.dangerAnims[id]
    if not (a and (a.h or 0) >= 2 and (a.h or 0) / math.max(1, a.p or 1) >= 0.3) then return false end
    -- Light: only wind-ups whose hits were big (15 %+ of max hp on average)
    if not cfg.dodge then return (a.d or 0) / math.max(1, a.h) >= 0.15 end
    return true
end
local function hookMob(m)
    pcall(function()
        -- the Animator may sit under the Humanoid or an AnimationController, and may come a moment later
        -- (11-21: "anims none" on every hit - the old lookup only tried Humanoid.Animator)
        local an = m:FindFirstChildWhichIsA("Animator", true)
        local t0 = os.clock()
        while not an and os.clock() - t0 < 6 and m.Parent do task.wait(0.25) an = m:FindFirstChildWhichIsA("Animator", true) end
        if not an then return end
        F.conns[#F.conns + 1] = an.AnimationPlayed:Connect(function(track)
            local id = track.Animation and track.Animation.AnimationId or "?"
            id = id:match("%d+") or id
            local root = mobRoot(m)
            local now = os.clock()
            animLog[#animLog + 1] = { mob = m, root = root, id = id, t = now }
            if #animLog > 80 then table.remove(animLog, 1) end
            local a = cfg.dangerAnims[id] or { p = 0, h = 0, r = 0 }
            a.p = (a.p or 0) + 1
            cfg.dangerAnims[id] = a
            if (cfg.dodge or cfg.dodgeLight) and cfg.farm and animWarn(id) and root then
                local r = hrp()
                local reach = math.max(18, a.r or 0)
                if r and (flat(root.Position) - flat(r.Position)).Magnitude < reach + 6 then
                    S.avoid = { root = root, radius = reach + 6, untilT = now + 1.6, id = id, mob = m.Name }
                    log(string.format("PREDODGE %s anim %s (hit %d of %d plays) - out to %.0f studs", m.Name, id, a.h, a.p, reach + 6))
                end
            end
        end)
    end)
end
do
    local folder = workspace:FindFirstChild("Enemies")
    if folder then
        for _, m in ipairs(folder:GetChildren()) do if m:IsA("Model") then task.spawn(hookMob, m) end end
        F.conns[#F.conns + 1] = folder.ChildAdded:Connect(function(m) if m:IsA("Model") then task.spawn(hookMob, m) end end)
    end
    local ee = R("EnemyEffect")
    if ee then
        F.conns[#F.conns + 1] = ee.OnClientEvent:Connect(function(kind, m)
            if kind == "Death" and typeof(m) == "Instance" then
                local root = m:IsA("Model") and mobRoot(m)
                recentDeaths[#recentDeaths + 1] = { name = m.Name, t = os.clock(), pos = root and root.Position }
                if #recentDeaths > 20 then table.remove(recentDeaths, 1) end
            end
        end)
    end
    -- bosses (Zyrtas, Sunken Defender) play no animation on our side: the server sends their attacks as
    -- ByteNetReliable(buffer, {mob, ...}). The buffer's first byte = packet kind -> learned like an animation, id "bn<kind>".
    local bn = R("ByteNetReliable")
    if bn then
        F.conns[#F.conns + 1] = bn.OnClientEvent:Connect(function(buf, refs)
            pcall(function()
                if IN_LOBBY or not cfg.farm or typeof(buf) ~= "buffer" or type(refs) ~= "table" then return end
                local kind = buffer.len(buf) > 0 and buffer.readu8(buf, 0) or -1
                local id = "bn" .. tostring(kind)
                local folder = workspace:FindFirstChild("Enemies")
                for _, m in pairs(refs) do
                    if typeof(m) == "Instance" and m:IsA("Model") and folder and m.Parent == folder then
                        local root = mobRoot(m)
                        local now = os.clock()
                        animLog[#animLog + 1] = { mob = m, root = root, id = id, t = now }
                        if #animLog > 80 then table.remove(animLog, 1) end
                        local a = cfg.dangerAnims[id] or { p = 0, h = 0, r = 0 }
                        a.p = (a.p or 0) + 1
                        cfg.dangerAnims[id] = a
                        if (cfg.dodge or cfg.dodgeLight) and cfg.farm and animWarn(id) and root then
                            local r = hrp()
                            local reach = math.max(18, a.r or 0)
                            if r and (flat(root.Position) - flat(r.Position)).Magnitude < reach + 6 then
                                S.avoid = { root = root, radius = reach + 6, untilT = now + 1.6, id = id, mob = m.Name }
                                log(string.format("PREDODGE %s packet %s (hit %d of %d) - out to %.0f studs", m.Name, id, a.h, a.p, reach + 6))
                            end
                        end
                        break
                    end
                end
            end)
        end)
    end
    go("learnsave", function() while F.alive do task.wait(DEV and 30 or 120) saveCfg() end end)
end
local function learnHit(dmg, maxHp)
    if dmg < maxHp * 0.03 then return "" end
    local r = hrp()
    if not r then return "" end
    local now, used, names = os.clock(), {}, {}
    for _, e in ipairs(animLog) do
        local key = e.id .. tostring(e.mob)
        if now - e.t < 1.6 and e.root and not used[key] then
            local d = (flat(e.root.Position) - flat(r.Position)).Magnitude
            if d < 60 then
                used[key] = true
                local a = cfg.dangerAnims[e.id] or { p = 1, h = 0, r = 0 }
                a.h = (a.h or 0) + 1
                a.d = (a.d or 0) + dmg / maxHp
                a.r = math.max(a.r or 0, math.min(60, d + 8))
                cfg.dangerAnims[e.id] = a
                names[#names + 1] = string.format("%s:%s(%d/%d)", e.mob.Name, e.id, a.h, a.p or 1)
            end
        end
    end
    local zn = {}
    for _, p in ipairs(liveDangers()) do
        if inZone(r.Position, p, 0) then
            S.zoneHits = S.zoneHits or setmetatable({}, { __mode = "k" })
            S.zoneHits[p] = (S.zoneHits[p] or 0) + dmg / maxHp
            local sig = zoneSig(p)
            if not zn[sig] then
                zn[sig] = true
                local z = cfg.zoneDmg[sig] or { n = 0, d = 0 }
                z.n, z.d = (z.n or 0) + 1, (z.d or 0) + dmg / maxHp
                cfg.zoneDmg[sig] = z
            end
        end
    end
    local died = {}
    for _, d in ipairs(recentDeaths) do
        if now - d.t < 5 then
            died[#died + 1] = string.format("%s %.1fs ago%s", d.name, now - d.t, d.pos and string.format(" %.0f studs", (flat(d.pos) - flat(r.Position)).Magnitude) or "")
        end
    end
    return " | anims " .. (#names > 0 and table.concat(names, ",") or "none") .. " | died " .. (#died > 0 and table.concat(died, ",") or "none")
end

-- 11-23 owner: "dodge everything at lvl 260". Most 260 hits come with no zone, or a zone 35-50 ms before the damage.
-- Pre-hit recorder (owner's PC only): keeps the last 2.5 s of the 4 nearest mobs (position, playing animations) and
-- every new part within 80 studs; on each hit writes that window to dq/prehit.txt to find the tell of each attack.
do
    if DEV and not IN_LOBBY then
        local frames, parts = {}, {}
        F.conns[#F.conns + 1] = workspace.DescendantAdded:Connect(function(p)
            if not p:IsA("BasePart") then return end
            local r = hrp()
            if not r then return end
            local ok, pos = pcall(function() return p.Position end)
            if not ok or (pos - r.Position).Magnitude > 80 then return end
            local c = char()
            if c and p:IsDescendantOf(c) then return end
            parts[#parts + 1] = { t = os.clock(), s = string.format("%s/%s %.0fx%.0fx%.0f d%.0f dy%.0f", p.Parent and p.Parent.Name or "?", p.Name,
                p.Size.X, p.Size.Y, p.Size.Z, (pos - r.Position).Magnitude, r.Position.Y - pos.Y) }
            if #parts > 120 then table.remove(parts, 1) end
        end)
        pcall(function()
            local bnr = R("ByteNetReliable")
            if not bnr then return end
            F.conns[#F.conns + 1] = bnr.OnClientEvent:Connect(function(buf, refs)
                if typeof(buf) ~= "buffer" then return end
                local r = hrp()
                if not r then return end
                local who = {}
                if type(refs) == "table" then
                    for _, m in pairs(refs) do
                        if typeof(m) == "Instance" and m:IsA("Model") then
                            local root = mobRoot(m)
                            who[#who + 1] = m.Name .. (root and string.format(" d%.0f", (root.Position - r.Position).Magnitude) or "")
                        end
                    end
                end
                local hex = {}
                for i = 0, math.min(buffer.len(buf), 20) - 1 do hex[#hex + 1] = string.format("%02x", buffer.readu8(buf, i)) end
                parts[#parts + 1] = { t = os.clock(), s = "PKT " .. table.concat(hex) .. " len" .. buffer.len(buf) .. " " .. table.concat(who, ",") }
                if #parts > 160 then table.remove(parts, 1) end
            end)
        end)
        go("prehit", function()
            while F.alive do
                task.wait(0.1)
                local r = hrp()
                if r and cfg.farm then
                    local list = enemies()
                    table.sort(list, function(a, b) return (a.r.Position - r.Position).Magnitude < (b.r.Position - r.Position).Magnitude end)
                    local row = {}
                    for i = 1, math.min(4, #list) do
                        local e = list[i]
                        local an = {}
                        pcall(function()
                            local a = e.m:FindFirstChildWhichIsA("Animator", true)
                            local src = a or e.h
                            for _, tr in ipairs(src:GetPlayingAnimationTracks()) do
                                local id = tr.Animation and tr.Animation.AnimationId or "?"
                                an[#an + 1] = (id:match("%d+") or id):sub(-6) .. "@" .. string.format("%.1f", tr.TimePosition)
                            end
                        end)
                        row[#row + 1] = string.format("%s d%.0f dy%.0f [%s]", e.m.Name, (e.r.Position - r.Position).Magnitude, r.Position.Y - e.r.Position.Y, table.concat(an, " "))
                    end
                    frames[#frames + 1] = { t = os.clock(), s = table.concat(row, " | ") }
                    if #frames > 25 then table.remove(frames, 1) end
                end
            end
        end)
        local function hook()
            local h = hum()
            if not h then return end
            local last = h.Health
            F.conns[#F.conns + 1] = h.HealthChanged:Connect(function(v)
                local d = last - v
                last = v
                if d < h.MaxHealth * 0.05 or not cfg.farm then return end
                local now = os.clock()
                local out = { string.format("%s HIT %.0fM", os.date("%H:%M:%S"), d / 1e6) }
                local pi = 1
                for _, f in ipairs(frames) do
                    while parts[pi] and parts[pi].t <= f.t do
                        if now - parts[pi].t < 2.5 then out[#out + 1] = string.format("  %+.1f NEW %s", parts[pi].t - now, parts[pi].s) end
                        pi = pi + 1
                    end
                    out[#out + 1] = string.format("  %+.1f %s", f.t - now, f.s)
                end
                while parts[pi] do
                    if now - parts[pi].t < 2.5 then out[#out + 1] = string.format("  %+.1f NEW %s", parts[pi].t - now, parts[pi].s) end
                    pi = pi + 1
                end
                pcall(appendfile, DIR .. "/prehit.txt", table.concat(out, "\n") .. "\n\n")
            end)
        end
        hook()
        F.conns[#F.conns + 1] = LP.CharacterAdded:Connect(function() task.wait(1) hook() end)
    end
end
do -- log damage taken (with what was going on), learn from it, and back off when low
    local last = nil
    -- 11-23 lvl 260: Soulless took 2x half our HP with "in zone: none". Note every new workspace object; on a big hit
    -- with no zone, log what appeared in the 4 s before it (name, age, distance) so the next fix has the cause.
    local newObjs = {}
    F.conns[#F.conns + 1] = workspace.ChildAdded:Connect(function(o)
        if IN_LOBBY or Players:FindFirstChild(o.Name) then return end
        newObjs[#newObjs + 1] = { o = o, t = os.clock(), n = o.Name }
        if #newObjs > 40 then table.remove(newObjs, 1) end
    end)
    local function hitSources()
        local r = hrp()
        local out = {}
        for i = #newObjs, 1, -1 do
            local e = newObjs[i]
            local age = os.clock() - e.t
            if age < 4 and #out < 8 then
                local p = e.o.Parent and (e.o:IsA("BasePart") and e.o or e.o:FindFirstChildWhichIsA("BasePart", true))
                out[#out + 1] = string.format("%s %.1fs%s", e.n, age, (p and r) and string.format(" %.0f studs %.0f up", (p.Position - r.Position).Magnitude, r.Position.Y - p.Position.Y) or "")
            end
        end
        return #out > 0 and table.concat(out, ", ") or "nothing new"
    end
    -- dq_165: a hit with no zone - list every live zone we were near and how far outside it we were on each of its
    -- own axes (negative = inside on that axis), so zones whose real hit volume is bigger than their part show up
    local function nearZones()
        local r = hrp()
        if not r then return "-" end
        local out = {}
        for _, p in ipairs(liveDangers()) do
            local lp = p.CFrame:PointToObjectSpace(r.Position)
            local ox, oy, oz = math.abs(lp.X) - p.Size.X / 2, math.abs(lp.Y) - p.Size.Y / 2, math.abs(lp.Z) - p.Size.Z / 2
            if math.max(ox, oy, oz) < 45 and #out < 6 then
                out[#out + 1] = string.format("%s%s(%.0fx%.0fx%.0f %s) out x%.0f y%.0f z%.0f age %.1fs%s", (p.Parent and p.Parent ~= workspace) and (p.Parent.Name .. ".") or "", p.Name,
                    p.Size.X, p.Size.Y, p.Size.Z, p.ClassName:sub(1, 5), ox, oy, oz, os.clock() - (dangers[p] or os.clock()),
                    (ox < 0 and oy < 0 and oz < 0) and " INBOX-BUT-SHAPE-SAID-CLEAR" or "")
            end
        end
        return #out > 0 and table.concat(out, " | ") or "no zone within 45"
    end
    local function hook()
        local h = hum()
        if not h then return end
        last = h.Health
        local lastMax = h.MaxHealth
        F.conns[#F.conns + 1] = h.HealthChanged:Connect(function(v)
            -- dq_166: max hp went down (equip best swapped a piece at the end of the run) - hp follows it, that is no hit
            local mx = h.MaxHealth
            if mx < lastMax - 1 then lastMax = mx last = v return end
            lastMax = mx
            -- dq_173: after the run is cleared equip best swaps gear and hp drops by that piece's health (-905.5M every
            -- run, logged as a hit with no mob alive) - max hp changes a moment later, so the check above missed it
            if S.runCleared and last and v < last - 1 then last = v return end
            if last and v < last - 1 and cfg.farm then
                local extra = ""
                pcall(function() extra = learnHit(last - v, h.MaxHealth) end)
                local why = hitWhy()
                log(string.format("HIT -%.0f hp %.0f/%.0f | %s%s", last - v, v, h.MaxHealth, why, extra))
                if why:find("in zone: none", 1, true) and (last - v) > h.MaxHealth * 0.2 then
                    pcall(function() log("HITSRC new in the last 4 s: " .. hitSources()) end)
                    pcall(function() log("ZONEMISS " .. nearZones()) end)
                end
                -- the spot we fought the boss from just got hit: count it and pick another one now
                if S.bossCell and os.clock() - S.bossCell.t < 2 then
                    local c = S.bossCell.stat
                    c.h = (c.h or 0) + math.max(0.2, (last - v) / h.MaxHealth * 5)
                    S.bossCell.until_ = 0
                    S.bossCell.hit = true
                end
            end
            last = v
        end)
    end
    hook()
    F.conns[#F.conns + 1] = LP.CharacterAdded:Connect(function() task.wait(1) hook() end)
end

--------------------------------------------------------------------------------
-- boss spot (owner 11-21: "find where to hit the boss from where it can't hit us"):
-- 48 spots around the boss = 8 directions relative to its facing x 3 distances (6/12/17, still in swing reach)
-- x 2 heights. Each spot keeps seconds spent and hits taken there (cfg.bossCells[boss][spot], kept across runs);
-- we fight from the spot with the fewest hits per second, and move at once when a spot gets hit.
--------------------------------------------------------------------------------
local CELL_R, CELL_H = { 6, 12, 17 }, { 1 } -- one height: the learned one below
local function ddNow() local p = LP:FindFirstChild("dungPerformance") local v = p and p:FindFirstChild("damageDone") return v and v.Value or 0 end
--------------------------------------------------------------------------------
-- learned fight height (method change 11-21, from 30 min of boss-spot data: hits per minute 5.3 at +10,
-- 4.8 at +18, 2.1 at +26 - most damage boxes are only 30-50 tall - but +26 often could not reach the mob).
-- Per mob name: start at +24; 1.5 s of swinging with no damage -> 4 lower (min 6); damage for 15 s -> try 3 higher
-- (max 34). Kept across runs in cfg.mobHeight.
--------------------------------------------------------------------------------
-- capped at 24 after the #101 kick (we hovered +36 over Addonis just before it)
local HEIGHT_MAX = 24
local HEIGHT_MIN = 16
local function heightFor(name, m)
    if m then return S.hoverFor(m) end -- dq_164: tall bosses hover higher (see S.hoverFor)
    return math.max(HEIGHT_MIN, math.min(HEIGHT_MAX, tonumber(cfg.mobHeight[name]) or 20))
end
local HT = {}
local function heightTick(e)
    local now, name = os.clock(), e.m.Name
    if HT.name ~= name then HT.name, HT.t0, HT.dd0, HT.okSince = name, now, ddNow(), nil return end
    if now - HT.t0 < 1.5 then return end
    local h = heightFor(name)
    if ddNow() > HT.dd0 then
        HT.okSince = HT.okSince or now
        if now - HT.okSince > 15 and h < HEIGHT_MAX then
            cfg.mobHeight[name] = h + 3 HT.okSince = now
            log(string.format("HEIGHT %s -> %d (hitting fine, trying higher)", name, h + 3))
        end
    elseif swingOn and h > HEIGHT_MIN then
        -- 11-23 owner: stay high over their heads (Archangels learned 8-12 and killed us there); never under HEIGHT_MIN
        cfg.mobHeight[name] = math.max(HEIGHT_MIN, h - 4) HT.okSince = nil
        log(string.format("HEIGHT %s -> %d (no damage at %d)", name, cfg.mobHeight[name], h))
    end
    HT.t0, HT.dd0 = now, ddNow()
end
-- party sides (owner 11-21: "split them to different sides"): with other players in the dungeon each bot keeps
-- its own side of the mob, by its place in the sorted user ids (2 bots = opposite sides). nil when alone.
local sectorCache = { t = 0, v = nil }
local function mySector()
    if IN_LOBBY then return nil end
    if os.clock() - sectorCache.t < 2 then return sectorCache.v end
    local ids = {}
    for _, pl in ipairs(Players:GetPlayers()) do ids[#ids + 1] = pl.UserId end
    local v = nil
    if #ids > 1 then
        table.sort(ids)
        local idx = 1
        for i, id in ipairs(ids) do if id == LP.UserId then idx = i end end
        local a = (idx - 1) * 2 * math.pi / #ids
        v = Vector3.new(math.cos(a), 0, math.sin(a))
    end
    sectorCache.t, sectorCache.v = os.clock(), v
    return v
end
S.mySector = mySector
local function cellPos(root, ai, ri, hi)
    local look = flat(root.CFrame.LookVector)
    if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
    look = look.Unit
    local a = (ai - 1) * math.pi / 4
    local dir = Vector3.new(look.X * math.cos(a) - look.Z * math.sin(a), 0, look.X * math.sin(a) + look.Z * math.cos(a))
    return root.Position + dir * CELL_R[ri] + Vector3.new(0, heightFor(root.Parent and root.Parent.Name or "?", root.Parent), 0)
end
-- 11-22 Forsaken Limbo: Destined Death's Ring (44x64) + Line zones show ~3 s before the damage. Light mode dodged
-- out, but the boss spot / stand spot only checked zones in Full mode, so the next tick put us straight back in
-- (12 deaths in one run). A zone the current mode would dodge is never chosen as a place to stand.
local function hotAt(pos)
    if cfg.dodge then return dangerAt(pos) end
    if not cfg.dodgeLight then return nil end
    for _, p in ipairs(liveDangers()) do if inZone(pos, p) and zoneWorthDodging(p) then return p end end
    return nil
end
local function bossSpot(e)
    local now = os.clock()
    local name = e.m.Name
    cfg.bossCells[name] = cfg.bossCells[name] or {}
    local stats = cfg.bossCells[name]
    local cur = S.bossCell
    if cur and cur.boss == e.m and now < cur.until_ then
        local p = cur.lift or cellPos(e.r, cur.ai, cur.ri, cur.hi)
        if cur.lift and hotAt(p) then p = Vector3.new(0, -1e6, 0) end
        if cur.lift and p.Y > -1e5 then
            cur.stat.s = (cur.stat.s or 0) + (now - cur.t)
            cur.t = now
            return p
        end
        if not cur.lift and ((cfg.dodge and okSpot(p) or (not cfg.dodge and not hotAt(p))) and not crowded(p)) then
            cur.stat.s = (cur.stat.s or 0) + (now - cur.t)
            cur.t = now
            return p
        end
    end
    if cur and cur.stat then cur.stat.s = (cur.stat.s or 0) + math.max(0, now - cur.t) end
    -- a spot where 2.5 s of swinging did no damage is out of reach: mark it and leave it
    local leave = cur and cur.boss == e.m and cur.hit
    if cur and cur.boss == e.m and not cur.hit and cur.t0 and now - cur.t0 >= 2.4 and ddNow() <= (cur.dd0 or 0) then
        cur.stat.nd = (cur.stat.nd or 0) + 1
        leave = true
    end
    local best, bestScore
    for ai = 1, 8 do for ri = 1, #CELL_R do for hi = 1, #CELL_H do
        local key = ai .. "_" .. ri .. "_" .. hi
        local st = stats[key] or { s = 0, h = 0 }
        stats[key] = st
        local p = cellPos(e.r, ai, ri, hi)
        if ((cfg.dodge and okSpot(p) or (not cfg.dodge and not hotAt(p))) and not crowded(p)) and not (leave and cur.key == key) then
            local score = ((st.h or 0) + 0.5) / ((st.s or 0) + 3) + CELL_R[ri] * 0.002 + math.min(3, st.nd or 0) * 0.3
            local sec = mySector()
            if sec then
                local v = flat(p - e.r.Position)
                if v.Magnitude > 0.1 then score = score + (1 - v.Unit:Dot(sec)) * 0.4 end -- 0 on our side, 0.8 on the far side
            end
            if not bestScore or score < bestScore then best, bestScore = { ai = ai, ri = ri, hi = hi, key = key, stat = st }, score end
        end
    end end end
    if not best then
        -- every cell is in a zone the mode dodges: try the same cells lifted over the zone (closest ring first)
        for ri = 1, #CELL_R do for ai = 1, 8 do
            if not best then
                local key = ai .. "_" .. ri .. "_1"
                local q = liftOver(cellPos(e.r, ai, ri, 1), function(x) return hotAt(x) end)
                if q and S.reachOK(q, e.r) then -- dq_179: reach check (was 3D < 62); dq_164: 40 -> 62, Q / E reach that far (the flower sits on the floor: 51 under the lifted spot)
                    stats[key] = stats[key] or { s = 0, h = 0 }
                    best = { ai = ai, ri = ri, hi = 1, key = key, stat = stats[key], lift = q }
                end
            end
        end end
        if not best then return nil end
        if os.clock() - (S.liftLogT or 0) > 5 then S.liftLogT = os.clock() log(string.format("BOSS SPOT %s: all cells in zones - over them at %s", name, v3s(best.lift))) end
    end
    best.boss, best.t, best.until_ = e.m, now, now + 2.5
    best.t0, best.dd0 = now, ddNow()
    if not cur or cur.key ~= best.key then
        if os.clock() - (S.spotLogT or 0) > 10 then S.spotLogT = os.clock() else best.quiet = true end
        if not best.quiet then log(string.format("BOSS SPOT %s: dir %d dist %d up %s (hits %.1f in %.0fs there)", name, best.ai, CELL_R[best.ri], "learned", best.stat.h or 0, best.stat.s or 0)) end
    end
    S.bossCell = best
    return best.lift or cellPos(e.r, best.ai, best.ri, best.hi)
end
-- a clear spot `radius` from `root` on our side of it (same height as us); nil if none is clear
local function outside(root, radius)
    local r = hrp()
    if not r or not root then return nil end
    local away = flat(r.Position) - flat(root.Position)
    if away.Magnitude < 0.1 then away = Vector3.new(1, 0, 0) end
    local base = math.atan2(away.Z, away.X)
    for _, off in ipairs({ 0, 0.5, -0.5, 1, -1, 1.6, -1.6, 2.4, -2.4, math.pi }) do
        local a = base + off
        local p = Vector3.new(root.Position.X + math.cos(a) * radius, r.Position.Y, root.Position.Z + math.sin(a) * radius)
        if okSpot(p) then return p end
    end
    return nil
end

-- dq_192: where to fight on the yin-yang floor. On the wrong half: the nearest spot of ours (get out first). On our
-- half: the spot nearest the boss that a straight line reaches without leaving our half; it is kept while it holds.
S.yySpot = function(h, e, me, y)
    local now = os.clock()
    local function at(x, z, yy) return Vector3.new(x, yy, z) end
    local c = S.yyCur
    if c and S.yyOk(h, c, 9) and not hotAt(c) then return c end
    if S.yyLast and now - S.yyLast.t < 0.15 then return S.yyLast.p end
    local best, fallback
    local onOurs = S.yyOk(h, me, 0)
    local function pathOk(p)
        for _, t in ipairs({ 0.25, 0.5, 0.75 }) do
            if not S.yyOver(h, me.X + (p.X - me.X) * t, me.Z + (p.Z - me.Z) * t) then return false end
        end
        return true
    end
    local centre = onOurs and e.r.Position or me
    for _, yy in ipairs({ y, y + 25 }) do
        for _, rad in ipairs(onOurs and { 6, 16, 28, 42, 58, 76, 96, 118 } or { 10, 20, 32, 46, 62, 80, 100 }) do
            for k = 0, 11 do
                local a = k * math.pi / 6 + rad * 0.07
                local p = at(centre.X + math.cos(a) * rad, centre.Z + math.sin(a) * rad, yy)
                if S.yyOk(h, p, 14) and hasFloor(p, 130) and (not onOurs or pathOk(p)) then
                    if not hotAt(p) then best = p break end
                    fallback = fallback or p
                end
            end
            if best then break end
        end
        if best then break end
    end
    -- nothing reachable without crossing: stay where we are while that is still ours
    if not best and onOurs and S.yyOk(h, me, 6) then best = me end
    best = best or fallback
    S.yyCur = best
    S.yyLast = { t = now, p = best }
    return best
end
local function engage(e)
    local r = hrp()
    if not r then return end
    if S.movingUntil and os.clock() < S.movingUntil then return end -- a stepped dodge is still moving us
    -- 11-23 Ephrath test: while we hold a mechanic spot, the fight must not pull us back to the boss
    -- (13:29: we flicked between the box and the hover spot, at 4.6 s outside the box)
    if S.impSpot then
        swingOn = false hold = nil
        local r0 = hrp()
        if r0 and (r0.Position - S.impSpot).Magnitude > 3 then setCF(CFrame.new(S.impSpot)) end
        return
    end
    -- decoy check: same target for 6 s of swinging and its hp has not dropped -> skip it for 20 s
    do
        local now = os.clock()
        S.decoy = S.decoy or {}
        -- dq_164: the Lifeless Flower (lvl 275) must die inside its 20 s or both bosses heal to full - never skip it.
        -- Out of swing reach (hovering over a zone) only Q / E hit, every 5.9 s: 2.5 s without damage means nothing there.
        local keep = e.m.Name:lower():find("flower") ~= nil
        local hbx = e.m:FindFirstChild("Hitbox")
        local far = hbx and hbx:IsA("BasePart") and (r.Position.Y - (hbx.Position.Y + hbx.Size.Y / 2)) > 13
        do -- dq_190
            local so0 = S.soFor(e.m.Name)
            if so0 > 0 then far = true end
            S.keepOff = so0 > (tonumber(cfg.standOff) or 0) and { r = e.r, d = so0 } or nil
        end
        -- dq_191 Boss Rush, Electro Elemental (11-24 17:56): at half hp it is immune until its Powered Statue of
        -- Fidelity (1800T) dies. The statue takes ~75T per Q / E and our swings miss it (the game pushes us off its
        -- spot), so 2.5 s without a drop is normal there - we called it immune 5 times and went back to the boss
        -- for 20 s each time (132 s for the statue instead of ~70). When every other mob is flagged immune there
        -- is nothing better to hit: wait a full Q / E round (7 s) before giving up on this one.
        do
            local lone = true
            for _, x in ipairs(enemies()) do
                if x.m ~= e.m and not (S.decoy[x.m] and (now < S.decoy[x.m] or (S.decoyHp and S.decoyHp[x.m] and x.h.Health >= S.decoyHp[x.m] - x.h.MaxHealth * 0.002))) then lone = false break end
            end
            if lone then far = true end
        end
        if S.dTarget ~= e.m then S.dTarget, S.dT0, S.dHp = e.m, now, e.h.Health
        elseif keep then S.dT0, S.dHp = now, e.h.Health
        elseif swingOn and now - S.dT0 > (far and 7 or 2.5) then -- 11-21 owner: 6 s was slow to leave an immune boss
            -- 11-21 lvl 100 Haste Tower: 80 s on it, 73M -> 68.9M (others alive); "hardly drops" counts as immune too:
            -- under 0.2% of max hp in 2.5 s of swinging (tower: 0.07%; a 320M boss solo still loses ~0.5%)
            if S.dHp - e.h.Health < e.h.MaxHealth * 0.002 then
                S.decoy[e.m] = now + 20
                S.decoyHp = S.decoyHp or setmetatable({}, { __mode = "k" })
                S.decoyHp[e.m] = e.h.Health
                log(string.format("IMMUNE %s hp %.0f did not drop in 2.5 s of hitting - hitting the others first", e.m.Name, e.h.Health))
                S.dTarget = nil
                return
            end
            S.dT0, S.dHp = now, e.h.Health
        elseif not swingOn and now - S.dT0 > 8 and S.dHp - e.h.Health < e.h.MaxHealth * 0.002 then
            -- 11-21 lvl 100: both bots stood still 26 s far from the Haste Tower (its spot red, no clear spot near it),
            -- never in reach, so the check above never ran. 8 s on a target we cannot reach: skip it for 8 s.
            S.decoy[e.m] = now + 8
            log(string.format("UNREACHABLE %s for 8 s - hitting the others first", e.m.Name))
            S.dTarget = nil
            return
        end
    end
    -- safe zone up: we stay in it (dodgeCheck holds us there); hit whatever is in reach from inside
    if safeZone() then
        hold = nil
        curTarget = e.r
        swingOn = (r.Position - e.r.Position).Magnitude < 30
        if swingOn and cfg.autoQE then
            -- (dq_167: Q / E / R are cast by the autocast loop)
        trySwap()
        end
        S.target = "in the safe zone"
        return
    end
    -- a boss: fight from the spot around it that gets hit least (red zone on us is still handled by dodgeCheck)
    if e.h.MaxHealth >= 8000 and cfg.move ~= "Walk" then
        curTarget = e.r
        do -- dq_192: yin-yang floor up - fight from our own half only
            local h = S.yy()
            if h then
                if S.yyArena ~= h.Parent then
                    S.yyArena = h.Parent
                    S.yyCur = nil
                    log("YIN-YANG floor up: we are " .. tostring(LP:GetAttribute("Alignment")) .. " - staying over the " .. h.Name)
                end
                if not S.yyOk(h, r.Position, 0) and os.clock() - (S.yyWarn or 0) > 2 then
                    S.yyWarn = os.clock()
                    log("YIN-YANG over the wrong half at " .. v3s(r.Position) .. " - moving out")
                end
                local q = S.yySpot(h, e, r.Position, e.r.Position.Y + heightFor(e.m.Name, e.m))
                if q then
                    if (r.Position - q).Magnitude > 3 then moveTo(q, e.r.Position) end
                    hold = { cf = CFrame.lookAt(q, e.r.Position), t = os.clock() }
                    swingOn = (q - e.r.Position).Magnitude < 40
                    S.bossCell = nil
                    S.target = "yin-yang: on our half"
                    return
                end
            end
        end
        -- dq_189: No Hit attempts 16:11-16:45 all died in the pizza: the dodge took us out to a dark slice, engage flew
        -- us 200 studs back to a boss cell near the pizza centre (lit / about to be lit), and so on until a wave caught us.
        -- While the pizza is up we wait in a dark slice at the boss's distance from the centre (at least 100), as near to
        -- the boss as a clear arc allows; Q / E still fire when it is in reach. Boss outside the pizza = fight as usual.
        do
            local pz = workspace:FindFirstChild("EmberwingPizza")
            local sl = pz and pz:FindFirstChild("Slices")
            local pc = sl and S.pizzaCentreOf and S.pizzaCentreOf(sl)
            if pc then
                local toBoss = Vector3.new(e.r.Position.X - pc.X, 0, e.r.Position.Z - pc.Z)
                if toBoss.Magnitude < 450 then
                    local mine = Vector3.new(r.Position.X - pc.X, 0, r.Position.Z - pc.Z)
                    local y = e.r.Position.Y + heightFor(e.m.Name, e.m)
                    if not (mine.Magnitude >= 95 and okSpot(r.Position)) then
                        local R = math.clamp(toBoss.Magnitude, 100, 380)
                        local a0 = (toBoss.Magnitude > 25) and math.atan2(toBoss.Z, toBoss.X) or math.atan2(mine.Z, mine.X)
                        if mine.Magnitude >= 95 then a0 = math.atan2(mine.Z, mine.X) R = math.clamp(mine.Magnitude, 100, 380) end
                        local q = S.pizzaSpot(pc, a0, R, y) or S.pizzaSpot(pc, a0, R + 30, y)
                        if q and (r.Position - q).Magnitude > 3 then moveTo(q, e.r.Position) end
                    end
                    local r2 = hrp()
                    if r2 and (Vector3.new(e.r.Position.X, 0, e.r.Position.Z) - Vector3.new(r2.Position.X, 0, r2.Position.Z)).Magnitude > 1 then hold = { cf = CFrame.lookAt(r2.Position, Vector3.new(e.r.Position.X, r2.Position.Y, e.r.Position.Z)), t = os.clock() } end
                    swingOn = r2 ~= nil and (r2.Position - e.r.Position).Magnitude < 40
                    S.target = "pizza: waiting in a dark slice"
                    return
                end
            end
        end
        local p = bossSpot(e)
        if not p then p = S.edgeSpot(e.r.Position + Vector3.new(0, heightFor(e.m.Name, e.m), 0)) end -- dq_169
        -- owner 11-23 lvl 260: "our skills are wide - just cast them": stand outside the mobs' reach (standOff studs) and
        -- let Q/E/R do the damage. 0 = off (old spot in swing reach).
        local so = S.soFor(e.m.Name)
        local keep = so > (tonumber(cfg.standOff) or 0)
        if keep and not p then p = e.r.Position end -- every boss cell red: the keep-off circle is still ours
        if p and so > 0 then
            -- keep-off boss: come from where we are (not through the boss), low so Q / E still reach it
            local dv = keep and (flat(r.Position) - flat(e.r.Position)) or (flat(p) - flat(e.r.Position))
            if dv.Magnitude < 0.1 then dv = flat(r.Position) - flat(e.r.Position) end
            if dv.Magnitude < 0.1 then dv = Vector3.new(0, 0, 1) end
            local hgt = heightFor(e.m.Name, e.m)
            if keep then hgt = math.min(hgt, 12) end
            local q = e.r.Position + dv.Unit * so + Vector3.new(0, hgt, 0)
            if keep then
                if hotAt(q) or not hasFloor(q, 130) then
                    local a0 = math.atan2(dv.Z, dv.X)
                    for i = 1, 11 do
                        local a = a0 + math.ceil(i / 2) * (i % 2 == 0 and -1 or 1) * math.pi / 6
                        local c = e.r.Position + Vector3.new(math.cos(a) * so, hgt, math.sin(a) * so)
                        if not hotAt(c) and hasFloor(c, 130) then q = c break end
                    end
                end
                p = q
                S.bossCell = nil
            elseif not hotAt(q) then p = q end
        end
        if p then
            if DEV and (r.Position - p).Magnitude > 200 then log(string.format("TRAVEL %.0f studs to %s (%s)", (r.Position - p).Magnitude, v3s(p), e.m.Name)) end
            if (r.Position - p).Magnitude > 3 then moveTo(p, e.r.Position) end
            hold = { cf = CFrame.lookAt(p, e.r.Position), t = os.clock() }
            swingOn = (p - e.r.Position).Magnitude < 40 + so
            -- dq_164: over a zone we are out of swing reach on purpose - that must not teach the height learner "no damage"
            if so <= 0 and not (S.bossCell and S.bossCell.lift) then heightTick(e) end
            if swingOn and cfg.autoQE then
                -- (dq_167: Q / E / R are cast by the autocast loop)
        trySwap()
            end
            return
        end
        S.bossCell = nil -- every spot is red right now: fall through to the normal side-step
    else
        S.bossCell = nil
    end
    -- a learned wind-up is playing near us: wait outside its reach, then come back
    if S.avoid then
        if os.clock() > S.avoid.untilT or not S.avoid.root.Parent then S.avoid = nil else
            local ar = S.avoid.root
            if (flat(r.Position) - flat(ar.Position)).Magnitude < S.avoid.radius then
                hold = nil
                local p = outside(ar, S.avoid.radius)
                if p then moveTo(p, ar.Position) end
            end
            -- still hit the target if it is not the one winding up and we are in reach
            swingOn = (e.r ~= ar) and (flat(hrp().Position) - flat(e.r.Position)).Magnitude < 14
            return
        end
    end
    local tp = e.r.Position
    local dir = flat(r.Position) - flat(tp)
    if dir.Magnitude < 0.1 then dir = Vector3.new(0, 0, 1) end
    -- hover > 0 = hover on; how high is learned per mob (heightFor)
    local hover = (cfg.move ~= "Walk") and (tonumber(cfg.hover) or 0) > 0 and heightFor(e.m.Name, e.m) or 0
    local stand
    if hover > 0 then
        -- just behind the mob's centre and above its head; the swing hitbox (16 x 50 x 22) reaches down
        stand = tp + dir.Unit * 2 + Vector3.new(0, hover, 0)
        local sec = mySector()
        if sec then stand = tp + sec * 4 + Vector3.new(0, hover, 0) end
        local so = S.soFor(e.m.Name)
        if so > 0 then stand = tp + dir.Unit * so + Vector3.new(0, hover, 0) end
        -- another player (bot) already over this mob: take the other side, further out
        if crowded(stand) then
            for _, deg in ipairs({ 180, 90, 270, 45, 135, 225, 315 }) do
                local a = math.rad(deg)
                local u = dir.Unit
                local rd = Vector3.new(u.X * math.cos(a) - u.Z * math.sin(a), 0, u.X * math.sin(a) + u.Z * math.cos(a))
                local p = tp + rd * 9 + Vector3.new(0, hover, 0)
                if not crowded(p) then stand = p break end
            end
        end
    else
        stand = tp + dir.Unit * (tonumber(cfg.standDist) or 4)
        stand = Vector3.new(stand.X, tp.Y, stand.Z)
    end
    curTarget = e.r
    stand = S.edgeSpot(stand) or stand -- dq_169: never inside a carry trigger's keep-out zone
    -- the usual spot is in a red zone: take a clear spot beside the mob (on the ground) and keep hitting
    local side = false
    if hotAt(stand) then
        local s = sideSpot(r.Position)
        if s then stand, side = s, true else
            -- no clear spot at the mob (held beams): never step into the red (11-21: it kept teleporting back into a beam).
            -- Take the closest clear spot a bit further out, or stay where we are; swing whenever in reach.
            local alt
            for _, rad in ipairs({ 14, 18, 22 }) do
                for k = 0, 15 do
                    local a = k * math.pi / 8
                    local p = Vector3.new(tp.X + math.cos(a) * rad, tp.Y + hover, tp.Z + math.sin(a) * rad)
                    if okSpot(p) and (not alt or (p - r.Position).Magnitude < (alt - r.Position).Magnitude) then alt = p end
                end
                if alt then break end
            end
            hold = nil
            if alt and (r.Position - alt).Magnitude > 3 then moveTo(alt, tp) end
            r = hrp()
            if r and alt then hold = { cf = CFrame.lookAt(alt, tp), t = os.clock() } end
            swingOn = r ~= nil and (r.Position - tp).Magnitude < 30
            return
        end
    end
    if (r.Position - stand).Magnitude > 3 then moveTo(stand, tp) end
    r = hrp()
    if r and hover > 0 then
        -- face down at the mob: the swing hitbox is built in front of us, so pointing at the mob reaches it
        hold = { cf = CFrame.lookAt(stand, tp), t = os.clock() }
    elseif r and cfg.move ~= "Walk" then
        setCF(faceCF(r.Position, tp))
    end
    local d = r and (flat(r.Position) - flat(tp)).Magnitude or 99
    local so2 = S.soFor(e.m.Name)
    swingOn = d < 14 + so2
    if hover > 0 and so2 <= 0 then heightTick(e) end
    if swingOn and cfg.autoQE then
        -- (dq_167: Q / E / R are cast by the autocast loop)
        trySwap()
    end
end

-- dq_164: Q / E / R whenever they are ready and a mob is in their reach - also while we dodge, move or hover over a
-- zone. Measured lvl 275 (dq/dmg.txt 11-24): one Q+E cast = 578T on every mob within 60-85 studs = 64 % of all boss
-- damage, cooldown 5.9 s, but the casts came 6-10 s apart because they only ran inside engage() with swingOn.
-- Also logs the flower mechanic (appears -> killed / ran out) so each run shows whether the bosses were healed.
go("autocast", function()
    -- dev PC only: dq/autorun.lua (study recorders) runs once per dungeon, so a study needs no rebuild
    if DEV and not IN_LOBBY then pcall(function() if isfile(DIR .. "/autorun.lua") then local f = loadstring(readfile(DIR .. "/autorun.lua")) if f then log("AUTORUN " .. tostring(f())) end end end) end
    local fl = nil -- {m, t0, hp}
    local rayT, rayN = os.clock(), 0
    while F.alive do
        task.wait(0.1)
        if os.clock() - rayT > 30 then
            local n = (S.exactRays or 0) - rayN
            if n > 0 and not IN_LOBBY then log(string.format("EXACT %d shape rays in 30 s (%.0f a second)", n, n / 30)) end
            rayT, rayN = os.clock(), S.exactRays or 0
            if S.dodgeBy and next(S.dodgeBy) then
                local t = {}
                for k, v in pairs(S.dodgeBy) do t[#t + 1] = { k = k, v = v } end
                table.sort(t, function(a, b) return a.v > b.v end)
                local o = {}
                for i = 1, math.min(6, #t) do o[#o + 1] = t[i].k .. " " .. t[i].v end
                log("DODGE CAUSES last 30 s: " .. table.concat(o, ", "))
                S.dodgeBy = {}
            end
        end
        if cfg.farm and not IN_LOBBY and not S.limitBusy then
            local r, h = hrp(), hum()
            local list = enemies()
            if r and h and h.Health > 0 and cfg.autoQE then
                local near = curTarget and curTarget.Parent and (curTarget.Position - r.Position).Magnitude < math.max(62, S.soFor(curTarget.Parent.Name) + 14)
                if not near then
                    for _, e in ipairs(list) do if (e.r.Position - r.Position).Magnitude < 55 then near = true break end end
                end
                if near then
                    -- dev study hook: getgenv().DQ_STAGGER = seconds to hold E after Q, so the damage of each spell
                    -- shows on its own in dq/dmg.txt
                    local stag = DEV and getgenv and tonumber(getgenv().DQ_STAGGER)
                    if castReady("Q") then cast("Q") S.lastQ = os.clock() end
                    if castReady("E") and (not stag or os.clock() - (S.lastQ or 0) > stag) then cast("E") end
                    if castReady("R") then cast("R") end
                end
            end
            local seen = nil
            for _, e in ipairs(list) do if e.m.Name:lower():find("flower") then seen = e break end end
            if seen and not (fl and fl.m == seen.m) then
                fl = { m = seen.m, t0 = os.clock(), hp = seen.h.Health }
                S.flowers = (S.flowers or 0) + 1
                log(string.format("FLOWER %d up (%.0fT) - 20 s to kill it or the bosses heal to full", S.flowers, seen.h.Health / 1e12))
            elseif seen and fl then
                fl.hp = seen.h.Health
            elseif fl and not seen then
                local life = os.clock() - fl.t0
                local killed = fl.hp < 2e14 or life < 20.8
                if killed then S.flowerKills = (S.flowerKills or 0) + 1 end
                log(string.format("FLOWER %d %s after %.1f s (last seen %.0fT) - killed %d of %d", S.flowers or 0, killed and "KILLED" or "RAN OUT -> bosses healed", life, fl.hp / 1e12, S.flowerKills or 0, S.flowers or 0))
                fl = nil
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- run bookkeeping
--------------------------------------------------------------------------------
local coins0 = nil
local function coins() local d = LP:FindFirstChild("data") return d and num(d:FindFirstChild("coins")) or 0 end
local sessionStart = os.clock()
local sessionCoins0 = coins()

-- why did a run end up in the lobby? (owner 11-21: "Retry goes back to the lobby") - log the game's own
-- run-end signals: a failed run, a host change, votes, and the server sending us back
do
    for _, n in ipairs({ "DungeonFail", "TransferHost", "voteRemote", "ReturnLobby", "ForceSpectate", "DisplayLoading" }) do
        local rem = R(n)
        if rem and rem:IsA("RemoteEvent") then
            F.conns[#F.conns + 1] = rem.OnClientEvent:Connect(function(...)
                local parts = {}
                for i, v in ipairs({ ... }) do if i <= 4 then parts[#parts + 1] = tostring(v):sub(1, 40) end end
                log("RUN-END signal " .. n .. "(" .. table.concat(parts, ", ") .. ")")
            end)
        end
    end
end

-- 11-22 portal floors: the game shows 3 portal cards (Portals gui) to the HOST only, and its own card button
-- just fires DisplayPortals:FireServer(slot 1-3). We note the offered names from the same event and pick the
-- safest card. Evasion (HP set to 1, hardcore) / Wager / Dominion / Overkill are last because the character
-- already dies a lot at 185+.
do
    local PORTAL_RANK = { Treasure = 1, Fortune = 2, Haste = 3, Quickfire = 4, Duplication = 5, Combination = 6,
        Echo = 7, Regular = 8, Gathering = 9, Endurance = 10, Speed = 11, Chance = 12, Elite = 13, Balance = 14,
        Equilibrium = 15, Strength = 16, Collosus = 17, Overkill = 18, Dominion = 19, Wager = 20, Evasion = 21 }
    local dp = R("DisplayPortals")
    if dp then
        local offered, pickToken = {}, 0
        F.conns[#F.conns + 1] = dp.OnClientEvent:Connect(function(slot, name, kind)
            local ds = workspace:FindFirstChild("DungeonSettings")
            local host = ds and ds:FindFirstChild("Host")
            if not (host and host.Value == LP.UserId) then return end
            if kind == "Display" and type(slot) == "number" then
                offered[slot] = tostring(name)
            elseif kind == "Reveal" then
                pickToken = pickToken + 1
                local my = pickToken
                task.delay(2, function()
                    if my ~= pickToken or not cfg.autoPortal then return end
                    local best, bestR
                    for s = 1, 3 do
                        local n = offered[s]
                        if n then
                            local r = PORTAL_RANK[n] or 12
                            if not bestR or r < bestR then best, bestR = s, r end
                        end
                    end
                    if not best then best = 1 end
                    log(string.format("PORTAL offered %s | %s | %s -> picked %d (%s)", offered[1] or "?", offered[2] or "?", offered[3] or "?", best, offered[best] or "?"))
                    pcall(function() dp:FireServer(best) end)
                    offered = {}
                end)
            end
        end)
    end
end

do
    local sr = R("SendRewards")
    if sr then
        F.conns[#F.conns + 1] = sr.OnClientEvent:Connect(function(a, b)
            S.runCleared = true
            local secs = S.runStart and (os.clock() - S.runStart) or 0
            S.lastRun = secs
            cfg.totalRuns = cfg.totalRuns + 1
            cfg.totalSeconds = cfg.totalSeconds + secs
            if secs > 0 and (cfg.bestRun == 0 or secs < cfg.bestRun) then cfg.bestRun = secs end
            saveCfg()
            log(string.format("RUN DONE %.0fs rewards %s %s | pullbacks %d deaths %d", secs, tostring(a), tostring(b), S.pullBacks, S.deaths))
            S.runStart = nil
            if not S.diedThisRun then cfg.deathStreak = 0 saveCfg() end
        end)
    end
end
pcall(function()
    F.conns[#F.conns + 1] = game:GetService("GuiService").ErrorMessageChanged:Connect(function(m)
        if m and m ~= "" then log("ROBLOX ERROR / KICK: " .. m) end
    end)
end)

local function watchDeath()
    local h = hum()
    if h then
        F.conns[#F.conns + 1] = h.Died:Connect(function()
            if S.runCleared then return end -- the game drops us after the last boss; not a real death
            S.deaths = S.deaths + 1 S.diedThisRun = true S.deathT = os.clock()
            S.runDeaths = (S.runDeaths or 0) + 1
            cfg.deathStreak = (tonumber(cfg.deathStreak) or 0) + 1 saveCfg()
            -- owner 11-21: don't jump to the lobby after a death (party runs go on, the friends are still fighting).
            -- After a respawn we fight again; the 3rd death in one run = stay out of the fight until the run ends
            -- (a respawn run once died 14 times in a row by flying straight back to the boss).
            if S.dumpFlight then pcall(S.dumpFlight, "DIED") end -- dq_184 dev
            pcall(function() -- dq_190
                local me, t = hrp(), curTarget
                if cfg.mode ~= "Boss Rush" or not (me and t and t.Parent) then return end
                -- (dq_191: the "keep off any boss we died near" rule is out - its first use was Pan Ku, whose
                -- yin-yang floor kills at any distance; only bosses with a measured reach are in S.bossKeep)
                local name, d = t.Parent.Name, (flat(me.Position) - flat(t.Position)).Magnitude
                log(string.format("BOSS RUSH death at %s: %.0f studs from it (flat), %.0f over its root%s", name, d, me.Position.Y - t.Position.Y, S.bossKeep[name] and (", keep-off " .. S.bossKeep[name]) or ""))
            end)
            log(string.format("DIED (%d this run, streak %d)%s", S.runDeaths, cfg.deathStreak,
                ""))
            -- 11-23 Neon Calamity: Mue no Ikari one-shot us every 12 s. Auto best, solo: 6 deaths = this dungeon is too hard,
            -- count it as a failed run and leave now (not after the 8 min stuck timer)
            -- 11-23: 6 cut off a Neon Expert run at the last boss (a clear had 5 deaths); 10 = a run that will not finish
            -- 11-23 First Sanctuary: 10 cut the run while boss Zuriel was still losing hp -> from 10 on, leave only when no
            -- enemy lost hp in the last 60 s; 20 deaths = leave anyway
            local nd = S.runDeaths or 0
            local moving = os.clock() - (S.progressAt or 0) < 60
            if nd >= 10 and nd < 20 and moving then log("death " .. nd .. " but enemies still losing hp - fighting on") end
            if nd >= 10 and (not moving or nd >= 20) and not S.deathLeft and cfg.autoBest and cfg.autoJoin and #Players:GetPlayers() <= 1 and S.noteRun then
                S.deathLeft = true
                pcall(S.noteRun, false, nd .. " deaths")
                log(nd .. " deaths -> ReturnLobby")
                local rl = R("ReturnLobby") if rl then rl:FireServer() end
                -- 11-23: ReturnLobby was ignored for 2.5 min while we kept dying -> our own teleport after 15 s
                task.delay(15, function() if F.alive and not IN_LOBBY then log("still here 15 s after ReturnLobby -> teleport") toLobby() end end)
            end
        end)
    end
end
watchDeath()
F.conns[#F.conns + 1] = LP.CharacterAdded:Connect(function() S.deathT = os.clock() task.wait(1) watchDeath() end)

--------------------------------------------------------------------------------
-- main farm loop
--------------------------------------------------------------------------------
local lobbyArrive = os.clock()
local endSeen = nil
local function dungeonTick()
    -- start screen
    local sb = pgui("mainGui.startDungeon")
    -- 11-22 lvl 180: after Start the same ImageLabel stays visible as a banner with no TextButton
    -- (dungeonStarted = true) and the bot sat at the start, never fighting. Only a screen with a button counts.
    local ds = workspace:FindFirstChild("dungeonStarted")
    if shown(sb) and sb:FindFirstChild("TextButton") and not (ds and ds:IsA("BoolValue") and ds.Value) then
        S.phase = "start"
        local btn = sb:FindFirstChild("TextButton")
        if btn and press(btn) then
            log("pressed Start")
            S.runStart = os.clock() reached = 0 coins0 = coins() S.endJobsDone = false S.routePick = nil S.autoNextLogged = nil
            if S.runKey then cfg.pendingRun = S.runKey() saveCfg() end
            task.wait(2)
        end
        return
    end
    -- end screen
    local cs = pgui("CompletionScreen.CompletionBorder")
    if shown(cs) then
        swingOn = false
        S.phase = "end"
        if not endSeen and S.noteRun then
            local f = workspace:FindFirstChild("dungeonFailed")
            pcall(S.noteRun, not (f and f:IsA("BoolValue") and f.Value), "fail screen")
        end
        endSeen = endSeen or os.clock()
        -- skill points / equip best / sell / quests also work in the dungeon: do them here, Retry skips the lobby
        if not S.endJobsDone and S.jobs then
            S.endJobsDone = true
            S.jobsRunning = true
            go("endjobs", function() S.jobs() S.jobsRunning = false end)
            task.delay(20, function() S.jobsRunning = false end)
        end
        if os.clock() - endSeen > 4 and not S.jobsRunning then
            -- the screen has two copies of Retry / Return (CompletionMain and a smaller panel): take a shown one
            -- after a death never Retry the same dungeon (11-21: Retry looped Sunken Fortress twice into death)
            local want = (cfg.retry and not S.needSell) and "Retry" or "Return"
            -- auto best: a better (or the failing one's replacement) dungeon is open -> lobby, PlaySolo picks it
            if want == "Retry" and S.autoNext then
                local ok, nk = pcall(S.autoNext)
                if ok and nk then
                    want = "Return"
                    if not S.autoNextLogged then S.autoNextLogged = true log("AUTO BEST next " .. nk .. " (now " .. S.runKey() .. ") -> Return") end
                end
            end
            local btn, seen = nil, {}
            local root = pgui("CompletionScreen")
            for _, d in ipairs(root and root:GetDescendants() or {}) do
                if d:IsA("TextButton") and d.Parent and (d.Parent.Name == "Retry" or d.Parent.Name == "Return") then
                    seen[#seen + 1] = d.Parent:GetFullName():gsub("^.-PlayerGui%.", "") .. (shown(d) and "(shown)" or "")
                    if d.Parent.Name == want and (not btn or shown(d)) then btn = d end
                end
            end
            if btn and press(btn) then log("pressed " .. want .. " " .. (shown(btn) and "shown" or "hidden")) else
                log("no end button (" .. table.concat(seen, ", ") .. "); ReturnLobby")
                local rl = R("ReturnLobby") if rl then rl:FireServer() end
            end
            endSeen = os.clock() + 6 -- wait before pressing again
        end
        return
    end
    endSeen = nil
    if not S.runStart then S.runStart = os.clock() S.progressAt = os.clock() S.hpSeen = setmetatable({}, { __mode = "k" }) end
    -- stuck guard = no enemy lost hp for stuckTimeout s (11-23: a plain 480 s run clock cut off every Neon Chaos run
    -- while Master Ryuken was still taking damage); a hard cap of 4x stops a run that drags on regardless
    if os.clock() - (S.hpCheckAt or 0) > 5 then
        S.hpCheckAt = os.clock()
        S.hpSeen = S.hpSeen or setmetatable({}, { __mode = "k" })
        for _, e in ipairs(enemies()) do
            local was = S.hpSeen[e.m]
            if was and e.h.Health < was - 1 then S.progressAt = os.clock() end
            S.hpSeen[e.m] = e.h.Health
        end
    end
    local lim = tonumber(cfg.stuckTimeout) or 480
    if os.clock() - (S.progressAt or S.runStart) > lim or os.clock() - S.runStart > lim * 4 then
        log("STUCK " .. math.floor(os.clock() - S.runStart) .. "s run, " .. math.floor(os.clock() - (S.progressAt or S.runStart)) .. "s without damage -> ReturnLobby")
        if S.noteRun then pcall(S.noteRun, false, "stuck") end
        task.delay(20, function() if F.alive and not IN_LOBBY then log("still here 20 s after ReturnLobby -> teleport") toLobby() end end)
        local rl = R("ReturnLobby") if rl then rl:FireServer() end
        S.runStart = os.clock() S.progressAt = os.clock()
        return
    end
    local h = hum()
    if not h or h.Health <= 0 then
        swingOn = false S.phase = "dead"
        S.deadSince = S.deadSince or os.clock()
        local dt = os.clock() - S.deadSince
        -- only when playing alone: a party keeps going (spectate / revive), so we wait with it
        local solo = #Players:GetPlayers() <= 1
        if solo and dt > 30 and not S.deadReturn then S.deadReturn = true log("dead 30 s (solo) -> ReturnLobby") local rl = R("ReturnLobby") if rl then rl:FireServer() end end
        if solo and dt > 60 and not S.deadTp then S.deadTp = true log("still dead 60 s (solo) -> teleport to lobby") toLobby() end
        return
    end
    S.deadSince, S.deadReturn, S.deadTp = nil, nil, nil
    -- after a death this run is over: no going back to the boss, wait for the lobby teleport
    local e = pickTarget()
    if e then
        S.phase = "fight"
        S.fought = true
        S.target = string.format("%s %.0f/%.0f", e.m.Name, e.h.Health, e.h.MaxHealth)
        -- DEV: every target change with all live mobs (owner 11-21: lvl 80 "hits the fake one, too slow")
        if DEV and S.lastTgt ~= e.m then
            S.lastTgt = e.m
            local all = {}
            for _, x in ipairs(enemies()) do
                all[#all + 1] = string.format("%s %.1fM/%.1fM%s%s", x.m.Name, x.h.Health / 1e6, x.h.MaxHealth / 1e6,
                    x.m:GetAttribute("Boss") == true and " BOSS" or "", (S.decoy and S.decoy[x.m] and os.clock() < S.decoy[x.m]) and " IMMUNE" or "")
            end
            log("TARGET " .. S.target .. " | all: " .. table.concat(all, ", "))
        end
        engage(e)
    else
        swingOn = false
        local p, i, n = nextWaypoint()
        if p and hotAt(p) then
            S.phase = "wait"
            S.target = "red zone on the path"
        elseif p then
            S.phase = "move"
            S.target = string.format("waypoint %d/%d", i, n)
            if DEV and hrp() and (hrp().Position - p).Magnitude > 100 then log(string.format("TRAVEL %.0f studs to route waypoint %d/%d at %s", (hrp().Position - p).Magnitude, i, n, v3s(p))) end
            moveTo(p)
        else
            S.phase = "wait"
            S.target = "no mob, no route"
            S.noMobSince = S.noMobSince or os.clock()
            -- 11-22 level 160 (Ethereal Farlands): rooms are joined by pads (workspace Teleports: TeleportOne..Four
            -- -> RecieverOne..Four); the next room's mobs only appear after standing on a pad. Room clear ->
            -- go to the nearest pad not used yet this run and touch it.
            local tpm = workspace:FindFirstChild("Teleports")
            local r = hrp()
            -- only once the run has started and we have fought here (10:23 test: a fresh run went to TeleportThree before Start)
            local started = workspace:FindFirstChild("dungeonStarted")
            if started and started:IsA("BoolValue") and not started.Value then tpm = nil end
            if not S.fought then tpm = nil end
            if tpm and r and os.clock() - S.noMobSince > 2 and os.clock() > (S.padNext or 0) then
                S.padUsed = S.padUsed or {}
                -- pads in number order (10:19 clean run: One then Two then the last boss). "Nearest" was wrong:
                -- 10:40 the nearest after room 1 was TeleportFour, behind a barrier -> pulled back 26 times -> S02 kick
                local best, bd
                for _, nm in ipairs({ "TeleportOne", "TeleportTwo", "TeleportThree", "TeleportFour" }) do
                    local pad = tpm:FindFirstChild(nm)
                    if pad and pad:IsA("BasePart") and not S.padUsed[pad] then
                        best, bd = pad, (pad.Position - r.Position).Magnitude
                        break
                    end
                end
                if best then
                    S.padUsed[best] = true
                    S.padNext = os.clock() + 4
                    log(string.format("PAD room clear -> %s (%.0f studs)", best.Name, bd))
                    moveTo(best.Position + Vector3.new(0, 3, 0))
                    pcall(function()
                        local rr = hrp()
                        if firetouchinterest and rr then firetouchinterest(rr, best, 0) task.wait(0.1) firetouchinterest(rr, best, 1) end
                    end)
                    -- pulled back off the pad (a used pad behind a barrier, 10:24 test) -> leave pads alone for a while
                    task.wait(0.6)
                    local rr = hrp()
                    -- a working pad sends us to its receiver far away; still near the pad = blocked / pulled back
                    if rr and (rr.Position - best.Position).Magnitude < 150 then
                        log("PAD " .. best.Name .. " did not send us anywhere (blocked) - pads paused 20 s")
                        S.padNext = os.clock() + 20
                    end
                    S.noMobSince = os.clock()
                    return
                end
            end
            -- 11-23 First Sanctuary (StreamingEnabled): after boss Zuriel remainingEnemies = 7 but none sent to us - the
            -- next room (boss Yaldabaoth) is too far to stream. Ask the game to stream each room marker in turn,
            -- nearest first; once enemies show up the fight loop goes to them.
            local remV = workspace:FindFirstChild("Enemies") and workspace.Enemies:FindFirstChild("remainingEnemies")
            local remN = remV and remV:IsA("ValueBase") and tonumber(remV.Value) or 0
            if remN > 0 and r and os.clock() - S.noMobSince > 3 and os.clock() > (S.exploreNext or 0) then
                S.exploreNext = os.clock() + 3
                S.explored = S.explored or {}
                -- candidates: DungeonMap models (roomInformation holds no parts on the client). 11-23 test: streaming
                -- around "circle2" at -60,-135,-1485 brought in all 7 (Archangels + Yaldabaoth room). Arena-like names
                -- first, nearest first; then every other model, nearest first.
                local best, bd, bp
                -- 11-23 15:00: each run spent ~50 s here (6 + 10 + 3 tries, the same spots every run). Spots that found
                -- enemies before on this map come first (cfg.exploreHits[map] = {"x,y,z", ...}), nearest first.
                local mapName = workspace:FindFirstChild("DungeonSettings") and workspace.DungeonSettings:FindFirstChild("SessionName")
                mapName = mapName and tostring(mapName.Value) or "?"
                cfg.exploreHits = type(cfg.exploreHits) == "table" and cfg.exploreHits or {}
                S.exploredSpot = S.exploredSpot or {}
                for _, s in ipairs(cfg.exploreHits[mapName] or {}) do
                    if not S.exploredSpot[s] then
                        local x, y, z = s:match("^(-?%d+),(-?%d+),(-?%d+)$")
                        local p = x and Vector3.new(tonumber(x), tonumber(y), tonumber(z))
                        if p then
                            local d = (p - r.Position).Magnitude
                            if d > 150 and (not bd or d < bd) then best, bd, bp = s, d, p end
                        end
                    end
                end
                if best then
                    S.exploredSpot[best] = true
                    log(string.format("EXPLORE %d enemies left -> known spot %s (%.0f studs)", remN, best, bd))
                    pcall(function() LP:RequestStreamAroundAsync(bp, 5) end)
                    local n = #enemies()
                    if n > 0 then log("EXPLORE found " .. n .. " enemies at the known spot") S.noMobSince = nil return end
                    S.noMobSince = os.clock() - 3
                    return
                end
                for pass = 1, 2 do
                    for _, c in ipairs((workspace:FindFirstChild("DungeonMap") or workspace):GetChildren()) do
                        if not S.explored[c] and (c:IsA("Model") or c:IsA("BasePart")) then
                            local nm = c.Name:lower()
                            local arena = nm:find("circle") or nm:find("boss") or nm:find("arena") or nm:find("entrance")
                            if pass == 2 or arena then
                                local ok, p = pcall(function() return c:IsA("BasePart") and c.Position or c:GetPivot().Position end)
                                if ok and p then
                                    local d = (p - r.Position).Magnitude
                                    if d > 150 and (not bd or d < bd) then best, bd, bp = c, d, p end
                                end
                            end
                        end
                    end
                    if best then break end
                end
                if best then
                    S.explored[best] = true
                    log(string.format("EXPLORE %d enemies left, none here -> stream %s at %.0f,%.0f,%.0f (%.0f studs)", remN, best.Name, bp.X, bp.Y, bp.Z, bd))
                    pcall(function() LP:RequestStreamAroundAsync(bp, 5) end)
                    local n = #enemies()
                    if n > 0 then
                        log("EXPLORE found " .. n .. " enemies near " .. best.Name)
                        local key = string.format("%d,%d,%d", math.floor(bp.X + 0.5), math.floor(bp.Y + 0.5), math.floor(bp.Z + 0.5))
                        local list = cfg.exploreHits[mapName] or {}
                        local have = false for _, s in ipairs(list) do if s == key then have = true end end
                        if not have and #list < 12 then list[#list + 1] = key cfg.exploreHits[mapName] = list saveCfg() log("EXPLORE remembered " .. key .. " for " .. mapName) end
                        S.noMobSince = nil return
                    end
                    S.noMobSince = os.clock() - 3 -- keep exploring; leave only once every marker was tried
                    return
                end
            end
            if os.clock() - S.noMobSince > 25 then
                -- 11-23 First Sanctuary: after boss Zuriel nothing to fight, ReturnLobby ignored 7 times (2.5 min).
                -- Log once what the map holds (to learn the way on), and after 2 ignored ReturnLobby teleport out.
                S.noMobTries = (S.noMobTries or 0) + 1
                if S.noMobTries == 1 then pcall(function()
                    local o = {}
                    local en = workspace:FindFirstChild("Enemies")
                    for _, m in ipairs(en and en:GetChildren() or {}) do
                        local h = m:FindFirstChildOfClass("Humanoid")
                        o[#o + 1] = m.Name .. (h and string.format("(%.0fM/%.0fM)", h.Health / 1e6, h.MaxHealth / 1e6) or "")
                    end
                    local flags = {}
                    for _, n in ipairs({ "dungeonStarted", "dungeonFinished", "dungeonFailed" }) do
                        local v = workspace:FindFirstChild(n) flags[#flags + 1] = n .. "=" .. tostring(v and v.Value)
                    end
                    local pads = {}
                    local tp = workspace:FindFirstChild("Teleports")
                    for _, p in ipairs(tp and tp:GetChildren() or {}) do pads[#pads + 1] = p.Name .. (S.padUsed and S.padUsed[p] and "(used)" or "") end
                    local prompts = 0
                    for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("ProximityPrompt") and d.Enabled then prompts = prompts + 1 end end
                    local r = hrp()
                    log("NOMOB map " .. tostring(S.runKey and S.runKey()) .. " | enemies: " .. (#o > 0 and table.concat(o, ", ") or "none") ..
                        " | " .. table.concat(flags, " ") .. " | pads: " .. (#pads > 0 and table.concat(pads, ",") or "none") ..
                        " | prompts " .. prompts .. " | me " .. (r and string.format("%.0f,%.0f,%.0f", r.Position.X, r.Position.Y, r.Position.Z) or "-"))
                end) end
                if S.noMobTries >= 3 then
                    log("no mob and no route, ReturnLobby ignored twice -> teleport to lobby")
                    S.noMobTries = 0
                    toLobby()
                else
                    log("no mob and no route for 25 s -> ReturnLobby")
                    local rl = R("ReturnLobby") if rl then rl:FireServer() end
                end
                S.noMobSince = nil
            end
            return
        end
    end
    S.noMobSince = nil S.noMobTries = 0
end

--------------------------------------------------------------------------------
-- auto best: highest difficulty the level opens, on maps we have a walking route for
-- (level needs from ReplicatedStorage.Modules.DungeonInfo, read 2026-11-21)
--------------------------------------------------------------------------------
local MAP_REQ = {
    { map = "Raided Village", req = { Normal = 1, Expert = 5, Chaos = 10, Calamity = 15 } },
    { map = "Sunken Fortress", req = { Normal = 20, Expert = 25, Chaos = 30, Calamity = 35 } },
    { map = "Cursed Marshes", req = { Normal = 40, Expert = 45, Chaos = 50, Calamity = 55 } },
    { map = "Ragnar\195\182k's Descent", req = { Normal = 60, Expert = 65, Chaos = 70, Calamity = 75 } },
    { map = "Thundering Peaks", req = { Normal = 80, Expert = 85, Chaos = 90, Calamity = 95 } },
    { map = "Fallen Paradise", req = { Normal = 100, Expert = 105, Chaos = 110, Calamity = 115 } },
    { map = "Eternal Domain", req = { Normal = 120, Expert = 125, Chaos = 130, Calamity = 135 } },
    { map = "Stardust Citadel", req = { Normal = 140, Expert = 145, Chaos = 150, Calamity = 155 } },
    { map = "Ethereal Farlands", req = { Normal = 160, Expert = 165, Chaos = 170, Calamity = 175 } },
    { map = "Hellbound Sanctum", req = { Normal = 180, Expert = 185, Chaos = 190, Calamity = 195 } },
    { map = "Forsaken Limbo", req = { Normal = 200, Expert = 205, Chaos = 210, Calamity = 215 } },
    { map = "Neon District", req = { Normal = 220, Expert = 225, Chaos = 230, Calamity = 235 } },
    { map = "The First Sanctuary", req = { Normal = 240, Expert = 245, Chaos = 250, Calamity = 255 } },
    { map = "Subliminal Dreamscape", req = { Normal = 260, Expert = 265, Chaos = 270, Calamity = 275 } },
}
local DIFFS = { "Normal", "Expert", "Chaos", "Calamity" }
local function myLevel() local d = LP:FindFirstChild("data") return d and num(d:FindFirstChild("level")) or 1 end

S.refused = {} -- map|diff the server would not start in this lobby (PlaySolo sent, no teleport)
-- 11-23 owner: "auto best should climb through every dungeon so I can leave it overnight".
-- Fight-only runs finish without a route (lvl 180-220 all night), so every open map counts now.
-- A dungeon that fails twice in a row (STUCK or the game's fail screen) is skipped for 4 h -> the next one down.
cfg.keyFail = type(cfg.keyFail) == "table" and cfg.keyFail or {}
cfg.keyBlock = type(cfg.keyBlock) == "table" and cfg.keyBlock or {}
local function runKey()
    local ds = workspace:FindFirstChild("DungeonSettings")
    local sn, df = ds and ds:FindFirstChild("SessionName"), ds and ds:FindFirstChild("Difficulty")
    if sn and df and tostring(sn.Value) ~= "" and tostring(df.Value) ~= "" then return tostring(sn.Value) .. "|" .. tostring(df.Value) end
    return curKey()
end
local function noteRun(ok, why, key)
    local k = key or runKey()
    cfg.pendingRun = ""
    if ok then
        cfg.keyFail[k] = 0 saveCfg()
        return
    end
    cfg.keyFail[k] = (cfg.keyFail[k] or 0) + 1
    log(string.format("RUN FAILED %s (%s) - %d in a row", k, why, cfg.keyFail[k]))
    if cfg.keyFail[k] >= 2 then
        cfg.keyFail[k] = 0
        cfg.keyBlock[k] = os.time() + 4 * 3600
        log("AUTO BEST: " .. k .. " failed twice - skipped for 4 h")
    end
    saveCfg()
end
local function bestDungeon()
    local lvl = myLevel()
    local list = {}
    -- MAP_REQ runs from easy to hard, so the last open one is the best
    for _, m in ipairs(MAP_REQ) do
        for _, d in ipairs(DIFFS) do
            local key = m.map .. "|" .. d
            if lvl >= m.req[d] and not S.refused[key] and os.time() >= (tonumber(cfg.keyBlock[key]) or 0) then
                list[#list + 1] = { map = m.map, diff = d, need = m.req[d] }
            end
        end
    end
    if #list == 0 then return cfg.map, cfg.difficulty, "no map open" end
    local pick = list[#list]
    return pick.map, pick.diff, string.format("lvl %d, needs %d", lvl, pick.need)
end

-- other modes: Map = the mode, Difficulty = a tier name (ReplicatedStorage.Modules.DungeonInfo)
local MODE_TIERS = {
    ["Elemental Raids"] = { { "One", 15 }, { "Two", 35 }, { "Three", 55 }, { "Four", 75 }, { "Five", 95 }, { "Six", 115 }, { "Seven", 135 },
        { "Eight", 155 }, { "Nine", 175 }, { "Ten", 195 }, { "Eleven", 215 }, { "Twelve", 235 }, { "Thirteen", 255 }, { "Fourteen", 275 } },
    ["Infinite Tower"] = { { "Destruction", 70 }, { "Tempest", 90 }, { "Blooming", 110 }, { "Eternity", 130 }, { "Dimensions", 150 }, { "Embers", 170 },
        { "Oblivion", 190 }, { "Limbo", 210 }, { "Overdrive", 230 }, { "Dawnbreak", 250 }, { "Sentience", 270 } },
    ["Boss Rush"] = { { "Fallen Paradise", 110 }, { "Eternal Domain", 130 }, { "Stardust Citadel", 150 }, { "Ethereal Farlands", 170 },
        { "Hellbound Sanctum", 190 }, { "Forsaken Limbo", 210 }, { "Neon District", 230 }, { "The First Sanctuary", 250 }, { "Subliminal Dreamscape", 270 } },
}
local MODES = { "Dungeons", "Elemental Raids", "Infinite Tower", "Boss Rush" }
-- auto best inside a mode: highest tier the level opens (a mode run without a route only fights what it sees)
local function bestTier(mode)
    local lvl, pick = myLevel(), nil
    for _, t in ipairs(MODE_TIERS[mode]) do if lvl >= t[2] and not S.refused[mode .. "|" .. t[1]] then pick = t[1] end end
    return pick or MODE_TIERS[mode][1][1]
end
local function playing(manual)
    local mode = cfg.mode or "Dungeons"
    if mode ~= "Dungeons" and MODE_TIERS[mode] then
        if cfg.autoBest and not manual then return mode, bestTier(mode) end
        return mode, cfg.modeTier[mode] or MODE_TIERS[mode][1][1]
    end
    if cfg.autoBest and not manual then local m, d = bestDungeon() return m, d end
    -- the server would not start the hand-picked difficulty (RV Calamity was refused all afternoon): one step easier
    local d = cfg.difficulty
    local idx = 1
    for i, x in ipairs(DIFFS) do if x == d then idx = i end end
    while idx > 1 and S.refused[cfg.map .. "|" .. DIFFS[idx]] do idx = idx - 1 end
    return cfg.map, DIFFS[idx]
end
-- 11-23 18:25 kicked "idle 20 minutes" while waiting in the lobby with Auto join off: answer the idle signal
-- with one virtual click (the usual anti-AFK), so a paused hub never gets the account kicked.
pcall(function()
    local vu = game:GetService("VirtualUser")
    F.conns[#F.conns + 1] = LP.Idled:Connect(function()
        pcall(function() vu:CaptureController() vu:ClickButton2(Vector2.new()) end)
        log("IDLE signal - sent one click so Roblox does not kick for idling")
    end)
end)
S.runKey = runKey
-- 11-23 First Sanctuary: the game sent us to the lobby twice mid-run (9.5 and 13 min in, no fail screen).
-- Log the dungeon room counters whenever they change, to see whether a timer or a lives count ends the run.
if not IN_LOBBY then go("roominfo", function()
    local last, lastT = "", nil
    while F.alive do
        local ri = workspace:FindFirstChild("roomInformation")
        if ri then
            local t = {}
            for _, n in ipairs({ "currentRoom", "timeLeft", "playersLeft" }) do
                local v = ri:FindFirstChild(n) t[#t + 1] = n .. "=" .. tostring(v and v.Value)
            end
            local cur = table.concat(t, " ")
            local tl = ri:FindFirstChild("timeLeft")
            local key = cur:gsub("timeLeft=%-?%d+", "") -- log a timer tick only every 60 s
            local tv = tl and tonumber(tl.Value)
            if key ~= last or (tv and tv ~= lastT and tv % 60 == 0) then log("ROOMINFO " .. cur) last = key end
            lastT = tv
        end
        task.wait(1)
    end
end) end
S.noteRun = noteRun
-- 11-23: 3 deaths in Neon Calamity sent us to the lobby with no fail screen. A run we started and never saw end
-- (cfg.pendingRun, set at Start) counts as a fail when the script wakes up in the lobby.
if IN_LOBBY and type(cfg.pendingRun) == "string" and cfg.pendingRun ~= "" then
    noteRun(false, "back in the lobby without a finish", cfg.pendingRun)
elseif not IN_LOBBY then
    cfg.pendingRun = runKey() saveCfg()
end
-- end screen: the dungeon auto best wants now, if it is not the one we just played (solo + Auto join only:
-- the lobby has to start the next one, and a party run stays with the friends)
S.autoNext = function()
    if not (cfg.autoBest and cfg.autoJoin) or (cfg.mode or "Dungeons") ~= "Dungeons" or #Players:GetPlayers() > 1 then return nil end
    local m, d = bestDungeon()
    local k = m .. "|" .. d
    if k ~= runKey() then return k end
    return nil
end

--------------------------------------------------------------------------------
-- sell: getInventory(userId)[type] = items {GUID, itemType, itemRarity, itemLocked, equipped, equippedE, equippedQ}
-- sellItems({weapons = {GUID...}, armors = ..., ...}) - same table the game's sell screen sends
--------------------------------------------------------------------------------
local RARITIES = { "common", "uncommon", "rare", "epic", "legendary", "heirloom" }
local TYPES = { "weapons", "armors", "helmets", "legs", "spells", "rings", "sigils" }
local sellInfo = { matches = "-", last = "-" }
local function sellList()
    local gi = R("getInventory")
    if not gi then return nil, 0 end
    local inv = ask("getInventory", LP.UserId)
    local list, n = { weapons = {}, armors = {}, helmets = {}, legs = {}, spells = {}, rings = {}, sigils = {} }, 0
    for _, ty in ipairs(TYPES) do
        if cfg.sellTypes[ty] and type(inv) == "table" and type(inv[ty]) == "table" then
            for _, it in pairs(inv[ty]) do
                local keep = it.itemLocked or it.equipped == true or it.equippedE == true or it.equippedQ == true
                local rar = tostring(it.itemRarity or ""):lower()
                if not keep and cfg.sellRarity[rar] and it.GUID then
                    local key = list[it.itemType] and it.itemType or ty
                    table.insert(list[key], it.GUID)
                    n = n + 1
                end
            end
        end
    end
    return list, n
end
local function countSell() local _, n = sellList() sellInfo.matches = tostring(n) .. " items" return n end
-- inventory snapshot: item count + which GUIDs are worn (to check that equip / sell really did something)
local function invSnap()
    local inv = R("getInventory") and ask("getInventory", LP.UserId)
    local n, eq = 0, {}
    for _, ty in ipairs(TYPES) do
        if type(inv) == "table" and type(inv[ty]) == "table" then
            for _, it in pairs(inv[ty]) do
                n = n + 1
                if it.equipped == true or it.equippedE == true or it.equippedQ == true then eq[#eq + 1] = tostring(it.GUID) end
            end
        end
    end
    table.sort(eq)
    return { n = n, eq = table.concat(eq, ","), eqn = #eq, inv = inv }
end
local function sellNow()
    local list, n = sellList()
    if not list or n == 0 then sellInfo.matches = "0 items" log("SELL nothing to sell") return end
    local before = invSnap()
    local ok = ask("sellItems", list)
    task.wait(1)
    local after = invSnap()
    -- one big call came back nil in a dungeon (11-21 13:33, 63 items): if nothing went, try one item type at a time
    if after.n >= before.n then
        log(string.format("SELL all at once -> %s, items %d -> %d: trying type by type", tostring(ok), before.n, after.n))
        for _, ty in ipairs(TYPES) do
            if #list[ty] > 0 then
                local one = { weapons = {}, armors = {}, helmets = {}, legs = {}, spells = {}, rings = {}, sigils = {} }
                one[ty] = list[ty]
                local r = ask("sellItems", one)
                log("SELL " .. ty .. " x" .. #list[ty] .. " -> " .. tostring(r))
                task.wait(0.5)
            end
        end
        task.wait(1)
        after = invSnap()
    end
    sellInfo.last = os.date("%H:%M") .. string.format(" · %d -> %d items", before.n, after.n) .. (IN_LOBBY and "" or " (dungeon)")
    sellInfo.matches = "0 items"
    log(string.format("SELL %d picked, inventory %d -> %d (%s)", n, before.n, after.n, IN_LOBBY and "lobby" or "dungeon"))
end
local function equipBest()
    if not R("EquipBest") then return end
    local before = invSnap()
    R("EquipBest"):FireServer()
    task.wait(1.5)
    local after = invSnap()
    log(string.format("EQUIP BEST (%s): worn %d items, %s", IN_LOBBY and "lobby" or "dungeon", after.eqn, before.eq == after.eq and "no change" or "CHANGED"))
end

--------------------------------------------------------------------------------
-- lobby jobs, once per lobby visit before the next run
--------------------------------------------------------------------------------
local function lobbyJobs()
    local data = LP:FindFirstChild("data")
    if cfg.autoSP and data then
        local free = num(data:FindFirstChild("freeSP"))
        if free > 0 then R("addSkillPoints"):FireServer(cfg.spStat, free) log("SKILL +" .. free .. " " .. cfg.spStat) task.wait(1) end
    end
    if cfg.autoEquipBest then pcall(equipBest) end
    if cfg.autoSell then
        if IN_LOBBY then pcall(sellNow) task.wait(1) S.needSell = false
        else
            -- the server only sells in the lobby: when the bag is this full, this run ends in the lobby
            local ok, snap = pcall(invSnap)
            if ok and snap.n >= (tonumber(cfg.sellAt) or 80) then
                S.needSell = true
                log(string.format("BAG %d items (sell at %d) - this run goes to the lobby to sell", snap.n, tonumber(cfg.sellAt) or 80))
            end
        end
    end
    if cfg.autoDaily and R("ClaimDaily") then
        -- the same call as walking into the daily rewards zone; only when a day has passed (lastDaily = unix time)
        local last = tonumber(LP:GetAttribute("lastDaily")) or 0
        if last == 0 or os.time() - last >= 86400 then
            R("ClaimDaily"):FireServer()
            task.wait(2)
            log("DAILY claim, lastDaily " .. last .. " -> " .. tostring(LP:GetAttribute("lastDaily")))
        end
    end
    if cfg.autoQuests and R("getPlayerQuests") and R("CompleteQuest") then
        local q = ask("getPlayerQuests")
        local cur = type(q) == "table" and q.NewCurrentQuests
        for _, kind in ipairs({ "Daily", "Weekly", "Battlepass" }) do
            local set = cur and cur[kind] and cur[kind].Quests
            if type(set) == "table" then
                for key, v in pairs(set) do
                    if type(v) == "table" and not v.Claimed and tonumber(v.Amount) and tonumber(v.Progress) and v.Progress >= v.Amount then
                        local ok = ask("CompleteQuest", kind, key)
                        log("QUEST " .. kind .. " " .. tostring(v.Description or key) .. " -> " .. tostring(ok))
                        task.wait(0.5)
                    end
                end
            end
        end
    end
    -- upgrade worn gear one level at a time (coins); the server refuses when we cannot pay or it is maxed.
    -- Same rule as the game's upgrade screen for which stat goes up. Spells / sigils cannot be upgraded.
    if cfg.autoUpgrade then
        pcall(function()
            local inv = ask("getInventory", LP.UserId)
            local done = 0
            for _, ty in ipairs({ "weapons", "armors", "helmets", "legs", "rings" }) do if cfg.upgSlots[ty] then
                for _, it in pairs(type(inv) == "table" and inv[ty] or {}) do
                    if it.equipped == true and (tonumber(it.currentUpgrade) or 0) < (tonumber(it.maxUpgrades) or 0) then
                        local stat = (tostring(it.itemName):find("Guardian") and "health") or ((tonumber(it.spellPower) or 0) < (tonumber(it.physicalPower) or 0) and "physical" or "spell")
                        for _ = 1, math.max(1, tonumber(cfg.upgLevels) or 5) do
                            local r = ask("upgradeItem", it.GUID, 1, stat, ty)
                            if r == false or r == nil then break end
                            done = done + 1
                            task.wait(0.3)
                        end
                    end
                end
            end end
            log("UPGRADE worn gear: " .. done .. " level(s) bought" .. (IN_LOBBY and "" or " (in a dungeon)"))
        end)
    end
    -- free rewards the game hands out (same calls as their claim buttons; the server says no when nothing is due).
    -- Lobby only, once per lobby visit. Nothing here costs anything (Robux / gem buys are never called).
    if cfg.autoFree and IN_LOBBY then
        local got = {}
        local function try(name, fn) local ok, r = pcall(fn) if ok and r ~= nil and r ~= false then got[#got + 1] = name end end
        try("offline", function() R("ClaimOffline"):FireServer() end)
        try("streak", function() R("ClaimStreakReward"):FireServer() end)
        try("enemy index", function() return ask("ClaimIndexEnemy") end)
        try("rng index", function() return ask("ClaimIndexRNG") end)
        for n = 1, 12 do try("playtime " .. n, function() return ask("ClaimPlaytimeReward", n) end) end
        pcall(function()
            local rewards = require(RS.Modules.LevelRewards)
            local lvl = myLevel()
            for key in pairs(rewards) do
                if tonumber(key) and tonumber(key) <= lvl then R("ClaimLevelMilestone"):FireServer(key) task.wait(0.2) end
            end
        end)
        log("FREE rewards tried (offline, streak, index, playtime 1-12, level milestones)" .. (#got > 0 and (" - yes: " .. table.concat(got, ", ")) or ""))
    end
end

-- game settings the owner can switch from the window (sent only when the game's value differs)
local function gameSetting(remoteKey, settingName, want)
    pcall(function()
        local v = LP:FindFirstChild("Settings") and LP.Settings:FindFirstChild(settingName)
        if v and v.Value ~= want then
            R("ChangeSetting"):FireServer(remoteKey)
            log("GAME SETTING " .. settingName .. " -> " .. tostring(want))
        end
    end)
end
local function applyGameSettings()
    gameSetting("lowGraphicsMode", "LowGraphicsMode", cfg.lowGfx == true)
end
task.delay(5, applyGameSettings)

-- sell NPC: some dungeons get a seller (Workspace.SellNPC, sent with SendSellNPC); selling works next to it.
-- With Auto sell on and the bag at the limit: go to it, sell with the filter, carry on.
go("sellnpc", function()
    while F.alive do
        task.wait(20)
        if not IN_LOBBY and cfg.farm and cfg.autoSell and not S.limitBusy then
            local npc = workspace:FindFirstChild("SellNPC")
            local root = npc and (npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart", true))
            if root then
                local ok, snap = pcall(invSnap)
                if ok and snap.n >= (tonumber(cfg.sellAt) or 80) then
                    log("SELL NPC found - selling " .. snap.n .. " items there")
                    S.limitBusy = true
                    pcall(function()
                        moveTo(root.Position + Vector3.new(0, 3, 4), root.Position)
                        task.wait(0.8)
                        sellNow()
                        S.needSell = false
                    end)
                    S.limitBusy = false
                end
            end
        end
    end
end)

S.jobs = lobbyJobs -- the end screen in the dungeon calls it too
local jobsDone = false
-- the lobby opens on the "Your Characters" menu (PlayerGui.LoadingScreen); nothing starts until a slot is picked.
-- Same call as its Play button: SelectCharacterSlot(slot). "Couldn't load. Please rejoin." -> teleport to the lobby again.
local menuTries, menuLast = 0, os.clock() -- start the clock at load: with 0 the first press fired at once (11-23 loop)
local function menuStep()
    local ls = pgui("LoadingScreen")
    if not ls or not ls.Enabled then return false end
    -- the LoadingScreen gui can stay enabled after the character is in; only its Menu frame being shown counts
    -- (dq_49 kept "picking a slot" while already standing in the lobby - each pick moves us to another server)
    local menu = ls:FindFirstChild("Menu")
    if not menu or not shown(menu) then return false end
    local c = LP.Character
    if c and c:FindFirstChild("HumanoidRootPart") and LP:GetAttribute("loaded") == true and not shown(menu) then return false end
    S.phase = "menu"
    local failed = false
    pcall(function()
        for _, d in ipairs(ls:GetDescendants()) do
            if d:IsA("TextLabel") and d.Text:find("Please rejoin") and shown(d) then failed = true end
        end
    end)
    if failed then
        S.target = "menu says rejoin"
        if os.clock() - menuLast > 20 then menuLast = os.clock() log("MENU could not load the character -> rejoin lobby") toLobby() end
        return true
    end
    -- the game's own Play button fires ONCE and then shows LOADING... (the server teleports us). Firing again while that
    -- teleport runs looks like what hung the loading screen (11-21 13:58: two picks 15 s apart, then stuck). Once, then 60 s.
    if LP:GetAttribute("IsTeleporting") == true then S.target = "teleporting..." return true end
    if os.clock() - menuLast > (menuTries == 0 and 40 or 45) then
        menuLast = os.clock()
        menuTries = menuTries + 1
        -- 11-23 night: pressing PLAY first looped 03:15-06:51 (100+ rejoins, never got in); SelectCharacterSlot got
        -- Exitta in on the first try at 02:50 (its 02:00 failure was the alt account with no character at all).
        -- So: remote first, the PLAY button only on the second try.
        local played = false
        if menuTries >= 2 then
            for _, d in ipairs(menu:GetDescendants()) do
                if d:IsA("TextLabel") and d.Text == "PLAY" and shown(d) then
                    local b = d:IsA("GuiButton") and d or d:FindFirstAncestorWhichIsA("GuiButton") or d.Parent:FindFirstChildWhichIsA("GuiButton")
                    if b and press(b) then played = true log("MENU pressed PLAY (try " .. menuTries .. ")") break end
                end
            end
        end
        if not played then
            local slot = tonumber(LP:GetAttribute("ActiveCharacterSlot")) or 1
            local r = R("SelectCharacterSlot")
            if r then r:FireServer(slot) log("MENU pick character slot " .. slot .. " (try " .. menuTries .. ")") end
        end
        if menuTries >= 2 then menuTries = 0 log("MENU still up after 2 tries -> rejoin lobby") toLobby() end
    end
    S.target = "character menu"
    return true
end

local function lobbyTick()
    S.phase = "lobby"
    if menuStep() then lobbyArrive = os.clock() return end
    if os.clock() - lobbyArrive < (tonumber(cfg.lobbyWait) or 8) then return end
    if not jobsDone then
        jobsDone = true
        S.target = "lobby jobs"
        local ok, err = pcall(lobbyJobs)
        if not ok then log("ERR lobby jobs: " .. tostring(err)) end
    end
    if not cfg.autoJoin then S.target = "Auto join is off" return end
    local ps = R("PlaySolo")
    if not ps then S.target = "no PlaySolo remote" return end
    local map, diff = playing(cfg.recordRoute and not cfg.farm)
    local key = map .. "|" .. diff
    -- PlaySolo that never teleports (11-21: Calamity hardcore after a hardcore death, 10 tries):
    -- 2 tries -> again without hardcore, 2 more -> skip this dungeon for this lobby visit
    S.tries = S.tries or {}
    S.tries[key] = (S.tries[key] or 0) + 1
    local hc = cfg.hardcore and S.tries[key] <= 2
    if S.tries[key] > 4 then
        S.refused[key] = true
        if S.tries[key] == 5 then log("PlaySolo " .. key .. " refused 4 times - skipping it" .. (cfg.autoBest and "" or " (manual pick: change map/difficulty)")) end
        -- (no more farm OFF here: a hand-picked dungeon the server keeps refusing steps down one difficulty, see playing())
        return
    end
    -- 11-23: the game's DungeonHandler sends LevelRequirement = DungeonInfo DifficultyReqs[Difficulty]; with 1 the server
    -- ignored every PlaySolo above Raided Village (all refused since 11-22 14:53)
    local need = 1
    for _, m in ipairs(MAP_REQ) do if m.map == map and m.req[diff] then need = m.req[diff] end end
    -- dq_163: raids / tower / boss rush are not in MAP_REQ (Elemental Raids Fourteen sent 1 and was refused 4 times, 11-24);
    -- the game button reads DungeonInfo.dungeonInfo[Map].DifficultyReqs[Difficulty] for every mode - same here
    pcall(function() local r = require(RS.Modules.DungeonInfo).dungeonInfo[map].DifficultyReqs[diff] if tonumber(r) then need = tonumber(r) end end)
    -- dq_185 owner 11-24: "one hit = lost" = the game's No Hit mode (the NoHit switch on the dungeon screen, solo only).
    -- "set noHit true" sends it with PlaySolo.
    local t = { Map = map, Calamity = false, Hardcore = hc, NoHit = cfg.noHit == true,
        Difficulty = diff, LevelRequirement = need, Tier = 1, Private = false, Easter = false }
    log("PlaySolo " .. map .. " " .. diff .. (hc and " hardcore" or "") .. (cfg.noHit == true and " NO HIT" or "") .. " (try " .. S.tries[key] .. ")")
    -- why does the server sometimes not start it? note our state + listen for any answer (once per lobby)
    pcall(function()
        local a = {}
        for k, v in pairs(LP:GetAttributes()) do
            local kl = k:lower()
            if kl:find("party") or kl:find("lobby") or kl:find("teleport") or kl:find("dungeon") or kl:find("loaded") or kl:find("slot") or kl:find("trad") then a[#a + 1] = k .. "=" .. tostring(v) end
        end
        local pg = LP:FindFirstChild("PlayerGui")
        for _, d in ipairs(pg and pg:GetDescendants() or {}) do
            if d.Name == "Party" and d:GetAttribute("ActiveParty") ~= nil then
                a[#a + 1] = "PartyGui.ActiveParty=" .. tostring(d:GetAttribute("ActiveParty")) .. " DungeonName=" .. tostring(d:GetAttribute("DungeonName"))
            end
        end
        log("  state: " .. table.concat(a, " "))
        if DEV and not S.lobbyEars then
            S.lobbyEars = true
            for _, rem in ipairs(RS:GetChildren()) do
                if rem:IsA("RemoteEvent") and rem.Name ~= "ByteNetReliable" and rem.Name ~= "ByteNetUnreliable" then
                    F.conns[#F.conns + 1] = rem.OnClientEvent:Connect(function(...)
                        if os.clock() - (S.earT or 0) > 30 then return end
                        local parts = {}
                        for i, v in ipairs({ ... }) do if i <= 4 then parts[#parts + 1] = tostring(v):sub(1, 60) end end
                        log("  server -> " .. rem.Name .. "(" .. table.concat(parts, ", ") .. ")")
                    end)
                end
            end
        end
        S.earT = os.clock()
    end)
    cfg.lastPlayed = key cfg.lastPlayedAt = os.time() saveCfg()
    S.target = map .. " · " .. diff
    ps:FireServer(t)
    lobbyArrive = os.clock() + 20 -- teleport takes a while; try again later if nothing happened
end

-- recording: the owner plays; we only take the start (PlaySolo with the picked dungeon) and the path
go("record", function()
    while F.alive do
        if cfg.recordRoute and not cfg.farm and not IN_LOBBY then
            if not rec.pts then rec.pts, rec.key = {}, curKey() log("RECORD started " .. rec.key .. " - play the run by hand") end
            recPoint()
        end
        task.wait(0.5)
    end
end)
do
    local sr = R("SendRewards")
    if sr then F.conns[#F.conns + 1] = sr.OnClientEvent:Connect(function() if rec.pts then recSave("run cleared") end end) end
end

--------------------------------------------------------------------------------
-- safety (shared msafe module, also for the aa / gpo / nexus hubs): kicks with
-- "moseeri dungeon: please rejoin for safety [S01..S04]" when stuck twice, pulled back a lot, staff joins, or errors pile up.
-- First stuck: back to a fresh lobby server.
--------------------------------------------------------------------------------
-- any kick / disconnect (game anti-cheat #101 too): keep the last 150 log lines in dq/lastkick.txt on every device,
-- so a friend can send the file (11-21: a friend dropped with #101 only in party runs, and friends keep no log file)
S.moves = {}
go("movesampler", function()
    while F.alive do
        task.wait(0.25)
        local r = hrp()
        if r and not IN_LOBBY then
            local m = S.moves
            m[#m + 1] = { t = os.clock(), p = r.Position }
            if #m > 60 then table.remove(m, 1) end
        end
    end
end)
local function moveStats()
    local m, maxStep, sum10, n = S.moves, 0, 0, 0
    for i = 2, #m do
        local d = (m[i].p - m[i - 1].p).Magnitude
        if d > maxStep then maxStep = d end
        if os.clock() - m[i].t <= 10 then sum10 = sum10 + d n = n + 1 end
    end
    local fast = 0
    for i = 2, #m do if (m[i].p - m[i - 1].p).Magnitude > 12 then fast = fast + 1 end end
    return string.format("moved %.0f studs in last 10 s, biggest 0.25 s step %.0f, steps over 12 studs %d/%d", sum10, maxStep, fast, #m - 1)
end
S.moveStats = moveStats
local function onKick(msg)
        if not msg or msg == "" then return end
        -- teleports between places also fire this: not a kick
        if msg == "DisconnectClientInitiated" or msg:find("Teleport") then return end
        local L = F.logLines
        local out = { os.date("%Y-%m-%d %H:%M:%S") .. " " .. VERSION .. " place " .. tostring(game.PlaceId) .. " players " .. #Players:GetPlayers(), "message: " .. msg }
        for i = math.max(1, #L - 149), #L do out[#out + 1] = L[i] end
        pcall(function() if not isfolder(DIR) then makefolder(DIR) end writefile(DIR .. "/lastkick.txt", table.concat(out, "\n")) end)
        -- owner 11-23: "if it drops again, get back into a map by itself". Rejoin the lobby after 10 s (the loader runs
        -- again there and Auto join starts the next dungeon). Not after a staff kick [S03] or the game's anti-cheat #101,
        -- and at most 3 rejoins an hour (a kick loop stays on the kick screen).
        if not S.rejoinSet and not msg:find("S03") and not msg:find("101") and not msg:find("TEST") then
            S.rejoinSet = true
            local now, keep = os.time(), {}
            for _, t in ipairs(type(cfg.rejoins) == "table" and cfg.rejoins or {}) do if now - (tonumber(t) or 0) < 3600 then keep[#keep + 1] = t end end
            if #keep < 3 then
                keep[#keep + 1] = now
                cfg.rejoins = keep saveCfg()
                log("REJOIN in 10 s (" .. #keep .. " this hour)")
                task.delay(10, function() pcall(function() TeleportService:Teleport(LOBBY_PLACE, LP) end) end)
            else
                log("REJOIN skipped: already 3 this hour")
            end
        end
        -- and post it to the owner's Discord data channel like AA does (owner 11-21: "no need for friends to open files").
        -- One "DQKICK" message per kick; the AA stats bot reads only AASTAT / AAITEM / AABR lines, so it skips these.
        if S.kickSent then return end
        S.kickSent = true
        task.spawn(function()
            local url = S.shareUrl
            if not url then
                local ok, u = pcall(function() return game:HttpGet("https://raw.githubusercontent.com/moseeri01/blueheater2/main/share_url.txt") end)
                url = ok and type(u) == "string" and u:match("https://[%w%./_%-]+") or nil
            end
            local req = (syn and syn.request) or (http and http.request) or request or http_request
            if not url or type(req) ~= "function" then return end
            local tail = {}
            for i = #L, 1, -1 do
                local s = L[i]
                if not (s:find(" PREDODGE ") or s:find(" NEWOBJ ") or s:find(" TARGET ")) then table.insert(tail, 1, s:sub(1, 110)) end
                if #tail >= 25 then break end
            end
            local h = hum()
            local head = "DQKICK " .. VERSION .. " id " .. tostring(LP.UserId % 100000) .. " | " .. msg:sub(1, 120)
                .. " | place " .. tostring(game.PlaceId) .. " players " .. #Players:GetPlayers()
                .. "\nsettings: move " .. tostring(cfg.move) .. " step " .. tostring(cfg.tpStep) .. " wait " .. tostring(cfg.tpWait)
                .. " hover " .. tostring(cfg.hover) .. " swing " .. tostring(cfg.swingRate) .. " dodge " .. (cfg.dodge and "Full" or (cfg.dodgeLight and "Light" or "Off"))
                .. " stand " .. tostring(cfg.standDist) .. " speed " .. tostring(h and h.WalkSpeed)
                .. "\n" .. moveStats()
            -- keep the newest lines (the old cut dropped the last 13 s before the kick)
            local text = table.concat(tail, "\n")
            local room = 1880 - #head
            if #text > room then text = text:sub(#text - room + 1) end
            local body = head .. "\n```\n" .. text .. "\n```"
            local ok, res = pcall(req, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode({ content = body }) })
            log("KICK report to Discord: " .. (ok and type(res) == "table" and tostring(res.StatusCode) or ("failed " .. tostring(res))))
        end)
end
S.onKick = onKick
-- evidence for the 2-bot kick (11-21): can two players physically push each other here? (every field on its own pcall)
if DEV then task.spawn(function()
    task.wait(3)
    local function q(fn) local ok, v = pcall(fn) return ok and tostring(v) or ("err " .. tostring(v):sub(1, 60)) end
    local PS = game:GetService("PhysicsService")
    local r = hrp()
    local g = q(function() return r.CollisionGroup end)
    local parts = {}
    for _, d in ipairs(r and r.Parent and r.Parent:GetChildren() or {}) do
        if d:IsA("BasePart") then parts[#parts + 1] = d.Name .. "=" .. q(function() return d.CanCollide end) .. "/" .. q(function() return d.CollisionGroup end) end
    end
    log("COLLCHECK group " .. g .. " self " .. q(function() return PS:CollisionGroupsAreCollidable(g, g) end) .. " | parts " .. table.concat(parts, " "))
end) end -- dev command "kicktest" posts a test report
pcall(function() F.conns[#F.conns + 1] = game:GetService("GuiService").ErrorMessageChanged:Connect(onKick) end)
-- fetch the Discord address early: after a kick the game may be too far gone to fetch it
task.spawn(function()
    local ok, u = pcall(function() return game:HttpGet("https://raw.githubusercontent.com/moseeri01/blueheater2/main/share_url.txt") end)
    S.shareUrl = ok and type(u) == "string" and u:match("https://[%w%./_%-]+") or nil
end)
local Safe = MSafe.start({ name = "moseeri dungeon", onLog = log, onStuck = function() toLobby() end,
    stuckKick = false, -- owner 11-23: no "please rejoin" screen at night; every stall = back to a fresh lobby
    stuckMin = tonumber(cfg.stuckMin) or 3,
    pullbackMax = 25, -- our own hover / hold corrections show up as pull-backs too (about 1 a minute), so higher than default
    enabled = true })
do
    local function ddv() local p = LP:FindFirstChild("dungPerformance") local v = p and p:FindFirstChild("damageDone") return v and v.Value or 0 end
    local lastDD, lastPhase = ddv(), S.phase
    go("safety", function()
        while F.alive do
            task.wait(2)
            Safe.cfg.enabled = true -- always on (owner 11-21: no switch)
            local h = hum()
            local dead = not h or h.Health <= 0 or S.phase == "dead"
            Safe.active = cfg.farm and (not IN_LOBBY or cfg.autoJoin) and not S.limitBusy and not cfg.recordRoute and not dead
            local dd = ddv()
            if dd ~= lastDD or (S.phase ~= lastPhase and (S.phase == "start" or S.phase == "end")) then Safe.progress() end
            lastDD, lastPhase = dd, S.phase
        end
    end)
end

go("farm", function()
    while F.alive do
        if cfg.recordRoute and not cfg.farm and IN_LOBBY then
            -- send the owner into the dungeon picked in the window, so the recording gets the right name
            local ok, err = pcall(lobbyTick)
            if not ok then log("ERR record start: " .. tostring(err)) end
            task.wait(0.5)
        elseif (IN_LOBBY and (cfg.farm or cfg.autoJoin) or cfg.farm) and not S.limitBusy then
            local ok, err = pcall(IN_LOBBY and lobbyTick or dungeonTick)
            if not ok then S.errors = S.errors + 1 MSafe.error() log("ERR tick: " .. tostring(err)) task.wait(1) end
            task.wait(0.1)
        else
            swingOn = false
            task.wait(0.3)
        end
    end
end)

--------------------------------------------------------------------------------
-- limit test (dungeon only). Each step stops at the first pull-back / kick sign.
--------------------------------------------------------------------------------
local LIM = { swing = {}, tp = {}, tween = {}, spell = {} }
local function limLog(kind, line) table.insert(LIM[kind], line) log("LIMIT " .. kind .. " " .. line) pcall(function() appendfile(DIR .. "/limits.txt", os.date("%m-%d %H:%M ") .. kind .. " " .. line .. "\n") end) end

-- the server answers every landed melee hit with M1Success: count those per second (mob hp is noisy - bosses
-- have immune phases, targets change). Rates alternate so a slow and a fast window hit the same mobs.
local m1Count = 0
do
    local m1 = R("M1Success")
    if m1 then F.conns[#F.conns + 1] = m1.OnClientEvent:Connect(function() m1Count = m1Count + 1 end) end
end
local function testSwing()
    for _, rate in ipairs({ 10, 30, 10, 30, 60 }) do
        local e = pickTarget()
        if not e then limLog("swing", "no mob - stand in a room with mobs") return end
        engage(e)
        swingOn = false
        local dd = LP:FindFirstChild("dungPerformance") and LP.dungPerformance:FindFirstChild("damageDone")
        local hp0, t0, fired, c0, d0 = e.h.Health, os.clock(), 0, m1Count, dd and dd.Value or 0
        while os.clock() - t0 < 5 and e.h.Health > 0 and F.alive do
            local r = hrp()
            if r then setCF(faceCF(e.r.Position + (flat(r.Position) - flat(e.r.Position)).Unit * 4, e.r.Position)) end
            attack() fired = fired + 1
            task.wait(1 / rate)
        end
        local secs = os.clock() - t0
        limLog("swing", string.format("rate %d -> sent %.1f/s, my dmg %.0f/s, mob hp drop %.0f/s (%s)", rate, fired / secs, ((dd and dd.Value or 0) - d0) / secs,
            (hp0 - e.h.Health) / secs, e.m.Name))
        task.wait(1)
    end
end

local function testTp()
    local rt = route()
    for _, step in ipairs({ 20, 50, 100, 200 }) do
        local r = hrp()
        if not r then return end
        local from = r.Position
        local dir
        local p = rt and nextWaypoint()
        if p and (flat(p) - flat(from)).Magnitude > 1 then dir = (flat(p) - flat(from)).Unit else dir = r.CFrame.LookVector end
        local pb0 = S.pullBacks
        local to = from + dir * step
        setCF(CFrame.new(to))
        task.wait(1.5)
        r = hrp()
        local off = r and (r.Position - to).Magnitude or -1
        local bad = S.pullBacks > pb0 or off > 15
        limLog("tp", string.format("jump %d studs -> %s (off by %.0f)", step, bad and "PULLED BACK" or "ok", off))
        setCF(CFrame.new(from)) task.wait(1.5)
        if bad then return end
    end
end

local function testTween()
    for _, speed in ipairs({ 30, 60, 100, 150 }) do
        local r = hrp()
        if not r then return end
        local from = r.Position
        local dir = r.CFrame.LookVector
        local p = nextWaypoint()
        if p and (flat(p) - flat(from)).Magnitude > 1 then dir = (flat(p) - flat(from)).Unit end
        local to = from + flat(dir).Unit * 60
        local pb0 = S.pullBacks
        local old = cfg.tweenSpeed
        cfg.tweenSpeed = speed
        moveTo(to, nil, "Tween")
        cfg.tweenSpeed = old
        task.wait(1)
        r = hrp()
        local off = r and (r.Position - to).Magnitude or -1
        local bad = S.pullBacks > pb0 or off > 15
        limLog("tween", string.format("%d studs/s -> %s (off by %.0f)", speed, bad and "PULLED BACK" or "ok", off))
        moveTo(from, nil, "Walk") task.wait(1)
        if bad then return end
    end
end

-- does the server let a spell go faster than its cooldown? Fire Q / E every 0.2 s for 6 s and count
-- how often the cooldown value jumps up again (= a cast the server took) and the damage done.
local function testSpell()
    for _, key in ipairs({ "Q", "E" }) do
        local e = pickTarget()
        if not e then limLog("spell", "no mob - stand in a room with mobs") return end
        engage(e)
        swingOn = false
        local cd = LP:FindFirstChild("cooldown" .. key)
        local last, accepted, sent = cd and cd.Value or 0, 0, 0
        local hp0, t0 = e.h.Health, os.clock()
        while os.clock() - t0 < 6 and e.h.Health > 0 and F.alive do
            cast(key) sent = sent + 1
            local t1 = os.clock()
            while os.clock() - t1 < 0.2 do
                local v = cd and cd.Value or 0
                if v > last + 0.3 then accepted = accepted + 1 end
                last = v
                task.wait()
            end
        end
        local secs = os.clock() - t0
        limLog("spell", string.format("%s: sent %d, server took %d in %.1fs, mob dmg %.0f/s", key, sent, accepted, secs, (hp0 - e.h.Health) / secs))
        task.wait(1.5)
    end
end

local function runLimit(kind)
    if IN_LOBBY then S.limitMsg = "go into a dungeon first" return end
    if S.limitBusy then return end
    S.limitBusy = true swingOn = false
    S.limitMsg = "testing " .. kind .. " ..."
    local ok, err = pcall(function()
        if kind == "swing" or kind == "all" then testSwing() end
        if kind == "spell" or kind == "all" then testSpell() end
        if kind == "tween" or kind == "all" then testTween() end
        if kind == "tp" or kind == "all" then testTp() end
    end)
    if not ok then log("ERR limit: " .. tostring(err)) end
    S.limitMsg = "done " .. kind .. " (see Limit test page)"
    S.limitBusy = false
end

--------------------------------------------------------------------------------
-- remote control for tests: dq/cmd.txt in, dq/state.json out
--------------------------------------------------------------------------------
local function writeState()
    local r = hrp()
    local st = {
        v = VERSION, t = os.date("%H:%M:%S"), place = game.PlaceId, lobby = IN_LOBBY, farm = cfg.farm, phase = S.phase,
        target = S.target, wp = S.wp, pos = r and v3s(r.Position) or "-", pullBacks = S.pullBacks, deaths = S.deaths,
        errors = S.errors, swings = S.swings, runs = cfg.totalRuns, lastRun = S.lastRun, limit = S.limitMsg, cfg = { autoBest = cfg.autoBest, map = cfg.map, difficulty = cfg.difficulty, mode = cfg.mode, hardcore = cfg.hardcore, hover = cfg.hover, dodge = cfg.dodge, retry = cfg.retry },
        log = { F.logLines[#F.logLines - 2], F.logLines[#F.logLines - 1], F.logLines[#F.logLines] },
    }
    pcall(function() writefile(DIR .. "/state.json", HttpService:JSONEncode(st)) end)
end
local function runCmd(line)
    local a, b, c = line:match("^(%S+)%s*(%S*)%s*(.*)$")
    if not a then return end
    log("CMD " .. line)
    if a == "farm" then cfg.farm = (b == "1" or b == "on") saveCfg()
    elseif a == "limit" then go("limit", runLimit, b ~= "" and b or "all")
    elseif a == "set" and b == "modeTier" then -- dq_163: tier of the current mode (Elemental Raids Fourteen = lvl 275)
        if type(cfg.modeTier) ~= "table" then cfg.modeTier = {} end
        cfg.modeTier[cfg.mode or "Dungeons"] = c saveCfg()
    elseif a == "set" and DEFAULT[b] ~= nil then
        local v = c
        if type(DEFAULT[b]) == "number" then v = tonumber(c) or DEFAULT[b] elseif type(DEFAULT[b]) == "boolean" then v = (c == "true" or c == "1") end
        cfg[b] = v
        if b == "dodge" then cfg.dodgeOn = v cfg.dodgeMode = "Full" cfg.dodgeLight = false end -- dq_161: one command turns Full dodge on/off
        saveCfg()
    elseif a == "return" then local rl = R("ReturnLobby") if rl then rl:FireServer() end
    elseif a == "lobby" then toLobby()
    elseif a == "jobs" then go("jobs", lobbyJobs)
    elseif a == "roll" then
        -- one free Relic dice roll (RollWeapon, the game's roll button); log the whole answer incl. cooldown
        go("roll", function()
            local rem = R("RollWeapon")
            if not rem then log("ROLL no RollWeapon here (" .. (IN_LOBBY and "lobby" or "dungeon") .. ")") return end
            -- the game answers {ok, cooldown, retryIn, weapons}; can take long, so wait up to 30 s here
            local res, done = nil, false
            task.spawn(function() local ok, r = pcall(function() return rem:InvokeServer() end) res = ok and r or ("error " .. tostring(r)) done = true end)
            local t0 = os.clock()
            while not done and os.clock() - t0 < 30 do task.wait(0.2) end
            if not done then log("ROLL no answer in 30 s") end
            pcall(function()
                local b = LP.PlayerGui:FindFirstChild("mainGui", true)
                local bp = b and b:FindFirstChild("HalloweenBP", true)
                log("ROLL button " .. (bp and ("found, visible=" .. tostring(bp.Visible) .. " parentVisible=" .. tostring(bp.Parent.Visible)) or "missing"))
            end)
            local function dump(v, depth)
                if type(v) ~= "table" then return tostring(v) end
                if depth > 2 then return "{...}" end
                local t = {}
                for k, x in pairs(v) do t[#t + 1] = tostring(k) .. "=" .. dump(x, depth + 1) end
                return "{" .. table.concat(t, ", ") .. "}"
            end
            log("ROLL (" .. (IN_LOBBY and "lobby" or "dungeon") .. ") -> " .. dump(res, 0):sub(1, 400))
            local attrs = {}
            for k, v in pairs(LP:GetAttributes()) do
                local kl = k:lower()
                if kl:find("roll") or kl:find("rng") or kl:find("relic") or kl:find("dice") or kl:find("luck") then attrs[#attrs + 1] = k .. "=" .. tostring(v) end
            end
            log("ROLL player attrs: " .. table.concat(attrs, " "))
        end)
    elseif a == "sell" then go("sell", sellNow)
    elseif a == "slots" then
        -- put spare spells into backup slots 1 / 2 (Blue Flames first, then spare Deadly Whirls); nothing is sold or dropped
        go("slots", function()
            local inv = ask("getInventory", LP.UserId)
            local spare = {}
            for _, it in pairs(type(inv) == "table" and inv.spells or {}) do
                if not it.equippedQ and not it.equippedE and not it.equipped then spare[#spare + 1] = it end
            end
            table.sort(spare, function(a, b) return (a.itemName == "Blue Flames" and 0 or 1) < (b.itemName == "Blue Flames" and 0 or 1) end)
            for i, slot in ipairs({ "Slot1", "Slot2" }) do
                local it = spare[i]
                if it then
                    local ok = ask("equipSpell", it.GUID, it.itemName, slot)
                    log("SLOTS " .. slot .. " <- " .. tostring(it.itemName) .. " -> " .. tostring(ok))
                    task.wait(0.5)
                end
            end
        end)
    elseif a == "colltest" then
        -- read only: can our character physically touch mobs? (collision groups + CanCollide)
        go("colltest", function()
            local PS = game:GetService("PhysicsService")
            local c, r = char(), hrp()
            local myG = r and r.CollisionGroup or "?"
            local e = enemies()[1]
            if not e then log("COLLTEST no mob") return end
            local groups = {}
            for _, p in ipairs(e.m:GetDescendants()) do if p:IsA("BasePart") then groups[p.CollisionGroup .. (p.CanCollide and "+collide" or "-nocollide")] = (groups[p.CollisionGroup .. (p.CanCollide and "+collide" or "-nocollide")] or 0) + 1 end end
            local gl = {}
            for k, v in pairs(groups) do gl[#gl + 1] = k .. " x" .. v end
            local can = "?"
            pcall(function() can = tostring(PS:CollisionGroupsAreCollidable(myG, e.r.CollisionGroup)) end)
            log(string.format("COLLTEST me group %s collide %s | %s parts: %s | my group vs its root group collidable: %s", myG, tostring(r and r.CanCollide), e.m.Name, table.concat(gl, ", "), can))
        end)
    elseif a == "fftest" then
        -- does ApplyForcefield (sent by the game during a Flashstep jump) give a shield without a jump?
        go("fftest", function()
            local c = char()
            local function ffs() local n = 0 for _, d in ipairs(c and c:GetChildren() or {}) do if d:IsA("ForceField") then n = n + 1 end end return n end
            local attrs = function() local t = {} for k, v in pairs(c and c:GetAttributes() or {}) do t[#t + 1] = k .. "=" .. tostring(v) end return table.concat(t, " ") end
            log("FFTEST before: forcefields " .. ffs() .. " | char attrs " .. attrs())
            R("ApplyForcefield"):FireServer()
            for i = 1, 6 do task.wait(0.5) log(string.format("FFTEST +%.1fs: forcefields %d | char attrs %s", i * 0.5, ffs(), attrs())) end
        end)
    elseif a == "dumpsrc" then
        -- decompile the client scripts here (read only, nothing runs or is sent); keep the ones that mention the
        -- dungeon remotes we want to understand -> dq/dsrc_<place>/
        go("dumpsrc", function()
            if type(decompile) ~= "function" then log("DUMPSRC no decompile") return end
            local want = { "ClientDamage", "EnemyAttack", "EnemyRemote", "TakeDamage", "SendSellNPC", "touchOrb", "LegacyTokenFound",
                "SecretDropShown", "Forcefield", "SpawnCompanion", "ContinueInf", "NextTier", "kaboomEvent", "FlashstepState",
                "UpdateKeys", "SendRune", "DropItem", "lootDropTest", "PerformanceReport", "NextRoom", "SwapCanSpawn", "Modifier" }
            -- "dumpsrc A,B,C" = keep scripts that mention these words instead
            if b ~= "" then want = {} for w in b:gmatch("[^,]+") do want[#want + 1] = w end end
            local dir = DIR .. "/dsrc_" .. tostring(game.PlaceId)
            pcall(function() if not isfolder(dir) then makefolder(dir) end end)
            local list, seen = {}, {}
            local function add(d) if typeof(d) == "Instance" and not seen[d] and (d:IsA("LocalScript") or d:IsA("ModuleScript")) then seen[d] = true list[#list + 1] = d end end
            for _, root in ipairs({ RS, game:GetService("ReplicatedFirst"), LP, workspace, game:GetService("StarterPlayer"), game:GetService("StarterGui") }) do
                pcall(function() for _, d in ipairs(root:GetDescendants()) do add(d) end end)
            end
            for _, fname in ipairs({ "getscripts", "getloadedmodules", "getnilinstances" }) do
                local fn = G[fname] or getfenv(0)[fname]
                if type(fn) == "function" then pcall(function() for _, d in ipairs(fn()) do add(d) end end) end
            end
            log("DUMPSRC " .. #list .. " scripts to read")
            local index, kept = {}, 0
            for i, s in ipairs(list) do
                if not F.alive then break end
                local ok, src = pcall(decompile, s)
                if ok and type(src) == "string" then
                    local hits = {}
                    for _, w in ipairs(want) do if src:find(w, 1, true) then hits[#hits + 1] = w end end
                    if #hits > 0 then
                        kept = kept + 1
                        local file = string.format("%04d_%s.lua", i, (s.Name:gsub("[^%w_%-]", "_")):sub(1, 40))
                        pcall(function() writefile(dir .. "/" .. file, "-- " .. s:GetFullName() .. "\n" .. src) end)
                        index[#index + 1] = file .. " | " .. table.concat(hits, ",") .. " | " .. s:GetFullName()
                    end
                end
                if i % 4 == 0 then task.wait() end
            end
            pcall(function() writefile(dir .. "/_index.txt", table.concat(index, "\n")) end)
            log("DUMPSRC done: " .. kept .. " scripts mention them -> " .. dir)
        end)
    elseif a == "hptest" then
        -- set a mob's hp to 0 / delete it on our side: does the server count it as dead (remainingEnemies, Death effect)?
        go("hptest", function()
            local en = workspace:FindFirstChild("Enemies")
            local rem = en and en:FindFirstChild("remainingEnemies")
            local list = enemies()
            if #list < 2 then log("HPTEST need 2 mobs") return end
            local a, b = list[1], list[2]
            local r0 = rem and rem.Value or -1
            pcall(function() a.h.Health = 0 end)
            task.wait(1.5)
            log(string.format("HPTEST hp->0 on %s: our copy hp %.0f, model still there %s, remainingEnemies %d -> %d", a.m.Name, a.h.Health, tostring(a.m.Parent ~= nil), r0, rem and rem.Value or -1))
            local r1 = rem and rem.Value or -1
            local name = b.m.Name
            pcall(function() b.m:Destroy() end)
            task.wait(2)
            log(string.format("HPTEST deleted %s on our side: remainingEnemies %d -> %d", name, r1, rem and rem.Value or -1))
        end)
    elseif a == "owntest" then
        -- can our client move mobs (network ownership)? Lift the 3 nearest mobs 25 studs on our side and see if they stay
        -- (server-owned parts snap back within a few frames). Also asks the executor's isnetworkowner if it has one.
        go("owntest", function()
            local r = hrp()
            if not r then return end
            local list = enemies()
            table.sort(list, function(x, y) return (x.r.Position - r.Position).Magnitude < (y.r.Position - r.Position).Magnitude end)
            for i = 1, math.min(3, #list) do
                local e = list[i]
                local p0 = e.r.Position
                local own = "n/a"
                pcall(function() if isnetworkowner then own = tostring(isnetworkowner(e.r)) end end)
                local anch = tostring(e.r.Anchored)
                pcall(function() e.r.CFrame = e.r.CFrame + Vector3.new(0, 25, 0) end)
                task.wait(0.6)
                local dy = e.r.Position.Y - p0.Y
                log(string.format("OWNTEST %s: isnetworkowner=%s anchored=%s, lifted 25 -> after 0.6 s still +%.0f (%s)", e.m.Name, own, anch, dy,
                    dy > 15 and "WE MOVE IT" or "server put it back"))
            end
        end)
    elseif a == "boxtest" then
        -- owner 11-21: "make the swing box bigger?" The box (Workspace.SwingHitboxAgony) is made by the server.
        -- Stand 35 studs from a mob (out of reach) and swing 5 s as is, then 5 s while every new box is grown to 120
        -- and moved onto the mob on our side. Damage in the 2nd window = the server trusts the client's box.
        go("boxtest", function()
            local was = cfg.farm
            cfg.farm = false S.limitBusy = true swingOn = false hold = nil
            local dd = function() local p = LP:FindFirstChild("dungPerformance") local v = p and p:FindFirstChild("damageDone") return v and v.Value or 0 end
            local e = pickTarget()
            if not e then log("BOXTEST no mob") S.limitBusy = false cfg.farm = was return end
            local function stand()
                local r = hrp()
                if not r or not e.r.Parent then return end
                local dir = flat(r.Position) - flat(e.r.Position)
                if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
                local p = e.r.Position + dir.Unit * (math.max(e.r.Size.X, e.r.Size.Z) / 2 + 40) -- 40 studs past its body
                setCF(CFrame.lookAt(p, e.r.Position))
            end
            local grow = false
            local conn = workspace.ChildAdded:Connect(function(o)
                if grow and o.Name == "SwingHitboxAgony" and o:IsA("BasePart") then
                    pcall(function() o.Size = Vector3.new(120, 120, 120) o.CFrame = e.r.CFrame end)
                end
            end)
            local function window()
                local a0 = dd()
                local t0 = os.clock()
                while os.clock() - t0 < 5 and e.h.Health > 0 do stand() attack() task.wait(0.1) end
                return dd() - a0
            end
            local normal = window()
            grow = true
            local big = window()
            grow = false
            conn:Disconnect()
            log(string.format("BOXTEST 40 studs past the body: normal box %.0f dmg, grown box %.0f dmg (%s)", normal, big, e.m.Name))
            S.limitBusy = false cfg.farm = was
        end)
    elseif a == "swaptest" then
        -- 25 s normal, 25 s with swapping, same fight; damage done by us in each window
        go("swaptest", function()
            local dd = function() local p = LP:FindFirstChild("dungPerformance") local v = p and p:FindFirstChild("damageDone") return v and v.Value or 0 end
            S.useSwap = false
            local a0 = dd() task.wait(25) local a1 = dd()
            S.useSwap = true S.swapN = 0
            local b0 = dd() task.wait(25) local b1 = dd()
            S.useSwap = false
            log(string.format("SWAPTEST normal %.0f dmg/s | with swap %.0f dmg/s (%d swaps)", (a1 - a0) / 25, (b1 - b0) / 25, S.swapN or 0))
        end)
    elseif a == "inv" then
        go("inv", function()
            local s = invSnap()
            local out = { os.date("%H:%M:%S") .. " inventory " .. s.n .. " items, worn " .. s.eqn .. (IN_LOBBY and " (lobby)" or " (dungeon)") }
            for _, ty in ipairs(TYPES) do
                local list = type(s.inv) == "table" and s.inv[ty]
                if type(list) == "table" then
                    local k = 0
                    for _, it in pairs(list) do
                        k = k + 1
                        if k <= 6 or it.equipped == true then
                            local f = {}
                            for key, v in pairs(it) do if type(v) ~= "table" then f[#f + 1] = key .. "=" .. tostring(v) else f[#f + 1] = key .. "={..}" end end
                            table.sort(f)
                            out[#out + 1] = ty .. " | " .. table.concat(f, " ")
                        end
                    end
                end
            end
            pcall(function() writefile(DIR .. "/inv.txt", table.concat(out, "\n")) end)
            log("INV -> dq/inv.txt")
        end)
    elseif a == "kicktest" then S.kickSent = nil if S.onKick then S.onKick("TEST report, not a real kick") end
    elseif a == "eval" then
        -- dev only: run one Lua line and log what it returns (cmd.txt is read only when dq/dev.flag exists)
        go("eval", function()
            local fn, err = loadstring("return " .. b .. (c ~= "" and (" " .. c) or ""))
            if not fn then fn, err = loadstring(b .. (c ~= "" and (" " .. c) or "")) end
            if not fn then log("EVAL compile " .. tostring(err)) return end
            local ok, r = pcall(fn)
            log("EVAL " .. (ok and "" or "error ") .. tostring(r):sub(1, 1500))
        end)
    elseif a == "mobs" then
        -- every model in Enemies (also ones with no Humanoid) + map parts near us named like gem / crystal / orb / core
        go("mobs", function()
            local r = hrp()
            local lines = { os.date("%H:%M:%S") .. " Enemies + gem-like map parts" }
            local en = workspace:FindFirstChild("Enemies")
            for _, m in ipairs(en and en:GetChildren() or {}) do
                local h = m:FindFirstChildOfClass("Humanoid")
                local root = m:IsA("Model") and (m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)) or (m:IsA("BasePart") and m)
                local attrs = {}
                for k, v in pairs(m:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end
                local kids = {}
                for _, c in ipairs(m:GetChildren()) do if #kids < 12 then kids[#kids + 1] = c.Name .. ":" .. c.ClassName end end
                lines[#lines + 1] = string.format("%s | %s | hum %s | %s | dist %s | attrs %s | kids %s", m.Name, m.ClassName,
                    h and string.format("%.0f/%.0f", h.Health, h.MaxHealth) or "NONE", root and v3s(root.Position) or "-",
                    (root and r) and string.format("%.0f", (root.Position - r.Position).Magnitude) or "-", table.concat(attrs, " "), table.concat(kids, ","))
            end
            for _, d in ipairs(workspace:GetDescendants()) do
                local n = d.Name:lower()
                if (n:find("gem") or n:find("crystal") or n:find("orb") or n:find("core") or n:find("shard") or n:find("totem")) and not (en and d:IsDescendantOf(en)) then
                    local p = d:IsA("BasePart") and d or (d:IsA("Model") and d:FindFirstChildWhichIsA("BasePart", true))
                    if p and r and (p.Position - r.Position).Magnitude < 300 then
                        lines[#lines + 1] = string.format("MAP %s | %s | %s | %.0f studs | tr %.1f", d:GetFullName(), d.ClassName, v3s(p.Position), (p.Position - r.Position).Magnitude, p.Transparency)
                    end
                end
            end
            pcall(function() writefile(DIR .. "/mobs.txt", table.concat(lines, "\n")) end)
            log("MOBS " .. #lines .. " lines -> dq/mobs.txt")
        end)
    elseif a == "around" then
        -- what is near us that is not map, mob or player (to find gems / crystals / objectives)
        go("around", function()
            local r = hrp()
            if not r then return end
            local rad = tonumber(b) or 150
            local skip = { workspace:FindFirstChild("DungeonMap"), workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Waste"),
                workspace:FindFirstChild("Spawns"), workspace:FindFirstChild("roomInformation") }
            for _, p in ipairs(Players:GetPlayers()) do if p.Character then skip[#skip + 1] = p.Character end end
            local lines, seen = {}, {}
            for _, d in ipairs(workspace:GetDescendants()) do
                if d:IsA("BasePart") and (d.Position - r.Position).Magnitude < rad then
                    local bad = false
                    for _, s in ipairs(skip) do if s and d:IsDescendantOf(s) then bad = true break end end
                    if not bad then
                        local key = d:GetFullName():gsub("%d+", "#")
                        seen[key] = (seen[key] or 0) + 1
                        if seen[key] <= 3 then
                            local attrs = {}
                            for k, v in pairs(d:GetAttributes()) do attrs[#attrs + 1] = k .. "=" .. tostring(v) end
                            local par = d.Parent
                            for k, v in pairs(par and par:GetAttributes() or {}) do attrs[#attrs + 1] = "parent." .. k .. "=" .. tostring(v) end
                            local extra = ""
                            if d:FindFirstChildWhichIsA("ProximityPrompt", true) or (par and par:FindFirstChildWhichIsA("ProximityPrompt", true)) then extra = extra .. " PROMPT" end
                            if d:FindFirstChildWhichIsA("ClickDetector", true) or (par and par:FindFirstChildWhichIsA("ClickDetector", true)) then extra = extra .. " CLICK" end
                            if par and par:FindFirstChildOfClass("Humanoid") then extra = extra .. " HUMANOID" end
                            lines[#lines + 1] = string.format("%s | %s | size %.0fx%.0fx%.0f | %.0f studs | tr %.1f | color %s%s | %s",
                                d:GetFullName(), d.ClassName, d.Size.X, d.Size.Y, d.Size.Z, (d.Position - r.Position).Magnitude,
                                d.Transparency, tostring(d.BrickColor), extra, table.concat(attrs, " "))
                        end
                    end
                end
            end
            table.insert(lines, 1, os.date("%H:%M:%S") .. " around " .. v3s(r.Position) .. " radius " .. rad .. " | " .. #lines .. " parts (max 3 per name)")
            pcall(function() writefile(DIR .. "/around.txt", table.concat(lines, "\n")) end)
            log("AROUND " .. #lines .. " lines -> dq/around.txt")
        end)
    elseif a == "reload" then task.spawn(function() G.dq_continue = true loadstring(readfile("dq/dq.lua"))() end) -- always the shared build (a 2nd account has DIR = dq/acc_<id>)
    elseif a == "stop" then if G.__dq_stop then G.__dq_stop() end
    end
end
go("cmd", function()
    if not DEV then return end -- test loop only on the owner's PC
    while F.alive do
        pcall(function()
            if isfile and isfile(DIR .. "/cmd.txt") then
                local s = readfile(DIR .. "/cmd.txt")
                if s and s:match("%S") then
                    writefile(DIR .. "/cmd.txt", "")
                    for line in s:gmatch("[^\r\n]+") do runCmd(line) end
                end
            end
        end)
        writeState()
        task.wait(2)
    end
end)

--------------------------------------------------------------------------------
-- pages (in their own function: Luau allows 200 locals per function and the whole script had 209 at the top -
-- Volt took it, Delta did not run it at all, 11-21)
--------------------------------------------------------------------------------
;(function()
local function set(key) return function(v) cfg[key] = v saveCfg() end end
local function get(key) return function() return cfg[key] end end
local function mapReq(name) for _, m in ipairs(MAP_REQ) do if m.map == name then return m.req end end return nil end

-- layout 11-21 (owner: window ran off the bottom): Farm = switches + pick + fight; Lobby = lobby jobs + sell;
-- fine-tuning numbers live on the Limit test page
local farmP = UI.page("Farm", 1)
local fc = UI.card(farmP, 1, "Dungeon")
UI.toggle(fc, "Auto farm (fight in dungeons)", get("farm"), set("farm"))
UI.toggle(fc, "Retry after clear (off = lobby)", get("retry"), set("retry"))
UI.toggle(fc, "Hardcore", get("hardcore"), set("hardcore"))
UI.info(fc, "Now", function() return S.phase .. " · " .. tostring(S.target) end)

local fi = UI.card(farmP, 1, "Fight")
UI.choice(fi, "Move", { "Teleport", "Tween", "Walk" }, get("move"), set("move"))
UI.stepper(fi, "Hover over mob (0 = ground)", 0, 30, get("hover"), set("hover"), 2)
-- Off = never dodge; Light = only big area attacks (40+ wide); Full = every red zone (slower farming)
-- owner 11-22: on/off switch apart from the mode; the mode is kept while dodge is off.
-- cfg.dodge / cfg.dodgeLight stay the flags the fight code reads, worked out from dodgeOn + dodgeMode.
if type(cfg.dodgeOn) ~= "boolean" then cfg.dodgeOn = (cfg.dodge or cfg.dodgeLight) and true or false end
if cfg.dodgeMode ~= "Light" and cfg.dodgeMode ~= "Full" then cfg.dodgeMode = cfg.dodge and "Full" or "Light" end
cfg.dodge = cfg.dodgeOn and cfg.dodgeMode == "Full"
cfg.dodgeLight = cfg.dodgeOn and cfg.dodgeMode == "Light"
UI.toggle(fi, "Dodge", function() return cfg.dodgeOn end, function(v)
    cfg.dodgeOn = v and true or false
    cfg.dodge = cfg.dodgeOn and cfg.dodgeMode == "Full" cfg.dodgeLight = cfg.dodgeOn and cfg.dodgeMode == "Light" saveCfg()
end)
UI.choice(fi, "Dodge mode", { "Light", "Full" }, function() return cfg.dodgeMode end, function(v)
    cfg.dodgeMode = v
    cfg.dodge = cfg.dodgeOn and v == "Full" cfg.dodgeLight = cfg.dodgeOn and v == "Light" saveCfg()
end)
UI.toggle(fi, "Auto pick portal", get("autoPortal"), set("autoPortal"))
UI.toggle(fi, "Auto Q / E", get("autoQE"), set("autoQE"))
UI.toggle(fi, "Boss first", get("bossFirst"), set("bossFirst"))

local pk = UI.card(farmP, 2, "Pick")
UI.toggle(pk, "Auto join dungeon (from lobby)", get("autoJoin"), set("autoJoin"))
UI.toggle(pk, "Auto best (level up)", get("autoBest"), set("autoBest"))
UI.info(pk, "Playing", function()
    local m, d = playing()
    return m .. " · " .. d .. (cfg.autoBest and "  (auto)" or "")
end)
UI.dropdown(pk, "Mode", 100, function()
    local lvl, out = myLevel(), {}
    for _, m in ipairs(MODES) do
        local need = MODE_TIERS[m] and MODE_TIERS[m][1][2] or 1
        out[#out + 1] = { key = m, text = m, right = "lvl " .. need .. "+", dim = lvl < need }
    end
    return out
end, function() return cfg.mode or "Dungeons" end, set("mode"))
UI.dropdown(pk, "Map", 110, function()
    local lvl, out = myLevel(), {}
    for _, m in ipairs(MAP_REQ) do
        local any = false
        for _, d in ipairs(DIFFS) do if routeFor(m.map .. "|" .. d) then any = true end end
        out[#out + 1] = { key = m.map, text = m.map, right = (any and "route · " or "") .. "lvl " .. m.req.Normal,
            dim = (cfg.mode or "Dungeons") ~= "Dungeons" or lvl < m.req.Normal }
    end
    return out
end, get("map"), set("map"))
UI.dropdown(pk, "Difficulty", 110, function()
    local lvl, out = myLevel(), {}
    local mode = cfg.mode or "Dungeons"
    if MODE_TIERS[mode] then
        for _, t in ipairs(MODE_TIERS[mode]) do
            local key = mode .. "|" .. t[1]
            out[#out + 1] = { key = t[1], text = t[1], right = (routeFor(key) and "route · " or "") .. "lvl " .. t[2], dim = lvl < t[2] }
        end
    else
        local req = mapReq(cfg.map) or {}
        for _, d in ipairs(DIFFS) do
            local key = cfg.map .. "|" .. d
            out[#out + 1] = { key = d, text = d, right = (routeFor(key) and "route · " or "") .. (req[d] and ("lvl " .. req[d]) or ""),
                dim = req[d] and lvl < req[d] }
        end
    end
    return out
end, function()
    local mode = cfg.mode or "Dungeons"
    if MODE_TIERS[mode] then return cfg.modeTier[mode] or MODE_TIERS[mode][1][1] end
    return cfg.difficulty
end, function(v)
    local mode = cfg.mode or "Dungeons"
    if MODE_TIERS[mode] then cfg.modeTier[mode] = v else cfg.difficulty = v end
    saveCfg()
end)
UI.toggle(pk, "Record route (play 1 run by hand)", get("recordRoute"), function(v)
    cfg.recordRoute = v
    if v then cfg.farm = false end -- recording = the owner plays
    if not v and rec.pts then recSave("switched off") end
    saveCfg()
end)
UI.info(pk, "Recording", function() return rec.pts and (rec.key .. " · " .. #rec.pts .. " points") or (cfg.recordRoute and "starts in the dungeon" or "-") end)

-- Lobby tab (owner 11-21: one card per topic, short labels so nothing is cut, no "run now" button - it all runs by itself)
local lobP = UI.page("Lobby", 2)
local function pickSummary(tbl, names)
    return function()
        local on = {}
        for _, o in ipairs(names) do if tbl()[o] then on[#on + 1] = o end end
        return #on == 0 and "nothing" or (#on == #names and "all" or table.concat(on, ", "))
    end
end
local function pickList(tbl, names, onWord, offWord)
    return function()
        local out = {}
        for _, o in ipairs(names) do out[#out + 1] = { key = o, text = o, right = tbl()[o] and onWord or offWord } end
        return out
    end
end

-- left column
local cc = UI.card(lobP, 1, "Character")
UI.toggle(cc, "Spend skill points", get("autoSP"), set("autoSP"))
UI.choice(cc, "Stat", { "physical", "spell", "health" }, get("spStat"), set("spStat"))
UI.toggle(cc, "Equip best", get("autoEquipBest"), set("autoEquipBest"))

local rw = UI.card(lobP, 1, "Rewards")
UI.toggle(rw, "Daily reward", get("autoDaily"), set("autoDaily"))
UI.toggle(rw, "Finished quests", get("autoQuests"), set("autoQuests"))
UI.toggle(rw, "Free rewards", get("autoFree"), set("autoFree"))
UI.note(rw, "Free rewards = offline, login streak, playtime, level milestones, index.")

local up = UI.card(lobP, 1, "Upgrade gear")
UI.toggle(up, "Upgrade worn gear (coins)", get("autoUpgrade"), set("autoUpgrade"))
local UPG_LIST = { "weapons", "armors", "helmets", "legs", "rings" }
local upgT = function() return cfg.upgSlots end
UI.dropdown(up, "Slots", 150, pickList(upgT, UPG_LIST, "upgrade", "skip"), pickSummary(upgT, UPG_LIST),
    function(o) cfg.upgSlots[o] = not cfg.upgSlots[o] or nil saveCfg() end,
    { isOn = function(o) return cfg.upgSlots[o] == true end, summary = pickSummary(upgT, UPG_LIST) })
UI.stepper(up, "Levels per item each time", 1, 30, get("upgLevels"), set("upgLevels"), 1)

-- right column
local sn = UI.card(lobP, 2, "Sell")
UI.toggle(sn, "Auto sell", get("autoSell"), set("autoSell"))
UI.stepper(sn, "Go to lobby at (items)", 30, 200, get("sellAt"), set("sellAt"), 10)
-- what to sell sits in the same card (owner 11-21: less confusing)
local RAR_LIST = { "common", "uncommon", "rare", "epic", "legendary", "heirloom" }
local rarT = function() return cfg.sellRarity end
local typT = function() return cfg.sellTypes end
UI.dropdown(sn, "Rarity", 130, pickList(rarT, RAR_LIST, "sell", "keep"), pickSummary(rarT, RAR_LIST),
    function(o) cfg.sellRarity[o] = not cfg.sellRarity[o] or nil saveCfg() end,
    { isOn = function(o) return cfg.sellRarity[o] == true end, summary = pickSummary(rarT, RAR_LIST) })
UI.dropdown(sn, "Types", 150, pickList(typT, TYPES, "sell", "keep"), pickSummary(typT, TYPES),
    function(o) cfg.sellTypes[o] = not cfg.sellTypes[o] or nil saveCfg() end,
    { isOn = function(o) return cfg.sellTypes[o] == true end, summary = pickSummary(typT, TYPES) })
UI.note(sn, "Never sells locked or equipped items.")
UI.button(sn, "Matches now", "Count", function() countSell() end)
UI.info(sn, "Would sell", function() return sellInfo.matches end)
UI.button(sn, "Sell now", "Sell", function() sellNow() end)
UI.info(sn, "Last sell", function() return sellInfo.last end)


local gs = UI.card(lobP, 2, "Game settings")
UI.toggle(gs, "Low graphics (phones)", get("lowGfx"), function(v) cfg.lowGfx = v saveCfg() applyGameSettings() end)

local limP = UI.page("Limit test", 3)
local lc = UI.card(limP, 1, "Find the limits")
UI.note(lc, "Use inside a dungeon, next to mobs. Stops at the first pull-back. Kick risk: use a spare account.")
UI.button(lc, "Swing rate 10-30/s", "Test", function() runLimit("swing") end)
UI.button(lc, "Spell faster than cooldown", "Test", function() runLimit("spell") end)
UI.button(lc, "Tween speed 30-150", "Test", function() runLimit("tween") end)
UI.button(lc, "Teleport jump 20-200", "Test", function() runLimit("tp") end)
UI.button(lc, "All three", "Test", function() runLimit("all") end)
UI.info(lc, "Status", function() return S.limitMsg end)
local adv = UI.card(limP, 1, "Fine tuning")
UI.stepper(adv, "Swings per sec", 1, 40, get("swingRate"), set("swingRate"), 1)
UI.stepper(adv, "Teleport step (studs)", 10, 300, get("tpStep"), set("tpStep"), 10)
UI.stepper(adv, "Stuck timeout (s)", 120, 1200, get("stuckTimeout"), set("stuckTimeout"), 30)
UI.info(adv, "Dodges · deaths", function() return S.dodges .. " · " .. S.deaths end)
local lr = UI.card(limP, 2, "Results")
for _, k in ipairs({ "swing", "spell", "tween", "tp" }) do
    for i = 1, 4 do UI.info(lr, k .. " " .. i, function() return LIM[k][i] or "-" end) end
end

local logP = UI.page("Log", 4)
local lg = UI.card(logP, 1, "Last lines")
for i = 12, 1, -1 do UI.info(lg, "", function() return F.logLines[#F.logLines - i + 1] or "" end) end
local lg2 = UI.card(logP, 2, "Info")
UI.info(lg2, "Version", function() return VERSION end)
UI.info(lg2, "Place", function() return IN_LOBBY and "lobby" or ("dungeon " .. game.PlaceId) end)
UI.info(lg2, "Waypoint", function() return S.wp end)
UI.note(lg2, "Files: Workspace/dq/ - log.txt, limits.txt, cfg.json, state.json, cmd.txt")

-- show/hide button
local tb = new("TextButton", { Name = "Toggle", Size = UDim2.fromOffset(52, 30), Position = UDim2.new(1, -260, 0, 120),
    BackgroundColor3 = T.headBg, BackgroundTransparency = 0.1, TextColor3 = T.accent, Font = Enum.Font.GothamBold, TextSize = 14, Text = "DQ" }, gui)
corner(tb, 8)
stroke(tb, T.accent)
tb.MouseButton1Click:Connect(function() win.Visible = not win.Visible end)
dots.MouseButton1Click:Connect(function() win.Visible = false end)

gui.Parent = guiParent
UI.show("Farm")
end)()

go("ui", function()
    while F.alive do
        if win.Visible then for _, f in ipairs(UI.refreshers) do pcall(f) end end
        task.wait(1)
    end
end)

local function stopMe()
    F.alive = false
    -- stop this copy's safety watcher too: an orphaned one counted "no progress" and kicked [S01] / sent us to
    -- the lobby after every reload (11-21 16:45)
    pcall(function() Safe.stop() end)
    swingOn = false
    for _, c in ipairs(F.conns) do pcall(function() c:Disconnect() end) end
    pcall(function() gui:Destroy() end)
end
if G.__dq_seq == SEQ then G.__dq_stop = stopMe end
go("seq", function()
    while F.alive do
        if G.__dq_seq ~= SEQ then log("older copy " .. SEQ .. " stops") stopMe() return end
        task.wait(0.2)
    end
end)
log("dq ready " .. VERSION .. " | " .. (IN_LOBBY and "lobby" or "dungeon") .. " | farm " .. tostring(cfg.farm))
notify("DQ ready. DQ button shows / hides the window.")
