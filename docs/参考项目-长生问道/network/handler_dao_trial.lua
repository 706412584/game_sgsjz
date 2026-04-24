-- ============================================================================
-- 《问道长生》道心试炼处理器（服务端权威）
-- 职责：心魔挑战（战斗型）+ 红尘历练（选择题型）— 产出道心
-- Actions: dao_trial_xinmo, dao_trial_hongchen
-- ============================================================================

local DataSkills   = require("data_skills")
local DataFormulas = require("data_formulas")

local M = {}
M.Actions = {}

-- ============================================================================
-- 工具函数
-- ============================================================================

local function GetTodayStr()
    return os.date("%Y-%m-%d")
end

--- 获取或重置每日道心追踪数据（复用 handler_dao 的结构）
local function GetDaoDaily(playerData)
    local today = GetTodayStr()
    local dd = playerData.daoDaily
    if type(dd) ~= "table" or dd.date ~= today then
        dd = { date = today, freeUsed = 0, daoGained = 0 }
        playerData.daoDaily = dd
    end
    return dd
end

--- 检查每日道心上限，返回实际可获得量
local function ClampDaoGain(playerData, rawGain)
    local tier = playerData.tier or 1
    local cap = DataSkills.GetDailyDaoHeartCap(tier)
    local dd = GetDaoDaily(playerData)
    local remaining = math.max(0, cap - (dd.daoGained or 0))
    return math.min(rawGain, remaining)
end

--- 记录每日道心获取
local function RecordDaoGain(playerData, amount)
    if amount <= 0 then return end
    local dd = GetDaoDaily(playerData)
    dd.daoGained = (dd.daoGained or 0) + amount
end

--- 获取/重置道心试炼每日次数（复用 trialDailyLog 但使用独立 key 前缀）
local function GetDaoTrialCount(playerData, trialId)
    local today = GetTodayStr()
    playerData.daoTrialDaily = playerData.daoTrialDaily or {}
    if playerData.daoTrialDaily.date ~= today then
        playerData.daoTrialDaily = { date = today, counts = {} }
    end
    local counts = playerData.daoTrialDaily.counts or {}
    return counts[trialId] or 0
end

local function RecordDaoTrialCount(playerData, trialId)
    local dd = playerData.daoTrialDaily
    dd.counts = dd.counts or {}
    dd.counts[trialId] = (dd.counts[trialId] or 0) + 1
end

--- 服务端简化战斗模拟
local function RunFight(pAtk, pDef, pHP, pCrit, pHit, pDodge, enemy)
    local eHP = enemy.hp
    local maxRounds = 20

    for _ = 1, maxRounds do
        -- 玩家攻击
        local pr = DataFormulas.ResolveAttack(
            { attack = pAtk, hit = pHit, crit = pCrit, skillAtkBonus = 0 },
            { defense = enemy.defense, dodge = enemy.dodge or 0, hp = eHP }
        )
        if pr.hit then eHP = eHP - pr.damage end
        if eHP <= 0 then return true end

        -- 心魔攻击
        local er = DataFormulas.ResolveAttack(
            { attack = enemy.attack, hit = enemy.hit or 85, crit = enemy.crit or 5, skillAtkBonus = 0 },
            { defense = pDef, dodge = pDodge, hp = pHP }
        )
        if er.hit then pHP = pHP - er.damage end
        if pHP <= 0 then return false end
    end

    return false -- 回合耗尽视为失败
end

-- ============================================================================
-- Action: dao_trial_xinmo — 心魔挑战
-- params: { playerKey: string }
-- 返回: { win, daoGain, summary } + sync { daoHeart, daoDaily, daoTrialDaily }
-- ============================================================================

M.Actions["dao_trial_xinmo"] = function(userId, params, reply)
    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    local trialDef = DataSkills.GetDaoTrial("xinmo")
    if not trialDef then
        reply(false, { msg = "心魔挑战配置缺失" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据读取失败" })
                return
            end

            -- 境界检查
            local tier = playerData.tier or 1
            if trialDef.unlockTier and tier < trialDef.unlockTier then
                reply(false, { msg = "境界不足，无法进行心魔挑战" })
                return
            end

            -- 每日次数检查
            local dailyLimit = trialDef.dailyLimit or 2
            local usedCount = GetDaoTrialCount(playerData, "xinmo")
            if usedCount >= dailyLimit then
                reply(false, { msg = "今日心魔挑战次数已用尽（" .. dailyLimit .. "次/天）" })
                return
            end

            -- 每日道心上限检查
            local dd = GetDaoDaily(playerData)
            local daoCap = DataSkills.GetDailyDaoHeartCap(tier)
            if (dd.daoGained or 0) >= daoCap then
                reply(false, { msg = "今日道心获取已达上限" })
                return
            end

            -- 记录次数
            RecordDaoTrialCount(playerData, "xinmo")

            -- 构造心魔：属性按玩家比例缩放
            local scale = 0.8 + tier * 0.05  -- tier1=0.85, tier10=1.30
            local demon = {
                name    = "心魔",
                attack  = math.floor((playerData.attack or 30) * scale),
                defense = math.floor((playerData.defense or 10) * scale),
                hp      = math.floor((playerData.hp or 800) * scale),
                hit     = math.min(95, 80 + tier),
                dodge   = math.min(30, 5 + tier * 2),
                crit    = math.min(25, 5 + tier),
            }

            -- 战斗
            local pAtk   = playerData.attack or 30
            local pDef   = playerData.defense or 10
            local pHP    = playerData.hp or 800
            local pCrit  = playerData.crit or 5
            local pHit   = playerData.hit or 90
            local pDodge = playerData.dodge or 5

            local win = RunFight(pAtk, pDef, pHP, pCrit, pHit, pDodge, demon)

            -- 计算道心奖励
            local rawReward = 0
            if win then
                rawReward = (trialDef.baseReward or 3) + (trialDef.bonusPerTier or 1) * tier
            else
                -- 失败也给少量道心（磨砺心志）
                rawReward = 1
            end
            local daoGain = ClampDaoGain(playerData, rawReward)

            -- 写入道心
            playerData.daoHeart = (playerData.daoHeart or 0) + daoGain
            RecordDaoGain(playerData, daoGain)

            -- 构建结果消息
            local summary
            if win then
                summary = "心魔挑战胜利！战胜心魔，道心+" .. daoGain
            else
                summary = "心魔挑战败北。心魔的力量超乎想象，道心+" .. daoGain
            end

            -- 保存
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[DaoTrialXinmo] uid=" .. tostring(userId)
                        .. " win=" .. tostring(win)
                        .. " daoGain=" .. daoGain
                        .. " tier=" .. tier)

                    reply(true, {
                        win      = win,
                        daoGain  = daoGain,
                        summary  = summary,
                        demonScale = scale,
                        remain   = dailyLimit - (usedCount + 1),
                    }, {
                        daoHeart      = playerData.daoHeart,
                        daoDaily      = playerData.daoDaily,
                        daoTrialDaily = playerData.daoTrialDaily,
                    })
                end,
                error = function(code, reason)
                    print("[DaoTrialXinmo] Set失败 uid=" .. tostring(userId)
                        .. " " .. tostring(reason))
                    reply(false, { msg = "保存失败，请重试" })
                end,
            })
        end,
        error = function(code, reason)
            print("[DaoTrialXinmo] Get失败 uid=" .. tostring(userId)
                .. " " .. tostring(reason))
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: dao_trial_hongchen — 红尘历练
-- params: { playerKey: string, optionIdx: number }
-- 返回: { daoGain, scene, chosenOption, summary } + sync { daoHeart, daoDaily, daoTrialDaily }
-- ============================================================================

M.Actions["dao_trial_hongchen"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local optionIdx = params.optionIdx  -- 1-based

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not optionIdx or type(optionIdx) ~= "number" then
        reply(false, { msg = "缺少选项索引" })
        return
    end

    local trialDef = DataSkills.GetDaoTrial("hongchen")
    if not trialDef then
        reply(false, { msg = "红尘历练配置缺失" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据读取失败" })
                return
            end

            -- 境界检查
            local tier = playerData.tier or 1
            if trialDef.unlockTier and tier < trialDef.unlockTier then
                reply(false, { msg = "境界不足，无法进行红尘历练" })
                return
            end

            -- 每日次数检查
            local dailyLimit = trialDef.dailyLimit or 3
            local usedCount = GetDaoTrialCount(playerData, "hongchen")
            if usedCount >= dailyLimit then
                reply(false, { msg = "今日红尘历练次数已用尽（" .. dailyLimit .. "次/天）" })
                return
            end

            -- 每日道心上限检查
            local dd = GetDaoDaily(playerData)
            local daoCap = DataSkills.GetDailyDaoHeartCap(tier)
            if (dd.daoGained or 0) >= daoCap then
                reply(false, { msg = "今日道心获取已达上限" })
                return
            end

            -- 记录次数
            RecordDaoTrialCount(playerData, "hongchen")

            -- 服务端随机选择场景（防止客户端作弊）
            local scene = DataSkills.GetRandomHongchenScene()
            if not scene or not scene.options then
                reply(false, { msg = "场景数据异常" })
                return
            end

            -- 验证选项索引
            if optionIdx < 1 or optionIdx > #scene.options then
                reply(false, { msg = "无效选项" })
                return
            end

            local chosen = scene.options[optionIdx]
            local rawReward = (chosen.daoHeart or 0) + math.floor((trialDef.bonusPerTier or 1) * tier * 0.3)
            local daoGain = ClampDaoGain(playerData, rawReward)

            -- 写入道心
            playerData.daoHeart = (playerData.daoHeart or 0) + daoGain
            RecordDaoGain(playerData, daoGain)

            local summary = chosen.msg .. "（道心+" .. daoGain .. "）"

            -- 保存
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[DaoTrialHongchen] uid=" .. tostring(userId)
                        .. " scene=" .. scene.id
                        .. " option=" .. optionIdx
                        .. " daoGain=" .. daoGain
                        .. " tier=" .. tier)

                    reply(true, {
                        daoGain      = daoGain,
                        sceneId      = scene.id,
                        sceneDesc    = scene.desc,
                        chosenIdx    = optionIdx,
                        chosenText   = chosen.text,
                        resultMsg    = chosen.msg,
                        summary      = summary,
                        remain       = dailyLimit - (usedCount + 1),
                    }, {
                        daoHeart      = playerData.daoHeart,
                        daoDaily      = playerData.daoDaily,
                        daoTrialDaily = playerData.daoTrialDaily,
                    })
                end,
                error = function(code, reason)
                    print("[DaoTrialHongchen] Set失败 uid=" .. tostring(userId)
                        .. " " .. tostring(reason))
                    reply(false, { msg = "保存失败，请重试" })
                end,
            })
        end,
        error = function(code, reason)
            print("[DaoTrialHongchen] Get失败 uid=" .. tostring(userId)
                .. " " .. tostring(reason))
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
