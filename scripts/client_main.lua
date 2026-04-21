------------------------------------------------------------
-- client_main.lua  —— 三国神将录 客户端入口
-- C/S 架构：网络模式通过 GAME_ACTION 与服务端交互
-- 单机模式兼容：直接调用 State + BattleEngine
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
local State          = require("data.data_state")
local C = Theme.colors
local S = Theme.sizes

------------------------------------------------------------
-- 网络 / 单机模式判断
------------------------------------------------------------
local isNetworkMode_ = false
local ClientNet      = nil
local BattleEngine   = nil  -- 仅单机模式加载

local function initNetworkOrStandalone()
    if IsNetworkMode and IsNetworkMode() then
        isNetworkMode_ = true
        ClientNet = require("network.client_net")
        print("[客户端] 网络模式")
    else
        isNetworkMode_ = false
        BattleEngine = require("data.battle_engine")
        -- 单机模式: 加载或创建本地存档
        local saved = State.Load()
        State.state = saved or State.CreateDefaultState()
        print("[客户端] 单机模式, power=" .. (State.state.power or 0))
    end
end

------------------------------------------------------------
-- 获取当前状态的便捷函数
------------------------------------------------------------
local function gs()
    return State.state
end

------------------------------------------------------------
-- 页面管理
------------------------------------------------------------
local currentPage_    = ""
local previousPage_   = "city"
local contentContainer_
local overlayContainer_
local backButton_

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

    local showBack = (pageId ~= "city")
    if backButton_ then
        backButton_:SetStyle({ opacity = showBack and 1 or 0 })
        backButton_.disabled = not showBack
        if pageId == "formation" then
            backButton_.text = "← 返回"
        else
            backButton_.text = "← 返回主城"
        end
    end

    if pageId == "city" then
        contentContainer_:AddChild(CityPage.Create(gs(), {
            onBuildingClick = function(buildingId, buildingInfo)
                print("[主城] 点击建筑: " .. buildingId .. " - " .. buildingInfo.name)
                if buildingId == "battle" then
                    switchPage("map")
                elseif buildingId == "heroes" then
                    switchPage("heroes")
                elseif buildingId == "forge" then
                    Modal.Alert("铁匠铺", "锻造系统开发中，敬请期待！")
                elseif buildingId == "recruit" then
                    Modal.Confirm("招募", "消耗招募令 x1 进行一次招募？", function()
                        if isNetworkMode_ then
                            ClientNet.SendAction("recruit")
                        else
                            local ok, heroId, info = State.DoRecruit(gs())
                            if ok and info then
                                local desc = info.type == "hero"
                                    and ("恭喜获得武将: " .. info.name .. "！")
                                    or  (info.name .. " 碎片 x" .. info.count)
                                Modal.Alert("招募结果", desc)
                            else
                                Modal.Alert("提示", tostring(heroId))
                            end
                            HUD.Update(gs())
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
        contentContainer_:AddChild(MapPage.Create(gs(), {
            onNodeClick = function(mapId, nodeId, nodeType)
                if nodeType == "event" then
                    Modal.Alert("事件", "你发现了一个机关，获得铜钱 200！")
                    if isNetworkMode_ then
                        -- TODO: 事件节点由服务端处理
                    else
                        gs().copper = gs().copper + 200
                        HUD.Update(gs())
                    end
                    return
                end
                if nodeType == "chest" then
                    Modal.Alert("宝箱", "打开宝箱获得经验酒 x3！")
                    if not isNetworkMode_ then
                        gs().nodeStars[mapId .. "_" .. nodeId] = 3
                        MapPage.Refresh(gs())
                    end
                    return
                end

                local cost = DM.NODE_STAMINA[nodeType] or 5
                local nodePower = DM.GetNodePower(mapId, nodeId) or 0
                local confirmMsg = "消耗 " .. cost .. " 体力进入战斗\n"
                    .. "敌方预估战力: " .. Theme.FormatNumber(nodePower)
                Modal.Confirm("挑战确认", confirmMsg, function()
                    if (gs().stamina or 0) < cost then
                        Modal.Alert("提示", "体力不足！")
                        return
                    end

                    if isNetworkMode_ then
                        ClientNet.SendAction("battle", {
                            mapId = mapId, nodeId = nodeId, nodeType = nodeType,
                        })
                    else
                        -- 单机模式: 本地战斗
                        gs().stamina = gs().stamina - cost
                        HUD.Update(gs())
                        local log = BattleEngine.QuickBattle(gs(), mapId, nodeId, nodeType)
                        switchPage("battle")
                        contentContainer_:ClearChildren()
                        contentContainer_:AddChild(BattlePage.Create(log, {
                            onBattleEnd = function()
                                if log.result.win then
                                    State.ApplyBattleRewards(gs(), log)
                                end
                                HUD.Update(gs())
                                switchPage("map")
                            end,
                        }))
                    end
                end)
            end,
            onFormationClick = function()
                switchPage("formation")
            end,
        }))

    elseif pageId == "heroes" then
        contentContainer_:AddChild(HeroesPage.Create(gs(), {}))

    elseif pageId == "formation" then
        contentContainer_:AddChild(FormationPage.Create(gs(), {
            onSave = function()
                if isNetworkMode_ then
                    ClientNet.SendAction("set_lineup", {
                        formation = gs().lineup.formation,
                        front     = gs().lineup.front,
                        back      = gs().lineup.back,
                    })
                else
                    State.RecalcPower(gs())
                end
                HUD.Update(gs())
                print("[阵容] 阵容已保存: 前排=" .. #gs().lineup.front
                    .. " 后排=" .. #gs().lineup.back)
            end,
        }))
    end

    print("[三国神将录] 切换页面: " .. pageId)
end

------------------------------------------------------------
-- 网络事件处理
------------------------------------------------------------

--- 处理服务端即时事件
local function handleGameEvt(evtType, data)
    if evtType == "battle_result" then
        -- 收到战斗结果: 显示战斗回放
        local log = {
            rounds      = data.rounds or {},
            totalRounds = data.totalRounds or 0,
            result = {
                win         = data.win,
                stars       = data.stars,
                drops       = data.drops or {},
                damageStats = data.damageStats or {},
                healStats   = data.healStats or {},
                allyAlive   = data.allyAlive or 0,
                enemyAlive  = data.enemyAlive or 0,
            },
        }
        switchPage("battle")
        contentContainer_:ClearChildren()
        contentContainer_:AddChild(BattlePage.Create(log, {
            onBattleEnd = function()
                HUD.Update(gs())
                switchPage("map")
            end,
        }))

    elseif evtType == "recruit_result" then
        local info = data.info
        if data.success and info then
            local desc = info.type == "hero"
                and ("恭喜获得武将: " .. info.name .. "！")
                or  (info.name .. " 碎片 x" .. (info.count or 0))
            Modal.Alert("招募结果", desc)
        else
            Modal.Alert("提示", tostring(data.heroId or "招募失败"))
        end

    elseif evtType == "action_result" then
        if not data.success then
            Modal.Alert("提示", data.msg or "操作失败")
        end

    elseif evtType == "error" then
        Modal.Alert("错误", data.msg or "未知错误")
    end
end

--- 进入游戏（网络模式: GameInit 到达后调用）
local function enterGame()
    HUD.Update(gs())
    switchPage("city")

    if isNetworkMode_ then
        ClientNet.SendAction("game_start")
    end
    print("[三国神将录] 进入游戏")
end

------------------------------------------------------------
-- Start / Stop
------------------------------------------------------------

function Start()
    SampleStart()

    -- 判断网络/单机模式
    initNetworkOrStandalone()

    -- UI 初始化
    UI.Init({
        theme = Theme.uiTheme,
        fonts = {
            { family = "sans", weights = { normal = "Fonts/MiSans-Regular.ttf" } },
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 弹窗叠加层
    overlayContainer_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        width = "100%", height = "100%",
    }
    Modal.Init(overlayContainer_)

    -- 返回按钮
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
            HUD.Create(),
            contentContainer_,
            backButton_,
            overlayContainer_,
        },
    }
    UI.SetRoot(root)

    -- 状态变更 → 自动刷新 HUD
    State.onStateChanged = function()
        HUD.Update(gs())
        -- 刷新当前页面（地图页需更新星级）
        if currentPage_ == "map" then
            MapPage.Refresh(gs())
        end
    end

    -- 网络模式: 初始化网络并等 GameInit
    if isNetworkMode_ then
        ClientNet.Init()

        -- GameEvt 事件路由
        ClientNet.OnGameEvt(handleGameEvt)

        -- GameInit 到达后进入游戏
        ClientNet.OnGameInit(function()
            print("[客户端] GameInit 到达, 进入游戏")
            enterGame()
        end)

        -- 换服回调
        ClientNet.OnServerSwitch(function()
            print("[客户端] 换服完成, 刷新界面")
            enterGame()
        end)

        -- 断线回调
        ClientNet.OnDisconnect(function()
            Modal.Alert("断线提示", "与服务器断开连接，正在重连...")
        end)

        -- 重连回调
        ClientNet.OnReconnect(function()
            Modal.Alert("重连成功", "已恢复连接")
            HUD.Update(gs())
        end)

        -- 被踢回调
        ClientNet.OnKicked(function(reason)
            local msg = "已被踢出游戏"
            if reason == "duplicate_login" then
                msg = "账号在其他设备登录"
            end
            Modal.Alert("下线通知", msg)
        end)

        print("[客户端] 等待服务端 GameInit...")
    else
        -- 单机模式: 直接进入
        enterGame()
    end

    SampleInitMouseMode(MM_FREE)
    print("[三国神将录] 客户端启动完成 - C/S 架构")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    if currentPage_ == "battle" then
        BattlePage.Update(dt)
    end
end

function Stop()
    -- 单机模式: 退出时保存
    if not isNetworkMode_ and gs() then
        State.Save(gs())
    end
    UI.Shutdown()
end
