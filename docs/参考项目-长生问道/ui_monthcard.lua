-- ============================================================================
-- 《问道长生》月卡页面
-- 两种月卡（道友/仙友）+ 每日领取 + 购买/续费
-- ============================================================================

local UI            = require("urhox-libs/UI")
local Theme         = require("ui_theme")
local Comp          = require("ui_components")
local Router        = require("ui_router")
local GamePlayer    = require("game_player")
local GameMonthcard = require("game_monthcard")
local DataMon       = require("data_monetization")

local M = {}

-- ============================================================================
-- 月卡卡片组件
-- ============================================================================

--- 构建单张月卡面板
---@param cardId string "basic"|"premium"
---@return table UI element
local function BuildCardPanel(cardId)
    local status = GameMonthcard.GetStatus(cardId)
    local cfg = status.config
    if not cfg then return UI.Panel {} end

    local isActive = status.active
    local isPremium = (cardId == "premium")

    -- 边框颜色：激活金色，未激活灰色；高级卡用更亮的金色
    local borderColor = isActive
        and (isPremium and { 220, 180, 60, 200 } or Theme.colors.borderGold)
        or Theme.colors.border

    -- 状态标签
    local statusText = ""
    local statusColor = Theme.colors.textSecondary
    if isActive then
        statusText = "剩余 " .. status.remainDays .. " 天"
        statusColor = Theme.colors.success
    else
        statusText = "未激活"
        statusColor = Theme.colors.textSecondary
    end

    -- 特权列表
    local privChildren = {}
    for i, priv in ipairs(cfg.privileges) do
        privChildren[#privChildren + 1] = UI.Label {
            text = "- " .. priv,
            fontSize = Theme.fontSize.small,
            fontColor = isActive and Theme.colors.textLight or Theme.colors.textSecondary,
        }
    end

    -- 每日奖励信息
    local dailyText = "每日: 仙石x" .. cfg.dailyStones
    if cfg.dailyXY > 0 then
        dailyText = dailyText .. " + 仙缘x" .. cfg.dailyXY
    end

    -- 即时奖励信息
    local instantText = "立即获得: 仙石x" .. cfg.instantStones
    if cfg.instantXY > 0 then
        instantText = instantText .. " + 仙缘x" .. cfg.instantXY
    end

    -- 按钮区域
    local buttonChildren = {}

    if isActive then
        -- 领取每日奖励按钮
        local canClaim = status.canClaim
        buttonChildren[#buttonChildren + 1] = UI.Panel {
            flex = 1,
            height = 38,
            borderRadius = Theme.radius.md,
            backgroundColor = canClaim and { 80, 140, 60, 230 } or { 60, 55, 45, 180 },
            justifyContent = "center",
            alignItems = "center",
            cursor = canClaim and "pointer" or "default",
            onClick = function(self)
                if not canClaim then return end
                GameMonthcard.ClaimDaily(cardId, function(ok)
                    if ok then Router.RebuildUI() end
                end)
            end,
            children = {
                UI.Label {
                    text = canClaim and "领取每日奖励" or "今日已领取",
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = canClaim and { 255, 255, 255, 255 } or { 120, 110, 100, 180 },
                },
            },
        }

        -- 续费按钮（剩余天数 <= 7 时显示）
        if status.remainDays <= 7 then
            buttonChildren[#buttonChildren + 1] = UI.Panel {
                flex = 1,
                height = 38,
                borderRadius = Theme.radius.md,
                backgroundColor = { 140, 90, 20, 230 },
                justifyContent = "center",
                alignItems = "center",
                cursor = "pointer",
                onClick = function(self)
                    GameMonthcard.Buy(cardId, function(ok)
                        if ok then Router.RebuildUI() end
                    end)
                end,
                children = {
                    UI.Label {
                        text = "续费 " .. cfg.price .. "元",
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = { 255, 230, 180, 255 },
                    },
                },
            }
        end
    else
        -- 购买按钮
        buttonChildren[#buttonChildren + 1] = UI.Panel {
            flex = 1,
            height = 40,
            borderRadius = Theme.radius.md,
            backgroundColor = isPremium and { 160, 100, 20, 240 } or { 140, 90, 20, 230 },
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function(self)
                GameMonthcard.Buy(cardId, function(ok)
                    if ok then Router.RebuildUI() end
                end)
            end,
            children = {
                UI.Label {
                    text = cfg.price .. "元 开通",
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    fontColor = { 255, 230, 180, 255 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.lg,
        borderColor = borderColor,
        borderWidth = isPremium and 2 or 1,
        padding = Theme.spacing.lg,
        gap = 10,
        children = {
            -- 头部：名称 + 状态
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = cfg.label,
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = isPremium and { 230, 190, 80, 255 } or Theme.colors.textGold,
                    },
                    UI.Panel {
                        paddingHorizontal = 8,
                        paddingVertical = 3,
                        borderRadius = 10,
                        backgroundColor = isActive and { 60, 120, 50, 180 } or { 60, 55, 50, 120 },
                        children = {
                            UI.Label {
                                text = statusText,
                                fontSize = Theme.fontSize.small,
                                fontWeight = "bold",
                                fontColor = statusColor,
                            },
                        },
                    },
                },
            },

            -- 分割线
            UI.Panel {
                width = "100%",
                height = 1,
                backgroundColor = Theme.colors.divider,
            },

            -- 即时奖励（购买时获得）
            UI.Label {
                text = instantText,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.gold,
            },

            -- 每日奖励
            UI.Label {
                text = dailyText,
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = Theme.colors.textLight,
            },

            -- 已领取天数
            isActive and UI.Label {
                text = "已领取 " .. status.totalClaimed .. " 天",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
            } or nil,

            -- 特权列表
            UI.Panel {
                width = "100%",
                gap = 3,
                children = {
                    UI.Label {
                        text = "专属特权:",
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textLight,
                    },
                    table.unpack(privChildren),
                },
            },

            -- 按钮区域
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 8,
                children = buttonChildren,
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

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        Comp.BuildSectionTitle("月卡特权"),

        -- 说明
        Comp.BuildCardPanel("月卡说明", {
            UI.Label {
                text = "购买月卡可立即获得大量仙石和仙缘，并在有效期内每天领取额外奖励。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "月卡到期前可续费，剩余天数将自动累加。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }),

        -- 仙友月卡（高级）放上面
        BuildCardPanel("premium"),

        -- 道友月卡（基础）
        BuildCardPanel("basic"),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
