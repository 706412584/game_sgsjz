-- ============================================================================
-- 《问道长生》道心试炼系统（客户端）
-- 职责：心魔挑战 & 红尘历练的 Can/Do 逻辑
-- 心魔挑战：战斗型，客户端预计算战斗过程供 UI 可视化，服务端权威结算
-- 红尘历练：选择题型，客户端展示场景+选项，服务端验证+发放奖励
-- ============================================================================

local GamePlayer   = require("game_player")
local DataSkills   = require("data_skills")
local DataFormulas = require("data_formulas")
local DataWorld    = require("data_world")

local M = {}

local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 查询接口
-- ============================================================================

--- 获取道心试炼每日使用次数
---@param trialId string "xinmo" | "hongchen"
---@return number used, number limit
function M.GetDailyCount(trialId)
    local p = GamePlayer.Get()
    if not p then return 0, 0 end

    local def = DataSkills.GetDaoTrial(trialId)
    if not def then return 0, 0 end

    local limit = def.dailyLimit or 2
    local today = os.date("%Y-%m-%d")
    local dd = p.daoTrialDaily
    if type(dd) ~= "table" or dd.date ~= today then
        return 0, limit
    end
    local counts = dd.counts or {}
    return counts[trialId] or 0, limit
end

--- 获取所有道心试炼列表（含状态信息）
---@return table[]
function M.GetAllDaoTrials()
    local p = GamePlayer.Get()
    if not p then return {} end
    local playerTier = p.tier or 1

    local result = {}
    for _, def in ipairs(DataSkills.DAO_TRIALS) do
        local unlocked = true
        if def.unlockTier and playerTier < def.unlockTier then
            unlocked = false
        end

        local used, limit = M.GetDailyCount(def.id)
        local remain = math.max(0, limit - used)

        result[#result + 1] = {
            id         = def.id,
            name       = def.name,
            type       = def.type,
            desc       = def.desc,
            unlocked   = unlocked,
            unlockTier = def.unlockTier,
            dailyUsed  = used,
            dailyLimit = limit,
            dailyRemain = remain,
            baseReward = def.baseReward or 0,
            bonusPerTier = def.bonusPerTier or 0,
        }
    end
    return result
end

--- 检查是否可以进行道心试炼
---@param trialId string
---@return boolean, string|nil
function M.CanChallenge(trialId)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local def = DataSkills.GetDaoTrial(trialId)
    if not def then return false, "未知试炼" end

    local playerTier = p.tier or 1
    if def.unlockTier and playerTier < def.unlockTier then
        return false, "境界不足"
    end

    local used, limit = M.GetDailyCount(trialId)
    if used >= limit then
        return false, "今日次数已用尽（" .. limit .. "次/天）"
    end

    -- 检查每日道心上限
    local today = os.date("%Y-%m-%d")
    local dd = p.daoDaily
    if type(dd) == "table" and dd.date == today then
        local cap = DataSkills.GetDailyDaoHeartCap(playerTier)
        if (dd.daoGained or 0) >= cap then
            return false, "今日道心获取已达上限"
        end
    end

    return true, nil
end

-- ============================================================================
-- 心魔挑战：客户端预计算战斗数据（供 UI 播放动画）
-- ============================================================================

--- 构造心魔属性（与服务端一致）
---@param playerData table
---@return table
local function MakeDemon(playerData)
    local tier = playerData.tier or 1
    local scale = 0.8 + tier * 0.05
    return {
        name    = "心魔",
        attack  = math.floor((playerData.attack or 30) * scale),
        defense = math.floor((playerData.defense or 10) * scale),
        hp      = math.floor((playerData.hp or 800) * scale),
        hit     = math.min(95, 80 + tier),
        dodge   = math.min(30, 5 + tier * 2),
        crit    = math.min(25, 5 + tier),
    }
end

--- 客户端预计算心魔战斗（返回逐回合数据，供 ui_trial 复用战斗可视化）
---@return table|nil result, string|nil err
function M.PrepareXinmo()
    local ok, reason = M.CanChallenge("xinmo")
    if not ok then return nil, reason end

    local p = GamePlayer.Get()
    if not p then return nil, "数据未加载" end

    local demon = MakeDemon(p)

    -- 逐回合战斗模拟（与 game_trial.lua RunFight 保持一致结构）
    local pAtk   = p.attack or 30
    local pDef   = p.defense or 10
    local pHP    = p.hp or 800
    local pHPMax = p.hpMax or pHP
    local pCrit  = p.crit or 5
    local pHit   = p.hit or 90
    local pDodge = p.dodge or 5

    local eHP    = demon.hp
    local eHPMax = demon.hp
    local maxRounds = 20

    local roundsData = {}
    local win = false
    local finished = false

    for r = 1, maxRounds do
        if finished then break end
        local round = {
            num = r,
            playerAction = nil,
            enemyAction = nil,
            playerHP = 0, playerHPMax = pHPMax,
            enemyHP = 0, enemyHPMax = eHPMax,
            finished = false, win = false,
        }

        -- 玩家攻击
        local pr = DataFormulas.ResolveAttack(
            { attack = pAtk, hit = pHit, crit = pCrit, skillAtkBonus = 0 },
            { defense = demon.defense, dodge = demon.dodge or 0, hp = eHP }
        )
        if pr.hit then
            eHP = eHP - pr.damage
            round.playerAction = { hit = true, crit = pr.crit, damage = pr.damage }
        else
            round.playerAction = { hit = false, crit = false, damage = 0 }
        end

        if eHP <= 0 then
            eHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = true
            roundsData[#roundsData + 1] = round
            win = true; finished = true
            goto nextRound
        end

        -- 心魔攻击
        local er = DataFormulas.ResolveAttack(
            { attack = demon.attack, hit = demon.hit or 85, crit = demon.crit or 5, skillAtkBonus = 0 },
            { defense = pDef, dodge = pDodge, hp = pHP }
        )
        if er.hit then
            pHP = pHP - er.damage
            round.enemyAction = { hit = true, crit = er.crit, damage = er.damage }
        else
            round.enemyAction = { hit = false, crit = false, damage = 0 }
        end

        if pHP <= 0 then
            pHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = false
            roundsData[#roundsData + 1] = round
            win = false; finished = true
            goto nextRound
        end

        round.playerHP = pHP; round.enemyHP = eHP
        roundsData[#roundsData + 1] = round

        ::nextRound::
    end

    local tier = p.tier or 1
    local def = DataSkills.GetDaoTrial("xinmo")
    local expectedReward = win
        and ((def.baseReward or 3) + (def.bonusPerTier or 1) * tier)
        or 1

    return {
        trialId   = "xinmo",
        trialName = "心魔挑战",
        trialType = "dao_xinmo",
        type      = "心魔",  -- 用于 ui_trial 类型识别
        fights    = {
            {
                floor  = 1,
                enemy  = demon,
                win    = win,
                log    = win and "战胜心魔" or "败于心魔",
                rounds = roundsData,
                monsterImg = nil,  -- 心魔无图片，UI 用文字替代
            },
        },
        cleared        = win and 1 or 0,
        reward         = 0,  -- 道心试炼不发灵石
        expectedDao    = expectedReward,
        win            = win,
    }, nil
end

--- 结算心魔挑战（调用服务端）
---@param callback function(ok, data)
function M.SettleXinmo(callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, { msg = onlineErr }) end
        return
    end

    local GameOps    = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("dao_trial_xinmo", {
        playerKey = GameServer.GetServerKey("player"),
    }, function(ok2, data)
        if ok2 then
            local msg = data and data.summary or "心魔挑战完成"
            GamePlayer.AddLog(msg)
            GamePlayer.MarkDirty()
        end
        if callback then callback(ok2, data) end
    end, { loading = true })
end

-- ============================================================================
-- 红尘历练：场景+选择题
-- ============================================================================

--- 获取一个随机红尘场景（客户端本地，用于 UI 展示）
---@return table scene { id, desc, options[] }
function M.GetRandomScene()
    return DataSkills.GetRandomHongchenScene()
end

--- 提交红尘历练选择（调用服务端）
---@param optionIdx number 1-based
---@param callback function(ok, data)
function M.SettleHongchen(optionIdx, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, { msg = onlineErr }) end
        return
    end

    local GameOps    = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("dao_trial_hongchen", {
        playerKey = GameServer.GetServerKey("player"),
        optionIdx = optionIdx,
    }, function(ok2, data)
        if ok2 then
            local msg = data and data.summary or "红尘历练完成"
            GamePlayer.AddLog(msg)
            GamePlayer.MarkDirty()
        end
        if callback then callback(ok2, data) end
    end, { loading = true })
end

--- 检查是否有可用的道心试炼（红点用）
---@return boolean
function M.HasAvailable()
    for _, def in ipairs(DataSkills.DAO_TRIALS) do
        local can = M.CanChallenge(def.id)
        if can then return true end
    end
    return false
end

return M
