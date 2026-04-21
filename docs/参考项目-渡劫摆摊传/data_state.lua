-- ============================================================================
-- data_state.lua — 渡劫摆摊传 游戏状态管理 + 云变量存档
-- 使用 clientCloud BatchSet/BatchGet 替代本地 XOR 加密存档
-- iscores: lingshi, xiuwei, totalEarned, totalSold, totalCrafted, totalAdWatched, stallLevel
-- values:  gameState (JSON blob, 包含所有非 iscores 的复杂数据)
-- ============================================================================
local Config = require("data_config")

local M = {}

-- ========== 云变量 Key 定义 ==========
-- iscores 键(整数, 可排行榜排序)
local ISCORE_KEYS = {
    "lingshi", "xiuwei", "totalEarned", "totalSold",
    "totalCrafted", "totalAdWatched", "stallLevel", "realmLevel",
}

-- values 键(复杂数据)
local GAME_STATE_KEY = "gameState"

-- ========== 默认状态 ==========
local function createDefaultState()
    return {
        -- 货币 (同步到 iscores)
        lingshi = 0,
        xiuwei = 0,

        -- 材料库存
        materials = {
            lingcao = 0,
            lingzhi = 0,
            xuantie = 0,
            -- 仙界基础材料
            lingjing_cao   = 0,
            tianchan_si    = 0,
            xingchen_kuang = 0,
            -- 仙界合成材料
            shanggu_lingjing  = 0,
            tianchan_jinghua  = 0,
            xingchen_jinghua  = 0,
            hundun_jing       = 0,
        },

        -- 商品库存(已制作完成的)
        products = {
            juqi_dan = 0,
            huichun_fu = 0,
            dijie_faqi = 0,
            ninghun_dan = 0,
            poxu_fu = 0,
            xianqi_canpian = 0,
            zhuji_lingyao = 0,
            wanling_juan = 0,
            tianjie_faqi = 0,
            feisheng_dan = 0,
            -- 仙界商品
            tianxian_dan     = 0,
            tianchan_fu      = 0,
            xingchen_faqi    = 0,
            xuanxian_lingdan = 0,
            shenluo_fu       = 0,
            jinxian_fabao    = 0,
            taiyi_lingdan    = 0,
            wanxiang_shenfu  = 0,
            zhunsheng_fabao  = 0,
            hundun_zhu       = 0,
        },

        -- 摊位 (stallLevel 同步到 iscores)
        stallLevel = 1,
        shelf = {},

        -- 统计 (同步到 iscores)
        totalSold = 0,
        totalEarned = 0,
        totalCrafted = 0,
        todayEarned = 0,       -- 今日收入(每日排行用)
        todayDate = "",        -- 今日日期标记(YYYYMMDD)

        -- 制作队列
        craftQueue = {},

        -- 广告增益
        adFlowBoostEnd = 0,
        adPriceBoostEnd = 0,
        adUpgradeDiscount = 0,     -- 剩余减免次数(0=无)
        adDiscountExpire = 0,      -- 减免过期时间戳
        totalAdWatched = 0,
        adFreeExpire = 0,      -- 免广告到期时间戳(os.time)
        dailyAdCounts = {},    -- 每种广告奖励今日已领次数 {[rewardKey]=count}
        dailyAdDate = "",      -- 每日广告次数重置日期标记(YYYYMMDD)
        offlineAdExtend = 0,   -- 离线延长广告已看次数(每次+1h,最多5次,领取后清零)

        -- 境界突破 (显式)
        realmLevel = 1,       -- 当前已突破到的境界等级 (1=炼气)
        lifespan = 100,       -- 当前剩余寿元(年)

        -- 转生系统
        rebirthCount = 0,     -- 转生次数
        dead = false,         -- 是否已陨落(寿元归零)

        -- 称号系统
        highestRealmEver = 1, -- 历史最高境界(转生保留)
        myTodayRank = nil,    -- 今日排名(缓存, 每次打开排行榜刷新)

        -- 新手标记
        storyPlayed = false,
        tutorialStep = 0,
        newbieGiftClaimed = false,
        guideCompleted = false,

        -- 灵田系统
        fieldLevel = 1,
        fieldPlots = {},

        -- 奇遇系统
        lastEncounterTime = 0,

        -- CDK 兑换
        redeemedCDKs = {},

        -- 炼化设置
        autoRefine = false,   -- 自动炼化开关
        autoRepairArtifacts = false, -- 法宝自动修复开关

        -- 灵童雇佣
        fieldServant = {
            tier = 0,                   -- 0=未雇佣, 1/2/3=木/玉/金
            expireTime = 0,             -- 到期时间戳(os.time)
            plantCrop = "lingcao_seed", -- 自动种植的作物类型(tier>=2时生效)
            paused = false,             -- 是否暂停工作
        },

        -- 炼器傀儡
        craftPuppet = {
            active = false,             -- 是否激活
            expireTime = 0,             -- 到期时间戳(os.time)
            products = {},              -- 自动制作的商品ID列表 如{"juqi_dan","huichun_fu"}
            paused = false,             -- 是否暂停工作
        },

        -- 角色信息
        playerName = "",      -- 道号(角色名)
        playerGender = "",    -- 性别("male"/"female")
        playerId = "",        -- 自定义玩家ID(角色创建时生成)
        serverId = 0,         -- 所属区服ID(服务端写入)

        -- 口碑系统
        reputation = 100,     -- 口碑值(0~1000)
        repStreak = 0,        -- 连续满足需求计数

        -- 讨价还价统计
        totalBargains = 0,    -- 讨价还价总次数
        bargainWins = 0,      -- 讨价还价成功次数(good/perfect)

        -- 每日任务
        dailyTasks = {},      -- 当日任务列表
        dailyTaskDate = "",   -- 任务刷新日期(YYYYMMDD)
        dailyTasksClaimed = 0, -- 累计已领取任务数

        -- 秘境探险
        dungeonCooldown = 0,   -- [废弃]下次可探险时间戳(保留兼容旧存档)
        totalDungeonRuns = 0,  -- 累计探险次数
        dungeonHistory = {},   -- 秘境历史记录(保留1天)
        dungeonDailyUses = {}, -- 每个秘境今日已用次数 {[dungeonId]=count}
        dungeonDailyDate = "", -- 秘境每日次数重置日期(YYYYMMDD)

        -- 渡劫小游戏
        dujieDailyDate = "",   -- 每日重置日期(YYYYMMDD)
        dujieFreeUses = 0,     -- 今日已用免费次数
        dujiePaidUses = 0,     -- 今日已用付费次数

        -- 渡劫 Boss 战 (功能10)
        tribulation_hp     = 0,     -- Boss 当前血量(0=未开始/已结束)
        tribulation_round  = 0,     -- 当前第几劫(0=未开始)
        tribulation_active = false, -- 是否处于 Boss 战中
        tribulation_won    = false, -- 是否已击败天劫Boss(允许飞升)

        -- 飞升/仙界 (功能11)
        ascended = false,   -- 是否已飞升进入仙界

        -- 法宝系统
        artifacts = {},          -- 已拥有法宝 {[artId] = {count=n, level=1}}
        equippedArtifacts = {},   -- 装备栏 [{id=artId, level=1}, ...]

        -- 珍藏物品
        collectibles = {},       -- {[itemId] = count}

        -- 广告奖励待确认(断线重连补发用)
        pendingAdReward = nil,  -- nil 或 {key=string, nonce=string}

        -- 设置
        bgmEnabled = true,
        sfxEnabled = true,

        -- 时间戳
        lastSaveTime = 0,

        -- 师徒系统
        masterId = nil,            -- 师父userId (nil=无师父)
        masterName = "",           -- 师父名字(展示用)
        masterRealmAtBind = 0,     -- 拜师时师父境界(出师目标)
        disciples = {},            -- 徒弟列表 [{userId,name,realmAtBind,acceptTime}]
        mentorXiuweiEarned = 0,    -- 累计从徒弟获得的修为
        graduatedCount = 0,        -- 已出师徒弟数
        pendingMentorInvites = {},  -- 待处理师徒邀请 [{fromId,fromName,fromRealm,type("recruit"/"apply"),timestamp}]
    }
end

-- ========== 当前状态 ==========
---@type table
M.state = createDefaultState()

-- ========== 云加载状态 ==========
M.cloudReady = false

-- ========== 服务端权威模式 ==========
M.serverMode = false

-- ========== 事件监听 ==========
local listeners = {}

--- 注册状态变化监听
---@param event string
---@param callback function
---@return number listenerId
function M.On(event, callback)
    if not listeners[event] then
        listeners[event] = {}
    end
    table.insert(listeners[event], callback)
    -- 返回取消订阅函数
    return function()
        M.Off(event, callback)
    end
end

--- 取消监听
---@param event string
---@param callback function
function M.Off(event, callback)
    if not listeners[event] then return end
    for i, cb in ipairs(listeners[event]) do
        if cb == callback then
            table.remove(listeners[event], i)
            return
        end
    end
end

--- 触发事件
---@param event string
---@param ... any
function M.Emit(event, ...)
    if listeners[event] then
        for _, cb in ipairs(listeners[event]) do
            cb(...)
        end
    end
end

-- ========== 状态操作 ==========

--- 检查并重置每日数据(跨天时自动归零)
function M.CheckDailyReset()
    local today = M.GetTodayKey()
    if M.state.todayDate ~= today then
        M.state.todayDate = today
        M.state.todayEarned = 0
    end
    -- 每日广告次数重置
    if M.state.dailyAdDate ~= today then
        M.state.dailyAdDate = today
        M.state.dailyAdCounts = {}
    end
    -- 每日秘境次数重置
    if M.state.dungeonDailyDate ~= today then
        M.state.dungeonDailyDate = today
        M.state.dungeonDailyUses = {}
        M.state.dungeonBonusUses = {}
    end
    -- 每日渡劫次数重置
    if M.state.dujieDailyDate ~= today then
        M.state.dujieDailyDate = today
        M.state.dujieFreeUses = 0
        M.state.dujiePaidUses = 0
    end
end

--- 每种广告奖励每日上限(默认)
local DAILY_AD_LIMIT = 3
--- 特定广告的独立上限
local AD_LIMIT_OVERRIDE = {
    dungeon_ticket = 1,  -- 秘境探险券每日1次
}

--- 获取某种广告奖励今日已领次数
---@param rewardKey string
---@return number
function M.GetDailyAdCount(rewardKey)
    M.CheckDailyReset()
    return M.state.dailyAdCounts[rewardKey] or 0
end

--- 获取每日广告上限(支持 per-key 独立上限)
---@param rewardKey? string 传入 key 时返回该 key 的上限，不传返回默认上限
---@return number
function M.GetDailyAdLimit(rewardKey)
    if rewardKey and AD_LIMIT_OVERRIDE[rewardKey] then
        return AD_LIMIT_OVERRIDE[rewardKey]
    end
    return DAILY_AD_LIMIT
end

--- 检查某种广告奖励今日是否还可领取
---@param rewardKey string
---@return boolean
function M.CanClaimAdReward(rewardKey)
    return M.GetDailyAdCount(rewardKey) < M.GetDailyAdLimit(rewardKey)
end

--- 消耗一次广告奖励次数(领取时调用)
---@param rewardKey string
function M.UseAdRewardCount(rewardKey)
    M.CheckDailyReset()
    M.state.dailyAdCounts[rewardKey] = (M.state.dailyAdCounts[rewardKey] or 0) + 1
end

--- 增加灵石
---@param amount number
function M.AddLingshi(amount)
    M.CheckDailyReset()
    M.state.lingshi = M.state.lingshi + math.floor(amount)
    M.state.totalEarned = M.state.totalEarned + math.floor(amount)
    M.state.todayEarned = (M.state.todayEarned or 0) + math.floor(amount)
    -- 被动修为: 每赚 PassiveXiuweiPerLingshi 灵石 → 10修为
    local threshold = Config.PassiveXiuweiPerLingshi or 50
    local xiuweiGain = math.floor(amount / threshold) * 10
    if xiuweiGain > 0 then
        M.AddXiuwei(xiuweiGain)
    end
    M.Emit("lingshi_changed", M.state.lingshi)
end

--- 消费灵石
---@param amount number
---@return boolean success
function M.SpendLingshi(amount)
    if M.state.lingshi >= amount then
        M.state.lingshi = M.state.lingshi - amount
        M.Emit("lingshi_changed", M.state.lingshi)
        return true
    end
    return false
end

--- 增加修为
---@param amount number
function M.AddXiuwei(amount)
    M.state.xiuwei = M.state.xiuwei + amount
    M.Emit("xiuwei_changed", M.state.xiuwei)
end

--- 增加材料
---@param materialId string
---@param amount number
function M.AddMaterial(materialId, amount)
    if M.state.materials[materialId] ~= nil then
        M.state.materials[materialId] = M.state.materials[materialId] + amount
        M.Emit("material_changed", materialId, M.state.materials[materialId])
    end
end

--- 消耗材料
---@param materialId string
---@param amount number
---@return boolean
function M.SpendMaterial(materialId, amount)
    if M.state.materials[materialId] and M.state.materials[materialId] >= amount then
        M.state.materials[materialId] = M.state.materials[materialId] - amount
        M.Emit("material_changed", materialId, M.state.materials[materialId])
        return true
    end
    return false
end

--- 增加商品库存
---@param productId string
---@param amount number
function M.AddProduct(productId, amount)
    M.state.products[productId] = (M.state.products[productId] or 0) + amount
    M.state.totalCrafted = (M.state.totalCrafted or 0) + amount
    M.Emit("product_changed", productId, M.state.products[productId])
end

--- 消耗商品(售出)
---@param productId string
---@param amount number
---@return boolean
function M.SellProduct(productId, amount)
    if M.state.products[productId] and M.state.products[productId] >= amount then
        M.state.products[productId] = M.state.products[productId] - amount
        M.state.totalSold = M.state.totalSold + amount
        M.Emit("product_changed", productId, M.state.products[productId])
        return true
    end
    return false
end

--- 升级摊位
---@param discount? number 折扣比例(0-1), 如 0.3 表示减免30%
---@return boolean success
function M.UpgradeStall(discount)
    local curLevel = M.state.stallLevel
    if curLevel >= #Config.StallLevels then return false end
    local nextCfg = Config.StallLevels[curLevel + 1]
    local cost = nextCfg.cost
    if discount and discount > 0 then
        cost = math.floor(cost * (1 - discount))
    end
    if M.SpendLingshi(cost) then
        M.state.stallLevel = curLevel + 1
        M.AddXiuwei(50)  -- 升级奖励
        M.Emit("stall_upgraded", M.state.stallLevel)
        return true
    end
    return false
end

--- 获取当前摊位配置
---@return table
function M.GetStallConfig()
    return Config.StallLevels[M.state.stallLevel]
end

--- 获取当前境界索引 (使用显式 realmLevel)
---@return number
function M.GetRealmIndex()
    return M.state.realmLevel
end

--- 获取称号总加成倍率(境界称号 + 排行称号)
---@return number multiplier (1.0 = 无加成)
function M.GetTitleBonus()
    local bonus = 0
    -- 境界称号加成
    local realmTitle = Config.GetRealmTitle(M.state.highestRealmEver or 1)
    if realmTitle then
        bonus = bonus + realmTitle.bonus
    end
    -- 排行称号加成
    local rankTitle = Config.GetRankTitle(M.state.myTodayRank)
    if rankTitle then
        bonus = bonus + rankTitle.bonus
    end
    return 1.0 + bonus
end

--- 售价加成是否生效
---@return boolean
function M.IsPriceBoosted()
    return (M.state.adPriceBoostEnd or 0) > os.time()
end

--- 售价加成剩余秒数
---@return number
function M.PriceBoostRemain()
    return math.max(0, (M.state.adPriceBoostEnd or 0) - os.time())
end

--- 升级/突破减免是否可用(次数>0 且未过期)
---@return boolean
function M.HasUpgradeDiscount()
    return (M.state.adUpgradeDiscount or 0) > 0
        and (M.state.adDiscountExpire or 0) > os.time()
end

--- 消耗一次升级减免
function M.UseUpgradeDiscount()
    if M.HasUpgradeDiscount() then
        M.state.adUpgradeDiscount = M.state.adUpgradeDiscount - 1
    end
end

--- 获取商品实际售价(含境界加成 + 转生加成 + 称号加成 + 售价加成)
---@param productCfg table
---@return number
function M.GetProductPrice(productCfg)
    local realmMul = Config.GetRealmPriceMultiplier(M.GetRealmIndex())
    local rebirthMul = M.GetRebirthBonus()
    local titleMul = M.GetTitleBonus()
    local priceMul = M.IsPriceBoosted() and 1.5 or 1.0
    return math.floor(productCfg.price * realmMul * rebirthMul * titleMul * priceMul)
end

--- 检查是否可以突破到下一境界
---@return boolean canBreak
---@return string? reason
function M.CanBreakthrough()
    local curLevel = M.state.realmLevel
    if curLevel >= #Config.Realms then
        return false, "已达最高境界"
    end
    local nextLevel = curLevel + 1
    local nextRealm = Config.Realms[nextLevel]
    if M.state.xiuwei < nextRealm.xiuwei then
        return false, "修为不足(需" .. nextRealm.xiuwei .. ")"
    end
    -- 检查突破材料需求
    local matReqs = Config.BreakthroughMaterials[nextLevel]
    if matReqs then
        for _, req in ipairs(matReqs) do
            local have = (M.state.collectibles or {})[req.id] or 0
            if have < req.count then
                local cfg = Config.GetCollectibleById(req.id)
                local name = cfg and cfg.name or req.id
                return false, name .. "不足(需" .. req.count .. ",有" .. have .. ")"
            end
        end
    end
    local cost = nextRealm.breakthroughCost
    if M.HasUpgradeDiscount() then
        cost = math.floor(cost * 0.7)
    end
    if M.state.lingshi < cost then
        return false, "灵石不足(需" .. cost .. ")"
    end
    return true
end

--- 执行境界突破
---@return boolean success
---@return string? reason
function M.Breakthrough()
    local canDo, reason = M.CanBreakthrough()
    if not canDo then return false, reason end

    local curLevel = M.state.realmLevel
    local nextRealm = Config.Realms[curLevel + 1]

    -- 消耗灵石(含减免)
    local cost = nextRealm.breakthroughCost
    if M.HasUpgradeDiscount() then
        cost = math.floor(cost * 0.7)
        M.UseUpgradeDiscount()
    end
    M.state.lingshi = M.state.lingshi - cost
    -- 提升境界
    M.state.realmLevel = curLevel + 1
    -- 更新历史最高境界(称号系统用)
    if M.state.realmLevel > (M.state.highestRealmEver or 1) then
        M.state.highestRealmEver = M.state.realmLevel
    end
    -- 突破增加寿元: 获得新境界的基础寿元
    M.state.lifespan = M.state.lifespan + nextRealm.lifespan

    M.Emit("lingshi_changed", M.state.lingshi)
    M.Emit("realm_up", M.state.realmLevel, nextRealm.name)
    return true
end

--- 炼化灵石化为修为
---@return boolean success
---@return number cost 消耗灵石
---@return number gain 获得修为
function M.RefineLingshi()
    local realmIdx = M.state.realmLevel
    local cfg = Config.AbsorbConfig[realmIdx]
    if not cfg then return false, 0, 0 end
    local cost = math.floor(cfg.amount * cfg.ratio)
    if M.state.lingshi < cost then
        return false, cost, cfg.amount
    end
    M.state.lingshi = M.state.lingshi - cost
    M.AddXiuwei(cfg.amount)
    M.Emit("lingshi_changed", M.state.lingshi)
    return true, cost, cfg.amount
end

--- 是否处于免广告状态
---@return boolean
function M.IsAdFree()
    return M.state.adFreeExpire > os.time()
end

--- 免广告剩余天数
---@return number
function M.AdFreeRemainDays()
    local remain = M.state.adFreeExpire - os.time()
    if remain <= 0 then return 0 end
    return math.ceil(remain / 86400)
end

--- 激活免广告特权
---@param days number 天数
function M.ActivateAdFree(days)
    local now = os.time()
    -- 如果已有免广告, 在原到期基础上延长; 否则从现在开始
    local base = M.state.adFreeExpire > now and M.state.adFreeExpire or now
    M.state.adFreeExpire = base + days * 86400
end

--- 获取当前炼化配置(用于UI显示)
---@return number cost 灵石花费
---@return number gain 修为获得
---@return boolean canAfford 是否买得起
function M.GetRefineInfo()
    local realmIdx = M.state.realmLevel
    local cfg = Config.AbsorbConfig[realmIdx]
    if not cfg then return 0, 0, false end
    local cost = math.floor(cfg.amount * cfg.ratio)
    return cost, cfg.amount, M.state.lingshi >= cost
end

--- 消耗寿元
---@param amount number 消耗的寿元(年)
function M.DrainLifespan(amount)
    if M.state.dead then return end
    M.state.lifespan = math.max(0, M.state.lifespan - amount)
    -- 检测寿元归零
    if M.state.lifespan <= 0 then
        -- 5% 概率触发逆活一世
        if math.random() < 0.05 then
            M.state.lifespan = 100
            M.Emit("lifespan_miracle")
        else
            M.state.dead = true
            M.Emit("player_dead")
        end
    end
end

--- 获取当前寿元
---@return number
function M.GetLifespan()
    return M.state.lifespan
end

--- 获取转生次数
---@return number
function M.GetRebirthCount()
    return M.state.rebirthCount
end

--- 获取转生全局收益加成倍率
---@return number multiplier (1.0 = 无加成)
function M.GetRebirthBonus()
    local rb = Config.Rebirth
    local bonus = M.state.rebirthCount * rb.bonusPerRebirth
    return 1.0 + math.min(bonus, rb.maxBonus)
end

--- 获取转生保留灵石比例
---@return number rate (0.0 ~ maxKeepRate)
function M.GetRebirthKeepRate()
    local rb = Config.Rebirth
    local rate = rb.lingshiKeepRate + M.state.rebirthCount * rb.keepRatePerRebirth
    return math.min(rate, rb.maxKeepRate)
end

--- 执行转生: 重置大部分状态, 保留灵石比例, 增加转生次数
---@return table summary 转生结算数据
function M.DoRebirth()
    local rb = Config.Rebirth
    local oldCount = M.state.rebirthCount
    local newCount = oldCount + 1

    -- 保留灵石
    local keepRate = M.GetRebirthKeepRate()
    local keptLingshi = math.floor(M.state.lingshi * keepRate)

    -- 转生加成
    local bonusLifespan = newCount * rb.lifespanBonus
    local bonusXiuwei = newCount * rb.xiuweiBonus

    -- 记录结算信息
    local summary = {
        oldRebirthCount = oldCount,
        newRebirthCount = newCount,
        oldLingshi = M.state.lingshi,
        keptLingshi = keptLingshi,
        keepRate = keepRate,
        bonusLifespan = bonusLifespan,
        bonusXiuwei = bonusXiuwei,
        oldRealmLevel = M.state.realmLevel,
        oldRealmName = Config.Realms[M.state.realmLevel].name,
    }

    -- 重置状态
    local defaults = createDefaultState()
    -- 保留全局字段
    defaults.rebirthCount = newCount
    defaults.storyPlayed = true            -- 转生后不再播放开场剧情
    defaults.newbieGiftClaimed = true       -- 不再给新手礼包
    defaults.tutorialStep = M.state.tutorialStep  -- 保留引导进度
    defaults.guideCompleted = M.state.guideCompleted  -- 保留引导完成状态
    defaults.bgmEnabled = M.state.bgmEnabled
    defaults.sfxEnabled = M.state.sfxEnabled
    defaults.autoRefine = M.state.autoRefine      -- 保留炼化设置
    defaults.playerName = M.state.playerName      -- 保留角色名
    defaults.playerGender = M.state.playerGender  -- 保留性别
    defaults.playerId = M.state.playerId          -- 保留玩家ID
    defaults.serverId = M.state.serverId          -- 保留区服ID
    defaults.redeemedCDKs = M.state.redeemedCDKs  -- 保留已兑换的CDK
    defaults.adFreeExpire = M.state.adFreeExpire  -- 保留免广告特权
    defaults.highestRealmEver = M.state.highestRealmEver or 1  -- 保留历史最高境界
    defaults.reputation = M.state.reputation              -- 口碑跨转生保留
    defaults.repStreak = 0                                -- 连击重置
    defaults.totalBargains = M.state.totalBargains        -- 讨价还价统计保留
    defaults.bargainWins = M.state.bargainWins
    defaults.dailyTasksClaimed = M.state.dailyTasksClaimed
    defaults.artifacts = M.state.artifacts                -- 法宝跨转生保留
    defaults.equippedArtifacts = M.state.equippedArtifacts
    -- 珍藏物品: 永久类保留, 消耗品清零
    local keptCollectibles = {}
    for itemId, count in pairs(M.state.collectibles or {}) do
        local cfg = Config.GetCollectibleById(itemId)
        if cfg and cfg.type == "permanent" and count > 0 then
            keptCollectibles[itemId] = count
        end
    end
    defaults.collectibles = keptCollectibles
    -- 每日任务在转生后由服务端重新刷新, dailyTasks/dailyTaskDate 用defaults即可
    -- 转生加成
    defaults.lingshi = keptLingshi
    defaults.xiuwei = bonusXiuwei
    defaults.lifespan = Config.Realms[1].lifespan + bonusLifespan
    defaults.dead = false

    M.state = defaults

    -- 保存并通知
    M.Save()
    M.Emit("rebirth_done", summary)
    M.Emit("state_loaded")
    M.Emit("lingshi_changed", M.state.lingshi)
    M.Emit("xiuwei_changed", M.state.xiuwei)

    return summary
end

-- ========== 云变量存档 ==========

--- 从 state 提取 gameState blob (非 iscores 的复杂数据)
---@return table
local function extractGameStateBlob()
    return {
        materials = M.state.materials,
        products = M.state.products,
        shelf = M.state.shelf,
        craftQueue = M.state.craftQueue,
        realmLevel = M.state.realmLevel,
        lifespan = M.state.lifespan,
        rebirthCount = M.state.rebirthCount,
        highestRealmEver = M.state.highestRealmEver or 1,
        dead = M.state.dead,
        adFlowBoostEnd = M.state.adFlowBoostEnd,
        adPriceBoostEnd = M.state.adPriceBoostEnd,
        adUpgradeDiscount = M.state.adUpgradeDiscount,
        adDiscountExpire = M.state.adDiscountExpire,
        adFreeExpire = M.state.adFreeExpire,
        dailyAdCounts = M.state.dailyAdCounts,
        dailyAdDate = M.state.dailyAdDate,
        offlineAdExtend = M.state.offlineAdExtend,
        storyPlayed = M.state.storyPlayed,
        tutorialStep = M.state.tutorialStep,
        newbieGiftClaimed = M.state.newbieGiftClaimed,
        guideCompleted = M.state.guideCompleted,
        fieldLevel = M.state.fieldLevel,
        fieldPlots = M.state.fieldPlots,
        lastEncounterTime = M.state.lastEncounterTime,
        redeemedCDKs = M.state.redeemedCDKs,
        playerName = M.state.playerName,
        playerGender = M.state.playerGender,
        playerId = M.state.playerId,
        serverId = M.state.serverId,
        bgmEnabled = M.state.bgmEnabled,
        sfxEnabled = M.state.sfxEnabled,
        autoRefine = M.state.autoRefine,
        fieldServant = M.state.fieldServant,
        craftPuppet = M.state.craftPuppet,
        lastSaveTime = M.state.lastSaveTime,
        -- 口碑/讨价还价/每日任务
        reputation = M.state.reputation,
        repStreak = M.state.repStreak,
        totalBargains = M.state.totalBargains,
        bargainWins = M.state.bargainWins,
        dailyTasks = M.state.dailyTasks,
        dailyTaskDate = M.state.dailyTaskDate,
        dailyTasksClaimed = M.state.dailyTasksClaimed,
        -- 秘境探险
        dungeonCooldown = M.state.dungeonCooldown,
        totalDungeonRuns = M.state.totalDungeonRuns,
        dungeonHistory = M.state.dungeonHistory,
        dungeonDailyUses = M.state.dungeonDailyUses,
        dungeonDailyDate = M.state.dungeonDailyDate,

        -- 秘境广告奖励次数
        dungeonBonusUses = M.state.dungeonBonusUses,

        -- 渡劫小游戏
        dujieDailyDate = M.state.dujieDailyDate,
        dujieFreeUses = M.state.dujieFreeUses,
        dujiePaidUses = M.state.dujiePaidUses,

        -- 法宝
        artifacts = M.state.artifacts,
        equippedArtifacts = M.state.equippedArtifacts,

        -- 珍藏物品
        collectibles = M.state.collectibles,

        -- 广告奖励待确认
        pendingAdReward = M.state.pendingAdReward,

        -- 渡劫 Boss 战
        tribulation_hp     = M.state.tribulation_hp,
        tribulation_round  = M.state.tribulation_round,
        tribulation_active = M.state.tribulation_active,
        tribulation_won    = M.state.tribulation_won,

        -- 飞升/仙界
        ascended = M.state.ascended,
    }
end

--- 获取今日日期 key 后缀 (YYYYMMDD)
---@return string
function M.GetTodayKey()
    return os.date("!%Y%m%d", os.time() + 8 * 3600)  -- UTC+8 北京时间零点刷新
end

--- 保存游戏(云变量 BatchSet)
function M.Save()
    if M.serverMode then return end  -- 服务端权威模式下不由客户端保存
    if not M.cloudReady then
        print("[Save] Cloud not ready, skipping save")
        return
    end

    M.state.lastSaveTime = os.time()

    local todayKey = "earned_" .. M.GetTodayKey()

    clientCloud:BatchSet()
        :SetInt("lingshi", math.floor(M.state.lingshi))
        :SetInt("xiuwei", math.floor(M.state.xiuwei))
        :SetInt("totalEarned", math.floor(M.state.totalEarned))
        :SetInt("totalSold", math.floor(M.state.totalSold))
        :SetInt("totalCrafted", math.floor(M.state.totalCrafted))
        :SetInt("totalAdWatched", math.floor(M.state.totalAdWatched))
        :SetInt("stallLevel", M.state.stallLevel)
        :SetInt("realmLevel", M.state.realmLevel)
        :SetInt(todayKey, math.floor(M.state.todayEarned or 0))
        :Set("playerName", M.state.playerName or "")
        :Set("playerGender", M.state.playerGender or "male")
        :Set("playerId", M.state.playerId or "")
        :Set(GAME_STATE_KEY, extractGameStateBlob())
        :Save("自动存档", {
            ok = function()
                print("[Save] Cloud save OK")
            end,
            error = function(code, reason)
                print("[Save] Cloud save failed: " .. tostring(reason))
            end,
            timeout = function()
                print("[Save] Cloud save timeout")
            end,
        })
end

--- 重置全服排行分数(GM用, 用 serverCloud 清零所有上榜用户的 iscores)
---@param callback? fun(success: boolean, msg?: string)
---@param sid? number 指定区服ID(nil则用当前区服)
function M.ResetRankScores(callback, sid)
    ---@diagnostic disable-next-line: undefined-global
    if not serverCloud then
        print("[GM] serverCloud 不可用, 回退到仅重置自己")
        M.ResetMyRankScores(callback)
        return
    end

    -- 区服 key 前缀
    if sid == nil then sid = M.state.serverId or 0 end
    local function rk(base)
        if not sid or sid == 0 then return base end
        return base .. "_" .. tostring(sid)
    end

    -- 用于扫描排行的 key 列表(覆盖所有排行维度, 带区服前缀)
    local todayKey = rk("earned_" .. M.GetTodayKey())
    local scanKeys = { rk("lingshi"), rk("totalEarned"), rk("realmLevel"), todayKey }
    -- 所有要清零的 iscore key
    local allResetKeys = {}
    for _, k in ipairs(ISCORE_KEYS) do
        allResetKeys[rk(k)] = true
    end
    allResetKeys[todayKey] = true

    -- Step 1: 从各排行榜收集所有上榜用户ID
    local userIdSet = {}
    local pending = #scanKeys

    local function onScanDone()
        -- 收集完毕, 开始逐个重置
        local userIds = {}
        for _, uid in pairs(userIdSet) do
            table.insert(userIds, uid)
        end
        if #userIds == 0 then
            print("[GM] 排行榜无用户, 无需重置")
            if callback then callback(true, "排行榜为空") end
            return
        end

        -- Step 2: 逐个用户 BatchSet 清零
        local totalUsers = #userIds
        local doneCount = 0
        local failCount = 0

        for _, uid in ipairs(userIds) do
            ---@diagnostic disable-next-line: undefined-global
            local batch = serverCloud:BatchSet(uid)
            for key, _ in pairs(allResetKeys) do
                batch:SetInt(key, 0)
            end
            batch:Save("GM全服重置排行", {
                ok = function()
                    doneCount = doneCount + 1
                    if doneCount + failCount >= totalUsers then
                        print("[GM] 全服排行重置完成: " .. doneCount .. " 成功, " .. failCount .. " 失败")
                        -- 同步自己的本地状态
                        M.state.lingshi = 0
                        M.state.xiuwei = 0
                        M.state.totalEarned = 0
                        M.state.totalSold = 0
                        M.state.totalCrafted = 0
                        M.state.totalAdWatched = 0
                        M.state.stallLevel = 1
                        M.state.todayEarned = 0
                        M.Emit("lingshi_changed", 0)
                        M.Emit("xiuwei_changed", 0)
                        if callback then callback(true, "已重置 " .. totalUsers .. " 位玩家") end
                    end
                end,
                error = function(code, reason)
                    failCount = failCount + 1
                    print("[GM] 重置用户 " .. tostring(uid) .. " 失败: " .. tostring(reason))
                    if doneCount + failCount >= totalUsers then
                        if callback then callback(failCount == 0, "完成 " .. doneCount .. "/" .. totalUsers) end
                    end
                end,
            })
        end
    end

    for _, key in ipairs(scanKeys) do
        ---@diagnostic disable-next-line: undefined-global
        serverCloud:GetRankList(key, 0, 100, {
            ok = function(rankList)
                for _, item in ipairs(rankList) do
                    userIdSet[tostring(item.userId)] = item.userId
                end
                pending = pending - 1
                if pending == 0 then onScanDone() end
            end,
            error = function(code, reason)
                print("[GM] GetRankList(" .. key .. ") failed: " .. tostring(reason))
                pending = pending - 1
                if pending == 0 then onScanDone() end
            end,
        })
    end
end

--- 仅重置自己的排行分数(fallback)
---@param callback? fun(success: boolean, msg?: string)
function M.ResetMyRankScores(callback)
    if not M.cloudReady then
        if callback then callback(false) end
        return
    end
    local sid = M.state.serverId
    local function rk(base)
        if not sid or sid == 0 then return base end
        return base .. "_" .. tostring(sid)
    end
    local batch = clientCloud:BatchSet()
    for _, key in ipairs(ISCORE_KEYS) do
        batch:SetInt(rk(key), 0)
    end
    local todayKey = rk("earned_" .. M.GetTodayKey())
    batch:SetInt(todayKey, 0)
    batch:Save("GM重置自己排行", {
        ok = function()
            M.state.lingshi = 0
            M.state.xiuwei = 0
            M.state.totalEarned = 0
            M.state.totalSold = 0
            M.state.totalCrafted = 0
            M.state.totalAdWatched = 0
            M.state.stallLevel = 1
            M.state.todayEarned = 0
            M.Emit("lingshi_changed", 0)
            M.Emit("xiuwei_changed", 0)
            if callback then callback(true, "已重置自己") end
        end,
        error = function(code, reason)
            print("[GM] Reset my rank failed: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 读取存档(云变量 BatchGet, 异步)
---@param callback? fun(success: boolean)
function M.Load(callback)
    if M.serverMode then
        -- 服务端权威模式下不主动加载, 等待 GameInit 事件
        if callback then callback(true) end
        return
    end
    local batchGet = clientCloud:BatchGet()
    for _, key in ipairs(ISCORE_KEYS) do
        batchGet:Key(key)
    end
    batchGet:Key(GAME_STATE_KEY)

    local function onLoadSuccess(values, iscores)
        local defaults = createDefaultState()
        M.state = defaults

        -- 从 iscores 恢复整数字段
        M.state.lingshi = iscores.lingshi or 0
        M.state.xiuwei = iscores.xiuwei or 0
        M.state.totalEarned = iscores.totalEarned or 0
        M.state.totalSold = iscores.totalSold or 0
        M.state.totalCrafted = iscores.totalCrafted or 0
        M.state.totalAdWatched = iscores.totalAdWatched or 0
        M.state.stallLevel = iscores.stallLevel or 1
        if M.state.stallLevel < 1 then M.state.stallLevel = 1 end

        -- 从 values 恢复 gameState blob
        local gs = values[GAME_STATE_KEY]
        if gs and type(gs) == "table" then
            -- 合并材料(兼容新增: 先用defaults兜底, 再合并云端所有key)
            if type(gs.materials) == "table" then
                for k, v in pairs(defaults.materials) do
                    M.state.materials[k] = gs.materials[k] or v
                end
                -- 合并非defaults中的高级材料(gaoji_lingcao等)
                for k, v in pairs(gs.materials) do
                    if M.state.materials[k] == nil then
                        M.state.materials[k] = v
                    end
                end
            end
            -- 合并商品(兼容新增: 先用defaults兜底, 再合并云端所有key)
            if type(gs.products) == "table" then
                for k, v in pairs(defaults.products) do
                    M.state.products[k] = gs.products[k] or v
                end
                for k, v in pairs(gs.products) do
                    if M.state.products[k] == nil then
                        M.state.products[k] = v
                    end
                end
            end
            -- 简单字段
            M.state.shelf = gs.shelf or {}
            M.state.craftQueue = gs.craftQueue or {}
            M.state.adFlowBoostEnd = gs.adFlowBoostEnd or 0
            M.state.adPriceBoostEnd = gs.adPriceBoostEnd or gs.adAutoSellEnd or 0
            -- 兼容旧存档: boolean → number
            if type(gs.adUpgradeDiscount) == "boolean" then
                M.state.adUpgradeDiscount = gs.adUpgradeDiscount and 1 or 0
            else
                M.state.adUpgradeDiscount = gs.adUpgradeDiscount or 0
            end
            M.state.adDiscountExpire = gs.adDiscountExpire or 0
            M.state.adFreeExpire = gs.adFreeExpire or 0
            M.state.dailyAdCounts = type(gs.dailyAdCounts) == "table" and gs.dailyAdCounts or {}
            M.state.dailyAdDate = gs.dailyAdDate or ""
            M.state.offlineAdExtend = gs.offlineAdExtend or 0
            M.state.realmLevel = math.max(gs.realmLevel or 1, iscores.realmLevel or 1)
            if M.state.realmLevel < 1 then M.state.realmLevel = 1 end
            M.state.lifespan = gs.lifespan or Config.Realms[M.state.realmLevel].lifespan
            M.state.rebirthCount = gs.rebirthCount or 0
            M.state.highestRealmEver = math.max(gs.highestRealmEver or 1, M.state.realmLevel)
            M.state.dead = (gs.dead == true)
            M.state.storyPlayed = (gs.storyPlayed == true)
            M.state.tutorialStep = gs.tutorialStep or 0
            M.state.newbieGiftClaimed = (gs.newbieGiftClaimed == true)
            M.state.guideCompleted = (gs.guideCompleted == true)
            M.state.fieldLevel = gs.fieldLevel or 1
            M.state.fieldPlots = type(gs.fieldPlots) == "table" and gs.fieldPlots or {}
            M.state.lastEncounterTime = gs.lastEncounterTime or 0
            M.state.redeemedCDKs = type(gs.redeemedCDKs) == "table" and gs.redeemedCDKs or {}
            M.state.bgmEnabled = (gs.bgmEnabled ~= false)
            M.state.sfxEnabled = (gs.sfxEnabled ~= false)
            M.state.autoRefine = (gs.autoRefine == true)
            -- 灵童雇佣
            if type(gs.fieldServant) == "table" then
                M.state.fieldServant = {
                    tier = gs.fieldServant.tier or 0,
                    expireTime = gs.fieldServant.expireTime or 0,
                    plantCrop = gs.fieldServant.plantCrop or "lingcao_seed",
                }
            end
            -- 炼器傀儡
            if type(gs.craftPuppet) == "table" then
                M.state.craftPuppet = {
                    active = (gs.craftPuppet.active == true),
                    expireTime = gs.craftPuppet.expireTime or 0,
                    products = type(gs.craftPuppet.products) == "table" and gs.craftPuppet.products or {},
                }
            end
            M.state.playerName = type(gs.playerName) == "string" and gs.playerName or ""
            M.state.playerGender = type(gs.playerGender) == "string" and gs.playerGender or ""
            M.state.playerId = type(gs.playerId) == "string" and gs.playerId or ""
            M.state.serverId = type(gs.serverId) == "number" and gs.serverId or 0
            M.state.lastSaveTime = gs.lastSaveTime or 0

            -- 渡劫 Boss 战 (新字段兜底，老存档默认值)
            M.state.tribulation_hp     = gs.tribulation_hp    or 0
            M.state.tribulation_round  = gs.tribulation_round or 0
            M.state.tribulation_active = (gs.tribulation_active == true)
            M.state.tribulation_won    = (gs.tribulation_won   == true)

            -- 飞升/仙界 (新字段兜底)
            M.state.ascended = (gs.ascended == true)
            -- realmLevel>=10 说明已是仙界境界，ascended 必须为 true
            if M.state.realmLevel >= 10 and not M.state.ascended then
                M.state.ascended = true
                print("[Load] 自动修正 ascended=true (realmLevel=" .. M.state.realmLevel .. ")")
            end
        end

        print("[Load] Cloud load OK")
        M.cloudReady = true
        M.Emit("state_loaded")
        if callback then callback(true) end
    end

    local function onLoadFail(reason)
        print("[Load] Cloud load failed: " .. tostring(reason))
        -- 不设置 cloudReady, 阻止 Save 覆盖云端数据
        if callback then callback(false) end
    end

    batchGet:Fetch({
        ok = function(values, iscores)
            onLoadSuccess(values, iscores)
        end,
        error = function(code, reason)
            onLoadFail(reason)
        end,
        timeout = function()
            onLoadFail("timeout")
        end,
    })
end

--- 刷新今日排名缓存(异步, 供称号加成使用)
function M.RefreshMyTodayRank()
    if not M.cloudReady then return end
    local sid = M.state.serverId
    local todayBase = "earned_" .. M.GetTodayKey()
    local todayKey = (sid and sid ~= 0) and (todayBase .. "_" .. tostring(sid)) or todayBase
    clientCloud:GetUserRank(clientCloud.userId, todayKey, {
        ok = function(rank, scoreValue)
            M.state.myTodayRank = rank  -- nil = 未上榜
        end,
        error = function()
            -- 查询失败不更新
        end,
    })
end

--- 重置状态(新游戏)
function M.Reset()
    M.state = createDefaultState()
    M.Emit("state_loaded")
    M.Save()
end

--- 获取玩家 ID (由服务端分配, 未分配时返回空串)
---@return string
function M.GetPlayerId()
    if M.state.playerId and M.state.playerId ~= "" then
        return M.state.playerId
    end
    return ""
end

--- 角色是否已创建(有道号)
---@return boolean
function M.HasPlayerName()
    return M.state.playerName ~= nil and M.state.playerName ~= ""
end

--- 获取显示用名称(道号 > 玩家ID > 未知)
---@return string
function M.GetDisplayName()
    if M.HasPlayerName() then
        return M.state.playerName
    end
    ---@diagnostic disable-next-line: undefined-global
    if lobby and lobby.GetMyUserId then
        ---@diagnostic disable-next-line: undefined-global
        return "玩家" .. tostring(lobby:GetMyUserId())
    end
    return "未知"
end

-- ========== 服务端同步接口 ==========

--- 接收服务端全量状态同步(GameSync, 每2秒)
---@param stateTable table 服务端发来的完整 state
function M.ApplyServerSync(stateTable)
    if not stateTable then return end
    local oldLingshi = M.state.lingshi
    local oldXiuwei = M.state.xiuwei
    local oldRealm = M.state.realmLevel
    local oldDead = M.state.dead
    -- 保存旧傀儡关键字段，用于避免无变化时触发 puppet_changed 导致制作页闪屏
    local oldPp = M.state.craftPuppet
    local oldPuppetKey = type(oldPp) == "table"
        and (tostring(oldPp.active) .. "|" .. tostring(oldPp.paused) .. "|" .. tostring(oldPp.expireTime)) or ""

    -- 全量覆盖
    local oldTutorialStep = M.state.tutorialStep or 0
    for k, v in pairs(stateTable) do
        M.state[k] = v
    end
    -- tutorialStep 只增不减: 客户端可能已推进到更高步骤, 防止被服务端旧值回退
    if M.state.tutorialStep < oldTutorialStep then
        M.state.tutorialStep = oldTutorialStep
    end
    -- JSON 反序列化后数字索引键会变成字符串键(如 "1" → 1)，需恢复
    -- fieldPlots 用数字索引 1..N 访问，必须修正
    if M.state.fieldPlots then
        local fixed = {}
        for k, v in pairs(M.state.fieldPlots) do
            local numKey = tonumber(k)
            if numKey then
                fixed[numKey] = v
            else
                fixed[k] = v
            end
        end
        M.state.fieldPlots = fixed
    end

    -- 触发变化事件(UI 刷新用)
    if M.state.lingshi ~= oldLingshi then M.Emit("lingshi_changed", M.state.lingshi) end
    if M.state.xiuwei ~= oldXiuwei then M.Emit("xiuwei_changed", M.state.xiuwei) end
    if M.state.realmLevel ~= oldRealm then
        local realmCfg = Config.Realms[M.state.realmLevel]
        M.Emit("realm_up", M.state.realmLevel, realmCfg and realmCfg.name or "")
    end
    if M.state.dead and not oldDead then M.Emit("player_dead") end
    -- 全量同步后刷新灵田/灵童/傀儡 UI
    if M.state.fieldPlots then
        local plotCount = 0
        for i, p in pairs(M.state.fieldPlots) do
            if type(p) == "table" and p.cropId and p.cropId ~= "" then
                plotCount = plotCount + 1
                print("[Sync] fieldPlots[" .. i .. "] cropId=" .. tostring(p.cropId) .. " plantTime=" .. tostring(p.plantTime))
            end
        end
        print("[Sync] fieldPlots has " .. plotCount .. " planted plots")
    end
    M.Emit("field_changed")
    M.Emit("servant_changed")
    -- puppet_changed 仅在数据实际变化时触发，避免制作页每次 sync 都重建傀儡状态条
    local newPp = M.state.craftPuppet
    local newPuppetKey = type(newPp) == "table"
        and (tostring(newPp.active) .. "|" .. tostring(newPp.paused) .. "|" .. tostring(newPp.expireTime)) or ""
    if newPuppetKey ~= oldPuppetKey then M.Emit("puppet_changed") end
end

--- 接收服务端初始化数据(GameInit, 首次连接)
---@param stateTable table 完整 state
function M.ApplyServerInit(stateTable)
    if not stateTable then return end
    M.state = createDefaultState()
    for k, v in pairs(stateTable) do
        M.state[k] = v
    end
    -- JSON 反序列化修正: fieldPlots 数字键恢复
    if M.state.fieldPlots then
        local fixed = {}
        for k, v in pairs(M.state.fieldPlots) do
            local numKey = tonumber(k)
            if numKey then fixed[numKey] = v else fixed[k] = v end
        end
        M.state.fieldPlots = fixed
    end
    M.cloudReady = true
    M.Emit("state_loaded")
    M.Emit("lingshi_changed", M.state.lingshi)
    M.Emit("xiuwei_changed", M.state.xiuwei)
end

-- ========== 公告系统 ==========
local ANNOUNCEMENT_KEY = "announcement"

--- 保存公告(GM 专用, 写入自己的云变量)
---@param text string
---@param callback? fun(success: boolean)
function M.SaveAnnouncement(text, callback)
    if not M.cloudReady then
        if callback then callback(false) end
        return
    end
    clientCloud:Set(ANNOUNCEMENT_KEY, {
        text = text,
        time = os.time(),
    }, {
        ok = function()
            print("[Announcement] Saved OK")
            if callback then callback(true) end
        end,
        error = function(code, reason)
            print("[Announcement] Save failed: " .. tostring(reason))
            if callback then callback(false) end
        end,
    })
end

--- 读取公告(从自己的云变量)
---@param callback fun(text: string|nil, time: number|nil)
function M.LoadAnnouncement(callback)
    if not M.cloudReady then
        callback(nil, nil)
        return
    end
    clientCloud:Get(ANNOUNCEMENT_KEY, {
        ok = function(values, iscores)
            local data = values[ANNOUNCEMENT_KEY]
            if data and type(data) == "table" and data.text and data.text ~= "" then
                callback(data.text, data.time)
            else
                callback(nil, nil)
            end
        end,
        error = function(code, reason)
            print("[Announcement] Load failed: " .. tostring(reason))
            callback(nil, nil)
        end,
    })
end

return M
