-- ============================================================================
-- 《问道长生》签到页面
-- 7天循环签到 + 广告加倍 + 奖励展示
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameSignin = require("game_signin")
local DataMon    = require("data_monetization")

local M = {}

-- ============================================================================
-- 奖励格式化
-- ============================================================================

--- 将奖励 table 格式化为行文本数组
---@param reward table { lingStone?, spiritStone?, xianYuan?, item?, count? }
---@return string[]
local function FormatRewardLines(reward)
    local lines = {}
    if reward.lingStone then
        lines[#lines + 1] = "灵石 x" .. reward.lingStone
    end
    if reward.spiritStone then
        lines[#lines + 1] = "仙石 x" .. reward.spiritStone
    end
    if reward.xianYuan then
        lines[#lines + 1] = "仙缘 x" .. reward.xianYuan
    end
    if reward.item then
        local cnt = reward.count or reward.itemCount or 1
        lines[#lines + 1] = reward.item .. " x" .. cnt
    end
    return lines
end

-- ============================================================================
-- 单日签到卡片
-- ============================================================================

---@param dayConfig table { day, free, ad }
---@param dayInCycle number 当前周期的签到天（1~7）
---@param signed boolean 今天是否已签到
---@param isToday boolean 是否是今天要签的天
---@return table UI element
local function BuildDayCard(dayConfig, dayInCycle, signed, isToday)
    local day = dayConfig.day
    -- 判断状态：已领取 / 今天 / 未到
    local isPast = day < dayInCycle or (day == dayInCycle and signed)
    local isCurrent = isToday and day == dayInCycle
    local isFuture = not isPast and not isCurrent

    -- 颜色
    local bgColor, borderColor, labelColor
    if isPast then
        bgColor = { 50, 45, 35, 200 }
        borderColor = { 80, 70, 55, 80 }
        labelColor = Theme.colors.textSecondary
    elseif isCurrent then
        bgColor = { 60, 50, 30, 240 }
        borderColor = Theme.colors.gold
        labelColor = Theme.colors.gold
    else
        bgColor = Theme.colors.bgDark
        borderColor = Theme.colors.border
        labelColor = Theme.colors.textLight
    end

    -- 奖励文本
    local rewardLines = FormatRewardLines(dayConfig.free)

    local rewardChildren = {}
    for _, line in ipairs(rewardLines) do
        rewardChildren[#rewardChildren + 1] = UI.Label {
            text = line,
            fontSize = 9,
            fontColor = isPast and { 120, 110, 95, 180 } or Theme.colors.textLight,
            textAlign = "center",
            width = "100%",
        }
    end

    -- 状态标记
    local statusText = ""
    local statusColor = Theme.colors.textSecondary
    if isPast then
        statusText = "已领"
        statusColor = Theme.colors.success
    elseif isCurrent then
        statusText = "今日"
        statusColor = Theme.colors.gold
    end

    return UI.Panel {
        width = "30%",
        minHeight = 90,
        backgroundColor = bgColor,
        borderRadius = Theme.radius.md,
        borderColor = borderColor,
        borderWidth = isCurrent and 2 or 1,
        padding = { 6, 4 },
        gap = 3,
        alignItems = "center",
        justifyContent = "center",
        children = {
            -- 第N天
            UI.Label {
                text = "第" .. day .. "天",
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                fontColor = labelColor,
            },
            -- 奖励列表
            UI.Panel {
                width = "100%",
                gap = 1,
                alignItems = "center",
                children = rewardChildren,
            },
            -- 状态
            statusText ~= "" and UI.Label {
                text = statusText,
                fontSize = 9,
                fontWeight = "bold",
                fontColor = statusColor,
            } or nil,
        },
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local signed = GameSignin.HasSignedToday()
    local adWatched = GameSignin.HasWatchedAd()
    local totalDays = GameSignin.GetTotalDays()
    local dayInCycle = GameSignin.GetDayInCycle()

    -- 7天签到卡片网格
    local dayCards = {}
    for _, r in ipairs(DataMon.SIGNIN_REWARDS) do
        dayCards[#dayCards + 1] = BuildDayCard(r, dayInCycle, signed, true)
    end

    -- 今日奖励详情
    local todayReward = GameSignin.GetTodayReward()
    local freeLines = FormatRewardLines(todayReward.free)
    local adLines = FormatRewardLines(todayReward.ad)

    local freeRewardChildren = {}
    for _, line in ipairs(freeLines) do
        freeRewardChildren[#freeRewardChildren + 1] = UI.Label {
            text = line,
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.textLight,
        }
    end

    local adRewardChildren = {}
    for _, line in ipairs(adLines) do
        adRewardChildren[#adRewardChildren + 1] = UI.Label {
            text = line,
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.gold,
        }
    end

    -- 签到按钮
    local claimButton
    if signed then
        claimButton = Comp.BuildInkButton("今日已签到", nil, { disabled = true })
    else
        claimButton = Comp.BuildInkButton("签到领取", function()
            GameSignin.Claim(function(ok)
                if ok then Router.RebuildUI() end
            end)
        end)
    end

    -- 广告加倍按钮
    local adButton
    if not signed then
        adButton = Comp.BuildSecondaryButton("看广告加倍 (先签到)", nil, { width = "80%" })
    elseif adWatched then
        adButton = Comp.BuildSecondaryButton("加倍奖励已领取", nil, { width = "80%" })
    else
        adButton = UI.Panel {
            width = "80%",
            height = 40,
            borderRadius = Theme.radius.md,
            backgroundColor = { 80, 60, 20, 220 },
            justifyContent = "center",
            alignItems = "center",
            alignSelf = "center",
            borderColor = Theme.colors.gold,
            borderWidth = 1,
            cursor = "pointer",
            onClick = function(self)
                GameSignin.ClaimAdDouble(function(ok)
                    if ok then Router.RebuildUI() end
                end)
            end,
            children = {
                UI.Label {
                    text = "看广告领加倍奖励",
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = Theme.colors.gold,
                },
            },
        }
    end

    -- 页面内容
    local contentChildren = {
        -- 返回按钮
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        -- 标题
        Comp.BuildSectionTitle("每日签到"),

        -- 累计签到统计
        Comp.BuildCardPanel("签到统计", {
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
                                text = tostring(totalDays),
                                fontSize = Theme.fontSize.title,
                                fontWeight = "bold",
                                fontColor = Theme.colors.gold,
                            },
                            UI.Label {
                                text = "累计签到(天)",
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
                                text = "第" .. dayInCycle .. "天",
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Label {
                                text = "当前周期",
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
                                text = signed and "已签" or "未签",
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = signed and Theme.colors.success or Theme.colors.danger,
                            },
                            UI.Label {
                                text = "今日状态",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                },
            },
        }),

        -- 7天签到网格
        Comp.BuildCardPanel("本周期奖励", {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 6,
                justifyContent = "center",
                children = dayCards,
            },
        }),

        -- 今日奖励详情
        Comp.BuildCardPanel("今日奖励详情", {
            -- 免费奖励
            UI.Panel {
                width = "100%",
                gap = 4,
                children = {
                    UI.Label {
                        text = "免费签到奖励",
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Panel {
                        width = "100%",
                        paddingLeft = 8,
                        gap = 2,
                        children = freeRewardChildren,
                    },
                },
            },
            Comp.BuildInkDivider(),
            -- 广告加倍奖励
            UI.Panel {
                width = "100%",
                gap = 4,
                children = {
                    UI.Label {
                        text = "广告加倍奖励",
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = Theme.colors.gold,
                    },
                    UI.Panel {
                        width = "100%",
                        paddingLeft = 8,
                        gap = 2,
                        children = adRewardChildren,
                    },
                },
            },
        }),

        -- 操作按钮
        UI.Panel {
            width = "100%",
            gap = 8,
            alignItems = "center",
            paddingVertical = 8,
            children = {
                claimButton,
                adButton,
            },
        },

        -- 签到说明
        Comp.BuildCardPanel("签到说明", {
            UI.Label {
                text = "每日签到可领取免费奖励，观看广告可额外领取加倍奖励。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "签到奖励每7天为一个周期，循环发放。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "每日签到时间以服务器时间为准，每日0:00重置。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
