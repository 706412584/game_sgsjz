------------------------------------------------------------
-- ui/page_city.lua  —— 三国神将录 主城页面 (2.5D 等距风格)
-- 等距底图 + 独立建筑贴图(透明) + cover 变换精确定位
--
-- 定位原理:
--   建筑中心点定义在原始底图像素坐标系 (1935×1080) 中，
--   运行时根据 backgroundFit="cover" 的缩放/裁剪变换
--   把底图坐标映射到屏幕坐标，建筑尺寸同步缩放。
--   不同屏幕尺寸下建筑始终对齐底图格子。
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 原始底图尺寸
------------------------------------------------------------
local IMG_W = 1935
local IMG_H = 1080

------------------------------------------------------------
-- 建筑基础尺寸（底图像素空间，约为格子宽度的 65%）
------------------------------------------------------------
local BASE_BLD_SIZE = 400

------------------------------------------------------------
-- 建筑配置
-- cx/cy: 建筑中心点在原始底图中的像素坐标
-- 通过观察底图石板路网格确定每个空地格子的中心
------------------------------------------------------------
local BUILDINGS = {
    {   -- 左上格子（樱花带与竹林之间的空地）
        id    = "battle",
        name  = "推图殿",
        desc  = "征战天下，推进地图",
        image = "Textures/buildings/bld_battle_iso.png",
        cx    = 1320,
        cy    = 620,
        scale = 1.35,
    },
    {   -- 中上格子（城中央大空地）
        id    = "recruit",
        name  = "招募亭",
        desc  = "招募新武将",
        image = "Textures/buildings/bld_recruit_iso.png",
        cx    = 1633,
        cy    = 971,
    },
    {   -- 右上格子（竹林左侧空地）
        id    = "heroes",
        name  = "武将阁",
        desc  = "管理武将，强化阵容",
        image = "Textures/buildings/bld_heroes_iso.png",
        cx    = 1156,
        cy    = 317,
    },
    {   -- 左中格子（池塘右上方空地）
        id    = "forge",
        name  = "铁匠铺",
        desc  = "打造装备，强化武器",
        image = "Textures/buildings/bld_forge_iso.png",
        cx    = 1091,
        cy    = 990,
    },
    {   -- 中心偏下格子（十字路口下方）
        id    = "treasure",
        name  = "宝物阁",
        desc  = "收集宝物，增强武将",
        image = "Textures/buildings/bld_treasure_iso.png",
        cx    = 665,
        cy    = 730,
    },
    {   -- 右中格子（稻田左侧空地）
        id    = "arena",
        name  = "演武场",
        desc  = "切磋比武，竞技排名",
        image = "Textures/buildings/bld_arena_iso.png",
        cx    = 1275,
        cy    = 1144,
    },
    {   -- 中心格子（十字路口附近）
        id    = "shop",
        name  = "商城",
        desc  = "购买道具与资源",
        image = "Textures/buildings/bld_shop_iso.png",
        cx    = 942,
        cy    = 519,
    },
    {   -- 右上格子（农田区域）
        id    = "tavern",
        name  = "酒馆",
        desc  = "以酒会友，武将升阶",
        image = "Textures/buildings/bld_tavern_iso.png",
        cx    = 1605,
        cy    = 397,
    },
}

------------------------------------------------------------
-- 回调 & 状态引用
------------------------------------------------------------
local callbacks_ = {}
local cityPanel_ = nil

-- fill 变换参数（供点击坐标反算使用）
local coverScale_ = 1
local cropX_ = 0
local cropY_ = 0
local scaleX_ = 1
local scaleY_ = 1

------------------------------------------------------------
-- 创建单个建筑 Widget（尺寸由外部传入，跟随 cover 缩放）
------------------------------------------------------------
local function createBuildingWidget(bld, posX, posY, bldSize)
    local function onTap()
        if callbacks_.onBuildingClick then
            callbacks_.onBuildingClick(bld.id, bld)
        end
    end

    local cellW = bldSize + 16

    -- 建筑图片
    local imgPanel = UI.Panel {
        width           = bldSize,
        height          = bldSize,
        backgroundImage = bld.image,
        backgroundFit   = "contain",
        cursor          = "pointer",
        onClick         = onTap,
    }

    -- 名称标签
    local fontSize = math.max(10, math.floor(bldSize * 0.12))
    local nameLabel = UI.Button {
        text                   = bld.name,
        fontSize               = fontSize,
        fontWeight              = "bold",
        textColor              = C.text,
        height                 = fontSize + 10,
        paddingHorizontal      = 10,
        backgroundColor        = { 20, 28, 45, 200 },
        hoverBackgroundColor   = C.jadeHover,
        pressedBackgroundColor = C.jadePressed,
        borderRadius           = math.floor((fontSize + 10) / 2),
        borderColor            = { C.gold[1], C.gold[2], C.gold[3], 120 },
        borderWidth            = 1,
        transition             = "all 0.15s easeOut",
        onClick                = onTap,
    }

    -- 文字叠加在建筑图片中下部（门口位置）
    local labelH = fontSize + 10
    local labelTop = math.floor(bldSize * 0.72)

    return UI.Panel {
        position   = "absolute",
        left       = posX,
        top        = posY,
        width      = cellW,
        height     = bldSize,
        alignItems = "center",
        children   = {
            imgPanel,
            UI.Panel {
                position = "absolute",
                top      = labelTop,
                left     = 0,
                width    = cellW,
                alignItems = "center",
                children = { nameLabel },
            },
        },
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

    -- 屏幕 & 内容区尺寸（面板实际大小）
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local panelW = screenW
    local panelH = screenH - S.hudHeight

    print(string.format("[主城] 面板: %.0fx%.0f", panelW, panelH))

    ----------------------------------------------------------------
    -- 计算 backgroundFit="fill" 的缩放变换
    -- fill: X/Y 各自拉伸填满面板，无裁剪无留白
    ----------------------------------------------------------------
    local scaleX = panelW / IMG_W
    local scaleY = panelH / IMG_H
    local coverScale = math.min(scaleX, scaleY)  -- 用于建筑尺寸缩放(取较小值保守)

    -- fill 模式: 无裁剪无留白
    local cropX = 0
    local cropY = 0

    -- 保存到模块变量，供点击日志反算使用
    coverScale_ = coverScale
    cropX_ = cropX
    cropY_ = cropY
    -- fill 模式额外保存独立缩放比
    scaleX_ = scaleX
    scaleY_ = scaleY

    -- 建筑尺寸跟随缩放
    local bldSize = math.floor(BASE_BLD_SIZE * coverScale)
    -- 限制最小/最大
    bldSize = math.max(60, math.min(bldSize, 320))
    local cellW = bldSize + 16

    print(string.format("[主城] coverScale=%.3f, crop=(%.0f,%.0f), bldSize=%d",
        coverScale, cropX, cropY, bldSize))

    -- 建筑 Widget 列表
    local children = {}

    for _, bld in ipairs(BUILDINGS) do
        -- 底图像素坐标 → 屏幕坐标
        -- fill 模式: X/Y 各自独立缩放
        local sx = bld.cx * scaleX
        local sy = bld.cy * scaleY

        -- 每个建筑可通过 scale 字段单独缩放
        local thisBldSize = bld.scale and math.floor(bldSize * bld.scale) or bldSize
        local thisCellW = thisBldSize + 16

        -- 居中对齐：容器左上角 = 中心点 - 容器半宽/半高
        local posX = math.floor(sx - thisCellW / 2)
        local posY = math.floor(sy - thisBldSize / 2)

        children[#children + 1] = createBuildingWidget(bld, posX, posY, thisBldSize)
    end

    -- 底部浮层
    children[#children + 1] = createProgressInfo(gameState)
    children[#children + 1] = createQuickInfo(gameState)

    -- 主城面板：等距底图 + 建筑贴图
    cityPanel_ = UI.Panel {
        width           = "100%",
        flexGrow        = 1,
        backgroundImage = "Textures/backgrounds/bg_city_iso.png",
        backgroundFit   = "fill",
        children        = children,
        -- 🔧 调试：点击空白处打印底图像素坐标（建筑有自己的onClick，不受影响）
        onClick = function(self, event)
            if not event then return end
            -- event.x/y 是屏幕坐标，需减去 HUD 高度得到面板内坐标
            local sx = event.x
            local sy = event.y - S.hudHeight
            -- 反算底图像素坐标: imgX = (screenX + cropX) / coverScale
            -- fill 模式: 用独立缩放比反算
            local imgX = math.floor(sx / scaleX_)
            local imgY = math.floor(sy / scaleY_)
            print(string.format(
                "[点击坐标] 屏幕=(%.0f,%.0f) 面板=(%.0f,%.0f) → 底图像素=(%d,%d)",
                event.x, event.y, sx, sy, imgX, imgY))
        end,
    }

    return cityPanel_
end

--- 获取建筑配置
function M.GetBuildings()
    return BUILDINGS
end

return M
