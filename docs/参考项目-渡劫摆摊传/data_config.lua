-- ============================================================================
-- data_config.lua — 渡劫摆摊传 静态数据配置
-- ============================================================================
local M = {}

-- ========== 版本号（与 .project/project.json 保持同步） ==========
M.VERSION = "1.0.42"

-- ========== 修仙风格配色 ==========
M.Colors = {
    -- 主色调
    bg          = { 25, 28, 38, 255 },       -- 深夜空色背景
    bgLight     = { 35, 40, 55, 255 },       -- 浅底色
    panel       = { 40, 45, 65, 240 },       -- 面板色
    panelLight  = { 55, 62, 85, 230 },       -- 浅面板
    -- 功能色
    gold        = { 218, 185, 107, 255 },    -- 灵石金
    goldDark    = { 168, 135, 67, 255 },     -- 暗金
    jade        = { 88, 199, 155, 255 },     -- 翠玉绿
    jadeDark    = { 58, 149, 115, 255 },     -- 暗绿
    purple      = { 150, 120, 210, 255 },    -- 灵气紫
    purpleDark  = { 110, 80, 170, 255 },     -- 暗紫
    red         = { 220, 80, 75, 255 },      -- 天劫红
    blue        = { 80, 150, 230, 255 },     -- 符文蓝
    orange      = { 230, 160, 60, 255 },     -- 丹火橙
    pink        = { 220, 140, 170, 255 },    -- 桃粉(女性名字)
    green       = { 100, 210, 140, 255 },    -- 在线绿
    -- 聊天气泡
    bubbleSelf  = { 40, 70, 65, 230 },       -- 自己消息气泡(深青)
    bubbleOther = { 38, 40, 55, 220 },       -- 他人消息气泡(深灰蓝)
    -- 文字色
    textPrimary = { 230, 225, 210, 255 },    -- 主文字
    textSecond  = { 160, 155, 145, 200 },    -- 次文字
    textGold    = { 235, 200, 120, 255 },    -- 金色文字
    textGreen   = { 120, 220, 170, 255 },    -- 绿色文字
    -- 边框
    border      = { 80, 85, 110, 120 },      -- 通用边框
    borderGold  = { 180, 150, 80, 150 },     -- 金色边框
}

-- ========== 境界数据 ==========
-- lifespan: 该境界基础寿元(年)
-- breakthroughCost: 突破到该境界所需灵石
M.Realms = {
    { name = "炼气", xiuwei = 0,         lifespan = 100,   breakthroughCost = 0,      unlockDesc = "聚气丹" },
    { name = "筑基", xiuwei = 5000,      lifespan = 200,   breakthroughCost = 2000,   unlockDesc = "回春符, 全商品售价+10%" },
    { name = "金丹", xiuwei = 18000,     lifespan = 500,   breakthroughCost = 8000,   unlockDesc = "低阶法器/筑基灵药/万灵卷, 客流速度+15%" },
    { name = "元婴", xiuwei = 50000,     lifespan = 1000,  breakthroughCost = 25000,  unlockDesc = "凝魂丹/天阶法器, 高价顾客概率提升" },
    { name = "化神", xiuwei = 120000,    lifespan = 2000,  breakthroughCost = 60000,  unlockDesc = "飞升丹, 全商品售价+20%" },
    { name = "炼虚", xiuwei = 260000,    lifespan = 5000,  breakthroughCost = 130000, unlockDesc = "破虚符, 自动售卖效率+30%" },
    { name = "合体", xiuwei = 520000,    lifespan = 10000, breakthroughCost = 260000, unlockDesc = "神秘商人收益倍率提升" },
    { name = "大乘", xiuwei = 980000,    lifespan = 50000, breakthroughCost = 500000, unlockDesc = "仙器残片, 客流速度额外+35%" },
    { name = "渡劫", xiuwei = 1800000,   lifespan = 99999, breakthroughCost = 1500000,unlockDesc = "解锁终局渡劫与飞升" },
}

-- 寿元消耗速率: 每现实秒消耗多少年寿元
M.LifespanDrainPerSec = 0.015  -- 每秒 0.015 年 ≈ 每分钟 0.9 年 (炼气期x0.5≈3.7小时)

-- ========== 吸收灵石化修为 ==========
-- ratio: 灵石/修为 比例; amount: 每次吸收获得的修为
M.AbsorbConfig = {
    { ratio = 1.5, amount = 50 },   -- 炼气: 75灵石→50修为 (新手特惠)
    { ratio = 3,   amount = 80 },   -- 筑基: 240灵石→80修为
    { ratio = 5,   amount = 120 },  -- 金丹: 600灵石→120修为
    { ratio = 8,   amount = 200 },  -- 元婴: 1600灵石→200修为
    { ratio = 12,  amount = 300 },  -- 化神: 3600灵石→300修为
    { ratio = 15,  amount = 500 },  -- 炼虚: 7500灵石→500修为
    { ratio = 15,  amount = 500 },  -- 合体
    { ratio = 15,  amount = 500 },  -- 大乘
    { ratio = 15,  amount = 500 },  -- 渡劫
}

-- 被动修为获取: 每赚 N 灵石 → 10 修为
M.PassiveXiuweiPerLingshi = 50  -- 每50灵石→10修为 (原100, 提升至20%转化率)

-- 炼气期寿元消耗倍率(新手保护)
M.RealmLifespanDrainMul = {
    [1] = 0.5,  -- 炼气期消耗减半, 存活时间翻倍(~3.7小时)
}

-- ========== 转生系统 ==========
M.Rebirth = {
    lingshiKeepRate = 0.10,       -- 转生保留灵石比例(10%)
    keepRatePerRebirth = 0.05,    -- 每次转生额外增加保留比例(+5%)
    maxKeepRate = 0.50,           -- 最高保留比例(50%)
    bonusPerRebirth = 0.05,       -- 每次转生全局收益加成(+5%)
    maxBonus = 1.00,              -- 最高收益加成(+100%)
    lifespanBonus = 20,           -- 每次转生额外初始寿元(+20年)
    xiuweiBonus = 100,            -- 每次转生额外初始修为
}

-- ========== 图片资源路径 ==========
M.Images = {
    lingshi     = "image/icon_lingshi.png",
    xiuwei      = "image/icon_xiuwei.png",
    -- 材料
    lingcao     = "image/icon_lingcao.png",
    lingzhi     = "image/icon_lingzhi.png",
    xuantie     = "image/icon_xuantie.png",
    -- 商品
    juqi_dan    = "image/icon_juqi_dan.png",
    huichun_fu  = "image/icon_huichun_fu.png",
    dijie_faqi  = "image/icon_dijie_faqi.png",
    ninghun_dan = "image/icon_ninghun_dan.png",
    poxu_fu     = "image/icon_poxu_fu.png",
    xianqi_canpian = "image/icon_xianqi_canpian.png",
    -- 高级商品
    zhuji_lingyao = "image/icon_zhuji_lingyao.png",
    wanling_juan  = "image/icon_wanling_juan.png",
    tianjie_faqi  = "image/icon_tianjie_faqi.png",
    feisheng_dan  = "image/icon_feisheng_dan.png",
    -- 仙界商品（功能11）
    product_tianxian_dan    = "image/product_tianxian_dan.png",
    product_tianchan_fu     = "image/product_tianchan_fu.png",
    product_xingchen_faqi   = "image/product_xingchen_faqi.png",
    product_xuanxian_lingdan= "image/product_xuanxian_lingdan.png",
    product_shenluo_fu      = "image/product_shenluo_fu.png",
    product_jinxian_fabao   = "image/product_jinxian_fabao.png",
    product_taiyi_lingdan   = "image/product_taiyi_lingdan.png",
    product_wanxiang_shenfu = "image/product_wanxiang_shenfu.png",
    product_zhunsheng_fabao = "image/product_zhunsheng_fabao.png",
    product_hundun_zhu      = "image/product_hundun_zhu.png",
    -- 仙界材料（功能11）
    lingjing_cao      = "image/mat_lingjing_cao.png",
    tianchan_si       = "image/mat_tianchan_si.png",
    xingchen_kuang    = "image/mat_xingchen_kuang.png",
    shanggu_lingjing  = "image/mat_shanggu_lingjing.png",
    tianchan_jinghua  = "image/mat_tianchan_jinghua.png",
    xingchen_jinghua  = "image/mat_xingchen_jinghua.png",
    hundun_jing       = "image/mat_hundun_jing.png",
    -- 顾客头像(男)
    sanxiu      = "image/avatar_sanxiu.png",
    sanxiu_m2   = "image/avatar_sanxiu_m2.png",
    sanxiu_m3   = "image/avatar_sanxiu_m3.png",
    youshang    = "image/avatar_youshang.png",
    youshang_m2 = "image/avatar_youshang_m2.png",
    youshang_m3 = "image/avatar_youshang_m3.png",
    zongmen     = "image/avatar_zongmen.png",
    zongmen_m2  = "image/avatar_zongmen_m2.png",
    zongmen_m3  = "image/avatar_zongmen_m3.png",
    guike       = "image/avatar_guike.png",
    guike_m2    = "image/avatar_guike_m2.png",
    guike_m3    = "image/avatar_guike_m3.png",
    -- 顾客头像(女)
    sanxiu_f    = "image/avatar_sanxiu_f.png",
    youshang_f  = "image/avatar_youshang_f.png",
    zongmen_f   = "image/avatar_zongmen_f.png",
    guike_f     = "image/avatar_guike_f.png",
    -- 角色打坐
    char_meditate = "image/char_meditate.png",
    char_meditate_female = "image/char_meditate_female.png",
    char_realm_bg = "image/char_realm_bg.png",
}

-- ========== 音效路径 ==========
M.SFX = {
    buy             = "audio/sfx/sfx_buy.ogg",
    upgrade         = "audio/sfx/sfx_upgrade.ogg",
    craft_complete  = "audio/sfx/sfx_craft_complete.ogg",
    encounter       = "audio/sfx/sfx_encounter.ogg",
    customer_arrive = "audio/sfx/sfx_customer_arrive.ogg",
    thunder_1       = "audio/sfx/thunder_strike_1.ogg",
    thunder_2       = "audio/sfx/thunder_strike_2.ogg",
    thunder_3       = "audio/sfx/thunder_strike_3.ogg",
}
M.BGM = "audio/bgm_xianfang.ogg"

-- ========== 材料数据 ==========
M.Materials = {
    {
        id = "lingcao",
        name = "灵草",
        rate = 10,       -- 每分钟产出
        icon = "[草]",
        image = "lingcao",
        color = { 80, 200, 120, 255 },
        cap = 29999,
    },
    {
        id = "lingzhi",
        name = "灵纸",
        rate = 8,
        icon = "[纸]",
        image = "lingzhi",
        color = { 200, 190, 130, 255 },
        cap = 29999,
    },
    {
        id = "xuantie",
        name = "玄铁",
        rate = 4,
        icon = "[铁]",
        image = "xuantie",
        color = { 150, 160, 180, 255 },
        cap = 29999,
    },
    -- 合成材料(rate=0: 不自动产出，仅通过合成获得)
    {
        id = "gaoji_lingcao",
        name = "高级灵草",
        rate = 0,
        icon = "[高草]",
        image = "lingcao",
        color = { 50, 180, 100, 255 },
        cap = 999,
    },
    {
        id = "jinglian_lingzhi",
        name = "精炼灵纸",
        rate = 0,
        icon = "[精纸]",
        image = "lingzhi",
        color = { 180, 170, 100, 255 },
        cap = 999,
    },
    {
        id = "hantie_ding",
        name = "寒铁锭",
        rate = 0,
        icon = "[锭]",
        image = "xuantie",
        color = { 130, 140, 170, 255 },
        cap = 999,
    },
    {
        id = "tianling_ye",
        name = "天灵液",
        rate = 0,
        icon = "[液]",
        image = "lingcao",
        color = { 180, 130, 255, 255 },
        cap = 99,
    },
}

-- ========== 商品数据 ==========
M.Products = {
    {
        id = "juqi_dan",
        name = "聚气丹",
        materialId = "lingcao",
        materialCost = 8,
        craftTime = 8,       -- 秒
        price = 36,
        unlockRealm = 1,     -- 炼气期解锁
        icon = "[丹]",
        image = "juqi_dan",
        color = { 230, 160, 60, 255 },
    },
    {
        id = "huichun_fu",
        name = "回春符",
        materialId = "lingzhi",
        materialCost = 6,
        craftTime = 8,
        price = 50,
        unlockRealm = 2,     -- 筑基期解锁
        icon = "[符]",
        image = "huichun_fu",
        color = { 80, 150, 230, 255 },
    },
    {
        id = "dijie_faqi",
        name = "低阶法器",
        materialId = "xuantie",
        materialCost = 3,
        craftTime = 12,
        price = 65,
        unlockRealm = 3,     -- 金丹期解锁
        icon = "[器]",
        image = "dijie_faqi",
        color = { 150, 120, 210, 255 },
    },
    {
        id = "ninghun_dan",
        name = "凝魂丹",
        materialId = "lingcao",
        materialCost = 15,    -- 灵草×15 (聚气丹的1.9倍)
        craftTime = 12,       -- 12秒
        price = 100,
        unlockRealm = 4,     -- 元婴期解锁
        icon = "[魂]",
        image = "ninghun_dan",
        color = { 170, 100, 220, 255 },
    },
    {
        id = "poxu_fu",
        name = "破虚符",
        materialId = "lingzhi",
        materialCost = 12,    -- 灵纸×12 (回春符的2倍)
        craftTime = 15,       -- 15秒
        price = 200,
        unlockRealm = 6,     -- 炼虚期解锁
        icon = "[虚]",
        image = "poxu_fu",
        color = { 60, 180, 230, 255 },
    },
    {
        id = "xianqi_canpian",
        name = "仙器残片",
        materialId = "xuantie",
        materialCost = 10,    -- 玄铁×10 (低阶法器的3.3倍)
        craftTime = 20,       -- 20秒
        price = 450,
        unlockRealm = 8,     -- 大乘期解锁
        icon = "[仙]",
        image = "xianqi_canpian",
        color = { 255, 200, 50, 255 },
    },
    -- === 使用合成材料的高级商品 ===
    {
        id = "zhuji_lingyao",
        name = "筑基灵药",
        materialId = "gaoji_lingcao",
        materialCost = 2,     -- 高级灵草×2
        craftTime = 15,       -- 15秒
        price = 180,
        unlockRealm = 3,     -- 金丹期解锁(与高级灵草合成同期)
        icon = "[药]",
        image = "zhuji_lingyao",
        color = { 100, 220, 130, 255 },
    },
    {
        id = "wanling_juan",
        name = "万灵卷",
        materialId = "jinglian_lingzhi",
        materialCost = 2,     -- 精炼灵纸×2
        craftTime = 15,
        price = 200,
        unlockRealm = 3,     -- 金丹期解锁(与精炼灵纸合成同期)
        icon = "[卷]",
        image = "wanling_juan",
        color = { 120, 180, 240, 255 },
    },
    {
        id = "tianjie_faqi",
        name = "天阶法器",
        materialId = "hantie_ding",
        materialCost = 2,     -- 寒铁锭×2
        craftTime = 20,
        price = 380,
        unlockRealm = 4,     -- 元婴期解锁(与寒铁锭合成同期)
        icon = "[天]",
        image = "tianjie_faqi",
        color = { 200, 170, 255, 255 },
    },
    {
        id = "feisheng_dan",
        name = "飞升丹",
        materialId = "tianling_ye",
        materialCost = 1,     -- 天灵液×1
        craftTime = 30,       -- 30秒(稀有品)
        price = 1200,
        unlockRealm = 5,     -- 化神期解锁(与天灵液合成同期)
        icon = "[升]",
        image = "feisheng_dan",
        color = { 255, 220, 100, 255 },
    },
}

-- ========== 摊位等级 ==========
M.StallLevels = {
    { level = 1, cost = 0,      queueLimit = 1,  slots = 1,  speedMul = 1.0 },
    { level = 2, cost = 300,    queueLimit = 2,  slots = 1,  speedMul = 1.2 },
    { level = 3, cost = 700,    queueLimit = 3,  slots = 2,  speedMul = 1.45 },
    { level = 4, cost = 1200,   queueLimit = 5,  slots = 3,  speedMul = 1.75 },
    { level = 5, cost = 2000,   queueLimit = 7,  slots = 4,  speedMul = 2.1 },
    { level = 6, cost = 5000,   queueLimit = 9,  slots = 5,  speedMul = 2.5 },
    { level = 7, cost = 12000,  queueLimit = 12, slots = 6,  speedMul = 3.0 },
    { level = 8, cost = 25000,  queueLimit = 14, slots = 8,  speedMul = 3.5 },
    { level = 9, cost = 50000,  queueLimit = 16, slots = 9,  speedMul = 4.0 },
    { level = 10, cost = 100000, queueLimit = 20, slots = 10, speedMul = 5.0 },
}

-- ========== 顾客类型 ==========
M.CustomerTypes = {
    {
        id = "sanxiu",
        name = "散修",
        weight = 60,
        buyCount = 1,       -- 每次购买数量
        buyInterval = 8,    -- 秒
        payMul = 1.0,
        color = { 180, 180, 180, 255 },
        avatar = "sanxiu",
        avatarMList = { "sanxiu", "sanxiu_m2", "sanxiu_m3" },
        avatarF = "sanxiu_f",
        dialogues = { "想买点%s...", "有%s吗?", "来点%s", "%s多少钱?", "听人说%s好用", "掌柜,来份%s", "%s还有货吗" },
    },
    {
        id = "youshang",
        name = "游商",
        weight = 25,
        buyCount = 2,       -- 每次购买数量
        buyInterval = 7,
        payMul = 1.2,
        color = { 100, 200, 150, 255 },
        avatar = "youshang",
        avatarMList = { "youshang", "youshang_m2", "youshang_m3" },
        avatarF = "youshang_f",
        dialogues = { "听说你这%s不错", "批发%s便宜吗", "给我来些%s", "%s品质如何?", "这批%s成色不错", "%s能便宜点吗" },
    },
    {
        id = "zongmen",
        name = "宗门弟子",
        weight = 12,
        buyCount = 3,       -- 每次购买数量
        buyInterval = 6,
        payMul = 1.5,
        color = { 120, 160, 230, 255 },
        avatar = "zongmen",
        avatarMList = { "zongmen", "zongmen_m2", "zongmen_m3" },
        avatarF = "zongmen_f",
        dialogues = { "师尊让我买%s", "宗门急需%s", "这%s灵气充足吗", "给我上等%s", "长老点名要%s", "门派任务需要%s" },
    },
    {
        id = "guike",
        name = "奇遇贵客",
        weight = 3,
        buyCount = 5,       -- 每次购买数量
        buyInterval = 0,    -- 即时购买
        payMul = 2.5,
        color = { 230, 190, 80, 255 },
        avatar = "guike",
        avatarMList = { "guike", "guike_m2", "guike_m3" },
        avatarF = "guike_f",
        dialogues = { "全要了!", "好东西不怕贵", "%s我出双倍", "有多少%s收多少", "本座看上了,包圆!" },
    },
}

-- ========== 顾客名字池 ==========
M.CustomerNames = {
    sanxiu = {
        "张三", "李四", "赵六", "王二麻子", "老刘头",
        "阿牛", "铁柱", "小翠", "胖婶", "瘦猴",
        "陈大壮", "周小花", "吴大锤", "孙寡妇", "刘麻子",
        "凡间来的樵夫", "进城的猎户", "隔壁老王", "卖菜的婆婆", "路过的书生",
        "村头铁匠", "山下药农", "落魄秀才", "退伍老兵", "流浪琴师",
    },
    youshang = {
        "胡商老马", "南海行商", "西域来客", "东海渔翁", "北荒皮货商",
        "丝路驼客", "药材贩子", "走街串巷的货郎", "坊市老板娘", "灵矿倒爷",
        "珍宝阁伙计", "万宝楼掌柜", "符箓批发商", "丹药中间人",
    },
    zongmen = {
        "师兄", "师姐", "小师妹", "师弟", "大师兄",
        "二师姐", "三师弟", "入门弟子", "外门长老", "内门师叔",
        "执事弟子", "守山弟子", "藏经阁小童", "丹房师妹", "剑阁师兄",
        "云霄宗弟子", "天机阁使者", "药王谷学徒",
    },
    guike = {
        "仙风道骨的老者", "神秘蒙面人", "紫衣女修", "白发剑仙",
        "飞来的前辈", "路过的大能", "化形的妖王", "渡劫期老怪",
        "元婴真君", "从天而降的仙人",
    },
}

-- ========== 闲聊对话(不带商品名) ==========
M.IdleChatDialogues = {
    sanxiu = {
        "今儿天气不错啊", "这仙坊越来越热闹了", "路过看看...",
        "唉,修炼好累", "听说隔壁摊位关门了", "凡间的饭真香啊",
        "有没有便宜的好东西?", "就随便逛逛", "好久没来仙坊了",
        "哎哟,腿都走酸了", "这修仙真不是人干的活",
    },
    youshang = {
        "最近行情怎么样?", "生意难做啊", "你这铺子位置不错",
        "走南闯北就爱逛坊市", "什么好卖给我推荐推荐", "货好不愁卖嘛",
        "同行们都在涨价啊", "有没有新品?",
    },
    zongmen = {
        "师尊说要下山历练", "宗门最近开销大", "来采购些日常用品",
        "终于轮到我出门了!", "秘境马上要开了", "门派大比在即",
        "掌柜道友辛苦了", "替师叔跑个腿",
    },
    guike = {
        "小友,有缘啊", "本座路过此地", "嗯...灵气还算充裕",
        "难得遇到个实在的商家", "这方天地倒也有趣",
    },
}

-- ========== 跨境界需求配置 ==========
M.CrossRealmDemandChance = 0.18  -- 18%概率想要下一境界商品
M.CrossRealmDialogues = {
    "你这有%s吗? 我特意来找的",
    "听说%s效果很好,有卖吗?",
    "我想买%s,你能弄到不?",
    "%s...应该很值钱吧?",
    "到处找%s,你这有没有?",
}

-- ========== 顾客需求匹配奖励 ==========
M.DemandMatchBonus = 1.5      -- 顾客买到想要的商品, 额外1.5倍灵石
M.DemandMismatchMul = 0.8     -- 买到非想要的商品, 只给0.8倍

-- ========== 开场剧情 ==========
M.StoryScenes = {
    {
        title = "雷劫降临",
        text = "我本以为，这一劫后便能飞升。",
    },
    {
        title = "当场失败",
        text = "结果修为没了，法宝碎了，连灵石也一块不剩。",
    },
    {
        title = "落到仙坊",
        text = "为了活下去，我只好先在仙坊摆摊。",
    },
    {
        title = "第一批货",
        text = "卖最便宜的丹药，赚最难挣的第一笔灵石。",
    },
    {
        title = "重燃目标",
        text = "今天摆摊，明日开铺，终有一天我还要再渡天劫。",
    },
    {
        title = "进入游戏",
        text = "先卖出第一单，再谈成仙。",
    },
}

-- ========== 新手礼包 ==========
M.NewbieGift = {
    lingshi = 2000,
    xiuwei = 200,
    materials = { lingcao = 100, lingzhi = 80, xuantie = 50 },
    products = { juqi_dan = 10, peiyuan_dan = 5 },
}

-- ========== 灵田系统 ==========
M.Crops = {
    { id = "lingcao_seed", name = "灵草种子", icon = "[苗]", growTime = 80,  yield = { lingcao = 25 }, cost = 10, color = { 80, 200, 120, 255 } },
    { id = "lingzhi_seed", name = "灵纸种子", icon = "[芽]", growTime = 120, yield = { lingzhi = 18 }, cost = 20, color = { 200, 190, 130, 255 } },
    { id = "xuantie_seed", name = "玄铁矿苗", icon = "[矿]", growTime = 200, yield = { xuantie = 12 }, cost = 35, color = { 150, 160, 180, 255 } },
}

M.FieldLevels = {
    { plots = 2, cost = 0 },
    { plots = 3, cost = 1000 },
    { plots = 4, cost = 3000 },
    { plots = 5, cost = 12000,  requiredRealm = 3 },   -- 需金丹期
    { plots = 6, cost = 40000,  requiredRealm = 4 },   -- 需元婴期
    { plots = 7, cost = 100000, requiredRealm = 5 },   -- 需化神期
    { plots = 8, cost = 250000, requiredRealm = 6 },   -- 需合体期
}

-- ========== 灵童雇佣系统 ==========
-- 定价依据: 前期1h在线约3000-5000灵石; 中期8000-15000/h; 后期20000-50000/h
-- 日租=约15-20%小时收入, 形成有意义的经济决策
M.FieldServants = {
    {
        tier = 1,
        name = "木灵童",
        desc = "自动收获成熟作物",
        cost = 500,                  -- 日租灵石
        requiredRealm = 1,           -- 炼气即可
        abilities = { harvest = true, plant = false, speedBonus = 0 },
        image = "image/servant_wood_20260412144233.png",
        color = { 100, 180, 80, 255 },
    },
    {
        tier = 2,
        name = "玉灵童",
        desc = "自动收获+自动种植(可选作物)",
        cost = 1500,
        requiredRealm = 2,           -- 筑基
        abilities = { harvest = true, plant = true, speedBonus = 0 },
        image = "image/servant_jade_20260412144218.png",
        color = { 120, 210, 180, 255 },
    },
    {
        tier = 3,
        name = "金灵童",
        desc = "收获+种植+生长加速20%",
        cost = 4000,
        requiredRealm = 3,           -- 金丹
        abilities = { harvest = true, plant = true, speedBonus = 0.2 },
        image = "image/servant_gold_20260412144220.png",
        color = { 240, 200, 80, 255 },
    },
}

-- ========== 炼器傀儡系统 ==========
M.CraftPuppet = {
    name = "炼器傀儡",
    desc = "自动制作指定商品(可选商品类型)",
    cost = 2000,                 -- 日租灵石
    requiredRealm = 2,           -- 筑基解锁
    image = "image/puppet_craft_20260412144224.png",
    color = { 180, 150, 120, 255 },
}

-- ========== 奇遇事件 ==========
M.Encounters = {
    { id = "treasure",  name = "发现宝箱", desc = "路边发现一个闪光的宝箱!",   reward = { lingshi = 50 },                   weight = 30 },
    { id = "herb",      name = "采到仙草", desc = "发现一株珍稀灵草!",         reward = { lingcao = 20, lingzhi = 10 },     weight = 25 },
    { id = "merchant",  name = "遇到行商", desc = "行商低价出售一批玄铁!",     reward = { xuantie = 8 },                    weight = 20 },
    { id = "enlighten", name = "顿悟修炼", desc = "突然灵光一闪，修为大增!",   reward = { xiuwei = 100 },                   weight = 15 },
    { id = "jackpot",   name = "天降灵石", desc = "天降异宝，化为大量灵石!",   reward = { lingshi = 200 },                  weight = 10 },
}
M.EncounterInterval = 300
M.EncounterChance = 0.05

-- ========== CDK 兑换码 ==========
M.CDKRewards = {
    GIFT1 = { name = "新手福利码", lingshi = 100, materials = { lingcao = 20, lingzhi = 15 } },
    GIFT2 = { name = "豪华礼包码", lingshi = 500, xiuwei = 200, materials = { lingcao = 50, lingzhi = 30, xuantie = 20 } },
    NOAD = { name = "免广告特权", adFree = true, adFreeDays = 30 },
}
M.CDK_PREFIX = "DJBT"

-- ========== 数值计算辅助 ==========

--- 获取当前境界索引(1-based)
---@param xiuwei number
---@return number realmIndex
function M.GetRealmIndex(xiuwei)
    local idx = 1
    for i = #M.Realms, 1, -1 do
        if xiuwei >= M.Realms[i].xiuwei then
            idx = i
            break
        end
    end
    return idx
end

--- 获取下一境界所需修为
---@param xiuwei number
---@return number|nil nextXiuwei
function M.GetNextRealmXiuwei(xiuwei)
    local idx = M.GetRealmIndex(xiuwei)
    if idx < #M.Realms then
        return M.Realms[idx + 1].xiuwei
    end
    return nil
end

-- ========== 秘境探险配置 ==========
M.DUNGEON_DAILY_LIMIT = 3  -- 每个秘境每日可探险次数

M.Dungeons = {
    {
        id = "lingcao", name = "灵草秘境", cost = 200, unlockRealm = 2,
        desc = "蕴含灵草精华的上古秘境",
        color = M.Colors.jade,
        icon = "image/dungeon_lingcao.png",
    },
    {
        id = "liandan", name = "炼丹洞府", cost = 500, unlockRealm = 3,
        desc = "丹道先贤遗留的洞府遗迹",
        color = M.Colors.orange,
        icon = "image/dungeon_liandan.png",
    },
    {
        id = "wanbao", name = "万宝秘藏", cost = 1500, unlockRealm = 4,
        desc = "传说中的万宝秘藏之地",
        color = M.Colors.purple,
        icon = "image/dungeon_wanbao.png",
    },
    {
        id = "tianjie", name = "天劫遗迹", cost = 3000, unlockRealm = 5,
        desc = "渡劫失败者留下的危险遗迹",
        color = M.Colors.red,
        icon = "image/dungeon_tianjie.png",
    },
    {
        id = "fabao", name = "法宝秘境", cost = 5000, unlockRealm = 6,
        desc = "蕴含法宝精华的远古炼器场",
        color = { 220, 180, 80, 255 },
        icon = "image/dungeon_fabao.png",
    },
}

--- 根据 id 查找秘境配置
---@param id string
---@return table|nil
function M.GetDungeonById(id)
    for _, d in ipairs(M.Dungeons) do
        if d.id == id then return d end
    end
    return nil
end

-- 秘境事件池: 每个秘境 6 个事件, 进入时随机抽 3 个
-- 选项类型: risk(60%成功/中奖励/轻惩罚), safe(100%安全/低奖励), gamble(30%成功/超高奖励/中惩罚)
-- 平衡原则: 三选项期望收益接近, gamble高方差, risk中等, safe保底
-- 奖励格式: { key = {min, max} }, key 可为 lingshi/xiuwei/lingcao/lingzhi/xuantie
M.DungeonEvents = {
    lingcao = {
        {
            desc = "发现一个散发灵气的宝箱",
            choices = {
                { text = "打开宝箱", type = "risk", successRate = 0.6,
                  success = { lingcao = {60, 120} }, fail = { lingshi = {-20, -40} } },
                { text = "绕道而行", type = "safe", successRate = 1.0,
                  success = { lingcao = {15, 30} }, fail = {} },
                { text = "强行闯关", type = "gamble", successRate = 0.3,
                  success = { lingcao = {150, 240} }, fail = { lingshi = {-30, -50} } },
            },
        },
        {
            desc = "遇到一片灵草丛, 但有毒雾笼罩",
            choices = {
                { text = "冒险采摘", type = "risk", successRate = 0.6,
                  success = { lingcao = {75, 135} }, fail = { lingshi = {-15, -35} } },
                { text = "在外围采集", type = "safe", successRate = 1.0,
                  success = { lingcao = {24, 45} }, fail = {} },
                { text = "以灵力驱散毒雾", type = "gamble", successRate = 0.3,
                  success = { lingcao = {180, 300} }, fail = { lingshi = {-30, -50} } },
            },
        },
        {
            desc = "一只灵兽守护着珍稀灵草",
            choices = {
                { text = "引开灵兽", type = "risk", successRate = 0.6,
                  success = { lingcao = {90, 150} }, fail = { lingshi = {-25, -50} } },
                { text = "采集周围散落的", type = "safe", successRate = 1.0,
                  success = { lingcao = {18, 36} }, fail = {} },
                { text = "驯服灵兽", type = "gamble", successRate = 0.3,
                  success = { lingcao = {210, 360}, xiuwei = {150, 300} }, fail = { lingshi = {-40, -60} } },
            },
        },
        {
            desc = "发现一处隐藏的灵泉",
            choices = {
                { text = "汲取灵泉", type = "risk", successRate = 0.6,
                  success = { lingcao = {60, 105}, xiuwei = {90, 180} }, fail = { lingshi = {-18, -35} } },
                { text = "在泉边打坐", type = "safe", successRate = 1.0,
                  success = { xiuwei = {60, 120} }, fail = {} },
                { text = "纵身跃入灵泉", type = "gamble", successRate = 0.3,
                  success = { lingcao = {240, 390}, xiuwei = {240, 450} }, fail = { lingshi = {-30, -50} } },
            },
        },
        {
            desc = "前方岔路, 左侧幽暗, 右侧明亮",
            choices = {
                { text = "走幽暗小路", type = "risk", successRate = 0.6,
                  success = { lingcao = {90, 165} }, fail = { lingshi = {-20, -40} } },
                { text = "走明亮大路", type = "safe", successRate = 1.0,
                  success = { lingcao = {15, 30} }, fail = {} },
                { text = "两条路都探索", type = "gamble", successRate = 0.3,
                  success = { lingcao = {180, 270} }, fail = { lingshi = {-30, -50} } },
            },
        },
        {
            desc = "遇到一位受伤的散修",
            choices = {
                { text = "帮助疗伤换取情报", type = "risk", successRate = 0.6,
                  success = { lingcao = {75, 135}, xiuwei = {60, 120} }, fail = { lingshi = {-15, -30} } },
                { text = "礼貌告辞", type = "safe", successRate = 1.0,
                  success = { xiuwei = {30, 60} }, fail = {} },
                { text = "结伴探索", type = "gamble", successRate = 0.3,
                  success = { lingcao = {150, 240}, lingshi = {150, 300} }, fail = { lingshi = {-30, -50} } },
            },
        },
    },

    liandan = {
        {
            desc = "发现一座残破的丹房",
            choices = {
                { text = "搜索丹房", type = "risk", successRate = 0.6,
                  success = { lingshi = {300, 600}, xiuwei = {240, 450} }, fail = { lingshi = {-60, -100} } },
                { text = "在外围拾取", type = "safe", successRate = 1.0,
                  success = { lingshi = {90, 180} }, fail = {} },
                { text = "启动丹房阵法", type = "gamble", successRate = 0.3,
                  success = { lingshi = {900, 1500}, xiuwei = {450, 900} }, fail = { lingshi = {-80, -120} } },
            },
        },
        {
            desc = "石壁上刻有古老的丹方",
            choices = {
                { text = "用心参悟", type = "risk", successRate = 0.6,
                  success = { xiuwei = {450, 750} }, fail = { lingshi = {-40, -80} } },
                { text = "抄录要点", type = "safe", successRate = 1.0,
                  success = { xiuwei = {120, 240} }, fail = {} },
                { text = "以神识强行铭记", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {900, 1500} }, fail = { lingshi = {-60, -120} } },
            },
        },
        {
            desc = "一个密封的药柜散发异香",
            choices = {
                { text = "小心开启", type = "risk", successRate = 0.6,
                  success = { lingzhi = {45, 90}, lingshi = {240, 450} }, fail = { lingshi = {-50, -90} } },
                { text = "只取外层", type = "safe", successRate = 1.0,
                  success = { lingzhi = {15, 30} }, fail = {} },
                { text = "全部取走", type = "gamble", successRate = 0.3,
                  success = { lingzhi = {90, 180}, lingshi = {450, 900} }, fail = { lingshi = {-80, -120} } },
            },
        },
        {
            desc = "洞府深处传来低沉轰鸣",
            choices = {
                { text = "谨慎前进", type = "risk", successRate = 0.6,
                  success = { lingshi = {360, 660}, xuantie = {15, 30} }, fail = { lingshi = {-70, -120} } },
                { text = "在原地等待", type = "safe", successRate = 1.0,
                  success = { lingshi = {60, 150} }, fail = {} },
                { text = "冲入查看", type = "gamble", successRate = 0.3,
                  success = { lingshi = {750, 1350}, xuantie = {30, 75} }, fail = { lingshi = {-80, -120} } },
            },
        },
        {
            desc = "遇到一位炼丹傀儡仍在运作",
            choices = {
                { text = "观察学习", type = "risk", successRate = 0.6,
                  success = { xiuwei = {360, 600} }, fail = { lingshi = {-35, -70} } },
                { text = "安全绕行", type = "safe", successRate = 1.0,
                  success = { xiuwei = {90, 180} }, fail = {} },
                { text = "尝试控制傀儡", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {750, 1200}, lingshi = {300, 600} }, fail = { lingshi = {-60, -120} } },
            },
        },
        {
            desc = "一池灵液缓缓冒泡",
            choices = {
                { text = "取灵液一瓶", type = "risk", successRate = 0.6,
                  success = { lingshi = {240, 480}, lingcao = {30, 60} }, fail = { lingshi = {-40, -80} } },
                { text = "在池边修炼", type = "safe", successRate = 1.0,
                  success = { xiuwei = {150, 270} }, fail = {} },
                { text = "饮用灵液", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {600, 1050}, lingshi = {300, 750} }, fail = { lingshi = {-60, -120} } },
            },
        },
    },

    wanbao = {
        {
            desc = "一间藏宝室大门半开",
            choices = {
                { text = "推门进入", type = "risk", successRate = 0.6,
                  success = { lingshi = {900, 1800}, lingcao = {60, 120} }, fail = { lingshi = {-150, -300} } },
                { text = "只看门口", type = "safe", successRate = 1.0,
                  success = { lingshi = {150, 300} }, fail = {} },
                { text = "破阵闯入", type = "gamble", successRate = 0.3,
                  success = { lingshi = {2400, 4500}, xuantie = {45, 90}, gaoji_lingcao = {1, 2} }, fail = { lingshi = {-200, -350} } },
            },
        },
        {
            desc = "发现一面镶满灵石的墙壁",
            choices = {
                { text = "仔细撬取", type = "risk", successRate = 0.6,
                  success = { lingshi = {1200, 2100} }, fail = { lingshi = {-180, -320} } },
                { text = "取几颗外露的", type = "safe", successRate = 1.0,
                  success = { lingshi = {240, 450} }, fail = {} },
                { text = "以法力震碎墙壁", type = "gamble", successRate = 0.3,
                  success = { lingshi = {3000, 6000}, jinglian_lingzhi = {1, 2} }, fail = { lingshi = {-200, -350} } },
            },
        },
        {
            desc = "一只巨大的石像手中握着宝物",
            choices = {
                { text = "巧取宝物", type = "risk", successRate = 0.6,
                  success = { xuantie = {45, 90}, lingshi = {600, 1200} }, fail = { lingshi = {-200, -350} } },
                { text = "研究石像获取灵感", type = "safe", successRate = 1.0,
                  success = { xiuwei = {180, 360} }, fail = {} },
                { text = "击碎石像", type = "gamble", successRate = 0.3,
                  success = { xuantie = {90, 180}, lingshi = {1500, 3000}, gaoji_lingcao = {1, 3} }, fail = { lingshi = {-250, -400} } },
            },
        },
        {
            desc = "遇到一个传送阵仍有微弱光芒",
            choices = {
                { text = "激活传送阵", type = "risk", successRate = 0.6,
                  success = { lingshi = {1050, 1950}, lingcao = {45, 90} }, fail = { lingshi = {-150, -250} } },
                { text = "研究阵法纹路", type = "safe", successRate = 1.0,
                  success = { xiuwei = {150, 300} }, fail = {} },
                { text = "注入全部灵力", type = "gamble", successRate = 0.3,
                  success = { lingshi = {2400, 4500}, lingzhi = {60, 120}, lingcao = {60, 120} }, fail = { lingshi = {-200, -350} } },
            },
        },
        {
            desc = "一排玉简整齐排列在石架上",
            choices = {
                { text = "逐个翻阅", type = "risk", successRate = 0.6,
                  success = { xiuwei = {600, 1050} }, fail = { lingshi = {-100, -200} } },
                { text = "取走一枚", type = "safe", successRate = 1.0,
                  success = { xiuwei = {120, 240} }, fail = {} },
                { text = "以神识全部吸收", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {1500, 2400} }, fail = { lingshi = {-200, -350} } },
            },
        },
        {
            desc = "一堆矿石散落在地面",
            choices = {
                { text = "挑选精华", type = "risk", successRate = 0.6,
                  success = { xuantie = {60, 105}, lingshi = {300, 600} }, fail = { lingshi = {-100, -200} } },
                { text = "随手捡几块", type = "safe", successRate = 1.0,
                  success = { xuantie = {15, 30} }, fail = {} },
                { text = "全部收入囊中", type = "gamble", successRate = 0.3,
                  success = { xuantie = {120, 210}, lingshi = {900, 1800} }, fail = { lingshi = {-200, -350} } },
            },
        },
    },

    tianjie = {
        {
            desc = "一道残留的天劫雷弧挡在前方",
            choices = {
                { text = "趁间隙穿过", type = "risk", successRate = 0.6,
                  success = { lingshi = {2400, 4500}, xiuwei = {900, 1500}, hantie_ding = {0, 1} }, fail = { lingshi = {-350, -700} } },
                { text = "等雷弧消散", type = "safe", successRate = 1.0,
                  success = { xiuwei = {240, 450} }, fail = {} },
                { text = "以身试雷淬体", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {2400, 4500}, lingshi = {1500, 3000}, hantie_ding = {1, 2} }, fail = { lingshi = {-400, -800} } },
            },
        },
        {
            desc = "发现渡劫失败者的储物袋",
            choices = {
                { text = "打开储物袋", type = "risk", successRate = 0.6,
                  success = { lingshi = {3000, 6000}, xuantie = {60, 120} }, fail = { lingshi = {-400, -800} } },
                { text = "默念超度后取走", type = "safe", successRate = 1.0,
                  success = { lingshi = {300, 600} }, fail = {} },
                { text = "吸收残留灵力", type = "gamble", successRate = 0.3,
                  success = { lingshi = {6000, 12000}, xiuwei = {1500, 2400}, jinglian_lingzhi = {1, 2} }, fail = { lingshi = {-500, -900} } },
            },
        },
        {
            desc = "一面天劫碎片悬浮在空中",
            choices = {
                { text = "小心收取", type = "risk", successRate = 0.6,
                  success = { xuantie = {75, 150}, xiuwei = {600, 1200}, gaoji_lingcao = {0, 1} }, fail = { lingshi = {-500, -1000} } },
                { text = "远距离观察", type = "safe", successRate = 1.0,
                  success = { xiuwei = {300, 600} }, fail = {} },
                { text = "以自身灵力融合", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {3000, 6000}, lingshi = {3000, 6000}, hantie_ding = {1, 3} }, fail = { lingshi = {-500, -900} } },
            },
        },
        {
            desc = "遗迹深处一尊金身法相完好无损",
            choices = {
                { text = "叩拜参悟", type = "risk", successRate = 0.6,
                  success = { xiuwei = {1200, 2100} }, fail = { lingshi = {-300, -600} } },
                { text = "默默观瞻", type = "safe", successRate = 1.0,
                  success = { xiuwei = {240, 480} }, fail = {} },
                { text = "尝试继承法相", type = "gamble", successRate = 0.3,
                  success = { xiuwei = {3600, 6000}, lingshi = {2400, 4500}, tianling_ye = {0, 1} }, fail = { lingshi = {-500, -900} } },
            },
        },
        {
            desc = "一团混沌灵气凝聚成珠",
            choices = {
                { text = "炼化灵珠", type = "risk", successRate = 0.6,
                  success = { lingshi = {3600, 6600}, lingcao = {90, 150} }, fail = { lingshi = {-500, -900} } },
                { text = "取少许灵气", type = "safe", successRate = 1.0,
                  success = { lingshi = {360, 750} }, fail = {} },
                { text = "吞噬灵珠", type = "gamble", successRate = 0.3,
                  success = { lingshi = {9000, 15000}, xiuwei = {1500, 3000}, gaoji_lingcao = {2, 4} }, fail = { lingshi = {-600, -1000} } },
            },
        },
        {
            desc = "遗迹出口处有一座残破祭坛",
            choices = {
                { text = "献上灵石祭拜", type = "risk", successRate = 0.6,
                  success = { xiuwei = {1500, 2700}, lingcao = {60, 120}, jinglian_lingzhi = {0, 1} }, fail = { lingshi = {-350, -600} } },
                { text = "直接离开", type = "safe", successRate = 1.0,
                  success = { lingshi = {240, 480} }, fail = {} },
                { text = "夺取祭坛核心", type = "gamble", successRate = 0.3,
                  success = { lingshi = {7500, 13500}, xiuwei = {1800, 3600}, tianling_ye = {0, 1} }, fail = { lingshi = {-600, -1000} } },
            },
        },
    },

    -- 法宝秘境: 以高级材料为主要掉落
    fabao = {
        {
            desc = "一座远古炼器炉散发着炽热灵光",
            choices = {
                { text = "尝试开炉取材", type = "risk", successRate = 0.6,
                  success = { gaoji_lingcao = {2, 4}, hantie_ding = {1, 3}, lingshi = {2000, 4000} }, fail = { lingshi = {-500, -800} } },
                { text = "在炉旁吸取余温", type = "safe", successRate = 1.0,
                  success = { gaoji_lingcao = {1, 2}, lingshi = {500, 1000} }, fail = {} },
                { text = "灌注灵力重启炼器炉", type = "gamble", successRate = 0.3,
                  success = { gaoji_lingcao = {4, 8}, hantie_ding = {3, 6}, lingshi = {5000, 8000} }, fail = { lingshi = {-600, -1000} } },
            },
        },
        {
            desc = "发现一面蕴含灵纹的古老法阵",
            choices = {
                { text = "解析灵纹收集残片", type = "risk", successRate = 0.6,
                  success = { jinglian_lingzhi = {2, 4}, gaoji_lingcao = {1, 2}, xiuwei = {600, 1200} }, fail = { lingshi = {-400, -700} } },
                { text = "临摹部分纹路", type = "safe", successRate = 1.0,
                  success = { jinglian_lingzhi = {1, 2}, xiuwei = {300, 600} }, fail = {} },
                { text = "强行破解法阵", type = "gamble", successRate = 0.3,
                  success = { jinglian_lingzhi = {4, 8}, hantie_ding = {2, 4}, lingshi = {4000, 7000} }, fail = { lingshi = {-600, -1000} } },
            },
        },
        {
            desc = "一堆寒铁矿脉在洞壁中隐隐发光",
            choices = {
                { text = "精心开采", type = "risk", successRate = 0.6,
                  success = { hantie_ding = {2, 5}, xuantie = {60, 120}, lingshi = {1500, 3000} }, fail = { lingshi = {-500, -900} } },
                { text = "捡拾散落碎片", type = "safe", successRate = 1.0,
                  success = { hantie_ding = {1, 2}, xuantie = {20, 40} }, fail = {} },
                { text = "以法力爆破矿脉", type = "gamble", successRate = 0.3,
                  success = { hantie_ding = {5, 10}, xuantie = {100, 200}, lingshi = {3000, 6000} }, fail = { lingshi = {-700, -1200} } },
            },
        },
        {
            desc = "一个封印的玉瓶悬浮在结界中央",
            choices = {
                { text = "小心解除封印", type = "risk", successRate = 0.6,
                  success = { tianling_ye = {1, 2}, gaoji_lingcao = {2, 3}, lingshi = {3000, 5000} }, fail = { lingshi = {-600, -1000} } },
                { text = "从结界缝隙取灵气", type = "safe", successRate = 1.0,
                  success = { gaoji_lingcao = {1, 2}, jinglian_lingzhi = {1, 2} }, fail = {} },
                { text = "强行破碎结界", type = "gamble", successRate = 0.3,
                  success = { tianling_ye = {2, 4}, gaoji_lingcao = {3, 6}, lingshi = {6000, 10000} }, fail = { lingshi = {-800, -1500} } },
            },
        },
        {
            desc = "一位炼器大师的残魂守护着工坊",
            choices = {
                { text = "恭敬求教", type = "risk", successRate = 0.6,
                  success = { hantie_ding = {2, 4}, jinglian_lingzhi = {2, 3}, xiuwei = {1000, 2000} }, fail = { lingshi = {-400, -700} } },
                { text = "远处观摩", type = "safe", successRate = 1.0,
                  success = { hantie_ding = {1, 2}, xiuwei = {500, 1000} }, fail = {} },
                { text = "试图继承残魂记忆", type = "gamble", successRate = 0.3,
                  success = { hantie_ding = {4, 8}, tianling_ye = {1, 3}, xiuwei = {2000, 4000} }, fail = { lingshi = {-700, -1200} } },
            },
        },
        {
            desc = "秘境深处一座天灵池散发璀璨光芒",
            choices = {
                { text = "汲取天灵池精华", type = "risk", successRate = 0.6,
                  success = { tianling_ye = {1, 3}, lingshi = {4000, 7000} }, fail = { lingshi = {-600, -1000} } },
                { text = "在池边冥想", type = "safe", successRate = 1.0,
                  success = { tianling_ye = {0, 1}, gaoji_lingcao = {1, 2}, xiuwei = {500, 1000} }, fail = {} },
                { text = "纵身跃入天灵池", type = "gamble", successRate = 0.3,
                  success = { tianling_ye = {3, 6}, gaoji_lingcao = {4, 8}, lingshi = {8000, 15000} }, fail = { lingshi = {-1000, -2000} } },
            },
        },
    },
}

-- ========== 讨价还价配置 ==========

M.BargainConfig = {
    bargainChance = 0.30, -- 顾客可讨价概率(30%)
    timeout      = 3.0,   -- 讨价还价按钮显示时间(秒)
    barSpeed     = 1.2,   -- 进度条来回速度(秒/周期)
    maxAttempts  = 3,     -- 每个顾客最多讨价次数
    speedUpPerAttempt = 1.3,  -- 每次加速倍率
    zones = {
        -- 从左到右区域: 降价(10%) | 原价(15%) | +20%(20%) | +50%(10%) | +20%(20%) | 原价(15%) | 降价(10%)
        { id = "bad",     size = 0.10, mul = 0.85, label = "-15%",  refuseChance = 0.30 },
        { id = "normal",  size = 0.15, mul = 1.00, label = "原价" },
        { id = "good",    size = 0.20, mul = 1.20, label = "+20%" },
        { id = "perfect", size = 0.10, mul = 1.50, label = "+50%" },
        { id = "good2",   size = 0.20, mul = 1.20, label = "+20%" },
        { id = "normal2", size = 0.15, mul = 1.00, label = "原价" },
        { id = "bad2",    size = 0.10, mul = 0.85, label = "-15%",  refuseChance = 0.30 },
    },
}

--- 根据 hitPosition(0~1) 计算讨价还价倍率
---@param hitPos number 0.0~1.0
---@return number multiplier, string zoneId, table zone
function M.GetBargainResult(hitPos)
    hitPos = math.max(0, math.min(1, hitPos))
    local accum = 0
    for _, zone in ipairs(M.BargainConfig.zones) do
        accum = accum + zone.size
        if hitPos <= accum then
            return zone.mul, zone.id, zone
        end
    end
    -- fallback
    local last = M.BargainConfig.zones[#M.BargainConfig.zones]
    return last.mul, last.id, last
end

-- ========== 材料合成配置 ==========

M.SynthesisRecipes = {
    {
        id = "gaoji_lingcao",
        name = "高级灵草",
        icon = "lingcao",   -- 复用基础材料图标(带标记)
        inputs = { { id = "lingcao", amount = 10 } },
        output = { id = "gaoji_lingcao", amount = 1 },
        unlockRealm = 3,  -- 金丹期
    },
    {
        id = "jinglian_lingzhi",
        name = "精炼灵纸",
        icon = "lingzhi",
        inputs = { { id = "lingzhi", amount = 10 } },
        output = { id = "jinglian_lingzhi", amount = 1 },
        unlockRealm = 3,
    },
    {
        id = "hantie_ding",
        name = "寒铁锭",
        icon = "xuantie",
        inputs = { { id = "xuantie", amount = 10 } },
        output = { id = "hantie_ding", amount = 1 },
        unlockRealm = 4,  -- 元婴期
    },
    {
        id = "tianling_ye",
        name = "天灵液",
        icon = "lingcao",
        inputs = {
            { id = "gaoji_lingcao", amount = 3 },
            { id = "jinglian_lingzhi", amount = 3 },
        },
        output = { id = "tianling_ye", amount = 1 },
        unlockRealm = 5,  -- 化神期
    },
}

--- 根据合成配方 id 获取配方
---@param id string
---@return table|nil
function M.GetSynthesisRecipeById(id)
    for _, recipe in ipairs(M.SynthesisRecipes) do
        if recipe.id == id then return recipe end
    end
    return nil
end

-- ========== 每日任务配置 ==========

M.DailyTaskPool = {
    {
        type = "sell_count",
        desc = "今日售出 %d 件商品",
        baseTarget = 20,
        realmScale = 5,     -- 每境界+5
        reward = { lingshi = 1000 },
        rewardScale = 0.3,  -- 每境界奖励+30%
    },
    {
        type = "craft_count",
        desc = "制作 %d 件商品",
        baseTarget = 10,
        realmScale = 3,
        reward = { xiuwei = 400 },
        rewardScale = 0.3,
    },
    {
        type = "earn_lingshi",
        desc = "今日赚取 %d 灵石",
        baseTarget = 1500,
        realmScale = 500,
        reward = { lingcao = 60 },
        rewardScale = 0.3,
    },
    {
        type = "harvest",
        desc = "收获灵田 %d 次",
        baseTarget = 3,
        realmScale = 1,
        reward = { lingzhi = 40 },
        rewardScale = 0.3,
    },
    {
        type = "encounter",
        desc = "触发 %d 次奇遇",
        baseTarget = 2,
        realmScale = 0,
        reward = { lingshi = 600 },
        rewardScale = 0.3,
    },
    {
        type = "bargain_win",
        desc = "讨价还价成功 %d 次",
        baseTarget = 3,
        realmScale = 0,
        reward = { xiuwei = 300 },
        rewardScale = 0.3,
    },
}

M.DAILY_TASK_COUNT = 4  -- 每日刷新任务数量

--- 生成每日任务列表(服务端调用)
---@param realmLevel number
---@return table[] tasks
function M.GenerateDailyTasks(realmLevel)
    -- 从池中随机抽取不重复的任务
    local pool = {}
    for i, t in ipairs(M.DailyTaskPool) do
        table.insert(pool, i)
    end
    local count = math.min(M.DAILY_TASK_COUNT, #pool)
    local tasks = {}
    for _ = 1, count do
        local idx = math.random(1, #pool)
        local taskDef = M.DailyTaskPool[pool[idx]]
        local target = taskDef.baseTarget + taskDef.realmScale * (realmLevel - 1)
        local rewardMul = 1.0 + taskDef.rewardScale * (realmLevel - 1)
        local reward = {}
        for k, v in pairs(taskDef.reward) do
            reward[k] = math.floor(v * rewardMul)
        end
        table.insert(tasks, {
            type = taskDef.type,
            desc = string.format(taskDef.desc, target),
            target = target,
            current = 0,
            claimed = false,
            reward = reward,
        })
        table.remove(pool, idx)
    end
    return tasks
end

-- ========== 口碑系统配置 ==========

M.ReputationLevels = {
    { threshold = 0,   name = "无名小摊", color = M.Colors.textSecond, custBonus = {},                              priceBonus = 0 },
    { threshold = 100, name = "小有名气", color = M.Colors.jade,       custBonus = { zongmen = 3 },                 priceBonus = 0 },
    { threshold = 300, name = "远近闻名", color = M.Colors.blue,       custBonus = { zongmen = 5, guike = 2 },      priceBonus = 0 },
    { threshold = 600, name = "仙坊名店", color = M.Colors.purple,     custBonus = { zongmen = 8, guike = 4 },      priceBonus = 0.05 },
    { threshold = 900, name = "天下第一", color = M.Colors.textGold,   custBonus = { zongmen = 10, guike = 6 },     priceBonus = 0.10 },
}

M.ReputationGain = {
    matched    = 5,    -- 满足需求匹配
    unmatched  = 1,    -- 未匹配但购买
    timeout    = -10,  -- 顾客超时离开
    streakAt   = 5,    -- 连续满足N次触发连击
    streakBonus = 20,  -- 连击额外奖励
}

M.REPUTATION_MAX = 1000

--- 根据口碑值获取当前口碑等级
---@param reputation number
---@return table level {threshold, name, custBonus, priceBonus}
function M.GetReputationLevel(reputation)
    local result = M.ReputationLevels[1]
    for _, lvl in ipairs(M.ReputationLevels) do
        if reputation >= lvl.threshold then
            result = lvl
        end
    end
    return result
end

--- 根据口碑调整顾客类型权重
---@param reputation number
---@return table adjustedTypes 调整权重后的顾客类型列表副本
function M.GetReputationAdjustedWeights(reputation)
    local repLvl = M.GetReputationLevel(reputation)
    local adjusted = {}
    for _, ct in ipairs(M.CustomerTypes) do
        local w = ct.weight
        if repLvl.custBonus[ct.id] then
            w = w + repLvl.custBonus[ct.id]
        end
        table.insert(adjusted, { type = ct, weight = w })
    end
    return adjusted
end

--- 获取境界加成的售价倍率
---@param realmIndex number
---@return number multiplier
function M.GetRealmPriceMultiplier(realmIndex)
    local mul = 1.0
    if realmIndex >= 2 then mul = mul + 0.10 end  -- 筑基 +10%
    if realmIndex >= 5 then mul = mul + 0.20 end  -- 化神 +20%
    return mul
end

--- 获取境界加成的客流速度倍率
---@param realmIndex number
---@return number multiplier
function M.GetRealmSpeedMultiplier(realmIndex)
    local mul = 1.0
    if realmIndex >= 3 then mul = mul * 1.15 end  -- 金丹 +15%
    if realmIndex >= 8 then mul = mul * 1.35 end  -- 大乘 +35%
    return mul
end

--- 计算商品是否已解锁
---@param productIndex number
---@param realmIndex number
---@return boolean
function M.IsProductUnlocked(productIndex, realmIndex)
    return realmIndex >= M.Products[productIndex].unlockRealm
end

--- 根据权重随机选取顾客类型
---@return table customerType
function M.RandomCustomerType()
    local totalWeight = 0
    for _, ct in ipairs(M.CustomerTypes) do
        totalWeight = totalWeight + ct.weight
    end
    local roll = math.random() * totalWeight
    local accum = 0
    for _, ct in ipairs(M.CustomerTypes) do
        accum = accum + ct.weight
        if roll <= accum then
            return ct
        end
    end
    return M.CustomerTypes[1]
end

--- 根据顾客类型 id 获取顾客类型配置
---@param id string
---@return table|nil
function M.GetCustomerTypeById(id)
    for _, ct in ipairs(M.CustomerTypes) do
        if ct.id == id then return ct end
    end
    return nil
end

--- 根据材料 id 获取材料配置
---@param id string
---@return table|nil
function M.GetMaterialById(id)
    for _, mat in ipairs(M.Materials) do
        if mat.id == id then return mat end
    end
    return nil
end

--- 根据商品 id 获取商品配置
---@param id string
---@return table|nil
function M.GetProductById(id)
    for _, prod in ipairs(M.Products) do
        if prod.id == id then return prod end
    end
    return nil
end

-- ========== 称号系统 ==========

--- 境界称号: 达到对应境界即可永久获得, 转生不丢失
--- bonus: 灵石收入加成百分比
M.RealmTitles = {
    -- realmIndex = 1 炼气 无称号
    [2] = { title = "筑基修士", bonus = 0.01, color = { 160, 200, 160, 255 } },
    [3] = { title = "金丹真人", bonus = 0.02, color = { 220, 200, 100, 255 } },
    [4] = { title = "元婴尊者", bonus = 0.03, color = { 170, 140, 220, 255 } },
    [5] = { title = "化神大能", bonus = 0.04, color = { 100, 180, 240, 255 } },
    [6] = { title = "炼虚上人", bonus = 0.05, color = { 80, 220, 180, 255 } },
    [7] = { title = "合体老祖", bonus = 0.06, color = { 240, 160, 80, 255 } },
    [8] = { title = "大乘真君", bonus = 0.07, color = { 230, 100, 100, 255 } },
    [9] = { title = "渡劫仙人", bonus = 0.08, color = { 255, 215, 0, 255 } },
}

--- 排行称号: 基于今日排行榜排名, 每日动态刷新
--- rank: 排名上限(<=), bonus: 灵石收入加成百分比
M.RankTitles = {
    { rank = 1,  title = "天命",  bonus = 0.05, color = { 255, 215, 0, 255 } },
    { rank = 3,  title = "先驱",  bonus = 0.03, color = { 200, 160, 255, 255 } },
    { rank = 10, title = "真人",  bonus = 0.02, color = { 100, 200, 255, 255 } },
    { rank = 30, title = "居士",  bonus = 0.01, color = { 180, 220, 180, 255 } },
}

-- ========== 法宝系统 ==========

--- 法宝配置表
--- bonus.type: "material_rate" 材料产出, "sell_price" 售价, "craft_speed" 制作速度,
---             "reputation" 口碑获取, "lifespan" 寿元消耗, "all" 全属性
M.Artifacts = {
    {
        id = "juling_fu",
        name = "聚灵符",
        desc = "蕴含天地灵气的符箓，佩戴后材料产出增加",
        bonus = { type = "material_rate", value = 0.02 },  -- +2%/级, 10级=20%
        recipe = { lingcao = 80, lingzhi = 50, xuantie = 30 },
        lingshiCost = 0,
        unlockRealm = 2,  -- 筑基期
        icon = "juling_fu",
    },
    {
        id = "zhaocai_yupei",
        name = "招财玉佩",
        desc = "招财进宝的玉佩，佩戴后商品售价提升",
        bonus = { type = "sell_price", value = 0.02 },  -- +2%/级, 10级=20%
        recipe = { gaoji_lingcao = 12, jinglian_lingzhi = 8, xuantie = 50 },
        lingshiCost = 3000,
        unlockRealm = 3,  -- 金丹期
        icon = "zhaocai_yupei",
    },
    {
        id = "tiangong_chui",
        name = "天工锤",
        desc = "传说中的神匠之锤，佩戴后制作速度加快",
        bonus = { type = "craft_speed", value = 0.03 },  -- +3%/级, 10级=30%
        recipe = { hantie_ding = 12, gaoji_lingcao = 20, jinglian_lingzhi = 15 },
        lingshiCost = 0,
        unlockRealm = 4,  -- 元婴期
        icon = "tiangong_chui",
    },
    {
        id = "koubei_lingpai",
        name = "口碑令牌",
        desc = "名商大贾的信物，佩戴后口碑获取大幅提升",
        bonus = { type = "reputation", value = 0.03 },  -- +3%/级, 10级=30%
        recipe = { jinglian_lingzhi = 20, hantie_ding = 15, tianling_ye = 5 },
        lingshiCost = 8000,
        unlockRealm = 5,  -- 化神期
        icon = "koubei_lingpai",
    },
    {
        id = "shiguang_shalou",
        name = "时光沙漏",
        desc = "封印了时光碎片的沙漏，佩戴后寿元消耗减缓",
        bonus = { type = "lifespan", value = 0.02 },  -- 每级-2%寿元消耗
        recipe = { tianling_ye = 12, hantie_ding = 20, gaoji_lingcao = 25 },
        lingshiCost = 0,
        unlockRealm = 6,  -- 炼虚期
        icon = "shiguang_shalou",
    },
    {
        id = "feisheng_yujian",
        name = "飞升玉简",
        desc = "记载飞升秘法的玉简，佩戴后全属性提升",
        bonus = { type = "all", value = 0.01 },  -- 每级全属性+1%
        recipe = { gaoji_lingcao = 40, jinglian_lingzhi = 40, hantie_ding = 35, tianling_ye = 30 },
        lingshiCost = 15000,
        unlockRealm = 8,  -- 大乘期
        icon = "feisheng_yujian",
    },
}

--- 法宝装备槽位解锁条件
M.ArtifactSlots = {
    { realm = 1, slots = 1 },  -- 初始1槽
    { realm = 2, slots = 2 },  -- 筑基期2槽
    { realm = 4, slots = 3 },  -- 元婴期3槽
}

-- ========== 法宝耐久系统 ==========
M.ArtifactDurability = {
    max = 100,              -- 最大耐久
    repairRatio = 0.2,      -- 修复消耗原配方材料的20%(向上取整)
    -- 按加成类型: 每N次对应行为扣1点耐久
    wearPerTrigger = {
        sell_price    = 15,  -- 每售出15件
        reputation    = 15,  -- 每售出15件
        material_rate = 15,  -- 每收获15次
        craft_speed   = 15,  -- 每制作完成15件
        lifespan      = 60,  -- 每60次寿命tick(约10分钟)
        all           = 15,  -- 全属性: 按售出计
    },
}

--- 获取当前境界可用装备槽数
---@param realmLevel number
---@return number
function M.GetArtifactSlotCount(realmLevel)
    local slots = 1
    for _, cfg in ipairs(M.ArtifactSlots) do
        if realmLevel >= cfg.realm then
            slots = cfg.slots
        end
    end
    return slots
end

--- 根据ID获取法宝配置
---@param artId string
---@return table|nil
function M.GetArtifactById(artId)
    for _, art in ipairs(M.Artifacts) do
        if art.id == artId then return art end
    end
    return nil
end

--- 获取法宝加成值（已装备法宝的总加成）
---@param equippedArtifacts table 已装备法宝列表 [{id, level}]
---@param bonusType string 加成类型
---@return number 总加成比例（如 0.18 表示 +18%）
function M.GetArtifactBonus(equippedArtifacts, bonusType)
    local total = 0
    for _, eq in ipairs(equippedArtifacts or {}) do
        -- 耐久为0时加成失效
        if (eq.durability or M.ArtifactDurability.max) > 0 then
            local art = M.GetArtifactById(eq.id)
            if art and art.bonus then
                local match = (art.bonus.type == bonusType) or (art.bonus.type == "all")
                if match then
                    local lvl = eq.level or 1
                    total = total + art.bonus.value * lvl
                end
            end
        end
    end
    return total
end

--- 获取法宝修复所需材料(原配方的20%，向上取整)
---@param artId string
---@return table|nil repairCost {matId = count, ...}, number|nil lingshiCost
function M.GetArtifactRepairCost(artId)
    local art = M.GetArtifactById(artId)
    if not art then return nil end
    local ratio = M.ArtifactDurability.repairRatio
    local cost = {}
    for matId, count in pairs(art.recipe) do
        cost[matId] = math.ceil(count * ratio)
    end
    local lingshi = math.ceil((art.lingshiCost or 0) * ratio)
    return cost, lingshi
end

--- 获取法宝耐久磨损触发阈值
---@param bonusType string
---@return number
function M.GetArtifactWearThreshold(bonusType)
    return M.ArtifactDurability.wearPerTrigger[bonusType] or 15
end

--- 根据历史最高境界获取境界称号
---@param highestRealm number 历史最高境界索引
---@return table|nil {title, bonus, color}
function M.GetRealmTitle(highestRealm)
    -- 从最高境界往下找
    for i = highestRealm, 2, -1 do
        if M.RealmTitles[i] then
            return M.RealmTitles[i]
        end
    end
    return nil
end

--- 根据今日排行名次获取排行称号
---@param rank number|nil 名次(1-based), nil表示未上榜
---@return table|nil {title, bonus, color}
function M.GetRankTitle(rank)
    if not rank then return nil end
    for _, rt in ipairs(M.RankTitles) do
        if rank <= rt.rank then
            return rt
        end
    end
    return nil
end

-- ========== 珍藏物品系统 ==========

--- 珍藏物品配置
--- type: "permanent" 永久(转生保留), "consumable" 消耗品
--- bonus: 永久类有效, type可为 "material_rate_X" "sell_price" "craft_speed" 等
--- effect: 消耗品使用效果描述
M.Collectibles = {
    -- 天劫遗迹掉落
    {
        id = "dujie_dan",
        name = "渡劫丹",
        desc = "蕴含天劫之力的丹药，突破时消耗，减少灵石花费10%",
        type = "consumable",
        effect = "breakthrough_discount",
        effectValue = 0.10,
        color = M.Colors.red,
        icon = "image/dungeon_tianjie.png",
    },
    {
        id = "pojing_dan",
        name = "破境丹",
        desc = "蕴含破境之力的丹药，使用后获得2000修为",
        type = "consumable",
        effect = "add_xiuwei",
        effectValue = 2000,
        color = M.Colors.orange,
        icon = "image/dungeon_tianjie.png",
    },
    -- 灵草秘境掉落
    {
        id = "juling_zhu",
        name = "聚灵珠",
        desc = "凝聚天地灵气的宝珠，永久提升灵草产量+5%",
        type = "permanent",
        bonus = { type = "material_rate_lingcao", value = 0.05 },
        color = M.Colors.jade,
        icon = "image/dungeon_lingcao.png",
    },
    {
        id = "lianzhi_gujuan",
        name = "炼纸古卷",
        desc = "记载炼纸秘法的古卷，永久提升灵纸产量+5%",
        type = "permanent",
        bonus = { type = "material_rate_lingzhi", value = 0.05 },
        color = { 200, 190, 130, 255 },
        icon = "image/dungeon_lingcao.png",
    },
    -- 万宝秘藏掉落
    {
        id = "xuantie_ling",
        name = "玄铁令",
        desc = "上古铸器令牌，永久提升玄铁产量+5%",
        type = "permanent",
        bonus = { type = "material_rate_xuantie", value = 0.05 },
        color = { 150, 160, 180, 255 },
        icon = "image/dungeon_wanbao.png",
    },
    {
        id = "zhaocai_yuchan",
        name = "招财玉蟾",
        desc = "金蟾聚财宝物，永久提升顾客出价+3%",
        type = "permanent",
        bonus = { type = "sell_price", value = 0.03 },
        color = M.Colors.textGold,
        icon = "image/dungeon_wanbao.png",
    },
    -- 炼丹洞府掉落
    {
        id = "liandan_miji",
        name = "炼丹秘籍",
        desc = "丹道先贤的秘籍，永久提升制作速度+5%",
        type = "permanent",
        bonus = { type = "craft_speed", value = 0.05 },
        color = M.Colors.orange,
        icon = "image/dungeon_liandan.png",
    },
    {
        id = "xiao_huan_dan",
        name = "小还丹",
        desc = "延年益寿的灵丹，使用后+10寿元",
        type = "consumable",
        effect = "add_lifespan",
        effectValue = 10,
        color = M.Colors.green,
        icon = "image/dungeon_liandan.png",
    },
}

--- 根据ID获取珍藏物品配置
---@param itemId string
---@return table|nil
function M.GetCollectibleById(itemId)
    for _, c in ipairs(M.Collectibles) do
        if c.id == itemId then return c end
    end
    return nil
end

--- 秘境珍藏掉落表: 每个秘境结算时按概率掉落
M.DungeonDrops = {
    tianjie = {
        { id = "dujie_dan",  chance = 0.15 },
        { id = "pojing_dan", chance = 0.08 },
    },
    lingcao = {
        { id = "juling_zhu",      chance = 0.10 },
        { id = "lianzhi_gujuan",  chance = 0.10 },
    },
    wanbao = {
        { id = "xuantie_ling",    chance = 0.10 },
        { id = "zhaocai_yuchan",  chance = 0.08 },
    },
    liandan = {
        { id = "liandan_miji",    chance = 0.10 },
        { id = "xiao_huan_dan",   chance = 0.20 },
    },
}

--- 突破材料需求(仅高级境界需要额外材料)
--- 键为目标境界索引(突破后的境界)
M.BreakthroughMaterials = {
    [8] = {  -- 炼虚→大乘: 需渡劫丹x2
        { id = "dujie_dan", count = 2 },
    },
    [9] = {  -- 大乘→渡劫: 需渡劫丹x5 + 破境丹x3
        { id = "dujie_dan",  count = 5 },
        { id = "pojing_dan", count = 3 },
    },
}

-- ============ 渡劫小游戏配置 ============
M.DUJIE_MIN_REALM = 5       -- 化神(5)及以上需渡劫突破
M.DUJIE_FREE_ATTEMPTS = 3   -- 每日免费次数
M.DUJIE_MAX_PAID = 3        -- 每日最多付费次数
M.DUJIE_HP = 3              -- 生命值(被击中次数)

--- 渡劫难度配置
--- tier = nextRealmLevel - DUJIE_MIN_REALM (6→tier1, 7→tier2, 8→tier3, 9→tier4)
M.DujieTiers = {
    [1] = {  -- 化神→炼虚
        name = "三九雷劫", totalBolts = 12, duration = 15,
        boltSpeed = 340, warningTime = 1.0, boltWidth = 40,
        playerSpeed = 300, retryCostBase = 100000,
    },
    [2] = {  -- 炼虚→合体
        name = "四九天劫", totalBolts = 16, duration = 20,
        boltSpeed = 400, warningTime = 0.8, boltWidth = 44,
        playerSpeed = 320, retryCostBase = 200000,
    },
    [3] = {  -- 合体→大乘
        name = "六九雷劫", totalBolts = 22, duration = 25,
        boltSpeed = 460, warningTime = 0.6, boltWidth = 48,
        playerSpeed = 340, retryCostBase = 400000,
    },
    [4] = {  -- 大乘→渡劫
        name = "九九天劫", totalBolts = 30, duration = 35,
        boltSpeed = 540, warningTime = 0.4, boltWidth = 52,
        playerSpeed = 360, retryCostBase = 800000,
    },
}

--- 获取珍藏物品的永久加成总值(所有已拥有的永久珍藏)
---@param collectibles table 玩家珍藏物品 {itemId = count}
---@param bonusType string 加成类型
---@return number 总加成比例
function M.GetCollectibleBonus(collectibles, bonusType)
    local total = 0
    for itemId, count in pairs(collectibles or {}) do
        if count > 0 then
            local cfg = M.GetCollectibleById(itemId)
            if cfg and cfg.type == "permanent" and cfg.bonus and cfg.bonus.type == bonusType then
                -- 只生效1个,不按数量叠加
                total = total + cfg.bonus.value
            end
        end
    end
    return total
end

--- 获取珍藏物品出售价格(灵石)
---@param itemId string
---@return number 出售价格(0表示不可出售)
function M.GetCollectibleSellPrice(itemId)
    local cfg = M.GetCollectibleById(itemId)
    if not cfg then return 0 end
    if cfg.type == "permanent" then
        -- 永久类: 按加成价值定价
        return cfg.sellPrice or 500
    else
        -- 消耗品: 固定价格
        return cfg.sellPrice or 200
    end
end

-- ========== 师徒系统配置 ==========
M.MentorConfig = {
    masterMinRealm      = 4,       -- 师父最低境界：元婴期(4)
    realmGap            = 2,       -- 师徒境界差要求（徒弟 <= 师父 - realmGap）
    maxDisciples        = 3,       -- 每人最多收3个徒弟
    discipleSpeedBonus  = 0.10,    -- 徒弟修炼速度 +10%
    masterShareRatio    = 0.10,    -- 师父获得徒弟修为的 10%
    inviteExpireSec     = 300,     -- 邀请有效期 5 分钟
    graduationRewardMaster   = 50000,  -- 出师奖励（师父）
    graduationRewardDisciple = 30000,  -- 出师奖励（徒弟）
}

-- ============================================================
-- 功能10+11: 渡劫Boss战 + 仙界摆摊系统追加配置
-- ============================================================

-- === 渡劫 Boss 战配置 ===
M.TribulationBoss = {
    maxHp        = 5,
    rounds       = 5,
    attackCost   = 50000,
    attackDmg    = 1,
    defendFabao  = 1,
    defendDmgMul = 0.5,
    normalDmgPct  = 0.15,
    heavyDmgPct   = 0.30,
    heavyChance   = 0.30,
    extraDmgPct   = 0.10,
    roundNames = { "初劫", "二劫", "三劫", "四劫", "终劫" },
    -- 难度增强：失败惩罚、豁命一击、随机天劫事件
    failPenaltyPct = 0.30,                           -- 失败扣30%当前灵石
    allInCostMul   = 3,                              -- 豁命一击费用倍率(3x)
    roundBossMul   = { 0.5, 0.75, 1.0, 1.5, 2.0 }, -- 各劫Boss反击伤害系数
    eventChance    = 0.60,                           -- 每轮触发随机事件概率
    events = {
        { id = "blessing",    name = "灵机乍现", desc = "本轮攻击伤害+50%",         dmgMul = 1.5 },
        { id = "double_cost", name = "法力枯竭", desc = "本轮攻击耗费灵石翻倍",     costMul = 2.0 },
        { id = "boss_heal",   name = "天劫蓄力", desc = "天劫恢复1点血量",           heal = 1 },
        { id = "calm",        name = "天地归寂", desc = "本轮天劫不反击",             noBossAtk = true },
        { id = "heavy_surge", name = "终劫怒潮", desc = "天劫重击概率提升至60%",     heavyChance = 0.60 },
    },
}

-- === 仙界境界 (接续凡间 M.Realms，追加索引 10-17) ===
M.Realms[10] = { name = "天仙",     xiuwei = 5400000,   lifespan = 999999, breakthroughCost = 0,          unlockDesc = "天仙丹/天蚕符" }
M.Realms[11] = { name = "真仙",     xiuwei = 9900000,   lifespan = 999999, breakthroughCost = 1500000,    unlockDesc = "星辰法器" }
M.Realms[12] = { name = "玄仙",     xiuwei = 18000000,  lifespan = 999999, breakthroughCost = 3000000,    unlockDesc = "玄仙灵丹/神罗天符" }
M.Realms[13] = { name = "金仙",     xiuwei = 32400000,  lifespan = 999999, breakthroughCost = 5000000,    unlockDesc = "金仙法宝" }
M.Realms[14] = { name = "太乙金仙", xiuwei = 58500000,  lifespan = 999999, breakthroughCost = 10000000,   unlockDesc = "太乙灵丹" }
M.Realms[15] = { name = "大罗金仙", xiuwei = 105000000, lifespan = 999999, breakthroughCost = 18000000,   unlockDesc = "万象神符" }
M.Realms[16] = { name = "准圣",     xiuwei = 189000000, lifespan = 999999, breakthroughCost = 30000000,   unlockDesc = "准圣法宝" }
M.Realms[17] = { name = "圣人",     xiuwei = 339000000, lifespan = 999999, breakthroughCost = 50000000,   unlockDesc = "混沌珠" }

-- === 仙界炼化比例 (接续 M.AbsorbConfig，索引10-17) ===
M.AbsorbConfig[10] = { ratio = 30,  amount = 1000 }  -- 天仙:   30,000灵石→1000修为
M.AbsorbConfig[11] = { ratio = 50,  amount = 1000 }  -- 真仙:   50,000灵石→1000修为
M.AbsorbConfig[12] = { ratio = 80,  amount = 1000 }  -- 玄仙:   80,000灵石→1000修为
M.AbsorbConfig[13] = { ratio = 120, amount = 1000 }  -- 金仙:  120,000灵石→1000修为
M.AbsorbConfig[14] = { ratio = 200, amount = 1000 }  -- 太乙:  200,000灵石→1000修为
M.AbsorbConfig[15] = { ratio = 300, amount = 1000 }  -- 大罗:  300,000灵石→1000修为
M.AbsorbConfig[16] = { ratio = 500, amount = 1000 }  -- 准圣:  500,000灵石→1000修为
M.AbsorbConfig[17] = { ratio = 800, amount = 1000 }  -- 圣人:  800,000灵石→1000修为

-- === 仙界材料 (追加至 M.Materials) ===
-- 基础材料（被动产出）
table.insert(M.Materials, {
    id = "lingjing_cao", name = "灵晶草", rate = 12, icon = "[晶草]",
    image = "lingjing_cao", color = { 100, 240, 180, 255 }, cap = 99999, celestial = true,
})
table.insert(M.Materials, {
    id = "tianchan_si", name = "天蚕丝", rate = 10, icon = "[蚕丝]",
    image = "tianchan_si", color = { 220, 200, 240, 255 }, cap = 99999, celestial = true,
})
table.insert(M.Materials, {
    id = "xingchen_kuang", name = "星辰矿", rate = 5, icon = "[星矿]",
    image = "xingchen_kuang", color = { 100, 160, 255, 255 }, cap = 99999, celestial = true,
})
-- 合成材料（rate=0，不自动产出）
table.insert(M.Materials, {
    id = "shanggu_lingjing", name = "上古灵晶", rate = 0, icon = "[古晶]",
    image = "shanggu_lingjing", color = { 180, 240, 220, 255 }, cap = 9999, celestial = true,
})
table.insert(M.Materials, {
    id = "tianchan_jinghua", name = "天蚕精华", rate = 0, icon = "[蚕华]",
    image = "tianchan_jinghua", color = { 240, 210, 255, 255 }, cap = 9999, celestial = true,
})
table.insert(M.Materials, {
    id = "xingchen_jinghua", name = "星辰精华", rate = 0, icon = "[星华]",
    image = "xingchen_jinghua", color = { 130, 180, 255, 255 }, cap = 9999, celestial = true,
})
table.insert(M.Materials, {
    id = "hundun_jing", name = "混沌晶", rate = 0, icon = "[混晶]",
    image = "hundun_jing", color = { 200, 200, 220, 255 }, cap = 999, celestial = true,
})

-- === 仙界合成配方 (追加至 M.SynthesisRecipes) ===
table.insert(M.SynthesisRecipes, { id = "shanggu_lingjing",  name = "上古灵晶",  inputs = {{ id="lingjing_cao",    amount=10 }},                                              output = { id="shanggu_lingjing",  amount=1 }, unlockRealm=12, time=30,  celestial=true })
table.insert(M.SynthesisRecipes, { id = "tianchan_jinghua",  name = "天蚕精华",  inputs = {{ id="tianchan_si",     amount=10 }},                                              output = { id="tianchan_jinghua",  amount=1 }, unlockRealm=12, time=30,  celestial=true })
table.insert(M.SynthesisRecipes, { id = "xingchen_jinghua",  name = "星辰精华",  inputs = {{ id="xingchen_kuang",  amount=10 }},                                              output = { id="xingchen_jinghua",  amount=1 }, unlockRealm=13, time=30,  celestial=true })
table.insert(M.SynthesisRecipes, { id = "hundun_jing",       name = "混沌晶",    inputs = {{ id="shanggu_lingjing", amount=3 }, { id="tianchan_jinghua", amount=3 }},        output = { id="hundun_jing",       amount=1 }, unlockRealm=14, time=60,  celestial=true })

-- === 仙界商品 (追加至 M.Products) ===
table.insert(M.Products, { id="tianxian_dan",    name="天仙丹",    materials={{ id="lingjing_cao",    count=8  }}, craftTime=10, price=2000,   unlockRealm=10, celestial=true, image="product_tianxian_dan",    color={ 120, 230, 180, 255 } })
table.insert(M.Products, { id="tianchan_fu",     name="天蚕符",    materials={{ id="tianchan_si",     count=6  }}, craftTime=10, price=2500,   unlockRealm=10, celestial=true, image="product_tianchan_fu",     color={ 200, 180, 100, 255 } })
table.insert(M.Products, { id="xingchen_faqi",   name="星辰法器",  materials={{ id="xingchen_kuang",  count=3  }}, craftTime=15, price=4000,   unlockRealm=11, celestial=true, image="product_xingchen_faqi",   color={ 160, 140, 220, 255 } })
table.insert(M.Products, { id="xuanxian_lingdan",name="玄仙灵丹",  materials={{ id="lingjing_cao",    count=15 }}, craftTime=15, price=7000,   unlockRealm=12, celestial=true, image="product_xuanxian_lingdan", color={ 100, 200, 255, 255 } })
table.insert(M.Products, { id="shenluo_fu",      name="神罗天符",  materials={{ id="tianchan_si",     count=12 }}, craftTime=15, price=10000,  unlockRealm=12, celestial=true, image="product_shenluo_fu",      color={ 255, 200, 100, 255 } })
table.insert(M.Products, { id="jinxian_fabao",   name="金仙法宝",  materials={{ id="xingchen_kuang",  count=10 }}, craftTime=20, price=18000,  unlockRealm=13, celestial=true, image="product_jinxian_fabao",   color={ 255, 180, 80, 255 }  })
table.insert(M.Products, { id="taiyi_lingdan",   name="太乙灵丹",  materials={{ id="shanggu_lingjing",count=2  }}, craftTime=20, price=32000,  unlockRealm=14, celestial=true, image="product_taiyi_lingdan",   color={ 230, 140, 255, 255 } })
table.insert(M.Products, { id="wanxiang_shenfu", name="万象神符",  materials={{ id="tianchan_jinghua",count=2  }}, craftTime=20, price=48000,  unlockRealm=15, celestial=true, image="product_wanxiang_shenfu", color={ 255, 220, 120, 255 } })
table.insert(M.Products, { id="zhunsheng_fabao", name="准圣法宝",  materials={{ id="xingchen_jinghua",count=2  }}, craftTime=25, price=75000,  unlockRealm=16, celestial=true, image="product_zhunsheng_fabao", color={ 255, 160, 160, 255 } })
table.insert(M.Products, { id="hundun_zhu",      name="混沌珠",    materials={{ id="hundun_jing",     count=1  }}, craftTime=40, price=130000, unlockRealm=17, celestial=true, image="product_hundun_zhu",      color={ 200, 180, 255, 255 } })

-- === 仙界秘境 (追加至 M.Dungeons) ===
table.insert(M.Dungeons, { id="xiancao",    name="仙草秘境", cost=500000,   unlockRealm=10, celestial=true, desc="蕴藏仙界灵草精华的秘境",         color={ 100, 230, 170, 255 }, icon="image/dungeon_xiancao.png"     })
table.insert(M.Dungeons, { id="fabao_xian", name="法宝秘境", cost=1500000,  unlockRealm=12, celestial=true, desc="蕴含仙界法宝精华的炼器秘地",      color={ 200, 160,  80, 255 }, icon="image/dungeon_fabao_xian.png"  })
table.insert(M.Dungeons, { id="hundun",     name="混沌秘境", cost=5000000,  unlockRealm=14, celestial=true, desc="开天辟地前的混沌遗迹，极度危险",   color={ 160, 140, 200, 255 }, icon="image/dungeon_hundun.png"      })

-- === 仙界秘境事件池 ===
-- 格式与凡间统一: choices/successRate/success/fail（fail 中 lingshi 取负值）
M.DungeonEvents.xiancao = {
    { name="灵晶草丛", desc="发现一片茂密的灵晶草", choices={
        { type="risk",   text="深入采集",  successRate=0.60, success={ lingjing_cao={800,1500} },    fail={ lingshi={-50000,-100000} } },
        { type="safe",   text="谨慎采摘",                    success={ lingjing_cao={400,700} } },
        { type="gamble", text="全力开采",  successRate=0.35, success={ lingjing_cao={2000,4000}, shengxian_dan={1,2} }, fail={ lingshi={-200000,-400000} } },
    }},
    { name="仙露结晶", desc="天降仙露凝结成晶", choices={
        { type="risk",   text="收集仙露",  successRate=0.65, success={ tianchan_si={600,1000} },     fail={ lingshi={-40000,-80000} } },
        { type="safe",   text="静待凝结",                    success={ lingjing_cao={300,500} } },
        { type="gamble", text="引导天机",  successRate=0.30, success={ tianchan_si={1500,3000}, shengxian_dan={1,3} }, fail={ lingshi={-300000,-600000} } },
    }},
    { name="升仙古树", desc="可摘取升仙丹的古树", choices={
        { type="risk",   text="攀爬采摘",  successRate=0.55, success={ shengxian_dan={1,2} },         fail={ lingshi={-100000,-200000} } },
        { type="safe",   text="捡拾落果",                    success={ lingjing_cao={500,800} } },
        { type="gamble", text="施法催熟",  successRate=0.30, success={ shengxian_dan={3,6} },         fail={ lingshi={-400000,-800000} } },
    }},
    { name="仙风呼啸", desc="仙风带来大量灵气", choices={
        { type="risk",   text="顺风采气",  successRate=0.70, success={ lingjing_cao={600,1200}, tianchan_si={300,600} }, fail={ lingshi={-60000,-120000} } },
        { type="safe",   text="原地修炼",                    success={ xiuwei={5000,10000} } },
        { type="gamble", text="驾风探索",  successRate=0.35, success={ lingjing_cao={2000,4000}, shengxian_dan={2,4} }, fail={ lingshi={-300000,-500000} } },
    }},
    { name="仙草药园", desc="一处无主的仙草药园", choices={
        { type="risk",   text="进入采集",  successRate=0.60, success={ lingjing_cao={1000,2000} },   fail={ lingshi={-80000,-150000} } },
        { type="safe",   text="在外摘取",                    success={ lingjing_cao={300,600} } },
        { type="gamble", text="秘法开锁",  successRate=0.30, success={ lingjing_cao={3000,6000}, shengxian_dan={2,5} }, fail={ lingshi={-500000,-1000000} } },
    }},
    { name="迷雾仙境", desc="迷雾深处藏有宝物", choices={
        { type="risk",   text="进入迷雾",  successRate=0.55, success={ tianchan_si={800,1600}, shengxian_dan={1,2} }, fail={ lingshi={-120000,-240000} } },
        { type="safe",   text="等待雾散",                    success={ lingjing_cao={400,700} } },
        { type="gamble", text="法眼破雾",  successRate=0.30, success={ shengxian_dan={4,8}, lingjing_cao={2000,4000} }, fail={ lingshi={-600000,-1200000} } },
    }},
}

M.DungeonEvents.fabao_xian = {
    { name="炼器台",   desc="散发法宝之气的古老炼器台", choices={
        { type="risk",   text="尝试激活",  successRate=0.55, success={ xingchen_kuang={600,1000} },   fail={ lingshi={-150000,-300000} } },
        { type="safe",   text="提取余气",                    success={ xingchen_kuang={200,400} } },
        { type="gamble", text="全力激活",  successRate=0.25, success={ jinxian_ling={1,2}, xingchen_kuang={2000,4000} }, fail={ lingshi={-800000,-1500000} } },
    }},
    { name="金仙遗物", desc="传说金仙留下的宝物", choices={
        { type="risk",   text="开启封印",  successRate=0.50, success={ jinxian_ling={1,3} },          fail={ lingshi={-200000,-400000} } },
        { type="safe",   text="解析法阵",                    success={ xingchen_kuang={400,800} } },
        { type="gamble", text="强行破封",  successRate=0.25, success={ jinxian_ling={3,6} },          fail={ lingshi={-1000000,-2000000} } },
    }},
    { name="星辰矿脉", desc="难得一见的星辰矿脉", choices={
        { type="risk",   text="挖掘矿脉",  successRate=0.65, success={ xingchen_kuang={800,1500} },   fail={ lingshi={-100000,-200000} } },
        { type="safe",   text="收集矿粒",                    success={ xingchen_kuang={300,600} } },
        { type="gamble", text="爆破开采",  successRate=0.30, success={ xingchen_kuang={3000,6000}, jinxian_ling={1,2} }, fail={ lingshi={-500000,-1000000} } },
    }},
    { name="法宝共鸣", desc="周围法宝产生共鸣震动", choices={
        { type="risk",   text="引导共鸣",  successRate=0.60, success={ xingchen_kuang={600,1200} },   fail={ lingshi={-150000,-300000} } },
        { type="safe",   text="收集法力",                    success={ xingchen_kuang={250,500} } },
        { type="gamble", text="融合法宝",  successRate=0.25, success={ jinxian_ling={2,5} },          fail={ lingshi={-1000000,-2000000} } },
    }},
    { name="仙铁矿山", desc="含有仙铁精华的山脉", choices={
        { type="risk",   text="深入开采",  successRate=0.55, success={ xingchen_kuang={1000,2000} },  fail={ lingshi={-200000,-400000} } },
        { type="safe",   text="表层采集",                    success={ xingchen_kuang={400,800} } },
        { type="gamble", text="灵力爆破",  successRate=0.25, success={ xingchen_kuang={4000,8000}, jinxian_ling={1,3} }, fail={ lingshi={-1000000,-2000000} } },
    }},
    { name="封印法阵", desc="古老封印法阵守护着宝物", choices={
        { type="risk",   text="破除封印",  successRate=0.50, success={ jinxian_ling={1,4}, xingchen_kuang={500,1000} }, fail={ lingshi={-300000,-600000} } },
        { type="safe",   text="分析法阵",                    success={ xingchen_kuang={300,600} } },
        { type="gamble", text="强攻法阵",  successRate=0.20, success={ jinxian_ling={4,8} },          fail={ lingshi={-1500000,-3000000} } },
    }},
}

M.DungeonEvents.hundun = {
    { name="混沌气流", desc="蕴含开天辟地能量的气流", choices={
        { type="risk",   text="吸收气流",     successRate=0.50, success={ xingchen_kuang={1000,2000}, lingjing_cao={500,1000} }, fail={ lingshi={-500000,-1000000} } },
        { type="safe",   text="借助气流修炼",                   success={ xiuwei={20000,40000} } },
        { type="gamble", text="引导混沌",     successRate=0.20, success={ honghuang_shi={1,2}, xingchen_kuang={5000,10000} },  fail={ lingshi={-3000000,-6000000} } },
    }},
    { name="洪荒遗迹", desc="洪荒时代的上古遗迹", choices={
        { type="risk",   text="探索遗迹",     successRate=0.45, success={ honghuang_shi={1,2} },                               fail={ lingshi={-800000,-1500000} } },
        { type="safe",   text="边缘观察",                       success={ xingchen_kuang={600,1200} } },
        { type="gamble", text="深入禁地",     successRate=0.20, success={ honghuang_shi={3,5} },                               fail={ lingshi={-5000000,-10000000} } },
    }},
    { name="开天裂缝", desc="开天时留下的空间裂缝", choices={
        { type="risk",   text="进入裂缝",     successRate=0.40, success={ honghuang_shi={1,3}, xingchen_kuang={1000,2000} },   fail={ lingshi={-1000000,-2000000} } },
        { type="safe",   text="收集裂缝能量",                   success={ xingchen_kuang={800,1600} } },
        { type="gamble", text="融合空间",     successRate=0.15, success={ honghuang_shi={4,8} },                               fail={ lingshi={-8000000,-15000000} } },
    }},
    { name="混沌宝矿", desc="混沌中孕育的上古宝矿", choices={
        { type="risk",   text="挖掘宝矿",     successRate=0.50, success={ honghuang_shi={1,2}, xingchen_kuang={1500,3000} },   fail={ lingshi={-1000000,-2000000} } },
        { type="safe",   text="采集外层",                       success={ xingchen_kuang={1000,2000} } },
        { type="gamble", text="混沌之力挖掘", successRate=0.20, success={ honghuang_shi={3,6}, xingchen_kuang={5000,10000} },  fail={ lingshi={-5000000,-10000000} } },
    }},
    { name="太初之源", desc="太初之气的源头", choices={
        { type="risk",   text="汲取太初之气", successRate=0.55, success={ lingjing_cao={2000,4000}, tianchan_si={1000,2000} }, fail={ lingshi={-800000,-1500000} } },
        { type="safe",   text="感悟太初",                       success={ xiuwei={50000,100000} } },
        { type="gamble", text="太初融合",     successRate=0.20, success={ honghuang_shi={2,4}, lingjing_cao={5000,10000} },    fail={ lingshi={-6000000,-12000000} } },
    }},
    { name="鸿蒙至宝", desc="传说中的鸿蒙宝物", choices={
        { type="risk",   text="尝试收取",     successRate=0.35, success={ honghuang_shi={2,4} },                               fail={ lingshi={-2000000,-4000000} } },
        { type="safe",   text="吸收外溢能量",                   success={ xingchen_kuang={1000,2000} } },
        { type="gamble", text="强取宝物",     successRate=0.15, success={ honghuang_shi={5,10} },                              fail={ lingshi={-10000000,-20000000} } },
    }},
}

-- === 仙界突破材料 (追加至 M.BreakthroughMaterials) ===
M.BreakthroughMaterials[11] = { { id="shengxian_dan", count=10 } }
M.BreakthroughMaterials[12] = { { id="shengxian_dan", count=24 } }
M.BreakthroughMaterials[13] = { { id="shengxian_dan", count=16 }, { id="jinxian_ling", count=6 } }
M.BreakthroughMaterials[14] = { { id="shengxian_dan", count=30 }, { id="jinxian_ling", count=16 } }
M.BreakthroughMaterials[15] = { { id="jinxian_ling",  count=30 }, { id="honghuang_shi", count=2 } }
M.BreakthroughMaterials[16] = { { id="jinxian_ling",  count=40 }, { id="honghuang_shi", count=8 } }
M.BreakthroughMaterials[17] = { { id="jinxian_ling",  count=60 }, { id="honghuang_shi", count=20 } }

-- === 3 种突破材料 + 8 件仙界珍藏/法宝 (追加至 M.Collectibles) ===
-- 突破材料（消耗品，秘境掉落）
table.insert(M.Collectibles, { id="shengxian_dan", name="升仙丹", type="consumable", effect="breakthrough_material", desc="凝聚仙灵之气，突破仙界初阶境界必需", color={255,215,100,255}, icon="image/shengxian_dan.png",  sellPrice=300000 })
table.insert(M.Collectibles, { id="jinxian_ling",  name="金仙令", type="consumable", effect="breakthrough_material", desc="上古金仙遗留令牌，突破金仙级境界必需", color={255,180, 50,255}, icon="image/jinxian_ling.png",   sellPrice=800000 })
table.insert(M.Collectibles, { id="honghuang_shi", name="洪荒石", type="consumable", effect="breakthrough_material", desc="开天辟地之石，准圣以上境界方能用",     color={180,160,240,255}, icon="image/honghuang_shi.png",  sellPrice=2000000 })
-- 永久珍藏（飞升后凡间秘境掉落）
table.insert(M.Collectibles, { id="xian_lingjing_pei", name="仙灵境佩", type="permanent", bonus={ type="material_rate_lingjing_cao", value=0.10 }, desc="仙界灵晶精华凝聚的玉佩，永久提升灵晶草产出+10%", color={ 100,230,180,255}, icon="image/xian_lingjing_pei.png", sellPrice=500000,  requireAscended=true })
table.insert(M.Collectibles, { id="tianchan_baohan",   name="天蚕宝函", type="permanent", bonus={ type="material_rate_tianchan_si",  value=0.10 }, desc="天蚕精丝织成的宝函，永久提升天蚕丝产出+10%",    color={ 220,200,255,255}, icon="image/tianchan_baohan.png",   sellPrice=500000,  requireAscended=true })
table.insert(M.Collectibles, { id="xingchen_lingjing", name="星辰灵晶", type="permanent", bonus={ type="material_rate_xingchen_kuang",value=0.10}, desc="天外陨星凝聚的灵晶，永久提升星辰矿产出+10%",    color={ 130,170,255,255}, icon="image/xingchen_lingjing.png", sellPrice=500000,  requireAscended=true })
table.insert(M.Collectibles, { id="xian_ding_jinghua", name="仙鼎精华", type="permanent", bonus={ type="sell_price_xian",            value=0.05 }, desc="上古仙鼎炼出的精华，永久提升仙界商品售价+5%",    color={ 255,160, 80,255}, icon="image/xian_ding_jinghua.png", sellPrice=800000,  requireAscended=true })
table.insert(M.Collectibles, { id="tianzun_danlu",     name="天尊丹炉", type="permanent", bonus={ type="craft_speed_xian",           value=0.08 }, desc="天尊遗留的丹炉，永久提升仙界制作速度+8%",        color={ 200,140, 80,255}, icon="image/tianzun_danlu.png",     sellPrice=800000,  requireAscended=true })
-- 消耗法宝（飞升后凡间秘境掉落，使用后增加法宝数量）
table.insert(M.Collectibles, { id="tian_jie_lingjian", name="天劫灵剑", type="consumable", effect="add_fabao_count", effectValue=3,  desc="天劫遗迹中获得的灵剑，使用后获得3个法宝",  color={180,220,255,255}, icon="image/tian_jie_lingjian.png", sellPrice=200000, requireAscended=true })
table.insert(M.Collectibles, { id="longwen_yupei",     name="龙纹玉佩", type="consumable", effect="add_fabao_count", effectValue=5,  desc="刻有龙纹的玉佩，使用后获得5个法宝",        color={100,200,150,255}, icon="image/longwen_yupei.png",     sellPrice=350000, requireAscended=true })
table.insert(M.Collectibles, { id="daozu_lingfu",      name="道祖灵符", type="consumable", effect="add_fabao_count", effectValue=10, desc="道祖亲书的灵符，使用后获得10个法宝",       color={255,220,120,255}, icon="image/daozu_lingfu.png",      sellPrice=600000, requireAscended=true })

-- === 仙界秘境掉落 (飞升后原有凡间秘境追加 requireAscended 条目) ===
M.DungeonDrops.lingcao[#M.DungeonDrops.lingcao+1] = { id="xian_lingjing_pei", chance=0.05, requireAscended=true }
M.DungeonDrops.lingcao[#M.DungeonDrops.lingcao+1] = { id="daozu_lingfu",      chance=0.03, requireAscended=true }
M.DungeonDrops.wanbao[#M.DungeonDrops.wanbao+1]   = { id="tianchan_baohan",   chance=0.04, requireAscended=true }
M.DungeonDrops.wanbao[#M.DungeonDrops.wanbao+1]   = { id="longwen_yupei",     chance=0.03, requireAscended=true }
M.DungeonDrops.tianjie[#M.DungeonDrops.tianjie+1] = { id="xingchen_lingjing", chance=0.04, requireAscended=true }
M.DungeonDrops.tianjie[#M.DungeonDrops.tianjie+1] = { id="tian_jie_lingjian", chance=0.04, requireAscended=true }
M.DungeonDrops.liandan[#M.DungeonDrops.liandan+1] = { id="xian_ding_jinghua", chance=0.04, requireAscended=true }
M.DungeonDrops.liandan[#M.DungeonDrops.liandan+1] = { id="tianzun_danlu",     chance=0.03, requireAscended=true }
-- 仙界专属秘境掉落
M.DungeonDrops.xiancao    = { { id="shengxian_dan", chance=0.12 }, { id="xian_lingjing_pei", chance=0.03, requireAscended=true }, { id="daozu_lingfu",  chance=0.02, requireAscended=true } }
M.DungeonDrops.fabao_xian = { { id="jinxian_ling",  chance=0.08 }, { id="tianchan_baohan",   chance=0.02, requireAscended=true }, { id="longwen_yupei", chance=0.02, requireAscended=true } }
M.DungeonDrops.hundun     = { { id="honghuang_shi", chance=0.05 }, { id="xingchen_lingjing", chance=0.02, requireAscended=true }, { id="tian_jie_lingjian", chance=0.02, requireAscended=true } }

-- === 仙界渡劫难度 (追加至 M.DujieTiers，tier 5 为凡间→渡劫，tier 6-12 为仙界) ===
M.DujieTiers[6]  = { name="一劫仙威", totalBolts=40,  duration=32, boltSpeed=600,  warningTime=0.35, boltWidth=50, playerSpeed=380, retryCostBase=1500000  }
M.DujieTiers[7]  = { name="二劫玄威", totalBolts=52,  duration=35, boltSpeed=660,  warningTime=0.30, boltWidth=52, playerSpeed=400, retryCostBase=3000000  }
M.DujieTiers[8]  = { name="三劫金威", totalBolts=65,  duration=38, boltSpeed=720,  warningTime=0.25, boltWidth=54, playerSpeed=420, retryCostBase=5000000  }
M.DujieTiers[9]  = { name="太乙天劫", totalBolts=80,  duration=42, boltSpeed=790,  warningTime=0.20, boltWidth=57, playerSpeed=440, retryCostBase=10000000 }
M.DujieTiers[10] = { name="大罗天劫", totalBolts=100, duration=48, boltSpeed=860,  warningTime=0.15, boltWidth=60, playerSpeed=460, retryCostBase=18000000 }
M.DujieTiers[11] = { name="准圣天劫", totalBolts=125, duration=55, boltSpeed=940,  warningTime=0.10, boltWidth=63, playerSpeed=480, retryCostBase=30000000 }
M.DujieTiers[12] = { name="开天劫境", totalBolts=165, duration=70, boltSpeed=1050, warningTime=0.06, boltWidth=67, playerSpeed=500, retryCostBase=50000000 }

-- === 仙界境界称号 (接续 M.RealmTitles，追加索引 10-17) ===
M.RealmTitles[10] = { title="天仙道者", bonus=0.10, color={ 135, 206, 250, 255 } }
M.RealmTitles[11] = { title="真仙尊者", bonus=0.12, color={ 120, 140, 255, 255 } }
M.RealmTitles[12] = { title="玄仙大能", bonus=0.14, color={ 160, 100, 255, 255 } }
M.RealmTitles[13] = { title="金仙真君", bonus=0.16, color={ 255, 215, 100, 255 } }
M.RealmTitles[14] = { title="太乙上仙", bonus=0.19, color={ 255, 200,  50, 255 } }
M.RealmTitles[15] = { title="大罗上仙", bonus=0.22, color={ 255, 220,   0, 255 } }
M.RealmTitles[16] = { title="准圣大尊", bonus=0.26, color={ 255, 240, 180, 255 } }
M.RealmTitles[17] = { title="混元圣人", bonus=0.30, color={ 255, 255, 220, 255 } }

-- === 仙界顾客 NPC（仅飞升后使用，凡间数据不变） ===
M.CustomerNamesXian = {
    sanxiu   = { "一苇渡仙", "太虚游仙", "烟波钓客", "洞天野仙", "踏云散修", "无名飞仙", "化形老仙", "灵台散人", "清风仙客", "问道云游者" },
    youshang = { "三十三天商队", "瑶池采买", "蓬莱岛掌柜", "灵宝行商", "仙界货郎", "上界倒爷", "天界中间人", "走遍三界的老商" },
    zongmen  = { "灵霄殿差役", "天庭仙官", "三清门下", "玉虚宫弟子", "昆仑传人", "蓬莱门生", "太白金星的差使" },
    guike    = { "一方界主", "混沌古仙", "太初真圣", "鸿蒙老者", "证道先贤" },
}

M.CustomerDialoguesXian = {
    sanxiu   = { "道友，此处可有%s？", "途经此地，正缺%s", "某寻%s多时，终得一见", "%s可有现货？", "飞升之后才知%s难求", "%s…价格好说" },
    youshang = { "此%s成色如何？", "批量进些%s，有折扣否？", "天界同行推荐了此间%s", "%s品质上乘才收", "你这%s三界可有名气？" },
    zongmen  = { "本门急需%s，有多少要多少", "掌门遣我专程取%s", "仙界大会在即，需备%s", "长老点名要此间%s", "宗门公务，来取%s" },
    guike    = { "此%s，吾已看中", "全数购来", "拿去，无需废话", "%s…此物本座收了" },
}

M.IdleChatDialoguesXian = {
    sanxiu   = { "仙界的灵气果然充沛啊", "飞升之后才知仙途漫漫", "这仙坊倒也热闹", "不知又过了几万年…", "有好东西推荐一下" },
    youshang = { "三界之内，生意最好做", "仙界物价不低啊", "这批货卖完要去瑶池进货", "同行们都在抢仙材" },
    zongmen  = { "宗门每隔千年就要大采购", "仙界规矩多，采购也繁琐", "掌柜道友辛苦了", "师尊说要多走走见识见识" },
    guike    = { "此地灵气，尚可", "有趣，有趣", "难得遇见个实在的商家" },
}

-- === 仙界摊位等级 (追加至 M.StallLevels，11-20级) ===
M.StallLevels[11] = { level = 11, cost = 500000,    queueLimit = 22, slots = 11, speedMul = 5.5  }
M.StallLevels[12] = { level = 12, cost = 1500000,   queueLimit = 24, slots = 12, speedMul = 6.0  }
M.StallLevels[13] = { level = 13, cost = 3000000,   queueLimit = 26, slots = 13, speedMul = 6.6  }
M.StallLevels[14] = { level = 14, cost = 6000000,   queueLimit = 28, slots = 14, speedMul = 7.2  }
M.StallLevels[15] = { level = 15, cost = 12000000,  queueLimit = 30, slots = 15, speedMul = 8.0  }
M.StallLevels[16] = { level = 16, cost = 25000000,  queueLimit = 32, slots = 16, speedMul = 8.8  }
M.StallLevels[17] = { level = 17, cost = 50000000,  queueLimit = 34, slots = 17, speedMul = 9.6  }
M.StallLevels[18] = { level = 18, cost = 100000000, queueLimit = 36, slots = 18, speedMul = 10.5 }
M.StallLevels[19] = { level = 19, cost = 200000000, queueLimit = 38, slots = 19, speedMul = 11.5 }
M.StallLevels[20] = { level = 20, cost = 500000000, queueLimit = 40, slots = 20, speedMul = 13.0 }

-- === 风水阵配置 ===
M.FengshuiFormations = {
    { id = "juke",    name = "聚客阵", bonusType = "customer_speed", desc = "提升顾客来访速度",   color = { 100, 200, 255, 255 } },
    { id = "wangcai", name = "旺财阵", bonusType = "sell_price",     desc = "提升商品售价",       color = { 255, 215, 100, 255 } },
    { id = "sugong",  name = "速工阵", bonusType = "craft_speed",    desc = "提升制作速度",       color = { 180, 255, 120, 255 } },
    { id = "lingtian",name = "灵田阵", bonusType = "material_rate",  desc = "提升材料产出速度",   color = { 120, 240, 200, 255 } },
    { id = "koubei",  name = "口碑阵", bonusType = "reputation",     desc = "提升声望获取速度",   color = { 255, 180, 120, 255 } },
}

M.FengshuiMaxLevel = 20

--- 计算风水阵升级费用（指数增长）
--- @param level number 当前等级(0-19)，升到 level+1 的费用
--- @return number
function M.GetFengshuiCost(level)
    -- 1级: 50万, 20级: ~5亿 (指数增长 base=500000, factor=1.35)
    return math.floor(500000 * (1.35 ^ level))
end

--- 计算风水阵单阵位加成比例
--- @param level number 阵位等级(0-20)
--- @return number 加成比例(0.0 ~ 0.60)
function M.GetFengshuiBonus(level)
    -- 每级 +3%, 最高20级 = 60%
    return level * 0.03
end

-- 风水成就称号（按所有阵位总等级解锁）
M.FengshuiTitles = {
    { totalLevel = 10,  title = "初窥风水", bonus = 0.05, color = { 150, 200, 255, 255 } },
    { totalLevel = 25,  title = "风水学徒", bonus = 0.10, color = { 100, 220, 180, 255 } },
    { totalLevel = 50,  title = "风水大师", bonus = 0.15, color = { 255, 215, 100, 255 } },
    { totalLevel = 75,  title = "阵法宗师", bonus = 0.20, color = { 255, 180,  50, 255 } },
    { totalLevel = 100, title = "风水圣手", bonus = 0.25, color = { 255, 100, 100, 255 } },
}

--- 根据总等级获取当前风水称号
--- @param totalLevel number 所有阵位等级之和
--- @return table|nil 称号配置或nil
function M.GetFengshuiTitle(totalLevel)
    local best = nil
    for _, t in ipairs(M.FengshuiTitles) do
        if totalLevel >= t.totalLevel then
            best = t
        end
    end
    return best
end

-- === 破镜丹商店配置(保留兼容) ===
M.PillShopItems = {
    { id = "dujie_dan",    name = "渡劫丹", price = 5050000,  desc = "凡间大乘/渡劫突破所需", icon = "image/dujie_dan.png",    color = { 200, 160, 255, 255 } },
    { id = "pojing_dan",   name = "破境丹", price = 6030000,  desc = "凡间渡劫突破所需",       icon = "image/pojing_dan.png",   color = { 255, 180, 100, 255 } },
    { id = "shengxian_dan",name = "升仙丹", price = 25000000, desc = "仙界初阶境界突破所需",   icon = "image/shengxian_dan.png",color = { 255, 215, 100, 255 } },
}

-- ========== 材料灵石估值(法宝自动修复计价) ==========
M.MaterialLingshiValue = {
    -- 凡间基础材料
    lingcao = 10,
    lingzhi = 20,
    xuantie = 55,
    -- 凡间合成材料
    gaoji_lingcao = 150,
    jinglian_lingzhi = 200,
    hantie_ding = 350,
    tianling_ye = 2000,
    -- 仙界基础材料
    lingjing_cao = 400,
    tianchan_si = 680,
    xingchen_kuang = 2200,
    -- 仙界合成材料
    shanggu_lingjing = 5000,
    tianchan_jinghua = 8000,
    xingchen_jinghua = 25000,
    hundun_jing = 80000,
}

--- 计算法宝自动修复所需灵石(按等级缩放)
---@param artId string
---@param level number 法宝等级(1~10)
---@return number lingshiCost
function M.GetArtifactAutoRepairCost(artId, level)
    level = level or 1
    local matCost, _ = M.GetArtifactRepairCost(artId)
    if not matCost then return level * 10000 end
    local baseLingshi = 0
    for matId, count in pairs(matCost) do
        baseLingshi = baseLingshi + count * (M.MaterialLingshiValue[matId] or 10)
    end
    return math.max(math.floor(baseLingshi * level * level), level * 10000)
end

-- ========== 聚宝阁商品配置(单价) ==========
M.MarketplaceItems = {
    -- 丹药分类 (每日限购2)
    { id = "dujie_dan",    name = "渡劫丹", price = 5050000,  desc = "凡间大乘/渡劫突破所需", icon = "image/dujie_dan.png",    color = { 200, 160, 255, 255 }, category = "pill", dailyLimit = 2 },
    { id = "pojing_dan",   name = "破境丹", price = 6030000,  desc = "凡间渡劫突破所需",       icon = "image/pojing_dan.png",   color = { 255, 180, 100, 255 }, category = "pill", dailyLimit = 2 },
    { id = "shengxian_dan",name = "升仙丹", price = 25000000, desc = "仙界初阶境界突破所需",   icon = "image/shengxian_dan.png",color = { 255, 215, 100, 255 }, category = "pill", dailyLimit = 2 },
    -- 凡间基础材料 (每日限购999)
    { id = "lingcao",       name = "灵草",   price = 10,    desc = "基础灵植，用途广泛",     icon = "image/icon_lingcao.png",  color = { 80, 200, 120, 255 },  category = "mortal_mat", isMaterial = true, dailyLimit = 999 },
    { id = "lingzhi",       name = "灵纸",   price = 20,    desc = "灵纹承载之纸",           icon = "image/icon_lingzhi.png",  color = { 200, 190, 130, 255 }, category = "mortal_mat", isMaterial = true, dailyLimit = 999 },
    { id = "xuantie",       name = "玄铁",   price = 55,    desc = "蕴含灵力的矿石",         icon = "image/icon_xuantie.png",  color = { 150, 160, 180, 255 }, category = "mortal_mat", isMaterial = true, dailyLimit = 999 },
    -- 凡间合成材料 (每日限购20)
    { id = "gaoji_lingcao",    name = "高级灵草",   price = 150,  desc = "品质上乘的灵草",     icon = "image/icon_lingcao.png",  color = { 50, 180, 100, 255 },  category = "mortal_synth", isMaterial = true, dailyLimit = 20 },
    { id = "jinglian_lingzhi", name = "精炼灵纸",   price = 200,  desc = "精炼后的高级灵纸",   icon = "image/icon_lingzhi.png",  color = { 180, 170, 100, 255 }, category = "mortal_synth", isMaterial = true, dailyLimit = 20 },
    { id = "hantie_ding",      name = "寒铁锭",     price = 350,  desc = "精炼冶金之锭",       icon = "image/icon_xuantie.png",  color = { 130, 140, 170, 255 }, category = "mortal_synth", isMaterial = true, dailyLimit = 20 },
    { id = "tianling_ye",      name = "天灵液",     price = 2000, desc = "蕴含天地精华之液",   icon = "image/icon_lingcao.png",  color = { 180, 130, 255, 255 }, category = "mortal_synth", isMaterial = true, dailyLimit = 20 },
    -- 仙界基础材料 (每日限购30)
    { id = "lingjing_cao",     name = "灵晶草",     price = 400,   desc = "仙界灵植",           icon = "image/mat_lingjing_cao.png",    color = { 100, 240, 180, 255 }, category = "celestial_mat", isMaterial = true, celestial = true, dailyLimit = 30 },
    { id = "tianchan_si",      name = "天蚕丝",     price = 680,   desc = "仙界天蚕所吐灵丝",   icon = "image/mat_tianchan_si.png",     color = { 220, 200, 240, 255 }, category = "celestial_mat", isMaterial = true, celestial = true, dailyLimit = 30 },
    { id = "xingchen_kuang",   name = "星辰矿",     price = 2200,  desc = "蕴含星辰之力的矿石", icon = "image/mat_xingchen_kuang.png",  color = { 100, 160, 255, 255 }, category = "celestial_mat", isMaterial = true, celestial = true, dailyLimit = 30 },
    -- 仙界合成材料 (每日限购10)
    { id = "shanggu_lingjing",  name = "上古灵晶",   price = 5000,  desc = "远古灵气结晶",       icon = "image/mat_lingjing_cao.png",    color = { 180, 240, 220, 255 }, category = "celestial_synth", isMaterial = true, celestial = true, dailyLimit = 10 },
    { id = "tianchan_jinghua",  name = "天蚕精华",   price = 8000,  desc = "天蚕灵丝精炼而成",   icon = "image/mat_tianchan_jinghua.png", color = { 240, 210, 255, 255 }, category = "celestial_synth", isMaterial = true, celestial = true, dailyLimit = 10 },
    { id = "xingchen_jinghua",  name = "星辰精华",   price = 25000, desc = "星辰矿凝练之精华",   icon = "image/mat_xingchen_jinghua.png", color = { 130, 180, 255, 255 }, category = "celestial_synth", isMaterial = true, celestial = true, dailyLimit = 10 },
    { id = "hundun_jing",       name = "混沌晶",     price = 80000, desc = "开天辟地之力的结晶", icon = "image/mat_xingchen_kuang.png",  color = { 200, 200, 220, 255 }, category = "celestial_synth", isMaterial = true, celestial = true, dailyLimit = 5 },
}

-- 聚宝阁分类名称
M.MarketplaceCategories = {
    { key = "pill",            name = "丹药" },
    { key = "mortal_mat",      name = "凡间基础材料" },
    { key = "mortal_synth",    name = "凡间合成材料" },
    { key = "celestial_mat",   name = "仙界基础材料", celestial = true },
    { key = "celestial_synth", name = "仙界合成材料", celestial = true },
}

-- === 商品字段统一后处理 ===
-- 仙界商品使用 materials 数组格式，但制作逻辑依赖 materialId/materialCost
-- 自动为单材料商品填充这两个字段，保证全流程兼容
for _, prod in ipairs(M.Products) do
    if not prod.materialId and prod.materials and #prod.materials == 1 then
        prod.materialId   = prod.materials[1].id
        prod.materialCost = prod.materials[1].count or 1
    end
end

return M
