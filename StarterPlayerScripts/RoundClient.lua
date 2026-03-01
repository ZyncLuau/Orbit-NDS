local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local lobbyGui = playerGui:WaitForChild("LobbyGui")
local mapSelector = lobbyGui:WaitForChild("MapSelector")
local mapTitle = mapSelector:WaitForChild("Title")
local mapImage = mapSelector:WaitForChild("MapImage")

local leaderboardFrame = lobbyGui:WaitForChild("RoundLeaderBoard")
local scrollingFrame = leaderboardFrame:WaitForChild("ScrollingFrame")
local playerRowTemplate = scrollingFrame:WaitForChild("PlayerRowTemplate")

local roundGui = playerGui:WaitForChild("Round")
local heartContainer = roundGui:WaitForChild("HeartContainer")
local heart1 = heartContainer:WaitForChild("Heart1")
local heart2 = heartContainer:WaitForChild("Heart2")
local heart3 = heartContainer:WaitForChild("Heart3")
local timerLabel = roundGui:WaitForChild("Timer")

local overAllGui = playerGui:WaitForChild("OverAll")
local gameStatus = overAllGui:WaitForChild("GameStatus")

local deathGui = playerGui:WaitForChild("Death")

local roundStateEvent = ReplicatedStorage:WaitForChild("RoundState")
local roundResultsEvent = ReplicatedStorage:WaitForChild("RoundResults")

local mapThumbnails = {
	[1] = "rbxassetid://108550486095433",
	[2] = "rbxassetid://95868762816735",
	[3] = "rbxassetid://96271184762844",
	[4] = "rbxassetid://129608192803104",
	[5] = "rbxassetid://87333158356434",
	[6] = "rbxassetid://110692766316205",
	[7] = "rbxassetid://109218557319688",
	[8] = "rbxassetid://79852948290726",
	[9] = "rbxassetid://71492571191506",
}

local fullHeartImage = heart1.Image
local defaultHeartImages = {
	heart1.Image,
	heart2.Image ~= "" and heart2.Image or fullHeartImage,
	heart3.Image ~= "" and heart3.Image or fullHeartImage,
}

local phase = "Intermission"
local phaseDuration = 0
local phaseStartTime = 0
local selectedMapIndex = nil
local resultsVisible = false

local rouletteActive = false
local rouletteNextTick = 0
local roulettePhase = 0
local rouletteHoldImageId = mapThumbnails[1]

local function setRoundVisible(isVisible)
	roundGui.Enabled = isVisible
	heartContainer.Visible = isVisible
	timerLabel.Visible = isVisible
	if not isVisible then
		timerLabel.Text = ""
	end
end

local function resetHeartsToFull()
	heart1.Image = defaultHeartImages[1]
	heart2.Image = defaultHeartImages[2]
	heart3.Image = defaultHeartImages[3]
end

local function clearLeaderboardRows()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child ~= playerRowTemplate then
			child:Destroy()
		end
	end
end

local function hideResults()
	resultsVisible = false
	leaderboardFrame.Visible = false
	clearLeaderboardRows()
end

local function showResults(results)
	resultsVisible = true
	leaderboardFrame.Visible = true
	clearLeaderboardRows()

	for _, entry in ipairs(results) do
		local row = playerRowTemplate:Clone()
		row.Visible = true
		row.Name = "PlayerRow_" .. entry.userId
		row.Parent = scrollingFrame

		local profilePicture = row:FindFirstChild("ProfilePicture")
		local playerName = row:FindFirstChild("PlayerName")
		local timeLabel = row:FindFirstChild("Time")

		if profilePicture and profilePicture:IsA("ImageLabel") then
			profilePicture.Image = Players:GetUserThumbnailAsync(
				entry.userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
		end

		if playerName and playerName:IsA("TextLabel") then
			playerName.Text = entry.name
		end

		if timeLabel and timeLabel:IsA("TextLabel") then
			if entry.dnf then
				timeLabel.Text = "DNF"
				timeLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
			else
				timeLabel.Text = string.format("%.2fs", entry.time)
				timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			end
		end
	end
end

local function resetMapSelectorVisuals()
	rouletteActive = false
	roulettePhase = 0
	rouletteNextTick = 0
	mapSelector.Visible = false
	mapImage.ImageTransparency = 1
	mapImage.Image = ""
	mapTitle.Text = "Selecting Map"
end

local function applyPhaseVisuals(newPhase)
	if newPhase == "Round" then
		hideResults()
		setRoundVisible(true)
		resetHeartsToFull()
		gameStatus.Text = "Round in progress"
		deathGui.Enabled = false
		mapSelector.Visible = false
	elseif newPhase == "Results" then
		setRoundVisible(false)
		resetMapSelectorVisuals()
		gameStatus.Text = "Round Results"
		deathGui.Enabled = false
	else
		setRoundVisible(false)
		hideResults()
		resetMapSelectorVisuals()
		gameStatus.Text = "Intermission"
		deathGui.Enabled = false
	end
end

roundStateEvent.OnClientEvent:Connect(function(newPhase, duration, mapIndex, startTime)
	phase = newPhase or "Intermission"
	phaseDuration = duration or 0
	selectedMapIndex = mapIndex
	phaseStartTime = startTime or workspace:GetServerTimeNow()
	applyPhaseVisuals(phase)
end)

roundResultsEvent.OnClientEvent:Connect(function(results)
	if phase == "Results" then
		showResults(results)
	end
end)

RunService.RenderStepped:Connect(function()
	local now = workspace:GetServerTimeNow()

	if phase == "Round" then
		local elapsed = now - phaseStartTime
		local remaining = math.max(0, phaseDuration - elapsed)
		timerLabel.Text = tostring(math.ceil(remaining))
		return
	end

	if phase ~= "Intermission" then
		return
	end

	local elapsed = now - phaseStartTime
	local remaining = math.max(0, phaseDuration - elapsed)

	if remaining > 10 then
		if mapSelector.Visible then
			mapSelector.Visible = false
		end
		return
	end

	mapSelector.Visible = true

	if remaining > 5 then
		if not rouletteActive then
			rouletteActive = true
			roulettePhase = 0
			rouletteNextTick = 0
			mapImage.ImageTransparency = 1
			mapTitle.Text = "Selecting Map."
		end

		if now >= rouletteNextTick then
			if roulettePhase == 0 then
				mapTitle.Text = "Selecting Map" .. string.rep(".", ((math.floor(now * 3) % 3) + 1))
				rouletteHoldImageId = mapThumbnails[math.random(1, 9)] or ""
				mapImage.Image = rouletteHoldImageId
				mapImage.ImageTransparency = 1
				roulettePhase = 1
				rouletteNextTick = now + 0.07
			else
				mapImage.ImageTransparency = 0
				roulettePhase = 0
				rouletteNextTick = now + 0.07
			end
		end
	else
		if rouletteActive then
			rouletteActive = false
		end
		mapTitle.Text = "Selected Map:"
		mapImage.Image = mapThumbnails[selectedMapIndex] or ""
		mapImage.ImageTransparency = 0
	end
end)
