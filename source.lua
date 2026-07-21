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

-- === КАСТОМНАЯ ТЕМА UI ===
_G.CustomTheme = {
    Tab_Color = Color3.fromRGB(31, 32, 33),
    Tab_Text_Color = Color3.fromRGB(255, 255, 255),
    Description_Color = Color3.fromRGB(31, 32, 33),
    Description_Text_Color = Color3.fromRGB(0, 240, 200),
    Container_Color = Color3.fromRGB(25, 10, 40),
    Container_Text_Color = Color3.fromRGB(255, 255, 255),
    Button_Text_Color = Color3.fromRGB(255, 255, 255),
    Toggle_Box_Color = Color3.fromRGB(35, 15, 55),
    Toggle_Inner_Color = Color3.fromRGB(0, 240, 200),
    Toggle_Text_Color = Color3.fromRGB(255, 255, 255),
    Toggle_Border_Color = Color3.fromRGB(140, 50, 255),
    Slider_Bar_Color = Color3.fromRGB(35, 15, 55),
    Slider_Inner_Color = Color3.fromRGB(0, 240, 200),
    Slider_Text_Color = Color3.fromRGB(255, 255, 255),
    Slider_Border_Color = Color3.fromRGB(140, 50, 255),
    Dropdown_Text_Color = Color3.fromRGB(255, 255, 255),
    Dropdown_Option_BorderSize = 1,
    Dropdown_Option_BorderColor = Color3.fromRGB(140, 50, 255),
    Dropdown_Option_Color = Color3.fromRGB(25, 10, 40),
    Dropdown_Option_Text_Color = Color3.fromRGB(255, 255, 255),
    TextBox_Text_Color = Color3.fromRGB(255, 255, 255),
    TextBox_Color = Color3.fromRGB(35, 15, 55),
    TextBox_Underline_Color = Color3.fromRGB(0, 240, 200)
}

-- === ЗАГРУЗКА БИБЛИОТЕКИ UI ===
local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/bro-pixel11/pixel-project/main/ui.lua"))()

local MainTab = Library:CreateTab("🪐", "Main Features", nil)
local SettingsTab = Library:CreateTab("⚙️", "Configuration", nil)

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

-- === СТАТИСТИКА (Эмуляция лейблов через TextBox/кнопки или текст) ===
-- Создаем информационные блоки в Main вкладке
MainTab:CreateTextBox("Status: Loading 282k dict...", function() end)

-- === ЗАГРУЗКА СЛОВАРЯ ===
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then return end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if word ~= "" then
                total = total + 1
                table.insert(globalWordsList, word)
                if total % 5000 == 0 then task.wait() end
            end
        end
        print("📚 Dictionary loaded: " .. total .. " words")
    end)
end

loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/fullwords/main/full_dict.txt")

-- === СЕТЕВЫЕ СОБЫТИЯ ===
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === UI КОМПОНЕНТЫ (MAIN TAB) ===
MainTab:CreateTextBox("Letter Cap (Max Length)", function(Text)
    lettercap = tonumber(Text) or math.huge
end)

MainTab:CreateToggle("Auto Search", function(Value)
    autosearch = Value
    if autosearch then
        task.spawn(function()
            while autosearch do task.wait(0.05); pcall(copyword) end
        end)
    end
end)

MainTab:CreateToggle("Auto Type (Mobile)", function(Value)
    autotype = Value
end)

MainTab:CreateToggle("Instant Type (No Delay)", function(Value)
    instanttype = Value
end)

MainTab:CreateToggle("Auto Join Game", function(Value)
    autojoin = Value
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

MainTab:CreateButton("Search Word (Manual)", function()
    copyword(true)
end)

MainTab:CreateButton("Clear Memory", function()
    sessionUsedWords = {}
end)

-- === UI КОМПОНЕНТЫ (SETTINGS TAB) ===
SettingsTab:CreateSlider("Auto Join Delay (sec)", 1, 5, function(Value)
    autoJoinDelay = Value
end)

SettingsTab:CreateSlider("Check Word Delay (x0.1s)", 1, 20, function(Value)
    checkWordDelay = Value / 10
end)

SettingsTab:CreateSlider("Typing WPM", 100, 1000, function(Value)
    typingWPM = Value
    speedWordDelay = 60 / (typingWPM * 5)
end)

SettingsTab:CreateToggle("Human Jittering", function(Value)
    jitterEnabled = Value
end)

SettingsTab:CreateSlider("Jitter Intensity", 1, 20, function(Value)
    jitterIntensity = Value / 100
end)

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
                if v:IsA("TextLabel") and v.Visible and v.Parent.Name ~= "uiui" then
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
        if v:IsA("TextBox") and v.Visible and v.Parent.Name ~= "uiui" then return v end
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

print("🚀 Bro-PixelScript успешно инициализирован с кастомным интерфейсом!")
