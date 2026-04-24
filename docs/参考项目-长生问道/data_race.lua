-- ============================================================================
-- 《问道长生》种族系统数据配置
-- 设计来源: docs/design-v2-cultivation-combat.md §二
-- ============================================================================

local M = {}

-- ============================================================================
-- 种族 ID 常量
-- ============================================================================
M.HUMAN   = "human"
M.DEMON   = "demon"
M.SPIRIT  = "spirit"
M.MONSTER = "monster"

-- ============================================================================
-- 种族定义
-- ============================================================================
M.RACES = {
    {
        id       = M.HUMAN,
        name     = "人族",
        desc     = "均衡全能，悟性出众，修行之路稳健前行。",
        position = "均衡全能",
        color    = { 200, 180, 140, 255 },  -- 暖黄
    },
    {
        id       = M.DEMON,
        name     = "魔族",
        desc     = "攻伐凌厉，以战养修，一念成魔万法皆破。",
        position = "攻击压制",
        color    = { 200, 80, 80, 255 },    -- 暗红
    },
    {
        id       = M.SPIRIT,
        name     = "灵族",
        desc     = "天生灵体，气血绵长，万邪不侵固若金汤。",
        position = "辅助防御",
        color    = { 100, 180, 220, 255 },  -- 灵蓝
    },
    {
        id       = M.MONSTER,
        name     = "妖族",
        desc     = "身法矫健，暴击凌厉，天生战体以力破巧。",
        position = "速度暴击",
        color    = { 120, 200, 100, 255 },  -- 妖绿
    },
}

--- 种族 ID → 中文名映射
M.LABEL = {
    [M.HUMAN]   = "人族",
    [M.DEMON]   = "魔族",
    [M.SPIRIT]  = "灵族",
    [M.MONSTER] = "妖族",
}

--- 种族 ID 有序列表（UI 遍历用）
M.LIST = { M.HUMAN, M.DEMON, M.SPIRIT, M.MONSTER }

-- ============================================================================
-- 种族初始加成（V2 设计 §2.1）
-- ============================================================================
-- 加成方式：absolute = 绝对值加算，percent = 百分比乘算
-- ============================================================================
M.INITIAL_BONUS = {
    [M.HUMAN] = {
        { stat = "wisdom",  value = 10,   mode = "absolute", desc = "悟性+10" },
        { stat = "cultivationSpeedPct", value = 0.05, mode = "percent", desc = "修炼速度+5%" },
    },
    [M.DEMON] = {
        { stat = "attack",  value = 0.15, mode = "percent",  desc = "攻击+15%" },
        { stat = "defense", value = -0.05, mode = "percent", desc = "防御-5%" },
    },
    [M.SPIRIT] = {
        { stat = "hpMax",   value = 0.10, mode = "percent",  desc = "气血+10%" },
        { stat = "dodge",   value = 3,    mode = "absolute", desc = "闪避+3%" },
    },
    [M.MONSTER] = {
        { stat = "speed",   value = 10,   mode = "absolute", desc = "速度+10" },
        { stat = "crit",    value = 3,    mode = "absolute", desc = "暴击+3%" },
    },
}

-- ============================================================================
-- 种族关系矩阵（V2 设计 §2.2）
-- ============================================================================
-- hostile = 敌对，ally = 同盟，neutral = 冷淡
-- ============================================================================
M.RELATION = {
    HOSTILE = "hostile",
    ALLY    = "ally",
    NEUTRAL = "neutral",
}

M.RELATION_MATRIX = {
    [M.HUMAN] = {
        [M.HUMAN]   = "ally",
        [M.DEMON]   = "hostile",
        [M.SPIRIT]  = "ally",
        [M.MONSTER] = "neutral",
    },
    [M.DEMON] = {
        [M.HUMAN]   = "hostile",
        [M.DEMON]   = "ally",
        [M.SPIRIT]  = "neutral",
        [M.MONSTER] = "ally",
    },
    [M.SPIRIT] = {
        [M.HUMAN]   = "ally",
        [M.DEMON]   = "neutral",
        [M.SPIRIT]  = "ally",
        [M.MONSTER] = "hostile",
    },
    [M.MONSTER] = {
        [M.HUMAN]   = "neutral",
        [M.DEMON]   = "ally",
        [M.SPIRIT]  = "hostile",
        [M.MONSTER] = "ally",
    },
}

--- 种族关系中文标签
M.RELATION_LABEL = {
    hostile = "敌对",
    ally    = "同盟",
    neutral = "冷淡",
}

--- 种族关系颜色
M.RELATION_COLOR = {
    hostile = { 220, 80, 60, 255 },   -- 红
    ally    = { 80, 200, 120, 255 },   -- 绿
    neutral = { 180, 170, 150, 255 },  -- 灰
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据种族 ID 获取种族定义
---@param raceId string
---@return table|nil
function M.GetRace(raceId)
    for _, r in ipairs(M.RACES) do
        if r.id == raceId then return r end
    end
    return nil
end

--- 获取两个种族之间的关系
---@param raceA string
---@param raceB string
---@return string "hostile"|"ally"|"neutral"
function M.GetRelation(raceA, raceB)
    local row = M.RELATION_MATRIX[raceA]
    if row then return row[raceB] or "neutral" end
    return "neutral"
end

--- 将种族初始加成应用到基础属性表上
--- stats: { attack, defense, hpMax, speed, crit, dodge, wisdom, ... }
---@param raceId string
---@param stats table 基础属性表（会被原地修改）
---@return table stats
function M.ApplyBonus(raceId, stats)
    local bonuses = M.INITIAL_BONUS[raceId]
    if not bonuses then return stats end
    for _, b in ipairs(bonuses) do
        local key = b.stat
        if key == "cultivationSpeedPct" then
            -- 特殊字段：修炼速度百分比，单独存储
            stats.cultivationSpeedPct = (stats.cultivationSpeedPct or 0) + b.value
        elseif b.mode == "absolute" then
            stats[key] = (stats[key] or 0) + b.value
        elseif b.mode == "percent" then
            stats[key] = math.floor((stats[key] or 0) * (1 + b.value))
        end
    end
    return stats
end

--- 获取种族加成描述文本列表
---@param raceId string
---@return string[]
function M.GetBonusDescs(raceId)
    local bonuses = M.INITIAL_BONUS[raceId]
    if not bonuses then return {} end
    local descs = {}
    for _, b in ipairs(bonuses) do
        descs[#descs + 1] = b.desc
    end
    return descs
end

--- 默认种族
M.DEFAULT = M.HUMAN

return M
