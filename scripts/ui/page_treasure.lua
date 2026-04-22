------------------------------------------------------------
-- ui/page_treasure.lua  —— 宝物页面
-- 左栏: 英雄列表 | 右栏: 宝物槽位 + 背包
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local DT    = require("data.data_treasure")
local DH    = require("data.data_heroes")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 模块状态
------------------------------------------------------------
local pagePanel_       = nil
local cachedState_     = nil
local sendAction_      = nil

local selectedHeroId_  = nil
local detailPanel_     = nil
local heroListContainer_ = nil

------------------------------------------------------------
-- 宝物实例格式化
------------------------------------------------------------
local function treasureName(inst)
    if not inst then return "空" end
    local tmpl = DT.Get(inst.templateId)
    return tmpl and tmpl.name or "???"
end

local function treasureQuality(inst)
    if not inst then return 1 end
    local tmpl = DT.Get(inst.templateId)
    -- quality 5=橙(+1=6红色), 6=红(+1=7金色)
    return tmpl and (tmpl.quality + 1) or 1
end

------------------------------------------------------------
-- 右栏: 宝物详情
------------------------------------------------------------
local function buildSlotCard(title, inst, slotInfo)
    local tmpl = inst and DT.Get(inst.templateId)
    local level = inst and (inst.level or 1) or 0
    local qColor = inst and Theme.QualityColor(treasureQuality(inst)) or C.border

    -- 属性行
    local attrChildren = {}
    if inst then
        local attrs = DT.CalcAttrs(inst)
        for attr, val in pairs(attrs) do
            attrChildren[#attrChildren + 1] = UI.Label {
                text = DT.FormatAttr(attr, val),
                fontSize = Theme.fontSize.bodySmall,
                fontColor = C.hp,
            }
        end
    end

    -- 被动
    local passiveLabel = nil
    if tmpl and tmpl.passiveDesc then
        passiveLabel = UI.Label {
            text = "被动: " .. tmpl.passiveDesc,
            fontSize = Theme.fontSize.caption,
            fontColor = C.gold,
            marginTop = 4,
        }
    end

    -- 按钮
    local buttons = {}
    if inst and level < DT.MAX_LEVEL then
        local cost = DT.GetUpgradeCost(level)
        local costText = cost
            and ("升级(精华" .. cost.essence .. " 铜钱" .. cost.copper .. ")")
            or "升级"
        buttons[#buttons + 1] = Comp.SanButton {
            text = costText,
            variant = "primary",
            fontSize = 11,
            height = 32,
            onClick = function()
                if slotInfo.type == "exclusive" then
                    sendAction_("treasure_upgrade", {
                        heroId = selectedHeroId_,
                        isExclusive = true,
                    })
                else
                    sendAction_("treasure_upgrade", {
                        heroId = selectedHeroId_,
                        slot = slotInfo.slot,
                    })
                end
            end,
        }
    end
    if inst and slotInfo.type == "public" then
        buttons[#buttons + 1] = Comp.SanButton {
            text = "卸下",
            variant = "secondary",
            fontSize = 11,
            height = 32,
            onClick = function()
                sendAction_("treasure_remove", {
                    heroId = selectedHeroId_,
                    slot = slotInfo.slot,
                })
            end,
        }
    end

    return Comp.SanCard {
        marginBottom = 8,
        children = {
            -- 标题行
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                marginBottom = 4,
                children = {
                    UI.Label {
                        text = title,
                        fontSize = Theme.fontSize.subtitle,
                        fontColor = C.gold,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text = inst
                            and (tmpl.name .. "  Lv." .. level)
                            or "(空)",
                        fontSize = Theme.fontSize.body,
                        fontColor = inst and qColor or C.textDim,
                    },
                },
            },
            -- 属性
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                flexWrap = "wrap",
                children = attrChildren,
            },
            passiveLabel,
            -- 按钮行
            #buttons > 0 and UI.Panel {
                flexDirection = "row",
                gap = 8,
                marginTop = 6,
                children = buttons,
            } or nil,
        },
    }
end

local function buildBagSection(state)
    local bag = state.treasureBag or {}
    if #bag == 0 then
        return UI.Label {
            text = "背包空空如也",
            fontSize = Theme.fontSize.body,
            fontColor = C.textDim,
            marginTop = 8,
        }
    end

    local items = {}
    for i, inst in ipairs(bag) do
        local tmpl = DT.Get(inst.templateId)
        local qColor = Theme.QualityColor(treasureQuality(inst))
        items[#items + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            padding = 6,
            backgroundColor = C.panelLight,
            borderRadius = 6,
            marginBottom = 4,
            children = {
                -- 名称+等级
                UI.Label {
                    text = (tmpl and tmpl.name or "???") .. " Lv." .. (inst.level or 1),
                    fontSize = Theme.fontSize.body,
                    fontColor = qColor,
                    flexGrow = 1,
                },
                -- 属性摘要
                UI.Label {
                    text = (function()
                        local attrs = DT.CalcAttrs(inst)
                        local parts = {}
                        for attr, val in pairs(attrs) do
                            parts[#parts + 1] = DT.FormatAttr(attr, val)
                        end
                        return table.concat(parts, " ")
                    end)(),
                    fontSize = Theme.fontSize.caption,
                    fontColor = C.hp,
                },
                -- 装备按钮(槽1)
                Comp.SanButton {
                    text = "槽1",
                    variant = "primary",
                    fontSize = 10,
                    height = 26,
                    paddingHorizontal = 8,
                    onClick = function()
                        sendAction_("treasure_equip", {
                            heroId = selectedHeroId_,
                            bagIndex = i,
                            slot = 1,
                        })
                    end,
                },
                -- 装备按钮(槽2)
                Comp.SanButton {
                    text = "槽2",
                    variant = "primary",
                    fontSize = 10,
                    height = 26,
                    paddingHorizontal = 8,
                    onClick = function()
                        sendAction_("treasure_equip", {
                            heroId = selectedHeroId_,
                            bagIndex = i,
                            slot = 2,
                        })
                    end,
                },
            },
        }
    end

    return UI.Panel {
        flexDirection = "column",
        width = "100%",
        marginTop = 8,
        children = items,
    }
end

local function buildComposeSection(state)
    local children = {}

    -- 材料显示
    children[#children + 1] = UI.Panel {
        flexDirection = "row",
        gap = 16,
        marginBottom = 8,
        children = {
            UI.Label {
                text = "宝物碎片: " .. (state.inventory.treasure_shards or 0),
                fontSize = Theme.fontSize.body,
                fontColor = C.text,
            },
            UI.Label {
                text = "专属碎片: " .. (state.inventory.exclusive_shards or 0),
                fontSize = Theme.fontSize.body,
                fontColor = C.text,
            },
            UI.Label {
                text = "宝物精华: " .. (state.inventory.treasure_essence or 0),
                fontSize = Theme.fontSize.body,
                fontColor = C.gold,
            },
        },
    }

    -- 公共宝物合成列表
    local publicIds = DT.GetAllPublicIds()
    for _, tid in ipairs(publicIds) do
        local tmpl = DT.Get(tid)
        local qColor = Theme.QualityColor((tmpl.quality or 5) + 1)
        children[#children + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            padding = 4,
            marginBottom = 2,
            children = {
                UI.Label {
                    text = tmpl.name,
                    fontSize = Theme.fontSize.bodySmall,
                    fontColor = qColor,
                    width = 90,
                },
                UI.Label {
                    text = "需" .. (tmpl.composeCost or 50) .. "碎片",
                    fontSize = Theme.fontSize.caption,
                    fontColor = C.textDim,
                    width = 70,
                },
                Comp.SanButton {
                    text = "合成",
                    variant = "gold",
                    fontSize = 10,
                    height = 24,
                    paddingHorizontal = 8,
                    disabled = (state.inventory.treasure_shards or 0) < (tmpl.composeCost or 50),
                    onClick = function()
                        sendAction_("treasure_compose", { templateId = tid })
                    end,
                },
            },
        }
    end

    -- 专属宝物合成
    if selectedHeroId_ then
        local exTid = DT.GetExclusiveFor(selectedHeroId_)
        if exTid then
            local exTmpl = DT.Get(exTid)
            local hero = state.heroes[selectedHeroId_]
            local hasEx = hero and hero.exclusive
            if not hasEx then
                children[#children + 1] = Comp.SanDivider { label = "专属宝物" }
                children[#children + 1] = UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 8,
                    padding = 4,
                    children = {
                        UI.Label {
                            text = exTmpl.name,
                            fontSize = Theme.fontSize.bodySmall,
                            fontColor = Theme.QualityColor(7),
                            width = 90,
                        },
                        UI.Label {
                            text = "需" .. (exTmpl.composeCost or 30) .. "专属碎片",
                            fontSize = Theme.fontSize.caption,
                            fontColor = C.textDim,
                        },
                        Comp.SanButton {
                            text = "合成",
                            variant = "gold",
                            fontSize = 10,
                            height = 24,
                            paddingHorizontal = 8,
                            disabled = (state.inventory.exclusive_shards or 0) < (exTmpl.composeCost or 30),
                            onClick = function()
                                sendAction_("treasure_compose_exclusive", {
                                    heroId = selectedHeroId_,
                                })
                            end,
                        },
                    },
                }
            end
        end
    end

    return Comp.SanCard {
        title = "合成",
        marginBottom = 8,
        children = children,
    }
end

local function refreshDetail(state)
    if not detailPanel_ then return end
    detailPanel_:RemoveAllChildren()

    if not selectedHeroId_ then
        detailPanel_:AddChild(UI.Label {
            text = "请选择英雄",
            fontSize = Theme.fontSize.headline,
            fontColor = C.textDim,
            marginTop = 40,
            textAlign = "center",
            width = "100%",
        })
        return
    end

    local hero = state.heroes[selectedHeroId_]
    if not hero then return end

    -- 英雄名
    local hd = DH.Get(selectedHeroId_)
    detailPanel_:AddChild(UI.Label {
        text = (hd and hd.name or selectedHeroId_) .. " 的宝物",
        fontSize = Theme.fontSize.headline,
        fontColor = C.gold,
        fontWeight = "bold",
        marginBottom = 8,
    })

    -- 公共宝物槽1
    local t1 = hero.treasures and hero.treasures[1]
    detailPanel_:AddChild(buildSlotCard("公共槽1", t1, { type = "public", slot = 1 }))

    -- 公共宝物槽2
    local t2 = hero.treasures and hero.treasures[2]
    detailPanel_:AddChild(buildSlotCard("公共槽2", t2, { type = "public", slot = 2 }))

    -- 专属宝物
    local exTid = DT.GetExclusiveFor(selectedHeroId_)
    if exTid then
        detailPanel_:AddChild(buildSlotCard(
            "专属宝物",
            hero.exclusive,
            { type = "exclusive" }
        ))
    end

    -- 分割线
    detailPanel_:AddChild(Comp.SanDivider { label = "背包" })

    -- 背包
    detailPanel_:AddChild(buildBagSection(state))

    -- 合成区
    detailPanel_:AddChild(Comp.SanDivider { label = "合成" })
    detailPanel_:AddChild(buildComposeSection(state))
end

------------------------------------------------------------
-- 左栏: 英雄列表
------------------------------------------------------------
local function refreshHeroList(state)
    if not heroListContainer_ then return end
    heroListContainer_:RemoveAllChildren()

    -- 收集已拥有英雄，按战力排序
    local list = {}
    for heroId, hs in pairs(state.heroes or {}) do
        if hs.level and hs.level > 0 then
            list[#list + 1] = { id = heroId, state = hs }
        end
    end
    table.sort(list, function(a, b)
        return (a.state.level or 0) > (b.state.level or 0)
    end)

    for _, entry in ipairs(list) do
        local heroId = entry.id
        local hs = entry.state
        local hd = DH.Get(heroId)
        local isSelected = (heroId == selectedHeroId_)

        -- 宝物数量
        local tCount = 0
        if hs.treasures then
            if hs.treasures[1] then tCount = tCount + 1 end
            if hs.treasures[2] then tCount = tCount + 1 end
        end
        if hs.exclusive then tCount = tCount + 1 end

        heroListContainer_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 8,
            padding = 6,
            marginBottom = 2,
            backgroundColor = isSelected and C.panelLight or C.panel,
            borderColor = isSelected and C.jade or C.border,
            borderWidth = isSelected and 2 or 1,
            borderRadius = 6,
            onClick = function()
                selectedHeroId_ = heroId
                refreshHeroList(state)
                refreshDetail(state)
            end,
            children = {
                Comp.HeroAvatar {
                    heroId = heroId,
                    size = S.heroAvatarSm,
                    quality = hd and (hd.quality + 1) or 1,
                },
                UI.Panel {
                    flexDirection = "column",
                    flexGrow = 1,
                    children = {
                        UI.Label {
                            text = hd and hd.name or heroId,
                            fontSize = Theme.fontSize.body,
                            fontColor = C.text,
                        },
                        UI.Label {
                            text = "Lv." .. hs.level .. "  宝物:" .. tCount,
                            fontSize = Theme.fontSize.caption,
                            fontColor = C.textDim,
                        },
                    },
                },
            },
        })
    end
end

------------------------------------------------------------
-- 公共接口
------------------------------------------------------------

--- 创建页面
---@param state table
---@param callbacks table  { sendAction: fun(action, params) }
---@return userdata panel
function M.Create(state, callbacks)
    cachedState_   = state
    sendAction_    = callbacks.sendAction
    selectedHeroId_ = nil

    -- 左栏
    heroListContainer_ = UI.Panel {
        flexDirection = "column",
        width = "100%",
    }

    local leftPanel = UI.Panel {
        width = 220,
        flexDirection = "column",
        children = {
            UI.Label {
                text = "选择英雄",
                fontSize = Theme.fontSize.subtitle,
                fontColor = C.gold,
                fontWeight = "bold",
                marginBottom = 6,
            },
            UI.ScrollView {
                flexGrow = 1,
                children = { heroListContainer_ },
            },
        },
    }

    -- 右栏
    detailPanel_ = UI.Panel {
        flexDirection = "column",
        width = "100%",
    }

    local rightPanel = UI.Panel {
        flexGrow = 1,
        flexDirection = "column",
        paddingLeft = 12,
        children = {
            UI.ScrollView {
                flexGrow = 1,
                children = { detailPanel_ },
            },
        },
    }

    -- 总面板
    pagePanel_ = UI.Panel {
        width = "100%",
        height = "100%",
        flexDirection = "row",
        padding = 10,
        backgroundColor = C.bg,
        children = {
            leftPanel,
            UI.Panel { width = 1, backgroundColor = C.border },
            rightPanel,
        },
    }

    refreshHeroList(state)
    return pagePanel_
end

--- 刷新页面
---@param state table
function M.Refresh(state)
    cachedState_ = state
    refreshHeroList(state)
    refreshDetail(state)
end

return M
