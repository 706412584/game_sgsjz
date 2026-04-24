-- ============================================================================
-- 《问道长生》主菜单页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")

local M = {}

-- 菜单功能列表（静态配置）
local MENU_FEATURES = {
    { name = "功法",   unlocked = true },
    { name = "乾坤袋", unlocked = true },
    { name = "坊市",   unlocked = true },
    { name = "试炼",   unlocked = true },
    { name = "渡劫",   unlocked = false },
    { name = "宗门",   unlocked = false },
    { name = "聊天",   unlocked = false },
    { name = "任务",   unlocked = false },
    { name = "排行",   unlocked = false },
}

-- 功能名称 -> 图标路径映射
local featureIcons = {
    ["功法"]   = Theme.images.iconQuest,
    ["乾坤袋"] = Theme.images.iconBag,
    ["坊市"]   = Theme.images.iconCurrency,
    ["试炼"]   = Theme.images.iconTrial,
    ["渡劫"]   = Theme.images.iconExplore,
    ["宗门"]   = Theme.images.iconSect,
    ["聊天"]   = Theme.images.iconChat,
    ["任务"]   = Theme.images.iconQuest,
    ["排行"]   = Theme.images.iconWorldMap,
}

-- 功能格子项
local function BuildFeatureCell(item)
    local isLocked = not item.unlocked
    local bgColor = isLocked and { 50, 45, 35, 150 } or Theme.colors.bgDark
    local txtColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight
    local iconPath = featureIcons[item.name]

    return UI.Panel {
        width = "30%",
        aspectRatio = 1,
        borderRadius = Theme.radius.md,
        backgroundColor = bgColor,
        borderColor = isLocked and Theme.colors.border or Theme.colors.borderGold,
        borderWidth = 1,
        justifyContent = "center",
        alignItems = "center",
        gap = 4,
        cursor = isLocked and "default" or "pointer",
        onClick = function(self)
            if not isLocked then
                print("[菜单] 点击: " .. item.name)
            end
        end,
        children = {
            -- 功能图标
            iconPath and UI.Panel {
                width = 36,
                height = 36,
                backgroundImage = iconPath,
                backgroundFit = "contain",
                imageTint = isLocked and { 80, 75, 65, 120 } or nil,
            } or nil,
            UI.Label {
                text = item.name,
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = txtColor,
            },
            isLocked and UI.Label {
                text = "未开放",
                fontSize = Theme.fontSize.tiny,
                fontColor = { 100, 90, 75, 120 },
            } or nil,
        },
    }
end

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 构建功能格子
    local featureCells = {}
    for _, item in ipairs(MENU_FEATURES) do
        featureCells[#featureCells + 1] = BuildFeatureCell(item)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgMenu,
        backgroundFit = "cover",
        children = {
            -- 背景遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 15, 12, 10, 150 },
            },
            -- 顶栏: 角色信息
            Comp.BuildTopBar(p),

            -- 主内容
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = false,
                scrollMultiplier = Theme.scrollSensitivity,
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = Theme.spacing.md,
                        gap = Theme.spacing.lg,
                        alignItems = "center",
                        children = {
                            -- 修为进度
                            Comp.BuildCultivationBar(p.cultivation, p.cultivationMax),

                            -- 中央标语
                            UI.Panel {
                                width = "100%",
                                paddingVertical = 20,
                                alignItems = "center",
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "踏入修仙界",
                                        fontSize = Theme.fontSize.title,
                                        fontWeight = "bold",
                                        fontColor = Theme.colors.textGold,
                                    },
                                    UI.Label {
                                        text = "道在脚下，心在天外",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = Theme.colors.textLight,
                                    },
                                },
                            },

                            -- 功能宫格
                            Comp.BuildSectionTitle("功能入口"),
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                flexWrap = "wrap",
                                gap = 8,
                                justifyContent = "center",
                                children = featureCells,
                            },

                            -- 底部快捷入口
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                gap = 8,
                                marginTop = 8,
                                children = {
                                    UI.Panel {
                                        flexGrow = 1,
                                        children = {
                                            Comp.BuildInkButton("洞 府", function()
                                                Router.EnterState(Router.STATE_HOME)
                                            end, { width = "100%", fontSize = Theme.fontSize.body }),
                                        },
                                    },
                                    UI.Panel {
                                        flexGrow = 1,
                                        children = {
                                            Comp.BuildSecondaryButton("游 历", function()
                                                Router.EnterState(Router.STATE_WORLD_MAP)
                                            end, { width = "100%" }),
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
            },

            -- 底部导航（菜单页无高亮 tab）
            Comp.BuildBottomNav("", Router.HandleNavigate),
        },
    }
end

return M
