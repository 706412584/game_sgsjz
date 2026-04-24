-- ============================================================================
-- 《问道长生》悟道模块
-- 职责：悟道参悟（增加进度、悟透奖励）
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer = require("game_player")
local GameItems  = require("game_items")
local DataSkills = require("data_skills")
local Router     = require("ui_router")

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- 每次参悟增加的进度范围
local PROGRESS_MIN = 5
local PROGRESS_MAX = 15

--- 获取每日免费悟道剩余次数
---@return number freeRemain, number freeTotal
function M.GetFreeRemain()
    local p = GamePlayer.Get()
    if not p then return 0, 0 end
    local freeTotal = DataSkills.FREE_MEDITATE_DAILY or 5
    local dd = p.daoDaily
    local today = os.date("%Y-%m-%d")
    if type(dd) ~= "table" or dd.date ~= today then
        return freeTotal, freeTotal  -- 新的一天，全部可用
    end
    local used = dd.freeUsed or 0
    return math.max(0, freeTotal - used), freeTotal
end

--- 获取每日道心获取进度
---@return number gained, number cap
function M.GetDailyDaoProgress()
    local p = GamePlayer.Get()
    if not p then return 0, 0 end
    local tier = p.tier or 1
    local cap = DataSkills.GetDailyDaoHeartCap(tier)
    local dd = p.daoDaily
    local today = os.date("%Y-%m-%d")
    if type(dd) ~= "table" or dd.date ~= today then
        return 0, cap
    end
    return dd.daoGained or 0, cap
end

--- 获取当前参悟所需修为（与服务端公式保持一致）
--- 免费次数内返回 0
---@param daoName string
---@return number cost
function M.GetMeditateCost(daoName)
    local p = GamePlayer.Get()
    if not p then return 0 end
    -- 免费次数内，消耗为0
    local freeRemain = M.GetFreeRemain()
    if freeRemain > 0 then return 0 end
    local tier = p.tier or 1
    local base = tier * 100
    for _, dao in ipairs(p.daoInsights or {}) do
        if dao.name == daoName then
            return base * ((dao.meditateCount or 0) + 1)
        end
    end
    return base
end

-- ============================================================================
-- 悟道参悟
-- ============================================================================

--- 检查是否可以参悟
---@param daoName string
---@return boolean, string|nil
function M.CanMeditate(daoName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local found = nil
    for _, dao in ipairs(p.daoInsights or {}) do
        if dao.name == daoName then
            found = dao
            break
        end
    end
    if not found then return false, "未拥有该悟道" end

    if found.locked then return false, "该悟道尚未解锁" end

    local maxProg = found.maxProgress or 100
    if (found.progress or 0) >= maxProg then
        return false, "已悟透此道"
    end

    -- 免费次数内跳过修为检查
    local freeRemain = M.GetFreeRemain()
    if freeRemain > 0 then
        return true, nil
    end

    -- 修为消耗前置校验（与服务端公式一致）
    local cost = M.GetMeditateCost(daoName)
    if (p.cultivation or 0) < cost then
        return false, string.format("修为不足（需要 %d）", cost)
    end

    return true, nil
end

--- 执行一次参悟
---@param daoName string
---@return boolean, string
function M.DoMeditate(daoName)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanMeditate(daoName)
        if not ok then return false, reason or "无法参悟" end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    local Toast = require("ui_toast")
    GameOps.Request("dao_meditate", {
        playerKey = GameServer.GetServerKey("player"),
        daoName   = daoName,
    }, function(ok2, data)
        if ok2 then
            local msg = data and data.msg or "参悟完成"
            GamePlayer.AddLog(msg)
            local variant = data and data.mastered and "success" or nil
            Toast.Show(msg, { variant = variant })
            Router.RebuildUI()  -- 就地刷新进度条，无需跳页
        else
            Toast.Show(data and data.msg or "参悟失败", { variant = "error" })
        end
    end, { loading = true })
    return true, nil
end

--- 检查是否有任意可参悟的道（红点用）
---@return boolean
function M.HasMeditatable()
    local p = GamePlayer.Get()
    if not p then return false end
    local freeRemain = M.GetFreeRemain()
    local cultivation = p.cultivation or 0
    for _, dao in ipairs(p.daoInsights or {}) do
        if not dao.locked and (dao.progress or 0) < (dao.maxProgress or 100) then
            -- 有免费次数时无需修为也能参悟
            if freeRemain > 0 then return true end
            local cost = M.GetMeditateCost(dao.name)
            if cultivation >= cost then
                return true
            end
        end
    end
    return false
end

return M
