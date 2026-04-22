-- ui/debug_log.lua — 悬浮调试日志面板 (带 Tag 过滤)
-- 拦截 print() 输出，按 [Tag] 过滤，显示在屏幕右上角
-- 支持最小化为悬浮圆圈 + 长按拖动
-- 基于渡劫摆摊传参考实现
local UI = require("urhox-libs/UI")

local M = {}

local MAX_LINES = 60
local PANEL_WIDTH = 480
local PANEL_HEIGHT = 340
local FONT_SIZE = 12
local TAG_FONT = 11
local BUBBLE_SIZE = 56
local BUBBLE_FONT = 9

local enabled_ = false
local panel_ = nil
local bubble_ = nil
local logLabel_ = nil
local bubbleLabel_ = nil
local lines_ = {}
local originalPrint_ = nil
local minimized_ = false
local contentPanel_ = nil
local filterBarPanel_ = nil
local container_ = nil
local titleLabel_ = nil

-- 拖动相关
local dragging_ = false
local dragReady_ = false
local dragStartX_ = 0
local dragStartY_ = 0
local dragLastX_ = 0
local dragLastY_ = 0
local bubbleX_ = nil
local bubbleY_ = 30
local DRAG_THRESHOLD = 8

-- Tag 过滤
local allTags_ = {}
local activeTags_ = {}
local tagBtns_ = {}
local showAll_ = false          -- 默认只显示项目标签

-- 项目默认显示的标签
local PROJECT_TAGS = { StartPage = true, DebugLog = true }

-- ========== 工具函数 ==========

local function extractTag(text)
    local tag = text:match("^%[([%w_]+)%]")
    if tag then return tag, text end
    return "_other", text
end

local allHiddenTags_ = { Sync = true }

local function shouldShow(entry)
    if showAll_ then return not allHiddenTags_[entry.tag] end
    return activeTags_[entry.tag] == true
end

local function refreshDisplay()
    if not logLabel_ or minimized_ then return end
    local visible = {}
    for _, entry in ipairs(lines_) do
        if shouldShow(entry) then
            visible[#visible + 1] = entry.text
        end
    end
    logLabel_:SetText(table.concat(visible, "\n"))
end

local function refreshBubbleText()
    if not bubbleLabel_ or not minimized_ then return end
    local lastText = ""
    for i = #lines_, 1, -1 do
        if shouldShow(lines_[i]) then
            lastText = lines_[i].text
            break
        end
    end
    if #lastText > 30 then lastText = lastText:sub(1, 27) .. "..." end
    bubbleLabel_:SetText(lastText)
end

local function updateTagBtnStyle(tag)
    local btn = tagBtns_[tag]
    if not btn then return end
    local isActive = showAll_ or activeTags_[tag]
    btn:SetStyle({
        backgroundColor = isActive and { 0, 100, 0, 220 } or { 60, 60, 60, 180 },
        borderColor = isActive and { 0, 200, 0, 200 } or { 100, 100, 100, 120 },
    })
end

local function createTagBtn(tag)
    if tagBtns_[tag] then return end
    local btn = UI.Panel {
        height = 28,
        paddingHorizontal = 8,
        backgroundColor = { 0, 100, 0, 220 },
        borderRadius = 4,
        borderWidth = 1,
        borderColor = { 0, 200, 0, 200 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            if showAll_ then
                showAll_ = false
                activeTags_ = {}
                activeTags_[tag] = true
            elseif activeTags_[tag] then
                activeTags_[tag] = nil
                if not next(activeTags_) then
                    showAll_ = true
                end
            else
                activeTags_[tag] = true
            end
            for t, _ in pairs(tagBtns_) do updateTagBtnStyle(t) end
            refreshDisplay()
        end,
        children = {
            UI.Label {
                text = tag,
                fontSize = TAG_FONT,
                fontColor = { 220, 255, 220, 255 },
            },
        },
    }
    tagBtns_[tag] = btn
    if filterBarPanel_ then filterBarPanel_:AddChild(btn) end
end

local function ensureTag(tag)
    if allTags_[tag] then return end
    allTags_[tag] = true
    createTagBtn(tag)
end

-- ========== 最小化/最大化 ==========

local function switchToMinimized()
    minimized_ = true
    if titleLabel_ then titleLabel_:SetText("[+]") end
    if panel_ then
        panel_:SetVisible(false)
        YGNodeStyleSetDisplay(panel_.node, YGDisplayNone)
    end
    if bubble_ then
        bubble_:SetVisible(true)
        YGNodeStyleSetDisplay(bubble_.node, YGDisplayFlex)
        refreshBubbleText()
    end
end

local function switchToMaximized()
    minimized_ = false
    if titleLabel_ then titleLabel_:SetText("[-]") end
    if panel_ then
        panel_:SetVisible(true)
        YGNodeStyleSetDisplay(panel_.node, YGDisplayFlex)
        refreshDisplay()
    end
    if bubble_ then
        bubble_:SetVisible(false)
        YGNodeStyleSetDisplay(bubble_.node, YGDisplayNone)
    end
end

-- ========== 拖动逻辑 ==========

local function getInputPos()
    local dpr = graphics:GetDPR()
    if input.numTouches > 0 then
        local ts = input:GetTouch(0)
        return ts.position.x / dpr, ts.position.y / dpr
    else
        local mp = input.mousePosition
        return mp.x / dpr, mp.y / dpr
    end
end

local function ensureBubbleX()
    if bubbleX_ == nil then
        local dpr = graphics:GetDPR()
        local screenW = graphics:GetWidth() / dpr
        bubbleX_ = screenW - BUBBLE_SIZE - 6
    end
end

local function moveBubbleTo(lx, ly)
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    lx = math.max(0, math.min(lx, screenW - BUBBLE_SIZE))
    ly = math.max(0, math.min(ly, screenH - BUBBLE_SIZE))
    bubbleX_ = lx
    bubbleY_ = ly
    YGNodeStyleSetPosition(bubble_.node, YGEdgeRight, YGUndefined)
    bubble_:SetStyle({ left = bubbleX_, top = bubbleY_ })
end

local function handleDragUpdate(eventType, eventData)
    if not dragReady_ and not dragging_ then return end
    local curX, curY = getInputPos()
    if dragReady_ and not dragging_ then
        local dx = curX - dragStartX_
        local dy = curY - dragStartY_
        if math.sqrt(dx * dx + dy * dy) > DRAG_THRESHOLD then
            dragging_ = true
            dragReady_ = false
            ensureBubbleX()
            dragLastX_ = curX
            dragLastY_ = curY
        end
        return
    end
    local pressed = input.numTouches > 0 or input:GetMouseButtonDown(MOUSEB_LEFT)
    if not pressed then
        dragging_ = false
        dragReady_ = false
        return
    end
    local dx = curX - dragLastX_
    local dy = curY - dragLastY_
    dragLastX_ = curX
    dragLastY_ = curY
    if dx ~= 0 or dy ~= 0 then moveBubbleTo(bubbleX_ + dx, bubbleY_ + dy) end
end

-- ========== 核心逻辑 ==========

local function addLine(text)
    local tag, body = extractTag(text)
    ensureTag(tag)
    local entry = { tag = tag, text = body }
    table.insert(lines_, entry)
    while #lines_ > MAX_LINES do table.remove(lines_, 1) end
    if shouldShow(entry) then
        refreshDisplay()
        refreshBubbleText()
    end
end

local function hookPrint()
    if originalPrint_ then return end
    originalPrint_ = print
    ---@diagnostic disable-next-line: lowercase-global
    print = function(...)
        originalPrint_(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
        local line = table.concat(parts, "\t")
        if #line > 120 then line = line:sub(1, 117) .. "..." end
        addLine(line)
    end
end

local function unhookPrint()
    if originalPrint_ then
        ---@diagnostic disable-next-line: lowercase-global
        print = originalPrint_
        originalPrint_ = nil
    end
end

-- ========== UI 构建 ==========

local function createBubble()
    if bubble_ then return end
    bubbleLabel_ = UI.Label {
        text = "", fontSize = BUBBLE_FONT,
        fontColor = { 0, 255, 0, 200 },
        width = "100%", textAlign = "center",
        whiteSpace = "normal", maxLines = 3,
        pointerEvents = "none",
    }
    bubble_ = UI.Panel {
        position = "absolute", right = 6, top = bubbleY_,
        width = BUBBLE_SIZE, height = BUBBLE_SIZE, zIndex = 1000,
        backgroundColor = { 0, 0, 0, 200 },
        borderWidth = 2, borderColor = { 0, 200, 0, 200 },
        borderRadius = BUBBLE_SIZE / 2,
        pointerEvents = "auto",
        justifyContent = "center", alignItems = "center",
        overflow = "hidden", paddingHorizontal = 4,
        onClick = function(self)
            if not dragging_ then switchToMaximized() end
        end,
        onPointerDown = function(event, self)
            local ix, iy = getInputPos()
            dragReady_ = true
            dragging_ = false
            dragStartX_ = ix
            dragStartY_ = iy
            dragLastX_ = ix
            dragLastY_ = iy
        end,
        children = {
            UI.Label {
                text = "DBG", fontSize = 10, fontWeight = "bold",
                fontColor = { 0, 255, 0, 255 }, textAlign = "center",
                width = "100%", pointerEvents = "none",
            },
            bubbleLabel_,
        },
    }
    bubble_:SetVisible(false)
    YGNodeStyleSetDisplay(bubble_.node, YGDisplayNone)
end

local function createPanel()
    if panel_ then return end
    logLabel_ = UI.Label {
        text = "", fontSize = FONT_SIZE,
        fontColor = { 0, 255, 0, 220 },
        width = "100%", whiteSpace = "normal",
    }
    contentPanel_ = UI.Panel {
        width = "100%", flexGrow = 1,
        overflow = "scroll", children = { logLabel_ },
    }
    filterBarPanel_ = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        gap = 5, paddingHorizontal = 6, paddingVertical = 4,
        backgroundColor = { 20, 20, 20, 200 },
    }
    filterBarPanel_:AddChild(UI.Panel {
        height = 28, paddingHorizontal = 8,
        backgroundColor = { 0, 80, 120, 220 },
        borderRadius = 4, borderWidth = 1,
        borderColor = { 0, 160, 220, 200 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            showAll_ = true
            activeTags_ = {}
            for t, _ in pairs(tagBtns_) do updateTagBtnStyle(t) end
            refreshDisplay()
        end,
        children = {
            UI.Label { text = "ALL", fontSize = TAG_FONT, fontWeight = "bold",
                fontColor = { 180, 230, 255, 255 } },
        },
    })
    titleLabel_ = UI.Label {
        text = "[-]", fontSize = 12, fontColor = { 200, 200, 200, 200 },
    }
    local titleBar = UI.Panel {
        width = "100%", height = 32,
        flexDirection = "row", alignItems = "center",
        justifyContent = "space-between",
        backgroundColor = { 0, 80, 0, 200 },
        paddingHorizontal = 8,
        children = {
            UI.Label { text = "DEBUG", fontSize = 13, fontWeight = "bold",
                fontColor = { 0, 255, 0, 255 } },
            UI.Panel {
                flexDirection = "row", gap = 8,
                children = {
                    UI.Panel {
                        paddingHorizontal = 8, height = 24,
                        backgroundColor = { 80, 0, 0, 180 }, borderRadius = 4,
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self) lines_ = {}; refreshDisplay() end,
                        children = { UI.Label { text = "CLR", fontSize = 11,
                            fontColor = { 255, 100, 100, 220 } } },
                    },
                    UI.Panel {
                        paddingHorizontal = 6, height = 24,
                        backgroundColor = { 60, 60, 60, 180 }, borderRadius = 4,
                        justifyContent = "center", alignItems = "center",
                        onClick = function(self) switchToMinimized() end,
                        children = { titleLabel_ },
                    },
                },
            },
        },
    }
    panel_ = UI.Panel {
        position = "absolute", right = 8, top = 30,
        width = PANEL_WIDTH, height = PANEL_HEIGHT, zIndex = 999,
        backgroundColor = { 0, 0, 0, 190 },
        borderWidth = 1, borderColor = { 0, 255, 0, 150 },
        borderRadius = 6, pointerEvents = "auto",
        children = { titleBar, filterBarPanel_, contentPanel_ },
    }
end

-- ========== 公开 API ==========

function M.Enable(container)
    if enabled_ then return end
    enabled_ = true
    container_ = container
    -- 默认激活项目标签
    for tag, _ in pairs(PROJECT_TAGS) do
        activeTags_[tag] = true
    end
    hookPrint()
    createPanel()
    createBubble()
    if container then
        if panel_ then container:AddChild(panel_) end
        if bubble_ then container:AddChild(bubble_) end
    end
    SubscribeToEvent("PostUpdate", handleDragUpdate)
    switchToMinimized()
    addLine("[DebugLog] debug panel enabled")
end

function M.Disable()
    if not enabled_ then return end
    enabled_ = false
    unhookPrint()
    UnsubscribeFromEvent("PostUpdate")
    if panel_ then panel_:Destroy(); panel_ = nil end
    if bubble_ then bubble_:Destroy(); bubble_ = nil end
    logLabel_ = nil
    contentPanel_ = nil
    filterBarPanel_ = nil
    titleLabel_ = nil
    bubbleLabel_ = nil
    lines_ = {}
    allTags_ = {}
    activeTags_ = {}
    tagBtns_ = {}
    showAll_ = false
    minimized_ = false
    dragging_ = false
    dragReady_ = false
    bubbleX_ = nil
    bubbleY_ = 30
end

function M.IsEnabled() return enabled_ end

function M.Log(text) addLine(tostring(text)) end

return M
