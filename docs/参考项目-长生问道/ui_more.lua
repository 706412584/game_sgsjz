-- ============================================================================
-- 《问道长生》更多功能页
-- 按分区展示：社交交流 / 交易市场 / 挑战玩法 / 福利商城 / 系统
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local Settings = require("ui_settings")
local RedDot = require("ui_red_dot")

local M = {}

-- ============================================================================
-- 分区数据
-- ============================================================================
local sections = {
    {
        title = "社交交流",
        items = {
            { name = "聊天", icon = Theme.images.iconChat,    desc = "仙友交流", state = Router.STATE_CHAT,    dotKey = RedDot.KEYS.MORE_CHAT },
            { name = "排行", icon = Theme.images.iconRanking, desc = "仙道排名", state = Router.STATE_RANKING, dotKey = RedDot.KEYS.MORE_RANKING },
        },
    },
    {
        title = "福利商城",
        items = {
            { name = "VIP",    icon = Theme.images.iconRanking,  desc = "VIP特权",    state = Router.STATE_VIP },
            { name = "抽奖",   icon = Theme.images.iconMarket,   desc = "仙缘抽奖",   state = Router.STATE_GACHA },
            { name = "通行证", icon = Theme.images.iconQuest,    desc = "赛季通行证", state = Router.STATE_BATTLEPASS },
            { name = "任务",   icon = Theme.images.iconQuest,    desc = "修仙任务",   state = Router.STATE_QUEST,      dotKey = RedDot.KEYS.MORE_QUEST },
        },
    },
    {
        title = "系统",
        items = {
            { name = "设置", icon = Theme.images.iconSettings, desc = "游戏设置", state = nil, action = "settings" },
        },
    },
}

-- ============================================================================
-- 单个功能卡片
-- ============================================================================
local function BuildFeatureCard(feat)
    local hasAction = (feat.state ~= nil or feat.action ~= nil)
    local isLocked = not hasAction

    local card = UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 12,
        padding = Theme.spacing.sm,
        borderRadius = Theme.radius.md,
        backgroundColor = isLocked and { 40, 35, 30, 120 } or Theme.colors.bgDark,
        borderColor = isLocked and Theme.colors.border or Theme.colors.borderGold,
        borderWidth = 1,
        cursor = isLocked and "default" or "pointer",
        hitSlop = 0,
        onClick = function(self)
            if isLocked then return end
            if feat.action == "settings" then
                Settings.Show()
            elseif feat.state then
                Router.EnterState(feat.state)
            end
        end,
        children = {
            -- 图标
            UI.Panel {
                width = 36,
                height = 36,
                backgroundImage = feat.icon,
                backgroundFit = "contain",
                imageTint = isLocked and { 120, 110, 100, 150 } or Theme.colors.gold,
            },
            -- 名称 + 描述
            UI.Panel {
                flexGrow = 1,
                gap = 2,
                children = {
                    UI.Label {
                        text = feat.name,
                        fontSize = Theme.fontSize.subtitle,
                        fontWeight = "bold",
                        fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                    },
                    UI.Label {
                        text = isLocked and "敬请期待" or feat.desc,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.textSecondary,
                    },
                },
            },
            -- 右箭头
            UI.Label {
                text = ">",
                fontSize = Theme.fontSize.body,
                fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
            },
        },
    }
    -- 红点包装
    if feat.dotKey then
        return Comp.WithRedDot(card, feat.dotKey)
    end
    return card
end

-- ============================================================================
-- 分区标题
-- ============================================================================
local function BuildSectionHeader(title)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        marginTop = 12,
        marginBottom = 4,
        paddingHorizontal = 4,
        children = {
            -- 左装饰线
            UI.Panel {
                height = 1,
                flexGrow = 1,
                backgroundColor = Theme.colors.borderGold,
            },
            UI.Label {
                text = title,
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
            -- 右装饰线
            UI.Panel {
                height = 1,
                flexGrow = 1,
                backgroundColor = Theme.colors.borderGold,
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
        Comp.BuildSectionTitle("更多功能"),
    }

    for _, section in ipairs(sections) do
        -- 分区标题
        contentChildren[#contentChildren + 1] = BuildSectionHeader(section.title)
        -- 功能列表（单列）
        for _, feat in ipairs(section.items) do
            contentChildren[#contentChildren + 1] = BuildFeatureCard(feat)
        end
    end

    -- 底部留白
    contentChildren[#contentChildren + 1] = UI.Panel { height = 40 }

    return Comp.BuildPageShell("more", p, contentChildren, Router.HandleNavigate)
end

return M
