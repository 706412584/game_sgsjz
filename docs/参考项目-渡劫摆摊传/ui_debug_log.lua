-- ============================================================================
-- ui_debug_log.lua — 悬浮调试日志面板 (带 Tag 过滤)
-- 拦截 print() 输出，按 [Tag] 过滤，显示在屏幕右上角
-- 支持最小化为悬浮圆圈 + 长按拖动
-- ============================================================================
local UI = require("urhox-libs/UI")

local M = {}

local MAX_LINES = 40         -- 最多保留行数
local PANEL_WIDTH = 260      -- 面板宽度
local PANEL_HEIGHT = 200     -- 面板高度
local FONT_SIZE = 7          -- 字体大小
local TAG_FONT = 7           -- tag 按钮字号
local BUBBLE_SIZE = 42       -- 悬浮圆圈直径
local BUBBLE_FONT = 6        -- 圆圈内字号

local enabled_ = false
local panel_ = nil           -- 展开面板
local bubble_ = nil          -- 最小化悬浮圆圈
local logLabel_ = nil
local bubbleLabel_ = nil     -- 圆圈内文字
local lines_ = {}            -- { tag=string, text=string }
local originalPrint_ = nil
local minimized_ = false
local contentPanel_ = nil
local filterBarPanel_ = nil
local container_ = nil
local titleLabel_ = nil      -- 标题栏 +/- 文字

-- 拖动相关（使用引擎 Update 轮询，绕开 UI Pan 手势命中检测问题）
local dragging_ = false
local dragReady_ = false     -- PointerDown 已按下，等待判定是拖动还是点击
local dragStartX_ = 0        -- 按下时的屏幕坐标
local dragStartY_ = 0
local dragLastX_ = 0         -- 上一帧的屏幕坐标
local dragLastY_ = 0
local dragStartTime_ = 0     -- 按下时间
local bubbleX_ = nil         -- 圆圈当前 left（nil 表示用默认 right 定位）
local bubbleY_ = 30          -- 圆圈当前 top
local DRAG_THRESHOLD = 8     -- 移动超过此像素才判定为拖动
local DRAG_UPDATE_TAG = "DebugLogDrag"

-- Tag 过滤状态
local allTags_ = {}          -- tag -> true (已出现过的 tag 集合)
local activeTags_ = {}       -- tag -> true (当前启用的 tag)
local tagBtns_ = {}          -- tag -> button widget
local showAll_ = true        -- true = 不过滤, 显示全部

-- ========== 工具函数 ==========

--- 从日志行提取 tag，格式: [Xxx] 开头
---@param text string
---@return string tag, string body
local function extractTag(text)
    local tag = text:match("^%[([%w_]+)%]")
    if tag then
        return tag, text
    end
    return "_other", text
end

--- All 模式下隐藏的标签(信息量大, 干扰阅读)
local allHiddenTags_ = { Sync = true }

--- 判断一行是否应该显示
local function shouldShow(entry)
    if showAll_ then return not allHiddenTags_[entry.tag] end
    return activeTags_[entry.tag] == true
end

--- 刷新日志显示
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

--- 刷新悬浮圆圈显示的最新日志
local function refreshBubbleText()
    if not bubbleLabel_ or not minimized_ then return end
    -- 取最后一条可见日志，截取显示
    local lastText = ""
    for i = #lines_, 1, -1 do
        if shouldShow(lines_[i]) then
            lastText = lines_[i].text
            break
        end
    end
    if #lastText > 30 then
        lastText = lastText:sub(1, 27) .. "..."
    end
    bubbleLabel_:SetText(lastText)
end

--- 更新单个 tag 按钮的样式
local function updateTagBtnStyle(tag)
    local btn = tagBtns_[tag]
    if not btn then return end
    local isActive = showAll_ or activeTags_[tag]
    btn:SetStyle({
        backgroundColor = isActive
            and { 0, 100, 0, 220 }
            or  { 60, 60, 60, 180 },
        borderColor = isActive
            and { 0, 200, 0, 200 }
            or  { 100, 100, 100, 120 },
    })
end

--- 创建一个 tag 过滤按钮
local function createTagBtn(tag)
    if tagBtns_[tag] then return end
    local btn = UI.Panel {
        height = 16,
        paddingHorizontal = 4,
        backgroundColor = { 0, 100, 0, 220 },
        borderRadius = 3,
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
            for t, _ in pairs(tagBtns_) do
                updateTagBtnStyle(t)
            end
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
    if filterBarPanel_ then
        filterBarPanel_:AddChild(btn)
    end
end

--- 注册新 tag
local function ensureTag(tag)
    if allTags_[tag] then return end
    allTags_[tag] = true
    createTagBtn(tag)
end

-- ========== 最小化/最大化切换 ==========

local function switchToMinimized()
    print("[DebugLog] >>> switchToMinimized() called")
    minimized_ = true
    if titleLabel_ then titleLabel_:SetText("[+]") end
    -- 隐藏展开面板
    if panel_ then
        panel_:SetVisible(false)
        YGNodeStyleSetDisplay(panel_.node, YGDisplayNone)
    end
    -- 显示悬浮圆圈
    if bubble_ then
        bubble_:SetVisible(true)
        YGNodeStyleSetDisplay(bubble_.node, YGDisplayFlex)
        refreshBubbleText()
    end
end

local function switchToMaximized()
    print("[DebugLog] >>> switchToMaximized() called, dragging_=" .. tostring(dragging_))
    minimized_ = false
    if titleLabel_ then titleLabel_:SetText("[-]") end
    -- 显示展开面板
    if panel_ then
        panel_:SetVisible(true)
        YGNodeStyleSetDisplay(panel_.node, YGDisplayFlex)
        refreshDisplay()
    end
    -- 隐藏悬浮圆圈
    if bubble_ then
        bubble_:SetVisible(false)
        YGNodeStyleSetDisplay(bubble_.node, YGDisplayNone)
    end
end

-- ========== 拖动逻辑（引擎 Update 轮询） ==========

--- 获取当前触摸/鼠标的逻辑坐标
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

--- 初始化 bubbleX_（从 right 定位转为 left 值）
local function ensureBubbleX()
    if bubbleX_ == nil then
        local dpr = graphics:GetDPR()
        local screenW = graphics:GetWidth() / dpr
        bubbleX_ = screenW - BUBBLE_SIZE - 6
    end
end

--- 移动圆圈到指定位置
local function moveBubbleTo(lx, ly)
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    if lx < 0 then lx = 0 end
    if lx > screenW - BUBBLE_SIZE then lx = screenW - BUBBLE_SIZE end
    if ly < 0 then ly = 0 end
    if ly > screenH - BUBBLE_SIZE then ly = screenH - BUBBLE_SIZE end
    bubbleX_ = lx
    bubbleY_ = ly
    YGNodeStyleSetPosition(bubble_.node, YGEdgeRight, YGUndefined)
    bubble_:SetStyle({ left = bubbleX_, top = bubbleY_ })
end

--- 每帧拖动更新（订阅 Update 事件）
local function handleDragUpdate(eventType, eventData)
    if not dragReady_ and not dragging_ then return end

    local curX, curY = getInputPos()

    -- 还在等待判定阶段
    if dragReady_ and not dragging_ then
        local dx = curX - dragStartX_
        local dy = curY - dragStartY_
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist > DRAG_THRESHOLD then
            -- 超过阈值，进入拖动模式
            dragging_ = true
            dragReady_ = false
            ensureBubbleX()
            dragLastX_ = curX
            dragLastY_ = curY
            print("[DebugLog] drag started, dist=" .. string.format("%.1f", dist))
        end
        return
    end

    -- 拖动中：检查是否还在按住
    local pressed = false
    if input.numTouches > 0 then
        pressed = true
    else
        pressed = input:GetMouseButtonDown(MOUSEB_LEFT)
    end

    if not pressed then
        -- 松手，结束拖动
        print("[DebugLog] drag ended at left=" .. tostring(bubbleX_) .. " top=" .. tostring(bubbleY_))
        dragging_ = false
        dragReady_ = false
        return
    end

    -- 更新位置
    local dx = curX - dragLastX_
    local dy = curY - dragLastY_
    dragLastX_ = curX
    dragLastY_ = curY
    if dx ~= 0 or dy ~= 0 then
        moveBubbleTo(bubbleX_ + dx, bubbleY_ + dy)
    end
end

-- ========== 核心逻辑 ==========

--- 添加一行日志
local function addLine(text)
    local tag, body = extractTag(text)
    ensureTag(tag)
    local entry = { tag = tag, text = body }
    table.insert(lines_, entry)
    while #lines_ > MAX_LINES do
        table.remove(lines_, 1)
    end
    if shouldShow(entry) then
        refreshDisplay()
        refreshBubbleText()
    end
end

--- Hook print 函数
local function hookPrint()
    if originalPrint_ then return end
    originalPrint_ = print
    ---@diagnostic disable-next-line: lowercase-global
    print = function(...)
        originalPrint_(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        local line = table.concat(parts, "\t")
        if #line > 120 then
            line = line:sub(1, 117) .. "..."
        end
        addLine(line)
    end
end

--- 恢复原始 print
local function unhookPrint()
    if originalPrint_ then
        ---@diagnostic disable-next-line: lowercase-global
        print = originalPrint_
        originalPrint_ = nil
    end
end

-- ========== UI 构建 ==========

--- 创建悬浮圆圈（最小化状态）
local function createBubble()
    if bubble_ then return end

    bubbleLabel_ = UI.Label {
        text = "",
        fontSize = BUBBLE_FONT,
        fontColor = { 0, 255, 0, 200 },
        width = "100%",
        textAlign = "center",
        whiteSpace = "normal",
        maxLines = 3,
        pointerEvents = "none",
    }

    -- 圆圈中间的 "DEBUG" 标识
    local debugTitle = UI.Label {
        text = "DBG",
        fontSize = 6,
        fontWeight = "bold",
        fontColor = { 0, 255, 0, 255 },
        textAlign = "center",
        width = "100%",
        pointerEvents = "none",
    }

    bubble_ = UI.Panel {
        position = "absolute",
        right = 6,
        top = bubbleY_,
        width = BUBBLE_SIZE,
        height = BUBBLE_SIZE,
        zIndex = 1000,
        backgroundColor = { 0, 0, 0, 200 },
        borderWidth = 2,
        borderColor = { 0, 200, 0, 200 },
        borderRadius = BUBBLE_SIZE / 2,
        pointerEvents = "auto",
        justifyContent = "center",
        alignItems = "center",
        overflow = "hidden",
        paddingHorizontal = 3,
        -- 点击展开（拖动中不触发）
        onClick = function(self)
            if not dragging_ then
                switchToMaximized()
            end
        end,
        -- 按下开始拖动判定
        onPointerDown = function(event, self)
            local ix, iy = getInputPos()
            dragReady_ = true
            dragging_ = false
            dragStartX_ = ix
            dragStartY_ = iy
            dragLastX_ = ix
            dragLastY_ = iy
            dragStartTime_ = time and time.elapsedTime or 0
            print("[DebugLog] bubble onPointerDown, startPos=" .. string.format("%.1f,%.1f", ix, iy))
        end,
        children = {
            debugTitle,
            bubbleLabel_,
        },
    }

    -- 初始隐藏（默认展开状态）
    bubble_:SetVisible(false)
    YGNodeStyleSetDisplay(bubble_.node, YGDisplayNone)
end

local function createPanel()
    if panel_ then return end

    logLabel_ = UI.Label {
        text = "",
        fontSize = FONT_SIZE,
        fontColor = { 0, 255, 0, 220 },
        width = "100%",
        whiteSpace = "normal",
    }

    contentPanel_ = UI.Panel {
        width = "100%",
        flexGrow = 1,
        overflow = "scroll",
        children = { logLabel_ },
    }

    -- Tag 过滤栏
    filterBarPanel_ = UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 3,
        paddingHorizontal = 3,
        paddingVertical = 2,
        backgroundColor = { 20, 20, 20, 200 },
    }

    -- "ALL" 按钮
    local allBtn = UI.Panel {
        height = 16,
        paddingHorizontal = 4,
        backgroundColor = { 0, 80, 120, 220 },
        borderRadius = 3,
        borderWidth = 1,
        borderColor = { 0, 160, 220, 200 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showAll_ = true
            activeTags_ = {}
            for t, _ in pairs(tagBtns_) do
                updateTagBtnStyle(t)
            end
            refreshDisplay()
        end,
        children = {
            UI.Label {
                text = "ALL",
                fontSize = TAG_FONT,
                fontWeight = "bold",
                fontColor = { 180, 230, 255, 255 },
            },
        },
    }
    filterBarPanel_:AddChild(allBtn)

    -- 最小化 / 清除按钮
    titleLabel_ = UI.Label {
        text = "[-]",
        fontSize = 7,
        fontColor = { 200, 200, 200, 200 },
    }

    -- 标题栏
    local titleBar = UI.Panel {
        width = "100%",
        height = 18,
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "space-between",
        backgroundColor = { 0, 80, 0, 200 },
        paddingHorizontal = 4,
        children = {
            UI.Label {
                text = "DEBUG",
                fontSize = 7,
                fontWeight = "bold",
                fontColor = { 0, 255, 0, 255 },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 6,
                children = {
                    -- CLEAR
                    UI.Panel {
                        paddingHorizontal = 4,
                        height = 14,
                        backgroundColor = { 80, 0, 0, 180 },
                        borderRadius = 3,
                        justifyContent = "center",
                        alignItems = "center",
                        onClick = function(self)
                            lines_ = {}
                            refreshDisplay()
                        end,
                        children = {
                            UI.Label {
                                text = "CLR",
                                fontSize = 6,
                                fontColor = { 255, 100, 100, 220 },
                            },
                        },
                    },
                    -- 最小化按钮
                    UI.Panel {
                        paddingHorizontal = 3,
                        height = 14,
                        backgroundColor = { 60, 60, 60, 180 },
                        borderRadius = 3,
                        justifyContent = "center",
                        alignItems = "center",
                        onClick = function(self)
                            switchToMinimized()
                        end,
                        children = { titleLabel_ },
                    },
                },
            },
        },
    }

    panel_ = UI.Panel {
        position = "absolute",
        right = 4,
        top = 30,
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
        zIndex = 999,
        backgroundColor = { 0, 0, 0, 180 },
        borderWidth = 1,
        borderColor = { 0, 255, 0, 150 },
        borderRadius = 4,
        pointerEvents = "auto",
        children = {
            titleBar,
            filterBarPanel_,
            contentPanel_,
        },
    }
end

-- ========== 公开 API ==========

--- 启用调试日志面板
---@param container table UI 根容器
function M.Enable(container)
    if enabled_ then return end
    enabled_ = true
    container_ = container
    hookPrint()
    createPanel()
    createBubble()
    if container then
        if panel_ then container:AddChild(panel_) end
        if bubble_ then container:AddChild(bubble_) end
    end
    -- 订阅 PostUpdate 事件用于拖动轮询（避免与 main.lua 的 Update 冲突）
    SubscribeToEvent("PostUpdate", handleDragUpdate)
    -- 默认最小化
    switchToMinimized()
    addLine("[DebugLog] 已启用 - 点击圆圈展开")
end

--- 禁用调试日志面板
function M.Disable()
    if not enabled_ then return end
    enabled_ = false
    unhookPrint()
    UnsubscribeFromEvent("PostUpdate")
    if panel_ then
        panel_:Destroy()
        panel_ = nil
        logLabel_ = nil
        contentPanel_ = nil
        filterBarPanel_ = nil
        titleLabel_ = nil
    end
    if bubble_ then
        bubble_:Destroy()
        bubble_ = nil
        bubbleLabel_ = nil
    end
    lines_ = {}
    allTags_ = {}
    activeTags_ = {}
    tagBtns_ = {}
    showAll_ = true
    minimized_ = false
    dragging_ = false
    dragReady_ = false
    bubbleX_ = nil
    bubbleY_ = 30
end

---@return boolean
function M.IsEnabled()
    return enabled_
end

--- 手动添加一行日志
---@param text string
function M.Log(text)
    addLine(tostring(text))
end

return M
