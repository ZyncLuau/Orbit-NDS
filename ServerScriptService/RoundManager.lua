local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ROUND_TIME = 180
local INTERMISSION_TIME = 20
local RESULTS_SHOW_TIME = 8
local SPAWN_EXTRA_OFFSET = 5

local mapsFolder = ReplicatedStorage:WaitForChild("Maps")
local currentMapFolder = Workspace:WaitForChild("CurrentMap")
local lobbyModel = Workspace:WaitForChild("Lobby")
local lobbyBase = lobbyModel:WaitForChild("Base")

local roundStateEvent = ReplicatedStorage:WaitForChild("RoundState")
local roundResultsEvent = ReplicatedStorage:WaitForChild("RoundResults")

local currentMapIndex = nil
local currentMapModel = nil
local roundPlayers = {}
local roundStartTimestamp = nil
local roundRunning = false

local currentPhase = "Intermission"
local currentPhaseDuration = INTERMISSION_TIME
local currentPhaseStartTime = 0

local finishTouchConnection = nil

local function getSafeYOffset(part, extraOffset)
	extraOffset = extraOffset or SPAWN_EXTRA_OFFSET
	if not part or not part:IsA("BasePart") then
		return extraOffset
	end
	return (part.Size.Y * 0.5) + extraOffset
end

local function teleportTo(part, player, extraOffset)
	if not part or not player then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end

	local yOffset = getSafeYOffset(part, extraOffset)
	hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, yOffset, 0))
end

local function teleportToLobby(player)
	teleportTo(lobbyBase, player, SPAWN_EXTRA_OFFSET)
end

local function getRoundPlayers()
	local players = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		players[plr] = {
			finished = false,
			finishTime = nil,
			leftGame = false,
		}
	end
	return players
end

local function sendCurrentPhaseToPlayer(player)
	local now = Workspace:GetServerTimeNow()

	if currentPhase == "Intermission" then
		local elapsed = now - currentPhaseStartTime
		local remaining = math.max(0, currentPhaseDuration - elapsed)
		roundStateEvent:FireClient(player, "Intermission", remaining, currentMapIndex, currentPhaseStartTime)
	elseif currentPhase == "Round" then
		-- Joiners during active round should stay in lobby and not see round UI.
		roundStateEvent:FireClient(player, "Intermission", 0, currentMapIndex, now)
	elseif currentPhase == "Results" then
		roundStateEvent:FireClient(player, "Results", 0, currentMapIndex, currentPhaseStartTime)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		if currentPhase == "Round" and not roundPlayers[player] then
			task.defer(teleportToLobby, player)
		end
	end)

	task.wait(1)
	sendCurrentPhaseToPlayer(player)
	if currentPhase == "Round" and not roundPlayers[player] then
		teleportToLobby(player)
	end
end)

local function disconnectFinishTouch()
	if finishTouchConnection then
		finishTouchConnection:Disconnect()
		finishTouchConnection = nil
	end
end

local function hookFinishPart(finishPart)
	disconnectFinishTouch()

	if not finishPart then
		warn("No Finish part found in map " .. tostring(currentMapIndex))
		return
	end

	local touchedDebounce = {}
	finishTouchConnection = finishPart.Touched:Connect(function(hit)
		if not roundRunning then
			return
		end

		local character = hit.Parent
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local player = Players:GetPlayerFromCharacter(character)
		if not player then
			return
		end

		if touchedDebounce[player] then
			return
		end
		touchedDebounce[player] = true

		local data = roundPlayers[player]
		if data and (not data.finished) then
			data.finished = true
			local now = Workspace:GetServerTimeNow()
			if roundStartTimestamp then
				data.finishTime = math.max(0, now - roundStartTimestamp)
			else
				data.finishTime = 0
			end
		end

		task.delay(0.2, function()
			touchedDebounce[player] = nil
		end)
	end)
end

while true do
	roundRunning = false
	currentMapModel = nil
	roundPlayers = {}

	currentMapIndex = math.random(1, 9)
	local intermissionStart = Workspace:GetServerTimeNow()
	currentPhase = "Intermission"
	currentPhaseDuration = INTERMISSION_TIME
	currentPhaseStartTime = intermissionStart

	roundStateEvent:FireAllClients("Intermission", INTERMISSION_TIME, currentMapIndex, intermissionStart)

	while Workspace:GetServerTimeNow() - intermissionStart < INTERMISSION_TIME do
		task.wait(0.1)
	end

	local mapName = tostring(currentMapIndex)
	local mapSource = mapsFolder:FindFirstChild(mapName)
	if not mapSource then
		warn("Map " .. mapName .. " missing in ReplicatedStorage.Maps")
		task.wait(1)
		continue
	end

	for _, child in ipairs(currentMapFolder:GetChildren()) do
		child:Destroy()
	end

	currentMapModel = mapSource:Clone()
	currentMapModel.Name = "ActiveMap"
	currentMapModel.Parent = currentMapFolder

	local startFolder = currentMapModel:FindFirstChild("Start")
	local spawnLocation = startFolder and startFolder:FindFirstChild("SpawnLocation")
	if not spawnLocation or not spawnLocation:IsA("BasePart") then
		warn("Map " .. mapName .. " missing Start/SpawnLocation BasePart")
		for _, child in ipairs(currentMapFolder:GetChildren()) do
			child:Destroy()
		end
		task.wait(1)
		continue
	end

	local finishPart = currentMapModel:FindFirstChild("Finish", true)
	hookFinishPart(finishPart)

	roundPlayers = getRoundPlayers()
	roundRunning = true
	roundStartTimestamp = Workspace:GetServerTimeNow()
	currentPhase = "Round"
	currentPhaseDuration = ROUND_TIME
	currentPhaseStartTime = roundStartTimestamp

	for plr in pairs(roundPlayers) do
		teleportTo(spawnLocation, plr, SPAWN_EXTRA_OFFSET)
	end

	roundStateEvent:FireAllClients("Round", ROUND_TIME, currentMapIndex, roundStartTimestamp)

	local ended = false
	while not ended do
		local now = Workspace:GetServerTimeNow()
		local elapsed = now - roundStartTimestamp
		local timeLeft = ROUND_TIME - elapsed

		for plr, data in pairs(roundPlayers) do
			if plr.Parent ~= Players then
				data.leftGame = true
			end
		end

		local activeCount = 0
		for _, data in pairs(roundPlayers) do
			if (not data.leftGame) and (not data.finished) then
				activeCount += 1
			end
		end

		if activeCount == 0 or timeLeft <= 0 then
			ended = true
		else
			task.wait(0.1)
		end
	end

	roundRunning = false
	currentPhase = "Results"
	currentPhaseDuration = 0
	currentPhaseStartTime = Workspace:GetServerTimeNow()

	local finished = {}
	local dnfs = {}
	for plr, data in pairs(roundPlayers) do
		if plr.Parent ~= Players then
			data.finishTime = nil
		end

		local entry = {
			userId = plr.UserId,
			name = plr.Name,
			time = data.finishTime,
			dnf = data.finishTime == nil,
		}

		if entry.dnf then
			table.insert(dnfs, entry)
		else
			table.insert(finished, entry)
		end
	end

	table.sort(finished, function(a, b)
		return a.time < b.time
	end)

	local results = {}
	for _, entry in ipairs(finished) do
		table.insert(results, entry)
	end
	for _, entry in ipairs(dnfs) do
		table.insert(results, entry)
	end

	for _, plr in ipairs(Players:GetPlayers()) do
		teleportToLobby(plr)
	end

	roundStateEvent:FireAllClients("Results", 0, currentMapIndex, currentPhaseStartTime)
	roundResultsEvent:FireAllClients(results)

	task.wait(RESULTS_SHOW_TIME)

	disconnectFinishTouch()
	for _, child in ipairs(currentMapFolder:GetChildren()) do
		child:Destroy()
	end
end
