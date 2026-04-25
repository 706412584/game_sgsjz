------------------------------------------------------------
-- ui/popup_hero_detail.lua  —— 武将详情弹窗（通用）
-- 参考风云天下风格：头像+基础信息/兵种/战法/三围/列传
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
-- 辅助：属性行（标签 + 数值）
------------------------------------------------------------
local function attrRow(label, value, color)
    return UI.Panel {
        flexDirection = "row",
        alignItems    = "center",
        justifyContent = "space-between",
        width         = "100%",
        paddingHorizontal = 4,
        height        = 22,
        children = {
            UI.Label {
                text      = label,
                fontSize  = Theme.fontSize.bodySmall,
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
-- 辅助：分隔标题
------------------------------------------------------------
local function sectionTitle(text)
    return UI.Panel {
        width     = "100%",
        marginTop = 8,
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
                    -- 大头像
                    Comp.HeroAvatar({
                        heroId  = heroId,
                        size    = S.heroAvatarLg,
                        quality = db.quality,
                    }),
                    -- 右侧信息列
                    UI.Panel {
                        flexGrow      = 1,
                        flexShrink    = 1,
                        flexDirection = "column",
                        gap           = 3,
                        children = {
                            -- 名字 + 品质标签
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
                            -- 阵营 + 定位
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
                            -- 等级/星级/战力（已拥有时）
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
            -- 2. 兵种信息
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
            -- 3. 战法 + 被动
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
                -- 兵种将没有战法
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

            -- 被动技能
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
            -- 4. 三围属性
            --------------------------------------------------------
            children[#children + 1] = sectionTitle("属性")
            children[#children + 1] = UI.Panel {
                width           = "100%",
                backgroundColor = C.panel,
                borderRadius    = 6,
                padding         = 8,
                gap             = 2,
                children = {
                    attrRow("统率（普攻伤害）", db.stats.tong .. " / " .. db.caps.tong, C.faction_wei),
                    attrRow("勇武（战法伤害）", db.stats.yong .. " / " .. db.caps.yong, C.red),
                    attrRow("智力（法攻伤害）", db.stats.zhi  .. " / " .. db.caps.zhi,  C.mp),
                },
            }

            --------------------------------------------------------
            -- 5. 进阶信息
            --------------------------------------------------------
            if db.evolve then
                children[#children + 1] = UI.Panel {
                    flexDirection = "row",
                    alignItems    = "center",
                    gap           = 6,
                    marginTop     = 6,
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
            -- 组合返回
            --------------------------------------------------------
            return UI.ScrollView {
                width     = "100%",
                maxHeight = 400,
                scrollY   = true,
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
