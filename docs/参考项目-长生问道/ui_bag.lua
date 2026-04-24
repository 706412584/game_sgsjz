-- ============================================================================
-- 《问道长生》储物页（重构版）
-- 功能：分类标签 + 子标签 + 容量显示 + 物品锁定 + 回收面板
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local RT = require("rich_text")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameItems = require("game_items")
local DataItems = require("data_items")
local GameServer = require("game_server")
local GameOps = require("network.game_ops")
local Toast = require("ui_toast")

local M = {}

-- ============================================================================
-- 页面状态
-- ============================================================================
local activeCategory_ = "fabao"    -- 当前主分类
local activeSubTab_   = nil        -- 当前子分类（nil=全部）
local selectedItem_   = 1          -- 当前选中物品索引（分类列表内）
local showRecycle_    = false       -- 回收面板
local showExpand_     = false       -- 扩容确认
local showBatchSell_  = false       -- 批量出售确认
local batchSellCount_ = 0
local batchSellPrice_ = 0

-- 回收品质勾选状态（新9品阶key）
local recycleQualities_ = {
    fanqi     = true,
    lingbao   = true,
    xtlingbao = false,
    huangqi   = false,
    diqi      = false,
    xianqi    = false,
    xtxianqi  = false,
    shenqi    = false,
    xtshenqi  = false,
}

-- ============================================================================
-- 构建分类主标签栏
-- ============================================================================
local function BuildCategoryTabs()
    local cats = DataItems.ITEM_CATEGORIES
    local counts = GameItems.GetCategoryCounts()
    local children = {}
    for _, cat in ipairs(cats) do
        local isActive = (cat.key == activeCategory_)
        local cnt = counts[cat.key] or 0
        local label = cat.label
        if cnt > 0 then label = label .. "(" .. cnt .. ")" end

        children[#children + 1] = UI.Panel {
            flexGrow = 1,
            height = 36,
            justifyContent = "center",
            alignItems = "center",
            backgroundColor = isActive and { 60, 50, 35, 255 } or { 0, 0, 0, 0 },
            borderColor = isActive and Theme.colors.gold or { 0, 0, 0, 0 },
            borderWidth = { bottom = isActive and 2 or 0 },
            cursor = "pointer",
            onClick = function(self)
                activeCategory_ = cat.key
                activeSubTab_ = nil
                selectedItem_ = 1
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = label,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.textGold or Theme.colors.textSecondary,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = { 30, 25, 20, 200 },
        borderColor = Theme.colors.border,
        borderWidth = { bottom = 1 },
        children = children,
    }
end

-- ============================================================================
-- 构建子标签栏（仅法宝/物品有子分类）
-- ============================================================================
local function BuildSubTabs()
    local catDef = DataItems.GetCategory(activeCategory_)
    if not catDef or not catDef.subTabs then return nil end

    local children = {}
    -- "全部"按钮
    local allActive = (activeSubTab_ == nil)
    children[#children + 1] = UI.Panel {
        paddingHorizontal = 10,
        paddingVertical = 4,
        borderRadius = Theme.radius.sm,
        backgroundColor = allActive and Theme.colors.gold or { 45, 38, 30, 200 },
        cursor = "pointer",
        onClick = function(self)
            activeSubTab_ = nil
            selectedItem_ = 1
            Router.RebuildUI()
        end,
        children = {
            UI.Label {
                text = "全部",
                fontSize = Theme.fontSize.small,
                fontWeight = allActive and "bold" or "normal",
                fontColor = allActive and Theme.colors.btnPrimaryText or Theme.colors.textLight,
            },
        },
    }
    for _, sub in ipairs(catDef.subTabs) do
        local isActive = (activeSubTab_ == sub)
        children[#children + 1] = UI.Panel {
            paddingHorizontal = 10,
            paddingVertical = 4,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or { 45, 38, 30, 200 },
            cursor = "pointer",
            onClick = function(self)
                activeSubTab_ = sub
                selectedItem_ = 1
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = sub,
                    fontSize = Theme.fontSize.small,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.tabActiveText or Theme.colors.textLight,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        paddingVertical = 6,
        paddingHorizontal = 4,
        children = children,
    }
end

-- ============================================================================
-- 构建容量栏
-- ============================================================================
local function BuildCapacityBar()
    local used = GameItems.GetBagUsed()
    local cap = GameItems.GetBagCapacity()
    local pct = used / math.max(cap, 1)
    local barColor = pct > 0.9 and Theme.colors.danger
        or pct > 0.7 and { 220, 180, 60, 255 }
        or Theme.colors.gold

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingHorizontal = 4,
        children = {
            UI.Label {
                text = "储物戒",
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
            -- 进度条
            UI.Panel {
                flexGrow = 1,
                height = 8,
                borderRadius = 4,
                backgroundColor = { 50, 45, 35, 255 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 4,
                        backgroundColor = barColor,
                    },
                },
            },
            UI.Label {
                text = used .. "/" .. cap,
                fontSize = Theme.fontSize.small,
                fontColor = pct > 0.9 and Theme.colors.danger or Theme.colors.textLight,
            },
        },
    }
end

-- ============================================================================
-- 构建物品格子
-- ============================================================================
local function BuildItemCell(item, idx, isSelected)
    local rarityColor = Comp.GetRarityColor(item.rarity)
    local bg = isSelected and { 60, 55, 40, 255 } or Theme.colors.bgDark
    local borderC = isSelected and Theme.colors.gold or rarityColor
    local locked = item.locked or false

    return UI.Panel {
        width = "22%",
        aspectRatio = 1,
        borderRadius = Theme.radius.sm,
        backgroundColor = bg,
        borderColor = borderC,
        borderWidth = isSelected and 3 or 2,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        cursor = "pointer",
        onClick = function(self)
            selectedItem_ = idx
            Router.RebuildUI()
        end,
        children = (function()
            local c = {}
            if locked then
                c[#c + 1] = UI.Panel {
                    position = "absolute",
                    top = 2, right = 2,
                    children = {
                        UI.Label {
                            text = "[锁]",
                            fontSize = 9,
                            fontWeight = "bold",
                            fontColor = Theme.colors.gold,
                        },
                    },
                }
            end
            c[#c + 1] = UI.Label {
                text = item.name,
                fontSize = 12,
                fontWeight = "bold",
                fontColor = Theme.colors.textLight,
                textAlign = "center",
            }
            c[#c + 1] = UI.Label {
                text = "x" .. (item.count or 1),
                fontSize = 10,
                fontWeight = "bold",
                fontColor = Theme.colors.textSecondary,
            }
            return c
        end)(),
    }
end

-- ============================================================================
-- 构建装备属性行
-- ============================================================================
local function BuildEquipStatLine(label, value, compareValue)
    local valStr = tostring(value)
    local valColor = Theme.colors.gold
    local diffWidget = nil
    if compareValue and compareValue ~= 0 then
        local diff = value - compareValue
        if diff > 0 then
            diffWidget = UI.Label {
                text = "(+" .. diff .. ")",
                fontSize = Theme.fontSize.small,
                fontColor = { 100, 220, 100, 255 },
            }
        elseif diff < 0 then
            diffWidget = UI.Label {
                text = "(" .. diff .. ")",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.danger,
            }
        end
    end
    local rowChildren = {
        UI.Label {
            text = label .. ": ",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
        },
        UI.Label {
            text = valStr,
            fontSize = Theme.fontSize.small,
            fontColor = valColor,
        },
    }
    if diffWidget then
        rowChildren[#rowChildren + 1] = diffWidget
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 4,
        alignItems = "center",
        children = rowChildren,
    }
end

--- 计算装备总属性值（基础+附加中同类）
---@param equip table
---@param statKey string "attack"|"defense"|"crit"|"speed" 等
---@return number
local function CalcEquipStat(equip, statKey)
    local val = 0
    -- 基础属性映射
    local baseMap = { attack = "baseAtk", defense = "baseDef", crit = "baseCrit", speed = "baseSpd" }
    if baseMap[statKey] then
        val = val + (equip[baseMap[statKey]] or 0)
    end
    -- 附加属性
    for _, es in ipairs(equip.extraStats or {}) do
        if es.stat == statKey then
            val = val + (es.value or 0)
        end
    end
    return val
end

-- ============================================================================
-- 构建装备详情面板（isEquip=true 的物品专用）
-- ============================================================================
local function BuildEquipDetail(item, globalIndex)
    if not item then return nil end
    local p = GamePlayer.Get()
    if not p then return nil end

    local qColor = DataItems.GetQualityColor(item.quality or "common")
    local qLabel = DataItems.GetQualityLabel(item.quality or "common")
    local slotDef = DataItems.GetSlotByKey(item.slot or "weapon")
    local slotLabel = slotDef and slotDef.label or "装备"
    local equipped = p.equippedItems or {}
    local curEquip = equipped[item.slot]  -- 当前同槽位已穿戴的装备

    local detailChildren = {}

    -- 品质 + 槽位行
    detailChildren[#detailChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Label {
                text = "[" .. slotLabel .. "]",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
            UI.Label {
                text = qLabel,
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                fontColor = qColor,
            },
        },
    }

    -- 属性列表（与当前装备对比）
    local statKeys = { "attack", "defense", "crit", "speed", "hp", "dodge", "hit" }
    for _, sk in ipairs(statKeys) do
        local val = CalcEquipStat(item, sk)
        if val > 0 then
            local cmpVal = curEquip and CalcEquipStat(curEquip, sk) or nil
            detailChildren[#detailChildren + 1] = BuildEquipStatLine(
                DataItems.STAT_LABEL[sk] or sk, val, cmpVal
            )
        end
    end

    -- 当前装备对比标题（如有）
    if curEquip then
        detailChildren[#detailChildren + 1] = UI.Divider {
            orientation = "horizontal",
            thickness = 1,
            fontColor = Theme.colors.divider,
            spacing = 4,
        }
        detailChildren[#detailChildren + 1] = UI.Label {
            text = "当前: " .. curEquip.name,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
        }
    end

    -- 按钮行
    detailChildren[#detailChildren + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        marginTop = 4,
        children = {
            -- 穿戴按钮
            UI.Panel {
                flexGrow = 1,
                children = {
                    Comp.BuildInkButton("穿戴", function()
                        GameOps.Request("equip_wear", {
                            playerKey = GameServer.GetServerKey("player"),
                            bagIndex  = globalIndex,
                        }, function(ok, data)
                            Toast.Show(data and data.msg or (ok and "穿戴成功" or "穿戴失败"),
                                { variant = ok and "success" or "error" })
                            if ok then
                                selectedItem_ = math.max(1, selectedItem_ - 1)
                                Router.RebuildUI()
                            end
                        end)
                    end, { width = "100%", fontSize = Theme.fontSize.body }),
                },
            },
            -- 锁定
            UI.Panel {
                flexGrow = 1,
                children = {
                    Comp.BuildSecondaryButton(item.locked and "解锁" or "锁定", function()
                        local ok, msg = GameItems.ToggleLock(globalIndex)
                        Toast.Show(msg, { variant = ok and "success" or "info" })
                        if ok then Router.RebuildUI() end
                    end, { width = "100%" }),
                },
            },
            -- 出售
            UI.Panel {
                flexGrow = 1,
                children = {
                    Comp.BuildSecondaryButton("出售", function()
                        if item.locked then
                            Toast.Show("已锁定的物品无法出售", { variant = "error" })
                            return
                        end
                        local ok, msg = GameItems.DoSellItem(globalIndex)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        if ok then
                            selectedItem_ = math.max(1, selectedItem_)
                            Router.RebuildUI()
                        end
                    end, { width = "100%" }),
                },
            },
        },
    }

    return Comp.BuildCardPanel(item.name, detailChildren, { borderColor = qColor })
end

-- ============================================================================
-- 构建已装备栏面板（展示当前穿戴的装备 + 脱下按钮）
-- ============================================================================
local function BuildEquippedBar()
    local p = GamePlayer.Get()
    if not p then return nil end
    local equipped = p.equippedItems or {}
    local hasAny = false
    for _, _ in pairs(equipped) do hasAny = true; break end
    if not hasAny then return nil end

    local slotChildren = {}
    for _, slotDef in ipairs(DataItems.EQUIP_SLOTS) do
        local eq = equipped[slotDef.slot]
        local qColor = eq and DataItems.GetQualityColor(eq.quality or "common") or { 60, 55, 45, 200 }
        slotChildren[#slotChildren + 1] = UI.Panel {
            width = "18%",
            aspectRatio = 1,
            borderRadius = Theme.radius.sm,
            backgroundColor = eq and { 50, 45, 35, 255 } or { 35, 30, 25, 200 },
            borderColor = qColor,
            borderWidth = 1,
            justifyContent = "center",
            alignItems = "center",
            gap = 1,
            cursor = eq and "pointer" or "default",
            onClick = eq and function(self)
                GameOps.Request("equip_remove", {
                    playerKey = GameServer.GetServerKey("player"),
                    slot      = slotDef.slot,
                }, function(ok, data)
                    Toast.Show(data and data.msg or (ok and "卸下成功" or "卸下失败"),
                        { variant = ok and "success" or "error" })
                    if ok then Router.RebuildUI() end
                end)
            end or nil,
            children = {
                UI.Label {
                    text = eq and eq.name or slotDef.label,
                    fontSize = 8,
                    fontColor = eq and Theme.colors.textLight or { 80, 75, 65, 200 },
                    textAlign = "center",
                },
                eq and UI.Label {
                    text = "[卸]",
                    fontSize = 7,
                    fontColor = Theme.colors.textSecondary,
                } or nil,
            },
        }
    end

    return Comp.BuildCardPanel("已装备(点击卸下)", {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 4,
            justifyContent = "center",
            children = slotChildren,
        },
    })
end

-- ============================================================================
-- 构建选中物品详情面板
-- ============================================================================
local function BuildItemDetail(item, globalIndex)
    if not item then return nil end
    -- 材料不走法宝品阶体系，直接标注"材料"；其他 bagItems 用 rarity 映射
    local rarityLabel, rarityColor
    if item.category == "material" then
        rarityLabel = "材料"
        rarityColor = Theme.colors.textSecondary
    else
        rarityLabel = DataItems.GetQualityLabel(item.rarity or "common") or "普通"
        rarityColor = Comp.GetRarityColor(item.rarity)
    end
    local locked = item.locked or false

    local detailChildren = {
        UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            children = (function()
                local c = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        alignItems = "center",
                        children = (function()
                            local cc = {
                                UI.Label {
                                    text = "数量: " .. (item.count or 1),
                                    fontSize = Theme.fontSize.body,
                                    fontColor = Theme.colors.textLight,
                                },
                            }
                            if locked then
                                cc[#cc + 1] = UI.Label {
                                    text = "[已锁定]",
                                    fontSize = Theme.fontSize.small,
                                    fontColor = Theme.colors.gold,
                                }
                            end
                            return cc
                        end)(),
                    },
                    UI.Label {
                        text = rarityLabel,
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = rarityColor,
                    },
                }
                return c
            end)(),
        },
    }
    -- 描述（有内容才添加；RT.Build 支持带 <c=...> 标签的高亮描述）
    if item.desc and item.desc ~= "" then
        detailChildren[#detailChildren + 1] = RT.Build(
            item.desc, Theme.fontSize.small, Theme.colors.textSecondary
        )
    end
    -- 操作按钮行
    detailChildren[#detailChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            marginTop = 4,
            children = {
                -- 使用按钮
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildInkButton("使用", function()
                            local ok, msg = GameItems.DoUseItem(globalIndex)
                            Toast.Show(msg, { variant = ok and "success" or "error" })
                            if ok then
                                selectedItem_ = math.max(1, selectedItem_)
                                Router.RebuildUI()
                            end
                        end, { width = "100%", fontSize = Theme.fontSize.body }),
                    },
                },
                -- 锁定/解锁按钮
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton(locked and "解锁" or "锁定", function()
                            local ok, msg = GameItems.ToggleLock(globalIndex)
                            Toast.Show(msg, { variant = ok and "success" or "info" })
                            if ok then Router.RebuildUI() end
                        end, { width = "100%" }),
                    },
                },
                -- 出售按钮
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("出售", function()
                            if locked then
                                Toast.Show("已锁定的物品无法出售", { variant = "error" })
                                return
                            end
                            local ok, msg = GameItems.DoSellItem(globalIndex)
                            Toast.Show(msg, { variant = ok and "success" or "error" })
                            if ok then
                                selectedItem_ = math.max(1, selectedItem_)
                                Router.RebuildUI()
                            end
                        end, { width = "100%" }),
                    },
                },
            },
        }

    return Comp.BuildCardPanel(item.name, detailChildren, { borderColor = rarityColor })
end

-- ============================================================================
-- 构建回收面板弹窗
-- ============================================================================
local function BuildRecyclePanel()
    local qualityOrder = DataItems.QUALITY_ORDER
    -- 品质勾选列表
    local checkChildren = {}
    for _, qKey in ipairs(qualityOrder) do
        local qDef = DataItems.QUALITY[qKey]
        if not qDef then goto cont end
        local checked = recycleQualities_[qKey] or false
        checkChildren[#checkChildren + 1] = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            cursor = "pointer",
            onClick = function(self)
                recycleQualities_[qKey] = not recycleQualities_[qKey]
                Router.RebuildUI()
            end,
            children = {
                UI.Panel {
                    width = 18, height = 18,
                    borderRadius = 3,
                    borderColor = qDef.color,
                    borderWidth = 1,
                    backgroundColor = checked and qDef.color or { 40, 35, 30, 200 },
                    justifyContent = "center",
                    alignItems = "center",
                    children = checked and {
                        UI.Label {
                            text = "V",
                            fontSize = 11,
                            fontWeight = "bold",
                            fontColor = Theme.colors.btnPrimaryText,
                        },
                    } or {},
                },
                UI.Label {
                    text = qDef.label,
                    fontSize = Theme.fontSize.body,
                    fontColor = qDef.color,
                },
            },
        }
        ::cont::
    end

    -- 预览结果
    local recyclable, totalPrice = GameItems.GetRecyclableItems(recycleQualities_)
    local cnt = 0
    for _, r in ipairs(recyclable) do cnt = cnt + (r.item.count or 1) end

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showRecycle_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "80%",
                backgroundColor = Theme.colors.bgDarkSolid,
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.md,
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label {
                        text = "回收站",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                        alignSelf = "center",
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = Theme.colors.divider,
                        spacing = 4,
                    },
                    UI.Label {
                        text = "选择回收品质(锁定物品不参与回收):",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.textLight,
                    },
                    -- 品质勾选网格
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        flexWrap = "wrap",
                        gap = 10,
                        children = checkChildren,
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = Theme.colors.divider,
                        spacing = 4,
                    },
                    -- 预览统计
                    Comp.BuildStatRow("符合条件物品",
                        tostring(cnt) .. " 件",
                        { valueColor = Theme.colors.textLight }),
                    Comp.BuildStatRow("预计获得",
                        "灵石 " .. tostring(totalPrice),
                        { valueColor = { 240, 220, 100, 255 } }),
                    -- 按钮行
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildSecondaryButton("取消", function()
                                        showRecycle_ = false
                                        Router.RebuildUI()
                                    end, { width = "100%" }),
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildInkButton("全部回收", function()
                                        showRecycle_ = false
                                        selectedItem_ = 1
                                        Router.RebuildUI()  -- 立即关闭弹窗
                                        GameItems.DoRecycle(recycleQualities_, function()
                                            Router.RebuildUI()  -- 服务端响应后刷新背包物品
                                        end)
                                    end, {
                                        width = "100%",
                                        fontSize = Theme.fontSize.body,
                                        disabled = cnt == 0,
                                    }),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建扩容确认弹窗
-- ============================================================================
local function BuildExpandConfirm()
    local cost, currency = GameItems.GetExpandCost()
    local cap = GameItems.GetBagCapacity()
    local newCap = cap + DataItems.BAG_EXPAND.perExpand
    local canExpand, reason = GameItems.CanExpandBag()

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showExpand_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "75%",
                backgroundColor = Theme.colors.bgDarkSolid,
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.md,
                alignItems = "center",
                onClick = function(self) end,
                children = {
                    UI.Label {
                        text = "储物扩容",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = Theme.colors.divider,
                        spacing = 4,
                    },
                    Comp.BuildStatRow("当前容量",
                        tostring(cap) .. " 格",
                        { valueColor = Theme.colors.textLight }),
                    Comp.BuildStatRow("扩容后",
                        tostring(newCap) .. " 格",
                        { valueColor = Theme.colors.gold }),
                    Comp.BuildStatRow("消耗",
                        currency .. " " .. tostring(cost),
                        { valueColor = { 240, 220, 100, 255 } }),
                    not canExpand and reason and UI.Label {
                        text = reason,
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.danger,
                        textAlign = "center",
                    } or nil,
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildSecondaryButton("取消", function()
                                        showExpand_ = false
                                        Router.RebuildUI()
                                    end, { width = "100%" }),
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildInkButton("确认扩容", function()
                                        showExpand_ = false
                                        Router.RebuildUI()  -- 立即关闭弹窗
                                        GameItems.DoExpandBag(function()
                                            Router.RebuildUI()  -- 服务端响应后刷新容量显示
                                        end)
                                    end, {
                                        width = "100%",
                                        fontSize = Theme.fontSize.body,
                                        disabled = not canExpand,
                                    }),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建批量出售确认弹窗
-- ============================================================================
local function BuildBatchSellConfirm()
    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            showBatchSell_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "75%",
                backgroundColor = Theme.colors.bgDarkSolid,
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.md,
                alignItems = "center",
                onClick = function(self) end,
                children = {
                    UI.Label {
                        text = "批量出售确认",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = Theme.colors.divider,
                        spacing = 4,
                    },
                    UI.Label {
                        text = "将出售灵宝品质及以下的所有物品",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.textLight,
                        textAlign = "center",
                    },
                    UI.Label {
                        text = "(已锁定物品不会被出售)",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                        textAlign = "center",
                    },
                    Comp.BuildStatRow("出售数量",
                        tostring(batchSellCount_) .. " 件",
                        { valueColor = Theme.colors.gold }),
                    Comp.BuildStatRow("预计获得",
                        "灵石 " .. tostring(batchSellPrice_),
                        { valueColor = { 240, 220, 100, 255 } }),
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        gap = 10,
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildSecondaryButton("取消", function()
                                        showBatchSell_ = false
                                        Router.RebuildUI()
                                    end, { width = "100%" }),
                                },
                            },
                            UI.Panel {
                                flexGrow = 1,
                                children = {
                                    Comp.BuildInkButton("确认出售", function()
                                        showBatchSell_ = false
                                        local ok, msg = GameItems.DoBatchSell("lingbao")
                                        Toast.Show(msg, { variant = ok and "success" or "error" })
                                        if ok then
                                            selectedItem_ = 1
                                            Router.RebuildUI()
                                        end
                                    end, { width = "100%", fontSize = Theme.fontSize.body }),
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 主页面构建
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 灵宠分类已移除，重置到法宝
    if activeCategory_ == "pet" then activeCategory_ = "fabao" end

    -- 来自装备槽点击时，切换到对应品类和子分类
    if payload and payload.category then
        activeCategory_ = payload.category
        activeSubTab_   = payload.subTab or nil
        selectedItem_   = 1
    end

    -- 旧数据迁移：确保所有物品有分类字段
    GameItems.MigrateBagCategories()

    local allItems = p.bagItems or {}

    -- 筛选当前分类的物品
    local filteredItems = GameItems.GetItemsByCategory(activeCategory_, activeSubTab_)
    if selectedItem_ > #filteredItems then selectedItem_ = 1 end

    -- 空状态
    if #allItems == 0 then
        return Comp.BuildPageShell("bag", p, {
            BuildCapacityBar(),
            BuildCategoryTabs(),
            Comp.BuildCardPanel("储物袋", {
                UI.Label {
                    text = "背包空空如也，去探索获取物品吧",
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textSecondary,
                    textAlign = "center",
                    width = "100%",
                    paddingVertical = 40,
                },
            }),
        }, Router.HandleNavigate)
    end

    -- 当前分类无物品
    local hasItems = #filteredItems > 0
    local sel = hasItems and filteredItems[selectedItem_] or nil

    -- 需要找到选中物品在全局 bagItems 中的索引（操作用）
    local globalIndex = 0
    if sel then
        for i, item in ipairs(allItems) do
            if item == sel then
                globalIndex = i
                break
            end
        end
    end

    -- 物品网格
    local itemCells = {}
    for i, item in ipairs(filteredItems) do
        itemCells[#itemCells + 1] = BuildItemCell(item, i, i == selectedItem_)
    end

    -- 子标签
    local subTabs = BuildSubTabs()

    local contentChildren = {
        -- 容量栏
        BuildCapacityBar(),
        -- 分类标签
        BuildCategoryTabs(),
    }
    -- 子标签（仅法宝/物品有，材料/灵宠没有）
    if subTabs then
        contentChildren[#contentChildren + 1] = subTabs
    end
    -- 已装备栏（仅法宝分类下显示）
    if activeCategory_ == "fabao" then
        local equippedBar = BuildEquippedBar()
        if equippedBar then
            contentChildren[#contentChildren + 1] = equippedBar
        end
    end
    -- 选中物品详情（装备用专属面板）
    contentChildren[#contentChildren + 1] = hasItems and (
        (sel and sel.isEquip) and BuildEquipDetail(sel, globalIndex) or BuildItemDetail(sel, globalIndex)
    ) or Comp.BuildCardPanel(nil, {
        UI.Label {
            text = "当前分类暂无物品",
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
            paddingVertical = 20,
        },
    })
    -- 物品网格（限制5排高度，超出滚动显示）
    if hasItems then
        contentChildren[#contentChildren + 1] = UI.ScrollView {
            width = "100%",
            maxHeight = 300,  -- 约4排格子高度
            showScrollbar = false,
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    justifyContent = "center",
                    gap = 8,
                    children = itemCells,
                },
            },
        }
    end
    -- 底部操作按钮
    contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 6,
            marginTop = 8,
            children = {
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("整理", function()
                            local msg = GameItems.SortBag()
                            Toast.Show(msg, { variant = "success" })
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("回收", function()
                            showRecycle_ = true
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("批量出售", function()
                            local cnt, price = GameItems.PreviewBatchSell("lingbao")
                            if cnt == 0 then
                                Toast.Show("没有可出售的物品", { variant = "error" })
                                return
                            end
                            batchSellCount_ = cnt
                            batchSellPrice_ = price
                            showBatchSell_ = true
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
                UI.Panel {
                    flexGrow = 1,
                    children = {
                        Comp.BuildSecondaryButton("扩容", function()
                            showExpand_ = true
                            Router.RebuildUI()
                        end, { width = "100%" }),
                    },
                },
            },
        }

    local pageShell = Comp.BuildPageShell("bag", p, contentChildren, Router.HandleNavigate)

    -- 叠加弹窗层
    if showRecycle_ or showExpand_ or showBatchSell_ then
        local overlay = nil
        if showRecycle_ then
            overlay = BuildRecyclePanel()
        elseif showExpand_ then
            overlay = BuildExpandConfirm()
        elseif showBatchSell_ then
            overlay = BuildBatchSellConfirm()
        end

        return UI.Panel {
            width = "100%",
            height = "100%",
            children = {
                pageShell,
                overlay,
            },
        }
    end

    return pageShell
end

return M
