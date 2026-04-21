-- ============================================================================
-- ui_reddot.lua -- 红点通知系统
-- 管理底部标签栏和工具栏按钮上的红点(Badge dot)提示
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")

local M = {}

-- ========== 红点节点注册 ==========
-- 每个节点: { widget, badge, conditionFn }
---@type table<string, {widget: table, badge: table, conditionFn: fun(): boolean}>
local nodes_ = {}

-- 刷新间隔控制
local refreshTimer_ = 0
local REFRESH_INTERVAL = 3.0  -- 每3秒刷新

-- ========== 条件判断函数 ==========

--- 炼丹页: 有已解锁配方且材料足够
local function checkCraft()
    local realmIdx = State.GetRealmIndex()
    for i, prod in ipairs(Config.Products) do
        if Config.IsProductUnlocked(i, realmIdx) then
            local mat = State.state.materials[prod.materialId] or 0
            if mat >= prod.materialCost then
                return true
            end
        end
    end
    return false
end

--- 灵田页: 有成熟可收获的作物
local function checkField()
    local Field = require("game_field")
    return Field.HasHarvestable()
end

--- 升级页: 灵石够升级摊位 或 可突破境界
local upgradeDbgTimer_ = 0
local function checkUpgrade()
    -- 摊位升级
    local curLevel = State.state.stallLevel
    local stallCanUp = false
    if curLevel < #Config.StallLevels then
        local nextCfg = Config.StallLevels[curLevel + 1]
        stallCanUp = State.state.lingshi >= nextCfg.cost
        if stallCanUp then
            return true
        end
    end
    -- 境界突破
    local canBreak = State.CanBreakthrough()

    -- 诊断日志(节流: 每10秒打印一次)
    upgradeDbgTimer_ = upgradeDbgTimer_ + 3  -- Refresh 每3秒调一次
    if upgradeDbgTimer_ >= 10 then
        upgradeDbgTimer_ = 0
        print("[RedDot][checkUpgrade] stallLv=" .. tostring(curLevel)
            .. " maxLv=" .. tostring(#Config.StallLevels)
            .. " lingshi=" .. tostring(State.state.lingshi)
            .. " stallCanUp=" .. tostring(stallCanUp)
            .. " canBreak=" .. tostring(canBreak))
    end

    if canBreak then return true end
    return false
end

--- 邮箱: 有未读邮件
local function checkMail()
    local Mail = require("ui_mail")
    return Mail.GetUnreadCount() > 0
end

--- 聊天: 有未读消息
local function checkChat()
    local Chat = require("ui_chat")
    return Chat.GetUnreadCount() > 0
end

--- 每日任务: 有可领取奖励
local function checkDaily()
    local Daily = require("ui_daily")
    return Daily.HasClaimable()
end

--- 秘境: 无冷却且有足够灵石进入至少一个秘境
local function checkDungeon()
    local Dungeon = require("ui_dungeon")
    return Dungeon.CanExplore()
end

-- 默认条件映射
local DEFAULT_CONDITIONS = {
    craft   = checkCraft,
    field   = checkField,
    upgrade = checkUpgrade,
    mail    = checkMail,
    chat    = checkChat,
    daily   = checkDaily,
    dungeon = checkDungeon,
}

-- ========== 公开 API ==========

--- 绑定红点到一个按钮控件
---@param nodeId string 节点标识 (如 "craft", "stall")
---@param widget table UI.Button 或 UI.Panel 控件
function M.Bind(nodeId, widget)
    -- 创建红点: 用 absolute 定位到按钮右上角外围，避免被挤到按钮间隙
    local badge = UI.Panel {
        position = "absolute",
        top = -3,
        right = 2,
        width = 8,
        height = 8,
        borderRadius = 4,
        backgroundColor = Config.Colors.red,
        pointerEvents = "none",
    }
    badge:Hide()
    widget:AddChild(badge)

    local condFn = DEFAULT_CONDITIONS[nodeId] or function() return false end
    nodes_[nodeId] = {
        widget = widget,
        badge = badge,
        conditionFn = condFn,
    }
end

--- 自定义某个节点的条件判断函数
---@param nodeId string
---@param fn fun(): boolean
function M.SetCondition(nodeId, fn)
    if nodes_[nodeId] then
        nodes_[nodeId].conditionFn = fn
    end
end

--- 刷新单个节点的红点显示
---@param nodeId string
function M.Refresh(nodeId)
    local node = nodes_[nodeId]
    if not node then return end
    local show = false
    local ok, result = pcall(node.conditionFn)
    if ok then show = result end
    if show then
        node.badge:Show()
    else
        node.badge:Hide()
    end
end

--- 刷新所有已注册节点
function M.RefreshAll()
    for id, _ in pairs(nodes_) do
        M.Refresh(id)
    end
end

--- 驱动定时刷新(在 HandleUpdate 中调用)
---@param dt number
function M.Update(dt)
    refreshTimer_ = refreshTimer_ + dt
    if refreshTimer_ >= REFRESH_INTERVAL then
        refreshTimer_ = refreshTimer_ - REFRESH_INTERVAL
        M.RefreshAll()
    end
end

return M
