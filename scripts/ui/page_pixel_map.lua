-- ui/page_pixel_map.lua — 像素地图测试页面
-- 纯色色块绘制，无需外部贴图
local UI = require("urhox-libs/UI")
local Comp = require("ui.components")

local M = {}

-- 瓦片配置
local TILE_PX    = 36                  -- 每格显示像素
local MAP_COLS   = 36                  -- 地图列数
local MAP_ROWS   = 18                  -- 地图行数

-- 地形颜色（RGBA）— 每种地形有 2-3 个色阶随机选用，增加层次感
local TERRAIN_COLORS = {
    grass = {
        { 92, 168, 64, 255 },
        { 80, 152, 56, 255 },
        { 100, 180, 72, 255 },
    },
    forest = {
        { 34, 110, 38, 255 },
        { 28, 96, 32, 255 },
        { 40, 120, 44, 255 },
    },
    water = {
        { 52, 108, 200, 255 },
        { 44, 96, 186, 255 },
        { 60, 120, 210, 255 },
    },
    mountain = {
        { 148, 128, 96, 255 },
        { 132, 112, 84, 255 },
        { 160, 140, 108, 255 },
    },
    road = {
        { 188, 168, 112, 255 },
        { 176, 156, 100, 255 },
    },
    city = {
        { 228, 188, 64, 255 },
        { 240, 200, 80, 255 },
    },
    sand = {
        { 208, 192, 136, 255 },
        { 196, 180, 124, 255 },
        { 216, 200, 148, 255 },
    },
    bridge = {
        { 160, 130, 80, 255 },
    },
}

--- 从色阶列表中随机选一个颜色
local function randomColor(terrainType)
    local list = TERRAIN_COLORS[terrainType] or TERRAIN_COLORS.grass
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

    -- 6) 主干道：横向穿过第 6 行
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

    -- 7) 桥梁：道路穿过河流的位置
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            if map[r][c] == "water" then
                -- 检查上下或左右是否有道路
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

    -- 8) 森林散布（只覆盖草地）
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            if map[r][c] == "grass" and math.random(100) < 22 then
                map[r][c] = "forest"
            end
        end
    end

    -- 9) 城池放置（三国经典城市布局）
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

    -- 地图网格面板（用 flexWrap 排列色块）
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

    -- 填充色块
    for r = 1, MAP_ROWS do
        for c = 1, MAP_COLS do
            local terrain = mapData[r][c]
            local color = randomColor(terrain)

            local tilePanel = UI.Panel {
                width           = TILE_PX,
                height          = TILE_PX,
                backgroundColor = color,
            }

            -- 城池显示名称
            local cityName = cityLookup[r .. "_" .. c]
            if cityName then
                tilePanel = UI.Panel {
                    width           = TILE_PX,
                    height          = TILE_PX,
                    backgroundColor = color,
                    alignItems      = "center",
                    justifyContent  = "center",
                    borderRadius    = 4,
                    borderWidth     = 2,
                    borderColor     = { 180, 140, 40, 255 },
                }
                tilePanel:AddChild(UI.Label {
                    text      = cityName,
                    fontSize  = 8,
                    fontColor = { 60, 20, 0, 255 },
                    fontWeight = "bold",
                })
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
        gap             = 20,
        backgroundColor = { 20, 15, 10, 220 },
        borderTop       = 1,
        borderColor     = { 120, 90, 40, 180 },
    }
    local legends = {
        { "草地",   { 92, 168, 64 } },
        { "森林",   { 34, 110, 38 } },
        { "水域",   { 52, 108, 200 } },
        { "山脉",   { 148, 128, 96 } },
        { "道路",   { 188, 168, 112 } },
        { "城池",   { 228, 188, 64 } },
        { "沙地",   { 208, 192, 136 } },
        { "桥梁",   { 160, 130, 80 } },
    }
    for _, lg in ipairs(legends) do
        local row = UI.Panel {
            flexDirection = "row",
            alignItems    = "center",
            gap           = 4,
        }
        row:AddChild(UI.Panel {
            width           = 10,
            height          = 10,
            borderRadius    = 2,
            backgroundColor = { lg[2][1], lg[2][2], lg[2][3], 255 },
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
