-- ============================================================================
-- 《问道长生》- 文字修仙放置游戏
-- 入口文件
-- ============================================================================

local UI = require("urhox-libs/UI")
local Router = require("ui_router")
local NVG = require("nvg_manager")
local Audio = require("audio_manager")
local Toast = require("ui_toast")
local GameServer = require("game_server")
local GamePlayer = require("game_player")
local GameCultivation = require("game_cultivation")
local ClientNet = require("network.client_net")
local Debug = require("ui_debug")
local Loading = require("ui_loading")
local GameAd = require("game_ad")
local ReconnectOverlay = require("ui_reconnect_overlay")

-- 页面模块（延迟加载，在 Start 中 require）
local ui_title
local ui_home
local ui_menu
local ui_world_map
local ui_explore
local ui_alchemy
local ui_bag
local ui_sect
local ui_chat
local ui_pet
local ui_more
local ui_home_pages
local ui_market
local ui_ranking
local ui_trial
local ui_quest
local ui_story
local ui_mail
local ui_social
local ui_signin
local ui_gift
local ui_recharge
local ui_monthcard
local ui_vip
local ui_gacha
local ui_battlepass

-- ============================================================================
-- 生命周期
-- ============================================================================



function Start()
    graphics.windowTitle = "问道长生"

    -- 1. 初始化 UI 系统
    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
                bold   = "Fonts/MiSans-Bold.ttf",
            } }
        },
        scale = UI.Scale.DEFAULT,
    })

    -- 1.5. 初始化 NanoVG 渲染管理器（必须在页面加载前）
    NVG.Init()

    -- 1.6. 初始化音频管理器并播放背景音乐
    Audio.Init()
    Audio.PlayBGM("audio/bgm_meditation.ogg")

    -- 1.7. 初始化区服管理器（读取本地记忆的服务器选择）
    GameServer.Init()

    -- 1.8. 初始化客户端网络（网络模式下注册远程事件）
    ClientNet.Init()

    -- 1.9. 初始化调试面板（劫持 print，捕获日志）
    Debug.Init()

    -- 1.10. 初始化广告管理器
    GameAd.Init()

    -- 2. 加载所有页面模块并注册到路由
    ui_title       = require("ui_title")
    ui_home        = require("ui_home")
    ui_menu        = require("ui_menu")
    ui_world_map   = require("ui_world_map")
    ui_explore     = require("ui_explore")
    ui_alchemy     = require("ui_alchemy")
    ui_bag         = require("ui_bag")
    ui_sect        = require("ui_sect")
    ui_chat        = require("ui_chat")
    ui_pet         = require("ui_pet")
    ui_more        = require("ui_more")
    ui_home_pages  = require("ui_home_pages")
    ui_market      = require("ui_market")
    ui_ranking     = require("ui_ranking")
    ui_trial       = require("ui_trial")
    ui_quest       = require("ui_quest")
    ui_story       = require("ui_story")
    ui_mail        = require("ui_mail")
    ui_social      = require("ui_social")
    ui_boss        = require("ui_boss")
    ui_signin      = require("ui_signin")
    ui_gift        = require("ui_gift")
    ui_recharge    = require("ui_recharge")
    ui_monthcard   = require("ui_monthcard")
    ui_vip         = require("ui_vip")
    ui_gacha       = require("ui_gacha")
    ui_battlepass  = require("ui_battlepass")

    Router.Register(Router.STATE_TITLE,       ui_title.Build)
    Router.Register(Router.STATE_HOME,        ui_home.Build)
    Router.Register(Router.STATE_MENU,        ui_menu.Build)
    Router.Register(Router.STATE_WORLD_MAP,   ui_world_map.Build)
    Router.Register(Router.STATE_EXPLORE,     ui_explore.Build)
    Router.Register(Router.STATE_ALCHEMY,     ui_alchemy.Build)
    Router.Register(Router.STATE_BAG,         ui_bag.Build)
    Router.Register(Router.STATE_SECT,        ui_sect.Build)
    Router.Register(Router.STATE_CHAT,        ui_chat.Build)
    Router.Register(Router.STATE_PET,         ui_pet.Build)
    Router.Register(Router.STATE_MORE,        ui_more.Build)
    Router.Register(Router.STATE_MARKET,     ui_market.Build)
    Router.Register(Router.STATE_RANKING,    ui_ranking.Build)
    Router.Register(Router.STATE_TRIAL,      ui_trial.Build)
    Router.Register(Router.STATE_QUEST,      ui_quest.Build)
    Router.Register(Router.STATE_STORY,      ui_story.Build)
    Router.Register(Router.STATE_MAIL,       ui_mail.Build)
    Router.Register(Router.STATE_SOCIAL,     ui_social.Build)
    Router.Register(Router.STATE_BOSS,       ui_boss.Build)
    Router.Register(Router.STATE_SIGNIN,     ui_signin.Build)
    Router.Register(Router.STATE_GIFT,       ui_gift.Build)
    Router.Register(Router.STATE_RECHARGE,   ui_recharge.Build)
    Router.Register(Router.STATE_MONTHCARD,  ui_monthcard.Build)
    Router.Register(Router.STATE_VIP,        ui_vip.Build)
    Router.Register(Router.STATE_GACHA,      ui_gacha.Build)
    Router.Register(Router.STATE_BATTLEPASS, ui_battlepass.Build)

    -- 洞府子页面
    Router.Register(Router.STATE_ATTR,        ui_home_pages.BuildAttr)
    Router.Register(Router.STATE_SKILL,       ui_home_pages.BuildSkill)
    Router.Register(Router.STATE_ARTIFACT,    ui_home_pages.BuildArtifact)
    Router.Register(Router.STATE_DAO,         ui_home_pages.BuildDao)
    Router.Register(Router.STATE_TRIBULATION, ui_home_pages.BuildTribulation)
    Router.Register(Router.STATE_PILL,        ui_home_pages.BuildPill)
    Router.Register(Router.STATE_STATS,       ui_home_pages.BuildStats)

    -- 注册带粒子系统的页面退出回调
    Router.RegisterExit(Router.STATE_TITLE, function() ui_title.StopParticles() end)
    Router.RegisterExit(Router.STATE_HOME,  function() ui_home.StopParticles() end)
    Router.RegisterExit(Router.STATE_STORY, function() ui_story.Cleanup() end)
    Router.RegisterExit(Router.STATE_SOCIAL, function() ui_social.Cleanup() end)
    Router.RegisterExit(Router.STATE_SECT, function() ui_sect.OnEnter() end)  -- 离开时重置，再回来会重新拉取
    Router.RegisterExit(Router.STATE_BOSS, function() ui_boss.Cleanup() end)

    -- 2.5. 注册全局 Toast + Debug + Loading 更新器
    NVG.Register("toast", nil, function(dt)
        Toast.Update(dt)
    end)
    NVG.Register("debug", nil, function(dt)
        Debug.Update(dt)
    end)
    NVG.Register("loading", nil, function(dt)
        Loading.Update(dt)
    end)

    -- 2.6. 注册覆盖层到路由系统（Toast + Loading + Debug 合并）
    Router.SetOverlayProvider(function()
        return UI.Panel {
            position = "absolute",
            left = 0, right = 0, top = 0, bottom = 0,
            pointerEvents = "box-none",
            children = {
                Toast.GetContainer(),
                Loading.GetContainer(),
                ReconnectOverlay.GetContainer(),
                Debug.GetContainer(),
            },
        }
    end)

    -- 3. 注册游戏逻辑更新（通过 NVG updater，避免覆盖 NVG 管理器的 Update 订阅）
    NVG.Register("game_logic", nil, function(dt)
        GamePlayer.Update(dt)
        GameCultivation.Update(dt)
    end)

    -- 4. 注册断线/重连回调（网络模式）
    if IsNetworkMode() then
        ClientNet.OnDisconnect(function()
            -- 被踢下线时不显示重连遮罩（由 OnKicked 处理）
            if ClientNet.IsKicked() then return end
            -- 还在标题页/创角/故事页时忽略断线（标题页 precheck 会自行处理）
            local st = Router.GetCurrentState()
            if st == Router.STATE_TITLE or st == Router.STATE_CREATE_ROLE or st == Router.STATE_STORY then
                print("[Main] 断线但仍在标题/创角/故事页，忽略")
                return
            end
            print("[Main] 检测到断线，显示重连遮罩")
            ReconnectOverlay.Show()
            -- 不清除玩家数据缓存，保留当前状态等待重连
        end)

        ClientNet.OnReconnect(function()
            -- 还在标题页时不处理重连（标题页 precheck 自行处理）
            local st = Router.GetCurrentState()
            if st == Router.STATE_TITLE or st == Router.STATE_CREATE_ROLE or st == Router.STATE_STORY then
                print("[Main] 重连成功但仍在标题/创角/故事页，忽略")
                return
            end
            print("[Main] 重连成功，隐藏遮罩并重新加载数据")
            ReconnectOverlay.Hide()
            Toast.Show("已重新连接服务器", { variant = "success" })
            -- 重连后重新加载一次玩家数据，确保云端数据同步
            if GamePlayer.HasCharacter() then
                GamePlayer.ForceSave(function(ok)
                    if ok then
                        print("[Main] 重连后数据保存成功")
                    end
                end)
            end
        end)

        -- 4.1. 被踢下线回调（双设备登录等）
        ClientNet.OnKicked(function(reason)
            print("[Main] 被踢下线: reason=" .. tostring(reason))
            -- 隐藏重连遮罩（如果有）
            ReconnectOverlay.Hide()
            -- 显示不可关闭的弹窗
            local Comp = require("ui_components")
            local msg = "您的账号已在其他设备登录，当前连接已断开。"
            if reason ~= "duplicate_login" then
                msg = "您已被服务器断开连接（" .. tostring(reason) .. "）"
            end
            local dlg = Comp.Dialog("连接中断", msg, {
                { text = "知道了", primary = true, onClick = function()
                    -- 无法重连，回到标题页
                    Router.EnterState(Router.STATE_TITLE)
                end },
            }, { closeOnMask = false })
            Router.ShowOverlayDialog(dlg)
        end)

        -- 4.2. 前后台切换检测（回到前台时若已断线立即显示重连遮罩）
        SubscribeToEvent("InputFocus", "HandleInputFocus")
    end

    -- 5. 进入标题页
    Router.EnterState(Router.STATE_TITLE)

    -- [诊断] 启动时检测云变量注入状态
    print("[Boot] clientCloud:", tostring(clientCloud))
    print("[Boot] clientScore:", tostring(clientScore))
    print("[Boot] IsNetworkMode:", tostring(IsNetworkMode()))
    print("[Boot] network.serverConnection:", tostring(network.serverConnection))

    print("[启动] 《问道长生》已启动")
end

-- ============================================================================
-- 前后台切换检测（回到前台时若已断线立即触发重连遮罩）
-- ============================================================================
function HandleInputFocus(eventType, eventData)
    local focus = eventData["Focus"]:GetBool()
    local minimized = eventData["Minimized"]:GetBool()
    print("[Main] InputFocus: focus=" .. tostring(focus) .. " minimized=" .. tostring(minimized))

    -- 回到前台且当前已断线 → 立即显示重连遮罩（不等 2-5 秒超时）
    if focus and not minimized then
        if IsNetworkMode() and not ClientNet.IsConnected() and not ClientNet.IsKicked() then
            -- 还在标题页/创角/故事页时不显示重连遮罩
            local st = Router.GetCurrentState()
            if st == Router.STATE_TITLE or st == Router.STATE_CREATE_ROLE or st == Router.STATE_STORY then
                return
            end
            print("[Main] 前台恢复时检测到断线，立即显示重连遮罩")
            if not ReconnectOverlay.IsActive() then
                ReconnectOverlay.Show()
            end
        end
    end
end

function Stop()
    -- 退出前强制保存
    if GamePlayer.HasCharacter() then
        GamePlayer.ForceSave()
    end
    UI.Shutdown()
end
