-- ============================================================================
-- 《问道长生》礼包处理器
-- Actions: gift_buy_weekly (仙石购买每周特惠)
-- 注意：新手礼包和境界突破礼包需要 RMB 支付，在充值系统中处理
-- 本 handler 只处理仙石购买的每周特惠
-- ============================================================================

local GameServer = require("game_server")
local DataMon    = require("data_monetization")

local M = {}
M.Actions = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取当前星期几 (1=周一 ... 7=周日)
---@return number
local function GetWeekday()
    local wday = tonumber(os.date("%w"))  -- 0=Sun, 1=Mon ... 6=Sat
    return wday == 0 and 7 or wday
end

--- 获取本周的起始日期字符串（用于购买记录 key）
---@return string "YYYY-WNN"
local function GetWeekKey()
    return os.date("%Y-W") .. string.format("%02d", tonumber(os.date("%W")) or 0)
end

--- 确保礼包数据字段存在
---@param pd table playerData
---@return table giftData
local function EnsureGiftData(pd)
    if not pd.giftPurchases then
        pd.giftPurchases = {}
    end
    return pd.giftPurchases
end

-- ============================================================================
-- Action: gift_buy_weekly — 购买每周特惠（仙石支付）
-- params: { dealId = string }
-- ============================================================================

M.Actions["gift_buy_weekly"] = function(userId, params, reply)
    local dealId = params.dealId
    if not dealId or dealId == "" then
        return reply(false, { msg = "缺少礼包ID" })
    end

    -- 查找配置
    local dealCfg = nil
    for _, d in ipairs(DataMon.WEEKLY_DEALS) do
        if d.id == dealId then
            dealCfg = d
            break
        end
    end
    if not dealCfg then
        return reply(false, { msg = "无效的礼包ID" })
    end

    -- 仙石支付的特惠才走此 handler
    if dealCfg.currency ~= "spiritStone" then
        return reply(false, { msg = "该礼包需要充值购买" })
    end

    -- 检查星期几是否匹配
    local today = GetWeekday()
    if today ~= dealCfg.weekday then
        return reply(false, { msg = "该特惠今日未开放" })
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

            local gifts = EnsureGiftData(pd)
            local weekKey = GetWeekKey()

            -- 检查本周是否已购买
            local purchaseKey = dealId .. "_" .. weekKey
            if gifts[purchaseKey] then
                return reply(false, { msg = "本周已购买此特惠" })
            end

            -- 扣仙石
            local cost = dealCfg.cost
            serverCloud.money:Cost(userId, "spiritStone", cost, {
                ok = function()
                    -- 标记已购
                    gifts[purchaseKey] = true

                    -- 计算奖励
                    local content = dealCfg.content
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
                            dealId  = dealId,
                            content = content,
                        }, sync)
                    end

                    -- 保存 playerData
                    pendingOps = pendingOps + 1
                    serverCloud:Set(userId, playerKey, pd, {
                        ok = function() TryFinish() end,
                        error = function() opsFailed = true; TryFinish() end,
                    })

                    -- 发放灵石（如有）
                    if content.lingStone and content.lingStone > 0 then
                        pendingOps = pendingOps + 1
                        serverCloud.money:Add(userId, "lingStone", content.lingStone, {
                            ok = function() TryFinish() end,
                            error = function() opsFailed = true; TryFinish() end,
                        })
                    end

                    -- 发放物品（灵尘等通过 playerData 直接处理）
                    if content.lingDust and content.lingDust > 0 then
                        pd.lingDust = (pd.lingDust or 0) + content.lingDust
                        sync.lingDust = pd.lingDust
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
                    reply(false, { msg = "仙石不足" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
