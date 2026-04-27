------------------------------------------------------------
-- data/data_skills.lua  —— 英雄结构化技能数据
-- 替代 battle_engine.lua 中 parseSkillFromDesc 的正则解析
-- 字段与 battle_engine 的 16 个消费点完全对齐
------------------------------------------------------------

local M = {}

------------------------------------------------------------
-- 结构说明:
--
-- effects[]  主动技能效果列表
--   .type       "damage"|"magic"|"heal"|"shield"|"buff"
--   .target     目标类型(见 battle_engine TARGET 常量)
--   .multiplier 伤害倍率(damage/magic)
--   .pct        百分比(heal/shield)
--   .buff/.dur  buff 类型和持续回合
--
-- statusEffect  技能命中后附加状态
--   .status     状态key
--   .rate       触发概率 0~1
--   .dur        持续回合
--   .isAlly     是否对友方
--
-- extras  高级战斗机制(14种)
--   .lifesteal           吸血比例
--   .pursuitOnKill       击杀追击
--   .killMoraleBonus     击杀回怒值
--   .counterRate         反击概率
--   .deathImmune         免死
--   .immuneControl       免控回合数
--   .executeThreshold    斩杀血线
--   .executeRate         斩杀概率
--   .ignoreDefense       无视防御比例
--   .selfHealPerTurn     每回合自回血比例
--   .allyMoraleBoost     全队增怒点数
--   .enemyMoraleReduce   全敌减怒点数
--   .debuffZhi           降智比例
--   .critBonus           暴击加成
--   .pursuitOnShieldBreak 破盾追击
--   .atkSelfShield       普攻后自身护盾比例
--
-- passiveStatusEffect  普攻被动附加状态
--   .status     状态key
--   .rate       概率 0~1
--   .dur        持续回合
------------------------------------------------------------

M.SKILL_DATA = {

    -- ==================================================================
    -- 魏 (wei) — 6 heroes
    -- ==================================================================

    -- 曹操: skill="无", 辅助统帅
    -- passiveDesc="战法增伤12%并为全队增怒15点"
    -- 注: "战法增伤12%"引擎无消费点, 仅展示; 增怒通过 extras
    caocao = {
        extras = { allyMoraleBoost = 15 },
    },

    -- 夏侯惇: "对前排单体造成160%物理伤害，被攻击时30%概率反击"
    xiaohoudun = {
        effects = {
            { type = "damage", target = "front_single", multiplier = 1.60 },
        },
        extras = { counterRate = 0.30 },
    },

    -- 张辽: "对纵排敌军造成240%物理伤害，击杀目标后追击一次"
    zhangliao = {
        effects = {
            { type = "damage", target = "line", multiplier = 2.40 },
        },
        extras = { pursuitOnKill = true },
    },

    -- 郭嘉: skill="无", 控场法师
    -- passiveDesc="战法减怒20并降智15%持续2回合"
    guojia = {
        extras = {
            enemyMoraleReduce = 20,
            debuffZhi         = 0.15,
        },
    },

    -- 司马懿: skill="无", 持续法核
    -- passiveDesc="法伤附灼烧持续消耗敌军"
    simayi = {
        passiveStatusEffect = { status = "burn", rate = 1.0, dur = 1 },
    },

    -- 甄姬: skill="无", 治疗辅助
    -- passiveDesc="治疗时净化友军负面状态" → 引擎无净化机制
    zhenji = {},

    -- ==================================================================
    -- 蜀 (shu) — 9 heroes
    -- ==================================================================

    -- 刘备: "为全体友军恢复20%兵力，并附加10%护盾持续2回合"
    liubei = {
        effects = {
            { type = "heal",   target = "ally_all", pct = 0.20 },
            { type = "shield", target = "ally_all", pct = 0.10 },
        },
    },

    -- 关羽: "对纵排敌军造成250%物理伤害，半血以下目标斩杀率+20%"
    guanyu = {
        effects = {
            { type = "damage", target = "line", multiplier = 2.50 },
        },
        extras = {
            executeThreshold = 0.5,
            executeRate      = 0.20,
        },
    },

    -- 张飞: "对前排全体造成230%物理伤害，35%概率眩晕目标1回合"
    -- passiveDesc="攻击35%概率眩晕敌人"
    zhangfei = {
        effects = {
            { type = "damage", target = "front", multiplier = 2.30 },
        },
        statusEffect = { status = "stun", rate = 0.35, dur = 1 },
        passiveStatusEffect = { status = "stun", rate = 0.35, dur = 1 },
    },

    -- 赵云: "对纵排敌军造成245%物理伤害，自身获得15%兵力护盾"
    -- passiveDesc="攻击后获得自身15%护盾"
    zhaoyun = {
        effects = {
            { type = "damage", target = "line", multiplier = 2.45 },
        },
        extras = { atkSelfShield = 0.15 },
    },

    -- 诸葛亮: skill="无", 法控核心
    -- passiveDesc="法伤40%概率沉默敌人"
    zhugeliang = {
        passiveStatusEffect = { status = "silence", rate = 0.40, dur = 1 },
    },

    -- 庞统: skill="无", 爆发法师
    -- passiveDesc="法伤附灼烧持续伤害"
    pangtong = {
        passiveStatusEffect = { status = "burn", rate = 1.0, dur = 1 },
    },

    -- 黄月英: skill="无", 机关辅助
    -- passiveDesc="全队增攻速并召唤机关协攻" → 引擎无此机制
    huangyueying = {},

    -- 马超: "对后排单体造成310%物理伤害，击杀目标回复30点士气"
    machao = {
        effects = {
            { type = "damage", target = "back_single", multiplier = 3.10 },
        },
        extras = { killMoraleBonus = 30 },
    },

    -- 黄忠: "对血量最高的单体造成320%物理伤害，无视目标50%防御"
    huangzhong = {
        effects = {
            { type = "damage", target = "highest_hp", multiplier = 3.20 },
        },
        extras = { ignoreDefense = 0.50 },
    },

    -- ==================================================================
    -- 吴 (wu) — 9 heroes
    -- ==================================================================

    -- 孙权: "为全体友军增加命中+12%、暴击+8%，并回复15点士气"
    -- 注: "命中+12%"引擎无消费点, 仅展示
    sunquan = {
        effects = {
            { type = "buff", target = "ally_all", buff = "atk_up", dur = 2 },
        },
        extras = {
            critBonus       = 0.08,
            allyMoraleBoost = 15,
        },
    },

    -- 孙策: "对前排全体造成260%物理伤害，吸取造成伤害的30%回复自身兵力"
    sunce = {
        effects = {
            { type = "damage", target = "front", multiplier = 2.60 },
        },
        extras = { lifesteal = 0.30 },
    },

    -- 周瑜: skill="无", 灼烧法核
    -- passiveDesc="法伤附灼烧持续灼伤敌军"
    zhouyu = {
        passiveStatusEffect = { status = "burn", rate = 1.0, dur = 1 },
    },

    -- 陆逊: "对横排全体造成200%法术伤害，灼烧效果扩散至相邻目标"
    luxun = {
        effects = {
            { type = "magic", target = "row", multiplier = 2.00 },
        },
        statusEffect = { status = "burn", rate = 1.0, dur = 2, isAlly = false },
    },

    -- 甘宁: "对单体造成180%物理伤害，本次攻击暴击率+15%"
    ganning = {
        effects = {
            { type = "damage", target = "single", multiplier = 1.80 },
        },
        extras = { critBonus = 0.15 },
    },

    -- 太史慈: "对随机2个敌军单体各造成210%物理伤害"
    taishici = {
        effects = {
            { type = "damage", target = "double", multiplier = 2.10 },
        },
    },

    -- 大乔: skill="无", 护盾辅助
    -- passiveDesc="为全队施加20%护盾抵挡伤害" → 通过 support 兵种行动
    daqiao = {},

    -- 小乔: skill="无", 法攻副C
    -- passiveDesc="法伤30%概率魅惑敌人"
    xiaoqiao = {
        passiveStatusEffect = { status = "charm", rate = 0.30, dur = 1 },
    },

    -- 孙尚香: "对随机2个敌军单体各造成145%物理伤害"
    sunshangxiang = {
        effects = {
            { type = "damage", target = "double", multiplier = 1.45 },
        },
    },

    -- ==================================================================
    -- 群 (qun) — 7 heroes
    -- ==================================================================

    -- 吕布: "对纵排敌军造成265%物理伤害，35%概率附破甲效果持续2回合"
    -- passiveDesc="攻击35%概率附破甲"
    lvbu = {
        effects = {
            { type = "damage", target = "line", multiplier = 2.65 },
        },
        statusEffect = { status = "armor_break", rate = 0.35, dur = 2 },
        passiveStatusEffect = { status = "armor_break", rate = 0.35, dur = 1 },
    },

    -- 貂蝉: skill="无", 控制辅助
    -- passiveDesc="法伤40%概率混乱敌人"
    diaochan = {
        passiveStatusEffect = { status = "charm", rate = 0.40, dur = 1 },
    },

    -- 华佗: skill="无", 顶级治疗
    -- passiveDesc="群疗并附持续回血效果" → 通过 support/medic 兵种行动
    huatuo = {},

    -- 董卓: "对前排单体造成180%物理伤害，自身每回合自动恢复8%兵力"
    dongzhuo = {
        effects = {
            { type = "damage", target = "front_single", multiplier = 1.80 },
        },
        extras = { selfHealPerTurn = 0.08 },
    },

    -- 袁绍: skill="无", 统帅辅助
    -- passiveDesc="全队增怒10点并增加攻击力"
    -- 注: "增加攻击力"引擎无消费点, 仅展示
    yuanshao = {
        extras = { allyMoraleBoost = 10 },
    },

    -- 左慈: skill="无", 控制法核
    -- passiveDesc="法伤50%概率控制敌人" (控制=眩晕)
    zuoci = {
        passiveStatusEffect = { status = "stun", rate = 0.50, dur = 1 },
    },

    -- 蔡文姬: skill="无", 治疗辅助
    -- passiveDesc="治疗15%并增加友军防御" → 通过 support/dancer 兵种行动
    caiwenji = {},

    -- ==================================================================
    -- 特殊进阶 — 2 heroes
    -- ==================================================================

    -- 魔吕布: "自身免控1回合，对纵排敌军造成285%物理伤害，首次被击杀时免死1次"
    molvbu = {
        effects = {
            { type = "damage", target = "line", multiplier = 2.85 },
        },
        extras = {
            immuneControl = 1,
            deathImmune   = true,
        },
    },

    -- 神吕布: "对纵排敌军造成320%物理伤害，破盾后追击一次，半血以下目标斩杀率+30%"
    shenlvbu = {
        effects = {
            { type = "damage", target = "line", multiplier = 3.20 },
        },
        extras = {
            pursuitOnShieldBreak = true,
            executeThreshold     = 0.5,
            executeRate          = 0.30,
        },
    },
}

return M
