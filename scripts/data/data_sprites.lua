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
-- 通用兵种精灵 (cavalry/chariot/strategist)
-- 用于无 heroId 的敌方小兵，按名字关键词匹配
------------------------------------------------------------
local SOLDIER_KEYWORDS = {
    -- 骑兵类
    { keywords = { "骑" }, sprite = "cavalry" },
    -- 战车/力士/重甲类
    { keywords = { "车", "力士", "重甲", "铁甲" }, sprite = "chariot" },
    -- 谋士/术士/祭司类
    { keywords = { "谋", "术", "祭", "法", "巫" }, sprite = "strategist" },
    -- 弓手类 → 用 strategist 做兜底 (远程形象)
    { keywords = { "弓", "弩", "射" }, sprite = "strategist" },
}

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 获取单位 idle 精灵贴图路径
---@param heroId string|nil
---@param unitName string|nil  用于小兵名字匹配
---@return string|nil
function M.GetIdle(heroId, unitName)
    if heroId and heroSpriteSet[heroId] then
        return UNIT_DIR .. "unit_" .. heroId .. "_idle.png"
    end
    -- 尝试按名字匹配通用兵种
    if unitName then
        for _, rule in ipairs(SOLDIER_KEYWORDS) do
            for _, kw in ipairs(rule.keywords) do
                if string.find(unitName, kw) then
                    return UNIT_DIR .. "unit_" .. rule.sprite .. "_idle.png"
                end
            end
        end
    end
    return nil
end

--- 获取单位 atk 精灵贴图路径
---@param heroId string|nil
---@param unitName string|nil
---@return string|nil
function M.GetAtk(heroId, unitName)
    if heroId and heroSpriteSet[heroId] then
        return UNIT_DIR .. "unit_" .. heroId .. "_atk.png"
    end
    if unitName then
        for _, rule in ipairs(SOLDIER_KEYWORDS) do
            for _, kw in ipairs(rule.keywords) do
                if string.find(unitName, kw) then
                    return UNIT_DIR .. "unit_" .. rule.sprite .. "_atk.png"
                end
            end
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
