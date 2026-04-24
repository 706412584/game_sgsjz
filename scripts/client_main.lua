-- client_main.lua — 三国神将录 客户端入口 (C/S + 单机兼容)
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
local RecruitPage   = require("ui.page_recruit")
local ShopPage      = require("ui.page_shop")
local EquipPage     = require("ui.page_equip")
local TreasurePage  = require("ui.page_treasure")
local ShopData      = require("data.data_shop")
local TS            = require("data.treasure_state")
local Modal         = require("ui.modal_manager")
local StartPage     = require("ui.page_start")
local DebugLog      = require("ui.debug_log")
local ServerUI      = require("ui.page_server")
local DM            = require("data.data_maps")
local DH            = require("data.data_heroes")
local State          = require("data.data_state")
local C = Theme.colors
local S = Theme.sizes

-- 网络 / 单机
local isNetworkMode_ = false
local ClientNet      = nil
local BattleEngine   = nil
local gameInitReady_   = false
local serverSelected_  = false

local function initNetworkOrStandalone()
    if IsNetworkMode and IsNetworkMode() then
        isNetworkMode_ = true
        ClientNet = require("network.client_net")
        print("[客户端] 网络模式")
    else
        isNetworkMode_ = false
        BattleEngine = require("data.battle_engine")
        local saved = State.Load()
        State.state = saved or State.CreateDefaultState()
        print("[客户端] 单机模式, power=" .. (State.state.power or 0))
    end
end

local function gs() return State.state end

-- 页面管理
local currentPage_    = ""
local previousPage_   = "city"
local contentContainer_
local overlayContainer_

-- 切换页面
local function switchPage(pageId)
    if currentPage_ == pageId then return end
    previousPage_ = currentPage_
    currentPage_ = pageId

    if not contentContainer_ then return end
    contentContainer_:ClearChildren()
    Modal.CloseAll()

    -- 非主城页面：顶部插入返回按钮行
    if pageId ~= "city" then
        local backText = (pageId == "formation") and "返回" or "返回主城"
        local backBar = UI.Panel {
            width          = "100%",
            flexDirection  = "row",
            justifyContent = "flex-start",
            paddingLeft    = 15,
            paddingTop     = 6,
            paddingBottom  = 4,
            children = {
                Comp.SanButton {
                    text    = backText,
                    variant = "primary",
                    onClick = function()
                        print("[返回按钮] onClick 触发! page=" .. currentPage_)
                        if currentPage_ == "formation" then
                            local backTo = previousPage_
                            if backTo == "" or backTo == "formation" then backTo = "city" end
                            switchPage(backTo)
                        else
                            switchPage("city")
                        end
                    end,
                },
            },
        }
        contentContainer_:AddChild(backBar)
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
                    switchPage("equip")
                elseif buildingId == "recruit" then
                    switchPage("recruit")
                elseif buildingId == "treasure" then
                    switchPage("treasure")
                elseif buildingId == "arena" then
                    Modal.Alert("演武场", "竞技系统开发中，敬请期待！")
                elseif buildingId == "shop" then
                    switchPage("shop")
                end
            end,
            onQuickAction = function(actionId)
                if actionId == "formation" then
                    switchPage("formation")
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

    elseif pageId == "recruit" then
        contentContainer_:AddChild(RecruitPage.Create(gs(), {
            onRecruit = function(recruitType)
                if recruitType == "single" then
                    if isNetworkMode_ then
                        ClientNet.SendAction("recruit")
                    else
                        local ok, msg, info = State.DoRecruit(gs())
                        if ok and info then
                            RecruitPage.ShowSingleResult(info)
                        else
                            Modal.Alert("提示", tostring(msg))
                        end
                        RecruitPage.Refresh(gs())
                        HUD.Update(gs())
                    end
                elseif recruitType == "ten" then
                    if isNetworkMode_ then
                        ClientNet.SendAction("recruit10")
                    else
                        local ok, msg, results = State.DoRecruit10(gs())
                        if ok and results then
                            RecruitPage.ShowTenResults(results)
                        else
                            Modal.Alert("提示", tostring(msg))
                        end
                        RecruitPage.Refresh(gs())
                        HUD.Update(gs())
                    end
                end
            end,
        }))

    elseif pageId == "shop" then
        contentContainer_:AddChild(ShopPage.Create(gs(), {
            onBuy = function(shopType, itemId)
                if isNetworkMode_ then
                    if shopType == "resource" then
                        ClientNet.SendAction("buy_shop_item", { itemId = itemId })
                    elseif shopType == "gift" then
                        ClientNet.SendAction("buy_gift_pack", { packId = itemId })
                    elseif shopType == "recharge" then
                        ClientNet.SendAction("recharge", { tierId = itemId })
                    end
                else
                    -- 单机模式: 本地处理
                    local ok, msg
                    if shopType == "resource" then
                        ok, msg = ShopData.BuyResourceItem(gs(), itemId)
                    elseif shopType == "gift" then
                        ok, msg = ShopData.BuyGiftPack(gs(), itemId)
                    elseif shopType == "recharge" then
                        ok, msg = ShopData.DoRecharge(gs(), itemId)
                    end
                    if ok then
                        Modal.Alert("购买成功", msg or "购买成功！")
                    else
                        Modal.Alert("提示", msg or "购买失败")
                    end
                    ShopPage.Refresh(gs())
                    HUD.Update(gs())
                end
            end,
        }))

    elseif pageId == "equip" then
        contentContainer_:AddChild(EquipPage.Create(gs(), {
            sendAction = function(action, params)
                if isNetworkMode_ then
                    ClientNet.SendAction(action, params)
                else
                    -- 单机模式: 本地处理
                    local ok, msg
                    if action == "equip_wear" then
                        ok, msg = State.EquipWear(gs(), params.heroId, params.bagIndex)
                    elseif action == "equip_remove" then
                        ok, msg = State.EquipRemove(gs(), params.heroId, params.slot)
                    elseif action == "equip_enhance" then
                        ok, msg = State.EquipEnhance(gs(), params.heroId, params.slot)
                    elseif action == "equip_refine" then
                        ok, msg = State.EquipRefine(gs(), params.heroId, params.slot)
                    elseif action == "equip_reforge" then
                        ok, msg = State.EquipReforge(gs(), params.heroId, params.slot, params.lockIndexes)
                    end
                    if ok then
                        State.RecalcPower(gs())
                    else
                        Modal.Alert("提示", msg or "操作失败")
                    end
                    EquipPage.Refresh(gs())
                    HUD.Update(gs())
                end
            end,
        }))

    elseif pageId == "treasure" then
        contentContainer_:AddChild(TreasurePage.Create(gs(), {
            sendAction = function(action, params)
                if isNetworkMode_ then
                    ClientNet.SendAction(action, params)
                else
                    -- 单机模式: 本地处理
                    local ok, msg
                    if action == "treasure_equip" then
                        ok, msg = TS.Equip(gs(), params.heroId, params.bagIndex, params.slot)
                    elseif action == "treasure_remove" then
                        ok, msg = TS.Remove(gs(), params.heroId, params.slot)
                    elseif action == "treasure_upgrade" then
                        ok, msg = TS.UpgradePublic(gs(), params.heroId, params.slot)
                    elseif action == "treasure_compose" then
                        ok, msg = TS.ComposePublic(gs(), params.templateId)
                    elseif action == "treasure_compose_exclusive" then
                        ok, msg = TS.ComposeExclusive(gs(), params.heroId)
                    end
                    if ok then
                        State.RecalcPower(gs())
                    else
                        Modal.Alert("提示", msg or "操作失败")
                    end
                    TreasurePage.Refresh(gs())
                    HUD.Update(gs())
                end
            end,
        }))
    end

    print("[三国神将录] 切换页面: " .. pageId)
end

-- 处理服务端即时事件
local function handleGameEvt(evtType, data)
    if evtType == "battle_result" then
        -- 收到战斗结果: 显示战斗回放
        print("[Battle] battle_result 收到, rounds=" .. tostring(data.rounds ~= nil)
            .. " #rounds=" .. #(data.rounds or {})
            .. " allies=" .. #(data.allies or {})
            .. " enemies=" .. #(data.enemies or {}))
        local log = {
            allies      = data.allies or {},
            enemies     = data.enemies or {},
            rounds      = data.rounds or {},
            totalRounds = data.totalRounds or 0,
            map_id      = data.mapId,
            node_id     = data.nodeId,
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
        print("[Battle] log构建完成 #rounds=" .. #log.rounds .. " totalRounds=" .. log.totalRounds)
        switchPage("battle")
        contentContainer_:ClearChildren()
        contentContainer_:AddChild(BattlePage.Create(log, {
            onBattleEnd = function()
                HUD.Update(gs())
                switchPage("map")
            end,
        }))

    elseif evtType == "recruit_result" then
        if data.success and data.info then
            if currentPage_ == "recruit" then
                RecruitPage.ShowSingleResult(data.info)
                RecruitPage.Refresh(gs())
            else
                local info = data.info
                local desc = info.type == "hero"
                    and ("恭喜获得武将: " .. (info.heroName or info.name or "") .. "！")
                    or  ((info.heroName or info.name or "") .. " 碎片 x" .. (info.count or 0))
                Modal.Alert("招募结果", desc)
            end
        else
            Modal.Alert("提示", tostring(data.msg or "招募失败"))
        end
        HUD.Update(gs())

    elseif evtType == "recruit10_result" then
        if data.success and data.results then
            if currentPage_ == "recruit" then
                RecruitPage.ShowTenResults(data.results)
                RecruitPage.Refresh(gs())
            else
                Modal.Alert("十连招募", "获得 " .. #data.results .. " 个结果")
            end
        else
            Modal.Alert("提示", tostring(data.msg or "十连招募失败"))
        end
        HUD.Update(gs())

    elseif evtType == "shop_result" then
        if data.success then
            local typeNames = { resource = "商品", gift = "礼包", recharge = "充值" }
            local label = typeNames[data.shopType] or "商品"
            Modal.Alert("购买成功", label .. "购买成功！")
        else
            Modal.Alert("提示", data.msg or "购买失败")
        end
        if currentPage_ == "shop" then
            ShopPage.Refresh(gs())
        end
        HUD.Update(gs())

    elseif evtType == "action_result" then
        if not data.success then
            Modal.Alert("提示", data.msg or "操作失败")
        end

    elseif evtType == "error" then
        Modal.Alert("错误", data.msg or "未知错误")
    end
end

--- 刷新 HUD 区服显示
local function refreshHudServer()
    if isNetworkMode_ then
        local name   = ServerUI.GetSelectedName()
        local status = ServerUI.GetSelectedStatus()
        if name ~= "" then
            HUD.SetServer(name, status)
        end
    end
end

--- 从开始界面进入游戏（双线汇合后调用）
local function enterGameFromStart()
    -- 隐藏开始界面
    StartPage.Hide()
    HUD.Update(gs())
    refreshHudServer()
    switchPage("city")

    if isNetworkMode_ then
        ClientNet.SendAction("game_start")
    end
    print("[三国神将录] 进入游戏")
end

--- 进入游戏（非开始界面场景：重连/换服后直接进入）
local function enterGame()
    HUD.Update(gs())
    refreshHudServer()
    switchPage("city")

    if isNetworkMode_ then
        ClientNet.SendAction("game_start")
    end
    print("[三国神将录] 进入游戏")
end

--- 回到开始界面（被踢/断线恢复等）
local function returnToStartScreen()
    gameInitReady_  = false
    serverSelected_ = false
    currentPage_    = ""
    if contentContainer_ then
        contentContainer_:ClearChildren()
    end
    Modal.CloseAll()
    StartPage.Show()
    StartPage.SetEnterEnabled(false)
    -- 重新拉取区服列表
    ServerUI.ResetSelection()
    ServerUI.FetchServerList()
end

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
        visible = false,
    }
    Modal.Init(overlayContainer_)
    -- 初始隐藏，防止空弹窗层拦截所有点击
    YGNodeStyleSetDisplay(overlayContainer_.node, YGDisplayNone)

    -- 返回按钮已改为 switchPage 内动态创建（非 absolute 定位）

    -- 内容区
    contentContainer_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexBasis     = 0,
        flexDirection = "column",
        overflow      = "hidden",
    }

    -- 开始界面覆盖层（网络模式显示，单机模式也短暂显示）
    local startPanel = StartPage.Create(function()
        -- "进入游戏" 按钮点击回调
        if isNetworkMode_ then
            -- 网络模式: 等 GameInit 到达再进入
            if gameInitReady_ then
                enterGameFromStart()
            else
                -- GameInit 尚未到达，按钮会被禁用，不应触发
                print("[客户端] 等待 GameInit...")
            end
        else
            -- 单机模式: 直接进入
            StartPage.Hide()
            enterGame()
        end
    end)

    -- 主布局
    local root = UI.SafeAreaView {
        width           = "100%",
        height          = "100%",
        flexDirection   = "column",
        backgroundColor = C.bg,
        children = {
            HUD.Create(),
            contentContainer_,
            overlayContainer_,
            startPanel,
        },
    }
    UI.SetRoot(root)

    -- 启用调试面板（悬浮在右上角，默认最小化为小圆圈）
    DebugLog.Enable(root)

    -- 状态变更 → 自动刷新 HUD
    State.onStateChanged = function()
        HUD.Update(gs())
        if currentPage_ == "map" then
            MapPage.Refresh(gs())
        elseif currentPage_ == "recruit" then
            RecruitPage.Refresh(gs())
        elseif currentPage_ == "shop" then
            ShopPage.Refresh(gs())
        elseif currentPage_ == "equip" then
            EquipPage.Refresh(gs())
        elseif currentPage_ == "formation" then
            FormationPage.Refresh(gs())
        elseif currentPage_ == "treasure" then
            TreasurePage.Refresh(gs())
        end
    end

    -- 网络模式: 初始化网络、区服、开始界面
    if isNetworkMode_ then
        ClientNet.Init()
        ServerUI.Init()

        -- 在开始界面嵌入区服选择控件
        local slot = StartPage.GetServerSlot()
        if slot then
            ServerUI.SetupStartScreenSlot(slot)
        end

        -- 区服列表回调
        ClientNet.OnServerList(function(list)
            ServerUI.OnServerListResp(list)
        end)

        -- 选服完成 → 标记 + 解锁按钮 + 刷新HUD区服
        ServerUI.OnServerReady(function()
            serverSelected_ = true
            refreshHudServer()
            -- 如果 GameInit 也到了，直接解锁按钮
            if gameInitReady_ then
                StartPage.SetEnterEnabled(true)
            end
        end)

        -- GameEvt 事件路由
        ClientNet.OnGameEvt(handleGameEvt)

        -- GameInit 到达
        ClientNet.OnGameInit(function()
            print("[客户端] GameInit 到达")
            gameInitReady_ = true
            -- 如果还在开始界面，解锁按钮等用户点击
            if StartPage.IsVisible() then
                if serverSelected_ then
                    StartPage.SetEnterEnabled(true)
                end
            else
                -- 不在开始界面（重连），直接刷新
                enterGame()
            end
        end)

        -- 换服回调
        ClientNet.OnServerSwitch(function()
            print("[客户端] 换服完成, 刷新界面")
            gameInitReady_ = true
            if StartPage.IsVisible() then
                StartPage.SetEnterEnabled(true)
            else
                enterGame()
            end
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
            elseif reason == "load_failed" then
                msg = "数据加载失败，请重试"
            end
            Modal.Alert("下线通知", msg, function()
                returnToStartScreen()
            end)
        end)

        -- 首次拉取区服列表
        ServerUI.FetchServerList()

        print("[客户端] 开始界面已显示, 等待选服+GameInit...")
    else
        -- 单机模式: 显示开始界面，立即可点击
        StartPage.SetEnterEnabled(true)
    end

    SampleInitMouseMode(MM_FREE)

    -- 订阅帧更新事件（帧动画、轮询等依赖此回调）
    SubscribeToEvent("Update", "HandleUpdate")

    print("[三国神将录] 客户端启动完成 - C/S 架构")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 开始界面火把帧动画
    StartPage.Update(dt)

    -- 区服列表重试轮询
    if isNetworkMode_ then
        ServerUI.Update(dt)
    end
    -- 战斗回放由 page_battle.lua 自主订阅 Update 事件驱动
end

function Stop()
    -- 单机模式: 退出时保存
    if not isNetworkMode_ and gs() then
        State.Save(gs())
    end
    UI.Shutdown()
end
