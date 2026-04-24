-- ============================================================================
-- 《问道长生》开场故事演出页
-- 4 幅水墨插画 + NanoVG 粒子动效 + 场景音效 + 逐行文字淡入
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Router = require("ui_router")
local NVG = require("nvg_manager")
local Audio = require("audio_manager")
local Inheritance = require("ui_inheritance")

local M = {}

-- ============================================================================
-- 故事数据
-- ============================================================================
local PANELS = {
    {
        image = Theme.images.story01,
        frames = {
            Theme.images.story01,
            Theme.images.story01_frame2,
            Theme.images.story01_frame3,
        },
        sfx   = "audio/story_sfx_01_creation.ogg",
        lines = {
            "天地初开，清浊分化，万灵由此而生。",
            "上古先民窥得大道残痕，遂有修真一脉传世。",
        },
    },
    {
        image = Theme.images.story02,
        frames = {
            Theme.images.story02,
            Theme.images.story02_frame2,
            Theme.images.story02_frame3,
            Theme.images.story02_frame4,
        },
        sfx   = "audio/story_sfx_02_calamity.ogg",
        lines = {
            "近百年来，灵机紊乱，天劫愈烈。",
            "坊间渐渐流传——",
            "这世上，已无真正的长生路了。",
        },
    },
    {
        image = Theme.images.story03,
        frames = {
            Theme.images.story03,
            Theme.images.story03_frame2,
            Theme.images.story03_frame3,
        },
        sfx   = "audio/story_sfx_03_escape.ogg",
        lines = {
            "那一夜，边城妖祸，亲族离散。",
            "逃亡途中，少年误入一处崩塌古洞。",
        },
    },
    {
        image = Theme.images.story04,
        frames = {
            Theme.images.story04,
            Theme.images.story04_frame2,
            Theme.images.story04_frame3,
        },
        sfx   = "audio/story_sfx_04_awakening.ogg",
        lines = {
            "残卷八字：见众生苦，方可问道。",
            "掌心浮现淡金古纹，",
            "修行，从此刻开始。",
        },
    },
}

-- ============================================================================
-- 粒子系统（每幕不同效果）
-- ============================================================================
local particles = {}
local screenW, screenH = 720, 1280
local particleInited = false

-- 幕1：金色灵光缓升 + 飘动云雾
local function CreateParticle1()
    local p = {}
    p.type = math.random() < 0.3 and "cloud" or "light"
    if p.type == "cloud" then
        p.x = math.random() * screenW
        p.y = math.random() * screenH * 0.5 + screenH * 0.1
        p.size = math.random() * 80 + 60
        p.speedX = (math.random() - 0.5) * 15
        p.speedY = -(math.random() * 5 + 2)
        p.alpha = math.random() * 0.06 + 0.02
        p.r, p.g, p.b = 220, 210, 180
    else
        p.x = math.random() * screenW
        p.y = screenH * 0.6 + math.random() * screenH * 0.4
        p.size = math.random() * 3 + 1.5
        p.speedX = (math.random() - 0.5) * 12
        p.speedY = -(math.random() * 40 + 20)
        p.alpha = math.random() * 0.5 + 0.2
        p.r, p.g, p.b = 220, 195, 120
    end
    p.lifetime = math.random() * 8 + 6
    p.age = 0
    p.alphaBase = p.alpha
    return p
end

-- 幕2：斜雨 + 红色余烬
local function CreateParticle2()
    local p = {}
    p.type = math.random() < 0.15 and "ember" or "rain"
    if p.type == "ember" then
        p.x = math.random() * screenW
        p.y = screenH * 0.3 + math.random() * screenH * 0.5
        p.size = math.random() * 3 + 1
        p.speedX = (math.random() - 0.5) * 30
        p.speedY = -(math.random() * 30 + 15)
        p.alpha = math.random() * 0.6 + 0.3
        p.r, p.g, p.b = 255, math.random(60, 120), 30
    else
        p.x = math.random() * (screenW + 200) - 100
        p.y = -math.random() * 100
        p.size = math.random() * 1.5 + 0.5
        p.len = math.random() * 25 + 15
        p.speedX = -60
        p.speedY = math.random() * 600 + 800
        p.alpha = math.random() * 0.25 + 0.1
        p.r, p.g, p.b = 180, 190, 210
    end
    p.lifetime = math.random() * 3 + 2
    p.age = 0
    p.alphaBase = p.alpha
    return p
end

-- 幕3：密集雨 + 远火明灭
local function CreateParticle3()
    local p = {}
    p.type = math.random() < 0.05 and "glow" or "rain"
    if p.type == "glow" then
        p.x = screenW * 0.7 + math.random() * screenW * 0.3
        p.y = screenH * 0.15 + math.random() * screenH * 0.15
        p.size = math.random() * 40 + 30
        p.speedX = 0
        p.speedY = 0
        p.alpha = math.random() * 0.08 + 0.02
        p.r, p.g, p.b = 255, 140, 40
        p.pulseSpeed = math.random() * 2 + 1
    else
        p.x = math.random() * (screenW + 300) - 150
        p.y = -math.random() * 80
        p.size = math.random() * 1 + 0.5
        p.len = math.random() * 20 + 12
        p.speedX = -40
        p.speedY = math.random() * 700 + 900
        p.alpha = math.random() * 0.2 + 0.08
        p.r, p.g, p.b = 160, 170, 195
    end
    p.lifetime = math.random() * 2.5 + 1.5
    p.age = 0
    p.alphaBase = p.alpha
    return p
end

-- 幕4：金色符文光点 + 尘埃
local function CreateParticle4()
    local p = {}
    p.type = math.random() < 0.35 and "rune" or "dust"
    if p.type == "rune" then
        local angle = math.random() * math.pi * 2
        local radius = math.random() * 120 + 60
        p.cx = screenW * 0.5
        p.cy = screenH * 0.45
        p.angle = angle
        p.radius = radius
        p.x = p.cx + math.cos(angle) * radius
        p.y = p.cy + math.sin(angle) * radius
        p.size = math.random() * 3 + 2
        p.speedAngle = (math.random() - 0.5) * 0.4
        p.speedX = 0
        p.speedY = 0
        p.alpha = math.random() * 0.6 + 0.3
        p.r, p.g, p.b = 230, 200, 100
    else
        p.x = math.random() * screenW
        p.y = math.random() * screenH
        p.size = math.random() * 1.5 + 0.5
        p.speedX = (math.random() - 0.5) * 8
        p.speedY = -(math.random() * 10 + 5)
        p.alpha = math.random() * 0.15 + 0.05
        p.r, p.g, p.b = 200, 190, 160
    end
    p.lifetime = math.random() * 6 + 4
    p.age = 0
    p.alphaBase = p.alpha
    return p
end

local createFns = { CreateParticle1, CreateParticle2, CreateParticle3, CreateParticle4 }
local PARTICLE_COUNTS = { 50, 80, 100, 45 }

local function InitParticles(panelIdx)
    screenW = graphics:GetWidth() / graphics:GetDPR()
    screenH = graphics:GetHeight() / graphics:GetDPR()
    particles = {}
    local count = PARTICLE_COUNTS[panelIdx] or 50
    local createFn = createFns[panelIdx] or CreateParticle1
    for i = 1, count do
        particles[i] = createFn()
        particles[i].age = math.random() * particles[i].lifetime * 0.5
    end
    particleInited = true
end

local function UpdateParticles(dt, panelIdx)
    local createFn = createFns[panelIdx] or CreateParticle1
    for i, p in ipairs(particles) do
        p.age = p.age + dt
        if p.type == "rune" and p.angle then
            p.angle = p.angle + p.speedAngle * dt
            p.x = p.cx + math.cos(p.angle) * p.radius
            p.y = p.cy + math.sin(p.angle) * p.radius
        else
            p.x = p.x + (p.speedX or 0) * dt
            p.y = p.y + (p.speedY or 0) * dt
        end
        if p.pulseSpeed then
            p.alpha = p.alphaBase * (0.5 + 0.5 * math.sin(p.age * p.pulseSpeed))
        end
        if p.age >= p.lifetime or p.y > screenH + 50 or p.y < -80 then
            particles[i] = createFn()
        end
    end
end

local function RenderParticles(ctx)
    for _, p in ipairs(particles) do
        local fadeAlpha = p.alpha or p.alphaBase
        local lifeRatio = p.age / p.lifetime
        if lifeRatio < 0.1 then
            fadeAlpha = fadeAlpha * (lifeRatio / 0.1)
        elseif lifeRatio > 0.8 then
            fadeAlpha = fadeAlpha * (1.0 - (lifeRatio - 0.8) / 0.2)
        end
        local a = math.floor(fadeAlpha * 255)
        if a < 2 then goto continue end

        if p.type == "rain" then
            nvgBeginPath(ctx)
            nvgMoveTo(ctx, p.x, p.y)
            nvgLineTo(ctx, p.x + (p.speedX or 0) * 0.02, p.y + (p.len or 15))
            nvgStrokeColor(ctx, nvgRGBA(p.r, p.g, p.b, a))
            nvgStrokeWidth(ctx, p.size)
            nvgStroke(ctx)
        elseif p.type == "cloud" then
            local paint = nvgRadialGradient(ctx,
                p.x, p.y, p.size * 0.2, p.size,
                nvgRGBA(p.r, p.g, p.b, a),
                nvgRGBA(p.r, p.g, p.b, 0))
            nvgBeginPath(ctx)
            nvgEllipse(ctx, p.x, p.y, p.size, p.size * 0.5)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        elseif p.type == "glow" then
            local paint = nvgRadialGradient(ctx,
                p.x, p.y, p.size * 0.1, p.size,
                nvgRGBA(p.r, p.g, p.b, a),
                nvgRGBA(p.r, p.g, p.b, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, p.size)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
        else
            local glowSize = p.size * 3
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
        end

        ::continue::
    end
end

-- ============================================================================
-- 状态
-- ============================================================================
local currentPanel_ = 1
local currentLine_ = 0
local autoTimer_ = 0
local AUTO_DELAY = 4.5
local LINE_INTERVAL = 0.8
local lineTimer_ = 0
local transitioning_ = false
local fadeOutTimer_ = -1
local FADE_DURATION = 0.8
local nvgRegistered_ = false
local storyActive_ = false
local bgmWasPaused_ = false

local lineElements_ = {}
local tapHintElement_ = nil
local rootElement_ = nil

-- 传承面板状态
local inheritanceActive_ = false

-- 帧动画状态
local FRAME_INTERVAL = 1.0       -- 每帧停留时间（秒）
local FRAME_FADE = 0.6           -- 交叉淡入淡出时长（秒）
local frameTimer_ = 0
local currentFrameIdx_ = 1
local bgPanelA_ = nil            -- 当前显示的背景层
local bgPanelB_ = nil            -- 下一帧淡入的背景层
local frameFading_ = false       -- 是否正在执行帧切换淡入淡出

-- 前置声明（定义在后方，但 StoryUpdate 中需要引用）
local StopPanelSFX

-- ============================================================================
-- 帧动画更新（交叉淡入淡出切换背景图）
-- ============================================================================
local function UpdateFrameAnimation(dt)
    if frameFading_ then return end  -- 淡入淡出动画进行中，等待完成

    local panel = PANELS[currentPanel_]
    if not panel or not panel.frames or #panel.frames <= 1 then return end

    frameTimer_ = frameTimer_ + dt
    if frameTimer_ < FRAME_INTERVAL then return end
    frameTimer_ = 0

    -- 计算下一帧索引（循环）
    local nextIdx = currentFrameIdx_ % #panel.frames + 1
    local nextImage = panel.frames[nextIdx]

    -- B 层设置下一帧图片并淡入
    if bgPanelB_ then
        bgPanelB_:SetStyle({ backgroundImage = nextImage })
        frameFading_ = true
        bgPanelB_:Animate({
            keyframes = { [0] = { opacity = 0 }, [1] = { opacity = 1 } },
            duration = FRAME_FADE,
            easing = "easeInOut",
            fillMode = "forwards",
            onComplete = function()
                -- 淡入完成后：A 层换成当前帧图（瞬间），B 层透明度归零
                if bgPanelA_ then
                    bgPanelA_:SetStyle({ backgroundImage = nextImage })
                end
                if bgPanelB_ then
                    bgPanelB_.props.opacity = 0
                    bgPanelB_.renderProps_.opacity = nil
                end
                currentFrameIdx_ = nextIdx
                frameFading_ = false
            end,
        })
    end
end

-- ============================================================================
-- 故事逻辑更新（合并到 NVG updater，避免 Update 事件冲突）
-- ============================================================================
local function StoryUpdate(dt)
    if not storyActive_ then return end

    -- 帧动画更新
    UpdateFrameAnimation(dt)

    -- 传承面板激活后，只更新传承逻辑，不再走故事流程
    if inheritanceActive_ then
        Inheritance.Update(dt)
        return
    end

    -- 淡出过渡
    if fadeOutTimer_ >= 0 then
        fadeOutTimer_ = fadeOutTimer_ + dt
        if fadeOutTimer_ >= FADE_DURATION then
            fadeOutTimer_ = -1
            if currentPanel_ < #PANELS then
                currentPanel_ = currentPanel_ + 1
                currentLine_ = 0
                lineTimer_ = 0
                autoTimer_ = 0
                transitioning_ = false
                -- 重置帧动画状态
                frameTimer_ = 0
                currentFrameIdx_ = 1
                frameFading_ = false
                bgPanelA_ = nil
                bgPanelB_ = nil
                StartNVG(currentPanel_)
                PlayPanelSFX(currentPanel_)
                Router.RebuildUI()
            else
                -- 第4幕结束 → 启动传承面板（不跳转创角页）
                inheritanceActive_ = true
                StopPanelSFX()
                Inheritance.Start(function()
                    M.Cleanup()
                end)
                Router.RebuildUI()
            end
        end
        return
    end

    if transitioning_ then return end

    local panel = PANELS[currentPanel_]
    if not panel then return end

    -- 逐行出现
    if currentLine_ < #panel.lines then
        lineTimer_ = lineTimer_ + dt
        if lineTimer_ >= LINE_INTERVAL then
            lineTimer_ = lineTimer_ - LINE_INTERVAL
            currentLine_ = currentLine_ + 1
            if lineElements_[currentLine_] then
                lineElements_[currentLine_]:Animate({
                    keyframes = {
                        [0] = { opacity = 0, translateY = 12 },
                        [1] = { opacity = 1, translateY = 0 },
                    },
                    duration = 0.6,
                    easing = "easeOut",
                    fillMode = "forwards",
                })
            end
            autoTimer_ = 0

            if currentLine_ >= #panel.lines and tapHintElement_ then
                tapHintElement_:Animate({
                    keyframes = { [0] = { opacity = 0 }, [1] = { opacity = 0.7 } },
                    duration = 0.5, easing = "easeOut", fillMode = "forwards",
                    onComplete = function()
                        if tapHintElement_ then
                            tapHintElement_:Animate({
                                keyframes = { [0] = { opacity = 0.3 }, [1] = { opacity = 0.8 } },
                                duration = 1.2, easing = "easeInOut",
                                loop = true, direction = "alternate",
                            })
                        end
                    end,
                })
            end
        end
        return
    end

    -- 自动翻页
    autoTimer_ = autoTimer_ + dt
    if autoTimer_ >= AUTO_DELAY then
        autoTimer_ = 0
        AdvanceStory()
    end
end

-- ============================================================================
-- NVG 粒子启停（同时包含粒子更新 + 故事逻辑更新）
-- ============================================================================
function StartNVG(panelIdx)
    if nvgRegistered_ then NVG.Unregister("story") end
    particleInited = false
    NVG.Register("story", RenderParticles, function(dt)
        -- 粒子更新
        if not particleInited then InitParticles(panelIdx) end
        UpdateParticles(dt, panelIdx)
        -- 故事逻辑更新（文字计时、自动翻页、淡出过渡）
        StoryUpdate(dt)
    end)
    nvgRegistered_ = true
end

local function StopNVG()
    if nvgRegistered_ then
        NVG.Unregister("story")
        nvgRegistered_ = false
    end
end

-- ============================================================================
-- 音效管理
-- ============================================================================
function PlayPanelSFX(panelIdx)
    Audio.StopLoop("story_sfx")
    local panel = PANELS[panelIdx]
    if panel and panel.sfx then
        Audio.PlayLoop("story_sfx", panel.sfx, 0.45)
    end
end

StopPanelSFX = function()
    Audio.StopLoop("story_sfx")
end

-- ============================================================================
-- 前进逻辑
-- ============================================================================
function AdvanceStory()
    if transitioning_ then return end

    local panel = PANELS[currentPanel_]

    if currentLine_ < #panel.lines then
        for i = currentLine_ + 1, #panel.lines do
            if lineElements_[i] then
                lineElements_[i]:Animate({
                    keyframes = {
                        [0] = { opacity = 0, translateY = 12 },
                        [1] = { opacity = 1, translateY = 0 },
                    },
                    duration = 0.4,
                    easing = "easeOut",
                    fillMode = "forwards",
                })
            end
        end
        currentLine_ = #panel.lines
        autoTimer_ = 0
        if tapHintElement_ then
            tapHintElement_:Animate({
                keyframes = { [0] = { opacity = 0 }, [1] = { opacity = 0.7 } },
                duration = 0.5, easing = "easeOut", fillMode = "forwards",
            })
        end
        return
    end

    -- 翻页淡出
    transitioning_ = true
    fadeOutTimer_ = 0
    if rootElement_ then
        rootElement_:Animate({
            keyframes = { [0] = { opacity = 1 }, [1] = { opacity = 0 } },
            duration = FADE_DURATION, easing = "easeIn", fillMode = "forwards",
        })
    end
end

local function SkipStory()
    if inheritanceActive_ then return end  -- 传承阶段不响应跳过
    -- 跳过故事，直接进入传承面板（不跳过创角）
    inheritanceActive_ = true
    StopPanelSFX()
    Inheritance.Start(function()
        M.Cleanup()
    end)
    Router.RebuildUI()
end

-- ============================================================================
-- 清理
-- ============================================================================
function M.Cleanup()
    storyActive_ = false
    inheritanceActive_ = false
    StopNVG()
    StopPanelSFX()
    -- 恢复主BGM（如果之前暂停了）
    if bgmWasPaused_ then
        Audio.ResumeBGM()
        bgmWasPaused_ = false
    end
    lineElements_ = {}
    tapHintElement_ = nil
    rootElement_ = nil
    particleInited = false
    -- 重置帧动画
    frameTimer_ = 0
    currentFrameIdx_ = 1
    frameFading_ = false
    bgPanelA_ = nil
    bgPanelB_ = nil
end

-- ============================================================================
-- 页面构建
-- ============================================================================
function M.Build(payload)
    if not storyActive_ then
        currentPanel_ = 1
        currentLine_ = 0
        autoTimer_ = 0
        lineTimer_ = 0
        transitioning_ = false
        fadeOutTimer_ = -1
        storyActive_ = true
        inheritanceActive_ = false
        -- 暂停主BGM（如果正在播放）
        if Audio.IsBGMPlaying() then
            Audio.PauseBGM()
            bgmWasPaused_ = true
        end
        StartNVG(currentPanel_)
        PlayPanelSFX(currentPanel_)
    end

    lineElements_ = {}
    local panel = PANELS[currentPanel_]

    -- 跳过按钮（故事和传承阶段都显示）
    local btnSkip = UI.Panel {
        position = "absolute",
        top = 48, right = 16,
        paddingLeft = 14, paddingRight = 14,
        paddingTop = 6, paddingBottom = 6,
        borderRadius = 14,
        backgroundColor = { 30, 25, 20, 120 },
        borderColor = { 160, 130, 60, 80 },
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self) SkipStory() end,
        children = {
            UI.Label {
                text = "跳过 >",
                fontSize = Theme.fontSize.small,
                fontColor = { 200, 190, 170, 200 },
            },
        },
    }

    -- ===== 传承面板模式 =====
    if inheritanceActive_ then
        local lastPanel = PANELS[#PANELS]
        local lastFrame = lastPanel.frames and lastPanel.frames[currentFrameIdx_] or lastPanel.image

        -- 保留双层背景用于帧动画继续
        bgPanelA_ = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundImage = lastFrame,
            backgroundFit = "cover",
            opacity = 1,
        }
        bgPanelB_ = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundImage = lastFrame,
            backgroundFit = "cover",
            opacity = 0,
        }

        -- 半透明遮罩（让传承面板更突出）
        local overlay = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 10, 8, 6, 140 },
        }

        local root = UI.Panel {
            width = "100%",
            height = "100%",
            backgroundColor = { 10, 8, 6, 255 },
            children = {
                bgPanelA_,
                bgPanelB_,
                overlay,
                Inheritance.Build(),
                -- 传承阶段不显示跳过按钮，避免跳过创建流程
            },
        }
        rootElement_ = root
        return root
    end

    -- ===== 正常故事模式 =====

    -- 文字行
    local lineChildren = {}
    for i = 1, #panel.lines do
        local lbl = UI.Label {
            text = panel.lines[i],
            fontSize = Theme.fontSize.subtitle,
            fontColor = { 235, 225, 205, 255 },
            textAlign = "center",
            opacity = 0,
            marginTop = (i == 1) and 0 or 6,
        }
        lineElements_[i] = lbl
        lineChildren[#lineChildren + 1] = lbl
    end

    -- 页面指示器
    local dots = {}
    for i = 1, #PANELS do
        dots[#dots + 1] = UI.Panel {
            width = (i == currentPanel_) and 18 or 6,
            height = 6,
            borderRadius = 3,
            backgroundColor = (i == currentPanel_)
                and { 200, 168, 85, 220 }
                or { 180, 170, 150, 100 },
        }
    end

    -- 点击提示
    tapHintElement_ = UI.Label {
        text = "点击继续",
        fontSize = Theme.fontSize.tiny,
        fontColor = { 180, 170, 150, 180 },
        textAlign = "center",
        opacity = 0,
    }

    -- 双层背景（A层当前帧，B层用于淡入下一帧）
    bgPanelA_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage = panel.frames and panel.frames[1] or panel.image,
        backgroundFit = "cover",
        opacity = 0,
    }
    bgPanelB_ = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundImage = panel.frames and panel.frames[1] or panel.image,
        backgroundFit = "cover",
        opacity = 0,
    }

    -- 根布局
    local root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = { 10, 8, 6, 255 },
        cursor = "pointer",
        onClick = function(self) AdvanceStory() end,
        children = {
            bgPanelA_,
            bgPanelB_,
            -- 底部固定遮罩
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 0,
                height = 280,
                backgroundColor = { 10, 8, 6, 180 },
            },
            -- 文字区域
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 100,
                alignItems = "center",
                paddingLeft = 40, paddingRight = 40,
                children = lineChildren,
            },
            -- 页面指示器
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 56,
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 8,
                children = dots,
            },
            -- 点击提示
            UI.Panel {
                position = "absolute",
                left = 0, right = 0, bottom = 34,
                alignItems = "center",
                children = { tapHintElement_ },
            },
            btnSkip,
        },
    }

    rootElement_ = root

    -- 背景 A 层淡入
    bgPanelA_:Animate({
        keyframes = { [0] = { opacity = 0 }, [1] = { opacity = 1 } },
        duration = 1.0, easing = "easeOut", fillMode = "forwards",
    })

    return root
end

return M
