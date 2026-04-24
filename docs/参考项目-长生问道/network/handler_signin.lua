-- ============================================================================
-- 《问道长生》签到处理器
-- Actions: signin_claim, signin_ad_double
-- 签到数据存储在 playerData.dailySignin 中
-- ============================================================================

local GameServer = require("game_server")
local DataMon    = require("data_monetization")

local M = {}
M.Actions = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取今天的日期字符串 YYYY-MM-DD
---@return string
local function TodayStr()
    return os.date("%Y-%m-%d")
end

--- 确保 dailySignin 字段存在
---@param pd table playerData
---@return table dailySignin
local function EnsureSignin(pd)
    if not pd.dailySignin then
        pd.dailySignin = {
            totalDays     = 0,
            lastSignDate  = "",
            todayAdWatched = false,
        }
    end
    return pd.dailySignin
end

-- ============================================================================
-- Action: signin_claim — 领取今日签到奖励
-- params: {} (无需参数)
-- ============================================================================

M.Actions["signin_claim"] = function(userId, params, reply)
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

            local signin = EnsureSignin(pd)
            local today = TodayStr()

            -- 检查是否已签到
            if signin.lastSignDate == today then
                return reply(false, { msg = "今日已签到" })
            end

            -- 计算奖励
            local reward = DataMon.GetSigninReward(signin.totalDays)
            signin.totalDays = signin.totalDays + 1
            signin.lastSignDate = today
            signin.todayAdWatched = false

            -- 发放灵石奖励（如有）
            local freeReward = reward.free
            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinishReply()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "奖励发放失败" })
                end
                reply(true, {
                    totalDays  = signin.totalDays,
                    dayInCycle = ((signin.totalDays - 1) % 7) + 1,
                    reward     = freeReward,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function()
                    TryFinishReply()
                end,
                error = function()
                    opsFailed = true
                    TryFinishReply()
                end,
            })

            -- 发放灵石
            if freeReward.lingStone and freeReward.lingStone > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "lingStone", freeReward.lingStone, {
                    ok = function()
                        serverCloud.money:Get(userId, {
                            ok = function(moneys)
                                sync.lingStone = moneys and moneys["lingStone"] or 0
                                sync.spiritStone = moneys and moneys["spiritStone"] or 0
                                TryFinishReply()
                            end,
                            error = function()
                                TryFinishReply()
                            end,
                        })
                    end,
                    error = function()
                        opsFailed = true
                        TryFinishReply()
                    end,
                })
            end

            -- 无灵石奖励时也要查余额同步
            if not freeReward.lingStone or freeReward.lingStone <= 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Get(userId, {
                    ok = function(moneys)
                        sync.lingStone = moneys and moneys["lingStone"] or 0
                        sync.spiritStone = moneys and moneys["spiritStone"] or 0
                        TryFinishReply()
                    end,
                    error = function()
                        TryFinishReply()
                    end,
                })
            end
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: signin_ad_double — 观看广告领取加倍奖励
-- params: {} (无需参数)
-- ============================================================================

M.Actions["signin_ad_double"] = function(userId, params, reply)
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

            local signin = EnsureSignin(pd)
            local today = TodayStr()

            -- 必须今天已签到
            if signin.lastSignDate ~= today then
                return reply(false, { msg = "请先签到" })
            end

            -- 检查是否已看过广告
            if signin.todayAdWatched then
                return reply(false, { msg = "今日已领取加倍奖励" })
            end

            -- 计算广告加倍奖励
            local reward = DataMon.GetSigninReward(signin.totalDays - 1)
            local adReward = reward.ad
            signin.todayAdWatched = true

            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinishReply()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "奖励发放失败" })
                end
                reply(true, {
                    adReward = adReward,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinishReply() end,
                error = function() opsFailed = true; TryFinishReply() end,
            })

            -- 发放仙石（如有）
            local totalSS = (adReward.spiritStone or 0)
            if totalSS > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "spiritStone", totalSS, {
                    ok = function() TryFinishReply() end,
                    error = function() opsFailed = true; TryFinishReply() end,
                })
            end

            -- 发放灵石（如有）
            local totalLS = (adReward.lingStone or 0)
            if totalLS > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "lingStone", totalLS, {
                    ok = function() TryFinishReply() end,
                    error = function() opsFailed = true; TryFinishReply() end,
                })
            end

            -- 查余额同步
            pendingOps = pendingOps + 1
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    sync.lingStone = moneys and moneys["lingStone"] or 0
                    sync.spiritStone = moneys and moneys["spiritStone"] or 0
                    TryFinishReply()
                end,
                error = function() TryFinishReply() end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
