-- ============================================================================
-- 《问道长生》断线重连遮罩
-- NanoVG 绘制全屏遮罩 + 经典圆点旋转加载动画
-- 阻止断线期间误操作 UI；超时后提供"返回标题"入口
-- ============================================================================

local UI    = require("urhox-libs/UI")
local NVG   = require("nvg_manager")
local Theme = require("ui_theme")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local active_       = false   -- 是否激活
local elapsed_      = 0       -- 动画累计时间
local timeoutTimer_ = 0       -- 断线累计时间（秒）
local container_    = nil     -- UI 遮罩容器（拦截点击）
local fadeAlpha_    = 0       -- 渐入透明度 0→1
local showFallback_ = false   -- 是否已显示"返回标题"按钮

-- 配置
local DOT_COUNT        = 10      -- 圆点数量
local DOT_RADIUS       = 5       -- 单个圆点半径
local RING_RADIUS      = 28      -- 环形半径
local FADE_SPEED       = 3.0     -- 渐入速度
local HINT_AFTER_SECS  = 20      -- N 秒后显示"检查网络"提示
local FALLBACK_SECS    = 40      -- N 秒后显示"返回标题"按钮

-- ============================================================================
-- 开始显示遮罩
-- ============================================================================
function M.Show()
    if active_ then return end
    active_       = true
    elapsed_      = 0
    timeoutTimer_ = 0
    fadeAlpha_    = 0
    showFallback_ = false

    -- 注册 NanoVG 渲染回调
    NVG.Register("reconnect_overlay", M.Render, M.Update)

    -- 重建 UI 容器来拦截点击
    RebuildContainer()
    print("[ReconnectOverlay] 断线遮罩已显示")
end

-- ============================================================================
-- 隐藏遮罩
-- ============================================================================
function M.Hide()
    if not active_ then return end
    active_       = false
    elapsed_      = 0
    timeoutTimer_ = 0
    fadeAlpha_    = 0
    showFallback_ = false

    -- 注销 NanoVG 渲染
    NVG.Unregister("reconnect_overlay")

    -- 清空 UI 容器
    if container_ then
        container_:ClearChildren()
    end
    print("[ReconnectOverlay] 断线遮罩已隐藏")
end

-- ============================================================================
-- 是否激活
-- ============================================================================
function M.IsActive()
    return active_
end

-- ============================================================================
-- NanoVG 渲染：圆点旋转加载动画 + 超时提示
-- ============================================================================
function M.Render(ctx)
    if not active_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local alpha = math.min(fadeAlpha_, 1.0)

    -- 半透明黑色背景
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, sw, sh)
    nvgFillColor(ctx, nvgRGBA(0, 0, 0, math.floor(175 * alpha)))
    nvgFill(ctx)

    -- 居中偏上的位置
    local cx = sw * 0.5
    local cy = sh * 0.42

    -- 绘制圆点环形
    for i = 0, DOT_COUNT - 1 do
        local angle = (i / DOT_COUNT) * math.pi * 2 - math.pi * 0.5
        local rotOffset = elapsed_ * 2.5
        angle = angle + rotOffset

        local dx = cx + math.cos(angle) * RING_RADIUS
        local dy = cy + math.sin(angle) * RING_RADIUS

        local dotAlpha = ((DOT_COUNT - i) / DOT_COUNT)
        dotAlpha = dotAlpha * dotAlpha
        local a = math.floor(255 * dotAlpha * alpha)

        nvgBeginPath(ctx)
        nvgCircle(ctx, dx, dy, DOT_RADIUS * (0.5 + 0.5 * dotAlpha))
        nvgFillColor(ctx, nvgRGBA(200, 170, 80, a))
        nvgFill(ctx)
    end

    -- 主文字
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFontSize(ctx, 16)
    nvgFillColor(ctx, nvgRGBA(200, 190, 160, math.floor(200 * alpha)))
    nvgText(ctx, cx, cy + RING_RADIUS + 18, "正在重新连接...")

    -- 断线时长（10s 后显示）
    if timeoutTimer_ >= 10 then
        local secA = math.min(1.0, (timeoutTimer_ - 10) / 3.0) * alpha
        nvgFontSize(ctx, 13)
        nvgFillColor(ctx, nvgRGBA(160, 150, 130, math.floor(180 * secA)))
        nvgText(ctx, cx, cy + RING_RADIUS + 42,
            string.format("已断线 %.0f 秒", timeoutTimer_))
    end

    -- 网络检查提示（HINT_AFTER_SECS 秒后）
    if timeoutTimer_ >= HINT_AFTER_SECS then
        local hintA = math.min(1.0, (timeoutTimer_ - HINT_AFTER_SECS) / 4.0) * alpha
        nvgFontSize(ctx, 13)
        nvgFillColor(ctx, nvgRGBA(220, 140, 80, math.floor(210 * hintA)))
        nvgText(ctx, cx, cy + RING_RADIUS + 64, "请检查网络连接后稍候...")
    end
end

-- ============================================================================
-- 每帧更新
-- ============================================================================
function M.Update(dt)
    if not active_ then return end
    elapsed_      = elapsed_ + dt
    timeoutTimer_ = timeoutTimer_ + dt
    fadeAlpha_    = math.min(1.0, fadeAlpha_ + dt * FADE_SPEED)

    -- 超过 FALLBACK_SECS 且尚未显示"返回标题"按钮 → 重建容器加入按钮
    if timeoutTimer_ >= FALLBACK_SECS and not showFallback_ then
        showFallback_ = true
        RebuildContainer()
        print("[ReconnectOverlay] 超时，显示返回标题按钮")
    end
end

-- ============================================================================
-- UI 遮罩容器（拦截点击 + 超时后提供返回标题按钮）
-- ============================================================================
function RebuildContainer()
    if not container_ then return end
    container_:ClearChildren()
    if not active_ then return end

    local children = {}

    -- 全屏透明面板拦截触摸/点击
    children[#children + 1] = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 1 },
    }

    -- 超时后：在底部显示"返回标题"按钮
    if showFallback_ then
        children[#children + 1] = UI.Panel {
            position = "absolute",
            left = 0, right = 0, bottom = 80,
            alignItems = "center",
            pointerEvents = "box-none",
            children = {
                UI.Button {
                    text      = "返回标题",
                    variant   = "secondary",
                    width     = 140,
                    height    = 44,
                    fontSize  = 15,
                    onClick   = function()
                        print("[ReconnectOverlay] 用户主动返回标题")
                        M.Hide()
                        local Router = require("ui_router")
                        Router.EnterState(Router.STATE_TITLE)
                    end,
                },
            },
        }
    end

    for _, child in ipairs(children) do
        container_:AddChild(child)
    end
end

-- ============================================================================
-- 获取容器（由 overlay provider 调用）
-- ============================================================================
function M.GetContainer()
    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "box-none",
    }
    if active_ then
        RebuildContainer()
    end
    return container_
end

return M
