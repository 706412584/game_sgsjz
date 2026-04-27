-- ui/page_pixel_map.lua — 像素地图（TileMap2D 引擎加载 TMX）
local UI = require("urhox-libs/UI")
local Comp = require("ui.components")

local M = {}

-- TMX 地图配置
local TMX_PATH   = "未命名.tmx"
local MAP_COLS   = 30
local MAP_ROWS   = 20
local TILE_PX    = 24   -- 原始瓦片像素

-- tileset 行 → 地形名映射（9列/行）
local ROW_TERRAIN = {
    [0] = "grass",    -- r00: 草地
    [1] = "grass",    -- r01: 草地变体
    [2] = "forest",   -- r02: 森林
    [3] = "mountain", -- r03: 山脉
    [4] = "water",    -- r04: 水域边缘
    [5] = "water",    -- r05: 水域内部
    [6] = "city",     -- r06: 城墙
    [7] = "bridge",   -- r07: 城门/桥梁
    [8] = "road",     -- r08: 道路
    [9] = "sand",     -- r09: 沙地/农田
}

--- 地形中文名（调试用）
local TERRAIN_NAMES = {
    grass    = "草地",
    forest   = "森林",
    water    = "水域",
    mountain = "山脉",
    road     = "道路",
    city     = "城池",
    sand     = "沙地",
    bridge   = "桥梁",
}

--- 地形底色
local TERRAIN_BG = {
    grass    = { 92, 168, 64, 255 },
    forest   = { 54, 120, 48, 255 },
    water    = { 52, 108, 200, 255 },
    mountain = { 148, 128, 96, 255 },
    road     = { 160, 140, 90, 255 },
    city     = { 140, 130, 110, 255 },
    sand     = { 208, 192, 136, 255 },
    bridge   = { 60, 100, 180, 255 },
}

--- 图例色
local LEGEND_COLORS = {
    grass    = { 92, 168, 64 },
    forest   = { 34, 110, 38 },
    water    = { 52, 108, 200 },
    mountain = { 148, 128, 96 },
    road     = { 188, 168, 112 },
    city     = { 228, 188, 64 },
    sand     = { 208, 192, 136 },
    bridge   = { 160, 130, 80 },
}

------------------------------------------------------------------------
-- TMX CSV 解析：嵌入 TMX 数据，避免运行时 XML 解析
-- Tiled 翻转标记位
------------------------------------------------------------------------
local FLIP_H    = 0x80000000
local FLIP_V    = 0x40000000
local FLIP_D    = 0x20000000
local FLIP_MASK = FLIP_H | FLIP_V | FLIP_D
local FIRSTGID  = 1
local TILESET_COLS = 9

--- 从 tile GID 获取切片路径和地形
local function tileInfo(gid)
    if gid == 0 then
        return "Textures/tiles_sliced/tile_r00_c00.png", "grass"
    end
    local raw = gid & ~FLIP_MASK  -- 去掉翻转位
    local idx = raw - FIRSTGID
    if idx < 0 then idx = 0 end
    local row = math.floor(idx / TILESET_COLS)
    local col = idx % TILESET_COLS
    local path = string.format("Textures/tiles_sliced/tile_r%02d_c%02d.png", row, col)
    local terrain = ROW_TERRAIN[row] or "grass"
    return path, terrain
end

------------------------------------------------------------------------
-- TMX 地图数据（从 未命名.tmx CSV 提取）
------------------------------------------------------------------------
local TMX_DATA = {
    {14,14,14,14,14,25,25,14,14,14,14,21,14,14,21,21,14,14,21,14,14,14,14,15,5,6,5,6,5,6},
    {15,33,34,35,36,65,73,73,73,73,73,73,73,73,73,73,3221225549,5,5,6,5,6,14,15,14,5,6,15,14,15},
    {15,25,25,3,3,25,3,3,22,3,3,25,3,22,3,3,74,14,14,15,14,15,5,6,31,14,21,5,6,6},
    {15,57,57,57,57,57,57,57,57,57,57,57,57,57,57,57,65,57,57,57,57,57,57,57,57,57,57,57,57,56},
    {19,536870968,5,5,3758096432,38,38,38,38,38,38,38,38,38,38,39,74,31,5,5,13,14,22,15,31,14,5,5,5,23},
    {15,536870968,25,25,1610612774,45,1073741862,1073741862,65,73,73,73,73,73,73,73,1610612813,31,5,32,13,86,13,5,6,5,14,21,5,5},
    {15,536870968,5,5,1610612774,3758096422,4,4,74,25,4,4,4,25,3,25,4,4,5,13,13,13,5,14,15,14,14,15,5,5},
    {19,536870968,5,5,1610612774,3758096422,4,25,74,4,4,25,25,20,3,25,25,4,4,33,34,35,36,5,5,22,5,6,5,5},
    {19,536870968,5,5,1610612774,3758096422,25,25,77,81,73,73,73,73,73,73,73,73,73,65,24,5,5,5,25,15,15,15,22,5},
    {15,536870968,5,5,1610612774,3758096422,4,4,4,74,20,6,6,6,6,6,24,24,24,24,24,5,5,25,25,5,14,25,5,5},
    {15,536870968,25,25,1610612774,3758096422,59,57,57,65,57,57,57,57,25,6,24,5,5,5,5,5,5,14,5,5,22,5,15,5},
    {19,536870968,25,5,1610612774,3758096422,1610612793,63,63,63,63,63,63,2684354617,25,6,24,24,24,24,24,24,5,5,21,5,5,5,15,15},
    {19,536870968,5,5,1610612774,3758096422,1610612793,63,63,63,63,63,63,2684354617,6,25,6,25,6,6,6,24,5,5,5,5,25,5,5,5},
    {19,536870968,5,5,1610612774,3758096422,1610612793,63,63,63,63,63,63,2684354617,6,6,25,6,6,6,6,6,13,13,13,5,22,14,5,5},
    {19,536870968,5,5,1610612774,2684354598,56,56,56,65,57,57,57,56,13,13,13,20,13,13,13,13,13,13,13,5,14,14,25,5},
    {19,536870968,5,25,1610612774,68,69,70,25,10,12,3,13,13,10,13,25,13,13,13,13,5,5,13,22,5,5,14,5,5},
    {56,536870968,5,5,47,1073741862,48,12,10,10,12,25,13,20,13,13,13,13,13,13,1,13,5,5,5,5,5,22,5,5},
    {15,33,34,35,36,5,5,23,24,24,24,24,24,24,24,24,24,24,24,29,33,34,35,36,5,22,5,5,5,5},
    {19,6,6,6,6,6,25,23,23,23,24,5,5,5,6,5,5,5,5,5,15,15,5,5,5,5,25,15,15,5},
    {19,19,19,19,25,15,25,25,25,15,17,17,17,17,15,25,25,15,17,15,15,15,25,17,17,17,17,14,15,15},
}

local container_ = nil
local onBack_    = nil
local debugLabel_ = nil

--- 创建页面
---@param opts? {onBack: fun()}
function M.Create(opts)
    opts = opts or {}
    onBack_ = opts.onBack

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
    -- 右侧：调试信息 + 尺寸
    debugLabel_ = UI.Label {
        text      = "Tiled TMX 30x20",
        fontSize  = 11,
        fontColor = { 120, 230, 180, 220 },
    }
    local rightRow = UI.Panel {
        flexDirection = "row",
        alignItems    = "center",
        gap           = 16,
    }
    rightRow:AddChild(debugLabel_)
    rightRow:AddChild(UI.Label {
        text      = string.format("%dx%d", MAP_COLS, MAP_ROWS),
        fontSize  = 11,
        fontColor = { 180, 160, 120, 180 },
    })
    topBar:AddChild(rightRow)
    container_:AddChild(topBar)

    -- 地图滚动区域
    local DISPLAY_PX = 36  -- 每格显示像素（放大显示）
    local scrollWrap = UI.Panel {
        width          = "100%",
        flexGrow       = 1,
        overflow       = "scroll",
        alignItems     = "center",
        justifyContent = "center",
        paddingTop     = 8,
        paddingBottom  = 8,
    }

    -- 地图网格面板
    local mapPanel = UI.Panel {
        width           = MAP_COLS * DISPLAY_PX,
        height          = MAP_ROWS * DISPLAY_PX,
        overflow        = "hidden",
        backgroundColor = { 92, 168, 64, 255 },
    }

    -- 渲染 TMX 瓦片
    local OVERLAP = 1
    for r = 1, MAP_ROWS do
        local rowData = TMX_DATA[r]
        if not rowData then break end
        for c = 1, MAP_COLS do
            local gid = rowData[c] or 0
            local tilePath, terrain = tileInfo(gid)
            local bg = TERRAIN_BG[terrain] or TERRAIN_BG.grass

            -- 点击回调
            local tileR, tileC, tileTerrain, tileSrc = r, c, terrain, tilePath
            local tileClick = function()
                local name = TERRAIN_NAMES[tileTerrain] or tileTerrain
                local short = tileSrc:match("[^/]+$") or tileSrc
                local info = string.format("瓦片[%d,%d] %s GID=%d", tileR, tileC, name, gid)
                print(string.format("[PixelMap] 点击 %s | %s", info, tileSrc))
                if debugLabel_ then
                    debugLabel_:SetText(info .. "  " .. short)
                end
            end

            local tilePanel = UI.Panel {
                position        = "absolute",
                left            = (c - 1) * DISPLAY_PX,
                top             = (r - 1) * DISPLAY_PX,
                width           = DISPLAY_PX + OVERLAP,
                height          = DISPLAY_PX + OVERLAP,
                backgroundColor = bg,
                backgroundImage = tilePath,
                backgroundFit   = "cover",
                onClick         = tileClick,
            }
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
