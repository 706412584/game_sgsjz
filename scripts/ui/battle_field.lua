------------------------------------------------------------
-- ui/battle_field.lua  —— 战场武将卡牌组件
-- 布局: 敌我各一个 3×3 九宫格 (3列×3行=9格)
-- 列: 后排=远端列, 前排=近端列, 中间列预留
-- 行: 按单位数居中分配 (1人→行2, 2人→行1/3, 3人→行1/2/3)
-- 卡片尺寸根据格子大小动态计算，确保不重叠
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 布局常量
------------------------------------------------------------
local TOP_MARGIN = 58   -- 顶栏(54px) + padding
local BOT_MARGIN = 55   -- 底部按钮区
local CELL_PAD   = 4    -- 格子内边距

-- 两侧区域在屏幕宽度中的范围 (比例)
local ALLY_X0  = 0.02   -- 我方区域左边
local ALLY_X1  = 0.46   -- 我方区域右边
local ENEMY_X0 = 0.54   -- 敌方区域左边
local ENEMY_X1 = 0.98   -- 敌方区域右边

-- 最大卡片尺寸
local MAX_CARD_W = 110
local MAX_CARD_H = 140
local AVATAR_RATIO = 0.62  -- 头像占卡片高度

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
local cardW_, cardH_, avatarSize_ = 100, 130, 78

------------------------------------------------------------
-- 九宫格计算
------------------------------------------------------------

--- 计算网格参数: 3列中心X, 3行中心Y, 格子宽高, 卡片尺寸
local function calcGrid(pW, pH, x0Frac, x1Frac)
    local x0 = math.floor(pW * x0Frac)
    local x1 = math.floor(pW * x1Frac)
    local y0 = TOP_MARGIN
    local y1 = pH - BOT_MARGIN

    local colW = (x1 - x0) / 3
    local rowH = (y1 - y0) / 3

    -- 3列中心X
    local colCenters = {
        x0 + colW * 0.5,
        x0 + colW * 1.5,
        x0 + colW * 2.5,
    }
    -- 3行中心Y
    local rowCenters = {
        y0 + rowH * 0.5,
        y0 + rowH * 1.5,
        y0 + rowH * 2.5,
    }

    -- 卡片尺寸 = 格子大小 - padding, 但不超过最大值
    local cw = math.min(MAX_CARD_W, math.floor(colW - CELL_PAD * 2))
    local ch = math.min(MAX_CARD_H, math.floor(rowH - CELL_PAD * 2))
    -- 保持宽高比
    if cw > ch * (MAX_CARD_W / MAX_CARD_H) then
        cw = math.floor(ch * (MAX_CARD_W / MAX_CARD_H))
    end
    local av = math.floor(ch * AVATAR_RATIO)

    return colCenters, rowCenters, cw, ch, av
end

--- N 个单位分配到 3 行 (居中分布), 返回行索引数组
local function assignRows(count)
    if count <= 0 then return {} end
    if count == 1 then return { 2 } end          -- 中间行
    if count == 2 then return { 1, 3 } end        -- 上下行
    return { 1, 2, 3 }                            -- 全部行
end

------------------------------------------------------------
-- 创建单个卡牌
------------------------------------------------------------
local function createCard(unit, side, posX, posY)
    local nameColor = side == "ally" and C.jade or C.red
    local hpColor   = side == "ally" and C.hp  or C.red

    local hpH  = math.max(4, math.floor(cardH_ * 0.04))
    local morH = math.max(3, math.floor(cardH_ * 0.03))
    local nameFontSize  = cardH_ < 100 and 8 or (cardH_ < 120 and 9 or 10)
    local statusFontSize = cardH_ < 100 and 7 or (cardH_ < 120 and 8 or 9)

    local hpBar = UI.ProgressBar {
        value           = 1.0,
        width           = cardW_ - 6,
        height          = hpH,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 2,
        fillColor       = hpColor,
        transition      = "value 0.3s easeOut",
    }

    local moraleBar = UI.ProgressBar {
        value           = (unit.morale or 0) / 100,
        width           = cardW_ - 6,
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
        borderRadius    = 6,
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
-- 将一组单位放入指定列的格子中
-- colCenter: 列中心X, rowCenters: 3行中心Y数组
------------------------------------------------------------
local function placeUnitsInColumn(units, side, colCenter, rowCenters)
    local cards = {}
    local n = #units
    if n == 0 then return cards end

    local rows = assignRows(n)
    for i, unit in ipairs(units) do
        if i > 3 then break end
        local rowIdx = rows[i]
        local posX = math.floor(colCenter - cardW_ / 2)
        local posY = math.floor(rowCenters[rowIdx] - cardH_ / 2)
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

    -- 计算我方九宫格
    local aCols, aRows, aw, ah, aav = calcGrid(pW, pH, ALLY_X0, ALLY_X1)
    -- 计算敌方九宫格
    local eCols, eRows, ew, eh, eav = calcGrid(pW, pH, ENEMY_X0, ENEMY_X1)

    -- 取两侧较小值作为统一卡片尺寸 (保持视觉一致)
    cardW_      = math.min(aw, ew)
    cardH_      = math.min(ah, eh)
    avatarSize_ = math.min(aav, eav)

    print(string.format(
        "[BattleField] pW=%d pH=%d cardW=%d cardH=%d avatar=%d",
        pW, pH, cardW_, cardH_, avatarSize_))

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

    -- 我方九宫格:
    --   列1(最左) = 后排, 列2(中) = 空, 列3(最右/靠中间) = 前排
    local allyBackCards  = placeUnitsInColumn(allyBack,  "ally", aCols[1], aRows)
    local allyFrontCards = placeUnitsInColumn(allyFront, "ally", aCols[3], aRows)

    -- 敌方九宫格 (镜像):
    --   列1(最左/靠中间) = 前排, 列2(中) = 空, 列3(最右) = 后排
    local enemyFrontCards = placeUnitsInColumn(enemyFront, "enemy", eCols[1], eRows)
    local enemyBackCards  = placeUnitsInColumn(enemyBack,  "enemy", eCols[3], eRows)

    -- 添加到容器
    local allCards = {}
    for _, c in ipairs(allyBackCards)   do allCards[#allCards + 1] = c end
    for _, c in ipairs(allyFrontCards)  do allCards[#allCards + 1] = c end
    for _, c in ipairs(enemyFrontCards) do allCards[#allCards + 1] = c end
    for _, c in ipairs(enemyBackCards)  do allCards[#allCards + 1] = c end

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
