-- ============================================================================
-- 《问道长生》充值页面
-- 7个档位 + 首充双倍标记 + 仙缘赠送
-- ============================================================================

local UI           = require("urhox-libs/UI")
local Theme        = require("ui_theme")
local Comp         = require("ui_components")
local Router       = require("ui_router")
local GamePlayer   = require("game_player")
local GameRecharge = require("game_recharge")
local DataMon      = require("data_monetization")

local M = {}

-- ============================================================================
-- 单个充值档位卡片
-- ============================================================================

---@param tierInfo table { config, hasFirstDouble, actualStones }
---@return table UI element
local function BuildTierCard(tierInfo)
    local cfg = tierInfo.config
    local hasFirst = tierInfo.hasFirstDouble
    local actual = tierInfo.actualStones

    -- 标签行
    local tagChildren = {}
    if hasFirst then
        tagChildren[#tagChildren + 1] = UI.Panel {
            paddingHorizontal = 6,
            paddingVertical = 2,
            borderRadius = 4,
            backgroundColor = { 180, 50, 30, 220 },
            children = {
                UI.Label {
                    text = "首充双倍",
                    fontSize = 9,
                    fontWeight = "bold",
                    fontColor = { 255, 220, 150, 255 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = hasFirst and Theme.colors.gold or Theme.colors.border,
        borderWidth = 1,
        padding = Theme.spacing.md,
        gap = 8,
        alignItems = "center",
        children = {
            -- 左侧：档位信息
            UI.Panel {
                flex = 1,
                gap = 4,
                children = {
                    -- 档位名称 + 标签
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = cfg.label,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            table.unpack(tagChildren),
                        },
                    },
                    -- 仙石数量
                    UI.Label {
                        text = "仙石 x" .. actual .. (hasFirst and " (含双倍)" or ""),
                        fontSize = Theme.fontSize.small,
                        fontColor = hasFirst and Theme.colors.gold or Theme.colors.textLight,
                    },
                    -- 仙缘赠送
                    cfg.bonusXY > 0 and UI.Label {
                        text = "赠仙缘 x" .. cfg.bonusXY,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textSecondary,
                    } or nil,
                },
            },
            -- 右侧：价格按钮
            UI.Panel {
                minWidth = 70,
                height = 36,
                borderRadius = Theme.radius.md,
                backgroundColor = { 140, 90, 20, 230 },
                justifyContent = "center",
                alignItems = "center",
                cursor = "pointer",
                onClick = function(self)
                    GameRecharge.Recharge(cfg.id, function(ok)
                        if ok then Router.RebuildUI() end
                    end)
                end,
                children = {
                    UI.Label {
                        text = cfg.price .. "元",
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = { 255, 230, 180, 255 },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local tiers = GameRecharge.GetTiers()
    local totalCharged = GameRecharge.GetTotalCharged()
    local vipLevel = DataMon.CalcVipLevel(totalCharged)

    -- 充值档位列表
    local tierCards = {}
    for _, t in ipairs(tiers) do
        tierCards[#tierCards + 1] = BuildTierCard(t)
    end

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        Comp.BuildSectionTitle("仙石充值"),

        -- 累计充值信息
        Comp.BuildCardPanel("充值信息", {
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
                                text = totalCharged .. "元",
                                fontSize = Theme.fontSize.title,
                                fontWeight = "bold",
                                fontColor = Theme.colors.gold,
                            },
                            UI.Label {
                                text = "累计充值",
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
                                text = "VIP " .. vipLevel,
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Label {
                                text = "当前等级",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                },
            },
        }),

        -- 档位列表
        Comp.BuildCardPanel("选择充值档位", tierCards),

        -- 说明
        Comp.BuildCardPanel("充值说明", {
            UI.Label {
                text = "每个档位首次充值可获得双倍仙石。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "充值同时赠送仙缘（绑定货币），可用于特殊消费。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "累计充值自动提升VIP等级，享受更多特权。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
