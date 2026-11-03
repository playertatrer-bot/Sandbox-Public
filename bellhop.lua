-- BellHop test for Unseen Liminality, version 2
-- Ticket ESP, BellHop alert, Auto ticket, Escape if stuck, Get ticket, Teleport away,
-- Safe BellHop picture, Scan report with an event log.
-- Standalone, so it can be tested before it goes into the main script.
--
-- What the game uses, from the first scan report:
--   BellHop: Workspace.GameObjects.NPCs.Bellhop, a Model with attribute AIType = "Bellhop".
--            Sounds: Walk, Run, Vocal1, Vocal2, Grab, HatTip, TicketTake. Animation TicketTake.
--   Ticket:  a Model named HotelTicket (MeshPart HotelTicket inside), picked up through the
--            game's prompt handler (ProximityPromptHandler.Interactions.HotelTicket).
--   Camera:  the tool named Camera.

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

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
	TicketLocked = Color3.fromRGB(150, 130, 70),
	Bellhop = Color3.fromRGB(255, 70, 70),
}

local CAMERA_WORDS = { "camera", "cam", "photo", "polaroid", "snap" }
local SPOT_WORDS = { "follow the music", "followthemusic" }
local CHARGE_RANGE = 100 -- studs. The BellHop running this close counts as charging at you.

local State = {
	TicketESP = true,
	Alert = true,
	AutoTicket = false,
	Escape = true,
}

local Running = true
local Busy = false -- a ticket run or picture run is moving you around
local Connections = {}
local Tracked = { Bellhops = {}, Tickets = {}, Prompts = {} }
local ESP = {}
local Log = {}
local LogStart = os.clock()
local LastTicketTake = 0 -- when a BellHop last played his TicketTake sound or animation
local LastGrab = 0 -- when a BellHop last played his Grab sound
local MyKeys = {
	string.lower(LocalPlayer.Name),
	string.lower(LocalPlayer.DisplayName),
	tostring(LocalPlayer.UserId),
}

local function track(conn)
	table.insert(Connections, conn)
	return conn
end

local function log(text)
	table.insert(Log, string.format("[%6.1f] %s", os.clock() - LogStart, text))
	if #Log > 150 then
		table.remove(Log, 1)
	end
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

local function isBellhop(obj)
	return obj:IsA("Model") and (obj:GetAttribute("AIType") == "Bellhop" or hasWord(obj.Name, "bellhop"))
end

local function isTicket(obj)
	return (obj:IsA("Model") or obj:IsA("BasePart") or obj:IsA("Tool")) and hasWord(obj.Name, "ticket")
end

-- Hooks a BellHop once: its attribute changes, sounds and animations go into the event log.
-- TicketTake proves a handover, Grab warns that he is about to get you.
local hookedBellhops = {}
local function hookBellhop(bellhop)
	if hookedBellhops[bellhop] then
		return
	end
	hookedBellhops[bellhop] = true
	track(bellhop.AttributeChanged:Connect(function(key)
		log(string.format("BellHop attribute %s = %s", key, tostring(bellhop:GetAttribute(key))))
	end))
	local function hookSound(sound)
		track(sound.Played:Connect(function()
			log("BellHop sound " .. sound.Name)
			if hasWord(sound.Name, "tickettake") then
				LastTicketTake = os.clock()
			elseif hasWord(sound.Name, "grab") then
				LastGrab = os.clock()
			end
		end))
	end
	for _, d in ipairs(bellhop:GetDescendants()) do
		if d:IsA("Sound") then
			hookSound(d)
		end
	end
	track(bellhop.DescendantAdded:Connect(function(d)
		if d:IsA("Sound") then
			hookSound(d)
		elseif d:IsA("Animator") then
			track(d.AnimationPlayed:Connect(function(trackPlayed)
				local name = trackPlayed.Animation and trackPlayed.Animation.Name or "?"
				log("BellHop animation " .. name)
				if hasWord(name, "tickettake") then
					LastTicketTake = os.clock()
				end
			end))
		end
	end))
	local animator = bellhop:FindFirstChildWhichIsA("Animator", true)
	if animator then
		track(animator.AnimationPlayed:Connect(function(trackPlayed)
			local name = trackPlayed.Animation and trackPlayed.Animation.Name or "?"
			log("BellHop animation " .. name)
			if hasWord(name, "tickettake") then
				LastTicketTake = os.clock()
			end
		end))
	end
end

-- Scanning. old marks things already there when the script started, so they are not fresh spawns.
local function consider(obj, old)
	local stamp = old and 0 or os.clock()
	if isBellhop(obj) and not Tracked.Bellhops[obj] then
		Tracked.Bellhops[obj] = true
		hookBellhop(obj)
	end
	if isTicket(obj) then
		if not old and not insidePlayer(obj) then
			log("ticket appeared: " .. obj:GetFullName())
		end
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
track(workspace.DescendantRemoving:Connect(function(obj)
	if Tracked.Tickets[obj] ~= nil and not insidePlayer(obj) then
		log("ticket removed: " .. obj:GetFullName())
	end
end))

-- The NPC folder gets checked every update too, since AIType can be set after a model loads.
local function refreshBellhops()
	local objects = workspace:FindFirstChild("GameObjects")
	local npcs = objects and objects:FindFirstChild("NPCs")
	if npcs then
		for _, child in ipairs(npcs:GetChildren()) do
			if isBellhop(child) and not Tracked.Bellhops[child] then
				Tracked.Bellhops[child] = true
				hookBellhop(child)
			end
		end
	end
end

-- Every BellHop loaded, nearest first, as { Model, Part, Distance }.
local function bellhops()
	local list = {}
	local origin = myPosition()
	for obj in pairs(Tracked.Bellhops) do
		if obj.Parent == nil then
			Tracked.Bellhops[obj] = nil
		elseif obj:IsDescendantOf(workspace) and not insidePlayer(obj) then
			local part = partOf(obj)
			if part then
				table.insert(list, { Model = obj, Part = part, Distance = (part.Position - origin).Magnitude })
			end
		end
	end
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	return list
end

-- The BellHop is after you when one of his attributes or values names you.
local function targetsMe(bellhop)
	local function mine(value)
		local text = string.lower(tostring(value))
		for _, key in ipairs(MyKeys) do
			if text == key then
				return true
			end
		end
		return false
	end
	for _, value in pairs(bellhop:GetAttributes()) do
		if mine(value) then
			return true
		end
	end
	for _, child in ipairs(bellhop:GetChildren()) do
		if child:IsA("ObjectValue") and (child.Value == LocalPlayer or child.Value == LocalPlayer.Character) then
			return true
		end
		if child:IsA("StringValue") and mine(child.Value) then
			return true
		end
	end
	return false
end

local function running(bellhop)
	for _, d in ipairs(bellhop:GetDescendants()) do
		if d:IsA("Sound") and d.Name == "Run" and d.IsPlaying then
			return true
		end
	end
	return false
end

local function promptText(prompt)
	return prompt.ObjectText .. " " .. prompt.ActionText .. " " .. prompt.Name
end

-- Every ticket on the map, nearest first, as { Object, Part, Prompt, Distance, Stamp, Locked }.
-- Locked means its prompt is off right now, which can mean it only works while you are the target.
local function findTickets()
	local list, seen = {}, {}
	local origin = myPosition()
	local function add(obj, prompt, stamp)
		if seen[obj] or not obj:IsDescendantOf(workspace) or insidePlayer(obj) then
			return
		end
		local part = partOf(obj)
		if not part then
			return
		end
		prompt = prompt or promptIn(obj)
		seen[obj] = true
		table.insert(list, {
			Object = obj,
			Part = part,
			Prompt = prompt,
			Distance = (part.Position - origin).Magnitude,
			Stamp = stamp or 0,
			Locked = prompt ~= nil and not prompt.Enabled,
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
		elseif prompt:IsDescendantOf(workspace) and hasWord(promptText(prompt), "ticket") then
			local holder = prompt.Parent
			if holder and holder:IsA("Attachment") then
				holder = holder.Parent
			end
			if holder then
				add(holder, prompt, stamp)
			end
		end
	end
	table.sort(list, function(a, b)
		if a.Locked ~= b.Locked then
			return not a.Locked
		end
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

-- Text on your screen, skipping the player list. Used for the spotted check and the event log.
local function screenTexts()
	local texts = {}
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not gui then
		return texts
	end
	for _, obj in ipairs(gui:GetDescendants()) do
		if (obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.TextTransparency < 1 and obj.ContentText ~= "" then
			if not hasWord(obj:GetFullName(), "playerlist") and shown(obj) then
				texts[obj.ContentText] = true
			end
		end
	end
	return texts
end

local function spottedText(texts)
	for text in pairs(texts) do
		local lowered = string.lower(text)
		for _, word in ipairs(SPOT_WORDS) do
			if string.find(lowered, word, 1, true) then
				return true
			end
		end
	end
	return false
end

-- A ticket in your hands: a ticket tool, something named ticket on your character, or a ticket
-- attribute or value on your character or player.
local function holdingTicket()
	local function truthy(value)
		return value ~= nil and value ~= false and value ~= 0 and value ~= ""
	end
	local char = LocalPlayer.Character
	if char then
		for _, d in ipairs(char:GetDescendants()) do
			if hasWord(d.Name, "ticket") then
				return true
			end
		end
		for key, value in pairs(char:GetAttributes()) do
			if hasWord(key, "ticket") and truthy(value) then
				return true
			end
		end
	end
	local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if hasWord(child.Name, "ticket") then
				return true
			end
		end
	end
	for key, value in pairs(LocalPlayer:GetAttributes()) do
		if hasWord(key, "ticket") and truthy(value) then
			return true
		end
	end
	local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	for _, d in ipairs(LocalPlayer:GetDescendants()) do
		if d:IsA("ValueBase") and hasWord(d.Name, "ticket") and not (gui and d:IsDescendantOf(gui)) then
			local ok, value = pcall(function()
				return d.Value
			end)
			if ok and truthy(value) then
				return true
			end
		end
	end
	return false
end

-- Event log hooks: your attributes, character and backpack changes, and every prompt you trigger.
track(LocalPlayer.AttributeChanged:Connect(function(key)
	log(string.format("player attribute %s = %s", key, tostring(LocalPlayer:GetAttribute(key))))
end))
local function hookCharacter(char)
	track(char.AttributeChanged:Connect(function(key)
		log(string.format("character attribute %s = %s", key, tostring(char:GetAttribute(key))))
	end))
	track(char.ChildAdded:Connect(function(child)
		log("character got " .. child.Name .. " (" .. child.ClassName .. ")")
	end))
	track(char.ChildRemoved:Connect(function(child)
		log("character lost " .. child.Name)
	end))
end
if LocalPlayer.Character then
	hookCharacter(LocalPlayer.Character)
end
track(LocalPlayer.CharacterAdded:Connect(hookCharacter))
local backpackNow = LocalPlayer:FindFirstChildOfClass("Backpack")
if backpackNow then
	track(backpackNow.ChildAdded:Connect(function(child)
		log("backpack got " .. child.Name)
	end))
end
track(ProximityPromptService.PromptTriggered:Connect(function(prompt)
	log(string.format("prompt triggered %s on %s", prompt.Name, prompt.Parent and prompt.Parent:GetFullName() or "?"))
end))

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
	log("message: " .. text)
	toastId += 1
	local id = toastId
	Toast.Text = text
	Toast.TextColor3 = color or THEME.Text
	Toast.BackgroundTransparency = 0.05
	Toast.TextTransparency = 0
	if not sticky then
		task.delay(3, function()
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
	Text = "BellHop is after you! Get a ticket",
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	Visible = false,
	Parent = Screen,
})
corner(Banner, 10)
create("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16), Parent = Banner })

-- ESP: tickets in gold (dim gold while locked), BellHops in red, through walls with distance.
local function espFor(target, color, label)
	local entry = ESP[target]
	if not entry then
		local part = partOf(target)
		if not part then
			return
		end
		local highlight = create("Highlight", {
			Adornee = target:IsA("Tool") and part or target,
			FillTransparency = 0.55,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Parent = EspFolder,
		})
		local board = create("BillboardGui", {
			Adornee = part,
			AlwaysOnTop = true,
			Size = UDim2.fromOffset(180, 24),
			StudsOffset = Vector3.new(0, 2.5, 0),
			Parent = EspFolder,
		})
		local text = create("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			TextStrokeTransparency = 0.3,
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			Parent = board,
		})
		entry = { Highlight = highlight, Board = board, Text = text, Part = part }
		ESP[target] = entry
	end
	entry.Highlight.FillColor = color
	entry.Highlight.OutlineColor = color
	entry.Text.TextColor3 = color
	entry.Text.Text = string.format("%s [%dm]", label, math.floor((entry.Part.Position - myPosition()).Magnitude))
	entry.Seen = true
end

local function syncESP(found, tickets)
	for _, entry in pairs(ESP) do
		entry.Seen = false
	end
	if State.TicketESP then
		for _, ticket in ipairs(tickets) do
			if ticket.Locked then
				espFor(ticket.Object, THEME.TicketLocked, "Ticket (locked)")
			else
				espFor(ticket.Object, THEME.Ticket, "Ticket")
			end
		end
		for _, bellhop in ipairs(found) do
			espFor(bellhop.Model, THEME.Bellhop, "BellHop")
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
		log("fired " .. prompt.Name .. " with fireproximityprompt")
		return true
	end
	local ok = pcall(function()
		prompt.HoldDuration = 0
		prompt:InputHoldBegin()
		task.wait(0.1)
		prompt:InputHoldEnd()
	end)
	log("fired " .. prompt.Name .. " with InputHoldBegin, " .. (ok and "ok" or "failed"))
	return ok
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

local function collect(ticket)
	local part = ticket.Part
	log(string.format("going to ticket %s, %dm, prompt %s%s", ticket.Object:GetFullName(), math.floor(ticket.Distance),
		ticket.Prompt and ticket.Prompt.Name or "none", ticket.Locked and " (locked)" or ""))
	teleport(CFrame.new(part.Position + Vector3.new(0, 2.5, 0)))
	task.wait(0.3)
	if ticket.Prompt then
		firePrompt(ticket.Prompt)
	end
	touch(part)
	local click = ticket.Object:FindFirstChildWhichIsA("ClickDetector", true)
	if click and typeof(fireclickdetector) == "function" then
		pcall(fireclickdetector, click)
	end
	local got = waitFor(function()
		return holdingTicket()
			or not ticket.Object:IsDescendantOf(workspace)
			or part.Transparency >= 1
			or (ticket.Prompt ~= nil and not ticket.Locked and not ticket.Prompt.Enabled)
	end, 2.5)
	log("pickup " .. (got and "confirmed" or "not confirmed") .. ", holding ticket: " .. tostring(holdingTicket()))
	return got
end

-- Stands 3 studs in front of the BellHop holding the ticket and tries every way to hand it over:
-- his prompts, using the ticket, touching him. His TicketTake sound or animation confirms it.
local function give()
	local found = bellhops()
	local target = nil
	for _, bellhop in ipairs(found) do
		if targetsMe(bellhop.Model) then
			target = bellhop
			break
		end
	end
	target = target or found[1]
	if not target then
		return false, "No BellHop loaded"
	end
	local _, hum = getCharacter()
	local ticketTool = findTool({ "ticket" })
	if ticketTool and hum and ticketTool.Parent ~= LocalPlayer.Character then
		hum:EquipTool(ticketTool)
		task.wait(0.2)
	end
	local part = target.Part
	local spot = part.Position + flatLook(part) * 3
	teleport(CFrame.lookAt(spot, Vector3.new(part.Position.X, spot.Y, part.Position.Z)))
	local started = os.clock()
	task.wait(0.2)
	for _, prompt in ipairs(target.Model:GetDescendants()) do
		if prompt:IsA("ProximityPrompt") and prompt.Enabled then
			firePrompt(prompt)
		end
	end
	if ticketTool then
		pcall(function()
			ticketTool:Activate()
		end)
	end
	touch(part)
	local given = waitFor(function()
		return LastTicketTake >= started or not holdingTicket()
	end, 3.5)
	log("handover " .. (given and "confirmed" or "not confirmed"))
	return given, given and "Ticket given, the BellHop let you go" or "He did not take the ticket"
end

-- Picks up the nearest ticket that works (up to 3 tries), then gives it.
local function getAndGive()
	local tickets = findTickets()
	if #tickets == 0 then
		return false, "No ticket loaded nearby, get closer to the hotel"
	end
	local got = false
	for index = 1, math.min(#tickets, 3) do
		if collect(tickets[index]) then
			got = true
			break
		end
	end
	if not got then
		return false, "Ticket pickup failed, tap Scan report and send it"
	end
	notify("Got a ticket, giving it to the BellHop", true, THEME.Accent)
	return give()
end

-- Teleport away: open floor 80 to 150 studs from the nearest BellHop, where he gives up the chase.
local function teleportAway()
	local found = bellhops()
	if #found == 0 then
		notify("No BellHop loaded")
		return false
	end
	local part = found[1].Part
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = {}
	for _, bellhop in ipairs(found) do
		table.insert(ignore, bellhop.Model)
	end
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
					return true
				end
			end
		end
	end
	notify("No open floor far enough away")
	return false
end

local function ticketRun(fromAuto)
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
		given = false
	end
	if given and home then
		teleport(home)
	end
	Busy = false
	notify(message or "Done")
	if not given and fromAuto and State.Escape then
		teleportAway()
	elseif not given and home then
		teleport(home)
	end
end

-- Safe BellHop picture: let him target you from 14 studs, get a ticket and give it so he lets you
-- go, take the picture from 8 studs with the camera locked on him, then go back.
local function safePicture()
	if Busy then
		return
	end
	local found = bellhops()
	if #found == 0 then
		notify("No BellHop loaded")
		return
	end
	Busy = true
	local _, _, root = getCharacter()
	local home = root and root.CFrame
	local message = nil
	local camLock = nil
	local bellhop = found[1].Model

	local ok, err = pcall(function()
		local part = partOf(bellhop)
		notify("Letting the BellHop target you", true, THEME.Accent)
		local spot = part.Position + flatLook(part) * 14 + Vector3.new(0, 1, 0)
		teleport(CFrame.lookAt(spot, Vector3.new(part.Position.X, spot.Y, part.Position.Z)))
		local targeted = waitFor(function()
			return targetsMe(bellhop) or spottedText(screenTexts())
		end, 6)
		log("targeted before picture: " .. tostring(targeted))

		if targeted then
			notify("Getting a ticket", true, THEME.Accent)
			local given, reason = getAndGive()
			if not given then
				message = reason
			end
		end

		part = partOf(bellhop)
		if not part or not bellhop:IsDescendantOf(workspace) then
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

-- Scan report: the game's real names plus the event log of everything that just happened.
local function scanReport()
	local lines = {}
	local function add(text)
		table.insert(lines, text)
	end
	local origin = myPosition()
	add(string.format("BellHop scan v2, place %d, %s", game.PlaceId, os.date("%Y-%m-%d %H:%M")))

	add("== BellHops")
	for _, bellhop in ipairs(bellhops()) do
		add(string.format("%s %dm, targets you: %s, running: %s", bellhop.Model:GetFullName(), math.floor(bellhop.Distance),
			tostring(targetsMe(bellhop.Model)), tostring(running(bellhop.Model))))
		for key, value in pairs(bellhop.Model:GetAttributes()) do
			add("  attribute " .. key .. " = " .. tostring(value))
		end
		for _, child in ipairs(bellhop.Model:GetChildren()) do
			if child:IsA("ValueBase") then
				local ok, value = pcall(function()
					return child.Value
				end)
				add("  value " .. child.Name .. " = " .. tostring(ok and value))
			end
		end
		for _, d in ipairs(bellhop.Model:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				add(string.format("  prompt %s action=%q object=%q enabled=%s", d.Name, d.ActionText, d.ObjectText, tostring(d.Enabled)))
			end
		end
	end

	add("== Every ticket in the world")
	for _, ticket in ipairs(findTickets()) do
		local obj = ticket.Object
		add(string.format("%s (%s) %dm transparency=%.2f tags=%s", obj:GetFullName(), obj.ClassName, math.floor(ticket.Distance),
			ticket.Part.Transparency, table.concat(CollectionService:GetTags(obj), ",")))
		for key, value in pairs(obj:GetAttributes()) do
			add("  attribute " .. key .. " = " .. tostring(value))
		end
		local prompt = ticket.Prompt
		if prompt then
			add(string.format("  prompt %s action=%q object=%q enabled=%s range=%d sight=%s hold=%.1f style=%s",
				prompt.Name, prompt.ActionText, prompt.ObjectText, tostring(prompt.Enabled), prompt.MaxActivationDistance,
				tostring(prompt.RequiresLineOfSight), prompt.HoldDuration, prompt.Style.Name))
			for key, value in pairs(prompt:GetAttributes()) do
				add("    prompt attribute " .. key .. " = " .. tostring(value))
			end
		else
			add("  no prompt")
		end
		local kinds = {}
		for _, d in ipairs(obj:GetDescendants()) do
			kinds[d.ClassName] = (kinds[d.ClassName] or 0) + 1
		end
		local summary = {}
		for kind, count in pairs(kinds) do
			table.insert(summary, kind .. " x" .. count)
		end
		add("  contains " .. table.concat(summary, ", "))
	end

	add("== Prompts within 80 studs")
	for prompt in pairs(Tracked.Prompts) do
		if prompt.Parent and prompt:IsDescendantOf(workspace) then
			local part = partOf(prompt.Parent)
			local dist = part and (part.Position - origin).Magnitude or math.huge
			if dist <= 80 then
				add(string.format("%s action=%q object=%q enabled=%s %dm", prompt:GetFullName(), prompt.ActionText,
					prompt.ObjectText, tostring(prompt.Enabled), math.floor(dist)))
			end
		end
	end

	add("== Text on your screen")
	for text in pairs(screenTexts()) do
		add(string.format("%q", text))
	end

	add("== You")
	add("holding a ticket: " .. tostring(holdingTicket()))
	for key, value in pairs(LocalPlayer:GetAttributes()) do
		add("player attribute " .. key .. " = " .. tostring(value))
	end
	local char = LocalPlayer.Character
	if char then
		for key, value in pairs(char:GetAttributes()) do
			add("character attribute " .. key .. " = " .. tostring(value))
		end
	end

	add("== Event log, oldest first")
	for _, line in ipairs(Log) do
		add(line)
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
create("UIListLayout", { Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder, Parent = Window })

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
	Text = "BellHop test v2",
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
		Size = UDim2.new(1, 0, 0, 28),
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
addToggle("Escape if stuck", "Escape")
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

-- Main loop, about 3 times a second: target check, alert, auto ticket, escape, ESP, status, text log.
local wasTargeted = false
local lastTexts = {}
local function update()
	refreshBellhops()
	local found = bellhops()
	local tickets = findTickets()
	local texts = screenTexts()

	for text in pairs(texts) do
		if not lastTexts[text] then
			log(string.format("screen text: %q", string.sub(text, 1, 80)))
		end
	end
	lastTexts = texts

	local targeted = spottedText(texts)
	local charging = false
	for _, bellhop in ipairs(found) do
		if targetsMe(bellhop.Model) then
			targeted = true
		end
		if bellhop.Distance <= CHARGE_RANGE and running(bellhop.Model) then
			charging = true
		end
	end
	local danger = targeted or charging

	Banner.Visible = State.Alert and danger
	if danger and not wasTargeted then
		log("danger started, targeted: " .. tostring(targeted) .. ", charging: " .. tostring(charging))
		if State.Alert then
			notify("BellHop is after you, get a ticket", false, THEME.Danger)
		end
		if State.AutoTicket and not Busy then
			task.spawn(ticketRun, true)
		end
	end
	wasTargeted = danger

	-- Grab warning while he is after you and you have no ticket: get out.
	if State.Escape and danger and not Busy and os.clock() - LastGrab < 1 and not holdingTicket() then
		LastGrab = 0
		log("grab warning, escaping")
		task.spawn(teleportAway)
	end

	local unlocked = 0
	for _, ticket in ipairs(tickets) do
		if not ticket.Locked then
			unlocked += 1
		end
	end
	local nearest = found[1]
	Status.Text = string.format(
		"BellHop: %s   Tickets: %d (%d open)\nAfter you: %s%s",
		nearest and string.format("%dm %s", math.floor(nearest.Distance), tostring(nearest.Model:GetAttribute("State") or "")) or "not loaded",
		#tickets,
		unlocked,
		targeted and "yes" or (charging and "charging" or "no"),
		Busy and "   working..." or ""
	)
	syncESP(found, tickets)
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
log("loaded, " .. #bellhops() .. " BellHop(s), " .. #findTickets() .. " ticket(s)")
notify("BellHop test v2 loaded")
