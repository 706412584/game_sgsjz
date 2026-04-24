-- ============================================================================
-- 《问道长生》灵宠数据配置（血脉进化 + 境界压制体系）
-- 替代旧 data_world.PETS 9品阶系统，统一为 5 阶血脉
-- ============================================================================

local M = {}

-- ============================================================================
-- 1. 五阶血脉体系
-- ============================================================================
-- 旧 9品阶 → 新 5血脉 映射:
--   fanqi/lingbao        → fanshou  (凡兽)
--   xtlingbao/huangqi    → lingqin  (灵禽)
--   diqi/xianqi          → zhenshou (珍兽)
--   xtxianqi/shenqi      → shenshou (神兽, 可化形)
--   xtshenqi             → hongmeng (鸿蒙, 可化形)
-- ============================================================================

M.BLOODLINE_ORDER = { "fanshou", "lingqin", "zhenshou", "shenshou", "hongmeng" }

M.BLOODLINE = {
    fanshou  = {
        label    = "凡兽",
        color    = { 180, 180, 180, 255 },
        hex      = "#B4B4B4",
        powerMul = 1.0,      -- 战力系数
        maxLevel = 100,       -- 血脉等级上限（不含觉醒）
        canTransform = false, -- 能否化形
        awakenStages = 2,     -- 最大觉醒阶段数
        talentSlots  = 1,     -- 捕获时随机天赋数
    },
    lingqin  = {
        label    = "灵禽",
        color    = { 41, 182, 246, 255 },
        hex      = "#29B6F6",
        powerMul = 1.5,
        maxLevel = 150,
        canTransform = false,
        awakenStages = 3,
        talentSlots  = 2,
    },
    zhenshou = {
        label    = "珍兽",
        color    = { 171, 71, 188, 255 },
        hex      = "#AB47BC",
        powerMul = 2.5,
        maxLevel = 250,
        canTransform = false,
        awakenStages = 4,
        talentSlots  = 2,
    },
    shenshou = {
        label    = "神兽",
        color    = { 255, 145, 0, 255 },
        hex      = "#FF9100",
        powerMul = 4.0,
        maxLevel = 400,
        canTransform = true,
        awakenStages = 5,
        talentSlots  = 3,
    },
    hongmeng = {
        label    = "鸿蒙",
        color    = { 255, 68, 68, 255 },
        hex      = "#FF4444",
        powerMul = 7.0,
        maxLevel = 500,
        canTransform = true,
        awakenStages = 6,
        talentSlots  = 3,
    },
}

-- 元素中文映射
M.ELEMENT_LABEL = {
    metal   = "金",
    wood    = "木",
    water   = "水",
    fire    = "火",
    earth   = "土",
    thunder = "雷",
    ice     = "冰",
    wind    = "风",
    yin     = "阴",
    yang    = "阳",
}

-- 血脉序号索引（比较高低用）
M.BLOODLINE_RANK = {}
for i, key in ipairs(M.BLOODLINE_ORDER) do
    M.BLOODLINE_RANK[key] = i
end

-- 中文名 → key 映射
M.BLOODLINE_NAME_MAP = {}
for k, v in pairs(M.BLOODLINE) do
    M.BLOODLINE_NAME_MAP[v.label] = k
end

-- ============================================================================
-- 2. 旧品质 → 新血脉 迁移映射
-- ============================================================================
M.QUALITY_TO_BLOODLINE = {
    fanqi     = "fanshou",
    lingbao   = "fanshou",
    xtlingbao = "lingqin",
    huangqi   = "lingqin",
    diqi      = "zhenshou",
    xianqi    = "zhenshou",
    xtxianqi  = "shenshou",
    shenqi    = "shenshou",
    xtshenqi  = "hongmeng",
}

-- ============================================================================
-- 3. 境界压制表
-- ============================================================================
-- 玩家境界(tier) → 灵宠等级上限
-- 灵宠实际最大等级 = min(血脉上限, 境界上限, 觉醒追加)
-- ============================================================================
M.REALM_PET_CAP = {
    [1]  = 20,   -- 炼气
    [2]  = 30,   -- 聚灵
    [3]  = 50,   -- 筑基
    [4]  = 80,   -- 金丹
    [5]  = 120,  -- 元婴
    [6]  = 160,  -- 化神
    [7]  = 220,  -- 返虚
    [8]  = 300,  -- 合道
    [9]  = 400,  -- 大乘
    [10] = 500,  -- 渡劫
}

--- 获取玩家境界对应的灵宠等级上限
---@param tier number 境界阶数(1~10)
---@return number
function M.GetRealmCap(tier)
    return M.REALM_PET_CAP[tier] or 20
end

-- ============================================================================
-- 4. 觉醒阶段（替代旧升阶 ASCENSION_STAGES）
-- ============================================================================
-- 每次觉醒：提升等级上限、解锁天赋槽位、增加属性
-- stage:         觉醒阶段编号（1~6）
-- name:          阶段名称
-- extraLevels:   追加等级上限
-- statBonus:     属性百分比加成
-- unlockTalent:  是否解锁一个额外天赋槽位
-- materials:     材料消耗（灵兽精血基数，按血脉倍率缩放）
-- lingshi:       灵石消耗基数
-- rate:          成功率(%)
-- ============================================================================
M.AWAKEN_STAGES = {
    { stage = 1, name = "初觉",   extraLevels = 30,  statBonus = 0.05, unlockTalent = false,
      jingxue = 10,  lingshi = 5000,    rate = 90 },
    { stage = 2, name = "灵觉",   extraLevels = 40,  statBonus = 0.08, unlockTalent = true,
      jingxue = 25,  lingshi = 15000,   rate = 75 },
    { stage = 3, name = "魂觉",   extraLevels = 50,  statBonus = 0.12, unlockTalent = false,
      jingxue = 50,  lingshi = 40000,   rate = 60 },
    { stage = 4, name = "道觉",   extraLevels = 60,  statBonus = 0.15, unlockTalent = true,
      jingxue = 100, lingshi = 100000,  rate = 45 },
    { stage = 5, name = "天觉",   extraLevels = 70,  statBonus = 0.20, unlockTalent = false,
      jingxue = 200, lingshi = 250000,  rate = 30 },
    { stage = 6, name = "圆满觉", extraLevels = 80,  statBonus = 0.25, unlockTalent = true,
      jingxue = 500, lingshi = 600000,  rate = 15 },
}

--- 获取觉醒阶段信息
---@param bloodline string 血脉key
---@param stage number 目标觉醒阶段(1~6)
---@return table|nil { stage, name, extraLevels, statBonus, unlockTalent, jingxue, lingshi, rate }
function M.GetAwakenInfo(bloodline, stage)
    local bl = M.BLOODLINE[bloodline]
    if not bl then return nil end
    if stage < 1 or stage > bl.awakenStages then return nil end
    local info = M.AWAKEN_STAGES[stage]
    if not info then return nil end
    -- 材料按血脉等级缩放
    local rank = M.BLOODLINE_RANK[bloodline] or 1
    local costMul = rank  -- 凡兽x1, 灵禽x2, 珍兽x3, 神兽x4, 鸿蒙x5
    return {
        stage       = info.stage,
        name        = info.name,
        extraLevels = info.extraLevels,
        statBonus   = info.statBonus,
        unlockTalent = info.unlockTalent,
        jingxue     = info.jingxue * costMul,
        lingshi     = info.lingshi * costMul,
        rate        = info.rate,
    }
end

-- ============================================================================
-- 5. 灵宠等级上限计算
-- ============================================================================

--- 获取灵宠最终等级上限
--- = min(血脉基础上限 + 觉醒追加, 境界压制上限)
---@param bloodline string 血脉key
---@param awakenStage number 已完成的觉醒阶段数(0~6)
---@param ownerTier number 主人境界阶数(1~10)
---@return number maxLevel, number bloodlineCap, number realmCap
function M.GetMaxLevel(bloodline, awakenStage, ownerTier)
    local bl = M.BLOODLINE[bloodline]
    if not bl then return 20, 20, 20 end

    -- 血脉上限 = 基础 + 觉醒追加
    local bloodlineCap = bl.maxLevel
    awakenStage = awakenStage or 0
    for i = 1, math.min(awakenStage, #M.AWAKEN_STAGES) do
        bloodlineCap = bloodlineCap + M.AWAKEN_STAGES[i].extraLevels
    end

    -- 境界压制上限
    local realmCap = M.GetRealmCap(ownerTier or 1)

    -- 实际上限取较小值
    local maxLevel = math.min(bloodlineCap, realmCap)
    return maxLevel, bloodlineCap, realmCap
end

-- ============================================================================
-- 6. 灵根天赋池
-- ============================================================================
-- 捕获时随机分配 talentSlots 个天赋，不重复
-- 觉醒 unlockTalent=true 时额外获得 1 个天赋
-- ============================================================================
M.TALENTS = {
    -- 战斗类
    { id = "iron_hide",    name = "厚皮",     type = "combat",
      desc = "受到伤害降低8%",               effect = { defPct = 0.08 } },
    { id = "swift_claw",   name = "疾爪",     type = "combat",
      desc = "攻击速度提升15%",              effect = { spdPct = 0.15 } },
    { id = "fire_blood",   name = "火血",     type = "combat",
      desc = "攻击力提升10%",                effect = { atkPct = 0.10 } },
    { id = "spirit_shield", name = "灵盾",    type = "combat",
      desc = "战斗开始时获得15%最大生命护盾",  effect = { initShieldPct = 0.15 } },
    { id = "berserk",      name = "狂暴",     type = "combat",
      desc = "生命低于30%时攻击力翻倍",       effect = { berserkThreshold = 0.30, berserkMul = 2.0 } },
    { id = "life_drain",   name = "汲命",     type = "combat",
      desc = "攻击时回复造成伤害的5%生命",     effect = { lifeStealPct = 0.05 } },
    { id = "crit_eye",     name = "锐目",     type = "combat",
      desc = "暴击率提升10%",                effect = { critPct = 0.10 } },
    { id = "thorns",       name = "荆棘",     type = "combat",
      desc = "受击时反弹12%伤害",            effect = { reflectPct = 0.12 } },

    -- 成长类
    { id = "fast_grow",    name = "速成",     type = "growth",
      desc = "升级经验需求降低15%",           effect = { expReducePct = 0.15 } },
    { id = "talent_luck",  name = "福缘",     type = "growth",
      desc = "觉醒成功率提升10%",            effect = { awakenRateBonus = 0.10 } },
    { id = "deep_bond",    name = "深契",     type = "growth",
      desc = "羁绊值获取速度提升20%",         effect = { bondGainPct = 0.20 } },
    { id = "spirit_body",  name = "灵体",     type = "growth",
      desc = "灵根共鸣加成额外提升25%",       effect = { resonanceBonus = 0.25 } },

    -- 探索类
    { id = "treasure_nose", name = "寻宝",    type = "explore",
      desc = "历练时额外掉落率提升10%",       effect = { dropRateBonus = 0.10 } },
    { id = "scout_eye",    name = "侦查",     type = "explore",
      desc = "历练发现事件概率提升15%",       effect = { eventRateBonus = 0.15 } },
    { id = "gather_hand",  name = "采集",     type = "explore",
      desc = "采集材料数量提升20%",           effect = { gatherBonus = 0.20 } },
    { id = "safe_return",  name = "保命",     type = "explore",
      desc = "历练遭遇Boss时逃跑成功率+30%",  effect = { escapeBonus = 0.30 } },

    -- 辅助类
    { id = "heal_aura",    name = "治愈光环", type = "support",
      desc = "每10秒回复主人2%最大生命",       effect = { healPct = 0.02, healInterval = 10 } },
    { id = "mana_flow",    name = "灵气涌动", type = "support",
      desc = "修炼速度提升5%",               effect = { cultivationPct = 0.05 } },
    { id = "lucky_star",   name = "幸运星",   type = "support",
      desc = "炼丹/锻造成功率提升5%",         effect = { craftRateBonus = 0.05 } },
    { id = "ward",         name = "守护",     type = "support",
      desc = "主人受到致命伤害时抵消一次（冷却300秒）", effect = { fatalGuardCD = 300 } },
}

-- 天赋 id → 定义 快查
M.TALENT_MAP = {}
for _, t in ipairs(M.TALENTS) do
    M.TALENT_MAP[t.id] = t
end

--- 随机抽取 count 个不重复天赋
---@param count number
---@param exclude? string[] 已有天赋id列表（排除）
---@return string[] talentIds
function M.RollTalents(count, exclude)
    local pool = {}
    local excSet = {}
    if exclude then
        for _, id in ipairs(exclude) do excSet[id] = true end
    end
    for _, t in ipairs(M.TALENTS) do
        if not excSet[t.id] then
            pool[#pool + 1] = t.id
        end
    end
    -- Fisher-Yates shuffle + take first count
    local n = #pool
    count = math.min(count, n)
    local result = {}
    for i = 1, count do
        local j = math.random(i, n)
        pool[i], pool[j] = pool[j], pool[i]
        result[#result + 1] = pool[i]
    end
    return result
end

-- ============================================================================
-- 7. 羁绊系统
-- ============================================================================
-- 灵宠与主人的亲密度，通过出战/喂养/日常积累
-- 达到特定等级解锁额外属性加成
-- ============================================================================
M.BOND_LEVELS = {
    { level = 1, name = "初识",   bondNeeded = 0,    statBonus = 0.00 },
    { level = 2, name = "相知",   bondNeeded = 100,  statBonus = 0.03 },
    { level = 3, name = "默契",   bondNeeded = 500,  statBonus = 0.06 },
    { level = 4, name = "心意相通", bondNeeded = 1500, statBonus = 0.10 },
    { level = 5, name = "灵魂契约", bondNeeded = 5000, statBonus = 0.15 },
}

--- 根据羁绊值获取羁绊等级信息
---@param bondValue number
---@return table { level, name, bondNeeded, statBonus, nextLevel, nextBondNeeded }
function M.GetBondLevel(bondValue)
    bondValue = bondValue or 0
    local current = M.BOND_LEVELS[1]
    for i = #M.BOND_LEVELS, 1, -1 do
        if bondValue >= M.BOND_LEVELS[i].bondNeeded then
            current = M.BOND_LEVELS[i]
            break
        end
    end
    local nextLv = M.BOND_LEVELS[current.level + 1]
    return {
        level         = current.level,
        name          = current.name,
        bondNeeded    = current.bondNeeded,
        statBonus     = current.statBonus,
        nextLevel     = nextLv and nextLv.level or nil,
        nextBondNeeded = nextLv and nextLv.bondNeeded or nil,
    }
end

-- 每小时出战获得的羁绊值
M.BOND_PER_HOUR_ACTIVE = 5
-- 升级时获得的羁绊值
M.BOND_PER_LEVEL_UP = 2
-- 觉醒成功时获得的羁绊值
M.BOND_PER_AWAKEN = 50

-- ============================================================================
-- 8. 化形系统
-- ============================================================================
-- 条件：血脉 >= 神兽 且 觉醒满阶 且 羁绊等级 >= 4
-- 化形后灵宠获得人形外观，解锁专属技能
-- ============================================================================
M.TRANSFORM_REQUIRE = {
    minBloodline   = "shenshou",   -- 最低血脉要求
    awakenFull     = true,          -- 需觉醒满阶
    minBondLevel   = 4,             -- 最低羁绊等级
    lingshi        = 500000,        -- 灵石消耗
    jingxue        = 200,           -- 灵兽精血消耗
}

--- 检查是否满足化形条件
---@param bloodline string
---@param awakenStage number
---@param bondLevel number
---@return boolean, string|nil reason
function M.CanTransform(bloodline, awakenStage, bondLevel)
    local bl = M.BLOODLINE[bloodline]
    if not bl then return false, "未知血脉" end
    if not bl.canTransform then
        return false, "仅神兽及以上血脉可化形"
    end
    local rank = M.BLOODLINE_RANK[bloodline] or 0
    local minRank = M.BLOODLINE_RANK[M.TRANSFORM_REQUIRE.minBloodline] or 4
    if rank < minRank then
        return false, "血脉不足，需" .. M.BLOODLINE[M.TRANSFORM_REQUIRE.minBloodline].label .. "及以上"
    end
    if M.TRANSFORM_REQUIRE.awakenFull and awakenStage < bl.awakenStages then
        return false, "需觉醒圆满（" .. bl.awakenStages .. "阶）"
    end
    if bondLevel < M.TRANSFORM_REQUIRE.minBondLevel then
        return false, "羁绊等级不足（需" .. M.TRANSFORM_REQUIRE.minBondLevel .. "级）"
    end
    return true, nil
end

-- ============================================================================
-- 9. 灵宠模板（从 data_world.PETS 迁移，quality → bloodline）
-- ============================================================================
-- 保留原 id/name/role/skill/image/desc/element/combatStats
-- 新增 bloodline 字段，移除 quality 字段
-- ============================================================================
M.PETS = {
    -- === 凡兽 ===
    { id = 1,  name = "白狐",     bloodline = "fanshou", role = "辅助", skill = "灵狐附体",
      image = "image/pet_01_whitefox.png",   desc = "温顺灵巧的白狐幼崽，能提升主人闪避",
      element = "metal", combatStats = { action = "heal", healPct = 0.06, interval = 4 } },
    { id = 2,  name = "灵兔",     bloodline = "fanshou", role = "辅助", skill = "月华护盾",
      image = "image/pet_02_rabbit.png",     desc = "通灵玉兔，月光下能为主人提供护盾",
      element = "earth", combatStats = { action = "heal", healPct = 0.05, interval = 4 } },
    { id = 5,  name = "蝴蝶",     bloodline = "fanshou", role = "辅助", skill = "迷梦粉尘",
      image = "image/pet_05_butterfly.png",  desc = "如玉般通透的蝴蝶，可使敌人昏迷",
      element = "wood", combatStats = { action = "heal", healPct = 0.05, interval = 4 } },
    { id = 6,  name = "黑猫",     bloodline = "fanshou", role = "辅助", skill = "暗影潜行",
      image = "image/pet_06_blackcat.png",   desc = "神秘黑猫，能隐入暗影辅助偷袭",
      element = "water", combatStats = { action = "heal", healPct = 0.06, interval = 4 } },
    { id = 9,  name = "水鱼",     bloodline = "fanshou", role = "防御", skill = "治愈水泡",
      image = "image/pet_09_waterfish.png",  desc = "水系灵鱼，能在战斗中治愈主人",
      element = "water", combatStats = { action = "shield", shieldPct = 0.15, interval = 4 } },
    { id = 10, name = "灵鹿",     bloodline = "fanshou", role = "辅助", skill = "草木回春",
      image = "image/pet_10_deer.png",       desc = "灵山之鹿，精通草木之道",
      element = "wood", combatStats = { action = "heal", healPct = 0.06, interval = 4 } },
    { id = 12, name = "灵鼠",     bloodline = "fanshou", role = "辅助", skill = "寻宝嗅觉",
      image = "image/pet_12_mouse.png",      desc = "机灵小鼠，擅长发现隐藏宝物",
      element = "earth", combatStats = { action = "heal", healPct = 0.05, interval = 4 } },
    { id = 13, name = "蜗牛",     bloodline = "fanshou", role = "防御", skill = "缓速结界",
      image = "image/pet_13_snail.png",      desc = "通体如玉的蜗牛，能减缓敌人速度",
      element = "earth", combatStats = { action = "shield", shieldPct = 0.12, interval = 4 } },

    -- === 灵禽 ===
    { id = 3,  name = "火鸟",     bloodline = "lingqin", role = "攻击", skill = "烈焰冲击",
      image = "image/pet_03_firebird.png",   desc = "浴火而生的灵鸟，能释放火焰攻击",
      element = "fire", combatStats = { action = "attack", damagePct = 0.15, interval = 3 } },
    { id = 4,  name = "幼龙",     bloodline = "lingqin", role = "攻击", skill = "龙息吐纳",
      image = "image/pet_04_greendragon.png",desc = "龙族幼崽，龙族血脉提升修炼速度",
      element = "wood", combatStats = { action = "attack", damagePct = 0.18, interval = 3 } },
    { id = 7,  name = "仙鹤",     bloodline = "lingqin", role = "辅助", skill = "仙鹤引路",
      image = "image/pet_07_crane.png",      desc = "仙家之鹤，能引领主人寻找机缘",
      element = "metal", combatStats = { action = "heal", healPct = 0.08, interval = 3 } },
    { id = 8,  name = "雷貂",     bloodline = "lingqin", role = "攻击", skill = "雷光闪击",
      image = "image/pet_08_thundermink.png",desc = "体蕴雷电的灵貂，速度极快",
      element = "metal", combatStats = { action = "attack", damagePct = 0.15, interval = 3 } },
    { id = 11, name = "玄龟",     bloodline = "lingqin", role = "防御", skill = "龟甲壁障",
      image = "image/pet_11_turtle.png",     desc = "万年灵龟，防御力极其强大",
      element = "water", combatStats = { action = "shield", shieldPct = 0.20, interval = 3 } },
    { id = 15, name = "冰狐",     bloodline = "lingqin", role = "攻击", skill = "冰封千里",
      image = "image/pet_15_icefox.png",     desc = "极寒之狐，能冻结大范围敌人",
      element = "water", combatStats = { action = "attack", damagePct = 0.15, interval = 3 } },

    -- === 珍兽 ===
    { id = 14, name = "金鸟",     bloodline = "zhenshou", role = "辅助", skill = "鹏翼天击",
      image = "image/pet_14_goldbird.png",   desc = "大鹏一展翅，天地为之震颤",
      element = "metal", combatStats = { action = "heal", healPct = 0.12, interval = 3 } },
    { id = 20, name = "寒冰麒麟", bloodline = "zhenshou", role = "防御", skill = "玄冰护体",
      image = "image/pet_20_iceqilin.png",   desc = "冰属性麒麟，寒气逼人，防御无双",
      element = "water", combatStats = { action = "shield", shieldPct = 0.28, interval = 3 } },
    { id = 21, name = "九尾天狐", bloodline = "zhenshou", role = "攻击", skill = "天狐幻杀",
      image = "image/pet_21_ninetail.png",   desc = "九尾天狐，媚术与杀伐并重",
      element = "fire", combatStats = { action = "attack", damagePct = 0.25, interval = 3 } },
    { id = 22, name = "金翅大鹏", bloodline = "zhenshou", role = "攻击", skill = "鹏击万里",
      image = "image/pet_22_goldpeng.png",   desc = "大鹏展翅遮天蔽日，速度无人能及",
      element = "metal", combatStats = { action = "attack", damagePct = 0.25, interval = 3 } },

    -- === 神兽 (四神兽) ===
    { id = 16, name = "青龙",     bloodline = "shenshou", role = "攻击", skill = "苍龙七宿",
      image = "image/pet_16_qinglong.png",   desc = "东方神兽，掌管春雷万物生长，龙威震慑一切妖邪",
      element = "wood", combatStats = { action = "attack", damagePct = 0.30, interval = 2 },
      transformImage = "image/pet_16_qinglong_human.png", transformName = "青龙仙人" },
    { id = 17, name = "白虎",     bloodline = "shenshou", role = "攻击", skill = "虎啸山林",
      image = "image/pet_17_baihu.png",      desc = "西方神兽，主杀伐之力，虎啸一声百兽臣服",
      element = "metal", combatStats = { action = "attack", damagePct = 0.30, interval = 2 },
      transformImage = "image/pet_17_baihu_human.png", transformName = "白虎战神" },
    { id = 18, name = "朱雀",     bloodline = "shenshou", role = "攻击", skill = "涅槃天火",
      image = "image/pet_18_zhuque.png",     desc = "南方神兽，浴火重生永恒不灭，天火焚尽一切",
      element = "fire", combatStats = { action = "attack", damagePct = 0.30, interval = 2 },
      transformImage = "image/pet_18_zhuque_human.png", transformName = "朱雀仙子" },
    { id = 19, name = "玄武",     bloodline = "shenshou", role = "防御", skill = "龟蛇玄甲",
      image = "image/pet_19_xuanwu.png",     desc = "北方神兽，龟蛇合体固若金汤，万法不侵",
      element = "water", combatStats = { action = "shield", shieldPct = 0.35, interval = 3 },
      transformImage = "image/pet_19_xuanwu_human.png", transformName = "玄武真君" },
}

-- 四神兽 id 列表
M.SACRED_BEAST_IDS = { 16, 17, 18, 19 }

-- 模板 id → 定义 快查
M.PET_MAP = {}
for _, pet in ipairs(M.PETS) do
    M.PET_MAP[pet.id] = pet
end

--- 按 id 获取灵宠模板
---@param templateId number
---@return table|nil
function M.GetPet(templateId)
    return M.PET_MAP[templateId]
end

--- 获取指定血脉的所有模板
---@param bloodline string
---@return table[]
function M.GetPetsByBloodline(bloodline)
    local result = {}
    for _, pet in ipairs(M.PETS) do
        if pet.bloodline == bloodline then
            result[#result + 1] = pet
        end
    end
    return result
end

-- ============================================================================
-- 10. 捕获概率（按血脉）
-- ============================================================================
-- 替代旧 data_world.PET_QUALITY_RATES
-- ============================================================================
M.CAPTURE_BLOODLINE_RATES = {
    low = {    -- 区域1-2
        fanshou = 70, lingqin = 25, zhenshou = 5, shenshou = 0, hongmeng = 0,
    },
    mid = {    -- 区域3-4
        fanshou = 50, lingqin = 35, zhenshou = 13, shenshou = 2, hongmeng = 0,
    },
    high = {   -- 区域5-6
        fanshou = 30, lingqin = 35, zhenshou = 25, shenshou = 10, hongmeng = 0,
    },
    ultra = {  -- 区域7-8
        fanshou = 15, lingqin = 25, zhenshou = 35, shenshou = 22, hongmeng = 3,
    },
    apex = {   -- 区域9-10
        fanshou = 5, lingqin = 15, zhenshou = 30, shenshou = 35, hongmeng = 15,
    },
}

--- 根据区域序号获取捕获血脉概率
---@param areaIndex number 区域序号(1~10)
---@return table
function M.GetCaptureRates(areaIndex)
    if areaIndex <= 2 then return M.CAPTURE_BLOODLINE_RATES.low end
    if areaIndex <= 4 then return M.CAPTURE_BLOODLINE_RATES.mid end
    if areaIndex <= 6 then return M.CAPTURE_BLOODLINE_RATES.high end
    if areaIndex <= 8 then return M.CAPTURE_BLOODLINE_RATES.ultra end
    return M.CAPTURE_BLOODLINE_RATES.apex
end

-- ============================================================================
-- 11. 分解产出（按血脉）
-- ============================================================================
M.DECOMPOSE_YIELD = {
    fanshou  = { jingxue = 1,  lingshi = 100 },
    lingqin  = { jingxue = 3,  lingshi = 500 },
    zhenshou = { jingxue = 8,  lingshi = 2000 },
    shenshou = { jingxue = 20, lingshi = 8000 },
    hongmeng = { jingxue = 50, lingshi = 25000 },
}

-- ============================================================================
-- 12. 数据迁移工具
-- ============================================================================

--- 将旧品质灵宠数据迁移为新血脉格式
--- 旧格式: { uid, templateId, quality, level, exp, ascStage }
--- 新格式: { uid, templateId, bloodline, level, exp, awakenStage, talents, bond, transformed }
---@param oldPet table 旧灵宠实例数据
---@return table newPet 新格式灵宠数据
function M.MigratePetData(oldPet)
    local quality = oldPet.quality or "fanqi"
    local bloodline = M.QUALITY_TO_BLOODLINE[quality] or "fanshou"

    -- ascStage → awakenStage（直接映射，上限由新血脉的 awakenStages 截断）
    local bl = M.BLOODLINE[bloodline]
    local maxAwaken = bl and bl.awakenStages or 2
    local awakenStage = math.min(oldPet.ascStage or 0, maxAwaken)

    -- 生成初始天赋（按 talentSlots）
    local talentSlots = bl and bl.talentSlots or 1
    local talents = M.RollTalents(talentSlots)

    return {
        uid         = oldPet.uid,
        templateId  = oldPet.templateId,
        bloodline   = bloodline,
        level       = oldPet.level or 1,
        exp         = oldPet.exp or 0,
        awakenStage = awakenStage,
        talents     = talents,
        bond        = 0,
        transformed = false,
    }
end

--- 检查灵宠数据是否为旧格式（有 quality 无 bloodline）
---@param pet table
---@return boolean
function M.IsOldFormat(pet)
    return pet.quality ~= nil and pet.bloodline == nil
end

return M
