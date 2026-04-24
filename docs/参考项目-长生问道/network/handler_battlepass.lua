-- ============================================================================
-- 《问道长生》通行证处理器
-- Actions: battlepass_buy_premium (购买高级通行证),
--          battlepass_claim_reward (领取等级奖励),
--          battlepass_add_exp (增加经验)
-- 数据存储在 playerData.battlePassData 中，按赛季重置
-- 注意：购买走模拟RMB流程（与月卡相同，生产环境应由支付回调触发）
-- ============================================================================

local GameServer = require("game_server")
local DataMon    = require("data_monetization")

local M = {}
M.Actions = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 赛季参考纪元（2026-01-01 00:00:00 UTC）
local SEASON_EPOCH = os.time({ year = 2026, month = 1, day = 1, hour = 0, min = 0, sec = 0 })

--- 获取当前赛季 ID（每 seasonDays 天轮换一次）
---@return string  例: "S1", "S2", ...
local function GetCurrentSeasonId()
    local elapsed = os.time() - SEASON_EPOCH
    local days = DataMon.BATTLE_PASS.seasonDays
    local idx = math.floor(elapsed / (days * 86400))
    return "S" .. (idx + 1)
end

--- 获取当前赛季剩余天数
---@return number
local function GetSeasonRemainDays()
    local elapsed = os.time() - SEASON_EPOCH
    local days = DataMon.BATTLE_PASS.seasonDays
    local seasonSec = days * 86400
    local inSeason = elapsed % seasonSec
    local remain = seasonSec - inSeason
    return math.ceil(remain / 86400)
end

--- 确保通行证数据存在，赛季变更时自动重置
---@param pd table playerData
---@return table battlePassData
local function EnsureBPData(pd)
    local curSeason = GetCurrentSeasonId()
    if not pd.battlePassData or pd.battlePassData.seasonId ~= curSeason then
        pd.battlePassData = {
            seasonId    = curSeason,
            exp         = 0,
            isPremium   = false,
            claimedFree = {},
            claimedPaid = {},
        }
    end
    return pd.battlePassData
end

--- 根据经验值计算等级
---@param exp number
---@return number
local function GetLevel(exp)
    local bp = DataMon.BATTLE_PASS
    return math.min(math.floor(exp / bp.expPerLevel), bp.maxLevel)
end

-- ============================================================================
-- Action: battlepass_buy_premium — 购买高级通行证（模拟RMB支付）
-- params: {}
-- ============================================================================

M.Actions["battlepass_buy_premium"] = function(userId, params, reply)
    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        playerKey = GameServer.GetServerKey("player")
    end
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local pd = scores and scores[playerKey]
            if type(pd) ~= "table" then
                return reply(false, { msg = "角色数据不存在" })
            end

            local bpData = EnsureBPData(pd)

            if bpData.isPremium then
                return reply(false, { msg = "本赛季已拥有高级通行证" })
            end

            -- 激活高级通行证
            bpData.isPremium = true

            -- 计入累计充值（影响VIP等级）
            local price = DataMon.BATTLE_PASS.premiumPrice
            if not pd.rechargeData then
                pd.rechargeData = { totalCharged = 0, firstDoubleUsed = {}, rechargeTimes = 0 }
            end
            pd.rechargeData.totalCharged = (pd.rechargeData.totalCharged or 0) + price
            pd.rechargeData.rechargeTimes = (pd.rechargeData.rechargeTimes or 0) + 1

            -- 并行保存 + 查余额
            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinish()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "购买保存失败" })
                end
                reply(true, {
                    isPremium    = true,
                    seasonId     = bpData.seasonId,
                    totalCharged = pd.rechargeData.totalCharged,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

            -- 查余额同步
            pendingOps = pendingOps + 1
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    sync.lingStone = moneys and moneys["lingStone"] or 0
                    sync.spiritStone = moneys and moneys["spiritStone"] or 0
                    sync.xianYuan = pd.xianYuan or 0
                    TryFinish()
                end,
                error = function() TryFinish() end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: battlepass_claim_reward — 领取等级奖励
-- params: { level = number, track = "free"|"paid" }
-- ============================================================================

M.Actions["battlepass_claim_reward"] = function(userId, params, reply)
    local level = params.level
    local track = params.track
    if not level or not track then
        return reply(false, { msg = "参数缺失" })
    end
    if track ~= "free" and track ~= "paid" then
        return reply(false, { msg = "奖励轨道无效" })
    end

    local rewardDef = DataMon.GetBattlePassReward(level)
    if not rewardDef then
        return reply(false, { msg = "该等级无奖励" })
    end

    local reward = rewardDef[track]
    if not reward then
        return reply(false, { msg = "奖励配置错误" })
    end

    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        playerKey = GameServer.GetServerKey("player")
    end
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local pd = scores and scores[playerKey]
            if type(pd) ~= "table" then
                return reply(false, { msg = "角色数据不存在" })
            end

            local bpData = EnsureBPData(pd)
            local currentLevel = GetLevel(bpData.exp)

            if currentLevel < level then
                return reply(false, { msg = "通行证等级不足（当前Lv." .. currentLevel .. "）" })
            end

            if track == "paid" and not bpData.isPremium then
                return reply(false, { msg = "需要购买高级通行证" })
            end

            local claimedKey = (track == "free") and "claimedFree" or "claimedPaid"
            local lvStr = tostring(level)
            if bpData[claimedKey][lvStr] then
                return reply(false, { msg = "该奖励已领取" })
            end

            -- 标记已领取
            bpData[claimedKey][lvStr] = true

            -- 并行发放奖励
            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinish()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "奖励发放失败" })
                end
                reply(true, {
                    level  = level,
                    track  = track,
                    reward = reward,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

            -- 发放灵石
            if reward.lingStone and reward.lingStone > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "lingStone", reward.lingStone, {
                    ok = function() TryFinish() end,
                    error = function() opsFailed = true; TryFinish() end,
                })
            end

            -- 发放仙石
            if reward.spiritStone and reward.spiritStone > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "spiritStone", reward.spiritStone, {
                    ok = function() TryFinish() end,
                    error = function() opsFailed = true; TryFinish() end,
                })
            end

            -- 查余额同步
            pendingOps = pendingOps + 1
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    sync.lingStone = moneys and moneys["lingStone"] or 0
                    sync.spiritStone = moneys and moneys["spiritStone"] or 0
                    TryFinish()
                end,
                error = function() TryFinish() end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: battlepass_add_exp — 增加通行证经验
-- params: { source = string }   source 必须是 expSources 中定义的 key
-- 服务端权威：忽略客户端传入的 amount，以配置表为准
-- ============================================================================

M.Actions["battlepass_add_exp"] = function(userId, params, reply)
    local source = params.source
    if not source then
        return reply(false, { msg = "经验来源未指定" })
    end

    local configuredAmount = DataMon.BATTLE_PASS.expSources[source]
    if not configuredAmount or configuredAmount <= 0 then
        return reply(false, { msg = "无效的经验来源: " .. tostring(source) })
    end

    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        playerKey = GameServer.GetServerKey("player")
    end
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local pd = scores and scores[playerKey]
            if type(pd) ~= "table" then
                return reply(false, { msg = "角色数据不存在" })
            end

            local bpData = EnsureBPData(pd)
            local maxExp = DataMon.BATTLE_PASS.maxLevel * DataMon.BATTLE_PASS.expPerLevel

            if bpData.exp >= maxExp then
                return reply(true, {
                    seasonId = bpData.seasonId,
                    exp    = bpData.exp,
                    level  = DataMon.BATTLE_PASS.maxLevel,
                    gained = 0,
                    source = source,
                    maxed  = true,
                })
            end

            local oldLevel = GetLevel(bpData.exp)
            bpData.exp = math.min(bpData.exp + configuredAmount, maxExp)
            local newLevel = GetLevel(bpData.exp)

            serverCloud:Set(userId, playerKey, pd, {
                ok = function()
                    reply(true, {
                        seasonId = bpData.seasonId,
                        exp      = bpData.exp,
                        level    = newLevel,
                        oldLevel = oldLevel,
                        gained   = configuredAmount,
                        source   = source,
                        levelUp  = newLevel > oldLevel,
                    })
                end,
                error = function()
                    reply(false, { msg = "保存失败" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
