---@meta
------------------------------------------------------------
-- data/battle_engine.lua  —— 三国神将录 回合制战斗引擎
-- 基于三围(统/勇/智)的自动战斗模拟
-- 来源: 设计文档 Section 3 + Section 23
------------------------------------------------------------
local DH = require("data.data_heroes")
local DM = require("data.data_maps")

local M = {}

------------------------------------------------------------
-- 常量
------------------------------------------------------------
M.MAX_ROUNDS      = 20    -- 超时回合数
M.MORALE_MAX      = 100   -- 士气上限(满100自动放战法)
M.MORALE_HIT      = 25    -- 普攻命中 +25
M.MORALE_BE_HIT   = 15    -- 被攻击 +15
M.MORALE_KILL     = 30    -- 击杀 +30
M.CRIT_MULTIPLIER = 1.5   -- 暴击倍率
M.BASE_CRIT_RATE  = 0.08  -- 基础暴击率

------------------------------------------------------------
-- 技能目标类型
------------------------------------------------------------
local TARGET = {
    SINGLE      = "single",       -- 单体
    LINE        = "line",         -- 纵排
    FRONT       = "front",        -- 前排
    BACK        = "back",         -- 后排
    ALL         = "all",          -- 全体
    RANDOM3     = "random3",      -- 随机3目标
    DOUBLE      = "double",       -- 双目标
    LOWEST_HP   = "lowest_hp",    -- 最低血量
    HIGHEST_HP  = "highest_hp",   -- 最高血量
    ALLY_ALL    = "ally_all",     -- 全体友方(治疗)
}

------------------------------------------------------------
-- 技能效果类型
------------------------------------------------------------
local EFFECT = {
    DAMAGE   = "damage",
    MAGIC    = "magic",
    HEAL     = "heal",
    SHIELD   = "shield",
    BUFF     = "buff",
    DEBUFF   = "debuff",
}

------------------------------------------------------------
-- 状态标签
------------------------------------------------------------
local STATUS = {
    STUN       = "stun",       -- 眩晕
    SILENCE    = "silence",    -- 沉默
    BURN       = "burn",       -- 灼烧
    ARMOR_BREAK = "armor_break", -- 破甲
    CHARM      = "charm",      -- 魅惑/混乱
    FREEZE     = "freeze",     -- 冰冻
    SHIELD     = "shield",     -- 护盾
    HOT        = "hot",        -- 持续回血
    ATK_UP     = "atk_up",     -- 增攻
    DEF_UP     = "def_up",     -- 增防
    SPEED_UP   = "speed_up",   -- 加速
}

M.STATUS = STATUS
M.TARGET = TARGET
M.EFFECT = EFFECT

------------------------------------------------------------
-- 技能数据库: 解析 heroData.skillDesc 生成结构化技能
-- 简化版: 为每个英雄预定义技能参数
------------------------------------------------------------
local SKILL_DB = {}

--- 根据 skillDesc 文本解析技能参数(启发式)
---@param heroId string
---@param heroData HeroData
---@return table
local function parseSkillFromDesc(heroId, heroData)
    local desc = heroData.skillDesc or ""
    local skill = {
        name     = heroData.skill or "普通攻击",
        heroId   = heroId,
        effects  = {},
    }

    -- 解析伤害倍率: "造成XXX%伤害" 或 "造成XXX%法伤"
    local dmgPct = desc:match("造成(%d+)%%[法]?伤")
    local isMagic = desc:find("法伤") ~= nil

    -- 解析治疗: "治疗XXX%兵力" 或 "群疗XXX%兵力"
    local healPct = desc:match("[治群]疗[%a]*(%d+)%%兵力")

    -- 解析护盾: "护盾XXX%兵力" 或 "护盾XXX%"
    local shieldPct = desc:match("护盾(%d+)%%")

    -- 解析目标类型
    local targetType = TARGET.SINGLE
    if desc:find("全体") or desc:find("群疗全体") or desc:find("全队") then
        targetType = TARGET.ALL
    elseif desc:find("纵排") then
        targetType = TARGET.LINE
    elseif desc:find("前排") then
        targetType = TARGET.FRONT
    elseif desc:find("后排") then
        targetType = TARGET.BACK
    elseif desc:find("随机3") or desc:find("随机三") then
        targetType = TARGET.RANDOM3
    elseif desc:find("2个目标") or desc:find("双目标") then
        targetType = TARGET.DOUBLE
    elseif desc:find("最高血量") then
        targetType = TARGET.HIGHEST_HP
    elseif desc:find("最低血量") then
        targetType = TARGET.LOWEST_HP
    end

    -- 治疗技能指向友方
    if healPct and not dmgPct then
        targetType = TARGET.ALLY_ALL
    end

    -- 构建主效果
    if healPct then
        skill.effects[#skill.effects + 1] = {
            type       = EFFECT.HEAL,
            target     = targetType,
            pct        = tonumber(healPct) / 100,
        }
    end
    if dmgPct then
        skill.effects[#skill.effects + 1] = {
            type       = isMagic and EFFECT.MAGIC or EFFECT.DAMAGE,
            target     = targetType,
            multiplier = tonumber(dmgPct) / 100,
        }
    end
    if shieldPct then
        skill.effects[#skill.effects + 1] = {
            type       = EFFECT.SHIELD,
            target     = TARGET.ALLY_ALL,
            pct        = tonumber(shieldPct) / 100,
        }
    end

    -- 如果没有伤害也没有治疗, 作为 buff 技能
    if #skill.effects == 0 then
        -- 检查是否增伤/增属性 buff
        if desc:find("增伤") or desc:find("增攻") or desc:find("攻击%+") then
            skill.effects[#skill.effects + 1] = {
                type   = EFFECT.BUFF,
                target = TARGET.ALLY_ALL,
                buff   = STATUS.ATK_UP,
                dur    = 2,
            }
        else
            -- 默认作为单体伤害
            skill.effects[#skill.effects + 1] = {
                type       = EFFECT.DAMAGE,
                target     = TARGET.SINGLE,
                multiplier = 1.8,
            }
        end
    end

    -- 解析附加状态效果: "XX%附/附加/概率 状态 N回合"
    local statusParsers = {
        { pattern = "(%d+)%%[附概率]*破甲", status = STATUS.ARMOR_BREAK },
        { pattern = "(%d+)%%[附概率]*眩晕", status = STATUS.STUN },
        { pattern = "(%d+)%%[附概率]*沉默", status = STATUS.SILENCE },
        { pattern = "(%d+)%%[附概率]*灼烧", status = STATUS.BURN },
        { pattern = "(%d+)%%[附概率]*混乱", status = STATUS.CHARM },
        { pattern = "(%d+)%%[附概率]*魅惑", status = STATUS.CHARM },
        { pattern = "(%d+)%%[附概率]*冰冻", status = STATUS.FREEZE },
        { pattern = "(%d+)%%[附概率]*控制", status = STATUS.STUN },
        { pattern = "附灼烧",               status = STATUS.BURN, fixedRate = 100 },
        { pattern = "附持续回血",            status = STATUS.HOT, fixedRate = 100, isAlly = true },
    }
    for _, sp in ipairs(statusParsers) do
        local rate = sp.fixedRate
        if not rate then
            local pct = desc:match(sp.pattern)
            if pct then rate = tonumber(pct) end
        else
            if not desc:find(sp.pattern) then rate = nil end
        end
        if rate then
            local dur = desc:match("(%d+)回合") or 2
            skill.statusEffect = {
                status = sp.status,
                rate   = rate / 100,
                dur    = tonumber(dur),
                isAlly = sp.isAlly or false,
            }
            break
        end
    end

    -- ============================================================
    -- 扩展: 解析高级战斗机制 (被动/条件触发)
    -- ============================================================
    skill.extras = {}

    -- 吸血: "吸血XX%"
    local lifestealPct = desc:match("吸血(%d+)%%")
    if lifestealPct then
        skill.extras.lifesteal = tonumber(lifestealPct) / 100
    end

    -- 追击: "击杀后追击一次" / "击杀回怒XX"
    if desc:find("击杀后追击") or desc:find("追击一次") then
        skill.extras.pursuitOnKill = true
    end
    local killMorale = desc:match("击杀回怒(%d+)")
    if killMorale then
        skill.extras.killMoraleBonus = tonumber(killMorale)
    end

    -- 反击: "被攻击时反击XX%"
    local counterPct = desc:match("反击(%d+)%%")
    if counterPct then
        skill.extras.counterRate = tonumber(counterPct) / 100
    end

    -- 免死: "免死1次" / "被击杀免死"
    if desc:find("免死") then
        skill.extras.deathImmune = true
    end
    -- 免控: "免控X回合"
    local immuneCtrl = desc:match("免控(%d+)回合")
    if immuneCtrl then
        skill.extras.immuneControl = tonumber(immuneCtrl)
    end

    -- 斩杀: "半血以下.*斩杀率+XX%"
    local executePct = desc:match("斩杀率%+(%d+)%%")
    if executePct then
        skill.extras.executeThreshold = 0.5
        skill.extras.executeRate = tonumber(executePct) / 100
    end

    -- 无视防御: "无视XX%防御"
    local ignoreDef = desc:match("无视(%d+)%%防御")
    if ignoreDef then
        skill.extras.ignoreDefense = tonumber(ignoreDef) / 100
    end

    -- 自回血: "自回血XX%"
    local selfHealPct = desc:match("自回血(%d+)%%")
    if selfHealPct then
        skill.extras.selfHealPerTurn = tonumber(selfHealPct) / 100
    end

    -- 增怒: "增怒XX点" / "回怒XX"
    local addMorale = desc:match("增怒(%d+)") or desc:match("回怒(%d+)")
    if addMorale then
        skill.extras.allyMoraleBoost = tonumber(addMorale)
    end

    -- 减怒: "减怒XX"
    local reduceMorale = desc:match("减怒(%d+)")
    if reduceMorale then
        skill.extras.enemyMoraleReduce = tonumber(reduceMorale)
    end

    -- 降智: "降智XX%持续N回合"
    local reduceZhi = desc:match("降智(%d+)%%")
    if reduceZhi then
        skill.extras.debuffZhi = tonumber(reduceZhi) / 100
    end

    -- 增暴击: "暴击率+XX%" / "暴击+XX%"
    local critBonus = desc:match("暴击率%+(%d+)%%") or desc:match("暴击%+(%d+)%%")
    if critBonus then
        skill.extras.critBonus = tonumber(critBonus) / 100
    end

    -- 破盾追击: "破盾后追击"
    if desc:find("破盾后追击") or desc:find("破盾追击") then
        skill.extras.pursuitOnShieldBreak = true
    end

    return skill
end

--- 获取英雄技能(带缓存)
---@param heroId string
---@return table
function M.GetSkill(heroId)
    if SKILL_DB[heroId] then return SKILL_DB[heroId] end
    local heroData = DH.Get(heroId)
    if not heroData then
        return { name = "普通攻击", effects = {{ type = EFFECT.DAMAGE, target = TARGET.SINGLE, multiplier = 1.0 }} }
    end
    local skill = parseSkillFromDesc(heroId, heroData)
    SKILL_DB[heroId] = skill
    return skill
end

------------------------------------------------------------
-- 战斗单元(BattleUnit)
------------------------------------------------------------

---@class BattleUnit
---@field id string
---@field name string
---@field heroId string|nil
---@field side string "ally"|"enemy"
---@field row string "front"|"back"
---@field tong number 统
---@field yong number 勇
---@field zhi number 智
---@field hp number
---@field maxHp number
---@field morale number
---@field level number
---@field statuses table<string, {dur:number, value:number}>
---@field alive boolean
---@field totalDamage number
---@field totalHeal number

--- 从英雄ID+玩家状态创建战斗单元
---@param heroId string
---@param heroState table {level, evolve}
---@param side string
---@param row string
---@return BattleUnit
function M.CreateHeroUnit(heroId, heroState, side, row)
    local hd = DH.Get(heroId)
    if not hd then
        return M.CreateSoldierUnit(heroId, 1, side, row, 1000)
    end

    local level = heroState and heroState.level or 1

    -- 三围成长: base + (cap - base) * (level / 80)
    local growthFactor = math.min(level / 80, 1.0)
    local tong = hd.stats.tong + (hd.caps.tong - hd.stats.tong) * growthFactor
    local yong = hd.stats.yong + (hd.caps.yong - hd.stats.yong) * growthFactor
    local zhi  = hd.stats.zhi  + (hd.caps.zhi  - hd.stats.zhi)  * growthFactor

    -- 兵力(HP) = 统 * 10 + 勇 * 5 + 等级 * 30
    local maxHp = math.floor(tong * 10 + yong * 5 + level * 30)

    return {
        id          = side .. "_" .. heroId,
        name        = hd.name,
        heroId      = heroId,
        side        = side,
        row         = row,
        tong        = math.floor(tong),
        yong        = math.floor(yong),
        zhi         = math.floor(zhi),
        hp          = maxHp,
        maxHp       = maxHp,
        morale      = 0,
        level       = level,
        statuses    = {},
        alive       = true,
        totalDamage = 0,
        totalHeal   = 0,
    }
end

--- 创建小兵单元(无英雄数据, 用简化数值)
---@param name string
---@param mapId number
---@param side string
---@param row string
---@param basePower number
---@return BattleUnit
function M.CreateSoldierUnit(name, mapId, side, row, basePower)
    local power = basePower or 1000
    -- 小兵三围按 power 等比缩放
    local tong = math.floor(power * 0.04 + math.random(5, 15))
    local yong = math.floor(power * 0.03 + math.random(5, 15))
    local zhi  = math.floor(power * 0.02 + math.random(5, 15))
    local maxHp = math.floor(tong * 8 + yong * 4 + 200)

    return {
        id          = side .. "_soldier_" .. name,
        name        = name,
        heroId      = nil,
        side        = side,
        row         = row,
        tong        = tong,
        yong        = yong,
        zhi         = zhi,
        hp          = maxHp,
        maxHp       = maxHp,
        morale      = 0,
        level       = 1,
        statuses    = {},
        alive       = true,
        totalDamage = 0,
        totalHeal   = 0,
    }
end

------------------------------------------------------------
-- 伤害计算公式
------------------------------------------------------------

--- Buff增伤倍率(atk_up +20%, def_up 减伤+20%)
local BUFF_ATK_MULT = 0.20
local BUFF_DEF_MULT = 0.20
local BUFF_SPD_PRIO = 15  -- speed_up 先手加成

--- 计算普攻伤害
---@param attacker BattleUnit
---@param defender BattleUnit
---@return number damage, boolean isCrit
local function calcBasicDamage(attacker, defender)
    -- 普攻伤害 = 统 * 3 * (1 - 对方统减伤率)
    local baseAtk = attacker.tong * 3
    -- atk_up: 增伤
    if attacker.statuses[STATUS.ATK_UP] then
        baseAtk = baseAtk * (1 + BUFF_ATK_MULT)
    end

    local defRate = math.min(defender.tong * 0.005, 0.6) -- 减伤上限60%

    -- def_up: 额外减伤
    if defender.statuses[STATUS.DEF_UP] then
        defRate = math.min(defRate + BUFF_DEF_MULT, 0.75)
    end

    -- 破甲: 防御减半
    if defender.statuses[STATUS.ARMOR_BREAK] then
        defRate = defRate * 0.5
    end

    local damage = baseAtk * (1 - defRate)

    -- 暴击判定
    local critRate = M.BASE_CRIT_RATE
    if attacker.yong > 100 then critRate = critRate + (attacker.yong - 100) * 0.001 end
    local isCrit = math.random() < critRate
    if isCrit then damage = damage * M.CRIT_MULTIPLIER end

    -- 随机波动 ±10%
    damage = damage * (0.9 + math.random() * 0.2)

    return math.floor(math.max(1, damage)), isCrit
end

--- 计算战法伤害
---@param attacker BattleUnit
---@param defender BattleUnit
---@param multiplier number
---@return number damage, boolean isCrit
local function calcSkillDamage(attacker, defender, multiplier)
    -- 战法伤害 = 勇 * 3 * multiplier * (1 - 对方勇减伤率)
    local baseAtk = attacker.yong * 3
    if attacker.statuses[STATUS.ATK_UP] then
        baseAtk = baseAtk * (1 + BUFF_ATK_MULT)
    end

    local defRate = math.min(defender.yong * 0.004, 0.55)
    if defender.statuses[STATUS.DEF_UP] then
        defRate = math.min(defRate + BUFF_DEF_MULT, 0.70)
    end

    if defender.statuses[STATUS.ARMOR_BREAK] then
        defRate = defRate * 0.5
    end

    local damage = baseAtk * multiplier * (1 - defRate)

    -- 战法暴击率较低但伤害更高
    local critRate = M.BASE_CRIT_RATE * 0.8
    if attacker.yong > 120 then critRate = critRate + (attacker.yong - 120) * 0.0012 end
    local isCrit = math.random() < critRate
    if isCrit then damage = damage * (M.CRIT_MULTIPLIER + 0.2) end

    damage = damage * (0.9 + math.random() * 0.2)
    return math.floor(math.max(1, damage)), isCrit
end

--- 计算法攻伤害
---@param attacker BattleUnit
---@param defender BattleUnit
---@param multiplier number
---@return number damage, boolean isCrit
local function calcMagicDamage(attacker, defender, multiplier)
    -- 法伤 = 智 * 3 * multiplier * (1 - 对方智减伤率)
    local baseAtk = attacker.zhi * 3
    if attacker.statuses[STATUS.ATK_UP] then
        baseAtk = baseAtk * (1 + BUFF_ATK_MULT)
    end

    local defRate = math.min(defender.zhi * 0.004, 0.5)
    if defender.statuses[STATUS.DEF_UP] then
        defRate = math.min(defRate + BUFF_DEF_MULT, 0.65)
    end

    local damage = baseAtk * multiplier * (1 - defRate)

    -- 法术不暴击，但受灼烧增伤
    if defender.statuses[STATUS.BURN] then
        damage = damage * 1.15
    end

    damage = damage * (0.9 + math.random() * 0.2)
    return math.floor(math.max(1, damage)), false
end

--- 计算治疗量
---@param healer BattleUnit
---@param target BattleUnit
---@param pct number
---@return number
local function calcHeal(healer, target, pct)
    local heal = math.floor(target.maxHp * pct)
    -- 智力加成
    heal = heal + math.floor(healer.zhi * 0.5)
    return heal
end

------------------------------------------------------------
-- 目标选取
------------------------------------------------------------

--- 获取存活单元列表
---@param units BattleUnit[]
---@param side string
---@param row string|nil
---@return BattleUnit[]
local function getAliveUnits(units, side, row)
    local result = {}
    for _, u in ipairs(units) do
        if u.alive and u.side == side then
            if not row or u.row == row then
                result[#result + 1] = u
            end
        end
    end
    return result
end

--- 选取目标
---@param attacker BattleUnit
---@param allUnits BattleUnit[]
---@param targetType string
---@return BattleUnit[]
local function selectTargets(attacker, allUnits, targetType)
    local enemySide = attacker.side == "ally" and "enemy" or "ally"
    local allySide  = attacker.side

    if targetType == TARGET.ALLY_ALL then
        return getAliveUnits(allUnits, allySide)
    end

    local enemies = getAliveUnits(allUnits, enemySide)
    if #enemies == 0 then return {} end

    if targetType == TARGET.ALL then
        return enemies
    elseif targetType == TARGET.FRONT then
        local front = getAliveUnits(allUnits, enemySide, "front")
        return #front > 0 and front or enemies
    elseif targetType == TARGET.BACK then
        local back = getAliveUnits(allUnits, enemySide, "back")
        return #back > 0 and back or enemies
    elseif targetType == TARGET.LINE then
        -- 纵排: 随机选一列(前排1人+后排1人)
        local front = getAliveUnits(allUnits, enemySide, "front")
        local back  = getAliveUnits(allUnits, enemySide, "back")
        local targets = {}
        if #front > 0 then targets[#targets + 1] = front[math.random(#front)] end
        if #back  > 0 then targets[#targets + 1] = back[math.random(#back)] end
        if #targets == 0 then targets = { enemies[math.random(#enemies)] } end
        return targets
    elseif targetType == TARGET.RANDOM3 then
        local targets = {}
        local pool = {}
        for _, e in ipairs(enemies) do pool[#pool + 1] = e end
        for _ = 1, math.min(3, #pool) do
            local idx = math.random(#pool)
            targets[#targets + 1] = pool[idx]
            table.remove(pool, idx)
        end
        return targets
    elseif targetType == TARGET.DOUBLE then
        local targets = {}
        local pool = {}
        for _, e in ipairs(enemies) do pool[#pool + 1] = e end
        for _ = 1, math.min(2, #pool) do
            local idx = math.random(#pool)
            targets[#targets + 1] = pool[idx]
            table.remove(pool, idx)
        end
        return targets
    elseif targetType == TARGET.LOWEST_HP then
        local lowest = enemies[1]
        for i = 2, #enemies do
            if enemies[i].hp / enemies[i].maxHp < lowest.hp / lowest.maxHp then
                lowest = enemies[i]
            end
        end
        return { lowest }
    elseif targetType == TARGET.HIGHEST_HP then
        local highest = enemies[1]
        for i = 2, #enemies do
            if enemies[i].hp > highest.hp then
                highest = enemies[i]
            end
        end
        return { highest }
    else
        -- SINGLE: 优先前排
        local front = getAliveUnits(allUnits, enemySide, "front")
        if #front > 0 then return { front[math.random(#front)] } end
        return { enemies[math.random(#enemies)] }
    end
end

------------------------------------------------------------
-- 伤害/治疗应用
------------------------------------------------------------

--- 对目标施加伤害
---@param attacker BattleUnit
---@param target BattleUnit
---@param rawDmg number
---@return number actualDmg
local function applyDamage(attacker, target, rawDmg)
    -- 护盾吸收
    local shieldInfo = target.statuses[STATUS.SHIELD]
    if shieldInfo and shieldInfo.value > 0 then
        local absorbed = math.min(shieldInfo.value, rawDmg)
        shieldInfo.value = shieldInfo.value - absorbed
        rawDmg = rawDmg - absorbed
        if shieldInfo.value <= 0 then
            target.statuses[STATUS.SHIELD] = nil
        end
    end

    target.hp = math.max(0, target.hp - rawDmg)
    attacker.totalDamage = attacker.totalDamage + rawDmg

    if target.hp <= 0 then
        target.alive = false
    end

    return rawDmg
end

--- 对目标施加治疗
---@param healer BattleUnit
---@param target BattleUnit
---@param amount number
---@return number actualHeal
local function applyHeal(healer, target, amount)
    local oldHp = target.hp
    target.hp = math.min(target.maxHp, target.hp + amount)
    local actualHeal = target.hp - oldHp
    healer.totalHeal = healer.totalHeal + actualHeal
    return actualHeal
end

--- 尝试施加状态效果
---@param target BattleUnit
---@param status string
---@param dur number
---@param rate number
---@param value number|nil
---@return boolean applied
local function tryApplyStatus(target, status, dur, rate, value)
    if not target.alive then return false end
    if math.random() > rate then return false end

    -- 不叠加控制(保留更长的)
    local existing = target.statuses[status]
    if existing and existing.dur >= dur then return false end

    target.statuses[status] = { dur = dur, value = value or 0 }
    return true
end

------------------------------------------------------------
-- 回合结算: 状态 tick
------------------------------------------------------------

--- 回合结束时结算状态
---@param unit BattleUnit
---@return table[] statusActions {type, status, damage/heal}
local function tickStatuses(unit)
    if not unit.alive then return {} end
    local actions = {}

    -- 灼烧 DoT
    local burn = unit.statuses[STATUS.BURN]
    if burn then
        local dot = math.floor(unit.maxHp * 0.05)
        unit.hp = math.max(1, unit.hp - dot)
        if unit.hp <= 0 then unit.hp = 1 end -- 灼烧不击杀
        actions[#actions + 1] = {
            type   = "burn_tick",
            target = unit.name,
            damage = dot,
        }
    end

    -- 持续回血 HoT
    local hot = unit.statuses[STATUS.HOT]
    if hot then
        local heal = math.floor(unit.maxHp * 0.06)
        local oldHp = unit.hp
        unit.hp = math.min(unit.maxHp, unit.hp + heal)
        actions[#actions + 1] = {
            type   = "hot_tick",
            target = unit.name,
            heal   = unit.hp - oldHp,
        }
    end

    -- 被动自回血(如董卓"每回合自回血8%")
    if unit.heroId then
        local sk = M.GetSkill(unit.heroId)
        if sk and sk.extras and sk.extras.selfHealPerTurn then
            local heal = math.floor(unit.maxHp * sk.extras.selfHealPerTurn)
            local oldHp = unit.hp
            unit.hp = math.min(unit.maxHp, unit.hp + heal)
            local actual = unit.hp - oldHp
            if actual > 0 then
                actions[#actions + 1] = {
                    type   = "passive_heal",
                    target = unit.name,
                    heal   = actual,
                }
            end
        end
    end

    -- 减少持续时间
    local expired = {}
    for status, info in pairs(unit.statuses) do
        info.dur = info.dur - 1
        if info.dur <= 0 then
            expired[#expired + 1] = status
        end
    end
    for _, status in ipairs(expired) do
        unit.statuses[status] = nil
    end

    return actions
end

------------------------------------------------------------
-- 出手顺序(基于统+速度)
------------------------------------------------------------

--- 确定出手顺序
---@param allUnits BattleUnit[]
---@return BattleUnit[]
local function getTurnOrder(allUnits)
    local alive = {}
    for _, u in ipairs(allUnits) do
        if u.alive then
            -- 眩晕/冰冻跳过
            if not u.statuses[STATUS.STUN] and not u.statuses[STATUS.FREEZE] then
                alive[#alive + 1] = u
            end
        end
    end
    -- 按 统+勇 降序(高属性先手), speed_up 加成
    table.sort(alive, function(a, b)
        local sa = a.tong + a.yong * 0.3 + math.random() * 5
        local sb = b.tong + b.yong * 0.3 + math.random() * 5
        if a.statuses[STATUS.SPEED_UP] then sa = sa + BUFF_SPD_PRIO end
        if b.statuses[STATUS.SPEED_UP] then sb = sb + BUFF_SPD_PRIO end
        return sa > sb
    end)
    return alive
end

------------------------------------------------------------
-- 执行单次行动
------------------------------------------------------------

--- 检查免死(deathImmune)并处理
---@param unit BattleUnit
---@return boolean savedByImmune
local function checkDeathImmune(unit)
    if unit.hp > 0 or unit.alive then return false end
    if not unit.heroId then return false end
    -- 检查是否有免死标记且尚未触发
    if unit._deathImmuneUsed then return false end
    local skill = M.GetSkill(unit.heroId)
    if skill and skill.extras and skill.extras.deathImmune then
        unit.hp = math.floor(unit.maxHp * 0.1)
        unit.alive = true
        unit._deathImmuneUsed = true
        return true
    end
    return false
end

--- 执行单个单元的行动
---@param actor BattleUnit
---@param allUnits BattleUnit[]
---@return table action {actor, type, targets, damage, isCrit, ...}
local function executeAction(actor, allUnits)
    if not actor.alive then return nil end

    -- 混乱状态: 攻击随机目标(包括友方)
    local isConfused = actor.statuses[STATUS.CHARM] ~= nil

    -- 判断是否释放战法(士气>=100且有heroId且未沉默)
    local useSkill = false
    local skill = nil
    if actor.heroId and actor.morale >= M.MORALE_MAX then
        if not actor.statuses[STATUS.SILENCE] then
            useSkill = true
            skill = M.GetSkill(actor.heroId)
            actor.morale = 0  -- 释放后清零
        end
    end

    -- 获取技能extras(即使不释放战法, 普攻时也需要被动extras)
    local extras = {}
    if actor.heroId then
        local sk = M.GetSkill(actor.heroId)
        if sk and sk.extras then extras = sk.extras end
    end

    local action = {
        actor    = actor.name,
        actorId  = actor.id,
        side     = actor.side,
        type     = useSkill and "skill" or "attack",
        name     = useSkill and skill.name or nil,
        targets  = {},
        damages  = {},
        heals    = {},
        isCrit   = {},
        killed   = {},
        statuses = {},
        extras   = {},  -- 记录触发的额外机制
    }

    -- 免控处理: 释放技能时自动施加免控
    if useSkill and extras.immuneControl then
        -- 免控会在技能释放的同回合清除控制状态
        actor.statuses[STATUS.STUN] = nil
        actor.statuses[STATUS.FREEZE] = nil
        actor.statuses[STATUS.CHARM] = nil
        isConfused = false
        action.extras[#action.extras + 1] = { type = "immune_control" }
    end

    --- 内部: 处理一次伤害命中的后续(吸血/斩杀/免死/击杀追击等)
    local function postDamageHit(t, dmg, isSkillHit)
        -- 斩杀: 低血量目标有概率直接击杀
        if t.alive and extras.executeRate and extras.executeThreshold then
            if t.hp / t.maxHp < extras.executeThreshold then
                if math.random() < extras.executeRate then
                    t.hp = 0
                    t.alive = false
                    action.extras[#action.extras + 1] = { type = "execute", target = t.name }
                end
            end
        end

        -- 免死检查
        if not t.alive then
            if checkDeathImmune(t) then
                action.extras[#action.extras + 1] = { type = "death_immune", target = t.name }
            end
        end

        -- 吸血
        if extras.lifesteal and extras.lifesteal > 0 and actor.alive then
            local healAmt = math.floor(dmg * extras.lifesteal)
            if healAmt > 0 then
                applyHeal(actor, actor, healAmt)
                action.extras[#action.extras + 1] = { type = "lifesteal", heal = healAmt }
            end
        end

        -- 被攻击增怒
        if t.alive then t.morale = math.min(M.MORALE_MAX, t.morale + M.MORALE_BE_HIT) end
        -- 击杀增怒
        if not t.alive then
            actor.morale = math.min(M.MORALE_MAX, actor.morale + M.MORALE_KILL)
            -- 击杀回怒额外加成
            if extras.killMoraleBonus then
                actor.morale = math.min(M.MORALE_MAX, actor.morale + extras.killMoraleBonus)
                action.extras[#action.extras + 1] = { type = "kill_morale", bonus = extras.killMoraleBonus }
            end
        end
    end

    if useSkill and skill then
        -- 释放战法
        local pursuitKillTarget = nil  -- 追击: 记录是否有击杀

        for _, eff in ipairs(skill.effects) do
            local targets
            if isConfused and eff.type ~= EFFECT.HEAL and eff.type ~= EFFECT.SHIELD and eff.type ~= EFFECT.BUFF then
                local confusedUnits = getAliveUnits(allUnits, actor.side)
                if #confusedUnits > 0 then
                    targets = { confusedUnits[math.random(#confusedUnits)] }
                else
                    targets = selectTargets(actor, allUnits, eff.target)
                end
            else
                targets = selectTargets(actor, allUnits, eff.target)
            end

            for _, t in ipairs(targets) do
                if eff.type == EFFECT.DAMAGE then
                    local mult = eff.multiplier or 1.8
                    -- 无视防御: 临时降低对方属性参与计算
                    local origYong = t.yong
                    if extras.ignoreDefense then
                        t.yong = math.floor(t.yong * (1 - extras.ignoreDefense))
                    end
                    local dmg, crit = calcSkillDamage(actor, t, mult)
                    t.yong = origYong  -- 恢复
                    -- 暴击加成
                    if extras.critBonus and not crit then
                        if math.random() < extras.critBonus then
                            dmg = math.floor(dmg * M.CRIT_MULTIPLIER)
                            crit = true
                        end
                    end
                    applyDamage(actor, t, dmg)
                    action.targets[#action.targets + 1] = t.name
                    action.damages[#action.damages + 1] = dmg
                    action.isCrit[#action.isCrit + 1] = crit
                    action.killed[#action.killed + 1] = not t.alive
                    postDamageHit(t, dmg, true)
                    if not t.alive then pursuitKillTarget = t end

                elseif eff.type == EFFECT.MAGIC then
                    local mult = eff.multiplier or 1.5
                    local origZhi = t.zhi
                    if extras.ignoreDefense then
                        t.zhi = math.floor(t.zhi * (1 - extras.ignoreDefense))
                    end
                    local dmg, crit = calcMagicDamage(actor, t, mult)
                    t.zhi = origZhi
                    applyDamage(actor, t, dmg)
                    action.targets[#action.targets + 1] = t.name
                    action.damages[#action.damages + 1] = dmg
                    action.isCrit[#action.isCrit + 1] = crit
                    action.killed[#action.killed + 1] = not t.alive
                    postDamageHit(t, dmg, true)
                    if not t.alive then pursuitKillTarget = t end

                elseif eff.type == EFFECT.HEAL then
                    local heal = calcHeal(actor, t, eff.pct or 0.2)
                    local actual = applyHeal(actor, t, heal)
                    action.targets[#action.targets + 1] = t.name
                    action.heals[#action.heals + 1] = actual
                    action.damages[#action.damages + 1] = 0

                elseif eff.type == EFFECT.SHIELD then
                    local shieldVal = math.floor(t.maxHp * (eff.pct or 0.1))
                    tryApplyStatus(t, STATUS.SHIELD, 2, 1.0, shieldVal)
                    action.targets[#action.targets + 1] = t.name
                    action.statuses[#action.statuses + 1] = { target = t.name, status = "shield", value = shieldVal }
                    action.damages[#action.damages + 1] = 0

                elseif eff.type == EFFECT.BUFF then
                    tryApplyStatus(t, eff.buff or STATUS.ATK_UP, eff.dur or 2, 1.0, 0)
                    action.targets[#action.targets + 1] = t.name
                    action.statuses[#action.statuses + 1] = { target = t.name, status = eff.buff or "atk_up" }
                    action.damages[#action.damages + 1] = 0
                end
            end

            -- 附加状态效果(仅对敌方)
            if skill.statusEffect and not skill.statusEffect.isAlly then
                for _, t in ipairs(targets) do
                    if t.alive and t.side ~= actor.side then
                        local applied = tryApplyStatus(t, skill.statusEffect.status, skill.statusEffect.dur, skill.statusEffect.rate)
                        if applied then
                            action.statuses[#action.statuses + 1] = {
                                target = t.name,
                                status = skill.statusEffect.status,
                                dur    = skill.statusEffect.dur,
                            }
                        end
                    end
                end
            end
            -- 友方附加状态(如持续回血)
            if skill.statusEffect and skill.statusEffect.isAlly then
                local allies = getAliveUnits(allUnits, actor.side)
                for _, t in ipairs(allies) do
                    tryApplyStatus(t, skill.statusEffect.status, skill.statusEffect.dur, skill.statusEffect.rate)
                end
            end
        end

        -- ============================================================
        -- 战法extras后处理
        -- ============================================================

        -- 增怒(全队): 如曹操"增怒15点"
        if extras.allyMoraleBoost then
            local allies = getAliveUnits(allUnits, actor.side)
            for _, a in ipairs(allies) do
                a.morale = math.min(M.MORALE_MAX, a.morale + extras.allyMoraleBoost)
            end
            action.extras[#action.extras + 1] = { type = "ally_morale", boost = extras.allyMoraleBoost }
        end

        -- 减怒(全敌): 如郭嘉"减怒25"
        if extras.enemyMoraleReduce then
            local enemySide = actor.side == "ally" and "enemy" or "ally"
            local enemies = getAliveUnits(allUnits, enemySide)
            for _, e in ipairs(enemies) do
                e.morale = math.max(0, e.morale - extras.enemyMoraleReduce)
            end
            action.extras[#action.extras + 1] = { type = "enemy_morale_reduce", amount = extras.enemyMoraleReduce }
        end

        -- 降智: 如郭嘉"降智15%持续2回合"(通过临时debuff模拟)
        if extras.debuffZhi then
            local enemySide = actor.side == "ally" and "enemy" or "ally"
            local enemies = getAliveUnits(allUnits, enemySide)
            for _, e in ipairs(enemies) do
                local reduction = math.floor(e.zhi * extras.debuffZhi)
                e.zhi = math.max(1, e.zhi - reduction)
            end
            action.extras[#action.extras + 1] = { type = "debuff_zhi", pct = extras.debuffZhi }
        end

        -- 击杀追击: 再攻击一个随机存活敌人
        if extras.pursuitOnKill and pursuitKillTarget then
            local enemySide = actor.side == "ally" and "enemy" or "ally"
            local remaining = getAliveUnits(allUnits, enemySide)
            if #remaining > 0 then
                local pt = remaining[math.random(#remaining)]
                local pdmg, pcrit = calcSkillDamage(actor, pt, 1.5)
                applyDamage(actor, pt, pdmg)
                action.targets[#action.targets + 1] = pt.name
                action.damages[#action.damages + 1] = pdmg
                action.isCrit[#action.isCrit + 1] = pcrit
                action.killed[#action.killed + 1] = not pt.alive
                action.extras[#action.extras + 1] = { type = "pursuit", target = pt.name, damage = pdmg }
                if not pt.alive then checkDeathImmune(pt) end
            end
        end
    else
        -- 普通攻击
        local enemySide = actor.side == "ally" and "enemy" or "ally"
        local targets
        if isConfused then
            local allies = getAliveUnits(allUnits, actor.side)
            targets = #allies > 0 and { allies[math.random(#allies)] } or {}
        else
            -- 优先前排
            local front = getAliveUnits(allUnits, enemySide, "front")
            if #front > 0 then
                targets = { front[math.random(#front)] }
            else
                local all = getAliveUnits(allUnits, enemySide)
                targets = #all > 0 and { all[math.random(#all)] } or {}
            end
        end

        for _, t in ipairs(targets) do
            local dmg, crit = calcBasicDamage(actor, t)
            -- 暴击加成(被动)
            if extras.critBonus and not crit then
                if math.random() < extras.critBonus then
                    dmg = math.floor(dmg * M.CRIT_MULTIPLIER)
                    crit = true
                end
            end
            applyDamage(actor, t, dmg)
            action.targets[#action.targets + 1] = t.name
            action.damages[#action.damages + 1] = dmg
            action.isCrit[#action.isCrit + 1] = crit
            action.killed[#action.killed + 1] = not t.alive

            -- 士气变化
            actor.morale = math.min(M.MORALE_MAX, actor.morale + M.MORALE_HIT)
            postDamageHit(t, dmg, false)
        end
    end

    return action
end

------------------------------------------------------------
-- 主战斗模拟
------------------------------------------------------------

--- 构建我方阵容
---@param gameState table
---@return BattleUnit[]
function M.BuildAllyTeam(gameState)
    local lineup = gameState.lineup
    local units = {}

    -- 前排
    for _, hid in ipairs(lineup.front or {}) do
        local heroState = gameState.heroes[hid]
        units[#units + 1] = M.CreateHeroUnit(hid, heroState, "ally", "front")
    end

    -- 后排
    for _, hid in ipairs(lineup.back or {}) do
        local heroState = gameState.heroes[hid]
        units[#units + 1] = M.CreateHeroUnit(hid, heroState, "ally", "back")
    end

    return units
end

--- 构建敌方阵容(基于地图数据和节点)
---@param mapId number
---@param nodeIdx number
---@param nodeType string
---@return BattleUnit[]
function M.BuildEnemyTeam(mapId, nodeIdx, nodeType)
    local mapData = DM.Get(mapId)
    if not mapData then
        -- fallback: 生成默认敌军
        return M.BuildDefaultEnemyTeam(mapId, nodeType)
    end

    local basePower = DM.GetNodePower(mapId, nodeIdx) or mapData.power

    -- 敌方阵容: 从地图数据中取小兵名
    local soldiers = mapData.soldiers or { "敌兵甲", "敌兵乙", "敌兵丙", "敌兵丁", "敌兵戊" }
    local elites   = mapData.elites or {}
    local boss     = mapData.boss or "守将"

    local units = {}

    if nodeType == "boss" then
        -- Boss节点: Boss + 2肉盾前排 + 2后排
        units[#units + 1] = M.CreateSoldierUnit(boss, mapId, "enemy", "front", basePower * 1.5)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[1] or "前排兵", mapId, "enemy", "front", basePower * 0.9)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[2] or "后排兵", mapId, "enemy", "back", basePower * 0.7)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[3] or "后排兵", mapId, "enemy", "back", basePower * 0.7)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[4] or "后排兵", mapId, "enemy", "back", basePower * 0.6)
    elseif nodeType == "elite" then
        -- 精英: 精英守将 + 4小兵
        local eliteName = #elites > 0 and elites[((nodeIdx - 1) % #elites) + 1] or "精英守将"
        units[#units + 1] = M.CreateSoldierUnit(eliteName, mapId, "enemy", "front", basePower * 1.2)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[1] or "前排兵", mapId, "enemy", "front", basePower * 0.85)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[2] or "后排兵", mapId, "enemy", "back", basePower * 0.7)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[3] or "后排兵", mapId, "enemy", "back", basePower * 0.65)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[4] or "后排兵", mapId, "enemy", "back", basePower * 0.6)
    else
        -- 普通: 从小兵池轮换
        local guardIdx = ((nodeIdx - 1) % #soldiers) + 1
        units[#units + 1] = M.CreateSoldierUnit(soldiers[guardIdx], mapId, "enemy", "front", basePower * 1.0)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[(guardIdx % #soldiers) + 1], mapId, "enemy", "front", basePower * 0.8)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[((guardIdx + 1) % #soldiers) + 1], mapId, "enemy", "back", basePower * 0.65)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[((guardIdx + 2) % #soldiers) + 1], mapId, "enemy", "back", basePower * 0.55)
        units[#units + 1] = M.CreateSoldierUnit(soldiers[((guardIdx + 3) % #soldiers) + 1], mapId, "enemy", "back", basePower * 0.5)
    end

    return units
end

--- 生成默认敌军(无地图数据时的fallback)
---@param mapId number
---@param nodeType string
---@return BattleUnit[]
function M.BuildDefaultEnemyTeam(mapId, nodeType)
    local power = 1000 + mapId * 100
    local names = { "敌兵甲", "敌兵乙", "敌兵丙", "敌兵丁", "敌兵戊" }
    local units = {}
    for i = 1, 5 do
        local row = i <= 2 and "front" or "back"
        local p = power * (i == 1 and 1.0 or (0.9 - i * 0.05))
        units[#units + 1] = M.CreateSoldierUnit(names[i], mapId, "enemy", row, p)
    end
    return units
end

------------------------------------------------------------
-- 战斗主入口
------------------------------------------------------------

--- 运行一场完整战斗
---@param allyUnits BattleUnit[]
---@param enemyUnits BattleUnit[]
---@param mapId number|nil
---@param nodeId number|nil
---@return table battleLog
function M.RunBattle(allyUnits, enemyUnits, mapId, nodeId)
    math.randomseed(math.floor(os.clock() * 100000))

    -- 合并所有单元
    local allUnits = {}
    for _, u in ipairs(allyUnits)  do allUnits[#allUnits + 1] = u end
    for _, u in ipairs(enemyUnits) do allUnits[#allUnits + 1] = u end

    local rounds = {}

    for roundNum = 1, M.MAX_ROUNDS do
        -- 检查胜负
        local allyAlive  = #getAliveUnits(allUnits, "ally")
        local enemyAlive = #getAliveUnits(allUnits, "enemy")
        if allyAlive == 0 or enemyAlive == 0 then break end

        -- 出手顺序
        local turnOrder = getTurnOrder(allUnits)
        local actions = {}

        for _, actor in ipairs(turnOrder) do
            if not actor.alive then goto continue end

            -- 再次检查是否战斗已结束
            local aA = #getAliveUnits(allUnits, "ally")
            local eA = #getAliveUnits(allUnits, "enemy")
            if aA == 0 or eA == 0 then break end

            local action = executeAction(actor, allUnits)
            if action then
                actions[#actions + 1] = action

                -- 反击检查: 被攻击的英雄如果有counterRate, 触发反击
                if action.type == "attack" or action.type == "skill" then
                    for ti = 1, #action.targets do
                        local tName = action.targets[ti]
                        local dmgVal = action.damages[ti] or 0
                        if dmgVal > 0 then
                            -- 查找对应的目标单元
                            for _, u in ipairs(allUnits) do
                                if u.name == tName and u.alive and u.heroId and u.side ~= actor.side then
                                    local tSkill = M.GetSkill(u.heroId)
                                    if tSkill and tSkill.extras and tSkill.extras.counterRate then
                                        if math.random() < tSkill.extras.counterRate and actor.alive then
                                            local cDmg, cCrit = calcBasicDamage(u, actor)
                                            applyDamage(u, actor, cDmg)
                                            actions[#actions + 1] = {
                                                actor   = u.name,
                                                actorId = u.id,
                                                side    = u.side,
                                                type    = "counter",
                                                targets = { actor.name },
                                                damages = { cDmg },
                                                isCrit  = { cCrit },
                                                killed  = { not actor.alive },
                                                heals   = {},
                                                statuses = {},
                                                extras  = {},
                                            }
                                        end
                                    end
                                    break
                                end
                            end
                        end
                    end
                end
            end

            ::continue::
        end

        -- 回合结束: 状态 tick
        local statusTicks = {}
        for _, u in ipairs(allUnits) do
            local ticks = tickStatuses(u)
            for _, t in ipairs(ticks) do
                statusTicks[#statusTicks + 1] = t
            end
        end

        rounds[#rounds + 1] = {
            round       = roundNum,
            actions     = actions,
            statusTicks = statusTicks,
        }
    end

    -- 结算
    local allyAlive, enemyAlive = 0, 0
    local allyTotalHp, enemyTotalHp = 0, 0
    for _, u in ipairs(allUnits) do
        if u.side == "ally" then
            if u.alive then allyAlive = allyAlive + 1; allyTotalHp = allyTotalHp + u.hp end
        else
            if u.alive then enemyAlive = enemyAlive + 1; enemyTotalHp = enemyTotalHp + u.hp end
        end
    end

    -- 超时判负: 按剩余总兵力
    local win
    if allyAlive == 0 then
        win = false
    elseif enemyAlive == 0 then
        win = true
    else
        win = allyTotalHp > enemyTotalHp
    end

    local dead = 0
    for _, u in ipairs(allyUnits) do if not u.alive then dead = dead + 1 end end
    local stars = win and (dead == 0 and 3 or (dead <= 2 and 2 or 1)) or 0

    -- 伤害/治疗统计
    local damageStats = {}
    local healStats   = {}
    for _, u in ipairs(allyUnits) do
        if u.totalDamage > 0 then
            damageStats[#damageStats + 1] = { name = u.name, damage = u.totalDamage }
        end
        if u.totalHeal > 0 then
            healStats[#healStats + 1] = { name = u.name, heal = u.totalHeal }
        end
    end
    table.sort(damageStats, function(a, b) return a.damage > b.damage end)
    table.sort(healStats,   function(a, b) return a.heal > b.heal end)

    -- 掉落生成
    local drops = {}
    if win then
        drops["铜钱"] = math.random(200, 500) + (mapId or 1) * 50
        drops["经验酒"] = math.random(1, 3)
        if stars >= 3 and math.random() < 0.2 then
            drops["招募令碎片"] = 1
        end
    end

    return {
        map_id      = mapId,
        node_id     = nodeId,
        allies      = allyUnits,
        enemies     = enemyUnits,
        rounds      = rounds,
        totalRounds = #rounds,
        result      = {
            win         = win,
            stars       = stars,
            drops       = drops,
            damageStats = damageStats,
            healStats   = healStats,
            allyAlive   = allyAlive,
            enemyAlive  = enemyAlive,
        },
    }
end

--- 快速战斗入口: 从 gameState 和节点信息直接生成战斗
---@param gameState table
---@param mapId number
---@param nodeId number
---@param nodeType string
---@return table battleLog
function M.QuickBattle(gameState, mapId, nodeId, nodeType)
    local allies  = M.BuildAllyTeam(gameState)
    local enemies = M.BuildEnemyTeam(mapId, nodeId, nodeType)
    return M.RunBattle(allies, enemies, mapId, nodeId)
end

return M
