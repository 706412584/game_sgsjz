------------------------------------------------------------
-- ui/page_city.lua  —— 三国神将录 主城页面
-- 全屏背景 + 6 个浮动建筑按钮
-- 点击建筑触发对应功能页/弹窗
-- 使用运行时像素计算定位（Yoga absolute 不支持百分比字符串）
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 建筑配置（百分比值，运行时转换为像素）
-- pctX / pctY: 0.0~1.0，相对于可用区域左上角
------------------------------------------------------------
local BUILDINGS = {
    {
        id    = "battle",
        name  = "推图殿",
        desc  = "征战天下，推进地图",
        image = "Textures/buildings/building_battle.png",
        pctX  = 0.06,
        pctY  = 0.10,
    },
    {
        id    = "heroes",
        name  = "武将阁",
        desc  = "管理武将，强化阵容",
        image = "Textures/buildings/building_heroes.png",
        pctX  = 0.75,
        pctY  = 0.05,
    },
    {
        id    = "forge",
        name  = "铁匠铺",
        desc  = "打造装备，强化武器",
        image = "Textures/buildings/building_forge.png",
        pctX  = 0.04,
        pctY  = 0.52,
    },
    {
        id    = "recruit",
        name  = "招募亭",
        desc  = "招募新武将",
        image = "Textures/buildings/building_recruit.png",
        pctX  = 0.32,
        pctY  = 0.03,
    },
    {
        id    = "arena",
        name  = "演武场",
        desc  = "切磋比武，竞技排名",
        image = "Textures/buildings/building_arena.png",
        pctX  = 0.52,
        pctY  = 0.48,
    },
    {
        id    = "shop",
        name  = "商城",
        desc  = "购买道具与资源",
        image = "Textures/buildings/building_shop.png",
        pctX  = 0.82,
        pctY  = 0.50,
    },
}

------------------------------------------------------------
-- 回调引用
------------------------------------------------------------
local callbacks_ = {}
local cityPanel_ = nil

------------------------------------------------------------
-- 创建单个建筑 Widget（绝对定位，像素偏移）
------------------------------------------------------------
local function createBuildingWidget(bld, posX, posY)
    local buildingSize = 110

    -- 点击回调（整个建筑区域共用）
    local function onBuildingTap()
        if callbacks_.onBuildingClick then
            callbacks_.onBuildingClick(bld.id, bld)
        end
    end

    -- 建筑图片（可点击）
    local imgPanel = UI.Panel {
        width           = buildingSize,
        height          = buildingSize,
        backgroundImage = bld.image,
        backgroundFit   = "contain",
        cursor          = "pointer",
        onClick         = onBuildingTap,
    }

    -- 建筑名标签
    local nameLabel = UI.Button {
        text               = bld.name,
        fontSize           = 13,
        fontWeight         = "bold",
        textColor          = C.text,
        height             = 26,
        paddingHorizontal  = 14,
        backgroundColor    = { C.jade[1], C.jade[2], C.jade[3], 200 },
        hoverBackgroundColor = C.jadeHover,
        pressedBackgroundColor = C.jadePressed,
        borderRadius       = 13,
        transition         = "all 0.15s easeOut",
        onClick            = onBuildingTap,
    }

    -- 容器：绝对定位用数值像素
    local container = UI.Panel {
        position   = "absolute",
        left       = posX,
        top        = posY,
        width      = buildingSize + 20,
        alignItems = "center",
        gap        = 4,
        children = {
            imgPanel,
            nameLabel,
        },
    }

    return container
end

------------------------------------------------------------
-- 创建主城页面
------------------------------------------------------------
--- @param gameState table
--- @param opts table { onBuildingClick: function(buildingId, buildingInfo) }
function M.Create(gameState, opts)
    opts = opts or {}
    callbacks_ = opts

    -- 计算可用区域尺寸（去掉 HUD 高度）
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local contentH = screenH - S.hudHeight

    print(string.format("[主城] 屏幕: %.0fx%.0f, 内容区: %.0fx%.0f", screenW, screenH, screenW, contentH))

    -- 创建建筑 Widget 列表（百分比转像素）
    local buildingWidgets = {}
    for _, bld in ipairs(BUILDINGS) do
        local posX = math.floor(bld.pctX * screenW)
        local posY = math.floor(bld.pctY * contentH)
        buildingWidgets[#buildingWidgets + 1] = createBuildingWidget(bld, posX, posY)
    end

    -- 半透明遮罩（覆盖在背景之上、建筑之下）
    local overlay = UI.Panel {
        position        = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 15, 20, 35, 120 },  -- 深蓝半透明遮罩
        pointerEvents   = "none",
    }

    -- 将遮罩插入到建筑列表最前面（先渲染遮罩，再渲染建筑）
    table.insert(buildingWidgets, 1, overlay)

    -- 主城面板：全屏背景 + 遮罩 + 建筑悬浮
    cityPanel_ = UI.Panel {
        width           = "100%",
        flexGrow        = 1,
        backgroundImage = "Textures/backgrounds/bg_city.png",
        backgroundFit   = "cover",
        children        = buildingWidgets,
    }

    return cityPanel_
end

--- 获取建筑配置
function M.GetBuildings()
    return BUILDINGS
end

return M
