-- ============================================================================
-- 《问道长生》任务系统
-- 职责：主线/每日任务进度追踪、条件检查、奖励领取
-- 设计：Can/Do 模式，进度由其他模块 NotifyAction 驱动
-- ============================================================================

local GamePlayer     = require("game_player")
local DataWorld      = require("data_world")
local GameServer     = require("game_server")
local GameBattlePass = require("game_battlepass")

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 每日任务动作映射：questId → actionType
-- ============================================================================
local DAILY_ACTIONS = {
    dq1 = "cultivate",        -- 静修
    dq2 = "gather_herb",      -- 采集灵草
    dq3 = "kill_monster",     -- 击败妖兽
    dq4 = "alchemy_success",  -- 炼丹成功
}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保任务数据结构存在
---@return table|nil
local function EnsureQuestData()
    local p = GamePlayer.Get()
    if not p then return nil end
    if not p.quests then p.quests = { daily = {}, main = {}, side = {} } end
    if not p.quests.mainClaimed then p.quests.mainClaimed = {} end
    if not p.quests.mainFlags then p.quests.mainFlags = {} end
    if not p.quests.dailyDate then p.quests.dailyDate = "" end
    if not p.quests.dailyCounters then p.quests.dailyCounters = {} end
    if not p.quests.dailyClaimed then p.quests.dailyClaimed = {} end
    return p
end

--- 检查每日任务是否需要重置（新一天）
---@param p table
local function CheckDailyReset(p)
    local today = os.date("%Y-%m-%d")
    if p.quests.dailyDate ~= today then
        p.quests.dailyDate = today
        p.quests.dailyCounters = {}
        p.quests.dailyClaimed = {}
        GamePlayer.MarkDirty()
    end
end

--- 获取每日计数器值
---@param p table
---@param actionType string
---@return number
local function GetDailyCounter(p, actionType)
    return p.quests.dailyCounters[actionType] or 0
end

--- 检查列表中是否包含指定 id
---@param list table
---@param id string
---@return boolean
local function ListContains(list, id)
    for _, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

-- ============================================================================
-- 主线任务条件检查器
-- 每个函数返回 (progress, maxProgress)
-- ============================================================================
local MAIN_CHECKERS = {
    mq1 = function(p)  -- 创角完成
        return 1, 1
    end,
    mq2 = function(p)  -- 静修1次
        local done = (p.quests and p.quests.mainFlags and p.quests.mainFlags.cultivated)
            or (p.cultivation or 0) > 0
            or #(p.cultivationLogs or {}) > 0
        return done and 1 or 0, 1
    end,
    mq3 = function(p)  -- 游历1次
        local done = #(p.bagItems or {}) > 0
            or (p.quests.mainFlags and p.quests.mainFlags.explored)
        return done and 1 or 0, 1
    end,
    mq4 = function(p)  -- 修为达到5000
        if (p.tier or 1) >= 2 then return 5000, 5000 end
        return math.min(p.cultivation or 0, 5000), 5000
    end,
    mq5 = function(p)  -- 购买任意物品
        local done = p.quests.mainFlags and p.quests.mainFlags.purchased
        return done and 1 or 0, 1
    end,
}

-- ============================================================================
-- 公开接口：动作通知
-- ============================================================================

--- 通知一个动作发生（由其他游戏模块调用）
--- actionType: "cultivate" | "gather_herb" | "kill_monster" | "alchemy_success"
---@param actionType string
---@param count? number 默认1
function M.NotifyAction(actionType, count)
    local p = EnsureQuestData()
    if not p then return end
    CheckDailyReset(p)
    count = count or 1
    p.quests.dailyCounters[actionType] = (p.quests.dailyCounters[actionType] or 0) + count
    GamePlayer.MarkDirty()

    -- 联网模式：通过 GameOps 同步计数器到 serverCloud
    if IsNetworkMode() then
        local GameOps = require("network.game_ops")
        GameOps.Request("quest_notify_action", {
            playerKey  = GameServer.GetServerKey("player"),
            actionType = actionType,
            count      = count,
        }, function(ok, data)
            if not ok then
                print("[GameQuest] NotifyAction 同步失败: " .. tostring(data and data.msg))
            end
        end)
    end
end

--- 设置主线任务标记（由其他模块调用）
---@param flag string "explored" | "purchased"
---@param value any
function M.SetMainFlag(flag, value)
    local p = EnsureQuestData()
    if not p then return end
    p.quests.mainFlags[flag] = value
    GamePlayer.MarkDirty()

    -- 联网模式：通过 GameOps 同步标记到 serverCloud
    if IsNetworkMode() then
        local GameOps = require("network.game_ops")
        GameOps.Request("quest_set_flag", {
            playerKey = GameServer.GetServerKey("player"),
            flag      = flag,
            value     = value ~= nil and value or true,
        }, function(ok, data)
            if not ok then
                print("[GameQuest] SetMainFlag 同步失败: " .. tostring(data and data.msg))
            end
        end)
    end
end

-- ============================================================================
-- 公开接口：查询
-- ============================================================================

--- 获取所有主线任务状态
---@return table[]
function M.GetMainQuests()
    local p = EnsureQuestData()
    if not p then return {} end

    local result = {}
    local prevCompleted = true  -- 主线任务顺序解锁

    for _, def in ipairs(DataWorld.MAIN_QUESTS) do
        local checker = MAIN_CHECKERS[def.id]
        local progress, maxProgress = 0, 1
        if checker then
            progress, maxProgress = checker(p)
        end

        local claimed = ListContains(p.quests.mainClaimed, def.id)

        ---@type string
        local status
        if claimed then
            status = "completed"
        elseif not prevCompleted then
            status = "locked"
        elseif progress >= maxProgress then
            status = "claimable"
        else
            status = "active"
        end

        result[#result + 1] = {
            id = def.id, name = def.name, desc = def.desc,
            reward = def.reward, rewardItems = def.rewardItems,
            progress = progress, maxProgress = maxProgress,
            status = status,
        }

        prevCompleted = claimed
    end
    return result
end

--- 获取所有每日任务状态
---@return table[]
function M.GetDailyQuests()
    local p = EnsureQuestData()
    if not p then return {} end
    CheckDailyReset(p)

    local result = {}
    for _, def in ipairs(DataWorld.DAILY_QUESTS) do
        local actionType = DAILY_ACTIONS[def.id] or "unknown"
        local progress = GetDailyCounter(p, actionType)
        local maxProgress = def.maxProgress or 1

        local claimed = ListContains(p.quests.dailyClaimed, def.id)

        ---@type string
        local status
        if claimed then
            status = "completed"
        elseif progress >= maxProgress then
            status = "claimable"
        else
            status = "active"
        end

        result[#result + 1] = {
            id = def.id, name = def.name, desc = def.desc,
            reward = def.reward, rewardItems = def.rewardItems,
            progress = math.min(progress, maxProgress),
            maxProgress = maxProgress,
            status = status,
        }
    end
    return result
end

--- 获取可领取任务总数（用于红点提示）
---@return number
function M.GetClaimableCount()
    local count = 0
    for _, q in ipairs(M.GetMainQuests()) do
        if q.status == "claimable" then count = count + 1 end
    end
    for _, q in ipairs(M.GetDailyQuests()) do
        if q.status == "claimable" then count = count + 1 end
    end
    return count
end

-- ============================================================================
-- 公开接口：领取奖励
-- ============================================================================

--- 检查是否可领取
---@param questId string
---@return boolean, string|nil
function M.CanClaim(questId)
    for _, q in ipairs(M.GetMainQuests()) do
        if q.id == questId then
            if q.status == "claimable" then return true, nil end
            return false, q.status == "completed" and "已领取" or "条件未达成"
        end
    end
    for _, q in ipairs(M.GetDailyQuests()) do
        if q.id == questId then
            if q.status == "claimable" then return true, nil end
            return false, q.status == "completed" and "已领取" or "条件未达成"
        end
    end
    return false, "未知任务"
end

--- 领取奖励
---@param questId string
---@return boolean, string
function M.DoClaim(questId)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    if not IsNetworkMode() then
        local ok, reason = M.CanClaim(questId)
        if not ok then return false, reason or "无法领取" end
    end

    local p = EnsureQuestData()
    if not p then return false, "数据未加载" end

    local def = nil
    for _, q in ipairs(DataWorld.MAIN_QUESTS) do
        if q.id == questId then def = q; break end
    end
    if not def then
        for _, q in ipairs(DataWorld.DAILY_QUESTS) do
            if q.id == questId then def = q; break end
        end
    end
    if not def then return false, "未知任务" end

    local GameOps = require("network.game_ops")
    GameOps.Request("quest_claim", {
        playerKey = GameServer.GetServerKey("player"),
        questId   = questId,
    }, function(ok2, data)
        if ok2 then
            local msg = data and data.msg or "任务奖励已领取"
            GamePlayer.AddLog(msg)
            local Toast = require("ui_toast")
            Toast.Show(msg)
            -- 日常任务完成后增加通行证经验
            if DAILY_ACTIONS[questId] then
                GameBattlePass.AddExp("dailyQuest")
            end
        else
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "领取失败", "error")
        end
        local Router = require("ui_router")
        Router.RebuildUI()
    end, { loading = true })
    return true, "领取中..."
end

return M
