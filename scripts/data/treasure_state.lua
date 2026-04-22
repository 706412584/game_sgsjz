------------------------------------------------------------
-- data/treasure_state.lua  —— 宝物系统状态操作
-- 穿戴/卸下/升级/合成/掉落，服务端调用
------------------------------------------------------------
local DT = require("data.data_treasure")

local M = {}

------------------------------------------------------------
-- 内部工具
------------------------------------------------------------

--- 确保英雄宝物槽位存在
---@param heroState table
local function ensureTreasureSlots(heroState)
    if not heroState.treasures then heroState.treasures = {} end
    if not heroState.exclusive then heroState.exclusive = nil end
end

--- 确保背包及材料字段存在
---@param state table
local function ensureBag(state)
    state.treasureBag = state.treasureBag or {}
    state.inventory = state.inventory or {}
    state.inventory.treasure_essence = state.inventory.treasure_essence or 0
    state.inventory.treasure_shards = state.inventory.treasure_shards or 0
    state.inventory.exclusive_shards = state.inventory.exclusive_shards or 0
end

------------------------------------------------------------
-- 穿戴 / 卸下（公共宝物）
------------------------------------------------------------

--- 从背包穿戴公共宝物到英雄槽位
---@param state table
---@param heroId string
---@param bagIndex number   背包索引 (1-based)
---@param slot number       目标槽位 (1 或 2)
---@return boolean, string
function M.Equip(state, heroId, bagIndex, slot)
    local hero = state.heroes[heroId]
    if not hero or hero.level <= 0 then return false, "英雄不存在" end
    if slot < 1 or slot > DT.PUBLIC_SLOTS then return false, "无效槽位" end

    ensureTreasureSlots(hero)
    ensureBag(state)

    local bag = state.treasureBag
    local inst = bag[bagIndex]
    if not inst then return false, "背包无此宝物" end

    local tmpl = DT.Get(inst.templateId)
    if not tmpl then return false, "宝物模板不存在" end
    if tmpl.type ~= "public" then return false, "专属宝物不可手动穿戴" end

    -- 目标槽位已有宝物 → 交换回背包
    local old = hero.treasures[slot]
    if old then
        bag[#bag + 1] = old
    end
    hero.treasures[slot] = inst
    table.remove(bag, bagIndex)

    return true, tmpl.name .. " 已装备"
end

--- 卸下公共宝物到背包
---@param state table
---@param heroId string
---@param slot number
---@return boolean, string
function M.Remove(state, heroId, slot)
    local hero = state.heroes[heroId]
    if not hero then return false, "英雄不存在" end

    ensureTreasureSlots(hero)
    ensureBag(state)

    local inst = hero.treasures[slot]
    if not inst then return false, "该槽位无宝物" end

    state.treasureBag[#state.treasureBag + 1] = inst
    hero.treasures[slot] = nil

    local tmpl = DT.Get(inst.templateId)
    return true, (tmpl and tmpl.name or "宝物") .. " 已卸下"
end

------------------------------------------------------------
-- 升级
------------------------------------------------------------

--- 升级公共宝物（已穿戴在英雄身上）
---@param state table
---@param heroId string
---@param slot number
---@return boolean, string
function M.UpgradePublic(state, heroId, slot)
    local hero = state.heroes[heroId]
    if not hero then return false, "英雄不存在" end

    ensureTreasureSlots(hero)
    ensureBag(state)

    local inst = hero.treasures[slot]
    if not inst then return false, "该槽位无宝物" end
    if (inst.level or 1) >= DT.MAX_LEVEL then return false, "已满级" end

    local curLv = inst.level or 1
    local cost = DT.GetUpgradeCost(curLv)
    if not cost then return false, "已满级" end

    if state.inventory.treasure_essence < cost.essence then
        return false, "宝物精华不足(需" .. cost.essence .. ")"
    end
    if state.copper < cost.copper then
        return false, "铜钱不足(需" .. cost.copper .. ")"
    end

    state.inventory.treasure_essence = state.inventory.treasure_essence - cost.essence
    state.copper = state.copper - cost.copper
    inst.level = curLv + 1

    local tmpl = DT.Get(inst.templateId)
    return true, (tmpl and tmpl.name or "宝物") .. " 升至 Lv." .. inst.level
end

--- 升级专属宝物
---@param state table
---@param heroId string
---@return boolean, string
function M.UpgradeExclusive(state, heroId)
    local hero = state.heroes[heroId]
    if not hero then return false, "英雄不存在" end

    ensureTreasureSlots(hero)
    ensureBag(state)

    local inst = hero.exclusive
    if not inst then return false, "无专属宝物" end
    if (inst.level or 1) >= DT.MAX_LEVEL then return false, "已满级" end

    local curLv = inst.level or 1
    local cost = DT.GetUpgradeCost(curLv)
    if not cost then return false, "已满级" end

    if state.inventory.treasure_essence < cost.essence then
        return false, "宝物精华不足(需" .. cost.essence .. ")"
    end
    if state.copper < cost.copper then
        return false, "铜钱不足(需" .. cost.copper .. ")"
    end

    state.inventory.treasure_essence = state.inventory.treasure_essence - cost.essence
    state.copper = state.copper - cost.copper
    inst.level = curLv + 1

    local tmpl = DT.Get(inst.templateId)
    return true, (tmpl and tmpl.name or "宝物") .. " 升至 Lv." .. inst.level
end

------------------------------------------------------------
-- 合成
------------------------------------------------------------

--- 合成公共宝物（碎片 → 新宝物实例，放入背包）
---@param state table
---@param templateId string
---@return boolean, string
function M.ComposePublic(state, templateId)
    local tmpl = DT.Get(templateId)
    if not tmpl then return false, "宝物不存在" end
    if tmpl.type ~= "public" then return false, "只能合成公共宝物" end

    ensureBag(state)

    local cost = tmpl.composeCost or 50
    if state.inventory.treasure_shards < cost then
        return false, "宝物碎片不足(需" .. cost .. ")"
    end

    state.inventory.treasure_shards = state.inventory.treasure_shards - cost
    state.treasureBag[#state.treasureBag + 1] = {
        templateId = templateId,
        level = 1,
    }
    return true, tmpl.name .. " 合成成功"
end

--- 合成专属宝物（专属碎片 → 直接绑定英雄）
---@param state table
---@param heroId string
---@return boolean, string
function M.ComposeExclusive(state, heroId)
    local hero = state.heroes[heroId]
    if not hero or hero.level <= 0 then return false, "英雄不存在" end

    ensureTreasureSlots(hero)
    ensureBag(state)

    if hero.exclusive then return false, "已拥有专属宝物" end

    local tmplId = DT.GetExclusiveFor(heroId)
    if not tmplId then return false, "该英雄无专属宝物" end

    local tmpl = DT.Get(tmplId)
    local cost = tmpl and tmpl.composeCost or 30
    if state.inventory.exclusive_shards < cost then
        return false, "专属碎片不足(需" .. cost .. ")"
    end

    state.inventory.exclusive_shards = state.inventory.exclusive_shards - cost
    hero.exclusive = {
        templateId = tmplId,
        level = 1,
    }
    return true, (tmpl and tmpl.name or "专属宝物") .. " 合成成功"
end

------------------------------------------------------------
-- 属性 / 战力计算
------------------------------------------------------------

--- 计算英雄全部宝物属性总和
---@param heroState table
---@return table {attr=value,...}
function M.CalcAllTreasureAttrs(heroState)
    local result = {}
    if not heroState then return result end

    -- 公共宝物
    if heroState.treasures then
        for slot = 1, DT.PUBLIC_SLOTS do
            local inst = heroState.treasures[slot]
            if inst then
                local attrs = DT.CalcAttrs(inst)
                for attr, val in pairs(attrs) do
                    result[attr] = (result[attr] or 0) + val
                end
            end
        end
    end

    -- 专属宝物
    if heroState.exclusive then
        local attrs = DT.CalcAttrs(heroState.exclusive)
        for attr, val in pairs(attrs) do
            result[attr] = (result[attr] or 0) + val
        end
    end

    return result
end

--- 计算英雄宝物战力贡献
---@param heroState table
---@return number
function M.CalcTreasurePower(heroState)
    local attrs = M.CalcAllTreasureAttrs(heroState)
    local power = 0
    -- 三围属性各 ×2 折算战力
    power = power + (attrs.tong or 0) * 2
    power = power + (attrs.yong or 0) * 2
    power = power + (attrs.zhi or 0) * 2
    -- 有专属宝物额外 +100 战力
    if heroState.exclusive then
        power = power + 100
    end
    return math.floor(power)
end

------------------------------------------------------------
-- 战斗掉落
------------------------------------------------------------

--- 战斗胜利后尝试掉落宝物材料
---@param state table
---@param nodeType string  "normal"|"elite"|"boss"
---@return table drops  { {name, count}, ... }
function M.TryDropMaterials(state, nodeType)
    ensureBag(state)

    local drops = {}
    local cfg = DT.DROP_CONFIG[nodeType]
    if not cfg then return drops end

    -- 宝物精华
    if cfg.essence and math.random() <= cfg.essence.rate then
        local count = math.random(cfg.essence.min, cfg.essence.max)
        state.inventory.treasure_essence = state.inventory.treasure_essence + count
        drops[#drops + 1] = { name = "宝物精华", count = count }
    end

    -- 宝物碎片
    if cfg.shards and math.random() <= cfg.shards.rate then
        local count = math.random(cfg.shards.min, cfg.shards.max)
        state.inventory.treasure_shards = state.inventory.treasure_shards + count
        drops[#drops + 1] = { name = "宝物碎片", count = count }
    end

    -- 专属碎片
    if cfg.exclusiveShards and math.random() <= cfg.exclusiveShards.rate then
        local count = math.random(cfg.exclusiveShards.min, cfg.exclusiveShards.max)
        state.inventory.exclusive_shards = state.inventory.exclusive_shards + count
        drops[#drops + 1] = { name = "专属碎片", count = count }
    end

    return drops
end

return M
