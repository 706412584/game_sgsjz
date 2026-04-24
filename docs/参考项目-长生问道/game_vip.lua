-- ============================================================================
-- 《问道长生》VIP系统 - 客户端逻辑
-- 职责：VIP等级查询、特权查询、每日灵石领取
-- VIP等级由累计充值金额自动计算，无需手动升级
-- ============================================================================

local GamePlayer = require("game_player")
local GameOps    = require("network.game_ops")
local GameServer = require("game_server")
local DataMon    = require("data_monetization")
local Toast      = require("ui_toast")

local M = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取今天的日期字符串 YYYY-MM-DD
---@return string
local function TodayStr()
    return os.date("%Y-%m-%d")
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 获取累计充值金额
---@return number
function M.GetTotalCharged()
    local p = GamePlayer.Get()
    if not p or not p.rechargeData then return 0 end
    return p.rechargeData.totalCharged or 0
end

--- 获取当前VIP等级
---@return number
function M.GetLevel()
    return DataMon.CalcVipLevel(M.GetTotalCharged())
end

--- 获取当前VIP配置
---@return table|nil
function M.GetConfig()
    return DataMon.GetVipConfig(M.GetLevel())
end

--- 获取每日灵石额度
---@return number
function M.GetDailyLingshi()
    local cfg = M.GetConfig()
    return cfg and cfg.dailyLingshi or 0
end

--- 获取下一VIP等级所需充值金额（nil = 已满级）
---@return number|nil
function M.GetNextCharge()
    return DataMon.GetNextVipCharge(M.GetLevel())
end

--- 获取当前VIP等级的特权列表
---@return string[]
function M.GetPrivileges()
    local cfg = M.GetConfig()
    return cfg and cfg.privileges or {}
end

--- 获取所有已解锁的特权（当前等级及以下所有特权）
---@return string[]
function M.GetAllUnlockedPrivileges()
    local level = M.GetLevel()
    local result = {}
    for _, v in ipairs(DataMon.VIP_LEVELS) do
        if v.level <= level and v.level > 0 then
            for _, priv in ipairs(v.privileges) do
                -- 跳过"VIPx特权"这类继承描述
                if not priv:match("^VIP%d+特权$") then
                    result[#result + 1] = priv
                end
            end
        end
    end
    return result
end

--- 今天是否已领取VIP灵石
---@return boolean
function M.HasClaimedToday()
    local p = GamePlayer.Get()
    if not p or not p.vipData then return false end
    return p.vipData.lastClaimDate == TodayStr()
end

--- 是否可以领取VIP灵石（有额度且今日未领）
---@return boolean
function M.CanClaimDaily()
    return M.GetDailyLingshi() > 0 and not M.HasClaimedToday()
end

--- 获取VIP完整状态（供 UI 使用）
---@return table
function M.GetStatus()
    local level = M.GetLevel()
    local totalCharged = M.GetTotalCharged()
    local nextCharge = M.GetNextCharge()
    local dailyLingshi = M.GetDailyLingshi()
    local claimedToday = M.HasClaimedToday()
    local allPrivs = M.GetAllUnlockedPrivileges()

    -- 距下一级差多少
    local chargeGap = 0
    if nextCharge then
        chargeGap = nextCharge - totalCharged
    end

    return {
        level          = level,
        totalCharged   = totalCharged,
        nextCharge     = nextCharge,
        chargeGap      = chargeGap,
        dailyLingshi   = dailyLingshi,
        claimedToday   = claimedToday,
        canClaim       = dailyLingshi > 0 and not claimedToday,
        privileges     = allPrivs,
        isMaxLevel     = (nextCharge == nil),
    }
end

-- ============================================================================
-- 操作
-- ============================================================================

--- 领取VIP每日灵石
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.ClaimDaily(callback)
    if M.GetDailyLingshi() <= 0 then
        Toast.Show("当前VIP等级无每日灵石奖励")
        if callback then callback(false, nil) end
        return
    end

    if M.HasClaimedToday() then
        Toast.Show("今日已领取")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("vip_claim_daily", { playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地缓存
            local p = GamePlayer.Get()
            if p then
                if not p.vipData then
                    p.vipData = {}
                end
                p.vipData.lastClaimDate = TodayStr()
                p.vipData.totalClaimed = data.totalClaimed or (p.vipData.totalClaimed or 0) + 1
            end
            Toast.Show("领取成功! 灵石+" .. (data.dailyLingshi or 0))
        else
            Toast.Show(data and data.msg or "领取失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "领取中..." })
end

return M
