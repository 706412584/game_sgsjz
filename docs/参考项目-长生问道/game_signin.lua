-- ============================================================================
-- 《问道长生》签到系统 - 客户端逻辑
-- 职责：签到状态缓存、GameOps 请求、广告加倍
-- ============================================================================

local GamePlayer     = require("game_player")
local GameOps        = require("network.game_ops")
local GameServer     = require("game_server")
local DataMon        = require("data_monetization")
local Toast          = require("ui_toast")
local GameAd         = require("game_ad")
local GameBattlePass = require("game_battlepass")

local M = {}

-- ============================================================================
-- 状态缓存
-- ============================================================================

--- 获取签到数据（从 playerData 中读取）
---@return table { totalDays, lastSignDate, todayAdWatched }
function M.GetData()
    local p = GamePlayer.Get()
    if not p then
        return { totalDays = 0, lastSignDate = "", todayAdWatched = false }
    end
    if not p.dailySignin then
        p.dailySignin = { totalDays = 0, lastSignDate = "", todayAdWatched = false }
    end
    return p.dailySignin
end

--- 今天是否已签到
---@return boolean
function M.HasSignedToday()
    local data = M.GetData()
    return data.lastSignDate == os.date("%Y-%m-%d")
end

--- 今天是否已看广告加倍
---@return boolean
function M.HasWatchedAd()
    local data = M.GetData()
    return data.todayAdWatched == true
end

--- 获取累计签到天数
---@return number
function M.GetTotalDays()
    return M.GetData().totalDays or 0
end

--- 获取当前周期的第几天（1~7）
---@return number
function M.GetDayInCycle()
    local total = M.GetTotalDays()
    if M.HasSignedToday() then
        -- 已签到：当前所在天
        return ((total - 1) % 7) + 1
    else
        -- 未签到：下一次签到将落在的天
        return (total % 7) + 1
    end
end

--- 获取今天的奖励配置
---@return table { day, free, ad }
function M.GetTodayReward()
    local total = M.GetTotalDays()
    if M.HasSignedToday() then
        return DataMon.GetSigninReward(total - 1)
    else
        return DataMon.GetSigninReward(total)
    end
end

-- ============================================================================
-- 请求：签到领取
-- ============================================================================

---@param callback fun(ok: boolean, data: table|nil)
function M.Claim(callback)
    if M.HasSignedToday() then
        Toast.Show("今日已签到")
        if callback then callback(false, nil) end
        return
    end

    GameOps.Request("signin_claim", { playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            -- 更新本地缓存
            local p = GamePlayer.Get()
            if p then
                p.dailySignin = p.dailySignin or {}
                p.dailySignin.totalDays = data.totalDays or p.dailySignin.totalDays
                p.dailySignin.lastSignDate = os.date("%Y-%m-%d")
                p.dailySignin.todayAdWatched = false
            end
            -- 显示奖励提示
            local reward = data.reward
            if reward then
                local parts = {}
                if reward.lingStone then
                    parts[#parts + 1] = "灵石+" .. reward.lingStone
                end
                if reward.item then
                    local cnt = reward.count or reward.itemCount or 1
                    parts[#parts + 1] = reward.item .. "x" .. cnt
                end
                if #parts > 0 then
                    Toast.Show("签到成功! " .. table.concat(parts, " "))
                else
                    Toast.Show("签到成功!")
                end
            else
                Toast.Show("签到成功!")
            end
            -- 签到成功后增加通行证经验
            GameBattlePass.AddExp("dailyLogin")
        else
            Toast.Show(data and data.msg or "签到失败")
        end
        if callback then callback(ok, data) end
    end, { loading = "签到中..." })
end

-- ============================================================================
-- 请求：广告加倍
-- ============================================================================

---@param callback fun(ok: boolean, data: table|nil)
function M.ClaimAdDouble(callback)
    if not M.HasSignedToday() then
        Toast.Show("请先签到")
        if callback then callback(false, nil) end
        return
    end
    if M.HasWatchedAd() then
        Toast.Show("今日已领取加倍奖励")
        if callback then callback(false, nil) end
        return
    end

    -- 通过广告管理器播放广告，成功后再请求服务端发放奖励
    GameAd.ShowAd("signin_double", function(adSuccess)
        if not adSuccess then
            if callback then callback(false, nil) end
            return
        end

        GameOps.Request("signin_ad_double", { playerKey = GameServer.GetServerKey("player") }, function(ok, data, sync)
        if ok then
            local p = GamePlayer.Get()
            if p and p.dailySignin then
                p.dailySignin.todayAdWatched = true
            end
            local adReward = data and data.adReward
            if adReward then
                local parts = {}
                if adReward.spiritStone then
                    parts[#parts + 1] = "仙石+" .. adReward.spiritStone
                end
                if adReward.lingStone then
                    parts[#parts + 1] = "灵石+" .. adReward.lingStone
                end
                if adReward.xianYuan then
                    parts[#parts + 1] = "仙缘+" .. adReward.xianYuan
                end
                if #parts > 0 then
                    Toast.Show("加倍领取! " .. table.concat(parts, " "))
                else
                    Toast.Show("加倍奖励已领取!")
                end
            else
                Toast.Show("加倍奖励已领取!")
            end
        else
            Toast.Show(data and data.msg or "领取失败")
        end
        if callback then callback(ok, data) end
        end, { loading = "领取中..." })
    end)
end

return M
