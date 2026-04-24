-- ============================================================================
-- 《问道长生》武学功法数据配置（V2 功法拆分）
-- 设计来源: docs/design-v2-cultivation-combat.md §3.4
-- 职责：武学功法（战斗技能）的定义、属性体系、品阶、灵根匹配
-- ============================================================================

local M = {}

-- ============================================================================
-- 属性常量（与灵根体系对应）
-- ============================================================================
M.ELEMENT_METAL   = "metal"    -- 金
M.ELEMENT_WOOD    = "wood"     -- 木
M.ELEMENT_WATER   = "water"    -- 水
M.ELEMENT_FIRE    = "fire"     -- 火
M.ELEMENT_EARTH   = "earth"    -- 土
M.ELEMENT_THUNDER = "thunder"  -- 雷
M.ELEMENT_ICE     = "ice"      -- 冰
M.ELEMENT_WIND    = "wind"     -- 风
M.ELEMENT_YIN     = "yin"      -- 阴
M.ELEMENT_YANG    = "yang"     -- 阳

M.ELEMENT_NAMES = {
    metal = "金", wood = "木", water = "水", fire = "火", earth = "土",
    thunder = "雷", ice = "冰", wind = "风", yin = "阴", yang = "阳",
}

-- ============================================================================
-- 复合灵根 → 基础属性映射（用于灵根匹配计算）
-- ============================================================================
M.COMPOSITE_ELEMENTS = {
    thunder = { "fire", "earth" },
    ice     = { "water", "earth" },
    wind    = { "wood", "metal" },
    yin     = { "water", "wood" },
    yang    = { "fire", "metal" },
}

-- ============================================================================
-- 品阶常量 + 境界要求
-- ============================================================================
M.GRADE_FAN  = "fan"   -- 凡品
M.GRADE_LING = "ling"  -- 灵品
M.GRADE_XUAN = "xuan"  -- 玄品
M.GRADE_DI   = "di"    -- 地品
M.GRADE_TIAN = "tian"  -- 天品
M.GRADE_XIAN = "xian"  -- 仙品

M.GRADE_INFO = {
    fan  = { name = "凡品", realmReq = 1, order = 1 },
    ling = { name = "灵品", realmReq = 2, order = 2 },
    xuan = { name = "玄品", realmReq = 4, order = 3 },
    di   = { name = "地品", realmReq = 5, order = 4 },
    tian = { name = "天品", realmReq = 6, order = 5 },
    xian = { name = "仙品", realmReq = 7, order = 6 },
}

-- 武学品阶颜色（RGBA，供 UI 层使用）
M.GRADE_COLORS = {
    fan  = { 149, 149, 149, 255 },   -- 灰
    ling = { 102, 187, 106, 255 },   -- 绿
    xuan = {  41, 182, 246, 255 },   -- 蓝
    di   = { 171,  71, 188, 255 },   -- 紫
    tian = { 255, 167,  38, 255 },   -- 橙
    xian = { 255,  87,  34, 255 },   -- 红橙（仙品）
}

-- 最多同时装备数
M.MAX_EQUIPPED = 3

-- ============================================================================
-- 灵根匹配 → 伤害倍率
-- ============================================================================
-- matchLevel: 0=无匹配, 1=单灵根匹配, 2=双灵根匹配
M.DAMAGE_MULTIPLIER = { [0] = 1.0, [1] = 1.2, [2] = 1.4 }

-- 复合灵根自身匹配倍率（如雷灵根用雷系武学）
M.COMPOSITE_SELF_MULTIPLIER = 1.3

-- ============================================================================
-- 灵根匹配 → 效果增幅（按属性分别定义）
-- ============================================================================
M.EFFECT_AMPLIFY = {
    metal   = { [0] = {},              [1] = {},                       [2] = {} },  -- 纯伤害无附加
    wood    = { [0] = {},              [1] = { durationAdd = 1 },      [2] = { durationAdd = 2 } },
    water   = { [0] = {},              [1] = { shieldAdd = 0.20 },     [2] = { shieldAdd = 0.40 } },
    fire    = { [0] = {},              [1] = { dmgAdd = 0.25 },        [2] = { dmgAdd = 0.50 } },
    earth   = { [0] = {},              [1] = { immunityAdd = 0.05 },   [2] = { immunityAdd = 0.10 } },
    thunder = { [0] = {},              [1] = { chanceAdd = 0.10 },     [2] = { chanceAdd = 0.15 } },
    ice     = { [0] = {},              [1] = { slowAdd = 0.10 },       [2] = { slowAdd = 0.15 } },
    wind    = { [0] = {},              [1] = { dodgeAdd = 0.05 },      [2] = { dodgeAdd = 0.10 } },
    yin     = { [0] = {},              [1] = { stealAdd = 0.10 },      [2] = { stealAdd = 0.15 } },
    yang    = { [0] = {},              [1] = { atkReduceAdd = 0.05 },   [2] = { atkReduceAdd = 0.08 } },
}

-- ============================================================================
-- 武学功法列表（22 个，覆盖 10 属性 × 6 品阶）
-- ============================================================================
-- baseDamage: 攻击力倍率基础值
-- effect: 战斗附加效果（与 game_explore.lua 战斗系统对接）
-- trigger: 每N回合触发一次 / 条件触发
-- cooldown: 冷却回合数
-- ============================================================================
M.ARTS = {
    -- ======== 金系 (metal) — 纯物理高爆发 ========
    { id = "suishi_quan", name = "碎石拳", element = "metal", grade = "fan",
      maxLevel = 10, baseDamage = 0.40,
      effect = { type = "damage" },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "initial", desc = "以内力碎石，纯粹的物理爆发" },
    { id = "jingang_zhi", name = "金刚指", element = "metal", grade = "ling",
      maxLevel = 10, baseDamage = 0.55,
      effect = { type = "damage" },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "drop", desc = "指力如钢，一击破甲" },
    { id = "huitian_mudi", name = "毁天灭地", element = "metal", grade = "xian",
      maxLevel = 10, baseDamage = 1.20,
      effect = { type = "damage" },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "倾天之力，毁天灭地" },

    -- ======== 木系 (wood) — 缠绕/毒 ========
    { id = "changteng_shu", name = "缠藤术", element = "wood", grade = "fan",
      maxLevel = 10, baseDamage = 0.25,
      effect = { type = "entangle", speedReduce = 0.30, duration = 2 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "召唤藤蔓缠绕，降低敌方速度" },
    { id = "wanmu_senluo", name = "万木森罗", element = "wood", grade = "di",
      maxLevel = 10, baseDamage = 0.40,
      effect = { type = "poison", dmgPerRound = 0.03, duration = 3 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "万木齐发，毒素侵蚀敌方" },

    -- ======== 水系 (water) — 护盾 ========
    { id = "shuibo_shu", name = "水波术", element = "water", grade = "fan",
      maxLevel = 10, baseDamage = 0.20,
      effect = { type = "shield", shieldPct = 0.15 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "凝水为盾，抵挡伤害" },
    { id = "lingquan_jue", name = "灵泉诀", element = "water", grade = "ling",
      maxLevel = 10, baseDamage = 0.25,
      effect = { type = "shield", shieldPct = 0.20 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "引灵泉之力，结成坚固水盾" },

    -- ======== 火系 (fire) — 灼烧 DoT ========
    { id = "huoqiu_shu", name = "火球术", element = "fire", grade = "fan",
      maxLevel = 10, baseDamage = 0.35,
      effect = { type = "burn", dmgPerRound = 0.04, duration = 2 },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "initial", desc = "凝聚火球攻击，灼烧敌方" },
    { id = "lieyan_zhang", name = "烈焰掌", element = "fire", grade = "xuan",
      maxLevel = 10, baseDamage = 0.45,
      effect = { type = "burn", dmgPerRound = 0.04, duration = 2 },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "drop", desc = "烈焰加身，灼烧敌方" },
    { id = "jiutian_xuanhuo", name = "九天玄火", element = "fire", grade = "tian",
      maxLevel = 10, baseDamage = 0.80,
      effect = { type = "burn", dmgPerRound = 0.05, duration = 3 },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "drop", desc = "引九天玄火焚尽一切" },

    -- ======== 土系 (earth) — 防御增强 ========
    { id = "houtu_shu", name = "厚土术", element = "earth", grade = "fan",
      maxLevel = 10, baseDamage = 0.15,
      effect = { type = "defense_buff", defBonus = 0.20, immunity = 0.10, duration = 3 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "initial", desc = "厚土护体，大幅提升防御" },
    { id = "dadi_zhidun", name = "大地之盾", element = "earth", grade = "di",
      maxLevel = 10, baseDamage = 0.25,
      effect = { type = "defense_buff", defBonus = 0.30, immunity = 0.15, duration = 3 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "大地之力凝为坚盾，固若金汤" },

    -- ======== 雷系 (thunder) — 眩晕 ========
    { id = "leiji_shu", name = "雷击术", element = "thunder", grade = "ling",
      maxLevel = 10, baseDamage = 0.50,
      effect = { type = "stun", chance = 0.30, duration = 1 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "召唤雷电轰击，有几率眩晕敌方" },
    { id = "tianlei_zhan", name = "天雷斩", element = "thunder", grade = "di",
      maxLevel = 10, baseDamage = 0.70,
      effect = { type = "stun", chance = 0.35, duration = 1 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "引天雷之力斩击，极高眩晕概率" },

    -- ======== 冰系 (ice) — 冰冻减速 ========
    { id = "bingjian_shu", name = "冰箭术", element = "ice", grade = "ling",
      maxLevel = 10, baseDamage = 0.35,
      effect = { type = "freeze", atkReduce = 0.20, duration = 2 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "冰箭射出，冻结敌方攻速" },
    { id = "hanbing_ci", name = "寒冰刺", element = "ice", grade = "xuan",
      maxLevel = 10, baseDamage = 0.45,
      effect = { type = "freeze", atkReduce = 0.25, duration = 2 },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "drop", desc = "寒冰凝刺穿体，极寒冻敌" },

    -- ======== 风系 (wind) — 闪避提升 ========
    { id = "xuanfeng_zhan", name = "旋风斩", element = "wind", grade = "fan",
      maxLevel = 10, baseDamage = 0.30,
      effect = { type = "dodge_buff", dodgeBonus = 0.15, duration = 2 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "旋风护身，提升闪避" },
    { id = "yufeng_jue", name = "御风诀", element = "wind", grade = "ling",
      maxLevel = 10, baseDamage = 0.35,
      effect = { type = "dodge_buff", dodgeBonus = 0.20, duration = 2 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "御风而行，身法大增" },

    -- ======== 阴系 (yin) — 生命窃取 ========
    { id = "shihun_shu", name = "噬魂术", element = "yin", grade = "xuan",
      maxLevel = 10, baseDamage = 0.35,
      effect = { type = "lifesteal", stealPct = 0.20 },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "drop", desc = "噬取敌方精气，化为己用" },
    { id = "wanwu_guiyuan", name = "万物归元", element = "yin", grade = "tian",
      maxLevel = 10, baseDamage = 0.55,
      effect = { type = "lifesteal", stealPct = 0.25 },
      trigger = "every_3", cooldown = 3,
      unlockMethod = "drop", desc = "万物归于虚无，生机尽夺" },

    -- ======== 阳系 (yang) — 驱散增益 ========
    { id = "poxiao_zhan", name = "破晓斩", element = "yang", grade = "xuan",
      maxLevel = 10, baseDamage = 0.40,
      effect = { type = "dispel", atkReduce = 0.05 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "破晓之光驱散黑暗，移除敌方增益" },
    { id = "shengsi_lunhui", name = "生死轮回", element = "yang", grade = "xian",
      maxLevel = 10, baseDamage = 0.90,
      effect = { type = "dispel", atkReduce = 0.08 },
      trigger = "every_4", cooldown = 4,
      unlockMethod = "drop", desc = "生死轮转，一切增益化为乌有" },
}

-- ============================================================================
-- 武学等级表（10 级，升级消耗沿用 SKILL_LEVELS 体系）
-- ============================================================================
M.LEVELS = {
    { level = 1,  timeSec = 0,      wisdomReq = 0,   multiplier = 1.0 },
    { level = 2,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.10 },
    { level = 3,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.20 },
    { level = 4,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.30 },
    { level = 5,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.45 },
    { level = 6,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.60 },
    { level = 7,  timeSec = 28800,  wisdomReq = 90,  multiplier = 1.80 },
    { level = 8,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.00 },
    { level = 9,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.20 },
    { level = 10, timeSec = 86400,  wisdomReq = 120, multiplier = 2.50 },
}

-- ============================================================================
-- 旧功法 → 新武学迁移映射
-- ============================================================================
M.MIGRATION_MAP = {
    ["金刚诀"] = "houtu_shu",     -- 防御→土系防御
    ["御风术"] = "yufeng_jue",    -- 身法→风系闪避
    ["烈焰掌"] = "lieyan_zhang",  -- 攻击→火系灼烧
    ["冰心诀"] = "bingjian_shu",  -- 冰伤→冰系冰冻
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据 ID 获取武学定义
---@param id string
---@return table|nil
function M.GetArt(id)
    for _, a in ipairs(M.ARTS) do
        if a.id == id then return a end
    end
    return nil
end

--- 根据名称获取武学定义
---@param name string
---@return table|nil
function M.GetArtByName(name)
    for _, a in ipairs(M.ARTS) do
        if a.name == name then return a end
    end
    return nil
end

--- 获取武学等级配置
---@param level number
---@return table|nil
function M.GetLevel(level)
    if level >= 1 and level <= #M.LEVELS then
        return M.LEVELS[level]
    end
    return nil
end

--- 检查是否可以装备武学（仅检查品阶境界要求）
---@param tier number 当前境界阶数
---@param artId string 武学 ID
---@return boolean, string|nil
function M.CanEquip(tier, artId)
    local art = M.GetArt(artId)
    if not art then return false, "武学不存在" end
    local gradeInfo = M.GRADE_INFO[art.grade]
    if not gradeInfo then return false, "品阶配置错误" end
    if tier < gradeInfo.realmReq then
        return false, "需要达到" .. gradeInfo.name .. "对应境界才可装备"
    end
    return true
end

--- 获取灵根对武学属性的匹配等级
--- 返回 0(无匹配) / 1(单灵根匹配) / 2(双灵根匹配)
---@param spiritRoots table[] playerData.spiritRoots
---@param element string 武学属性
---@return number matchLevel
function M.GetSpiritRootMatchLevel(spiritRoots, element)
    if not spiritRoots or #spiritRoots == 0 then return 0 end

    local matchCount = 0
    for _, root in ipairs(spiritRoots) do
        local rootType = root.type
        if rootType == element then
            -- 基础灵根完全匹配
            matchCount = matchCount + 1
        else
            -- 检查复合灵根是否包含该属性
            local composites = M.COMPOSITE_ELEMENTS[rootType]
            if composites then
                for _, base in ipairs(composites) do
                    if base == element then
                        matchCount = matchCount + 1
                        break
                    end
                end
            end
        end
    end

    if matchCount >= 2 then return 2 end
    if matchCount >= 1 then return 1 end
    return 0
end

--- 获取灵根匹配的伤害倍率
---@param spiritRoots table[]
---@param element string
---@return number multiplier
function M.GetDamageMultiplier(spiritRoots, element)
    local matchLevel = M.GetSpiritRootMatchLevel(spiritRoots, element)
    return M.DAMAGE_MULTIPLIER[matchLevel] or 1.0
end

--- 获取灵根匹配的效果增幅数据
---@param element string
---@param matchLevel number
---@return table amplify 增幅字段表
function M.GetEffectAmplify(element, matchLevel)
    local amplifyTable = M.EFFECT_AMPLIFY[element]
    if not amplifyTable then return {} end
    return amplifyTable[matchLevel] or {}
end

--- 获取当前境界可用的所有武学（按品阶排序）
---@param tier number
---@return table[]
function M.GetAvailable(tier)
    local result = {}
    for _, art in ipairs(M.ARTS) do
        local gradeInfo = M.GRADE_INFO[art.grade]
        if gradeInfo and tier >= gradeInfo.realmReq then
            result[#result + 1] = art
        end
    end
    table.sort(result, function(a, b)
        local ga = M.GRADE_INFO[a.grade]
        local gb = M.GRADE_INFO[b.grade]
        return (ga and ga.order or 0) > (gb and gb.order or 0)
    end)
    return result
end

--- 获取指定属性在指定境界可用的武学列表
---@param element string
---@param tier number
---@return table[]
function M.GetAvailableByElement(element, tier)
    local result = {}
    for _, art in ipairs(M.ARTS) do
        if art.element == element then
            local gradeInfo = M.GRADE_INFO[art.grade]
            if gradeInfo and tier >= gradeInfo.realmReq then
                result[#result + 1] = art
            end
        end
    end
    return result
end

--- 根据旧功法名称获取迁移后的武学 ID
---@param oldName string
---@return string|nil artId
function M.MigrateOldSkill(oldName)
    return M.MIGRATION_MAP[oldName]
end

--- 计算武学在指定等级的实际基础伤害倍率
---@param artId string
---@param level number
---@return number
function M.CalcBaseDamage(artId, level)
    local art = M.GetArt(artId)
    if not art then return 0 end
    local lvConf = M.GetLevel(level or 1)
    local multiplier = lvConf and lvConf.multiplier or 1.0
    return art.baseDamage * multiplier
end

--- 获取新角色的初始武学列表
--- 根据种族给予不同初始武学：人族/灵族→碎石拳+火球术，魔族/妖族→碎石拳+厚土术
---@param race string
---@return table[] owned { { id, level } }
---@return table equipped { id|nil, id|nil, nil }
function M.GetInitialMartialArts(race)
    local owned = {
        { id = "suishi_quan", level = 1 },
        { id = "huoqiu_shu",  level = 1 },
        { id = "houtu_shu",   level = 1 },
    }
    -- 所有种族都拥有 3 个凡品武学，默认装备前两个
    local equipped = { "suishi_quan", "huoqiu_shu", nil }
    return owned, equipped
end

return M
