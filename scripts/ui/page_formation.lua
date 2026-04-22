------------------------------------------------------------
-- ui/page_formation.lua  —— 三国神将录 阵容编辑页面
-- 前排2 + 后排3 布阵, 支持拖放 + 点击双模式
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local Modal = require("ui.modal_manager")
local DH    = require("data.data_heroes")
local DF    = require("data.data_formation")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

-- 内部状态
local pagePanel_, gameState_, callbacks_
local editFront_ = {}
local editBack_  = {}
local editFormation_ = "feng_shi"

-- UI 引用
local slotPanels_    = { front = {}, back = {} }
local powerLabel_, heroListContainer_, heroListScroll_
local formationBtnLabel_, formationDescLabel_, formationListPanel_

-- 拖放状态
local dragCtx_
local dragStartX_, dragStartY_ = 0, 0
local maybeDragHero_ = nil  -- { heroId, widget }
local cachedCtxLayout_ = nil  -- 拖拽期间缓存 context 绝对坐标(避免每帧重算)
local dragUpdateBound_ = false  -- Update 事件是否已绑定
local dragEndFrame_ = -1        -- 拖拽结束帧号(防止同帧 onClick 双重触发)

-- 英雄列表缓存: heroRows_[heroId] = { row=Panel, inLineup=bool }
local heroRows_ = {}
local heroOrder_ = {}  -- 排序后的 heroId 列表(创建时确定)

-- 前置声明(解决循环引用)
local refreshSlots
local refreshHeroList
local startHeroDrag

------------------------------------------------------------
-- 辅助
------------------------------------------------------------
local function isInLineup(heroId)
    for _, h in ipairs(editFront_) do if h == heroId then return true end end
    for _, h in ipairs(editBack_)  do if h == heroId then return true end end
    return false
end

local function calcTeamPower()
    local total = 0
    local all = {}
    for _, h in ipairs(editFront_) do all[#all + 1] = h end
    for _, h in ipairs(editBack_)  do all[#all + 1] = h end
    for _, hid in ipairs(all) do
        local hd = DH.Get(hid)
        local hs = gameState_.heroes[hid]
        if hd and hs then
            local gf = math.min((hs.level or 1) / 80, 1.0)
            total = total + math.floor(
                hd.stats.tong + (hd.caps.tong - hd.stats.tong) * gf +
                hd.stats.yong + (hd.caps.yong - hd.stats.yong) * gf +
                hd.stats.zhi  + (hd.caps.zhi  - hd.stats.zhi)  * gf)
        end
    end
    return total
end

local function getHeroStats(heroId)
    local hd = DH.Get(heroId)
    local hs = gameState_.heroes[heroId]
    if not hd or not hs then return nil end
    local lv = hs.level or 1
    local gf = math.min(lv / 80, 1.0)
    return {
        tong  = math.floor(hd.stats.tong + (hd.caps.tong - hd.stats.tong) * gf),
        yong  = math.floor(hd.stats.yong + (hd.caps.yong - hd.stats.yong) * gf),
        zhi   = math.floor(hd.stats.zhi  + (hd.caps.zhi  - hd.stats.zhi)  * gf),
        level = lv,
    }
end

--- 压缩数组(移除 nil 空洞)
local function compactArray(arr)
    local r = {}
    for _, v in ipairs(arr) do if v then r[#r + 1] = v end end
    return r
end

------------------------------------------------------------
-- 拖放系统
------------------------------------------------------------

--- 快速更新拖拽图标位置(绕过 SetStyle, 直接 Yoga API)
local DRAG_ICON_HALF = 26  -- 52 / 2
local function fastUpdateDragPos(x, y)
    if not dragCtx_ or not dragCtx_.isDragging_ then return end
    dragCtx_.cursorX_ = x
    dragCtx_.cursorY_ = y
    if not cachedCtxLayout_ then
        cachedCtxLayout_ = dragCtx_:GetAbsoluteLayout()
    end
    local iconNode = dragCtx_.dragIcon_.node
    YGNodeStyleSetPosition(iconNode, YGEdgeLeft, (x - cachedCtxLayout_.x) - DRAG_ICON_HALF)
    YGNodeStyleSetPosition(iconNode, YGEdgeTop,  (y - cachedCtxLayout_.y) - DRAG_ICON_HALF)
end

--- 停止拖拽追踪(取消 Update 事件订阅)
local function stopDragTracking()
    if dragUpdateBound_ then
        UnsubscribeFromEvent("Update")
        dragUpdateBound_ = false
    end
    maybeDragHero_ = nil
    -- 恢复英雄列表指针事件(拖拽期间被禁用以跳过 hit testing)
    if heroListScroll_ and heroListScroll_.props then
        heroListScroll_.props.pointerEvents = nil
    end
    -- 记录拖拽结束帧: UI 框架的 HandlePointerUp 会在同帧触发 onClick,
    -- 同帧内的 onClick 必须跳过以防止 "拖拽下阵 + 点击下阵" 双重触发
    dragEndFrame_ = time.frameNumber
end

--- 启动每帧拖拽追踪: 订阅 Update 事件, 轮询鼠标位置
local function startDragTracking()
    if dragUpdateBound_ then return end
    dragUpdateBound_ = true
    SubscribeToEvent("Update", function(eventType, eventData)
        local mx = input.mousePosition.x
        local my = input.mousePosition.y

        -- 阶段1: 未正式拖拽,检测拖动阈值
        if maybeDragHero_ and dragCtx_ and not dragCtx_:IsDragging() then
            -- 鼠标已松开但未达到拖拽阈值 → 取消预拖拽
            if not input:GetMouseButtonDown(MOUSEB_LEFT) then
                stopDragTracking()
                return
            end
            local dx = mx - dragStartX_
            local dy = my - dragStartY_
            if dx * dx + dy * dy > 16 then -- 4px 阈值
                local cache = heroRows_[maybeDragHero_.heroId]
                local widget = cache and cache.row
                startHeroDrag(
                    { heroId = maybeDragHero_.heroId, _srcType = "list" },
                    widget, maybeDragHero_.heroId, mx, my)
                maybeDragHero_ = nil
            end
        end

        -- 阶段2: 正在拖拽,更新位置
        if dragCtx_ and dragCtx_:IsDragging() then
            fastUpdateDragPos(mx, my)
            -- 检测鼠标释放
            if not input:GetMouseButtonDown(MOUSEB_LEFT) then
                local target = dragCtx_:FindDropTargetAt(mx, my)
                dragCtx_:EndDrag(target)
                stopDragTracking()
            end
        elseif not maybeDragHero_ then
            -- 既不在预拖拽也不在拖拽中,停止追踪
            stopDragTracking()
        end
    end)
end

--- 启动拖拽并设置武将头像为拖拽图标
startHeroDrag = function(itemData, widget, heroId, x, y)
    if not dragCtx_ then return end
    cachedCtxLayout_ = nil  -- 重置缓存,首次 move 时重算
    -- 禁用英雄列表指针事件: findWidgetAt 跳过 pointerEvents="none" 的子树
    if heroListScroll_ and heroListScroll_.props then
        heroListScroll_.props.pointerEvents = "none"
    end
    dragCtx_:StartDrag(itemData, widget, "", x, y)
    local hd = DH.Get(heroId)
    local qc = Theme.HeroQualityColor(hd and hd.quality or 0)
    dragCtx_.dragIcon_:SetStyle({
        backgroundImage = "Textures/heroes/hero_" .. heroId .. ".png",
        backgroundFit   = "cover",
        width = 52, height = 52,
        borderRadius = 6, borderColor = qc, borderWidth = 2,
    })
    dragCtx_.dragIconLabel_:SetText("")
end

local function initDragDrop()
    dragCtx_ = UI.DragDropContext {
        position = "absolute", width = 0, height = 0,
        canDrop = function(itemData, sourceSlot, targetSlot)
            local ti = targetSlot and targetSlot._fmtInfo
            if not ti then return false end
            if itemData._srcType == "list" then
                if isInLineup(itemData.heroId) then return false end
            elseif itemData._srcType == "slot" then
                local si = itemData._slotInfo
                if si.row == ti.row and si.idx == ti.idx then return false end
            end
            return true
        end,
        onDragEnd = function(itemData, sourceSlot, targetSlot, success)
            stopDragTracking()  -- 兜底: 确保 Update 事件已取消
            -- 槽位拖到空白区域 → 下阵
            if not targetSlot and itemData._srcType == "slot" then
                local si = itemData._slotInfo
                local arr = si.row == "front" and editFront_ or editBack_
                arr[si.idx] = nil
                if si.row == "front" then editFront_ = compactArray(arr)
                else editBack_ = compactArray(arr) end
                refreshSlots()
                return
            end
            if not success then return end
            local ti = targetSlot._fmtInfo
            local tArr = ti.row == "front" and editFront_ or editBack_
            if itemData._srcType == "list" then
                tArr[ti.idx] = itemData.heroId
            elseif itemData._srcType == "slot" then
                local si = itemData._slotInfo
                local sArr = si.row == "front" and editFront_ or editBack_
                local srcH, tgtH = sArr[si.idx], tArr[ti.idx]
                sArr[si.idx] = tgtH
                tArr[ti.idx] = srcH
            end
            refreshSlots()
        end,
        onDragCancel = function() stopDragTracking(); refreshSlots() end,
    }
end

------------------------------------------------------------
-- 槽位渲染(公共函数)
------------------------------------------------------------
local function renderSlotContent(panel, heroId, label)
    panel:ClearChildren()
    if heroId then
        local hd = DH.Get(heroId)
        local st = getHeroStats(heroId)
        local qc = Theme.HeroQualityColor(hd and hd.quality or 0)
        panel:AddChild(Comp.HeroAvatar({
            heroId = heroId, size = 52,
            quality = hd and hd.quality or 1,
            level = st and st.level or 1, showLevel = true,
        }))
        panel:AddChild(UI.Label {
            text = hd and hd.name or heroId, fontSize = 10,
            fontColor = qc, textAlign = "center", width = 60, maxLines = 1, marginTop = 2,
        })
        if st then
            panel:AddChild(UI.Label {
                text = "统"..st.tong.." 勇"..st.yong.." 智"..st.zhi,
                fontSize = 8, fontColor = C.textDim,
                textAlign = "center", width = 70, marginTop = 1,
            })
        end
    else
        panel:AddChild(UI.Panel {
            width = 52, height = 52, borderRadius = 6,
            borderColor = C.border, borderWidth = 2, borderStyle = "dashed",
            justifyContent = "center", alignItems = "center",
            backgroundColor = { 40, 50, 65, 180 },
            children = { UI.Label { text = "+", fontSize = 20, fontColor = C.textDim } },
        })
        panel:AddChild(UI.Label {
            text = label, fontSize = 9, fontColor = C.textDim,
            textAlign = "center", marginTop = 2,
        })
    end
end

------------------------------------------------------------
-- 刷新阵容槽位 UI
------------------------------------------------------------
function refreshSlots()
    for idx = 1, 2 do renderSlotContent(slotPanels_.front[idx], editFront_[idx], "前排"..idx) end
    for idx = 1, 3 do renderSlotContent(slotPanels_.back[idx],  editBack_[idx],  "后排"..idx) end
    if powerLabel_ then
        powerLabel_:SetText("预估战力: " .. Theme.FormatNumber(calcTeamPower()))
    end
    refreshHeroList()
end

------------------------------------------------------------
-- 槽位点击: 直接下阵
------------------------------------------------------------
local function onSlotClick(row, idx)
    if time.frameNumber == dragEndFrame_ then return end
    local arr = row == "front" and editFront_ or editBack_
    if arr[idx] then
        arr[idx] = nil
        if row == "front" then editFront_ = compactArray(arr)
        else editBack_ = compactArray(arr) end
        refreshSlots()
    end
end

------------------------------------------------------------
-- 刷新英雄选择列表
------------------------------------------------------------
--- 创建单个英雄行(仅在首次调用时执行,之后缓存复用)
local function createHeroRow(heroId)
    local hero = { id = heroId, data = DH.Get(heroId), state = gameState_.heroes[heroId] }
    if not hero.data then return nil end

    local stats = getHeroStats(heroId)
    local qColor = Theme.HeroQualityColor(hero.data.quality)
    local statsText = stats and ("统"..stats.tong.." 勇"..stats.yong.." 智"..stats.zhi) or ""

    local inLineupLabel = UI.Label { text = "[已上阵]", fontSize = 9, fontColor = C.jade }
    inLineupLabel:SetVisible(false)

    local heroRow
    heroRow = UI.Panel {
        width = "100%", height = 56,
        flexDirection = "row", alignItems = "center", gap = 8,
        paddingHorizontal = 8, paddingVertical = 4,
        backgroundColor = C.panel,
        borderRadius = 6, borderColor = C.border, borderWidth = 1,
        onClick = function()
            if time.frameNumber == dragEndFrame_ then return end
            if isInLineup(heroId) then
                Modal.Alert("提示", hero.data.name .. " 已在阵容中")
                return
            end
            local placed = false
            if #editFront_ < 2 then
                editFront_[#editFront_ + 1] = heroId; placed = true
            elseif #editBack_ < 3 then
                editBack_[#editBack_ + 1] = heroId; placed = true
            end
            if placed then refreshSlots()
            else Modal.Alert("提示", "阵容已满(前排2+后排3)") end
        end,
        onPointerDown = function(event)
            if isInLineup(heroId) then return end
            dragStartX_ = event.x
            dragStartY_ = event.y
            maybeDragHero_ = { heroId = heroId }
            startDragTracking()  -- 启动 Update 轮询,消除间隙死区
        end,
        children = {
            Comp.HeroAvatar({ heroId = heroId, size = 44, quality = hero.data.quality }),
            UI.Panel {
                flexGrow = 1, flexShrink = 1, flexDirection = "column", gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { text = hero.data.name, fontSize = 13, fontColor = qColor, fontWeight = "bold" },
                            UI.Label { text = "Lv."..(hero.state.level or 1), fontSize = 10, fontColor = C.textDim },
                            inLineupLabel,
                        },
                    },
                    UI.Label {
                        text = (hero.data.role or "").."  "..statsText,
                        fontSize = 10, fontColor = C.textDim, maxLines = 1,
                    },
                },
            },
            UI.Panel {
                width = 80, alignItems = "flex-end",
                children = {
                    UI.Label { text = hero.data.skill or "", fontSize = 10, fontColor = C.gold, textAlign = "right", maxLines = 1 },
                },
            },
        },
    }

    heroRows_[heroId] = { row = heroRow, inLineup = false, badge = inLineupLabel }
    return heroRow
end

--- 首次构建英雄列表(排序+创建行)
local function buildHeroListOnce()
    if not heroListContainer_ then return end
    heroListContainer_:ClearChildren()
    heroRows_ = {}
    heroOrder_ = {}

    local owned = {}
    for hid, _ in pairs(gameState_.heroes or {}) do
        local hData = DH.Get(hid)
        if hData then owned[#owned + 1] = { id = hid, data = hData } end
    end
    table.sort(owned, function(a, b)
        if a.data.quality ~= b.data.quality then return a.data.quality > b.data.quality end
        return a.id < b.id
    end)
    for _, h in ipairs(owned) do
        heroOrder_[#heroOrder_ + 1] = h.id
        local row = createHeroRow(h.id)
        if row then heroListContainer_:AddChild(row) end
    end
end

--- 增量刷新英雄列表: 只更新上阵状态样式(不销毁/重建)
function refreshHeroList()  ---@diagnostic disable-line: lowercase-global
    for _, heroId in ipairs(heroOrder_) do
        local cache = heroRows_[heroId]
        if cache then
            local inNow = isInLineup(heroId)
            if cache.inLineup ~= inNow then
                cache.inLineup = inNow
                cache.row:SetStyle({
                    backgroundColor = inNow and { 60, 70, 50, 180 } or C.panel,
                    opacity = inNow and 0.6 or 1.0,
                })
                cache.badge:SetVisible(inNow)
            end
        end
    end
end

------------------------------------------------------------
-- 阵法选择器
------------------------------------------------------------
local function refreshFormationDisplay()
    local f = DF.Get(editFormation_)
    if formationBtnLabel_ then formationBtnLabel_.text = f and f.name or "锋矢阵" end
    if formationDescLabel_ then formationDescLabel_.text = f and f.detail or "" end
end

local function buildFormationList()
    if not formationListPanel_ then return end
    formationListPanel_:ClearChildren()
    local formations = DF.GetAllWithStatus(gameState_)
    for _, fi in ipairs(formations) do
        local isSel = fi.id == editFormation_
        local isLock = not fi.unlocked
        local unlockText = ""
        if fi.unlock.type == "map" then unlockText = "通关"..fi.unlock.value.."张地图解锁" end
        local buffTexts = {}
        if fi.buffs then
            for attr, val in pairs(fi.buffs) do
                buffTexts[#buffTexts + 1] = DF.GetBuffName(attr)..DF.FormatBuff(attr, val)
            end
        end
        local rowBg = isSel and { 80,60,30,220 } or (isLock and { 30,30,35,200 } or { 40,45,55,200 })
        formationListPanel_:AddChild(UI.Panel {
            width = "100%", flexDirection = "column", padding = 6, gap = 2,
            backgroundColor = rowBg, borderRadius = 6,
            borderColor = isSel and C.gold or C.border, borderWidth = isSel and 2 or 1,
            opacity = isLock and 0.5 or 1.0,
            onClick = function()
                if isLock then Modal.Alert("未解锁", fi.name.."需要"..unlockText); return end
                editFormation_ = fi.id
                refreshFormationDisplay()
                formationListPanel_:SetVisible(false)
                YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayNone)
            end,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row", alignItems = "center", gap = 6,
                    children = {
                        UI.Label { text = fi.name, fontSize = 12, fontColor = isSel and C.gold or (isLock and C.textDim or C.text), fontWeight = "bold" },
                        isSel and UI.Label { text = "[当前]", fontSize = 9, fontColor = C.gold } or nil,
                        isLock and UI.Label { text = "["..unlockText.."]", fontSize = 9, fontColor = { 180,80,80,255 } } or nil,
                    },
                },
                UI.Label { text = table.concat(buffTexts, "  "), fontSize = 9, fontColor = isLock and C.textDim or C.jade, maxLines = 2 },
            },
        })
    end
end

local function toggleFormationList()
    if not formationListPanel_ then return end
    local vis = formationListPanel_:IsVisible()
    if vis then
        formationListPanel_:SetVisible(false)
        YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayNone)
    else
        buildFormationList()
        formationListPanel_:SetVisible(true)
        YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayFlex)
    end
end

------------------------------------------------------------
-- 保存阵容
------------------------------------------------------------
local function saveLineup()
    gameState_.lineup.formation = editFormation_
    gameState_.lineup.front, gameState_.lineup.back = {}, {}
    for _, h in ipairs(editFront_) do gameState_.lineup.front[#gameState_.lineup.front + 1] = h end
    for _, h in ipairs(editBack_)  do gameState_.lineup.back[#gameState_.lineup.back + 1] = h end
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------
function M.Create(gameState, callbacks)
    gameState_ = gameState
    callbacks_ = callbacks or {}
    slotPanels_ = { front = {}, back = {} }

    editFront_, editBack_ = {}, {}
    editFormation_ = gameState.lineup.formation or DF.GetDefault()
    for _, h in ipairs(gameState.lineup.front or {}) do editFront_[#editFront_ + 1] = h end
    for _, h in ipairs(gameState.lineup.back  or {}) do editBack_[#editBack_ + 1] = h end

    -- 初始化拖放
    initDragDrop()

    powerLabel_ = UI.Label {
        text = "预估战力: "..Theme.FormatNumber(calcTeamPower()),
        fontSize = Theme.fontSize.subtitle, fontColor = C.gold, fontWeight = "bold",
    }

    -- 创建槽位面板(含拖放事件)
    local function makeSlot(row, i)
        local slot
        slot = UI.Panel {
            width = 72, alignItems = "center", gap = 2, paddingVertical = 4,
            onClick = function() onSlotClick(row, i) end,
            onPointerDown = function(event)
                local arr = row == "front" and editFront_ or editBack_
                if arr[i] and dragCtx_ then
                    startHeroDrag(
                        { heroId = arr[i], _srcType = "slot", _slotInfo = { row = row, idx = i } },
                        slot, arr[i], event.x, event.y)
                    startDragTracking()  -- 启动 Update 轮询
                end
            end,
            onPointerEnter = function(event, self)
                if dragCtx_ and dragCtx_:IsDragging() then
                    local item = dragCtx_:GetDragData()
                    local ok = true
                    if item._srcType == "list" and isInLineup(item.heroId) then ok = false end
                    if item._srcType == "slot" and item._slotInfo.row == row and item._slotInfo.idx == i then ok = false end
                    self:SetStyle({ borderColor = ok and {100,200,100,255} or {200,100,100,255}, borderWidth = 2 })
                end
            end,
            onPointerLeave = function(event, self)
                self:SetStyle({ borderColor = {0,0,0,0}, borderWidth = 0 })
            end,
        }
        slot._fmtInfo = { row = row, idx = i }
        dragCtx_:RegisterDropTarget(slot)
        slotPanels_[row][i] = slot
        return slot
    end

    local frontSlots = {}
    for i = 1, 2 do frontSlots[i] = makeSlot("front", i) end
    local backSlots = {}
    for i = 1, 3 do backSlots[i] = makeSlot("back", i) end

    -- 阵法选择
    local curF = DF.Get(editFormation_)
    formationBtnLabel_ = UI.Label { text = curF and curF.name or "锋矢阵", fontSize = 12, fontColor = C.gold, fontWeight = "bold" }
    formationDescLabel_ = UI.Label { text = curF and curF.detail or "", fontSize = 9, fontColor = C.jade, maxLines = 1 }

    formationListPanel_ = UI.ScrollView {
        width = "100%", maxHeight = 180, scrollY = true, gap = 4, padding = 4,
        backgroundColor = { 25,30,40,240 }, borderRadius = 6,
        borderColor = C.gold, borderWidth = 1,
    }
    formationListPanel_:SetVisible(false)
    YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayNone)

    local formationSelector = UI.Panel {
        width = "100%", gap = 4,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center",
                justifyContent = "space-between",
                paddingHorizontal = 6, paddingVertical = 4,
                backgroundColor = { 50,45,30,200 }, borderRadius = 6,
                borderColor = C.gold, borderWidth = 1,
                onClick = toggleFormationList,
                children = {
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6,
                        children = {
                            UI.Label { text = "阵法:", fontSize = 11, fontColor = C.textDim },
                            formationBtnLabel_,
                        },
                    },
                    UI.Panel { flexDirection = "column", alignItems = "flex-end", flexShrink = 1,
                        children = { formationDescLabel_ },
                    },
                },
            },
            formationListPanel_,
        },
    }

    -- 阵容区域
    local formationPanel = UI.Panel {
        width = "100%", padding = 8, gap = 4, alignItems = "center",
        backgroundColor = { C.panel[1], C.panel[2], C.panel[3], 200 }, borderRadius = 8,
        children = {
            UI.Panel { width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginBottom = 4,
                children = {
                    UI.Label { text = "阵容编辑", fontSize = Theme.fontSize.title, fontColor = C.gold, fontWeight = "bold" },
                    powerLabel_,
                },
            },
            formationSelector,
            Comp.SanDivider({ spacing = 4 }),
            UI.Label { text = "前排 (坦克/近战)", fontSize = Theme.fontSize.caption, fontColor = C.textDim, marginBottom = 2 },
            UI.Panel { flexDirection = "row", justifyContent = "center", gap = 16, children = frontSlots },
            UI.Label { text = "后排 (输出/辅助)", fontSize = Theme.fontSize.caption, fontColor = C.textDim, marginTop = 6, marginBottom = 2 },
            UI.Panel { flexDirection = "row", justifyContent = "center", gap = 12, children = backSlots },
        },
    }

    -- 按钮行
    local buttonRow = UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "center", gap = 12, paddingVertical = 6,
        children = {
            Comp.SanButton({ text = "清空阵容", variant = "secondary", width = 100, height = S.btnSmHeight, fontSize = S.btnSmFontSize,
                onClick = function()
                    Modal.Confirm("确认", "确定清空当前阵容？", function()
                        editFront_, editBack_ = {}, {}
                        refreshSlots()
                    end)
                end,
            }),
            Comp.SanButton({ text = "保存阵容", variant = "primary", width = 140, height = S.btnSmHeight, fontSize = S.btnSmFontSize,
                onClick = function()
                    local total = #editFront_ + #editBack_
                    if total == 0 then Modal.Alert("提示", "阵容至少需要1名武将！"); return end
                    saveLineup()
                    local fName = DF.Get(editFormation_)
                    fName = fName and fName.name or editFormation_
                    Modal.Alert("保存成功", "阵容已更新！共"..total.."名武将\n阵法: "..fName)
                    if callbacks_.onSave then callbacks_.onSave() end
                end,
            }),
        },
    }

    -- 英雄列表
    heroListContainer_ = UI.Panel { width = "100%", flexDirection = "column", gap = 4, padding = 4 }
    heroListScroll_ = UI.ScrollView { flexGrow = 1, flexBasis = 0, scrollY = true, padding = 4, children = { heroListContainer_ } }

    pagePanel_ = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0, flexDirection = "row", backgroundColor = C.bg,
        children = {
            UI.Panel { width = "45%", flexDirection = "column", padding = 8, gap = 6,
                children = { formationPanel, buttonRow },
            },
            UI.Panel { width = 1, backgroundColor = C.divider },
            UI.Panel { flexGrow = 1, flexBasis = 0, flexDirection = "column",
                children = {
                    UI.Panel { width = "100%", flexDirection = "row", alignItems = "center", justifyContent = "space-between", paddingHorizontal = 8, paddingVertical = 4,
                        children = {
                            UI.Label { text = "可选武将", fontSize = Theme.fontSize.subtitle, fontColor = C.text, fontWeight = "bold" },
                            UI.Label { text = "拖拽或点击武将上阵", fontSize = Theme.fontSize.caption, fontColor = C.textDim },
                        },
                    },
                    Comp.SanDivider({ spacing = 2 }),
                    heroListScroll_,
                },
            },
            dragCtx_,
        },
    }

    buildHeroListOnce()
    refreshSlots()
    return pagePanel_
end

function M.Refresh(gameState)
    if not pagePanel_ then return end
    gameState_ = gameState
    editFront_, editBack_ = {}, {}
    editFormation_ = gameState.lineup.formation or DF.GetDefault()
    for _, h in ipairs(gameState.lineup.front or {}) do editFront_[#editFront_ + 1] = h end
    for _, h in ipairs(gameState.lineup.back  or {}) do editBack_[#editBack_ + 1] = h end
    refreshFormationDisplay()
    -- 全量刷新: 英雄可能升级/新增,需要重建列表
    buildHeroListOnce()
    refreshSlots()
end

return M
