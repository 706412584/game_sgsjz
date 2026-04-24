-- ============================================================================
-- 《问道长生》礼包系统 - 客户端逻辑
-- 职责：礼包状态查询、购买请求、可用性判断
-- 三类礼包：新手礼包、境界突破礼包、每周特惠
-- ============================================================================

local GamePlayer = require("game_player")
local GameOps    = require("network.game_ops")
local GameServer = require("game_server")
local DataMon    = require("data_monetization")
local Toast      = require("ui_toast")

local M = {}

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 获取当前星期几（1=周一 ... 7=周日）
---@return number
local function GetWeekday()
    local wday = tonumber(os.date("%w"))
    return wday == 0 and 7 or wday
end

--- 获取本周 key
---@return string
local function GetWeekKey()
    return os.date("%Y-W") .. string.format("%02d", tonumber(os.date("%W")) or 0)
end

--- 获取角色创建至今的天数
---@return number
local function GetAccountAgeDays()
    local p = GamePlayer.Get()
    if not p then return 999 end

    -- 优先用 createdAt（Unix 时间戳），兼容旧格式 createTime（"YYYY-MM-DD"）
    local createTs = nil
    if p.createdAt and type(p.createdAt) == "number" and p.createdAt > 0 then
        createTs = p.createdAt
    elseif p.createTime and type(p.createTime) == "string" then
        local y, m, d = p.createTime:match("(%d+)-(%d+)-(%d+)")
        if y then
            createTs = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        end
    end

    if not createTs then return 999 end

    local now = os.time()
    return math.floor((now - createTs) / 86400) + 1
end

--- 获取礼包购买记录
---@return table
local function GetPurchases()
    local p = GamePlayer.Get()
    if not p then return {} end
    return p.giftPurchases or {}
end

-- ============================================================================
-- 新手礼包
-- ============================================================================

--- 获取可用的新手礼包列表（7天内且未购买的）
---@return table[] { config, canBuy, reason }
function M.GetNewbieGifts()
    local ageDays = GetAccountAgeDays()
    local purchases = GetPurchases()
    local result = {}

    for _, gift in ipairs(DataMon.NEWBIE_GIFTS) do
        local entry = { config = gift, canBuy = false, reason = "" }

        if purchases[gift.id] then
            entry.reason = "已购买"
        elseif ageDays > 7 then
            entry.reason = "已过期"
        elseif ageDays < gift.day then
            entry.reason = "第" .. gift.day .. "天开放"
        else
            entry.canBuy = true
        end

        result[#result + 1] = entry
    end

    return result
end

--- 是否还有新手礼包可购买
---@return boolean
function M.HasAvailableNewbie()
    local gifts = M.GetNewbieGifts()
    for _, g in ipairs(gifts) do
        if g.canBuy then return true end
    end
    return false
end

-- ============================================================================
-- 境界突破礼包
-- ============================================================================

--- 获取可用的境界突破礼包列表
---@return table[] { config, canBuy, reason }
function M.GetBreakthroughGifts()
    local p = GamePlayer.Get()
    local purchases = GetPurchases()
    local result = {}

    -- 获取当前境界 tier
    local currentTier = 1
    if p then
        currentTier = p.tier or 1
    end

    for _, gift in ipairs(DataMon.BREAKTHROUGH_GIFTS) do
        local entry = { config = gift, canBuy = false, reason = "" }

        if purchases[gift.id] then
            entry.reason = "已购买"
        elseif currentTier < gift.tier then
            entry.reason = "需达到" .. gift.realm .. "期"
        else
            entry.canBuy = true
        end

        result[#result + 1] = entry
    end

    return result
end

--- 是否有境界突破礼包可购买
---@return boolean
function M.HasAvailableBreakthrough()
    local gifts = M.GetBreakthroughGifts()
    for _, g in ipairs(gifts) do
        if g.canBuy then return true end
    end
    return false
end

-- ============================================================================
-- 每周特惠
-- ============================================================================

--- 获取今日的每周特惠列表
---@return table[] { config, canBuy, reason, isToday }
function M.GetWeeklyDeals()
    local weekday = GetWeekday()
    local purchases = GetPurchases()
    local weekKey = GetWeekKey()
    local result = {}

    for _, deal in ipairs(DataMon.WEEKLY_DEALS) do
        local entry = {
            config  = deal,
            canBuy  = false,
            reason  = "",
            isToday = deal.weekday == weekday,
        }

        local purchaseKey = deal.id .. "_" .. weekKey
        if purchases[purchaseKey] then
            entry.reason = "本周已购买"
        elseif deal.weekday ~= weekday then
            local dayNames = { "周一", "周二", "周三", "周四", "周五", "周六", "周日" }
            entry.reason = dayNames[deal.weekday] .. "开放"
        else
            entry.canBuy = true
        end

        result[#result + 1] = entry
    end

    return result
end

--- 购买每周特惠（仙石支付）
---@param dealId string
---@param callback fun(ok: boolean, data: table|nil)
function M.BuyWeeklyDeal(dealId, callback)
    GameOps.Request("gift_buy_weekly", { dealId = dealId, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地购买记录
            local p = GamePlayer.Get()
            if p then
                p.giftPurchases = p.giftPurchases or {}
                local weekKey = GetWeekKey()
                p.giftPurchases[dealId .. "_" .. weekKey] = true
            end
            local content = data and data.content
            if content then
                Toast.Show("购买成功! " .. DataMon.FormatGiftContent(content))
            else
                Toast.Show("购买成功!")
            end
        else
            Toast.Show(data and data.msg or "购买失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "购买中..." })
end

-- ============================================================================
-- 红点提示
-- ============================================================================

--- 是否有可购买的礼包（用于红点显示）
---@return boolean
function M.HasAnyAvailable()
    if M.HasAvailableNewbie() then return true end
    if M.HasAvailableBreakthrough() then return true end

    -- 检查今日特惠
    local deals = M.GetWeeklyDeals()
    for _, d in ipairs(deals) do
        if d.canBuy then return true end
    end

    return false
end

return M
