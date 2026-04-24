-- ============================================================================
-- 《问道长生》任务系统页
-- 日常/主线任务 + 进度条 + 领取奖励
-- 接入 game_quest.lua 真实逻辑
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local RT = require("rich_text")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameQuest = require("game_quest")
local Toast = require("ui_toast")

local M = {}

-- 当前选中标签
local selectedTab_ = 1
local TAB_LABELS = { "日常", "主线" }
local TAB_KEYS   = { "daily", "main" }

-- 任务状态样式
local statusStyles = {
    claimable = { text = "可领取", fontColor = Theme.colors.gold },
    active    = { text = "进行中", fontColor = Theme.colors.accent },
    completed = { text = "已完成", fontColor = Theme.colors.success },
    locked    = { text = "未解锁", fontColor = Theme.colors.textSecondary },
}

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8,
                paddingVertical = 4,
                cursor = "pointer",
                onClick = function(self)
                    selectedTab_ = 1
                    Router.EnterState(Router.STATE_HOME)
                end,
                children = {
                    UI.Label {
                        text = "< 返回",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = "任务",
                fontSize = Theme.fontSize.heading,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- 标签栏
-- ============================================================================
local function BuildTabBar()
    local tabChildren = {}
    -- 预先获取数据用于红点
    local dailyQuests = GameQuest.GetDailyQuests()
    local mainQuests  = GameQuest.GetMainQuests()
    local questSets = { dailyQuests, mainQuests }

    for i, label in ipairs(TAB_LABELS) do
        local isActive = (i == selectedTab_)
        local quests = questSets[i] or {}
        local claimCount = 0
        for _, q in ipairs(quests) do
            if q.status == "claimable" then claimCount = claimCount + 1 end
        end

        tabChildren[#tabChildren + 1] = UI.Panel {
            flexGrow = 1,
            paddingVertical = 8,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or { 50, 42, 35, 200 },
            alignItems = "center",
            cursor = "pointer",
            onClick = function(self)
                selectedTab_ = i
                Router.RebuildUI()
            end,
            children = {
                UI.Panel {
                    flexDirection = "row",
                    gap = 4,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = label,
                            fontSize = Theme.fontSize.body,
                            fontWeight = isActive and "bold" or "normal",
                            fontColor = isActive and Theme.colors.tabActiveText or Theme.colors.textLight,
                        },
                        claimCount > 0 and UI.Panel {
                            width = 16, height = 16,
                            borderRadius = 8,
                            backgroundColor = Theme.colors.danger,
                            justifyContent = "center",
                            alignItems = "center",
                            children = {
                                UI.Label {
                                    text = tostring(claimCount),
                                    fontSize = 9, fontWeight = "bold",
                                    fontColor = Theme.colors.white,
                                },
                            },
                        } or nil,
                    },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        children = tabChildren,
    }
end

-- ============================================================================
-- 进度条
-- ============================================================================
local function BuildProgressBar(current, max)
    local pct = max > 0 and (current / max) or 0
    if pct > 1 then pct = 1 end

    return UI.Panel {
        width = "100%", height = 8,
        borderRadius = 4,
        backgroundColor = { 50, 45, 35, 255 },
        overflow = "hidden",
        children = {
            UI.Panel {
                width = tostring(math.floor(pct * 100)) .. "%",
                height = "100%",
                borderRadius = 4,
                backgroundColor = pct >= 1 and Theme.colors.success or Theme.colors.accent,
            },
        },
    }
end

-- ============================================================================
-- 单个任务卡片
-- ============================================================================
local function BuildQuestCard(quest)
    local style = statusStyles[quest.status] or statusStyles.active
    local isLocked    = (quest.status == "locked")
    local isClaimable = (quest.status == "claimable")
    local isCompleted = (quest.status == "completed")

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = quest.name,
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                },
                UI.Panel {
                    paddingHorizontal = 8,
                    paddingVertical = 2,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = isClaimable and Theme.colors.gold or { 50, 42, 35, 200 },
                    children = {
                        UI.Label {
                            text = style.text,
                            fontSize = Theme.fontSize.tiny,
                            fontWeight = isClaimable and "bold" or "normal",
                            fontColor = isClaimable and Theme.colors.btnPrimaryText or style.color,
                        },
                    },
                },
            },
        },
        -- 描述
        UI.Label {
            text = quest.desc,
            fontSize = Theme.fontSize.small,
            fontColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
            width = "100%",
        },
        -- 进度条
        (not isLocked and not isCompleted) and UI.Panel {
            width = "100%", gap = 4,
            children = {
                BuildProgressBar(quest.progress, quest.maxProgress),
                (function()
                    local isDone = quest.progress >= quest.maxProgress
                    local numColor = isDone and "<c=green>" or "<c=gray>"
                    local progStr = numColor .. tostring(quest.progress) .. "</c> / " .. tostring(quest.maxProgress)
                    local lbl = RT.Build(progStr, Theme.fontSize.tiny, Theme.colors.textSecondary)
                    lbl.alignSelf = "flex-end"
                    return lbl
                end)(),
            },
        } or nil,
        -- 奖励 + 领取按钮
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginTop = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 4, alignItems = "center",
                    children = {
                        UI.Label {
                            text = "奖励:",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = { 140, 125, 105, 255 },
                        },
                        RT.Build(quest.reward or "", Theme.fontSize.small, Theme.colors.goldLight),
                    },
                },
                isClaimable and UI.Panel {
                    paddingHorizontal = 16,
                    paddingVertical = 6,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = Theme.colors.gold,
                    cursor = "pointer",
                    onClick = function(self)
                        local ok, msg = GameQuest.DoClaim(quest.id)
                        if not ok then
                            Toast.Show(msg, { variant = "error" })
                        end
                        -- ok 时不显示 toast，GameOps 回调会处理结果提示
                        Router.RebuildUI()
                    end,
                    children = {
                        UI.Label {
                            text = "领取",
                            fontSize = Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = Theme.colors.btnPrimaryText,
                        },
                    },
                } or nil,
            },
        },
    })
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 从 GameQuest 获取真实数据
    local quests
    if selectedTab_ == 1 then
        quests = GameQuest.GetDailyQuests()
    else
        quests = GameQuest.GetMainQuests()
    end

    local contentChildren = {
        BuildBackRow(),
        BuildTabBar(),
    }

    -- 按状态排序：可领取 > 进行中 > 已完成 > 未解锁
    local sortOrder = { claimable = 1, active = 2, completed = 3, locked = 4 }
    table.sort(quests, function(a, b)
        return (sortOrder[a.status] or 9) < (sortOrder[b.status] or 9)
    end)

    for _, quest in ipairs(quests) do
        contentChildren[#contentChildren + 1] = BuildQuestCard(quest)
    end

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
