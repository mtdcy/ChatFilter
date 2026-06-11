-- 兼容函数
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

local ChatFilter = {
    version = GetAddOnMetadata("ChatFilter", "Version"),
    keywords = {},
    frame = nil,
    scrollFrame = nil,
    content = nil,
    autoScroll = true,
    maxLines = 100,  -- 最大显示行数
    lastMessages = {},  -- 用于存储每个发言者的最后一条消息
    enabled = false,  -- 总开关状态
    debugMode = true,  -- 调试模式
   
    -- Buttons
    minButton = nil,
    clearButton = nil,
    soundButton = nil, -- 声音复选框
    lockButton = nil,
    latestButton = nil,
    resizeButton = nil,
}

-- 职业颜色映射
local CLASS_COLORS = {
    ["DEATHKNIGHT"] = {0.77, 0.12, 0.23},
    ["DEMONHUNTER"] = {0.64, 0.19, 0.79},
    ["DRUID"] = {1.00, 0.49, 0.04},
    ["HUNTER"] = {0.67, 0.83, 0.45},
    ["MAGE"] = {0.41, 0.80, 0.94},
    ["MONK"] = {0.00, 1.00, 0.59},
    ["PALADIN"] = {0.96, 0.55, 0.73},
    ["PRIEST"] = {1.00, 1.00, 1.00},
    ["ROGUE"] = {1.00, 0.96, 0.41},
    ["SHAMAN"] = {0.00, 0.44, 0.87},
    ["WARLOCK"] = {0.58, 0.51, 0.79},
    ["WARRIOR"] = {0.78, 0.61, 0.43},
}

-- 字符串
local titleText = "聊天过滤 v" .. ChatFilter.version .. ", 左键密语，右键拷贝消息，命令 /cf"

-- 调试打印函数
local function Print(message)
    SELECTED_CHAT_FRAME:AddMessage(message, 0.7, 0.7, 0)
end

-- 初始化过滤框体: 此时 ChatFilterDB 并未加载
function ChatFilter:Init()
    if self.frame then return end

    -- 主框体
    self.frame = CreateFrame("Frame", "ChatFilterFrame", UIParent, "BasicFrameTemplateWithInset")
    self.frame:SetSize(400, 500)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", function()
        ChatFilter:OnFrameMoved()
    end)

    -- 标题
    self.frame.title = self.frame:CreateFontString(nil, "OVERLAY")
    self.frame.title:SetFontObject("GameFontHighlight")
    self.frame.title:SetPoint("LEFT", self.frame.TitleBg, "LEFT", 5, 0)
    self.frame.title:SetText(titleText)

    -- 关闭按钮
    self.frame.CloseButton:SetScript("OnClick", function()
        self:OnFrameClosed()
        self.frame:Hide()
    end)

    -- 滚动框体
    self.scrollFrame = CreateFrame("ScrollFrame", nil, self.frame)
    self.scrollFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 8, -30)
    self.scrollFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 28)

    -- 内容框体
    self.content = CreateFrame("Frame", nil, self.scrollFrame)
    self.content:SetSize(self.scrollFrame:GetWidth(), 1) -- 初始高度为1
    self.scrollFrame:SetScrollChild(self.content)

    self.content:SetScript("OnSizeChanged", function(_, width, height)
    end)

    -- 滚动事件
    self.scrollFrame:EnableMouseWheel(true)
    self.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local max = self:GetVerticalScrollRange()
        local new = current - (delta * 20)
        new = math.max(0, math.min(new, max))
        self:SetVerticalScroll(new)
        ChatFilter:UpdateScrollState()
    end)

    -- "最小化"按钮
    self.minButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.minButton:SetSize(22, 22)
    self.minButton:SetPoint("BOTTOMLEFT", self.frame, "BOTTOMLEFT", 8, 4)
    self.minButton:SetScript("OnClick", function()
        ChatFilter:OnFrameMinimized()
    end)

    -- "清除所有记录"按钮
    self.clearButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.clearButton:SetText("清除记录")
    self.clearButton:SetSize(self.clearButton:GetTextWidth() + 16, 22)
    self.clearButton:SetPoint("LEFT", self.minButton, "RIGHT", 8, 0)
    self.clearButton:SetScript("OnClick", function()
        ChatFilter:ClearAllRecords()
    end)

    -- "暂停"按钮
    self.pauseButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.pauseButton:SetText("暂停")
    self.pauseButton:SetSize(self.pauseButton:GetTextWidth() + 16, 22)
    self.pauseButton:SetPoint("LEFT", self.clearButton, "RIGHT", 8, 0)
    self.pauseButton:SetScript("OnClick", function()
        ChatFilter:OnFilterPaused()
    end)

    -- "声音"按钮
    self.soundButton = CreateFrame("CheckButton", nil, self.frame, "InterfaceOptionsCheckButtonTemplate")
    self.soundButton.text:SetText("声音")
    self.soundButton:SetPoint("LEFT", self.pauseButton, "RIGHT", 8, 0)
    self.soundButton:SetScript("OnClick", function()
        ChatFilter:ToggleSound()
    end)
    
    -- "锁定"按钮
    self.lockButton = CreateFrame("CheckButton", nil, self.frame, "InterfaceOptionsCheckButtonTemplate")
    self.lockButton.text:SetText("锁定")
    self.lockButton:SetPoint("LEFT", self.soundButton, "RIGHT", self.soundButton.text:GetWidth() + 8, 0)
    self.lockButton:SetScript("OnClick", function()
        ChatFilter:ToggleLocked()
    end)

    -- "跳转到最新"按钮
    self.latestButton = CreateFrame("Button", nil, self.frame, "UIPanelButtonTemplate")
    self.latestButton:SetText("跳转到最新")
    self.latestButton:SetSize(self.latestButton:GetTextWidth() + 16, 22)
    self.latestButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -8, 4)
    self.latestButton:SetScript("OnClick", function()
        ChatFilter:ScrollToBottom()
    end)

    -- 缩放功能
    self.frame:SetResizable(true)
    self.frame:SetResizeBounds(300, 200, 800, 800)
    self.resizeButton = CreateFrame("Button", nil, self.frame)
    self.resizeButton:SetSize(16, 16)
    self.resizeButton:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", 0, 0)

    -- 添加贴图
    local texture = self.resizeButton:CreateTexture()
    texture:SetAllPoints()
    texture:SetTexture([[Interface\ChatFrame\UI-ChatIM-SizeGrabber-Up]])
    self.resizeButton:SetNormalTexture(texture)

    -- 缩放逻辑
    self.resizeButton:SetScript("OnMouseDown", function()
        -- 开始缩放：参数为 "BOTTOMRIGHT" 表示拖动右下角调整大小
        ChatFilter.frame:StartSizing("BOTTOMRIGHT")
    end)

    self.resizeButton:SetScript("OnMouseUp", function()
        -- 停止缩放
        ChatFilter.frame:StopMovingOrSizing()
    end)

    -- 监听窗口大小变化
    self.frame:SetScript("OnSizeChanged", function(_, width, height)
        self:OnSizeChanged()
    end)

    -- 美化：使用 ElvUI 材质
    if ElvUI then
        -- 获取 ElvUI 的皮肤模块 (Skins)
        local E, _ = unpack(ElvUI) -- 获取 ElvUI 的核心对象
        local S = E:GetModule('Skins')

        S:HandlePortraitFrame(self.frame)
        S:HandleNextPrevButton(self.minButton)
        S:HandleButton(self.clearButton)
        S:HandleButton(self.pauseButton)
        S:HandleCheckBox(self.soundButton)
        S:HandleCheckBox(self.lockButton)
        S:HandleButton(self.latestButton)

        self.minButton:SetTemplate("Transparent") -- 恢复最小化按钮的背景
        self.minButton:SetSize(22, 22) -- 修复按钮大小
    end

    self.frame:Hide()

    -- 注册事件
    self:RegisterEvents()
end

-- 完成插件加载
function ChatFilter:OnLoaded(addonName, ...)
    if addonName == "ChatFilter" then
        self:Init()

        -- 初始化数据库
        ChatFilterDB = ChatFilterDB or {}
        ChatFilterDB.recentMessages = ChatFilterDB.recentMessages or {}
        ChatFilterDB.locked = ChatFilterDB.locked or false
        ChatFilterDB.locked = ChatFilterDB.playSound or false

        -- 加载数据库
        self.enabled = ChatFilterDB.enabled or false
        self:LoadKeywords()

        -- 清理旧消息
        self:CleanOldMessages()

        -- 同步界面元素状态
        self.frame:SetMovable(true) -- 保证窗口能够移动到旧位置

        if self.enabled then
            self.frame:Show()
            self:RefreshFilteredMessages()
        end

        if ChatFilterDB.pos then
            self.frame:ClearAllPoints()
            self.frame:SetPoint(ChatFilterDB.pos.point, UIParent, ChatFilterDB.pos.point, ChatFilterDB.pos.x, ChatFilterDB.pos.y)
        end

        self.soundButton:SetChecked(ChatFilterDB.playSound)
        self.lockButton:SetChecked(ChatFilterDB.locked)
        self:ScrollToBottom()

        if ChatFilterDB.locked then
            self.resizeButton:Hide()
            self.frame:SetMovable(false)
        else
            self.frame:SetMovable(true)
        end

        Print("ChatFilter v" .. self.version .. " 已加载。")
    end
end

-- 加载关键词
function ChatFilter:LoadKeywords()
    if ChatFilterDB.keywords and #ChatFilterDB.keywords > 0 then
        self.keywords = ChatFilterDB.keywords
        Print("ChatFilter 已加载关键词")
    else
        -- 默认关键词
        self.keywords = {
            {{"MC", "风暴", "双龙"}, {"摸奖", "抽奖"}},
        }
        ChatFilterDB.keywords = self.keywords
        Print("ChatFilter 加载默认关键词")
    end
    self:ShowKeywordSets()
end

-- 更新窗口大小
function ChatFilter:OnSizeChanged()
    if self.resizeTimer then
        self.resizeTimer:Cancel()
    end

    self.resizeTimer = C_Timer.After(0.5, function()
        -- 手动调整 content 大小
        self.content:SetWidth(self.scrollFrame:GetWidth())

        -- 刷新消息显示
        local playSound = ChatFilterDB.playSound 
        ChatFilterDB.playSound = false      -- 临时关闭声音
        self:RefreshFilteredMessages()
        ChatFilterDB.playSound = playSound  -- 恢复声音
    end)
end

-- 更新 ScrollToBottom 函数
function ChatFilter:ScrollToBottom()
    C_Timer.After(0.05, function()
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange())
        self.autoScroll = true
        self:UpdateScrollState()
    end)
end

-- 更新 UpdateScrollState 函数
function ChatFilter:UpdateScrollState()
    local scrollFrame = self.scrollFrame
    local currentScroll = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    self.autoScroll = (currentScroll >= maxScroll - 1)

    if self.autoScroll then
        self.latestButton:Hide()
    else
        self.latestButton:Show()
    end
end

-- 新增: 清除所有记录的函数
function ChatFilter:ClearAllRecords()
    -- 清空内容框体
    for _, child in ipairs({self.content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    self.content:SetHeight(1)

    -- 重置最后消息记录
    self.lastMessages = {}

    -- 清空保存的消息
    ChatFilterDB.recentMessages = {}

    -- 更新滚动状态
    self:UpdateScrollState()

    -- 提示用户
    Print("ChatFilter 已清除所有记录。")
end

-- 处理聊天消息
function ChatFilter:OnChatMessage(event, message, sender, _, _, _, _, _, _, _, _, _, guid)
    if not self.enabled then return end

    -- 去除服务器名
    local senderName = string.match(sender, "(.-)%-")

    for _, keywordSet in ipairs(self.keywords) do
        if self:ContainsKeyword(message, keywordSet) then
            local class = guid and select(2, GetPlayerInfoByGUID(guid)) or (UnitExists(sender) and select(2, UnitClass(sender)))

            -- 只保留过滤后的消息，不然消息量太大
            table.insert(ChatFilterDB.recentMessages, 1, {
                event = event,
                message = message,
                sender = senderName or sender,
                class = class,
                time = time()
            })

            self:DisplayFilteredMessage(ChatFilterDB.recentMessages[1])
            break
        end
    end
end

-- 检查消息是否包含关键词
function ChatFilter:ContainsKeyword(message, keywordSet)
    message = string.lower(message)
    local setMatch = true
    for _, andGroup in ipairs(keywordSet) do
        local groupMatch = false
        for _, keyword in ipairs(andGroup) do
            if string.find(message, string.lower(keyword)) then
                groupMatch = true
                break
            end
        end
        if not groupMatch then
            setMatch = false
            break
        end
    end
    return setMatch
end

-- 显示过滤后的消息
function ChatFilter:DisplayFilteredMessage(messageInfo)
    if not self.frame or not self.frame:IsShown() or not self.content then 
        Print("Frame or content not available")
        return 
    end

    local message = messageInfo.message
    local sender = messageInfo.sender
    local class = messageInfo.class
    local time = messageInfo.time

    local timeText = date("%H:%M", time)

    -- 检查是否是重复消息
    if self.lastMessages[sender] then
        if self.lastMessages[sender].ignored then
            -- 不再更新被忽略的目标
            return
        elseif self.lastMessages[sender].message == message then
            -- 更新现有消息的时间戳
            self.lastMessages[sender].time = time
            self.lastMessages[sender].timeString:SetText(timeText)

            self:ReorderMessages()
            return
        else
            -- 如果是同一个发送者的不同消息，移除旧消息
            self.lastMessages[sender].line:Hide()
            self.lastMessages[sender].line:SetParent(nil)
            self.lastMessages[sender] = nil
        end
    end

    local line = CreateFrame("Frame", nil, self.content)
    line:SetWidth(self.content:GetWidth())
    line:SetHeight(20) -- 设置一个初始高度，稍后会根据实际内容调整

    local timeString = line:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeString:SetPoint("TOPLEFT", line, "TOPLEFT", 0, -4)
    timeString:SetText(timeText)
    timeString:SetTextColor(0.8, 0.8, 0.8)

    local fullMessage = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fullMessage:SetPoint("TOPLEFT", line, "TOPLEFT", timeString:GetWidth() + 4, -4)
    fullMessage:SetPoint("RIGHT", line, "RIGHT", 0, 0)
    fullMessage:SetJustifyH("LEFT")
    fullMessage:SetSpacing(2)

    local r, g, b = unpack(class and CLASS_COLORS[class] or {1, 1, 1})
    local coloredName = string.format("[|cFF%02X%02X%02X%s|r]", r*255, g*255, b*255, sender)

    local highlightedMessage = self:HighlightKeywords(message)

    fullMessage:SetText(coloredName .. ": |cFFFFFFFF" .. highlightedMessage .. "|r")

    -- 计算并设置行高
    fullMessage:SetWidth(line:GetWidth() - 60)
    local messageHeight = fullMessage:GetStringHeight() + 5
    line:SetHeight(messageHeight)

    -- 添加点击角色名称的功能
    local nameLength = fullMessage:GetStringWidth(coloredName)
    local nameButton = CreateFrame("Button", nil, line)
    nameButton:SetPoint("TOPLEFT", fullMessage, "TOPLEFT", 0, 0)
    nameButton:SetSize(nameLength, fullMessage:GetStringHeight())

    nameButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    nameButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            ChatFrame_OpenChat("/s " .. message)
        elseif IsShiftKeyDown() then
            -- Shift: 忽略指定目标
            self.lastMessages[sender].ignored = true
            -- 给时间标签做个标记
            self.lastMessages[sender].timeString:SetAlpha(0.4)
            self.lastMessages[sender].fullMessage:SetAlpha(0.4)
            Print("ChatFilter 已忽略目标：" .. sender)
        else
            ChatFrame_OpenChat("/w " .. sender .. " ")
        end
    end)

    self.lastMessages[sender] = {
        ignored = false,
        line = line,
        message = message,
        time = time,
        timeString = timeString,
        fullMessage = fullMessage,
    }

    self:ReorderMessages()

    if self.autoScroll then
        self:ScrollToBottom()
    end

    -- 播放音频提醒
    if ChatFilterDB.playSound then
        PlaySound(SOUNDKIT.TELL_MESSAGE)
    end
end

-- 添加一个新的命令来切换音频提醒
function ChatFilter:ToggleSound()
    ChatFilterDB.playSound = not ChatFilterDB.playSound

    if self.soundButton:GetChecked() ~= ChatFilterDB.playSound then
        self.soundButton:SetChecked(ChatFilterDB.playSound)
    end

    if ChatFilterDB.playSound then
        Print("ChatFilter 声音提醒已开启")
    else
        Print("ChatFilter 声音提醒已关闭")
    end
end

-- 添加新函数来重新排列消息
function ChatFilter:ReorderMessages()
    local messages = {}
    for _, msg in pairs(self.lastMessages) do
        table.insert(messages, msg)
    end

    -- 按时间降序排序，最新的消息在数组的开头
    table.sort(messages, function(a, b) return a.time > b.time end)

    local yOffset = 0
    for i, msg in ipairs(messages) do
        msg.line:ClearAllPoints()
        msg.line:SetPoint("BOTTOMLEFT", self.content, "BOTTOMLEFT", 0, yOffset)
        msg.line:SetPoint("RIGHT", self.content, "RIGHT")
        msg.line:Show()
        yOffset = yOffset + msg.line:GetHeight()
    end

    local contentHeight = yOffset
    self.content:SetHeight(math.max(contentHeight, self.scrollFrame:GetHeight()))

    -- 移除超过最大行数的旧消息
    while #messages > self.maxLines do
        local oldestMsg = table.remove(messages)
        oldestMsg.line:Hide()
        oldestMsg.line:SetParent(nil)
        for sender, msg in pairs(self.lastMessages) do
            if msg == oldestMsg then
                self.lastMessages[sender] = nil
                break
            end
        end
    end

    self:UpdateScrollPosition()
end

function ChatFilter:UpdateScrollPosition()
    local scrollFrame = self.scrollFrame
    local contentHeight = self.content:GetHeight()
    local frameHeight = scrollFrame:GetHeight()
    local maxScroll = math.max(contentHeight - frameHeight, 0)

    if self.autoScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    else
        local currentScroll = scrollFrame:GetVerticalScroll()
        scrollFrame:SetVerticalScroll(math.min(currentScroll, maxScroll))
    end
end

-- 高亮关键词
function ChatFilter:HighlightKeywords(message)
    local highlightedMessage = message
    for _, keywordSet in ipairs(self.keywords) do
        if self:ContainsKeyword(message, keywordSet) then
            for _, andGroup in ipairs(keywordSet) do
                for _, keyword in ipairs(andGroup) do
                    local pattern = keyword:gsub("(%a)", function(c) return "[" .. c:lower() .. c:upper() .. "]" end)
                    highlightedMessage = highlightedMessage:gsub(pattern, "|cFFFFFF00%1|r")
                end
            end
            break
        end
    end
    return highlightedMessage
end

-- 滚动到底部
function ChatFilter:ScrollToBottom()
    C_Timer.After(0.05, function()
        self.scrollFrame:SetVerticalScroll(self.scrollFrame:GetVerticalScrollRange())
        self.autoScroll = true
        self:UpdateScrollState()
    end)
end

-- 更新滚动状态
function ChatFilter:UpdateScrollState()
    if not self.scrollFrame then
        return
    end

    local currentScroll = self.scrollFrame:GetVerticalScroll()
    local maxScroll = math.max(self.content:GetHeight() - self.scrollFrame:GetHeight(), 0)
    self.autoScroll = (currentScroll >= maxScroll - 1)

    if self.autoScroll then
        self.latestButton:Hide()
    else
        self.latestButton:Show()
    end
end

-- 切换框体显示/隐藏的函数
function ChatFilter:ToggleFrame()
    if not self.frame then
        self:CreateFilterFrame()
    end

    self.enabled = not self.enabled
    ChatFilterDB.enabled = self.enabled
    if self.enabled then
        self.frame:Show()
        self:RefreshFilteredMessages()
        Print("ChatFilter 已启用")
    else
        self.frame:Hide()
        Print("ChatFilter 已禁用")
    end
end

-- 处理框体的关闭
function ChatFilter:OnFrameClosed()
    self.enabled = false
    ChatFilterDB.enabled = false
    Print("ChatFilter 已禁用")
end

-- 处理框体的位置
function ChatFilter:OnFrameMoved()
    self.frame:StopMovingOrSizing()

    local point, _, _, x, y = self.frame:GetPoint()
    ChatFilterDB.pos = { 
        point = point,
        x = x, 
        y = y,
    }
end

-- 处理暂停过滤消息
function ChatFilter:OnFilterPaused()
    if self.enabled then
        self.enabled = false
        self.pauseButton:SetText("继续")
        Print("ChatFilter 消息过滤已暂停")
    else
        self.enabled = true
        self.pauseButton:SetText("暂停")
        Print("ChatFilter 消息过滤已恢复")
    end
end

-- 处理窗口最小化
function ChatFilter:OnFrameMinimized()
    local texture = self.minButton:GetNormalTexture()
    if self.minButton:GetParent() == UIParent then 
        -- 恢复窗口
        if texture then 
            texture:SetRotation(math.rad(180))
        end
        self.enabled = ChatFilterDB.enabled -- 恢复原始状态
        self.frame:Show()
        self.minButton:SetParent(self.frame)
        Print("ChatFilter 已恢复")
    else
        -- 最小化
        if texture then
            texture:SetRotation(math.rad(0))
        end
        self.enabled = false -- 暂停处理消息
        self.minButton:SetParent(UIParent)
        self.frame:Hide()
        Print("ChatFilter 已隐藏")
    end
end

-- 锁定框架
function ChatFilter:ToggleLocked()
    ChatFilterDB.locked = not ChatFilterDB.locked

    if self.lockButton:GetChecked() ~= ChatFilterDB.locked then
        self.lockButton:SetChecked(ChatFilterDB.locked)
    end

    if ChatFilterDB.locked then
        if self.resizeTimer then
            self.resizeTimer:Cancel()
        end
        self.resizeButton:Hide()
        self.frame:SetMovable(false)
        Print("ChatFilter 已经锁定")
    else
        self.resizeButton:Show()
        self.frame:SetMovable(true)
        Print("ChatFilter 解除锁定")
    end
end

-- 刷新过滤消息
function ChatFilter:RefreshFilteredMessages()
    if not self.content then return end

    for _, child in ipairs({self.content:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end
    self.lastMessages = {}
    self.content:SetHeight(1)

    -- 刷新时总是滚动到最新消息
    self.autoScroll = true

    if ChatFilterDB.recentMessages then
        local displayedSenders = {}
        for i = #ChatFilterDB.recentMessages, 1, -1 do
            local messageInfo = ChatFilterDB.recentMessages[i]
            if not displayedSenders[messageInfo.sender] then
                for _, keywordSet in ipairs(self.keywords) do
                    if self:ContainsKeyword(messageInfo.message, keywordSet) then
                        self:DisplayFilteredMessage(messageInfo)
                        displayedSenders[messageInfo.sender] = true
                        break
                    end
                end
            end
            if #self.lastMessages >= self.maxLines then
                break
            end
        end
    end

    self:ReorderMessages()
end

-- 添加一个新函数来清理旧消息
function ChatFilter:CleanOldMessages()
    local currentTime = time()
    local oneDayAgo = currentTime - (24 * 60 * 60)  -- 24小时前的时间戳

    local i = 1
    while i <= #ChatFilterDB.recentMessages do
        if ChatFilterDB.recentMessages[i].time < oneDayAgo then
            table.remove(ChatFilterDB.recentMessages, i)
        else
            i = i + 1
        end
    end
end

-- 将关键词组合转换为字符串（用于显示）
function ChatFilter:KeywordSetToString(keywordSet)
    local parts = {}
    for _, andGroup in ipairs(keywordSet) do
        table.insert(parts, "(" .. table.concat(andGroup, " 或 ") .. ")")
    end
    return table.concat(parts, " 且 ")
end

-- 显示所有关键词组合
function ChatFilter:ShowKeywordSets()
    Print("ChatFilter 关键词列表:")
    if #self.keywords == 0 then
        Print("  无关键词")
    else
        for i, keywordSet in ipairs(self.keywords) do
            Print("  " .. i .. ". " .. self:KeywordSetToString(keywordSet))
        end
    end
end

-- 添加关键词组合
function ChatFilter:AddKeywordSet(keywords)
    table.insert(self.keywords, keywords)
    ChatFilterDB.keywords = self.keywords
    Print("ChatFilter 已添加关键词: " .. self:KeywordSetToString(keywords))
    self:ShowKeywordSets()
    self:RefreshFilteredMessages()
end

-- 移除关键词组合
function ChatFilter:RemoveKeywordSet(index)
    if index > 0 and index <= #self.keywords then
        local removed = table.remove(self.keywords, index)
        ChatFilterDB.keywords = self.keywords
        Print("ChatFilter 已移除关键词: " .. self:KeywordSetToString(removed))
        self:ShowKeywordSets()
        self:RefreshFilteredMessages()
    else
        Print("  无效的索引: " .. tostring(index))
    end
end

-- 添加 trim 函数
function string.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

-- 添加斜杠命令
SLASH_CHATFILTER1 = "/cf"
SlashCmdList["CHATFILTER"] = function(msg)
    local command, arg = msg:match("^(%S*)%s*(.-)$")
    if command == "toggle" then
        ChatFilter:ToggleFrame()
    elseif command == "lock" then
        ChatFilter:ToggleLocked()
    elseif command == "list" then
        ChatFilter:ShowKeywordSets()
    elseif command == "sound" then
        ChatFilter:ToggleSound()
    elseif command == "add" and arg ~= "" then
        -- 将中文符号转换为英文符号
        arg = arg:gsub("，", ","):gsub("；", ";")

        local keywords = {}
        for andGroup in arg:gmatch("([^;]+)") do
            local orGroup = {}
            for keyword in andGroup:gmatch("([^,]+)") do
                table.insert(orGroup, string.trim(keyword))
            end
            table.insert(keywords, orGroup)
        end
        ChatFilter:AddKeywordSet(keywords)
    elseif command == "remove" and arg ~= "" then
        local index = tonumber(arg)
        if index then
            ChatFilter:RemoveKeywordSet(index)
        else
            Print("请提供有效的索引号")
        end
    elseif command == "debug" then
        ChatFilter.debugMode = not ChatFilter.debugMode
        Print("ChatFilter 调试模式: " .. (ChatFilter.debugMode and "开启" or "关闭"))
    else
        Print("ChatFilter 命令:")
        Print("  /cf toggle - 开启/关闭 ChatFilter")
        Print("  /cf lock - 开启/关闭框架锁定")
        Print("  /cf sound - 开启/关闭音频提醒")
        Print("  /cf list - 显示所有关键词组合")
        Print("  /cf add <关键词组1>;<关键词组2>... - 添加关键词组合")
        Print("  /cf remove <索引> - 移除指定索引的关键词组合")
        Print("  /cf debug - 切换调试模式")
        Print("  注意: 每个关键词组内用逗号分隔，不同组之间用分号分隔")
    end
end

-- 注册事件
function ChatFilter:RegisterEvents()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("CHAT_MSG_CHANNEL")
    frame:RegisterEvent("CHAT_MSG_YELL")
    frame:RegisterEvent("CHAT_MSG_SAY")
    frame:SetScript("OnEvent", function(_, event, ...)
        if event == "ADDON_LOADED" then
            self:OnLoaded(...)
        elseif self.enabled then
            self:OnChatMessage(event, ...)
        end
    end)
end

-- 创建窗口
ChatFilter:Init()

-- vim:ft=lua:ts=4:sw=4
