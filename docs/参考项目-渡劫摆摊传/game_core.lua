-- ============================================================================
-- game_core.lua — 渡劫摆摊传 核心游戏逻辑
-- 材料产出、制作队列、顾客系统、售卖循环、广告增益、离线收益
-- ============================================================================
local Config = require("data_config")
local State = require("data_state")
local Encounter = require("game_encounter")
local cjson = cjson  ---@diagnostic disable-line: undefined-global

local M = {}

-- ========== 音效播放 ==========
---@type Node
local sfxNode_ = nil
local sfxEnabled_ = true

--- 设置 SFX 开关
---@param enabled boolean
function M.SetSFXEnabled(enabled)
    sfxEnabled_ = enabled
end

--- 获取 SFX 开关状态
---@return boolean
function M.IsSFXEnabled()
    return sfxEnabled_
end

--- 播放音效(2D, 无空间感)
---@param sfxKey string Config.SFX 的键名
function M.PlaySFX(sfxKey)
    if not sfxEnabled_ then return end
    -- 开始界面可见时不播放游戏音效
    local StartScreen = require("ui_start")
    if StartScreen.IsVisible() then return end
    local path = Config.SFX[sfxKey]
    if not path then return end
    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    -- 延迟创建节点
    if not sfxNode_ then
        sfxNode_ = scene_:CreateChild("SFX")
    end
    local source = sfxNode_:CreateComponent("SoundSource")
    source.soundType = "Effect"
    source.gain = 0.6
    source.autoRemoveMode = REMOVE_COMPONENT
    source:Play(sound)
end

-- ========== 计时器 ==========
local materialTimer = 0
local MATERIAL_TICK = 1.0
local customerSpawnTimer = 0
local CUSTOMER_SPAWN_BASE = 5.0
local autoSaveTimer = 0
local AUTO_SAVE_INTERVAL = 30
-- autoSellTimer removed (replaced by price boost)
local lifespanTimer = 0
local LIFESPAN_TICK = 1.0         -- 每秒扣减寿元
local autoRefineTimer = 0
local AUTO_REFINE_INTERVAL = 1.0  -- 自动炼化每秒一次
local servantTimer = 0
local SERVANT_INTERVAL = 2.0      -- 灵童每2秒检查一次
local puppetTimer = 0
local PUPPET_INTERVAL = 3.0       -- 傀儡每3秒检查一次

-- ========== 顾客队列 ==========
---@class Customer
---@field type table
---@field buyTimer number
---@field state string "walking"|"buying"|"leaving"
---@field walkProgress number 0-1
---@field targetProduct table

---@type Customer[]
M.customers = {}

-- ========== 制作队列 ==========
---@class CraftTask
---@field productId string
---@field remainTime number
---@field totalTime number

---@type CraftTask[]
M.craftQueue = {}
local MAX_CRAFT_QUEUE = 20

-- ========== 日志系统 ==========
---@type {text: string, time: number, color: table}[]
M.logs = {}
local MAX_LOGS = 50

--- 添加日志(含去重：最近3条相同文本合并为 "xxx (xN)")
---@param text string
---@param color? table
function M.AddLog(text, color)
    -- 去重检查：最近3条中是否有相同文本(忽略末尾 (xN) 计数)
    local baseText = text:gsub(" %(x%d+%)$", "")
    for i = 1, math.min(3, #M.logs) do
        local existing = M.logs[i]
        local existBase = existing.text:gsub(" %(x%d+%)$", "")
        if existBase == baseText then
            -- 提取已有计数
            local count = existing.text:match("%(x(%d+)%)$")
            count = count and (tonumber(count) + 1) or 2
            existing.text = baseText .. " (x" .. count .. ")"
            existing.time = os.time()
            existing.color = color or existing.color
            State.Emit("log_added", existing)
            return
        end
    end
    table.insert(M.logs, 1, {
        text = text,
        time = os.time(),
        color = color or Config.Colors.textPrimary,
    })
    if #M.logs > MAX_LOGS then
        table.remove(M.logs, #M.logs)
    end
    State.Emit("log_added", M.logs[1])
end

-- ========== 浮动文字队列(购买动效) ==========
---@type {text: string, color: table, life: number, maxLife: number}[]
M.floatingTexts = {}
M.dungeonState = nil  -- 秘境探险客户端运行时状态

--- 添加浮动文字
---@param text string
---@param color? table
function M.AddFloatingText(text, color)
    table.insert(M.floatingTexts, {
        text = text,
        color = color or Config.Colors.textGold,
        life = 1.5,
        maxLife = 1.5,
    })
end

-- ========== 广告增益查询 ==========

--- 客流翻倍是否生效
---@return boolean
function M.IsFlowBoosted()
    return State.state.adFlowBoostEnd > os.time()
end

--- 客流翻倍剩余秒数
---@return number
function M.FlowBoostRemain()
    return math.max(0, State.state.adFlowBoostEnd - os.time())
end

--- 售价加成是否生效
---@return boolean
function M.IsPriceBoosted()
    return State.IsPriceBoosted()
end

--- 售价加成剩余秒数
---@return number
function M.PriceBoostRemain()
    return State.PriceBoostRemain()
end

-- ========== 材料产出 ==========

---@param dt number
local function updateMaterials(dt)
    materialTimer = materialTimer + dt
    if materialTimer >= MATERIAL_TICK then
        materialTimer = materialTimer - MATERIAL_TICK
        for _, mat in ipairs(Config.Materials) do
            local perSecond = mat.rate / 60.0
            State.AddMaterial(mat.id, perSecond)
        end
    end
end

-- ========== 制作系统 ==========

--- 开始制作商品(单个)
---@param productId string
---@return boolean success
---@return string? reason
function M.StartCraft(productId)
    local prodCfg = Config.GetProductById(productId)
    if not prodCfg then return false, "未知商品" end

    -- 队列上限检查(客户端和服务端模式通用)
    if #M.craftQueue >= MAX_CRAFT_QUEUE then
        return false, "制作队列已满(上限" .. MAX_CRAFT_QUEUE .. ")"
    end

    local realmIdx = State.GetRealmIndex()
    if realmIdx < prodCfg.unlockRealm then
        return false, "境界不足,需" .. Config.Realms[prodCfg.unlockRealm].name
    end

    local matId = prodCfg.materialId
    local matStock = State.state.materials[matId] or 0
    if matStock < prodCfg.materialCost then
        local matCfg = Config.GetMaterialById(matId)
        return false, (matCfg and matCfg.name or "材料") .. "不足(需" .. prodCfg.materialCost .. ")"
    end

    -- 预扣材料(防止连续点击重复发送)
    State.SpendMaterial(matId, prodCfg.materialCost)

    if State.serverMode then
        M.SendGameAction("start_craft", { productId = productId })
        return true
    end

    table.insert(M.craftQueue, {
        productId = productId,
        remainTime = prodCfg.craftTime,
        totalTime = prodCfg.craftTime,
    })
    M.AddLog("开始制作: " .. prodCfg.name, Config.Colors.blue)
    State.Emit("craft_started", productId)
    return true
end

--- 批量制作
---@param productId string
---@param count number
---@return number successCount
---@return string? lastReason
function M.BatchCraft(productId, count)
    if State.serverMode then
        -- 服务端模式: 本地预检查+预扣材料, 一次batch请求
        local prodCfg = Config.GetProductById(productId)
        if not prodCfg then return 0, "未知商品" end

        local realmIdx = State.GetRealmIndex()
        if realmIdx < prodCfg.unlockRealm then
            return 0, "境界不足,需" .. Config.Realms[prodCfg.unlockRealm].name
        end

        local matId = prodCfg.materialId
        local matStock = State.state.materials[matId] or 0
        local queueSlots = MAX_CRAFT_QUEUE - #M.craftQueue
        -- 可制作数量 = min(请求数, 队列剩余, 材料可支撑数)
        local canMake = math.min(count, queueSlots, math.floor(matStock / prodCfg.materialCost))
        if canMake <= 0 then
            if queueSlots <= 0 then return 0, "制作队列已满(上限" .. MAX_CRAFT_QUEUE .. ")" end
            local matCfg = Config.GetMaterialById(matId)
            return 0, (matCfg and matCfg.name or "材料") .. "不足(需" .. prodCfg.materialCost .. ")"
        end

        -- 预扣材料
        State.SpendMaterial(matId, prodCfg.materialCost * canMake)
        M.SendGameAction("batch_craft", { productId = productId, count = canMake })
        return canMake
    end

    -- 单机模式: 逐个制作
    local made = 0
    local reason = nil
    for _ = 1, count do
        local ok, r = M.StartCraft(productId)
        if ok then
            made = made + 1
        else
            reason = r
            break
        end
    end
    return made, reason
end

--- 更新制作队列
---@param dt number
local function updateCraftQueue(dt)
    local i = 1
    while i <= #M.craftQueue do
        local task = M.craftQueue[i]
        task.remainTime = task.remainTime - dt
        if task.remainTime <= 0 then
            State.AddProduct(task.productId, 1)
            local prodCfg = Config.GetProductById(task.productId)
            M.AddLog((prodCfg and prodCfg.name or "?") .. " 制作完成!", Config.Colors.jade)
            M.PlaySFX("craft_complete")
            State.Emit("craft_completed", task.productId)
            table.remove(M.craftQueue, i)
        else
            i = i + 1
        end
    end
    State.state.craftQueue = {}
    for _, task in ipairs(M.craftQueue) do
        table.insert(State.state.craftQueue, {
            productId = task.productId,
            remainTime = task.remainTime,
            totalTime = task.totalTime,
        })
    end
end

-- ========== 顾客系统 ==========

--- 获取可售商品
---@return table[]
local function getAvailableProducts()
    local result = {}
    local realmIdx = State.GetRealmIndex()
    for i, prod in ipairs(Config.Products) do
        if Config.IsProductUnlocked(i, realmIdx) and State.state.products[prod.id] > 0 then
            table.insert(result, prod)
        end
    end
    return result
end

--- 从所有已解锁商品(不论库存)中随机选择一个作为"想要的"
--- 有一定概率(CrossRealmDemandChance)想要下一境界的商品(跨境界需求)
---@return table|nil product
---@return boolean isCrossRealm 是否为跨境界需求
local function randomWantProduct()
    local realmIdx = State.GetRealmIndex()

    -- 跨境界需求: 概率想要下一个未解锁境界的商品
    if math.random() < Config.CrossRealmDemandChance then
        local crossRealm = {}
        for i, prod in ipairs(Config.Products) do
            if prod.unlockRealm == realmIdx + 1 then
                table.insert(crossRealm, prod)
            end
        end
        if #crossRealm > 0 then
            return crossRealm[math.random(#crossRealm)], true
        end
    end

    -- 正常需求: 从已解锁商品中随机
    local unlocked = {}
    for i, prod in ipairs(Config.Products) do
        if Config.IsProductUnlocked(i, realmIdx) then
            table.insert(unlocked, prod)
        end
    end
    if #unlocked == 0 then return nil, false end
    return unlocked[math.random(#unlocked)], false
end

--- 随机获取顾客名字
---@param custType table
---@return string
local function randomCustomerName(custType)
    local names = Config.CustomerNames[custType.id]
    if names and #names > 0 then
        return names[math.random(#names)]
    end
    return custType.name
end

--- 生成顾客对话文本
---@param custType table
---@param wantProd table|nil
---@param isCrossRealm boolean
---@return string
local function generateDialogue(custType, wantProd, isCrossRealm)
    -- 跨境界需求: 用专属对话模板
    if isCrossRealm and wantProd then
        local templates = Config.CrossRealmDialogues
        local template = templates[math.random(#templates)]
        return string.format(template, wantProd.name)
    end

    -- 30%概率闲聊(不提商品名)
    local idleChats = Config.IdleChatDialogues[custType.id]
    if idleChats and #idleChats > 0 and math.random() < 0.30 then
        return idleChats[math.random(#idleChats)]
    end

    -- 正常商品对话
    if not wantProd then return "随便看看" end
    if not custType.dialogues or #custType.dialogues == 0 then
        return "想买" .. wantProd.name
    end
    local template = custType.dialogues[math.random(#custType.dialogues)]
    return string.format(template, wantProd.name)
end

--- 判断名字是否为女性(含女性暗示字)
local femaleHints = { "婶", "姐", "妹", "娘", "妇", "婆", "翠", "花", "女修", "老板娘" }
local function isFemaleByName(name)
    for _, hint in ipairs(femaleHints) do
        if name:find(hint) then return true end
    end
    return false
end

--- 刷新顾客
local function spawnCustomer()
    local stallCfg = State.GetStallConfig()
    if #M.customers >= stallCfg.queueLimit then return end

    local available = getAvailableProducts()
    if #available == 0 then return end

    local custType = Config.RandomCustomerType()
    local custName = randomCustomerName(custType)
    -- 性别判断: 名字暗示女性 → 女; 否则40%随机女性
    local isFemale = isFemaleByName(custName) or math.random() < 0.4
    local avatarKey
    if isFemale then
        avatarKey = custType.avatarF or custType.avatar
    elseif custType.avatarMList and #custType.avatarMList > 0 then
        avatarKey = custType.avatarMList[math.random(#custType.avatarMList)]
    else
        avatarKey = custType.avatar
    end
    -- 想要的商品(可能没货) vs 实际购买的商品(有货的)
    local wantProd, isCrossRealm = randomWantProduct()
    ---@type Customer
    local customer = {
        type = custType,
        displayName = custName,                              -- 随机名字
        avatarKey = avatarKey,                                -- 头像键(男或女)
        buyTimer = custType.buyInterval,
        state = "walking",
        walkProgress = 0,
        wantProduct = wantProd,                              -- 想要什么
        targetProduct = available[math.random(#available)],  -- 实际会买什么(有库存的)
        dialogue = generateDialogue(custType, wantProd, isCrossRealm),
        matched = false,                                      -- 是否匹配成功
        isCrossRealm = isCrossRealm,                          -- 跨境界需求标记
    }
    -- 跨境界需求: 商品未解锁,无法满足,但仍然会买别的
    if isCrossRealm then
        customer.matched = false
        -- 跨境界提示文本
        local realmIdx = State.GetRealmIndex()
        local nextRealm = Config.Realms[realmIdx + 1]
        if nextRealm then
            customer.crossRealmHint = "突破" .. nextRealm.name .. "后可解锁"
        end
    else
        -- 正常逻辑: 如果想要的商品有库存, 优先购买它
        if wantProd then
            for _, prod in ipairs(available) do
                if prod.id == wantProd.id then
                    customer.targetProduct = wantProd
                    customer.matched = true
                    break
                end
            end
        end
    end
    table.insert(M.customers, customer)
    M.PlaySFX("customer_arrive")
    State.Emit("customer_arrived", customer)
end

--- 更新顾客
---@param dt number
local function updateCustomers(dt)
    local stallCfg = State.GetStallConfig()
    local realmIdx = State.GetRealmIndex()
    local speedMul = stallCfg.speedMul * Config.GetRealmSpeedMultiplier(realmIdx)

    -- 广告客流翻倍
    if M.IsFlowBoosted() then
        speedMul = speedMul * 2.0
    end

    local spawnInterval = CUSTOMER_SPAWN_BASE / speedMul
    customerSpawnTimer = customerSpawnTimer + dt
    if customerSpawnTimer >= spawnInterval then
        customerSpawnTimer = customerSpawnTimer - spawnInterval
        spawnCustomer()
    end

    local i = 1
    while i <= #M.customers do
        local cust = M.customers[i]
        local shouldRemove = false

        if cust.state == "walking" then
            cust.walkProgress = cust.walkProgress + dt * 2.0
            if cust.walkProgress >= 1.0 then
                cust.walkProgress = 1.0
                cust.state = "buying"
            end

        elseif cust.state == "buying" then
            if cust.type.buyInterval == 0 then
                cust.buyTimer = 0
            else
                cust.buyTimer = cust.buyTimer - dt * speedMul
            end

            if cust.buyTimer <= 0 then
                local prod = cust.targetProduct
                local buyCount = (cust.type.buyCount) or 1
                local actualBuy = math.min(buyCount, State.state.products[prod.id] or 0)
                if actualBuy > 0 and State.SellProduct(prod.id, actualBuy) then
                    local price = State.GetProductPrice(prod)
                    local finalPrice = math.floor(price * cust.type.payMul * actualBuy)
                    -- 需求匹配奖励
                    local bonusText = ""
                    if cust.matched then
                        finalPrice = math.floor(finalPrice * Config.DemandMatchBonus)
                        bonusText = " (心满意足!)"
                    end
                    State.AddLingshi(finalPrice)
                    local logName = cust.displayName or cust.type.name
                    M.AddLog(logName .. " 购买 " .. prod.name
                        .. " +" .. finalPrice .. " 灵石" .. bonusText,
                        cust.matched and Config.Colors.textGold or Config.Colors.textGreen)
                    M.AddFloatingText("+" .. finalPrice .. (cust.matched and " 满意!" or ""),
                        cust.matched and Config.Colors.textGold or Config.Colors.jade)
                    M.PlaySFX("buy")
                    State.Emit("sale_completed", {
                        customer = cust,
                        product = prod,
                        price = finalPrice,
                        matched = cust.matched,
                    })
                end
                cust.state = "leaving"
                cust.walkProgress = 1.0
            end

        elseif cust.state == "leaving" then
            cust.walkProgress = cust.walkProgress - dt * 2.0
            if cust.walkProgress <= 0 then
                shouldRemove = true
            end
        end

        if shouldRemove then
            table.remove(M.customers, i)
            State.Emit("customer_left")
        else
            i = i + 1
        end
    end
end

-- updateAutoSell removed: replaced by price boost (adPriceBoostEnd)

-- ========== 自动炼化 ==========
local function updateAutoRefine(dt)
    if not State.state.autoRefine then return end

    autoRefineTimer = autoRefineTimer + dt
    if autoRefineTimer < AUTO_REFINE_INTERVAL then return end
    autoRefineTimer = autoRefineTimer - AUTO_REFINE_INTERVAL

    -- 已满修为(已到渡劫境界最高修为)不再炼化
    local realmIdx = State.state.realmLevel
    if realmIdx >= #Config.Realms then return end
    local nextRealm = Config.Realms[realmIdx + 1]
    if State.state.xiuwei >= nextRealm.xiuwei then return end

    local ok, cost, gain = State.RefineLingshi()
    if ok then
        M.AddFloatingText("炼化 修为+" .. gain, Config.Colors.purple)
    end
end

-- ========== 灵童自动操作 ==========
local Field = require("game_field")

--- 检查灵童是否有效(未过期且 tier>0)
---@return boolean active
---@return table|nil servantCfg
local function isServantActive()
    local sv = State.state.fieldServant
    if sv.tier <= 0 then return false, nil end
    if os.time() >= sv.expireTime then
        -- 过期，自动清零
        sv.tier = 0
        sv.expireTime = 0
        State.Emit("servant_expired")
        return false, nil
    end
    return true, Config.FieldServants[sv.tier]
end

local function updateFieldServant(dt)
    servantTimer = servantTimer + dt
    if servantTimer < SERVANT_INTERVAL then return end
    servantTimer = servantTimer - SERVANT_INTERVAL

    local active, cfg = isServantActive()
    if not active or not cfg then return end

    local abilities = cfg.abilities
    local maxPlots = Field.GetMaxPlots()

    -- 自动收获
    if abilities.harvest then
        for i = 1, maxPlots do
            if Field.CanHarvest(i) then
                local rewards = Field.Harvest(i)
                if rewards then
                    local parts = {}
                    for matId, amt in pairs(rewards) do
                        local mat = Config.GetMaterialById(matId)
                        table.insert(parts, (mat and mat.name or matId) .. "+" .. amt)
                    end
                    M.AddFloatingText("[灵童]收获 " .. table.concat(parts, " "), cfg.color)
                end
            end
        end
    end

    -- 自动种植(tier>=2), 支持分田种植(tier>=3)
    if abilities.plant then
        local sv = State.state.fieldServant
        local plotCrops = sv.plotCrops
        local defaultCrop = sv.plantCrop or "lingcao_seed"
        for i = 1, maxPlots do
            local plot = State.state.fieldPlots[i]
            if not plot or not plot.cropId then
                local cropId = (plotCrops and plotCrops[tostring(i)]) or defaultCrop
                local ok, reason = Field.Plant(i, cropId)
                if ok then
                    local crop = Field.GetCropById(cropId)
                    M.AddFloatingText("[灵童]种植 " .. (crop and crop.name or cropId), cfg.color)
                end
            end
        end
    end
end

-- ========== 炼器傀儡自动操作 ==========

--- 检查傀儡是否有效
---@return boolean
local function isPuppetActive()
    local pp = State.state.craftPuppet
    if not pp.active then return false end
    if os.time() >= pp.expireTime then
        pp.active = false
        pp.expireTime = 0
        State.Emit("puppet_expired")
        return false
    end
    return true
end

local function updateCraftPuppet(dt)
    puppetTimer = puppetTimer + dt
    if puppetTimer < PUPPET_INTERVAL then return end
    puppetTimer = puppetTimer - PUPPET_INTERVAL

    if not isPuppetActive() then return end

    local pp = State.state.craftPuppet
    if #pp.products == 0 then return end

    -- 检查制作队列是否已满
    local stallLvl = State.state.stallLevel
    if stallLvl > #Config.StallLevels then stallLvl = #Config.StallLevels end
    local queueLimit = Config.StallLevels[stallLvl].queueLimit
    if #M.craftQueue >= queueLimit then return end

    -- 批量填满队列
    local mode = pp.craftMode or "priority"
    local crafted = 0

    if mode == "roundrobin" then
        local productCount = #pp.products
        local exhausted = {}
        local exhaustedCount = 0
        while #M.craftQueue < queueLimit and exhaustedCount < productCount do
            local addedThisRound = false
            for idx, prodId in ipairs(pp.products) do
                if #M.craftQueue >= queueLimit then break end
                if not exhausted[idx] then
                    local prodCfg = Config.GetProductById(prodId)
                    if prodCfg and State.state.realmLevel >= prodCfg.unlockRealm then
                        local matId = prodCfg.materialId
                        local matCost = prodCfg.materialCost
                        if (State.state.materials[matId] or 0) >= matCost then
                            M.StartCraft(prodId)
                            crafted = crafted + 1
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
        while #M.craftQueue < queueLimit do
            local foundAny = false
            for _, prodId in ipairs(pp.products) do
                if #M.craftQueue >= queueLimit then break end
                local prodCfg = Config.GetProductById(prodId)
                if prodCfg and State.state.realmLevel >= prodCfg.unlockRealm then
                    local matId = prodCfg.materialId
                    local matCost = prodCfg.materialCost
                    if (State.state.materials[matId] or 0) >= matCost then
                        M.StartCraft(prodId)
                        crafted = crafted + 1
                        foundAny = true
                        break
                    end
                end
            end
            if not foundAny then break end
        end
    end

    if crafted > 0 then
        M.AddFloatingText("[傀儡]批量制作 x" .. crafted, Config.CraftPuppet.color)
    end
end

-- ========== 浮动文字更新 ==========
local function updateFloatingTexts(dt)
    local i = 1
    while i <= #M.floatingTexts do
        local ft = M.floatingTexts[i]
        ft.life = ft.life - dt
        if ft.life <= 0 then
            table.remove(M.floatingTexts, i)
        else
            i = i + 1
        end
    end
end

-- ========== 离线收益 ==========

--- 离线产率(非100%，鼓励在线游玩)
local OFFLINE_RATE = 0.7
--- 基础离线上限(秒)
local OFFLINE_BASE_CAP = 3 * 3600
--- 广告延长每次增加(秒)
local OFFLINE_AD_EXTEND = 3600
--- 广告延长最大次数
local OFFLINE_AD_MAX = 5

--- 计算离线收益(完整循环: 材料+灵田→制作→售卖→灵石)
---@param offlineSeconds number 实际离线秒数
---@param capSeconds? number 离线上限秒数(默认3h，广告可延长)
---@return table|nil
function M.CalculateOfflineEarnings(offlineSeconds, capSeconds)
    local cap = capSeconds or OFFLINE_BASE_CAP
    offlineSeconds = math.min(offlineSeconds, cap)
    if offlineSeconds < 60 then return nil end

    local offlineMinutes = offlineSeconds / 60.0
    local rate = OFFLINE_RATE

    -- ① 基础材料产出
    local matPool = {}
    for _, mat in ipairs(Config.Materials) do
        matPool[mat.id] = math.floor(mat.rate * offlineMinutes * rate)
    end

    -- ② 灵田收获(根据已种植地块计算可收获轮次)
    local fieldYield = {}
    local plots = State.state.fieldPlots or {}
    local maxPlots = #Config.FieldLevels > 0
        and Config.FieldLevels[math.min(State.state.fieldLevel, #Config.FieldLevels)].plots
        or 2
    local now = os.time()
    for i = 1, maxPlots do
        local plot = plots[i]
        if plot and plot.cropId and plot.plantTime then
            local crop = nil
            for _, c in ipairs(Config.Crops) do
                if c.id == plot.cropId then crop = c; break end
            end
            if crop then
                -- 已经过的时间
                local elapsed = now - plot.plantTime
                -- 离线期间可完成的完整收获轮次
                local totalTime = math.max(elapsed, offlineSeconds)
                local cycles = math.floor(totalTime / crop.growTime)
                if cycles < 1 then cycles = 0 end
                -- 计算收获(至少1轮如果作物已成熟)
                if elapsed >= crop.growTime then
                    cycles = math.max(cycles, 1)
                end
                for matId, amount in pairs(crop.yield) do
                    fieldYield[matId] = (fieldYield[matId] or 0) + amount * cycles
                end
            end
        end
    end
    -- 灵田产出也乘以离线产率
    for matId, amount in pairs(fieldYield) do
        matPool[matId] = (matPool[matId] or 0) + math.floor(amount * rate)
    end

    -- ③ 自动制作(用材料池制作已解锁商品)
    local realmIdx = State.GetRealmIndex()
    local craftedProducts = {}
    -- 按价格从高到低排序，优先制作高价商品
    local sortedProducts = {}
    for i, prod in ipairs(Config.Products) do
        if Config.IsProductUnlocked(i, realmIdx) then
            table.insert(sortedProducts, prod)
        end
    end
    table.sort(sortedProducts, function(a, b) return a.price > b.price end)

    -- 模拟制作: 循环消耗材料
    local changed = true
    while changed do
        changed = false
        for _, prod in ipairs(sortedProducts) do
            local matId = prod.materialId
            if (matPool[matId] or 0) >= prod.materialCost then
                matPool[matId] = matPool[matId] - prod.materialCost
                craftedProducts[prod.id] = (craftedProducts[prod.id] or 0) + 1
                changed = true
            end
        end
    end

    -- ④ 自动售卖(模拟顾客购买)
    local stallCfg = State.GetStallConfig()
    local speedMul = stallCfg.speedMul * Config.GetRealmSpeedMultiplier(realmIdx)
    local spawnInterval = CUSTOMER_SPAWN_BASE / speedMul
    local maxCustomers = math.floor(offlineSeconds / spawnInterval)
    -- 计算平均顾客付费倍率
    local avgPayMul = 0
    local totalWeight = 0
    for _, ct in ipairs(Config.CustomerTypes) do
        avgPayMul = avgPayMul + ct.payMul * ct.weight
        totalWeight = totalWeight + ct.weight
    end
    avgPayMul = avgPayMul / totalWeight
    -- 需求匹配概率约30%
    local matchRate = 0.3

    -- 可售商品总数
    local totalProducts = 0
    for _, count in pairs(craftedProducts) do
        totalProducts = totalProducts + count
    end
    -- 加上已有库存
    local existingProducts = {}
    for _, prod in ipairs(Config.Products) do
        local stock = State.state.products[prod.id] or 0
        if stock > 0 then
            existingProducts[prod.id] = stock
            totalProducts = totalProducts + stock
        end
    end

    -- 实际售出数量 = min(顾客数, 商品数)
    local soldCount = math.min(maxCustomers, totalProducts)
    local totalLingshi = 0
    local soldProducts = {}
    local remaining = soldCount

    -- 优先卖高价商品
    for _, prod in ipairs(sortedProducts) do
        if remaining <= 0 then break end
        local available = (craftedProducts[prod.id] or 0) + (existingProducts[prod.id] or 0)
        if available > 0 then
            local sell = math.min(available, remaining)
            local basePrice = State.GetProductPrice(prod)
            -- 平均价格: 基础 × 平均付费倍率 × (1 + 匹配率 × 匹配奖励)
            local avgPrice = basePrice * avgPayMul * (1 + matchRate * (Config.DemandMatchBonus - 1))
            totalLingshi = totalLingshi + math.floor(avgPrice * sell * rate)
            soldProducts[prod.id] = sell
            remaining = remaining - sell
        end
    end

    -- 剩余未售出的商品(归还给玩家)
    local unsoldProducts = {}
    for prodId, count in pairs(craftedProducts) do
        local sold = soldProducts[prodId] or 0
        local leftover = count - sold
        if leftover > 0 then
            unsoldProducts[prodId] = leftover
        end
    end

    return {
        minutes       = math.floor(offlineMinutes),
        rate          = rate,
        materials     = matPool,           -- 剩余未用掉的材料
        fieldYield    = fieldYield,        -- 灵田原始产出
        crafted       = craftedProducts,   -- 制作的商品
        sold          = soldProducts,      -- 售出的商品
        unsold        = unsoldProducts,    -- 未售出的商品(归还)
        lingshi       = totalLingshi,      -- 售卖获得灵石
        soldCount     = soldCount,
    }
end

--- 发放离线收益(完整版: 材料+商品+灵石)
---@param earnings table
---@param doubleMul? number 广告翻倍倍率(仅用于灵石)
function M.ApplyOfflineEarnings(earnings, doubleMul)
    local mul = doubleMul or 1
    -- 发放剩余材料
    for matId, amount in pairs(earnings.materials) do
        if amount > 0 then
            State.AddMaterial(matId, math.floor(amount))
        end
    end
    -- 发放未售出的商品
    if earnings.unsold then
        for prodId, count in pairs(earnings.unsold) do
            State.AddProduct(prodId, count)
        end
    end
    -- 发放灵石(可翻倍)
    if earnings.lingshi and earnings.lingshi > 0 then
        State.AddLingshi(math.floor(earnings.lingshi * mul))
    end
end

--- 获取离线基础上限(秒)
function M.GetOfflineBaseCap()
    return OFFLINE_BASE_CAP
end

--- 获取广告延长参数
function M.GetOfflineAdExtend()
    return OFFLINE_AD_EXTEND, OFFLINE_AD_MAX
end

-- ========== 主更新 ==========

--- 从存档恢复制作队列
function M.RestoreCraftQueue()
    M.craftQueue = {}
    if State.state.craftQueue then
        for _, task in ipairs(State.state.craftQueue) do
            table.insert(M.craftQueue, {
                productId = task.productId,
                remainTime = task.remainTime or 0,
                totalTime = task.totalTime or 0,
            })
        end
    end
    -- 初始化奇遇模块(注册服务端事件监听)
    Encounter.Init()
end

-- ========== 寿元消耗 ==========
local function updateLifespan(dt)
    lifespanTimer = lifespanTimer + dt
    if lifespanTimer >= LIFESPAN_TICK then
        lifespanTimer = lifespanTimer - LIFESPAN_TICK
        local drain = Config.LifespanDrainPerSec * LIFESPAN_TICK
        -- 境界寿元消耗倍率(炼气期减半, 新手保护)
        local realmMul = Config.RealmLifespanDrainMul[State.state.realmLevel]
        if realmMul then
            drain = drain * realmMul
        end
        State.DrainLifespan(drain)
    end
end

--- 每帧更新
---@param dt number
function M.Update(dt)
    -- 服务端权威模式: 更新视觉元素, 所有经济逻辑由服务端驱动
    if State.serverMode then
        updateFloatingTexts(dt)
        -- 客户端视觉计时器递减(仅动画, 不触发逻辑; GameSync 会用服务端准确值覆盖)
        for _, task in ipairs(M.craftQueue) do
            if task.remainTime > 0 then
                task.remainTime = math.max(0, task.remainTime - dt)
            end
        end
        for _, c in ipairs(M.customers) do
            if c.state == "buying" and c.buyTimer and c.buyTimer > 0 and not c.bargaining then
                c.buyTimer = math.max(0, c.buyTimer - dt)
            elseif c.state == "walking" then
                c.walkProgress = math.min(1.0, (c.walkProgress or 0) + dt * 2.0)
                -- 走完自动切到 buying (视觉预测, GameSync 会校正)
                if c.walkProgress >= 1.0 then
                    c.state = "buying"
                    -- buyTimer 已在 spawn 时由服务端设好
                end
            elseif c.state == "leaving" then
                c.walkProgress = math.max(0, (c.walkProgress or 1.0) - dt * 2.0)
            end
        end
        return
    end

    -- === 以下为单机模式逻辑(保留向后兼容) ===

    -- 已陨落: 只更新浮动文字和自动存档, 停止一切游戏逻辑
    if State.state.dead then
        updateFloatingTexts(dt)
        autoSaveTimer = autoSaveTimer + dt
        if autoSaveTimer >= AUTO_SAVE_INTERVAL then
            autoSaveTimer = 0
            State.Save()
        end
        return
    end

    updateMaterials(dt)
    updateCraftQueue(dt)
    updateCustomers(dt)
    updateAutoRefine(dt)
    updateFieldServant(dt)
    updateCraftPuppet(dt)
    updateFloatingTexts(dt)
    updateLifespan(dt)

    -- 奇遇事件检测
    Encounter.Update(dt)

    autoSaveTimer = autoSaveTimer + dt
    if autoSaveTimer >= AUTO_SAVE_INTERVAL then
        autoSaveTimer = 0
        State.Save()
    end
end

--- 转生后重置游戏核心运行时状态
function M.OnRebirth()
    M.customers = {}
    M.craftQueue = {}
    M.logs = {}
    M.floatingTexts = {}
    materialTimer = 0
    customerSpawnTimer = 0
    autoSaveTimer = 0
    autoRefineTimer = 0
    servantTimer = 0
    puppetTimer = 0
    lifespanTimer = 0
end

-- ========== 服务端权威模式辅助 ==========

--- 发送游戏操作到服务端
---@param action string 操作名
---@param params? table 参数表
function M.SendGameAction(action, params)
    local ClientNet = require("network.client_net")
    local Shared = require("network.shared")
    local vm = VariantMap()
    vm["Action"] = Variant(action)
    vm["Params"] = Variant(cjson.encode(params or {}))
    ClientNet.SendToServer(Shared.EVENTS.GAME_ACTION, vm)
end

--- 从 GameInit 恢复顾客列表和制作队列
---@param customersData table[] 服务端活跃顾客
---@param craftQueueData table[] 服务端制作队列
function M.InitFromServer(customersData, craftQueueData)
    -- 恢复顾客(服务端格式 → 客户端显示格式)
    M.customers = {}
    for _, cd in ipairs(customersData or {}) do
        local custType = Config.GetCustomerTypeById and Config.GetCustomerTypeById(cd.typeId)
        if not custType then
            custType = { id = cd.typeId, name = cd.displayName or "散修", buyInterval = 8, payMul = 1.0, color = { 180, 180, 180, 255 } }
        end
        table.insert(M.customers, {
            type = custType,
            displayName = cd.displayName,
            avatarKey = cd.avatarKey,
            buyTimer = cd.buyTimer or 0,
            state = cd.state or "walking",
            walkProgress = cd.walkProgress or 0,
            wantProduct = cd.wantProductId and Config.GetProductById(cd.wantProductId) or nil,
            targetProduct = Config.GetProductById(cd.targetProductId),
            dialogue = cd.dialogue or "",
            matched = cd.matched or false,
            isCrossRealm = cd.isCrossRealm or false,
            crossRealmHint = cd.crossRealmHint,
            serverId = cd.id,
            canBargain = cd.canBargain or false,
            bargainDone = cd.bargainDone or false,
            bargainMul = cd.bargainMul,
            bargaining = cd.bargaining or false,
        })
    end
    -- 恢复制作队列
    M.craftQueue = {}
    for _, task in ipairs(craftQueueData or {}) do
        table.insert(M.craftQueue, {
            productId = task.productId,
            remainTime = task.remainTime or 0,
            totalTime = task.totalTime or 0,
        })
    end
end

--- 从 GameInit 恢复秘境探险状态(重连)
---@param dungeonData table|nil 服务端 DungeonJson
function M.InitDungeonFromServer(dungeonData)
    if not dungeonData then
        M.dungeonState = nil
        return
    end
    M.dungeonState = {
        dungeonId = dungeonData.dungeonId,
        step = dungeonData.step,
        totalSteps = dungeonData.totalSteps,
        desc = dungeonData.desc,
        choices = dungeonData.choices,
        results = dungeonData.results or {},
        totalReward = dungeonData.totalReward or {},
    }
    print("[Dungeon] 重连恢复秘境状态: " .. tostring(dungeonData.dungeonId) .. " step=" .. tostring(dungeonData.step))
end

--- 从 GameEvt data 中提取并即时更新 State 的关键字段(降低操作延迟)
---@param data table
local function applyInstantSync(data)
    if data.lingshi   ~= nil then State.state.lingshi   = data.lingshi   end
    if data.xiuwei    ~= nil then State.state.xiuwei    = data.xiuwei    end
    if data.realmLevel ~= nil then State.state.realmLevel = data.realmLevel end
    if data.lifespan  ~= nil then State.state.lifespan  = data.lifespan  end
    if data.stallLevel ~= nil then State.state.stallLevel = data.stallLevel end
    if data.fieldLevel ~= nil then State.state.fieldLevel = data.fieldLevel end
    if data.autoRefine ~= nil then State.state.autoRefine = data.autoRefine end
    if data.autoRepairArtifacts ~= nil then State.state.autoRepairArtifacts = data.autoRepairArtifacts end
    if data.fieldServant ~= nil and type(data.fieldServant) == "table" then
        State.state.fieldServant = data.fieldServant
        State.Emit("servant_changed")
    end
    if data.craftPuppet ~= nil and type(data.craftPuppet) == "table" then
        State.state.craftPuppet = data.craftPuppet
        State.Emit("puppet_changed")
    end
    if data.materials ~= nil then
        for matId, amount in pairs(data.materials) do
            State.state.materials[matId] = amount
        end
    end
    if data.products ~= nil then
        for prodId, amount in pairs(data.products) do
            State.state.products[prodId] = amount
        end
    end
    if data.fieldPlots ~= nil and type(data.fieldPlots) == "table" then
        -- JSON 反序列化修正: 数字索引键从字符串恢复为数字
        local fixed = {}
        for k, v in pairs(data.fieldPlots) do
            local numKey = tonumber(k)
            if numKey then fixed[numKey] = v else fixed[k] = v end
        end
        State.state.fieldPlots = fixed
        State.Emit("field_changed")
    end
    if data.reputation ~= nil then State.state.reputation = data.reputation end
    if data.dailyTasks ~= nil then State.state.dailyTasks = data.dailyTasks end
    if data.dungeonDailyUses ~= nil then State.state.dungeonDailyUses = data.dungeonDailyUses end
    if data.totalDungeonRuns ~= nil then State.state.totalDungeonRuns = data.totalDungeonRuns end
    if data.fengshui ~= nil and type(data.fengshui) == "table" then
        State.state.fengshui = data.fengshui
    end
    if data.collectibles ~= nil and type(data.collectibles) == "table" then
        State.state.collectibles = data.collectibles
    end
end

--- 处理服务端即时事件(GameEvt)，驱动客户端视觉反馈
---@param evtType string 事件类型
---@param data table 事件数据
function M.HandleServerEvent(evtType, data)
    -- 即时同步：从事件数据中提取关键状态字段，立即更新客户端
    applyInstantSync(data)

    if evtType == "customer_spawn" then
        local custType = Config.GetCustomerTypeById and Config.GetCustomerTypeById(data.typeId)
        if not custType then
            custType = { id = data.typeId, name = data.displayName or "散修", buyInterval = 8, payMul = 1.0, color = { 180, 180, 180, 255 } }
        end
        table.insert(M.customers, {
            type = custType,
            displayName = data.displayName,
            avatarKey = data.avatarKey,
            buyTimer = data.buyTimer or 0,
            state = "walking",
            walkProgress = 0,
            wantProduct = data.wantProductId and Config.GetProductById(data.wantProductId) or nil,
            targetProduct = Config.GetProductById(data.targetProductId),
            dialogue = data.dialogue or "",
            matched = data.matched or false,
            isCrossRealm = data.isCrossRealm or false,
            crossRealmHint = data.crossRealmHint,
            serverId = data.id,
            canBargain = data.canBargain or false,
            bargaining = false,
        })
        M.PlaySFX("customer_arrive")
        State.Emit("customer_arrived")

    elseif evtType == "customer_leave" then
        for i, cust in ipairs(M.customers) do
            if cust.serverId == data.custId then
                table.remove(M.customers, i)
                State.Emit("customer_left")
                break
            end
        end

    elseif evtType == "sale_done" then
        -- 从顾客列表移除(转为 leaving 动画)
        for i, cust in ipairs(M.customers) do
            if cust.serverId == data.custId then
                cust.state = "leaving"
                cust.walkProgress = 1.0
                break
            end
        end
        local logName = data.displayName or "顾客"
        local prodName = data.productName or "?"
        local bonusText = data.matched and " (心满意足!)" or ""
        M.AddLog(logName .. " 购买 " .. prodName .. " +" .. data.price .. " 灵石" .. bonusText,
            data.matched and Config.Colors.textGold or Config.Colors.textGreen)
        M.AddFloatingText("+" .. data.price .. (data.matched and " 满意!" or ""),
            data.matched and Config.Colors.textGold or Config.Colors.jade)
        M.PlaySFX("buy")
        State.Emit("sale_completed", {
            product = { name = prodName, id = data.productId },
            price = data.price,
            matched = data.matched,
        })

    elseif evtType == "craft_done" then
        M.AddLog((data.productName or "?") .. " 制作完成!", Config.Colors.jade)
        M.PlaySFX("craft_complete")
        State.Emit("craft_completed", data.productId)
        -- 从本地队列移除第一个匹配项
        for i, task in ipairs(M.craftQueue) do
            if task.productId == data.productId then
                table.remove(M.craftQueue, i)
                break
            end
        end

    elseif evtType == "craft_started" then
        local prodCfg = Config.GetProductById(data.productId)
        M.AddLog("开始制作: " .. (prodCfg and prodCfg.name or "?"), Config.Colors.blue)
        -- 用服务端权威材料数据覆盖本地(修正预扣偏差)
        if data.materials then
            for k, v in pairs(data.materials) do
                State.state.materials[k] = v
            end
        end
        State.Emit("craft_started", data.productId)
        if prodCfg then
            -- 用加速后的时间作为视觉倒计时(法宝+珍藏制作加速)
            local s = State.state
            local speedMul = 1.0 + Config.GetArtifactBonus(s.equippedArtifacts or {}, "craft_speed")
                + Config.GetCollectibleBonus(s.collectibles or {}, "craft_speed")
            local actualTime = prodCfg.craftTime / speedMul
            table.insert(M.craftQueue, {
                productId = data.productId,
                remainTime = actualTime,
                totalTime = actualTime,
            })
        end

    elseif evtType == "puppet_batch_crafted" then
        -- 傀儡批量制作: 同步材料 + 批量加入本地队列
        if data.materials then
            for k, v in pairs(data.materials) do
                State.state.materials[k] = v
            end
        end
        if data.craftPuppet then
            State.state.craftPuppet = data.craftPuppet
        end
        local s = State.state
        local speedMul = 1.0 + Config.GetArtifactBonus(s.equippedArtifacts or {}, "craft_speed")
            + Config.GetCollectibleBonus(s.collectibles or {}, "craft_speed")
        local names = {}
        for _, prodId in ipairs(data.crafted or {}) do
            local prodCfg = Config.GetProductById(prodId)
            if prodCfg then
                local actualTime = prodCfg.craftTime / speedMul
                table.insert(M.craftQueue, {
                    productId = prodId,
                    remainTime = actualTime,
                    totalTime = actualTime,
                })
                names[prodCfg.name or prodId] = (names[prodCfg.name or prodId] or 0) + 1
            end
        end
        -- 日志: "傀儡制作: 丹药A x5, 丹药B x3"
        local parts = {}
        for name, cnt in pairs(names) do
            table.insert(parts, name .. " x" .. cnt)
        end
        if #parts > 0 then
            M.AddLog("[傀儡]批量制作: " .. table.concat(parts, ", "), Config.Colors.blue)
        end
        State.Emit("craft_started")
        State.Emit("puppet_changed")

    elseif evtType == "batch_craft_done" then
        local prodCfg = Config.GetProductById(data.productId)
        local name = prodCfg and prodCfg.name or "?"
        M.AddLog("批量制作: " .. name .. " x" .. (data.count or 0), Config.Colors.blue)
        -- 用服务端权威材料数据覆盖本地(修正预扣偏差)
        if data.materials then
            for k, v in pairs(data.materials) do
                State.state.materials[k] = v
            end
        end
        if prodCfg then
            -- 用加速后的时间作为视觉倒计时(法宝+珍藏制作加速)
            local s = State.state
            local speedMul = 1.0 + Config.GetArtifactBonus(s.equippedArtifacts or {}, "craft_speed")
                + Config.GetCollectibleBonus(s.collectibles or {}, "craft_speed")
            local actualTime = prodCfg.craftTime / speedMul
            for _ = 1, (data.count or 0) do
                table.insert(M.craftQueue, {
                    productId = data.productId,
                    remainTime = actualTime,
                    totalTime = actualTime,
                })
            end
        end

    elseif evtType == "realm_up" then
        M.AddLog("突破至【" .. (data.name or "") .. "】!", Config.Colors.purple)
        M.AddFloatingText("突破! " .. (data.name or ""), Config.Colors.textGold)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("恭喜突破至" .. (data.name or "") .. "!", { variant = "success", duration = 3 })

    elseif evtType == "dujie_check_result" then
        -- 渡劫预检查结果(次数/费用信息)
        State.Emit("dujie_check_result", data)

    elseif evtType == "dujie_begin" then
        -- 渡劫小游戏开始
        local Dujie = require("game_dujie")
        Dujie.StartGame(data)

    elseif evtType == "dujie_fail" then
        -- 渡劫失败, 更新剩余次数
        local Dujie = require("game_dujie")
        Dujie.OnServerFail(data)
        M.AddLog(data.msg or "渡劫失败", Config.Colors.red)

    elseif evtType == "rebirth_done" then
        M.customers = {}
        M.craftQueue = {}
        M.logs = {}
        M.floatingTexts = {}
        M.AddLog("第" .. (data.newRebirthCount or 1) .. "世开始!", Config.Colors.purple)
        State.Emit("rebirth_done", data)

    elseif evtType == "stall_upgraded" then
        M.AddLog("摊位升至 Lv." .. (data.level or "?") .. "!", Config.Colors.textGold)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("摊位升级成功!", { variant = "success", duration = 2 })
        State.Emit("stall_upgraded", data.level)

    elseif evtType == "fengshui_upgraded" then
        if data.fengshui then State.state.fengshui = data.fengshui end
        -- 从配置查找阵位名称
        local fName = "阵位"
        for _, f in ipairs(Config.FengshuiFormations) do
            if f.id == data.formationId then fName = f.name break end
        end
        local fLvl = data.newLevel or "?"
        M.AddLog(fName .. "升至 Lv." .. fLvl .. "!", Config.Colors.blue)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(fName .. " 升级成功!", { variant = "success", duration = 2 })
        State.Emit("fengshui_upgraded", data)

    elseif evtType == "pill_purchased" then
        if data.collectibles then State.state.collectibles = data.collectibles end
        local pName = data.itemName or "丹药"
        M.AddLog("购买了 " .. pName .. "!", Config.Colors.orange)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("成功购买 " .. pName .. "!", { variant = "success", duration = 2 })
        State.Emit("pill_purchased", data)

    elseif evtType == "marketplace_purchased" then
        if data.lingshi then State.state.lingshi = data.lingshi end
        if data.materials then State.state.materials = data.materials end
        if data.collectibles then State.state.collectibles = data.collectibles end
        if data.dailyShopBuys then State.state.dailyShopBuys = data.dailyShopBuys end
        local pName = data.itemName or "商品"
        local amt = data.amount or 1
        M.AddLog("购买了 " .. pName .. " x" .. amt, Config.Colors.orange)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("成功购买 " .. pName .. " x" .. amt, { variant = "success", duration = 2 })
        State.Emit("marketplace_purchased", data)

    elseif evtType == "field_planted" then
        State.Emit("field_changed")

    elseif evtType == "field_harvested" then
        -- 日志已在客户端乐观更新时打出, 此处仅刷新 UI
        State.Emit("field_changed")

    elseif evtType == "field_harvest_all_done" then
        -- 客户端已改为逐个 field_harvest, 此事件仅兼容保留
        State.Emit("field_changed")

    elseif evtType == "field_upgraded" then
        -- 日志已在客户端乐观更新时打出, 此处仅刷新 UI
        State.Emit("field_upgraded", data.level)

    elseif evtType == "ad_reward_done" then
        -- 服务端已确认奖励, 清除待确认记录
        State.state.pendingAdReward = nil
        -- 同步服务端返回的buff状态到客户端
        if data.adFlowBoostEnd then State.state.adFlowBoostEnd = data.adFlowBoostEnd end
        if data.adPriceBoostEnd then State.state.adPriceBoostEnd = data.adPriceBoostEnd end
        if data.adUpgradeDiscount then State.state.adUpgradeDiscount = data.adUpgradeDiscount end
        if data.adDiscountExpire then State.state.adDiscountExpire = data.adDiscountExpire end
        if data.offlineAdExtend then State.state.offlineAdExtend = data.offlineAdExtend end
        if data.totalAdWatched then State.state.totalAdWatched = data.totalAdWatched end
        if data.dungeonBonusUses then State.state.dungeonBonusUses = data.dungeonBonusUses end
        if data.dailyAdCounts then State.state.dailyAdCounts = data.dailyAdCounts end
        local Ad = require("ui_ad")
        Ad.MarkDirty()
        local keyNames = { bless = "仙缘加持", fortune = "天降横财", aid = "修仙助力", dungeon_ticket = "秘境探险券" }
        local name = keyNames[data.key] or data.key or ""
        M.AddLog("福利领取成功: " .. name, Config.Colors.purple)
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(name .. " 已激活!", { variant = "success", duration = 2 })

    elseif evtType == "merchant_done" then
        if (data.earned or 0) > 0 then
            M.AddLog("神秘商人收购! +" .. data.earned .. "灵石", Config.Colors.purple)
        else
            M.AddLog("神秘商人来了, 但库存为空!", Config.Colors.textSecond)
        end

    elseif evtType == "refine_done" then
        local cost = data.cost or 0
        local gain = data.gain or 0
        M.AddLog("炼化灵石! -" .. cost .. "灵石 修为+" .. gain, Config.Colors.textGold)
        M.AddFloatingText("修为+" .. gain, Config.Colors.purple)

    elseif evtType == "refine_batch_done" then
        local totalCost = data.totalCost or 0
        local totalGain = data.totalGain or 0
        local count = data.count or 0
        local HUD = require("ui_hud")
        M.AddLog("一键炼化x" .. count .. "! -" .. HUD.FormatNumber(totalCost) .. "灵石 修为+" .. HUD.FormatNumber(totalGain), Config.Colors.textGold)
        M.AddFloatingText("修为+" .. HUD.FormatNumber(totalGain), Config.Colors.purple)
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("炼化x" .. count .. " 修为+" .. HUD.FormatNumber(totalGain), { variant = "success", duration = 1.5 })

    elseif evtType == "refine_toggled" then
        M.AddLog("自动炼化: " .. (data.enabled and "开启" or "关闭"), Config.Colors.blue)

    elseif evtType == "auto_repair_toggled" then
        M.AddLog("自动修复: " .. (data.enabled and "开启" or "关闭"), Config.Colors.blue)
        State.Emit("auto_repair_toggled", data)

    elseif evtType == "newbie_gift_claimed" then
        M.AddLog("新手礼包已领取!", Config.Colors.textGold)

    elseif evtType == "lifespan_miracle" then
        M.AddLog("误入禁地, 意外获得续命神药! 延寿百年!", Config.Colors.textGold)
        M.PlaySFX("encounter")
        State.Emit("lifespan_miracle")

    elseif evtType == "player_dead" then
        M.AddLog("寿元耗尽, 道消身陨...", Config.Colors.red)
        -- 立即标记 dead, 防止后续 GAME_SYNC 中 dead 变化再次触发弹窗
        State.state.dead = true
        State.Emit("player_dead")

    elseif evtType == "encounter" then
        M.PlaySFX("encounter")
        State.Emit("encounter_triggered", data)

    elseif evtType == "auto_sell" then
        M.AddLog("[自动] 制售 " .. (data.productName or "?") .. " +" .. (data.price or 0) .. "灵石",
            Config.Colors.blue)
        M.AddFloatingText("[自动] +" .. (data.price or 0), Config.Colors.blue)

    elseif evtType == "gm_result" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "GM操作完成", { variant = "success", duration = 2 })

    elseif evtType == "cdk_result" then
        local UI = require("urhox-libs/UI")
        if data.ok then
            UI.Toast.Show(data.msg or "兑换成功!", { variant = "success", duration = 2 })
            if data.reward then
                local CDK = require("ui_cdk")
                CDK.ShowRewardModal(data.reward)
            end
        else
            UI.Toast.Show(data.msg or "兑换失败", { variant = "warning", duration = 2 })
        end

    elseif evtType == "cdk_created" then
        local GM = require("ui_gm")
        if GM.OnCdkCreated then GM.OnCdkCreated(data) end

    elseif evtType == "gm_version_info" then
        local GM = require("ui_gm")
        if GM.OnVersionInfo then GM.OnVersionInfo(data) end

    elseif evtType == "gm_debug_list" then
        local GM = require("ui_gm")
        if GM.OnDebugList then GM.OnDebugList(data) end

    elseif evtType == "online_status" then
        State.Emit("online_status_result", data)

    elseif evtType == "action_fail" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "操作失败", { variant = "warning", duration = 2 })
        -- 如果讨价面板正在等待结果，关闭它
        State.Emit("bargain_done", { zone = "fail", mul = 1.0, win = false })
        -- 通知其他监听者（如 ui_tribulation 战斗日志）
        State.Emit("action_fail_received", data)

    elseif evtType == "offline_claimed" then
        M.AddLog("离线收益已领取" .. (data.doubleMul == 2 and "(双倍灵石!)" or ""),
            Config.Colors.textGold)

    elseif evtType == "mail_reward_done" then
        print("[MailReward] 收到 mail_reward_done, lingshi=" .. tostring(data.lingshi)
            .. " xiuwei=" .. tostring(data.xiuwei)
            .. " type=" .. tostring(data.rewardType) .. " amt=" .. tostring(data.rewardAmt))
        local HUD = require("ui_hud")
        local rewardType = data.rewardType or ""
        local rewardAmt  = data.rewardAmt or 0
        local title      = data.title or "邮件"
        if rewardAmt > 0 then
            if rewardType == "lingshi" then
                M.AddLog("邮件奖励: +" .. HUD.FormatNumber(rewardAmt) .. " 灵石", Config.Colors.textGold)
            elseif rewardType == "xiuwei" then
                M.AddLog("邮件奖励: +" .. rewardAmt .. " 修为", Config.Colors.purple)
            else
                local mat = Config.GetMaterialById(rewardType)
                local matName = mat and mat.name or rewardType
                M.AddLog("邮件奖励: +" .. rewardAmt .. " " .. matName, Config.Colors.textGreen)
            end
        else
            M.AddLog("已领取邮件: " .. title, Config.Colors.textGold)
        end
        M.PlaySFX("upgrade")
        print("[MailReward] 即时同步后 State.lingshi=" .. tostring(State.state.lingshi)
            .. " xiuwei=" .. tostring(State.state.xiuwei))

    elseif evtType == "bargain_result" then
        -- 多轮讨价: 更新本地顾客状态
        for _, cust in ipairs(M.customers) do
            if cust.serverId == data.custId then
                cust.bargainMul = data.mul
                if data.isFinal then
                    cust.bargainDone = true
                    cust.bargaining = false
                    print("[Bargain] bargain_result isFinal, bargaining=false custId=" .. tostring(data.custId))
                end
                if data.refused then
                    -- 顾客拒绝: 标记离开
                    cust.bargainDone = true
                    cust.bargaining = false
                    cust.state = "leaving"
                    cust.walkProgress = 1.0
                    print("[Bargain] bargain_result refused, bargaining=false custId=" .. tostring(data.custId))
                end
                if not data.isFinal and not data.refused then
                    -- 多轮讨价中，保持 bargaining=true
                    cust.bargaining = true
                    print("[Bargain] bargain_result 继续讨价, bargaining=true custId=" .. tostring(data.custId))
                end
                break
            end
        end
        State.state.totalBargains = data.totalBargains or State.state.totalBargains
        State.state.bargainWins = data.bargainWins or State.state.bargainWins
        local mulPct = math.floor((data.mul or 1.0) * 100)
        if data.refused then
            M.AddLog("顾客拒绝购买,生气离开了!", Config.Colors.red)
            M.PlaySFX("encounter")
        elseif data.win then
            M.AddLog("讨价成功! 售价x" .. mulPct .. "%", Config.Colors.textGold)
            M.AddFloatingText("讨价成功 x" .. mulPct .. "%!", Config.Colors.textGold)
            M.PlaySFX("upgrade")
        else
            M.AddLog("讨价结果: 售价x" .. mulPct .. "%", Config.Colors.textSecond)
        end
        State.Emit("bargain_done", data)

    elseif evtType == "bargain_accepted" then
        -- 玩家接受讨价结果
        for _, cust in ipairs(M.customers) do
            if cust.serverId == data.custId then
                cust.bargainDone = true
                cust.bargainMul = data.mul
                cust.bargaining = false
                print("[Bargain] bargain_accepted, bargaining=false custId=" .. tostring(data.custId))
                break
            end
        end
        local mulPct = math.floor((data.mul or 1.0) * 100)
        M.AddLog("接受讨价 售价x" .. mulPct .. "%", Config.Colors.jade)
        State.Emit("bargain_accepted", data)

    elseif evtType == "synthesize_done" then
        local mat = Config.GetMaterialById(data.outputId)
        local matName = mat and mat.name or data.outputId
        M.AddLog("合成成功: " .. matName .. " x" .. (data.outputAmount or 0), Config.Colors.jade)
        M.AddFloatingText("合成 " .. matName .. " x" .. (data.outputAmount or 0), Config.Colors.jade)
        M.PlaySFX("craft_complete")
        State.Emit("synthesize_done", data)

    elseif evtType == "synthesize_all_done" then
        local results = data.results or {}
        local parts = {}
        for _, r in ipairs(results) do
            table.insert(parts, r.name .. "x" .. r.amount)
        end
        local summary = table.concat(parts, ", ")
        M.AddLog("一键合成: " .. summary, Config.Colors.jade)
        M.AddFloatingText("一键合成完成", Config.Colors.jade)
        M.PlaySFX("craft_complete")
        State.Emit("synthesize_done", data)

    elseif evtType == "daily_task_claimed" then
        local reward = data.reward or {}
        local parts = {}
        if reward.lingshi then table.insert(parts, "灵石+" .. reward.lingshi) end
        if reward.xiuwei then table.insert(parts, "修为+" .. reward.xiuwei) end
        M.AddLog("任务奖励: " .. table.concat(parts, " "), Config.Colors.textGold)
        M.PlaySFX("upgrade")
        State.Emit("daily_task_claimed", data)

    elseif evtType == "dungeon_enter" then
        -- 进入秘境: 保存运行时状态
        M.dungeonState = {
            dungeonId = data.dungeonId,
            step = data.step,
            totalSteps = data.totalSteps,
            desc = data.desc,
            choices = data.choices,
            results = {},
            totalReward = {},
        }
        local cfg = Config.GetDungeonById(data.dungeonId)
        M.AddLog("进入" .. (cfg and cfg.name or "秘境") .. "...", Config.Colors.jade)
        M.PlaySFX("encounter")
        State.Emit("dungeon_enter", data)

    elseif evtType == "dungeon_result" then
        -- 秘境选择结果
        local stepResult = {
            step = data.step,
            choiceIdx = data.choiceIdx,
            choiceText = data.choiceText,
            success = data.success,
            reward = data.reward,
        }
        if M.dungeonState then
            table.insert(M.dungeonState.results, stepResult)
            M.dungeonState.totalReward = data.totalReward or M.dungeonState.totalReward
        end
        -- 日志
        if data.success then
            local parts = {}
            for k, v in pairs(data.reward or {}) do
                table.insert(parts, k .. "+" .. v)
            end
            M.AddLog("探险成功! " .. table.concat(parts, " "), Config.Colors.textGold)
            M.PlaySFX("upgrade")
        else
            local parts = {}
            for k, v in pairs(data.reward or {}) do
                if v < 0 then table.insert(parts, k .. v) end
            end
            M.AddLog("探险失败... " .. table.concat(parts, " "), Config.Colors.red)
        end
        if data.isLast then
            -- 探险结束
            M.AddLog("秘境探险结束!", Config.Colors.jade)
            State.Emit("dungeon_settle", data)
            M.dungeonState = nil
        else
            -- 下一事件
            if M.dungeonState then
                M.dungeonState.step = data.nextStep
                M.dungeonState.desc = data.nextDesc
                M.dungeonState.choices = data.nextChoices
            end
            State.Emit("dungeon_next", data)
        end

    elseif evtType == "dungeon_abandon" then
        M.AddLog("放弃秘境探险", Config.Colors.textSecond)
        M.dungeonState = nil
        State.Emit("dungeon_abandon", data)

    elseif evtType == "artifact_crafted" then
        M.AddLog("炼制成功: " .. (data.name or "法宝"), Config.Colors.jade)
        M.AddFloatingText("炼制 " .. (data.name or "法宝"), Config.Colors.jade)
        M.PlaySFX("craft_complete")
        State.Emit("artifact_changed")

    elseif evtType == "artifact_equipped" then
        local artCfg = Config.GetArtifactById(data.artId)
        M.AddLog("装备法宝: " .. (artCfg and artCfg.name or ""), Config.Colors.purple)
        M.PlaySFX("upgrade")
        State.Emit("artifact_changed")

    elseif evtType == "artifact_unequipped" then
        local artCfg = Config.GetArtifactById(data.artId)
        M.AddLog("卸下法宝: " .. (artCfg and artCfg.name or ""), Config.Colors.textSecond)
        State.Emit("artifact_changed")

    elseif evtType == "artifact_upgraded" then
        local artCfg = Config.GetArtifactById(data.artId)
        M.AddLog("法宝升阶: " .. (artCfg and artCfg.name or "") .. " → " .. (data.newLevel or 2) .. "阶", Config.Colors.textGold)
        M.AddFloatingText("升阶! " .. (data.newLevel or 2) .. "阶", Config.Colors.textGold)
        M.PlaySFX("upgrade")
        State.Emit("artifact_changed")

    elseif evtType == "artifact_repaired" then
        local artCfg = Config.GetArtifactById(data.artId)
        M.AddLog("法宝修复: " .. (artCfg and artCfg.name or "") .. " 耐久已满", Config.Colors.jade)
        M.AddFloatingText("修复成功", Config.Colors.jade)
        M.PlaySFX("craft_complete")
        State.Emit("artifact_changed")

    elseif evtType == "artifact_durability_zero" then
        M.AddLog("法宝 " .. (data.name or "") .. " 耐久归零,加成已失效!", Config.Colors.danger)
        M.AddFloatingText((data.name or "法宝") .. " 损坏", Config.Colors.danger)
        M.PlaySFX("fail")
        State.Emit("artifact_changed")

    elseif evtType == "artifact_durability_warn" then
        local artCfg = Config.GetArtifactById(data.artId)
        M.AddLog("法宝 " .. (artCfg and artCfg.name or "") .. " 耐久低: " .. (data.durability or 0), Config.Colors.warning)
        State.Emit("artifact_changed")

    -- ========== 分田种植 ==========
    elseif evtType == "plot_crop_set" then
        local crop = nil
        for _, c in ipairs(Config.Crops) do if c.id == data.cropId then crop = c; break end end
        M.AddLog("地块" .. (data.plotIdx or "?") .. "设置种植: " .. (crop and crop.name or data.cropId), Config.Colors.jade)
        State.Emit("field_changed")

    -- ========== 珍藏物品 ==========
    elseif evtType == "collectible_gained" then
        if data.items then
            for _, itemId in ipairs(data.items) do
                local cfg = Config.GetCollectibleById(itemId)
                if cfg then
                    M.AddLog("获得珍藏: " .. cfg.name, Config.Colors.textGold)
                    M.AddFloatingText(cfg.name, Config.Colors.textGold)
                end
            end
            M.PlaySFX("upgrade")
        end
        State.Emit("collectible_changed")

    elseif evtType == "item_used" then
        M.AddLog(data.msg or "使用成功", Config.Colors.jade)
        M.AddFloatingText(data.name or "物品", Config.Colors.jade)
        M.PlaySFX("craft_complete")
        State.Emit("collectible_changed")

    elseif evtType == "collectible_used" then
        -- 仙界消耗品使用成功
        if data.collectibles then State.state.collectibles = data.collectibles end
        if data.fabaoCount ~= nil then State.state.fabaoCount = data.fabaoCount end
        M.AddLog(data.msg or "使用成功", Config.Colors.jade)
        M.AddFloatingText(data.name or "物品", Config.Colors.jade)
        M.PlaySFX("craft_complete")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "使用成功", { variant = "success", duration = 2 })
        State.Emit("collectible_changed")

    elseif evtType == "collectible_sold" then
        if data.collectibles then State.state.collectibles = data.collectibles end
        local HUD = require("ui_hud")
        M.AddLog("出售 " .. (data.name or "物品") .. " x" .. (data.amount or 1)
            .. " +" .. HUD.FormatNumber(data.totalPrice or 0) .. "灵石", Config.Colors.textGold)
        M.AddFloatingText("+" .. HUD.FormatNumber(data.totalPrice or 0) .. " 灵石", Config.Colors.textGold)
        M.PlaySFX("buy")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("成功出售「" .. (data.name or "物品") .. "」获得 " .. HUD.FormatNumber(data.totalPrice or 0) .. " 灵石", { variant = "success", duration = 2 })
        State.Emit("collectible_changed")

    -- ========== 师徒系统 ==========
    elseif evtType == "mentor_invite_received" then
        -- 实时收到邀请(对方在线发来的)
        local UI = require("urhox-libs/UI")
        local fromName = data.fromName or "仙友"
        local fromRealmName = data.fromRealmName or ""
        local inviteType = data.inviteType or "recruit"
        local fromId = data.fromId or 0
        local title, msg
        if inviteType == "recruit" then
            title = "收徒邀请"
            msg = fromName .. "(" .. fromRealmName .. ") 想收你为徒\n拜师后修炼速度+10%"
        else
            title = "拜师申请"
            msg = fromName .. "(" .. fromRealmName .. ") 想拜你为师\n收徒后获得徒弟修为10%分成"
        end
        UI.Toast.Show(fromName .. (inviteType == "recruit" and " 想收你为徒" or " 想拜你为师"),
            { variant = "info", duration = 5 })
        local modal = UI.Modal {
            title = title,
            size = "sm",
            closeOnOverlay = true,
            onClose = function(self) self:Destroy() end,
        }
        modal:AddContent(UI.Panel {
            width = "100%", gap = 6, padding = 4, alignItems = "center",
            children = {
                UI.Label { text = msg, fontSize = 10, fontColor = Config.Colors.text, textAlign = "center", width = "100%" },
                UI.Panel {
                    flexDirection = "row", gap = 10, width = "100%", justifyContent = "center", marginTop = 6,
                    children = {
                        UI.Button {
                            text = "拒绝", fontSize = 9, height = 28, paddingHorizontal = 18,
                            variant = "secondary", borderRadius = 6,
                            onClick = function()
                                modal:Close()
                                M.SendGameAction("mentor_reject", { fromId = fromId })
                            end,
                        },
                        UI.Button {
                            text = "同意", fontSize = 9, height = 28, paddingHorizontal = 18,
                            variant = "primary", borderRadius = 6,
                            onClick = function()
                                modal:Close()
                                M.SendGameAction("mentor_accept", { fromId = fromId })
                            end,
                        },
                    },
                },
            },
        })
        modal:Open()

    elseif evtType == "mentor_pending_list" then
        -- 上线时收到待处理邀请列表 → 交给 ui_mentor 展示
        State.Emit("mentor_pending_list", data)

    elseif evtType == "mentor_result" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "操作完成", { variant = "success", duration = 3 })

    elseif evtType == "mentor_bound" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "师徒关系建立", { variant = "success", duration = 4 })
        M.AddLog(data.msg or "师徒关系建立", Config.Colors.textGold)
        M.PlaySFX("upgrade")
        State.Emit("mentor_changed")

    elseif evtType == "mentor_rejected" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "对方拒绝了邀请", { variant = "warning", duration = 3 })

    elseif evtType == "mentor_dismissed" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "师徒关系已解除", { variant = "info", duration = 3 })
        M.AddLog(data.msg or "师徒关系已解除", Config.Colors.warning)
        State.Emit("mentor_changed")

    elseif evtType == "mentor_graduated" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "出师了", { variant = "success", duration = 5 })
        M.AddLog(data.msg or "出师", Config.Colors.textGold)
        M.AddFloatingText("出师了", Config.Colors.textGold)
        M.PlaySFX("upgrade")
        State.Emit("mentor_changed")

    elseif evtType == "mentor_offline_settle" then
        if data.xiuwei and data.xiuwei > 0 then
            local HUD = require("ui_hud")
            local UI = require("urhox-libs/UI")
            UI.Toast.Show("离线期间获得徒弟分成 " .. HUD.FormatNumber(data.xiuwei) .. " 修为", { variant = "success", duration = 4 })
            M.AddLog("离线徒弟分成 +" .. HUD.FormatNumber(data.xiuwei) .. " 修为", Config.Colors.jade)
        end

    elseif evtType == "mentor_gift_result" then
        local UI = require("urhox-libs/UI")
        if data.ok then
            UI.Toast.Show(data.msg or "赠送成功", { variant = "success", duration = 3 })
            M.AddLog(data.msg or "赠送成功", Config.Colors.jade)
        else
            UI.Toast.Show(data.msg or "赠送失败", { variant = "warning", duration = 3 })
        end
        State.Emit("mentor_changed")
        State.Emit("mentor_gift_result", data)  -- 传递 remaining 次数给 UI

    elseif evtType == "mentor_gift_received" then
        local UI = require("urhox-libs/UI")
        UI.Toast.Show(data.msg or "收到徒弟赠礼", { variant = "success", duration = 4 })
        M.AddLog(data.msg or "收到徒弟赠礼", Config.Colors.textGold)
        M.AddFloatingText("收到赠礼", Config.Colors.textGold)
        M.PlaySFX("coin")

    elseif evtType == "mentor_info" then
        State.Emit("mentor_info_received", data)

    -- ====== 渡劫 Boss 战事件 (功能10) ======
    elseif evtType == "tribulation_state" then
        -- 初始化/重连恢复 Boss战状态
        State.state.tribulation_active = true
        State.state.tribulation_hp     = data.hp    or 0
        State.state.tribulation_round  = data.round or 1
        State.Emit("tribulation_state_changed", data)

    elseif evtType == "tribulation_round" then
        -- 每轮结束，更新 Boss 状态
        State.state.tribulation_hp    = data.hp    or 0
        State.state.tribulation_round = data.round or 1
        State.Emit("tribulation_round_ended", data)

    elseif evtType == "tribulation_win" then
        -- Boss 战胜利
        State.state.tribulation_active = false
        State.state.tribulation_hp     = 0
        State.state.tribulation_round  = 0
        State.state.tribulation_won    = true
        M.AddLog("天劫已破！渡劫成功！", Config.Colors.textGold)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("天劫已破！可飞升仙界！", { variant = "success", duration = 3 })
        State.Emit("tribulation_win", data)

    elseif evtType == "tribulation_fail" then
        -- Boss 战失败
        State.state.tribulation_active = false
        State.state.tribulation_hp     = 0
        State.state.tribulation_round  = 0
        M.AddLog("渡劫失败，残余灵石受损...", Config.Colors.red)
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("渡劫失败！可再次尝试", { variant = "warning", duration = 3 })
        State.Emit("tribulation_fail", data)

    -- ====== 飞升事件 (功能11) ======
    elseif evtType == "ascend_success" then
        State.state.realmLevel = data.realmLevel or State.state.realmLevel
        State.state.ascended   = true
        State.state.tribulation_won = true
        if data.lifespan then State.state.lifespan = data.lifespan end
        M.AddLog("飞升成功！晋升【" .. (data.realmName or "天仙") .. "】！", Config.Colors.textGold)
        M.AddFloatingText("飞升! " .. (data.realmName or "天仙"), Config.Colors.textGold)
        M.PlaySFX("upgrade")
        local UI = require("urhox-libs/UI")
        UI.Toast.Show("恭喜飞升仙界！踏入【" .. (data.realmName or "天仙") .. "】！", { variant = "success", duration = 4 })
        State.Emit("ascended", data)
    end
end

--- 发送讨价还价操作
---@param custId number 顾客服务端ID
---@param hitPos number 击中位置(0-1)
function M.Bargain(custId, hitPos)
    -- 客户端立即标记 bargaining，暂停进度条
    for _, c in ipairs(M.customers) do
        if c.serverId == custId then
            c.bargaining = true
            print("[Bargain] 客户端设置 bargaining=true custId=" .. tostring(custId))
            break
        end
    end
    M.SendGameAction("bargain", { custId = custId, hitPos = hitPos })
end

--- 发送接受讨价还价结果
---@param custId number 顾客服务端ID
function M.BargainAccept(custId)
    M.SendGameAction("bargain_accept", { custId = custId })
end

--- 发送合成操作
---@param recipeId string 配方ID
---@param count? number 合成数量(默认1)
function M.Synthesize(recipeId, count)
    M.SendGameAction("synthesize", { recipeId = recipeId, count = count or 1 })
end

--- 一键合成(所有配方合成到上限)
function M.SynthesizeAll()
    M.SendGameAction("synthesize_all", {})
end

--- 发送领取每日任务奖励
---@param taskIdx number 任务索引(从1开始)
function M.ClaimDailyTask(taskIdx)
    M.SendGameAction("claim_daily_task", { taskIdx = taskIdx })
end

--- 进入秘境探险
---@param dungeonId string 秘境ID
function M.EnterDungeon(dungeonId)
    M.SendGameAction("dungeon_enter", { dungeonId = dungeonId })
end

--- 秘境中做出选择
---@param choiceIdx number 选项索引(1-3)
function M.DungeonChoose(choiceIdx)
    M.SendGameAction("dungeon_choose", { choiceIdx = choiceIdx })
end

--- 放弃秘境探险
function M.AbandonDungeon()
    M.SendGameAction("dungeon_abandon", {})
end

return M
