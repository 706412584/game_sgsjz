-- ============================================================================
-- 《问道长生》任务处理器（服务端权威）
-- 职责：服务端验证完成条件 + 发放物品/货币奖励 + 标记已领取
-- Actions: quest_claim, quest_set_flag, quest_notify_action
-- ============================================================================

local DataWorld = require("data_world")

local M = {}
M.Actions = {}

-- ============================================================================
-- 每日任务动作映射（与客户端 game_quest.lua 保持一致）
-- ============================================================================

local DAILY_ACTIONS = {
    dq1 = "cultivate",
    dq2 = "gather_herb",
    dq3 = "kill_monster",
    dq4 = "alchemy_success",
}

-- ============================================================================
-- 服务端内存缓存：每日计数器
-- 避免 quest_notify_action 每 5 秒做整个 playerData 的读-改-写，
-- 防止覆盖其他 handler（shop_buy、item_use_pill 等）同时写入的数据。
-- 结构: questCounterCache_[compositeKey] = { date=..., counters={...} }
-- compositeKey = tostring(userId) .. ":" .. playerKey
-- ============================================================================
local questCounterCache_ = {}

-- ============================================================================
-- 主线任务条件检查器（服务端版，使用 playerData 而非 GamePlayer.Get()）
-- ============================================================================

local MAIN_CHECKERS = {
    mq1 = function(pd)  -- 创角完成
        return 1, 1
    end,
    mq2 = function(pd)  -- 静修1次
        local done = (pd.quests and pd.quests.mainFlags and pd.quests.mainFlags.cultivated)
            or (pd.cultivation or 0) > 0
            or #(pd.cultivationLogs or {}) > 0
        return done and 1 or 0, 1
    end,
    mq3 = function(pd)  -- 游历1次
        local done = #(pd.bagItems or {}) > 0
            or (pd.quests and pd.quests.mainFlags and pd.quests.mainFlags.explored)
        return done and 1 or 0, 1
    end,
    mq4 = function(pd)  -- 修为达到5000
        if (pd.tier or 1) >= 2 then return 5000, 5000 end
        -- 炼气后期(sub>=3)的 cultivationMax=5000，但服务端 cultivation 未实时同步，直接放行
        if (pd.sub or 1) >= 3 then return 5000, 5000 end
        return math.min(pd.cultivation or 0, 5000), 5000
    end,
    mq5 = function(pd)  -- 购买任意物品
        local done = pd.quests and pd.quests.mainFlags and pd.quests.mainFlags.purchased
        return done and 1 or 0, 1
    end,
}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保任务数据结构存在
---@param pd table playerData
local function EnsureQuestData(pd)
    if not pd.quests then pd.quests = { daily = {}, main = {}, side = {} } end
    if not pd.quests.mainClaimed then pd.quests.mainClaimed = {} end
    if not pd.quests.mainFlags then pd.quests.mainFlags = {} end
    if not pd.quests.dailyDate then pd.quests.dailyDate = "" end
    if not pd.quests.dailyCounters then pd.quests.dailyCounters = {} end
    if not pd.quests.dailyClaimed then pd.quests.dailyClaimed = {} end
end

--- 检查每日任务是否需要重置
---@param pd table playerData
local function CheckDailyReset(pd)
    local today = os.date("%Y-%m-%d")
    if pd.quests.dailyDate ~= today then
        pd.quests.dailyDate = today
        pd.quests.dailyCounters = {}
        pd.quests.dailyClaimed = {}
    end
end

--- 获取某玩家的内存计数器缓存（自动处理每日重置）
---@param userId any
---@param playerKey string
---@return table counters 当日计数器 { cultivate=N, ... }
local function GetCachedCounters(userId, playerKey)
    local ckey = tostring(userId) .. ":" .. playerKey
    local today = os.date("%Y-%m-%d")
    local entry = questCounterCache_[ckey]
    if not entry or entry.date ~= today then
        entry = { date = today, counters = {} }
        questCounterCache_[ckey] = entry
    end
    return entry.counters
end

--- 将内存缓存的计数器合并到 playerData.quests.dailyCounters
--- 取 max(内存值, 持久化值) 保证不丢失
---@param pd table playerData
---@param userId any
---@param playerKey string
local function MergeCountersIntoPlayerData(pd, userId, playerKey)
    EnsureQuestData(pd)
    CheckDailyReset(pd)
    local cached = GetCachedCounters(userId, playerKey)
    for action, cnt in pairs(cached) do
        local existing = pd.quests.dailyCounters[action] or 0
        pd.quests.dailyCounters[action] = math.max(existing, cnt)
    end
end

-- ============================================================================
-- 服务端内存缓存：主线任务标记（与计数器同理，避免全量写 playerData）
-- 结构: questFlagCache_[compositeKey] = { cultivated=true, explored=true, ... }
-- ============================================================================
local questFlagCache_ = {}

--- 获取某玩家的内存标记缓存
---@param userId any
---@param playerKey string
---@return table flags
local function GetCachedFlags(userId, playerKey)
    local ckey = tostring(userId) .. ":" .. playerKey
    if not questFlagCache_[ckey] then
        questFlagCache_[ckey] = {}
    end
    return questFlagCache_[ckey]
end

--- 将内存缓存的标记合并到 playerData.quests.mainFlags
---@param pd table playerData
---@param userId any
---@param playerKey string
local function MergeFlagsIntoPlayerData(pd, userId, playerKey)
    EnsureQuestData(pd)
    local cached = GetCachedFlags(userId, playerKey)
    for flag, val in pairs(cached) do
        if not pd.quests.mainFlags[flag] then
            pd.quests.mainFlags[flag] = val
        end
    end
end

--- 列表中是否包含指定 id
---@param list table
---@param id string
---@return boolean
local function ListContains(list, id)
    for _, v in ipairs(list) do
        if v == id then return true end
    end
    return false
end

--- 向 bagItems 添加物品
---@param pd table playerData
---@param itemName string
---@param count number
local function AddItemToData(pd, itemName, count)
    if not pd.bagItems then pd.bagItems = {} end
    for _, item in ipairs(pd.bagItems) do
        if item.name == itemName then
            item.count = (item.count or 1) + count
            return
        end
    end
    pd.bagItems[#pd.bagItems + 1] = { name = itemName, count = count }
end

-- ============================================================================
-- Action: quest_claim — 服务端任务领取
-- params: { playerKey: string, questId: string }
-- 返回: { msg } + sync { quests, bagItems, lingStone?, spiritStone? }
-- ============================================================================

M.Actions["quest_claim"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local questId   = params.questId

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not questId or questId == "" then
        reply(false, { msg = "缺少 questId" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    -- 查找任务定义
    ---@type table|nil
    local def = nil
    local isMain = false
    for _, q in ipairs(DataWorld.MAIN_QUESTS) do
        if q.id == questId then def = q; isMain = true; break end
    end
    if not def then
        for _, q in ipairs(DataWorld.DAILY_QUESTS) do
            if q.id == questId then def = q; break end
        end
    end
    if not def then
        reply(false, { msg = "未知任务" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            EnsureQuestData(playerData)
            CheckDailyReset(playerData)

            -- ── 已领取检查 ──
            if isMain then
                if ListContains(playerData.quests.mainClaimed, questId) then
                    reply(false, { msg = "已领取" })
                    return
                end
            else
                if ListContains(playerData.quests.dailyClaimed, questId) then
                    reply(false, { msg = "已领取" })
                    return
                end
            end

            -- ── 合并内存缓存到 playerData（确保计数器和标记最新） ──
            MergeCountersIntoPlayerData(playerData, userId, playerKey)
            MergeFlagsIntoPlayerData(playerData, userId, playerKey)

            -- ── 条件检查 ──
            if isMain then
                -- 主线任务：顺序解锁检查
                local prevCompleted = true
                for _, q in ipairs(DataWorld.MAIN_QUESTS) do
                    if q.id == questId then break end
                    prevCompleted = ListContains(playerData.quests.mainClaimed, q.id)
                end
                if not prevCompleted then
                    reply(false, { msg = "前置任务未完成" })
                    return
                end

                local checker = MAIN_CHECKERS[questId]
                if checker then
                    local progress, maxProgress = checker(playerData)
                    if progress < maxProgress then
                        reply(false, { msg = "条件未达成" })
                        return
                    end
                end
            else
                -- 每日任务：计数器检查（已合并内存缓存）
                local actionType = DAILY_ACTIONS[questId] or "unknown"
                local counter = playerData.quests.dailyCounters[actionType] or 0
                local maxProgress = def.maxProgress or 1
                if counter < maxProgress then
                    reply(false, { msg = "条件未达成" })
                    return
                end
            end

            -- ── 发放奖励 ──
            local syncFields = {}
            local rewardMsgs = {}
            -- 收集需要走 money 子系统的货币奖励
            local moneyRewards = {} -- { {currency=..., amount=...}, ... }

            if def.rewardItems then
                for itemName, count in pairs(def.rewardItems) do
                    if itemName == "灵石" then
                        moneyRewards[#moneyRewards + 1] = { currency = "lingStone", amount = count }
                        rewardMsgs[#rewardMsgs + 1] = "灵石x" .. count
                    elseif itemName == "仙石" then
                        moneyRewards[#moneyRewards + 1] = { currency = "spiritStone", amount = count }
                        rewardMsgs[#rewardMsgs + 1] = "仙石x" .. count
                    else
                        AddItemToData(playerData, itemName, count)
                        rewardMsgs[#rewardMsgs + 1] = itemName .. "x" .. count
                    end
                end
            end

            -- 标记已领取
            if isMain then
                playerData.quests.mainClaimed[#playerData.quests.mainClaimed + 1] = questId
            else
                playerData.quests.dailyClaimed[#playerData.quests.dailyClaimed + 1] = questId
            end

            -- sync quests + bagItems
            syncFields.quests   = playerData.quests
            syncFields.bagItems = playerData.bagItems

            -- 保存（不含货币，货币走 money 子系统）
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    local rewardStr = #rewardMsgs > 0
                        and table.concat(rewardMsgs, ", ") or def.reward

                    -- 发放货币奖励（链式异步）
                    local function doMoneyRewards(idx)
                        if idx > #moneyRewards then
                            -- 所有货币发放完毕，查询最新余额
                            if #moneyRewards > 0 then
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        for _, mr in ipairs(moneyRewards) do
                                            syncFields[mr.currency] = (moneys and moneys[mr.currency]) or 0
                                        end
                                        print("[QuestClaim] " .. questId
                                            .. " reward=" .. rewardStr
                                            .. " uid=" .. tostring(userId))
                                        reply(true, {
                                            msg = "完成任务「" .. def.name .. "」，获得 " .. rewardStr,
                                        }, syncFields)
                                    end,
                                    error = function()
                                        print("[QuestClaim] " .. questId
                                            .. " reward=" .. rewardStr
                                            .. " uid=" .. tostring(userId))
                                        reply(true, {
                                            msg = "完成任务「" .. def.name .. "」，获得 " .. rewardStr,
                                        }, syncFields)
                                    end,
                                })
                            else
                                print("[QuestClaim] " .. questId
                                    .. " reward=" .. rewardStr
                                    .. " uid=" .. tostring(userId))
                                reply(true, {
                                    msg = "完成任务「" .. def.name .. "」，获得 " .. rewardStr,
                                }, syncFields)
                            end
                            return
                        end

                        local mr = moneyRewards[idx]
                        serverCloud.money:Add(userId, mr.currency, mr.amount, {
                            ok = function()
                                doMoneyRewards(idx + 1)
                            end,
                            error = function(code2, reason2)
                                print("[QuestClaim] money:Add " .. mr.currency .. " 失败: " .. tostring(reason2))
                                doMoneyRewards(idx + 1)
                            end,
                        })
                    end

                    doMoneyRewards(1)
                end,
                error = function(code, reason)
                    print("[QuestClaim] 保存失败 uid=" .. tostring(userId)
                        .. " " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function(code, reason)
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: quest_set_flag — 设置主线任务标记（持久化到 serverCloud）
-- params: { playerKey: string, flag: string, value: any }
-- 用途：修炼等客户端行为需要在服务端留下持久化标记以供任务检查
-- ============================================================================

M.Actions["quest_set_flag"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local flag      = params.flag
    local value     = params.value

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not flag or flag == "" then
        reply(false, { msg = "缺少 flag" })
        return
    end

    -- 白名单：只允许设置已知的标记
    local ALLOWED_FLAGS = {
        cultivated = true,
        explored   = true,
        purchased  = true,
    }
    if not ALLOWED_FLAGS[flag] then
        reply(false, { msg = "不允许的标记: " .. tostring(flag) })
        return
    end

    -- ★ 纯内存操作，不做 serverCloud 读写，避免全量 playerData 覆盖竞态
    local flags = GetCachedFlags(userId, playerKey)

    -- 幂等：已设置过直接返回成功
    if flags[flag] then
        reply(true, {})
        return
    end

    flags[flag] = value ~= nil and value or true

    print("[QuestSetFlag] " .. flag .. "=" .. tostring(flags[flag])
        .. " uid=" .. tostring(userId) .. " (in-memory)")

    -- 不 sync quests 回客户端（同 quest_notify_action 的理由）
    reply(true, {})
end

-- ============================================================================
-- Action: quest_notify_action — 持久化每日任务计数器
-- params: { playerKey: string, actionType: string, count?: number }
-- 用途：客户端完成动作后同步计数器到 serverCloud，确保领取时服务端验证通过
-- ============================================================================

--- 每日动作白名单（与 DAILY_ACTIONS 值集合一致）
local ALLOWED_ACTIONS = {
    cultivate       = true,
    gather_herb     = true,
    kill_monster    = true,
    alchemy_success = true,
}

M.Actions["quest_notify_action"] = function(userId, params, reply)
    local playerKey  = params.playerKey
    local actionType = params.actionType
    local count      = params.count or 1

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not actionType or not ALLOWED_ACTIONS[actionType] then
        reply(false, { msg = "不允许的动作类型: " .. tostring(actionType) })
        return
    end

    -- ★ 纯内存操作，不做 serverCloud 读写，彻底消除竞态覆盖风险
    local counters = GetCachedCounters(userId, playerKey)
    counters[actionType] = (counters[actionType] or 0) + count

    print("[QuestNotifyAction] " .. actionType .. "+"
        .. tostring(count) .. " → " .. tostring(counters[actionType])
        .. " uid=" .. tostring(userId) .. " (in-memory)")

    -- 不 sync quests 回客户端：ApplySync 会整体替换 playerData_.quests，
    -- 丢失 mainClaimed/dailyClaimed 等字段。客户端本地已维护自己的计数器。
    reply(true, {})
end

return M
