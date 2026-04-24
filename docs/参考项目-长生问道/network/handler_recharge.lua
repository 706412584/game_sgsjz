-- ============================================================================
-- 《问道长生》充值处理器
-- Actions: recharge_complete (充值完成，发放仙石+仙缘+首充双倍)
-- 注意：实际生产环境应由支付平台回调触发，此处为开发模式直接模拟
-- ============================================================================

local GameServer = require("game_server")
local DataMon    = require("data_monetization")

local M = {}
M.Actions = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保充值数据存在
---@param pd table playerData
---@return table rechargeData
local function EnsureRechargeData(pd)
    if not pd.rechargeData then
        pd.rechargeData = {
            totalCharged   = 0,
            firstDoubleUsed = {},
            rechargeTimes  = 0,
        }
    end
    if not pd.rechargeData.firstDoubleUsed then
        pd.rechargeData.firstDoubleUsed = {}
    end
    return pd.rechargeData
end

-- ============================================================================
-- Action: recharge_complete — 充值完成（模拟/回调）
-- params: { tierId = string }
-- ============================================================================

M.Actions["recharge_complete"] = function(userId, params, reply)
    local tierId = params.tierId
    if not tierId or tierId == "" then
        return reply(false, { msg = "缺少充值档位" })
    end

    -- 查找档位
    local tierCfg = nil
    for _, t in ipairs(DataMon.RECHARGE_TIERS) do
        if t.id == tierId then
            tierCfg = t
            break
        end
    end
    if not tierCfg then
        return reply(false, { msg = "无效的充值档位" })
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

            local rData = EnsureRechargeData(pd)

            -- 计算仙石：首充双倍
            local isFirstDouble = false
            local stonesGained = tierCfg.stones
            if tierCfg.firstDouble and not rData.firstDoubleUsed[tierId] then
                stonesGained = tierCfg.stones * 2
                rData.firstDoubleUsed[tierId] = true
                isFirstDouble = true
            end

            -- 仙缘
            local xyGained = tierCfg.bonusXY or 0

            -- 更新充值记录
            rData.totalCharged = (rData.totalCharged or 0) + tierCfg.price
            rData.rechargeTimes = (rData.rechargeTimes or 0) + 1

            -- 并行操作
            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinish()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "充值发放失败" })
                end
                reply(true, {
                    tierId         = tierId,
                    stonesGained   = stonesGained,
                    xyGained       = xyGained,
                    totalCharged   = rData.totalCharged,
                    rechargeTimes  = rData.rechargeTimes,
                    firstDoubleUsed = isFirstDouble,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

            -- 发放仙石
            if stonesGained > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "spiritStone", stonesGained, {
                    ok = function() TryFinish() end,
                    error = function() opsFailed = true; TryFinish() end,
                })
            end

            -- 发放仙缘（通过 playerData 存储）
            if xyGained > 0 then
                pd.xianYuan = (pd.xianYuan or 0) + xyGained
                sync.xianYuan = pd.xianYuan
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

return M
