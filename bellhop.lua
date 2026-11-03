-- BellHop test for Unseen Liminality
-- Ticket ESP, BellHop alert, Auto ticket, Get ticket, Safe BellHop picture, Teleport away, Scan report.
-- Standalone, so it can be tested before it goes into the main script.
-- After testing, tap Scan report and send it back. It lists the game's real names for the
-- BellHop, the tickets and their prompts, so the main script can match them exactly.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local GuiParent = (gethui and gethui()) or game:GetService("CoreGui")
local GlobalEnv = (getgenv and getgenv()) or _G
local setClipboard = setclipboard or toclipboard or set_clipboard

if type(GlobalEnv.BellhopTestUnload) == "function" then
	pcall(GlobalEnv.BellhopTestUnload)
end

local THEME = {
	Window = Color3.fromRGB(17, 17, 21),
	Surface = Color3.fromRGB(28, 28, 34),
	Stroke = Color3.fromRGB(56, 56, 66),
	Text = Color3.fromRGB(236, 236, 240),
	SubText = Color3.fromRGB(145, 145, 158),
	Accent = Color3.fromRGB(232, 196, 84),
	AccentDark = Color3.fromRGB(28, 24, 12),
	Danger = Color3.fromRGB(200, 58, 58),
	Track = Color3.fromRGB(52, 52, 60),
	Ticket = Color3.fromRGB(255, 214, 90),
	Bellhop = Color3.fromRGB(255, 70, 70),
}

local CAMERA_WORDS = { "camera", "cam", "photo", "polaroid", "snap" }
local SPOT_WORDS = { "follow the music", "followthemusic" }
local FRESH_TICKET = 45 -- seconds a newly spawned ticket counts as a sign the BellHop spotted you

local State = {
	TicketESP = true,
	Alert = true,
	AutoTicket = false,
}

local Running = true
local Busy = false -- a ticket run or picture run is moving you around
local Connections = {}
local Tracked = { Bellhops = {}, Tickets = {}, Prompts = {} }
local ESP = {}

local function track(conn)
	table.insert(Connections, conn)
	return conn
end

local function create(className, props)
	local obj = Instance.new(className)
	if obj:IsA("GuiObject") then
		obj.BorderSizePixel = 0
	end
	for key, value in pairs(props) do
		if key ~= "Parent" then
			obj[key] = value
		end
	end
	obj.Parent = props.Parent
	return obj
end

local function corner(obj, radius)
	create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = obj })
end

local function hasWord(text, word)
	return string.find(string.lower(text), word, 1, true) ~= nil
end

local function getCharacter()
	local char = LocalPlayer.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
end

local function myPosition()
	local _, _, root = getCharacter()
	if root then
		return root.Position
	end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

-- Inside a player's character or backpack, so it is held, not lying on the map.
local function insidePlayer(obj)
	local node = obj.Parent
	while node and node ~= game do
		if node:IsA("Backpack") or (node:IsA("Model") and Players:GetPlayerFromCharacter(node)) then
			return true
		end
		node = node.Parent
	end
	return false
end

local function partOf(obj)
	if obj:IsA("BasePart") then
		return obj
	end
	if obj:IsA("Attachment") then
		return obj.Parent and obj.Parent:IsA("BasePart") and obj.Parent or nil
	end
	if obj:IsA("Tool") then
		return obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart", true)
	end
	if obj:IsA("Model") then
		return obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart") or obj:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function promptIn(obj)
	if obj:IsA("ProximityPrompt") then
		return obj
	end
	return obj:FindFirstChildWhichIsA("ProximityPrompt", true)
end

local function flatLook(part)
	local look = part.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

-- Scanning: BellHop models, things named ticket, and every prompt on the map.
-- old marks things already there when the script started, so they do not count as fresh spawns.
local function consider(obj, old)
	local stamp = old and 0 or os.clock()
	if obj:IsA("Model") and hasWord(obj.Name, "bellhop") then
		Tracked.Bellhops[obj] = true
	end
	if (obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool")) and hasWord(obj.Name, "ticket") then
		Tracked.Tickets[obj] = stamp
	elseif obj:IsA("ProximityPrompt") then
		Tracked.Prompts[obj] = stamp
	end
end

for _, obj in ipairs(workspace:GetDescendants()) do
	consider(obj, true)
end
track(workspace.DescendantAdded:Connect(function(obj)
	consider(obj, false)
end))

local function nearestBellhop()
	local best, bestDist = nil, math.huge
	local origin = myPosition()
	for obj in pairs(Tracked.Bellhops) do
		if obj.Parent == nil then
			Tracked.Bellhops[obj] = nil
		elseif obj:IsDescendantOf(workspace) and not insidePlayer(obj) then
			local part = partOf(obj)
			if part then
				local dist = (part.Position - origin).Magnitude
				if dist < bestDist then
					best, bestDist = obj, dist
				end
			end
		end
	end
	return best, bestDist
end

local function promptText(prompt)
	return prompt.ObjectText .. " " .. prompt.ActionText .. " " .. prompt.Name
end

-- The ticket's glowing aura: a light, particles, sparkles, a beam or a highlight on it.
local function glows(obj)
	local function check(root)
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Highlight") or d:IsA("Sparkles") or d:IsA("Beam") then
				return true
			end
		end
		return false
	end
	if check(obj) then
		return true
	end
	local parent = obj.Parent
	if parent and parent:IsA("Model") and parent ~= workspace then
		local _, size = parent:GetBoundingBox()
		if size.Magnitude < 12 then
			return check(parent)
		end
	end
	return false
end

-- Tickets lying on the map, nearest first, as { Object, Part, Prompt, Distance, Stamp }.
-- A ticket is anything named ticket, or anything with a prompt that mentions a ticket.
-- loose also counts small glowing things with a prompt, in case the ticket has a plain name.
local function findTickets(loose)
	local list, seen = {}, {}
	local origin = myPosition()
	local function add(obj, prompt, stamp)
		if seen[obj] or not obj:IsDescendantOf(workspace) or insidePlayer(obj) then
			return
		end
		local part = partOf(obj)
		prompt = prompt or promptIn(obj)
		if not part or (prompt and not prompt.Enabled) or (not prompt and part.Transparency >= 1) then
			return
		end
		seen[obj] = true
		table.insert(list, {
			Object = obj,
			Part = part,
			Prompt = prompt,
			Distance = (part.Position - origin).Magnitude,
			Stamp = stamp or 0,
		})
	end

	for obj, stamp in pairs(Tracked.Tickets) do
		if obj.Parent == nil then
			Tracked.Tickets[obj] = nil
		else
			add(obj, nil, stamp)
		end
	end
	for prompt, stamp in pairs(Tracked.Prompts) do
		if prompt.Parent == nil then
			Tracked.Prompts[prompt] = nil
		elseif prompt.Enabled and prompt:IsDescendantOf(workspace) then
			local holder = prompt.Parent
			if holder and holder:IsA("Attachment") then
				holder = holder.Parent
			end
			if holder then
				if hasWord(promptText(prompt), "ticket") then
					add(holder, prompt, stamp)
				elseif loose and glows(holder) then
					local part = partOf(holder)
					if part and part.Size.Magnitude < 6 then
						add(holder, prompt, stamp)
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	return list
end

-- Visible on screen: every frame above it is visible and its ScreenGui is on.
local function shown(obj)
	local node = obj
	while node and not node:IsA("LayerCollector") do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node == nil or node.Enabled
end

-- "Follow The Music" on your screen means the BellHop spotted you.
local function spottedText()
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return false
	end
	for _, obj in ipairs(gui:GetDescendants()) do
		if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.TextTransparency < 1 then
			local text = string.lower(obj.ContentText)
			for _, word in ipairs(SPOT_WORDS) do
				if string.find(text, word, 1, true) and shown(obj) then
					return true
				end
			end
		end
	end
	return false
end

local function freshTicket(tickets)
	for _, ticket in ipairs(tickets) do
		if ticket.Stamp > 0 and os.clock() - ticket.Stamp < FRESH_TICKET then
			return true
		end
	end
	return false
end

-- Toast and alert banner
local Screen = create("ScreenGui", {
	Name = "BellhopTest",
	ResetOnSpawn = false,
	DisplayOrder = 60,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = GuiParent,
})
local EspFolder = create("Folder", { Name = "BellhopTestESP", Parent = GuiParent })

local Toast = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 42),
	Size = UDim2.fromOffset(0, 30),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.Window,
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = THEME.Text,
	TextTransparency = 1,
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	Parent = Screen,
})
corner(Toast, 8)
create("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), Parent = Toast })

local toastId = 0
local function notify(text, sticky, color)
	toastId += 1
	local id = toastId
	Toast.Text = text
	Toast.TextColor3 = color or THEME.Text
	Toast.BackgroundTransparency = 0.05
	Toast.TextTransparency = 0
	if not sticky then
		task.delay(2.5, function()
			if id == toastId and Toast.Parent then
				Toast.BackgroundTransparency = 1
				Toast.TextTransparency = 1
			end
		end)
	end
end

local Banner = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 80),
	Size = UDim2.fromOffset(0, 34),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.Danger,
	Text = "BellHop spotted you! Find a ticket",
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	Visible = false,
	Parent = Screen,
})
corner(Banner, 10)
create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = Banner })

-- ESP: tickets in gold, the BellHop in red, both through walls with distance.
local function espFor(target, color, label)
	local entry = ESP[target]
	if not entry then
		local part = partOf(target)
		if not part then
			return
		end
		local highlight = create("Highlight", {
			Adornee = target:IsA("Tool") and part or target,
			FillColor = color,
			OutlineColor = color,
			FillTransparency = 0.55,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Parent = EspFolder,
		})
		local board = create("BillboardGui", {
			Adornee = part,
			AlwaysOnTop = true,
			Size = UDim2.fromOffset(160, 24),
			StudsOffset = Vector3.new(0, 2.5, 0),
			Parent = EspFolder,
		})
		local text = create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			TextColor3 = color,
			TextStrokeTransparency = 0.3,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			Parent = board,
		})
		entry = { Highlight = highlight, Board = board, Text = text, Part = part }
		ESP[target] = entry
	end
	entry.Text.Text = string.format("%s [%dm]", label, math.floor((entry.Part.Position - myPosition()).Magnitude))
	entry.Seen = true
end

local function syncESP(bellhop, tickets)
	for _, entry in pairs(ESP) do
		entry.Seen = false
	end
	if State.TicketESP then
		for _, ticket in ipairs(tickets) do
			espFor(ticket.Object, THEME.Ticket, "Ticket")
		end
		if bellhop then
			espFor(bellhop, THEME.Bellhop, "BellHop")
		end
	end
	for target, entry in pairs(ESP) do
		if not entry.Seen or not target:IsDescendantOf(workspace) then
			entry.Highlight:Destroy()
			entry.Board:Destroy()
			ESP[target] = nil
		end
	end
end

-- Moving and interacting
local function teleport(cframe)
	local _, _, root = getCharacter()
	if not root then
		return false
	end
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

local function waitFor(check, timeout)
	local deadline = os.clock() + timeout
	while os.clock() < deadline and Running do
		if check() then
			return true
		end
		task.wait(0.1)
	end
	return check()
end

-- Uses the executor's fireproximityprompt when it has one, otherwise holds the prompt itself.
local function firePrompt(prompt)
	if typeof(fireproximityprompt) == "function" and pcall(fireproximityprompt, prompt) then
		return true
	end
	return pcall(function()
		prompt.HoldDuration = 0
		prompt:InputHoldBegin()
		task.wait(0.1)
		prompt:InputHoldEnd()
	end)
end

local function touch(part)
	local _, _, root = getCharacter()
	if root and typeof(firetouchinterest) == "function" then
		pcall(firetouchinterest, root, part, 0)
		task.wait()
		pcall(firetouchinterest, root, part, 1)
	end
end

local function findTool(words)
	for _, holder in ipairs({ LocalPlayer.Character or false, LocalPlayer:FindFirstChildOfClass("Backpack") or false }) do
		if holder then
			for _, child in ipairs(holder:GetChildren()) do
				if child:IsA("Tool") then
					for _, word in ipairs(words) do
						if hasWord(child.Name, word) then
							return child
						end
					end
				end
			end
		end
	end
	return nil
end

-- A ticket in your hands: a ticket tool, something named ticket on your character,
-- or a ticket attribute or value on your player.
local function holdingTicket()
	if findTool({ "ticket" }) then
		return true
	end
	local char = LocalPlayer.Character
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if hasWord(d.Name, "ticket") then
				return true
			end
		end
	end
	for key, value in pairs(LocalPlayer:GetAttributes()) do
		if hasWord(key, "ticket") and value then
			return true
		end
	end
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, d in ipairs(LocalPlayer:GetDescendants()) do
		if d:IsA("ValueBase") and hasWord(d.Name, "ticket") and not (gui and d:IsDescendantOf(gui)) then
			local ok, value = pcall(function()
				return d.Value
			end)
			if ok and value and value ~= 0 and value ~= "" then
				return true
			end
		end
	end
	return false
end

local function collect(entry)
	local part = entry.Part
	teleport(CFrame.new(part.Position + Vector3.new(0, 2.5, 0)))
	task.wait(0.25)
	if entry.Prompt then
		firePrompt(entry.Prompt)
	end
	touch(part)
	local click = entry.Object:FindFirstChildWhichIsA("ClickDetector", true)
	if click and typeof(fireclickdetector) == "function" then
		pcall(fireclickdetector, click)
	end
	return waitFor(function()
		return holdingTicket()
			or not entry.Object:IsDescendantOf(workspace)
			or (entry.Prompt ~= nil and not entry.Prompt.Enabled)
	end, 2.5)
end

-- Stands 3 studs in front of the BellHop holding the ticket and tries every way to hand it over:
-- his prompts, using the ticket, and touching him.
local function give()
	local bellhop = nearestBellhop()
	if not bellhop then
		return false, "No BellHop loaded"
	end
	local part = partOf(bellhop)
	local _, hum = getCharacter()
	local ticket = findTool({ "ticket" })
	if ticket and hum and ticket.Parent ~= LocalPlayer.Character then
		hum:EquipTool(ticket)
		task.wait(0.2)
	end
	local spot = part.Position + flatLook(part) * 3
	teleport(CFrame.lookAt(spot, Vector3.new(part.Position.X, spot.Y, part.Position.Z)))
	task.wait(0.2)
	for _, prompt in ipairs(bellhop:GetDescendants()) do
		if prompt:IsA("ProximityPrompt") and prompt.Enabled then
			firePrompt(prompt)
		end
	end
	if ticket then
		pcall(function()
			ticket:Activate()
		end)
	end
	touch(part)
	local given = waitFor(function()
		return not holdingTicket() or not spottedText()
	end, 3)
	return given, given and "Ticket given, the BellHop backed off" or "He did not take the ticket"
end

-- Waits up to 4 seconds for a ticket to spawn, picks up the nearest one that works, then gives it.
local function getAndGive()
	local tickets = {}
	waitFor(function()
		tickets = findTickets(true)
		return #tickets > 0
	end, 4)
	if #tickets == 0 then
		return false, "No ticket found"
	end
	local got = false
	for index = 1, math.min(#tickets, 3) do
		if collect(tickets[index]) then
			got = true
			break
		end
	end
	if not got then
		return false, "Ticket pickup failed"
	end
	notify("Got a ticket, giving it to the BellHop", true, THEME.Accent)
	return give()
end

local function ticketRun()
	if Busy then
		return
	end
	Busy = true
	local _, _, root = getCharacter()
	local home = root and root.CFrame
	notify("Getting a ticket", true, THEME.Accent)
	local ok, given, message = pcall(getAndGive)
	if not ok then
		message = "Ticket run failed: " .. tostring(given)
	end
	if home then
		teleport(home)
	end
	Busy = false
	notify(message or "Done")
end

-- Safe BellHop picture: let him spot you from 14 studs, get a ticket and give it to him so he
-- stops chasing, take the picture from 8 studs with the camera locked on him, then go back.
local function safePicture()
	if Busy then
		return
	end
	local bellhop = nearestBellhop()
	if not bellhop then
		notify("No BellHop loaded")
		return
	end
	Busy = true
	local _, _, root = getCharacter()
	local home = root and root.CFrame
	local message = nil
	local camLock = nil

	local ok, err = pcall(function()
		local part = partOf(bellhop)
		notify("Letting the BellHop spot you", true, THEME.Accent)
		local spot = part.Position + flatLook(part) * 14 + Vector3.new(0, 1, 0)
		teleport(CFrame.lookAt(spot, Vector3.new(part.Position.X, spot.Y, part.Position.Z)))
		local spotted = waitFor(function()
			return spottedText() or freshTicket(findTickets(true))
		end, 6)

		if spotted then
			notify("Getting a ticket", true, THEME.Accent)
			local given, reason = getAndGive()
			if not given then
				message = reason
			end
		end

		bellhop = nearestBellhop() or bellhop
		part = partOf(bellhop)
		if not part then
			message = "BellHop unloaded"
			return
		end
		local shotSpot = part.Position + flatLook(part) * 8 + Vector3.new(0, 1, 0)
		teleport(CFrame.lookAt(shotSpot, Vector3.new(part.Position.X, shotSpot.Y, part.Position.Z)))
		camLock = RunService.RenderStepped:Connect(function()
			local cam = workspace.CurrentCamera
			local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
			if cam and head and part.Parent then
				cam.CFrame = CFrame.lookAt(head.Position, part.Position)
			end
		end)

		notify("Taking the picture", true, THEME.Accent)
		local camera = findTool(CAMERA_WORDS)
		if not camera then
			message = "No camera tool found"
			return
		end
		local _, hum = getCharacter()
		if hum and camera.Parent ~= LocalPlayer.Character then
			hum:EquipTool(camera)
			task.wait(0.4)
		end
		for _ = 1, 2 do
			pcall(function()
				camera:Activate()
			end)
			task.wait(1.5)
		end
		message = message or "Picture taken, check your album"
	end)

	if camLock then
		camLock:Disconnect()
	end
	if not ok then
		message = "Safe picture failed: " .. tostring(err)
	end
	if home then
		teleport(home)
	end
	Busy = false
	notify(message or "Done")
end

-- Teleport away: the nearest open floor 80 to 150 studs from the BellHop. Far enough and he stops chasing.
local function teleportAway()
	local bellhop = nearestBellhop()
	if not bellhop then
		notify("No BellHop loaded")
		return
	end
	local part = partOf(bellhop)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { bellhop }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(ignore, plr.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	for _, distance in ipairs({ 150, 110, 80 }) do
		for step = 0, 11 do
			local angle = math.rad(step * 30)
			local probe = part.Position + Vector3.new(math.sin(angle), 0, math.cos(angle)) * distance + Vector3.new(0, 20, 0)
			local hit = workspace:Raycast(probe, Vector3.new(0, -60, 0), params)
			if hit and hit.Normal.Y > 0.6 then
				local headroom = workspace:Raycast(hit.Position + Vector3.new(0, 0.5, 0), Vector3.new(0, 6, 0), params)
				if not headroom then
					teleport(CFrame.new(hit.Position + Vector3.new(0, 3, 0)))
					notify(string.format("Teleported %d studs away from the BellHop", distance))
					return
				end
			end
		end
	end
	notify("No open floor far enough away")
end

-- Scan report: everything the main script needs to match the game's names exactly.
local function scanReport()
	local lines = {}
	local function add(text)
		table.insert(lines, text)
	end
	local origin = myPosition()
	add(string.format("BellHop scan, place %d, %s", game.PlaceId, os.date("%Y-%m-%d %H:%M")))

	add("== BellHop models")
	for obj in pairs(Tracked.Bellhops) do
		if obj.Parent then
			local part = partOf(obj)
			add(string.format("%s (%s) %dm", obj:GetFullName(), obj.ClassName, part and math.floor((part.Position - origin).Magnitude) or -1))
			for key, value in pairs(obj:GetAttributes()) do
				add("  attribute " .. key .. " = " .. tostring(value))
			end
			for _, d in ipairs(obj:GetDescendants()) do
				if d:IsA("ProximityPrompt") then
					add(string.format("  prompt %s action=%q object=%q enabled=%s", d.Name, d.ActionText, d.ObjectText, tostring(d.Enabled)))
				elseif d:IsA("Sound") then
					add(string.format("  sound %s %s", d.Name, d.IsPlaying and "playing" or ""))
				elseif d:IsA("ValueBase") or d:IsA("Script") or d:IsA("LocalScript") then
					add("  " .. d.ClassName .. " " .. d.Name)
				end
			end
		end
	end

	add("== Ticket candidates on the map")
	for _, ticket in ipairs(findTickets(true)) do
		add(string.format(
			"%s (%s) %dm prompt=%s",
			ticket.Object:GetFullName(),
			ticket.Object.ClassName,
			math.floor(ticket.Distance),
			ticket.Prompt and string.format("%q/%q", ticket.Prompt.ActionText, ticket.Prompt.ObjectText) or "none"
		))
	end

	add("== Prompts within 80 studs")
	for prompt in pairs(Tracked.Prompts) do
		if prompt.Parent and prompt:IsDescendantOf(workspace) then
			local part = partOf(prompt.Parent)
			local dist = part and (part.Position - origin).Magnitude or math.huge
			if dist <= 80 then
				add(string.format("%s action=%q object=%q enabled=%s %dm", prompt:GetFullName(), prompt.ActionText, prompt.ObjectText, tostring(prompt.Enabled), math.floor(dist)))
			end
		end
	end

	add("== Templates in ReplicatedStorage named ticket, bellhop or music")
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if hasWord(d.Name, "ticket") or hasWord(d.Name, "bellhop") or hasWord(d.Name, "music") then
			add(d:GetFullName() .. " (" .. d.ClassName .. ")")
		end
	end

	add("== Text on your screen")
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	local count = 0
	if gui then
		for _, d in ipairs(gui:GetDescendants()) do
			if (d:IsA("TextLabel") or d:IsA("TextButton")) and d.ContentText ~= "" and shown(d) and count < 40 then
				count += 1
				add(string.format("%s: %q", d:GetFullName(), d.ContentText))
			end
		end
	end

	add("== Your tools and ticket state")
	for _, holder in ipairs({ LocalPlayer.Character or false, LocalPlayer:FindFirstChildOfClass("Backpack") or false }) do
		if holder then
			for _, child in ipairs(holder:GetChildren()) do
				if child:IsA("Tool") then
					add("tool " .. child.Name .. " in " .. holder.Name)
				end
			end
		end
	end
	add("holding a ticket: " .. tostring(holdingTicket()))
	add("spotted text on screen: " .. tostring(spottedText()))
	for key, value in pairs(LocalPlayer:GetAttributes()) do
		add("player attribute " .. key .. " = " .. tostring(value))
	end

	local report = table.concat(lines, "\n")
	print(report)
	if setClipboard and pcall(setClipboard, report) then
		notify("Scan report copied, paste it to me")
	else
		notify("Scan report printed to the console")
	end
end

-- Window
local Window = create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 70, 0.5, 0),
	Size = UDim2.fromOffset(230, 0),
	AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = THEME.Window,
	Parent = Screen,
})
corner(Window, 12)
create("UIStroke", { Color = THEME.Stroke, Parent = Window })
create("UIPadding", {
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 10),
	Parent = Window,
})
create("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Window })

local order = 0
local function nextOrder()
	order += 1
	return order
end

local TitleBar = create("Frame", {
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1,
	Active = true,
	LayoutOrder = nextOrder(),
	Parent = Window,
})
create("TextLabel", {
	Size = UDim2.new(1, -30, 1, 0),
	BackgroundTransparency = 1,
	Text = "BellHop test",
	TextColor3 = THEME.Accent,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = TitleBar,
})
local CloseButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, 0, 0, 0),
	Size = UDim2.fromOffset(24, 24),
	BackgroundColor3 = THEME.Surface,
	Text = "X",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	Parent = TitleBar,
})
corner(CloseButton, 6)

local Status = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Text = "Scanning...",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.Gotham,
	TextSize = 11,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	LayoutOrder = nextOrder(),
	Parent = Window,
})

local function addToggle(text, key)
	local row = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = THEME.Surface,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = nextOrder(),
		Parent = Window,
	})
	corner(row, 8)
	create("TextLabel", {
		Position = UDim2.fromOffset(10, 0),
		Size = UDim2.new(1, -60, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	local switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.fromOffset(34, 18),
		BackgroundColor3 = THEME.Track,
		Parent = row,
	})
	corner(switch, 9)
	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = THEME.Text,
		Parent = switch,
	})
	corner(knob, 7)
	local function paint()
		local on = State[key]
		switch.BackgroundColor3 = on and THEME.Accent or THEME.Track
		knob.Position = on and UDim2.new(0, 18, 0.5, 0) or UDim2.new(0, 2, 0.5, 0)
	end
	row.MouseButton1Click:Connect(function()
		State[key] = not State[key]
		paint()
	end)
	paint()
end

local function addButtons(specs)
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder = nextOrder(),
		Parent = Window,
	})
	local count = #specs
	for index, spec in ipairs(specs) do
		local accent = spec[3] == true
		local button = create("TextButton", {
			Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0),
			Position = UDim2.new((index - 1) / count, 6 * (index - 1) / count, 0, 0),
			BackgroundColor3 = accent and THEME.Accent or THEME.Surface,
			Text = spec[1],
			TextColor3 = accent and THEME.AccentDark or THEME.Text,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			Parent = row,
		})
		corner(button, 8)
		button.MouseButton1Click:Connect(function()
			task.spawn(spec[2])
		end)
	end
end

addToggle("Ticket ESP", "TicketESP")
addToggle("BellHop alert", "Alert")
addToggle("Auto ticket", "AutoTicket")
addButtons({ { "Get ticket", ticketRun, true }, { "Teleport away", teleportAway } })
addButtons({ { "Safe BellHop picture", safePicture, true } })
addButtons({ { "Scan report", scanReport } })

-- Drag the window by its title
do
	local dragging, dragInput, startPos, startInput = false, nil, nil, nil
	TitleBar.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		dragInput = kind == Enum.UserInputType.Touch and input or nil
		startInput = input.Position
		startPos = Window.Position
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				conn:Disconnect()
			end
		end)
	end)
	track(UserInputService.InputChanged:Connect(function(input)
		if not dragging then
			return
		end
		local valid = (dragInput ~= nil and input == dragInput)
			or (dragInput == nil and input.UserInputType == Enum.UserInputType.MouseMovement)
		if valid then
			local delta = input.Position - startInput
			Window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end))
end

-- Main loop: spotted check, alert, auto ticket, ESP and status, about 3 times a second.
local wasSpotted = false
local function update()
	local bellhop, bellDist = nearestBellhop()
	local spotted = spottedText()
	local tickets = findTickets(spotted)
	if not spotted and bellhop then
		spotted = freshTicket(tickets)
	end

	Banner.Visible = State.Alert and spotted
	if spotted and not wasSpotted then
		if State.Alert then
			notify("BellHop spotted you, find a ticket", false, THEME.Danger)
		end
		if State.AutoTicket and not Busy then
			task.spawn(ticketRun)
		end
	end
	wasSpotted = spotted

	Status.Text = string.format(
		"BellHop: %s   Tickets: %d\nSpotted: %s%s",
		bellhop and (math.floor(bellDist) .. "m") or "not loaded",
		#tickets,
		spotted and "yes" or "no",
		Busy and "   working..." or ""
	)
	syncESP(bellhop, tickets)
end

task.spawn(function()
	while Running do
		local ok, err = pcall(update)
		if not ok then
			warn("[BellHop test] " .. tostring(err))
		end
		task.wait(0.3)
	end
end)

local function unload()
	if not Running then
		return
	end
	Running = false
	for _, conn in ipairs(Connections) do
		conn:Disconnect()
	end
	for _, entry in pairs(ESP) do
		entry.Highlight:Destroy()
		entry.Board:Destroy()
	end
	EspFolder:Destroy()
	Screen:Destroy()
	if GlobalEnv.BellhopTestUnload == unload then
		GlobalEnv.BellhopTestUnload = nil
	end
end

CloseButton.MouseButton1Click:Connect(unload)
GlobalEnv.BellhopTestUnload = unload
notify("BellHop test loaded")
