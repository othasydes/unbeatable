-- Last Letter acceptance-signal diagnostic
-- PASSIVE ONLY: observes client-visible UI/state/RemoteEvents. It never fires a RemoteEvent.
-- Run during a match, play several accepted + rejected words, then send WordHelper_Acceptance_Diagnostic.txt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local LP = Players.LocalPlayer
local START = os.clock()
local LOGFILE = "WordHelper_Acceptance_Diagnostic.txt"
local lines = {}
local conns = {}
local hooked = {}
local last = {}

local function clean(v)
    local ok, s = pcall(function()
        if typeof(v) == "Instance" then return v:GetFullName() end
        if typeof(v) == "table" then return HttpService:JSONEncode(v) end
        return tostring(v)
    end)
    s = ok and s or "<unprintable>"
    s = s:gsub("[\r\n]+", " ")
    if #s > 220 then s = s:sub(1,217) .. "..." end
    return s
end

local function path(obj)
    local ok, p = pcall(function() return obj:GetFullName() end)
    return ok and p or tostring(obj)
end

local function log(kind, obj, detail)
    local line = string.format("[%09.3f] %-10s %-90s %s", os.clock()-START, kind, obj and path(obj) or "-", detail or "")
    table.insert(lines, line)
    print("[WH-DIAG] " .. line)
    if writefile then pcall(writefile, LOGFILE, table.concat(lines, "\n")) end
end

local function add(conn) table.insert(conns, conn) end

local function hookRemote(obj)
    if hooked[obj] or not obj:IsA("RemoteEvent") then return end
    hooked[obj] = true
    local ok, conn = pcall(function()
        return obj.OnClientEvent:Connect(function(...)
            local args = table.pack(...)
            local out = {}
            for i=1, math.min(args.n, 12) do out[#out+1] = clean(args[i]) end
            log("REMOTE", obj, "args=[" .. table.concat(out, " | ") .. "]")
        end)
    end)
    if ok and conn then add(conn) end
end

local function interestingName(obj)
    local n = obj.Name:lower()
    return n:find("word",1,true) or n:find("answer",1,true) or n:find("accept",1,true)
        or n:find("correct",1,true) or n:find("type",1,true) or n:find("choice",1,true)
        or n:find("timer",1,true) or n:find("turn",1,true) or n:find("player",1,true)
        or n:find("round",1,true) or n:find("result",1,true)
end

local function emitProp(obj, prop)
    local ok, v = pcall(function() return obj[prop] end)
    if not ok then return end
    local key = path(obj) .. "::" .. prop
    local s = clean(v)
    if last[key] == s then return end
    last[key] = s
    log("UI/STATE", obj, prop .. "=" .. s)
end

local function hookState(obj)
    if hooked[obj] then return end
    if obj:IsA("RemoteEvent") then hookRemote(obj); return end
    if not interestingName(obj) then return end
    hooked[obj] = true

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        emitProp(obj, "Text")
        add(obj:GetPropertyChangedSignal("Text"):Connect(function() emitProp(obj,"Text") end))
        add(obj:GetPropertyChangedSignal("Visible"):Connect(function() emitProp(obj,"Visible") end))
    elseif obj:IsA("BoolValue") or obj:IsA("StringValue") or obj:IsA("IntValue") or obj:IsA("NumberValue") or obj:IsA("ObjectValue") then
        emitProp(obj, "Value")
        add(obj:GetPropertyChangedSignal("Value"):Connect(function() emitProp(obj,"Value") end))
    elseif obj:IsA("GuiObject") then
        emitProp(obj, "Visible")
        add(obj:GetPropertyChangedSignal("Visible"):Connect(function() emitProp(obj,"Visible") end))
    end

    local ok, attrs = pcall(function() return obj:GetAttributes() end)
    if ok then
        for k,v in pairs(attrs) do log("ATTRIBUTE", obj, k .. "=" .. clean(v)) end
        add(obj.AttributeChanged:Connect(function(k)
            log("ATTRIBUTE", obj, k .. "=" .. clean(obj:GetAttribute(k)))
        end))
    end
end

-- All replicated server -> client RemoteEvents are high-value acceptance candidates.
for _,obj in ipairs(ReplicatedStorage:GetDescendants()) do hookRemote(obj) end
add(ReplicatedStorage.DescendantAdded:Connect(function(obj)
    hookRemote(obj)
    hookState(obj)
end))

-- Observe likely game-state values in ReplicatedStorage.
for _,obj in ipairs(ReplicatedStorage:GetDescendants()) do hookState(obj) end

local function hookPlayerGui()
    local pg = LP:FindFirstChildOfClass("PlayerGui") or LP:WaitForChild("PlayerGui",10)
    if not pg then return end
    local inGame = pg:FindFirstChild("InGame")
    if inGame then
        log("INFO", inGame, "InGame UI found")
        for _,obj in ipairs(inGame:GetDescendants()) do hookState(obj) end
        add(inGame.DescendantAdded:Connect(function(obj)
            log("ADDED", obj, obj.ClassName)
            hookState(obj)
        end))
        add(inGame.DescendantRemoving:Connect(function(obj)
            if interestingName(obj) then log("REMOVED", obj, obj.ClassName) end
        end))
    else
        log("INFO", pg, "InGame UI not present yet; watching for it")
        local c
        c = pg.ChildAdded:Connect(function(ch)
            if ch.Name == "InGame" then
                if c then c:Disconnect() end
                task.defer(hookPlayerGui)
            end
        end)
        add(c)
    end
end
hookPlayerGui()

-- Timestamp keyboard submission attempts so we can correlate nearby signals.
add(UserInputService.InputBegan:Connect(function(input, processed)
    if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
        log("ENTER", nil, "Return pressed processed=" .. tostring(processed))
    end
end))

log("START", nil, "Passive acceptance diagnostic started. File=" .. LOGFILE)
log("INFO", nil, "Play 5-10 accepted turns, ideally fast ting replies, plus 1-2 rejected attempts if convenient.")
