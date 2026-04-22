------------------------------------------------------------
-- ui/page_equip.lua  —— 三国神将录 装备页
-- 左侧：英雄列表选择 | 右侧：装备槽 + 背包 + 操作
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local Modal = require("ui.modal_manager")
local DH    = require("data.data_heroes")
local DE    = require("data.data_equip")
local DS    = require("data.data_state")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

-- 内部状态
local pagePanel_
local heroListContainer_
local detailPanel_
local cachedState_
local sendAction_
local selectedHeroId_
local selectedSlot_           -- 当前选中的槽位
local selectedBagIndex_       -- 当前选中的背包索引

------------------------------------------------------------
-- 品质边框色
------------------------------------------------------------
local function equipQColor(quality)
    return Theme.HeroQualityColor(quality)
end

------------------------------------------------------------
-- 构建英雄选择卡片
------------------------------------------------------------
local function createHeroCard(heroId, heroState)
    local db = DH.Get(heroId)
    if not db then return nil end
    if not heroState or heroState.level <= 0 then return nil end

    local equipCount = 0
    if heroState.equips then
        for _, slot in ipairs(DE.SLOTS) do
            if heroState.equips[slot] then equipCount = equipCount + 1 end
        end
    end

    local isSelected = (heroId == selectedHeroId_)

    return UI.Panel {
        width           = "100%",
        height          = 56,
        flexDirection   = "row",
        alignItems      = "center",
        gap             = 6,
        padding         = 6,
        backgroundColor = isSelected and C.panelLight or C.panel,
        borderRadius    = 6,
        borderColor     = isSelected and C.jade or C.border,
        borderWidth     = isSelected and 2 or 1,
        marginBottom    = 3,
        onClick = function()
            selectedHeroId_ = heroId
            selectedSlot_ = nil
            selectedBagIndex_ = nil
            M.RefreshDetail()
            M.RefreshList()
        end,
        children = {
            Comp.HeroAvatar({
                heroId    = heroId,
                size      = S.heroAvatarSm,
                quality   = db.quality,
                level     = heroState.level,
                showLevel = true,
            }),
            UI.Panel {
                flexGrow      = 1,
                flexShrink    = 1,
                flexDirection = "column",
                gap           = 2,
                children = {
                    UI.Label {
                        text       = db.name,
                        fontSize   = Theme.fontSize.body,
                        fontColor  = Theme.HeroQualityColor(db.quality),
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text      = "装备 " .. equipCount .. "/6",
                        fontSize  = Theme.fontSize.caption,
                        fontColor = equipCount > 0 and C.jade or C.textDim,
                    },
                },
            },
        },
    }
end

------------------------------------------------------------
-- 构建英雄列表
------------------------------------------------------------
local function buildHeroList()
    local heroes = cachedState_ and cachedState_.heroes or {}
    local sorted = DH.GetSortedList()
    local children = {}

    for _, entry in ipairs(sorted) do
        local hid = entry.id
        local hs = heroes[hid]
        if hs and hs.level > 0 then
            local card = createHeroCard(hid, hs)
            if card then children[#children + 1] = card end
        end
    end

    if #children == 0 then
        children[#children + 1] = UI.Label {
            text = "暂无可装备英雄", fontSize = 12, fontColor = C.textDim,
            textAlign = "center", width = "100%", marginTop = 20,
        }
    end

    return UI.Panel {
        width = "100%", flexDirection = "column",
        children = children,
    }
end

------------------------------------------------------------
-- 装备槽位单元格
------------------------------------------------------------
local function createSlotCell(slot, equipInst, heroId)
    local slotName = DE.SLOT_NAMES[slot]
    local isSelected = (selectedSlot_ == slot and selectedBagIndex_ == nil)
    local hasEquip = (equipInst ~= nil and equipInst.templateId ~= nil)

    local children = {}
    local bgColor = C.panel
    local borderCol = C.border

    if hasEquip then
        local tmpl = DE.TEMPLATES[equipInst.templateId]
        local qCol = equipQColor(tmpl.quality)
        borderCol = isSelected and C.gold or qCol

        -- 装备名
        children[#children + 1] = UI.Label {
            text = tmpl.name, fontSize = 10, fontColor = qCol,
            fontWeight = "bold", textAlign = "center",
            width = "100%",
        }
        -- 强化等级
        if (equipInst.level or 0) > 0 then
            children[#children + 1] = UI.Label {
                text = "+" .. equipInst.level, fontSize = 9,
                fontColor = C.jade, textAlign = "center",
            }
        end
        -- 精炼
        if (equipInst.refineLevel or 0) > 0 then
            children[#children + 1] = UI.Label {
                text = "精" .. equipInst.refineLevel, fontSize = 8,
                fontColor = C.gold, textAlign = "center",
            }
        end
    else
        borderCol = isSelected and C.gold or C.border
        children[#children + 1] = UI.Label {
            text = slotName, fontSize = 10, fontColor = C.textDim,
            textAlign = "center",
        }
        children[#children + 1] = UI.Label {
            text = "空", fontSize = 9, fontColor = { 100, 100, 100, 255 },
            textAlign = "center",
        }
    end

    return UI.Panel {
        width           = 72,
        height          = 72,
        justifyContent  = "center",
        alignItems      = "center",
        backgroundColor = bgColor,
        borderRadius    = 6,
        borderColor     = borderCol,
        borderWidth     = isSelected and 2 or 1,
        flexDirection   = "column",
        gap             = 2,
        onClick = function()
            selectedSlot_ = slot
            selectedBagIndex_ = nil
            M.RefreshDetail()
        end,
        children = children,
    }
end

------------------------------------------------------------
-- 装备槽位网格 (2行3列)
------------------------------------------------------------
local function buildEquipSlots(heroId)
    local hero = cachedState_ and cachedState_.heroes[heroId]
    if not hero then return UI.Panel {} end
    local equips = hero.equips or {}

    local rows = {}
    for i = 1, 6, 3 do
        local rowChildren = {}
        for j = 0, 2 do
            local idx = i + j
            if idx <= 6 then
                local slot = DE.SLOTS[idx]
                rowChildren[#rowChildren + 1] = createSlotCell(slot, equips[slot], heroId)
            end
        end
        rows[#rows + 1] = UI.Panel {
            flexDirection  = "row",
            justifyContent = "center",
            gap            = 6,
            children       = rowChildren,
        }
    end

    return UI.Panel {
        width = "100%", flexDirection = "column",
        gap = 6, alignItems = "center",
        children = rows,
    }
end

------------------------------------------------------------
-- 属性总览面板
------------------------------------------------------------
local function buildAttrSummary(heroId)
    local hero = cachedState_ and cachedState_.heroes[heroId]
    if not hero or not hero.equips then return nil end

    local attrs, setCount = DE.CalcAllEquipAttrs(hero.equips)
    local bonuses = DE.GetActiveSetBonuses(setCount)

    -- 属性不为空才显示
    local hasAttrs = false
    for _ in pairs(attrs) do hasAttrs = true; break end
    if not hasAttrs and #bonuses == 0 then return nil end

    local lines = {}
    for attr, val in pairs(attrs) do
        lines[#lines + 1] = UI.Label {
            text = DE.GetAttrName(attr) .. " " .. DE.FormatAttrValue(attr, val),
            fontSize = 10, fontColor = C.text,
        }
    end

    -- 套装效果
    for _, b in ipairs(bonuses) do
        lines[#lines + 1] = UI.Label {
            text = b.setName .. "(" .. b.pieces .. "件): " .. b.desc,
            fontSize = 10, fontColor = C.gold,
        }
    end

    return Comp.SanCard({
        title = "装备属性总览",
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row",
                flexWrap = "wrap", gap = 8,
                children = lines,
            },
        },
    })
end

------------------------------------------------------------
-- 操作按钮区域（选中槽位时）
------------------------------------------------------------
local function buildSlotActions(heroId, slot)
    local hero = cachedState_ and cachedState_.heroes[heroId]
    if not hero then return nil end
    local equips = hero.equips or {}
    local inst = equips[slot]
    if not inst then
        return UI.Label {
            text = "选择背包中的装备进行穿戴",
            fontSize = 11, fontColor = C.textDim,
            textAlign = "center", width = "100%", marginTop = 6,
        }
    end

    local tmpl = DE.TEMPLATES[inst.templateId]
    if not tmpl then return nil end

    local maxLv = DE.GetEnhanceMaxLevel(hero.level)
    local curLv = inst.level or 0
    local cost, rate = DE.GetEnhanceCost(curLv)
    local refLv = inst.refineLevel or 0

    local actionChildren = {
        -- 装备信息
        UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            marginBottom = 6,
            children = {
                UI.Label {
                    text = tmpl.name .. (curLv > 0 and (" +" .. curLv) or ""),
                    fontSize = 13, fontColor = equipQColor(tmpl.quality),
                    fontWeight = "bold",
                },
                UI.Label {
                    text = DE.QUALITY_NAMES[tmpl.quality] .. "品 " .. DE.SLOT_NAMES[tmpl.slot],
                    fontSize = 10, fontColor = C.textDim,
                },
            },
        },
        -- 基础属性
        UI.Panel {
            width = "100%", flexDirection = "row", flexWrap = "wrap", gap = 6,
            marginBottom = 4,
            children = (function()
                local attrLabels = {}
                local finalAttrs = DE.CalcEquipAttrs(inst)
                for attr, val in pairs(finalAttrs) do
                    attrLabels[#attrLabels + 1] = UI.Label {
                        text = DE.GetAttrName(attr) .. DE.FormatAttrValue(attr, val),
                        fontSize = 10, fontColor = C.jade,
                    }
                end
                return attrLabels
            end)(),
        },
    }

    -- 副属性展示
    if inst.subAttrs and #inst.subAttrs > 0 then
        local subLabels = {}
        for i, sub in ipairs(inst.subAttrs) do
            local locked = false
            if inst.locked then
                for _, li in ipairs(inst.locked) do
                    if li == i then locked = true; break end
                end
            end
            subLabels[#subLabels + 1] = UI.Label {
                text = (locked and "[锁]" or "") .. DE.GetAttrName(sub.attr) .. DE.FormatAttrValue(sub.attr, sub.value),
                fontSize = 10,
                fontColor = locked and C.gold or { 180, 200, 220, 255 },
            }
        end
        actionChildren[#actionChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "column", gap = 2,
            marginBottom = 6,
            children = {
                UI.Label { text = "副属性:", fontSize = 10, fontColor = C.textDim },
                table.unpack(subLabels),
            },
        }
    end

    -- 操作按钮
    actionChildren[#actionChildren + 1] = UI.Panel {
        width = "100%", flexDirection = "row", flexWrap = "wrap",
        gap = 6, marginTop = 4,
        children = {
            -- 强化
            Comp.SanButton({
                text = curLv >= maxLv and "强化已满" or ("强化(" .. cost .. "铜)"),
                variant = curLv >= maxLv and "secondary" or "primary",
                height = S.btnSmHeight, fontSize = S.btnSmFontSize,
                flexGrow = 1,
                onClick = function()
                    if curLv >= maxLv then
                        Modal.Alert("提示", "已达强化上限 +" .. maxLv)
                        return
                    end
                    if sendAction_ then
                        sendAction_("equip_enhance", { heroId = heroId, slot = slot })
                    end
                end,
            }),
            -- 卸下
            Comp.SanButton({
                text = "卸下",
                variant = "danger",
                height = S.btnSmHeight, fontSize = S.btnSmFontSize,
                onClick = function()
                    if sendAction_ then
                        sendAction_("equip_remove", { heroId = heroId, slot = slot })
                    end
                end,
            }),
        },
    }

    -- 精炼按钮（橙品+）
    if tmpl.quality >= 5 then
        actionChildren[#actionChildren + 1] = Comp.SanButton({
            text = refLv >= DE.MAX_REFINE and "精炼已满" or ("精炼 Lv." .. refLv .. "->" .. (refLv + 1)),
            variant = refLv >= DE.MAX_REFINE and "secondary" or "gold",
            height = S.btnSmHeight, fontSize = S.btnSmFontSize, marginTop = 4,
            onClick = function()
                if refLv >= DE.MAX_REFINE then
                    Modal.Alert("提示", "已达精炼上限")
                    return
                end
                if sendAction_ then
                    sendAction_("equip_refine", { heroId = heroId, slot = slot })
                end
            end,
        })
    end

    -- 洗练按钮（紫品+）
    if tmpl.quality >= 4 then
        local stoneCount = cachedState_ and cachedState_.inventory
            and cachedState_.inventory.reforge_stone or 0
        actionChildren[#actionChildren + 1] = Comp.SanButton({
            text = "洗练(石:" .. stoneCount .. ")",
            variant = stoneCount > 0 and "primary" or "secondary",
            height = S.btnSmHeight, fontSize = S.btnSmFontSize, marginTop = 4,
            onClick = function()
                if sendAction_ then
                    sendAction_("equip_reforge", {
                        heroId = heroId, slot = slot, lockIndexes = {},
                    })
                end
            end,
        })
    end

    return Comp.SanCard({
        title = "装备操作",
        children = actionChildren,
    })
end

------------------------------------------------------------
-- 背包装备列表
------------------------------------------------------------
local function createBagItem(bagIndex, equipInst)
    local tmpl = DE.TEMPLATES[equipInst.templateId]
    if not tmpl then return nil end

    local qCol = equipQColor(tmpl.quality)
    local isSelected = (selectedBagIndex_ == bagIndex)
    local lvText = (equipInst.level or 0) > 0 and (" +" .. equipInst.level) or ""

    return UI.Panel {
        width           = "100%",
        height          = 48,
        flexDirection   = "row",
        alignItems      = "center",
        gap             = 6,
        padding         = 6,
        backgroundColor = isSelected and C.panelLight or C.panel,
        borderRadius    = 4,
        borderColor     = isSelected and C.gold or C.border,
        borderWidth     = isSelected and 2 or 1,
        marginBottom    = 2,
        onClick = function()
            selectedBagIndex_ = bagIndex
            selectedSlot_ = nil
            M.RefreshDetail()
        end,
        children = {
            -- 品质色块
            UI.Panel {
                width = 4, height = 36,
                backgroundColor = qCol, borderRadius = 2,
            },
            -- 信息
            UI.Panel {
                flexGrow = 1, flexShrink = 1, flexDirection = "column", gap = 1,
                children = {
                    UI.Label {
                        text = tmpl.name .. lvText,
                        fontSize = 11, fontColor = qCol, fontWeight = "bold",
                    },
                    UI.Label {
                        text = DE.QUALITY_NAMES[tmpl.quality] .. " " .. DE.SLOT_NAMES[tmpl.slot],
                        fontSize = 9, fontColor = C.textDim,
                    },
                },
            },
            -- 穿戴按钮
            Comp.SanButton({
                text = "穿戴",
                variant = "primary",
                height = S.btnSmHeight, fontSize = S.btnSmFontSize,
                paddingHorizontal = 12,
                onClick = function()
                    if selectedHeroId_ and sendAction_ then
                        sendAction_("equip_wear", {
                            heroId   = selectedHeroId_,
                            bagIndex = bagIndex,
                        })
                    end
                end,
            }),
        },
    }
end

local function buildBagList()
    local bag = cachedState_ and cachedState_.equipBag or {}
    local children = {}

    -- 按品质降序排列
    local sorted = {}
    for i, inst in ipairs(bag) do
        sorted[#sorted + 1] = { idx = i, inst = inst }
    end
    table.sort(sorted, function(a, b)
        local ta = DE.TEMPLATES[a.inst.templateId]
        local tb = DE.TEMPLATES[b.inst.templateId]
        local qa = ta and ta.quality or 0
        local qb = tb and tb.quality or 0
        if qa ~= qb then return qa > qb end
        return a.idx < b.idx
    end)

    for _, entry in ipairs(sorted) do
        local item = createBagItem(entry.idx, entry.inst)
        if item then children[#children + 1] = item end
    end

    if #children == 0 then
        children[#children + 1] = UI.Label {
            text = "背包为空，通过战斗获取装备",
            fontSize = 11, fontColor = C.textDim,
            textAlign = "center", width = "100%", marginTop = 10,
        }
    end

    return UI.Panel {
        width = "100%", flexDirection = "column",
        children = {
            UI.Label {
                text = "装备背包(" .. #bag .. ")",
                fontSize = Theme.fontSize.subtitle,
                fontColor = C.gold, fontWeight = "bold",
                marginBottom = 6,
            },
            table.unpack(children),
        },
    }
end

------------------------------------------------------------
-- 右侧详情面板
------------------------------------------------------------
local function buildDetailContent()
    if not selectedHeroId_ then
        return UI.Panel {
            flexGrow = 1, justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "选择英雄管理装备",
                    fontSize = Theme.fontSize.body, fontColor = C.textDim,
                },
            },
        }
    end

    local hero = cachedState_ and cachedState_.heroes[selectedHeroId_]
    local db = DH.Get(selectedHeroId_)
    if not hero or not db then
        return UI.Label { text = "英雄数据异常", fontSize = 12, fontColor = C.red }
    end

    local detailChildren = {
        -- 英雄名
        UI.Panel {
            width = "100%", flexDirection = "row", alignItems = "center",
            gap = 8, marginBottom = 6,
            children = {
                Comp.HeroAvatar({
                    heroId = selectedHeroId_, size = S.heroAvatarMd,
                    quality = db.quality, level = hero.level, showLevel = true,
                }),
                UI.Panel {
                    flexDirection = "column", gap = 2,
                    children = {
                        UI.Label {
                            text = db.name .. " Lv." .. hero.level,
                            fontSize = Theme.fontSize.subtitle,
                            fontColor = Theme.HeroQualityColor(db.quality),
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = "战力 " .. DS.CalcHeroPower(selectedHeroId_, hero),
                            fontSize = Theme.fontSize.bodySmall,
                            fontColor = C.gold,
                        },
                    },
                },
            },
        },

        -- 装备槽位
        buildEquipSlots(selectedHeroId_),
    }

    -- 属性总览
    local attrPanel = buildAttrSummary(selectedHeroId_)
    if attrPanel then
        detailChildren[#detailChildren + 1] = attrPanel
    end

    -- 选中槽位的操作面板
    if selectedSlot_ then
        local actions = buildSlotActions(selectedHeroId_, selectedSlot_)
        if actions then
            detailChildren[#detailChildren + 1] = actions
        end
    end

    -- 背包
    detailChildren[#detailChildren + 1] = Comp.SanDivider({ spacing = 8 })
    detailChildren[#detailChildren + 1] = buildBagList()

    return UI.Panel {
        flexGrow = 1, flexDirection = "column",
        padding = 10, gap = 6,
        children = detailChildren,
    }
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建装备页
---@param state table
---@param callbacks table { sendAction }
function M.Create(state, callbacks)
    callbacks     = callbacks or {}
    sendAction_   = callbacks.sendAction
    cachedState_  = state
    selectedHeroId_ = nil
    selectedSlot_   = nil
    selectedBagIndex_ = nil

    -- 英雄列表
    heroListContainer_ = UI.Panel {
        width = "100%", flexDirection = "column",
        children = { buildHeroList() },
    }

    -- 右侧详情
    detailPanel_ = UI.Panel {
        flexGrow = 1, flexBasis = 0,
        children = { buildDetailContent() },
    }

    -- 主布局
    pagePanel_ = UI.Panel {
        width = "100%", flexGrow = 1, flexBasis = 0,
        flexDirection = "row",
        children = {
            -- 左侧英雄列表
            UI.Panel {
                width = 200, flexDirection = "column",
                children = {
                    UI.Label {
                        text = "选择英雄",
                        fontSize = Theme.fontSize.subtitle,
                        fontColor = C.gold, fontWeight = "bold",
                        paddingHorizontal = 8, paddingVertical = 6,
                    },
                    UI.ScrollView {
                        flexGrow = 1, flexBasis = 0,
                        scrollY = true, padding = 6,
                        children = { heroListContainer_ },
                    },
                },
            },
            -- 分割线
            UI.Panel {
                width = 1, height = "100%",
                backgroundColor = C.border,
            },
            -- 右侧详情
            UI.ScrollView {
                flexGrow = 1, flexBasis = 0,
                scrollY = true,
                children = { detailPanel_ },
            },
        },
    }

    return pagePanel_
end

--- 刷新英雄列表
function M.RefreshList()
    if not heroListContainer_ then return end
    heroListContainer_:ClearChildren()
    heroListContainer_:AddChild(buildHeroList())
end

--- 刷新详情面板
function M.RefreshDetail()
    if not detailPanel_ then return end
    detailPanel_:ClearChildren()
    detailPanel_:AddChild(buildDetailContent())
end

--- 外部状态刷新
function M.Refresh(state)
    cachedState_ = state
    M.RefreshList()
    M.RefreshDetail()
end

return M
