-- ============================================================================
-- 《渡劫摆摊传》渡劫小游戏
-- NanoVG 全屏闪电躲避小游戏 (独立 NanoVG 上下文)
-- 化神(5)及以上突破时触发: 闪电从天而降, 玩家左右移动躲避
-- ============================================================================

local UI     = require("urhox-libs/UI")
local Config = require("data_config")
local State  = require("data_state")

local M = {}

-- ====================== 常量 ======================
local RENDER_ORDER   = 999991   -- UI库(999990)之上, Guide(999992)之下
local COUNTDOWN_SECS = 3        -- 倒计时秒数
local HIT_FLASH_TIME = 0.35     -- 被击中闪烁时长
local RESULT_SHOW    = 2.0      -- 结果展示时长
local PLAYER_W       = 36       -- 玩家宽度(逻辑像素)
local PLAYER_H       = 48       -- 玩家高度(逻辑像素)
local GROUND_OFFSET  = 80       -- 地面距底部距离
local WARNING_ALPHA  = 0.35     -- 预警区域透明度
local BOLT_GLOW      = 8        -- 闪电光晕大小

-- ====================== 状态 ======================
local vg_        = nil
local fontReady_ = false
local nvgActive_ = false
local container_ = nil
local blocker_   = nil

-- 游戏阶段: "idle" | "countdown" | "playing" | "hit" | "result"
local phase_     = "idle"
local elapsed_   = 0       -- 当前阶段计时
local totalTime_ = 0       -- playing阶段已过时长

-- 配置(由服务端数据设置)
local tierName_    = ""
local tierData_    = nil     -- DujieTiers[tier]
local hp_          = 3       -- 剩余生命
local maxHp_       = 3

-- 玩家
local playerX_     = 0       -- 玩家中心X(逻辑坐标)
local playerY_     = 0       -- 玩家底部Y
local moveDir_     = 0       -- -1左 0停 1右

-- 闪电
local bolts_       = {}      -- 活跃闪电 {x, y, w, speed, warning, active, hit}
local nextBolt_    = 0       -- 下一道闪电生成倒计时
local boltIndex_   = 0       -- 已生成闪电数

-- 特效
local shakeTime_   = 0       -- 屏幕震动剩余时间
local shakeX_      = 0
local shakeY_      = 0
local particles_   = {}      -- 击中粒子
local hitFlash_    = 0       -- 被击中全屏闪烁

-- 背景星星粒子
local stars_ = {}
local STAR_COUNT = 40

-- 角色图片句柄
local imgMale_   = nil       -- 男修打坐图
local imgFemale_ = nil       -- 女修打坐图
local imgW_, imgH_ = 0, 0   -- 图片原始尺寸

-- 操作提示
local hintTimer_ = 0         -- 操作提示倒计时(首次显示2秒)
local HINT_DURATION = 3.0    -- 提示持续时间
local HINT_FADE = 1.0        -- 淡出时间

-- 屏幕尺寸(逻辑)
local sw_, sh_, dpr_ = 0, 0, 1

-- 结果
local resultSuccess_ = false
local resultMsg_     = ""
local freeLeft_      = 0
local paidLeft_      = 0

-- 前向声明
local GameCore
local closePending_ = false

-- ====================== 工具函数 ======================
local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function lerp(a, b, t) return a + (b - a) * t end

local function randomRange(lo, hi) return lo + math.random() * (hi - lo) end

-- 渲染确认标志: 仅当渲染回调至少执行过一次后才驱动游戏逻辑
local renderConfirmed_ = false

-- ====================== 初始化星星 ======================
local function initStars()
    stars_ = {}
    for i = 1, STAR_COUNT do
        stars_[i] = {
            x = math.random() * 1000,   -- 会在渲染时映射到实际宽度
            y = math.random() * 600,     -- 映射到实际高度(地面以上)
            r = randomRange(0.5, 2.0),
            twinkle = randomRange(0, math.pi * 2),  -- 闪烁相位
            speed = randomRange(0.5, 2.0),           -- 闪烁速度
        }
    end
end

-- ====================== 初始化 ======================
function M.Init()
    if vg_ then return end
    vg_ = nvgCreate(1)
    if vg_ then
        nvgSetRenderOrder(vg_, RENDER_ORDER)
        nvgCreateFont(vg_, "sans", "Fonts/MiSans-Regular.ttf")
        fontReady_ = true
        -- 加载打坐角色图片
        imgMale_ = nvgCreateImage(vg_, Config.Images.char_meditate, 0)
        imgFemale_ = nvgCreateImage(vg_, Config.Images.char_meditate_female, 0)
        -- 获取图片尺寸
        if imgMale_ and imgMale_ > 0 then
            imgW_, imgH_ = nvgImageSize(vg_, imgMale_)
        end
    end
    initStars()
    GameCore = require("game_core")
end

function M.SetContainer(c)
    container_ = c
end

-- ====================== UI阻断层 ======================
local function showBlocker()
    if not container_ then return end
    if blocker_ then return end
    blocker_ = UI.Panel {
        position = "absolute",
        left = 0, right = 0, top = 0, bottom = 0,
        pointerEvents = "auto",
        backgroundColor = { 0, 0, 0, 1 },
    }
    container_:AddChild(blocker_)
end

local function hideBlocker()
    if blocker_ then
        blocker_:SetVisible(false)
        YGNodeStyleSetDisplay(blocker_.node, YGDisplayNone)
        if container_ then
            container_:RemoveChild(blocker_)
        end
        blocker_ = nil
    end
end

-- ====================== NanoVG 管理 ======================
local function activateNVG()
    if vg_ and not nvgActive_ then
        SubscribeToEvent(vg_, "NanoVGRender", "HandleDujieRender")
        nvgActive_ = true
        renderConfirmed_ = false
    end
end

local function deactivateNVG()
    if vg_ and nvgActive_ then
        UnsubscribeFromEvent(vg_, "NanoVGRender")
        nvgActive_ = false
    end
end

-- ====================== 输入处理 ======================
local function updateInput()
    moveDir_ = 0
    -- 键盘
    if input:GetKeyDown(KEY_A) or input:GetKeyDown(KEY_LEFT) then
        moveDir_ = -1
    elseif input:GetKeyDown(KEY_D) or input:GetKeyDown(KEY_RIGHT) then
        moveDir_ = 1
    end
    -- 触屏: 触摸左半屏向左, 右半屏向右
    if input.numTouches > 0 then
        local touch = input:GetTouch(0)
        local tx = touch.position.x / dpr_
        if tx < sw_ * 0.5 then
            moveDir_ = -1
        else
            moveDir_ = 1
        end
    end
end

-- ====================== 闪电生成 ======================
local function spawnBolt()
    if not tierData_ then return end
    boltIndex_ = boltIndex_ + 1
    local bw = tierData_.boltWidth or 36
    local x = randomRange(bw, sw_ - bw)
    local bolt = {
        x = x,
        y = -20,
        w = bw,
        speed = tierData_.boltSpeed + randomRange(-30, 30),
        warning = tierData_.warningTime,
        warningElapsed = 0,
        active = false,  -- 预警阶段不激活
        hit = false,
        segments = {},   -- 锯齿路径
    }
    -- 生成锯齿闪电路径
    local segs = math.random(4, 7)
    for i = 1, segs do
        bolt.segments[i] = {
            dx = randomRange(-bw * 0.4, bw * 0.4),
            dy = sh_ / segs * i,
        }
    end
    table.insert(bolts_, bolt)
end

-- ====================== 碰撞检测 ======================
-- 检查闪电整条路径是否与玩家碰撞框相交
local function checkCollision(bolt)
    if bolt.hit then return false end
    -- 玩家碰撞框
    local px = playerX_
    local py = playerY_ - PLAYER_H * 0.5
    local pw = PLAYER_W * 0.35
    local ph = PLAYER_H * 0.45
    local pLeft   = px - pw
    local pRight  = px + pw
    local pTop    = py - ph
    local pBottom = py + ph

    -- 闪电路径: 从 (bx, by-30) 沿锯齿线段到各节点
    local bx = bolt.x
    local by = bolt.y
    local ratio = clamp((by + 30) / sh_, 0, 1)
    -- 构建闪电路径各节点的实际坐标
    local prevX = bx
    local prevY = by - 30
    for _, seg in ipairs(bolt.segments) do
        local sx = bx + seg.dx * ratio
        local sy = by - 30 + seg.dy * ratio * 0.6
        -- 线段 (prevX,prevY)→(sx,sy) 与玩家AABB碰撞检测
        -- 快速排除: 线段完全在玩家框外
        local segLeft   = math.min(prevX, sx)
        local segRight  = math.max(prevX, sx)
        local segTop    = math.min(prevY, sy)
        local segBottom = math.max(prevY, sy)
        -- 考虑闪电宽度
        local hw = bolt.w * 0.3
        if segRight + hw >= pLeft and segLeft - hw <= pRight
            and segBottom >= pTop and segTop <= pBottom then
            return true
        end
        prevX = sx
        prevY = sy
    end
    return false
end

-- ====================== 被击中处理 ======================
local function onHit(bolt)
    bolt.hit = true
    hp_ = hp_ - 1
    shakeTime_ = 0.3
    hitFlash_ = HIT_FLASH_TIME
    -- 生成粒子
    for i = 1, 8 do
        table.insert(particles_, {
            x = playerX_,
            y = playerY_ - PLAYER_H * 0.5,
            vx = randomRange(-120, 120),
            vy = randomRange(-180, -40),
            life = randomRange(0.4, 0.8),
            maxLife = 0.8,
            r = randomRange(3, 6),
        })
    end
    if hp_ <= 0 then
        -- 失败 → 发送结果
        phase_ = "result"
        elapsed_ = 0
        resultSuccess_ = false
        resultMsg_ = "渡劫失败"
        GameCore.SendGameAction("dujie_result", { success = false })
    else
        phase_ = "hit"
        elapsed_ = 0
    end
end

-- ====================== 游戏更新 ======================
local function updateGame(dt)
    if phase_ == "countdown" then
        elapsed_ = elapsed_ + dt
        if elapsed_ >= COUNTDOWN_SECS then
            phase_ = "playing"
            elapsed_ = 0
            totalTime_ = 0
            nextBolt_ = 1.0  -- 首道闪电1秒后出现
            boltIndex_ = 0
        end
        return
    end

    if phase_ == "hit" then
        elapsed_ = elapsed_ + dt
        if elapsed_ >= HIT_FLASH_TIME then
            phase_ = "playing"
            elapsed_ = 0
        end
        return
    end

    if phase_ == "result" then
        elapsed_ = elapsed_ + dt
        return
    end

    if phase_ ~= "playing" then return end

    totalTime_ = totalTime_ + dt

    -- 更新操作提示倒计时
    if hintTimer_ > 0 then
        hintTimer_ = hintTimer_ - dt
    end

    -- 检查是否通关
    if tierData_ and totalTime_ >= tierData_.duration and #bolts_ == 0 then
        phase_ = "result"
        elapsed_ = 0
        resultSuccess_ = true
        resultMsg_ = tierName_ .. " 渡劫成功!"
        GameCore.SendGameAction("dujie_result", { success = true })
        return
    end

    -- 更新输入
    updateInput()

    -- 移动玩家
    if moveDir_ ~= 0 and tierData_ then
        local speed = tierData_.playerSpeed or 280
        playerX_ = playerX_ + moveDir_ * speed * dt
        playerX_ = clamp(playerX_, PLAYER_W * 0.5, sw_ - PLAYER_W * 0.5)
    end

    -- 生成闪电
    if tierData_ and boltIndex_ < tierData_.totalBolts then
        nextBolt_ = nextBolt_ - dt
        if nextBolt_ <= 0 then
            spawnBolt()
            local remaining = tierData_.totalBolts - boltIndex_
            if remaining > 0 then
                local timeLeft = tierData_.duration - totalTime_
                nextBolt_ = math.max(0.3, timeLeft / remaining)
            end
        end
    end

    -- 更新闪电
    for i = #bolts_, 1, -1 do
        local b = bolts_[i]
        if not b.active then
            b.warningElapsed = b.warningElapsed + dt
            if b.warningElapsed >= b.warning then
                b.active = true
                -- 随机播放一个雷声
                GameCore.PlaySFX("thunder_" .. math.random(1, 3))
            end
        else
            b.y = b.y + b.speed * dt
            -- 碰撞检测
            if not b.hit and checkCollision(b) then
                onHit(b)
            end
            -- 移除出屏闪电
            if b.y > sh_ + 50 then
                table.remove(bolts_, i)
            end
        end
    end

    -- 更新粒子
    for i = #particles_, 1, -1 do
        local p = particles_[i]
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.vy = p.vy + 400 * dt  -- 重力
        p.life = p.life - dt
        if p.life <= 0 then
            table.remove(particles_, i)
        end
    end

    -- 更新震动
    if shakeTime_ > 0 then
        shakeTime_ = shakeTime_ - dt
        shakeX_ = randomRange(-4, 4)
        shakeY_ = randomRange(-4, 4)
    else
        shakeX_ = 0
        shakeY_ = 0
    end

    -- 更新击中闪烁
    if hitFlash_ > 0 then
        hitFlash_ = hitFlash_ - dt
    end
end

-- ====================== NanoVG 渲染 ======================

-- 绘制渐变天空背景
local function drawBackground(v)
    -- 暗紫到深蓝渐变
    local topR, topG, topB = 15, 5, 30
    local botR, botG, botB = 5, 10, 40
    -- 渡劫时闪电闪烁效果
    local flashMul = 1.0
    if hitFlash_ > 0 then
        flashMul = 1.0 + 2.0 * (hitFlash_ / HIT_FLASH_TIME)
    end
    local bg = nvgLinearGradient(v, 0, 0, 0, sh_,
        nvgRGBA(topR * flashMul, topG * flashMul, topB * flashMul, 255),
        nvgRGBA(botR * flashMul, botG * flashMul, botB * flashMul, 255))
    nvgBeginPath(v)
    nvgRect(v, 0, 0, sw_, sh_)
    nvgFillPaint(v, bg)
    nvgFill(v)
end

-- 绘制背景星星
local function drawStars(v)
    local groundY = sh_ - GROUND_OFFSET
    for _, s in ipairs(stars_) do
        local sx = (s.x / 1000) * sw_
        local sy = (s.y / 600) * (groundY - 20)
        local brightness = math.sin(totalTime_ * s.speed + s.twinkle) * 0.4 + 0.6
        local a = math.floor(200 * brightness)
        nvgBeginPath(v)
        nvgCircle(v, sx, sy, s.r * brightness)
        nvgFillColor(v, nvgRGBA(220, 220, 255, clamp(a, 40, 220)))
        nvgFill(v)
    end
end

-- 绘制底部方向箭头提示
local function drawArrows(v)
    if phase_ ~= "playing" and phase_ ~= "hit" then return end
    local arrowW = 60
    local arrowH = 50
    local margin = 30
    local bottomY = sh_ - 20
    local arrowAlpha = 50
    -- 左箭头
    local leftActive = (moveDir_ == -1)
    local la = leftActive and 160 or arrowAlpha
    nvgBeginPath(v)
    local lx = margin + arrowW * 0.5
    local ly = bottomY - arrowH * 0.5
    nvgMoveTo(v, lx - arrowW * 0.4, ly)
    nvgLineTo(v, lx + arrowW * 0.2, ly - arrowH * 0.4)
    nvgLineTo(v, lx + arrowW * 0.2, ly + arrowH * 0.4)
    nvgClosePath(v)
    nvgFillColor(v, nvgRGBA(200, 200, 255, la))
    nvgFill(v)
    -- 右箭头
    local rightActive = (moveDir_ == 1)
    local ra = rightActive and 160 or arrowAlpha
    nvgBeginPath(v)
    local rx = sw_ - margin - arrowW * 0.5
    local ry = ly
    nvgMoveTo(v, rx + arrowW * 0.4, ry)
    nvgLineTo(v, rx - arrowW * 0.2, ry - arrowH * 0.4)
    nvgLineTo(v, rx - arrowW * 0.2, ry + arrowH * 0.4)
    nvgClosePath(v)
    nvgFillColor(v, nvgRGBA(200, 200, 255, ra))
    nvgFill(v)
end

-- 绘制操作提示(首次出现, 渐隐)
local function drawHint(v)
    if hintTimer_ <= 0 then return end
    local alpha = 1.0
    if hintTimer_ < HINT_FADE then
        alpha = hintTimer_ / HINT_FADE
    end
    local a = math.floor(220 * alpha)
    nvgFontFace(v, "sans")
    nvgFontSize(v, 22)
    nvgTextAlign(v, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(v, nvgRGBA(220, 220, 255, a))
    nvgText(v, sw_ * 0.5, sh_ * 0.65, "点击左右两侧移动躲避雷劫")
end

-- 绘制地面
local function drawGround(v)
    local groundY = sh_ - GROUND_OFFSET
    -- 地面渐变
    local grd = nvgLinearGradient(v, 0, groundY, 0, sh_,
        nvgRGBA(30, 50, 30, 255), nvgRGBA(10, 20, 10, 255))
    nvgBeginPath(v)
    nvgRect(v, 0, groundY, sw_, GROUND_OFFSET)
    nvgFillPaint(v, grd)
    nvgFill(v)
    -- 地面线
    nvgBeginPath(v)
    nvgMoveTo(v, 0, groundY)
    nvgLineTo(v, sw_, groundY)
    nvgStrokeColor(v, nvgRGBA(60, 120, 60, 180))
    nvgStrokeWidth(v, 2)
    nvgStroke(v)
end

-- 绘制灵力光圈(角色脚下)
local function drawAura(v, px, py)
    -- 脉冲光圈
    local pulse = math.sin(totalTime_ * 3) * 0.3 + 0.7
    local auraR = PLAYER_W * 0.8 * pulse
    -- 外圈发光
    local auraPaint = nvgRadialGradient(v, px, py, auraR * 0.2, auraR,
        nvgRGBA(140, 120, 255, math.floor(60 * pulse)),
        nvgRGBA(140, 120, 255, 0))
    nvgBeginPath(v)
    nvgEllipse(v, px, py, auraR, auraR * 0.35)
    nvgFillPaint(v, auraPaint)
    nvgFill(v)
    -- 内圈亮光
    local innerPaint = nvgRadialGradient(v, px, py, 0, auraR * 0.4,
        nvgRGBA(200, 180, 255, math.floor(80 * pulse)),
        nvgRGBA(200, 180, 255, 0))
    nvgBeginPath(v)
    nvgEllipse(v, px, py, auraR * 0.4, auraR * 0.15)
    nvgFillPaint(v, innerPaint)
    nvgFill(v)
end

-- 绘制玩家(打坐角色图片)
local function drawPlayer(v)
    local px = playerX_
    local py = playerY_

    -- 灵力光圈(脚下)
    drawAura(v, px, py)

    -- 选择性别对应图片
    local gender = "male"
    if State and State.state and State.state.playerGender then
        gender = State.state.playerGender
    end
    local img = (gender == "female") and imgFemale_ or imgMale_

    if img and img > 0 and imgW_ > 0 and imgH_ > 0 then
        -- 计算绘制尺寸(保持宽高比, 适配 PLAYER_H)
        local drawH = PLAYER_H + 16
        local drawW = drawH * (imgW_ / imgH_)
        local drawX = px - drawW * 0.5
        local drawY = py - drawH

        -- 被击中时闪烁透明度
        local alpha = 1.0
        if phase_ == "hit" then
            alpha = math.sin(elapsed_ * 30) * 0.3 + 0.7
        end

        local imgPaint = nvgImagePattern(v, drawX, drawY, drawW, drawH, 0, img, alpha)
        nvgBeginPath(v)
        nvgRect(v, drawX, drawY, drawW, drawH)
        nvgFillPaint(v, imgPaint)
        nvgFill(v)

        -- 被击中红色叠加
        if phase_ == "hit" then
            local a = math.floor(math.sin(elapsed_ * 30) * 60 + 60)
            nvgBeginPath(v)
            nvgRect(v, drawX, drawY, drawW, drawH)
            nvgFillColor(v, nvgRGBA(255, 80, 80, clamp(a, 0, 120)))
            nvgFill(v)
        end
    else
        -- 降级: 图片未加载时仍绘制简化角色
        nvgBeginPath(v)
        nvgMoveTo(v, px, py - PLAYER_H)
        nvgLineTo(v, px - PLAYER_W * 0.5, py)
        nvgLineTo(v, px + PLAYER_W * 0.5, py)
        nvgClosePath(v)
        local robePaint = nvgLinearGradient(v, px, py - PLAYER_H, px, py,
            nvgRGBA(180, 160, 220, 255), nvgRGBA(100, 80, 160, 255))
        nvgFillPaint(v, robePaint)
        nvgFill(v)
        nvgBeginPath(v)
        nvgCircle(v, px, py - PLAYER_H - 6, 8)
        nvgFillColor(v, nvgRGBA(240, 220, 200, 255))
        nvgFill(v)
        if phase_ == "hit" then
            local a = math.floor(math.sin(elapsed_ * 30) * 80 + 80)
            nvgBeginPath(v)
            nvgCircle(v, px, py - PLAYER_H * 0.5, PLAYER_W)
            nvgFillColor(v, nvgRGBA(255, 100, 100, clamp(a, 0, 160)))
            nvgFill(v)
        end
    end
end

-- 绘制闪电预警区域
local function drawWarning(v, bolt)
    if bolt.active then return end
    local progress = bolt.warningElapsed / bolt.warning
    local a = math.floor(WARNING_ALPHA * 255 * progress)
    nvgBeginPath(v)
    nvgRect(v, bolt.x - bolt.w * 0.7, 0, bolt.w * 1.4, sh_)
    nvgFillColor(v, nvgRGBA(255, 50, 50, clamp(a, 0, 120)))
    nvgFill(v)
end

-- 绘制闪电(锯齿路径+光晕)
local function drawBolt(v, bolt)
    if not bolt.active then return end
    local bx = bolt.x
    local by = bolt.y
    -- 光晕
    nvgBeginPath(v)
    nvgCircle(v, bx, by, bolt.w * 0.8 + BOLT_GLOW)
    nvgFillColor(v, nvgRGBA(200, 200, 255, 40))
    nvgFill(v)
    -- 主闪电线
    nvgBeginPath(v)
    nvgMoveTo(v, bx, by - 30)
    for _, seg in ipairs(bolt.segments) do
        local ratio = clamp((by + 30) / sh_, 0, 1)
        nvgLineTo(v, bx + seg.dx * ratio, by - 30 + seg.dy * ratio * 0.6)
    end
    nvgStrokeColor(v, nvgRGBA(220, 220, 255, 240))
    nvgStrokeWidth(v, 3)
    nvgStroke(v)
    -- 外发光线
    nvgBeginPath(v)
    nvgMoveTo(v, bx, by - 30)
    for _, seg in ipairs(bolt.segments) do
        local ratio = clamp((by + 30) / sh_, 0, 1)
        nvgLineTo(v, bx + seg.dx * ratio, by - 30 + seg.dy * ratio * 0.6)
    end
    nvgStrokeColor(v, nvgRGBA(150, 150, 255, 80))
    nvgStrokeWidth(v, 8)
    nvgStroke(v)
    -- 落点球
    nvgBeginPath(v)
    nvgCircle(v, bx, by, 6)
    nvgFillColor(v, nvgRGBA(255, 255, 200, 220))
    nvgFill(v)
end

-- 绘制粒子
local function drawParticles(v)
    for _, p in ipairs(particles_) do
        local a = clamp(math.floor(255 * (p.life / p.maxLife)), 0, 255)
        nvgBeginPath(v)
        nvgCircle(v, p.x, p.y, p.r * (p.life / p.maxLife))
        nvgFillColor(v, nvgRGBA(255, 200, 100, a))
        nvgFill(v)
    end
end

-- 绘制爱心路径(贝塞尔曲线)
local function heartPath(v, cx, cy, size)
    local s = size
    nvgBeginPath(v)
    nvgMoveTo(v, cx, cy + s * 0.35)
    -- 左半边
    nvgBezierTo(v, cx, cy,
                   cx - s * 0.55, cy - s * 0.2,
                   cx - s * 0.5, cy + s * 0.05)
    nvgBezierTo(v, cx - s * 0.45, cy + s * 0.35,
                   cx, cy + s * 0.65,
                   cx, cy + s * 0.8)
    -- 右半边
    nvgBezierTo(v, cx, cy + s * 0.65,
                   cx + s * 0.45, cy + s * 0.35,
                   cx + s * 0.5, cy + s * 0.05)
    nvgBezierTo(v, cx + s * 0.55, cy - s * 0.2,
                   cx, cy,
                   cx, cy + s * 0.35)
    nvgClosePath(v)
end

-- 绘制HP(爱心形状)
local function drawHP(v)
    local y = 22
    local x = 20
    local heartSize = 12
    local spacing = 26
    for i = 1, maxHp_ do
        heartPath(v, x + heartSize * 0.5, y, heartSize)
        if i <= hp_ then
            -- 红色实心爱心 + 发光
            local glow = nvgRadialGradient(v, x + heartSize * 0.5, y + heartSize * 0.4,
                heartSize * 0.2, heartSize * 0.8,
                nvgRGBA(255, 60, 60, 255), nvgRGBA(180, 30, 30, 255))
            nvgFillPaint(v, glow)
        else
            nvgFillColor(v, nvgRGBA(60, 60, 70, 180))
        end
        nvgFill(v)
        x = x + spacing
    end
end

-- 绘制进度条
local function drawProgress(v)
    if not tierData_ then return end
    local barW = sw_ * 0.6
    local barH = 8
    local barX = (sw_ - barW) * 0.5
    local barY = 52
    local progress = clamp(totalTime_ / tierData_.duration, 0, 1)
    -- 背景
    nvgBeginPath(v)
    nvgRoundedRect(v, barX, barY, barW, barH, 4)
    nvgFillColor(v, nvgRGBA(40, 40, 60, 180))
    nvgFill(v)
    -- 进度
    nvgBeginPath(v)
    nvgRoundedRect(v, barX, barY, barW * progress, barH, 4)
    local pGrad = nvgLinearGradient(v, barX, barY, barX + barW * progress, barY,
        nvgRGBA(100, 180, 255, 255), nvgRGBA(180, 130, 255, 255))
    nvgFillPaint(v, pGrad)
    nvgFill(v)
    -- 标题
    nvgFontFace(v, "sans")
    nvgFontSize(v, 16)
    nvgTextAlign(v, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(v, nvgRGBA(200, 200, 255, 220))
    nvgText(v, sw_ * 0.5, barY + barH + 4, tierName_)
end

-- 绘制倒计时
local function drawCountdown(v)
    local remain = math.ceil(COUNTDOWN_SECS - elapsed_)
    remain = clamp(remain, 1, COUNTDOWN_SECS)
    local scale = 1.0 + (1.0 - (elapsed_ % 1.0)) * 0.3
    nvgFontFace(v, "sans")
    nvgFontSize(v, 72 * scale)
    nvgTextAlign(v, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    nvgFillColor(v, nvgRGBA(255, 255, 200, 240))
    nvgText(v, sw_ * 0.5, sh_ * 0.4, tostring(remain))

    nvgFontSize(v, 28)
    nvgFillColor(v, nvgRGBA(220, 200, 255, 200))
    nvgText(v, sw_ * 0.5, sh_ * 0.4 + 60, tierName_ .. " 即将降临!")

    nvgFontSize(v, 18)
    nvgFillColor(v, nvgRGBA(180, 180, 200, 160))
    nvgText(v, sw_ * 0.5, sh_ * 0.4 + 95, "左右移动躲避雷劫")
end

-- 绘制结果
local function drawResult(v)
    local a = clamp(math.floor(255 * math.min(1, elapsed_ / 0.5)), 0, 255)
    -- 半透明遮罩
    nvgBeginPath(v)
    nvgRect(v, 0, 0, sw_, sh_)
    nvgFillColor(v, nvgRGBA(0, 0, 0, math.floor(a * 0.5)))
    nvgFill(v)

    nvgFontFace(v, "sans")
    if resultSuccess_ then
        nvgFontSize(v, 42)
        nvgTextAlign(v, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(v, nvgRGBA(255, 215, 0, a))
        nvgText(v, sw_ * 0.5, sh_ * 0.38, resultMsg_)
        -- 光芒效果
        for i = 1, 8 do
            local angle = (elapsed_ * 0.5 + i * math.pi / 4) % (math.pi * 2)
            local rx = sw_ * 0.5 + math.cos(angle) * 60
            local ry = sh_ * 0.38 + math.sin(angle) * 30
            nvgBeginPath(v)
            nvgCircle(v, rx, ry, 3)
            nvgFillColor(v, nvgRGBA(255, 230, 100, math.floor(a * 0.6)))
            nvgFill(v)
        end
    else
        nvgFontSize(v, 38)
        nvgTextAlign(v, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(v, nvgRGBA(220, 80, 80, a))
        nvgText(v, sw_ * 0.5, sh_ * 0.38, resultMsg_)
    end

    -- 剩余次数提示
    nvgFontSize(v, 18)
    nvgFillColor(v, nvgRGBA(200, 200, 220, math.floor(a * 0.8)))
    local infoText = string.format("今日剩余: 免费%d次  付费%d次", freeLeft_, paidLeft_)
    nvgText(v, sw_ * 0.5, sh_ * 0.38 + 50, infoText)
end

-- ====================== 绘制场景(被 pcall 包裹) ======================
local function drawScene(v)
    -- 保存并应用震动
    nvgSave(v)
    nvgTranslate(v, shakeX_, shakeY_)

    -- 背景 + 星星
    drawBackground(v)
    drawStars(v)
    drawGround(v)

    if phase_ == "countdown" then
        drawPlayer(v)
        drawCountdown(v)
    elseif phase_ == "playing" or phase_ == "hit" then
        -- 预警区域
        for _, b in ipairs(bolts_) do
            drawWarning(v, b)
        end
        -- 玩家
        drawPlayer(v)
        -- 闪电
        for _, b in ipairs(bolts_) do
            drawBolt(v, b)
        end
        -- 粒子
        drawParticles(v)
        -- HUD
        drawHP(v)
        drawProgress(v)
        -- 方向箭头
        drawArrows(v)
        -- 操作提示
        drawHint(v)
    elseif phase_ == "result" then
        drawPlayer(v)
        drawResult(v)
    end

    nvgRestore(v)
end

-- ====================== 主渲染回调 ======================
function HandleDujieRender(eventType, eventData)
    if phase_ == "idle" then return end
    local v = vg_
    if not v then return end

    -- 在渲染回调中直接获取屏幕尺寸(与 ui_toast/ui_loading 保持一致)
    local curDpr = graphics:GetDPR()
    local curW = graphics:GetWidth() / curDpr
    local curH = graphics:GetHeight() / curDpr
    if curW < 1 or curH < 1 then return end

    -- 同步给模块变量(供游戏逻辑使用)
    dpr_ = curDpr
    sw_ = curW
    sh_ = curH

    -- 标记渲染已确认(允许 M.Update 驱动逻辑)
    if not renderConfirmed_ then
        renderConfirmed_ = true
    end

    -- 开始NanoVG帧
    nvgBeginFrame(v, curW, curH, curDpr)

    -- 用 pcall 保护绘图代码, 确保 nvgEndFrame 一定被调用
    local ok, err = pcall(drawScene, v)
    if not ok then
        print("[Dujie] 渲染错误: " .. tostring(err))
    end

    nvgEndFrame(v)
end

-- ====================== 对外接口 ======================

--- 开始渡劫小游戏
---@param data table 服务端 dujie_begin 事件数据
function M.StartGame(data)
    if phase_ ~= "idle" then return end

    local tier = data.tier or 1
    tierData_ = Config.DujieTiers[tier]
    if not tierData_ then
        print("[Dujie] 无效的渡劫等级: " .. tostring(tier))
        return
    end
    tierName_ = tierData_.name
    maxHp_ = Config.DUJIE_HP
    hp_ = maxHp_
    freeLeft_ = data.freeLeft or 0
    paidLeft_ = data.paidLeft or 0

    -- 重置状态
    bolts_ = {}
    particles_ = {}
    boltIndex_ = 0
    nextBolt_ = 1.0
    totalTime_ = 0
    shakeTime_ = 0
    shakeX_ = 0
    shakeY_ = 0
    hitFlash_ = 0
    resultSuccess_ = false
    resultMsg_ = ""

    -- 屏幕尺寸
    dpr_ = graphics:GetDPR()
    sw_ = graphics:GetWidth() / dpr_
    sh_ = graphics:GetHeight() / dpr_

    -- 初始化玩家位置
    playerX_ = sw_ * 0.5
    playerY_ = sh_ - GROUND_OFFSET
    moveDir_ = 0

    -- 操作提示计时
    hintTimer_ = HINT_DURATION

    -- 进入倒计时
    phase_ = "countdown"
    elapsed_ = 0

    -- 激活渲染和输入阻断
    activateNVG()
    showBlocker()
end

--- 服务端通知成功
---@param data table {name, freeLeft, paidLeft}
function M.OnServerSuccess(data)
    -- 结果由服务端确认后展示(已在 dujie_result 里完成)
    -- 这里更新剩余次数
    freeLeft_ = data.freeLeft or freeLeft_
    paidLeft_ = data.paidLeft or paidLeft_
    -- 延迟关闭
    if closePending_ then return end
    closePending_ = true
    -- 等结果展示完毕再关
end

--- 服务端通知失败(次数信息)
---@param data table {freeLeft, paidLeft, msg}
function M.OnServerFail(data)
    freeLeft_ = data.freeLeft or freeLeft_
    paidLeft_ = data.paidLeft or paidLeft_
    resultMsg_ = data.msg or "渡劫失败"
end

--- 关闭渡劫界面
function M.Close()
    phase_ = "idle"
    elapsed_ = 0
    bolts_ = {}
    particles_ = {}
    closePending_ = false
    renderConfirmed_ = false
    deactivateNVG()
    hideBlocker()
end

--- 是否正在渡劫中
---@return boolean
function M.IsActive()
    return phase_ ~= "idle"
end

--- 更新(由 main.lua HandleUpdate 调用)
function M.Update(dt)
    if phase_ == "idle" then return end

    -- 必须等渲染回调至少执行一次, 才开始驱动游戏逻辑
    -- 防止渲染未工作时游戏自动完成(玩家看不到但逻辑跑完)
    if not renderConfirmed_ then return end

    -- 驱动游戏逻辑
    updateGame(dt)

    -- 结果展示完毕后自动关闭
    if phase_ == "result" and elapsed_ >= RESULT_SHOW then
        M.Close()
    end
end

return M
