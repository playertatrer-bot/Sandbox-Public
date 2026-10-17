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
local RENDER_NAMES = { RENDER_NAME, SWAY_GUARD_NAME, SWAY_FIX_NAME }

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

if type(GlobalEnv.BackroomsUnload) == "function" then
	pcall(GlobalEnv.BackroomsUnload)
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
	InstantInteract = false,
	AntiAfk = false,
}

local RANGES = {
	FovValue = { 30, 120, 5 },
	SpeedValue = { 16, 150, 2 },
	FlySpeed = { 10, 300, 5 },
	AlertRange = { 20, 300, 10 },
	TpDistance = { 10, 100, 5 },
}

local SAVED_KEYS = {
	"Fullbright", "NoFog", "CustomFov", "FovValue", "FirstPerson", "NoSway",
	"SpeedValue", "FlySpeed", "PlayerESP", "EntityESP", "ItemESP",
	"EntityAlert", "AlertRange", "TpDistance", "InstantInteract", "AntiAfk",
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

local function notify(text)
	toastId += 1
	local id = toastId
	Toast.Text = text
	tween(Toast, { BackgroundTransparency = 0.05, TextTransparency = 0 })
	tween(ToastStroke, { Transparency = 0 })
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
		StudsOffset = Vector3.new(0, kind == "Item" and 1.5 or 3.5, 0),
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
		if not obj:IsDescendantOf(workspace) then
			Entities[obj] = nil
		elseif source == "humanoid" and not obj:FindFirstChildOfClass("Humanoid") then
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
		if obj:IsDescendantOf(workspace) and not isPlayerCharacter(obj) then
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

local function findSafeSpot(target, targetRoot, distance, height)
	local center = targetRoot.Position
	local behind = flatUnit(-targetRoot.CFrame.LookVector) or Vector3.new(1, 0, 0)
	local baseFloor = findFloor(center + Vector3.new(0, 1, 0), 40)
	local probeY = baseFloor and baseFloor.Y + 3 or center.Y + 1

	for _, scale in ipairs(TP_SCALES) do
		local radius = math.max(distance * scale, MIN_TP_DISTANCE)
		for _, angle in ipairs(TP_ANGLES) do
			local direction = CFrame.Angles(0, math.rad(angle), 0):VectorToWorldSpace(behind)
			local probe = Vector3.new(center.X, probeY, center.Z) + direction * radius
			local floor = findFloor(probe, 40)
			if floor
				and (not baseFloor or math.abs(floor.Y - baseFloor.Y) <= 8)
				and hasRoom(floor, height)
				and awayFromEntities(floor, target)
			then
				return floor
			end
		end
	end
	return nil
end

local function rootHeight(hum, root)
	if hum.RigType == Enum.HumanoidRigType.R15 then
		return hum.HipHeight + root.Size.Y / 2
	end
	return root.Size.Y / 2 + 2
end

local function teleportToEntity(target)
	if not target or not target:IsDescendantOf(workspace) then
		notify("Pick an entity from the list")
		return
	end

	local targetRoot = getRoot(target)
	if workspace.StreamingEnabled and targetRoot then
		pcall(function()
			LocalPlayer:RequestStreamAroundAsync(rootPosition(targetRoot), 3)
		end)
		if not target:IsDescendantOf(workspace) then
			notify("The entity left before the teleport")
			return
		end
		targetRoot = getRoot(target)
	end
	if not targetRoot or not targetRoot:IsA("BasePart") then
		notify(target.Name .. " has no body to aim at")
		return
	end

	local char, hum, root = getCharacter()
	if not char or not hum or not root or hum.Health <= 0 then
		notify("Your character is not ready")
		return
	end

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
	local spaceIgnore = table.clone(players)
	table.insert(spaceIgnore, Probe)
	FloorRay.FilterDescendantsInstances = ignore
	SpaceCheck.FilterDescendantsInstances = spaceIgnore

	local height = math.clamp(char:GetExtentsSize().Y - 0.5, 3, 7)
	Probe.Parent = workspace.CurrentCamera or workspace
	local searched, floor = pcall(findSafeSpot, target, targetRoot, State.TpDistance, height)
	Probe.Parent = nil
	if not searched then
		error(floor, 0)
	end
	if not floor then
		notify("No safe spot near " .. target.Name)
		return
	end

	local standPos = floor + Vector3.new(0, rootHeight(hum, root) + 0.25, 0)
	local focus = Vector3.new(targetRoot.Position.X, standPos.Y, targetRoot.Position.Z)
	ReturnCFrame = root.CFrame
	root.CFrame = CFrame.lookAt(standPos, focus)
	root.AssemblyLinearVelocity = Vector3.zero
	notify(string.format("Landed %dm from %s", math.floor((focus - standPos).Magnitude), target.Name))
end

local function onTeleportPressed()
	if TeleportBusy then
		return
	end
	if not SelectedEntity then
		notify("Pick an entity from the list")
		return
	end
	TeleportBusy = true
	local ok, err = pcall(teleportToEntity, SelectedEntity)
	TeleportBusy = false
	if not ok then
		warn("[Backrooms] " .. tostring(err))
		notify("Teleport failed")
	end
end

local function onReturnPressed()
	if not ReturnCFrame then
		notify("No saved spot yet")
		return
	end
	local _, hum, root = getCharacter()
	if not hum or not root or hum.Health <= 0 then
		notify("Your character is not ready")
		return
	end
	root.CFrame = ReturnCFrame
	root.AssemblyLinearVelocity = Vector3.zero
	ReturnCFrame = nil
	notify("Back at your saved spot")
end

local startCamera = workspace.CurrentCamera
local viewport = startCamera and startCamera.ViewportSize or Vector2.new(1280, 720)
local WINDOW_WIDTH = math.min(340, viewport.X - 90)
local WINDOW_HEIGHT = math.clamp(viewport.Y - 80, 250, 360)
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

local Sidebar = create("Frame", {
	Name = "Sidebar",
	Position = UDim2.fromOffset(0, BODY_TOP),
	Size = UDim2.new(0, SIDEBAR_WIDTH, 1, BODY_HEIGHT),
	BackgroundTransparency = 1,
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
		Position = UDim2.fromOffset(12, 0),
		Size = UDim2.new(1, -12, 1, 0),
		BackgroundTransparency = 1,
		Text = name,
		TextColor3 = THEME.SubText,
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = button,
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

local function addButtonPair(tab, leftText, rightText)
	tab.Order += 1
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 34),
		BackgroundTransparency = 1,
		LayoutOrder = tab.Order,
		Parent = tab.Page,
	})
	local left = styledButton("accent", leftText, row)
	left.Size = UDim2.new(0.5, -3, 1, 0)
	local right = styledButton("plain", rightText, row)
	right.Size = UDim2.new(0.5, -3, 1, 0)
	right.Position = UDim2.new(0.5, 3, 0, 0)
	return left, right
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

local EspTab = makeTab("ESP", true)
addSection(EspTab, "Highlights")
addToggle(EspTab, "Players", "PlayerESP", syncESP)
addToggle(EspTab, "Entities", "EntityESP", syncESP)
addToggle(EspTab, "Items", "ItemESP", syncESP)
addSection(EspTab, "Warning")
addToggle(EspTab, "Entity Alert", "EntityAlert", updateAlert)
addSlider(EspTab, "Alert range", "AlertRange", "m")

local EntitiesTab = makeTab("Entities", false)
addSlider(EntitiesTab, "Teleport distance", "TpDistance", "m")
local TeleportButton, ReturnButton = addButtonPair(EntitiesTab, "Teleport", "Return")
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
	Size = UDim2.new(1, 0, 1, -118),
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
	if ActiveTab ~= "Entities" or not Window.Visible then
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
		row.Dist.Text = string.format("%dm", math.floor(entry.Distance))
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

track(UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.RightShift then
		toggleWindow()
	end
end))

RunService:BindToRenderStep(RENDER_NAME, Enum.RenderPriority.Last.Value, applyEnvironment)
RunService:BindToRenderStep(SWAY_GUARD_NAME, Enum.RenderPriority.Camera.Value - 1, guardCameraOffset)
RunService:BindToRenderStep(SWAY_FIX_NAME, Enum.RenderPriority.Last.Value + 1000, stabilizeCamera)

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
end))

track(RunService.Stepped:Connect(function()
	if State.Noclip then
		stepNoclip()
	end
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
loop(0.15, function()
	updateLabels()
	updateAlert()
end)

local function unload()
	if not Running then
		return
	end
	Running = false
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
	if Saved[key] == true and type(State[key]) == "boolean" then
		setToggle(key, true)
	end
end

notify("Backrooms loaded")
