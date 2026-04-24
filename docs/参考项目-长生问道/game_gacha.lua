-- ============================================================================
-- 《问道长生》抽奖系统 - 客户端逻辑
-- 职责：抽奖状态查询、单抽/十连请求
-- ============================================================================

local GamePlayer = require("game_player")
local GameOps    = require("network.game_ops")
local DataMon    = require("data_monetization")
local Toast      = require("ui_toast")

local M = {}

-- 最近一次抽奖结果（供 UI 展示用）
M.lastResults = nil

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 获取抽奖数据
---@return table { totalPulls, pityCounter }
function M.GetData()
    local p = GamePlayer.Get()
    if not p or not p.gachaData then
        return { totalPulls = 0, pityCounter = 0 }
    end
    return p.gachaData
end

--- 获取累计抽奖次数
---@return number
function M.GetTotalPulls()
    return M.GetData().totalPulls or 0
end

--- 获取当前保底计数（距上次高品质的抽数）
---@return number
function M.GetPityCounter()
    return M.GetData().pityCounter or 0
end

--- 距软保底还需几抽
---@return number
function M.GetSoftPityRemain()
    local pity = M.GetPityCounter()
    local remain = DataMon.GACHA.softPity - pity
    return math.max(0, remain)
end

--- 距硬保底还需几抽
---@return number
function M.GetHardPityRemain()
    local pity = M.GetPityCounter()
    local remain = DataMon.GACHA.hardPity - pity
    return math.max(0, remain)
end

--- 获取单抽费用
---@return number
function M.GetSingleCost()
    return DataMon.GACHA.singleCost
end

--- 获取十连费用
---@return number
function M.GetTenCost()
    return DataMon.GACHA.tenCost
end

--- 获取完整状态（供 UI 使用）
---@return table
function M.GetStatus()
    return {
        totalPulls      = M.GetTotalPulls(),
        pityCounter     = M.GetPityCounter(),
        softPityRemain  = M.GetSoftPityRemain(),
        hardPityRemain  = M.GetHardPityRemain(),
        singleCost      = M.GetSingleCost(),
        tenCost         = M.GetTenCost(),
        lastResults     = M.lastResults,
    }
end

-- ============================================================================
-- 操作
-- ============================================================================

--- 抽奖（单抽或十连）
---@param count number 1 或 10
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.Pull(count, callback)
    if count ~= 1 and count ~= 10 then
        Toast.Show("抽奖次数无效")
        if callback then callback(false, nil) end
        return
    end

    local cost = (count == 10) and M.GetTenCost() or M.GetSingleCost()

    local GameServer = require("game_server")
    GameOps.Request("gacha_pull", { count = count, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地缓存
            local p = GamePlayer.Get()
            if p then
                if not p.gachaData then
                    p.gachaData = {}
                end
                p.gachaData.totalPulls = data.totalPulls or p.gachaData.totalPulls
                p.gachaData.pityCounter = data.pityCounter or p.gachaData.pityCounter
            end

            -- 保存结果供 UI 展示
            M.lastResults = data.results

            -- Toast 简要提示（高品质装备特别提示）
            local highItems = {}
            for _, r in ipairs(data.results or {}) do
                if r.quality == "xtshenqi" or r.quality == "shenqi"
                    or r.quality == "xtxianqi" or r.quality == "xianqi" then
                    highItems[#highItems + 1] = (r.desc or r.label)
                end
            end
            if #highItems > 0 then
                Toast.Show("恭喜获得: " .. table.concat(highItems, ", "))
            else
                -- 汇总获得物品
                local summary = {}
                for _, r in ipairs(data.results or {}) do
                    if r.desc then
                        summary[#summary + 1] = r.desc
                    end
                end
                if #summary > 0 then
                    Toast.Show("获得: " .. table.concat(summary, ", "))
                else
                    Toast.Show("抽奖完成，消耗仙石" .. cost)
                end
            end
        else
            Toast.Show(data and data.msg or "抽奖失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "抽奖中..." })
end

return M
