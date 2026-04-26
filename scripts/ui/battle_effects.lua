------------------------------------------------------------
-- ui/battle_effects.lua  —— 战斗浮动特效 (增强版)
-- 伤害数字(多段散射)、暴击(红墨横幅)、击杀、技能水墨横幅、
-- 治疗粒子(++上浮)、extras浮字 — TTL 生命周期管理
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors

local M = {}

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------
local container_  -- 特效容器 (absolute, 100%, pointerEvents=none)
local effects_ = {} -- { { widget, ttl, elapsed } }

------------------------------------------------------------
-- 内部: 注册一个带生命周期的控件
------------------------------------------------------------
local function registerFx(widget, ttl)
    effects_[#effects_ + 1] = {
        widget  = widget,
        ttl     = ttl,
        elapsed = 0,
    }
end

------------------------------------------------------------
-- 工具: 创建浮动 Label 并播放动画
------------------------------------------------------------
local function spawnLabel(x, y, text, fontSize, fontColor, ttl, animConfig, extraStyle)
    if not container_ then return end

    local style = {
        text          = text,
        fontSize      = fontSize,
        fontColor     = fontColor,
        fontWeight    = "bold",
        textAlign     = "center",
        position      = "absolute",
        left          = math.floor(x - 50),
        top           = math.floor(y - 20),
        width         = 100,
        pointerEvents = "none",
    }

    if extraStyle then
        for k, v in pairs(extraStyle) do style[k] = v end
    end

    local label = UI.Label(style)
    container_:AddChild(label)

    if animConfig then
        label:Animate(animConfig)
    end

    registerFx(label, ttl)
    return label
end

------------------------------------------------------------
-- 工具: 创建水墨横幅 (图片+文字叠加)
------------------------------------------------------------
local function spawnInkBanner(x, y, text, brushImage, textColor, ttl)
    if not container_ then return end

    local bannerW = 200
    local bannerH = 50

    local banner = UI.Panel {
        position        = "absolute",
        left            = math.floor(x - bannerW / 2),
        top             = math.floor(y - bannerH / 2),
        width           = bannerW,
        height          = bannerH,
        backgroundImage = brushImage,
        backgroundFit   = "fill",
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "none",
    }

    local label = UI.Label {
        text       = text,
        fontSize   = 18,
        fontColor  = textColor,
        fontWeight = "bold",
        textAlign  = "center",
        pointerEvents = "none",
    }

    banner:AddChild(label)
    container_:AddChild(banner)

    -- 横向展开 + 渐显 → 停留 → 渐隐上飘
    banner:Animate({
        keyframes = {
            [0]    = { scaleX = 0.3, scaleY = 0.6, opacity = 0, translateY = 0 },
            [0.15] = { scaleX = 1.15, scaleY = 1.0, opacity = 1, translateY = 0 },
            [0.25] = { scaleX = 1.0, scaleY = 1.0, opacity = 1, translateY = 0 },
            [0.7]  = { scaleX = 1.0, scaleY = 1.0, opacity = 1, translateY = -5 },
            [1]    = { scaleX = 1.0, scaleY = 1.0, opacity = 0, translateY = -20 },
        },
        duration = ttl,
        easing   = "easeOut",
        fillMode = "forwards",
    })

    registerFx(banner, ttl)
    return banner
end

------------------------------------------------------------
-- 工具: 生成一个治疗粒子 (+)
------------------------------------------------------------
local function spawnHealParticle(x, y, char, color, ttl)
    if not container_ then return end

    local ox = math.random(-20, 20)
    local oy = math.random(-5, 10)
    local sz = math.random(10, 16)
    local drift = math.random(-8, 8)

    local label = UI.Label {
        text          = char,
        fontSize      = sz,
        fontColor     = color,
        fontWeight    = "bold",
        textAlign     = "center",
        position      = "absolute",
        left          = math.floor(x + ox - 10),
        top           = math.floor(y + oy - 10),
        width         = 20,
        pointerEvents = "none",
    }

    container_:AddChild(label)

    label:Animate({
        keyframes = {
            [0]   = { translateY = 0, translateX = 0, opacity = 0, scale = 0.5 },
            [0.1] = { translateY = -5, translateX = drift * 0.2, opacity = 1, scale = 1.0 },
            [0.5] = { translateY = -30, translateX = drift * 0.6, opacity = 0.9, scale = 1.0 },
            [1]   = { translateY = -55, translateX = drift, opacity = 0, scale = 0.6 },
        },
        duration = ttl,
        easing   = "easeOut",
        fillMode = "forwards",
    })

    registerFx(label, ttl)
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 初始化特效容器
function M.Init(parent)
    container_ = parent
    effects_ = {}
end

--- 显示伤害数字 (增强版: 多段散射)
--- 暴击横幅已拆分到 ShowCritBanner，此处暴击仅显示加大伤害数字+散射
---@param x number 屏幕X (目标位置)
---@param y number 屏幕Y (目标位置)
---@param value number 伤害值
---@param isCrit boolean 是否暴击
function M.ShowDamage(x, y, value, isCrit)
    local dmgText = tostring(math.floor(value))

    if isCrit then
        -- 暴击: 在目标位置显示加大红色伤害数字
        spawnLabel(x, y, "-" .. dmgText, 22,
            { 255, 60, 40, 255 }, 1.1,
            {
                keyframes = {
                    [0]    = { scale = 0.5, translateY = 0, opacity = 0 },
                    [0.1]  = { scale = 1.6, translateY = -5, opacity = 1 },
                    [0.25] = { scale = 1.2, translateY = -10, opacity = 1 },
                    [0.6]  = { scale = 1.1, translateY = -25, opacity = 0.7 },
                    [1]    = { scale = 1.0, translateY = -45, opacity = 0 },
                },
                duration = 1.1,
                easing   = "easeOut",
                fillMode = "forwards",
            })

        -- 附加散射碎片数字 (3~4段小数字飞散)
        local fragments = math.random(3, 4)
        local fragVal = math.floor(value / fragments)
        for f = 1, fragments do
            local fx = x + math.random(-30, 30)
            local fy = y + math.random(-10, 15)
            local delay = f * 0.05
            spawnLabel(fx, fy, "-" .. fragVal,
                math.random(11, 14),
                { 255, 80 + math.random(0, 60), 60, 255 },
                1.0,
                {
                    keyframes = {
                        [0]   = { scale = 0.3, translateY = 0, opacity = 0 },
                        [0.15] = { scale = 1.2, translateY = -3, opacity = 1 },
                        [0.4] = { scale = 1.0, translateY = -15, opacity = 0.8 },
                        [1]   = { scale = 0.8, translateY = -40, opacity = 0 },
                    },
                    duration = 0.9,
                    easing   = "easeOut",
                    fillMode = "forwards",
                    delay    = delay,
                })
        end
    else
        -- 普通伤害: 主数字 + 散射小数字
        -- 主数字: 红白色, 弹出放大再缩回
        spawnLabel(x, y, "-" .. dmgText, 18,
            { 255, 220, 210, 255 }, 1.0,
            {
                keyframes = {
                    [0]    = { scale = 0.5, translateY = 0, opacity = 0 },
                    [0.1]  = { scale = 1.3, translateY = -5, opacity = 1 },
                    [0.25] = { scale = 1.0, translateY = -10, opacity = 1 },
                    [0.6]  = { scale = 1.0, translateY = -25, opacity = 0.7 },
                    [1]    = { scale = 0.9, translateY = -45, opacity = 0 },
                },
                duration = 1.0,
                easing   = "easeOut",
                fillMode = "forwards",
            })

        -- 2个散射碎片
        for f = 1, 2 do
            local fx = x + math.random(-25, 25)
            local fy = y + math.random(-5, 10)
            spawnLabel(fx, fy, "-" .. math.floor(value / 3),
                math.random(9, 12),
                { 255, 160, 140, 220 },
                0.7,
                {
                    keyframes = {
                        [0]   = { scale = 0.4, translateY = 0, opacity = 0 },
                        [0.2] = { scale = 1.0, translateY = -8, opacity = 0.8 },
                        [1]   = { scale = 0.6, translateY = -30, opacity = 0 },
                    },
                    duration = 0.7,
                    easing   = "easeOut",
                    fillMode = "forwards",
                    delay    = f * 0.06,
                })
        end
    end
end

--- 显示治疗 (增强版: 主数字 + 一堆 ++ 粒子上浮)
function M.ShowHeal(x, y, value)
    -- 主治疗数字: 绿色, 放大弹出
    spawnLabel(x, y, "+" .. math.floor(value), 18,
        { 100, 255, 130, 255 }, 1.0,
        {
            keyframes = {
                [0]    = { scale = 0.5, translateY = 0, opacity = 0 },
                [0.12] = { scale = 1.3, translateY = -5, opacity = 1 },
                [0.3]  = { scale = 1.0, translateY = -12, opacity = 1 },
                [0.7]  = { scale = 1.0, translateY = -30, opacity = 0.7 },
                [1]    = { scale = 0.9, translateY = -50, opacity = 0 },
            },
            duration = 1.0,
            easing   = "easeOut",
            fillMode = "forwards",
        })

    -- 粒子群: 6~8 个 "+" 符号, 黄绿/绿色, 不同大小, 向上飘散
    local particleCount = math.random(6, 8)
    local greens = {
        { 100, 255, 130, 255 },
        { 140, 255, 100, 255 },
        { 180, 255, 80,  255 },
        { 200, 255, 120, 230 },
        { 120, 230, 90,  255 },
    }
    for p = 1, particleCount do
        local color = greens[math.random(1, #greens)]
        local char = (math.random() > 0.4) and "+" or "++"
        local ttl = 0.6 + math.random() * 0.5
        spawnHealParticle(x, y - 5, char, color, ttl)
    end
end

--- 显示击杀提示 (增强: 放大震动)
function M.ShowKill(x, y, name)
    spawnLabel(x, y, "击杀!", 22, C.red, 1.2, {
        keyframes = {
            [0]    = { scale = 2.0, opacity = 0, rotate = -5 },
            [0.15] = { scale = 1.1, opacity = 1, rotate = 2 },
            [0.3]  = { scale = 1.0, opacity = 1, rotate = 0 },
            [0.7]  = { scale = 1.0, opacity = 1, rotate = 0 },
            [1]    = { scale = 1.0, opacity = 0, rotate = 0 },
        },
        duration = 1.2,
        easing   = "easeOutBack",
        fillMode = "forwards",
    })
end

--- 显示暴击横幅 — 红色水墨横幅 + 暴击文字 (在攻击方位置)
---@param x number 攻击方屏幕X
---@param y number 攻击方屏幕Y
---@param value number 暴击伤害总值
---@param animDelay number|nil 延迟显示(秒), 用于技能后再显示暴击
function M.ShowCritBanner(x, y, value, animDelay)
    if not container_ then return end
    local dmgText = tostring(math.floor(value))
    local bannerW = 200
    local bannerH = 50
    local bx = math.floor(x - bannerW / 2)
    local by = math.floor(y - bannerH / 2 - 35)
    local totalTtl = 1.4

    local banner = UI.Panel {
        position        = "absolute",
        left            = bx,
        top             = by,
        width           = bannerW,
        height          = bannerH,
        backgroundImage = "Textures/ui/ink_brush_red.png",
        backgroundFit   = "fill",
        justifyContent  = "center",
        alignItems      = "center",
        pointerEvents   = "none",
    }

    local label = UI.Label {
        text       = "暴击 " .. dmgText,
        fontSize   = 18,
        fontColor  = { 255, 220, 60, 255 },
        fontWeight = "bold",
        textAlign  = "center",
        pointerEvents = "none",
    }
    banner:AddChild(label)
    container_:AddChild(banner)

    local delay = animDelay or 0

    banner:Animate({
        keyframes = {
            [0]    = { scaleX = 0.3, scaleY = 0.6, opacity = 0, translateY = 0 },
            [0.15] = { scaleX = 1.15, scaleY = 1.0, opacity = 1, translateY = 0 },
            [0.25] = { scaleX = 1.0, scaleY = 1.0, opacity = 1, translateY = 0 },
            [0.7]  = { scaleX = 1.0, scaleY = 1.0, opacity = 1, translateY = -5 },
            [1]    = { scaleX = 1.0, scaleY = 1.0, opacity = 0, translateY = -20 },
        },
        duration = totalTtl,
        easing   = "easeOut",
        fillMode = "forwards",
        delay    = delay,
    })

    registerFx(banner, totalTtl + delay)
end

--- 显示技能名 — 黑色水墨横幅 + 金色技能名文字
function M.ShowSkillName(x, y, name)
    spawnInkBanner(x, y - 40, name,
        "Textures/ui/ink_brush_black.png",
        { 255, 220, 120, 255 }, 2.0)
end

--- 显示兵种特性名 — 黑色水墨横幅 + 青色文字
function M.ShowTroopPassive(x, y, name)
    spawnInkBanner(x, y - 40, name,
        "Textures/ui/ink_brush_black.png",
        { 120, 255, 220, 255 }, 1.2)
end

--- 显示状态效果
function M.ShowStatus(x, y, statusName)
    spawnLabel(x, y + 20, statusName, 12, { 200, 180, 100, 255 }, 0.8, {
        keyframes = {
            [0]   = { scale = 0.5, translateY = 0, opacity = 0 },
            [0.15] = { scale = 1.1, translateY = 0, opacity = 1 },
            [0.3]  = { scale = 1.0, translateY = -5, opacity = 1 },
            [1]    = { scale = 1.0, translateY = -20, opacity = 0 },
        },
        duration = 0.8,
        easing   = "easeOut",
        fillMode = "forwards",
    })
end

------------------------------------------------------------
-- extras 特殊机制视觉提示
------------------------------------------------------------
local EXTRA_CONFIG = {
    dodge              = { text = "闪避!",     color = { 120, 220, 255, 255 }, size = 14 },
    execute            = { text = "斩杀!",     color = { 255, 60,  60,  255 }, size = 18 },
    death_immune       = { text = "免死!",     color = { 255, 220, 80,  255 }, size = 18 },
    lifesteal          = { text = "吸血",      color = { 180, 255, 120, 255 }, size = 14 },
    kill_morale        = { text = "杀敌回怒!", color = { 255, 200, 60,  255 }, size = 13 },
    pursuit            = { text = "追击!",     color = { 255, 140, 40,  255 }, size = 16 },
    ally_morale        = { text = "全军增怒!", color = { 255, 220, 80,  255 }, size = 14 },
    enemy_morale_reduce= { text = "敌军减怒!", color = { 160, 120, 255, 255 }, size = 14 },
    debuff_zhi         = { text = "降智!",     color = { 160, 120, 255, 255 }, size = 14 },
    immune_control     = { text = "免控!",     color = { 100, 255, 200, 255 }, size = 14 },
    counter            = { text = "反击!",     color = { 255, 180, 60,  255 }, size = 16 },
}

--- 显示 extras 特殊机制浮动提示
---@param x number 屏幕X
---@param y number 屏幕Y
---@param extraType string extras 类型
---@param extraData table|nil 额外数据
function M.ShowExtra(x, y, extraType, extraData)
    local cfg = EXTRA_CONFIG[extraType]
    if not cfg then return end

    local text = cfg.text
    if extraType == "lifesteal" and extraData and extraData.heal then
        text = "吸血+" .. math.floor(extraData.heal)
    end
    if extraType == "pursuit" and extraData and extraData.damage then
        text = "追击!" .. math.floor(extraData.damage)
    end

    local ox = math.random(-10, 10)
    local oy = -35 + math.random(-5, 5)

    spawnLabel(x + ox, y + oy, text, cfg.size, cfg.color, 1.0, {
        keyframes = {
            [0]    = { scale = 0.6, translateY = 0, opacity = 0 },
            [0.12] = { scale = 1.2, translateY = -3, opacity = 1 },
            [0.3]  = { scale = 1.0, translateY = -8, opacity = 1 },
            [0.7]  = { scale = 1.0, translateY = -18, opacity = 0.7 },
            [1]    = { scale = 0.9, translateY = -30, opacity = 0 },
        },
        duration = 1.0,
        easing   = "easeOut",
        fillMode = "forwards",
    })
end

--- 每帧更新: 管理特效生命周期
function M.Update(dt)
    local i = 1
    while i <= #effects_ do
        local fx = effects_[i]
        fx.elapsed = fx.elapsed + dt
        if fx.elapsed >= fx.ttl then
            if container_ and fx.widget then
                container_:RemoveChild(fx.widget)
            end
            table.remove(effects_, i)
        else
            i = i + 1
        end
    end
end

--- 清空所有特效
function M.Clear()
    if container_ then
        for _, fx in ipairs(effects_) do
            container_:RemoveChild(fx.widget)
        end
    end
    effects_ = {}
end

return M
