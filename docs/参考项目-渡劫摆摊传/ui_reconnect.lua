-- ============================================================================
-- 《渡劫摆摊传》断线重连遮罩
-- NanoVG 绘制全屏遮罩 + 金色圆点旋转加载动画
-- 独立 nvgCreate 模式（不依赖 nvg_manager）
-- 阻止断线期间误操作 UI
-- ============================================================================

local UI = require("urhox-libs/UI")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local active_    = false   -- 是否激活
local elapsed_   = 0       -- 动画累计时间
local container_ = nil     -- UI 遮罩容器（拦截点击）
local fadeAlpha_ = 0       -- 渐入透明度 0→1
local vg_        = nil     -- NanoVG 上下文
local fontReady_ = false   -- 字体是否已创建
local nvgActive_ = false   -- NanoVG 渲染回调是否已注册

-- 配置
local DOT_COUNT      = 10     -- 圆点数量
local DOT_RADIUS     = 5      -- 单个圆点半径
local RING_RADIUS    = 28     -- 环形半径
local FADE_SPEED     = 3.0    -- 渐入速度
local TIMEOUT        = 10.0   -- 超时秒数，超时后提示点击重试
local timedOut_      = false  -- 是否已超时
local onRetryCallback_ = nil  -- 重试回调

-- NanoVG render order: 重连遮罩比 Loading(999996) 更高
local RENDER_ORDER = 999997

-- ============================================================================
-- 初始化（只调用一次）
-- ============================================================================
function M.Init()
    vg_ = nvgCreate(1)
    if vg_ then
        nvgSetRenderOrder(vg_, RENDER_ORDER)
        nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
        fontReady_ = true
        print("[ReconnectOverlay] NanoVG 初始化完成")
    else
        print("[ReconnectOverlay] NanoVG 创建失败!")
    end
end

-- ============================================================================
-- UI 遮罩容器（拦截所有点击事件）
-- ============================================================================
local function RebuildContainer()
    if not container_ then return end
    container_:ClearChildren()
    if not active_ then return end

    local blocker = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 1 },
        onClick = function(self)
            if timedOut_ and onRetryCallback_ then
                print("[ReconnectOverlay] 用户点击重试")
                -- 重置超时状态，重新开始计时
                timedOut_ = false
                elapsed_ = 0
                RebuildContainer()
                onRetryCallback_()
            end
        end,
    }
    container_:AddChild(blocker)
end

-- ============================================================================
-- NanoVG 渲染：圆点旋转加载动画
-- ============================================================================
function HandleReconnectOverlayRender(eventType, eventData)
    if not active_ or not vg_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local alpha = math.min(fadeAlpha_, 1.0)

    nvgBeginFrame(vg_, sw, sh, dpr)

    -- 半透明黑色背景
    nvgBeginPath(vg_)
    nvgRect(vg_, 0, 0, sw, sh)
    nvgFillColor(vg_, nvgRGBA(0, 0, 0, math.floor(160 * alpha)))
    nvgFill(vg_)

    -- 居中偏上
    local cx = sw * 0.5
    local cy = sh * 0.45

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

        nvgBeginPath(vg_)
        nvgCircle(vg_, dx, dy, DOT_RADIUS * (0.5 + 0.5 * dotAlpha))
        nvgFillColor(vg_, nvgRGBA(200, 170, 80, a))
        nvgFill(vg_)
    end

    -- 文字提示
    if fontReady_ then
        nvgFontFace(vg_, "sans")
        nvgFontSize(vg_, 16)
        nvgTextAlign(vg_, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        nvgFillColor(vg_, nvgRGBA(200, 190, 160, math.floor(200 * alpha)))
        if timedOut_ then
            nvgText(vg_, cx, cy + RING_RADIUS + 20, "连接超时，点击屏幕重试")
        else
            nvgText(vg_, cx, cy + RING_RADIUS + 20, "正在重新连接...")
        end
    end

    nvgEndFrame(vg_)
end

-- ============================================================================
-- 开始显示遮罩
-- ============================================================================
function M.Show()
    if active_ then return end
    active_ = true
    elapsed_ = 0
    fadeAlpha_ = 0
    timedOut_ = false

    -- 注册 NanoVG 渲染回调
    if vg_ and not nvgActive_ then
        SubscribeToEvent(vg_, "NanoVGRender", "HandleReconnectOverlayRender")
        nvgActive_ = true
    end

    RebuildContainer()
    print("[ReconnectOverlay] 断线遮罩已显示")
end

-- ============================================================================
-- 隐藏遮罩
-- ============================================================================
function M.Hide()
    if not active_ then return end
    active_ = false
    elapsed_ = 0
    fadeAlpha_ = 0

    -- 注销 NanoVG 渲染
    if vg_ and nvgActive_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        nvgActive_ = false
    end

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
-- 设置重试回调
-- ============================================================================
function M.OnRetry(callback)
    onRetryCallback_ = callback
end

-- ============================================================================
-- 每帧更新（由 main.lua 的 HandleUpdate 驱动）
-- ============================================================================
function M.Update(dt)
    if not active_ then return end
    elapsed_ = elapsed_ + dt
    fadeAlpha_ = fadeAlpha_ + dt * FADE_SPEED
    if fadeAlpha_ > 1.0 then fadeAlpha_ = 1.0 end

    -- 超时检测
    if not timedOut_ and elapsed_ >= TIMEOUT then
        timedOut_ = true
        print("[ReconnectOverlay] 超时 (" .. TIMEOUT .. "s)，等待用户点击重试")
        RebuildContainer()   -- 重建容器以注册点击回调
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
