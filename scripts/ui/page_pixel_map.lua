-- ui/page_pixel_map.lua — 像素地图（切片瓦片贴图渲染）
local UI = require("urhox-libs/UI")
local Comp = require("ui.components")

local M = {}

-- 瓦片配置
local TILE_PX    = 36                  -- 每格显示像素
local MAP_COLS   = 36                  -- 地图列数
local MAP_ROWS   = 18                  -- 地图行数

------------------------------------------------------------------------
-- 地形 → 瓦片贴图映射
-- 贴图来源: Textures/tiles_sliced/ (从原始 tileset 切片，24x24 透明背景)
-- 行映射: r00-r01=草地, r02=森林, r03=山脉, r04=水域,
--         r05=农田, r06=城池, r07=桥梁, r08=道路, r09=沙地
------------------------------------------------------------------------
local function slicedTiles(row, count)
    count = count or 9
    local t = {}
    for c = 0, count - 1 do
        t[#t + 1] = string.format("Textures/tiles_sliced/tile_r%02d_c%02d.png", row, c)
    end
    return t
end

local TERRAIN_TILES = {
    grass    = slicedTiles(0, 9),   -- r00: 浅草 9 变体
    -- r01 也是草地变体，合并进 grass
    forest   = slicedTiles(2, 9),   -- r02: 森林
    mountain = slicedTiles(3, 9),   -- r03: 山脉
    water    = slicedTiles(4, 9),   -- r04: 水域
    farmland = slicedTiles(5, 5),   -- r05 c00-c04: 纯农田（c05-c08 是南岸水域，归 autotile）
    city     = slicedTiles(6, 9),   -- r06: 城池
    bridge   = slicedTiles(7, 9),   -- r07: 桥梁
    road     = slicedTiles(8, 9),   -- r08: 道路
    sand     = slicedTiles(9, 9),   -- r09: 沙地
}
-- 将 r01 草地变体也加入 grass 列表
for _, v in ipairs(slicedTiles(1, 9)) do
    TERRAIN_TILES.grass[#TERRAIN_TILES.grass + 1] = v
end

--- 地形底色（切片贴图有透明区域，需底色衬托）
local TERRAIN_BG = {
    grass    = { 92, 168, 64, 255 },
    forest   = { 54, 120, 48, 255 },
    water    = { 52, 108, 200, 255 },
    mountain = { 148, 128, 96, 255 },
    road     = { 160, 140, 90, 255 },
    city     = { 140, 130, 110, 255 },
    sand     = { 208, 192, 136, 255 },
    bridge   = { 60, 100, 180, 255 },
    farmland = { 100, 150, 60, 255 },
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

------------------------------------------------------------------------
-- 水域 Autotile —— 根据四邻地形选择正确的边缘/角/中心瓦片
------------------------------------------------------------------------
local function wt(row, col)
    return string.format("Textures/tiles_sliced/tile_r%02d_c%02d.png", row, col)
end

--- 水域瓦片按边缘模式分组
--- key = 哪些方向有陆地邻居
local WATER_AUTO = {
    center     = { wt(4,6), wt(4,8) },                     -- 四周都是水 → 中心
    north      = { wt(4,0), wt(4,1), wt(4,4) },            -- 上方陆地 → 北岸
    south      = { wt(5,6), wt(5,7), wt(5,8) },            -- 下方陆地 → 南岸
    east       = { wt(4,5) },                               -- 右方陆地 → 东岸
    west       = { wt(4,7) },                               -- 左方陆地 → 西岸
    north_east = { wt(4,2) },                               -- 右上陆地 → 东北角
    north_west = { wt(4,3) },                               -- 左上陆地 → 西北角
    south_west = { wt(5,5) },                               -- 左下陆地 → 西南角
    south_east = { wt(4,5) },                               -- 右下陆地 → 东南角（复用东岸）
}

--- 判断地形是否属于水域（水域和桥梁在 autotile 邻居检测中视为同类）
local function isWaterLike(terrain)
    return terrain == "water" or terrain == "bridge"
end

--- 根据四邻地形选择水域瓦片
---@param mapData table 地图二维数组
---@param r number 行号
---@param c number 列号
---@return string 瓦片路径
local function selectWaterTile(mapData, r, c)
    local rows, cols = #mapData, #mapData[1]

    -- 检测四方向是否为陆地（地图边界视为水域，避免边缘产生假岸线）
    local nLand = false
    local sLand = false
    local eLand = false
    local wLand = false
    if r > 1    then nLand = not isWaterLike(mapData[r - 1][c]) end
    if r < rows then sLand = not isWaterLike(mapData[r + 1][c]) end
    if c < cols then eLand = not isWaterLike(mapData[r][c + 1]) end
    if c > 1    then wLand = not isWaterLike(mapData[r][c - 1]) end

    -- 统计陆地邻居数量
    local landCount = 0
    if nLand then landCount = landCount + 1 end
    if sLand then landCount = landCount + 1 end
    if eLand then landCount = landCount + 1 end
    if wLand then landCount = landCount + 1 end

    -- 匹配模式：0→中心，3+→被围（用中心），2→角/窄道，1→岸
    local key
    if landCount == 0 or landCount >= 3 then
        key = "center"
    elseif nLand and eLand then
        key = "north_east"
    elseif nLand and wLand then
        key = "north_west"
    elseif sLand and wLand then
        key = "south_west"
    elseif sLand and eLand then
        key = "south_east"
    elseif nLand and sLand then
        -- 南北夹缝（窄河横道），随机取南或北岸
        key = math.random(2) == 1 and "north" or "south"
    elseif eLand and wLand then
        -- 东西夹缝（窄河纵道），随机取东或西岸
        key = math.random(2) == 1 and "east" or "west"
    elseif nLand then key = "north"
    elseif sLand then key = "south"
    elseif eLand then key = "east"
    elseif wLand then key = "west"
    else
        key = "center"
    end

    local tiles = WATER_AUTO[key]
    return tiles[math.random(1, #tiles)]
end

------------------------------------------------------------------------
-- 城池多格布局 — 每座城占 3×3 格（墙+角+门）
------------------------------------------------------------------------
local CITY_LAYOUT = {
    nw = { wt(6, 4) },                             -- 左上角
    n  = { wt(6, 0), wt(6, 1), wt(6, 2), wt(6, 9) }, -- 北墙（水平墙段）
    ne = { wt(6, 4) },                             -- 右上角
    w  = { wt(6, 5) },                             -- 西墙（垂直墙段）
    c  = { wt(6, 7) },                             -- 城内（中心）
    e  = { wt(6, 6) },                             -- 东墙（垂直墙段）
    sw = { wt(6, 4) },                             -- 左下角
    s  = { wt(6, 8) },                             -- 南门（城门楼）
    se = { wt(6, 4) },                             -- 右下角
}

--- 3×3 偏移 → 布局位置键
local CITY_OFFSETS = {
    { -1, -1, "nw" }, { -1, 0, "n" }, { -1, 1, "ne" },
    {  0, -1, "w"  }, {  0, 0, "c" }, {  0, 1, "e"  },
    {  1, -1, "sw" }, {  1, 0, "s" }, {  1, 1, "se" },
}

------------------------------------------------------------------------
-- 道路 Autotile — 根据四邻地形选择正确的道路瓦片
------------------------------------------------------------------------
local ROAD_AUTO = {
    center     = { wt(8,0), wt(8,1), wt(8,2) },   -- 多方向连接 → 实心路面
    horizontal = { wt(8,0), wt(8,1) },             -- 东西走向
    vertical   = { wt(8,2), wt(8,7) },             -- 南北走向
    isolated   = { wt(8,8), wt(8,9) },             -- 孤立路块
}

--- 判断地形是否属于道路类（道路 autotile 邻居检测中视为同类）
local function isRoadLike(terrain)
    return terrain == "road" or terrain == "bridge" or terrain == "city"
end

--- 根据四邻地形选择道路瓦片
---@param mapData table 地图二维数组
---@param r number 行号
---@param c number 列号
---@return string 瓦片路径
local function selectRoadTile(mapData, r, c)
    local rows, cols = #mapData, #mapData[1]
    local nRoad = r > 1    and isRoadLike(mapData[r - 1][c])
    local sRoad = r < rows and isRoadLike(mapData[r + 1][c])
    local eRoad = c < cols and isRoadLike(mapData[r][c + 1])
    local wRoad = c > 1    and isRoadLike(mapData[r][c - 1])

    local count = 0
    if nRoad then count = count + 1 end
    if sRoad then count = count + 1 end
    if eRoad then count = count + 1 end
    if wRoad then count = count + 1 end

    local tiles
    if count == 0 then
        tiles = ROAD_AUTO.isolated
    elseif count >= 2 then
        tiles = ROAD_AUTO.center
    elseif nRoad or sRoad then
        tiles = ROAD_AUTO.vertical
    else
        tiles = ROAD_AUTO.horizontal
    end
    return tiles[math.random(1, #tiles)]
end

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

    -- 10) 城池放置（三国经典城市布局）——每城占 3×3 格
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
    local cityPosMap = {}  -- "r_c" → 布局位置 (nw/n/ne/w/c/e/sw/s/se)
    for _, ct in ipairs(cities) do
        for _, off in ipairs(CITY_OFFSETS) do
            local rr = ct.r + off[1]
            local cc = ct.c + off[2]
            if rr >= 1 and rr <= MAP_ROWS and cc >= 1 and cc <= MAP_COLS then
                map[rr][cc] = "city"
                cityPosMap[rr .. "_" .. cc] = off[3]
            end
        end
        -- 城门前方加一格道路连接
        local gateR = ct.r + 2
        if gateR >= 1 and gateR <= MAP_ROWS and map[gateR][ct.c] ~= "water" then
            map[gateR][ct.c] = "road"
        end
    end

    return map, cities, cityPosMap
end

local container_ = nil
local onBack_    = nil

--- 创建页面
---@param opts? {onBack: fun()}
function M.Create(opts)
    opts = opts or {}
    onBack_ = opts.onBack
    local mapData, cities, cityPosMap = generateMap()

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
            local tilePath
            if terrain == "water" then
                tilePath = selectWaterTile(mapData, r, c)
            elseif terrain == "road" then
                tilePath = selectRoadTile(mapData, r, c)
            elseif terrain == "city" then
                local pos = cityPosMap[r .. "_" .. c]
                if pos then
                    local tiles = CITY_LAYOUT[pos]
                    tilePath = tiles[math.random(1, #tiles)]
                else
                    tilePath = randomTile("city")
                end
            else
                tilePath = randomTile(terrain)
            end
            local cityName = cityLookup[r .. "_" .. c]

            local bg = TERRAIN_BG[terrain] or TERRAIN_BG.grass
            local tilePanel
            if cityName then
                -- 城池：贴图 + 名称标签 + 边框
                tilePanel = UI.Panel {
                    width           = TILE_PX,
                    height          = TILE_PX,
                    backgroundColor = bg,
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
                -- 普通地形：底色 + 切片贴图
                tilePanel = UI.Panel {
                    width           = TILE_PX,
                    height          = TILE_PX,
                    backgroundColor = bg,
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
