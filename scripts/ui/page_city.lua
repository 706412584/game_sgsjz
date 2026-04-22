------------------------------------------------------------
-- ui/page_city.lua  —— 三国神将录 主城页面 (2.5D 等距风格)
-- 等距底图 + 独立建筑贴图(透明) + 绝对定位点击区域
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 建筑配置
-- pctX / pctY: 0.0~1.0，相对于内容区左上角（百分比定位）
-- 建筑贴图已替换为等距风格透明 PNG
------------------------------------------------------------
local BUILDINGS = {
    {
        id    = "battle",
        name  = "推图殿",
        desc  = "征战天下，推进地图",
        image = "Textures/buildings/bld_battle_iso.png",
        pctX  = 0.05,
        pctY  = 0.08,
    },
    {
        id    = "recruit",
        name  = "招募亭",
        desc  = "招募新武将",
        image = "Textures/buildings/bld_recruit_iso.png",
        pctX  = 0.28,
        pctY  = 0.02,
    },
    {
        id    = "heroes",
        name  = "武将阁",
        desc  = "管理武将，强化阵容",
        image = "Textures/buildings/bld_heroes_iso.png",
        pctX  = 0.72,
        pctY  = 0.02,
    },
    {
        id    = "forge",
        name  = "铁匠铺",
        desc  = "打造装备，强化武器",
        image = "Textures/buildings/bld_forge_iso.png",
        pctX  = 0.05,
        pctY  = 0.46,
    },
    {
        id    = "treasure",
        name  = "宝物阁",
        desc  = "收集宝物，增强武将",
        image = "Textures/buildings/bld_treasure_iso.png",
        pctX  = 0.30,
        pctY  = 0.42,
    },
    {
        id    = "arena",
        name  = "演武场",
        desc  = "切磋比武，竞技排名",
        image = "Textures/buildings/bld_arena_iso.png",
        pctX  = 0.54,
        pctY  = 0.40,
    },
    {
        id    = "shop",
        name  = "商城",
        desc  = "购买道具与资源",
        image = "Textures/buildings/bld_shop_iso.png",
        pctX  = 0.80,
        pctY  = 0.44,
    },
}

------------------------------------------------------------
-- 回调 & 状态引用
------------------------------------------------------------
local callbacks_ = {}
local cityPanel_ = nil

------------------------------------------------------------
-- 建筑尺寸
------------------------------------------------------------
local BUILDING_SIZE = 130
local BUILDING_CELL = BUILDING_SIZE + 20  -- 容器宽度（图片+间距）

------------------------------------------------------------
-- 创建单个建筑 Widget
------------------------------------------------------------
local function createBuildingWidget(bld, posX, posY)
    local function onTap()
        if callbacks_.onBuildingClick then
            callbacks_.onBuildingClick(bld.id, bld)
        end
    end

    -- 建筑图片
    local imgPanel = UI.Panel {
        width           = BUILDING_SIZE,
        height          = BUILDING_SIZE,
        backgroundImage = bld.image,
        backgroundFit   = "contain",
        cursor          = "pointer",
        onClick         = onTap,
    }

    -- 名称标签（建筑下方）
    local nameLabel = UI.Button {
        text                   = bld.name,
        fontSize               = 13,
        fontWeight              = "bold",
        textColor              = C.text,
        height                 = 24,
        paddingHorizontal      = 12,
        backgroundColor        = { 20, 28, 45, 200 },
        hoverBackgroundColor   = C.jadeHover,
        pressedBackgroundColor = C.jadePressed,
        borderRadius           = 12,
        borderColor            = { C.gold[1], C.gold[2], C.gold[3], 120 },
        borderWidth            = 1,
        transition             = "all 0.15s easeOut",
        onClick                = onTap,
    }

    return UI.Panel {
        position   = "absolute",
        left       = posX,
        top        = posY,
        width      = BUILDING_CELL,
        alignItems = "center",
        gap        = 3,
        children   = { imgPanel, nameLabel },
    }
end

------------------------------------------------------------
-- 左下角推图进度
------------------------------------------------------------
local progressLabel_ = nil

local function createProgressInfo(gameState)
    local DM = require("data.data_maps")
    local curMap = gameState.currentMap or 1
    local mapData = DM.MAPS[curMap]
    local mapName = mapData and mapData.name or ("第" .. curMap .. "图")

    local cleared = 0
    for nodeId = 1, 24 do
        local key = curMap .. "_" .. nodeId
        if gameState.nodeStars and gameState.nodeStars[key] then
            cleared = cleared + 1
        end
    end

    progressLabel_ = UI.Label {
        text      = mapName .. "  " .. cleared .. "/24",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.text,
    }

    return UI.Panel {
        position          = "absolute",
        bottom            = 8,
        left              = 10,
        flexDirection     = "row",
        alignItems        = "center",
        gap               = 6,
        paddingHorizontal = 10,
        paddingVertical   = 5,
        borderRadius      = 12,
        backgroundColor   = { 20, 28, 45, 210 },
        borderColor       = C.border,
        borderWidth       = 1,
        cursor            = "pointer",
        onClick = function()
            if callbacks_.onBuildingClick then
                callbacks_.onBuildingClick("battle", BUILDINGS[1])
            end
        end,
        children = {
            UI.Label {
                text       = "征战",
                fontSize   = Theme.fontSize.caption,
                fontColor  = C.gold,
                fontWeight = "bold",
            },
            progressLabel_,
        },
    }
end

------------------------------------------------------------
-- 右下角快捷信息
------------------------------------------------------------
local function createQuickInfo(gameState)
    local zhaomuling = gameState.zhaomuling or 0

    return UI.Panel {
        position          = "absolute",
        bottom            = 8,
        right             = 10,
        flexDirection     = "row",
        alignItems        = "center",
        gap               = 12,
        paddingHorizontal = 10,
        paddingVertical   = 5,
        borderRadius      = 12,
        backgroundColor   = { 20, 28, 45, 210 },
        borderColor       = C.border,
        borderWidth       = 1,
        children = {
            -- 招募令
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 4,
                cursor        = "pointer",
                onClick = function()
                    if callbacks_.onBuildingClick then
                        callbacks_.onBuildingClick("recruit", BUILDINGS[2])
                    end
                end,
                children = {
                    UI.Panel {
                        width           = 18,
                        height          = 18,
                        backgroundImage = "Textures/icons/icon_zhaomuling.png",
                        backgroundFit   = "contain",
                        pointerEvents   = "none",
                    },
                    UI.Label {
                        text      = tostring(zhaomuling),
                        fontSize  = Theme.fontSize.bodySmall,
                        fontColor = C.text,
                    },
                },
            },
            -- 阵容
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 4,
                cursor        = "pointer",
                onClick = function()
                    if callbacks_.onQuickAction then
                        callbacks_.onQuickAction("formation")
                    end
                end,
                children = {
                    UI.Label {
                        text       = "阵容",
                        fontSize   = Theme.fontSize.caption,
                        fontColor  = C.jade,
                        fontWeight = "bold",
                    },
                },
            },
        },
    }
end

------------------------------------------------------------
-- 创建主城页面
------------------------------------------------------------
---@param gameState table
---@param opts table { onBuildingClick, onQuickAction }
function M.Create(gameState, opts)
    opts = opts or {}
    callbacks_ = opts

    -- 屏幕 & 内容区尺寸
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local contentH = screenH - S.hudHeight

    print(string.format("[主城] 屏幕: %.0fx%.0f, 内容区: %.0fx%.0f", screenW, screenH, screenW, contentH))

    -- 建筑 Widget 列表
    local children = {}

    for _, bld in ipairs(BUILDINGS) do
        local posX = math.floor(bld.pctX * screenW)
        local posY = math.floor(bld.pctY * contentH)
        children[#children + 1] = createBuildingWidget(bld, posX, posY)
    end

    -- 底部浮层
    children[#children + 1] = createProgressInfo(gameState)
    children[#children + 1] = createQuickInfo(gameState)

    -- 主城面板：等距底图 + 建筑贴图
    cityPanel_ = UI.Panel {
        width           = "100%",
        flexGrow        = 1,
        backgroundImage = "Textures/backgrounds/bg_city_iso.png",
        backgroundFit   = "cover",
        children        = children,
    }

    return cityPanel_
end

--- 获取建筑配置
function M.GetBuildings()
    return BUILDINGS
end

return M
