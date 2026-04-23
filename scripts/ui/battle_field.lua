------------------------------------------------------------
-- ui/battle_field.lua  —— 战场武将卡牌组件
-- 布局: 以屏幕中线为轴，左右对称 4 列 × 3 行网格
--   我方后排 ← 我方前排 | 中线 | 敌方前排 → 敌方后排
-- 行: 按单位数居中 (1人→行2, 2人→行1/3, 3人→行1/2/3)
-- 卡片尺寸由行高动态决定，保证不重叠
-- 参考: 风云天下 — 卡牌铺满战场，结果按钮浮在上层
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 布局常量
------------------------------------------------------------
-- 顶栏是 absolute 浮层(54px)，底部结果按钮也是 absolute 浮层
-- 参考风云天下: 卡牌铺满战场，按钮浮在上层，不需要大量预留
local TOP_MARGIN = 56   -- 仅避开顶栏遮挡
local BOT_MARGIN = 8    -- 底边最小留白(结果按钮浮层不占布局空间)
local ROW_GAP    = 4    -- 行间最小间距

-- 对称列位置: 以 0.50 为中线, 前排/后排各有固定偏移
local CENTER       = 0.50
local INNER_OFFSET = 0.13   -- 前排距中线
local OUTER_OFFSET = 0.28   -- 后排距中线

-- 4 列中心 X (屏幕宽度比例), 完美对称
local COL_X = {
    ally_back   = CENTER - OUTER_OFFSET,   -- 0.22
    ally_front  = CENTER - INNER_OFFSET,   -- 0.37
    enemy_front = CENTER + INNER_OFFSET,   -- 0.63
    enemy_back  = CENTER + OUTER_OFFSET,   -- 0.78
}

-- 卡片尺寸上限
local MAX_CARD_W = 120
local MAX_CARD_H = 150
local AVATAR_RATIO = 0.78   -- 头像占卡片高度比例

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
local panelW_, panelH_ = 0, 0
local lastHighlight_ = nil
local cardW_, cardH_, avatarSize_ = 100, 130, 80

------------------------------------------------------------
-- 行位置计算: 3 行均匀分布在安全区
------------------------------------------------------------
local function calcRowCenters(pH)
    local y0 = TOP_MARGIN
    local y1 = pH - BOT_MARGIN
    local rowH = (y1 - y0) / 3
    return {
        y0 + rowH * 0.5,   -- 行1 中心
        y0 + rowH * 1.5,   -- 行2 中心
        y0 + rowH * 2.5,   -- 行3 中心
    }, rowH
end

--- 根据行高计算卡片尺寸
local function calcCardSize(rowH)
    local ch = math.min(MAX_CARD_H, math.floor(rowH - ROW_GAP))
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
-- 创建单个卡牌
------------------------------------------------------------
local function createCard(unit, side, posX, posY)
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

    local imgPath = unit.heroId
        and ("Textures/heroes/hero_" .. unit.heroId .. ".png")
        or nil

    local avatar = UI.Panel {
        width           = avatarSize_,
        height          = avatarSize_,
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
                fontSize  = nameFontSize,
                fontColor = C.text,
                textAlign = "center",
            },
        } or {},
    }

    local card = UI.Panel {
        position   = "absolute",
        left       = posX,
        top        = posY,
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
        posX        = posX,
        posY        = posY,
    }

    return card
end

------------------------------------------------------------
-- 将一组单位放入指定列
------------------------------------------------------------
local function placeUnitsInColumn(units, side, colXFrac, rowCenters, pW)
    local cards = {}
    local n = #units
    if n == 0 then return cards end

    local rows = assignRows(n)
    local centerX = math.floor(colXFrac * pW)

    for i, unit in ipairs(units) do
        if i > 3 then break end
        local rowIdx = rows[i]
        local posX = math.floor(centerX - cardW_ / 2)
        local posY = math.floor(rowCenters[rowIdx] - cardH_ / 2)
        local posBottom = posY + cardH_
        print(string.format(
            "[BattleField] %s %s: col=%.2f row=%d posX=%d posY=%d bottom=%d (panelH=%.0f)",
            side, unit.name or "?", colXFrac, rowIdx, posX, posY, posBottom, panelH_))
        cards[#cards + 1] = createCard(unit, side, posX, posY)
    end
    return cards
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

function M.Create(parent, allies, enemies, pW, pH)
    container_ = parent
    panelW_ = pW
    panelH_ = pH
    unitCards_ = {}
    lastHighlight_ = nil

    -- 计算 3 行中心 Y 和行高
    local rowCenters, rowH = calcRowCenters(pH)

    -- 根据行高计算卡片尺寸
    cardW_, cardH_, avatarSize_ = calcCardSize(rowH)

    print(string.format(
        "[BattleField] pW=%.0f pH=%.0f rowH=%.0f cardW=%d cardH=%d avatar=%d TOP=%d BOT=%d",
        pW, pH, rowH, cardW_, cardH_, avatarSize_, TOP_MARGIN, BOT_MARGIN))
    print(string.format(
        "[BattleField] 行中心Y: row1=%.0f row2=%.0f row3=%.0f  安全区=[%d ~ %.0f]",
        rowCenters[1], rowCenters[2], rowCenters[3], TOP_MARGIN, pH - BOT_MARGIN))
    print(string.format(
        "[BattleField] 列中心X: ally_back=%.0f ally_front=%.0f | enemy_front=%.0f enemy_back=%.0f",
        COL_X.ally_back * pW, COL_X.ally_front * pW,
        COL_X.enemy_front * pW, COL_X.enemy_back * pW))

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

    -- 布局 4 列 (对称)
    local allCards = {}
    local groups = {
        { allyBack,   COL_X.ally_back },
        { allyFront,  COL_X.ally_front },
        { enemyFront, COL_X.enemy_front },
        { enemyBack,  COL_X.enemy_back },
    }
    for _, g in ipairs(groups) do
        local side = (g[2] < CENTER) and "ally" or "enemy"
        local cards = placeUnitsInColumn(g[1], side, g[2], rowCenters, pW)
        for _, c in ipairs(cards) do allCards[#allCards + 1] = c end
    end

    for _, card in ipairs(allCards) do
        parent:AddChild(card)
    end
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

--- 高亮当前行动者
function M.HighlightUnit(unitId)
    if lastHighlight_ and unitCards_[lastHighlight_] then
        local prev = unitCards_[lastHighlight_]
        prev.avatar:SetStyle({ borderWidth = 2 })
    end
    local info = unitCards_[unitId]
    if info then
        info.avatar:SetStyle({ borderWidth = 4 })
        info.panel:Animate({
            keyframes = { { scale = 1.08 }, { scale = 1.0 } },
            duration  = 0.3,
            easing    = "easeOutBack",
        })
    end
    lastHighlight_ = unitId
end

--- 获取单位卡牌中心位置
function M.GetUnitPos(unitId)
    local info = unitCards_[unitId]
    if not info then return nil end
    return {
        x = info.posX + cardW_ / 2,
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
