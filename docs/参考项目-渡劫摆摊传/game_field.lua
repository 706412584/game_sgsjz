-- ============================================================================
-- game_field.lua — 灵田系统（种植/收获/升级）
-- 使用 os.time() 时间戳，支持离线自动生长
-- ============================================================================
local Config = require("data_config")
local State = require("data_state")
---@type table
local GameCore  -- 延迟加载，避免与 game_core 循环依赖

local function getGameCore()
    if not GameCore then GameCore = require("game_core") end
    return GameCore
end

local M = {}

--- 获取当前田地可用地块数
---@return number
function M.GetMaxPlots()
    local lvl = State.state.fieldLevel
    if lvl > #Config.FieldLevels then lvl = #Config.FieldLevels end
    return Config.FieldLevels[lvl].plots
end

--- 获取田地升级费用（nil=已满级）
---@return number|nil
function M.GetUpgradeCost()
    local lvl = State.state.fieldLevel
    if lvl >= #Config.FieldLevels then return nil end
    return Config.FieldLevels[lvl + 1].cost
end

--- 获取田地升级所需境界（nil=无境界要求）
---@return number|nil realmIdx
---@return string|nil realmName
function M.GetUpgradeRealmReq()
    local lvl = State.state.fieldLevel
    if lvl >= #Config.FieldLevels then return nil, nil end
    local nextCfg = Config.FieldLevels[lvl + 1]
    if nextCfg.requiredRealm then
        return nextCfg.requiredRealm, Config.Realms[nextCfg.requiredRealm].name
    end
    return nil, nil
end

--- 升级田地
---@return boolean success
---@return string? reason
function M.UpgradeField()
    local cost = M.GetUpgradeCost()
    if not cost then return false, "已满级" end
    -- 检查境界要求
    local reqRealm, reqName = M.GetUpgradeRealmReq()
    if reqRealm and State.state.realmLevel < reqRealm then
        return false, "需达到" .. reqName .. "期"
    end
    if not State.SpendLingshi(cost) then return false, "灵石不足" end
    State.state.fieldLevel = State.state.fieldLevel + 1
    State.Emit("field_upgraded", State.state.fieldLevel)
    if State.serverMode then
        getGameCore().SendGameAction("field_upgrade")
    end
    return true
end

--- 获取作物配置
---@param cropId string
---@return table|nil
function M.GetCropById(cropId)
    for _, c in ipairs(Config.Crops) do
        if c.id == cropId then return c end
    end
    return nil
end

--- 种植作物
---@param plotIdx number 1-based
---@param cropId string
---@return boolean success
---@return string? reason
function M.Plant(plotIdx, cropId)
    if plotIdx < 1 or plotIdx > M.GetMaxPlots() then return false, "无效地块" end
    local existing = State.state.fieldPlots[plotIdx]
    print("[Field] Plant attempt: plotIdx=" .. plotIdx .. " cropId=" .. tostring(cropId)
        .. " existing=" .. tostring(existing)
        .. " existingCropId=" .. tostring(existing and existing.cropId)
        .. " fieldPlotsType=" .. type(State.state.fieldPlots))
    if existing and existing.cropId and existing.cropId ~= "" then return false, "该地块已种植" end
    local crop = M.GetCropById(cropId)
    if not crop then return false, "未知种子" end
    if not State.SpendLingshi(crop.cost) then return false, "灵石不足(需" .. crop.cost .. ")" end
    State.state.fieldPlots[plotIdx] = {
        cropId = cropId,
        plantTime = os.time(),
    }
    State.Emit("field_changed")
    if State.serverMode then
        getGameCore().SendGameAction("field_plant", { plotIdx = plotIdx, cropId = cropId })
    end
    return true
end

--- 获取灵童生长加速系数
---@return number speedBonus (0 = 无加速)
function M.GetServantSpeedBonus()
    local sv = State.state.fieldServant
    if not sv or sv.tier <= 0 then return 0 end
    if os.time() >= (sv.expireTime or 0) then return 0 end
    local servantCfg = Config.FieldServants[sv.tier]
    return servantCfg and servantCfg.abilities.speedBonus or 0
end

--- 获取地块生长进度 0~1
---@param plotIdx number
---@return number progress, number remainSec
function M.GetProgress(plotIdx)
    local plot = State.state.fieldPlots[plotIdx]
    if not plot or not plot.cropId then return 0, 0 end
    local crop = M.GetCropById(plot.cropId)
    if not crop then return 0, 0 end
    local speedBonus = M.GetServantSpeedBonus()
    local actualGrowTime = crop.growTime / (1 + speedBonus)
    local elapsed = os.time() - plot.plantTime
    local progress = math.min(1.0, elapsed / actualGrowTime)
    local remain = math.max(0, actualGrowTime - elapsed)
    return progress, remain
end

--- 是否可收获
---@param plotIdx number
---@return boolean
function M.CanHarvest(plotIdx)
    local progress, _ = M.GetProgress(plotIdx)
    return progress >= 1.0
end

--- 收获地块
---@param plotIdx number
---@return table|nil rewards  {materialId = amount, ...}
function M.Harvest(plotIdx)
    if not M.CanHarvest(plotIdx) then return nil end
    local plot = State.state.fieldPlots[plotIdx]
    local crop = M.GetCropById(plot.cropId)
    if not crop then return nil end
    -- 发放奖励（法宝/珍藏产量加成）
    local s = State.state
    local artBonus = 1.0 + Config.GetArtifactBonus(s.equippedArtifacts or {}, "material_rate")
    local rewards = {}
    for matId, amount in pairs(crop.yield) do
        local collBonus = 1.0 + Config.GetCollectibleBonus(s.collectibles or {}, "material_rate_" .. matId)
        local finalAmount = math.floor(amount * artBonus * collBonus)
        if finalAmount < 1 then finalAmount = 1 end
        State.AddMaterial(matId, finalAmount)
        rewards[matId] = finalAmount
    end
    -- 清空地块
    State.state.fieldPlots[plotIdx] = {}
    State.Emit("field_changed")
    if State.serverMode then
        getGameCore().SendGameAction("field_harvest", { plotIdx = plotIdx })
    end
    return rewards
end

--- 一键收获所有成熟地块
---@return table totalRewards
function M.HarvestAll()
    local total = {}
    for i = 1, M.GetMaxPlots() do
        local rewards = M.Harvest(i)
        if rewards then
            for matId, amount in pairs(rewards) do
                total[matId] = (total[matId] or 0) + amount
            end
        end
    end
    -- 注: 各 Harvest(i) 在 serverMode 下已各自发送了 field_harvest 的 GameAction
    -- 不需要再额外发送 field_harvest_all, 服务端会逐个处理
    return total
end

--- 是否有任何可收获的
---@return boolean
function M.HasHarvestable()
    for i = 1, M.GetMaxPlots() do
        if M.CanHarvest(i) then return true end
    end
    return false
end

return M
