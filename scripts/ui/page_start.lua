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

-- 火球动画参数（从右上飞向左下）
local FIREBALL_IMG = "image/fireball_ink_20260422125819.png"
local FB_W, FB_H   = 260, 170          -- 火球贴图显示尺寸
local FB_SPEED      = 110              -- 像素/秒
local FB_ANGLE      = math.rad(225)    -- 飞行方向：左下 (225°)
local FB_VX         = FB_SPEED * math.cos(FB_ANGLE)
local FB_VY         = -FB_SPEED * math.sin(FB_ANGLE) -- UI 坐标 Y 向下

-- 两颗火球，错开时间，增加动感
local fireballs_ = {}

--- 初始化火球起始位置（屏幕右上外侧）
local function resetFireball(fb, screenW, screenH, offsetPct)
    -- 从右上角外侧不同位置出发
    fb.x = screenW * (0.75 + offsetPct * 0.3) + FB_W
    fb.y = -(FB_H + offsetPct * screenH * 0.15)
end

--- 创建开始界面覆盖层
---@param onEnter fun()
---@return table panel
function M.Create(onEnter)
    onEnterCallback_ = onEnter
    enterEnabled_ = false
    fireballs_    = {}

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr   = graphics:GetDPR()
    local screenW = physW / dpr
    local screenH = physH / dpr

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

    -- 1) 静态背景图
    startScreen_:AddChild(UI.Panel {
        backgroundImage = "image/start_fire_f4_20260422063329.png",
        backgroundFit   = "cover",
        width           = "100%",
        height          = "100%",
        position        = "absolute",
        top = 0, left = 0,
    })

    -- 2) 火球动画层（两颗火球错开飞行）
    for i = 1, 2 do
        local fbPanel = UI.Panel {
            width           = FB_W,
            height          = FB_H,
            position        = "absolute",
            top = -FB_H, left = 0,
            pointerEvents   = "none",
            backgroundImage = FIREBALL_IMG,
            backgroundFit   = "contain",
            opacity         = (i == 1) and 0.9 or 0.6,
        }
        startScreen_:AddChild(fbPanel)
        local fb = { panel = fbPanel, x = 0, y = 0, scale = (i == 1) and 1.0 or 0.7 }
        resetFireball(fb, screenW, screenH, (i - 1) * 0.5)
        -- 第二颗初始偏移一段距离，模拟已在飞行中
        if i == 2 then
            fb.x = fb.x + FB_VX * 1.8
            fb.y = fb.y + FB_VY * 1.8
        end
        fireballs_[i] = fb
    end

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

--- 每帧更新 — 驱动火球飞行动画
---@param dt number
function M.Update(dt)
    if #fireballs_ == 0 then return end

    local physW = graphics:GetWidth()
    local physH = graphics:GetHeight()
    local dpr   = graphics:GetDPR()
    local screenW = physW / dpr
    local screenH = physH / dpr

    for i, fb in ipairs(fireballs_) do
        fb.x = fb.x + FB_VX * dt
        fb.y = fb.y + FB_VY * dt

        -- 飞出屏幕左下角后重置到右上角
        local w = FB_W * fb.scale
        local h = FB_H * fb.scale
        if fb.x < -w or fb.y > screenH + h then
            resetFireball(fb, screenW, screenH, (i - 1) * 0.5)
        end

        -- 更新面板位置
        fb.panel:SetStyle({
            left   = math.floor(fb.x),
            top    = math.floor(fb.y),
            width  = math.floor(w),
            height = math.floor(h),
        })
    end
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
