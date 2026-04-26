------------------------------------------------------------
-- ui/battle_effects.lua  —— 战斗浮动特效
-- 伤害数字、暴击、击杀、技能名、治疗 — TTL 生命周期管理
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
-- 工具: 创建浮动 Label 并播放动画
------------------------------------------------------------
local function spawnLabel(x, y, text, fontSize, fontColor, ttl, animConfig)
    if not container_ then return end

    local label = UI.Label {
        text      = text,
        fontSize  = fontSize,
        fontColor = fontColor,
        fontWeight = "bold",
        textAlign = "center",
        position  = "absolute",
        left      = math.floor(x - 40),
        top       = math.floor(y - 20),
        width     = 80,
        pointerEvents = "none",
    }

    container_:AddChild(label)

    -- 播放动画
    if animConfig then
        label:Animate(animConfig)
    end

    effects_[#effects_ + 1] = {
        widget  = label,
        ttl     = ttl,
        elapsed = 0,
    }
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 初始化特效容器
function M.Init(parent)
    container_ = parent
    effects_ = {}
end

--- 显示伤害数字
---@param x number 屏幕X
---@param y number 屏幕Y
---@param value number 伤害值
---@param isCrit boolean 是否暴击
function M.ShowDamage(x, y, value, isCrit)
    local text = tostring(math.floor(value))
    if isCrit then
        -- 暴击: 金色大字 + 弹跳
        spawnLabel(x, y, text, 22, C.gold, 1.2, {
            keyframes = {
                { scale = 1.5, translateY = 0, opacity = 1 },
                { scale = 1.0, translateY = -30, opacity = 1 },
                { scale = 1.0, translateY = -50, opacity = 0 },
            },
            duration = 1.2,
            easing   = "easeOut",
            fillMode = "forwards",
        })
    else
        -- 普通: 白色上浮淡出
        spawnLabel(x, y, text, 16, C.text, 0.8, {
            keyframes = {
                { translateY = 0, opacity = 1 },
                { translateY = -40, opacity = 0 },
            },
            duration = 0.8,
            easing   = "easeOut",
            fillMode = "forwards",
        })
    end
end

--- 显示治疗数字
function M.ShowHeal(x, y, value)
    local text = "+" .. tostring(math.floor(value))
    spawnLabel(x, y, text, 16, C.hp, 0.8, {
        keyframes = {
            { translateY = 0, opacity = 1 },
            { translateY = -40, opacity = 0 },
        },
        duration = 0.8,
        easing   = "easeOut",
        fillMode = "forwards",
    })
end

--- 显示击杀提示
function M.ShowKill(x, y, name)
    spawnLabel(x, y, "击杀!", 20, C.red, 1.0, {
        keyframes = {
            { scale = 1.8, opacity = 1 },
            { scale = 1.0, opacity = 1 },
            { scale = 1.0, opacity = 0 },
        },
        duration = 1.0,
        easing   = "easeOut",
        fillMode = "forwards",
    })
end

--- 显示技能名
function M.ShowSkillName(x, y, name)
    spawnLabel(x, y - 30, name, 14, C.gold, 1.0, {
        keyframes = {
            { scale = 0.5, opacity = 0 },
            { scale = 1.1, opacity = 1 },
            { scale = 1.0, opacity = 1 },
            { scale = 1.0, opacity = 0 },
        },
        duration = 1.0,
        easing   = "easeOut",
        fillMode = "forwards",
    })
end

--- 显示状态效果
function M.ShowStatus(x, y, statusName)
    spawnLabel(x, y + 20, statusName, 12, { 200, 180, 100, 255 }, 0.8, {
        keyframes = {
            { translateY = 0, opacity = 1 },
            { translateY = -20, opacity = 0 },
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
    -- 吸血显示数值
    if extraType == "lifesteal" and extraData and extraData.heal then
        text = "吸血+" .. math.floor(extraData.heal)
    end
    -- 追击显示伤害
    if extraType == "pursuit" and extraData and extraData.damage then
        text = "追击!" .. math.floor(extraData.damage)
    end

    -- 偏移避免和伤害数字重叠
    local ox = math.random(-10, 10)
    local oy = -35 + math.random(-5, 5)

    spawnLabel(x + ox, y + oy, text, cfg.size, cfg.color, 1.0, {
        keyframes = {
            { scale = 0.6, translateY = 0, opacity = 0 },
            { scale = 1.1, translateY = -5, opacity = 1 },
            { scale = 1.0, translateY = -25, opacity = 0 },
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
            -- 过期: 移除
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
