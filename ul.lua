-- After a server hop the script starts before the game finishes loading.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local EXTRA_ENTITY_NAMES = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local hasVirtualUser, VirtualUser = pcall(function()
	return game:GetService("VirtualUser")
end)

local LocalPlayer = Players.LocalPlayer
local GuiParent = (gethui and gethui()) or game:GetService("CoreGui")
local GlobalEnv = (getgenv and getgenv()) or _G
local setClipboard = setclipboard or toclipboard or set_clipboard or (Clipboard and Clipboard.set)
local WHITE = Color3.new(1, 1, 1)

local RENDER_NAME = "BackroomsEnvironment"
local SWAY_GUARD_NAME = "BackroomsSwayGuard"
local SWAY_FIX_NAME = "BackroomsSwayFix"
local HOLD_NAME = "BackroomsHold"
local RENDER_NAMES = { RENDER_NAME, SWAY_GUARD_NAME, SWAY_FIX_NAME, HOLD_NAME }

local DISCORD_INVITE = "https://discord.gg/cVfEXUwGDT"
local LINK_COLOR = "rgb(88,166,255)"
local SWAY_WORDS = { "sway", "bob", "tilt", "shake" }

local ENTITY_FOLDERS = {
	entities = true, entity = true, monsters = true, monster = true,
	enemies = true, enemy = true, npcs = true, npc = true,
	mobs = true, creatures = true, ai = true,
}

local EntityNames = {}
for _, name in ipairs(EXTRA_ENTITY_NAMES) do
	EntityNames[name] = true
end

-- "reload" tells the old copy that a new copy is taking over, so a running hunt carries on.
if type(GlobalEnv.BackroomsUnload) == "function" then
	pcall(GlobalEnv.BackroomsUnload, "reload")
end

for _, child in ipairs(GuiParent:GetChildren()) do
	if child.Name == "Backrooms" or child.Name == "BackroomsESP" then
		child:Destroy()
	end
end

for _, bindName in ipairs(RENDER_NAMES) do
	pcall(function()
		RunService:UnbindFromRenderStep(bindName)
	end)
end

local State = {
	Fullbright = false,
	NoFog = false,
	CustomFov = false,
	FovValue = 90,
	FirstPerson = false,
	NoSway = false,
	Speed = false,
	SpeedValue = 28,
	Fly = false,
	FlySpeed = 50,
	Noclip = false,
	InfJump = false,
	PlayerESP = false,
	EntityESP = false,
	ItemESP = false,
	EntityAlert = false,
	AlertRange = 60,
	TpDistance = 30,
	PullToCamera = false,
	SafeDistance = 15,
	PhotoWindow = 8,
	AutoShot = true,
	ClearView = true,
	PumpkinESP = false,
	InstantInteract = false,
	AntiAfk = false,
}

local RANGES = {
	FovValue = { 30, 120, 5 },
	SpeedValue = { 16, 150, 2 },
	FlySpeed = { 10, 300, 5 },
	AlertRange = { 20, 300, 10 },
	TpDistance = { 10, 100, 5 },
	SafeDistance = { 10, 20, 1 },
	PhotoWindow = { 3, 20, 1 },
}

local SAVED_KEYS = {
	"Fullbright", "NoFog", "CustomFov", "FovValue", "FirstPerson", "NoSway",
	"SpeedValue", "FlySpeed", "PlayerESP", "EntityESP", "ItemESP",
	"EntityAlert", "AlertRange", "TpDistance", "PullToCamera", "SafeDistance", "PhotoWindow", "AutoShot",
	"ClearView", "PumpkinESP", "InstantInteract", "AntiAfk",
}

local CONFIG_FILE = "Backrooms_config.json"
local FileAccess = typeof(writefile) == "function"
	and typeof(readfile) == "function"
	and typeof(isfile) == "function"

local function loadConfig()
	if not FileAccess then
		return {}
	end
	local ok, data = pcall(function()
		if isfile(CONFIG_FILE) then
			return HttpService:JSONDecode(readfile(CONFIG_FILE))
		end
		return nil
	end)
	if ok and type(data) == "table" then
		return data
	end
	return {}
end

local function saveConfig()
	if not FileAccess then
		return
	end
	local data = {}
	for _, key in ipairs(SAVED_KEYS) do
		data[key] = State[key]
	end
	pcall(function()
		writefile(CONFIG_FILE, HttpService:JSONEncode(data))
	end)
end

local Saved = loadConfig()
for key, range in pairs(RANGES) do
	if type(Saved[key]) == "number" then
		State[key] = math.clamp(math.floor(Saved[key]), range[1], range[2])
	end
end

local THEME = {
	Window = Color3.fromRGB(17, 17, 21),
	Surface = Color3.fromRGB(28, 28, 34),
	SurfaceLight = Color3.fromRGB(40, 40, 48),
	Stroke = Color3.fromRGB(56, 56, 66),
	Text = Color3.fromRGB(236, 236, 240),
	SubText = Color3.fromRGB(145, 145, 158),
	Accent = Color3.fromRGB(232, 196, 84),
	AccentDark = Color3.fromRGB(28, 24, 12),
	Track = Color3.fromRGB(52, 52, 60),
	Knob = Color3.fromRGB(245, 245, 248),
	Danger = Color3.fromRGB(200, 58, 58),
}

local ESP_COLORS = {
	Player = Color3.fromRGB(80, 170, 255),
	Entity = Color3.fromRGB(255, 70, 70),
	Item = Color3.fromRGB(255, 220, 80),
	Pumpkin = Color3.fromRGB(90, 230, 110),
}

local Connections = {}
local Running = true

local function track(conn)
	table.insert(Connections, conn)
	return conn
end

local function loop(interval, fn)
	task.spawn(function()
		while Running do
			local ok, err = pcall(fn)
			if not ok then
				warn("[Backrooms] " .. tostring(err))
			end
			task.wait(interval)
		end
	end)
end

local function getCharacter()
	local char = LocalPlayer.Character
	if not char then
		return nil, nil, nil
	end
	return char, char:FindFirstChildOfClass("Humanoid"), char:FindFirstChild("HumanoidRootPart")
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
	if props.Parent then
		obj.Parent = props.Parent
	end
	return obj
end

local function corner(obj, radius)
	return create("UICorner", {
		CornerRadius = UDim.new(0, radius or 8),
		Parent = obj,
	})
end

local function stroke(obj, color, transparency, thickness)
	return create("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color or THEME.Stroke,
		Transparency = transparency or 0,
		Thickness = thickness or 1,
		Parent = obj,
	})
end

local function pad(obj, left, right, top, bottom)
	return create("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right),
		PaddingTop = UDim.new(0, top),
		PaddingBottom = UDim.new(0, bottom),
		Parent = obj,
	})
end

local function tween(obj, goal, duration)
	local info = TweenInfo.new(duration or 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local anim = TweenService:Create(obj, info, goal)
	anim:Play()
	return anim
end

local ScreenGui = create("ScreenGui", {
	Name = "Backrooms",
	ResetOnSpawn = false,
	DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	Parent = GuiParent,
})

local ESPFolder = create("Folder", {
	Name = "BackroomsESP",
	Parent = GuiParent,
})

local Toast = create("TextLabel", {
	Name = "Toast",
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
	ZIndex = 10,
	Parent = ScreenGui,
})
corner(Toast, 8)
pad(Toast, 14, 14, 0, 0)
local ToastStroke = stroke(Toast, THEME.Stroke, 1)
local toastId = 0

-- sticky keeps the toast up until the next notify replaces it.
local function notify(text, sticky, color)
	toastId += 1
	local id = toastId
	Toast.Text = text
	Toast.TextColor3 = color or THEME.Text
	ToastStroke.Color = color or THEME.Stroke
	tween(Toast, { BackgroundTransparency = 0.05, TextTransparency = 0 })
	tween(ToastStroke, { Transparency = 0 })
	if sticky then
		return
	end
	task.delay(2.5, function()
		if id == toastId and Toast.Parent then
			tween(Toast, { BackgroundTransparency = 1, TextTransparency = 1 }, 0.3)
			tween(ToastStroke, { Transparency = 1 }, 0.3)
		end
	end)
end

local LightBackup = {}
local FogBackup = {}
local AtmosBackup = {}
local CameraBackup = {}
local FovBackup = nil
local PushedMinZoom = nil
local SwayScripts = {}

local function onFullbright(enabled)
	if enabled then
		LightBackup.Brightness = Lighting.Brightness
		LightBackup.ClockTime = Lighting.ClockTime
		LightBackup.GlobalShadows = Lighting.GlobalShadows
		LightBackup.Ambient = Lighting.Ambient
		LightBackup.OutdoorAmbient = Lighting.OutdoorAmbient
	elseif LightBackup.Brightness then
		Lighting.Brightness = LightBackup.Brightness
		Lighting.ClockTime = LightBackup.ClockTime
		Lighting.GlobalShadows = LightBackup.GlobalShadows
		Lighting.Ambient = LightBackup.Ambient
		Lighting.OutdoorAmbient = LightBackup.OutdoorAmbient
		table.clear(LightBackup)
	end
end

local function onNoFog(enabled)
	if enabled then
		FogBackup.FogStart = Lighting.FogStart
		FogBackup.FogEnd = Lighting.FogEnd
		return
	end
	if FogBackup.FogEnd then
		Lighting.FogStart = FogBackup.FogStart
		Lighting.FogEnd = FogBackup.FogEnd
		table.clear(FogBackup)
	end
	for atmos, values in pairs(AtmosBackup) do
		if atmos.Parent then
			atmos.Density = values.Density
			atmos.Haze = values.Haze
		end
	end
	table.clear(AtmosBackup)
end

local function onCustomFov(enabled)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	if enabled then
		FovBackup = cam.FieldOfView
	elseif FovBackup then
		cam.FieldOfView = FovBackup
		FovBackup = nil
	end
end

local function onFirstPerson(enabled)
	if enabled then
		local cam = workspace.CurrentCamera
		CameraBackup.Mode = LocalPlayer.CameraMode
		CameraBackup.Min = PushedMinZoom or LocalPlayer.CameraMinZoomDistance
		CameraBackup.Max = LocalPlayer.CameraMaxZoomDistance
		CameraBackup.Zoom = cam and (cam.CFrame.Position - cam.Focus.Position).Magnitude or 0
		PushedMinZoom = nil
		LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		LocalPlayer.CameraMinZoomDistance = 0.5
		LocalPlayer.CameraMaxZoomDistance = 0.5
		return
	end
	if not CameraBackup.Mode then
		return
	end
	local mode = CameraBackup.Mode
	local minZoom = CameraBackup.Min
	local maxZoom = CameraBackup.Max
	local zoom = math.max(minZoom, math.min(CameraBackup.Zoom, maxZoom))
	table.clear(CameraBackup)
	LocalPlayer.CameraMode = mode
	LocalPlayer.CameraMaxZoomDistance = maxZoom
	if mode ~= Enum.CameraMode.LockFirstPerson and zoom > minZoom + 1 then
		PushedMinZoom = minZoom
		LocalPlayer.CameraMinZoomDistance = zoom
		task.delay(0.25, function()
			if PushedMinZoom ~= nil and not State.FirstPerson then
				LocalPlayer.CameraMinZoomDistance = PushedMinZoom
				PushedMinZoom = nil
			end
		end)
	else
		LocalPlayer.CameraMinZoomDistance = minZoom
	end
end

local function isSwayScript(obj)
	if obj.ClassName ~= "LocalScript" then
		return false
	end
	local name = string.lower(obj.Name)
	for _, word in ipairs(SWAY_WORDS) do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

local function muteSwayScript(obj)
	if SwayScripts[obj] or not isSwayScript(obj) then
		return
	end
	local readable, enabled = pcall(function()
		return obj.Enabled
	end)
	if readable and enabled and pcall(function()
		obj.Enabled = false
	end) then
		SwayScripts[obj] = true
	end
end

local function scanSwayScripts()
	local roots = {}
	if LocalPlayer.Character then
		table.insert(roots, LocalPlayer.Character)
	end
	for _, className in ipairs({ "PlayerScripts", "PlayerGui", "Backpack" }) do
		local root = LocalPlayer:FindFirstChildOfClass(className)
		if root then
			table.insert(roots, root)
		end
	end
	for _, root in ipairs(roots) do
		for _, obj in ipairs(root:GetDescendants()) do
			muteSwayScript(obj)
		end
	end
end

local function onNoSway(enabled)
	if enabled then
		scanSwayScripts()
		return
	end
	for obj in pairs(SwayScripts) do
		if obj.Parent then
			pcall(function()
				obj.Enabled = true
			end)
		end
	end
	table.clear(SwayScripts)
end

local function guardCameraOffset()
	if not State.NoSway then
		return
	end
	local _, hum = getCharacter()
	if hum then
		local offset = hum.CameraOffset
		if offset.X ~= 0 or offset.Z ~= 0 then
			hum.CameraOffset = Vector3.new(0, offset.Y, 0)
		end
	end
end

local function stabilizeCamera()
	if not State.NoSway then
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local cf = cam.CFrame
	local look = cf.LookVector
	if math.abs(look.Y) > 0.98 then
		return
	end
	local position = cf.Position
	if cam.CameraType == Enum.CameraType.Custom then
		local focus = cam.Focus.Position
		local zoom = (focus - position):Dot(look)
		if zoom > 0 then
			local onLine = focus - look * zoom
			if (onLine - position).Magnitude < 4 then
				position = onLine
			end
		end
	end
	cam.CFrame = CFrame.lookAt(position, position + look)
end

local function applyEnvironment()
	if State.Fullbright then
		Lighting.Brightness = 2
		Lighting.ClockTime = 14
		Lighting.GlobalShadows = false
		Lighting.Ambient = WHITE
		Lighting.OutdoorAmbient = WHITE
	end
	if State.NoFog then
		Lighting.FogStart = 0
		Lighting.FogEnd = 1e6
		for _, obj in ipairs(Lighting:GetChildren()) do
			if obj:IsA("Atmosphere") then
				if not AtmosBackup[obj] then
					AtmosBackup[obj] = { Density = obj.Density, Haze = obj.Haze }
				end
				obj.Density = 0
				obj.Haze = 0
			end
		end
	end
	local cam = workspace.CurrentCamera
	if State.CustomFov and cam then
		cam.FieldOfView = State.FovValue
	end
	if State.FirstPerson then
		if LocalPlayer.CameraMode ~= Enum.CameraMode.LockFirstPerson then
			LocalPlayer.CameraMode = Enum.CameraMode.LockFirstPerson
		end
		if LocalPlayer.CameraMaxZoomDistance > 0.5 then
			LocalPlayer.CameraMinZoomDistance = 0.5
			LocalPlayer.CameraMaxZoomDistance = 0.5
		end
	end
end

local DefaultSpeed = 16
local NoclipParts = {}
local FlyRig = nil
local FlyUp = false
local FlyDown = false

local function flatUnit(vector)
	local flat = Vector3.new(vector.X, 0, vector.Z)
	if flat.Magnitude < 1e-3 then
		return nil
	end
	return flat.Unit
end

local function onSpeed(enabled)
	local _, hum = getCharacter()
	if not hum then
		return
	end
	if enabled then
		DefaultSpeed = hum.WalkSpeed
	else
		hum.WalkSpeed = DefaultSpeed
	end
end

local function onNoclip(enabled)
	if enabled then
		return
	end
	for part in pairs(NoclipParts) do
		if part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(NoclipParts)
end

local function stepNoclip()
	local char = LocalPlayer.Character
	if not char then
		return
	end
	for _, part in ipairs(char:GetDescendants()) do
		if part:IsA("BasePart") and part.CanCollide then
			part.CanCollide = false
			NoclipParts[part] = true
		end
	end
end

local function destroyFlyRig()
	if not FlyRig then
		return
	end
	FlyRig.Velocity:Destroy()
	FlyRig.Align:Destroy()
	FlyRig.Attachment:Destroy()
	FlyRig = nil
end

local function buildFlyRig(root)
	destroyFlyRig()

	local attachment = create("Attachment", {
		Name = "BackroomsFly",
		Parent = root,
	})

	local velocity = create("LinearVelocity", {
		Name = "BackroomsFly",
		Attachment0 = attachment,
		RelativeTo = Enum.ActuatorRelativeTo.World,
		VelocityConstraintMode = Enum.VelocityConstraintMode.Vector,
		MaxForce = math.huge,
		VectorVelocity = Vector3.zero,
		Parent = root,
	})

	local align = create("AlignOrientation", {
		Name = "BackroomsFly",
		Mode = Enum.OrientationAlignmentMode.OneAttachment,
		Attachment0 = attachment,
		RigidityEnabled = true,
		CFrame = root.CFrame.Rotation,
		Parent = root,
	})

	FlyRig = {
		Root = root,
		Attachment = attachment,
		Velocity = velocity,
		Align = align,
	}
end

local function stepFly()
	local _, hum, root = getCharacter()
	local cam = workspace.CurrentCamera
	if not hum or not root or not cam or hum.Health <= 0 then
		return
	end
	if not FlyRig or FlyRig.Root ~= root or not FlyRig.Velocity.Parent then
		buildFlyRig(root)
	end
	hum.PlatformStand = true

	local camCF = cam.CFrame
	local flat = flatUnit(camCF.LookVector)
	local move = hum.MoveDirection
	local direction = Vector3.zero

	if move.Magnitude > 0 then
		if flat then
			local yaw = CFrame.lookAt(Vector3.zero, flat)
			direction = camCF:VectorToWorldSpace(yaw:VectorToObjectSpace(move))
		else
			direction = move
		end
	end

	local typing = UserInputService:GetFocusedTextBox() ~= nil
	local vertical = 0
	if FlyUp or (not typing and UserInputService:IsKeyDown(Enum.KeyCode.Space)) then
		vertical += 1
	end
	if FlyDown or (not typing and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)) then
		vertical -= 1
	end
	direction += Vector3.new(0, vertical, 0)
	if direction.Magnitude > 1 then
		direction = direction.Unit
	end

	FlyRig.Velocity.VectorVelocity = direction * State.FlySpeed
	if flat then
		FlyRig.Align.CFrame = CFrame.lookAt(Vector3.zero, flat)
	end
end

local FlyPad = create("Frame", {
	Name = "FlyPad",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -18, 0.45, 0),
	Size = UDim2.fromOffset(62, 130),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = ScreenGui,
})

local function makeHoldButton(text, yOffset, setter)
	local button = create("TextButton", {
		Position = UDim2.fromOffset(0, yOffset),
		Size = UDim2.fromOffset(62, 60),
		BackgroundColor3 = THEME.Window,
		BackgroundTransparency = 0.1,
		AutoButtonColor = false,
		Text = text,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Parent = FlyPad,
	})
	corner(button, 12)
	local outline = stroke(button)

	local function paint(held)
		button.BackgroundColor3 = held and THEME.Accent or THEME.Window
		button.TextColor3 = held and THEME.AccentDark or THEME.Text
		outline.Color = held and THEME.Accent or THEME.Stroke
	end

	button.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
			return
		end
		setter(true)
		paint(true)
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				setter(false)
				paint(false)
				conn:Disconnect()
			end
		end)
	end)
end

makeHoldButton("UP", 0, function(held)
	FlyUp = held
end)

makeHoldButton("DOWN", 70, function(held)
	FlyDown = held
end)

local function onFly(enabled)
	FlyPad.Visible = enabled
	if enabled then
		return
	end
	destroyFlyRig()
	FlyUp = false
	FlyDown = false
	local _, hum, root = getCharacter()
	if hum then
		hum.PlatformStand = false
	end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local ESP = {}
local Entities = {}
-- Auto take picture state in one table to stay under the Luau 200 local limit.
local Bring = {
	Held = nil, -- entity being held, with its saved state
	Hover = nil, -- spot you float at during a picture run
	Running = false, -- a picture run is in progress
	Token = 0, -- bumps on cancel
	Cleared = {}, -- parts hidden on your screen for the shot, with their saved state
	RemoteLog = {}, -- remote calls the game made during the current shot, as { remote, time }
	Noise = { Remotes = {}, Sources = {}, Sounds = {}, Anims = {} }, -- signals that fire on their own, ignored as proof
	PhotoRemote = nil, -- the remote that proved a picture, learned on the first confirmed shot
	Unhook = nil, -- removes the remote watch
}

-- Halloween 2026 green pumpkins.
local Pumpkin = {
	Found = {}, -- every pumpkin-named Model or part seen in workspace
	Done = {}, -- pumpkins with a shot taken this session
	Rows = {}, -- list rows by pumpkin
	Targets = {}, -- latest scan, nearest first, refreshed every second
	Confirmed = false, -- the latest scan found pumpkins that read as green
}
local WatchedFolders = {}
local Prompts = {}
local Clickers = {}
local PromptBackup = {}

local function isPlayerCharacter(obj)
	return Players:GetPlayerFromCharacter(obj) ~= nil
end

local function getRoot(target)
	if target:IsA("BasePart") or target:IsA("Attachment") then
		return target
	end
	if target:IsA("Model") then
		return target.PrimaryPart
			or target:FindFirstChild("HumanoidRootPart")
			or target:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function rootPosition(root)
	if root:IsA("Attachment") then
		return root.WorldPosition
	end
	return root.Position
end

local function myPosition()
	local _, _, root = getCharacter()
	if root then
		return root.Position
	end
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or Vector3.zero
end

local function interactLabel(objectText, holder)
	if objectText ~= "" then
		return objectText
	end
	local base = holder
	if base:IsA("Attachment") and base.Parent then
		base = base.Parent
	end
	local parent = base.Parent
	if parent and parent:IsA("Model") and parent ~= workspace then
		return parent.Name
	end
	return base.Name
end

local function applyInstantPrompt(prompt)
	if prompt.HoldDuration > 0 then
		if PromptBackup[prompt] == nil then
			PromptBackup[prompt] = prompt.HoldDuration
		end
		prompt.HoldDuration = 0
	end
end

local function onInstantInteract(enabled)
	if enabled then
		for prompt in pairs(Prompts) do
			applyInstantPrompt(prompt)
		end
		return
	end
	for prompt, duration in pairs(PromptBackup) do
		if prompt.Parent then
			prompt.HoldDuration = duration
		end
	end
	table.clear(PromptBackup)
end

local function addEntity(obj, source)
	if Entities[obj] == nil then
		Entities[obj] = source
	end
end

local function watchFolder(folder)
	if WatchedFolders[folder] then
		return
	end
	WatchedFolders[folder] = true
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			addEntity(child, "named")
		end
	end
end

local function consider(obj)
	-- Pumpkins: "pumpkin" in the name, or in an attribute on a Model.
	if string.find(string.lower(obj.Name), "pumpkin", 1, true) then
		if obj:IsA("Model") or obj:IsA("BasePart") then
			Pumpkin.Found[obj] = true
		end
	elseif obj:IsA("Model") then
		for key, value in pairs(obj:GetAttributes()) do
			local attr = string.lower(key) .. " " .. (type(value) == "string" and string.lower(value) or "")
			if string.find(attr, "pumpkin", 1, true) then
				Pumpkin.Found[obj] = true
				break
			end
		end
	end
	local class = obj.ClassName
	if class == "Humanoid" then
		local model = obj.Parent
		if model and model:IsA("Model") and model ~= workspace then
			addEntity(model, "humanoid")
		end
	elseif class == "ProximityPrompt" then
		Prompts[obj] = true
		if State.InstantInteract then
			applyInstantPrompt(obj)
		end
	elseif class == "ClickDetector" then
		Clickers[obj] = true
	elseif class == "LocalScript" then
		if State.NoSway then
			muteSwayScript(obj)
		end
	elseif class == "Folder" then
		if ENTITY_FOLDERS[string.lower(obj.Name)] then
			watchFolder(obj)
		end
	elseif WatchedFolders[obj.Parent] or EntityNames[obj.Name] then
		if obj:IsA("Model") or obj:IsA("BasePart") then
			addEntity(obj, "named")
		end
	end
end

local function removeESP(target)
	local entry = ESP[target]
	if not entry then
		return
	end
	if entry.Highlight then
		entry.Highlight:Destroy()
	end
	entry.Billboard:Destroy()
	ESP[target] = nil
end

local function addESP(target, kind, name)
	local existing = ESP[target]
	if existing then
		if existing.Kind == kind and existing.Root:IsDescendantOf(workspace) then
			existing.Name = name
			return
		end
		removeESP(target)
	end

	local root = getRoot(target)
	if not root then
		return
	end

	local color = ESP_COLORS[kind]
	local highlight = nil
	if kind ~= "Item" and (target:IsA("Model") or target:IsA("BasePart")) then
		highlight = create("Highlight", {
			Adornee = target,
			FillColor = color,
			OutlineColor = color,
			FillTransparency = 0.65,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Parent = ESPFolder,
		})
	end

	local billboard = create("BillboardGui", {
		Adornee = root,
		AlwaysOnTop = true,
		Size = UDim2.fromOffset(200, 30),
		StudsOffset = Vector3.new(0, (kind == "Item" or kind == "Pumpkin") and 1.5 or 3.5, 0),
		MaxDistance = kind == "Item" and 300 or 2000,
		Parent = ESPFolder,
	})

	local label = create("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = color,
		TextStrokeTransparency = 0.3,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Parent = billboard,
	})

	ESP[target] = {
		Kind = kind,
		Name = name,
		Root = root,
		Highlight = highlight,
		Billboard = billboard,
		Label = label,
	}
end

local function collectWanted()
	local want = {}

	if State.PlayerESP then
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if plr ~= LocalPlayer and char and char:IsDescendantOf(workspace) then
				want[char] = { "Player", plr.DisplayName }
			end
		end
	end

	if State.EntityESP then
		for obj in pairs(Entities) do
			if obj:IsDescendantOf(workspace) and not isPlayerCharacter(obj) then
				want[obj] = { "Entity", obj.Name }
			end
		end
	end

	if State.ItemESP then
		for prompt in pairs(Prompts) do
			local holder = prompt.Parent
			if holder and holder ~= workspace and prompt.Enabled and not want[holder] then
				want[holder] = { "Item", interactLabel(prompt.ObjectText, holder) }
			end
		end
		for clicker in pairs(Clickers) do
			local holder = clicker.Parent
			if holder and holder ~= workspace and not want[holder] then
				want[holder] = { "Item", interactLabel("", holder) }
			end
		end
	end

	if State.PumpkinESP and Pumpkin.Targets then
		local label = Pumpkin.Confirmed and "Green Pumpkin" or "Pumpkin"
		for _, entry in ipairs(Pumpkin.Targets) do
			local obj = entry.Target
			if obj:IsDescendantOf(workspace) and not want[obj] then
				want[obj] = { "Pumpkin", label }
			end
		end
	end

	return want
end

local function syncESP()
	local want = collectWanted()
	for target in pairs(ESP) do
		if not want[target] then
			removeESP(target)
		end
	end
	for target, info in pairs(want) do
		addESP(target, info[1], info[2])
	end
end

local function maintain()
	for obj, source in pairs(Entities) do
		if not obj:IsDescendantOf(workspace)
			or (source == "humanoid" and not obj:FindFirstChildOfClass("Humanoid"))
		then
			Entities[obj] = nil
		end
	end
	for folder in pairs(WatchedFolders) do
		if not folder:IsDescendantOf(workspace) then
			WatchedFolders[folder] = nil
		end
	end
	for prompt in pairs(Prompts) do
		if not prompt:IsDescendantOf(workspace) then
			Prompts[prompt] = nil
			PromptBackup[prompt] = nil
		elseif State.InstantInteract then
			applyInstantPrompt(prompt)
		end
	end
	for clicker in pairs(Clickers) do
		if not clicker:IsDescendantOf(workspace) then
			Clickers[clicker] = nil
		end
	end
	syncESP()
end

local function updateLabels()
	local origin = myPosition()
	for _, entry in pairs(ESP) do
		if entry.Root.Parent then
			local dist = math.floor((rootPosition(entry.Root) - origin).Magnitude)
			entry.Label.Text = string.format("%s [%dm]", entry.Name, dist)
		end
	end
end

local AlertLabel = create("TextLabel", {
	Name = "EntityAlert",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 6),
	Size = UDim2.fromOffset(0, 28),
	AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = THEME.Window,
	BackgroundTransparency = 0.1,
	Text = "",
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	Visible = false,
	Parent = ScreenGui,
})
corner(AlertLabel, 14)
pad(AlertLabel, 14, 14, 0, 0)
local AlertStroke = stroke(AlertLabel)

local function updateAlert()
	if not State.EntityAlert then
		AlertLabel.Visible = false
		return
	end

	local origin = myPosition()
	local nearestName = nil
	local nearestDist = math.huge
	for obj in pairs(Entities) do
		if obj:IsDescendantOf(workspace) and not isPlayerCharacter(obj) and not (Bring.Held and Bring.Held.Mode == "pull" and Bring.Held.Entity == obj) then
			local root = getRoot(obj)
			if root then
				local dist = (rootPosition(root) - origin).Magnitude
				if dist < nearestDist then
					nearestName = obj.Name
					nearestDist = dist
				end
			end
		end
	end

	AlertLabel.Visible = true
	if not nearestName then
		AlertLabel.Text = "No entities found"
		AlertLabel.BackgroundColor3 = THEME.Window
		AlertStroke.Color = THEME.Stroke
		return
	end
	local danger = nearestDist <= State.AlertRange
	AlertLabel.Text = string.format("Nearest: %s (%dm)", nearestName, math.floor(nearestDist))
	AlertLabel.BackgroundColor3 = danger and THEME.Danger or THEME.Window
	AlertStroke.Color = danger and THEME.Danger or THEME.Stroke
end

for _, obj in ipairs(workspace:GetDescendants()) do
	consider(obj)
end
track(workspace.DescendantAdded:Connect(consider))

local DANGER_WORDS = { "kill", "death", "damage", "hurt", "lava", "acid", "void" }
local TP_ANGLES = { 0, 30, -30, 60, -60, 90, -90, 120, -120, 150, -150, 180 }
local TP_SCALES = { 1, 0.75, 0.5 }
local MIN_TP_DISTANCE = 8
local ENTITY_CLEARANCE = 15

local SelectedEntity = nil
local ReturnCFrame = nil
local TeleportBusy = false

local FloorRay = RaycastParams.new()
FloorRay.FilterType = Enum.RaycastFilterType.Exclude
FloorRay.IgnoreWater = true
pcall(function()
	FloorRay.RespectCanCollide = true
end)

local SpaceCheck = OverlapParams.new()
SpaceCheck.FilterType = Enum.RaycastFilterType.Exclude

local Probe = create("Part", {
	Name = "BackroomsProbe",
	Anchored = true,
	CanCollide = false,
	CanTouch = false,
	Transparency = 1,
	Size = Vector3.new(3, 5, 3),
})

local function belongsToEntity(part)
	local node = part
	while node and node ~= workspace do
		if Entities[node] then
			return true
		end
		node = node.Parent
	end
	return false
end

local function isDangerous(part)
	if belongsToEntity(part) then
		return true
	end
	local name = string.lower(part.Name)
	for _, word in ipairs(DANGER_WORDS) do
		if string.find(name, word, 1, true) then
			return true
		end
	end
	return false
end

local function findFloor(origin, depth)
	local hit = workspace:Raycast(origin, Vector3.new(0, -depth, 0), FloorRay)
	if hit and hit.Normal.Y > 0.6 and not isDangerous(hit.Instance) then
		return hit.Position
	end
	return nil
end

local function hasRoom(floor, height)
	Probe.Size = Vector3.new(3, height, 3)
	Probe.CFrame = CFrame.new(floor + Vector3.new(0, 0.4 + height / 2, 0))
	local parts = workspace:GetPartsInPart(Probe, SpaceCheck)
	for _, part in ipairs(parts) do
		if part ~= workspace.Terrain and (part.CanCollide or isDangerous(part)) then
			return false
		end
	end
	return true
end

local function awayFromEntities(spot, target)
	for ent in pairs(Entities) do
		if ent ~= target and ent:IsDescendantOf(workspace) and not isPlayerCharacter(ent) then
			local root = getRoot(ent)
			if root and (rootPosition(root) - spot).Magnitude < ENTITY_CLEARANCE then
				return false
			end
		end
	end
	return true
end

local function hasSight(eye, point)
	return workspace:Raycast(eye, point - eye, FloorRay) == nil
end

-- Returns the first spot with a clear line to the entity, or the first open spot if none has one.
local function findSafeSpot(target, targetRoot, distance, height)
	local center = targetRoot.Position
	local behind = flatUnit(-targetRoot.CFrame.LookVector) or Vector3.new(1, 0, 0)
	local baseFloor = findFloor(center + Vector3.new(0, 1, 0), 40)
	local probeY = baseFloor and baseFloor.Y + 3 or center.Y + 1

	local fallback = nil
	for _, scale in ipairs(TP_SCALES) do
		local radius = math.max(distance * scale, math.min(MIN_TP_DISTANCE, distance))
		for _, angle in ipairs(TP_ANGLES) do
			local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(behind)
			local probe = Vector3.new(center.X, probeY, center.Z) + direction * radius
			local floor = findFloor(probe, 40)
			if floor
				and (not baseFloor or math.abs(floor.Y - baseFloor.Y) <= 8)
				and hasRoom(floor, height)
				and awayFromEntities(floor, target)
			then
				if hasSight(floor + Vector3.new(0, height, 0), center) then
					return floor
				end
				fallback = fallback or floor
			end
		end
	end
	return fallback
end

local function rootHeight(hum, root)
	if hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2
end

-- Auto take picture holds the entity in one of two modes.
-- lock (default): the entity stays where the server has it and your camera stays on it.
-- pull: pins the entity in front of your camera. Server owned entities get anchored locally,
-- so the photo sees a position the server never had. That gap trips the PS kick.
-- Grouped in one table to stay under the Luau 200 local limit.
local HOLD = {
	Fill = 0.6, -- share of the view height a pulled entity fills
	MinDistance = 6,
	LeashSlack = 15, -- pull mode
	LockSlack = 6, -- lock mode
	Settle = 0.4, -- seconds for the server to register a teleport
	PumpkinNear = 6, -- landing distance from a pumpkin, close enough for a big clear shot
	Grace = 0.4, -- seconds you stay after a confirmed picture
	Confirm = 1.2, -- seconds to wait for proof of a picture before the next try
	Baseline = 0.3, -- seconds of listening before the first try, to learn background noise
	CameraWords = { "camera", "cam", "photo", "polaroid", "snap" },
}

local HoldRay = RaycastParams.new()
HoldRay.FilterType = Enum.RaycastFilterType.Exclude
HoldRay.IgnoreWater = true
pcall(function()
	HoldRay.RespectCanCollide = true
end)

-- Sight checks count every queryable part, collidable or not, the same as a default raycast.
Bring.SightRay = RaycastParams.new()
Bring.SightRay.FilterType = Enum.RaycastFilterType.Exclude
Bring.SightRay.IgnoreWater = true

-- Clear view hides blocking parts on your screen only and lets raycasts pass through them.
-- Nothing replicates. restoreCleared puts every part back the way it was.
local function restoreCleared()
	for part, saved in pairs(Bring.Cleared) do
		if part.Parent then
			pcall(function()
				-- CanQuery goes first. It must be true before CanCollide turns back on.
				part.CanQuery = saved[2]
				part.CanCollide = saved[1]
				part.LocalTransparencyModifier = saved[3]
				for decal, value in pairs(saved[4]) do
					if decal.Parent then
						decal.LocalTransparencyModifier = value
					end
				end
			end)
		end
	end
	table.clear(Bring.Cleared)
end

-- True when nothing sits between origin and the entity. During a run with Clear view on,
-- each blocker gets cleared and the ray goes again. Terrain stays.
local function hasClearView(entity, origin, center)
	local ignore = { entity }
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(ignore, plr.Character)
		end
	end
	Bring.SightRay.FilterDescendantsInstances = ignore
	local clearing = State.ClearView and Bring.Running
	for _ = 1, 24 do
		local hit = workspace:Raycast(origin, center - origin, Bring.SightRay)
		if not hit then
			return true
		end
		local part = hit.Instance
		if not clearing or part:IsA("Terrain") or Bring.Cleared[part] then
			return false
		end
		-- Never hide the floor you stand on. On the ground, losing its collision drops you through it.
		if not Bring.Hover and part.CanCollide then
			local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
			local below = root and workspace:Raycast(root.Position, Vector3.new(0, -10, 0), Bring.SightRay)
			if below and below.Instance == part then
				return false
			end
		end
		local cleared = pcall(function()
			local decals = {}
			for _, child in ipairs(part:GetChildren()) do
				if child:IsA("Decal") then
					decals[child] = child.LocalTransparencyModifier
					child.LocalTransparencyModifier = 1
				end
			end
			Bring.Cleared[part] = { part.CanCollide, part.CanQuery, part.LocalTransparencyModifier, decals }
			part.CanCollide = false
			part.CanQuery = false
			part.LocalTransparencyModifier = 1
		end)
		if not cleared then
			return false
		end
	end
	return false
end

local function yawOf(vector)
	return math.atan2(-vector.X, -vector.Z)
end

local function boundsOf(target)
	if target:IsA("Model") then
		return target:GetBoundingBox()
	end
	return target.CFrame, target.Size
end


local function aimCamera(target)
	local cam = workspace.CurrentCamera
	if not cam or not target:IsDescendantOf(workspace) then
		return
	end
	local box = boundsOf(target)
	cam.CFrame = CFrame.lookAt(cam.CFrame.Position, box.Position)
end

local function releaseHeld()
	local held = Bring.Held
	if not held then
		return nil
	end
	Bring.Held = nil
	local entity = held.Entity
	if held.Origin and not held.Owned and entity:IsDescendantOf(workspace) then
		pcall(function()
			entity:PivotTo(held.Origin)
		end)
	end
	for part, saved in pairs(held.Parts) do
		if part.Parent then
			part.CanCollide = saved[1]
			part.CanTouch = saved[2]
		end
	end
	if held.Anchor and held.Anchor.Parent then
		held.Anchor.Anchored = held.WasAnchored
	end
	return entity
end

-- Lock mode: aim at the real entity, release if it walks out of range, flag blocked views.
local function lockStep(held)
	local entity = held.Entity
	local center = boundsOf(entity).Position
	local _, _, myRoot = getCharacter()
	if myRoot and (myRoot.Position - center).Magnitude > held.Leash then
		releaseHeld()
		notify(entity.Name .. " moved away, try again")
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	-- During a run the camera sits at your head, the spot the server sees you at.
	local hover = Bring.Hover
	local origin = cam.CFrame.Position
	if hover and hover.Eye then
		origin = hover.Eye
	elseif Bring.Running then
		local head = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Head")
		if head then
			origin = head.Position
		end
	end
	local up = Vector3.yAxis
	if hover and math.abs((center - origin).Unit.Y) > 0.97 then
		up = hover.Direction
	end
	cam.CFrame = CFrame.lookAt(origin, center, up)
	local clear = hasClearView(entity, origin, center)
	if clear ~= held.Clear then
		held.Clear = clear
		if clear then
			notify("Ready!", false, THEME.Accent)
		else
			notify("View blocked", true, THEME.Danger)
		end
	end
end

local function pinHeld()
	local held = Bring.Held
	if not held then
		return
	end
	local entity = held.Entity
	if not held.Root:IsDescendantOf(workspace) then
		releaseHeld()
		notify(entity.Name .. " unloaded")
		return
	end
	if held.Mode == "lock" then
		lockStep(held)
		return
	end
	-- The server still sees the entity at RealPosition. Drop the hold before a shot from too far out.
	local _, _, myRoot = getCharacter()
	if myRoot and (myRoot.Position - held.RealPosition).Magnitude > held.Leash then
		releaseHeld()
		notify("You moved away, hold released")
		return
	end
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end

	local camCF = cam.CFrame
	local look = camCF.LookVector
	local minDistance = math.max(held.Radius + 2, HOLD.MinDistance)
	local fit = held.Span / (2 * math.tan(math.rad(cam.FieldOfView) / 2) * HOLD.Fill)
	local distance = math.max(fit, minDistance)

	HoldRay.FilterDescendantsInstances = { entity, LocalPlayer.Character }
	local hit = workspace:Raycast(camCF.Position, look * distance, HoldRay)
	if hit then
		distance = math.max(hit.Distance - held.Radius, minDistance)
	end

	local center = camCF.Position + look * distance
	local facing = flatUnit(camCF.Position - center) or flatUnit(-camCF.UpVector) or Vector3.new(0, 0, 1)
	local rotation = CFrame.Angles(0, yawOf(facing) - held.BaseYaw, 0) * held.BaseRotation
	local rootCF = CFrame.new(center - rotation:VectorToWorldSpace(held.CenterInRoot)) * rotation
	entity:PivotTo(rootCF * held.PivotInRoot)
	held.Anchor.AssemblyLinearVelocity = Vector3.zero
	held.Anchor.AssemblyAngularVelocity = Vector3.zero
end

local function safePin()
	if not Bring.Held then
		return
	end
	local ok, err = pcall(pinHeld)
	if not ok then
		pcall(releaseHeld)
		warn("[Backrooms] " .. tostring(err))
		notify("Hold dropped")
	end
end

local function grabEntity(entity, mode)
	local root = getRoot(entity)
	if not root or not root:IsA("BasePart") then
		notify(entity.Name .. " has no body to hold")
		return false
	end

	if mode == "lock" then
		local _, _, myRoot = getCharacter()
		local reach = myRoot and (myRoot.Position - root.Position).Magnitude or 0
		Bring.Held = {
			Entity = entity,
			Root = root,
			Mode = "lock",
			Parts = {},
			Leash = math.max(reach, 10) + HOLD.LockSlack,
			Clear = nil,
		}
		pinHeld()
		return true
	end

	local anchor = root.AssemblyRootPart or root
	-- isnetworkowner says whether your client simulates the entity. Unknown counts as not owned.
	local owned = false
	if typeof(isnetworkowner) == "function" then
		local checked, result = pcall(isnetworkowner, anchor)
		owned = checked and result == true
	end
	local rootCF = root.CFrame
	local pivot = entity:GetPivot()
	local box, size = boundsOf(entity)

	local parts = {}
	local list = entity:GetDescendants()
	if entity:IsA("BasePart") then
		table.insert(list, entity)
	end
	for _, part in ipairs(list) do
		if part:IsA("BasePart") then
			parts[part] = { part.CanCollide, part.CanTouch }
			part.CanCollide = false
			part.CanTouch = false
		end
	end

	local wasAnchored = anchor.Anchored
	if not owned then
		anchor.Anchored = true
	end

	local _, _, myRoot = getCharacter()
	local start = root.Position
	local reach = myRoot and (myRoot.Position - start).Magnitude or 0

	Bring.Held = {
		Entity = entity,
		Root = root,
		Mode = "pull",
		RealPosition = start,
		Leash = reach + HOLD.LeashSlack,
		Anchor = anchor,
		WasAnchored = wasAnchored,
		Owned = owned,
		Parts = parts,
		Origin = pivot,
		PivotInRoot = rootCF:ToObjectSpace(pivot),
		CenterInRoot = rootCF:PointToObjectSpace(box.Position),
		BaseRotation = rootCF.Rotation,
		BaseYaw = yawOf(flatUnit(rootCF.LookVector) or Vector3.new(0, 0, -1)),
		Span = math.max(size.X, size.Y, size.Z),
		Radius = size.Magnitude / 2,
	}
	pinHeld()
	return true
end

-- Streams the entity in and returns its root, or nil and a reason.
local function resolveTarget(target)
	if not target or not target:IsDescendantOf(workspace) then
		return nil, "Pick an entity from the list"
	end
	local targetRoot = getRoot(target)
	if workspace.StreamingEnabled and targetRoot then
		pcall(function()
			LocalPlayer:RequestStreamAroundAsync(rootPosition(targetRoot), 3)
		end)
		if not target:IsDescendantOf(workspace) then
			return nil, "The entity left before the teleport"
		end
		targetRoot = getRoot(target)
	end
	if not targetRoot or not targetRoot:IsA("BasePart") then
		return nil, target.Name .. " has no body to aim at"
	end
	return targetRoot
end

-- extra is the target, so the floor search never lands on top of it.
local function prepareSearch(extra)
	local players = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			table.insert(players, plr.Character)
		end
	end
	local ignore = table.clone(players)
	for ent in pairs(Entities) do
		table.insert(ignore, ent)
	end
	table.insert(ignore, Probe)
	if extra then
		table.insert(ignore, extra)
	end
	local spaceIgnore = table.clone(players)
	table.insert(spaceIgnore, Probe)
	FloorRay.FilterDescendantsInstances = ignore
	SpaceCheck.FilterDescendantsInstances = spaceIgnore
end

-- Moves you to a safe spot near the entity. keepReturn leaves an existing Return spot in place.
local function landNear(target, distance, keepReturn)
	local targetRoot, reason = resolveTarget(target)
	if not targetRoot then
		return false, reason
	end

	local char, hum, root = getCharacter()
	if not char or not hum or not root or hum.Health <= 0 then
		return false, "Your character is not ready"
	end

	prepareSearch(target)

	local height = math.clamp(char:GetExtentsSize().Y - 0.5, 3, 7)
	Probe.Parent = workspace.CurrentCamera or workspace
	local searched, floor = pcall(findSafeSpot, target, targetRoot, distance, height)
	Probe.Parent = nil
	if not searched then
		error(floor, 0)
	end
	if not floor then
		return false, "No safe spot near " .. target.Name
	end

	local standPos = floor + Vector3.new(0, rootHeight(hum, root) + 0.25, 0)
	local focus = Vector3.new(targetRoot.Position.X, standPos.Y, targetRoot.Position.Z)
	if not keepReturn or not ReturnCFrame then
		ReturnCFrame = root.CFrame
	end
	root.CFrame = CFrame.lookAt(standPos, focus)
	root.AssemblyLinearVelocity = Vector3.zero
	return true, string.format("Landed %dm from %s", math.floor((focus - standPos).Magnitude), target.Name)
end

-- Hover: you float Safe distance studs from the entity, eyes a little above its head, and follow
-- it for the whole run. Walls and ceilings do not matter: noclip is on, and Clear view hides
-- whatever sits between you and it. This keeps you out of reach of entities that kill up close,
-- like the BellHop in its narrow hallway.
local function hoverPose(hover)
	local box, size = boundsOf(hover.Target)
	local center = box.Position
	local rise = math.clamp(size.Y / 2 + 2, 3, 8)
	local reach = State.SafeDistance
	local flat = math.sqrt(math.max(reach * reach - rise * rise, 4))
	local eye = center + hover.Direction * flat + Vector3.new(0, rise, 0)
	local rootPos = eye - Vector3.new(0, 1.5, 0)
	return CFrame.lookAt(rootPos, Vector3.new(center.X, rootPos.Y, center.Z)), eye, center
end

local function stepHover()
	local hover = Bring.Hover
	if not hover or not hover.Target:IsDescendantOf(workspace) then
		return
	end
	local char, hum, root = getCharacter()
	if not hum or not root or hum.Health <= 0 then
		return
	end
	local ok, cf, eye = pcall(hoverPose, hover)
	if not ok then
		return
	end
	hover.Eye = eye
	hum.PlatformStand = true
	root.CFrame = cf
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	-- No-touch always. With Clear view on, your own body is hidden on your screen so it stays out of the shot.
	for _, obj in ipairs(char:GetDescendants()) do
		local isPart = obj:IsA("BasePart")
		if isPart and obj.CanTouch then
			obj.CanTouch = false
			hover.Touch[obj] = true
		end
		if State.ClearView and (isPart or obj:IsA("Decal")) then
			if hover.Hidden[obj] == nil then
				hover.Hidden[obj] = obj.LocalTransparencyModifier
			end
			obj.LocalTransparencyModifier = 1
		end
	end
end

local function stopHover()
	local hover = Bring.Hover
	if not hover then
		return
	end
	Bring.Hover = nil
	for part in pairs(hover.Touch) do
		if part.Parent then
			part.CanTouch = true
		end
	end
	for obj, value in pairs(hover.Hidden) do
		if obj.Parent then
			obj.LocalTransparencyModifier = value
		end
	end
	if not State.Noclip then
		onNoclip(false)
	end
	local _, hum, root = getCharacter()
	if hum and not State.Fly then
		hum.PlatformStand = hover.Stand
	end
	if root then
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Starts the hover at a safe distance from the entity. Returns true, or false with a reason.
local function floatAbove(target)
	local targetRoot, reason = resolveTarget(target)
	if not targetRoot then
		return false, reason
	end
	local char, hum, root = getCharacter()
	if not char or not hum or not root or hum.Health <= 0 then
		return false, "Your character is not ready"
	end

	prepareSearch()
	local base = flatUnit(-targetRoot.CFrame.LookVector) or Vector3.new(1, 0, 0)
	local hover = {
		Target = target,
		Direction = base,
		Stand = hum.PlatformStand,
		Touch = {},
		Hidden = {},
		Eye = nil,
	}
	-- Prefer a side with a clear line from your eyes to the entity. If every side is walled in,
	-- the spot behind it is used and Clear view handles the walls.
	for _, angle in ipairs(TP_ANGLES) do
		hover.Direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(base)
		local _, eye, center = hoverPose(hover)
		if hasSight(eye, center) then
			break
		end
		hover.Direction = base
	end

	Bring.Hover = hover
	stepNoclip()
	stepHover()
	return true
end

local function onTeleportPressed()
	if TeleportBusy or Bring.Running then
		return
	end
	local target = SelectedEntity
	if not target then
		notify("Pick an entity from the list")
		return
	end
	TeleportBusy = true
	local ok, err = pcall(function()
		releaseHeld()
		local landed, message = landNear(target, State.TpDistance, false)
		if landed then
			task.spawn(function()
				RunService.RenderStepped:Wait()
				pcall(aimCamera, target)
			end)
		end
		notify(message)
	end)
	TeleportBusy = false
	if not ok then
		warn("[Backrooms] " .. tostring(err))
		notify("Teleport failed")
	end
end

local function onReturnPressed()
	if Bring.Running then
		Bring.Token += 1
		return
	end
	if not ReturnCFrame then
		notify("No saved spot yet")
		return
	end
	local _, hum, root = getCharacter()
	if not hum or not root or hum.Health <= 0 then
		notify("Your character is not ready")
		return
	end
	pcall(releaseHeld)
	root.CFrame = ReturnCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	ReturnCFrame = nil
	notify("Back at your saved spot")
end

local WINDOW_WIDTH, WINDOW_HEIGHT
do
	local startCamera = workspace.CurrentCamera
	local viewport = startCamera and startCamera.ViewportSize or Vector2.new(1280, 720)
	WINDOW_WIDTH = math.min(340, viewport.X - 90)
	WINDOW_HEIGHT = math.clamp(viewport.Y - 80, 250, 360)
end
local SIDEBAR_WIDTH = 96
local TITLE_HEIGHT = 38
local FOOTER_HEIGHT = 24
local BODY_TOP = TITLE_HEIGHT + 1
local BODY_HEIGHT = -(BODY_TOP + FOOTER_HEIGHT + 1)

local Window = create("Frame", {
	Name = "Window",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 66, 0.5, 0),
	Size = UDim2.fromOffset(WINDOW_WIDTH, WINDOW_HEIGHT),
	BackgroundColor3 = THEME.Window,
	Parent = ScreenGui,
})
corner(Window, 12)
stroke(Window)

local TitleBar = create("Frame", {
	Name = "TitleBar",
	Size = UDim2.new(1, 0, 0, TITLE_HEIGHT),
	BackgroundTransparency = 1,
	Active = true,
	Parent = Window,
})

corner(create("Frame", {
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(8, 8),
	BackgroundColor3 = THEME.Accent,
	Parent = TitleBar,
}), 4)

create("TextLabel", {
	Position = UDim2.fromOffset(30, 0),
	Size = UDim2.new(1, -74, 1, 0),
	BackgroundTransparency = 1,
	RichText = true,
	Text = 'Backrooms  <font color="rgb(145,145,158)" size="11">Unseen Liminality</font>',
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamBold,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTruncate = Enum.TextTruncate.AtEnd,
	Parent = TitleBar,
})

local HideButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -8, 0.5, 0),
	Size = UDim2.fromOffset(28, 28),
	BackgroundColor3 = THEME.Surface,
	AutoButtonColor = false,
	Modal = true,
	Text = "-",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	Parent = TitleBar,
})
corner(HideButton, 8)

create("Frame", {
	Position = UDim2.fromOffset(0, TITLE_HEIGHT),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = THEME.Stroke,
	Parent = Window,
})

create("Frame", {
	Position = UDim2.fromOffset(SIDEBAR_WIDTH, BODY_TOP),
	Size = UDim2.new(0, 1, 1, BODY_HEIGHT),
	BackgroundColor3 = THEME.Stroke,
	Parent = Window,
})

create("Frame", {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 0, 1, -FOOTER_HEIGHT),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = THEME.Stroke,
	Parent = Window,
})

-- Footer locals live in a block so they do not count against the 200 local limit.
do
	local LINK_TEXT = 'More: <font color="' .. LINK_COLOR .. '"><u>' .. DISCORD_INVITE .. "</u></font>"
	local COPIED_TEXT = '<font color="' .. LINK_COLOR .. '">copied!</font>'

	local Footer = create("TextButton", {
		Name = "Footer",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, FOOTER_HEIGHT),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		RichText = true,
		Text = LINK_TEXT,
		TextColor3 = THEME.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 11,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = Window,
	})

	local footerId = 0
	Footer.MouseButton1Click:Connect(function()
		local copied = false
		if setClipboard then
			copied = pcall(setClipboard, DISCORD_INVITE)
		end
		footerId += 1
		local id = footerId
		Footer.Text = copied and COPIED_TEXT or "copy failed"
		task.delay(2, function()
			if id == footerId and Footer.Parent then
				Footer.Text = LINK_TEXT
			end
		end)
	end)
end

-- Scrolls when the tabs outgrow a short screen.
local Sidebar = create("ScrollingFrame", {
	Name = "Sidebar",
	Position = UDim2.fromOffset(0, BODY_TOP),
	Size = UDim2.new(0, SIDEBAR_WIDTH, 1, BODY_HEIGHT),
	BackgroundTransparency = 1,
	ScrollBarThickness = 0,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = Window,
})
pad(Sidebar, 8, 8, 8, 8)
create("UIListLayout", {
	Padding = UDim.new(0, 4),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = Sidebar,
})

local PageHolder = create("Frame", {
	Name = "Pages",
	Position = UDim2.fromOffset(SIDEBAR_WIDTH + 1, BODY_TOP),
	Size = UDim2.new(1, -(SIDEBAR_WIDTH + 1), 1, BODY_HEIGHT),
	BackgroundTransparency = 1,
	ClipsDescendants = true,
	Parent = Window,
})

local Tabs = {}
local TabCount = 0
local ActiveTab = nil

local function selectTab(name)
	ActiveTab = name
	for tabName, tab in pairs(Tabs) do
		local active = tabName == name
		tab.Page.Visible = active
		tab.Indicator.Visible = active
		tween(tab.Button, { BackgroundTransparency = active and 0 or 1 })
		tween(tab.Label, { TextColor3 = active and THEME.Text or THEME.SubText })
	end
	local tab = Tabs[name]
	if tab and tab.OnOpen then
		task.spawn(tab.OnOpen)
	end
end

local function makeTab(name, scrolling)
	TabCount += 1
	local button = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 32),
		BackgroundColor3 = THEME.Surface,
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = TabCount,
		Parent = Sidebar,
	})
	corner(button, 8)

	local indicator = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.fromOffset(3, 14),
		BackgroundColor3 = THEME.Accent,
		Visible = false,
		Parent = button,
	})
	corner(indicator, 2)

	local label = create("TextLabel", {
		Position = UDim2.fromOffset(12, 2),
		Size = UDim2.new(1, -16, 1, -4),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = THEME.SubText,
		Font = Enum.Font.GothamMedium,
		TextScaled = true,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
	})
	-- Long tab names wrap and shrink to fit the sidebar.
	create("UITextSizeConstraint", {
		MaxTextSize = 12,
		MinTextSize = 8,
		Parent = label,
	})

	local page
	if scrolling then
		page = create("ScrollingFrame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = THEME.Stroke,
			ScrollingDirection = Enum.ScrollingDirection.Y,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(),
			Visible = false,
			Parent = PageHolder,
		})
	else
		page = create("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Visible = false,
			Parent = PageHolder,
		})
	end
	pad(page, 10, 10, 10, 10)
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = page,
	})

	local tab = {
		Button = button,
		Label = label,
		Indicator = indicator,
		Page = page,
		Scroller = scrolling and page or nil,
		Order = 0,
		OnOpen = nil,
	}
	Tabs[name] = tab
	button.MouseButton1Click:Connect(function()
		selectTab(name)
	end)
	return tab
end

local Handlers = {}
local Refreshers = {}

local function setToggle(key, value)
	if State[key] == value then
		return
	end
	State[key] = value
	local handler = Handlers[key]
	if handler then
		local ok, err = pcall(handler, value)
		if not ok then
			warn("[Backrooms] " .. tostring(err))
		end
	end
	local refresh = Refreshers[key]
	if refresh then
		refresh(false)
	end
	saveConfig()
end

local function addSection(tab, text)
	tab.Order += 1
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Text = string.upper(text),
		TextColor3 = THEME.SubText,
		Font = Enum.Font.GothamBold,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		LayoutOrder = tab.Order,
		Parent = tab.Page,
	})
end

local function addNote(tab, text)
	tab.Order += 1
	create("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = THEME.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = tab.Order,
		Parent = tab.Page,
	})
end

local function addToggle(tab, text, key, handler)
	tab.Order += 1
	local row = create("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = THEME.Surface,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = tab.Order,
		Parent = tab.Page,
	})
	corner(row, 8)

	create("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -64, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local switch = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(36, 20),
		BackgroundColor3 = THEME.Track,
		Parent = row,
	})
	corner(switch, 10)

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 3, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = THEME.Knob,
		Parent = switch,
	})
	corner(knob, 7)

	Handlers[key] = handler
	Refreshers[key] = function(instant)
		local on = State[key]
		local trackColor = on and THEME.Accent or THEME.Track
		local knobPos = on and UDim2.new(0, 19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0)
		if instant then
			switch.BackgroundColor3 = trackColor
			knob.Position = knobPos
		else
			tween(switch, { BackgroundColor3 = trackColor })
			tween(knob, { Position = knobPos })
		end
	end
	row.MouseButton1Click:Connect(function()
		setToggle(key, not State[key])
	end)
	Refreshers[key](true)
end

local function addSlider(tab, text, key, suffix)
	local range = RANGES[key]
	tab.Order += 1
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 50),
		BackgroundColor3 = THEME.Surface,
		LayoutOrder = tab.Order,
		Parent = tab.Page,
	})
	corner(row, 8)

	create("TextLabel", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -96, 0, 16),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	local valueLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 8),
		Size = UDim2.fromOffset(80, 16),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = THEME.Accent,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local bar = create("Frame", {
		Position = UDim2.new(0, 12, 0, 34),
		Size = UDim2.new(1, -24, 0, 4),
		BackgroundColor3 = THEME.Track,
		Parent = row,
	})
	corner(bar, 2)

	local fill = create("Frame", {
		Size = UDim2.fromScale(0, 1),
		BackgroundColor3 = THEME.Accent,
		Parent = bar,
	})
	corner(fill, 2)

	local knob = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = THEME.Knob,
		Parent = bar,
	})
	corner(knob, 7)

	local hitbox = create("TextButton", {
		Position = UDim2.fromOffset(0, 22),
		Size = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = "",
		ZIndex = 2,
		Parent = row,
	})

	local function render()
		local alpha = (State[key] - range[1]) / (range[2] - range[1])
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		valueLabel.Text = tostring(State[key]) .. suffix
	end

	local function setFromX(x)
		local width = bar.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
		local steps = math.floor(alpha * (range[2] - range[1]) / range[3] + 0.5)
		local value = math.clamp(range[1] + steps * range[3], range[1], range[2])
		if value ~= State[key] then
			State[key] = value
			render()
		end
	end

	local dragging = false
	local dragInput = nil

	hitbox.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		dragInput = kind == Enum.UserInputType.Touch and input or nil
		if tab.Scroller then
			tab.Scroller.ScrollingEnabled = false
		end
		setFromX(input.Position.X)
		local conn
		conn = input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
				if tab.Scroller then
					tab.Scroller.ScrollingEnabled = true
				end
				conn:Disconnect()
				saveConfig()
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
			setFromX(input.Position.X)
		end
	end))

	render()
end

local BUTTON_STYLES = {
	accent = { THEME.Accent, THEME.AccentDark },
	danger = { THEME.Danger, THEME.Text },
	plain = { THEME.SurfaceLight, THEME.Text },
}

local function styledButton(style, text, parent)
	local colors = BUTTON_STYLES[style] or BUTTON_STYLES.plain
	local button = create("TextButton", {
		BackgroundColor3 = colors[1],
		AutoButtonColor = true,
		Text = text,
		TextColor3 = colors[2],
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		Parent = parent,
	})
	corner(button, 8)
	return button
end

local function addButton(tab, text, style)
	tab.Order += 1
	local button = styledButton(style, text, tab.Page)
	button.Size = UDim2.new(1, 0, 0, 34)
	button.LayoutOrder = tab.Order
	return button
end

local function addButtonRow(tab, specs)
	tab.Order += 1
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = tab.Order,
		Parent = tab.Page,
	})
	local count = #specs
	local gap = 6
	local buttons = {}
	for index, spec in ipairs(specs) do
		local button = styledButton(spec[2], spec[1], row)
		button.Size = UDim2.new(1 / count, -gap * (count - 1) / count, 1, 0)
		button.Position = UDim2.new((index - 1) / count, gap * (index - 1) / count, 0, 0)
		buttons[index] = button
	end
	return table.unpack(buttons)
end

local VisualsTab = makeTab("Visuals", true)
addSection(VisualsTab, "Lighting")
addToggle(VisualsTab, "Fullbright", "Fullbright", onFullbright)
addToggle(VisualsTab, "No Fog", "NoFog", onNoFog)
addSection(VisualsTab, "Camera")
addToggle(VisualsTab, "Custom FOV", "CustomFov", onCustomFov)
addSlider(VisualsTab, "Field of view", "FovValue", "")
addToggle(VisualsTab, "First Person", "FirstPerson", onFirstPerson)
addToggle(VisualsTab, "No Camera Sway", "NoSway", onNoSway)

local MovementTab = makeTab("Movement", true)
addSection(MovementTab, "Walking")
addToggle(MovementTab, "Speed", "Speed", onSpeed)
addSlider(MovementTab, "Walk speed", "SpeedValue", "")
addToggle(MovementTab, "Infinite Jump", "InfJump")
addSection(MovementTab, "Flight")
addToggle(MovementTab, "Fly", "Fly", onFly)
addSlider(MovementTab, "Fly speed", "FlySpeed", "")
addToggle(MovementTab, "Noclip", "Noclip", onNoclip)
addSection(MovementTab, "Teleport")
addSlider(MovementTab, "Teleport distance", "TpDistance", "m")
addSection(MovementTab, "Auto picture")
addToggle(MovementTab, "Auto shutter", "AutoShot")
addToggle(MovementTab, "Clear view", "ClearView")
addSlider(MovementTab, "Safe distance", "SafeDistance", "m")
addSlider(MovementTab, "Photo window", "PhotoWindow", "s")
addToggle(MovementTab, "Pull to camera", "PullToCamera")

local EspTab = makeTab("ESP", true)
addSection(EspTab, "Highlights")
addToggle(EspTab, "Players", "PlayerESP", syncESP)
addToggle(EspTab, "Entities", "EntityESP", syncESP)
addToggle(EspTab, "Items", "ItemESP", syncESP)
addSection(EspTab, "Warning")
addToggle(EspTab, "Entity Alert", "EntityAlert", updateAlert)
addSlider(EspTab, "Alert range", "AlertRange", "m")

local EntitiesTab = makeTab("(NEW) entity achievements", false)
local PictureButton = addButton(EntitiesTab, "Auto take picture", "accent")
local TeleportButton, ReturnButton = addButtonRow(EntitiesTab, {
	{ "Teleport", "plain" },
	{ "Return", "plain" },
})
TeleportButton.MouseButton1Click:Connect(onTeleportPressed)
ReturnButton.MouseButton1Click:Connect(onReturnPressed)

EntitiesTab.Order += 1
local EntityCount = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Text = "ENTITIES (0)",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	LayoutOrder = EntitiesTab.Order,
	Parent = EntitiesTab.Page,
})

EntitiesTab.Order += 1
local EntityList = create("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -102),
	BackgroundTransparency = 1,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = THEME.Stroke,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	LayoutOrder = EntitiesTab.Order,
	Parent = EntitiesTab.Page,
})
create("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = EntityList,
})

local EntityEmpty = create("TextLabel", {
	Size = UDim2.new(1, -4, 0, 34),
	BackgroundTransparency = 1,
	Text = "No entities found yet",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	LayoutOrder = -1,
	Parent = EntityList,
})

Pumpkin.Tab = makeTab("(NEW) Halloween 2026", false)
Pumpkin.Button = addButton(Pumpkin.Tab, "Auto take pictures", "accent")
addToggle(Pumpkin.Tab, "Green pumpkin ESP", "PumpkinESP", syncESP)

Pumpkin.Tab.Order += 1
Pumpkin.Count = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Text = "GREEN PUMPKINS (0)",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	LayoutOrder = Pumpkin.Tab.Order,
	Parent = Pumpkin.Tab.Page,
})

Pumpkin.Tab.Order += 1
Pumpkin.List = create("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -104),
	BackgroundTransparency = 1,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = THEME.Stroke,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	LayoutOrder = Pumpkin.Tab.Order,
	Parent = Pumpkin.Tab.Page,
})
create("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = Pumpkin.List,
})

Pumpkin.Empty = create("TextLabel", {
	Size = UDim2.new(1, -4, 0, 34),
	BackgroundTransparency = 1,
	Text = "No pumpkins loaded yet",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	LayoutOrder = -1,
	Parent = Pumpkin.List,
})

-- Server hop finder: hops public servers of this game until the chosen entity shows up.
-- Before each hop the script queues itself with queue_on_teleport, so it starts on its own
-- in the next server and keeps looking. The hunt is also saved to a file, so an autoexec copy
-- of the script picks it up too.
local Hunt = {
	ScriptUrl = "https://raw.githubusercontent.com/playertatrer-bot/Sandbox-Public/main/ul.lua",
	StateFile = "Backrooms_hunt.json",
	KnownFile = "Backrooms_entities.json",
	ScanTime = 12, -- seconds to look around each server before hopping on
	Fresh = 180, -- seconds a saved hunt stays resumable, so an old one never restarts by surprise
	State = nil, -- { Target, Match, Loose, Key, Id, Active, Visited = { job ids }, Hops, Updated }
	Known = {}, -- every entity name seen in any server, saved to KnownFile
	Rows = {},
	Busy = false, -- a hop is in progress
	Failed = false, -- the last teleport failed
	Queued = false, -- this server already queued the script for the next one
	AliasMap = {}, -- normalized name -> wiki name, built from Seeds

	-- Every entity on the Unseen Liminality wiki: 15 in the game, then the upcoming
	-- and private server ones. Seen is the model name your game uses, from your clip.
	-- Also holds other likely model names. Names learned in new servers get added on top.
	Seeds = {
		{ Name = "Archibald Leland Sutter Still Life", Seen = "LampMan", Also = { "Archibald", "LampStillLife" } },
		{ Name = "The Misremembered", Seen = "Misremembered", Also = {} },
		{ Name = "The Misprint", Also = { "Misprint", "MisPaint" } },
		{ Name = "Still Life", Seen = "StillLife", Also = {} },
		{ Name = "The Caroler", Also = { "Caroler", "Carolers" } },
		{ Name = "The Mimic", Also = { "Mimic", "FakePlayer" } },
		{ Name = "Cap'n Clark", Seen = "Pirate", Also = { "CapnClark", "CaptainClark", "TheCaptain" } },
		{ Name = "The Bellhop", Also = { "Bellhop" } },
		{ Name = "Headhunter", Also = {} },
		{ Name = "The Rolling Giant", Also = { "RollingGiant" } },
		{ Name = "SpongeBob Balloon", Seen = "Bob", Also = { "SpongeBob", "SpongeBobBalloon" } },
		{ Name = "Die Dice", Also = { "DieDice" } },
		{ Name = "Looker", Also = {} },
		{ Name = "The Following Chair", Also = { "FollowingChair" } },
		{ Name = "The Moving Mannequins", Also = { "Mannequin", "Mannequins", "MovingMannequin", "MovingMannequins" } },
		{ Name = "Furniture Crabs", Also = { "FurnitureCrab" } },
		{ Name = "Captain Huss", Also = { "CaptainHuss", "Huss" } },
		{ Name = "Evil SpongeBob Balloon", Also = { "EvilBob", "EvilSpongeBob" } },
		{ Name = "Gubbys", Also = { "Gubby" } },
	},
}

Hunt.Tab = makeTab("(NEW) Server hop finder", false)
Hunt.Button = addButton(Hunt.Tab, "Server hop to find", "accent")

Hunt.Tab.Order += 1
Hunt.Box = create("TextBox", {
	Size = UDim2.new(1, 0, 0, 34),
	BackgroundColor3 = THEME.Surface,
	ClearTextOnFocus = false,
	PlaceholderText = "Type an entity or pick one below",
	PlaceholderColor3 = THEME.SubText,
	Text = "",
	TextColor3 = THEME.Text,
	Font = Enum.Font.GothamMedium,
	TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left,
	LayoutOrder = Hunt.Tab.Order,
	Parent = Hunt.Tab.Page,
})
corner(Hunt.Box, 8)
pad(Hunt.Box, 12, 12, 0, 0)

Hunt.Tab.Order += 1
Hunt.Count = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Text = "KNOWN ENTITIES (0)",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.GothamBold,
	TextSize = 10,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Bottom,
	LayoutOrder = Hunt.Tab.Order,
	Parent = Hunt.Tab.Page,
})

Hunt.Tab.Order += 1
Hunt.List = create("ScrollingFrame", {
	Size = UDim2.new(1, 0, 1, -102),
	BackgroundTransparency = 1,
	ScrollBarThickness = 2,
	ScrollBarImageColor3 = THEME.Stroke,
	ScrollingDirection = Enum.ScrollingDirection.Y,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	LayoutOrder = Hunt.Tab.Order,
	Parent = Hunt.Tab.Page,
})
create("UIListLayout", {
	Padding = UDim.new(0, 6),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = Hunt.List,
})

Hunt.Empty = create("TextLabel", {
	Size = UDim2.new(1, -4, 0, 34),
	BackgroundTransparency = 1,
	Text = "No entities seen yet",
	TextColor3 = THEME.SubText,
	Font = Enum.Font.Gotham,
	TextSize = 12,
	LayoutOrder = -1,
	Parent = Hunt.List,
})

-- Names match without case, spaces or symbols, so "Lamp Man" finds "LampMan" and "capn clark" finds "Cap'n Clark".
function Hunt.norm(name)
	return string.lower((string.gsub(name, "[^%w]", "")))
end

for _, seed in ipairs(Hunt.Seeds) do
	local key = Hunt.norm(seed.Name)
	Hunt.AliasMap[key] = seed.Name
	Hunt.AliasMap[(string.gsub(key, "^the", ""))] = seed.Name
	if seed.Seen then
		Hunt.AliasMap[Hunt.norm(seed.Seen)] = seed.Name
	end
	for _, alias in ipairs(seed.Also) do
		Hunt.AliasMap[Hunt.norm(alias)] = seed.Name
	end
end

-- Every normalized name that counts as the target. Wiki names bring all their aliases.
-- A typed name that is not on the wiki list matches loosely, by containment.
function Hunt.matchSet(target)
	local key = Hunt.norm(target)
	local owner = Hunt.AliasMap[key]
	if not owner then
		return { [key] = true }, true
	end
	local set = {}
	for alias, name in pairs(Hunt.AliasMap) do
		if name == owner then
			set[alias] = true
		end
	end
	return set, false
end

function Hunt.read(path)
	if not FileAccess then
		return nil
	end
	local ok, data = pcall(function()
		if isfile(path) then
			return HttpService:JSONDecode(readfile(path))
		end
		return nil
	end)
	return ok and data or nil
end

function Hunt.write(path, data)
	if FileAccess then
		pcall(function()
			writefile(path, HttpService:JSONEncode(data))
		end)
	end
end

for _, name in ipairs(Hunt.read(Hunt.KnownFile) or {}) do
	if type(name) == "string" then
		Hunt.Known[name] = true
	end
end

-- Remembers every entity name seen, so the list grows with each server you visit.
function Hunt.learn()
	local added = false
	for obj in pairs(Entities) do
		if obj:IsDescendantOf(workspace) and not isPlayerCharacter(obj) and not Hunt.Known[obj.Name] then
			Hunt.Known[obj.Name] = true
			added = true
		end
	end
	if added then
		local names = {}
		for name in pairs(Hunt.Known) do
			table.insert(names, name)
		end
		Hunt.write(Hunt.KnownFile, names)
	end
end

-- The hunted entity in this server, or nil. deep also checks every model in the map by name.
function Hunt.findHere(state, deep)
	local function fits(name)
		local key = Hunt.norm(name)
		if state.Match[key] then
			return true
		end
		return state.Loose and #state.Key >= 4 and string.find(key, state.Key, 1, true) ~= nil
	end
	for obj in pairs(Entities) do
		if obj:IsDescendantOf(workspace) and not isPlayerCharacter(obj) and fits(obj.Name) then
			return obj
		end
	end
	if deep then
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("Model") and fits(obj.Name) and not isPlayerCharacter(obj) then
				return obj
			end
		end
	end
	return nil
end

function Hunt.paint()
	local active = Hunt.State ~= nil and Hunt.State.Active
	local colors = BUTTON_STYLES[active and "danger" or "accent"]
	Hunt.Button.Text = active and "Stop finding" or "Server hop to find"
	Hunt.Button.BackgroundColor3 = colors[1]
	Hunt.Button.TextColor3 = colors[2]
end

function Hunt.save()
	local state = Hunt.State
	if state then
		state.Updated = os.time()
		Hunt.write(Hunt.StateFile, state)
	end
end

function Hunt.stop(message)
	if Hunt.State then
		Hunt.State.Active = false
		Hunt.save()
	end
	Hunt.State = nil
	GlobalEnv.BackroomsHunt = nil
	Hunt.paint()
	if message then
		notify(message)
	end
end

-- Picks a random public server of this place that has room and was not visited yet.
-- Fails with "error" when the server list does not load, or "full" when every server was visited.
function Hunt.pickServer()
	local visited = { [game.JobId] = true }
	for _, id in ipairs(Hunt.State.Visited) do
		visited[id] = true
	end
	local cursor = nil
	for _ = 1, 5 do
		local url = string.format(
			"https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100%s",
			game.PlaceId,
			cursor and ("&cursor=" .. HttpService:UrlEncode(cursor)) or ""
		)
		local fetched, page = pcall(function()
			return HttpService:JSONDecode(game:HttpGet(url))
		end)
		if not fetched or type(page) ~= "table" or type(page.data) ~= "table" then
			return nil, "error"
		end
		local open = {}
		for _, server in ipairs(page.data) do
			if type(server) == "table" and type(server.id) == "string" and not visited[server.id]
				and (tonumber(server.playing) or 0) < (tonumber(server.maxPlayers) or 0)
			then
				table.insert(open, server.id)
			end
		end
		if #open > 0 then
			return open[math.random(1, #open)]
		end
		if type(page.nextPageCursor) ~= "string" then
			break
		end
		cursor = page.nextPageCursor
	end
	return nil, "full"
end

-- Queues the script for the next server, then teleports. It never gives up on its own:
-- a busy server list gets retried, a failed teleport moves to another server, and once
-- every server was checked it starts over. Only Stop finding ends it.
function Hunt.hop()
	local state = Hunt.State
	if not state or not state.Active or Hunt.Busy then
		return
	end
	Hunt.Busy = true
	table.insert(state.Visited, game.JobId)
	while #state.Visited > 300 do
		table.remove(state.Visited, 1)
	end

	local failures = 0
	while Hunt.State == state and state.Active and Running do
		local serverId, reason = Hunt.pickServer()
		if not serverId then
			failures += 1
			if reason == "full" then
				notify("Checked every server, starting over", true, THEME.Accent)
				table.clear(state.Visited)
				table.insert(state.Visited, game.JobId)
			else
				notify("Server list busy, retrying", true, THEME.Accent)
			end
			task.wait(math.min(3 + failures * 2, 15))
		else
			state.Hops += 1
			Hunt.save()

			if not Hunt.Queued then
				local queue = queue_on_teleport or queueonteleport
					or (syn and syn.queue_on_teleport)
					or (fluxus and fluxus.queue_on_teleport)
				if typeof(queue) == "function" then
					local code = string.format(
						'getgenv().BackroomsHunt = game:GetService("HttpService"):JSONDecode([==[%s]==])\nloadstring(game:HttpGet("%s"))()',
						HttpService:JSONEncode(state),
						Hunt.ScriptUrl
					)
					Hunt.Queued = pcall(queue, code)
				end
				if not Hunt.Queued then
					notify("No queue_on_teleport here, add the script to autoexec", true, THEME.Danger)
					task.wait(3)
				end
			end

			Hunt.Failed = false
			local sent = pcall(function()
				game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, serverId, LocalPlayer)
			end)
			table.insert(state.Visited, serverId)
			local waited = 0
			while sent and waited < 30 and not Hunt.Failed and Hunt.State == state and state.Active and Running do
				task.wait(0.5)
				waited += 0.5
			end
			if Hunt.State == state and state.Active and Running then
				failures += 1
				notify("Teleport failed, trying another server", true, THEME.Accent)
				task.wait(math.min(2 + failures, 10))
			end
		end
	end
	Hunt.Busy = false
end

track(game:GetService("TeleportService").TeleportInitFailed:Connect(function(player)
	if player == LocalPlayer then
		Hunt.Failed = true
	end
end))

-- Looks around this server for ScanTime seconds, then hops on if the entity is not here.
function Hunt.run()
	local state = Hunt.State
	if not state or not state.Active then
		return
	end
	Hunt.paint()
	notify("Finding " .. state.Target, true, THEME.Accent)

	local started = os.clock()
	local nextDeep = started + 3
	local found = nil
	while Running and Hunt.State == state and state.Active and os.clock() - started < Hunt.ScanTime do
		local deep = os.clock() >= nextDeep
		if deep then
			nextDeep = os.clock() + 4
		end
		found = Hunt.findHere(state, deep)
		if found then
			break
		end
		task.wait(0.5)
	end
	if not Running or Hunt.State ~= state or not state.Active then
		return
	end

	if found then
		addEntity(found, "named")
		SelectedEntity = found
		if not State.EntityESP then
			setToggle("EntityESP", true)
		end
		Hunt.stop(nil)
		notify("FOUND!", true, THEME.Accent)
		return
	end
	notify("Not found, server hopping", true, THEME.Accent)
	task.wait(1)
	Hunt.hop()
end

function Hunt.start()
	local target = string.match(Hunt.Box.Text, "^%s*(.-)%s*$") or ""
	if target == "" then
		notify("Pick or type an entity first")
		return
	end
	local match, loose = Hunt.matchSet(target)
	Hunt.State = {
		Target = Hunt.AliasMap[Hunt.norm(target)] or target,
		Match = match,
		Loose = loose,
		Key = Hunt.norm(target),
		Id = HttpService:GenerateGUID(false),
		Active = true,
		Visited = {},
		Hops = 0,
	}
	Hunt.save()
	GlobalEnv.BackroomsHunt = Hunt.State
	task.spawn(Hunt.run)
end

-- Runs on load. Picks up a hunt from the last server, or from the copy this one replaced.
-- carried comes from queue_on_teleport, or from getgenv when the script reloads in the same server.
-- saved is the file. When both hold the same hunt, the file decides, since it records a Stop.
function Hunt.resume()
	local carried = GlobalEnv.BackroomsHunt
	local saved = Hunt.read(Hunt.StateFile)
	local state = nil
	if type(carried) == "table" and type(saved) == "table" and carried.Id == saved.Id then
		if saved.Active == true then
			state = saved
		end
	elseif type(carried) == "table" then
		if carried.Active == true then
			state = carried
		end
	elseif type(saved) == "table" and saved.Active == true
		and type(saved.Updated) == "number" and os.time() - saved.Updated <= Hunt.Fresh
	then
		state = saved -- autoexec copy with nothing carried over
	end
	if not state or type(state.Target) ~= "string" then
		GlobalEnv.BackroomsHunt = nil
		return
	end
	state.Visited = type(state.Visited) == "table" and state.Visited or {}
	state.Hops = tonumber(state.Hops) or 0
	if type(state.Match) ~= "table" or next(state.Match) == nil then
		state.Match, state.Loose = Hunt.matchSet(state.Target)
	end
	state.Key = type(state.Key) == "string" and state.Key or Hunt.norm(state.Target)
	Hunt.State = state
	GlobalEnv.BackroomsHunt = state
	Hunt.Box.Text = state.Target
	-- Starts looking right away. The scan does not need your character, and entities
	-- that load in during the scan still count.
	Hunt.run()
end

function Hunt.refresh()
	if Tabs[ActiveTab] ~= Hunt.Tab or not Window.Visible then
		return
	end
	-- Entities loaded in this server, by wiki name when one matches.
	local here = {}
	local origin = myPosition()
	for obj in pairs(Entities) do
		if obj:IsDescendantOf(workspace) and not isPlayerCharacter(obj) then
			local name = Hunt.AliasMap[Hunt.norm(obj.Name)] or obj.Name
			local root = getRoot(obj)
			local dist = root and (rootPosition(root) - origin).Magnitude or math.huge
			if not here[name] or dist < here[name] then
				here[name] = dist
			end
		end
	end

	-- Every wiki entity, plus learned names that match none of them. Ones in this server go first.
	local names, listed, labels = {}, {}, {}
	for _, seed in ipairs(Hunt.Seeds) do
		listed[seed.Name] = true
		table.insert(names, seed.Name)
		if seed.Seen and Hunt.norm(seed.Seen) ~= Hunt.norm(seed.Name) then
			labels[seed.Name] = seed.Name .. " (" .. seed.Seen .. ")"
		end
	end
	for name in pairs(Hunt.Known) do
		local display = Hunt.AliasMap[Hunt.norm(name)] or name
		if not listed[display] then
			listed[display] = true
			table.insert(names, display)
		end
	end
	table.sort(names, function(a, b)
		local da, db = here[a], here[b]
		if da and db then
			return da < db
		end
		if da or db then
			return da ~= nil
		end
		return string.lower(a) < string.lower(b)
	end)

	local chosenKey = Hunt.norm(Hunt.Box.Text)
	local chosen = Hunt.AliasMap[chosenKey]
	for index, name in ipairs(names) do
		local row = Hunt.Rows[name]
		if not row then
			local button = create("TextButton", {
				Size = UDim2.new(1, -4, 0, 34),
				BackgroundColor3 = THEME.Surface,
				AutoButtonColor = false,
				Text = "",
				Parent = Hunt.List,
			})
			corner(button, 8)
			local outline = stroke(button, THEME.Accent, 0, 1.5)
			local label = create("TextLabel", {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -84, 1, 0),
				BackgroundTransparency = 1,
				Text = labels[name] or name,
				TextColor3 = THEME.Text,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = button,
			})
			local status = create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0, 64, 1, 0),
				BackgroundTransparency = 1,
				Text = "",
				TextColor3 = THEME.SubText,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = button,
			})
			button.MouseButton1Click:Connect(function()
				Hunt.Box.Text = name
				Hunt.refresh()
			end)
			row = { Button = button, Outline = outline, Label = label, Status = status }
			Hunt.Rows[name] = row
		end
		local picked = (chosen ~= nil and chosen == name) or Hunt.norm(name) == chosenKey
		row.Button.LayoutOrder = index
		row.Outline.Enabled = picked
		row.Label.TextColor3 = picked and THEME.Accent or THEME.Text
		local dist = here[name]
		row.Status.Text = dist and string.format("here %dm", math.floor(dist)) or ""
	end
	Hunt.Empty.Visible = #names == 0
	Hunt.Count.Text = string.format("ENTITIES (%d)", #names)
end

Hunt.Tab.OnOpen = Hunt.refresh

Hunt.Button.MouseButton1Click:Connect(function()
	if Hunt.State and Hunt.State.Active then
		Hunt.stop("Stopped finding")
	else
		Hunt.start()
	end
end)

local MiscTab = makeTab("Misc", true)
addSection(MiscTab, "Utility")
addToggle(MiscTab, "Instant Interact", "InstantInteract", onInstantInteract)
addToggle(MiscTab, "Anti AFK", "AntiAfk")
addSection(MiscTab, "Script")
addNote(MiscTab, "Tap B or press RightShift to show or hide this menu. Settings save on their own.")
local UnloadButton = addButton(MiscTab, "Unload script", "danger")

local EntityRows = {}

local function paintSelection()
	for ent, row in pairs(EntityRows) do
		local active = ent == SelectedEntity
		row.Outline.Enabled = active
		row.Name.TextColor3 = active and THEME.Accent or THEME.Text
	end
end

local function makeEntityRow(entity)
	local button = create("TextButton", {
		Size = UDim2.new(1, -4, 0, 34),
		BackgroundColor3 = THEME.Surface,
		AutoButtonColor = false,
		Text = "",
		Parent = EntityList,
	})
	corner(button, 8)
	local outline = stroke(button, THEME.Accent, 0, 1.5)
	outline.Enabled = false

	local nameLabel = create("TextLabel", {
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -84, 1, 0),
		BackgroundTransparency = 1,
		Text = entity.Name,
		TextColor3 = THEME.Text,
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})

	local distLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 0),
		Size = UDim2.new(0, 64, 1, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = THEME.SubText,
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = button,
	})

	button.MouseButton1Click:Connect(function()
		if SelectedEntity == entity then
			SelectedEntity = nil
		else
			SelectedEntity = entity
		end
		paintSelection()
	end)

	local row = {
		Button = button,
		Name = nameLabel,
		Dist = distLabel,
		Outline = outline,
	}
	EntityRows[entity] = row
	return row
end

local function refreshEntityList()
	if Tabs[ActiveTab] ~= EntitiesTab or not Window.Visible then
		return
	end

	local origin = myPosition()
	local entries = {}
	local count = 0
	for ent in pairs(Entities) do
		if ent:IsDescendantOf(workspace) and not isPlayerCharacter(ent) then
			local root = getRoot(ent)
			if root then
				count += 1
				entries[count] = { Entity = ent, Distance = (rootPosition(root) - origin).Magnitude }
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.Distance < b.Distance
	end)

	local seen = {}
	for index, entry in ipairs(entries) do
		local ent = entry.Entity
		seen[ent] = true
		local row = EntityRows[ent] or makeEntityRow(ent)
		row.Button.LayoutOrder = index
		row.Name.Text = ent.Name
		local holding = Bring.Held and Bring.Held.Entity == ent
		row.Dist.Text = holding and (Bring.Held.Mode == "lock" and "locked" or "held")
			or string.format("%dm", math.floor(entry.Distance))
	end
	for ent, row in pairs(EntityRows) do
		if not seen[ent] then
			row.Button:Destroy()
			EntityRows[ent] = nil
		end
	end
	if SelectedEntity and not seen[SelectedEntity] then
		SelectedEntity = nil
	end

	EntityEmpty.Visible = count == 0
	EntityCount.Text = string.format("ENTITIES (%d)", count)
	paintSelection()
end

EntitiesTab.OnOpen = refreshEntityList

-- Returns loaded pumpkins nearest first, and true when they are confirmed green.
-- Each entry is the smallest pumpkin-sized object, so a container model holding many
-- pumpkins never counts as one giant pumpkin in the middle of the map.
-- With no confirmed green ones it returns every pumpkin so the run still has targets.
local function collectPumpkins()
	local MAX_SIZE = 25 -- studs. Anything bigger is a container, not a pumpkin.

	local function greenish(color)
		return color.G > color.R + 0.12 and color.G > color.B + 0.12
	end

	-- Green check: names and attributes up to 3 levels up, green lights or highlights,
	-- green mesh tint, then the color of the biggest part.
	local function isGreen(obj)
		local node, depth = obj, 0
		while node and node ~= workspace and depth < 4 do
			if string.find(string.lower(node.Name), "green", 1, true) then
				return true
			end
			for key, value in pairs(node:GetAttributes()) do
				local attr = string.lower(key) .. " " .. (type(value) == "string" and string.lower(value) or "")
				if string.find(attr, "green", 1, true) then
					return true
				end
			end
			node = node.Parent
			depth += 1
		end
		local best, bestSize = nil, 0
		local parts = obj:GetDescendants()
		if obj:IsA("BasePart") then
			table.insert(parts, obj)
		end
		for _, child in ipairs(parts) do
			if child:IsA("Light") then
				if greenish(child.Color) then
					return true
				end
			elseif child:IsA("Highlight") then
				if greenish(child.FillColor) or greenish(child.OutlineColor) then
					return true
				end
			elseif child:IsA("SpecialMesh") then
				local tint = child.VertexColor
				if tint.Y > tint.X + 0.12 and tint.Y > tint.Z + 0.12 then
					return true
				end
			elseif child:IsA("BasePart") and child.Size.Magnitude > bestSize then
				best, bestSize = child, child.Size.Magnitude
			end
		end
		return best ~= nil and greenish(best.Color)
	end

	-- Display name: the closest name with "pumpkin" in it, preferring one that also says "green".
	local function labelOf(obj)
		local node, depth, named = obj, 0, nil
		while node and node ~= workspace and depth < 4 do
			local lowered = string.lower(node.Name)
			if string.find(lowered, "pumpkin", 1, true) then
				if string.find(lowered, "green", 1, true) then
					return node.Name
				end
				named = named or node.Name
			end
			node = node.Parent
			depth += 1
		end
		return named or obj.Name
	end

	local function sizeOf(obj)
		local _, size = boundsOf(obj)
		return math.max(size.X, size.Y, size.Z)
	end

	local CollectionService = game:GetService("CollectionService")
	local taggedGreen = {}
	local ok, tags = pcall(function()
		return CollectionService:GetAllTags()
	end)
	if ok then
		for _, tag in ipairs(tags) do
			local lowered = string.lower(tag)
			if string.find(lowered, "pumpkin", 1, true) then
				for _, obj in ipairs(CollectionService:GetTagged(tag)) do
					if obj:IsA("Model") or obj:IsA("BasePart") then
						Pumpkin.Found[obj] = true
						if string.find(lowered, "green", 1, true) then
							taggedGreen[obj] = true
						end
					end
				end
			end
		end
	end

	-- Pumpkins a player is carrying do not count.
	local function carried(obj)
		local node = obj.Parent
		while node and node ~= workspace do
			if node:IsA("Tool") or Players:GetPlayerFromCharacter(node) then
				return true
			end
			node = node.Parent
		end
		return false
	end

	local named = {}
	for obj in pairs(Pumpkin.Found) do
		if not obj:IsDescendantOf(workspace) then
			Pumpkin.Found[obj] = nil
		elseif not carried(obj) then
			named[obj] = true
		end
	end

	local function holdsNamed(obj)
		for other in pairs(named) do
			if other ~= obj and other:IsDescendantOf(obj) then
				return true
			end
		end
		return false
	end

	-- Pumpkin-sized named objects count. A big one with no named pumpkins inside
	-- stands for its pumpkin-sized children instead.
	local candidates = {}
	for obj in pairs(named) do
		if sizeOf(obj) <= MAX_SIZE then
			candidates[obj] = true
		elseif not holdsNamed(obj) then
			for _, child in ipairs(obj:GetChildren()) do
				if (child:IsA("Model") or child:IsA("BasePart")) and sizeOf(child) <= MAX_SIZE then
					candidates[child] = true
				end
			end
		end
	end

	-- A candidate holding another candidate is a wrapper. The one inside is the pumpkin.
	local wrappers = {}
	for obj in pairs(candidates) do
		local node = obj.Parent
		while node and node ~= workspace do
			if candidates[node] then
				wrappers[node] = true
			end
			node = node.Parent
		end
	end

	local origin = myPosition()
	local green, all = {}, {}
	for obj in pairs(candidates) do
		local root = not wrappers[obj] and getRoot(obj)
		if root and root:IsA("BasePart") then
			local entry = {
				Target = obj,
				Label = labelOf(obj),
				Distance = (root.Position - origin).Magnitude,
			}
			table.insert(all, entry)
			if taggedGreen[obj] or isGreen(obj) then
				table.insert(green, entry)
			end
		end
	end
	local list = #green > 0 and green or all
	table.sort(list, function(a, b)
		return a.Distance < b.Distance
	end)
	return list, #green > 0
end

local function refreshPumpkinList()
	if Tabs[ActiveTab] ~= Pumpkin.Tab or not Window.Visible then
		return
	end
	local list, confirmed = Pumpkin.Targets or {}, Pumpkin.Confirmed
	local seen = {}
	local done = 0
	for index, entry in ipairs(list) do
		local obj = entry.Target
		seen[obj] = true
		local row = Pumpkin.Rows[obj]
		if not row then
			local frame = create("Frame", {
				Size = UDim2.new(1, -4, 0, 34),
				BackgroundColor3 = THEME.Surface,
				Parent = Pumpkin.List,
			})
			corner(frame, 8)
			create("TextLabel", {
				Position = UDim2.fromOffset(12, 0),
				Size = UDim2.new(1, -84, 1, 0),
				BackgroundTransparency = 1,
				Text = entry.Label,
				TextColor3 = THEME.Text,
				Font = Enum.Font.GothamMedium,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = frame,
			})
			local status = create("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -12, 0, 0),
				Size = UDim2.new(0, 64, 1, 0),
				BackgroundTransparency = 1,
				Text = "",
				TextColor3 = THEME.SubText,
				Font = Enum.Font.Gotham,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = frame,
			})
			row = { Frame = frame, Status = status }
			Pumpkin.Rows[obj] = row
		end
		local isDone = Pumpkin.Done[obj] == true
		if isDone then
			done += 1
		end
		row.Frame.LayoutOrder = index
		row.Status.Text = isDone and "done" or string.format("%dm", math.floor(entry.Distance))
		row.Status.TextColor3 = isDone and THEME.Accent or THEME.SubText
	end
	for obj, row in pairs(Pumpkin.Rows) do
		if not seen[obj] then
			row.Frame:Destroy()
			Pumpkin.Rows[obj] = nil
		end
	end
	Pumpkin.Empty.Visible = #list == 0
	Pumpkin.Count.Text = string.format("%s (%d)   DONE %d", confirmed and "GREEN PUMPKINS" or "PUMPKINS", #list, done)
end

Pumpkin.Tab.OnOpen = refreshPumpkinList

-- One picture of one target: get close, lock on, shoot until the picture is confirmed, clean up.
-- near lands you on the floor next to it (pumpkins). Otherwise you float above it (entities).
-- Returns whether a picture was confirmed, a message when something went wrong, and whether the whole run should stop.
local function shootTarget(target, token, near)
	local function findCamera(holder)
		if not holder then
			return nil
		end
		for _, child in ipairs(holder:GetChildren()) do
			if child:IsA("Tool") then
				local name = string.lower(child.Name)
				for _, word in ipairs(HOLD.CameraWords) do
					if string.find(name, word, 1, true) then
						return child
					end
				end
			end
		end
		return nil
	end

	-- Equips the camera tool if needed. Returns it only when it is ready to shoot.
	local function cameraReady()
		local char, hum = getCharacter()
		if not char or not hum then
			return nil
		end
		local tool = findCamera(char)
		if not tool then
			tool = findCamera(LocalPlayer:FindFirstChildOfClass("Backpack"))
			if not tool then
				return nil
			end
			hum:EquipTool(tool)
			task.wait(0.35)
		end
		if not tool.Enabled then
			return nil -- still reloading
		end
		return tool
	end

	local watchers = {}
	local shot = false
	local message = nil
	local stop = false

	local ok, err = pcall(function()
		if releaseHeld() then
			task.wait(0.15)
		end

		local moved, reason
		if near then
			moved, reason = landNear(target, HOLD.PumpkinNear, true)
		else
			moved, reason = floatAbove(target)
		end
		if not moved then
			message = reason
			return
		end

		task.wait(HOLD.Settle)
		if not Running or token ~= Bring.Token then
			message, stop = "Cancelled", true
			return
		end
		local char, hum = getCharacter()
		if not char or not hum or hum.Health <= 0 then
			message, stop = "You died before the shot", true
			return
		end
		if not target:IsDescendantOf(workspace) then
			message = target.Name .. " unloaded"
			return
		end

		local mode = State.PullToCamera and "pull" or "lock"
		aimCamera(target)
		if not grabEntity(target, mode) then
			return
		end
		if mode == "pull" then
			notify("Ready!", false, THEME.Accent)
		end

		-- A tap is only a try. A picture counts once something a real photo touches reacts.
		-- Reward signals: the game's remote, your stats, the target.
		-- Camera signals: the shutter sound, the capture animation, the flash, the camera going on
		-- cooldown, a popup in your GUI. These fire with no reward too, so a picture of an entity
		-- already in your album still counts.
		-- Whatever reacts before the first try is background noise for the rest of the run.
		local events = {}
		local lastTry = nil
		local noise = Bring.Noise
		local hasTool = findCamera(char) ~= nil or findCamera(LocalPlayer:FindFirstChildOfClass("Backpack")) ~= nil
		local started = os.clock()
		local baselineEnd = started + HOLD.Baseline
		local deadline = started + State.PhotoWindow
		local nextTry = baselineEnd
		local tries = 0
		-- Past the baseline: a try happened, or with no camera tool, the baseline time ran out.
		local function live()
			return lastTry ~= nil or (not hasTool and os.clock() >= baselineEnd)
		end

		local function listen(signal, source, check)
			table.insert(watchers, signal:Connect(function()
				if not check or check() then
					events[source] = os.clock()
				end
			end))
		end
		local gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if gui then
			listen(gui.DescendantAdded, "gui")
		end
		listen(LocalPlayer.AttributeChanged, "stats")
		for _, obj in ipairs(LocalPlayer:GetDescendants()) do
			if obj:IsA("ValueBase") and not (gui and obj:IsDescendantOf(gui)) then
				listen(obj.Changed, "stats")
			end
		end
		listen(target.AncestryChanged, "target")
		listen(target.AttributeChanged, "target")

		-- Sounds count one by one: any sound that plays before the first try is noise from then on.
		-- Your character's footstep and fall sounds never count.
		local function onSound(sound)
			if not live() then
				noise.Sounds[sound] = true
			elseif not noise.Sounds[sound] then
				events.sound = os.clock()
			end
		end
		local function watchSounds(container)
			if not container then
				return
			end
			local function hook(obj)
				if obj:IsA("Sound") and not (obj.Parent and obj.Parent.Name == "HumanoidRootPart") then
					table.insert(watchers, obj.Played:Connect(function()
						onSound(obj)
					end))
					if obj.IsPlaying then
						onSound(obj)
					end
				end
			end
			for _, obj in ipairs(container:GetDescendants()) do
				hook(obj)
			end
			table.insert(watchers, container.DescendantAdded:Connect(hook))
		end
		watchSounds(gui)
		watchSounds(game:GetService("SoundService"))
		watchSounds(workspace.CurrentCamera)
		watchSounds(char)

		-- Animations count one by one too. Walk, idle and the other default animations never count.
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then
			local defaults = {}
			local animate = char:FindFirstChild("Animate")
			if animate then
				for _, obj in ipairs(animate:GetDescendants()) do
					if obj:IsA("Animation") then
						defaults[obj.AnimationId] = true
					end
				end
			end
			table.insert(watchers, animator.AnimationPlayed:Connect(function(track)
				local id = track.Animation and track.Animation.AnimationId or ""
				if defaults[id] then
					return
				end
				if not live() then
					noise.Anims[id] = true
				elseif not noise.Anims[id] then
					events.anim = os.clock()
				end
			end))
		end

		-- Your own taps count as tries too, so manual shots get confirmed the same way.
		local tools = {}
		local function watchTool(obj)
			if not obj:IsA("Tool") or tools[obj] then
				return
			end
			tools[obj] = true
			table.insert(watchers, obj.Activated:Connect(function()
				lastTry = os.clock()
			end))
			listen(obj:GetPropertyChangedSignal("Enabled"), "cooldown", function()
				return not obj.Enabled
			end)
			for _, light in ipairs(obj:GetDescendants()) do
				if light:IsA("Light") then
					listen(light:GetPropertyChangedSignal("Enabled"), "flash", function()
						return light.Enabled
					end)
				end
			end
		end
		for _, child in ipairs(char:GetChildren()) do
			watchTool(child)
		end
		table.insert(watchers, char.ChildAdded:Connect(watchTool))
		table.clear(Bring.RemoteLog)

		-- Once the photo remote is known, other remotes stop counting. Every other signal still counts.
		local function confirmedSince(since)
			for _, entry in ipairs(Bring.RemoteLog) do
				local remote, at = entry[1], entry[2]
				if at >= since and not noise.Remotes[remote] and (not Bring.PhotoRemote or Bring.PhotoRemote == remote) then
					Bring.PhotoRemote = remote
					return true
				end
			end
			for source, at in pairs(events) do
				if at >= since and not noise.Sources[source] then
					return true
				end
			end
			return false
		end
		while Running and token == Bring.Token and os.clock() < deadline do
			local _, alive = getCharacter()
			if not alive or alive.Health <= 0 then
				message, stop = "You died before the shot", true
				return
			end
			local now = os.clock()
			if not lastTry and (hasTool or now < baselineEnd) then
				for source in pairs(events) do
					noise.Sources[source] = true
				end
				for _, entry in ipairs(Bring.RemoteLog) do
					noise.Remotes[entry[1]] = true
				end
			end

			-- With no camera tool, any proof after the baseline counts, for a screen button shutter.
			local since = lastTry or (not hasTool and now >= baselineEnd and baselineEnd) or nil
			if since and confirmedSince(since) then
				shot = true
				notify("Picture taken!", false, THEME.Accent)
				task.wait(HOLD.Grace)
				break
			end
			local held = Bring.Held
			if not held then
				break
			end

			-- Auto shutter: try once the view is clear and the camera is ready.
			-- No proof within Confirm seconds means the camera was still reloading, so it tries again.
			if State.AutoShot and now >= nextTry and (held.Mode == "pull" or held.Clear) then
				local tool = cameraReady()
				if tool then
					tries += 1
					if tries == 2 then
						notify("Waiting for the camera", true, THEME.Accent)
					end
					lastTry = os.clock()
					tool:Activate()
					nextTry = os.clock() + HOLD.Confirm
				else
					nextTry = os.clock() + 0.2
				end
			end
			task.wait()
		end
		if token ~= Bring.Token then
			message, stop = "Cancelled", true
		elseif not shot then
			message = "No shot taken"
		end
	end)

	for _, conn in ipairs(watchers) do
		conn:Disconnect()
	end
	pcall(releaseHeld)
	pcall(stopHover)
	pcall(restoreCleared)
	if not ok then
		warn("[Backrooms] " .. tostring(err))
		message = "Picture failed"
	end
	return shot, message, stop
end

-- Takes a picture of each target in order from one saved spot, then sends you back there.
-- onShot runs for every target that got a shot.
local function runPictures(targets, button, idleText, near, onShot)
	-- While a run is active its button turns into Cancel.
	local function paintRunButton(running)
		local colors = BUTTON_STYLES[running and "danger" or "accent"]
		button.Text = running and "Cancel" or idleText
		button.BackgroundColor3 = colors[1]
		button.TextColor3 = colors[2]
	end

	Bring.Running = true
	Bring.Token += 1
	local token = Bring.Token
	paintRunButton(true)
	Bring.Noise = { Remotes = {}, Sources = {}, Sounds = {}, Anims = {} }

	-- Remote watch: logs the game's own FireServer and InvokeServer calls during the run.
	-- A picture has to reach the server, so a call right after a shot is the strongest proof.
	-- Needs hookmetamethod. Without it, the other proof signals still work. Removed when the run ends.
	if not Bring.Unhook and typeof(hookmetamethod) == "function" and typeof(getnamecallmethod) == "function" then
		local log = Bring.RemoteLog
		local fromScript = typeof(checkcaller) == "function" and checkcaller or function()
			return false
		end
		local original
		local function spy(self, ...)
			local method = getnamecallmethod()
			if (method == "FireServer" or method == "InvokeServer") and not fromScript() then
				log[#log + 1] = { self, os.clock() }
			end
			return original(self, ...)
		end
		if typeof(newcclosure) == "function" then
			spy = newcclosure(spy)
		end
		local hooked, previous = pcall(hookmetamethod, game, "__namecall", spy)
		if hooked and previous then
			original = previous
			Bring.Unhook = function()
				Bring.Unhook = nil
				pcall(hookmetamethod, game, "__namecall", previous)
			end
		end
	end

	local _, _, startRoot = getCharacter()
	local home = startRoot and startRoot.CFrame
	local savedReturn = ReturnCFrame
	local total = #targets
	local shots = 0
	local message = nil
	local stopReason = nil

	if not home then
		message = "Your character is not ready"
	else
		for index, target in ipairs(targets) do
			if not Running or token ~= Bring.Token then
				break
			end
			if target:IsDescendantOf(workspace) then
				local count = total > 1 and string.format(" (%d/%d)", index, total) or ""
				notify("Teleporting you to bypass kicks" .. count, true, THEME.Accent)
				local shot, reason, stop = shootTarget(target, token, near)
				if shot then
					shots += 1
					if onShot then
						onShot(target)
					end
				end
				message = reason
				if stop then
					stopReason = reason
					break
				end
			end
		end
		if total > 1 then
			local summary = string.format("%d of %d pictures taken", shots, total)
			message = stopReason and (stopReason .. ", " .. summary) or summary
		end
	end

	if Bring.Unhook then
		Bring.Unhook()
	end
	table.clear(Bring.RemoteLog)
	ReturnCFrame = savedReturn
	Bring.Running = false
	if not Running then
		return
	end
	paintRunButton(false)

	local returned = false
	local _, hum, root = getCharacter()
	if home and hum and root and hum.Health > 0 then
		root.CFrame = home
		root.AssemblyLinearVelocity = Vector3.zero
		returned = true
	end
	if returned then
		message = message and (message .. ", back at your spot") or "Back at your spot"
	end
	notify(message or "Stopped")
	task.spawn(refreshEntityList)
	task.spawn(refreshPumpkinList)
end

PictureButton.MouseButton1Click:Connect(function()
	if Bring.Running then
		Bring.Token += 1
		return
	end
	if TeleportBusy then
		return
	end
	local target = SelectedEntity
	if not target then
		notify("Pick an entity from the list")
		return
	end
	task.spawn(runPictures, { target }, PictureButton, "Auto take picture")
end)

-- Shoots every loaded pumpkin that is not done yet, nearest first, then sends you back.
Pumpkin.Button.MouseButton1Click:Connect(function()
	if Bring.Running then
		Bring.Token += 1
		return
	end
	if TeleportBusy then
		return
	end
	local list = collectPumpkins()
	local targets = {}
	for _, entry in ipairs(list) do
		if not Pumpkin.Done[entry.Target] then
			table.insert(targets, entry.Target)
		end
	end
	if #targets == 0 then
		notify(#list == 0 and "No pumpkins loaded yet" or "Every loaded pumpkin is done")
		return
	end
	task.spawn(runPictures, targets, Pumpkin.Button, "Auto take pictures", true, function(target)
		Pumpkin.Done[target] = true
	end)
end)

local function toggleWindow()
	Window.Visible = not Window.Visible
	if Window.Visible then
		task.spawn(refreshEntityList)
	end
end

local function makeDraggable(handle, frame)
	local dragging = false
	local moved = false
	local dragInput = nil
	local startInput, startPos

	handle.InputBegan:Connect(function(input)
		local kind = input.UserInputType
		if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
			return
		end
		dragging = true
		moved = false
		dragInput = kind == Enum.UserInputType.Touch and input or nil
		startInput = input.Position
		startPos = frame.Position
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
		if not valid then
			return
		end
		local delta = input.Position - startInput
		if delta.Magnitude > 6 then
			moved = true
		end
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + delta.X,
			startPos.Y.Scale, startPos.Y.Offset + delta.Y
		)
	end))

	return function()
		return moved
	end
end

makeDraggable(TitleBar, Window)
HideButton.MouseButton1Click:Connect(toggleWindow)

do
	local OpenButton = create("TextButton", {
		Name = "Open",
		Position = UDim2.new(0, 12, 0.25, 0),
		Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = THEME.Window,
		BackgroundTransparency = 0.05,
		AutoButtonColor = false,
		Text = "B",
		TextColor3 = THEME.Accent,
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		Parent = ScreenGui,
	})
	corner(OpenButton, 23)
	stroke(OpenButton, THEME.Accent, 0.2, 1.5)

	local openWasDragged = makeDraggable(OpenButton, OpenButton)
	OpenButton.MouseButton1Click:Connect(function()
		if not openWasDragged() then
			toggleWindow()
		end
	end)
end

track(UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then
		toggleWindow()
	end
end))

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value, applyEnvironment)
RunService:BindToRenderStep(SWAY_GUARD_NAME, Enum.RenderPriority.Camera.Value - 1, guardCameraOffset)
RunService:BindToRenderStep(SWAY_FIX_NAME, Enum.RenderPriority.Last.Value + 1000, stabilizeCamera)
RunService:BindToRenderStep(HOLD_NAME, Enum.RenderPriority.Camera.Value + 1, safePin)

track(RunService.RenderStepped:Connect(function()
	if State.NoSway then
		task.defer(stabilizeCamera)
	end
end))

track(LocalPlayer.DescendantAdded:Connect(function(obj)
	if State.NoSway and obj.ClassName == "LocalScript" then
		muteSwayScript(obj)
	end
end))

track(RunService.Heartbeat:Connect(function()
	if State.Speed then
		local _, hum = getCharacter()
		if hum then
			hum.WalkSpeed = State.SpeedValue
		end
	end
	if State.Fly then
		stepFly()
	end
	stepHover()
	safePin()
end))

track(RunService.Stepped:Connect(function()
	if State.Noclip or Bring.Hover then
		stepNoclip()
	end
	stepHover()
	safePin()
end))

track(UserInputService.JumpRequest:Connect(function()
	if State.InfJump and not State.Fly then
		local _, hum = getCharacter()
		if hum then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end))

track(LocalPlayer.Idled:Connect(function()
	if State.AntiAfk and hasVirtualUser then
		pcall(function()
			VirtualUser:CaptureController()
			VirtualUser:ClickButton2(Vector2.zero)
		end)
	end
end))

loop(0.5, maintain)
loop(0.5, refreshEntityList)
-- Pumpkin scan feeds the list, the ESP and the run.
loop(1, function()
	Pumpkin.Targets, Pumpkin.Confirmed = collectPumpkins()
end)
loop(0.5, refreshPumpkinList)
loop(3, Hunt.learn)
loop(1, Hunt.refresh)
loop(0.15, function()
	updateLabels()
	updateAlert()
end)

-- reason is "reload" when a new copy of the script replaces this one. The hunt then stays
-- saved for the new copy. The Unload button passes nothing, which ends the hunt.
local function unload(reason)
	if not Running then
		return
	end
	Running = false
	pcall(releaseHeld)
	pcall(stopHover)
	pcall(restoreCleared)
	if Bring.Unhook then
		pcall(Bring.Unhook)
	end
	if Hunt.State and reason ~= "reload" then
		pcall(Hunt.stop, nil)
	end
	for key, handler in pairs(Handlers) do
		if State[key] then
			State[key] = false
			pcall(handler, false)
		end
	end
	for _, conn in ipairs(Connections) do
		conn:Disconnect()
	end
	for _, bindName in ipairs(RENDER_NAMES) do
		pcall(function()
			RunService:UnbindFromRenderStep(bindName)
		end)
	end
	for target in pairs(ESP) do
		removeESP(target)
	end
	Probe:Destroy()
	ESPFolder:Destroy()
	ScreenGui:Destroy()
	if GlobalEnv.BackroomsUnload == unload then
		GlobalEnv.BackroomsUnload = nil
	end
end

UnloadButton.MouseButton1Click:Connect(unload)
GlobalEnv.BackroomsUnload = unload

selectTab("Visuals")

for _, key in ipairs(SAVED_KEYS) do
	local value = Saved[key]
	if type(value) == "boolean" and type(State[key]) == "boolean" and value ~= State[key] then
		setToggle(key, value)
	end
end

notify("Backrooms loaded")
task.spawn(Hunt.resume)
