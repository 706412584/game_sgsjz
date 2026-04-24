-- ============================================================================
-- 《问道长生》全局 Toast 通知组件
-- 支持 variant 主题色（success/error/info/默认）
-- 支持 <c=gold>关键文字</c> 颜色标签实现关键信息高亮
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local RT = require("rich_text")

local M = {}

-- 配置
local STAY_DURATION = 1.8     -- 中央停留时间（秒），无新消息时自然消失
local FADE_IN = 0.15          -- 新消息淡入时长
local FADE_OUT_UP = 0.3       -- 旧消息上移淡出时长
local SLIDE_UP_DIST = 50      -- 旧消息上移距离（px）
local DEBOUNCE = 0.05         -- 防抖间隔（50ms）
local MAX_VISIBLE = 3         -- 最多同时显示的 toast 数

-- 状态
local toasts_ = {}            -- { { element, fading } }
local container_ = nil
local lastShowTime_ = -1      -- 上次显示时间戳（防抖用）
local elapsed_ = 0            -- 累计时间（用于防抖判断）

-- 当前中央消息
local centerToast_ = nil      -- 当前占据中央的 toast 引用

-- ============================================================================
-- Variant 主题配置
-- ============================================================================
local VARIANTS = {
    default = {
        bg       = { 25, 22, 18, 220 },
        border   = { 180, 150, 80, 120 },
        text     = { 230, 210, 140, 255 },
        prefix   = "",
    },
    success = {
        bg       = { 20, 35, 20, 230 },
        border   = { 80, 180, 80, 150 },
        text     = { 140, 230, 140, 255 },
        prefix   = "",
    },
    error = {
        bg       = { 40, 20, 20, 230 },
        border   = { 200, 80, 80, 150 },
        text     = { 240, 140, 140, 255 },
        prefix   = "",
    },
    info = {
        bg       = { 20, 25, 40, 220 },
        border   = { 100, 140, 200, 140 },
        text     = { 160, 200, 240, 255 },
        prefix   = "",
    },
}

-- ============================================================================
-- 解析颜色标签（委托 rich_text.lua 统一解析器）
-- 返回 { {text, fontColor}, ... } 格式（兼容 BuildLabelChildren）
-- ============================================================================
local function ParseColorTags(text, defaultColor)
    local rawSegs = RT.Parse(text, defaultColor)
    local out = {}
    for _, seg in ipairs(rawSegs) do
        out[#out + 1] = { text = seg.value, fontColor = seg.color or defaultColor }
    end
    return out
end

-- ============================================================================
-- 创建容器
-- ============================================================================
local function EnsureContainer()
    if container_ then return end
    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "none",
        alignItems = "center",
        justifyContent = "center",
    }
end

-- ============================================================================
-- 将一条 toast 从容器中移除
-- ============================================================================
local function RemoveToast(t)
    if t.element and container_ then
        container_:RemoveChild(t.element)
    end
    for j, tt in ipairs(toasts_) do
        if tt == t then
            table.remove(toasts_, j)
            break
        end
    end
    if centerToast_ == t then
        centerToast_ = nil
    end
end

-- ============================================================================
-- 旧消息淡出上移动画
-- ============================================================================
local function DismissUp(t)
    if t.fading then return end
    t.fading = true
    t.element:Animate({
        keyframes = {
            [0] = { opacity = 1, translateY = 0 },
            [1] = { opacity = 0, translateY = -SLIDE_UP_DIST },
        },
        duration = FADE_OUT_UP,
        easing = "easeIn",
        fillMode = "forwards",
        onComplete = function()
            RemoveToast(t)
        end,
    })
end

-- ============================================================================
-- 根据 segments 构建子元素列表（多段不同颜色的 Label 横排）
-- ============================================================================
local function BuildLabelChildren(segments)
    local children = {}
    for _, seg in ipairs(segments) do
        children[#children + 1] = UI.Label {
            text = seg.text,
            fontSize = 14,
            fontWeight = "bold",
            fontColor = seg.fontColor,
        }
    end
    return children
end

-- ============================================================================
-- 显示一条 Toast
-- text: 显示文字，支持 <c=gold>高亮</c> 标签
-- opts: 可选 { fontColor = {r,g,b,a}, variant = "success"|"error"|"info" }
-- ============================================================================
function M.Show(text, opts)
    -- 空消息拦截
    if text == nil or text == "" then return end
    local textStr = tostring(text)
    if textStr == "" or textStr == "nil" then return end

    EnsureContainer()
    -- 支持字符串简写: Toast.Show("msg", "success") → { variant = "success" }
    if type(opts) == "string" then
        opts = { variant = opts }
    end
    opts = opts or {}

    -- 去重：与当前中央消息内容相同则忽略
    if centerToast_ and not centerToast_.fading and centerToast_.text == textStr then
        centerToast_.timer = 0  -- 重置计时器延长显示
        return
    end

    -- 选择主题
    local variant = VARIANTS[opts.variant or "default"] or VARIANTS.default

    -- 文本颜色优先级：opts.fontColor > variant.text
    local baseColor = opts.fontColor or variant.text

    -- 加前缀
    local fullText = variant.prefix .. textStr

    -- 解析颜色标签
    local segments = ParseColorTags(fullText, baseColor)

    -- 把当前中央消息推走（淡出上移）
    if centerToast_ and not centerToast_.fading then
        DismissUp(centerToast_)
    end

    -- 超出最大显示数量时，立即移除最早的
    while #toasts_ >= MAX_VISIBLE do
        local oldest = toasts_[1]
        if oldest then
            RemoveToast(oldest)
        else
            break
        end
    end

    -- 创建新 Toast 元素
    local el = UI.Panel {
        paddingLeft = 24, paddingRight = 24,
        paddingTop = 8, paddingBottom = 8,
        borderRadius = 18,
        backgroundColor = variant.bg,
        borderColor = variant.border,
        borderWidth = 1,
        justifyContent = "center",
        alignItems = "center",
        flexDirection = "row",
        opacity = 0,
        pointerEvents = "none",
        children = BuildLabelChildren(segments),
    }

    container_:AddChild(el)

    local toast = { element = el, timer = 0, fading = false, text = textStr }
    toasts_[#toasts_ + 1] = toast
    centerToast_ = toast

    -- 淡入动画
    el:Animate({
        keyframes = {
            [0] = { opacity = 0, translateY = 12 },
            [1] = { opacity = 1, translateY = 0 },
        },
        duration = FADE_IN,
        easing = "easeOut",
        fillMode = "forwards",
    })

    lastShowTime_ = elapsed_
end

-- ============================================================================
-- 更新（每帧调用）
-- ============================================================================
function M.Update(dt)
    elapsed_ = elapsed_ + dt

    -- 中央消息自然消失（超过停留时间且没有新消息挤它）
    if centerToast_ and not centerToast_.fading then
        centerToast_.timer = centerToast_.timer + dt
        if centerToast_.timer >= STAY_DURATION then
            DismissUp(centerToast_)
        end
    end

    -- 处理待显示队列
    if M._pendingQueue then
        local allDone = true
        for _, item in ipairs(M._pendingQueue) do
            if not item.fired then
                item.timer = item.timer + dt
                if item.timer >= item.delay then
                    -- 防抖检查
                    if (elapsed_ - lastShowTime_) >= DEBOUNCE then
                        M.Show(item.text, item.opts)
                        item.fired = true
                    else
                        allDone = false
                    end
                else
                    allDone = false
                end
            end
        end
        if allDone then
            M._pendingQueue = nil
        end
    end
end

-- ============================================================================
-- 获取容器（每次 RebuildUI 时调用，创建新容器并迁移已有 Toast）
-- ============================================================================
function M.GetContainer()
    local oldToasts = toasts_
    local oldCenter = centerToast_

    -- 创建新容器
    container_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "none",
        alignItems = "center",
        justifyContent = "center",
    }

    -- 迁移已有 Toast 到新容器（保留动画状态）
    toasts_ = {}
    centerToast_ = nil
    for _, t in ipairs(oldToasts) do
        if t.element then
            container_:AddChild(t.element)
            toasts_[#toasts_ + 1] = t
            if t == oldCenter then
                centerToast_ = t
            end
        end
    end

    return container_
end

-- ============================================================================
-- 重置
-- ============================================================================
function M.Reset()
    toasts_ = {}
    centerToast_ = nil
    container_ = nil
    M._pendingQueue = nil
    lastShowTime_ = -1
    elapsed_ = 0
end

-- ============================================================================
-- 连续显示多条消息
-- messages: { "文字1", "文字2", ... }
-- interval: 每条间隔（秒），默认 0.5
-- ============================================================================
function M.ShowSequence(messages, interval, opts)
    interval = interval or 0.5
    opts = opts or {}
    M._pendingQueue = M._pendingQueue or {}
    for i, msg in ipairs(messages) do
        local delay = (i - 1) * interval
        M._pendingQueue[#M._pendingQueue + 1] = {
            text = msg,
            delay = delay,
            timer = 0,
            fired = false,
            opts = opts,
        }
    end
end

-- ============================================================================
-- 公共工具：颜色标签解析（供外部模块复用）
-- ============================================================================

--- 颜色标签预设表
M.TAG_COLORS = RT.TAG_COLORS

--- 解析 <c=xxx>文字</c> 颜色标签（参见 ParseColorTags 本地函数）
M.ParseColorTags = ParseColorTags

return M
