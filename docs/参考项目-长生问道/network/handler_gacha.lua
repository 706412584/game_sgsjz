-- ============================================================================
-- 《问道长生》抽奖处理器
-- Actions: gacha_pull (单抽/十连)
-- 抽奖数据存储在 playerData.gachaData 中
-- 服务端权威：概率计算、保底判定、扣费均在服务端完成
-- ============================================================================

local GameServer  = require("game_server")
local DataMon     = require("data_monetization")
local DataItems   = require("data_items")
local PillsHelper = require("network.pills_helper")

local M = {}
M.Actions = {}

-- ============================================================================
-- 抽奖材料/丹药奖池（随机给一种丹药）
-- ============================================================================
local GACHA_PILL_POOL = {
    { name = "培元丹",     count = 5, quality = "common",   desc = "修为+200" },
    { name = "回气丹",     count = 5, quality = "common",   desc = "灵力恢复100" },
    { name = "凝神丹",     count = 3, quality = "uncommon", desc = "神识+20" },
    { name = "通脉丹",     count = 2, quality = "rare",     desc = "修炼速度+20%(1小时)" },
    { name = "上品培元丹", count = 2, quality = "uncommon", desc = "修为+1000" },
    { name = "强身丹",     count = 2, quality = "uncommon", desc = "气血+50(永久)" },
    { name = "灵攻丹",     count = 2, quality = "uncommon", desc = "攻击+10(永久)" },
    { name = "固元丹",     count = 2, quality = "uncommon", desc = "防御+8(永久)" },
}

-- ============================================================================
-- 装备生成（复用 handler_explore 逻辑）
-- ============================================================================

--- 根据抽奖品质生成一件随机装备
---@param quality string 品质 key（如 xianqi, shenqi 等）
---@return table 装备数据
local function GenerateGachaEquip(quality)
    -- 1. 随机槽位
    local slotKeys = DataItems.EQUIP_SLOT_KEYS
    local slot = slotKeys[math.random(#slotKeys)]

    -- 2. 从装备池中选同品质装备
    local pool = DataItems.EQUIP_DROP_POOL and DataItems.EQUIP_DROP_POOL[slot] or {}
    local candidates = {}
    for _, e in ipairs(pool) do
        if e.quality == quality then
            candidates[#candidates + 1] = e
        end
    end
    -- 如果该品质没装备模板，降级到 fanqi
    if #candidates == 0 then
        for _, e in ipairs(pool) do
            if e.quality == "fanqi" then
                candidates[#candidates + 1] = e
            end
        end
    end

    -- 基础装备模板
    local base
    if #candidates > 0 then
        base = candidates[math.random(#candidates)]
    else
        base = { name = "抽奖法宝", baseAtk = 10, baseDef = 5, baseCrit = 0, baseSpd = 0 }
    end

    -- 3. 生成主属性
    local slotDef = DataItems.GetSlotByKey(slot)
    local mainStatType = slotDef and slotDef.mainStat or "attack"
    local msMin, msMax = DataItems.GetMainStatRange(quality, mainStatType)
    local mainStat = {
        type  = mainStatType,
        value = math.random(msMin, msMax),
    }

    -- 4. 生成副属性
    local subStatCount = DataItems.SUB_STAT_COUNTS[quality] or 1
    local subStats = {}
    local available = {}
    for _, s in ipairs(DataItems.EXTRA_STAT_POOL) do
        if s ~= mainStatType then
            available[#available + 1] = s
        end
    end
    for _ = 1, subStatCount do
        if #available == 0 then break end
        local idx = math.random(#available)
        local statType = available[idx]
        table.remove(available, idx)
        local minVal, maxVal = DataItems.GetSubStatRange(statType, quality)
        local sub = { type = statType, value = math.random(minVal, maxVal) }
        if statType == "elemDmg" then
            local elements = { "metal", "wood", "water", "fire", "earth" }
            sub.element = elements[math.random(#elements)]
        end
        subStats[#subStats + 1] = sub
    end

    -- 5. 组装装备
    return {
        name       = base.name,
        slot       = slot,
        subType    = slotDef and slotDef.label or "手持",
        category   = "fabao",
        quality    = quality,
        rarity     = quality,
        count      = 1,
        baseAtk    = base.baseAtk or 0,
        baseDef    = base.baseDef or 0,
        baseCrit   = base.baseCrit or 0,
        baseSpd    = base.baseSpd or 0,
        mainStat   = mainStat,
        subStats   = subStats,
        timestamp  = os.time(),
        desc       = "抽奖获得",
        isEquip    = true,
    }
end

--- 添加丹药到 pills 列表（堆叠同名）
---@param pills table[]
---@param pillDef table { name, count, quality, desc }
local function AddPillToList(pills, pillDef)
    for _, p in ipairs(pills) do
        if p.name == pillDef.name then
            p.count = (p.count or 0) + pillDef.count
            return
        end
    end
    pills[#pills + 1] = {
        name    = pillDef.name,
        count   = pillDef.count,
        quality = pillDef.quality or "common",
        desc    = pillDef.desc or "",
        effect  = pillDef.desc or "",
    }
end

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保 gachaData 字段存在
---@param pd table playerData
---@return table gachaData
local function EnsureGachaData(pd)
    if not pd.gachaData then
        pd.gachaData = {
            totalPulls = 0,
            pityCounter = 0,  -- 距上次高品质的累计抽数
        }
    end
    return pd.gachaData
end

--- 执行单次抽奖（含保底机制）
---@param pityCounter number 当前保底计数
---@return table { quality, label, pityReset }
local function RollOnce(pityCounter)
    local rates = DataMon.GACHA_RATES
    local gacha = DataMon.GACHA

    -- 硬保底：100抽必出神器以上
    if pityCounter >= gacha.hardPity - 1 then
        -- 从神器及以上中随机
        local highPool = {}
        for _, r in ipairs(rates) do
            if r.quality == "xtshenqi" or r.quality == "shenqi" then
                highPool[#highPool + 1] = r
            end
        end
        local pick = highPool[math.random(1, #highPool)]
        return { quality = pick.quality, label = pick.label, pityReset = true }
    end

    -- 软保底：50抽必出仙器以上
    if pityCounter >= gacha.softPity - 1 then
        local midPool = {}
        for _, r in ipairs(rates) do
            if r.quality == "xtshenqi" or r.quality == "shenqi"
                or r.quality == "xtxianqi" or r.quality == "xianqi" then
                midPool[#midPool + 1] = r
            end
        end
        local pick = midPool[math.random(1, #midPool)]
        return { quality = pick.quality, label = pick.label, pityReset = true }
    end

    -- 正常概率抽取
    local roll = math.random()
    local cumulative = 0
    for _, r in ipairs(rates) do
        cumulative = cumulative + r.rate
        if roll <= cumulative then
            -- 仙器及以上重置保底
            local isHigh = (r.quality == "xtshenqi" or r.quality == "shenqi"
                or r.quality == "xtxianqi" or r.quality == "xianqi")
            return { quality = r.quality, label = r.label, pityReset = isHigh }
        end
    end

    -- 兜底：返回最低档
    local last = rates[#rates]
    return { quality = last.quality, label = last.label, pityReset = false }
end

-- ============================================================================
-- Action: gacha_pull — 抽奖（单抽/十连）
-- params: { count = 1|10 }
-- ============================================================================

M.Actions["gacha_pull"] = function(userId, params, reply)
    local count = params.count or 1
    if count ~= 1 and count ~= 10 then
        return reply(false, { msg = "抽奖次数无效" })
    end

    local gacha = DataMon.GACHA
    local cost = (count == 10) and gacha.tenCost or gacha.singleCost

    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        playerKey = GameServer.GetServerKey("player")
    end
    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local pd = scores and scores[playerKey]
            if type(pd) ~= "table" then
                return reply(false, { msg = "角色数据不存在" })
            end

            local gData = EnsureGachaData(pd)

            -- 背包容量预检查（最坏情况：所有结果都是装备，各占 1 格）
            local curBag = pd.bagItems or {}
            local bagCap = pd.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
            local bagFree = bagCap - #curBag
            if bagFree < count then
                return reply(false, { msg = "背包空间不足（剩余" .. bagFree .. "格），请先整理背包再抽奖" })
            end

            -- 扣费（仙石）
            serverCloud.money:Cost(userId, "spiritStone", cost, {
                ok = function()
                    -- 从独立 key 读取丹药
                    PillsHelper.Read(userId, function(pills, pillsErr)
                        if not pills then
                            reply(false, { msg = "丹药数据读取失败" })
                            return
                        end

                        -- 执行抽奖
                        math.randomseed(os.time() + (gData.totalPulls or 0))
                        local results = {}
                        local pity = gData.pityCounter or 0

                        for i = 1, count do
                            local result = RollOnce(pity)
                            results[#results + 1] = {
                                quality = result.quality,
                                label   = result.label,
                            }
                            if result.pityReset then
                                pity = 0
                            else
                                pity = pity + 1
                            end
                        end

                        -- 更新数据
                        gData.totalPulls = (gData.totalPulls or 0) + count
                        gData.pityCounter = pity

                        -- 处理抽到的物品（灵石直接发放，法宝加入背包，材料给丹药）
                        local lingStoneGained = 0
                        local bagItems = pd.bagItems or {}
                        local equipGenerated = {}
                        local pillsGenerated = {}

                        for _, r in ipairs(results) do
                            if r.quality == "lingshi" then
                                lingStoneGained = lingStoneGained + 5000
                                r.desc = "灵石x5000"
                            elseif r.quality == "material" then
                                -- 随机给一种丹药
                                local pick = GACHA_PILL_POOL[math.random(#GACHA_PILL_POOL)]
                                AddPillToList(pills, pick)
                                r.desc = pick.name .. "x" .. pick.count
                                pillsGenerated[#pillsGenerated + 1] = pick.name
                            else
                                -- 法宝：生成实际装备加入背包
                                local equip = GenerateGachaEquip(r.quality)
                                bagItems[#bagItems + 1] = equip
                                local qDef = DataItems.QUALITY[r.quality]
                                r.desc = equip.name .. (qDef and ("(" .. qDef.label .. ")") or "")
                                r.equipName = equip.name
                                r.equipSlot = equip.subType
                                equipGenerated[#equipGenerated + 1] = equip.name
                            end
                        end

                        pd.bagItems = bagItems
                        pd.pills = nil  -- 从 blob 中清除

                        -- 并行保存
                        local sync = {}
                        local pendingOps = 0
                        local opsFinished = 0
                        local opsFailed = false

                        local function TryFinish()
                            opsFinished = opsFinished + 1
                            if opsFinished < pendingOps then return end
                            if opsFailed then
                                return reply(false, { msg = "抽奖结果保存失败" })
                            end
                            reply(true, {
                                results      = results,
                                count        = count,
                                cost         = cost,
                                totalPulls   = gData.totalPulls,
                                pityCounter  = gData.pityCounter,
                                lingStoneGained = lingStoneGained,
                            }, sync)
                        end

                        -- 保存独立 pills key
                        pendingOps = pendingOps + 1
                        PillsHelper.Write(userId, pills, function(pillsOk)
                            if not pillsOk then opsFailed = true end
                            TryFinish()
                        end, playerKey)

                        -- 保存 playerData（不含 pills）
                        pendingOps = pendingOps + 1
                        serverCloud:Set(userId, playerKey, pd, {
                            ok = function() TryFinish() end,
                            error = function() opsFailed = true; TryFinish() end,
                        })

                        -- 发放灵石（如有）
                        if lingStoneGained > 0 then
                            pendingOps = pendingOps + 1
                            serverCloud.money:Add(userId, "lingStone", lingStoneGained, {
                                ok = function() TryFinish() end,
                                error = function() opsFailed = true; TryFinish() end,
                            })
                        end

                        -- 同步背包和丹药到客户端
                        sync.bagItems = pd.bagItems
                        sync.pills    = pills  -- 从独立 key 读取的最新 pills

                        -- 查余额同步
                        pendingOps = pendingOps + 1
                        serverCloud.money:Get(userId, {
                            ok = function(moneys)
                                sync.lingStone = moneys and moneys["lingStone"] or 0
                                sync.spiritStone = moneys and moneys["spiritStone"] or 0
                                TryFinish()
                            end,
                            error = function() TryFinish() end,
                        })
                    end, playerKey) -- PillsHelper.Read
                end,
                error = function()
                    reply(false, { msg = "仙石不足（需要" .. cost .. "仙石）" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
