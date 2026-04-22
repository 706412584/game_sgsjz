-- ui/page_start.lua — 三国神将录 开始界面 (zIndex=900)
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors

local M = {}

local startScreen_     = nil
local serverSlot_      = nil
local onEnterCallback_ = nil
local enterBtn_        = nil
local enterEnabled_    = false

-- 帧动画状态（双层 A/B 交叉淡入淡出 — 完整背景帧）
-- 序列: f1(无火) → f2(起火) → f3(旺盛) → f4(旺盛变体) → 之后 f3↔f4 循环
local FIRE_FRAMES = {
    "image/start_fire_f1_20260422064736.png",   -- 无火，火球远处
    "image/start_fire_f2_20260422064619.png",   -- 小火苗，火球逼近
    "image/start_fire_f3_20260422064621.png",   -- 旺盛，火球落地
    "image/start_fire_f4_20260422064622.png",   -- 旺盛变体，火球炸开
}
local FRAME_INTERVAL = 1.2      -- 每帧停留秒数
local FRAME_FADE     = 0.8      -- 交叉淡入淡出时长
local bgLayerA_      = nil      -- 当前显示层
local bgLayerB_      = nil      -- 淡入过渡层
local frameTimer_    = 0
local frameIndex_    = 1        -- 当前帧 (1-4)
local introPlayed_   = false    -- 开场 1→2→3→4 是否播完
local frameFading_   = false    -- 是否正在淡入淡出

--- 创建开始界面覆盖层
---@param onEnter fun()
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter
    enterEnabled_ = false
    frameTimer_   = 0
    frameIndex_   = 1
    introPlayed_  = false
    frameFading_  = false
    bgLayerA_     = nil
    bgLayerB_     = nil

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

    -- 1) 火把帧动画背景（双层 A/B 交叉淡入淡出）
    bgLayerA_ = UI.Panel {
        backgroundImage = FIRE_FRAMES[1],
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
        opacity         = 1.0,
    }
    bgLayerB_ = UI.Panel {
        backgroundImage = FIRE_FRAMES[1],
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
        opacity         = 0,
    }
    startScreen_:AddChild(bgLayerA_)
    startScreen_:AddChild(bgLayerB_)

    -- 2) 底部火光渐变（暖橙色，模拟篝火映照）
    startScreen_:AddChild(UI.Panel {
        width    = "100%",
        height   = "35%",
        position = "absolute",
        bottom   = 0,
        left     = 0,
        backgroundGradient = {
            direction = "to-bottom",
            colors = {
                { 0, 0, 0, 0 },
                { 30, 10, 0, 180 },
            },
        },
    })

    -- 3) 底部深色遮罩（让按钮文字可读）
    startScreen_:AddChild(UI.Panel {
        width    = "100%",
        height   = "25%",
        position = "absolute",
        bottom   = 0,
        left     = 0,
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
            },
        },
        onPress = function()
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

--- 每帧更新火把帧动画
--- 序列: f1→f2→f3→f4（开场），之后 f3↔f4 循环
---@param dt number
function M.Update(dt)
    if not startScreen_ or not M.IsVisible() then return end
    if not bgLayerA_ or not bgLayerB_ then return end
    if frameFading_ then return end

    frameTimer_ = frameTimer_ + dt
    if frameTimer_ < FRAME_INTERVAL then return end
    frameTimer_ = 0

    -- 计算下一帧
    local nextIdx
    if not introPlayed_ then
        -- 开场阶段: 1→2→3→4 顺序播放
        nextIdx = frameIndex_ + 1
        if nextIdx > 4 then
            -- 开场播完，进入循环
            introPlayed_ = true
            nextIdx = 3   -- 回到 f3 开始循环
        end
    else
        -- 循环阶段: f3↔f4
        nextIdx = (frameIndex_ == 3) and 4 or 3
    end

    local nextImage = FIRE_FRAMES[nextIdx]

    -- B 层设置下一帧图片并淡入
    bgLayerB_:SetStyle({ backgroundImage = nextImage })
    frameFading_ = true
    bgLayerB_:Animate({
        keyframes = {
            [0] = { opacity = 0 },
            [1] = { opacity = 1.0 },
        },
        duration = FRAME_FADE,
        easing   = "easeInOut",
        fillMode = "forwards",
        onComplete = function()
            -- 淡入完成：A 层换成当前帧图（瞬间），B 层归零
            if bgLayerA_ then
                bgLayerA_:SetStyle({ backgroundImage = nextImage })
            end
            if bgLayerB_ then
                bgLayerB_.props.opacity = 0
                bgLayerB_.renderProps_.opacity = nil
            end
            frameIndex_ = nextIdx
            frameFading_ = false
        end,
    })
end

-- 公开 API
function M.Show()
    if startScreen_ then
        startScreen_:SetVisible(true)
        YGNodeStyleSetDisplay(startScreen_.node, YGDisplayFlex)
    end
end

function M.Hide()
    if startScreen_ then
        startScreen_:SetVisible(false)
        YGNodeStyleSetDisplay(startScreen_.node, YGDisplayNone)
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
