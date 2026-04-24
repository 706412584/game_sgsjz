-- ============================================================================
-- 《问道长生》通行证系统 - 客户端逻辑
-- 职责：赛季状态查询、购买高级通行证、领取奖励、经验增加
-- ============================================================================

local GamePlayer = require("game_player")
local GameOps    = require("network.game_ops")
local GameServer = require("game_server")
local DataMon    = require("data_monetization")
local Toast      = require("ui_toast")

local M = {}

-- ============================================================================
-- 赛季工具（与服务端保持一致）
-- ============================================================================

local SEASON_EPOCH = os.time({ year = 2026, month = 1, day = 1, hour = 0, min = 0, sec = 0 })

--- 获取当前赛季 ID
---@return string
local function GetCurrentSeasonId()
    local elapsed = os.time() - SEASON_EPOCH
    local days = DataMon.BATTLE_PASS.seasonDays
    local idx = math.floor(elapsed / (days * 86400))
    return "S" .. (idx + 1)
end

--- 获取当前赛季剩余天数
---@return number
function M.GetSeasonRemainDays()
    local elapsed = os.time() - SEASON_EPOCH
    local days = DataMon.BATTLE_PASS.seasonDays
    local seasonSec = days * 86400
    local inSeason = elapsed % seasonSec
    local remain = seasonSec - inSeason
    return math.ceil(remain / 86400)
end

-- ============================================================================
-- 状态查询
-- ============================================================================

--- 获取通行证数据（自动检测赛季重置）
---@return table
function M.GetData()
    local p = GamePlayer.Get()
    if not p then return { seasonId = "", exp = 0, isPremium = false, claimedFree = {}, claimedPaid = {} } end

    local curSeason = GetCurrentSeasonId()
    local bp = p.battlePassData
    if not bp or bp.seasonId ~= curSeason then
        return { seasonId = curSeason, exp = 0, isPremium = false, claimedFree = {}, claimedPaid = {} }
    end
    return bp
end

--- 获取当前等级
---@return number
function M.GetLevel()
    local data = M.GetData()
    local bp = DataMon.BATTLE_PASS
    return math.min(math.floor((data.exp or 0) / bp.expPerLevel), bp.maxLevel)
end

--- 获取当前经验值
---@return number
function M.GetExp()
    return M.GetData().exp or 0
end

--- 当前等级内的经验进度
---@return number current, number total
function M.GetLevelProgress()
    local exp = M.GetExp()
    local perLevel = DataMon.BATTLE_PASS.expPerLevel
    local level = M.GetLevel()
    if level >= DataMon.BATTLE_PASS.maxLevel then
        return perLevel, perLevel  -- 满级
    end
    local cur = exp - level * perLevel
    return cur, perLevel
end

--- 是否已购买高级通行证
---@return boolean
function M.IsPremium()
    return M.GetData().isPremium == true
end

--- 检查某级某轨道是否已领取
---@param level number
---@param track string "free"|"paid"
---@return boolean
function M.HasClaimed(level, track)
    local data = M.GetData()
    local claimedKey = (track == "free") and "claimedFree" or "claimedPaid"
    local claimed = data[claimedKey] or {}
    return claimed[tostring(level)] == true
end

--- 某级某轨道是否可领取
---@param level number
---@param track string "free"|"paid"
---@return boolean
function M.CanClaim(level, track)
    if M.GetLevel() < level then return false end
    if track == "paid" and not M.IsPremium() then return false end
    if M.HasClaimed(level, track) then return false end
    local rewardDef = DataMon.GetBattlePassReward(level)
    if not rewardDef or not rewardDef[track] then return false end
    return true
end

--- 是否有任何可领取的奖励（供红点提示）
---@return boolean
function M.HasAnyClaimable()
    for _, lv in ipairs(DataMon.BATTLE_PASS_LEVELS) do
        if M.CanClaim(lv, "free") then return true end
        if M.CanClaim(lv, "paid") then return true end
    end
    return false
end

--- 获取完整状态（供 UI 使用）
---@return table
function M.GetStatus()
    local data = M.GetData()
    local curExp, totalExp = M.GetLevelProgress()
    return {
        seasonId       = data.seasonId or "",
        level          = M.GetLevel(),
        exp            = M.GetExp(),
        curLevelExp    = curExp,
        expPerLevel    = totalExp,
        isPremium      = M.IsPremium(),
        remainDays     = M.GetSeasonRemainDays(),
        maxLevel       = DataMon.BATTLE_PASS.maxLevel,
        premiumPrice   = DataMon.BATTLE_PASS.premiumPrice,
    }
end

-- ============================================================================
-- 操作
-- ============================================================================

--- 购买高级通行证
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.BuyPremium(callback)
    if M.IsPremium() then
        Toast.Show("本赛季已拥有高级通行证")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("battlepass_buy_premium", { playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            local p = GamePlayer.Get()
            if p then
                if not p.battlePassData then p.battlePassData = {} end
                p.battlePassData.isPremium = true
                p.battlePassData.seasonId = data.seasonId or GetCurrentSeasonId()
                -- 确保基础结构完整（防止 GetData() 返回空对象）
                if not p.battlePassData.exp then p.battlePassData.exp = 0 end
                if not p.battlePassData.claimedFree then p.battlePassData.claimedFree = {} end
                if not p.battlePassData.claimedPaid then p.battlePassData.claimedPaid = {} end
                if data.totalCharged and p.rechargeData then
                    p.rechargeData.totalCharged = data.totalCharged
                end
            end
            Toast.Show("高级通行证激活成功")
        else
            Toast.Show(data and data.msg or "购买失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "购买中..." })
end

--- 领取等级奖励
---@param level number
---@param track string "free"|"paid"
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.ClaimReward(level, track, callback)
    if not M.CanClaim(level, track) then
        Toast.Show("无法领取该奖励")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("battlepass_claim_reward", { level = level, track = track, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地缓存
            local p = GamePlayer.Get()
            if p and p.battlePassData then
                local claimedKey = (track == "free") and "claimedFree" or "claimedPaid"
                if not p.battlePassData[claimedKey] then p.battlePassData[claimedKey] = {} end
                p.battlePassData[claimedKey][tostring(level)] = true
            end
            Toast.Show("领取成功")
        else
            Toast.Show(data and data.msg or "领取失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "领取中..." })
end

--- 增加通行证经验
---@param source string 经验来源 key
---@param callback fun(ok: boolean, data: table|nil)|nil
function M.AddExp(source, callback)
    GameOps.Request("battlepass_add_exp", { source = source, playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            local p = GamePlayer.Get()
            if p then
                if not p.battlePassData then p.battlePassData = {} end
                p.battlePassData.exp = data.exp or p.battlePassData.exp or 0
                p.battlePassData.seasonId = data.seasonId or p.battlePassData.seasonId or GetCurrentSeasonId()
            end
            if data.levelUp then
                Toast.Show("通行证升级！当前Lv." .. (data.level or 0))
            end
        end
        if callback then callback(ok, data) end
    end)
end

return M
