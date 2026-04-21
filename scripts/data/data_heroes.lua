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
        stats   = { tong = 92, yong = 86, zhi = 98 },
        caps    = { tong = 220, yong = 205, zhi = 235 },
        skill   = "挟天子令",
        skillDesc = "全队增伤12%，增怒15点，持续2回合",
        evolve  = "乱世曹操",
    },
    xiaohoudun = {
        name    = "夏侯惇",
        quality = 3,  -- 紫
        faction = "wei",
        role    = "前排反击坦",
        stats   = { tong = 96, yong = 88, zhi = 56 },
        caps    = { tong = 230, yong = 210, zhi = 165 },
        skill   = "拔矢啖睛",
        skillDesc = "对单体造成200%伤害，被攻击时反击60%",
        evolve  = nil,
    },
    zhangliao = {
        name    = "张辽",
        quality = 4,  -- 橙
        faction = "wei",
        role    = "突击收割",
        stats   = { tong = 84, yong = 104, zhi = 70 },
        caps    = { tong = 210, yong = 245, zhi = 180 },
        skill   = "威震逍遥",
        skillDesc = "对纵排造成240%伤害，击杀后追击一次",
        evolve  = "破军张辽",
    },
    guojia = {
        name    = "郭嘉",
        quality = 4,  -- 橙
        faction = "wei",
        role    = "控场法师",
        stats   = { tong = 62, yong = 58, zhi = 112 },
        caps    = { tong = 170, yong = 165, zhi = 250 },
        skill   = "十胜十败",
        skillDesc = "全体敌人减怒25，降智15%持续2回合",
        evolve  = "寒星郭嘉",
    },
    simayi = {
        name    = "司马懿",
        quality = 5,  -- 红
        faction = "wei",
        role    = "持续法核",
        stats   = { tong = 68, yong = 72, zhi = 122 },
        caps    = { tong = 180, yong = 180, zhi = 270 },
        skill   = "鹰视狼顾",
        skillDesc = "对全体造成160%法伤，附灼烧3回合",
        evolve  = "冥策司马懿",
    },
    zhenji = {
        name    = "甄姬",
        quality = 3,  -- 紫
        faction = "wei",
        role    = "治疗辅助",
        stats   = { tong = 58, yong = 46, zhi = 102 },
        caps    = { tong = 160, yong = 145, zhi = 235 },
        skill   = "洛神赋",
        skillDesc = "群体治疗25%兵力，净化1个负面状态",
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
        stats   = { tong = 88, yong = 74, zhi = 94 },
        caps    = { tong = 210, yong = 190, zhi = 228 },
        skill   = "仁德载物",
        skillDesc = "治疗全体友军20%兵力，附护盾10%持续2回合",
        evolve  = "汉昭刘备",
    },
    guanyu = {
        name    = "关羽",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "普攻斩将",
        stats   = { tong = 95, yong = 110, zhi = 64 },
        caps    = { tong = 225, yong = 250, zhi = 175 },
        skill   = "青龙偃月",
        skillDesc = "对纵排造成250%伤害，半血以下目标斩杀率+20%",
        evolve  = "武圣关羽",
    },
    zhangfei = {
        name    = "张飞",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "前排爆发坦",
        stats   = { tong = 102, yong = 108, zhi = 42 },
        caps    = { tong = 240, yong = 248, zhi = 145 },
        skill   = "丈八蛇矛",
        skillDesc = "对前排造成230%伤害，35%眩晕1回合",
        evolve  = "狂战张飞",
    },
    zhaoyun = {
        name    = "赵云",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "全能突击",
        stats   = { tong = 90, yong = 103, zhi = 74 },
        caps    = { tong = 220, yong = 240, zhi = 188 },
        skill   = "七进七出",
        skillDesc = "对纵排造成245%伤害，自身获得15%护盾",
        evolve  = "神枪赵云",
    },
    zhugeliang = {
        name    = "诸葛亮",
        quality = 5,  -- 红
        faction = "shu",
        role    = "法控核心",
        stats   = { tong = 64, yong = 50, zhi = 126 },
        caps    = { tong = 170, yong = 150, zhi = 275 },
        skill   = "火烧连营",
        skillDesc = "对全体造成170%法伤，40%沉默1回合",
        evolve  = "神机诸葛",
    },
    pangtong = {
        name    = "庞统",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "爆发法师",
        stats   = { tong = 58, yong = 52, zhi = 118 },
        caps    = { tong = 155, yong = 150, zhi = 255 },
        skill   = "连环火计",
        skillDesc = "对后排造成220%法伤，附灼烧2回合",
        evolve  = "凤鸣庞统",
    },
    huangyueying = {
        name    = "黄月英",
        quality = 3,  -- 紫
        faction = "shu",
        role    = "机关辅助",
        stats   = { tong = 70, yong = 64, zhi = 102 },
        caps    = { tong = 185, yong = 170, zhi = 230 },
        skill   = "木牛流马",
        skillDesc = "全队增攻速15%，召唤机关协攻2回合",
        evolve  = nil,
    },
    machao = {
        name    = "马超",
        quality = 4,  -- 橙
        faction = "shu",
        role    = "战法单切",
        stats   = { tong = 82, yong = 112, zhi = 58 },
        caps    = { tong = 205, yong = 252, zhi = 165 },
        skill   = "西凉铁骑",
        skillDesc = "对后排单体造成310%伤害，击杀回怒30",
        evolve  = "飞骑马超",
    },
    huangzhong = {
        name    = "黄忠",
        quality = 4,  -- 橙 (从现有页面保留, 设计文档未单独列出但在章7可招募)
        faction = "shu",
        role    = "弓箭主C",
        stats   = { tong = 86, yong = 108, zhi = 62 },
        caps    = { tong = 210, yong = 245, zhi = 175 },
        skill   = "百步穿杨",
        skillDesc = "对最高血量敌人造成320%伤害，无视50%防御",
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
        stats   = { tong = 86, yong = 82, zhi = 96 },
        caps    = { tong = 208, yong = 205, zhi = 232 },
        skill   = "帝业天下",
        skillDesc = "全队命中+12%，暴击+8%，回怒15",
        evolve  = "帝略孙权",
    },
    sunce = {
        name    = "孙策",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "前排战法核",
        stats   = { tong = 92, yong = 108, zhi = 60 },
        caps    = { tong = 225, yong = 248, zhi = 172 },
        skill   = "霸王一击",
        skillDesc = "对前排造成260%伤害，吸血30%",
        evolve  = "霸王孙策",
    },
    zhouyu = {
        name    = "周瑜",
        quality = 5,  -- 红
        faction = "wu",
        role    = "灼烧法核",
        stats   = { tong = 60, yong = 58, zhi = 124 },
        caps    = { tong = 165, yong = 160, zhi = 272 },
        skill   = "赤壁烈焰",
        skillDesc = "对全体造成155%法伤，附灼烧3回合",
        evolve  = "赤天周瑜",
    },
    luxun = {
        name    = "陆逊",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "持续法师",
        stats   = { tong = 66, yong = 62, zhi = 116 },
        caps    = { tong = 175, yong = 168, zhi = 252 },
        skill   = "火烧连营",
        skillDesc = "对横排造成200%法伤，灼烧扩散至相邻目标",
        evolve  = "炎谋陆逊",
    },
    ganning = {
        name    = "甘宁",
        quality = 3,  -- 紫
        faction = "wu",
        role    = "普攻暴击",
        stats   = { tong = 76, yong = 98, zhi = 56 },
        caps    = { tong = 198, yong = 232, zhi = 160 },
        skill   = "百骑劫营",
        skillDesc = "对单体造成280%伤害，暴击率+25%",
        evolve  = nil,
    },
    taishici = {
        name    = "太史慈",
        quality = 4,  -- 橙
        faction = "wu",
        role    = "双击主C",
        stats   = { tong = 84, yong = 100, zhi = 68 },
        caps    = { tong = 205, yong = 238, zhi = 178 },
        skill   = "双目标打击",
        skillDesc = "对2个目标各造成210%伤害",
        evolve  = "裂空太史慈",
    },
    daqiao = {
        name    = "大乔",
        quality = 3,  -- 紫
        faction = "wu",
        role    = "护盾辅助",
        stats   = { tong = 62, yong = 42, zhi = 104 },
        caps    = { tong = 165, yong = 140, zhi = 236 },
        skill   = "芳泽无加",
        skillDesc = "全队护盾15%兵力，持续2回合",
        evolve  = nil,
    },
    xiaoqiao = {
        name    = "小乔",
        quality = 3,  -- 紫
        faction = "wu",
        role    = "法攻副C",
        stats   = { tong = 56, yong = 48, zhi = 108 },
        caps    = { tong = 150, yong = 145, zhi = 240 },
        skill   = "倾城之恋",
        skillDesc = "对后排造成190%法伤，30%魅惑1回合",
        evolve  = nil,
    },
    sunshangxiang = {
        name    = "孙尚香",
        quality = 3,  -- 紫 (现有页面角色, 补充三围上限)
        faction = "wu",
        role    = "弓箭输出",
        stats   = { tong = 78, yong = 94, zhi = 65 },
        caps    = { tong = 195, yong = 225, zhi = 170 },
        skill   = "烈弓连珠",
        skillDesc = "对随机3目标造成160%伤害，15%附灼烧2回合",
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
        stats   = { tong = 96, yong = 132, zhi = 48 },
        caps    = { tong = 220, yong = 260, zhi = 165 },
        skill   = "无双破军",
        skillDesc = "对纵排造成265%伤害，35%附破甲2回合",
        evolve  = "魔吕布",
    },
    diaochan = {
        name    = "貂蝉",
        quality = 4,  -- 橙
        faction = "qun",
        role    = "控制辅助",
        stats   = { tong = 62, yong = 56, zhi = 114 },
        caps    = { tong = 165, yong = 160, zhi = 248 },
        skill   = "倾国倾城",
        skillDesc = "对后排造成180%法伤，40%混乱1回合",
        evolve  = "绝代貂蝉",
    },
    huatuo = {
        name    = "华佗",
        quality = 4,  -- 橙
        faction = "qun",
        role    = "顶级治疗",
        stats   = { tong = 70, yong = 48, zhi = 118 },
        caps    = { tong = 180, yong = 145, zhi = 255 },
        skill   = "青囊术",
        skillDesc = "群疗全体30%兵力，附持续回血3回合",
        evolve  = "仙医华佗",
    },
    dongzhuo = {
        name    = "董卓",
        quality = 3,  -- 紫
        faction = "qun",
        role    = "前排肉盾",
        stats   = { tong = 110, yong = 90, zhi = 42 },
        caps    = { tong = 248, yong = 215, zhi = 145 },
        skill   = "暴虐横行",
        skillDesc = "前排高肉，每回合自回血8%",
        evolve  = nil,
    },
    yuanshao = {
        name    = "袁绍",
        quality = 3,  -- 紫
        faction = "qun",
        role    = "统帅辅助",
        stats   = { tong = 84, yong = 78, zhi = 88 },
        caps    = { tong = 210, yong = 195, zhi = 220 },
        skill   = "四世三公",
        skillDesc = "全队兵力+10%，攻击+8%持续3回合",
        evolve  = nil,
    },
    zuoci = {
        name    = "左慈",
        quality = 5,  -- 红
        faction = "qun",
        role    = "控制法核",
        stats   = { tong = 64, yong = 52, zhi = 124 },
        caps    = { tong = 172, yong = 155, zhi = 272 },
        skill   = "太虚幻术",
        skillDesc = "对全体造成150%法伤，50%控制1回合",
        evolve  = "太虚左慈",
    },
    caiwenji = {
        name    = "蔡文姬",
        quality = 3,  -- 紫 (现有页面角色, 补充三围)
        faction = "qun",
        role    = "治疗辅助",
        stats   = { tong = 52, yong = 40, zhi = 108 },
        caps    = { tong = 155, yong = 140, zhi = 240 },
        skill   = "胡笳十八拍",
        skillDesc = "恢复全体友军20%兵力，增加10%防御2回合",
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
        stats   = { tong = 108, yong = 146, zhi = 56 },
        caps    = { tong = 240, yong = 278, zhi = 178 },
        skill   = "魔神降世",
        skillDesc = "免控1回合，对纵排造成285%伤害，首次被击杀免死1次",
        evolve  = "神吕布",
    },
    shenlvbu = {
        name    = "神吕布",
        quality = 6,  -- 金
        faction = "qun",
        role    = "终局神将",
        stats   = { tong = 122, yong = 158, zhi = 68 },
        caps    = { tong = 260, yong = 300, zhi = 195 },
        skill   = "天神无双",
        skillDesc = "破盾后追击，对纵排造成320%伤害，半血以下斩杀率+30%",
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

--- 获取全部英雄ID列表
---@return string[]
function M.GetAllIds()
    local ids = {}
    for id in pairs(M.HEROES) do
        ids[#ids + 1] = id
    end
    return ids
end

--- 计算英雄总数
---@return number
function M.GetCount()
    local n = 0
    for _ in pairs(M.HEROES) do n = n + 1 end
    return n
end

return M
