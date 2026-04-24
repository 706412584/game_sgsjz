-- ============================================================================
-- 《问道长生》功法管理模块（V2 拆分版）
-- 职责：修炼功法升级 + 武学功法升级/装备/卸下
-- 设计：Can/Do 模式，所有变更走 GameOps 服务端验证
-- ============================================================================

local GamePlayer      = require("game_player")
local DataCultArts    = require("data_cultivation_arts")
local DataMartialArts = require("data_martial_arts")

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 修炼功法：升级
-- ============================================================================

--- 检查是否可以升级修炼功法
---@return boolean, string|nil
function M.CanTrainCultArt()
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local cultArt = p.cultivationArt
    if not cultArt or not cultArt.id then return false, "未装备修炼功法" end

    local artDef = DataCultArts.GetArt(cultArt.id)
    if not artDef then return false, "功法数据异常" end

    local level = cultArt.level or 1
    if level >= #DataCultArts.LEVELS then return false, "功法已达最高等级" end

    local nextLv = DataCultArts.GetLevel(level + 1)
    if not nextLv then return false, "无法获取升级配置" end

    if (p.wisdom or 0) < nextLv.wisdomReq then
        return false, "悟性不足（需要" .. nextLv.wisdomReq .. "）"
    end

    return true, nil
end

--- 执行修炼功法升级
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoTrainCultArt(callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanTrainCultArt()
        if not ok then
            local Toast = require("ui_toast")
            Toast.Show(reason or "无法修炼功法", "error")
            if callback then callback(false, reason) end
            return false, reason or "无法修炼"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("cult_art_train", {
        playerKey = GameServer.GetServerKey("player"),
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local msg = data and data.msg or "修炼功法升级成功"
            GamePlayer.AddLog(msg)
            local Toast = require("ui_toast")
            Toast.Show(msg)
            if callback then callback(true, msg) end
        else
            local msg = data and data.msg or "修炼功法升级失败"
            local Toast = require("ui_toast")
            Toast.Show(msg, "error")
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

--- 检查是否可以切换修炼功法
---@param artId string 目标功法 ID
---@return boolean, string|nil
function M.CanSwitchCultArt(artId)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local artDef = DataCultArts.GetArt(artId)
    if not artDef then return false, "功法不存在" end

    -- 阵营检查
    local canUse, msg = DataCultArts.CanUse(p.race or "human", artId)
    if not canUse then return false, msg end

    -- 当前已装备检查
    local cultArt = p.cultivationArt
    if cultArt and cultArt.id == artId then return false, "已装备该功法" end

    return true, nil
end

--- 切换修炼功法（需先拥有，走 GameOps）
---@param artId string
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoSwitchCultArt(artId, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanSwitchCultArt(artId)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法切换"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("cult_art_switch", {
        playerKey = GameServer.GetServerKey("player"),
        artId = artId,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local msg = data and data.msg or "切换修炼功法成功"
            GamePlayer.AddLog(msg)
            local Toast = require("ui_toast")
            Toast.Show(msg)
            if callback then callback(true, msg) end
        else
            local msg = data and data.msg or "切换失败"
            local Toast = require("ui_toast")
            Toast.Show(msg, "error")
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

-- ============================================================================
-- 武学功法：升级
-- ============================================================================

--- 检查是否可以升级武学
---@param artId string
---@return boolean, string|nil
function M.CanTrainMartialArt(artId)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local ma = p.martialArts
    if not ma then return false, "无武学数据" end

    -- 检查是否拥有
    local found = nil
    for _, owned in ipairs(ma.owned or {}) do
        if owned.id == artId then
            found = owned
            break
        end
    end
    if not found then return false, "未拥有该武学" end

    local artDef = DataMartialArts.GetArt(artId)
    if not artDef then return false, "武学数据异常" end

    local level = found.level or 1
    if level >= (artDef.maxLevel or 10) then return false, "武学已达最高等级" end

    local nextLv = DataMartialArts.GetLevel(level + 1)
    if not nextLv then return false, "无法获取升级配置" end

    if (p.wisdom or 0) < nextLv.wisdomReq then
        return false, "悟性不足（需要" .. nextLv.wisdomReq .. "）"
    end

    return true, nil
end

--- 执行武学升级
---@param artId string
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoTrainMartialArt(artId, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanTrainMartialArt(artId)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法修炼"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("martial_art_train", {
        playerKey = GameServer.GetServerKey("player"),
        artId = artId,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local msg = data and data.msg or "武学升级成功"
            GamePlayer.AddLog(msg)
            local Toast = require("ui_toast")
            Toast.Show(msg)
            if callback then callback(true, msg) end
        else
            local msg = data and data.msg or "武学升级失败"
            local Toast = require("ui_toast")
            Toast.Show(msg, "error")
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

-- ============================================================================
-- 武学功法：装备 / 卸下
-- ============================================================================

--- 检查是否可以装备武学到指定槽位
---@param artId string
---@param slot? number 槽位 1~3，nil=自动选空槽
---@return boolean, string|nil
function M.CanEquipMartialArt(artId, slot)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local ma = p.martialArts
    if not ma then return false, "无武学数据" end

    -- 检查拥有
    local found = false
    for _, owned in ipairs(ma.owned or {}) do
        if owned.id == artId then found = true; break end
    end
    if not found then return false, "未拥有该武学" end

    -- 品阶境界检查
    local canEquip, msg = DataMartialArts.CanEquip(p.tier or 1, artId)
    if not canEquip then return false, msg end

    -- 检查是否已装备
    local equipped = ma.equipped or {}
    for i = 1, DataMartialArts.MAX_EQUIPPED do
        if equipped[i] == artId then return false, "已装备该武学" end
    end

    -- 槽位检查
    if slot then
        if slot < 1 or slot > DataMartialArts.MAX_EQUIPPED then
            return false, "无效槽位"
        end
    else
        -- 查找空槽
        local hasSlot = false
        for i = 1, DataMartialArts.MAX_EQUIPPED do
            if not equipped[i] then hasSlot = true; break end
        end
        if not hasSlot then return false, "装备栏已满，请先卸下一个武学" end
    end

    return true, nil
end

--- 装备武学
---@param artId string
---@param slot? number
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoEquipMartialArt(artId, slot, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanEquipMartialArt(artId, slot)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法装备"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("martial_art_equip", {
        playerKey = GameServer.GetServerKey("player"),
        artId = artId,
        slot = slot,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local artDef = DataMartialArts.GetArt(artId)
            local msg = "装备武学：" .. (artDef and artDef.name or artId)
            local Toast = require("ui_toast")
            Toast.Show(msg)
            if callback then callback(true, msg) end
        else
            local msg = data and data.msg or "装备失败"
            local Toast = require("ui_toast")
            Toast.Show(msg, "error")
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

--- 卸下武学
---@param slot number 槽位 1~3
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoUnequipMartialArt(slot, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    local p = GamePlayer.Get()
    if not p then
        if callback then callback(false, "数据未加载") end
        return false, "数据未加载"
    end

    local ma = p.martialArts
    local equipped = ma and ma.equipped or {}
    if not equipped[slot] then
        if callback then callback(false, "该槽位无武学") end
        return false, "该槽位无武学"
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("martial_art_unequip", {
        playerKey = GameServer.GetServerKey("player"),
        slot = slot,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local Toast = require("ui_toast")
            Toast.Show("已卸下武学")
            if callback then callback(true, "已卸下武学") end
        else
            local msg = data and data.msg or "卸下失败"
            local Toast = require("ui_toast")
            Toast.Show(msg, "error")
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

-- ============================================================================
-- 查询辅助
-- ============================================================================

--- 获取当前修炼功法信息（含等级、加成等）
---@return table|nil { id, name, level, maxLevel, bonus, desc, faction }
function M.GetCultArtInfo()
    local p = GamePlayer.Get()
    if not p or not p.cultivationArt then return nil end

    local ca = p.cultivationArt
    local artDef = DataCultArts.GetArt(ca.id)
    if not artDef then return nil end

    local level = ca.level or 1
    return {
        id       = ca.id,
        name     = artDef.name,
        level    = level,
        maxLevel = #DataCultArts.LEVELS,
        bonus    = DataCultArts.CalcBonus(ca.id, level),
        desc     = artDef.desc,
        faction  = artDef.faction,
    }
end

--- 获取已装备的武学列表（3 个槽位）
---@return table[] slots { [1..3] = { id, name, level, element, grade, ... } | nil }
function M.GetEquippedMartialArts()
    local p = GamePlayer.Get()
    if not p or not p.martialArts then return {} end

    local equipped = p.martialArts.equipped or {}
    local owned = p.martialArts.owned or {}
    local slots = {}

    for i = 1, DataMartialArts.MAX_EQUIPPED do
        local artId = equipped[i]
        if artId then
            local artDef = DataMartialArts.GetArt(artId)
            -- 查找等级
            local level = 1
            for _, o in ipairs(owned) do
                if o.id == artId then level = o.level or 1; break end
            end
            if artDef then
                local gradeInfo = DataMartialArts.GRADE_INFO[artDef.grade]
                slots[i] = {
                    id       = artId,
                    name     = artDef.name,
                    level    = level,
                    maxLevel = artDef.maxLevel or 10,
                    element  = artDef.element,
                    elementName = DataMartialArts.ELEMENT_NAMES[artDef.element] or "?",
                    grade    = artDef.grade,
                    gradeName = gradeInfo and gradeInfo.name or "?",
                    desc     = artDef.desc,
                    baseDamage = DataMartialArts.CalcBaseDamage(artId, level),
                }
            end
        end
    end

    return slots
end

--- 获取所有已拥有的武学列表
---@return table[]
function M.GetOwnedMartialArts()
    local p = GamePlayer.Get()
    if not p or not p.martialArts then return {} end

    local owned = p.martialArts.owned or {}
    local equipped = p.martialArts.equipped or {}
    local equippedSet = {}
    for i = 1, DataMartialArts.MAX_EQUIPPED do
        if equipped[i] then equippedSet[equipped[i]] = i end
    end

    local result = {}
    for _, o in ipairs(owned) do
        local artDef = DataMartialArts.GetArt(o.id)
        if artDef then
            local gradeInfo = DataMartialArts.GRADE_INFO[artDef.grade]
            result[#result + 1] = {
                id          = o.id,
                name        = artDef.name,
                level       = o.level or 1,
                maxLevel    = artDef.maxLevel or 10,
                element     = artDef.element,
                elementName = DataMartialArts.ELEMENT_NAMES[artDef.element] or "?",
                grade       = artDef.grade,
                gradeName   = gradeInfo and gradeInfo.name or "?",
                desc        = artDef.desc,
                equippedSlot = equippedSet[o.id],
                baseDamage  = DataMartialArts.CalcBaseDamage(o.id, o.level or 1),
            }
        end
    end

    return result
end

return M
