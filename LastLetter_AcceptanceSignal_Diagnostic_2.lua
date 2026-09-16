-- Last Letter Acceptance Diagnostic #2
-- PASSIVE packet/client-state introspection. Does NOT fire RemoteEvents or invoke server actions.
-- Goal: identify how ReplicatedStorage.Modules.Packet.RemoteEvent buffers are decoded client-side.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local LP = Players.LocalPlayer
local START = os.clock()
local LOGFILE = "WordHelper_Acceptance_Diagnostic_2.txt"
local lines = {}
local conns = {}
local last = {}

local function safe(v)
    local ok, s = pcall(function()
        if typeof(v) == "Instance" then return v:GetFullName() end
        if typeof(v) == "buffer" then return "buffer(len=" .. tostring(buffer.len(v)) .. ")" end
        return tostring(v)
    end)
    s = ok and s or "<unprintable>"
    s = s:gsub("[\r\n]+"," ")
    if #s > 350 then s = s:sub(1,347).."..." end
    return s
end

local function log(kind, where, detail)
    local line = string.format("[%09.3f] %-12s %-80s %s",
        os.clock()-START, kind, where or "-", detail or "")
    lines[#lines+1] = line
    print("[WH-DIAG2] "..line)
    if writefile then pcall(writefile, LOGFILE, table.concat(lines,"\n")) end
end

local function add(c) if c then conns[#conns+1]=c end end

local function hexBuffer(b, maxBytes)
    local ok, out = pcall(function()
        local n = buffer.len(b)
        local lim = math.min(n, maxBytes or 96)
        local t = {}
        for i=0,lim-1 do
            t[#t+1] = string.format("%02X", buffer.readu8(b,i))
        end
        return table.concat(t," ") .. (n>lim and " ..." or "")
    end)
    return ok and out or "<hex unavailable>"
end

local function currentWord()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local ig = pg and pg:FindFirstChild("InGame")
    local frame = ig and ig:FindFirstChild("Frame")
    local cw = frame and frame:FindFirstChild("CurrentWord")
    if not cw then return "" end
    local letters = {}
    for _,d in ipairs(cw:GetDescendants()) do
        if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.Text and d.Text ~= "" then
            local pos = 9999
            pcall(function() pos = d.AbsolutePosition.X end)
            letters[#letters+1] = {x=pos, text=d.Text}
        end
    end
    table.sort(letters,function(a,b) return a.x<b.x end)
    local t={}
    for _,v in ipairs(letters) do t[#t+1]=v.text end
    return table.concat(t):lower():gsub("%s+","")
end

local function typeText()
    local pg = LP:FindFirstChildOfClass("PlayerGui")
    local ig = pg and pg:FindFirstChild("InGame")
    local frame = ig and ig:FindFirstChild("Frame")
    local ty = frame and frame:FindFirstChild("Type")
    return ty and ty.Text or ""
end

local packetFolder = ReplicatedStorage:FindFirstChild("Modules")
packetFolder = packetFolder and packetFolder:FindFirstChild("Packet")
local remote = packetFolder and packetFolder:FindFirstChild("RemoteEvent")

log("START","-","Diagnostic #2 started. File="..LOGFILE)
log("PACKET_PATH","-", packetFolder and packetFolder:GetFullName() or "Packet module/folder NOT FOUND")
log("REMOTE_PATH","-", remote and remote:GetFullName() or "RemoteEvent NOT FOUND")

-- Inventory Packet descendants.
if packetFolder then
    for _,d in ipairs(packetFolder:GetDescendants()) do
        log("PACKET_OBJ",d:GetFullName(),d.ClassName)
    end
end

-- Inspect ModuleScripts named Packet / under Packet when require is safe.
local function inspectFunction(fn, label)
    if typeof(fn) ~= "function" then return end
    if debug and debug.getinfo then
        local ok,info = pcall(debug.getinfo,fn)
        if ok and info then
            log("FUNC_INFO",label,
                "name="..safe(info.name).." source="..safe(info.source).." linedefined="..safe(info.linedefined))
        end
    end
    if debug and debug.getconstants then
        local ok,cs = pcall(debug.getconstants,fn)
        if ok and type(cs)=="table" then
            local vals={}
            for i=1,math.min(#cs,80) do
                local v=cs[i]
                if type(v)=="string" or type(v)=="number" then vals[#vals+1]=safe(v) end
            end
            if #vals>0 then log("CONSTANTS",label,table.concat(vals," | ")) end
        end
    end
    if debug and debug.getupvalues then
        local ok,ups = pcall(debug.getupvalues,fn)
        if ok and type(ups)=="table" then
            for k,v in pairs(ups) do
                local vt=typeof(v)
                if vt=="string" or vt=="number" or vt=="boolean" or vt=="Instance" then
                    log("UPVALUE",label,tostring(k).."="..safe(v))
                elseif vt=="table" then
                    local keys={}
                    local c=0
                    for kk,_ in pairs(v) do
                        c=c+1
                        if #keys<30 then keys[#keys+1]=safe(kk) end
                    end
                    log("UPVALUE_TABLE",label,tostring(k).." keys("..c..")="..table.concat(keys,","))
                end
            end
        end
    end
end

local function inspectModule(ms)
    if not ms or not ms:IsA("ModuleScript") then return end
    log("MODULE",ms:GetFullName(),"attempting require/introspection")
    local ok,res = pcall(require,ms)
    if not ok then
        log("MODULE_ERR",ms:GetFullName(),safe(res))
        return
    end
    log("MODULE_RET",ms:GetFullName(),"typeof="..typeof(res))
    if type(res)=="table" then
        local keys={}
        for k,v in pairs(res) do
            keys[#keys+1]=safe(k)..":"..typeof(v)
        end
        table.sort(keys)
        log("MODULE_KEYS",ms:GetFullName(),table.concat(keys," | "))
        for k,v in pairs(res) do
            if typeof(v)=="function" then inspectFunction(v,ms.Name.."."..safe(k)) end
        end
    elseif typeof(res)=="function" then
        inspectFunction(res,ms.Name)
    end
end

if packetFolder then
    if packetFolder:IsA("ModuleScript") then inspectModule(packetFolder) end
    for _,d in ipairs(packetFolder:GetDescendants()) do
        if d:IsA("ModuleScript") then inspectModule(d) end
    end
end

-- Inspect existing client callbacks connected to the packet RemoteEvent if executor exposes getconnections.
if remote and getconnections then
    local ok,connections = pcall(getconnections,remote.OnClientEvent)
    if ok and type(connections)=="table" then
        log("CONNECTIONS",remote:GetFullName(),"count="..#connections)
        for i,c in ipairs(connections) do
            local fn
            pcall(function() fn=c.Function end)
            if typeof(fn)=="function" then inspectFunction(fn,"OnClientEvent["..i.."]") end
        end
    else
        log("CONNECTIONS","-","getconnections failed")
    end
else
    log("CONNECTIONS","-","getconnections unavailable or RemoteEvent missing")
end

-- Log every packet with length + first bytes, correlated with current UI state.
if remote then
    add(remote.OnClientEvent:Connect(function(...)
        local a=table.pack(...)
        local parts={}
        for i=1,a.n do
            local v=a[i]
            if typeof(v)=="buffer" then
                parts[#parts+1]="arg"..i.." buffer len="..buffer.len(v).." hex="..hexBuffer(v,96)
            else
                parts[#parts+1]="arg"..i.." "..typeof(v).."="..safe(v)
            end
        end
        log("PACKET_RX",remote:GetFullName(),
            table.concat(parts," || ").." || CurrentWord="..currentWord().." || Type="..typeText())
    end))
end

-- High-resolution UI correlation: log actual CurrentWord text whenever it changes.
local hookedLetters={}
local function hookCurrentWord()
    local pg=LP:FindFirstChildOfClass("PlayerGui")
    local ig=pg and pg:FindFirstChild("InGame")
    local frame=ig and ig:FindFirstChild("Frame")
    local cw=frame and frame:FindFirstChild("CurrentWord")
    if not cw then return end

    local function snapshot(reason)
        local w=currentWord()
        local key="CW:"..w
        if last.CW~=key then
            last.CW=key
            log("CURRENT_WORD",cw:GetFullName(),reason.." word="..w)
        end
    end
    local function hook(d)
        if hookedLetters[d] then return end
        if d:IsA("TextLabel") or d:IsA("TextButton") then
            hookedLetters[d]=true
            add(d:GetPropertyChangedSignal("Text"):Connect(function() snapshot("TextChanged") end))
        end
    end
    for _,d in ipairs(cw:GetDescendants()) do hook(d) end
    add(cw.DescendantAdded:Connect(function(d) hook(d); task.defer(function() snapshot("DescendantAdded") end) end))
    add(cw.DescendantRemoving:Connect(function() task.defer(function() snapshot("DescendantRemoving") end) end))
    snapshot("hooked")
end

task.spawn(function()
    while task.wait(0.25) do pcall(hookCurrentWord) end
end)

-- Turn text correlation.
task.spawn(function()
    while task.wait(0.02) do
        local t=typeText()
        if t~=last.Type then
            last.Type=t
            log("TYPE_CHANGE","-",t)
        end
    end
end)

-- Mark Enter attempts with the exact visible word and turn text.
add(UserInputService.InputBegan:Connect(function(input,processed)
    if input.KeyCode==Enum.KeyCode.Return or input.KeyCode==Enum.KeyCode.KeypadEnter then
        log("ENTER","-","processed="..tostring(processed).." word="..currentWord().." || Type="..typeText())
    end
end))

log("INFO","-","Play about 5-10 accepted turns. Include fast ting replies if possible, plus 1 rejected attempt.")
log("INFO","-","You do NOT need to finish the match. Upload "..LOGFILE.." afterward.")
