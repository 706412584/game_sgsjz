-- ============================================================================
-- 《问道长生》角色创建页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local DataRace = require("data_race")
local DataSpiritRoot = require("data_spirit_root")

local M = {}

-- 角色创建临时数据
local roleData = {
    gender = "男",
    avatarIndex = 1,
    race = DataRace.DEFAULT,
    spiritRootType = DataSpiritRoot.GOLD,  -- 五行灵根类型（默认金）
    fortune = "普通机缘",
    name = "",
}
local fortunes = { "普通机缘", "稀有机缘", "传说机缘", "无机缘" }

-- 随机道号素材
local NAME_PREFIXES = {
    "清", "玄", "紫", "青", "云", "风", "明", "星", "天", "灵",
    "无", "凌", "逸", "幽", "苍", "墨", "白", "素", "尘", "寒",
    "静", "虚", "道", "真", "玉", "鹤", "松", "竹", "兰", "梅",
}
local NAME_SUFFIXES = {
    "尘", "风", "云", "鹤", "阳", "虚", "玄", "真", "一", "然",
    "道", "心", "明", "远", "空", "逸", "默", "幽", "澜", "霄",
    "微", "渺", "朴", "素", "清", "宁", "安", "止", "觉", "悟",
}

local function RandomDaoName()
    local p = NAME_PREFIXES[math.random(1, #NAME_PREFIXES)]
    local s = NAME_SUFFIXES[math.random(1, #NAME_SUFFIXES)]
    -- 避免前后相同
    while s == p do
        s = NAME_SUFFIXES[math.random(1, #NAME_SUFFIXES)]
    end
    return p .. s
end

-- 构建选择行
local function BuildSelectRow(label, value, onTap)
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        padding = { 12, 16 },
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            if onTap then onTap() end
        end,
        children = {
            UI.Label {
                text = label,
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
            UI.Label {
                text = value,
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
        },
    }
end

function M.Build(payload)
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgCreateRole,
        backgroundFit = "cover",
        children = {
            -- 半透明遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 20, 18, 15, 120 },
            },
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
                        padding = { 40, 24, 24, 24 },
                        gap = 16,
                        alignItems = "center",
                        children = {
                            -- 页面标题
                            UI.Label {
                                text = "开 辟 道 途",
                                fontSize = 28,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                                textAlign = "center",
                            },
                            UI.Label {
                                text = "选定根基，踏入修行之路",
                                fontSize = Theme.fontSize.small,
                                fontColor = Theme.colors.textLight,
                                textAlign = "center",
                                marginBottom = 8,
                            },

                            -- 当前选中的头像（大图预览）
                            UI.Panel {
                                width = 120,
                                height = 120,
                                borderRadius = 60,
                                backgroundColor = { 35, 30, 25, 180 },
                                borderColor = Theme.colors.gold,
                                borderWidth = 2,
                                justifyContent = "center",
                                alignItems = "center",
                                overflow = "hidden",
                                children = {
                                    UI.Panel {
                                        width = 100,
                                        height = 100,
                                        backgroundImage = Theme.avatars[roleData.gender][roleData.avatarIndex],
                                        backgroundFit = "contain",
                                    },
                                },
                            },

                            -- 头像选择网格（5个头像一排）
                            UI.Panel {
                                width = "100%",
                                flexDirection = "row",
                                justifyContent = "center",
                                gap = 8,
                                marginBottom = 8,
                                children = (function()
                                    local items = {}
                                    local avatarList = Theme.avatars[roleData.gender]
                                    for i = 1, #avatarList do
                                        local selected = (i == roleData.avatarIndex)
                                        items[#items + 1] = UI.Panel {
                                            width = 52,
                                            height = 52,
                                            borderRadius = 26,
                                            backgroundColor = selected and { 200, 168, 85, 60 } or { 35, 30, 25, 150 },
                                            borderColor = selected and Theme.colors.gold or Theme.colors.border,
                                            borderWidth = selected and 2 or 1,
                                            justifyContent = "center",
                                            alignItems = "center",
                                            overflow = "hidden",
                                            cursor = "pointer",
                                            onClick = function(self)
                                                roleData.avatarIndex = i
                                                Router.RebuildUI()
                                            end,
                                            children = {
                                                UI.Panel {
                                                    width = 44,
                                                    height = 44,
                                                    backgroundImage = avatarList[i],
                                                    backgroundFit = "contain",
                                                },
                                            },
                                        }
                                    end
                                    return items
                                end)(),
                            },

                            -- 性别选择（分段按钮）
                            UI.Panel {
                                width = "100%",
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "性别",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = Theme.colors.textSecondary,
                                        marginBottom = 4,
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        gap = 8,
                                        children = {
                                            -- 男
                                            UI.Panel {
                                                flexGrow = 1,
                                                height = 40,
                                                borderRadius = Theme.radius.md,
                                                backgroundColor = roleData.gender == "男" and Theme.colors.gold or Theme.colors.bgDark,
                                                borderColor = Theme.colors.borderGold,
                                                borderWidth = 1,
                                                justifyContent = "center",
                                                alignItems = "center",
                                                cursor = "pointer",
                                                onClick = function(self)
                                                    roleData.gender = "男"
                                                    roleData.avatarIndex = 1
                                                    Router.RebuildUI()
                                                end,
                                                children = {
                                                    UI.Label {
                                                        text = "男",
                                                        fontSize = Theme.fontSize.body,
                                                        fontWeight = "bold",
                                                        fontColor = roleData.gender == "男" and Theme.colors.btnPrimaryText or Theme.colors.textLight,
                                                    },
                                                },
                                            },
                                            -- 女
                                            UI.Panel {
                                                flexGrow = 1,
                                                height = 40,
                                                borderRadius = Theme.radius.md,
                                                backgroundColor = roleData.gender == "女" and Theme.colors.gold or Theme.colors.bgDark,
                                                borderColor = Theme.colors.borderGold,
                                                borderWidth = 1,
                                                justifyContent = "center",
                                                alignItems = "center",
                                                cursor = "pointer",
                                                onClick = function(self)
                                                    roleData.gender = "女"
                                                    roleData.avatarIndex = 1
                                                    Router.RebuildUI()
                                                end,
                                                children = {
                                                    UI.Label {
                                                        text = "女",
                                                        fontSize = Theme.fontSize.body,
                                                        fontWeight = "bold",
                                                        fontColor = roleData.gender == "女" and Theme.colors.btnPrimaryText or Theme.colors.textLight,
                                                    },
                                                },
                                            },
                                        },
                                    },
                                },
                            },

                            -- 种族选择（分段按钮 4选1）
                            UI.Panel {
                                width = "100%",
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "种族",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = Theme.colors.textSecondary,
                                        marginBottom = 4,
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        gap = 6,
                                        children = (function()
                                            local btns = {}
                                            for _, raceDef in ipairs(DataRace.RACES) do
                                                local rid = raceDef.id
                                                local selected = (roleData.race == rid)
                                                btns[#btns + 1] = UI.Panel {
                                                    flexGrow = 1,
                                                    height = 40,
                                                    borderRadius = Theme.radius.md,
                                                    backgroundColor = selected
                                                        and { raceDef.color[1], raceDef.color[2], raceDef.color[3], 200 }
                                                        or Theme.colors.bgDark,
                                                    borderColor = selected and raceDef.color or Theme.colors.borderGold,
                                                    borderWidth = 1,
                                                    justifyContent = "center",
                                                    alignItems = "center",
                                                    cursor = "pointer",
                                                    onClick = function(self)
                                                        roleData.race = rid
                                                        Router.RebuildUI()
                                                    end,
                                                    children = {
                                                        UI.Label {
                                                            text = raceDef.name,
                                                            fontSize = Theme.fontSize.small,
                                                            fontWeight = "bold",
                                                            fontColor = selected and { 20, 18, 15, 255 } or Theme.colors.textLight,
                                                        },
                                                    },
                                                }
                                            end
                                            return btns
                                        end)(),
                                    },
                                    -- 种族加成提示
                                    UI.Label {
                                        text = (function()
                                            local descs = DataRace.GetBonusDescs(roleData.race)
                                            local raceDef = DataRace.GetRace(roleData.race)
                                            return (raceDef and raceDef.position or "") .. "  " .. table.concat(descs, "  ")
                                        end)(),
                                        fontSize = Theme.fontSize.tiny,
                                        fontColor = { 160, 200, 140, 200 },
                                        marginTop = 2,
                                    },
                                },
                            },

                            -- 灵根（五行选择）
                            UI.Panel {
                                width = "100%",
                                gap = 4,
                                children = {
                                    UI.Label {
                                        text = "灵根",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = Theme.colors.textSecondary,
                                        marginBottom = 4,
                                    },
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        gap = 6,
                                        children = (function()
                                            local btns = {}
                                            for _, typeId in ipairs(DataSpiritRoot.BASE_LIST) do
                                                local t = DataSpiritRoot.TYPES[typeId]
                                                local selected = (roleData.spiritRootType == typeId)
                                                btns[#btns + 1] = UI.Panel {
                                                    flexGrow = 1,
                                                    height = 40,
                                                    borderRadius = Theme.radius.md,
                                                    backgroundColor = selected
                                                        and { t.color[1], t.color[2], t.color[3], 200 }
                                                        or Theme.colors.bgDark,
                                                    borderColor = selected and t.color or Theme.colors.borderGold,
                                                    borderWidth = 1,
                                                    justifyContent = "center",
                                                    alignItems = "center",
                                                    cursor = "pointer",
                                                    onClick = function(self)
                                                        roleData.spiritRootType = typeId
                                                        Router.RebuildUI()
                                                    end,
                                                    children = {
                                                        UI.Label {
                                                            text = t.name,
                                                            fontSize = Theme.fontSize.small,
                                                            fontWeight = "bold",
                                                            fontColor = selected and { 20, 18, 15, 255 } or Theme.colors.textLight,
                                                        },
                                                    },
                                                }
                                            end
                                            return btns
                                        end)(),
                                    },
                                    UI.Label {
                                        text = "品质随机（创角后确定）",
                                        fontSize = Theme.fontSize.tiny,
                                        fontColor = { 160, 200, 140, 200 },
                                        marginTop = 2,
                                    },
                                },
                            },

                            -- 机缘
                            BuildSelectRow("机  缘", roleData.fortune, function()
                                local idx = math.random(1, #fortunes)
                                roleData.fortune = fortunes[idx]
                                Router.RebuildUI()
                            end),

                            -- 道号输入
                            UI.Panel {
                                width = "100%",
                                gap = 4,
                                marginTop = 8,
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        alignItems = "center",
                                        children = {
                                            UI.Label {
                                                text = "道号",
                                                fontSize = Theme.fontSize.small,
                                                fontColor = Theme.colors.textSecondary,
                                            },
                                            UI.Panel {
                                                paddingLeft = 10,
                                                paddingRight = 10,
                                                paddingTop = 4,
                                                paddingBottom = 4,
                                                borderRadius = Theme.radius.sm,
                                                backgroundColor = { 35, 30, 25, 180 },
                                                borderColor = Theme.colors.borderGold,
                                                borderWidth = 1,
                                                cursor = "pointer",
                                                onClick = function(self)
                                                    roleData.name = RandomDaoName()
                                                    Router.RebuildUI()
                                                end,
                                                children = {
                                                    UI.Label {
                                                        text = "随机道号",
                                                        fontSize = Theme.fontSize.tiny,
                                                        fontColor = Theme.colors.textGold,
                                                    },
                                                },
                                            },
                                        },
                                    },
                                    UI.TextField {
                                        value = roleData.name,
                                        placeholder = "请输入道号...",
                                        maxLength = 12,
                                        fontSize = Theme.fontSize.body,
                                        onChange = function(self, v)
                                            roleData.name = v
                                        end,
                                    },
                                },
                            },

                            -- 间距
                            UI.Panel { height = 16 },

                            -- 确认创建
                            Comp.BuildInkButton("确认创建", function()
                                local raceName = DataRace.LABEL[roleData.race] or "人族"
                                local quality = DataSpiritRoot.RandomQuality()
                                local charInfo = {
                                    gender = roleData.gender,
                                    name = roleData.name,
                                    avatarIndex = roleData.avatarIndex,
                                    race = roleData.race,
                                    spiritRoots = {
                                        { type = roleData.spiritRootType, quality = quality, slot = 1 },
                                    },
                                    fortune = roleData.fortune,
                                }
                                print("[角色创建] 创建角色: " .. charInfo.name .. " 种族: " .. raceName
                                    .. " 灵根: " .. DataSpiritRoot.TYPES[roleData.spiritRootType].name
                                    .. "-" .. DataSpiritRoot.GetQualityName(quality))
                                local GamePlayer = require("game_player")
                                GamePlayer.CreateCharacter(charInfo, function(success)
                                    if success then
                                        print("[角色创建] 角色数据保存成功")
                                    else
                                        print("[角色创建] 角色数据保存失败")
                                    end
                                end)
                                Router.EnterState(Router.STATE_HOME, { newPlayer = true })
                            end),

                            -- 返回
                            Comp.BuildTextButton("返回标题", function()
                                Router.EnterState(Router.STATE_TITLE)
                            end, { fontColor = Theme.colors.textSecondary }),
                        },
                    },
                },
            },
        },
    }

    -- 入场淡入效果（从故事页过渡而来）
    root:SetStyle({ opacity = 0 })
    root:Animate({
        keyframes = {
            [0] = { opacity = 0 },
            [1] = { opacity = 1 },
        },
        duration = 1.0,
        easing = "easeOut",
        fillMode = "forwards",
    })

    return root
end

return M
