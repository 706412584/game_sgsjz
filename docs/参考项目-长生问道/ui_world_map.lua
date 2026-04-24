-- ============================================================================
-- 《问道长生》游历地图页（地图风格 - 背景图 + 绝对定位功能点）
-- 支持区域选择 + 难度选择，传递 areaId/difficulty 到探索页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameExplore = require("game_explore")
local DataWorld = require("data_world")
local DataRealms = require("data_realms")
local NVG = require("nvg_manager")

local M = {}

-- 当前选中区域索引（nil 表示未选中）
local selectedIdx = nil
-- 当前选中难度（默认普通）
local selectedDifficulty = "normal"
-- 当前地图 Tab："mortal"=凡界舆图，"immortal"=仙界秘境
local currentMapTab_ = "mortal"

-- ============================================================================
-- 地图位置点数据（包含绝对定位坐标 %）
-- ============================================================================
local mapPoints = {
    {
        icon = Theme.images.iconExplore,
        posX = "18%",  posY = "22%",
        areaIdx = 1,
    },
    {
        icon = Theme.images.iconSect,
        posX = "68%",  posY = "18%",
        areaIdx = 2,
    },
    {
        icon = Theme.images.iconWorldMap,
        posX = "72%",  posY = "52%",
        areaIdx = 3,
    },
    {
        icon = Theme.images.iconAlchemy,
        posX = "25%",  posY = "58%",
        areaIdx = 4,
    },
}

-- ============================================================================
-- 难度颜色配置
-- ============================================================================
local DIFF_COLORS = {
    normal = { 160, 200, 160 },
    elite  = { 220, 180, 80 },
    hard   = { 220, 80, 80 },
}

-- ============================================================================
-- 构建地图上的功能点
-- ============================================================================
local function BuildLocationMarker(point, area, isSelected, isUnlocked)
    local markerAlpha = isUnlocked and 255 or 100
    return UI.Panel {
        position = "absolute",
        left = point.posX,
        top = point.posY,
        width = 90,
        height = 88,
        alignItems = "center",
        gap = 3,
        cursor = isUnlocked and "pointer" or "default",
        onClick = function(self)
            if not isUnlocked then return end
            if selectedIdx == point.areaIdx then
                selectedIdx = nil  -- 再次点击取消
            else
                selectedIdx = point.areaIdx
            end
            Router.RebuildUI()
        end,
        children = {
            -- 发光底盘（选中时显示）
            UI.Panel {
                width = 52,
                height = 52,
                borderRadius = 26,
                backgroundColor = isSelected and { 200, 168, 85, 60 }
                    or (not isUnlocked and { 60, 55, 50, 100 } or { 30, 25, 20, 100 }),
                borderColor = isSelected and Theme.colors.gold
                    or (not isUnlocked and { 120, 110, 100, 80 } or { 200, 168, 85, 80 }),
                borderWidth = isSelected and 2 or 1,
                justifyContent = "center",
                alignItems = "center",
                children = {
                    -- 图标
                    UI.Panel {
                        width = 30,
                        height = 30,
                        backgroundImage = point.icon,
                        backgroundFit = "contain",
                        imageTint = isSelected and Theme.colors.gold
                            or (not isUnlocked and { 120, 110, 100, markerAlpha } or { 220, 210, 190, 230 }),
                    },
                    -- 锁定标记
                    not isUnlocked and UI.Label {
                        position = "absolute",
                        bottom = -2,
                        fontSize = 16,
                        text = "X",
                        fontColor = { 180, 80, 80, 200 },
                        fontWeight = "bold",
                    } or nil,
                },
            },
            -- 地名（毛笔刷背景）
            UI.Panel {
                width = 88,
                height = 28,
                backgroundImage = Theme.images.brushLabelBg,
                backgroundFit = "fill",
                justifyContent = "center",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = area.name,
                        fontSize = 12,
                        fontWeight = "bold",
                        fontColor = isSelected and Theme.colors.gold
                            or (not isUnlocked and { 150, 140, 130, 180 } or { 230, 220, 200, 240 }),
                        textAlign = "center",
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 难度选择标签
-- ============================================================================
local function BuildDifficultySelector()
    local tabs = {}
    for _, diff in ipairs(DataWorld.DIFFICULTIES) do
        local isActive = selectedDifficulty == diff.id
        local diffColor = DIFF_COLORS[diff.id] or { 180, 180, 180 }
        tabs[#tabs + 1] = UI.Panel {
            paddingLeft = 10, paddingRight = 10,
            paddingTop = 4, paddingBottom = 4,
            borderRadius = 4,
            backgroundColor = isActive and { diffColor[1], diffColor[2], diffColor[3], 40 } or { 0, 0, 0, 0 },
            borderColor = isActive and diffColor or { 100, 90, 80, 120 },
            borderWidth = isActive and 1 or 0,
            cursor = "pointer",
            onClick = function(self)
                selectedDifficulty = diff.id
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = diff.name,
                    fontSize = Theme.fontSize.small,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and diffColor or { 160, 150, 140 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 8,
        children = tabs,
    }
end

-- ============================================================================
-- 选中区域的详情浮层
-- ============================================================================
local function BuildDetailPopup(area, isUnlocked, playerTier)
    local rewardText = area.drops and table.concat(area.drops, "、") or "探索可获取灵石与材料"
    -- 仙界区域：补充 immortalDrop 掉落信息
    if area.isImmortal and area.immortalDrop then
        local id = area.immortalDrop
        local dropInfo = id.name .. "（" .. id.rate .. "%概率，" .. id.countMin
            .. (id.countMax > id.countMin and ("-" .. id.countMax) or "") .. "个/战）"
        rewardText = rewardText .. "、" .. dropInfo
    end
    local diffConf = DataWorld.GetDifficulty(selectedDifficulty)
    local diffColor = DIFF_COLORS[selectedDifficulty] or { 180, 180, 180 }

    -- 解锁条件文字（支持仙界 tier >= 11）
    local unlockText = ""
    if not isUnlocked then
        local realmData = DataRealms.GetAnyRealm(area.unlockTier)
        local realmName = realmData and realmData.name or ("第" .. area.unlockTier .. "阶")
        unlockText = "需要达到 " .. realmName .. " 境界解锁"
    end

    -- 难度倍率说明
    local mulText = ""
    if diffConf then
        local parts = {}
        if diffConf.statMul ~= 1 then parts[#parts + 1] = "怪物强度x" .. diffConf.statMul end
        if diffConf.dropMul ~= 1 then parts[#parts + 1] = "掉落x" .. diffConf.dropMul end
        if diffConf.expMul ~= 1 then parts[#parts + 1] = "经验x" .. diffConf.expMul end
        if #parts > 0 then mulText = table.concat(parts, "  ") end
    end

    -- 动态构建 children，避免 nil 截断数组
    local popupChildren = {}

    -- 标题行 + 关闭
    popupChildren[#popupChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label {
                text = area.name,
                fontSize = Theme.fontSize.heading,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 10,
                children = {
                    UI.Label {
                        text = "区域 " .. (area.areaIndex or "?"),
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.accent,
                    },
                    UI.Label {
                        text = "X",
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textSecondary,
                        cursor = "pointer",
                        onClick = function(self)
                            selectedIdx = nil
                            Router.RebuildUI()
                        end,
                    },
                },
            },
        },
    }

    -- 描述
    popupChildren[#popupChildren + 1] = UI.Label {
        text = area.desc,
        fontSize = Theme.fontSize.body,
        fontColor = Theme.colors.textLight,
        width = "100%",
    }

    popupChildren[#popupChildren + 1] = Comp.BuildInkDivider()

    -- 奖励
    popupChildren[#popupChildren + 1] = Comp.BuildStatRow("可获奖励", rewardText)

    -- 难度选择
    local diffChildren = {
        UI.Label {
            text = "选择难度",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textDim,
        },
        BuildDifficultySelector(),
    }
    if mulText ~= "" then
        diffChildren[#diffChildren + 1] = UI.Label {
            text = mulText,
            fontSize = 11,
            fontColor = diffColor,
            textAlign = "center",
            width = "100%",
        }
    end
    popupChildren[#popupChildren + 1] = UI.Panel {
        width = "100%",
        gap = 4,
        children = diffChildren,
    }

    -- 未解锁提示
    if not isUnlocked then
        popupChildren[#popupChildren + 1] = UI.Panel {
            width = "100%",
            paddingTop = 4, paddingBottom = 4,
            backgroundColor = { 80, 40, 40, 60 },
            borderRadius = 4,
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = unlockText,
                    fontSize = Theme.fontSize.small,
                    fontColor = { 220, 120, 120 },
                },
            },
        }
    end

    -- 组队Boss入口（只在有Boss的已解锁区域显示）
    if isUnlocked then
        local enc = DataWorld.GetAreaEncounters(area.id)
        if enc and enc.boss then
            popupChildren[#popupChildren + 1] = Comp.BuildSecondaryButton(
                "组队Boss: " .. enc.boss.name, function()
                    Router.EnterState(Router.STATE_BOSS)
                end, { width = "100%" }
            )
        end
    end

    -- 开始/解锁按钮
    if isUnlocked then
        popupChildren[#popupChildren + 1] = Comp.BuildInkButton("开始游历", function()
            Router.EnterState(Router.STATE_EXPLORE, {
                areaId = area.id,
                difficulty = selectedDifficulty,
            })
        end, { width = "100%", fontSize = Theme.fontSize.body })
    else
        popupChildren[#popupChildren + 1] = Comp.BuildSecondaryButton("尚未解锁", function() end, {
            width = "100%",
            disabled = true,
        })
    end

    return UI.Panel {
        position = "absolute",
        bottom = 115,
        left = "6%",
        right = "6%",
        maxHeight = "55%",
        backgroundColor = { 25, 22, 18, 235 },
        borderRadius = Theme.radius.lg,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        overflow = "scroll",
        padding = Theme.spacing.md,
        gap = Theme.spacing.sm,
        children = popupChildren,
    }
end

-- ============================================================================
-- 凡界/仙界 Tab 切换器（仅 tier>=11 时显示）
-- ============================================================================
local function BuildTabSwitcher()
    local tabs = {
        { id = "mortal",   label = "凡界舆图" },
        { id = "immortal", label = "仙界秘境" },
    }
    local tabBtns = {}
    for _, t in ipairs(tabs) do
        local isActive = currentMapTab_ == t.id
        tabBtns[#tabBtns + 1] = UI.Panel {
            flex = 1,
            paddingVertical = 7,
            alignItems = "center",
            borderBottomWidth = isActive and 2 or 0,
            borderColor = isActive and { 167, 139, 250, 255 } or { 0, 0, 0, 0 },
            cursor = "pointer",
            onClick = function(self)
                currentMapTab_ = t.id
                selectedIdx = nil
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = t.label,
                    fontSize = Theme.fontSize.small,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and { 167, 139, 250, 255 } or { 160, 150, 140, 200 },
                },
            },
        }
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = { 18, 14, 10, 220 },
        borderBottomWidth = 1,
        borderColor = { 80, 60, 100, 120 },
        children = tabBtns,
    }
end

-- ============================================================================
-- 仙界秘境列表视图
-- ============================================================================
local IMMORTAL_PURPLE   = { 167, 139, 250, 255 }
local IMMORTAL_PURPLE_D = { 90, 70, 130, 200 }

local function BuildImmortalAreaRow(area, isUnlocked, playerTier)
    local enc = DataWorld.GetAreaEncounters(area.id)
    local bossName = enc and enc.boss and enc.boss.name or nil

    -- 解锁条件
    local realmData = DataRealms.GetAnyRealm(area.unlockTier)
    local realmName = realmData and realmData.name or ("第" .. area.unlockTier .. "阶")

    -- immortalDrop 描述
    local dropLine = ""
    if area.immortalDrop then
        local id = area.immortalDrop
        dropLine = id.name .. " " .. id.rate .. "% · "
            .. id.countMin .. (id.countMax > id.countMin and ("-" .. id.countMax) or "") .. "个/战"
    end

    local nameColor = isUnlocked and IMMORTAL_PURPLE or { 120, 110, 100, 160 }
    local borderCol = isUnlocked and { 100, 75, 160, 180 } or { 60, 55, 50, 120 }

    -- 操作按钮
    local actionBtn
    if isUnlocked then
        actionBtn = Comp.BuildInkButton("进入历练", function()
            Router.EnterState(Router.STATE_EXPLORE, {
                areaId = area.id,
                difficulty = selectedDifficulty,
            })
        end, { fontSize = Theme.fontSize.small })
    else
        actionBtn = UI.Panel {
            paddingHorizontal = 12, paddingVertical = 6,
            borderRadius = Theme.radius.sm,
            backgroundColor = { 40, 35, 50, 100 },
            children = {
                UI.Label {
                    text = "需" .. realmName .. "解锁",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = { 180, 100, 100, 200 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        paddingVertical = 10,
        paddingHorizontal = 12,
        gap = 10,
        backgroundColor = isUnlocked and { 40, 30, 60, 120 } or { 25, 20, 30, 80 },
        borderRadius = Theme.radius.md,
        borderColor = borderCol,
        borderWidth = 1,
        children = {
            -- 左：区域信息
            UI.Panel {
                flex = 1,
                gap = 3,
                children = {
                    -- 名称 + 区域编号
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label {
                                text = area.name,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = nameColor,
                            },
                            UI.Label {
                                text = "第" .. (area.areaIndex - 10) .. "层",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = { 130, 110, 170, 180 },
                            },
                        },
                    },
                    -- 描述
                    UI.Label {
                        text = area.desc,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = { 150, 140, 130, 180 },
                        numberOfLines = 1,
                    },
                    -- 掉落 + Boss
                    UI.Panel {
                        flexDirection = "row",
                        gap = 10,
                        children = {
                            dropLine ~= "" and UI.Label {
                                text = dropLine,
                                fontSize = Theme.fontSize.tiny,
                                fontColor = { 167, 139, 250, 200 },
                            } or nil,
                            bossName and UI.Label {
                                text = "Boss: " .. bossName,
                                fontSize = Theme.fontSize.tiny,
                                fontColor = { 220, 100, 80, 200 },
                            } or nil,
                        },
                    },
                },
            },
            -- 右：操作按钮
            actionBtn,
        },
    }
end

local function BuildImmortalTabView(p)
    local playerTier = p.tier or 1
    local playerSub  = p.sub or 1
    local immortalAreas = DataWorld.GetImmortalAreas()

    local rows = {}
    for _, area in ipairs(immortalAreas) do
        local isUnlocked = DataWorld.IsAreaUnlocked(area.id, playerTier, playerSub)
        rows[#rows + 1] = BuildImmortalAreaRow(area, isUnlocked, playerTier)
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        overflow = "scroll",
        backgroundColor = { 10, 8, 16, 255 },
        padding = 12,
        gap = 8,
        children = (function()
            local c = {
                -- 仙界标题
                UI.Panel {
                    width = "100%",
                    alignItems = "center",
                    paddingBottom = 6,
                    children = {
                        UI.Label {
                            text = "-- 仙 界 秘 境 --",
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            fontColor = { 167, 139, 250, 200 },
                            textAlign = "center",
                        },
                        UI.Label {
                            text = "飞升后可探索的仙人秘境，蕴含珍稀仙材",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = { 130, 110, 170, 160 },
                        },
                    },
                },
            }
            for _, row in ipairs(rows) do c[#c + 1] = row end
            return c
        end)(),
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 自动跳转：如果玩家正在挂机，延迟一帧进入探索页（避免 Build 中直接跳转导致黑屏）
    -- noAutoRedirect=true 时跳过（用户从探索页主动返回地图，不应被弹回）
    if GameExplore.IsAFKActive() and not (payload and payload.noAutoRedirect) then
        local areaId = GameExplore.GetSelectedArea() or DataWorld.AREAS[1].id
        local diff = GameExplore.GetSelectedDifficulty() or "normal"
        NVG.Register("world_map_auto_redirect", nil, function()
            NVG.Unregister("world_map_auto_redirect")
            Router.EnterState(Router.STATE_EXPLORE, {
                areaId = areaId,
                difficulty = diff,
            })
        end)
    end

    local playerTier = p.tier or 1
    local playerSub = p.sub or 1
    local areas = DataWorld.AREAS

    -- 地图标记
    local markerChildren = {}
    for _, point in ipairs(mapPoints) do
        local area = areas[point.areaIdx]
        if area then
            local isUnlocked = DataWorld.IsAreaUnlocked(area.id, playerTier, playerSub)
            local isSelected = selectedIdx == point.areaIdx
            markerChildren[#markerChildren + 1] = BuildLocationMarker(point, area, isSelected, isUnlocked)
        end
    end

    -- 详情浮层（如果有选中）
    local detailPopup = nil
    if selectedIdx and areas[selectedIdx] then
        local selArea = areas[selectedIdx]
        local isUnlocked = DataWorld.IsAreaUnlocked(selArea.id, playerTier, playerSub)
        detailPopup = BuildDetailPopup(selArea, isUnlocked, playerTier)
    end

    -- 地图标题标签
    markerChildren[#markerChildren + 1] = UI.Panel {
        position = "absolute",
        top = "2%",
        left = "0%",
        right = "0%",
        alignItems = "center",
        children = {
            UI.Label {
                text = "-- 天 下 舆 图 --",
                fontSize = Theme.fontSize.subtitle,
                fontWeight = "bold",
                fontColor = { 200, 168, 85, 180 },
                textAlign = "center",
            },
        },
    }

    -- 中间主视图：凡界地图 or 仙界秘境列表
    local midView
    if playerTier >= 11 and currentMapTab_ == "immortal" then
        midView = BuildImmortalTabView(p)
    else
        midView = UI.Panel {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            backgroundImage = Theme.images.bgMap,
            backgroundFit = "cover",
            children = (function()
                local c = {
                    -- 地图遮罩（轻微压暗以便图标可见）
                    UI.Panel {
                        position = "absolute",
                        top = 0, left = 0, right = 0, bottom = 0,
                        backgroundColor = { 10, 8, 6, 80 },
                    },
                }
                for _, m in ipairs(markerChildren) do
                    c[#c + 1] = m
                end
                return c
            end)(),
        }
    end

    -- 页面子元素
    local pageChildren = {
        -- 顶部状态栏
        Comp.BuildTopBar(p),
    }
    -- 飞升后显示凡界/仙界 Tab 切换器
    if playerTier >= 11 then
        pageChildren[#pageChildren + 1] = BuildTabSwitcher()
    end
    pageChildren[#pageChildren + 1] = midView
    pageChildren[#pageChildren + 1] = Comp.BuildChatTicker(function()
        Router.EnterState(Router.STATE_CHAT)
    end)
    pageChildren[#pageChildren + 1] = Comp.BuildBottomNav("map", Router.HandleNavigate)

    -- 详情弹窗放在页面根节点上层，避免被地图容器裁切
    if detailPopup then
        pageChildren[#pageChildren + 1] = detailPopup
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        children = pageChildren,
    }
end

return M
