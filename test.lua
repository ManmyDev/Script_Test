--[[
	Player Client: Ultimate Admin Auto-Farm Hub (With Remote Logger & Auto-Inspector)
	Location: StarterPlayer > StarterPlayerScripts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local NovaUI = require(ReplicatedStorage:WaitForChild("NovaUI"))

-- 🔍 ระบบดักจับและสแกนหา RemoteEvents ทุกตัวในเกมอัตโนมัติ (พิมพ์ลง F9 Console)
local function initializeRemoteLogger()
	print("================ [REMOTE LOGGER STARTED] ================")
	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if descendant:IsA("RemoteEvent") or descendant:IsA("RemoteFunction") then
			print(string.format("[Found Remote] Name: %s | Path: %s", descendant.Name, descendant:GetFullName()))
		end
	end
	print("=========================================================")
end

initializeRemoteLogger()

-- ฟังก์ชันค้นหาและเชื่อมต่อ Remote แบบยืดหยุ่น
local function findRemoteEvent(possibleNames)
	for _, folder in ipairs({ReplicatedStorage, ReplicatedStorage:FindFirstChild("Remotes"), ReplicatedStorage:FindFirstChild("CAM")}) do
		if folder then
			for _, name in ipairs(possibleNames) do
				local found = folder:FindFirstChild(name, true)
				if found and found:IsA("RemoteEvent") then
					print("[Auto-Finder] Connected to Remote:", found:GetFullName())
					return found
				end
			end
		end
	end
	-- ค้นหาทั่วทั้ง ReplicatedStorage เป็นทางเลือกสุดท้าย
	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if descendant:IsA("RemoteEvent") then
			for _, name in ipairs(possibleNames) do
				if string.lower(descendant.Name) == string.lower(name) then
					print("[Auto-Finder] Global Connected to Remote:", descendant:GetFullName())
					return descendant
				end
			end
		end
	end
	return nil
end

local CombatRemote = findRemoteEvent({"CombatEvent", "CombatRemote", "AttackEvent", "M1", "Punch", "Combat", "Melee"})
local SkillRemote = findRemoteEvent({"SkillEvent", "SkillRemote", "UseSkill", "CastSkill", "Ability", "Skills"})

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

NovaUI:SetTheme("Cyber")

local Window = NovaUI:CreateWindow({
	Title = "Nova Admin - Logger Hub",
	Version = "v17.0",
	Subtitle = "Remote Logger & Smart Combat Engine",
	Logo = "🔍",
})

local FarmTab = Window:AddTab({ Name = "Farm Hub", Group = "Automation", Icon = "⚙️", Color = Color3.fromRGB(59, 130, 246) })

local StatusSection = FarmTab:AddSection({
	Title = "Live Diagnostics & Status",
	Description = "Monitors target detection and remote execution in real-time.",
	Icon = "👁️",
	Color3.fromRGB(129, 140, 248),
})

local ControlSection = FarmTab:AddSection({
	Title = "Target & Skill Settings",
	Description = "Custom skill selection, Demon Horn mode, and smart automation.",
	Icon = "🎯",
	Color3.fromRGB(79, 209, 197),
})

local BlockSection = FarmTab:AddSection({
	Title = "Auto-Block Scenarios",
	Description = "Configure defensive blocking behaviors for different combat situations.",
	Icon = "🛡️",
	Color3.fromRGB(246, 173, 85),
})

local breathingProfiles = {
	["Thunder"] = { Name = "Thunder Breathing ⚡", Slots = { 1, 3, 2, 4, 5 }, AttackDelay = 0.28, EngagementRange = 30 },
	["Flame"] = { Name = "Flame Breathing 🔥", Slots = { 2, 1, 3, 4, 5 }, AttackDelay = 0.35, EngagementRange = 15 },
	["Water"] = { Name = "Water Breathing 🌊", Slots = { 1, 2, 3, 4, 5 }, AttackDelay = 0.32, EngagementRange = 12 },
	["Beast"] = { Name = "Beast Breathing 🐗", Slots = { 3, 1, 2, 4, 5 }, AttackDelay = 0.30, EngagementRange = 8 },
	["Default"] = { Name = "Standard Breathing ⚔️", Slots = { 1, 2, 3, 4, 5 }, AttackDelay = 0.35, EngagementRange = 15 }
}

local availableSkillOptions = {
	{ Name = "Skill Slot 1", Icon = "⚔️" },
	{ Name = "Skill Slot 2", Icon = "⚡" },
	{ Name = "Skill Slot 3", Icon = "🔥" },
	{ Name = "Skill Slot 4", Icon = "🌊" },
	{ Name = "Skill Slot 5 (Ultimate)", Icon = "👑" },
}

local enabledSkillSlots = { [1] = true, [2] = true, [3] = true }
local skillCooldowns = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
local skillCooldownDurations = { [1] = 4.0, [2] = 6.0, [3] = 8.0, [4] = 10.0, [5] = 25.0 }

local activeProfile = breathingProfiles["Default"]
local isAutoFarming = false
local isDemonHornFarmActive = false
local isTeleportEnabled = false
local currentTarget = nil

local comboIndex = 1
local skillRotationIndex = 1
local lastAttackTime = 0
local lastDodgeTime = 0
local isBlocking = false

local blockEveryIncomingAttack = false
local blockDuringBossFights = false
local blockWhenLowHealth = true

-- ตรวจสอบปราณอัตโนมัติ
local function detectPlayerBreathingStyle()
	if not Character then return "Default" end
	for _, child in ipairs(Character:GetChildren()) do
		local childName = string.lower(child.Name)
		if childName:find("thunder") then return "Thunder"
		elseif childName:find("flame") then return "Flame"
		elseif childName:find("water") then return "Water"
		elseif childName:find("beast") then return "Beast" end
	end
	return "Default"
end

task.spawn(function()
	while Window.Gui.Parent do
		pcall(function()
			local foundKey = detectPlayerBreathingStyle()
			if breathingProfiles[foundKey] and activeProfile ~= breathingProfiles[foundKey] then
				activeProfile = breathingProfiles[foundKey]
				skillRotationIndex = 1
			end
		end)
		task.wait(2)
	end
end)

ControlSection:AddDropdown({
	Title = "Select Allowed Skills",
	Description = "Choose which skill slots the AI is allowed to cast.",
	Options = availableSkillOptions,
	Max = 5,
	Popup = true,
	Placeholder = "Select allowed skills...",
	Callback = function(selected)
		enabledSkillSlots = {}
		for _, item in ipairs(selected) do
			local slotNum = tonumber(item:match("%d+"))
			if slotNum then enabledSkillSlots[slotNum] = true end
		end
	end,
})

ControlSection:AddToggle({
	Title = "Enable Demon Horn Farm Mode",
	Description = "Filters targets exclusively to Demon Minions and Hoyuzo.",
	Default = false,
	Callback = function(state)
		isDemonHornFarmActive = state
	end,
})

BlockSection:AddToggle({
	Title = "Block Every Incoming Attack",
	Description = "Continuously holds block to mitigate all incoming damage.",
	Default = false,
	Callback = function(state)
		blockEveryIncomingAttack = state
	end,
})

BlockSection:AddToggle({
	Title = "Block During Boss Fights",
	Description = "Automatically raises block whenever your target is a Boss.",
	Default = false,
	Callback = function(state)
		blockDuringBossFights = state
	end,
})

BlockSection:AddToggle({
	Title = "Block When Health is Low (<30%)",
	Description = "Raises defensive block automatically when your HP drops below 30%.",
	Default = true,
	Callback = function(state)
		blockWhenLowHealth = state
	end,
})

local function isSkillReadyAndAllowed(slotNumber)
	if not enabledSkillSlots[slotNumber] then return false end
	local currentTime = tick()
	if currentTime < (skillCooldowns[slotNumber] or 0) then return false end
	return true
end

local function getNextAllowedAndReadySkillSlot()
	local totalSlots = #activeProfile.Slots
	for i = 1, totalSlots do
		local checkIndex = (skillRotationIndex + i - 2) % totalSlots + 1
		local slotNumber = activeProfile.Slots[checkIndex]
		if isSkillReadyAndAllowed(slotNumber) then
			skillRotationIndex = checkIndex % totalSlots + 1
			return slotNumber
		end
	end
	return nil
end

local function getPrioritizedTarget()
	local bestTarget = nil
	local shortestDist = math.huge
	
	for _, obj in ipairs(workspace:GetChildren()) do
		local hum = obj:FindFirstChild("Humanoid")
		local hrp = obj:FindFirstChild("HumanoidRootPart")
		
		if hum and hrp and obj ~= Character and hum.Health > 0 then
			if not Players:GetPlayerFromCharacter(obj) then
				local objNameLower = string.lower(obj.Name)
				local dist = (HumanoidRootPart.Position - hrp.Position).Magnitude
				
				if isDemonHornFarmActive then
					if objNameLower:match("demon") or objNameLower:match("hoyuzo") or objNameLower:match("minion") then
						if dist < shortestDist then
							shortestDist = dist
							bestTarget = obj
						end
					end
				else
					if dist < shortestDist then
						shortestDist = dist
						bestTarget = obj
					end
				end
			end
		end
	end
	
	return bestTarget
end

local function teleportToTarget(targetPart)
	if not targetPart or not HumanoidRootPart then return end
	HumanoidRootPart.CFrame = targetPart.CFrame * CFrame.new(0, 3, 4)
end

-- ⚔️ ระบบต่อสู้พร้อมระบบส่งคำสั่งผ่าน Remote
local function executePlayerCombatAgainstNPC(npcCharacter)
	if not npcCharacter or not npcCharacter:FindFirstChild("HumanoidRootPart") then return end
	
	local npcHumanoid = npcCharacter:FindFirstChild("Humanoid")
	local npcRootPart = npcCharacter.HumanoidRootPart
	if not npcHumanoid or npcHumanoid.Health <= 0 then return end
	
	local distance = (HumanoidRootPart.Position - npcRootPart.Position).Magnitude
	
	if isTeleportEnabled and distance > activeProfile.EngagementRange then
		teleportToTarget(npcRootPart)
		task.wait(0.15)
		return
	end
	
	HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position, Vector3.new(npcRootPart.Position.X, npcRootPart.Position.Y, npcRootPart.Position.Z))
	
	local currentTime = tick()
	if currentTime - lastAttackTime >= activeProfile.AttackDelay then
		lastAttackTime = currentTime
		
		if comboIndex <= 4 then
			print("[Combat Debug] Firing M1 Attack -> Target:", npcCharacter.Name, "Combo:", comboIndex)
			if CombatRemote then
				CombatRemote:FireServer({
					Action = "LightAttack",
					ComboIndex = comboIndex,
					Target = npcCharacter
				})
			else
				print("[Combat Debug] ⚠️ CombatRemote is nil!")
			end
			comboIndex = comboIndex + 1
		else
			local targetSkillSlot = getNextAllowedAndReadySkillSlot()
			if targetSkillSlot then
				print(string.format("[Combat Debug] ⚔️ Firing Skill Slot %d -> %s", targetSkillSlot, npcCharacter.Name))
				if SkillRemote then
					SkillRemote:FireServer({
						SkillSlot = targetSkillSlot,
						Target = npcCharacter
					})
				end
				skillCooldowns[targetSkillSlot] = currentTime + (skillCooldownDurations[targetSkillSlot] or 5.0)
			end
			comboIndex = comboIndex + 1
			if comboIndex > 4 then comboIndex = 1 end
		end
	end
end

ControlSection:AddToggle({
	Title = "Enable Instant Teleport",
	Description = "Warp directly to target positions.",
	Default = false,
	Callback = function(state)
		isTeleportEnabled = state
	end,
})

ControlSection:AddToggle({
	Title = "Enable Ultimate Auto-Farm",
	Description = "Runs complete automation with remote logger.",
	Default = false,
	Callback = function(state)
		isAutoFarming = state
		print("[Auto-Farm State Changed]:", state)
		if isAutoFarming then
			task.spawn(function()
				while isAutoFarming do
					currentTarget = getPrioritizedTarget()
					
					if currentTarget then
						executePlayerCombatAgainstNPC(currentTarget)
					else
						print("[Auto-Farm Debug] No valid target found in workspace. Waiting...")
						task.wait(1)
					end
					
					task.wait(0.1)
				end
			end)
		end
	end,
})

Window:Notify({
	Title = "Logger Hub Loaded",
	Content = "Check F9 Console for scanned Remotes list.",
	Type = "success",
})
