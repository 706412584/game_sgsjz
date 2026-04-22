-- ui/page_start.lua — 三国神将录 开始界面 (zIndex=900)
local UI    = require("urhox-libs/UI")
local Video = require("urhox-libs/Video")
local Theme = require("ui.theme")
local C     = Theme.colors

local M = {}

local startScreen_     = nil
local videoBg_         = nil
local videoWrap_       = nil   -- 视频包裹层，用于 opacity 淡入淡出
local serverSlot_      = nil
local onEnterCallback_ = nil
local enterBtn_        = nil
local enterEnabled_    = false

-- 背景视频路径（使用第一个视频）
local BG_VIDEO = "video/cgt-20260422145730-c7dvw_video.mp4"

-- 无缝循环参数
local LOOP_END   = 4.0   -- 循环终点（秒）
local FADE_DUR   = 0.35  -- 淡出/淡入时长（秒）
local FADE_START = LOOP_END - FADE_DUR  -- 开始淡出的时间点

-- 循环状态机
local loopState_   = "playing"  -- "playing" | "fading_out" | "seeking" | "fading_in"
local fadeTimer_   = 0

--- 创建开始界面覆盖层
---@param onEnter fun()
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter
    enterEnabled_ = false
    videoBg_      = nil

    startScreen_ = UI.Panel {
        id            = "start_screen",
        width         = "100%",
        height        = "100%",
        position      = "absolute",
        top = 0, left = 0,
        zIndex        = 900,
        justifyContent = "center",
        alignItems    = "center",
        overflow      = "hidden",
        backgroundColor = C.bg,
    }

    -- 1) 静态背景图（视频加载前显示）
    startScreen_:AddChild(UI.Panel {
        backgroundImage = "image/start_fire_f4_20260422063329.png",
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
    })

    -- 2) 视频包裹层（用于淡入淡出实现无闪屏循环）
    videoWrap_ = UI.Panel {
        width    = "100%",
        height   = "100%",
        position = "absolute",
        top = 0, left = 0,
        opacity  = 1.0,
        transition = "opacity " .. FADE_DUR .. "s easeInOut",
    }

    videoBg_ = Video.VideoPlayer {
        src            = BG_VIDEO,
        width          = "100%",
        height         = "100%",
        textureWidth   = 1280,
        textureHeight  = 720,
        autoPlay       = true,
        loop           = false,          -- 关闭内置循环，手动控制
        muted          = true,
        volume         = 0,
        objectFit      = "cover",
        backgroundColor = { 0, 0, 0, 0 },
        onEnded = function(self)
            -- 视频自然播放结束时也做 seek 回起点
            if loopState_ == "playing" then
                loopState_ = "fading_out"
                fadeTimer_ = FADE_DUR
                if videoWrap_ then videoWrap_:SetStyle({ opacity = 0 }) end
            end
        end,
    }
    videoWrap_:AddChild(videoBg_)
    startScreen_:AddChild(videoWrap_)

    -- 初始化循环状态
    loopState_ = "playing"
    fadeTimer_  = 0

    -- 3) 底部火光渐变（暖橙色，模拟篝火映照）
    startScreen_:AddChild(UI.Panel {
        width    = "100%",
        height   = "35%",
        position = "absolute",
        bottom   = 0,
        left     = 0,
        pointerEvents = "none",
        backgroundGradient = {
            direction = "to-bottom",
            colors = {
                { 0, 0, 0, 0 },
                { 30, 10, 0, 180 },
            },
        },
    })

    -- 4) 底部深色遮罩（让按钮文字可读）
    startScreen_:AddChild(UI.Panel {
        width    = "100%",
        height   = "25%",
        position = "absolute",
        bottom   = 0,
        left     = 0,
        pointerEvents = "none",
        backgroundGradient = {
            direction = "to-bottom",
            colors = {
                { 0, 0, 0, 0 },
                { 0, 0, 0, 160 },
            },
        },
    })

    -- 内容区：上-标题  下-区服+按钮
    local contentPanel = UI.Panel {
        width          = "100%",
        height         = "100%",
        justifyContent = "space-between",
        alignItems     = "center",
    }

    -- 上部: 标题
    contentPanel:AddChild(UI.Panel {
        width      = "100%",
        alignItems = "center",
        paddingTop = 40,
        gap        = 4,
        children = {
            UI.Panel {
                backgroundImage = "image/title_logo_20260421153613.png",
                backgroundFit   = "contain",
                width           = 360,
                height          = 200,
            },
            UI.Label {
                text       = "百将争雄  逐鹿天下",
                fontSize   = 13,
                fontColor  = { 220, 200, 150, 200 },
                textAlign  = "center",
            },
        },
    })

    -- 下部: 区服+进入按钮
    serverSlot_ = UI.Panel {
        id             = "start_server_slot",
        alignItems     = "center",
        justifyContent = "center",
        height         = 36,
    }

    local serverBg = UI.Panel {
        alignItems        = "center",
        justifyContent    = "center",
        paddingHorizontal = 16,
        paddingVertical   = 6,
        borderRadius      = 16,
        backgroundColor   = { C.bg[1], C.bg[2], C.bg[3], 180 },
        borderColor       = C.border,
        borderWidth       = 1,
        children          = { serverSlot_ },
    }

    enterBtn_ = UI.Panel {
        width          = 220,
        height         = 62,
        alignItems     = "center",
        justifyContent = "center",
        opacity        = 0.4,
        cursor         = "pointer",
        transition     = "opacity 0.3s easeOut",
        children = {
            UI.Panel {
                backgroundImage = "image/btn_enter_20260421153715.png",
                backgroundFit   = "contain",
                width           = 220,
                height          = 62,
                pointerEvents   = "none",
            },
        },
        onClick = function()
            if not enterEnabled_ then return end
            if onEnterCallback_ then onEnterCallback_() end
        end,
    }

    contentPanel:AddChild(UI.Panel {
        width        = "85%",
        maxWidth     = 340,
        alignItems   = "center",
        marginBottom = 60,
        gap          = 16,
        children = {
            serverBg,
            enterBtn_,
            UI.Label {
                text      = "v1.0.0",
                fontSize  = 10,
                fontColor = { C.textDim[1], C.textDim[2], C.textDim[3], 120 },
            },
        },
    })

    startScreen_:AddChild(contentPanel)
    return startScreen_
end

--- 每帧更新 — 驱动无闪屏视频循环
---@param dt number
function M.Update(dt)
    if not videoBg_ or not videoWrap_ then return end

    if loopState_ == "playing" then
        -- 监控播放时间，到达淡出起点时开始淡出
        local t = videoBg_:GetCurrentTime()
        if t >= FADE_START then
            loopState_ = "fading_out"
            fadeTimer_ = FADE_DUR
            videoWrap_:SetStyle({ opacity = 0 })
        end

    elseif loopState_ == "fading_out" then
        -- 等待淡出完成
        fadeTimer_ = fadeTimer_ - dt
        if fadeTimer_ <= 0 then
            -- 淡出完成，Seek 回起点
            videoBg_:Seek(0)
            videoBg_:Play()
            loopState_ = "seeking"
            fadeTimer_ = 0.05  -- 给 seek 一小段缓冲时间
        end

    elseif loopState_ == "seeking" then
        -- 等待 seek 缓冲
        fadeTimer_ = fadeTimer_ - dt
        if fadeTimer_ <= 0 then
            -- 开始淡入
            videoWrap_:SetStyle({ opacity = 1.0 })
            loopState_ = "fading_in"
            fadeTimer_ = FADE_DUR
        end

    elseif loopState_ == "fading_in" then
        -- 等待淡入完成
        fadeTimer_ = fadeTimer_ - dt
        if fadeTimer_ <= 0 then
            loopState_ = "playing"
        end
    end
end

-- 公开 API
function M.Show()
    if startScreen_ then
        startScreen_:SetVisible(true)
        YGNodeStyleSetDisplay(startScreen_.node, YGDisplayFlex)
        -- 恢复视频播放并重置循环状态
        if videoBg_ then
            videoBg_:Seek(0)
            videoBg_:Play()
        end
        if videoWrap_ then videoWrap_:SetStyle({ opacity = 1.0 }) end
        loopState_ = "playing"
        fadeTimer_  = 0
    end
end

function M.Hide()
    if startScreen_ then
        startScreen_:SetVisible(false)
        YGNodeStyleSetDisplay(startScreen_.node, YGDisplayNone)
        -- 暂停视频节省性能
        if videoBg_ then videoBg_:Pause() end
    end
end

---@return boolean
function M.IsVisible()
    return startScreen_ ~= nil and startScreen_:IsVisible()
end

---@return table|nil
function M.GetServerSlot()
    return serverSlot_
end

---@param enabled boolean
function M.SetEnterEnabled(enabled)
    enterEnabled_ = enabled
    if enterBtn_ then
        enterBtn_:SetStyle({ opacity = enabled and 1.0 or 0.4 })
    end
end

return M
