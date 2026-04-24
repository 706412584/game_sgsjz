-- ============================================================================
-- 掉落逻辑模块（阶段二.五 下一计划起步）
-- 职责：提供纯函数式掉落计算，不直接修改玩家数据
-- ============================================================================

local DataItems = require("data_items")

local M = {}

local DROP_CHANCE_BY_TIER = {
    [1] = 0.00, [2] = 0.00,
    [3] = 0.06, [4] = 0.06,
    [5] = 0.10, [6] = 0.10,
    [7] = 0.14, [8] = 0.14,
    [9] = 0.18, [10] = 0.18,
}

local ALLOWED_QUALITY_BY_TIER = {
    [1] = { common = true },
    [2] = { common = true, uncommon = true },
    [3] = { common = true, uncommon = true },
    [4] = { common = true, uncommon = true, rare = true },
    [5] = { common = true, uncommon = true, rare = true },
    [6] = { common = true, uncommon = true, rare = true },
    [7] = { common = true, uncommon = true, rare = true, epic = true },
    [8] = { common = true, uncommon = true, rare = true, epic = true },
    [9] = { common = true, uncommon = true, rare = true, epic = true },
    [10] = { common = true, uncommon = true, rare = true, epic = true },
}

local function clampTier(tier)
    local t = math.floor(tonumber(tier) or 1)
    if t < 1 then return 1 end
    if t > 10 then return 10 end
    return t
end

local function hasArtifact(artifacts, name)
    for _, a in ipairs(artifacts or {}) do
        if a.name == name then return true end
    end
    return false
end

local function pickWeighted(list)
    local total = 0
    for _, item in ipairs(list) do
        total = total + (item.weight or 1)
    end
    if total <= 0 then return nil end
    local r = math.random(1, total)
    local acc = 0
    for _, item in ipairs(list) do
        acc = acc + (item.weight or 1)
        if r <= acc then return item end
    end
    return list[#list]
end

function M.RollArtifactDrop(tier, existingArtifacts)
    local t = clampTier(tier)
    local chance = DROP_CHANCE_BY_TIER[t] or 0
    if chance <= 0 or math.random() > chance then
        return nil, nil
    end

    local gate = ALLOWED_QUALITY_BY_TIER[t] or ALLOWED_QUALITY_BY_TIER[1]
    local candidates = {}
    for _, def in ipairs(DataItems.ARTIFACTS or {}) do
        local quality = def.quality or "common"
        if gate[quality] and not hasArtifact(existingArtifacts, def.name) then
            local q = DataItems.QUALITY[quality]
            candidates[#candidates + 1] = {
                def = def,
                weight = q and q.weight or 1,
            }
        end
    end
    if #candidates == 0 then return nil, nil end

    local picked = pickWeighted(candidates)
    if not picked or not picked.def then return nil, nil end
    local def = picked.def
    return {
        id = def.id,
        name = def.name,
        quality = def.quality or "common",
        slot = def.slot or "weapon",
        effect = def.effect or "",
        level = 1,
        maxLevel = 10,
        equipped = false,
    }, def
end

return M
