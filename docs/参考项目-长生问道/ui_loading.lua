-- ============================================================================
-- 《问道长生》全局加载遮罩
-- NanoVG 金色圆点旋转动画 + 自定义提示文字
-- 统一拦截异步操作，超过阈值自动显示加载提示
-- 用法：Loading.Start("提示文字") → 异步操作 → Loading.Stop()
-- ============================================================================

local UI = require("urhox-libs/UI")
local NVG = require("nvg_manager")
local Theme = require("ui_theme")

local M = {}

-- 配置
local DELAY = 1.5             -- 超过此秒数才显示遮罩
local MIN_DISPLAY = 0.8       -- 最短显示时长（避免闪烁）

-- 动画配置
local DOT_COUNT   = 10        -- 圆点数量
local DOT_RADIUS  = 5         -- 单个圆点半径
local RING_RADIUS = 28        -- 环形半径
local FADE_SPEED  = 3.0       -- 渐入速度

-- 状态
local active_     = false     -- 是否有操作正在进行
local refCount_   = 0         -- 引用计数：Start +1，Stop -1，归零才真正隐藏
local elapsed_    = 0         -- 已等待时长
local visible_    = false     -- 遮罩是否已显示（NanoVG 渲染中）
local message_    = ""        -- 显示文字
local container_  = nil       -- UI 容器（拦截点击）
local animElapsed_ = 0        -- 动画累计时间
local fadeAlpha_   = 0        -- 渐入透明度 0→1
local displayTime_ = 0        -- 已显示时长（用于最短显示判定）
local pendingStop_ = false    -- 有未处理的 Stop 请求（等待最短显示后执行）

-- 前向声明（内部函数互相引用）
local DoShow
local DoHide

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
function M.Render(ctx)
    if not visible_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local alpha = math.min(fadeAlpha_, 1.0)

    -- 半透明黑色背景
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(140 * alpha)))
    nvgFill(ctx)

    -- 居中偏上的位置
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

        nvgBeginPath(ctx)
        nvgCircle(ctx, dx, dy, DOT_RADIUS * (0.5 + 0.5 * dotAlpha))
        nvgFillColor(ctx, nvgRGBA(200, 170, 80, a))
        nvgFill(ctx)
    end

    -- 提示文字
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 16)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(200, 190, 160, math.floor(200 * alpha)))
    nvgText(ctx, cx, cy + RING_RADIUS + 20, message_)
end

-- ============================================================================
-- 动画更新（NVG.Register 的 updateFn）
-- ============================================================================
function M.UpdateAnim(dt)
    if not visible_ then return end
    animElapsed_ = animElapsed_ + dt
    fadeAlpha_ = fadeAlpha_ + dt * FADE_SPEED
    if fadeAlpha_ > 1.0 then fadeAlpha_ = 1.0 end
    displayTime_ = displayTime_ + dt

    -- 检查待处理的 Stop 请求
    if pendingStop_ and displayTime_ >= MIN_DISPLAY then
        DoHide()
    end
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

    -- 注册 NanoVG 渲染
    NVG.Register("loading_overlay", M.Render, M.UpdateAnim)

    -- 添加点击拦截层
    RebuildBlocker()
    print("[Loading] 加载遮罩已显示: " .. message_)
end

DoHide = function()
    if not visible_ then return end
    visible_ = false
    active_ = false
    refCount_ = 0
    elapsed_ = 0
    customDelay_ = nil
    animElapsed_ = 0
    fadeAlpha_ = 0
    displayTime_ = 0
    pendingStop_ = false

    -- 注销 NanoVG 渲染
    NVG.Unregister("loading_overlay")

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
---@param delay? number 延迟显示秒数，默认 DELAY(1.5s)
function M.Start(msg, delay)
    refCount_ = refCount_ + 1
    message_ = msg or "加载中..."
    customDelay_ = delay or nil
    if not active_ then
        -- 首次激活：重置计时
        active_ = true
        elapsed_ = 0
        pendingStop_ = false
    end
    -- 已经 active 时不重置 elapsed_，避免连续点击不断推迟显示阈值
    -- 不立即显示，等 Update 计时超过阈值
end

-- ============================================================================
-- 结束加载
-- ============================================================================
function M.Stop()
    if not active_ then return end
    refCount_ = math.max(0, refCount_ - 1)
    -- 引用计数未归零，还有其他请求在进行中
    if refCount_ > 0 then return end
    -- 引用计数归零，真正停止
    -- 如果遮罩还没显示，直接清理
    if not visible_ then
        active_ = false
        elapsed_ = 0
        customDelay_ = nil
        return
    end
    -- 遮罩已显示，检查最短显示时长
    if displayTime_ >= MIN_DISPLAY then
        DoHide()
    else
        pendingStop_ = true
    end
end

-- ============================================================================
-- 强制停止（断线等异常场景，忽略引用计数和最短显示）
-- ============================================================================
function M.ForceStop()
    refCount_ = 0
    if visible_ then
        DoHide()
    else
        active_ = false
        elapsed_ = 0
        customDelay_ = nil
        pendingStop_ = false
    end
end

-- ============================================================================
-- 立即显示（跳过延迟）
-- ============================================================================
---@param msg? string 提示文字
function M.ShowNow(msg)
    refCount_ = refCount_ + 1
    message_ = msg or "加载中..."
    active_ = true
    elapsed_ = DELAY  -- 跳过延迟
    pendingStop_ = false
    if not visible_ then
        DoShow()
    end
end

-- ============================================================================
-- 每帧更新（由 main.lua 的 NVG updater 驱动）
-- ============================================================================
function M.Update(dt)
    if not active_ then return end
    if visible_ then return end  -- 已显示则由 UpdateAnim 接管
    elapsed_ = elapsed_ + dt
    if elapsed_ >= (customDelay_ or DELAY) then
        DoShow()
    end
end

-- ============================================================================
-- 获取容器（overlay provider 调用，每次 RebuildUI 时重建）
-- ============================================================================
function M.GetContainer()
    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "box-none",
    }
    -- 如果已激活且正在显示，重建拦截层
    if visible_ then
        RebuildBlocker()
    end
    return container_
end

return M
