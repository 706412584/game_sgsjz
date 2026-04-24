-- ============================================================================
-- 《问道长生》渡劫小游戏
-- 职责：NanoVG 全屏避雷小游戏，玩家左右移动躲避天劫雷电
-- 接入：NVG.Register("dujie", renderFn, updateFn) / NVG.Unregister("dujie")
-- 渲染：renderFn 在 nvgBeginFrame/nvgEndFrame 之间被调用，无需自己管帧
-- ============================================================================

local M = {}

local NVG = require("nvg_manager")

-- ============================================================================
-- 常量
-- ============================================================================
local PLAYER_SPEED    = 0.85   -- 每秒移动屏幕宽度比（归一化）
local PLAYER_W_NORM   = 0.045  -- 玩家半径（占屏幕宽度）
local PLAYER_Y_NORM   = 0.80   -- 玩家 Y 中心（占屏幕高度）
local MAX_LIVES       = 3      -- 最大生命值
local INVINCIBLE_DUR  = 1.2    -- 被击中后无敌时间(秒)
local STRIKE_DUR      = 0.28   -- 雷击持续时间(秒)
local RESULT_DELAY    = 3.2    -- 结算后自动关闭延迟(秒)
local WARN_ALPHA_MAX  = 150    -- 预警线最大透明度
local RECONNECT_GRACE = 8.0    -- 断线容忍窗口（秒），超时才判失败

-- ============================================================================
-- 状态
-- ============================================================================
local state_       = "idle"   -- "idle" | "playing" | "result"
---@type table|nil
local cfg_         = nil
---@type fun(survived: boolean)|nil
local onResult_    = nil

local playerX_     = 0.5     -- 玩家 X 中心，归一化 0~1
local lives_       = MAX_LIVES
local invincible_  = 0.0     -- 无敌剩余时间(秒)
local gameTimer_   = 0.0
local resultTimer_ = 0.0
local survived_    = false
local bolts_       = {}      -- 当前活跃雷柱
local schedule_    = {}      -- 预生成落雷时间表 { spawnAt, x }
local schedIdx_    = 1

local moveLeft_       = false
local moveRight_      = false
-- 断线容忍
local disconnectTimer_ = 0.0  -- 断线累计时间（秒）
local isPaused_        = false -- 是否因断线而暂停

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 十六进制颜色字符串（不含#）→ r,g,b（0~255）
local function HexToRGB(hex)
    local r = tonumber(hex:sub(1, 2), 16) or 255
    local g = tonumber(hex:sub(3, 4), 16) or 255
    local b = tonumber(hex:sub(5, 6), 16) or 255
    return r, g, b
end

--- 预生成落雷时间表（均匀分布 + 轻微随机偏移）
local function BuildSchedule(cfg)
    local count    = cfg.boltCount
    local duration = cfg.duration
    local sched    = {}
    local interval = (duration - 1.0) / math.max(1, count)
    for i = 1, count do
        local base   = 1.0 + (i - 1) * interval
        local jitter = interval * 0.25 * (math.random() * 2 - 1)
        local x      = 0.08 + math.random() * 0.84   -- 避免极端贴边
        sched[#sched + 1] = { spawnAt = math.max(0.5, base + jitter), x = x }
    end
    table.sort(sched, function(a, b) return a.spawnAt < b.spawnAt end)
    return sched
end

-- ============================================================================
-- 输入处理
-- ============================================================================

local function OnKeyDown(_, eventData)
    if state_ ~= "playing" then return end
    local key = eventData["Key"]:GetInt()
    if key == KEY_LEFT or key == KEY_A  then moveLeft_  = true end
    if key == KEY_RIGHT or key == KEY_D then moveRight_ = true end
end

local function OnKeyUp(_, eventData)
    local key = eventData["Key"]:GetInt()
    if key == KEY_LEFT or key == KEY_A  then moveLeft_  = false end
    if key == KEY_RIGHT or key == KEY_D then moveRight_ = false end
end

local function OnTouchBegin(_, eventData)
    if state_ ~= "playing" then return end
    local screenW = graphics:GetWidth()
    local x = eventData["X"]:GetInt()
    if x < screenW / 2 then moveLeft_ = true else moveRight_ = true end
end

local function OnTouchEnd(_, _)
    moveLeft_  = false
    moveRight_ = false
end

local function SubInput()
    SubscribeToEvent("KeyDown",     OnKeyDown)
    SubscribeToEvent("KeyUp",       OnKeyUp)
    SubscribeToEvent("TouchBegin",  OnTouchBegin)
    SubscribeToEvent("TouchEnd",    OnTouchEnd)
    SubscribeToEvent("TouchCancel", OnTouchEnd)
end

local function UnsubInput()
    UnsubscribeFromEvent("KeyDown")
    UnsubscribeFromEvent("KeyUp")
    UnsubscribeFromEvent("TouchBegin")
    UnsubscribeFromEvent("TouchEnd")
    UnsubscribeFromEvent("TouchCancel")
    moveLeft_  = false
    moveRight_ = false
end

-- ============================================================================
-- 碰撞检测
-- ============================================================================

local function IsHit(bolt, pX, boltWNorm)
    if bolt.phase ~= "strike" then return false end
    local half = (boltWNorm + PLAYER_W_NORM) * 0.5
    return math.abs(pX - bolt.x) < half
end

-- ============================================================================
-- 游戏更新
-- ============================================================================

local function FinishGame(survived)
    state_      = "result"
    survived_   = survived
    resultTimer_ = RESULT_DELAY
    UnsubInput()
end

local function UpdatePlaying(dt)
    -- 断线检测：进入容忍窗口而非立即判失败
    local okNet, ClientNet = pcall(require, "network.client_net")
    local isConnected = not okNet or ClientNet.IsConnected()

    if not isConnected then
        disconnectTimer_ = disconnectTimer_ + dt
        if not isPaused_ then
            isPaused_ = true
            print("[Dujie] 检测到断线，暂停渡劫，容忍窗口=" .. RECONNECT_GRACE .. "s")
        end
        -- 超过容忍窗口才真正判失败
        if disconnectTimer_ >= RECONNECT_GRACE then
            print("[Dujie] 断线超时，强制中止渡劫小游戏")
            local cb = onResult_
            M.StopGame()
            if cb then cb(false) end
        end
        return  -- 断线期间不更新游戏逻辑
    end

    -- 重连成功：恢复游戏
    if isPaused_ then
        isPaused_ = false
        disconnectTimer_ = 0.0
        print("[Dujie] 网络恢复，继续渡劫（已暂停期间雷柱冻结）")
    end

    local screenW = graphics:GetWidth()

    -- 移动玩家
    local dx = 0
    if moveLeft_  then dx = dx - PLAYER_SPEED * dt end
    if moveRight_ then dx = dx + PLAYER_SPEED * dt end
    local half = PLAYER_W_NORM * 0.5
    playerX_ = math.max(half, math.min(1.0 - half, playerX_ + dx))

    -- 无敌计时
    if invincible_ > 0 then invincible_ = invincible_ - dt end

    gameTimer_ = gameTimer_ + dt

    -- 生成新雷柱
    while schedIdx_ <= #schedule_ do
        local s = schedule_[schedIdx_]
        if gameTimer_ >= s.spawnAt then
            bolts_[#bolts_ + 1] = { x = s.x, phase = "warn", timer = 0.0 }
            schedIdx_ = schedIdx_ + 1
        else
            break
        end
    end

    -- 更新雷柱
    local warnTime  = cfg_.warnTime or 1.0
    local boltWNorm = (cfg_.boltW or 40) / screenW
    local newBolts  = {}
    local gameOver  = false

    for _, bolt in ipairs(bolts_) do
        bolt.timer = bolt.timer + dt
        if bolt.phase == "warn" then
            if bolt.timer >= warnTime then
                bolt.phase = "strike"
                bolt.timer = 0.0
            end
            newBolts[#newBolts + 1] = bolt
        elseif bolt.phase == "strike" then
            -- 碰撞检测（仅strike阶段，无敌时跳过）
            if invincible_ <= 0 and IsHit(bolt, playerX_, boltWNorm) then
                lives_     = lives_ - 1
                invincible_ = INVINCIBLE_DUR
                if lives_ <= 0 then gameOver = true end
            end
            if bolt.timer < STRIKE_DUR then
                newBolts[#newBolts + 1] = bolt
            end
            -- timer >= STRIKE_DUR 时自然丢弃（不加入 newBolts）
        end
    end
    bolts_ = newBolts

    if gameOver then
        FinishGame(false)
        return
    end

    -- 胜利条件：超时且所有雷柱已处理
    if gameTimer_ >= cfg_.duration and schedIdx_ > #schedule_ and #bolts_ == 0 then
        FinishGame(true)
    end
end

local function UpdateResult(dt)
    resultTimer_ = resultTimer_ - dt
    if resultTimer_ <= 0 then
        local cb = onResult_
        local sv = survived_
        M.StopGame()
        if cb then cb(sv) end
    end
end

-- ============================================================================
-- NanoVG 渲染（在 nvgBeginFrame/nvgEndFrame 之间调用，无需自己管帧）
-- ============================================================================

local function DrawBg(ctx, w, h)
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    local grad = nvgLinearGradient(ctx, 0, 0, 0, h,
        nvgRGBA(8, 3, 20, 255), nvgRGBA(25, 8, 45, 255))
    nvgFillPaint(ctx, grad)
    nvgFill(ctx)
end

local function DrawGround(ctx, w, h)
    local gY = h * PLAYER_Y_NORM + 38
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, gY, w, h - gY)
    nvgFillColor(ctx, nvgRGBA(12, 5, 25, 255))
    nvgFill(ctx)
    nvgBeginPath(ctx)
    nvgMoveTo(ctx, 0, gY)
    nvgLineTo(ctx, w, gY)
    nvgStrokeColor(ctx, nvgRGBA(90, 50, 150, 200))
    nvgStrokeWidth(ctx, 2)
    nvgStroke(ctx)
end

local function DrawBolts(ctx, w, h)
    local cr, cg, cb = HexToRGB(cfg_.colorHex or "8B5CF6")
    local boltW      = cfg_.boltW or 40
    local warnTime   = cfg_.warnTime or 1.0
    local strikeH    = h * PLAYER_Y_NORM + 38

    for _, bolt in ipairs(bolts_) do
        local bx = bolt.x * w
        if bolt.phase == "warn" then
            local progress = math.min(1.0, bolt.timer / warnTime)
            local alpha    = math.floor(WARN_ALPHA_MAX * progress)
            -- 闪烁：快接近时加快频率
            local freq = 4 + progress * 6
            if math.floor(bolt.timer * freq) % 2 == 1 then alpha = math.floor(alpha * 0.55) end
            -- 预警光柱（半透明）
            nvgBeginPath(ctx)
            nvgRect(ctx, bx - boltW * 0.5, 0, boltW, strikeH)
            nvgFillColor(ctx, nvgRGBA(cr, cg, cb, alpha))
            nvgFill(ctx)
            -- 预警中心线
            nvgBeginPath(ctx)
            nvgRect(ctx, bx - 1.5, 0, 3, strikeH)
            nvgFillColor(ctx, nvgRGBA(220, 200, 255, math.min(255, alpha * 2)))
            nvgFill(ctx)
        elseif bolt.phase == "strike" then
            local t     = bolt.timer / STRIKE_DUR
            local alpha = math.floor(255 * (1.0 - t * 0.5))
            -- 外发光
            nvgBeginPath(ctx)
            nvgRect(ctx, bx - boltW, 0, boltW * 2, strikeH)
            nvgFillColor(ctx, nvgRGBA(cr, cg, cb, math.floor(alpha * 0.35)))
            nvgFill(ctx)
            -- 主雷柱
            nvgBeginPath(ctx)
            nvgRect(ctx, bx - boltW * 0.5, 0, boltW, strikeH)
            nvgFillColor(ctx, nvgRGBA(cr, cg, cb, alpha))
            nvgFill(ctx)
            -- 核心白光
            nvgBeginPath(ctx)
            nvgRect(ctx, bx - 4, 0, 8, strikeH)
            nvgFillColor(ctx, nvgRGBA(255, 255, 255, alpha))
            nvgFill(ctx)
        end
    end
end

local function DrawPlayer(ctx, w, h)
    -- 无敌时快速闪烁
    if invincible_ > 0 and math.floor(invincible_ * 9) % 2 == 1 then return end
    local px = playerX_ * w
    local py = h * PLAYER_Y_NORM
    local pr = PLAYER_W_NORM * w * 0.55
    -- 外发光
    nvgBeginPath(ctx)
    nvgCircle(ctx, px, py, pr * 1.8)
    nvgFillColor(ctx, nvgRGBA(100, 160, 255, 45))
    nvgFill(ctx)
    -- 主体
    nvgBeginPath(ctx)
    nvgCircle(ctx, px, py, pr)
    nvgFillColor(ctx, nvgRGBA(170, 215, 255, 235))
    nvgFill(ctx)
    -- 高光点
    nvgBeginPath(ctx)
    nvgCircle(ctx, px - pr * 0.3, py - pr * 0.3, pr * 0.25)
    nvgFillColor(ctx, nvgRGBA(255, 255, 255, 180))
    nvgFill(ctx)
end

local function DrawHUD(ctx, w, h)
    nvgFontFace(ctx, "sans")
    -- 天劫名称
    nvgFontSize(ctx, 22)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    nvgFillColor(ctx, nvgRGBA(210, 170, 255, 255))
    nvgText(ctx, w * 0.5, 14, cfg_.name or "天劫")
    -- 剩余时间
    local remaining = math.max(0, cfg_.duration - gameTimer_)
    nvgFontSize(ctx, 17)
    nvgFillColor(ctx, nvgRGBA(255, 225, 140, 220))
    nvgText(ctx, w * 0.5, 42, string.format("剩余 %.1f 秒", remaining))
    -- 生命值（实心圆点）
    local dotR    = 10
    local dotGap  = 28
    local startX  = w * 0.5 - (MAX_LIVES - 1) * dotGap * 0.5
    for i = 1, MAX_LIVES do
        nvgBeginPath(ctx)
        nvgCircle(ctx, startX + (i - 1) * dotGap, h - 38, dotR)
        if i <= lives_ then
            nvgFillColor(ctx, nvgRGBA(255, 75, 75, 255))
        else
            nvgFillColor(ctx, nvgRGBA(55, 35, 35, 180))
        end
        nvgFill(ctx)
    end
    -- 操作提示（前3秒显示）
    if gameTimer_ < 3.0 then
        local tipAlpha = math.floor(200 * math.min(1.0, (3.0 - gameTimer_) / 1.0))
        nvgFontSize(ctx, 14)
        nvgFillColor(ctx, nvgRGBA(180, 180, 220, tipAlpha))
        nvgText(ctx, w * 0.5, h - 70, "左右键 / 触屏左右半屏 移动躲避")
    end

    -- 断线暂停提示（叠加在最上层）
    if isPaused_ then
        local graceSecs = math.max(0, RECONNECT_GRACE - disconnectTimer_)
        -- 半透明遮罩
        nvgBeginPath(ctx)
        nvgRect(ctx, 0, 0, w, h)
        nvgFillColor(ctx, nvgRGBA(0, 0, 0, 140))
        nvgFill(ctx)
        -- 主提示
        nvgFontFace(ctx, "sans")
        nvgFontSize(ctx, 22)
        nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        nvgFillColor(ctx, nvgRGBA(255, 160, 60, 255))
        nvgText(ctx, w * 0.5, h * 0.42, "天劫暂停 — 正在重连...")
        -- 旋转小圆点（复用 overlay 风格）
        local dots  = 8
        local ringR = 18
        local animDotR = 4
        local angle0 = disconnectTimer_ * 3.0
        for i = 0, dots - 1 do
            local ang = (i / dots) * math.pi * 2 - math.pi * 0.5 + angle0
            local dx2 = w * 0.5 + math.cos(ang) * ringR
            local dy2 = h * 0.5 - 6 + math.sin(ang) * ringR
            local da  = ((dots - i) / dots)
            da = da * da
            nvgBeginPath(ctx)
            nvgCircle(ctx, dx2, dy2, animDotR * (0.5 + 0.5 * da))
            nvgFillColor(ctx, nvgRGBA(255, 160, 60, math.floor(255 * da)))
            nvgFill(ctx)
        end
        -- 倒计时
        nvgFontSize(ctx, 15)
        nvgFillColor(ctx, nvgRGBA(200, 185, 155, 220))
        nvgText(ctx, w * 0.5, h * 0.5 + 38,
            string.format("%.0f 秒后天劫自动终止", graceSecs))
    end
end

local function DrawResult(ctx, w, h)
    -- 半透明遮罩
    nvgBeginPath(ctx)
    nvgRect(ctx, 0, 0, w, h)
    if survived_ then
        nvgFillColor(ctx, nvgRGBA(0, 15, 0, 170))
    else
        nvgFillColor(ctx, nvgRGBA(25, 0, 0, 170))
    end
    nvgFill(ctx)
    -- 主文字
    nvgFontFace(ctx, "sans")
    nvgFontSize(ctx, 44)
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if survived_ then
        nvgFillColor(ctx, nvgRGBA(160, 255, 160, 255))
        nvgText(ctx, w * 0.5, h * 0.44, "渡劫成功")
    else
        nvgFillColor(ctx, nvgRGBA(255, 90, 90, 255))
        nvgText(ctx, w * 0.5, h * 0.44, "渡劫失败")
    end
    -- 倒计时副文字
    nvgFontSize(ctx, 17)
    nvgFillColor(ctx, nvgRGBA(190, 190, 190, 200))
    nvgText(ctx, w * 0.5, h * 0.56,
        string.format("%.0f 秒后继续...", math.max(0, resultTimer_)))
end

local function RenderGame(ctx)
    local w = graphics:GetWidth()
    local h = graphics:GetHeight()
    DrawBg(ctx, w, h)
    DrawGround(ctx, w, h)
    if cfg_ then
        DrawBolts(ctx, w, h)
    end
    DrawPlayer(ctx, w, h)
    DrawHUD(ctx, w, h)
    if state_ == "result" then
        DrawResult(ctx, w, h)
    end
end

-- ============================================================================
-- 公共 API
-- ============================================================================

--- 启动渡劫小游戏
---@param cfg table  DUJIE_TIERS[tier] 配置（boltCount/duration/boltSpeed/warnTime/boltW/colorHex/name）
---@param onResult fun(survived: boolean) 结果回调（游戏结束后自动调用）
function M.StartGame(cfg, onResult)
    if state_ ~= "idle" then M.StopGame() end
    cfg_           = cfg
    onResult_      = onResult
    state_         = "playing"
    playerX_       = 0.5
    lives_         = MAX_LIVES
    invincible_    = 0.0
    gameTimer_     = 0.0
    bolts_         = {}
    schedule_      = BuildSchedule(cfg)
    schedIdx_      = 1
    survived_      = false
    disconnectTimer_ = 0.0
    isPaused_        = false
    NVG.Register("dujie",
        function(ctx) RenderGame(ctx) end,
        function(dt)
            if state_ == "playing" then
                UpdatePlaying(dt)
            elseif state_ == "result" then
                UpdateResult(dt)
            end
        end
    )
    SubInput()
    print("[Dujie] 启动 tier=" .. tostring(cfg.tier)
          .. " name=" .. tostring(cfg.name)
          .. " bolts=" .. tostring(cfg.boltCount)
          .. " dur=" .. tostring(cfg.duration) .. "s")
end

--- 强制停止游戏（如返回主界面时调用）
function M.StopGame()
    if state_ == "idle" then return end
    NVG.Unregister("dujie")
    UnsubInput()
    state_           = "idle"
    cfg_             = nil
    bolts_           = {}
    schedule_        = {}
    disconnectTimer_ = 0.0
    isPaused_        = false
    print("[Dujie] 游戏停止")
end

--- 是否正在游戏中
---@return boolean
function M.IsPlaying()
    return state_ ~= "idle"
end

return M
