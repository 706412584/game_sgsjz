---@meta
--- 三国神将录 - 英雄完整数据表
--- Spec 04: 英雄数据配置
--- 来源: 设计文档 Section 17 核心武将数值总表
--- + 现有 page_heroes.lua 中的角色补充

local M = {}

----------------------------------------------------------------------------
-- 品质常量
----------------------------------------------------------------------------
M.QUALITY_GREEN  = 1  -- 绿
M.QUALITY_BLUE   = 2  -- 蓝
M.QUALITY_PURPLE = 3  -- 紫
M.QUALITY_ORANGE = 4  -- 橙
M.QUALITY_RED    = 5  -- 红
M.QUALITY_GOLD   = 6  -- 金

--- 品质中文名
M.QUALITY_NAMES = {
    [1] = "绿", [2] = "蓝", [3] = "紫",
    [4] = "橙", [5] = "红", [6] = "金",
}

----------------------------------------------------------------------------
-- 势力常量
----------------------------------------------------------------------------
M.FACTION_WEI = "wei"
M.FACTION_SHU = "shu"
M.FACTION_WU  = "wu"
M.FACTION_QUN = "qun"

M.FACTION_NAMES = {
    wei = "魏", shu = "蜀", wu = "吴", qun = "群",
}

----------------------------------------------------------------------------
-- 定位/角色类型
----------------------------------------------------------------------------
M.ROLE_NAMES = {
    tank       = "前排坦克",
    melee_dps  = "前排输出",
    ranged_dps = "远程输出",
    mage       = "法攻主C",
    support    = "辅助治疗",
    control    = "控制法师",
    assassin   = "突击收割",
    commander  = "统帅辅助",
}

----------------------------------------------------------------------------
-- 英雄数据库
-- 字段说明:
--   name      : 中文名
--   quality   : 品质等级 (3=紫, 4=橙, 5=红, 6=金)
--   faction   : 势力 (wei/shu/wu/qun)
--   role      : 定位描述 (中文)
--   stats     : { tong, yong, zhi } 基础三围 (1级裸将)
--   caps      : { tong, yong, zhi } 三围上限 (不含装备/羁绊/Buff)
--   skill     : 战法名
--   skillDesc : 战法描述
--   evolve    : 进阶名称 (nil表示无进阶)
--   avatar    : 头像资源文件名 (nil则按 hero_{id} 查找)
----------------------------------------------------------------------------

---@class HeroData
---@field name string
---@field quality number
---@field faction string
---@field role string
---@field stats {tong:number, yong:number, zhi:number}
---@field caps {tong:number, yong:number, zhi:number}
---@field skill string
---@field skillDesc string
---@field passive string|nil      -- 被动技能名称
---@field passiveDesc string|nil  -- 被动技能描述
---@field lore string|nil         -- 人物列传
---@field evolve string|nil
---@field avatar string|nil

---@type table<string, HeroData>
M.HEROES = {

    -- ======================================================================
    -- 魏 (wei)
    -- ======================================================================

    caocao = {
        name    = "曹操",
        quality = 4,  -- 橙
        faction = "wei",
        role    = "辅助统帅",
        stats   = { tong = 97, yong = 91, zhi = 103, hp = 3000 },
        caps    = { tong = 232, yong = 216, zhi = 248 },
        skill   = "无",
        skillDesc = "无",
        passive = "奸雄",
        passiveDesc = "战法增伤12%并为全队回怒",
        lore    = "挟天子以令诸侯，一代枭雄，文武兼备，奠定曹魏基业。",
        evolve  = "乱世曹操",
    },
    xiaohoudun = {
        name    = "夏侯惇",
        quality = 3,  -- 紫
        faction = "wei",
        role    = "前排反击坦",
        stats   = { tong = 96, yong = 88, zhi = 56, hp = 3000 },
        caps    = { tong = 230, yong = 210, zhi = 165 },
        skill   = "拔矢啖睛",
        skillDesc = "对前排单体造成160%物理伤害，被攻击时30%概率反击",
        passive = "刚烈",
        passiveDesc = "被攻击时30%概率反击",
        evolve  = nil,
    },
    zhangliao = {
        name    = "张辽",
        quality = 4,  -- 橙
        faction = "wei",
        role    = "突击收割",
        stats   = { tong = 95, yong = 117, zhi = 79, hp = 3000 },
        caps    = { tong = 236, yong = 276, zhi = 203 },
        skill   = "威震逍遥",
        skillDesc = "对纵排敌军造成240%物理伤害，击杀目标后追击一次",
        passive = "疾驰",
        passiveDesc = "击杀敌人后追击一次",
        evolve  = "破军张辽",
    },
    guojia = {
        name    = "郭嘉",
        quality = 4,  -- 橙
        faction = "wei",
        role    = "控场法师",
        stats   = { tong = 78, yong = 73, zhi = 141, hp = 3000 },
        caps    = { tong = 214, yong = 208, zhi = 315 },
        skill   = "无",
        skillDesc = "无",
        passive = "鬼才",
        passiveDesc = "战法减敌怒并降低智力",
        evolve  = "寒星郭嘉",
    },
    simayi = {
        name    = "司马懿",
        quality = 5,  -- 红
        faction = "wei",
        role    = "持续法核",
        stats   = { tong = 93, yong = 99, zhi = 168, hp = 3000 },
        caps    = { tong = 247, yong = 247, zhi = 371 },
        skill   = "无",
        skillDesc = "无",
        passive = "隐忍",
        passiveDesc = "法伤附灼烧持续消耗敌军",
        evolve  = "冥策司马懿",
    },
    zhenji = {
        name    = "甄姬",
        quality = 3,  -- 紫
        faction = "wei",
        role    = "治疗辅助",
        stats   = { tong = 58, yong = 46, zhi = 102, hp = 3000 },
        caps    = { tong = 160, yong = 145, zhi = 235 },
        skill   = "无",
        skillDesc = "无",
        passive = "洛水清波",
        passiveDesc = "治疗时净化友军负面状态",
        evolve  = nil,
    },

    -- ======================================================================
    -- 蜀 (shu)
    -- ======================================================================

    liubei = {
        name    = "刘备",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "治疗统帅",
        stats   = { tong = 100, yong = 84, zhi = 107, hp = 3000 },
        caps    = { tong = 238, yong = 216, zhi = 259 },
        skill   = "仁德载物",
        skillDesc = "为全体友军恢复20%兵力，并附加10%护盾持续2回合",
        passive = "仁德",
        passiveDesc = "治疗全军并附护盾",
        evolve  = "汉昭刘备",
    },
    guanyu = {
        name    = "关羽",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "普攻斩将",
        stats   = { tong = 103, yong = 119, zhi = 69, hp = 3000 },
        caps    = { tong = 244, yong = 271, zhi = 190 },
        skill   = "青龙偃月",
        skillDesc = "对纵排敌军造成250%物理伤害，半血以下目标斩杀率+20%",
        passive = "武圣",
        passiveDesc = "半血以下目标斩杀率+20%",
        evolve  = "武圣关羽",
    },
    zhangfei = {
        name    = "张飞",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "前排爆发坦",
        stats   = { tong = 118, yong = 125, zhi = 49, hp = 3000 },
        caps    = { tong = 277, yong = 286, zhi = 167 },
        skill   = "丈八蛇矛",
        skillDesc = "对前排全体造成230%物理伤害，35%概率眩晕目标1回合",
        passive = "万夫不当",
        passiveDesc = "攻击35%概率眩晕敌人",
        evolve  = "狂战张飞",
    },
    zhaoyun = {
        name    = "赵云",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "全能突击",
        stats   = { tong = 98, yong = 112, zhi = 81, hp = 3000 },
        caps    = { tong = 240, yong = 262, zhi = 205 },
        skill   = "七进七出",
        skillDesc = "对纵排敌军造成245%物理伤害，自身获得15%兵力护盾",
        passive = "龙胆",
        passiveDesc = "攻击后获得自身15%护盾",
        evolve  = "神枪赵云",
    },
    zhugeliang = {
        name    = "诸葛亮",
        quality = 5,  -- 红
        faction = "shu",
        role    = "法控核心",
        stats   = { tong = 96, yong = 75, zhi = 189, hp = 3000 },
        caps    = { tong = 255, yong = 225, zhi = 413 },
        skill   = "无",
        skillDesc = "无",
        passive = "卧龙",
        passiveDesc = "法伤40%概率沉默敌人",
        evolve  = "神机诸葛",
    },
    pangtong = {
        name    = "庞统",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "爆发法师",
        stats   = { tong = 74, yong = 66, zhi = 150, hp = 3000 },
        caps    = { tong = 197, yong = 191, zhi = 324 },
        skill   = "无",
        skillDesc = "无",
        passive = "凤雏",
        passiveDesc = "法伤附灼烧持续伤害",
        evolve  = "凤鸣庞统",
    },
    huangyueying = {
        name    = "黄月英",
        quality = 3,  -- 紫
        faction = "shu",
        role    = "机关辅助",
        stats   = { tong = 70, yong = 64, zhi = 102, hp = 3000 },
        caps    = { tong = 185, yong = 170, zhi = 230 },
        skill   = "无",
        skillDesc = "无",
        passive = "机巧",
        passiveDesc = "全队增攻速并召唤机关协攻",
        evolve  = nil,
    },
    machao = {
        name    = "马超",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "战法单切",
        stats   = { tong = 94, yong = 129, zhi = 67, hp = 3000 },
        caps    = { tong = 236, yong = 290, zhi = 190 },
        skill   = "西凉铁骑",
        skillDesc = "对后排单体造成310%物理伤害，击杀目标回复30点士气",
        passive = "铁骑",
        passiveDesc = "击杀敌人回复30怒气",
        evolve  = "飞骑马超",
    },
    huangzhong = {
        name    = "黄忠",
        quality = 4,  -- 橙 (从现有页面保留, 设计文档未单独列出但在章7可招募)
        faction = "shu",
        role    = "弓箭主C",
        stats   = { tong = 97, yong = 122, zhi = 70, hp = 3000 },
        caps    = { tong = 238, yong = 278, zhi = 198 },
        skill   = "百步穿杨",
        skillDesc = "对血量最高的单体造成320%物理伤害，无视目标50%防御",
        passive = "神射",
        passiveDesc = "攻击无视50%防御",
        evolve  = nil,
    },

    -- ======================================================================
    -- 吴 (wu)
    -- ======================================================================

    sunquan = {
        name    = "孙权",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "平衡统帅",
        stats   = { tong = 94, yong = 90, zhi = 105, hp = 3000 },
        caps    = { tong = 228, yong = 225, zhi = 255 },
        skill   = "帝业天下",
        skillDesc = "为全体友军增加命中+12%、暴击+8%，并回复15点士气",
        passive = "制衡",
        passiveDesc = "全队命中暴击提升并回怒",
        evolve  = "帝略孙权",
    },
    sunce = {
        name    = "孙策",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "前排战法核",
        stats   = { tong = 103, yong = 120, zhi = 67, hp = 3000 },
        caps    = { tong = 251, yong = 277, zhi = 192 },
        skill   = "霸王一击",
        skillDesc = "对前排全体造成260%物理伤害，吸取造成伤害的30%回复自身兵力",
        passive = "霸体",
        passiveDesc = "战法吸血30%回复兵力",
        evolve  = "霸王孙策",
    },
    zhouyu = {
        name    = "周瑜",
        quality = 5,  -- 红
        faction = "wu",
        role    = "灼烧法核",
        stats   = { tong = 89, yong = 86, zhi = 185, hp = 3000 },
        caps    = { tong = 245, yong = 238, zhi = 405 },
        skill   = "无",
        skillDesc = "无",
        passive = "业火",
        passiveDesc = "法伤附灼烧持续灼伤敌军",
        evolve  = "赤天周瑜",
    },
    luxun = {
        name    = "陆逊",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "持续法师",
        stats   = { tong = 78, yong = 74, zhi = 138, hp = 3000 },
        caps    = { tong = 208, yong = 200, zhi = 300 },
        skill   = "火烧连营",
        skillDesc = "对横排全体造成200%法术伤害，灼烧效果扩散至相邻目标",
        passive = "火攻",
        passiveDesc = "灼烧可扩散至相邻目标",
        evolve  = "炎谋陆逊",
    },
    ganning = {
        name    = "甘宁",
        quality = 3,  -- 紫
        faction = "wu",
        role    = "普攻暴击",
        stats   = { tong = 76, yong = 98, zhi = 56, hp = 3000 },
        caps    = { tong = 198, yong = 232, zhi = 160 },
        skill   = "百骑劫营",
        skillDesc = "对单体造成180%物理伤害，本次攻击暴击率+15%",
        passive = "锦帆",
        passiveDesc = "暴击率+15%",
        evolve  = nil,
    },
    taishici = {
        name    = "太史慈",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "双击主C",
        stats   = { tong = 97, yong = 115, zhi = 78, hp = 3000 },
        caps    = { tong = 236, yong = 274, zhi = 205 },
        skill   = "双目标打击",
        skillDesc = "对随机2个敌军单体各造成210%物理伤害",
        passive = "双矢",
        passiveDesc = "战法同时攻击2个目标",
        evolve  = "裂空太史慈",
    },
    daqiao = {
        name    = "大乔",
        quality = 3,  -- 紫
        faction = "wu",
        role    = "护盾辅助",
        stats   = { tong = 62, yong = 42, zhi = 104, hp = 3000 },
        caps    = { tong = 165, yong = 140, zhi = 236 },
        skill   = "无",
        skillDesc = "无",
        passive = "国色",
        passiveDesc = "为全队施加护盾抵挡伤害",
        evolve  = nil,
    },
    xiaoqiao = {
        name    = "小乔",
        quality = 3,  -- 紫
        faction = "wu",
        role    = "法攻副C",
        stats   = { tong = 56, yong = 48, zhi = 108, hp = 3000 },
        caps    = { tong = 150, yong = 145, zhi = 240 },
        skill   = "无",
        skillDesc = "无",
        passive = "天香",
        passiveDesc = "法伤30%概率魅惑敌人",
        evolve  = nil,
    },
    sunshangxiang = {
        name    = "孙尚香",
        quality = 3,  -- 紫 (现有页面角色, 补充三围上限)
        faction = "wu",
        role    = "弓箭输出",
        stats   = { tong = 78, yong = 94, zhi = 65, hp = 3000 },
        caps    = { tong = 195, yong = 225, zhi = 170 },
        skill   = "烈弓连珠",
        skillDesc = "对随机2个敌军单体各造成145%物理伤害",
        passive = "烈弓",
        passiveDesc = "攻击可命中多个目标",
        evolve  = nil,
    },

    -- ======================================================================
    -- 群 (qun)
    -- ======================================================================

    lvbu = {
        name    = "吕布",
        quality = 4,  -- 橙
        faction = "qun",
        role    = "战法主C",
        stats   = { tong = 101, yong = 139, zhi = 50, hp = 3000 },
        caps    = { tong = 231, yong = 273, zhi = 173 },
        skill   = "无双破军",
        skillDesc = "对纵排敌军造成265%物理伤害，35%概率附破甲效果持续2回合",
        passive = "无双",
        passiveDesc = "攻击35%概率附破甲",
        evolve  = "魔吕布",
    },
    diaochan = {
        name    = "貂蝉",
        quality = 4,  -- 橙
        faction = "qun",
        role    = "控制辅助",
        stats   = { tong = 78, yong = 70, zhi = 143, hp = 3000 },
        caps    = { tong = 206, yong = 200, zhi = 310 },
        skill   = "无",
        skillDesc = "无",
        passive = "离间",
        passiveDesc = "法伤40%概率混乱敌人",
        evolve  = "绝代貂蝉",
    },
    huatuo = {
        name    = "华佗",
        quality = 4,  -- 橙
        faction = "qun",
        role    = "顶级治疗",
        stats   = { tong = 86, yong = 59, zhi = 145, hp = 3000 },
        caps    = { tong = 221, yong = 178, zhi = 313 },
        skill   = "无",
        skillDesc = "无",
        passive = "妙手",
        passiveDesc = "群疗并附持续回血效果",
        evolve  = "仙医华佗",
    },
    dongzhuo = {
        name    = "董卓",
        quality = 3,  -- 紫
        faction = "qun",
        role    = "前排肉盾",
        stats   = { tong = 110, yong = 90, zhi = 42, hp = 3000 },
        caps    = { tong = 248, yong = 215, zhi = 145 },
        skill   = "暴虐横行",
        skillDesc = "对前排单体造成180%物理伤害，自身每回合自动恢复8%兵力",
        passive = "暴虐",
        passiveDesc = "每回合自动回复8%兵力",
        evolve  = nil,
    },
    yuanshao = {
        name    = "袁绍",
        quality = 3,  -- 紫
        faction = "qun",
        role    = "统帅辅助",
        stats   = { tong = 84, yong = 78, zhi = 88, hp = 3000 },
        caps    = { tong = 210, yong = 195, zhi = 220 },
        skill   = "无",
        skillDesc = "无",
        passive = "盟主",
        passiveDesc = "全队增加兵力和攻击力",
        evolve  = nil,
    },
    zuoci = {
        name    = "左慈",
        quality = 5,  -- 红
        faction = "qun",
        role    = "控制法核",
        stats   = { tong = 96, yong = 78, zhi = 186, hp = 3000 },
        caps    = { tong = 258, yong = 233, zhi = 408 },
        skill   = "无",
        skillDesc = "无",
        passive = "幻术",
        passiveDesc = "法伤50%概率控制敌人",
        evolve  = "太虚左慈",
    },
    caiwenji = {
        name    = "蔡文姬",
        quality = 3,  -- 紫 (现有页面角色, 补充三围)
        faction = "qun",
        role    = "治疗辅助",
        stats   = { tong = 52, yong = 40, zhi = 108, hp = 3000 },
        caps    = { tong = 155, yong = 140, zhi = 240 },
        skill   = "无",
        skillDesc = "无",
        passive = "悲歌",
        passiveDesc = "治疗并增加友军防御",
        evolve  = nil,
    },

    -- ======================================================================
    -- 特殊进阶 (红/金品质)
    -- ======================================================================

    molvbu = {
        name    = "魔吕布",
        quality = 5,  -- 红
        faction = "qun",
        role    = "反控爆发核",
        stats   = { tong = 125, yong = 170, zhi = 65, hp = 3000 },
        caps    = { tong = 279, yong = 323, zhi = 207 },
        skill   = "魔神降世",
        skillDesc = "自身免控1回合，对纵排敌军造成285%物理伤害，首次被击杀时免死1次",
        passive = "魔神",
        passiveDesc = "免控1回合，首次致死免死",
        evolve  = "神吕布",
    },
    shenlvbu = {
        name    = "神吕布",
        quality = 6,  -- 金
        faction = "qun",
        role    = "终局神将",
        stats   = { tong = 151, yong = 195, zhi = 84, hp = 3000 },
        caps    = { tong = 321, yong = 371, zhi = 241 },
        skill   = "天神无双",
        skillDesc = "对纵排敌军造成320%物理伤害，破盾后追击一次，半血以下目标斩杀率+30%",
        passive = "天神",
        passiveDesc = "破盾追击，半血以下斩杀率+30%",
        evolve  = nil,  -- 终阶
    },
}

----------------------------------------------------------------------------
-- 英雄排序列表 (按势力分组，品质倒序)
----------------------------------------------------------------------------

--- 获取英雄有序列表
---@return {id:string, data:HeroData}[]
function M.GetSortedList()
    local list = {}
    for id, data in pairs(M.HEROES) do
        list[#list + 1] = { id = id, data = data }
    end
    -- 排序: 品质倒序 > 势力 > 名字
    local factionOrder = { wei = 1, shu = 2, wu = 3, qun = 4 }
    table.sort(list, function(a, b)
        if a.data.quality ~= b.data.quality then
            return a.data.quality > b.data.quality
        end
        local fa = factionOrder[a.data.faction] or 99
        local fb = factionOrder[b.data.faction] or 99
        if fa ~= fb then return fa < fb end
        return a.id < b.id
    end)
    return list
end

--- 按势力筛选
---@param faction string
---@return {id:string, data:HeroData}[]
function M.GetByFaction(faction)
    local list = {}
    for id, data in pairs(M.HEROES) do
        if data.faction == faction then
            list[#list + 1] = { id = id, data = data }
        end
    end
    table.sort(list, function(a, b)
        if a.data.quality ~= b.data.quality then
            return a.data.quality > b.data.quality
        end
        return a.id < b.id
    end)
    return list
end

--- 按品质筛选
---@param minQuality number
---@return {id:string, data:HeroData}[]
function M.GetByQuality(minQuality)
    local list = {}
    for id, data in pairs(M.HEROES) do
        if data.quality >= minQuality then
            list[#list + 1] = { id = id, data = data }
        end
    end
    table.sort(list, function(a, b)
        if a.data.quality ~= b.data.quality then
            return a.data.quality > b.data.quality
        end
        return a.id < b.id
    end)
    return list
end

----------------------------------------------------------------------------
-- 便捷 API
----------------------------------------------------------------------------

--- 获取英雄配置
---@param heroId string
---@return HeroData|nil
function M.Get(heroId)
    return M.HEROES[heroId]
end

--- 获取英雄名
---@param heroId string
---@return string
function M.GetName(heroId)
    local h = M.HEROES[heroId]
    return h and h.name or heroId
end

--- 获取英雄品质
---@param heroId string
---@return number
function M.GetQuality(heroId)
    local h = M.HEROES[heroId]
    return h and h.quality or 1
end

--- 判断英雄是否存在
---@param heroId string
---@return boolean
function M.Exists(heroId)
    return M.HEROES[heroId] ~= nil
end

--- 获取全部英雄 {id, data} 列表
---@return {id:string, data:HeroData}[]
function M.GetAll()
    local list = {}
    for id, data in pairs(M.HEROES) do
        list[#list + 1] = { id = id, data = data }
    end
    return list
end

--- 获取全部英雄ID列表
---@return string[]
function M.GetAllIds()
    local ids = {}
    for id in pairs(M.HEROES) do
        ids[#ids + 1] = id
    end
    return ids
end

--- 按品质范围获取英雄列表（用于招募卡池）
---@param minQ number 最低品质
---@param maxQ number 最高品质
---@return {id:string, data:HeroData}[]
function M.GetByQualityRange(minQ, maxQ)
    local list = {}
    for id, data in pairs(M.HEROES) do
        if data.quality >= minQ and data.quality <= maxQ then
            -- 排除进阶形态（魔吕布/神吕布等），它们不可直接招募
            if id ~= "molvbu" and id ~= "shenlvbu" then
                list[#list + 1] = { id = id, data = data }
            end
        end
    end
    return list
end

--- 计算英雄总数
---@return number
function M.GetCount()
    local n = 0
    for _ in pairs(M.HEROES) do n = n + 1 end
    return n
end

return M
