local RbxAnalytics = game:GetService("RbxAnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local userHWID = RbxAnalytics:GetClientId()
local KEYS_URL = "https://raw.githubusercontent.com/bro-pixel11/keys.json/main/auth.json"

local userProvidedKey = getgenv().PixelKey or _G.PixelKey or PixelKey

if not userProvidedKey or userProvidedKey == "" then
    Players.LocalPlayer:Kick("❌ Ошибка: Ключ не найден! Укажите getgenv().PixelKey = 'ВАШ_КЛЮЧ' перед loadstring.")
    return
end

local function authenticate()
    local success, response = pcall(function()
        return game:HttpGet(KEYS_URL)
    end)

    if not success or not response then
        return false, "Ошибка подключения к серверу авторизации!"
    end

    local ok, keysData = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not ok or type(keysData) ~= "table" then
        return false, "Ошибка чтения базы ключей!"
    end

    local registeredHWID = keysData[userProvidedKey]

    if not registeredHWID then
        return false, "Неверный ключ доступа!"
    end

    if type(registeredHWID) == "table" then
        for _, allowedHWID in ipairs(registeredHWID) do
            if allowedHWID == userHWID then
                return true, "Успешно!"
            end
        end
        return false, "Ваш HWID не найден в списке разрешённых!\nВаш HWID: " .. tostring(userHWID)
    end

    if registeredHWID == userHWID then
        return true, "Успешно!"
    end

    if registeredHWID == "UNASSIGNED" then
        return false, "Ключ не активирован. Ваш HWID:\n" .. tostring(userHWID)
    end

    return false, "Ключ привязан к другому HWID!\nВаш текущий HWID: " .. tostring(userHWID)
end

local isAuthenticated, authMessage = authenticate()

if not isAuthenticated then
    Players.LocalPlayer:Kick("🔒 [Bro-Pixel Auth]: " .. authMessage)
    error("[AUTH FAILED]: " .. authMessage)
    return
end

print("✅ Авторизация прошла успешно! Загрузка Bro-PixelScript...")

-- === ЗАГРУЗКА FLUENT UI ===
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/SaveManager.lua"))()
local InterfaceManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/dawid-scripts/Fluent/master/Addons/InterfaceManager.lua"))()

local Window = Fluent:CreateWindow({
    Title = "Bro-PixelScript (Word Bomb)",
    SubTitle = "by Bro-Pixel",
    TabWidth = 160,
    Size = UDim2.fromOffset(580, 460),
    Acrylic = true,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl
})

local Tabs = {
    Main = Window:AddTab({ Title = "Main", Icon = "home" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

local Options = Fluent.Options

-- === СОСТОЯНИЕ И НАСТРОЙКИ ===
local globalWordsList = {} 
local sessionUsedWords = {}
local lettercap = math.huge
local autosearch = false
local autotype = false
local instanttype = false
local autojoin = false
local autoJoinDelay = 2 
local jitterEnabled = false 
local jitterIntensity = 0.05 
local lastChunk = ""
local lastTypeTime = 0
local wasMyTurn = false
local isTyping = false 

local checkWordDelay = 1.0 
local startTime = os.time()
local totalTurns = 0

local typingWPM = 500
local speedWordDelay = 60 / (typingWPM * 5)

local Vim = game:GetService("VirtualInputManager")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- === СТАТУС / ПАРАГРАФ ДЛЯ СЛОВАРЯ ===
local StatusParagraph = Tabs.Main:AddParagraph({
    Title = "Dictionary Status",
    Content = "⏳ Loading 282k dictionary..."
})

-- === ЗАГРУЗКА СЛОВАРЯ ===
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            StatusParagraph:SetDesc("❌ Failed to load dictionary!")
            return 
        end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if word ~= "" then
                total = total + 1
                table.insert(globalWordsList, word)
                if total % 5000 == 0 then task.wait() end
            end
        end
        StatusParagraph:SetDesc("📚 Dictionary loaded: " .. total .. " words (Ready)")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/fullwords/main/full_dict.txt")

-- === СЕТЕВЫЕ СОБЫТИЯ ===
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === UI ЭЛЕМЕНТЫ (MAIN TAB) ===
Tabs.Main:AddInput("LetterCapInput", {
    Title = "Letter Cap",
    Description = "Max letter count for words (leave high if none)",
    Default = "",
    Placeholder = "Enter max length...",
    Numeric = true,
    Finished = false,
    Callback = function(Value)
        lettercap = tonumber(Value) or math.huge
    end
})

Tabs.Main:AddToggle("AutoSearch", {
    Title = "Auto Search",
    Default = false
}):OnChanged(function()
    autosearch = Options.AutoSearch.Value
    if autosearch then
        task.spawn(function()
            while autosearch do task.wait(0.05); pcall(copyword) end
        end)
    end
end)

Tabs.Main:AddToggle("AutoType", {
    Title = "Auto Type (Mobile)",
    Default = false
}):OnChanged(function()
    autotype = Options.AutoType.Value
end)

Tabs.Main:AddToggle("InstantType", {
    Title = "⚡ Instant Type (No Delay)",
    Default = false
}):OnChanged(function()
    instanttype = Options.InstantType.Value
end)

Tabs.Main:AddToggle("AutoJoin", {
    Title = "🚪 Auto Join Game",
    Default = false
}):OnChanged(function()
    autojoin = Options.AutoJoin.Value
    if autojoin and Games then
        task.spawn(function()
            if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
            sessionUsedWords = {} 
            pcall(function()
                for i = -1, -20, -1 do 
                    Games.GameEvent:FireServer(i, "JoinGame") 
                end
            end)
        end)
    end
end)

Tabs.Main:AddButton({
    Title = "🔥 Search Word (Manual)",
    Description = "Forces a manual word search",
    Callback = function()
        copyword(true)
    end
})

Tabs.Main:AddButton({
    Title = "🗑️ Clear Memory",
    Description = "Clears session used words history",
    Callback = function()
        sessionUsedWords = {}
        Fluent:Notify({ Title = "Memory", Content = "Session words cleared!", Duration = 3 })
    end
})

-- === UI ЭЛЕМЕНТЫ (SETTINGS TAB) ===
Tabs.Settings:AddSlider("AutoJoinDelaySlider", {
    Title = "Auto Join Delay",
    Description = "Delay before joining a game",
    Default = 2,
    Min = 1,
    Max = 5,
    Rounding = 0,
    Callback = function(Value)
        autoJoinDelay = Value
    end
})

Tabs.Settings:AddSlider("CheckWordDelaySlider", {
    Title = "Check Word Delay",
    Description = "Delay before typing starts",
    Default = 1.0,
    Min = 0.1,
    Max = 2.0,
    Rounding = 1,
    Callback = function(Value)
        checkWordDelay = Value
    end
})

Tabs.Settings:AddSlider("TypingWPMSlider", {
    Title = "Typing WPM",
    Description = "Words Per Minute speed",
    Default = 500,
    Min = 100,
    Max = 1000,
    Rounding = 0,
    Callback = function(Value)
        typingWPM = Value
        speedWordDelay = 60 / (typingWPM * 5)
    end
})

Tabs.Settings:AddToggle("HumanJitter", {
    Title = "Human Jittering",
    Description = "Slight realistic delay fluctuations",
    Default = false
}):OnChanged(function()
    jitterEnabled = Options.HumanJitter.Value
end)

Tabs.Settings:AddSlider("JitterIntensitySlider", {
    Title = "Jitter Strength",
    Description = "Intensity of delay fluctuations",
    Default = 0.05,
    Min = 0.01,
    Max = 0.2,
    Rounding = 2,
    Callback = function(Value)
        jitterIntensity = Value
    end
})

-- === ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ИГРЫ ===
local function getChunk()
    for _, v in pairs(getgc(true)) do
        if type(v) == "function" then
            local info = debug.getinfo(v)
            if info and info.name == "updateInfoFrame" then
                for _, up in pairs(debug.getupvalues(v)) do
                    if type(up) == "table" and up.Prompt then return tostring(up.Prompt):lower() end
                end
            end
        end
    end
    return nil
end

local function getGameStatus()
    local prompt = getChunk()
    if not prompt then return nil, false end
    local isMyTurn = false
    local localPlayer = Players.LocalPlayer
    if localPlayer then
        local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
        if playerGui then
            for _, v in pairs(playerGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and v.Parent.Name ~= "Fluent" then
                    local text = v.Text:lower()
                    if string.find(text, "quick") or string.find(text, "быстро") or string.find(text, "your turn") or string.find(text, "ходи") then
                        isMyTurn = true
                        break
                    end
                end
            end
        end
    end
    return prompt, isMyTurn
end

local function getGameTextBox()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return nil end
    local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
    if not playerGui then return nil end
    for _, v in pairs(playerGui:GetDescendants()) do
        if v:IsA("TextBox") and v.Visible and v.Parent.Name ~= "Fluent" then return v end
    end
    return nil
end

-- === ЛОГИКА ВВОДА СЛОВ ===
local function typeWordMobile(word, targetPrompt)
    if isTyping then return end 
    isTyping = true 
    
    if not instanttype and checkWordDelay > 0 then task.wait(checkWordDelay) end
    
    local currentPrompt, isMyTurn = getGameStatus()
    if currentPrompt ~= targetPrompt or not isMyTurn then
        isTyping = false
        return
    end
    
    local textBox = getGameTextBox()
    if textBox then 
        textBox:CaptureFocus() 
        task.wait(0.01)
        textBox.Text = "" 
        task.wait(0.01)
    end
    
    for i = 1, #word do
        local checkPrompt, checkTurn = getGameStatus()
        if checkPrompt ~= targetPrompt or not checkTurn then break end
        
        local char = string.sub(word, i, i)
        local keyCode = nil
        
        if char == "-" then keyCode = Enum.KeyCode.Minus
        elseif char == "'" then keyCode = Enum.KeyCode.Quote
        else keyCode = Enum.KeyCode[char:upper()] end
        
        if keyCode then
            local currentDelay = speedWordDelay
            if instanttype then currentDelay = 0
            elseif jitterEnabled then
                local randomOffset = (math.random() * 2 - 1) * jitterIntensity
                currentDelay = speedWordDelay + randomOffset
                if currentDelay < 0.005 then currentDelay = 0.005 end
            end
            
            if i == 1 and textBox and textBox.Text ~= "" then textBox.Text = "" end
            
            Vim:SendKeyEvent(true, keyCode, false, game)
            if currentDelay > 0 then task.wait(currentDelay / 2) end
            Vim:SendKeyEvent(false, keyCode, false, game)
            if currentDelay > 0 then task.wait(currentDelay / 2) end
        end
    end
    
    local finalPrompt, finalTurn = getGameStatus()
    if finalPrompt == targetPrompt and finalTurn then
        if not instanttype then task.wait(0.02) end
        Vim:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
        if not instanttype then task.wait(0.01) end
        Vim:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
        totalTurns = totalTurns + 1
    else
        if textBox then textBox.Text = "" end
    end
    
    isTyping = false 
end

function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()
    if not contains then 
        lastChunk = "" 
        wasMyTurn = false
        return 
    end

    local turnSwitchedToMe = (isMyTurn and not wasMyTurn)
    wasMyTurn = isMyTurn

    local currentTime = os.clock()
    if currentTime - lastTypeTime > 4 then lastChunk = "" end

    if lastChunk ~= contains or bruteforce or turnSwitchedToMe then
        lastChunk = contains
        lastTypeTime = currentTime

        local promptLower = contains:lower()
        local specialMatches = {}
        local normalMatches = {}
        
        for i = 1, #globalWordsList do
            local candidate = globalWordsList[i]
            if string.find(candidate, promptLower, 1, true) then
                if not sessionUsedWords[candidate] and #candidate <= lettercap then
                    if string.find(candidate, "-", 1, true) or string.find(candidate, "'", 1, true) then
                        table.insert(specialMatches, candidate)
                    else
                        table.insert(normalMatches, candidate)
                    end
                end
            end
        end

        local finalword = nil
        if #specialMatches > 0 then
            finalword = specialMatches[math.random(1, #specialMatches)]
        elseif #normalMatches > 0 then
            local shortestNormal = normalMatches[1]
            for i = 2, #normalMatches do
                if #normalMatches[i] < #shortestNormal then shortestNormal = normalMatches[i] end
            end
            finalword = shortestNormal
        end

        if finalword then
            sessionUsedWords[finalword] = true
            if autotype and isMyTurn then
                task.spawn(function() typeWordMobile(finalword, promptLower) end)
                lastChunk = "" 
            end
        end
    end
end

-- === АВТО-ПРИСОЕДИНЕНИЕ ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            if autojoin then 
                task.spawn(function()
                    if autoJoinDelay > 0 then task.wait(autoJoinDelay) end
                    pcall(function() 
                        Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                        sessionUsedWords = {}
                    end)
                end)
            end
        end)
    end
end

-- === ANTI-DUPE ===
task.spawn(function()
    while task.wait(0.3) do
        local localPlayer = Players.LocalPlayer
        local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
        local gameGui = playerGui and (playerGui:FindFirstChild("GameUI") or playerGui:FindFirstChild("DesktopUI") or playerGui:FindFirstChild("MobileUI"))
        
        if gameGui then
            for _, v in pairs(gameGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and #v.Text >= 2 then
                    local text = v.Text:gsub("%s+", "")
                    if text == text:upper() and not text:find("%d") and not text:find("TURN") and not text:find("ХОД") then
                        local lowerWord = text:lower()
                        if not sessionUsedWords[lowerWord] then
                            sessionUsedWords[lowerWord] = true
                        end
                    end
                end
            end
        end
    end
end)

-- Настройка менеджеров сохранения/интерфейса Fluent
SaveManager:SetLibrary(Fluent)
InterfaceManager:SetLibrary(Fluent)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({})
InterfaceManager:SetFolder("BroPixelScript")
SaveManager:SetFolder("BroPixelScript/wordbomb")

InterfaceManager:BuildInterfaceSection(Tabs.Settings)
SaveManager:BuildConfigSection(Tabs.Settings)

Window:SelectTab(1)

Fluent:Notify({
    Title = "Bro-PixelScript",
    Content = "Successfully loaded with Fluent UI!",
    Duration = 5
})

SaveManager:LoadAutoloadConfig()
