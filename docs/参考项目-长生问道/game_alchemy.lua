-- ============================================================================
-- 《问道长生》炼丹系统
-- 职责：材料校验、炼丹倒计时、服务端结算
-- 设计：Can/Do 模式 + 客户端倒计时门槛
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")
local GameQuest  = require("game_quest")
local NVG        = require("nvg_manager")
local Router     = require("ui_router")

local M = {}

local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 气运 → 炼丹成功率加成
-- ============================================================================
local FORTUNE_BONUS = {
    ["低迷"] = -5,
    ["普通"] = 0,
    ["小吉"] = 5,
    ["大吉"] = 10,
    ["天命"] = 15,
}

-- ============================================================================
-- 炼丹倒计时状态
-- ============================================================================
local ALCHEMY_UPDATE_KEY = "alchemy_timer"
local REBUILD_INTERVAL   = 0.5

---@class AlchemyState
local alchemyState_ = {
    active     = false,
    recipeId   = nil,   ---@type string|nil
    recipeName = nil,   ---@type string|nil
    duration   = 0,
    elapsed    = 0,
    rebuildAcc = 0,
    callback   = nil,   ---@type fun(ok: boolean, msg: string)|nil
}

-- ============================================================================
-- 丹方查询
-- ============================================================================

--- 获取玩家已解锁的丹方列表（按 knownRecipes 过滤）
---@return table[]
function M.GetAllRecipes()
    local p = GamePlayer.Get()
    local known = {}
    if p and p.knownRecipes then
        for _, id in ipairs(p.knownRecipes) do
            known[id] = true
        end
    else
        known["peiyuan"] = true  -- 兜底：至少有培元丹
    end

    local recipes = {}
    local allPills = {}
    for _, pill in ipairs(DataItems.PILLS_COMMON) do allPills[#allPills + 1] = pill end
    for _, pill in ipairs(DataItems.PILLS_LIMITED) do allPills[#allPills + 1] = pill end
    for _, pill in ipairs(DataItems.PILLS_BREAKTHROUGH) do allPills[#allPills + 1] = pill end
    for _, pill in ipairs(DataItems.PILLS_REQUIRED_BREAK) do allPills[#allPills + 1] = pill end
    for _, pill in ipairs(allPills) do
        if known[pill.id] then
            recipes[#recipes + 1] = pill
        end
    end
    return recipes
end

--- 获取全部丹方（不论是否解锁，用于 GM/调试）
---@return table[]
function M.GetAllRecipesDebug()
    local recipes = {}
    for _, p in ipairs(DataItems.PILLS_COMMON) do recipes[#recipes + 1] = p end
    for _, p in ipairs(DataItems.PILLS_LIMITED) do recipes[#recipes + 1] = p end
    for _, p in ipairs(DataItems.PILLS_BREAKTHROUGH) do recipes[#recipes + 1] = p end
    for _, p in ipairs(DataItems.PILLS_REQUIRED_BREAK) do recipes[#recipes + 1] = p end
    return recipes
end

--- 获取坊市可购买解锁的突破丹配方（按玩家当前境界过滤）
-- 规则：player.tier >= targetTier-1 且尚未解锁 → 可在坊市购买
---@return table[] { pill, alreadyKnown: bool }
function M.GetShopBreakthroughRecipes()
    local p = GamePlayer.Get()
    local currentTier = p and (p.tier or 1) or 1
    local known = {}
    if p and p.knownRecipes then
        for _, id in ipairs(p.knownRecipes) do
            known[id] = true
        end
    end

    local result = {}
    for _, pill in ipairs(DataItems.PILLS_REQUIRED_BREAK) do
        -- 当前境界 >= targetTier-1 时可在坊市出现（提前准备材料）
        if currentTier >= (pill.targetTier - 1) then
            result[#result + 1] = {
                pill        = pill,
                alreadyKnown = known[pill.id] == true,
            }
        end
    end
    return result
end

--- 根据 id 查找丹方
---@param recipeId string
---@return table|nil
function M.FindRecipe(recipeId)
    return DataItems.FindPill(recipeId)
end

--- 解锁一个丹方（由游历/坊市系统调用）
---@param recipeId string
---@return boolean ok, string msg
function M.UnlockRecipe(recipeId)
    local p = GamePlayer.Get()
    if not p then return false, "无角色数据" end
    -- 检查配方是否存在
    if not DataItems.FindPill(recipeId) then
        return false, "丹方不存在: " .. recipeId
    end
    p.knownRecipes = p.knownRecipes or { "peiyuan" }
    for _, id in ipairs(p.knownRecipes) do
        if id == recipeId then return false, "已拥有该丹方" end
    end
    p.knownRecipes[#p.knownRecipes + 1] = recipeId
    GamePlayer.MarkDirty()
    local recipe = DataItems.FindPill(recipeId)
    return true, "获得丹方：" .. (recipe and recipe.name or recipeId)
end

--- 检查玩家是否已解锁某丹方
---@param recipeId string
---@return boolean
function M.IsRecipeKnown(recipeId)
    local p = GamePlayer.Get()
    if not p or not p.knownRecipes then return recipeId == "peiyuan" end
    for _, id in ipairs(p.knownRecipes) do
        if id == recipeId then return true end
    end
    return false
end

--- 根据名称查找丹方
---@param name string
---@return table|nil
function M.FindRecipeByName(name)
    return DataItems.FindPillByName(name)
end

-- ============================================================================
-- 材料查询
-- ============================================================================

--- 获取背包中某材料的数量
---@param matName string
---@return number
function M.GetMaterialCount(matName)
    local p = GamePlayer.Get()
    if not p then return 0 end
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == matName then
            return item.count or 0
        end
    end
    return 0
end

--- 检查某丹方各材料的持有情况
---@param recipeId string
---@return table[] { name, need, have, enough }
function M.CheckMaterials(recipeId)
    local recipe = DataItems.FindPill(recipeId)
    if not recipe or not recipe.materials then return {} end
    local result = {}
    for matName, needCount in pairs(recipe.materials) do
        local have = M.GetMaterialCount(matName)
        result[#result + 1] = {
            name   = matName,
            need   = needCount,
            have   = have,
            enough = have >= needCount,
        }
    end
    return result
end

-- ============================================================================
-- 炼丹：Can/Do（倒计时 → 服务端结算）
-- ============================================================================

--- 检查是否可以炼制某丹药
---@param recipeId string 丹方 id
---@return boolean, string|nil
function M.CanAlchemy(recipeId)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local recipe = DataItems.FindPill(recipeId)
    if not recipe then return false, "未知丹方" end
    if not recipe.materials then return false, "丹方缺少材料配置" end

    for matName, needCount in pairs(recipe.materials) do
        local have = M.GetMaterialCount(matName)
        if have < needCount then
            return false, matName .. "不足"
        end
    end

    return true, nil
end

--- 持久化炼丹状态到 playerData（重登后可恢复）
--- 联网模式下必须 force=true 强制写入，否则 MarkDirty 不会实际保存
local function SaveAlchemyState(recipeId, startTs, duration)
    local p = GamePlayer.Get()
    if not p then return end
    p.alchemyActive = {
        recipeId = recipeId,
        startTs  = startTs,
        duration = duration,
    }
    GamePlayer.Save(nil, true)  -- force=true: 确保联网模式也写入 serverCloud
end

--- 清除持久化的炼丹状态
local function ClearAlchemyState()
    local p = GamePlayer.Get()
    if not p then return end
    p.alchemyActive = nil
    GamePlayer.Save(nil, true)  -- force=true: 确保联网模式也写入 serverCloud
end

--- 内部：倒计时结束后提交服务端
local function SubmitAlchemy(recipeId, cb)
    local recipe = DataItems.FindPill(recipeId)
    local GameOps    = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("alchemy_craft", {
        recipeId  = recipeId,
        playerKey = GameServer.GetServerKey("player"),
    }, function(ok2, data)
        if ok2 then
            local success = data.success
            local msg
            if success then
                GameQuest.NotifyAction("alchemy_success", 1)
                msg = "炼丹成功: " .. (data.pillName or (recipe and recipe.name) or "丹药")
                GamePlayer.AddLog(msg)
            else
                msg = "炼丹失败，材料已消耗"
                GamePlayer.AddLog(msg)
            end
            if cb then cb(success, msg) end
        else
            local Toast = require("ui_toast")
            Toast.Show(data.msg or data.error or "炼丹失败", "error")
            if cb then cb(false, data.msg or data.error or "炼丹失败") end
        end
        -- 刷新 UI（如果当前在炼丹页）
        if Router.GetCurrentState() == Router.STATE_ALCHEMY then
            Router.RebuildUI()
        end
    end, { loading = "提交炼丹..." })
end

--- 炼丹倒计时更新（由 NVG.Register 驱动）
function M.UpdateAlchemy(dt)
    if not alchemyState_.active then return end

    alchemyState_.elapsed = alchemyState_.elapsed + dt

    -- 定期刷新 UI
    alchemyState_.rebuildAcc = alchemyState_.rebuildAcc + dt
    if alchemyState_.rebuildAcc >= REBUILD_INTERVAL then
        alchemyState_.rebuildAcc = 0
        if Router.GetCurrentState() == Router.STATE_ALCHEMY then
            Router.RebuildUI()
        end
    end

    -- 倒计时结束 → 提交服务端
    if alchemyState_.elapsed >= alchemyState_.duration then
        local recipeId = alchemyState_.recipeId
        local cb       = alchemyState_.callback
        NVG.Unregister(ALCHEMY_UPDATE_KEY)
        alchemyState_.active   = false
        alchemyState_.callback = nil
        ClearAlchemyState()
        SubmitAlchemy(recipeId, cb)
    end
end

--- 开始炼丹（启动倒计时，倒计时结束后自动提交服务端）
---@param recipeId string 丹方 id
---@param callback? fun(success: boolean, message: string)
---@return boolean started, string message
function M.DoAlchemy(recipeId, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    if alchemyState_.active then
        local msg = "炼丹炉正在炼制中"
        if callback then callback(false, msg) end
        return false, msg
    end

    -- 网络模式：跳过客户端材料校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanAlchemy(recipeId)
        if not ok then
            if callback then callback(false, reason or "无法炼丹") end
            return false, reason or "无法炼丹"
        end
    end

    local recipe   = DataItems.FindPill(recipeId)
    local duration = (recipe and recipe.time) or 30
    local startTs  = os.time()

    alchemyState_.active     = true
    alchemyState_.recipeId   = recipeId
    alchemyState_.recipeName = recipe and recipe.name or "丹药"
    alchemyState_.duration   = duration
    alchemyState_.elapsed    = 0
    alchemyState_.rebuildAcc = 0
    alchemyState_.callback   = callback

    -- 持久化到 playerData
    SaveAlchemyState(recipeId, startTs, duration)

    NVG.Register(ALCHEMY_UPDATE_KEY, nil, function(dt)
        M.UpdateAlchemy(dt)
    end)

    return true, "开始炼制"
end

-- ============================================================================
-- 倒计时查询 API
-- ============================================================================

--- 炼丹是否进行中
---@return boolean
function M.IsAlchemyActive()
    return alchemyState_.active
end

--- 获取炼丹进度
---@return table|nil { elapsed, duration, recipeName, recipeId, progress }
function M.GetAlchemyProgress()
    if not alchemyState_.active then return nil end
    return {
        elapsed    = alchemyState_.elapsed,
        duration   = alchemyState_.duration,
        recipeName = alchemyState_.recipeName,
        recipeId   = alchemyState_.recipeId,
        progress   = math.min(1.0, alchemyState_.elapsed / alchemyState_.duration),
    }
end

--- 取消炼制（材料不消耗，因为服务端未被调用）
---@return boolean, string
function M.CancelAlchemy()
    if not alchemyState_.active then
        return false, "当前没有炼丹进行中"
    end
    NVG.Unregister(ALCHEMY_UPDATE_KEY)
    local name = alchemyState_.recipeName or "丹药"
    alchemyState_.active   = false
    alchemyState_.callback = nil
    ClearAlchemyState()
    if Router.GetCurrentState() == Router.STATE_ALCHEMY then
        Router.RebuildUI()
    end
    return true, "已取消炼制" .. name
end

-- ============================================================================
-- 登录恢复炼丹状态
-- ============================================================================

--- 登录后调用：检查 playerData.alchemyActive，恢复倒计时
function M.RestoreFromSave()
    if alchemyState_.active then return end  -- 已有进行中的炼丹
    local p = GamePlayer.Get()
    if not p or not p.alchemyActive then return end

    local aa = p.alchemyActive
    local recipeId = aa.recipeId
    local startTs  = aa.startTs or 0
    local duration = aa.duration or 30
    local now      = os.time()
    local elapsed  = now - startTs

    if elapsed >= duration then
        -- 离线期间已炼完 → 直接提交服务端结算
        print("[Alchemy] RestoreFromSave: 已过期，直接提交结算 recipeId=" .. tostring(recipeId))
        p.alchemyActive = nil
        GamePlayer.Save(nil, true)  -- force=true: 清除过期状态
        SubmitAlchemy(recipeId, function(ok2, msg2)
            local Toast = require("ui_toast")
            Toast.Show(msg2, { variant = ok2 and "success" or "error" })
        end)
        return
    end

    -- 尚未炼完 → 恢复倒计时
    local recipe = DataItems.FindPill(recipeId)
    print("[Alchemy] RestoreFromSave: 恢复倒计时 recipeId=" .. tostring(recipeId)
        .. " elapsed=" .. elapsed .. "/" .. duration)

    alchemyState_.active     = true
    alchemyState_.recipeId   = recipeId
    alchemyState_.recipeName = recipe and recipe.name or "丹药"
    alchemyState_.duration   = duration
    alchemyState_.elapsed    = elapsed
    alchemyState_.rebuildAcc = 0
    alchemyState_.callback   = function(ok2, msg2)
        local Toast = require("ui_toast")
        Toast.Show(msg2, { variant = ok2 and "success" or "error" })
    end

    NVG.Register(ALCHEMY_UPDATE_KEY, nil, function(dt)
        M.UpdateAlchemy(dt)
    end)
end

-- ============================================================================
-- 兼容接口
-- ============================================================================

function M.CanAlchemyByName(pillName)
    local recipe = DataItems.FindPillByName(pillName)
    if not recipe then return false, "未知丹方: " .. pillName end
    return M.CanAlchemy(recipe.id)
end

---@param pillName string
---@param callback? fun(success: boolean, message: string)
---@return boolean, string
function M.DoAlchemyByName(pillName, callback)
    local recipe = DataItems.FindPillByName(pillName)
    if not recipe then
        if callback then callback(false, "未知丹方: " .. pillName) end
        return false, "未知丹方: " .. pillName
    end
    return M.DoAlchemy(recipe.id, callback)
end

return M
