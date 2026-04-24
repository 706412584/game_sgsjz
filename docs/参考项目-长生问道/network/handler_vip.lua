-- ============================================================================
-- 《问道长生》VIP 处理器
-- Actions: vip_claim_daily (领取VIP每日灵石)
-- VIP 等级由累计充值自动计算，无需购买
-- 每日灵石领取记录存储在 playerData.vipData 中
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

--- 确保 vipData 字段存在
---@param pd table playerData
---@return table vipData
local function EnsureVipData(pd)
    if not pd.vipData then
        pd.vipData = {
            lastClaimDate = "",
            totalClaimed  = 0,
        }
    end
    return pd.vipData
end

-- ============================================================================
-- Action: vip_claim_daily — 领取VIP每日灵石
-- params: {} (无需参数，等级由服务端根据充值记录计算)
-- ============================================================================

M.Actions["vip_claim_daily"] = function(userId, params, reply)
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

            -- 计算 VIP 等级
            local totalCharged = 0
            if pd.rechargeData and pd.rechargeData.totalCharged then
                totalCharged = pd.rechargeData.totalCharged
            end
            local vipLevel = DataMon.CalcVipLevel(totalCharged)

            -- 获取 VIP 配置
            local vipCfg = DataMon.GetVipConfig(vipLevel)
            if not vipCfg then
                return reply(false, { msg = "VIP数据异常" })
            end

            -- 检查每日灵石额度
            local dailyLingshi = vipCfg.dailyLingshi or 0
            if dailyLingshi <= 0 then
                return reply(false, { msg = "当前VIP等级无每日灵石奖励" })
            end

            local vipData = EnsureVipData(pd)
            local today = TodayStr()

            -- 检查今日是否已领
            if vipData.lastClaimDate == today then
                return reply(false, { msg = "今日已领取VIP灵石" })
            end

            -- 更新领取记录
            vipData.lastClaimDate = today
            vipData.totalClaimed = (vipData.totalClaimed or 0) + 1

            -- 并行操作
            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinish()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "领取失败" })
                end
                reply(true, {
                    vipLevel     = vipLevel,
                    dailyLingshi = dailyLingshi,
                    totalClaimed = vipData.totalClaimed,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

            -- 发放灵石
            pendingOps = pendingOps + 1
            serverCloud.money:Add(userId, "lingStone", dailyLingshi, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

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

return M
