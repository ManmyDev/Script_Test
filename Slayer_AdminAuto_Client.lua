local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")

local LocalPlayer = Players.LocalPlayer
local NovaURL = "https://raw.githubusercontent.com/ManmyDev/Nova_UI/refs/heads/main/NovaUI.lua"
local NovaUI = loadstring(game:HttpGet(NovaURL))()
local InputHandler = require(ReplicatedStorage.CAM.Client.Components.Client.InputHandler)
local DashHandler = require(ReplicatedStorage.CAM.Client.Modules.GamePlay.Dash_Handler)
local SequenceTeleport = require(ReplicatedStorage.CAM.Client.Modules.SequenceTeleport)
local GameSettings = require(ReplicatedStorage.CAM.Global.gameSettings)

NovaUI:SetTheme("Neon")

local Window = NovaUI:CreateWindow({
    Title = "Slayer Admin Auto",
    Version = "v0.1",
    Subtitle = "Client-side prototype",
    Logo = "◈",
})

local FarmingTab = Window:AddTab({
    Name = "Auto Farm",
    Group = "Automation",
    Icon = "⚔",
    Color = Color3.fromRGB(59, 130, 246),
})

local MovementTab = Window:AddTab({
    Name = "Movement",
    Group = "Automation",
    Icon = "🏃",
    Color = Color3.fromRGB(239, 68, 68),
})

local LootTab = Window:AddTab({
    Name = "Loot",
    Group = "Automation",
    Icon = "🎁",
    Color = Color3.fromRGB(245, 158, 11),
})

local State = {
    Enabled = false,
    AutoCombat = true,
    AutoChest = true,
    AutoLoot = true,
    UseDash = true,
    UseTeleport = true,
    Busy = false,
    Generation = 0,
    LastStatus = "",
}

local Config = {
    NPC_TAG = "Humanoids",
    LOOT_TAG = GameSettings.Tags.LootDrop or "LootDrop",
    CHEST_TAG = GameSettings.Tags.Chest or "Chest",
    ATTACK_RANGE = 9,
    PICKUP_RANGE = 8,
    CHEST_RANGE = 9,
    TARGET_SCAN_RANGE = 180,
    DASH_ESTIMATED_DISTANCE = 14,
    DASH_COOLDOWN = 1.0,
    TELEPORT_DISTANCE = 100,
    TELEPORT_COOLDOWN = 8,
    TELEPORT_OFFSET = 6,
    MOVE_TIMEOUT = 5,
}

local function status(message, notify)
    if State.LastStatus == message then
        return
    end
    State.LastStatus = message
    print("[SlayerAuto] " .. message)
    if notify then
        Window:Notify({
            Title = "Slayer Auto",
            Content = message,
            Type = "info",
            Duration = 3,
        })
    end
end

local function getCharacter()
    local character = LocalPlayer.Character
    if not character or not character.Parent then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return character, nil, nil
    end

    return character, humanoid, root
end

local function getModelRoot(model)
    if not model or not model:IsA("Model") then
        return nil
    end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function isPlayerCharacter(model)
    return Players:GetPlayerFromCharacter(model) ~= nil
end

local function getNearestNPC()
    local character, _, root = getCharacter()
    if not root then
        return nil
    end

    local bestModel
    local bestHumanoid
    local bestRoot
    local bestDistance = Config.TARGET_SCAN_RANGE

    for _, model in ipairs(CollectionService:GetTagged(Config.NPC_TAG)) do
        if model:IsA("Model") and model ~= character and model.Parent and not isPlayerCharacter(model) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local targetRoot = getModelRoot(model)

            if humanoid and humanoid.Health > 0 and targetRoot and targetRoot:IsDescendantOf(workspace) then
                local distance = (targetRoot.Position - root.Position).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestModel = model
                    bestHumanoid = humanoid
                    bestRoot = targetRoot
                end
            end
        end
    end

    return bestModel, bestHumanoid, bestRoot, bestDistance
end

local function getPrompt(instance)
    if not instance then
        return nil
    end
    if instance:IsA("ProximityPrompt") then
        return instance
    end
    return instance:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function getNearestTaggedPart(tag, maxDistance)
    local _, _, root = getCharacter()
    if not root then
        return nil
    end

    local bestInstance
    local bestPrompt
    local bestDistance = maxDistance

    for _, instance in ipairs(CollectionService:GetTagged(tag)) do
        if instance.Parent then
            local part
            if instance:IsA("BasePart") then
                part = instance
            elseif instance:IsA("Model") then
                part = getModelRoot(instance)
            end

            local prompt = getPrompt(instance)
            if part and prompt and prompt.Enabled then
                local owner = instance:GetAttribute("DropOwnerUserId")
                local reserved = instance:GetAttribute("DropReservedFor")
                local eligible = not (typeof(owner) == "number" and owner ~= LocalPlayer.UserId)
                if typeof(reserved) == "string" and not string.find(reserved, "," .. LocalPlayer.UserId .. ",", 1, true) then
                    eligible = false
                end

                local distance = (part.Position - root.Position).Magnitude
                if eligible and distance < bestDistance then
                    bestDistance = distance
                    bestInstance = instance
                    bestPrompt = prompt
                end
            end
        end
    end

    return bestInstance, bestPrompt, bestDistance
end

local function getNearestChest()
    local _, _, root = getCharacter()
    if not root then
        return nil
    end

    local bestChest
    local bestPrompt
    local bestDistance = Config.TARGET_SCAN_RANGE

    for _, chest in ipairs(CollectionService:GetTagged(Config.CHEST_TAG)) do
        if chest.Parent then
            local part = chest:IsA("BasePart") and chest or getModelRoot(chest)
            local prompt = getPrompt(chest)
            if part and prompt and prompt.Enabled then
                local distance = (part.Position - root.Position).Magnitude
                if distance < bestDistance then
                    bestDistance = distance
                    bestChest = chest
                    bestPrompt = prompt
                end
            end
        end
    end

    return bestChest, bestPrompt, bestDistance
end

local function moveToPosition(position, generation)
    local character, humanoid, root = getCharacter()
    if not humanoid or not root then
        return false
    end

    local path = PathfindingService:CreatePath({
        AgentCanJump = true,
        WaypointSpacing = 5,
    })

    local ok = pcall(function()
        path:ComputeAsync(root.Position, position)
    end)

    if not ok or path.Status ~= Enum.PathStatus.Success then
        humanoid:MoveTo(position)
        local started = os.clock()
        while State.Enabled and State.Generation == generation and os.clock() - started < Config.MOVE_TIMEOUT do
            local _, currentHumanoid, currentRoot = getCharacter()
            if not currentHumanoid or not currentRoot then
                return false
            end
            if (currentRoot.Position - position).Magnitude <= 4 then
                return true
            end
            task.wait(0.1)
        end
        return false
    end

    for _, waypoint in ipairs(path:GetWaypoints()) do
        if not State.Enabled or State.Generation ~= generation then
            return false
        end

        local _, currentHumanoid, currentRoot = getCharacter()
        if not currentHumanoid or not currentRoot then
            return false
        end

        if (currentRoot.Position - position).Magnitude <= 4 then
            return true
        end

        if waypoint.Action == Enum.PathWaypointAction.Jump then
            currentHumanoid.Jump = true
        end

        currentHumanoid:MoveTo(waypoint.Position)
        local started = os.clock()

        while State.Enabled and State.Generation == generation and os.clock() - started < 1.5 do
            local _, checkHumanoid, checkRoot = getCharacter()
            if not checkHumanoid or not checkRoot then
                return false
            end
            if (checkRoot.Position - waypoint.Position).Magnitude <= 3 then
                break
            end
            task.wait(0.1)
        end
    end

    return true
end

local lastDashAt = 0
local lastTeleportAt = -math.huge

-- Uses the game's existing teleport sequence and visual transition.
-- Client-side prototype only: the server may reject/correct arbitrary destinations.
local function maybeTeleportToward(targetPosition, distance, generation)
    if not State.UseTeleport or distance < Config.TELEPORT_DISTANCE then
        return false
    end
    if os.clock() - lastTeleportAt < Config.TELEPORT_COOLDOWN then
        return false
    end
    if SequenceTeleport.IsActive() then
        return false
    end
    if not State.Enabled or State.Generation ~= generation then
        return false
    end

    local _, humanoid, root = getCharacter()
    if not humanoid or not root then
        return false
    end

    -- Land a few studs before the target rather than inside its model.
    local flatDirection = Vector3.new(
        targetPosition.X - root.Position.X,
        0,
        targetPosition.Z - root.Position.Z
    )
    local destinationPosition = targetPosition
    if flatDirection.Magnitude > 0.01 then
        destinationPosition -= flatDirection.Unit * Config.TELEPORT_OFFSET
    end

    local destination = CFrame.new(destinationPosition) * root.CFrame.Rotation
    local ok, controller = pcall(function()
        return SequenceTeleport.Start({
            FallLength = 1,
            TeleportAtFall = 0.5,
            RiseLength = 1,
            Destination = destination,
        })
    end)

    if not ok or not controller then
        status("Teleport sequence could not start; using normal movement")
        return false
    end

    lastTeleportAt = os.clock()
    status(("Teleporting: %.0f studs away"):format(distance), true)

    -- Pause Auto movement until the built-in transition finishes.
    local started = os.clock()
    while controller.IsActive() and os.clock() - started < 8 do
        task.wait(0.1)
    end

    return true
end

local function getDashLetter(direction)
    local camera = workspace.CurrentCamera
    if not camera then
        return "W"
    end

    local forward = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
    if forward.Magnitude < 0.01 then
        return "W"
    end
    forward = forward.Unit

    local right = Vector3.new(-forward.Z, 0, forward.X)
    local dir = Vector3.new(direction.X, 0, direction.Z)
    if dir.Magnitude < 0.01 then
        return "W"
    end
    dir = dir.Unit

    local x = dir:Dot(right)
    local y = dir:Dot(forward)
    if math.abs(x) > math.abs(y) then
        return x > 0 and "D" or "A"
    end
    return y > 0 and "W" or "S"
end

local function maybeDashToward(targetPosition, distance)
    if not State.UseDash or distance <= Config.DASH_ESTIMATED_DISTANCE + Config.ATTACK_RANGE then
        return false
    end
    if os.clock() - lastDashAt < Config.DASH_COOLDOWN then
        return false
    end

    local _, humanoid, root = getCharacter()
    if not humanoid or not root then
        return false
    end

    local direction = targetPosition - root.Position
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude < 0.01 then
        return false
    end
    direction = direction.Unit

    local predictedPosition = root.Position + direction * Config.DASH_ESTIMATED_DISTANCE
    local predictedDistance = (targetPosition - predictedPosition).Magnitude

    if predictedDistance < 5 or predictedDistance > Config.ATTACK_RANGE + 2 then
        return false
    end

    local didDash = false
    local ok = pcall(function()
        didDash = DashHandler.Perform(getDashLetter(direction))
    end)

    if ok and didDash then
        lastDashAt = os.clock()
        task.wait(0.25)
        return true
    end

    return false
end

local function attackWhileClose(targetModel, targetHumanoid, generation)
    if not State.AutoCombat then
        return
    end

    local _, humanoid, root = getCharacter()
    local targetRoot = getModelRoot(targetModel)
    if not humanoid or not root or not targetRoot then
        return
    end

    local distance = (targetRoot.Position - root.Position).Magnitude
    if distance > Config.ATTACK_RANGE then
        return
    end

    InputHandler.VirtualPress("Combat", Enum.UserInputType.Touch)
    local started = os.clock()

    while State.Enabled
        and State.Generation == generation
        and targetModel.Parent
        and targetHumanoid.Health > 0
        and os.clock() - started < 0.45 do
        local _, currentHumanoid, currentRoot = getCharacter()
        local currentTargetRoot = getModelRoot(targetModel)
        if not currentHumanoid or not currentRoot or not currentTargetRoot then
            break
        end
        if (currentTargetRoot.Position - currentRoot.Position).Magnitude > Config.ATTACK_RANGE + 2 then
            break
        end
        task.wait(0.05)
    end

    InputHandler.VirtualRelease("Combat")
end

local function activatePrompt(prompt, generation)
    if not prompt or not prompt.Parent or not prompt.Enabled then
        return false
    end

    local _, humanoid, root = getCharacter()
    if not humanoid or not root then
        return false
    end

    local parentPart = prompt.Parent:IsA("BasePart") and prompt.Parent or prompt.Parent:FindFirstAncestorWhichIsA("BasePart")
    if not parentPart then
        return false
    end

    local distance = (parentPart.Position - root.Position).Magnitude
    local activationDistance = math.min(prompt.MaxActivationDistance, Config.PICKUP_RANGE)
    if distance > activationDistance then
        moveToPosition(parentPart.Position, generation)
    end

    if not State.Enabled or State.Generation ~= generation or not prompt.Parent or not prompt.Enabled then
        return false
    end

    local _, currentHumanoid, currentRoot = getCharacter()
    if not currentHumanoid or not currentRoot then
        return false
    end
    if (parentPart.Position - currentRoot.Position).Magnitude > prompt.MaxActivationDistance then
        return false
    end

    local holdDuration = math.max(prompt.HoldDuration, 0)
    local ok = pcall(function()
        prompt:InputHoldBegin()
    end)
    if not ok then
        return false
    end

    task.wait(holdDuration + 0.1)
    pcall(function()
        prompt:InputHoldEnd()
    end)
    return true
end

local function runFarm(generation)
    while State.Enabled and State.Generation == generation do
        local character, humanoid, root = getCharacter()
        if not humanoid or not root then
            status("Waiting for character...")
            task.wait(1)
            continue
        end

        local npc, npcHumanoid, npcRoot, npcDistance = getNearestNPC()
        if npc and npcHumanoid and npcRoot then
            status("Target: " .. npc.Name)
            if npcDistance > Config.ATTACK_RANGE then
                if not maybeTeleportToward(npcRoot.Position, npcDistance, generation)
                    and not maybeDashToward(npcRoot.Position, npcDistance) then
                    moveToPosition(npcRoot.Position, generation)
                end
            end
            attackWhileClose(npc, npcHumanoid, generation)
            task.wait(0.1)
            continue
        end

        local chest, chestPrompt, chestDistance = getNearestChest()
        if State.AutoChest and chest and chestPrompt then
            status("Chest found: " .. chest.Name)
            if chestDistance > math.min(chestPrompt.MaxActivationDistance, Config.CHEST_RANGE) then
                local chestPart = chest:IsA("BasePart") and chest or getModelRoot(chest)
                if chestPart then
                    if not maybeTeleportToward(chestPart.Position, chestDistance, generation) then
                        moveToPosition(chestPart.Position, generation)
                    end
                else
                    task.wait(0.25)
                end
            else
                activatePrompt(chestPrompt, generation)
                task.wait(0.5)
            end
            continue
        end

        local drop, dropPrompt, dropDistance = getNearestTaggedPart(Config.LOOT_TAG, Config.TARGET_SCAN_RANGE)
        if State.AutoLoot and drop and dropPrompt then
            status("Collecting loot")
            if dropDistance > math.min(dropPrompt.MaxActivationDistance, Config.PICKUP_RANGE) then
                local part = drop:IsA("BasePart") and drop or getModelRoot(drop)
                if part then
                    if not maybeTeleportToward(part.Position, dropDistance, generation) then
                        moveToPosition(part.Position, generation)
                    end
                end
            else
                activatePrompt(dropPrompt, generation)
                task.wait(0.25)
            end
            continue
        end

        status("Searching for NPCs, chests, and loot")
        task.wait(0.5)
    end

    InputHandler.VirtualRelease("Combat")
    State.Busy = false
end

local farmSection = FarmingTab:AddSection({
    Title = "Automation",
    Description = "Client-side prototype. Uses the game's existing input and prompts.",
    Icon = "⚙",
    Color = Color3.fromRGB(79, 209, 197),
})

farmSection:AddToggle({
    Title = "Auto Farm",
    Description = "Find NPCs, approach, and use the normal combat input.",
    Default = false,
    Callback = function(on)
        State.Enabled = on
        State.Generation += 1
        local generation = State.Generation

        if on then
            State.Busy = true
            status("Auto Farm enabled", true)
            task.spawn(function()
                local ok, err = pcall(runFarm, generation)
                InputHandler.VirtualRelease("Combat")
                State.Busy = false
                if not ok then
                    warn("[SlayerAuto] " .. tostring(err))
                    status("Stopped because of an error", true)
                end
            end)
        else
            InputHandler.VirtualRelease("Combat")
            status("Auto Farm disabled", true)
        end
    end,
})

farmSection:AddToggle({
    Title = "Auto Combat",
    Description = "Hold the game's normal Combat input while in range.",
    Default = true,
    Callback = function(on)
        State.AutoCombat = on
        if not on then
            InputHandler.VirtualRelease("Combat")
        end
    end,
})

local lootSection = LootTab:AddSection({
    Title = "Collection",
    Description = "Open tagged chests and collect tagged loot drops.",
    Icon = "🎁",
    Color = Color3.fromRGB(245, 158, 11),
})

lootSection:AddToggle({
    Title = "Auto Open Chests",
    Description = "Uses a chest ProximityPrompt when available.",
    Default = true,
    Callback = function(on)
        State.AutoChest = on
    end,
})

lootSection:AddToggle({
    Title = "Auto Collect Loot",
    Description = "Moves to LootDrop items and uses their ProximityPrompt.",
    Default = true,
    Callback = function(on)
        State.AutoLoot = on
    end,
})

local movementSection = MovementTab:AddSection({
    Title = "Navigation",
    Description = "Pathfinding, dash, and the built-in teleport sequence for very distant targets.",
    Icon = "🏃",
    Color = Color3.fromRGB(239, 68, 68),
})

movementSection:AddToggle({
    Title = "Use Dash When Useful",
    Description = "Dashes only when the estimated endpoint should be near the target.",
    Default = true,
    Callback = function(on)
        State.UseDash = on
    end,
})

movementSection:AddToggle({
    Title = "Use Teleport When Very Far",
    Description = ("Uses the built-in sequence beyond %d studs; server may correct client-side movement."):format(Config.TELEPORT_DISTANCE),
    Default = true,
    Callback = function(on)
        State.UseTeleport = on
    end,
})

movementSection:AddButton({
    Title = "Stop Everything",
    Description = "Stops navigation and releases the Combat input.",
    ButtonText = "Stop",
    Callback = function()
        State.Enabled = false
        State.Generation += 1
        InputHandler.VirtualRelease("Combat")
        status("Stopped manually", true)
    end,
})

Window:Notify({
    Title = "Slayer Admin Auto loaded",
    Content = "Start with Auto Farm disabled, then enable it when ready.",
    Type = "info",
    Duration = 5,
})
