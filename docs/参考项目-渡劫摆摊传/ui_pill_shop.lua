-- ============================================================================
-- ui_pill_shop.lua — 聚宝阁 UI (Modal 弹窗)
-- 用灵石购买丹药、材料等物品，按分类展示
-- 点击"购买"弹出确认弹窗：显示名字、单价、数量输入、总价
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local M = {}

-- ========== 辅助 ==========

--- 获取玩家已拥有数量(丹药在collectibles，材料在materials)
local function getOwnedCount(item)
    local s = State.state
    local count
    if item.isMaterial then
        count = s.materials and s.materials[item.id] or 0
    else
        count = s.collectibles and s.collectibles[item.id] or 0
    end
    return math.floor(count)
end

--- 获取今日已购数量
local function getDailyBought(item)
    local s = State.state
    if not s.dailyShopBuys then return 0 end
    return s.dailyShopBuys[item.id] or 0
end

--- 获取今日剩余可购数量(nil表示不限购)
local function getDailyRemaining(item)
    if not item.dailyLimit then return nil end
    return math.max(0, item.dailyLimit - getDailyBought(item))
end

--- 计算最大可购买数量(考虑灵石和每日限购)
local function getMaxBuyCount(item)
    local lingshi = State.state.lingshi or 0
    if item.price <= 0 then return 99 end
    local maxByLingshi = math.max(0, math.floor(lingshi / item.price))
    local remaining = getDailyRemaining(item)
    if remaining ~= nil then
        return math.min(maxByLingshi, remaining)
    end
    return maxByLingshi
end

-- ========== 购买确认弹窗 ==========

local function showBuyConfirmModal(item)
    local maxCount = getMaxBuyCount(item)
    local currentQty = math.min(1, maxCount)
    local c = item.color
    local owned = getOwnedCount(item)

    -- 引用：数量标签、总价标签、确认按钮(后续动态更新)
    local qtyLabel = nil
    local totalLabel = nil
    local confirmBtn = nil
    local confirmModal = nil

    --- 刷新数量/总价/按钮状态
    local function refreshQtyDisplay()
        if qtyLabel then
            qtyLabel:SetText(tostring(currentQty))
        end
        local total = currentQty * item.price
        if totalLabel then
            totalLabel:SetText(HUD.FormatNumber(total) .. " 灵石")
        end
        if confirmBtn then
            local canAfford = currentQty > 0 and total <= (State.state.lingshi or 0)
            confirmBtn.props.disabled = not canAfford
        end
    end

    --- 数量调整
    local function adjustQty(delta)
        currentQty = math.max(1, math.min(maxCount, currentQty + delta))
        refreshQtyDisplay()
    end

    -- 图标
    local iconWidget = nil
    if item.icon and item.icon ~= "" then
        iconWidget = UI.Panel {
            backgroundImage = item.icon,
            backgroundFit = "contain",
            width = 40,
            height = 40,
            borderRadius = 8,
        }
    end

    -- 数量控制按钮样式
    local qtyBtnStyle = {
        width = 30, height = 30, borderRadius = 6, fontSize = 14,
        backgroundColor = { 80, 80, 100, 200 },
        textColor = { 255, 255, 255, 255 },
    }

    qtyLabel = UI.Label {
        text = tostring(currentQty),
        fontSize = 16,
        fontWeight = "bold",
        fontColor = { 255, 255, 255, 255 },
        textAlign = "center",
        width = 50,
    }

    totalLabel = UI.Label {
        text = HUD.FormatNumber(currentQty * item.price) .. " 灵石",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = Config.Colors.gold,
        textAlign = "center",
    }

    local canAfford = maxCount >= 1
    confirmBtn = UI.Button {
        text = "确认购买",
        fontSize = 13,
        height = 36,
        width = "100%",
        borderRadius = 8,
        disabled = not canAfford,
        backgroundColor = canAfford and { c[1], c[2], c[3], 220 } or { 60, 60, 70, 200 },
        textColor = { 255, 255, 255, 255 },
        onClick = function(self)
            if currentQty <= 0 then return end
            self.props.disabled = true  -- 防止重复点击
            self:SetText("购买中...")
            GameCore.SendGameAction("buy_marketplace", {
                itemId = item.id,
                amount = currentQty,
            })
            -- 延迟关闭确认弹窗，等服务端响应后由事件刷新主弹窗
            if confirmModal then
                confirmModal:Close()
            end
        end,
    }

    -- 输入区：-10  -1  [数量]  +1  +10  MAX
    local qtyControls = UI.Panel {
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 4,
        flexWrap = "wrap",
        children = {
            UI.Button {
                text = "-10",
                fontSize = 11,
                width = qtyBtnStyle.width, height = qtyBtnStyle.height,
                borderRadius = qtyBtnStyle.borderRadius,
                backgroundColor = qtyBtnStyle.backgroundColor,
                textColor = qtyBtnStyle.textColor,
                onClick = function(self) adjustQty(-10) end,
            },
            UI.Button {
                text = "-1",
                fontSize = 11,
                width = qtyBtnStyle.width, height = qtyBtnStyle.height,
                borderRadius = qtyBtnStyle.borderRadius,
                backgroundColor = qtyBtnStyle.backgroundColor,
                textColor = qtyBtnStyle.textColor,
                onClick = function(self) adjustQty(-1) end,
            },
            -- 数量显示
            UI.Panel {
                backgroundColor = { 30, 30, 40, 200 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { c[1], c[2], c[3], 100 },
                justifyContent = "center",
                alignItems = "center",
                width = 56,
                height = 30,
                children = { qtyLabel },
            },
            UI.Button {
                text = "+1",
                fontSize = 11,
                width = qtyBtnStyle.width, height = qtyBtnStyle.height,
                borderRadius = qtyBtnStyle.borderRadius,
                backgroundColor = qtyBtnStyle.backgroundColor,
                textColor = qtyBtnStyle.textColor,
                onClick = function(self) adjustQty(1) end,
            },
            UI.Button {
                text = "+10",
                fontSize = 11,
                width = qtyBtnStyle.width, height = qtyBtnStyle.height,
                borderRadius = qtyBtnStyle.borderRadius,
                backgroundColor = qtyBtnStyle.backgroundColor,
                textColor = qtyBtnStyle.textColor,
                onClick = function(self) adjustQty(10) end,
            },
            UI.Button {
                text = "MAX",
                fontSize = 10,
                width = 36, height = qtyBtnStyle.height,
                borderRadius = qtyBtnStyle.borderRadius,
                backgroundColor = { c[1], c[2], c[3], 120 },
                textColor = { 255, 255, 255, 255 },
                onClick = function(self)
                    currentQty = math.max(1, maxCount)
                    refreshQtyDisplay()
                end,
            },
        },
    }

    confirmModal = UI.Modal {
        title = "购买确认",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
        children = {
            UI.ScrollView {
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                showScrollBar = false,
                children = {
            UI.Panel {
                width = "100%",
                padding = 12,
                paddingBottom = 25,
                gap = 10,
                alignItems = "center",
                children = {
                    -- 商品信息行
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 8,
                        width = "100%",
                        padding = 8,
                        backgroundColor = { c[1], c[2], c[3], 25 },
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = { c[1], c[2], c[3], 60 },
                        children = {
                            iconWidget or UI.Panel {
                                width = 40, height = 40,
                                borderRadius = 8,
                                backgroundColor = { c[1], c[2], c[3], 60 },
                                justifyContent = "center",
                                alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = string.sub(item.name, 1, 6),
                                        fontSize = 10, fontColor = c, fontWeight = "bold",
                                    },
                                },
                            },
                            UI.Panel {
                                flexGrow = 1, flexShrink = 1, gap = 2,
                                children = {
                                    UI.Label {
                                        text = item.name,
                                        fontSize = 13, fontColor = c, fontWeight = "bold",
                                    },
                                    UI.Label {
                                        text = "单价: " .. HUD.FormatNumber(item.price) .. " 灵石",
                                        fontSize = 10, fontColor = Config.Colors.textSecond,
                                    },
                                    UI.Label {
                                        text = "已拥有: " .. owned,
                                        fontSize = 9, fontColor = Config.Colors.textSecond,
                                    },
                                },
                            },
                        },
                    },
                    -- 限购提示
                    (function()
                        local remaining = getDailyRemaining(item)
                        if remaining ~= nil then
                            local soldOut = remaining <= 0
                            return UI.Label {
                                text = soldOut
                                    and "今日已售罄 (限购" .. item.dailyLimit .. "/日)"
                                    or "今日剩余 " .. remaining .. "/" .. item.dailyLimit,
                                fontSize = 9,
                                fontColor = soldOut and { 255, 100, 100, 255 } or { 255, 200, 80, 255 },
                            }
                        end
                        return nil
                    end)(),
                    -- 数量选择
                    UI.Label {
                        text = "购买数量 (最多 " .. maxCount .. ")",
                        fontSize = 10,
                        fontColor = Config.Colors.textSecond,
                    },
                    qtyControls,
                    -- 总价
                    UI.Panel {
                        width = "100%",
                        padding = 8,
                        backgroundColor = { 40, 35, 20, 200 },
                        borderRadius = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "总价",
                                fontSize = 10,
                                fontColor = Config.Colors.textSecond,
                            },
                            totalLabel,
                        },
                    },
                    -- 当前灵石
                    UI.Label {
                        text = "持有: " .. HUD.FormatNumber(State.state.lingshi or 0) .. " 灵石",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                    },
                    -- 确认按钮
                    confirmBtn,
                    -- 灵石不足提示
                    maxCount <= 0 and UI.Label {
                        text = "灵石不足，无法购买",
                        fontSize = 10,
                        fontColor = { 255, 100, 100, 255 },
                    } or nil,
                },
            },
                },
            },
        },
    }

    confirmModal:Open()
end

-- ========== 商品列表 UI ==========

--- 创建单个商品卡片
local function createItemCard(item)
    local owned = getOwnedCount(item)
    local c = item.color
    local remaining = getDailyRemaining(item)
    local soldOut = remaining ~= nil and remaining <= 0
    local canBuy = not soldOut and (State.state.lingshi or 0) >= item.price

    -- 尝试加载图标
    local iconWidget = nil
    if item.icon and item.icon ~= "" then
        iconWidget = UI.Panel {
            backgroundImage = item.icon,
            backgroundFit = "contain",
            width = 32, height = 32, borderRadius = 6,
        }
    end

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        padding = 6, gap = 6,
        backgroundColor = { c[1], c[2], c[3], 20 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { c[1], c[2], c[3], 60 },
        children = {
            -- 图标
            iconWidget or UI.Panel {
                width = 32, height = 32, borderRadius = 6,
                backgroundColor = { c[1], c[2], c[3], 60 },
                justifyContent = "center", alignItems = "center",
                children = {
                    UI.Label {
                        text = string.sub(item.name, 1, 6),
                        fontSize = 9, fontColor = c, fontWeight = "bold",
                    },
                },
            },
            -- 信息
            UI.Panel {
                flexGrow = 1, flexShrink = 1, gap = 1,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4, flexWrap = "wrap",
                        children = {
                            UI.Label {
                                text = item.name,
                                fontSize = 11, fontColor = c, fontWeight = "bold",
                            },
                            UI.Label {
                                text = "x1",
                                fontSize = 9, fontColor = { 200, 200, 210, 255 },
                            },
                            UI.Label {
                                text = HUD.FormatNumber(item.price) .. "灵石",
                                fontSize = 9, fontColor = Config.Colors.gold,
                            },
                            UI.Label {
                                text = "(库存" .. owned .. ")",
                                fontSize = 8, fontColor = Config.Colors.textSecond,
                            },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 4,
                        children = {
                            UI.Label {
                                text = item.desc,
                                fontSize = 8, fontColor = Config.Colors.textSecond,
                            },
                            remaining ~= nil and UI.Label {
                                text = soldOut and "今日售罄" or ("限购" .. remaining .. "/" .. item.dailyLimit),
                                fontSize = 8,
                                fontColor = soldOut and { 255, 100, 100, 255 } or { 255, 200, 80, 255 },
                            } or nil,
                        },
                    },
                },
            },
            -- 购买按钮(统一绿色，灵石不足/售罄灰色)
            UI.Button {
                text = soldOut and "售罄" or "购买",
                fontSize = 10,
                height = 26,
                paddingHorizontal = 12,
                backgroundColor = canBuy and { 60, 180, 80, 220 } or { 80, 80, 90, 180 },
                textColor = canBuy and { 255, 255, 255, 255 } or { 140, 140, 150, 255 },
                borderRadius = 6,
                disabled = not canBuy,
                onClick = function(self)
                    showBuyConfirmModal(item)
                end,
            },
        },
    }
end

--- 创建分类标题
local function createCategoryHeader(catName)
    return UI.Panel {
        paddingVertical = 4, paddingHorizontal = 6,
        children = {
            UI.Label {
                text = "-- " .. catName .. " --",
                fontSize = 10, fontColor = Config.Colors.gold,
                fontWeight = "bold", textAlign = "center", width = "100%",
            },
        },
    }
end

-- ========== 公开接口 ==========

--- 打开聚宝阁弹窗
function M.ShowPillShopModal()
    local s = State.state
    local isAscended = s.ascended or false

    local contentChildren = {}

    -- 提示文字
    table.insert(contentChildren, UI.Panel {
        padding = 4,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 6, alignItems = "center",
        children = {
            UI.Label {
                text = "用灵石直接购买丹药与材料",
                fontSize = 9, fontColor = Config.Colors.textSecond, textAlign = "center",
            },
        },
    })

    -- 按分类渲染商品
    for _, cat in ipairs(Config.MarketplaceCategories) do
        if not cat.celestial or isAscended then
            local catItems = {}
            for _, item in ipairs(Config.MarketplaceItems) do
                if item.category == cat.key then
                    if not item.celestial or isAscended then
                        table.insert(catItems, item)
                    end
                end
            end
            if #catItems > 0 then
                table.insert(contentChildren, createCategoryHeader(cat.name))
                for _, item in ipairs(catItems) do
                    table.insert(contentChildren, createItemCard(item))
                end
            end
        end
    end

    local modal = UI.Modal {
        title = "聚宝阁",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
        children = {
            UI.ScrollView {
                width = "100%",
                flexGrow = 1, flexShrink = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 6, padding = 8,
                        children = contentChildren,
                    },
                },
            },
        },
    }

    modal:Open()

    -- 监听购买事件 → 刷新弹窗
    local unsub1, unsub2
    unsub1 = State.On("pill_purchased", function()
        if not modal or not modal.node then
            if unsub1 then unsub1() end
            if unsub2 then unsub2() end
            return
        end
        modal:Destroy()
        if unsub1 then unsub1() end
        if unsub2 then unsub2() end
        M.ShowPillShopModal()
    end)
    unsub2 = State.On("marketplace_purchased", function()
        if not modal or not modal.node then
            if unsub1 then unsub1() end
            if unsub2 then unsub2() end
            return
        end
        modal:Destroy()
        if unsub1 then unsub1() end
        if unsub2 then unsub2() end
        M.ShowPillShopModal()
    end)
end

return M
