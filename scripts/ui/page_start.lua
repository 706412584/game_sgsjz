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

-- 火星动画状态
local emberA_    = nil   -- 火星图层 A
local emberB_    = nil   -- 火星图层 B
local offsetA_   = 0     -- A 层偏移 (px)
local offsetB_   = 0     -- B 层偏移 (px)
local SPEED_A    = 12    -- A 层漂移速度 (px/s)
local SPEED_B    = 8     -- B 层漂移速度 (px/s)
local RANGE      = 40    -- 最大偏移量 (px)
local fadeTimer_ = 0     -- 呼吸闪烁计时器

--- 创建开始界面覆盖层
---@param onEnter fun()
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter
    enterEnabled_ = false
    offsetA_ = 0
    offsetB_ = 0
    fadeTimer_ = 0

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

    -- 1) 纯净背景图
    startScreen_:AddChild(UI.Panel {
        backgroundImage = "image/edited_bg_start_clean_20260421153502.png",
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
    })

    -- 2) 暖色调遮罩（战火氛围）
    startScreen_:AddChild(UI.Panel {
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
        backgroundColor = { 40, 15, 5, 30 },
    })

    -- 3) 火星图层 A（稀疏大颗粒，缓慢向上漂移）
    emberA_ = UI.Panel {
        backgroundImage = "image/embers_a_20260421160220.png",
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
        opacity         = 0.7,
    }
    startScreen_:AddChild(emberA_)

    -- 4) 火星图层 B（细密小火花，稍快漂移，半透明）
    emberB_ = UI.Panel {
        backgroundImage = "image/embers_b_20260421160309.png",
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
        opacity         = 0.4,
    }
    startScreen_:AddChild(emberB_)

    -- 5) 底部火光渐变（暖橙色，模拟地面篝火映照）
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

    -- 6) 底部深色遮罩（让按钮文字可读）
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

------------------------------------------------------------
-- 动画更新（由 client_main HandleUpdate 调用）
------------------------------------------------------------

--- 每帧更新火星漂移动画
---@param dt number
function M.Update(dt)
    if not startScreen_ or not M.IsVisible() then return end

    -- 火星层 A: 缓慢向上漂移
    offsetA_ = offsetA_ + SPEED_A * dt
    if offsetA_ >= RANGE then offsetA_ = 0 end

    -- 火星层 B: 稍快向上漂移
    offsetB_ = offsetB_ + SPEED_B * dt
    if offsetB_ >= RANGE then offsetB_ = 0 end

    -- 呼吸闪烁（opacity 在 0.5~0.8 之间缓慢波动）
    fadeTimer_ = fadeTimer_ + dt
    local breathA = 0.55 + 0.25 * math.sin(fadeTimer_ * 1.2)
    local breathB = 0.30 + 0.20 * math.sin(fadeTimer_ * 0.8 + 1.5)

    if emberA_ then
        emberA_:SetStyle({ top = -offsetA_, opacity = breathA })
    end
    if emberB_ then
        emberB_:SetStyle({ top = -offsetB_, opacity = breathB })
    end
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

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
