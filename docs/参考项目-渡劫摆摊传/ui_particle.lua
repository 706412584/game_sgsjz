-- ============================================================================
-- ui_particle.lua — 炼化粒子特效 (NanoVG 渲染)
-- 金色/紫色光点上升扩散 + 辉光效果
-- ============================================================================

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local vg_        = nil
local particles_ = {}
local active_    = false

local RENDER_ORDER = 999980   -- 低于 Loading/Reconnect, 高于普通 UI

-- ============================================================================
-- 初始化
-- ============================================================================
function M.Init()
    vg_ = nvgCreate(1)
    if vg_ then
        nvgSetRenderOrder(vg_, RENDER_ORDER)
        SubscribeToEvent(vg_, "NanoVGRender", "HandleParticleRender")
        print("[Particle] 初始化完成")
    end
end

-- ============================================================================
-- 发射粒子
-- @param count  number  粒子数量
-- @param color  table   {r, g, b} 基础颜色 (0-255)
-- @param cy     number? 发射中心Y (逻辑坐标), 默认屏幕35%处
-- ============================================================================
function M.Emit(count, color, cy)
    if not vg_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr
    local cx = sw * 0.5
    cy = cy or (sh * 0.35)

    color = color or { 220, 180, 60 }

    for i = 1, (count or 12) do
        local angle = math.random() * math.pi * 2
        local speed = 30 + math.random() * 50
        local life = 0.8 + math.random() * 0.7

        table.insert(particles_, {
            x = cx + (math.random() - 0.5) * 50,
            y = cy + (math.random() - 0.5) * 20,
            vx = math.cos(angle) * speed * 0.6,
            vy = -math.abs(math.sin(angle)) * speed - 15,   -- 主要向上
            life = life,
            maxLife = life,
            size = 1.5 + math.random() * 2.5,
            r = color[1] + math.floor((math.random() - 0.5) * 40),
            g = color[2] + math.floor((math.random() - 0.5) * 30),
            b = color[3] + math.floor((math.random() - 0.5) * 20),
        })
    end
    active_ = true
end

-- ============================================================================
-- 每帧更新
-- ============================================================================
function M.Update(dt)
    if not active_ then return end

    local alive = {}
    for _, p in ipairs(particles_) do
        p.life = p.life - dt
        if p.life > 0 then
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.vy = p.vy - 8 * dt         -- 轻微上升加速
            p.vx = p.vx * (1 - 1.5 * dt) -- 水平减速
            table.insert(alive, p)
        end
    end
    particles_ = alive

    if #particles_ == 0 then
        active_ = false
    end
end

-- ============================================================================
-- NanoVG 渲染
-- ============================================================================
function HandleParticleRender(eventType, eventData)
    if not active_ or not vg_ or #particles_ == 0 then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr

    nvgBeginFrame(vg_, sw, sh, dpr)

    for _, p in ipairs(particles_) do
        local alpha = p.life / p.maxLife
        alpha = alpha * alpha   -- 非线性淡出, 后期快速消失
        local a = math.floor(255 * alpha)
        local r = math.min(255, math.max(0, p.r))
        local g = math.min(255, math.max(0, p.g))
        local b = math.min(255, math.max(0, p.b))

        -- 外层辉光 (大圆, 低透明度)
        local glowSize = p.size * (2.5 + (1 - alpha) * 1.5)
        nvgBeginPath(vg_)
        nvgCircle(vg_, p.x, p.y, glowSize)
        nvgFillColor(vg_, nvgRGBA(r, g, b, math.floor(a * 0.2)))
        nvgFill(vg_)

        -- 核心光点 (小圆, 高亮)
        local coreSize = p.size * (0.6 + alpha * 0.4)
        nvgBeginPath(vg_)
        nvgCircle(vg_, p.x, p.y, coreSize)
        nvgFillColor(vg_, nvgRGBA(
            math.min(255, r + 40),
            math.min(255, g + 30),
            math.min(255, b + 20),
            a
        ))
        nvgFill(vg_)
    end

    nvgEndFrame(vg_)
end

-- ============================================================================
-- 打坐灵气聚拢特效 — 持续从外围向角色中心汇聚的灵气光点
-- ============================================================================

local meditate_particles_ = {}
local meditate_active_ = false
local meditate_timer_ = 0
local meditate_cx_ = 0      -- 聚拢目标中心 X（逻辑坐标）
local meditate_cy_ = 0      -- 聚拢目标中心 Y（逻辑坐标）
local MEDITATE_RENDER_ORDER = 999991  -- UI库(999990)之上

local meditate_vg_ = nil

--- 开启打坐粒子
-- @param cx number  聚拢中心 X 比例 (0~1, 相对屏幕宽)
-- @param cy number  聚拢中心 Y 比例 (0~1, 相对屏幕高)
function M.StartMeditate(cx, cy)
    if not meditate_vg_ then
        meditate_vg_ = nvgCreate(1)
        if meditate_vg_ then
            nvgSetRenderOrder(meditate_vg_, MEDITATE_RENDER_ORDER)
            SubscribeToEvent(meditate_vg_, "NanoVGRender", "HandleMeditateRender")
        end
    end
    if not meditate_vg_ then return end
    meditate_cx_ = cx or 0.5
    meditate_cy_ = cy or 0.33
    meditate_active_ = true
    meditate_particles_ = {}
    meditate_timer_ = 0
end

--- 动态更新打坐粒子汇聚中心（每帧调用，跟随控件位置）
-- @param cx number  聚拢中心 X 比例 (0~1)
-- @param cy number  聚拢中心 Y 比例 (0~1)
function M.SetMeditateCenter(cx, cy)
    meditate_cx_ = cx or meditate_cx_
    meditate_cy_ = cy or meditate_cy_
end

--- 关闭打坐粒子
function M.StopMeditate()
    meditate_active_ = false
    meditate_particles_ = {}
end

--- 发射一批向中心聚拢的灵气粒子
local function spawnMeditateParticles(sw, sh, count)
    local targetX = sw * meditate_cx_
    local targetY = sh * meditate_cy_

    for i = 1, count do
        -- 从外围随机位置出发
        local angle = math.random() * math.pi * 2
        local dist = 60 + math.random() * 40     -- 起始距离 60~100 逻辑像素
        local startX = targetX + math.cos(angle) * dist
        local startY = targetY + math.sin(angle) * dist
        local life = 1.2 + math.random() * 0.8   -- 1.2~2.0 秒

        -- 颜色: 紫/蓝/金随机
        local palette = {
            { 160, 130, 255 },  -- 淡紫
            { 120, 160, 255 },  -- 淡蓝
            { 200, 180, 255 },  -- 亮紫
            { 220, 200, 130 },  -- 淡金
        }
        local c = palette[math.random(1, #palette)]

        table.insert(meditate_particles_, {
            x = startX, y = startY,
            targetX = targetX, targetY = targetY,
            life = life, maxLife = life,
            size = 1.0 + math.random() * 1.5,
            r = c[1], g = c[2], b = c[3],
            angle = angle,   -- 记录初始角度用于螺旋
            dist = dist,     -- 当前距中心距离
            initDist = dist, -- 初始距离
            spiralSpeed = 1.5 + math.random() * 1.0,  -- 旋转速度
        })
    end
end

--- 打坐粒子每帧更新（在 M.Update 中调用）
function M.UpdateMeditate(dt)
    if not meditate_active_ then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr

    -- 定时发射
    meditate_timer_ = meditate_timer_ + dt
    if meditate_timer_ >= 0.15 then
        meditate_timer_ = meditate_timer_ - 0.15
        spawnMeditateParticles(sw, sh, 3)
    end

    -- 更新粒子：螺旋向中心聚拢
    local targetX = sw * meditate_cx_
    local targetY = sh * meditate_cy_
    local alive = {}
    for _, p in ipairs(meditate_particles_) do
        p.life = p.life - dt
        if p.life > 0 then
            local progress = 1.0 - (p.life / p.maxLife)  -- 0→1
            -- 距离随时间缩小（加速趋近）
            p.dist = p.initDist * (1.0 - progress * progress)
            -- 角度持续旋转（螺旋效果）
            p.angle = p.angle + p.spiralSpeed * dt
            -- 计算位置
            p.x = targetX + math.cos(p.angle) * p.dist
            p.y = targetY + math.sin(p.angle) * p.dist
            table.insert(alive, p)
        end
    end
    meditate_particles_ = alive
end

--- 打坐粒子 NanoVG 渲染
function HandleMeditateRender(eventType, eventData)
    if not meditate_active_ or not meditate_vg_ or #meditate_particles_ == 0 then return end

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr

    nvgBeginFrame(meditate_vg_, sw, sh, dpr)

    for _, p in ipairs(meditate_particles_) do
        local progress = 1.0 - (p.life / p.maxLife)
        -- 透明度: 中间最亮，起始和结束淡
        local alpha
        if progress < 0.2 then
            alpha = progress / 0.2           -- 淡入
        elseif progress > 0.8 then
            alpha = (1.0 - progress) / 0.2   -- 淡出
        else
            alpha = 1.0
        end
        alpha = alpha * 0.7   -- 整体柔和
        local a = math.floor(255 * alpha)
        local r = math.min(255, p.r)
        local g = math.min(255, p.g)
        local b = math.min(255, p.b)

        -- 外层辉光
        local glowSize = p.size * 3.0
        nvgBeginPath(meditate_vg_)
        nvgCircle(meditate_vg_, p.x, p.y, glowSize)
        nvgFillColor(meditate_vg_, nvgRGBA(r, g, b, math.floor(a * 0.15)))
        nvgFill(meditate_vg_)

        -- 核心光点
        local coreSize = p.size * (0.5 + (1.0 - p.dist / p.initDist) * 0.5)
        nvgBeginPath(meditate_vg_)
        nvgCircle(meditate_vg_, p.x, p.y, coreSize)
        nvgFillColor(meditate_vg_, nvgRGBA(
            math.min(255, r + 50),
            math.min(255, g + 40),
            math.min(255, b + 30),
            a
        ))
        nvgFill(meditate_vg_)
    end

    nvgEndFrame(meditate_vg_)
end

return M
