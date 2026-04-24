-- ============================================================================
-- 《问道长生》月卡处理器
-- Actions: monthcard_buy (购买月卡), monthcard_claim_daily (领取每日奖励)
-- 月卡数据存储在 playerData.monthCards 中
-- 注意：购买走模拟RMB流程（与充值相同，生产环境应由支付回调触发）
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

--- 获取当前时间戳
---@return number
local function Now()
    return os.time()
end

--- 确保 monthCards 字段存在
---@param pd table playerData
---@return table monthCards
local function EnsureMonthCards(pd)
    if not pd.monthCards then
        pd.monthCards = {}
    end
    return pd.monthCards
end

--- 检查月卡是否在有效期内
---@param cardData table|nil
---@return boolean
local function IsCardActive(cardData)
    if not cardData then return false end
    local expiry = cardData.expiryTime or 0
    return Now() < expiry
end

-- ============================================================================
-- Action: monthcard_buy — 购买月卡（模拟RMB支付）
-- params: { cardId = "basic"|"premium" }
-- ============================================================================

M.Actions["monthcard_buy"] = function(userId, params, reply)
    local cardId = params.cardId
    if not cardId or cardId == "" then
        return reply(false, { msg = "缺少月卡类型" })
    end

    local cardCfg = DataMon.MONTH_CARDS[cardId]
    if not cardCfg then
        return reply(false, { msg = "无效的月卡类型" })
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

            local mc = EnsureMonthCards(pd)

            -- 检查是否已有有效月卡（允许续费：在到期前购买延长30天）
            local existing = mc[cardId]
            local now = Now()
            local startTime = now
            if existing and IsCardActive(existing) then
                -- 续费：从当前到期时间往后延长
                startTime = existing.expiryTime
            end

            local expiryTime = startTime + cardCfg.durationDays * 86400

            -- 设置月卡数据
            mc[cardId] = mc[cardId] or {}
            mc[cardId].purchaseTime = now
            mc[cardId].expiryTime   = expiryTime
            -- 不重置 lastClaimDate，续费当天如果已领过就不再重复领

            -- 即时奖励
            local instantSS = cardCfg.instantStones or 0
            local instantXY = cardCfg.instantXY or 0

            -- 仙缘直接写 playerData
            if instantXY > 0 then
                pd.xianYuan = (pd.xianYuan or 0) + instantXY
            end

            -- 同步更新充值记录（月卡计入累计充值，影响VIP等级）
            if not pd.rechargeData then
                pd.rechargeData = { totalCharged = 0, firstDoubleUsed = {}, rechargeTimes = 0 }
            end
            pd.rechargeData.totalCharged = (pd.rechargeData.totalCharged or 0) + cardCfg.price
            pd.rechargeData.rechargeTimes = (pd.rechargeData.rechargeTimes or 0) + 1

            -- 并行操作
            local sync = {}
            local pendingOps = 0
            local opsFinished = 0
            local opsFailed = false

            local function TryFinish()
                opsFinished = opsFinished + 1
                if opsFinished < pendingOps then return end
                if opsFailed then
                    return reply(false, { msg = "月卡购买失败" })
                end

                -- 计算剩余天数
                local remainDays = math.ceil((expiryTime - Now()) / 86400)

                reply(true, {
                    cardId       = cardId,
                    label        = cardCfg.label,
                    instantSS    = instantSS,
                    instantXY    = instantXY,
                    expiryTime   = expiryTime,
                    remainDays   = remainDays,
                    totalCharged = pd.rechargeData.totalCharged,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

            -- 发放即时仙石
            if instantSS > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "spiritStone", instantSS, {
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
-- Action: monthcard_claim_daily — 领取月卡每日奖励
-- params: { cardId = "basic"|"premium" }
-- ============================================================================

M.Actions["monthcard_claim_daily"] = function(userId, params, reply)
    local cardId = params.cardId
    if not cardId or cardId == "" then
        return reply(false, { msg = "缺少月卡类型" })
    end

    local cardCfg = DataMon.MONTH_CARDS[cardId]
    if not cardCfg then
        return reply(false, { msg = "无效的月卡类型" })
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

            local mc = EnsureMonthCards(pd)
            local cardData = mc[cardId]

            -- 检查月卡是否有效
            if not IsCardActive(cardData) then
                return reply(false, { msg = cardCfg.label .. "未激活或已过期" })
            end

            -- 检查今日是否已领
            local today = TodayStr()
            if cardData.lastClaimDate == today then
                return reply(false, { msg = "今日已领取" })
            end

            -- 更新领取记录
            cardData.lastClaimDate = today
            cardData.totalClaimed = (cardData.totalClaimed or 0) + 1

            -- 每日奖励
            local dailySS = cardCfg.dailyStones or 0
            local dailyXY = cardCfg.dailyXY or 0

            -- 仙缘写 playerData
            if dailyXY > 0 then
                pd.xianYuan = (pd.xianYuan or 0) + dailyXY
            end

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

                local remainDays = math.ceil((cardData.expiryTime - Now()) / 86400)

                reply(true, {
                    cardId       = cardId,
                    dailySS      = dailySS,
                    dailyXY      = dailyXY,
                    totalClaimed = cardData.totalClaimed,
                    remainDays   = remainDays,
                }, sync)
            end

            -- 保存 playerData
            pendingOps = pendingOps + 1
            serverCloud:Set(userId, playerKey, pd, {
                ok = function() TryFinish() end,
                error = function() opsFailed = true; TryFinish() end,
            })

            -- 发放每日仙石
            if dailySS > 0 then
                pendingOps = pendingOps + 1
                serverCloud.money:Add(userId, "spiritStone", dailySS, {
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

return M
