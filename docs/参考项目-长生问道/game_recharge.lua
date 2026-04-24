-- ============================================================================
-- 《问道长生》充值系统 - 客户端逻辑
-- 职责：充值档位查询、首充状态、充值请求
-- ============================================================================

local GamePlayer = require("game_player")
local GameOps    = require("network.game_ops")
local GameServer = require("game_server")
local DataMon    = require("data_monetization")
local Toast      = require("ui_toast")

local M = {}

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 获取充值数据
---@return table { totalCharged, firstDoubleUsed, rechargeTimes }
function M.GetData()
    local p = GamePlayer.Get()
    if not p then
        return { totalCharged = 0, firstDoubleUsed = {}, rechargeTimes = 0 }
    end
    if not p.rechargeData then
        p.rechargeData = { totalCharged = 0, firstDoubleUsed = {}, rechargeTimes = 0 }
    end
    return p.rechargeData
end

--- 获取累计充值金额(RMB)
---@return number
function M.GetTotalCharged()
    return M.GetData().totalCharged or 0
end

--- 是否已使用首充双倍（指定档位）
---@param tierId string
---@return boolean
function M.HasUsedFirstDouble(tierId)
    local data = M.GetData()
    local used = data.firstDoubleUsed or {}
    return used[tierId] == true
end

--- 获取所有充值档位及状态
---@return table[] { config, hasFirstDouble, actualStones }
function M.GetTiers()
    local result = {}
    for _, tier in ipairs(DataMon.RECHARGE_TIERS) do
        local hasFirst = not M.HasUsedFirstDouble(tier.id) and tier.firstDouble
        local actualStones = tier.stones
        if hasFirst then
            actualStones = tier.stones * 2
        end

        result[#result + 1] = {
            config         = tier,
            hasFirstDouble = hasFirst,
            actualStones   = actualStones,
        }
    end
    return result
end

--- 获取充值次数
---@return number
function M.GetRechargeTimes()
    return M.GetData().rechargeTimes or 0
end

--- 是否为首充（从未充过值）
---@return boolean
function M.IsFirstRecharge()
    return M.GetRechargeTimes() == 0
end

-- ============================================================================
-- 充值请求（模拟）
-- ============================================================================

--- 发起充值（开发模式：直接走服务端模拟发放）
---@param tierId string 档位 ID
---@param callback fun(ok: boolean, data: table|nil)
function M.Recharge(tierId, callback)
    -- 查找档位
    local tierCfg = nil
    for _, t in ipairs(DataMon.RECHARGE_TIERS) do
        if t.id == tierId then
            tierCfg = t
            break
        end
    end
    if not tierCfg then
        Toast.Show("无效的充值档位")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("recharge_complete", { tierId = tierId, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地缓存
            local p = GamePlayer.Get()
            if p then
                p.rechargeData = p.rechargeData or {}
                p.rechargeData.totalCharged = data.totalCharged or p.rechargeData.totalCharged
                p.rechargeData.rechargeTimes = data.rechargeTimes or p.rechargeData.rechargeTimes
                if data.firstDoubleUsed then
                    p.rechargeData.firstDoubleUsed = p.rechargeData.firstDoubleUsed or {}
                    p.rechargeData.firstDoubleUsed[tierId] = true
                end
            end

            -- Toast
            local parts = {}
            if data.stonesGained then
                parts[#parts + 1] = "仙石+" .. data.stonesGained
            end
            if data.xyGained then
                parts[#parts + 1] = "仙缘+" .. data.xyGained
            end
            if #parts > 0 then
                Toast.Show("充值成功! " .. table.concat(parts, " "))
            else
                Toast.Show("充值成功!")
            end
        else
            Toast.Show(data and data.msg or "充值失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "处理中..." })
end

return M
