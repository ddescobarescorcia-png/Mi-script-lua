-- LennonHubServer (Script en ServerScriptService)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-- CONFIG: coloca aquí los UserIds que serán administradores
local ADMINS = {
    12345678, -- <- reemplaza por tu UserId
    -- 87654321,
}

-- Utilities: asegurar RemoteEvent/Function y folder Tools/Logs
local function ensure(name, class, parent)
    local obj = parent:FindFirstChild(name)
    if not obj then
        obj = Instance.new(class)
        obj.Name = name
        obj.Parent = parent
    end
    return obj
end

local LennonEvent = ensure("LennonHubEvent", "RemoteEvent", ReplicatedStorage)
local LennonAdminFn = ensure("LennonHubAdminCheck", "RemoteFunction", ReplicatedStorage)
local toolsFolder = ensure("Tools", "Folder", ReplicatedStorage)
local LennonLogs = ensure("LennonLogs", "Folder", ServerStorage)

-- Comprueba si jugador es admin
local function isAdmin(player)
    for _, id in ipairs(ADMINS) do
        if player.UserId == id then return true end
    end
    return false
end

-- RemoteFunction: devuelve si jugador es admin
LennonAdminFn.OnServerInvoke = function(player)
    return isAdmin(player)
end

-- Logging simple
local function writeLog(player, action, details)
    local entry = Instance.new("StringValue")
    entry.Name = tostring(os.time()) .. "_" .. (player and tostring(player.UserId) or "server")
    entry.Value = string.format("[%s] %s (Id:%s): %s -- %s",
        os.date("%Y-%m-%d %H:%M:%S"), (player and player.Name or "Server"), (player and tostring(player.UserId) or "0"),
        tostring(action), tostring(details or ""))
    entry.Parent = LennonLogs
    -- opcional: limitar logs (no implementado por simplicidad)
end

-- Helpers de humanoid/character
local function getHumanoid(player)
    local char = player.Character
    if not char then return nil end
    return char:FindFirstChildWhichIsA("Humanoid")
end

-- Acciones permitidas
local function giveTool(player, toolName)
    local tool = toolsFolder:FindFirstChild(toolName)
    if tool and player and player:FindFirstChild("Backpack") then
        local clone = tool:Clone()
        clone.Parent = player.Backpack
        writeLog(player, "GiveTool", toolName)
    end
end

local function teleportToSpawn(player)
    local char = player.Character
    if not char or not char.PrimaryPart then return end
    local spawnPart = Workspace:FindFirstChild("LennonSpawn")
    if spawnPart and spawnPart:IsA("BasePart") then
        char:SetPrimaryPartCFrame(spawnPart.CFrame + Vector3.new(0,3,0))
        writeLog(player, "TeleportToSpawn", "LennonSpawn")
    else
        local spawn = Workspace:FindFirstChildOfClass("SpawnLocation")
        if spawn then
            char:SetPrimaryPartCFrame(spawn.CFrame + Vector3.new(0,3,0))
            writeLog(player, "TeleportToSpawn", "DefaultSpawn")
        end
    end
end

local function changeWalkSpeed(player, delta)
    local humanoid = getHumanoid(player)
    if humanoid then
        local newSpeed = math.clamp((humanoid.WalkSpeed or 16) + tonumber(delta or 0), 6, 200)
        humanoid.WalkSpeed = newSpeed
        writeLog(player, "ChangeWalkSpeed", tostring(newSpeed))
    end
end

local function changeJumpPower(player, delta)
    local humanoid = getHumanoid(player)
    if humanoid then
        local newJump = math.clamp((humanoid.JumpPower or 50) + tonumber(delta or 0), 0, 300)
        humanoid.JumpPower = newJump
        writeLog(player, "ChangeJumpPower", tostring(newJump))
    end
end

local function healPlayer(player, amount)
    local humanoid = getHumanoid(player)
    if humanoid then
        local maxH = humanoid.MaxHealth or 100
        if not amount then
            humanoid.Health = maxH
        else
            humanoid.Health = math.clamp(humanoid.Health + tonumber(amount), 0, maxH)
        end
        writeLog(player, "Heal", tostring(amount or "Full"))
    end
end

-- Invisibilidad guardada por BoolValue en Player
local function ensureInvisValue(player)
    local bv = player:FindFirstChild("Lennon_Invisible")
    if not bv then
        bv = Instance.new("BoolValue")
        bv.Name = "Lennon_Invisible"
        bv.Value = false
        bv.Parent = player
    end
    return bv
end

local function applyInvisibilityToCharacter(char, makeInvisible)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            part.Transparency = makeInvisible and 1 or 0
            part.CanCollide = not makeInvisible
        elseif part:IsA("Decal") or part:IsA("Texture") then
            part.Transparency = makeInvisible and 1 or 0
        end
    end
    for _, acc in ipairs(char:GetChildren()) do
        if acc:IsA("Accessory") then
            local handle = acc:FindFirstChild("Handle")
            if handle then
                handle.Transparency = makeInvisible and 1 or 0
                handle.CanCollide = not makeInvisible
            end
        end
    end
end

local function setInvisibility(player, flag)
    local bv = ensureInvisValue(player)
    bv.Value = flag and true or false
    if player.Character then
        applyInvisibilityToCharacter(player.Character, bv.Value)
    end
    writeLog(player, "SetInvisibility", tostring(bv.Value))
end

local function toggleInvisibility(player)
    local bv = ensureInvisValue(player)
    setInvisibility(player, not bv.Value)
    return bv.Value
end

-- Reaplicar invisibilidad cuando el character spawnea
Players.PlayerAdded:Connect(function(player)
    ensureInvisValue(player)
    player.CharacterAdded:Connect(function(char)
        local bv = ensureInvisValue(player)
        -- dar tiempo a que parts existan
        task.delay(0.1, function()
            applyInvisibilityToCharacter(char, bv.Value)
        end)
    end)
end)

-- Dispatcher de RemoteEvent (acciones)
LennonEvent.OnServerEvent:Connect(function(player, action, ...)
    -- Acciones disponibles para cualquier jugador:
    if action == "RequestGiveTool" then
        local toolName = ...
        giveTool(player, toolName)
        return
    elseif action == "TeleportToSpawn" then
        teleportToSpawn(player)
        return
    end

    -- Acciones admin: comprobar permiso
    if not isAdmin(player) then
        writeLog(player, "DeniedAction", tostring(action))
        return
    end

    -- Acciones admin concretas
    if action == "GiveTool" then
        local toolName = ...
        giveTool(player, toolName)
    elseif action == "ChangeWalkSpeed" then
        local delta = ...
        changeWalkSpeed(player, delta)
    elseif action == "ChangeJumpPower" then
        local delta = ...
        changeJumpPower(player, delta)
    elseif action == "Heal" then
        local amount = ...
        healPlayer(player, amount)
    elseif action == "SetInvisibility" then
        local flag = ...
        if flag == "toggle" then
            toggleInvisibility(player)
        else
            setInvisibility(player, flag and true or false)
        end
    else
        writeLog(player, "UnknownAction", tostring(action))
    end
end)

print("[LennonHubServer] Iniciado (admin count:", #ADMINS, ")")
