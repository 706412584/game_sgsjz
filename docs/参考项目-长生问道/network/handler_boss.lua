-- ============================================================================
-- 《问道长生》组队 Boss 奖励结算 Handler（服务端权威）
-- 职责：验证结算令牌 → 发放灵石 → 装备掉落 → 同步客户端
-- Action: boss_settle
-- ============================================================================

local M = {}
M.Actions = {}

local DataWorld    = require("data_world")
local DataItems    = require("data_items")
local GameServer   = require("game_server")

-- ============================================================================
-- Boss 专用装备掉落（从 handler_explore 提取，共享逻辑）
-- ============================================================================

--- Boss 专用装备掉落：更高掉落率 + 品质保底 + 额外词条
---@param tier number 玩家境界
---@param areaId string 区域ID
---@return table|nil 装备数据
local function TryGenerateBossEquipDrop(tier, areaId)
    -- Boss 掉落率固定 60%
    local dropRate = 60
    if math.random(100) > dropRate then
        return nil
    end

    local slotKeys = DataItems.EQUIP_SLOT_KEYS
    local slot = slotKeys[math.random(#slotKeys)]
    local pool = DataItems.EQUIP_DROP_POOL[slot]
    if not pool or #pool == 0 then return nil end

    -- 根据区域确定品质概率
    local areaIndex = DataWorld.AREA_INDEX[areaId] or 1
    local rates = DataItems.GetQualityRatesByArea(areaIndex)
    local qualityRoll = math.random(100)
    local targetQuality = "fanqi"
    local acc = 0
    for _, q in ipairs(DataItems.QUALITY_ORDER) do
        acc = acc + (rates[q] or 0)
        if qualityRoll <= acc then
            targetQuality = q
            break
        end
    end

    -- 组队 Boss 品质保底：灵宝
    local minQuality = "lingbao"
    local qualityRank = {}
    for i, q in ipairs(DataItems.QUALITY_ORDER) do qualityRank[q] = i end
    local minRank = qualityRank[minQuality] or 2
    local curRank = qualityRank[targetQuality] or 1
    if curRank < minRank then
        targetQuality = minQuality
    end

    -- 从该品质中随机选一个基础装备
    local candidates = {}
    for _, e in ipairs(pool) do
        if e.quality == targetQuality then
            candidates[#candidates + 1] = e
        end
    end
    if #candidates == 0 then
        for rank = minRank, 1, -1 do
            local fallbackQ = DataItems.QUALITY_ORDER[rank]
            for _, e in ipairs(pool) do
                if e.quality == fallbackQ then
                    candidates[#candidates + 1] = e
                end
            end
            if #candidates > 0 then
                targetQuality = fallbackQ
                break
            end
        end
    end
    if #candidates == 0 then return nil end
    local base = candidates[math.random(#candidates)]

    -- 生成附加属性（+1 额外词条）
    local statRange = DataItems.EQUIP_STAT_RANGES[targetQuality]
    local extraStats = {}
    if statRange then
        local extraCount = (statRange.extraStats or 0) + 1
        local available = {}
        for _, s in ipairs(DataItems.EXTRA_STAT_POOL) do
            available[#available + 1] = s
        end
        for _ = 1, extraCount do
            if #available == 0 then break end
            local idx = math.random(#available)
            local statName = available[idx]
            table.remove(available, idx)
            local value = math.random(statRange.statRange[1], statRange.statRange[2])
            value = value + math.floor(tier * 0.5) + math.floor(tier * 0.3)
            extraStats[#extraStats + 1] = { stat = statName, value = value }
        end
    end

    local slotDef = DataItems.GetSlotByKey(slot)
    return {
        name       = base.name,
        slot       = slot,
        subType    = slotDef and slotDef.label or "手持",
        category   = "fabao",
        quality    = targetQuality,
        rarity     = targetQuality,
        count      = 1,
        baseAtk    = base.baseAtk or 0,
        baseDef    = base.baseDef or 0,
        baseCrit   = base.baseCrit or 0,
        baseSpd    = base.baseSpd or 0,
        extraStats = extraStats,
        dropTier   = tier,
        timestamp  = os.time(),
        desc       = "组队Boss掉落",
        isEquip    = true,
    }
end

-- ============================================================================
-- Action: boss_settle — 组队 Boss 奖励结算
-- params: { settleToken: string, playerKey: string }
-- ============================================================================

M.Actions["boss_settle"] = function(userId, params, reply)
    local settleToken = params.settleToken or ""
    local playerKey   = params.playerKey or ""

    if settleToken == "" or playerKey == "" then
        reply(false, { msg = "缺少参数" })
        return
    end

    -- 验证结算令牌
    local ServerBoss = require("network.server_boss")
    local settleData, err = ServerBoss.ConsumePendingSettle(userId, settleToken)
    if not settleData then
        reply(false, { msg = err or "结算失败" })
        return
    end

    local reward   = settleData.reward or 0
    local tier     = settleData.tier or 1
    local areaId   = settleData.areaId or "yunwu"
    local bossName = settleData.bossName or "Boss"

    -- 发放灵石
    serverCloud.money:Add(userId, "lingStone", reward, {
        ok = function()
            -- 尝试装备掉落
            local equip = TryGenerateBossEquipDrop(tier, areaId)

            if equip then
                -- 写入背包
                serverCloud:Get(userId, playerKey, {
                    ok = function(scores)
                        local playerData = scores and scores[playerKey]
                        if type(playerData) ~= "table" then
                            M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                            return
                        end
                        local bagItems = playerData.bagItems or {}
                        playerData.bagItems = bagItems

                        -- 容量防护：背包已满 → 强制回收为灵石
                        local bagCap = playerData.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
                        if #bagItems >= bagCap then
                            local sellPrice = DataItems.EQUIP_SELL_PRICE[equip.quality] or 10
                            print("[HandlerBoss] bag_full forced auto-sell " .. equip.name
                                .. " uid=" .. tostring(userId))
                            serverCloud.money:Add(userId, "lingStone", sellPrice, {
                                ok = function()
                                    -- 更新统计并完成
                                    local afkStats = playerData.afkStats or {}
                                    playerData.afkStats = afkStats
                                    afkStats.bossKills = (afkStats.bossKills or 0) + 1
                                    afkStats.totalEquipDrops = (afkStats.totalEquipDrops or 0) + 1
                                    serverCloud:Set(userId, playerKey, playerData, {
                                        ok = function()
                                            settleData.bagFullAutoSold = equip.name
                                            settleData.bagFullSellPrice = sellPrice
                                            M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                                        end,
                                        error = function()
                                            M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                                        end,
                                    })
                                end,
                                error = function()
                                    M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                                end,
                            })
                            return
                        end

                        bagItems[#bagItems + 1] = equip

                        -- 更新统计
                        local afkStats = playerData.afkStats or {}
                        playerData.afkStats = afkStats
                        afkStats.bossKills = (afkStats.bossKills or 0) + 1
                        afkStats.totalEquipDrops = (afkStats.totalEquipDrops or 0) + 1

                        serverCloud:Set(userId, playerKey, playerData, {
                            ok = function()
                                M.FinishSettle(userId, reply, reward, bossName, settleData, equip, playerKey)
                            end,
                            error = function()
                                M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                            end,
                        })
                    end,
                    error = function()
                        M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                    end,
                })
            else
                -- 无装备掉落，但仍更新统计
                serverCloud:Get(userId, playerKey, {
                    ok = function(scores)
                        local playerData = scores and scores[playerKey]
                        if type(playerData) == "table" then
                            local afkStats = playerData.afkStats or {}
                            playerData.afkStats = afkStats
                            afkStats.bossKills = (afkStats.bossKills or 0) + 1
                            serverCloud:Set(userId, playerKey, playerData, {
                                ok = function()
                                    M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                                end,
                                error = function()
                                    M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                                end,
                            })
                        else
                            M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                        end
                    end,
                    error = function()
                        M.FinishSettle(userId, reply, reward, bossName, settleData, nil, playerKey)
                    end,
                })
            end
        end,
        error = function(code, reason)
            print("[HandlerBoss] money:Add failed uid=" .. tostring(userId) .. " " .. tostring(reason))
            reply(false, { msg = "灵石发放失败" })
        end,
    })
end

--- 完成结算回复
function M.FinishSettle(userId, reply, reward, bossName, settleData, equip, playerKey)
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            local balance = moneys and moneys["lingStone"] or 0
            local resultData = {
                bossName = bossName,
                reward   = reward,
                damage   = settleData.damage,
                ratio    = math.floor((settleData.ratio or 0) * 100),
                balance  = balance,
                msg      = "击败" .. bossName .. "，获得灵石" .. reward,
            }
            local sync = {
                lingStone   = balance,
                spiritStone = moneys and moneys["spiritStone"] or 0,
            }

            if equip then
                local ql = DataItems.GetQualityLabel(equip.quality)
                resultData.equipDrop = equip
                resultData.equipMsg = "获得装备: [" .. ql .. "]" .. equip.name

                -- 读取最新背包同步
                local pKey = playerKey
                if not pKey or pKey == "" then
                    pKey = GameServer.GetServerKey("player")
                end
                serverCloud:Get(userId, pKey, {
                    ok = function(scores2)
                        local pd2 = scores2 and scores2[pKey]
                        if type(pd2) == "table" then
                            sync.bagItems = pd2.bagItems
                            sync.afkStats = pd2.afkStats
                        end
                        reply(true, resultData, sync)
                    end,
                    error = function()
                        reply(true, resultData, sync)
                    end,
                })
            else
                reply(true, resultData, sync)
            end
        end,
        error = function()
            reply(true, {
                bossName = bossName,
                reward   = reward,
                msg      = "击败" .. bossName .. "，获得灵石" .. reward,
            })
        end,
    })
end

return M
