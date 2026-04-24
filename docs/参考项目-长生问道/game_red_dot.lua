-- ============================================================================
-- 《问道长生》红点规则引擎
-- 集中管理所有红点的判断逻辑，提供 RefreshAll / Refresh 接口
-- 由 GameOps.ApplySync / 页面进入 等时机触发
-- ============================================================================

local RedDot      = require("ui_red_dot")
local GamePlayer  = require("game_player")

local M = {}

-- ============================================================================
-- 延迟加载业务模块（避免循环依赖）
-- ============================================================================
local modules_ = {}
local function GetModule(name)
    if not modules_[name] then
        local ok, mod = pcall(require, name)
        if ok then modules_[name] = mod end
    end
    return modules_[name]
end

-- ============================================================================
-- 红点规则表：key → checker(playerData) → boolean
-- 返回 true 表示应显示红点
-- ============================================================================
local RULES = {}
local KEYS = RedDot.KEYS

-- 洞府功能按钮
RULES[KEYS.HOME_SKILL] = function()
    local mod = GetModule("game_skill")
    if mod and mod.CanTrainCultArt then
        local ok = mod.CanTrainCultArt()
        return ok == true
    end
    return false
end

RULES[KEYS.HOME_ARTIFACT] = function()
    local mod = GetModule("game_artifact")
    if mod and mod.HasUpgradeable then
        return mod.HasUpgradeable()
    end
    return false
end

RULES[KEYS.HOME_DAO] = function()
    local mod = GetModule("game_dao")
    if mod and mod.HasMeditatable then
        return mod.HasMeditatable()
    end
    return false
end

RULES[KEYS.HOME_TRIBULATION] = function()
    local mod = GetModule("game_cultivation")
    if mod and mod.CanTribulation then
        local ok = mod.CanTribulation()
        return ok == true
    end
    return false
end

RULES[KEYS.HOME_PILL] = function()
    local mod = GetModule("game_items")
    if mod and mod.HasUsablePill then
        return mod.HasUsablePill()
    end
    return false
end

-- 更多页面
RULES[KEYS.MORE_QUEST] = function()
    local mod = GetModule("game_quest")
    if mod and mod.GetClaimableCount then
        return mod.GetClaimableCount() > 0
    end
    return false
end

RULES[KEYS.MORE_SECT] = function()
    local mod = GetModule("game_sect")
    if mod and mod.HasPending then
        return mod.HasPending()
    end
    return false
end

-- 灵宠
RULES[KEYS.NAV_PET] = function()
    local mod = GetModule("game_pet")
    if mod and mod.HasLevelUpReady then
        return mod.HasLevelUpReady()
    end
    return false
end

RULES[KEYS.MORE_TRIAL] = function()
    local mod = GetModule("game_dao_trial")
    if mod and mod.HasAvailable then
        return mod.HasAvailable()
    end
    return false
end

-- ============================================================================
-- 冒泡规则：子红点可见 → 父导航按钮可见
-- ============================================================================
local BUBBLE_MAP = {
    [KEYS.NAV_HOME] = {
        KEYS.HOME_SKILL,
        KEYS.HOME_ARTIFACT,
        KEYS.HOME_DAO,
        KEYS.HOME_TRIBULATION,
        KEYS.HOME_PILL,
        KEYS.HOME_ATTR,
    },
    [KEYS.NAV_MORE] = {
        KEYS.MORE_QUEST,
        KEYS.MORE_SECT,
        KEYS.MORE_ALCHEMY,
        KEYS.MORE_EXPLORE,
        KEYS.MORE_CHAT,
        KEYS.MORE_MARKET,
        KEYS.MORE_RANKING,
        KEYS.MORE_TRIAL,
    },
}

local function RefreshBubbles()
    for parentKey, childKeys in pairs(BUBBLE_MAP) do
        local anyVisible = false
        for _, ck in ipairs(childKeys) do
            if RedDot.IsVisible(ck) then
                anyVisible = true
                break
            end
        end
        if anyVisible then
            RedDot.Show(parentKey)
        else
            RedDot.Hide(parentKey)
        end
    end
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 刷新所有红点（数据加载完成、ApplySync 后调用）
function M.RefreshAll()
    local p = GamePlayer.Get()
    if not p then return end

    for key, checker in pairs(RULES) do
        local ok, show = pcall(checker)
        if ok and show then
            RedDot.Show(key)
        else
            RedDot.Hide(key)
        end
    end

    RefreshBubbles()
end

--- 刷新单个红点
---@param key string
function M.Refresh(key)
    local checker = RULES[key]
    if not checker then return end

    local ok, show = pcall(checker)
    if ok and show then
        RedDot.Show(key)
    else
        RedDot.Hide(key)
    end

    -- 刷新关联的冒泡
    RefreshBubbles()
end

--- 刷新指定模块相关的红点
---@param module string 模块标识（"skill"/"artifact"/"dao"/"cultivation"/"pill"/"quest"/"sect"/"pet"）
function M.RefreshModule(module)
    local keyMap = {
        skill       = KEYS.HOME_SKILL,
        artifact    = KEYS.HOME_ARTIFACT,
        dao         = KEYS.HOME_DAO,
        cultivation = KEYS.HOME_TRIBULATION,
        pill        = KEYS.HOME_PILL,
        quest       = KEYS.MORE_QUEST,
        sect        = KEYS.MORE_SECT,
        pet         = KEYS.NAV_PET,
        trial       = KEYS.MORE_TRIAL,
    }
    local key = keyMap[module]
    if key then M.Refresh(key) end
end

return M
