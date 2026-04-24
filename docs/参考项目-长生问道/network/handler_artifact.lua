-- ============================================================================
-- 《问道长生》服务端 handler — 法宝操作
-- Actions: artifact_equip, artifact_unequip, artifact_enhance,
--          artifact_ascend, artifact_decompose, artifact_reroll
-- ============================================================================

local HandlerUtils = require("network.handler_utils")
local DataItems    = require("data_items")

local M = {}
M.Actions = {}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 在 artifacts 列表中按名称查找；同时搜索 equippedItems（兼容旧存档）
---@param arts table[]
---@param name string
---@param equippedItems? table  equippedItems 字典（slot→item）
---@return table|nil found
---@return number|nil index
local function FindArtByName(arts, name, equippedItems)
    for i, a in ipairs(arts) do
        if a.name == name then return a, i end
    end
    -- 兼容：旧存档可能将已装备法宝存在 equippedItems 而非 artifacts
    if equippedItems then
        for _, a in pairs(equippedItems) do
            if type(a) == "table" and a.name == name then return a, nil end
        end
    end
    return nil, nil
end

--- 扣除背包物品
---@param bagItems table[]
---@param itemName string
---@param count number
---@return boolean
local function ConsumeItem(bagItems, itemName, count)
    for i, item in ipairs(bagItems) do
        if item.name == itemName and (item.count or 0) >= count then
            item.count = item.count - count
            if item.count <= 0 then table.remove(bagItems, i) end
            return true
        end
    end
    return false
end

--- 添加背包物品（堆叠）
---@param bagItems table[]
---@param itemName string
---@param count number
local function AddItem(bagItems, itemName, count)
    for _, item in ipairs(bagItems) do
        if item.name == itemName then
            item.count = (item.count or 0) + count
            return
        end
    end
    bagItems[#bagItems + 1] = { name = itemName, count = count }
end

--- 标准化品质 key（兼容旧品质 common/uncommon/... → fanqi/lingbao/...）
---@param quality string|nil
---@return string
local function NormalizeQuality(quality)
    quality = quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    return quality
end

--- 获取法宝最大等级
---@param art table
---@return number
local function GetMaxLevel(art)
    local quality = NormalizeQuality(art.quality)
    return DataItems.GetMaxLevel(quality, art.ascStage or 0)
end

--- 用新分段表计算强化增幅百分比
---@param level number
---@return number
local function GetEnhancePct(level)
    return DataItems.GetTotalEnhancePct(level - 1)
end

--- 副属性 type → playerData 字段映射
local STAT_TYPE_TO_FIELD = {
    attack    = "attack",
    defense   = "defense",
    hp        = "hpMax",
    crit      = "crit",
    speed     = "speed",
    dodge     = "dodge",
    hit       = "hit",
    cultSpeed = "cultSpeedBonus",
    elemDmg   = "elemDmgBonus",
}

--- 法宝效果应用/移除（装备/卸下时用，支持新旧格式）
---@param playerData table
---@param art table
---@param sign number 1=应用, -1=移除
local function ApplyArtifactEffect(playerData, art, sign)
    if not art then return end
    local enhancePct = GetEnhancePct(art.level or 1)

    -- 新格式：mainStat + subStats
    if art.mainStat then
        local field = STAT_TYPE_TO_FIELD[art.mainStat.type]
        if field then
            local boosted = math.floor(art.mainStat.value * (1 + enhancePct / 100))
            playerData[field] = (playerData[field] or 0) + boosted * sign
        end
        -- 副属性不受强化加成
        if art.subStats then
            for _, sub in ipairs(art.subStats) do
                local sf = STAT_TYPE_TO_FIELD[sub.type]
                if sf then
                    playerData[sf] = (playerData[sf] or 0) + sub.value * sign
                end
            end
        end
        return
    end

    -- 旧格式：effect 字符串（向后兼容）
    if not art.effect then return end
    local effects = HandlerUtils.ParseEffect(art.effect)
    for _, e in ipairs(effects) do
        local boosted = math.floor(e.value * (1 + enhancePct / 100))
        local delta = boosted * sign
        local k = e.key
        if k == "攻击" then
            playerData.attack = (playerData.attack or 0) + delta
        elseif k == "防御" then
            playerData.defense = (playerData.defense or 0) + delta
        elseif k == "速度" then
            playerData.speed = (playerData.speed or 0) + delta
        elseif k == "灵力上限" then
            playerData.mpMax = (playerData.mpMax or 200) + delta
        elseif k == "暴击" then
            playerData.crit = (playerData.crit or 0) + delta
        end
    end
end

--- 构建装备/强化后通用 sync 字段
---@param playerData table
---@return table
local function BuildArtSync(playerData)
    return {
        artifacts      = playerData.artifacts,
        equippedItems  = playerData.equippedItems,
        attack         = playerData.attack,
        defense        = playerData.defense,
        speed          = playerData.speed,
        mpMax          = playerData.mpMax,
        crit           = playerData.crit,
        dodge          = playerData.dodge,
        hit            = playerData.hit,
        hpMax          = playerData.hpMax,
        cultSpeedBonus = playerData.cultSpeedBonus,
        elemDmgBonus   = playerData.elemDmgBonus,
    }
end

-- ============================================================================
-- artifact_equip — 装备法宝（同槽位自动卸旧）
-- params: { playerKey, artName }
-- ============================================================================
M.Actions["artifact_equip"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artName   = params.artName
    if not playerKey or not artName then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local target = FindArtByName(playerData.artifacts or {}, artName)
            if not target then return reply(false, { msg = "未拥有该法宝" }) end
            if target.equipped then return reply(false, { msg = "已经装备中" }) end

            -- 同槽位卸旧
            local slot = target.slot or "weapon"
            for _, a in ipairs(playerData.artifacts or {}) do
                if a.equipped and (a.slot or "weapon") == slot and a.name ~= artName then
                    a.equipped = false
                    ApplyArtifactEffect(playerData, a, -1)
                end
            end

            -- 装新
            target.equipped = true
            ApplyArtifactEffect(playerData, target, 1)

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    reply(true, { msg = "装备 " .. artName }, BuildArtSync(playerData))
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
-- artifact_unequip — 卸下法宝
-- params: { playerKey, artName }
-- ============================================================================
M.Actions["artifact_unequip"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artName   = params.artName
    if not playerKey or not artName then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            local found = FindArtByName(playerData.artifacts or {}, artName)
            if not found then return reply(false, { msg = "未拥有该法宝" }) end
            if not found.equipped then return reply(false, { msg = "未装备该法宝" }) end

            found.equipped = false
            ApplyArtifactEffect(playerData, found, -1)

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    reply(true, { msg = "卸下 " .. artName }, BuildArtSync(playerData))
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
-- artifact_enhance — 法宝强化（灵石 + 灵尘 + 天元精魄）
-- params: { playerKey, artName }
-- ============================================================================
M.Actions["artifact_enhance"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artName   = params.artName
    if not playerKey or not artName then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end
            if not playerData.bagItems then playerData.bagItems = {} end

            local art = FindArtByName(playerData.artifacts or {}, artName, playerData.equippedItems)
            if not art then return reply(false, { msg = "未拥有该法宝" }) end

            local curLevel = art.level or 1
            local maxLv = GetMaxLevel(art)
            if curLevel >= maxLv then
                return reply(false, { msg = "已达当前强化等级上限（" .. maxLv .. "级）" })
            end

            local info = DataItems.GetEnhanceInfo(curLevel)
            if not info then
                return reply(false, { msg = "无法获取强化配置" })
            end

            -- 校验灵尘
            if info.lingchen > 0 then
                local ok = ConsumeItem(playerData.bagItems, "灵尘", info.lingchen)
                if not ok then
                    return reply(false, { msg = "灵尘不足（需要" .. info.lingchen .. "）" })
                end
            end

            -- 校验天元精魄（仙器+品质才需要）
            local quality = NormalizeQuality(art.quality)
            local needTianyuan = info.tianyuan > 0 and DataItems.NeedsTianyuan(quality)
            if needTianyuan then
                local ok = ConsumeItem(playerData.bagItems, "天元精魄", info.tianyuan)
                if not ok then
                    -- 回滚灵尘
                    if info.lingchen > 0 then
                        AddItem(playerData.bagItems, "灵尘", info.lingchen)
                    end
                    return reply(false, { msg = "天元精魄不足（需要" .. info.tianyuan .. "）" })
                end
            end

            -- 扣灵石（通过 money 子系统原子操作）
            serverCloud.money:Cost(userId, "lingStone", info.lingshi, {
                ok = function()
                    -- 扣费成功，服务端掷骰
                    local roll = math.random(1, 100)
                    if roll > info.rate then
                        -- 强化失败：材料已消耗，只回传余额和背包
                        serverCloud:Set(userId, playerKey, playerData, {
                            ok = function()
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        reply(true, {
                                            msg     = art.name .. " 强化失败",
                                            success = false,
                                        }, {
                                            lingStone = (moneys and moneys.lingStone) or 0,
                                            bagItems  = playerData.bagItems,
                                        })
                                    end,
                                    error = function()
                                        reply(true, {
                                            msg     = art.name .. " 强化失败",
                                            success = false,
                                        }, { bagItems = playerData.bagItems })
                                    end,
                                })
                            end,
                            error = function()
                                reply(true, { msg = art.name .. " 强化失败", success = false })
                            end,
                        })
                        return
                    end

                    -- 强化成功：移除旧效果 → 升级 → 应用新效果
                    if art.equipped then
                        ApplyArtifactEffect(playerData, art, -1)
                    end
                    art.level = curLevel + 1
                    if art.equipped then
                        ApplyArtifactEffect(playerData, art, 1)
                    end

                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    local sync = BuildArtSync(playerData)
                                    sync.lingStone = (moneys and moneys.lingStone) or 0
                                    sync.bagItems  = playerData.bagItems
                                    reply(true, {
                                        msg     = art.name .. " 强化至 Lv." .. art.level,
                                        success = true,
                                    }, sync)
                                end,
                                error = function()
                                    local sync = BuildArtSync(playerData)
                                    sync.bagItems = playerData.bagItems
                                    reply(true, {
                                        msg     = art.name .. " 强化至 Lv." .. art.level,
                                        success = true,
                                    }, sync)
                                end,
                            })
                        end,
                        error = function(e)
                            print("[ArtifactEnhance] 保存失败但已扣费! uid=" .. tostring(userId))
                            reply(false, { msg = "保存失败: " .. tostring(e) })
                        end,
                    })
                end,
                error = function(code, reason)
                    -- 灵石扣费失败，回滚材料
                    if info.lingchen > 0 then
                        AddItem(playerData.bagItems, "灵尘", info.lingchen)
                    end
                    if needTianyuan then
                        AddItem(playerData.bagItems, "天元精魄", info.tianyuan)
                    end
                    reply(false, { msg = "灵石不足（需要" .. info.lingshi .. "）" })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- artifact_ascend — 法宝升阶（灵尘 + 灵石，概率成功）
-- params: { playerKey, artName }
-- ============================================================================
M.Actions["artifact_ascend"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artName   = params.artName
    if not playerKey or not artName then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end
            if not playerData.bagItems then playerData.bagItems = {} end

            local art = FindArtByName(playerData.artifacts or {}, artName, playerData.equippedItems)
            if not art then return reply(false, { msg = "未拥有该法宝" }) end

            local quality = NormalizeQuality(art.quality)
            local ascStage = art.ascStage or 0
            if ascStage >= 3 then
                return reply(false, { msg = "已达最高升阶" })
            end

            -- 需满级
            local maxLv = DataItems.GetMaxLevel(quality, ascStage)
            if (art.level or 1) < maxLv then
                return reply(false, { msg = "需达到当前强化上限（" .. maxLv .. "级）" })
            end

            local ascInfo = DataItems.GetAscensionInfo(quality, ascStage + 1)
            if not ascInfo then
                return reply(false, { msg = "该品质不可升阶" })
            end

            -- 扣灵尘
            if ascInfo.lingchen > 0 then
                local ok = ConsumeItem(playerData.bagItems, "灵尘", ascInfo.lingchen)
                if not ok then
                    return reply(false, { msg = "灵尘不足（需要" .. ascInfo.lingchen .. "）" })
                end
            end

            -- 扣灵石
            serverCloud.money:Cost(userId, "lingStone", ascInfo.lingshi, {
                ok = function()
                    -- 扣费成功，掷骰判定
                    local roll = math.random(1, 100)
                    local success = roll <= ascInfo.rate

                    if success then
                        -- 升阶成功：更新属性效果
                        if art.equipped then
                            ApplyArtifactEffect(playerData, art, -1)
                        end
                        art.ascStage = ascStage + 1
                        if art.equipped then
                            ApplyArtifactEffect(playerData, art, 1)
                        end
                    end

                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    local sync = BuildArtSync(playerData)
                                    sync.lingStone = (moneys and moneys.lingStone) or 0
                                    sync.bagItems  = playerData.bagItems
                                    reply(true, {
                                        msg         = success and (artName .. " " .. ascInfo.name .. "成功") or (artName .. " 升阶失败，材料已消耗"),
                                        success     = success,
                                        stageName   = ascInfo.name,
                                        extraLevels = ascInfo.extraLevels,
                                        newAscStage = art.ascStage,
                                    }, sync)
                                end,
                                error = function()
                                    local sync = BuildArtSync(playerData)
                                    sync.bagItems = playerData.bagItems
                                    reply(true, {
                                        msg     = success and (artName .. " " .. ascInfo.name .. "成功") or (artName .. " 升阶失败，材料已消耗"),
                                        success = success,
                                    }, sync)
                                end,
                            })
                        end,
                        error = function(e)
                            print("[ArtifactAscend] 保存失败! uid=" .. tostring(userId))
                            reply(false, { msg = "保存失败: " .. tostring(e) })
                        end,
                    })
                end,
                error = function(code, reason)
                    -- 灵石扣费失败，回滚灵尘
                    if ascInfo.lingchen > 0 then
                        AddItem(playerData.bagItems, "灵尘", ascInfo.lingchen)
                    end
                    reply(false, { msg = "灵石不足（需要" .. ascInfo.lingshi .. "）" })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- artifact_decompose — 法宝分解（回收材料）
-- params: { playerKey, artName }
-- ============================================================================
M.Actions["artifact_decompose"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artName   = params.artName
    if not playerKey or not artName then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end
            if not playerData.bagItems then playerData.bagItems = {} end

            local art, artIdx = FindArtByName(playerData.artifacts or {}, artName)
            if not art then return reply(false, { msg = "未拥有该法宝" }) end
            if art.equipped then return reply(false, { msg = "已装备的法宝不能分解" }) end

            local quality = NormalizeQuality(art.quality)
            local yields = DataItems.DECOMPOSE_YIELD[quality]
            if not yields then
                return reply(false, { msg = "该品质无法分解" })
            end

            -- 移除法宝
            table.remove(playerData.artifacts, artIdx)

            -- 发放背包材料
            local resultYields = {}
            if yields.lingchen > 0 then
                AddItem(playerData.bagItems, "灵尘", yields.lingchen)
                resultYields["灵尘"] = yields.lingchen
            end
            if yields.tianyuan > 0 then
                AddItem(playerData.bagItems, "天元精魄", yields.tianyuan)
                resultYields["天元精魄"] = yields.tianyuan
            end
            if yields.jingxue > 0 then
                AddItem(playerData.bagItems, "灵兽精血", yields.jingxue)
                resultYields["灵兽精血"] = yields.jingxue
            end

            -- 仙石走 money 子系统
            if yields.xianshi > 0 then
                resultYields["仙石"] = yields.xianshi
                serverCloud.money:Add(userId, "spiritStone", yields.xianshi, {
                    ok = function()
                        -- 保存 playerData
                        serverCloud:Set(userId, playerKey, playerData, {
                            ok = function()
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        reply(true, {
                                            msg    = artName .. " 已分解",
                                            yields = resultYields,
                                        }, {
                                            artifacts   = playerData.artifacts,
                                            bagItems    = playerData.bagItems,
                                            spiritStone = (moneys and moneys.spiritStone) or 0,
                                        })
                                    end,
                                    error = function()
                                        reply(true, {
                                            msg    = artName .. " 已分解",
                                            yields = resultYields,
                                        }, {
                                            artifacts = playerData.artifacts,
                                            bagItems  = playerData.bagItems,
                                        })
                                    end,
                                })
                            end,
                            error = function(e)
                                reply(false, { msg = "保存失败: " .. tostring(e) })
                            end,
                        })
                    end,
                    error = function(code, reason)
                        -- money:Add 失败但法宝已移除，仍然保存
                        print("[ArtifactDecompose] 仙石发放失败: " .. tostring(reason))
                        resultYields["仙石"] = 0
                        serverCloud:Set(userId, playerKey, playerData, {
                            ok = function()
                                reply(true, {
                                    msg    = artName .. " 已分解（仙石发放异常）",
                                    yields = resultYields,
                                }, {
                                    artifacts = playerData.artifacts,
                                    bagItems  = playerData.bagItems,
                                })
                            end,
                            error = function(e)
                                reply(false, { msg = "保存失败: " .. tostring(e) })
                            end,
                        })
                    end,
                })
            else
                -- 无仙石产出，直接保存
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        reply(true, {
                            msg    = artName .. " 已分解",
                            yields = resultYields,
                        }, {
                            artifacts = playerData.artifacts,
                            bagItems  = playerData.bagItems,
                        })
                    end,
                    error = function(e)
                        reply(false, { msg = "保存失败: " .. tostring(e) })
                    end,
                })
            end
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- artifact_reroll — 法宝副属性洗炼（仙器+品阶，元婴+境界）
-- params: { playerKey, artName }
-- ============================================================================
M.Actions["artifact_reroll"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artName   = params.artName
    if not playerKey or not artName then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end
            if not playerData.bagItems then playerData.bagItems = {} end

            local art = FindArtByName(playerData.artifacts or {}, artName, playerData.equippedItems)
            if not art then return reply(false, { msg = "未拥有该法宝" }) end

            -- 品阶检查（仙器及以上）
            local quality = NormalizeQuality(art.quality)
            if not DataItems.CanRerollQuality(quality) then
                return reply(false, { msg = "仅仙器及以上品阶可洗炼" })
            end

            -- 境界检查（元婴 = tier 5）
            local realmTier = playerData.realmTier or 1
            if realmTier < DataItems.REROLL_MIN_REALM then
                return reply(false, { msg = "需达到元婴境界才可洗炼" })
            end

            -- 必须有副属性
            if not art.subStats or #art.subStats == 0 then
                return reply(false, { msg = "该法宝无副属性" })
            end

            -- 计算锁定数量
            local lockCount = 0
            if art.locked then
                for _, lk in ipairs(art.locked) do
                    if lk then lockCount = lockCount + 1 end
                end
            end
            -- 不能锁定全部副属性
            if lockCount >= #art.subStats then
                return reply(false, { msg = "不能锁定全部副属性" })
            end

            -- 消耗灵尘
            local lingchenNeed = DataItems.REROLL_COST.lingchen
            if not ConsumeItem(playerData.bagItems, "灵尘", lingchenNeed) then
                return reply(false, { msg = "灵尘不足（需要" .. lingchenNeed .. "）" })
            end

            -- 消耗灵石（money 子系统）
            local lingshiNeed = DataItems.REROLL_COST.lingshi
            serverCloud.money:Cost(userId, "lingStone", lingshiNeed, {
                ok = function()
                    -- 灵石扣费成功，执行洗炼逻辑
                    local function doReroll()
                        -- 移除旧效果（如已装备）
                        if art.equipped then
                            ApplyArtifactEffect(playerData, art, -1)
                        end

                        -- 收集锁定的副属性 type，避免重复
                        local usedTypes = {}
                        for i, sub in ipairs(art.subStats) do
                            if art.locked and art.locked[i] then
                                usedTypes[sub.type] = true
                            end
                        end

                        -- 构建可用属性池（排除已锁定的 type）
                        local pool = {}
                        for _, st in ipairs(DataItems.EXTRA_STAT_POOL) do
                            if not usedTypes[st] then
                                pool[#pool + 1] = st
                            end
                        end

                        -- 为未锁定位置生成新副属性
                        for i = 1, #art.subStats do
                            if not (art.locked and art.locked[i]) then
                                if #pool > 0 then
                                    local idx = math.random(#pool)
                                    local statType = pool[idx]
                                    table.remove(pool, idx)
                                    local minVal, maxVal = DataItems.GetSubStatRange(statType, quality)
                                    local sub = {
                                        type  = statType,
                                        value = math.random(minVal, maxVal),
                                    }
                                    if statType == "elemDmg" then
                                        local elements = { "metal", "wood", "water", "fire", "earth" }
                                        sub.element = elements[math.random(#elements)]
                                    end
                                    art.subStats[i] = sub
                                    usedTypes[statType] = true
                                end
                            end
                        end

                        -- 应用新效果（如已装备）
                        if art.equipped then
                            ApplyArtifactEffect(playerData, art, 1)
                        end

                        -- 保存
                        serverCloud:Set(userId, playerKey, playerData, {
                            ok = function()
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        local sync = BuildArtSync(playerData)
                                        sync.lingStone   = (moneys and moneys.lingStone) or 0
                                        sync.spiritStone = (moneys and moneys.spiritStone) or 0
                                        sync.bagItems    = playerData.bagItems
                                        reply(true, {
                                            msg      = artName .. " 洗炼完成",
                                            subStats = art.subStats,
                                        }, sync)
                                    end,
                                    error = function()
                                        local sync = BuildArtSync(playerData)
                                        sync.bagItems = playerData.bagItems
                                        reply(true, {
                                            msg      = artName .. " 洗炼完成",
                                            subStats = art.subStats,
                                        }, sync)
                                    end,
                                })
                            end,
                            error = function(e)
                                print("[ArtifactReroll] 保存失败但已扣费! uid=" .. tostring(userId))
                                reply(false, { msg = "保存失败: " .. tostring(e) })
                            end,
                        })
                    end

                    -- 如有锁定副属性，额外扣仙石
                    if lockCount > 0 then
                        local lockCost = lockCount * DataItems.REROLL_LOCK_COST
                        serverCloud.money:Cost(userId, "spiritStone", lockCost, {
                            ok = function()
                                doReroll()
                            end,
                            error = function(code, reason)
                                -- 仙石扣费失败，回滚灵尘和灵石
                                AddItem(playerData.bagItems, "灵尘", lingchenNeed)
                                serverCloud.money:Add(userId, "lingStone", lingshiNeed, {
                                    ok = function() end,
                                    error = function() end,
                                })
                                reply(false, { msg = "仙石不足（锁定费用" .. lockCost .. "）" })
                            end,
                        })
                    else
                        doReroll()
                    end
                end,
                error = function(code, reason)
                    -- 灵石扣费失败，回滚灵尘
                    AddItem(playerData.bagItems, "灵尘", lingchenNeed)
                    reply(false, { msg = "灵石不足（需要" .. lingshiNeed .. "）" })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

-- ============================================================================
-- artifact_batch_decompose — 法宝批量分解（按品阶）
-- params: { playerKey, qualities = {"fanqi","lingbao",...} }
-- ============================================================================
M.Actions["artifact_batch_decompose"] = function(userId, params, reply)
    local playerKey  = params.playerKey
    local qualities  = params.qualities
    if not playerKey or type(qualities) ~= "table" or #qualities == 0 then
        return reply(false, { msg = "参数缺失" })
    end

    -- 构建品阶查找集合
    local qualitySet = {}
    for _, q in ipairs(qualities) do
        qualitySet[q] = true
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end
            if not playerData.bagItems then playerData.bagItems = {} end

            local arts = playerData.artifacts or {}
            local remaining = {}
            local totalYields = {}
            local count = 0
            local totalXianshi = 0

            for _, art in ipairs(arts) do
                local quality = NormalizeQuality(art.quality)
                if not art.equipped and qualitySet[quality] then
                    local yields = DataItems.DECOMPOSE_YIELD[quality]
                    if yields then
                        count = count + 1
                        -- 累计材料产出
                        if yields.lingchen > 0 then
                            AddItem(playerData.bagItems, "灵尘", yields.lingchen)
                            totalYields["灵尘"] = (totalYields["灵尘"] or 0) + yields.lingchen
                        end
                        if yields.tianyuan > 0 then
                            AddItem(playerData.bagItems, "天元精魄", yields.tianyuan)
                            totalYields["天元精魄"] = (totalYields["天元精魄"] or 0) + yields.tianyuan
                        end
                        if yields.jingxue > 0 then
                            AddItem(playerData.bagItems, "灵兽精血", yields.jingxue)
                            totalYields["灵兽精血"] = (totalYields["灵兽精血"] or 0) + yields.jingxue
                        end
                        if yields.xianshi > 0 then
                            totalXianshi = totalXianshi + yields.xianshi
                            totalYields["仙石"] = (totalYields["仙石"] or 0) + yields.xianshi
                        end
                    else
                        remaining[#remaining + 1] = art
                    end
                else
                    remaining[#remaining + 1] = art
                end
            end

            if count == 0 then
                return reply(false, { msg = "没有可分解的法宝" })
            end

            playerData.artifacts = remaining

            -- 保存并发放仙石
            local function SaveAndReply()
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        if totalXianshi > 0 then
                            serverCloud.money:Add(userId, "spiritStone", totalXianshi, {
                                ok = function()
                                    serverCloud.money:Get(userId, {
                                        ok = function(moneys)
                                            reply(true, {
                                                count  = count,
                                                yields = totalYields,
                                            }, {
                                                artifacts   = playerData.artifacts,
                                                bagItems    = playerData.bagItems,
                                                spiritStone = (moneys and moneys.spiritStone) or 0,
                                            })
                                        end,
                                        error = function()
                                            reply(true, {
                                                count  = count,
                                                yields = totalYields,
                                            }, {
                                                artifacts = playerData.artifacts,
                                                bagItems  = playerData.bagItems,
                                            })
                                        end,
                                    })
                                end,
                                error = function()
                                    totalYields["仙石"] = 0
                                    reply(true, {
                                        count  = count,
                                        yields = totalYields,
                                        msg    = "分解完成（仙石发放异常）",
                                    }, {
                                        artifacts = playerData.artifacts,
                                        bagItems  = playerData.bagItems,
                                    })
                                end,
                            })
                        else
                            reply(true, {
                                count  = count,
                                yields = totalYields,
                            }, {
                                artifacts = playerData.artifacts,
                                bagItems  = playerData.bagItems,
                            })
                        end
                    end,
                    error = function(e)
                        reply(false, { msg = "保存失败: " .. tostring(e) })
                    end,
                })
            end

            SaveAndReply()
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

return M
