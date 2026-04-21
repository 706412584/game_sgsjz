-- ============================================================================
-- 《渡劫摆摊传》全局加载遮罩
-- NanoVG 金色圆点旋转动画 + 自定义提示文字
-- 独立 nvgCreate 模式（不依赖 nvg_manager）
-- 用法：Loading.Start("提示文字") → 异步操作 → Loading.Stop()
-- ============================================================================

local UI = require("urhox-libs/UI")

local M = {}

-- 配置
local DELAY       = 1.5        -- 超过此秒数才显示遮罩
local MIN_DISPLAY = 0.8        -- 最短显示时长（避免闪烁）

-- 动画配置
local DOT_COUNT   = 10         -- 圆点数量
local DOT_RADIUS  = 5          -- 单个圆点半径
local RING_RADIUS = 28         -- 环形半径
local FADE_SPEED  = 3.0        -- 渐入速度

-- 状态
local active_      = false     -- 是否有操作正在进行
local elapsed_     = 0         -- 已等待时长
local visible_     = false     -- NanoVG 渲染是否已激活
local message_     = ""        -- 显示文字
local container_   = nil       -- UI 容器（拦截点击）
local animElapsed_ = 0         -- 动画累计时间
local fadeAlpha_   = 0         -- 渐入透明度 0→1
local displayTime_ = 0         -- 已显示时长
local pendingStop_ = false     -- 有未处理的 Stop 请求
local vg_          = nil       -- NanoVG 上下文
local fontReady_   = false     -- 字体是否已创建
local nvgActive_   = false     -- NanoVG 渲染回调是否已注册

-- NanoVG render order: Loading 比 Toast(999995) 更高
local RENDER_ORDER = 999996

-- 前向声明
local DoShow
local DoHide

-- ============================================================================
-- 初始化（只调用一次）
-- ============================================================================
function M.Init()
    vg_ = nvgCreate(1)
    if vg_ then
        nvgSetRenderOrder(vg_, RENDER_ORDER)
        nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
        fontReady_ = true
        print("[Loading] NanoVG 初始化完成")
    else
        print("[Loading] NanoVG 创建失败!")
    end
end

-- ============================================================================
-- UI 拦截容器
-- ============================================================================
local function RebuildBlocker()
    if not container_ then return end
    container_:ClearChildren()
    if not visible_ then return end

    local blocker = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 1 },
    }
    container_:AddChild(blocker)
end

-- ============================================================================
-- NanoVG 渲染：金色圆点旋转加载动画
-- ============================================================================
function HandleLoadingOverlayRender(eventType, eventData)
    if not visible_ or not vg_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local alpha = math.min(fadeAlpha_, 1.0)

    nvgBeginFrame(vg_, sw, sh, dpr)

    -- 半透明黑色背景
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, sw, sh)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(140 * alpha)))
    nvgFill(vg_)

    -- 居中偏上
    local cx = sw * 0.5
    local cy = sh * 0.45

    -- 绘制圆点环形
    for i = 0, DOT_COUNT - 1 do
        local angle = (i / DOT_COUNT) * math.pi * 2 - math.pi * 0.5
        local rotOffset = animElapsed_ * 2.5
        angle = angle + rotOffset

        local dx = cx + math.cos(angle) * RING_RADIUS
        local dy = cy + math.sin(angle) * RING_RADIUS

        -- 每个点的透明度：尾部淡出效果
        local dotAlpha = ((DOT_COUNT - i) / DOT_COUNT)
        dotAlpha = dotAlpha * dotAlpha
        local a = math.floor(255 * dotAlpha * alpha)

        nvgBeginPath(vg_)
        nvgCircle(vg_, dx, dy, DOT_RADIUS * (0.5 + 0.5 * dotAlpha))
        nvgFillColor(vg_, nvgRGBA(200, 170, 80, a))
        nvgFill(vg_)
    end

    -- 提示文字
    if fontReady_ then
        nvgFontFace(vg_, "sans")
        nvgFontSize(vg_, 16)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg_, nvgRGBA(200, 190, 160, math.floor(200 * alpha)))
        nvgText(vg_, cx, cy + RING_RADIUS + 20, message_)
    end

    nvgEndFrame(vg_)
end

-- ============================================================================
-- 内部：显示/隐藏
-- ============================================================================
DoShow = function()
    if visible_ then return end
    visible_ = true
    animElapsed_ = 0
    fadeAlpha_ = 0
    displayTime_ = 0

    -- 注册 NanoVG 渲染回调
    if vg_ and not nvgActive_ then
        SubscribeToEvent(vg_, "NanoVGRender", "HandleLoadingOverlayRender")
        nvgActive_ = true
    end

    -- 添加点击拦截层
    RebuildBlocker()
    print("[Loading] 加载遮罩已显示: " .. message_)
end

DoHide = function()
    if not visible_ then return end
    visible_ = false
    active_ = false
    elapsed_ = 0
    animElapsed_ = 0
    fadeAlpha_ = 0
    displayTime_ = 0
    pendingStop_ = false

    -- 注销 NanoVG 渲染回调
    if vg_ and nvgActive_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        nvgActive_ = false
    end

    -- 清空拦截层
    if container_ then
        container_:ClearChildren()
    end
    print("[Loading] 加载遮罩已隐藏")
end

-- ============================================================================
-- 开始一次加载
-- ============================================================================
---@param msg? string 提示文字，默认 "加载中..."
function M.Start(msg)
    message_ = msg or "加载中..."
    active_ = true
    elapsed_ = 0
    pendingStop_ = false
end

-- ============================================================================
-- 结束加载
-- ============================================================================
function M.Stop()
    if not active_ then return end
    if not visible_ then
        active_ = false
        elapsed_ = 0
        return
    end
    if displayTime_ >= MIN_DISPLAY then
        DoHide()
    else
        pendingStop_ = true
    end
end

-- ============================================================================
-- 立即显示（跳过延迟）
-- ============================================================================
---@param msg? string 提示文字
function M.ShowNow(msg)
    message_ = msg or "加载中..."
    active_ = true
    elapsed_ = DELAY
    pendingStop_ = false
    if not visible_ then
        DoShow()
    end
end

-- ============================================================================
-- 每帧更新（由 main.lua 的 HandleUpdate 驱动）
-- ============================================================================
function M.Update(dt)
    -- 延迟显示逻辑
    if active_ and not visible_ then
        elapsed_ = elapsed_ + dt
        if elapsed_ >= DELAY then
            DoShow()
        end
    end

    -- 动画更新
    if visible_ then
        animElapsed_ = animElapsed_ + dt
        fadeAlpha_ = fadeAlpha_ + dt * FADE_SPEED
        if fadeAlpha_ > 1.0 then fadeAlpha_ = 1.0 end
        displayTime_ = displayTime_ + dt

        if pendingStop_ and displayTime_ >= MIN_DISPLAY then
            DoHide()
        end
    end
end

-- ============================================================================
-- 获取容器（overlay provider 调用）
-- ============================================================================
function M.GetContainer()
    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "box-none",
    }
    if visible_ then
        RebuildBlocker()
    end
    return container_
end

return M
