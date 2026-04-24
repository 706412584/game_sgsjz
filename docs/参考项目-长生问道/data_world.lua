-- ============================================================================
-- 《问道长生》世界数据配置 (区域/怪物/灵宠/试炼/任务)
-- 数据来源: docs/roadmap.md 阶段四
-- ============================================================================

local M = {}

-- ============================================================================
-- 9.1 探索区域（10大区域）
-- ============================================================================
-- unlockTier/unlockSub: 解锁所需大境界阶数/小境界索引
-- areaIndex: 区域序号 (1-10)，用于品质概率档位查询
-- ============================================================================
M.AREAS = {
    { id = "yunwu",    name = "云雾山",   areaIndex = 1,  unlockTier = 1,  unlockSub = 1, desc = "云雾缭绕的山脉，适合初入修行之人历练。" },
    { id = "tianque",  name = "天阙遗迹", areaIndex = 2,  unlockTier = 3,  unlockSub = 1, desc = "上古遗迹，危机四伏但机缘不少。" },
    { id = "donghai",  name = "东海海滨", areaIndex = 3,  unlockTier = 4,  unlockSub = 1, desc = "东海之滨，海妖出没之地。" },
    { id = "fushan",   name = "夫山遗迹", areaIndex = 4,  unlockTier = 5,  unlockSub = 1, desc = "神秘的上古大能洞府遗址。" },
    { id = "xuanbing", name = "玄冰深渊", areaIndex = 5,  unlockTier = 6,  unlockSub = 1, desc = "寒气刺骨的冰封深渊，强大妖兽栖息于此。" },
    { id = "jiutian",  name = "九天雷域", areaIndex = 6,  unlockTier = 7,  unlockSub = 1, desc = "雷电交织的空间裂隙，雷系灵兽的天堂。" },
    { id = "wanggu",   name = "万古战场", areaIndex = 7,  unlockTier = 8,  unlockSub = 1, desc = "上古仙魔大战遗址，残留着恐怖气息。" },
    { id = "xianmo",   name = "仙魔裂隙", areaIndex = 8,  unlockTier = 9,  unlockSub = 1, desc = "仙界与魔界交汇的裂隙，危机与机遇并存。" },
    { id = "huntian",  name = "混天墟",   areaIndex = 9,  unlockTier = 10, unlockSub = 1, desc = "混沌之力肆虐的虚空废墟，传说中有四神兽出没。" },
    { id = "taiyuan",  name = "太渊秘境", areaIndex = 10, unlockTier = 10, unlockSub = 3, desc = "宇宙尽头的秘境，修行者的终极试炼之地。" },
    -- 仙界区域 (飞升后可探索, areaIndex 11-15)
    { id = "sanxian_ye",      name = "散仙野",   areaIndex = 11, unlockTier = 11, unlockSub = 1,
      isImmortal = true, immortalDrop = { name = "仙灵丹", rate = 25, countMin = 1, countMax = 2 },
      desc = "飞升后的第一片仙土，散仙修炼之所，仙气浓郁。" },
    { id = "zhenjing_dong",   name = "真仙洞天", areaIndex = 12, unlockTier = 13, unlockSub = 1,
      isImmortal = true, immortalDrop = { name = "仙灵丹", rate = 30, countMin = 1, countMax = 3 },
      desc = "真仙与玄仙栖居的洞天福地，灵泉涌动，机缘不断。" },
    { id = "taiyi_fu",        name = "太乙仙府", areaIndex = 13, unlockTier = 15, unlockSub = 1,
      isImmortal = true, immortalDrop = { name = "仙元丹", rate = 20, countMin = 1, countMax = 2 },
      desc = "太乙金仙驻足之地，法则之力凝聚成形，充满大道玄机。" },
    { id = "daluo_mijing",    name = "大罗秘境", areaIndex = 14, unlockTier = 17, unlockSub = 1,
      isImmortal = true, immortalDrop = { name = "大罗仙丹", rate = 15, countMin = 1, countMax = 1 },
      desc = "大罗金仙与混元金仙角逐之地，法力磅礴，危机四伏。" },
    { id = "hunyan_daochang", name = "混元道场", areaIndex = 15, unlockTier = 20, unlockSub = 1,
      isImmortal = true, immortalDrop = { name = "大罗仙丹", rate = 20, countMin = 1, countMax = 2 },
      desc = "准圣境的至高道场，洪荒之力在此汇聚，天地法则触手可及。" },
}

-- 区域id → areaIndex 快查
M.AREA_INDEX = {}
for _, a in ipairs(M.AREAS) do
    M.AREA_INDEX[a.id] = a.areaIndex
end

-- ============================================================================
-- 9.2 怪物列表（50+怪物覆盖10区域）
-- ============================================================================
M.MONSTERS = {
    -- 云雾山 (区域1)
    { id = 1,  name = "野狼",     areaId = "yunwu",   isBoss = false },
    { id = 2,  name = "山贼",     areaId = "yunwu",   isBoss = false },
    { id = 3,  name = "毒蛇",     areaId = "yunwu",   isBoss = false },
    { id = 4,  name = "蜘蛛精",   areaId = "yunwu",   isBoss = false },
    { id = 5,  name = "螳螂精",   areaId = "yunwu",   isBoss = false },
    -- 天阙遗迹 (区域2)
    { id = 6,  name = "骷髅兵",   areaId = "tianque", isBoss = false },
    { id = 7,  name = "火虎",     areaId = "tianque", isBoss = false },
    { id = 8,  name = "石魔",     areaId = "tianque", isBoss = false },
    { id = 9,  name = "僵尸",     areaId = "tianque", isBoss = false },
    { id = 10, name = "怨灵",     areaId = "tianque", isBoss = false },
    -- 东海海滨 (区域3)
    { id = 11, name = "狐妖",     areaId = "donghai", isBoss = false },
    { id = 12, name = "天狗",     areaId = "donghai", isBoss = false },
    { id = 13, name = "金鹰",     areaId = "donghai", isBoss = false },
    { id = 14, name = "冰熊",     areaId = "donghai", isBoss = false },
    { id = 15, name = "海蛟",     areaId = "donghai", isBoss = false },
    -- 夫山遗迹 (区域4)
    { id = 16, name = "熔岩魔像", areaId = "fushan",  isBoss = false },
    { id = 17, name = "邪僧",     areaId = "fushan",  isBoss = false },
    { id = 18, name = "刺客",     areaId = "fushan",  isBoss = false },
    { id = 19, name = "地狱犬",   areaId = "fushan",  isBoss = false },
    { id = 20, name = "傀儡师",   areaId = "fushan",  isBoss = false },
    -- 玄冰深渊 (区域5)
    { id = 21, name = "冰魄兽",   areaId = "xuanbing", isBoss = false },
    { id = 22, name = "霜狼王",   areaId = "xuanbing", isBoss = false },
    { id = 23, name = "寒冰蛟龙", areaId = "xuanbing", isBoss = false },
    { id = 24, name = "雪人",     areaId = "xuanbing", isBoss = false },
    { id = 25, name = "冰晶傀儡", areaId = "xuanbing", isBoss = false },
    -- 九天雷域 (区域6)
    { id = 26, name = "雷兽",     areaId = "jiutian", isBoss = false },
    { id = 27, name = "电蛟",     areaId = "jiutian", isBoss = false },
    { id = 28, name = "雷灵",     areaId = "jiutian", isBoss = false },
    { id = 29, name = "风雷鹰",   areaId = "jiutian", isBoss = false },
    { id = 30, name = "劫雷傀儡", areaId = "jiutian", isBoss = false },
    -- 万古战场 (区域7)
    { id = 31, name = "战魂",     areaId = "wanggu",  isBoss = false },
    { id = 32, name = "骨将",     areaId = "wanggu",  isBoss = false },
    { id = 33, name = "魔兵",     areaId = "wanggu",  isBoss = false },
    { id = 34, name = "亡灵法师", areaId = "wanggu",  isBoss = false },
    { id = 35, name = "血魔",     areaId = "wanggu",  isBoss = false },
    -- 仙魔裂隙 (区域8)
    { id = 36, name = "堕天使",   areaId = "xianmo",  isBoss = false },
    { id = 37, name = "魔化仙人", areaId = "xianmo",  isBoss = false },
    { id = 38, name = "虚空行者", areaId = "xianmo",  isBoss = false },
    { id = 39, name = "裂隙魔龙", areaId = "xianmo",  isBoss = false },
    { id = 40, name = "时空猎手", areaId = "xianmo",  isBoss = false },
    -- 混天墟 (区域9)
    { id = 41, name = "混沌兽",   areaId = "huntian", isBoss = false },
    { id = 42, name = "噬天魔蛟", areaId = "huntian", isBoss = false },
    { id = 43, name = "虚无行者", areaId = "huntian", isBoss = false },
    { id = 44, name = "末日使徒", areaId = "huntian", isBoss = false },
    { id = 45, name = "毁灭傀儡", areaId = "huntian", isBoss = false },
    -- 太渊秘境 (区域10)
    { id = 46, name = "太古凶兽", areaId = "taiyuan", isBoss = false },
    { id = 47, name = "天魔大圣", areaId = "taiyuan", isBoss = false },
    { id = 48, name = "虚空巨龙", areaId = "taiyuan", isBoss = false },
    { id = 49, name = "星辰古神", areaId = "taiyuan", isBoss = false },
    { id = 50, name = "太渊守护者", areaId = "taiyuan", isBoss = false },
    -- 散仙野 (区域11)
    { id = 51, name = "散仙魔修", areaId = "sanxian_ye",      isBoss = false },
    { id = 52, name = "仙灵兽",   areaId = "sanxian_ye",      isBoss = false },
    { id = 53, name = "天仙游魂", areaId = "sanxian_ye",      isBoss = false },
    { id = 54, name = "炼器傀儡", areaId = "sanxian_ye",      isBoss = false },
    { id = 55, name = "仙域巡察", areaId = "sanxian_ye",      isBoss = false },
    -- 真仙洞天 (区域12)
    { id = 56, name = "洞天守卫", areaId = "zhenjing_dong",   isBoss = false },
    { id = 57, name = "玄仙剑修", areaId = "zhenjing_dong",   isBoss = false },
    { id = 58, name = "金仙法师", areaId = "zhenjing_dong",   isBoss = false },
    { id = 59, name = "仙力蛟龙", areaId = "zhenjing_dong",   isBoss = false },
    { id = 60, name = "玄界行者", areaId = "zhenjing_dong",   isBoss = false },
    -- 太乙仙府 (区域13)
    { id = 61, name = "太乙符兵", areaId = "taiyi_fu",        isBoss = false },
    { id = 62, name = "仙府卫灵", areaId = "taiyi_fu",        isBoss = false },
    { id = 63, name = "大罗门人", areaId = "taiyi_fu",        isBoss = false },
    { id = 64, name = "法则战傀", areaId = "taiyi_fu",        isBoss = false },
    { id = 65, name = "仙道古兽", areaId = "taiyi_fu",        isBoss = false },
    -- 大罗秘境 (区域14)
    { id = 66, name = "混元魔兵", areaId = "daluo_mijing",    isBoss = false },
    { id = 67, name = "大罗遗灵", areaId = "daluo_mijing",    isBoss = false },
    { id = 68, name = "斩尸剑灵", areaId = "daluo_mijing",    isBoss = false },
    { id = 69, name = "法则傀儡", areaId = "daluo_mijing",    isBoss = false },
    { id = 70, name = "混元天龙", areaId = "daluo_mijing",    isBoss = false },
    -- 混元道场 (区域15)
    { id = 71, name = "准圣残魂", areaId = "hunyan_daochang", isBoss = false },
    { id = 72, name = "洪荒凶兽", areaId = "hunyan_daochang", isBoss = false },
    { id = 73, name = "道韵行者", areaId = "hunyan_daochang", isBoss = false },
    { id = 74, name = "法则魔神", areaId = "hunyan_daochang", isBoss = false },
    { id = 75, name = "混元道魔", areaId = "hunyan_daochang", isBoss = false },
}

-- ============================================================================
-- 10.1 灵宠列表（品质使用新9品阶key）
-- ============================================================================
M.PETS = {
    -- 普通灵宠 (各区域可捕获)
    { id = 1,  name = "白狐",   quality = "lingbao",   role = "辅助", skill = "灵狐附体",   image = "image/pet_01_whitefox.png",     desc = "温顺灵巧的白狐幼崽，能提升主人闪避",
      element = "metal", combatStats = { action = "heal", healPct = 0.06, interval = 4 } },
    { id = 2,  name = "灵兔",   quality = "fanqi",     role = "辅助", skill = "月华护盾",   image = "image/pet_02_rabbit.png",       desc = "通灵玉兔，月光下能为主人提供护盾",
      element = "earth", combatStats = { action = "heal", healPct = 0.05, interval = 4 } },
    { id = 3,  name = "火鸟",   quality = "xtlingbao", role = "攻击", skill = "烈焰冲击",   image = "image/pet_03_firebird.png",     desc = "浴火而生的灵鸟，能释放火焰攻击",
      element = "fire", combatStats = { action = "attack", damagePct = 0.15, interval = 3 } },
    { id = 4,  name = "幼龙",   quality = "huangqi",   role = "攻击", skill = "龙息吐纳",   image = "image/pet_04_greendragon.png",  desc = "龙族幼崽，龙族血脉提升修炼速度",
      element = "wood", combatStats = { action = "attack", damagePct = 0.18, interval = 3 } },
    { id = 5,  name = "蝴蝶",   quality = "fanqi",     role = "辅助", skill = "迷梦粉尘",   image = "image/pet_05_butterfly.png",    desc = "如玉般通透的蝴蝶，可使敌人昏迷",
      element = "wood", combatStats = { action = "heal", healPct = 0.05, interval = 4 } },
    { id = 6,  name = "黑猫",   quality = "lingbao",   role = "辅助", skill = "暗影潜行",   image = "image/pet_06_blackcat.png",     desc = "神秘黑猫，能隐入暗影辅助偷袭",
      element = "water", combatStats = { action = "heal", healPct = 0.06, interval = 4 } },
    { id = 7,  name = "仙鹤",   quality = "xtlingbao", role = "辅助", skill = "仙鹤引路",   image = "image/pet_07_crane.png",        desc = "仙家之鹤，能引领主人寻找机缘",
      element = "metal", combatStats = { action = "heal", healPct = 0.08, interval = 3 } },
    { id = 8,  name = "雷貂",   quality = "xtlingbao", role = "攻击", skill = "雷光闪击",   image = "image/pet_08_thundermink.png",  desc = "体蕴雷电的灵貂，速度极快",
      element = "metal", combatStats = { action = "attack", damagePct = 0.15, interval = 3 } },
    { id = 9,  name = "水鱼",   quality = "lingbao",   role = "防御", skill = "治愈水泡",   image = "image/pet_09_waterfish.png",    desc = "水系灵鱼，能在战斗中治愈主人",
      element = "water", combatStats = { action = "shield", shieldPct = 0.15, interval = 4 } },
    { id = 10, name = "灵鹿",   quality = "lingbao",   role = "辅助", skill = "草木回春",   image = "image/pet_10_deer.png",         desc = "灵山之鹿，精通草木之道",
      element = "wood", combatStats = { action = "heal", healPct = 0.06, interval = 4 } },
    { id = 11, name = "玄龟",   quality = "xtlingbao", role = "防御", skill = "龟甲壁障",   image = "image/pet_11_turtle.png",       desc = "万年灵龟，防御力极其强大",
      element = "water", combatStats = { action = "shield", shieldPct = 0.20, interval = 3 } },
    { id = 12, name = "灵鼠",   quality = "fanqi",     role = "辅助", skill = "寻宝嗅觉",   image = "image/pet_12_mouse.png",        desc = "机灵小鼠，擅长发现隐藏宝物",
      element = "earth", combatStats = { action = "heal", healPct = 0.05, interval = 4 } },
    { id = 13, name = "蜗牛",   quality = "fanqi",     role = "防御", skill = "缓速结界",   image = "image/pet_13_snail.png",        desc = "通体如玉的蜗牛，能减缓敌人速度",
      element = "earth", combatStats = { action = "shield", shieldPct = 0.12, interval = 4 } },
    { id = 14, name = "金鸟",   quality = "diqi",      role = "辅助", skill = "鹏翼天击",   image = "image/pet_14_goldbird.png",     desc = "大鹏一展翅，天地为之震颤",
      element = "metal", combatStats = { action = "heal", healPct = 0.12, interval = 3 } },
    { id = 15, name = "冰狐",   quality = "xtlingbao", role = "攻击", skill = "冰封千里",   image = "image/pet_15_icefox.png",       desc = "极寒之狐，能冻结大范围敌人",
      element = "water", combatStats = { action = "attack", damagePct = 0.15, interval = 3 } },
    -- 高级灵宠 (高级区域)
    { id = 20, name = "寒冰麒麟", quality = "xianqi",  role = "防御", skill = "玄冰护体",   image = "image/pet_20_iceqilin.png",     desc = "冰属性麒麟，寒气逼人，防御无双",
      element = "water", combatStats = { action = "shield", shieldPct = 0.28, interval = 3 } },
    { id = 21, name = "九尾天狐", quality = "xianqi",  role = "攻击", skill = "天狐幻杀",   image = "image/pet_21_ninetail.png",     desc = "九尾天狐，媚术与杀伐并重",
      element = "fire", combatStats = { action = "attack", damagePct = 0.25, interval = 3 } },
    { id = 22, name = "金翅大鹏", quality = "xianqi",  role = "攻击", skill = "鹏击万里",   image = "image/pet_22_goldpeng.png",     desc = "大鹏展翅遮天蔽日，速度无人能及",
      element = "metal", combatStats = { action = "attack", damagePct = 0.25, interval = 3 } },
    -- 四神兽 (混天墟/太渊秘境 0.1%，固定先天仙器品质)
    { id = 16, name = "青龙",   quality = "xtxianqi", role = "攻击", skill = "苍龙七宿",   image = "image/pet_16_qinglong.png",     desc = "东方神兽，掌管春雷万物生长，龙威震慑一切妖邪",
      element = "wood", combatStats = { action = "attack", damagePct = 0.30, interval = 2 } },
    { id = 17, name = "白虎",   quality = "xtxianqi", role = "攻击", skill = "虎啸山林",   image = "image/pet_17_baihu.png",        desc = "西方神兽，主杀伐之力，虎啸一声百兽臣服",
      element = "metal", combatStats = { action = "attack", damagePct = 0.30, interval = 2 } },
    { id = 18, name = "朱雀",   quality = "xtxianqi", role = "攻击", skill = "涅槃天火",   image = "image/pet_18_zhuque.png",       desc = "南方神兽，浴火重生永恒不灭，天火焚尽一切",
      element = "fire", combatStats = { action = "attack", damagePct = 0.30, interval = 2 } },
    { id = 19, name = "玄武",   quality = "xtxianqi", role = "防御", skill = "龟蛇玄甲",   image = "image/pet_19_xuanwu.png",       desc = "北方神兽，龟蛇合体固若金汤，万法不侵",
      element = "water", combatStats = { action = "shield", shieldPct = 0.35, interval = 3 } },
}

--- 四神兽 id 列表
M.SACRED_BEAST_IDS = { 16, 17, 18, 19 }

-- ============================================================================
-- 灵宠捕获率配置
-- ============================================================================
M.PET_CAPTURE_RATES = {
    yunwu    = 15,
    tianque  = 13,
    donghai  = 12,
    fushan   = 11,
    xuanbing = 10,
    jiutian  = 9,
    wanggu   = 8,
    xianmo   = 7,
    huntian         = 6,
    taiyuan         = 5,
    -- 仙界区域灵宠捕获率（仙界生灵更难捕获）
    sanxian_ye      = 3,
    zhenjing_dong   = 2,
    taiyi_fu        = 1,
    daluo_mijing    = 0,
    hunyan_daochang = 0,
}

--- 灵宠品质概率（与区域联动）
--- 高级区域有概率捕获高品质灵宠
M.PET_QUALITY_RATES = {
    low = {    -- 区域1-2
        fanqi = 50, lingbao = 30, xtlingbao = 15, huangqi = 5, diqi = 0, xianqi = 0, xtxianqi = 0,
    },
    mid = {    -- 区域3-4
        fanqi = 35, lingbao = 30, xtlingbao = 20, huangqi = 10, diqi = 5, xianqi = 0, xtxianqi = 0,
    },
    high = {   -- 区域5-6
        fanqi = 20, lingbao = 25, xtlingbao = 25, huangqi = 15, diqi = 10, xianqi = 5, xtxianqi = 0,
    },
    ultra = {  -- 区域7-8
        fanqi = 10, lingbao = 18, xtlingbao = 22, huangqi = 20, diqi = 18, xianqi = 10, xtxianqi = 2,
    },
    apex = {   -- 区域9-10
        fanqi = 5, lingbao = 10, xtlingbao = 18, huangqi = 22, diqi = 22, xianqi = 15, xtxianqi = 8,
    },
}

--- 根据区域序号获取灵宠品质概率
---@param areaIndex number 区域序号 (1-10)
---@return table
function M.GetPetQualityRates(areaIndex)
    if areaIndex <= 2 then return M.PET_QUALITY_RATES.low end
    if areaIndex <= 4 then return M.PET_QUALITY_RATES.mid end
    if areaIndex <= 6 then return M.PET_QUALITY_RATES.high end
    if areaIndex <= 8 then return M.PET_QUALITY_RATES.ultra end
    return M.PET_QUALITY_RATES.apex
end

-- ============================================================================
-- 11. 试炼列表（8大副本）
-- ============================================================================
M.TRIALS = {
    { id = "wanyao",   name = "万妖塔",   type = "闯关", maxFloor = 100, unlockTier = nil,
      desc = "逐层挑战妖兽，层数越高奖励越丰厚。",
      rewardPerFloor = { lingshi = 20, lingchen = 1 },
      bossFloorInterval = 10,
      bossReward = { lingshi = 200, lingchen = 5 },
    },
    { id = "mijing",   name = "秘境试炼", type = "限时", timeLimit = 1800, unlockTier = nil,
      desc = "限时击败尽可能多的敌人，按击杀数结算奖励。",
      rewardPerKill = { lingshi = 15, lingchen = 1 },
      bonusThresholds = { { kills = 20, reward = { lingshi = 300 } }, { kills = 50, reward = { lingshi = 800, tianyuan = 1 } } },
    },
    { id = "shengsi",  name = "生死擂台", type = "生存", maxFloor = nil, unlockTier = nil,
      desc = "无尽波次的敌人来袭，坚持越久奖励越多。",
      rewardPerWave = { lingshi = 25, lingchen = 1 },
      bonusThresholds = { { waves = 15, reward = { lingshi = 500, jingxue = 2 } }, { waves = 30, reward = { lingshi = 1000, jingxue = 5 } } },
    },
    { id = "xianmo_t", name = "仙魔战场", type = "闯关", maxFloor = 50, unlockTier = 4,
      desc = "仙魔两族交战之地，需金丹期以上方可进入。",
      rewardPerFloor = { lingshi = 50, lingchen = 2 },
      bossFloorInterval = 10,
      bossReward = { lingshi = 500, lingchen = 10, tianyuan = 1 },
    },
    { id = "leijie",   name = "雷劫秘境", type = "闯关", maxFloor = 80, unlockTier = 6,
      desc = "雷劫降临的秘境，只有化神期以上修士才能踏入。",
      rewardPerFloor = { lingshi = 80, lingchen = 3 },
      bossFloorInterval = 10,
      bossReward = { lingshi = 800, lingchen = 15, tianyuan = 2 },
    },
    { id = "shenmo",   name = "神魔试炼", type = "生存", maxFloor = nil, unlockTier = 7,
      desc = "神魔大战遗留的试炼场，需返虚期以上方可挑战。",
      rewardPerWave = { lingshi = 100, lingchen = 4 },
      bonusThresholds = { { waves = 10, reward = { lingshi = 1000, tianyuan = 2 } }, { waves = 25, reward = { lingshi = 3000, tianyuan = 5, jingxue = 5 } } },
    },
    { id = "taigu",    name = "太古遗境", type = "闯关", maxFloor = 60, unlockTier = 9,
      desc = "太古时代遗留的秘境，蕴含上古凶兽的力量。",
      rewardPerFloor = { lingshi = 150, lingchen = 5, tianyuan = 1 },
      bossFloorInterval = 10,
      bossReward = { lingshi = 1500, lingchen = 25, tianyuan = 3, jingxue = 3 },
    },
    { id = "hundun",   name = "混沌试炼", type = "生存", maxFloor = nil, unlockTier = 10,
      desc = "混沌之力肆虐的终极试炼，最顶尖的修士才敢踏入。",
      rewardPerWave = { lingshi = 250, lingchen = 8, tianyuan = 1 },
      bonusThresholds = { { waves = 10, reward = { lingshi = 2500, tianyuan = 5, jingxue = 5 } }, { waves = 20, reward = { lingshi = 5000, tianyuan = 10, jingxue = 10 } } },
    },
}

-- ============================================================================
-- 13. 任务定义
-- ============================================================================

-- 13.2 主线任务
M.MAIN_QUESTS = {
    { id = "mq1", name = "初入修途", desc = "完成角色创建",       condition = "创角完成",  reward = "灵石x200",   rewardItems = { ["灵石"] = 200 } },
    { id = "mq2", name = "首次修炼", desc = "洞府静修1次",        condition = "静修1次",   reward = "培元丹x3",   rewardItems = { ["培元丹"] = 3 } },
    { id = "mq3", name = "出师下山", desc = "首次游历",           condition = "游历1次",   reward = "灵石x300",   rewardItems = { ["灵石"] = 300 } },
    { id = "mq4", name = "筑基之路", desc = "修为达到5000",       condition = "修为>=5000", reward = "筑基丹x1",  rewardItems = { ["筑基丹"] = 1 } },
    { id = "mq5", name = "首入坊市", desc = "购买任意物品",       condition = "购买1件",   reward = "灵石x100",   rewardItems = { ["灵石"] = 100 } },
}

-- 13.1 每日任务模板
M.DAILY_QUESTS = {
    { id = "dq1", name = "每日修炼", desc = "静修1次",        maxProgress = 1, reward = "灵石x50",   rewardItems = { ["灵石"] = 50 } },
    { id = "dq2", name = "采集灵草", desc = "采集灵草3株",    maxProgress = 3, reward = "灵草x5",    rewardItems = { ["灵草"] = 5 } },
    { id = "dq3", name = "击败妖兽", desc = "击败任意妖兽5只", maxProgress = 5, reward = "灵石x100",  rewardItems = { ["灵石"] = 100 } },
    { id = "dq4", name = "炼丹修行", desc = "成功炼丹1次",    maxProgress = 1, reward = "培元丹x2",  rewardItems = { ["培元丹"] = 2 } },
}

-- ============================================================================
-- 难度模式
-- ============================================================================
M.DIFFICULTIES = {
    { id = "normal", name = "普通", statMul = 1.0, dropMul = 1.0, expMul = 1.0, rewardMul = 1.0 },
    { id = "elite",  name = "精英", statMul = 2.0, dropMul = 1.5, expMul = 1.5, rewardMul = 1.5 },
    { id = "hard",   name = "困难", statMul = 3.5, dropMul = 2.0, expMul = 2.0, rewardMul = 2.0 },
}

--- 难度 id → 配置快查
---@type table<string, table>
M.DIFFICULTY_MAP = {}
for _, d in ipairs(M.DIFFICULTIES) do
    M.DIFFICULTY_MAP[d.id] = d
end

-- ============================================================================
-- 区域遭遇表（10区域完整数据）
-- 怪物属性按 roadmap 阶段四设计
-- ============================================================================
M.AREA_ENCOUNTERS = {
    yunwu = {
        combat = {
            { name = "野狼",   baseAtk = 12, baseDef = 8,  baseHP = 60,  reward = 15, weight = 10 },
            { name = "山贼",   baseAtk = 15, baseDef = 10, baseHP = 80,  reward = 18, weight = 10 },
            { name = "毒蛇",   baseAtk = 18, baseDef = 6,  baseHP = 70,  reward = 17, weight = 8 },
            { name = "蜘蛛精", baseAtk = 20, baseDef = 12, baseHP = 100, reward = 22, weight = 6 },
            { name = "螳螂精", baseAtk = 22, baseDef = 10, baseHP = 120, reward = 25, weight = 6 },
        },
        gather = {
            { name = "灵草丛",   drop = "灵草", dropCount = { 1, 3 }, weight = 12 },
            { name = "矿脉",     drop = "矿石", dropCount = { 1, 2 }, weight = 8 },
            { name = "兽骨遗骸", drop = "兽骨", dropCount = { 1, 2 }, weight = 5 },
        },
        nothingWeight = 8,
        boss = {
            name = "树妖王", hpMul = 8, atkMul = 2.5, defMul = 2,
            dropRate = 70, minQuality = "lingbao",
            extraDrop = { { name = "灵草", count = { 3, 6 }, rate = 80 } },
        },
    },
    tianque = {
        combat = {
            { name = "骷髅兵", baseAtk = 30, baseDef = 20, baseHP = 250, reward = 50,  weight = 10 },
            { name = "火虎",   baseAtk = 38, baseDef = 22, baseHP = 300, reward = 60,  weight = 8 },
            { name = "石魔",   baseAtk = 35, baseDef = 30, baseHP = 350, reward = 55,  weight = 7 },
            { name = "僵尸",   baseAtk = 32, baseDef = 25, baseHP = 280, reward = 52,  weight = 8 },
            { name = "怨灵",   baseAtk = 45, baseDef = 18, baseHP = 400, reward = 75,  weight = 5 },
        },
        gather = {
            { name = "灵石矿",   drop = "灵尘", dropCount = { 1, 2 }, weight = 10 },
            { name = "兽骨遗骸", drop = "兽骨",  dropCount = { 1, 3 }, weight = 6 },
        },
        nothingWeight = 6,
        boss = {
            name = "遗迹守卫", hpMul = 10, atkMul = 3, defMul = 2.5,
            dropRate = 80, minQuality = "xtlingbao",
            extraDrop = { { name = "灵尘", count = { 2, 4 }, rate = 60 } },
        },
    },
    donghai = {
        combat = {
            { name = "狐妖", baseAtk = 55, baseDef = 30, baseHP = 450, reward = 100, weight = 10 },
            { name = "天狗", baseAtk = 60, baseDef = 35, baseHP = 500, reward = 110, weight = 8 },
            { name = "金鹰", baseAtk = 65, baseDef = 28, baseHP = 480, reward = 105, weight = 7 },
            { name = "冰熊", baseAtk = 55, baseDef = 45, baseHP = 650, reward = 130, weight = 6 },
            { name = "海蛟", baseAtk = 75, baseDef = 32, baseHP = 700, reward = 140, weight = 4 },
        },
        gather = {
            { name = "灵泉", drop = "灵泉水", dropCount = { 1, 2 }, weight = 7 },
            { name = "海贝堆", drop = "兽骨", dropCount = { 2, 4 }, weight = 10 },
        },
        nothingWeight = 5,
        boss = {
            name = "海蛟龙", hpMul = 12, atkMul = 3.5, defMul = 2.5,
            dropRate = 85, minQuality = "xtlingbao",
            extraDrop = { { name = "灵泉水", count = { 2, 4 }, rate = 70 } },
        },
    },
    fushan = {
        combat = {
            { name = "熔岩魔像", baseAtk = 90,  baseDef = 50, baseHP = 650,  reward = 200, weight = 10 },
            { name = "邪僧",     baseAtk = 100, baseDef = 42, baseHP = 700,  reward = 220, weight = 8 },
            { name = "刺客",     baseAtk = 110, baseDef = 35, baseHP = 600,  reward = 210, weight = 7 },
            { name = "地狱犬",   baseAtk = 105, baseDef = 48, baseHP = 800,  reward = 230, weight = 6 },
            { name = "傀儡师",   baseAtk = 120, baseDef = 45, baseHP = 950,  reward = 240, weight = 4 },
        },
        gather = {
            { name = "天材地宝", drop = "天材地宝", dropCount = { 1, 1 }, weight = 3 },
            { name = "灵泉",     drop = "灵泉水",   dropCount = { 1, 2 }, weight = 5 },
            { name = "灵尘矿",   drop = "灵尘",     dropCount = { 2, 4 }, weight = 8 },
        },
        nothingWeight = 4,
        boss = {
            name = "远古妖龙", hpMul = 15, atkMul = 4, defMul = 3,
            dropRate = 90, minQuality = "huangqi",
            extraDrop = { { name = "天材地宝", count = { 1, 2 }, rate = 60 }, { name = "灵尘", count = { 3, 6 }, rate = 80 } },
        },
    },
    xuanbing = {
        combat = {
            { name = "冰魄兽",   baseAtk = 160, baseDef = 80,  baseHP = 1400, reward = 350, weight = 10 },
            { name = "霜狼王",   baseAtk = 180, baseDef = 75,  baseHP = 1600, reward = 380, weight = 8 },
            { name = "寒冰蛟龙", baseAtk = 200, baseDef = 90,  baseHP = 1800, reward = 400, weight = 6 },
            { name = "雪人",     baseAtk = 170, baseDef = 100, baseHP = 2000, reward = 370, weight = 7 },
            { name = "冰晶傀儡", baseAtk = 210, baseDef = 85,  baseHP = 1700, reward = 420, weight = 4 },
        },
        gather = {
            { name = "寒冰矿",   drop = "灵尘", dropCount = { 2, 5 }, weight = 8 },
            { name = "千年寒玉", drop = "天材地宝", dropCount = { 1, 1 }, weight = 3 },
        },
        nothingWeight = 4,
        boss = {
            name = "冰晶巨龙", hpMul = 15, atkMul = 4, defMul = 3.5,
            dropRate = 90, minQuality = "huangqi",
            extraDrop = { { name = "灵尘", count = { 5, 10 }, rate = 80 }, { name = "天元精魄", count = { 1, 1 }, rate = 15 } },
        },
    },
    jiutian = {
        combat = {
            { name = "雷兽",     baseAtk = 280, baseDef = 120, baseHP = 2500, reward = 600, weight = 10 },
            { name = "电蛟",     baseAtk = 320, baseDef = 110, baseHP = 2800, reward = 650, weight = 8 },
            { name = "雷灵",     baseAtk = 350, baseDef = 100, baseHP = 2600, reward = 680, weight = 6 },
            { name = "风雷鹰",   baseAtk = 300, baseDef = 130, baseHP = 3000, reward = 620, weight = 7 },
            { name = "劫雷傀儡", baseAtk = 380, baseDef = 140, baseHP = 3200, reward = 720, weight = 4 },
        },
        gather = {
            { name = "雷灵石", drop = "灵尘", dropCount = { 3, 6 }, weight = 8 },
            { name = "天雷精华", drop = "天材地宝", dropCount = { 1, 1 }, weight = 3 },
        },
        nothingWeight = 3,
        boss = {
            name = "雷劫天龙", hpMul = 15, atkMul = 4.5, defMul = 3.5,
            dropRate = 95, minQuality = "diqi",
            extraDrop = { { name = "灵尘", count = { 8, 15 }, rate = 90 }, { name = "天元精魄", count = { 1, 2 }, rate = 25 } },
        },
    },
    wanggu = {
        combat = {
            { name = "战魂",     baseAtk = 480, baseDef = 200, baseHP = 4500, reward = 1000, weight = 10 },
            { name = "骨将",     baseAtk = 520, baseDef = 220, baseHP = 5000, reward = 1050, weight = 8 },
            { name = "魔兵",     baseAtk = 550, baseDef = 190, baseHP = 4800, reward = 1080, weight = 6 },
            { name = "亡灵法师", baseAtk = 600, baseDef = 170, baseHP = 4500, reward = 1100, weight = 7 },
            { name = "血魔",     baseAtk = 650, baseDef = 210, baseHP = 5500, reward = 1150, weight = 4 },
        },
        gather = {
            { name = "古战灵石", drop = "灵尘", dropCount = { 5, 10 }, weight = 8 },
            { name = "魔核碎片", drop = "天元精魄", dropCount = { 1, 1 }, weight = 2 },
        },
        nothingWeight = 3,
        boss = {
            name = "远古魔将", hpMul = 18, atkMul = 5, defMul = 4,
            dropRate = 95, minQuality = "diqi",
            extraDrop = { { name = "灵尘", count = { 10, 20 }, rate = 90 }, { name = "天元精魄", count = { 1, 3 }, rate = 35 } },
        },
    },
    xianmo = {
        combat = {
            { name = "堕天使",   baseAtk = 850,  baseDef = 350, baseHP = 7000, reward = 1800, weight = 10 },
            { name = "魔化仙人", baseAtk = 900,  baseDef = 380, baseHP = 7500, reward = 1900, weight = 8 },
            { name = "虚空行者", baseAtk = 950,  baseDef = 320, baseHP = 8000, reward = 2000, weight = 6 },
            { name = "裂隙魔龙", baseAtk = 1000, baseDef = 400, baseHP = 9000, reward = 2100, weight = 5 },
            { name = "时空猎手", baseAtk = 980,  baseDef = 360, baseHP = 8500, reward = 2050, weight = 4 },
        },
        gather = {
            { name = "虚空碎片", drop = "灵尘", dropCount = { 8, 15 }, weight = 6 },
            { name = "仙魔精华", drop = "天元精魄", dropCount = { 1, 2 }, weight = 3 },
            { name = "灵兽残骸", drop = "灵兽精血", dropCount = { 1, 2 }, weight = 3 },
        },
        nothingWeight = 2,
        boss = {
            name = "仙魔之王", hpMul = 20, atkMul = 5.5, defMul = 4.5,
            dropRate = 100, minQuality = "xianqi",
            extraDrop = { { name = "天元精魄", count = { 2, 4 }, rate = 50 }, { name = "灵兽精血", count = { 2, 4 }, rate = 50 } },
        },
    },
    huntian = {
        combat = {
            { name = "混沌兽",   baseAtk = 1400, baseDef = 550, baseHP = 12000, reward = 3400, weight = 10 },
            { name = "噬天魔蛟", baseAtk = 1550, baseDef = 600, baseHP = 13000, reward = 3500, weight = 8 },
            { name = "虚无行者", baseAtk = 1600, baseDef = 520, baseHP = 14000, reward = 3600, weight = 6 },
            { name = "末日使徒", baseAtk = 1700, baseDef = 580, baseHP = 15000, reward = 3700, weight = 5 },
            { name = "毁灭傀儡", baseAtk = 1800, baseDef = 620, baseHP = 16000, reward = 3800, weight = 4 },
        },
        gather = {
            { name = "混沌精华", drop = "天元精魄", dropCount = { 1, 3 }, weight = 4 },
            { name = "虚空灵源", drop = "灵尘", dropCount = { 10, 20 }, weight = 6 },
            { name = "灵兽精魂", drop = "灵兽精血", dropCount = { 1, 3 }, weight = 4 },
        },
        nothingWeight = 2,
        boss = {
            name = "混沌天魔", hpMul = 22, atkMul = 6, defMul = 5,
            dropRate = 100, minQuality = "xianqi",
            extraDrop = { { name = "天元精魄", count = { 3, 5 }, rate = 60 }, { name = "灵兽精血", count = { 3, 5 }, rate = 60 } },
        },
    },
    taiyuan = {
        combat = {
            { name = "太古凶兽",   baseAtk = 2200, baseDef = 850,  baseHP = 20000, reward = 5000, weight = 10 },
            { name = "天魔大圣",   baseAtk = 2400, baseDef = 900,  baseHP = 21000, reward = 5200, weight = 8 },
            { name = "虚空巨龙",   baseAtk = 2600, baseDef = 880,  baseHP = 22000, reward = 5300, weight = 6 },
            { name = "星辰古神",   baseAtk = 2700, baseDef = 950,  baseHP = 23000, reward = 5400, weight = 5 },
            { name = "太渊守护者", baseAtk = 2800, baseDef = 1000, baseHP = 24000, reward = 5500, weight = 4 },
        },
        gather = {
            { name = "太渊精髓", drop = "天元精魄", dropCount = { 2, 4 }, weight = 4 },
            { name = "太古灵源", drop = "灵尘", dropCount = { 15, 30 }, weight = 5 },
            { name = "太渊灵血", drop = "灵兽精血", dropCount = { 2, 4 }, weight = 4 },
        },
        nothingWeight = 1,
        boss = {
            name = "太渊古神", hpMul = 25, atkMul = 7, defMul = 6,
            dropRate = 100, minQuality = "xianqi",
            extraDrop = { { name = "天元精魄", count = { 5, 8 }, rate = 70 }, { name = "灵兽精血", count = { 5, 8 }, rate = 70 } },
        },
    },
    -- -------------------------------------------------------------------------
    -- 仙界区域遭遇表（boss.extraDrop 使用 chance+count 整数，与 handler 保持一致）
    -- -------------------------------------------------------------------------
    sanxian_ye = {
        combat = {
            { name = "散仙魔修", baseAtk = 3500,  baseDef = 1400, baseHP = 30000,  reward = 8000,  weight = 10 },
            { name = "仙灵兽",   baseAtk = 3800,  baseDef = 1300, baseHP = 32000,  reward = 8200,  weight = 9  },
            { name = "天仙游魂", baseAtk = 4000,  baseDef = 1200, baseHP = 28000,  reward = 8500,  weight = 8  },
            { name = "炼器傀儡", baseAtk = 3600,  baseDef = 1600, baseHP = 35000,  reward = 8300,  weight = 6  },
            { name = "仙域巡察", baseAtk = 4200,  baseDef = 1500, baseHP = 38000,  reward = 8800,  weight = 4  },
        },
        gather = {
            { name = "仙灵草丛", drop = "仙灵草", dropCount = { 1, 2 }, weight = 8 },
            { name = "仙元石矿", drop = "仙元石", dropCount = { 1, 1 }, weight = 4 },
            { name = "仙露花圃", drop = "仙灵露", dropCount = { 1, 2 }, weight = 6 },
        },
        nothingWeight = 4,
        boss = {
            name = "仙域守护神", hpMul = 20, atkMul = 4, defMul = 3,
            dropRate = 100, minQuality = "xtxianqi",
            extraDrop = {
                { name = "仙灵丹", count = 3, chance = 80 },
                { name = "仙灵草", count = 5, chance = 90 },
            },
        },
    },
    zhenjing_dong = {
        combat = {
            { name = "洞天守卫", baseAtk = 5500,  baseDef = 2200, baseHP = 55000,  reward = 13000, weight = 10 },
            { name = "玄仙剑修", baseAtk = 6000,  baseDef = 2000, baseHP = 52000,  reward = 13500, weight = 9  },
            { name = "金仙法师", baseAtk = 6500,  baseDef = 1900, baseHP = 50000,  reward = 14000, weight = 7  },
            { name = "仙力蛟龙", baseAtk = 5800,  baseDef = 2500, baseHP = 60000,  reward = 13800, weight = 5  },
            { name = "玄界行者", baseAtk = 6800,  baseDef = 2300, baseHP = 58000,  reward = 14500, weight = 4  },
        },
        gather = {
            { name = "洞天灵泉", drop = "仙灵露", dropCount = { 1, 3 }, weight = 8 },
            { name = "玄仙草地", drop = "仙灵草", dropCount = { 2, 4 }, weight = 7 },
            { name = "金仙矿脉", drop = "仙元石", dropCount = { 1, 2 }, weight = 5 },
        },
        nothingWeight = 3,
        boss = {
            name = "洞天玄龙", hpMul = 22, atkMul = 5, defMul = 4,
            dropRate = 100, minQuality = "xtxianqi",
            extraDrop = {
                { name = "仙灵丹", count = 5, chance = 85 },
                { name = "仙元丹", count = 2, chance = 40 },
                { name = "仙元石", count = 8, chance = 90 },
            },
        },
    },
    taiyi_fu = {
        combat = {
            { name = "太乙符兵", baseAtk = 9000,  baseDef = 3500, baseHP = 90000,  reward = 22000, weight = 10 },
            { name = "仙府卫灵", baseAtk = 9500,  baseDef = 3200, baseHP = 95000,  reward = 22500, weight = 9  },
            { name = "大罗门人", baseAtk = 10000, baseDef = 3000, baseHP = 100000, reward = 23000, weight = 7  },
            { name = "法则战傀", baseAtk = 9200,  baseDef = 4000, baseHP = 110000, reward = 22800, weight = 5  },
            { name = "仙道古兽", baseAtk = 10500, baseDef = 3800, baseHP = 105000, reward = 24000, weight = 4  },
        },
        gather = {
            { name = "太乙仙晶矿", drop = "仙元石",   dropCount = { 2, 3 }, weight = 6 },
            { name = "法则凝晶",   drop = "大罗仙晶", dropCount = { 1, 1 }, weight = 3 },
            { name = "太乙灵露",   drop = "仙灵露",   dropCount = { 2, 4 }, weight = 7 },
        },
        nothingWeight = 2,
        boss = {
            name = "太乙仙君", hpMul = 25, atkMul = 6, defMul = 5,
            dropRate = 100, minQuality = "xtxianqi",
            extraDrop = {
                { name = "仙元丹",   count = 3, chance = 85 },
                { name = "大罗仙晶", count = 2, chance = 50 },
                { name = "仙灵丹",   count = 5, chance = 90 },
            },
        },
    },
    daluo_mijing = {
        combat = {
            { name = "混元魔兵", baseAtk = 16000, baseDef = 6000,  baseHP = 180000, reward = 42000, weight = 10 },
            { name = "大罗遗灵", baseAtk = 17000, baseDef = 5800,  baseHP = 190000, reward = 43000, weight = 9  },
            { name = "斩尸剑灵", baseAtk = 18000, baseDef = 5500,  baseHP = 200000, reward = 45000, weight = 7  },
            { name = "法则傀儡", baseAtk = 16500, baseDef = 7000,  baseHP = 210000, reward = 43500, weight = 5  },
            { name = "混元天龙", baseAtk = 19000, baseDef = 6500,  baseHP = 220000, reward = 47000, weight = 4  },
        },
        gather = {
            { name = "大罗仙晶矿", drop = "大罗仙晶", dropCount = { 1, 2 }, weight = 5 },
            { name = "混元灵液",   drop = "仙灵露",   dropCount = { 3, 5 }, weight = 6 },
            { name = "法则精华",   drop = "仙元石",   dropCount = { 3, 5 }, weight = 6 },
        },
        nothingWeight = 2,
        boss = {
            name = "大罗天君", hpMul = 28, atkMul = 7, defMul = 6,
            dropRate = 100, minQuality = "xtxianqi",
            extraDrop = {
                { name = "大罗仙丹", count = 2, chance = 75 },
                { name = "大罗仙晶", count = 3, chance = 60 },
                { name = "仙元丹",   count = 5, chance = 90 },
                { name = "斩尸珠",   count = 1, chance = 20 },
            },
        },
    },
    hunyan_daochang = {
        combat = {
            { name = "准圣残魂", baseAtk = 30000, baseDef = 12000, baseHP = 380000, reward = 90000,  weight = 10 },
            { name = "洪荒凶兽", baseAtk = 32000, baseDef = 11000, baseHP = 400000, reward = 95000,  weight = 9  },
            { name = "道韵行者", baseAtk = 34000, baseDef = 10500, baseHP = 420000, reward = 100000, weight = 7  },
            { name = "法则魔神", baseAtk = 31000, baseDef = 13000, baseHP = 450000, reward = 95000,  weight = 5  },
            { name = "混元道魔", baseAtk = 36000, baseDef = 12500, baseHP = 480000, reward = 110000, weight = 4  },
        },
        gather = {
            { name = "混元道晶", drop = "大罗仙晶", dropCount = { 2, 3 }, weight = 5 },
            { name = "洪荒灵髓", drop = "仙灵露",   dropCount = { 5, 8 }, weight = 6 },
            { name = "准圣精华", drop = "仙元石",   dropCount = { 5, 8 }, weight = 5 },
        },
        nothingWeight = 1,
        boss = {
            name = "混元天道", hpMul = 35, atkMul = 9, defMul = 8,
            dropRate = 100, minQuality = "xtxianqi",
            extraDrop = {
                { name = "大罗仙丹", count = 3, chance = 85 },
                { name = "大罗仙晶", count = 5, chance = 70 },
                { name = "斩尸珠",   count = 1, chance = 35 },
                { name = "混元珠",   count = 1, chance = 15 },
            },
        },
    },
}

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据id获取区域
---@param id string
---@return table|nil
function M.GetArea(id)
    for _, a in ipairs(M.AREAS) do
        if a.id == id then return a end
    end
    return nil
end

--- 获取区域序号
---@param areaId string
---@return number
function M.GetAreaIndex(areaId)
    return M.AREA_INDEX[areaId] or 1
end

--- 获取指定区域的怪物列表
---@param areaId string
---@return table
function M.GetMonstersByArea(areaId)
    local result = {}
    for _, m in ipairs(M.MONSTERS) do
        if m.areaId == areaId then
            result[#result + 1] = m
        end
    end
    return result
end

--- 根据id获取灵宠模板
---@param id number
---@return table|nil
function M.GetPet(id)
    for _, pet in ipairs(M.PETS) do
        if pet.id == id then return pet end
    end
    return nil
end

--- 根据id获取难度配置
---@param diffId string 如 "normal"/"elite"/"hard"
---@return table
function M.GetDifficulty(diffId)
    return M.DIFFICULTY_MAP[diffId or "normal"] or M.DIFFICULTIES[1]
end

--- 获取区域遭遇配置
---@param areaId string
---@return table|nil
function M.GetAreaEncounters(areaId)
    return M.AREA_ENCOUNTERS[areaId]
end

--- 获取灵宠捕获率
---@param areaId string
---@return number
function M.GetPetCaptureRate(areaId)
    return M.PET_CAPTURE_RATES[areaId] or 10
end

--- 检查玩家是否已解锁某区域
---@param areaId string
---@param playerTier number
---@param playerSub number
---@return boolean, string|nil
function M.IsAreaUnlocked(areaId, playerTier, playerSub)
    local area = M.GetArea(areaId)
    if not area then return false, "区域不存在" end
    playerTier = playerTier or 1
    playerSub = playerSub or 1
    if playerTier > area.unlockTier then return true end
    if playerTier == area.unlockTier and playerSub >= (area.unlockSub or 1) then return true end
    return false, "需要" .. (area.unlockTier or 1) .. "阶境界"
end

--- 根据id获取试炼
---@param id string
---@return table|nil
function M.GetTrial(id)
    for _, t in ipairs(M.TRIALS) do
        if t.id == id then return t end
    end
    return nil
end

-- ============================================================================
-- 组队 Boss 全局配置
-- ============================================================================

M.GROUP_BOSS_CONFIG = {
    minPlayers    = 2,       -- 最少开战人数
    maxPlayers    = 5,       -- 房间人数上限
    roundInterval = 0.8,     -- 每回合间隔（秒）
    maxRounds     = 100,     -- 最大回合数
    roomTimeout   = 120,     -- 等待超时（秒）
    hpScale       = 0.7,     -- 每多一人 Boss 额外 HP 倍率
    atkScale      = 1.2,     -- 组队 Boss 攻击相对单人倍率
    defScale      = 1.1,     -- 组队 Boss 防御相对单人倍率
    -- 每个区域 Boss 灵石基础奖励（按 AREA_INDEX 顺序，1-15）
    rewardLingShi = { 80, 200, 400, 800, 1500, 2500, 4000, 6000, 9000, 15000,
                      25000, 40000, 60000, 90000, 130000 },
}

--- 获取组队 Boss 配置
---@return table
function M.GetGroupBossConfig()
    return M.GROUP_BOSS_CONFIG
end

--- 获取所有仙界区域列表（isImmortal = true 的区域）
---@return table
function M.GetImmortalAreas()
    local result = {}
    for _, a in ipairs(M.AREAS) do
        if a.isImmortal then
            result[#result + 1] = a
        end
    end
    return result
end

return M
