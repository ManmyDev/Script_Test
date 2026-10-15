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

local Utility = require(ReplicatedStorage.CAM.Global.Utility)
local CharacterInfo = require(ReplicatedStorage.CAM.Global.Character_info_provider)
local CollectibleItems = require(ReplicatedStorage.CAM.Global.Collectibles.Items)
local Checker = require(ReplicatedStorage.CAM.Global.Checker)
local SignalEvent = require(ReplicatedStorage.Communication.ServerAndClient.Signals.SignalEvent)
local ToolbarItemRestrictions = require(ReplicatedStorage.CAM.Global.Subsets.Gameplay.ToolbarItemRestrictions)

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
    AutoRunHeld = false,
    AutoRunToggledByAuto = false,
    SelectedWeaponSlot = 1,
    AutoBestWeapon = true,
    LastBestWeapon = nil,
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

local function startAutoRun()
    -- If the player is already running manually (held or toggled), do not take ownership.
    if RunHandler.Is_Running == true or RunHandler.Toggled == true or InputHandler.IsDown("Run") then
        return
    end

    if State.AutoRunHeld or State.AutoRunToggledByAuto then
        return
    end

    local wasToggled = RunHandler.Toggled == true
    InputHandler.VirtualPress("Run", Enum.UserInputType.Keyboard)

    -- The game's Run_Initiator toggles RunHandler.Toggled when Run is configured
    -- as a toggle; otherwise it expects the Run input to remain held.
    if not wasToggled and RunHandler.Toggled == true then
        State.AutoRunToggledByAuto = true
        InputHandler.VirtualRelease("Run")
    else
        State.AutoRunHeld = true
    end
end

local function stopAutoRun()
    if State.AutoRunHeld then
        InputHandler.VirtualRelease("Run")
        State.AutoRunHeld = false
    end

    if State.AutoRunToggledByAuto then
        if RunHandler.Toggled == true then
            InputHandler.VirtualPress("Run", Enum.UserInputType.Keyboard)
            InputHandler.VirtualRelease("Run")
        end
        State.AutoRunToggledByAuto = false
    end
end

local function moveToPositionInternal(position, generation)
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

local function moveToPosition(position, generation)
    startAutoRun()
    local ok, reached = pcall(moveToPositionInternal, position, generation)
    stopAutoRun()

    if not ok then
        warn("[SlayerAuto] Navigation error: " .. tostring(reached))
        return false
    end
    return reached == true
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


-- Inventory / Hotbar weapon selector
local Utility = require(ReplicatedStorage.CAM.Global.Utility)
local CharacterInfo = require(ReplicatedStorage.CAM.Global.Character_info_provider)
local CollectibleItems = require(ReplicatedStorage.CAM.Global.Collectibles.Items)
local Checker = require(ReplicatedStorage.CAM.Global.Checker)
local SignalEvent = require(
    ReplicatedStorage.Communication.ServerAndClient.Signals.SignalEvent
)

local TOOLBAR_SLOTS = {
    { Name = "One", Index = 1, Input = "Toolbar_1st" },
    { Name = "Two", Index = 2, Input = "Toolbar_2nd" },
    { Name = "Three", Index = 3, Input = "Toolbar_3rd" },
    { Name = "Four", Index = 4, Input = "Toolbar_4th" },
    { Name = "Five", Index = 5, Input = "Toolbar_5th" },
}

local function getInventoryData()
    local ok, data = pcall(function()
        return Utility.GetData(LocalPlayer, true)
    end)

    if not ok or not data then
        warn("[SlayerAuto] Unable to read player data")
        return nil
    end

    return data
end

local function getOwnedCombatItems()
    local result = {}

    local ok, bags = pcall(function()
        return CharacterInfo.GetItemBags(LocalPlayer)
    end)

    if not ok or type(bags) ~= "table" then
        warn("[SlayerAuto] Unable to read item bags")
        return result
    end

    for _, bag in ipairs(bags) do
        if typeof(bag) == "Instance" then
            for _, entry in ipairs(bag:GetChildren()) do
                local definition = CollectibleItems[entry.Name]

                if type(definition) == "table"
                    and definition.HasCombat == true
                    and type(definition.CombatPreset) == "string" then

                    local idObject = entry:FindFirstChild("Id")
                    local itemId = idObject
                        and tonumber(idObject.Value)

                    if itemId then
                        local score = 0
                        local stats = definition.ActiveToolStats

                        if type(stats) == "table" then
                            for statName, value in pairs(stats) do
                                if typeof(value) == "number" then
                                    local name = string.lower(tostring(statName))

                                    if string.find(name, "damage", 1, true) then
                                        score += value * 100
                                    else
                                        score += value
                                    end
                                end
                            end
                        end

                        local rarity = definition.Rarity
                        if typeof(rarity) == "number" then
                            score += rarity * 10
                        end

                        table.insert(result, {
                            Id = itemId,
                            Name = entry.Name,
                            Score = score,
                        })
                    end
                end
            end
        end
    end

    return result
end

local function getChild(container, name)
    if typeof(container) == "Instance" then
        return container:FindFirstChild(name)
    end

    if type(container) == "table" then
        return container[name]
    end

    return nil
end

local function getValue(object)
    if typeof(object) == "Instance" then
        return object.Value
    end

    if type(object) == "table" then
        if object.Value ~= nil then
            return object.Value
        end

        if object.Id ~= nil then
            return object.Id
        end
    end

    return object
end

local function getToolbar(data)
    local inventory = getChild(data, "Inventory")
    return getChild(inventory, "Toolbar")
end

local function findItemSlot(toolbar, itemId)
    if not toolbar then
        return nil
    end

    for _, slot in ipairs(TOOLBAR_SLOTS) do
        local value = getChild(toolbar, slot.Name)

        if value and tonumber(getValue(value)) == itemId then
            return slot
        end
    end

    return nil
end

local function selectToolbarSlot(slot)
    if not slot then
        return false
    end

    local ok, err = pcall(function()
        InputHandler.VirtualPress(
            slot.Input,
            Enum.UserInputType.Touch
        )

        task.wait(0.05)

        InputHandler.VirtualRelease(slot.Input)
    end)

    if not ok then
        warn("[SlayerAuto] Hotbar selection error:", err)
        return false
    end

    State.SelectedWeaponSlot = slot.Index
    return true
end

local function selectBestAvailableWeapon()
    if not State.AutoBestWeapon then
        return false
    end

    local data = getInventoryData()

    if not data then
        status("Inventory data is not ready.", true)
        return false
    end

    local toolbar = getToolbar(data)

    if not toolbar then
        status("Could not find the Hotbar data.", true)
        return false
    end

    local items = getOwnedCombatItems()

    if #items == 0 then
        status("No owned combat weapons were found.", true)
        return false
    end

    table.sort(items, function(a, b)
        return a.Score > b.Score
    end)

    local bestItem = items[1]
    local slot = findItemSlot(toolbar, bestItem.Id)

    if not slot then
        local ok, denied = pcall(function()
            return Checker.DenyLoadoutChange(LocalPlayer)
        end)

        if not ok or denied == true then
            status("The game currently restricts loadout changes.", true)
            return false
        end

        -- หาช่อง Hotbar ที่ว่าง
        for _, candidate in ipairs(TOOLBAR_SLOTS) do
            local value = getChild(toolbar, candidate.Name)

            if value and tonumber(getValue(value)) == 0 then
                slot = candidate
                break
            end
        end

        -- ถ้าไม่มีช่องว่าง ให้ลองช่องสุดท้าย
        slot = slot or TOOLBAR_SLOTS[#TOOLBAR_SLOTS]

        local sent, err = pcall(function()
            SignalEvent.ToServer(
                "Toolbar_Equip",
                slot.Name,
                bestItem.Id
            )
        end)

        if not sent then
            warn("[SlayerAuto] Equip request failed:", err)
            status("Could not request weapon equip.", true)
            return false
        end

        -- รอให้ข้อมูล Hotbar อัปเดต
        local deadline = os.clock() + 3

        repeat
            task.wait(0.15)

            data = getInventoryData()
            toolbar = getToolbar(data)

            local currentSlot = getChild(toolbar, slot.Name)

            if currentSlot
                and tonumber(getValue(currentSlot)) == bestItem.Id then
                break
            end
        until os.clock() >= deadline

        local currentSlot = getChild(toolbar, slot.Name)

        if not currentSlot
            or tonumber(getValue(currentSlot)) ~= bestItem.Id then
            status("The game did not confirm the Hotbar change.", true)
            return false
        end
    end

    if not selectToolbarSlot(slot) then
        status("Could not select the weapon slot.", true)
        return false
    end

    if State.LastBestWeapon ~= bestItem.Name then
        State.LastBestWeapon = bestItem.Name

        status(
            ("Best weapon: %s | Slot %d"):format(
                bestItem.Name,
                slot.Index
            ),
            true
        )
    end

    return true
end


local function selectBestAvailableWeapon()
    if not State.AutoBestWeapon then
        return false
    end

    local data = getInventoryData()
    if not data then
        status("Inventory data is not ready.", true)
        return false
    end

    local toolbar = getToolbar(data)
    if not toolbar then
        status("Could not find the Hotbar data.", true)
        return false
    end

    local items = getOwnedCombatItems()
    if #items == 0 then
        status("No owned combat weapons were found.", true)
        return false
    end

    table.sort(items, function(a, b)
        return a.Score > b.Score
    end)

    local bestItem = items[1]
    local slot = findItemSlot(toolbar, bestItem.Id)

    if not slot then
        local ok, denied = pcall(function()
            return Checker.DenyLoadoutChange(LocalPlayer)
        end)

        if not ok or denied == true then
            status("The game currently restricts loadout changes.", true)
            return false
        end

        -- Prefer an empty slot; otherwise try the last slot.
        for _, candidate in ipairs(TOOLBAR_SLOTS) do
            local value = toolbar:FindFirstChild(candidate.Name)

            if value and tonumber(value.Value) == 0 then
                slot = candidate
                break
            end
        end

        slot = slot or TOOLBAR_SLOTS[#TOOLBAR_SLOTS]

        -- Request the game's normal equip action.
        local sent, err = pcall(function()
            SignalEvent.ToServer(
                "Toolbar_Equip",
                slot.Name,
                bestItem.Id
            )
        end)

        if not sent then
            warn("[SlayerAuto] Equip request failed:", err)
            status("Could not request weapon equip.", true)
            return false
        end

        -- Wait for the game to update the replicated Hotbar.
        local deadline = os.clock() + 3

        repeat
            task.wait(0.15)

            data = getInventoryData()
            toolbar = getToolbar(data)

            local currentSlot = toolbar
                and toolbar:FindFirstChild(slot.Name)

            if currentSlot
                and tonumber(currentSlot.Value) == bestItem.Id then
                break
            end
        until os.clock() >= deadline

        local currentSlot = toolbar
            and toolbar:FindFirstChild(slot.Name)

        if not currentSlot
            or tonumber(currentSlot.Value) ~= bestItem.Id then
            status("The game did not confirm the Hotbar change.", true)
            return false
        end
    end

    if not selectToolbarSlot(slot) then
        status("Could not select the weapon slot.", true)
        return false
    end

    if State.LastBestWeapon ~= bestItem.Name then
        State.LastBestWeapon = bestItem.Name
        status(
            ("Best weapon: %s | Slot %d"):format(
                bestItem.Name,
                slot.Index
            ),
            true
        )
    end

    return true
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

    selectBestAvailableWeapon()
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
                if State.UseTeleport and SequenceTeleport.IsActive() then
                    task.wait(0.15)
                elseif not maybeTeleportToward(npcRoot.Position, npcDistance, generation) then
                    if not State.Enabled or State.Generation ~= generation then
                        break
                    end
                
                    if not maybeDashToward(npcRoot.Position, npcDistance) then
                        moveToPosition(npcRoot.Position, generation)
                    end
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
    stopAutoRun()
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
        State.Generation += 1
        local generation = State.Generation
        State.Enabled = on
    
        if not on then
            pcall(function()
                InputHandler.VirtualRelease("Combat")
            end)
    
            stopAutoRun()
            status("Auto Farm disabled", true)
            return
        end
    
        status("Auto Farm enabled", true)
    
        task.spawn(function()
            local ok, err = xpcall(function()
                runFarm(generation)
            end, debug.traceback)
    
            pcall(function()
                InputHandler.VirtualRelease("Combat")
            end)
    
            stopAutoRun()
    
            if not ok then
                warn("[SlayerAuto] Auto Farm error:\n" .. tostring(err))
    
                if State.Generation == generation then
                    State.Enabled = false
                    State.Generation += 1
                end
    
                status("Auto Farm stopped because of an error. Check console.", true)
            end
        end)
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

local weaponSection = FarmingTab:AddSection({
    Title = "Weapon Selection",
    Description = "Automatically equips the strongest weapon that exposes readable stats in Character/Backpack.",
    Icon = "⚔",
    Color = Color3.fromRGB(168, 85, 247),
})

local function getEquippedToolName()
    local character = LocalPlayer.Character
    if not character then
        return "none"
    end

    local tool = character:FindFirstChildOfClass("Tool")
    return tool and tool.Name or "none"
end

weaponSection:AddToggle({
    Title = "Auto Select Best Weapon",
    Description = "Before attacking, compares weapon attributes and equips the highest-scoring available Tool.",
    Default = true,
    Callback = function(on)
        State.AutoBestWeapon = on
        if on then
            selectBestAvailableWeapon()
        end
    end,
})

weaponSection:AddButton({
    Title = "Find Best Weapon Now",
    Description = "Searches equipped/backpack Tools and equips the best one when its stats are available.",
    ButtonText = "Find Best",
    Callback = function()
        selectBestAvailableWeapon()
    end,
})

weaponSection:AddButton({
    Title = "Show Equipped Weapon",
    Description = "Displays the Tool currently equipped on your character.",
    ButtonText = "Check",
    Callback = function()
        status("Currently equipped: " .. getEquippedToolName(), true)
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
    Description = "Uses Humanoid path movement and the game's Run_Handler while navigating, plus dash/teleport options.",
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
        stopAutoRun()
        status("Stopped manually", true)
    end,
})

Window:Notify({
    Title = "Slayer Admin Auto loaded",
    Content = "Start with Auto Farm disabled, then enable it when ready.",
    Type = "info",
    Duration = 5,
})
