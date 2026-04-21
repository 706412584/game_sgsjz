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

-- 帧动画状态
local emberPanel_  = nil
local EMBER_FRAMES = {
    "image/embers_f1_20260421160716.png",
    "image/embers_f2_20260421160810.png",
    "image/embers_f3_20260421160808.png",
    "image/embers_f4_20260421160813.png",
}
local FRAME_COUNT   = #EMBER_FRAMES
local FRAME_TIME    = 0.18   -- 每帧持续时间 (秒)，~5.5fps
local frameTimer_   = 0
local frameIndex_   = 1
local breathTimer_  = 0      -- 呼吸闪烁计时器

--- 创建开始界面覆盖层
---@param onEnter fun()
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter
    enterEnabled_ = false
    frameTimer_  = 0
    frameIndex_  = 1
    breathTimer_ = 0

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

    -- 3) 火星帧动画图层（单 Panel，切换 backgroundImage）
    emberPanel_ = UI.Panel {
        backgroundImage = EMBER_FRAMES[1],
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
        opacity         = 0.7,
    }
    startScreen_:AddChild(emberPanel_)

    -- 4) 底部火光渐变（暖橙色，模拟篝火映照）
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

    -- 5) 底部深色遮罩（让按钮文字可读）
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

--- 每帧更新火星帧动画 + 呼吸闪烁
---@param dt number
function M.Update(dt)
    if not startScreen_ or not M.IsVisible() then return end
    if not emberPanel_ then return end

    -- 帧动画切换
    frameTimer_ = frameTimer_ + dt
    if frameTimer_ >= FRAME_TIME then
        frameTimer_ = frameTimer_ - FRAME_TIME
        frameIndex_ = frameIndex_ % FRAME_COUNT + 1
        emberPanel_:SetStyle({ backgroundImage = EMBER_FRAMES[frameIndex_] })
    end

    -- 呼吸闪烁（opacity 在 0.5~0.85 之间缓慢波动）
    breathTimer_ = breathTimer_ + dt
    local breath = 0.55 + 0.30 * math.sin(breathTimer_ * 1.0)
    emberPanel_:SetStyle({ opacity = breath })
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
