local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local LogService = game:GetService("LogService")

local LocalPlayer = Players.LocalPlayer
local NovaURL = "https://raw.githubusercontent.com/ManmyDev/Nova_UI/refs/heads/main/NovaUI.lua"
local NovaUI = loadstring(game:HttpGet(NovaURL))()

-- ป้องกัน Error หากโหลดโมดูลไม่ทัน
local function safeRequire(path, timeout)
    local instance = ReplicatedStorage
    for _, part in ipairs(path) do
        instance = instance:WaitForChild(part, timeout or 5)
        if not instance then return nil end
    end
    local ok, res = pcall(require, instance)
    return ok and res or nil
end

local InputHandler = safeRequire({"CAM", "Client", "Components", "Client", "InputHandler"}) or require(ReplicatedStorage.CAM.Client.Components.Client.InputHandler)
local RunHandler = safeRequire({"CAM", "Client", "Modules", "GamePlay", "Run_Handler"}) or require(ReplicatedStorage.CAM.Client.Modules.GamePlay.Run_Handler)
local DashHandler = safeRequire({"CAM", "Client", "Modules", "GamePlay", "Dash_Handler"}) or require(ReplicatedStorage.CAM.Client.Modules.GamePlay.Dash_Handler)
local SequenceTeleport = safeRequire({"CAM", "Client", "Modules", "SequenceTeleport"}) or require(ReplicatedStorage.CAM.Client.Modules.SequenceTeleport)
local GameSettings = safeRequire({"CAM", "Global", "gameSettings"}) or require(ReplicatedStorage.CAM.Global.gameSettings)

local Utility = safeRequire({"CAM", "Global", "Utility"}) or require(ReplicatedStorage.CAM.Global.Utility)
local CharacterInfo = safeRequire({"CAM", "Global", "Character_info_provider"}) or require(ReplicatedStorage.CAM.Global.Character_info_provider)
local CollectibleItems = safeRequire({"CAM", "Global", "Collectibles", "Items"}) or require(ReplicatedStorage.CAM.Global.Collectibles.Items)
local Checker = safeRequire({"CAM", "Global", "Checker"}) or require(ReplicatedStorage.CAM.Global.Checker)
local SignalEvent = safeRequire({"Communication", "ServerAndClient", "Signals", "SignalEvent"}) or require(ReplicatedStorage.Communication.ServerAndClient.Signals.SignalEvent)

NovaUI:SetTheme("Neon")

local Window = NovaUI:CreateWindow({
    Title = "Slayer Admin Auto",
    Version = "v0.2 - Target Lock",
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
    CurrentTarget = nil, -- เก็บ NPC ที่กำลังล็อคเป้าไว้
}

local Config = {
    NPC_TAG = "Humanoids",
    LOOT_TAG = (GameSettings and GameSettings.Tags and GameSettings.Tags.LootDrop) or "LootDrop",
    CHEST_TAG = (GameSettings and GameSettings.Tags and GameSettings.Tags.Chest) or "Chest",
    ATTACK_RANGE = 9,
    PICKUP_RANGE = 8,
    CHEST_RANGE = 9,
    TARGET_SCAN_RANGE = 180,
    DASH_ESTIMATED_DISTANCE = 14,
    DASH_COOLDOWN = 0.8,
    TELEPORT_DISTANCE = 100,
    TELEPORT_COOLDOWN = 8,
    TELEPORT_OFFSET = 6,
    MOVE_TIMEOUT = 5,
}

-- Console ระบบวินิจฉัย
local ConsoleState = { Lines = {}, MaxLines = 35, LastError = "No errors recorded." }
local consoleGui, consolePanel, consoleLog, consoleStatus, consoleListLayout

local function pushConsoleLine(level, message)
    message = tostring(message)
    local timestamp = os.date("%H:%M:%S")
    local lineText = ("[%s] [%s] %s"):format(timestamp, level, message)

    table.insert(ConsoleState.Lines, lineText)
    while #ConsoleState.Lines > ConsoleState.MaxLines do
        table.remove(ConsoleState.Lines, 1)
    end

    if level == "ERROR" then
        ConsoleState.LastError = message
        if consoleStatus then
            consoleStatus.Text = "LAST ERROR: " .. message
            consoleStatus.TextColor3 = Color3.fromRGB(255, 105, 105)
        end
    elseif consoleStatus and ConsoleState.LastError == "No errors recorded." then
        consoleStatus.Text = "Status: " .. message
    end

    if consoleLog then
        for _, child in ipairs(consoleLog:GetChildren()) do
            if child:IsA("TextLabel") then child:Destroy() end
        end

        for _, savedLine in ipairs(ConsoleState.Lines) do
            local isError = string.find(savedLine, "[ERROR]", 1, true) ~= nil
            local isWarning = string.find(savedLine, "[WARN]", 1, true) ~= nil
            local label = Instance.new("TextLabel")
            label.Name = "ConsoleLine"
            label.BackgroundTransparency = 1
            label.Size = UDim2.new(1, -8, 0, 0)
            label.AutomaticSize = Enum.AutomaticSize.Y
            label.Font = Enum.Font.Code
            label.TextSize = 12
            label.TextWrapped = true
            label.TextXAlignment = Enum.TextXAlignment.Left
            label.TextYAlignment = Enum.TextYAlignment.Top
            label.Text = savedLine
            label.TextColor3 = isError and Color3.fromRGB(255, 110, 110)
                or (isWarning and Color3.fromRGB(255, 196, 100) or Color3.fromRGB(210, 220, 235))
            label.Parent = consoleLog
        end

        task.defer(function()
            if consoleLog and consoleListLayout then
                consoleLog.CanvasSize = UDim2.new(0, 0, 0, consoleListLayout.AbsoluteContentSize.Y + 12)
                consoleLog.CanvasPosition = Vector2.new(0, math.max(0, consoleListLayout.AbsoluteContentSize.Y))
            end
        end)
    end
end

local function createDiagnosticConsole()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return end

    local oldGui = playerGui:FindFirstChild("SlayerAutoDiagnosticConsole")
    if oldGui then oldGui:Destroy() end

    consoleGui = Instance.new("ScreenGui")
    consoleGui.Name = "SlayerAutoDiagnosticConsole"
    consoleGui.ResetOnSpawn = false
    consoleGui.DisplayOrder = 999
    consoleGui.Parent = playerGui

    consolePanel = Instance.new("Frame")
    consolePanel.Name = "ConsolePanel"
    consolePanel.AnchorPoint = Vector2.new(1, 1)
    consolePanel.Position = UDim2.new(1, -16, 1, -16)
    consolePanel.Size = UDim2.new(0, 460, 0, 250)
    consolePanel.BackgroundColor3 = Color3.fromRGB(18, 22, 31)
    consolePanel.BackgroundTransparency = 0.08
    consolePanel.BorderSizePixel = 0
    consolePanel.Parent = consoleGui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 8)
    panelCorner.Parent = consolePanel

    local header = Instance.new("TextLabel")
    header.Name = "Header"
    header.BackgroundTransparency = 1
    header.Position = UDim2.new(0, 10, 0, 5)
    header.Size = UDim2.new(1, -100, 0, 25)
    header.Font = Enum.Font.GothamBold
    header.Text = "SLAYER AUTO / CONSOLE"
    header.TextSize = 13
    header.TextColor3 = Color3.fromRGB(230, 235, 245)
    header.TextXAlignment = Enum.TextXAlignment.Left
    header.Parent = consolePanel

    local hideButton = Instance.new("TextButton")
    hideButton.Name = "HideButton"
    hideButton.Position = UDim2.new(1, -66, 0, 5)
    hideButton.Size = UDim2.new(0, 56, 0, 24)
    hideButton.BackgroundColor3 = Color3.fromRGB(55, 65, 81)
    hideButton.BorderSizePixel = 0
    hideButton.Font = Enum.Font.GothamBold
    hideButton.Text = "HIDE"
    hideButton.TextSize = 11
    hideButton.TextColor3 = Color3.new(1, 1, 1)
    hideButton.Parent = consolePanel
    Instance.new("UICorner", hideButton).CornerRadius = UDim.new(0, 5)

    consoleStatus = Instance.new("TextLabel")
    consoleStatus.Name = "StatusLine"
    consoleStatus.BackgroundColor3 = Color3.fromRGB(30, 36, 48)
    consoleStatus.BorderSizePixel = 0
    consoleStatus.Position = UDim2.new(0, 8, 0, 34)
    consoleStatus.Size = UDim2.new(1, -16, 0, 30)
    consoleStatus.Font = Enum.Font.Gotham
    consoleStatus.Text = "Status: Console ready; waiting for errors."
    consoleStatus.TextSize = 11
    consoleStatus.TextColor3 = Color3.fromRGB(160, 220, 180)
    consoleStatus.TextWrapped = true
    consoleStatus.TextXAlignment = Enum.TextXAlignment.Left
    consoleStatus.Parent = consolePanel
    Instance.new("UICorner", consoleStatus).CornerRadius = UDim.new(0, 4)

    consoleLog = Instance.new("ScrollingFrame")
    consoleLog.Name = "Log"
    consoleLog.Position = UDim2.new(0, 8, 0, 70)
    consoleLog.Size = UDim2.new(1, -16, 1, -78)
    consoleLog.BackgroundColor3 = Color3.fromRGB(10, 13, 19)
    consoleLog.BorderSizePixel = 0
    consoleLog.ScrollBarThickness = 6
    consoleLog.CanvasSize = UDim2.new(0, 0, 0, 0)
    consoleLog.Parent = consolePanel
    Instance.new("UICorner", consoleLog).CornerRadius = UDim.new(0, 4)

    consoleListLayout = Instance.new("UIListLayout")
    consoleListLayout.Padding = UDim.new(0, 3)
    consoleListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    consoleListLayout.Parent = consoleLog

    local openButton = Instance.new("TextButton")
    openButton.Name = "OpenConsoleButton"
    openButton.AnchorPoint = Vector2.new(1, 1)
    openButton.Position = UDim2.new(1, -16, 1, -16)
    openButton.Size = UDim2.new(0, 145, 0, 34)
    openButton.BackgroundColor3 = Color3.fromRGB(30, 41, 59)
    openButton.BorderSizePixel = 0
    openButton.Font = Enum.Font.GothamBold
    openButton.Text = "OPEN ERROR CONSOLE"
    openButton.TextSize = 11
    openButton.TextColor3 = Color3.new(1, 1, 1)
    openButton.Visible = false
    openButton.Parent = consoleGui
    Instance.new("UICorner", openButton).CornerRadius = UDim.new(0, 6)

    hideButton.Activated:Connect(function()
        consolePanel.Visible = false
        openButton.Visible = true
    end)

    openButton.Activated:Connect(function()
        consolePanel.Visible = true
        openButton.Visible = false
    end)

    pushConsoleLine("INFO", "Console initialized.")
end

createDiagnosticConsole()

LogService.MessageOut:Connect(function(message, messageType)
    if messageType == Enum.MessageType.MessageError then
        if not string.find(message, "[SlayerAuto] Auto Farm error:", 1, true) then
            pushConsoleLine("ERROR", message)
        end
    elseif messageType == Enum.MessageType.MessageWarning then
        pushConsoleLine("WARN", message)
    end
end)

local function status(message, notify)
    if State.LastStatus == message then return end
    State.LastStatus = message
    print("[SlayerAuto] " .. message)
    if consoleStatus and ConsoleState.LastError == "No errors recorded." then
        consoleStatus.Text = "STATUS: " .. tostring(message)
        consoleStatus.TextColor3 = Color3.fromRGB(160, 220, 180)
    end
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
    if not character or not character.Parent then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then return character, nil, nil end
    return character, humanoid, root
end

local function getModelRoot(model)
    if not model or not model:IsA("Model") then return nil end
    return model:FindFirstChild("HumanoidRootPart")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
end

local function isPlayerCharacter(model)
    return Players:GetPlayerFromCharacter(model) ~= nil
end

-- ระบบเลือก/ล็อคเป้าหมาย
local function getTargetNPC()
    local character, _, root = getCharacter()
    if not root then return nil end

    -- 1. เช็คเป้าหมายเดิมที่ล็อคไว้
    if State.CurrentTarget and State.CurrentTarget.Parent then
        local humanoid = State.CurrentTarget:FindFirstChildOfClass("Humanoid")
        local targetRoot = getModelRoot(State.CurrentTarget)
        if humanoid and humanoid.Health > 0 and targetRoot and targetRoot:IsDescendantOf(workspace) then
            local distance = (targetRoot.Position - root.Position).Magnitude
            if distance <= Config.TARGET_SCAN_RANGE + 50 then -- อนุญาตให้ไล่ตามเกินระยะสแกนเล็กน้อย
                return State.CurrentTarget, humanoid, targetRoot, distance
            end
        end
    end

    -- 2. ถ้าเป้าหมายเดิมตายหรือหลุดระยะ ให้ล้างค่าแล้วหาเป้าหมายที่ใกล้ที่สุดใหม่
    State.CurrentTarget = nil
    local bestModel, bestHumanoid, bestRoot
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

    if bestModel then
        State.CurrentTarget = bestModel -- ล็อคเป้าหมายใหม่
    end

    return bestModel, bestHumanoid, bestRoot, bestDistance
end

local function startAutoRun()
    if not RunHandler then return end
    if RunHandler.Is_Running == true or RunHandler.Toggled == true or (InputHandler and InputHandler.IsDown and InputHandler.IsDown("Run")) then
        return
    end

    if State.AutoRunHeld or State.AutoRunToggledByAuto then return end

    local wasToggled = RunHandler.Toggled == true
    if InputHandler and InputHandler.VirtualPress then
        InputHandler.VirtualPress("Run", Enum.UserInputType.Keyboard)
    end

    if not wasToggled and RunHandler.Toggled == true then
        State.AutoRunToggledByAuto = true
        if InputHandler and InputHandler.VirtualRelease then
            InputHandler.VirtualRelease("Run")
        end
    else
        State.AutoRunHeld = true
    end
end

local function stopAutoRun()
    if State.AutoRunHeld then
        if InputHandler and InputHandler.VirtualRelease then
            InputHandler.VirtualRelease("Run")
        end
        State.AutoRunHeld = false
    end

    if State.AutoRunToggledByAuto then
        if RunHandler and RunHandler.Toggled == true then
            if InputHandler then
                InputHandler.VirtualPress("Run", Enum.UserInputType.Keyboard)
                InputHandler.VirtualRelease("Run")
            end
        end
        State.AutoRunToggledByAuto = false
    end
end

local function moveToPositionInternal(position, generation)
    local character, humanoid, root = getCharacter()
    if not humanoid or not root then return false end

    local path = PathfindingService:CreatePath({ AgentCanJump = true, WaypointSpacing = 5 })
    local ok = pcall(function() path:ComputeAsync(root.Position, position) end)

    if not ok or path.Status ~= Enum.PathStatus.Success then
        humanoid:MoveTo(position)
        local started = os.clock()
        while State.Enabled and State.Generation == generation and os.clock() - started < Config.MOVE_TIMEOUT do
            local _, currentHumanoid, currentRoot = getCharacter()
            if not currentHumanoid or not currentRoot then return false end
            if (currentRoot.Position - position).Magnitude <= 4 then return true end
            task.wait(0.05)
        end
        return false
    end

    for _, waypoint in ipairs(path:GetWaypoints()) do
        if not State.Enabled or State.Generation ~= generation then return false end
        local _, currentHumanoid, currentRoot = getCharacter()
        if not currentHumanoid or not currentRoot then return false end

        if (currentRoot.Position - position).Magnitude <= 4 then return true end
        if waypoint.Action == Enum.PathWaypointAction.Jump then currentHumanoid.Jump = true end

        currentHumanoid:MoveTo(waypoint.Position)
        local started = os.clock()

        while State.Enabled and State.Generation == generation and os.clock() - started < 1.2 do
            local _, checkHumanoid, checkRoot = getCharacter()
            if not checkHumanoid or not checkRoot then return false end
            if (checkRoot.Position - waypoint.Position).Magnitude <= 3 then break end
            task.wait(0.05)
        end
    end

    return true
end

local function moveToPosition(position, generation)
    startAutoRun()
    local ok, reached = pcall(moveToPositionInternal, position, generation)
    stopAutoRun()
    return ok and reached == true
end

local function attackWhileClose(targetModel, targetHumanoid, generation)
    if not State.AutoCombat then return end

    local _, humanoid, root = getCharacter()
    local targetRoot = getModelRoot(targetModel)
    if not humanoid or not root or not targetRoot then return end

    local distance = (targetRoot.Position - root.Position).Magnitude
    if distance > Config.ATTACK_RANGE then return end

    if InputHandler then
        InputHandler.VirtualPress("Combat", Enum.UserInputType.Touch)
    end

    -- ปรับปรุงจังหวะกดตีให้ต่อเนื่องขึ้น
    local started = os.clock()
    while State.Enabled
        and State.Generation == generation
        and targetModel.Parent
        and targetHumanoid.Health > 0
        and os.clock() - started < 0.25 do
        
        local _, currentHumanoid, currentRoot = getCharacter()
        local currentTargetRoot = getModelRoot(targetModel)
        if not currentHumanoid or not currentRoot or not currentTargetRoot then break end
        if (currentTargetRoot.Position - currentRoot.Position).Magnitude > Config.ATTACK_RANGE + 2 then break end
        task.wait(0.03)
    end

    if InputHandler then
        InputHandler.VirtualRelease("Combat")
    end
end

-- ลูปหลักของ Auto Farm
local function runFarm(generation)
    while State.Enabled and State.Generation == generation do
        local character, humanoid, root = getCharacter()
        if not humanoid or not root then
            status("Waiting for character...")
            task.wait(0.5)
            continue
        end

        -- 1. ล็อคและจัดการ NPC ก่อนเสมอ
        local npc, npcHumanoid, npcRoot, npcDistance = getTargetNPC()
        if npc and npcHumanoid and npcRoot then
            status("Locked Target: " .. npc.Name .. " (" .. math.floor(npcHumanoid.Health) .. " HP)")
            
            if npcDistance > Config.ATTACK_RANGE then
                moveToPosition(npcRoot.Position, generation)
            end
            
            attackWhileClose(npc, npcHumanoid, generation)
            task.wait(0.02)
            continue
        end

        -- 2. เมื่อไม่มี NPC ให้เช็คเปิดหีบ
        if State.AutoChest then
            local chest, chestPrompt, chestDistance = getNearestChest()
            if chest and chestPrompt then
                status("Opening chest: " .. chest.Name)
                if chestDistance > Config.CHEST_RANGE then
                    local chestPart = chest:IsA("BasePart") and chest or getModelRoot(chest)
                    if chestPart then moveToPosition(chestPart.Position, generation) end
                else
                    activatePrompt(chestPrompt, generation)
                end
                continue
            end
        end

        -- 3. เมื่อไม่มี NPC ให้เช็คเก็บของดรอป
        if State.AutoLoot then
            local drop, dropPrompt, dropDistance = getNearestTaggedPart(Config.LOOT_TAG, Config.TARGET_SCAN_RANGE)
            if drop and dropPrompt then
                status("Collecting loot...")
                if dropDistance > Config.PICKUP_RANGE then
                    local part = drop:IsA("BasePart") and drop or getModelRoot(drop)
                    if part then moveToPosition(part.Position, generation) end
                else
                    activatePrompt(dropPrompt, generation)
                end
                continue
            end
        end

        status("Searching for targets...")
        task.wait(0.25)
    end

    if InputHandler then InputHandler.VirtualRelease("Combat") end
    stopAutoRun()
    State.Busy = false
    State.CurrentTarget = nil
end

-- สร้างสวิตช์เปิด/ปิดใน UI
local farmSection = FarmingTab:AddSection({
    Title = "Automation",
    Description = "Auto Farm with Target Lock",
    Icon = "⚙",
    Color = Color3.fromRGB(79, 209, 197),
})

farmSection:AddToggle({
    Title = "Auto Farm",
    Description = "Lock target and attack until dead.",
    Default = false,
    Callback = function(on)
        State.Generation += 1
        local generation = State.Generation
        State.Enabled = on

        if not on then
            if InputHandler then InputHandler.VirtualRelease("Combat") end
            stopAutoRun()
            State.CurrentTarget = nil
            status("Auto Farm disabled", true)
            return
        end

        status("Auto Farm enabled", true)

        task.spawn(function()
            local ok, err = xpcall(function()
                runFarm(generation)
            end, debug.traceback)

            if InputHandler then InputHandler.VirtualRelease("Combat") end
            stopAutoRun()

            if not ok then
                pushConsoleLine("ERROR", "Auto Farm crashed:\n" .. tostring(err))
                if State.Generation == generation then
                    State.Enabled = false
                    State.Generation += 1
                end
                status("Auto Farm stopped due to an error.", true)
            end
        end)
    end,
})

Window:Notify({
    Title = "Slayer Auto Loaded",
    Content = "Target Lock system added.",
    Type = "info",
    Duration = 4,
})
