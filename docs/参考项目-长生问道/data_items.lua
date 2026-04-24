-- ============================================================================
-- 《问道长生》物品体系数据配置
-- 数据来源: docs/roadmap.md 阶段四
-- ============================================================================

local M = {}

-- ============================================================================
-- 4.1 品质等级 & 颜色（9品阶体系）
-- ============================================================================
M.QUALITY_ORDER = { "fanqi", "lingbao", "xtlingbao", "huangqi", "diqi", "xianqi", "xtxianqi", "shenqi", "xtshenqi" }

M.QUALITY = {
    fanqi     = { label = "凡器",     color = { 149, 149, 149, 255 }, hex = "#959595", weight = 50, maxLevel = 100, ascMaxLevel = 150, extraStats = 1 },
    lingbao   = { label = "灵宝",     color = { 174, 213, 129, 255 }, hex = "#AED581", weight = 30, maxLevel = 120, ascMaxLevel = 190, extraStats = 1 },
    xtlingbao = { label = "先天灵宝", color = { 41,  182, 246, 255 }, hex = "#29B6F6", weight = 15, maxLevel = 150, ascMaxLevel = 240, extraStats = 2 },
    huangqi   = { label = "皇器",     color = { 171, 71,  188, 255 }, hex = "#AB47BC", weight = 8,  maxLevel = 180, ascMaxLevel = 280, extraStats = 2 },
    diqi      = { label = "帝器",     color = { 234, 128, 252, 255 }, hex = "#EA80FC", weight = 4,  maxLevel = 220, ascMaxLevel = 350, extraStats = 3 },
    xianqi    = { label = "仙器",     color = { 255, 112, 67,  255 }, hex = "#FF7043", weight = 1,  maxLevel = 260, ascMaxLevel = 400, extraStats = 3 },
    xtxianqi  = { label = "先天仙器", color = { 255, 87,  34,  255 }, hex = "#FF5722", weight = 0,  maxLevel = 320, ascMaxLevel = 450, extraStats = 4 },
    shenqi    = { label = "神器",     color = { 255, 215, 0,   255 }, hex = "#FFD700", weight = 0,  maxLevel = 400, ascMaxLevel = 500, extraStats = 4 },
    xtshenqi  = { label = "先天神器", color = { 255, 68,  68,  255 }, hex = "#FF4444", weight = 0,  maxLevel = 500, ascMaxLevel = 500, extraStats = 5 },
}

-- 品质序号索引（用于比较品质高低）
M.QUALITY_RANK = {}
for i, key in ipairs(M.QUALITY_ORDER) do
    M.QUALITY_RANK[key] = i
end

-- 中文名 → key 映射
M.QUALITY_NAME_MAP = {}
for k, v in pairs(M.QUALITY) do
    M.QUALITY_NAME_MAP[v.label] = k
end

-- 旧品质key → 新品质key 兼容映射（数据迁移用）
M.OLD_QUALITY_MAP = {
    common   = "fanqi",
    uncommon = "lingbao",
    rare     = "xtlingbao",
    epic     = "huangqi",
    legend   = "diqi",
    mythic   = "xianqi",
}

-- ============================================================================
-- 4.1.5 丹药专属品阶（与法宝9品阶体系完全独立）
-- ============================================================================
M.PILL_QUALITY_ORDER = { "xia", "zhong", "shang", "ji", "xian" }

M.PILL_QUALITY = {
    xia   = { label = "下品", color = { 149, 149, 149, 255 } },
    zhong = { label = "中品", color = { 174, 213, 129, 255 } },
    shang = { label = "上品", color = {  41, 182, 246, 255 } },
    ji    = { label = "极品", color = { 171,  71, 188, 255 } },
    xian  = { label = "仙品", color = { 255, 215,   0, 255 } },
}

-- 丹药品阶基础炼制时间（秒），丹炉品阶可在此基础上缩减
M.PILL_BASE_TIME = {
    xia   =   900,   -- 下品：15分钟
    zhong =  1800,   -- 中品：30分钟
    shang =  3600,   -- 上品：1小时
    ji    =  7200,   -- 极品：2小时
    xian  = 14400,   -- 仙品：4小时
}

--- 获取丹药品阶颜色（返回 {r,g,b,a}）
---@param qualityKey string
---@return table
function M.GetPillQualityColor(qualityKey)
    local q = M.PILL_QUALITY[qualityKey]
    return q and q.color or { 180, 180, 180, 255 }
end

--- 计算实际炼制时间（秒），考虑丹炉品阶加成
---@param pillQuality string 丹药品阶 key
---@param furnaceQuality string|nil 丹炉品阶 key（nil=无丹炉）
---@return number seconds
function M.CalcAlchemyTime(pillQuality, furnaceQuality)
    local base = M.PILL_BASE_TIME[pillQuality] or 900
    -- 丹炉品阶折扣：每升一品减少 8%，上限 40%
    local furnaceRank = 0
    if furnaceQuality then
        for i, k in ipairs(M.PILL_QUALITY_ORDER) do
            if k == furnaceQuality then furnaceRank = i - 1; break end
        end
    end
    local discount = math.min(0.40, furnaceRank * 0.08)
    return math.floor(base * (1 - discount))
end

-- ============================================================================
-- 4.2 新材料定义
-- ============================================================================
M.ENHANCE_MATERIALS = {
    { id = "lingchen",       name = "灵尘",     quality = "fanqi",    price = 15,   currency = "灵石", source = "装备分解" },
    { id = "tianyuan_jingpo", name = "天元精魄", quality = "xianqi",   price = 500,  currency = "灵石", source = "仙器+分解/副本" },
    { id = "lingshou_jingxue", name = "灵兽精血", quality = "xianqi",  price = 500,  currency = "灵石", source = "灵宠分解/副本" },
    { id = "xianshi",        name = "仙石",     quality = "xianqi",   price = 0,    currency = "",    source = "仙器+分解" },
}

-- ============================================================================
-- 4.3 强化消耗表（500级，分段式生成）
-- ============================================================================
-- 分段定义: {maxLevel, pctPerLevel, lingshi, lingchen, tianyuan, successRate}
local ENHANCE_SEGMENTS = {
    { maxLevel = 10,  pctPerLevel = 3.0, lingshi = 50,    lingchen = 1,  tianyuan = 0,  rate = 100 },
    { maxLevel = 30,  pctPerLevel = 2.5, lingshi = 100,   lingchen = 2,  tianyuan = 0,  rate = 95 },
    { maxLevel = 50,  pctPerLevel = 2.0, lingshi = 200,   lingchen = 3,  tianyuan = 0,  rate = 90 },
    { maxLevel = 80,  pctPerLevel = 1.8, lingshi = 400,   lingchen = 5,  tianyuan = 1,  rate = 80 },
    { maxLevel = 100, pctPerLevel = 1.5, lingshi = 800,   lingchen = 8,  tianyuan = 1,  rate = 70 },
    { maxLevel = 150, pctPerLevel = 1.2, lingshi = 1500,  lingchen = 12, tianyuan = 2,  rate = 60 },
    { maxLevel = 200, pctPerLevel = 1.0, lingshi = 3000,  lingchen = 18, tianyuan = 3,  rate = 50 },
    { maxLevel = 280, pctPerLevel = 0.8, lingshi = 6000,  lingchen = 25, tianyuan = 5,  rate = 40 },
    { maxLevel = 350, pctPerLevel = 0.6, lingshi = 12000, lingchen = 35, tianyuan = 8,  rate = 30 },
    { maxLevel = 400, pctPerLevel = 0.5, lingshi = 25000, lingchen = 50, tianyuan = 12, rate = 20 },
    { maxLevel = 500, pctPerLevel = 0.3, lingshi = 50000, lingchen = 80, tianyuan = 20, rate = 15 },
}

--- 获取指定等级的强化信息
---@param level number 当前强化等级 (1~500)
---@return table|nil { level, pct, lingshi, lingchen, tianyuan, rate }
function M.GetEnhanceInfo(level)
    if level < 1 or level > 500 then return nil end
    for _, seg in ipairs(ENHANCE_SEGMENTS) do
        if level <= seg.maxLevel then
            return {
                level    = level,
                pct      = seg.pctPerLevel,
                lingshi  = seg.lingshi,
                lingchen = seg.lingchen,
                tianyuan = seg.tianyuan,
                rate     = seg.rate,
            }
        end
    end
    return nil
end

--- 计算累计强化百分比加成
---@param level number
---@return number 累计百分比
function M.GetTotalEnhancePct(level)
    if level <= 0 then return 0 end
    local total = 0
    local prevMax = 0
    for _, seg in ipairs(ENHANCE_SEGMENTS) do
        local segStart = prevMax + 1
        local segEnd = math.min(level, seg.maxLevel)
        if segStart <= segEnd then
            total = total + (segEnd - segStart + 1) * seg.pctPerLevel
        end
        prevMax = seg.maxLevel
        if level <= seg.maxLevel then break end
    end
    return total
end

--- 判断指定品质的强化是否需要天元精魄
---@param quality string 品质key
---@return boolean
function M.NeedsTianyuan(quality)
    local rank = M.QUALITY_RANK[quality] or 0
    return rank >= M.QUALITY_RANK["xianqi"]
end

-- ============================================================================
-- 4.4 升阶系统
-- ============================================================================
-- base 值用于计算升阶消耗: 灵尘=base×倍率, 灵石=base×100×倍率
M.ASCENSION_BASE = {
    fanqi     = 5,
    lingbao   = 10,
    xtlingbao = 20,
    huangqi   = 35,
    diqi      = 60,
    xianqi    = 100,
    xtxianqi  = 180,
    shenqi    = 300,
    xtshenqi  = 0,  -- 先天神器不可升阶
}

M.ASCENSION_STAGES = {
    { stage = 1, name = "初阶升华", extraLevels = 50, lingchenMul = 1, lingshiMul = 100, rate = 80 },
    { stage = 2, name = "中阶升华", extraLevels = 50, lingchenMul = 3, lingshiMul = 300, rate = 50 },
    { stage = 3, name = "高阶升华", extraLevels = 50, lingchenMul = 8, lingshiMul = 800, rate = 30 },
}

--- 获取升阶消耗
---@param quality string 品质key
---@param stage number 升阶阶段 (1~3)
---@return table|nil { stage, name, extraLevels, lingchen, lingshi, rate }
function M.GetAscensionInfo(quality, stage)
    local base = M.ASCENSION_BASE[quality]
    if not base or base <= 0 then return nil end
    local stageInfo = M.ASCENSION_STAGES[stage]
    if not stageInfo then return nil end
    return {
        stage       = stageInfo.stage,
        name        = stageInfo.name,
        extraLevels = stageInfo.extraLevels,
        lingchen    = base * stageInfo.lingchenMul,
        lingshi     = base * stageInfo.lingshiMul,
        rate        = stageInfo.rate,
    }
end

--- 获取品质的最终等级上限（含升阶）
---@param quality string
---@param ascStage number 已完成的升阶阶段数 (0~3)
---@return number
function M.GetMaxLevel(quality, ascStage)
    local q = M.QUALITY[quality]
    if not q then return 100 end
    ascStage = ascStage or 0
    local extraLevels = 0
    for i = 1, math.min(ascStage, 3) do
        local si = M.ASCENSION_STAGES[i]
        if si then
            extraLevels = extraLevels + si.extraLevels
        end
    end
    return math.min(q.maxLevel + extraLevels, q.ascMaxLevel)
end

-- ============================================================================
-- 4.5 灵宠升级消耗表（分段式）
-- ============================================================================
-- 每段: {maxLevel, expBase, expEnd, lingshi, jingxue}
local PET_LEVEL_SEGMENTS = {
    { maxLevel = 10,  expBase = 100,     expEnd = 550,     lingshi = 30,    jingxue = 1 },
    { maxLevel = 30,  expBase = 600,     expEnd = 2000,    lingshi = 60,    jingxue = 2 },
    { maxLevel = 50,  expBase = 2200,    expEnd = 5000,    lingshi = 120,   jingxue = 3 },
    { maxLevel = 80,  expBase = 5500,    expEnd = 12000,   lingshi = 250,   jingxue = 5 },
    { maxLevel = 100, expBase = 13000,   expEnd = 25000,   lingshi = 500,   jingxue = 8 },
    { maxLevel = 150, expBase = 27000,   expEnd = 60000,   lingshi = 1000,  jingxue = 12 },
    { maxLevel = 200, expBase = 65000,   expEnd = 130000,  lingshi = 2000,  jingxue = 18 },
    { maxLevel = 280, expBase = 140000,  expEnd = 300000,  lingshi = 4000,  jingxue = 28 },
    { maxLevel = 350, expBase = 320000,  expEnd = 600000,  lingshi = 8000,  jingxue = 40 },
    { maxLevel = 400, expBase = 650000,  expEnd = 1000000, lingshi = 15000, jingxue = 60 },
    { maxLevel = 500, expBase = 1100000, expEnd = 2500000, lingshi = 30000, jingxue = 100 },
}

--- 获取灵宠指定等级的升级信息
---@param level number 当前等级 (1~500)
---@return table|nil { level, expNeeded, lingshi, jingxue }
function M.GetPetLevelInfo(level)
    if level < 1 or level > 500 then return nil end
    local prevMax = 0
    for _, seg in ipairs(PET_LEVEL_SEGMENTS) do
        if level <= seg.maxLevel then
            -- 线性插值经验需求
            local segLen = seg.maxLevel - prevMax
            local posInSeg = level - prevMax
            local t = (posInSeg - 1) / math.max(segLen - 1, 1)
            local expNeeded = math.floor(seg.expBase + (seg.expEnd - seg.expBase) * t)
            return {
                level     = level,
                expNeeded = expNeeded,
                lingshi   = seg.lingshi,
                jingxue   = seg.jingxue,
            }
        end
        prevMax = seg.maxLevel
    end
    return nil
end

-- ============================================================================
-- 4.6 分解产出表
-- ============================================================================
M.DECOMPOSE_YIELD = {
    fanqi     = { lingchen = 2,   xianshi = 0, tianyuan = 0, jingxue = 1 },
    lingbao   = { lingchen = 5,   xianshi = 0, tianyuan = 0, jingxue = 3 },
    xtlingbao = { lingchen = 12,  xianshi = 0, tianyuan = 0, jingxue = 5 },
    huangqi   = { lingchen = 25,  xianshi = 0, tianyuan = 0, jingxue = 8 },
    diqi      = { lingchen = 50,  xianshi = 0, tianyuan = 0, jingxue = 12 },
    xianqi    = { lingchen = 80,  xianshi = 3, tianyuan = 2, jingxue = 15 },
    xtxianqi  = { lingchen = 150, xianshi = 8, tianyuan = 5, jingxue = 25 },
    -- 神器/先天神器不可分解（不掉落，不可能拥有来分解）
}

-- ============================================================================
-- 4.7 掉落相关配置
-- ============================================================================

--- 可掉落品质列表（不含神器、先天神器）
M.DROPPABLE_QUALITIES = { "fanqi", "lingbao", "xtlingbao", "huangqi", "diqi", "xianqi", "xtxianqi" }

--- 掉落率配置（按区域等级 tier 区分）
--- baseRate: 战斗胜利后掉落装备的基础概率(%)
M.EQUIP_DROP_RATE = {
    { tierMin = 1, tierMax = 2,  baseRate = 12 },
    { tierMin = 3, tierMax = 4,  baseRate = 15 },
    { tierMin = 5, tierMax = 6,  baseRate = 18 },
    { tierMin = 7, tierMax = 8,  baseRate = 20 },
    { tierMin = 9, tierMax = 10, baseRate = 22 },
}

--- 品质概率配置（百分比，总和=100）
--- 不同区域档位下品质分布不同
M.EQUIP_QUALITY_RATES = {
    low = {   -- 区域1-2 (云雾山/天阙遗迹)
        fanqi = 55, lingbao = 30, xtlingbao = 12, huangqi = 3, diqi = 0, xianqi = 0, xtxianqi = 0,
    },
    mid = {   -- 区域3-4 (东海海滨/夫山遗迹)
        fanqi = 35, lingbao = 30, xtlingbao = 20, huangqi = 10, diqi = 5, xianqi = 0, xtxianqi = 0,
    },
    high = {  -- 区域5-6 (玄冰深渊/九天雷域)
        fanqi = 20, lingbao = 25, xtlingbao = 25, huangqi = 15, diqi = 10, xianqi = 5, xtxianqi = 0,
    },
    ultra = { -- 区域7-8 (万古战场/仙魔裂隙)
        fanqi = 10, lingbao = 18, xtlingbao = 25, huangqi = 20, diqi = 15, xianqi = 10, xtxianqi = 2,
    },
    apex = {  -- 区域9-10 (混天墟/太渊秘境)
        fanqi = 5, lingbao = 12, xtlingbao = 20, huangqi = 22, diqi = 20, xianqi = 15, xtxianqi = 6,
    },
}

--- 根据区域编号获取品质概率档位
---@param areaIndex number 区域序号 (1-10)
---@return table
function M.GetQualityRatesByArea(areaIndex)
    if areaIndex <= 2 then return M.EQUIP_QUALITY_RATES.low end
    if areaIndex <= 4 then return M.EQUIP_QUALITY_RATES.mid end
    if areaIndex <= 6 then return M.EQUIP_QUALITY_RATES.high end
    if areaIndex <= 8 then return M.EQUIP_QUALITY_RATES.ultra end
    return M.EQUIP_QUALITY_RATES.apex
end

--- 兼容旧接口：根据 tier 获取品质概率档位
---@param tier number
---@return table
function M.GetQualityRates(tier)
    if tier <= 3 then return M.EQUIP_QUALITY_RATES.low end
    if tier <= 5 then return M.EQUIP_QUALITY_RATES.mid end
    if tier <= 7 then return M.EQUIP_QUALITY_RATES.high end
    if tier <= 9 then return M.EQUIP_QUALITY_RATES.ultra end
    return M.EQUIP_QUALITY_RATES.apex
end

--- 根据 tier 获取掉落率(%)
---@param tier number
---@return number
function M.GetEquipDropRate(tier)
    for _, cfg in ipairs(M.EQUIP_DROP_RATE) do
        if tier >= cfg.tierMin and tier <= cfg.tierMax then
            return cfg.baseRate
        end
    end
    return 10
end

--- 副属性池（随机从中抽取）
M.EXTRA_STAT_POOL = { "attack", "defense", "hp", "crit", "speed", "dodge", "hit", "cultSpeed", "elemDmg" }

--- 副属性中文名映射
M.STAT_LABEL = {
    attack   = "攻击",
    defense  = "防御",
    hp       = "气血",
    crit     = "暴击",
    speed    = "速度",
    dodge    = "闪避",
    hit      = "命中",
    cultSpeed = "修炼速度",
    elemDmg  = "灵根属性伤害",
}

--- 副属性是否为百分比类型
M.STAT_IS_PERCENT = {
    crit     = true,
    dodge    = true,
    hit      = true,
    cultSpeed = true,
    elemDmg  = true,
}

--- 副属性数值范围（按品阶缩放系数, 基础范围见 STAT_BASE_RANGE）
M.STAT_BASE_RANGE = {
    attack   = { 5, 80 },
    defense  = { 3, 50 },
    hp       = { 20, 500 },
    crit     = { 1, 8 },
    speed    = { 2, 30 },
    dodge    = { 1, 5 },
    hit      = { 1, 5 },
    cultSpeed = { 1, 10 },
    elemDmg  = { 2, 12 },
}

--- 品阶对应的副属性缩放因子（越高品阶数值越大）
M.STAT_QUALITY_SCALE = {
    fanqi     = 0.15,
    lingbao   = 0.25,
    xtlingbao = 0.35,
    huangqi   = 0.45,
    diqi      = 0.60,
    xianqi    = 0.75,
    xtxianqi  = 0.85,
    shenqi    = 0.95,
    xtshenqi  = 1.00,
}

--- 计算指定品阶副属性的数值范围
---@param statType string 副属性类型
---@param quality string 品阶key
---@return number min, number max
function M.GetSubStatRange(statType, quality)
    local base = M.STAT_BASE_RANGE[statType]
    if not base then return 1, 1 end
    local scale = M.STAT_QUALITY_SCALE[quality] or 0.15
    local minVal = math.max(1, math.floor(base[1] + (base[2] - base[1]) * scale * 0.5))
    local maxVal = math.max(minVal, math.floor(base[1] + (base[2] - base[1]) * scale))
    return minVal, maxVal
end

--- 品质 → 附加属性条数 + 数值范围
M.EQUIP_STAT_RANGES = {
    fanqi     = { extraStats = 1, statRange = { 2,  5 } },
    lingbao   = { extraStats = 1, statRange = { 4,  10 } },
    xtlingbao = { extraStats = 2, statRange = { 8,  18 } },
    huangqi   = { extraStats = 2, statRange = { 12, 25 } },
    diqi      = { extraStats = 3, statRange = { 18, 35 } },
    xianqi    = { extraStats = 3, statRange = { 25, 50 } },
    xtxianqi  = { extraStats = 4, statRange = { 35, 70 } },
    shenqi    = { extraStats = 4, statRange = { 50, 100 } },
    xtshenqi  = { extraStats = 5, statRange = { 70, 150 } },
}

-- ============================================================================
-- 5.1 通用丹药 (不限次数)
-- ============================================================================
M.PILLS_COMMON = {
    { id = "peiyuan",     name = "培元丹",     quality = "xia",   effect = "修为+200",          materials = { ["灵草"] = 1, ["矿石"] = 2 },         time = 900,  rate = 80 },
    { id = "huiqi",       name = "回气丹",     quality = "xia",   effect = "灵力恢复100",        materials = { ["灵草"] = 1, ["灵泉水"] = 1 },       time = 900,  rate = 80 },
    { id = "ningshen",    name = "凝神丹",     quality = "zhong", effect = "神识+20",            materials = { ["灵草"] = 2, ["兽骨"] = 1 },         time = 1800, rate = 60 },
    { id = "tongmai",     name = "通脉丹",     quality = "shang", effect = "修炼速度+20%(1小时)", materials = { ["灵草"] = 3, ["灵泉水"] = 1 },       time = 3600, rate = 40 },
    { id = "peiyuan_up",  name = "上品培元丹", quality = "zhong", effect = "修为+1000",          materials = { ["灵草"] = 3, ["矿石"] = 5 },         time = 1800, rate = 50 },
    { id = "peiyuan_top", name = "极品培元丹", quality = "ji",    effect = "修为+5000",          materials = { ["灵草"] = 5, ["天材地宝"] = 1 },     time = 7200, rate = 30 },
}

-- ============================================================================
-- 5.2 限制丹药 (每境界限次)
-- ============================================================================
M.PILLS_LIMITED = {
    { id = "hongyun",   name = "鸿运丹", quality = "shang", effect = "气运+1级",       perRealm = 1, materials = { ["灵草"] = 5, ["天材地宝"] = 1 }, rate = 25, time = 3600 },
    { id = "qiangshen", name = "强身丹", quality = "zhong", effect = "气血+50(永久)",   perRealm = 5, materials = { ["灵草"] = 2, ["兽骨"] = 2 },    rate = 50, time = 1800 },
    { id = "linggong",  name = "灵攻丹", quality = "zhong", effect = "攻击+10(永久)",   perRealm = 5, materials = { ["灵草"] = 2, ["矿石"] = 3 },    rate = 50, time = 1800 },
    { id = "guyuan",    name = "固元丹", quality = "zhong", effect = "防御+8(永久)",    perRealm = 5, materials = { ["兽骨"] = 3, ["矿石"] = 2 },    rate = 50, time = 1800 },
    { id = "jifeng",    name = "疾风丹", quality = "shang", effect = "速度+3(永久)",    perRealm = 3, materials = { ["灵草"] = 3, ["灵泉水"] = 2 },  rate = 35, time = 3600 },
    { id = "xisui",     name = "洗髓丹", quality = "shang", effect = "悟性+5(永久)",    perRealm = 3, materials = { ["灵草"] = 3, ["天材地宝"] = 1 }, rate = 30, time = 3600 },
}

-- ============================================================================
-- 5.3 突破辅助丹药（可选，提升成功率/保护道心）
-- ============================================================================
M.PILLS_BREAKTHROUGH = {
    { id = "zhuji",   name = "筑基丹", quality = "shang", effect = "渡劫成功率+20%",  perBreak = 1, materials = { ["灵草"] = 5, ["天材地宝"] = 1 }, rate = 20, time = 3600 },
    { id = "qingxin", name = "清心丹", quality = "shang", effect = "渡劫失败不降道心", perBreak = 1, materials = { ["灵草"] = 5, ["灵泉水"] = 3 },  rate = 25, time = 3600 },
    { id = "pojie",   name = "破劫丹", quality = "ji",    effect = "渡劫成功率+30%",  perBreak = 1, materials = { ["天材地宝"] = 3 },              rate = 10, time = 7200 },
}

-- ============================================================================
-- 5.4 必需突破丹（大境界突破的前置消耗，无论成败均消耗）
-- 来源：炼丹（坊市丹方解锁）
-- ============================================================================
-- 品阶说明：zhong=中品 / shang=上品 / ji=极品 / xian=仙品
M.PILLS_REQUIRED_BREAK = {
    {
        id = "zhuji_req",   name = "筑基丹",     targetTier = 3,
        quality = "zhong",
        effect  = "聚灵境→筑基境突破必需，×2枚",
        desc    = "采集灵草九九八十一株，以灵泉淬炼，凝为丹胚",
        materials = { ["灵草"] = 5, ["天材地宝"] = 1 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.zhong or 1800,
    },
    {
        id = "jindan_req",  name = "金丹凝结丹", targetTier = 4,
        quality = "shang",
        effect  = "筑基境→金丹境突破必需，×2枚",
        desc    = "凝萃天地精华，引元气入丹，令金丹自然圆满",
        materials = { ["天材地宝"] = 3, ["灵泉水"] = 2 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.shang or 3600,
    },
    {
        id = "ninying_req", name = "凝婴丹",     targetTier = 5,
        quality = "ji",
        effect  = "金丹境→元婴境突破必需，×3枚",
        desc    = "以三花聚顶之法提炼，令金丹化形，元婴孕育而生",
        materials = { ["天材地宝"] = 5, ["灵兽精血"] = 1 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.ji or 7200,
    },
    {
        id = "huashen_req", name = "化神丹",     targetTier = 6,
        quality = "ji",
        effect  = "元婴境→化神境突破必需，×3枚",
        desc    = "元婴圆满后以此丹引导神魂蜕变，化形于虚空之间",
        materials = { ["天材地宝"] = 5, ["天元精魄"] = 1 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.ji or 7200,
    },
    {
        id = "fanxu_req",   name = "返虚丹",     targetTier = 7,
        quality = "xian",
        effect  = "化神境→返虚境突破必需，×5枚",
        desc    = "炼化大道虚空之气，令神识归虚，再度凝实于虚无间",
        materials = { ["天材地宝"] = 8, ["天元精魄"] = 2 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.xian or 14400,
    },
    {
        id = "hedao_req",   name = "合道丹",     targetTier = 8,
        quality = "xian",
        effect  = "返虚境→合道境突破必需，×5枚",
        desc    = "以天地大道精华提炼，修士服下后道心与天地同频共振",
        materials = { ["天材地宝"] = 10, ["天元精魄"] = 3, ["灵兽精血"] = 2 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.xian or 14400,
    },
    {
        id = "dacheng_req", name = "大乘丹",     targetTier = 9,
        quality = "xian",
        effect  = "合道境→大乘境突破必需，×7枚",
        desc    = "汇聚日月精华，融合五行之气，令修士大道圆满无缺",
        materials = { ["天材地宝"] = 15, ["天元精魄"] = 5, ["灵兽精血"] = 3 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.xian or 14400,
    },
    {
        id = "shenyou_req", name = "神游丹",     targetTier = 10,
        quality = "xian",
        effect  = "大乘境→渡劫境突破必需，×7枚",
        desc    = "神魂出窍游历三千大道，淬炼完毕方可面对最终天劫",
        materials = { ["天材地宝"] = 20, ["天元精魄"] = 8, ["灵兽精血"] = 5 },
        craftTime = M.PILL_BASE_TIME and M.PILL_BASE_TIME.xian or 14400,
    },
}

--- 根据 targetTier 查找必需突破丹
---@param targetTier number 目标大境界（3~10）
---@return table|nil
function M.GetRequiredBreakPill(targetTier)
    for _, pill in ipairs(M.PILLS_REQUIRED_BREAK) do
        if pill.targetTier == targetTier then return pill end
    end
    return nil
end

--- 根据名称查找必需突破丹
---@param name string
---@return table|nil
function M.FindRequiredBreakPillByName(name)
    for _, pill in ipairs(M.PILLS_REQUIRED_BREAK) do
        if pill.name == name then return pill end
    end
    return nil
end

-- ============================================================================
-- 5.5 炼丹材料
-- ============================================================================
M.MATERIALS = {
    { id = "lingcao",      name = "灵草",     quality = "fanqi",     price = 20,  currency = "灵石", source = "探索采集" },
    { id = "kuangshi",     name = "矿石",     quality = "fanqi",     price = 15,  currency = "灵石", source = "探索采矿" },
    { id = "shougu",       name = "兽骨",     quality = "fanqi",     price = 30,  currency = "灵石", source = "击杀灵兽" },
    { id = "lingquanshui", name = "灵泉水",   quality = "lingbao",   price = 80,  currency = "灵石", source = "稀有采集点" },
    { id = "tiancaidibao", name = "天材地宝", quality = "xtlingbao", price = 50,  currency = "仙石", source = "Boss掉落/秘境" },
    -- 新增强化材料
    { id = "lingchen",       name = "灵尘",     quality = "fanqi",   price = 15,  currency = "灵石", source = "装备分解" },
    { id = "tianyuan_jingpo", name = "天元精魄", quality = "xianqi",  price = 500, currency = "灵石", source = "仙器+分解/副本" },
    { id = "lingshou_jingxue", name = "灵兽精血", quality = "xianqi", price = 500, currency = "灵石", source = "灵宠分解/副本" },
}

-- ============================================================================
-- 5.6 仙界专属资源（不可炼制，仙界玩法产出）
-- ============================================================================
--[[
  7 种核心仙界资源，对应 IMMORTAL_REALMS 的 breakItems 消耗字段。
  获取途径：仙界秘境、游历奖励、仙界 Boss 掉落、特殊赛季事件。
  质量说明：使用自定义 quality 标识仙界等级，用于 UI 颜色区分。
]]
M.IMMORTAL_RESOURCES = {
    {
        id      = "xianldan",
        name    = "仙灵丹",
        quality = "xian",        -- 仙品（紫色）
        type    = "consumable",
        tier    = 11,            -- 从飞升 T11 开始使用
        desc    = "仙界基础修炼材料，散仙与真仙境修炼及突破的核心消耗，坊市可流通",
        source  = "仙界秘境、游历奖励、坊市购买",
        usage   = "T11 散仙突破需×99；T12 真仙突破需×360",
    },
    {
        id      = "xianyuandan",
        name    = "仙元丹",
        quality = "xian",
        type    = "consumable",
        tier    = 13,
        desc    = "仙界中级突破材料，真仙晋升玄仙、金仙、太乙金仙的必需品",
        source  = "仙界高级秘境、顶级 Boss 掉落",
        usage   = "T13 玄仙需×99；T14 金仙需×299；T15 太乙金仙需×499",
    },
    {
        id      = "daluoxiandan",
        name    = "大罗仙丹",
        quality = "xian",
        type    = "consumable",
        tier    = 16,
        desc    = "大罗层级专属丹药，突破大罗金仙与混元金仙的核心消耗，极为稀有",
        source  = "大罗秘境、混元副本 Boss 掉落",
        usage   = "T16 大罗金仙需×99；T17 混元金仙需×299",
    },
    {
        id      = "zhansizhu",
        name    = "斩尸珠",
        quality = "xian",
        type    = "special",
        tier    = 18,
        desc    = "准圣境斩尸的唯一材料，每斩一尸消耗一颗，全程共消耗3颗",
        source  = "斩尸秘境、准圣境特殊事件",
        usage   = "T18 一尸准圣×1；T19 二尸准圣×1；T20 三尸准圣×1",
    },
    {
        id      = "yashenxuanjing",
        name    = "亚圣玄晶",
        quality = "xian",
        type    = "special",
        tier    = 21,
        desc    = "半步圣人的结晶，凝聚亚圣之力，每赛季极少产出",
        source  = "亚圣境特殊副本、赛季限定活动",
        usage   = "T21 亚圣×1；T22 圣人×3",
    },
    {
        id      = "hongmengziqi",
        name    = "鸿蒙紫气",
        quality = "xian",
        type    = "resource",
        tier    = 15,            -- 太乙金仙解锁
        desc    = "混沌洪荒的先天之气，三千大道之始，证就圣人的核心材料（洪荒经典：鸿蒙初分，紫气万道）",
        source  = "太乙金仙境气运事件、仙界特殊剧情奖励",
        usage   = "T22 圣人突破需×36；T24 准天道突破需×100",
    },
    {
        id      = "hunyuandaoguo",
        name    = "混元道果",
        quality = "xian",
        type    = "special",
        tier    = 22,            -- 圣人境解锁
        desc    = "混元层级道果，凝聚三千大道之精华，道祖传承的专属载体",
        source  = "混元秘境、圣人境特殊感悟",
        usage   = "T23 道祖突破需×1",
    },
}

--- 根据 id 查找仙界资源
---@param id string
---@return table|nil
function M.GetImmortalResource(id)
    for _, r in ipairs(M.IMMORTAL_RESOURCES) do
        if r.id == id then return r end
    end
    return nil
end

--- 根据名称查找仙界资源
---@param name string
---@return table|nil
function M.FindImmortalResourceByName(name)
    for _, r in ipairs(M.IMMORTAL_RESOURCES) do
        if r.name == name then return r end
    end
    return nil
end

-- ============================================================================
-- 6.1 物品分类枚举
-- ============================================================================
M.ITEM_CATEGORIES = {
    { key = "fabao",    label = "法宝",  subTabs = { "头戴", "身穿", "手持", "饰品", "鞋子" } },
    { key = "material", label = "材料",  subTabs = nil },
    { key = "item",     label = "物品",  subTabs = { "宝箱", "其他" } },
}

--- 根据 category key 获取分类定义
---@param key string
---@return table|nil
function M.GetCategory(key)
    for _, cat in ipairs(M.ITEM_CATEGORIES) do
        if cat.key == key then return cat end
    end
    return nil
end

--- 根据物品推断 category + subType
---@param itemName string
---@return string category, string|nil subType
function M.InferCategory(itemName)
    if M.FindPillByName(itemName) then
        return "item", "丹药"
    end
    for _, mat in ipairs(M.MATERIALS) do
        if mat.name == itemName then return "material", nil end
    end
    -- 装备检查（按掉落池）
    for _, slotKey in ipairs(M.EQUIP_SLOT_KEYS) do
        local pool = M.EQUIP_DROP_POOL[slotKey]
        if pool then
            for _, eq in ipairs(pool) do
                if eq.name == itemName then
                    local slotDef = M.GetSlotByKey(slotKey)
                    return "fabao", slotDef and slotDef.label or "手持"
                end
            end
        end
    end
    return "item", "其他"
end

-- ============================================================================
-- 6.2 背包容量配置
-- ============================================================================
M.BAG_EXPAND = {
    initialCapacity = 50,
    perExpand       = 10,
    maxCapacity     = 120,
    costPerSlot     = 20,
}

-- ============================================================================
-- 7.1 装备槽位（5个部位）
-- ============================================================================
M.EQUIP_SLOTS = {
    { slot = "head",      label = "头戴", mainStat = "defense" },
    { slot = "body",      label = "身穿", mainStat = "defense" },
    { slot = "weapon",    label = "手持", mainStat = "attack" },
    { slot = "accessory", label = "饰品", mainStat = "crit" },
    { slot = "shoes",     label = "鞋子", mainStat = "speed" },
}

--- 根据 slot key 获取槽位定义
---@param slotKey string
---@return table|nil
function M.GetSlotByKey(slotKey)
    for _, s in ipairs(M.EQUIP_SLOTS) do
        if s.slot == slotKey then return s end
    end
    return nil
end

--- 所有槽位key列表
M.EQUIP_SLOT_KEYS = { "weapon", "head", "body", "accessory", "shoes" }

-- ============================================================================
-- 7.2 装备掉落池（按槽位分组，品质覆盖9品阶）
-- ============================================================================
M.EQUIP_DROP_POOL = {
    weapon = {
        { name = "铁剑",       quality = "fanqi",     baseAtk = 8 },
        { name = "青铜长刀",   quality = "fanqi",     baseAtk = 10 },
        { name = "灵木法杖",   quality = "lingbao",   baseAtk = 15 },
        { name = "寒铁双刃",   quality = "lingbao",   baseAtk = 18 },
        { name = "赤焰枪",     quality = "xtlingbao", baseAtk = 28 },
        { name = "紫霄神剑",   quality = "xtlingbao", baseAtk = 35 },
        { name = "天罡破魔刀", quality = "huangqi",   baseAtk = 50 },
        { name = "帝灵战戟",   quality = "diqi",      baseAtk = 75 },
        { name = "轩辕剑",     quality = "xianqi",    baseAtk = 110 },
        { name = "太虚灭世刃", quality = "xtxianqi",  baseAtk = 160 },
        { name = "鸿蒙天帝剑", quality = "shenqi",    baseAtk = 230 },
        { name = "盘古斧",     quality = "xtshenqi",  baseAtk = 350 },
    },
    head = {
        { name = "布冠",       quality = "fanqi",     baseDef = 4 },
        { name = "铜发冠",     quality = "fanqi",     baseDef = 6 },
        { name = "灵玉冠",     quality = "lingbao",   baseDef = 10 },
        { name = "虎头盔",     quality = "xtlingbao", baseDef = 18 },
        { name = "凤翎冠",     quality = "huangqi",   baseDef = 30 },
        { name = "帝辉天冠",   quality = "diqi",      baseDef = 45 },
        { name = "混元金冠",   quality = "xianqi",    baseDef = 65 },
        { name = "太清道冠",   quality = "xtxianqi",  baseDef = 95 },
        { name = "九天神冠",   quality = "shenqi",    baseDef = 140 },
        { name = "鸿蒙道冠",   quality = "xtshenqi",  baseDef = 210 },
    },
    body = {
        { name = "粗布衣",     quality = "fanqi",     baseDef = 6 },
        { name = "皮甲",       quality = "fanqi",     baseDef = 8 },
        { name = "灵纹道袍",   quality = "lingbao",   baseDef = 14 },
        { name = "玄铁锁甲",   quality = "lingbao",   baseDef = 18 },
        { name = "天蚕宝衣",   quality = "xtlingbao", baseDef = 28 },
        { name = "星辰法袍",   quality = "huangqi",   baseDef = 45 },
        { name = "帝霸战甲",   quality = "diqi",      baseDef = 65 },
        { name = "混元仙衣",   quality = "xianqi",    baseDef = 90 },
        { name = "太虚圣袍",   quality = "xtxianqi",  baseDef = 130 },
        { name = "九天神甲",   quality = "shenqi",    baseDef = 190 },
        { name = "太极阴阳袍", quality = "xtshenqi",  baseDef = 280 },
    },
    accessory = {
        { name = "木珠串",     quality = "fanqi",     baseCrit = 2 },
        { name = "灵石坠",     quality = "fanqi",     baseCrit = 3 },
        { name = "碧玉佩",     quality = "lingbao",   baseCrit = 5 },
        { name = "龙纹玉佩",   quality = "xtlingbao", baseCrit = 9 },
        { name = "天机灵珠",   quality = "huangqi",   baseCrit = 15 },
        { name = "帝灵宝珠",   quality = "diqi",      baseCrit = 22 },
        { name = "太虚法环",   quality = "xianqi",    baseCrit = 32 },
        { name = "先天灵珠",   quality = "xtxianqi",  baseCrit = 48 },
        { name = "九天灵环",   quality = "shenqi",    baseCrit = 70 },
        { name = "混沌灵珠",   quality = "xtshenqi",  baseCrit = 100 },
    },
    shoes = {
        { name = "草鞋",       quality = "fanqi",     baseSpd = 2 },
        { name = "皮靴",       quality = "fanqi",     baseSpd = 3 },
        { name = "灵风履",     quality = "lingbao",   baseSpd = 5 },
        { name = "踏云靴",     quality = "xtlingbao", baseSpd = 9 },
        { name = "凌波仙履",   quality = "huangqi",   baseSpd = 15 },
        { name = "帝步风云靴", quality = "diqi",      baseSpd = 22 },
        { name = "御风神靴",   quality = "xianqi",    baseSpd = 32 },
        { name = "凌天仙履",   quality = "xtxianqi",  baseSpd = 48 },
        { name = "九天追日靴", quality = "shenqi",    baseSpd = 70 },
        { name = "缩地千里靴", quality = "xtshenqi",  baseSpd = 100 },
    },
}

-- ============================================================================
-- 7.3 装备售价配置（按品质）
-- ============================================================================
M.EQUIP_SELL_PRICE = {
    fanqi     = 10,
    lingbao   = 30,
    xtlingbao = 80,
    huangqi   = 200,
    diqi      = 500,
    xianqi    = 1500,
    xtxianqi  = 5000,
    shenqi    = 15000,
    xtshenqi  = 50000,
}

-- ============================================================================
-- 7.4 法宝定义（坊市固定法宝，保留兼容）
-- ============================================================================
M.ARTIFACTS = {
    { id = "biyu_zan",    name = "碧玉灵簪", quality = "lingbao",   slot = "accessory", effect = "灵力上限+50",      price = nil, currency = nil },
    { id = "zhenmo_ling", name = "镇魔铃",   quality = "xtlingbao", slot = "weapon",    effect = "攻击+15, 暴击+3%", price = nil, currency = nil },
    { id = "xuantie_dun", name = "玄铁盾",   quality = "fanqi",     slot = "body",      effect = "防御+25",          price = 300, currency = "灵石" },
    { id = "zijin_ling",  name = "紫金铃",   quality = "xtlingbao", slot = "weapon",    effect = "攻击+25, 暴击+2%", price = 500, currency = "灵石" },
    { id = "xianling_shan", name = "仙灵扇", quality = "huangqi",   slot = "weapon",    effect = "攻击+35, 速度+40", price = 80,  currency = "仙石" },
}

-- ============================================================================
-- 8 称号体系
-- ============================================================================
M.TITLE_RARITIES = {
    { level = 1, label = "普通", color = { 149, 149, 149, 255 }, hex = "#959595", bonus = 0 },
    { level = 2, label = "优秀", color = { 174, 213, 129, 255 }, hex = "#AED581", bonus = 1 },
    { level = 3, label = "精良", color = { 41,  182, 246, 255 }, hex = "#29B6F6", bonus = 3 },
    { level = 4, label = "史诗", color = { 234, 128, 252, 255 }, hex = "#EA80FC", bonus = 5 },
    { level = 5, label = "传说", color = { 255, 112, 67,  255 }, hex = "#FF7043", bonus = 8 },
    { level = 6, label = "神话", color = { 244, 81,  30,  255 }, hex = "#F4511E", bonus = 12 },
}

-- ============================================================================
-- 12.1 坊市商品定价
-- ============================================================================
M.MARKET_GOODS = {
    -- 丹药
    { name = "培元丹",   category = "丹药", price = 50,   currency = "灵石", stock = 10 },
    { name = "洗髓丹",   category = "丹药", price = 200,  currency = "灵石", stock = 5 },
    { name = "筑基丹",   category = "丹药", price = 30,   currency = "仙石", stock = 1 },
    { name = "凝神丹",   category = "丹药", price = 120,  currency = "灵石", stock = 3 },
    { name = "强身丹",   category = "丹药", price = 100,  currency = "灵石", stock = 5 },
    { name = "灵攻丹",   category = "丹药", price = 150,  currency = "灵石", stock = 5 },
    { name = "鸿运丹",   category = "丹药", price = 50,   currency = "仙石", stock = 1 },
    -- 法宝
    { name = "紫金铃",   category = "法宝", price = 500,  currency = "灵石", stock = 2 },
    { name = "玄铁盾",   category = "法宝", price = 300,  currency = "灵石", stock = 3 },
    { name = "仙灵扇",   category = "法宝", price = 80,   currency = "仙石", stock = 1 },
    -- 功法
    { name = "冰心诀",   category = "功法", price = 800,  currency = "灵石", stock = 1 },
    { name = "烈焰掌",   category = "功法", price = 400,  currency = "灵石", stock = 2 },
    -- 材料
    { name = "灵草",     category = "材料", price = 20,   currency = "灵石", stock = 99 },
    { name = "兽骨",     category = "材料", price = 30,   currency = "灵石", stock = 50 },
    { name = "灵泉水",   category = "材料", price = 80,   currency = "灵石", stock = 10 },
    { name = "天材地宝", category = "材料", price = 50,   currency = "仙石", stock = 2 },
    -- 新材料
    { name = "灵尘",     category = "材料", price = 15,   currency = "灵石", stock = 99 },
    { name = "天元精魄", category = "材料", price = 500,  currency = "灵石", stock = 5 },
    { name = "灵兽精血", category = "材料", price = 500,  currency = "灵石", stock = 5 },
    -- 礼包
    { name = "灵尘礼包",   category = "礼包", price = 120,  currency = "灵石", stock = 99 },
    { name = "灵尘大礼包", category = "礼包", price = 550,  currency = "灵石", stock = 20 },
    -- 兑换（仙石→灵石）
    { name = "灵石小包",   category = "兑换", price = 1,   currency = "仙石", stock = 99 },
    { name = "灵石中包",   category = "兑换", price = 10,  currency = "仙石", stock = 99 },
    { name = "灵石大包",   category = "兑换", price = 50,  currency = "仙石", stock = 10 },
}

-- 12.2 寄售坊配置（V2 双货币）
M.TRADING_POST = {
    maxListings = 5,
    -- 费率：灵石 5%，仙石 10%
    feeRates = {
        lingStone   = 0.05,
        spiritStone = 0.10,
    },
    feeRate = 0.05,  -- 旧字段兼容（灵石默认）
    -- 仙石交易限制
    spiritStoneTrade = {
        requireMonthCard = true,   -- 需开通月卡
        dailyLimit       = 5,      -- 每日上限5笔（至尊月卡10笔 → 由月卡特权覆盖）
    },
}

--- 物品类型交易规则（寄售坊）
--- type: "pill"=丹药, "material"=材料, "artifact"=法宝, "cultSkill"=修炼功法,
---       "martialArt"=武学功法, "washPill"=洗灵丹
M.ITEM_TRADE_RULES = {
    -- 丹药/材料：灵石交易
    pill     = { tradable = true,  currency = "lingStone" },
    material = { tradable = true,  currency = "lingStone" },
    -- 洗灵丹：不可交易
    washPill = { tradable = false, currency = nil },
    -- 修炼功法：仙石交易
    cultSkill = { tradable = true, currency = "spiritStone" },
    -- 法宝：按品阶，见 TRADE_RULES
    -- 武学功法：按品阶
}

--- 武学品阶交易规则
M.MARTIAL_TRADE_RULES = {
    fan  = { tradable = true,  currency = "lingStone" },
    ling = { tradable = true,  currency = "lingStone" },
    xuan = { tradable = true,  currency = "lingStone" },
    di   = { tradable = true,  currency = "spiritStone" },
    tian = { tradable = true,  currency = "spiritStone" },
    xian = { tradable = false, currency = nil },  -- 仙品武学不可交易
}

--- 判断物品是否可上架寄售 + 使用货币
---@param itemType string "pill"|"material"|"artifact"|"cultSkill"|"martialArt"|"washPill"
---@param qualityOrGrade string|nil 法宝品阶key 或 武学品阶key
---@return boolean tradable, string|nil currencyKey, string|nil reason
function M.CheckTradable(itemType, qualityOrGrade)
    -- 洗灵丹
    if itemType == "washPill" then
        return false, nil, "洗灵丹不可交易"
    end
    -- 法宝
    if itemType == "artifact" then
        local rule = M.TRADE_RULES[qualityOrGrade]
        if not rule then return false, nil, "未知品阶" end
        if not rule.tradable then return false, nil, "该品阶法宝不可交易" end
        local currKey = rule.currency == "仙石" and "spiritStone" or "lingStone"
        return true, currKey, nil
    end
    -- 武学功法
    if itemType == "martialArt" then
        local rule = M.MARTIAL_TRADE_RULES[qualityOrGrade]
        if not rule then return false, nil, "未知品阶" end
        if not rule.tradable then return false, nil, "仙品武学不可交易" end
        return true, rule.currency, nil
    end
    -- 通用类型
    local rule = M.ITEM_TRADE_RULES[itemType]
    if not rule then return false, nil, "该类型物品不可交易" end
    if not rule.tradable then return false, nil, "该物品不可交易" end
    return true, rule.currency, nil
end

--- 获取寄售手续费率
---@param currencyKey string "lingStone"|"spiritStone"
---@return number
function M.GetTradeFeeRate(currencyKey)
    return M.TRADING_POST.feeRates[currencyKey] or 0.05
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 获取品质颜色(RGBA)，兼容中文label、英文key和旧key
---@param quality string 品质标识
---@return table {r,g,b,a}
function M.GetQualityColor(quality)
    -- 先尝试直接作为新 key 查
    if M.QUALITY[quality] then
        return M.QUALITY[quality].color
    end
    -- 尝试旧 key 映射
    local newKey = M.OLD_QUALITY_MAP[quality]
    if newKey and M.QUALITY[newKey] then
        return M.QUALITY[newKey].color
    end
    -- 尝试中文 label
    local key = M.QUALITY_NAME_MAP[quality]
    if key and M.QUALITY[key] then
        return M.QUALITY[key].color
    end
    return M.QUALITY.fanqi.color
end

--- 获取品质hex颜色
---@param quality string
---@return string
function M.GetQualityHex(quality)
    if M.QUALITY[quality] then
        return M.QUALITY[quality].hex
    end
    local newKey = M.OLD_QUALITY_MAP[quality]
    if newKey and M.QUALITY[newKey] then
        return M.QUALITY[newKey].hex
    end
    local key = M.QUALITY_NAME_MAP[quality]
    if key and M.QUALITY[key] then
        return M.QUALITY[key].hex
    end
    return M.QUALITY.fanqi.hex
end

--- 获取品质中文显示名，兼容中文label、英文key和旧key
---@param quality string
---@return string
function M.GetQualityLabel(quality)
    if M.QUALITY[quality] then
        return M.QUALITY[quality].label
    end
    local newKey = M.OLD_QUALITY_MAP[quality]
    if newKey and M.QUALITY[newKey] then
        return M.QUALITY[newKey].label
    end
    if M.QUALITY_NAME_MAP[quality] then
        return quality
    end
    return "凡器"
end

--- 获取品质key（兼容旧key和中文label）
---@param qualityInput string
---@return string
function M.GetQualityKey(qualityInput)
    -- 已是新 key
    if M.QUALITY[qualityInput] then return qualityInput end
    -- 旧 key 映射
    local newKey = M.OLD_QUALITY_MAP[qualityInput]
    if newKey then return newKey end
    -- 中文 label
    local key = M.QUALITY_NAME_MAP[qualityInput]
    if key then return key end
    return "fanqi"
end

--- 迁移旧品质key到新品质key
---@param oldQuality string
---@return string 新品质key
function M.MigrateQuality(oldQuality)
    if M.QUALITY[oldQuality] then return oldQuality end
    return M.OLD_QUALITY_MAP[oldQuality] or "fanqi"
end

--- 根据id查找丹药(所有类别)
---@param id string
---@return table|nil
function M.FindPill(id)
    for _, p in ipairs(M.PILLS_COMMON) do
        if p.id == id then return p end
    end
    for _, p in ipairs(M.PILLS_LIMITED) do
        if p.id == id then return p end
    end
    for _, p in ipairs(M.PILLS_BREAKTHROUGH) do
        if p.id == id then return p end
    end
    for _, p in ipairs(M.PILLS_REQUIRED_BREAK) do
        if p.id == id then return p end
    end
    return nil
end

--- 根据名称查找丹药
---@param name string
---@return table|nil
function M.FindPillByName(name)
    for _, p in ipairs(M.PILLS_COMMON) do
        if p.name == name then return p end
    end
    for _, p in ipairs(M.PILLS_LIMITED) do
        if p.name == name then return p end
    end
    for _, p in ipairs(M.PILLS_BREAKTHROUGH) do
        if p.name == name then return p end
    end
    for _, p in ipairs(M.PILLS_REQUIRED_BREAK) do
        if p.name == name then return p end
    end
    return nil
end

-- ============================================================================
-- 炼丹等级系统
-- ============================================================================
M.ALCHEMY_LEVELS = {
    { level = 1, name = "炼丹学徒",   expReq = 0,    rateBonus = 0 },
    { level = 2, name = "炼丹师",     expReq = 100,  rateBonus = 3 },
    { level = 3, name = "高级炼丹师", expReq = 300,  rateBonus = 6 },
    { level = 4, name = "圣丹师",     expReq = 800,  rateBonus = 10 },
    { level = 5, name = "仙丹师",     expReq = 2000, rateBonus = 15 },
}

--- 根据经验值获取当前炼丹等级信息
---@param exp number
---@return table { level, name, expReq, rateBonus, nextExp }
function M.GetAlchemyLevel(exp)
    exp = exp or 0
    local cur = M.ALCHEMY_LEVELS[1]
    for i = #M.ALCHEMY_LEVELS, 1, -1 do
        if exp >= M.ALCHEMY_LEVELS[i].expReq then
            cur = M.ALCHEMY_LEVELS[i]
            break
        end
    end
    local nextLv = M.ALCHEMY_LEVELS[cur.level + 1]
    return {
        level     = cur.level,
        name      = cur.name,
        rateBonus = cur.rateBonus,
        expReq    = cur.expReq,
        nextExp   = nextLv and nextLv.expReq or nil,
    }
end

-- ============================================================================
-- 9. 法宝副属性洗炼配置
-- ============================================================================

--- 洗炼消耗
M.REROLL_COST = {
    lingchen = 100,     -- 灵尘 × 100
    lingshi  = 500,     -- 灵石 × 500
}

--- 洗炼锁定费用（每条锁定的副属性消耗仙石数）
M.REROLL_LOCK_COST = 200

--- 洗炼最低品阶要求（仙器及以上）
M.REROLL_MIN_QUALITY = "xianqi"

--- 洗炼最低境界要求（元婴 = tier 5）
M.REROLL_MIN_REALM = 5

--- 副属性条数配置
--- 凡器~先天灵宝=1, 皇器~帝器=2, 仙器~先天仙器=3, 神器~先天神器=4
M.SUB_STAT_COUNTS = {
    fanqi     = 1,
    lingbao   = 1,
    xtlingbao = 1,
    huangqi   = 2,
    diqi      = 2,
    xianqi    = 3,
    xtxianqi  = 3,
    shenqi    = 4,
    xtshenqi  = 4,
}

--- 判断指定品阶法宝是否可洗炼
---@param quality string 品阶key
---@return boolean
function M.CanRerollQuality(quality)
    local rank = M.QUALITY_RANK[quality] or 0
    local minRank = M.QUALITY_RANK[M.REROLL_MIN_QUALITY] or 6
    return rank >= minRank
end

-- ============================================================================
-- 10. 法宝交易规则
-- ============================================================================

--- 交易规则：品阶 → 是否可交易 + 使用货币
M.TRADE_RULES = {
    fanqi     = { tradable = true,  currency = "灵石" },
    lingbao   = { tradable = true,  currency = "灵石" },
    xtlingbao = { tradable = true,  currency = "灵石" },
    huangqi   = { tradable = true,  currency = "灵石" },
    diqi      = { tradable = true,  currency = "灵石" },
    xianqi    = { tradable = true,  currency = "仙石" },
    xtxianqi  = { tradable = true,  currency = "仙石" },
    shenqi    = { tradable = false, currency = nil },
    xtshenqi  = { tradable = false, currency = nil },
}

--- 判断指定品阶法宝是否可交易
---@param quality string 品阶key
---@return boolean tradable, string|nil currency
function M.IsTradable(quality)
    local rule = M.TRADE_RULES[quality]
    if not rule then return false, nil end
    return rule.tradable, rule.currency
end

--- 主属性数值范围（按品阶，掉落时随机生成）
M.MAIN_STAT_RANGE = {
    fanqi     = { attack = { 5, 10 },   defense = { 3, 6 },   crit = { 1, 2 },   speed = { 1, 2 } },
    lingbao   = { attack = { 10, 18 },  defense = { 6, 12 },  crit = { 2, 4 },   speed = { 2, 4 } },
    xtlingbao = { attack = { 18, 30 },  defense = { 12, 20 }, crit = { 4, 6 },   speed = { 4, 6 } },
    huangqi   = { attack = { 30, 50 },  defense = { 20, 35 }, crit = { 6, 10 },  speed = { 6, 10 } },
    diqi      = { attack = { 50, 80 },  defense = { 35, 55 }, crit = { 10, 15 }, speed = { 10, 15 } },
    xianqi    = { attack = { 80, 120 }, defense = { 55, 80 }, crit = { 15, 22 }, speed = { 15, 22 } },
    xtxianqi  = { attack = { 120, 180 }, defense = { 80, 120 }, crit = { 22, 32 }, speed = { 22, 32 } },
    shenqi    = { attack = { 180, 260 }, defense = { 120, 180 }, crit = { 32, 48 }, speed = { 32, 48 } },
    xtshenqi  = { attack = { 260, 380 }, defense = { 180, 260 }, crit = { 48, 70 }, speed = { 48, 70 } },
}

--- 获取主属性数值范围
---@param quality string 品阶key
---@param statType string 主属性类型 (attack/defense/crit/speed)
---@return number min, number max
function M.GetMainStatRange(quality, statType)
    local qRange = M.MAIN_STAT_RANGE[quality]
    if not qRange then return 5, 10 end
    local sRange = qRange[statType]
    if not sRange then return 5, 10 end
    return sRange[1], sRange[2]
end

return M
