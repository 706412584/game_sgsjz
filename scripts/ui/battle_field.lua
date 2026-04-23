------------------------------------------------------------
-- ui/battle_field.lua  —— 战场武将卡牌组件
-- 创建、布局、状态更新武将卡牌 (110×150, absolute 定位)
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 常量
------------------------------------------------------------
local CARD_W = 110
local CARD_H = 150
local AVATAR_SIZE = 90
local HP_H   = 6
local MOR_H  = 4

-- 状态效果中文映射
local STATUS_NAMES = {
    stun = "晕", silence = "默", burn = "烧", armor_break = "破",
    charm = "乱", freeze = "冻", shield = "盾", hot = "回",
    atk_up = "攻↑", def_up = "防↑", speed_up = "速↑",
}

------------------------------------------------------------
-- 对称网格布局
-- 我方(左): 后排 x=0.13, 前排 x=0.29
-- 敌方(右): 前排 x=0.71, 后排 x=0.87  (镜像对称)
-- 纵向: 在顶栏(70px)和底部按钮(65px)之间均匀分布
------------------------------------------------------------
local TOP_MARGIN = 70   -- 顶栏54px + 余量
local BOT_MARGIN = 65   -- 底部结果/加速按钮区

local X_FRAC = {
    ally_back   = 0.13,
    ally_front  = 0.29,
    enemy_front = 0.71,
    enemy_back  = 0.87,
}

--- 在安全区域内均匀分布 N 张卡牌的 Y 坐标 (返回 top 值数组)
local function calcYSlots(count, pH)
    local topY = TOP_MARGIN
    local botY = pH - BOT_MARGIN - CARD_H
    if botY < topY then botY = topY end
    if count <= 0 then return {} end
    if count == 1 then
        return { math.floor((topY + botY) / 2) }
    end
    local slots = {}
    local step = (botY - topY) / (count - 1)
    for i = 1, count do
        slots[i] = math.floor(topY + (i - 1) * step)
    end
    return slots
end

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------
local container_     -- 父容器
local unitCards_ = {} -- { [unitId] = { panel, hpBar, moraleBar, statusLabel, avatar, nameLabel, posX, posY } }
local panelW_, panelH_ = 0, 0
local lastHighlight_ = nil

------------------------------------------------------------
-- 创建单个卡牌
------------------------------------------------------------
local function createCard(unit, side, posX, posY)
    local nameColor = side == "ally" and C.jade or C.red
    local hpColor   = side == "ally" and C.hp  or C.red

    -- HP 条
    local hpBar = UI.ProgressBar {
        value           = 1.0,
        width           = CARD_W - 10,
        height          = HP_H,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 2,
        fillColor       = hpColor,
        transition      = "value 0.3s easeOut",
    }

    -- 士气条
    local moraleBar = UI.ProgressBar {
        value           = (unit.morale or 0) / 100,
        width           = CARD_W - 10,
        height          = MOR_H,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 1,
        fillColor       = C.morale,
        transition      = "value 0.3s easeOut",
    }

    -- 状态标签
    local statusLabel = UI.Label {
        text      = "",
        fontSize  = 9,
        fontColor = C.gold,
        textAlign = "center",
        width     = CARD_W,
        maxLines  = 1,
    }

    -- 名字标签
    local nameLabel = UI.Label {
        text      = unit.name or "???",
        fontSize  = 10,
        fontColor = nameColor,
        fontWeight = "bold",
        textAlign = "center",
        width     = CARD_W,
        maxLines  = 1,
    }

    -- 头像
    local imgPath = unit.heroId
        and ("Textures/heroes/hero_" .. unit.heroId .. ".png")
        or nil

    local avatar = UI.Panel {
        width           = AVATAR_SIZE,
        height          = AVATAR_SIZE,
        borderRadius    = 8,
        borderColor     = nameColor,
        borderWidth     = 2,
        backgroundImage = imgPath,
        backgroundFit   = "cover",
        backgroundColor = side == "ally" and { 30, 55, 45, 255 } or { 55, 30, 30, 255 },
        justifyContent  = "center",
        alignItems      = "center",
        transition      = "borderColor 0.2s easeOut",
        children = (not imgPath) and {
            UI.Label {
                text      = string.sub(unit.name or "?", 1, 6),
                fontSize  = 12,
                fontColor = C.text,
                textAlign = "center",
            },
        } or {},
    }

    -- 卡牌容器
    local card = UI.Panel {
        position = "absolute",
        left     = posX,
        top      = posY,
        width    = CARD_W,
        height   = CARD_H,
        alignItems = "center",
        gap      = 2,
        transition = "opacity 0.3s easeOut",
        children = {
            avatar,
            nameLabel,
            hpBar,
            moraleBar,
            statusLabel,
        },
    }

    unitCards_[unit.id] = {
        panel      = card,
        hpBar      = hpBar,
        moraleBar  = moraleBar,
        statusLabel = statusLabel,
        avatar     = avatar,
        nameLabel  = nameLabel,
        posX       = posX,
        posY       = posY,
    }

    return card
end

------------------------------------------------------------
-- 布局一组单位
------------------------------------------------------------
local function layoutGroup(units, xFrac, pW, pH)
    local cards = {}
    local n = #units
    local ySlots = calcYSlots(n, pH)

    for i, unit in ipairs(units) do
        local posX = math.floor(xFrac * pW - CARD_W / 2)
        local posY = ySlots[i] or math.floor(pH / 2 - CARD_H / 2)
        cards[#cards + 1] = createCard(unit, unit.side, posX, posY)
    end
    return cards
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建所有武将卡牌并添加到容器
---@param parent table UI容器
---@param allies table[] BattleUnit[]
---@param enemies table[] BattleUnit[]
---@param pW number 面板宽度(像素)
---@param pH number 面板高度(像素)
function M.Create(parent, allies, enemies, pW, pH)
    container_ = parent
    panelW_ = pW
    panelH_ = pH
    unitCards_ = {}
    lastHighlight_ = nil

    -- 分前后排
    local allyFront, allyBack = {}, {}
    for _, u in ipairs(allies) do
        if u.row == "front" then allyFront[#allyFront + 1] = u
        else allyBack[#allyBack + 1] = u end
    end

    local enemyFront, enemyBack = {}, {}
    for _, u in ipairs(enemies) do
        if u.row == "front" then enemyFront[#enemyFront + 1] = u
        else enemyBack[#enemyBack + 1] = u end
    end

    -- 布局并添加
    local groups = {
        { allyBack,   X_FRAC.ally_back },
        { allyFront,  X_FRAC.ally_front },
        { enemyFront, X_FRAC.enemy_front },
        { enemyBack,  X_FRAC.enemy_back },
    }

    for _, g in ipairs(groups) do
        local cards = layoutGroup(g[1], g[2], pW, pH)
        for _, card in ipairs(cards) do
            parent:AddChild(card)
        end
    end
end

--- 更新单位状态
function M.UpdateUnit(unitId, hp, maxHp, morale, statuses, alive)
    local info = unitCards_[unitId]
    if not info then return end

    -- HP
    if info.hpBar then
        local ratio = alive and math.max(0, hp / maxHp) or 0
        info.hpBar:SetValue(ratio)
    end

    -- 士气
    if info.moraleBar then
        info.moraleBar:SetValue((morale or 0) / 100)
    end

    -- 阵亡透明
    if not alive then
        info.panel:SetStyle({ opacity = 0.3 })
    end

    -- 状态标签
    if info.statusLabel then
        if statuses and next(statuses) then
            local parts = {}
            for status, sInfo in pairs(statuses) do
                local sName = STATUS_NAMES[status] or status
                parts[#parts + 1] = sName .. sInfo.dur
            end
            info.statusLabel.text = table.concat(parts, " ")
        else
            info.statusLabel.text = ""
        end
    end
end

--- 高亮当前行动者
function M.HighlightUnit(unitId)
    -- 取消上一个高亮
    if lastHighlight_ and unitCards_[lastHighlight_] then
        local prev = unitCards_[lastHighlight_]
        prev.avatar:SetStyle({ borderWidth = 2 })
    end

    local info = unitCards_[unitId]
    if info then
        info.avatar:SetStyle({ borderWidth = 4 })
        -- 简单放大动画
        info.panel:Animate({
            keyframes = {
                { scale = 1.08 },
                { scale = 1.0 },
            },
            duration = 0.3,
            easing   = "easeOutBack",
        })
    end

    lastHighlight_ = unitId
end

--- 获取单位卡牌中心位置 (相对容器)
function M.GetUnitPos(unitId)
    local info = unitCards_[unitId]
    if not info then return nil end
    return {
        x = info.posX + CARD_W / 2,
        y = info.posY,
    }
end

--- 通过名字查找 unitId
function M.FindUnitByName(name)
    for uid, info in pairs(unitCards_) do
        if info.nameLabel and info.nameLabel.text == name then
            return uid
        end
    end
    return nil
end

--- 清理
function M.Clear()
    unitCards_ = {}
    lastHighlight_ = nil
    container_ = nil
end

return M
