-- data_treasure.lua — 宝物数据模块
-- 公共宝物(8种) + 专属宝物(12种), 10级成长体系

local M = {}

---------------------------------------------------------------------------
-- 常量
---------------------------------------------------------------------------
M.MAX_LEVEL    = 10
M.PUBLIC_SLOTS = 2   -- 每位英雄2个公共宝物槽

-- 等级属性倍率
M.LEVEL_MULT = {
    1.00, 1.10, 1.22, 1.35, 1.50,
    1.68, 1.88, 2.10, 2.35, 2.65,
}

-- 升级消耗 { essence=宝物精华, copper=铜钱 }，索引=当前等级
M.UPGRADE_COSTS = {
    [1] = { essence = 5,   copper = 500   },
    [2] = { essence = 10,  copper = 1000  },
    [3] = { essence = 20,  copper = 2000  },
    [4] = { essence = 35,  copper = 4000  },
    [5] = { essence = 50,  copper = 6000  },
    [6] = { essence = 70,  copper = 9000  },
    [7] = { essence = 100, copper = 12000 },
    [8] = { essence = 140, copper = 16000 },
    [9] = { essence = 200, copper = 20000 },
    -- 10级满级，无下一级消耗
}

-- 掉落配置（按节点类型）
M.DROP_CONFIG = {
    normal = {
        essence = { rate = 0.25, min = 1, max = 2 },
    },
    elite = {
        essence = { rate = 0.50, min = 2, max = 4 },
        shards  = { rate = 0.12, min = 1, max = 2 },
    },
    boss = {
        essence = { rate = 1.00, min = 3, max = 6 },
        shards  = { rate = 0.25, min = 1, max = 3 },
        exclusiveShards = { rate = 0.08, min = 1, max = 1 },
    },
}

---------------------------------------------------------------------------
-- 宝物模板
---------------------------------------------------------------------------
M.TEMPLATES = {
    -- ═══════════════ 公共宝物 (8) ═══════════════
    sunzi_bingfa = {
        name  = "孙子兵法",
        type  = "public",
        quality = 5,  -- 橙
        baseAttr = { zhi = 12 },
        growthAttr = { zhi = 3 },
        passiveId   = "team_speed",
        passiveDesc = "全队速度+6",
        desc  = "百战百胜，善之善者也",
        composeCost = 50,
    },
    taiping_yaoshu = {
        name  = "太平要术",
        type  = "public",
        quality = 6,  -- 红
        baseAttr = { zhi = 18 },
        growthAttr = { zhi = 4 },
        passiveId   = "ctrl_hit_first",
        passiveDesc = "首次控制命中+10%",
        desc  = "道法自然，太平无为",
        composeCost = 80,
    },
    hufu_jinling = {
        name  = "虎符金令",
        type  = "public",
        quality = 5,
        baseAttr = { tong = 10 },
        growthAttr = { tong = 3 },
        passiveId   = "front_dmg_reduce",
        passiveDesc = "前排减伤+5%",
        desc  = "虎符合一，三军听令",
        composeCost = 50,
    },
    chiyan_zhangu = {
        name  = "赤焰战鼓",
        type  = "public",
        quality = 6,
        baseAttr = { yong = 16 },
        growthAttr = { yong = 4 },
        passiveId   = "skill_dmg_first",
        passiveDesc = "首次战法增伤12%",
        desc  = "战鼓声声催人进",
        composeCost = 80,
    },
    baihu_jigua = {
        name  = "白虎机括",
        type  = "public",
        quality = 5,
        baseAttr = { tong = 8 },
        growthAttr = { tong = 2 },
        passiveId   = "pursuit_rate",
        passiveDesc = "普攻追击率+6%",
        desc  = "机关算尽，百步穿杨",
        composeCost = 50,
    },
    qingnang_milu = {
        name  = "青囊秘录",
        type  = "public",
        quality = 6,
        baseAttr = { zhi = 16 },
        growthAttr = { zhi = 4 },
        passiveId   = "heal_lowest_eot",
        passiveDesc = "回合末最低血目标回血",
        desc  = "妙手仁心，悬壶济世",
        composeCost = 80,
    },
    xuanjia_bingjian = {
        name  = "玄甲兵鉴",
        type  = "public",
        quality = 5,
        baseAttr = { tong = 12 },
        growthAttr = { tong = 3 },
        passiveId   = "anti_crit_dmg",
        passiveDesc = "被暴击伤害-10%",
        desc  = "玄甲铁壁，固若金汤",
        composeCost = 50,
    },
    fenglei_zhanqi = {
        name  = "风雷战旗",
        type  = "public",
        quality = 6,
        baseAttr = { yong = 12 },
        growthAttr = { yong = 3 },
        passiveId   = "morale_init",
        passiveDesc = "全队开场怒气+10",
        desc  = "风雷激荡，士气如虹",
        composeCost = 80,
    },

    -- ═══════════════ 专属宝物 (12) ═══════════════
    ex_lvbu = {
        name  = "方天画戟",
        type  = "exclusive",
        heroId = "lvbu",
        quality = 6,
        baseAttr = { yong = 22 },
        growthAttr = { yong = 5 },
        passiveId   = "skill_mult_up",
        passiveDesc = "无双破军倍率+25%，破甲回合+1",
        desc  = "天下无双，戟指苍穹",
        composeCost = 30,
    },
    ex_guanyu = {
        name  = "青龙偃月刀",
        type  = "exclusive",
        heroId = "guanyu",
        quality = 6,
        baseAttr = { yong = 18 },
        growthAttr = { yong = 4 },
        passiveId   = "execute_threshold_up",
        passiveDesc = "斩杀阈值提升至35%",
        desc  = "义薄云天，刀落万军",
        composeCost = 30,
    },
    ex_zhangfei = {
        name  = "丈八蛇矛",
        type  = "exclusive",
        heroId = "zhangfei",
        quality = 6,
        baseAttr = { yong = 16, tong = 10 },
        growthAttr = { yong = 4, tong = 2 },
        passiveId   = "stun_rate_up",
        passiveDesc = "眩晕概率+10%",
        desc  = "燕人张翼德在此",
        composeCost = 30,
    },
    ex_zhaoyun = {
        name  = "龙胆亮银枪",
        type  = "exclusive",
        heroId = "zhaoyun",
        quality = 6,
        baseAttr = { yong = 16 },
        growthAttr = { yong = 4 },
        passiveId   = "first_round_dodge",
        passiveDesc = "首回合闪避+12%",
        desc  = "七进七出，枪影如龙",
        composeCost = 30,
    },
    ex_zhugeliang = {
        name  = "八卦羽扇",
        type  = "exclusive",
        heroId = "zhugeliang",
        quality = 6,
        baseAttr = { zhi = 24 },
        growthAttr = { zhi = 6 },
        passiveId   = "silence_rate_up",
        passiveDesc = "沉默概率+12%",
        desc  = "运筹帷幄，决胜千里",
        composeCost = 30,
    },
    ex_zhouyu = {
        name  = "赤焰琴书",
        type  = "exclusive",
        heroId = "zhouyu",
        quality = 6,
        baseAttr = { zhi = 22 },
        growthAttr = { zhi = 5 },
        passiveId   = "burn_stack_up",
        passiveDesc = "灼烧层数上限+1",
        desc  = "羽扇纶巾，谈笑间灰飞烟灭",
        composeCost = 30,
    },
    ex_huatuo = {
        name  = "青囊天卷",
        type  = "exclusive",
        heroId = "huatuo",
        quality = 6,
        baseAttr = { zhi = 20 },
        growthAttr = { zhi = 5 },
        passiveId   = "first_skill_purify",
        passiveDesc = "首次释放战法后全队净化",
        desc  = "医者仁心，妙手回春",
        composeCost = 30,
    },
    ex_caocao = {
        name  = "魏武令",
        type  = "exclusive",
        heroId = "caocao",
        quality = 6,
        baseAttr = { tong = 16, zhi = 14 },
        growthAttr = { tong = 4, zhi = 3 },
        passiveId   = "team_atk_up",
        passiveDesc = "全队增伤额外+6%",
        desc  = "挟天子以令诸侯",
        composeCost = 30,
    },
    ex_simayi = {
        name  = "冥策灵盘",
        type  = "exclusive",
        heroId = "simayi",
        quality = 6,
        baseAttr = { zhi = 24 },
        growthAttr = { zhi = 6 },
        passiveId   = "burn_dmg_up",
        passiveDesc = "灼烧伤害提升20%",
        desc  = "鹰视狼顾，隐忍待发",
        composeCost = 30,
    },
    ex_sunquan = {
        name  = "制衡玉玺",
        type  = "exclusive",
        heroId = "sunquan",
        quality = 6,
        baseAttr = { tong = 14, zhi = 16 },
        growthAttr = { tong = 3, zhi = 4 },
        passiveId   = "team_crit_hit",
        passiveDesc = "全队命中与暴击额外+5%",
        desc  = "坐断东南，制衡天下",
        composeCost = 30,
    },
    ex_liubei = {
        name  = "仁德玉佩",
        type  = "exclusive",
        heroId = "liubei",
        quality = 6,
        baseAttr = { tong = 12, zhi = 16 },
        growthAttr = { tong = 3, zhi = 4 },
        passiveId   = "heal_shield",
        passiveDesc = "治疗附带护盾",
        desc  = "以仁德服天下",
        composeCost = 30,
    },
    ex_zuoci = {
        name  = "太虚灵符",
        type  = "exclusive",
        heroId = "zuoci",
        quality = 6,
        baseAttr = { zhi = 22 },
        growthAttr = { zhi = 5 },
        passiveId   = "freeze_morph_hit",
        passiveDesc = "冰冻/变形命中+10%",
        desc  = "变化无穷，神出鬼没",
        composeCost = 30,
    },
}

-- 公共宝物ID列表（缓存）
local publicIds_ = nil
-- 专属宝物 heroId → templateId 映射（缓存）
local exclusiveMap_ = nil

---------------------------------------------------------------------------
-- 查询 API
---------------------------------------------------------------------------

--- 获取宝物模板
---@param templateId string
---@return table|nil
function M.Get(templateId)
    return M.TEMPLATES[templateId]
end

--- 获取所有公共宝物ID列表
---@return string[]
function M.GetAllPublicIds()
    if publicIds_ then return publicIds_ end
    publicIds_ = {}
    for id, t in pairs(M.TEMPLATES) do
        if t.type == "public" then
            publicIds_[#publicIds_ + 1] = id
        end
    end
    table.sort(publicIds_, function(a, b)
        return (M.TEMPLATES[a].quality or 0) < (M.TEMPLATES[b].quality or 0)
    end)
    return publicIds_
end

--- 获取英雄专属宝物的 templateId
---@param heroId string
---@return string|nil
function M.GetExclusiveFor(heroId)
    if not exclusiveMap_ then
        exclusiveMap_ = {}
        for id, t in pairs(M.TEMPLATES) do
            if t.type == "exclusive" and t.heroId then
                exclusiveMap_[t.heroId] = id
            end
        end
    end
    return exclusiveMap_[heroId]
end

--- 计算单个宝物实例的属性（按等级倍率）
---@param instance table {templateId, level}
---@return table {attr=value,...}
function M.CalcAttrs(instance)
    if not instance or not instance.templateId then return {} end
    local tmpl = M.TEMPLATES[instance.templateId]
    if not tmpl then return {} end
    local level = math.max(1, math.min(instance.level or 1, M.MAX_LEVEL))
    local mult = M.LEVEL_MULT[level] or 1.0
    local attrs = {}
    for attr, base in pairs(tmpl.baseAttr) do
        local growth = (tmpl.growthAttr and tmpl.growthAttr[attr]) or 0
        attrs[attr] = math.floor((base + growth * (level - 1)) * mult)
    end
    return attrs
end

--- 获取升级消耗
---@param currentLevel number
---@return table|nil {essence, copper}
function M.GetUpgradeCost(currentLevel)
    return M.UPGRADE_COSTS[currentLevel]
end

--- 属性中文名
local ATTR_NAMES = {
    tong = "统率", yong = "勇武", zhi = "智力",
}

--- 获取属性中文名
---@param attr string
---@return string
function M.GetAttrName(attr)
    return ATTR_NAMES[attr] or attr
end

--- 格式化属性值
---@param attr string
---@param val number
---@return string
function M.FormatAttr(attr, val)
    return M.GetAttrName(attr) .. "+" .. tostring(val)
end

return M
