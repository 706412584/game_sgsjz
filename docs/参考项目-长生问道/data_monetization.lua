-- ============================================================================
-- 《问道长生》变现体系配置常量
-- 数据来源: docs/design-v2-cultivation-combat.md 十~十八章
-- ============================================================================

local M = {}

-- ============================================================================
-- 10. 货币体系
-- ============================================================================

-- 货币 key 常量
M.CURRENCY = {
    LING_STONE   = "lingStone",    -- 灵石（基础货币）
    SPIRIT_STONE = "spiritStone",  -- 仙石（付费货币）
    XIAN_YUAN    = "xianYuan",     -- 仙缘（绑定货币）
}

-- ============================================================================
-- 11. 充值档位
-- ============================================================================

M.RECHARGE_TIERS = {
    { id = "r6",   price = 6,   stones = 60,   firstDouble = true, bonusXY = 10,   label = "小试仙缘" },
    { id = "r12",  price = 12,  stones = 130,  firstDouble = true, bonusXY = 25,   label = "初入仙途" },
    { id = "r30",  price = 30,  stones = 350,  firstDouble = true, bonusXY = 70,   label = "仙缘初聚" },
    { id = "r68",  price = 68,  stones = 850,  firstDouble = true, bonusXY = 180,  label = "仙途渐远" },
    { id = "r128", price = 128, stones = 1700, firstDouble = true, bonusXY = 400,  label = "问道之路" },
    { id = "r328", price = 328, stones = 4600, firstDouble = true, bonusXY = 1200, label = "登仙之基" },
    { id = "r648", price = 648, stones = 9800, firstDouble = true, bonusXY = 2800, label = "仙道无极" },
}

-- ============================================================================
-- 11.2 广告配置
-- ============================================================================

M.AD_CONFIG = {
    globalCooldownSec = 60,    -- 全局冷却 60 秒
    maxPerHour        = 8,     -- 每小时最多 8 个
    maxPerDay         = 25,    -- 每日最多 25 个
    minSessionTimeSec = 180,   -- 进入游戏至少 3 分钟后才出现
}

-- 广告场景定义
M.AD_SCENES = {
    {
        id       = "signin_double",
        label    = "签到加倍",
        reward   = { spiritStone = 5, xianYuan = 10 },
        maxDaily = 1,
    },
    {
        id       = "cultivate_boost",
        label    = "修炼加速",
        desc     = "2倍速度30分钟",
        reward   = { spiritStone = 3 },
        maxDaily = 3,
    },
    {
        id       = "explore_double",
        label    = "探索双倍",
        desc     = "本次奖励翻倍",
        reward   = { spiritStone = 2 },
        maxDaily = 5,
    },
    {
        id       = "free_gacha",
        label    = "免费抽奖",
        desc     = "1次标准池",
        maxDaily = 2,
    },
    {
        id       = "revive",
        label    = "续战复活",
        desc     = "回满血续战",
        maxDaily = 3,
    },
    {
        id       = "offline_double",
        label    = "离线收益加倍",
        desc     = "离线修为翻倍",
        maxDaily = 1,
    },
    {
        id       = "alchemy_boost",
        label    = "炼丹成功率提升",
        desc     = "本次+15%",
        maxDaily = 3,
    },
    {
        id       = "enhance_protect",
        label    = "强化保护",
        desc     = "失败不掉级",
        maxDaily = 3,
    },
}

-- 广告场景索引 (id -> config)
M.AD_SCENE_MAP = {}
for _, sc in ipairs(M.AD_SCENES) do
    M.AD_SCENE_MAP[sc.id] = sc
end

-- ============================================================================
-- 12. 月卡配置
-- ============================================================================

M.MONTH_CARDS = {
    basic = {
        id            = "basic",
        label         = "道友月卡",
        price         = 30,
        instantStones = 300,
        instantXY     = 100,
        dailyStones   = 50,
        dailyXY       = 10,
        durationDays  = 30,
        privileges    = { "仙石交易权限", "坊市手续费减半(2.5%)" },
    },
    premium = {
        id            = "premium",
        label         = "仙友月卡",
        price         = 68,
        instantStones = 680,
        instantXY     = 300,
        dailyStones   = 100,
        dailyXY       = 30,
        durationDays  = 30,
        privileges    = { "道友全部特权", "每日免费抽奖1次", "修炼+10%", "背包+40格" },
    },
}

-- ============================================================================
-- 13. 通行证（赛季）
-- ============================================================================

M.BATTLE_PASS = {
    maxLevel     = 50,
    expPerLevel  = 100,
    premiumPrice = 68,     -- RMB
    seasonDays   = 45,

    -- 经验来源
    expSources = {
        dailyLogin     = 30,
        dailyQuest     = 50,
        exploreWin     = 5,
        weeklyQuest    = 100,
        breakthrough   = 200,
    },
}

-- 通行证奖励表 (等级 -> { free, paid })
M.BATTLE_PASS_REWARDS = {
    [5]  = { free = { lingStone = 200 },                        paid = { spiritStone = 50,  lingDust = 20 } },
    [10] = { free = { lingStone = 500 },                        paid = { spiritStone = 80,  item = "洗灵丹", itemCount = 1 } },
    [15] = { free = { lingStone = 800 },                        paid = { spiritStone = 60,  lingStone = 1000 } },
    [20] = { free = { lingStone = 1000 },                       paid = { spiritStone = 100, item = "灵兽精血", itemCount = 5 } },
    [25] = { free = { lingStone = 1500 },                       paid = { spiritStone = 80,  lingStone = 2000 } },
    [30] = { free = { lingStone = 2000 },                       paid = { spiritStone = 120, item = "高级宝箱", itemCount = 1 } },
    [35] = { free = { lingStone = 2500 },                       paid = { spiritStone = 100, lingStone = 3000 } },
    [40] = { free = { lingStone = 3000 },                       paid = { spiritStone = 150, title = "赛季征途" } },
    [45] = { free = { lingStone = 4000 },                       paid = { spiritStone = 200, lingStone = 5000 } },
    [50] = { free = { lingStone = 5000 },                       paid = { spiritStone = 300, title = "赛季之巅", frame = true } },
}

-- 里程碑等级集合（快速判定）
M.BATTLE_PASS_MILESTONE = {}
for lv in pairs(M.BATTLE_PASS_REWARDS) do
    M.BATTLE_PASS_MILESTONE[lv] = true
end

--- 获取任意等级的通行证奖励（里程碑用预定义，其余自动生成）
---@param lv number 等级 1~maxLevel
---@return table|nil { free, paid }
function M.GetBattlePassReward(lv)
    if lv < 1 or lv > M.BATTLE_PASS.maxLevel then return nil end
    -- 里程碑等级：使用预定义奖励
    if M.BATTLE_PASS_REWARDS[lv] then
        return M.BATTLE_PASS_REWARDS[lv]
    end
    -- 非里程碑等级：自动生成小奖励（随等级递增）
    local lingStone = math.floor((30 + lv * 40) / 50) * 50  -- 50步进，lv1=50 lv49=3950
    local spiritStone = 5 + math.floor(lv / 10) * 5          -- 5~25
    return {
        free = { lingStone = lingStone },
        paid = { spiritStone = spiritStone },
    }
end

-- 等级列表：1~50 全部有奖励
M.BATTLE_PASS_LEVELS = {}
for lv = 1, M.BATTLE_PASS.maxLevel do
    M.BATTLE_PASS_LEVELS[lv] = lv
end

-- ============================================================================
-- 14. 抽奖/开箱
-- ============================================================================

M.GACHA = {
    singleCost = 50,       -- 单抽仙石
    tenCost    = 450,      -- 十连仙石（9折）
    softPity   = 50,       -- 50抽保底仙器以上
    hardPity   = 100,      -- 100抽大保底神器以上
}

-- 标准池概率
M.GACHA_RATES = {
    { quality = "xtshenqi",  rate = 0.003, label = "先天神器" },
    { quality = "shenqi",    rate = 0.007, label = "神器" },
    { quality = "xtxianqi",  rate = 0.020, label = "先天仙器" },
    { quality = "xianqi",    rate = 0.050, label = "仙器" },
    { quality = "diqi",      rate = 0.120, label = "帝器" },
    { quality = "huangqi",   rate = 0.200, label = "皇器" },
    { quality = "xtlingbao", rate = 0.250, label = "先天灵宝" },
    { quality = "lingbao",   rate = 0.200, label = "灵宝" },
    { quality = "material",  rate = 0.147, label = "材料/丹药" },
    { quality = "lingshi",   rate = 0.003, label = "灵石x5000" },
}

-- ============================================================================
-- 15. 礼包
-- ============================================================================

-- 15.1 新手礼包（创角后7天限购1次）
M.NEWBIE_GIFTS = {
    {
        id       = "newbie_d1",
        day      = 1,
        label    = "新手礼包(第1天)",
        price    = 6,
        content  = { spiritStone = 100, item = "培元丹", itemCount = 10, lingStone = 2000 },
    },
    {
        id       = "newbie_d3",
        day      = 3,
        label    = "新手礼包(第3天)",
        price    = 12,
        content  = { spiritStone = 200, item = "宝箱钥匙", itemCount = 2, lingDust = 50 },
    },
    {
        id       = "newbie_d7",
        day      = 7,
        label    = "新手礼包(第7天)",
        price    = 30,
        content  = { spiritStone = 500, item = "洗灵丹", itemCount = 1, item2 = "天材地宝", item2Count = 3 },
    },
}

-- 15.2 境界突破礼包（每种仅限购1次）
M.BREAKTHROUGH_GIFTS = {
    { id = "bt_zhuji",  realm = "筑基", tier = 2, price = 12,  content = { spiritStone = 100, item = "筑基丹",        itemCount = 2, lingStone = 3000 } },
    { id = "bt_jindan", realm = "金丹", tier = 4, price = 30,  content = { spiritStone = 200, item = "破劫丹",        itemCount = 1, lingStone = 5000 } },
    { id = "bt_yuanying",realm= "元婴", tier = 5, price = 68,  content = { spiritStone = 300, item = "洗灵丹",        itemCount = 1, item2 = "宝箱钥匙", item2Count = 3 } },
    { id = "bt_huashen", realm= "化神", tier = 6, price = 128, content = { spiritStone = 500, item = "天品武学选择箱", itemCount = 1, lingStone = 20000 } },
    { id = "bt_dujie",  realm = "渡劫", tier = 8, price = 328, content = { spiritStone = 800, item = "先天仙器选择箱", itemCount = 1, lingStone = 50000 } },
}

-- 15.3 每周特惠（仙石购买，每周刷新）
M.WEEKLY_DEALS = {
    { id = "weekly_mon", weekday = 1, label = "周一灵石包", cost = 30,  currency = "spiritStone", content = { lingStone = 5000 } },
    { id = "weekly_wed", weekday = 3, label = "周三材料包", cost = 50,  currency = "spiritStone", content = { item = "天元精魄", itemCount = 5, item2 = "灵兽精血", item2Count = 5 } },
    { id = "weekly_fri", weekday = 5, label = "周五强化包", cost = 40,  currency = "spiritStone", content = { lingDust = 100, lingStone = 3000 } },
    { id = "weekly_end", weekday = 6, label = "周末大礼包", cost = 68,  currency = "rmb",         content = { item = "宝箱钥匙", itemCount = 1, spiritStone = 50 } },
}

-- ============================================================================
-- 15.4 每日签到
-- ============================================================================

M.SIGNIN_REWARDS = {
    { day = 1, free = { lingStone = 100 },              ad = { lingStone = 200, spiritStone = 5, xianYuan = 10 } },
    { day = 2, free = { item = "培元丹", count = 3 },   ad = { item = "培元丹", count = 6, spiritStone = 5, xianYuan = 10 } },
    { day = 3, free = { lingStone = 200 },              ad = { lingStone = 400, spiritStone = 5, xianYuan = 10 } },
    { day = 4, free = { item = "灵草", count = 5 },     ad = { item = "灵草", count = 10, spiritStone = 5, xianYuan = 10 } },
    { day = 5, free = { lingStone = 300 },              ad = { lingStone = 600, spiritStone = 5, xianYuan = 10 } },
    { day = 6, free = { item = "凝神丹", count = 2 },   ad = { item = "凝神丹", count = 4, spiritStone = 5, xianYuan = 10 } },
    { day = 7, free = { item = "宝箱钥匙", count = 1 }, ad = { item = "宝箱钥匙", count = 1, spiritStone = 10, xianYuan = 20 } },
}

-- ============================================================================
-- 16. VIP 等级
-- ============================================================================

M.VIP_LEVELS = {
    { level = 0,  charge = 0,     dailyLingshi = 0,    privileges = {} },
    { level = 1,  charge = 6,     dailyLingshi = 0,    privileges = { "自动拾取", "快速炼丹" } },
    { level = 2,  charge = 30,    dailyLingshi = 200,  privileges = { "VIP1特权", "每日领取灵石" } },
    { level = 3,  charge = 98,    dailyLingshi = 500,  privileges = { "VIP2特权", "探索扫荡" } },
    { level = 4,  charge = 198,   dailyLingshi = 800,  privileges = { "VIP3特权", "炼丹成功率+5%" } },
    { level = 5,  charge = 388,   dailyLingshi = 1200, privileges = { "VIP4特权", "强化成功率+3%" } },
    { level = 6,  charge = 648,   dailyLingshi = 1500, privileges = { "VIP5特权", "背包+30格" } },
    { level = 7,  charge = 1288,  dailyLingshi = 2000, privileges = { "VIP6特权", "坊市手续费-3%" } },
    { level = 8,  charge = 2888,  dailyLingshi = 3000, privileges = { "VIP7特权", "抽奖保底减10抽" } },
    { level = 9,  charge = 6888,  dailyLingshi = 5000, privileges = { "VIP8特权", "称号:问道仙尊" } },
    { level = 10, charge = 12888, dailyLingshi = 8000, privileges = { "VIP9特权", "限定头像框" } },
}

--- 根据累计充值金额计算 VIP 等级
---@param totalCharged number 累计充值(RMB)
---@return number level
function M.CalcVipLevel(totalCharged)
    local lv = 0
    for _, v in ipairs(M.VIP_LEVELS) do
        if totalCharged >= v.charge then
            lv = v.level
        else
            break
        end
    end
    return lv
end

--- 获取 VIP 等级配置
---@param level number
---@return table|nil
function M.GetVipConfig(level)
    for _, v in ipairs(M.VIP_LEVELS) do
        if v.level == level then return v end
    end
    return nil
end

--- 获取下一 VIP 等级需要的充值金额
---@param currentLevel number
---@return number|nil
function M.GetNextVipCharge(currentLevel)
    for _, v in ipairs(M.VIP_LEVELS) do
        if v.level == currentLevel + 1 then
            return v.charge
        end
    end
    return nil
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 格式化礼包内容为可读字符串
---@param content table
---@return string
function M.FormatGiftContent(content)
    local parts = {}
    if content.spiritStone then
        parts[#parts + 1] = "仙石x" .. content.spiritStone
    end
    if content.xianYuan then
        parts[#parts + 1] = "仙缘x" .. content.xianYuan
    end
    if content.lingStone then
        parts[#parts + 1] = "灵石x" .. content.lingStone
    end
    if content.lingDust then
        parts[#parts + 1] = "灵尘x" .. content.lingDust
    end
    if content.item then
        local cnt = content.itemCount or content.count or 1
        parts[#parts + 1] = content.item .. "x" .. cnt
    end
    if content.item2 then
        local cnt = content.item2Count or 1
        parts[#parts + 1] = content.item2 .. "x" .. cnt
    end
    return table.concat(parts, " + ")
end

--- 获取签到奖励（按累计天数，7天循环）
---@param totalDays number 累计签到天数（从0开始，下一次签到后 +1）
---@return table reward { day, free, ad }
function M.GetSigninReward(totalDays)
    local dayInCycle = (totalDays % 7) + 1  -- 1~7
    for _, r in ipairs(M.SIGNIN_REWARDS) do
        if r.day == dayInCycle then return r end
    end
    return M.SIGNIN_REWARDS[1]
end

return M
