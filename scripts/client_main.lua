------------------------------------------------------------
-- client_main.lua  —— 三国神将录 客户端入口
-- 主城界面 → 建筑功能 → 弹窗系统
-- Phase 2：接入真实战斗引擎 + 阵容编辑
------------------------------------------------------------
require "LuaScripts/Utilities/Sample"

local UI     = require("urhox-libs/UI")
local Theme  = require("ui.theme")
local Comp   = require("ui.components")
local HUD    = require("ui.hud")
local CityPage      = require("ui.page_city")
local MapPage       = require("ui.page_map")
local HeroesPage    = require("ui.page_heroes")
local BattlePage    = require("ui.page_battle")
local FormationPage = require("ui.page_formation")
local Modal         = require("ui.modal_manager")
local DM            = require("data.data_maps")
local DH            = require("data.data_heroes")
local BattleEngine  = require("data.battle_engine")
local C = Theme.colors
local S = Theme.sizes

------------------------------------------------------------
-- 模拟玩家状态（Phase 1 用，后续由 data_state.lua 替代）
------------------------------------------------------------
local gameState = {
    power       = 2450,
    copper      = 5000,
    yuanbao     = 100,
    stamina     = 115,
    staminaMax  = 120,
    currentMap  = 1,
    nodeStars   = {},
    clearedMaps = {},
    heroes = {
        lvbu         = { level = 10, evolve = 0, exp = 0 },
        guanyu       = { level = 8,  evolve = 0, exp = 0 },
        zhangfei     = { level = 7,  evolve = 0, exp = 0 },
        zhaoyun      = { level = 9,  evolve = 0, exp = 0 },
        zhugeliang   = { level = 6,  evolve = 0, exp = 0 },
        sunshangxiang = { level = 7, evolve = 0, exp = 0 },
        diaochan     = { level = 5,  evolve = 0, exp = 0 },
        daqiao       = { level = 4,  evolve = 0, exp = 0 },
        caiwenji     = { level = 5,  evolve = 0, exp = 0 },
        zhenji       = { level = 6,  evolve = 0, exp = 0 },
        huangzhong   = { level = 8,  evolve = 0, exp = 0 },
        xiaohoudun   = { level = 7,  evolve = 0, exp = 0 },
    },
    lineup = {
        formation = "feng_shi",
        front = { "lvbu", "zhangfei" },
        back  = { "zhugeliang", "guanyu", "zhaoyun" },
    },
    inventory  = {},
    jianghun   = 0,
    zhaomuling = 0,
}

------------------------------------------------------------
-- 页面管理
------------------------------------------------------------
local currentPage_ = ""
local previousPage_ = "city"  -- 用于返回
local contentContainer_
local overlayContainer_ -- 弹窗叠加层
local backButton_       -- 返回按钮

------------------------------------------------------------
-- 切换页面
------------------------------------------------------------
local function switchPage(pageId)
    if currentPage_ == pageId then return end
    previousPage_ = currentPage_
    currentPage_ = pageId

    if not contentContainer_ then return end
    contentContainer_:ClearChildren()
    Modal.CloseAll()

    -- 返回按钮的显隐和文字
    local showBack = (pageId ~= "city")
    if backButton_ then
        backButton_:SetStyle({ opacity = showBack and 1 or 0 })
        backButton_.disabled = not showBack
        -- 根据上下文显示不同返回文字
        if pageId == "formation" then
            backButton_.text = "← 返回"
        else
            backButton_.text = "← 返回主城"
        end
    end

    if pageId == "city" then
        contentContainer_:AddChild(CityPage.Create(gameState, {
            onBuildingClick = function(buildingId, buildingInfo)
                print("[主城] 点击建筑: " .. buildingId .. " - " .. buildingInfo.name)
                if buildingId == "battle" then
                    switchPage("map")
                elseif buildingId == "heroes" then
                    switchPage("heroes")
                elseif buildingId == "forge" then
                    Modal.Alert("铁匠铺", "锻造系统开发中，敬请期待！")
                elseif buildingId == "recruit" then
                    Modal.Confirm("招募", "消耗招募令 ×1 进行一次招募？", function()
                        if gameState.zhaomuling > 0 then
                            gameState.zhaomuling = gameState.zhaomuling - 1
                            Modal.Alert("招募结果", "恭喜获得武将碎片 ×10！")
                        else
                            Modal.Alert("提示", "招募令不足！")
                        end
                    end)
                elseif buildingId == "arena" then
                    Modal.Alert("演武场", "竞技系统开发中，敬请期待！")
                elseif buildingId == "shop" then
                    Modal.Alert("商城", "商城系统开发中，敬请期待！")
                end
            end,
        }))

    elseif pageId == "map" then
        contentContainer_:AddChild(MapPage.Create(gameState, {
            onNodeClick = function(mapId, nodeId, nodeType)
                if nodeType == "event" then
                    Modal.Alert("事件", "你发现了一个机关，获得铜钱 200！")
                    gameState.copper = gameState.copper + 200
                    HUD.Update(gameState)
                    return
                end
                if nodeType == "chest" then
                    Modal.Alert("宝箱", "打开宝箱获得经验酒 ×3！")
                    gameState.nodeStars[mapId .. "_" .. nodeId] = 3
                    MapPage.Refresh(gameState)
                    return
                end
                -- 从数据表获取体力消耗
                local cost = DM.NODE_STAMINA[nodeType] or 5
                -- 显示战前信息（敌方战力预估）
                local nodePower = DM.GetNodePower(mapId, nodeId) or 0
                local confirmMsg = "消耗 " .. cost .. " 体力进入战斗\n"
                    .. "敌方预估战力: " .. Theme.FormatNumber(nodePower)
                Modal.Confirm(
                    "挑战确认",
                    confirmMsg,
                    function()
                        if gameState.stamina < cost then
                            Modal.Alert("提示", "体力不足！")
                            return
                        end
                        gameState.stamina = gameState.stamina - cost
                        HUD.Update(gameState)

                        -- 使用真实战斗引擎
                        local log = BattleEngine.QuickBattle(gameState, mapId, nodeId, nodeType)
                        print("[战斗引擎] 完成 map=" .. mapId .. " node=" .. nodeId
                            .. " 回合=" .. log.totalRounds
                            .. " 结果=" .. (log.result.win and "胜利" or "失败"))

                        switchPage("battle")
                        contentContainer_:ClearChildren()
                        contentContainer_:AddChild(BattlePage.Create(log, {
                            onBattleEnd = function()
                                if log.result.win then
                                    local key = mapId .. "_" .. nodeId
                                    local old = gameState.nodeStars[key] or 0
                                    gameState.nodeStars[key] = math.max(old, log.result.stars)
                                    gameState.copper = gameState.copper + (log.result.drops["铜钱"] or 0)
                                    gameState.power  = gameState.power + math.random(10, 50)
                                end
                                HUD.Update(gameState)
                                switchPage("map")
                            end,
                        }))
                    end
                )
            end,
            onFormationClick = function()
                switchPage("formation")
            end,
        }))

    elseif pageId == "heroes" then
        contentContainer_:AddChild(HeroesPage.Create(gameState, {}))

    elseif pageId == "formation" then
        contentContainer_:AddChild(FormationPage.Create(gameState, {
            onSave = function()
                -- 阵容保存后更新战力
                HUD.Update(gameState)
                print("[阵容] 阵容已保存: 前排=" .. #gameState.lineup.front
                    .. " 后排=" .. #gameState.lineup.back)
            end,
        }))

    end

    print("[三国神将录] 切换页面: " .. pageId)
end

------------------------------------------------------------
-- Start / Stop
------------------------------------------------------------

function Start()
    SampleStart()

    -- 初始化 UI 系统
    UI.Init({
        theme = Theme.uiTheme,
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } },
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 弹窗叠加层（覆盖在所有内容之上）
    overlayContainer_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        width  = "100%",
        height = "100%",
    }

    -- 初始化弹窗管理器
    Modal.Init(overlayContainer_)

    -- 返回按钮（左上角，叠加层下方）
    backButton_ = UI.Button {
        text               = "← 返回主城",
        position           = "absolute",
        top                = 52,
        left               = 8,
        height             = 32,
        paddingHorizontal  = 12,
        fontSize           = 12,
        fontWeight         = "bold",
        textColor          = C.text,
        backgroundImage    = "Textures/ui/btn_secondary.png",
        backgroundFit      = "sliced",
        backgroundSlice    = { top = 10, right = 10, bottom = 10, left = 10 },
        backgroundColor    = { 0, 0, 0, 0 },
        hoverBackgroundColor = { 255, 255, 255, 30 },
        pressedBackgroundColor = { 0, 0, 0, 40 },
        borderRadius       = 6,
        opacity            = 0,
        disabled           = true,
        transition         = "opacity 0.2s easeOut",
        onClick = function()
            -- 从阵容页返回到之前的页面(通常是map或heroes)
            if currentPage_ == "formation" then
                local backTo = previousPage_
                if backTo == "" or backTo == "formation" then backTo = "city" end
                switchPage(backTo)
            else
                switchPage("city")
            end
        end,
    }

    -- 内容区
    contentContainer_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexBasis     = 0,
        flexDirection = "column",
        overflow      = "hidden",
    }

    -- 主布局
    local root = UI.SafeAreaView {
        width           = "100%",
        height          = "100%",
        flexDirection   = "column",
        backgroundColor = C.bg,
        children = {
            -- HUD 顶栏
            HUD.Create(),

            -- 内容区
            contentContainer_,

            -- 返回按钮（绝对定位在 HUD 下方）
            backButton_,

            -- 弹窗叠加层（最顶层）
            overlayContainer_,
        },
    }

    UI.SetRoot(root)

    -- 初始化 HUD 数值
    HUD.Update(gameState)

    -- 默认显示主城
    switchPage("city")

    -- 设置鼠标模式
    SampleInitMouseMode(MM_FREE)

    print("[三国神将录] 客户端启动完成 - Phase 2 战斗引擎")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 更新战斗回放
    if currentPage_ == "battle" then
        BattlePage.Update(dt)
    end
end

function Stop()
    UI.Shutdown()
end
