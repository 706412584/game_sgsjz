------------------------------------------------------------
-- data/data_equip.lua  —— 三国神将录 装备数据模块
-- 职责：装备模板库、槽位/品质常量、属性计算、套装效果
-- 两端共享（客户端展示 + 服务端逻辑）
------------------------------------------------------------

local M = {}

------------------------------------------------------------
-- 1. 常量
------------------------------------------------------------

--- 装备槽位定义
M.SLOTS = { "weapon", "helmet", "armor", "boots", "accessory", "mount" }

M.SLOT_NAMES = {
    weapon    = "武器",
    helmet    = "头盔",
    armor     = "铠甲",
    boots     = "靴子",
    accessory = "饰品",
    mount     = "坐骑",
}

--- 品质常量 1-6
M.QUALITY_NAMES = { "白", "绿", "蓝", "紫", "橙", "金" }

--- 主属性名称映射
M.ATTR_NAMES = {
    tong  = "统率",
    yong  = "勇武",
    zhi   = "智力",
    hp    = "兵力",
    atk   = "攻击",
    def   = "防御",
    crit  = "暴击",
    dodge = "闪避",
    speed = "速度",
}

------------------------------------------------------------
-- 2. 装备模板库
------------------------------------------------------------

--- 每件装备模板
---@class EquipTemplate
---@field name string       装备名称
---@field slot string       槽位
---@field quality number    品质 1-6
---@field setId string|nil  套装ID
---@field baseAttr table    基础属性 { attr = value, ... }
---@field desc string|nil   描述

M.TEMPLATES = {
    ------------------------------------------------
    -- 武圣套 (wusheng) — 攻击型
    ------------------------------------------------
    qinglong_yanyue  = { name = "青龙偃月刀",  slot = "weapon",    quality = 5, setId = "wusheng",
                         baseAttr = { tong = 120, yong = 80 },
                         desc = "温酒斩华雄的传奇兵刃" },
    wusheng_helmet   = { name = "武圣盔",      slot = "helmet",    quality = 5, setId = "wusheng",
                         baseAttr = { def = 60, hp = 800 },
                         desc = "关帝庙中供奉的圣盔" },
    wusheng_armor    = { name = "赤兔战甲",    slot = "armor",     quality = 5, setId = "wusheng",
                         baseAttr = { def = 90, hp = 1200 },
                         desc = "与赤兔同色的火红铠甲" },
    wusheng_boots    = { name = "千里靴",      slot = "boots",     quality = 5, setId = "wusheng",
                         baseAttr = { speed = 30, dodge = 0.05 },
                         desc = "日行千里的神行靴" },
    wusheng_acc      = { name = "春秋宝典",    slot = "accessory", quality = 5, setId = "wusheng",
                         baseAttr = { zhi = 40, tong = 60 },
                         desc = "夜读春秋所悟之典" },
    wusheng_mount    = { name = "赤兔马",      slot = "mount",     quality = 5, setId = "wusheng",
                         baseAttr = { speed = 40, hp = 600 },
                         desc = "人中吕布，马中赤兔" },

    ------------------------------------------------
    -- 卧龙套 (wolong) — 法术型
    ------------------------------------------------
    wolong_fan       = { name = "鹅毛扇",      slot = "weapon",    quality = 5, setId = "wolong",
                         baseAttr = { zhi = 140, tong = 40 },
                         desc = "运筹帷幄的羽扇" },
    wolong_helmet    = { name = "纶巾",        slot = "helmet",    quality = 5, setId = "wolong",
                         baseAttr = { zhi = 50, def = 40 },
                         desc = "羽扇纶巾的标志" },
    wolong_armor     = { name = "八卦衣",      slot = "armor",     quality = 5, setId = "wolong",
                         baseAttr = { def = 60, zhi = 60, hp = 800 },
                         desc = "道袍绣八卦阵纹" },
    wolong_boots     = { name = "步云履",      slot = "boots",     quality = 5, setId = "wolong",
                         baseAttr = { speed = 25, dodge = 0.04 },
                         desc = "脚踏祥云的道人履" },
    wolong_acc       = { name = "七星灯",      slot = "accessory", quality = 5, setId = "wolong",
                         baseAttr = { zhi = 80, hp = 400 },
                         desc = "续命祈禳的七星灯" },
    wolong_mount     = { name = "四轮车",      slot = "mount",     quality = 5, setId = "wolong",
                         baseAttr = { speed = 20, def = 40, hp = 800 },
                         desc = "木牛流马之师" },

    ------------------------------------------------
    -- 霸王套 (bawang) — 坦克型
    ------------------------------------------------
    bawang_ji        = { name = "方天画戟",    slot = "weapon",    quality = 5, setId = "bawang",
                         baseAttr = { yong = 150, tong = 50 },
                         desc = "天下无双的霸王之戟" },
    bawang_helmet    = { name = "兽面盔",      slot = "helmet",    quality = 5, setId = "bawang",
                         baseAttr = { def = 80, hp = 1000 },
                         desc = "狰狞兽面的战盔" },
    bawang_armor     = { name = "玄铁甲",      slot = "armor",     quality = 5, setId = "bawang",
                         baseAttr = { def = 120, hp = 1500 },
                         desc = "刀枪不入的玄铁铸甲" },
    bawang_boots     = { name = "霸王履",      slot = "boots",     quality = 5, setId = "bawang",
                         baseAttr = { speed = 20, hp = 600 },
                         desc = "力拔山兮气盖世" },
    bawang_acc       = { name = "传国玉玺",    slot = "accessory", quality = 5, setId = "bawang",
                         baseAttr = { hp = 1200, def = 40 },
                         desc = "受命于天，既寿永昌" },
    bawang_mount     = { name = "踏雪乌骓",    slot = "mount",     quality = 5, setId = "bawang",
                         baseAttr = { speed = 35, hp = 800 },
                         desc = "项王所乘，追风踏雪" },

    ------------------------------------------------
    -- 天命套 (tianming) — 速度型
    ------------------------------------------------
    tianming_sword   = { name = "倚天剑",      slot = "weapon",    quality = 5, setId = "tianming",
                         baseAttr = { tong = 100, yong = 60, speed = 15 },
                         desc = "号令天下，莫敢不从" },
    tianming_helmet  = { name = "天命冠",      slot = "helmet",    quality = 5, setId = "tianming",
                         baseAttr = { def = 50, speed = 20 },
                         desc = "天命所归者之冕" },
    tianming_armor   = { name = "龙鳞甲",      slot = "armor",     quality = 5, setId = "tianming",
                         baseAttr = { def = 80, hp = 1000, dodge = 0.03 },
                         desc = "龙鳞覆体，避实击虚" },
    tianming_boots   = { name = "追风靴",      slot = "boots",     quality = 5, setId = "tianming",
                         baseAttr = { speed = 45, dodge = 0.06 },
                         desc = "迅如疾风的天命之靴" },
    tianming_acc     = { name = "天机玉佩",    slot = "accessory", quality = 5, setId = "tianming",
                         baseAttr = { speed = 25, dodge = 0.05 },
                         desc = "洞察天机的灵玉" },
    tianming_mount   = { name = "照夜玉狮子",  slot = "mount",     quality = 5, setId = "tianming",
                         baseAttr = { speed = 50, dodge = 0.04 },
                         desc = "赵子龙坐骑，白如凝脂" },

    ------------------------------------------------
    -- 神兵套 (shenbing) — 暴击型
    ------------------------------------------------
    shenbing_blade   = { name = "七星刀",      slot = "weapon",    quality = 5, setId = "shenbing",
                         baseAttr = { tong = 90, yong = 90, crit = 0.08 },
                         desc = "暗藏杀机的七星宝刀" },
    shenbing_helmet  = { name = "虎贲盔",      slot = "helmet",    quality = 5, setId = "shenbing",
                         baseAttr = { def = 55, crit = 0.05 },
                         desc = "虎贲勇士的锋锐头盔" },
    shenbing_armor   = { name = "锁子甲",      slot = "armor",     quality = 5, setId = "shenbing",
                         baseAttr = { def = 70, hp = 900, crit = 0.03 },
                         desc = "精钢链环编织的轻甲" },
    shenbing_boots   = { name = "闪电靴",      slot = "boots",     quality = 5, setId = "shenbing",
                         baseAttr = { speed = 30, crit = 0.04 },
                         desc = "迅雷不及掩耳" },
    shenbing_acc     = { name = "破军符",      slot = "accessory", quality = 5, setId = "shenbing",
                         baseAttr = { atk = 60, crit = 0.06 },
                         desc = "杀伐果断的军符" },
    shenbing_mount   = { name = "绝影",        slot = "mount",     quality = 5, setId = "shenbing",
                         baseAttr = { speed = 40, crit = 0.04, hp = 500 },
                         desc = "曹操坐骑，奔逸绝影" },

    ------------------------------------------------
    -- 散件（无套装, 各品质覆盖）
    ------------------------------------------------
    -- 白色基础
    iron_sword       = { name = "铁剑",        slot = "weapon",    quality = 1,
                         baseAttr = { tong = 15, yong = 10 } },
    iron_helmet      = { name = "铁盔",        slot = "helmet",    quality = 1,
                         baseAttr = { def = 8, hp = 100 } },
    iron_armor       = { name = "铁甲",        slot = "armor",     quality = 1,
                         baseAttr = { def = 12, hp = 150 } },
    cloth_boots      = { name = "布靴",        slot = "boots",     quality = 1,
                         baseAttr = { speed = 5 } },
    wooden_charm     = { name = "木符",        slot = "accessory", quality = 1,
                         baseAttr = { hp = 80 } },
    farm_horse       = { name = "驽马",        slot = "mount",     quality = 1,
                         baseAttr = { speed = 8 } },

    -- 绿色
    fine_sword       = { name = "精铁剑",      slot = "weapon",    quality = 2,
                         baseAttr = { tong = 30, yong = 20 } },
    fine_helmet      = { name = "精铁盔",      slot = "helmet",    quality = 2,
                         baseAttr = { def = 16, hp = 200 } },
    fine_armor       = { name = "皮甲",        slot = "armor",     quality = 2,
                         baseAttr = { def = 24, hp = 300 } },
    leather_boots    = { name = "皮靴",        slot = "boots",     quality = 2,
                         baseAttr = { speed = 10, dodge = 0.01 } },
    jade_charm       = { name = "玉符",        slot = "accessory", quality = 2,
                         baseAttr = { hp = 160, zhi = 10 } },
    war_horse        = { name = "战马",        slot = "mount",     quality = 2,
                         baseAttr = { speed = 15, hp = 150 } },

    -- 蓝色
    steel_blade      = { name = "百炼钢刀",    slot = "weapon",    quality = 3,
                         baseAttr = { tong = 55, yong = 35 } },
    steel_helmet     = { name = "百炼盔",      slot = "helmet",    quality = 3,
                         baseAttr = { def = 30, hp = 400 } },
    steel_armor      = { name = "鱼鳞甲",      slot = "armor",     quality = 3,
                         baseAttr = { def = 45, hp = 550 } },
    wind_boots       = { name = "疾风靴",      slot = "boots",     quality = 3,
                         baseAttr = { speed = 18, dodge = 0.02 } },
    silver_charm     = { name = "银符",        slot = "accessory", quality = 3,
                         baseAttr = { hp = 300, zhi = 25 } },
    swift_horse      = { name = "良驹",        slot = "mount",     quality = 3,
                         baseAttr = { speed = 22, hp = 300 } },

    -- 紫色
    purple_blade     = { name = "玄铁刀",      slot = "weapon",    quality = 4,
                         baseAttr = { tong = 80, yong = 55 } },
    purple_helmet    = { name = "虎头盔",      slot = "helmet",    quality = 4,
                         baseAttr = { def = 50, hp = 650 } },
    purple_armor     = { name = "明光铠",      slot = "armor",     quality = 4,
                         baseAttr = { def = 70, hp = 850 } },
    purple_boots     = { name = "云步靴",      slot = "boots",     quality = 4,
                         baseAttr = { speed = 25, dodge = 0.03 } },
    purple_charm     = { name = "金符",        slot = "accessory", quality = 4,
                         baseAttr = { hp = 500, zhi = 40 } },
    purple_mount     = { name = "汗血宝马",    slot = "mount",     quality = 4,
                         baseAttr = { speed = 30, hp = 500 } },

    -- 金色独件
    gold_blade       = { name = "干将莫邪",    slot = "weapon",    quality = 6,
                         baseAttr = { tong = 160, yong = 110, crit = 0.06 },
                         desc = "雌雄双剑，削铁如泥" },
    gold_armor       = { name = "凤凰甲",      slot = "armor",     quality = 6,
                         baseAttr = { def = 140, hp = 1800, dodge = 0.04 },
                         desc = "浴火重生的凤凰之甲" },
}

------------------------------------------------------------
-- 3. 套装效果定义
------------------------------------------------------------

---@class SetBonus
---@field name string 套装名称
---@field pieces table<number, table> {count -> effect}

M.SETS = {
    wusheng = {
        name = "武圣套",
        [2] = { desc = "攻击+15%",       type = "atk_pct",      value = 0.15 },
        [4] = { desc = "暴击+10%",       type = "crit",         value = 0.10 },
        [6] = { desc = "普攻双击概率20%", type = "double_strike", value = 0.20 },
    },
    wolong = {
        name = "卧龙套",
        [2] = { desc = "智力+15%",       type = "zhi_pct",       value = 0.15 },
        [4] = { desc = "战法伤害+20%",   type = "skill_dmg_pct", value = 0.20 },
        [6] = { desc = "战法冷却-1回合",  type = "skill_cd_reduce", value = 1 },
    },
    bawang = {
        name = "霸王套",
        [2] = { desc = "生命+20%",       type = "hp_pct",        value = 0.20 },
        [4] = { desc = "防御+15%",       type = "def_pct",       value = 0.15 },
        [6] = { desc = "受伤反弹10%",    type = "dmg_reflect",   value = 0.10 },
    },
    tianming = {
        name = "天命套",
        [2] = { desc = "速度+15%",       type = "speed_pct",     value = 0.15 },
        [4] = { desc = "闪避+10%",       type = "dodge",         value = 0.10 },
        [6] = { desc = "首回合免疫控制",  type = "cc_immune_r1",  value = 1 },
    },
    shenbing = {
        name = "神兵套",
        [2] = { desc = "攻击+10%",       type = "atk_pct",       value = 0.10 },
        [4] = { desc = "暴击伤害+25%",   type = "crit_dmg",      value = 0.25 },
        [6] = { desc = "击杀回血15%",    type = "kill_heal",     value = 0.15 },
    },
}

------------------------------------------------------------
-- 4. 强化规则
------------------------------------------------------------

--- 强化消耗和成功率
---@param level number 当前强化等级(将要升到 level+1)
---@return number cost   铜币消耗
---@return number rate   成功率 0-1
---@return number downgrade 失败降级数
function M.GetEnhanceCost(level)
    if level < 10 then
        return (level + 1) * 1000, 1.0, 0
    elseif level < 20 then
        return (level + 1) * 2000, 0.80, 0
    elseif level < 30 then
        return (level + 1) * 5000, 0.60, 1
    else
        return (level + 1) * 10000, 0.40, 2
    end
end

--- 强化上限 = 英雄等级 × 2
function M.GetEnhanceMaxLevel(heroLevel)
    return heroLevel * 2
end

------------------------------------------------------------
-- 5. 精炼规则
------------------------------------------------------------

M.MAX_REFINE = 5
--- 每级精炼加成 = 基础属性 × 5%
M.REFINE_BONUS_PER_LEVEL = 0.05

------------------------------------------------------------
-- 6. 副属性（洗练）
------------------------------------------------------------

--- 副属性池，按品质范围
M.SUB_ATTR_POOLS = {
    -- 品质 4 (紫)
    [4] = {
        { attr = "hp",    min = 200,  max = 500  },
        { attr = "atk",   min = 10,   max = 30   },
        { attr = "def",   min = 10,   max = 25   },
        { attr = "crit",  min = 0.02, max = 0.05 },
        { attr = "dodge", min = 0.02, max = 0.05 },
        { attr = "speed", min = 5,    max = 15   },
    },
    -- 品质 5 (橙)
    [5] = {
        { attr = "hp",    min = 400,  max = 800  },
        { attr = "atk",   min = 20,   max = 50   },
        { attr = "def",   min = 15,   max = 40   },
        { attr = "crit",  min = 0.03, max = 0.08 },
        { attr = "dodge", min = 0.03, max = 0.07 },
        { attr = "speed", min = 10,   max = 25   },
    },
    -- 品质 6 (金)
    [6] = {
        { attr = "hp",    min = 600,  max = 1200 },
        { attr = "atk",   min = 30,   max = 80   },
        { attr = "def",   min = 25,   max = 60   },
        { attr = "crit",  min = 0.05, max = 0.12 },
        { attr = "dodge", min = 0.04, max = 0.10 },
        { attr = "speed", min = 15,   max = 40   },
    },
}

--- 副属性条数
M.SUB_ATTR_COUNTS = {
    [4] = { init = 1, max = 2 },  -- 紫
    [5] = { init = 2, max = 3 },  -- 橙
    [6] = { init = 2, max = 4 },  -- 金
}

--- 洗练锁定费用(元宝)
M.REFORGE_LOCK_COST = 50

------------------------------------------------------------
-- 7. 属性计算
------------------------------------------------------------

--- 计算装备最终属性
---@param equipInstance table { templateId, level, refineLevel, subAttrs }
---@return table attrs  最终属性 { tong=x, yong=y, ... }
function M.CalcEquipAttrs(equipInstance)
    if not equipInstance or not equipInstance.templateId then return {} end
    local tmpl = M.TEMPLATES[equipInstance.templateId]
    if not tmpl then return {} end

    local attrs = {}
    local level = equipInstance.level or 0
    local refine = equipInstance.refineLevel or 0

    -- 基础属性 × (1 + 强化等级 × 0.1) + 精炼加成
    for attr, base in pairs(tmpl.baseAttr) do
        local enhanced = base * (1 + level * 0.1)
        local refined  = base * refine * M.REFINE_BONUS_PER_LEVEL
        attrs[attr] = enhanced + refined
    end

    -- 副属性叠加
    if equipInstance.subAttrs then
        for _, sub in ipairs(equipInstance.subAttrs) do
            attrs[sub.attr] = (attrs[sub.attr] or 0) + sub.value
        end
    end

    return attrs
end

--- 计算英雄所有装备总属性
---@param equips table { weapon={...}, helmet={...}, ... }
---@return table totalAttrs
---@return table setCount  { setId = count }
function M.CalcAllEquipAttrs(equips)
    if not equips then return {}, {} end
    local total = {}
    local setCount = {}

    for _, slot in ipairs(M.SLOTS) do
        local inst = equips[slot]
        if inst and inst.templateId then
            local attrs = M.CalcEquipAttrs(inst)
            for attr, val in pairs(attrs) do
                total[attr] = (total[attr] or 0) + val
            end
            -- 统计套装件数
            local tmpl = M.TEMPLATES[inst.templateId]
            if tmpl and tmpl.setId then
                setCount[tmpl.setId] = (setCount[tmpl.setId] or 0) + 1
            end
        end
    end

    return total, setCount
end

--- 获取已激活的套装效果列表
---@param setCount table { setId = count }
---@return table[] effects  { {setName, pieces, desc, type, value}, ... }
function M.GetActiveSetBonuses(setCount)
    local effects = {}
    for setId, count in pairs(setCount) do
        local setDef = M.SETS[setId]
        if setDef then
            local thresholds = { 2, 4, 6 }
            for _, t in ipairs(thresholds) do
                if count >= t and setDef[t] then
                    effects[#effects + 1] = {
                        setName = setDef.name,
                        pieces  = t,
                        desc    = setDef[t].desc,
                        type    = setDef[t].type,
                        value   = setDef[t].value,
                    }
                end
            end
        end
    end
    return effects
end

------------------------------------------------------------
-- 8. 装备生成（服务端用：关卡掉落/打造）
------------------------------------------------------------

--- 按品质范围随机生成一件装备实例
---@param minQuality number 最低品质
---@param maxQuality number 最高品质
---@param slot string|nil   指定槽位(可选)
---@return table|nil equipInstance
function M.GenerateEquip(minQuality, maxQuality, slot)
    -- 收集符合条件的模板
    local pool = {}
    for id, tmpl in pairs(M.TEMPLATES) do
        if tmpl.quality >= minQuality and tmpl.quality <= maxQuality then
            if not slot or tmpl.slot == slot then
                pool[#pool + 1] = { id = id, tmpl = tmpl }
            end
        end
    end
    if #pool == 0 then return nil end

    local pick = pool[math.random(1, #pool)]
    local inst = {
        templateId  = pick.id,
        level       = 0,
        refineLevel = 0,
        subAttrs    = {},
        locked      = {},
    }

    -- 根据品质生成初始副属性
    local subCfg = M.SUB_ATTR_COUNTS[pick.tmpl.quality]
    if subCfg then
        local subPool = M.SUB_ATTR_POOLS[pick.tmpl.quality]
        if subPool then
            inst.subAttrs = M.RollSubAttrs(subPool, subCfg.init)
        end
    end

    return inst
end

--- 随机副属性
---@param pool table[] 副属性池
---@param count number 生成条数
---@return table[]
function M.RollSubAttrs(pool, count)
    local result = {}
    local used = {}
    for i = 1, count do
        -- 防止重复属性
        local candidates = {}
        for _, p in ipairs(pool) do
            if not used[p.attr] then
                candidates[#candidates + 1] = p
            end
        end
        if #candidates == 0 then break end
        local pick = candidates[math.random(1, #candidates)]
        used[pick.attr] = true
        local value
        if pick.max <= 1 then
            -- 百分比属性
            value = pick.min + math.random() * (pick.max - pick.min)
            value = math.floor(value * 1000 + 0.5) / 1000  -- 3位精度
        else
            value = math.random(math.floor(pick.min), math.floor(pick.max))
        end
        result[#result + 1] = { attr = pick.attr, value = value }
    end
    return result
end

--- 按品质获取掉落概率表（关卡掉落用）
---@param nodeType string "normal"|"elite"|"boss"
---@return number minQ, number maxQ, number dropRate
function M.GetDropParams(nodeType)
    if nodeType == "boss" then
        return 4, 5, 0.80       -- 紫-橙, 80%掉落率
    elseif nodeType == "elite" then
        return 3, 4, 0.50       -- 蓝-紫, 50%
    else
        return 1, 3, 0.25       -- 白-蓝, 25%
    end
end

------------------------------------------------------------
-- 9. 格式化辅助（UI 展示用）
------------------------------------------------------------

--- 格式化属性值为展示字符串
---@param attr string  属性key
---@param value number 属性值
---@return string
function M.FormatAttrValue(attr, value)
    if attr == "crit" or attr == "dodge" then
        return string.format("+%.1f%%", value * 100)
    elseif attr == "hp" then
        return string.format("+%d", math.floor(value))
    else
        return string.format("+%d", math.floor(value))
    end
end

--- 获取属性中文名
---@param attr string
---@return string
function M.GetAttrName(attr)
    return M.ATTR_NAMES[attr] or attr
end

return M
