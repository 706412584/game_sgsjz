-- ============================================================================
-- 《问道长生》宗门系统数据常量
-- 宗门配置、角色权限、等级表、操作枚举
-- ============================================================================

local M = {}

-- ============================================================================
-- 种族定义（宗门种族绑定）
-- ============================================================================

--- 种族标签（中文显示名）
M.RACE_LABEL = {
    human   = "人族",
    demon   = "魔族",
    spirit  = "灵族",
    monster = "妖族",
}

--- 种族列表（用于 UI 筛选 Tab）
M.RACE_LIST = { "human", "demon", "spirit", "monster" }

--- 种族宗门加成（P3 预留，宗门等级 >= 3 生效）
M.RACE_BONUS = {
    human   = { stat = "cultivationSpeed", value = 0.05, desc = "修炼速度+5%" },
    demon   = { stat = "attack",           value = 0.05, desc = "攻击+5%" },
    spirit  = { stat = "maxHp",            value = 0.05, desc = "气血+5%" },
    monster = { stat = "speed",            value = 0.05, desc = "速度+5%" },
}

-- ============================================================================
-- 宗门创建配置
-- ============================================================================

M.CREATE_COST       = 10000   -- 创建宗门灵石费用
M.NAME_MIN_LEN      = 2      -- 宗门名最短（字符数）
M.NAME_MAX_LEN      = 8      -- 宗门名最长（字符数）
M.MAX_MEMBERS       = 50     -- P1 成员上限
M.DEFAULT_NOTICE    = "欢迎加入本宗门，同修共进！"
M.DONATE_RATE       = 10     -- 每10灵石 = 1贡献
M.DONATE_MIN        = 100    -- 最低捐献100灵石
M.DONATE_DAILY_MAX  = 10000  -- 每日最多捐献10000灵石

-- ============================================================================
-- 角色定义
-- ============================================================================

M.ROLE = {
    LEADER = "leader",   -- 宗主
    ELDER  = "elder",    -- 长老
    MEMBER = "member",   -- 普通弟子
}

M.ROLE_LABEL = {
    leader = "宗主",
    elder  = "长老",
    member = "弟子",
}

M.ROLE_COLOR = {
    leader = { 228, 193, 36, 255 },   -- 金色
    elder  = { 160, 120, 220, 255 },  -- 紫色
    member = { 180, 165, 140, 255 },  -- 灰白
}

-- 权限：谁可以执行什么操作
M.ROLE_PERMISSION = {
    approve  = { leader = true, elder = true },   -- 审批入门
    reject   = { leader = true, elder = true },
    kick     = { leader = true, elder = true },   -- 踢人（长老不能踢长老）
    transfer = { leader = true },                  -- 转让宗主
    notice   = { leader = true, elder = true },   -- 编辑公告（P2）
}

-- ============================================================================
-- 宗门等级表（P3 预留，P1 只有 1 级）
-- ============================================================================

M.LEVEL_TABLE = {
    { level = 1, name = "草创",   maxMembers = 50,  reqContribution = 0 },
    { level = 2, name = "初立",   maxMembers = 80,  reqContribution = 10000 },
    { level = 3, name = "兴盛",   maxMembers = 120, reqContribution = 50000 },
    { level = 4, name = "鼎盛",   maxMembers = 200, reqContribution = 200000 },
    { level = 5, name = "仙门",   maxMembers = 500, reqContribution = 1000000 },
}

--- 获取等级信息
---@param level number
---@return table
function M.GetLevelInfo(level)
    return M.LEVEL_TABLE[math.max(1, math.min(level or 1, #M.LEVEL_TABLE))]
end

-- ============================================================================
-- 宗门贡献产出配置（各操作产出贡献值）
-- ============================================================================

M.CONTRIBUTION_YIELDS = {
    explore_victory = 5,      -- 探索战斗胜利
    alchemy_craft   = 3,      -- 炼丹一次
    advance_sub     = 20,     -- 小境界突破
    tribulation     = 100,    -- 渡劫成功
    dao_meditate    = 2,      -- 悟道一次
    boss_kill       = 30,     -- 世界Boss参与
    recharge        = 50,     -- 充值完成
    trial_win       = 10,     -- 试炼挑战（排位）
}

--- 种族加成按宗门等级缩放（等级 >= 3 时生效）
M.RACE_BONUS_SCALE = {
    [3] = 1.0,   -- +5%  (基础值)
    [4] = 1.6,   -- +8%  (基础值×1.6)
    [5] = 2.4,   -- +12% (基础值×2.4)
}

--- 获取宗门种族加成（考虑等级）
---@param race string
---@param sectLevel number
---@return table|nil  { stat, value, desc }
function M.GetRaceBonus(race, sectLevel)
    local level = sectLevel or 1
    if level < 3 then return nil end
    local base = M.RACE_BONUS[race]
    if not base then return nil end
    local scale = M.RACE_BONUS_SCALE[level] or M.RACE_BONUS_SCALE[5]
    return {
        stat  = base.stat,
        value = base.value * scale,
        desc  = base.desc,
    }
end

-- ============================================================================
-- 宗门任务配置（每日任务池，每日随机分配 3 个）
-- ============================================================================

M.SECT_TASK_POOL = {
    { id = "explore_3",    name = "探索历练",   desc = "完成3次探索战斗",     action = "explore_settle",      target = 3,  reward = 15 },
    { id = "alchemy_2",    name = "炼丹修行",   desc = "炼丹2次",            action = "alchemy_craft",       target = 2,  reward = 10 },
    { id = "dao_3",        name = "悟道参悟",   desc = "悟道3次",            action = "dao_meditate",        target = 3,  reward = 10 },
    { id = "trial_1",      name = "试炼挑战",   desc = "完成1次试炼挑战",     action = "trial_challenge",     target = 1,  reward = 20 },
    { id = "boss_1",       name = "降妖除魔",   desc = "参与1次世界Boss",     action = "boss_settle",         target = 1,  reward = 25 },
    { id = "donate_500",   name = "慷慨解囊",   desc = "捐献500灵石",        action = "donate",              target = 500, reward = 15 },
    { id = "advance_1",    name = "突破境界",   desc = "完成1次小境界突破",    action = "advance_sub",         target = 1,  reward = 30 },
    { id = "explore_5",    name = "连续征伐",   desc = "完成5次探索战斗",     action = "explore_settle",      target = 5,  reward = 25 },
}

M.DAILY_TASK_COUNT = 3     -- 每日分配任务数
M.TASK_BONUS_ALL   = 20    -- 全部完成额外奖励贡献

-- ============================================================================
-- 每周贡献分配配置
-- ============================================================================

--- 每周贡献排名奖励（按排名发放灵石）
M.WEEKLY_REWARDS = {
    { rank = 1,  lingStone = 2000, xianStone = 5, label = "第1名" },
    { rank = 2,  lingStone = 1500, xianStone = 3, label = "第2名" },
    { rank = 3,  lingStone = 1000, xianStone = 1, label = "第3名" },
    { rank = 4,  lingStone = 500,  xianStone = 0, label = "第4-10名" },
    { rank = 10, lingStone = 500,  xianStone = 0, label = "第4-10名" },
}

--- 获取某排名的奖励
---@param rank number 1-based
---@return table|nil { lingStone, xianStone, label }
function M.GetWeeklyReward(rank)
    if rank == 1 then return M.WEEKLY_REWARDS[1] end
    if rank == 2 then return M.WEEKLY_REWARDS[2] end
    if rank == 3 then return M.WEEKLY_REWARDS[3] end
    if rank >= 4 and rank <= 10 then return M.WEEKLY_REWARDS[4] end
    return nil
end

-- ============================================================================
-- 宗门宝库商品配置（用贡献兑换）
-- ============================================================================

--- 商品类型
M.SHOP_ITEM_TYPE = {
    PILL      = "pill",       -- 丹药（写入 pills 独立 key）
    BAG_ITEM  = "bag_item",   -- 背包物品（写入 bagItems）
    CURRENCY  = "currency",   -- 货币（灵石/仙石，走 money:Add）
}

--- 宗门宝库商品列表
--- reqLevel: 宗门等级要求（nil 或 1 表示无限制）
--- dailyLimit: 每日个人购买上限（nil 表示无限制）
M.SECT_SHOP_ITEMS = {
    {
        id = "shop_peiyuan",  name = "培元丹x5",
        type = "pill",   pillId = "peiyuan", count = 5,
        cost = 30,  reqLevel = 1,  dailyLimit = 3,
        desc = "恢复修为，修炼必备",
    },
    {
        id = "shop_huiqi",  name = "回气丹x5",
        type = "pill",   pillId = "huiqi", count = 5,
        cost = 30,  reqLevel = 1,  dailyLimit = 3,
        desc = "恢复灵力，战斗续航",
    },
    {
        id = "shop_ningshen",  name = "凝神丹x3",
        type = "pill",   pillId = "ningshen", count = 3,
        cost = 50,  reqLevel = 2,  dailyLimit = 2,
        desc = "提升神识，领悟功法",
    },
    {
        id = "shop_tongmai",  name = "通脉丹x2",
        type = "pill",   pillId = "tongmai", count = 2,
        cost = 80,  reqLevel = 2,  dailyLimit = 2,
        desc = "疏通经脉，加速突破",
    },
    {
        id = "shop_lingcao",  name = "灵草x10",
        type = "bag_item",   itemName = "灵草", count = 10,
        cost = 20,  reqLevel = 1,  dailyLimit = 5,
        desc = "炼丹基础材料",
    },
    {
        id = "shop_kuangshi",  name = "矿石x10",
        type = "bag_item",   itemName = "矿石", count = 10,
        cost = 20,  reqLevel = 1,  dailyLimit = 5,
        desc = "炼器基础材料",
    },
    {
        id = "shop_lingstone",  name = "灵石x500",
        type = "currency",   currency = "lingStone", count = 500,
        cost = 60,  reqLevel = 1,  dailyLimit = 3,
        desc = "通用货币",
    },
    {
        id = "shop_xianstone",  name = "仙石x1",
        type = "currency",   currency = "xianStone", count = 1,
        cost = 200,  reqLevel = 3,  dailyLimit = 1,
        desc = "稀有货币",
    },
}

--- 根据 id 查找商品
---@param itemId string
---@return table|nil
function M.GetShopItem(itemId)
    for _, item in ipairs(M.SECT_SHOP_ITEMS) do
        if item.id == itemId then return item end
    end
    return nil
end

-- ============================================================================
-- 宗门秘境配置
-- ============================================================================

--- 秘境难度（每日可挑战次数、贡献消耗、怪物缩放、奖励缩放）
M.REALM_DIFFICULTIES = {
    {
        id = "easy",   name = "外围",
        cost = 10,     dailyLimit = 5,  reqLevel = 1,
        floors = 3,    -- 闯关层数
        enemyScale = 0.6,  rewardScale = 0.6,
        desc = "秘境外围，妖兽较弱，适合初入宗门的弟子",
    },
    {
        id = "normal", name = "内域",
        cost = 25,     dailyLimit = 3,  reqLevel = 1,
        floors = 5,
        enemyScale = 1.0,  rewardScale = 1.0,
        desc = "秘境内域，危机四伏，需有一定修为",
    },
    {
        id = "hard",   name = "核心",
        cost = 50,     dailyLimit = 2,  reqLevel = 2,
        floors = 7,
        enemyScale = 1.6,  rewardScale = 1.8,
        desc = "秘境核心区域，强敌环伺，奖励丰厚",
    },
}

--- 秘境怪物名称池
M.REALM_MONSTERS = {
    "幽冥蛛", "岩甲兽", "赤焰蝠", "寒冰蟒", "雷翼雕",
    "噬魂蚁后", "碧眼狼王", "玄铁犀", "血瞳鬼猿", "紫雾妖狐",
}

--- 秘境每层怪物属性（基础值，乘以 enemyScale + 层数递增）
M.REALM_ENEMY_BASE = {
    attack  = 20,
    defense = 10,
    hp      = 100,
    hit     = 85,
    dodge   = 5,
    crit    = 5,
}

--- 秘境每层递增
M.REALM_FLOOR_GROWTH = {
    attack  = 8,
    defense = 4,
    hp      = 60,
    dodge   = 1,
    crit    = 1,
}

--- 秘境奖励配置（每通关一层的基础奖励）
M.REALM_REWARD_PER_FLOOR = {
    lingStone    = 50,       -- 灵石/层
    contribution = 5,        -- 贡献/层
}

--- 秘境通关额外奖励（全部通关的额外奖励概率表）
M.REALM_CLEAR_BONUS = {
    { type = "pill",     pillId = "peiyuan",  count = 2, chance = 80, name = "培元丹x2" },
    { type = "pill",     pillId = "huiqi",    count = 2, chance = 80, name = "回气丹x2" },
    { type = "pill",     pillId = "ningshen", count = 1, chance = 30, name = "凝神丹x1" },
    { type = "bag_item", itemName = "灵草",    count = 5, chance = 50, name = "灵草x5" },
    { type = "bag_item", itemName = "矿石",    count = 5, chance = 50, name = "矿石x5" },
}

--- 查找秘境难度配置
---@param diffId string
---@return table|nil
function M.GetRealmDifficulty(diffId)
    for _, d in ipairs(M.REALM_DIFFICULTIES) do
        if d.id == diffId then return d end
    end
    return nil
end

-- ============================================================================
-- 散修联盟（虚拟宗门，不存储）
-- ============================================================================

M.FREELANCER = {
    id   = "",
    name = "散修联盟",
    desc = "四海为家，独自修行。加入宗门可获得更多修炼资源与同道扶持。",
}

-- ============================================================================
-- 操作枚举（客户端 -> 服务端 Action 字段）
-- ============================================================================

M.ACTION = {
    GET_INFO     = "get_info",      -- 获取当前宗门信息+成员
    BROWSE       = "browse",        -- 浏览宗门列表
    CREATE       = "create",        -- 创建宗门
    APPLY        = "apply",         -- 申请加入
    CANCEL_APPLY = "cancel_apply",  -- 取消申请
    GET_PENDING  = "get_pending",   -- 获取待审批列表
    APPROVE      = "approve",       -- 批准入门
    REJECT       = "reject",        -- 拒绝申请
    LEAVE        = "leave",         -- 退出宗门
    KICK         = "kick",          -- 踢出成员
    TRANSFER     = "transfer",      -- 转让宗主
    EDIT_NOTICE  = "edit_notice",   -- 编辑公告
    UPGRADE      = "upgrade",       -- 升级宗门（宗主）
    DONATE       = "donate",        -- 捐献灵石换贡献
    GET_TASKS    = "get_tasks",     -- 获取今日宗门任务
    CLAIM_TASK   = "claim_task",    -- 领取单个任务奖励
    CLAIM_ALL    = "claim_all",     -- 领取全部完成额外奖励
    SHOP_BUY     = "shop_buy",     -- 宗门宝库购买
    REALM_ENTER  = "realm_enter",  -- 进入宗门秘境
}

-- ============================================================================
-- 回复类型枚举（服务端 -> 客户端 Action 字段）
-- ============================================================================

M.RESP_ACTION = {
    SECT_INFO    = "sect_info",     -- 宗门信息 + 成员列表
    BROWSE_LIST  = "browse_list",   -- 宗门列表
    PENDING_LIST = "pending_list",  -- 待审批列表
    RESULT       = "result",        -- 通用操作结果
    TASK_LIST    = "task_list",     -- 宗门任务列表
    REALM_RESULT = "realm_result",  -- 秘境挑战结果
}

return M
