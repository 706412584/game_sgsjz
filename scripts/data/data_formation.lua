------------------------------------------------------------
-- data/data_formation.lua  —— 三国神将录 阵法数据
-- 定义所有阵法及其战斗加成效果
-- 阵法影响: 全队战斗属性、前排/后排专属效果
------------------------------------------------------------

local M = {}

------------------------------------------------------------
-- 阵法数据库
-- 每个阵法:
--   id          阵法ID(唯一)
--   name        中文名
--   desc        简要描述
--   detail      详细战斗效果说明
--   unlock      解锁条件: { type, value }
--   frontSlots  前排槽位数
--   backSlots   后排槽位数
--   buffs       战斗加成 { attr = value, ... }
--               属性: tong/yong/zhi/hp/def/crit/dodge/morale_init
--               百分比: tong_pct/yong_pct/zhi_pct/hp_pct/atk_pct/def_pct
--               特殊: front_def_pct / back_atk_pct (前排/后排独立加成)
--   setRequire  阵法共鸣: { faction, count, bonus }
--               同阵营角色达到 count 个时额外激活 bonus
------------------------------------------------------------

M.FORMATIONS = {
    -- ============================================================
    -- 基础阵法 (初始解锁)
    -- ============================================================
    {
        id         = "feng_shi",
        name       = "锋矢阵",
        desc       = "攻守兼备的基础阵法",
        detail     = "全队统率+5%, 勇武+5%",
        unlock     = { type = "default" },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            tong_pct = 0.05,
            yong_pct = 0.05,
        },
    },

    -- ============================================================
    -- 进阶阵法 (通关地图解锁)
    -- ============================================================
    {
        id         = "he_yi",
        name       = "鹤翼阵",
        desc       = "后排输出大幅提升",
        detail     = "后排攻击+15%, 全队智力+8%",
        unlock     = { type = "map", value = 5 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            back_atk_pct = 0.15,
            zhi_pct      = 0.08,
        },
    },
    {
        id         = "yu_lin",
        name       = "鱼鳞阵",
        desc       = "前排坚不可摧",
        detail     = "前排防御+20%, 全队兵力+10%",
        unlock     = { type = "map", value = 10 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            front_def_pct = 0.20,
            hp_pct        = 0.10,
        },
    },
    {
        id         = "chang_she",
        name       = "长蛇阵",
        desc       = "速攻先手，首轮士气高涨",
        detail     = "全队初始士气+30, 暴击+5%",
        unlock     = { type = "map", value = 15 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            morale_init = 30,
            crit        = 0.05,
        },
    },
    {
        id         = "yan_xing",
        name       = "雁行阵",
        desc       = "远程法师阵法，智力大幅提升",
        detail     = "全队智力+15%, 后排攻击+10%",
        unlock     = { type = "map", value = 20 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            zhi_pct      = 0.15,
            back_atk_pct = 0.10,
        },
    },
    {
        id         = "fang_yuan",
        name       = "方圆阵",
        desc       = "铁壁防御，削减敌方士气",
        detail     = "全队防御+12%, 兵力+8%, 闪避+3%",
        unlock     = { type = "map", value = 30 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            def_pct = 0.12,
            hp_pct  = 0.08,
            dodge   = 0.03,
        },
    },
    {
        id         = "tian_fu",
        name       = "天覆阵",
        desc       = "诸葛亮所创，攻防一体",
        detail     = "全队三围+10%, 暴击+3%",
        unlock     = { type = "map", value = 40 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            tong_pct = 0.10,
            yong_pct = 0.10,
            zhi_pct  = 0.10,
            crit     = 0.03,
        },
    },
    {
        id         = "di_zai",
        name       = "地载阵",
        desc       = "厚积薄发，续航持久",
        detail     = "全队兵力+18%, 防御+8%, 初始士气+15",
        unlock     = { type = "map", value = 50 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            hp_pct      = 0.18,
            def_pct     = 0.08,
            morale_init = 15,
        },
    },
    {
        id         = "feng_hou",
        name       = "风后阵",
        desc       = "极致爆发，一击必杀",
        detail     = "全队攻击+18%, 暴击+8%, 闪避+3%",
        unlock     = { type = "map", value = 60 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            atk_pct = 0.18,
            crit    = 0.08,
            dodge   = 0.03,
        },
    },
    {
        id         = "ba_zhen",
        name       = "八阵图",
        desc       = "传说中的至尊阵法",
        detail     = "全队三围+12%, 兵力+12%, 暴击+5%, 初始士气+20",
        unlock     = { type = "map", value = 80 },
        frontSlots = 2,
        backSlots  = 3,
        buffs      = {
            tong_pct    = 0.12,
            yong_pct    = 0.12,
            zhi_pct     = 0.12,
            hp_pct      = 0.12,
            crit        = 0.05,
            morale_init = 20,
        },
    },
}

------------------------------------------------------------
-- 索引表
------------------------------------------------------------
M.BY_ID = {}
for _, f in ipairs(M.FORMATIONS) do
    M.BY_ID[f.id] = f
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 获取阵法数据
---@param formationId string
---@return table|nil
function M.Get(formationId)
    return M.BY_ID[formationId]
end

--- 获取默认阵法ID
---@return string
function M.GetDefault()
    return "feng_shi"
end

--- 检查阵法是否已解锁
---@param formationId string
---@param gameState table
---@return boolean
function M.IsUnlocked(formationId, gameState)
    local f = M.BY_ID[formationId]
    if not f then return false end
    if f.unlock.type == "default" then return true end
    if f.unlock.type == "map" then
        -- 检查已通关地图数
        local cleared = 0
        if gameState.clearedMaps then
            for _ in pairs(gameState.clearedMaps) do
                cleared = cleared + 1
            end
        end
        return cleared >= f.unlock.value
    end
    return false
end

--- 获取所有阵法列表(带解锁状态)
---@param gameState table
---@return table[] { id, name, desc, detail, unlocked, buffs, unlock }
function M.GetAllWithStatus(gameState)
    local result = {}
    for _, f in ipairs(M.FORMATIONS) do
        result[#result + 1] = {
            id       = f.id,
            name     = f.name,
            desc     = f.desc,
            detail   = f.detail,
            unlocked = M.IsUnlocked(f.id, gameState),
            buffs    = f.buffs,
            unlock   = f.unlock,
        }
    end
    return result
end

--- 获取阵法战斗加成(用于战斗引擎)
---@param formationId string
---@return table buffs
function M.GetBuffs(formationId)
    local f = M.BY_ID[formationId]
    if not f then return {} end
    return f.buffs or {}
end

--- 格式化buff属性名
---@param attr string
---@return string
function M.GetBuffName(attr)
    local names = {
        tong_pct      = "统率",
        yong_pct      = "勇武",
        zhi_pct       = "智力",
        hp_pct        = "兵力",
        atk_pct       = "攻击",
        def_pct       = "防御",
        crit          = "暴击率",
        dodge         = "闪避率",
        morale_init   = "初始士气",
        front_def_pct = "前排防御",
        back_atk_pct  = "后排攻击",
    }
    return names[attr] or attr
end

--- 格式化buff数值
---@param attr string
---@param value number
---@return string
function M.FormatBuff(attr, value)
    if attr == "morale_init" then
        return "+" .. math.floor(value)
    end
    return "+" .. math.floor(value * 100) .. "%"
end

return M
