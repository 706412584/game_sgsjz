-- ============================================================================
-- ui_toast.lua — 修仙国风全局 Toast 系统
-- 屏幕居中弹出 → 向上飘动 → 淡出消失，支持多条堆叠
-- 用法: local XToast = require("ui_toast")
--       XToast.Show("突破成功!", { variant = "success" })
-- ============================================================================
local Config = require("data_config")

local M = {}

-- ========== Toast 队列 ==========
local toasts = {}
local nextId = 1
local vg = nil
local fontReady = false

-- ========== 配置 ==========
local MAX_TOASTS = 6
local DEFAULT_DURATION = 2.0
local TOAST_HEIGHT = 36
local TOAST_GAP = 6
local FLOAT_SPEED = 25         -- 向上飘动速度(像素/秒)
local ENTER_DURATION = 0.25    -- 入场动画时长
local EXIT_DURATION = 0.4      -- 退出淡出时长

-- ========== 修仙配色方案 ==========
local VARIANT_STYLES = {
    success = {
        bg = { 30, 45, 35, 220 },
        border = { 120, 200, 140, 180 },
        text = { 180, 255, 200, 255 },
        icon = "check",
        glow = { 88, 199, 155 },
    },
    warning = {
        bg = { 50, 40, 20, 220 },
        border = { 218, 185, 107, 180 },
        text = { 255, 230, 160, 255 },
        icon = "warn",
        glow = { 218, 185, 107 },
    },
    error = {
        bg = { 50, 25, 25, 220 },
        border = { 220, 100, 90, 180 },
        text = { 255, 180, 170, 255 },
        icon = "cross",
        glow = { 220, 80, 75 },
    },
    info = {
        bg = { 25, 35, 55, 220 },
        border = { 120, 170, 230, 180 },
        text = { 180, 210, 255, 255 },
        icon = "info",
        glow = { 80, 150, 230 },
    },
}

-- ========== 内部工具 ==========

---@param variant string
---@param customColor table|nil
---@param customBg table|nil
---@return table
local function getStyle(variant, customColor, customBg)
    local base = VARIANT_STYLES[variant] or VARIANT_STYLES.info
    local style = {
        bg = customBg or base.bg,
        border = base.border,
        text = customColor or base.text,
        icon = base.icon,
        glow = base.glow,
    }
    if customBg then
        style.border = { math.min(255, customBg[1] + 40), math.min(255, customBg[2] + 40), math.min(255, customBg[3] + 40), 180 }
        style.glow = { math.min(255, customBg[1] + 60), math.min(255, customBg[2] + 60), math.min(255, customBg[3] + 60) }
    end
    return style
end

--- easeOutQuad
local function easeOutQuad(t)
    return 1 - (1 - t) * (1 - t)
end

-- ========== 公开接口 ==========

--- 显示 Toast
---@param message string
---@param options table|nil
function M.Show(message, options)
    options = options or {}
    local variant = options.variant or options.type or "info"
    local duration = options.duration or DEFAULT_DURATION

    local toast = {
        id = nextId,
        message = message or "",
        variant = variant,
        duration = duration,
        customColor = options.color,
        customBg = options.bgColor,
        elapsed = 0,           -- 已经过时间
        totalLife = ENTER_DURATION + duration + EXIT_DURATION,
        offsetY = 0,           -- 向上飘动累计偏移
    }
    nextId = nextId + 1

    -- 限制最大数量，移除最旧的
    while #toasts >= MAX_TOASTS do
        table.remove(toasts, 1)
    end

    table.insert(toasts, toast)
    return toast.id
end

--- 初始化
function M.Init()
    vg = nvgCreate(1)
    if vg then
        nvgSetRenderOrder(vg, 999995)
        nvgCreateFont(vg, "sans", "Fonts/MiSans-Regular.ttf")
        fontReady = true
        SubscribeToEvent(vg, "NanoVGRender", "HandleXiuxianToastRender")
    end
end

-- ========== 更新逻辑 ==========

---@param dt number
function M.Update(dt)
    for i = #toasts, 1, -1 do
        local t = toasts[i]
        t.elapsed = t.elapsed + dt
        -- 向上飘动(进入完成后开始飘)
        if t.elapsed > ENTER_DURATION then
            t.offsetY = t.offsetY + FLOAT_SPEED * dt
        end
        -- 生命周期结束
        if t.elapsed >= t.totalLife then
            table.remove(toasts, i)
        end
    end
end

-- ========== 渲染 ==========

--- 绘制图标
---@param iconType string
---@param cx number
---@param cy number
---@param r number
---@param color table
---@param alpha number
local function drawIcon(iconType, cx, cy, r, color, alpha)
    local a = math.floor(alpha * 255)
    local cr, cg, cb = color[1], color[2], color[3]

    if iconType == "check" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - r * 0.35, cy)
        nvgLineTo(vg, cx - r * 0.05, cy + r * 0.3)
        nvgLineTo(vg, cx + r * 0.4, cy - r * 0.25)
        nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, a))
        nvgStrokeWidth(vg, 2)
        nvgLineCap(vg, NVG_ROUND)
        nvgLineJoin(vg, NVG_ROUND)
        nvgStroke(vg)
    elseif iconType == "cross" then
        local s = r * 0.28
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx - s, cy - s)
        nvgLineTo(vg, cx + s, cy + s)
        nvgMoveTo(vg, cx + s, cy - s)
        nvgLineTo(vg, cx - s, cy + s)
        nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, a))
        nvgStrokeWidth(vg, 2)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    elseif iconType == "warn" then
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - r * 0.35)
        nvgLineTo(vg, cx, cy + r * 0.05)
        nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, a))
        nvgStrokeWidth(vg, 2.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy + r * 0.35, 1.5)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, a))
        nvgFill(vg)
    else -- info
        nvgBeginPath(vg)
        nvgCircle(vg, cx, cy - r * 0.35, 1.5)
        nvgFillColor(vg, nvgRGBA(cr, cg, cb, a))
        nvgFill(vg)
        nvgBeginPath(vg)
        nvgMoveTo(vg, cx, cy - r * 0.05)
        nvgLineTo(vg, cx, cy + r * 0.35)
        nvgStrokeColor(vg, nvgRGBA(cr, cg, cb, a))
        nvgStrokeWidth(vg, 2.5)
        nvgLineCap(vg, NVG_ROUND)
        nvgStroke(vg)
    end
end

function HandleXiuxianToastRender(eventType, eventData)
    if #toasts == 0 or not vg then return end

    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr

    -- UI 缩放
    local uiScale = 1.0
    local shortSide = math.min(graphics:GetWidth(), graphics:GetHeight()) / dpr
    if shortSide < 500 then
        uiScale = 1.15
    end

    local toastH = TOAST_HEIGHT / uiScale
    local gap = TOAST_GAP / uiScale
    local borderRadius = 10 / uiScale
    local fontSize = 13 / uiScale
    local iconCircleR = 11 / uiScale
    local maxToastW = screenW * 0.8 / uiScale
    local minToastW = screenW * 0.35 / uiScale

    nvgBeginFrame(vg, screenW, screenH, dpr)
    nvgSave(vg)

    -- 从最新到最旧渲染，最新的在屏幕中间，旧的往上堆叠
    -- toasts 数组: 1=最旧, #toasts=最新
    local centerY = screenH * 0.42  -- 稍偏上的居中位置

    for idx = #toasts, 1, -1 do
        local t = toasts[idx]
        local style = getStyle(t.variant, t.customColor, t.customBg)

        -- 计算透明度
        local alpha = 1.0
        local scale = 1.0
        if t.elapsed < ENTER_DURATION then
            -- 入场: 从下方弹入 + 放大
            local p = t.elapsed / ENTER_DURATION
            local ease = easeOutQuad(p)
            alpha = ease
            scale = 0.8 + 0.2 * ease
        elseif t.elapsed > ENTER_DURATION + t.duration then
            -- 退出: 淡出
            local p = (t.elapsed - ENTER_DURATION - t.duration) / EXIT_DURATION
            p = math.min(1, p)
            alpha = 1 - easeOutQuad(p)
        end

        -- 堆叠位置: 从当前 toast 到最新 toast 之间有多少个，决定偏移
        local stackIndex = #toasts - idx  -- 0=最新, 1=次新...
        local stackOffsetY = stackIndex * (toastH + gap)

        -- 最终 Y: 居中 - 堆叠偏移 - 飘动偏移
        local y = centerY - stackOffsetY - t.offsetY

        -- 测量文字宽度来决定 toast 宽度
        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        local textW = nvgTextBounds(vg, 0, 0, t.message)
        local iconSpace = iconCircleR * 2 + 18
        local padRight = 14
        local toastW = math.max(minToastW, math.min(maxToastW, textW + iconSpace + padRight))

        local x = (screenW - toastW) / 2

        local bg = style.bg
        local border = style.border
        local glow = style.glow
        local textC = style.text

        -- 入场缩放
        if scale < 1.0 then
            local cx = x + toastW / 2
            local cy = y + toastH / 2
            nvgSave(vg)
            nvgTranslate(vg, cx, cy)
            nvgScale(vg, scale, scale)
            nvgTranslate(vg, -cx, -cy)
        end

        -- 外发光
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x - 2, y - 2, toastW + 4, toastH + 4, borderRadius + 2)
        nvgFillColor(vg, nvgRGBA(glow[1], glow[2], glow[3], math.floor(25 * alpha)))
        nvgFill(vg)

        -- 背景
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, toastW, toastH, borderRadius)
        nvgFillColor(vg, nvgRGBA(bg[1], bg[2], bg[3], math.floor((bg[4] or 220) * alpha)))
        nvgFill(vg)

        -- 描边
        nvgBeginPath(vg)
        nvgRoundedRect(vg, x, y, toastW, toastH, borderRadius)
        nvgStrokeColor(vg, nvgRGBA(border[1], border[2], border[3], math.floor((border[4] or 180) * alpha)))
        nvgStrokeWidth(vg, 1.0)
        nvgStroke(vg)

        -- 图标背景圆
        local iconX = x + iconCircleR + 8
        local iconY = y + toastH / 2
        nvgBeginPath(vg)
        nvgCircle(vg, iconX, iconY, iconCircleR)
        nvgFillColor(vg, nvgRGBA(glow[1], glow[2], glow[3], math.floor(35 * alpha)))
        nvgFill(vg)

        -- 图标
        drawIcon(style.icon, iconX, iconY, iconCircleR, textC, alpha)

        -- 文字
        local textX = iconX + iconCircleR + 8
        local maxTextW = toastW - (textX - x) - padRight

        nvgFontFace(vg, "sans")
        nvgFontSize(vg, fontSize)
        nvgFillColor(vg, nvgRGBA(textC[1], textC[2], textC[3], math.floor(255 * alpha)))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)

        nvgSave(vg)
        nvgIntersectScissor(vg, textX, y, maxTextW, toastH)
        nvgText(vg, textX, y + toastH / 2, t.message)
        nvgRestore(vg)

        if scale < 1.0 then
            nvgRestore(vg)
        end
    end

    nvgRestore(vg)
    nvgEndFrame(vg)
end

return M
