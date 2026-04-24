-- ============================================================================
-- 《问道长生》试炼处理器（服务端权威）
-- 职责：服务端独立模拟战斗 + 计算奖励 + 更新进度
-- Actions: trial_challenge
-- ============================================================================

local DataWorld    = require("data_world")
local DataFormulas = require("data_formulas")

local M = {}
M.Actions = {}

-- ============================================================================
-- 常量（与客户端 game_trial.lua 保持一致）
-- ============================================================================

local FLOOR_SCALE = { atk = 5, def = 3, hp = 40 }

local REWARD_PER_FLOOR = 15
local REWARD_PER_WAVE  = 20
local REWARD_PER_KILL  = 10

local MIJING_MAX_ROUNDS = 30

-- ============================================================================
-- 内部工具
-- ============================================================================

---@param floor number
---@param baseName string
---@return table
local function MakeEnemy(floor, baseName)
    return {
        name    = baseName .. "（第" .. floor .. "层）",
        attack  = 10 + floor * FLOOR_SCALE.atk,
        defense = 5  + floor * FLOOR_SCALE.def,
        hp      = 50 + floor * FLOOR_SCALE.hp,
        hit     = 85,
        dodge   = math.min(30, 5 + math.floor(floor / 5)),
        crit    = math.min(25, 3 + math.floor(floor / 8)),
    }
end

---@return string
local function RandomMonsterName()
    local monsters = DataWorld.MONSTERS
    if #monsters == 0 then return "妖兽" end
    return monsters[math.random(1, #monsters)].name
end

--- 服务端战斗模拟（简化版，不返回逐回合数据）
---@param pAtk number
---@param pDef number
---@param pHP number
---@param pCrit number
---@param pHit number
---@param pDodge number
---@param enemy table
---@return boolean win
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

        -- 敌方攻击
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
-- Action: trial_challenge — 服务端试炼挑战
-- params: { playerKey: string, trialId: string }
-- 返回: { cleared, reward, summary } + sync { trials, lingStone }
-- ============================================================================

M.Actions["trial_challenge"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local trialId   = params.trialId

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not trialId or trialId == "" then
        reply(false, { msg = "缺少 trialId" })
        return
    end

    local def = DataWorld.GetTrial(trialId)
    if not def then
        reply(false, { msg = "未知试炼" })
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
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            -- 校验解锁
            if def.unlockTier and (playerData.tier or 1) < def.unlockTier then
                reply(false, { msg = "需要达到更高境界才能解锁" })
                return
            end
            if (playerData.hp or 0) <= 0 then
                reply(false, { msg = "气血耗尽，无法挑战" })
                return
            end

            -- 每日试炼次数限制（每种试炼每天最多挑战 3 次）
            local DAILY_LIMIT = 3
            local today = os.date("%Y-%m-%d")
            playerData.trialDailyLog = playerData.trialDailyLog or {}
            if playerData.trialDailyLog.date ~= today then
                playerData.trialDailyLog = { date = today, counts = {} }
            end
            local counts = playerData.trialDailyLog.counts or {}
            local trialCount = counts[trialId] or 0
            if trialCount >= DAILY_LIMIT then
                reply(false, { msg = "今日" .. def.name .. "挑战次数已耗尽（" .. DAILY_LIMIT .. "次/天），明日重置" })
                return
            end
            -- 记录本次挑战（先更新计数，保证即使后续保存失败也不会重刷）
            counts[trialId] = trialCount + 1
            playerData.trialDailyLog.counts = counts

            -- 确保 trials 数据
            if not playerData.trials then playerData.trials = {} end

            -- 提取战斗属性
            local pAtk   = playerData.attack or 30
            local pDef   = playerData.defense or 10
            local pHP    = playerData.hp or 800
            local pCrit  = playerData.crit or 5
            local pHit   = playerData.hit or 90
            local pDodge = playerData.dodge or 5

            local cleared = 0
            local reward  = 0
            local summary = ""

            -- ── 闯关 ──
            if def.type == "闯关" then
                local startFloor = (playerData.trials[trialId] or 0) + 1
                local maxFloor   = def.maxFloor or 100
                local maxAttempt = 5

                for f = startFloor, math.min(startFloor + maxAttempt - 1, maxFloor) do
                    local win = RunFight(pAtk, pDef, pHP, pCrit, pHit, pDodge,
                        MakeEnemy(f, RandomMonsterName()))
                    if win then
                        cleared = cleared + 1
                        playerData.trials[trialId] = f
                    else
                        break
                    end
                end

                reward = cleared * REWARD_PER_FLOOR
                local best = playerData.trials[trialId] or 0
                if cleared > 0 then
                    summary = def.name .. "：闯过" .. cleared .. "层（当前第"
                        .. best .. "层），获得灵石" .. reward
                else
                    summary = def.name .. "：挑战失败，止步第" .. startFloor .. "层"
                end

            -- ── 生存 ──
            elseif def.type == "生存" then
                local wave = 0
                local maxWaves = 50
                while wave < maxWaves do
                    wave = wave + 1
                    local win = RunFight(pAtk, pDef, pHP, pCrit, pHit, pDodge,
                        MakeEnemy(wave, RandomMonsterName()))
                    if not win then break end
                end

                cleared = wave
                reward  = wave * REWARD_PER_WAVE
                local prevBest = playerData.trials[trialId] or 0
                if cleared > prevBest then
                    playerData.trials[trialId] = cleared
                end
                local best = playerData.trials[trialId] or cleared
                summary = def.name .. "：坚持到第" .. cleared .. "波（最佳第"
                    .. best .. "波），获得灵石" .. reward

            -- ── 限时击杀 ──
            elseif def.type == "限时" then
                local kills = 0
                local difficulty = 1
                for _ = 1, MIJING_MAX_ROUNDS do
                    local win = RunFight(pAtk, pDef, pHP, pCrit, pHit, pDodge,
                        MakeEnemy(difficulty, RandomMonsterName()))
                    if win then
                        kills = kills + 1
                        difficulty = difficulty + 1
                    else
                        break
                    end
                end

                cleared = kills
                reward  = kills * REWARD_PER_KILL
                local prevBest = playerData.trials[trialId] or 0
                if kills > prevBest then
                    playerData.trials[trialId] = kills
                end
                local best = playerData.trials[trialId] or kills
                summary = def.name .. "：击杀" .. kills .. "只（最高"
                    .. best .. "只），获得灵石" .. reward
            end

            -- 保存试炼进度（不含灵石，灵石走 money 子系统）
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    -- 发放灵石（通过 money 原子操作）
                    local function finishReply(lingBalance)
                        print("[TrialChallenge] " .. trialId
                            .. " type=" .. def.type
                            .. " cleared=" .. cleared
                            .. " reward=" .. reward
                            .. " uid=" .. tostring(userId))

                        reply(true, {
                            cleared = cleared,
                            reward  = reward,
                            summary = summary,
                        }, {
                            trials    = playerData.trials,
                            lingStone = lingBalance,
                        })
                    end

                    if reward > 0 then
                        serverCloud.money:Add(userId, "lingStone", reward, {
                            ok = function()
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        finishReply((moneys and moneys["lingStone"]) or 0)
                                    end,
                                    error = function()
                                        finishReply(nil)
                                    end,
                                })
                            end,
                            error = function(code2, reason2)
                                print("[TrialChallenge] money:Add 失败 uid=" .. tostring(userId)
                                    .. " " .. tostring(reason2))
                                finishReply(nil)
                            end,
                        })
                    else
                        finishReply(nil)
                    end
                end,
                error = function(code, reason)
                    print("[TrialChallenge] 保存失败 uid=" .. tostring(userId)
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

return M
