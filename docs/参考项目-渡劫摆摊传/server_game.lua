-- ============================================================================
-- server_game.lua — 服务端游戏逻辑(权威)
-- 职责：驱动材料/制作/顾客/售卖/寿元/奇遇等全部经济循环
-- ============================================================================

---@diagnostic disable: undefined-global

local Config = require("data_config")
local MentorModule = require("server_mentor")
local cjson = cjson

local M = {}

-- ========== 依赖注入 ==========
local SendToClient_ = nil
local PlayerMgr_ = nil
local EVENTS_ = nil
local GetConnection_ = nil
local AllocatePlayerId_ = nil
local GetServerName_ = nil
-- GM 用户 ID 列表
local GM_USER_IDS = { ["1644503283"] = true, ["529757584"] = true }
local DEV_USER_ID = "1644503283"  -- 兼容 isDev 判断

-- ========== 版本管理 ==========
local CLOUD_REQUIRED_VERSION_KEY = "global_required_version"
local requiredVersion_ = ""  -- 服务端内存中缓存的最低版本号

-- ========== 调试白名单 ==========
local CLOUD_DEBUG_WHITELIST_KEY = "global_debug_whitelist"
local debugWhitelist_ = {}  -- { ["userId"] = true }

-- ========== 计时器常量 ==========
local MATERIAL_TICK       = 1.0
local CUSTOMER_SPAWN_BASE = 8.0
local AUTO_SELL_INTERVAL  = 5.0
local AUTO_REFINE_INTERVAL = 1.0
local LIFESPAN_TICK       = 1.0
local SYNC_INTERVAL       = 2.0
local OFFLINE_RATE        = 0.7
local OFFLINE_BASE_CAP    = 3 * 3600
local OFFLINE_AD_EXTEND   = 3600
local OFFLINE_AD_MAX      = 5
local DAILY_AD_LIMIT      = 3
local AD_LIMIT_OVERRIDE   = { dungeon_ticket = 1 }  -- 特定广告独立上限

-- ========== 每玩家运行时数据 ==========
---@type table<number, table> userId -> runtime
local runtimes_ = {}

local function createRuntime()
    return {
        materialTimer = 0,
        customerTimer = 0,
        -- autoSellTimer removed (replaced by price boost)
        autoRefineTimer = 0,
        lifespanTimer = 0,
        encounterTimer = 0,
        syncTimer = 0,
        customers = {},
        nextCustId = 1,
        craftQueue = {},
        pendingOffline = nil,
        servantTimer = 0,
        puppetTimer = 0,
        autoRepairTimer = 0,
        gameStarted = false, -- 玩家点击"进入游戏"后才置 true
        dungeonState = nil,  -- 秘境探险运行时状态(非持久化)
    }
end

-- GameInit 发送后的回调队列（确保 CHAT_HISTORY 在 GAME_INIT 之后发送）
local postInitCallbacks_ = {}  -- userId -> function

-- ========== 辅助函数 ==========

local function getTodayKey()
    return os.date("!%Y%m%d", os.time() + 8 * 3600)  -- UTC+8 北京时间零点刷新
end

local function checkDailyReset(s)
    local today = getTodayKey()
    if s.todayDate ~= today then
        s.todayDate = today
        s.todayEarned = 0
    end
    if s.dailyAdDate ~= today then
        s.dailyAdDate = today
        s.dailyAdCounts = {}
    end
    -- 聚宝阁每日限购重置
    if s.dailyShopDate ~= today then
        s.dailyShopDate = today
        s.dailyShopBuys = {}
    end
end

local function getRebirthBonus(s)
    local rb = Config.Rebirth
    return 1.0 + math.min(s.rebirthCount * rb.bonusPerRebirth, rb.maxBonus)
end

local function getTitleBonus(s)
    local bonus = 0
    local realmTitle = Config.GetRealmTitle(s.highestRealmEver or 1)
    if realmTitle then bonus = bonus + realmTitle.bonus end
    local rankTitle = Config.GetRankTitle(s.myTodayRank)
    if rankTitle then bonus = bonus + rankTitle.bonus end
    return 1.0 + bonus
end

--- 获取已装备法宝的加成
---@param s table 玩家状态
---@param bonusType string 加成类型
---@return number 总加成比例
local function getArtifactBonus(s, bonusType)
    return Config.GetArtifactBonus(s.equippedArtifacts, bonusType)
end

--- 法宝耐久磨损: 对已装备且 bonus.type 匹配的法宝累加 wearCount, 达阈值扣1点耐久
---@param userId number
---@param s table 玩家状态
---@param triggerType string 触发类型 ("sell_price"|"reputation"|"craft_speed"|"material_rate"|"lifespan"|"all")
---@param delta number 触发增量(默认1)
---@return boolean 是否有法宝耐久变化
local function wearArtifactByType(userId, s, triggerType, delta)
    if not s.equippedArtifacts or #s.equippedArtifacts == 0 then return false end
    local changed = false
    for _, eq in ipairs(s.equippedArtifacts) do
        local art = Config.GetArtifactById(eq.id)
        if art and art.bonus then
            local bt = art.bonus.type
            -- 匹配规则: 触发类型与法宝加成类型相同, 或法宝是 "all" 且触发为 sell_price
            local match = (bt == triggerType)
                or (bt == "all" and triggerType == "sell_price")
            if match and (eq.durability or Config.ArtifactDurability.max) > 0 then
                eq.wearCount = (eq.wearCount or 0) + (delta or 1)
                local threshold = Config.GetArtifactWearThreshold(bt)
                if eq.wearCount >= threshold then
                    eq.wearCount = eq.wearCount - threshold
                    eq.durability = math.max(0, (eq.durability or Config.ArtifactDurability.max) - 1)
                    -- 同步耐久到仓库(卸下再装备时保持一致)
                    if s.artifacts and s.artifacts[eq.id] then
                        s.artifacts[eq.id].durability = eq.durability
                        s.artifacts[eq.id].wearCount = eq.wearCount
                    end
                    changed = true
                    if eq.durability == 0 then
                        sendEvt(userId, "artifact_durability_zero", { artId = eq.id, name = art.name })
                    elseif eq.durability <= 20 then
                        sendEvt(userId, "artifact_durability_warn", { artId = eq.id, durability = eq.durability })
                    end
                end
            end
        end
    end
    return changed
end

--- 获取珍藏物品永久加成
---@param s table 玩家状态
---@param bonusType string 加成类型
---@return number 总加成比例
local function getCollectibleBonus(s, bonusType)
    return Config.GetCollectibleBonus(s.collectibles or {}, bonusType)
end

--- 获取风水阵加成
---@param s table 玩家状态
---@param bonusType string 加成类型(customer_speed/sell_price/craft_speed/material_rate/reputation)
---@return number 加成比例(0.0~)
local function getFengshuiBonus(s, bonusType)
    local fs = s.fengshui
    if not fs then return 0 end
    local totalBonus = 0
    for _, formation in ipairs(Config.FengshuiFormations) do
        if formation.bonusType == bonusType then
            local lvl = fs[formation.id] or 0
            totalBonus = totalBonus + Config.GetFengshuiBonus(lvl)
        end
    end
    -- 风水称号额外全局加成
    local totalLevel = 0
    for _, formation in ipairs(Config.FengshuiFormations) do
        totalLevel = totalLevel + (fs[formation.id] or 0)
    end
    local titleCfg = Config.GetFengshuiTitle(totalLevel)
    if titleCfg then
        totalBonus = totalBonus + titleCfg.bonus / #Config.FengshuiFormations -- 称号加成均分到各类型
    end
    return totalBonus
end

local function getProductPrice(s, prodCfg)
    local realmMul = Config.GetRealmPriceMultiplier(s.realmLevel)
    local priceMul = ((s.adPriceBoostEnd or 0) > os.time()) and 1.5 or 1.0
    local artBonus = 1.0 + getArtifactBonus(s, "sell_price")
    local collBonus = 1.0 + getCollectibleBonus(s, "sell_price")
    local fsBonus = 1.0 + getFengshuiBonus(s, "sell_price")
    return math.floor(prodCfg.price * realmMul * getRebirthBonus(s) * getTitleBonus(s) * priceMul * artBonus * collBonus * fsBonus)
end

local function getStallConfig(s)
    local lvl = math.min(s.stallLevel, #Config.StallLevels)
    return Config.StallLevels[lvl]
end

local function addXiuwei(s, amount, userId)
    s.xiuwei = s.xiuwei + amount
    -- 师徒修为分成：有师父时给师父分成
    if userId and s.masterId then
        MentorModule.DistributeToMaster(userId, s, amount)
    end
end

local function addLingshi(s, amount)
    checkDailyReset(s)
    local amt = math.floor(amount)
    s.lingshi = s.lingshi + amt
    -- 灵石下限保护: 不允许为负
    if s.lingshi < 0 then s.lingshi = 0 end
    -- 只有正收入才计入统计
    if amt > 0 then
        s.totalEarned = s.totalEarned + amt
        s.todayEarned = (s.todayEarned or 0) + amt
    end
    local threshold = Config.PassiveXiuweiPerLingshi or 50
    local xiuweiGain = math.floor(amount / threshold) * 10
    if xiuweiGain > 0 then addXiuwei(s, xiuweiGain) end
end

local function spendLingshi(s, amount)
    if s.lingshi >= amount then
        s.lingshi = s.lingshi - amount
        return true
    end
    return false
end

local function addMaterial(s, matId, amount)
    local current = s.materials[matId] or 0
    local mat = Config.GetMaterialById(matId) or Config.GetSynthesisRecipeById(matId)
    local cap = (mat and mat.cap) or 9999
    s.materials[matId] = math.min(cap, current + amount)
end

local function spendMaterial(s, matId, amount)
    if s.materials[matId] and s.materials[matId] >= amount then
        s.materials[matId] = s.materials[matId] - amount
        return true
    end
    return false
end

local function addProduct(s, prodId, amount)
    s.products[prodId] = (s.products[prodId] or 0) + amount
    s.totalCrafted = (s.totalCrafted or 0) + amount
end

local function sellProduct(s, prodId, amount)
    if s.products[prodId] and s.products[prodId] >= amount then
        s.products[prodId] = s.products[prodId] - amount
        s.totalSold = s.totalSold + amount
        return true
    end
    return false
end

local function drainLifespan(s, amount)
    if s.dead then return end
    s.lifespan = math.max(0, s.lifespan - amount)
    if s.lifespan <= 0 then
        if math.random() < 0.05 then
            s.lifespan = 100
            return "miracle"
        else
            s.dead = true
            return "dead"
        end
    end
    return nil
end

-- ========== 发送工具 ==========

local function sendEvt(userId, evtType, data)
    local vm = VariantMap()
    vm["Type"] = Variant(evtType)
    vm["DataJson"] = Variant(cjson.encode(data or {}))
    SendToClient_(userId, EVENTS_.GAME_EVT, vm)
end

local function sendSync(userId, s)
    local vm = VariantMap()
    vm["StateJson"] = Variant(cjson.encode(s))
    SendToClient_(userId, EVENTS_.GAME_SYNC, vm)
end

-- ========== 每日任务进度推进 ==========

--- 推进每日任务进度(在各逻辑点调用)
---@param s table 玩家状态
---@param taskType string 任务类型
---@param delta number 增量
local function advanceDailyTask(s, taskType, delta)
    if not s.dailyTasks then return end
    for _, task in ipairs(s.dailyTasks) do
        if task.type == taskType and not task.claimed then
            task.current = math.min(task.target, (task.current or 0) + delta)
        end
    end
end

--- 刷新每日任务(如果日期变更)
---@param s table
local function refreshDailyTasks(s)
    local today = getTodayKey()
    if s.dailyTaskDate ~= today then
        s.dailyTasks = Config.GenerateDailyTasks(s.realmLevel)
        s.dailyTaskDate = today
    end
end

-- ========== 口碑系统 ==========

--- 更新口碑值
---@param s table 玩家状态
---@param matched boolean 是否满足需求匹配
---@param purchased boolean 是否成功购买
local function updateReputation(s, matched, purchased)
    local gain = Config.ReputationGain
    -- 防御旧存档缺失 reputation 字段
    if s.reputation == nil then s.reputation = 100 end
    local artMul = 1.0 + getArtifactBonus(s, "reputation") + getFengshuiBonus(s, "reputation")
    if not purchased then
        -- 超时离开(惩罚不受法宝加成)
        s.reputation = math.max(0, s.reputation + gain.timeout)
        s.repStreak = 0
        return
    end
    if matched then
        s.reputation = math.min(Config.REPUTATION_MAX, s.reputation + math.floor(gain.matched * artMul))
        s.repStreak = (s.repStreak or 0) + 1
        -- 连击奖励
        if s.repStreak >= gain.streakAt then
            s.reputation = math.min(Config.REPUTATION_MAX, s.reputation + math.floor(gain.streakBonus * artMul))
            s.repStreak = 0
        end
    else
        s.reputation = math.min(Config.REPUTATION_MAX, s.reputation + math.floor(gain.unmatched * artMul))
        s.repStreak = 0
    end
end

-- ========== 顾客生成 ==========

local femaleHints = { "婶", "姐", "妹", "娘", "妇", "婆", "翠", "花", "女修", "老板娘" }
local function isFemaleByName(name)
    for _, hint in ipairs(femaleHints) do
        if name:find(hint) then return true end
    end
    return false
end

local function randomCustomerName(custType)
    local names = Config.CustomerNames[custType.id]
    if names and #names > 0 then return names[math.random(#names)] end
    return custType.name
end

local function randomWantProduct(realmIdx, isAscended)
    if math.random() < Config.CrossRealmDemandChance then
        local cross = {}
        for _, prod in ipairs(Config.Products) do
            if prod.unlockRealm == realmIdx + 1 then
                -- 飞升只跨境仙界商品，未飞升只跨境凡间商品
                local ok = isAscended and prod.celestial or (not isAscended and not prod.celestial)
                if ok then table.insert(cross, prod) end
            end
        end
        if #cross > 0 then return cross[math.random(#cross)], true end
    end
    local unlocked = {}
    for i, prod in ipairs(Config.Products) do
        if Config.IsProductUnlocked(i, realmIdx) then
            if isAscended then
                if prod.celestial then table.insert(unlocked, prod) end
            else
                if not prod.celestial then table.insert(unlocked, prod) end
            end
        end
    end
    if #unlocked == 0 then return nil, false end
    return unlocked[math.random(#unlocked)], false
end

local function generateDialogue(custType, wantProd, isCrossRealm)
    if isCrossRealm and wantProd then
        local t = Config.CrossRealmDialogues
        return string.format(t[math.random(#t)], wantProd.name)
    end
    local idle = Config.IdleChatDialogues[custType.id]
    if idle and #idle > 0 and math.random() < 0.30 then
        return idle[math.random(#idle)]
    end
    if not wantProd then return "随便看看" end
    if not custType.dialogues or #custType.dialogues == 0 then return "想买" .. wantProd.name end
    return string.format(custType.dialogues[math.random(#custType.dialogues)], wantProd.name)
end

local function getAvailableProducts(s)
    local result = {}
    local isAscended = (s.ascended == true)
    for i, prod in ipairs(Config.Products) do
        if Config.IsProductUnlocked(i, s.realmLevel) and (s.products[prod.id] or 0) > 0 then
            -- 飞升玩家只卖仙界商品，未飞升只卖凡间商品
            if isAscended then
                if prod.celestial then table.insert(result, prod) end
            else
                if not prod.celestial then table.insert(result, prod) end
            end
        end
    end
    return result
end

local function spawnCustomer(userId, s, rt)
    local stallCfg = getStallConfig(s)
    if #rt.customers >= stallCfg.queueLimit then return end
    local available = getAvailableProducts(s)
    if #available == 0 then return end

    -- 口碑系统: 根据口碑调整顾客类型权重
    local custType
    local rep = s.reputation or 100
    local adjusted = Config.GetReputationAdjustedWeights(rep)
    local totalW = 0
    for _, aw in ipairs(adjusted) do totalW = totalW + aw.weight end
    local roll = math.random() * totalW
    local accW = 0
    for _, aw in ipairs(adjusted) do
        accW = accW + aw.weight
        if roll <= accW then custType = aw.type; break end
    end
    if not custType then custType = Config.CustomerTypes[1] end

    local custName = randomCustomerName(custType)
    local isFemale = isFemaleByName(custName) or math.random() < 0.4
    local avatarKey
    if isFemale then
        avatarKey = custType.avatarF or custType.avatar
    elseif custType.avatarMList and #custType.avatarMList > 0 then
        avatarKey = custType.avatarMList[math.random(#custType.avatarMList)]
    else
        avatarKey = custType.avatar
    end

    local isAscended = (s.ascended == true)
    local wantProd, isCrossRealm = randomWantProduct(s.realmLevel, isAscended)
    local targetProd = available[math.random(#available)]
    local matched = false
    local crossRealmHint = nil

    if isCrossRealm then
        local nextRealm = Config.Realms[s.realmLevel + 1]
        if nextRealm then crossRealmHint = "突破" .. nextRealm.name .. "后可解锁" end
    else
        if wantProd then
            for _, prod in ipairs(available) do
                if prod.id == wantProd.id then
                    targetProd = wantProd
                    matched = true
                    break
                end
            end
        end
    end

    local canBargain = math.random() < (Config.BargainConfig.bargainChance or 0.30)
    local cust = {
        id = rt.nextCustId,
        typeId = custType.id,
        displayName = custName,
        avatarKey = avatarKey,
        dialogue = generateDialogue(custType, wantProd, isCrossRealm),
        wantProductId = wantProd and wantProd.id or nil,
        targetProductId = targetProd.id,
        matched = matched,
        isCrossRealm = isCrossRealm,
        crossRealmHint = crossRealmHint,
        buyTimer = custType.buyInterval,
        payMul = custType.payMul,
        canBargain = canBargain,
        state = "walking",
        walkProgress = 0,
    }
    rt.nextCustId = rt.nextCustId + 1
    table.insert(rt.customers, cust)

    sendEvt(userId, "customer_spawn", {
        id = cust.id,
        typeId = cust.typeId,
        displayName = cust.displayName,
        avatarKey = cust.avatarKey,
        dialogue = cust.dialogue,
        wantProductId = cust.wantProductId,
        targetProductId = cust.targetProductId,
        matched = cust.matched,
        isCrossRealm = cust.isCrossRealm,
        crossRealmHint = cust.crossRealmHint,
        buyTimer = cust.buyTimer,
        payMul = cust.payMul,
        canBargain = cust.canBargain,
    })
end

-- ========== 每玩家更新子系统 ==========

local function updateMaterials(s, rt, dt)
    rt.materialTimer = rt.materialTimer + dt
    if rt.materialTimer >= MATERIAL_TICK then
        rt.materialTimer = rt.materialTimer - MATERIAL_TICK
        local artBonus = 1.0 + getArtifactBonus(s, "material_rate")
        local fsMatBonus = 1.0 + getFengshuiBonus(s, "material_rate")
        for _, mat in ipairs(Config.Materials) do
            if not (mat.celestial and not s.ascended) then
                -- 珍藏物品: 各材料单独加成(material_rate_lingcao 等)
                local collMatBonus = 1.0 + getCollectibleBonus(s, "material_rate_" .. mat.id)
                addMaterial(s, mat.id, mat.rate / 60.0 * artBonus * collMatBonus * fsMatBonus)
            end
        end
    end
end

local function updateCraftQueue(userId, s, rt, dt)
    local craftSpeedMul = 1.0 + getArtifactBonus(s, "craft_speed") + getCollectibleBonus(s, "craft_speed") + getFengshuiBonus(s, "craft_speed")
    local i = 1
    while i <= #rt.craftQueue do
        local task = rt.craftQueue[i]
        task.remainTime = task.remainTime - dt * craftSpeedMul
        if task.remainTime <= 0 then
            addProduct(s, task.productId, 1)
            advanceDailyTask(s, "craft_count", 1)
            local prodCfg = Config.GetProductById(task.productId)
            sendEvt(userId, "craft_done", {
                productId = task.productId,
                productName = prodCfg and prodCfg.name or "?",
            })
            -- 法宝耐久磨损: 制作完成触发 craft_speed 类型
            wearArtifactByType(userId, s, "craft_speed", 1)
            table.remove(rt.craftQueue, i)
        else
            i = i + 1
        end
    end
    -- 同步到 state 供存档
    s.craftQueue = {}
    for _, task in ipairs(rt.craftQueue) do
        table.insert(s.craftQueue, {
            productId = task.productId,
            remainTime = task.remainTime,
            totalTime = task.totalTime,
        })
    end
end

local function updateCustomers(userId, s, rt, dt)
    local stallCfg = getStallConfig(s)
    local speedMul = stallCfg.speedMul * Config.GetRealmSpeedMultiplier(s.realmLevel)
    speedMul = speedMul * (1.0 + getFengshuiBonus(s, "customer_speed"))
    if s.adFlowBoostEnd > os.time() then speedMul = speedMul * 2.0 end

    local spawnInterval = CUSTOMER_SPAWN_BASE / speedMul
    rt.customerTimer = rt.customerTimer + dt
    if rt.customerTimer >= spawnInterval then
        rt.customerTimer = rt.customerTimer - spawnInterval
        spawnCustomer(userId, s, rt)
    end

    local i = 1
    while i <= #rt.customers do
        local cust = rt.customers[i]
        local shouldRemove = false

        if cust.state == "walking" then
            cust.walkProgress = cust.walkProgress + dt * 2.0
            if cust.walkProgress >= 1.0 then
                cust.walkProgress = 1.0
                cust.state = "buying"
            end
        elseif cust.state == "buying" then
            -- 讨价还价进行中: 暂停购买计时器
            if cust.bargaining then
                -- 不递减 buyTimer, 等待讨价结果
            elseif cust.buyTimer == 0 then
                cust.buyTimer = -1  -- 即时购买标记
            else
                cust.buyTimer = cust.buyTimer - dt
            end
            if cust.buyTimer <= 0 and not cust.bargaining then
                local prodCfg = Config.GetProductById(cust.targetProductId)
                local custType = Config.GetCustomerTypeById(cust.typeId)
                local buyCount = (custType and custType.buyCount) or 1
                local actualBuy = math.min(buyCount, s.products[cust.targetProductId] or 0)
                if prodCfg and actualBuy > 0 and sellProduct(s, prodCfg.id, actualBuy) then
                    local price = getProductPrice(s, prodCfg)
                    -- 口碑售价加成
                    local repLvl = Config.GetReputationLevel(s.reputation or 100)
                    local repPriceMul = 1.0 + (repLvl.priceBonus or 0)
                    local finalPrice = math.floor(price * cust.payMul * actualBuy * repPriceMul)
                    if cust.matched then
                        finalPrice = math.floor(finalPrice * Config.DemandMatchBonus)
                    end
                    -- 讨价还价倍率(如果已讨价)
                    if cust.bargainMul then
                        finalPrice = math.floor(finalPrice * cust.bargainMul)
                    end
                    addLingshi(s, finalPrice)
                    -- 口碑更新
                    updateReputation(s, cust.matched, true)
                    -- 每日任务进度
                    advanceDailyTask(s, "sell_count", actualBuy)
                    advanceDailyTask(s, "earn_lingshi", finalPrice)
                    PlayerMgr_.SetDirty(userId)
                    sendEvt(userId, "sale_done", {
                        custId = cust.id,
                        displayName = cust.displayName,
                        productId = prodCfg.id,
                        productName = prodCfg.name,
                        price = finalPrice,
                        matched = cust.matched,
                        lingshi = s.lingshi,
                        reputation = s.reputation,
                    })
                    -- 法宝耐久磨损: 售卖触发 sell_price/reputation 类型
                    wearArtifactByType(userId, s, "sell_price", actualBuy)
                    wearArtifactByType(userId, s, "reputation", actualBuy)
                else
                    -- 库存不足: 顾客静默离开，不扣口碑
                    -- (扣口碑仅限顾客超时/讨价失败等主动拒绝场景)
                end
                cust.state = "leaving"
                cust.walkProgress = 1.0
            end
        elseif cust.state == "leaving" then
            cust.walkProgress = cust.walkProgress - dt * 2.0
            if cust.walkProgress <= 0 then shouldRemove = true end
        end

        if shouldRemove then
            sendEvt(userId, "customer_leave", { custId = cust.id, reputation = s.reputation })
            table.remove(rt.customers, i)
        else
            i = i + 1
        end
    end
end

-- updateAutoSell removed: replaced by price boost (adPriceBoostEnd)

local function updateAutoRefine(userId, s, rt, dt)
    if not s.autoRefine then return end
    rt.autoRefineTimer = rt.autoRefineTimer + dt
    if rt.autoRefineTimer < AUTO_REFINE_INTERVAL then return end
    rt.autoRefineTimer = rt.autoRefineTimer - AUTO_REFINE_INTERVAL

    if s.realmLevel >= #Config.Realms then return end
    local nextRealm = Config.Realms[s.realmLevel + 1]
    if s.xiuwei >= nextRealm.xiuwei then return end

    local cfg = Config.AbsorbConfig[s.realmLevel]
    if not cfg then return end
    local cost = math.floor(cfg.amount * cfg.ratio)
    if s.lingshi >= cost then
        s.lingshi = s.lingshi - cost
        addXiuwei(s, cfg.amount, userId)
    end
end

-- ========== 法宝自动修复(服务端) ==========
local AUTO_REPAIR_INTERVAL = 5.0
local AUTO_REPAIR_DURABILITY_THRESHOLD = 50

local function updateAutoRepairArtifacts(userId, s, rt, dt)
    if not s.autoRepairArtifacts then return end
    if not s.equippedArtifacts or #s.equippedArtifacts == 0 then return end
    rt.autoRepairTimer = rt.autoRepairTimer + dt
    if rt.autoRepairTimer < AUTO_REPAIR_INTERVAL then return end
    rt.autoRepairTimer = rt.autoRepairTimer - AUTO_REPAIR_INTERVAL

    local maxDur = Config.ArtifactDurability.max
    local repaired = false
    for _, eq in ipairs(s.equippedArtifacts) do
        local dur = eq.durability or maxDur
        if dur < AUTO_REPAIR_DURABILITY_THRESHOLD then
            local level = eq.level or 1
            local cost = Config.GetArtifactAutoRepairCost(eq.id, level)
            if s.lingshi >= cost then
                spendLingshi(s, cost)
                eq.durability = maxDur
                eq.wearCount = 0
                -- 同步到仓库
                if s.artifacts and s.artifacts[eq.id] then
                    s.artifacts[eq.id].durability = maxDur
                    s.artifacts[eq.id].wearCount = 0
                end
                repaired = true
            end
        end
    end
    if repaired then
        PlayerMgr_.SetDirty(userId)
        sendSync(userId, s)
    end
end

-- ========== 灵童自动操作(服务端) ==========
local SERVANT_INTERVAL = 2.0
local PUPPET_INTERVAL  = 3.0

local function updateFieldServant(userId, s, rt, dt)
    local sv = s.fieldServant
    if not sv or sv.tier <= 0 then return end
    if sv.paused then return end
    if os.time() >= sv.expireTime then
        sv.tier = 0
        sv.expireTime = 0
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "servant_expired", {})
        return
    end
    rt.servantTimer = rt.servantTimer + dt
    if rt.servantTimer < SERVANT_INTERVAL then return end
    rt.servantTimer = rt.servantTimer - SERVANT_INTERVAL

    local cfg = Config.FieldServants[sv.tier]
    if not cfg then return end
    local abilities = cfg.abilities
    local speedBonus = abilities.speedBonus or 0
    local lvl = math.min(s.fieldLevel or 1, #Config.FieldLevels)
    local maxPlots = Config.FieldLevels[lvl].plots

    local changed = false

    -- 自动收获
    if abilities.harvest then
        for i = 1, maxPlots do
            local plot = s.fieldPlots[i]
            if plot and plot.cropId and plot.cropId ~= "" then
                local crop = nil
                for _, c in ipairs(Config.Crops) do if c.id == plot.cropId then crop = c; break end end
                if crop then
                    local actualGrowTime = crop.growTime / (1 + speedBonus)
                    local elapsed = os.time() - plot.plantTime
                    if elapsed >= actualGrowTime then
                        for matId, amount in pairs(crop.yield) do
                            addMaterial(s, matId, amount)
                        end
                        s.fieldPlots[i] = {}
                        advanceDailyTask(s, "harvest", 1)
                        -- 法宝耐久磨损: 收获触发 material_rate 类型
                        wearArtifactByType(userId, s, "material_rate", 1)
                        PlayerMgr_.SetDirty(userId)
                        changed = true
                        print("[Servant] Auto-harvest plot " .. i .. " cropId=" .. plot.cropId)
                    end
                end
            end
        end
    end

    -- 自动种植(tier>=2, 支持分田种植)
    if abilities.plant then
        local plotCrops = sv.plotCrops  -- 分田配置 {[1]="lingcao_seed", [2]="lingzhi_seed", ...}
        local defaultCrop = sv.plantCrop or "lingcao_seed"
        for i = 1, maxPlots do
            local plot = s.fieldPlots[i]
            if not plot or not plot.cropId or plot.cropId == "" then
                -- 优先使用分田配置, 回退到全局配置
                local cropId = (plotCrops and plotCrops[tostring(i)]) or defaultCrop
                local crop = nil
                for _, c in ipairs(Config.Crops) do if c.id == cropId then crop = c; break end end
                if crop and s.lingshi >= crop.cost then
                    s.lingshi = s.lingshi - crop.cost
                    s.fieldPlots[i] = { cropId = cropId, plantTime = os.time() }
                    PlayerMgr_.SetDirty(userId)
                    changed = true
                    print("[Servant] Auto-plant plot " .. i .. " cropId=" .. cropId)
                end
            end
        end
    end

    -- 灵童操作后同步 fieldPlots 给客户端
    if changed then
        sendEvt(userId, "servant_field_sync", {
            fieldPlots = s.fieldPlots,
            materials = s.materials,
            lingshi = s.lingshi,
        })
    end
end

-- ========== 炼器傀儡自动制作(服务端) ==========
local function updateCraftPuppet(userId, s, rt, dt)
    local pp = s.craftPuppet
    if not pp or not pp.active then return end
    if pp.paused then return end
    if os.time() >= pp.expireTime then
        pp.active = false
        pp.expireTime = 0
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "puppet_expired", {})
        return
    end
    rt.puppetTimer = rt.puppetTimer + dt
    if rt.puppetTimer < PUPPET_INTERVAL then return end
    rt.puppetTimer = rt.puppetTimer - PUPPET_INTERVAL

    if not pp.products or #pp.products == 0 then return end

    -- 检查制作队列是否已满
    local stallLvl = math.min(s.stallLevel or 1, #Config.StallLevels)
    local queueLimit = Config.StallLevels[stallLvl].queueLimit
    if #rt.craftQueue >= queueLimit then return end

    -- 批量填满队列
    -- mode: "priority"(默认) = 优先排满第一个商品再排下一个
    --        "roundrobin"     = 多商品交替轮询均匀排列
    local mode = pp.craftMode or "priority"
    local crafted = {}  -- 记录本次批量制作的商品列表

    if mode == "roundrobin" then
        -- 轮询模式: 多商品交替排列，直到队列满或所有商品缺材料
        local productCount = #pp.products
        local exhausted = {}  -- 标记材料不足的商品
        local exhaustedCount = 0
        while #rt.craftQueue < queueLimit and exhaustedCount < productCount do
            local addedThisRound = false
            for idx, prodId in ipairs(pp.products) do
                if #rt.craftQueue >= queueLimit then break end
                if not exhausted[idx] then
                    local prodCfg = Config.GetProductById(prodId)
                    if prodCfg and s.realmLevel >= prodCfg.unlockRealm then
                        local matId = prodCfg.materialId
                        local matCost = prodCfg.materialCost
                        if (s.materials[matId] or 0) >= matCost then
                            spendMaterial(s, matId, matCost)
                            table.insert(rt.craftQueue, {
                                productId = prodId,
                                remainTime = prodCfg.craftTime,
                                totalTime = prodCfg.craftTime,
                            })
                            table.insert(crafted, prodId)
                            addedThisRound = true
                        else
                            exhausted[idx] = true
                            exhaustedCount = exhaustedCount + 1
                        end
                    else
                        exhausted[idx] = true
                        exhaustedCount = exhaustedCount + 1
                    end
                end
            end
            if not addedThisRound then break end
        end
    else
        -- 优先级模式(默认): 排满第一个商品再排下一个
        while #rt.craftQueue < queueLimit do
            local foundAny = false
            for _, prodId in ipairs(pp.products) do
                if #rt.craftQueue >= queueLimit then break end
                local prodCfg = Config.GetProductById(prodId)
                if prodCfg and s.realmLevel >= prodCfg.unlockRealm then
                    local matId = prodCfg.materialId
                    local matCost = prodCfg.materialCost
                    if (s.materials[matId] or 0) >= matCost then
                        spendMaterial(s, matId, matCost)
                        table.insert(rt.craftQueue, {
                            productId = prodId,
                            remainTime = prodCfg.craftTime,
                            totalTime = prodCfg.craftTime,
                        })
                        table.insert(crafted, prodId)
                        foundAny = true
                        break  -- 优先级模式: 找到一个就从头重新轮询, 优先排满第一个
                    end
                end
            end
            if not foundAny then break end  -- 所有商品都缺材料
        end
    end

    if #crafted > 0 then
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "puppet_batch_crafted", {
            crafted = crafted,
            materials = s.materials,
            craftPuppet = s.craftPuppet,
        })
    end
end

local function updateLifespan(userId, s, rt, dt)
    rt.lifespanTimer = rt.lifespanTimer + dt
    if rt.lifespanTimer >= LIFESPAN_TICK then
        rt.lifespanTimer = rt.lifespanTimer - LIFESPAN_TICK
        local drain = Config.LifespanDrainPerSec * LIFESPAN_TICK
        local realmMul = Config.RealmLifespanDrainMul[s.realmLevel]
        if realmMul then drain = drain * realmMul end
        local artReduce = math.min(getArtifactBonus(s, "lifespan"), 0.8)  -- 最多减少80%
        if artReduce > 0 then drain = drain * (1.0 - artReduce) end
        -- 法宝耐久磨损: 寿元 tick 触发 lifespan 类型
        wearArtifactByType(userId, s, "lifespan", 1)
        local result = drainLifespan(s, drain)
        if result == "miracle" then
            sendEvt(userId, "lifespan_miracle", {})
            PlayerMgr_.SetDirty(userId)
        elseif result == "dead" then
            sendEvt(userId, "player_dead", {})
            PlayerMgr_.SetDirty(userId)
        end
    end
end

local function updateEncounter(userId, s, rt, dt)
    if s.tutorialStep < 6 then return end
    rt.encounterTimer = rt.encounterTimer + dt
    if rt.encounterTimer < Config.EncounterInterval then return end
    rt.encounterTimer = rt.encounterTimer - Config.EncounterInterval
    if math.random() > Config.EncounterChance then return end

    -- 权重随机选择
    local total = 0
    for _, e in ipairs(Config.Encounters) do total = total + e.weight end
    local eroll = math.random() * total
    local accum = 0
    local encounter = Config.Encounters[1]
    for _, e in ipairs(Config.Encounters) do
        accum = accum + e.weight
        if eroll <= accum then encounter = e; break end
    end

    -- 发放奖励(按境界缩放: 每境界+30%)
    local r = encounter.reward
    local realmScale = 1.0 + (s.realmLevel - 1) * 0.3
    local rewardParts = {}
    if r.lingshi then local v = math.floor(r.lingshi * realmScale); addLingshi(s, v); table.insert(rewardParts, "+" .. v .. " 灵石") end
    if r.xiuwei then local v = math.floor(r.xiuwei * realmScale); addXiuwei(s, v, userId); table.insert(rewardParts, "+" .. v .. " 修为") end
    if r.lingcao then local v = math.floor(r.lingcao * realmScale); addMaterial(s, "lingcao", v); table.insert(rewardParts, "+" .. v .. " 灵草") end
    if r.lingzhi then local v = math.floor(r.lingzhi * realmScale); addMaterial(s, "lingzhi", v); table.insert(rewardParts, "+" .. v .. " 灵纸") end
    if r.xuantie then local v = math.floor(r.xuantie * realmScale); addMaterial(s, "xuantie", v); table.insert(rewardParts, "+" .. v .. " 玄铁") end

    s.lastEncounterTime = os.time()
    PlayerMgr_.SetDirty(userId)
    advanceDailyTask(s, "encounter", 1)
    sendEvt(userId, "encounter", {
        id = encounter.id,
        name = encounter.name,
        desc = encounter.desc,
        rewardText = table.concat(rewardParts, ", "),
    })
end

-- ========== 操作处理器 ==========

local ACTION_HANDLERS = {}

local MAX_CRAFT_QUEUE = 20

ACTION_HANDLERS["start_craft"] = function(userId, s, rt, params)
    local prodId = params.productId
    local prodCfg = Config.GetProductById(prodId)
    if not prodCfg then return sendEvt(userId, "action_fail", { msg = "未知商品" }) end
    if #rt.craftQueue >= MAX_CRAFT_QUEUE then
        return sendEvt(userId, "action_fail", { msg = "制作队列已满" })
    end
    if s.realmLevel < prodCfg.unlockRealm then
        return sendEvt(userId, "action_fail", { msg = "境界不足" })
    end
    if not spendMaterial(s, prodCfg.materialId, prodCfg.materialCost) then
        return sendEvt(userId, "action_fail", { msg = "材料不足" })
    end
    table.insert(rt.craftQueue, {
        productId = prodId, remainTime = prodCfg.craftTime, totalTime = prodCfg.craftTime,
    })
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "craft_started", { productId = prodId, materials = s.materials })
end

ACTION_HANDLERS["batch_craft"] = function(userId, s, rt, params)
    local prodId = params.productId
    local count = math.min(params.count or 1, 50)
    local prodCfg = Config.GetProductById(prodId)
    if not prodCfg then return sendEvt(userId, "action_fail", { msg = "未知商品" }) end
    if s.realmLevel < prodCfg.unlockRealm then
        return sendEvt(userId, "action_fail", { msg = "境界不足" })
    end
    local made = 0
    for _ = 1, count do
        if #rt.craftQueue >= MAX_CRAFT_QUEUE then break end
        if not spendMaterial(s, prodCfg.materialId, prodCfg.materialCost) then break end
        table.insert(rt.craftQueue, {
            productId = prodId, remainTime = prodCfg.craftTime, totalTime = prodCfg.craftTime,
        })
        made = made + 1
    end
    if made > 0 then PlayerMgr_.SetDirty(userId) end
    sendEvt(userId, "batch_craft_done", { productId = prodId, count = made, materials = s.materials })
end

ACTION_HANDLERS["breakthrough"] = function(userId, s, rt, params)
    if s.realmLevel >= #Config.Realms then
        return sendEvt(userId, "action_fail", { msg = "已达最高境界" })
    end
    -- 化神及以上必须走渡劫流程
    if s.realmLevel >= Config.DUJIE_MIN_REALM then
        return sendEvt(userId, "action_fail", { msg = "此境界需渡劫突破" })
    end
    local nextLevel = s.realmLevel + 1
    local nextRealm = Config.Realms[nextLevel]
    if s.xiuwei < nextRealm.xiuwei then
        return sendEvt(userId, "action_fail", { msg = "修为不足" })
    end
    -- 检查突破材料需求
    local matReqs = Config.BreakthroughMaterials[nextLevel]
    if matReqs then
        for _, req in ipairs(matReqs) do
            local have = (s.collectibles or {})[req.id] or 0
            if have < req.count then
                local cfg = Config.GetCollectibleById(req.id)
                local name = cfg and cfg.name or req.id
                return sendEvt(userId, "action_fail", { msg = name .. "不足(需" .. req.count .. ",有" .. have .. ")" })
            end
        end
    end
    local cost = nextRealm.breakthroughCost
    local hasDiscount = (s.adUpgradeDiscount or 0) > 0 and (s.adDiscountExpire or 0) > os.time()
    if hasDiscount then
        cost = math.floor(cost * 0.7)
    end
    if s.lingshi < cost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    -- 扣除突破材料
    if matReqs then
        if not s.collectibles then s.collectibles = {} end
        for _, req in ipairs(matReqs) do
            s.collectibles[req.id] = (s.collectibles[req.id] or 0) - req.count
            if s.collectibles[req.id] <= 0 then s.collectibles[req.id] = nil end
        end
    end
    if hasDiscount then
        s.adUpgradeDiscount = s.adUpgradeDiscount - 1
    end
    s.lingshi = s.lingshi - cost
    s.realmLevel = s.realmLevel + 1
    if s.realmLevel > (s.highestRealmEver or 1) then s.highestRealmEver = s.realmLevel end
    s.lifespan = s.lifespan + nextRealm.lifespan
    -- 师徒系统：出师检测(目标 = 师父拜师时境界 - 1)
    if s.masterId and s.realmLevel >= ((s.masterRealmAtBind or 99) - 1) then
        MentorModule.HandleGraduation(userId, s)
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "realm_up", { level = s.realmLevel, name = nextRealm.name, lingshi = s.lingshi, xiuwei = s.xiuwei, realmLevel = s.realmLevel, lifespan = s.lifespan })
end

-- ============ 渡劫小游戏 ============

--- 检查并重置渡劫每日次数
local function checkDujieDailyReset(s)
    local today = getTodayKey()
    if (s.dujieDailyDate or "") ~= today then
        s.dujieDailyDate = today
        s.dujieFreeUses = 0
        s.dujiePaidUses = 0
    end
end

-- 检查并重置秘境每日次数(前移到 ad_reward handler 之前, 否则 local function 前向引用为 nil)
local function checkDungeonDailyReset(s)
    local today = getTodayKey()
    if (s.dungeonDailyDate or "") ~= today then
        s.dungeonDailyDate = today
        s.dungeonDailyUses = {}
        s.dungeonBonusUses = {}
    end
end

--- 渡劫预检查: 返回次数和费用信息(不扣费)
ACTION_HANDLERS["dujie_check"] = function(userId, s, rt, params)
    if s.realmLevel < Config.DUJIE_MIN_REALM then
        return sendEvt(userId, "action_fail", { msg = "境界不足,无需渡劫" })
    end
    if s.realmLevel >= #Config.Realms then
        return sendEvt(userId, "action_fail", { msg = "已达最高境界" })
    end
    local nextLevel = s.realmLevel + 1
    checkDujieDailyReset(s)
    local freeLeft = Config.DUJIE_FREE_ATTEMPTS - (s.dujieFreeUses or 0)
    local paidLeft = Config.DUJIE_MAX_PAID - (s.dujiePaidUses or 0)
    local isPaid = freeLeft <= 0
    local retryCost = 0
    if isPaid and paidLeft > 0 then
        local tier = math.max(1, math.min(nextLevel - Config.DUJIE_MIN_REALM, #Config.DujieTiers))
        local tierCfg = Config.DujieTiers[tier]
        retryCost = math.floor(tierCfg.retryCostBase * (2 ^ (s.dujiePaidUses or 0)))
    end
    sendEvt(userId, "dujie_check_result", {
        freeLeft = math.max(0, freeLeft),
        paidLeft = math.max(0, paidLeft),
        isPaid = isPaid,
        retryCost = retryCost,
        lingshi = s.lingshi,
    })
end

ACTION_HANDLERS["dujie_start"] = function(userId, s, rt, params)
    -- 1. 境界检查
    if s.realmLevel < Config.DUJIE_MIN_REALM then
        return sendEvt(userId, "action_fail", { msg = "境界不足,无需渡劫" })
    end
    if s.realmLevel >= #Config.Realms then
        return sendEvt(userId, "action_fail", { msg = "已达最高境界" })
    end
    local nextLevel = s.realmLevel + 1
    local nextRealm = Config.Realms[nextLevel]

    -- 2. 修为检查
    if s.xiuwei < nextRealm.xiuwei then
        return sendEvt(userId, "action_fail", { msg = "修为不足" })
    end

    -- 3. 突破材料检查(只验证不扣除)
    local matReqs = Config.BreakthroughMaterials[nextLevel]
    if matReqs then
        for _, req in ipairs(matReqs) do
            local have = (s.collectibles or {})[req.id] or 0
            if have < req.count then
                local cfg = Config.GetCollectibleById(req.id)
                local name = cfg and cfg.name or req.id
                return sendEvt(userId, "action_fail", { msg = name .. "不足(需" .. req.count .. ",有" .. have .. ")" })
            end
        end
    end

    -- 4. 灵石检查(只验证不扣除)
    local cost = nextRealm.breakthroughCost
    local hasDiscount = (s.adUpgradeDiscount or 0) > 0 and (s.adDiscountExpire or 0) > os.time()
    if hasDiscount then cost = math.floor(cost * 0.7) end
    if s.lingshi < cost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end

    -- 5. 每日次数检查
    checkDujieDailyReset(s)
    local freeLeft = Config.DUJIE_FREE_ATTEMPTS - (s.dujieFreeUses or 0)
    local paidLeft = Config.DUJIE_MAX_PAID - (s.dujiePaidUses or 0)
    local isPaid = freeLeft <= 0
    local retryCost = 0

    if isPaid then
        if paidLeft <= 0 then
            return sendEvt(userId, "action_fail", { msg = "今日渡劫次数已用完" })
        end
        -- 付费灵石: base * 2^paidUses
        local tier = math.max(1, math.min(nextLevel - Config.DUJIE_MIN_REALM, #Config.DujieTiers))
        local tierCfg = Config.DujieTiers[tier]
        retryCost = math.floor(tierCfg.retryCostBase * (2 ^ (s.dujiePaidUses or 0)))
        if s.lingshi < (cost + retryCost) then
            return sendEvt(userId, "action_fail", { msg = "灵石不足(渡劫费用" .. retryCost .. ")" })
        end
        s.lingshi = s.lingshi - retryCost
        s.dujiePaidUses = (s.dujiePaidUses or 0) + 1
    else
        s.dujieFreeUses = (s.dujieFreeUses or 0) + 1
    end

    -- 6. 记录运行时状态(反作弊)
    local tier = math.max(1, math.min(nextLevel - Config.DUJIE_MIN_REALM, #Config.DujieTiers))
    local tierCfg = Config.DujieTiers[tier]
    rt.dujieStartTime = os.time()
    rt.dujieTargetLevel = nextLevel
    rt.dujieTier = tier

    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "dujie_begin", {
        tier = tier,
        tierName = tierCfg.name,
        nextLevel = nextLevel,
        nextRealmName = nextRealm.name,
        duration = tierCfg.duration,
        freeLeft = math.max(0, Config.DUJIE_FREE_ATTEMPTS - (s.dujieFreeUses or 0)),
        paidLeft = math.max(0, Config.DUJIE_MAX_PAID - (s.dujiePaidUses or 0)),
        retryCost = retryCost,
        lingshi = s.lingshi,
    })
end

ACTION_HANDLERS["dujie_result"] = function(userId, s, rt, params)
    if not rt or not rt.dujieStartTime then
        return sendEvt(userId, "action_fail", { msg = "未在渡劫中" })
    end

    local success = params.success == true
    local elapsed = os.time() - rt.dujieStartTime
    local nextLevel = rt.dujieTargetLevel
    local tier = rt.dujieTier

    -- 清除运行时状态
    rt.dujieStartTime = nil
    rt.dujieTargetLevel = nil
    rt.dujieTier = nil

    -- 失败路径
    if not success then
        checkDujieDailyReset(s)
        local freeLeft = Config.DUJIE_FREE_ATTEMPTS - (s.dujieFreeUses or 0)
        local paidLeft = Config.DUJIE_MAX_PAID - (s.dujiePaidUses or 0)
        local nextCost = 0
        if freeLeft <= 0 and paidLeft > 0 then
            local tierCfg = Config.DujieTiers[tier]
            if tierCfg then
                nextCost = math.floor(tierCfg.retryCostBase * (2 ^ (s.dujiePaidUses or 0)))
            end
        end
        sendEvt(userId, "dujie_fail", {
            tier = tier,
            freeLeft = math.max(0, freeLeft),
            paidLeft = math.max(0, paidLeft),
            nextRetryCost = nextCost,
            lingshi = s.lingshi,
        })
        return
    end

    -- 反作弊: 最短时间检查(70%容忍度)
    local tierCfg = Config.DujieTiers[tier]
    if tierCfg and elapsed < (tierCfg.duration * 0.7) then
        return sendEvt(userId, "action_fail", { msg = "渡劫异常,请重试" })
    end

    -- 重新验证(防竞态)
    if not nextLevel or nextLevel > #Config.Realms then
        return sendEvt(userId, "action_fail", { msg = "境界数据异常" })
    end
    local nextRealm = Config.Realms[nextLevel]
    local matReqs = Config.BreakthroughMaterials[nextLevel]
    if matReqs then
        for _, req in ipairs(matReqs) do
            local have = (s.collectibles or {})[req.id] or 0
            if have < req.count then
                return sendEvt(userId, "action_fail", { msg = "突破材料已不足" })
            end
        end
    end
    local cost = nextRealm.breakthroughCost
    local hasDiscount = (s.adUpgradeDiscount or 0) > 0 and (s.adDiscountExpire or 0) > os.time()
    if hasDiscount then cost = math.floor(cost * 0.7) end
    if s.lingshi < cost then
        return sendEvt(userId, "action_fail", { msg = "灵石已不足" })
    end

    -- 扣除突破材料
    if matReqs then
        if not s.collectibles then s.collectibles = {} end
        for _, req in ipairs(matReqs) do
            s.collectibles[req.id] = (s.collectibles[req.id] or 0) - req.count
            if s.collectibles[req.id] <= 0 then s.collectibles[req.id] = nil end
        end
    end

    -- 扣除灵石+升级
    if hasDiscount then s.adUpgradeDiscount = s.adUpgradeDiscount - 1 end
    s.lingshi = s.lingshi - cost
    s.realmLevel = nextLevel
    if s.realmLevel > (s.highestRealmEver or 1) then s.highestRealmEver = s.realmLevel end
    s.lifespan = s.lifespan + nextRealm.lifespan

    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "realm_up", {
        level = s.realmLevel, name = nextRealm.name,
        lingshi = s.lingshi, xiuwei = s.xiuwei,
        realmLevel = s.realmLevel, lifespan = s.lifespan,
        dujieSuccess = true,
    })
end

ACTION_HANDLERS["rebirth"] = function(userId, s, rt, params)
    local rb = Config.Rebirth
    local newCount = s.rebirthCount + 1
    local keepRate = rb.lingshiKeepRate + s.rebirthCount * rb.keepRatePerRebirth
    keepRate = math.min(keepRate, rb.maxKeepRate)
    local keptLingshi = math.floor(s.lingshi * keepRate)
    local bonusLifespan = newCount * rb.lifespanBonus
    local bonusXiuwei = newCount * rb.xiuweiBonus

    local summary = {
        oldRebirthCount = s.rebirthCount,
        newRebirthCount = newCount,
        keptLingshi = keptLingshi,
        keepRate = keepRate,
    }

    -- 保留字段
    local kept = {
        storyPlayed = true,
        newbieGiftClaimed = true,
        guideCompleted = s.guideCompleted, -- 转世保留引导完成状态，避免重新触发引导遮罩
        tutorialStep = s.tutorialStep,
        bgmEnabled = s.bgmEnabled,
        sfxEnabled = s.sfxEnabled,
        autoRefine = s.autoRefine,
        playerName = s.playerName,
        playerGender = s.playerGender,
        playerId = s.playerId,
        serverId = s.serverId,
        redeemedCDKs = s.redeemedCDKs,
        adFreeExpire = s.adFreeExpire,
        highestRealmEver = s.highestRealmEver or 1,
        reputation = s.reputation or 100,
        totalBargains = s.totalBargains or 0,
        bargainWins = s.bargainWins or 0,
        dailyTasksClaimed = s.dailyTasksClaimed or 0,
    }

    -- 重置 state (直接复用 s 引用)
    local defaults = {
        lingshi = keptLingshi, xiuwei = bonusXiuwei,
        materials = { lingcao = 0, lingzhi = 0, xuantie = 0 },
        products = {
            juqi_dan = 0, huichun_fu = 0, dijie_faqi = 0,
            ninghun_dan = 0, poxu_fu = 0, xianqi_canpian = 0,
        },
        stallLevel = 1, shelf = {},
        totalSold = 0, totalEarned = 0, totalCrafted = 0,
        todayEarned = 0, todayDate = "",
        craftQueue = {},
        adFlowBoostEnd = 0, adPriceBoostEnd = 0, adUpgradeDiscount = 0, adDiscountExpire = 0,
        totalAdWatched = 0,
        dailyAdCounts = {}, dailyAdDate = "",
        offlineAdExtend = 0,
        realmLevel = 1,
        lifespan = Config.Realms[1].lifespan + bonusLifespan,
        rebirthCount = newCount,
        dead = false,
        myTodayRank = nil,
        lastEncounterTime = 0,
        fieldLevel = 1, fieldPlots = {},
        fieldServant = { tier = 0, expireTime = 0, plantCrop = "lingcao_seed" },
        craftPuppet = { active = false, expireTime = 0, products = {} },
        lastSaveTime = 0,
        repStreak = 0,
        dailyTasks = {}, dailyTaskDate = "",
    }
    -- 珍藏物品: 永久类保留, 消耗品清零
    local keptCollectibles = {}
    for itemId, count in pairs(s.collectibles or {}) do
        local cfg = Config.GetCollectibleById(itemId)
        if cfg and cfg.type == "permanent" and count > 0 then
            keptCollectibles[itemId] = count
        end
    end
    defaults.collectibles = keptCollectibles

    for k, v in pairs(defaults) do s[k] = v end
    for k, v in pairs(kept) do s[k] = v end

    -- 重置运行时
    rt.customers = {}
    rt.craftQueue = {}
    rt.materialTimer = 0
    rt.customerTimer = 0
    rt.autoRefineTimer = 0
    rt.lifespanTimer = 0
    rt.encounterTimer = 0
    rt.servantTimer = 0
    rt.puppetTimer = 0
    rt.nextCustId = 1

    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "rebirth_done", summary)
end

ACTION_HANDLERS["stall_upgrade"] = function(userId, s, rt, params)
    if s.stallLevel >= #Config.StallLevels then
        return sendEvt(userId, "action_fail", { msg = "已满级" })
    end
    local nextCfg = Config.StallLevels[s.stallLevel + 1]
    local cost = nextCfg.cost
    local hasDiscount = (s.adUpgradeDiscount or 0) > 0 and (s.adDiscountExpire or 0) > os.time()
    if hasDiscount then
        cost = math.floor(cost * 0.7)
        s.adUpgradeDiscount = s.adUpgradeDiscount - 1
    end
    if not spendLingshi(s, cost) then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    s.stallLevel = s.stallLevel + 1
    addXiuwei(s, 50)
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "stall_upgraded", { level = s.stallLevel, lingshi = s.lingshi, stallLevel = s.stallLevel })
end

ACTION_HANDLERS["field_plant"] = function(userId, s, rt, params)
    local plotIdx = params.plotIdx
    local cropId = params.cropId
    local lvl = math.min(s.fieldLevel, #Config.FieldLevels)
    local maxPlots = Config.FieldLevels[lvl].plots
    if plotIdx < 1 or plotIdx > maxPlots then
        return sendEvt(userId, "action_fail", { msg = "无效地块" })
    end
    local existing = s.fieldPlots[plotIdx]
    if existing and existing.cropId then
        return sendEvt(userId, "action_fail", { msg = "该地块已种植" })
    end
    local crop = nil
    for _, c in ipairs(Config.Crops) do if c.id == cropId then crop = c; break end end
    if not crop then return sendEvt(userId, "action_fail", { msg = "未知种子" }) end
    if not spendLingshi(s, crop.cost) then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    s.fieldPlots[plotIdx] = { cropId = cropId, plantTime = os.time() }
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "field_planted", { plotIdx = plotIdx, cropId = cropId, lingshi = s.lingshi })
end

ACTION_HANDLERS["field_harvest"] = function(userId, s, rt, params)
    local plotIdx = params.plotIdx
    local plot = s.fieldPlots[plotIdx]
    if not plot or not plot.cropId then
        return sendEvt(userId, "action_fail", { msg = "无作物" })
    end
    local crop = nil
    for _, c in ipairs(Config.Crops) do if c.id == plot.cropId then crop = c; break end end
    if not crop then return sendEvt(userId, "action_fail", { msg = "未知作物" }) end
    -- 灵童加速: 计算实际生长时间
    local sv = s.fieldServant
    local servantCfg = sv and sv.tier > 0 and os.time() < (sv.expireTime or 0) and Config.FieldServants[sv.tier] or nil
    local speedBonus = servantCfg and servantCfg.abilities.speedBonus or 0
    local actualGrowTime = crop.growTime / (1 + speedBonus)
    local elapsed = os.time() - plot.plantTime
    if elapsed < actualGrowTime then
        return sendEvt(userId, "action_fail", { msg = "尚未成熟" })
    end
    -- 法宝/珍藏产量加成
    local artBonus = 1.0 + getArtifactBonus(s, "material_rate")
    local rewards = {}
    for matId, amount in pairs(crop.yield) do
        local collMatBonus = 1.0 + getCollectibleBonus(s, "material_rate_" .. matId)
        local finalAmount = math.floor(amount * artBonus * collMatBonus)
        if finalAmount < 1 then finalAmount = 1 end
        addMaterial(s, matId, finalAmount)
        rewards[matId] = finalAmount
    end
    s.fieldPlots[plotIdx] = {}
    advanceDailyTask(s, "harvest", 1)
    -- 法宝耐久磨损: 收获触发 material_rate 类型
    wearArtifactByType(userId, s, "material_rate", 1)
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "field_harvested", { plotIdx = plotIdx, rewards = rewards, materials = s.materials })
end

ACTION_HANDLERS["field_harvest_all"] = function(userId, s, rt, params)
    local lvl = math.min(s.fieldLevel, #Config.FieldLevels)
    local maxPlots = Config.FieldLevels[lvl].plots
    -- 灵童加速: 计算实际生长时间
    local sv = s.fieldServant
    local servantCfg = sv and sv.tier > 0 and os.time() < (sv.expireTime or 0) and Config.FieldServants[sv.tier] or nil
    local speedBonus = servantCfg and servantCfg.abilities.speedBonus or 0
    -- 法宝/珍藏产量加成
    local artBonus = 1.0 + getArtifactBonus(s, "material_rate")
    local totalRewards = {}
    local count = 0
    for i = 1, maxPlots do
        local plot = s.fieldPlots[i]
        if plot and plot.cropId then
            local crop = nil
            for _, c in ipairs(Config.Crops) do if c.id == plot.cropId then crop = c; break end end
            if crop then
                local actualGrowTime = crop.growTime / (1 + speedBonus)
                local elapsed = os.time() - plot.plantTime
                if elapsed >= actualGrowTime then
                    for matId, amount in pairs(crop.yield) do
                        local collMatBonus = 1.0 + getCollectibleBonus(s, "material_rate_" .. matId)
                        local finalAmount = math.floor(amount * artBonus * collMatBonus)
                        if finalAmount < 1 then finalAmount = 1 end
                        addMaterial(s, matId, finalAmount)
                        totalRewards[matId] = (totalRewards[matId] or 0) + finalAmount
                    end
                    s.fieldPlots[i] = {}
                    count = count + 1
                end
            end
        end
    end
    if count > 0 then
        advanceDailyTask(s, "harvest", count)
        -- 法宝耐久磨损: 批量收获按次数触发 material_rate 类型
        wearArtifactByType(userId, s, "material_rate", count)
        PlayerMgr_.SetDirty(userId)
    end
    sendEvt(userId, "field_harvest_all_done", { rewards = totalRewards, count = count, materials = s.materials })
end

ACTION_HANDLERS["field_upgrade"] = function(userId, s, rt, params)
    if s.fieldLevel >= #Config.FieldLevels then
        return sendEvt(userId, "action_fail", { msg = "已满级" })
    end
    local nextCfg = Config.FieldLevels[s.fieldLevel + 1]
    if nextCfg.requiredRealm and s.realmLevel < nextCfg.requiredRealm then
        return sendEvt(userId, "action_fail", { msg = "境界不足" })
    end
    if not spendLingshi(s, nextCfg.cost) then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    s.fieldLevel = s.fieldLevel + 1
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "field_upgraded", { level = s.fieldLevel, fieldLevel = s.fieldLevel, lingshi = s.lingshi })
end

-- ========== 灵童雇佣 ==========
ACTION_HANDLERS["hire_servant"] = function(userId, s, rt, params)
    local tier = tonumber(params.tier)
    if not tier or tier < 1 or tier > #Config.FieldServants then
        return sendEvt(userId, "action_fail", { msg = "无效灵童等级" })
    end
    local cfg = Config.FieldServants[tier]
    if s.realmLevel < cfg.requiredRealm then
        return sendEvt(userId, "action_fail", { msg = "需" .. Config.Realms[cfg.requiredRealm].name .. "期" })
    end
    if not spendLingshi(s, cfg.cost) then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    if not s.fieldServant then
        s.fieldServant = { tier = 0, expireTime = 0, plantCrop = "lingcao_seed" }
    end
    s.fieldServant.tier = tier
    s.fieldServant.expireTime = os.time() + 86400  -- 24h
    rt.servantTimer = 0
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "servant_hired", {
        tier = tier, expireTime = s.fieldServant.expireTime,
        lingshi = s.lingshi, fieldServant = s.fieldServant,
    })
end

ACTION_HANDLERS["set_servant_crop"] = function(userId, s, rt, params)
    local cropId = params.cropId
    if not cropId then
        return sendEvt(userId, "action_fail", { msg = "缺少作物ID" })
    end
    -- 验证作物存在
    local found = false
    for _, c in ipairs(Config.Crops) do
        if c.id == cropId then found = true; break end
    end
    if not found then
        return sendEvt(userId, "action_fail", { msg = "未知作物" })
    end
    if not s.fieldServant then
        s.fieldServant = { tier = 0, expireTime = 0, plantCrop = "lingcao_seed" }
    end
    s.fieldServant.plantCrop = cropId
    -- 设置全局作物时，清空分田配置(统一模式)
    s.fieldServant.plotCrops = nil
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "servant_crop_set", { cropId = cropId, fieldServant = s.fieldServant })
end

--- 分田种植: 为指定地块设置独立作物(仅金灵童 tier>=3 可用)
ACTION_HANDLERS["set_plot_crop"] = function(userId, s, rt, params)
    local plotIdx = tonumber(params.plotIdx)
    local cropId = params.cropId
    if not plotIdx or not cropId then
        return sendEvt(userId, "action_fail", { msg = "参数错误" })
    end
    -- 验证作物存在
    local found = false
    for _, c in ipairs(Config.Crops) do
        if c.id == cropId then found = true; break end
    end
    if not found then
        return sendEvt(userId, "action_fail", { msg = "未知作物" })
    end
    if not s.fieldServant then
        s.fieldServant = { tier = 0, expireTime = 0, plantCrop = "lingcao_seed" }
    end
    -- 金灵童(tier>=3)才支持分田
    if s.fieldServant.tier < 3 then
        return sendEvt(userId, "action_fail", { msg = "需要金灵童才能分田种植" })
    end
    -- 验证地块范围
    local lvl = math.min(s.fieldLevel or 1, #Config.FieldLevels)
    local maxPlots = Config.FieldLevels[lvl].plots
    if plotIdx < 1 or plotIdx > maxPlots then
        return sendEvt(userId, "action_fail", { msg = "无效地块" })
    end
    -- 初始化 plotCrops
    if not s.fieldServant.plotCrops then
        s.fieldServant.plotCrops = {}
    end
    s.fieldServant.plotCrops[tostring(plotIdx)] = cropId
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "plot_crop_set", {
        plotIdx = plotIdx,
        cropId = cropId,
        fieldServant = s.fieldServant,
    })
end

-- ========== 炼器傀儡雇佣 ==========
ACTION_HANDLERS["hire_puppet"] = function(userId, s, rt, params)
    local cfg = Config.CraftPuppet
    if s.realmLevel < cfg.requiredRealm then
        return sendEvt(userId, "action_fail", { msg = "需" .. Config.Realms[cfg.requiredRealm].name .. "期" })
    end
    if not spendLingshi(s, cfg.cost) then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    if not s.craftPuppet then
        s.craftPuppet = { active = false, expireTime = 0, products = {} }
    end
    s.craftPuppet.active = true
    s.craftPuppet.expireTime = os.time() + 86400  -- 24h
    rt.puppetTimer = 0
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "puppet_hired", {
        expireTime = s.craftPuppet.expireTime,
        lingshi = s.lingshi, craftPuppet = s.craftPuppet,
    })
end

ACTION_HANDLERS["set_puppet_products"] = function(userId, s, rt, params)
    local products = params.products
    if type(products) ~= "table" then
        return sendEvt(userId, "action_fail", { msg = "缺少商品列表" })
    end
    -- 验证商品都存在
    local valid = {}
    for _, prodId in ipairs(products) do
        if Config.GetProductById(prodId) then
            table.insert(valid, prodId)
        end
    end
    if not s.craftPuppet then
        s.craftPuppet = { active = false, expireTime = 0, products = {} }
    end
    s.craftPuppet.products = valid
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "puppet_products_set", { products = valid, craftPuppet = s.craftPuppet })
end

ACTION_HANDLERS["set_puppet_mode"] = function(userId, s, rt, params)
    if not s.craftPuppet then
        s.craftPuppet = { active = false, expireTime = 0, products = {} }
    end
    local mode = params.mode
    if mode ~= "priority" and mode ~= "roundrobin" then
        return sendEvt(userId, "action_fail", { msg = "无效模式" })
    end
    s.craftPuppet.craftMode = mode
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "puppet_mode_set", { craftMode = mode, craftPuppet = s.craftPuppet })
end

-- ========== 灵童/傀儡暂停切换 ==========
ACTION_HANDLERS["toggle_servant_pause"] = function(userId, s, rt, params)
    if not s.fieldServant or s.fieldServant.tier <= 0 then
        return sendEvt(userId, "action_fail", { msg = "未雇佣灵童" })
    end
    s.fieldServant.paused = not s.fieldServant.paused
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "servant_pause_toggled", {
        paused = s.fieldServant.paused,
        fieldServant = s.fieldServant,
    })
end

ACTION_HANDLERS["toggle_puppet_pause"] = function(userId, s, rt, params)
    if not s.craftPuppet or not s.craftPuppet.active then
        return sendEvt(userId, "action_fail", { msg = "未雇佣傀儡" })
    end
    s.craftPuppet.paused = not s.craftPuppet.paused
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "puppet_pause_toggled", {
        paused = s.craftPuppet.paused,
        craftPuppet = s.craftPuppet,
    })
end

-- ========== 讨价还价 ==========
ACTION_HANDLERS["bargain"] = function(userId, s, rt, params)
    local custId = params.custId
    local hitPos = tonumber(params.hitPos)
    if not custId or not hitPos then
        return sendEvt(userId, "action_fail", { msg = "参数缺失" })
    end
    -- 找到对应顾客
    local cust = nil
    for _, c in ipairs(rt.customers) do
        if c.id == custId then cust = c; break end
    end
    if not cust then
        print("[Bargain-S] 顾客不存在 custId=" .. tostring(custId) .. " 当前顾客数=" .. #rt.customers)
        return sendEvt(userId, "action_fail", { msg = "顾客不存在" })
    end
    print("[Bargain-S] 开始讨价 custId=" .. tostring(custId) .. " state=" .. tostring(cust.state) .. " buyTimer=" .. tostring(cust.buyTimer) .. " bargaining=" .. tostring(cust.bargaining))
    if cust.state ~= "buying" then
        return sendEvt(userId, "action_fail", { msg = "顾客不在购买状态" })
    end
    if cust.bargainDone then
        return sendEvt(userId, "action_fail", { msg = "已讨价还价过" })
    end
    -- 多轮讨价: 记录尝试次数
    cust.bargainAttempts = (cust.bargainAttempts or 0) + 1
    local maxAttempts = Config.BargainConfig.maxAttempts or 3

    -- 计算结果
    local mul, zoneId, zone = Config.GetBargainResult(hitPos)
    cust.bargainMul = mul
    cust.bargaining = true  -- 暂停 buyTimer
    s.totalBargains = (s.totalBargains or 0) + 1

    -- 顾客拒绝判定(降价区域有概率拒绝)
    local refused = false
    if zone and zone.refuseChance and zone.refuseChance > 0 then
        if math.random() < zone.refuseChance then
            refused = true
        end
    end

    local win = mul > 1.0
    local isFinal = refused or (cust.bargainAttempts >= maxAttempts) or (zoneId == "perfect")

    if refused then
        -- 顾客拒绝购买并离开
        cust.bargainDone = true
        cust.bargaining = false
        cust.state = "leaving"
        cust.walkProgress = 1.0
        updateReputation(s, false, false)
    elseif isFinal then
        -- 最后一次或完美命中: 锁定结果
        cust.bargainDone = true
        cust.bargaining = false
        if win then
            s.bargainWins = (s.bargainWins or 0) + 1
            advanceDailyTask(s, "bargain_win", 1)
        end
    end
    -- 非 final 时: bargainDone=false, 玩家可继续

    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "bargain_result", {
        custId = custId,
        zone = zoneId,
        mul = mul,
        win = win,
        refused = refused,
        isFinal = isFinal,
        attempt = cust.bargainAttempts,
        maxAttempts = maxAttempts,
        totalBargains = s.totalBargains,
        bargainWins = s.bargainWins or 0,
        reputation = s.reputation,
    })
end

-- 玩家接受当前讨价结果
ACTION_HANDLERS["bargain_accept"] = function(userId, s, rt, params)
    local custId = params.custId
    if not custId then
        return sendEvt(userId, "action_fail", { msg = "参数缺失" })
    end
    local cust = nil
    for _, c in ipairs(rt.customers) do
        if c.id == custId then cust = c; break end
    end
    if not cust then
        print("[Bargain-S] bargain_accept 顾客不存在 custId=" .. tostring(custId) .. " 当前顾客数=" .. #rt.customers)
        return sendEvt(userId, "action_fail", { msg = "顾客不存在" })
    end
    print("[Bargain-S] bargain_accept custId=" .. tostring(custId) .. " buyTimer=" .. tostring(cust.buyTimer) .. " bargaining=" .. tostring(cust.bargaining) .. " bargainDone=" .. tostring(cust.bargainDone))
    if cust.bargainDone then return end  -- 已锁定
    -- 锁定当前结果
    cust.bargainDone = true
    cust.bargaining = false
    local win = (cust.bargainMul or 1.0) > 1.0
    if win then
        s.bargainWins = (s.bargainWins or 0) + 1
        advanceDailyTask(s, "bargain_win", 1)
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "bargain_accepted", { custId = custId, mul = cust.bargainMul })
end

-- ========== 材料合成 ==========
ACTION_HANDLERS["synthesize"] = function(userId, s, rt, params)
    local recipeId = params.recipeId
    local count = math.max(1, math.min(tonumber(params.count) or 1, 99))
    local recipe = Config.GetSynthesisRecipeById(recipeId)
    if not recipe then
        return sendEvt(userId, "action_fail", { msg = "未知配方" })
    end
    if s.realmLevel < recipe.unlockRealm then
        return sendEvt(userId, "action_fail", { msg = "境界不足，需要" .. Config.Realms[recipe.unlockRealm].name })
    end
    -- 检查产出材料上限
    local output = recipe.output
    local outMat = Config.GetMaterialById(output.id) or Config.GetSynthesisRecipeById(output.id)
    local outCap = (outMat and outMat.cap) or 9999
    local currentOut = s.materials[output.id] or 0
    local roomLeft = math.max(0, outCap - currentOut)
    if roomLeft <= 0 then
        return sendEvt(userId, "action_fail", { msg = (outMat and outMat.name or output.id) .. "已达上限(" .. outCap .. ")" })
    end
    -- 计算最多可合成数量(受材料和cap双重限制)
    local maxByRoom = math.floor(roomLeft / output.amount)
    if maxByRoom <= 0 then
        return sendEvt(userId, "action_fail", { msg = (outMat and outMat.name or output.id) .. "已达上限(" .. outCap .. ")" })
    end
    local maxPossible = math.min(count, maxByRoom)
    for _, inp in ipairs(recipe.inputs) do
        local have = s.materials[inp.id] or 0
        local canMake = math.floor(have / inp.amount)
        maxPossible = math.min(maxPossible, canMake)
    end
    if maxPossible <= 0 then
        return sendEvt(userId, "action_fail", { msg = "材料不足" })
    end
    -- 扣除输入材料
    for _, inp in ipairs(recipe.inputs) do
        s.materials[inp.id] = (s.materials[inp.id] or 0) - inp.amount * maxPossible
    end
    -- 添加输出材料
    local gained = output.amount * maxPossible
    addMaterial(s, output.id, gained)
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "synthesize_done", {
        recipeId = recipeId,
        count = maxPossible,
        outputId = output.id,
        outputAmount = gained,
        materials = s.materials,
    })
end

-- ========== 一键合成(所有配方合成到上限) ==========
ACTION_HANDLERS["synthesize_all"] = function(userId, s, rt, params)
    local results = {}
    local anyDone = false
    -- 按配方顺序(低级→高级)依次合成
    for _, recipe in ipairs(Config.SynthesisRecipes) do
        if s.realmLevel >= recipe.unlockRealm then
            local output = recipe.output
            local outMat = Config.GetMaterialById(output.id) or Config.GetSynthesisRecipeById(output.id)
            local outCap = (outMat and outMat.cap) or 9999
            local currentOut = s.materials[output.id] or 0
            local roomLeft = math.max(0, outCap - currentOut)
            local maxByRoom = math.floor(roomLeft / output.amount)
            if maxByRoom > 0 then
                local maxPossible = maxByRoom
                for _, inp in ipairs(recipe.inputs) do
                    local have = s.materials[inp.id] or 0
                    local canMake = math.floor(have / inp.amount)
                    maxPossible = math.min(maxPossible, canMake)
                end
                if maxPossible > 0 then
                    -- 扣除输入材料
                    for _, inp in ipairs(recipe.inputs) do
                        s.materials[inp.id] = (s.materials[inp.id] or 0) - inp.amount * maxPossible
                    end
                    -- 添加输出材料
                    local gained = output.amount * maxPossible
                    addMaterial(s, output.id, gained)
                    anyDone = true
                    table.insert(results, {
                        recipeId = recipe.id,
                        name = recipe.name,
                        count = maxPossible,
                        amount = gained,
                    })
                end
            end
        end
    end
    if not anyDone then
        return sendEvt(userId, "action_fail", { msg = "没有可合成的材料" })
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "synthesize_all_done", {
        results = results,
        materials = s.materials,
    })
end

-- ========== 每日任务领取 ==========
ACTION_HANDLERS["claim_daily_task"] = function(userId, s, rt, params)
    local taskIdx = tonumber(params.taskIdx)
    if not taskIdx then
        return sendEvt(userId, "action_fail", { msg = "参数缺失" })
    end
    refreshDailyTasks(s)
    local task = s.dailyTasks[taskIdx]
    if not task then
        return sendEvt(userId, "action_fail", { msg = "任务不存在" })
    end
    if task.claimed then
        return sendEvt(userId, "action_fail", { msg = "已领取" })
    end
    if (task.current or 0) < task.target then
        return sendEvt(userId, "action_fail", { msg = "任务未完成" })
    end
    -- 发放奖励
    task.claimed = true
    s.dailyTasksClaimed = (s.dailyTasksClaimed or 0) + 1
    if task.reward then
        if task.reward.lingshi then addLingshi(s, task.reward.lingshi) end
        if task.reward.xiuwei then addXiuwei(s, task.reward.xiuwei) end
        if task.reward.materials then
            for matId, amount in pairs(task.reward.materials) do
                addMaterial(s, matId, amount)
            end
        end
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "daily_task_claimed", {
        taskIdx = taskIdx,
        reward = task.reward,
        dailyTasks = s.dailyTasks,
        lingshi = s.lingshi,
        xiuwei = s.xiuwei,
        materials = s.materials,
    })
end

ACTION_HANDLERS["ad_reward"] = function(userId, s, rt, params)
    local key = params.key
    if not key then return sendEvt(userId, "action_fail", { msg = "缺少key" }) end

    -- 幂等性保护: 相同 nonce 不重复发放(防止断线重连重发导致双倍奖励)
    local nonce = params.nonce
    if nonce and nonce ~= "" then
        if not s.lastAdNonces then s.lastAdNonces = {} end
        if s.lastAdNonces[nonce] then
            -- 已处理过的 nonce, 直接返回成功(但不重复发放)
            print("[Ad] 幂等拦截: userId=" .. tostring(userId) .. " nonce=" .. nonce)
            sendEvt(userId, "ad_reward_done", {
                key = key,
                adFlowBoostEnd = s.adFlowBoostEnd or 0,
                adPriceBoostEnd = s.adPriceBoostEnd or 0,
                adUpgradeDiscount = s.adUpgradeDiscount or 0,
                adDiscountExpire = s.adDiscountExpire or 0,
                offlineAdExtend = s.offlineAdExtend or 0,
                totalAdWatched = s.totalAdWatched or 0,
                dungeonBonusUses = s.dungeonBonusUses or {},
                dailyAdCounts = s.dailyAdCounts or {},
            })
            return
        end
        -- 记录 nonce(保留最近20个, 防止无限增长)
        s.lastAdNonces[nonce] = true
        local count = 0
        for _ in pairs(s.lastAdNonces) do count = count + 1 end
        if count > 20 then
            -- 清理最早的(简单策略: 全部清除后只保留当前)
            s.lastAdNonces = { [nonce] = true }
        end
    end

    checkDailyReset(s)
    local adLimit = AD_LIMIT_OVERRIDE[key] or DAILY_AD_LIMIT
    local used = s.dailyAdCounts[key] or 0
    if used >= adLimit then
        return sendEvt(userId, "action_fail", { msg = "今日已达上限" })
    end
    s.dailyAdCounts[key] = used + 1
    s.totalAdWatched = s.totalAdWatched + 1

    -- === 合并后的3大福利 ===
    if key == "bless" then
        -- 仙缘加持: 客流翻倍5分钟 + 售价加成×1.5持续2小时
        s.adFlowBoostEnd = os.time() + 300
        s.adPriceBoostEnd = os.time() + 7200
    elseif key == "fortune" then
        -- 天降横财: 补货20分钟材料 + 神秘商人3倍清库存
        for _, mat in ipairs(Config.Materials) do
            if not (mat.celestial and not s.ascended) then addMaterial(s, mat.id, mat.rate * 20) end
        end
        local totalEarned = 0
        local realmMul = Config.GetRealmPriceMultiplier(s.realmLevel)
        for _, prod in ipairs(Config.Products) do
            local stock = s.products[prod.id]
            if stock and stock > 0 then
                local price = math.floor(prod.price * realmMul * 3)
                local total = price * stock
                s.products[prod.id] = 0
                addLingshi(s, total)
                totalEarned = totalEarned + total
            end
        end
        sendEvt(userId, "merchant_done", { earned = totalEarned })
    elseif key == "aid" then
        -- 修仙助力: 升级/突破减免30%×3次(2小时) + 离线延长+1小时
        s.adUpgradeDiscount = 3
        s.adDiscountExpire = os.time() + 7200
        if s.offlineAdExtend < OFFLINE_AD_MAX then
            s.offlineAdExtend = s.offlineAdExtend + 1
        end
    -- === 兼容旧key(防止旧客户端残留请求) ===
    elseif key == "flow" then
        s.adFlowBoostEnd = os.time() + 300
    elseif key == "supply" then
        for _, mat in ipairs(Config.Materials) do
            if not (mat.celestial and not s.ascended) then addMaterial(s, mat.id, mat.rate * 20) end
        end
    elseif key == "autosell" then
        s.adPriceBoostEnd = os.time() + 7200
    elseif key == "merchant" then
        local totalEarned = 0
        local realmMul = Config.GetRealmPriceMultiplier(s.realmLevel)
        for _, prod in ipairs(Config.Products) do
            local stock = s.products[prod.id]
            if stock and stock > 0 then
                local price = math.floor(prod.price * realmMul * 3)
                local total = price * stock
                s.products[prod.id] = 0
                addLingshi(s, total)
                totalEarned = totalEarned + total
            end
        end
        sendEvt(userId, "merchant_done", { earned = totalEarned })
    elseif key == "discount" then
        s.adUpgradeDiscount = 3
        s.adDiscountExpire = os.time() + 7200
    elseif key == "offline_extend" then
        if s.offlineAdExtend >= OFFLINE_AD_MAX then
            return sendEvt(userId, "action_fail", { msg = "已达上限" })
        end
        s.offlineAdExtend = s.offlineAdExtend + 1
    elseif key == "dungeon_ticket" then
        -- 🔴 先执行跨天重置检查: 如果玩家当天第一次操作是看广告而非进秘境,
        -- dungeonDailyDate 还是昨天的日期。若不先重置, 后续进秘境时
        -- checkDungeonDailyReset 会把今天刚获得的 bonus 一起清空。
        checkDungeonDailyReset(s)
        -- 秘境次数: 所有秘境各+3次
        if not s.dungeonBonusUses then s.dungeonBonusUses = {} end
        for _, dg in ipairs(Config.Dungeons) do
            s.dungeonBonusUses[dg.id] = (s.dungeonBonusUses[dg.id] or 0) + 3
        end
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "ad_reward_done", {
        key = key,
        adFlowBoostEnd = s.adFlowBoostEnd or 0,
        adPriceBoostEnd = s.adPriceBoostEnd or 0,
        adUpgradeDiscount = s.adUpgradeDiscount or 0,
        adDiscountExpire = s.adDiscountExpire or 0,
        offlineAdExtend = s.offlineAdExtend or 0,
        totalAdWatched = s.totalAdWatched or 0,
        dungeonBonusUses = s.dungeonBonusUses or {},
        dailyAdCounts = s.dailyAdCounts or {},
    })
end

ACTION_HANDLERS["refine"] = function(userId, s, rt, params)
    if s.realmLevel >= #Config.Realms then
        return sendEvt(userId, "action_fail", { msg = "已达最高境界" })
    end
    local cfg = Config.AbsorbConfig[s.realmLevel]
    if not cfg then
        return sendEvt(userId, "action_fail", { msg = "配置异常" })
    end
    local cost = math.floor(cfg.amount * cfg.ratio)
    if s.lingshi < cost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    s.lingshi = s.lingshi - cost
    addXiuwei(s, cfg.amount, userId)
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "refine_done", { cost = cost, gain = cfg.amount, lingshi = s.lingshi, xiuwei = s.xiuwei })
end

ACTION_HANDLERS["refine_batch"] = function(userId, s, rt, params)
    if s.realmLevel >= #Config.Realms then
        return sendEvt(userId, "action_fail", { msg = "已达最高境界" })
    end
    local cfg = Config.AbsorbConfig[s.realmLevel]
    if not cfg then
        return sendEvt(userId, "action_fail", { msg = "配置异常" })
    end
    local cost = math.floor(cfg.amount * cfg.ratio)
    local nextRealm = Config.Realms[s.realmLevel + 1]
    local totalCost, totalGain, count = 0, 0, 0
    while s.lingshi >= cost do
        s.lingshi = s.lingshi - cost
        addXiuwei(s, cfg.amount, userId)
        totalCost = totalCost + cost
        totalGain = totalGain + cfg.amount
        count = count + 1
        if nextRealm and s.xiuwei >= nextRealm.xiuwei then break end
    end
    if count == 0 then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "refine_batch_done", { totalCost = totalCost, totalGain = totalGain, count = count, lingshi = s.lingshi, xiuwei = s.xiuwei })
end

ACTION_HANDLERS["toggle_refine"] = function(userId, s, rt, params)
    s.autoRefine = not s.autoRefine
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "refine_toggled", { enabled = s.autoRefine, autoRefine = s.autoRefine })
end

ACTION_HANDLERS["toggle_auto_repair"] = function(userId, s, rt, params)
    s.autoRepairArtifacts = not s.autoRepairArtifacts
    rt.autoRepairTimer = 0
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "auto_repair_toggled", { enabled = s.autoRepairArtifacts, autoRepairArtifacts = s.autoRepairArtifacts })
end

ACTION_HANDLERS["newbie_gift"] = function(userId, s, rt, params)
    if s.newbieGiftClaimed then
        return sendEvt(userId, "action_fail", { msg = "已领取" })
    end
    local gift = Config.NewbieGift
    addLingshi(s, gift.lingshi)
    if gift.xiuwei then addXiuwei(s, gift.xiuwei) end
    if gift.materials then
        for matId, amount in pairs(gift.materials) do addMaterial(s, matId, amount) end
    end
    if gift.products then
        for prodId, amount in pairs(gift.products) do addProduct(s, prodId, amount) end
    end
    s.newbieGiftClaimed = true
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "newbie_gift_claimed", {})
end

ACTION_HANDLERS["mail_reward"] = function(userId, s, rt, params)
    local rewardType = params.rewardType or ""
    local rewardAmt  = tonumber(params.rewardAmt) or 0
    local title      = params.title or "邮件"
    print("[Server][MailReward] userId=" .. tostring(userId)
        .. " type=" .. rewardType .. " amt=" .. tostring(rewardAmt))

    if rewardAmt <= 0 then
        sendEvt(userId, "mail_reward_done", { title = title })
        return
    end

    if rewardType == "lingshi" then
        addLingshi(s, rewardAmt)
    elseif rewardType == "xiuwei" then
        addXiuwei(s, rewardAmt)
    elseif rewardType == "lingcao" or rewardType == "lingzhi" or rewardType == "xuantie"
        or rewardType == "yaodan" or rewardType == "jingshi" then
        addMaterial(s, rewardType, rewardAmt)
    end

    PlayerMgr_.SetDirty(userId)
    -- 携带即时同步字段，让客户端 applyInstantSync 立即更新而不必等 GameSync
    sendEvt(userId, "mail_reward_done", {
        title = title,
        rewardType = rewardType,
        rewardAmt = rewardAmt,
        lingshi = s.lingshi,
        xiuwei = s.xiuwei,
        materials = s.materials,
    })
    print("[Server][MailReward] 已发放, lingshi=" .. tostring(s.lingshi)
        .. " xiuwei=" .. tostring(s.xiuwei))
end

ACTION_HANDLERS["game_start"] = function(userId, s, rt, params)
    if not rt.gameStarted then
        rt.gameStarted = true
        print("[GameServer] game_start uid=" .. tostring(userId) .. " 游戏逻辑启动")
    end
end

ACTION_HANDLERS["story_played"] = function(userId, s, rt, params)
    s.storyPlayed = true
    PlayerMgr_.SetDirty(userId)
end

ACTION_HANDLERS["tutorial_step"] = function(userId, s, rt, params)
    local newStep = params and params.step or 0
    -- 只增不减
    if type(newStep) == "number" and newStep > (s.tutorialStep or 0) then
        s.tutorialStep = newStep
        PlayerMgr_.SetDirty(userId)
    end
end

ACTION_HANDLERS["guide_completed"] = function(userId, s, rt, params)
    s.guideCompleted = true
    PlayerMgr_.SetDirty(userId)
    print("[GameServer] guide_completed: uid=" .. tostring(userId) .. " guideCompleted=" .. tostring(s.guideCompleted))
end

ACTION_HANDLERS["set_settings"] = function(userId, s, rt, params)
    if params.bgmEnabled ~= nil then s.bgmEnabled = params.bgmEnabled end
    if params.sfxEnabled ~= nil then s.sfxEnabled = params.sfxEnabled end
    PlayerMgr_.SetDirty(userId)
end

ACTION_HANDLERS["player_info"] = function(userId, s, rt, params)
    if params.name then s.playerName = params.name end
    if params.gender then s.playerGender = params.gender end
    -- playerId 由服务端 OnPlayerLoaded 统一分配，不再接受客户端传入
    -- 角色信息是关键数据，立即保存到云端（不等 30s 定时保存）
    PlayerMgr_.SetDirty(userId)
    PlayerMgr_.SavePlayer(userId, function(ok)
        if ok then
            print("[GameServer] player_info 立即保存成功: uid=" .. tostring(userId) .. " name=" .. tostring(params.name))
        else
            print("[GameServer] player_info 立即保存失败: uid=" .. tostring(userId))
        end
    end)
end

ACTION_HANDLERS["check_online"] = function(userId, s, rt, params)
    local targetId = tonumber(params.targetId) or 0
    if targetId == 0 then return end
    local onlineUsers = GetOnlineUsers()
    local isOnline = false
    for _, uid in ipairs(onlineUsers) do
        if uid == targetId then isOnline = true; break end
    end
    sendEvt(userId, "online_status", { targetId = targetId, online = isOnline })
end

ACTION_HANDLERS["claim_offline"] = function(userId, s, rt, params)
    if not rt.pendingOffline then
        return sendEvt(userId, "action_fail", { msg = "无离线收益" })
    end
    local earnings = rt.pendingOffline
    local doubleMul = math.min(params.doubleMul or 1, 2)
    -- 发放材料
    for matId, amount in pairs(earnings.materials or {}) do
        if amount > 0 then addMaterial(s, matId, math.floor(amount)) end
    end
    -- 发放未售出商品
    if earnings.unsold then
        for prodId, count in pairs(earnings.unsold) do
            addProduct(s, prodId, count)
        end
    end
    -- 发放灵石(可翻倍)
    if earnings.lingshi and earnings.lingshi > 0 then
        addLingshi(s, math.floor(earnings.lingshi * doubleMul))
    end
    -- 领取后清零离线延长次数
    s.offlineAdExtend = 0
    rt.pendingOffline = nil
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "offline_claimed", { doubleMul = doubleMul })
end

-- ========== 秘境探险 ==========

--- 生成秘境探险运行时: 从事件池随机抽3个事件, 预掷骰子
---@param dungeonId string
---@return table dungeonState
local function createDungeonRun(dungeonId)
    local pool = Config.DungeonEvents[dungeonId]
    if not pool then return nil end
    -- 随机抽3个不重复事件
    local indices = {}
    for i = 1, #pool do indices[i] = i end
    -- Fisher-Yates shuffle
    for i = #indices, 2, -1 do
        local j = math.random(1, i)
        indices[i], indices[j] = indices[j], indices[i]
    end
    local events = {}
    for i = 1, math.min(3, #indices) do
        local evt = pool[indices[i]]
        -- 预掷骰子: 每个选项生成随机数(anti-cheat)
        local rolls = {}
        for ci, ch in ipairs(evt.choices) do
            rolls[ci] = math.random()
        end
        table.insert(events, {
            desc = evt.desc,
            choices = evt.choices,
            rolls = rolls,
        })
    end
    return {
        dungeonId = dungeonId,
        events = events,
        step = 1,       -- 当前事件索引(1~3)
        results = {},   -- 每步结果记录
        totalReward = {},-- 累计奖励汇总
        settled = false,
    }
end

local DUNGEON_HISTORY_TTL = 86400  -- 历史记录保留1天(秒)
local DUNGEON_HISTORY_MAX = 20     -- 最多保留条数

--- 清理过期秘境历史记录
local function pruneDungeonHistory(s)
    if not s.dungeonHistory then return end
    local now = os.time()
    local kept = {}
    for _, h in ipairs(s.dungeonHistory) do
        if (now - (h.time or 0)) < DUNGEON_HISTORY_TTL then
            table.insert(kept, h)
        end
    end
    -- 超出上限截断(保留最新)
    while #kept > DUNGEON_HISTORY_MAX do
        table.remove(kept, 1)
    end
    s.dungeonHistory = kept
end

--- 添加秘境历史记录
local function addDungeonHistory(s, dungeonId, results, totalReward, abandoned)
    if not s.dungeonHistory then s.dungeonHistory = {} end
    pruneDungeonHistory(s)
    table.insert(s.dungeonHistory, {
        time = os.time(),
        dungeonId = dungeonId,
        results = results,
        totalReward = totalReward,
        abandoned = abandoned or false,
    })
end

--- 过滤秘境选项敏感字段(仅发 text/type 给客户端, 隐藏 successRate/success/fail/rolls)
local function filterChoicesForClient(choices)
    if not choices then return {} end
    local filtered = {}
    for _, ch in ipairs(choices) do
        table.insert(filtered, { text = ch.text, type = ch.type })
    end
    return filtered
end

--- 获取某秘境今日已用次数
local function getDungeonDailyUses(s, dungeonId)
    checkDungeonDailyReset(s)
    if not s.dungeonDailyUses then s.dungeonDailyUses = {} end
    return s.dungeonDailyUses[dungeonId] or 0
end

--- 结算秘境奖励到玩家状态
local function settleDungeonRewards(s, totalReward)
    for key, amount in pairs(totalReward) do
        if key == "lingshi" then
            addLingshi(s, amount)
        elseif key == "xiuwei" then
            s.xiuwei = (s.xiuwei or 0) + amount
        else
            -- 材料奖励（包含凡间和仙界材料）
            if not s.materials then s.materials = {} end
            s.materials[key] = (s.materials[key] or 0) + amount
        end
    end
end

ACTION_HANDLERS["dungeon_enter"] = function(userId, s, rt, params)
    local dungeonId = params.dungeonId
    if not dungeonId then
        return sendEvt(userId, "action_fail", { msg = "参数缺失" })
    end
    -- 检查是否已在秘境中
    if rt.dungeonState then
        return sendEvt(userId, "action_fail", { msg = "已在秘境中" })
    end
    -- 检查每日次数(基础次数 + 广告奖励次数)
    -- 仙界秘境每日基础1次，凡间秘境3次
    local dgCfgForLimit = Config.GetDungeonById(dungeonId)
    local dailyLimit = (dgCfgForLimit and dgCfgForLimit.celestial) and 1 or (Config.DUNGEON_DAILY_LIMIT or 3)
    local bonusUses = (s.dungeonBonusUses and s.dungeonBonusUses[dungeonId]) or 0
    local totalLimit = dailyLimit + bonusUses
    local usedToday = getDungeonDailyUses(s, dungeonId)
    if usedToday >= totalLimit then
        return sendEvt(userId, "action_fail", { msg = "今日次数已用完" })
    end
    -- 检查秘境配置
    local cfg = Config.GetDungeonById(dungeonId)
    if not cfg then
        return sendEvt(userId, "action_fail", { msg = "秘境不存在" })
    end
    -- 检查境界要求
    local realmIdx = s.realmLevel or 1
    if realmIdx < cfg.unlockRealm then
        return sendEvt(userId, "action_fail", { msg = "境界不足" })
    end
    -- 检查灵石
    if (s.lingshi or 0) < cfg.cost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    -- 扣费
    addLingshi(s, -cfg.cost)
    -- 记录每日次数
    checkDungeonDailyReset(s)
    s.dungeonDailyUses[dungeonId] = usedToday + 1
    s.totalDungeonRuns = (s.totalDungeonRuns or 0) + 1
    -- 创建运行时
    local ds = createDungeonRun(dungeonId)
    if not ds then
        return sendEvt(userId, "action_fail", { msg = "事件池为空" })
    end
    rt.dungeonState = ds
    PlayerMgr_.SetDirty(userId)
    -- 发送第一个事件(过滤敏感字段)
    local firstEvt = ds.events[1]
    sendEvt(userId, "dungeon_enter", {
        dungeonId = dungeonId,
        step = 1,
        totalSteps = #ds.events,
        desc = firstEvt.desc,
        choices = filterChoicesForClient(firstEvt.choices),
        lingshi = s.lingshi,
        dungeonDailyUses = s.dungeonDailyUses,
        dungeonBonusUses = s.dungeonBonusUses or {},
    })
end

ACTION_HANDLERS["dungeon_choose"] = function(userId, s, rt, params)
    local choiceIdx = tonumber(params.choiceIdx)
    if not choiceIdx then
        return sendEvt(userId, "action_fail", { msg = "参数缺失" })
    end
    local ds = rt.dungeonState
    if not ds or ds.settled then
        return sendEvt(userId, "action_fail", { msg = "未在秘境中" })
    end
    local curEvt = ds.events[ds.step]
    if not curEvt then
        return sendEvt(userId, "action_fail", { msg = "事件异常" })
    end
    if choiceIdx < 1 or choiceIdx > #curEvt.choices then
        return sendEvt(userId, "action_fail", { msg = "选项无效" })
    end
    local choice = curEvt.choices[choiceIdx]
    local roll = curEvt.rolls[choiceIdx]
    local success = roll <= (choice.successRate or 1.0)
    -- 计算奖励
    local reward = {}
    local src = success and choice.success or choice.fail
    if src then
        for key, range in pairs(src) do
            local minV, maxV = range[1], range[2]
            if minV > maxV then minV, maxV = maxV, minV end
            local amount = (minV == maxV) and minV or math.random(minV, maxV)
            reward[key] = amount
            ds.totalReward[key] = (ds.totalReward[key] or 0) + amount
        end
    end
    -- 记录结果
    table.insert(ds.results, {
        step = ds.step,
        choiceIdx = choiceIdx,
        choiceText = choice.text,
        success = success,
        reward = reward,
    })
    -- 判断是否结束
    local isLast = ds.step >= #ds.events
    if isLast then
        -- 结算奖励
        settleDungeonRewards(s, ds.totalReward)
        ds.settled = true
    end
    PlayerMgr_.SetDirty(userId)
    -- 发送结果
    local evtData = {
        step = ds.step,
        choiceIdx = choiceIdx,
        choiceText = choice.text,
        success = success,
        reward = reward,
        totalReward = ds.totalReward,
        isLast = isLast,
        lingshi = s.lingshi,
        xiuwei = s.xiuwei,
    }
    if not isLast then
        -- 推进到下一事件
        ds.step = ds.step + 1
        local nextEvt = ds.events[ds.step]
        evtData.nextStep = ds.step
        evtData.nextDesc = nextEvt.desc
        evtData.nextChoices = filterChoicesForClient(nextEvt.choices)
    end
    sendEvt(userId, "dungeon_result", evtData)
    -- 如果结束, 记录历史并清理运行时; 掷骰珍藏掉落
    if isLast then
        addDungeonHistory(s, ds.dungeonId, ds.results, ds.totalReward, false)
        -- 珍藏物品掉落判定
        local drops = Config.DungeonDrops[ds.dungeonId]
        if drops then
            if not s.collectibles then s.collectibles = {} end
            local gained = {}
            for _, drop in ipairs(drops) do
                if math.random() < drop.chance then
                    s.collectibles[drop.id] = (s.collectibles[drop.id] or 0) + 1
                    table.insert(gained, drop.id)
                end
            end
            if #gained > 0 then
                sendEvt(userId, "collectible_gained", { items = gained, collectibles = s.collectibles })
            end
        end
        rt.dungeonState = nil
        advanceDailyTask(s, "dungeon", 1)
    end
end

ACTION_HANDLERS["dungeon_abandon"] = function(userId, s, rt, params)
    if not rt.dungeonState then
        return sendEvt(userId, "action_fail", { msg = "未在秘境中" })
    end
    local ds = rt.dungeonState
    -- 放弃时仍结算已获得的奖励
    if next(ds.totalReward) then
        settleDungeonRewards(s, ds.totalReward)
    end
    addDungeonHistory(s, ds.dungeonId, ds.results, ds.totalReward, true)
    rt.dungeonState = nil
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "dungeon_abandon", {
        totalReward = ds.totalReward,
        lingshi = s.lingshi,
        xiuwei = s.xiuwei,
    })
end

-- ========== GM 操作 (通过 GameAction 走服务端) ==========

--- GM 权限检查
local function isGM(userId)
    return GM_USER_IDS[tostring(userId)] == true
end

--- GM: 添加资源
ACTION_HANDLERS["gm_add"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local what = params.what  -- "lingshi" / "xiuwei" / "materials" / "products"
    local amount = tonumber(params.amount) or 0
    if what == "lingshi" then
        addLingshi(s, amount)
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "gm_result", { msg = "已添加 " .. amount .. " 灵石" })
    elseif what == "xiuwei" then
        addXiuwei(s, amount)
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "gm_result", { msg = "已添加 " .. amount .. " 修为" })
    elseif what == "materials" then
        for _, mat in ipairs(Config.Materials) do
            addMaterial(s, mat.id, amount)
        end
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "gm_result", { msg = "已添加全部材料各" .. amount })
    elseif what == "products" then
        for _, prod in ipairs(Config.Products) do
            addProduct(s, prod.id, amount)
        end
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "gm_result", { msg = "已添加全部商品各" .. amount })
    elseif what == "reputation" then
        s.reputation = math.min(1000, (s.reputation or 100) + amount)
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "gm_result", { msg = "口碑+" .. amount .. " 当前:" .. s.reputation })
    else
        sendEvt(userId, "action_fail", { msg = "未知资源类型: " .. tostring(what) })
    end
end

--- GM: 重置存档
ACTION_HANDLERS["gm_reset"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    -- 保留身份 + 转世信息
    local keep = {
        playerName   = s.playerName,
        playerGender = s.playerGender,
        playerId     = s.playerId,
        serverId     = s.serverId,
        rebirthCount = s.rebirthCount or 0,
        highestRealmEver = s.highestRealmEver or 1,
        redeemedCDKs = s.redeemedCDKs,
        storyPlayed  = s.storyPlayed,
        bgmEnabled   = s.bgmEnabled,
        sfxEnabled   = s.sfxEnabled,
    }
    -- 重置为默认状态
    local def = require("server_player").CreateDefaultState()
    for k, v in pairs(def) do s[k] = v end
    -- 恢复保留字段
    for k, v in pairs(keep) do s[k] = v end
    -- 清空运行时
    rt.customers = {}
    rt.craftQueue = {}
    rt.nextCustId = 1
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "gm_result", { msg = "本区数据已重置（保留角色名和转世）!" })
    -- 重新发送 GameInit 让客户端刷新完整状态（含 guideCompleted=false）
    M._doSendGameInit(userId)
end

--- GM: 删除区服数据(云端 iScore 归零 + gameState 清空, 支持指定区服)
ACTION_HANDLERS["gm_delete_server"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local PlayerMgr = require("server_player")
    -- 支持通过 params.sid 指定目标区服，默认当前区服
    local targetSid = (params and type(params.sid) == "number") and params.sid or (s.serverId or 0)
    local isCurrentServer = (targetSid == (s.serverId or 0))
    local rk = function(base) return PlayerMgr.RealmKey(base, targetSid) end

    -- 1) 云端归零: iScore 全部置 0, gameState 置空
    local ISCORE_KEYS = { "lingshi", "xiuwei", "totalEarned", "totalSold",
                          "totalCrafted", "totalAdWatched", "stallLevel", "realmLevel", "fengshuiLevel" }
    local todayKey = rk("earned_" .. getTodayKey())
    local batch = serverCloud:BatchSet(userId)
    for _, key in ipairs(ISCORE_KEYS) do batch:SetInt(rk(key), 0) end
    batch:SetInt(todayKey, 0)
    batch:Set(rk("gameState"), "")
    batch:Set(rk("playerName"), "")
    batch:Set(rk("playerGender"), "")
    batch:Set(rk("playerId"), "")
    batch:Save("gm_delete_server", {
        ok = function()
            -- 2) 仅删除当前区服时重置内存状态
            if isCurrentServer then
                local def = PlayerMgr.CreateDefaultState()
                for k, v in pairs(def) do s[k] = v end
                s.serverId = targetSid
                -- 清空运行时
                rt.customers = {}
                rt.craftQueue = {}
                rt.nextCustId = 1
                PlayerMgr_.SetDirty(userId)
                -- 重新发送 GameInit 让客户端刷新完整状态（含 guideCompleted=false）
                M._doSendGameInit(userId)
            end
            sendEvt(userId, "gm_result", { msg = "区服S" .. targetSid .. " 数据已删除!" })
        end,
        error = function(code, reason)
            sendEvt(userId, "gm_result", { msg = "删除失败: " .. tostring(reason) })
        end,
    })
    sendEvt(userId, "gm_result", { msg = "正在删除区服S" .. targetSid .. "数据..." })
end

-- ========== CDK 兑换码池（服务端 serverCloud 存储） ==========
-- 内存缓存: { "CODE" = { rewardKey, cdkType="single"|"universal", usedBy={uid,...} } }
local cdkPool_ = {}
local cdkPoolLoaded_ = false
local CLOUD_CDK_POOL_KEY = "cdk_pool"

--- 从 serverCloud 加载 CDK 池到内存
local function loadCdkPool(callback)
    if cdkPoolLoaded_ then
        if callback then callback() end
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    if not serverCloud then
        cdkPoolLoaded_ = true
        if callback then callback() end
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    serverCloud:Get(0, CLOUD_CDK_POOL_KEY, {
        ok = function(values)
            local raw = values and values[CLOUD_CDK_POOL_KEY]
            if raw and raw ~= "" then
                local ok2, pool = pcall(cjson.decode, raw)
                if ok2 and type(pool) == "table" then
                    cdkPool_ = pool
                end
            end
            cdkPoolLoaded_ = true
            print("[CDK] 加载 CDK 池: " .. M.CountTable(cdkPool_) .. " 个码")
            if callback then callback() end
        end,
        error = function(code, reason)
            print("[CDK] CDK 池加载失败: " .. tostring(reason))
            cdkPoolLoaded_ = true
            if callback then callback() end
        end,
    })
end

--- 持久化 CDK 池到 serverCloud
local function saveCdkPool()
    ---@diagnostic disable-next-line: undefined-global
    if not serverCloud then return end
    ---@diagnostic disable-next-line: undefined-global
    serverCloud:Set(0, CLOUD_CDK_POOL_KEY, cjson.encode(cdkPool_), {
        ok = function() end,
        error = function(code, reason)
            print("[CDK] CDK 池保存失败: " .. tostring(reason))
        end,
    })
end

--- 生成随机码 (DJBT-XXXX-XXXX)
local function generateCdkCode()
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local function rc()
        local idx = math.random(1, #chars)
        return chars:sub(idx, idx)
    end
    local part1 = rc() .. rc() .. rc() .. rc()
    local part2 = rc() .. rc() .. rc() .. rc()
    return Config.CDK_PREFIX .. "-" .. part1 .. "-" .. part2
end

--- 辅助: 统计 table 元素数
function M.CountTable(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

--- GM: 创建 CDK 码（服务端生成 + 入库）
ACTION_HANDLERS["gm_cdk_create"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local rewardKey = params.rewardKey or ""
    local cdkType = params.cdkType or "single"  -- "single" | "universal"
    local count = math.max(1, math.min(50, tonumber(params.count) or 1))
    local customReward = params.customReward  -- 自定义奖励 table (可选)

    -- 自定义奖励模式: 直接用 customReward, rewardKey 设为 "CUSTOM"
    local rewardName = ""
    if customReward and type(customReward) == "table" then
        rewardKey = "CUSTOM"
        -- 构建奖励名称
        local parts = {}
        if customReward.lingshi then table.insert(parts, "灵石" .. customReward.lingshi) end
        if customReward.xiuwei then table.insert(parts, "修为" .. customReward.xiuwei) end
        if customReward.materials and type(customReward.materials) == "table" then
            for k, v in pairs(customReward.materials) do
                table.insert(parts, tostring(k) .. tostring(v))
            end
        end
        if customReward.products and type(customReward.products) == "table" then
            for id, cnt in pairs(customReward.products) do
                local p = Config.GetProductById(id)
                table.insert(parts, (p and p.name or id) .. "x" .. cnt)
            end
        end
        if customReward.collectibles and type(customReward.collectibles) == "table" then
            for id, cnt in pairs(customReward.collectibles) do
                local c = Config.GetCollectibleById(id)
                table.insert(parts, (c and c.name or id) .. "x" .. cnt)
            end
        end
        rewardName = "自定义(" .. table.concat(parts, "+") .. ")"
    else
        if not Config.CDKRewards[rewardKey] then
            return sendEvt(userId, "gm_result", { msg = "奖励类型不存在: " .. rewardKey })
        end
        rewardName = Config.CDKRewards[rewardKey].name
    end

    loadCdkPool(function()
        local codes = {}
        for _ = 1, count do
            local code = generateCdkCode()
            -- 确保不重复
            while cdkPool_[code] do code = generateCdkCode() end
            cdkPool_[code] = {
                rewardKey = rewardKey,
                cdkType = cdkType,
                customReward = customReward,  -- 自定义奖励存储到 pool
                usedBy = {},
            }
            table.insert(codes, code)
        end
        saveCdkPool()
        local typeName = cdkType == "universal" and "通用码" or "单人码"
        print("[CDK] GM 创建 " .. count .. " 个" .. typeName .. " 奖励=" .. rewardName)
        sendEvt(userId, "cdk_created", {
            codes = codes,
            cdkType = cdkType,
            rewardName = rewardName,
        })
    end)
end

--- CDK 兑换（服务端验证 + 发放）
ACTION_HANDLERS["gm_cdk"] = function(userId, s, rt, params)
    local code = (params.code or ""):upper():gsub("%s", "")
    if code == "" then
        return sendEvt(userId, "cdk_result", { ok = false, msg = "请输入兑换码" })
    end

    loadCdkPool(function()
        local entry = cdkPool_[code]
        if not entry then
            return sendEvt(userId, "cdk_result", { ok = false, msg = "无效的兑换码" })
        end

        local uidStr = tostring(userId)

        local entryType = entry.cdkType or "single"

        -- 检查该用户是否已使用过此码
        for _, uid in ipairs(entry.usedBy or {}) do
            if tostring(uid) == uidStr then
                return sendEvt(userId, "cdk_result", { ok = false, msg = "你已使用过该兑换码" })
            end
        end

        -- 单人码: 已被他人使用则不可用（通用码跳过此检查）
        if entryType ~= "universal" and #(entry.usedBy or {}) > 0 then
            return sendEvt(userId, "cdk_result", { ok = false, msg = "该兑换码已被使用" })
        end

        -- 查找奖励
        local reward
        if entry.rewardKey == "CUSTOM" and entry.customReward then
            reward = entry.customReward
            reward.name = reward.name or "自定义奖励"
        else
            reward = Config.CDKRewards[entry.rewardKey]
        end
        if not reward then
            return sendEvt(userId, "cdk_result", { ok = false, msg = "奖励配置不存在" })
        end

        -- 发放奖励
        if reward.lingshi then addLingshi(s, reward.lingshi) end
        if reward.xiuwei then addXiuwei(s, reward.xiuwei) end
        if reward.materials then
            for matId, amount in pairs(reward.materials) do
                addMaterial(s, matId, amount)
            end
        end
        if reward.adFree and reward.adFreeDays then
            local now = os.time()
            local base = (s.adFreeExpire or 0) > now and s.adFreeExpire or now
            s.adFreeExpire = base + reward.adFreeDays * 86400
        end
        -- 发放丹药(products)
        if reward.products and type(reward.products) == "table" then
            for prodId, amount in pairs(reward.products) do
                addProduct(s, prodId, amount)
            end
        end
        -- 发放珍藏物品(collectibles)
        if reward.collectibles and type(reward.collectibles) == "table" then
            if not s.collectibles then s.collectibles = {} end
            for itemId, count in pairs(reward.collectibles) do
                s.collectibles[itemId] = (s.collectibles[itemId] or 0) + count
            end
        end

        -- 记录使用者
        if not entry.usedBy then entry.usedBy = {} end
        table.insert(entry.usedBy, userId)
        saveCdkPool()

        -- 玩家本地也记录（防重复显示）
        if not s.redeemedCDKs then s.redeemedCDKs = {} end
        table.insert(s.redeemedCDKs, code)
        PlayerMgr_.SetDirty(userId)

        print("[CDK] 兑换成功: uid=" .. tostring(userId) .. " code=" .. code
            .. " type=" .. (entry.cdkType or "single"))
        sendEvt(userId, "cdk_result", { ok = true, msg = reward.name .. " 兑换成功!", reward = reward })
    end)
end

--- GM: 重置排行榜(服务端 serverCloud 有权限)
ACTION_HANDLERS["gm_reset_rank"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local sid = tonumber(params.sid) or (s.serverId or 0)
    local rk = function(base)
        if not sid or sid == 0 then return base end
        return base .. "_" .. tostring(sid)
    end
    local todayKey = rk("earned_" .. getTodayKey())
    local ISCORE_KEYS = { "lingshi", "xiuwei", "totalEarned", "totalSold", "totalCrafted", "totalAdWatched", "stallLevel", "realmLevel", "fengshuiLevel" }
    local scanKeys = { rk("lingshi"), rk("totalEarned"), rk("realmLevel"), todayKey }
    local allResetKeys = {}
    for _, k in ipairs(ISCORE_KEYS) do allResetKeys[rk(k)] = true end
    allResetKeys[todayKey] = true

    -- 从各排行榜收集上榜用户ID
    local userIdSet = {}
    local pending = #scanKeys
    local function onScanDone()
        local userIds = {}
        for _, uid in pairs(userIdSet) do table.insert(userIds, uid) end
        if #userIds == 0 then
            sendEvt(userId, "gm_result", { msg = "区服S" .. sid .. " 排行榜为空" })
            return
        end
        local totalUsers = #userIds
        local doneCount = 0
        local failCount = 0
        for _, uid in ipairs(userIds) do
            local batch = serverCloud:BatchSet(uid)
            for key, _ in pairs(allResetKeys) do batch:SetInt(key, 0) end
            batch:Save("GM重置排行", {
                ok = function()
                    doneCount = doneCount + 1
                    if doneCount + failCount >= totalUsers then
                        sendEvt(userId, "gm_result", { msg = "区服S" .. sid .. " 排行已清零! 共" .. totalUsers .. "位玩家" })
                    end
                end,
                error = function(code, reason)
                    failCount = failCount + 1
                    if doneCount + failCount >= totalUsers then
                        sendEvt(userId, "gm_result", { msg = "重置完成(成功" .. doneCount .. "/失败" .. failCount .. ")" })
                    end
                end,
            })
        end
    end

    for _, scanKey in ipairs(scanKeys) do
        serverCloud:GetRankList(scanKey, 0, 100, {
            ok = function(rankList)
                for _, entry in ipairs(rankList or {}) do
                    userIdSet[entry.userId] = entry.userId
                end
                pending = pending - 1
                if pending <= 0 then onScanDone() end
            end,
            error = function()
                pending = pending - 1
                if pending <= 0 then onScanDone() end
            end,
        })
    end
    sendEvt(userId, "gm_result", { msg = "正在重置区服S" .. sid .. "排行..." })
end

--- GM: 封禁玩家（全局, 不分区服）
ACTION_HANDLERS["gm_ban"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local targetUid = params and tonumber(params.uid)
    if not targetUid then return sendEvt(userId, "gm_result", { msg = "缺少目标UID" }) end
    if not serverCloud then return sendEvt(userId, "gm_result", { msg = "serverCloud 不可用" }) end

    print("[GM_BAN] 开始封禁 targetUid=" .. tostring(targetUid) .. " type=" .. type(targetUid))
    serverCloud:BatchSet(targetUid)
        :Set("banned", "true")
        :Save("gm_ban", {
            ok = function()
                print("[GameServer] GM封禁玩家: uid=" .. tostring(targetUid))
                sendEvt(userId, "gm_result", { msg = "玩家 " .. tostring(targetUid) .. " 已封禁" })
                -- 如果在线则发送封禁通知（不断开连接）
                if GetConnection_ then
                    local conn = GetConnection_(targetUid)
                    if conn then
                        local kickData = VariantMap()
                        kickData["Reason"] = Variant("banned")
                        conn:SendRemoteEvent(EVENTS_.KICKED, true, kickData)
                        print("[GameServer] 已发送封禁通知给在线玩家: uid=" .. tostring(targetUid))
                    end
                end
            end,
            error = function(code, reason)
                sendEvt(userId, "gm_result", { msg = "封禁失败: " .. tostring(reason) })
            end,
        })
end

--- GM: 解封玩家
ACTION_HANDLERS["gm_unban"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local targetUid = params and tonumber(params.uid)
    if not targetUid then return sendEvt(userId, "gm_result", { msg = "缺少目标UID" }) end
    if not serverCloud then return sendEvt(userId, "gm_result", { msg = "serverCloud 不可用" }) end

    serverCloud:BatchSet(targetUid)
        :Set("banned", "")
        :Save("gm_unban", {
            ok = function()
                print("[GameServer] GM解封玩家: uid=" .. tostring(targetUid))
                if OnUnbanned_ then OnUnbanned_(targetUid) end
                sendEvt(userId, "gm_result", { msg = "玩家 " .. tostring(targetUid) .. " 已解封" })
            end,
            error = function(code, reason)
                sendEvt(userId, "gm_result", { msg = "解封失败: " .. tostring(reason) })
            end,
        })
end

-- ========== 版本管理 ==========

ACTION_HANDLERS["gm_set_version"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local ver = params and params.version
    if not ver or ver == "" then
        return sendEvt(userId, "gm_result", { msg = "请输入版本号" })
    end
    if not serverCloud then
        return sendEvt(userId, "gm_result", { msg = "serverCloud 不可用" })
    end
    serverCloud:Set(0, CLOUD_REQUIRED_VERSION_KEY, ver, {
        ok = function()
            requiredVersion_ = ver
            print("[GameServer] GM设置最低版本号: " .. ver .. " by uid=" .. tostring(userId))
            sendEvt(userId, "gm_result", { msg = "最低版本号已设置为: " .. ver })
        end,
        error = function(code, reason)
            sendEvt(userId, "gm_result", { msg = "设置失败: " .. tostring(reason) })
        end,
    })
end

ACTION_HANDLERS["gm_get_version"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    sendEvt(userId, "gm_version_info", {
        requiredVersion = requiredVersion_,
        clientVersion = Config.VERSION,
    })
end

-- ========== 调试白名单管理 ==========

--- 辅助: 将 debugWhitelist_ 持久化到 serverCloud
local function saveDebugWhitelist()
    if not serverCloud then return end
    local list = {}
    for uid, _ in pairs(debugWhitelist_) do
        list[#list + 1] = uid
    end
    serverCloud:Set(0, CLOUD_DEBUG_WHITELIST_KEY, cjson.encode(list), {
        ok = function() end,
        error = function(code, reason)
            print("[GameServer] 保存调试白名单失败: " .. tostring(reason))
        end,
    })
end

ACTION_HANDLERS["gm_debug_add"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local targetUid = tostring(params and params.uid or "")
    if targetUid == "" then
        return sendEvt(userId, "gm_result", { msg = "请输入用户ID" })
    end
    debugWhitelist_[targetUid] = true
    saveDebugWhitelist()
    -- 返回最新列表
    local list = {}
    for uid, _ in pairs(debugWhitelist_) do list[#list + 1] = uid end
    sendEvt(userId, "gm_debug_list", { list = list })
    sendEvt(userId, "gm_result", { msg = "已添加调试用户: " .. targetUid })
end

ACTION_HANDLERS["gm_debug_remove"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local targetUid = tostring(params and params.uid or "")
    if targetUid == "" then
        return sendEvt(userId, "gm_result", { msg = "请输入用户ID" })
    end
    debugWhitelist_[targetUid] = nil
    saveDebugWhitelist()
    local list = {}
    for uid, _ in pairs(debugWhitelist_) do list[#list + 1] = uid end
    sendEvt(userId, "gm_debug_list", { list = list })
    sendEvt(userId, "gm_result", { msg = "已移除调试用户: " .. targetUid })
end

ACTION_HANDLERS["gm_debug_list"] = function(userId, s, rt, params)
    if not isGM(userId) then return sendEvt(userId, "action_fail", { msg = "无权限" }) end
    local list = {}
    for uid, _ in pairs(debugWhitelist_) do list[#list + 1] = uid end
    sendEvt(userId, "gm_debug_list", { list = list })
end

-- ========== 珍藏物品使用 ==========

ACTION_HANDLERS["use_item"] = function(userId, s, rt, params)
    local itemId = params and params.itemId
    if not itemId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    local cfg = Config.GetCollectibleById(itemId)
    if not cfg then return sendEvt(userId, "action_fail", { msg = "未知物品" }) end
    if cfg.type ~= "consumable" then
        return sendEvt(userId, "action_fail", { msg = "该物品不可使用" })
    end
    if not s.collectibles then s.collectibles = {} end
    local have = s.collectibles[itemId] or 0
    if have < 1 then
        return sendEvt(userId, "action_fail", { msg = "数量不足" })
    end
    -- 扣除
    s.collectibles[itemId] = have - 1
    if s.collectibles[itemId] <= 0 then s.collectibles[itemId] = nil end
    -- 效果
    local msg = cfg.name .. " 使用成功"
    if cfg.effect == "add_xiuwei" then
        addXiuwei(s, cfg.effectValue)
        msg = msg .. "，修为+" .. cfg.effectValue
    elseif cfg.effect == "add_lifespan" then
        s.lifespan = s.lifespan + cfg.effectValue
        msg = msg .. "，寿元+" .. cfg.effectValue
    elseif cfg.effect == "breakthrough_discount" then
        -- 渡劫丹效果: 减少下次突破灵石消耗(存入临时标记)
        -- 渡劫丹作为突破材料消耗，不单独使用
        s.collectibles[itemId] = (s.collectibles[itemId] or 0) + 1 -- 退还
        return sendEvt(userId, "action_fail", { msg = "渡劫丹为突破材料，不可直接使用" })
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "item_used", {
        itemId = itemId,
        name = cfg.name,
        msg = msg,
        collectibles = s.collectibles,
        xiuwei = s.xiuwei,
        lifespan = s.lifespan,
    })
end

-- ========== 珍藏物品出售 ==========

ACTION_HANDLERS["sell_collectible"] = function(userId, s, rt, params)
    local itemId = params and params.itemId
    local amount = math.max(1, tonumber(params and params.amount) or 1)
    if not itemId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    local cfg = Config.GetCollectibleById(itemId)
    if not cfg then return sendEvt(userId, "action_fail", { msg = "未知物品" }) end
    if not s.collectibles then s.collectibles = {} end
    local have = s.collectibles[itemId] or 0
    -- 永久类必须保留1个(保持效果), 消耗品可全部出售
    local minKeep = (cfg.type == "permanent") and 1 or 0
    local maxSell = have - minKeep
    if maxSell <= 0 then
        local msg = cfg.type == "permanent" and "需保留至少1个以维持加成效果" or "数量不足"
        return sendEvt(userId, "action_fail", { msg = msg })
    end
    amount = math.min(amount, maxSell)
    local unitPrice = Config.GetCollectibleSellPrice(itemId)
    local totalPrice = unitPrice * amount
    s.collectibles[itemId] = have - amount
    if s.collectibles[itemId] <= 0 then s.collectibles[itemId] = nil end
    addLingshi(s, totalPrice)
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "collectible_sold", {
        itemId = itemId,
        name = cfg.name,
        amount = amount,
        unitPrice = unitPrice,
        totalPrice = totalPrice,
        lingshi = s.lingshi,
        collectibles = s.collectibles,
    })
end

-- ========== 仙界消耗品使用 ==========

ACTION_HANDLERS["use_collectible"] = function(userId, s, rt, params)
    local itemId = params and params.id
    if not itemId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    local cfg = Config.GetCollectibleById(itemId)
    if not cfg then return sendEvt(userId, "action_fail", { msg = "未知物品" }) end
    if cfg.type ~= "consumable" then
        return sendEvt(userId, "action_fail", { msg = "该物品不可使用" })
    end
    -- breakthrough_discount 为突破专用材料，不可手动消耗
    if cfg.effect == "breakthrough_discount" then
        return sendEvt(userId, "action_fail", { msg = "该材料为突破专用，不可手动使用" })
    end
    if not s.collectibles then s.collectibles = {} end
    local have = s.collectibles[itemId] or 0
    if have < 1 then
        return sendEvt(userId, "action_fail", { msg = "数量不足" })
    end
    -- 飞升检查
    if cfg.requireAscended and not s.ascended then
        return sendEvt(userId, "action_fail", { msg = "需要先飞升才可使用" })
    end
    -- 效果预校验（防止消耗物品却无效）
    local MAX_FABAO_BONUS = 20
    if cfg.effect == "add_fabao_count" then
        if (s.fabaoCount or 0) >= MAX_FABAO_BONUS then
            return sendEvt(userId, "action_fail", { msg = "法宝上限已达最大值(" .. MAX_FABAO_BONUS .. ")，无需使用" })
        end
    end
    -- 扣除
    s.collectibles[itemId] = have - 1
    if s.collectibles[itemId] <= 0 then s.collectibles[itemId] = nil end
    -- 效果
    local msg = cfg.name .. " 使用成功"
    if cfg.effect == "add_fabao_count" then
        local val = cfg.effectValue or 1
        local before = s.fabaoCount or 0
        s.fabaoCount = math.min(before + val, MAX_FABAO_BONUS)
        local actual = s.fabaoCount - before
        msg = msg .. "，法宝上限+" .. actual
        if s.fabaoCount >= MAX_FABAO_BONUS then
            msg = msg .. "（已达上限）"
        end
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "collectible_used", {
        id = itemId,
        name = cfg.name,
        effect = cfg.effect,
        effectValue = cfg.effectValue,
        msg = msg,
        collectibles = s.collectibles,
        fabaoCount = s.fabaoCount,
    })
end

-- ========== 法宝系统 ==========

ACTION_HANDLERS["craft_artifact"] = function(userId, s, rt, params)
    local artId = params and params.artId
    if not artId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    local artCfg = Config.GetArtifactById(artId)
    if not artCfg then return sendEvt(userId, "action_fail", { msg = "法宝不存在" }) end
    -- 境界检查
    if s.realmLevel < artCfg.unlockRealm then
        return sendEvt(userId, "action_fail", { msg = "境界不足，需要" .. (Config.Realms[artCfg.unlockRealm] and Config.Realms[artCfg.unlockRealm].name or "") })
    end
    -- 材料检查
    for matId, count in pairs(artCfg.recipe) do
        local have = s.materials and s.materials[matId] or 0
        if have < count then
            return sendEvt(userId, "action_fail", { msg = "材料不足" })
        end
    end
    -- 灵石检查
    if s.lingshi < artCfg.lingshiCost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    -- 扣材料
    for matId, count in pairs(artCfg.recipe) do
        s.materials[matId] = s.materials[matId] - count
    end
    -- 扣灵石
    s.lingshi = s.lingshi - artCfg.lingshiCost
    -- 加法宝(新增耐久字段)
    if not s.artifacts then s.artifacts = {} end
    if not s.artifacts[artId] then
        s.artifacts[artId] = { count = 0, level = 1 }
    end
    s.artifacts[artId].count = s.artifacts[artId].count + 1
    -- 每个法宝记录初始耐久(存在 artifacts 数据中, 装备时复制到 equippedArtifacts)
    PlayerMgr_.SetDirty(userId)
    sendSync(userId, s)
    sendEvt(userId, "artifact_crafted", { artId = artId, name = artCfg.name })
end

ACTION_HANDLERS["equip_artifact"] = function(userId, s, rt, params)
    local artId = params and params.artId
    if not artId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    local artCfg = Config.GetArtifactById(artId)
    if not artCfg then return sendEvt(userId, "action_fail", { msg = "法宝不存在" }) end
    -- 检查是否拥有
    if not s.artifacts or not s.artifacts[artId] or s.artifacts[artId].count < 1 then
        return sendEvt(userId, "action_fail", { msg = "未拥有该法宝" })
    end
    -- 检查是否已装备同款
    if not s.equippedArtifacts then s.equippedArtifacts = {} end
    for _, eq in ipairs(s.equippedArtifacts) do
        if eq.id == artId then
            return sendEvt(userId, "action_fail", { msg = "已装备同款法宝" })
        end
    end
    -- 检查装备栏位（基础栏位 + 法宝消耗品扩展的额外栏位）
    local maxSlots = Config.GetArtifactSlotCount(s.realmLevel) + (s.fabaoCount or 0)
    if #s.equippedArtifacts >= maxSlots then
        return sendEvt(userId, "action_fail", { msg = "装备栏已满(最多" .. maxSlots .. "个)" })
    end
    -- 装备(读取仓库中已有的耐久, 首次装备才用满值)
    local artData = s.artifacts[artId]
    local level = artData.level or 1
    local maxDur = Config.ArtifactDurability.max
    local dur = artData.durability or maxDur
    local wc = artData.wearCount or 0
    table.insert(s.equippedArtifacts, {
        id = artId,
        level = level,
        durability = dur,
        wearCount = wc,
    })
    PlayerMgr_.SetDirty(userId)
    sendSync(userId, s)
    sendEvt(userId, "artifact_equipped", { artId = artId })
end

ACTION_HANDLERS["unequip_artifact"] = function(userId, s, rt, params)
    local artId = params and params.artId
    if not artId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    if not s.equippedArtifacts then s.equippedArtifacts = {} end
    local found = false
    for i, eq in ipairs(s.equippedArtifacts) do
        if eq.id == artId then
            -- 卸下时把耐久/磨损回写到 artifacts 仓库, 防止重新装备后耐久重置
            if s.artifacts and s.artifacts[artId] then
                s.artifacts[artId].durability = eq.durability
                s.artifacts[artId].wearCount = eq.wearCount or 0
            end
            table.remove(s.equippedArtifacts, i)
            found = true
            break
        end
    end
    if not found then
        return sendEvt(userId, "action_fail", { msg = "未装备该法宝" })
    end
    PlayerMgr_.SetDirty(userId)
    sendSync(userId, s)
    sendEvt(userId, "artifact_unequipped", { artId = artId })
end

ACTION_HANDLERS["upgrade_artifact"] = function(userId, s, rt, params)
    local artId = params and params.artId
    if not artId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    local artCfg = Config.GetArtifactById(artId)
    if not artCfg then return sendEvt(userId, "action_fail", { msg = "法宝不存在" }) end
    if not s.artifacts or not s.artifacts[artId] then
        return sendEvt(userId, "action_fail", { msg = "未拥有该法宝" })
    end
    local artData = s.artifacts[artId]
    local curLevel = artData.level or 1
    if curLevel >= 10 then
        return sendEvt(userId, "action_fail", { msg = "法宝已达最高10阶" })
    end
    if artData.count < 3 then
        return sendEvt(userId, "action_fail", { msg = "需要3个同款法宝才能升阶" })
    end
    -- 消耗3个，等级+1
    artData.count = artData.count - 3
    artData.level = curLevel + 1
    -- 如果消耗后数量为0但有剩余等级，保留数据
    if artData.count < 0 then artData.count = 0 end
    -- 同步已装备法宝的等级
    if s.equippedArtifacts then
        for _, eq in ipairs(s.equippedArtifacts) do
            if eq.id == artId then
                eq.level = artData.level
            end
        end
    end
    PlayerMgr_.SetDirty(userId)
    sendSync(userId, s)
    sendEvt(userId, "artifact_upgraded", { artId = artId, newLevel = artData.level })
end

ACTION_HANDLERS["repair_artifact"] = function(userId, s, rt, params)
    local artId = params and params.artId
    if not artId then return sendEvt(userId, "action_fail", { msg = "参数错误" }) end
    if not s.equippedArtifacts then s.equippedArtifacts = {} end
    -- 找到已装备的该法宝
    local eq = nil
    for _, e in ipairs(s.equippedArtifacts) do
        if e.id == artId then eq = e; break end
    end
    if not eq then
        return sendEvt(userId, "action_fail", { msg = "未装备该法宝" })
    end
    local maxDur = Config.ArtifactDurability.max
    if (eq.durability or maxDur) >= maxDur then
        return sendEvt(userId, "action_fail", { msg = "耐久已满,无需修复" })
    end
    -- 计算修复费用
    local matCost, lingshiCost = Config.GetArtifactRepairCost(artId)
    if not matCost then
        return sendEvt(userId, "action_fail", { msg = "法宝配置异常" })
    end
    -- 检查材料
    for matId, count in pairs(matCost) do
        local have = s.materials and s.materials[matId] or 0
        if have < count then
            return sendEvt(userId, "action_fail", { msg = "修复材料不足" })
        end
    end
    -- 检查灵石
    if s.lingshi < lingshiCost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足" })
    end
    -- 扣材料
    for matId, count in pairs(matCost) do
        s.materials[matId] = s.materials[matId] - count
    end
    -- 扣灵石
    s.lingshi = s.lingshi - lingshiCost
    -- 恢复满耐久
    eq.durability = maxDur
    eq.wearCount = 0
    -- 同步回仓库(卸下时不会再丢数据)
    if s.artifacts and s.artifacts[artId] then
        s.artifacts[artId].durability = maxDur
        s.artifacts[artId].wearCount = 0
    end
    PlayerMgr_.SetDirty(userId)
    sendSync(userId, s)
    sendEvt(userId, "artifact_repaired", {
        artId = artId,
        durability = maxDur,
        lingshi = s.lingshi,
        materials = s.materials,
    })
end

-- ========== 师徒系统 ==========
ACTION_HANDLERS["mentor_invite"] = function(userId, s, rt, params)
    return MentorModule.HandleInvite(userId, s, rt, params)
end
ACTION_HANDLERS["mentor_accept"] = function(userId, s, rt, params)
    return MentorModule.HandleAccept(userId, s, rt, params)
end
ACTION_HANDLERS["mentor_reject"] = function(userId, s, rt, params)
    return MentorModule.HandleReject(userId, s, rt, params)
end
ACTION_HANDLERS["mentor_dismiss"] = function(userId, s, rt, params)
    return MentorModule.HandleDismiss(userId, s, rt, params)
end
ACTION_HANDLERS["mentor_query"] = function(userId, s, rt, params)
    return MentorModule.HandleQuery(userId, s, rt, params)
end
ACTION_HANDLERS["mentor_apply"] = function(userId, s, rt, params)
    return MentorModule.HandleApply(userId, s, rt, params)
end

ACTION_HANDLERS["mentor_gift"] = function(userId, s, rt, params)
    return MentorModule.HandleGift(userId, s, rt, params)
end

ACTION_HANDLERS["mentor_graduate"] = function(userId, s, rt, params)
    return MentorModule.HandleGraduationRequest(userId, s, rt, params)
end

-- ========== 渡劫 Boss 战 + 飞升 (功能10+11) ==========

-- 渡劫 Boss 战常量 (realm 9→10 的专属通关机制)
local TRIBULATION_REALM = 9  -- 渡劫期 = Realms[9]

ACTION_HANDLERS["tribulation_start"] = function(userId, s, rt, params)
    local boss = Config.TribulationBoss
    if not boss then
        return sendEvt(userId, "action_fail", { msg = "渡劫配置缺失" })
    end
    -- 境界检查: 必须在渡劫期
    if s.realmLevel ~= TRIBULATION_REALM then
        return sendEvt(userId, "action_fail", { msg = "只有渡劫期才能挑战天劫" })
    end
    -- 不能重复开始
    if s.tribulation_active then
        -- 已在进行中，直接恢复状态发给客户端
        return sendEvt(userId, "tribulation_state", {
            hp    = s.tribulation_hp,
            round = s.tribulation_round,
            maxHp = boss.maxHp,
            rounds = boss.rounds,
            roundNames = boss.roundNames,
            lingshi = s.lingshi,
        })
    end
    -- 修为检查 (需达到天仙门槛 1,800,000)
    local nextRealm = Config.Realms[TRIBULATION_REALM + 1]
    if not nextRealm then
        return sendEvt(userId, "action_fail", { msg = "目标境界配置缺失" })
    end
    if s.xiuwei < nextRealm.xiuwei then
        return sendEvt(userId, "action_fail", { msg = "修为不足(需" .. nextRealm.xiuwei .. ")" })
    end
    -- 初始化 Boss 状态
    s.tribulation_hp          = boss.maxHp
    s.tribulation_round       = 1
    s.tribulation_active      = true
    s.tribulation_allin_next  = false
    -- 为第一轮滚随机事件
    local firstEvent = nil
    if boss.events and #boss.events > 0 and math.random() < (boss.eventChance or 0) then
        local evIdx = math.random(1, #boss.events)
        firstEvent = boss.events[evIdx]
        s.tribulation_event_id = firstEvent.id
    else
        s.tribulation_event_id = nil
    end
    PlayerMgr_.SetDirty(userId)
    print("[Tribulation] 开始渡劫Boss战 uid=" .. userId .. " hp=" .. s.tribulation_hp)
    sendEvt(userId, "tribulation_state", {
        hp         = s.tribulation_hp,
        round      = s.tribulation_round,
        maxHp      = boss.maxHp,
        rounds     = boss.rounds,
        roundNames = boss.roundNames,
        lingshi    = s.lingshi,
        curEvent   = firstEvent and { id = firstEvent.id, name = firstEvent.name, desc = firstEvent.desc } or nil,
    })
end

ACTION_HANDLERS["tribulation_action"] = function(userId, s, rt, params)
    local boss = Config.TribulationBoss
    if not boss then return sendEvt(userId, "action_fail", { msg = "渡劫配置缺失" }) end
    if not s.tribulation_active then
        return sendEvt(userId, "action_fail", { msg = "当前未在渡劫中" })
    end

    local actionType = params.type or "attack"  -- "attack" | "defend" | "all_in"
    local round = s.tribulation_round
    local log = {}

    -- ===== 当前轮随机事件效果 =====
    local eventId = s.tribulation_event_id
    local curEvent = nil
    if eventId and boss.events then
        for _, ev in ipairs(boss.events) do
            if ev.id == eventId then curEvent = ev; break end
        end
    end
    local dmgMul       = (curEvent and curEvent.dmgMul)      or 1.0
    local costMul      = (curEvent and curEvent.costMul)     or 1.0
    local noBossAtk    = (curEvent and curEvent.noBossAtk)   or false
    local heavyChance  = (curEvent and curEvent.heavyChance) or boss.heavyChance

    -- 天劫蓄力：Boss 本轮先回复1HP
    if curEvent and curEvent.heal then
        local healed = math.min(curEvent.heal, boss.maxHp - s.tribulation_hp)
        if healed > 0 then
            s.tribulation_hp = s.tribulation_hp + healed
            table.insert(log, { type = "boss_heal", heal = healed })
        end
    end

    -- 豁命一击惩罚（上轮使用过全力一击，本轮 Boss 反击双倍）
    local allinPenalty = s.tribulation_allin_next or false
    s.tribulation_allin_next = false  -- 重置标志

    -- 各劫 Boss 反击系数（初劫0.5x → 终劫2.0x）
    local roundMuls = boss.roundBossMul or { 1, 1, 1, 1, 1 }
    local roundMul  = roundMuls[round] or 1.0
    if allinPenalty then roundMul = roundMul * 2.0 end

    -- ===== 玩家出招 =====
    local playerDmg = 0
    if actionType == "attack" then
        local actualCost = math.floor(boss.attackCost * costMul)
        if s.lingshi < actualCost then
            return sendEvt(userId, "action_fail", { msg = "灵石不足，无法施展法术" })
        end
        s.lingshi = s.lingshi - actualCost
        local isHeavy = math.random() < heavyChance
        if isHeavy then
            playerDmg = math.floor(boss.heavyDmgPct * boss.maxHp * dmgMul + 0.5)
        else
            playerDmg = math.floor(boss.normalDmgPct * boss.maxHp * dmgMul + 0.5)
        end
        table.insert(log, { type = "attack", dmg = playerDmg, cost = actualCost, isHeavy = isHeavy })

    elseif actionType == "all_in" then
        -- 豁命一击：3倍灵石，保证重击，但下轮 Boss 反击双倍
        local allInMul   = boss.allInCostMul or 3
        local actualCost = math.floor(boss.attackCost * allInMul * costMul)
        if s.lingshi < actualCost then
            return sendEvt(userId, "action_fail", { msg = "灵石不足，豁命需" .. actualCost .. "灵石" })
        end
        s.lingshi = s.lingshi - actualCost
        playerDmg = math.floor(boss.heavyDmgPct * boss.maxHp * dmgMul + 0.5)
        s.tribulation_allin_next = true  -- 标记下轮 Boss 双倍
        table.insert(log, { type = "all_in", dmg = playerDmg, cost = actualCost })

    elseif actionType == "defend" then
        local fabaoCount = #(s.equippedArtifacts or {})
        if fabaoCount < boss.defendFabao then
            return sendEvt(userId, "action_fail", { msg = "需要装备法宝才能防御" })
        end
        playerDmg = math.floor(boss.normalDmgPct * boss.maxHp * 0.5 + 0.5)
        table.insert(log, { type = "defend", fabao = boss.defendFabao })
    else
        return sendEvt(userId, "action_fail", { msg = "无效操作" })
    end

    -- ===== 对 Boss 造成伤害 =====
    s.tribulation_hp = math.max(0, s.tribulation_hp - playerDmg)

    -- ===== 判断 Boss 是否死亡 =====
    if s.tribulation_hp <= 0 then
        s.tribulation_hp     = 0
        s.tribulation_active = false
        s.tribulation_round  = 0
        s.tribulation_won    = true
        PlayerMgr_.SetDirty(userId)
        print("[Tribulation] Boss 击败! uid=" .. userId)
        return sendEvt(userId, "tribulation_win", {
            round   = round,
            log     = log,
            lingshi = s.lingshi,
        })
    end

    -- ===== Boss 反击 =====
    local bossDmg = 0
    local skipBossAtk = (noBossAtk and actionType ~= "defend")
    if skipBossAtk then
        table.insert(log, { type = "boss_skip" })
    elseif actionType == "defend" then
        bossDmg = math.floor(boss.normalDmgPct * boss.maxHp * boss.defendDmgMul * roundMul + 0.5)
        table.insert(log, { type = "boss_normal", dmg = bossDmg })
    else
        if math.random() < heavyChance then
            bossDmg = math.floor(boss.heavyDmgPct * boss.maxHp * roundMul + 0.5)
            if math.random() < 0.3 then
                bossDmg = bossDmg + math.floor(boss.extraDmgPct * boss.maxHp * roundMul + 0.5)
            end
            table.insert(log, { type = "boss_heavy", dmg = bossDmg })
        else
            bossDmg = math.floor(boss.normalDmgPct * boss.maxHp * roundMul + 0.5)
            table.insert(log, { type = "boss_normal", dmg = bossDmg })
        end
    end
    if not skipBossAtk and bossDmg > 0 then
        local lingshiLoss = math.min(bossDmg * boss.attackCost, s.lingshi)
        s.lingshi = math.max(0, s.lingshi - lingshiLoss)
        table.insert(log, { type = "boss_attack", dmg = bossDmg, lingshiLoss = lingshiLoss })
    end

    -- ===== 进入下一劫 =====
    s.tribulation_round = round + 1
    if s.tribulation_round > boss.rounds then
        -- 所有劫数用完但 Boss 未死亡 → 失败，扣30%灵石
        local penaltyPct = boss.failPenaltyPct or 0
        local penalty    = math.floor(s.lingshi * penaltyPct)
        s.lingshi = math.max(0, s.lingshi - penalty)
        s.tribulation_active = false
        s.tribulation_round  = 0
        s.tribulation_hp     = 0
        PlayerMgr_.SetDirty(userId)
        print("[Tribulation] 渡劫失败 uid=" .. userId .. " 罚没=" .. penalty)
        return sendEvt(userId, "tribulation_fail", {
            log     = log,
            lingshi = s.lingshi,
            penalty = penalty,
        })
    end

    -- 为下一轮滚随机事件
    local nextEvent = nil
    if boss.events and #boss.events > 0 and math.random() < (boss.eventChance or 0) then
        local evIdx = math.random(1, #boss.events)
        nextEvent = boss.events[evIdx]
        s.tribulation_event_id = nextEvent.id
    else
        s.tribulation_event_id = nil
    end

    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "tribulation_round", {
        round      = s.tribulation_round,
        hp         = s.tribulation_hp,
        maxHp      = boss.maxHp,
        rounds     = boss.rounds,
        roundNames = boss.roundNames,
        log        = log,
        lingshi    = s.lingshi,
        nextEvent  = nextEvent and { id = nextEvent.id, name = nextEvent.name, desc = nextEvent.desc } or nil,
        allinNext  = s.tribulation_allin_next,
    })
end

ACTION_HANDLERS["ascend"] = function(userId, s, rt, params)
    -- 飞升：Boss 战胜利后玩家确认飞升
    if s.tribulation_active then
        return sendEvt(userId, "action_fail", { msg = "渡劫未结束" })
    end
    if s.realmLevel ~= TRIBULATION_REALM then
        return sendEvt(userId, "action_fail", { msg = "境界不符" })
    end
    if s.ascended then
        return sendEvt(userId, "action_fail", { msg = "已经飞升" })
    end
    if not s.tribulation_won then
        return sendEvt(userId, "action_fail", { msg = "尚未通过天劫，请先挑战天劫Boss" })
    end
    -- 执行飞升: 晋级 天仙，标记 ascended
    local nextRealm = Config.Realms[TRIBULATION_REALM + 1]
    if not nextRealm then
        return sendEvt(userId, "action_fail", { msg = "目标境界配置缺失" })
    end
    s.realmLevel = TRIBULATION_REALM + 1
    s.ascended   = true
    if s.realmLevel > (s.highestRealmEver or 1) then
        s.highestRealmEver = s.realmLevel
    end
    -- 仙界寿元无限
    s.lifespan = nextRealm.lifespan
    PlayerMgr_.SetDirty(userId)
    print("[Ascend] 玩家飞升! uid=" .. userId .. " realm=" .. s.realmLevel)
    sendEvt(userId, "ascend_success", {
        realmLevel = s.realmLevel,
        realmName  = nextRealm.name,
        lingshi    = s.lingshi,
        xiuwei     = s.xiuwei,
        lifespan   = s.lifespan,
    })
end

-- ========== 风水阵升级 ==========
ACTION_HANDLERS["fengshui_upgrade"] = function(userId, s, rt, params)
    local formationId = params.formationId
    if not formationId then
        return sendEvt(userId, "action_fail", { msg = "缺少阵位ID" })
    end
    -- 验证阵位存在
    local found = false
    for _, f in ipairs(Config.FengshuiFormations) do
        if f.id == formationId then found = true; break end
    end
    if not found then
        return sendEvt(userId, "action_fail", { msg = "无效的阵位" })
    end
    if s.fengshui == nil then s.fengshui = {} end
    local curLevel = s.fengshui[formationId] or 0
    if curLevel >= Config.FengshuiMaxLevel then
        return sendEvt(userId, "action_fail", { msg = "已达最高等级" })
    end
    local cost = Config.GetFengshuiCost(curLevel)
    if s.lingshi < cost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足，需要" .. cost })
    end
    spendLingshi(s, cost)
    s.fengshui[formationId] = curLevel + 1
    PlayerMgr_.SetDirty(userId)
    -- 计算总等级和称号
    local totalLevel = 0
    for _, f in ipairs(Config.FengshuiFormations) do
        totalLevel = totalLevel + (s.fengshui[f.id] or 0)
    end
    -- 风水排行榜已通过 server_player BatchSet 同步，无需单独 SetScore
    local titleCfg = Config.GetFengshuiTitle(totalLevel)
    sendEvt(userId, "fengshui_upgraded", {
        formationId = formationId,
        newLevel = s.fengshui[formationId],
        cost = cost,
        lingshi = s.lingshi,
        totalLevel = totalLevel,
        title = titleCfg and titleCfg.title or nil,
        fengshui = s.fengshui,
    })
end

-- ========== 破镜丹商店购买 ==========
ACTION_HANDLERS["buy_pill"] = function(userId, s, rt, params)
    local itemId = params.itemId
    local amount = params.amount or 1
    if not itemId then
        return sendEvt(userId, "action_fail", { msg = "缺少物品ID" })
    end
    -- 查找商品配置
    local itemCfg = nil
    for _, item in ipairs(Config.PillShopItems) do
        if item.id == itemId then itemCfg = item; break end
    end
    if not itemCfg then
        return sendEvt(userId, "action_fail", { msg = "无效的商品" })
    end
    local totalCost = itemCfg.price * amount
    if s.lingshi < totalCost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足，需要" .. totalCost })
    end
    spendLingshi(s, totalCost)
    -- 添加到珍藏/消耗品库存
    if s.collectibles == nil then s.collectibles = {} end
    s.collectibles[itemId] = (s.collectibles[itemId] or 0) + amount
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "pill_purchased", {
        itemId = itemId,
        itemName = itemCfg.name,
        amount = amount,
        totalCost = totalCost,
        lingshi = s.lingshi,
        collectibles = s.collectibles,
    })
end

-- ========== 聚宝阁购买(替代buy_pill，支持材料+丹药) ==========
ACTION_HANDLERS["buy_marketplace"] = function(userId, s, rt, params)
    local itemId = params.itemId
    if not itemId then
        return sendEvt(userId, "action_fail", { msg = "缺少物品ID" })
    end
    -- 从聚宝阁商品列表查找
    local itemCfg = nil
    for _, item in ipairs(Config.MarketplaceItems) do
        if item.id == itemId then itemCfg = item; break end
    end
    if not itemCfg then
        return sendEvt(userId, "action_fail", { msg = "无效的商品" })
    end
    -- 仙界物品需飞升
    if itemCfg.celestial and not s.ascended then
        return sendEvt(userId, "action_fail", { msg = "需先飞升才能购买仙界物品" })
    end
    -- 每日限购校验
    checkDailyReset(s)
    local dailyLimit = itemCfg.dailyLimit
    local bought = 0
    if dailyLimit then
        if s.dailyShopBuys == nil then s.dailyShopBuys = {} end
        bought = s.dailyShopBuys[itemId] or 0
        if bought >= dailyLimit then
            return sendEvt(userId, "action_fail", { msg = itemCfg.name .. "今日已达限购上限(" .. dailyLimit .. ")" })
        end
    end
    -- 支持数量参数(默认1)
    local buyAmount = math.max(1, math.floor(tonumber(params.amount) or 1))
    -- 限购截断：不能超过今日剩余额度
    if dailyLimit then
        local remaining = dailyLimit - bought
        if buyAmount > remaining then
            buyAmount = remaining
        end
    end
    local unitPrice = itemCfg.price
    local totalCost = unitPrice * buyAmount
    if s.lingshi < totalCost then
        return sendEvt(userId, "action_fail", { msg = "灵石不足，需要" .. totalCost })
    end
    spendLingshi(s, totalCost)
    if itemCfg.isMaterial then
        -- 材料类：加入 materials
        if s.materials == nil then s.materials = {} end
        s.materials[itemId] = (s.materials[itemId] or 0) + buyAmount
    else
        -- 丹药/珍藏类：加入 collectibles
        if s.collectibles == nil then s.collectibles = {} end
        s.collectibles[itemId] = (s.collectibles[itemId] or 0) + buyAmount
    end
    -- 累加每日购买计数
    if dailyLimit then
        s.dailyShopBuys[itemId] = bought + buyAmount
    end
    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "marketplace_purchased", {
        itemId = itemId,
        itemName = itemCfg.name,
        amount = buyAmount,
        totalCost = totalCost,
        lingshi = s.lingshi,
        materials = s.materials,
        collectibles = s.collectibles,
        dailyShopBuys = s.dailyShopBuys,
    })
end

-- ========== 离线收益计算 ==========

function M.CalculateOfflineEarnings(s, offlineSeconds)
    local cap = OFFLINE_BASE_CAP + (s.offlineAdExtend or 0) * OFFLINE_AD_EXTEND
    offlineSeconds = math.min(offlineSeconds, cap)
    if offlineSeconds < 60 then return nil end

    local offlineMinutes = offlineSeconds / 60.0
    local rate = OFFLINE_RATE

    -- 材料(含法宝/珍藏加成，与在线逻辑一致)
    local artMatBonus = 1.0 + getArtifactBonus(s, "material_rate")
    local matPool = {}
    for _, mat in ipairs(Config.Materials) do
        if not (mat.celestial and not s.ascended) then
            local collMatBonus = 1.0 + getCollectibleBonus(s, "material_rate_" .. mat.id)
            matPool[mat.id] = math.floor(mat.rate * offlineMinutes * rate * artMatBonus * collMatBonus)
        end
    end

    -- 灵童状态检测
    local sv = s.fieldServant
    local now = os.time()
    local offlineStart = now - offlineSeconds
    local servantActive = sv and sv.tier > 0 and not sv.paused and sv.expireTime > offlineStart
    local servantCfg = servantActive and Config.FieldServants[sv.tier] or nil
    local servantSeconds = servantActive and math.min(offlineSeconds, sv.expireTime - offlineStart) or 0
    local speedBonus = servantCfg and servantCfg.abilities.speedBonus or 0
    local canHarvest = servantCfg and servantCfg.abilities.harvest or false
    local canPlant = servantCfg and servantCfg.abilities.plant or false
    local servantInfo = nil
    local fieldHarvests = {}  -- {cropId = totalCycles} 用于弹窗展示
    local fieldYields = {}    -- {matId = totalAmount} 灵童具体产出

    -- 灵田
    local plots = s.fieldPlots or {}
    local lvl = math.min(s.fieldLevel or 1, #Config.FieldLevels)
    local maxPlots = Config.FieldLevels[lvl].plots
    for i = 1, maxPlots do
        local plot = plots[i]
        local hasCrop = plot and plot.cropId and plot.cropId ~= "" and plot.plantTime
        if hasCrop then
            local crop = nil
            for _, c in ipairs(Config.Crops) do if c.id == plot.cropId then crop = c; break end end
            if crop then
                local growTime = crop.growTime / (1 + speedBonus)
                if canHarvest and canPlant then
                    -- 灵童自动收获+重种: 用灵童有效时间算完整循环
                    local cycles = math.floor(servantSeconds / growTime)
                    cycles = math.max(cycles, 1)
                    for matId, amount in pairs(crop.yield) do
                        local gained = math.floor(amount * cycles * rate)
                        matPool[matId] = (matPool[matId] or 0) + gained
                        fieldYields[matId] = (fieldYields[matId] or 0) + gained
                    end
                    fieldHarvests[crop.id] = (fieldHarvests[crop.id] or 0) + cycles
                elseif canHarvest then
                    -- 灵童仅收获不重种: 成熟就收1次
                    local elapsed = now - plot.plantTime
                    if elapsed >= growTime then
                        for matId, amount in pairs(crop.yield) do
                            local gained = math.floor(amount * rate)
                            matPool[matId] = (matPool[matId] or 0) + gained
                            fieldYields[matId] = (fieldYields[matId] or 0) + gained
                        end
                        fieldHarvests[crop.id] = (fieldHarvests[crop.id] or 0) + 1
                    end
                else
                    -- 无灵童: 原逻辑(不加速)
                    local elapsed = now - plot.plantTime
                    local totalTime = math.max(elapsed, offlineSeconds)
                    local cycles = math.floor(totalTime / crop.growTime)
                    if elapsed >= crop.growTime then cycles = math.max(cycles, 1) end
                    for matId, amount in pairs(crop.yield) do
                        matPool[matId] = (matPool[matId] or 0) + math.floor(amount * cycles * rate)
                    end
                end
            end
        elseif canPlant and servantActive then
            -- 空地+灵童可种植: 按分田配置或全局配置补算
            local plotCrops = sv.plotCrops
            local defaultCrop = sv.plantCrop or "lingcao_seed"
            local cropId = (plotCrops and plotCrops[tostring(i)]) or defaultCrop
            local crop = nil
            for _, c in ipairs(Config.Crops) do if c.id == cropId then crop = c; break end end
            if crop then
                local growTime = crop.growTime / (1 + speedBonus)
                local cycles = math.floor(servantSeconds / growTime)
                if cycles > 0 then
                    for matId, amount in pairs(crop.yield) do
                        local gained = math.floor(amount * cycles * rate)
                        matPool[matId] = (matPool[matId] or 0) + gained
                        fieldYields[matId] = (fieldYields[matId] or 0) + gained
                    end
                    fieldHarvests[crop.id] = (fieldHarvests[crop.id] or 0) + cycles
                end
            end
        end
    end

    if servantActive then
        servantInfo = {
            name = servantCfg.name,
            tier = sv.tier,
            speedBonus = speedBonus,
            minutes = math.floor(servantSeconds / 60),
            harvests = fieldHarvests,
            yields = fieldYields,
        }
    end

    -- 傀儡状态检测
    local pp = s.craftPuppet
    local puppetActive = pp and pp.active and not pp.paused and pp.expireTime > offlineStart
    local puppetSeconds = puppetActive and math.min(offlineSeconds, pp.expireTime - offlineStart) or 0
    local puppetInfo = nil

    -- 自动制作
    local sortedProducts = {}
    if puppetActive and pp.products and #pp.products > 0 then
        -- 傀儡激活: 只制作傀儡配置的产品
        for _, prodId in ipairs(pp.products) do
            local prodCfg = Config.GetProductById(prodId)
            if prodCfg then table.insert(sortedProducts, prodCfg) end
        end
    else
        -- 无傀儡: 所有已解锁产品
        for i, prod in ipairs(Config.Products) do
            if Config.IsProductUnlocked(i, s.realmLevel) then
                table.insert(sortedProducts, prod)
            end
        end
    end
    table.sort(sortedProducts, function(a, b) return a.price > b.price end)

    -- 灵童产出不参与自动制作/出售, 先从 matPool 中移除
    for matId, amount in pairs(fieldYields) do
        matPool[matId] = (matPool[matId] or 0) - amount
        if matPool[matId] <= 0 then matPool[matId] = nil end
    end

    local craftedProducts = {}
    local changed = true
    while changed do
        changed = false
        for _, prod in ipairs(sortedProducts) do
            if (matPool[prod.materialId] or 0) >= prod.materialCost then
                matPool[prod.materialId] = matPool[prod.materialId] - prod.materialCost
                craftedProducts[prod.id] = (craftedProducts[prod.id] or 0) + 1
                changed = true
            end
        end
    end

    -- 灵童产出加回 matPool(作为剩余材料返回给客户端)
    for matId, amount in pairs(fieldYields) do
        matPool[matId] = (matPool[matId] or 0) + amount
    end

    if puppetActive then
        local puppetProdNames = {}
        for _, prodId in ipairs(pp.products or {}) do
            local prodCfg = Config.GetProductById(prodId)
            if prodCfg then table.insert(puppetProdNames, prodCfg.name) end
        end
        puppetInfo = {
            name = "炼器傀儡",
            minutes = math.floor(puppetSeconds / 60),
            products = puppetProdNames,
        }
    end

    -- 自动售卖
    local stallCfg = getStallConfig(s)
    local speedMul = stallCfg.speedMul * Config.GetRealmSpeedMultiplier(s.realmLevel)
    local spawnInterval = CUSTOMER_SPAWN_BASE / speedMul
    local maxCustomers = math.floor(offlineSeconds / spawnInterval)

    local avgPayMul, totalWeight = 0, 0
    for _, ct in ipairs(Config.CustomerTypes) do
        avgPayMul = avgPayMul + ct.payMul * ct.weight
        totalWeight = totalWeight + ct.weight
    end
    avgPayMul = avgPayMul / totalWeight
    local matchRate = 0.3

    local totalProducts = 0
    for _, count in pairs(craftedProducts) do totalProducts = totalProducts + count end
    local existingProducts = {}
    for _, prod in ipairs(Config.Products) do
        local stock = s.products[prod.id] or 0
        if stock > 0 then existingProducts[prod.id] = stock; totalProducts = totalProducts + stock end
    end

    local soldCount = math.min(maxCustomers, totalProducts)
    local totalLingshi = 0
    local soldProducts = {}
    local remaining = soldCount
    for _, prod in ipairs(sortedProducts) do
        if remaining <= 0 then break end
        local avail = (craftedProducts[prod.id] or 0) + (existingProducts[prod.id] or 0)
        if avail > 0 then
            local sell = math.min(avail, remaining)
            local basePrice = getProductPrice(s, prod)
            local avgPrice = basePrice * avgPayMul * (1 + matchRate * (Config.DemandMatchBonus - 1))
            totalLingshi = totalLingshi + math.floor(avgPrice * sell * rate)
            soldProducts[prod.id] = sell
            remaining = remaining - sell
        end
    end

    local unsoldProducts = {}
    for prodId, count in pairs(craftedProducts) do
        local sold = soldProducts[prodId] or 0
        if count - sold > 0 then unsoldProducts[prodId] = count - sold end
    end

    return {
        hasEarnings = true,
        offlineSeconds = offlineSeconds,
        minutes = math.floor(offlineMinutes),
        rate = rate,
        materials = matPool,
        crafted = craftedProducts,
        sold = soldProducts,
        unsold = unsoldProducts,
        lingshi = totalLingshi,
        soldCount = soldCount,
        servantInfo = servantInfo,
        puppetInfo = puppetInfo,
    }
end

-- ========== 公开接口 ==========

local OnBanned_ = nil    -- 封禁回调（通知 server_main 缓存封禁用户）
local OnUnbanned_ = nil  -- 解封回调（通知 server_main 清除封禁缓存）

--- 初始化
---@param deps table { SendToClient, PlayerMgr, EVENTS, GetConnection, OnBanned, OnUnbanned }
function M.Init(deps)
    SendToClient_ = deps.SendToClient
    PlayerMgr_ = deps.PlayerMgr
    EVENTS_ = deps.EVENTS
    GetConnection_ = deps.GetConnection
    AllocatePlayerId_ = deps.AllocatePlayerId
    GetServerName_ = deps.GetServerName
    OnBanned_ = deps.OnBanned
    OnUnbanned_ = deps.OnUnbanned
    -- 加载全局最低版本号
    if serverCloud then
        serverCloud:Get(0, CLOUD_REQUIRED_VERSION_KEY, {
            ok = function(values)
                local raw = values and values[CLOUD_REQUIRED_VERSION_KEY]
                if raw and raw ~= "" then
                    requiredVersion_ = raw
                    print("[GameServer] 已加载最低版本号: " .. requiredVersion_)
                else
                    print("[GameServer] 未设置最低版本号")
                end
            end,
            error = function(code, reason)
                print("[GameServer] 加载最低版本号失败: " .. tostring(reason))
            end,
        })
        -- 加载调试白名单
        serverCloud:Get(0, CLOUD_DEBUG_WHITELIST_KEY, {
            ok = function(values)
                local raw = values and values[CLOUD_DEBUG_WHITELIST_KEY]
                if raw and raw ~= "" then
                    local ok2, decoded = pcall(cjson.decode, raw)
                    if ok2 and type(decoded) == "table" then
                        debugWhitelist_ = {}
                        for _, uid in ipairs(decoded) do
                            debugWhitelist_[tostring(uid)] = true
                        end
                        print("[GameServer] 已加载调试白名单: " .. #decoded .. " 人")
                    end
                else
                    print("[GameServer] 调试白名单为空")
                end
            end,
            error = function(code, reason)
                print("[GameServer] 加载调试白名单失败: " .. tostring(reason))
            end,
        })
    end
    -- 初始化师徒系统
    MentorModule.Init({
        SendToClient = SendToClient_,
        PlayerMgr = PlayerMgr_,
        EVENTS = EVENTS_,
        GetConnection = GetConnection_,
        GetServerName = GetServerName_,
        sendEvt = sendEvt,
    })

    print("[GameServer] 初始化完成")
end

--- 玩家加载完成后调用
---@param userId number
--- 玩家数据加载完成，初始化运行时状态
---@param userId number
---@param sendGameInit boolean|nil 是否发送GameInit（默认true，预加载时传false）
function M.OnPlayerLoaded(userId, sendGameInit)
    local s = PlayerMgr_.GetState(userId)
    if not s then return end

    -- ===== 旧存档字段迁移(防 nil 崩溃) =====
    if s.reputation == nil then s.reputation = 100 end
    if s.repStreak == nil then s.repStreak = 0 end
    if s.totalBargains == nil then s.totalBargains = 0 end
    if s.bargainWins == nil then s.bargainWins = 0 end
    if s.dailyTasks == nil then s.dailyTasks = {} end
    if s.dailyTaskDate == nil then s.dailyTaskDate = "" end
    if s.dailyTasksClaimed == nil then s.dailyTasksClaimed = 0 end
    if s.todayEarned == nil then s.todayEarned = 0 end
    if s.todayDate == nil then s.todayDate = "" end
    if s.fieldLevel == nil then s.fieldLevel = 1 end
    if s.fieldPlots == nil then s.fieldPlots = {} end
    if s.autoRefine == nil then s.autoRefine = false end
    if s.autoRepairArtifacts == nil then s.autoRepairArtifacts = false end
    if s.fieldServant == nil then s.fieldServant = { tier = 0, expireTime = 0, plantCrop = "lingcao_seed" } end
    if s.craftPuppet == nil then s.craftPuppet = { active = false, expireTime = 0, products = {} } end
    if s.craftPuppet.craftMode == nil then s.craftPuppet.craftMode = "priority" end
    if s.redeemedCDKs == nil then s.redeemedCDKs = {} end
    if s.offlineAdExtend == nil then s.offlineAdExtend = 0 end
    if s.dailyAdCounts == nil then s.dailyAdCounts = {} end
    if s.dailyAdDate == nil then s.dailyAdDate = "" end
    if s.dungeonHistory == nil then s.dungeonHistory = {} end
    if s.dungeonDailyUses == nil then s.dungeonDailyUses = {} end
    if s.dungeonDailyDate == nil then s.dungeonDailyDate = "" end
    if s.dungeonBonusUses == nil then s.dungeonBonusUses = {} end
    -- 渡劫小游戏字段兜底
    if s.dujieDailyDate == nil then s.dujieDailyDate = "" end
    if s.dujieFreeUses == nil then s.dujieFreeUses = 0 end
    if s.dujiePaidUses == nil then s.dujiePaidUses = 0 end
    -- 渡劫 Boss 战字段兜底 (功能10)
    if s.tribulation_hp == nil then s.tribulation_hp = 0 end
    if s.tribulation_round == nil then s.tribulation_round = 0 end
    if s.tribulation_active == nil then s.tribulation_active = false end
    if s.tribulation_won == nil then s.tribulation_won = false end
    if s.tribulation_event_id == nil then s.tribulation_event_id = nil end
    if s.tribulation_allin_next == nil then s.tribulation_allin_next = false end
    -- 飞升/仙界字段兜底 (功能11)
    if s.ascended == nil then s.ascended = false end
    -- realmLevel>=10 说明已经是仙界境界，ascended 必须为 true
    if s.realmLevel >= 10 and not s.ascended then
        s.ascended = true
        print("[OnPlayerLoaded] 自动修正 ascended=true (realmLevel=" .. s.realmLevel .. ")")
    end
    if s.artifacts == nil then s.artifacts = {} end
    if s.equippedArtifacts == nil then s.equippedArtifacts = {} end
    -- 已装备法宝: 旧存档补充耐久字段
    for _, eq in ipairs(s.equippedArtifacts) do
        if eq.durability == nil then eq.durability = Config.ArtifactDurability.max end
        if eq.wearCount == nil then eq.wearCount = 0 end
    end
    if s.collectibles == nil then s.collectibles = {} end
    -- 风水阵字段兜底
    if s.fengshui == nil then s.fengshui = {} end
    if s.lastBroadcastId == nil then s.lastBroadcastId = 0 end
    if s.lastAdNonces == nil then s.lastAdNonces = {} end
    -- 师徒系统字段兜底
    if s.masterId == nil then s.masterId = nil end
    if s.masterName == nil then s.masterName = "" end
    if s.masterRealmAtBind == nil then s.masterRealmAtBind = 0 end
    if s.disciples == nil then s.disciples = {} end
    if s.mentorXiuweiEarned == nil then s.mentorXiuweiEarned = 0 end
    if s.graduatedCount == nil then s.graduatedCount = 0 end
    if s.pendingMentorInvites == nil then s.pendingMentorInvites = {} end
    -- 灵童分田种植: 旧存档兜底 plotCrops
    if s.fieldServant and s.fieldServant.plotCrops == nil then
        s.fieldServant.plotCrops = nil  -- 明确保留 nil, 回退到 plantCrop
    end
    -- 转世丢失 guideCompleted 的存档修复: 转世过的玩家必定已完成引导
    if not s.guideCompleted and (s.rebirthCount or 0) >= 1 then
        s.guideCompleted = true
        PlayerMgr_.SetDirty(userId)
        print("[GameServer] OnPlayerLoaded: 修复转世丢失的 guideCompleted uid=" .. tostring(userId))
    end
    -- 确保所有产品都有初始值(防 getAvailableProducts 中 nil > 0 崩溃)
    if s.products then
        for _, prod in ipairs(Config.Products) do
            if s.products[prod.id] == nil then s.products[prod.id] = 0 end
        end
    end

    -- 服务端分配角色ID: 空ID或旧6位随机ID(100000-999999)均重新分配
    local needNewId = (not s.playerId or s.playerId == "")
    if not needNewId and s.playerId then
        local num = tonumber(s.playerId)
        if num and num >= 100000 and num <= 999999 then
            needNewId = true -- 旧的6位随机ID，重新分配
        end
    end
    if needNewId and AllocatePlayerId_ then
        local oldId = s.playerId or ""
        s.playerId = AllocatePlayerId_()
        PlayerMgr_.SetDirty(userId)
        print("[GameServer] 为玩家分配角色ID: uid=" .. tostring(userId) .. " playerId=" .. s.playerId .. " (旧ID=" .. oldId .. ")")
    end

    -- 写入角色ID → 平台UID 反向索引（供GM工具离线查询用）
    -- userId=0 为全局共享存储，pidKey 格式: "pid2uid_1000001"
    if s.playerId and s.playerId ~= "" and serverCloud then
        local pidKey = "pid2uid_" .. s.playerId
        serverCloud:Set(0, pidKey, tostring(userId), {
            ok = function() end,
            error = function(code, reason)
                print("[GameServer] 角色ID反向索引写入失败: " .. tostring(reason))
            end,
        })
    end

    -- 刷新每日任务
    refreshDailyTasks(s)

    local rt = createRuntime()
    runtimes_[userId] = rt

    -- 老玩家自动启动游戏逻辑(已经历过剧情，不需等客户端 game_start)
    -- 修复: 身份升级路径下客户端回调链断裂导致 game_start 永不发送的问题
    if s.storyPlayed then
        rt.gameStarted = true
        print("[GameServer] OnPlayerLoaded: 老玩家自动 gameStarted=true uid=" .. tostring(userId))
    end

    -- 恢复制作队列
    if s.craftQueue then
        for _, task in ipairs(s.craftQueue) do
            table.insert(rt.craftQueue, {
                productId = task.productId,
                remainTime = task.remainTime or 0,
                totalTime = task.totalTime or 0,
            })
        end
    end

    -- 计算离线收益
    local sid = PlayerMgr_.GetServerId and PlayerMgr_.GetServerId(userId) or -1
    if s.lastSaveTime and s.lastSaveTime > 0 then
        local offlineSeconds = os.time() - s.lastSaveTime
        print("[Offline-Diag] OnPlayerLoaded uid=" .. tostring(userId) .. " sid=" .. tostring(sid)
            .. " lastSaveTime=" .. tostring(s.lastSaveTime) .. " offlineSec=" .. tostring(offlineSeconds)
            .. " sendGameInit=" .. tostring(sendGameInit))
        if offlineSeconds >= 60 then
            rt.pendingOffline = M.CalculateOfflineEarnings(s, offlineSeconds)
            print("[Offline-Diag] pendingOffline created: hasEarnings=" .. tostring(rt.pendingOffline and rt.pendingOffline.hasEarnings))
        end
        -- 结算离线师徒收益
        MentorModule.SettleOfflineMentorRewards(userId, s)
    else
        print("[Offline-Diag] OnPlayerLoaded uid=" .. tostring(userId) .. " sid=" .. tostring(sid)
            .. " lastSaveTime=" .. tostring(s.lastSaveTime) .. " (no save time, skip)")
    end

    -- 发送 GameInit（预加载阶段跳过，等 CLIENT_READY 后由 HandleClientReady 发送）
    if sendGameInit ~= false then
        M.SendGameInit(userId)
    end
end

--- 玩家断开连接
---@param userId number
function M.OnPlayerDisconnect(userId)
    local rt = runtimes_[userId]
    if rt then
        -- 保存制作队列到 state
        local s = PlayerMgr_.GetState(userId)
        if s then
            s.craftQueue = {}
            for _, task in ipairs(rt.craftQueue) do
                table.insert(s.craftQueue, {
                    productId = task.productId,
                    remainTime = task.remainTime,
                    totalTime = task.totalTime,
                })
            end
            PlayerMgr_.SetDirty(userId)
        end
        runtimes_[userId] = nil
    end
end

--- 每帧更新所有在线玩家
---@param dt number
function M.Update(dt)
    for _, userId in ipairs(PlayerMgr_.GetAllPlayerIds()) do
        local s = PlayerMgr_.GetState(userId)
        local rt = runtimes_[userId]
        if s and rt then
            -- pcall 保护: 一个玩家的错误不影响其他玩家
            local ok, err = pcall(function()
                -- 玩家未点击"进入游戏"前，跳过所有游戏逻辑
                if not rt.gameStarted then return end

                if s.dead then
                    -- 已陨落只同步
                    rt.syncTimer = rt.syncTimer + dt
                    if rt.syncTimer >= SYNC_INTERVAL then
                        rt.syncTimer = 0
                        sendSync(userId, s)
                    end
                else
                    updateMaterials(s, rt, dt)
                    updateCraftQueue(userId, s, rt, dt)
                    updateCustomers(userId, s, rt, dt)
                    updateAutoRefine(userId, s, rt, dt)
                    updateAutoRepairArtifacts(userId, s, rt, dt)
                    updateFieldServant(userId, s, rt, dt)
                    updateCraftPuppet(userId, s, rt, dt)
                    updateLifespan(userId, s, rt, dt)
                    updateEncounter(userId, s, rt, dt)

                    rt.syncTimer = rt.syncTimer + dt
                    if rt.syncTimer >= SYNC_INTERVAL then
                        rt.syncTimer = 0
                        PlayerMgr_.SetDirty(userId)
                        sendSync(userId, s)
                    end
                end
            end)
            if not ok then
                -- 限制错误日志频率(每个玩家每10秒最多打印1次)
                local now = os.time()
                rt.lastErrTime = rt.lastErrTime or 0
                if now - rt.lastErrTime >= 10 then
                    rt.lastErrTime = now
                    print("[GameServer] Update error uid=" .. tostring(userId) .. ": " .. tostring(err))
                end
            end
        end
    end
end

-- 不依赖玩家 state 的轻量 action，可在 LoadPlayer 完成前响应
local STATELESS_ACTIONS = { check_online = true }

--- 处理客户端游戏操作
---@param userId number
---@param action string
---@param paramsJson string
function M.HandleGameAction(userId, action, paramsJson)
    local params = {}
    if paramsJson and paramsJson ~= "" then
        local ok, decoded = pcall(cjson.decode, paramsJson)
        if ok then params = decoded end
    end

    -- 无状态 action：不需要 s/rt，跳过 IsLoaded 检查
    if STATELESS_ACTIONS[action] then
        local handler = ACTION_HANDLERS[action]
        if handler then
            local ok, err = pcall(handler, userId, nil, nil, params)
            if not ok then
                print("[GameServer] Stateless action error action=" .. action .. " uid=" .. tostring(userId) .. ": " .. tostring(err))
            end
        end
        return
    end

    local s = PlayerMgr_.GetState(userId)
    local rt = runtimes_[userId]
    if not s or not rt then return end

    local handler = ACTION_HANDLERS[action]
    if handler then
        local ok, err = pcall(handler, userId, s, rt, params)
        if not ok then
            print("[GameServer] Action error action=" .. tostring(action) .. " uid=" .. tostring(userId) .. ": " .. tostring(err))
            sendEvt(userId, "action_fail", { msg = "操作失败，请重试" })
        end
    else
        print("[GameServer] 未知操作: " .. tostring(action))
        sendEvt(userId, "action_fail", { msg = "未知操作: " .. tostring(action) })
    end
end

--- 处理前后台切换
---@param userId number
---@param foreground boolean
function M.HandleAppBg(userId, foreground)
    if not foreground then
        -- 切后台立即保存
        PlayerMgr_.SetDirty(userId)
        PlayerMgr_.SavePlayer(userId)
        print("[GameServer] 玩家切后台,立即保存: uid=" .. tostring(userId))
    end
end

--- 发送 GameInit（内部先检查封禁状态）
---@param userId number
function M.SendGameInit(userId)
    local s = PlayerMgr_.GetState(userId)
    local rt = runtimes_[userId]
    if not s or not rt then return end

    -- 检查封禁状态（使用 BatchGet 与项目其他读取模式统一）
    if serverCloud then
        serverCloud:BatchGet(userId)
            :Key("banned")
            :Fetch({
                ok = function(scores)
                    local val = scores and scores["banned"]
                    if val == "true" then
                        -- 被封禁，发送封禁通知（不断开连接，避免无限重连）
                        print("[GameServer] 玩家已封禁,发送封禁通知: uid=" .. tostring(userId))
                        -- 通知 server_main 缓存封禁状态
                        if OnBanned_ then OnBanned_(userId) end
                        if GetConnection_ then
                            local conn = GetConnection_(userId)
                            if conn then
                                local kickData = VariantMap()
                                kickData["Reason"] = Variant("banned")
                                conn:SendRemoteEvent(EVENTS_.KICKED, true, kickData)
                                print("[GameServer] 已发送封禁通知给uid=" .. tostring(userId))
                            end
                        end
                        return
                    end
                    -- 未封禁，正常发送 GameInit
                    M._doSendGameInit(userId)
                end,
                error = function(code, reason)
                    -- 查询失败，按未封禁处理
                    print("[GameServer] 封禁查询失败,按未封禁处理: uid=" .. tostring(userId) .. " reason=" .. tostring(reason))
                    M._doSendGameInit(userId)
                end,
            })
        return
    end

    -- serverCloud 不可用，直接发送
    M._doSendGameInit(userId)
end

--- 实际发送 GameInit（内部方法）
---@param userId number
function M._doSendGameInit(userId)
    local s = PlayerMgr_.GetState(userId)
    local rt = runtimes_[userId]
    if not s or not rt then
        print("[GameServer] _doSendGameInit: 状态丢失! uid=" .. tostring(userId)
            .. " state=" .. tostring(s ~= nil) .. " runtime=" .. tostring(rt ~= nil)
            .. " (可能是 RemovePlayer 竞态)")
        return
    end

    local vm = VariantMap()
    vm["StateJson"] = Variant(cjson.encode(s))
    -- 离线收益数据(含诊断信息供客户端打印)
    local offlinePayload = rt.pendingOffline or {}
    local sid = PlayerMgr_.GetServerId and PlayerMgr_.GetServerId(userId) or -1
    offlinePayload._diag = {
        sid = sid,
        lastSaveTime = s.lastSaveTime or 0,
        now = os.time(),
        offlineSec = (s.lastSaveTime and s.lastSaveTime > 0) and (os.time() - s.lastSaveTime) or 0,
    }
    vm["OfflineJson"] = Variant(cjson.encode(offlinePayload))
    -- 活跃顾客列表(重连恢复)
    local custList = {}
    for _, cust in ipairs(rt.customers) do
        table.insert(custList, {
            id = cust.id, typeId = cust.typeId,
            displayName = cust.displayName, avatarKey = cust.avatarKey,
            dialogue = cust.dialogue,
            wantProductId = cust.wantProductId,
            targetProductId = cust.targetProductId,
            matched = cust.matched,
            isCrossRealm = cust.isCrossRealm,
            crossRealmHint = cust.crossRealmHint,
            buyTimer = cust.buyTimer,
            payMul = cust.payMul,
            state = cust.state,
            walkProgress = cust.walkProgress,
            canBargain = cust.canBargain,
            bargainDone = cust.bargainDone,
            bargainMul = cust.bargainMul,
            bargaining = cust.bargaining or false,
        })
    end
    vm["CustomersJson"] = Variant(cjson.encode(custList))
    -- 制作队列
    local queueList = {}
    for _, task in ipairs(rt.craftQueue) do
        table.insert(queueList, {
            productId = task.productId,
            remainTime = task.remainTime,
            totalTime = task.totalTime,
        })
    end
    vm["CraftQueueJson"] = Variant(cjson.encode(queueList))
    -- 秘境探险状态(重连恢复)
    if rt.dungeonState then
        local ds = rt.dungeonState
        local curEvt = ds.events[ds.step]
        vm["DungeonJson"] = Variant(cjson.encode({
            dungeonId = ds.dungeonId,
            step = ds.step,
            totalSteps = #ds.events,
            desc = curEvt and curEvt.desc or "",
            choices = filterChoicesForClient(curEvt and curEvt.choices or {}),
            results = ds.results,
            totalReward = ds.totalReward,
            settled = ds.settled,
        }))
    end
    vm["UserId"] = Variant(tostring(userId))
    -- GM 权限判断: 用 connection.identity 获取真实 userId 验证
    local realUid = userId
    if GetConnection_ then
        local conn = GetConnection_(userId)
        if conn then
            local identityUid = conn.identity["user_id"]
            if identityUid then realUid = identityUid:GetInt64() end
        end
    end
    local isDev = (tostring(realUid) == DEV_USER_ID)
    vm["IsDev"] = Variant(isDev)
    -- 调试白名单: GM 或白名单用户开启调试面板
    local debugEnabled = isDev or debugWhitelist_[tostring(realUid)] == true
    vm["DebugEnabled"] = Variant(debugEnabled)
    -- 版本管理: 传最低版本号给客户端
    if requiredVersion_ ~= "" then
        vm["RequiredVersion"] = Variant(requiredVersion_)
    end
    SendToClient_(userId, EVENTS_.GAME_INIT, vm)
    print("[GameServer] GameInit 已发送: uid=" .. tostring(userId) .. " isDev=" .. tostring(isDev))

    -- 触发 post-init 回调（确保 CHAT_HISTORY 等在 GAME_INIT 之后发送）
    if postInitCallbacks_[userId] then
        local cb = postInitCallbacks_[userId]
        postInitCallbacks_[userId] = nil
        cb()
    end
end

--- 获取玩家运行时(GM 用)
---@param userId number
---@return table|nil
function M.GetRuntime(userId)
    return runtimes_[userId]
end

--- 注册 GameInit 发送后的一次性回调
--- 用于确保 CHAT_HISTORY 等事件在 GAME_INIT 之后发送
---@param userId number
---@param callback function
function M.SetPostInitCallback(userId, callback)
    postInitCallbacks_[userId] = callback
end

--- 邮件奖励发放(供 mail_server.lua 调用，服务端权威发放)
---@param userId number
---@param rewardType string
---@param rewardAmt number
---@param title string
function M.ApplyMailReward(userId, rewardType, rewardAmt, title, reward)
    local s = PlayerMgr_.GetState(userId)
    if not s then
        print("[Server][MailReward] ApplyMailReward: no state for uid=" .. tostring(userId))
        return
    end

    -- 新版多资源奖励(复用CDK发放逻辑)
    if reward and type(reward) == "table" then
        print("[Server][MailReward] ApplyMailReward(multi) uid=" .. tostring(userId))
        if reward.lingshi then addLingshi(s, reward.lingshi) end
        if reward.xiuwei then addXiuwei(s, reward.xiuwei) end
        if reward.materials and type(reward.materials) == "table" then
            for matId, amount in pairs(reward.materials) do
                addMaterial(s, matId, amount)
            end
        end
        if reward.products and type(reward.products) == "table" then
            for prodId, amount in pairs(reward.products) do
                addProduct(s, prodId, amount)
            end
        end
        if reward.collectibles and type(reward.collectibles) == "table" then
            if not s.collectibles then s.collectibles = {} end
            for itemId, count in pairs(reward.collectibles) do
                s.collectibles[itemId] = (s.collectibles[itemId] or 0) + count
            end
        end
        PlayerMgr_.SetDirty(userId)
        sendEvt(userId, "mail_reward_done", {
            title = title,
            lingshi = s.lingshi,
            xiuwei = s.xiuwei,
            materials = s.materials,
            products = s.products,
            collectibles = s.collectibles,
        })
        print("[Server][MailReward] 多资源已发放, lingshi=" .. tostring(s.lingshi)
            .. " xiuwei=" .. tostring(s.xiuwei))
        return
    end

    -- 兼容旧版单资源邮件
    print("[Server][MailReward] ApplyMailReward(legacy) uid=" .. tostring(userId)
        .. " type=" .. tostring(rewardType) .. " amt=" .. tostring(rewardAmt))

    rewardAmt = tonumber(rewardAmt) or 0
    if rewardAmt <= 0 then
        sendEvt(userId, "mail_reward_done", { title = title })
        return
    end

    if rewardType == "lingshi" then
        addLingshi(s, rewardAmt)
    elseif rewardType == "xiuwei" then
        addXiuwei(s, rewardAmt)
    elseif rewardType == "lingcao" or rewardType == "lingzhi" or rewardType == "xuantie"
        or rewardType == "yaodan" or rewardType == "jingshi" then
        addMaterial(s, rewardType, rewardAmt)
    end

    PlayerMgr_.SetDirty(userId)
    sendEvt(userId, "mail_reward_done", {
        title = title,
        rewardType = rewardType,
        rewardAmt = rewardAmt,
        lingshi = s.lingshi,
        xiuwei = s.xiuwei,
        materials = s.materials,
    })
    print("[Server][MailReward] 已发放, lingshi=" .. tostring(s.lingshi)
        .. " xiuwei=" .. tostring(s.xiuwei))
end

return M
