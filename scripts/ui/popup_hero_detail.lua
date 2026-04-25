------------------------------------------------------------
-- ui/popup_hero_detail.lua  —— 武将详情弹窗（通用）
-- 风云天下风格：头像+属性(含衍生战斗属性)+兵种+战法+列传
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local Modal = require("ui.modal_manager")
local DH    = require("data.data_heroes")
local DT    = require("data.data_troops")
local DS    = require("data.data_state")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 阵营颜色映射
------------------------------------------------------------
local FACTION_COLORS = {
    wei = C.faction_wei,
    shu = C.faction_shu,
    wu  = C.faction_wu,
    qun = C.faction_qun,
}

------------------------------------------------------------
-- 凹陷徽章（风云天下风格：深色底+内阴影边框）
------------------------------------------------------------
local BADGE_BG    = { 22, 28, 42, 255 }   -- 极深底色
local BADGE_BORDER = { 14, 18, 30, 255 }   -- 更深边框模拟内凹

local function statBadge(label, value, color)
    return UI.Panel {
        width           = "48%",
        flexDirection   = "row",
        justifyContent  = "space-between",
        alignItems      = "center",
        backgroundColor = BADGE_BG,
        borderColor     = BADGE_BORDER,
        borderWidth     = 1,
        borderRadius    = 4,
        paddingHorizontal = 6,
        paddingVertical   = 3,
        marginBottom    = 3,
        children = {
            UI.Label {
                text      = label,
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
            },
            UI.Label {
                text       = tostring(value),
                fontSize   = Theme.fontSize.bodySmall,
                fontColor  = color or C.text,
                fontWeight = "bold",
            },
        },
    }
end

------------------------------------------------------------
-- 三围行（宽版，带 base/cap 显示）
------------------------------------------------------------
local function triStatRow(label, base, cap, color)
    return UI.Panel {
        width           = "100%",
        flexDirection   = "row",
        justifyContent  = "space-between",
        alignItems      = "center",
        backgroundColor = BADGE_BG,
        borderColor     = BADGE_BORDER,
        borderWidth     = 1,
        borderRadius    = 4,
        paddingHorizontal = 6,
        paddingVertical   = 3,
        marginBottom    = 3,
        children = {
            UI.Label {
                text      = label,
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
            },
            UI.Label {
                text       = tostring(base) .. " / " .. tostring(cap),
                fontSize   = Theme.fontSize.bodySmall,
                fontColor  = color or C.text,
                fontWeight = "bold",
            },
        },
    }
end

------------------------------------------------------------
-- 辅助：分隔标题
------------------------------------------------------------
local function sectionTitle(text)
    return UI.Panel {
        width        = "100%",
        marginTop    = 8,
        marginBottom = 4,
        children = {
            UI.Label {
                text       = text,
                fontSize   = Theme.fontSize.subtitle,
                fontColor  = C.gold,
                fontWeight = "bold",
            },
            UI.Divider {
                color   = C.divider,
                spacing = 4,
            },
        },
    }
end

------------------------------------------------------------
-- 格式化百分比
------------------------------------------------------------
local function fmtPct(v)
    return string.format("%.1f%%", (v or 0) * 100)
end

------------------------------------------------------------
-- 公开 API：显示武将详情弹窗
------------------------------------------------------------

--- 显示武将详情弹窗
---@param heroId string
---@param heroState table|nil  玩家当前该英雄的状态（nil=未拥有）
---@param fullState table|nil  完整玩家状态（用于计算战力等）
function M.Show(heroId, heroState, fullState)
    local db = DH.Get(heroId)
    if not db then return end

    local owned   = heroState ~= nil and (heroState.level or 0) > 0
    local level   = heroState and heroState.level or 0
    local star    = heroState and heroState.star or 0
    local qColor  = Theme.HeroQualityColor(db.quality)
    local fColor  = FACTION_COLORS[db.faction] or C.textDim
    local fName   = DH.FACTION_NAMES[db.faction] or "?"
    local qName   = DH.QUALITY_NAMES[db.quality] or "?"

    -- 战力
    local heroPower = 0
    if owned then
        heroPower = DS.CalcHeroPower(heroId, heroState)
    end

    -- 衍生战斗属性
    local derived = nil
    if owned then
        derived = DS.CalcDerivedStats(heroId, heroState)
    end

    Modal.Show({
        title = db.name .. " - 武将详情",
        width = 420,
        closeOnOverlay = true,
        content = function()
            local children = {}

            --------------------------------------------------------
            -- 1. 头像 + 基础信息
            --------------------------------------------------------
            children[#children + 1] = UI.Panel {
                flexDirection = "row",
                gap           = 12,
                width         = "100%",
                alignItems    = "center",
                children = {
                    Comp.HeroAvatar({
                        heroId  = heroId,
                        size    = S.heroAvatarLg,
                        quality = db.quality,
                    }),
                    UI.Panel {
                        flexGrow      = 1,
                        flexShrink    = 1,
                        flexDirection = "column",
                        gap           = 3,
                        children = {
                            UI.Panel {
                                flexDirection = "row",
                                alignItems    = "center",
                                gap           = 6,
                                children = {
                                    UI.Label {
                                        text       = db.name,
                                        fontSize   = Theme.fontSize.headline,
                                        fontColor  = qColor,
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text      = qName .. "品",
                                        fontSize  = Theme.fontSize.caption,
                                        fontColor = qColor,
                                        backgroundColor = { qColor[1], qColor[2], qColor[3], 40 },
                                        borderRadius = 4,
                                        paddingHorizontal = 4,
                                        paddingVertical = 1,
                                    },
                                },
                            },
                            UI.Panel {
                                flexDirection = "row",
                                gap           = 8,
                                children = {
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
                            owned and UI.Panel {
                                flexDirection = "row",
                                gap           = 10,
                                alignItems    = "center",
                                children = {
                                    UI.Label {
                                        text       = "Lv." .. level,
                                        fontSize   = Theme.fontSize.body,
                                        fontColor  = C.gold,
                                        fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text       = Theme.StarsText(star),
                                        fontSize   = Theme.fontSize.body,
                                        fontColor  = Theme.StarColor(star),
                                    },
                                    UI.Label {
                                        text       = "战力 " .. Theme.FormatNumber(heroPower),
                                        fontSize   = Theme.fontSize.bodySmall,
                                        fontColor  = C.gold,
                                    },
                                },
                            } or UI.Label {
                                text      = "未拥有",
                                fontSize  = Theme.fontSize.body,
                                fontColor = C.textDim,
                            },
                        },
                    },
                },
            }

            --------------------------------------------------------
            -- 2. 属性（三围 + 衍生战斗属性）
            --------------------------------------------------------
            children[#children + 1] = sectionTitle("属性")

            -- 2a. 基础三围（始终显示 base/cap）
            children[#children + 1] = UI.Panel {
                width           = "100%",
                backgroundColor = C.panel,
                borderRadius    = 6,
                padding         = 6,
                gap             = 0,
                children = {
                    triStatRow("统率", db.stats.tong, db.caps.tong, C.faction_wei),
                    triStatRow("勇武", db.stats.yong, db.caps.yong, C.red),
                    triStatRow("智力", db.stats.zhi,  db.caps.zhi,  C.mp),
                },
            }

            -- 2b. 衍生战斗属性（仅已拥有时显示）
            if derived then
                children[#children + 1] = UI.Panel {
                    width           = "100%",
                    backgroundColor = C.panel,
                    borderRadius    = 6,
                    padding         = 6,
                    marginTop       = 4,
                    flexDirection   = "row",
                    flexWrap        = "wrap",
                    justifyContent  = "space-between",
                    children = {
                        statBadge("普攻", derived.atkNormal, C.faction_wei),
                        statBadge("普防", math.floor(derived.defNormal * 1000), C.faction_wei),
                        statBadge("战攻", derived.atkSkill, C.red),
                        statBadge("战防", math.floor(derived.defSkill * 1000), C.red),
                        statBadge("策攻", derived.atkMagic, C.mp),
                        statBadge("策防", math.floor(derived.defMagic * 1000), C.mp),
                        statBadge("暴击", fmtPct(derived.critRate), C.gold),
                        statBadge("闪避", fmtPct(derived.dodgeRate), C.jade),
                        statBadge("反击", fmtPct(derived.counterRate), C.gold),
                        statBadge("抵挡", derived.blockImmune and "免疫" or fmtPct(derived.blockRate), C.jade),
                    },
                }
            end

            --------------------------------------------------------
            -- 3. 兵种信息
            --------------------------------------------------------
            local troopKey  = DT.GetHeroTroop(heroId)
            local troopData = troopKey and DT.Get(troopKey) or nil
            local catName   = DT.GetHeroCatName(heroId)
            local heroCat   = DT.GetHeroCategory(heroId)

            children[#children + 1] = sectionTitle("兵种")

            if troopData then
                local troopName = troopData.name or "未知"
                local descText  = troopData.battleDesc or ("兵种分类：" .. catName .. "系")

                children[#children + 1] = UI.Panel {
                    width           = "100%",
                    backgroundColor = C.panel,
                    borderRadius    = 6,
                    padding         = 8,
                    children = {
                        UI.Label {
                            text       = troopName .. "（" .. catName .. "系）",
                            fontSize   = Theme.fontSize.body,
                            fontColor  = C.jade,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text       = descText,
                            fontSize   = Theme.fontSize.bodySmall,
                            fontColor  = C.text,
                            whiteSpace = "normal",
                            width      = "100%",
                            marginTop  = 4,
                        },
                    },
                }
            end

            --------------------------------------------------------
            -- 4. 战法 + 被动
            --------------------------------------------------------
            local isSkillHero = (heroCat == "infantry" or heroCat == "cavalry" or heroCat == "archer")

            if isSkillHero and db.skill ~= "无" then
                children[#children + 1] = sectionTitle("战法")
                children[#children + 1] = UI.Panel {
                    width           = "100%",
                    backgroundColor = C.panel,
                    borderRadius    = 6,
                    padding         = 8,
                    children = {
                        UI.Label {
                            text       = db.skill,
                            fontSize   = Theme.fontSize.body,
                            fontColor  = C.gold,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text       = db.skillDesc or "",
                            fontSize   = Theme.fontSize.bodySmall,
                            fontColor  = C.text,
                            whiteSpace = "normal",
                            width      = "100%",
                            marginTop  = 4,
                        },
                    },
                }
            else
                children[#children + 1] = sectionTitle("战法")
                children[#children + 1] = UI.Panel {
                    width           = "100%",
                    backgroundColor = C.panel,
                    borderRadius    = 6,
                    padding         = 8,
                    children = {
                        UI.Label {
                            text       = "无（由专属兵种提供战场效果）",
                            fontSize   = Theme.fontSize.bodySmall,
                            fontColor  = C.textDim,
                        },
                    },
                }
            end

            if db.passive then
                children[#children + 1] = sectionTitle("被动")
                children[#children + 1] = UI.Panel {
                    width           = "100%",
                    backgroundColor = C.panel,
                    borderRadius    = 6,
                    padding         = 8,
                    children = {
                        UI.Label {
                            text       = db.passive,
                            fontSize   = Theme.fontSize.body,
                            fontColor  = C.jade,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text       = db.passiveDesc or "",
                            fontSize   = Theme.fontSize.bodySmall,
                            fontColor  = C.text,
                            whiteSpace = "normal",
                            width      = "100%",
                            marginTop  = 4,
                        },
                    },
                }
            end

            --------------------------------------------------------
            -- 5. 进阶信息
            --------------------------------------------------------
            if db.evolve then
                children[#children + 1] = UI.Panel {
                    flexDirection     = "row",
                    alignItems        = "center",
                    gap               = 6,
                    marginTop         = 6,
                    paddingHorizontal = 4,
                    children = {
                        UI.Label {
                            text      = "可进阶 ->",
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

            --------------------------------------------------------
            -- 6. 人物列传
            --------------------------------------------------------
            if db.lore and db.lore ~= "" then
                children[#children + 1] = sectionTitle("人物列传")
                children[#children + 1] = UI.Panel {
                    width           = "100%",
                    backgroundColor = C.panel,
                    borderRadius    = 6,
                    padding         = 8,
                    children = {
                        UI.Label {
                            text       = db.lore,
                            fontSize   = Theme.fontSize.bodySmall,
                            fontColor  = C.text,
                            whiteSpace = "normal",
                            width      = "100%",
                        },
                    },
                }
            end

            --------------------------------------------------------
            -- 组合返回（flexShrink 防溢出，隐藏滚动条）
            --------------------------------------------------------
            return UI.ScrollView {
                width      = "100%",
                flexGrow   = 1,
                flexShrink = 1,
                scrollY    = true,
                showScrollbar = false,
                children = {
                    UI.Panel {
                        width         = "100%",
                        flexDirection = "column",
                        gap           = 4,
                        padding       = 4,
                        children      = children,
                    },
                },
            }
        end,
        buttons = {
            { text = "关闭", variant = "secondary" },
        },
    })
end

return M
