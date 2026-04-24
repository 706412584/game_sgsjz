-- ============================================================================
-- 《问道长生》境界体系数据配置
-- 策划版本: v2.0（2026-04 升级）
-- 参考文档: docs/realm-upgrade-plan.md
-- ============================================================================

local M = {}

-- ============================================================================
-- 1.1 小境界（4 阶）
-- ============================================================================
-- 大圆满 是唯一可发起大境界突破（渡劫/突破）的子阶
-- ============================================================================
M.SUB_REALMS = { "初期", "中期", "后期", "大圆满" }
M.SUB_REALM_MAX = 4  -- 大圆满索引

-- ============================================================================
-- 1.2 大境界定义（凡人期 tier 1~10）
-- ============================================================================
-- cultivation    : {初期门槛, 中期门槛, 后期门槛, 大圆满门槛} 修为需求
-- daoHeartReq    : {初→中, 中→后, 后→大圆满} 最低道心要求（时间门，不可购买）
-- breakItem      : 大境界突破消耗丹药名称（nil = 无要求）
-- breakCount     : 大境界突破消耗丹药数量
-- breakRate      : 大境界突破基础成功率(%)
-- tribName       : 天劫名称（突破时触发）
-- lifespan       : 寿命上限(年)，-1=不死
-- desc           : 境界描述文案
-- ============================================================================
M.REALMS = {
    {
        tier = 1, name = "炼气",
        cultivation  = { 0, 600, 1800, 3500 },
        daoHeartReq  = { 10, 15, 20 },
        breakItem    = nil,
        breakCount   = 0,
        breakRate    = 100,
        tribName     = nil,
        lifespan     = 100,
        desc = "感应天地元气，接引入体，全身内气转化为真气",
    },
    {
        tier = 2, name = "聚灵",
        cultivation  = { 5000, 12000, 22000, 38000 },
        daoHeartReq  = { 30, 40, 50 },
        breakItem    = "筑基丹",
        breakCount   = 2,
        breakRate    = 80,
        tribName     = "凝基劫",
        lifespan     = 200,
        desc = "凝聚天地灵气，真气日益精纯，初窥修真门径",
    },
    {
        tier = 3, name = "筑基",
        cultivation  = { 60000, 120000, 220000, 380000 },
        daoHeartReq  = { 60, 70, 80 },
        breakItem    = "金丹凝结丹",
        breakCount   = 2,
        breakRate    = 65,
        tribName     = "金丹天劫",
        lifespan     = 500,
        desc = "神念与灵魂合一成为神魂，真气压缩为真元，筑修炼之基",
    },
    {
        tier = 4, name = "金丹",
        cultivation  = { 500000, 1000000, 1800000, 3200000 },
        daoHeartReq  = { 100, 120, 140 },
        breakItem    = "凝婴丹",
        breakCount   = 3,
        breakRate    = 50,
        tribName     = "元婴劫",
        lifespan     = 1000,
        desc = "真元凝聚成丹，丹田中结金丹一枚，自此脱胎换骨",
    },
    {
        tier = 5, name = "元婴",
        cultivation  = { 4500000, 9000000, 16000000, 28000000 },
        daoHeartReq  = { 170, 220, 280 },
        breakItem    = "化神丹",
        breakCount   = 3,
        breakRate    = 35,
        tribName     = "化神三灾",
        lifespan     = 3000,
        desc = "斩去虚妄成元婴，元婴自动吐纳，记录修士全部信息",
    },
    {
        tier = 6, name = "化神",
        cultivation  = { 40000000, 80000000, 150000000, 260000000 },
        daoHeartReq  = { 350, 450, 560 },
        breakItem    = "返虚丹",
        breakCount   = 5,
        breakRate    = 22,
        tribName     = "四九天劫",
        lifespan     = 10000,
        desc = "领悟法则改造其身，修出元神，一丝元神不毁则可重生，长生不老",
    },
    {
        tier = 7, name = "返虚",
        cultivation  = { 350000000, 700000000, 1300000000, 2300000000 },
        daoHeartReq  = { 700, 900, 1100 },
        breakItem    = "合道丹",
        breakCount   = 5,
        breakRate    = 14,
        tribName     = "六九天劫",
        lifespan     = 50000,
        desc = "法则圆融，得窥大道，有四九天劫",
    },
    {
        tier = 8, name = "合道",
        cultivation  = { 3000000000, 6000000000, 11000000000, 20000000000 },
        daoHeartReq  = { 1400, 1700, 2000 },
        breakItem    = "大乘丹",
        breakCount   = 7,
        breakRate    = 9,
        tribName     = "九九天劫",
        lifespan     = 100000,
        desc = "万世灵光现，择适而合，虚空造物，人称陆地神仙",
    },
    {
        tier = 9, name = "大乘",
        cultivation  = { 25000000000, 50000000000, 90000000000, 160000000000 },
        daoHeartReq  = { 2500, 3000, 3600 },
        breakItem    = "神游丹",
        breakCount   = 7,
        breakRate    = 6,
        tribName     = nil,
        lifespan     = 500000,
        desc = "知行合一，能唯心开境，言出法随，有九九天劫",
    },
    {
        tier = 10, name = "渡劫",
        cultivation  = { 200000000000, 400000000000, 750000000000, 1350000000000 },
        daoHeartReq  = { 4500, 5500, 6800 },
        breakItem    = "仙灵丹",
        breakCount   = 99,
        breakRate    = 3,
        tribName     = "飞升雷劫",
        lifespan     = -1,
        desc = "喜游于尘世间却不为凡尘所扰，清净自然，飞升在即",
    },
}

-- ============================================================================
-- 1.3 小境界升阶基础增幅（SUB_BREAK_BONUS）
-- ============================================================================
-- 索引 = tier
-- 实际奖励 = bonus × sub_multiplier
--   初期→中期：× 1
--   中期→后期：× 2
--   后期→大圆满：× 3
-- ============================================================================
M.SUB_BREAK_BONUS = {
    { atk =   3, def =   1, hp =    8 },  -- tier 1 炼气
    { atk =   8, def =   3, hp =   20 },  -- tier 2 聚灵
    { atk =  15, def =   6, hp =   40 },  -- tier 3 筑基
    { atk =  28, def =  12, hp =   80 },  -- tier 4 金丹
    { atk =  50, def =  20, hp =  150 },  -- tier 5 元婴
    { atk =  90, def =  35, hp =  280 },  -- tier 6 化神
    { atk = 160, def =  60, hp =  500 },  -- tier 7 返虚
    { atk = 280, def = 100, hp =  900 },  -- tier 8 合道
    { atk = 480, def = 170, hp = 1500 },  -- tier 9 大乘
    { atk = 800, def = 280, hp = 2500 },  -- tier 10 渡劫
}

-- 小境界升阶倍率（sub 为目标子阶，即升到几阶时的倍率）
M.SUB_MULTIPLIER = { 1, 2, 3 }  -- 索引1=初→中, 2=中→后, 3=后→大圆满

-- ============================================================================
-- 1.4 大境界突破属性增幅（BREAK_BONUS）
-- ============================================================================
-- 索引 i = 从第 i 个境界突破到第 i+1 个
-- 含飞升：索引 10 = 渡劫→散仙
-- ============================================================================
M.BREAK_BONUS = {
    { atk =   120, def =   45, hp =    350, spd =  3, crit = 0, sense =  20 },  -- 炼气→聚灵
    { atk =   200, def =   65, hp =    550, spd =  5, crit = 0, sense =  30 },  -- 聚灵→筑基
    { atk =   350, def =   95, hp =    900, spd =  8, crit = 1, sense =  50 },  -- 筑基→金丹
    { atk =   600, def =  160, hp =   1800, spd = 12, crit = 1, sense =  80 },  -- 金丹→元婴
    { atk =  1000, def =  250, hp =   3200, spd = 18, crit = 2, sense = 120 },  -- 元婴→化神
    { atk =  1800, def =  400, hp =   5500, spd = 25, crit = 2, sense = 160 },  -- 化神→返虚
    { atk =  3200, def =  650, hp =   9000, spd = 32, crit = 3, sense = 220 },  -- 返虚→合道
    { atk =  5500, def = 1000, hp =  14000, spd = 40, crit = 3, sense = 280 },  -- 合道→大乘
    { atk =  9000, def = 1600, hp =  22000, spd = 50, crit = 5, sense = 350 },  -- 大乘→渡劫
    { atk = 16000, def = 2500, hp =  40000, spd = 65, crit = 5, sense = 600 },  -- 渡劫→散仙（飞升）
}

-- ============================================================================
-- 1.5 渡劫配置（大境界突破天劫）
-- ============================================================================
-- targetTier : 突破后到达的境界阶数
-- baseRate   : 已写入 REALMS[tier].breakRate，此处备用
-- pillBonus  : 每枚突破辅助丹药额外加成的成功率(%)
-- ============================================================================
-- targetTier = 突破后到达的境界阶数（即：从 targetTier-1 突破到 targetTier）
-- pillBonus  = 凡人期：每枚辅助丹额外加成(%)；仙人期：0（使用材料体系，无药丸加成）
M.TRIBULATIONS = {
    -- 凡人期（T3~T10）
    { name = "凝基劫",   targetTier =  3, baseRate = 80,   pillBonus = 20 },
    { name = "金丹天劫", targetTier =  4, baseRate = 65,   pillBonus = 15 },
    { name = "元婴劫",   targetTier =  5, baseRate = 50,   pillBonus = 10 },
    { name = "化神三灾", targetTier =  6, baseRate = 35,   pillBonus =  8 },
    { name = "四九天劫", targetTier =  7, baseRate = 22,   pillBonus =  5 },
    { name = "六九天劫", targetTier =  8, baseRate = 14,   pillBonus =  3 },
    { name = "九九天劫", targetTier =  9, baseRate =  9,   pillBonus =  2 },
    { name = "飞升雷劫", targetTier = 10, baseRate =  6,   pillBonus =  1 },
    -- 仙人期（T11~T24）
    { name = "仙劫",          targetTier = 11, baseRate =  3,     pillBonus = 0 },
    { name = "天仙劫",        targetTier = 12, baseRate =  2,     pillBonus = 0 },
    { name = "玄仙劫",        targetTier = 13, baseRate =  1.5,   pillBonus = 0 },
    { name = "金仙天劫",      targetTier = 14, baseRate =  1,     pillBonus = 0 },
    { name = "太乙天劫",      targetTier = 15, baseRate =  0.8,   pillBonus = 0 },
    { name = "大罗劫",        targetTier = 16, baseRate =  0.5,   pillBonus = 0 },
    { name = "混元劫",        targetTier = 17, baseRate =  0.3,   pillBonus = 0 },
    { name = "斩尸劫（一斩）", targetTier = 18, baseRate =  0.2,   pillBonus = 0 },
    { name = "斩尸劫（二斩）", targetTier = 19, baseRate =  0.2,   pillBonus = 0 },
    { name = "斩尸劫（三斩）", targetTier = 20, baseRate =  0.1,   pillBonus = 0 },
    { name = "亚圣天劫",      targetTier = 21, baseRate =  0.05,  pillBonus = 0 },
    { name = "圣人劫",        targetTier = 22, baseRate =  0.02,  pillBonus = 0 },
    { name = "道祖劫",        targetTier = 23, baseRate =  0.01,  pillBonus = 0 },
    { name = "天道劫",        targetTier = 24, baseRate =  0.005, pillBonus = 0 },
    -- T25 天道：无天劫，持天道令直接晋升
}

-- 突破失败消耗当前修为的百分比
M.BREAK_FAIL_COST_PCT = 20

-- ============================================================================
-- 1.6 仙人期 15 境（v2 开放）
-- ============================================================================
-- 仙人期小境界使用"仙气"代替"修为"（单位相同，字段名不同）
-- breakItems : 多资源复合消耗，格式 {{ item=名, count=N }, ...}
-- ============================================================================
-- 文化来源：洪荒体系 + 《凡人修仙传》+ 《遮天》
-- 正确顺序：散仙→真仙→玄仙→金仙→太乙金仙→大罗金仙→混元金仙→一/二/三尸准圣→亚圣→圣人→道祖→准天道→天道
M.IMMORTAL_REALMS = {
    {
        tier = 11, name = "散仙",
        lifespan  = -1,
        breakRate =  3,
        tribName  = "仙劫",
        breakItems = { { item = "仙灵丹", count = 99 } },
        bonus = { atk = 16000,  def = 2500,  hp = 40000,  sense = 600 },
        -- 仙气需求（仙人期小境界使用仙气替代凡人修为）
        xianQiReq = { 2000000000000, 4000000000000, 7500000000000, 13500000000000 },
        desc = "飞升初成，仙力未纯，若不遇大劫则长生久视",
    },
    {
        tier = 12, name = "真仙",
        lifespan  = -1,
        breakRate =  2,
        tribName  = "天仙劫",
        breakItems = { { item = "仙灵丹", count = 360 } },
        bonus = { atk = 28000,  def = 4000,  hp = 72000,  sense = 900 },
        xianQiReq = { 25000000000000, 50000000000000, 90000000000000, 160000000000000 },
        desc = "正式成仙，仙力圆满，举手投足间天地异变",
    },
    {
        tier = 13, name = "玄仙",
        lifespan  = -1,
        breakRate =  1.5,
        tribName  = "玄仙劫",
        breakItems = { { item = "仙元丹", count = 99 } },
        bonus = { atk = 46000,  def = 6000,  hp = 115000, sense = 1400 },
        xianQiReq = { 250000000000000, 500000000000000, 900000000000000, 1600000000000000 },
        desc = "初感法则，力量蜕变，已可感应天地法则之存在",
    },
    {
        tier = 14, name = "金仙",
        lifespan  = -1,
        breakRate =  1,
        tribName  = "金仙天劫",
        breakItems = { { item = "仙元丹", count = 299 } },
        bonus = { atk = 68000,  def = 8500,  hp = 170000, sense = 2000 },
        xianQiReq = { 2500000000000000, 5000000000000000, 9000000000000000, 16000000000000000 },
        desc = "法则凝实，须渡天人五衰之劫方可晋升",
    },
    {
        tier = 15, name = "太乙金仙",
        lifespan  = -1,
        breakRate =  0.8,
        tribName  = "太乙天劫",
        breakItems = { { item = "仙元丹", count = 499 } },
        bonus = { atk = 95000,  def = 12000, hp = 240000, sense = 2800 },
        xianQiReq = { 25000000000000000, 50000000000000000, 90000000000000000, 160000000000000000 },
        desc = "开一窍聚三气，法则凝成道果，鸿蒙紫气开始积聚",
    },
    {
        tier = 16, name = "大罗金仙",
        lifespan  = -1,
        breakRate =  0.5,
        tribName  = "大罗劫",
        breakItems = { { item = "大罗仙丹", count = 99 } },
        bonus = { atk = 130000, def = 16000, hp = 320000, sense = 3800 },
        xianQiReq = { 250000000000000000, 500000000000000000, 900000000000000000, 1600000000000000000 },
        desc = "三花聚顶五气朝元，多法则融合，天地间顶尖存在",
    },
    {
        tier = 17, name = "混元金仙",
        lifespan  = -1,
        breakRate =  0.3,
        tribName  = "混元劫",
        breakItems = { { item = "大罗仙丹", count = 299 } },
        bonus = { atk = 170000, def = 21000, hp = 420000, sense = 5000 },
        xianQiReq = { 2500000000000000000, 5000000000000000000, 9000000000000000000, 16000000000000000000 },
        desc = "法则圆融，斩尸之路开启，准圣之门在望",
    },
    {
        tier = 18, name = "一尸准圣",
        lifespan  = -1,
        breakRate =  0.2,
        tribName  = "斩尸劫（一斩）",
        breakItems = { { item = "斩尸珠", count = 1 } },
        bonus = { atk = 220000, def = 28000, hp = 550000, sense = 7000 },
        xianQiReq = { 25000000000000000000, 50000000000000000000, 90000000000000000000, 160000000000000000000 },
        desc = "斩断本我，了断外因果，身外化身初成",
    },
    {
        tier = 19, name = "二尸准圣",
        lifespan  = -1,
        breakRate =  0.2,
        tribName  = "斩尸劫（二斩）",
        breakItems = { { item = "斩尸珠", count = 1 } },
        bonus = { atk = 280000, def = 36000, hp = 700000, sense = 9500 },
        xianQiReq = { 2.5e20, 5e20, 9e20, 1.6e21 },
        desc = "斩断执我，了断内因果，本我执我皆化虚无",
    },
    {
        tier = 20, name = "三尸准圣",
        lifespan  = -1,
        breakRate =  0.1,
        tribName  = "斩尸劫（三斩）",
        breakItems = { { item = "斩尸珠", count = 1 } },
        bonus = { atk = 360000, def = 46000, hp = 900000, sense = 13000 },
        xianQiReq = { 2.5e21, 5e21, 9e21, 1.6e22 },
        desc = "斩断明我，了断天道因果，准圣圆满，亿万年一遇",
    },
    {
        tier = 21, name = "亚圣",
        lifespan  = -1,
        breakRate =  0.05,
        tribName  = "亚圣天劫",
        breakItems = { { item = "亚圣玄晶", count = 1 } },
        bonus = { atk = 460000, def = 60000, hp = 1150000, sense = 17000 },
        xianQiReq = { 2.5e22, 5e22, 9e22, 1.6e23 },
        desc = "半步圣人，天下无敌，唯差临门一脚便可证圣",
    },
    {
        tier = 22, name = "圣人",
        lifespan  = -1,
        breakRate =  0.02,
        tribName  = "圣人劫",
        breakItems = {
            { item = "鸿蒙紫气", count = 36 },
            { item = "亚圣玄晶", count = 3 },
        },
        bonus = { atk = 590000, def = 78000, hp = 1500000, sense = 22000 },
        xianQiReq = { 2.5e23, 5e23, 9e23, 1.6e24 },
        desc = "混元大罗金仙，万劫不灭，因果不沾，鸿蒙紫气36枚证就圣位",
    },
    {
        tier = 23, name = "道祖",
        lifespan  = -1,
        breakRate =  0.01,
        tribName  = "道祖劫",
        breakItems = {
            { item = "混元道果", count = 1 },
            { item = "道韵",    count = 50 },
        },
        bonus = { atk = 750000, def = 100000, hp = 1900000, sense = 28000 },
        xianQiReq = { 2.5e24, 5e24, 9e24, 1.6e25 },
        desc = "三千大道之主，参悟至尊法则，俯瞰众生圣人",
    },
    {
        tier = 24, name = "准天道",
        lifespan  = -1,
        breakRate =  0.005,
        tribName  = "天道劫",
        breakItems = {
            { item = "天道印",  count = 1 },
            { item = "道韵",   count = 100 },
            { item = "鸿蒙紫气", count = 100 },
        },
        bonus = { atk = 960000, def = 130000, hp = 2500000, sense = 36000 },
        xianQiReq = { 2.5e25, 5e25, 9e25, 1.6e26 },
        desc = "感悟天道本源，即将与天道合一，超越所有生灵",
    },
    {
        tier = 25, name = "天道",
        lifespan  = -1,
        breakRate =  nil,   -- 无需突破，持有天道令直接晋升
        tribName  = nil,
        breakItems = {
            { item = "天道令", count = 1 },   -- 赛季全服唯一
        },
        bonus = { atk = 1300000, def = 180000, hp = 3500000, sense = 50000 },
        xianQiReq = { 2.5e26, 5e26, 9e26, 1.6e27 },
        desc = "与天道合一，超越所有存在，天道即我，我即天道",
    },
}

-- ============================================================================
-- 渡劫小游戏难度配置（tier 6~10）
-- tier      : 当前大境界阶数（6=化神 … 10=渡劫）
-- name      : 天劫名称
-- boltCount : 总雷数
-- duration  : 游戏时长(秒)
-- boltSpeed : 落雷速度(px/s，1080P 参考值)
-- warnTime  : 预警时间(秒)
-- boltW     : 雷柱宽度(px，1080P 参考值)
-- colorHex  : 雷电颜色（十六进制字符串，不含 #）
-- ============================================================================
M.DUJIE_TIERS = {
    [6]  = { tier=6,  name="三九天劫",   boltCount=15, duration=20, boltSpeed=320, warnTime=1.2, boltW=38, colorHex="8B5CF6" },
    [7]  = { tier=7,  name="四九天劫",   boltCount=20, duration=26, boltSpeed=390, warnTime=1.0, boltW=42, colorHex="6D28D9" },
    [8]  = { tier=8,  name="六九天劫",   boltCount=27, duration=32, boltSpeed=460, warnTime=0.7, boltW=47, colorHex="C4B5FD" },
    [9]  = { tier=9,  name="七七天劫",   boltCount=36, duration=40, boltSpeed=530, warnTime=0.5, boltW=52, colorHex="F59E0B" },
    [10] = { tier=10, name="九九归元劫", boltCount=50, duration=52, boltSpeed=620, warnTime=0.3, boltW=58, colorHex="DC2626" },
}

--- 获取渡劫小游戏配置
---@param tier number 当前大境界阶数（6~10 有小游戏，其余返回 nil）
---@return table|nil
function M.GetDujieTier(tier)
    return M.DUJIE_TIERS[tier]
end

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据阶数获取凡人期境界配置（tier 1~10）
---@param tier number
---@return table|nil
function M.GetRealm(tier)
    return M.REALMS[tier]
end

--- 根据阶数获取仙人期境界配置（tier 11~25）
---@param tier number
---@return table|nil
function M.GetImmortalRealm(tier)
    return M.IMMORTAL_REALMS[tier - 10]
end

--- 根据阶数获取任意境界配置（tier 1~25）
---@param tier number
---@return table|nil
function M.GetAnyRealm(tier)
    if tier <= 10 then
        return M.REALMS[tier]
    else
        return M.GetImmortalRealm(tier)
    end
end

--- 获取完整境界名（如"筑基大圆满"）
---@param tier number 阶数
---@param sub number 小境界索引(1=初期,2=中期,3=后期,4=大圆满)
---@return string
function M.GetFullName(tier, sub)
    local r = M.GetAnyRealm(tier)
    if not r then return "未知" end
    return r.name .. (M.SUB_REALMS[sub] or "")
end

--- 解析完整境界名为 tier, sub
---@param fullName string 如"筑基大圆满"
---@return number|nil tier, number|nil sub
function M.ParseFullName(fullName)
    local allRealms = {}
    for _, r in ipairs(M.REALMS) do allRealms[#allRealms + 1] = r end
    for _, r in ipairs(M.IMMORTAL_REALMS) do allRealms[#allRealms + 1] = r end
    for _, r in ipairs(allRealms) do
        for si, sn in ipairs(M.SUB_REALMS) do
            if fullName == r.name .. sn then
                return r.tier, si
            end
        end
    end
    return nil, nil
end

--- 获取指定境界小境界的修为需求
---@param tier number
---@param sub number
---@return number
function M.GetCultivationReq(tier, sub)
    local r = M.GetRealm(tier)
    if not r then return 0 end
    return r.cultivation[sub] or 0
end

--- 获取仙人期指定境界小境界的仙气需求（tier >= 11）
---@param tier number 仙人期阶数（11~25）
---@param sub number 小境界索引（1~4）
---@return number
function M.GetXianQiReq(tier, sub)
    local r = M.GetImmortalRealm(tier)
    if not r or not r.xianQiReq then return 0 end
    return r.xianQiReq[sub] or 0
end

--- 获取升小境界所需最低道心
---@param tier number 当前大境界阶数
---@param fromSub number 当前子阶（升到 fromSub+1 时检查）
---@return number
function M.GetDaoHeartReq(tier, fromSub)
    local r = M.GetRealm(tier)
    if not r or not r.daoHeartReq then return 0 end
    return r.daoHeartReq[fromSub] or 0
end

--- 计算小境界升阶属性奖励
---@param tier number 大境界阶数
---@param fromSub number 从哪个小境界升（1=初期升中期时传1）
---@return table { atk, def, hp }
function M.GetSubBreakBonus(tier, fromSub)
    local base = M.SUB_BREAK_BONUS[tier]
    if not base then return { atk = 0, def = 0, hp = 0 } end
    local mult = M.SUB_MULTIPLIER[fromSub] or 1
    return {
        atk = base.atk * mult,
        def = base.def * mult,
        hp  = base.hp  * mult,
    }
end

--- 获取大境界突破增幅（从 fromTier 突破到 fromTier+1）
---@param fromTier number
---@return table|nil
function M.GetBreakBonus(fromTier)
    return M.BREAK_BONUS[fromTier]
end

--- 获取渡劫配置（按目标境界查找）
---@param targetTier number 突破后到达的阶数
---@return table|nil
function M.GetTribulation(targetTier)
    for _, t in ipairs(M.TRIBULATIONS) do
        if t.targetTier == targetTier then return t end
    end
    return nil
end

--- 判断是否为大圆满（可尝试大境界突破）
---@param sub number
---@return boolean
function M.IsGreatCircle(sub)
    return sub == M.SUB_REALM_MAX
end

return M
