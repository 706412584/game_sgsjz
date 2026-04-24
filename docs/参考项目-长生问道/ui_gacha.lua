-- ============================================================================
-- 《问道长生》抽奖页面
-- 概率展示 + 单抽/十连按钮 + 保底计数 + 结果展示
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameGacha  = require("game_gacha")
local DataMon    = require("data_monetization")

local M = {}

-- ============================================================================
-- 品质颜色映射
-- ============================================================================

local QUALITY_COLORS = {
    xtshenqi = { 255, 100, 50, 255 },   -- 橙红
    shenqi   = { 255, 150, 30, 255 },   -- 橙
    xtxianqi = { 200, 120, 255, 255 },  -- 紫
    xianqi   = { 160, 100, 220, 255 },  -- 浅紫
    diqi     = { 80, 160, 255, 255 },   -- 蓝
    huangqi  = { 80, 200, 120, 255 },   -- 绿
    xtlingbao = { 120, 200, 180, 255 }, -- 青
    lingbao  = { 180, 180, 180, 255 },  -- 灰白
    material = { 150, 140, 120, 255 },  -- 灰
    lingshi  = { 200, 168, 85, 255 },   -- 金
}

--- 获取品质颜色
---@param quality string
---@return table
local function GetQualityColor(quality)
    return QUALITY_COLORS[quality] or Theme.colors.textLight
end

-- ============================================================================
-- 抽奖结果展示
-- ============================================================================

---@param results table[]|nil
---@return table UI element
local function BuildResultsPanel(results)
    if not results or #results == 0 then
        return UI.Panel {
            width = "100%",
            padding = Theme.spacing.lg,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "点击下方按钮开始抽奖",
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textSecondary,
                },
            },
        }
    end

    local itemChildren = {}
    for i, r in ipairs(results) do
        itemChildren[#itemChildren + 1] = UI.Panel {
            width = 70,
            height = 80,
            borderRadius = Theme.radius.md,
            backgroundColor = { 45, 40, 32, 200 },
            borderColor = GetQualityColor(r.quality),
            borderWidth = 1,
            alignItems = "center",
            justifyContent = "center",
            gap = 4,
            children = {
                -- 品质名称
                UI.Label {
                    text = r.label or "?",
                    fontSize = Theme.fontSize.tiny,
                    fontWeight = "bold",
                    fontColor = GetQualityColor(r.quality),
                    textAlign = "center",
                },
                -- 序号
                UI.Label {
                    text = "#" .. i,
                    fontSize = 8,
                    fontColor = Theme.colors.textSecondary,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        justifyContent = "center",
        children = itemChildren,
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local status = GameGacha.GetStatus()

    -- 概率表
    local rateRows = {}
    for _, r in ipairs(DataMon.GACHA_RATES) do
        rateRows[#rateRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            paddingVertical = 2,
            children = {
                UI.Label {
                    text = r.label,
                    fontSize = Theme.fontSize.small,
                    fontColor = GetQualityColor(r.quality),
                },
                UI.Label {
                    text = string.format("%.1f%%", r.rate * 100),
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                },
            },
        }
    end

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        Comp.BuildSectionTitle("仙缘抽奖"),

        -- 保底信息
        Comp.BuildCardPanel("保底进度", {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-around",
                children = {
                    UI.Panel {
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = tostring(status.totalPulls),
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textLight,
                            },
                            UI.Label {
                                text = "累计抽奖",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                    UI.Panel {
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = tostring(status.softPityRemain),
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = { 160, 100, 220, 255 },
                            },
                            UI.Label {
                                text = "距仙器保底",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                    UI.Panel {
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = tostring(status.hardPityRemain),
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = { 255, 150, 30, 255 },
                            },
                            UI.Label {
                                text = "距神器保底",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                },
            },
        }),

        -- 抽奖结果
        Comp.BuildCardPanel("抽奖结果", {
            BuildResultsPanel(status.lastResults),
        }),

        -- 抽奖按钮
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 12,
            justifyContent = "center",
            paddingVertical = Theme.spacing.sm,
            children = {
                -- 单抽按钮
                UI.Panel {
                    flex = 1,
                    height = 44,
                    borderRadius = Theme.radius.md,
                    backgroundColor = { 100, 70, 160, 230 },
                    justifyContent = "center",
                    alignItems = "center",
                    cursor = "pointer",
                    onClick = function(self)
                        GameGacha.Pull(1, function(ok)
                            if ok then Router.RebuildUI() end
                        end)
                    end,
                    children = {
                        UI.Label {
                            text = "单抽  " .. status.singleCost .. "仙石",
                            fontSize = Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = { 255, 255, 255, 255 },
                        },
                    },
                },
                -- 十连按钮
                UI.Panel {
                    flex = 1,
                    height = 44,
                    borderRadius = Theme.radius.md,
                    backgroundColor = { 160, 100, 20, 240 },
                    justifyContent = "center",
                    alignItems = "center",
                    cursor = "pointer",
                    onClick = function(self)
                        GameGacha.Pull(10, function(ok)
                            if ok then Router.RebuildUI() end
                        end)
                    end,
                    children = {
                        UI.Label {
                            text = "十连  " .. status.tenCost .. "仙石",
                            fontSize = Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = { 255, 230, 180, 255 },
                        },
                    },
                },
            },
        },

        -- 概率表
        Comp.BuildCardPanel("概率一览", {
            UI.Panel {
                width = "100%",
                gap = 2,
                children = rateRows,
            },
        }),

        -- 规则说明
        Comp.BuildCardPanel("抽奖规则", {
            UI.Label {
                text = "每次抽奖消耗仙石，十连有九折优惠。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "50抽未出仙器以上，第50抽保底出仙器。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "100抽未出神器以上，第100抽保底出神器。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "抽到仙器及以上品质时保底计数重置。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
