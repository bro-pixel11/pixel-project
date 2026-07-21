--[[
    Bro-PixelScript (wordbomb) - Rayfield Colorful Edition
    [DICTIONARY: 282k full_dict.txt Only | STRATEGY: Special Characters (Random) -> Shortest Word]
    (UPDATED: Auto Join, Anti-Dupe Stealer, Async Dictionary Load & Custom Search Logic)
]]

getgenv().deletewhendupefound = true

-- Загрузка Rayfield UI
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-- Создание сочного цветного окна
local Window = Rayfield:CreateWindow({
   Name = "🎨 Bro-PixelScript (wordbomb) 🎨",
   LoadingTitle = "⚡ Bro-Pixel Loader ⚡",
   LoadingSubtitle = "by Bro-Pixel",
   Theme = "CustomTheme", 

   DisableRayfieldPrompts = false,
   DisableBuildWarnings = false,

   ConfigurationSaving = { Enabled = false },
   KeySystem = false,
   Size = UDim2.fromOffset(340, 280),
   
   CustomTheme = {
        TextColor = Color3.fromRGB(255, 255, 255),
        Background = Color3.fromRGB(25, 10, 40),        
        MainColor = Color3.fromRGB(90, 30, 180),       
        AccentColor = Color3.fromRGB(0, 240, 200),       
        OutlineColor = Color3.fromRGB(140, 50, 255),    
        PlaceholderColor = Color3.fromRGB(180, 150, 220)
   }
})

-- Создание вкладок
local MainTab = Window:CreateTab("🪐 Main", nil)
local SettingsTab = Window:CreateTab("⚙️ Settings", nil)

local statusLabel = MainTab:CreateLabel("⏳ Loading and indexing 282k dictionary...")

-- Основная база слов
local globalWordsList = {} 

-- === АСИНХРОННАЯ ЗАГРУЗКА СЛОВАРЯ (БЕЗ ЗАВИСАНИЙ UI) ===
local function loadDictionaryAsync(url)
    task.spawn(function()
        local success, raw = pcall(function() return game:HttpGet(url) end)
        if not success or not raw then 
            statusLabel:Set("❌ Failed to load dictionary!")
            return 
        end
        
        local total = 0
        for word in raw:gmatch("[^\r\n]+") do
            word = word:gsub("%s+", ""):lower()
            if word ~= "" then
                total = total + 1
                table.insert(globalWordsList, word)
                
                -- Раз в 5000 слов даем кадру обновиться, чтобы не вешать клиент
                if total % 5000 == 0 then
                    task.wait()
                end
            end
        end
        statusLabel:Set("📚 Dictionary: " .. total .. " words (Ready)")
    end)
end

-- Запускаем загрузку словаря асинхронно
loadDictionaryAsync("https://raw.githubusercontent.com/bro-pixel11/fullwords/main/full_dict.txt")

-- === STATE & SETTINGS ===
local sessionUsedWords = {}
local lettercap = math.huge
local autosearch = false
local autotype = false
local instanttype = false
local autojoin = false
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
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- === ИНИЦИАЛИЗАЦИЯ СЕТЕВЫХ СОБЫТИЙ ДЛЯ AUTO JOIN ===
local Games = ReplicatedStorage:WaitForChild("Network", 10)
if Games then Games = Games:WaitForChild("Games", 10) end

-- === UI ELEMENTS (MAIN TAB) ===
MainTab:CreateInput({
   Name = "Letter Cap",
   PlaceholderText = "Enter max letter count...",
   Callback = function(Text) lettercap = tonumber(Text) or math.huge end,
})

MainTab:CreateToggle({
   Name = "Auto Search",
   CurrentValue = false,
   Callback = function(Value)
      autosearch = Value
      if autosearch then
          task.spawn(function()
              while autosearch do task.wait(0.05); pcall(copyword) end
          end)
      end
   end,
})

MainTab:CreateToggle({ 
    Name = "Auto Type (Mobile)", 
    CurrentValue = false, 
    Callback = function(Value) autotype = Value end 
})

MainTab:CreateToggle({ 
    Name = "⚡ Instant Type (No Delay) ⚡", 
    CurrentValue = false, 
    Callback = function(Value) instanttype = Value end 
})

MainTab:CreateToggle({
    Name = "🚪 Auto Join Game 🚪",
    CurrentValue = false,
    Callback = function(Value)
        autojoin = Value
        if autojoin and Games then
            pcall(function()
                for i = -1, -20, -1 do 
                    Games.GameEvent:FireServer(i, "JoinGame") 
                end
            end)
        end
    end
})

MainTab:CreateButton({ 
    Name = "🔥 Search Word (Manual) 🔥", 
    Callback = function() copyword(true) end 
})

MainTab:CreateButton({ 
    Name = "🗑️ Clear Memory", 
    Callback = function() sessionUsedWords = {}; matchLabel:Set("Current Match: Cleared") end 
})

-- === UI ELEMENTS (SETTINGS TAB) ===
SettingsTab:CreateSlider({
   Name = "Check Word Delay",
   Info = "Delay before typing (0.1s to 2.0s)",
   Range = {1, 20}, 
   Increment = 1,
   Suffix = " (x0.1 sec)",
   CurrentValue = 10, 
   Callback = function(Value) checkWordDelay = Value / 10 end,
})

SettingsTab:CreateSlider({
   Name = "Typing WPM",
   Info = "Words Per Minute speed",
   Range = {100, 1000},
   Increment = 50,
   Suffix = " WPM",
   CurrentValue = 500,
   Callback = function(Value)
      typingWPM = Value
      speedWordDelay = 60 / (typingWPM * 5)
   end,
})

SettingsTab:CreateToggle({
   Name = "Human Jittering",
   CurrentValue = false,
   Info = "Slight realistic delay fluctuations",
   Callback = function(Value) jitterEnabled = Value end,
})

SettingsTab:CreateSlider({
   Name = "Jitter Delay",
   Info = "Jittering strength",
   Range = {1, 20}, 
   Increment = 1,
   Suffix = " ms", 
   CurrentValue = 5, 
   Callback = function(Value) jitterIntensity = Value / 100 end,
})

-- === STATS PANEL ===
local StatsSection = MainTab:CreateSection("📊 Statistics 📊")
local elapsedLabel = MainTab:CreateLabel("Elapsed Time: 00:00:00")
local turnsLabel = MainTab:CreateLabel("Total Turns: 0")
local promptLabel = MainTab:CreateLabel("Current Prompt: None")
local solutionsLabel = MainTab:CreateLabel("Solutions Found: 0")
local matchLabel = MainTab:CreateLabel("Current Match: None")
MainTab:CreateSection("------------------")

-- === HELPERS ===
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
                if v:IsA("TextLabel") and v.Visible and v.Parent.Name ~= "Rayfield" then
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
        if v:IsA("TextBox") and v.Visible and v.Parent.Name ~= "Rayfield" then return v end
    end
    return nil
end

-- === TYPING LOGIC ===
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
        
        if char == "-" then
            keyCode = Enum.KeyCode.Minus
        elseif char == "'" then
            keyCode = Enum.KeyCode.Quote
        else
            keyCode = Enum.KeyCode[char:upper()]
        end
        
        if keyCode then
            local currentDelay = speedWordDelay
            
            if instanttype then
                currentDelay = 0
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
        if not instanttype then task.wait(0.03) end
        totalTurns = totalTurns + 1
        turnsLabel:Set("Total Turns: " .. totalTurns)
    else
        if textBox then textBox.Text = "" end
    end
    
    isTyping = false 
end

-- === МОДИФИЦИРОВАННАЯ ЛОГИКА ПОИСКА (ДЕФИС / АПОСТРОФ [РАНДОМ] -> МИН. ДЛИНА) ===
function copyword(bruteforce)
    if isTyping then return end
    local contains, isMyTurn = getGameStatus()
    
    if not contains then 
        lastChunk = "" 
        wasMyTurn = false
        promptLabel:Set("Current Prompt: None")
        solutionsLabel:Set("Solutions Found: 0")
        matchLabel:Set("Current Match: None")
        return 
    end

    local turnSwitchedToMe = (isMyTurn and not wasMyTurn)
    wasMyTurn = isMyTurn

    local currentTime = os.clock()
    if currentTime - lastTypeTime > 4 then lastChunk = "" end

    if lastChunk ~= contains or bruteforce or turnSwitchedToMe then
        lastChunk = contains
        lastTypeTime = currentTime
        promptLabel:Set("Current Prompt: " .. contains:upper())

        local promptLower = contains:lower()
        local specialMatches = {}
        local normalMatches = {}
        
        -- Сканируем единый большой словарь и разделяем на две группы
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

        solutionsLabel:Set("Solutions Found: " .. (#specialMatches + #normalMatches))

        local finalword = nil
        
        -- Приоритет №1: Если есть спец-слова, выбираем РАНДОМНОЕ из них
        if #specialMatches > 0 then
            finalword = specialMatches[math.random(1, #specialMatches)]
        -- Приоритет №2: Если спец-слов нет, выбираем САМОЕ КОРОТКОЕ из обычных
        elseif #normalMatches > 0 then
            local shortestNormal = normalMatches[1]
            for i = 2, #normalMatches do
                if #normalMatches[i] < #shortestNormal then
                    shortestNormal = normalMatches[i]
                end
            end
            finalword = shortestNormal
        end

        if finalword then
            sessionUsedWords[finalword] = true
            matchLabel:Set("Current Match: " .. finalword:upper())
            
            if autotype and isMyTurn then
                task.spawn(function()
                    typeWordMobile(finalword, promptLower)
                end)
                lastChunk = "" 
            end
        else
            matchLabel:Set("Current Match: Not Found")
        end
    end
end

-- === ФОНОВЫЙ ПОТОК ДЛЯ ПОДКЛЮЧЕНИЯ AUTO JOIN ===
if Games then
    local registerGame = Games:FindFirstChild("RegisterGame")
    if registerGame then
        registerGame.OnClientEvent:Connect(function(gameRoomID)
            if autojoin then 
                pcall(function() 
                    Games.GameEvent:FireServer(gameRoomID, "JoinGame") 
                    print("🚪 [Auto-Join]: Успешно зашли в комнату катки:", gameRoomID)
                end)
            end
        end)
    end
end

-- === ОПТИМИЗИРОВАННЫЙ СТИЛЕР ЧУЖИХ ОТВЕТОВ (ANTI-DUPE) ===
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
                            print("🔥 [Anti-Dupe]: " .. lowerWord)
                        end
                    end
                end
            end
        end
    end
end)

-- === TIMER LOOP ===
task.spawn(function()
    while task.wait(1) do
        local elapsed = os.time() - startTime
        local hours = math.floor(elapsed / 3600)
        local minutes = math.floor((elapsed % 3600) / 60)
        local seconds = elapsed % 60
        elapsedLabel:Set(string.format("Elapsed Time: %02d:%02d:%02d", hours, minutes, seconds))
    end
end)
