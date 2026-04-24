-- ============================================================================
-- 《问道长生》战斗 & 修炼公式模块
-- 数据来源: docs/game-design-values.md §1.4, §15
-- ============================================================================

local DataRealms     = require("data_realms")
local DataAttr       = require("data_attributes")
local DataSpiritRoot = require("data_spirit_root")

local M = {}

-- ============================================================================
-- 1.4 修炼产出公式 (放置挂机)
-- ============================================================================
-- 每秒修为 = 基础值 * 灵根倍率 * 功法加成 * 洞府浓度加成
-- 基础值 = 1 + 境界阶数 * 0.5
-- 洞府浓度加成 = 1 + 浓度/100

--- 计算每秒修为产出
---@param tier number 境界阶数
---@param spiritRoots table[] 灵根数组 [{type,quality,slot}]（兼容旧 rootName 字符串）
---@param skillBonus number 功法修炼速度加成(如0.15表示+15%)
---@param caveDensity number 洞府灵气浓度(0~100)
---@return number
function M.CalcCultivationPerSec(tier, spiritRoots, skillBonus, caveDensity)
    local base = 1 + tier * 0.5
    local rootRate
    if type(spiritRoots) == "table" and #spiritRoots > 0 then
        rootRate = DataSpiritRoot.CalcMultiplier(spiritRoots)
    elseif type(spiritRoots) == "string" then
        -- 向后兼容：旧数据传 rootName 字符串
        rootRate = DataAttr.GetRootRate(spiritRoots)
    else
        rootRate = 1.0
    end
    local skillMul = 1 + (skillBonus or 0)
    local caveMul = 1 + (caveDensity or 0) / 100
    return base * rootRate * skillMul * caveMul
end

-- ============================================================================
-- 15.1 伤害计算
-- ============================================================================
-- 基础伤害 = 攻击 * (1 + 功法攻击加成%)
-- 实际伤害 = 基础伤害 * (100 / (100 + 防御))
-- 暴击伤害 = 实际伤害 * 暴击倍率

M.CRIT_MULTIPLIER = 1.5    -- 暴击伤害倍率
M.MIN_HIT_RATE    = 10     -- 最低命中率(%)
M.MAX_HIT_RATE    = 95     -- 最高命中率(%)
M.MAX_CRIT_RATE   = 50     -- 最高暴击率(%)

--- 计算一次攻击的基础伤害(不含暴击)
---@param attack number 攻击力
---@param defense number 目标防御力
---@param skillAtkBonus number 功法攻击加成(如0.3表示+30%)
---@return number
function M.CalcDamage(attack, defense, skillAtkBonus)
    local baseDmg = attack * (1 + (skillAtkBonus or 0))
    local actualDmg = baseDmg * (100 / (100 + defense))
    return math.max(1, math.floor(actualDmg))
end

--- 计算暴击伤害
---@param baseDamage number
---@return number
function M.CalcCritDamage(baseDamage)
    return math.floor(baseDamage * M.CRIT_MULTIPLIER)
end

-- ============================================================================
-- 15.2 命中判定
-- ============================================================================
-- 命中概率 = 命中 - 闪避 (最低10%, 最高95%)
-- 暴击概率 = 暴击 (最高50%)

--- 计算命中率
---@param hitRate number 攻击方命中(%)
---@param dodgeRate number 防守方闪避(%)
---@return number 实际命中率(%)
function M.CalcHitRate(hitRate, dodgeRate)
    local rate = hitRate - dodgeRate
    return math.max(M.MIN_HIT_RATE, math.min(M.MAX_HIT_RATE, rate))
end

--- 计算实际暴击率
---@param critRate number 暴击(%)
---@return number 实际暴击率(%)
function M.CalcCritRate(critRate)
    return math.min(M.MAX_CRIT_RATE, math.max(0, critRate))
end

--- 判定一次攻击结果
---@param attacker table { attack, hit, crit, skillAtkBonus }
---@param defender table { defense, dodge, hp }
---@return table { hit, crit, damage }
function M.ResolveAttack(attacker, defender)
    local result = { hit = false, crit = false, damage = 0 }

    -- 命中判定
    local hitRate = M.CalcHitRate(attacker.hit or 95, defender.dodge or 0)
    if math.random(100) > hitRate then
        return result -- miss
    end
    result.hit = true

    -- 伤害计算
    local dmg = M.CalcDamage(attacker.attack, defender.defense, attacker.skillAtkBonus)

    -- 暴击判定
    local critRate = M.CalcCritRate(attacker.crit or 0)
    if math.random(100) <= critRate then
        result.crit = true
        dmg = M.CalcCritDamage(dmg)
    end

    result.damage = dmg
    return result
end

-- ============================================================================
-- 突破相关
-- ============================================================================

--- 计算突破成功率(含丹药加成)
---@param tier number 目标境界阶数
---@param pillBonus number 丹药加成百分点(如20表示+20%)
---@return number 成功率(%)
function M.CalcBreakRate(tier, pillBonus)
    local realm = DataRealms.GetRealm(tier)
    if not realm then return 0 end
    local rate = realm.breakRate + (pillBonus or 0)
    return math.min(100, math.max(0, rate))
end

--- 计算突破失败损失的修为
---@param currentCultivation number
---@return number
function M.CalcBreakFailCost(currentCultivation)
    return math.floor(currentCultivation * DataRealms.BREAK_FAIL_COST_PCT / 100)
end

return M
