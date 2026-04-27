-- ui/page_pixel_map.lua — 像素地图测试页面
-- 使用 sprite_forge 切割的 tileset 瓦片贴图渲染
local UI = require("urhox-libs/UI")
local Comp = require("ui.components")

local M = {}

-- 瓦片配置
local TILE_PX    = 36                  -- 每格显示像素
local MAP_COLS   = 36                  -- 地图列数
local MAP_ROWS   = 18                  -- 地图行数

------------------------------------------------------------------------
-- 地形 → tileset 瓦片映射（sprite_forge 分析 + 目视识别）
-- 瓦片来源: spr_sanguo_map_tileset (16x16 grid)
-- 切片路径: Textures/tiles/tile_RR_CC.png (RR=行, CC=列)
------------------------------------------------------------------------
local TERRAIN_TILES = {
    grass = {
        "Textures/tiles/tile_00_00.png",   -- 纯绿草地
        "Textures/tiles/tile_00_05.png",   -- 纯绿草地变体
        "Textures/tiles/tile_00_10.png",   -- 纯绿草地变体
    },
    forest = {
        "Textures/tiles/tile_03_05.png",   -- 树木（深绿树冠）
        "Textures/tiles/tile_03_15.png",   -- 树木变体
        "Textures/tiles/tile_03_10.png",   -- 树木变体
    },
    water = {
        "Textures/tiles/tile_07_15.png",   -- 纯蓝水面
        "Textures/tiles/tile_08_15.png",   -- 纯蓝水面变体
    },
    mountain = {
        "Textures/tiles/tile_05_04.png",   -- 棕色岩石山地
        "Textures/tiles/tile_05_05.png",   -- 棕色岩石山地变体
    },
    road = {
        "Textures/tiles/tile_12_05.png",   -- 棕色道路
    },
    city = {
        "Textures/tiles/tile_10_05.png",   -- 灰色城墙/城垛
        "Textures/tiles/tile_10_13.png",   -- 城墙变体
    },
    sand = {
        "Textures/tiles/tile_15_05.png",   -- 黄色沙地
        "Textures/tiles/tile_15_10.png",   -- 沙地变体
    },
    bridge = {
        "Textures/tiles/tile_06_08.png",   -- 桥梁（棕色横跨蓝色）
    },
    farmland = {
        "Textures/tiles/tile_13_05.png",   -- 农田（绿色网格）
        "Textures/tiles/tile_13_10.png",   -- 农田变体
    },
}

--- 图例用的代表色（仅用于底部图例色块显示）
local LEGEND_COLORS = {
    grass    = { 92, 168, 64 },
    forest   = { 34, 110, 38 },
    water    = { 52, 108, 200 },
    mountain = { 148, 128, 96 },
    road     = { 188, 168, 112 },
    city     = { 228, 188, 64 },
    sand     = { 208, 192, 136 },
    bridge   = { 160, 130, 80 },
    farmland = { 100, 160, 60 },
}

--- 从瓦片列表中随机选一个贴图路径
local function randomTile(terrainType)
    local list = TERRAIN_TILES[terrainType] or TERRAIN_TILES.grass
    return list[math.random(1, #list)]
end

--- 地形生成 — 三国大地图风格
local function generateMap()
    math.randomseed(os.time())
    local map = {}
    for r = 1, MAP_ROWS do
        map[r] = {}
        for c = 1, MAP_COLS do
            map[r][c] = "grass"
        end
    end

    -- 1) 长江横河（第 10-11 行，蜿蜒）
    local riverCenter = 10
    for c = 1, MAP_COLS do
        local offset = math.floor(math.sin(c * 0.35) * 1.5 + 0.5)
        for dr = 0, 1 do
            local rr = riverCenter + offset + dr
            if rr >= 1 and rr <= MAP_ROWS then
                map[rr][c] = "water"
            end
        end
    end

    -- 2) 支流（纵向，约第 12 列，往下流）
    local branchCol = 12
    for r = 1, MAP_ROWS do
        local cc = branchCol + math.floor(math.sin(r * 0.6) * 1 + 0.5)
        if cc >= 1 and cc <= MAP_COLS then
            if r < riverCenter - 1 or r > riverCenter + 3 then
                if math.random(100) < 70 then
                    map[r][cc] = "water"
                end
            end
        end
    end

    -- 3) 北方山脉（第 1-3 行）
    for c = 1, MAP_COLS do
        for r = 1, 3 do
            if math.random(100) < 60 + (3 - r) * 12 then
                map[r][c] = "mountain"
            end
        end
    end

    -- 4) 南方零星山丘（第 14-16 行）
    for c = 1, MAP_COLS do
        for r = 14, 16 do
            if math.random(100) < 20 then
                map[r][c] = "mountain"
            end
        end
    end

    -- 5) 南方沙地（最底 2 行局部）
    for c = 1, MAP_COLS do
        for r = MAP_ROWS - 1, MAP_ROWS do
            if math.random(100) < 40 then
                map[r][c] = "sand"
            end
        end
    end

    -- 6) 农田（散布在草地上，河流南岸附近）
    for c = 1, MAP_COLS do
        for r = 12, 14 do
            if map[r][c] == "grass" and math.random(100) < 18 then
                map[r][c] = "farmland"
            end
        end
    end

    -- 7) 主干道：横向穿过第 6 行
    for c = 1, MAP_COLS do
        local rr = 6 + math.floor(math.sin(c * 0.25) * 0.8 + 0.5)
        if rr >= 1 and rr <= MAP_ROWS and map[rr][c] == "grass" then
            map[rr][c] = "road"
        end
    end
    -- 纵向道路穿过第 20 列
    for r = 1, MAP_ROWS do
        local cc = 20 + math.floor(math.sin(r * 0.4) * 0.8 + 0.5)
        if cc >= 1 and cc <= MAP_COLS and (map[r][cc] == "grass" or map[r][cc] == "road") then
            map[r][cc] = "road"
        end
    end

    -- 8) 桥梁：道路穿过河流的位置
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            if map[r][c] == "water" then
                local hasRoadNeighbor = false
                if r > 1 and map[r - 1][c] == "road" then hasRoadNeighbor = true end
                if r < MAP_ROWS and map[r + 1][c] == "road" then hasRoadNeighbor = true end
                if c > 1 and map[r][c - 1] == "road" then hasRoadNeighbor = true end
                if c < MAP_COLS and map[r][c + 1] == "road" then hasRoadNeighbor = true end
                if hasRoadNeighbor then
                    map[r][c] = "bridge"
                end
            end
        end
    end

    -- 9) 森林散布（只覆盖草地）
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            if map[r][c] == "grass" and math.random(100) < 22 then
                map[r][c] = "forest"
            end
        end
    end

    -- 10) 城池放置（三国经典城市布局）
    local cities = {
        { r = 3,  c = 8,  name = "邺城" },
        { r = 4,  c = 28, name = "许昌" },
        { r = 5,  c = 18, name = "洛阳" },
        { r = 7,  c = 6,  name = "汉中" },
        { r = 7,  c = 32, name = "寿春" },
        { r = 13, c = 8,  name = "成都" },
        { r = 13, c = 24, name = "建业" },
        { r = 15, c = 16, name = "长沙" },
    }
    for _, ct in ipairs(cities) do
        if ct.r >= 1 and ct.r <= MAP_ROWS and ct.c >= 1 and ct.c <= MAP_COLS then
            map[ct.r][ct.c] = "city"
        end
    end

    return map, cities
end

local container_ = nil
local onBack_    = nil

--- 创建页面
---@param opts? {onBack: fun()}
function M.Create(opts)
    opts = opts or {}
    onBack_ = opts.onBack
    local mapData, cities = generateMap()

    -- 全屏容器
    container_ = UI.Panel {
        id              = "pixel_map_page",
        width           = "100%",
        height          = "100%",
        backgroundColor = { 10, 10, 15, 255 },
        overflow        = "hidden",
    }

    -- 标题栏
    local topBar = UI.Panel {
        width             = "100%",
        height            = 44,
        flexDirection     = "row",
        alignItems        = "center",
        justifyContent    = "space-between",
        paddingHorizontal = 16,
        backgroundColor   = { 20, 15, 10, 220 },
        borderBottom      = 1,
        borderColor       = { 120, 90, 40, 180 },
    }
    local leftRow = UI.Panel {
        flexDirection = "row",
        alignItems    = "center",
        gap           = 12,
    }
    leftRow:AddChild(Comp.SanButton {
        text    = "返回",
        variant = "secondary",
        onClick = function()
            if onBack_ then onBack_() end
        end,
    })
    leftRow:AddChild(UI.Label {
        text       = "天下大势",
        fontSize   = 16,
        fontColor  = { 240, 220, 160, 255 },
        fontWeight = "bold",
    })
    topBar:AddChild(leftRow)
    topBar:AddChild(UI.Label {
        text      = string.format("%dx%d", MAP_COLS, MAP_ROWS),
        fontSize  = 11,
        fontColor = { 180, 160, 120, 180 },
    })
    container_:AddChild(topBar)

    -- 地图滚动区域
    local scrollWrap = UI.Panel {
        width          = "100%",
        flexGrow       = 1,
        overflow       = "scroll",
        alignItems     = "center",
        justifyContent = "center",
        paddingTop     = 8,
        paddingBottom  = 8,
    }

    -- 地图网格面板（用 flexWrap 排列瓦片）
    local mapPanel = UI.Panel {
        width         = MAP_COLS * TILE_PX,
        height        = MAP_ROWS * TILE_PX,
        flexWrap      = "wrap",
        flexDirection = "row",
    }

    -- 城市名称查找表
    local cityLookup = {}
    for _, ct in ipairs(cities) do
        cityLookup[ct.r .. "_" .. ct.c] = ct.name
    end

    -- 填充瓦片贴图
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            local terrain = mapData[r][c]
            local tilePath = randomTile(terrain)
            local cityName = cityLookup[r .. "_" .. c]

            local tilePanel
            if cityName then
                -- 城池：贴图 + 名称标签 + 边框
                tilePanel = UI.Panel {
                    width           = TILE_PX,
                    height          = TILE_PX,
                    backgroundImage = tilePath,
                    backgroundFit   = "cover",
                    alignItems      = "center",
                    justifyContent  = "center",
                    borderRadius    = 4,
                    borderWidth     = 2,
                    borderColor     = { 180, 140, 40, 255 },
                }
                tilePanel:AddChild(UI.Label {
                    text       = cityName,
                    fontSize   = 8,
                    fontColor  = { 255, 240, 180, 255 },
                    fontWeight = "bold",
                })
            else
                -- 普通地形：贴图
                tilePanel = UI.Panel {
                    width           = TILE_PX,
                    height          = TILE_PX,
                    backgroundImage = tilePath,
                    backgroundFit   = "cover",
                }
            end

            mapPanel:AddChild(tilePanel)
        end
    end

    scrollWrap:AddChild(mapPanel)
    container_:AddChild(scrollWrap)

    -- 底部图例
    local infoBar = UI.Panel {
        width           = "100%",
        height          = 32,
        flexDirection   = "row",
        alignItems      = "center",
        justifyContent  = "center",
        gap             = 16,
        backgroundColor = { 20, 15, 10, 220 },
        borderTop       = 1,
        borderColor     = { 120, 90, 40, 180 },
    }
    local legends = {
        { "草地",   "grass" },
        { "森林",   "forest" },
        { "水域",   "water" },
        { "山脉",   "mountain" },
        { "道路",   "road" },
        { "城池",   "city" },
        { "沙地",   "sand" },
        { "农田",   "farmland" },
        { "桥梁",   "bridge" },
    }
    for _, lg in ipairs(legends) do
        local clr = LEGEND_COLORS[lg[2]]
        local row = UI.Panel {
            flexDirection = "row",
            alignItems    = "center",
            gap           = 4,
        }
        row:AddChild(UI.Panel {
            width           = 10,
            height          = 10,
            borderRadius    = 2,
            backgroundColor = { clr[1], clr[2], clr[3], 255 },
        })
        row:AddChild(UI.Label {
            text      = lg[1],
            fontSize  = 10,
            fontColor = { 200, 190, 160, 200 },
        })
        infoBar:AddChild(row)
    end
    container_:AddChild(infoBar)

    return container_
end

return M
