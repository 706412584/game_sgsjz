------------------------------------------------------------
-- ui/battle_field.lua  —— 战场武将卡牌组件 (flex 布局版)
-- 布局: 使用 flexDirection="row" + flexGrow spacer 实现对称 4 列
--   [spacer] [后排] [spacer] [前排] [中线spacer] [前排] [spacer] [后排] [spacer]
-- 卡牌是 flex 子元素，自动适配容器实际宽度（解决 safe area 偏移）
-- 参考: 风云天下 — 卡牌铺满战场，结果按钮浮在上层
------------------------------------------------------------
local UI      = require("urhox-libs/UI")
local Theme   = require("ui.theme")
local Sprites = require("data.data_sprites")
local C       = Theme.colors
local S       = Theme.sizes

local M = {}

------------------------------------------------------------
-- 布局常量
------------------------------------------------------------
local TOP_MARGIN = 54   -- 顶栏高度(52+2px线)
local BOT_MARGIN = 4    -- 底边最小留白

-- flex spacer 比例 (控制列的水平分布)
-- 布局: [3] col [2] col [5] col [2] col [3]
-- 即: 外侧留白3 | 后排列 | 间距2 | 前排列 | 中线5 | 前排列 | 间距2 | 后排列 | 外侧留白3
local GROW_OUTER  = 3   -- 两端留白
local GROW_INNER  = 2   -- 前后排之间间距
local GROW_CENTER = 5   -- 中线间距

-- 卡片尺寸上限
local MAX_CARD_W  = 120
local MAX_CARD_H  = 150
local AVATAR_RATIO = 0.92   -- 头像占卡片高度比例 (放大立绘)

-- 状态效果中文映射
local STATUS_NAMES = {
    stun = "晕", silence = "默", burn = "烧", armor_break = "破",
    charm = "乱", freeze = "冻", shield = "盾", hot = "回",
    atk_up = "攻↑", def_up = "防↑", speed_up = "速↑",
}

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------
local container_
local unitCards_ = {}
local lastHighlight_ = nil
local cardW_, cardH_, avatarSize_ = 100, 130, 80
local gridRow_   -- flexRow 容器引用, 用于估算位置
local containerW_, containerH_ = 0, 0  -- 用于 GetUnitPos 估算

-- 攻击精灵恢复定时器队列
local atkTimers_ = {}  -- { { unitId, remaining } }

------------------------------------------------------------
-- 根据可用高度计算卡片尺寸
------------------------------------------------------------
local function calcCardSize(availH)
    -- 3行, 行间用 space-around 自动分配
    -- 估算: 每行可用高度 ≈ availH / 3, 卡片取 90% 行高
    local rowH = availH / 3
    local ch = math.min(MAX_CARD_H, math.floor(rowH * 0.90))
    local cw = math.floor(ch * (MAX_CARD_W / MAX_CARD_H))
    cw = math.min(MAX_CARD_W, cw)
    local av = math.floor(ch * AVATAR_RATIO)
    return cw, ch, av
end

--- N 个单位分配到 3 行 (居中), 返回行索引数组
local function assignRows(count)
    if count <= 0 then return {} end
    if count == 1 then return { 2 } end
    if count == 2 then return { 1, 3 } end
    return { 1, 2, 3 }
end

------------------------------------------------------------
-- 创建单个卡牌 (不再设 position=absolute)
------------------------------------------------------------
local function createCard(unit, side, colKey, rowIdx)
    local nameColor = side == "ally" and C.jade or C.red
    local hpColor   = side == "ally" and C.hp  or C.red

    local hpH  = math.max(5, math.floor(cardH_ * 0.05))
    local morH = math.max(3, math.floor(cardH_ * 0.03))
    local nameFontSize   = cardH_ < 80 and 8 or (cardH_ < 100 and 9 or 10)
    local statusFontSize = cardH_ < 80 and 7 or (cardH_ < 100 and 8 or 9)

    local hpBar = UI.ProgressBar {
        value           = 1.0,
        width           = avatarSize_,
        height          = hpH,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 2,
        fillColor       = hpColor,
        transition      = "value 0.3s easeOut",
    }

    local moraleBar = UI.ProgressBar {
        value           = (unit.morale or 0) / 100,
        width           = avatarSize_,
        height          = morH,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 1,
        fillColor       = C.morale,
        transition      = "value 0.3s easeOut",
    }

    local statusLabel = UI.Label {
        text      = "",
        fontSize  = statusFontSize,
        fontColor = C.gold,
        textAlign = "center",
        width     = cardW_,
        maxLines  = 1,
    }

    local nameLabel = UI.Label {
        text       = unit.name or "???",
        fontSize   = nameFontSize,
        fontColor  = nameColor,
        fontWeight = "bold",
        textAlign  = "center",
        width      = cardW_,
        maxLines   = 1,
    }

    -- 优先使用战斗精灵图，无精灵则回退英雄头像
    -- ally 朝右, enemy 朝左
    local spriteIdle = Sprites.GetIdle(unit.heroId, unit.name, side)
    local spriteAtk  = Sprites.GetAtk(unit.heroId, unit.name, side)
    local imgPath = spriteIdle
        or (unit.heroId and ("Textures/heroes/hero_" .. unit.heroId .. ".png"))
        or nil

    local avatar = UI.Panel {
        width           = avatarSize_,
        height          = avatarSize_,
        backgroundImage = imgPath,
        backgroundFit   = "contain",
        justifyContent  = "center",
        alignItems      = "center",
        children = (not imgPath) and {
            UI.Label {
                text      = string.sub(unit.name or "?", 1, 6),
                fontSize  = nameFontSize,
                fontColor = C.text,
                textAlign = "center",
            },
        } or {},
    }

    -- 普通 flex 子元素, 不用 absolute
    local card = UI.Panel {
        width      = cardW_,
        height     = cardH_,
        alignItems = "center",
        gap        = 1,
        transition = "opacity 0.3s easeOut",
        children   = {
            avatar,
            nameLabel,
            hpBar,
            moraleBar,
            statusLabel,
        },
    }

    unitCards_[unit.id] = {
        panel       = card,
        hpBar       = hpBar,
        moraleBar   = moraleBar,
        statusLabel = statusLabel,
        avatar      = avatar,
        nameLabel   = nameLabel,
        colKey      = colKey,
        rowIdx      = rowIdx,
        spriteIdle  = spriteIdle or imgPath,
        spriteAtk   = spriteAtk,
    }

    return card
end

------------------------------------------------------------
-- 创建一列容器 (flex column, space-around 纵向分布)
-- 用 3 个 slot: 仅占用需要的行, 空行放空 panel 占位
------------------------------------------------------------
local function createColumn(units, side, colKey)
    local n = #units
    local rows = assignRows(n)

    -- 3 行 slot
    local slots = { nil, nil, nil }
    for i, unit in ipairs(units) do
        if i > 3 then break end
        local rowIdx = rows[i]
        slots[rowIdx] = createCard(unit, side, colKey, rowIdx)
    end

    -- 构建 3 行子元素(空行用 flexGrow spacer 占位)
    local children = {}
    for r = 1, 3 do
        if slots[r] then
            children[#children + 1] = slots[r]
        else
            -- 空占位: 和卡片同高, 保持 3 行均匀
            children[#children + 1] = UI.Panel {
                width  = cardW_,
                height = cardH_,
            }
        end
    end

    return UI.Panel {
        width          = cardW_,
        flexDirection  = "column",
        justifyContent = "space-around",
        alignItems     = "center",
        children       = children,
    }
end

--- 创建 flex spacer
local function spacer(grow)
    return UI.Panel { flexGrow = grow, flexBasis = 0 }
end

------------------------------------------------------------
-- 估算列中心 X 位置 (给特效用)
-- 基于 flexGrow 比例计算: total = 3+cw+2+cw+5+cw+2+cw+3 = 15 + 4*cw(归一化)
------------------------------------------------------------
local function estimateColCenterX(colKey, totalW)
    -- spacer 总 grow = 3+2+5+2+3 = 15
    -- 4 列各占 cardW_ 固定宽度
    local fixedW = 4 * cardW_
    local spacerW = math.max(0, totalW - fixedW)
    local growUnit = spacerW / 15  -- 每单位 grow 对应的像素

    -- 从左到右:
    -- [grow=3 spacer] [allyBack col] [grow=2 spacer] [allyFront col] [grow=5 spacer] [enemyFront col] [grow=2 spacer] [enemyBack col] [grow=3 spacer]
    local colCenters = {
        ally_back   = GROW_OUTER * growUnit + cardW_ * 0.5,
        ally_front  = GROW_OUTER * growUnit + cardW_ + GROW_INNER * growUnit + cardW_ * 0.5,
        enemy_front = GROW_OUTER * growUnit + cardW_ + GROW_INNER * growUnit + cardW_ + GROW_CENTER * growUnit + cardW_ * 0.5,
        enemy_back  = GROW_OUTER * growUnit + cardW_ + GROW_INNER * growUnit + cardW_ + GROW_CENTER * growUnit + cardW_ + GROW_INNER * growUnit + cardW_ * 0.5,
    }
    return colCenters[colKey] or (totalW * 0.5)
end

local function estimateRowCenterY(rowIdx, totalH)
    -- 去除上下 margin, 3行 space-around 分布
    local availH = totalH - TOP_MARGIN - BOT_MARGIN
    -- space-around: 每行中心 = TOP_MARGIN + availH*(2*row-1)/6
    return TOP_MARGIN + availH * (2 * rowIdx - 1) / 6
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

function M.Create(parent, allies, enemies, pW, pH)
    container_ = parent
    unitCards_ = {}
    lastHighlight_ = nil

    -- 用 SafeContentArea 获取实际可用宽度 (扣除 safe area insets)
    local safeX, safeY, safeW, safeH = UI.GetSafeContentArea()
    containerW_ = safeW    -- 实际容器宽度 (特效估算用)
    containerH_ = pH       -- 高度不受 safe area 横向 insets 影响

    -- 可用高度 (减去顶栏和底部留白)
    local availH = pH - TOP_MARGIN - BOT_MARGIN
    cardW_, cardH_, avatarSize_ = calcCardSize(availH)

    print(string.format(
        "[BattleField] screenW=%.0f safeW=%.0f pH=%.0f availH=%.0f cardW=%d cardH=%d avatar=%d",
        pW, safeW, pH, availH, cardW_, cardH_, avatarSize_))

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

    print(string.format(
        "[BattleField] 单位数: allyBack=%d allyFront=%d | enemyFront=%d enemyBack=%d",
        #allyBack, #allyFront, #enemyFront, #enemyBack))

    -- 构建 4 列
    local colAllyBack   = createColumn(allyBack,   "ally",  "ally_back")
    local colAllyFront  = createColumn(allyFront,  "ally",  "ally_front")
    local colEnemyFront = createColumn(enemyFront, "enemy", "enemy_front")
    local colEnemyBack  = createColumn(enemyBack,  "enemy", "enemy_back")

    -- flex row 容器: spacer + col + spacer + col + center spacer + col + spacer + col + spacer
    gridRow_ = UI.Panel {
        width          = "100%",
        height         = "100%",
        paddingTop     = TOP_MARGIN,
        paddingBottom  = BOT_MARGIN,
        flexDirection  = "row",
        alignItems     = "stretch",
        children       = {
            spacer(GROW_OUTER),     -- 左侧留白
            colAllyBack,            -- 我方后排
            spacer(GROW_INNER),     -- 后排-前排间距
            colAllyFront,           -- 我方前排
            spacer(GROW_CENTER),    -- 中线留白
            colEnemyFront,          -- 敌方前排
            spacer(GROW_INNER),     -- 前排-后排间距
            colEnemyBack,           -- 敌方后排
            spacer(GROW_OUTER),     -- 右侧留白
        },
    }

    parent:AddChild(gridRow_)
end

--- 更新单位状态
function M.UpdateUnit(unitId, hp, maxHp, morale, statuses, alive)
    local info = unitCards_[unitId]
    if not info then return end

    if info.hpBar then
        local ratio = alive and math.max(0, hp / maxHp) or 0
        info.hpBar:SetValue(ratio)
    end

    if info.moraleBar then
        info.moraleBar:SetValue((morale or 0) / 100)
    end

    if not alive then
        info.panel:SetStyle({ opacity = 0.3 })
    end

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

--- 高亮当前行动者 (缩放 + 攻击精灵切换)
function M.HighlightUnit(unitId)
    local info = unitCards_[unitId]
    if info then

        -- 攻击精灵切换动画
        if info.spriteAtk then
            info.avatar:SetStyle({ backgroundImage = info.spriteAtk })
        end

        -- 缩放弹跳动画
        info.panel:Animate({
            keyframes = { { scale = 1.12 }, { scale = 1.0 } },
            duration  = 0.35,
            easing    = "easeOutBack",
        })

        -- 延迟恢复 idle 精灵 (通过定时器队列)
        if info.spriteAtk and info.spriteIdle then
            atkTimers_[#atkTimers_ + 1] = { unitId = unitId, remaining = 0.4 }
        end
    end
    lastHighlight_ = unitId
end

--- 获取单位卡牌中心位置 (估算, 供特效定位)
function M.GetUnitPos(unitId)
    local info = unitCards_[unitId]
    if not info then return nil end

    -- 用 flex 比例估算 — 特效浮动文字近似即可
    local x = estimateColCenterX(info.colKey, containerW_)
    local y = estimateRowCenterY(info.rowIdx, containerH_)
    return { x = x, y = y }
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

--- 驱动攻击精灵恢复定时器 (需要每帧从 page_battle 调用)
function M.TickTimers(dt)
    local i = 1
    while i <= #atkTimers_ do
        local t = atkTimers_[i]
        t.remaining = t.remaining - dt
        if t.remaining <= 0 then
            local info = unitCards_[t.unitId]
            if info and info.avatar and info.spriteIdle then
                info.avatar:SetStyle({ backgroundImage = info.spriteIdle })
            end
            table.remove(atkTimers_, i)
        else
            i = i + 1
        end
    end
end

--- 清理
function M.Clear()
    unitCards_ = {}
    lastHighlight_ = nil
    atkTimers_ = {}
    container_ = nil
    gridRow_ = nil
end

return M
