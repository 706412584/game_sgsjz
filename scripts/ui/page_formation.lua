------------------------------------------------------------
-- ui/page_formation.lua  —— 三国神将录 阵容编辑页面
-- 前排2 + 后排3 布阵 → 从已有英雄中选择上阵
-- 显示三围预览/总战力估算
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
local pagePanel_
local gameState_
local callbacks_

-- 当前编辑中的阵容(临时副本)
local editFront_ = {}   -- { heroId1, heroId2 }
local editBack_  = {}   -- { heroId1, heroId2, heroId3 }
local editFormation_ = "feng_shi"  -- 当前选中阵法ID

-- 选择中的槽位 (nil=未选择)
local selectedSlot_ = nil  -- { row="front"|"back", idx=1..N }

-- UI 引用(用于动态更新)
local slotPanels_    = {}   -- { front={}, back={} }
local powerLabel_
local heroListContainer_
local formationBtnLabel_     -- 阵法按钮上的名称
local formationDescLabel_    -- 阵法效果描述
local formationListPanel_    -- 阵法选择下拉面板

------------------------------------------------------------
-- 辅助
------------------------------------------------------------

--- 检查英雄是否已在阵容中
local function isInLineup(heroId)
    for _, h in ipairs(editFront_) do
        if h == heroId then return true end
    end
    for _, h in ipairs(editBack_) do
        if h == heroId then return true end
    end
    return false
end

--- 计算阵容估算战力
local function calcTeamPower()
    local total = 0
    local allSlots = {}
    for _, h in ipairs(editFront_) do allSlots[#allSlots + 1] = h end
    for _, h in ipairs(editBack_)  do allSlots[#allSlots + 1] = h end

    for _, hid in ipairs(allSlots) do
        local heroData = DH.Get(hid)
        local heroState = gameState_.heroes[hid]
        if heroData and heroState then
            local lv = heroState.level or 1
            local gf = math.min(lv / 80, 1.0)
            local tong = heroData.stats.tong + (heroData.caps.tong - heroData.stats.tong) * gf
            local yong = heroData.stats.yong + (heroData.caps.yong - heroData.stats.yong) * gf
            local zhi  = heroData.stats.zhi  + (heroData.caps.zhi  - heroData.stats.zhi)  * gf
            total = total + math.floor(tong + yong + zhi)
        end
    end
    return total
end

--- 获取英雄三围(含等级成长)
local function getHeroStats(heroId)
    local heroData = DH.Get(heroId)
    local heroState = gameState_.heroes[heroId]
    if not heroData or not heroState then return nil end
    local lv = heroState.level or 1
    local gf = math.min(lv / 80, 1.0)
    return {
        tong = math.floor(heroData.stats.tong + (heroData.caps.tong - heroData.stats.tong) * gf),
        yong = math.floor(heroData.stats.yong + (heroData.caps.yong - heroData.stats.yong) * gf),
        zhi  = math.floor(heroData.stats.zhi  + (heroData.caps.zhi  - heroData.stats.zhi)  * gf),
        level = lv,
    }
end

------------------------------------------------------------
-- 刷新阵容槽位 UI
------------------------------------------------------------
local function refreshSlots()
    -- 前排
    for idx = 1, 2 do
        local panel = slotPanels_.front[idx]
        if panel then
            panel:ClearChildren()
            local heroId = editFront_[idx]
            if heroId then
                local heroData = DH.Get(heroId)
                local stats = getHeroStats(heroId)
                local qColor = Theme.QualityColor(heroData and (heroData.quality + 1) or 1)
                -- 头像
                panel:AddChild(Comp.HeroAvatar({
                    heroId   = heroId,
                    size     = 52,
                    quality  = heroData and heroData.quality or 1,
                    level    = stats and stats.level or 1,
                    showLevel = true,
                }))
                -- 名字
                panel:AddChild(UI.Label {
                    text      = heroData and heroData.name or heroId,
                    fontSize  = 10,
                    fontColor = qColor,
                    textAlign = "center",
                    width     = 60,
                    maxLines  = 1,
                    marginTop = 2,
                })
                -- 三围简略
                if stats then
                    panel:AddChild(UI.Label {
                        text      = "统" .. stats.tong .. " 勇" .. stats.yong .. " 智" .. stats.zhi,
                        fontSize  = 8,
                        fontColor = C.textDim,
                        textAlign = "center",
                        width     = 70,
                        marginTop = 1,
                    })
                end
            else
                -- 空槽
                panel:AddChild(UI.Panel {
                    width           = 52,
                    height          = 52,
                    borderRadius    = 6,
                    borderColor     = C.border,
                    borderWidth     = 2,
                    borderStyle     = "dashed",
                    justifyContent  = "center",
                    alignItems      = "center",
                    backgroundColor = { 40, 50, 65, 180 },
                    children = {
                        UI.Label {
                            text      = "+",
                            fontSize  = 20,
                            fontColor = C.textDim,
                        },
                    },
                })
                panel:AddChild(UI.Label {
                    text      = "前排" .. idx,
                    fontSize  = 9,
                    fontColor = C.textDim,
                    textAlign = "center",
                    marginTop = 2,
                })
            end
        end
    end

    -- 后排
    for idx = 1, 3 do
        local panel = slotPanels_.back[idx]
        if panel then
            panel:ClearChildren()
            local heroId = editBack_[idx]
            if heroId then
                local heroData = DH.Get(heroId)
                local stats = getHeroStats(heroId)
                local qColor = Theme.QualityColor(heroData and (heroData.quality + 1) or 1)
                panel:AddChild(Comp.HeroAvatar({
                    heroId   = heroId,
                    size     = 52,
                    quality  = heroData and heroData.quality or 1,
                    level    = stats and stats.level or 1,
                    showLevel = true,
                }))
                panel:AddChild(UI.Label {
                    text      = heroData and heroData.name or heroId,
                    fontSize  = 10,
                    fontColor = qColor,
                    textAlign = "center",
                    width     = 60,
                    maxLines  = 1,
                    marginTop = 2,
                })
                if stats then
                    panel:AddChild(UI.Label {
                        text      = "统" .. stats.tong .. " 勇" .. stats.yong .. " 智" .. stats.zhi,
                        fontSize  = 8,
                        fontColor = C.textDim,
                        textAlign = "center",
                        width     = 70,
                        marginTop = 1,
                    })
                end
            else
                panel:AddChild(UI.Panel {
                    width           = 52,
                    height          = 52,
                    borderRadius    = 6,
                    borderColor     = C.border,
                    borderWidth     = 2,
                    borderStyle     = "dashed",
                    justifyContent  = "center",
                    alignItems      = "center",
                    backgroundColor = { 40, 50, 65, 180 },
                    children = {
                        UI.Label {
                            text      = "+",
                            fontSize  = 20,
                            fontColor = C.textDim,
                        },
                    },
                })
                panel:AddChild(UI.Label {
                    text      = "后排" .. idx,
                    fontSize  = 9,
                    fontColor = C.textDim,
                    textAlign = "center",
                    marginTop = 2,
                })
            end
        end
    end

    -- 更新战力
    if powerLabel_ then
        powerLabel_.text = "预估战力: " .. Theme.FormatNumber(calcTeamPower())
    end

    -- 刷新英雄列表中已上阵标记
    refreshHeroList()
end

------------------------------------------------------------
-- 槽位点击处理
------------------------------------------------------------
local function onSlotClick(row, idx)
    -- 如果槽位有英雄 → 下阵
    local lineupArr = row == "front" and editFront_ or editBack_
    if lineupArr[idx] then
        -- 弹窗确认下阵
        local heroName = DH.GetName(lineupArr[idx])
        Modal.Confirm("下阵确认", "确定将 " .. heroName .. " 移出阵容？", function()
            lineupArr[idx] = nil
            -- 压缩数组(移除nil洞)
            local newArr = {}
            for _, v in ipairs(lineupArr) do
                if v then newArr[#newArr + 1] = v end
            end
            if row == "front" then editFront_ = newArr else editBack_ = newArr end
            selectedSlot_ = nil
            refreshSlots()
        end)
        return
    end

    -- 空槽 → 进入选择模式，高亮此槽位
    selectedSlot_ = { row = row, idx = idx }
    refreshSlots()
    refreshHeroList()
end

------------------------------------------------------------
-- 刷新英雄选择列表
------------------------------------------------------------
function refreshHeroList()
    if not heroListContainer_ then return end
    heroListContainer_:ClearChildren()

    -- 获取玩家拥有的英雄(按品质降序)
    local ownedHeroes = {}
    for hid, hState in pairs(gameState_.heroes) do
        local hData = DH.Get(hid)
        if hData then
            ownedHeroes[#ownedHeroes + 1] = {
                id    = hid,
                data  = hData,
                state = hState,
            }
        end
    end
    table.sort(ownedHeroes, function(a, b)
        if a.data.quality ~= b.data.quality then
            return a.data.quality > b.data.quality
        end
        return a.id < b.id
    end)

    for _, hero in ipairs(ownedHeroes) do
        local inLineup = isInLineup(hero.id)
        local stats = getHeroStats(hero.id)
        local qColor = Theme.QualityColor(hero.data.quality + 1)

        -- 三围文字
        local statsText = stats
            and ("统" .. stats.tong .. " 勇" .. stats.yong .. " 智" .. stats.zhi)
            or ""

        -- 角色定位
        local roleText = hero.data.role or ""

        local heroRow = UI.Panel {
            width         = "100%",
            height        = 56,
            flexDirection = "row",
            alignItems    = "center",
            gap           = 8,
            paddingHorizontal = 8,
            paddingVertical = 4,
            backgroundColor = inLineup and { 60, 70, 50, 180 } or C.panel,
            borderRadius  = 6,
            borderColor   = (selectedSlot_ and not inLineup) and C.jade or C.border,
            borderWidth   = 1,
            opacity       = inLineup and 0.6 or 1.0,
            onClick       = function()
                if inLineup then
                    -- 已在阵容: 提示
                    Modal.Alert("提示", hero.data.name .. " 已在阵容中")
                    return
                end
                if not selectedSlot_ then
                    -- 未选择槽位: 自动找空槽
                    local placed = false
                    -- 先尝试前排
                    if #editFront_ < 2 then
                        editFront_[#editFront_ + 1] = hero.id
                        placed = true
                    elseif #editBack_ < 3 then
                        editBack_[#editBack_ + 1] = hero.id
                        placed = true
                    end
                    if placed then
                        selectedSlot_ = nil
                        refreshSlots()
                    else
                        Modal.Alert("提示", "阵容已满(前排2+后排3)")
                    end
                else
                    -- 有选中槽位: 放入
                    local lineupArr = selectedSlot_.row == "front" and editFront_ or editBack_
                    lineupArr[selectedSlot_.idx] = hero.id
                    selectedSlot_ = nil
                    refreshSlots()
                end
            end,
            children = {
                -- 头像
                Comp.HeroAvatar({
                    heroId  = hero.id,
                    size    = 44,
                    quality = hero.data.quality,
                }),

                -- 信息列
                UI.Panel {
                    flexGrow      = 1,
                    flexShrink    = 1,
                    flexDirection = "column",
                    gap           = 2,
                    children = {
                        UI.Panel {
                            flexDirection = "row",
                            alignItems    = "center",
                            gap           = 6,
                            children = {
                                UI.Label {
                                    text      = hero.data.name,
                                    fontSize  = 13,
                                    fontColor = qColor,
                                    fontWeight = "bold",
                                },
                                UI.Label {
                                    text      = "Lv." .. (hero.state.level or 1),
                                    fontSize  = 10,
                                    fontColor = C.textDim,
                                },
                                inLineup and UI.Label {
                                    text      = "[已上阵]",
                                    fontSize  = 9,
                                    fontColor = C.jade,
                                } or nil,
                            },
                        },
                        UI.Label {
                            text      = roleText .. "  " .. statsText,
                            fontSize  = 10,
                            fontColor = C.textDim,
                            maxLines  = 1,
                        },
                    },
                },

                -- 战法
                UI.Panel {
                    width         = 80,
                    alignItems    = "flex-end",
                    children = {
                        UI.Label {
                            text      = hero.data.skill or "",
                            fontSize  = 10,
                            fontColor = C.gold,
                            textAlign = "right",
                            maxLines  = 1,
                        },
                    },
                },
            },
        }

        heroListContainer_:AddChild(heroRow)
    end
end

------------------------------------------------------------
-- 阵法选择器
------------------------------------------------------------

--- 刷新阵法按钮显示
local function refreshFormationDisplay()
    local f = DF.Get(editFormation_)
    if formationBtnLabel_ then
        formationBtnLabel_.text = f and f.name or "锋矢阵"
    end
    if formationDescLabel_ then
        formationDescLabel_.text = f and f.detail or ""
    end
end

--- 构建阵法选择列表内容
local function buildFormationList()
    if not formationListPanel_ then return end
    formationListPanel_:ClearChildren()

    local formations = DF.GetAllWithStatus(gameState_)
    for _, fi in ipairs(formations) do
        local isSelected = fi.id == editFormation_
        local isLocked   = not fi.unlocked

        -- 解锁条件文字
        local unlockText = ""
        if fi.unlock.type == "map" then
            unlockText = "通关" .. fi.unlock.value .. "张地图解锁"
        end

        -- buff 文字列表
        local buffTexts = {}
        if fi.buffs then
            for attr, val in pairs(fi.buffs) do
                buffTexts[#buffTexts + 1] = DF.GetBuffName(attr) .. DF.FormatBuff(attr, val)
            end
        end
        local buffStr = table.concat(buffTexts, "  ")

        local rowBg
        if isSelected then
            rowBg = { 80, 60, 30, 220 }
        elseif isLocked then
            rowBg = { 30, 30, 35, 200 }
        else
            rowBg = { 40, 45, 55, 200 }
        end

        local row = UI.Panel {
            width           = "100%",
            flexDirection   = "column",
            padding         = 6,
            gap             = 2,
            backgroundColor = rowBg,
            borderRadius    = 6,
            borderColor     = isSelected and C.gold or C.border,
            borderWidth     = isSelected and 2 or 1,
            opacity         = isLocked and 0.5 or 1.0,
            onClick         = function()
                if isLocked then
                    Modal.Alert("未解锁", fi.name .. "需要" .. unlockText)
                    return
                end
                editFormation_ = fi.id
                refreshFormationDisplay()
                -- 关闭列表
                formationListPanel_:SetVisible(false)
                YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayNone)
            end,
            children = {
                -- 第一行: 阵名 + 状态
                UI.Panel {
                    width         = "100%",
                    flexDirection = "row",
                    alignItems    = "center",
                    gap           = 6,
                    children = {
                        UI.Label {
                            text       = fi.name,
                            fontSize   = 12,
                            fontColor  = isSelected and C.gold or (isLocked and C.textDim or C.text),
                            fontWeight = "bold",
                        },
                        isSelected and UI.Label {
                            text      = "[当前]",
                            fontSize  = 9,
                            fontColor = C.gold,
                        } or nil,
                        isLocked and UI.Label {
                            text      = "[" .. unlockText .. "]",
                            fontSize  = 9,
                            fontColor = { 180, 80, 80, 255 },
                        } or nil,
                    },
                },
                -- 第二行: 效果描述
                UI.Label {
                    text      = buffStr,
                    fontSize  = 9,
                    fontColor = isLocked and C.textDim or C.jade,
                    maxLines  = 2,
                },
            },
        }
        formationListPanel_:AddChild(row)
    end
end

--- 切换阵法选择列表的显示/隐藏
local function toggleFormationList()
    if not formationListPanel_ then return end
    local isVisible = formationListPanel_:IsVisible()
    if isVisible then
        formationListPanel_:SetVisible(false)
        YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayNone)
    else
        buildFormationList()
        formationListPanel_:SetVisible(true)
        YGNodeStyleSetDisplay(formationListPanel_.node, YGDisplayFlex)
    end
end

------------------------------------------------------------
-- 保存阵容到 gameState
------------------------------------------------------------
local function saveLineup()
    gameState_.lineup.formation = editFormation_
    gameState_.lineup.front = {}
    gameState_.lineup.back  = {}
    for _, h in ipairs(editFront_) do
        gameState_.lineup.front[#gameState_.lineup.front + 1] = h
    end
    for _, h in ipairs(editBack_) do
        gameState_.lineup.back[#gameState_.lineup.back + 1] = h
    end
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建阵容编辑页面
---@param gameState table
---@param callbacks table { onSave?:function }
---@return Panel
function M.Create(gameState, callbacks)
    gameState_ = gameState
    callbacks_ = callbacks or {}
    selectedSlot_ = nil
    slotPanels_ = { front = {}, back = {} }

    -- 初始化编辑副本
    editFront_ = {}
    editBack_  = {}
    editFormation_ = gameState.lineup.formation or DF.GetDefault()
    for _, h in ipairs(gameState.lineup.front or {}) do
        editFront_[#editFront_ + 1] = h
    end
    for _, h in ipairs(gameState.lineup.back or {}) do
        editBack_[#editBack_ + 1] = h
    end

    -- 阵容预估战力
    powerLabel_ = UI.Label {
        text      = "预估战力: " .. Theme.FormatNumber(calcTeamPower()),
        fontSize  = Theme.fontSize.subtitle,
        fontColor = C.gold,
        fontWeight = "bold",
    }

    -- 创建槽位面板
    local frontSlots = {}
    for i = 1, 2 do
        local slot = UI.Panel {
            width         = 72,
            alignItems    = "center",
            gap           = 2,
            paddingVertical = 4,
            onClick       = function() onSlotClick("front", i) end,
        }
        slotPanels_.front[i] = slot
        frontSlots[i] = slot
    end

    local backSlots = {}
    for i = 1, 3 do
        local slot = UI.Panel {
            width         = 72,
            alignItems    = "center",
            gap           = 2,
            paddingVertical = 4,
            onClick       = function() onSlotClick("back", i) end,
        }
        slotPanels_.back[i] = slot
        backSlots[i] = slot
    end

    -- 阵法选择按钮
    local curFormation = DF.Get(editFormation_)
    formationBtnLabel_ = UI.Label {
        text       = curFormation and curFormation.name or "锋矢阵",
        fontSize   = 12,
        fontColor  = C.gold,
        fontWeight = "bold",
    }
    formationDescLabel_ = UI.Label {
        text      = curFormation and curFormation.detail or "",
        fontSize  = 9,
        fontColor = C.jade,
        maxLines  = 1,
    }

    -- 阵法选择列表(默认隐藏)
    formationListPanel_ = UI.ScrollView {
        width           = "100%",
        maxHeight       = 180,
        scrollY         = true,
        gap             = 4,
        padding         = 4,
        backgroundColor = { 25, 30, 40, 240 },
        borderRadius    = 6,
        borderColor     = C.gold,
        borderWidth     = 1,
        display         = "none",
    }
    formationListPanel_:SetVisible(false)

    local formationSelector = UI.Panel {
        width         = "100%",
        gap           = 4,
        children = {
            -- 阵法按钮行
            UI.Panel {
                width           = "100%",
                flexDirection   = "row",
                alignItems      = "center",
                justifyContent  = "space-between",
                paddingHorizontal = 6,
                paddingVertical   = 4,
                backgroundColor = { 50, 45, 30, 200 },
                borderRadius    = 6,
                borderColor     = C.gold,
                borderWidth     = 1,
                onClick         = toggleFormationList,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems    = "center",
                        gap           = 6,
                        children = {
                            UI.Label {
                                text      = "阵法:",
                                fontSize  = 11,
                                fontColor = C.textDim,
                            },
                            formationBtnLabel_,
                        },
                    },
                    UI.Panel {
                        flexDirection = "column",
                        alignItems    = "flex-end",
                        flexShrink    = 1,
                        children = {
                            formationDescLabel_,
                        },
                    },
                },
            },
            -- 展开的阵法列表
            formationListPanel_,
        },
    }

    -- 阵容区域
    local formationPanel = UI.Panel {
        width         = "100%",
        padding       = 8,
        gap           = 4,
        alignItems    = "center",
        backgroundColor = { C.panel[1], C.panel[2], C.panel[3], 200 },
        borderRadius  = 8,
        children = {
            -- 标题行
            UI.Panel {
                width          = "100%",
                flexDirection  = "row",
                justifyContent = "space-between",
                alignItems     = "center",
                marginBottom   = 4,
                children = {
                    UI.Label {
                        text      = "阵容编辑",
                        fontSize  = Theme.fontSize.title,
                        fontColor = C.gold,
                        fontWeight = "bold",
                    },
                    powerLabel_,
                },
            },

            -- 阵法选择器
            formationSelector,

            Comp.SanDivider({ spacing = 4 }),

            -- 前排标签 + 槽位
            UI.Label {
                text      = "前排 (坦克/近战)",
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
                marginBottom = 2,
            },
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "center",
                gap            = 16,
                children       = frontSlots,
            },

            -- 后排标签 + 槽位
            UI.Label {
                text      = "后排 (输出/辅助)",
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
                marginTop  = 6,
                marginBottom = 2,
            },
            UI.Panel {
                flexDirection  = "row",
                justifyContent = "center",
                gap            = 12,
                children       = backSlots,
            },
        },
    }

    -- 保存按钮
    local saveBtn = Comp.SanButton({
        text     = "保存阵容",
        variant  = "primary",
        width    = 140,
        height   = 36,
        fontSize = 14,
        onClick  = function()
            -- 至少需要1个英雄
            local total = #editFront_ + #editBack_
            if total == 0 then
                Modal.Alert("提示", "阵容至少需要1名武将！")
                return
            end
            saveLineup()
            local fName = DF.Get(editFormation_)
            fName = fName and fName.name or editFormation_
            Modal.Alert("保存成功", "阵容已更新！共" .. total .. "名武将\n阵法: " .. fName)
            if callbacks_.onSave then
                callbacks_.onSave()
            end
        end,
    })

    -- 一键清空
    local clearBtn = Comp.SanButton({
        text     = "清空阵容",
        variant  = "secondary",
        width    = 100,
        height   = 36,
        fontSize = 12,
        onClick  = function()
            Modal.Confirm("确认", "确定清空当前阵容？", function()
                editFront_ = {}
                editBack_  = {}
                selectedSlot_ = nil
                refreshSlots()
            end)
        end,
    })

    -- 按钮行
    local buttonRow = UI.Panel {
        width          = "100%",
        flexDirection  = "row",
        justifyContent = "center",
        gap            = 12,
        paddingVertical = 6,
        children = { clearBtn, saveBtn },
    }

    -- 英雄列表区
    heroListContainer_ = UI.Panel {
        width         = "100%",
        flexDirection = "column",
        gap           = 4,
        padding       = 4,
    }

    local heroListScroll = UI.ScrollView {
        flexGrow  = 1,
        flexBasis = 0,
        scrollY   = true,
        padding   = 4,
        children  = { heroListContainer_ },
    }

    -- 英雄列表标题
    local heroListHeader = UI.Panel {
        width         = "100%",
        flexDirection = "row",
        alignItems    = "center",
        justifyContent = "space-between",
        paddingHorizontal = 8,
        paddingVertical   = 4,
        children = {
            UI.Label {
                text      = "可选武将",
                fontSize  = Theme.fontSize.subtitle,
                fontColor = C.text,
                fontWeight = "bold",
            },
            UI.Label {
                text      = "点击武将上阵 / 点击槽位下阵",
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
            },
        },
    }

    -- 主布局(左右分栏: 60% 阵容 | 40% 英雄列表)
    pagePanel_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexBasis     = 0,
        flexDirection = "row",
        backgroundColor = C.bg,
        children = {
            -- 左侧: 阵容 + 按钮
            UI.Panel {
                width         = "45%",
                flexDirection = "column",
                padding       = 8,
                gap           = 6,
                children = {
                    formationPanel,
                    buttonRow,
                },
            },

            -- 分割线
            UI.Panel {
                width           = 1,
                backgroundColor = C.divider,
            },

            -- 右侧: 英雄列表
            UI.Panel {
                flexGrow      = 1,
                flexBasis     = 0,
                flexDirection = "column",
                children = {
                    heroListHeader,
                    Comp.SanDivider({ spacing = 2 }),
                    heroListScroll,
                },
            },
        },
    }

    -- 初始填充
    refreshSlots()

    return pagePanel_
end

--- 刷新页面(状态同步后调用)
---@param gameState table
function M.Refresh(gameState)
    if not pagePanel_ then return end
    gameState_ = gameState

    -- 同步编辑副本
    editFront_ = {}
    editBack_  = {}
    editFormation_ = gameState.lineup.formation or DF.GetDefault()
    for _, h in ipairs(gameState.lineup.front or {}) do
        editFront_[#editFront_ + 1] = h
    end
    for _, h in ipairs(gameState.lineup.back or {}) do
        editBack_[#editBack_ + 1] = h
    end

    selectedSlot_ = nil
    refreshFormationDisplay()
    refreshSlots()
end

return M
