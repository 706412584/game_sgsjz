------------------------------------------------------------
-- ui/page_map.lua  —— 三国神将录 地图/章节页
-- 接入 data_maps 数据模块，支持 10 章 × 10 图 × 24 节点
-- 左侧章节导航 + 图列表 | 右侧节点网格
------------------------------------------------------------
local UI     = require("urhox-libs/UI")
local Theme  = require("ui.theme")
local Comp   = require("ui.components")
local Modal  = require("ui.modal_manager")
local DM     = require("data.data_maps")
local C      = Theme.colors
local S      = Theme.sizes

local M = {}

-- 内部状态
local pagePanel_
local chapterListContainer_     -- 左侧章节列表
local mapListContainer_         -- 中间图列表
local nodeContainer_            -- 右侧节点区域
local mapTitleLabel_
local mapPowerLabel_
local starLabel_
local bossLabel_
local currentChapter_   = 1
local currentMap_       = 1
local cachedState_              -- 缓存玩家状态
local onNodeClick_              -- 回调 function(mapId, nodeId, nodeType)
local onFormationClick_         -- 回调 function() 进入阵容编辑

------------------------------------------------------------
-- 节点类型颜色
------------------------------------------------------------
local NODE_BORDER_COLORS = {
    normal  = C.border,
    elite   = C.gold,
    boss    = C.red,
    event   = C.mp,
    chest   = C.morale,
}

------------------------------------------------------------
-- 构建节点卡片
------------------------------------------------------------
local function createNodeCard(mapId, nodeIdx, state)
    local tpl      = DM.NODE_TEMPLATE[nodeIdx]
    if not tpl then return nil end

    local nodeId   = tpl[1]
    local nodeType = tpl[2]
    local nodeName = tpl[3]
    local nodeKey  = mapId .. "_" .. nodeId
    local stars    = (state and state.nodeStars and state.nodeStars[nodeKey]) or 0

    -- 计算已解锁最大节点
    local maxNode = 0
    if state and state.nodeStars then
        for k, _ in pairs(state.nodeStars) do
            local m, n = k:match("^(%d+)_(%d+)$")
            if m and tonumber(m) == mapId then
                local nn = tonumber(n)
                if nn > maxNode then maxNode = nn end
            end
        end
    end

    -- 解锁判定：地图级锁定优先
    local mapLocked = not DM.IsMapUnlocked(mapId, state)
    local locked = mapLocked or (nodeId > (maxNode + 1))
    if nodeId == 1 and not mapLocked then locked = false end

    local typeName = DM.NODE_TYPE_NAMES[nodeType] or "普通"
    local staCost  = DM.NODE_STAMINA[nodeType] or 0
    local isCleared = stars > 0

    local borderColor = NODE_BORDER_COLORS[nodeType] or C.border

    -- 节点图标路径 (chest -> treasure icon)
    local iconType = nodeType == "chest" and "treasure" or nodeType
    local iconPath = "Textures/icons/icon_node_" .. iconType .. ".png"

    -- 节点战力
    local nodePower = DM.GetNodePower(mapId, nodeIdx)

    local children = {}

    -- 节点图标
    children[#children + 1] = UI.Panel {
        width           = 32,
        height          = 32,
        backgroundImage = iconPath,
        backgroundFit   = "contain",
        opacity         = locked and 0.3 or 1.0,
    }

    -- 节点名
    children[#children + 1] = UI.Label {
        text      = nodeName,
        fontSize  = Theme.fontSize.caption,
        fontColor = locked and C.textDim or C.text,
        marginTop = 1,
    }

    -- 星级 / 锁定 / 体力
    if isCleared then
        children[#children + 1] = Comp.StarBar({ stars = stars, size = 8 })
    elseif locked then
        children[#children + 1] = UI.Label {
            text      = "🔒",
            fontSize  = 9,
            fontColor = C.textDim,
        }
    elseif staCost > 0 then
        children[#children + 1] = UI.Label {
            text      = staCost .. "体",
            fontSize  = 8,
            fontColor = C.stamina,
        }
    end

    -- 节点战力（非事件/宝箱）
    if nodePower > 0 and not locked then
        children[#children + 1] = UI.Label {
            text      = Theme.FormatNumber(nodePower),
            fontSize  = 7,
            fontColor = C.goldDim,
        }
    end

    return UI.Panel {
        width           = 62,
        height          = 82,
        alignItems      = "center",
        justifyContent  = "center",
        backgroundColor = isCleared and { 35, 55, 50, 255 } or C.panel,
        borderRadius    = 6,
        borderColor     = isCleared and C.jade or borderColor,
        borderWidth     = isCleared and 2 or 1,
        padding         = 3,
        opacity         = locked and 0.5 or 1.0,
        transition      = "scale 0.15s easeOut",
        onClick = (not locked) and function()
            if onNodeClick_ then
                onNodeClick_(mapId, nodeId, nodeType)
            end
        end or nil,
        children = children,
    }
end

------------------------------------------------------------
-- 构建节点网格
------------------------------------------------------------
local function buildNodeGrid(mapId, state)
    local children = {}
    for i = 1, #DM.NODE_TEMPLATE do
        local card = createNodeCard(mapId, i, state)
        if card then
            children[#children + 1] = card
        end
    end

    return UI.Panel {
        flexDirection  = "row",
        flexWrap       = "wrap",
        gap            = 4,
        padding        = 6,
        justifyContent = "center",
        children       = children,
    }
end

------------------------------------------------------------
-- 右侧节点面板标题区
------------------------------------------------------------
local function buildNodeHeader(mapId, state)
    local mapData = DM.Get(mapId)
    if not mapData then return UI.Panel {} end

    -- 计算星级
    local totalStars = 24 * 3
    local earnedStars = 0
    if state and state.nodeStars then
        for k, v in pairs(state.nodeStars) do
            local m = k:match("^(%d+)_")
            if m and tonumber(m) == mapId then
                earnedStars = earnedStars + v
            end
        end
    end

    mapTitleLabel_ = UI.Label {
        text       = "第" .. mapId .. "图  " .. mapData.name,
        fontSize   = Theme.fontSize.subtitle,
        fontColor  = C.gold,
        fontWeight = "bold",
    }

    mapPowerLabel_ = UI.Label {
        text      = "战力 " .. Theme.FormatNumber(mapData.power),
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.textDim,
    }

    starLabel_ = UI.Label {
        text      = "★ " .. earnedStars .. "/" .. totalStars,
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.goldDim,
    }

    bossLabel_ = UI.Label {
        text      = "Boss: " .. mapData.boss,
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.red,
    }

    -- 编辑阵容按钮
    local formationBtn = Comp.SanButton({
        text     = "编辑阵容",
        variant  = "secondary",
        height   = S.btnSmHeight,
        fontSize = S.btnSmFontSize,
        paddingHorizontal = 10,
        onClick  = function()
            if onFormationClick_ then onFormationClick_() end
        end,
    })

    return UI.Panel {
        width             = "100%",
        flexDirection     = "column",
        gap               = 2,
        paddingHorizontal = 8,
        paddingVertical   = 6,
        backgroundColor   = { 30, 38, 55, 255 },
        children = {
            -- 第一行：图名 + 战力 + 阵容按钮
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "space-between",
                alignItems     = "center",
                children       = { mapTitleLabel_, UI.Panel {
                    flexDirection = "row", gap = 8, alignItems = "center",
                    children = { mapPowerLabel_, formationBtn },
                }},
            },
            -- 第二行：星级 + Boss
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "space-between",
                alignItems     = "center",
                children       = { starLabel_, bossLabel_ },
            },
        },
    }
end

------------------------------------------------------------
-- 中间：图列表（当前章节的10图）
------------------------------------------------------------
local function buildMapList(chapter, state)
    local maps = DM.GetChapterMaps(chapter)
    local children = {}

    for _, mapData in ipairs(maps) do
        local mapId    = mapData.id
        local isActive = (mapId == currentMap_)
        local mapLocked = not DM.IsMapUnlocked(mapId, state)
        local mapCleared = DM.IsMapCleared(mapId, state)

        -- 计算本图星数
        local mapStars = 0
        if state and state.nodeStars then
            for k, v in pairs(state.nodeStars) do
                local m = k:match("^(%d+)_")
                if m and tonumber(m) == mapId then
                    mapStars = mapStars + v
                end
            end
        end

        local rightLabel
        if mapLocked then
            rightLabel = UI.Label {
                text      = "未解锁",
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
            }
        elseif mapCleared then
            rightLabel = UI.Label {
                text      = "★" .. mapStars,
                fontSize  = Theme.fontSize.caption,
                fontColor = isActive and C.bg or C.gold,
            }
        elseif mapStars > 0 then
            rightLabel = UI.Label {
                text      = "★" .. mapStars,
                fontSize  = Theme.fontSize.caption,
                fontColor = isActive and C.bg or C.goldDim,
            }
        else
            rightLabel = UI.Panel {}
        end

        children[#children + 1] = UI.Panel {
            width             = "100%",
            height            = 40,
            flexDirection     = "row",
            alignItems        = "center",
            justifyContent    = "space-between",
            paddingHorizontal = 8,
            backgroundColor   = mapLocked and { 25, 25, 30, 255 } or (isActive and C.jade or C.panel),
            borderRadius      = 6,
            borderColor       = mapLocked and { 50, 50, 55, 255 } or (isActive and C.jade or C.border),
            borderWidth       = 1,
            marginBottom      = 3,
            opacity           = mapLocked and 0.5 or 1.0,
            transition        = "backgroundColor 0.15s easeOut",
            onClick = (not mapLocked) and function()
                currentMap_ = mapId
                M.Refresh(cachedState_)
            end or nil,
            children = {
                UI.Label {
                    text      = mapId .. ". " .. mapData.name,
                    fontSize  = Theme.fontSize.bodySmall,
                    fontColor = mapLocked and C.textDim or (isActive and C.bg or C.text),
                    fontWeight = isActive and "bold" or "normal",
                },
                rightLabel,
            },
        }
    end

    return UI.Panel {
        width         = "100%",
        flexDirection = "column",
        children      = children,
    }
end

------------------------------------------------------------
-- 左侧：章节导航（10章）
------------------------------------------------------------
local function buildChapterNav(state)
    local children = {}

    for _, theme in ipairs(DM.THEMES) do
        local ch       = theme.id
        local isActive = (ch == currentChapter_)
        local chLocked = not DM.IsChapterUnlocked(ch, state)

        children[#children + 1] = UI.Panel {
            width           = "100%",
            height          = 36,
            justifyContent  = "center",
            alignItems      = "center",
            backgroundColor = chLocked and { 25, 25, 30, 255 } or (isActive and C.jade or { 0, 0, 0, 0 }),
            borderRadius    = 6,
            marginBottom    = 2,
            paddingHorizontal = 4,
            opacity         = chLocked and 0.45 or 1.0,
            transition      = "backgroundColor 0.15s easeOut",
            onClick = (not chLocked) and function()
                currentChapter_ = ch
                -- 自动选中该章第一图
                currentMap_ = (ch - 1) * 10 + 1
                M.Refresh(cachedState_)
            end or nil,
            children = {
                UI.Label {
                    text      = theme.name,
                    fontSize  = Theme.fontSize.caption,
                    fontColor = chLocked and C.textDim or (isActive and C.bg or C.text),
                    fontWeight = isActive and "bold" or "normal",
                    textAlign = "center",
                },
            },
        }
    end

    return UI.Panel {
        width         = "100%",
        flexDirection = "column",
        padding       = 4,
        children      = children,
    }
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建地图页
---@param state table 玩家状态
---@param callbacks table { onNodeClick = function(mapId, nodeId, nodeType) }
function M.Create(state, callbacks)
    callbacks         = callbacks or {}
    onNodeClick_      = callbacks.onNodeClick
    onFormationClick_ = callbacks.onFormationClick
    cachedState_      = state

    -- 确保 chapter 和 map 同步
    currentChapter_ = DM.GetChapter(currentMap_)

    -- 左侧章节列表
    chapterListContainer_ = UI.Panel {
        width         = "100%",
        flexDirection = "column",
        children      = { buildChapterNav(state) },
    }

    -- 中间图列表
    mapListContainer_ = UI.Panel {
        width         = "100%",
        flexDirection = "column",
        children      = { buildMapList(currentChapter_, state) },
    }

    -- 右侧节点区域
    nodeContainer_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexDirection = "column",
        children = {
            buildNodeHeader(currentMap_, state),
            buildNodeGrid(currentMap_, state),
        },
    }

    -- 主布局：三列
    pagePanel_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexBasis     = 0,
        flexDirection = "row",
        children = {
            -- 左侧：章节导航
            UI.ScrollView {
                width    = 88,
                scrollY  = true,
                children = { chapterListContainer_ },
            },

            -- 分割线
            UI.Panel {
                width           = 1,
                height          = "100%",
                backgroundColor = C.border,
            },

            -- 中间：图列表
            UI.ScrollView {
                width    = 140,
                scrollY  = true,
                padding  = 4,
                children = { mapListContainer_ },
            },

            -- 分割线
            UI.Panel {
                width           = 1,
                height          = "100%",
                backgroundColor = C.border,
            },

            -- 右侧：节点网格
            UI.ScrollView {
                flexGrow = 1,
                flexBasis = 0,
                scrollY  = true,
                children = { nodeContainer_ },
            },
        },
    }

    return pagePanel_
end

--- 刷新地图页
function M.Refresh(state)
    cachedState_ = state or cachedState_

    -- 刷新章节导航
    if chapterListContainer_ then
        chapterListContainer_:ClearChildren()
        chapterListContainer_:AddChild(buildChapterNav(cachedState_))
    end

    -- 刷新图列表
    if mapListContainer_ then
        mapListContainer_:ClearChildren()
        mapListContainer_:AddChild(buildMapList(currentChapter_, cachedState_))
    end

    -- 刷新节点区域
    if nodeContainer_ then
        nodeContainer_:ClearChildren()
        nodeContainer_:AddChild(buildNodeHeader(currentMap_, cachedState_))
        nodeContainer_:AddChild(buildNodeGrid(currentMap_, cachedState_))
    end
end

--- 获取页面面板
function M.GetPanel()
    return pagePanel_
end

--- 设置当前图
function M.SetMap(mapId)
    currentMap_     = mapId
    currentChapter_ = DM.GetChapter(mapId)
end

--- 获取当前图
function M.GetCurrentMap()
    return currentMap_
end

return M
