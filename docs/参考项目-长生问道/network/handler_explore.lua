-- ============================================================================
-- 《问道长生》探索处理器（服务端权威）
-- 职责：随机遭遇选择 + 采集掉落数量 + 战斗结算，服务端掷骰
-- Actions: explore_encounter, explore_settle, save_afk_stats
-- ============================================================================

local M = {}
M.Actions = {}

local DataItems  = require("data_items")
local DataWorld  = require("data_world")
local DataSkills = require("data_skills")

--- 品质标签获取（兼容新旧 key）
local function GetQualityLabel(quality)
    return DataItems.GetQualityLabel(quality)
end

-- ============================================================================
-- 历练道心奖励工具
-- ============================================================================

local function GetTodayStr()
    return os.date("%Y-%m-%d")
end

--- 尝试给予历练道心奖励，返回实际获得的道心数
--- 受每日上限约束，有概率触发
---@param playerData table
---@return number daoGained
local function TryExploreDaoReward(playerData)
    local chance = DataSkills.EXPLORE_DAO_CHANCE or 30
    if math.random(100) > chance then return 0 end

    local tier = playerData.tier or 1
    local cap  = DataSkills.GetDailyDaoHeartCap(tier)

    -- 初始化/重置每日追踪
    local today = GetTodayStr()
    local dd = playerData.daoDaily
    if type(dd) ~= "table" or dd.date ~= today then
        dd = { date = today, freeUsed = 0, daoGained = 0 }
        playerData.daoDaily = dd
    end

    local remaining = math.max(0, cap - (dd.daoGained or 0))
    if remaining <= 0 then return 0 end

    local range = DataSkills.EXPLORE_DAO_RANGE or { 1, 3 }
    local raw = math.random(range[1], range[2])
    local gain = math.min(raw, remaining)
    if gain <= 0 then return 0 end

    playerData.daoHeart = (playerData.daoHeart or 0) + gain
    dd.daoGained = (dd.daoGained or 0) + gain
    return gain
end

-- ============================================================================
-- 装备掉落生成（服务端权威）
-- ============================================================================

--- 根据区域和境界生成一件随机装备
---@param tier number 玩家境界
---@param areaId? string 区域ID（有则按区域概率，无则按 tier 兼容）
---@return table|nil 装备数据，nil 表示不掉落
local function TryGenerateEquipDrop(tier, areaId)
    -- 1. 判断是否触发掉落
    local dropRate = DataItems.GetEquipDropRate(tier)
    if math.random(100) > dropRate then
        return nil
    end

    -- 2. 随机选择槽位
    local slotKeys = DataItems.EQUIP_SLOT_KEYS
    local slot = slotKeys[math.random(#slotKeys)]
    local pool = DataItems.EQUIP_DROP_POOL[slot]
    if not pool or #pool == 0 then return nil end

    -- 3. 根据区域（优先）或 tier 确定品质概率，掷骰选品质
    local rates
    if areaId then
        local areaIndex = DataWorld.AREA_INDEX[areaId] or 1
        rates = DataItems.GetQualityRatesByArea(areaIndex)
    else
        rates = DataItems.GetQualityRates(tier)
    end
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

    -- 4. 从该品质中随机选一个基础装备
    local candidates = {}
    for _, e in ipairs(pool) do
        if e.quality == targetQuality then
            candidates[#candidates + 1] = e
        end
    end
    -- 如果该品质没装备，降级到 fanqi
    if #candidates == 0 then
        for _, e in ipairs(pool) do
            if e.quality == "fanqi" then
                candidates[#candidates + 1] = e
            end
        end
    end
    if #candidates == 0 then return nil end
    local base = candidates[math.random(#candidates)]

    -- 5. 生成主属性（V2：按槽位确定主属性类型）
    local slotDef = DataItems.GetSlotByKey(slot)
    local mainStatType = slotDef and slotDef.mainStat or "attack"
    local msMin, msMax = DataItems.GetMainStatRange(targetQuality, mainStatType)
    local mainStat = {
        type  = mainStatType,
        value = math.random(msMin, msMax),
    }

    -- 6. 生成副属性（V2：按品阶决定条数，从池中不重复抽取）
    local subStatCount = DataItems.SUB_STAT_COUNTS[targetQuality] or 1
    local subStats = {}
    local available = {}
    for _, s in ipairs(DataItems.EXTRA_STAT_POOL) do
        if s ~= mainStatType then  -- 排除与主属性相同的类型
            available[#available + 1] = s
        end
    end
    for _ = 1, subStatCount do
        if #available == 0 then break end
        local idx = math.random(#available)
        local statType = available[idx]
        table.remove(available, idx)
        local minVal, maxVal = DataItems.GetSubStatRange(statType, targetQuality)
        local sub = { type = statType, value = math.random(minVal, maxVal) }
        if statType == "elemDmg" then
            local elements = { "metal", "wood", "water", "fire", "earth" }
            sub.element = elements[math.random(#elements)]
        end
        subStats[#subStats + 1] = sub
    end

    -- 7. 组装装备数据（V2 结构）
    local equip = {
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
        mainStat   = mainStat,
        subStats   = subStats,
        dropTier   = tier,
        timestamp  = os.time(),
        desc       = "探索掉落",
        isEquip    = true,
    }

    return equip
end

--- Boss 专用装备掉落：更高掉落率 + 品质保底 + 额外掉落
---@param tier number 玩家境界
---@param bossData table Boss 配置 { dropRate, minQuality, extraDrop }
---@param areaId? string 区域ID
---@return table|nil 装备数据
local function TryGenerateBossEquipDrop(tier, bossData, areaId)
    -- Boss 使用自己的 dropRate（百分比），比普通怪高很多
    local dropRate = bossData.dropRate or 70
    if math.random(100) > dropRate then
        return nil
    end

    -- 随机选择槽位
    local slotKeys = DataItems.EQUIP_SLOT_KEYS
    local slot = slotKeys[math.random(#slotKeys)]
    local pool = DataItems.EQUIP_DROP_POOL[slot]
    if not pool or #pool == 0 then return nil end

    -- 根据区域（优先）或 tier 确定品质概率，掷骰选品质
    local rates
    if areaId then
        local areaIndex = DataWorld.AREA_INDEX[areaId] or 1
        rates = DataItems.GetQualityRatesByArea(areaIndex)
    else
        rates = DataItems.GetQualityRates(tier)
    end
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

    -- Boss 品质保底：不低于 minQuality（兼容旧key）
    local minQuality = bossData.minQuality or "lingbao"
    minQuality = DataItems.GetQualityKey(minQuality)
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
    -- 如果该品质没装备，向下找最近的品质
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

    -- 生成主属性（V2：按槽位确定主属性类型）
    local slotDef = DataItems.GetSlotByKey(slot)
    local mainStatType = slotDef and slotDef.mainStat or "attack"
    local msMin, msMax = DataItems.GetMainStatRange(targetQuality, mainStatType)
    -- Boss 掉落主属性偏高：取值范围上移 20%
    local bossBoost = math.floor((msMax - msMin) * 0.2)
    local mainStat = {
        type  = mainStatType,
        value = math.random(msMin + bossBoost, msMax),
    }

    -- 生成副属性（V2：Boss 额外 +1 词条）
    local subStatCount = (DataItems.SUB_STAT_COUNTS[targetQuality] or 1) + 1
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
        local minVal, maxVal = DataItems.GetSubStatRange(statType, targetQuality)
        -- Boss 额外加成：数值上移 15%
        local boost = math.floor((maxVal - minVal) * 0.15)
        local sub = { type = statType, value = math.random(minVal + boost, maxVal) }
        if statType == "elemDmg" then
            local elements = { "metal", "wood", "water", "fire", "earth" }
            sub.element = elements[math.random(#elements)]
        end
        subStats[#subStats + 1] = sub
    end

    -- 组装装备数据（V2 结构）
    local equip = {
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
        mainStat   = mainStat,
        subStats   = subStats,
        dropTier   = tier,
        timestamp  = os.time(),
        desc       = "Boss掉落",
        isEquip    = true,
    }

    return equip
end

--- 检查装备是否应被自动卖出
---@param equip table 装备数据
---@param playerData table 玩家数据（含 autoSellBelow 配置）
---@return boolean shouldSell, number sellPrice
local function ShouldAutoSell(equip, playerData)
    local autoSellBelow = playerData.autoSellBelow
    if not autoSellBelow or autoSellBelow == "" or autoSellBelow == "none" then
        return false, 0
    end
    -- 品质排名映射
    local qualityRank = {}
    for i, q in ipairs(DataItems.QUALITY_ORDER) do qualityRank[q] = i end
    local equipRank = qualityRank[equip.quality] or 1
    local thresholdRank = qualityRank[autoSellBelow] or 0
    if equipRank <= thresholdRank then
        local price = DataItems.EQUIP_SELL_PRICE[equip.quality] or 10
        return true, price
    end
    return false, 0
end

--- 生成装备描述文本（用于战斗日志）
---@param equip table
---@return string
local function FormatEquipDrop(equip)
    local ql = GetQualityLabel(equip.quality)
    local slotDef = DataItems.GetSlotByKey(equip.slot)
    local slotLabel = slotDef and slotDef.label or "装备"
    local parts = { "[" .. ql .. "]" .. equip.name .. "（" .. slotLabel .. "）" }
    -- 基础属性
    if (equip.baseAtk or 0) > 0 then parts[#parts + 1] = "攻击+" .. equip.baseAtk end
    if (equip.baseDef or 0) > 0 then parts[#parts + 1] = "防御+" .. equip.baseDef end
    if (equip.baseCrit or 0) > 0 then parts[#parts + 1] = "暴击+" .. equip.baseCrit end
    if (equip.baseSpd or 0) > 0 then parts[#parts + 1] = "速度+" .. equip.baseSpd end
    -- 主属性（V2）
    if equip.mainStat then
        local label = DataItems.STAT_LABEL[equip.mainStat.type] or equip.mainStat.type
        local isPct = DataItems.STAT_IS_PERCENT and DataItems.STAT_IS_PERCENT[equip.mainStat.type]
        parts[#parts + 1] = label .. "+" .. equip.mainStat.value .. (isPct and "%" or "")
    end
    -- 副属性（V2）
    for _, sub in ipairs(equip.subStats or {}) do
        local label = DataItems.STAT_LABEL[sub.type] or sub.type
        if sub.type == "elemDmg" and sub.element then
            local elemLabels = { metal = "金", wood = "木", water = "水", fire = "火", earth = "土" }
            label = (elemLabels[sub.element] or "") .. "属性伤害"
        end
        local isPct = DataItems.STAT_IS_PERCENT and DataItems.STAT_IS_PERCENT[sub.type]
        parts[#parts + 1] = label .. "+" .. sub.value .. (isPct and "%" or "")
    end
    -- 兼容旧格式 extraStats
    if equip.extraStats then
        for _, es in ipairs(equip.extraStats) do
            local label = DataItems.STAT_LABEL[es.stat] or es.stat
            parts[#parts + 1] = label .. "+" .. es.value
        end
    end
    return table.concat(parts, " ")
end

-- 待结算战斗缓存（防伪造）
---@type table<number, { token: string, encName: string, reward: number, expireAt: number }>
local pendingCombat_ = {}
local SETTLE_TOKEN_EXPIRE = 120

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 按权重随机选择
---@param list table[]
---@return table
local function PickRandom(list)
    local total = 0
    for _, e in ipairs(list) do total = total + (e.weight or 10) end
    local r = math.random(1, total)
    local acc = 0
    for _, e in ipairs(list) do
        acc = acc + (e.weight or 10)
        if r <= acc then return e end
    end
    return list[#list]
end

--- 根据区域+难度+境界生成遭遇
---@param areaId string
---@param difficulty string
---@param tier number
---@return table encounter { type="combat"/"gather"/"nothing", ... }
local function GenerateAreaEncounter(areaId, difficulty, tier)
    local areaEnc = DataWorld.GetAreaEncounters(areaId)
    if not areaEnc then
        return { type = "nothing", name = "无事发生" }
    end

    local diffConf = DataWorld.GetDifficulty(difficulty)
    local statMul = diffConf and diffConf.statMul or 1.0
    local rewardMul = diffConf and diffConf.rewardMul or 1.0
    local dropMul = diffConf and diffConf.dropMul or 1.0

    -- 构建加权候选池：combat + gather + nothing
    local pool = {}
    for _, c in ipairs(areaEnc.combat or {}) do
        pool[#pool + 1] = { type = "combat", data = c, weight = c.weight or 10 }
    end
    for _, g in ipairs(areaEnc.gather or {}) do
        pool[#pool + 1] = { type = "gather", data = g, weight = g.weight or 10 }
    end
    local nw = areaEnc.nothingWeight or 6
    pool[#pool + 1] = { type = "nothing", data = { name = "无事发生" }, weight = nw }

    -- Boss 判定（普通2%，精英2.5%，困难3%）
    local bossChance = 2
    if difficulty == "elite" then bossChance = 2.5
    elseif difficulty == "hard" then bossChance = 3 end
    if areaEnc.boss and math.random(100) <= bossChance then
        local boss = areaEnc.boss
        -- 用区域普通怪的平均属性作基底
        local avgAtk, avgDef, avgHP, avgReward = 0, 0, 0, 0
        local combatList = areaEnc.combat or {}
        for _, c in ipairs(combatList) do
            avgAtk = avgAtk + c.baseAtk
            avgDef = avgDef + c.baseDef
            avgHP  = avgHP  + c.baseHP
            avgReward = avgReward + c.reward
        end
        local n = math.max(1, #combatList)
        avgAtk = avgAtk / n
        avgDef = avgDef / n
        avgHP  = avgHP  / n
        avgReward = avgReward / n

        local rndAtk = 0.9 + math.random() * 0.2
        local rndDef = 0.9 + math.random() * 0.2
        local rndHP  = 0.95 + math.random() * 0.1
        return {
            type   = "combat",
            isBoss = true,
            name   = boss.name,
            atk    = math.floor(avgAtk * (boss.atkMul or 3) * (1 + tier * 0.3) * statMul * rndAtk),
            def    = math.floor(avgDef * (boss.defMul or 2) * (1 + tier * 0.2) * statMul * rndDef),
            hp     = math.floor(avgHP  * (boss.hpMul or 10) * (1 + tier * 0.5) * statMul * rndHP),
            reward = math.floor(avgReward * (boss.hpMul or 10) * rewardMul * 0.5),
            bossData = boss,
        }
    end

    -- 按权重随机选类型
    local picked = PickRandom(pool)

    if picked.type == "nothing" then
        return { type = "nothing", name = "无事发生" }
    end

    if picked.type == "gather" then
        local g = picked.data
        local min = g.dropCount[1]
        local max = g.dropCount[2]
        -- 难度提升掉落数量
        max = math.floor(max * dropMul)
        if max < min then max = min end
        return {
            type      = "gather",
            name      = g.name,
            drop      = g.drop,
            dropCount = { min, max },
        }
    end

    -- combat: 动态计算属性
    local c = picked.data
    local rndAtk = 0.8 + math.random() * 0.4
    local rndDef = 0.8 + math.random() * 0.4
    local rndHP  = 0.9 + math.random() * 0.2
    return {
        type   = "combat",
        isBoss = false,
        name   = c.name,
        atk    = math.floor(c.baseAtk * (1 + tier * 0.3) * statMul * rndAtk),
        def    = math.floor(c.baseDef * (1 + tier * 0.2) * statMul * rndDef),
        hp     = math.floor(c.baseHP  * (1 + tier * 0.5) * statMul * rndHP),
        reward = math.floor(c.reward * rewardMul),
    }
end

--- 在背包中添加物品（堆叠同名）
---@param bagItems table[]
---@param itemName string
---@param count number
local function AddToBag(bagItems, itemName, count)
    for _, item in ipairs(bagItems) do
        if item.name == itemName then
            item.count = (item.count or 0) + count
            return
        end
    end
    bagItems[#bagItems + 1] = {
        name   = itemName,
        count  = count,
        rarity = "common",
        desc   = "探索获得",
    }
end

---@param userId number
---@param enc table
---@param tier number 玩家境界
---@return string
local function CreatePendingCombat(userId, enc, tier)
    local token = tostring(userId) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
    pendingCombat_[userId] = {
        token    = token,
        encName  = enc.name or "未知",
        reward   = math.max(0, math.floor(enc.reward or 0)),
        tier     = tier or 1,
        expireAt = os.time() + SETTLE_TOKEN_EXPIRE,
    }
    return token
end

---@param userId number
---@param token string
---@return table|nil, string|nil
local function ConsumePendingCombat(userId, token)
    local pending = pendingCombat_[userId]
    pendingCombat_[userId] = nil

    if not pending then
        return nil, "无待结算战斗，请重新探索"
    end
    if not token or token == "" then
        return nil, "缺少结算令牌"
    end
    if token ~= pending.token then
        return nil, "结算令牌无效"
    end
    if os.time() > (pending.expireAt or 0) then
        return nil, "结算已过期，请重新探索"
    end
    return pending, nil
end

-- ============================================================================
-- Action: explore_encounter — 服务端生成遭遇 + 采集类直接结算
-- params: { playerKey: string }
-- 返回:
--   gather:  { type, encName, drop, dropCount, bagItems }
--   combat:  { type, encName, atk, def, hp, reward } (客户端播放战斗动画)
--   nothing: { type, encName }
-- ============================================================================

M.Actions["explore_encounter"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local areaId    = params.areaId or "yunwu"
    local difficulty = params.difficulty or "normal"

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    -- 验证区域和难度合法性
    local areaConf = DataWorld.GetArea(areaId)
    if not areaConf then
        reply(false, { msg = "无效区域" })
        return
    end
    local diffConf = DataWorld.GetDifficulty(difficulty)
    if not diffConf then
        reply(false, { msg = "无效难度" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores, iscores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            -- 检查气血
            if (playerData.hp or 0) <= 0 then
                reply(false, { msg = "气血耗尽，无法探索" })
                return
            end

            -- 检查区域解锁
            local tier = playerData.tier or 1
            local sub  = playerData.sub or 1
            local unlocked, lockReason = DataWorld.IsAreaUnlocked(areaId, tier, sub)
            if not unlocked then
                reply(false, { msg = lockReason or "区域未解锁" })
                return
            end

            -- 服务端生成区域遭遇
            local enc = GenerateAreaEncounter(areaId, difficulty, tier)

            if enc.type == "nothing" then
                pendingCombat_[userId] = nil
                print("[Explore] nothing uid=" .. tostring(userId) .. " area=" .. areaId)
                reply(true, { encounterType = "nothing", encounterName = enc.name })

            elseif enc.type == "gather" then
                pendingCombat_[userId] = nil
                local min = enc.dropCount[1]
                local max = enc.dropCount[2]
                local count = math.random(min, max)

                local bagItems = playerData.bagItems or {}
                playerData.bagItems = bagItems

                -- 容量检查：如果物品不可堆叠（背包中无同名）且已满，则拒绝
                local bagCap = playerData.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
                local hasExisting = false
                for _, bi in ipairs(bagItems) do
                    if bi.name == enc.drop then hasExisting = true; break end
                end
                if not hasExisting and #bagItems >= bagCap then
                    reply(false, { msg = "储物戒已满（" .. #bagItems .. "/" .. bagCap .. "），请先整理背包", bagFull = true })
                    return
                end

                AddToBag(bagItems, enc.drop, count)

                -- 保存
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        print("[Explore] gather " .. enc.drop .. "x" .. count
                            .. " uid=" .. tostring(userId))
                        reply(true, {
                            encounterType = "gather",
                            encounterName = enc.name,
                            dropName      = enc.drop,
                            dropCount     = count,
                        }, {
                            bagItems = bagItems,
                        })
                    end,
                    error = function(code, reason)
                        reply(false, { msg = "保存失败" })
                    end,
                })

            elseif enc.type == "combat" then
                -- 战斗：返回怪物数据，客户端播放战斗动画后调用 explore_settle
                -- 在 pending 中额外保存 isBoss 和 bossData 用于结算
                local settleToken = CreatePendingCombat(userId, enc, tier)
                -- 追加 boss 信息和区域ID到 pending
                if pendingCombat_[userId] then
                    pendingCombat_[userId].areaId = areaId
                    if enc.isBoss then
                        pendingCombat_[userId].isBoss = true
                        pendingCombat_[userId].bossData = enc.bossData
                    end
                end
                print("[Explore] combat " .. enc.name
                    .. (enc.isBoss and " [BOSS]" or "")
                    .. " uid=" .. tostring(userId) .. " area=" .. areaId
                    .. " diff=" .. difficulty)
                reply(true, {
                    encounterType = "combat",
                    encounterName = enc.name,
                    settleToken = settleToken,
                    enemy = {
                        name    = enc.name,
                        atk     = enc.atk,
                        def     = enc.def,
                        hp      = enc.hp,
                        reward  = enc.reward,
                        settleToken = settleToken,
                        isBoss  = enc.isBoss or false,
                        areaId  = areaId,
                        difficulty = difficulty,
                    },
                })
            end
        end,
        error = function(code, reason)
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: explore_settle — 战斗结算（战斗由客户端模拟，服务端验证+发放）
-- params: { playerKey: string, win: bool, settleToken: string }
-- 说明：客户端仅上报胜负 + 一次性令牌，奖励与怪物信息均以服务端缓存为准
-- ============================================================================

M.Actions["explore_settle"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local win       = params.win and true or false
    local settleToken = params.settleToken or ""

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    local pending, pendingErr = ConsumePendingCombat(userId, settleToken)
    if not pending then
        reply(false, { msg = pendingErr or "结算失败，请重新探索" })
        return
    end
    local encName = pending.encName
    local reward  = pending.reward or 0
    local tier    = pending.tier or 1

    local isBoss   = pending.isBoss or false
    local bossData = pending.bossData
    local pendingAreaId = pending.areaId

    if win and reward > 0 then
        -- 胜利：通过 serverCloud.money 发放灵石（原子操作）
        serverCloud.money:Add(userId, "lingStone", math.floor(reward), {
            ok = function()
                -- 灵石到账后，尝试灵宠捕获
                local HandlerPet = require("network.handler_pet")
                local tryCapture = HandlerPet.Actions["pet_try_capture"]
                tryCapture(userId, { playerKey = playerKey, areaId = pendingAreaId }, function(petOk, petData, petSync)
                    -- 尝试装备掉落（Boss 使用专属掉落率和品质保证）
                    local droppedEquip
                    if isBoss and bossData then
                        droppedEquip = TryGenerateBossEquipDrop(tier, bossData, pendingAreaId)
                    else
                        droppedEquip = TryGenerateEquipDrop(tier, pendingAreaId)
                    end

                    -- Boss 额外掉落物品（灵草、丹方碎片等）
                    local bossExtraDrops = {}
                    if isBoss and bossData and bossData.extraDrop then
                        for _, ed in ipairs(bossData.extraDrop) do
                            local chance = ed.chance or 100
                            if math.random(100) <= chance then
                                local cnt = ed.count or 1
                                bossExtraDrops[#bossExtraDrops + 1] = {
                                    name  = ed.name,
                                    count = cnt,
                                }
                            end
                        end
                    end

                    -- 仙界区域普通战斗：按 immortalDrop 概率掉落仙灵丹/仙元丹/大罗仙丹
                    if not isBoss then
                        local areaConf = pendingAreaId and DataWorld.GetArea(pendingAreaId)
                        if areaConf and areaConf.isImmortal and areaConf.immortalDrop then
                            local id = areaConf.immortalDrop
                            if math.random(100) <= (id.rate or 25) then
                                local cnt = math.random(id.countMin or 1, id.countMax or 1)
                                bossExtraDrops[#bossExtraDrops + 1] = { name = id.name, count = cnt }
                            end
                        end
                    end

                    -- 闭包变量：无bag写入时由统计写入路径设置
                    local cachedAfkStats_ = nil
                    local cachedDaoGain_  = 0
                    local cachedDaoDaily_ = nil
                    local cachedDaoHeart_ = nil

                    -- 内部函数：完成回复（装备已处理或无装备）
                    -- autoSoldEquipInfo: 自动卖出的装备（可选）
                    -- autoSoldPrice: 自动卖出获得的灵石（可选）
                    local function FinishReply(equipSaved, autoSoldEquipInfo, autoSoldPrice)
                        serverCloud.money:Get(userId, {
                            ok = function(moneys)
                                local balance = moneys and moneys["lingStone"] or 0
                                local bossLabel = isBoss and "[Boss] " or ""
                                local resultData = {
                                    win     = true,
                                    encName = encName,
                                    isBoss  = isBoss,
                                    reward  = reward,
                                    balance = balance,
                                    msg     = bossLabel .. "战胜" .. encName .. "，获得灵石" .. reward,
                                }
                                local sync = {
                                    lingStone   = balance,
                                    spiritStone = moneys and moneys["spiritStone"] or 0,
                                }

                                -- 附加灵宠捕获结果
                                if petOk and petData and petData.captured then
                                    resultData.petCaptured = true
                                    if petData.duplicate then
                                        resultData.petMsg = "遇到野生" .. (petData.petName or "灵宠")
                                            .. "，但已拥有，获得灵宠经验+" .. (petData.bonusExp or 50)
                                    else
                                        local blLabel = petData.bloodlineLabel or "凡兽"
                                        resultData.petMsg = "捕获了野生" .. (petData.petName or "灵宠")
                                            .. "（" .. blLabel .. "）"
                                    end
                                    if petSync then
                                        for k, v in pairs(petSync) do sync[k] = v end
                                    end
                                end

                                -- 附加装备掉落结果
                                if equipSaved and droppedEquip then
                                    resultData.equipDrop = droppedEquip
                                    resultData.equipMsg = "获得装备: " .. FormatEquipDrop(droppedEquip)
                                end

                                -- 附加自动卖结果
                                if autoSoldEquipInfo then
                                    local ql = GetQualityLabel(autoSoldEquipInfo.quality)
                                    resultData.autoSold = true
                                    resultData.autoSoldEquip = autoSoldEquipInfo.name
                                    resultData.autoSoldQuality = ql
                                    resultData.autoSoldPrice = autoSoldPrice or 0
                                    resultData.autoSoldMsg = "自动回收[" .. ql .. "]"
                                        .. autoSoldEquipInfo.name .. "，获得灵石+"
                                        .. (autoSoldPrice or 0)
                                end

                                -- 附加 Boss 额外掉落
                                if #bossExtraDrops > 0 then
                                    resultData.bossExtraDrops = bossExtraDrops
                                    local parts = {}
                                    for _, ed in ipairs(bossExtraDrops) do
                                        parts[#parts + 1] = ed.name .. "x" .. ed.count
                                    end
                                    resultData.bossExtraMsg = "Boss额外掉落: " .. table.concat(parts, "、")
                                end

                                -- 附加历练道心奖励
                                if cachedDaoGain_ and cachedDaoGain_ > 0 then
                                    resultData.daoGain = cachedDaoGain_
                                    resultData.daoMsg = "感悟天地，道心+" .. cachedDaoGain_
                                end

                                print("[Explore] combat_win " .. encName
                                    .. (isBoss and " [BOSS]" or "")
                                    .. " reward=" .. reward
                                    .. " uid=" .. tostring(userId)
                                    .. " balance=" .. balance
                                    .. (equipSaved and (" equip=" .. droppedEquip.name) or "")
                                    .. (#bossExtraDrops > 0 and (" extra=" .. #bossExtraDrops) or "")
                                    .. (cachedDaoGain_ > 0 and (" dao+" .. cachedDaoGain_) or ""))

                                -- 如果有装备或额外掉落写入了背包，读取最新 bagItems 同步
                                local hasBagChanges = equipSaved or #bossExtraDrops > 0
                                if hasBagChanges then
                                    serverCloud:Get(userId, playerKey, {
                                        ok = function(scores2)
                                            local pd2 = scores2 and scores2[playerKey]
                                            if type(pd2) == "table" then
                                                sync.bagItems = pd2.bagItems
                                                sync.afkStats = pd2.afkStats
                                                sync.daoHeart = pd2.daoHeart
                                                sync.daoDaily = pd2.daoDaily
                                            end
                                            reply(true, resultData, sync)
                                        end,
                                        error = function()
                                            reply(true, resultData, sync)
                                        end,
                                    })
                                else
                                    if cachedAfkStats_ then
                                        sync.afkStats = cachedAfkStats_
                                    end
                                    if cachedDaoGain_ > 0 then
                                        sync.daoHeart = cachedDaoHeart_
                                        sync.daoDaily = cachedDaoDaily_
                                    end
                                    reply(true, resultData, sync)
                                end
                            end,
                            error = function()
                                reply(true, {
                                    win = true, encName = encName, reward = reward,
                                    msg = "战胜" .. encName .. "，获得灵石" .. reward,
                                })
                            end,
                        })
                    end

                    -- 如果有装备掉落或 Boss 额外掉落，写入玩家背包（同时更新统计）
                    -- 否则也需要单独读写 playerData 来更新统计
                    local needBagWrite = droppedEquip or #bossExtraDrops > 0
                    if needBagWrite then
                        serverCloud:Get(userId, playerKey, {
                            ok = function(scores, iscores)
                                local playerData = scores and scores[playerKey]
                                if type(playerData) ~= "table" then
                                    FinishReply(false)
                                    return
                                end
                                local bagItems = playerData.bagItems or {}
                                playerData.bagItems = bagItems

                                -- 战斗统计
                                local afkStats = playerData.afkStats or {}
                                playerData.afkStats = afkStats
                                afkStats.totalBattles = (afkStats.totalBattles or 0) + 1
                                afkStats.totalWins = (afkStats.totalWins or 0) + 1
                                afkStats.totalLingStone = (afkStats.totalLingStone or 0) + reward
                                if isBoss then
                                    afkStats.bossKills = (afkStats.bossKills or 0) + 1
                                end

                                -- 历练道心奖励（概率触发，受每日上限约束）
                                local exploreDaoGain = TryExploreDaoReward(playerData)
                                cachedDaoGain_  = exploreDaoGain
                                cachedDaoDaily_ = playerData.daoDaily
                                cachedDaoHeart_ = playerData.daoHeart

                                -- 装备掉落处理：检查自动卖 + 容量防护
                                local autoSoldEquip = nil
                                local autoSellPrice = 0
                                local bagCap = playerData.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
                                if droppedEquip then
                                    local shouldSell, price = ShouldAutoSell(droppedEquip, playerData)
                                    -- 容量防护：背包已满且未自动回收 → 强制回收为灵石
                                    if not shouldSell and #bagItems >= bagCap then
                                        shouldSell = true
                                        price = DataItems.EQUIP_SELL_PRICE[droppedEquip.quality] or 10
                                        print("[Explore] bag_full forced auto-sell " .. droppedEquip.name
                                            .. " uid=" .. tostring(userId))
                                    end
                                    if shouldSell then
                                        autoSoldEquip = droppedEquip
                                        autoSellPrice = price
                                        afkStats.totalEquipDrops = (afkStats.totalEquipDrops or 0) + 1
                                        afkStats.totalAutoSold = (afkStats.totalAutoSold or 0) + 1
                                        afkStats.totalAutoSoldLingStone = (afkStats.totalAutoSoldLingStone or 0) + price
                                        -- 不放入背包，后续通过 money:Add 发放灵石
                                    else
                                        bagItems[#bagItems + 1] = droppedEquip
                                        afkStats.totalEquipDrops = (afkStats.totalEquipDrops or 0) + 1
                                    end
                                end

                                -- Boss 额外掉落物品（堆叠同名）
                                for _, ed in ipairs(bossExtraDrops) do
                                    AddToBag(bagItems, ed.name, ed.count)
                                    afkStats.totalMatDrops = (afkStats.totalMatDrops or 0) + ed.count
                                end

                                serverCloud:Set(userId, playerKey, playerData, {
                                    ok = function()
                                        if droppedEquip then
                                            print("[Explore] equip_drop " .. droppedEquip.name
                                                .. " [" .. (droppedEquip.quality or "?") .. "]"
                                                .. (autoSoldEquip and (" AUTO_SOLD=" .. autoSellPrice) or "")
                                                .. " uid=" .. tostring(userId))
                                        end
                                        if #bossExtraDrops > 0 then
                                            print("[Explore] boss_extra_drops uid=" .. tostring(userId)
                                                .. " count=" .. #bossExtraDrops)
                                        end
                                        -- 自动卖：通过 money:Add 发放灵石
                                        if autoSoldEquip and autoSellPrice > 0 then
                                            serverCloud.money:Add(userId, "lingStone", autoSellPrice, {
                                                ok = function()
                                                    print("[Explore] auto_sell " .. autoSoldEquip.name
                                                        .. " +" .. autoSellPrice .. " uid=" .. tostring(userId))
                                                    FinishReply(not autoSoldEquip, autoSoldEquip, autoSellPrice)
                                                end,
                                                error = function()
                                                    FinishReply(not autoSoldEquip, autoSoldEquip, autoSellPrice)
                                                end,
                                            })
                                        else
                                            FinishReply(droppedEquip ~= nil)
                                        end
                                    end,
                                    error = function()
                                        FinishReply(false)
                                    end,
                                })
                            end,
                            error = function()
                                FinishReply(false)
                            end,
                        })
                    else
                        -- 无装备/额外掉落，但仍需更新统计
                        serverCloud:Get(userId, playerKey, {
                            ok = function(scores2)
                                local pd2 = scores2 and scores2[playerKey]
                                if type(pd2) ~= "table" then
                                    FinishReply(false)
                                    return
                                end
                                local afkStats = pd2.afkStats or {}
                                pd2.afkStats = afkStats
                                afkStats.totalBattles = (afkStats.totalBattles or 0) + 1
                                afkStats.totalWins = (afkStats.totalWins or 0) + 1
                                afkStats.totalLingStone = (afkStats.totalLingStone or 0) + reward
                                if isBoss then
                                    afkStats.bossKills = (afkStats.bossKills or 0) + 1
                                end
                                -- 历练道心奖励（概率触发，受每日上限约束）
                                local daoGain2 = TryExploreDaoReward(pd2)
                                cachedDaoGain_  = daoGain2
                                cachedDaoDaily_ = pd2.daoDaily
                                cachedDaoHeart_ = pd2.daoHeart
                                cachedAfkStats_ = pd2.afkStats
                                serverCloud:Set(userId, playerKey, pd2, {
                                    ok = function() FinishReply(false) end,
                                    error = function() FinishReply(false) end,
                                })
                            end,
                            error = function()
                                FinishReply(false)
                            end,
                        })
                    end
                end)
            end,
            error = function(code, reason)
                print("[Explore] money:Add failed uid=" .. tostring(userId) .. " " .. tostring(reason))
                reply(false, { msg = "奖励发放失败" })
            end,
        })
    else
        -- 败北：扣除气血 + 更新统计
        serverCloud:Get(userId, playerKey, {
            ok = function(scores, iscores)
                local playerData = scores and scores[playerKey]
                if type(playerData) ~= "table" then
                    reply(false, { msg = "玩家数据解析失败" })
                    return
                end

                local hpMax = playerData.hpMax or 800
                local hpLoss = math.floor(hpMax * 0.1)
                playerData.hp = math.max(0, (playerData.hp or 0) - hpLoss)

                -- 败北统计
                local afkStats = playerData.afkStats or {}
                playerData.afkStats = afkStats
                afkStats.totalBattles = (afkStats.totalBattles or 0) + 1
                afkStats.totalLosses = (afkStats.totalLosses or 0) + 1

                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        print("[Explore] combat_lose " .. encName
                            .. " hpLoss=" .. hpLoss
                            .. " uid=" .. tostring(userId))
                        reply(true, {
                            win    = false,
                            encName = encName,
                            hpLoss = hpLoss,
                            msg    = "败于" .. encName .. "，损失气血" .. hpLoss,
                        }, {
                            hp = playerData.hp,
                            afkStats = playerData.afkStats,
                        })
                    end,
                    error = function()
                        reply(false, { msg = "保存失败" })
                    end,
                })
            end,
            error = function()
                reply(false, { msg = "读取数据失败" })
            end,
        })
    end
end

-- ============================================================================
-- Action: save_afk_stats — 仅保存 afkStats 到 playerData（增量合并）
-- 避免客户端 force Save 整个 playerData 覆盖服务端已修改的 pills/bagItems 等
-- params: { playerKey, afkStats: table }
-- ============================================================================
M.Actions["save_afk_stats"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local afkStats  = params.afkStats
    if not playerKey or type(afkStats) ~= "table" then
        return reply(false, { msg = "参数缺失" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "角色数据读取失败" })
            end

            -- 仅更新 afkStats 字段，不触碰 pills/bagItems 等
            playerData.afkStats = afkStats

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    reply(true, {}, { afkStats = afkStats })
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
