-- ============================================================================
-- 《问道长生》服务端 handler — 装备操作
-- Actions: equip_wear, equip_remove
-- 装备数据格式: bagItems 中 isEquip=true 的物品
-- 已装备数据: playerData.equippedItems = { weapon=item, head=item, ... }
-- ============================================================================

local HandlerUtils = require("network.handler_utils")
local DataItems    = require("data_items")

local M = {}
M.Actions = {}

--- 构建同步字段（穿戴/脱下共用）
---@param playerData table
---@return table sync
local function BuildSync(playerData)
    return {
        bagItems      = playerData.bagItems,
        equippedItems = playerData.equippedItems,
        attack        = playerData.attack,
        defense       = playerData.defense,
        speed         = playerData.speed,
        crit          = playerData.crit,
        dodge         = playerData.dodge,
        hit           = playerData.hit,
        hpMax         = playerData.hpMax,
        hp            = playerData.hp,
    }
end

-- ============================================================================
-- equip_wear — 穿戴装备（同槽位自动卸旧 → 放回背包）
-- params: { playerKey, bagIndex }
-- bagIndex: 1-based 背包中该装备的全局索引
-- ============================================================================
M.Actions["equip_wear"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local bagIndex  = params.bagIndex
    if not playerKey or not bagIndex then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local bagItems = playerData.bagItems or {}
            if bagIndex < 1 or bagIndex > #bagItems then
                return reply(false, { msg = "物品索引无效" })
            end

            local item = bagItems[bagIndex]
            if not item or not item.isEquip then
                return reply(false, { msg = "该物品不是装备" })
            end

            local slot = item.slot
            if not slot then
                return reply(false, { msg = "装备缺少槽位信息" })
            end

            -- 确保 equippedItems 存在
            playerData.equippedItems = playerData.equippedItems or {}

            -- 同槽位卸旧 → 放回背包
            local oldEquip = playerData.equippedItems[slot]
            if oldEquip then
                HandlerUtils.ApplyEquipStatsToData(playerData, oldEquip, -1)
                bagItems[#bagItems + 1] = oldEquip
            end

            -- 从背包移除新装备
            table.remove(bagItems, bagIndex)

            -- 穿上新装备
            playerData.equippedItems[slot] = item
            HandlerUtils.ApplyEquipStatsToData(playerData, item, 1)

            -- 保存
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    local oldName = oldEquip and oldEquip.name or nil
                    local msg = "装备了 " .. item.name
                    if oldName then
                        msg = msg .. "（替换 " .. oldName .. "）"
                    end
                    reply(true, { msg = msg, slot = slot }, BuildSync(playerData))
                end,
                error = function(e)
                    reply(false, { msg = "保存失败: " .. tostring(e) })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- equip_remove — 脱下装备 → 放回背包
-- params: { playerKey, slot }
-- ============================================================================
M.Actions["equip_remove"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local slot      = params.slot
    if not playerKey or not slot then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            playerData.equippedItems = playerData.equippedItems or {}
            local equip = playerData.equippedItems[slot]
            if not equip then
                return reply(false, { msg = "该槽位没有装备" })
            end

            -- 检查背包容量
            local bagItems = playerData.bagItems or {}
            local bagCap = playerData.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
            if #bagItems >= bagCap then
                return reply(false, { msg = "背包已满，无法脱下" })
            end

            -- 移除属性加成
            HandlerUtils.ApplyEquipStatsToData(playerData, equip, -1)

            -- 放回背包
            playerData.equippedItems[slot] = nil
            bagItems[#bagItems + 1] = equip
            playerData.bagItems = bagItems

            -- 保存
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    reply(true, { msg = "卸下了 " .. equip.name, slot = slot }, BuildSync(playerData))
                end,
                error = function(e)
                    reply(false, { msg = "保存失败: " .. tostring(e) })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

return M
