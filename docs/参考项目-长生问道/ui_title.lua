-- ============================================================================
-- 《问道长生》标题页（水墨风动画与灵气粒子）
-- 集成区服选择：显示当前服务器 → 点击选服 → 点击进入 → 云端检查
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local Settings = require("ui_settings")
local ServerSelect = require("ui_server_select")
local GameServer = require("game_server")
local GamePlayer = require("game_player")
local Toast = require("ui_toast")

local NVG = require("nvg_manager")
local Loading = require("ui_loading")
local ClientNet = require("network.client_net")
local DataServers = require("data_servers")

local M = {}

-- 入场动画是否已播放（避免打开/关闭设置时重复播放）
local animationsPlayed = false

-- 加载中标记（防止重复点击）
local isLoading_ = false
local enterBtn_ = nil

-- 服务端预检状态
local precheck_ = {
    active   = false,   -- 是否正在预检
    ready    = false,   -- 服务端已就绪
    elapsed  = 0,       -- 已经过时间
    shown    = false,   -- 是否已显示 Loading
}
local PRECHECK_THRESHOLD = 0.5  -- 500ms 后才显示 Loading
local PRECHECK_TIMEOUT   = 20   -- 20s 后停止后台预检，让用户手动重试
local WAIT_READY_TIMEOUT = 15   -- 点击"进入游戏"后最多等 15s

-- 重置动画标记（供 Router 在真正切换页面时调用）
function M.ResetAnimations()
    animationsPlayed = false
end

-- ============================================================================
-- 服务端预检（后台轮询 clientCloud 就绪状态）
-- ============================================================================

--- 检测 clientCloud 是否已注入就绪
---@return boolean
local function IsCloudReady()
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud ~= nil then return true end
    ---@diagnostic disable-next-line: undefined-global
    if clientScore ~= nil then return true end
    -- 网络模式下尝试注入 polyfill
    if IsNetworkMode() and network.serverConnection then
        if not ClientNet.IsPolyfill() then
            ClientNet.InjectPolyfill()
        end
        ---@diagnostic disable-next-line: undefined-global
        return clientCloud ~= nil
    end
    return false
end

--- 启动预检
local function StartPrecheck()
    -- 防止重复调用（Build 可能因 RebuildUI 被多次执行）
    if precheck_.active or precheck_.ready then return end

    if not IsNetworkMode() then
        precheck_.ready = true
        return
    end
    -- 立即检测一次
    if IsCloudReady() then
        precheck_.ready = true
        return
    end
    precheck_.active  = true
    precheck_.ready   = false
    precheck_.elapsed = 0
    precheck_.shown   = false

    NVG.Register("title_precheck", nil, function(dt)
        if precheck_.ready then return end
        precheck_.elapsed = precheck_.elapsed + dt

        if IsCloudReady() then
            precheck_.ready  = true
            precheck_.active = false
            if precheck_.shown then
                Loading.Stop()
                precheck_.shown = false
            end
            NVG.Unregister("title_precheck")
            print("[Title] 预检完成: 服务端就绪, 耗时 " .. string.format("%.0fms", precheck_.elapsed * 1000))
            return
        end

        -- 超过阈值未就绪 → 显示加载动画
        if not precheck_.shown and precheck_.elapsed >= PRECHECK_THRESHOLD then
            precheck_.shown = true
            Loading.ShowNow("正在连接服务器...")
            print("[Title] 预检: 超过500ms未就绪，显示加载遮罩")
        end

        -- 超时：停止后台预检，隐藏加载动画，让用户手动点击重试
        if precheck_.elapsed >= PRECHECK_TIMEOUT then
            precheck_.active = false
            NVG.Unregister("title_precheck")
            if precheck_.shown then
                Loading.Stop()
                precheck_.shown = false
            end
            Toast.Show("连接服务器超时，请稍后点击进入", { variant = "error" })
            print("[Title] 预检超时（" .. PRECHECK_TIMEOUT .. "s），停止等待")
        end
    end)
end

--- 停止预检（离开标题页时调用）
local function StopPrecheck()
    if precheck_.active then
        NVG.Unregister("title_precheck")
        precheck_.active = false
    end
    if precheck_.shown then
        Loading.Stop()
        precheck_.shown = false
    end
end

-- ============================================================================
-- 灵气粒子系统（NanoVG 实现 - 通过 nvg_manager 调度）
-- ============================================================================
local particles = {}
local MAX_PARTICLES = 40
local particleInited = false
local screenW, screenH = 720, 1280

local function CreateParticle(forceBottom)
    local p = {}
    p.x = math.random() * screenW
    if forceBottom then
        p.y = screenH * 0.7 + math.random() * (screenH * 0.35)
    else
        p.y = math.random() * screenH
    end
    p.size = math.random() * 3 + 1.5
    p.speedY = -(math.random() * 60 + 30)
    p.speedX = (math.random() - 0.5) * 20
    p.alpha = math.random() * 0.4 + 0.15
    p.alphaSpeed = (math.random() - 0.5) * 0.3
    p.lifetime = math.random() * 10 + 8
    p.age = 0
    local colorType = math.random(1, 3)
    if colorType == 1 then
        p.r, p.g, p.b = 200, 168, 85
    elseif colorType == 2 then
        p.r, p.g, p.b = 120, 180, 220
    else
        p.r, p.g, p.b = 220, 215, 200
    end
    return p
end

local function InitParticles()
    if particleInited then return end
    particleInited = true
    screenW = graphics:GetWidth() / graphics:GetDPR()
    screenH = graphics:GetHeight() / graphics:GetDPR()
    for i = 1, MAX_PARTICLES do
        particles[i] = CreateParticle(false)
        particles[i].age = math.random() * particles[i].lifetime * 0.5
    end
end

local function UpdateParticles(dt)
    for i, p in ipairs(particles) do
        p.age = p.age + dt
        p.x = p.x + p.speedX * dt
        p.y = p.y + p.speedY * dt
        p.alpha = p.alpha + p.alphaSpeed * dt
        if p.alpha > 0.55 then p.alpha = 0.55; p.alphaSpeed = -math.abs(p.alphaSpeed) end
        if p.alpha < 0.1 then p.alpha = 0.1; p.alphaSpeed = math.abs(p.alphaSpeed) end
        if p.age >= p.lifetime or p.y < -30 then
            particles[i] = CreateParticle(true)
        end
    end
end

local function RenderParticles(ctx)
    for _, p in ipairs(particles) do
        local fadeAlpha = p.alpha
        local lifeRatio = p.age / p.lifetime
        if lifeRatio > 0.75 then
            fadeAlpha = fadeAlpha * (1.0 - (lifeRatio - 0.75) / 0.25)
        end
        if lifeRatio < 0.1 then
            fadeAlpha = fadeAlpha * (lifeRatio / 0.1)
        end

        local a = math.floor(fadeAlpha * 255)
        if a < 2 then goto continue end

        local glowSize = p.size * 3.5
        local paint = nvgRadialGradient(ctx,
            p.x, p.y, p.size * 0.3, glowSize,
            nvgRGBA(p.r, p.g, p.b, math.floor(a * 0.4)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, p.x, p.y, glowSize)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)

        nvgBeginPath(ctx)
        nvgCircle(ctx, p.x, p.y, p.size * 0.6)
        nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, a))
        nvgFill(ctx)

        ::continue::
    end
end

-- ============================================================================
-- 启停粒子系统
-- ============================================================================
local titleRegistered = false

function M.StartParticles()
    if titleRegistered then return end
    titleRegistered = true
    NVG.Register("title", RenderParticles, function(dt)
        InitParticles()
        UpdateParticles(dt)
    end)
end

function M.StopParticles()
    if not titleRegistered then return end
    titleRegistered = false
    NVG.Unregister("title")
    -- 离开标题页时停止预检和等待
    StopPrecheck()
    NVG.Unregister("title_wait_ready")
end

-- ============================================================================
-- 进入游戏（Load-Gate：一次性加载全部玩家数据）
-- ============================================================================
local function DoEnterGame()
    -- 切服后需重置缓存
    GamePlayer.Reset()

    print("[Title] Load-Gate: 加载玩家数据...")
    GamePlayer.Load(function(success, isNewPlayer)
        isLoading_ = false
        -- 恢复按钮文字
        if enterBtn_ then
            pcall(function() enterBtn_:SetStyle({ text = "进入游戏" }) end)
        end
        if not success then
            Toast.Show("网络连接失败，请稍后重试", { variant = "error" })
            return
        end

        -- 加载屏蔽列表
        local okBlock, GameBlock = pcall(require, "game_block")
        if okBlock and GameBlock.Load then
            GameBlock.Load()
        end

        -- 通知服务端玩家进入区服（在线人数计数）
        if IsNetworkMode() and ClientNet.IsConnected() then
            local currentSrv = GameServer.GetCurrentServer()
            local joinData = VariantMap()
            joinData["Action"] = Variant("join")
            joinData["ServerId"] = Variant(currentSrv.id)
            ClientNet.SendToServer("ReqServerOnline", joinData)
        end

        -- 停止预检（离开标题页前）
        StopPrecheck()

        -- 数据加载完成，首次刷新红点
        local okRD, GameRedDot = pcall(require, "game_red_dot")
        if okRD and GameRedDot.RefreshAll then
            GameRedDot.RefreshAll()
        end

        if isNewPlayer then
            print("[Title] 新玩家，进入故事")
            Router.EnterState(Router.STATE_STORY)
        else
            -- 恢复炼丹状态（离线期间可能有未完成的炼丹）
            local okAlch, GameAlchemy = pcall(require, "game_alchemy")
            if okAlch and GameAlchemy.RestoreFromSave then
                GameAlchemy.RestoreFromSave()
            end

            print("[Title] 老玩家，进入主页")
            Router.EnterState(Router.STATE_HOME)
        end
    end)
end

local function HandleEnterGame()
    if isLoading_ then return end

    if not IsNetworkMode() then
        Toast.Show("当前版本仅支持联网模式", { variant = "error" })
        return
    end

    isLoading_ = true

    -- 立即将按钮文字改为加载中
    if enterBtn_ then
        pcall(function() enterBtn_:SetStyle({ text = "加载中..." }) end)
    end

    -- 预检已就绪 → 直接加载数据
    if precheck_.ready then
        DoEnterGame()
        return
    end

    -- 预检未就绪 → 显示 Loading 并等待就绪后自动进入
    if not precheck_.shown then
        precheck_.shown = true
        Loading.ShowNow("正在连接服务器...")
    end

    -- 等待服务端就绪的 updater（有超时保护）
    local waitElapsed_ = 0
    NVG.Register("title_wait_ready", nil, function(dt)
        waitElapsed_ = waitElapsed_ + dt

        if IsCloudReady() then
            precheck_.ready = true
            NVG.Unregister("title_wait_ready")
            if precheck_.shown then
                Loading.Stop()
                precheck_.shown = false
            end
            if precheck_.active then
                NVG.Unregister("title_precheck")
                precheck_.active = false
            end
            DoEnterGame()
            return
        end

        -- 超时：还原按钮状态，提示用户重试
        if waitElapsed_ >= WAIT_READY_TIMEOUT then
            NVG.Unregister("title_wait_ready")
            if precheck_.shown then
                Loading.Stop()
                precheck_.shown = false
            end
            if precheck_.active then
                NVG.Unregister("title_precheck")
                precheck_.active = false
            end
            isLoading_ = false
            if enterBtn_ then
                pcall(function() enterBtn_:SetStyle({ text = "进入游戏" }) end)
            end
            Toast.Show("连接服务器超时，请检查网络后重试", { variant = "error" })
            print("[Title] 等待服务端超时（" .. WAIT_READY_TIMEOUT .. "s）")
        end
    end)
end

-- ============================================================================
-- 页面构建
-- ============================================================================
function M.Build(payload)
    M.StartParticles()
    isLoading_ = false

    -- 进入标题页时立即启动服务端预检
    StartPrecheck()

    local shouldAnimate = not animationsPlayed
    local currentServer = GameServer.GetCurrentServer()

    -- ---- 顶部水墨远山 ----
    local mountainDecor = UI.Panel {
        width = "100%",
        height = 220,
        backgroundImage = Theme.images.titleMountain,
        backgroundFit = "cover",
        opacity = shouldAnimate and 0 or 0.05,
    }

    -- ---- 金色标题 ----
    local titleImage = UI.Panel {
        width = 480,
        height = 170,
        backgroundImage = Theme.images.titleGold,
        backgroundFit = "contain",
        opacity = shouldAnimate and 0 or 1,
    }

    -- ---- 副标题 ----
    local subtitleLabel = UI.Label {
        text = "-- 修仙 . 放置 . 悟道 --",
        fontSize = Theme.fontSize.small,
        fontColor = Theme.colors.textLight,
        textAlign = "center",
        opacity = shouldAnimate and 0 or 1,
    }

    -- ---- 服务器选择按钮 ----
    -- 获取当前区服在线状态（如果有缓存数据）
    local serverOnlineData = ServerSelect.GetOnlineData()
    local currentOnline = serverOnlineData[currentServer.id]
    local statusChildren = {
        UI.Label {
            text = "服务器",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textLight,
        },
        UI.Label {
            text = currentServer.name,
            fontSize = Theme.fontSize.body,
            fontWeight = "bold",
            fontColor = { 80, 220, 130, 255 },
        },
    }
    -- 如果有在线数据，显示状态标签
    if currentOnline and DataServers.IsSelectable(currentServer) then
        local sTag, sColor, sBg = DataServers.GetStatusByOnline(currentOnline)
        statusChildren[#statusChildren + 1] = UI.Panel {
            paddingLeft = 5, paddingRight = 5,
            paddingTop = 2, paddingBottom = 2,
            borderRadius = 3,
            backgroundColor = sBg,
            children = {
                UI.Label {
                    text = sTag,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = sColor,
                },
            },
        }
    end


    -- 箭头指示
    statusChildren[#statusChildren + 1] = UI.Label {
        text = ">>",
        fontSize = Theme.fontSize.small,
        fontColor = { 160, 130, 60, 180 },
    }

    local serverBtn = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        padding = { 6, 14 },
        borderRadius = 16,
        backgroundColor = { 30, 25, 20, 160 },
        borderColor = { 160, 130, 60, 80 },
        borderWidth = 1,
        cursor = "pointer",
        opacity = shouldAnimate and 0 or 1,
        onClick = function(self)
            ServerSelect.Show(
                function(server)
                    -- 切服后重置预检状态并重新检测
                    StopPrecheck()
                    precheck_.ready = false
                    Router.RebuildUI()
                end,
                nil  -- 关闭回调
            )
        end,
        children = statusChildren,
    }

    -- ---- 进入游戏按钮 ----
    local enterLabel = UI.Label {
        text = "进入游戏",
        fontSize = Theme.fontSize.subtitle,
        fontWeight = "bold",
        fontColor = Theme.colors.textLight,
    }
    enterBtn_ = enterLabel   -- 保存引用，用于加载时更新文字
    local btnEnter = UI.Panel {
        width = "80%",
        height = 44,
        borderRadius = Theme.radius.md,
        backgroundColor = Theme.colors.gold,
        justifyContent = "center",
        alignItems = "center",
        alignSelf = "center",
        borderColor = Theme.colors.goldDark,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            HandleEnterGame()
        end,
        children = { enterLabel },
    }
    btnEnter:SetStyle({ opacity = shouldAnimate and 0 or 1 })

    local versionLabel = UI.Label {
        text = "v0.1.0  |  " .. currentServer.name,
        fontSize = Theme.fontSize.tiny,
        fontColor = { 120, 110, 95, 150 },
        opacity = shouldAnimate and 0 or 1,
    }

    -- ---- 右上角设置按钮 ----
    local btnSettings = UI.Panel {
        position = "absolute",
        top = 50,
        right = 15,
        width = 38,
        height = 38,
        borderRadius = 19,
        backgroundColor = { 30, 25, 20, 140 },
        borderColor = { 160, 130, 60, 80 },
        borderWidth = 1,
        justifyContent = "center",
        alignItems = "center",
        cursor = "pointer",
        opacity = shouldAnimate and 0 or 1,
        onClick = function(self)
            Settings.Show()
        end,
        children = {
            UI.Label {
                text = "⚙",
                fontSize = 20,
                fontColor = Theme.colors.textLight,
            },
        },
    }

    -- ---- 设置弹窗 overlay ----
    local settingsVisible = Settings.IsVisible()
    local settingsOverlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = settingsVisible and "auto" or "none",
        children = settingsVisible and {
            Settings.Build(function() Settings.Hide() end),
        } or {},
    }
    Settings.BindOverlay(settingsOverlay)

    -- ---- 选服弹窗 overlay ----
    local serverSelectVisible = ServerSelect.IsVisible()
    local serverSelectOverlay = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        pointerEvents = serverSelectVisible and "auto" or "none",
        children = serverSelectVisible and {
            ServerSelect.Build(),
        } or {},
    }
    ServerSelect.BindOverlay(serverSelectOverlay)

    -- ---- 构建 UI 树 ----
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgCreateRole,
        backgroundFit = "cover",
        children = {
            -- 半透明水墨遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 20, 18, 15, 80 },
            },

            -- 主内容
            UI.Panel {
                width = "100%",
                height = "100%",
                alignItems = "center",
                children = {
                    mountainDecor,

                    -- 标题区域
                    UI.Panel {
                        alignItems = "center",
                        gap = 8,
                        marginTop = -30,
                        children = {
                            titleImage,
                            subtitleLabel,
                        },
                    },

                    -- 中间弹性留白
                    UI.Panel { flexGrow = 1 },

                    -- 服务器选择按钮
                    UI.Panel {
                        alignItems = "center",
                        marginBottom = 16,
                        children = { serverBtn },
                    },

                    -- 按钮组
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        gap = 12,
                        paddingBottom = 20,
                        children = {
                            btnEnter,
                        },
                    },

                    -- 版本号
                    UI.Panel {
                        marginBottom = 32,
                        alignItems = "center",
                        children = { versionLabel },
                    },
                },
            },

            -- 右上角设置按钮
            btnSettings,

            -- 弹窗层（叠在最上）
            settingsOverlay,
            serverSelectOverlay,
        },
    }

    -- ====================================================================
    -- 入场动画序列
    -- ====================================================================
    if shouldAnimate then
        animationsPlayed = true

        mountainDecor:Animate({
            keyframes = {
                [0] = { opacity = 0, translateY = -10 },
                [1] = { opacity = 0.05, translateY = 0 },
            },
            duration = 2.0,
            easing = "easeOut",
            fillMode = "forwards",
        })

        titleImage:Animate({
            keyframes = {
                [0]   = { opacity = 0, scale = 0.7 },
                [0.6] = { opacity = 1, scale = 1.06 },
                [1]   = { opacity = 1, scale = 1.0 },
            },
            duration = 1.0,
            easing = "easeOut",
            fillMode = "forwards",
            onComplete = function()
                titleImage:Animate({
                    keyframes = {
                        [0] = { scale = 1.0, opacity = 1.0 },
                        [1] = { scale = 1.03, opacity = 0.85 },
                    },
                    duration = 2.5,
                    easing = "easeInOut",
                    loop = true,
                    direction = "alternate",
                })
            end,
        })

        subtitleLabel:Animate({
            keyframes = {
                [0]   = { opacity = 0, translateY = 12 },
                [0.4] = { opacity = 0, translateY = 12 },
                [1]   = { opacity = 1, translateY = 0 },
            },
            duration = 1.2,
            easing = "easeOut",
            fillMode = "forwards",
        })

        serverBtn:Animate({
            keyframes = {
                [0]   = { opacity = 0, translateY = 15 },
                [0.3] = { opacity = 0, translateY = 15 },
                [1]   = { opacity = 1, translateY = 0 },
            },
            duration = 1.0,
            easing = "easeOut",
            fillMode = "forwards",
        })

        btnEnter:Animate({
            keyframes = {
                [0]   = { opacity = 0, translateY = 20 },
                [0.4] = { opacity = 0, translateY = 20 },
                [1]   = { opacity = 1, translateY = 0 },
            },
            duration = 1.2,
            easing = "easeOut",
            fillMode = "forwards",
        })

        btnSettings:Animate({
            keyframes = {
                [0]   = { opacity = 0 },
                [0.5] = { opacity = 0 },
                [1]   = { opacity = 1 },
            },
            duration = 1.4,
            easing = "easeOut",
            fillMode = "forwards",
        })

        versionLabel:Animate({
            keyframes = {
                [0]   = { opacity = 0 },
                [0.7] = { opacity = 0 },
                [1]   = { opacity = 1 },
            },
            duration = 2.0,
            easing = "linear",
            fillMode = "forwards",
        })
    else
        titleImage:Animate({
            keyframes = {
                [0] = { scale = 1.0, opacity = 1.0 },
                [1] = { scale = 1.03, opacity = 0.85 },
            },
            duration = 2.5,
            easing = "easeInOut",
            loop = true,
            direction = "alternate",
        })
    end

    return root
end

return M
