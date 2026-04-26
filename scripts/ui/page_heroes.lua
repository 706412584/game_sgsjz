------------------------------------------------------------
-- ui/page_heroes.lua  —— 三国神将录 武将页
-- 接入 data_heroes 数据模块，支持势力筛选 + 32武将
-- 左侧列表 (势力tab + 列表) | 右侧详情
------------------------------------------------------------
local UI     = require("urhox-libs/UI")
local Theme  = require("ui.theme")
local Comp   = require("ui.components")
local Modal  = require("ui.modal_manager")
local DH     = require("data.data_heroes")
local DT     = require("data.data_troops")
local DS     = require("data.data_state")
local HeroPopup = require("ui.popup_hero_detail")
local C      = Theme.colors
local S      = Theme.sizes

local M = {}

-- 内部状态
local pagePanel_
local heroListContainer_
local detailPanel_
local filterTabContainer_
local selectedHeroId_
local currentFilter_    = "all"   -- "all"|"wei"|"shu"|"wu"|"qun"
local currentCatFilter_ = "all"   -- "all"|"infantry"|"cavalry"|"archer"|"magic"|"support"|"siege"
local cachedState_
local onLineupChange_

-- 势力筛选标签
local FILTER_TABS = {
    { id = "all", name = "全部" },
    { id = "wei", name = "魏"   },
    { id = "shu", name = "蜀"   },
    { id = "wu",  name = "吴"   },
    { id = "qun", name = "群"   },
}

-- 兵种分类筛选标签
local CAT_FILTER_TABS = {
    { id = "all",      name = "全部" },
    { id = "infantry", name = "步兵" },
    { id = "cavalry",  name = "骑兵" },
    { id = "archer",   name = "弓兵" },
    { id = "magic",    name = "法术" },
    { id = "support",  name = "辅助" },
}

-- 势力颜色
local FACTION_COLORS = {
    wei = C.faction_wei,
    shu = C.faction_shu,
    wu  = C.faction_wu,
    qun = C.faction_qun,
}

------------------------------------------------------------
-- 构建筛选标签行（通用）
------------------------------------------------------------
local function buildTabRow(tabs, currentId, colorFn, onSelect)
    local children = {}
    for _, tab in ipairs(tabs) do
        local isActive = (tab.id == currentId)
        local tabColor = colorFn(tab)

        children[#children + 1] = UI.Panel {
            height          = 26,
            paddingHorizontal = 8,
            justifyContent  = "center",
            alignItems      = "center",
            backgroundColor = isActive and tabColor or { 0, 0, 0, 0 },
            borderRadius    = 13,
            borderColor     = tabColor,
            borderWidth     = 1,
            transition      = "backgroundColor 0.15s easeOut",
            onClick = function()
                onSelect(tab.id)
            end,
            children = {
                UI.Label {
                    text      = tab.name,
                    fontSize  = Theme.fontSize.caption,
                    fontColor = isActive and C.bg or C.text,
                    fontWeight = isActive and "bold" or "normal",
                },
            },
        }
    end
    return children
end

local function buildFilterTabs()
    -- 势力筛选行
    local factionChildren = buildTabRow(FILTER_TABS, currentFilter_, function(tab)
        return tab.id ~= "all" and FACTION_COLORS[tab.id] or C.jade
    end, function(id)
        currentFilter_ = id
        selectedHeroId_ = nil
        M.RefreshList()
        M.RefreshDetail(nil, nil)
    end)

    -- 兵种分类筛选行
    local catChildren = buildTabRow(CAT_FILTER_TABS, currentCatFilter_, function(_)
        return C.gold
    end, function(id)
        currentCatFilter_ = id
        selectedHeroId_ = nil
        M.RefreshList()
        M.RefreshDetail(nil, nil)
    end)

    return UI.Panel {
        width             = "100%",
        flexDirection     = "column",
        paddingHorizontal = 8,
        paddingTop        = 6,
        paddingBottom     = 2,
        gap               = 4,
        children = {
            UI.Panel {
                width         = "100%",
                flexDirection = "row",
                gap           = 6,
                children      = factionChildren,
            },
            UI.Panel {
                width         = "100%",
                flexDirection = "row",
                gap           = 4,
                flexWrap      = "wrap",
                children      = catChildren,
            },
        },
    }
end

------------------------------------------------------------
-- 获取筛选后的英雄列表（势力 + 兵种分类双重筛选）
------------------------------------------------------------
local function getFilteredHeroes()
    local base
    if currentFilter_ == "all" then
        base = DH.GetSortedList()
    else
        base = DH.GetByFaction(currentFilter_)
    end

    -- 兵种分类筛选
    if currentCatFilter_ == "all" then
        return base
    end

    local result = {}
    for _, entry in ipairs(base) do
        local cat = DT.GetHeroCategory(entry.id)
        if cat == currentCatFilter_ then
            result[#result + 1] = entry
        end
    end
    return result
end

------------------------------------------------------------
-- 构建单个武将卡片（列表项）
------------------------------------------------------------
local function createHeroCard(heroId, heroState)
    local db = DH.Get(heroId)
    if not db then return nil end

    local level    = heroState and heroState.level or 1
    local qColor   = Theme.HeroQualityColor(db.quality)
    local isSelected = (heroId == selectedHeroId_)
    local owned    = heroState ~= nil

    return UI.Panel {
        width           = "100%",
        height          = 64,
        flexDirection   = "row",
        alignItems      = "center",
        gap             = 8,
        padding         = 6,
        backgroundColor = isSelected and C.panelLight or C.panel,
        borderRadius    = 6,
        borderColor     = isSelected and C.jade or C.border,
        borderWidth     = isSelected and 2 or 1,
        marginBottom    = 3,
        opacity         = owned and 1.0 or 0.5,
        transition      = "backgroundColor 0.2s easeOut",
        onClick = function()
            selectedHeroId_ = heroId
            M.RefreshDetail(heroId, heroState)
        end,
        children = {
            -- 头像
            Comp.HeroAvatar({
                heroId    = heroId,
                size      = S.heroAvatarSm,
                quality   = db.quality,
                level     = owned and level or nil,
                showLevel = owned,
            }),

            -- 信息列
            UI.Panel {
                flexGrow      = 1,
                flexShrink    = 1,
                flexDirection = "column",
                gap           = 2,
                children = {
                    -- 名字 + 定位
                    UI.Panel {
                        flexDirection = "row",
                        alignItems    = "center",
                        gap           = 4,
                        children = {
                            UI.Label {
                                text       = db.name,
                                fontSize   = Theme.fontSize.body,
                                fontColor  = qColor,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text      = db.role,
                                fontSize  = Theme.fontSize.caption,
                                fontColor = C.textDim,
                            },
                        },
                    },
                    -- 三围
                    UI.Label {
                        text      = "统" .. db.stats.tong .. " 勇" .. db.stats.yong .. " 智" .. db.stats.zhi,
                        fontSize  = Theme.fontSize.caption,
                        fontColor = C.textDim,
                    },
                },
            },

            -- 等级/未拥有
            UI.Label {
                text      = owned and ("Lv." .. level) or "未获",
                fontSize  = Theme.fontSize.bodySmall,
                fontColor = owned and C.gold or C.textDim,
            },
        },
    }
end

------------------------------------------------------------
-- 构建武将列表
------------------------------------------------------------
local function buildHeroList()
    local heroes = (cachedState_ and cachedState_.heroes) or {}
    local filtered = getFilteredHeroes()
    local children = {}

    for _, entry in ipairs(filtered) do
        local hid       = entry.id
        local heroState = heroes[hid]
        local card      = createHeroCard(hid, heroState)
        if card then
            children[#children + 1] = card
        end
    end

    if #children == 0 then
        children[#children + 1] = UI.Panel {
            width          = "100%",
            height         = 80,
            justifyContent = "center",
            alignItems     = "center",
            children = {
                UI.Label {
                    text       = "暂无武将",
                    fontSize   = Theme.fontSize.body,
                    fontColor  = C.textDim,
                    textAlign  = "center",
                },
            },
        }
    end

    -- 武将计数
    local ownedCount = 0
    for _, entry in ipairs(filtered) do
        if heroes[entry.id] then ownedCount = ownedCount + 1 end
    end

    -- 头部统计
    local countLabel = UI.Label {
        text      = "拥有 " .. ownedCount .. "/" .. #filtered,
        fontSize  = Theme.fontSize.caption,
        fontColor = C.textDim,
        textAlign = "right",
        paddingHorizontal = 8,
        paddingBottom = 4,
    }

    return UI.Panel {
        width         = "100%",
        flexDirection = "column",
        children      = { countLabel, table.unpack(children) },
    }
end

------------------------------------------------------------
-- 三围数值块
------------------------------------------------------------
local function createStatBlock(label, value, capValue, color)
    return UI.Panel {
        alignItems = "center",
        gap        = 2,
        children = {
            UI.Label {
                text      = label,
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
            },
            UI.Label {
                text       = tostring(value),
                fontSize   = Theme.fontSize.headline,
                fontColor  = color,
                fontWeight = "bold",
            },
            UI.Label {
                text      = "上限 " .. capValue,
                fontSize  = 8,
                fontColor = C.textDim,
            },
        },
    }
end

------------------------------------------------------------
-- 构建武将详情面板
------------------------------------------------------------
local function buildDetailPanel(heroId, heroState)
    local db = heroId and DH.Get(heroId) or nil
    if not db then
        return UI.Panel {
            flexGrow       = 1,
            justifyContent = "center",
            alignItems     = "center",
            children = {
                UI.Label { text = "选择武将查看详情", fontSize = Theme.fontSize.body, fontColor = C.textDim },
            },
        }
    end

    local level   = heroState and heroState.level or 1
    local owned   = heroState ~= nil
    local qColor  = Theme.HeroQualityColor(db.quality)
    local fColor  = FACTION_COLORS[db.faction] or C.textDim
    local fName   = DH.FACTION_NAMES[db.faction] or "?"
    local qName   = DH.QUALITY_NAMES[db.quality] or "?"

    local detailChildren = {
        -- 头像 + 基础信息
        UI.Panel {
            flexDirection = "row",
            gap           = 12,
            children = {
                Comp.HeroAvatar({
                    heroId  = heroId,
                    size    = S.heroAvatarLg,
                    quality = db.quality,
                }),
                UI.Panel {
                    flexDirection  = "column",
                    gap            = 3,
                    justifyContent = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems    = "center",
                            gap           = 8,
                            children = {
                                UI.Label {
                                    text       = db.name,
                                    fontSize   = Theme.fontSize.headline,
                                    fontColor  = qColor,
                                    fontWeight = "bold",
                                },
                                UI.Button {
                                    text            = "详情",
                                    width           = 44,
                                    height          = 22,
                                    fontSize        = 10,
                                    fontWeight      = "bold",
                                    textColor       = C.gold,
                                    backgroundColor = { C.gold[1], C.gold[2], C.gold[3], 30 },
                                    hoverBackgroundColor = { C.gold[1], C.gold[2], C.gold[3], 60 },
                                    borderColor     = C.gold,
                                    borderWidth     = 1,
                                    borderRadius    = 11,
                                    onClick = function()
                                        HeroPopup.Show(heroId, heroState, cachedState_)
                                    end,
                                },
                            },
                        },
                        UI.Panel {
                            flexDirection = "row",
                            gap           = 8,
                            children = {
                                UI.Label {
                                    text      = qName .. "品",
                                    fontSize  = Theme.fontSize.bodySmall,
                                    fontColor = qColor,
                                },
                                UI.Label {
                                    text      = fName,
                                    fontSize  = Theme.fontSize.bodySmall,
                                    fontColor = fColor,
                                },
                                UI.Label {
                                    text      = db.role,
                                    fontSize  = Theme.fontSize.bodySmall,
                                    fontColor = C.textDim,
                                },
                            },
                        },
                        UI.Label {
                            text      = owned and ("Lv." .. level) or "未拥有",
                            fontSize  = Theme.fontSize.subtitle,
                            fontColor = owned and C.gold or C.textDim,
                        },
                    },
                },
            },
        },

        Comp.SanDivider(),

        -- 三围详情 + 兵力
        UI.Panel {
            gap = 4,
            children = {
                UI.Panel {
                    flexDirection  = "row",
                    justifyContent = "space-around",
                    children = {
                        createStatBlock("统", db.stats.tong, db.caps.tong, C.faction_wei),
                        createStatBlock("勇", db.stats.yong, db.caps.yong, C.red),
                        createStatBlock("智", db.stats.zhi,  db.caps.zhi,  C.mp),
                    },
                },
                UI.Panel {
                    flexDirection  = "row",
                    justifyContent = "center",
                    alignItems     = "center",
                    gap            = 6,
                    marginTop      = 2,
                    children = {
                        UI.Label {
                            text      = "兵力",
                            fontSize  = Theme.fontSize.caption,
                            fontColor = C.textDim,
                        },
                        UI.Label {
                            text       = tostring(db.stats.hp or 3000),
                            fontSize   = Theme.fontSize.headline,
                            fontColor  = C.hp,
                            fontWeight = "bold",
                        },
                    },
                },
            },
        },

        Comp.SanDivider(),

    }

    -- 技能/兵种卡片（根据兵种分类区分）
    local heroCat = DT.GetHeroCategory(heroId)
    local isSkillHero = (heroCat == "infantry" or heroCat == "cavalry" or heroCat == "archer")

    if isSkillHero and db.skill ~= "无" then
        -- 战法将：显示战法卡片
        detailChildren[#detailChildren + 1] = Comp.SanCard({
            title = "战法：" .. db.skill,
            children = {
                UI.Label {
                    text       = db.skillDesc,
                    fontSize   = Theme.fontSize.body,
                    fontColor  = C.text,
                    whiteSpace = "normal",
                    width      = "100%",
                    marginTop  = 4,
                },
            },
        })
    else
        -- 兵种将：显示专属兵种卡片
        local troopKey  = DT.GetHeroTroop(heroId)
        local troopData = troopKey and DT.Get(troopKey) or nil
        local troopName = troopData and troopData.name or "未知"
        local catName   = DT.GetHeroCatName(heroId)

        -- 使用 battleDesc 详细描述
        local descText = (troopData and troopData.battleDesc) or ("兵种分类：" .. catName .. "系")

        detailChildren[#detailChildren + 1] = Comp.SanCard({
            title = "专属兵种：" .. troopName .. "（" .. catName .. "系）",
            children = {
                UI.Label {
                    text       = descText,
                    fontSize   = Theme.fontSize.body,
                    fontColor  = C.text,
                    whiteSpace = "normal",
                    width      = "100%",
                    marginTop  = 4,
                },
                UI.Label {
                    text       = "该武将不消耗士气，由专属兵种提供战场效果",
                    fontSize   = Theme.fontSize.caption,
                    fontColor  = C.textDim,
                    whiteSpace = "normal",
                    width      = "100%",
                    marginTop  = 4,
                },
            },
        })
    end

    -- 被动技能
    if db.passive then
        detailChildren[#detailChildren + 1] = Comp.SanCard({
            title = "被动：" .. db.passive,
            children = {
                UI.Label {
                    text       = db.passiveDesc or "",
                    fontSize   = Theme.fontSize.body,
                    fontColor  = C.jade,
                    whiteSpace = "normal",
                    width      = "100%",
                    marginTop  = 4,
                },
            },
        })
    end

    -- 进阶信息
    if db.evolve then
        detailChildren[#detailChildren + 1] = UI.Panel {
            flexDirection     = "row",
            alignItems        = "center",
            gap               = 6,
            paddingHorizontal = 4,
            marginTop         = 4,
            children = {
                UI.Label {
                    text      = "进阶→",
                    fontSize  = Theme.fontSize.bodySmall,
                    fontColor = C.textDim,
                },
                UI.Label {
                    text       = db.evolve,
                    fontSize   = Theme.fontSize.bodySmall,
                    fontColor  = C.gold,
                    fontWeight = "bold",
                },
            },
        }
    end

    -- 养成区域（已拥有）
    if owned and heroState.level > 0 then
        local lvInfo = DS.GetLevelInfo(cachedState_, heroId)
        local star   = heroState.star or 1
        local frags  = heroState.fragments or 0
        local starCost = DS.GetStarCost(star)
        local heroPower = DS.CalcHeroPower(heroId, heroState)
        local wineCount = (cachedState_.inventory and cachedState_.inventory.exp_wine) or 0

        -- 经验条
        local expRatio = lvInfo and (lvInfo.exp / math.max(lvInfo.expNeed, 1)) or 0
        detailChildren[#detailChildren + 1] = Comp.SanCard({
            title = "养成",
            children = {
                -- 战力
                UI.Panel {
                    flexDirection = "row",
                    alignItems    = "center",
                    gap           = 4,
                    marginBottom  = 4,
                    children = {
                        UI.Label { text = "战力", fontSize = 10, fontColor = C.textDim },
                        UI.Label { text = tostring(heroPower), fontSize = 13,
                                   fontColor = C.gold, fontWeight = "bold" },
                        UI.Label { text = "  ★" .. star, fontSize = 12,
                                   fontColor = Theme.StarColor(star), fontWeight = "bold" },
                    },
                },
                -- 经验条
                UI.Panel {
                    flexDirection = "row",
                    alignItems    = "center",
                    gap           = 6,
                    marginBottom  = 4,
                    children = {
                        UI.Label { text = "Lv." .. (lvInfo and lvInfo.level or level),
                                   fontSize = 11, fontColor = C.text, fontWeight = "bold" },
                        UI.Panel {
                            flexGrow = 1, height = 8,
                            backgroundColor = C.panel, borderRadius = 4,
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = tostring(math.floor(expRatio * 100)) .. "%",
                                    height = "100%",
                                    backgroundColor = C.jade,
                                    borderRadius = 4,
                                },
                            },
                        },
                        UI.Label {
                            text = lvInfo and (lvInfo.exp .. "/" .. lvInfo.expNeed) or "",
                            fontSize = 9, fontColor = C.textDim,
                        },
                    },
                },
                -- 升级按钮行
                UI.Panel {
                    flexDirection = "row",
                    gap           = 6,
                    marginTop     = 4,
                    children = {
                        Comp.SanButton({
                            text = "升级×1 (酒:" .. wineCount .. ")",
                            variant = "primary",
                            flexGrow = 1,
                            height = S.btnSmHeight,
                            fontSize = S.btnSmFontSize,
                            onClick = function()
                                local ok, msg = DS.UseExpWine(cachedState_, heroId, 1)
                                if ok then
                                    M.RefreshList()
                                    M.RefreshDetail(heroId, cachedState_.heroes[heroId])
                                else
                                    Modal.Alert("提示", msg)
                                end
                            end,
                        }),
                        Comp.SanButton({
                            text = "升级×10",
                            variant = "primary",
                            flexGrow = 1,
                            height = S.btnSmHeight,
                            fontSize = S.btnSmFontSize,
                            onClick = function()
                                local ok, msg = DS.UseExpWine(cachedState_, heroId, 10)
                                if ok then
                                    M.RefreshList()
                                    M.RefreshDetail(heroId, cachedState_.heroes[heroId])
                                else
                                    Modal.Alert("提示", msg)
                                end
                            end,
                        }),
                    },
                },
                -- 升星行
                UI.Panel {
                    flexDirection = "row",
                    gap           = 6,
                    alignItems    = "center",
                    marginTop     = 6,
                    children = {
                        UI.Label {
                            text = "碎片: " .. frags .. "/" .. starCost,
                            fontSize = 11, fontColor = C.textDim,
                        },
                        Comp.SanButton({
                            text = star >= DS.MAX_HERO_STAR and "已满星" or ("升星→" .. (star + 1) .. "★"),
                            variant = "gold",
                            flexGrow = 1,
                            height = S.btnSmHeight,
                            fontSize = S.btnSmFontSize,
                            onClick = function()
                                if star >= DS.MAX_HERO_STAR then
                                    Modal.Alert("提示", "已满星")
                                    return
                                end
                                local ok, msg = DS.StarUp(cachedState_, heroId)
                                Modal.Alert(ok and "升星成功" or "提示", msg)
                                if ok then
                                    M.RefreshList()
                                    M.RefreshDetail(heroId, cachedState_.heroes[heroId])
                                end
                            end,
                        }),
                    },
                },
            },
        })
    elseif heroState and heroState.level <= 0 then
        -- 未合成英雄（有碎片但 level=0）
        local frags = heroState.fragments or 0
        detailChildren[#detailChildren + 1] = Comp.SanCard({
            title = "碎片收集",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems    = "center",
                    gap           = 6,
                    children = {
                        UI.Label { text = "碎片: " .. frags .. "/30",
                                   fontSize = 12, fontColor = C.text },
                        UI.Panel {
                            flexGrow = 1, height = 8,
                            backgroundColor = C.panel, borderRadius = 4,
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = tostring(math.min(math.floor(frags / 30 * 100), 100)) .. "%",
                                    height = "100%",
                                    backgroundColor = C.jade,
                                    borderRadius = 4,
                                },
                            },
                        },
                    },
                },
                Comp.SanButton({
                    text = frags >= 30 and "合成英雄" or "碎片不足",
                    variant = frags >= 30 and "gold" or "secondary",
                    height = S.btnSmHeight,
                    fontSize = S.btnSmFontSize,
                    marginTop = 6,
                    onClick = function()
                        if frags < 30 then
                            Modal.Alert("提示", "碎片不足，需要30个碎片合成")
                            return
                        end
                        local ok, msg = DS.ComposeHero(cachedState_, heroId)
                        Modal.Alert(ok and "合成成功" or "提示", msg)
                        if ok then
                            M.RefreshList()
                            M.RefreshDetail(heroId, cachedState_.heroes[heroId])
                        end
                    end,
                }),
            },
        })
    end

    return UI.Panel {
        flexGrow      = 1,
        flexDirection = "column",
        padding       = 12,
        gap           = 6,
        children      = detailChildren,
    }
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建武将页
---@param state table 玩家状态
---@param callbacks table { onLineupChange }
function M.Create(state, callbacks)
    callbacks       = callbacks or {}
    onLineupChange_ = callbacks.onLineupChange
    cachedState_    = state
    selectedHeroId_ = nil

    -- 势力筛选标签
    filterTabContainer_ = UI.Panel {
        width         = "100%",
        flexDirection = "column",
        children      = { buildFilterTabs() },
    }

    -- 武将列表
    heroListContainer_ = UI.Panel {
        width         = "100%",
        flexDirection = "column",
        children      = { buildHeroList() },
    }

    -- 右侧详情
    detailPanel_ = UI.Panel {
        id        = "hero_detail",
        flexGrow  = 1,
        flexBasis = 0,
        children  = { buildDetailPanel(nil, nil) },
    }

    -- 主布局：左列表 + 右详情
    pagePanel_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexBasis     = 0,
        flexDirection = "row",
        children = {
            -- 左侧（筛选 + 列表）
            UI.Panel {
                width         = 250,
                flexDirection = "column",
                children = {
                    filterTabContainer_,
                    UI.ScrollView {
                        flexGrow  = 1,
                        flexBasis = 0,
                        scrollY   = true,
                        padding   = 6,
                        children  = { heroListContainer_ },
                    },
                },
            },

            -- 分割线
            UI.Panel {
                width           = 1,
                height          = "100%",
                backgroundColor = C.border,
            },

            -- 右侧详情
            UI.ScrollView {
                flexGrow  = 1,
                flexBasis = 0,
                scrollY   = true,
                children  = { detailPanel_ },
            },
        },
    }

    return pagePanel_
end

--- 刷新武将列表（筛选变化时）
function M.RefreshList()
    if not heroListContainer_ then return end
    heroListContainer_:ClearChildren()
    heroListContainer_:AddChild(buildHeroList())

    if filterTabContainer_ then
        filterTabContainer_:ClearChildren()
        filterTabContainer_:AddChild(buildFilterTabs())
    end
end

--- 刷新详情面板
function M.RefreshDetail(heroId, heroState)
    if not detailPanel_ then return end
    detailPanel_:ClearChildren()
    detailPanel_:AddChild(buildDetailPanel(heroId, heroState))
end

--- 获取页面面板
function M.GetPanel()
    return pagePanel_
end

--- 获取武将数据库（兼容旧接口）
function M.GetHeroDB()
    return DH.HEROES
end

return M
