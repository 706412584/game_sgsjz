-- ============================================================================
-- ui_stall.lua — 摆摊页面 (竖屏适配: 货架弹性宽度)
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local Bargain = require("ui_bargain")

local M = {}

local stallPanel = nil

--- 创建商品槽位 (弹性宽度适配窄屏)
---@param index number
local function createShelfSlot(index)
    local realmIdx = State.GetRealmIndex()
    local stallCfg = State.GetStallConfig()
    local prod = nil
    if index <= #Config.Products then
        prod = Config.Products[index]
    end

    -- 仙界商品不受摊位等级限制，仅按境界解锁
    local isCelestial = prod and prod.celestial == true
    local isLocked = (not isCelestial) and (index > stallCfg.slots)
    local isUnlocked = prod and Config.IsProductUnlocked(index, realmIdx)
    local stock = prod and State.state.products[prod.id] or 0

    -- 计算解锁该位置需要的摊位等级（仅凡间商品使用）
    local needStallLv = #Config.StallLevels + 1
    if not isCelestial then
        for _, sl in ipairs(Config.StallLevels) do
            if sl.slots >= index then needStallLv = sl.level; break end
        end
    end

    local bgColor = isLocked and { 30, 33, 45, 200 } or Config.Colors.panelLight

    -- 商品图片或文本回退
    local prodIcon
    if prod and isUnlocked and prod.image and Config.Images[prod.image] then
        prodIcon = UI.Panel { backgroundImage = Config.Images[prod.image], backgroundFit = "contain", width = 22, height = 22 }
    elseif prod and isUnlocked then
        prodIcon = UI.Label { text = prod.icon, fontSize = 14, fontColor = prod.color }
    end

    return UI.Panel {
        flexGrow = 1,
        flexBasis = 0,
        minWidth = 60,
        maxWidth = 110,
        height = 56,
        backgroundColor = bgColor,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = isLocked and Config.Colors.border or Config.Colors.borderGold,
        alignItems = "center",
        justifyContent = "center",
        gap = 1,
        padding = 2,
        children = isLocked and {
            UI.Label {
                text = "摊位Lv" .. needStallLv,
                fontSize = 8,
                fontColor = Config.Colors.textSecond,
            },
            UI.Label { text = "未解锁", fontSize = 8, fontColor = Config.Colors.textSecond },
        } or (prod and isUnlocked) and {
            prodIcon,
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 3,
                children = {
                    UI.Label { text = prod.name, fontSize = 9, fontColor = Config.Colors.textPrimary },
                    UI.Label {
                        text = "x" .. math.floor(stock),
                        fontSize = 9,
                        fontColor = stock > 0 and Config.Colors.textGreen or Config.Colors.red,
                    },
                },
            },
            UI.Label {
                text = State.GetProductPrice(prod) .. "灵石",
                fontSize = 8,
                fontColor = Config.Colors.textGold,
            },
        } or {
            UI.Label { text = "?", fontSize = 14, fontColor = Config.Colors.textSecond },
            UI.Label {
                text = "需" .. (prod and Config.Realms[prod.unlockRealm].name or "?"),
                fontSize = 8,
                fontColor = Config.Colors.textSecond,
            },
        },
    }
end

--- 创建顾客条目(大头像+高对比度卡片)
---@param index number
---@param customer Customer
local function createCustomerRow(index, customer)
    local prog = 0
    if customer.state == "buying" and customer.type.buyInterval > 0 then
        prog = 1.0 - (customer.buyTimer / customer.type.buyInterval)
    elseif customer.state == "buying" and customer.type.buyInterval == 0 then
        prog = 1.0
    end

    -- 头像 (用 backgroundImage 圆形面板，优先使用 customer.avatarKey 支持男女随机)
    local avatarWidget
    local avatarKey = customer.avatarKey or customer.type.avatar
    if avatarKey and Config.Images[avatarKey] then
        avatarWidget = UI.Panel {
            width = 28, height = 28, borderRadius = 14,
            backgroundImage = Config.Images[avatarKey],
            backgroundFit = "cover",
            borderWidth = 1,
            borderColor = customer.type.color,
            flexShrink = 0,
        }
    else
        avatarWidget = UI.Panel {
            width = 28, height = 28, borderRadius = 14,
            backgroundColor = { customer.type.color[1], customer.type.color[2], customer.type.color[3], 180 },
            alignItems = "center", justifyContent = "center",
            flexShrink = 0,
            children = {
                UI.Label { text = customer.type.name:sub(1, 3), fontSize = 10, fontColor = { 255, 255, 255, 255 } },
            },
        }
    end

    -- 想要的商品小图标
    local wantIcon
    if customer.wantProduct and customer.wantProduct.image and Config.Images[customer.wantProduct.image] then
        wantIcon = UI.Panel { backgroundImage = Config.Images[customer.wantProduct.image], backgroundFit = "contain", width = 14, height = 14 }
    end

    -- 对话气泡文本
    local dialogueText = customer.dialogue or ""
    -- 跨境界需求: 橙红色边框 + 提示文字
    local isCrossRealm = customer.isCrossRealm
    -- 状态颜色
    local isBuying = customer.state == "buying"
    local cardBg = isCrossRealm and { 55, 35, 30, 240 }
        or (isBuying and { 60, 55, 40, 240 } or { 50, 55, 75, 230 })
    local borderClr = isCrossRealm and { 200, 100, 50, 220 }
        or (customer.matched and Config.Colors.borderGold
        or (isBuying and { 120, 100, 50, 200 } or { 70, 80, 110, 180 }))
    local nameColor = customer.type.color
    local dialogColor = isCrossRealm and { 255, 160, 80, 255 }
        or (customer.matched and Config.Colors.textGold or Config.Colors.textPrimary)

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        paddingHorizontal = 4,
        paddingVertical = 2,
        backgroundColor = cardBg,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = borderClr,
        children = {
            -- 左侧头像
            avatarWidget,
            -- 右侧信息区
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 1,
                children = {
                    -- 第一行: 名字 + 标签
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        children = {
                            UI.Label {
                                text = customer.displayName or customer.type.name,
                                fontSize = 10,
                                fontColor = nameColor,
                                fontWeight = "bold",
                            },
                            customer.matched and UI.Label {
                                text = "满意",
                                fontSize = 7,
                                fontColor = { 255, 220, 100, 255 },
                                backgroundColor = { 100, 75, 20, 220 },
                                borderRadius = 3,
                                paddingHorizontal = 3,
                            } or nil,
                            isCrossRealm and UI.Label {
                                text = customer.crossRealmHint or "未解锁",
                                fontSize = 7,
                                fontColor = { 255, 200, 150, 255 },
                                backgroundColor = { 150, 60, 30, 220 },
                                borderRadius = 3,
                                paddingHorizontal = 3,
                            } or nil,
                            wantIcon,
                        },
                    },
                    -- 第二行: 对话气泡
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "💬",
                                fontSize = 8,
                            },
                            UI.Label {
                                text = dialogueText,
                                fontSize = 9,
                                fontColor = dialogColor,
                                flexShrink = 1,
                            },
                        },
                    },
                    -- 第三行: 进度条 + 目标商品 + 讨价还价按钮
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 3,
                        children = {
                            UI.ProgressBar {
                                value = prog,
                                flexGrow = 1,
                                flexBasis = 0,
                                height = 4,
                                variant = customer.type.payMul >= 2.0 and "warning" or "primary",
                            },
                            UI.Label {
                                text = customer.targetProduct and customer.targetProduct.name or "",
                                fontSize = 8,
                                fontColor = Config.Colors.textSecond,
                            },
                            -- 讨价还价按钮（仅在购买中、可讨价且未讨价时显示）
                            (isBuying and customer.canBargain and not customer.bargainDone) and UI.Button {
                                text = "讨价",
                                fontSize = 7,
                                paddingHorizontal = 5,
                                paddingVertical = 1,
                                backgroundColor = { 120, 90, 30, 230 },
                                textColor = Config.Colors.textGold,
                                borderRadius = 3,
                                onClick = function()
                                    Bargain.Open(customer.serverId)
                                end,
                            } or nil,
                            -- 已讨价结果标签
                            (customer.bargainDone and customer.bargainMul) and UI.Label {
                                text = customer.bargainMul > 1.0
                                    and ("+" .. math.floor((customer.bargainMul - 1) * 100) .. "%")
                                    or (customer.bargainMul < 1.0
                                        and ("-" .. math.floor((1 - customer.bargainMul) * 100) .. "%")
                                        or "原价"),
                                fontSize = 7,
                                fontColor = customer.bargainMul > 1.0 and Config.Colors.textGold or Config.Colors.red,
                                backgroundColor = { 40, 35, 25, 200 },
                                borderRadius = 3,
                                paddingHorizontal = 4,
                            } or nil,
                        },
                    },
                },
            },
        },
    }
end

function M.Create()
    stallPanel = UI.Panel {
        id = "stall_page",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        paddingHorizontal = 4,
        paddingVertical = 2,
        gap = 2,
        children = {
            -- ===== 上半部分: 打坐角色+标题+货架+增益 =====
            UI.Panel {
                width = "100%",
                flexShrink = 0,
                gap = 2,
                children = {
                    -- 标题 + 浮动文字
                    UI.Panel {
                        alignItems = "center",
                        gap = 1,
                        children = {
                            UI.Label {
                                text = "仙坊摊位",
                                fontSize = 12,
                                fontColor = Config.Colors.textGold,
                                fontWeight = "bold",
                            },
                            UI.Panel {
                                id = "floating_text_area",
                                flexDirection = "row",
                                alignItems = "center",
                            },
                        },
                    },
                    -- 货架
                    UI.Panel {
                        id = "shelf_container",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 4,
                        flexWrap = "wrap",
                    },
                    -- 广告增益状态
                    UI.Panel {
                        id = "boost_status",
                        flexDirection = "row",
                        justifyContent = "center",
                        gap = 4,
                        flexWrap = "wrap",
                    },
                },
            },
            -- ===== 中间: 顾客队列 (填满剩余空间, 可滚动) =====
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                flexShrink = 1,
                overflow = "hidden",
                gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        flexShrink = 0,
                        children = {
                            UI.Label {
                                text = "顾客队列",
                                fontSize = 10,
                                fontColor = Config.Colors.textPrimary,
                            },
                            UI.Panel {
                                flexDirection = "row",
                                alignItems = "center",
                                gap = 4,
                                children = {
                                    UI.Button {
                                        id = "auto_bargain_btn",
                                        text = Bargain.IsAutoBargainEnabled() and "自动讨价:开" or "自动讨价:关",
                                        fontSize = 7,
                                        height = 16,
                                        paddingHorizontal = 5,
                                        backgroundColor = Bargain.IsAutoBargainEnabled()
                                            and { 100, 75, 20, 230 } or { 50, 50, 60, 230 },
                                        textColor = Bargain.IsAutoBargainEnabled()
                                            and Config.Colors.textGold or Config.Colors.textSecond,
                                        borderRadius = 3,
                                        borderWidth = 1,
                                        borderColor = Bargain.IsAutoBargainEnabled()
                                            and Config.Colors.borderGold or Config.Colors.border,
                                        onClick = function(self)
                                            local enabled = Bargain.ToggleAutoBargain()
                                            self:SetText(enabled and "自动讨价:开" or "自动讨价:关")
                                            self:SetStyle({
                                                backgroundColor = enabled
                                                    and { 100, 75, 20, 230 } or { 50, 50, 60, 230 },
                                                textColor = enabled
                                                    and Config.Colors.textGold or Config.Colors.textSecond,
                                                borderColor = enabled
                                                    and Config.Colors.borderGold or Config.Colors.border,
                                            })
                                        end,
                                    },
                                    UI.Label {
                                        id = "queue_count",
                                        text = "0/1",
                                        fontSize = 9,
                                        fontColor = Config.Colors.textSecond,
                                    },
                                },
                            },
                        },
                    },
                    UI.Panel {
                        id = "customer_list",
                        gap = 2,
                        flexGrow = 1,
                        flexBasis = 0,
                        flexShrink = 1,
                        overflow = "scroll",
                    },
                },
            },
            -- ===== 底部: 统计栏 (固定在页面最底部) =====
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 12,
                paddingVertical = 2,
                backgroundColor = Config.Colors.panelLight,
                borderRadius = 4,
                flexShrink = 0,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            UI.Label { text = "售出", fontSize = 8, fontColor = Config.Colors.textSecond },
                            UI.Label { id = "stat_sold", text = "0", fontSize = 10, fontColor = Config.Colors.textPrimary },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        children = {
                            UI.Label { text = "收入", fontSize = 8, fontColor = Config.Colors.textSecond },
                            UI.Label { id = "stat_earned", text = "0", fontSize = 10, fontColor = Config.Colors.textGold },
                        },
                    },
                },
            },
        },
    }
    return stallPanel
end

function M.Refresh()
    if not stallPanel then return end

    -- 更新货架
    local shelfContainer = stallPanel:FindById("shelf_container")
    if shelfContainer then
        shelfContainer:ClearChildren()
        local stallCfg = State.GetStallConfig()
        local isAscended = (State.state.ascended == true)
        for i = 1, #Config.Products do
            local prod = Config.Products[i]
            if isAscended then
                -- 飞升玩家：只显示仙界商品
                if prod.celestial then
                    shelfContainer:AddChild(createShelfSlot(i))
                end
            else
                -- 未飞升：只显示凡间商品（含摊位等级锁定的槽位）
                if not prod.celestial then
                    shelfContainer:AddChild(createShelfSlot(i))
                end
            end
        end
        -- 未飞升玩家：补充超出商品数量的空锁定槽位
        if not isAscended then
            local stallCfgSlots = stallCfg.slots
            for i = #Config.Products + 1, stallCfgSlots do
                shelfContainer:AddChild(createShelfSlot(i))
            end
        end
    end

    -- 更新浮动文字
    local ftArea = stallPanel:FindById("floating_text_area")
    if ftArea then
        ftArea:ClearChildren()
        if #GameCore.floatingTexts > 0 then
            local ft = GameCore.floatingTexts[1]
            local alpha = math.floor(255 * (ft.life / ft.maxLife))
            ftArea:AddChild(UI.Label {
                text = ft.text,
                fontSize = 13,
                fontColor = { ft.color[1], ft.color[2], ft.color[3], alpha },
                fontWeight = "bold",
            })
        end
    end

    -- 更新广告增益状态
    local boostArea = stallPanel:FindById("boost_status")
    if boostArea then
        boostArea:ClearChildren()
        if GameCore.IsFlowBoosted() then
            boostArea:AddChild(UI.Label {
                text = "客流x2 " .. GameCore.FlowBoostRemain() .. "s",
                fontSize = 9,
                fontColor = Config.Colors.orange,
                backgroundColor = { 60, 40, 20, 200 },
                borderRadius = 4,
                paddingHorizontal = 6,
                paddingVertical = 2,
            })
        end
        if GameCore.IsPriceBoosted() then
            boostArea:AddChild(UI.Label {
                text = "售价x1.5 " .. math.floor(GameCore.PriceBoostRemain() / 60) .. "min",
                fontSize = 9,
                fontColor = Config.Colors.orange,
                backgroundColor = { 60, 40, 20, 200 },
                borderRadius = 4,
                paddingHorizontal = 6,
                paddingVertical = 2,
            })
        end
    end

    -- 更新顾客列表
    local custList = stallPanel:FindById("customer_list")
    if custList then
        custList:ClearChildren()
        if #GameCore.customers == 0 then
            custList:AddChild(UI.Label {
                text = "暂无顾客...",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                paddingVertical = 6,
            })
        else
            for i, cust in ipairs(GameCore.customers) do
                custList:AddChild(createCustomerRow(i, cust))
            end
        end
    end

    -- 队列计数
    local queueLbl = stallPanel:FindById("queue_count")
    if queueLbl then
        local stallCfg = State.GetStallConfig()
        queueLbl:SetText(#GameCore.customers .. "/" .. stallCfg.queueLimit)
    end

    -- 统计
    local soldLbl = stallPanel:FindById("stat_sold")
    if soldLbl then soldLbl:SetText(tostring(State.state.totalSold)) end
    local earnedLbl = stallPanel:FindById("stat_earned")
    if earnedLbl then earnedLbl:SetText(tostring(math.floor(State.state.totalEarned))) end
end

return M
