--[[
	Player Client: Ultimate Admin Auto-Farm Hub (Auto-Detect Breathing + Custom Skills + Cooldown Tracker)
	Location: StarterPlayer > StarterPlayerScripts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local NovaUI = require(ReplicatedStorage:WaitForChild("NovaUI"))

-- อ้างอิง Remotes ของระบบการต่อสู้
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:FindFirstChild("CAM")
local CombatRemote = Remotes and (Remotes:FindFirstChild("CombatEvent") or Remotes:FindFirstChild("CombatRemote"))
local SkillRemote = Remotes and (Remotes:FindFirstChild("SkillEvent") or Remotes:FindFirstChild("SkillRemote"))

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")
local Humanoid = Character:WaitForChild("Humanoid")

NovaUI:SetTheme("Cyber")

local Window = NovaUI:CreateWindow({
	Title = "Nova Admin - Ultimate Auto Farm",
	Version = "v15.0",
	Subtitle = "Auto-Detect Breathing & Smart Skill Engine",
	Logo = "⚔️",
})

local FarmTab = Window:AddTab({ Name = "Farm Hub", Group = "Automation", Icon = "⚙️", Color = Color3.fromRGB(59, 130, 246) })

local StatusSection = FarmTab:AddSection({
	Title = "Live Character Breathing Status",
	Description = "Detects your character's equipped Breathing Style in real-time.",
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

-- 📜 ฐานข้อมูลโปรไฟล์ค่าพลังของแต่ละปราณ
local breathingProfiles = {
	["Thunder"] = {
		Name = "Thunder Breathing ⚡",
		Slots = { 1, 3, 2, 4, 5 },
		AttackDelay = 0.28,
		EngagementRange = 30,
	},
	["Flame"] = {
		Name = "Flame Breathing 🔥",
		Slots = { 2, 1, 3, 4, 5 },
		AttackDelay = 0.35,
		EngagementRange = 15,
	},
	["Water"] = {
		Name = "Water Breathing 🌊",
		Slots = { 1, 2, 3, 4, 5 },
		AttackDelay = 0.32,
		EngagementRange = 12,
	},
	["Beast"] = {
		Name = "Beast Breathing 🐗",
		Slots = { 3, 1, 2, 4, 5 },
		AttackDelay = 0.30,
		EngagementRange = 8,
	},
	["Default"] = {
		Name = "Standard Breathing ⚔️",
		Slots = { 1, 2, 3, 4, 5 },
		AttackDelay = 0.35,
		EngagementRange = 15,
	}
}

-- สกิลทั้งหมดที่มีในระบบ (Slot 1 ถึง Slot 5)
local availableSkillOptions = {
	{ Name = "Skill Slot 1", Icon = "⚔️" },
	{ Name = "Skill Slot 2", Icon = "⚡" },
	{ Name = "Skill Slot 3", Icon = "🔥" },
	{ Name = "Skill Slot 4", Icon = "🌊" },
	{ Name = "Skill Slot 5 (Ultimate)", Icon = "👑" },
}

-- ตารางเก็บสถานะสกิลที่เปิดใช้งาน (Default: เปิด 1, 2, 3)
local enabledSkillSlots = { [1] = true, [2] = true, [3] = true }

-- ระบบบันทึก Cooldown ของแต่ละสกิล (Local Tracker)
local skillCooldowns = { [1] = 0, [2] = 0, [3] = 0, [4] = 0, [5] = 0 }
local skillCooldownDurations = { [1] = 4.0, [2] = 6.0, [3] = 8.0, [4] = 10.0, [5] = 25.0 }

local activeProfile = breathingProfiles["Default"]
local isAutoFarming = false
local isDemonHornFarmActive = false
local isTeleportEnabled = false
local currentTarget = nil
local selectedDynamicTargets = {}

local comboIndex = 1
local skillRotationIndex = 1
local lastAttackTime = 0
local lastDodgeTime = 0
local isBlocking = false

local blockEveryIncomingAttack = false
local blockDuringBossFights = false
local blockWhenLowHealth = true

-- 🔍 ฟังก์ชัน Auto-Detect เช็คปราณจากตัวละครแบบอัตโนมัติ
local function detectPlayerBreathingStyle()
	if not Character then return "Default" end
	
	local breathingValue = Character:FindFirstChild("Breathing") or Character:FindFirstChild("BreathingStyle") or LocalPlayer:FindFirstChild("Breathing")
	if breathingValue and breathingValue.Value then
		local valName = tostring(breathingValue.Value)
		for key, _ in pairs(breathingProfiles) do
			if string.find(string.lower(valName), string.lower(key)) then
				return key
			end
		end
	end
	
	local attrBreathing = Character:GetAttribute("Breathing") or Character:GetAttribute("Style")
	if attrBreathing then
		for key, _ in pairs(breathingProfiles) do
			if string.find(string.lower(tostring(attrBreathing)), string.lower(key)) then
				return key
			end
		end
	end
	
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
				Window:Notify({
					Title = "Breathing Auto-Detected",
					Content = "Adapted profile to " .. activeProfile.Name,
					Type = "info",
				})
			end
		end)
		task.wait(2)
	end
end)

-- 🎛️ Dropdown เลือกสกิลที่อนุญาตให้ AI ใช้
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
			if slotNum then
				enabledSkillSlots[slotNum] = true
			end
		end
		print("[Skill Selector] Updated allowed skills count:", #selected)
	end,
})

ControlSection:AddToggle({
	Title = "Enable Demon Horn Farm Mode",
	Description = "Filters targets exclusively to Demon Minions, Blood Art Demons, and Hoyuzo.",
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
	Description = "Automatically raises block whenever your current target is a Boss.",
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

-- ฟังก์ชันเช็คความพร้อมของสกิล (เปิดใช้งาน + ไม่ติด Cooldown)
local function isSkillReadyAndAllowed(slotNumber)
	if not enabledSkillSlots[slotNumber] then return false end
	
	local currentTime = tick()
	if currentTime < (skillCooldowns[slotNumber] or 0) then return false end
	
	local cooldownFolder = Character:FindFirstChild("Cooldowns") or LocalPlayer:FindFirstChild("Cooldowns")
	if cooldownFolder and cooldownFolder:FindFirstChild("Skill_" .. slotNumber) then return false end
	
	if Character:GetAttribute("Skill_" .. slotNumber .. "_CD") == true then return false end
	
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
	
	for slotNumber, isEnabled in pairs(enabledSkillSlots) do
		if isEnabled and isSkillReadyAndAllowed(slotNumber) then
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
				
				if isDemonHornFarmActive then
					local isDemonTarget = objNameLower:match("demon") or objNameLower:match("hoyuzo") or objNameLower:match("minion")
					if isDemonTarget then
						local dist = (HumanoidRootPart.Position - hrp.Position).Magnitude
						if dist < shortestDist then
							shortestDist = dist
							bestTarget = obj
						end
					end
				else
					local dist = (HumanoidRootPart.Position - hrp.Position).Magnitude
					local isBoss = objNameLower:match("boss") or obj:FindFirstChild("IsBoss") or objNameLower:match("giyen") or objNameLower:match("akaza") or objNameLower:match("rengu") or objNameLower:match("hoyuzo")
					
					if isBoss then dist = dist * 0.5 end
					
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

local function checkNpcAttackAndDodge(npcCharacter)
	if not npcCharacter then return false end
	local animator = npcCharacter:FindFirstChildOfClass("Animator", true) or (npcCharacter:FindFirstChild("Humanoid") and npcCharacter.Humanoid:FindFirstChildOfClass("Animator"))
	
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			local animId = string.lower(track.Animation.AnimationId or "")
			if animId:find("attack") or animId:find("swing") or animId:find("slash") or animId:find("skill") or animId:find("smash") then
				local currentTime = tick()
				if currentTime - lastDodgeTime >= 1.5 then
					lastDodgeTime = currentTime
					if CombatRemote then
						CombatRemote:FireServer({ Action = "Dash", Direction = "Back" })
					end
					return true
				end
			end
		end
	end
	return false
end

-- ⚔️ ระบบต่อสู้หลักครบวงจร
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
	
	if checkNpcAttackAndDodge(npcCharacter) then
		task.wait(0.15)
		return
	end
	
	local myHealthPercent = Humanoid.Health / Humanoid.MaxHealth
	local currentTime = tick()
	local objNameLower = string.lower(npcCharacter.Name)
	local isCurrentTargetBoss = objNameLower:match("boss") or npcCharacter:FindFirstChild("IsBoss") or objNameLower:match("hoyuzo")
	
	local shouldBlockNow = false
	if blockEveryIncomingAttack then
		shouldBlockNow = true
	elseif blockDuringBossFights and isCurrentTargetBoss then
		shouldBlockNow = true
	elseif blockWhenLowHealth and myHealthPercent < 0.3 then
		shouldBlockNow = true
	end
	
	if shouldBlockNow then
		if not isBlocking and CombatRemote then
			isBlocking = true
			CombatRemote:FireServer({ Action = "BlockStart" })
		end
	else
		if isBlocking and (myHealthPercent >= 0.4 or (not blockEveryIncomingAttack and not (blockDuringBossFights and isCurrentTargetBoss))) then
			isBlocking = false
			if CombatRemote then
				CombatRemote:FireServer({ Action = "BlockEnd" })
			end
		end
	end
	
	HumanoidRootPart.CFrame = CFrame.new(HumanoidRootPart.Position, Vector3.new(npcRootPart.Position.X, npcRootPart.Position.Y, npcRootPart.Position.Z))
	
	if currentTime - lastAttackTime >= activeProfile.AttackDelay then
		lastAttackTime = currentTime
		
		if comboIndex <= 4 then
			if CombatRemote then
				CombatRemote:FireServer({
					Action = "LightAttack",
					ComboIndex = comboIndex,
					Target = npcCharacter
				})
			end
			comboIndex = comboIndex + 1
		else
			local targetSkillSlot = getNextAllowedAndReadySkillSlot()
			
			if targetSkillSlot then
				print(string.format("[%s] ⚔️ Firing Skill Slot %d -> %s", activeProfile.Name, targetSkillSlot, npcCharacter.Name))
				if SkillRemote then
					SkillRemote:FireServer({
						SkillSlot = targetSkillSlot,
						Target = npcCharacter
					})
				end
				skillCooldowns[targetSkillSlot] = currentTime + (skillCooldownDurations[targetSkillSlot] or 5.0)
			else
				print(string.format("[%s] ⏳ No skills ready. Performing M1 combo.", activeProfile.Name))
			end
			
			comboIndex = 1
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
	Description = "Runs complete automation with auto-detected breathing and skill filters.",
	Default = false,
	Callback = function(state)
		isAutoFarming = state
		if isAutoFarming then
			task.spawn(function()
				while isAutoFarming do
					currentTarget = getPrioritizedTarget()
					
					if currentTarget then
						executePlayerCombatAgainstNPC(currentTarget)
					else
						task.wait(1)
					end
					
					task.wait(0.1)
				end
			end)
		else
			if isBlocking and CombatRemote then
				CombatRemote:FireServer({ Action = "BlockEnd" })
				isBlocking = false
			end
		end
	end,
})

Window:Notify({
	Title = "Ultimate Script Loaded",
	Content = "All advanced systems and auto-detection initialized.",
	Type = "success",
})
