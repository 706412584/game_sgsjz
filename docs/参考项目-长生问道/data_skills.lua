-- ============================================================================
-- 《问道长生》功法 & 悟道数据配置
-- 数据来源: docs/game-design-values.md §6, §14
-- ============================================================================

local M = {}

-- ============================================================================
-- 6.1 功法列表
-- ============================================================================
-- type: 基础/防御/身法/攻击
-- effect: 主效果描述
-- unlock: 解锁条件描述
-- unlockPrice/unlockCurrency: 坊市购买价格(nil=初始拥有)
-- ============================================================================
M.SKILLS = {
    { id = "tuna",     name = "吐纳术", type = "基础", maxLevel = 10, effect = "修炼速度+15%",      unlock = "初始",   unlockPrice = nil,  unlockCurrency = nil,
      combatEffect = { type = "heal", value = 0.05, trigger = "every_5", cooldown = 5, desc = "吐纳回气，回复气血" } },
    { id = "jingang",  name = "金刚诀", type = "防御", maxLevel = 10, effect = "防御+20",            unlock = "初始",   unlockPrice = nil,  unlockCurrency = nil,
      combatEffect = { type = "shield", value = 0.25, trigger = "hp_low", cooldown = 4, desc = "金刚护体，减伤" } },
    { id = "yufeng",   name = "御风术", type = "身法", maxLevel = 10, effect = "速度+15, 闪避+2%",   unlock = "初始",   unlockPrice = nil,  unlockCurrency = nil,
      combatEffect = { type = "buff", value = 0.20, buffStat = "dodge", trigger = "every_4", duration = 2, cooldown = 4, desc = "御风身法，闪避提升" } },
    { id = "lieyan",   name = "烈焰掌", type = "攻击", maxLevel = 10, effect = "攻击+30",            unlock = "坊市购买", unlockPrice = 400,  unlockCurrency = "灵石",
      combatEffect = { type = "damage", value = 0.35, trigger = "every_3", cooldown = 3, desc = "烈焰掌力，伤害暴增" } },
    { id = "bingxin",  name = "冰心诀", type = "基础", maxLevel = 10, effect = "修炼速度+20%",       unlock = "坊市购买", unlockPrice = 800,  unlockCurrency = "灵石",
      combatEffect = { type = "damage", value = 0.25, trigger = "every_4", cooldown = 4, desc = "冰心诀意，冻伤敌方" } },
}

-- ============================================================================
-- 6.2 功法升级表
-- ============================================================================
-- time: 修炼时间描述
-- timeSec: 修炼时间(秒)
-- wisdomReq: 悟性需求
-- multiplier: 效果倍率
-- ============================================================================
M.SKILL_LEVELS = {
    { level = 1,  timeSec = 0,      wisdomReq = 0,   multiplier = 1.0 },
    { level = 2,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.2 },
    { level = 3,  timeSec = 1800,   wisdomReq = 50,  multiplier = 1.2 },
    { level = 4,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 5,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 6,  timeSec = 7200,   wisdomReq = 70,  multiplier = 1.5 },
    { level = 7,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 8,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 9,  timeSec = 28800,  wisdomReq = 90,  multiplier = 2.0 },
    { level = 10, timeSec = 86400,  wisdomReq = 120, multiplier = 3.0 },
}

-- ============================================================================
-- 14. 悟道列表
-- ============================================================================
-- maxProgress: 满进度
-- reward: 奖励描述
-- unlockTier: 需要的最低境界阶数(nil=初始)
-- ============================================================================
M.DAO_INSIGHTS = {
    { id = "tiandao", name = "天道感悟", desc = "感悟天道运行之理，领悟阴阳相生之道。",           maxProgress = 100, reward = "全属性+5, 道心+15",        unlockTier = nil },
    { id = "wuxing",  name = "五行之道", desc = "参悟金木水火土五行相克之法，调和自身元气。",     maxProgress = 100, reward = "功法效果+10, 道心+10",     unlockTier = nil },
    { id = "jianyi",  name = "剑意初悟", desc = "以剑为道，心剑合一，感受剑意的锋芒与纯粹。",   maxProgress = 100, reward = "攻击+20, 暴击+5, 道心+12", unlockTier = 4 },
}

-- ============================================================================
-- 14.1 悟道系统配置
-- ============================================================================
-- FREE_MEDITATE_DAILY : 每日免费参悟次数（不消耗修为）
-- EXPLORE_DAO_CHANCE  : 历练战斗胜利获得道心的概率(%)
-- EXPLORE_DAO_RANGE   : 历练获得道心数量范围 {min, max}
-- ============================================================================
M.FREE_MEDITATE_DAILY = 5

M.EXPLORE_DAO_CHANCE = 30   -- 30% 概率
M.EXPLORE_DAO_RANGE  = { 1, 3 }

--- 根据境界计算每日道心获取上限
--- 设计思路：每个境界小境界突破需要一定道心，按一周左右能攒够来控制日上限
--- 例：炼气 daoHeartReq = {10,15,20}，合计 45 道心，日上限约 45/7 ≈ 7
---@param tier number 当前大境界阶数
---@return number
function M.GetDailyDaoHeartCap(tier)
    -- 每个 tier 的合理日上限（递增，保证高境界不会太快也不会太慢）
    local caps = {
        8,    -- tier 1 炼气: req 10+15+20=45, ~6天
        12,   -- tier 2 聚灵: req 30+40+50=120, ~10天
        16,   -- tier 3 筑基: req 60+70+80=210, ~13天
        22,   -- tier 4 金丹: req 100+120+140=360, ~16天
        30,   -- tier 5 元婴: req 170+220+280=670, ~22天
        40,   -- tier 6 化神: req 350+450+560=1360, ~34天
        55,   -- tier 7 返虚: req 700+900+1100=2700, ~49天
        70,   -- tier 8 合道: req 1400+1700+2000=5100, ~73天
        90,   -- tier 9 大乘: req 2500+3000+3600=9100, ~101天
        120,  -- tier 10 渡劫: req 4500+5500+6800=16800, ~140天
    }
    if tier >= 1 and tier <= 10 then return caps[tier] end
    -- 仙人期：线性递增
    return 120 + (tier - 10) * 15
end

-- ============================================================================
-- 14.2 道心试炼配置
-- ============================================================================
-- 两种道心试炼，都在角色-试炼页中展示
-- type: "心魔" / "红尘"
-- 心魔挑战：与内心心魔战斗，属性按玩家比例缩放，胜利获得道心
-- 红尘历练：回答选择题（随机场景），根据选择获得不同道心
-- ============================================================================
M.DAO_TRIALS = {
    {
        id = "xinmo",
        name = "心魔挑战",
        type = "心魔",
        desc = "直面内心心魔，以道心磨砺意志。战胜心魔可获得大量道心。",
        unlockTier = 1,
        dailyLimit = 2,
        -- 心魔属性 = 玩家属性 × scale，越高境界 scale 越大（服务端计算）
        baseReward = 3,   -- 基础道心奖励
        bonusPerTier = 1, -- 每个 tier 额外道心
    },
    {
        id = "hongchen",
        name = "红尘历练",
        type = "红尘",
        desc = "入红尘体验人间百态，在纷扰中坚守本心。每次历练随机遭遇不同场景。",
        unlockTier = 1,
        dailyLimit = 3,
        baseReward = 2,
        bonusPerTier = 1,
    },
}

--- 红尘历练场景池
--- 每个场景有多个选项，不同选项给予不同道心奖励
M.HONGCHEN_SCENES = {
    {
        id = "hc_beggar",
        desc = "路遇一名衣衫褴褛的乞丐倒在路旁，面色苍白，气息微弱。",
        options = {
            { text = "施以灵丹救治", daoHeart = 3, msg = "你救下乞丐，其感激涕零。善念温暖道心。" },
            { text = "留下干粮离去", daoHeart = 2, msg = "你默默留下食物。虽未停留，道心亦有所得。" },
            { text = "视而不见", daoHeart = 0, msg = "你从旁走过。红尘中无动于衷，道心未有触动。" },
        },
    },
    {
        id = "hc_treasure",
        desc = "前方路上散落着一只锦囊，隐约散发灵气，四周无人。",
        options = {
            { text = "原地等候失主", daoHeart = 3, msg = "失主归来，感激不尽。你心如明镜，道心坚固。" },
            { text = "交给附近村长", daoHeart = 2, msg = "你将锦囊交予长者。行事坦荡，道心略有增长。" },
            { text = "收入囊中", daoHeart = 0, msg = "你将锦囊收下。贪念虽小，道心未有增益。" },
        },
    },
    {
        id = "hc_dispute",
        desc = "两位商贩为一件灵器的归属争吵不休，引来围观。",
        options = {
            { text = "公正调解", daoHeart = 3, msg = "你明察秋毫，化解纷争。公正之心磨砺道心。" },
            { text = "劝双方各退一步", daoHeart = 2, msg = "你以和为贵，平息争端。圆融处世，道心有益。" },
            { text = "围观看热闹", daoHeart = 0, msg = "你驻足旁观。事不关己，道心未有波澜。" },
        },
    },
    {
        id = "hc_child",
        desc = "一个孩童在山路上迷路哭泣，天色渐暗。",
        options = {
            { text = "护送回家", daoHeart = 3, msg = "你亲自送孩童归家。仁心善举，道心温润。" },
            { text = "指明方向", daoHeart = 2, msg = "你为孩童指点迷津。举手之劳，道心微增。" },
            { text = "匆匆走过", daoHeart = 0, msg = "你加快脚步离去。道心未有触动。" },
        },
    },
    {
        id = "hc_demon",
        desc = "一只受伤的妖兽蜷缩在路边，眼中带着恐惧与请求。",
        options = {
            { text = "疗伤放归", daoHeart = 3, msg = "妖兽感恩离去。万物有灵，慈悲之心坚固道心。" },
            { text = "留些食物", daoHeart = 2, msg = "你留下食物便走。一念之善，道心有感。" },
            { text = "警惕绕行", daoHeart = 1, msg = "你谨慎绕开。虽无善举，但保全自身也是一种道。" },
        },
    },
    {
        id = "hc_old_monk",
        desc = "一位老僧在古寺前打坐，见你路过，邀你品茶论道。",
        options = {
            { text = "静心论道", daoHeart = 3, msg = "你与老僧谈玄论妙，心境豁然开朗。道心大增。" },
            { text = "饮茶闲聊", daoHeart = 2, msg = "你品茗闲谈，心中宁静。道心有所感悟。" },
            { text = "婉拒离去", daoHeart = 1, msg = "你礼貌告辞。虽错过机缘，但守时也是修行。" },
        },
    },
}

--- 获取道心试炼配置
---@param id string
---@return table|nil
function M.GetDaoTrial(id)
    for _, t in ipairs(M.DAO_TRIALS) do
        if t.id == id then return t end
    end
    return nil
end

--- 随机获取一个红尘场景
---@return table
function M.GetRandomHongchenScene()
    return M.HONGCHEN_SCENES[math.random(#M.HONGCHEN_SCENES)]
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据id获取功法
---@param id string
---@return table|nil
function M.GetSkill(id)
    for _, s in ipairs(M.SKILLS) do
        if s.id == id then return s end
    end
    return nil
end

--- 根据名称获取功法
---@param name string
---@return table|nil
function M.GetSkillByName(name)
    for _, s in ipairs(M.SKILLS) do
        if s.name == name then return s end
    end
    return nil
end

--- 获取功法等级配置
---@param level number
---@return table|nil
function M.GetSkillLevel(level)
    return M.SKILL_LEVELS[level]
end

--- 获取悟道配置
---@param id string
---@return table|nil
function M.GetInsight(id)
    for _, d in ipairs(M.DAO_INSIGHTS) do
        if d.id == id then return d end
    end
    return nil
end

return M
