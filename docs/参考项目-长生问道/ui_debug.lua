-- ============================================================================
-- 《问道长生》全局调试面板
-- 悬浮圆形按钮 + 可展开日志/数据/系统面板
-- 支持 tag 过滤、横向滚动、拖拽
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Toast = require("ui_toast")

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================
local MAX_LOGS      = 100
local BTN_SIZE      = 44
local BTN_MARGIN    = 12
local PANEL_WIDTH   = 300
local PANEL_HEIGHT  = 320

-- 项目 tag 白名单（自动从 print 的 [xxx] 前缀提取）
local PROJECT_TAGS = {
    ["GameServer"]   = true,
    ["GamePlayer"]   = true,
    ["Cultivation"]  = true,
    ["Title"]        = true,
    ["Home"]         = true,
    ["Inheritance"]  = true,
    ["AudioManager"] = true,
    ["网络"]         = true,
    ["试炼"]         = true,
    ["宗门"]         = true,
    ["任务"]         = true,
    ["灵宠"]         = true,
    ["角色创建"]     = true,
    ["菜单"]         = true,
    ["聊天"]         = true,
    ["炼丹"]         = true,
    ["探索"]         = true,
    ["修炼"]         = true,
    ["法宝"]         = true,
    ["悟道"]         = true,
    ["背包"]         = true,
    ["启动"]         = true,
}

-- ============================================================================
-- 状态
-- ============================================================================
local enabled_    = true
local expanded_   = false
local logs_       = {}          -- { { text, level, time, tag }, ... }
local activeTab_  = "log"
local showAll_    = false       -- false=仅项目标签, true=全部
local container_  = nil
local btnEl_      = nil
local panelEl_    = nil
local btnRight_   = BTN_MARGIN
local btnBottom_  = BTN_MARGIN
local panelRight_  = nil   -- nil = 跟随按钮位置
local panelBottom_ = nil
local dirty_      = false
local rebuilding_ = false

local originalPrint_ = nil

-- ============================================================================
local function MarkDirty()
    dirty_ = true
end

-- ============================================================================
-- 从文本提取 [xxx] tag，同时返回去掉前缀后的纯文本
-- ============================================================================
local function ExtractTag(text)
    local tag, rest = text:match("^%[([^%]]+)%]%s*(.*)")
    if tag then
        return tag, rest
    end
    return nil, text
end

-- ============================================================================
-- 日志捕获
-- ============================================================================

function M.Init()
    if originalPrint_ then return end
    originalPrint_ = _G.print
    _G.print = function(...)
        originalPrint_(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        M.Log(table.concat(parts, "  "), "info")
    end
end

---@param text string
---@param level? string
---@param tag? string  可选 tag，未传则自动从文本 [xxx] 提取
function M.Log(text, level, tag)
    level = level or "info"
    local cleanText = text
    if not tag then
        tag, cleanText = ExtractTag(text)
    end
    logs_[#logs_ + 1] = {
        text  = cleanText,
        level = level,
        time  = os.date("%H:%M:%S"),
        tag   = tag,
    }
    while #logs_ > MAX_LOGS do
        table.remove(logs_, 1)
    end
    if expanded_ then MarkDirty() end
end

---@param text string
---@param tag? string
function M.LogError(text, tag) M.Log(text, "error", tag) end
---@param text string
---@param tag? string
function M.LogWarn(text, tag) M.Log(text, "warn", tag) end

-- ============================================================================
-- 开关
-- ============================================================================

function M.SetEnabled(v)
    enabled_ = v
    MarkDirty()
end

function M.IsEnabled() return enabled_ end

-- ============================================================================
-- UI 辅助
-- ============================================================================

local function GetLevelColor(level)
    if level == "error" then return { 255, 90, 90, 255 } end
    if level == "warn"  then return { 255, 200, 80, 255 } end
    return { 180, 180, 180, 255 }
end

local function GetTagColor(tag)
    if not tag then return { 100, 100, 100, 255 } end
    return { 130, 180, 220, 255 }
end

--- 判断日志是否通过过滤
local function PassFilter(entry)
    if showAll_ then return true end
    if entry.level == "error" or entry.level == "warn" then return true end
    return entry.tag and PROJECT_TAGS[entry.tag]
end

-- ============================================================================
-- 面板内容构建
-- ============================================================================

local function BuildLogTab()
    local children = {}
    local count = 0
    for i = #logs_, 1, -1 do
        if count >= 50 then break end
        local entry = logs_[i]
        if entry and PassFilter(entry) then
            count = count + 1
            -- 每条日志用横向滚动容器包裹，防止重叠
            local tagStr = ""
            if entry.tag then
                tagStr = "[" .. entry.tag .. "] "
            end
            children[#children + 1] = UI.Panel {
                width = "100%",
                flexShrink = 0,
                marginBottom = 1,
                children = {
                    UI.Label {
                        text = entry.time .. "  " .. tagStr .. entry.text,
                        fontSize = 11,
                        fontColor = GetLevelColor(entry.level),
                    },
                },
            }
        end
    end
    if #children == 0 then
        children[1] = UI.Label {
            text = showAll_ and "暂无日志" or "暂无项目日志（点击「全部」查看所有）",
            fontSize = 12,
            fontColor = Theme.colors.textSecondary,
        }
    end
    return children
end

local function BuildDataTab()
    local GamePlayer = require("game_player")
    local p = GamePlayer.Get()
    if not p then
        return { UI.Label { text = "玩家数据未加载", fontSize = 12, fontColor = Theme.colors.textSecondary } }
    end
    local lines = {
        "角色: " .. (p.name or "?") .. " (" .. (p.gender or "?") .. ")",
        "境界: " .. (p.realmName or "?") .. "  修为: " .. (p.cultivation or 0) .. "/" .. (p.cultivationMax or 0),
        "灵石: " .. (p.lingStone or 0) .. "  仙石: " .. (p.spiritStone or 0),
        "气血: " .. (p.hp or 0) .. "/" .. (p.hpMax or 0) .. "  灵力: " .. (p.mp or 0) .. "/" .. (p.mpMax or 0),
        "攻击: " .. (p.attack or 0) .. "  防御: " .. (p.defense or 0) .. "  速度: " .. (p.speed or 0),
        "暴击: " .. (p.crit or 0) .. "  闪避: " .. (p.dodge or 0) .. "  命中: " .. (p.hit or 0),
        "悟性: " .. (p.wisdom or 0) .. "  气运: " .. (p.fortune or 0) .. "  道心: " .. (p.daoHeart or 0),
        "背包: " .. #(p.bagItems or {}) .. " 件  功法: " .. #(p.skills or {}) .. " 个",
        "法宝: " .. #(p.artifacts or {}) .. " 个  丹药: " .. #(p.pills or {}) .. " 种",
        "寄售: " .. #(p.tradingListings or {}) .. " 件",
        "战力: " .. (p.power or 0),
    }
    -- 丹药明细（帮助调试丹药服用问题）
    if p.pills and #p.pills > 0 then
        lines[#lines + 1] = "-- 丹药明细 --"
        for _, pill in ipairs(p.pills) do
            lines[#lines + 1] = "  " .. (pill.name or "?") .. " x" .. tostring(pill.count or 0)
        end
    end
    local children = {}
    for _, line in ipairs(lines) do
        children[#children + 1] = UI.Label {
            text = line, fontSize = 12,
            fontColor = { 200, 200, 200, 255 }, marginBottom = 3,
        }
    end
    return children
end

local function BuildSystemTab()
    local dpr = graphics:GetDPR()
    local pw, ph = graphics:GetWidth(), graphics:GetHeight()
    local lw, lh = math.floor(pw / dpr), math.floor(ph / dpr)
    local GamePlayer = require("game_player")
    -- 获取用户 ID
    local uid = "未连接"
    if IsNetworkMode() then
        local ClientNet = require("network.client_net")
        local uidVal = ClientNet.GetUserId()
        if uidVal ~= 0 then uid = tostring(uidVal) end
    elseif clientCloud and clientCloud.userId and clientCloud.userId ~= 0 then
        uid = tostring(clientCloud.userId)
    end
    local lines = {
        "用户ID: " .. uid,
        "物理分辨率: " .. pw .. " x " .. ph,
        "逻辑分辨率: " .. lw .. " x " .. lh,
        "DPR: " .. string.format("%.1f", dpr),
        "玩家数据: " .. (GamePlayer.IsLoaded() and "已加载" or "未加载"),
        "有角色: " .. (GamePlayer.HasCharacter() and "是" or "否"),
        "日志条数: " .. #logs_,
    }
    local children = {}
    for _, line in ipairs(lines) do
        children[#children + 1] = UI.Label {
            text = line, fontSize = 12,
            fontColor = { 200, 200, 200, 255 }, marginBottom = 3,
        }
    end
    return children
end

local function BuildTabBtn(label, tabKey)
    local isActive = activeTab_ == tabKey
    return UI.Panel {
        flexGrow = 1,
        paddingVertical = 6,
        backgroundColor = isActive and { 80, 70, 50, 255 } or { 40, 35, 28, 255 },
        borderRadius = 4,
        justifyContent = "center",
        alignItems = "center",
        onClick = function()
            if activeTab_ ~= tabKey then
                activeTab_ = tabKey
                MarkDirty()
            end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = 12,
                fontWeight = isActive and "bold" or "normal",
                fontColor = isActive and Theme.colors.textGold or Theme.colors.textSecondary,
            },
        },
    }
end

--- 底部操作栏按钮
local function BuildActionBtn(label, color, bgColor, onClick)
    return UI.Panel {
        paddingHorizontal = 10, paddingVertical = 4,
        borderRadius = 4,
        backgroundColor = bgColor,
        onClick = onClick,
        children = {
            UI.Label { text = label, fontSize = 11, fontColor = color },
        },
    }
end

-- ============================================================================
-- 内部重建
-- ============================================================================

local function DoRebuildPanel()
    if not container_ then return end
    if panelEl_ then
        container_:RemoveChild(panelEl_)
        panelEl_ = nil
    end
    if not expanded_ then return end

    local tabContent
    if activeTab_ == "log" then
        tabContent = BuildLogTab()
    elseif activeTab_ == "data" then
        tabContent = BuildDataTab()
    else
        tabContent = BuildSystemTab()
    end

    -- 底部按钮列表
    local bottomBtns = {}

    -- 日志标签页：过滤/全部 切换按钮
    if activeTab_ == "log" then
        if showAll_ then
            bottomBtns[#bottomBtns + 1] = BuildActionBtn(
                "项目", { 130, 180, 220, 255 }, { 35, 55, 70, 200 },
                function() showAll_ = false; MarkDirty() end
            )
        else
            bottomBtns[#bottomBtns + 1] = BuildActionBtn(
                "全部", { 180, 180, 180, 255 }, { 50, 50, 50, 200 },
                function() showAll_ = true; MarkDirty() end
            )
        end
    end

    bottomBtns[#bottomBtns + 1] = BuildActionBtn(
        "复制", { 160, 200, 160, 255 }, { 40, 60, 40, 200 },
        function()
            local lines = {}
            for i = #logs_, 1, -1 do
                local e = logs_[i]
                if e and PassFilter(e) then
                    local tag = e.tag and ("[" .. e.tag .. "] ") or ""
                    lines[#lines + 1] = e.time .. "  " .. tag .. e.text
                end
            end
            if #lines == 0 then
                Toast.Show("无日志可复制", { variant = "info" })
                return
            end
            local text = table.concat(lines, "\n")
            -- 内部剪贴板（Web/WASM 下 useSystemClipboard 会崩溃，不使用）
            pcall(function()
                ui:SetClipboardText(text)
            end)
            -- 无论结果都输出到引擎控制台，方便从浏览器 DevTools 复制
            if originalPrint_ then
                originalPrint_("===== [调试日志导出] " .. #lines .. " 条 =====")
                originalPrint_(text)
                originalPrint_("===== [调试日志导出结束] =====")
            end
            Toast.Show("已导出 " .. #lines .. " 条日志（可从浏览器控制台复制）", { variant = "info" })
        end
    )
    bottomBtns[#bottomBtns + 1] = BuildActionBtn(
        "清空", { 255, 150, 150, 255 }, { 80, 40, 40, 200 },
        function() logs_ = {}; MarkDirty() end
    )
    bottomBtns[#bottomBtns + 1] = BuildActionBtn(
        "收起", { 200, 200, 200, 255 }, { 50, 50, 50, 200 },
        function()
            expanded_ = false
            panelRight_  = nil
            panelBottom_ = nil
            MarkDirty()
        end
    )

    local pRight  = panelRight_  or btnRight_
    local pBottom = panelBottom_ or (btnBottom_ + BTN_SIZE + 8)

    panelEl_ = UI.Panel {
        position = "absolute",
        right = pRight,
        bottom = pBottom,
        width = PANEL_WIDTH,
        height = PANEL_HEIGHT,
        pointerEvents = "auto",
        backgroundColor = { 20, 18, 14, 235 },
        borderColor = { 120, 100, 50, 180 },
        borderWidth = 1,
        borderRadius = 8,
        overflow = "hidden",
        children = {
            -- 标签栏（同时作为拖拽手柄）
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                padding = 4,
                onPanStart = function(event, widget)
                    -- 首次拖拽时初始化独立位置
                    if not panelRight_ then
                        panelRight_  = btnRight_
                        panelBottom_ = btnBottom_ + BTN_SIZE + 8
                    end
                    return true
                end,
                onPanMove = function(event, widget)
                    panelRight_  = math.max(0, panelRight_  - event.deltaX)
                    panelBottom_ = math.max(0, panelBottom_ - event.deltaY)
                    -- 直接 SetStyle 更新位置，不重建面板（避免中断手势）
                    if panelEl_ then
                        panelEl_:SetStyle({
                            right = panelRight_,
                            bottom = panelBottom_,
                        })
                    end
                end,
                onPanEnd = function(event, widget) end,
                children = {
                    BuildTabBtn("日志", "log"),
                    BuildTabBtn("数据", "data"),
                    BuildTabBtn("系统", "system"),
                },
            },
            -- 过滤状态提示（仅日志标签页）
            activeTab_ == "log" and UI.Panel {
                width = "100%",
                paddingHorizontal = 8,
                paddingVertical = 2,
                backgroundColor = showAll_ and { 50, 50, 50, 150 } or { 35, 55, 70, 150 },
                children = {
                    UI.Label {
                        text = showAll_ and "显示全部日志" or "仅显示项目日志（错误/警告始终显示）",
                        fontSize = 10,
                        fontColor = showAll_ and { 150, 150, 150, 255 } or { 130, 180, 220, 255 },
                    },
                },
            } or nil,
            -- 内容区
            UI.ScrollView {
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                flexBasis = 0,
                scrollMultiplier = Theme.scrollSensitivity,
                padding = 8,
                children = tabContent,
            },
            -- 底部操作栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "flex-end",
                padding = 4, gap = 6,
                children = bottomBtns,
            },
        },
    }
    container_:AddChild(panelEl_)
end

local function DoRebuildButton()
    if not container_ then return end
    if btnEl_ then
        container_:RemoveChild(btnEl_)
        btnEl_ = nil
    end
    if not enabled_ then return end

    btnEl_ = UI.Panel {
        position = "absolute",
        right = btnRight_,
        bottom = btnBottom_,
        width = BTN_SIZE,
        height = BTN_SIZE,
        borderRadius = BTN_SIZE / 2,
        backgroundColor = { 60, 50, 35, 220 },
        borderColor = { 150, 130, 70, 180 },
        borderWidth = 1,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "auto",
        onPanStart = function(event, widget)
            return true
        end,
        onPanMove = function(event, widget)
            btnRight_  = math.max(0, btnRight_  - event.deltaX)
            btnBottom_ = math.max(0, btnBottom_ - event.deltaY)
            -- 直接 SetStyle 更新位置，不重建（避免中断手势）
            if btnEl_ then
                btnEl_:SetStyle({ right = btnRight_, bottom = btnBottom_ })
            end
            -- 面板跟随按钮移动（未独立拖拽过时）
            if expanded_ and panelEl_ and not panelRight_ then
                panelEl_:SetStyle({
                    right = btnRight_,
                    bottom = btnBottom_ + BTN_SIZE + 8,
                })
            end
        end,
        onPanEnd = function(event, widget)
        end,
        onClick = function()
            expanded_ = not expanded_
            if not expanded_ then
                panelRight_  = nil
                panelBottom_ = nil
            end
            MarkDirty()
        end,
        children = {
            UI.Label {
                text = "调试",
                fontSize = 11,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
                pointerEvents = "none",
            },
        },
    }
    container_:AddChild(btnEl_)
end

local function FlushDirty()
    if not dirty_ then return end
    if rebuilding_ then return end
    rebuilding_ = true
    dirty_ = false

    DoRebuildButton()
    DoRebuildPanel()

    rebuilding_ = false
end

-- ============================================================================
-- 公开接口
-- ============================================================================

---@return table
function M.GetContainer()
    btnEl_ = nil
    panelEl_ = nil

    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "box-none",
    }

    if enabled_ then
        rebuilding_ = true
        DoRebuildButton()
        if expanded_ then DoRebuildPanel() end
        rebuilding_ = false
    end

    return container_
end

local refreshTimer_ = 0
function M.Update(dt)
    if not enabled_ then return end
    if expanded_ and activeTab_ ~= "log" then
        refreshTimer_ = refreshTimer_ + dt
        if refreshTimer_ >= 1.0 then
            refreshTimer_ = 0
            MarkDirty()
        end
    end
    FlushDirty()
end

return M
