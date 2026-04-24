-- ============================================================================
-- 《问道长生》服务端 handler — 物品操作
-- Actions: item_use_pill, item_sell, item_batch_sell, item_recycle, item_expand_bag
-- ============================================================================

local HandlerUtils = require("network.handler_utils")
local DataItems    = require("data_items")
local PillsHelper  = require("network.pills_helper")

local M = {}
M.Actions = {}

-- ============================================================================
-- 辅助：品质排序权重
-- ============================================================================
local QUALITY_WEIGHT = {
    mythic   = 60,
    legend   = 50,
    epic     = 40,
    rare     = 30,
    uncommon = 20,
    common   = 10,
}

-- ============================================================================
-- item_use_pill — 服用丹药（扣丹药 + 应用效果 + pillUsage）
-- params: { playerKey, pillName }
-- ============================================================================
M.Actions["item_use_pill"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local pillName  = params.pillName
    if not playerKey or not pillName then
        return reply(false, { msg = "参数缺失" })
    end

    -- 并行读取 playerData 和独立 pills key
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                print("[item_use_pill] ERROR: playerData 不是 table, uid=" .. tostring(userId))
                return reply(false, { msg = "角色数据读取失败" })
            end

            PillsHelper.Read(userId, function(pills, errMsg)
                if not pills then
                    return reply(false, { msg = "丹药数据读取失败" })
                end

                -- 查找丹药
                local pill = nil
                for _, p in ipairs(pills) do
                    if p.name == pillName then pill = p; break end
                end
                if not pill then
                    return reply(false, { msg = "未拥有该丹药" })
                end
                if pill.locked then
                    return reply(false, { msg = "该丹药暂未解锁" })
                end
                if (pill.count or 0) <= 0 then
                    return reply(false, { msg = "丹药数量不足" })
                end

                -- perRealm 限制
                local def = DataItems.FindPillByName(pillName)
                if def and def.perRealm then
                    playerData.pillUsage = playerData.pillUsage or {}
                    local usage = playerData.pillUsage[pillName] or 0
                    if usage >= def.perRealm then
                        return reply(false, { msg = "本境界已达服用上限(" .. def.perRealm .. "次)" })
                    end
                end

                -- 扣除丹药
                pill.count = pill.count - 1

                -- 应用效果
                local effectMsg = ""
                local moneyRewards = {}
                if def then
                    effectMsg, moneyRewards = HandlerUtils.ApplyEffectToData(playerData, def.effect)
                    if def.perRealm then
                        playerData.pillUsage = playerData.pillUsage or {}
                        playerData.pillUsage[pillName] = (playerData.pillUsage[pillName] or 0) + 1
                    end
                end

                playerData.pills = nil  -- 从 blob 中清除

                -- 构建 sync 字段
                local sync = {
                    pills     = pills,
                    pillUsage = playerData.pillUsage,
                }
                local effectKeys = { "cultivation", "hpMax", "hp", "mp",
                    "attack", "defense", "speed", "sense", "wisdom", "fortune",
                    "lifespan", "gameYear", "mpMax", "crit" }
                for _, ek in ipairs(effectKeys) do
                    if playerData[ek] ~= nil then
                        sync[ek] = playerData[ek]
                    end
                end

                -- 写入独立 pills key
                PillsHelper.Write(userId, pills, function(pillsOk)
                    if not pillsOk then
                        print("[item_use_pill] pills 写入失败 uid=" .. tostring(userId))
                    end
                    -- 写入 playerData（pillUsage + 效果属性，不含 pills）
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            local msg = "服用" .. pillName .. "成功"
                            if effectMsg ~= "" then msg = msg .. "，" .. effectMsg end
                            if #moneyRewards > 0 then
                                HandlerUtils.GrantMoneyRewards(userId, moneyRewards, function(balances)
                                    if balances then
                                        for k2, v2 in pairs(balances) do
                                            sync[k2] = v2
                                        end
                                    end
                                    reply(true, { msg = msg }, sync)
                                end)
                            else
                                reply(true, { msg = msg }, sync)
                            end
                        end,
                        error = function(e)
                            reply(false, { msg = "保存失败: " .. tostring(e) })
                        end,
                    })
                end, playerKey)
            end, playerKey)
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- item_use_from_bag — 从背包使用丹药（原子：移除背包物品 → 加入pills → 服用）
-- params: { playerKey, itemIndex }
-- ============================================================================
M.Actions["item_use_from_bag"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local itemIndex = params.itemIndex
    if not playerKey or not itemIndex then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local items = playerData.bagItems or {}
            if itemIndex < 1 or itemIndex > #items then
                return reply(false, { msg = "无效的物品索引" })
            end

            local item = items[itemIndex]
            local pillDef = DataItems.FindPillByName(item.name)
            if not pillDef then
                return reply(false, { msg = (item.name or "物品") .. "无法直接使用" })
            end

            local pillName = item.name

            -- 从独立 key 读取 pills
            PillsHelper.Read(userId, function(pills, errMsg)
                if not pills then
                    return reply(false, { msg = "丹药数据读取失败" })
                end

                -- 1) 从背包移除 1 个
                if (item.count or 1) <= 1 then
                    table.remove(items, itemIndex)
                else
                    item.count = item.count - 1
                end

                -- 2) 加入 pills 列表
                local found = false
                for _, pill in ipairs(pills) do
                    if pill.name == pillName then
                        pill.count = (pill.count or 0) + 1
                        found = true
                        break
                    end
                end
                if not found then
                    pills[#pills + 1] = {
                        name    = pillName,
                        count   = 1,
                        quality = pillDef.quality or "common",
                        desc    = pillDef.effect or "",
                        effect  = pillDef.effect or "",
                    }
                end

                -- 3) 服用丹药
                local pill = nil
                for _, p in ipairs(pills) do
                    if p.name == pillName then pill = p; break end
                end
                if not pill or (pill.count or 0) <= 0 then
                    return reply(false, { msg = "丹药数量异常" })
                end
                if pill.locked then
                    return reply(false, { msg = "该丹药暂未解锁" })
                end

                -- perRealm 限制
                if pillDef.perRealm then
                    playerData.pillUsage = playerData.pillUsage or {}
                    local usage = playerData.pillUsage[pillName] or 0
                    if usage >= pillDef.perRealm then
                        return reply(false, { msg = "本境界已达服用上限(" .. pillDef.perRealm .. "次)" })
                    end
                end

                -- 扣除丹药
                pill.count = pill.count - 1

                -- 应用效果
                local effectMsg = ""
                local moneyRewards = {}
                effectMsg, moneyRewards = HandlerUtils.ApplyEffectToData(playerData, pillDef.effect)
                if pillDef.perRealm then
                    playerData.pillUsage = playerData.pillUsage or {}
                    playerData.pillUsage[pillName] = (playerData.pillUsage[pillName] or 0) + 1
                end

                playerData.pills = nil  -- 从 blob 中清除

                -- 构建 sync
                local sync = {
                    bagItems  = playerData.bagItems,
                    pills     = pills,
                    pillUsage = playerData.pillUsage,
                }
                local effectKeys = { "cultivation", "hpMax", "hp", "mp",
                    "attack", "defense", "speed", "sense", "wisdom", "fortune",
                    "lifespan", "gameYear", "mpMax", "crit" }
                for _, ek in ipairs(effectKeys) do
                    if playerData[ek] ~= nil then
                        sync[ek] = playerData[ek]
                    end
                end

                -- 写入独立 pills key
                PillsHelper.Write(userId, pills, function(pillsOk)
                    if not pillsOk then
                        print("[item_use_from_bag] pills 写入失败 uid=" .. tostring(userId))
                    end
                    -- 写入 playerData（bagItems + pillUsage + 效果属性）
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            local msg = "服用" .. pillName .. "成功"
                            if effectMsg ~= "" then msg = msg .. "，" .. effectMsg end
                            if #moneyRewards > 0 then
                                HandlerUtils.GrantMoneyRewards(userId, moneyRewards, function(balances)
                                    if balances then
                                        for k2, v2 in pairs(balances) do
                                            sync[k2] = v2
                                        end
                                    end
                                    reply(true, { msg = msg }, sync)
                                end)
                            else
                                reply(true, { msg = msg }, sync)
                            end
                        end,
                        error = function(e)
                            reply(false, { msg = "保存失败: " .. tostring(e) })
                        end,
                    })
                end, playerKey)
            end, playerKey)
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- item_sell — 出售单件物品
-- params: { playerKey, itemIndex, count }
-- ============================================================================
M.Actions["item_sell"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local itemIndex = params.itemIndex
    local count     = params.count or 1
    if not playerKey or not itemIndex then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local items = playerData.bagItems or {}
            if itemIndex < 1 or itemIndex > #items then
                return reply(false, { msg = "无效的物品索引" })
            end

            local item = items[itemIndex]
            local sellCount = math.min(count, item.count or 1)
            local unitPrice = HandlerUtils.SELL_PRICE[item.rarity or "common"] or 5
            local totalPrice = unitPrice * sellCount

            -- 移除物品
            if sellCount >= (item.count or 1) then
                table.remove(items, itemIndex)
            else
                item.count = item.count - sellCount
            end

            -- 保存背包变更（不含灵石，灵石走 money 子系统）
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    -- 通过 money 子系统加灵石
                    serverCloud.money:Add(userId, "lingStone", totalPrice, {
                        ok = function()
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    reply(true, {
                                        msg = "出售" .. (item.name or "物品") .. "x" .. sellCount .. "，获得灵石" .. totalPrice,
                                    }, {
                                        bagItems  = playerData.bagItems,
                                        lingStone = (moneys and moneys["lingStone"]) or 0,
                                    })
                                end,
                                error = function()
                                    reply(true, {
                                        msg = "出售" .. (item.name or "物品") .. "x" .. sellCount .. "，获得灵石" .. totalPrice,
                                    }, { bagItems = playerData.bagItems })
                                end,
                            })
                        end,
                        error = function(e)
                            reply(true, {
                                msg = "出售" .. (item.name or "物品") .. "x" .. sellCount .. "，灵石发放异常",
                            }, { bagItems = playerData.bagItems })
                        end,
                    })
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
-- item_batch_sell — 批量出售（按品质）
-- params: { playerKey, maxQuality }
-- ============================================================================
M.Actions["item_batch_sell"] = function(userId, params, reply)
    local playerKey  = params.playerKey
    local maxQuality = params.maxQuality or "uncommon"
    if not playerKey then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local maxWeight = QUALITY_WEIGHT[maxQuality] or 20
            local items = playerData.bagItems or {}
            local totalPrice = 0
            local totalCount = 0

            for i = #items, 1, -1 do
                local item = items[i]
                if not item.locked then
                    local w = QUALITY_WEIGHT[item.rarity or "common"] or 0
                    if w <= maxWeight then
                        local unitPrice = HandlerUtils.SELL_PRICE[item.rarity or "common"] or 5
                        local cnt = item.count or 1
                        totalPrice = totalPrice + unitPrice * cnt
                        totalCount = totalCount + cnt
                        table.remove(items, i)
                    end
                end
            end

            if totalCount == 0 then
                return reply(false, { msg = "没有可出售的物品" })
            end

            -- 保存背包变更（不含灵石，灵石走 money 子系统）
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    serverCloud.money:Add(userId, "lingStone", totalPrice, {
                        ok = function()
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    reply(true, {
                                        msg = "批量出售" .. totalCount .. "件物品，获得灵石" .. totalPrice,
                                    }, {
                                        bagItems  = playerData.bagItems,
                                        lingStone = (moneys and moneys["lingStone"]) or 0,
                                    })
                                end,
                                error = function()
                                    reply(true, {
                                        msg = "批量出售" .. totalCount .. "件物品，获得灵石" .. totalPrice,
                                    }, { bagItems = playerData.bagItems })
                                end,
                            })
                        end,
                        error = function()
                            reply(true, {
                                msg = "批量出售" .. totalCount .. "件物品，灵石发放异常",
                            }, { bagItems = playerData.bagItems })
                        end,
                    })
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
-- item_recycle — 批量回收（按品质集合）
-- params: { playerKey, selectedQualities }
-- selectedQualities: { common=true, uncommon=true, ... }
-- ============================================================================
M.Actions["item_recycle"] = function(userId, params, reply)
    local playerKey         = params.playerKey
    local selectedQualities = params.selectedQualities
    if not playerKey or not selectedQualities then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local items = playerData.bagItems or {}
            local totalPrice = 0
            local totalCount = 0

            for i = #items, 1, -1 do
                local item = items[i]
                local rarity = item.rarity or "common"
                if selectedQualities[rarity] and not item.locked then
                    local unitPrice = HandlerUtils.SELL_PRICE[rarity] or 5
                    local cnt = item.count or 1
                    totalPrice = totalPrice + unitPrice * cnt
                    totalCount = totalCount + cnt
                    table.remove(items, i)
                end
            end

            if totalCount == 0 then
                return reply(false, { msg = "没有符合条件的可回收物品" })
            end

            -- 保存背包变更（不含灵石，灵石走 money 子系统）
            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    serverCloud.money:Add(userId, "lingStone", totalPrice, {
                        ok = function()
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    reply(true, {
                                        msg = "回收" .. totalCount .. "件物品，获得灵石" .. totalPrice,
                                    }, {
                                        bagItems  = playerData.bagItems,
                                        lingStone = (moneys and moneys["lingStone"]) or 0,
                                    })
                                end,
                                error = function()
                                    reply(true, {
                                        msg = "回收" .. totalCount .. "件物品，获得灵石" .. totalPrice,
                                    }, { bagItems = playerData.bagItems })
                                end,
                            })
                        end,
                        error = function()
                            reply(true, {
                                msg = "回收" .. totalCount .. "件物品，灵石发放异常",
                            }, { bagItems = playerData.bagItems })
                        end,
                    })
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
-- item_expand_bag — 背包扩容
-- params: { playerKey }
-- ============================================================================
M.Actions["item_expand_bag"] = function(userId, params, reply)
    local playerKey = params.playerKey
    if not playerKey then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local cap = playerData.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
            if cap >= DataItems.BAG_EXPAND.maxCapacity then
                return reply(false, { msg = "已达容量上限(" .. DataItems.BAG_EXPAND.maxCapacity .. "格)" })
            end

            local cost = cap * DataItems.BAG_EXPAND.costPerSlot

            -- 先通过 money 子系统扣灵石（原子操作，余额不足自动失败）
            serverCloud.money:Cost(userId, "lingStone", cost, {
                ok = function()
                    -- 扣费成功，更新背包容量
                    playerData.bagCapacity = cap + DataItems.BAG_EXPAND.perExpand

                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    reply(true, {
                                        msg = "扩容成功! 容量: " .. playerData.bagCapacity .. "/" .. DataItems.BAG_EXPAND.maxCapacity,
                                    }, {
                                        bagCapacity = playerData.bagCapacity,
                                        lingStone   = (moneys and moneys["lingStone"]) or 0,
                                    })
                                end,
                                error = function()
                                    reply(true, {
                                        msg = "扩容成功! 容量: " .. playerData.bagCapacity .. "/" .. DataItems.BAG_EXPAND.maxCapacity,
                                    }, { bagCapacity = playerData.bagCapacity })
                                end,
                            })
                        end,
                        error = function(e)
                            -- 扣费成功但保存失败 —— 严重异常（灵石已扣但容量未加）
                            print("[ExpandBag] 保存失败但灵石已扣! uid=" .. tostring(userId) .. " cost=" .. cost)
                            reply(false, { msg = "保存失败: " .. tostring(e) })
                        end,
                    })
                end,
                error = function(code, reason)
                    reply(false, { msg = "灵石不足(需" .. cost .. ")" })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- set_auto_sell — 设置自动回收品质阈值
-- params: { playerKey, autoSellBelow }
-- autoSellBelow: "none" | "fanqi" | "lingbao" | "xtlingbao" | "huangqi"
-- ============================================================================
local VALID_AUTO_SELL = { none = true, fanqi = true, lingbao = true, xtlingbao = true, huangqi = true }

M.Actions["set_auto_sell"] = function(userId, params, reply)
    local playerKey     = params.playerKey
    local autoSellBelow = params.autoSellBelow or "none"
    if not playerKey then
        return reply(false, { msg = "参数缺失" })
    end
    if not VALID_AUTO_SELL[autoSellBelow] then
        return reply(false, { msg = "无效的自动回收品质: " .. tostring(autoSellBelow) })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            playerData.autoSellBelow = autoSellBelow

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    local labelMap = {
                        none      = "关闭",
                        fanqi     = "凡器及以下",
                        lingbao   = "灵宝及以下",
                        xtlingbao = "先天灵宝及以下",
                        huangqi   = "皇器及以下",
                    }
                    reply(true, {
                        msg = "自动回收已设为: " .. (labelMap[autoSellBelow] or autoSellBelow),
                    }, {
                        autoSellBelow = autoSellBelow,
                    })
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
