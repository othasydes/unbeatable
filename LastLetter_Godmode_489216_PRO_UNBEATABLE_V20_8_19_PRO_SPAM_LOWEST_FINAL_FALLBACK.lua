-- V20.8.19: F9 ignores LOWEST ENTRY ordering; Pro lowest-response is final fallback after all literal spams
-- WordHelper V20.8.3 lightweight launcher - Pro 489,216 / 12,546-word delta
-- V20.8.3: rejector temporarily disabled; Pro discovery recognizes the full Pro dictionary.
-- Dictionary is external/cached instead of embedded in this Lua source.

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
    ProCustomWords = {},
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
Config.ProCustomWords = Config.ProCustomWords or {}

-- V20.6.2: purge mistaken old Pro spellings from persisted custom-word config.
do
    local cleanedProCustomWords = {}
    local seenProCustomWords = {}
    for _, savedWord in ipairs(Config.ProCustomWords) do
        local w = tostring(savedWord or ""):lower()
        if w ~= "nlaka'pumax" and w ~= "nlaka pumax" and w ~= "nluka'pumax" then
            if w ~= "" and not seenProCustomWords[w] then
                seenProCustomWords[w] = true
                table.insert(cleanedProCustomWords, savedWord)
            end
        end
    end
    Config.ProCustomWords = cleanedProCustomWords
end

local CLEAN_SLATE_MARKER = "WordHelper_476670_CleanSlate.done"
if not (isfile and isfile(CLEAN_SLATE_MARKER)) then
    Config.CustomWords = {}
    if writefile then
        pcall(function() writefile("WordHelper_RejectedWords.json", "[]") end)
        pcall(function()
            writefile(
                "WordHelper_DiscoveredWords.json",
                HttpService:JSONEncode({pending = {}, ignored = {}})
            )
        end)
    end
    SaveConfig()
    if writefile then
        pcall(function() writefile(CLEAN_SLATE_MARKER, "476670") end)
    end
end

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

local fileName = "LastLetterLibrary_476670.txt"

-- V17 external dictionary source.
-- Upload LastLetterLibrary_476670.txt to this path in your existing GitHub repo.
-- WordHelper uses the cached local file whenever available, so normal launches do
-- not repeatedly download 476k words.
local dictionaryUrl =
    "https://raw.githubusercontent.com/othasydes/unbeatables/refs/heads/main/LastLetterLibrary_476670.txt"

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

-- V17: prefer the cached dictionary. Only hit GitHub when the cache is missing.
UpdateStatus("Loading 476,670 Casual + 12,546 Pro delta (489,216 total)...", THEME.Warning)

local Words = {}
local SeenWords = {}

-- Canonical exact-membership index for every word WordHelper actually loads.
WordHelperKnownWords = {}

local function EnsureDictionary(fname)
    if isfile and isfile(fname) then
        UpdateStatus("Using cached dictionary...", THEME.Success)
        return true
    end

    UpdateStatus("Downloading dictionary from GitHub...", THEME.Warning)
    local body = nil

    if request then
        local ok, res = pcall(function()
            return request({Url = dictionaryUrl, Method = "GET"})
        end)
        if ok and res and res.Body and #res.Body > 1000 then
            body = res.Body
        end
    end

    if not body then
        local ok, result = pcall(function()
            return game:HttpGet(dictionaryUrl .. "?cache=" .. tostring(os.time()))
        end)
        if ok and result and #result > 1000 then
            body = result
        end
    end

    if body and writefile then
        local ok = pcall(function() writefile(fname, body) end)
        if ok then
            UpdateStatus("Dictionary downloaded + cached!", THEME.Success)
            return true
        end
    end

    UpdateStatus("Dictionary missing - upload the V17 TXT to GitHub.", Color3.fromRGB(255, 80, 80))
    return false
end

local function LoadList(fname)
    UpdateStatus("Parsing word list...", THEME.Warning)
    if isfile and isfile(fname) then
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
        return true
    end
    UpdateStatus("No word list found!", Color3.fromRGB(255, 80, 80))
    return false
end

if EnsureDictionary(fileName) then
    LoadList(fileName)
end

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

-- V17 FAST PREFIX INDEX
-- Each 1-4 letter prefix points to a contiguous start/end range inside the sorted
-- Words array. This avoids binary-search + bucket scanning for every Unbeatable
-- reply-count query without storing millions of duplicate word references.
local PrefixRanges = {}

local function RebuildPrefixRanges()
    PrefixRanges = {}
    local total = #Words

    for i, w in ipairs(Words) do
        local maxLen = math.min(4, #w)
        for n = 1, maxLen do
            local p = w:sub(1, n)
            local range = PrefixRanges[p]
            if range then
                range[2] = i
            else
                PrefixRanges[p] = {i, i}
            end
        end

        -- Yield occasionally during startup so Roblox does not appear frozen.
        if i % 30000 == 0 then
            task.wait()
        end
    end
end

UpdateStatus("Building fast 1-4 letter prefix index...", THEME.Warning)
RebuildPrefixRanges()
UpdateStatus("Prefix index ready!", THEME.Success)

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
    "__LOWEST_ENTRY__",
    "__X__"
}

GodmodeSanitizePriority = function(list)
    local cleaned = {}
    local seen = {}

    if type(list) ~= "table" then list = GodmodeDefaultPriority end

    for _, value in ipairs(list) do
        local item = tostring(value or "")
        if item == "__TRAP__" or item == "__LOWEST_ENTRY__" or item == "__X__" then
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

    -- Keep all hardcoded special categories available even with older saved configs.
    if not seen["__TRAP__"] then table.insert(cleaned, 1, "__TRAP__") end

    if not seen["__LOWEST_ENTRY__"] then
        local insertAt = #cleaned + 1
        for i, existing in ipairs(cleaned) do
            if existing == "__X__" then
                insertAt = i
                break
            end
        end
        table.insert(cleaned, insertAt, "__LOWEST_ENTRY__")
    end

    if not seen["__X__"] then table.insert(cleaned, "__X__") end

    return cleaned
end

Config.GodmodePriority = GodmodeSanitizePriority(Config.GodmodePriority)

CustomTrapWords = CustomTrapWords or {}

-- V20.4: exact 2-letter returns confirmed by the user to work in casual servers.
-- This table is length-specific: it NEVER suppresses/pollutes a valid 3/4-letter
-- return that merely ends in one of these pairs.
GodmodeConfirmedTwoLetter = {
    ["zi"]=true, ["sd"]=true, ["md"]=true, ["mg"]=true, ["rg"]=true,
    ["yg"]=true, ["yp"]=true, ["yc"]=true, ["mh"]=true, ["nh"]=true,
    ["dh"]=true, ["kh"]=true, ["dz"]=true, ["lw"]=true, ["dw"]=true,
    ["sf"]=true, ["sv"]=true, ["tz"]=true, ["tx"]=true, ["kt"]=true,
    ["nk"]=true, ["hl"]=true, ["yw"]=true, ["bt"]=true, ["mb"]=true,
    ["fd"]=true, ["pk"]=true, ["sz"]=true, ["hd"]=true, ["pf"]=true,
    ["cw"]=true, ["kw"]=true, ["sb"]=true, ["sg"]=true
}

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
    for index, category in ipairs(Config.GodmodePriority) do
        if category == "__TRAP__" then
            if GodmodeIsTrapWord(word) then
                return true, index, true
            end
        elseif category == "__LOWEST_ENTRY__" then
            -- Dedicated lazy search handles this special category.
        elseif category == "__X__" then
            if word:sub(-1) == "x" then
                return true, index, false
            end
        elseif #word >= #category and word:sub(-#category) == category then
            return true, index, false
        end
    end
    return false, nil, false
end

GodmodeLowestEntryActiveSet = GodmodeLowestEntryActiveSet or {}
GodmodeLowestEntryActiveInfo = GodmodeLowestEntryActiveInfo or {}
GodmodeLowestEntryCache = GodmodeLowestEntryCache or {}

GodmodeGetPriorityCategory = function(word)
    local exhaustedIndex = nil
    local exhaustedEnding = nil

    for index, category in ipairs(Config.GodmodePriority) do
        if category == "__TRAP__" then
            if GodmodeIsTrapWord(word) then
                return "TRAP", index, false, nil
            end
        elseif category == "__LOWEST_ENTRY__" then
            if GodmodeLowestEntryActiveSet[word] then
                return "LOWEST ENTRY", index, false, GodmodeLowestEntryActiveInfo[word]
            end
        elseif category == "__X__" then
            if word:sub(-1) == "x" then
                return "X", index, false, nil
            end
        elseif #word >= #category and word:sub(-#category) == category then
            if GodmodeHasAvailableReply(category) then
                return category:upper(), index, false, nil
            elseif not exhaustedIndex then
                exhaustedIndex = index
                exhaustedEnding = category
            end
        end
    end

    if exhaustedIndex then
        return exhaustedEnding:upper() .. " EXHAUSTED", exhaustedIndex, true, nil
    end

    return "", nil, false, nil
end

local function GetGodmodeScore(word)
    local category, categoryIndex, exhausted, lowestInfo = GodmodeGetPriorityCategory(word)

    if categoryIndex and not exhausted then
        if category == "LOWEST ENTRY" and lowestInfo then
            -- Keep the word inside LOWEST ENTRY's exact priority slot while ranking
            -- lower non-self pools first. The fractional bonus can never jump a row.
            local poolBonus = 0.90 / math.max(1, lowestInfo.NonSelfReplies - 2)
            local prefixBonus = math.min(#lowestInfo.Prefix, 4) * 0.001
            return (10000 - categoryIndex) + poolBonus + prefixBonus
        end
        return 10000 - categoryIndex
    end

    -- Exhausted strategic endings remain visible only as a final fallback.
    if categoryIndex and exhausted then
        return -1000 - categoryIndex
    end

    -- Ordinary exact-prefix words ALWAYS remain available as fallback.
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
            local char = text:match("starting with:%s*([A-Za-z][A-Za-z'%-]*)")
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

-- V20.8.8 LONG-WORD DISPLAY LOCK
-- Last Letter's CurrentWord presentation can become a sliding/truncated window on
-- very long entries. WordHelper used to interpret that window as a brand-new prefix,
-- causing the selected long suggestion to disappear midway through typing.
--
-- Once the player has clearly begun the current long recommendation, preserve that
-- target and reconstruct the logical full typed prefix from the visible window.
env.WordHelperLongWord = env.WordHelperLongWord or {
    Word = "",
    Progress = 0,
    LastVisible = "",
    Active = false
}

env.WordHelperLongWord.Reset = function()
    env.WordHelperLongWord.Word = ""
    env.WordHelperLongWord.Progress = 0
    env.WordHelperLongWord.LastVisible = ""
    env.WordHelperLongWord.PreviousDetected = ""
    env.WordHelperLongWord.SlidingFull = ""
    env.WordHelperLongWord.SlidingWindow = ""
    env.WordHelperLongWord.Active = false
end

env.WordHelperLongWord.MaybeLock = function(word, typedPrefix)
    -- V20.8.12: deliberately disabled. Long-word handling is now reconstruction-only,
    -- so backspacing immediately restores the normal dynamic suggestion list.
    return
end

env.WordHelperLongWord.ReconstructSliding = function(previousText, rawText)
    local state = env.WordHelperLongWord
    local function clean(v)
        v = tostring(v or ""):lower():gsub("%.%.%.", ""):gsub("…", "")
        return v:gsub("[^a-z'%-]", "")
    end
    local previous = clean(previousText)
    local raw = tostring(rawText or ""):lower()
    local overflow = raw:find("%.%.%.") ~= nil or raw:find("…",1,true) ~= nil
    local visible = clean(raw)

    if not overflow then
        state.SlidingFull, state.SlidingWindow = visible, visible
        return visible
    end

    local full = clean(state.SlidingFull or previous)
    local oldWindow = clean(state.SlidingWindow or "")
    if full == "" then full = previous end
    if visible == "" then return full end

    local pos, from = nil, 1
    while true do
        local p = full:find(visible, from, true)
        if not p then break end
        pos, from = p, p + 1
    end
    if pos then
        full = full:sub(1,pos-1)..visible
        state.SlidingFull,state.SlidingWindow=full,visible
        return full
    end

    for overlap=math.min(#full,#visible),1,-1 do
        if full:sub(-overlap)==visible:sub(1,overlap) then
            full=full..visible:sub(overlap+1)
            state.SlidingFull,state.SlidingWindow=full,visible
            return full
        end
    end

    -- Typo recovery uses letters only for comparison, but retains exact punctuation.
    if oldWindow~="" then
        local oldLetters=oldWindow:gsub("[^a-z]","")
        local newLetters=visible:gsub("[^a-z]","")
        local common,limit=0,math.min(#oldLetters,#newLetters)
        for i=1,limit do
            if oldLetters:sub(i,i)~=newLetters:sub(i,i) then break end
            common=i
        end
        if common>=math.min(3,limit) then
            local oldPos=full:find(oldWindow,1,true)
            if oldPos then
                full=full:sub(1,oldPos-1)..visible
                state.SlidingFull,state.SlidingWindow=full,visible
                return full
            end
        end
    end

    state.SlidingWindow=visible
    return full
end

env.WordHelperLongWord.Resolve = function(visibleText, requiredLetter)
    -- Preserve real Pro-prefix punctuation such as t-i and apostrophe prefixes.
    local text = tostring(visibleText or ""):lower()
    text = text:gsub("%.%.%.", ""):gsub("…", "")
    return text:gsub("[^a-z'%-]", "")
end

env.WordHelperLongWord.Reset()

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
    -- V20.8.3: automatic/manual rejection is temporarily disabled.
    -- Keep the tracker implementation in-source so it can be restored later.
    return false
    --[[ REJECTOR_PRESERVED_IMPLEMENTATION
    word = tostring(word or ""):lower():gsub("[^a-z]", "")
    if #word < 2 or Blacklist[word] or UsedWords[word] then return false end

    Blacklist[word] = true
    if env.WordHelperUnbeatable
        and env.WordHelperUnbeatable.AdjustUnavailableWord
        and not UsedWords[word] then
        env.WordHelperUnbeatable.AdjustUnavailableWord(word, 1)
    end
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
    ]]
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

-- V20.8.3: rejector disabled; do not load persisted rejected words.
-- env.WordHelperBlacklistTracker.Load()

-- V20.7.3: one-time cleanup of entries the user re-tested successfully in-game.
-- These had been learned by the old global-Wrong race and must not remain hidden.
do
    local falseRejected = {
        allylmetals = true,
        idest = true,
        laibach = true,
        rgen = true,
        xi = true,
    }
    local changed = false
    for word in pairs(falseRejected) do
        if Blacklist[word] then
            Blacklist[word] = nil
            changed = true
        end
    end
    if changed then
        env.WordHelperBlacklistTracker.LiveBlacklist = Blacklist
        env.WordHelperBlacklistTracker.Save()
    end
end

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

    -- Casual/base dictionary membership.
    if WordHelperKnownWords[word] == true then
        return true
    end

    -- V20.8.3: while Pro Unbeatable is active, discovery must compare against
    -- the ENTIRE Pro pool, not only the 476,670-word Casual base.  The Pro
    -- delta keeps normalized lookup keys because many source entries contain
    -- punctuation that the in-game submitted word does not expose.
    if sortMode == "Pro Unbeatable" and env.WordHelperUnbeatable then
        if env.WordHelperUnbeatable.ProDictionaryDeltaSet
            and env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] then
            return true
        end
        if env.WordHelperUnbeatable.ProDictionaryNormalizedUnique
            and env.WordHelperUnbeatable.ProDictionaryNormalizedUnique[word] then
            return true
        end
        if env.WordHelperUnbeatable.ProExclusiveSet
            and env.WordHelperUnbeatable.ProExclusiveSet[word] then
            return true
        end
        if env.WordHelperUnbeatable.ProExclusiveNormalized
            and env.WordHelperUnbeatable.ProExclusiveNormalized[word] then
            return true
        end
    end

    return false
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
        if raw:match("^[A-Z][A-Z'%-]*$") and #raw >= 2 and #raw <= 40 then
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

            -- Also give the rejection tracker the exact submitted word seen on
            -- Last Letter's packet stream. A Wrong sound is global, so the
            -- blacklist system must match it back to THIS exact submission
            -- before it is allowed to blacklist anything.
            if env.WordHelperBlacklistTracker then
                env.WordHelperBlacklistTracker.LastPacketSubmittedWord = candidate
                env.WordHelperBlacklistTracker.LastPacketSubmittedAt = now
            end
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

            -- V20.8.6 SERVER-CONFIRMED USED WORD:
            -- Diagnostic #2 established the repeatable sequence:
            --   packet 26 (ChatBubble carrying the COMPLETE submitted word)
            --   -> packet 15 (AnswerResults)
            --   -> packet 8 (next returned prefix)
            -- Record the packet candidate here, at AnswerResults, rather than waiting
            -- for CurrentWord/Type UI to settle. This catches ultra-fast opponent words
            -- that may never exist for a full rendered frame on this client.
            --
            -- Crucially, this also eliminates the historical self-solve ambiguity:
            -- a returned prefix that happens to be a valid dictionary word is NOT a
            -- ChatBubble+AnswerResults submission, so the prompt itself is never marked
            -- used by this primary path. Only the exact completed submitted word is.
            if env.WordHelperUsedTracker
                and env.WordHelperUsedTracker.RecordObservedUsedWord then
                pcall(env.WordHelperUsedTracker.RecordObservedUsedWord, candidate, true)
            end
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
    elseif sortMode == "Godmode" then sortMode = "Unbeatable"
    elseif sortMode == "Unbeatable" then sortMode = "Pro Unbeatable"
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
env.WordHelperBlacklistBtn.Visible = false -- V20.8.3 rejector temporarily removed
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
env.WordHelperGodmodeEditor.Info.Text = "Top = highest priority. TRAP / LOWEST ENTRY / X are movable hardcoded priorities."
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

        local special = category == "__TRAP__"
            or category == "__LOWEST_ENTRY__"
            or category == "__X__"
        local editor
        if special then
            editor = Instance.new("TextLabel", row)
            if category == "__TRAP__" then
                editor.Text = "TRAP"
                editor.TextColor3 = THEME.Success
            elseif category == "__LOWEST_ENTRY__" then
                editor.Text = "LOWEST ENTRY"
                editor.TextColor3 = THEME.Warning
            else
                editor.Text = "X"
                editor.TextColor3 = THEME.Accent
            end
        else
            editor = Instance.new("TextBox", row)
            editor.Text = category
            editor.TextColor3 = THEME.Text
            editor.ClearTextOnFocus = false
        end
        editor.Size = UDim2.new(0, 145, 1, -6)
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
        up.Position = UDim2.new(0, 176, 0, 3)
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
        down.Position = UDim2.new(0, 218, 0, 3)
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
env.WordHelperBlacklistFrame.Visible = false -- V20.8.3 rejector temporarily removed
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
    WordBrowserFrame.Size = UDim2.new(0, 300, 0, 435)
    WordBrowserFrame.Position = UDim2.new(0.5, -150, 0.5, -217)
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

    -- V20.5: dedicated Pro-only dictionary insertion.
    -- These entries NEVER touch Words/Buckets/WordHelperKnownWords.
    local WBAddProWordBox = Instance.new("TextBox", WordBrowserFrame)
    WBAddProWordBox.Font = Enum.Font.Gotham
    WBAddProWordBox.TextSize = 12
    WBAddProWordBox.BackgroundColor3 = THEME.ItemBG
    WBAddProWordBox.Size = UDim2.new(0.70, 0, 0, 24)
    WBAddProWordBox.Position = UDim2.new(0.02, 0, 0, 110)
    WBAddProWordBox.TextColor3 = THEME.Text
    Instance.new("UICorner", WBAddProWordBox).CornerRadius = UDim.new(0, 4)
    SetupPhantomBox(WBAddProWordBox, "Add Pro-only word...")

    local WBAddProWordBtn = Instance.new("TextButton", WordBrowserFrame)
    WBAddProWordBtn.Text = "Add Pro"
    WBAddProWordBtn.Font = Enum.Font.GothamBold
    WBAddProWordBtn.TextSize = 10
    WBAddProWordBtn.TextColor3 = Color3.fromRGB(120, 200, 255)
    WBAddProWordBtn.BackgroundColor3 = THEME.ItemBG
    WBAddProWordBtn.Size = UDim2.new(0.24, 0, 0, 24)
    WBAddProWordBtn.Position = UDim2.new(0.74, 0, 0, 110)
    Instance.new("UICorner", WBAddProWordBtn).CornerRadius = UDim.new(0, 4)

    local WBSearchBtn = Instance.new("TextButton", WordBrowserFrame)
    WBSearchBtn.Text = "Go"
    WBSearchBtn.Font = Enum.Font.GothamBold
    WBSearchBtn.TextSize = 12
    WBSearchBtn.BackgroundColor3 = THEME.Accent
    WBSearchBtn.Size = UDim2.new(0.1, 0, 0, 24)
    WBSearchBtn.Position = UDim2.new(0.88, 0, 0, 45)
    Instance.new("UICorner", WBSearchBtn).CornerRadius = UDim.new(0, 4)

    local WBList = Instance.new("ScrollingFrame", WordBrowserFrame)
    WBList.Size = UDim2.new(1, -20, 1, -195)
    WBList.Position = UDim2.new(0, 10, 0, 145)
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

        -- Custom insertion changes sorted-array positions, so rebuild the compact
        -- prefix ranges here. Manual word additions are rare; gameplay stays fast.
        RebuildPrefixRanges()

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

    local function AddProWordFromBrowser()
        local raw = tostring(WBAddProWordBox.Text or "")
        if raw == "" or raw == "Add Pro-only word..." then return end

        -- Preserve punctuation that Pro servers demonstrably support, while removing
        -- spaces/control characters around accidental paste/typing.
        local word = raw:lower():gsub("[%s%c]+", "")

        if #word < 2 then
            ShowToast("Pro words must be at least 2 characters.", "warning")
            return
        end

        -- Pro additions allow internal apostrophes and hyphens, e.g.
        -- nlaka'pamux / xes-as-a-service.
        if not word:match("^[a-z][a-z'%-]*[a-z]$")
            and not word:match("^[a-z][a-z]$") then
            ShowToast("Pro words may use A-Z, internal apostrophes, and hyphens.", "warning")
            return
        end

        Config.ProCustomWords = Config.ProCustomWords or {}

        local function normalized(v)
            return tostring(v or ""):lower():gsub("[^a-z]", "")
        end

        local norm = normalized(word)

        -- Check both canonical spelling and punctuation-stripped identity.
        if env.WordHelperUnbeatable
            and env.WordHelperUnbeatable.ProExclusiveNormalized
            and env.WordHelperUnbeatable.ProExclusiveNormalized[norm] then
            ShowToast(word .. " is already in the Pro dictionary.", "warning")
            return
        end

        for _, existing in ipairs(Config.ProCustomWords) do
            if existing == word or normalized(existing) == norm then
                ShowToast(word .. " is already in your Pro-only words.", "warning")
                return
            end
        end

        table.insert(Config.ProCustomWords, word)
        SaveConfig()

        -- Refresh ONLY the isolated Pro dictionary. No normal dictionary arrays
        -- or prefix indexes are touched.
        if env.WordHelperUnbeatable
            and env.WordHelperUnbeatable.RefreshProExclusiveWords then
            env.WordHelperUnbeatable.RefreshProExclusiveWords()
        end

        env.WordHelperUnbeatable.ProSortCache = {}
        forceUpdateList = true
        lastDetected = "---"

        WBAddProWordBox.Text = ""
        WBAddProWordBox:ReleaseFocus()

        if UpdateList then
            UpdateList(cachedDetected or "", lastRequiredLetter)
        end

        ShowToast("Added to Pro-only dictionary: " .. word, "success")
    end

    WBAddProWordBtn.MouseButton1Click:Connect(AddProWordFromBrowser)
    WBAddProWordBox.FocusLost:Connect(function(enter)
        if enter then AddProWordFromBrowser() end
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


-- ============================================================
-- UNBEATABLE MODE v2 - exact 5-turn stages + return qualification
-- ============================================================
env.WordHelperUnbeatable = env.WordHelperUnbeatable or {}
env.WordHelperUnbeatable.PrefixVersion = env.WordHelperUnbeatable.PrefixVersion or {}
env.WordHelperUnbeatable.Stage = 1
env.WordHelperUnbeatable.ObservedStage = 1
env.WordHelperUnbeatable.CompletedTurns = 0
env.WordHelperUnbeatable.CurrentTurn = 1
env.WordHelperUnbeatable.WasMyTurn = false
env.WordHelperUnbeatable.ReplyCache = {}
env.WordHelperUnbeatable.SortCache = {}
env.WordHelperUnbeatable.ProSortCache = {}

-- Confirmed in-game 2-letter returns. These have been manually observed to
-- actually trigger as 2-letter prefixes, so Stage 2 prioritizes them instead
-- of assuming every dictionary-qualified 2-letter suffix is returned by game.
env.WordHelperUnbeatable.KnownTwoLetterTraps = {
    ez=true, zi=true, sd=true, md=true, mg=true, rg=true, yg=true, yp=true, yc=true,
    mh=true, nh=true, dh=true, kh=true, dz=true, lw=true, dw=true, sf=true, sv=true, tz=true,
    tx=true, kt=true, nk=true, hl=true, yw=true, bt=true, mb=true, fd=true, pk=true,
    sz=true, hd=true, pf=true, cw=true, kw=true, sb=true, sg=true
}

-- V16: 2-letter prefixes confirmed by live testing to NOT trigger as standalone
-- Stage-2 returns. This suppression is length-specific only; the same final pair
-- can still participate normally in valid 3- or 4-letter prefixes later.
env.WordHelperUnbeatable.SuppressedTwoLetter = {
    ["bb"] = true,
    ["bf"] = true,
    ["bt"] = true,
    ["cm"] = true,
    ["cp"] = true,
    ["db"] = true,
    ["dc"] = true,
    ["dg"] = true,
    ["dl"] = true,
    ["dn"] = true,
    ["dt"] = true,
    ["fc"] = true,
    ["ft"] = true,
    ["gj"] = true,
    ["gm"] = true,
    ["gp"] = true,
    ["gt"] = true,
    ["hc"] = true,
    ["ii"] = true,
    ["iq"] = true,
    ["kb"] = true,
    ["kj"] = true,
    ["km"] = true,
    ["kp"] = true,
    ["lc"] = true,
    ["lg"] = true,
    ["lm"] = true,
    ["lv"] = true,
    ["mm"] = true,
    ["mt"] = true,
    ["mv"] = true,
    ["mw"] = true,
    ["mz"] = true,
    ["nj"] = true,
    ["np"] = true,
    ["nr"] = true,
    ["nt"] = true,
    ["qt"] = true,
    ["rc"] = true,
    ["rf"] = true,
    ["rl"] = true,
    ["rw"] = true,
    ["tp"] = true,
    ["tv"] = true,
    ["ue"] = true,
    ["uj"] = true,
    ["uw"] = true,
    ["vh"] = true,
    ["vs"] = true,
    ["vt"] = true,
    ["wt"] = true,
    ["xr"] = true,
    ["yb"] = true,
    ["yd"] = true,
    ["yf"] = true,
    ["ys"] = true,
    ["zl"] = true,
    ["zm"] = true,
}


-- Last Letter prefix stages (the increase happens ON every 5th turn):
--   turns  1-4  -> max return length 1
--   turns  5-9  -> max return length 2
--   turns 10-14 -> max return length 3
--   turns 15+   -> max return length 4 (stays at 4 until match reset)
local function UnbeatableStageForCompletedTurns(completedTurns)
    completedTurns = math.max(0, tonumber(completedTurns) or 0)
    local currentTurn = completedTurns + 1
    -- Confirmed rule: turns 1-5=S1, 6-10=S2, 11-15=S3, 16+=S4.
    return math.clamp(math.floor(completedTurns / 5) + 1, 1, 4)
end

local function UnbeatableCountUsedWords()
    local count = 0
    for _ in pairs(UsedWords) do
        count = count + 1
    end
    return count
end

env.WordHelperUnbeatable.MatchStartUsedCount = env.WordHelperUnbeatable.MatchStartUsedCount or 0

env.WordHelperUnbeatable.ResetStage = function()
    env.WordHelperUnbeatable.Stage = 1
    env.WordHelperUnbeatable.ObservedStage = 1
    env.WordHelperUnbeatable.CompletedTurns = 0
    env.WordHelperUnbeatable.CurrentTurn = 1
    env.WordHelperUnbeatable.WasMyTurn = false
    env.WordHelperUnbeatable.MatchStartUsedCount = 0
    env.WordHelperUnbeatable.ReplyCache = {}
    env.WordHelperUnbeatable.SortCache = {}
    env.WordHelperUnbeatable.ProSortCache = {}
end

-- Manual/new-match prefix reset without deleting UsedWords.  Record how many
-- used words existed at the start of this match, then count only words accepted
-- AFTER that baseline for the 1 -> 2 -> 3 -> 4 prefix progression.
env.WordHelperUnbeatable.ResetPrefixCounter = function()
    env.WordHelperUnbeatable.MatchStartUsedCount = UnbeatableCountUsedWords()
    env.WordHelperUnbeatable.Stage = 1
    env.WordHelperUnbeatable.ObservedStage = 1
    env.WordHelperUnbeatable.CompletedTurns = 0
    env.WordHelperUnbeatable.CurrentTurn = 1
    env.WordHelperUnbeatable.WasMyTurn = false
    env.WordHelperUnbeatable.ReplyCache = {}
    env.WordHelperUnbeatable.SortCache = {}
    env.WordHelperUnbeatable.ProSortCache = {}
    forceUpdateList = true
end

-- UsedWords is populated by the authoritative server AnswerResults path.
-- Five completed answers means the NEXT turn is turn 6/stage 2; ten means
-- turn 11/stage 3; fifteen means turn 16/stage 4. MatchStartUsedCount lets F5 restart
-- this progression without throwing away the used-word filter.
env.WordHelperUnbeatable.SyncStageFromUsedWords = function()
    local totalUsed = UnbeatableCountUsedWords()
    local baseline = math.max(0, tonumber(env.WordHelperUnbeatable.MatchStartUsedCount) or 0)
    if totalUsed < baseline then
        baseline = 0
        env.WordHelperUnbeatable.MatchStartUsedCount = 0
    end
    local completed = math.max(0, totalUsed - baseline)
    local countedStage = UnbeatableStageForCompletedTurns(completed)
    local newStage = countedStage
    local oldStage = env.WordHelperUnbeatable.Stage

    env.WordHelperUnbeatable.CompletedTurns = completed
    env.WordHelperUnbeatable.CurrentTurn = completed + 1
    env.WordHelperUnbeatable.Stage = newStage
    env.WordHelperUnbeatable.ObservedStage = newStage

    if newStage ~= oldStage then
        -- Stage changes alter which suffix lengths can be returned, so cached
        -- strategy data must be rebuilt once. Avoid spawning a toast here: the
        -- stage observer runs from the live game loop and UI creation was causing
        -- unnecessary stutter at exactly the point the stage changed.
        -- V13: stage is part of candidate cache keys; reply counts themselves
        -- do not change merely because stage changes, so keep both caches warm.
        forceUpdateList = true
    end

    return newStage
end

-- Observation is a safety net only.  A shorter visible prefix NEVER lowers the
-- stage because late-game returns can legitimately fall back from 4 -> 3 -> 2 -> 1.
-- A longer observed prefix may raise the stage if an accepted turn was missed by
-- the used-word observer.
env.WordHelperUnbeatable.ObservePrefix = function(prefix)
    -- V10: intentionally does not affect turn/stage progression.
    -- UsedWords is the single source of truth so typing, backspacing, and
    -- transient prefix UI cannot move Unbeatable to another stage.
    return env.WordHelperUnbeatable.Stage
end

-- Count the responses that would still be available AFTER our candidate is used.
-- The raw cache excludes words that are already blacklisted/used; GetCandidateInfo
-- additionally subtracts our proposed candidate when it itself starts with the
-- returned suffix, because that word will become unavailable to the opponent.
-- V18.2 FAST: dynamic unavailable counts for 1-4 letter starting prefixes.
env.WordHelperUnbeatable.UnavailablePrefixCount = env.WordHelperUnbeatable.UnavailablePrefixCount or {}

env.WordHelperUnbeatable.RebuildUnavailablePrefixCount = function()
    local counts = {}

    local function addWord(word)
        word = tostring(word or ""):lower()
        for n = 1, math.min(4, #word) do
            local p = word:sub(1, n)
            counts[p] = (counts[p] or 0) + 1
        end
    end

    for word in pairs(Blacklist) do
        addWord(word)
    end
    for word in pairs(UsedWords) do
        if not Blacklist[word] then
            addWord(word)
        end
    end

    env.WordHelperUnbeatable.UnavailablePrefixCount = counts
end

env.WordHelperUnbeatable.AdjustUnavailableWord = function(word, delta)
    word = tostring(word or ""):lower()
    delta = tonumber(delta) or 0
    if delta == 0 or word == "" then return end

    local counts = env.WordHelperUnbeatable.UnavailablePrefixCount
    for n = 1, math.min(4, #word) do
        local p = word:sub(1, n)
        local nextValue = (counts[p] or 0) + delta
        if nextValue > 0 then
            counts[p] = nextValue
        else
            counts[p] = nil
        end
    end
end

env.WordHelperUnbeatable.RebuildUnavailablePrefixCount()

env.WordHelperUnbeatable.GetBaseReplyInfo = function(prefix)
    prefix = tostring(prefix or ""):lower()
    if prefix == "" then return 0, false end

    local range = PrefixRanges[prefix]
    if not range then return 0, false end

    local total = range[2] - range[1] + 1
    local unavailable = env.WordHelperUnbeatable.UnavailablePrefixCount[prefix] or 0
    local count = math.max(0, total - unavailable)
    local selfSolve = WordHelperKnownWords[prefix] == true
        and not Blacklist[prefix]
        and not UsedWords[prefix]

    return count, selfSolve
end

-- Return-rule model:
--   * ordinary prefix: at least 3 usable entries are required
--   * prefix that is itself still a usable word: at least 4 are required
-- We test suffixes longest-first up to the CURRENT stage.  This is what makes a
-- stage-4 word fall through to a true/exclusive 3-letter return only when its
-- 4-letter suffix does NOT qualify.  The same rule naturally continues 3 -> 2 -> 1.
env.WordHelperUnbeatable.GetCandidateInfo = function(candidate)
    local stageNow = math.clamp(tonumber(env.WordHelperUnbeatable.Stage) or 1, 1, 4)
    local pv = env.WordHelperUnbeatable.PrefixVersion
    local versionParts = {}
    for n = 1, math.min(stageNow, #candidate) do
        local suffix = candidate:sub(#candidate - n + 1)
        versionParts[#versionParts + 1] = suffix .. ":" .. tostring(pv[suffix] or 0)
    end
    local candidateCacheKey = tostring(candidate)
        .. "|s" .. tostring(stageNow)
        .. "|" .. table.concat(versionParts, ",")
    local cached = env.WordHelperUnbeatable.SortCache[candidateCacheKey]
    if cached then return cached end

    local stage = math.clamp(tonumber(env.WordHelperUnbeatable.Stage) or 1, 1, 4)
    local chosenPrefix = ""
    local replyCount = 999999
    local selfSolve = false
    local minimumRequired = 3
    local excessReplies = 999999
    local qualified = false

    for suffixLen = math.min(stage, #candidate), 1, -1 do
        local prefix = candidate:sub(-suffixLen)
        local baseCount, baseSelf = env.WordHelperUnbeatable.GetBaseReplyInfo(prefix)

        -- Our candidate has not been placed into UsedWords yet while suggestions
        -- are being sorted.  If it could also answer the suffix, remove it now to
        -- model the opponent's real post-play pool.
        local candidateWasCounted =
            candidate:sub(1, #prefix) == prefix
            and not Blacklist[candidate]
            and not UsedWords[candidate]

        local available = baseCount - (candidateWasCounted and 1 or 0)
        local availableSelf = baseSelf and candidate ~= prefix
        local required = availableSelf and 4 or 3

        -- The game only returns this suffix when it has enough valid continuations.
        -- If it does not qualify, keep falling back to the next shorter suffix.
        if available >= required then
            chosenPrefix = prefix
            replyCount = available
            selfSolve = availableSelf
            minimumRequired = required
            excessReplies = available - required
            qualified = true
            break
        end
    end

    -- Exact-minimum pools are the nastiest legal returns:
    -- 3 responses normally, or 4 when the returned prefix can self-solve.
    local perfectTrap = qualified and excessReplies == 0
    local knownTwoLetter = qualified
        and #chosenPrefix == 2
        and env.WordHelperUnbeatable.KnownTwoLetterTraps[chosenPrefix] == true

    -- Difficulty is primary.  An exact-minimum fallback is intentionally allowed
    -- to beat an easy longer suffix.  For equally difficult returns, prefer the
    -- longest return available at the current stage (4, then 3, then 2, then 1).
    local score
    if qualified then
        score = 20000000
            - math.min(excessReplies, 1000) * 100000
            + #chosenPrefix * 1000
            - replyCount * 10
        if perfectTrap then score = score + 5000000 end
        if selfSolve then score = score - 5 end

        -- Unknown/unverified 2-letter returns are still retained as a fallback,
        -- but confirmed in-game 2-letter traps are preferred whenever we need
        -- to drop from the reliable 3/4-letter analysis to a 2-letter return.
        if #chosenPrefix == 2 and not knownTwoLetter then
            score = score - 4000000
        end
    else
        -- Should be rare, but never leave the list empty: any playable word remains
        -- available as a final fallback when none of its suffixes qualifies.
        score = -1000000 - #candidate
    end

    local info = {
        Prefix = chosenPrefix,
        Replies = replyCount,
        SelfSolve = selfSolve,
        Minimum = minimumRequired,
        Excess = excessReplies,
        Qualified = qualified,
        Trap = perfectTrap,
        KnownTwoLetter = knownTwoLetter,
        SuppressedTwoLetter = (#chosenPrefix == 2
            and env.WordHelperUnbeatable.SuppressedTwoLetter[chosenPrefix] == true),
        Score = score,
        Stage = stage,
        Turn = env.WordHelperUnbeatable.CurrentTurn or 1
    }

    env.WordHelperUnbeatable.SortCache[candidateCacheKey] = info
    return info
end

-- ============================================================
-- V20.4 GODMODE LOWEST ENTRY
--
-- Runs ONLY when LOWEST ENTRY has no live priority above it for the current
-- prompt. It does not alter normal exact-prefix matching or normal fallbacks.
--
-- Qualification: minimum 3 replies EXCLUDING self-solve.
-- Returned suffix: longest valid suffix allowed by current stage.
-- Casual exact-2-letter returns: trusted only from GodmodeConfirmedTwoLetter.
-- 3/4-letter returns are preserved completely independently of their final pair.
-- ============================================================
GodmodeGetLowestEntryInfo = function(candidate)
    candidate = tostring(candidate or ""):lower()
    if candidate == "" then return nil end

    env.WordHelperUnbeatable.SyncStageFromUsedWords()
    local stage = math.clamp(tonumber(env.WordHelperUnbeatable.Stage) or 1, 1, 4)
    local pv = env.WordHelperUnbeatable.PrefixVersion

    local versionParts = {}
    for n = 1, math.min(stage, #candidate) do
        local p = candidate:sub(-n)
        versionParts[#versionParts + 1] = p .. ":" .. tostring(pv[p] or 0)
    end
    local key = candidate .. "|s" .. tostring(stage) .. "|" .. table.concat(versionParts, ",")
    local cached = GodmodeLowestEntryCache[key]
    if cached ~= nil then return cached or nil end

    local chosen = nil

    for suffixLen = math.min(stage, #candidate), 1, -1 do
        local prefix = candidate:sub(-suffixLen)

        -- Hidden casual-server 2-letter eligibility is length-specific.
        local allowed = suffixLen ~= 2 or GodmodeConfirmedTwoLetter[prefix] == true

        if allowed then
            local baseCount, baseSelf = env.WordHelperUnbeatable.GetBaseReplyInfo(prefix)

            local candidateWasCounted =
                candidate:sub(1, #prefix) == prefix
                and not Blacklist[candidate]
                and not UsedWords[candidate]

            local available = baseCount - (candidateWasCounted and 1 or 0)
            local selfAvailable = baseSelf and candidate ~= prefix
            local nonSelf = available - (selfAvailable and 1 or 0)

            if nonSelf >= 3 then
                chosen = {
                    Prefix = prefix,
                    NonSelfReplies = nonSelf,
                    TotalReplies = available,
                    SelfSolve = selfAvailable,
                    Stage = stage,
                    Turn = env.WordHelperUnbeatable.CurrentTurn or 1
                }
                break
            end
        end
    end

    GodmodeLowestEntryCache[key] = chosen or false
    return chosen
end

GodmodePrepareLowestEntry = function(exacts, bucket, prefix, tryFallbackLengths)
    table.clear(GodmodeLowestEntryActiveSet)
    table.clear(GodmodeLowestEntryActiveInfo)

    if type(exacts) ~= "table" or type(bucket) ~= "table" then return exacts end
    if not prefix or prefix == "" or prefix:find("#") or prefix:find("%*") then return exacts end

    local lowestIndex = nil
    for i, category in ipairs(Config.GodmodePriority) do
        if category == "__LOWEST_ENTRY__" then
            lowestIndex = i
            break
        end
    end
    if not lowestIndex then return exacts end

    -- Lazy gate: if ANY live configured category above LOWEST ENTRY is already
    -- present, LOWEST ENTRY does no work at all.
    for _, word in ipairs(exacts) do
        for i = 1, lowestIndex - 1 do
            local category = Config.GodmodePriority[i]
            if category == "__TRAP__" then
                if GodmodeIsTrapWord(word) then return exacts end
            elseif category == "__X__" then
                if word:sub(-1) == "x" then return exacts end
            elseif category ~= "__LOWEST_ENTRY__"
                and #word >= #category
                and word:sub(-#category) == category
                and GodmodeHasAvailableReply(category) then
                return exacts
            end
        end
    end

    local startIndex = BinarySearchStart(bucket, prefix)
    if startIndex == -1 then return exacts end

    -- Lowest Entry is a fallback strategy, so only now do we inspect the complete
    -- exact-prefix range. GetBaseReplyInfo is O(1), and per-word results are cached.
    local best = {}
    local keepLimit = 120

    local function better(a, b)
        if not b then return true end
        if a.Info.NonSelfReplies ~= b.Info.NonSelfReplies then
            return a.Info.NonSelfReplies < b.Info.NonSelfReplies
        end
        if #a.Info.Prefix ~= #b.Info.Prefix then
            return #a.Info.Prefix > #b.Info.Prefix
        end
        return #a.Word < #b.Word
    end

    local function addBest(word, info)
        local entry = {Word = word, Info = info}
        if #best < keepLimit then
            best[#best + 1] = entry
            return
        end

        local worstIndex = 1
        for j = 2, #best do
            if better(best[worstIndex], best[j]) then
                worstIndex = j
            end
        end

        if better(entry, best[worstIndex]) then
            best[worstIndex] = entry
        end
    end

    for i = startIndex, #bucket do
        local word = bucket[i]
        if word:sub(1, #prefix) ~= prefix then break end

        if not Blacklist[word]
            and (not UsedWords[word] or Config.ShowUsedWords)
            and (suffixMode == "" or word:sub(-#suffixMode) == suffixMode)
            and (lengthMode == 0 or tryFallbackLengths or #word == lengthMode) then

            local info = GodmodeGetLowestEntryInfo(word)
            if info then addBest(word, info) end
        end
    end

    table.sort(best, function(a, b) return better(a, b) end)

    local already = {}
    for _, word in ipairs(exacts) do already[word] = true end

    for _, entry in ipairs(best) do
        GodmodeLowestEntryActiveSet[entry.Word] = true
        GodmodeLowestEntryActiveInfo[entry.Word] = entry.Info

        if not already[entry.Word] then
            exacts[#exacts + 1] = entry.Word
            already[entry.Word] = true
        end
    end

    return exacts
end

-- ============================================================
-- V20.8.2 PRO 489,216 DICTIONARY DELTA
-- The normal 476,670 Casual dictionary remains untouched.  This embedded
-- delta contains only the 12,546 additional words present in the user's
-- current 489,216-word Pro union, so Pro Unbeatable gets the full Pro pool
-- without duplicating another ~476k strings in memory.
--
-- Punctuation is preserved exactly.  Returned punctuation prefixes are only
-- considered when they start with A-Z and are at least 3 characters long,
-- matching the observed game rule (e.g. GAL-O -> L-O at Stage 3).
-- ============================================================
env.WordHelperUnbeatable.ProDictionaryTotal = 489216
env.WordHelperUnbeatable.ProDictionaryDeltaWords = {}
env.WordHelperUnbeatable.ProDictionaryDeltaSet = {}
env.WordHelperUnbeatable.ProDictionaryDeltaBuckets = {}
env.WordHelperUnbeatable.ProDictionaryDeltaPrefixCount = {}
env.WordHelperUnbeatable.ProDictionaryDeltaUnavailable = {}
env.WordHelperUnbeatable.ProDictionaryNormalizedUnique = {}

env.WordHelperUnbeatable.InitProDictionaryDelta = function()
    local rawDelta = [==[
a-begging
a-bomb
a-bombs
a-cock-bill
a-fib
a-fibs
a-frame
a-frames
a-game
a-games
a-go-go
a-go-gos
a-ha
a-hole
a-holes
a-ideal
a-ideals
a-law
a-laws
a-life
a-lifes
a-line
a-lines
a-list
a-lister
a-listers
a-lists
a-methyl-p-tyrosine
a-ok
a-okay
a-optimal
a-optimalities
a-optimality
a-pose
a-poses
a-raf
a-rafs
a-road
a-roads
a-roll
a-rolls
a-side
a-sides
a-spot
a-spots
aariya
aaron's-beard
aaron's-beards
abamectin
abamectins
abat-jour
abaza
abdominal-a
abdominal-as
abdominal-b
abdominal-bs
abenaki
abhava
abhavas
abidji
abilities-to-be
ability-to-be
abipones
about-face
about-faced
about-faces
about-facing
about-turn
about-turned
about-turning
about-turns
above-mentioned
absent-mindedly
absent-mindedness
absent-mindednesses
abso-bloody-lutely
acanthodians
acanthodiis
ace-high
ace-k
ace-spec
ace-specs
acey-deucey
acey-deuceys
acey-deucies
acey-deucy
achma
achumawi
acibenzolar-s-methyl
acibenzolar-s-methyls
acid-citrate-dextrose
acid-citrate-dextroses
acid-fast
acid-fastness
acid-fastnesses
ack-ack
ack-acks
aclacinomycin
acnestis
aconitate
acoustic-electromagnetic
acqui-hire
acqui-hired
acqui-hires
acqui-hiring
acre-feet
acre-foot
acrylonitrile-butadiene-styrene
acrylonitrile-butadiene-styrenes
acyl-d-alanyl-d-alanine
acyl-d-alanyl-d-alanines
acyl-enzyme
acyl-enzymes
ad-hocracies
ad-hocracy
ad-lib
ad-libbed
ad-libbing
ad-libs
ad'iyah
add-in
add-ins
add-on
add-ons
addition-elimination
addition-eliminations
addon
addons
adioukrou
adirondacks
adja
adjukru
administrator-in-training
administrators-in-training
adnyamathanha
adsorption-desorption
adsorption-desorptions
adult-gerontologies
adult-gerontology
adyghe
adzera
aero-hydro-servo-elastic
aeruginosin
aeruginosins
africanfuturism
africanfuturisms
africanfuturist
africanfuturists
afrikaners
afro-beat
afro-beats
afro-funk
afro-fusion
afro-futurism
afro-futurisms
afro-futurist
afro-futurists
afro-latinx
afro-latinxs
afro-pop
afrofuturism
afrofuturisms
afrofuturist
afrofuturists
after-dark
after-dinner
after-five
after-hours
after-school
after-work
ag-gag
agar-agar
agar-agars
age-appropriate
age-appropriateness
age-appropriatenesses
age-at-harvest
age-long
age-old
age-worthiness
age-worthinesses
aggrupation
aggrupations
aghem
aglianico
aglianicos
agreeance
agreeances
agro-industrialisation
agro-industrialisations
agro-industrialization
agro-industrializations
ah-ha
ahtna
ahupua'a
aid-de-camp
aide-de-camp
aide-memoire
aides-de-camp
aides-memoire
aides-memoires
aids-de-camp
aim-inhibited
ain't
air-ball
air-balled
air-balling
air-balls
air-condition
air-conditioned
air-conditioning
air-conditions
air-dried
air-dries
air-dry
air-drying
air-kiss
air-kissed
air-kisses
air-kissing
air-to-air
air-to-ground
air-to-surface
airy-fairier
airy-fairiest
airy-fairy
aizi
ajawa
ajika
ajivikas
ajmalicine
ajmalicines
ajoblanco
ajoblancos
ajvar
ajvars
akans
akatek
akateko
akawaio
akebu
akhvakh
akiapolaau
akiapolaaus
akie
aklanon
akreophagists
akuammicine
akuammicines
akutak
akutaq
akutaqs
alacranite
alacranites
alagebrium
alago
alagwa
alak
alanyl-alanine
alanyl-alanines
alanyl-glutamine
alanylalanines
albiglutide
albitites
alef-beis
alef-bet
alefacept
alekano
aleph-beis
aleph-bet
aleph-noughts
aleph-null
aleph-nulls
aleph-zero
aleph-zeroes
aleph-zeros
algonkians
algorithm-as-a-service
algorithms-as-a-service
alice-in-wonderland
aliskiren
alkaloidoses
alkenone
alkenones
alkyl-lysophospholipid
alkyl-lysophospholipids
all-around
all-arounder
all-arounders
all-day
all-fired
all-hands-on-deck
all-important
all-in
all-in-one
all-in-ones
all-inclusive
all-inclusives
all-ins
all-knowing
all-natural
all-new
all-night
all-nighter
all-nighters
all-or-none
all-or-nothing
all-out
all-outer
all-outers
all-play-all
all-play-alls
all-powerful
all-pro
all-purpose
all-round
all-rounder
all-rounders
all-star
all-stars
all-time
all-timer
all-timers
all-trans
all-year
allabogdanite
allabogdanites
almotriptan
alnoites
alpha-adaptin
alpha-adaptins
alpha-adrenergic
alpha-adrenoreceptor
alpha-adrenoreceptors
alpha-amanitin
alpha-amanitins
alpha-bungarotoxin
alpha-bungarotoxins
alpha-carbon
alpha-carbons
alpha-catenin
alpha-catenins
alpha-complementation
alpha-complementations
alpha-conotoxin
alpha-conotoxins
alpha-cyclodextrin
alpha-cypermethrin
alpha-cypermethrins
alpha-difluoromethylornithine
alpha-difluoromethylornithines
alpha-endosulphan
alpha-galactosidase
alpha-galactosidases
alpha-galactosylceramide
alpha-galactosylceramides
alpha-hexachlorocyclohexane
alpha-hexachlorocyclohexanes
alpha-i-iduronidases
alpha-ketoglutarate
alpha-ketoglutarates
alpha-ketoisocaproate
alpha-ketoisocaproates
alpha-l-antitrypsin
alpha-l-antitrypsins
alpha-l-arabinofuranosidase
alpha-l-arabinofuranosidases
alpha-mannosidase
alpha-mannosidases
alpha-methyl-p-tyrosine
alpha-methyl-p-tyrosines
alpha-methyl-para-tyrosine
alpha-methyl-para-tyrosines
alpha-methylfentanyl
alpha-methylfentanyls
alpha-methylstyrene
alpha-methylstyrenes
alpha-methyltryptamine
alpha-methyltryptamines
alpha-n-acetylgalactosaminidase
alpha-n-acetylgalactosaminidases
alpha-n-acetylglucosaminidase
alpha-n-acetylglucosaminidases
alpha-naphthoflavone
alpha-naphthoflavones
alpha-naphthol
alpha-naphthols
alpha-naphthylisothiocyanate
alpha-naphthylisothiocyanates
alpha-phellandrene
alpha-phellandrenes
alpha-pinene
alpha-pinenes
alpha-quartz
alpha-quartzes
alpha-sarcoglycanopathies
alpha-sarcoglycanopathy
alpha-subunit
alpha-subunits
alpha-synucleinopathies
alpha-synucleinopathy
alprenolol
alprostadil
also-ran
also-rans
alt-center
alt-centers
alt-country
alt-left
alt-lefts
alt-light
alt-lights
alt-lite
alt-lites
alt-pop
alt-right
alt-righter
alt-righters
alt-rights
alt-rock
alt-tech
alt-techs
alter-global
alter-globalisation
alter-globalisations
alter-globalism
alter-globalisms
alter-globalist
alter-globalists
alter-globalization
alter-globalizations
alterna-rock
alto-relievi
alto-relievo
alto-relievos
alto-rilievi
alto-rilievo
alutiiq
alutor
alvimopan
always-on
alzheimer's
amarogentin
amarogentins
amastias
amatoxin
amatoxins
ambassador-at-large
ambassador-in-residence
ambassadors-at-large
ambassadors-in-residence
ambrisentan
ambroxol
amchur
amifostine
amikacin
amiloride
aminates
aminations
amino-terminal
amino-terminals
aminomethylated
aminomethylation
aminomethylations
amisulpride
amlexanox
amn't
amoeboflagellate
amoeboflagellates
amour-propre
amours-propres
amoxapine
amoxicillin-clavulanate
amoxicillin-clavulanates
amped-up
ampere-hour
ampere-hours
ampicillin-sulbactams
amuse-bouche
amuse-bouches
amuse-gueule
amuse-gueules
amuses-bouches
amylmetacresol
an-cap
an-caps
anaesthesiologist-resuscitator
anaesthesiologist-resuscitators
anagliptin
anakinra
anal-retentive
anal-retentiveness
anal-retentivenesses
anal-retentives
anarcha-feminism
anarcha-feminisms
anarcha-feminist
anarcha-feminists
anarcho-capitalism
anarcho-capitalisms
anarcho-capitalist
anarcho-capitalists
anarcho-communism
anarcho-communisms
anarcho-communist
anarcho-communists
anarcho-feminism
anarcho-feminisms
anarcho-feminist
anarcho-feminists
anarcho-pacifism
anarcho-pacifisms
anarcho-pacifist
anarcho-pacifists
anarcho-primitivism
anarcho-primitivisms
anarcho-primitivist
anarcho-primitivists
anarcho-queer
anarcho-queers
anarcho-syndicalism
anarcho-syndicalisms
anarcho-syndicalist
anarcho-syndicalists
anatoxin-a
anatoxin-as
andhbhakt
andhbhakti
andhbhakts
andorites
aneityum
anesthesiologist-resuscitator
anesthesiologist-resuscitators
anglo-catholic
anglo-catholicism
anglo-catholicisms
anglo-catholics
anglo-saxons
anidulafungin
anii
anjam
ankle-biter
ankle-biters
ankle-biting
ankle-bitings
ankole-watusi
ankole-watusis
ankyrin-b
ankyrin-g
ankyrin-gs
anmitsu
annexin
annexins
annulene
annulenes
anorexia-cachexia
anorexia-cachexias
another-guess
ant-follower
ant-followers
ant-tanager
ant-tanagers
anti-abortion
anti-abortionist
anti-abortionists
anti-academic
anti-acne
anti-adblock
anti-administration
anti-ageing
anti-ager
anti-agers
anti-aggression
anti-aggressive
anti-aging
anti-aim
anti-aims
anti-alcohol
anti-alcoholism
anti-aliasing
anti-aliasings
anti-alien
anti-allergenic
anti-allergenics
anti-allergic
anti-allergics
anti-allergy
anti-alzheimer
anti-alzheimer's
anti-american
anti-americanism
anti-americanisms
anti-anaemia
anti-anarchism
anti-anarchisms
anti-anarchist
anti-anarchists
anti-androgen
anti-androgenic
anti-androgens
anti-anemia
anti-annexation
anti-anthropocentrism
anti-anthropocentrisms
anti-anti-semitism
anti-anti-semitisms
anti-antibodies
anti-antibody
anti-antisemitism
anti-antisemitisms
anti-apartheid
anti-aphrodisiac
anti-aphrodisiacs
anti-aristocratic
anti-armor
anti-armour
anti-arrhythmia
anti-arrhythmic
anti-arrhythmics
anti-art
anti-arthritic
anti-arthritics
anti-arthritis
anti-arts
anti-assimilation
anti-asthma
anti-asthmatic
anti-atheism
anti-atheisms
anti-atheist
anti-atheists
anti-atherosclerotic
anti-authoritarian
anti-authoritarianism
anti-authoritarianisms
anti-authoritarians
anti-authority
anti-backlash
anti-ballistic
anti-bias
anti-black
anti-blackness
anti-blacknesses
anti-boss
anti-bourgeois
anti-boycott
anti-boycotts
anti-buddhist
anti-buddhists
anti-bug
anti-bugging
anti-bunching
anti-bunchings
anti-bureaucratic
anti-burglar
anti-burglary
anti-capitalism
anti-capitalisms
anti-capitalist
anti-capitalists
anti-catholic
anuak
anuki
anuta
anyin
anything-as-a-service
anythings-as-a-service
apalutamide
apamin
apamins
apicoectomies
apicolateral
apilimod
apple-of-peru
apple-pie
apple-pies
apple-polish
apple-polished
apple-polisher
apple-polishers
apple-polishes
apple-polishing
apples-of-peru
application-as-a-service
applications-as-a-service
apremilast
aprepitant
ara-gonite
ara-gonites
arabinitol
arabinitols
arabino-oligosaccharide
arabino-oligosaccharides
arabitols
arachidonate
arachidonates
arago
araki
arc-boutant
arc-connected
arch-fiend
arch-fiends
arch-nemeses
arch-nemesis
arch-villain
arch-villains
arcs-boutants
arctites
ardaites
aren't
arenberg-nordkirchner
arenberg-nordkirchners
arformoterol
arg-c
arg-cs
argatroban
argle-bargle
argle-bargles
argy-bargies
argy-bargy
arhuaco
aringa
aristolochines
arm-twist
arm-twisted
arm-twister
arm-twisters
arm-twisting
arm-twistings
arm-twists
arm-wrestle
arm-wrestled
arm-wrestler
arm-wrestlers
arm-wrestles
arm-wrestling
arm's-length
armodafinil
armor-piercing
armor-plated
armour-piercing
armour-plated
aro-ace
aro-aces
aronia
around-the-clock
arsenolamprite
arsenolamprites
art-rock
art-rocker
art-rockers
artemether-lumefantrine
artemether-lumefantrines
artesunate
artsy-craftsy
artsy-fartsy
arty-crafty
arty-farty
aruamu
arvanitika
as-a-services
as-told-to
as-told-tos
asabiyya
asabiyyah
asenapine
ash-blond
ash-blonde
ash'arisms
ash'arites
asmat
asp-n
asp-ns
aspartyls
asperger's
ass-kick
ass-kicked
ass-kicking
ass-kicks
ass-kisser
ass-kissers
ass-kissing
ass-kissings
assmannshauser
associate's
astasia-abasia
astasia-abasias
at-bat
at-bats
at-home
at-homeness
at-homenesses
at-large
at-risk
at-will
ataxia-telangiectasia
ataxia-telangiectasias
atazanavir
ateso
athlete-activist
athlete-activists
atikamekw
atogepant
atomoxetine
atorada
atovaquone
atrio-ventricular
atsugewi
attention-getter
attention-getters
attention-getting
attorney-at-law
attorneys-at-law
aucubin
aucubins
aunt-in-law
aunts-in-law
auranofin
aurorite
aurorites
austria-hungary
austro-hungarian
austro-hungarians
authentication-as-a-service
authentications-as-a-service
auto-antonym
auto-antonyms
auto-covariance
auto-covariances
auto-da-fe
auto-generate
auto-generated
auto-generates
auto-generating
auto-generation
auto-generations
auto-generator
auto-generators
auto-rebuy
auto-rebuys
auto-resonance
auto-resonances
auto-responder
auto-responders
auto-response
auto-responses
auto-rickshaw
auto-rickshaws
auto-sexing
auto-suggest
auto-suggested
auto-suggesting
auto-suggestion
auto-suggestions
auto-suggestive
auto-suggests
auto-tune
auto-tuned
auto-tunes
auto-tuning
auxlang
auxlangs
avacopan
avanafil
avant-garde
avant-gardes
avant-gardism
avant-gardisms
avant-gardist
avant-gardists
avant-prog
avatime
avatrombopag
avava
aven't
avermectin
avermectins
avibactam
avikam
aw-shucks
awadhi
awe-inspiring
awe-strike
awe-strikes
awe-striking
awe-struck
axe-money
axe-monies
axicon
ayat
ayats
aye-aye
aye-ayes
aymara
ayoreo
ayyam-i-ha
ayyavazhi
ayyavazhis
azacyclic
azelastine
azetidine
azetidines
azetidinone
azetidinones
azidothymidine-triphosphate
azidothymidine-triphosphates
azilsartan
azomethine-h
azomethine-hs
azoxyanisole
azoxyanisoles
azoxynaphthalenes
aztreonam
azurite-malachites
b-ball
b-baller
b-ballers
b-balls
b-boy
b-boying
b-boyings
b-boys
b-day
b-days
b-film
b-films
b-girl
b-girling
b-girlings
b-girls
b-graph
b-graphs
b-ideal
b-ideals
b-line
b-lines
b-list
b-lister
b-listers
b-lists
b-movie
b-movies
b-myc
b-mycs
b-raf
b-rafs
b-road
b-roads
b-roll
b-rolls
b-school
b-schools
b-side
b-sides
b-tree
b-trees
b-value
b-values
b-word
b-words
b'day
b'days
ba'ath
ba'athism
ba'athisms
ba'athist
ba'athists
baa-lamb
baa-lambs
babbler-vanga
babbler-vangas
baby-faced
baby-sit
bachelor's
back-alley
back-and-forth
back-and-forths
back-arc
back-arcs
back-burn
back-burned
back-burner
back-burnered
back-burnering
back-burners
back-burning
back-burns
back-channel
back-channeled
back-channeling
back-channelings
back-channelled
back-channelling
back-channellings
back-channels
back-check
back-checked
back-checker
back-checkers
back-checking
back-checks
back-end
back-ends
back-formation
back-formations
back-load
back-loaded
back-loading
back-loads
back-of-the-envelope
back-palm
back-palmed
back-palming
back-palms
back-pass
back-passes
back-projection
back-projections
back-scratching
back-scratchings
back-taxiing
back-to-back
back-to-backs
back-to-the-land
back-up
back-ups
backbone-as-a-service
bad-mouth
bad-mouthed
bad-mouthing
bad-mouths
bad-natured
bad-tempered
baghdadite
baghdadites
bagvalal
baha'i
baha'is
bai-u
bain-marie
bain-maries
bains-marie
bait-and-switch
bait-and-switched
bait-and-switches
bait-and-switching
bakati
bakati'
bakoko
bakpao-bakpao
bakso-bakso
bakuchiol
bakuchiols
bakwan-bakwan
bald-faced
bald-headed
balkanite
balkanites
ball-and-socket
ball-and-stick
ball-breaker
ball-breakers
ball-flower
ball-flowers
ball-less
ball-peen
ball-pein
balled-and-burlapped
baloxavir
balsalazide
bambala
bambalas
bamileke
bamlanivimab-etesevimab
bamum
band-aid
band-aids
band-saw
band-sawed
band-sawing
band-sawn
band-saws
bandar-log
bandar-logs
bang-bang
bang-up
bank-breaker
bank-breakers
bankings-as-a-service
bankon
banna'i
bannisterite
bannisterites
baotite
baotites
bare-assed
bare-bones
bare-handed
bare-knuckle
bare-knuckled
bare-knuckles
bariba
bariis
barkada
barkadas
barley-bree
barley-brees
barlowite
barlowites
barrel-chested
barrel-fermented
barrel-roll
barrel-rolled
barrel-rolling
barrel-rolls
barrel-vaulted
bas-relief
bas-reliefs
bashi-bazouk
bashi-bazouks
bashkirs
bass-baritone
bass-baritones
bass-relief
bass-reliefs
basso-relievi
basso-relievo
basso-relievos
batroxobin
batteries-as-a-service
battle-ax
battle-axe
battle-axes
battle-scarred
battle-tested
baxdrostat
baybayin
bazedoxifene
bazirite
bazirites
bear-hug
bear-hugged
bear-hugging
bear-hugs
bearsites
beat-'em-up
beat-'em-ups
beat-up
beaten-up
beating-up
beatings-up
beche-de-mer
beches-de-mer
bed-and-breakfast
bed-and-breakfasts
bed-ridden
bed-wetter
bed-wetters
bed-wetting
bed-wettings
bedaquiline
beddy-bye
bee-eater
bee-eaters
bee-line
bee-lined
bee-lines
bee-lining
bee-stung
beef-head
beef-heads
beer-bellied
beetle-browed
beetle-crusher
beetle-crushers
before-after
before-and-after
beg-off
beg-offs
beggar-my-neighbor
beggar-my-neighbour
beggar-thy-neighbours
behind-the-scenes
being-beyond-the-world
being-in-and-for-itself
being-in-the-world-with-others
being-with-one-another
beings-beyond-the-world
beings-for-themselves
beings-in-and-for-themselves
beings-in-the-world-with-others
beings-with-one-another
bekwarra
belatacept
bell-bottom
bell-bottomed
bell-bottoms
bell-less
belle-lettrist
belle-lettrists
belles-lettres
below-the-radar
belumosudil
benazepril
bench-press
bench-pressed
bench-presses
bench-pressing
benoni
benonis
bensulfuron-methyl
bensulfuron-methyls
bentorite
bentorites
bepotastine
bermanite
bermanites
berndtite
berndtites
berrel-vaulted
best-seller
best-sellerdom
best-sellerdoms
best-sellers
best-selling
beta-adrenergic
beta-alanine
beta-alanines
beta-amyloid
beta-amyloids
beta-blocker
beta-blockers
beta-bungarotoxin
beta-bungarotoxins
beta-cyclodextrins
beta-cypermethrins
beta-fructofuranosidase
beta-fructofuranosidases
beta-galactosidase
beta-galactosidases
beta-glucan
beta-glucanase
beta-glucanases
beta-glucans
beta-glucocerebrosidases
beta-glucosidase
beta-glucosidases
beta-glucuronidase
beta-glucuronidases
beta-hexachlorocyclohexane
beta-hexachlorocyclohexanes
beta-hydroxy-beta-methylbutyrate
beta-hydroxy-beta-methylbutyrates
beta-hydroxybutyrate
beta-hydroxybutyrates
beta-lactam
beta-lactamase
beta-lactamases
beta-lactams
beta-lactoglobulin
beta-lactoglobulins
beta-mannosidase
beta-mannosidases
beta-mercaptoethanol
beta-mercaptoethanols
beta-n-acetylglucosaminidase
beta-n-acetylglucosaminidases
beta-n-acetylhexosaminidase
beta-n-acetylhexosaminidases
beta-naphthol
beta-naphthols
beta-phellandrene
beta-phellandrenes
beta-pinene
beta-pinenes
beta-sarcoglycanopathy
beta-sheet
beta-sheets
beta-subunit
beta-subunits
beta-thromboglobulins
beta-thujaplicin
beta-thujaplicins
betrixaban
better-off
bexagliflozin
bhaca
bhacas
bhakti-marga
bhakti-margas
bhujia
bhujias
bi-annual
bi-curiosities
bi-curiosity
bi-curious
bi-gender
bi-gendered
bi-lipschitz
bi-maxwellian
bi-weekly
biafada
bias-variance
bibim-guksu
bible-banging
bible-bashing
bible-thumper
bible-thumpers
bible-thumping
bicaudal-c
bicaudal-cs
bicaudal-d
bicaudal-ds
bid-a-bid
bid-a-bids
biddy-biddies
biddy-biddy
big-boned
big-city
big-endian
big-endianness
big-endiannesses
big-hearted
big-heartedness
big-heartednesses
big-league
big-name
big-screen
big-ticket
big-time
big-timer
big-timers
bigraph
bigraphs
billet-doux
billets-doux
bilo-bilo
bindi-eye
bindi-eyes
binge-eating
binge-eatings
binge-watch
binge-watched
binge-watches
binge-watching
binukid
bio-crude
bio-crudes
bio-leaching
bio-leachings
bio-oil
bio-oils
bio-psycho-social-cultural
biocomputer
biocomputers
biohack
biohacked
biohacks
biometrics-as-a-service
biopsychosocial
biopsychosocially
bioshelter
bioshelters
bipartiteness
bipartitenesses
bird-dog
bird-dogged
bird-dogging
bird-dogs
bird-of-paradise
bird-on-the-wing
bird-watch
bird-watched
bird-watcher
bird-watchers
bird-watches
bird-watching
bird-watchings
bird's-eye
bird's-eyes
bird's-foot
bird's-foots
birds-of-paradise
biscuit-root
biscuit-roots
bislama
bissau-guinean
bissau-guineans
bitch-slap
bitch-slapped
bitch-slapping
bitch-slaps
bite-size
bite-sized
bitter-ender
bitter-enders
black-and-blue
black-and-tan
black-and-white
black-and-whites
black-browed
black-faced
black-fast
black-market
black-marketed
black-marketing
black-markets
black-on-black
black-or-white
black-pill
black-pilled
black-pilling
black-pills
bladder-and-string
blah-blah
blah-blah-blah
blah-blah-blahs
blah-blahs
blankety-blank
blankety-blanks
blast-freeze
blast-freezes
blast-freezing
blast-froze
blast-frozen
bleeding-edge
blind-bake
blind-baked
blind-bakes
blind-baking
blind-loaded
blind-your-eye
blind-your-eyes
bling-bling
bling-blings
block-in-course
blockchain-as-a-service
blockchains-as-a-service
blocks-in-course
blood-and-guts
blood-and-thunder
blood-red
blood-relationship
blood-relationships
blow-by-blow
blow-dried
blow-dries
blow-dry
blow-dryer
blow-dryers
blow-drying
blow-up
blow-ups
blown-in-the-bottle
blown-up
blue-blooded
blue-collar
blue-collared
blue-eye
blue-eyes
blue-grays
blue-greys
blue-hair
blue-hairs
blue-pencil
blue-penciled
blue-penciling
blue-pencilled
blue-pencilling
blue-pencils
blue-ribbon
blue-skied
blue-skies
blue-sky
blue-skyed
blue-skying
blue-water
bo-peep
bo-peeps
board-a-match
board-and-batt
board-and-batten
bobby-sock
bobby-socker
bobby-sockers
bobby-socks
bobby-sox
bobby-soxer
bobby-soxers
boceprevir
bodice-ripper
bodice-rippers
bodice-ripping
body-hugging
body-paint
body-painted
body-painting
body-paints
body-positive
body-shame
body-shamed
body-shamer
body-shamers
body-shames
body-shaming
body-shamings
body-slam
body-slammed
body-slamming
body-slams
bok-bok
bold-faced
bolewa
bolt-on
bonattite
bonattites
bone-chilling
bone-jarring
bone-tired
bone-weary
boo-boo
boo-boos
boo-hoo
boo-hooed
boo-hooing
boo-hoos
booby-trap
booby-trapped
booby-trapping
booby-traps
boogie-woogie
booty-call
booty-called
booty-calling
booty-calls
bopomofo
borhani
born-again
bornemanite
bornemanites
boromuscovite
boromuscovites
bosavi
bosnian-herzegovinian
bosnian-herzegovinians
botlikh
botok-botok
bottle-fed
bottle-fedfirst-feet
bottle-feed
bottle-feeding
bottle-feeds
bottle-o
bottle-os
bottom-dwelling
bottom-feeder
bottom-feeders
bottom-feeding
bottom-line
bottom-liner
bottom-liners
bottom-up
bouyei
bow-legged
bow-tie
bow-ties
bowlo
bowlos
box-thorn
box-thorns
boy-meets-girl
bozeman
brabantite
brabantites
brahmacharya
brahmacharyas
brain-dead
brain-picker
brain-pickers
brain-picking
brain-pickings
brake-by-wire
brand-name
brand-new
brazen-faced
bread-and-butter
break-dance
break-danced
break-dancer
break-dancers
break-dances
break-dancing
break-in
break-ins
break-up
break-ups
breccio-conglomerates
bred-in-the-bone
breech-loader
breech-loaders
breech-loading
breeze-block
breeze-blocks
bretazenil
bri'ish
briartite
briartites
bric-a-brac
brick-and-mortar
bride-to-be
brides-to-be
bright-cut
bright-line
brise-soleil
brise-soleils
bro-country
bro-ey
broad-gauge
broad-gauged
broad-leafed
broad-leaved
broad-minded
broad-mindedly
broad-mindedness
broad-mindednesses
brock-faced
brockle-face
brockle-faced
brockle-faces
broken-down
broken-hearted
broken-heartedly
broken-heartedness
broken-heartednesses
broken-mouthed
broker-dealer
broker-dealers
brother-german
brother-in-arms
brother-in-law
brothers-german
brothers-in-arms
brothers-in-law
brotizolam
brout-englert-higgs
brown-tail
broxyquinoline
brush-off
brush-offs
brush-pen
brush-pens
brush-turkey
brush-turkeys
brush-up
brush-ups
bryostatin
bryostatins
bu-zhong-yi-qi-tang
buang
buberian
bucindolol
budae-jjigae
buddy-buddy
budesonide-formoterol
budesonide-formoterols
budu
budukh
bug-eyed
buh-bye
build-up
build-ups
built-in
built-up
bukar-sadong
bukusu
bul'gogi
bul'gogis
bulb-like
bulevirtide
bull's-eye
bull's-eyes
bumper-to-bumper
bumpety-bump
bumpety-bumps
bunji-bunji
bunji-bunjis
buntil-buntil
buras-buras
burn-the-wind
burn-the-winds
burned-out
burnt-out
buryat
bus-mile
bus-miles
bush-league
bush-tanager
bush-tanagers
business-to-business
business-to-business-to-consumer
business-to-business-to-consumers
business-to-businesses
business-to-consumer
business-to-consumers
business-to-customers
business-to-employees
business-to-government
business-to-governments
busuu
butabarbital
butadiynes
butcher's-broom
butcher's-brooms
butlerite
butlerites
butt-dial
butt-dialed
butt-dialing
butt-dials
butt-fuck
butt-fucked
butt-fucking
butt-fucks
butt-headed
butt-ugly
butter-and-eggs
butynes
buuz
buy-in
buy-ins
buyeo
buzz-cut
buzz-cuts
buzzard-eagle
buzzard-eagles
by-and-by
by-and-bys
by-and-large
by-blow
by-blows
by-by
by-drinking
by-drinkings
by-election
by-elections
by-form
by-forms
by-product
by-products
by-wire
byali
bye-blow
bye-blows
bye-bye
bye-election
bye-elections
bystrite
bystrites
c-akt
c-akts
c-beauty
c-bet
c-bets
c-command
c-commands
c-fos
c-foses
c-glycoside
c-glycosides
c-graph
c-graphs
c-ideal
c-jun
c-juns
c-kit
c-kits
c-list
c-lister
c-listers
c-lists
c-maf
c-mafs
c-mannosylation
c-mannosylations
c-met
c-myc
c-mycs
c-onc
c-oncs
c-optimal
c-optimalities
c-optimality
c-pop
c-pops
c-raf
c-rafs
c-ras
c-rases
c-section
c-sections
c-select
c-selection
c-selections
c-selects
c-sis
c-sises
c-src
c-srcs
c-stoff
c-stoffe
c-terminal
c-terminals
c-termini
c-terminus
c-terminuses
c-walk
c-walking
c-walkings
c-walks
c-yes
c-yeses
c'mon
cable-stayed
cache-sexe
cache-sexes
cachupa
caddos
cadherin
cadherins
cafetites
cage-bird
cage-birds
cakwe-cakwe
calc-schist
calc-schists
calc-sinter
calc-sinters
calc-tufa
calc-tufas
calcareous-argillaceous
calderite
calderites
call-and-response
call-and-responses
call-by-name
call-by-need
call-by-reference
call-by-value
call-in
call-ins
call-out
call-outs
call-up
call-ups
call-with-current-continuation
call-with-current-continuations
calon-segur
calon-segurs
calzirtite
calzirtites
camazepam
can-can
can-cans
can-do
can't
can't-miss
canary-flycatcher
canary-flycatchers
cap'n
cap'ns
cape-pondweed
cape-pondweeds
captologies
captology
capture-the-flag
capture-the-flags
car-mile
car-miles
carbo-load
carbo-loaded
carbo-loading
carbo-loads
carlosturanite
carlosturanites
carmichaelites
carpet-bomb
carpet-bombed
carpet-bombing
carpet-bombs
carrot-and-stick
carve-out
carve-outs
carvel-built
carvones
case-by-case
case-cohort
case-control
case-harden
case-hardened
case-hardening
case-hardens
case-insensitive
case-sensitive
cash-in
cash-ins
cash-out
cash-outs
casirivimab-imdevimab
cast-iron
castle-builder
castle-builders
castle-building
castle-buildings
cat-and-dog
cat-and-mouse
cat-foot
cat-footed
cat-footing
cat-foots
cat-like
cat-sat
cat-sit
cat-sits
cat-sitting
cat's-feet
cat's-foot
catch-as-catch-can
catch-as-catch-cans
catch-up
catch-ups
catechol-o-methyltransferase
catechol-o-methyltransferases
catloaf
cattierite
cattierites
catty-corner
catty-cornered
cause-and-effect
cave-in
cave-ins
cavitand
cavitands
cease-fire
cease-fires
cebuano
cefoperazone-sulbactam
ceftazidime-avibactam
ceftazidime-avibactams
ceftolozane-tazobactam
ceftolozane-tazobactams
cell-mediated
cello-oligosaccharide
cello-oligosaccharides
center-fire
center-fires
cesanite
cesanites
ch'i
ch'i-p'ao
ch'i-p'aos
ch'is
ch'orti
ch'orti'
cha-cha
cha-cha-cha
cha-cha-chas
cha-chas
chabad-lubavitch
chac-mool
chac-mools
chaihu-shugan-san
chain-smoke
chain-smoked
chain-smoker
chain-smokers
chain-smokes
chain-smoking
chajchas
chakana
chakanas
chakapuli
chakhokhbili
char-grill
char-grilled
char-grilling
char-grills
chashu
chashus
chashushuli
chassagne-montrachet
chassagne-montrachets
chat-tyrant
chat-tyrants
chateauneuf-du-pape
chateauneuf-du-papes
chebakia
chebakias
check-in
check-ins
check-up
check-ups
chee-chee
cheese-head
cheese-headed
cheese-heads
chef-d'oeuvre
chefs-d'oeuvre
chemo-attractant
chemo-attractants
chenite
chenites
cherry-pick
cherry-picked
cherry-picking
cherry-picks
chest-beating
chest-beatings
chest-thumping
chest-thumpings
chesterite
chesterites
cheval-de-frise
chevaux-de-frise
chhattisgarhi
chhi-chhi
chi-chi
chi-chis
chi-rho
chi-rhos
chi-square
chi-squared
chi-squares
chicken-and-egg
child-centeredness
child-centerednesses
child-centredness
child-centrednesses
child-in-law
child-rearing
child-rearings
children-in-law
chin-up
chin-ups
chin-wag
chin-wagged
chin-wagging
chin-wags
chip-in
chip-ins
chiquitano
chit-chat
chit-chats
chit-chatted
chit-chatting
chito-oligosaccharide
chito-oligosaccharides
chitter-chatter
chitter-chatters
chocolate-coloured
cholecystokinin-pancreozymin
cholecystokinin-pancreozymins
chorea-acanthocytoses
chorea-acanthocytosis
choreographer-in-residence
choreographers-in-residence
chrome-spinel
chrome-spinels
chru
chuch'e
chuch'es
chuck-will's-widow
chuck-will's-widows
chuj
chulym
chute-the-chute
chute-the-chutes
ci-devant
ciclopirox
cinaciguat
cinanserin
cinobufagin
cinobufagins
cinobufotalin
cinobufotalins
cinoxacin
cinq-cents
cirro-cumuli
cirro-cumulus
cirro-strati
cirro-stratus
cis-dichlorodiammineplatinum
cis-gender
cis-gendered
cis-het
cis-heteronormativities
cis-heteronormativity
cis-hets
cis-nerolidol
cis-nerolidols
cis-platinum
cis-platinums
cis-prenyltransferase
cis-prenyltransferases
cis-trans
cisplatin-pemetrexed
citicoline
city-state
city-states
civic-minded
civic-mindedness
civic-mindednesses
cladribine
clairites
clapped-out
clasp-knife
clasp-knives
claudin
claudins
clean-cut
clean-shaven
clean-up
clean-ups
clear-cut
clear-cuts
clear-cutting
clear-cuttings
clear-fell
clear-felled
clear-felling
clear-fells
clear-headed
clear-headedly
clear-headedness
clear-headednesses
clear-sighted
clear-sightedly
clear-sightedness
clear-sightednesses
clear-up
clerite
clerites
cli-fi
cli-fis
click-clack
click-clacked
click-clacking
click-clacks
click-to-call
click-to-calls
click-to-dial
click-to-talk
clickety-clack
clickety-clacked
clickety-clacking
clickety-clacks
client-side
client-sides
cliff-hang
cliff-hanger
cliff-hangers
cliff-hanging
cliff-hangs
cliff-hung
climate-controlled
clinician-researcher
clinician-researchers
clinician-scientist
clinician-scientists
clinico-morphological
clip-clop
clip-clopped
clip-clopping
clip-clops
clip-fed
clip-on
clip-ons
cloak-and-dagger
clodinafop-propargyl
clodinafop-propargyls
clomifene
clop-clop
clop-clopped
clop-clopping
clop-clops
clopen
clorgiline
close-fitting
close-in
close-knit
close-lipped
close-minded
close-quarter
close-quartered
close-up
close-ups
closed-captioned
closed-captioning
closed-captionings
closed-circuit
closed-door
closed-minded
closer-knit
closest-knit
clotiazepam
cloud-cuckoo-land
cloud-cuckoo-lands
cloud-kissing
cloxazolam
cloxyquins
club-rush
club-rushes
clued-up
cluj-napoca
co-administer
co-administered
co-administering
co-administers
co-administration
co-administrations
co-adoption
co-anchor
co-anchored
co-anchoring
co-anchors
co-author
co-authored
co-authoring
co-authors
co-authorship
co-authorships
co-brand
co-branded
co-branding
co-brands
co-captain
co-captained
co-captaining
co-captains
co-chair
co-chaired
co-chairing
co-chairpeople
co-chairs
co-champion
co-champions
co-chromatographed
co-conspirator
co-conspirators
co-counsel
co-counsels
co-create
co-created
co-creates
co-creating
co-creator
co-creators
co-crystallization
co-crystallizations
co-crystallize
co-crystallized
co-crystallizing
co-defendant
co-defendants
co-dependence
co-dependency
co-dependent
co-design
co-designed
co-designer
co-designers
co-designing
co-designs
co-develop
co-developed
co-developer
co-developers
co-developing
co-develops
co-discover
co-discovered
co-discoverer
co-discoverers
co-discovering
co-discovers
co-drive
co-driven
co-driver
co-drivers
co-drives
co-driving
co-drove
co-ed
co-edit
co-edited
co-editing
co-edition
co-editions
co-editor
co-editors
co-edits
co-eds
co-executor
co-executors
co-exist
co-existed
co-existence
co-existences
co-existing
co-exists
co-factor
co-factors
co-favorite
co-favorites
co-favourite
co-favourites
co-feature
co-featured
co-features
co-featuring
co-finance
co-financed
co-finances
co-financing
co-found
co-founded
co-founder
co-founders
co-founding
co-founds
co-head
co-headed
co-heading
co-heads
co-heir
co-heiress
co-heiresses
co-heirs
co-host
co-hostess
co-hostesses
co-hosts
co-immobilisation
co-immobilisations
co-immobilization
co-immobilizations
co-immunoprecipitated
co-immunoprecipitates
co-immunoprecipitating
co-immunoprecipitation
co-immunoprecipitations
co-invent
co-invented
co-inventing
co-inventor
co-inventors
co-invents
co-invest
co-invested
co-investing
co-investor
co-investors
co-invests
co-lead
co-leader
co-leaders
co-leading
co-leads
co-led
co-manage
co-managed
co-management
co-managements
co-manager
co-managers
co-manages
co-managing
co-market
co-marketed
co-marketing
co-markets
co-occur
co-occurred
co-occurrence
co-occurrences
co-occurrent
co-occurring
co-occurs
co-op
co-ops
co-opt
co-opted
co-opting
co-opts
co-ordinate
co-ordinated
co-ordinates
co-ordinating
co-ordination
co-ordinations
co-ordinator
co-ordinators
co-own
co-owned
co-owner
co-owners
co-ownership
co-ownerships
co-owning
co-owns
co-parent
co-parents
co-partner
co-partners
co-pilot
co-precipitate
co-precipitated
co-precipitates
co-precipitating
co-precipitation
co-precipitations
co-president
co-presidents
co-prime
co-produce
co-produced
co-producer
co-producers
co-produces
co-producing
co-product
co-production
co-productions
co-products
co-publish
co-published
co-publisher
co-publishers
co-publishes
co-publishing
co-recipient
co-recipients
co-religionist
co-religionists
co-representative
co-representatives
co-repressor
co-repressors
co-respondent
co-respondents
co-responsibilities
co-responsibility
co-responsible
co-ruler
co-rulers
co-sponsor
co-sponsored
co-sponsoring
co-sponsors
co-sponsorship
co-sponsorships
co-star
co-starred
co-starring
co-stars
co-tenant
co-tenants
co-trimoxazole
co-vertex
co-vertexes
co-vertices
co-winner
co-winners
co-worker
co-workers
co-working
co-workings
co-write
co-writer
co-writers
co-writes
co-writing
co-written
co-wrote
coarse-grained
coast-to-coast
cobaltomenite
cobaltomenites
coca-colonisation
coca-colonisations
coca-colonization
coca-colonizations
cock-a-doodle-doo
cock-a-doodle-dooed
cock-a-doodle-dooing
cock-a-doodle-doos
cock-a-leekie
cock-a-leekies
cock-block
cock-blocked
cock-blocker
cock-blockers
cock-blocking
cock-blocks
cock-of-the-rock
cock-up
code-name
code-named
code-names
code-naming
code-switching
code-switchings
coffee-coloured
coffee-klatsch
coffee-klatschen
coffee-klatsches
cognition-as-a-service
cognitions-as-a-service
cohen-macaulay
cohen-macaulayness
cohen-macaulaynesses
coin-op
coin-ops
coked-up
cold-blooded
cold-bloodedly
cold-bloodedness
cold-bloodednesses
cold-call
cold-called
cold-calling
cold-calls
cold-cut
cold-eyed
cold-hearted
cold-heartedly
cold-heartedness
cold-heartednesses
cold-press
cold-pressed
cold-presses
cold-pressing
cold-shoulder
cold-shouldered
cold-shouldering
cold-shoulders
cold-smoke
cold-smoked
cold-smokes
cold-smoking
cold-turkey
cold-turkeyed
cold-turkeying
cold-turkeys
cold-water
colesevelam
collagen-glycosaminoglycan
colonel-in-chief
colonel-in-chiefs
colonels-in-chief
column-major
column-wise
comb-over
comb-overs
come-all-ye
come-all-ye's
come-all-yes
come-all-you
come-all-you's
come-all-yous
come-along
come-alongs
come-and-cuddle-me
come-and-cuddle-mes
come-hither
come-hithers
come-on
come-ons
come-outer
come-outers
comedie-ballet
comedie-ballets
comedies-ballets
coming-of-age
coming-out
coming-outs
coming-to-be
comings-of-age
comings-to-be
commanders-in-chief
con-non-con
con-non-cons
concavo-convex
cone-cut
cone-like
connect-the-dot
connect-the-dots
connectivities-as-a-service
connectivity-as-a-service
conotoxin
conotoxins
consciousness-raising
consciousness-raisings
container-as-a-service
containers-as-a-service
conyo
conyos
cook-off
cook-offs
cool-off
cool-offs
cooling-off
cop-out
cop-outs
cord-cutter
cord-cutters
cord-cutting
cord-cuttings
cordon-bleu
cordon-bleus
corporate-wide
cortico-subcortical
corynanthine
corynanthines
cost-effective
cost-effectively
cost-effectiveness
cost-effectivenesses
cotton-picking
couch-surf
couch-surfed
couch-surfer
couch-surfers
couch-surfing
couch-surfings
couch-surfs
could've
couldn't
couldn't-care-less
couldn't've
council-general
councils-general
counselor-at-law
counselor-in-training
counselors-at-law
counselors-in-training
counter-accusation
counter-accusations
counter-adaptation
counter-adaptations
counter-adaptive
counter-advertising
counter-advertisings
counter-affidavit
counter-affidavits
counter-agent
counter-agents
counter-aggression
counter-aggressions
counter-argue
counter-argued
counter-argues
counter-arguing
counter-argument
counter-arguments
counter-assault
counter-assaults
counter-attack
counter-attacked
counter-attacker
counter-attackers
counter-attacking
counter-attacks
counter-bid
counter-bidding
counter-bids
counter-blast
court-martial
court-martialed
court-martialing
court-martialled
court-martialling
court-martials
cousin-german
cousin-germans
cousin-in-law
cousins-german
cousins-in-law
cover-all
cover-alls
cover-up
cover-ups
cow-heifer
cow-heifers
cowl-neck
cowl-necks
crab-plover
crab-plovers
crack-up
crack-ups
cracker-barrel
crash-land
crash-landed
crash-landing
crash-lands
crazy-quilt
cream-faced
creepy-crawlies
creepy-crawly
crohn's
crop-dusting
crop-dustings
croque-madame
croque-madames
croque-monsieur
croque-monsieurs
cross-back
cross-backs
cross-chain
cross-chained
cross-chaining
cross-chains
cross-channel
cross-check
cross-checked
cross-checking
cross-checks
cross-claim
cross-claims
cross-collateralisation
cross-collateralisations
cross-collateralization
cross-collateralizations
cross-compatibilities
cross-compatibility
cross-compatible
cross-compilation
cross-compilations
cross-complaint
cross-complaints
cross-compound
cross-contact
cross-contacts
cross-contaminate
cross-contaminated
cross-contaminates
cross-contaminating
cross-contamination
cross-contaminations
cross-countries
cross-country
cross-cousin
cross-cousins
cross-cultural
cross-culturally
cross-current
cross-currents
cross-curricular
cross-date
cross-dated
cross-dates
cross-dating
cross-datings
cross-desensitisation
cross-desensitisations
cross-desensitization
cross-desensitizations
cross-disciplinary
cross-docking
cross-dockings
cross-dress
cross-dressed
cross-dresser
cross-dressers
cross-dresses
cross-dressing
cross-dressings
cross-examination
cross-examinations
cross-examine
cross-examined
cross-examiner
cross-examiners
cross-examines
cross-examining
cross-eye
cross-eyed
cross-eyes
cross-fade
cross-faded
cross-fading
cross-fadings
cross-fed
cross-feed
cross-feeding
cross-feeds
cross-fertile
cross-fertilisation
cross-fertilisations
cross-fertilise
cross-fertilised
cross-fertilises
cross-fertilising
crovalimab
crow's-feet
crow's-foot
crowd-kill
crowd-killed
crowd-kills
crowd-pleaser
crowd-pleasers
crowd-surf
crowd-surfed
crowd-surfer
crowd-surfers
crowd-surfing
crowd-surfings
crowd-surfs
crown-of-the-field
crush-out
crush-outs
crush-room
crush-rooms
crypto-christianities
crypto-christianity
crypto-fascism
crypto-fascisms
crypto-fascist
crypto-fascists
crypto-jew
crypto-jewish
crypto-jews
crypto-judaism
crypto-judaisms
cubo-futurism
cubo-futurisms
cubo-octahedra
cubo-octahedron
cubo-octahedrons
cuckoo-pint
cuckoo-pints
cuckoo-shrike
cuckoo-shrikes
cucurbituril
cucurbiturils
cul-de-sac
cul-de-sacs
culasses
culatelli
culs-de-lampe
culs-de-sac
cum-ex
curator-in-residence
curators-in-residence
cure-all
cure-alls
curetonites
cusk-eel
cusk-eels
custom-make
custom-makes
custom-making
custom-tailor
custom-tailored
custom-tailoring
custom-tailors
cut-and-dried
cut-and-dry
cut-and-try
cut-in
cut-ins
cut-throat
cut-throats
cutting-edge
cuyonon
cybercrime-as-a-service
cybercrimes-as-a-service
cybersecurities-as-a-service
cybersecurity-as-a-service
cyclo-cross
cyhalofop-butyl
cyhalofop-butyls
cylindro-conical
cyrilovite
cyrilovites
cyromazine
d-ala-d-ala
d-ala-d-alas
d-ala-d-lac
d-ala-d-lacs
d-alanyl-d-alanine
d-alanyl-d-alanines
d-algebra
d-algebraic
d-algebras
d-alloisoleucine
d-alloisoleucines
d-allose
d-alloses
d-amphetamine
d-apiose
d-apioses
d-arabinose
d-arabinoses
d-arabitol
d-arabitols
d-asparagine
d-asparagines
d-bag
d-bags
d-beat
d-brane
d-branes
d-carvone
d-carvones
d-chloroform
d-chloroforms
d-configuration
d-configurations
d-cysteine
d-cysteines
d-day
d-days
d-efficiencies
d-efficiency
d-enantiomer
d-enantiomers
d-error
d-errors
d-fructose
d-fructoses
d-fucose
d-fucoses
d-galactosamine
d-galactosamines
d-galactose
d-galactoses
d-glucitols
d-glucosamine
d-glucuronolactone
d-glucuronolactones
d-glyceraldehyde
d-glyceraldehydes
d-graph
d-graphs
d-ideal
d-idose
d-idoses
d-isomer
d-isomers
d-leucine
d-leucines
d-list
d-lister
d-listers
d-lists
d-lyxose
d-lyxoses
d-mark
d-marks
d-optimal
d-optimalities
d-optimality
d-orbital
d-orbitals
d-pad
d-pads
d-panthenol
d-panthenols
d-phenylalanine
d-phenylalanines
d-phenylglycine
d-phenylglycines
d-proline
d-ribulose
d-ribuloses
d-serine
d-serines
d-sorbitol
d-sorbitols
d-threitol
d-threitols
d-trehalose
d-trehaloses
d-tryptophan
d-tyrosine
d-tyrosines
d-xylose
d-xyloses
d'ansite
d'ansites
d'oh
d'ye
d'you
daasanach
dabigatran
dabrafenib-trametinib
daclatasvir
daemonological
daemonologies
daemonologist
daemonologists
daevas
daisy-chain
daisy-chained
daisy-chaining
daisy-chains
daisy-like
dak-bokkeum-tang
dalotuzumab
dance-off
dance-offs
dance-punk
dance-walk
dance-walks
dane-zaa
danofloxacin
dapple-gray
dappled-gray
daratumumab-lenalidomide-dexamethasone
darshanas
dashboard-as-a-service
dashboards-as-a-service
dastar
dastars
database-as-a-service
databases-as-a-service
date-rape
date-raped
date-rapes
date-raping
daughter-in-law
daughters-in-law
davul
davuls
day-care
day-cares
day-hike
day-hiked
day-hiker
day-hikers
day-hikes
day-hiking
day-hikings
day-to-day
day-to-days
day-trade
day-traded
day-trader
day-traders
day-trades
day-trading
dazaga
de-air
de-aired
de-airing
de-airs
de-alcoholisation
de-alcoholisations
de-alcoholised
de-alcoholization
de-alcoholizations
de-alcoholized
de-anonymisation
de-anonymisations
de-anonymise
de-anonymised
de-anonymising
de-anonymization
de-anonymizations
de-anonymize
de-anonymized
de-anonymizing
de-ba'athification
de-ba'athifications
de-baathification
de-baathifications
de-commoditisation
de-commoditisations
de-commoditise
de-commoditised
de-commoditises
de-commoditising
de-commoditization
de-commoditizations
de-commoditize
de-commoditized
de-commoditizes
de-commoditizing
de-compartmentalisation
de-compartmentalisations
de-compartmentalise
de-compartmentalised
de-compartmentalises
de-compartmentalising
de-compartmentalization
de-compartmentalizations
de-compartmentalize
de-compartmentalized
de-compartmentalizes
de-compartmentalizing
de-cross-linking
de-cross-linkings
de-crosslinking
de-crosslinkings
de-emphases
de-emphasis
de-emphasise
de-emphasised
de-emphasises
de-emphasising
de-emphasize
de-emphasized
de-emphasizes
de-emphasizing
de-endothelialisation
de-endothelialisations
de-endothelialization
de-endothelializations
de-energise
de-energised
de-energises
de-energising
de-energize
de-energized
de-energizes
de-energizing
de-epithelialisations
de-epithelializations
de-escalate
de-escalated
de-escalates
de-escalating
de-escalation
de-escalations
de-escalator
de-escalators
de-escalatory
de-esterification
de-esterifications
de-identification
de-identifications
de-industrialisations
de-industrialise
de-industrialised
de-industrialises
de-industrialising
de-industrializations
de-industrialize
de-industrialized
de-industrializes
de-industrializing
de-institutionalisation
de-institutionalisations
de-institutionalization
de-institutionalizations
de-internationalisation
de-internationalisations
de-internationalization
de-internationalizations
de-judaisation
de-judaisations
de-judaization
de-judaizations
de-leaf
de-leafed
de-leafing
de-leafs
de-mine
de-mined
de-mines
de-mining
de-minings
de-russification
de-russifications
de-skill
de-skilled
de-skilling
de-skills
de-stalinisation
de-stalinisations
de-stalinised
de-stalinising
de-stalinization
de-stalinizations
de-stalinized
de-stalinizing
de-stress
de-stressed
de-stresses
de-stressing
de-sumoylation
de-sumoylations
deacetylase
deacetylases
dead-alive
dead-and-alive
dead-drunk
dead-drunkenness
dead-drunkennesses
dead-end
dead-ended
dead-ending
dead-ends
dead-man's-fingers
dead-men's-fingers
dead-name
dead-named
dead-names
dead-naming
dead-on
deaf-aid
deaf-aids
deaf-mute
deaf-mutes
deal-breaker
deal-breakers
deanonymisation
deanonymisations
deanonymise
deanonymised
deanonymising
deanonymization
deanonymizations
deanonymize
deanonymized
deanonymizing
death-defying
death-of-man
death-of-men
death's-head
death's-heads
deaths-of-man
deauthenticate
deauthentication
deauthentications
deauthorization
deauthorizations
deauthorize
deauthorized
deauthorizing
decade-long
decades-long
deep-cut
deep-discount
deep-dish
deep-dyed
deep-freeze
deep-freezes
deep-freezing
deep-fried
deep-fries
deep-froze
deep-frozen
deep-fry
deep-fryer
deep-fryers
deep-frying
deep-pocketed
deep-rooted
deep-rootedness
deep-rootednesses
deep-sea
deep-seated
deep-six
deep-sixed
deep-sixes
deep-sixing
deep-sky
deep-throating
deep-throatings
deep-voiced
deer-horn
deer-horns
deerite
deerites
defactinib
dehooker
dehookers
dei-naoero
deidentification
deidentifications
deidentified
deidentify
dek
deks
delorazepam
delta-sarcoglycanopathy
delta-v
delta-vs
demethylwedelolactone
demethylwedelolactones
demi-caractere
demi-glace
demi-glaces
demi-god
demi-gods
demi-monde
demi-mondes
demi-pension
demi-pensions
demi-sec
demi-vierge
demi-vierges
demo'd
demo'ing
democratic-republican
democratic-republicans
dena'ina
denatonium
denje'c'jute
denje'c'jutes
densenet
densenets
deobfuscate
deobfuscates
deobfuscating
deobfuscation
deobfuscations
deobfuscator
deobfuscators
derring-do
derring-dos
des-gamma-carboxyprothrombin
des-gamma-carboxyprothrombins
designer-developer
designer-developers
designer-in-residence
designers-in-residence
desktops-as-a-service
desmoglein
desmogleins
detail-orientedness
detail-orientednesses
deubiquitinase
deubiquitinases
deubiquitinate
deubiquitinated
deubiquitinates
deubiquitinating
deurbanisation
deurbanisations
deurbanization
deurbanizations
devekut
devil-may-care
devops-as-a-service
dew-cup
dew-cups
dew-drink
dew-drinks
dewindtite
dewindtites
dextrosursumversions
dhokla
dhoklas
dholuo
dhu'l-hijja
dhu'l-hijjah
dhuwal
di-n-acetylchitobiose
di-n-acetylchitobioses
di-n-butylamine
di-n-butylamines
di-n-propylamine
di-n-propylamines
di-ubiquitin
di-ubiquitins
diablos
dial-up
dial-ups
dibromobenzenes
dibutylnitrosamine
dibutylnitrosamines
dichloro-diphenyl-trichloroethane
dichloro-diphenyl-trichloroethanes
dichlorprop-p
dichlorprop-ps
dick-waving
diclazepam
diclofop-methyl
diclofop-methyls
didanosine
diddle-daddle
diddle-daddled
diddle-daddles
diddle-daddling
diddly-squat
diddly-squats
didemnin
didemnins
didn't
didot
didots
die-cast
die-casted
die-casting
die-casts
die-cut
die-cuts
die-cutting
die-forge
die-forged
die-forges
die-forging
die-hard
die-hardism
die-hardisms
die-in
die-ins
die-off
die-offs
diers
diethylnitrosamine
diethylnitrosamines
difference-in-difference
difference-in-differences
digalactosyldiacylglycerol
digalactosyldiacylglycerols
dihydroartemisinin-piperaquine
dihydroartemisinin-piperaquines
diimidazole
diimide
diimides
dijon
dik-dik
dik-diks
dilly-dallied
dilly-dallies
dilly-dally
dilly-dallying
diloxanide
dim-sighted
dim-witted
dim-wittedness
dim-wittednesses
dimethenamid-p
dimethenamid-ps
dine-in
dine-out
diner-out
diners-out
ding-dong
ding-donged
ding-donging
ding-dongs
dioleoyl
dioleoyls
diosmectite
diosmectites
dioula
dipivefrin
dipole-dipole
direct-acting
direct-fire
direct-fired
direct-fires
direct-firing
direct-to-consumer
direct-to-consumers
direct-to-product
direct-to-video
director-in-residence
directors-in-residence
dithiothreitol
dithiothreitols
dityrosine
dityrosines
dive-bomb
dive-bombed
dive-bombing
dive-bombs
dizin
dizinc
djugun
dluwang
do-all
do-good
do-gooder
do-gooders
do-gooding
do-goodings
do-goodism
do-goodisms
do-goods
do-it-yourself
do-it-yourselfer
do-it-yourselfers
do-nothing
do-nothingism
do-nothingisms
do-nothings
do-or-die
do-over
do-overs
do-rag
do-rags
do-re-mi
do-re-mis
do-si-do
do-si-doed
do-si-doing
do-si-dos
do'a
do'as
docetaxel-gemcitabine
docetaxel-prednisone
docetaxel-trastuzumab
dodecamethylcyclohexasiloxane
dodecamethylcyclohexasiloxanes
dodecanol
dodecanols
doenjang-guk
doenjang-jjigae
doesn't
dog-cheap
dog-ear
dog-eared
dog-earing
dog-ears
dog-friendliness
dog-friendlinesses
dog-pile
dog-piled
dog-piles
dog-piling
dog-proof
dog-proofed
dog-proofing
dog-proofings
dog-proofs
dog-speak
dog-speaks
dog-stopper
dog-stoppers
dog-tired
dog's-tail
dog's-tails
don't
don't-know
don't-knows
don'ts
doo-doo
doo-doos
doo-hickey
doo-hickeys
doo-wop
doo-wops
door-to-door
doramectin
doripenem
dorrite
dorrites
dostoyevskian
dot-com
dot-coms
dot-to-dot
dot-to-dots
double-acting
double-action
double-banked
double-barrel
double-barreled
double-barrelled
double-blind
double-bogey
double-bogeyed
double-bogeying
double-bogeys
double-book
double-booked
double-booking
double-books
double-breasted
double-check
double-checked
double-checking
double-checks
double-click
double-clicked
double-clicking
double-clicks
double-cross
double-crossed
double-crosser
double-crossers
double-crosses
double-crossing
double-date
double-dated
double-dates
double-dating
double-deal
double-dealer
double-dealers
double-dealing
double-dealings
double-deals
double-dealt
double-deck
double-decked
double-decker
double-deckers
double-digit
double-dip
double-dipped
double-dipper
double-dippers
double-dipping
double-dips
double-double
double-doubles
double-edged
double-ended
double-face
double-faced
double-facedly
double-glazed
double-head
double-headed
double-heading
double-heads
double-helical
double-jointed
double-jointedness
double-jointednesses
double-minded
double-o
double-os
double-park
double-parked
double-parking
double-parkings
double-parks
double-pitch
double-print
double-printed
double-printing
double-prints
double-seater
double-seaters
double-sided
double-space
double-spaced
double-spaces
double-spacing
double-starred
double-stop
double-stopped
double-stopping
double-stops
double-talk
double-talked
double-talker
double-talkers
dough-faced
dove-eyed
down-and-out
down-and-outer
down-and-outers
down-and-outs
down-at-heel
down-at-the-heel
down-ballot
down-bow
down-bows
down-faced
down-home
down-low
down-lows
down-market
down-projection
down-projections
down-tempo
down-tempos
down-to-earth
down-to-earthness
down-to-earthnesses
down-valley
doyayo
drag-and-drop
drag-queen
drag-queens
dravyas
dress-up
dress-ups
dressing-down
dressing-downs
dried-up
drill-like
drink-driver
drink-drivers
drink-driving
drink-drivings
drip-dried
drip-dries
drip-dry
drip-drying
drive-by
drive-by-wire
drive-bys
drive-in
drive-ins
drive-through
drive-throughs
drive-thru
drive-thrus
drongo-cuckoo
drongo-cuckoos
drop-dead
drop-down
drop-downs
drop-forge
drop-forged
drop-forges
drop-forging
drop-in
drop-ins
drop-kick
drop-kicked
drop-kicking
drop-kicks
drop-off
drop-offs
drop-ship
drop-shipped
drop-shipping
drop-shippings
drop-ships
dropwing
dropwings
druzes
dry-ash
dry-clean
dry-cleanable
dry-cleaned
dry-cleaning
dry-cleans
dry-cure
dry-cured
dry-cures
dry-curing
dry-eyed
dry-handed
dry-hump
dry-humped
dry-humping
dry-humps
dry-nurse
dry-nursed
dry-nurses
dry-nursing
dry-press
dry-pressed
dry-presses
dry-pressing
dry-rot
dry-rots
dry-rotted
dry-rotting
dry-salt
dry-salted
dry-salting
dry-salts
dry-tooling
dry-toolings
dry-waxed
du-rag
du-rags
du'ah
du'ahs
dual-earner
dual-purpose
dubujjigae
duct-tape
duct-taped
duct-tapes
duct-taping
dufrenites
dull-normal
dull-normals
dull-witted
dull-wittedness
dull-wittednesses
dum-dum
dum-dums
dumb-ass
dumb-asses
dumb-dumb
dumb-dumbs
dumber-ass
dumbest-ass
dumbfuck
dumbfucks
dust-up
dutchman's-breeches
duty-bound
duwal
duwendes
dyan
dyed-in-the-wool
dynemicin
dynemicins
dyno'd
dyschondroplasia
dyschondroplasias
dysgammaglobulinemia
dysraphism
dysraphisms
dysregulate
dysregulates
dysregulating
dysregulation
dysregulations
dzala
e-activism
e-activisms
e-address
e-addresses
e-advocacies
e-advocacy
e-alert
e-alerts
e-archive
e-archives
e-assessment
e-assessments
e-auction
e-auctions
e-ballot
e-ballots
e-bank
e-banking
e-bankings
e-banks
e-begging
e-beggings
e-bicycle
e-bicycles
e-bidding
e-biddings
e-bike
e-biked
e-bikes
e-biking
e-bikings
e-bill
e-billing
e-billings
e-bills
e-blast
e-blasts
e-boat
e-boats
e-book
e-books
e-box
e-boxes
e-boy
e-boys
e-brochure
e-brochures
e-bullying
e-bullyings
e-business
e-businesses
e-car
e-card
e-cards
e-cars
e-cash
e-cashes
e-catalog
e-catalogs
e-catalogue
e-catalogues
e-check
e-checks
e-cheque
e-cheques
e-cig
e-cigarette
e-cigarettes
e-cigs
e-collection
e-collections
e-commerce
e-commerces
e-commercial
e-communication
e-communications
e-confidence
e-confidences
e-consent
e-consents
e-consult
e-consults
e-content
e-contents
e-contract
e-contracts
e-counseling
e-counselings
e-counselling
e-counsellings
e-couple
e-coupon
e-coupons
e-crime
e-crimes
e-criminal
e-criminals
e-currencies
e-currency
e-date
e-dated
e-dater
e-daters
e-dates
e-dating
e-datings
e-democracies
e-democracy
e-discoveries
e-discovery
e-document
e-documentation
e-documentations
e-documents
e-edition
e-editions
e-friend
e-friends
e-fu
e-fuel
e-fuels
e-girl
e-girls
e-gov
e-government
e-governments
e-govs
e-graph
e-graphs
e-health
e-healths
e-hon
e-hookah
e-hookahs
e-ideal
e-ideals
e-infrastructure
e-infrastructures
e-juice
e-juices
e-kid
e-kids
e-kitten
e-kittens
e-learner
e-learners
e-learning
e-learnings
e-liquid
e-liquids
e-mail
e-mailed
e-mailer
e-mailers
e-mailing
e-mails
e-marketing
e-marketings
e-marketplace
e-marketplaces
e-methanol
e-methanols
e-money
e-moneys
e-monies
e-newsletter
e-newsletters
e-newspaper
e-newspapers
e-optimal
e-optimalities
e-optimality
e-pal
e-pals
e-paper
e-papers
e-participation
e-participations
e-politics
e-portfolio
e-portfolios
e-process
e-processes
e-procurement
e-procurements
e-publisher
e-publishers
e-publishing
e-publishings
e-reader
e-readers
e-rehabilitation
e-rehabilitations
e-resume
e-resumes
e-safety
e-scooter
e-scooters
e-securities
e-security
e-selectin
e-selectins
e-seller
e-sellers
e-service
e-services
e-servqual
e-servquals
e-sex
e-sexes
e-shop
e-shops
e-signature
e-signatures
e-simulation
e-simulations
e-sport
e-sports
e-stim
e-stims
e-substitution
e-substitutions
e-tail
e-tailer
e-tailers
e-tailing
e-tailings
e-tails
e-text
e-textbook
e-textbooks
e-textile
e-textiles
e-texts
e-ticket
e-tickets
e-vite
e-vites
e-vote
e-votes
e-voting
e-votings
e-zine
e-zines
e'en
e'er
eagle-eyed
eagle-hawk
eagle-hawks
ear-piercing
ear-piercingly
ear-piercings
ear-shattering
ear-tag
ear-tagged
ear-tagging
ear-tags
earth-shattering
earth-shatteringly
earth-sheltered
east-northeast
east-northeasts
east-southeast
east-southeasts
east-west
easy-going
easy-peasy
eau-de-vie
eaux-de-vie
ebb-tide
ebb-tides
echinocandin
echinocandins
eco-anxieties
eco-anxiety
eco-fascism
eco-fascisms
eco-feminism
eco-feminisms
eco-feminist
eco-feminists
eco-friendlier
eco-friendliest
eco-friendliness
eco-friendlinesses
eco-horror
eco-horrors
eco-hotel
eco-hotels
eco-innovation
eco-innovations
eco-lodge
eco-lodges
eco-modernism
eco-modernisms
eco-modernist
eco-modernists
eco-resort
eco-resorts
eco-socialism
eco-socialisms
eco-socialist
eco-socialists
eco-volunteering
eco-volunteerings
edelfosine
edelfosines
editor-in-chief
editor-in-chiefs
edrophonium
educator-in-residence
educators-in-residence
eensie-weensie
eensy-weensy
eezgii
effenbergerites
efficiencies-as-a-service
efficiency-as-a-service
efgartigimod
egg-eater
egg-eaters
egg-in-a-hole
egg-in-a-holes
ego-dystonic
ego-identities
ego-identity
ego-trip
ego-tripped
ego-tripper
ego-trippers
ego-tripping
ego-trips
egodystonic
eid-al-adha
eid-al-fitr
eid-ul-adha
eid-ul-fitr
eight-gauge
eight-square
eight-thousanders
eighteen-wheeler
eighteen-wheelers
eighty-eight
eighty-eighth
eighty-eighths
eighty-eights
eighty-fifth
eighty-fifths
eighty-first
eighty-firsts
eighty-five
eighty-fives
eighty-four
eighty-fours
eighty-fourth
eighty-fourths
eighty-nine
eighty-nines
eighty-ninth
eighty-ninths
eighty-one
eighty-ones
eighty-second
eighty-seconds
eighty-seven
eighty-sevens
eighty-seventh
eighty-sevenths
eighty-six
eighty-sixed
eighty-sixes
eighty-sixing
eighty-sixth
eighty-sixths
eighty-third
eighty-thirds
eighty-three
eighty-threes
eighty-two
eighty-twos
either-or
either-ors
ejagham
ejaghams
ekajuk
ekari
ekois
elacestrant
elafibranor
elamipretide
eletriptan
ellenbergerite
ellenbergerites
ellipticine
ellipticines
elo
elvitegravir
emakhuwa
embo
emedastine
emilites
empty-chair
empty-chaired
empty-chairing
empty-chairs
empty-handed
empty-handedness
empty-handednesses
empty-headed
empty-headedness
empty-headednesses
empty-hearted
emu-wren
emu-wrens
encebollado
encephalomyeloradiculopathies
encorafenib-binimetinib
end-all
end-alls
end-blown
end-dump
end-match
end-matched
end-matches
end-matching
end-member
end-members
end-ran
end-run
end-running
end-runs
end-stage
end-stopped
end-to-end
endo-beta-n-acetylglucosaminidase
endo-beta-n-acetylglucosaminidases
energies-as-a-service
engineer-in-chief
engineer-in-training
engineers-in-chief
engineers-in-training
englishites
enone
enones
enoughness
enoughnesses
ensemble-in-residence
ensembles-in-residence
ensitrelvir
entr'actes
entre-deux
entrepreneur-in-residence
environment-friendliness
environment-friendlinesses
environment-friendly
envy-freeness
envy-freenesses
ephrin
ephrin-eph
ephrins
epinastine
epoch-making
eprinomectin
eprosartan
epsilon-caprolactone
epsilon-caprolactones
epsilon-neighborhood
epsilon-neighborhoods
epsilon-neighbourhood
epsilon-neighbourhoods
epsilon-polylysine
epsilon-polylysines
equal-area
equal-tempered
equal-to-the-apostles
equi-axed
equi-inclination
equi-inclinations
ereyesterdays
erfurt
ergoline
ergolines
erlichmanite
erlichmanites
erzya
esan
esaxerenone
eshay
eshays
eskaleut
eskimo-aleut
esperamicin
estate-bottle
estate-bottled
esterification-hydrolyses
esterification-hydrolysis
esthesioneuroblastoma
esthesioneuroblastomas
ethambutol-isoniazids
ether-a-go-go
ether-a-go-gos
ethno-nationalism
ethno-nationalisms
ethno-nationalist
ethno-nationalists
ethno-state
ethno-states
ethyleneimine
ethylidynes
ethylphenol
ethylphenols
etizolam
eulytites
euro-disco
euro-discos
even-aged
even-keeled
even-minded
even-tempered
even-temperedness
even-temperednesses
even-toed
evenkites
ever-changing
ever-present
everything-as-a-service
evil-minded
evil-mindedness
evil-mindednesses
ewe-neck
ewe-necked
ewe-necks
ewedu
ewondo
ex-boyfriend
ex-boyfriends
ex-captain
ex-colleague
ex-colleagues
ex-con
ex-cons
ex-convict
ex-convicts
ex-directory
ex-ex-gay
ex-ex-gays
ex-fiance
ex-fiancee
ex-fiancees
ex-fiances
ex-gay
ex-gays
ex-girlfriend
ex-girlfriends
ex-husband
ex-husbands
ex-libris
ex-mayor
ex-mayors
ex-partner
ex-partners
ex-president
ex-presidents
ex-serviceman
ex-servicemen
ex-voto
ex-votos
ex-wife
ex-wives
examinations-in-chief
executive-in-residence
executives-in-residence
exercisabilities
exercisability
exosome
exosomes
extended-release
extra-aortic
extra-axillary
extra-classroom
extra-virgin
eye-appealing
eye-catcher
eye-catchers
eye-catching
eye-filling
eye-opener
eye-openers
eye-opening
eye-openings
eye-popper
eye-poppers
eye-popping
eye-poppings
eye-roll
eye-rolled
eye-rolling
eye-rollings
eye-rolls
eye-servant
eye-servants
eye-server
eye-servers
eye-service
eye-services
eye-spotted
eyeball-to-eyeball
f-actin
f-actins
f-block
f-blocks
f-bomb
f-bombs
f-center
f-centers
f-centre
f-centres
f-contraction
f-contractions
f-gas
f-gases
f-graph
f-graphs
f-hole
f-holes
f-number
f-numbers
f-orbital
f-orbitals
f-ratio
f-ratios
f-slur
f-slurs
f-stop
f-stops
f-system
f-systems
f-test
f-tests
f-word
f-words
fa'afafine
face-centered
face-centred
face-off
face-offs
face-to-face
face-to-faces
fact-check
fact-checked
fact-checker
fact-checkers
fact-checking
fact-checks
fact-finding
fact-findings
factories-as-a-service
faculties-in-residence
fade-in
fade-ins
fade-out
fade-outs
fail-safe
fail-safed
fail-safes
fail-safing
faint-hearted
faint-heartedness
faint-heartednesses
fair-faced
fair-minded
fairy-bluebird
fairy-bluebirds
far-fetch
far-fetched
far-fetchedness
far-fetchednesses
far-fetches
far-fetching
far-flung
far-forth
far-left
far-leftist
far-leftists
far-off
far-out
far-reaching
far-right
far-rightist
far-rightists
fare-thee-well
fare-thee-wells
farmer-entrepreneur
farmer-entrepreneurs
fast-food
fast-forward
fast-forwarded
fast-forwarding
fast-forwardings
fast-forwards
fast-mass
fast-moving
fat-ass
fat-assed
fat-asses
fat-shame
fat-shamed
fat-shames
fat-shaming
fat-shamings
father-in-law
fathers-in-law
fatwa'd
faux-bourdon
faux-bourdons
faux-hawk
faux-hawks
faux-naif
fe'fe'
fe'i
feeble-minded
feel-bad
fell-walker
fell-walkers
felo-de-se
felones-de-se
felos-de-se
female-to-male
female-to-males
fence-mending
fence-mendings
fence-off
fence-offs
fence-sitter
fence-sitters
fence-sitting
fence-sittings
fenfluramine-phentermine
fenfluramine-phentermines
fenoxaprop-ethyl
fenoxaprop-ethyls
fenoxaprop-p
fenoxaprop-p-ethyl
fenoxaprop-p-ethyls
fenoxaprop-ps
fer-de-lance
fer-de-lances
ferro-actinolite
ferro-glaucophane
ferro-hornblende
fesenjan
fetuin-a
fetuin-as
fetuin-b
fetuin-bs
few-shot
fi
fiddle-faddle
fiddle-faddles
fifty-eight
fifty-eighth
fifty-eighths
fifty-eights
fifty-fifth
fifty-fifths
fifty-fifties
fifty-fifty
fifty-first
fifty-firsts
fifty-five
fifty-fives
fifty-four
fifty-fours
fifty-fourth
fifty-fourths
fifty-nine
fifty-nines
fifty-ninth
fifty-ninths
fifty-one
fifty-ones
fifty-second
fifty-seconds
fifty-seven
fifty-sevens
fifty-seventh
fifty-sevenths
fifty-six
fifty-sixes
fifty-sixth
fifty-sixths
fifty-third
fifty-thirds
fifty-three
fifty-threes
fifty-two
fifty-twos
fig-marigold
fig-marigolds
figure-of-eight
figures-of-eight
fil-am
fil-ams
fill-in
fill-ins
finance-as-a-service
finances-as-a-service
fine-tune
fine-tuned
fine-tuner
fine-tuners
fine-tunes
fine-tuning
finger-spell
finger-spelled
finger-spelling
finger-spells
finger-spelt
finite-dimensional
finite-dimensionalities
finite-dimensionality
finnemanite
finnemanites
fintechs-as-a-service
fipa
fire-and-brimstone
fire-eater
fire-eaters
fire-eye
fire-eyes
fire-worshipper
fire-worshippers
first-class
first-classes
first-feet
first-foot
first-footed
first-footer
first-footers
first-footing
first-footings
first-foots
first-hand
first-in-class
first-order
first-person
first-rate
first-rateness
first-ratenesses
first-rater
first-raters
first-string
first-stringer
first-stringers
first-world
fischesserite
fischesserites
fist-fuck
fist-fucked
fist-fucking
fist-fucks
five-and-dime
five-and-dimes
five-and-ten
five-and-tens
five-dimensional
five-finger
five-fingers
five-o
five-os
five-sisters
five-sphere
five-spheres
five-star
five-way
five-ways
fix-up
fix-ups
fixed-line
fixer-upper
fixer-uppers
flag-waver
flag-wavers
flag-waving
flak-catcher
flak-catchers
flame-of-the-forest
flame-of-the-woods
flames-of-the-forest
flames-of-the-woods
flare-up
flare-ups
flash-forward
flash-forwarded
flash-forwarding
flash-forwards
flat-earther
flat-earthers
flat-foot
flat-footed
flat-footing
flat-foots
flea-market
flea-markets
fleet-foot
fleet-footed
fleur-de-lis
fleur-de-luce
fleur-de-lys
fleurs-de-lis
fleurs-de-luce
fleurs-de-lys
flick-knife
flick-knives
flip-flop
flip-flopped
flip-flopper
flip-floppers
flip-flopping
flip-flops
floating-point
floccinaucinihilipilificate
floccinaucinihilipilificates
floccinaucinihilipilificatings
floor-through
floor-throughs
flower-of-an-hour
flowers-of-an-hour
flualprazolam
fluazifop-butyl
fluazifop-butyls
fluazifop-p
fluazifop-p-butyl
fluazifop-p-butyls
fluazifop-ps
flubromazepam
flubromazolam
fluor-liddicoatite
fluoro-edenite
fluralaner
fluticasone-salmeterol
fluticasone-salmeterols
fluxapyroxad
fly-by
fly-by-night
fly-by-nights
fly-by-wire
fly-by-wires
fly-bys
fly-on-the-wall
fly-past
fly-pasts
fly-up-the-creek
fly-up-the-creeks
flycatcher-shrike
flycatcher-shrikes
fo'c's'le
fo'c's'les
fo'c'sle
fo'c'sles
foliage-gleaner
foliage-gleaners
folk-right
folk-rights
follow-on
follow-ons
follow-through
follow-throughs
follow-up
follow-ups
fongbe
foot-lambert
foot-lamberts
foot-pound-second
football-mad
for-profit
force-fed
force-feed
force-feeding
force-feedings
fore-and-aft
fore-and-after
forget-me-not
forget-me-nots
form-fitting
forward-looking
forward-lookingness
forward-lookingnesses
forward-thinking
fos-b
fos-bs
fostemsavir
fougerite
fougerites
foul-up
foul-ups
founder-in-residence
founders-in-residence
four-ball
four-balls
four-dimensional
four-dimensionalities
four-dimensionality
four-dimensionally
four-eye
four-eyes
four-on-the-floor
four-on-the-floors
four-sphere
four-spheres
four-star
four-way
four-ways
fraipontite
fraipontites
frame-dragging
frame-draggings
frame-perfect
frame-up
frame-ups
framycetin
franco-ontarian
franco-ontarians
free-fall
free-falling
free-falls
free-fell
free-for-all
free-for-alls
free-market
free-marketeer
free-marketeers
free-markets
free-range
free-to-play
french-cut
frigophobia
front-end
front-end-as-a-service
front-ends
front-ends-as-a-service
frontend-as-a-service
frontends-as-a-service
frou-frou
frou-frous
fructo-oligosaccharide
fructo-oligosaccharides
fruit-hunter
fruit-hunters
fs
fuck-off
fuck-offs
fuck-up
fuck-ups
fuddy-duddies
fuddy-duddy
fuiyoh
full-blooded
full-blown
full-bodied
full-fledged
full-grown
full-length
full-on
full-rigged
full-rigger
full-riggers
full-scale
full-sib
full-sibling
full-siblings
full-sibs
full-size
full-sized
full-term
full-terms
full-time
full-timer
full-timers
function-as-a-service
functions-as-a-service
fuqaha'
fuzhounese
fuzzy-headed
fuzzy-wuzzies
fuzzy-wuzzy
g-actin
g-actins
g-algebra
g-algebras
g-banded
g-banding
g-bandings
g-code
g-codes
g-commerce
g-computation
g-computations
g-estimation
g-estimations
g-force
g-forces
g-graph
g-graphs
g-homomorphism
g-homomorphisms
g-house
g-houses
g-man
g-men
g-optimal
g-optimalities
g-optimality
g-rated
g-ring
g-rings
g-spot
g-spots
g-string
g-strings
g-suit
g-suits
g-test
g-tests
g'day
g'morning
g'night
gabapentinoid
gabapentinoids
gado-gado
gado-gados
gagauz
gain-of-function
gairaigo
gal-o
gal-os
galacto-oligosaccharide
galacto-oligosaccharides
galactosylceramide
galactosylceramides
galbi-jjim
galbi-jjims
galbi-tang
galectin
galectins
galentine's
gamma-adaptin
gamma-adaptins
gamma-aminobutyrate
gamma-aminobutyrates
gamma-butyrolactone
gamma-butyrolactones
gamma-cyclodextrin
gamma-cyclodextrins
gamma-glutamyl
gamma-glutamylcysteine
gamma-glutamylcysteines
gamma-glutamyls
gamma-glutamyltransferase
gamma-glutamyltransferases
gamma-hexachlorocyclohexane
gamma-hexachlorocyclohexanes
gamma-hydroxybutyrate
gamma-hydroxybutyrates
gamma-oryzanol
gamma-oryzanols
gamma-sarcoglycanopathy
gamma-secretase
gamma-secretases
ganetespib
gang-gang
gang-gangs
gankogui
gankoguis
ganzi
gap-toothed
garden-variety
gas-guzzler
gas-guzzlers
gas-guzzling
gastro-esophageal
gastro-oesophageal
gay-ass
gay-baiting
gay-baitings
gaylors
gayo
gbagyi
gbandi
gbaya
gbii
gbo
gcaleka
gcalekas
ge'ez
gedaged
gedatolisib
gedeo
gedunin
gedunins
gee-gaw
gee-gaws
geerite
geerites
geldanamycin
gemigliptin
gender-critical
gender-fluid
genderbent
genon
genons
geomungo
geomungos
gepotidacin
get-go
get-gos
get-rich-quick
get-together
get-togethers
get-up
get-up-and-go
get-up-and-goes
get-ups
ghetto-blaster
ghetto-blasters
giddy-up
gijinkas
gikyode
gill-over-the-ground
gill-over-the-grounds
gilyak
ginjo-shu
ginsenoside
ginsenosides
girls-and-boys
gitga'at
gitxaala
give-and-take
give-and-takes
givosiran
glacio-hydro-isostatic
glaserites
glatiramer
glecaprevir-pibrentasvir
glory-of-the-snow
glory-of-the-snows
glory-of-the-sun
glory-of-the-suns
glory-pea
glory-peas
glow-in-the-dark
glow-up
glow-ups
glu-c
glu-cs
glucosylceramide
glucosylceramides
glucuronidation
glucuronidations
glucuronolactone
glucuronolactones
glucuronoside
glucuronosides
glutamyl
glutamyls
glyoxylate
go-ahead
go-aheads
go-as-you-please
go-away-bird
go-away-birds
go-between
go-betweens
go-cart
go-carted
go-carting
go-carts
go-getter
go-getters
go-go
go-gos
go-kart
go-karted
go-karting
go-karts
go-no-go
go-to
go-tos
god-emperor
god-emperors
god-fearing
godoberi
going-away
going-over
goings-on
goings-over
gokhru
gold-tail
gold-tails
goma-ae
gomaae
gomae
gomarians
gomarists
good-doer
good-for-naughts
good-for-nothing
good-for-nothings
good-hearted
good-heartedly
good-heartedness
good-heartednesses
good-humored
good-humoredly
good-humoured
good-humouredly
good-king-henries
good-king-henry
good-looking
good-lookingness
good-lookingnesses
good-natured
good-naturedly
good-naturedness
good-naturednesses
good-neighbor
good-neighbour
good-o
good-oh
good-sized
good-tempered
good-temperedly
good-temperedness
good-temperednesses
good-time
goof-up
goof-ups
google-bombing
google-bombings
gooniyandi
goserelins
government-in-exile
government-issued
governments-in-exile
governor-general
governor-general-in-council
governor-generals
governor-generals-in-council
governor-generalship
governor-generalships
governor-in-council
governors-general
governors-in-council
gowli
goyim
gram-negative
gram-positive
grammatico-historical
granddaughters-in-law
grandfather-in-law
grandfathers-in-law
grass-of-parnassus
gray-a
gray-ace
gray-faced
great-aunt
great-aunts
great-grandchild
great-grandchildren
great-granddaughter
great-granddaughters
great-grandfather
great-grandfathers
great-grandkid
great-grandkids
great-grandmother
great-grandmothers
great-grandparent
great-grandparents
great-grandson
great-grandsons
great-great-grandfather
great-great-grandfathers
great-great-grandmother
great-great-grandmothers
great-hearted
great-nephew
great-nephews
great-niece
great-nieces
great-uncle
great-uncles
green-light
green-lighted
green-lighting
green-lights
green-lit
grey-a
grey-ace
grey-faced
gri-gri
grihasthas
groom-to-be
grooms-to-be
ground-cuckoo
ground-cuckoos
grown-up
grown-up-ness
grown-up-nesses
grown-ups
guambiano
gudu
guilt-trip
guilt-tripped
guilt-tripping
guilt-trips
guinea-bissau
guinea-bissauan
guinea-bissauans
guizhi-fuling
gumatj
gumbo-limbo
gumbo-limbos
gumuz
gun-toting
gunas
gung-ho
guotie
gurma
gurunsi
gut-wrenching
gutta-percha
gutta-perchas
guv'nor
guv'nors
gwangbokjeol
gwich'in
gwiyagal
gyaru-o
gyaru-os
gyeran-jjim
gympie-gympies
gyrification
gyrifications
h-beam
h-beams
h-bomb
h-bombs
h-bond
h-bonded
h-bonding
h-bondings
h-bonds
h-graph
h-graphs
h-pop
h-ras
h-rases
h-transform
h-transforms
h-vector
h-vectors
ha-ha
ha-has
ha'p'orth
ha'p'orths
haak-en-steek
haak-en-steeks
habit-forming
hackfests
hackmanite
hackmanites
hactivism
hactivisms
hactivist
hactivists
hadiyya
hadn't
hadn't've
haejang-guk
hail-fellow-well-met
hair-raiser
hair-raisers
hair-raising
hair-raisingly
halaal
halazepam
half-and-half
half-and-halfs
half-arse
half-arsed
half-arses
half-arsing
half-ass
half-assed
half-asses
half-assing
half-baked
half-blind
half-blindness
half-blindnesses
half-blood
half-blooded
half-breed
half-breeds
half-brother
half-brothers
half-caste
half-castes
half-eaten
half-evergreen
half-faced
half-hang
half-hanged
half-hanging
half-hangings
half-hangs
half-hardy
half-hearted
half-heartedly
half-heartedness
half-heartednesses
half-hour
half-hourly
half-human
half-humans
half-hung
half-joke
half-joked
half-jokes
half-joking
half-jokingly
half-life
half-lives
half-mast
half-masted
half-masting
half-masts
half-n-half
half-naked
half-one
half-ones
half-plane
half-planes
half-sib
half-sibling
half-siblings
half-sibs
half-sister
half-sisters
half-smoke
half-smokes
half-space
half-spaces
half-staff
half-staffs
half-term
half-true
half-truth
half-truths
half-volley
half-volleyed
half-volleying
half-volleys
half-wit
half-wits
half-witted
half-yearly
hallowe'en
hallowe'ens
halo-halo
halofantrine
halosulfuron-methyl
halosulfuron-methyls
halq'emeylem
ham-fisted
ham-handed
ham-handedly
ham-handedness
ham-handednesses
hammer-and-tongs
hammer-on
hammer-ons
hand-fed
hand-feed
hand-feeding
hand-feeds
hand-me-down
hand-me-downs
hand-pollinating
hand-pollination
hand-pollinations
hand-to-hand
hand-to-mouth
hang-gliding
hang-up
hang-ups
hanga
hangaza
hanger-on
hangers-on
hanky-pankies
hanky-panky
hanos
hanzi
haplo-insufficiencies
haplo-insufficiency
happy-go-luckier
happy-go-luckies
happy-go-luckiest
happy-go-lucky
hara-kiri
hara-kiris
harbinger-of-spring
harbingers-of-spring
hard-bitten
hard-boiled
hard-core
hard-headdresses
hard-headednesses
hard-hearted
hard-heartedness
hard-heartednesses
hard-liner
hard-liners
hard-nosed
hard-on
hard-ons
hard-pressed
hare-brained
harrier-hawk
harrier-hawks
hartites
harum-scarum
haryanvi
has-been
has-beens
hashimoto's
hasn't
hate-watch
hate-watched
hate-watches
hate-watching
haut-relief
haut-reliefs
haute-contre
hautes-contre
have-a-go
haven't
havu
haw-haw
haw-hawed
haw-hawing
haw-haws
hawai'i
hawk-eagle
hawk-eagles
hawk-eyed
hawk-owl
hawk-owls
hdi
he-he
he-he'd
he-heing
he-hes
he'd
he'd've
he'll
he's
head-butt
head-butted
head-butter
head-butters
head-butting
head-butts
head-carrying
head-carryings
head-hunting
head-huntings
head-on
head-ons
head-splitting
head-to-head
healthspan
healthspans
heart-searching
heart-searchings
heart-stopper
heart-stoppers
heart-stoppingly
heart-to-heart
heart-to-hearts
heat-treat
heat-treated
heat-treating
heat-treats
heave-ho
heave-hos
heaven-sent
heavy-duty
heavy-handed
heavy-handedly
heavy-handedness
heavy-handednesses
heavy-headed
heavy-headedness
heavy-headednesses
heavy-hearted
heavy-heartedly
heavy-heartedness
heavy-heartednesses
hee-hee
hee-heed
hee-heeing
hee-hees
heebie-jeebies
heigh-ho
height-ho
hell-bent
hell-raiser
hell-raisers
helter-skelter
helter-skelters
helvites
hen-of-the-woods
here's
herkimers
hermeneutic-phenomenological
heron's-bill
heron's-bills
hetero-oligomerisation
hetero-oligomerisations
hetero-oligomerization
hetero-oligomerizations
hexa-peri-hexabenzocoronene
hexa-peri-hexabenzocoronenes
hexynes
hi-fi
hi-fis
hi-hat
hi-hats
hi-res
hi-tech
hi-vis
hide-and-go-seek
hide-and-go-seeks
hide-and-seek
hide-and-seeks
higgledy-piggledy
high-altitude
high-and-mighty
high-beam
high-beams
high-born
high-class
high-context
high-cost
high-cut
high-definition
high-definitions
high-density
high-dimensional
high-end
high-energy
high-fi
high-fis
high-five
high-fived
high-fives
high-fiving
high-flown
high-frequency
high-grade
high-handed
high-handedly
high-handedness
high-handednesses
high-hanging
high-hat
high-hats
high-hatted
high-hatting
high-k
high-key
high-level
high-maintenance
high-minded
high-mindedly
high-mindedness
high-mindednesses
high-octane
high-order
high-pitch
high-pitched
high-powered
high-pressure
high-pressured
high-pressures
high-pressuring
high-proof
high-ranking
high-res
high-resolution
high-rise
high-riser
high-risers
high-rises
high-risk
high-sided
high-sounding
high-speed
high-spirited
high-stick
high-sticked
high-sticking
high-sticks
high-strung
high-tech
high-temperature
high-test
high-throughput
high-toned
high-up
high-ups
high-value
high-velocity
high-visibility
high-yield
hill-topping
hill-toppings
hillites
hip-hop
hip-hopera
hip-hoperas
hip-hopper
hip-hoppers
hip-hopping
hip-hops
hip-huggers
hippety-hop
hippity-hop
hippity-hoppity
hit-and-miss
hit-and-ran
hit-and-run
hit-and-running
hit-and-runs
hit-or-miss
hit-to-kill
hitch-hike
hits-and-runs
hitting-and-running
hive-minded
hixkaryana
hlubis
hmar
hmong-mien
hmongic
ho-chunk
ho-hum
ho'oponopono
hochu-ekki-to
hocus-pocus
hocus-pocused
hocus-pocuses
hocus-pocusing
hoelites
hold-up
hold-ups
holier-than-thou
holtite
holtites
holus-bolus
home-cooked
homo-oligomerisation
homo-oligomerisations
homo-oligomerization
homo-oligomerizations
homoanatoxin-a
homoanatoxin-as
honest-to-god
honky-tonk
honky-tonks
honokiol
honokiols
hoo-ha
hoo-hah
hoo-hahs
hoo-has
hook-up
hook-ups
hoopoe-lark
hoopoe-larks
host-guest
hot-blooded
hot-bloodedness
hot-bloodednesses
hot-plug
hot-pluggable
hot-plugged
hot-plugging
hot-plugs
hot-swap
hot-swappable
hot-swapped
hot-swapping
hot-swaps
hot-wire
hot-wired
hot-wires
hot-wiring
hotel-dieu
hotels-dieu
house-proud
how-to
how-tos
how'd
how're
how's
how've
howsoe'er
huang-lian-jie-du-tang
hub-and-spoke
huet-huet
huet-huets
hug-me-tight
hug-me-tights
hugger-mugger
hugger-muggers
huitoto
hul'qumi'num
humuhumunukunukuapua'a
hundred-percenter
hundred-percenters
hundred-percentism
hundred-percentisms
hunky-dory
hunt-and-peck
hunter-gatherer
hunter-gatherers
huntington's
huntite
huntites
hunzib
hurdy-gurdies
hurdy-gurdy
hurlbutite
hurlbutites
hurly-burlies
hurly-burly
hush-a-bye
hush-a-byed
hush-a-byes
hush-a-bying
hush-hush
huu-ay-aht
hydra-headed
hyper-aggressive
hyper-aggressively
hyper-calvinism
hyper-calvinisms
hyper-calvinist
hyper-calvinists
hyper-mediated
hyper-personalisation
hyper-personalisations
hyper-personalization
hyper-personalizations
hystero-epilepsies
hystero-epilepsy
hystero-salpingo-oophorectomies
hystero-salpingo-oophorectomy
hystero-salpingoophorectomies
hystero-salpingoophorectomy
hysterosalpingo-oophorectomies
hysterosalpingo-oophorectomy
i-beam
i-beams
i-concept
i-concepts
i-graph
i-graphs
i-hood
i-hoods
i-it
i-its
i-kiribati
i-ness
i-nesses
i-novel
i-novels
i-optimal
i-optimalities
i-optimality
i-pop
i-self
i-selves
i-thou
i-thous
i-vector
i-vectors
i'd
i'd've
i'll
i'm
i's
i've
ibero-romance
ibibio
iboga
ibogas
ibopamine
ibos
ibrutinib-rituximab
ice-skate
ice-skated
ice-skates
ice-skating
iceskates
iconique
icosagon
icosagons
icosahedrite
icosahedrites
idebenone
idec
identities-as-a-service
identity-as-a-service
idoma
igala
iguratimod
ijarean
ijarians
ikizu
ikwo
ilamas
ilang-ilang
ilang-ilangs
ill-advised
ill-advisedly
ill-being
ill-beings
ill-bred
ill-conceived
ill-equipped
ill-fared
ill-faring
ill-fated
ill-favored
ill-favoured
ill-looking
ill-mannered
ill-starred
ill-tempered
ill-timed
ill-treat
ill-treated
ill-treating
ill-treatment
ill-treatments
ill-treats
illyrians
ilonggos
imageabilities
imageability
imipenem-cilastatin-relebactam
imipenem-cilastatin-relebactams
immediate-release
immuno-inflammatory
imonda
in-and-in
in-and-out
in-and-outer
in-and-outers
in-and-outs
in-between
in-betweener
in-betweeners
in-betweens
in-depth
in-depthness
in-depthnesses
in-engine
in-flight
in-game
in-group
in-groups
in-house
in-joke
in-jokes
in-law
in-laws
in-line
in-order-to
in-order-tos
in-your-face
incyclotorsion
indo-european
indolizidine
indolizidines
indolizine
indolizines
infinite-dimensional
infinite-dimensionalities
infinite-dimensionality
infinity-dimensional
inflamm-ageing
inflamm-aging
information-analytical
information-theoretic
inku
innsbruck
insights-as-a-service
integro-differential
intra-abdominal
intra-abdominally
intra-aortic
inuit-yupik-unangan
iobitridol
iodochlorohydroxyquinoline
iodosulfuron-methyl
iodosulfuron-methyl-sodium
iodosulfuron-methyl-sodiums
iodosulfuron-methyls
ionisation-recombination
ionisation-recombinations
ionization-recombination
ionization-recombinations
iota-carrageenan
iota-carrageenans
iota-toxin
iota-toxins
ioxaglate
ioxaglates
ipsapirone
ipso-substitution
ipso-substitutions
iranite
iranites
ischemia-reperfusions
isekai'd
ishikawaite
ishikawaites
island-hop
island-hopped
island-hopping
island-hops
isma'ili
isma'ilis
isma'ilism
isma'ilisms
isn't
isobutyraldehydes
isobutyrates
isomalto-oligosaccharide
isomalto-oligosaccharides
isopropyl-beta-d-thiogalactopyranoside
isopropyl-beta-d-thiogalactopyranosides
ispinesib
istisqa'
istisqaa'
istriot
isu
it'd
it'll
it's
itameshi
itopride
itsy-bitsy
itty-bitty
iturin
iturins
j-aggregate
j-aggregated
j-aggregates
j-aggregation
j-aggregations
j-beauties
j-beauty
j-card
j-cards
j-continuous
j-core
j-cores
j-coupled
j-coupling
j-couplings
j-curve
j-curves
j-day
j-days
j-drama
j-dramas
j-euro
j-euros
j-function
j-functions
j-holomorphic
j-homomorphism
j-homomorphisms
j-horror
j-horrors
j-invariant
j-invariants
j-measure
j-measures
j-pop
j-pops
j-pouch
j-pouches
j-punk
j-punks
j-rock
j-rocks
j-stroke
j-strokes
j-substitution
j-substitutions
j-town
j-towns
j-trance
j-trances
jack-go-to-bed-at-noon
jack-go-to-bed-at-noons
jack-in-the-box
jack-in-the-boxes
jack-in-the-pulpit
jack-in-the-pulpits
jack-jump-up-and-kiss-me
jack-jump-up-and-kiss-mes
jack-o-lantern
jack-o-lanterns
jack-o'-lantern
jack-of-all-trades
jack-off
jack-offs
jack-over-the-ground
jack-over-the-grounds
jack-pudding
jack-puddings
jack-up
jack-ups
jahn-teller
jaipurite
jaipurites
jakaltek
jam-pack
jam-packed
jam-packing
jam-packs
jamesians
janus-faced
jaquimas
jaw-breaking
jaw-breakings
jaw-dropper
jaw-droppers
jaw-droppingly
jawi
jazz-funk
jelqed
jelqer
jelqers
jelqing
jelqmaxx
jelqmaxxing
jerry-built
jig-a-jig
jig-a-jigs
jig-jig
jig-jigs
jig-jog
jig-jogs
jim-dandies
jim-dandy
jirai-kei
jiu-jitsu
jiu-jutsu
jnana-marga
jnana-margas
johannsenite
johannsenites
john-go-to-bed-at-noon
john-go-to-bed-at-noons
johnnies-come-lately
johnny-come-latelies
johnny-come-lately
johnny-jump-up
johnny-jump-ups
johnny-on-the-spot
johnny-on-the-spots
join-the-dot
join-the-dots
jori
joris
journalist-in-residence
journalists-in-residence
joy-juice
joy-juices
ju-jitsu
ju-jutsu
judaeo-arabic
judaeo-christian
judaeo-christian-islamic
judaeo-christianities
judaeo-christianity
judaeo-christians
judaeo-spanish
judaeo-tajik
judaeo-tat
judeo-arabic
judeo-christian
judeo-christian-islamic
judeo-christianities
judeo-christianity
judeo-christians
judeo-spanish
judeo-tajik
judeo-tat
jukun
jump-start
jump-started
jump-starting
jump-starts
jump-up
jump-ups
jumpstart
jumpstarted
jumpstarting
jumpstarts
jumpstyles
jun-b
jun-bs
jun-d
jun-ds
jungar
junggar
jusqu'au-boutisme
jusqu'au-boutismes
jusqu'au-boutiste
jusqu'au-boutistes
just-in-time
juxta-articular
juxta-epithelial
juxta-glomerular
juxta-pleural
juxta-renal
juzen-taiho-to
juzu
k-algebra
k-algebras
k-beauty
k-cadherin
k-cadherins
k-casein
k-caseins
k-center
k-centers
k-derivation
k-derivations
k-dimensional
k-drama
k-dramas
k-functor
k-functors
k-grade
k-grades
k-graph
k-graphs
k-indie
k-invariant
k-invariants
k-medoid
k-medoids
k-normal
k-partition
k-partitions
k-planar
k-pop
k-pops
k-ras
k-rases
k-set
k-sets
k-shaped
k-subset
k-subsets
k-substitution
k-substitutions
k-theories
k-theory
k-topologies
k-topology
k-vector
k-vectors
k-vertex
k-vertices
k'iche
k'iche'
ka'ak
ka'aks
kabeljauw
kabeljauws
kabiye
kabuverdianu
kadang-kadang
kadazan
kadazan-dusun
kadazandusun
kaeshi
kaguru
kaiten-zushi
kakeibo
kakiage
kakiages
kal-guksu
kala-azar
kaleckian
kaleckians
kalenjin
kalenjins
kam-tai
kama'ainas
kambaata
kambera
kami-oshi
kami-oshis
kampo
kampos
kanazawa
kangkong
kangkongs
kangkung
kangkungs
kani
kanienkehaka
kanikama
kaolinite-serpentine
kaolinite-serpentines
kapin
kappa-carrageenan
kappa-carrageenans
kappa-casein
kappa-caseins
kaqchikeles
karai-karai
karamojong
karamojongs
karay-a
kare-kare
karelianite
karelianites
karma-marga
karma-margas
katophorite
katophorites
kavango
kavangos
keepy-uppies
keepy-uppy
kekulene
kekulenes
kelewele
ketazolam
ketiv
ketupat-ketupat
keynesians
kgalagadi
kgati
khakas
khamrabaevite
khamrabaevites
kharcho
khartal
khartals
khiamniungan
khinalug
khinkali
khinklebi
khoekhoegowab
khol
khus-khus
khus-khuses
ki-yi
ki-yied
ki-yiing
ki-yis
kick-start
kick-started
kick-starting
kick-starts
kiga
kilishi
kilivila
kill-devil
kill-devils
kiloelectron-volt
kiloelectron-volts
kilovolt-ampere
kilovolt-amperes
kilowatt-hour
kilowatt-hours
kimchi-jjigae
kimilsungism-kimjongilism
kimilsungism-kimjongilisms
kinaray-a
kind-hearted
kind-heartedly
kind-heartedness
kind-heartednesses
kinetochore-microtubule
king-in-parliament
king-of-the-salmon
king-of-the-salmons
king-size
king-sized
kinga
kink-shame
kink-shamed
kink-shames
kink-shaming
kinyarwanda
kip-up
kip-ups
kipchaks
kipsigis
kirgiz
kisir
kiss-a-ba
kiss-a-bas
kiss-and-look-up
kiss-and-look-ups
kiss-her-in-the-butteries
kiss-her-in-the-buttery
kiss-me
kiss-me-at-the-gate
kiss-me-at-the-gates
kiss-me-over-the-garden-gate
kiss-me-over-the-garden-gates
kiss-me-quick
kiss-me-quicks
kiss-mes
kissi
kitty-come
kitty-comes
kitty-corner
kitty-cornered
kitty-run
kitty-runs
kituba
kjokkenmoddinger
klepon-klepon
klocki
knee-highs
knee-slapper
knee-slappers
knees-up
knick-knack
knick-knackeries
knick-knackery
knick-knacks
knife-edge
knife-edges
knight-errant
knight-errantries
knight-errantry
knights-errant
knock-down
knock-down-and-drag-out
knock-down-and-drag-outs
knock-kneed
knock-knock
knock-on
knock-up
knocker-up
knocker-upper
knocker-uppers
knocker-ups
know-how
know-hows
know-it-all
know-it-alls
know-nothing
know-nothingism
know-nothingisms
know-nothings
knowledge-as-a-service
knowledges-as-a-service
knuckle-dust
knuckle-dusted
knuckle-dusting
knuckle-dusts
kok-saghyz
kokoda
komi-permyak
kompetenz-kompetenz
konjo
konkomba
konso
konyo
konyos
kootenays
kopytka
koshari
kosharis
kouign-amann
kovshes
kpelle
krabi
krachel
krachels
kraepelinian
kraepelinians
krio
kriol
krobu
krutaites
kugelblitz
kugelblitzes
kukama
kukatja
kumaoni
kunama
kunamas
kung-fu
kuo-yu
kuria
kurias
kusaal
kwak'wala
kwakwaka'wakw
kwandu
kwara'ae
kwasio
kwaya
kwazulu-natal
kwek-kwek
kwere
kx'a
l-acetylcarnitine
l-alanine
l-alanines
l-alanyl-l-alanine
l-alanyl-l-alanines
l-alanyl-l-glutamine
l-alloisoleucine
l-alloisoleucines
l-amphetamine
l-arabinitol
l-arabinitols
l-arabinose
l-arabinoses
l-arabitol
l-arabitols
l-arginine
l-arginines
l-asparaginase
l-asparaginases
l-asparagine
l-asparagines
l-aspartate
l-aspartates
l-bracket
l-brackets
l-carnitine
l-carnitines
l-carvone
l-carvones
l-cell
l-cells
l-configuration
l-configurations
l-cysteine
l-cysteines
l-dopa
l-dopas
l-enantiomer
l-enantiomers
l-form
l-forms
l-fucose
l-fucoses
l-function
l-functions
l-galactose
l-galactoses
l-glutamate
l-glutamates
l-glutamine
l-glutamines
l-glycero-d-manno-heptose
l-glycero-d-manno-heptoses
l-graph
l-graphs
l-homoserine
l-homoserines
l-hydroxyproline
l-hydroxyprolines
l-idose
l-idoses
l-infinities
l-infinity
l-isoleucine
l-isoleucines
l-isomer
l-isomers
l-kurtoses
l-kurtosis
l-leucine
l-leucines
l-leucovorin
l-lyxose
l-lyxoses
l-malate
l-malates
l-mannose
l-mannoses
l-matrices
l-matrix
l-menthol
l-meth
l-methamphetamine
l-methamphetamines
l-methionine
l-meths
l-mimosine
l-moment
l-moments
l-myc
l-mycs
l-nucleoside
l-nucleosides
l-ornithine-l-aspartate
l-phenylalanine
l-phenylalanines
l-phenylalaninol
l-phenylalaninols
l-phenylglycine
l-phenylglycines
l-pop
l-proline
l-reduction
l-reductions
l-rhamnose
l-rhamnoses
l-selectin
l-selectins
l-serine
l-serines
l-shaped
l-tetrahydropalmatine
l-tetrahydropalmatines
l-threonine
l-trehalose
l-trehaloses
l-tryptophan
l-tyrosine
l-tyrosines
l-value
l-values
l-xylose
l-xyloses
l'chaim
l'chayim
la-de-da
la-di-da
lab-e-shireen
lab-on-a-chip
lab-on-a-molecule
lab-on-chip
lab-on-chips
labs-on-a-chip
labs-on-a-molecule
labs-on-chip
labs-on-chips
lacto-ovo-vegetarian
lacto-ovo-vegetarians
lacto-vegetarian
lacto-vegetarians
ladies-in-waiting
ladies-of-the-night
lady-help
lady-helps
lady-in-waiting
lady-killer
lady-killers
lady-killings
lady-of-the-night
lady's-comb
lady's-combs
lady's-delight
lady's-delights
lady's-eardrop
lady's-eardrops
lady's-earrings
lady's-finger
lady's-fingers
lady's-glove
lady's-gloves
lady's-grass
lady's-grasses
lady's-lace
lady's-laces
lady's-lint
lady's-lints
lady's-maid
lady's-maided
lady's-maiding
lady's-maids
lady's-nightcap
lady's-nightcaps
lady's-pocket
lady's-pockets
lady's-purse
lady's-purses
lady's-slipper
lady's-slippers
lady's-smock
lady's-smocks
lady's-sorrel
lady's-sorrels
lady's-thimble
lady's-thimbles
lady's-thumb
lady's-thumbs
lady's-tobacco
lady's-tobaccos
lady's-tresses
lafutidine
lah-de-dah
lah-dee-dah
lah-di-dah
laid-back
laisser-aller
laisser-passer
laissez-aller
laissez-faire
laissez-faireism
laissez-faireisms
laissez-faires
laissez-passer
lakshadweep
lambda-carrageenan
lambda-carrageenans
lambda-cyhalothrins
lame-o
lame-os
lance-jack
lance-jacks
lanosterol
laparohysterosalpingooophorectomies
laquinimod
lardy-dardy
large-scale
larimar
lash-up
last-ditch
last-minute
latch-up
latch-ups
latchup
latchups
late-term
lateen-rigged
latrotoxin
latrotoxins
latter-day
lava-lava
lava-lavas
law-abiding
law-abidingness
law-abidingnesses
lawyer-linguist
lawyer-linguists
lay-by
lay-bys
lay-up
lay-ups
lazertinib
lead-in
lead-ins
lead-up
lead-ups
lean-to
lean-tos
learner-centeredness
learner-centerednesses
learner-centredness
learner-centrednesses
learning-as-a-service
learnings-as-a-service
lease-up
lease-ups
ledipasvir-sofosbuvir
lefamulin
left-hand
left-handed
left-handedness
left-handednesses
left-handers
left-libertarianism
left-libertarianisms
left-wing
left-winger
left-wingers
leg-pull
leg-puller
leg-pullers
leg-pulling
leg-pullings
leg-pulls
lega
lemang-lemang
lemba
lembas
lendings-as-a-service
leniolisib
lenje
lergotrile
let's
leu-enkephalin
levamisole
level-headed
level-headedly
level-headedness
level-headednesses
levo-alpha-acetylmethadol
levo-alpha-acetylmethadols
levodopa-carbidopa
leyak
lezgian
li-ion
li-ions
li-liger
li-ligers
li'l
lianhua-qingwen
liberal-minded
lickety-split
liddicoatite
liddicoatites
lie-in
lie-ins
life-and-death
life-form
life-forms
life-size
life-sized
life-world
life-worlds
lifitegrast
ligbi
light-fingered
light-headed
light-headedly
light-headedness
light-headednesses
light-hearted
light-heartedly
light-heartedness
light-heartednesses
light-horseman
light-horsemen
light-minded
lighter-out
lighter-outs
lighting-as-a-service
lightings-as-a-service
lightning-quick
lihir
like-minded
like-mindedly
like-mindedness
like-mindednesses
likely-looking
lilies-of-the-valley
lily-livered
lily-of-the-valley
linaclotide
lincoln-douglas
line-up
line-ups
ling-ling-o
ling-ling-os
lingling-o
lingling-os
link-up
linsey-woolsey
linsey-woolseys
lip-reading
lip-service
lip-synched
lip-synching
lip-syncing
lipo-chitooligosaccharide
lipo-chitooligosaccharides
lipo-oligosaccharides
lirone
lisu
lithium-ion
lithium-ions
little-endian
little-endianness
little-endiannesses
live-forever
live-forevers
live-in
live-ins
live-stream
live-streamed
live-streaming
live-streams
lived-in
livvi
livvi-karelian
llapingachos
lo-fi
lo-fis
load-bearing
load-independent
lobio
localisation-delocalisation
localisation-delocalisations
localization-delocalization
localization-delocalizations
lock-in
lock-ins
lock-up
log-sum-exp
log-sum-exps
loganins
lokoya
lolcow
lolcows
loloish
long-acting
long-distance
long-haul
long-hauled
long-hauling
long-hauls
long-minded
long-range
long-suffering
long-sufferings
long-tailed
long-term
long-termism
long-termisms
long-winded
long-windedly
long-windedness
long-windednesses
long-wool
long-wooled
longer-range
longer-term
longest-range
longest-term
lontong-lontong
look-up
look-ups
looker-on
lookers-on
loop-back
loop-backs
loose-jointed
loose-leaf
loose-leafed
loose-leaves
lord-and-lady
lords-and-ladies
lormetazepam
loss-of-function
lost-and-found
loud-mouthed
loukoumades
loup-garou
loups-garous
love-hate
love-in
love-in-a-mist
love-in-a-mists
love-in-idleness
love-in-idlenesses
love-ins
love-lies-bleeding
love-lies-bleedings
love-shy
love-shyness
love-shynesses
love-struck
loving-kindness
loving-kindnesses
low-alcohol
low-altitude
low-brow
low-budget
low-calorie
low-carb
low-carbohydrate
low-ceilinged
low-class
low-context
low-cost
low-density
low-dimensional
low-down
low-end
low-fat
low-fi
low-fidelity
low-fis
low-frequency
low-functioning
low-grade
low-heeled
low-impact
low-income
low-k
low-key
low-keyed
low-level
low-life
low-lifes
low-lived
low-lives
low-maintenance
low-minded
low-mindedly
low-necked
low-order
low-paid
low-pitch
low-pitched
low-power
low-powered
low-pressure
low-quality
low-rent
low-rise
low-riser
low-risers
low-rises
low-risk
low-sided
low-speed
low-spirited
low-sulfur
low-sulphur
low-tar
low-tech
low-temperature
low-tension
low-throughput
low-value
low-velocity
low-yield
lower-budget
lower-carb
lower-class
lower-classness
lower-classnesses
lower-dimensional
lower-fat
lower-order
lower-pitched
lower-quality
lower-risk
lowest-budget
lowest-carb
lowest-dimensional
lowest-fat
lowest-order
lowest-pitched
lowest-quality
lowest-risk
lozengers
lp-norm
lp-norms
lp-space
lp-spaces
luba-kasai
luba-katanga
luba-lulua
luft
lufts
lugbara
lumacaftor-ivacaftor
lumazine
luminogen
luminogenic
luminogens
luseogliflozin
lushootseed
lusutrombopag
luvale
lying-in
lying-ins
lyings-in
lys-c
lys-cs
lys-n
lys-ns
lyxopyranose
lyxopyranoses
lyxoses
m-aminobenzoate
m-aminobenzoates
m-cadherin
m-cadherins
m-cat
m-cats
m-chloronitrobenzene
m-chloronitrobenzenes
m-chlorophenylpiperazine
m-chlorophenylpiperazines
m-commerce
m-commerces
m-cresol
m-cresols
m-dependence
m-dependences
m-dependent
m-dichlorobenzene
m-dichlorobenzenes
m-dimensional
m-dimensionalities
m-dimensionality
m-ethylphenol
m-ethylphenols
m-health
m-healths
m-hydroxybenzaldehyde
m-hydroxybenzoate
m-hydroxybenzoates
m-matrices
m-matrix
m-nitroaniline
m-nitroanilines
m-nitrobenzaldehyde
m-nitrobenzaldehydes
m-nitrochlorobenzene
m-nitrochlorobenzenes
m-phenylenediamine
m-phenylenediamines
m-terphenyl
m-terphenyls
m-theories
m-theory
m-toluidine
m-toluidines
m-vector
m-vectors
m-way
m-ways
m'kay
m'ladies
m'lady
ma'am
ma'ams
ma'ariv
ma'arivim
ma'jonga
ma'rifa
ma'rifas
maaqoudas
maasai
machineries-as-a-service
machinery-as-a-service
machines-as-a-service
macro-axes
macro-axis
macro-kjeldahl
made-up
madonna-whore
mafenide
magnesio-arfvedsonite
magnesio-arfvedsonites
magnesio-carbonatites
magnesio-hastingsites
magnesio-hornblende
magnesio-wustite
magnesio-wustites
magnetite-ulvospinel
magnetite-ulvospinels
magpie-jay
magpie-jays
magpie-lark
magpie-larks
magpie-robin
magpie-robins
mah-jong
mah-jongg
mah-jonggs
mah-jongs
mahi-mahi
mahi-mahis
maiden's-blush
maiden's-blushes
maidenhair-vine
maidenhair-vines
majles
majleses
major-domo
major-domos
majorisation-minimisation
majorisation-minimisations
majorization-minimization
majorization-minimizations
makatite
makatites
make-believe
make-believes
make-do
make-up
make-ups
makhuwa
maki-e
making-of
making-ofs
male-to-female
male-to-females
maliseet-passamaquoddy
malto-oligosaccharide
malto-oligosaccharides
malvi
malwares-as-a-service
mama-san
mama-sans
mambila
man-about-town
man-at-arms
man-child
man-children
man-eater
man-eaters
man-eating
man-o'-war
man-of-all-work
man-of-the-earth
man-of-war
man-to-man
man-to-mans
man'oushe
man'ousheh
man'yogana
maneki-neko
mange-tout
mange-touts
mangel-wurzel
mangel-wurzels
mani-pedi
mani-pedis
manic-depressive
manic-depressives
mankon
mannan-oligosaccharide
mannan-oligosaccharides
manno-oligosaccharide
manno-oligosaccharides
manufacturing-as-a-service
manufacturings-as-a-service
many-sided
many-sidedness
many-sidednesses
manza
manzai
mao-tai
mao-tais
mao-to
maprotiline
mapudungun
marasmic-kwashiorkors
marbofloxacin
march-past
march-pasts
mare's-nest
mare's-nests
mare's-tail
mare's-tails
mark-up
mark-ups
marketing-as-a-service
marketings-as-a-service
marketplace-as-a-service
marketplaces-as-a-service
marmitako
marmitakos
marxism-leninism
marxism-leninism-maoism
marxism-leninism-maoisms
marxism-leninisms
marxist-leninist
marxist-leninist-maoist
marxist-leninist-maoists
marxist-leninists
masalit
mash-up
mash-ups
masha'allah
mashi
masrites
mass-energies
mass-energy
mass-produce
mass-produced
mass-producer
mass-producers
mass-produces
mass-producing
match-to-sample
math-anxious
matter-of-fact
matter-of-factly
matter-of-factness
matter-of-factnesses
mayenite
mayenites
mbaka
mbala
mbalakh
mbalas
mbara
mbesa
mbessa
mbila
mbilas
mboi
mboko
mbole
mbonga
mbula
mcguinnessites
me-self
me-selves
me-too
me-tooism
me-tooisms
mealy-mouthed
mean-spirited
mean-spiritedly
mean-spiritedness
mean-spiritednesses
meat-and-potatoes
meat-eater
meat-eaters
mechanosensation
mechanosensations
mechanosensing
mechanosensitive
mechanosensitivities
mechanosensitivity
mechanosensor
mechanosensors
mechanosensory
mecoprop-p
mecoprop-ps
medazepam
media-savvy
meemaw
meemaws
meet-and-greet
meet-and-greets
meet-cute
meet-cutes
meet-up
meet-ups
meeting-cute
meets-cute
mega-earthquake
mega-earthquakes
mekeo
melchiors
melpa
memaw
memaws
men-about-town
men-at-arms
men-o'-war
men-of-all-work
men-of-the-earth
men-of-the-earths
men-of-war
mendes
menma
mentsuyu
menya
meow-meow
meow-meows
mephenytoin
mephobarbital
meropenem-vaborbactam
meropenem-vaborbactams
merry-andrew
merry-andrews
merry-go-round
merry-go-rounds
mesmerisingly
mesmerizingly
meso-tetraphenylporphyrin
meso-tetraphenylporphyrins
messenger-at-arms
messengers-at-arms
met-cute
met-enkephalin
meta-analyse
meta-analysed
meta-analyses
meta-analysing
meta-analysis
meta-chlorophenylpiperazine
meta-chlorophenylpiperazines
meta-cresol
meta-cresols
meta-dichlorobenzene
meta-dichlorobenzenes
meta-emotion
meta-emotions
meta-genome
meta-genomes
meta-genomic
meta-genomics
meta-iodobenzylguanidine
meta-iodobenzylguanidines
meta-knowledge
meta-knowledges
meta-meme
meta-memes
meta-ontologies
meta-ontology
meta-optimisation
meta-optimisations
meta-optimization
meta-optimizations
meta-phenylenediamine
meta-phenylenediamines
meta-reference
meta-references
meta-transcriptome
meta-transcriptomes
meta-transcriptomic
meta-transcriptomics
meter-kilogram-second
methionine-enkephalin
methionine-enkephalins
metipranolol
metolachlor
metolachlors
metre-kilogram-second
metsulfuron
metsulfuron-methyl
metsulfuron-methyls
metsulfurons
metsulphuron
metsulphuron-methyl
metsulphuron-methyls
metsulphurons
metz
mfengu
mfengus
mgbo
mgbolizhia
mi'kmaq
mi'kmaqs
miao-yao
mic'd
micafungin
micro-electro-mechanical
micro-kjeldahl
micro-limit
micro-limits
micro-nap
micro-napping
micro-naps
micro-optimisation
micro-optimisations
micro-optimise
micro-optimised
micro-optimises
micro-optimising
micro-optimization
micro-optimizations
micro-optimize
micro-optimized
micro-optimizes
micro-optimizing
micro-opto-electro-mechanical
micro-osteoperforation
micro-osteoperforations
micro-spectrophotometers
micro-spectrophotometric
micro-spectrophotometrically
micro-spectrophotometries
micro-spectrophotometry
mid-air
mid-airs
mid-circle
mid-circles
mid-cycle
mid-cycles
mid-level
mid-on
mid-range
mid-ranges
mid-sentence
mid-shelf
mid-term
midcingulate
middle-aged
middle-ager
middle-agers
middle-class
middle-classness
middle-classnesses
middle-end
middle-endian
middle-of-the-road
middle-of-the-roader
middle-of-the-roaders
middle-of-the-roadism
middle-of-the-roadisms
midodrine
might-be
might-bes
might-have-been
might've
mightn't
miglitol
mijikenda
mild-and-bitter
mild-and-bitters
mile-a-minute
mile-a-minutes
mile-ton
mile-tons
milk-and-water
milk-and-watery
mille-feuille
mille-feuilles
mimamsas
mimosine
min-cash
min-cashes
min-entropies
min-entropy
min-max
min-maxed
min-maxes
min-maxing
min-raise
min-raised
min-raises
min-raising
mind-blowing
mind-blowingly
mind-boggling
mind-bogglingly
mind-your-own-business
mind-your-own-businesses
mini-component
mini-components
mini-crisis
mini-filament
mini-filaments
mini-map
mini-maps
mini-me
mini-mes
mini-review
mini-reviews
mipomersen
mise-en-scene
mise-en-scenes
mitmita
mitragynine
mitragynines
miwok
mix-up
mix-ups
mixe-zoque
mixe-zoquean
mixe-zoqueans
mixe-zoques
mixed-blood
mixed-bloods
mixed-endian
mixed-handedness
mixed-handednesses
mixed-integer
mixed-orientation
mixed-race
mixed-up
mkate
mkeka
mkekas
mkhedruli
mm-hm
mm-hmm
mm-kay
mmen
mo'oku'auhau
mobile-friendlinesses
mobilities-as-a-service
mobility-as-a-service
mock-up
mock-ups
model-view-controller
model-view-controllers
model-view-presenter
model-view-presenters
model-view-viewmodel
model-view-viewmodels
moganite
moganites
mohammedans
mojibake
mokele-mbembe
mokele-mbembes
mold-breaking
mom-and-pop
mom-and-pops
moms-and-pops
money-changer
money-changers
mongolites
monjayaki
month-on-month
month-over-month
moon-eyed
moor-bird
moor-birds
morogo
moru
moses-in-the-cradle
moses-on-a-raft
most-favored-nation
most-favoured-nation
moth-eaten
mother-in-law
mother-naked
mother-of-millions
mother-of-pearl
mother-of-pearls
mother-of-thousands
mother-of-thyme
mother-of-thymes
mother-of-wheat
mother-of-wheats
mothers-in-law
motte-and-bailey
mould-breaking
moules-frites
moulin-a-vent
moulin-a-vents
mound-bird
mound-birds
mound-builder
mound-builders
mountain-gem
mountain-gems
mouth-to-mouth
mouth-watering
mouth-wateringly
mpinda
mpoto
mpumalanga
mpur
mru
mrus
mscarlet-i
mscarlet-is
msemmen
msemmens
mu-law
mu-laws
mu-meson
mu-mesons
mu'adhdhin
mu'adhdhins
mu'tazilah
mu'tazilahs
mu'tazilas
mu'tazilism
mu'tazilisms
mu'tazilite
mu'tazilites
mu'umu'u
muddle-head
muddle-headed
muddle-headedness
muddle-headednesses
muddle-heads
muhajir
muki
mukimo
multi-aquifer
multi-attraction
multi-biomarker
multi-biometric
multi-biometrics
multi-cell
multi-celled
multi-hierarchical
multi-hit
multi-institutional
multi-instrumentalist
multi-instrumentalists
multi-interdisciplinary
multi-method
multi-methodological
multi-objective
multi-omics
multi-organ-on-a-chip
multi-organs-on-chips
multi-photon
multi-purpose
multi-stakeholder
multi-stakeholderism
multi-stakeholderisms
multi-stakeholders
multi-tenancies
multi-tenancy
multi-thread
multi-threaded
multi-threading
multi-threadings
multi-threads
multi-trunk
multi-trunks
mumblety-peg
mumblety-pegs
mumuye
mumuyes
mungaka
muon-antimuon
murder-suicide
murder-suicides
murmanite
murmanites
murunskites
muscle-up
muscle-ups
musician-in-residence
musicians-in-residence
must-do
must-dos
mustn't
muu-muu
muu-muus
muzzle-loaded
muzzle-loader
muzzle-loaders
muzzle-loading
mvps
mvskoke
mvskokes
mwera
mwotlap
myc-r
myc-rs
mycosubtilin
mycosubtilins
myf
myofiber
myofibers
myriad-minded
mzungu
n-acetyl-aspartyl-glutamate
n-acetyl-aspartyl-glutamates
n-acetyl-beta-d-glucosaminidase
n-acetyl-beta-d-glucosaminidases
n-acetyl-d-alanine
n-acetyl-d-alanines
n-acetyl-d-galactosamine
n-acetyl-d-galactosamines
n-acetyl-d-glucosamine
n-acetyl-d-glucosamines
n-acetyl-d-mannosamine
n-acetyl-d-mannosamines
n-acetyl-l-aspartate
n-acetyl-l-aspartates
n-acetyl-l-cysteine
n-acetyl-l-cysteines
n-acetyl-l-leucine
n-acetyl-l-leucines
n-acetyl-l-methionine
n-acetyl-l-methionines
n-acetyl-l-phenylalanine
n-acetyl-l-phenylalanines
n-acetyl-l-tryptophan
n-acetyl-l-tryptophans
n-acetyl-l-tyrosine
n-acetyl-l-tyrosines
n-acetyl-seryl-aspartyl-lysyl-proline
n-acetyl-seryl-aspartyl-lysyl-prolines
n-acetylaspartate
n-acetylaspartates
n-acetylate
n-acetylated
n-acetylates
n-acetylating
n-acetylation
n-acetylations
n-acetylchitooligosaccharide
n-acetylchitooligosaccharides
n-acetylcysteine
n-acetylcysteines
n-acetylgalactosamine
n-acetylgalactosamines
n-acetylgalactosaminyltransferase
n-acetylgalactosaminyltransferases
n-acetylglucosamine
n-acetylglucosamines
n-acetylglucosaminyltransferase
n-acetylglucosaminyltransferases
n-acetylglutamate
n-acetylglutamates
n-acetylmuramyl-l-alanyl-d-isoglutamine
n-acetylmuramyl-l-alanyl-d-isoglutamines
n-acetylphenylalanine
n-acetylphenylalanines
n-acetylserotonin
n-acetylserotonins
n-acetyltransferase
n-acetyltransferases
n-acetyltryptophan
n-acetyltryptophans
n-acyl-phosphatidylethanolamine
n-acyl-phosphatidylethanolamines
n-acylhydrazone
n-acylhydrazones
n-acylphosphatidylethanolamine
n-acylphosphatidylethanolamines
n-adic
n-alkylation
n-alkylations
n-allylnormetazocine
n-allylnormorphine
n-arachidonoylethanolamine
n-arachidonoylethanolamines
n-ary
n-arylation
n-arylations
n-asparagine
n-asparagines
n-ball
n-balls
n-benzoyl-n-phenylhydroxylamine
n-benzoyl-n-phenylhydroxylamines
n-benzylaniline
n-benzylanilines
n-benzylidenebenzylamine
n-benzylidenebenzylamines
n-butane
n-butanes
n-butyl
n-butylamine
n-butylamines
n-butyldeoxynojirimycin
n-butyls
n-cadherin
n-cadherins
n-chain
n-chains
n-decane
n-decanes
n-desmethylclozapine
n-desmethylclozapines
n-desmethyldiazepam
n-desmethyltamoxifen
n-desmethyltamoxifens
n-diethylnitrosamines
n-dimensional
n-dimensionalities
n-dimensionality
n-dodecanol
n-dodecanols
n-ethyl
n-ethyl-n-nitrosourea
n-ethyl-n-nitrosoureas
n-ethylcarbazole
n-ethylmaleimide
n-ethylmaleimides
n-ethyls
n-fixing
n-fluorobenzenesulfonimide
n-fluorobenzenesulfonimides
n-fluorobenzenesulphonimide
n-fluorobenzenesulphonimides
n-formyl-l-methionyl-l-leucyl-l-phenylalanine
n-formyl-methionyl-leucyl-phenylalanine
n-formyl-methionyl-leucyl-phenylalanines
n-formylmorpholine
n-formylmorpholines
n-glycoside
n-glycosides
n-glycosidic
n-gon
n-gonal
n-gons
n-gram
n-grams
n-graph
n-graphs
n-heptane
n-heptanes
n-heterocycle
n-heterocycles
n-heterocyclic
n-heterocyclisation
n-heterocyclisations
n-heterocyclization
n-heterocyclizations
n-hexacosane
n-hexacosanes
n-hexadecane
n-hexadecanes
n-hexane
n-hexanes
n-hydroxylation
n-hydroxylations
n-hydroxyphthalimide
n-hydroxyphthalimides
n-hydroxysuccinimide
n-hydroxysuccinimides
n-isopropylacrylamide
n-isopropylacrylamides
n-link
n-manifold
n-manifolds
n-methyl-d-aspartates
n-methyl-n-nitrosourea
n-methyl-n-nitrosoureas
n-methylacetamide
n-methylacetamides
n-methylalanine
n-methylalanines
n-methylamphetamine
n-methylaniline
n-methylanilines
n-methylformamide
n-methylformamides
n-methylhistamine
n-methylhistamines
n-methylmorpholine
n-methylmorpholines
n-methylpiperidine
n-methylpiperidines
n-methylpyrrolidine
n-methylpyrrolidines
n-methylpyrrolidone
n-methylpyrrolidones
n-methyltransferase
n-methyltransferases
n-methyltryptamine
n-methyltryptamines
n-myc
n-mycs
n-myristoyltransferase
n-myristoyltransferases
n-nitrosamine
n-nitrosamines
n-nitrosation
n-nitrosations
n-nitroso-n-methylurea
n-nitroso-n-methylureas
n-nitrosodi-n-butylamine
n-nitrosodi-n-butylamines
n-nitrosodibutylamine
n-nitrosodibutylamines
n-nitrosodiethanolamine
n-nitrosodiethanolamines
n-nitrosodiethylamine
n-nitrosodiethylamines
n-nitrosodimethylamine
n-nitrosodimethylamines
n-nitrosomethylethylamine
n-nitrosomethylethylamines
n-nitrosopyrrolidine
n-nitrosopyrrolidines
n-nonadecane
n-nonadecanes
n-nonane
n-nonanes
n-octane
n-octanes
n-oleoylethanolamide
n-oleoylethanolamides
n-oleoylethanolamine
n-oleoylethanolamines
n-palmitoylethanolamine
n-palmitoylethanolamines
n-pentane
n-pentanes
n-phenyl-p-phenylenediamine
n-phenyl-p-phenylenediamines
n-phenylbenzamide
n-phenylbenzamides
n-phenylbenzylamine
n-phenylbenzylamines
n-phenylglycine
n-phenylglycines
n-phenylhydroxylamine
n-phenylhydroxylamines
n-phenylmaleimide
n-phenylmaleimides
n-phosphonomethylglycine
n-phosphonomethylglycines
n-process
n-processes
n-propane
n-propanes
n-propyl
n-propylamine
n-propylamines
n-propyls
n-ras
n-rases
n-ray
n-rays
n-retinylidene-n-retinylethanolamine
n-retinylidene-n-retinylethanolamines
n-sphere
n-spheres
n-src
n-srcs
n-sulfonylurea
n-terminal
n-terminals
n-termini
n-terminus
n-terminuses
n-tert-butyl-alpha-phenylnitrone
n-tert-butyl-alpha-phenylnitrones
n-tetradecane
n-tetradecanes
n-tier
n-tuple
n-tuples
n-vector
n-vectors
n-word
n-words
n'dama
n'golo
n'ko
na'vi
nab-paclitaxel
nafcillin
nakanai
nakwi
nalfurafine
nalik
naltriben
naltrindole
naltrindoles
namby-pambies
namby-pamby
name-calling
name-callings
name-check
name-checked
name-checking
name-checks
name-drop
name-dropped
name-dropper
name-droppers
name-dropping
name-droppings
name-drops
nano-bio-technologies
nano-biotechnological
nano-electro-mechanical
nano-hydroxyapatite
nano-hydroxyapatites
nano-opto-electro-mechanical
nantes
nantucket
nap-of-the-earth
naphtholates
narco-pentecostalisms
narco-state
narco-states
narrow-minded
narrow-mindedly
narrow-mindedness
narrow-mindednesses
naskapi
naso-orbito-ethmoidal
nasta'liq
nation-state
nation-states
native-hen
native-hens
natrite
natrites
natrosilites
natur-philosophie
natur-philosophien
nauna
nda'nda'
ndai
ndaka
ndam
ndambomo
ndani
ndasa
ndemli
ndendeule
ndengereko
ndolo
ndom
ndombe
ndonga
ndunda
ndunga
ndwandwe
ndyuka
ndyukas
ne'er
ne'er-do-weel
ne'er-do-weels
ne'er-do-well
ne'er-do-wells
ne'ertheless
near-close
near-death
near-deaths
near-ring
near-rings
neck-rein
neck-reined
neck-reining
neck-reins
needn't
neighborite
neighborites
nelarabine
nenets
nengone
neo-avant-garde
neo-baroque
neo-dada
neo-dadaism
neo-dadaisms
neo-dadaist
neo-dadaists
neo-dadas
neo-darwinism
neo-darwinisms
neo-feudal
neo-feudalism
neo-feudalisms
neo-feudalist
neo-feudalists
neo-freudianism
neo-freudianisms
neo-functionalisation
neo-functionalisations
neo-functionalization
neo-functionalizations
neo-impressionism
neo-impressionisms
neo-institutionalisms
neo-kaleckian
neo-kaleckians
neo-kantian
neo-kantianism
neo-kantianisms
neo-kantians
neo-keynesian
neo-keynesians
neo-kraepelinian
neo-kraepelinians
neo-malthusian
neo-malthusianism
neo-malthusianisms
neo-malthusians
neo-marxism
neo-marxisms
neo-marxist
neo-marxists
neo-melanesian
neo-nationalism
neo-nationalisms
neo-nationalist
neo-nationalists
neo-nazi
neo-nazis
neo-nazism
neo-nazisms
neo-osteogeneses
neo-osteogenesis
neo-panamax
neo-pentane
neo-pentanes
neo-piagetian
neo-piagetians
neo-pythagorean
neo-pythagoreanism
neo-pythagoreanisms
neo-pythagoreans
neo-scholastic
neo-scholasticism
neo-scholasticisms
neoadjuvant
neoantigen
neoantigens
neobladder
neobladders
neocarzinostatin
neohesperidindihydrochalcones
neolites
neonatorum
neopros
nerolidol
nerolidols
nerve-racking
nerve-wracking
neryl
neryls
networking-as-a-service
networkings-as-a-service
networks-as-a-service
neuro-fuzzy
neuro-ophthalmologic
neuro-ophthalmological
neuro-ophthalmologies
neuro-ophthalmologist
neuro-ophthalmologists
neuro-ophthalmology
never-before-seen
never-ending
never-was
never-weres
nevi'im
new-fashioned
newton-metre
newton-metres
next-door
next-gen
next-generation
nfs
nga'ka
ngaju
ngam
ngambay
ngangam
ngarigo
ngarluma
ngbundu
ngie
ngiemboon
ngindo
ngizim
ngwe
nice-looking
nicer-looking
nicest-looking
nick-nack
nick-nacks
nickel-and-dime
nickel-and-dimed
nickel-and-dimes
nickel-and-diming
nickel-iron
nickel-irons
nickeled-and-dimed
nickeling-and-diming
nickels-and-dimes
niclosamide
niger-congo
night-light
night-lights
nightingale-thrush
nightingale-thrushes
nihali
nihon-ga
nihon-gas
nii
nikkei-jin
nikkei-jins
nilo-saharan
nilo-saharans
nimetazepam
nimzo-indian
nimzo-indians
ninety-eight
ninety-eighth
ninety-eighths
ninety-eights
ninety-fifth
ninety-fifths
ninety-first
ninety-firsts
ninety-five
ninety-fives
ninety-four
ninety-fours
ninety-fourth
ninety-fourths
ninety-nine
ninety-nines
ninety-ninth
ninety-ninths
ninety-one
ninety-ones
ninety-second
ninety-seconds
ninety-seven
ninety-sevens
ninety-seventh
ninety-sevenths
ninety-six
ninety-sixes
ninety-sixth
ninety-sixths
ninety-third
ninety-thirds
ninety-three
ninety-threes
ninety-two
ninety-twos
ninongs
nipped-b
nipped-bs
nirmatrelvir-ritonavir
nisga'a
nitisinone
nitrification-denitrification
nitrification-denitrifications
nitty-gritties
nitty-gritty
nivkh
njebi
njen
njerep
nkami
nkongho
nkonya
nkutu
nlaka'pamux
nnam
no-brainer
no-brainers
no-go
no-goes
no-good
no-goodnik
no-goodniks
no-goods
no-gos
no-hoper
no-hopers
no-life
no-lifed
no-lifer
no-lifers
no-lifes
no-lifing
no-lives
no-name
no-names
no-no
no-nonsense
no-nos
no-scope
no-scoped
no-scopes
no-scoping
no-see-um
no-see-ums
no-show
no-shows
nobiin
nocodazole
nodularin-r
nodularin-rs
noetherian
noise-cancelling
nokotas
nolanite
nolanites
nominative-accusative
non-agricultural
non-alcoholic
non-alcoholics
non-apologies
non-apology
non-aquatic
non-aqueous
non-archimedean
non-aristocratic
non-asymptotic
non-asymptotically
non-atopic
non-attributable
non-authoritarian
non-availability
non-bankruptcies
non-bearing
non-belligerence
non-belligerences
non-belligerency
non-belligerents
non-benzodiazepine
non-benzodiazepines
non-binary
non-biodegradabilities
non-biodegradability
non-biodegradable
non-carbohydrate
non-carcinogenic
non-chalcedonian
non-chalcedonians
non-cis
non-cisgender
non-classroom
non-classrooms
non-cognitivism
non-cognitivisms
non-cognitivist
non-cognitivists
non-combustible
non-comedogenic
non-commissioned
non-communicable
non-communicative
non-compositional
non-comprehending
non-con
non-concentrated
non-confidential
non-configurationalities
non-configurationality
non-cons
non-consecutively
non-consensually
non-consent
non-consenting
non-consents
non-consequentialisms
non-consequentialists
non-conservative
non-constructive
non-contextuality
non-continuous
non-contradiction
non-contributing
non-contributory
non-controversial
non-cooperations
non-coplanarities
non-dance
non-dances
non-dealer
non-dealers
non-denominational
non-departmental
non-dependent
non-dependents
non-depositional
non-depreciating
non-desarguesian
non-deterministic
non-deterministically
non-differentiabilities
non-differentiability
non-differentiable
non-differential
non-dimensionalisation
non-dimensionalisations
non-dimensionalise
non-dimensionalization
non-dimensionalizations
non-dimensionalize
non-directivities
non-disciplinary
non-discrimination
non-discriminatory
non-disjunctions
non-documentaries
non-earthquake
non-ecclesiastical
none-so-pretties
none-so-pretty
nor'easters
nor'westers
nordazepam
nordiazepam
normochromic
normoxia
normoxias
normoxic
north-northeast
north-northeasterlies
north-northeasts
north-northwest
north-northwesterlies
north-northwests
not-for-profits
not-me
noth-ing
noth-ings
now-time
now-times
now's
np-complete
np-completeness
np-completenesses
np-hard
np-hardness
np-hardnesses
nsenga
nso'
nubians
nudie-cutie
nudie-cuties
nuh
nuh-uh
null-space
null-spaces
nulligravida
nulligravidas
nunggubuyu
nurse-midwife
nurse-midwiferies
nurse-midwifery
nurse-midwives
nushu
nuu-chah-nulth
nyah-nyah
nyah-nyahed
nyah-nyahing
nyah-nyahs
nyakyusa
nyam
nyambo
nyankole
nyayas
nyika
nyungwe
o-acetylserine
o-acetylserines
o-be-joyful
o-be-joyfuls
o-benzoquinone
o-benzoquinones
o-benzylhydroxylamine
o-benzylhydroxylamines
o-benzyne
o-benzynes
o-chloronitrobenzene
o-chloronitrobenzenes
o-chlorophenol
o-chlorophenols
o-chlorotoluene
o-chlorotoluenes
o-cresol
o-cresolphthalein
o-cresolphthaleins
o-cresols
o-dealkylation
o-dealkylations
o-desmethyltramadol
o-desmethyltramadols
o-desmethylvenlafaxines
o-dibromobenzene
o-dibromobenzenes
o-ethylphenol
o-ethylphenols
o-glycoside
o-glycosides
o-hydroxyacetophenone
o-hydroxyacetophenones
o-hydroxybenzyl
o-hydroxybenzyls
o-link
o-mannosyltransferase
o-mannosyltransferases
o-methylation
o-methyltransferase
o-methyltransferases
o-module
o-modules
o-nitrobenzaldehyde
o-nitrobenzaldehydes
o-nitrochlorobenzene
o-nitrochlorobenzenes
o-nitrophenol
o-nitrophenols
o-o
o-o-aa
o-o-aas
o-os
o-phenylenediamine
o-phenylenediamines
o-phosphorylethanolamine
o-phosphorylethanolamines
o-phosphoserine
o-phosphoserines
o-phthalaldehyde
o-phthalaldehydes
o-phthalaldialdehyde
o-phthalaldialdehydes
o-quinodimethane
o-quinodimethanes
o-substitution
o-substitutions
o-terphenyl
o-terphenyls
o-tolualdehyde
o-tolualdehydes
o-toluidine
o-toluidines
o-xylene
o-xylenes
o-xylose
o-xyloses
o-xylylene
o-xylylenes
o'clock
o'er
o'nyong-nyong
o'nyong-nyongs
o'o
o'odham
o'odhams
oak-leaf
oak-leaves
ob-gyn
ob-gyns
obacunone
obatoclax
obedients
obsessive-compulsive
obsessive-compulsiveness
obsessive-compulsivenesses
obsessive-compulsives
obstetric-gynaecologic
obstetric-gynaecological
obstetric-gynecologic
obstetric-gynecological
obstetrical-gynaecological
obstetrical-gynecological
obstetrician-gynaecologist
obstetrician-gynaecologists
obstetrician-gynecologist
obstetrician-gynecologists
obstetrics-gynaecologies
obstetrics-gynaecology
obstetrics-gynecologies
obstetrics-gynecology
oceanians
ocinaplon
octree
octrees
octynes
odds-on
odonto-stomatological
odronextamab
oeil-de-boeuf
oeils-de-boeuf
off-center
off-centre
off-color
off-colored
off-colour
off-coloured
off-dry
off-field
off-glide
off-glides
off-grid
off-gridder
off-gridders
off-key
off-kilter
off-license
off-licenses
off-limits
off-line
off-minded
off-peak
off-piste
off-putting
off-puttingly
off-ramp
off-ramps
off-sale
off-screen
off-season
off-seasons
off-site
off-slip
off-slips
off-speed
off-spin
off-spinning
off-spins
off-the-grid
off-the-shelf
off-the-shoulder
off-the-wall
off-white
off-whites
officer-in-residence
officers-in-residence
offretite
offretites
ogbia
ogbono
oh-oh
oh-so
ohagi
ohagis
ohlone
ohlones
ok'd
ok'ing
ok's
okada
okadas
okaite
okaites
okinawan
okinawans
okpe
okpella
oku
ol'
olanzapine-fluoxetine
old-fashioned
old-fashionedly
old-fashionedness
old-fashionednesses
old-fashioneds
old-man-and-woman
old-man-in-the-spring
old-men-in-the-spring
old-time
old-timer
old-timers
old-times
old-timey
oldsite
oldsites
oleamide
olenite
olenites
oleo-pneumatic
oleoyl-estrone
oleoylethanolamides
oleoyls
oleuropein
oleuropeins
olezarsen
olivopontocerebellar
oltipraz
omarigliptin
omega-conotoxin
omega-conotoxins
omega-oxidation
omega-oxidations
on-demand
on-line
on-ramp
on-ramps
on-site
on-slip
on-slips
on-the-job
on-year
once-over
once-overs
oncofertilities
oncofertility
oncoimmunological
oncoimmunologically
oncoimmunologies
oncoimmunology
oncometabolic
oncometabolite
oncometabolites
onde-onde
ondeh-ondeh
one-and-done
one-dimensional
one-dimensionalities
one-dimensionality
one-dimensionally
one-eighties
one-eighty
one-eyed
one-holer
one-holers
one-hundred-percenter
one-hundred-percenters
one-hundred-percentism
one-hundred-percentisms
one-idea'd
one-ideaed
one-liner
one-liners
one-off
one-offs
one-on-one
one-on-ones
one-outer
one-outers
one-piece
one-pieces
one-shot
one-shots
one-shotted
one-shotting
one-sided
one-sidedly
one-sidedness
one-sidednesses
one-size-fits-most
one-sphere
one-spheres
one-star
one-time
one-to-one
one-up
one-upmanship
one-upmanships
one-upped
one-upping
one-ups
one-upsmanship
one-upsmanships
one-way
one-ways
one's
onychodystrophies
onychodystrophy
onychogryphosis
onychomatricoma
onychomatricomas
onychomatricomata
onychotillomania
onychotillomanias
ooh-la-la
oops-a-daisy
op-ed
op-eds
open-air
open-and-shut
open-ended
open-endedness
open-endednesses
open-label
open-letter
open-minded
open-mindedly
open-mindedness
open-mindednesses
open-necked
open-source
opera-ballet
opera-ballets
opera-comique
operas-ballets
operas-comiques
opocephali
oprelvekin
opt-in
opt-ins
opt-out
opt-outs
opticianries
opticianry
orang-utan
orang-utans
orbito-frontal
orexin-a
orexin-as
orexin-b
orexin-bs
orforglipron
organo-montmorillonite
organo-montmorillonites
oritavancin
oromos
orotate
orotated
orotatephosphoribosyltransferase
orotates
ortho-benzyne
ortho-benzynes
ortho-chlorophenol
ortho-chlorophenols
ortho-chlorotoluene
ortho-chlorotoluenes
ortho-cresol
ortho-cresols
ortho-dichlorobenzene
ortho-dichlorobenzenes
ortho-k
ortho-ks
ortho-nitrobenzaldehyde
ortho-nitrobenzaldehydes
ortho-phenylenediamine
ortho-phenylenediamines
ortho-phthalaldehyde
ortho-phthalaldehydes
ortho-quinodimethane
ortho-quinodimethanes
ortho-terphenyl
ortho-terphenyls
ortho-toluidine
ortho-toluidines
ortho-xylene
ortho-xylenes
oshindonga
ossau-iraty
ossau-iratys
osteo-odonto-keratoprostheses
osteo-odonto-keratoprosthesis
otak-otak
otavite
otavites
other-directed
other-directedness
other-directednesses
other-worldliness
other-worldlinesses
other-worldly
otoe-missouria
otokonokos
otomanguean
otoprotectant
otrovert
otroverts
ottawan
ottawans
ought-to-be
ought-to-bes
ought-to-do
ought-to-dos
oughtn't
out-and-out
out-and-outer
out-and-outers
out-group
out-groups
out-of-body
out-of-bounds
out-of-date
out-of-door
out-of-doors
out-of-school
out-of-sight
out-of-the-way
out-year
out-years
outward-looking
ovalene
ovalenes
over-intellectualisation
over-intellectualisations
over-intellectualised
over-intellectualises
over-intellectualising
over-intellectualization
over-intellectualizations
over-intellectualized
over-intellectualizes
over-intellectualizing
over-reliance
over-reliances
over-relied
over-relies
over-rely
over-relying
over-the-counter
over-the-top
over-the-topness
over-the-topnesses
over-unity
oviedo
ovomucin
ovomucins
owlet-nightjar
owlet-nightjars
oxalosuccinate
oxidation-reduction
oxidation-reductions
oxo-biodegradable
oxo-degradable
oxotremorine-m
oxotremorine-ms
oxymercuration-demercuration
oxymercuration-demercurations
oyelites
ozone-friendly
p-adic
p-aminohippurate
p-azoxyanisole
p-azoxyanisoles
p-benzyne
p-benzynes
p-brane
p-branes
p-bromoaniline
p-bromoanilines
p-cadherin
p-cadherins
p-chloro-m-cresol
p-chloro-m-cresols
p-chloromercuribenzoate
p-chloromercuribenzoates
p-chloronitrobenzene
p-chloronitrobenzenes
p-chlorophenylalanine
p-chlorophenylalanines
p-code
p-codes
p-complete
p-completeness
p-completenesses
p-cresol
p-cresols
p-cymene
p-cymenes
p-dimethylaminoazobenzene
p-dimethylaminoazobenzenes
p-dimethylaminobenzaldehyde
p-dimethylaminobenzaldehydes
p-divinylbenzene
p-ethylphenol
p-ethylphenols
p-fluorophenylalanine
p-fluorophenylalanines
p-glycoprotein
p-glycoproteins
p-graph
p-graphs
p-hack
p-hacked
p-hacking
p-hackings
p-hacks
p-hydroxyacetophenone
p-hydroxyacetophenones
p-hydroxybenzaldehyde
p-hydroxybenzaldehydes
p-hydroxybenzyl
p-hydroxybenzyls
p-hydroxyphenylpyruvate
p-hydroxyphenylpyruvates
p-matrices
p-matrix
p-nitroaniline
p-nitroanilines
p-nitrobenzoate
p-nitrobenzoates
p-nitrochlorobenzene
p-nitrochlorobenzenes
p-nitrophenol
p-nitrophenols
p-nitrophenylphosphate
p-nitrophenylphosphates
p-nitrosophenol
p-nitrosophenols
p-norm
p-norms
p-orbital
p-orbitals
p-phenetidine
p-phenetidines
p-phenylenediamine
p-phenylenediamines
p-polarisation
p-polarisations
p-polarised
p-polarization
p-polarizations
p-polarized
p-quinodimethane
p-quinodimethanes
p-selectin
p-selectins
p-substitution
p-substitutions
p-terphenyl
p-terphenyls
p-tert-butyl
p-tert-butyls
p-toluenesulfonamide
p-toluenesulfonamides
p-toluenesulfonate
p-toluenesulfonates
p-toluenesulphonate
p-toluenesulphonates
p-trap
p-traps
p-value
p-values
p-xylene
p-xylenes
p-xylylene
p-xylylenediamine
p-xylylenediamines
p-xylylenes
p-zombie
p-zombies
pa'anga
pa'angas
pa'o
pa'os
paarites
pacceka-buddha
pacceka-buddhas
paid-up
painted-snipe
painted-snipes
pakhavajes
pakhawajes
palaeo-oceanic
palaeo-oceanographic
palaeo-oceanographies
palaeo-oceanography
pale-faced
paleo-oceanic
paleo-oceanographic
paleo-oceanographies
paleo-oceanography
paltusotine
pama-nyungan
pamidronate
pan-fried
pan-fries
pan-fry
pan-frying
pan-sear
pan-seared
pan-searing
pan-sears
pan-slavic
pan-slavism
pan-slavisms
pan-slavist
pan-slavists
panekuk-panekuk
paolovite
paolovites
papel
papels
papier-mache
para-benzyne
para-benzynes
para-chlorophenylalanine
para-chlorophenylalanines
para-cresol
para-cresols
para-dichlorobenzenes
para-dimethylaminobenzaldehyde
para-dimethylaminobenzaldehydes
para-methoxyamphetamine
para-methoxyamphetamines
para-nitrophenylphosphate
para-nitrophenylphosphates
para-phenylenediamine
para-phenylenediamines
para-substituent
para-substituents
para-substituted
para-substitution
para-substitutions
para-terphenyl
parent-in-law
pari-mutuel
pari-mutuels
paris-mutuels
parkerite
parkerites
parkinson's
parley-voo
parley-vooed
parley-vooing
parley-voos
part-score
part-scores
part-song
part-songs
part-time
part-timer
part-timers
passe-partout
passe-partouts
passer-by
passers-by
paste-up
paste-ups
path-connected
path-connectedness
path-connectednesses
paticca-samuppada
paticca-samuppadas
pawaia
pawrent
pawrents
pay-as-you-earn
pay-as-you-go
pay-as-you-please
pay-as-you-will
pay-as-you-wish
pay-for-play
pay-per-view
pay-per-views
pay-to-play
pay-to-view
pay-to-views
pay-what-you-can
pay-what-you-feel
pay-what-you-like
pay-what-you-want
pay-what-you-will
pay-what-you-wish
payabilities
payablenesses
payao
payaos
payments-as-a-service
payrolls-as-a-service
pea-green
pea-souper
pea-soupers
peach-coloured
peacock-pheasant
peacock-pheasants
pearceite-polybasites
peat-reek
peat-reeks
pee-pee
pee-peed
pee-peeing
pee-pees
peepaw
peepaws
peer-to-peer
pell-mell
pellitories-of-the-wall
pellitory-of-the-wall
pelog
pempek-pempek
pen-and-ink
pen-and-inks
pen-and-paper
penbutolol
pende
penny-farthing
penny-farthings
penny-pinching
pent-up
people-first
pepes-pepes
pepper-and-salt
peramivir
pergolide
peri-implantation
peri-implantations
peri-implantites
peri-implantitides
peri-implantitis
perkedel-perkedel
perlialite
perugia
perylene
pesh-kabz
peskotomuhkati-wolastoqey
pfalz-ardenner
pfalz-ardenners
phags-pa
pharmacist-in-charge
pharmacists-in-charge
pharmaco-electroencephalographies
pharmaco-electroencephalography
phi-coefficient
phi-coefficients
phishing-as-a-service
phishings-as-a-service
phone-in
phone-ins
phospho-acceptor
phospho-acceptors
photo-cross-link
photo-cross-linked
photo-cross-linker
photo-cross-linkers
photo-cross-links
photo-crosslink
photo-crosslinked
photo-crosslinker
photo-crosslinkers
photo-crosslinks
phuket
phuthi
phuthis
physician-in-training
physician-investigator
physician-investigators
physician-scientist
physician-scientists
physicians-in-training
pi-conjugated
pianississimi
pianississimos
pianists-in-residence
pibrentasvir
pick-and-mix
pick-me
pick-me-up
pick-me-ups
pick-mes
pick-up
pick-ups
picker-up
picker-upper
picker-uppers
picker-ups
pie-in-the-sky
pied-piping
pied-pipings
pien-tze-huang
piggy-back
piggy-backed
piggy-backing
piggy-backs
pile-up
pile-ups
pillararene
pillararenes
pilsenite
pilsenites
pin-table
pin-tables
pin-up
pin-ups
pince-nez
pinch-hit
pinch-hits
pinch-hitter
pinch-hitters
pinch-hitting
ping-pong
ping-ponged
ping-ponging
ping-pongs
pink-collar
piperacillin-tazobactam
piperacillin-tazobactams
pirc
pircs
pistol-whip
pistol-whipped
pistol-whipping
pistol-whips
pitch-and-toss
pitch-and-tosses
pitch-black
pitch-blackness
pitch-blacknesses
pitch-dark
pitter-patter
pitter-pattered
pitter-pattering
pitter-patters
pixie-bob
pixie-bobs
place-name
place-names
platform-as-a-service
platforms-as-a-service
play-act
play-acted
play-acting
play-actor
play-actors
play-acts
play-off
play-offs
played-out
pleasantness-unpleasantness
pleasantness-unpleasantnesses
pleasure-pain
pleasure-pains
plethysmometer
plethysmometers
plug-in
plug-ins
plug-ugly
pnar
po-po
po-pos
point-and-click
point-blank
poison-oak
poison-oaks
polarite
polarites
pom-pom
pom-poms
pont-l'eveque
pont-l'eveques
poo-poo
poo-pooed
poo-pooer
poo-pooers
poo-pooing
poo-poos
pooh-pooh
pooh-poohed
pooh-pooher
pooh-poohers
pooh-poohing
pooh-poohs
poop-head
poop-heads
pooper-scooper
pooper-scoopers
pooron
poorons
poors
pop-up
pop-ups
porte-crayon
porte-crayons
porte-monnaie
porte-monnaies
post-anarchism
post-anarchisms
post-anarchist
post-anarchists
post-apocalyptic
post-baccalaureate
post-baccalaureates
post-baptismal
post-blackness
post-blacknesses
post-britpop
post-christendoms
post-christian
post-christianity
post-cinematic
post-circumcision
post-colonial
post-colonialism
post-colonialisms
post-colonialist
post-colonialists
post-colonials
post-combustion
post-common
post-commons
post-communion
post-communions
post-communism
post-communisms
post-communist
post-communists
post-contemporary
post-depositional
post-einsteinian
post-grunge
post-hardcore
post-hospitalisation
post-hospitalization
post-human
post-humanism
post-humanisms
post-humanist
post-humanists
post-humans
post-ictal
post-infection
post-infections
post-infectious
post-internet
post-islamism
post-islamisms
post-judgement
post-judgment
post-keratoplasty
post-keynesian
post-left
post-leftist
post-leftists
post-lockdown
post-minimalism
post-minimalisms
post-minimalist
post-minimalists
post-neoadjuvant
post-nominal
post-nominals
post-normal
post-oedipal
post-op
post-operation
post-ops
post-panamax
post-pandemic
post-polio
post-poliomyelitis
post-politics
post-postmodern
post-postmodernism
post-postmodernisms
post-postmodernist
post-postmodernists
post-punk
post-punks
post-pyloric
post-rock
post-romantic
post-romanticism
post-romanticisms
post-socialism
post-socialisms
post-socialist
post-structural
post-structuralism
post-structuralisms
post-structuralist
post-structuralists
post-synchronisations
post-synchronizations
post-tetanic
pot-au-feu
pot-limit
potarite
potarites
potassic-hastingsites
potsdam
potty-chair
potty-chairs
pouilly-fuisse
pouilly-fuisses
pouilly-fume
pouilly-fumes
pouligny-saint-pierre
pousse-cafe
pousse-cafes
povidone-iodine
povidone-iodines
pow-wow
pow-wowed
pow-wowing
pow-wows
power-by-wire
power-dive
power-dived
power-dives
power-diving
power-dove
power-driven
power-knowledge
power-knowledges
power-up
power-ups
practico-inert
practitioner-in-residence
practitioners-in-residence
pralmorelin
pratitya-samutpada
pratitya-samutpadas
pratyeka-buddha
pratyeka-buddhas
pre-anaesthetic
pre-anesthetic
pre-approved
pre-arraignment
pre-auth
pre-authorisation
pre-authorisations
pre-authorise
pre-authorised
pre-authorises
pre-authorising
pre-authorization
pre-authorizations
pre-authorize
pre-authorized
pre-authorizes
pre-authorizing
pre-auths
pre-boarding
pre-book
pre-booked
pre-booking
pre-books
pre-calculi
pre-calculus
pre-calculuses
pre-came
pre-check-in
pre-check-ins
pre-cum
pre-cummed
pre-cumming
pre-cums
pre-dominant
pre-dreadnought
pre-dreadnoughts
pre-earthquake
pre-ejaculate
pre-electronic
pre-empt
pre-empted
pre-empting
pre-emption
pre-emptions
pre-emptive
pre-emptively
pre-empts
pre-erythrocytic
pre-flop
pre-hook
pre-ictal
pre-image
pre-images
pre-interview
pre-k
pre-keynesian
pre-keynesians
pre-kindergarten
pre-kindergartens
pre-knowledge
pre-known
pre-lab
pre-labs
pre-lockdown
pre-marxian
pre-marxist
pre-nominal
pre-nominals
pre-oedipal
pre-op
pre-operation
pre-ops
pre-owned
pre-pandemic
pre-prepare
pre-prepared
pre-prepares
pre-preparing
pre-proto-indo-european
pre-proto-indo-europeans
pre-raphaelite
pre-raphaelites
pre-raphaelitism
pre-raphaelitisms
pre-record
pre-recorded
pre-recording
pre-records
pre-release
pre-released
pre-releases
pre-releasing
pre-sale
pre-sales
pre-slaughter
pre-smoked
pre-spawn
pre-spawns
pre-surgery
pre-surgical
prekallikrein
prekallikreins
prekese
prenominals
prewind
price-fixing
price-fixings
priderite
priderites
prie-dieu
prie-dieus
prie-dieux
prince-archbishopric
prince-archbishoprics
prince-bishopric
prince-bishoprics
principal-in-residence
principals-in-residence
privacies-as-a-service
pro-aging
pro-am
pro-ams
pro-choice
pro-choicer
pro-choicers
pro-circumcision
pro-democracy
pro-democrat
pro-democratic
pro-democrats
pro-dom
pro-domme
pro-dommes
pro-doms
pro-life
pro-lifeism
pro-lifeisms
pro-lifer
pro-lifers
pro-opiomelanocortins
pro-vaxxer
pro-vaxxers
producer-in-residence
producers-in-residence
professional-in-residence
professionals-in-residence
professor-in-residence
professors-in-residence
pseudo-acronym
pseudo-acronyms
pseudo-anglicism
pseudo-anglicisms
pseudo-anonymisation
pseudo-anonymisations
pseudo-anonymities
pseudo-anonymity
pseudo-anonymization
pseudo-anonymizations
pseudo-arabic
pseudo-arc
pseudo-archaeological
pseudo-archaeologies
pseudo-archaeology
pseudo-archaic
pseudo-archeological
pseudo-archeologies
pseudo-archeology
pseudo-arcs
pseudo-autobiographical
pseudo-autobiographies
pseudo-autobiography
pseudo-catholic
pseudo-character
pseudo-characters
pseudo-color
pseudo-colors
pseudo-colour
pseudo-coloured
pseudo-colours
pseudo-complement
pseudo-complementation
psy-op
psy-ops
psy-trance
psy-trances
psy-war
psy-wars
psych-out
psych-outs
psycho-aesthetic
psycho-aesthetics
psycho-educational
psycho-emotional
psycho-esthetic
psycho-esthetics
psycho-logic
psycho-logics
psycho-moral
psycho-oncologic
psycho-oncological
psycho-oncologies
psycho-oncologist
psycho-oncologists
psycho-oncology
psycho-philosophical
ptilolite
ptilolites
pu-erh
pu-erhs
pub-sub
publish-subscribe
pubococcygeus
puligny-montrachet
puligny-montrachets
pull-in
pull-ins
pull-up
pull-ups
pump-action
pump-and-dump
pump-and-dumps
pump-fake
pump-faked
pump-fakes
pump-faking
punch-up
punch-ups
punk-pop
pupusa
pupusas
pure-hearted
pure-heartedness
pure-heartednesses
push-bike
push-biked
push-bikes
push-biking
push-button
push-buttons
push-up
push-ups
pussy-whip
pussy-whipped
pussy-whipping
pussy-whips
put-and-take
put-on
put-ons
put-up
put-you-up
put-you-ups
pyochelin
pyochelins
pyoverdine
pyoverdines
pyraclostrobin
pyridyls
pyrrolizidinealkaloidoses
q-algebra
q-algebras
q-analog
q-analogs
q-analogue
q-analogues
q-analyses
q-analysis
q-beta
q-bic
q-calculus
q-calculuses
q-deformation
q-deformations
q-derivative
q-derivatives
q-difference
q-differences
q-differential
q-differentials
q-differentiation
q-differentiations
q-dimension
q-dimensions
q-extension
q-extensions
q-factorial
q-factorials
q-flex
q-function
q-functions
q-gamma
q-generalisation
q-generalisations
q-generalization
q-generalizations
q-graph
q-graphs
q-harmonic
q-hermite
q-hypergeometric
q-ideal
q-ideals
q-integral
q-integrals
q-integrating
q-integration
q-integrations
q-learning
q-learnings
q-max
q-number
q-numbers
q-optimal
q-optimalities
q-optimality
q-oscillator
q-oscillators
q-partial
q-particle
q-particles
q-pochhammer
q-pochhammers
q-pop
q-series
q-slope
q-slopes
q-test
q-tests
q-theta
q-tip
q-tips
q-tree
q-trees
q-value
q-values
q'anjob'al
q'eqchi
q'eqchi'
qabili
quail-plover
quail-plovers
quail-thrush
quail-thrushes
quantum-mechanical
quarter-on-quarter
quarter-over-quarter
quasi-abelian
quasi-adiabatic
quasi-adjudicative
quasi-affine
quasi-amorphous
quasi-analytic
quasi-atomic
quasi-autobiographical
quasi-bayesian
quasi-cartesian
quasi-classical
quasi-coherent
quasi-concave
quasi-concavities
quasi-concavity
quasi-conformal
quasi-continua
quasi-continuities
quasi-continuity
quasi-continuous
quasi-continuous-wave
quasi-continuum
quasi-contract
quasi-convex
quasi-convexities
quasi-convexity
quasi-cycle
quasi-cycles
quasi-degeneracies
quasi-degeneracy
quasi-degenerate
quasi-delict
quasi-delicts
quasi-deuteron
quasi-deuterons
quasi-diabatic
quasi-diagonal
quasi-dimensional
quasi-discrete
quasi-distribution
quasi-distributions
quasi-einstein
quasi-elastic
quasi-equilibria
quasi-equilibrium
quasi-experiment
quasi-experimental
quasi-experimentally
quasi-experiments
quasi-exponential
quasi-exponentially
quasi-extinction
quasi-extinctions
quasi-fission
quasi-fissions
quasi-frobenius
quasi-fuchsian
quasi-geodesic
quasi-geodesics
quasi-geostrophic
quasi-geostrophies
quasi-geostrophy
quasi-governmental
quasi-group
quasi-groups
quasi-harmonic
quasi-hereditary
quasi-hexagonal
quasi-hole
quasi-holes
quasi-homogeneities
quasi-homogeneity
quasi-homogeneous
quasi-hydrostatic
quasi-hyperbolic
quasi-identifier
quasi-identifiers
quasi-identities
quasi-identity
quasi-independence
quasi-independences
quasi-independent
quasi-injective
quasi-inverse
quasi-inverses
quasi-invertible
quasi-irreversible
quasi-isometric
quaterpyridine
quaterpyridines
quazepam
queen-of-the-prairies
queen-size
queen-sized
queer-baiting
queer-baitings
queer-looking
quern-stone
quern-stones
queryable
quick-witted
quick-wittedly
quick-wittedness
quick-wittednesses
quizalofop-p-ethyl
quizalofop-p-ethyls
quoc-ngu
qur'an
qur'anic
qur'ans
qusongites
qvevris
r-algebra
r-algebras
r-cadherin
r-cadherins
r-carvone
r-carvones
r-colored
r-enantiomer
r-enantiomers
r-glyceraldehyde
r-glyceraldehydes
r-loop
r-loops
r-module
r-modules
r-process
r-processes
r-rated
r-spondin
r-spondins
r-transform
r-transforms
r-tree
r-trees
r-value
r-values
r-word
r-words
ra-ra
ra-ras
rabbit-feet
rabbit-foot
rack-and-pinion
rage-bait
rage-baited
rage-baiting
rage-baits
rags-to-riches
rah-rah
rah-rahs
rainbow-coloured
rakaat
rakaats
rake-off
rake-offs
ram-raid
ram-raided
ram-raiding
ram-raids
ransomware-as-a-service
ransomwares-as-a-service
rao-blackwellisation
rao-blackwellisations
rao-blackwellised
rao-blackwellization
rao-blackwellizations
rao-blackwellized
raramuri
raramuris
rat-on-a-stick
rate-limited
ratio'd
rats-on-a-stick
rauvite
rauvites
rauwolscine
rauwolscines
raynaud's
razzle-dazzle
razzle-dazzles
re-add
re-added
re-adding
re-adds
re-elect
re-elected
re-electing
re-elects
re-emerge
re-emerged
re-emerges
re-emerging
re-endothelialisation
re-endothelialisations
re-endothelialization
re-endothelializations
re-engagement
re-epithelialisations
re-epithelializations
re-estimate
re-estimated
re-estimates
re-estimating
re-estimation
re-estimations
re-evaluate
re-evaluated
re-evaluates
re-evaluating
re-evaluation
re-evaluations
re-exploration
re-explorations
re-explore
re-explored
re-explores
re-exploring
re-expose
re-exposed
re-exposes
re-exposing
re-exposure
re-exposures
re-express
re-expressed
re-expresses
re-expressing
re-expression
re-expressions
re-identification
re-identifications
re-identified
re-identifies
re-identify
re-identifying
re-queen
re-queened
re-queening
re-queens
re-record
re-recorded
re-recording
re-records
re-release
re-released
re-releases
re-releasing
re-treatment
re-treatments
re-up
re-ups
read-only
real-life
real-time
real-valued
real-world
rear-ender
rear-enders
red-blooded
red-eye
red-eyes
red-handed
red-hots
red-pill
red-pilled
red-pilling
red-pills
red-tapeism
red-tapeisms
red-tapism
red-tapisms
reduction-oxidation
reduction-oxidations
reed-mace
reed-maces
reedmergnerite
reedmergnerites
refactor
refactoring
refactors
relative-in-law
relatives-in-law
reliabilities-as-a-service
reliability-as-a-service
religio-philosophical
rendille
rengginang-rengginang
renin-angiotensin-aldosterone
rent-free
representation-theoretic
researcher-in-residence
researchers-in-residence
resnet
resnets
rev-head
rev-heads
revi'i
rez-de-chaussee
rhathymias
ribitol
rica-rica
ricci-flat
ricci-flatness
ricci-flatnesses
richetite
richetites
ride-or-die
riffle-shuffle
riffle-shuffled
riffle-shuffles
riffle-shuffling
right-footed
right-hand
right-handed
right-handedness
right-handednesses
right-handers
right-libertarianism
right-libertarianisms
right-minded
right-o
right-on
right-to-life
right-to-lifer
right-to-lifers
right-to-work
right-wing
right-winger
right-wingers
righty-ho
ring-around-the-rosies
ring-around-the-rosy
ring-silicate
ring-silicates
rinky-dink
rip-off
rip-offs
rip-roaring
risedronate
risk-taker
risk-takers
ritlecitinib
ro-langs
ro-ro
ro-ros
road-going
road-trip
road-tripped
road-tripping
road-trips
robin-chat
robin-chats
robo-advisers
robo-advisors
robotics-as-a-service
rock-and-roll
rock-bottom
roflumilast
roggianite
roggianites
role-play
role-played
role-player
role-players
role-playing
role-playings
role-plays
roll-off
roll-offs
roll-on
roll-ons
roller-skate
roller-skated
roller-skates
roller-skating
roly-polies
roly-poly
roly-polys
romiplostim
rosasite
rose-tinted
rostite
rostites
rosy-cheeked
rotigotine
rough-and-ready
rough-and-tumble
rough-and-tumbles
rough-dried
rough-dries
rough-dry
rough-drying
rough-hewn
roul-roul
roul-rouls
round-shouldered
round-the-clock
round-trip
round-trips
round-up
round-ups
routhierite
routhierites
roux-en-y
rova-t
rovaniemi
row-major
row-wise
rowdy-dow
rozenite
rozenites
rozvi
rum-dum
rum-dumb
run-down
run-downs
run-in
run-ins
run-of-mine
run-of-the-mill
run-of-the-mine
run-off
run-offs
run-on
run-ons
run-stopper
run-stoppers
run-up
run-ups
runner-up
runner-ups
runners-up
runyankole
ruq'ah
rutul
ruyi
ruyis
rzehakinids
s-adenosyl-l-homocysteine
s-adenosyl-l-homocysteines
s-adenosyl-l-methionine
s-adenosyl-l-methionines
s-adenosylhomocysteine
s-adenosylhomocysteines
s-adenosylmethionine
s-adenosylmethionines
s-allyl-l-cysteines
s-allylcysteine
s-allylcysteines
s-box
s-boxes
s-carvone
s-carvones
s-enantiomer
s-enantiomers
s-expression
s-expressions
s-glycoside
s-glycosides
s-graph
s-graphs
s-matrices
s-matrix
s-mephenytoin
s-mephenytoins
s-mercaptocysteine
s-mercaptocysteines
s-methylcysteine
s-methylcysteines
s-methylmethionine
s-methylmethionines
s-metolachlor
s-metolachlors
s-myc
s-mycs
s-nitrosation
s-nitrosations
s-nitroso-glutathione
s-nitroso-glutathiones
s-nitroso-n-acetylcysteine
s-nitroso-n-acetylcysteines
s-nitroso-n-acetylpenicillamine
s-nitroso-n-acetylpenicillamines
s-nitrosoglutathione
s-nitrosoglutathiones
s-nitrosohaemoglobins
s-nitrosothiol
s-nitrosothiols
s-nitrosylation
s-nitrosylations
s-orbital
s-orbitals
s-palmitoylation
s-palmitoylations
s-parameter
s-parameters
s-polarisation
s-polarisations
s-polarization
s-polarizations
s-scheme
s-schemes
s-word
s-words
s'more
s'mores
sabas
sabbath-breaking
sabbath-keeper
sabbath-keeping
sabia-laranjeira
sabia-laranjeiras
sacubitril
sado-erotic
safeword
safewords
safranal
safranals
saharawi
saharawis
sahos
saikosaponin
saikosaponins
sailing-master
saint-john's-wort
saint-john's-worts
saint-nectaire
saint-nectaires
saint-simonian
saint-simonianism
saint-simonianisms
saint-simonians
saint-simonism
saint-simonisms
sairei-to
saireito
sakacin
sakacins
salah
salak
salaks
salmorejo
salmorejos
salpingo-oophorectomies
salpingo-oophorectomy
salpingooophorectomies
salt-and-pepper
salt-glazed
salzburger
salzburgers
samanya
samanyas
samarnon
same-sex
samkhyas
sand-blind
sang-froid
sang-froids
sannyasa
sannyasas
sans-culotte
sans-culottes
sanyasa
sanyasas
sapin-sapin
saraiki
saraikis
sargija
sasaites
satellite-as-a-service
satellites-as-a-service
satguru
satgurus
satsivi
sauce-alone
sauce-alones
sauconites
saudades
saw-wing
saw-wings
saw-wort
saw-worts
say-so
say-sos
sayrite
sayrites
scale-up
scale-ups
scaredy-cat
scaredy-cats
schallerite
schallerites
scholar-in-residence
scholars-in-residence
schreyerite
schreyerites
schumacherite
schumacherites
sci-fi
sci-fis
scientist-in-residence
scientists-in-residence
scissors-and-paste
scot-free
screen-scrape
screen-scraped
screen-scraper
screen-scrapers
screen-scrapes
screen-scraping
se'i
sea-foam
sea-foams
sec-butyl
sec-butylamine
sec-butylamines
sec-butyls
seco-iridoid
seco-iridoids
secoiridoid
secoiridoids
secologanin
secologanins
second-class
second-classes
second-generation
second-guess
second-guessed
second-guesser
second-guessers
second-guesses
second-guessing
second-in-command
second-in-commands
second-rate
second-rateness
second-ratenesses
second-rater
second-raters
second-rates
second-string
second-world
securities-as-a-service
security-as-a-service
see-through
seek-no-further
seek-no-furthers
segnitite
segnitites
selamectin
self-abandon
self-abandoned
self-abandoning
self-abandonment
self-abandons
self-abasement
self-abasements
self-abnegating
self-abnegation
self-abnegations
self-absorbed
self-absorbedness
self-absorbednesses
self-absorption
self-absorptions
self-abuse
self-abused
self-abuses
self-abusing
self-acceptance
self-acceptances
self-accepting
self-accountabilities
self-accountability
self-accusation
self-accusations
self-accusatory
self-accusing
self-acknowledged
self-acquired
self-acting
self-action
self-actions
self-activate
self-activated
self-activates
self-activating
self-actualisation
self-actualisations
self-actualise
self-actualised
self-actualises
self-actualising
self-actualization
self-actualizations
self-actualize
self-actualized
self-actualizes
self-actualizing
self-adapt
self-adaptation
self-adaptations
self-adapted
self-adapting
self-adaptive
self-adapts
self-addressed
self-adhesive
self-adjoint
self-adjointness
self-adjointnesses
self-adjust
self-adjusted
self-adjusting
self-adjustment
self-adjustments
self-adjusts
self-administer
self-administered
self-administering
self-administers
self-administration
self-administrations
self-admiration
self-admirations
self-admitted
self-adulation
self-adulations
self-advancement
self-advancements
self-advertise
self-advertised
self-advertisement
self-advertisements
self-advertises
self-advertising
self-advocacies
self-advocacy
self-advocate
self-advocated
self-advocates
self-advocating
self-affection
self-affections
self-affine
self-affinities
self-affinity
self-affirmation
self-affirmations
selk'nam
selkup
sell-by
selves-as-object
selves-as-subject
semaphorin
semaphorins
semarang
semi-algebraic
semi-aquatic
semi-autobiographical
semi-autobiographies
semi-autobiography
semi-bluff
semi-bluffing
semi-bluffings
semi-bluffs
semi-cascade
semi-cascades
semi-concave
semi-darkness
semi-darknesses
semi-decidable
semi-dry
semi-modular
semi-monocoque
semi-monocoques
semi-opera
semi-operas
semi-parametric
semi-presidentialisms
semi-quantitative
semi-quantitatively
semi-retired
semi-retirement
semi-retirements
semi-trailer
semi-trailers
semi-woody
send-off
send-offs
serunai
server-side
server-sides
set-aside
set-asides
set-off
set-offs
set-to
set-tos
set-up
set-ups
setsubun
setsuwa
setswana
seven-dimensional
seven-sphere
seven-spheres
seventy-eight
seventy-eighth
seventy-eighths
seventy-eights
seventy-fifth
seventy-fifths
seventy-first
seventy-firsts
seventy-five
seventy-fives
seventy-four
seventy-fours
seventy-fourth
seventy-fourths
seventy-nine
seventy-nines
seventy-ninth
seventy-ninths
seventy-one
seventy-ones
seventy-second
seventy-seconds
seventy-seven
seventy-sevens
seventy-seventh
seventy-sevenths
seventy-six
seventy-sixes
seventy-sixth
seventy-sixths
seventy-third
seventy-thirds
seventy-three
seventy-threes
seventy-two
seventy-twos
sex-and-shopping
sex-link
sex-linkage
sex-linkages
sex-links
sex-negative
sex-negativities
sex-negativity
sex-positive
sex-positivities
sex-positivity
sgian-dubh
sgian-dubhs
sgurrs
sh'ma
shabu-shabu
shake-up
shake-ups
shakuyaku-kanzo-to
shan't
shangri-la
shangri-las
shar-pei
shar-peis
she-oak
she-oaks
she'd
she'd've
she'll
she's
shelf-stable
sherbro
sherbros
sheriff-pinks
shevi'i
shi
shi'a
shi'as
shi'i
shi'is
shi'ism
shi'isms
shi'ite
shi'ites
shibuya-kei
shichi-go-san
shilly-shallied
shilly-shallies
shilly-shally
shilly-shallying
shinrin-yoku
shinrinyoku
ship-breaker
ship-broker
ship-rigged
shipibo-conibo
shipibo-konibo
shiritori
shishi-odoshi
shit-faced
shkmeruli
sho-saiko-to
shojo-ai
shonen-ai
shoo-flies
shoo-fly
shoo-in
shoo-ins
shoot-'em-up
shoot-'em-ups
shoot-em-up
shoot-em-ups
shoot-out
shoot-outs
shop-bought
shop-soiled
shop-window
shorrtest-term
short-circuit
short-circuited
short-circuiting
short-circuits
short-distance
short-haired
short-handed
short-handedly
short-handedness
short-handednesses
short-legged
short-lived
short-range
short-tempered
short-term
short-termism
short-termisms
shorter-range
shorter-term
shortest-range
shortest-term
shoujo-ai
should've
shouldn't
shouldn't've
shouldn'ts
shounen-ai
shove-it
shove-its
show-and-tell
show-and-tells
show-off
show-offs
shrike-tanager
shrike-tanagers
shrike-thrush
shrike-thrushes
shrike-tyrant
shrike-tyrants
shrike-vireo
shrike-vireos
shrub-steppe
shrub-steppes
shun-ga
shut-in
shut-ins
si-wu-tang
sialomucin
sialomucins
sibiu
sibling-in-law
siblings-in-law
side-by-side
side-centered
side-centred
side-on
side-wire
side-wired
side-wires
side-wiring
sight-read
sight-reading
sight-reads
sigma-additive
sigma-algebra
sigma-algebras
sigma-field
sigma-fields
sigma-ring
sigma-rings
sign-in
sign-ins
sign-up
sign-ups
silver-copper
silver-coppers
silver-tongued
simple-minded
singer-songwriter
singer-songwriters
single-blind
single-breasted
single-cell
single-celled
single-handed
single-handedly
single-handedness
single-handednesses
single-minded
single-player
single-sex
single-sided
single-wide
single-wides
sino-tibetan
sino-vietnamese
sipuleucel-t
sipuleucel-ts
sisaala
sister-in-law
sisters-in-law
sit-down
sit-downs
sit-in
sit-ins
sit-up
sit-up-and-beg
sit-ups
siwi
six-dimensional
six-figure
six-pack
six-packs
six-shooter
six-shooters
six-sphere
six-spheres
six-way
six-ways
sixty-eight
sixty-eighth
sixty-eighths
sixty-eights
sixty-fifth
sixty-fifths
sixty-first
sixty-firsts
sixty-five
sixty-fives
sixty-four
sixty-fours
sixty-fourth
sixty-fourths
sixty-nine
sixty-nined
sixty-nines
sixty-nining
sixty-ninth
sixty-ninths
sixty-one
sixty-ones
sixty-second
sixty-seconds
sixty-seven
sixty-sevens
sixty-seventh
sixty-sevenths
sixty-six
sixty-sixes
sixty-sixth
sixty-sixths
sixty-third
sixty-thirds
sixty-three
sixty-threes
sixty-two
sixty-twos
skew-whiff
skill-less
skill-lessness
skill-lessnesses
skin-tight
skinny-dip
skinny-dipped
skinny-dipping
skinny-dips
sky-blue
slack-jawed
slap-up
slash-and-burn
sleep-deprived
sleep-learning
sleep-learnings
sleep-teaching
sleep-teachings
slip-on
slip-ons
slip-up
slip-ups
slo-mo
slo-mos
sloop-of-war
sloops-of-wars
slot-and-filler
slot-car
slot-cars
slow-foot
slow-footed
slow-mo
slow-moed
slow-motion
slow-moving
slow-witted
slow-wittedly
slow-wittedness
slow-wittednesses
slower-footed
slower-moving
slowest-footed
slowest-moving
slut-shame
slut-shamed
slut-shames
slut-shaming
slut-shamings
sm'algyax
small-minded
small-scale
small-time
small-timer
small-timers
small-town
small-towner
small-towns
smash-and-grab
smash-and-grabs
smash-up
sml
smoke-jack
smoke-jacks
smooth-talk
smooth-talked
smooth-talking
smooth-talks
snail-eater
snail-eaters
snarl-up
snarl-ups
snip-snap
snip-snap-snorum
snip-snapped
snip-snapping
snip-snaps
snow-in-summer
snow-in-summers
snow-on-the-mountain
snow-on-the-mountains
snow-rose
snow-roses
snow-whiteness
snow-whitenesses
snow-whites
so-and-so
so-and-sos
so-called
so-so
socio-affective
socio-anthropological
socio-cultural
socio-economic
socio-economical
socio-economically
socio-institutional
socio-legal
socio-political
socio-politically
socio-politico-economic
socio-psychological
socio-sexual
socio-technical
sofosbuvir
soft-boiled
soft-core
soft-hearted
soft-heartedness
soft-heartednesses
soft-minded
soft-paste
soft-serve
soft-serves
soft-spoken
soft-spokenness
soft-spokennesses
softwares-as-a-service
sol-fa
sol-fas
sol-gel
sol-gels
solid-looking
solid-mouth
solid-mouthed
solids-not-fat
son-in-law
sons-in-law
sosaku-hanga
sotagliflozin
sotho-tswana
sotho-tswanas
sothos
sou'wester
sou'westers
soul-searching
soul-searchings
souls-like
souls-likes
south-southeast
south-southeasterlies
south-southeasts
south-southwest
south-southwesterlies
south-southwests
soyasaponin
soyasaponins
space-age
space-ages
space-time
space-times
span-new
spatio-temporal
speaker-in-residence
speakers-in-residence
speech-to-text
speech-to-texts
speed-up
spic-and-span
spick-and-span
spin-off
spin-offs
split-off
split-offs
spot-check
spot-checked
spot-checking
spot-checks
spot-throat
spot-throats
spread-eagle
spread-eagled
spread-eagles
spread-eagling
spring-clean
spring-cleaned
spring-cleaning
spring-cleans
squeaky-clean
st'at'imc
st'at'imcets
stable-meal
stable-meals
stand-alone
stand-in
stand-ins
stand-off
stand-offs
stand-up
stand-ups
standard-bearer
standard-bearers
standing-reserve
standing-reserves
star-of-bethlehem
star-spangled
starch-root
starch-roots
state-controlled
state-of-the-art
state-owned
state-run
state-wide
stay-at-home
stay-at-homer
stay-at-homers
steady-going
steady-handed
step-and-repeat
step-by-step
step-free
step-parent
step-relative
step-relatives
stepbrother-in-law
stepbrothers-in-law
stepchild-in-law
stepchildren-in-law
stepdaughter-in-law
stepdaughters-in-law
stepfather-in-law
stepfathers-in-law
stepmother-in-law
stepmothers-in-law
stepparent-in-law
stepparents-in-law
stereo-electroencephalographic
stereo-electroencephalographies
stereo-electroencephalography
stick-in-the-mud
stick-in-the-muds
stick-on
stick-to-it-iveness
stick-to-it-ivenesses
stick-to-itiveness
stick-to-itivenesses
still-burn
still-burned
still-burning
still-burns
stimulation-inhibition
stimulation-inhibitions
stimuli-responsiveness
stimuli-responsivenesses
stimulus-responsiveness
stimulus-responsivenesses
stone-cold
stone-curlew
stone-curlews
stop-and-frisk
stop-and-frisks
stop-and-go
stop-go
stop-motion
stop-motions
stop-off
stop-offs
store-and-forward
stork's-bill
stork's-bills
stout-hearted
straight-a
straight-acting
straight-arm
straight-armed
straight-arming
straight-arms
straight-from-the-shoulder
straight-to-video
straight-up
street-legal
stuck-up
student-centeredness
student-centerednesses
student-centredness
student-centrednesses
styrene-butadiene-styrene
styrene-butadiene-styrenes
sub-aqua
sub-branch
sub-branches
sub-cohort
sub-cohorts
sub-cycle
sub-cycles
sub-decadal
sub-delegate
sub-delegated
sub-delegates
sub-delegating
sub-delegation
sub-delegations
sub-drain
sub-drains
sub-expression
sub-expressions
sub-genre
sub-genres
sub-gigahertz
sub-grid
sub-grids
sub-i
sub-index
sub-indexes
sub-internship
sub-internships
sub-is
sub-q
sub-rosa
sub-saharan
sub-test
sub-tests
sub-vocabularies
sub-vocabulary
sub-zero
such-and-such
suck-up
suck-ups
suiboku-ga
sukajan
sukajans
sukuma
sulfamethoxazole-trimethoprim
sulfamethoxazole-trimethoprims
sulphamethoxazole-trimethoprim
sulphamethoxazole-trimethoprims
sumatriptan-naproxens
sumero-akkadian
sumi-e
summing-up
summings-up
sun-worshipper
sun-worshippers
sunday-go-to-meeting
sundubu-jjigae
super-centenarian
super-centenarians
super-duper
super-duperest
super-earth
super-earths
super-ego
super-egos
super-enhancer
super-enhancers
super-exponential
super-exponentially
super-g
super-gs
super-injunction
super-injunctions
super-jupiter
super-jupiters
super-neptune
super-neptunes
super-nyquist
super-resolution
super-spreader
super-spreaders
super-spreading
super-spreadings
super-taster
super-tasters
super-tasting
super-tastings
supra-aortic
sure-fire
sure-footed
sure-footedly
sure-footedness
sure-footednesses
surface-level
surface-to-air
surface-to-surface
surveillance-as-a-service
surveillances-as-a-service
sux
sveshnikov
sveshnikovs
swallow-shrike
swallow-shrikes
swallow-wort
swallow-worts
swan-neck
swan-necks
swearing-in
swearing-ins
swearings-in
sweet-and-sour
switched-on
swizzle-stick
sword-and-sandal
sword-and-sandals
sword-swallowers
swys
sympatho-adrenomedullary
syn-periplanar
syrniki
t-bone
t-boned
t-bones
t-boning
t-boy
t-boys
t-cadherin
t-cadherins
t-chart
t-charts
t-commerce
t-commerces
t-dick
t-dicks
t-girl
t-girls
t-graph
t-graphene
t-graphenes
t-graphs
t-intersection
t-intersections
t-matrices
t-matrix
t-octylphenoxypolyethoxyethanol
t-octylphenoxypolyethoxyethanols
t-optimal
t-pop
t-pose
t-posed
t-poses
t-posing
t-rex
t-rexes
t-shirt
t-shirted
t-shirts
t-slur
t-slurs
t-square
t-squares
t-stoff
t-stoffe
t-test
t-tests
t'boli
ta-da
ta-ta
taabwa
table-board
table-boards
table-hop
table-hopped
table-hopper
table-hoppers
table-hopping
table-hops
table-tapping
table-tappings
table-topped
table-turning
table-turnings
taegeuk
taegeuks
taekwon-do
taekwon-dos
tag-team
tag-teamed
tag-teaming
tag-teams
tahu-tahu
take-off
take-offs
take-out
take-outs
take-over
take-overs
take-up
takedaites
taken-for-grantedness
taken-for-grantednesses
takuan
takuans
takyas
takyeh
takyehs
talking-to
talking-tos
talkings-to
tally-ho
tally-hos
tam-o'-shanter
tam-tam
tam-tams
taoiseach
taoiseachs
tap-dancing
tap-in
tap-ins
task-motivated
tavil
tax-exempt
tay-sachs
tboli
teach-in
teach-ins
teacher-centeredness
teacher-centerednesses
teacher-centredness
teacher-centrednesses
teacher-in-residence
teacher-researcher
teacher-researchers
teacher-student
teachers-in-residence
team-kill
team-killed
team-kills
tech-savvy
techno-entrepreneurship
techno-entrepreneurships
tee-hee
tee-heed
tee-heeing
tee-hees
tee-shirt
tee-shirted
tee-shirts
teensy-weensier
teensy-weensiest
teensy-weensy
teeny-tiny
teeny-weenier
teeny-weeniest
teeny-weeny
teicoplanin
tejo
teke
tekes
tekyehs
tempeh-tempeh
ten-printed
tenant-in-chief
tenants-in-chief
tenascin-c
tenascin-cs
tenascin-r
tenascin-rs
tenascin-w
tenascin-ws
tenascin-x
tenascin-xes
tender-hearted
tender-heartedness
tender-heartednesses
tender-minded
tender-mindedness
tender-mindednesses
tenofovir-emtricitabine-efavirenz
tert-amyl
tert-amyls
tert-butanesulfinamides
tert-butanesulphinamide
tert-butanesulphinamides
tert-butyl
tert-butylamine
tert-butylamines
tert-butylhydroquinone
tert-butylhydroquinones
tert-butyls
tete-a-tete
tete-a-tetes
tetrachlorodibenzo-p-dioxin
tetrachlorodibenzo-p-dioxins
tex-mex
text-to-image
text-to-images
text-to-speech
text-to-speeches
thank-you-ma'am
thank-you-ma'ams
that'd
that'll
that's
that've
theater-in-the-round
theaters-in-the-round
theatre-in-the-round
theatres-in-the-round
theologian-in-residence
theologians-in-residence
there'd
there'll
there're
there's
there've
they-group
they-groups
they-self
they-selves
they'd
they'd've
they'll
they're
they've
thick-knee
thick-knees
thick-skinned
thigh-high
thigh-highs
thin-skinned
thing-in-itself
things-in-themselves
third-class
third-classes
third-generation
third-party
third-rate
third-rater
third-raters
third-rates
third-world
third-worldism
third-worldisms
third-worldist
third-worldists
thirty-eight
thirty-eighth
thirty-eighths
thirty-eights
thirty-fifth
thirty-fifths
thirty-first
thirty-firsts
thirty-five
thirty-fives
thirty-four
thirty-fours
thirty-fourth
thirty-fourths
thirty-nine
thirty-nines
thirty-ninth
thirty-ninths
thirty-one
thirty-ones
thirty-second
thirty-seconds
thirty-seven
thirty-sevens
thirty-seventh
thirty-sevenths
thirty-six
thirty-sixes
thirty-sixth
thirty-sixths
thirty-third
this'll
this's
thought-out
thought-provoking
three-ball
three-balls
three-dimensional
three-dimensionalism
three-dimensionalisms
three-dimensionalist
three-dimensionalists
three-dimensionalities
three-dimensionality
three-dimensionally
three-faces-under-a-hood
three-faces-under-a-hoods
three-factor
three-manifold
three-manifolds
three-sixties
three-sixty
three-sphere
three-spheres
three-star
three-tori
three-torus
three-way
three-ways
thrush-babbler
thrush-babblers
thunder-and-lightning
ti-liger
ti-ligers
tic-tac-toe
tic-tac-toes
ticarcillin-clavulanate
ticarcillin-clavulanates
tickety-boo
tickle-my-fancies
tickle-my-fancy
tide-rode
tie-dye
tie-dyed
tie-dyeing
tie-dyeings
tie-dyes
tie-in
tie-ins
tie-up
tie-ups
tifal
tiger's-eye
tiger's-eyes
tight-knit
tight-lipped
tii
tiletamine-zolazepams
time-honored
time-honoured
time-invariant
time-out
time-outs
time-periodic
time-sensitive
time-variant
time-varying
timor-leste
tip-and-run
tip-in
tip-ins
tip-off
tip-offs
tip-top
tip-tops
tiradito
tiraditos
tirilazad
tirthankaras
tirzepatide
tit-babbler
tit-babblers
tit-for-tat
tit-spinetail
tit-spinetails
tit-tyrant
tit-tyrants
tiv
tixagevimab-cilgavimab
tla-o-qui-aht
to-and-fro
to-and-fros
to-do
to-dos
to-go
to-night
to-year
to'abaita
toad-frog
toad-frogs
toad-in-the-hole
toads-in-the-hole
tody-flycatcher
tody-flycatchers
tody-tyrant
tody-tyrants
tofogliflozin
tohu-bohu
tohu-bohus
tohubohus
tojolab'ales
tokoeka
tom-tom
tom-toms
ton-mile
ton-miles
tonalite-trondhjemite-granodiorite
tonalite-trondhjemite-granodiorites
tone-deaf
tone-deafness
tone-deafnesses
toned-down
tongue-in-cheek
tongue-lash
tongue-lashed
tongue-lashes
tongue-lashing
tongue-lashings
tongue-tie
tongue-tied
tongue-ties
tongue-tying
tongue-walk
tongue-walked
tongue-walking
tongue-walks
toodle-oo
top-down
top-heavily
top-heaviness
top-heavinesses
top-heavy
top-notch
top-notcher
top-notchers
top-of-the-line
top-to-the-east
top-to-the-east-northeast
top-to-the-east-southeast
top-to-the-north
top-to-the-north-northeast
top-to-the-north-northwest
top-to-the-northeast
top-to-the-northwest
top-to-the-south
top-to-the-south-southeast
top-to-the-south-southwest
top-to-the-southeast
top-to-the-southwest
top-to-the-west
top-to-the-west-northwest
top-to-the-west-southwest
top-up
top-ups
toraja-sa'dan
toss-up
toss-ups
touch-and-go
touch-me-not
touch-me-nots
touch-point
touch-points
touch-type
touch-typed
touch-types
touch-typing
touch-typist
touch-typists
touch-up
touch-ups
touchy-feely
tough-minded
tough-mindedness
tough-mindednesses
toyi-toyi
toyi-toyied
toyi-toyiing
toyi-toyis
treasuries-as-a-service
tri-color
tri-colors
tri-colour
tri-colours
tri-n-butylamine
tri-n-butylamines
tri-o-tolylphosphine
tri-o-tolylphosphines
tri-tert-butylphosphine
tri-tert-butylphosphines
tri-tip
tri-tips
true-blue
true-hearted
try-on
try-ons
tryptases
tsakonian
tse'khene
tshivenda
tshwa
tsilhqot'in
tsk-tsk
tsk-tsked
tsk-tsking
tsk-tsks
tsleil-waututh
tsongas
tsuut'ina
tswa
tteok-bokki
tube-eye
tube-eyes
tuco-tuco
tuco-tucos
tucu-tucu
tucu-tucus
tuft-hunter
tuft-hunters
tuftsin
tuftsins
tug-of-war
tugs-of-war
tuk-tuk
tuk-tuks
tukano
tum-tum
tum-tums
tune-up
tune-ups
tupan
tupans
tupuri
turbo-ramjet
turbo-ramjets
tuyuca
twice-baked
twin-axes
twin-axis
two-and-a-half-dimensional
two-ball
two-balls
two-dimensional
two-dimensionalism
two-dimensionalisms
two-dimensionalities
two-dimensionality
two-dimensionally
two-eyed
two-faced
two-facedly
two-facedness
two-facednesses
two-factor
two-fold
two-seater
two-seaters
two-sided
two-sidedness
two-sidednesses
two-sphere
two-spheres
two-spirit
two-spirited
two-spirits
two-spot
two-spots
two-star
two-stroke
two-time
two-timed
two-timer
two-timers
two-times
two-timing
two-up
two-ups
two-way
two-ways
twopenn'orth
twopenny-halfpenny
tympanomastoidectomies
tympanomastoidectomy
tyrant-flycatcher
tyrant-flycatchers
tyrant-manakin
tyrant-manakins
tz'utujil
tz'utujiles
tz'utujils
tzolk'in
tzolk'ins
u-ey
u-eys
u-form
u-forms
u-ie
u-ies
u-law
u-laws
u-process
u-processes
u-shaped
u-statistic
u-statistics
u-substitution
u-substitutions
u-turn
u-turned
u-turning
u-turns
ubidecarenone
ubiquinol
ubiquinols
ubiquitinate
ubiquitinated
ubiquitinates
ubiquitinating
ubisemiquinone
ubisemiquinones
ubrogepant
ubykh
ucayalina
udenafil
udmurt
udorthents
uh-huh
uh-oh
uh-uh
ukay-ukay
ukiyo-e
ukiyo-ye
ukoy
ukulelists
ultra-high
ultra-leftism
ultra-leftisms
ultra-leftist
ultra-leftists
ultra-pasteurisation
ultra-pasteurisations
ultra-pasteurised
ultra-pasteurization
ultra-pasteurizations
ultra-pasteurized
ultra-premium
umpire-in-chief
umpires-in-chief
un-get-at-able
un-understandable
un-understanding
un-understood
uncalled-for
unkei-to
up-and-comer
up-and-comers
up-and-coming
up-and-down
up-and-over
up-and-under
up-conversion
up-conversions
up-converted
up-converter
up-converters
up-converting
up-projection
up-projections
up-regulated
up-regulates
up-regulating
up-regulation
up-regulations
up-titrating
up-titration
up-titrations
up-to-date
up-to-dately
up-to-dateness
up-to-datenesses
up-to-the-minute
up-valley
upadacitinib
upper-class
upper-classness
upper-classnesses
upregulate
upregulated
upregulates
upregulating
upregulation
upregulations
upside-down
upside-downness
upside-downnesses
urea-formaldehyde
urea-formaldehydes
urhobo
uru-eu-wau-wau
user-friendlier
user-friendliest
user-friendliness
user-friendlinesses
user-unfriendliness
user-unfriendlinesses
ushuaia
ustic
ustifluvent
ustifluvents
ustochrept
ustochrepts
ustollic
ustorthent
ustorthents
utaite
utaites
utonagans
uziza
v-akt
v-akts
v-block
v-blocks
v-day
v-days
v-fib
v-fibs
v-fos
v-foses
v-jun
v-juns
v-keis
v-kit
v-kits
v-maf
v-mafs
v-myc
v-mycs
v-neck
v-necks
v-onc
v-oncs
v-optimal
v-optimalities
v-optimality
v-pop
v-ras
v-rases
v-shaped
v-sis
v-sises
v-statistic
v-statistics
v-steaming
v-steamings
v-substitution
v-substitutions
v-tach
v-tachs
v-tail
v-tails
v'ahavta
va-jay-jay
va-jay-jays
va-va-voom
vaborbactam
vaisheshika
vaisheshikas
vajra-mushti
vajrayana
valentine's
vamorolone
vatsongas
vectorcardiograms
vedantas
vice-captain
vice-captains
vice-chancellor
vice-chancellors
vice-chancellorship
vice-chancellorships
vice-consul
vice-consuls
vice-presidencies
vice-presidency
vice-president
vice-president-elects
vice-presidents
vice-presidents-elect
video-electroencephalogram
video-electroencephalograms
video-electroencephalographic
video-electroencephalographies
video-electroencephalography
video-oculographic
video-oculographies
video-polysomnographic
video-polysomnographies
video-polysomnography
viets
viid
vijayadashami
violarite
violarites
vis-a-vis
vo-ag
voc-ed
voc-eds
voice-to-text
voice-to-texts
vol-au-vent
vol-au-vents
vori
voxilaprevir
vranec
vranecs
vunjo
w-curve
w-curves
w-distance
w-distances
w-graph
w-graphs
w-shaped
waacking
waakye
wabi-sabi
wafuu
wag-on-the-wall
wag-on-the-walls
wake-robin
wake-robins
wake-up
wake-ups
walk-in
walk-ins
walk-on
walk-ons
walk-through
walk-throughs
walk-up
walk-ups
walkie-talkie
walkie-talkies
war-game
war-gamed
war-games
war-gaming
war-torn
waray-waray
warbler-finch
warbler-finches
wasei-eigo
wash-and-wear
washed-out
washing-up
washing-ups
water-apple
water-apples
water-arum
water-arums
water-berries
water-berry
water-bind
water-binds
water-like
water-plantain
water-plantains
wax-eye
wax-eyes
way-out
we-experience
we-experiences
we-group
we-groups
we'd
we'd've
we'll
we're
we've
weak-kneed
weak-minded
web-toed
weigh-in
weigh-ins
well-balanced
well-behaved
well-being
well-beings
well-born
well-bred
well-brought-up
well-child
well-conditioned
well-defined
well-disciplined
well-done
well-earned
well-established
well-founded
well-foundedness
well-foundednesses
well-grounded
well-heeled
well-informed
well-intentioned
well-known
well-mannered
well-meaning
well-meaningly
well-meant
well-nigh
well-off
well-order
well-ordered
well-ordering
well-orderings
well-orders
well-posed
well-posedness
well-posednesses
well-quasi-order
well-quasi-ordered
well-quasi-ordering
well-quasi-orderings
well-quasi-orders
wen-do
weren't
wesekh
west-northwest
west-northwests
west-southwest
west-southwests
wet'suwet'en
wh's-in-situ
whack-a-mole
wham-bam
which'll
whiff-whaff
whiff-whaffs
who'd
who'd've
who'll
who're
who's
who've
whoop-de-do
whoop-de-doo
whoop-de-doos
whoop-de-dos
why'd
why'll
why're
why's
why've
wi-fi
wi-fis
wide-awake
wide-awakeness
wide-awakenesses
wide-awakes
wide-bodies
wide-body
wide-eyed
wide-flung
wide-ranging
win-win
wind-broken
wind-rode
wind-rose
wind-roses
wind-up
wind-ups
wishy-washier
wishy-washiest
wishy-washiness
wishy-washinesses
wishy-washy
witch-hunt
witch-hunted
witch-hunter
witch-hunters
witch-hunting
witch-hunts
wolaytta
wolf-eel
wolf-eels
wolf-herring
wolf-herrings
wolf's-bane
wolf's-banes
woman-about-town
woman-to-woman
women-about-town
won't
wonga-wonga
wonga-wongas
wood-fired
word-blind
word-final
word-finally
word-initial
word-initially
word-medial
word-medially
word-of-mouth
work-and-tumble
work-and-turn
work-and-twist
would-be
would-bes
would've
wouldn't
wouldn't've
wren-babbler
wren-babblers
wren-warbler
wren-warblers
write-down
write-downs
write-in
write-ins
write-off
write-offs
write-only
write-protected
write-protecting
write-up
write-ups
wrong-minded
wu-wei
wukchumni
x-as-a-service
x-axes
x-axis
x-caboquinho
x-caboquinhos
x-coordinate
x-coordinates
x-distance
x-distances
x-ed
x-efficiencies
x-efficiency
x-efficient
x-inefficiencies
x-inefficiency
x-inefficient
x-ing
x-intercept
x-intercepts
x-rated
x-ray
x-rayed
x-raying
x-rays
x-value
x-values
x-vector
x-vectors
x'd
x'ing
x's
xamtanga
xes-as-a-service
xesibe
xesibes
xi'an
xiao-chai-hu-tang
xiao'erjing
xibe
xima
xinafoates
xurel
xylo-oligosaccharide
xylo-oligosaccharides
y-axes
y-axis
y-coordinate
y-coordinates
y-dimension
y-dimensions
y-distance
y-distances
y-intercept
y-intercepts
y-junction
y-junctions
y'all
y'all's
y'know
yab-yum
yackety-yack
yackety-yacked
yackety-yacking
yackety-yacks
yackety-yak
yackety-yakked
yackety-yakking
yackety-yaks
yacouba
yaeyama
yagaria
yaghnobi
yakety-yak
yakety-yakked
yakety-yakking
yakety-yaks
yakity-yak
yakity-yakked
yakity-yakking
yakity-yaks
yala
yalunka
yamato-damashii
yamato-e
yansi
yaoguai
yaos
ye-ye
ye-yes
ye'elimite
ye'elimites
yea-saying
yeast-leavened
yee-haw
yellow-bellied
yellow-dog
yersiniabactin
yersiniabactins
yesn't
yesterday-today-and-tomorrow
yesterday-today-and-tomorrows
yesterday-today-tomorrow
yesterday-today-tomorrows
yindjibarndi
ylang-ylang
ylang-ylangs
ylidic
yn
yo-heave-ho
yo-ho
yo-ho-ho
yo-hos
yo-yo
yo-yoed
yo-yoer
yo-yoers
yo-yoing
yo-yos
yokai
yoo-hoo
yoo-hoos
yorkie-poo
yorkie-poos
yoshimuraite
yoshimuraites
yottanewtons
you-know-who
you'd
you'd've
you'll
you're
you've
young-old
young'un
young'uns
yuefu
yugambeh
yukaghirs
yuksporites
yum-yum
yup'ik
z-ajoene
z-ajoenes
z-alkene
z-alkenes
z-axes
z-axis
z-coordinate
z-coordinates
z-distance
z-distances
z-drug
z-drugs
z-fighting
z-fightings
z-graph
z-graphs
z-groups
z-guggulsterone
z-guggulsterones
z-ideal
z-ideals
z-intercept
z-intercepts
z-ligustilide
z-ligustilides
z-list
z-lister
z-listers
z-lists
z-matrices
z-matrix
z-matrixes
z-number
z-numbers
z-orders
z-parameter
z-parameters
z-plasties
z-plasty
z-scheme
z-schemes
z-score
z-scored
z-scores
z-scoring
z-scorings
z-test
z-tests
z-value
z-values
za'atar
za'atars
zaa
zaalouk
zaalouks
zaas
zaghawa
zaghawas
zawg
zawgs
zay
zayanes
zays
zaza
zazaki
zearalenone
zearalenones
zenzic
zenzics
zero-calorie
zero-click
zero-day
zero-days
zero-dimensional
zero-order
zero-rated
zero-shot
zero-sum
zero-valent
zero-waste
zero-zero
zeta-carotene
zeta-carotenes
zeta-cypermethrin
zeta-cypermethrins
zhangjiajie
zhuyin
ziehl-neelsen-stained
zip-up
zip-ups
zipperhead
zipperheads
ziv-aflibercept
zolotniks
zrazy
zubrowka
zvolen
zwiebelkuchen
]==]

    local normalizedOwner = {}
    local normalizedAmbiguous = {}

    for word in rawDelta:gmatch("[^\r\n]+") do
        word = tostring(word or ""):lower():gsub("[%s%c]+", "")
        if #word >= 2 and not env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] then
            env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] = true
            table.insert(env.WordHelperUnbeatable.ProDictionaryDeltaWords, word)

            local first = word:sub(1, 1)
            local bucket = env.WordHelperUnbeatable.ProDictionaryDeltaBuckets[first]
            if not bucket then
                bucket = {}
                env.WordHelperUnbeatable.ProDictionaryDeltaBuckets[first] = bucket
            end
            bucket[#bucket + 1] = word

            for n = 1, math.min(4, #word) do
                local p = word:sub(1, n)
                env.WordHelperUnbeatable.ProDictionaryDeltaPrefixCount[p] =
                    (env.WordHelperUnbeatable.ProDictionaryDeltaPrefixCount[p] or 0) + 1
            end

            local norm = word:gsub("[^a-z]", "")
            if norm ~= "" then
                if normalizedOwner[norm] and normalizedOwner[norm] ~= word then
                    normalizedAmbiguous[norm] = true
                elseif not normalizedOwner[norm] then
                    normalizedOwner[norm] = word
                end
            end
        end
    end

    table.sort(env.WordHelperUnbeatable.ProDictionaryDeltaWords)
    for _, bucket in pairs(env.WordHelperUnbeatable.ProDictionaryDeltaBuckets) do
        table.sort(bucket)
    end

    for norm, word in pairs(normalizedOwner) do
        if not normalizedAmbiguous[norm] then
            env.WordHelperUnbeatable.ProDictionaryNormalizedUnique[norm] = word
        end
    end
end
env.WordHelperUnbeatable.InitProDictionaryDelta()

env.WordHelperUnbeatable.AdjustProDeltaUnavailableWord = function(word, deltaAmount)
    -- Canonical Pro entries may contain apostrophes/hyphens; keep them intact.
    word = tostring(word or ""):lower():gsub("%s+", "")
    deltaAmount = tonumber(deltaAmount) or 0
    if deltaAmount == 0
        or not env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] then
        return
    end

    local counts = env.WordHelperUnbeatable.ProDictionaryDeltaUnavailable
    for n = 1, math.min(4, #word) do
        local p = word:sub(1, n)
        local nextValue = (counts[p] or 0) + deltaAmount
        if nextValue > 0 then
            counts[p] = nextValue
        else
            counts[p] = nil
        end
    end
end

env.WordHelperUnbeatable.RebuildProDeltaUnavailable = function()
    env.WordHelperUnbeatable.ProDictionaryDeltaUnavailable = {}
    for word in pairs(Blacklist) do
        if env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] then
            env.WordHelperUnbeatable.AdjustProDeltaUnavailableWord(word, 1)
        end
    end
    for word in pairs(UsedWords) do
        if not Blacklist[word] and env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] then
            env.WordHelperUnbeatable.AdjustProDeltaUnavailableWord(word, 1)
        end
    end
end

env.WordHelperUnbeatable.RebuildProDeltaUnavailable()

-- V19.1: words confirmed by the user to exist in Pro servers only.
-- IMPORTANT: these are deliberately NOT merged into Words/Buckets or the normal
-- membership table, so no other WordHelper mode can surface them.
env.WordHelperUnbeatable.HardcodedProExclusiveWords = {
    -- Existing confirmed Pro-only XES entries.
    "xes-as-a-service",
    "xesibe",
    "xesibes",

    -- V20.5: newly confirmed Pro dictionary entries.
    "luba",
    "luba-kasai",
    "luba-katanga",
    "luba-lulua",
    "nlaka'pamux"
}

env.WordHelperUnbeatable.ProExclusiveWords = {}
env.WordHelperUnbeatable.ProExclusiveSet = {}
env.WordHelperUnbeatable.ProExclusiveNormalized = {}

env.WordHelperUnbeatable.RefreshProExclusiveWords = function()
    local list = {}
    local set = {}
    local normalizedMap = {}

    local function add(word)
        word = tostring(word or ""):lower():gsub("[%s%c]+", "")
        if #word < 2 then return end

        local norm = word:gsub("[^a-z]", "")
        if norm == "" then return end

        -- V20.8.2: the 489,216-word Pro union already contains the old hardcoded
        -- Pro words. Keep this table only as an overlay for future manual words
        -- that are genuinely outside the embedded Pro dictionary.
        if WordHelperKnownWords[word] == true
            or (env.WordHelperUnbeatable.ProDictionaryDeltaSet
                and env.WordHelperUnbeatable.ProDictionaryDeltaSet[word]) then
            return
        end

        if set[word] or normalizedMap[norm] then
            return
        end

        list[#list + 1] = word
        set[word] = true
        normalizedMap[norm] = word
    end

    for _, word in ipairs(env.WordHelperUnbeatable.HardcodedProExclusiveWords) do
        add(word)
    end

    Config.ProCustomWords = Config.ProCustomWords or {}
    for _, word in ipairs(Config.ProCustomWords) do
        add(word)
    end

    table.sort(list)

    env.WordHelperUnbeatable.ProExclusiveWords = list
    env.WordHelperUnbeatable.ProExclusiveSet = set
    env.WordHelperUnbeatable.ProExclusiveNormalized = normalizedMap
end

env.WordHelperUnbeatable.RefreshProExclusiveWords()

-- V19.3: confirmed Pro-server 2-letter returns that do NOT trigger alone.
-- Suppression applies ONLY when the actual chosen returned prefix is exactly
-- two letters. Longer 3/4-letter returns ending in these pairs remain valid.
env.WordHelperUnbeatable.ProSuppressedTwoLetter = {
    ["rf"] = true,
    ["rl"] = true,
    ["dn"] = true,
    ["rs"] = true,
    ["ln"] = true,
    ["tl"] = true,
    ["ls"] = true,
    -- V20.7.8: user-requested fallback-only Pro two-letter returns.
    -- These stay available if needed, but never receive strategic priority.
    ["ck"] = true,
    ["lt"] = true,
    ["wk"] = true,
    ["rk"] = true
}

env.WordHelperUnbeatable.ProPriorityTwoLetter = {
    ["nl"] = true
}

-- V20.7.9: while F8 Spicy mode is ON and Pro Unbeatable is at Stage 2,
-- prefer these user-confirmed 2-letter trap returns whenever candidates are
-- otherwise tied on the live reply-bank size.  Reply count STILL comes first,
-- so a 1-reply return always beats a 2-reply return.  The preferred traps are
-- randomized only among strategically equal candidates.
env.WordHelperUnbeatable.ProSpicyStage2TwoLetter = {
    ["zi"] = true, ["sd"] = true, ["md"] = true, ["mg"] = true, ["rg"] = true,
    ["yg"] = true, ["yp"] = true, ["yc"] = true, ["mh"] = true, ["nh"] = true,
    ["dh"] = true, ["kh"] = true, ["dz"] = true, ["lw"] = true, ["dw"] = true,
    ["sf"] = true, ["sv"] = true, ["tz"] = true, ["tx"] = true, ["kt"] = true,
    ["nk"] = true, ["hl"] = true, ["yw"] = true, ["bt"] = true, ["mb"] = true,
    ["fd"] = true, ["pk"] = true, ["sz"] = true, ["hd"] = true, ["pf"] = true,
    ["cw"] = true, ["kw"] = true, ["sb"] = true, ["sg"] = true, ["mz"] = true,
    ["ez"] = true, ["pc"] = true, ["fs"] = true, ["tg"] = true
}

-- V20.7.8: optional Pro-only randomized tie-breaker (F8).
-- Strategic logic is unchanged: punctuation tier, reply count, confirmed 2L
-- handling, and returned-prefix length are all resolved BEFORE randomness.
-- Randomness only chooses among strategically equivalent candidates.
env.WordHelperUnbeatable.ProSpicyRandom = env.WordHelperUnbeatable.ProSpicyRandom or false
env.WordHelperUnbeatable.ProSpicySeed = env.WordHelperUnbeatable.ProSpicySeed or math.random(1, 2147483000)
env.WordHelperUnbeatable.ProSpicyRank = function(word)
    local text = tostring(word or "") .. "|"
        .. tostring(env.WordHelperUnbeatable.ProSpicySeed or 1) .. "|"
        .. tostring(env.WordHelperUnbeatable.CurrentTurn or 1)
    local h = 2166136261
    for i = 1, #text do
        h = (h * 16777619 + text:byte(i)) % 2147483647
    end
    return h
end

env.WordHelperUnbeatable.IsProWordUnavailable = function(word)
    word = tostring(word or ""):lower()
    if Blacklist[word] == true or UsedWords[word] == true then return true end

    -- Server packets may omit punctuation from a Pro spelling. Resolve the unique
    -- normalized identity so that the canonical Pro word is still treated as used.
    local norm = word:gsub("[^a-z]", "")
    if env.WordHelperUsedTracker
        and env.WordHelperUsedTracker.NormalizedUsed
        and env.WordHelperUsedTracker.NormalizedUsed[norm] then
        return true
    end

    local canonical = env.WordHelperUnbeatable.ProDictionaryNormalizedUnique
        and env.WordHelperUnbeatable.ProDictionaryNormalizedUnique[norm]
    return canonical ~= nil
        and (Blacklist[canonical] == true or UsedWords[canonical] == true)
end

-- Add Pro-only continuations to a normal prefix count without contaminating the
-- normal dictionary.  This matters if one of these words itself is a valid solve
-- for a returned Pro prefix.
env.WordHelperUnbeatable.GetProBaseReplyInfo = function(prefix)
    prefix = tostring(prefix or ""):lower()
    local count, selfSolve = env.WordHelperUnbeatable.GetBaseReplyInfo(prefix)

    -- V20.7: add the current Pro-only delta while subtracting Pro-delta words
    -- already used/blacklisted in this match. Casual words remain counted by
    -- GetBaseReplyInfo, so no 476k duplicate dictionary is needed.
    local deltaTotal = env.WordHelperUnbeatable.ProDictionaryDeltaPrefixCount[prefix] or 0
    local deltaUnavailable = env.WordHelperUnbeatable.ProDictionaryDeltaUnavailable[prefix] or 0
    count = count + math.max(0, deltaTotal - deltaUnavailable)

    if env.WordHelperUnbeatable.ProDictionaryDeltaSet[prefix]
        and not env.WordHelperUnbeatable.IsProWordUnavailable(prefix) then
        selfSolve = true
    end

    -- Future manually-added Pro words that are not in either loaded dictionary
    -- remain supported as a tiny overlay.
    for _, proWord in ipairs(env.WordHelperUnbeatable.ProExclusiveWords) do
        if proWord:sub(1, #prefix) == prefix
            and not env.WordHelperUnbeatable.IsProWordUnavailable(proWord) then
            count = count + 1
            if proWord == prefix then
                selfSolve = true
            end
        end
    end

    return count, selfSolve
end


-- V20.8.1: cached difficulty tie-breaker for deterministic Pro Unbeatable.
-- V20.8.0 rescanned the reply dictionary once for EVERY candidate being ranked.
-- That preserved the desired "fewest replies -> longest forced answer" logic,
-- but became expensive in large Pro result sets.
--
-- Difficulty is really a property of the RETURNED PREFIX, not normally of the
-- producer word. Cache the two shortest live non-self replies per prefix and
-- PrefixVersion.  The second reply is retained only for the rare case where the
-- producer itself also starts with the returned prefix and therefore must be
-- hypothetically removed from its own reply bank.
--
-- Result: EXACT SAME hard-mode ordering, but expensive reply scans happen once
-- per unique returned prefix/version instead of once per candidate.
env.WordHelperUnbeatable.ProForcedReplyCache = env.WordHelperUnbeatable.ProForcedReplyCache or {}

env.WordHelperUnbeatable.GetProForcedReplyDifficulty = function(prefix, candidate)
    prefix = tostring(prefix or ""):lower()
    candidate = tostring(candidate or ""):lower()
    if prefix == "" then return 0, "" end

    local version = (env.WordHelperUnbeatable.PrefixVersion or {})[prefix] or 0
    local cacheKey = prefix .. "|v" .. tostring(version)
    local cached = env.WordHelperUnbeatable.ProForcedReplyCache[cacheKey]

    if not cached then
        local firstLen, firstWord = math.huge, ""
        local secondLen, secondWord = math.huge, ""
        local seen = {}

        local function consider(word)
            if not word or word == "" then return end
            if seen[word] then return end
            seen[word] = true
            if word == prefix then return end -- self-solve is excluded from NonSelfReplies
            if word:sub(1, #prefix) ~= prefix then return end
            if env.WordHelperUnbeatable.IsProWordUnavailable(word) then return end

            local len = #word
            if len < firstLen or (len == firstLen and (firstWord == "" or word < firstWord)) then
                secondLen, secondWord = firstLen, firstWord
                firstLen, firstWord = len, word
            elseif word ~= firstWord and (len < secondLen or (len == secondLen and (secondWord == "" or word < secondWord))) then
                secondLen, secondWord = len, word
            end
        end

        -- Casual/base dictionary range.
        local range = PrefixRanges[prefix]
        if range then
            for i = range[1], range[2] do
                consider(Words[i])
            end
        end

        -- Embedded Pro-only delta. Buckets are sorted, so stop after prefix range.
        local first = prefix:sub(1, 1)
        local deltaBucket = env.WordHelperUnbeatable.ProDictionaryDeltaBuckets[first] or {}
        local seenPrefix = false
        for _, word in ipairs(deltaBucket) do
            local matches = word:sub(1, #prefix) == prefix
            if matches then
                seenPrefix = true
                consider(word)
            elseif seenPrefix then
                break
            end
        end

        -- Tiny future manual Pro-only overlay.
        for _, word in ipairs(env.WordHelperUnbeatable.ProExclusiveWords or {}) do
            consider(word)
        end

        cached = {
            FirstLen = firstLen, FirstWord = firstWord,
            SecondLen = secondLen, SecondWord = secondWord
        }
        env.WordHelperUnbeatable.ProForcedReplyCache[cacheKey] = cached
    end

    -- Candidate is treated as already played. Usually it does not start with its
    -- own returned suffix, but when it does, use the cached second-shortest reply.
    local len, word = cached.FirstLen, cached.FirstWord
    if word ~= "" and word == candidate then
        len, word = cached.SecondLen, cached.SecondWord
    end

    if not len or len == math.huge or not word or word == "" then
        return 0, ""
    end
    return len, word
end

-- ============================================================
-- PRO UNBEATABLE
-- Pro-server observed trigger rule:
--   a returned prefix qualifies when it has at least ONE usable
--   continuation OTHER than the prefix's own self-solve.
--
-- Everything else stays aligned with normal Unbeatable:
--   * same turn/stage progression
--   * longest qualifying suffix first
--   * candidate is treated as used after play
--   * UsedWords / Blacklist / exhaustion all apply
--   * no normal-server 2-letter whitelist/suppression bias
-- ============================================================
env.WordHelperUnbeatable.GetProCandidateInfo = function(candidate)
    local stageNow = math.clamp(tonumber(env.WordHelperUnbeatable.Stage) or 1, 1, 4)
    local pv = env.WordHelperUnbeatable.PrefixVersion
    local versionParts = {}

    for n = 1, math.min(stageNow, #candidate) do
        local suffix = candidate:sub(#candidate - n + 1)
        versionParts[#versionParts + 1] = suffix .. ":" .. tostring(pv[suffix] or 0)
    end

    local candidateCacheKey = tostring(candidate)
        .. "|pro485|s" .. tostring(stageNow)
        .. "|" .. table.concat(versionParts, ",")

    local cached = env.WordHelperUnbeatable.ProSortCache[candidateCacheKey]
    if cached then return cached end

    local chosenPrefix = ""
    local totalReplies = 999999
    local nonSelfReplies = 999999
    local selfSolve = false
    local qualified = false
    local chosenHasPunctuation = false

    for suffixLen = math.min(stageNow, #candidate), 1, -1 do
        local prefix = candidate:sub(-suffixLen)
        local startsWithLetter = prefix:match("^[a-z]") ~= nil
        local hasPunctuation = prefix:find("'", 1, true) ~= nil
            or prefix:find("-", 1, true) ~= nil

        -- Observed Pro rule: a returned prefix cannot START with punctuation.
        -- User-confirmed punctuation traps should begin at Stage 3, so a 2-char
        -- form such as A- is never promoted as a punctuation return.
        local punctuationLengthAllowed = (not hasPunctuation) or suffixLen >= 3

        if startsWithLetter and punctuationLengthAllowed then
            local baseCount, baseSelf = env.WordHelperUnbeatable.GetProBaseReplyInfo(prefix)

            local candidateWasCounted =
                candidate:sub(1, #prefix) == prefix
                and not env.WordHelperUnbeatable.IsProWordUnavailable(candidate)

            local available = baseCount - (candidateWasCounted and 1 or 0)
            local availableSelf = baseSelf and candidate ~= prefix
            local otherReplies = available - (availableSelf and 1 or 0)

            if otherReplies >= 1 then
                chosenPrefix = prefix
                totalReplies = available
                nonSelfReplies = otherReplies
                selfSolve = availableSelf
                qualified = true
                chosenHasPunctuation = hasPunctuation
                break
            end
        end
    end

    local perfectTrap = qualified and nonSelfReplies == 1

    -- V20.7 dynamic punctuation trap: not a hardcoded word list.  Any candidate
    -- whose ACTUAL stage-legal returned prefix contains an apostrophe/hyphen and
    -- leaves only 1-2 non-self replies enters the punctuation-trap tier. If the
    -- Pro dictionary later gains more replies, it naturally falls back into the
    -- normal Lowest Entry tier without any code change.
    local punctuationTrap = qualified
        and chosenHasPunctuation
        and #chosenPrefix >= 3
        and nonSelfReplies <= 2

    local priorityTier
    if punctuationTrap then
        priorityTier = 1
    elseif perfectTrap then
        priorityTier = 2
    elseif qualified then
        priorityTier = 3
    else
        priorityTier = 4
    end

    local score
    if qualified then
        score = 30000000
            - math.min(nonSelfReplies, 1000) * 100000
            + #chosenPrefix * 1000
            - totalReplies * 10

        if perfectTrap then
            score = score + 5000000
        end
        if punctuationTrap then
            score = score + 10000000
        end
    else
        score = -1000000 - #candidate
    end

    local info = {
        Prefix = chosenPrefix,
        Replies = totalReplies,
        NonSelfReplies = nonSelfReplies,
        SelfSolve = selfSolve,
        Minimum = 1,
        Qualified = qualified,
        Trap = perfectTrap,
        PunctuationReturn = chosenHasPunctuation,
        PunctuationTrap = punctuationTrap,
        PriorityTier = priorityTier,
        LowestEntry = qualified and not punctuationTrap and not perfectTrap,
        ProSuppressedTwoLetter = (
            #chosenPrefix == 2
            and env.WordHelperUnbeatable.ProSuppressedTwoLetter[chosenPrefix] == true
        ),
        ProPriorityTwoLetter = (
            #chosenPrefix == 2
            and env.WordHelperUnbeatable.ProPriorityTwoLetter[chosenPrefix] == true
        ),
        ProSpicyStage2TwoLetter = (
            stageNow == 2
            and #chosenPrefix == 2
            and env.WordHelperUnbeatable.ProSpicyStage2TwoLetter[chosenPrefix] == true
        ),
        Score = score,
        Stage = stageNow,
        Turn = env.WordHelperUnbeatable.CurrentTurn or 1
    }

    env.WordHelperUnbeatable.ProSortCache[candidateCacheKey] = info
    return info
end

-- V20.8.18 FAST PRO SPAM MODE (F9)
-- Performance / priority rule:
--   1) LOWEST ENTRY is deliberately ignored wherever it sits in GodmodePriority;
--   2) evaluate each literal configured spam's live Pro reply count ONCE per refresh;
--   3) cheaply scan candidates by suffix in their existing relative priority order;
--   4) if a live spam exists, analyze only the highest-priority available spam;
--   5) only when ALL literal spams are unavailable, fall back to normal deterministic
--      Pro Unbeatable (lowest live response count -> longest forced response).
env.WordHelperUnbeatable.ProSpamMode = env.WordHelperUnbeatable.ProSpamMode or false

env.WordHelperUnbeatable.SelectTopProCandidates = function(candidateList)
    local infoMap = {}
    local difficultyMap = {}
    local heap = {}
    local keepLimit = 120
    local selectedCandidates = candidateList

    -- F9 optimization: GetProBaseReplyInfo used to run from inside the heap
    -- comparator, causing thousands of repeated full-Pro availability checks.
    -- Build the live spam table once, then keep only the best available spam row.
    if env.WordHelperUnbeatable.ProSpamMode then
        local liveSpam = {}
        for index, category in ipairs(Config.GodmodePriority or {}) do
            if type(category) == "string"
                and category ~= ""
                and category ~= "__TRAP__"
                -- F9 intentionally ignores LOWEST ENTRY's editor position.
                -- Normal Pro Unbeatable is the final fallback after every literal spam.
                and category ~= "__LOWEST_ENTRY__"
                and category ~= "__X__" then
                local liveCount = env.WordHelperUnbeatable.GetProBaseReplyInfo(category)
                if (tonumber(liveCount) or 0) > 0 then
                    liveSpam[#liveSpam + 1] = {Index = index, Ending = category}
                end
            end
        end

        local bestIndex = nil
        local spamCandidates = {}
        for _, word in ipairs(candidateList) do
            for _, spam in ipairs(liveSpam) do
                local ending = spam.Ending
                if #word >= #ending and word:sub(-#ending) == ending then
                    if bestIndex == nil or spam.Index < bestIndex then
                        bestIndex = spam.Index
                        spamCandidates = {word}
                    elseif spam.Index == bestIndex then
                        spamCandidates[#spamCandidates + 1] = word
                    end
                    break
                end
            end
        end

        if bestIndex ~= nil and #spamCandidates > 0 then
            selectedCandidates = spamCandidates
        end
    end

    local function difficultyFor(word, info)
        local cached = difficultyMap[word]
        if cached then return cached[1], cached[2] end
        local len, forcedWord = env.WordHelperUnbeatable.GetProForcedReplyDifficulty(
            info and info.Prefix or "", word
        )
        difficultyMap[word] = {len, forcedWord}
        return len, forcedWord
    end

    local function better(a, b)
        local infoA = infoMap[a]
        local infoB = infoMap[b]

        -- Existing deterministic Pro hierarchy is intentionally retained here.
        -- In F9 mode selectedCandidates has already been narrowed to the single
        -- highest-priority live spam row. Therefore this comparator can focus on
        -- lowest response count -> longest forced response without repeated spam scans.
        local tierA = infoA and infoA.PriorityTier or 4
        local tierB = infoB and infoB.PriorityTier or 4

        local aSuppressed = infoA and infoA.ProSuppressedTwoLetter == true
        local bSuppressed = infoB and infoB.ProSuppressedTwoLetter == true
        if aSuppressed then tierA = 4 end
        if bSuppressed then tierB = 4 end

        if tierA ~= tierB then return tierA < tierB end

        local repliesA = infoA and infoA.NonSelfReplies or math.huge
        local repliesB = infoB and infoB.NonSelfReplies or math.huge
        if repliesA ~= repliesB then return repliesA < repliesB end

        if not env.WordHelperUnbeatable.ProSpicyRandom and repliesA < math.huge then
            local hardLenA = difficultyFor(a, infoA)
            local hardLenB = difficultyFor(b, infoB)
            if hardLenA ~= hardLenB then return hardLenA > hardLenB end
        end

        if env.WordHelperUnbeatable.ProSpicyRandom
            and (tonumber(env.WordHelperUnbeatable.Stage) or 1) == 2 then
            local aSpicy2 = infoA and infoA.ProSpicyStage2TwoLetter == true
            local bSpicy2 = infoB and infoB.ProSpicyStage2TwoLetter == true
            if aSpicy2 ~= bSpicy2 then return aSpicy2 end
        end

        local aPriority2 = infoA and infoA.ProPriorityTwoLetter == true
        local bPriority2 = infoB and infoB.ProPriorityTwoLetter == true
        if aPriority2 ~= bPriority2 then return aPriority2 end

        local prefixLenA = infoA and #(infoA.Prefix or "") or 0
        local prefixLenB = infoB and #(infoB.Prefix or "") or 0
        if prefixLenA ~= prefixLenB then return prefixLenA > prefixLenB end

        if env.WordHelperUnbeatable.ProSpicyRandom then
            local rA = env.WordHelperUnbeatable.ProSpicyRank(a)
            local rB = env.WordHelperUnbeatable.ProSpicyRank(b)
            if rA ~= rB then return rA > rB end
        end

        local sA = infoA and infoA.Score or -math.huge
        local sB = infoB and infoB.Score or -math.huge
        if sA == sB then return #a < #b end
        return sA > sB
    end

    local function heapWorse(a, b)
        return better(b, a)
    end

    local function siftUp(index)
        while index > 1 do
            local parent = math.floor(index / 2)
            if not heapWorse(heap[index], heap[parent]) then break end
            heap[index], heap[parent] = heap[parent], heap[index]
            index = parent
        end
    end

    local function siftDown(index)
        while true do
            local left = index * 2
            local right = left + 1
            local worst = index
            if left <= #heap and heapWorse(heap[left], heap[worst]) then
                worst = left
            end
            if right <= #heap and heapWorse(heap[right], heap[worst]) then
                worst = right
            end
            if worst == index then break end
            heap[index], heap[worst] = heap[worst], heap[index]
            index = worst
        end
    end

    for _, w in ipairs(selectedCandidates) do
        local info = env.WordHelperUnbeatable.GetProCandidateInfo(w)
        infoMap[w] = info

        if #heap < keepLimit then
            heap[#heap + 1] = w
            siftUp(#heap)
        elseif better(w, heap[1]) then
            heap[1] = w
            siftDown(1)
        end
    end

    table.sort(heap, better)
    return heap
end

-- V18.2 exact top-K selector. It evaluates every legal candidate so obscure
-- traps remain discoverable, but only retains the best 120 for the final sort.
env.WordHelperUnbeatable.SelectTopCandidates = function(candidateList)
    local infoMap = {}
    local heap = {}
    local keepLimit = 120
    local stage2 = (env.WordHelperUnbeatable.Stage or 1) == 2

    local function better(a, b)
        local infoA = infoMap[a]
        local infoB = infoMap[b]

        if stage2 then
            local aSuppressed = infoA and infoA.SuppressedTwoLetter == true
            local bSuppressed = infoB and infoB.SuppressedTwoLetter == true
            local aKnown = infoA and infoA.KnownTwoLetter == true and not aSuppressed
            local bKnown = infoB and infoB.KnownTwoLetter == true and not bSuppressed

            if aKnown ~= bKnown then return aKnown end
            if aSuppressed ~= bSuppressed then return not aSuppressed end
        end

        local sA = infoA and infoA.Score or -math.huge
        local sB = infoB and infoB.Score or -math.huge
        if sA == sB then return #a < #b end
        return sA > sB
    end

    local function heapWorse(a, b)
        return better(b, a)
    end

    local function siftUp(index)
        while index > 1 do
            local parent = math.floor(index / 2)
            if not heapWorse(heap[index], heap[parent]) then break end
            heap[index], heap[parent] = heap[parent], heap[index]
            index = parent
        end
    end

    local function siftDown(index)
        while true do
            local left = index * 2
            local right = left + 1
            local worst = index
            if left <= #heap and heapWorse(heap[left], heap[worst]) then worst = left end
            if right <= #heap and heapWorse(heap[right], heap[worst]) then worst = right end
            if worst == index then break end
            heap[index], heap[worst] = heap[worst], heap[index]
            index = worst
        end
    end

    for _, w in ipairs(candidateList) do
        local info = env.WordHelperUnbeatable.GetCandidateInfo(w)
        infoMap[w] = info
        env.WordHelperUnbeatable.SortCache[w] = info

        if #heap < keepLimit then
            heap[#heap + 1] = w
            siftUp(#heap)
        elseif better(w, heap[1]) then
            heap[1] = w
            siftDown(1)
        end
    end

    table.sort(heap, better)
    return heap
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

                    -- Each configured Godmode priority gets an independent tail quota.
                    -- A lower-priority ending encountered earlier alphabetically cannot
                    -- crowd a later higher-priority ending out of the candidate pool.
                    local tailPriorityAddedByIndex = {}
                    local tailPerPriorityLimit = 90
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
                        elseif sortMode == "Unbeatable" or sortMode == "Pro Unbeatable" then
                            checkWord(w)
                            count = count + 1
                        elseif sortMode == "Godmode" then
                            -- Cheap tail scan only: LOWEST ENTRY is intentionally excluded
                            -- and handled later by its lazy dedicated search.
                            local canAddPriority, priorityIndex, isTrapPriority =
                                GodmodeMatchesConfiguredPriority(w)

                            local priorityCount = priorityIndex
                                and (tailPriorityAddedByIndex[priorityIndex] or 0)
                                or 0

                            if canAddPriority
                                and (isTrapPriority or priorityCount < tailPerPriorityLimit)
                                and not seenExact[w]
                                and not Blacklist[w]
                                and (not UsedWords[w] or Config.ShowUsedWords)
                                and (suffixMode == "" or w:sub(-#suffixMode) == suffixMode)
                                and (lengthMode == 0 or tryFallbackLengths or #w == lengthMode) then

                                table.insert(exacts, w)
                                seenExact[w] = true

                                if priorityIndex and not isTrapPriority then
                                    tailPriorityAddedByIndex[priorityIndex] = priorityCount + 1
                                end
                            end
                        elseif sortMode ~= "Godmode"
                            and sortMode ~= "Unbeatable"
                            and sortMode ~= "Pro Unbeatable" then
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
            
            if sortMode == "Godmode" then
                exacts = GodmodePrepareLowestEntry(
                    exacts,
                    bucket,
                    prefix,
                    tryFallbackLengths
                )
            end

            -- V20.7: while Pro Unbeatable is selected, merge the current Pro
            -- dictionary delta into the Casual candidate pool without contaminating
            -- any other mode. Punctuation spellings are preserved exactly.
            if sortMode == "Pro Unbeatable" then
                local alreadyAdded = {}
                for _, existing in ipairs(exacts) do
                    alreadyAdded[existing] = true
                end

                local deltaBucket = env.WordHelperUnbeatable.ProDictionaryDeltaBuckets[firstChar] or {}
                local deltaStart = 1
                if #prefix > 0 then
                    local found = BinarySearchStart(deltaBucket, prefix)
                    if found ~= -1 then
                        deltaStart = found
                    else
                        deltaStart = #deltaBucket + 1
                    end
                end

                for i = deltaStart, #deltaBucket do
                    local proWord = deltaBucket[i]
                    if #prefix > 0 and proWord:sub(1, #prefix) ~= prefix then
                        break
                    end

                    if not alreadyAdded[proWord]
                        and not env.WordHelperUnbeatable.IsProWordUnavailable(proWord)
                        and (suffixMode == "" or proWord:sub(-#suffixMode) == suffixMode)
                        and (lengthMode == 0 or tryFallbackLengths or #proWord == lengthMode) then
                        table.insert(exacts, proWord)
                        alreadyAdded[proWord] = true
                    end
                end

                -- Keep future manually-added Pro words as a tiny overlay.
                for _, proWord in ipairs(env.WordHelperUnbeatable.ProExclusiveWords) do
                    if not alreadyAdded[proWord]
                        and not env.WordHelperUnbeatable.IsProWordUnavailable(proWord)
                        and (suffixMode == "" or proWord:sub(-#suffixMode) == suffixMode)
                        and (lengthMode == 0 or tryFallbackLengths or #proWord == lengthMode) then

                        local proMatchLen = GetMatchLength(proWord, prefix)
                        if proMatchLen == #prefix then
                            table.insert(exacts, proWord)
                            alreadyAdded[proWord] = true
                        end
                    end
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
        elseif sortMode == "Unbeatable" then
            env.WordHelperUnbeatable.SyncStageFromUsedWords()
            matches = env.WordHelperUnbeatable.SelectTopCandidates(matches)

        elseif sortMode == "Pro Unbeatable" then
            env.WordHelperUnbeatable.SyncStageFromUsedWords()
            matches = env.WordHelperUnbeatable.SelectTopProCandidates(matches)

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
                local categoryTag, _, _, lowestInfo = GodmodeGetPriorityCategory(w)

                if categoryTag == "LOWEST ENTRY" and lowestInfo then
                    displayText = displayText
                        .. "  <font color=\"rgb(150,150,160)\">[LOWEST ENTRY -> "
                        .. lowestInfo.Prefix:upper()
                        .. " / "
                        .. tostring(lowestInfo.NonSelfReplies)
                        .. " NONSELF]</font>"
                elseif categoryTag ~= "" then
                    displayText = displayText
                        .. "  <font color=\"rgb(150,150,160)\">["
                        .. categoryTag
                        .. "]</font>"
                end
            elseif sortMode == "Unbeatable" then
                local ub = env.WordHelperUnbeatable.GetCandidateInfo(w)
                local prefixTag = ub.Prefix ~= "" and ub.Prefix:upper() or "FALLBACK"
                local detail = "T" .. tostring(ub.Turn or 1)
                    .. " S" .. tostring(ub.Stage)
                    .. " -> " .. prefixTag
                if ub.Qualified then
                    detail = detail
                        .. " / " .. tostring(ub.Replies) .. "R"
                        .. " / MIN" .. tostring(ub.Minimum)
                else
                    detail = detail .. " / ANY FALLBACK"
                end
                if ub.SelfSolve then detail = detail .. " / SELF" end
                if ub.Trap then detail = detail .. " / PERFECT" end
                if ub.KnownTwoLetter then detail = detail .. " / KNOWN2" end
                displayText = displayText
                    .. "  <font color=\"rgb(150,150,160)\">["
                    .. detail
                    .. "]</font>"
            elseif sortMode == "Pro Unbeatable" then
                local pro = env.WordHelperUnbeatable.GetProCandidateInfo(w)
                local prefixTag = pro.Prefix ~= "" and pro.Prefix:upper() or "FALLBACK"
                local detail = "PRO T" .. tostring(pro.Turn or 1)
                    .. " S" .. tostring(pro.Stage)
                    .. " -> " .. prefixTag

                if pro.Qualified then
                    detail = detail
                        .. " / " .. tostring(pro.NonSelfReplies) .. " SOLVE"
                    if pro.NonSelfReplies ~= 1 then
                        detail = detail .. "S"
                    end
                    if pro.SelfSolve then
                        detail = detail .. " / +" .. "SELF"
                    end
                else
                    detail = detail .. " / ANY FALLBACK"
                end

                if pro.PunctuationTrap then
                    detail = detail .. " / PUNCT-TRAP"
                elseif pro.Trap then
                    detail = detail .. " / PERFECT1"
                elseif pro.LowestEntry then
                    detail = detail .. " / LOWEST ENTRY"
                end
                if pro.ProSpicyStage2TwoLetter and env.WordHelperUnbeatable.ProSpicyRandom then
                    detail = detail .. " / 2L-SPICY"
                elseif pro.ProPriorityTwoLetter then
                    detail = detail .. " / 2L-PRIORITY"
                end
                if pro.ProSuppressedTwoLetter then
                    detail = detail .. " / 2L-FALLBACK"
                end

                displayText = displayText
                    .. "  <font color=\"rgb(150,150,160)\">["
                    .. detail
                    .. "]</font>"
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

    -- Clear packet proof from any previous attempt. The next rejection is only
    -- trusted if packet 26 independently reports this same exact word.
    env.WordHelperBlacklistTracker.LastPacketSubmittedWord = ""
    env.WordHelperBlacklistTracker.LastPacketSubmittedAt = 0

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

    -- SoundService.Game.Wrong is global, so a Wrong sound by itself is NEVER
    -- enough to blacklist our last submitted word.  The old packet-only fix was
    -- safe against many false positives, but rejected answers do not always
    -- produce the same packet-26 ChatBubble proof as accepted submissions.
    --
    -- New rule: at the exact instant Wrong fires, the normal game UI must still
    -- visibly show OUR turn and CurrentWord must still be the exact word that we
    -- armed on Enter.  Packet 26 remains useful corroboration when it exists, but
    -- it is no longer mandatory for a genuine local rejection.
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
        return
    end

    -- IMPORTANT: use the visible Type label directly here instead of GetTurnInfo.
    -- GetTurnInfo intentionally has a log fallback whose required-letter cache can
    -- outlive the visible turn.  That is useful elsewhere, but unsafe for tying a
    -- GLOBAL Wrong sound to a specific player's attempt.
    local player = Players.LocalPlayer
    local gui = player and player:FindFirstChild("PlayerGui")
    local inGame = gui and gui:FindFirstChild("InGame")
    local frame = inGame and inGame:FindFirstChild("Frame")
    local typeLbl = frame and frame:FindFirstChild("Type")
    local typeText =
        (typeLbl and typeLbl:IsA("TextLabel"))
        and tostring(typeLbl.Text or "")
        or ""

    local visiblyMyTurn = false
    if player and typeText ~= "" then
        visiblyMyTurn =
            typeText:sub(1, #player.Name) == player.Name
            or typeText:sub(1, #player.DisplayName) == player.DisplayName
    end

    local visibleAttempt = ""
    if frame then
        visibleAttempt = tostring(select(1, GetCurrentGameWord(frame)) or "")
            :lower():gsub("[^a-z]", "")
    end

    local localRejectionMatches =
        visiblyMyTurn
        and visibleAttempt == pendingWord
        and (now - pendingAt) <= 1.10

    if not localRejectionMatches then
        -- Do NOT clear a fresh pending attempt merely because somebody else's
        -- global Wrong sound fired.  It will either be replaced by the next Enter
        -- or expire naturally through BeginAttempt's rejection window.
        if StatusText then
            StatusText.Text = "Ignored unrelated Wrong sound"
            StatusText.TextColor3 = THEME.SubText
        end
        return
    end

    -- Give packet 26 a moment to arrive.  It is corroborating evidence only; the
    -- local visible-turn + exact CurrentWord match above is the rejection proof.
    task.delay(0.12, function()
        if unloaded then return end

        -- Do not let a newer Enter attempt inherit an older Wrong callback.
        local livePending =
            tostring(env.WordHelperBlacklistTracker.PendingWord or "")
                :lower():gsub("[^a-z]", "")
        local livePendingAt =
            tonumber(env.WordHelperBlacklistTracker.PendingAt or 0) or 0
        if livePending ~= pendingWord or math.abs(livePendingAt - pendingAt) > 0.001 then
            return
        end

        local packetWord =
            tostring(env.WordHelperBlacklistTracker.LastPacketSubmittedWord or "")
                :lower():gsub("[^a-z]", "")
        local packetAt =
            tonumber(env.WordHelperBlacklistTracker.LastPacketSubmittedAt or 0) or 0
        local packetMatches =
            packetWord == pendingWord
            and packetAt > 0
            and packetAt >= (pendingAt - 0.10)
            and (tick() - packetAt) <= 1.25

        if Blacklist[pendingWord] or UsedWords[pendingWord] then
            env.WordHelperBlacklistTracker.ClearPending()
            return
        end

        -- Re-check the rejection proof AFTER the short delay. A successful fast
        -- submission can race with the global Wrong sound; if the turn has advanced
        -- or CurrentWord no longer shows the exact attempt, it was not our rejection.
        local livePlayer = Players.LocalPlayer
        local liveGui = livePlayer and livePlayer:FindFirstChild("PlayerGui")
        local liveInGame = liveGui and liveGui:FindFirstChild("InGame")
        local liveFrame = liveInGame and liveInGame:FindFirstChild("Frame")
        local liveType = liveFrame and liveFrame:FindFirstChild("Type")
        local liveTypeText = (liveType and liveType:IsA("TextLabel"))
            and tostring(liveType.Text or "") or ""
        local stillMyTurn = livePlayer and (
            liveTypeText:sub(1, #livePlayer.Name) == livePlayer.Name
            or liveTypeText:sub(1, #livePlayer.DisplayName) == livePlayer.DisplayName
        )
        local liveVisibleAttempt = ""
        if liveFrame then
            liveVisibleAttempt = tostring(select(1, GetCurrentGameWord(liveFrame)) or "")
                :lower():gsub("[^a-z]", "")
        end
        if not stillMyTurn or liveVisibleAttempt ~= pendingWord then
            env.WordHelperBlacklistTracker.ClearPending()
            return
        end

        if not env.WordHelperBlacklistTracker.IsKnownWord(pendingWord) then
            env.WordHelperBlacklistTracker.ClearPending()
            if ShowToast then
                ShowToast("Rejected capture skipped - not in dictionary: " .. pendingWord, "warning")
            end
            return
        end

        local proof = packetMatches
            and "visible local rejection + exact packet match"
            or "visible local rejection (packet optional)"

        local added = env.WordHelperBlacklistTracker.Add(
            pendingWord,
            proof .. " + SoundService.Game.Wrong via " .. tostring(source or "sound")
        )

        env.WordHelperBlacklistTracker.ClearPending()

        if added and StatusText then
            StatusText.Text = "Blacklisted from rejection: " .. pendingWord
            StatusText.TextColor3 = THEME.Warning
        end
    end)
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
            and (tick() - cachedAt) <= 0.55 then
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
    lobbySeenSince = 0,
    matchBreakSince = 0,
    pendingMatchReset = false,
    ActivePrompt = "",
    ActivePromptTypeText = ""
}

-- V20.8.7 SERVER-ONLY USED-WORD TRACKING
-- Accepted words are now sourced exclusively from the server-confirmed packet path.
-- CurrentWord remains available elsewhere for prefix/stage/UI functions, but it no
-- longer has authority to add anything to UsedWords.

env.WordHelperUsedTracker.IsKnownDictionaryWord = function(word)
    -- V20.8.15: preserve apostrophes/hyphens. %c is NOT appropriate here because
    -- punctuation is part of the canonical identity of many Pro words.
    word = tostring(word or ""):lower():gsub("%s+", "")
    if #word < 2 then return false end

    if WordHelperKnownWords[word] == true then
        return true
    end
    if env.WordHelperUnbeatable
        and env.WordHelperUnbeatable.ProDictionaryDeltaSet
        and env.WordHelperUnbeatable.ProDictionaryDeltaSet[word] then
        return true
    end
    if env.WordHelperUnbeatable
        and env.WordHelperUnbeatable.ProExclusiveSet
        and env.WordHelperUnbeatable.ProExclusiveSet[word] then
        return true
    end

    -- Fallback only for observers that genuinely lose punctuation. Use a
    -- canonical spelling only when the normalized Pro identity is unique.
    local norm = word:gsub("[^a-z]", "")
    return env.WordHelperUnbeatable
        and env.WordHelperUnbeatable.ProDictionaryNormalizedUnique
        and env.WordHelperUnbeatable.ProDictionaryNormalizedUnique[norm] ~= nil
end

env.WordHelperUsedTracker.NormalizedUsed = env.WordHelperUsedTracker.NormalizedUsed or {}

env.WordHelperUsedTracker.RecordObservedUsedWord = function(word, serverConfirmed)
    -- V20.8.7: only the authoritative Packet 26 -> AnswerResults path may mark USED.
    if serverConfirmed ~= true then return end
    -- Preserve punctuation exactly from the authoritative server answer.
    word = tostring(word or ""):lower():gsub("%s+", "")
    if #word < 2 then return end

    local storedWord = word

    -- V20.8.14: resolve a server-confirmed word against the full Pro dictionary
    -- BEFORE the known-word gate, including punctuation-normalized Pro entries.
    if sortMode == "Pro Unbeatable"
        and env.WordHelperUnbeatable
        and env.WordHelperUnbeatable.ProDictionaryNormalizedUnique then
        local norm = storedWord:gsub("[^a-z]", "")
        local canonical = env.WordHelperUnbeatable.ProDictionaryNormalizedUnique[norm]
        if canonical then storedWord = canonical end
    end

    if not env.WordHelperUsedTracker.IsKnownDictionaryWord(storedWord) then return end

    -- If punctuation was lost upstream and the normalized identity uniquely maps
    -- to a Pro spelling, store ONLY that canonical spelling. This prevents one
    -- punctuation answer from being counted twice by the stage checker.
    if not WordHelperKnownWords[storedWord]
        and not (env.WordHelperUnbeatable.ProDictionaryDeltaSet
            and env.WordHelperUnbeatable.ProDictionaryDeltaSet[storedWord])
        and not (env.WordHelperUnbeatable.ProExclusiveSet
            and env.WordHelperUnbeatable.ProExclusiveSet[storedWord]) then
        local norm = storedWord:gsub("[^a-z]", "")
        local canonical = env.WordHelperUnbeatable.ProDictionaryNormalizedUnique
            and env.WordHelperUnbeatable.ProDictionaryNormalizedUnique[norm]
        if canonical then storedWord = canonical end
    end

    if UsedWords[storedWord] then return end
    UsedWords[storedWord] = true
    env.WordHelperUsedTracker.NormalizedUsed[storedWord:gsub("[^a-z]", "")] = true
    env.WordHelperUsedTracker.LastRecordedWord = storedWord
    env.WordHelperUsedTracker.LastRecordedSource =
        "Server AnswerResults"
    env.WordHelperUsedTracker.LastRecordedAt = tick()
    -- The authoritative accepted-word signal ends any long-word display pin.
    if env.WordHelperLongWord then
        env.WordHelperLongWord.Reset()
    end

    -- Positive acceptance beats an older learned rejection. If the observer sees
    -- the game advance after this exact word, automatically restore it.
    if Blacklist[storedWord] then
        Blacklist[storedWord] = nil
        env.WordHelperBlacklistTracker.LiveBlacklist = Blacklist
        env.WordHelperBlacklistTracker.Save()
        if env.WordHelperBlacklistTracker.Refresh then
            pcall(env.WordHelperBlacklistTracker.Refresh)
        end
    end

    if env.WordHelperUnbeatable then
        if env.WordHelperUnbeatable.AdjustUnavailableWord and not Blacklist[storedWord] then
            env.WordHelperUnbeatable.AdjustUnavailableWord(storedWord, 1)
        end
        if env.WordHelperUnbeatable.AdjustProDeltaUnavailableWord and not Blacklist[storedWord] then
            env.WordHelperUnbeatable.AdjustProDeltaUnavailableWord(storedWord, 1)
        end

        local pv = env.WordHelperUnbeatable.PrefixVersion
        for n = 1, math.min(4, #storedWord) do
            local p = storedWord:sub(1, n)
            pv[p] = (pv[p] or 0) + 1
        end
        if env.WordHelperUnbeatable.SyncStageFromUsedWords then
            env.WordHelperUnbeatable.SyncStageFromUsedWords()
        end
    end
    -- Pro ranking caches must never survive a newly accepted/used word.
    if env.WordHelperUnbeatable then
        env.WordHelperUnbeatable.ProForcedReplyCache = {}
        env.WordHelperUnbeatable.SortCache = {}
    end
    forceUpdateList = true
    lastDetected = "---"
end
local lastRequiredLetter = ""

-- Manual used-word reset. F6 calls this so a new game can start immediately
-- without waiting for the automatic round/lobby detector.
env.WordHelperUsedTracker.ClearUsedWords = function(showNotification)
    table.clear(UsedWords)
    if env.WordHelperUsedTracker.NormalizedUsed then
        table.clear(env.WordHelperUsedTracker.NormalizedUsed)
    end
    if env.WordHelperLongWord then env.WordHelperLongWord.Reset() end
    if env.WordHelperUnbeatable and env.WordHelperUnbeatable.ResetStage then
        env.WordHelperUnbeatable.ResetStage()
    end
    if env.WordHelperUnbeatable and env.WordHelperUnbeatable.RebuildUnavailablePrefixCount then
        env.WordHelperUnbeatable.RebuildUnavailablePrefixCount()
    end
    if env.WordHelperUnbeatable and env.WordHelperUnbeatable.RebuildProDeltaUnavailable then
        env.WordHelperUnbeatable.RebuildProDeltaUnavailable()
    end
    env.WordHelperUsedTracker.observedWord = ""
    env.WordHelperUsedTracker.observedWordSince = 0
    env.WordHelperUsedTracker.inactiveSince = 0
    env.WordHelperUsedTracker.lobbySeenSince = 0
    env.WordHelperUsedTracker.ActivePrompt = ""
    env.WordHelperUsedTracker.ActivePromptTypeText = ""

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

-- Automatic between-life match reset.  This intentionally has no toast and no
-- deferred UpdateList call: it runs inside the live observer and should be as cheap
-- as possible.  A fresh match gets a fresh UsedWords pool and Unbeatable turn 1.
env.WordHelperUsedTracker.ResetForNewMatch = function()
    table.clear(UsedWords)
    if env.WordHelperLongWord then env.WordHelperLongWord.Reset() end
    if env.WordHelperUnbeatable and env.WordHelperUnbeatable.ResetStage then
        env.WordHelperUnbeatable.ResetStage()
    end

    env.WordHelperUsedTracker.observedWord = ""
    env.WordHelperUsedTracker.observedWordSince = 0
    env.WordHelperUsedTracker.inactiveSince = 0
    env.WordHelperUsedTracker.lobbySeenSince = 0
    env.WordHelperUsedTracker.matchBreakSince = 0
    env.WordHelperUsedTracker.pendingMatchReset = false
    env.WordHelperUsedTracker.ActivePrompt = ""
    env.WordHelperUsedTracker.ActivePromptTypeText = ""

    GodmodeReplyAvailabilityCache = {}
    currentBestMatch = nil
    forceUpdateList = true
    lastDetected = "---"

    if StatusText then
        StatusText.Text = "New Match - Unbeatable Stage 1"
        StatusText.TextColor3 = THEME.Success
    end
end

-- V17.2 register fix: this chunk is already at Luau's 200-local limit.
-- Keep the stats widgets in the shared environment instead of allocating four
-- more long-lived/local registers at the bottom of the main chunk.
env.WordHelperStatsData = env.WordHelperStatsData or {}
StatsData = env.WordHelperStatsData

StatsData.Frame = Instance.new("Frame")
StatsData.Frame.Name = "StatsFrame"
StatsData.Frame.Size = UDim2.new(0, 120, 0, 60)
StatsData.Frame.Position = UDim2.new(0.5, -60, 0, 10)
StatsData.Frame.BackgroundColor3 = THEME.Background
StatsData.Frame.Visible = false
StatsData.Frame.Parent = ScreenGui
EnableDragging(StatsData.Frame)
Instance.new("UICorner", StatsData.Frame).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", StatsData.Frame).Color = THEME.Accent

StatsData.Timer = Instance.new("TextLabel")
StatsData.Timer.Size = UDim2.new(1, 0, 0, 25)
StatsData.Timer.Position = UDim2.new(0, 0, 0, 5)
StatsData.Timer.BackgroundTransparency = 1
StatsData.Timer.TextColor3 = THEME.Text
StatsData.Timer.Font = Enum.Font.GothamBold
StatsData.Timer.TextSize = 20
StatsData.Timer.Text = "--"
StatsData.Timer.Parent = StatsData.Frame

StatsData.Count = Instance.new("TextLabel")
StatsData.Count.Size = UDim2.new(1, 0, 0, 20)
StatsData.Count.Position = UDim2.new(0, 0, 0, 30)
StatsData.Count.BackgroundTransparency = 1
StatsData.Count.TextColor3 = THEME.SubText
StatsData.Count.Font = Enum.Font.Gotham
StatsData.Count.TextSize = 12
StatsData.Count.Text = "Words: 0"
StatsData.Count.Parent = StatsData.Frame

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

        -- A life loss ends the current match but does NOT necessarily return the
        -- player to the lobby.  During that short transition Last Letter drops its
        -- active timer/type/word state, then the next match starts again at a
        -- one-letter prefix.  Do not reset merely because a 1-letter prefix appears:
        -- late-game 4 -> 3 -> 2 -> 1 fallback is valid.  Require the real quiet gap
        -- first, then a fresh one-letter opening.
        local cleanRequiredForReset = tostring(requiredLetter or ""):lower():gsub("[^a-z]", "")
        local resumedGameplay = isVisible and (seconds ~= nil or isMyTurn or cleanRequiredForReset ~= "")
        if env.WordHelperUsedTracker.pendingMatchReset
            and resumedGameplay
            and #cleanRequiredForReset == 1 then
            env.WordHelperUsedTracker.ResetForNewMatch()
        end

        if isVisible and isMyTurn and requiredLetter and #requiredLetter > 0 then
            env.WordHelperUnbeatable.ObservePrefix(requiredLetter)
        end
        
        -- V20.7.2 FAST USED-WORD CAPTURE:
        -- Sample CurrentWord every rendered frame instead of only every 50 ms.
        -- Fast players can submit a complete answer and advance the turn inside
        -- the old polling window, which meant the final accepted spelling was
        -- never seen and therefore never entered into UsedWords.  RenderStepped
        -- already bounds this to the client's frame rate, so no extra loop is
        -- introduced here.  Acceptance is STILL committed only by the existing
        -- turn/Type transition logic below; faster sampling does not mark typed
        -- but rejected words as used.
        -- V20.8.11: Last Letter uses a literal "..." overflow tile for long words.
        -- Preserve the previous full prefix before reading the new sliding window.
        env.WordHelperLongWord.PreviousDetected = cachedDetected or ""
        cachedDetected, cachedCensored = GetCurrentGameWord(frame)

        if not cachedCensored and env.WordHelperLongWord then
            if env.WordHelperLongWord.ReconstructSliding then
                cachedDetected = env.WordHelperLongWord.ReconstructSliding(
                    env.WordHelperLongWord.PreviousDetected,
                    cachedDetected
                )
            end
            if env.WordHelperLongWord.Resolve then
                cachedDetected = env.WordHelperLongWord.Resolve(
                    cachedDetected,
                    requiredLetter
                )
            end
        end
        lastWordCheck = now
        local detected, censored = cachedDetected, cachedCensored

        if isVisible and isMyTurn and not env.WordHelperUnbeatable.WasMyTurn
            and detected and detected ~= "" and not censored then
            env.WordHelperUnbeatable.ObservePrefix(detected)
        end
        env.WordHelperUnbeatable.WasMyTurn = isVisible and isMyTurn

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

        -- V20.8.7: no CurrentWord/Type-transition UsedWords fallback.
        -- Only server-confirmed AnswerResults packets can mark an accepted word USED.

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
                if env.WordHelperUnbeatable and env.WordHelperUnbeatable.ResetStage then
                    env.WordHelperUnbeatable.ResetStage()
                end
                env.WordHelperUsedTracker.observedWord = ""
                env.WordHelperUsedTracker.observedWordSince = 0
                env.WordHelperUsedTracker.roundHadActivity = false
                env.WordHelperUsedTracker.inactiveSince = 0
                env.WordHelperUsedTracker.lobbySeenSince = 0
                env.WordHelperUsedTracker.matchBreakSince = 0
                env.WordHelperUsedTracker.pendingMatchReset = false
                StatusText.Text = "New Game Ready - Used Words Cleared"
                StatusText.TextColor3 = THEME.Success
                forceUpdateList = true
            end
        else
            env.WordHelperUsedTracker.lobbySeenSince = 0
        end

        -- Track genuine match activity. The InGame GUI can stay visible after a match,
        -- so visibility alone is not a reliable reset signal.
        local hasMatchActivity = seconds ~= nil or typeVisible or detected ~= "" or isMyTurn
        if hasMatchActivity then
            env.WordHelperUsedTracker.roundHadActivity = true
            env.WordHelperUsedTracker.inactiveSince = 0
            env.WordHelperUsedTracker.matchBreakSince = 0
        elseif env.WordHelperUsedTracker.roundHadActivity then
            if env.WordHelperUsedTracker.inactiveSince == 0 then
                env.WordHelperUsedTracker.inactiveSince = now
            end

            -- A between-life transition is shorter than the full game-over pause.
            -- Arm a reset after a genuine quiet gap, but do not execute it until the
            -- next match visibly resumes on its one-letter opening prefix.
            if env.WordHelperUsedTracker.matchBreakSince == 0 then
                env.WordHelperUsedTracker.matchBreakSince = now
            elseif (now - env.WordHelperUsedTracker.matchBreakSince) >= 0.60
                and UnbeatableCountUsedWords() > 0 then
                env.WordHelperUsedTracker.pendingMatchReset = true
            end

            if (now - env.WordHelperUsedTracker.inactiveSince) >= 2.5 then
                table.clear(UsedWords)
                if env.WordHelperUnbeatable and env.WordHelperUnbeatable.ResetStage then
                    env.WordHelperUnbeatable.ResetStage()
                end
                env.WordHelperUsedTracker.observedWord = ""
                env.WordHelperUsedTracker.observedWordSince = 0
                env.WordHelperUsedTracker.roundHadActivity = false
                env.WordHelperUsedTracker.inactiveSince = 0
                env.WordHelperUsedTracker.matchBreakSince = 0
                env.WordHelperUsedTracker.pendingMatchReset = false
                StatusText.Text = "Game Over - Used Words Cleared"
                StatusText.TextColor3 = THEME.Success
                forceUpdateList = true
            end
        end

        -- Keep the original GUI-close reset as an immediate fallback.
        if env.WordHelperUsedTracker.wasRoundVisible and not isVisible and env.WordHelperUsedTracker.roundHadActivity then
            table.clear(UsedWords)
            if env.WordHelperUnbeatable and env.WordHelperUnbeatable.ResetStage then
                env.WordHelperUnbeatable.ResetStage()
            end
            env.WordHelperUsedTracker.observedWord = ""
            env.WordHelperUsedTracker.observedWordSince = 0
            env.WordHelperUsedTracker.roundHadActivity = false
            env.WordHelperUsedTracker.inactiveSince = 0
            env.WordHelperUsedTracker.matchBreakSince = 0
            env.WordHelperUsedTracker.pendingMatchReset = false
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

    if input.KeyCode == Enum.KeyCode.F9 then
        if sortMode ~= "Pro Unbeatable" then
            if ShowToast then
                ShowToast("Pro Spam Mode only works in Pro Unbeatable", "warning")
            end
            if StatusText then
                StatusText.Text = "F9 Spam: Pro Unbeatable only"
                StatusText.TextColor3 = THEME.Warning
            end
            return
        end

        env.WordHelperUnbeatable.ProSpamMode =
            not env.WordHelperUnbeatable.ProSpamMode
        env.WordHelperUnbeatable.ProSortCache = {}
        env.WordHelperUnbeatable.ProForcedReplyCache = {}
        currentBestMatch = nil
        forceUpdateList = true
        lastDetected = "---"

        if ShowToast then
            ShowToast(
                env.WordHelperUnbeatable.ProSpamMode
                    and "Pro Spam: ON / LOWEST ENTRY = final fallback"
                    or "Pro Spam Mode: OFF (F9)",
                env.WordHelperUnbeatable.ProSpamMode and "success" or "warning"
            )
        end
        if StatusText then
            StatusText.Text = env.WordHelperUnbeatable.ProSpamMode
                and "Pro Spam: ON / all spams -> Pro lowest-response fallback"
                or "Pro Spam Mode: OFF (F9)"
            StatusText.TextColor3 = env.WordHelperUnbeatable.ProSpamMode
                and THEME.Success or THEME.Warning
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.F8 then
        if sortMode ~= "Pro Unbeatable" then
            if ShowToast then
                ShowToast("Spicy Randomizer only works in Pro Unbeatable", "warning")
            end
            if StatusText then
                StatusText.Text = "F8 Spicy: Pro Unbeatable only"
                StatusText.TextColor3 = THEME.Warning
            end
            return
        end

        env.WordHelperUnbeatable.ProSpicyRandom = not env.WordHelperUnbeatable.ProSpicyRandom
        env.WordHelperUnbeatable.ProSpicySeed = math.random(1, 2147483000)
        env.WordHelperUnbeatable.ProSortCache = {}
        currentBestMatch = nil
        forceUpdateList = true
        lastDetected = "---"
        if ShowToast then
            ShowToast(
                env.WordHelperUnbeatable.ProSpicyRandom
                    and "Pro Spicy Randomizer: ON (F8) / Stage 2 trap bank active"
                    or "Pro Spicy Randomizer: OFF (F8)",
                env.WordHelperUnbeatable.ProSpicyRandom and "success" or "warning"
            )
        end
        if StatusText then
            StatusText.Text = env.WordHelperUnbeatable.ProSpicyRandom
                and "Pro Spicy Randomizer: ON (F8)"
                or "Pro Spicy Randomizer: OFF (F8)"
            StatusText.TextColor3 = env.WordHelperUnbeatable.ProSpicyRandom
                and THEME.Success or THEME.Warning
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.F7 then
        env.WordHelperUIDebugger.Start()
        return
    end

    if input.KeyCode == Enum.KeyCode.F5 then
        if env.WordHelperUnbeatable and env.WordHelperUnbeatable.ResetPrefixCounter then
            env.WordHelperUnbeatable.ResetPrefixCounter()
            if StatusText then
                StatusText.Text = "Prefix Reset: Turn 1 / Stage 1 (F5)"
                StatusText.TextColor3 = THEME.Success
            end
        end
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
    pcall(function() writefile(WORDHELPER_FILE, WORDHELPER_SOURCE) end)
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
