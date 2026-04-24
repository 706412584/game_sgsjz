-- ============================================================================
-- 《问道长生》水墨主题色板与样式工具
-- ============================================================================

local Theme = {}

-- 核心色板
Theme.colors = {
    -- 背景
    bgParchment     = { 232, 220, 200, 255 },   -- 米白底色
    bgParchmentDark = { 210, 198, 175, 255 },   -- 深米白
    bgDark          = { 35, 30, 25, 150 },       -- 深色面板（~60%透明度，可透出背景）
    bgDarkSolid     = { 35, 30, 25, 255 },       -- 深色不透明
    bgOverlay       = { 20, 18, 15, 180 },       -- 半透明遮罩

    -- 文字
    textPrimary     = { 44, 40, 35, 255 },       -- 深色主文字
    textSecondary   = { 190, 180, 158, 255 },     -- 次要文字（深色背景可读）
    textLight       = { 200, 195, 180, 255 },    -- 浅色文字（深底上）
    textGold        = { 200, 168, 85, 255 },     -- 金色文字

    -- 强调色
    gold            = { 200, 168, 85, 255 },     -- 金色
    goldDark        = { 160, 130, 60, 255 },     -- 深金
    goldLight       = { 220, 195, 130, 255 },    -- 浅金
    inkBlack        = { 30, 25, 20, 255 },       -- 墨黑
    accent          = { 120, 170, 220, 255 },    -- 青蓝灵气（调亮）

    -- 功能色
    danger          = { 180, 60, 60, 255 },      -- 红(气血)
    dangerLight     = { 200, 90, 90, 255 },      -- 浅红
    success         = { 80, 160, 80, 255 },      -- 绿
    successLight    = { 100, 180, 100, 255 },    -- 浅绿
    warning         = { 200, 160, 50, 255 },     -- 警告黄

    -- 边框与分割
    border          = { 80, 70, 55, 100 },       -- 普通边框
    borderGold      = { 160, 130, 60, 120 },     -- 金色边框
    divider         = { 80, 70, 55, 60 },        -- 分割线

    -- 标签选中态文字
    tabActiveText   = { 240, 235, 225, 255 },    -- 浅白色（金色底上）

    -- 按钮文字（金色底/主要按钮上的文字统一用浅白）
    btnPrimaryText  = { 240, 235, 225, 255 },    -- 主按钮文字（InkButton 同色）

    -- 特殊
    transparent     = { 0, 0, 0, 0 },
    white           = { 255, 255, 255, 255 },
    black           = { 0, 0, 0, 255 },
}

-- 字体尺寸
Theme.fontSize = {
    title    = 28,   -- 页面大标题
    heading  = 20,   -- 章节标题
    subtitle = 16,   -- 副标题
    body     = 14,   -- 正文
    small    = 12,   -- 小字
    tiny     = 10,   -- 极小
}

-- 间距
Theme.spacing = {
    xs  = 4,
    sm  = 8,
    md  = 12,
    lg  = 16,
    xl  = 24,
    xxl = 32,
}

-- 圆角
Theme.radius = {
    sm = 4,
    md = 8,
    lg = 12,
}

-- 底部导航高度
Theme.bottomNavHeight = 80

-- 全局滚动灵敏度（scrollMultiplier，默认引擎值为 3）
Theme.scrollSensitivity = 0.55

-- 底部导航选中色（绿色灵气）
Theme.colors.navActive     = { 80, 220, 130, 255 }     -- 选中文字/图标绿色
Theme.colors.navActiveDim  = { 60, 180, 100, 200 }     -- 选中图标 tint

-- 顶部状态栏高度
Theme.topBarHeight = 80

-- ============================================================================
-- 图片资源路径（assets/image/ 是资源根目录的一部分，直接从 image/ 引用）
-- ============================================================================
Theme.images = {
    -- 页面背景图（720x1290, 9:16 竖屏）
    bgTitle      = "image/bg_title.png",
    bgCreateRole = "image/bg_create_role.png",
    bgMenu       = "image/bg_menu.png",
    bgHome       = "image/bg_home.png",
    bgExplore    = "image/bg_explore.png",
    bgAlchemy    = "image/bg_alchemy.png",
    bgBag        = "image/bg_bag.png",
    bgSect       = "image/bg_sect.png",
    bgWorldMap   = "image/bg_world_map.png",
    bgMap        = "image/bg_map.png",
    bgChat       = "image/bg_chat.png",

    -- 功能图标（128x128, 透明背景）
    iconHome     = "image/icon_home.png",
    iconAlchemy  = "image/icon_alchemy.png",
    iconBag      = "image/icon_bag.png",
    iconExplore  = "image/icon_explore.png",
    iconSect     = "image/icon_sect.png",
    iconTrial    = "image/icon_trial.png",
    iconQuest    = "image/icon_quest.png",
    iconChat     = "image/icon_chat.png",
    iconCurrency = "image/icon_currency.png",
    iconSettings = "image/icon_settings.png",
    iconWorldMap = "image/icon_world_map.png",
    iconMarket   = "image/icon_currency.png",    -- 坊市（复用货币图标）
    iconRanking  = "image/icon_explore.png",     -- 排行（暂用探索图标占位）

    -- 洞府功能图标（128x128, 透明背景, 青蓝仙侠风）
    iconAttr        = "image/icon_attr_v2.png",
    iconSkill       = "image/icon_skill_v2.png",
    iconArtifact    = "image/icon_artifact_v2.png",
    iconDao         = "image/icon_dao_v2.png",
    iconTribulation = "image/icon_tribulation_v2.png",
    iconPill        = "image/icon_pill_v2.png",

    -- 特殊图标
    iconMapMarker = "image/icon_map_marker.png",     -- 64x64
    iconMeditate  = "image/icon_meditate.png",       -- 256x256 打坐剪影
    meditateChar      = "image/meditate_character.png",         -- 512x512 打坐角色（男，通用兜底）
    meditateCharF     = "image/meditate_character_female.png", -- 512x512 打坐角色（女，通用兜底）

    -- 标题页素材
    titleCalligraphy = "image/title_calligraphy.png",  -- 水墨书法标题（黑色）
    titleGold        = "image/title_gold.png",         -- 金色书法标题（带笔刷装饰）
    titleMountain    = "image/title_mountain.png",     -- 水墨远山装饰
    titleBrushStroke = "image/title_brush_stroke.png", -- 毛笔笔触装饰条
    iconPet       = "image/pet_01_whitefox.png",     -- 灵宠图标（复用小白狐）
    iconMore      = "image/icon_more.png",           -- 更多菜单图标
    brushLabelBg  = "image/brush_label_bg.png",      -- 横向毛笔刷（地点文字底衬）

    -- 开场故事插画（720x1280, 水墨风）
    story01 = "image/story_01_20260406172808.png",
    story02 = "image/story_02_20260406172833.png",
    story03 = "image/story_03_20260406164059.png",
    story04 = "image/story_04_20260406164053.png",

    -- 故事帧动画（每幕2~3张额外帧，配合原图循环播放）
    story01_frame2 = "image/edited_story_01_frame2_20260406174023.png",
    story01_frame3 = "image/edited_story_01_frame3_20260406174122.png",
    story02_frame2 = "image/edited_story_02_frame2_20260406180253.png",
    story02_frame3 = "image/edited_story_02_frame3_20260406174701.png",
    story02_frame4 = "image/edited_story_02_frame4_20260406174757.png",
    story03_frame2 = "image/edited_story_03_frame2_20260406180324.png",
    story03_frame3 = "image/edited_story_03_frame3_20260406180441.png",
    story04_frame2 = "image/edited_story_04_frame2_20260406175416.png",
    story04_frame3 = "image/edited_story_04_frame3_20260406175500.png",

    -- 头像边框
    avatarFrame   = "image/avatar_frame_01_20260407034845.png",

    -- 角色头像（256x256, 透明背景）
    avatarMale1   = "image/avatar_male_1.png",
    avatarMale2   = "image/avatar_male_2.png",
    avatarMale3   = "image/avatar_male_3.png",
    avatarMale4   = "image/avatar_male_4.png",
    avatarMale5   = "image/avatar_male_5.png",
    avatarFemale1 = "image/avatar_female_1.png",
    avatarFemale2 = "image/avatar_female_2.png",
    avatarFemale3 = "image/avatar_female_3.png",
    avatarFemale4 = "image/avatar_female_4.png",
    avatarFemale5 = "image/avatar_female_5.png",

    -- 怪物图（256x256, 透明背景）
    monster01 = "image/monster_01_wolf.png",
    monster02 = "image/monster_02_bandit.png",
    monster03 = "image/monster_03_snake.png",
    monster04 = "image/monster_04_skeleton.png",
    monster05 = "image/monster_05_treant.png",
    monster06 = "image/monster_06_firetiger.png",
    monster07 = "image/monster_07_golem.png",
    monster08 = "image/monster_08_foxdemon.png",
    monster09 = "image/monster_09_wraith.png",
    monster10 = "image/monster_10_lavagolem.png",
    monster11 = "image/monster_11_spider.png",
    monster12 = "image/monster_12_zombie.png",
    monster13 = "image/monster_13_tengu.png",
    monster14 = "image/monster_14_eagle.png",
    monster15 = "image/monster_15_icebear.png",
    monster16 = "image/monster_16_evilmonk.png",
    monster17 = "image/monster_17_mantis.png",
    monster18 = "image/monster_18_hellhound.png",
    monster19 = "image/monster_19_assassin.png",
    monster20 = "image/monster_20_dragonboss.png",

    -- 灵宠图（256x256, 透明背景）
    pet01 = "image/pet_01_whitefox.png",
    pet02 = "image/pet_02_rabbit.png",
    pet03 = "image/pet_03_firebird.png",
    pet04 = "image/pet_04_greendragon.png",
    pet05 = "image/pet_05_butterfly.png",
    pet06 = "image/pet_06_blackcat.png",
    pet07 = "image/pet_07_crane.png",
    pet08 = "image/pet_08_thundermink.png",
    pet09 = "image/pet_09_waterfish.png",
    pet10 = "image/pet_10_deer.png",
    pet11 = "image/pet_11_turtle.png",
    pet12 = "image/pet_12_mouse.png",
    pet13 = "image/pet_13_snail.png",
    pet14 = "image/pet_14_goldbird.png",
    pet15 = "image/pet_15_icefox.png",
    pet16 = "image/pet_16_qinglong.png",
    pet17 = "image/pet_17_baihu.png",
    pet18 = "image/pet_18_zhuque.png",
    pet19 = "image/pet_19_xuanwu.png",
}

-- 按性别分组的头像列表
Theme.avatars = {
    ["男"] = {
        "image/avatar_male_1.png",
        "image/avatar_male_2.png",
        "image/avatar_male_3.png",
        "image/avatar_male_4.png",
        "image/avatar_male_5.png",
    },
    ["女"] = {
        "image/avatar_female_4.png",
        "image/avatar_female_4.png",
        "image/avatar_female_4.png",
        "image/avatar_female_4.png",
        "image/avatar_female_4.png",
    },
}

-- 打坐角色变体（按头像索引对应，透明背景）
Theme.meditateChars = {
    ["男"] = {
        "image/meditate_male_2_20260416145832.png",
        "image/meditate_male_2_20260416145832.png",
        "image/meditate_male_2_20260416145832.png",
        "image/meditate_male_2_20260416145832.png",
        "image/meditate_male_2_20260416145832.png",
    },
    ["女"] = {
        "image/meditate_female_1_20260416145842.png",
        "image/meditate_female_1_20260416145842.png",
        "image/meditate_female_1_20260416145842.png",
        "image/meditate_female_1_20260416145842.png",
        "image/meditate_female_1_20260416145842.png",
    },
}

-- 怪物数据列表（按难度递增）
Theme.monsters = {
    { name = "野狼",       image = "image/monster_01_wolf.png",       level = 1  },
    { name = "山贼",       image = "image/monster_02_bandit.png",     level = 2  },
    { name = "巨毒蛇",     image = "image/monster_03_snake.png",      level = 3  },
    { name = "鬼火骷髅",   image = "image/monster_04_skeleton.png",   level = 5  },
    { name = "树妖",       image = "image/monster_05_treant.png",     level = 7  },
    { name = "火焰虎",     image = "image/monster_06_firetiger.png",  level = 10 },
    { name = "石像魔",     image = "image/monster_07_golem.png",      level = 12 },
    { name = "妖狐",       image = "image/monster_08_foxdemon.png",   level = 15 },
    { name = "冥界恶鬼",   image = "image/monster_09_wraith.png",     level = 18 },
    { name = "岩流巨人",   image = "image/monster_10_lavagolem.png",  level = 20 },
    { name = "水妖蛛",     image = "image/monster_11_spider.png",     level = 23 },
    { name = "僵尸",       image = "image/monster_12_zombie.png",     level = 25 },
    { name = "天狗",       image = "image/monster_13_tengu.png",      level = 28 },
    { name = "雷电鹰",     image = "image/monster_14_eagle.png",      level = 30 },
    { name = "冰霜巨熊",   image = "image/monster_15_icebear.png",    level = 33 },
    { name = "邪修",       image = "image/monster_16_evilmonk.png",   level = 35 },
    { name = "螳螂精",     image = "image/monster_17_mantis.png",     level = 38 },
    { name = "地狱三头犬", image = "image/monster_18_hellhound.png",  level = 40 },
    { name = "暗影刺客",   image = "image/monster_19_assassin.png",   level = 45 },
    { name = "龙魂",       image = "image/monster_20_dragonboss.png", level = 50 },
}

-- 灵宠数据列表
Theme.pets = {
    { name = "小白狐",   image = "image/pet_01_whitefox.png",     quality = "普通", skill = "灵狐附体",   desc = "温顺灵巧的白狐幼崽，能提升主人闪避" },
    { name = "玉兔",     image = "image/pet_02_rabbit.png",       quality = "普通", skill = "月华护盾",   desc = "通灵玉兔，月光下能为主人提供护盾" },
    { name = "火灵鸟",   image = "image/pet_03_firebird.png",     quality = "良品", skill = "烈焰冲击",   desc = "浴火而生的灵鸟，能释放火焰攻击" },
    { name = "小青龙",   image = "image/pet_04_greendragon.png",  quality = "珍稀", skill = "龙息吐纳",   desc = "青龙幼崽，龙族血脉提升修炼速度" },
    { name = "玉蝴蝶",   image = "image/pet_05_butterfly.png",    quality = "普通", skill = "迷梦粉尘",   desc = "如玉般通透的蝴蝶，可使敌人昏迷" },
    { name = "妖灵猫",   image = "image/pet_06_blackcat.png",     quality = "良品", skill = "暗影潜行",   desc = "神秘黑猫，能隐入暗影辅助偷袭" },
    { name = "仙鹤",     image = "image/pet_07_crane.png",        quality = "珍稀", skill = "仙鹤引路",   desc = "仙家之鹤，能引领主人寻找机缘" },
    { name = "雷电貂",   image = "image/pet_08_thundermink.png",  quality = "良品", skill = "雷光闪击",   desc = "体蕴雷电的灵貂，速度极快" },
    { name = "水灵鱼",   image = "image/pet_09_waterfish.png",    quality = "普通", skill = "治愈水泡",   desc = "水系灵鱼，能在战斗中治愈主人" },
    { name = "灵鹿",     image = "image/pet_10_deer.png",         quality = "良品", skill = "草木回春",   desc = "灵山之鹿，精通草木之道" },
    { name = "灵龟",     image = "image/pet_11_turtle.png",       quality = "珍稀", skill = "龟甲壁障",   desc = "万年灵龟，防御力极其强大" },
    { name = "妖精鼠",   image = "image/pet_12_mouse.png",        quality = "普通", skill = "寻宝嗅觉",   desc = "机灵小鼠，擅长发现隐藏宝物" },
    { name = "玉蜗",     image = "image/pet_13_snail.png",        quality = "普通", skill = "缓速结界",   desc = "通体如玉的蜗牛，能减缓敌人速度" },
    { name = "金翼大鹏", image = "image/pet_14_goldbird.png",     quality = "传说", skill = "鹏翼天击",   desc = "大鹏一展翅，天地为之震颤" },
    { name = "冰蓝狐",   image = "image/pet_15_icefox.png",       quality = "珍稀", skill = "冰封千里",   desc = "极寒之狐，能冻结大范围敌人" },
    -- 四大神兽
    { name = "青龙",     image = "image/pet_16_qinglong.png",    quality = "神话", skill = "苍龙七宿",   desc = "东方神兽，掌管春雷万物生长，龙威震慑一切妖邪" },
    { name = "白虎",     image = "image/pet_17_baihu.png",       quality = "神话", skill = "虎啸山林",   desc = "西方神兽，主杀伐之力，虎啸一声百兽臣服" },
    { name = "朱雀",     image = "image/pet_18_zhuque.png",       quality = "神话", skill = "涅槃天火",   desc = "南方神兽，浴火重生永恒不灭，天火焚尽一切" },
    { name = "玄武",     image = "image/pet_19_xuanwu.png",       quality = "神话", skill = "龟蛇玄甲",   desc = "北方神兽，龟蛇合体固若金汤，万法不侵" },
}

return Theme
