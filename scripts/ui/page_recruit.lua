------------------------------------------------------------
-- ui/page_recruit.lua  —— 三国神将录 招募页面
-- 展示卡池概率、单抽/十连、保底计数、结果展示
-- 500行以内
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local DH    = require("data.data_heroes")
local State = require("data.data_state")
local Modal = require("ui.modal_manager")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------
local callbacks_     = {}
local recruitPanel_  = nil
local zhaomuLabel_   = nil
local pity4Label_    = nil
local pity5Label_    = nil
local totalLabel_    = nil
local resultArea_    = nil

------------------------------------------------------------
-- 品质色辅助 (data_heroes quality → theme quality+1)
------------------------------------------------------------
local function qColor(q)
    return Theme.QualityColor((q or 3) + 1)
end

local function qName(q)
    return DH.QUALITY_NAMES[q] or "?"
end

------------------------------------------------------------
-- 卡池概率展示
------------------------------------------------------------
local function createRatesPanel()
    local cfg = State.RECRUIT_CONFIG
    local rows = {}
    for _, r in ipairs(cfg.rates) do
        local color = qColor(r.quality)
        rows[#rows + 1] = UI.Panel {
            flexDirection = "row",
            alignItems    = "center",
            gap           = 6,
            children = {
                UI.Panel {
                    width = 10, height = 10,
                    borderRadius = 5,
                    backgroundColor = color,
                },
                UI.Label {
                    text      = qName(r.quality) .. "将",
                    fontSize  = Theme.fontSize.bodySmall,
                    fontColor = color,
                    fontWeight = "bold",
                    width     = 36,
                },
                -- 概率条
                UI.Panel {
                    flexGrow = 1, height = 12,
                    backgroundColor = { C.panel[1], C.panel[2], C.panel[3], 180 },
                    borderRadius = 6,
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width  = tostring(r.rate) .. "%",
                            height = "100%",
                            backgroundColor = color,
                            borderRadius = 6,
                        },
                    },
                },
                UI.Label {
                    text      = r.rate .. "%",
                    fontSize  = Theme.fontSize.caption,
                    fontColor = C.textDim,
                    width     = 32,
                    textAlign = "right",
                },
            },
        }
    end

    return Comp.SanCard {
        title    = "卡池概率",
        padding  = 10,
        children = rows,
    }
end

------------------------------------------------------------
-- 保底 & 统计信息
------------------------------------------------------------
local function createStatsPanel(gameState)
    local stats = State.GetRecruitStats(gameState)

    totalLabel_ = UI.Label {
        text      = "累计招募: " .. stats.total .. " 次",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.textDim,
    }
    pity4Label_ = UI.Label {
        text      = "距橙将保底: " .. math.max(0, stats.nextPity4) .. " 抽",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = qColor(4),
    }
    pity5Label_ = UI.Label {
        text      = "距红将保底: " .. math.max(0, stats.nextPity5) .. " 抽",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = qColor(5),
    }

    return Comp.SanCard {
        title    = "保底进度",
        padding  = 10,
        children = {
            totalLabel_,
            pity4Label_,
            pity5Label_,
        },
    }
end

------------------------------------------------------------
-- 刷新统计标签
------------------------------------------------------------
local function refreshStats(gameState)
    local stats = State.GetRecruitStats(gameState)
    if totalLabel_ then
        totalLabel_.text = "累计招募: " .. stats.total .. " 次"
    end
    if pity4Label_ then
        pity4Label_.text = "距橙将保底: " .. math.max(0, stats.nextPity4) .. " 抽"
    end
    if pity5Label_ then
        pity5Label_.text = "距红将保底: " .. math.max(0, stats.nextPity5) .. " 抽"
    end
    if zhaomuLabel_ then
        zhaomuLabel_.text = "招募令: " .. (gameState.zhaomuling or 0)
    end
end

------------------------------------------------------------
-- 单条结果卡片
------------------------------------------------------------
local function createResultCard(info)
    local color = qColor(info.quality)
    local isHero = (info.type == "hero")
    local desc = isHero
        and (info.heroName .. " (整将)")
        or  (info.heroName .. " x" .. info.count)
    local heroId = info.heroId

    return UI.Panel {
        width  = 80,
        alignItems = "center",
        gap    = 3,
        children = {
            -- 头像
            Comp.HeroAvatar {
                heroId  = heroId,
                size    = 56,
                quality = (info.quality or 3) + 1,
            },
            -- 名字
            UI.Label {
                text      = info.heroName or "",
                fontSize  = 10,
                fontColor = color,
                fontWeight = isHero and "bold" or "normal",
                textAlign = "center",
            },
            -- 类型
            UI.Label {
                text      = isHero and "整将" or ("碎片x" .. info.count),
                fontSize  = 9,
                fontColor = isHero and C.gold or C.textDim,
                textAlign = "center",
            },
        },
    }
end

------------------------------------------------------------
-- 显示招募结果 (单抽)
------------------------------------------------------------
local function showSingleResult(info)
    if not resultArea_ then return end
    resultArea_:ClearChildren()

    resultArea_:AddChild(UI.Panel {
        width          = "100%",
        alignItems     = "center",
        justifyContent = "center",
        paddingVertical = 10,
        gap            = 8,
        children = {
            UI.Label {
                text      = "招募结果",
                fontSize  = Theme.fontSize.subtitle,
                fontColor = C.gold,
                fontWeight = "bold",
            },
            createResultCard(info),
        },
    })
end

------------------------------------------------------------
-- 显示十连结果
------------------------------------------------------------
local function showTenResults(results)
    if not resultArea_ then return end
    resultArea_:ClearChildren()

    -- 结果卡片网格 (2行5列)
    local row1Children = {}
    local row2Children = {}
    for i, r in ipairs(results) do
        local card = createResultCard(r)
        if i <= 5 then
            row1Children[#row1Children + 1] = card
        else
            row2Children[#row2Children + 1] = card
        end
    end

    resultArea_:AddChild(UI.Panel {
        width          = "100%",
        alignItems     = "center",
        gap            = 8,
        paddingVertical = 8,
        children = {
            UI.Label {
                text      = "十连招募结果",
                fontSize  = Theme.fontSize.subtitle,
                fontColor = C.gold,
                fontWeight = "bold",
            },
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "center",
                flexWrap       = "wrap",
                gap            = 4,
                children       = row1Children,
            },
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "center",
                flexWrap       = "wrap",
                gap            = 4,
                children       = row2Children,
            },
        },
    })
end

------------------------------------------------------------
-- 操作按钮区
------------------------------------------------------------
local function createActionBar(gameState)
    zhaomuLabel_ = UI.Label {
        text      = "招募令: " .. (gameState.zhaomuling or 0),
        fontSize  = Theme.fontSize.body,
        fontColor = C.text,
        fontWeight = "bold",
    }

    return UI.Panel {
        width          = "100%",
        flexDirection  = "row",
        alignItems     = "center",
        justifyContent = "spaceBetween",
        paddingHorizontal = 12,
        paddingVertical   = 8,
        backgroundColor = { C.panel[1], C.panel[2], C.panel[3], 200 },
        borderRadius    = 8,
        borderColor     = C.border,
        borderWidth     = 1,
        children = {
            -- 左侧：招募令数量 + 图标
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 6,
                children = {
                    UI.Panel {
                        width  = 24, height = 24,
                        backgroundImage = "Textures/icons/icon_zhaomuling.png",
                        backgroundFit   = "contain",
                    },
                    zhaomuLabel_,
                },
            },
            -- 右侧：单抽 + 十连
            UI.Panel {
                flexDirection = "row",
                gap           = 8,
                children = {
                    Comp.SanButton {
                        text    = "单抽 x1",
                        variant = "primary",
                        width   = 90,
                        height  = 36,
                        fontSize = 13,
                        onClick = function()
                            if callbacks_.onRecruit then
                                callbacks_.onRecruit("single")
                            end
                        end,
                    },
                    Comp.SanButton {
                        text    = "十连 x10",
                        variant = "gold",
                        width   = 100,
                        height  = 36,
                        fontSize = 13,
                        onClick = function()
                            if callbacks_.onRecruit then
                                callbacks_.onRecruit("ten")
                            end
                        end,
                    },
                },
            },
        },
    }
end

------------------------------------------------------------
-- 主入口
------------------------------------------------------------

--- 创建招募页面
---@param gameState table
---@param opts table { onRecruit: fun(type: "single"|"ten") }
function M.Create(gameState, opts)
    opts = opts or {}
    callbacks_ = opts

    -- 结果展示区
    resultArea_ = UI.Panel {
        width     = "100%",
        flexGrow  = 1,
        flexShrink = 1,
        flexBasis = 0,
        overflow  = "scroll",
    }

    -- 初始欢迎内容
    resultArea_:AddChild(UI.Panel {
        width          = "100%",
        height         = "100%",
        alignItems     = "center",
        justifyContent = "center",
        gap            = 8,
        children = {
            UI.Label {
                text      = "招募亭",
                fontSize  = Theme.fontSize.display,
                fontColor = C.gold,
                fontWeight = "bold",
            },
            UI.Label {
                text      = "消耗招募令召唤武将或获得碎片",
                fontSize  = Theme.fontSize.body,
                fontColor = C.textDim,
            },
            UI.Label {
                text      = "10抽保底橙将  50抽保底红将",
                fontSize  = Theme.fontSize.bodySmall,
                fontColor = qColor(4),
            },
        },
    })

    -- 左侧：概率 + 保底
    local leftPanel = UI.Panel {
        width         = 180,
        flexDirection = "column",
        gap           = 8,
        flexShrink    = 0,
        children = {
            createRatesPanel(),
            createStatsPanel(gameState),
        },
    }

    -- 主布局: 左信息 + 右结果
    recruitPanel_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexDirection = "column",
        gap           = 6,
        padding       = 8,
        overflow      = "hidden",
        children = {
            -- 上方内容区 (左右分栏)
            UI.Panel {
                width         = "100%",
                flexGrow      = 1,
                flexShrink    = 1,
                flexBasis     = 0,
                flexDirection = "row",
                gap           = 8,
                overflow      = "hidden",
                children = {
                    leftPanel,
                    resultArea_,
                },
            },
            -- 下方操作栏
            createActionBar(gameState),
        },
    }

    return recruitPanel_
end

--- 刷新页面 (状态同步后调用)
---@param gameState table
function M.Refresh(gameState)
    refreshStats(gameState)
end

--- 显示单抽结果
---@param info table { type, name, count, quality }
function M.ShowSingleResult(info)
    showSingleResult(info)
end

--- 显示十连结果
---@param results table[] 每次抽取结果
function M.ShowTenResults(results)
    showTenResults(results)
end

return M
