------------------------------------------------------------
-- data/data_shop.lua  —— 三国神将录 商城数据配置
-- 商品表、礼包表、充值档位、购买逻辑
-- 两端共享（服务端执行购买，客户端展示）
------------------------------------------------------------
local M = {}

------------------------------------------------------------
-- 一、资源商品（用元宝购买游戏资源）
------------------------------------------------------------
M.RESOURCE_ITEMS = {
    -- 体力
    {
        id       = "stamina_1",
        name     = "体力补给(小)",
        desc     = "立即恢复60点体力",
        category = "stamina",
        icon     = "Textures/icons/icon_stamina.png",
        currency = "yuanbao",
        price    = 50,
        reward   = { stamina = 60 },
        dailyLimit = 4,
    },
    -- 铜钱
    {
        id       = "copper_1",
        name     = "铜钱袋(小)",
        desc     = "获得5000铜钱",
        category = "copper",
        icon     = "Textures/icons/icon_copper.png",
        currency = "yuanbao",
        price    = 30,
        reward   = { copper = 5000 },
        dailyLimit = 0,  -- 0=不限购
    },
    {
        id       = "copper_2",
        name     = "铜钱袋(大)",
        desc     = "获得30000铜钱",
        category = "copper",
        icon     = "Textures/icons/icon_copper.png",
        currency = "yuanbao",
        price    = 150,
        reward   = { copper = 30000 },
        dailyLimit = 0,
    },
    -- 经验酒
    {
        id       = "exp_wine_1",
        name     = "经验酒(小)",
        desc     = "获得10瓶经验酒",
        category = "item",
        icon     = "Textures/icons/icon_exp_wine.png",
        currency = "yuanbao",
        price    = 40,
        reward   = { exp_wine = 10 },
        dailyLimit = 0,
    },
    {
        id       = "exp_wine_2",
        name     = "经验酒(大)",
        desc     = "获得50瓶经验酒",
        category = "item",
        icon     = "Textures/icons/icon_exp_wine.png",
        currency = "yuanbao",
        price    = 160,
        reward   = { exp_wine = 50 },
        dailyLimit = 0,
    },
    -- 招募令
    {
        id       = "zhaomuling_1",
        name     = "招募令 x5",
        desc     = "获得5张招募令",
        category = "recruit",
        icon     = "Textures/icons/icon_zhaomuling.png",
        currency = "yuanbao",
        price    = 80,
        reward   = { zhaomuling = 5 },
        dailyLimit = 0,
    },
    {
        id       = "zhaomuling_2",
        name     = "招募令 x20",
        desc     = "获得20张招募令(赠2张)",
        category = "recruit",
        icon     = "Textures/icons/icon_zhaomuling.png",
        currency = "yuanbao",
        price    = 280,
        reward   = { zhaomuling = 22 },
        dailyLimit = 0,
    },
    -- 将魂
    {
        id       = "jianghun_1",
        name     = "将魂包(小)",
        desc     = "获得200将魂",
        category = "item",
        icon     = "Textures/icons/icon_jianghun.png",
        currency = "yuanbao",
        price    = 60,
        reward   = { jianghun = 200 },
        dailyLimit = 0,
    },
}

------------------------------------------------------------
-- 二、礼包（打折组合包）
------------------------------------------------------------
M.GIFT_PACKS = {
    {
        id       = "newbie_pack",
        name     = "新手礼包",
        desc     = "超值新手大礼",
        tag      = "限购1次",
        icon     = "Textures/icons/icon_yuanbao.png",
        currency = "yuanbao",
        price    = 100,
        origPrice = 300,
        reward   = {
            copper     = 20000,
            exp_wine   = 30,
            zhaomuling = 5,
            jianghun   = 500,
        },
        totalLimit = 1,  -- 终身限购
    },
    {
        id       = "weekly_pack",
        name     = "每周礼包",
        desc     = "每周限购一次",
        tag      = "周限1次",
        icon     = "Textures/icons/icon_yuanbao.png",
        currency = "yuanbao",
        price    = 200,
        origPrice = 500,
        reward   = {
            copper     = 50000,
            exp_wine   = 50,
            zhaomuling = 10,
            stamina    = 120,
        },
        weeklyLimit = 1,
    },
    {
        id       = "stamina_pack",
        name     = "体力畅饮包",
        desc     = "体力恢复大礼包",
        tag      = "每日1次",
        icon     = "Textures/icons/icon_stamina.png",
        currency = "yuanbao",
        price    = 60,
        origPrice = 120,
        reward   = {
            stamina  = 120,
            copper   = 5000,
        },
        dailyLimit = 1,
    },
    {
        id       = "recruit_pack",
        name     = "招募特惠包",
        desc     = "招募令大礼",
        tag      = "每日1次",
        icon     = "Textures/icons/icon_zhaomuling.png",
        currency = "yuanbao",
        price    = 150,
        origPrice = 350,
        reward   = {
            zhaomuling = 15,
            jianghun   = 300,
        },
        dailyLimit = 1,
    },
}

------------------------------------------------------------
-- 三、充值档位（模拟充值，暂不接真实支付）
------------------------------------------------------------
M.RECHARGE_TIERS = {
    { id = "r6",   price = 6,   yuanbao = 60,   firstBonus = 60,   tag = "" },
    { id = "r30",  price = 30,  yuanbao = 300,  firstBonus = 300,  tag = "热门" },
    { id = "r68",  price = 68,  yuanbao = 680,  firstBonus = 680,  tag = "" },
    { id = "r128", price = 128, yuanbao = 1280, firstBonus = 1280, tag = "超值" },
    { id = "r328", price = 328, yuanbao = 3280, firstBonus = 3280, tag = "" },
    { id = "r648", price = 648, yuanbao = 6480, firstBonus = 6480, tag = "尊享" },
}

------------------------------------------------------------
-- 四、购买逻辑（服务端调用）
------------------------------------------------------------

--- 查找资源商品
---@param itemId string
---@return table|nil
function M.FindResourceItem(itemId)
    for _, item in ipairs(M.RESOURCE_ITEMS) do
        if item.id == itemId then return item end
    end
    return nil
end

--- 查找礼包
---@param packId string
---@return table|nil
function M.FindGiftPack(packId)
    for _, pack in ipairs(M.GIFT_PACKS) do
        if pack.id == packId then return pack end
    end
    return nil
end

--- 查找充值档位
---@param tierId string
---@return table|nil
function M.FindRechargeTier(tierId)
    for _, tier in ipairs(M.RECHARGE_TIERS) do
        if tier.id == tierId then return tier end
    end
    return nil
end

--- 发放奖励到玩家状态（服务端调用）
---@param state table 玩家状态
---@param reward table { copper=n, yuanbao=n, stamina=n, ... }
function M.GrantReward(state, reward)
    for key, amount in pairs(reward) do
        if key == "copper" then
            state.copper = (state.copper or 0) + amount
        elseif key == "yuanbao" then
            state.yuanbao = (state.yuanbao or 0) + amount
        elseif key == "stamina" then
            state.stamina = math.min(
                (state.stamina or 0) + amount,
                (state.staminaMax or 120) + amount  -- 允许超上限
            )
        elseif key == "jianghun" then
            state.jianghun = (state.jianghun or 0) + amount
        elseif key == "zhaomuling" then
            state.zhaomuling = (state.zhaomuling or 0) + amount
        elseif key == "exp_wine" then
            state.inventory = state.inventory or {}
            state.inventory.exp_wine = (state.inventory.exp_wine or 0) + amount
        end
    end
end

--- 确保商城购买记录存在（兼容旧存档）
---@param state table
function M.EnsureShopRecords(state)
    if not state.shopBuys then state.shopBuys = {} end
    if not state.shopDaily then state.shopDaily = {} end
    if not state.shopWeekly then state.shopWeekly = {} end
    if not state.rechargeFirst then state.rechargeFirst = {} end
    if not state.lastShopResetDay then state.lastShopResetDay = 0 end
    if not state.lastShopResetWeek then state.lastShopResetWeek = 0 end
end

--- 获取当天日期编号 (用于每日限购重置)
---@return number
local function todayNumber()
    return math.floor(os.time() / 86400)
end

--- 获取本周编号
---@return number
local function weekNumber()
    return math.floor(os.time() / (86400 * 7))
end

--- 检查每日限购并重置过期计数
---@param state table
local function checkDailyReset(state)
    M.EnsureShopRecords(state)
    local today = todayNumber()
    if state.lastShopResetDay ~= today then
        state.shopDaily = {}
        state.lastShopResetDay = today
    end
end

--- 检查每周限购并重置过期计数
---@param state table
local function checkWeeklyReset(state)
    M.EnsureShopRecords(state)
    local week = weekNumber()
    if state.lastShopResetWeek ~= week then
        state.shopWeekly = {}
        state.lastShopResetWeek = week
    end
end

--- 购买资源商品
---@param state table
---@param itemId string
---@return boolean success
---@return string message
function M.BuyResourceItem(state, itemId)
    local item = M.FindResourceItem(itemId)
    if not item then return false, "商品不存在" end

    -- 检查货币
    if item.currency == "yuanbao" then
        if (state.yuanbao or 0) < item.price then
            return false, "元宝不足"
        end
    elseif item.currency == "copper" then
        if (state.copper or 0) < item.price then
            return false, "铜钱不足"
        end
    end

    -- 检查每日限购
    if item.dailyLimit and item.dailyLimit > 0 then
        checkDailyReset(state)
        local bought = state.shopDaily[itemId] or 0
        if bought >= item.dailyLimit then
            return false, "今日已达购买上限"
        end
        state.shopDaily[itemId] = bought + 1
    end

    -- 扣款
    if item.currency == "yuanbao" then
        state.yuanbao = state.yuanbao - item.price
    elseif item.currency == "copper" then
        state.copper = state.copper - item.price
    end

    -- 发放奖励
    M.GrantReward(state, item.reward)
    return true, item.name .. " 购买成功"
end

--- 购买礼包
---@param state table
---@param packId string
---@return boolean success
---@return string message
function M.BuyGiftPack(state, packId)
    local pack = M.FindGiftPack(packId)
    if not pack then return false, "礼包不存在" end

    M.EnsureShopRecords(state)

    -- 检查终身限购
    if pack.totalLimit and pack.totalLimit > 0 then
        local bought = state.shopBuys[packId] or 0
        if bought >= pack.totalLimit then
            return false, "已达购买上限"
        end
    end

    -- 检查每日限购
    if pack.dailyLimit and pack.dailyLimit > 0 then
        checkDailyReset(state)
        local bought = state.shopDaily[packId] or 0
        if bought >= pack.dailyLimit then
            return false, "今日已达购买上限"
        end
    end

    -- 检查每周限购
    if pack.weeklyLimit and pack.weeklyLimit > 0 then
        checkWeeklyReset(state)
        local bought = state.shopWeekly[packId] or 0
        if bought >= pack.weeklyLimit then
            return false, "本周已达购买上限"
        end
    end

    -- 检查货币
    if pack.currency == "yuanbao" then
        if (state.yuanbao or 0) < pack.price then
            return false, "元宝不足"
        end
    end

    -- 扣款
    if pack.currency == "yuanbao" then
        state.yuanbao = state.yuanbao - pack.price
    end

    -- 更新购买计数
    state.shopBuys[packId] = (state.shopBuys[packId] or 0) + 1
    if pack.dailyLimit and pack.dailyLimit > 0 then
        state.shopDaily[packId] = (state.shopDaily[packId] or 0) + 1
    end
    if pack.weeklyLimit and pack.weeklyLimit > 0 then
        state.shopWeekly[packId] = (state.shopWeekly[packId] or 0) + 1
    end

    -- 发放奖励
    M.GrantReward(state, pack.reward)
    return true, pack.name .. " 购买成功"
end

--- 模拟充值（发放元宝）
---@param state table
---@param tierId string
---@return boolean success
---@return string message
---@return number totalYuanbao 实际获得元宝数
function M.DoRecharge(state, tierId)
    local tier = M.FindRechargeTier(tierId)
    if not tier then return false, "充值档位不存在", 0 end

    M.EnsureShopRecords(state)

    local total = tier.yuanbao
    -- 首充双倍
    if not state.rechargeFirst[tierId] then
        total = total + tier.firstBonus
        state.rechargeFirst[tierId] = true
    end

    state.yuanbao = (state.yuanbao or 0) + total
    return true, "充值成功，获得 " .. total .. " 元宝", total
end

--- 获取商城展示信息（用于客户端UI展示剩余购买次数等）
---@param state table
---@return table info
function M.GetShopInfo(state)
    M.EnsureShopRecords(state)
    checkDailyReset(state)
    checkWeeklyReset(state)
    return {
        daily   = state.shopDaily or {},
        weekly  = state.shopWeekly or {},
        total   = state.shopBuys or {},
        firstRC = state.rechargeFirst or {},
    }
end

--- 资源名称映射（用于 UI 展示奖励内容）
M.REWARD_NAMES = {
    copper     = "铜钱",
    yuanbao    = "元宝",
    stamina    = "体力",
    jianghun   = "将魂",
    zhaomuling = "招募令",
    exp_wine   = "经验酒",
}

--- 资源图标映射
M.REWARD_ICONS = {
    copper     = "Textures/icons/icon_copper.png",
    yuanbao    = "Textures/icons/icon_yuanbao.png",
    stamina    = "Textures/icons/icon_stamina.png",
    jianghun   = "Textures/icons/icon_jianghun.png",
    zhaomuling = "Textures/icons/icon_zhaomuling.png",
    exp_wine   = "Textures/icons/icon_exp_wine.png",
}

return M
