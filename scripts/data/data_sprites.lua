---@meta
------------------------------------------------------------
-- data/data_sprites.lua  —— 战斗单位精灵图路径映射
-- 提供 heroId → idle/atk 精灵贴图路径的查询
-- 对敌方小兵(无 heroId)按名字关键词做模糊匹配
------------------------------------------------------------

local M = {}

------------------------------------------------------------
-- 精灵图目录 (assets/Textures/units/)
-- 命名规范: unit_{id}_idle.png / unit_{id}_atk.png
------------------------------------------------------------
local UNIT_DIR = "Textures/units/"

--- 有完整精灵图的 heroId 列表
local HERO_SPRITES = {
    "caocao", "xiaohoudun", "zhangliao", "guojia", "simayi", "zhenji",
    "liubei", "guanyu", "zhangfei", "zhaoyun", "zhugeliang", "pangtong",
    "huangyueying", "machao", "huangzhong",
    "sunquan", "sunce", "zhouyu", "luxun", "ganning", "taishici",
    "daqiao", "xiaoqiao", "sunshangxiang",
    "lvbu", "diaochan", "huatuo", "dongzhuo", "yuanshao", "zuoci", "caiwenji",
}

-- 快速查找表
local heroSpriteSet = {}
for _, id in ipairs(HERO_SPRITES) do
    heroSpriteSet[id] = true
end

------------------------------------------------------------
-- 通用兵种精灵映射
-- 分两层匹配: 1)阵营(颜色) 2)武器类型(精灵)
-- 精灵文件: unit_soldier_{faction}_{idle|atk}[_left].png
--           unit_soldier_archer_{color}_{idle|atk}[_left].png
--           unit_soldier_shield_{idle|atk}[_left].png
--           unit_cavalry_{idle|atk}[_left].png (已有)
--           unit_chariot_{idle|atk}[_left].png (已有)
--           unit_strategist_{idle|atk}[_left].png (已有)
------------------------------------------------------------

--- 阵营 → 步兵精灵名 / 弓手精灵名
local FACTION_SPRITES = {
    { keywords = { "黄巾" },           infantry = "soldier_huangjin",  archer = "soldier_archer_yellow" },
    { keywords = { "西凉" },           infantry = "soldier_xiliang",   archer = "soldier_archer_red" },
    { keywords = { "河北" },           infantry = "soldier_hebei",     archer = "soldier_archer_blue" },
    { keywords = { "魏国", "虎豹", "青州" }, infantry = "soldier_wei",      archer = "soldier_archer_blue" },
    { keywords = { "江东", "水军" },   infantry = "soldier_wu",        archer = "soldier_archer_red" },
    { keywords = { "蜀国", "白耳", "西川" }, infantry = "soldier_shu",      archer = "soldier_archer_green" },
    { keywords = { "魔", "神罚", "天机", "幻术" }, infantry = "soldier_shenmo",   archer = "soldier_archer_purple" },
}

--- 武器类型 → 精灵类型
local WEAPON_TYPE = {
    { keywords = { "骑" },                          spriteType = "cavalry" },   -- 已有通用骑兵
    { keywords = { "弓", "弩", "射", "火弩" },      spriteType = "archer" },    -- 弓手
    { keywords = { "盾", "重盾" },                  spriteType = "shield" },    -- 盾兵
    { keywords = { "谋", "术", "祭", "法", "巫", "军师", "方士" }, spriteType = "strategist" }, -- 谋士
    { keywords = { "车", "力士", "重甲", "铁甲" },  spriteType = "chariot" },   -- 战车/重步
}

--- 根据单位名查找匹配的精灵名
---@param unitName string
---@return string|nil spriteName  完整精灵基础名(不含 idle/atk/方向)
local function matchSoldierSprite(unitName)
    -- 先识别武器类型
    local weaponType = nil
    for _, rule in ipairs(WEAPON_TYPE) do
        for _, kw in ipairs(rule.keywords) do
            if string.find(unitName, kw) then
                weaponType = rule.spriteType
                break
            end
        end
        if weaponType then break end
    end

    -- 识别阵营
    local faction = nil
    for _, rule in ipairs(FACTION_SPRITES) do
        for _, kw in ipairs(rule.keywords) do
            if string.find(unitName, kw) then
                faction = rule
                break
            end
        end
        if faction then break end
    end

    -- 根据武器类型 + 阵营决定精灵
    if weaponType == "cavalry" then
        return "cavalry"                    -- 通用骑兵精灵
    elseif weaponType == "chariot" then
        return "chariot"                    -- 通用战车精灵
    elseif weaponType == "strategist" then
        return "strategist"                 -- 通用谋士精灵
    elseif weaponType == "archer" then
        if faction then
            return faction.archer           -- 阵营弓手
        end
        return "soldier_archer_blue"        -- 默认蓝色弓手
    elseif weaponType == "shield" then
        return "soldier_shield"             -- 盾兵
    else
        -- 刀兵/枪兵/死士/近卫等步兵 → 阵营步兵
        if faction then
            return faction.infantry
        end
        return "soldier_wei"                -- 默认深蓝步兵
    end
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 根据阵营决定后缀: ally 朝右(默认), enemy 朝左(_left)
local function suffix(side)
    return side == "enemy" and "_left" or ""
end

--- 获取单位 idle 精灵贴图路径
---@param heroId string|nil
---@param unitName string|nil  用于小兵名字匹配
---@param side string|nil      "ally"|"enemy", 默认 "ally"(朝右)
---@return string|nil
function M.GetIdle(heroId, unitName, side)
    local sfx = suffix(side)
    if heroId and heroSpriteSet[heroId] then
        return UNIT_DIR .. "unit_" .. heroId .. "_idle" .. sfx .. ".png"
    end
    -- 按阵营+武器双层匹配
    if unitName then
        local sprite = matchSoldierSprite(unitName)
        if sprite then
            return UNIT_DIR .. "unit_" .. sprite .. "_idle" .. sfx .. ".png"
        end
    end
    return nil
end

--- 获取单位 atk 精灵贴图路径
---@param heroId string|nil
---@param unitName string|nil
---@param side string|nil      "ally"|"enemy", 默认 "ally"(朝右)
---@return string|nil
function M.GetAtk(heroId, unitName, side)
    local sfx = suffix(side)
    if heroId and heroSpriteSet[heroId] then
        return UNIT_DIR .. "unit_" .. heroId .. "_atk" .. sfx .. ".png"
    end
    if unitName then
        local sprite = matchSoldierSprite(unitName)
        if sprite then
            return UNIT_DIR .. "unit_" .. sprite .. "_atk" .. sfx .. ".png"
        end
    end
    return nil
end

--- 检查 heroId 是否有精灵图
---@param heroId string
---@return boolean
function M.HasSprite(heroId)
    return heroSpriteSet[heroId] == true
end

return M
