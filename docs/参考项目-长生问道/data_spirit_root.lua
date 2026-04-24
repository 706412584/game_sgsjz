-- ============================================================================
-- 《问道长生》V2 灵根系统数据模块
-- 五行灵根类型 + 品质体系 + 多灵根觉醒 + 旧数据迁移
-- ============================================================================

local M = {}

-- ============================================================================
-- 1. 灵根类型定义
-- ============================================================================

--- 基础灵根（创角可选）
M.GOLD  = "gold"
M.WOOD  = "wood"
M.WATER = "water"
M.FIRE  = "fire"
M.EARTH = "earth"

--- 复合灵根（元婴/合道觉醒）
M.THUNDER = "thunder"  -- 火+土
M.YIN     = "yin"      -- 水+木
M.YANG    = "yang"     -- 火+金
M.WIND    = "wind"     -- 木+金
M.ICE     = "ice"      -- 水+土

--- 灵根详细信息
M.TYPES = {
    [M.GOLD]  = { name = "金灵根", element = "gold",  color = {255, 215, 0, 255} },
    [M.WOOD]  = { name = "木灵根", element = "wood",  color = {34, 180, 34, 255} },
    [M.WATER] = { name = "水灵根", element = "water", color = {30, 144, 255, 255} },
    [M.FIRE]  = { name = "火灵根", element = "fire",  color = {255, 80, 20, 255} },
    [M.EARTH] = { name = "土灵根", element = "earth", color = {160, 130, 80, 255} },
    -- 复合灵根
    [M.THUNDER] = { name = "雷灵根", element = "thunder", compose = {M.FIRE, M.EARTH}, color = {180, 100, 255, 255} },
    [M.YIN]     = { name = "阴灵根", element = "yin",     compose = {M.WATER, M.WOOD}, color = {100, 80, 160, 255} },
    [M.YANG]    = { name = "阳灵根", element = "yang",    compose = {M.FIRE, M.GOLD},  color = {255, 200, 100, 255} },
    [M.WIND]    = { name = "风灵根", element = "wind",    compose = {M.WOOD, M.GOLD},  color = {150, 220, 180, 255} },
    [M.ICE]     = { name = "冰灵根", element = "ice",     compose = {M.WATER, M.EARTH}, color = {140, 220, 255, 255} },
}

--- 基础灵根列表（创角选择用）
M.BASE_LIST = { M.GOLD, M.WOOD, M.WATER, M.FIRE, M.EARTH }

--- 复合灵根列表
M.COMPOSITE_LIST = { M.THUNDER, M.YIN, M.YANG, M.WIND, M.ICE }

--- 全部灵根列表（觉醒池）
M.ALL_LIST = { M.GOLD, M.WOOD, M.WATER, M.FIRE, M.EARTH, M.THUNDER, M.YIN, M.YANG, M.WIND, M.ICE }

-- ============================================================================
-- 2. 品质定义（保留原有体系）
-- ============================================================================

M.QUALITIES = {
    { id = "waste",  name = "废品", rate = 0.5, prob = 10 },
    { id = "low",    name = "下品", rate = 0.8, prob = 30 },
    { id = "mid",    name = "中品", rate = 1.0, prob = 35 },
    { id = "upper",  name = "上品", rate = 1.5, prob = 20 },
    { id = "heaven", name = "天品", rate = 2.0, prob = 5 },
}

--- 品质 id → 配置 的查找表
M.QUALITY_MAP = {}
for _, q in ipairs(M.QUALITIES) do
    M.QUALITY_MAP[q.id] = q
end

-- ============================================================================
-- 3. 数量倍率
-- ============================================================================

M.COUNT_MULTIPLIER = { [1] = 1.0, [2] = 1.3, [3] = 1.6 }

-- ============================================================================
-- 4. 觉醒触发境界
-- ============================================================================

--- tier 值对应觉醒的 slot（元婴=5→slot2, 合道=8→slot3）
M.AWAKEN_TIERS = { [5] = 2, [8] = 3 }

-- ============================================================================
-- 函数
-- ============================================================================

--- 按概率随机品质
---@return string qualityId
function M.RandomQuality()
    local roll = math.random(100)
    local acc = 0
    for _, q in ipairs(M.QUALITIES) do
        acc = acc + q.prob
        if roll <= acc then return q.id end
    end
    return "mid"
end

--- 获取品质倍率
---@param qualityId string
---@return number
function M.GetQualityRate(qualityId)
    local q = M.QUALITY_MAP[qualityId]
    return q and q.rate or 1.0
end

--- 获取品质显示名
---@param qualityId string
---@return string
function M.GetQualityName(qualityId)
    local q = M.QUALITY_MAP[qualityId]
    return q and q.name or "未知"
end

--- 计算灵根综合修炼倍率：数量倍率 x 最高品质倍率
---@param roots table spiritRoots 数组
---@return number
function M.CalcMultiplier(roots)
    if not roots or #roots == 0 then return 1.0 end
    local count = math.min(#roots, 3)
    local countMul = M.COUNT_MULTIPLIER[count] or 1.0
    -- 取最高品质倍率
    local maxRate = 0
    for _, r in ipairs(roots) do
        local rate = M.GetQualityRate(r.quality)
        if rate > maxRate then maxRate = rate end
    end
    if maxRate == 0 then maxRate = 1.0 end
    return countMul * maxRate
end

--- 获取灵根显示名称（如"火灵根-上品"）
---@param root table { type, quality, slot }
---@return string
function M.GetDisplayName(root)
    local t = M.TYPES[root.type]
    local typeName = t and t.name or "未知灵根"
    local qualName = M.GetQualityName(root.quality)
    return typeName .. "-" .. qualName
end

--- 获取灵根颜色
---@param root table
---@return table rgba
function M.GetColor(root)
    local t = M.TYPES[root.type]
    return t and t.color or {200, 200, 200, 255}
end

--- 获取已有灵根的基础属性集合（用于觉醒冲突检测）
---@param roots table spiritRoots 数组
---@return table set { gold=true, fire=true, ... }
local function GetOwnedElements(roots)
    local set = {}
    for _, r in ipairs(roots) do
        local t = M.TYPES[r.type]
        if t then
            if t.compose then
                for _, e in ipairs(t.compose) do set[e] = true end
            else
                set[r.type] = true
            end
        end
    end
    return set
end

--- 检查某个灵根类型是否可以觉醒（不与已有基础属性冲突）
---@param roots table 已有灵根数组
---@param typeId string 待觉醒灵根类型
---@return boolean
function M.CanAwaken(roots, typeId)
    local owned = GetOwnedElements(roots)
    local t = M.TYPES[typeId]
    if not t then return false end
    if t.compose then
        -- 复合灵根：组成属性不能与已有基础灵根重复
        for _, e in ipairs(t.compose) do
            if owned[e] then return false end
        end
    else
        -- 基础灵根：不能重复
        if owned[typeId] then return false end
    end
    return true
end

--- 随机觉醒一个新灵根（元婴/合道触发）
---@param roots table 已有灵根数组
---@param slot number 目标槽位 (2 或 3)
---@return table|nil 新灵根 { type, quality, slot } 或 nil（无可选）
function M.RandomAwaken(roots, slot)
    -- 收集所有可觉醒的灵根
    local candidates = {}
    for _, typeId in ipairs(M.ALL_LIST) do
        if M.CanAwaken(roots, typeId) then
            candidates[#candidates + 1] = typeId
        end
    end
    if #candidates == 0 then return nil end
    local chosen = candidates[math.random(1, #candidates)]
    return { type = chosen, quality = M.RandomQuality(), slot = slot }
end

--- 旧数据迁移：rootBone 字符串 → spiritRoots 数组
---@param rootBone string 如 "上品灵根"
---@return table spiritRoots
function M.MigrateFromOld(rootBone)
    -- 解析品质
    local qualityId = "mid"  -- 默认中品
    local qualityMap = {
        ["废灵根"]  = "waste",
        ["下品灵根"] = "low",
        ["中品灵根"] = "mid",
        ["上品灵根"] = "upper",
        ["天灵根"]  = "heaven",
        ["变异灵根"] = "heaven",  -- 变异映射为天品
    }
    if rootBone and qualityMap[rootBone] then
        qualityId = qualityMap[rootBone]
    end
    -- 随机分配一个基础五行
    local typeId = M.BASE_LIST[math.random(1, #M.BASE_LIST)]
    return {
        { type = typeId, quality = qualityId, slot = 1 },
    }
end

return M
