-- WordHelper self-contained launcher
-- Saves this exact version locally so server-browser teleports reload it.

local WORDHELPER_FILE = "WordHelper_Current.lua"
local WORDHELPER_SOURCE = [=[
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local RbxAnalyticsService = game:GetService("RbxAnalyticsService")

local cloneref = cloneref or function(o) return o end
local gethui = gethui or function() return CoreGui end

local CoreGui = cloneref(game:GetService("CoreGui"))
local Players = cloneref(game:GetService("Players"))
local VirtualInputManager = cloneref(game:GetService("VirtualInputManager"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local TweenService = cloneref(game:GetService("TweenService"))
local LogService = cloneref(game:GetService("LogService"))
local GuiService = cloneref(game:GetService("GuiService"))

local request = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request

local TOGGLE_KEY = Enum.KeyCode.RightControl
local MIN_CPM = 50
local MAX_CPM_LEGIT = 1500
local MAX_CPM_BLATANT = 3000

math.randomseed(os.time())

local THEME = {
    Background = Color3.fromRGB(20, 20, 24),
    ItemBG = Color3.fromRGB(32, 32, 38),
    Accent = Color3.fromRGB(114, 100, 255),
    Text = Color3.fromRGB(240, 240, 240),
    SubText = Color3.fromRGB(150, 150, 160),
    Success = Color3.fromRGB(100, 255, 140),
    Warning = Color3.fromRGB(255, 200, 80),
    Slider = Color3.fromRGB(60, 60, 70)
}

local function ColorToRGB(c)
    return string.format("%d,%d,%d", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

local ConfigFile = "WordHelper_Config.json"
local Config = {
    CPM = 550,
    Blatant = false,
    Humanize = true,
    FingerModel = true,
    SortMode = "Random",
    SuffixMode = "",
    LengthMode = 0,
    AutoPlay = false,
    AutoJoin = false,
    AutoJoinSettings = {
        _1v1 = true,
        _4p = true,
        _8p = true
    },
    PanicMode = true,
    ShowKeyboard = false,
    ErrorRate = 5,
    ThinkDelay = 0.8,
    RiskyMistakes = false,
    CustomWords = {},
    MinTypeSpeed = 50,
    MaxTypeSpeed = 3000,
    KeyboardLayout = "QWERTY",
    ShowUsedWords = false,
    GodmodePriority = {
        "__TRAP__",
        "ler",
        "ines",
        "ters",
        "ting",
        "ally",
        "ely",
        "king",
        "pers",
        "__X__"
    }
}

local function SaveConfig()
    if writefile then
        writefile(ConfigFile, HttpService:JSONEncode(Config))
    end
end

local function LoadConfig()
    if isfile and isfile(ConfigFile) then
        local success, decoded = pcall(function() return HttpService:JSONDecode(readfile(ConfigFile)) end)
        if success and decoded then
            for k, v in pairs(decoded) do Config[k] = v end
        end
    end
end
LoadConfig()

local currentCPM = Config.CPM
local isBlatant = Config.Blatant
local useHumanization = Config.Humanize
local useFingerModel = Config.FingerModel
local sortMode = Config.SortMode
if sortMode == "Killer" then
    sortMode = "Godmode"
    Config.SortMode = "Godmode"
end
local suffixMode = Config.SuffixMode or ""
local lengthMode = Config.LengthMode or 0
local autoPlay = Config.AutoPlay
local autoJoin = Config.AutoJoin
local panicMode = Config.PanicMode
local showKeyboard = Config.ShowKeyboard
local errorRate = Config.ErrorRate
local thinkDelayCurrent = Config.ThinkDelay
local riskyMistakes = Config.RiskyMistakes
local keyboardLayout = Config.KeyboardLayout or "QWERTY"

local isTyping = false
local isAutoPlayScheduled = false
local lastTypingStart = 0
local runConn = nil
local inputConn = nil
local logConn = nil
local unloaded = false
local isMyTurnLogDetected = false
local logRequiredLetters = ""
local turnExpiryTime = 0
local Blacklist = {}
local UsedWords = {}
local RandomOrderCache = {}
local RandomPriority = {}
local lastDetected = "---"
local lastLogicUpdate = 0
local lastAutoJoinCheck = 0
local lastWordCheck = 0
local cachedDetected = ""
local cachedCensored = false
local LOGIC_RATE = 0.1
local AUTO_JOIN_RATE = 0.5
local UpdateList
local ButtonCache = {}
local ButtonData = {}
local JoinDebounce = {}
local thinkDelayMin = 0.4
local thinkDelayMax = 1.2

local listUpdatePending = false
local forceUpdateList = false
local lastInputTime = 0
local LIST_DEBOUNCE = 0.05
local currentBestMatch = nil

if logConn then logConn:Disconnect() end
logConn = LogService.MessageOut:Connect(function(message, type)
    local wordPart, timePart = message:match("Word:%s*([A-Za-z]+)%s+Time to respond:%s*(%d+)")
    if wordPart and timePart then
        isMyTurnLogDetected = true
        logRequiredLetters = wordPart
        turnExpiryTime = tick() + tonumber(timePart)
    end
end)

local url = "https://raw.githubusercontent.com/skrylor/english-words/refs/heads/main/merged_english.txt"
local fileName = "ultimate_words_v4.txt"

-- Temporary Loading UI
local LoadingGui = Instance.new("ScreenGui")
LoadingGui.Name = "WordHelperLoading"
local success, parent = pcall(function() return gethui() end)
if not success or not parent then parent = game:GetService("CoreGui") end
LoadingGui.Parent = parent
LoadingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local LoadingFrame = Instance.new("Frame", LoadingGui)
LoadingFrame.Size = UDim2.new(0, 300, 0, 100)
LoadingFrame.Position = UDim2.new(0.5, -150, 0.4, 0)
LoadingFrame.BackgroundColor3 = THEME.Background
LoadingFrame.BorderSizePixel = 0
Instance.new("UICorner", LoadingFrame).CornerRadius = UDim.new(0, 10)
local LStroke = Instance.new("UIStroke", LoadingFrame)
LStroke.Color = THEME.Accent
LStroke.Transparency = 0.5
LStroke.Thickness = 2

local LoadingTitle = Instance.new("TextLabel", LoadingFrame)
LoadingTitle.Size = UDim2.new(1, 0, 0, 40)
LoadingTitle.BackgroundTransparency = 1
LoadingTitle.Text = "WordHelper V4"
LoadingTitle.TextColor3 = THEME.Accent
LoadingTitle.Font = Enum.Font.GothamBold
LoadingTitle.TextSize = 18

local LoadingStatus = Instance.new("TextLabel", LoadingFrame)
LoadingStatus.Size = UDim2.new(1, -20, 0, 30)
LoadingStatus.Position = UDim2.new(0, 10, 0, 50)
LoadingStatus.BackgroundTransparency = 1
LoadingStatus.Text = "Initializing..."
LoadingStatus.TextColor3 = THEME.Text
LoadingStatus.Font = Enum.Font.Gotham
LoadingStatus.TextSize = 14

local function UpdateStatus(text, color)
    LoadingStatus.Text = text
    if color then LoadingStatus.TextColor3 = color end
    game:GetService("RunService").RenderStepped:Wait()
end

-- Startup: Always fetch fresh word list
local function FetchWords()
    UpdateStatus("Fetching latest word list...", THEME.Warning)
    local success, res = pcall(function()
        return request({Url = url, Method = "GET"})
    end)
    
    if success and res and res.Body then
        writefile(fileName, res.Body)
        UpdateStatus("Fetched successfully!", THEME.Success)
    else
        UpdateStatus("Fetch failed! Using cached.", Color3.fromRGB(255, 80, 80))
    end
    task.wait(0.5)
end

FetchWords()

local Words = {}
local SeenWords = {}

-- Canonical exact-membership index for every word WordHelper actually loads.
-- Kept separate from Buckets so discovery never depends on search-index state.
WordHelperKnownWords = {}

local function LoadList(fname)
    UpdateStatus("Parsing word list...", THEME.Warning)
    if isfile(fname) then
        local content = readfile(fname)
        for w in content:gmatch("[^\r\n]+") do
            local clean = w:gsub("[%s%c]+", ""):lower()
            if #clean > 0 and not SeenWords[clean] then
                SeenWords[clean] = true
                WordHelperKnownWords[clean] = true
                table.insert(Words, clean)
            end
        end
        UpdateStatus("Loaded " .. #Words .. " words!", THEME.Success)
    else
         UpdateStatus("No word list found!", Color3.fromRGB(255, 80, 80))
    end
    task.wait(1)
end

LoadList(fileName)

if LoadingGui then LoadingGui:Destroy() end

table.sort(Words)
Buckets = {}
for _, w in ipairs(Words) do
    local c = w:sub(1,1) or ""
    if c == "" then c = "#" end
    Buckets[c] = Buckets[c] or {}
    table.insert(Buckets[c], w)
end

if Config.CustomWords then
    for _, w in ipairs(Config.CustomWords) do
        local clean = w:gsub("[%s%c]+", ""):lower()
        if #clean > 0 and not SeenWords[clean] then
            SeenWords[clean] = true
            WordHelperKnownWords[clean] = true
            table.insert(Words, clean)
            local c = clean:sub(1,1) or ""
            if c == "" then c = "#" end
            Buckets[c] = Buckets[c] or {}
            table.insert(Buckets[c], clean)
        end
    end
end

-- Custom words are appended after the base dictionary has already been sorted.
-- Restore ordering here because several WordHelper searches rely on sorted indexes.
table.sort(Words)
for _, bucket in pairs(Buckets) do
    table.sort(bucket)
end

-- Clear memory
SeenWords = nil

local function shuffleTable(t)
    local n = #t
    for i = n, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

local HardLetterScores = {
    x = 10, z = 9, q = 9, j = 8, v = 6, k = 5, b = 4, f = 3, w = 3,
    y = 2, g = 2, p = 2
}

-- Trap-word set used by Godmode.
local TrapWordPriority = {
    ["across"] = true,
    ["adieux"] = true,
    ["adz"] = true,
    ["adzer"] = true,
    ["ajaja"] = true,
    ["ales"] = true,
    ["allan"] = true,
    ["alms"] = true,
    ["alumni"] = true,
    ["amdahl"] = true,
    ["analog"] = true,
    ["ancestry"] = true,
    ["angers"] = true,
    ["arriving"] = true,
    ["asb"] = true,
    ["asf"] = true,
    ["asgd"] = true,
    ["asmr"] = true,
    ["aspergers"] = true,
    ["avijja"] = true,
    ["ballan"] = true,
    ["bandh"] = true,
    ["batch"] = true,
    ["bergmehl"] = true,
    ["biochemistry"] = true,
    ["bkgd"] = true,
    ["blitze"] = true,
    ["bloggers"] = true,
    ["bomb"] = true,
    ["boodh"] = true,
    ["boss"] = true,
    ["botch"] = true,
    ["boyg"] = true,
    ["braggers"] = true,
    ["braving"] = true,
    ["britch"] = true,
    ["buddh"] = true,
    ["budh"] = true,
    ["buggers"] = true,
    ["buhl"] = true,
    ["buhlbuhl"] = true,
    ["bundh"] = true,
    ["burgers"] = true,
    ["butch"] = true,
    ["byp"] = true,
    ["calligraphy"] = true,
    ["cartography"] = true,
    ["carving"] = true,
    ["catch"] = true,
    ["cats"] = true,
    ["caving"] = true,
    ["ccw"] = true,
    ["ceil"] = true,
    ["ceilidh"] = true,
    ["chon"] = true,
    ["ckw"] = true,
    ["clutch"] = true,
    ["colosseum"] = true,
    ["cookies"] = true,
    ["cork"] = true,
    ["craving"] = true,
    ["cross"] = true,
    ["crutch"] = true,
    ["cuz"] = true,
    ["cyc"] = true,
    ["dahl"] = true,
    ["daledh"] = true,
    ["dallan"] = true,
    ["dangers"] = true,
    ["debt"] = true,
    ["delving"] = true,
    ["dentistry"] = true,
    ["deux"] = true,
    ["dha"] = true,
    ["dhu"] = true,
    ["diggers"] = true,
    ["ditch"] = true,
    ["diving"] = true,
    ["dork"] = true,
    ["dosadh"] = true,
    ["doss"] = true,
    ["driving"] = true,
    ["dummkopf"] = true,
    ["dutch"] = true,
    ["ecb"] = true,
    ["edh"] = true,
    ["eintopf"] = true,
    ["ejusd"] = true,
    ["ellan"] = true,
    ["elytral"] = true,
    ["endangers"] = true,
    ["endrumpf"] = true,
    ["erg"] = true,
    ["erin"] = true,
    ["esd"] = true,
    ["etch"] = true,
    ["exo"] = true,
    ["eyed"] = true,
    ["fardh"] = true,
    ["fetch"] = true,
    ["fillan"] = true,
    ["fingers"] = true,
    ["fleadh"] = true,
    ["floss"] = true,
    ["forgers"] = true,
    ["fork"] = true,
    ["formula"] = true,
    ["fugazi"] = true,
    ["gazi"] = true,
    ["gers"] = true,
    ["gingiva"] = true,
    ["giving"] = true,
    ["gleg"] = true,
    ["gloss"] = true,
    ["goner"] = true,
    ["gotcha"] = true,
    ["gross"] = true,
    ["gugelhupf"] = true,
    ["gyp"] = true,
    ["hajj"] = true,
    ["haloumi"] = true,
    ["hatch"] = true,
    ["having"] = true,
    ["hdbk"] = true,
    ["hexs"] = true,
    ["hitch"] = true,
    ["hoggers"] = true,
    ["holography"] = true,
    ["homework"] = true,
    ["housework"] = true,
    ["hutch"] = true,
    ["hyp"] = true,
    ["iampf"] = true,
    ["ices"] = true,
    ["iconv"] = true,
    ["ileum"] = true,
    ["industry"] = true,
    ["inks"] = true,
    ["isz"] = true,
    ["italy"] = true,
    ["itch"] = true,
    ["ivy"] = true,
    ["jiving"] = true,
    ["joggers"] = true,
    ["joss"] = true,
    ["keratocni"] = true,
    ["kers"] = true,
    ["keys"] = true,
    ["kjeldahl"] = true,
    ["kohl"] = true,
    ["kulturkampf"] = true,
    ["kuvasz"] = true,
    ["lamb"] = true,
    ["lamedh"] = true,
    ["lampf"] = true,
    ["latch"] = true,
    ["leaving"] = true,
    ["lehr"] = true,
    ["lexicography"] = true,
    ["lhd"] = true,
    ["linen"] = true,
    ["lingers"] = true,
    ["linoleum"] = true,
    ["living"] = true,
    ["loggers"] = true,
    ["loner"] = true,
    ["loss"] = true,
    ["loving"] = true,
    ["luz"] = true,
    ["lyc"] = true,
    ["match"] = true,
    ["maul"] = true,
    ["mbaqanga"] = true,
    ["miledh"] = true,
    ["mitch"] = true,
    ["mmfd"] = true,
    ["mongers"] = true,
    ["moss"] = true,
    ["moving"] = true,
    ["mtx"] = true,
    ["muggers"] = true,
    ["mullan"] = true,
    ["myc"] = true,
    ["myg"] = true,
    ["nabk"] = true,
    ["neritjc"] = true,
    ["nerving"] = true,
    ["network"] = true,
    ["neutral"] = true,
    ["nicely"] = true,
    ["noghl"] = true,
    ["notch"] = true,
    ["okshoofd"] = true,
    ["olaf"] = true,
    ["omni"] = true,
    ["oner"] = true,
    ["oog"] = true,
    ["outwork"] = true,
    ["oxo"] = true,
    ["pastry"] = true,
    ["patch"] = true,
    ["paul"] = true,
    ["paving"] = true,
    ["paz"] = true,
    ["petroleum"] = true,
    ["peuhl"] = true,
    ["pez"] = true,
    ["phpht"] = true,
    ["pins"] = true,
    ["pirai"] = true,
    ["pitch"] = true,
    ["plotx"] = true,
    ["plungers"] = true,
    ["pollan"] = true,
    ["polyp"] = true,
    ["ponga"] = true,
    ["pork"] = true,
    ["poss"] = true,
    ["proving"] = true,
    ["qe"] = true,
    ["quidditch"] = true,
    ["random"] = true,
    ["rangers"] = true,
    ["raving"] = true,
    ["recross"] = true,
    ["recusf"] = true,
    ["reds"] = true,
    ["reliving"] = true,
    ["rematch"] = true,
    ["retch"] = true,
    ["revving"] = true,
    ["rework"] = true,
    ["rez"] = true,
    ["ringers"] = true,
    ["riyadh"] = true,
    ["ross"] = true,
    ["roving"] = true,
    ["sadh"] = true,
    ["samadh"] = true,
    ["sandal"] = true,
    ["sank"] = true,
    ["sao"] = true,
    ["saps"] = true,
    ["saul"] = true,
    ["saving"] = true,
    ["schafkopf"] = true,
    ["schlemihl"] = true,
    ["schuyt"] = true,
    ["scoog"] = true,
    ["shilh"] = true,
    ["shlemiehl"] = true,
    ["shradh"] = true,
    ["shuls"] = true,
    ["sidh"] = true,
    ["sieving"] = true,
    ["sikh"] = true,
    ["simoom"] = true,
    ["singers"] = true,
    ["sitz"] = true,
    ["skank"] = true,
    ["slovintzi"] = true,
    ["smh"] = true,
    ["snitch"] = true,
    ["sobuto"] = true,
    ["soul"] = true,
    ["spork"] = true,
    ["sprachgefuhl"] = true,
    ["sriracha"] = true,
    ["stanek"] = true,
    ["stickies"] = true,
    ["stingers"] = true,
    ["stitch"] = true,
    ["stork"] = true,
    ["surviving"] = true,
    ["taggers"] = true,
    ["tehr"] = true,
    ["teruteru"] = true,
    ["tomb"] = true,
    ["toner"] = true,
    ["toss"] = true,
    ["transf"] = true,
    ["triggers"] = true,
    ["tyg"] = true,
    ["typography"] = true,
    ["tzedakah"] = true,
    ["unloving"] = true,
    ["unmoving"] = true,
    ["unskaithd"] = true,
    ["unstitch"] = true,
    ["usb"] = true,
    ["vetoed"] = true,
    ["videography"] = true,
    ["villan"] = true,
    ["vozhd"] = true,
    ["wafd"] = true,
    ["watch"] = true,
    ["waving"] = true,
    ["willinakaqe"] = true,
    ["wingers"] = true,
    ["witch"] = true,
    ["wjc"] = true,
    ["work"] = true,
    ["wretch"] = true,
    ["xylography"] = true,
    ["xylotypography"] = true,
    ["yaksha"] = true,
    ["yangtze"] = true,
    ["yez"] = true,
    ["york"] = true,
    ["yw"] = true,
    ["zeroed"] = true,
    ["zeroes"] = true,
    ["zho"] = true,
    ["zhuzh"] = true,
    ["zingers"] = true,
    ["zirai"] = true,
    ["zmudz"] = true,
    ["zoaeae"] = true,
    ["zool"] = true,
    ["zoos"] = true,
    ["zuz"] = true,
}

-- User-editable GodMode priority list.
-- Special tokens are movable but intentionally not renameable in the UI.
GodmodeDefaultPriority = {
    "__TRAP__",
    "ler",
    "ines",
    "ters",
    "ting",
    "ally",
    "ely",
    "king",
    "pers",
    "__X__"
}

GodmodeSanitizePriority = function(list)
    local cleaned = {}
    local seen = {}

    if type(list) ~= "table" then list = GodmodeDefaultPriority end

    for _, value in ipairs(list) do
        local item = tostring(value or "")
        if item == "__TRAP__" or item == "__X__" then
            if not seen[item] then
                table.insert(cleaned, item)
                seen[item] = true
            end
        else
            item = item:lower():gsub("[^a-z]", "")
            if #item > 0 and not seen[item] then
                table.insert(cleaned, item)
                seen[item] = true
            end
        end
    end

    -- Keep both special categories available even if an older/bad config omitted them.
    if not seen["__TRAP__"] then table.insert(cleaned, 1, "__TRAP__") end
    if not seen["__X__"] then table.insert(cleaned, "__X__") end

    return cleaned
end

Config.GodmodePriority = GodmodeSanitizePriority(Config.GodmodePriority)

CustomTrapWords = CustomTrapWords or {}

GodmodeIsTrapWord = function(word)
    return TrapWordPriority[word] == true
        or CustomTrapWords[word] == true
end

-- Dynamic GodMode reply-exhaustion cache.
-- Globals are used here deliberately to avoid adding more main-chunk locals.
GodmodeReplyAvailabilityCache = GodmodeReplyAvailabilityCache or {}

GodmodeHasAvailableReply = function(prefix)
    prefix = tostring(prefix or ""):lower()
    if prefix == "" then return true end

    local cached = GodmodeReplyAvailabilityCache[prefix]
    if cached and (tick() - cached.Time) < 0.2 then
        return cached.Value
    end

    local available = false
    local bucket = Buckets and Buckets[prefix:sub(1, 1)]

    if bucket then
        for _, replyWord in ipairs(bucket) do
            if replyWord:sub(1, #prefix) == prefix
                and not Blacklist[replyWord]
                and not UsedWords[replyWord] then
                available = true
                break
            end
        end
    end

    GodmodeReplyAvailabilityCache[prefix] = {
        Time = tick(),
        Value = available
    }

    return available
end

GodmodeMatchesConfiguredPriority = function(word)
    for _, category in ipairs(Config.GodmodePriority) do
        if category == "__TRAP__" then
            if GodmodeIsTrapWord(word) then return true end
        elseif category == "__X__" then
            if word:sub(-1) == "x" then return true end
        elseif #word >= #category and word:sub(-#category) == category then
            return true
        end
    end
    return false
end

GodmodeGetPriorityCategory = function(word)
    local exhaustedIndex = nil
    local exhaustedEnding = nil

    for index, category in ipairs(Config.GodmodePriority) do
        if category == "__TRAP__" then
            if GodmodeIsTrapWord(word) then
                return "TRAP", index, false
            end
        elseif category == "__X__" then
            if word:sub(-1) == "x" then
                return "X", index, false
            end
        elseif #word >= #category and word:sub(-#category) == category then
            if GodmodeHasAvailableReply(category) then
                return category:upper(), index, false
            elseif not exhaustedIndex then
                exhaustedIndex = index
                exhaustedEnding = category
            end
        end
    end

    if exhaustedIndex then
        return exhaustedEnding:upper() .. " EXHAUSTED", exhaustedIndex, true
    end

    return "", nil, false
end

local function GetGodmodeScore(word)
    local category, categoryIndex, exhausted = GodmodeGetPriorityCategory(word)

    if categoryIndex and not exhausted then
        return 10000 - categoryIndex
    end

    -- Exhausted strategic endings remain visible only as a final fallback.
    if categoryIndex and exhausted then
        return -1000 - categoryIndex
    end

    return 0
end

local function GetKillerScore(word)
    local lastChar = word:sub(-1)
    return HardLetterScores[lastChar] or 0
end

local function getDistance(s1, s2)
    if #s1 == 0 then
        return #s2
    end
    if #s2 == 0 then
        return #s1
    end
    if s1 == s2 then
        return 0
    end
    local matrix = {}
    for i = 0, #s1 do matrix[i] = {[0] = i} end
    for j = 0, #s2 do matrix[0][j] = j end
    for i = 1, #s1 do
        for j = 1, #s2 do
            local cost = (s1:sub(i,i) == s2:sub(j,j)) and 0 or 1
            matrix[i][j] = math.min(matrix[i-1][j]+1, matrix[i][j-1]+1, matrix[i-1][j-1]+cost)
        end
    end
    return matrix[#s1][#s2]
end

local function Tween(obj, props, time)
    TweenService:Create(obj, TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
end

local function GetCurrentGameWord(providedFrame)
    local frame = providedFrame
    if not frame then
        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local inGame = gui and gui:FindFirstChild("InGame")
        frame = inGame and inGame:FindFirstChild("Frame")
    end

    local container = frame and frame:FindFirstChild("CurrentWord")
    if not container then return "", false end
    
    local detected = ""
    local censored = false
    
    local children = container:GetChildren()
    local letterData = {}
    
    for _, c in ipairs(children) do
        if c:IsA("GuiObject") and c.Visible then
            local txt = c:FindFirstChild("Letter")
            if txt and txt:IsA("TextLabel") and txt.TextTransparency < 1 then
                table.insert(letterData, {
                    Obj = c,
                    Txt = txt,
                    X = c.AbsolutePosition.X,
                    Id = tonumber(c.Name) or 0
                })
            end
        end
    end
    
    table.sort(letterData, function(a,b)
        if math.abs(a.X - b.X) > 2 then
            return a.X < b.X
        end
        return a.Id < b.Id
    end)

    for _, data in ipairs(letterData) do
        local t = tostring(data.Txt.Text)
        if t:find("#") or t:find("%*") then censored = true end
        detected = detected .. t
    end
    
    return detected:lower():gsub(" ", ""), censored
end

local function GetTurnInfo(providedFrame)
    if isMyTurnLogDetected then
        if tick() < turnExpiryTime then
            return true, logRequiredLetters
        else
            isMyTurnLogDetected = false
        end
    end

    local frame = providedFrame
    if not frame then
        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local inGame = gui and gui:FindFirstChild("InGame")
        frame = inGame and inGame:FindFirstChild("Frame")
    end

    local typeLbl = frame and frame:FindFirstChild("Type")
    
    if typeLbl and typeLbl:IsA("TextLabel") then
        local text = typeLbl.Text
        local player = Players.LocalPlayer
        if text:sub(1, #player.Name) == player.Name or text:sub(1, #player.DisplayName) == player.DisplayName then
            local char = text:match("starting with:%s*([A-Za-z])")
            return true, char
        end
    end
    return false, nil
end

local function GetSecureParent()
    local success, result = pcall(function()
        return gethui()
    end)
    if success and result then return result end
    
    success, result = pcall(function()
        return CoreGui
    end)
    if success and result then return result end
    
    return Players.LocalPlayer.PlayerGui
end

local ParentTarget = GetSecureParent()
local GuiName = tostring(math.random(1000000, 9999999))

local env = (getgenv and getgenv()) or _G

env.WordHelperCustomTraps = env.WordHelperCustomTraps or {
    FileName = "WordHelper_CustomTraps.json"
}

env.WordHelperCustomTraps.Save = function()
    if not writefile then return end

    local list = {}
    for word, enabled in pairs(CustomTrapWords) do
        if enabled then
            table.insert(list, word)
        end
    end
    table.sort(list)

    pcall(function()
        writefile(
            env.WordHelperCustomTraps.FileName,
            HttpService:JSONEncode(list)
        )
    end)
end

env.WordHelperCustomTraps.Load = function()
    if not (
        isfile
        and readfile
        and isfile(env.WordHelperCustomTraps.FileName)
    ) then
        return
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(
            readfile(env.WordHelperCustomTraps.FileName)
        )
    end)

    if ok and type(decoded) == "table" then
        for _, word in ipairs(decoded) do
            local clean = tostring(word):lower():gsub("[^a-z]", "")
            if #clean >= 2 then
                CustomTrapWords[clean] = true
            end
        end
    end
end

env.WordHelperCustomTraps.Add = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 then return false end

    CustomTrapWords[word] = true
    env.WordHelperCustomTraps.Save()
    GodmodeReplyAvailabilityCache = {}
    forceUpdateList = true
    lastDetected = "---"

    if ShowToast then
        ShowToast("Marked as custom trap: " .. word, "success")
    end

    return true
end

env.WordHelperCustomTraps.Remove = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if not CustomTrapWords[word] then return false end

    CustomTrapWords[word] = nil
    env.WordHelperCustomTraps.Save()
    GodmodeReplyAvailabilityCache = {}
    forceUpdateList = true
    lastDetected = "---"

    if ShowToast then
        ShowToast("Removed custom trap: " .. word, "warning")
    end

    return true
end

env.WordHelperCustomTraps.Load()

-- Persistent rejected-word learning system.
env.WordHelperBlacklistTracker = env.WordHelperBlacklistTracker or {
    FileName = "WordHelper_RejectedWords.json",
    PendingWord = "",
    PendingAt = 0,
    PendingCurrentWord = "",
    PendingTypeText = "",
    LastAttempt = ""
}

-- Canonical blacklist table for this execution.
-- All rejection UI/save functions below read this same live table.
env.WordHelperBlacklistTracker.LiveBlacklist = Blacklist

env.WordHelperBlacklistTracker.Save = function()
    if not writefile then return end
    local list = {}
    for word, blocked in pairs(env.WordHelperBlacklistTracker.LiveBlacklist or Blacklist) do
        if blocked then
            table.insert(list, word)
        end
    end
    table.sort(list)
    pcall(function()
        writefile(
            env.WordHelperBlacklistTracker.FileName,
            HttpService:JSONEncode(list)
        )
    end)
end

env.WordHelperBlacklistTracker.Load = function()
    if not (isfile and readfile and isfile(env.WordHelperBlacklistTracker.FileName)) then
        return
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(
            readfile(env.WordHelperBlacklistTracker.FileName)
        )
    end)

    if ok and type(decoded) == "table" then
        for _, word in ipairs(decoded) do
            if type(word) == "string" and #word >= 2 then
                Blacklist[word:lower()] = true
            end
        end
    end
end

env.WordHelperBlacklistTracker.RemoveFromCaches = function(word)
    RandomPriority[word] = nil
    for _, list in pairs(RandomOrderCache) do
        for i = #list, 1, -1 do
            if list[i] == word then
                table.remove(list, i)
            end
        end
    end
end

env.WordHelperBlacklistTracker.Add = function(word, reason)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 or Blacklist[word] then return false end

    Blacklist[word] = true
    env.WordHelperBlacklistTracker.LiveBlacklist = Blacklist
    env.WordHelperBlacklistTracker.RemoveFromCaches(word)
    env.WordHelperBlacklistTracker.Save()
    forceUpdateList = true
    lastDetected = "---"

    if StatusText then
        StatusText.Text = "Blacklisted: " .. word
        StatusText.TextColor3 = THEME.Warning
    end
    if ShowToast then
        ShowToast("Rejected word permanently blacklisted: " .. word, "warning")
    end
    if env.WordHelperBlacklistTracker.Refresh then
        pcall(env.WordHelperBlacklistTracker.Refresh)
        task.defer(function()
            if env.WordHelperBlacklistTracker.Refresh then
                pcall(env.WordHelperBlacklistTracker.Refresh)
            end
        end)
    end
    return true
end

env.WordHelperBlacklistTracker.Remove = function(word)
    word = tostring(word or ""):lower()
    if not Blacklist[word] then return end
    Blacklist[word] = nil
    env.WordHelperBlacklistTracker.LiveBlacklist = Blacklist
    env.WordHelperBlacklistTracker.Save()
    forceUpdateList = true
    lastDetected = "---"
    if env.WordHelperBlacklistTracker.Refresh then
        env.WordHelperBlacklistTracker.Refresh()
    end
    if ShowToast then
        ShowToast("Restored word: " .. word, "success")
    end
end

env.WordHelperBlacklistTracker.HasRejectionMessage = function()
    local player = Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local inGame = gui and gui:FindFirstChild("InGame")
    if not inGame then return false end

    for _, obj in ipairs(inGame:GetDescendants()) do
        if obj:IsA("TextLabel") and obj.Visible then
            local text = tostring(obj.Text or ""):lower()
            if text:find("invalid", 1, true)
                or text:find("not a word", 1, true)
                or text:find("banned", 1, true)
                or text:find("blacklisted", 1, true)
                or text:find("not allowed", 1, true) then
                return true
            end
        end
    end
    return false
end

env.WordHelperBlacklistTracker.Load()

if env.WordHelperInstance and env.WordHelperInstance.Parent then
    env.WordHelperInstance:Destroy()
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = GuiName
ScreenGui.Parent = ParentTarget
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

env.WordHelperInstance = ScreenGui

local ToastContainer = Instance.new("Frame", ScreenGui)
ToastContainer.Name = "ToastContainer"
ToastContainer.Size = UDim2.new(0, 300, 1, 0)
ToastContainer.Position = UDim2.new(1, -320, 0, 20)
ToastContainer.BackgroundTransparency = 1
ToastContainer.ZIndex = 100

local function ShowToast(message, type)
    local toast = Instance.new("Frame")
    toast.Size = UDim2.new(1, 0, 0, 40)
    toast.BackgroundColor3 = THEME.ItemBG
    toast.BorderSizePixel = 0
    toast.BackgroundTransparency = 1
    toast.Parent = ToastContainer
    
    local stroke = Instance.new("UIStroke", toast)
    stroke.Thickness = 1.5
    stroke.Transparency = 1
    
    local color = THEME.Text
    if type == "success" then color = THEME.Success
    elseif type == "warning" then color = THEME.Warning
    elseif type == "error" then color = Color3.fromRGB(255, 80, 80)
    end
    stroke.Color = color
    
    Instance.new("UICorner", toast).CornerRadius = UDim.new(0, 6)
    
    local lbl = Instance.new("TextLabel", toast)
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = message
    lbl.TextColor3 = color
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 14
    lbl.TextWrapped = true
    lbl.TextTransparency = 1
    
    Tween(toast, {BackgroundTransparency = 0.1}, 0.3)
    Tween(lbl, {TextTransparency = 0}, 0.3)
    Tween(stroke, {Transparency = 0.2}, 0.3)
    
    task.delay(3, function()
        if toast and toast.Parent then
            Tween(toast, {BackgroundTransparency = 1}, 0.5)
            Tween(lbl, {TextTransparency = 1}, 0.5)
            Tween(stroke, {Transparency = 1}, 0.5)
            task.wait(0.5)
            toast:Destroy()
        end
    end)
end


-- Accepted unknown-word discovery / learning system.
-- Uses a separate env table so we do not add main-chunk locals (Luau register limit).
env.WordHelperDiscovery = env.WordHelperDiscovery or {}
env.WordHelperDiscovery.FileName = "WordHelper_DiscoveredWords.json"
env.WordHelperDiscovery.Pending = env.WordHelperDiscovery.Pending or {}
env.WordHelperDiscovery.Ignored = env.WordHelperDiscovery.Ignored or {}
env.WordHelperDiscovery.LastAcceptedWord = env.WordHelperDiscovery.LastAcceptedWord or ""
env.WordHelperDiscovery.LastAcceptedAt = env.WordHelperDiscovery.LastAcceptedAt or 0
env.WordHelperDiscovery.LastWrongAt = env.WordHelperDiscovery.LastWrongAt or 0
env.WordHelperDiscovery.CurrentCandidate = env.WordHelperDiscovery.CurrentCandidate or ""
env.WordHelperDiscovery.CurrentCandidateAt = env.WordHelperDiscovery.CurrentCandidateAt or 0
env.WordHelperDiscovery.LastWPMText = env.WordHelperDiscovery.LastWPMText or ""
env.WordHelperDiscovery.AcceptanceBestCandidate = env.WordHelperDiscovery.AcceptanceBestCandidate or ""
env.WordHelperDiscovery.AcceptanceBestCandidateAt = env.WordHelperDiscovery.AcceptanceBestCandidateAt or 0
env.WordHelperDiscovery.AcceptanceBestCandidateValid = env.WordHelperDiscovery.AcceptanceBestCandidateValid or false
env.WordHelperDiscovery.SessionSeen = env.WordHelperDiscovery.SessionSeen or {}
env.WordHelperDiscovery.FullCandidate = env.WordHelperDiscovery.FullCandidate or ""
env.WordHelperDiscovery.LastVisibleSuffix = env.WordHelperDiscovery.LastVisibleSuffix or ""
env.WordHelperDiscovery.CandidateTruncated = env.WordHelperDiscovery.CandidateTruncated or false
env.WordHelperDiscovery.ReconstructionValid = env.WordHelperDiscovery.ReconstructionValid ~= false
env.WordHelperDiscovery.LastTypeText = env.WordHelperDiscovery.LastTypeText or ""
env.WordHelperDiscovery.AcceptancePulseAt = env.WordHelperDiscovery.AcceptancePulseAt or 0

env.WordHelperDiscovery.IsKnownWord = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 then return false end
    return WordHelperKnownWords[word] == true
end


env.WordHelperDiscovery.Save = function()
    if not writefile then return end
    pcall(function()
        writefile(
            env.WordHelperDiscovery.FileName,
            HttpService:JSONEncode({
                pending = env.WordHelperDiscovery.Pending,
                ignored = env.WordHelperDiscovery.Ignored
            })
        )
    end)
end

env.WordHelperDiscovery.Load = function()
    if not (isfile and readfile and isfile(env.WordHelperDiscovery.FileName)) then
        return
    end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(env.WordHelperDiscovery.FileName))
    end)
    if not ok or type(decoded) ~= "table" then return end

    if type(decoded.pending) == "table" then
        for word, count in pairs(decoded.pending) do
            local clean = tostring(word):lower():gsub("[^a-z]", "")
            if #clean >= 2 then
                env.WordHelperDiscovery.Pending[clean] = math.max(1, tonumber(count) or 1)
            end
        end
    end

    if type(decoded.ignored) == "table" then
        for word, ignored in pairs(decoded.ignored) do
            local clean = tostring(word):lower():gsub("[^a-z]", "")
            if #clean >= 2 and ignored then
                env.WordHelperDiscovery.Ignored[clean] = true
            end
        end
    end
end

env.WordHelperDiscovery.PendingCount = function()
    local count = 0
    for word, seen in pairs(env.WordHelperDiscovery.Pending) do
        if seen and not env.WordHelperDiscovery.IsKnownWord(word) then
            count = count + 1
        end
    end
    return count
end

env.WordHelperDiscovery.RefreshButton = function()
    if env.WordHelperDiscovery.OpenButton then
        env.WordHelperDiscovery.OpenButton.Text =
            "Discovered (" .. tostring(env.WordHelperDiscovery.PendingCount()) .. ")"
    end
end

env.WordHelperDiscovery.RefreshUI = function()
    env.WordHelperDiscovery.RefreshButton()
    if not env.WordHelperDiscovery.Scroll then return end

    for _, child in ipairs(env.WordHelperDiscovery.Scroll:GetChildren()) do
        if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
            child:Destroy()
        end
    end

    local query = ""
    if env.WordHelperDiscovery.SearchBox then
        query = tostring(env.WordHelperDiscovery.SearchBox.Text or ""):lower():gsub("[^a-z]", "")
        if query == "searchdiscoveredwords" then query = "" end
    end

    local words = {}
    for word, seenCount in pairs(env.WordHelperDiscovery.Pending) do
        if seenCount
            and not env.WordHelperDiscovery.IsKnownWord(word)
            and (query == "" or word:find(query, 1, true)) then
            table.insert(words, word)
        end
    end
    table.sort(words)

    for index, word in ipairs(words) do
        local row = Instance.new("Frame", env.WordHelperDiscovery.Scroll)
        row.Size = UDim2.new(1, -6, 0, 30)
        row.BackgroundColor3 = THEME.ItemBG
        row.LayoutOrder = index
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local label = Instance.new("TextLabel", row)
        label.Size = UDim2.new(1, -130, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.BackgroundTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextColor3 = THEME.Text
        label.Text = word .. "  x" .. tostring(env.WordHelperDiscovery.Pending[word] or 1)

        local add = Instance.new("TextButton", row)
        add.Size = UDim2.new(0, 52, 0, 22)
        add.Position = UDim2.new(1, -116, 0.5, -11)
        add.BackgroundColor3 = THEME.Background
        add.TextColor3 = THEME.Success
        add.Font = Enum.Font.GothamBold
        add.TextSize = 10
        add.Text = "ADD"
        Instance.new("UICorner", add).CornerRadius = UDim.new(0, 4)
        add.MouseButton1Click:Connect(function()
            env.WordHelperDiscovery.Approve(word, false)
        end)

        local ignore = Instance.new("TextButton", row)
        ignore.Size = UDim2.new(0, 56, 0, 22)
        ignore.Position = UDim2.new(1, -60, 0.5, -11)
        ignore.BackgroundColor3 = THEME.Background
        ignore.TextColor3 = THEME.Warning
        ignore.Font = Enum.Font.GothamBold
        ignore.TextSize = 9
        ignore.Text = "IGNORE"
        Instance.new("UICorner", ignore).CornerRadius = UDim.new(0, 4)
        ignore.MouseButton1Click:Connect(function()
            env.WordHelperDiscovery.Ignore(word)
        end)
    end

    if env.WordHelperDiscovery.Header then
        env.WordHelperDiscovery.Header.Text =
            "Discovered Words (" .. tostring(#words) .. ")"
    end
    if env.WordHelperDiscovery.Layout then
        env.WordHelperDiscovery.Scroll.CanvasSize =
            UDim2.new(0, 0, 0, env.WordHelperDiscovery.Layout.AbsoluteContentSize.Y + 6)
    end
end

env.WordHelperDiscovery.Approve = function(word, silent)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 then return false end

    if env.WordHelperDiscovery.IsKnownWord(word) then
        env.WordHelperDiscovery.Pending[word] = nil
        env.WordHelperDiscovery.Save()
        env.WordHelperDiscovery.RefreshUI()
        return false
    end

    Config.CustomWords = Config.CustomWords or {}
    local alreadyCustom = false
    for _, existing in ipairs(Config.CustomWords) do
        if existing == word then
            alreadyCustom = true
            break
        end
    end
    if not alreadyCustom then
        table.insert(Config.CustomWords, word)
    end

    WordHelperKnownWords[word] = true
    table.insert(Words, word)
    local first = word:sub(1, 1)
    Buckets[first] = Buckets[first] or {}
    table.insert(Buckets[first], word)
    table.sort(Words)
    table.sort(Buckets[first])

    -- Game-confirmed accepted words should not remain in the rejection blacklist.
    if Blacklist[word] then
        Blacklist[word] = nil
        if env.WordHelperBlacklistTracker and env.WordHelperBlacklistTracker.Save then
            env.WordHelperBlacklistTracker.Save()
        end
    end

    env.WordHelperDiscovery.Pending[word] = nil
    env.WordHelperDiscovery.Ignored[word] = nil
    if env.WordHelperDiscovery.SessionSeen[word] then
        UsedWords[word] = true
    end
    env.WordHelperDiscovery.Save()
    SaveConfig()

    GodmodeReplyAvailabilityCache = {}
    forceUpdateList = true
    lastDetected = "---"

    if UpdateList then
        local _, requiredNow = GetTurnInfo()
        UpdateList(cachedDetected or "", requiredNow or "")
    end

    env.WordHelperDiscovery.RefreshUI()

    if not silent and ShowToast then
        ShowToast("Added discovered word: " .. word, "success")
    end
    return true
end

env.WordHelperDiscovery.ApproveAll = function()
    local words = {}
    for word, count in pairs(env.WordHelperDiscovery.Pending) do
        if count and not env.WordHelperDiscovery.IsKnownWord(word) then
            table.insert(words, word)
        end
    end
    table.sort(words)

    local added = 0
    for _, word in ipairs(words) do
        if env.WordHelperDiscovery.Approve(word, true) then
            added = added + 1
        end
    end
    env.WordHelperDiscovery.RefreshUI()
    if ShowToast then
        ShowToast("Added " .. tostring(added) .. " discovered words", "success")
    end
end

env.WordHelperDiscovery.Ignore = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 then return end
    env.WordHelperDiscovery.Pending[word] = nil
    env.WordHelperDiscovery.Ignored[word] = true
    env.WordHelperDiscovery.Save()
    env.WordHelperDiscovery.RefreshUI()
    if ShowToast then
        ShowToast("Ignored discovered word: " .. word, "warning")
    end
end

env.WordHelperDiscovery.ConsiderAccepted = function(word, source)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 or #word > 40 then return false end


    if env.WordHelperDiscovery.IsKnownWord(word) then
        return false
    end
    if Blacklist[word] then
        return false
    end
    if env.WordHelperDiscovery.Ignored[word] then
        return false
    end

    local now = tick()
    if (now - (env.WordHelperDiscovery.LastWrongAt or 0)) < 0.75 then
        return false
    end
    if env.WordHelperDiscovery.LastAcceptedWord == word
        and (now - (env.WordHelperDiscovery.LastAcceptedAt or 0)) < 1.0 then
        return false
    end

    env.WordHelperDiscovery.LastAcceptedWord = word
    env.WordHelperDiscovery.LastAcceptedAt = now
    env.WordHelperDiscovery.Pending[word] =
        (tonumber(env.WordHelperDiscovery.Pending[word]) or 0) + 1
    env.WordHelperDiscovery.SessionSeen[word] = true
    env.WordHelperDiscovery.Save()
    env.WordHelperDiscovery.RefreshUI()

    if ShowToast then
        ShowToast("Discovered accepted word: " .. word, "success")
    end
    return true
end

-- Packet-based accepted-word discovery.
--
-- Last Letter sends gameplay through ReplicatedStorage.Modules.Packet.RemoteEvent.
-- The first byte of the incoming buffer is the packet id. Our F7 packet capture
-- established the important sequence:
--   26 (ChatBubble)     -> contains the COMPLETE submitted word as an ASCII run
--   15 (AnswerResults)  -> follows the submitted answer
-- A real accepted answer is then confirmed by the Type prompt moving to the next
-- player. This means discovery no longer reads CurrentWord at all, so truncation,
-- animation, fast typing, corrections and GUI tile rebuilds cannot corrupt words.
--
-- Safety policy:
--   * word must come from packet 26, not from the GUI
--   * packet 15 must follow it almost immediately
--   * the turn must actually change afterward
--   * a Wrong sound after the answer blocks learning
--   * known / ignored / blacklisted words remain excluded

-- Disconnect any older recorder connections left by previous injected versions.
if env.WordHelperDiscovery.RecorderDisconnectAll then
    pcall(env.WordHelperDiscovery.RecorderDisconnectAll)
end
if env.WordHelperDiscovery.TypedSoundConnections then
    for _, connection in ipairs(env.WordHelperDiscovery.TypedSoundConnections) do
        pcall(function() connection:Disconnect() end)
    end
end
env.WordHelperDiscovery.TypedSoundConnections = {}
env.WordHelperDiscovery.TypedSoundConnected = false

env.WordHelperDiscovery.PacketRemote = nil
env.WordHelperDiscovery.PacketConnection = nil
env.WordHelperDiscovery.PacketCandidate = ""
env.WordHelperDiscovery.PacketCandidateAt = 0
env.WordHelperDiscovery.PacketAnswerCandidate = ""
env.WordHelperDiscovery.PacketAnswerAt = 0
env.WordHelperDiscovery.PacketAnswerWrongBaseline = 0
env.WordHelperDiscovery.PacketAnswerTypeText = ""
env.WordHelperDiscovery.PacketLastId = -1

env.WordHelperDiscovery.PacketReadU8 = function(buf, offset)
    local ok, value = pcall(function()
        return buffer.readu8(buf, offset)
    end)
    if ok then return value end
    return nil
end

env.WordHelperDiscovery.PacketLength = function(buf)
    local ok, value = pcall(function()
        return buffer.len(buf)
    end)
    if ok then return value end
    return 0
end

env.WordHelperDiscovery.PacketPrintableRuns = function(buf)
    local runs = {}
    local length = env.WordHelperDiscovery.PacketLength(buf)
    if length <= 0 then return runs end

    local current = {}
    local function flush()
        if #current > 0 then
            runs[#runs + 1] = table.concat(current)
            current = {}
        end
    end

    -- byte 0 is the packet id; payload begins at byte 1.
    for offset = 1, length - 1 do
        local byte = env.WordHelperDiscovery.PacketReadU8(buf, offset)
        if byte and byte >= 32 and byte <= 126 then
            current[#current + 1] = string.char(byte)
        else
            flush()
        end
    end
    flush()
    return runs
end

env.WordHelperDiscovery.PacketExtractWord = function(buf)
    local runs = env.WordHelperDiscovery.PacketPrintableRuns(buf)
    local best = ""

    for _, raw in ipairs(runs) do
        -- Accepted/submitted words in Last Letter's ChatBubble packets are emitted
        -- as uppercase alphabetic ASCII. Requiring uppercase avoids player names and
        -- most unrelated text carried by the same generic ChatBubble packet id.
        if raw:match("^[A-Z]+$") and #raw >= 2 and #raw <= 40 then
            local lower = raw:lower()
            if lower ~= "visible"
                and lower ~= "hidden"
                and lower ~= "none"
                and lower ~= "true"
                and lower ~= "false" then
                if #raw > #best then
                    best = raw
                end
            end
        end
    end

    if best == "" then return "" end
    return best:lower()
end

env.WordHelperDiscovery.PacketClearAnswer = function()
    env.WordHelperDiscovery.PacketAnswerCandidate = ""
    env.WordHelperDiscovery.PacketAnswerAt = 0
    env.WordHelperDiscovery.PacketAnswerWrongBaseline = 0
    env.WordHelperDiscovery.PacketAnswerTypeText = ""
end

env.WordHelperDiscovery.PacketHandle = function(...)
    local args = {...}
    local buf = args[1]
    if typeof(buf) ~= "buffer" then return end

    local packetId = env.WordHelperDiscovery.PacketReadU8(buf, 0)
    if packetId == nil then return end
    env.WordHelperDiscovery.PacketLastId = packetId
    local now = tick()

    if packetId == 26 then -- ChatBubble
        local candidate = env.WordHelperDiscovery.PacketExtractWord(buf)
        if candidate ~= "" then
            env.WordHelperDiscovery.PacketCandidate = candidate
            env.WordHelperDiscovery.PacketCandidateAt = now
        end
        return
    end

    if packetId == 15 then -- AnswerResults
        local candidate = tostring(env.WordHelperDiscovery.PacketCandidate or "")
        local candidateAt = tonumber(env.WordHelperDiscovery.PacketCandidateAt or 0) or 0

        -- In our packet capture the complete-word ChatBubble and AnswerResults were
        -- ~1 ms apart. Keep a generous but tight window to avoid pairing unrelated UI
        -- ChatBubble packets with an answer result.
        if candidate ~= "" and (now - candidateAt) <= 0.45 then
            env.WordHelperDiscovery.PacketAnswerCandidate = candidate
            env.WordHelperDiscovery.PacketAnswerAt = now
            env.WordHelperDiscovery.PacketAnswerWrongBaseline =
                tonumber(env.WordHelperDiscovery.LastWrongAt or 0) or 0
            env.WordHelperDiscovery.PacketAnswerTypeText =
                tostring(env.WordHelperDiscovery.LastTypeText or "")
        else
            env.WordHelperDiscovery.PacketClearAnswer()
        end
        return
    end
end

env.WordHelperDiscovery.AttachPacketRemote = function(remote)
    if not (remote and remote:IsA("RemoteEvent")) then return false end
    if env.WordHelperDiscovery.PacketRemote == remote
        and env.WordHelperDiscovery.PacketConnection then
        return true
    end

    if env.WordHelperDiscovery.PacketConnection then
        pcall(function() env.WordHelperDiscovery.PacketConnection:Disconnect() end)
    end

    env.WordHelperDiscovery.PacketRemote = remote
    local ok, connection = pcall(function()
        return remote.OnClientEvent:Connect(function(...)
            env.WordHelperDiscovery.PacketHandle(...)
        end)
    end)
    if ok and connection then
        env.WordHelperDiscovery.PacketConnection = connection
        return true
    end
    env.WordHelperDiscovery.PacketConnection = nil
    return false
end

env.WordHelperDiscovery.EnsurePacketRemote = function()
    if env.WordHelperDiscovery.PacketConnection
        and env.WordHelperDiscovery.PacketRemote
        and env.WordHelperDiscovery.PacketRemote.Parent then
        return true
    end

    local replicatedStorage = game:GetService("ReplicatedStorage")
    local modules = replicatedStorage:FindFirstChild("Modules")
    local packet = modules and modules:FindFirstChild("Packet")
    local remote = packet and packet:FindFirstChild("RemoteEvent")
    if remote and env.WordHelperDiscovery.AttachPacketRemote(remote) then
        return true
    end
    return false
end

env.WordHelperDiscovery.ObserveFrame = function(detectedWord, censored, typeText, now, frame)
    typeText = tostring(typeText or "")
    now = tonumber(now) or tick()
    env.WordHelperDiscovery.EnsurePacketRemote()

    if env.WordHelperDiscovery.LastTypeText == "" then
        env.WordHelperDiscovery.LastTypeText = typeText
    elseif typeText ~= env.WordHelperDiscovery.LastTypeText then
        local candidate = tostring(env.WordHelperDiscovery.PacketAnswerCandidate or "")
        local answerAt = tonumber(env.WordHelperDiscovery.PacketAnswerAt or 0) or 0
        local wrongAt = tonumber(env.WordHelperDiscovery.LastWrongAt or 0) or 0
        local wrongBaseline = tonumber(env.WordHelperDiscovery.PacketAnswerWrongBaseline or 0) or 0
        local answerType = tostring(env.WordHelperDiscovery.PacketAnswerTypeText or "")

        -- A turn transition is the final acceptance proof. Rejections leave the same
        -- player active, so they never reach ConsiderAccepted.
        if candidate ~= ""
            and answerAt > 0
            and (now - answerAt) <= 1.35
            and wrongAt <= wrongBaseline
            and (answerType == "" or answerType == env.WordHelperDiscovery.LastTypeText) then
            env.WordHelperDiscovery.ConsiderAccepted(
                candidate,
                "Packet ChatBubble + AnswerResults + turn change"
            )
        end

        env.WordHelperDiscovery.PacketClearAnswer()
        env.WordHelperDiscovery.LastTypeText = typeText
    end

    -- Expire any result that did not produce a turn change. This is the normal path
    -- for rejected answers and prevents stale packets from pairing with a later turn.
    local answerAt = tonumber(env.WordHelperDiscovery.PacketAnswerAt or 0) or 0
    if answerAt > 0 and (now - answerAt) > 1.35 then
        env.WordHelperDiscovery.PacketClearAnswer()
    end
end

-- Attach immediately; ObserveFrame also retries if the game recreates the packet layer.
env.WordHelperDiscovery.EnsurePacketRemote()

env.WordHelperDiscovery.BuildUI = function()
    if env.WordHelperDiscovery.Frame and env.WordHelperDiscovery.Frame.Parent then
        return
    end

    env.WordHelperDiscovery.Frame = Instance.new("Frame", ScreenGui)
    env.WordHelperDiscovery.Frame.Name = "DiscoveredWords"
    env.WordHelperDiscovery.Frame.Size = UDim2.new(0, 360, 0, 420)
    env.WordHelperDiscovery.Frame.Position = UDim2.new(0.5, -180, 0.5, -210)
    env.WordHelperDiscovery.Frame.BackgroundColor3 = THEME.Background
    env.WordHelperDiscovery.Frame.Visible = false
    env.WordHelperDiscovery.Frame.ClipsDescendants = true
    do
        local dragging = false
        local dragInput = nil
        local dragStart = nil
        local startPos = nil

        env.WordHelperDiscovery.Frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = env.WordHelperDiscovery.Frame.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then
                        dragging = false
                    end
                end)
            end
        end)

        env.WordHelperDiscovery.Frame.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        UserInputService.InputChanged:Connect(function(input)
            if dragging and input == dragInput and dragStart and startPos then
                local delta = input.Position - dragStart
                env.WordHelperDiscovery.Frame.Position = UDim2.new(
                    startPos.X.Scale,
                    startPos.X.Offset + delta.X,
                    startPos.Y.Scale,
                    startPos.Y.Offset + delta.Y
                )
            end
        end)
    end
    Instance.new("UICorner", env.WordHelperDiscovery.Frame).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke", env.WordHelperDiscovery.Frame)
    stroke.Color = THEME.Accent
    stroke.Transparency = 0.5
    stroke.Thickness = 2

    env.WordHelperDiscovery.Header = Instance.new("TextLabel", env.WordHelperDiscovery.Frame)
    env.WordHelperDiscovery.Header.Size = UDim2.new(1, -80, 0, 38)
    env.WordHelperDiscovery.Header.Position = UDim2.new(0, 12, 0, 0)
    env.WordHelperDiscovery.Header.BackgroundTransparency = 1
    env.WordHelperDiscovery.Header.TextXAlignment = Enum.TextXAlignment.Left
    env.WordHelperDiscovery.Header.Font = Enum.Font.GothamBold
    env.WordHelperDiscovery.Header.TextSize = 15
    env.WordHelperDiscovery.Header.TextColor3 = THEME.Text
    env.WordHelperDiscovery.Header.Text = "Discovered Words"

    local close = Instance.new("TextButton", env.WordHelperDiscovery.Frame)
    close.Size = UDim2.new(0, 38, 0, 38)
    close.Position = UDim2.new(1, -42, 0, 0)
    close.BackgroundTransparency = 1
    close.Text = "X"
    close.TextColor3 = Color3.fromRGB(255, 100, 100)
    close.Font = Enum.Font.GothamBold
    close.TextSize = 15
    close.MouseButton1Click:Connect(function()
        env.WordHelperDiscovery.Frame.Visible = false
    end)

    env.WordHelperDiscovery.SearchBox = Instance.new("TextBox", env.WordHelperDiscovery.Frame)
    env.WordHelperDiscovery.SearchBox.Size = UDim2.new(1, -126, 0, 26)
    env.WordHelperDiscovery.SearchBox.Position = UDim2.new(0, 10, 0, 42)
    env.WordHelperDiscovery.SearchBox.BackgroundColor3 = THEME.ItemBG
    env.WordHelperDiscovery.SearchBox.TextColor3 = THEME.Text
    env.WordHelperDiscovery.SearchBox.PlaceholderText = "Search discovered words..."
    env.WordHelperDiscovery.SearchBox.PlaceholderColor3 = THEME.SubText
    env.WordHelperDiscovery.SearchBox.Text = ""
    env.WordHelperDiscovery.SearchBox.Font = Enum.Font.Gotham
    env.WordHelperDiscovery.SearchBox.TextSize = 11
    Instance.new("UICorner", env.WordHelperDiscovery.SearchBox).CornerRadius = UDim.new(0, 4)
    env.WordHelperDiscovery.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
        env.WordHelperDiscovery.RefreshUI()
    end)

    local addAll = Instance.new("TextButton", env.WordHelperDiscovery.Frame)
    addAll.Size = UDim2.new(0, 100, 0, 26)
    addAll.Position = UDim2.new(1, -110, 0, 42)
    addAll.BackgroundColor3 = THEME.Accent
    addAll.TextColor3 = THEME.Text
    addAll.Text = "ADD ALL"
    addAll.Font = Enum.Font.GothamBold
    addAll.TextSize = 10
    Instance.new("UICorner", addAll).CornerRadius = UDim.new(0, 4)
    addAll.MouseButton1Click:Connect(function()
        env.WordHelperDiscovery.ApproveAll()
    end)

    env.WordHelperDiscovery.Scroll = Instance.new("ScrollingFrame", env.WordHelperDiscovery.Frame)
    env.WordHelperDiscovery.Scroll.Size = UDim2.new(1, -20, 1, -82)
    env.WordHelperDiscovery.Scroll.Position = UDim2.new(0, 10, 0, 76)
    env.WordHelperDiscovery.Scroll.BackgroundTransparency = 1
    env.WordHelperDiscovery.Scroll.ScrollBarThickness = 3
    env.WordHelperDiscovery.Scroll.ScrollBarImageColor3 = THEME.Accent
    env.WordHelperDiscovery.Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)

    env.WordHelperDiscovery.Layout = Instance.new("UIListLayout", env.WordHelperDiscovery.Scroll)
    env.WordHelperDiscovery.Layout.Padding = UDim.new(0, 3)
    env.WordHelperDiscovery.Layout.SortOrder = Enum.SortOrder.LayoutOrder

    env.WordHelperDiscovery.RefreshUI()
end

env.WordHelperDiscovery.Load()

-- Remove stale false-positive discoveries left by older builds.
-- If a saved pending word already exists in the base/custom dictionary, it was
-- never a genuine discovery and should not appear in the review panel.
do
    local cleanedKnownDiscovery = false
    for word, _ in pairs(env.WordHelperDiscovery.Pending) do
        if env.WordHelperDiscovery.IsKnownWord(word) then
            env.WordHelperDiscovery.Pending[word] = nil
            cleanedKnownDiscovery = true
        end
    end
    if cleanedKnownDiscovery then
        env.WordHelperDiscovery.Save()
    end
end


local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 300, 0, 500)
MainFrame.Position = UDim2.new(0.8, -50, 0.4, 0)
MainFrame.BackgroundColor3 = THEME.Background
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local function EnableDragging(frame)
    local dragging, dragInput, dragStart, startPos
    local function Update(input)
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
            
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    
    frame.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            Update(input)
        end
    end)
end

EnableDragging(MainFrame)

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 10)
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = THEME.Accent
Stroke.Transparency = 0.5
Stroke.Thickness = 2

local Header = Instance.new("Frame", MainFrame)
Header.Size = UDim2.new(1, 0, 0, 45)
Header.BackgroundColor3 = THEME.ItemBG
Header.BorderSizePixel = 0

local Title = Instance.new("TextLabel", Header)
Title.Text = "Word<font color=\"rgb(114,100,255)\">Helper</font> V4"
Title.RichText = true
Title.Font = Enum.Font.GothamBold
Title.TextSize = 18
Title.TextColor3 = THEME.Text
Title.Size = UDim2.new(1, -50, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.TextXAlignment = Enum.TextXAlignment.Left

local MinBtn = Instance.new("TextButton", Header)
MinBtn.Text = "-"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 24
MinBtn.TextColor3 = THEME.SubText
MinBtn.Size = UDim2.new(0, 45, 1, 0)
MinBtn.Position = UDim2.new(1, -90, 0, 0)
MinBtn.BackgroundTransparency = 1

local CloseBtn = Instance.new("TextButton", Header)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 18
CloseBtn.TextColor3 = Color3.fromRGB(255, 80, 80)
CloseBtn.Size = UDim2.new(0, 45, 1, 0)
CloseBtn.Position = UDim2.new(1, -45, 0, 0)
CloseBtn.BackgroundTransparency = 1

CloseBtn.MouseButton1Click:Connect(function()
    unloaded = true
    if runConn then runConn:Disconnect() runConn = nil end
    if inputConn then inputConn:Disconnect() inputConn = nil end
    if logConn then logConn:Disconnect() logConn = nil end
    
    for _, btn in ipairs(ButtonCache) do btn:Destroy() end
    table.clear(ButtonCache)

    if ScreenGui and ScreenGui.Parent then ScreenGui:Destroy() end
end)

local StatusFrame = Instance.new("Frame", MainFrame)
StatusFrame.Size = UDim2.new(1, -30, 0, 24)
StatusFrame.Position = UDim2.new(0, 15, 0, 55)
StatusFrame.BackgroundTransparency = 1

local StatusDot = Instance.new("Frame", StatusFrame)
StatusDot.Size = UDim2.new(0, 8, 0, 8)
StatusDot.Position = UDim2.new(0, 0, 0.5, -4)
StatusDot.BackgroundColor3 = THEME.SubText
Instance.new("UICorner", StatusDot).CornerRadius = UDim.new(1, 0)

local StatusText = Instance.new("TextLabel", StatusFrame)
StatusText.Text = "Idle..."
StatusText.RichText = true
StatusText.Font = Enum.Font.Gotham
StatusText.TextSize = 12
StatusText.TextColor3 = THEME.SubText
StatusText.Size = UDim2.new(1, -15, 1, 0)
StatusText.Position = UDim2.new(0, 15, 0, 0)
StatusText.BackgroundTransparency = 1
StatusText.TextXAlignment = Enum.TextXAlignment.Left

local SearchFrame = Instance.new("Frame", MainFrame)
SearchFrame.Size = UDim2.new(1, -10, 0, 26)
SearchFrame.Position = UDim2.new(0, 5, 0, 82)
SearchFrame.BackgroundColor3 = THEME.ItemBG
Instance.new("UICorner", SearchFrame).CornerRadius = UDim.new(0, 6)

local SearchBox = Instance.new("TextBox", SearchFrame)
SearchBox.Size = UDim2.new(1, -20, 1, 0)
SearchBox.Position = UDim2.new(0, 10, 0, 0)
SearchBox.BackgroundTransparency = 1
SearchBox.Font = Enum.Font.Gotham
SearchBox.TextSize = 14
SearchBox.TextColor3 = THEME.Text
SearchBox.PlaceholderText = "Search words..."
SearchBox.PlaceholderColor3 = THEME.SubText
SearchBox.Text = ""
SearchBox.TextXAlignment = Enum.TextXAlignment.Left

env.WordHelperSearchRevision = env.WordHelperSearchRevision or 0

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    env.WordHelperSearchRevision = env.WordHelperSearchRevision + 1
    local revision = env.WordHelperSearchRevision

    -- Let rapid keystrokes collapse into one search. This prevents expensive
    -- one-letter searches from blocking the next character the user types.
    task.delay(0.045, function()
        if revision ~= env.WordHelperSearchRevision then return end
        if UpdateList then
            UpdateList(lastDetected, lastRequiredLetter)
        end
    end)
end)

local ScrollList = Instance.new("ScrollingFrame", MainFrame)
ScrollList.Size = UDim2.new(1, -10, 1, -220)
ScrollList.Position = UDim2.new(0, 5, 0, 115)
ScrollList.BackgroundTransparency = 1
ScrollList.ScrollBarThickness = 3
ScrollList.ScrollBarImageColor3 = THEME.Accent
ScrollList.CanvasSize = UDim2.new(0,0,0,0)

local UIListLayout = Instance.new("UIListLayout", ScrollList)
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 4)

local SettingsFrame = Instance.new("Frame", MainFrame)
SettingsFrame.BackgroundColor3 = THEME.ItemBG
SettingsFrame.BorderSizePixel = 0
SettingsFrame.ClipsDescendants = true

local SlidersFrame = Instance.new("Frame", SettingsFrame)
SlidersFrame.Size = UDim2.new(1, 0, 0, 125)
SlidersFrame.BackgroundTransparency = 1

local TogglesFrame = Instance.new("ScrollingFrame", SettingsFrame)
TogglesFrame.Size = UDim2.new(1, 0, 0, 310)
TogglesFrame.Position = UDim2.new(0, 0, 0, 125)
TogglesFrame.BackgroundTransparency = 1
TogglesFrame.BorderSizePixel = 0
TogglesFrame.ScrollBarThickness = 3
TogglesFrame.ScrollBarImageColor3 = THEME.Accent
TogglesFrame.CanvasSize = UDim2.new(0, 0, 0, 365)
TogglesFrame.ScrollingDirection = Enum.ScrollingDirection.Y
TogglesFrame.Visible = false

local sep = Instance.new("Frame", SettingsFrame)
sep.Size = UDim2.new(1, 0, 0, 1)
sep.BackgroundColor3 = Color3.fromRGB(45, 45, 50)

local settingsCollapsed = true
local function UpdateLayout()
    if settingsCollapsed then
        Tween(SettingsFrame, {Size = UDim2.new(1, 0, 0, 125), Position = UDim2.new(0, 0, 1, -125)})
        Tween(ScrollList, {Size = UDim2.new(1, -10, 1, -245)})
        TogglesFrame.Visible = false
    else
        Tween(SettingsFrame, {Size = UDim2.new(1, 0, 0, 435), Position = UDim2.new(0, 0, 1, -435)})
        Tween(ScrollList, {Size = UDim2.new(1, -10, 1, -555)})
        TogglesFrame.Visible = true
    end
end
UpdateLayout()

local ExpandBtn = Instance.new("TextButton", SlidersFrame)
ExpandBtn.Text = "v Show Settings v"
ExpandBtn.Font = Enum.Font.GothamBold
ExpandBtn.TextSize = 14
ExpandBtn.TextColor3 = THEME.Accent
ExpandBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
ExpandBtn.BackgroundTransparency = 0.5
ExpandBtn.Size = UDim2.new(1, -10, 0, 30)
ExpandBtn.Position = UDim2.new(0, 5, 1, -35)
Instance.new("UICorner", ExpandBtn).CornerRadius = UDim.new(0, 6)

ExpandBtn.MouseButton1Click:Connect(function()
    settingsCollapsed = not settingsCollapsed
    ExpandBtn.Text = settingsCollapsed and "v Show Settings v" or "^ Hide Settings ^"
    UpdateLayout()
end)

local function SetupSlider(btn, bg, fill, callback)
    btn.MouseButton1Down:Connect(function()
        local move, rel
        local function Update()
            local mousePos = UserInputService:GetMouseLocation()
            local relX = math.clamp(mousePos.X - bg.AbsolutePosition.X, 0, bg.AbsoluteSize.X)
            local pct = relX / bg.AbsoluteSize.X
            callback(pct)
            Config.CPM = currentCPM
            Config.ErrorRate = errorRate
            Config.ThinkDelay = thinkDelayCurrent
        end
        Update()
        move = RunService.RenderStepped:Connect(Update)
        rel = UserInputService.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
                if move then move:Disconnect() move = nil end
                if rel then rel:Disconnect() rel = nil end
                SaveConfig()
            end
        end)
    end)
end

local KeyboardFrame = Instance.new("Frame", ScreenGui)
KeyboardFrame.Name = "KeyboardFrame"
KeyboardFrame.Size = UDim2.new(0, 400, 0, 160)
KeyboardFrame.Position = UDim2.new(0.1, 0, 0.5, -80)
KeyboardFrame.BackgroundColor3 = THEME.Background
KeyboardFrame.Visible = showKeyboard
EnableDragging(KeyboardFrame)
Instance.new("UICorner", KeyboardFrame).CornerRadius = UDim.new(0, 8)
local KStroke = Instance.new("UIStroke", KeyboardFrame)
KStroke.Color = THEME.Accent
KStroke.Transparency = 0.6
KStroke.Thickness = 2

local Keys = {}
local function CreateKey(char, pos, size)
    local k = Instance.new("Frame", KeyboardFrame)
    k.Size = size or UDim2.new(0, 30, 0, 30)
    k.Position = pos
    k.BackgroundColor3 = THEME.ItemBG
    Instance.new("UICorner", k).CornerRadius = UDim.new(0, 4)
    
    local l = Instance.new("TextLabel", k)
    l.Size = UDim2.new(1,0,1,0)
    l.BackgroundTransparency = 1
    l.Text = char:upper()
    l.TextColor3 = THEME.Text
    l.Font = Enum.Font.GothamBold
    l.TextSize = 14
    
    Keys[char:lower()] = k
    return k
end

local function GenerateKeyboard()
    for _, c in ipairs(KeyboardFrame:GetChildren()) do
        if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
    end
    Keys = {}
    
    local rows
    if keyboardLayout == "QWERTZ" then
        rows = {
            {"q","w","e","r","t","z","u","i","o","p"},
            {"a","s","d","f","g","h","j","k","l"},
            {"y","x","c","v","b","n","m"}
        }
    elseif keyboardLayout == "AZERTY" then
        rows = {
            {"a","z","e","r","t","y","u","i","o","p"},
            {"q","s","d","f","g","h","j","k","l","m"},
            {"w","x","c","v","b","n"}
        }
    else -- QWERTY
        rows = {
            {"q","w","e","r","t","y","u","i","o","p"},
            {"a","s","d","f","g","h","j","k","l"},
            {"z","x","c","v","b","n","m"}
        }
    end
    
    local startY = 15
    local spacing = 35
    for r, rowChars in ipairs(rows) do
        local rowWidth = #rowChars * 35
        local startX = (400 - rowWidth) / 2
        for i, char in ipairs(rowChars) do
            CreateKey(char, UDim2.new(0, startX + (i-1)*35, 0, startY + (r-1)*35))
        end
    end
    local space = CreateKey(" ", UDim2.new(0.5, -100, 0, startY + 3*35), UDim2.new(0, 200, 0, 30))
    space.FindFirstChild(space, "TextLabel").Text = "SPACE"
end

GenerateKeyboard()

local function CreateDropdown(parent, text, options, default, callback)
    local container = Instance.new("Frame", parent)
    container.Size = UDim2.new(0, 130, 0, 24)
    container.BackgroundColor3 = THEME.Background
    container.ZIndex = 10
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 4)
    
    local mainBtn = Instance.new("TextButton", container)
    mainBtn.Size = UDim2.new(1, 0, 1, 0)
    mainBtn.BackgroundTransparency = 1
    mainBtn.Text = text .. ": " .. default
    mainBtn.Font = Enum.Font.GothamMedium
    mainBtn.TextSize = 11
    mainBtn.TextColor3 = THEME.Accent
    mainBtn.ZIndex = 11

    local listFrame = Instance.new("Frame", container)
    listFrame.Size = UDim2.new(1, 0, 0, #options * 24)
    listFrame.Position = UDim2.new(0, 0, 1, 2)
    listFrame.BackgroundColor3 = THEME.ItemBG
    listFrame.Visible = false
    listFrame.ZIndex = 20
    Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 4)
    
    local isOpen = false
    
    mainBtn.MouseButton1Click:Connect(function()
        isOpen = not isOpen
        listFrame.Visible = isOpen
    end)
    
    for i, opt in ipairs(options) do
        local btn = Instance.new("TextButton", listFrame)
        btn.Size = UDim2.new(1, 0, 0, 24)
        btn.Position = UDim2.new(0, 0, 0, (i-1)*24)
        btn.BackgroundTransparency = 1
        btn.Text = opt
        btn.Font = Enum.Font.Gotham
        btn.TextSize = 11
        btn.TextColor3 = THEME.Text
        btn.ZIndex = 21
        
        btn.MouseButton1Click:Connect(function()
            mainBtn.Text = text .. ": " .. opt
            isOpen = false
            listFrame.Visible = false
            callback(opt)
        end)
    end
    
    return container
end

local LayoutDropdown = CreateDropdown(TogglesFrame, "Layout", {"QWERTY", "QWERTZ", "AZERTY"}, keyboardLayout, function(val)
    keyboardLayout = val
    Config.KeyboardLayout = keyboardLayout
    GenerateKeyboard()
    SaveConfig()
end)
LayoutDropdown.Position = UDim2.new(0, 150, 0, 145)

UserInputService.InputBegan:Connect(function(input)
    if not showKeyboard then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local char = input.KeyCode.Name:lower()
        if Keys[char] then
            Tween(Keys[char], {BackgroundColor3 = THEME.Accent}, 0.1)
        end
        if input.KeyCode == Enum.KeyCode.Space then
            Tween(Keys[" "], {BackgroundColor3 = THEME.Accent}, 0.1)
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if not showKeyboard then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        local char = input.KeyCode.Name:lower()
        if Keys[char] then
            Tween(Keys[char], {BackgroundColor3 = THEME.ItemBG}, 0.2)
        end
        if input.KeyCode == Enum.KeyCode.Space then
            Tween(Keys[" "], {BackgroundColor3 = THEME.ItemBG}, 0.2)
        end
    end
end)

local SliderLabel = Instance.new("TextLabel", SlidersFrame)
SliderLabel.Text = "Speed: " .. currentCPM .. " CPM"
SliderLabel.Font = Enum.Font.GothamMedium
SliderLabel.TextSize = 12
SliderLabel.TextColor3 = THEME.SubText
SliderLabel.Size = UDim2.new(1, -30, 0, 20)
SliderLabel.Position = UDim2.new(0, 15, 0, 8)
SliderLabel.BackgroundTransparency = 1
SliderLabel.TextXAlignment = Enum.TextXAlignment.Left

local SliderBg = Instance.new("Frame", SlidersFrame)
SliderBg.Size = UDim2.new(1, -30, 0, 6)
SliderBg.Position = UDim2.new(0, 15, 0, 30)
SliderBg.BackgroundColor3 = THEME.Slider
Instance.new("UICorner", SliderBg).CornerRadius = UDim.new(1, 0)

local SliderFill = Instance.new("Frame", SliderBg)
SliderFill.Size = UDim2.new(0.5, 0, 1, 0)
SliderFill.BackgroundColor3 = THEME.Accent
Instance.new("UICorner", SliderFill).CornerRadius = UDim.new(1, 0)

local SliderBtn = Instance.new("TextButton", SliderBg)
SliderBtn.Size = UDim2.new(1,0,1,0)
SliderBtn.BackgroundTransparency = 1
SliderBtn.Text = ""

local ErrorLabel = Instance.new("TextLabel", SlidersFrame)
ErrorLabel.Text = "Error Rate: " .. errorRate .. "%"
ErrorLabel.Font = Enum.Font.GothamMedium
ErrorLabel.TextSize = 11
ErrorLabel.TextColor3 = THEME.SubText
ErrorLabel.Size = UDim2.new(1, -30, 0, 18)
ErrorLabel.Position = UDim2.new(0, 15, 0, 36)
ErrorLabel.BackgroundTransparency = 1
ErrorLabel.TextXAlignment = Enum.TextXAlignment.Left

local ErrorBg = Instance.new("Frame", SlidersFrame)
ErrorBg.Size = UDim2.new(1, -30, 0, 6)
ErrorBg.Position = UDim2.new(0, 15, 0, 56)
ErrorBg.BackgroundColor3 = THEME.Slider
Instance.new("UICorner", ErrorBg).CornerRadius = UDim.new(1, 0)

local ErrorFill = Instance.new("Frame", ErrorBg)
ErrorFill.Size = UDim2.new(errorRate/30, 0, 1, 0)
ErrorFill.BackgroundColor3 = Color3.fromRGB(200, 100, 100)
Instance.new("UICorner", ErrorFill).CornerRadius = UDim.new(1, 0)

local ErrorBtn = Instance.new("TextButton", ErrorBg)
ErrorBtn.Size = UDim2.new(1,0,1,0)
ErrorBtn.BackgroundTransparency = 1
ErrorBtn.Text = ""

SetupSlider(ErrorBtn, ErrorBg, ErrorFill, function(pct)
    errorRate = math.floor(pct * 30)
    Config.ErrorRate = errorRate
    ErrorFill.Size = UDim2.new(pct, 0, 1, 0)
    ErrorLabel.Text = "Error Rate: " .. errorRate .. "% (per-letter)"
end)

local ThinkLabel = Instance.new("TextLabel", SlidersFrame)
ThinkLabel.Text = string.format("Think: %.2fs", thinkDelayCurrent)
ThinkLabel.Font = Enum.Font.GothamMedium
ThinkLabel.TextSize = 11
ThinkLabel.TextColor3 = THEME.SubText
ThinkLabel.Size = UDim2.new(1, -30, 0, 18)
ThinkLabel.Position = UDim2.new(0, 15, 0, 62)
ThinkLabel.BackgroundTransparency = 1
ThinkLabel.TextXAlignment = Enum.TextXAlignment.Left

local ThinkBg = Instance.new("Frame", SlidersFrame)
ThinkBg.Size = UDim2.new(1, -30, 0, 6)
ThinkBg.Position = UDim2.new(0, 15, 0, 82)
ThinkBg.BackgroundColor3 = THEME.Slider
Instance.new("UICorner", ThinkBg).CornerRadius = UDim.new(1, 0)

local ThinkFill = Instance.new("Frame", ThinkBg)
local thinkPct = (thinkDelayCurrent - thinkDelayMin) / (thinkDelayMax - thinkDelayMin)
ThinkFill.Size = UDim2.new(thinkPct, 0, 1, 0)
ThinkFill.BackgroundColor3 = THEME.Accent
Instance.new("UICorner", ThinkFill).CornerRadius = UDim.new(1, 0)

local ThinkBtn = Instance.new("TextButton", ThinkBg)
ThinkBtn.Size = UDim2.new(1,0,1,0)
ThinkBtn.BackgroundTransparency = 1
ThinkBtn.Text = ""

SetupSlider(ThinkBtn, ThinkBg, ThinkFill, function(pct)
    thinkDelayCurrent = thinkDelayMin + pct * (thinkDelayMax - thinkDelayMin)
    Config.ThinkDelay = thinkDelayCurrent
    ThinkFill.Size = UDim2.new(pct, 0, 1, 0)
    ThinkLabel.Text = string.format("Think: %.2fs", thinkDelayCurrent)
end)

local function CreateToggle(text, pos, callback)
    local btn = Instance.new("TextButton", TogglesFrame)
    btn.Text = text
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.TextColor3 = THEME.Success
    btn.BackgroundColor3 = THEME.Background
    btn.Size = UDim2.new(0, 85, 0, 24)
    btn.Position = pos
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    
    btn.MouseButton1Click:Connect(function()
        local newState, newText, newColor = callback()
        btn.Text = newText
        btn.TextColor3 = newColor
        SaveConfig()
    end)
    return btn
end

local HumanizeBtn = CreateToggle("Humanize: "..(useHumanization and "ON" or "OFF"), UDim2.new(0, 15, 0, 5), function()
    useHumanization = not useHumanization
    Config.Humanize = useHumanization
    return useHumanization, "Humanize: "..(useHumanization and "ON" or "OFF"), useHumanization and THEME.Success or Color3.fromRGB(255, 100, 100)
end)
HumanizeBtn.TextColor3 = useHumanization and THEME.Success or Color3.fromRGB(255, 100, 100)

local FingerBtn = CreateToggle("10-Finger: "..(useFingerModel and "ON" or "OFF"), UDim2.new(0, 105, 0, 5), function()
    useFingerModel = not useFingerModel
    Config.FingerModel = useFingerModel
    return useFingerModel, "10-Finger: "..(useFingerModel and "ON" or "OFF"), useFingerModel and THEME.Success or Color3.fromRGB(255, 100, 100)
end)
FingerBtn.TextColor3 = useFingerModel and THEME.Success or Color3.fromRGB(255, 100, 100)

local KeyboardBtn = CreateToggle("Keyboard: "..(showKeyboard and "ON" or "OFF"), UDim2.new(0, 195, 0, 5), function()
    showKeyboard = not showKeyboard
    Config.ShowKeyboard = showKeyboard
    KeyboardFrame.Visible = showKeyboard
    return showKeyboard, "Keyboard: "..(showKeyboard and "ON" or "OFF"), showKeyboard and THEME.Success or Color3.fromRGB(255, 100, 100)
end)
KeyboardBtn.TextColor3 = showKeyboard and THEME.Success or Color3.fromRGB(255, 100, 100)

local SortBtn = CreateToggle("Sort: "..sortMode, UDim2.new(0, 15, 0, 33), function()
    if sortMode == "Random" then sortMode = "Shortest"
    elseif sortMode == "Shortest" then sortMode = "Longest"
    elseif sortMode == "Longest" then sortMode = "Godmode"
    else sortMode = "Random" end
    
    Config.SortMode = sortMode
    lastDetected = "---"
    return true, "Sort: "..sortMode, THEME.Accent
end)
SortBtn.TextColor3 = THEME.Accent
SortBtn.Size = UDim2.new(0, 130, 0, 24)

local AutoBtn = CreateToggle("Auto Play: "..(autoPlay and "ON" or "OFF"), UDim2.new(0, 150, 0, 33), function()
    autoPlay = not autoPlay
    Config.AutoPlay = autoPlay
    return autoPlay, "Auto Play: "..(autoPlay and "ON" or "OFF"), autoPlay and THEME.Success or Color3.fromRGB(255, 100, 100)
end)
AutoBtn.TextColor3 = autoPlay and THEME.Success or Color3.fromRGB(255, 100, 100)
AutoBtn.Size = UDim2.new(0, 130, 0, 24)

local AutoJoinBtn = CreateToggle("Auto Join: "..(autoJoin and "ON" or "OFF"), UDim2.new(0, 15, 0, 61), function()
    autoJoin = not autoJoin
    Config.AutoJoin = autoJoin
    return autoJoin, "Auto Join: "..(autoJoin and "ON" or "OFF"), autoJoin and THEME.Success or Color3.fromRGB(255, 100, 100)
end)
AutoJoinBtn.TextColor3 = autoJoin and THEME.Success or Color3.fromRGB(255, 100, 100)
AutoJoinBtn.Size = UDim2.new(0, 265, 0, 24)

-- Used-word display mode. Stored on env to avoid consuming another top-level local register.
env.WordHelperShowUsedBtn = CreateToggle(
    Config.ShowUsedWords and "Used Words: SHOW" or "Used Words: HIDE",
    UDim2.new(0, 15, 0, 265),
    function()
        Config.ShowUsedWords = not Config.ShowUsedWords
        forceUpdateList = true
        if UpdateList then UpdateList(lastDetected, lastRequiredLetter) end
        ShowToast(Config.ShowUsedWords and "Used words will remain visible in grey" or "Used words will be hidden", "success")
        return Config.ShowUsedWords,
            Config.ShowUsedWords and "Used Words: SHOW" or "Used Words: HIDE",
            Config.ShowUsedWords and THEME.Warning or THEME.Success
    end
)
env.WordHelperShowUsedBtn.Size = UDim2.new(0, 265, 0, 24)
env.WordHelperShowUsedBtn.TextColor3 = Config.ShowUsedWords and THEME.Warning or THEME.Success

local function CreateCheckbox(text, pos, key)
    local container = Instance.new("TextButton", TogglesFrame)
    container.Size = UDim2.new(0, 90, 0, 24)
    container.Position = pos
    container.BackgroundColor3 = THEME.ItemBG
    container.AutoButtonColor = false
    container.Text = ""
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 4)
    
    local box = Instance.new("Frame", container)
    box.Size = UDim2.new(0, 14, 0, 14)
    box.Position = UDim2.new(0, 5, 0.5, -7)
    box.BackgroundColor3 = THEME.Slider
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 3)
    
    local check = Instance.new("Frame", box)
    check.Size = UDim2.new(0, 8, 0, 8)
    check.Position = UDim2.new(0.5, -4, 0.5, -4)
    check.BackgroundColor3 = THEME.Success
    check.Visible = Config.AutoJoinSettings[key]
    Instance.new("UICorner", check).CornerRadius = UDim.new(0, 2)
    
    local lbl = Instance.new("TextLabel", container)
    lbl.Text = text
    lbl.Font = Enum.Font.GothamMedium
    lbl.TextSize = 11
    lbl.TextColor3 = THEME.SubText
    lbl.Size = UDim2.new(1, -25, 1, 0)
    lbl.Position = UDim2.new(0, 25, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    
    container.MouseButton1Click:Connect(function()
        Config.AutoJoinSettings[key] = not Config.AutoJoinSettings[key]
        check.Visible = Config.AutoJoinSettings[key]
        if Config.AutoJoinSettings[key] then
            lbl.TextColor3 = THEME.Text
            Tween(box, {BackgroundColor3 = THEME.Accent}, 0.2)
        else
            lbl.TextColor3 = THEME.SubText
            Tween(box, {BackgroundColor3 = THEME.Slider}, 0.2)
        end
        SaveConfig()
    end)
    
    if Config.AutoJoinSettings[key] then
        lbl.TextColor3 = THEME.Text
        box.BackgroundColor3 = THEME.Accent
    end
    
    return container
end

CreateCheckbox("1v1", UDim2.new(0, 15, 0, 88), "_1v1")
CreateCheckbox("4 Player", UDim2.new(0, 110, 0, 88), "_4p")
CreateCheckbox("8 Player", UDim2.new(0, 205, 0, 88), "_8p")

local BlatantBtn = CreateToggle("Blatant Mode: "..(isBlatant and "ON" or "OFF"), UDim2.new(0, 15, 0, 115), function()
    isBlatant = not isBlatant
    Config.Blatant = isBlatant
    return isBlatant, "Blatant Mode: "..(isBlatant and "ON" or "OFF"), isBlatant and Color3.fromRGB(255, 80, 80) or THEME.SubText
end)
BlatantBtn.TextColor3 = isBlatant and Color3.fromRGB(255, 80, 80) or THEME.SubText
BlatantBtn.Size = UDim2.new(0, 130, 0, 24)

local RiskyBtn = CreateToggle("Risky Mistakes: "..(riskyMistakes and "ON" or "OFF"), UDim2.new(0, 150, 0, 115), function()
    riskyMistakes = not riskyMistakes
    Config.RiskyMistakes = riskyMistakes
    return riskyMistakes, "Risky Mistakes: "..(riskyMistakes and "ON" or "OFF"), riskyMistakes and Color3.fromRGB(255, 80, 80) or THEME.SubText
end)
RiskyBtn.TextColor3 = riskyMistakes and Color3.fromRGB(255, 80, 80) or THEME.SubText
RiskyBtn.Size = UDim2.new(0, 130, 0, 24)

local ManageWordsBtn = Instance.new("TextButton", TogglesFrame)
ManageWordsBtn.Text = "Manage Custom Words"
ManageWordsBtn.Font = Enum.Font.GothamMedium
ManageWordsBtn.TextSize = 11
ManageWordsBtn.TextColor3 = THEME.Accent
ManageWordsBtn.BackgroundColor3 = THEME.Background
ManageWordsBtn.Size = UDim2.new(0, 130, 0, 24)
ManageWordsBtn.Position = UDim2.new(0, 15, 0, 145)
Instance.new("UICorner", ManageWordsBtn).CornerRadius = UDim.new(0, 4)

-- GodMode priority editor launcher. Dedicated row below Manage Custom Words / Layout.
ManageWordsBtn.Size = UDim2.new(0, 130, 0, 24)

env.WordHelperGodmodeEditorBtn = Instance.new("TextButton", TogglesFrame)
env.WordHelperGodmodeEditorBtn.Text = "GodMode Priority"
env.WordHelperGodmodeEditorBtn.Font = Enum.Font.GothamMedium
env.WordHelperGodmodeEditorBtn.TextSize = 11
env.WordHelperGodmodeEditorBtn.TextColor3 = THEME.Success
env.WordHelperGodmodeEditorBtn.BackgroundColor3 = THEME.Background
env.WordHelperGodmodeEditorBtn.Size = UDim2.new(0, 265, 0, 24)
env.WordHelperGodmodeEditorBtn.Position = UDim2.new(0, 15, 0, 175)
Instance.new("UICorner", env.WordHelperGodmodeEditorBtn).CornerRadius = UDim.new(0, 4)

local WordBrowserBtn = Instance.new("TextButton", TogglesFrame)
WordBrowserBtn.Text = "Word Browser"
WordBrowserBtn.Font = Enum.Font.GothamMedium
WordBrowserBtn.TextSize = 11
WordBrowserBtn.TextColor3 = Color3.fromRGB(200, 150, 255)
WordBrowserBtn.BackgroundColor3 = THEME.Background
WordBrowserBtn.Size = UDim2.new(0, 265, 0, 24)
WordBrowserBtn.Position = UDim2.new(0, 15, 0, 205)
Instance.new("UICorner", WordBrowserBtn).CornerRadius = UDim.new(0, 4)

local ServerBrowserBtn = Instance.new("TextButton", TogglesFrame)
ServerBrowserBtn.Text = "Server Browser"
ServerBrowserBtn.Font = Enum.Font.GothamMedium
ServerBrowserBtn.TextSize = 11
ServerBrowserBtn.TextColor3 = Color3.fromRGB(100, 200, 255)
ServerBrowserBtn.BackgroundColor3 = THEME.Background
ServerBrowserBtn.Size = UDim2.new(0, 265, 0, 24)
ServerBrowserBtn.Position = UDim2.new(0, 15, 0, 235)
Instance.new("UICorner", ServerBrowserBtn).CornerRadius = UDim.new(0, 4)


env.WordHelperBlacklistBtn = Instance.new("TextButton", TogglesFrame)
env.WordHelperBlacklistBtn.Text = "Rejected Words"
env.WordHelperBlacklistBtn.Font = Enum.Font.GothamMedium
env.WordHelperBlacklistBtn.TextSize = 11
env.WordHelperBlacklistBtn.TextColor3 = THEME.Warning
env.WordHelperBlacklistBtn.BackgroundColor3 = THEME.Background
env.WordHelperBlacklistBtn.Size = UDim2.new(0, 265, 0, 24)
env.WordHelperBlacklistBtn.Position = UDim2.new(0, 15, 0, 295)


env.WordHelperBlacklistLastBtn = Instance.new("TextButton", TogglesFrame)
env.WordHelperBlacklistLastBtn.Text = "Blacklist Last Attempt"
env.WordHelperBlacklistLastBtn.Font = Enum.Font.GothamMedium
env.WordHelperBlacklistLastBtn.TextSize = 11
env.WordHelperBlacklistLastBtn.TextColor3 = Color3.fromRGB(255, 170, 90)
env.WordHelperBlacklistLastBtn.BackgroundColor3 = THEME.Background
env.WordHelperBlacklistLastBtn.Size = UDim2.new(0, 265, 0, 24)
env.WordHelperBlacklistLastBtn.Position = UDim2.new(0, 15, 0, 325)
Instance.new("UICorner", env.WordHelperBlacklistLastBtn).CornerRadius = UDim.new(0, 4)

env.WordHelperBlacklistLastBtn.MouseButton1Click:Connect(function()
    local word = tostring(
        env.WordHelperBlacklistTracker.LastAttempt or ""
    ):lower():gsub("[^a-z]", "")

    if #word < 2 then
        ShowToast("No recent word attempt captured.", "warning")
        return
    end

    if UsedWords[word] then
        ShowToast(
            word .. " was accepted, so it was not blacklisted.",
            "warning"
        )
        return
    end

    if Blacklist[word] then
        ShowToast(word .. " is already blacklisted.", "warning")
        return
    end

    env.WordHelperBlacklistTracker.Add(word, "manual confirmation")
end)
Instance.new("UICorner", env.WordHelperBlacklistBtn).CornerRadius = UDim.new(0, 4)

-- ============================================================
-- GodMode Priority Editor
-- ============================================================
env.WordHelperGodmodeEditor = env.WordHelperGodmodeEditor or {}
env.WordHelperGodmodeEditor.Frame = Instance.new("Frame", ScreenGui)
env.WordHelperGodmodeEditor.Frame.Name = "GodmodePriorityEditor"
env.WordHelperGodmodeEditor.Frame.Size = UDim2.new(0, 360, 0, 500)
env.WordHelperGodmodeEditor.Frame.Position = UDim2.new(0.5, -180, 0.5, -250)
env.WordHelperGodmodeEditor.Frame.BackgroundColor3 = THEME.Background
env.WordHelperGodmodeEditor.Frame.Visible = false
env.WordHelperGodmodeEditor.Frame.ClipsDescendants = true
EnableDragging(env.WordHelperGodmodeEditor.Frame)
Instance.new("UICorner", env.WordHelperGodmodeEditor.Frame).CornerRadius = UDim.new(0, 8)

env.WordHelperGodmodeEditor.Stroke = Instance.new("UIStroke", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.Stroke.Color = THEME.Success
env.WordHelperGodmodeEditor.Stroke.Transparency = 0.45
env.WordHelperGodmodeEditor.Stroke.Thickness = 2

env.WordHelperGodmodeEditor.Title = Instance.new("TextLabel", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.Title.Text = "GodMode Priority Editor"
env.WordHelperGodmodeEditor.Title.Font = Enum.Font.GothamBold
env.WordHelperGodmodeEditor.Title.TextSize = 16
env.WordHelperGodmodeEditor.Title.TextColor3 = THEME.Text
env.WordHelperGodmodeEditor.Title.Size = UDim2.new(1, -50, 0, 38)
env.WordHelperGodmodeEditor.Title.Position = UDim2.new(0, 12, 0, 0)
env.WordHelperGodmodeEditor.Title.BackgroundTransparency = 1
env.WordHelperGodmodeEditor.Title.TextXAlignment = Enum.TextXAlignment.Left

env.WordHelperGodmodeEditor.Close = Instance.new("TextButton", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.Close.Text = "X"
env.WordHelperGodmodeEditor.Close.Font = Enum.Font.GothamBold
env.WordHelperGodmodeEditor.Close.TextSize = 16
env.WordHelperGodmodeEditor.Close.TextColor3 = Color3.fromRGB(255, 100, 100)
env.WordHelperGodmodeEditor.Close.Size = UDim2.new(0, 40, 0, 38)
env.WordHelperGodmodeEditor.Close.Position = UDim2.new(1, -42, 0, 0)
env.WordHelperGodmodeEditor.Close.BackgroundTransparency = 1

env.WordHelperGodmodeEditor.Info = Instance.new("TextLabel", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.Info.Text = "Top = highest priority. Edit endings directly. TRAP/X are special."
env.WordHelperGodmodeEditor.Info.Font = Enum.Font.Gotham
env.WordHelperGodmodeEditor.Info.TextSize = 10
env.WordHelperGodmodeEditor.Info.TextColor3 = THEME.SubText
env.WordHelperGodmodeEditor.Info.Size = UDim2.new(1, -20, 0, 28)
env.WordHelperGodmodeEditor.Info.Position = UDim2.new(0, 10, 0, 38)
env.WordHelperGodmodeEditor.Info.BackgroundTransparency = 1
env.WordHelperGodmodeEditor.Info.TextWrapped = true

env.WordHelperGodmodeEditor.Scroll = Instance.new("ScrollingFrame", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.Scroll.Size = UDim2.new(1, -20, 0, 330)
env.WordHelperGodmodeEditor.Scroll.Position = UDim2.new(0, 10, 0, 70)
env.WordHelperGodmodeEditor.Scroll.BackgroundColor3 = THEME.ItemBG
env.WordHelperGodmodeEditor.Scroll.BorderSizePixel = 0
env.WordHelperGodmodeEditor.Scroll.ScrollBarThickness = 4
env.WordHelperGodmodeEditor.Scroll.ScrollBarImageColor3 = THEME.Accent
env.WordHelperGodmodeEditor.Scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
Instance.new("UICorner", env.WordHelperGodmodeEditor.Scroll).CornerRadius = UDim.new(0, 6)

env.WordHelperGodmodeEditor.Layout = Instance.new("UIListLayout", env.WordHelperGodmodeEditor.Scroll)
env.WordHelperGodmodeEditor.Layout.SortOrder = Enum.SortOrder.LayoutOrder
env.WordHelperGodmodeEditor.Layout.Padding = UDim.new(0, 4)

env.WordHelperGodmodeEditor.AddBox = Instance.new("TextBox", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.AddBox.Size = UDim2.new(0, 205, 0, 28)
env.WordHelperGodmodeEditor.AddBox.Position = UDim2.new(0, 10, 0, 410)
env.WordHelperGodmodeEditor.AddBox.BackgroundColor3 = THEME.ItemBG
env.WordHelperGodmodeEditor.AddBox.TextColor3 = THEME.Text
env.WordHelperGodmodeEditor.AddBox.PlaceholderText = "New ending (example: ging)"
env.WordHelperGodmodeEditor.AddBox.PlaceholderColor3 = THEME.SubText
env.WordHelperGodmodeEditor.AddBox.Text = ""
env.WordHelperGodmodeEditor.AddBox.Font = Enum.Font.Gotham
env.WordHelperGodmodeEditor.AddBox.TextSize = 12
Instance.new("UICorner", env.WordHelperGodmodeEditor.AddBox).CornerRadius = UDim.new(0, 4)

env.WordHelperGodmodeEditor.AddBtn = Instance.new("TextButton", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.AddBtn.Text = "Add Ending"
env.WordHelperGodmodeEditor.AddBtn.Font = Enum.Font.GothamMedium
env.WordHelperGodmodeEditor.AddBtn.TextSize = 11
env.WordHelperGodmodeEditor.AddBtn.TextColor3 = THEME.Success
env.WordHelperGodmodeEditor.AddBtn.BackgroundColor3 = THEME.ItemBG
env.WordHelperGodmodeEditor.AddBtn.Size = UDim2.new(0, 125, 0, 28)
env.WordHelperGodmodeEditor.AddBtn.Position = UDim2.new(0, 225, 0, 410)
Instance.new("UICorner", env.WordHelperGodmodeEditor.AddBtn).CornerRadius = UDim.new(0, 4)

env.WordHelperGodmodeEditor.ResetBtn = Instance.new("TextButton", env.WordHelperGodmodeEditor.Frame)
env.WordHelperGodmodeEditor.ResetBtn.Text = "Reset Default Priority"
env.WordHelperGodmodeEditor.ResetBtn.Font = Enum.Font.GothamMedium
env.WordHelperGodmodeEditor.ResetBtn.TextSize = 11
env.WordHelperGodmodeEditor.ResetBtn.TextColor3 = THEME.Warning
env.WordHelperGodmodeEditor.ResetBtn.BackgroundColor3 = THEME.ItemBG
env.WordHelperGodmodeEditor.ResetBtn.Size = UDim2.new(1, -20, 0, 30)
env.WordHelperGodmodeEditor.ResetBtn.Position = UDim2.new(0, 10, 0, 450)
Instance.new("UICorner", env.WordHelperGodmodeEditor.ResetBtn).CornerRadius = UDim.new(0, 4)

env.WordHelperGodmodeEditor.Commit = function(message)
    Config.GodmodePriority = GodmodeSanitizePriority(Config.GodmodePriority)
    GodmodeReplyAvailabilityCache = {}
    forceUpdateList = true
    lastDetected = "---"
    SaveConfig()
    if UpdateList then UpdateList(lastDetected, lastRequiredLetter) end
    if message and ShowToast then ShowToast(message, "success") end
end

env.WordHelperGodmodeEditor.Refresh = function()
    local scroll = env.WordHelperGodmodeEditor.Scroll
    for _, child in ipairs(scroll:GetChildren()) do
        if child:IsA("Frame") then child:Destroy() end
    end

    for index, category in ipairs(Config.GodmodePriority) do
        local row = Instance.new("Frame", scroll)
        row.Size = UDim2.new(1, -8, 0, 32)
        row.BackgroundColor3 = THEME.Background
        row.BorderSizePixel = 0
        row.LayoutOrder = index
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local number = Instance.new("TextLabel", row)
        number.Size = UDim2.new(0, 25, 1, 0)
        number.BackgroundTransparency = 1
        number.Text = tostring(index) .. "."
        number.TextColor3 = THEME.SubText
        number.Font = Enum.Font.GothamBold
        number.TextSize = 11

        local special = category == "__TRAP__" or category == "__X__"
        local editor
        if special then
            editor = Instance.new("TextLabel", row)
            editor.Text = category == "__TRAP__" and "TRAP" or "X"
            editor.TextColor3 = category == "__TRAP__" and THEME.Success or THEME.Accent
        else
            editor = Instance.new("TextBox", row)
            editor.Text = category
            editor.TextColor3 = THEME.Text
            editor.ClearTextOnFocus = false
        end
        editor.Size = UDim2.new(0, 135, 1, -6)
        editor.Position = UDim2.new(0, 28, 0, 3)
        editor.BackgroundColor3 = special and THEME.Background or THEME.ItemBG
        editor.BackgroundTransparency = special and 1 or 0
        editor.Font = Enum.Font.GothamMedium
        editor.TextSize = 12
        editor.TextXAlignment = Enum.TextXAlignment.Left
        if not special then Instance.new("UICorner", editor).CornerRadius = UDim.new(0, 4) end

        if not special then
            editor.FocusLost:Connect(function()
                local clean = tostring(editor.Text or ""):lower():gsub("[^a-z]", "")
                if #clean == 0 then
                    editor.Text = Config.GodmodePriority[index]
                    ShowToast("Ending cannot be empty.", "warning")
                    return
                end
                for i, existing in ipairs(Config.GodmodePriority) do
                    if i ~= index and existing == clean then
                        editor.Text = Config.GodmodePriority[index]
                        ShowToast("That priority already exists.", "warning")
                        return
                    end
                end
                Config.GodmodePriority[index] = clean
                editor.Text = clean
                env.WordHelperGodmodeEditor.Commit("GodMode ending changed to: " .. clean)
                env.WordHelperGodmodeEditor.Refresh()
            end)
        end

        local up = Instance.new("TextButton", row)
        up.Text = "↑"
        up.Font = Enum.Font.GothamBold
        up.TextSize = 14
        up.TextColor3 = THEME.Text
        up.BackgroundColor3 = THEME.ItemBG
        up.Size = UDim2.new(0, 38, 0, 26)
        up.Position = UDim2.new(0, 170, 0, 3)
        Instance.new("UICorner", up).CornerRadius = UDim.new(0, 4)
        up.MouseButton1Click:Connect(function()
            if index <= 1 then return end
            Config.GodmodePriority[index], Config.GodmodePriority[index - 1] =
                Config.GodmodePriority[index - 1], Config.GodmodePriority[index]
            env.WordHelperGodmodeEditor.Commit()
            env.WordHelperGodmodeEditor.Refresh()
        end)

        local down = Instance.new("TextButton", row)
        down.Text = "↓"
        down.Font = Enum.Font.GothamBold
        down.TextSize = 14
        down.TextColor3 = THEME.Text
        down.BackgroundColor3 = THEME.ItemBG
        down.Size = UDim2.new(0, 38, 0, 26)
        down.Position = UDim2.new(0, 212, 0, 3)
        Instance.new("UICorner", down).CornerRadius = UDim.new(0, 4)
        down.MouseButton1Click:Connect(function()
            if index >= #Config.GodmodePriority then return end
            Config.GodmodePriority[index], Config.GodmodePriority[index + 1] =
                Config.GodmodePriority[index + 1], Config.GodmodePriority[index]
            env.WordHelperGodmodeEditor.Commit()
            env.WordHelperGodmodeEditor.Refresh()
        end)

        local remove = Instance.new("TextButton", row)
        remove.Text = special and "LOCK" or "Remove"
        remove.Font = Enum.Font.GothamMedium
        remove.TextSize = 10
        remove.TextColor3 = special and THEME.SubText or Color3.fromRGB(255, 120, 120)
        remove.BackgroundColor3 = THEME.ItemBG
        remove.Size = UDim2.new(0, 72, 0, 26)
        remove.Position = UDim2.new(1, -76, 0, 3)
        Instance.new("UICorner", remove).CornerRadius = UDim.new(0, 4)
        if not special then
            remove.MouseButton1Click:Connect(function()
                local removed = table.remove(Config.GodmodePriority, index)
                env.WordHelperGodmodeEditor.Commit("Removed ending: " .. tostring(removed))
                env.WordHelperGodmodeEditor.Refresh()
            end)
        end
    end

    env.WordHelperGodmodeEditor.Scroll.CanvasSize =
        UDim2.new(0, 0, 0, env.WordHelperGodmodeEditor.Layout.AbsoluteContentSize.Y + 8)
end

env.WordHelperGodmodeEditor.AddBtn.MouseButton1Click:Connect(function()
    local clean = tostring(env.WordHelperGodmodeEditor.AddBox.Text or ""):lower():gsub("[^a-z]", "")
    if #clean == 0 then
        ShowToast("Enter an ending first.", "warning")
        return
    end
    for _, existing in ipairs(Config.GodmodePriority) do
        if existing == clean then
            ShowToast("That priority already exists.", "warning")
            return
        end
    end

    -- Insert immediately before X when possible, otherwise append.
    local insertAt = #Config.GodmodePriority + 1
    for i, existing in ipairs(Config.GodmodePriority) do
        if existing == "__X__" then
            insertAt = i
            break
        end
    end
    table.insert(Config.GodmodePriority, insertAt, clean)
    env.WordHelperGodmodeEditor.AddBox.Text = ""
    env.WordHelperGodmodeEditor.Commit("Added GodMode ending: " .. clean)
    env.WordHelperGodmodeEditor.Refresh()
end)

env.WordHelperGodmodeEditor.ResetBtn.MouseButton1Click:Connect(function()
    Config.GodmodePriority = {}
    for _, item in ipairs(GodmodeDefaultPriority) do
        table.insert(Config.GodmodePriority, item)
    end
    env.WordHelperGodmodeEditor.Commit("GodMode priority reset to default.")
    env.WordHelperGodmodeEditor.Refresh()
end)

env.WordHelperGodmodeEditor.Close.MouseButton1Click:Connect(function()
    env.WordHelperGodmodeEditor.Frame.Visible = false
end)

env.WordHelperGodmodeEditorBtn.MouseButton1Click:Connect(function()
    env.WordHelperGodmodeEditor.Frame.Visible = not env.WordHelperGodmodeEditor.Frame.Visible
    if env.WordHelperGodmodeEditor.Frame.Visible then
        env.WordHelperGodmodeEditor.Refresh()
    end
end)

env.WordHelperBlacklistFrame = Instance.new("Frame", ScreenGui)
env.WordHelperBlacklistFrame.Name = "RejectedWordsManager"
env.WordHelperBlacklistFrame.Size = UDim2.new(0, 300, 0, 400)
env.WordHelperBlacklistFrame.Position = UDim2.new(0.5, -150, 0.5, -200)
env.WordHelperBlacklistFrame.BackgroundColor3 = THEME.Background
env.WordHelperBlacklistFrame.Visible = false
env.WordHelperBlacklistFrame.ClipsDescendants = true
EnableDragging(env.WordHelperBlacklistFrame)
Instance.new("UICorner", env.WordHelperBlacklistFrame).CornerRadius = UDim.new(0, 8)

env.WordHelperBlacklistStroke = Instance.new("UIStroke", env.WordHelperBlacklistFrame)
env.WordHelperBlacklistStroke.Color = THEME.Warning
env.WordHelperBlacklistStroke.Transparency = 0.5
env.WordHelperBlacklistStroke.Thickness = 2

env.WordHelperBlacklistHeader = Instance.new("TextLabel", env.WordHelperBlacklistFrame)
env.WordHelperBlacklistHeader.Text = "Rejected Words"
env.WordHelperBlacklistHeader.Font = Enum.Font.GothamBold
env.WordHelperBlacklistHeader.TextSize = 16
env.WordHelperBlacklistHeader.TextColor3 = THEME.Text
env.WordHelperBlacklistHeader.Size = UDim2.new(1, -40, 0, 40)
env.WordHelperBlacklistHeader.Position = UDim2.new(0, 10, 0, 0)
env.WordHelperBlacklistHeader.BackgroundTransparency = 1
env.WordHelperBlacklistHeader.TextXAlignment = Enum.TextXAlignment.Left

env.WordHelperBlacklistClose = Instance.new("TextButton", env.WordHelperBlacklistFrame)
env.WordHelperBlacklistClose.Text = "X"
env.WordHelperBlacklistClose.Font = Enum.Font.GothamBold
env.WordHelperBlacklistClose.TextSize = 16
env.WordHelperBlacklistClose.TextColor3 = Color3.fromRGB(255, 100, 100)
env.WordHelperBlacklistClose.Size = UDim2.new(0, 40, 0, 40)
env.WordHelperBlacklistClose.Position = UDim2.new(1, -40, 0, 0)
env.WordHelperBlacklistClose.BackgroundTransparency = 1

env.WordHelperBlacklistSearch = Instance.new("TextBox", env.WordHelperBlacklistFrame)
env.WordHelperBlacklistSearch.Size = UDim2.new(1, -20, 0, 26)
env.WordHelperBlacklistSearch.Position = UDim2.new(0, 10, 0, 42)
env.WordHelperBlacklistSearch.BackgroundColor3 = THEME.ItemBG
env.WordHelperBlacklistSearch.TextColor3 = THEME.Text
env.WordHelperBlacklistSearch.PlaceholderText = "Search rejected words..."
env.WordHelperBlacklistSearch.PlaceholderColor3 = THEME.SubText
env.WordHelperBlacklistSearch.Text = ""
env.WordHelperBlacklistSearch.Font = Enum.Font.Gotham
env.WordHelperBlacklistSearch.TextSize = 12
Instance.new("UICorner", env.WordHelperBlacklistSearch).CornerRadius = UDim.new(0, 4)

env.WordHelperBlacklistScroll = Instance.new("ScrollingFrame", env.WordHelperBlacklistFrame)
env.WordHelperBlacklistScroll.Size = UDim2.new(1, -20, 1, -122)
env.WordHelperBlacklistScroll.Position = UDim2.new(0, 10, 0, 74)
env.WordHelperBlacklistScroll.BackgroundTransparency = 1
env.WordHelperBlacklistScroll.ScrollBarThickness = 3
env.WordHelperBlacklistScroll.ScrollBarImageColor3 = THEME.Warning
env.WordHelperBlacklistScroll.CanvasSize = UDim2.new(0, 0, 0, 0)

env.WordHelperBlacklistLayout = Instance.new("UIListLayout", env.WordHelperBlacklistScroll)
env.WordHelperBlacklistLayout.Padding = UDim.new(0, 3)
env.WordHelperBlacklistLayout.SortOrder = Enum.SortOrder.LayoutOrder


env.WordHelperBlacklistAddBox = Instance.new(
    "TextBox",
    env.WordHelperBlacklistFrame
)
env.WordHelperBlacklistAddBox.Size = UDim2.new(1, -85, 0, 28)
env.WordHelperBlacklistAddBox.Position = UDim2.new(0, 10, 1, -38)
env.WordHelperBlacklistAddBox.BackgroundColor3 = THEME.ItemBG
env.WordHelperBlacklistAddBox.TextColor3 = THEME.Text
env.WordHelperBlacklistAddBox.PlaceholderText = "Add banned word..."
env.WordHelperBlacklistAddBox.PlaceholderColor3 = THEME.SubText
env.WordHelperBlacklistAddBox.Text = ""
env.WordHelperBlacklistAddBox.Font = Enum.Font.Gotham
env.WordHelperBlacklistAddBox.TextSize = 12
env.WordHelperBlacklistAddBox.ClearTextOnFocus = false
Instance.new(
    "UICorner",
    env.WordHelperBlacklistAddBox
).CornerRadius = UDim.new(0, 4)

env.WordHelperBlacklistAddBtn = Instance.new(
    "TextButton",
    env.WordHelperBlacklistFrame
)
env.WordHelperBlacklistAddBtn.Size = UDim2.new(0, 65, 0, 28)
env.WordHelperBlacklistAddBtn.Position = UDim2.new(1, -75, 1, -38)
env.WordHelperBlacklistAddBtn.BackgroundColor3 = THEME.Accent
env.WordHelperBlacklistAddBtn.TextColor3 = THEME.Text
env.WordHelperBlacklistAddBtn.Text = "Add"
env.WordHelperBlacklistAddBtn.Font = Enum.Font.GothamBold
env.WordHelperBlacklistAddBtn.TextSize = 11
Instance.new(
    "UICorner",
    env.WordHelperBlacklistAddBtn
).CornerRadius = UDim.new(0, 4)

env.WordHelperBlacklistTracker.ManualAdd = function()
    local word = tostring(
        env.WordHelperBlacklistAddBox.Text or ""
    ):lower():gsub("[^a-z]", "")

    if #word < 2 then
        ShowToast("Enter a word with at least 2 letters.", "warning")
        return
    end

    if Blacklist[word] then
        ShowToast(word .. " is already rejected.", "warning")
        return
    end

    local added =
        env.WordHelperBlacklistTracker.Add(
            word,
            "manually added rejected word"
        )

    if added then
        env.WordHelperBlacklistAddBox.Text = ""
        env.WordHelperBlacklistTracker.Refresh()
    end
end

env.WordHelperBlacklistAddBtn.MouseButton1Click:Connect(function()
    env.WordHelperBlacklistTracker.ManualAdd()
end)

env.WordHelperBlacklistAddBox.FocusLost:Connect(function(enterPressed)
    if enterPressed then
        env.WordHelperBlacklistTracker.ManualAdd()
    end
end)

env.WordHelperBlacklistTracker.Refresh = function()
    for _, child in ipairs(env.WordHelperBlacklistScroll:GetChildren()) do
        if child:IsA("GuiObject") and child.Name ~= "UIListLayout" then
            child:Destroy()
        end
    end

    local query = env.WordHelperBlacklistSearch.Text:lower():gsub("[^a-z]", "")
    local words = {}
    for word, blocked in pairs(env.WordHelperBlacklistTracker.LiveBlacklist or Blacklist) do
        if blocked and (query == "" or word:find(query, 1, true)) then
            table.insert(words, word)
        end
    end
    table.sort(words)

    for index, word in ipairs(words) do
        local row = Instance.new("Frame", env.WordHelperBlacklistScroll)
        row.Size = UDim2.new(1, -5, 0, 28)
        row.BackgroundColor3 = THEME.ItemBG
        row.LayoutOrder = index
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

        local label = Instance.new("TextLabel", row)
        label.Text = word
        label.Font = Enum.Font.Gotham
        label.TextSize = 12
        label.TextColor3 = THEME.SubText
        label.Size = UDim2.new(1, -75, 1, 0)
        label.Position = UDim2.new(0, 8, 0, 0)
        label.BackgroundTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Left

        local restore = Instance.new("TextButton", row)
        restore.Text = "Restore"
        restore.Font = Enum.Font.GothamBold
        restore.TextSize = 10
        restore.TextColor3 = THEME.Success
        restore.BackgroundTransparency = 1
        restore.Size = UDim2.new(0, 65, 1, 0)
        restore.Position = UDim2.new(1, -68, 0, 0)
        restore.MouseButton1Click:Connect(function()
            env.WordHelperBlacklistTracker.Remove(word)
        end)
    end

    env.WordHelperBlacklistHeader.Text = "Rejected Words (" .. #words .. ")"
    env.WordHelperBlacklistScroll.CanvasSize =
        UDim2.new(0, 0, 0, env.WordHelperBlacklistLayout.AbsoluteContentSize.Y + 5)
end

env.WordHelperBlacklistBtn.MouseButton1Click:Connect(function()
    env.WordHelperBlacklistFrame.Visible = not env.WordHelperBlacklistFrame.Visible
    if env.WordHelperBlacklistFrame.Visible then
        env.WordHelperBlacklistTracker.Refresh()
    end
end)

env.WordHelperBlacklistClose.MouseButton1Click:Connect(function()
    env.WordHelperBlacklistFrame.Visible = false
end)

env.WordHelperBlacklistSearch:GetPropertyChangedSignal("Text"):Connect(function()
    env.WordHelperBlacklistTracker.Refresh()
end)

local CustomWordsFrame = Instance.new("Frame", ScreenGui)
CustomWordsFrame.Name = "CustomWordsFrame"
CustomWordsFrame.Size = UDim2.new(0, 250, 0, 350)
CustomWordsFrame.Position = UDim2.new(0.5, -125, 0.5, -175)
CustomWordsFrame.BackgroundColor3 = THEME.Background
CustomWordsFrame.Visible = false
CustomWordsFrame.ClipsDescendants = true
EnableDragging(CustomWordsFrame)
Instance.new("UICorner", CustomWordsFrame).CornerRadius = UDim.new(0, 8)
local CWStroke = Instance.new("UIStroke", CustomWordsFrame)
CWStroke.Color = THEME.Accent
CWStroke.Transparency = 0.5
CWStroke.Thickness = 2

local CWHeader = Instance.new("TextLabel", CustomWordsFrame)
CWHeader.Text = "Custom Words Manager"
CWHeader.Font = Enum.Font.GothamBold
CWHeader.TextSize = 14
CWHeader.TextColor3 = THEME.Text
CWHeader.Size = UDim2.new(1, 0, 0, 35)
CWHeader.BackgroundTransparency = 1

local CWCloseBtn = Instance.new("TextButton", CustomWordsFrame)
CWCloseBtn.Text = "X"
CWCloseBtn.Font = Enum.Font.GothamBold
CWCloseBtn.TextSize = 14
CWCloseBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
CWCloseBtn.Size = UDim2.new(0, 30, 0, 30)
CWCloseBtn.Position = UDim2.new(1, -30, 0, 2)
CWCloseBtn.BackgroundTransparency = 1
CWCloseBtn.MouseButton1Click:Connect(function() CustomWordsFrame.Visible = false end)

ManageWordsBtn.MouseButton1Click:Connect(function()
    CustomWordsFrame.Visible = not CustomWordsFrame.Visible
    CustomWordsFrame.Parent = nil
    CustomWordsFrame.Parent = ScreenGui
end)

local function SetupPhantomBox(box, placeholder)
    box.Text = placeholder
    box.TextColor3 = THEME.SubText
    
    box.Focused:Connect(function()
        if box.Text == placeholder then
            box.Text = ""
            box.TextColor3 = THEME.Text
        end
    end)
    
    box.FocusLost:Connect(function()
        if box.Text == "" then
            box.Text = placeholder
            box.TextColor3 = THEME.SubText
        end
    end)
end

local CWSearchBox = Instance.new("TextBox", CustomWordsFrame)
CWSearchBox.Font = Enum.Font.Gotham
CWSearchBox.TextSize = 12
CWSearchBox.BackgroundColor3 = THEME.ItemBG
CWSearchBox.Size = UDim2.new(1, -20, 0, 24)
CWSearchBox.Position = UDim2.new(0, 10, 0, 35)
Instance.new("UICorner", CWSearchBox).CornerRadius = UDim.new(0, 4)
SetupPhantomBox(CWSearchBox, "Search words...")

local CWScroll = Instance.new("ScrollingFrame", CustomWordsFrame)
CWScroll.Size = UDim2.new(1, -10, 1, -110)
CWScroll.Position = UDim2.new(0, 5, 0, 65)
CWScroll.BackgroundTransparency = 1
CWScroll.ScrollBarThickness = 2
CWScroll.ScrollBarImageColor3 = THEME.Accent
CWScroll.CanvasSize = UDim2.new(0,0,0,0)

local CWListLayout = Instance.new("UIListLayout", CWScroll)
CWListLayout.SortOrder = Enum.SortOrder.LayoutOrder
CWListLayout.Padding = UDim.new(0, 2)

local CWAddBox = Instance.new("TextBox", CustomWordsFrame)
CWAddBox.Font = Enum.Font.Gotham
CWAddBox.TextSize = 12
CWAddBox.BackgroundColor3 = THEME.ItemBG
CWAddBox.Size = UDim2.new(0, 170, 0, 24)
CWAddBox.Position = UDim2.new(0, 10, 1, -35)
Instance.new("UICorner", CWAddBox).CornerRadius = UDim.new(0, 4)
SetupPhantomBox(CWAddBox, "Add new word...")

local CWAddBtn = Instance.new("TextButton", CustomWordsFrame)
CWAddBtn.Text = "Add"
CWAddBtn.Font = Enum.Font.GothamBold
CWAddBtn.TextSize = 11
CWAddBtn.TextColor3 = THEME.Success
CWAddBtn.BackgroundColor3 = THEME.ItemBG
CWAddBtn.Size = UDim2.new(0, 50, 0, 24)
CWAddBtn.Position = UDim2.new(1, -60, 1, -35)
Instance.new("UICorner", CWAddBtn).CornerRadius = UDim.new(0, 4)

local function RefreshCustomWords()
    for _, c in ipairs(CWScroll:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    
    local queryRaw = CWSearchBox.Text
    local query = (queryRaw == "Search words...") and "" or queryRaw:lower():gsub("[%s%c]+", "")
    
    local list = Config.CustomWords or {}
    local shownCount = 0
    
    for i, w in ipairs(list) do
        if query == "" or w:find(query, 1, true) then
            shownCount = shownCount + 1
            local row = Instance.new("TextButton", CWScroll)
            row.Size = UDim2.new(1, -6, 0, 22)
            row.BackgroundColor3 = (shownCount % 2 == 0) and Color3.fromRGB(25,25,30) or Color3.fromRGB(30,30,35)
            row.BorderSizePixel = 0
            row.Text = ""
            row.AutoButtonColor = false
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
            
            row.MouseButton1Click:Connect(function()
                SmartType(w, lastDetected, true, true)
                Tween(row, {BackgroundColor3 = THEME.Accent}, 0.2)
                task.delay(0.2, function()
                     Tween(row, {BackgroundColor3 = (shownCount % 2 == 0) and Color3.fromRGB(25,25,30) or Color3.fromRGB(30,30,35)}, 0.2)
                end)
            end)
            
            local lbl = Instance.new("TextLabel", row)
            lbl.Text = w
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 12
            lbl.TextColor3 = THEME.Text
            lbl.Size = UDim2.new(1, -30, 1, 0)
            lbl.Position = UDim2.new(0, 5, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.TextXAlignment = Enum.TextXAlignment.Left

            -- Removed nested invisible button to fix click handling
            
            local del = Instance.new("TextButton", row)
            del.Text = "X"
            del.Font = Enum.Font.GothamBold
            del.TextSize = 11
            del.TextColor3 = Color3.fromRGB(255, 80, 80)
            del.Size = UDim2.new(0, 22, 1, 0)
            del.Position = UDim2.new(1, -22, 0, 0)
            del.BackgroundTransparency = 1
            
            del.MouseButton1Click:Connect(function()
                table.remove(Config.CustomWords, i)
                SaveConfig()
                Blacklist[w] = true
                RefreshCustomWords()
                ShowToast("Removed: " .. w, "warning")
            end)
        end
    end
    CWScroll.CanvasSize = UDim2.new(0, 0, 0, shownCount * 24)
end

CWSearchBox:GetPropertyChangedSignal("Text"):Connect(RefreshCustomWords)

CWAddBtn.MouseButton1Click:Connect(function()
    local text = CWAddBox.Text
    if text == "Add new word..." then return end
    
    text = text:gsub("[%s%c]+", ""):lower()
    if #text < 2 then return end
    
    if not Config.CustomWords then Config.CustomWords = {} end
    
    for _, w in ipairs(Config.CustomWords) do
        if w == text then
            ShowToast("Word already in custom list!", "warning")
            return
        end
    end
    
    local existsInMain = WordHelperKnownWords[text] == true
    local c = text:sub(1,1)
    
    if existsInMain then
         ShowToast("Word already in main dictionary!", "error")
         return
    end

    table.insert(Config.CustomWords, text)
    SaveConfig()
    
    WordHelperKnownWords[text] = true
    table.insert(Words, text)
    if c == "" then c = "#" end
    Buckets[c] = Buckets[c] or {}
    table.insert(Buckets[c], text)
    -- Keep dictionary indexes sorted so prefix binary-search remains reliable.
    table.sort(Words)
    table.sort(Buckets[c])
    
    CWAddBox.Text = ""
    CWAddBox:ReleaseFocus()
    RefreshCustomWords()
    ShowToast("Added custom word: " .. text, "success")
end)

RefreshCustomWords()

local ServerFrame = Instance.new("Frame", ScreenGui)
ServerFrame.Name = "ServerBrowser"
ServerFrame.Size = UDim2.new(0, 350, 0, 400)
ServerFrame.Position = UDim2.new(0.5, -175, 0.5, -200)
ServerFrame.BackgroundColor3 = THEME.Background
ServerFrame.Visible = false
ServerFrame.ClipsDescendants = true
EnableDragging(ServerFrame)
Instance.new("UICorner", ServerFrame).CornerRadius = UDim.new(0, 8)
local SBStroke = Instance.new("UIStroke", ServerFrame)
SBStroke.Color = THEME.Accent
SBStroke.Transparency = 0.5
SBStroke.Thickness = 2

local SBHeader = Instance.new("TextLabel", ServerFrame)
SBHeader.Text = "Server Browser"
SBHeader.Font = Enum.Font.GothamBold
SBHeader.TextSize = 16
SBHeader.TextColor3 = THEME.Text
SBHeader.Size = UDim2.new(1, 0, 0, 40)
SBHeader.BackgroundTransparency = 1

local SBClose = Instance.new("TextButton", ServerFrame)
SBClose.Text = "X"
SBClose.Font = Enum.Font.GothamBold
SBClose.TextSize = 16
SBClose.TextColor3 = Color3.fromRGB(255, 100, 100)
SBClose.Size = UDim2.new(0, 40, 0, 40)
SBClose.Position = UDim2.new(1, -40, 0, 0)
SBClose.BackgroundTransparency = 1
SBClose.MouseButton1Click:Connect(function() ServerFrame.Visible = false end)

local SBList = Instance.new("ScrollingFrame", ServerFrame)
SBList.Size = UDim2.new(1, -20, 1, -90)
SBList.Position = UDim2.new(0, 10, 0, 50)
SBList.BackgroundTransparency = 1
SBList.ScrollBarThickness = 3
SBList.ScrollBarImageColor3 = THEME.Accent

local SBLayout = Instance.new("UIListLayout", SBList)
SBLayout.Padding = UDim.new(0, 5)
SBLayout.SortOrder = Enum.SortOrder.LayoutOrder

local ServerSortMode = "Smallest"

local SBSortBtn = Instance.new("TextButton", ServerFrame)
SBSortBtn.Text = "Sort: Smallest"
SBSortBtn.Font = Enum.Font.GothamBold
SBSortBtn.TextSize = 12
SBSortBtn.BackgroundColor3 = THEME.ItemBG
SBSortBtn.TextColor3 = THEME.SubText
SBSortBtn.Size = UDim2.new(0.5, -15, 0, 30)
SBSortBtn.Position = UDim2.new(0, 10, 1, -40)
Instance.new("UICorner", SBSortBtn).CornerRadius = UDim.new(0, 6)

local SBRefresh = Instance.new("TextButton", ServerFrame)
SBRefresh.Text = "Refresh"
SBRefresh.Font = Enum.Font.GothamBold
SBRefresh.TextSize = 12
SBRefresh.BackgroundColor3 = THEME.Accent
SBRefresh.Size = UDim2.new(0.5, -15, 0, 30)
SBRefresh.Position = UDim2.new(0.5, 5, 1, -40)
Instance.new("UICorner", SBRefresh).CornerRadius = UDim.new(0, 6)

local function FetchServers()
    SBRefresh.Text = "..."
    
    for _, c in ipairs(SBList:GetChildren()) do
        if c:IsA("Frame") then c:Destroy() end
    end
    
    task.spawn(function()
        local success, result = pcall(function()
            return request({
                Url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100",
                Method = "GET"
            })
        end)
        
        if success and result and result.Body then
            local data = HttpService:JSONDecode(result.Body)
            if data and data.data then
                local servers = data.data
                
                if ServerSortMode == "Smallest" then
                    table.sort(servers, function(a,b) return (a.playing or 0) < (b.playing or 0) end)
                else
                    table.sort(servers, function(a,b) return (a.playing or 0) > (b.playing or 0) end)
                end
                
                for _, srv in ipairs(servers) do
                    if srv.playing and srv.maxPlayers and srv.id ~= game.JobId then
                        local row = Instance.new("Frame", SBList)
                        row.Size = UDim2.new(1, -6, 0, 45)
                        row.BackgroundColor3 = THEME.ItemBG
                        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
                        
                        local info = Instance.new("TextLabel", row)
                        info.Text = "Players: " .. srv.playing .. " / " .. srv.maxPlayers .. "\nPing: " .. (srv.ping or "?") .. "ms"
                        info.Size = UDim2.new(0.6, 0, 1, 0)
                        info.Position = UDim2.new(0, 10, 0, 0)
                        info.BackgroundTransparency = 1
                        info.TextColor3 = THEME.Text
                        info.Font = Enum.Font.Gotham
                        info.TextSize = 12
                        info.TextXAlignment = Enum.TextXAlignment.Left
                        
                        local join = Instance.new("TextButton", row)
                        join.Text = "Join"
                        join.BackgroundColor3 = Color3.fromRGB(100, 200, 100)
                        join.Size = UDim2.new(0, 80, 0, 25)
                        join.Position = UDim2.new(1, -90, 0.5, -12.5)
                        join.Font = Enum.Font.GothamBold
                        join.TextSize = 12
                        join.TextColor3 = Color3.fromRGB(255,255,255)
                        Instance.new("UICorner", join).CornerRadius = UDim.new(0, 4)
                        
                        join.MouseButton1Click:Connect(function()
                            join.Text = "Joining..."
                            ShowToast("Teleporting...", "success")
                            
                            -- Reload this exact saved WordHelper version after teleport.
                            if queue_on_teleport then
                                queue_on_teleport([[
                                    task.wait(2)
                                    local ok, err = pcall(function()
                                        if isfile and isfile("WordHelper_Current.lua") then
                                            local source = readfile("WordHelper_Current.lua")
                                            local compiled, compileError = loadstring(source)
                                            if not compiled then
                                                error("WordHelper compile failed: " .. tostring(compileError))
                                            end
                                            compiled()
                                        else
                                            error("WordHelper_Current.lua was not found")
                                        end
                                    end)
                                    if not ok then
                                        warn("WordHelper teleport reload failed:", err)
                                    end
                                ]])
                            end

                            task.spawn(function()
                                local success, err = pcall(function()
                                    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, srv.id, Players.LocalPlayer)
                                end)
                                if not success then
                                    join.Text = "Failed"
                                    ShowToast("Teleport Failed: " .. tostring(err), "error")
                                    task.wait(2)
                                    join.Text = "Join"
                                end
                            end)
                        end)
                    end
                end
                
                SBList.CanvasSize = UDim2.new(0,0,0, SBLayout.AbsoluteContentSize.Y)
            end
        else
            ShowToast("Failed to fetch servers", "error")
        end
        SBRefresh.Text = "Refresh"
    end)
end

SBSortBtn.MouseButton1Click:Connect(function()
    if ServerSortMode == "Smallest" then
        ServerSortMode = "Largest"
    else
        ServerSortMode = "Smallest"
    end
    SBSortBtn.Text = "Sort: " .. ServerSortMode
    FetchServers()
end)

SBRefresh.MouseButton1Click:Connect(FetchServers)

ServerBrowserBtn.MouseButton1Click:Connect(function()
    ServerFrame.Visible = not ServerFrame.Visible
    ServerFrame.Parent = nil
    ServerFrame.Parent = ScreenGui
    
    if ServerFrame.Visible then
        FetchServers()
    end
end)

do
    local WordBrowserFrame = Instance.new("Frame", ScreenGui)
    WordBrowserFrame.Name = "WordBrowser"
    WordBrowserFrame.Size = UDim2.new(0, 300, 0, 400)
    WordBrowserFrame.Position = UDim2.new(0.5, -150, 0.5, -200)
    WordBrowserFrame.BackgroundColor3 = THEME.Background
    WordBrowserFrame.Visible = false
    WordBrowserFrame.ClipsDescendants = true
    EnableDragging(WordBrowserFrame)
    Instance.new("UICorner", WordBrowserFrame).CornerRadius = UDim.new(0, 8)
    local WBStroke = Instance.new("UIStroke", WordBrowserFrame)
    WBStroke.Color = THEME.Accent
    WBStroke.Transparency = 0.5
    WBStroke.Thickness = 2

    local WBHeader = Instance.new("TextLabel", WordBrowserFrame)
    WBHeader.Text = "Word Browser"
    WBHeader.Font = Enum.Font.GothamBold
    WBHeader.TextSize = 16
    WBHeader.TextColor3 = THEME.Text
    WBHeader.Size = UDim2.new(1, 0, 0, 40)
    WBHeader.BackgroundTransparency = 1

    local WBClose = Instance.new("TextButton", WordBrowserFrame)
    WBClose.Text = "X"
    WBClose.Font = Enum.Font.GothamBold
    WBClose.TextSize = 16
    WBClose.TextColor3 = Color3.fromRGB(255, 100, 100)
    WBClose.Size = UDim2.new(0, 40, 0, 40)
    WBClose.Position = UDim2.new(1, -40, 0, 0)
    WBClose.BackgroundTransparency = 1
    WBClose.MouseButton1Click:Connect(function() WordBrowserFrame.Visible = false end)

    local WBStartBox = Instance.new("TextBox", WordBrowserFrame)
    WBStartBox.Font = Enum.Font.Gotham
    WBStartBox.TextSize = 12
    WBStartBox.BackgroundColor3 = THEME.ItemBG
    WBStartBox.Size = UDim2.new(0.4, 0, 0, 24)
    WBStartBox.Position = UDim2.new(0, 10, 0, 45)
    Instance.new("UICorner", WBStartBox).CornerRadius = UDim.new(0, 4)
    SetupPhantomBox(WBStartBox, "Starts with...")

    local WBEndBox = Instance.new("TextBox", WordBrowserFrame)
    WBEndBox.Font = Enum.Font.Gotham
    WBEndBox.TextSize = 12
    WBEndBox.BackgroundColor3 = THEME.ItemBG
    WBEndBox.Size = UDim2.new(0.4, 0, 0, 24)
    WBEndBox.Position = UDim2.new(0.45, 0, 0, 45)
    Instance.new("UICorner", WBEndBox).CornerRadius = UDim.new(0, 4)
    SetupPhantomBox(WBEndBox, "Ends with...")

    local WBLengthBox = Instance.new("TextBox", WordBrowserFrame)
    WBLengthBox.Font = Enum.Font.Gotham
    WBLengthBox.TextSize = 12
    WBLengthBox.BackgroundColor3 = THEME.ItemBG
    WBLengthBox.Size = UDim2.new(0.2, 0, 0, 24)
    WBLengthBox.Position = UDim2.new(0.02, 0, 0, 80)
    Instance.new("UICorner", WBLengthBox).CornerRadius = UDim.new(0, 4)
    SetupPhantomBox(WBLengthBox, "Len...")

    -- Add custom dictionary words directly from the Word Browser.
    local WBAddWordBox = Instance.new("TextBox", WordBrowserFrame)
    WBAddWordBox.Font = Enum.Font.Gotham
    WBAddWordBox.TextSize = 12
    WBAddWordBox.BackgroundColor3 = THEME.ItemBG
    WBAddWordBox.Size = UDim2.new(0.48, 0, 0, 24)
    WBAddWordBox.Position = UDim2.new(0.25, 0, 0, 80)
    WBAddWordBox.TextColor3 = THEME.Text
    Instance.new("UICorner", WBAddWordBox).CornerRadius = UDim.new(0, 4)
    SetupPhantomBox(WBAddWordBox, "Add new word...")

    local WBAddWordBtn = Instance.new("TextButton", WordBrowserFrame)
    WBAddWordBtn.Text = "Add Word"
    WBAddWordBtn.Font = Enum.Font.GothamBold
    WBAddWordBtn.TextSize = 10
    WBAddWordBtn.TextColor3 = THEME.Success
    WBAddWordBtn.BackgroundColor3 = THEME.ItemBG
    WBAddWordBtn.Size = UDim2.new(0.22, 0, 0, 24)
    WBAddWordBtn.Position = UDim2.new(0.75, 0, 0, 80)
    Instance.new("UICorner", WBAddWordBtn).CornerRadius = UDim.new(0, 4)

    local WBSearchBtn = Instance.new("TextButton", WordBrowserFrame)
    WBSearchBtn.Text = "Go"
    WBSearchBtn.Font = Enum.Font.GothamBold
    WBSearchBtn.TextSize = 12
    WBSearchBtn.BackgroundColor3 = THEME.Accent
    WBSearchBtn.Size = UDim2.new(0.1, 0, 0, 24)
    WBSearchBtn.Position = UDim2.new(0.88, 0, 0, 45)
    Instance.new("UICorner", WBSearchBtn).CornerRadius = UDim.new(0, 4)

    local WBList = Instance.new("ScrollingFrame", WordBrowserFrame)
    WBList.Size = UDim2.new(1, -20, 1, -160)
    WBList.Position = UDim2.new(0, 10, 0, 115)
    WBList.BackgroundTransparency = 1
    WBList.ScrollBarThickness = 3
    WBList.ScrollBarImageColor3 = THEME.Accent
    WBList.CanvasSize = UDim2.new(0,0,0,0)

    local WBLayout = Instance.new("UIListLayout", WBList)
    WBLayout.Padding = UDim.new(0, 2)
    WBLayout.SortOrder = Enum.SortOrder.LayoutOrder


    local function SearchWords()
        for _, c in ipairs(WBList:GetChildren()) do
            if c:IsA("GuiObject") and c.Name ~= "UIListLayout" then c:Destroy() end
        end
        
        local sVal = WBStartBox.Text
        local eVal = WBEndBox.Text
        local lVal = tonumber(WBLengthBox.Text)
        
        if sVal == "Starts with..." then sVal = "" end
        if eVal == "Ends with..." then eVal = "" end
        
        sVal = sVal:lower():gsub("[%s%c]+", "")
        eVal = eVal:lower():gsub("[%s%c]+", "")
        
        
        -- Word Browser filters are intentionally local to this window.
        -- Searching here must never change the main WordHelper suffix/length
        -- filters or act as a hidden refresh/reset for the gameplay list.

        if sVal == "" and eVal == "" and not lVal then return end
        
        local results = {}
        local limit = 200
        
        local bucket = Words
        if sVal ~= "" then
            local c = sVal:sub(1,1)
            if Buckets and Buckets[c] then
                bucket = Buckets[c]
            end
        end
        
        for _, w in ipairs(bucket) do
            local matchStart = (sVal == "") or (w:sub(1, #sVal) == sVal)
            -- We can use the global vars now or local, doesn't matter much for this loop
            local matchEnd = (eVal == "") or (w:sub(-#eVal) == eVal)
            local matchLen = (not lVal) or (#w == lVal)
            
            if matchStart and matchEnd and matchLen then
                table.insert(results, w)
                if #results >= limit then break end
            end
        end
        
        for i, w in ipairs(results) do
            local row = Instance.new("TextButton", WBList)
            row.Size = UDim2.new(1, -6, 0, 24)
            row.Text = ""
            row.AutoButtonColor = false
            Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)

            local lbl = Instance.new("TextLabel", row)
            lbl.Text = w
            lbl.Font = Enum.Font.Gotham
            lbl.TextSize = 11
            lbl.Size = UDim2.new(1, -170, 1, 0)
            lbl.Position = UDim2.new(0, 5, 0, 0)
            lbl.BackgroundTransparency = 1
            lbl.TextXAlignment = Enum.TextXAlignment.Left

            local trapBtn = Instance.new("TextButton", row)
            trapBtn.Size = UDim2.new(0, 72, 0, 18)
            trapBtn.Position = UDim2.new(1, -154, 0.5, -9)
            trapBtn.BackgroundColor3 = THEME.Background
            trapBtn.Font = Enum.Font.GothamBold
            trapBtn.TextSize = 8
            trapBtn.AutoButtonColor = true
            Instance.new("UICorner", trapBtn).CornerRadius = UDim.new(0, 4)

            local blacklistBtn = Instance.new("TextButton", row)
            blacklistBtn.Size = UDim2.new(0, 76, 0, 18)
            blacklistBtn.Position = UDim2.new(1, -78, 0.5, -9)
            blacklistBtn.BackgroundColor3 = THEME.Background
            blacklistBtn.Font = Enum.Font.GothamBold
            blacklistBtn.TextSize = 8
            blacklistBtn.AutoButtonColor = true
            Instance.new("UICorner", blacklistBtn).CornerRadius = UDim.new(0, 4)

            local function RefreshBrowserWordState()
                local baseColor =
                    (i % 2 == 0)
                    and Color3.fromRGB(25,25,30)
                    or Color3.fromRGB(30,30,35)

                if Blacklist[w] then
                    row.BackgroundColor3 = Color3.fromRGB(58, 26, 30)
                    lbl.TextColor3 = Color3.fromRGB(255, 105, 105)
                    lbl.Text = w .. "  [BLACKLISTED]"
                    blacklistBtn.Text = "RESTORE"
                    blacklistBtn.TextColor3 = THEME.Success
                else
                    row.BackgroundColor3 = baseColor
                    lbl.TextColor3 = THEME.Text
                    lbl.Text = w
                    blacklistBtn.Text = "BLACKLIST"
                    blacklistBtn.TextColor3 = Color3.fromRGB(255, 100, 100)
                end
            end

            local function RefreshTrapButton()
                if CustomTrapWords[w] then
                    trapBtn.Text = "UNMARK"
                    trapBtn.TextColor3 = THEME.Warning
                elseif TrapWordPriority[w] then
                    trapBtn.Text = "BUILT-IN"
                    trapBtn.TextColor3 = THEME.SubText
                else
                    trapBtn.Text = "MARK TRAP"
                    trapBtn.TextColor3 = THEME.Success
                end
            end

            RefreshTrapButton()
            RefreshBrowserWordState()

            row.MouseButton1Click:Connect(function()
                if Blacklist[w] then
                    ShowToast(w .. " is blacklisted. Restore it first to type it.", "warning")
                    return
                end

                SmartType(w, lastDetected, true, true)
                Tween(row, {BackgroundColor3 = THEME.Accent}, 0.2)
                task.delay(0.2, function()
                    if row and row.Parent then
                        RefreshBrowserWordState()
                    end
                end)
            end)

            trapBtn.MouseButton1Click:Connect(function()
                if TrapWordPriority[w] and not CustomTrapWords[w] then
                    ShowToast(w .. " is already a built-in trap.", "warning")
                    return
                end

                if CustomTrapWords[w] then
                    env.WordHelperCustomTraps.Remove(w)
                else
                    env.WordHelperCustomTraps.Add(w)
                end

                RefreshTrapButton()
            end)

            blacklistBtn.MouseButton1Click:Connect(function()
                if Blacklist[w] then
                    env.WordHelperBlacklistTracker.Remove(w)
                else
                    env.WordHelperBlacklistTracker.Add(w, "manual Word Browser")
                end

                RefreshBrowserWordState()
            end)

            -- Blacklisted words intentionally remain visible in the browser.
        end

        WBList.CanvasSize = UDim2.new(0,0,0, WBLayout.AbsoluteContentSize.Y)
    end

    local function AddWordFromBrowser()
        local raw = tostring(WBAddWordBox.Text or "")
        if raw == "" or raw == "Add new word..." then return end

        local word = raw:lower():gsub("[%s%c]+", "")
        if #word < 2 then
            ShowToast("Custom words must be at least 2 letters.", "warning")
            return
        end
        if not word:match("^[a-z]+$") then
            ShowToast("Use letters A-Z only when adding a word.", "warning")
            return
        end

        local first = word:sub(1, 1)
        if WordHelperKnownWords[word] then
            ShowToast(word .. " is already in the dictionary.", "warning")
            return
        end

        Config.CustomWords = Config.CustomWords or {}
        for _, existing in ipairs(Config.CustomWords) do
            if existing == word then
                ShowToast(word .. " is already in your custom words.", "warning")
                return
            end
        end

        table.insert(Config.CustomWords, word)
        WordHelperKnownWords[word] = true
        table.insert(Words, word)
        Buckets[first] = Buckets[first] or {}
        table.insert(Buckets[first], word)

        -- Prefix search uses binary search, so custom additions must preserve sorting.
        table.sort(Words)
        table.sort(Buckets[first])

        SaveConfig()
        GodmodeReplyAvailabilityCache = {}
        forceUpdateList = true
        lastDetected = "---"

        WBAddWordBox.Text = ""
        WBAddWordBox:ReleaseFocus()
        if RefreshCustomWords then RefreshCustomWords() end
        if UpdateList then UpdateList(cachedDetected or "", lastRequiredLetter) end

        ShowToast("Added to dictionary: " .. word, "success")
    end

    WBAddWordBtn.MouseButton1Click:Connect(AddWordFromBrowser)
    WBAddWordBox.FocusLost:Connect(function(enter)
        if enter then AddWordFromBrowser() end
    end)

    WBSearchBtn.MouseButton1Click:Connect(SearchWords)
    WBStartBox.FocusLost:Connect(function(enter) if enter then SearchWords() end end)
    WBEndBox.FocusLost:Connect(function(enter) if enter then SearchWords() end end)
    WBLengthBox.FocusLost:Connect(function(enter) if enter then SearchWords() end end)

    env.WordHelperDiscovery.OpenButton = Instance.new("TextButton", WordBrowserFrame)
    env.WordHelperDiscovery.OpenButton.Size = UDim2.new(0, 150, 0, 26)
    env.WordHelperDiscovery.OpenButton.Position = UDim2.new(1, -160, 1, -34)
    env.WordHelperDiscovery.OpenButton.BackgroundColor3 = THEME.ItemBG
    env.WordHelperDiscovery.OpenButton.TextColor3 = THEME.Accent
    env.WordHelperDiscovery.OpenButton.Font = Enum.Font.GothamBold
    env.WordHelperDiscovery.OpenButton.TextSize = 10
    Instance.new("UICorner", env.WordHelperDiscovery.OpenButton).CornerRadius = UDim.new(0, 4)
    env.WordHelperDiscovery.OpenButton.MouseButton1Click:Connect(function()
        env.WordHelperDiscovery.BuildUI()
        env.WordHelperDiscovery.RefreshUI()
        env.WordHelperDiscovery.Frame.Visible = true
        env.WordHelperDiscovery.Frame.Parent = nil
        env.WordHelperDiscovery.Frame.Parent = ScreenGui
    end)
    env.WordHelperDiscovery.RefreshButton()

    WordBrowserBtn.MouseButton1Click:Connect(function()
        WordBrowserFrame.Visible = not WordBrowserFrame.Visible
        WordBrowserFrame.Parent = nil
        WordBrowserFrame.Parent = ScreenGui
    end)
end

local function CalculateDelay()
    local charsPerMin = currentCPM
    local baseDelay = 60 / charsPerMin
    local variance = baseDelay * 0.4
    return useHumanization and (baseDelay + math.random()*variance - (variance/2)) or baseDelay
end

local KEY_POS = {}
do
    local row1 = "qwertyuiop"
    local row2 = "asdfghjkl"
    local row3 = "zxcvbnm"
    for i = 1, #row1 do
        KEY_POS[row1:sub(i,i)] = {x = i, y = 1}
    end
    for i = 1, #row2 do
        KEY_POS[row2:sub(i,i)] = {x = i + 0.5, y = 2}
    end
    for i = 1, #row3 do
        KEY_POS[row3:sub(i,i)] = {x = i + 1, y = 3}
    end
end

local function KeyDistance(a, b)
    if not a or not b then return 1 end
    a = a:lower()
    b = b:lower()
    local pa = KEY_POS[a]
    local pb = KEY_POS[b]
    if not pa or not pb then return 1 end
    local dx = pa.x - pb.x
    local dy = pa.y - pb.y
    return math.sqrt(dx*dx + dy*dy)
end

local lastKey = nil
local function CalculateDelayForKeys(prevChar, nextChar)
    if isBlatant then 
        return 60 / currentCPM 
    end

    local charsPerMin = currentCPM
    local baseDelay = 60 / charsPerMin
    
    local variance = baseDelay * 0.35
    local extra = 0
    
    if useHumanization and useFingerModel and prevChar and nextChar and prevChar ~= "" then
        local dist = KeyDistance(prevChar, nextChar)
        extra = dist * 0.018 * (550 / math.max(150, currentCPM))
        
        local pa = KEY_POS[prevChar:lower()]
        local pb = KEY_POS[nextChar:lower()]
        if pa and pb then
            if (pa.x <= 5 and pb.x <= 5) or (pa.x > 5 and pb.x > 5) then
                extra = extra * 0.8
            end
        end
    end

    if useHumanization then
        local r = (math.random() + math.random() + math.random()) / 3
        local noise = (r * 2 - 1) * variance
        return math.max(0.005, baseDelay + extra + noise)
    else
        return baseDelay
    end
end

local VirtualUser = game:GetService("VirtualUser")
local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function GetKeyCode(char)
    local layout = Config.KeyboardLayout or "QWERTY"
    
    if type(char) == "string" and #char == 1 then
        char = char:lower()
        if layout == "QWERTZ" then
            if char == "z" then return Enum.KeyCode.Y end
            if char == "y" then return Enum.KeyCode.Z end
        elseif layout == "AZERTY" then
            if char == "a" then return Enum.KeyCode.Q end
            if char == "q" then return Enum.KeyCode.A end
            if char == "z" then return Enum.KeyCode.W end
            if char == "w" then return Enum.KeyCode.Z end
            if char == "m" then return Enum.KeyCode.Semicolon end -- M is often next to L
            -- NOTE: AZERTY is tricky because M can vary, but standard AZERTY FR places M right of L (where semi-colon is on QWERTY)
            -- However, many games might use scan codes where M is actually comma or something else depending on the specific AZERTY variant.
            -- For standard AZERTY (France), M is indeed usually where ; is.
        end
        return Enum.KeyCode[char:upper()]
    end
    return nil
end

local function SimulateKey(input)
    if typeof(input) == "string" and #input == 1 then
         local char = input
         local vimSuccess = pcall(function()
             VirtualInputManager:SendTextInput(char)
         end)
         
         if not vimSuccess then
             -- Fallback for executors that don't support SendTextInput or for keycodes
             local key
             pcall(function() key = GetKeyCode(input) end)
             if not key then pcall(function() key = Enum.KeyCode[input:upper()] end) end
             
             if key then
                 pcall(function()
                     VirtualInputManager:SendKeyEvent(true, key, false, game)
                     task.wait(0.01)
                     VirtualInputManager:SendKeyEvent(false, key, false, game)
                 end)
             end
         end
         return
    end

    local key
    if typeof(input) == "EnumItem" then
        key = input
    else
        pcall(function() key = Enum.KeyCode[input:upper()] end)
    end

    if key then
        local baseHold = math.clamp(12 / currentCPM, 0.015, 0.05)
        local hold = isBlatant and 0.002 or (baseHold + (math.random() * 0.01) - 0.005)

        local vimSuccess = pcall(function()
            VirtualInputManager:SendKeyEvent(true, key, false, game)
            task.wait(hold)
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end)

        if not vimSuccess then
            pcall(function()
                VirtualUser:TypeKey(key)
            end)
        end
    end
end

local function Backspace(count)
    local focused = UserInputService:GetFocusedTextBox()
    if focused and focused:IsDescendantOf(game) and focused.TextEditable then
        local text = focused.Text
        focused.Text = text:sub(1, -count - 1)
        lastKey = nil
        return
    end

    local key = Enum.KeyCode.Backspace
    for i = 1, count do
        pcall(function()
            VirtualInputManager:SendKeyEvent(true, key, false, game)
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end)
        if i % 20 == 0 then task.wait() end
    end
    lastKey = nil
end

local function PressEnter()
    SimulateKey(Enum.KeyCode.Return)
    lastKey = nil
end

local function GetGameTextBox()
    local player = Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local inGame = gui and gui:FindFirstChild("InGame")
    if inGame then
        local frame = inGame:FindFirstChild("Frame")
        if frame then
             for _, c in ipairs(frame:GetDescendants()) do
                 if c:IsA("TextBox") and c.Visible then return c end
             end
        end
        for _, c in ipairs(inGame:GetDescendants()) do
             if c:IsA("TextBox") and c.Visible then return c end
        end
    end
    return UserInputService:GetFocusedTextBox()
end

local function SmartType(targetWord, currentDetected, isCorrection, bypassTurn)
    if unloaded then return end
    
    if isTyping then
        if (tick() - lastTypingStart) > 15 then
            isTyping = false
            isAutoPlayScheduled = false
            StatusText.Text = "Typing State Reset (Timeout)"
            StatusText.TextColor3 = THEME.Warning
        else
            return
        end
    end

    isTyping = true
    lastTypingStart = tick()
    
    local targetBox = GetGameTextBox()
    if targetBox then
        targetBox:CaptureFocus()
        task.wait(0.1)
    end
    
    StatusText.Text = "Typing..."
    StatusText.TextColor3 = THEME.Accent
    Tween(StatusDot, {BackgroundColor3 = THEME.Accent})

    local success, err = pcall(function()
        if isCorrection then
            local commonLen = 0
            local minLen = math.min(#targetWord, #currentDetected)
            for i = 1, minLen do
                if targetWord:sub(i,i) == currentDetected:sub(i,i) then
                    commonLen = i
                else
                    break
                end
            end

            local backspaceCount = #currentDetected - commonLen
            if backspaceCount > 0 then
                Backspace(backspaceCount)
                task.wait(0.15)
            end
            
            local toType = targetWord:sub(commonLen + 1)
            for i = 1, #toType do
                if not bypassTurn and not GetTurnInfo() then
                    -- Double check if turn info is just flickering
                    task.wait(0.05)
                    if not GetTurnInfo() then break end
                end
                local ch = toType:sub(i, i)
                SimulateKey(ch)
                task.wait(CalculateDelayForKeys(lastKey, ch))
                lastKey = ch
                if useHumanization and math.random() < 0.03 then
                    task.wait(0.15 + math.random() * 0.45)
                end
            end

            -- Pre-submission verify
            local finalCheck = GetGameTextBox()
            if not riskyMistakes then
                task.wait(0.1)
                finalCheck = GetGameTextBox()
                if finalCheck and finalCheck.Text ~= targetWord then
                     StatusText.Text = "Typing mismatch detected!"
                     StatusText.TextColor3 = THEME.Warning
                     Backspace(#finalCheck.Text)
                     
                     isTyping = false
                     forceUpdateList = true
                     return
                end
            end

            PressEnter()
            
            local verifyStart = tick()
            local accepted = false
            
            while (tick() - verifyStart) < 1.5 do
                local currentCheck = GetCurrentGameWord()
                if currentCheck == "" or (currentCheck ~= targetWord and currentCheck ~= currentDetected) then
                     accepted = true
                     break
                end
                task.wait(0.05)
            end

            if not accepted then
                env.WordHelperBlacklistTracker.Add(targetWord, "auto rejection")
                RandomPriority[targetWord] = nil
                
                for k, list in pairs(RandomOrderCache) do
                    for i = #list, 1, -1 do
                        if list[i] == targetWord then table.remove(list, i) end
                    end
                end

                StatusText.Text = "Rejected: removed '" .. targetWord .. "'"
                StatusText.TextColor3 = THEME.Warning
                
                local focused = UserInputService:GetFocusedTextBox()
                if focused and focused:IsDescendantOf(game) and focused.TextEditable then
                    focused.Text = ""
                else
                    Backspace(#targetWord + 5)
                end

                lastDetected = "---"
                isTyping = false
                forceUpdateList = true
                return
            else
                StatusText.Text = "Word Cleared (Corrected)"
                StatusText.TextColor3 = THEME.SubText

                local current = GetCurrentGameWord()
                if #current > 0 then
                    Backspace(#current)
                end

                UsedWords[targetWord] = true
                isMyTurnLogDetected = false
                task.wait(0.2)
            end
        else
            local missingPart = ""
            if targetWord:sub(1, #currentDetected) == currentDetected then
                missingPart = targetWord:sub(#currentDetected + 1)
            else
                missingPart = targetWord
            end

            local letters = "abcdefghijklmnopqrstuvwxyz"
            for i = 1, #missingPart do
                if not bypassTurn and not GetTurnInfo() then
                     -- Double check if turn info is just flickering
                     task.wait(0.05)
                     if not GetTurnInfo() then break end
                end
                local ch = missingPart:sub(i, i)
                if errorRate > 0 and (math.random() < (errorRate / 100)) then
                    local typoChar
                    repeat
                        local idx = math.random(1, #letters)
                        typoChar = letters:sub(idx, idx)
                    until typoChar ~= ch
                    SimulateKey(typoChar)
                    
                    if riskyMistakes then
                         task.wait(0.05 + math.random() * 0.1)
                         PressEnter()
                    end

                    task.wait(CalculateDelayForKeys(lastKey, typoChar))
                    lastKey = typoChar
                    local realize = thinkDelayCurrent * (0.6 + math.random() * 0.8)
                    task.wait(realize)
                    SimulateKey(Enum.KeyCode.Backspace)
                    lastKey = nil
                    task.wait(0.05 + math.random() * 0.08)
                    SimulateKey(ch)
                    task.wait(CalculateDelayForKeys(lastKey, ch))
                    lastKey = ch
                else
                    SimulateKey(ch)
                    task.wait(CalculateDelayForKeys(lastKey, ch))
                    lastKey = ch
                end
                if useHumanization and math.random() < 0.03 then
                    task.wait(0.12 + math.random() * 0.5)
                end
            end

            -- Pre-submission verify
            if not riskyMistakes then
                -- Wait a moment for last character to register
                task.wait(0.1)
                local finalCheck = GetGameTextBox()
                if finalCheck and finalCheck.Text ~= targetWord then
                    StatusText.Text = "Typing mismatch detected!"
                    StatusText.TextColor3 = THEME.Warning
                    Backspace(#finalCheck.Text)
                    
                    isTyping = false
                    forceUpdateList = true
                    -- Return without blacklisting
                    return
                end
            end

            PressEnter()
            
            local verifyStart = tick()
            local accepted = false
            
            while (tick() - verifyStart) < 1.5 do
                local currentCheck = GetCurrentGameWord()
                if currentCheck == "" or (currentCheck ~= targetWord and currentCheck ~= currentDetected) then
                     accepted = true
                     break
                end
                task.wait(0.05)
            end

            if not accepted then
                
                local postCheck = GetGameTextBox()
                if postCheck and postCheck.Text == targetWord then
                     StatusText.Text = "Enter failed? Retrying..."
                     PressEnter()
                     task.wait(0.5)
                     if GetCurrentGameWord() == currentDetected then
                         StatusText.Text = "Submission Failed (Lag?)"
                         StatusText.TextColor3 = THEME.Warning
                         Backspace(#targetWord)
                         isTyping = false
                         forceUpdateList = true
                         return
                     end
                end

                env.WordHelperBlacklistTracker.Add(targetWord, "auto rejection")
                for k, list in pairs(RandomOrderCache) do
                    for i = #list, 1, -1 do
                        if list[i] == targetWord then table.remove(list, i) end
                    end
                end
                StatusText.Text = "Rejected: removed '" .. targetWord .. "'"
                StatusText.TextColor3 = THEME.Warning
                
                local focused = UserInputService:GetFocusedTextBox()
                if focused and focused:IsDescendantOf(game) and focused.TextEditable then
                    focused.Text = ""
                else
                    Backspace(#targetWord + 5)
                end
                
                isTyping = false
                lastDetected = "---"
                forceUpdateList = true

                task.spawn(function()
                    task.wait(0.1)
                    local _, req = GetTurnInfo()
                    UpdateList(currentDetected, req)
                end)
                return
            else
                StatusText.Text = "Verification Failed"
                StatusText.TextColor3 = THEME.Warning
                
                local current = GetCurrentGameWord()
                if #current > 0 then
                    Backspace(#current)
                end

                UsedWords[targetWord] = true
                isMyTurnLogDetected = false
                task.wait(0.2)
            end
        end
    end)
    isTyping = false
    forceUpdateList = true
end

local function GetMatchLength(str, prefix)
    local len = 0
    local max = math.min(#str, #prefix)
    for i = 1, max do
        local pb = string.byte(prefix, i)
        if pb == 35 or pb == string.byte(str, i) then
            len = i
        else
            break
        end
    end
    return len
end

local function BinarySearchStart(list, prefix)
    local left = 1
    local right = #list
    local result = -1
    local pLen = #prefix

    while left <= right do
        local mid = math.floor((left + right) / 2)
        local word = list[mid]
        local sub = word:sub(1, pLen)

        if sub == prefix then
            result = mid
            right = mid - 1
        elseif sub < prefix then
            left = mid + 1
        else
            right = mid - 1
        end
    end

    return result
end

UpdateList = function(detectedText, requiredLetter)
    local matches = {}
    local searchPrefix = detectedText
    local isBacktracked = false
    local manualSearch = false

    if SearchBox and SearchBox.Text ~= "" then
        searchPrefix = SearchBox.Text:lower():gsub("[%s%c]+", "")
        manualSearch = true
        if requiredLetter and searchPrefix:sub(1,1) ~= requiredLetter:sub(1,1):lower() then
             requiredLetter = nil
        end
    end

    if not manualSearch and requiredLetter and #requiredLetter > 0 then
        local reqLen = GetMatchLength(requiredLetter, searchPrefix)
        if reqLen == #searchPrefix and #requiredLetter > #searchPrefix then
             searchPrefix = requiredLetter
        end
    end
    
    local firstChar = searchPrefix:sub(1,1)
    if firstChar == "#" then firstChar = nil end

    if (not firstChar or firstChar == "") and requiredLetter then
        firstChar = requiredLetter:sub(1,1):lower()
    end
    
    local bucket
    if firstChar and firstChar ~= "" and Buckets then
        bucket = Buckets[firstChar] or {}
    else
        bucket = Words
    end
    
    local function CollectMatches(prefix, tryFallbackLengths)
        local exacts = {}
        local fallbackExacts = {}
        local partials = {}
        local maxPartialLen = 0
        local limit = 100
        
        if bucket then
            local checkWord = function(w)
                if Blacklist[w] or (UsedWords[w] and not Config.ShowUsedWords) then return end
                
                -- Check for main list filtering (suffix/length)
                if suffixMode ~= "" and w:sub(-#suffixMode) ~= suffixMode then return end
                
                local isLengthMatch = true
                if not tryFallbackLengths and lengthMode > 0 then
                    isLengthMatch = (#w == lengthMode)
                elseif tryFallbackLengths and lengthMode > 0 then
                     isLengthMatch = true
                end
                
                if not isLengthMatch then return end

                local mLen = GetMatchLength(w, prefix)
                if mLen == #prefix then
                    table.insert(exacts, w)
                elseif #exacts == 0 then
                    if mLen > maxPartialLen then
                        maxPartialLen = mLen
                        partials = {w}
                    elseif mLen == maxPartialLen and mLen > 0 then
                        if #partials < 50 then table.insert(partials, w) end
                    end
                end
            end

            local useBinary = true
            if prefix:find("#") or prefix:find("%*") then useBinary = false end
            
            if useBinary and #prefix > 0 then
                local startIndex = BinarySearchStart(bucket, prefix)
                
                if startIndex ~= -1 then
                    local count = 0
                    -- Only 40 rows are displayed. A smaller ordinary pool is plenty,
                    -- while the existing tail scan still captures configured Godmode
                    -- priorities/traps beyond this point.
                    local normalLimit = manualSearch and 700 or 1400
                    local tailPriorityAdded = 0
                    local seenExact = {}

                    for i = startIndex, #bucket do
                        local w = bucket[i]

                        if w:sub(1, #prefix) ~= prefix then break end

                        -- Keep the normal candidate pool bounded for performance.
                        -- After the limit is reached, GodMode continues only far enough
                        -- to capture trap words that would otherwise be missed.
                        if count < normalLimit then
                            checkWord(w)
                            if not Blacklist[w] and (not UsedWords[w] or Config.ShowUsedWords) then
                                seenExact[w] = true
                            end
                            count = count + 1
                        elseif sortMode == "Godmode" then
                            -- Continue the cheap scan so late priority matches are not lost,
                            -- but bound non-trap additions to avoid another UI freeze.
                            local canAddPriority = GodmodeMatchesConfiguredPriority(w)
                            local isTrapPriority = GodmodeIsTrapWord(w)
                            if canAddPriority
                                and (isTrapPriority or tailPriorityAdded < 350)
                                and not seenExact[w]
                                and not Blacklist[w]
                                and (not UsedWords[w] or Config.ShowUsedWords)
                                and (suffixMode == "" or w:sub(-#suffixMode) == suffixMode)
                                and (lengthMode == 0 or tryFallbackLengths or #w == lengthMode) then
                                table.insert(exacts, w)
                                seenExact[w] = true
                                if not isTrapPriority then
                                    tailPriorityAdded = tailPriorityAdded + 1
                                end
                            end
                        elseif sortMode ~= "Godmode" then
                            break
                        end
                    end
                end
            else
                local searchLimit = (sortMode == "Random") and 1000 or limit
                for _, w in ipairs(bucket) do
                    checkWord(w)
                    if #exacts >= searchLimit then break end
                end
            end
            
            if sortMode == "Random" and #exacts > 0 then
                shuffleTable(exacts)
            end
        end
        return exacts, partials, maxPartialLen
    end

    local exacts, partials, pLen = CollectMatches(searchPrefix, false)

    if #exacts == 0 and lengthMode > 0 then
        local fallbackExacts, fallbackPartials, fallbackPLen = CollectMatches(searchPrefix, true)
        if #fallbackExacts > 0 then
             exacts = fallbackExacts
        end
    end

    if #exacts > 0 then
        matches = exacts
    elseif pLen > 0 then
        matches = partials
        searchPrefix = searchPrefix:sub(1, pLen)
        isBacktracked = true
    elseif requiredLetter and #requiredLetter > 0 then
        local reqChar = requiredLetter:sub(1,1):lower()
        if searchPrefix:sub(1,1):lower() ~= reqChar then
            local fallbackBucket = (Buckets and Buckets[reqChar]) or Words
            if fallbackBucket then
                for _, w in ipairs(fallbackBucket) do
                    if not Blacklist[w] and (not UsedWords[w] or Config.ShowUsedWords) then
                         local mLen = GetMatchLength(w, requiredLetter)
                         if mLen == #requiredLetter then
                             table.insert(matches, w)
                             if #matches >= 100 then break end
                         end
                    end
                end
            end
            
            if #matches > 0 then
                searchPrefix = requiredLetter
                isBacktracked = true
            end
        end
    end
    
    if #matches > 0 then
        if sortMode == "Longest" then
            table.sort(matches, function(a, b) return #a > #b end)
        elseif sortMode == "Shortest" then
            table.sort(matches, function(a, b) return #a < #b end)
        elseif sortMode == "Godmode" then
            local godScoreCache = {}
            for _, w in ipairs(matches) do
                godScoreCache[w] = GetGodmodeScore(w)
            end

            table.sort(matches, function(a, b)
                local sA = godScoreCache[a] or 0
                local sB = godScoreCache[b] or 0
                if sA == sB then
                    return #a < #b
                end
                return sA > sB
            end)
        elseif sortMode == "Killer" then
            table.sort(matches, function(a, b)
                local sA = GetKillerScore(a)
                local sB = GetKillerScore(b)
                if sA == sB then
                    return #a < #b
                end
                return sA > sB
            end)
        end
    end
    
    local displayList = {}
    local maxDisplay = 40
    for i = 1, math.min(maxDisplay, #matches) do table.insert(displayList, matches[i]) end
    
    if showKeyboard and KeyboardFrame.Visible then
        local colors = {
            Color3.fromRGB(100, 255, 140),
            Color3.fromRGB(255, 180, 200),
            Color3.fromRGB(100, 200, 255)
        }
        
        local targetKeys = {}

        for i = 1, math.min(3, #displayList) do
            local w = displayList[i]
            local nextChar = w:sub(#searchPrefix + 1, #searchPrefix + 1)
            if nextChar and nextChar ~= "" then
                local char = nextChar:lower()
                if not targetKeys[char] then
                    targetKeys[char] = i
                end
            end
        end

        for char, k in pairs(Keys) do
            local priority = targetKeys[char]
            if priority then
                k.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
                Tween(k, {BackgroundColor3 = colors[priority]}, 0.3)
            else
                Tween(k, {BackgroundColor3 = THEME.ItemBG}, 0.2)
            end
        end
    end

    if #matches > 0 and not isBacktracked then
        currentBestMatch = matches[1]
    else
        currentBestMatch = nil
    end
    
    if isBacktracked then
        local validPart = searchPrefix
        local invalidPart = detectedText:sub(#searchPrefix + 1)
        local accentRGB = ColorToRGB(THEME.Accent)
        StatusText.Text = "No match: <font color=\"rgb(" .. accentRGB .. ")\">" .. validPart .. "</font><font color=\"rgb(255,80,80)\">" .. invalidPart .. "</font>"
        StatusText.TextColor3 = THEME.SubText
    elseif #exacts == 0 and lengthMode > 0 and suffixMode ~= "" then
         StatusText.Text = "No len match (showing all)"
         StatusText.TextColor3 = THEME.Warning
    end

    for i = 1, math.max(#displayList, #ButtonCache) do
        local w = displayList[i]
        local btn = ButtonCache[i]

        if w then
            local lbl
            if not btn then
                btn = Instance.new("TextButton")
                btn.Size = UDim2.new(1, -6, 0, 30)
                btn.BackgroundColor3 = THEME.ItemBG
                btn.Text = ""
                btn.AutoButtonColor = false
                Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
                
                lbl = Instance.new("TextLabel", btn)
                lbl.Name = "Label"
                lbl.Size = UDim2.new(1, -20, 1, 0)
                lbl.Position = UDim2.new(0, 10, 0, 0)
                lbl.BackgroundTransparency = 1
                lbl.Font = Enum.Font.GothamMedium
                lbl.TextSize = 14
                lbl.TextXAlignment = Enum.TextXAlignment.Left
                lbl.RichText = true
                
                btn.MouseEnter:Connect(function()
                    local d = ButtonData[btn]
                    if not (d and d.used) then Tween(btn, {BackgroundColor3 = Color3.fromRGB(45,45,55)}) end
                end)
                btn.MouseLeave:Connect(function()
                    local d = ButtonData[btn]
                    Tween(btn, {BackgroundColor3 = (d and d.used) and Color3.fromRGB(27,27,31) or THEME.ItemBG})
                end)
                
                btn.MouseButton1Click:Connect(function()
                    local d = ButtonData[btn]
                    if d and not d.used then
                        SmartType(d.word, d.detected, true)
                        local l = btn:FindFirstChild("Label")
                        if l then l.TextColor3 = THEME.Success end
                        Tween(btn, {BackgroundColor3 = Color3.fromRGB(30,60,40)})
                    end
                end)
                
                btn.Parent = ScrollList
                table.insert(ButtonCache, btn)
            else
                lbl = btn:FindFirstChild("Label")
                btn.Visible = true
                btn.Parent = ScrollList
                btn.BackgroundColor3 = THEME.ItemBG
                if lbl then lbl.TextColor3 = THEME.Text end
            end
            
            ButtonData[btn] = {word = w, detected = detectedText, used = UsedWords[w] == true}
            
            local accentRGB = ColorToRGB(THEME.Accent)
            
            if i == 1 then accentRGB = "100,255,140"
            elseif i == 2 then accentRGB = "255,180,200"
            elseif i == 3 then accentRGB = "100,200,255"
            end

            local textRGB = ColorToRGB(THEME.Text)
            
            local displayText = ""
            if isBacktracked then
                local prefix = w:sub(1, #searchPrefix)
                local suffix = w:sub(#searchPrefix + 1)
                displayText = "<font color=\"rgb(" .. accentRGB .. ")\">" .. prefix .. "</font>"
                    .. "<font color=\"rgb(" .. textRGB .. ")\">" .. suffix .. "</font>"
            else
                local prefix = w:sub(1, #detectedText)
                local suffix = w:sub(#detectedText + 1)
                displayText = "<font color=\"rgb(" .. accentRGB .. ")\">" .. prefix .. "</font>"
                    .. "<font color=\"rgb(" .. textRGB .. ")\">" .. suffix .. "</font>"
            end
            
            -- Show why a word is prioritized while GodMode is selected.
            if sortMode == "Godmode" then
                local categoryTag = ""

                categoryTag = select(1, GodmodeGetPriorityCategory(w))

                if categoryTag ~= "" then
                    displayText = displayText
                        .. "  <font color=\"rgb(150,150,160)\">["
                        .. categoryTag
                        .. "]</font>"
                end
            end

            if UsedWords[w] then
                btn.BackgroundColor3 = Color3.fromRGB(27, 27, 31)
                if lbl then
                    lbl.TextColor3 = THEME.SubText
                    lbl.Text = "<font color=\"rgb(120,120,130)\">" .. w .. "  [USED]</font>"
                end
            else
                if lbl then
                    lbl.TextColor3 = THEME.Text
                    lbl.Text = displayText
                end
            end
        else
            if btn then
                btn.Visible = false
                ButtonData[btn] = nil
            end
        end
    end
    
    ScrollList.CanvasSize = UDim2.new(0,0,0, UIListLayout.AbsoluteContentSize.Y)
end

SetupSlider(SliderBtn, SliderBg, SliderFill, function(pct)
    local max = isBlatant and MAX_CPM_BLATANT or MAX_CPM_LEGIT
    currentCPM = math.floor(MIN_CPM + (pct * (max - MIN_CPM)))
    SliderFill.Size = UDim2.new(pct, 0, 1, 0)
    SliderLabel.Text = "Speed: " .. currentCPM .. " CPM"
    if currentCPM > 900 then Tween(SliderFill, {BackgroundColor3 = Color3.fromRGB(255,80,80)}) 
    else Tween(SliderFill, {BackgroundColor3 = THEME.Accent}) end
end)

MinBtn.MouseButton1Click:Connect(function()
    local isMin = MainFrame.Size.Y.Offset < 100
    if not isMin then
        Tween(MainFrame, {Size = UDim2.new(0, 300, 0, 45)})
        ScrollList.Visible = false
        SettingsFrame.Visible = false
        StatusFrame.Visible = false
        MinBtn.Text = "+"
    else
        Tween(MainFrame, {Size = UDim2.new(0, 300, 0, 500)})
        task.wait(0.2)
        ScrollList.Visible = true
        SettingsFrame.Visible = true
        StatusFrame.Visible = true
        MinBtn.Text = "-"
    end
end)


-- Permanent rejection learning: correlate the local player's Enter press
-- with Last Letter's confirmed rejection sound. The Wrong sound is global,
-- so it is only trusted inside a short window after OUR own submission.
env.WordHelperBlacklistTracker.TypedBuffer = ""
env.WordHelperBlacklistTracker.LastKeyAt = 0
-- Do not nil KeyConnection/WrongSoundConnection here: the cleanup block below
-- needs the previous execution's references so it can disconnect them.
env.WordHelperBlacklistTracker.PendingWord = ""
env.WordHelperBlacklistTracker.PendingAt = 0
env.WordHelperBlacklistTracker.PendingRequired = ""
env.WordHelperBlacklistTracker.PendingTimer = nil
env.WordHelperBlacklistTracker.RejectionWindow = 1.80

env.WordHelperBlacklistTracker.IsKnownWord = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 then return false end
    return WordHelperKnownWords[word] == true
end

env.WordHelperBlacklistTracker.ReadTimerSeconds = function(frame)
    local circle = frame and frame:FindFirstChild("Circle")
    local timer = circle and circle:FindFirstChild("Timer")
    local seconds = timer and timer:FindFirstChild("Seconds")
    if seconds and seconds:IsA("TextLabel") then
        return tonumber(tostring(seconds.Text):match("([%d%.]+)"))
    end
    return nil
end

env.WordHelperBlacklistTracker.ClearPending = function()
    env.WordHelperBlacklistTracker.PendingWord = ""
    env.WordHelperBlacklistTracker.PendingAt = 0
    env.WordHelperBlacklistTracker.PendingRequired = ""
    env.WordHelperBlacklistTracker.PendingTimer = nil
end

env.WordHelperBlacklistTracker.BeginAttempt = function(word, requiredLetters)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    requiredLetters = tostring(requiredLetters or ""):lower():gsub("[^a-z]", "")

    -- Never learn typos, already rejected words, or words already known as used.
    if #word < 2 or Blacklist[word] or UsedWords[word] then return false end
    if not env.WordHelperBlacklistTracker.IsKnownWord(word) then return false end

    local player = Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local inGame = gui and gui:FindFirstChild("InGame")
    local frame = inGame and inGame:FindFirstChild("Frame")
    if not frame then return false end

    local isMyTurn, currentRequired = GetTurnInfo(frame)
    if not isMyTurn then return false end

    currentRequired = tostring(currentRequired or ""):lower():gsub("[^a-z]", "")
    if requiredLetters == "" then requiredLetters = currentRequired end

    -- Do not reject the attempt based on the required-prefix cache here.
    -- The rejection diagnostic proved GetTurnInfo can retain a stale required
    -- letter (for example "x") across later turns. That stale value prevented
    -- otherwise valid dictionary words from ever being armed.
    --
    -- Typo protection remains intact because BeginAttempt still requires the
    -- exact submitted word to exist in WordHelper's canonical known-word set.

    local timerAtSubmit = env.WordHelperBlacklistTracker.ReadTimerSeconds(frame)

    -- Do not learn anything submitted at the edge of timeout.
    if timerAtSubmit and timerAtSubmit < 1.5 then
        return false
    end

    env.WordHelperBlacklistTracker.PendingWord = word
    env.WordHelperBlacklistTracker.PendingAt = tick()
    env.WordHelperBlacklistTracker.PendingRequired = requiredLetters
    env.WordHelperBlacklistTracker.PendingTimer = timerAtSubmit
    env.WordHelperBlacklistTracker.LastAttempt = word

    if StatusText then
        StatusText.Text = "Watching rejection: " .. word
        StatusText.TextColor3 = THEME.SubText
    end

    -- Automatically disarm if no Wrong sound arrives quickly.
    task.delay(env.WordHelperBlacklistTracker.RejectionWindow + 0.10, function()
        if env.WordHelperBlacklistTracker.PendingWord == word
            and (tick() - env.WordHelperBlacklistTracker.PendingAt)
                > env.WordHelperBlacklistTracker.RejectionWindow then
            env.WordHelperBlacklistTracker.ClearPending()
            if StatusText and UsedWords[word] then
                StatusText.Text = "Accepted: " .. word
                StatusText.TextColor3 = THEME.Success
            end
        end
    end)

    return true
end

-- Last Letter confirmed rejection sound detector.
-- Uses BOTH Played and Playing-property signals because the F7 inspector proved
-- the executor can observe Playing even when a standalone Played connection is unreliable.

-- Clean up listeners left by a previous injected WordHelper execution before
-- replacing their references. This prevents duplicate/stale rejection callbacks.
if env.WordHelperBlacklistTracker.WrongSoundConnection then
    pcall(function() env.WordHelperBlacklistTracker.WrongSoundConnection:Disconnect() end)
end
if env.WordHelperBlacklistTracker.WrongPlayingConnection then
    pcall(function() env.WordHelperBlacklistTracker.WrongPlayingConnection:Disconnect() end)
end
if env.WordHelperBlacklistTracker.WrongAddedConnection then
    pcall(function() env.WordHelperBlacklistTracker.WrongAddedConnection:Disconnect() end)
end
if env.WordHelperBlacklistTracker.KeyConnection then
    pcall(function() env.WordHelperBlacklistTracker.KeyConnection:Disconnect() end)
end

env.WordHelperBlacklistTracker.SoundService = game:GetService("SoundService")
env.WordHelperBlacklistTracker.WrongSoundConnection = nil
env.WordHelperBlacklistTracker.WrongPlayingConnection = nil
env.WordHelperBlacklistTracker.WrongAddedConnection = nil
env.WordHelperBlacklistTracker.KeyConnection = nil
env.WordHelperBlacklistTracker.LastWrongHandledAt = 0

env.WordHelperBlacklistTracker.HandleWrongSound = function(source)
    if unloaded then return end

    local now = tick()
    if now - (env.WordHelperBlacklistTracker.LastWrongHandledAt or 0) < 0.08 then return end
    env.WordHelperBlacklistTracker.LastWrongHandledAt = now

    if env.WordHelperDiscovery then
        env.WordHelperDiscovery.LastWrongAt = now
    end

    -- The Wrong sound is global, so only trust it when our Enter handler has
    -- already armed a fresh local submission. BeginAttempt performed all the
    -- safety checks BEFORE submission: my turn, correct starting prefix,
    -- dictionary membership, not already blacklisted/used, and not near timeout.
    local pendingWord =
        tostring(env.WordHelperBlacklistTracker.PendingWord or "")
            :lower():gsub("[^a-z]", "")
    local pendingAt =
        tonumber(env.WordHelperBlacklistTracker.PendingAt or 0) or 0

    local hasFreshPending =
        #pendingWord >= 2
        and (now - pendingAt)
            <= (env.WordHelperBlacklistTracker.RejectionWindow or 1.80)

    if not hasFreshPending then
        -- A global Wrong sound with no local armed attempt belongs to somebody
        -- else (or arrived too late), so never blacklist from it.
        return
    end

    -- Do NOT re-check GetTurnInfo/current required letters here. The game may
    -- already have changed the turn UI because the word was rejected.
    local candidate = pendingWord

    -- The pending attempt was checked against UsedWords before Enter. A later
    -- UsedWords flag can be the observer racing the rejection animation, so it
    -- must not veto this confirmed rejection.
    if Blacklist[candidate] then
        env.WordHelperBlacklistTracker.ClearPending()
        return
    end

    if not env.WordHelperBlacklistTracker.IsKnownWord(candidate) then
        env.WordHelperBlacklistTracker.ClearPending()
        if ShowToast then
            ShowToast("Rejected capture skipped - not in dictionary: " .. candidate, "warning")
        end
        return
    end

    local added = env.WordHelperBlacklistTracker.Add(
        candidate,
        "confirmed local pending attempt + SoundService.Game.Wrong via "
            .. tostring(source or "sound")
    )

    env.WordHelperBlacklistTracker.ClearPending()

    if added and StatusText then
        StatusText.Text = "Blacklisted from rejection: " .. candidate
        StatusText.TextColor3 = THEME.Warning
    end
end

env.WordHelperBlacklistTracker.AttachWrongSound = function(sound)
    if not sound or not sound:IsA("Sound") then return false end
    if sound.Name ~= "Wrong" and tostring(sound.SoundId) ~= "rbxassetid://4612384231" then return false end

    if env.WordHelperBlacklistTracker.WrongSoundConnection then
        pcall(function() env.WordHelperBlacklistTracker.WrongSoundConnection:Disconnect() end)
    end
    if env.WordHelperBlacklistTracker.WrongPlayingConnection then
        pcall(function() env.WordHelperBlacklistTracker.WrongPlayingConnection:Disconnect() end)
    end

    env.WordHelperBlacklistTracker.WrongSound = sound
    env.WordHelperBlacklistTracker.WrongSoundConnection = nil
    env.WordHelperBlacklistTracker.WrongPlayingConnection = nil

    pcall(function()
        env.WordHelperBlacklistTracker.WrongSoundConnection = sound.Played:Connect(function()
            env.WordHelperBlacklistTracker.HandleWrongSound("Played")
        end)
    end)
    pcall(function()
        env.WordHelperBlacklistTracker.WrongPlayingConnection = sound:GetPropertyChangedSignal("Playing"):Connect(function()
            if sound.Playing then env.WordHelperBlacklistTracker.HandleWrongSound("Playing") end
        end)
    end)

    if ShowToast then ShowToast("Rejection detector armed", "success") end
    return true
end

env.WordHelperBlacklistTracker.GameSounds = env.WordHelperBlacklistTracker.SoundService:FindFirstChild("Game")
env.WordHelperBlacklistTracker.WrongSound = env.WordHelperBlacklistTracker.GameSounds and env.WordHelperBlacklistTracker.GameSounds:FindFirstChild("Wrong")

if not env.WordHelperBlacklistTracker.AttachWrongSound(env.WordHelperBlacklistTracker.WrongSound) then
    if env.WordHelperBlacklistTracker.WrongAddedConnection then
        pcall(function() env.WordHelperBlacklistTracker.WrongAddedConnection:Disconnect() end)
    end
    env.WordHelperBlacklistTracker.WrongAddedConnection = env.WordHelperBlacklistTracker.SoundService.DescendantAdded:Connect(function(obj)
        if obj:IsA("Sound") and (obj.Name == "Wrong" or tostring(obj.SoundId) == "rbxassetid://4612384231") then
            env.WordHelperBlacklistTracker.AttachWrongSound(obj)
        end
    end)
    if ShowToast then ShowToast("Waiting for Last Letter rejection sound", "warning") end
end

-- Capture the actual word from Last Letter's CurrentWord tiles on Enter.
-- This avoids relying on a TextBox that the game does not consistently expose.
if env.WordHelperBlacklistTracker.KeyConnection then
    pcall(function()
        env.WordHelperBlacklistTracker.KeyConnection:Disconnect()
    end)
end

env.WordHelperBlacklistTracker.KeyConnection =
    UserInputService.InputBegan:Connect(function(input, processed)
        if unloaded then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

        local keyName = input.KeyCode.Name
        if keyName ~= "Return" and keyName ~= "KeypadEnter" then return end

        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local inGame = gui and gui:FindFirstChild("InGame")
        local frame = inGame and inGame:FindFirstChild("Frame")
        if not frame then return end

        -- Ignore Enter presses in WordHelper search/input boxes or Roblox chat.
        local focused = UserInputService:GetFocusedTextBox()
        if focused and (not inGame or not focused:IsDescendantOf(inGame)) then
            return
        end

        local isMyTurn, requiredLetters = GetTurnInfo(frame)
        if not isMyTurn then return end

        requiredLetters =
            tostring(requiredLetters or ""):lower():gsub("[^a-z]", "")

        -- The capture logs proved the full attempted word is represented by
        -- InGame.Frame.CurrentWord immediately before the submission resolves.
        local attemptedWord = select(1, GetCurrentGameWord(frame)) or ""
        attemptedWord = tostring(attemptedWord):lower():gsub("[^a-z]", "")

        -- Prefer the continuously cached pre-submit word when the direct read has
        -- already been cleared/rebuilt by Last Letter's own Enter handler.
        local cachedAttempt = tostring(env.WordHelperBlacklistTracker.LastPreSubmitWord or "")
        local cachedAt = tonumber(env.WordHelperBlacklistTracker.LastPreSubmitAt or 0) or 0
        if (#attemptedWord < 2 or attemptedWord == requiredLetters)
            and #cachedAttempt >= 2
            and (tick() - cachedAt) <= 1.25 then
            attemptedWord = cachedAttempt
        end

        if #attemptedWord < 2 then
            if StatusText then
                StatusText.Text = "Enter seen - no cached word"
                StatusText.TextColor3 = THEME.Warning
            end
            if ShowToast then
                ShowToast("Enter detected, but no word was captured", "warning")
            end
            return
        end

        if StatusText then
            StatusText.Text = "Captured Enter: " .. attemptedWord
            StatusText.TextColor3 = THEME.SubText
        end

        env.WordHelperBlacklistTracker.BeginAttempt(
            attemptedWord,
            requiredLetters
        )
    end)

env.WordHelperUsedTracker = {
    lastTypeVisible = false,
    observedWord = "",
    observedWordSince = 0,
    lastObservedTypeText = "",
    wasRoundVisible = false,
    roundHadActivity = false,
    inactiveSince = 0,
    lobbySeenSince = 0
}

env.WordHelperUsedTracker.IsKnownDictionaryWord = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 then return false end
    return WordHelperKnownWords[word] == true
end

env.WordHelperUsedTracker.RecordObservedUsedWord = function(word)
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 or UsedWords[word] then return end
    if not env.WordHelperUsedTracker.IsKnownDictionaryWord(word) then return end

    UsedWords[word] = true
    forceUpdateList = true
end
local lastRequiredLetter = ""

-- Manual used-word reset. F6 calls this so a new game can start immediately
-- without waiting for the automatic round/lobby detector.
env.WordHelperUsedTracker.ClearUsedWords = function(showNotification)
    table.clear(UsedWords)
    env.WordHelperUsedTracker.observedWord = ""
    env.WordHelperUsedTracker.observedWordSince = 0
    env.WordHelperUsedTracker.inactiveSince = 0
    env.WordHelperUsedTracker.lobbySeenSince = 0

    -- Used words affect strategic-ending exhaustion, so invalidate this cache too.
    GodmodeReplyAvailabilityCache = {}
    currentBestMatch = nil
    forceUpdateList = true
    lastDetected = "---"

    if StatusText then
        StatusText.Text = "Used Words Cleared (F6)"
        StatusText.TextColor3 = THEME.Success
    end

    if showNotification and ShowToast then
        ShowToast("Used words cleared", "success")
    end

    -- Refresh immediately rather than waiting for the next normal list update.
    task.defer(function()
        if unloaded then return end
        local detectedNow = cachedDetected or ""
        local _, requiredNow = GetTurnInfo()
        UpdateList(detectedNow, requiredNow or lastRequiredLetter)
    end)
end

local StatsData = {}

do
    local sf = Instance.new("Frame")
    sf.Name = "StatsFrame"
    sf.Size = UDim2.new(0, 120, 0, 60)
    sf.Position = UDim2.new(0.5, -60, 0, 10)
    sf.BackgroundColor3 = THEME.Background
    sf.Visible = false
    sf.Parent = ScreenGui
    EnableDragging(sf)
    Instance.new("UICorner", sf).CornerRadius = UDim.new(0, 8)
    Instance.new("UIStroke", sf).Color = THEME.Accent
    StatsData.Frame = sf

    local st = Instance.new("TextLabel")
    st.Size = UDim2.new(1, 0, 0, 25)
    st.Position = UDim2.new(0, 0, 0, 5)
    st.BackgroundTransparency = 1
    st.TextColor3 = THEME.Text
    st.Font = Enum.Font.GothamBold
    st.TextSize = 20
    st.Text = "--"
    st.Parent = sf
    StatsData.Timer = st

    local sc = Instance.new("TextLabel")
    sc.Size = UDim2.new(1, 0, 0, 20)
    sc.Position = UDim2.new(0, 0, 0, 30)
    sc.BackgroundTransparency = 1
    sc.TextColor3 = THEME.SubText
    sc.Font = Enum.Font.Gotham
    sc.TextSize = 12
    sc.Text = "Words: 0"
    sc.Parent = sf
    StatsData.Count = sc
end

runConn = RunService.RenderStepped:Connect(function()
    local success, err = pcall(function()
        local now = tick()
        local player = Players.LocalPlayer
        local gui = player and player:FindFirstChild("PlayerGui")
        local frame = gui and gui:FindFirstChild("InGame") and gui.InGame:FindFirstChild("Frame")

        if isTyping and (tick() - lastTypingStart) > 15 then
            isTyping = false
            isAutoPlayScheduled = false
            StatusText.Text = "Typing State Reset (Watchdog)"
            StatusText.TextColor3 = THEME.Warning
        end
        
        local isVisible = false
        if frame and frame.Parent then
            if frame.Parent:IsA("ScreenGui") then
                isVisible = frame.Parent.Enabled
            elseif frame.Parent:IsA("GuiObject") then
                isVisible = frame.Parent.Visible
            end
        end

        local seconds = nil
        if isVisible then
            local circle = frame:FindFirstChild("Circle")
            local timerLbl = circle and circle:FindFirstChild("Timer") and circle.Timer:FindFirstChild("Seconds")
            
            if timerLbl then
                local timeText = timerLbl.Text
                seconds = tonumber(timeText:match("([%d%.]+)"))
                
                StatsData.Frame.Visible = true
                StatsData.Timer.Text = timeText
                if seconds and seconds < 3 then StatsData.Timer.TextColor3 = Color3.fromRGB(255, 80, 80)
                else StatsData.Timer.TextColor3 = THEME.Text end
            end
        else
            StatsData.Frame.Visible = false
        end

        local isMyTurn, requiredLetter = GetTurnInfo(frame)
        
        if (now - lastWordCheck) > 0.05 then
            cachedDetected, cachedCensored = GetCurrentGameWord(frame)
            lastWordCheck = now
        end
        local detected, censored = cachedDetected, cachedCensored

        -- Continuously cache the full pre-submit word while it is visible.
        -- InputBegan callbacks can run after Last Letter has already processed Enter,
        -- so relying on CurrentWord at the exact Enter callback is not reliable.
        if isVisible and isMyTurn and detected and not censored then
            local req = tostring(requiredLetter or ""):lower():gsub("[^a-z]", "")
            local cleanDetected = tostring(detected or ""):lower():gsub("[^a-z]", "")
            if #cleanDetected >= 2
                and (req == "" or cleanDetected:sub(1, #req) == req) then
                env.WordHelperBlacklistTracker.LastPreSubmitWord = cleanDetected
                env.WordHelperBlacklistTracker.LastPreSubmitAt = tick()
                env.WordHelperBlacklistTracker.LastPreSubmitRequired = req
            end
        end

        if isVisible and isMyTurn and not isTyping and seconds and seconds < 1.5 then
            local char = (requiredLetter or ""):lower()
            local bucket = Buckets[char]
            if bucket then
                local bestWord = nil
                local bestLen = 999
                for _, w in ipairs(bucket) do
                    if not Blacklist[w] and not UsedWords[w] and w:sub(1, #detected) == detected then
                        if #w < bestLen then
                            bestWord = w
                            bestLen = #w
                        end
                    end
                end
                
                if bestWord then
                    StatusText.Text = "PANIC SAVE!"
                    StatusText.TextColor3 = Color3.fromRGB(255, 50, 50)
                    SmartType(bestWord, detected, false)
                end
            end
        end

        if autoJoin and (now - lastAutoJoinCheck > AUTO_JOIN_RATE) then
            lastAutoJoinCheck = now
            task.spawn(function()
                local displayMatch = gui and gui:FindFirstChild("DisplayMatch")
                local dFrame = displayMatch and displayMatch:FindFirstChild("Frame")
                local matches = dFrame and dFrame:FindFirstChild("Matches")
                
                if matches then
                    for _, matchFrame in ipairs(matches:GetChildren()) do
                        if (matchFrame:IsA("Frame") or matchFrame:IsA("GuiObject")) and matchFrame.Name ~= "UIListLayout" then
                            local joinBtn = matchFrame:FindFirstChild("Join")
                            local title = matchFrame:FindFirstChild("Title")
                            
                            local isLastLetter = false
                            local titleText = "N/A"
                            if title and title:IsA("TextLabel") then
                                titleText = title.Text
                                if titleText:find("Last Letter") then
                                    isLastLetter = true
                                end
                            end

                            local idx = tonumber(matchFrame.Name)
                            local allowed = true
                            if idx then
                                if idx >= 1 and idx <= 4 then allowed = Config.AutoJoinSettings._1v1
                                elseif idx >= 5 and idx <= 8 then allowed = Config.AutoJoinSettings._4p
                                elseif idx == 9 then allowed = Config.AutoJoinSettings._8p
                                end
                            end

                            if joinBtn and joinBtn.Visible and isLastLetter and allowed then
                                local matchId = matchFrame.Name
                                if (tick() - (JoinDebounce[matchId] or 0)) > 2 then
                                    JoinDebounce[matchId] = tick()
                                    task.wait(0.5)
                                    
                                    local clicked = false
                                    if getconnections then
                                        if joinBtn:IsA("GuiButton") then
                                            local success, conns = pcall(function() return getconnections(joinBtn.MouseButton1Click) end)
                                            if success and conns then
                                                for _, conn in ipairs(conns) do
                                                    if conn.Fire then conn:Fire() end
                                                    if conn.Function then
                                                        task.spawn(conn.Function)
                                                    end
                                                    clicked = true
                                                end
                                            end
                                        end
                                    end
                                    
                                    if not clicked then
                                        local cd = joinBtn:FindFirstChildWhichIsA("ClickDetector")
                                        if cd then
                                            fireclickdetector(cd)
                                            clicked = true
                                        end
                                    end

                                    if not clicked then
                                        local absPos = joinBtn.AbsolutePosition
                                        local absSize = joinBtn.AbsoluteSize
                                        local centerX = absPos.X + absSize.X/2
                                        local centerY = absPos.Y + absSize.Y/2
                                        
                                        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, true, game, 1)
                                        task.wait(0.05)
                                        VirtualInputManager:SendMouseButtonEvent(centerX, centerY, 0, false, game, 1)
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end)
        end

        local typeLbl = frame and frame:FindFirstChild("Type")
        local typeVisible = typeLbl and typeLbl.Visible
        local typeText = (typeLbl and typeLbl:IsA("TextLabel") and typeLbl.Text) or ""

        -- Observe every visible candidate for accepted unknown-word learning.
        if isVisible and env.WordHelperDiscovery and env.WordHelperDiscovery.ObserveFrame then
            env.WordHelperDiscovery.ObserveFrame(detected, censored, typeText, now, frame)
        end

        -- Observe words typed by every player, including manual input.
        if isVisible then
            if detected ~= "" and not censored then
                if env.WordHelperUsedTracker.observedWord == "" or detected:sub(1, #env.WordHelperUsedTracker.observedWord) == env.WordHelperUsedTracker.observedWord then
                    if env.WordHelperUsedTracker.IsKnownDictionaryWord(detected) then
                        env.WordHelperUsedTracker.observedWord = detected
                        env.WordHelperUsedTracker.observedWordSince = now
                    end
                elseif detected ~= env.WordHelperUsedTracker.observedWord then
                    env.WordHelperUsedTracker.RecordObservedUsedWord(env.WordHelperUsedTracker.observedWord)
                    env.WordHelperUsedTracker.observedWord = env.WordHelperUsedTracker.IsKnownDictionaryWord(detected) and detected or ""
                    env.WordHelperUsedTracker.observedWordSince = now
                end
            elseif env.WordHelperUsedTracker.observedWord ~= "" and ((now - env.WordHelperUsedTracker.observedWordSince) > 0.08 or typeText ~= env.WordHelperUsedTracker.lastObservedTypeText) then
                env.WordHelperUsedTracker.RecordObservedUsedWord(env.WordHelperUsedTracker.observedWord)
                env.WordHelperUsedTracker.observedWord = ""
            end

            if typeText ~= env.WordHelperUsedTracker.lastObservedTypeText and env.WordHelperUsedTracker.observedWord ~= "" and (now - env.WordHelperUsedTracker.observedWordSince) > 0.08 then
                env.WordHelperUsedTracker.RecordObservedUsedWord(env.WordHelperUsedTracker.observedWord)
                env.WordHelperUsedTracker.observedWord = ""
            end
        end

        -- Reset when the lobby / match-selection interface returns after a real round.
        -- Last Letter keeps the InGame GUI alive, but DisplayMatch becomes visible again.
        if env.WordHelperUsedTracker.roundHadActivity
            and gui
            and gui:FindFirstChild("DisplayMatch")
            and gui.DisplayMatch:FindFirstChild("Frame")
            and gui.DisplayMatch.Frame.Visible then
            if env.WordHelperUsedTracker.lobbySeenSince == 0 then
                env.WordHelperUsedTracker.lobbySeenSince = now
            elseif (now - env.WordHelperUsedTracker.lobbySeenSince) >= 0.75 then
                table.clear(UsedWords)
                env.WordHelperUsedTracker.observedWord = ""
                env.WordHelperUsedTracker.observedWordSince = 0
                env.WordHelperUsedTracker.roundHadActivity = false
                env.WordHelperUsedTracker.inactiveSince = 0
                env.WordHelperUsedTracker.lobbySeenSince = 0
                StatusText.Text = "New Game Ready - Used Words Cleared"
                StatusText.TextColor3 = THEME.Success
                forceUpdateList = true
            end
        else
            env.WordHelperUsedTracker.lobbySeenSince = 0
        end

        -- Track genuine match activity. The InGame GUI can stay visible after a match,
        -- so visibility alone is not a reliable reset signal.
        if seconds ~= nil or typeVisible or detected ~= "" or isMyTurn then
            env.WordHelperUsedTracker.roundHadActivity = true
            env.WordHelperUsedTracker.inactiveSince = 0
        elseif env.WordHelperUsedTracker.roundHadActivity then
            if env.WordHelperUsedTracker.inactiveSince == 0 then
                env.WordHelperUsedTracker.inactiveSince = now
            elseif (now - env.WordHelperUsedTracker.inactiveSince) >= 2.5 then
                table.clear(UsedWords)
                env.WordHelperUsedTracker.observedWord = ""
                env.WordHelperUsedTracker.observedWordSince = 0
                env.WordHelperUsedTracker.roundHadActivity = false
                env.WordHelperUsedTracker.inactiveSince = 0
                StatusText.Text = "Game Over - Used Words Cleared"
                StatusText.TextColor3 = THEME.Success
                forceUpdateList = true
            end
        end

        -- Keep the original GUI-close reset as an immediate fallback.
        if env.WordHelperUsedTracker.wasRoundVisible and not isVisible and env.WordHelperUsedTracker.roundHadActivity then
            table.clear(UsedWords)
            env.WordHelperUsedTracker.observedWord = ""
            env.WordHelperUsedTracker.observedWordSince = 0
            env.WordHelperUsedTracker.roundHadActivity = false
            env.WordHelperUsedTracker.inactiveSince = 0
            StatusText.Text = "Game Over - Used Words Cleared"
            StatusText.TextColor3 = THEME.Success
            forceUpdateList = true
        end

        env.WordHelperUsedTracker.wasRoundVisible = isVisible
        env.WordHelperUsedTracker.lastObservedTypeText = typeText
        env.WordHelperUsedTracker.lastTypeVisible = typeVisible
        if censored then
            if StatusText.Text ~= "Word is Censored" then
                StatusText.Text = "Word is Censored"
                StatusText.TextColor3 = THEME.Warning
                Tween(StatusDot, {BackgroundColor3 = THEME.Warning})
                
                for _, btn in ipairs(ButtonCache) do btn.Visible = false end
                StatsData.Count.Text = "Words: 0"
            end
            
            listUpdatePending = false
            forceUpdateList = false
            currentBestMatch = nil
            lastDetected = detected
            lastRequiredLetter = requiredLetter
        end
        
        if listUpdatePending and (now - lastInputTime > LIST_DEBOUNCE) then
            listUpdatePending = false
            UpdateList(lastDetected, lastRequiredLetter)
            
            local visCount = 0
            for _, b in ipairs(ButtonCache) do
                if b.Visible then visCount = visCount + 1 end
            end
            StatsData.Count.Text = "Words: " .. visCount .. "+"
        end

        if not isVisible then
            if StatusText.Text ~= "Not in Round" then
                StatusText.Text = "Not in Round"
                StatusText.TextColor3 = THEME.SubText
                Tween(StatusDot, {BackgroundColor3 = THEME.SubText})
                for _, btn in ipairs(ButtonCache) do btn.Visible = false end
                StatsData.Count.Text = "Words: 0"
            end
            lastDetected = "---"
        elseif detected ~= lastDetected or requiredLetter ~= lastRequiredLetter or forceUpdateList then
            currentBestMatch = nil
            lastDetected = detected
            lastRequiredLetter = requiredLetter
            
            if detected == "" and not forceUpdateList then
                StatusText.Text = "Waiting..."
                StatusText.TextColor3 = THEME.SubText
                Tween(StatusDot, {BackgroundColor3 = THEME.SubText})
                
                UpdateList("", requiredLetter)
                listUpdatePending = false
                
                local visCount = 0
                for _, b in ipairs(ButtonCache) do
                    if b.Visible then visCount = visCount + 1 end
                end
                StatsData.Count.Text = "Words: " .. visCount .. "+"
            else
                if detected ~= "" then
                    local isCompleted = false
                    if #detected > 2 then
                        local c = detected:sub(1,1)
                        if c ~= "#" and Buckets and Buckets[c] then
                            for _, w in ipairs(Buckets[c]) do
                                if w == detected then
                                    isCompleted = true
                                    break
                                end
                            end
                        end
                    end

                    if isCompleted then
                        StatusText.Text = "Completed: " .. detected .. " <font color=\"rgb(100,255,140)\">✓</font>"
                        StatusText.TextColor3 = THEME.Success
                        Tween(StatusDot, {BackgroundColor3 = THEME.Success})
                    else
                        StatusText.Text = "Input: " .. detected
                        StatusText.TextColor3 = THEME.Accent
                        Tween(StatusDot, {BackgroundColor3 = THEME.Warning})
                    end
                end
                
                if forceUpdateList then
                    listUpdatePending = true
                    lastInputTime = 0
                    forceUpdateList = false
                else
                    listUpdatePending = true
                    lastInputTime = now
                end
            end
        end

        if autoPlay and not isTyping and not isAutoPlayScheduled and currentBestMatch and detected == lastDetected then
            local isMyTurnCheck, _ = GetTurnInfo(frame)
            if isMyTurnCheck then
                isAutoPlayScheduled = true
                local targetWord = currentBestMatch
                local snapshotDetected = lastDetected
                
                task.spawn(function()
                    local delay = isBlatant and 0.15 or (0.8 + math.random() * 0.5)
                    task.wait(delay)
                    
                    local stillMyTurn, _ = GetTurnInfo()
                    if autoPlay and not isTyping and GetCurrentGameWord() == snapshotDetected and stillMyTurn then
                         SmartType(targetWord, snapshotDetected, false)
                    end
                    isAutoPlayScheduled = false
                end)
            end
        end
    end)
end)

-- Temporary Last Letter rejection UI inspector.
-- Press F7 immediately before submitting a known rejected word.
env.WordHelperUIDebugger = env.WordHelperUIDebugger or {
    Active = false,
    FileName = "WordHelper_UI_Sound_Debug.txt",
    Duration = 8.0,
    PollRate = 0.025
}

env.WordHelperUIDebugger.GetPath = function(obj, root)
    local parts = {}
    local current = obj
    while current and current ~= root do
        table.insert(parts, 1, current.Name)
        current = current.Parent
    end
    if root then
        table.insert(parts, 1, root.Name)
    end
    return table.concat(parts, ".")
end

env.WordHelperUIDebugger.ReadObject = function(obj, root)
    local state = {
        ClassName = obj.ClassName,
        Path = env.WordHelperUIDebugger.GetPath(obj, root)
    }

    if obj:IsA("GuiObject") then
        state.Visible = obj.Visible
        state.BackgroundTransparency = obj.BackgroundTransparency
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        state.Text = tostring(obj.Text or "")
        state.TextTransparency = obj.TextTransparency
    end

    if obj:IsA("ScreenGui") then
        state.Enabled = obj.Enabled
    end

    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        state.ImageTransparency = obj.ImageTransparency
        state.Image = tostring(obj.Image or "")
    end

    return state
end

env.WordHelperUIDebugger.Snapshot = function()
    local player = Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local inGame = gui and gui:FindFirstChild("InGame")
    local snapshot = {}

    if not inGame then
        return snapshot, nil
    end

    snapshot[inGame] = env.WordHelperUIDebugger.ReadObject(inGame, inGame)
    for _, obj in ipairs(inGame:GetDescendants()) do
        if obj:IsA("GuiObject")
            or obj:IsA("ScreenGui")
            or obj:IsA("UIStroke")
            or obj:IsA("UIGradient") then
            snapshot[obj] = env.WordHelperUIDebugger.ReadObject(obj, inGame)
        end
    end

    return snapshot, inGame
end

env.WordHelperUIDebugger.StateToString = function(state)
    if not state then return "<missing>" end
    local parts = {
        "class=" .. tostring(state.ClassName),
        "path=" .. tostring(state.Path)
    }

    if state.Text ~= nil then
        table.insert(parts, "text=" .. string.format("%q", state.Text))
    end
    if state.Visible ~= nil then
        table.insert(parts, "visible=" .. tostring(state.Visible))
    end
    if state.Enabled ~= nil then
        table.insert(parts, "enabled=" .. tostring(state.Enabled))
    end
    if state.BackgroundTransparency ~= nil then
        table.insert(parts, "bgT=" .. tostring(state.BackgroundTransparency))
    end
    if state.TextTransparency ~= nil then
        table.insert(parts, "textT=" .. tostring(state.TextTransparency))
    end
    if state.ImageTransparency ~= nil then
        table.insert(parts, "imageT=" .. tostring(state.ImageTransparency))
    end
    if state.Image ~= nil and state.Image ~= "" then
        table.insert(parts, "image=" .. string.format("%q", state.Image))
    end

    return table.concat(parts, " | ")
end

env.WordHelperUIDebugger.StatesDiffer = function(a, b)
    if not a or not b then return true end
    return a.Text ~= b.Text
        or a.Visible ~= b.Visible
        or a.Enabled ~= b.Enabled
        or a.BackgroundTransparency ~= b.BackgroundTransparency
        or a.TextTransparency ~= b.TextTransparency
        or a.ImageTransparency ~= b.ImageTransparency
        or a.Image ~= b.Image
        or a.Path ~= b.Path
        or a.ClassName ~= b.ClassName
end

env.WordHelperUIDebugger.SoundPath = function(sound)
    local ok, fullName = pcall(function() return sound:GetFullName() end)
    if ok then return fullName end
    return tostring(sound.Name or "<sound>")
end

env.WordHelperUIDebugger.SoundToString = function(sound)
    local fields = {
        "path=" .. env.WordHelperUIDebugger.SoundPath(sound),
        "soundId=" .. string.format("%q", tostring(sound.SoundId or "")),
        "name=" .. string.format("%q", tostring(sound.Name or ""))
    }
    local okVol, vol = pcall(function() return sound.Volume end)
    if okVol then table.insert(fields, "volume=" .. tostring(vol)) end
    local okSpeed, speed = pcall(function() return sound.PlaybackSpeed end)
    if okSpeed then table.insert(fields, "speed=" .. tostring(speed)) end
    local okLoop, looped = pcall(function() return sound.Looped end)
    if okLoop then table.insert(fields, "looped=" .. tostring(looped)) end
    local okPos, pos = pcall(function() return sound.TimePosition end)
    if okPos then table.insert(fields, "timePosition=" .. tostring(pos)) end
    return table.concat(fields, " | ")
end

env.WordHelperUIDebugger.Start = function()
    if env.WordHelperUIDebugger.Active then
        if ShowToast then
            ShowToast("F7 UI + sound capture is already running", "warning")
        end
        return
    end

    if not writefile then
        if ShowToast then
            ShowToast("Executor does not support writefile", "error")
        end
        return
    end

    local before, inGame = env.WordHelperUIDebugger.Snapshot()
    if not inGame then
        if ShowToast then
            ShowToast("InGame UI not found - enter a match first", "warning")
        end
        return
    end

    env.WordHelperUIDebugger.Active = true

    if ShowToast then
        ShowToast("F7 UI + sound capture started - submit word now", "success")
    end
    if StatusText then
        StatusText.Text = "F7 UI + sound capture running..."
        StatusText.TextColor3 = THEME.Warning
    end

    task.spawn(function()
        local started = tick()
        local previous = before
        local lines = {}
        local eventCount = 0
        local soundEvents = {}
        local soundEventCount = 0
        local soundConnections = {}
        local connectedSounds = {}

        local function logSound(kind, sound)
            soundEventCount = soundEventCount + 1
            table.insert(soundEvents, string.format(
                "[+%.3fs] %s | %s",
                tick() - started,
                kind,
                env.WordHelperUIDebugger.SoundToString(sound)
            ))
        end

        local function watchSound(sound)
            if not sound or not sound:IsA("Sound") or connectedSounds[sound] then return end
            connectedSounds[sound] = true

            local okPlayed, playedConn = pcall(function()
                return sound.Played:Connect(function()
                    logSound("PLAYED", sound)
                end)
            end)
            if okPlayed and playedConn then table.insert(soundConnections, playedConn) end

            local okEnded, endedConn = pcall(function()
                return sound.Ended:Connect(function()
                    logSound("ENDED", sound)
                end)
            end)
            if okEnded and endedConn then table.insert(soundConnections, endedConn) end

            local okProp, propConn = pcall(function()
                return sound:GetPropertyChangedSignal("Playing"):Connect(function()
                    if sound.Playing then
                        logSound("PLAYING_TRUE", sound)
                    end
                end)
            end)
            if okProp and propConn then table.insert(soundConnections, propConn) end
        end

        -- Watch sounds that already exist anywhere in the client and any sounds
        -- created during the capture. This is temporary diagnostics only.
        for _, obj in ipairs(game:GetDescendants()) do
            if obj:IsA("Sound") then watchSound(obj) end
        end
        local addedConn = game.DescendantAdded:Connect(function(obj)
            if obj:IsA("Sound") then
                watchSound(obj)
                logSound("SOUND_ADDED", obj)
            end
        end)
        table.insert(soundConnections, addedConn)

        table.insert(lines, "WordHelper Last Letter UI + Sound Capture")
        table.insert(lines, "Capture duration: " .. tostring(env.WordHelperUIDebugger.Duration) .. " seconds")
        table.insert(lines, "Started tick: " .. string.format("%.3f", started))
        table.insert(lines, "Initial UI objects: " .. tostring((function()
            local n = 0
            for _ in pairs(before) do n = n + 1 end
            return n
        end)()))
        table.insert(lines, "")
        table.insert(lines, "Initial Sound objects watched: " .. tostring((function()
            local n = 0
            for _ in pairs(connectedSounds) do n = n + 1 end
            return n
        end)()))
        table.insert(lines, "")
        table.insert(lines, "=== INITIAL IMPORTANT TEXT ===")

        for _, state in pairs(before) do
            if state.Text ~= nil and state.Text ~= "" then
                table.insert(lines, env.WordHelperUIDebugger.StateToString(state))
            end
        end
        table.insert(lines, "")
        table.insert(lines, "=== CHANGES ===")

        while not unloaded and (tick() - started) < env.WordHelperUIDebugger.Duration do
            task.wait(env.WordHelperUIDebugger.PollRate)

            local current, currentInGame = env.WordHelperUIDebugger.Snapshot()
            if not currentInGame then
                table.insert(lines, string.format("[+%.3fs] InGame UI disappeared", tick() - started))
                break
            end

            for obj, oldState in pairs(previous) do
                local newState = current[obj]
                if not newState then
                    eventCount = eventCount + 1
                    table.insert(lines, string.format(
                        "[+%.3fs] REMOVED | %s",
                        tick() - started,
                        env.WordHelperUIDebugger.StateToString(oldState)
                    ))
                elseif env.WordHelperUIDebugger.StatesDiffer(oldState, newState) then
                    eventCount = eventCount + 1
                    table.insert(lines, string.format(
                        "[+%.3fs] CHANGED | BEFORE: %s",
                        tick() - started,
                        env.WordHelperUIDebugger.StateToString(oldState)
                    ))
                    table.insert(lines, "           AFTER:  " .. env.WordHelperUIDebugger.StateToString(newState))
                end
            end

            for obj, newState in pairs(current) do
                if not previous[obj] then
                    eventCount = eventCount + 1
                    table.insert(lines, string.format(
                        "[+%.3fs] ADDED | %s",
                        tick() - started,
                        env.WordHelperUIDebugger.StateToString(newState)
                    ))
                end
            end

            previous = current
        end

        for _, conn in ipairs(soundConnections) do
            pcall(function() conn:Disconnect() end)
        end

        table.insert(lines, "")
        table.insert(lines, "=== SOUND EVENTS ===")
        if #soundEvents == 0 then
            table.insert(lines, "<no Sound.Played/Playing events detected>")
        else
            for _, eventLine in ipairs(soundEvents) do
                table.insert(lines, eventLine)
            end
        end
        table.insert(lines, "")
        table.insert(lines, "=== FINAL IMPORTANT TEXT ===")
        for _, state in pairs(previous) do
            if state.Text ~= nil and state.Text ~= "" then
                table.insert(lines, env.WordHelperUIDebugger.StateToString(state))
            end
        end
        table.insert(lines, "")
        table.insert(lines, "Total UI change events: " .. tostring(eventCount))
        table.insert(lines, "Total sound events: " .. tostring(soundEventCount))

        local ok, err = pcall(function()
            writefile(env.WordHelperUIDebugger.FileName, table.concat(lines, "\n"))
        end)

        env.WordHelperUIDebugger.Active = false

        if ok then
            if ShowToast then
                ShowToast("UI + sound capture saved: " .. env.WordHelperUIDebugger.FileName, "success")
            end
            if StatusText then
                StatusText.Text = "F7 capture saved (" .. tostring(eventCount) .. " UI / " .. tostring(soundEventCount) .. " sound)"
                StatusText.TextColor3 = THEME.Success
            end
        else
            if ShowToast then
                ShowToast("UI capture save failed", "error")
            end
            if StatusText then
                StatusText.Text = "F7 capture save failed: " .. tostring(err)
                StatusText.TextColor3 = THEME.Warning
            end
        end
    end)
end

inputConn = UserInputService.InputBegan:Connect(function(input)
    if unloaded then return end

    if input.KeyCode == Enum.KeyCode.F7 then
        env.WordHelperUIDebugger.Start()
        return
    end

    if input.KeyCode == Enum.KeyCode.F6 then
        if env.WordHelperUsedTracker and env.WordHelperUsedTracker.ClearUsedWords then
            env.WordHelperUsedTracker.ClearUsedWords(true)
        end
        return
    end

    if input.KeyCode == TOGGLE_KEY then ScreenGui.Enabled = not ScreenGui.Enabled end
end)

]=]

if writefile then
    writefile(WORDHELPER_FILE, WORDHELPER_SOURCE)
end

local compiled, compileError = loadstring(WORDHELPER_SOURCE)
if not compiled then
    warn("SCRIPT COMPILE ERROR:")
    warn(compileError)
    return
end

local ok, runtimeError = pcall(compiled)
if not ok then
    warn("SCRIPT RUNTIME ERROR:")
    warn(runtimeError)
end
