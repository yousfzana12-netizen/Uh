-- [context: Roblox Lua, executor, Windows x64 — صيد الضبّان]
-- ESP + Head redirect on manual fire — zero auto

local Players  = game:GetService("Players")
local UIS      = game:GetService("UserInputService")
local CoreGui  = game:GetService("CoreGui")
local WS       = game:GetService("Workspace")
local RS       = game:GetService("ReplicatedStorage")

local LP = Players.LocalPlayer
local Char, Root

local function RefreshChar()
    Char = LP.Character or LP.CharacterAdded:Wait()
    Root = Char:WaitForChild("HumanoidRootPart", 5)
end
RefreshChar()
LP.CharacterAdded:Connect(function() task.wait(1.5); RefreshChar() end)

-- remotes
local dhab  = RS:WaitForChild("Dhab", 15)
local Event = dhab:WaitForChild("Event", 10)

-- seed sync — server seeds track ours
local Seed = math.random(140000000, 160000000)
Event.OnClientEvent:Connect(function(action, data)
    if action == "Projectile" and typeof(data) == "table" and data.seed then
        Seed = data.seed - 104729  -- step forward past the shot we just tracked
    end
end)

-- ── TIER / COLOR ────────────────────────────────────────────────────────────
local TierRank = {T1=1,T2=2,T3=3,T4=4,T5=5,T6=6,T7=7,T8=8}
local TierColor = {
    T1=Color3.fromRGB(80,220,80),
    T2=Color3.fromRGB(80,150,255),
    T3=Color3.fromRGB(190,80,255),
    T4=Color3.fromRGB(255,145,0),
    T5=Color3.fromRGB(255,50,50),
    T6=Color3.fromRGB(255,220,0),
}

-- ── DABS ────────────────────────────────────────────────────────────────────
local function GetDabs()
    local wild = WS:FindFirstChild("DhabWild")
    if not wild then return {} end
    local out = {}
    for _, m in ipairs(wild:GetChildren()) do
        if m.ClassName == "Model" and m.Name:sub(1,5) == "Dhab_" then
            if tostring(m:GetAttribute("State")) ~= "death" then
                local tier  = tostring(m:GetAttribute("Tier") or "T1")
                local giant = m:GetAttribute("DhabGiant") == true
                local uid   = m:GetAttribute("Uid") or m.Name
                local bp    = m:FindFirstChild("HumanoidRootPart")
                           or m:FindFirstChild("Head")
                           or m:FindFirstChild("Hitbox")
                           or m.PrimaryPart
                           or m:FindFirstChildWhichIsA("BasePart")
                local rank  = (TierRank[tier] or 1) + (giant and 100 or 0)
                if bp then
                    table.insert(out, {model=m, bp=bp, uid=uid, tier=tier, rank=rank, giant=giant})
                end
            end
        end
    end
    return out
end

-- ── ESP ─────────────────────────────────────────────────────────────────────
local ESPOn    = false
local ESPCache = {}
local ESPConns = {}

local function KillBill(m)
    if ESPCache[m] then pcall(function() ESPCache[m]:Destroy() end); ESPCache[m] = nil end
end

local function ClearESP()
    for _, c in ipairs(ESPConns) do pcall(c.Disconnect, c) end
    ESPConns = {}
    for m in pairs(ESPCache) do KillBill(m) end
end

local function MakeBill(entry)
    local m, bp, tier, giant = entry.model, entry.bp, entry.tier, entry.giant
    if ESPCache[m] then return end
    local col = TierColor[tier] or Color3.fromRGB(200,200,200)
    if giant then col = Color3.fromRGB(255,60,60) end

    local bb = Instance.new("BillboardGui")
    bb.Size        = UDim2.new(0, 130, 0, 26)
    bb.StudsOffset = Vector3.new(0, 3.5, 0)
    bb.AlwaysOnTop = true
    bb.Parent      = bp

    local tl = Instance.new("TextLabel", bb)
    tl.Size                   = UDim2.new(1,0,1,0)
    tl.BackgroundTransparency = 1
    tl.Font                   = Enum.Font.GothamBold
    tl.TextSize               = 12
    tl.TextColor3             = col
    tl.TextStrokeTransparency = 0
    tl.Text = (giant and "👑 " or "") .. tier

    -- live distance update
    local conn = game:GetService("RunService").Heartbeat:Connect(function()
        if not Root or not bp or not bp.Parent then return end
        local dist = math.floor((Root.Position - bp.Position).Magnitude)
        tl.Text = (giant and "👑 " or "") .. tier .. "  " .. dist .. "m"
    end)
    table.insert(ESPConns, conn)

    ESPCache[m] = bb
    m.AncestryChanged:Connect(function()
        pcall(function() bb:Destroy() end)
        ESPCache[m] = nil
        conn:Disconnect()
    end)
end

local function RefreshESP()
    ClearESP()
    for _, e in ipairs(GetDabs()) do MakeBill(e) end
    local wild = WS:FindFirstChild("DhabWild")
    if wild then
        local c = wild.ChildAdded:Connect(function(m)
            if not ESPOn then return end
            task.wait(0.2)
            if m.ClassName == "Model" and m.Name:sub(1,5) == "Dhab_" then
                local tier  = tostring(m:GetAttribute("Tier") or "T1")
                local giant = m:GetAttribute("DhabGiant") == true
                local uid   = m:GetAttribute("Uid") or m.Name
                local bp    = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                local rank  = (TierRank[tier] or 1) + (giant and 100 or 0)
                if bp then MakeBill({model=m,bp=bp,uid=uid,tier=tier,rank=rank,giant=giant}) end
            end
        end)
        table.insert(ESPConns, c)
    end
end

-- ── HEAD REDIRECT ───────────────────────────────────────────────────────────
-- لما الاعب يضغط كليك يدوياً → نشوف أقرب ضب بالكروس هير → نضرب رأسه
local HeadOn = false

local function GetAimedDab()
    if not Root then return nil end
    local cam    = WS.CurrentCamera
    local origin = cam.CFrame.Position
    local look   = cam.CFrame.LookVector
    local best, bestScore = nil, math.huge
    for _, e in ipairs(GetDabs()) do
        local tPos    = e.bp.Position
        local dist    = (tPos - origin).Magnitude
        local toTgt   = (tPos - origin).Unit
        local dotVal  = toTgt:Dot(look)
        local angle   = math.acos(math.clamp(dotVal, -1, 1))
        -- within 40° cone and max 150 studs
        if angle < math.rad(40) and dist < 150 then
            local score = dist * (angle + 0.01)
            if score < bestScore then best = e; bestScore = score end
        end
    end
    return best
end

UIS.InputBegan:Connect(function(input, gpe)
    if not HeadOn then return end
    if gpe then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

    task.spawn(function()
        task.wait(0.03)  -- let the game fire its own Projectile first (seed sync)
        local target = GetAimedDab()
        if not target then return end

        local origin = Root.Position
        local tPos   = target.bp.Position
        local diff   = tPos - origin
        local hDist  = math.sqrt(diff.X^2 + diff.Z^2)
        local pitch  = math.atan2(-diff.Y, hDist)
        local dir    = diff.Unit
        local seed   = Seed
        Seed         = Seed - 104729

        -- send head hit right after the game's own shot
        pcall(function() Event:FireServer("Aim", {pitch=pitch, aiming=true}) end)
        task.wait(0.02)
        pcall(function()
            Event:FireServer("Projectile", {
                direction = dir, seed = seed,
                origin = origin, weapon = "nabbata"
            })
        end)
        task.wait(0.02)
        pcall(function()
            Event:FireServer("Hit", {
                uid = target.uid, zone = "head",
                weapon = "nabbata", seed = seed
            })
        end)
        pcall(function() Event:FireServer("Aim", {pitch=0, aiming=false}) end)
    end)
end)

-- ── GUI ─────────────────────────────────────────────────────────────────────
if CoreGui:FindFirstChild("DhabV5") then CoreGui.DhabV5:Destroy() end
local Gui = Instance.new("ScreenGui")
Gui.Name = "DhabV5"; Gui.ResetOnSpawn = false; Gui.Parent = CoreGui

local Main = Instance.new("Frame")
Main.Size             = UDim2.new(0, 190, 0, 0)
Main.AutomaticSize    = Enum.AutomaticSize.Y
Main.Position         = UDim2.new(0, 14, 0.5, -60)
Main.BackgroundColor3 = Color3.fromRGB(8, 8, 16)
Main.BorderSizePixel  = 0
Main.Parent           = Gui
Instance.new("UICorner", Main).CornerRadius = UDim.new(0, 10)

local pad = Instance.new("UIPadding", Main)
pad.PaddingLeft  = UDim.new(0,10); pad.PaddingRight  = UDim.new(0,10)
pad.PaddingTop   = UDim.new(0,10); pad.PaddingBottom = UDim.new(0,10)
Instance.new("UIListLayout", Main).Padding = UDim.new(0, 7)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1,0,0,18); title.BackgroundTransparency=1
title.Font=Enum.Font.GothamBold; title.TextSize=13
title.TextColor3=Color3.fromRGB(220,170,50); title.Text="🦎 DabHunt V5"
title.Parent=Main

local function Toggle(offTxt, onTxt, offCol, onCol, fn)
    local b = Instance.new("TextButton")
    b.Size=UDim2.new(1,0,0,32); b.BackgroundColor3=offCol
    b.Font=Enum.Font.GothamBold; b.TextSize=12
    b.TextColor3=Color3.fromRGB(255,255,255)
    b.Text=offTxt; b.AutoButtonColor=true; b.Parent=Main
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    local state = false
    b.MouseButton1Click:Connect(function()
        state = not state
        b.Text             = state and onTxt  or offTxt
        b.BackgroundColor3 = state and onCol  or offCol
        fn(state)
    end)
    return b
end

Toggle(
    "ESP   ⬜ OFF", "ESP   ✅ ON",
    Color3.fromRGB(35,35,55), Color3.fromRGB(25,120,55),
    function(on)
        ESPOn = on
        if on then RefreshESP() else ClearESP() end
    end
)

Toggle(
    "🎯 Head Hit   ⬜ OFF", "🎯 Head Hit   ✅ ON",
    Color3.fromRGB(35,35,55), Color3.fromRGB(140,30,10),
    function(on) HeadOn = on end
)

-- drag
do
    local drag, ox, oy = false, 0, 0
    Main.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag=true; ox=i.Position.X-Main.Position.X.Offset; oy=i.Position.Y-Main.Position.Y.Offset
        end
    end)
    Main.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
    UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            Main.Position=UDim2.new(0,i.Position.X-ox,0,i.Position.Y-oy)
        end
    end)
end

warn("[V5] ✅ ESP + Head Hit loaded")
