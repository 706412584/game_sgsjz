-- ============================================================================
-- 《问道长生》修炼功法数据配置（V2 功法拆分）
-- 设计来源: docs/design-v2-cultivation-combat.md §三
-- 职责：修炼功法（提升修炼速度）的定义、阵营规则、等级倍率
-- ============================================================================

local M = {}

-- ============================================================================
-- 阵营常量
-- ============================================================================
M.FACTION_RIGHTEOUS = "righteous"  -- 正道
M.FACTION_DEMONIC   = "demonic"    -- 魔道
M.FACTION_UNIVERSAL = "universal"  -- 通用

-- ============================================================================
-- 阵营与种族映射
-- ============================================================================
-- 人族/灵族 → 正道，魔族/妖族 → 魔道
M.RACE_FACTION = {
    human   = M.FACTION_RIGHTEOUS,
    spirit  = M.FACTION_RIGHTEOUS,
    demon   = M.FACTION_DEMONIC,
    monster = M.FACTION_DEMONIC,
}

-- ============================================================================
-- 修炼功法列表
-- ============================================================================
-- realmMin/realmMax: 适用境界范围（tier），nil 表示不限
-- faction: 阵营限制
-- baseBonus: 基础修炼速度加成（如 0.20 = +20%）
-- unlockMethod: 获取方式
-- ============================================================================
M.ARTS = {
    -- ======== 正道系 ========
    {
        id        = "qingxin_tuna",
        name      = "清心吐纳决",
        faction   = M.FACTION_RIGHTEOUS,
        realmMin  = 1,
        realmMax  = 4,   -- 炼气~金丹
        baseBonus = 0.20,
        unlockMethod = "initial",  -- 正道初始
        desc      = "正道入门心法，引天地灵气入体，清心凝神，修炼速度+20%。",
    },
    {
        id        = "taishang_yuanying",
        name      = "太上元婴经",
        faction   = M.FACTION_RIGHTEOUS,
        realmMin  = 5,
        realmMax  = 7,   -- 元婴~返虚
        baseBonus = 0.40,
        unlockMethod = "drop",
        desc      = "正道上乘心法，凝练元婴，修炼速度+40%。",
    },
    {
        id        = "hundun_hedao",
        name      = "混沌合道录",
        faction   = M.FACTION_RIGHTEOUS,
        realmMin  = 8,
        realmMax  = 9,   -- 合道~渡劫
        baseBonus = 0.70,
        unlockMethod = "drop",
        desc      = "正道至高心法，混沌归一，修炼速度+70%。",
    },
    -- ======== 魔道系 ========
    {
        id        = "shihun_tunyuan",
        name      = "噬魂吞元功",
        faction   = M.FACTION_DEMONIC,
        realmMin  = 1,
        realmMax  = 4,
        baseBonus = 0.20,
        unlockMethod = "initial",
        desc      = "魔道入门功法，噬取天地精华为己用，修炼速度+20%。",
    },
    {
        id        = "mingyuan_huaying",
        name      = "冥渊化婴术",
        faction   = M.FACTION_DEMONIC,
        realmMin  = 5,
        realmMax  = 7,
        baseBonus = 0.40,
        unlockMethod = "drop",
        desc      = "魔道上乘功法，以冥渊之力化婴，修炼速度+40%。",
    },
    {
        id        = "wanmo_guiyuan",
        name      = "万魔归元典",
        faction   = M.FACTION_DEMONIC,
        realmMin  = 8,
        realmMax  = 9,
        baseBonus = 0.70,
        unlockMethod = "drop",
        desc      = "魔道至高功法，万魔归一，修炼速度+70%。",
    },
    -- ======== 通用系 ========
    {
        id        = "xianqi_tuna",
        name      = "仙气吐纳经",
        faction   = M.FACTION_UNIVERSAL,
        realmMin  = 9,
        realmMax  = nil,  -- 渡劫+，无上限
        baseBonus = 1.00,
        unlockMethod = "drop",
        desc      = "超脱正魔的仙家心法，修炼速度+100%。",
    },
}

-- ============================================================================
-- 修炼功法等级表（10 级，沿用 SKILL_LEVELS 体系）
-- ============================================================================
M.LEVELS = {
    { level = 1,  timeSec = 0,      wisdomReq = 0,   multiplier = 1.0 },
    { level = 2,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.1 },
    { level = 3,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.2 },
    { level = 4,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.3 },
    { level = 5,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 6,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.6 },
    { level = 7,  timeSec = 28800,  wisdomReq = 90,  multiplier = 1.8 },
    { level = 8,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 9,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.2 },
    { level = 10, timeSec = 86400,  wisdomReq = 120, multiplier = 2.5 },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据 ID 获取修炼功法定义
---@param id string
---@return table|nil
function M.GetArt(id)
    for _, a in ipairs(M.ARTS) do
        if a.id == id then return a end
    end
    return nil
end

--- 根据名称获取修炼功法定义
---@param name string
---@return table|nil
function M.GetArtByName(name)
    for _, a in ipairs(M.ARTS) do
        if a.name == name then return a end
    end
    return nil
end

--- 获取修炼功法等级配置
---@param level number
---@return table|nil
function M.GetLevel(level)
    if level >= 1 and level <= #M.LEVELS then
        return M.LEVELS[level]
    end
    return nil
end

--- 获取指定种族的初始修炼功法 ID
---@param race string "human"|"demon"|"spirit"|"monster"
---@return string
function M.GetInitialArtForRace(race)
    local faction = M.RACE_FACTION[race] or M.FACTION_RIGHTEOUS
    if faction == M.FACTION_DEMONIC then
        return "shihun_tunyuan"
    end
    return "qingxin_tuna"
end

--- 检查种族是否能使用指定功法
---@param race string
---@param artId string
---@return boolean, string|nil
function M.CanUse(race, artId)
    local art = M.GetArt(artId)
    if not art then return false, "功法不存在" end
    if art.faction == M.FACTION_UNIVERSAL then return true end
    local raceFaction = M.RACE_FACTION[race] or M.FACTION_RIGHTEOUS
    if art.faction ~= raceFaction then
        local factionName = art.faction == M.FACTION_RIGHTEOUS and "正道" or "魔道"
        return false, "此功法为" .. factionName .. "功法，与你的种族不符"
    end
    return true
end

--- 检查境界是否在功法适用范围内
---@param artId string
---@param tier number 当前境界阶数
---@return boolean inRange 是否在最佳范围内
function M.IsInRealmRange(artId, tier)
    local art = M.GetArt(artId)
    if not art then return false end
    if art.realmMin and tier < art.realmMin then return false end
    if art.realmMax and tier > art.realmMax then return false end
    return true
end

--- 计算修炼功法的实际修炼速度加成
--- 低阶功法在高阶境界仍可使用，但加成不变
---@param artId string
---@param level number 功法等级
---@return number bonus 修炼速度加成（如 0.3 = +30%）
function M.CalcBonus(artId, level)
    local art = M.GetArt(artId)
    if not art then return 0 end
    local lvConf = M.GetLevel(level or 1)
    local multiplier = lvConf and lvConf.multiplier or 1.0
    return art.baseBonus * multiplier
end

--- 检查功法是否已解锁（initial 类型始终解锁，drop 类型需在 unlockedCultArts 中）
---@param art table 功法定义
---@param unlockedCultArts table|nil 已解锁的 drop 功法 id 集合 { [artId]=true }
---@return boolean
function M.IsUnlocked(art, unlockedCultArts)
    if art.unlockMethod == "initial" then return true end
    if not unlockedCultArts then return false end
    return unlockedCultArts[art.id] == true
end

--- 获取适用于当前种族+境界的所有功法（排序：加成从高到低）
--- 仅返回已解锁且达到境界要求的功法
---@param race string
---@param tier number|nil 当前境界阶数（nil 则不做境界过滤）
---@param unlockedCultArts table|nil 已解锁的 drop 功法 { [artId]=true }（nil 则仅返回 initial）
---@return table[] 可用功法定义列表
function M.GetAvailable(race, tier, unlockedCultArts)
    local result = {}
    for _, art in ipairs(M.ARTS) do
        local canUse = M.CanUse(race, art.id)
        if canUse then
            -- 境界下限过滤
            if tier and art.realmMin and tier < art.realmMin then
                -- 未达到境界要求，跳过
            elseif not M.IsUnlocked(art, unlockedCultArts) then
                -- 未解锁（drop 类型且不在解锁列表中），跳过
            else
                result[#result + 1] = art
            end
        end
    end
    -- 按 baseBonus 降序
    table.sort(result, function(a, b) return a.baseBonus > b.baseBonus end)
    return result
end

--- 获取指定种族在指定境界的最佳初始功法
--- 用于副本掉落/商店展示推荐
---@param race string
---@param tier number
---@return table|nil
function M.GetBestForRealm(race, tier)
    local available = M.GetAvailable(race, tier, nil)
    for _, art in ipairs(available) do
        if M.IsInRealmRange(art.id, tier) then
            return art
        end
    end
    -- 没有匹配范围的，返回可用列表第一个
    return available[1]
end

return M
