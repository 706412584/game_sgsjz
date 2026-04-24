-- ============================================================================
-- 《问道长生》VIP页面
-- VIP等级展示 + 特权列表 + 每日灵石领取 + 等级进度
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameVip    = require("game_vip")
local DataMon    = require("data_monetization")

local M = {}

-- ============================================================================
-- VIP等级列表中的单行
-- ============================================================================

---@param vipCfg table VIP_LEVELS 中的一行
---@param currentLevel number 当前VIP等级
---@return table UI element
local function BuildVipRow(vipCfg, currentLevel)
    local isCurrent = (vipCfg.level == currentLevel)
    local isUnlocked = (vipCfg.level <= currentLevel)

    -- 特权文本（去掉"VIPx特权"继承描述）
    local privTexts = {}
    for _, priv in ipairs(vipCfg.privileges) do
        if not priv:match("^VIP%d+特权$") then
            privTexts[#privTexts + 1] = priv
        end
    end

    local privStr = #privTexts > 0 and table.concat(privTexts, ", ") or "-"
    local dailyStr = vipCfg.dailyLingshi > 0 and ("灵石x" .. vipCfg.dailyLingshi .. "/日") or "-"

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = isCurrent and { 60, 50, 30, 180 } or Theme.colors.bgDark,
        borderRadius = Theme.radius.sm,
        borderColor = isCurrent and Theme.colors.gold or Theme.colors.transparent,
        borderWidth = isCurrent and 1 or 0,
        padding = Theme.spacing.sm,
        gap = 6,
        alignItems = "center",
        children = {
            -- 等级标记
            UI.Panel {
                width = 48,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "VIP" .. vipCfg.level,
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = isUnlocked and Theme.colors.gold or Theme.colors.textSecondary,
                    },
                },
            },
            -- 充值要求
            UI.Panel {
                width = 60,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = vipCfg.charge .. "元",
                        fontSize = Theme.fontSize.small,
                        fontColor = isUnlocked and Theme.colors.textLight or Theme.colors.textSecondary,
                    },
                },
            },
            -- 每日灵石
            UI.Panel {
                width = 80,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = dailyStr,
                        fontSize = Theme.fontSize.small,
                        fontColor = isUnlocked and Theme.colors.success or Theme.colors.textSecondary,
                    },
                },
            },
            -- 特权
            UI.Panel {
                flex = 1,
                flexShrink = 1,
                children = {
                    UI.Label {
                        text = privStr,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = isUnlocked and Theme.colors.textLight or { 100, 90, 75, 150 },
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

    local status = GameVip.GetStatus()

    -- 进度条：当前充值 / 下一等级充值
    local progressChildren = {}
    if not status.isMaxLevel then
        local nextCharge = status.nextCharge or 0
        local ratio = 0
        if nextCharge > 0 then
            ratio = math.min(1, status.totalCharged / nextCharge)
        end
        local pctWidth = math.floor(ratio * 100)

        progressChildren = {
            UI.Label {
                text = "距VIP" .. (status.level + 1) .. " 还需充值 " .. status.chargeGap .. "元",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            -- 进度条背景
            UI.Panel {
                width = "100%",
                height = 12,
                borderRadius = 6,
                backgroundColor = { 50, 45, 35, 200 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = pctWidth .. "%",
                        height = "100%",
                        borderRadius = 6,
                        backgroundColor = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = status.totalCharged .. " / " .. nextCharge .. " 元",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
                textAlign = "right",
            },
        }
    else
        progressChildren = {
            UI.Label {
                text = "已达最高VIP等级",
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                fontColor = Theme.colors.gold,
                width = "100%",
            },
        }
    end

    -- 每日灵石领取区域
    local dailyClaimChildren = {}
    if status.dailyLingshi > 0 then
        local canClaim = status.canClaim
        dailyClaimChildren = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                justifyContent = "space-between",
                children = {
                    UI.Panel {
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "每日灵石",
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textLight,
                            },
                            UI.Label {
                                text = "灵石 x" .. status.dailyLingshi,
                                fontSize = Theme.fontSize.small,
                                fontColor = Theme.colors.gold,
                            },
                        },
                    },
                    UI.Panel {
                        minWidth = 90,
                        height = 36,
                        borderRadius = Theme.radius.md,
                        backgroundColor = canClaim and { 80, 140, 60, 230 } or { 60, 55, 45, 180 },
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = canClaim and "pointer" or "default",
                        onClick = function(self)
                            if not canClaim then return end
                            GameVip.ClaimDaily(function(ok)
                                if ok then Router.RebuildUI() end
                            end)
                        end,
                        children = {
                            UI.Label {
                                text = canClaim and "领取" or "已领取",
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = canClaim and { 255, 255, 255, 255 } or { 120, 110, 100, 180 },
                            },
                        },
                    },
                },
            },
        }
    else
        dailyClaimChildren = {
            UI.Label {
                text = "VIP2及以上可每日领取灵石",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }
    end

    -- 已解锁特权列表
    local privChildren = {}
    if #status.privileges > 0 then
        for _, priv in ipairs(status.privileges) do
            privChildren[#privChildren + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 6,
                alignItems = "center",
                children = {
                    UI.Panel {
                        width = 6, height = 6,
                        borderRadius = 3,
                        backgroundColor = Theme.colors.success,
                    },
                    UI.Label {
                        text = priv,
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textLight,
                    },
                },
            }
        end
    else
        privChildren[#privChildren + 1] = UI.Label {
            text = "充值即可解锁VIP特权",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
        }
    end

    -- VIP等级表
    local vipRows = {}
    for _, v in ipairs(DataMon.VIP_LEVELS) do
        if v.level > 0 then
            vipRows[#vipRows + 1] = BuildVipRow(v, status.level)
        end
    end

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        Comp.BuildSectionTitle("VIP特权"),

        -- 当前VIP信息卡
        Comp.BuildCardPanel("VIP " .. status.level, {
            -- 等级和充值信息
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
                                text = "VIP " .. status.level,
                                fontSize = Theme.fontSize.title,
                                fontWeight = "bold",
                                fontColor = Theme.colors.gold,
                            },
                            UI.Label {
                                text = "当前等级",
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
                                text = status.totalCharged .. "元",
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textLight,
                            },
                            UI.Label {
                                text = "累计充值",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                },
            },
            -- 进度条
            UI.Panel {
                width = "100%",
                gap = 4,
                marginTop = 6,
                children = progressChildren,
            },
        }),

        -- 每日灵石领取
        Comp.BuildCardPanel("每日灵石", dailyClaimChildren),

        -- 已解锁特权
        Comp.BuildCardPanel("已解锁特权", {
            UI.Panel {
                width = "100%",
                gap = 6,
                children = privChildren,
            },
        }),

        -- VIP等级表
        Comp.BuildCardPanel("VIP等级一览", {
            -- 表头
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                paddingBottom = 4,
                borderBottomWidth = 1,
                borderColor = Theme.colors.divider,
                children = {
                    UI.Panel { width = 48, alignItems = "center", children = {
                        UI.Label { text = "等级", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    }},
                    UI.Panel { width = 60, alignItems = "center", children = {
                        UI.Label { text = "充值", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    }},
                    UI.Panel { width = 80, alignItems = "center", children = {
                        UI.Label { text = "每日灵石", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    }},
                    UI.Panel { flex = 1, children = {
                        UI.Label { text = "新增特权", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    }},
                },
            },
            -- 等级行
            UI.Panel {
                width = "100%",
                gap = 4,
                children = vipRows,
            },
        }),

        -- 说明
        Comp.BuildCardPanel("VIP说明", {
            UI.Label {
                text = "VIP等级由累计充值金额自动提升，无需手动操作。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "VIP2及以上每日可领取灵石，等级越高奖励越丰厚。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "前往充值页面充值即可提升VIP等级。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
