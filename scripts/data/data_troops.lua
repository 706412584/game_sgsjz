---@meta
------------------------------------------------------------
-- data/data_troops.lua  —— 兵种数据库
-- 6大兵种分类 + 细分兵种 + 克制关系 + 分类特性
-- 来源: 设计文档 Section 16.3 / Section 20
------------------------------------------------------------
local M = {}

------------------------------------------------------------
-- 兵种大类常量
------------------------------------------------------------
M.CAT_INFANTRY  = "infantry"    -- 步兵系
M.CAT_CAVALRY   = "cavalry"     -- 骑兵系
M.CAT_ARCHER    = "archer"      -- 弓兵系
M.CAT_SIEGE     = "siege"       -- 机械系
M.CAT_MAGIC     = "magic"       -- 法术系
M.CAT_SUPPORT   = "support"     -- 辅助系

M.CAT_NAMES = {
    infantry = "步兵",
    cavalry  = "骑兵",
    archer   = "弓兵",
    siege    = "机械",
    magic    = "法术",
    support  = "辅助",
}

------------------------------------------------------------
-- 分类被动特性（战斗中自动生效）
------------------------------------------------------------
-- cavalry  : 所有骑兵都有闪避能力
-- archer   : 被抵挡时不受伤害; 高暴击
-- siege    : 不受士气影响; 攻击或防御极突出
-- support  : 无攻击力, 纯辅助
M.CAT_PASSIVES = {
    infantry = {},
    cavalry  = { dodge_bonus = 0.10 },             -- +10%闪避
    archer   = { crit_bonus = 0.12, block_immune = true }, -- +12%暴击, 被挡不受伤
    siege    = { morale_immune = true },            -- 不受士气影响
    magic    = {},
    support  = {},
}

------------------------------------------------------------
-- 克制关系: attacker_cat → defender_cat → 伤害倍率
-- 枪克骑(步克骑), 骑克弓, 弓克枪(弓克步)
------------------------------------------------------------
M.COUNTER_TABLE = {
    infantry = { cavalry = 1.15 },     -- 步兵对骑兵 +15%
    cavalry  = { archer  = 1.15 },     -- 骑兵对弓兵 +15%
    archer   = { infantry = 1.15 },    -- 弓兵对步兵 +15%
    -- 盾兵减免弓兵伤害由细分兵种处理
}

--- 获取克制倍率
---@param atkCat string 攻击方大类
---@param defCat string 防守方大类
---@return number 倍率(1.0=无克制)
function M.GetCounterMult(atkCat, defCat)
    local row = M.COUNTER_TABLE[atkCat]
    if row and row[defCat] then return row[defCat] end
    return 1.0
end

------------------------------------------------------------
-- 细分兵种数据库
------------------------------------------------------------
---@class TroopType
---@field name string           中文名
---@field category string       所属大类
---@field desc string           特点描述
---@field bonuses table|nil     属性加成 { stat = pct }
---@field specials table|nil    特殊效果

---@type table<string, TroopType>
M.TROOPS = {
    -- ================================================================
    -- 步兵系
    -- ================================================================
    infantry          = { name = "步兵",       category = "infantry", desc = "无",
        battleDesc = "对前排单体造成物理伤害" },
    heavy_infantry    = { name = "重步兵",     category = "infantry", desc = "伤害高",
        bonuses = { atk_pct = 0.08 },
        battleDesc = "对前排单体造成物理伤害，攻击+8%" },
    saber             = { name = "刀兵",       category = "infantry", desc = "伤害高",
        bonuses = { atk_pct = 0.10 },
        battleDesc = "对前排单体造成物理伤害，攻击+10%" },
    spear             = { name = "枪兵",       category = "infantry", desc = "对骑兵伤害增加",
        specials = { anti_cavalry = 0.20 },
        battleDesc = "对前排单体造成物理伤害，对骑兵额外+20%伤害" },
    light_infantry    = { name = "轻步兵",     category = "infantry", desc = "伤害高",
        bonuses = { atk_pct = 0.08 },
        battleDesc = "对前排单体造成物理伤害，攻击+8%" },
    shield            = { name = "盾牌兵",     category = "infantry", desc = "弓兵伤害减少",
        specials = { anti_archer_def = 0.20 },
        battleDesc = "对前排单体造成物理伤害，受弓兵伤害-20%" },
    shield_basic      = { name = "盾兵",       category = "infantry", desc = "弓兵伤害减少",
        specials = { anti_archer_def = 0.15 },
        battleDesc = "对前排单体造成物理伤害，受弓兵伤害-15%" },
    halberd           = { name = "戟兵",       category = "infantry", desc = "对骑兵伤害增加",
        specials = { anti_cavalry = 0.18 },
        battleDesc = "对前排单体造成物理伤害，对骑兵额外+18%伤害" },
    zhishui_heavy     = { name = "止水重步",   category = "infantry", desc = "擅长抵挡",
        bonuses = { def_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，防御+15%，擅长抵挡" },
    panshi_heavy      = { name = "磐石重步",   category = "infantry", desc = "磐石般坚固",
        bonuses = { def_pct = 0.20 },
        battleDesc = "对前排单体造成物理伤害，防御+20%，坚如磐石" },
    liehuo_light      = { name = "烈火轻步",   category = "infantry", desc = "攻击机动并重",
        bonuses = { atk_pct = 0.08, spd_pct = 0.08 },
        battleDesc = "对前排单体造成物理伤害，攻击+8%，速度+8%" },
    taxue_light       = { name = "踏雪轻步",   category = "infantry", desc = "机动性高",
        bonuses = { spd_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，速度+15%，优先出手" },
    tiechui_heavy     = { name = "铁锤重步",   category = "infantry", desc = "伤害高",
        bonuses = { atk_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，攻击+15%，重锤破敌" },
    changqiang_phalanx = { name = "长枪方阵", category = "infantry", desc = "对骑兵伤害增加",
        specials = { anti_cavalry = 0.22 },
        battleDesc = "对前排单体造成物理伤害，对骑兵额外+22%伤害" },
    golden_heavy      = { name = "黄金重步",   category = "infantry", desc = "综合能力强",
        bonuses = { atk_pct = 0.08, def_pct = 0.08 },
        battleDesc = "对前排单体造成物理伤害，攻击+8%，防御+8%，攻守兼备" },
    reaper_heavy      = { name = "死神重步",   category = "infantry", desc = "擅长暴击",
        bonuses = { crit_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，暴击率+15%，致命一击" },
    greenwood         = { name = "绿林野战",   category = "infantry", desc = "擅长反击",
        specials = { counter_rate = 0.25 },
        battleDesc = "对前排单体造成物理伤害，25%概率反击敌方攻击" },
    rattan            = { name = "藤甲兵",     category = "infantry", desc = "机动性高",
        bonuses = { spd_pct = 0.12 },
        battleDesc = "对前排单体造成物理伤害，速度+12%" },

    -- ================================================================
    -- 骑兵系 (全体 +10% 闪避)
    -- ================================================================
    cavalry_basic     = { name = "骑兵",       category = "cavalry", desc = "无",
        battleDesc = "对前排单体造成物理伤害，骑兵系自带闪避+10%" },
    heavy_cavalry     = { name = "重骑兵",     category = "cavalry", desc = "擅长闪避",
        bonuses = { dodge_pct = 0.08 },
        battleDesc = "对前排单体造成物理伤害，闪避+8%，骑兵系自带闪避+10%" },
    golden_cavalry    = { name = "黄金骑",     category = "cavalry", desc = "综合能力强",
        bonuses = { atk_pct = 0.06, def_pct = 0.06 },
        battleDesc = "对前排单体造成物理伤害，攻击+6%，防御+6%，骑兵系自带闪避+10%" },
    guerrilla_cavalry = { name = "游击骑",     category = "cavalry", desc = "机动性高",
        bonuses = { spd_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，速度+15%，骑兵系自带闪避+10%" },
    charge_cavalry    = { name = "冲锋骑",     category = "cavalry", desc = "伤害强",
        bonuses = { atk_pct = 0.12 },
        battleDesc = "对前排单体造成物理伤害，攻击+12%，骑兵系自带闪避+10%" },
    assault_cavalry   = { name = "突击骑",     category = "cavalry", desc = "伤害高",
        bonuses = { atk_pct = 0.10 },
        battleDesc = "对前排单体造成物理伤害，攻击+10%，骑兵系自带闪避+10%" },
    saber_cavalry     = { name = "砍刀骑",     category = "cavalry", desc = "伤害高",
        bonuses = { atk_pct = 0.10 },
        battleDesc = "对前排单体造成物理伤害，攻击+10%，骑兵系自带闪避+10%" },
    fire_cavalry      = { name = "烈火骑",     category = "cavalry", desc = "机动伤害并重",
        bonuses = { atk_pct = 0.08, spd_pct = 0.08 },
        battleDesc = "对前排单体造成物理伤害，攻击+8%，速度+8%，骑兵系自带闪避+10%" },
    thunder_cavalry   = { name = "雷电骑",     category = "cavalry", desc = "机动性强",
        bonuses = { spd_pct = 0.12 },
        battleDesc = "对前排单体造成物理伤害，速度+12%，骑兵系自带闪避+10%" },
    shadow_cavalry    = { name = "暗影骑",     category = "cavalry", desc = "擅长暴击",
        bonuses = { crit_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，暴击率+15%，骑兵系自带闪避+10%" },
    white_dragon_cav  = { name = "白龙骑",     category = "cavalry", desc = "防御能力高",
        bonuses = { def_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，防御+15%，骑兵系自带闪避+10%" },
    lion_cavalry      = { name = "狮子骑",     category = "cavalry", desc = "伤害高",
        bonuses = { atk_pct = 0.15 },
        battleDesc = "对前排单体造成物理伤害，攻击+15%，骑兵系自带闪避+10%" },
    lingbo_cavalry    = { name = "凌波骑",     category = "cavalry", desc = "擅长闪躲",
        bonuses = { dodge_pct = 0.12 },
        battleDesc = "对前排单体造成物理伤害，闪避+12%，骑兵系自带闪避+10%" },

    -- ================================================================
    -- 弓兵系 (全体 +12% 暴击, 被挡不受伤)
    -- ================================================================
    archer_basic      = { name = "弓兵",       category = "archer", desc = "无",
        battleDesc = "对单体造成物理伤害，弓兵系自带暴击+12%，被抵挡不受伤" },
    longbow           = { name = "长弓兵",     category = "archer", desc = "擅长暴击",
        bonuses = { crit_pct = 0.08 },
        battleDesc = "对单体造成物理伤害，暴击率+8%，弓兵系自带暴击+12%，被抵挡不受伤" },
    heavy_bow         = { name = "重弓兵",     category = "archer", desc = "擅长暴击",
        bonuses = { crit_pct = 0.08 },
        battleDesc = "对单体造成物理伤害，暴击率+8%，弓兵系自带暴击+12%，被抵挡不受伤" },
    javelin           = { name = "投矛兵",     category = "archer", desc = "伤害高",
        bonuses = { atk_pct = 0.12 },
        battleDesc = "对单体造成物理伤害，攻击+12%，弓兵系自带暴击+12%，被抵挡不受伤" },
    dart              = { name = "飞镖兵",     category = "archer", desc = "擅长闪避",
        bonuses = { dodge_pct = 0.10 },
        battleDesc = "对单体造成物理伤害，闪避+10%，弓兵系自带暴击+12%，被抵挡不受伤" },
    heavy_longbow     = { name = "重型长弓",   category = "archer", desc = "擅长暴击",
        bonuses = { crit_pct = 0.10 },
        battleDesc = "对单体造成物理伤害，暴击率+10%，弓兵系自带暴击+12%，被抵挡不受伤" },
    crossbow          = { name = "劲弩兵",     category = "archer", desc = "擅长暴击",
        bonuses = { crit_pct = 0.12 },
        battleDesc = "对单体造成物理伤害，暴击率+12%，弓兵系自带暴击+12%，被抵挡不受伤" },
    shadow_bow        = { name = "影子弓",     category = "archer", desc = "反击/抵挡",
        specials = { counter_rate = 0.20 },
        battleDesc = "对单体造成物理伤害，20%概率反击，弓兵系自带暴击+12%，被抵挡不受伤" },
    poison_dart       = { name = "剧毒标兵",   category = "archer", desc = "暴击+逃兵",
        bonuses = { crit_pct = 0.10 }, specials = { flee_chance = 0.08 },
        battleDesc = "对单体造成物理伤害，暴击率+10%，8%概率令敌军逃兵，弓兵系自带暴击+12%" },
    snow_longbow      = { name = "飘雪长弓",   category = "archer", desc = "擅长抵挡",
        bonuses = { def_pct = 0.12 },
        battleDesc = "对单体造成物理伤害，防御+12%，弓兵系自带暴击+12%，被抵挡不受伤" },
    fire_javelin      = { name = "烈火掷矛",   category = "archer", desc = "暴击+高伤害",
        bonuses = { crit_pct = 0.10, atk_pct = 0.08 },
        battleDesc = "对单体造成物理伤害，攻击+8%，暴击率+10%，弓兵系自带暴击+12%，被抵挡不受伤" },
    tree_throw        = { name = "拔树投掷",   category = "archer", desc = "伤害高",
        bonuses = { atk_pct = 0.15 },
        battleDesc = "对单体造成物理伤害，攻击+15%，弓兵系自带暴击+12%，被抵挡不受伤" },
    thunder_crossbow  = { name = "紫电怒弩",   category = "archer", desc = "暴击",
        bonuses = { crit_pct = 0.12 },
        battleDesc = "对单体造成物理伤害，暴击率+12%，弓兵系自带暴击+12%，被抵挡不受伤" },
    golden_crossbow   = { name = "黄金连弩",   category = "archer", desc = "综合能力强",
        bonuses = { atk_pct = 0.08, crit_pct = 0.08 },
        battleDesc = "对单体造成物理伤害，攻击+8%，暴击率+8%，弓兵系自带暴击+12%，被抵挡不受伤" },
    mounted_bow       = { name = "战弓骑",     category = "archer", desc = "擅长暴击",
        bonuses = { crit_pct = 0.10 },
        battleDesc = "对单体造成物理伤害，暴击率+10%，弓兵系自带暴击+12%，被抵挡不受伤" },
    lingbo_dart       = { name = "凌波影子镖", category = "archer", desc = "机动性高",
        bonuses = { spd_pct = 0.15 },
        battleDesc = "对单体造成物理伤害，速度+15%，弓兵系自带暴击+12%，被抵挡不受伤" },

    -- ================================================================
    -- 机械系 (不受士气影响)
    -- ================================================================
    catapult          = { name = "投石车",     category = "siege", desc = "横向伤害",
        specials = { aoe_row = true },
        battleDesc = "对横排全体造成物理伤害，不受士气影响" },
    arrow_tower       = { name = "箭楼车",     category = "siege", desc = "单体高暴击",
        bonuses = { crit_pct = 0.20 },
        battleDesc = "对单体造成物理伤害，暴击率+20%，不受士气影响" },
    hammer_cart       = { name = "巨型铁锤车", category = "siege", desc = "单体伤害",
        bonuses = { atk_pct = 0.10 },
        battleDesc = "对单体造成物理伤害，攻击+10%，不受士气影响" },
    rock_cart         = { name = "磐石甲车",   category = "siege", desc = "防御减免",
        bonuses = { def_pct = 0.25 },
        battleDesc = "对单体造成物理伤害，防御+25%，不受士气影响" },
    ballista          = { name = "弩炮车",     category = "siege", desc = "纵向伤害",
        specials = { aoe_line = true },
        battleDesc = "对纵排全体造成物理伤害，不受士气影响" },
    mega_arrow_tower  = { name = "巨树箭塔车", category = "siege", desc = "箭楼增强",
        bonuses = { crit_pct = 0.25, atk_pct = 0.08 },
        battleDesc = "对单体造成物理伤害，攻击+8%，暴击率+25%，不受士气影响" },
    sky_thunder       = { name = "天雷轰",     category = "siege", desc = "投石车增强",
        bonuses = { atk_pct = 0.15 }, specials = { aoe_row = true },
        battleDesc = "对横排全体造成物理伤害，攻击+15%，不受士气影响" },
    fire_ballista     = { name = "烈火弩炮",   category = "siege", desc = "弩炮增强",
        bonuses = { atk_pct = 0.12 }, specials = { aoe_line = true },
        battleDesc = "对纵排全体造成物理伤害，攻击+12%，不受士气影响" },

    -- ================================================================
    -- 法术系
    -- ================================================================
    fire_strategist     = { name = "火计策士",   category = "magic", desc = "成功率高, 威力不大",
        bonuses = { hit_pct = 0.10 },
        battleDesc = "对全体敌军造成法术伤害，命中率+10%，成功率高但威力较低" },
    water_strategist    = { name = "水计策士",   category = "magic", desc = "成功率适中, 威力适中",
        battleDesc = "对全体敌军造成法术伤害，成功率与威力均衡" },
    thunder_mage        = { name = "雷击术士",   category = "magic", desc = "成功率低, 威力大, 混乱",
        bonuses = { atk_pct = 0.12 }, specials = { confuse_chance = 0.15 },
        battleDesc = "对全体敌军造成法术伤害，攻击+12%，15%概率令目标混乱，威力大但成功率低" },
    fire_god            = { name = "火神策士",   category = "magic", desc = "火计加强版",
        bonuses = { atk_pct = 0.10, hit_pct = 0.08 },
        battleDesc = "对全体敌军造成法术伤害，攻击+10%，命中率+8%，火计强化版" },
    flood_strategist    = { name = "洪水策士",   category = "magic", desc = "水计加强版",
        bonuses = { atk_pct = 0.10 },
        battleDesc = "对全体敌军造成法术伤害，攻击+10%，水计强化版" },
    thorn_mage          = { name = "荆棘术士",   category = "magic", desc = "AOE 无伤害, 叛逃",
        specials = { defect_chance = 0.20 },
        battleDesc = "对全体敌军施加控制，不造成伤害，20%概率令目标叛逃" },
    sun_mage            = { name = "烈日术士",   category = "magic", desc = "AOE 无伤害, 混乱",
        specials = { confuse_chance = 0.25 },
        battleDesc = "对全体敌军施加控制，不造成伤害，25%概率令目标混乱" },
    rockfall_strategist = { name = "落石策士",   category = "magic", desc = "AOE 威力适中",
        bonuses = { atk_pct = 0.08 },
        battleDesc = "对全体敌军造成法术伤害，攻击+8%，落石覆盖范围广" },
    thunder_god         = { name = "紫电术士",   category = "magic", desc = "雷击加强版",
        bonuses = { atk_pct = 0.15 }, specials = { confuse_chance = 0.20 },
        battleDesc = "对全体敌军造成法术伤害，攻击+15%，20%概率令目标混乱，雷击强化版" },

    -- ================================================================
    -- 辅助系 (无攻击力, 纯辅助)
    -- ================================================================
    supply            = { name = "粮草队",     category = "support", desc = "治疗部队",
        specials = { heal_pct = 0.10 },
        battleDesc = "每回合为全体友军恢复10%兵力，不参与攻击" },
    dancer            = { name = "舞姬",       category = "support", desc = "随机振奋",
        specials = { inspire_chance = 0.65 },
        battleDesc = "每回合65%概率振奋随机友军，提升其攻击力，不参与攻击" },
    medic             = { name = "医疗队",     category = "support", desc = "高级治疗",
        specials = { heal_pct = 0.18 },
        battleDesc = "每回合为全体友军恢复18%兵力，不参与攻击，高级治疗" },
    war_drum          = { name = "战鼓队",     category = "support", desc = "+34士气-5敌方",
        bonuses = { def_pct = 0.10 },
        specials = { morale_boost = 34, morale_reduce = 5 },
        battleDesc = "每回合为全体友军增加34点士气，降低敌方5点士气，防御+10%，不参与攻击" },
}

------------------------------------------------------------
-- 英雄 → 兵种映射
-- key = heroId, value = troop_type key
------------------------------------------------------------
M.HERO_TROOP = {
    -- 步兵系
    zhaoyun       = "zhishui_heavy",       -- 止水重步
    zhangfei      = "tiechui_heavy",       -- 铁锤重步
    liubei        = "golden_heavy",        -- 黄金重步
    sunquan       = "golden_heavy",        -- 黄金重步
    luxun         = "taxue_light",         -- 踏雪轻步

    -- 骑兵系
    sunce         = "golden_cavalry",      -- 黄金骑
    ganning       = "thunder_cavalry",     -- 雷电骑
    xiaohoudun    = "shadow_cavalry",      -- 暗影骑
    machao        = "lion_cavalry",        -- 狮子骑
    huangzhong    = "lingbo_cavalry",      -- 凌波骑
    zhangliao     = "charge_cavalry",      -- 冲锋骑（突击收割→冲锋骑）
    lvbu          = "lion_cavalry",        -- 狮子骑（天下第一武将）
    molvbu        = "lion_cavalry",        -- 狮子骑（魔吕布）
    shenlvbu      = "lion_cavalry",        -- 狮子骑（神吕布）

    -- 弓兵系
    taishici      = "fire_javelin",        -- 烈火掷矛
    guanyu        = "golden_crossbow",     -- 黄金连弩
    dongzhuo      = "crossbow",            -- 劲弩兵
    sunshangxiang = "fire_javelin",        -- 烈火掷矛（弓箭输出）

    -- 法术系
    zhouyu        = "fire_god",            -- 火神策士
    guojia        = "thorn_mage",          -- 荆棘术士
    pangtong      = "rockfall_strategist", -- 落石策士
    zhugeliang    = "thunder_god",         -- 紫电术士
    simayi        = "flood_strategist",    -- 洪水策士（持续法核）
    zuoci         = "thunder_god",         -- 紫电术士（控制法核）
    diaochan      = "sun_mage",            -- 烈日术士（控制辅助→混乱）

    -- 辅助系
    caiwenji      = "dancer",              -- 舞姬
    xiaoqiao      = "dancer",              -- 舞姬
    huatuo        = "medic",               -- 医疗队
    daqiao        = "war_drum",            -- 战鼓队
    zhenji        = "medic",               -- 医疗队（治疗辅助）
    caocao        = "war_drum",            -- 战鼓队（辅助统帅→鼓舞全军）
    yuanshao      = "war_drum",            -- 战鼓队（统帅辅助→盟主鼓舞）
    huangyueying  = "hammer_cart",         -- 巨型铁锤车（机关辅助→机械系）
}

------------------------------------------------------------
-- API
------------------------------------------------------------

--- 获取英雄的兵种 key
---@param heroId string
---@return string|nil troopKey
function M.GetHeroTroop(heroId)
    return M.HERO_TROOP[heroId]
end

--- 获取兵种数据
---@param troopKey string
---@return TroopType|nil
function M.Get(troopKey)
    return M.TROOPS[troopKey]
end

--- 获取英雄的兵种大类
---@param heroId string
---@return string|nil category
function M.GetHeroCategory(heroId)
    local key = M.HERO_TROOP[heroId]
    if not key then return nil end
    local t = M.TROOPS[key]
    return t and t.category or nil
end

--- 获取英雄兵种的中文名
---@param heroId string
---@return string
function M.GetHeroTroopName(heroId)
    local key = M.HERO_TROOP[heroId]
    if not key then return "步兵" end
    local t = M.TROOPS[key]
    return t and t.name or "步兵"
end

--- 获取英雄兵种大类中文名
---@param heroId string
---@return string
function M.GetHeroCatName(heroId)
    local cat = M.GetHeroCategory(heroId)
    return cat and M.CAT_NAMES[cat] or "步兵"
end

--- 获取兵种属性加成
---@param troopKey string
---@return table bonuses { atk_pct, def_pct, spd_pct, crit_pct, dodge_pct, hit_pct }
function M.GetBonuses(troopKey)
    local t = M.TROOPS[troopKey]
    return t and t.bonuses or {}
end

--- 获取分类被动
---@param category string
---@return table
function M.GetCatPassives(category)
    return M.CAT_PASSIVES[category] or {}
end

return M
