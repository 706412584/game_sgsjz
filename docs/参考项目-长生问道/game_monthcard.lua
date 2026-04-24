-- ============================================================================
-- 《问道长生》月卡系统 - 客户端逻辑
-- 职责：月卡状态查询、购买、每日领取
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

--- 获取当前时间戳
---@return number
local function Now()
    return os.time()
end

--- 确保 monthCards 字段存在
---@param p table playerData
---@return table monthCards
local function EnsureMonthCards(p)
    if not p.monthCards then
        p.monthCards = {}
    end
    return p.monthCards
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 获取月卡原始数据
---@param cardId string "basic"|"premium"
---@return table|nil cardData
function M.GetCardData(cardId)
    local p = GamePlayer.Get()
    if not p then return nil end
    local mc = EnsureMonthCards(p)
    return mc[cardId]
end

--- 月卡是否在有效期内
---@param cardId string
---@return boolean
function M.IsActive(cardId)
    local cd = M.GetCardData(cardId)
    if not cd then return false end
    return Now() < (cd.expiryTime or 0)
end

--- 获取月卡剩余天数（0 = 已过期）
---@param cardId string
---@return number
function M.GetRemainDays(cardId)
    local cd = M.GetCardData(cardId)
    if not cd then return 0 end
    local remaining = (cd.expiryTime or 0) - Now()
    if remaining <= 0 then return 0 end
    return math.ceil(remaining / 86400)
end

--- 今天是否已领取每日奖励
---@param cardId string
---@return boolean
function M.HasClaimedToday(cardId)
    local cd = M.GetCardData(cardId)
    if not cd then return false end
    return cd.lastClaimDate == TodayStr()
end

--- 是否可以领取每日奖励（激活且今日未领）
---@param cardId string
---@return boolean
function M.CanClaimDaily(cardId)
    return M.IsActive(cardId) and not M.HasClaimedToday(cardId)
end

--- 获取月卡完整状态（供 UI 使用）
---@param cardId string
---@return table { config, active, remainDays, claimedToday, canClaim, totalClaimed }
function M.GetStatus(cardId)
    local cfg = DataMon.MONTH_CARDS[cardId]
    if not cfg then
        return { config = nil, active = false, remainDays = 0, claimedToday = false, canClaim = false, totalClaimed = 0 }
    end

    local active = M.IsActive(cardId)
    local remainDays = M.GetRemainDays(cardId)
    local claimedToday = M.HasClaimedToday(cardId)
    local cd = M.GetCardData(cardId)

    return {
        config       = cfg,
        active       = active,
        remainDays   = remainDays,
        claimedToday = claimedToday,
        canClaim     = active and not claimedToday,
        totalClaimed = cd and cd.totalClaimed or 0,
    }
end

--- 是否有任何月卡可领取每日奖励（红点提示用）
---@return boolean
function M.HasAnyClaimable()
    for id, _ in pairs(DataMon.MONTH_CARDS) do
        if M.CanClaimDaily(id) then return true end
    end
    return false
end

--- 是否有任何月卡激活
---@return boolean
function M.HasAnyActive()
    for id, _ in pairs(DataMon.MONTH_CARDS) do
        if M.IsActive(id) then return true end
    end
    return false
end

-- ============================================================================
-- 操作
-- ============================================================================

--- 购买月卡（模拟RMB支付）
---@param cardId string "basic"|"premium"
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.Buy(cardId, callback)
    local cfg = DataMon.MONTH_CARDS[cardId]
    if not cfg then
        Toast.Show("无效的月卡类型")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("monthcard_buy", { cardId = cardId, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地月卡缓存
            local p = GamePlayer.Get()
            if p then
                local mc = EnsureMonthCards(p)
                mc[cardId] = mc[cardId] or {}
                mc[cardId].purchaseTime = Now()
                mc[cardId].expiryTime = data.expiryTime or (Now() + cfg.durationDays * 86400)
                -- 更新充值数据
                if data.totalCharged and p.rechargeData then
                    p.rechargeData.totalCharged = data.totalCharged
                end
            end

            local parts = {}
            if data.instantSS and data.instantSS > 0 then
                parts[#parts + 1] = "仙石+" .. data.instantSS
            end
            if data.instantXY and data.instantXY > 0 then
                parts[#parts + 1] = "仙缘+" .. data.instantXY
            end
            Toast.Show(cfg.label .. "激活成功! " .. table.concat(parts, " "))
        else
            Toast.Show(data and data.msg or "购买失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "处理中..." })
end

--- 领取每日奖励
---@param cardId string "basic"|"premium"
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.ClaimDaily(cardId, callback)
    local cfg = DataMon.MONTH_CARDS[cardId]
    if not cfg then
        Toast.Show("无效的月卡类型")
        if callback then callback(false, nil) end
        return
    end

    if not M.IsActive(cardId) then
        Toast.Show(cfg.label .. "未激活")
        if callback then callback(false, nil) end
        return
    end

    if M.HasClaimedToday(cardId) then
        Toast.Show("今日已领取")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("monthcard_claim_daily", { cardId = cardId, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地缓存
            local p = GamePlayer.Get()
            if p then
                local mc = EnsureMonthCards(p)
                if mc[cardId] then
                    mc[cardId].lastClaimDate = TodayStr()
                    mc[cardId].totalClaimed = data.totalClaimed or (mc[cardId].totalClaimed or 0) + 1
                end
            end

            local parts = {}
            if data.dailySS and data.dailySS > 0 then
                parts[#parts + 1] = "仙石+" .. data.dailySS
            end
            if data.dailyXY and data.dailyXY > 0 then
                parts[#parts + 1] = "仙缘+" .. data.dailyXY
            end
            Toast.Show("领取成功! " .. table.concat(parts, " "))
        else
            Toast.Show(data and data.msg or "领取失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "领取中..." })
end

return M
