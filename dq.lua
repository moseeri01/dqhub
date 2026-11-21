-- moseeri dungeon (dq) - farm + limit test for the dungeon game (GameId 4201418016)
-- lobby place 11872917490, dungeon place 14928194914
-- Load:  loadstring(game:HttpGet("https://raw.githubusercontent.com/moseeri01/dqhub/main/dq.lua"))()
-- Owner (local build):  loadstring(readfile("dq/dq.lua"))()
local VERSION = "dq_64"
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
    autoBest = true, retry = true, dodge = false, dodgeLight = true, -- owner 11-21: farming without dodge is faster even with deaths
    sellRarity = { common = true, uncommon = true, rare = true }, sellTypes = { weapons = true, armors = true, helmets = true, legs = true },
    badRoute = {}, deathStreak = 0, lastPlayed = "", lastPlayedAt = 0, autoJoin = false, dangerAnims = {}, bossCells = {}, mobHeight = {}, zoneDmg = {}, timingLog = false, sellAt = 80, mode = "Dungeons", modeTier = {}, recordRoute = false,
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


--------------------------------------------------------------------------------
-- game access
--------------------------------------------------------------------------------
local function R(name) return RS:FindFirstChild(name) end
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
        -- dummies in the lobby have ~1e25 hp: never a target
        if h and r and h.Health > 0 and h.MaxHealth < 1e12 then out[#out + 1] = { m = m, h = h, r = r } end
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
        local nm = e.m.Name:lower()
        if nm:find("orb") or nm:find("sentry") or nm:find("crystal") or nm:find("gem") or nm:find("totem") or nm:find("pylon") then score = score - 2000 end
        -- healers first of all: Fortress Shaman carries a "heal" Beam (dq mobs scan 11-21) and keeps the others alive
        if e.m:FindFirstChild("heal") or nm:find("shaman") or nm:find("cleric") or nm:find("healer") then score = score - 3000 end
        if not bestScore or score < bestScore then best, bestScore = e, score end
    end
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
local function setCF(cf)
    local r = hrp()
    if not r then return end
    r.AssemblyLinearVelocity = Vector3.zero
    r.CFrame = cf
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
    if (r.Position - lastSet.pos).Magnitude > 10 then
        S.pullBacks = S.pullBacks + 1
        log(string.format("PULLBACK set %s now %s", v3s(lastSet.pos), v3s(r.Position)))
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
    local r = hrp()
    if not r then return end
    lookAt = lookAt or pos
    if mode == "Teleport" then
        local step = math.max(5, tonumber(cfg.tpStep) or 60)
        for _ = 1, 60 do
            r = hrp()
            if not r or not F.alive then return end
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
            if not r then return end
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
    if (r.Position - hold.cf.Position).Magnitude > 12 then
        S.pullBacks = S.pullBacks + 1
        log(string.format("PULLBACK (hover) want %s now %s", v3s(hold.cf.Position), v3s(r.Position)))
    end
    r.AssemblyLinearVelocity = Vector3.zero
    r.CFrame = hold.cf
end)

--------------------------------------------------------------------------------
-- dodge: mobs build a red Indicator + a Hitbox part before a skill lands (Aftershock, rapidfire, TargetBeam,
-- plain Hitbox). Stand outside every live one; if no nearby spot is clear (map-wide AoE) go to a safe spot.
--------------------------------------------------------------------------------
local dangers = {} -- part -> born time
local function isDanger(p)
    if not p:IsA("BasePart") then return false end
    -- (DeadlyWhirl / DeadlyVortex are OUR spells - they appear on us when Q/E is used; not dangers. 11-21 14:03)
    if p.Name ~= "Hitbox" and p.Name ~= "Indicator" then return false end
    -- players' own skills carry OwnerUserId (our Q made 30x30 Hitboxes: 1206 dodges from our own skills on 11-21)
    if p:GetAttribute("OwnerUserId") ~= nil or (p.Parent and p.Parent:GetAttribute("OwnerUserId") ~= nil) then return false end
    local c = char()
    if c and p:IsDescendantOf(c) then return false end
    local en = workspace:FindFirstChild("Enemies")
    if p.Parent and p.Parent:IsA("Model") and p.Parent:FindFirstChildOfClass("Humanoid") then return false end -- a mob's own body hitbox
    -- arena-sized parts are not attacks (11-21 Sunken Fortress: 2 such zones sent us to the spawn every second)
    if math.max(p.Size.X, p.Size.Y, p.Size.Z) > 700 then
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
    if not isDanger(p) then return end
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
        if not p.Parent or now - t > 15 then dangers[p] = nil else out[#out + 1] = p end
    end
    liveCache, liveAt = out, now
    return out
end
-- inside the part's box (+ margin); flat red discs (Indicator) count as a tall column
local function inZone(pos, p, margin)
    local lp = p.CFrame:PointToObjectSpace(pos)
    local m = margin or 6
    local hx, hy, hz = p.Size.X / 2 + m, p.Size.Y / 2 + m, p.Size.Z / 2 + m
    -- a flat ring / disc is a tall column of damage. Its thin axis is not always Y: round rings are cylinders lying
    -- on their side (thin axis X, e.g. the 1x214x214 ring that one-shot us on 11-21 while we hovered over it).
    local sx, sy, sz = p.Size.X, p.Size.Y, p.Size.Z
    local thin = math.min(sx, sy, sz)
    if thin <= 2.5 then -- flat rings only; a 5-thick slash box is not a column (it blocked every spot, 11-21 13:43)
        if thin == sx then hx = math.max(hx, 60) elseif thin == sy then hy = math.max(hy, 60) else hz = math.max(hz, 60) end
    end
    return math.abs(lp.X) <= hx and math.abs(lp.Z) <= hz and math.abs(lp.Y) <= hy
end
local function dangerAt(pos)
    for _, p in ipairs(liveDangers()) do if inZone(pos, p) then return p end end
    return nil
end

-- 11-21: dodging to a spot over a cliff dropped us off the map. A spot needs solid floor within 80 studs below.
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
local function hasFloor(p)
    local ex = { workspace:FindFirstChild("Enemies"), workspace:FindFirstChild("Waste") }
    for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then ex[#ex + 1] = pl.Character end end
    floorParams.FilterDescendantsInstances = ex
    local hit = workspace:Raycast(p + Vector3.new(0, 2, 0), Vector3.new(0, -80, 0), floorParams)
    for _ = 1, 10 do
        if not hit then return false end
        if hit.Instance.CanCollide or hit.Instance:IsA("Terrain") then return true end
        -- see-through effect parts (zones, beams): look below them
        hit = workspace:Raycast(hit.Position - Vector3.new(0, 0.1, 0), Vector3.new(0, -80, 0), floorParams)
    end
    return false
end
local function okSpot(p) return not dangerAt(p) and hasFloor(p) end
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
local function sideSpot(from)
    if curTarget and curTarget.Parent then
        local tp = curTarget.Position
        local best, bestD
        for _, rad in ipairs({ 5, 8, 11 }) do
            for k = 0, 15 do
                local a = k * math.pi / 8
                local hov = (cfg.move ~= "Walk") and (tonumber(cfg.hover) or 0) > 0 and ((curTarget and curTarget.Parent) and (tonumber(cfg.mobHeight[curTarget.Parent.Name]) or 24) or 24) or 0 -- stay up: melee swings miss us
                local p = Vector3.new(tp.X + math.cos(a) * rad, tp.Y + hov, tp.Z + math.sin(a) * rad)
                if okSpot(p) then
                    local dd = (p - from).Magnitude
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
    local s = sideSpot(from)
    if s then return s end
    if curTarget and curTarget.Parent then
        local tp = curTarget.Position
        local hov = (cfg.move ~= "Walk") and (tonumber(cfg.hover) or 0) > 0 and ((curTarget and curTarget.Parent) and (tonumber(cfg.mobHeight[curTarget.Parent.Name]) or 24) or 24) or 0
        local best, bestD
        for _, rad in ipairs({ 14, 18, 22 }) do
            for k = 0, 15 do
                local a = k * math.pi / 8
                local p = Vector3.new(tp.X + math.cos(a) * rad, tp.Y + hov, tp.Z + math.sin(a) * rad)
                if okSpot(p) then
                    local dd = (p - from).Magnitude
                    if not bestD or dd < bestD then best, bestD = p, dd end
                end
            end
            if best then return best end
        end
    end
    -- no clear spot in reach: get out anyway (11-21 Cursed Marshes: stayed in a 50-wide zone and took -2040)
    for _, rad in ipairs({ 8, 14, 22, 32, 45, 60, 80, 110, 140, 180, 230 }) do
        for k = 0, 11 do
            local a = k * math.pi / 6
            local p = from + Vector3.new(math.cos(a) * rad, 0, math.sin(a) * rad)
            if okSpot(p) then return p end
        end
    end
    -- nowhere clear within 110 studs: stay and keep hitting (the old jump to the map start bounced us
    -- 350 studs back and forth every second on 11-21; flying up dropped us into the void)
    return nil
end
--------------------------------------------------------------------------------
-- safe zone (Zyrtas, Sunken Fortress - found 11-21): every ~20 s the boss kills everyone outside
-- Workspace.SafeZoneHitbox / SafeZoneIndicator (29x32), shown ~5 s before. While one exists: stand in its middle.
--------------------------------------------------------------------------------
local safeParts = {}
local function isSafePart(p) return p:IsA("BasePart") and p.Name:lower():find("safezone") ~= nil end
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
        if not p.Parent then safeParts[p] = nil else
            local d = me and (flat(p.Position) - flat(me.Position)).Magnitude or 0
            if not ba or d < ba then any, ba = p, d end
            if p.Name:lower():find("indicator") and (not bi or d < bi) then ind, bi = p, d end
        end
    end
    local p = ind or any
    if not p then return nil end
    -- stand on the floor in the middle: the indicator lies on the floor, the hitbox is a tall box around it
    local y = ind and (ind.Position.Y + 3) or (p.Position.Y - p.Size.Y / 2 + 4)
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
end
S.dodges = 0
local lastDodge = 0
local zoneWorthDodging -- set further down (needs the learned threat table)
local function dodgeCheck()
    if IN_LOBBY then return false end
    do -- safe zone beats everything else, red zones included
        local sp = safeZone()
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
    if os.clock() - lastDodge < 0.25 then return false end
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
        setCF(faceCF(to, look)) -- face the mob: the swing loop keeps hitting from the side
        S.dodges = S.dodges + 1
        if os.clock() - (S.lastDodgeLog or 0) > 3 then S.lastDodgeLog = os.clock() log(string.format("DODGE -> %s (%d live zones, %d dodges)", v3s(to), #liveDangers(), S.dodges)) end
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

do -- log damage taken (with what was going on), learn from it, and back off when low
    local last = nil
    local function hook()
        local h = hum()
        if not h then return end
        last = h.Health
        F.conns[#F.conns + 1] = h.HealthChanged:Connect(function(v)
            if last and v < last - 1 and cfg.farm then
                local extra = ""
                pcall(function() extra = learnHit(last - v, h.MaxHealth) end)
                log(string.format("HIT -%.0f hp %.0f/%.0f | %s%s", last - v, v, h.MaxHealth, hitWhy(), extra))
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
local function heightFor(name) return tonumber(cfg.mobHeight[name]) or 24 end
local HT = {}
local function heightTick(e)
    local now, name = os.clock(), e.m.Name
    if HT.name ~= name then HT.name, HT.t0, HT.dd0, HT.okSince = name, now, ddNow(), nil return end
    if now - HT.t0 < 1.5 then return end
    local h = heightFor(name)
    if ddNow() > HT.dd0 then
        HT.okSince = HT.okSince or now
        if now - HT.okSince > 15 and h < 34 then
            cfg.mobHeight[name] = h + 3 HT.okSince = now
            log(string.format("HEIGHT %s -> %d (hitting fine, trying higher)", name, h + 3))
        end
    elseif swingOn and h > 6 then
        cfg.mobHeight[name] = math.max(6, h - 4) HT.okSince = nil
        log(string.format("HEIGHT %s -> %d (no damage at %d)", name, cfg.mobHeight[name], h))
    end
    HT.t0, HT.dd0 = now, ddNow()
end
local function cellPos(root, ai, ri, hi)
    local look = flat(root.CFrame.LookVector)
    if look.Magnitude < 0.1 then look = Vector3.new(0, 0, -1) end
    look = look.Unit
    local a = (ai - 1) * math.pi / 4
    local dir = Vector3.new(look.X * math.cos(a) - look.Z * math.sin(a), 0, look.X * math.sin(a) + look.Z * math.cos(a))
    return root.Position + dir * CELL_R[ri] + Vector3.new(0, heightFor(root.Parent and root.Parent.Name or "?"), 0)
end
local function bossSpot(e)
    local now = os.clock()
    local name = e.m.Name
    cfg.bossCells[name] = cfg.bossCells[name] or {}
    local stats = cfg.bossCells[name]
    local cur = S.bossCell
    if cur and cur.boss == e.m and now < cur.until_ then
        local p = cellPos(e.r, cur.ai, cur.ri, cur.hi)
        if (okSpot(p) or not cfg.dodge) then
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
        if (okSpot(p) or not cfg.dodge) and not (leave and cur.key == key) then
            local score = ((st.h or 0) + 0.5) / ((st.s or 0) + 3) + CELL_R[ri] * 0.002 + math.min(3, st.nd or 0) * 0.3
            if not bestScore or score < bestScore then best, bestScore = { ai = ai, ri = ri, hi = hi, key = key, stat = st }, score end
        end
    end end end
    if not best then return nil end
    best.boss, best.t, best.until_ = e.m, now, now + 2.5
    best.t0, best.dd0 = now, ddNow()
    if not cur or cur.key ~= best.key then
        if os.clock() - (S.spotLogT or 0) > 10 then S.spotLogT = os.clock() else best.quiet = true end
        if not best.quiet then log(string.format("BOSS SPOT %s: dir %d dist %d up %s (hits %.1f in %.0fs there)", name, best.ai, CELL_R[best.ri], "learned", best.stat.h or 0, best.stat.s or 0)) end
    end
    S.bossCell = best
    return cellPos(e.r, best.ai, best.ri, best.hi)
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

local function engage(e)
    local r = hrp()
    if not r then return end
    -- safe zone up: we stay in it (dodgeCheck holds us there); hit whatever is in reach from inside
    if safeZone() then
        hold = nil
        curTarget = e.r
        swingOn = (r.Position - e.r.Position).Magnitude < 30
        if swingOn and cfg.autoQE then
            if castReady("Q") then cast("Q") end
            if castReady("E") then cast("E") end
        trySwap()
        end
        S.target = "in the safe zone"
        return
    end
    -- a boss: fight from the spot around it that gets hit least (red zone on us is still handled by dodgeCheck)
    if e.h.MaxHealth >= 8000 and cfg.move ~= "Walk" then
        curTarget = e.r
        local p = bossSpot(e)
        if p then
            if (r.Position - p).Magnitude > 3 then moveTo(p, e.r.Position) end
            hold = { cf = CFrame.lookAt(p, e.r.Position), t = os.clock() }
            swingOn = (p - e.r.Position).Magnitude < 40
            heightTick(e)
            if swingOn and cfg.autoQE then
                if castReady("Q") then cast("Q") end
                if castReady("E") then cast("E") end
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
    local hover = (cfg.move ~= "Walk") and (tonumber(cfg.hover) or 0) > 0 and heightFor(e.m.Name) or 0
    local stand
    if hover > 0 then
        -- just behind the mob's centre and above its head; the swing hitbox (16 x 50 x 22) reaches down
        stand = tp + dir.Unit * 2 + Vector3.new(0, hover, 0)
    else
        stand = tp + dir.Unit * (tonumber(cfg.standDist) or 4)
        stand = Vector3.new(stand.X, tp.Y, stand.Z)
    end
    curTarget = e.r
    -- the usual spot is in a red zone: take a clear spot beside the mob (on the ground) and keep hitting
    local side = false
    if cfg.dodge and dangerAt(stand) then
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
    swingOn = d < 14
    if hover > 0 then heightTick(e) end
    if swingOn and cfg.autoQE then
        if castReady("Q") then cast("Q") end
        if castReady("E") then cast("E") end
        trySwap()
    end
end

--------------------------------------------------------------------------------
-- run bookkeeping
--------------------------------------------------------------------------------
local coins0 = nil
local function coins() local d = LP:FindFirstChild("data") return d and num(d:FindFirstChild("coins")) or 0 end
local sessionStart = os.clock()
local sessionCoins0 = coins()

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
            S.deaths = S.deaths + 1 S.diedThisRun = true
            S.runDeaths = (S.runDeaths or 0) + 1
            cfg.deathStreak = (tonumber(cfg.deathStreak) or 0) + 1 saveCfg()
            -- owner 11-21: don't jump to the lobby after a death (party runs go on, the friends are still fighting).
            -- After a respawn we fight again; the 3rd death in one run = stay out of the fight until the run ends
            -- (a respawn run once died 14 times in a row by flying straight back to the boss).
            log(string.format("DIED (%d this run, streak %d)%s", S.runDeaths, cfg.deathStreak,
                ""))
        end)
    end
end
watchDeath()
F.conns[#F.conns + 1] = LP.CharacterAdded:Connect(function() task.wait(1) watchDeath() end)

--------------------------------------------------------------------------------
-- main farm loop
--------------------------------------------------------------------------------
local lobbyArrive = os.clock()
local endSeen = nil
local function dungeonTick()
    -- start screen
    local sb = pgui("mainGui.startDungeon")
    if shown(sb) then
        S.phase = "start"
        local btn = sb:FindFirstChild("TextButton")
        if btn and press(btn) then
            log("pressed Start")
            S.runStart = os.clock() reached = 0 coins0 = coins() S.endJobsDone = false S.routePick = nil
            task.wait(2)
        end
        return
    end
    -- end screen
    local cs = pgui("CompletionScreen.CompletionBorder")
    if shown(cs) then
        swingOn = false
        S.phase = "end"
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
            local want = (cfg.retry and not S.needSell and (not S.diedThisRun or #Players:GetPlayers() > 1)) and "Retry" or "Return"
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
    if not S.runStart then S.runStart = os.clock() end
    -- stuck guard
    if os.clock() - S.runStart > (tonumber(cfg.stuckTimeout) or 480) then
        log("STUCK " .. math.floor(os.clock() - S.runStart) .. "s -> ReturnLobby")
        local rl = R("ReturnLobby") if rl then rl:FireServer() end
        S.runStart = os.clock()
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
        S.target = string.format("%s %.0f/%.0f", e.m.Name, e.h.Health, e.h.MaxHealth)
        engage(e)
    else
        swingOn = false
        local p, i, n = nextWaypoint()
        if p and cfg.dodge and dangerAt(p) then
            S.phase = "wait"
            S.target = "red zone on the path"
        elseif p then
            S.phase = "move"
            S.target = string.format("waypoint %d/%d", i, n)
            moveTo(p)
        else
            S.phase = "wait"
            S.target = "no mob, no route"
            S.noMobSince = S.noMobSince or os.clock()
            if os.clock() - S.noMobSince > 25 then
                log("no mob and no route for 25 s -> ReturnLobby")
                S.noMobSince = nil
                local rl = R("ReturnLobby") if rl then rl:FireServer() end
            end
            return
        end
    end
    S.noMobSince = nil
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
local function bestDungeon()
    local lvl = myLevel()
    local list = {}
    -- MAP_REQ runs from easy to hard, so the last open one with a route is the best
    for _, m in ipairs(MAP_REQ) do
        for _, d in ipairs(DIFFS) do
            local key = m.map .. "|" .. d
            if lvl >= m.req[d] and routeFor(key) and not S.refused[key] then
                list[#list + 1] = { map = m.map, diff = d, need = m.req[d] }
            end
        end
    end
    if #list == 0 then return cfg.map, cfg.difficulty, "no route map open" end
    -- two deaths in a row: one step easier until a clean clear
    local pick = list[math.max(1, #list - ((tonumber(cfg.deathStreak) or 0) >= 2 and 1 or 0))]
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
    local inv = gi:InvokeServer(LP.UserId)
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
    local inv = R("getInventory") and R("getInventory"):InvokeServer(LP.UserId)
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
    local ok = R("sellItems"):InvokeServer(list)
    task.wait(1)
    local after = invSnap()
    -- one big call came back nil in a dungeon (11-21 13:33, 63 items): if nothing went, try one item type at a time
    if after.n >= before.n then
        log(string.format("SELL all at once -> %s, items %d -> %d: trying type by type", tostring(ok), before.n, after.n))
        for _, ty in ipairs(TYPES) do
            if #list[ty] > 0 then
                local one = { weapons = {}, armors = {}, helmets = {}, legs = {}, spells = {}, rings = {}, sigils = {} }
                one[ty] = list[ty]
                local r = R("sellItems"):InvokeServer(one)
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
        local q = R("getPlayerQuests"):InvokeServer()
        local cur = type(q) == "table" and q.NewCurrentQuests
        for _, kind in ipairs({ "Daily", "Weekly", "Battlepass" }) do
            local set = cur and cur[kind] and cur[kind].Quests
            if type(set) == "table" then
                for key, v in pairs(set) do
                    if type(v) == "table" and not v.Claimed and tonumber(v.Amount) and tonumber(v.Progress) and v.Progress >= v.Amount then
                        local ok = R("CompleteQuest"):InvokeServer(kind, key)
                        log("QUEST " .. kind .. " " .. tostring(v.Description or key) .. " -> " .. tostring(ok))
                        task.wait(0.5)
                    end
                end
            end
        end
    end
end

S.jobs = lobbyJobs -- the end screen in the dungeon calls it too
local jobsDone = false
-- the lobby opens on the "Your Characters" menu (PlayerGui.LoadingScreen); nothing starts until a slot is picked.
-- Same call as its Play button: SelectCharacterSlot(slot). "Couldn't load. Please rejoin." -> teleport to the lobby again.
local menuTries, menuLast = 0, 0
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
    if os.clock() - menuLast > (menuTries == 0 and 3 or 60) then
        menuLast = os.clock()
        menuTries = menuTries + 1
        local slot = tonumber(LP:GetAttribute("ActiveCharacterSlot")) or 1
        local r = R("SelectCharacterSlot")
        if r then r:FireServer(slot) log("MENU pick character slot " .. slot .. " (try " .. menuTries .. ")") end
        if menuTries >= 4 then menuTries = 0 log("MENU still up after 4 tries -> rejoin lobby") toLobby() end
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
        log("PlaySolo " .. key .. " refused 4 times - skipping it" .. (cfg.autoBest and "" or " (manual pick: change map/difficulty)"))
        -- (no more farm OFF here: a hand-picked dungeon the server keeps refusing steps down one difficulty, see playing())
        return
    end
    local t = { Map = map, Calamity = false, Hardcore = hc, NoHit = false,
        Difficulty = diff, LevelRequirement = 1, Tier = 1, Private = false, Easter = false }
    log("PlaySolo " .. map .. " " .. diff .. (hc and " hardcore" or "") .. " (try " .. S.tries[key] .. ")")
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

go("farm", function()
    while F.alive do
        if cfg.recordRoute and not cfg.farm and IN_LOBBY then
            -- send the owner into the dungeon picked in the window, so the recording gets the right name
            local ok, err = pcall(lobbyTick)
            if not ok then log("ERR record start: " .. tostring(err)) end
            task.wait(0.5)
        elseif (IN_LOBBY and (cfg.farm or cfg.autoJoin) or cfg.farm) and not S.limitBusy then
            local ok, err = pcall(IN_LOBBY and lobbyTick or dungeonTick)
            if not ok then S.errors = S.errors + 1 log("ERR tick: " .. tostring(err)) task.wait(1) end
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
    elseif a == "set" and DEFAULT[b] ~= nil then
        local v = c
        if type(DEFAULT[b]) == "number" then v = tonumber(c) or DEFAULT[b] elseif type(DEFAULT[b]) == "boolean" then v = (c == "true" or c == "1") end
        cfg[b] = v saveCfg()
    elseif a == "return" then local rl = R("ReturnLobby") if rl then rl:FireServer() end
    elseif a == "lobby" then toLobby()
    elseif a == "jobs" then go("jobs", lobbyJobs)
    elseif a == "sell" then go("sell", sellNow)
    elseif a == "slots" then
        -- put spare spells into backup slots 1 / 2 (Blue Flames first, then spare Deadly Whirls); nothing is sold or dropped
        go("slots", function()
            local inv = R("getInventory"):InvokeServer(LP.UserId)
            local spare = {}
            for _, it in pairs(type(inv) == "table" and inv.spells or {}) do
                if not it.equippedQ and not it.equippedE and not it.equipped then spare[#spare + 1] = it end
            end
            table.sort(spare, function(a, b) return (a.itemName == "Blue Flames" and 0 or 1) < (b.itemName == "Blue Flames" and 0 or 1) end)
            for i, slot in ipairs({ "Slot1", "Slot2" }) do
                local it = spare[i]
                if it then
                    local ok = R("equipSpell"):InvokeServer(it.GUID, it.itemName, slot)
                    log("SLOTS " .. slot .. " <- " .. tostring(it.itemName) .. " -> " .. tostring(ok))
                    task.wait(0.5)
                end
            end
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
    elseif a == "reload" then task.spawn(function() G.dq_continue = true loadstring(readfile(DIR .. "/dq.lua"))() end)
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
-- pages
--------------------------------------------------------------------------------
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
UI.choice(fi, "Dodge", { "Off", "Light", "Full" }, function() return cfg.dodge and "Full" or (cfg.dodgeLight and "Light" or "Off") end,
    function(v) cfg.dodge = (v == "Full") cfg.dodgeLight = (v == "Light") saveCfg() end)
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

local lobP = UI.page("Lobby", 2)
local lj = UI.card(lobP, 1, "In the lobby")
UI.toggle(lj, "Skill points (all into one)", get("autoSP"), set("autoSP"))
UI.choice(lj, "Skill point stat", { "physical", "spell", "health" }, get("spStat"), set("spStat"))
UI.toggle(lj, "Equip best", get("autoEquipBest"), set("autoEquipBest"))
UI.toggle(lj, "Daily reward", get("autoDaily"), set("autoDaily"))
UI.toggle(lj, "Claim finished quests", get("autoQuests"), set("autoQuests"))
UI.button(lj, "Run lobby jobs now", "Run", function() lobbyJobs() end)
local sn = UI.card(lobP, 2, "Sell")
UI.toggle(sn, "Auto sell (in the lobby)", get("autoSell"), set("autoSell"))
UI.stepper(sn, "Go to lobby to sell at (items)", 30, 200, get("sellAt"), set("sellAt"), 10)
UI.button(sn, "Matches now", "Count", function() countSell() end)
UI.info(sn, "Would sell", function() return sellInfo.matches end)
UI.button(sn, "Sell now", "Sell", function() sellNow() end)
UI.info(sn, "Last sell", function() return sellInfo.last end)
local sc = UI.card(lobP, 2, "What to sell")
-- dropdowns instead of pill rows (owner 11-21: shorter, less lag); tap an entry to switch it, the list stays open
local function pickList(tbl, names)
    return function()
        local out = {}
        for _, o in ipairs(names) do out[#out + 1] = { key = o, text = o, right = tbl()[o] and "sell" or "keep" } end
        return out
    end
end
local function pickSummary(tbl, names)
    return function()
        local on = {}
        for _, o in ipairs(names) do if tbl()[o] then on[#on + 1] = o end end
        return #on == 0 and "nothing" or (#on == #names and "all" or table.concat(on, ", "))
    end
end
local RAR_LIST = { "common", "uncommon", "rare", "epic", "legendary", "heirloom" }
local rarT = function() return cfg.sellRarity end
local typT = function() return cfg.sellTypes end
UI.dropdown(sc, "Rarity", 130, pickList(rarT, RAR_LIST), pickSummary(rarT, RAR_LIST),
    function(o) cfg.sellRarity[o] = not cfg.sellRarity[o] or nil saveCfg() end,
    { isOn = function(o) return cfg.sellRarity[o] == true end, summary = pickSummary(rarT, RAR_LIST) })
UI.dropdown(sc, "Item types", 150, pickList(typT, TYPES), pickSummary(typT, TYPES),
    function(o) cfg.sellTypes[o] = not cfg.sellTypes[o] or nil saveCfg() end,
    { isOn = function(o) return cfg.sellTypes[o] == true end, summary = pickSummary(typT, TYPES) })
UI.note(sc, "Never sells locked or equipped items.")

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

go("ui", function()
    while F.alive do
        if win.Visible then for _, f in ipairs(UI.refreshers) do pcall(f) end end
        task.wait(1)
    end
end)

local function stopMe()
    F.alive = false
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
