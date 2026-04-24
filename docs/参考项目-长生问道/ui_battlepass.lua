-- ============================================================================
-- 《问道长生》通行证页面
-- 赛季进度 + 免费/付费奖励轨道 + 购买高级通行证
-- ============================================================================

local UI             = require("urhox-libs/UI")
local Theme          = require("ui_theme")
local Comp           = require("ui_components")
local Router         = require("ui_router")
local GamePlayer     = require("game_player")
local GameBattlePass = require("game_battlepass")
local DataMon        = require("data_monetization")

local M = {}

-- ============================================================================
-- 奖励描述格式化
-- ============================================================================

--- 将奖励表转为可读文本
---@param reward table
---@return string
local function FormatReward(reward)
    local parts = {}
    if reward.lingStone then
        parts[#parts + 1] = "灵石x" .. reward.lingStone
    end
    if reward.spiritStone then
        parts[#parts + 1] = "仙石x" .. reward.spiritStone
    end
    if reward.lingDust then
        parts[#parts + 1] = "灵尘x" .. reward.lingDust
    end
    if reward.item then
        local cnt = reward.itemCount or 1
        parts[#parts + 1] = reward.item .. "x" .. cnt
    end
    if reward.title then
        parts[#parts + 1] = "称号:" .. reward.title
    end
    if reward.frame then
        parts[#parts + 1] = "限定头像框"
    end
    return table.concat(parts, "\n")
end

-- ============================================================================
-- 单个等级奖励行
-- ============================================================================

---@param lv number
---@param rewardDef table { free, paid }
---@param status table  当前状态
---@param isMilestone boolean 是否里程碑等级
---@return table UI element
local function BuildRewardRow(lv, rewardDef, status, isMilestone)
    local currentLv = status.level
    local isPremium = status.isPremium
    local reached = currentLv >= lv

    -- 免费轨道
    local freeClaimed  = GameBattlePass.HasClaimed(lv, "free")
    local freeCanClaim = GameBattlePass.CanClaim(lv, "free")

    -- 付费轨道
    local paidClaimed  = GameBattlePass.HasClaimed(lv, "paid")
    local paidCanClaim = GameBattlePass.CanClaim(lv, "paid")

    -- 等级标签颜色（里程碑用金色加粗）
    local lvColor = reached and Theme.colors.textGold or Theme.colors.textSecondary
    if isMilestone and not reached then
        lvColor = { 180, 150, 80, 200 }  -- 未达到的里程碑用暗金
    end

    -- 按钮/状态构建
    local function MakeClaimBtn(track, canClaim, claimed)
        if claimed then
            return UI.Label {
                text = "已领取",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.success,
            }
        elseif canClaim then
            return UI.Panel {
                paddingHorizontal = 8,
                paddingVertical = 3,
                borderRadius = Theme.radius.sm,
                backgroundColor = Theme.colors.gold,
                cursor = "pointer",
                onClick = function(self)
                    GameBattlePass.ClaimReward(lv, track, function(ok)
                        if ok then Router.RebuildUI() end
                    end)
                end,
                children = {
                    UI.Label {
                        text = "领取",
                        fontSize = Theme.fontSize.tiny,
                        fontWeight = "bold",
                        fontColor = Theme.colors.bgDarkSolid,
                    },
                },
            }
        elseif track == "paid" and not isPremium then
            return UI.Label {
                text = "需高级",
                fontSize = Theme.fontSize.tiny,
                fontColor = { 150, 100, 50, 180 },
            }
        else
            return UI.Label {
                text = "未达到",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
            }
        end
    end

    -- 背景色：里程碑更醒目
    local rowBg = reached and { 50, 45, 35, 150 } or { 35, 30, 25, 100 }
    if isMilestone then
        rowBg = reached and { 60, 50, 30, 180 } or { 45, 38, 25, 140 }
    end

    -- 边框：可领取 > 里程碑 > 普通
    local canClaimAny = freeCanClaim or paidCanClaim
    local borderClr = canClaimAny and Theme.colors.gold
        or (isMilestone and { 120, 100, 50, 120 } or Theme.colors.border)
    local borderW = canClaimAny and 1 or (isMilestone and 1 or 0)

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = isMilestone and 8 or 5,
        paddingHorizontal = 8,
        borderRadius = Theme.radius.sm,
        backgroundColor = rowBg,
        borderColor = borderClr,
        borderWidth = borderW,
        gap = 6,
        children = {
            -- 等级
            UI.Panel {
                width = 36,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = isMilestone and ("Lv." .. lv) or tostring(lv),
                        fontSize = isMilestone and Theme.fontSize.body or Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = lvColor,
                    },
                },
            },
            -- 免费奖励
            UI.Panel {
                flex = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = "[免费]",
                        fontSize = 9,
                        fontColor = Theme.colors.success,
                    },
                    UI.Label {
                        text = FormatReward(rewardDef.free),
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textLight,
                    },
                    MakeClaimBtn("free", freeCanClaim, freeClaimed),
                },
            },
            -- 分隔
            UI.Panel {
                width = 1,
                height = "80%",
                backgroundColor = Theme.colors.divider,
            },
            -- 付费奖励
            UI.Panel {
                flex = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = "[高级]",
                        fontSize = 9,
                        fontColor = { 200, 168, 85, 255 },
                    },
                    UI.Label {
                        text = FormatReward(rewardDef.paid),
                        fontSize = Theme.fontSize.tiny,
                        fontColor = isPremium and Theme.colors.textLight or Theme.colors.textSecondary,
                    },
                    MakeClaimBtn("paid", paidCanClaim, paidClaimed),
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

    local status = GameBattlePass.GetStatus()
    local curExp, totalExp = GameBattlePass.GetLevelProgress()

    -- 经验进度条比例
    local progressRatio = (totalExp > 0) and (curExp / totalExp) or 0
    local progressPct = math.floor(progressRatio * 100)

    -- 奖励行列表（50级全部显示，里程碑高亮）
    local rewardRows = {}
    for _, lv in ipairs(DataMon.BATTLE_PASS_LEVELS) do
        local rewardDef = DataMon.GetBattlePassReward(lv)
        if rewardDef then
            local isMilestone = DataMon.BATTLE_PASS_MILESTONE[lv] == true
            rewardRows[#rewardRows + 1] = BuildRewardRow(lv, rewardDef, status, isMilestone)
        end
    end

    -- 经验来源说明
    local expSourceRows = {}
    local sourceLabels = {
        dailyLogin     = "每日登录",
        dailyQuest     = "每日任务",
        exploreWin     = "探索胜利",
        weeklyQuest    = "每周任务",
        breakthrough   = "境界突破",
    }
    for src, amount in pairs(DataMon.BATTLE_PASS.expSources) do
        expSourceRows[#expSourceRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            paddingVertical = 2,
            children = {
                UI.Label {
                    text = sourceLabels[src] or src,
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                },
                UI.Label {
                    text = "+" .. amount .. "经验",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textGold,
                },
            },
        }
    end

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        Comp.BuildSectionTitle("修仙通行证"),

        -- 赛季信息卡片
        Comp.BuildCardPanel("赛季概览", {
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
                                text = status.seasonId,
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Label {
                                text = "当前赛季",
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
                                text = tostring(status.remainDays) .. "天",
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = status.remainDays <= 7
                                    and Theme.colors.danger or Theme.colors.textLight,
                            },
                            UI.Label {
                                text = "剩余天数",
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
                                text = status.isPremium and "已激活" or "未激活",
                                fontSize = Theme.fontSize.subtitle,
                                fontWeight = "bold",
                                fontColor = status.isPremium
                                    and Theme.colors.success or Theme.colors.textSecondary,
                            },
                            UI.Label {
                                text = "高级通行证",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                },
            },
        }),

        -- 等级进度
        Comp.BuildCardPanel("等级进度", {
            -- 等级数字
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "flex-end",
                children = {
                    UI.Label {
                        text = "Lv." .. status.level,
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = curExp .. " / " .. totalExp .. " (" .. progressPct .. "%)",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                    },
                },
            },
            -- 进度条背景
            UI.Panel {
                width = "100%",
                height = 10,
                borderRadius = 5,
                backgroundColor = { 60, 50, 40, 200 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.max(progressPct, 1)) .. "%",
                        height = "100%",
                        borderRadius = 5,
                        backgroundColor = Theme.colors.gold,
                    },
                },
            },
            -- 满级提示
            status.level >= status.maxLevel and UI.Label {
                text = "已达最高等级",
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
                marginTop = 4,
            } or nil,
        }),

        -- 购买高级通行证按钮（未购买时显示）
        not status.isPremium and UI.Panel {
            width = "100%",
            height = 48,
            borderRadius = Theme.radius.md,
            backgroundColor = { 160, 100, 20, 240 },
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            marginBottom = Theme.spacing.sm,
            onClick = function(self)
                GameBattlePass.BuyPremium(function(ok)
                    if ok then Router.RebuildUI() end
                end)
            end,
            children = {
                UI.Label {
                    text = "购买高级通行证  " .. status.premiumPrice .. "元",
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = { 255, 230, 180, 255 },
                },
            },
        } or nil,

        -- 奖励轨道（限高滚动）
        Comp.BuildCardPanel("奖励一览", {
            UI.Panel {
                width = "100%",
                maxHeight = 300,
                overflow = "scroll",
                gap = Theme.spacing.sm,
                children = rewardRows,
            },
        }),

        -- 经验来源说明
        Comp.BuildCardPanel("经验获取途径", expSourceRows),

        -- 规则说明
        Comp.BuildCardPanel("通行证规则", {
            UI.Label {
                text = "每赛季持续" .. DataMon.BATTLE_PASS.seasonDays .. "天，赛季结束后进度重置。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "免费轨道所有玩家均可领取，高级轨道需购买高级通行证。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "通过日常活动获取经验提升通行证等级，到达对应等级即可领取奖励。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
            UI.Label {
                text = "高级通行证购买后立即生效，可追溯领取已达到等级的付费奖励。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
                width = "100%",
            },
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
