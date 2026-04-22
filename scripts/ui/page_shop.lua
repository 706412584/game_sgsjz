------------------------------------------------------------
-- ui/page_shop.lua  —— 三国神将录 商城页面
-- 三标签: 资源商店 / 礼包 / 充值
-- 500行以内
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local Shop  = require("data.data_shop")
local Modal = require("ui.modal_manager")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------
local callbacks_     = {}
local selectedTab_   = 1          -- 1=资源 2=礼包 3=充值
local contentArea_   = nil
local tabButtons_    = {}
local yuanbaoLabel_  = nil
local gameState_     = nil

local TAB_NAMES = { "资源商店", "礼包", "充值" }

------------------------------------------------------------
-- 工具函数
------------------------------------------------------------

--- 格式化奖励文本
local function rewardText(reward)
    local parts = {}
    for key, amount in pairs(reward) do
        local name = Shop.REWARD_NAMES[key] or key
        parts[#parts + 1] = name .. " x" .. amount
    end
    return table.concat(parts, "  ")
end

--- 刷新元宝显示
local function refreshYuanbao()
    if yuanbaoLabel_ and gameState_ then
        yuanbaoLabel_.text = "元宝: " .. Theme.FormatNumber(gameState_.yuanbao or 0)
    end
end

------------------------------------------------------------
-- 标签栏
------------------------------------------------------------
local function createTabBar()
    local tabs = {}
    for i, name in ipairs(TAB_NAMES) do
        local isActive = (i == selectedTab_)
        local btn = UI.Button {
            id        = "shop_tab_" .. i,
            text      = name,
            height    = 34,
            fontSize  = Theme.fontSize.body,
            fontWeight = isActive and "bold" or "normal",
            textColor  = isActive and C.bg or C.text,
            backgroundColor = isActive and C.gold or C.panel,
            hoverBackgroundColor = isActive and C.gold or C.panelLight,
            pressedBackgroundColor = isActive and C.goldDim or { 0, 0, 0, 40 },
            borderRadius = 6,
            paddingHorizontal = 18,
            transition = "all 0.15s easeOut",
            onClick = function()
                if selectedTab_ ~= i then
                    selectedTab_ = i
                    M.RefreshContent()
                end
            end,
        }
        tabButtons_[i] = btn
        tabs[#tabs + 1] = btn
    end

    return UI.Panel {
        width         = "100%",
        flexDirection = "row",
        gap           = 6,
        paddingHorizontal = 8,
        paddingVertical   = 6,
        children = tabs,
    }
end

--- 刷新标签高亮
local function refreshTabHighlight()
    for i, btn in ipairs(tabButtons_) do
        local isActive = (i == selectedTab_)
        btn:SetStyle({
            backgroundColor = isActive and C.gold or C.panel,
            textColor       = isActive and C.bg or C.text,
            fontWeight      = isActive and "bold" or "normal",
        })
    end
end

------------------------------------------------------------
-- 资源商品卡片
------------------------------------------------------------
local function createResourceCard(item)
    local shopInfo = Shop.GetShopInfo(gameState_)
    local limitText = ""
    if item.dailyLimit and item.dailyLimit > 0 then
        local bought = shopInfo.daily[item.id] or 0
        local remain = item.dailyLimit - bought
        limitText = "今日剩余: " .. remain .. "/" .. item.dailyLimit
    end

    return UI.Panel {
        width           = "100%",
        flexDirection   = "row",
        alignItems      = "center",
        backgroundColor = C.panel,
        borderRadius    = 8,
        borderColor     = C.border,
        borderWidth     = 1,
        padding         = 8,
        gap             = 10,
        children = {
            -- 图标
            UI.Panel {
                width  = 40, height = 40,
                backgroundImage = item.icon,
                backgroundFit   = "contain",
                flexShrink = 0,
            },
            -- 信息区
            UI.Panel {
                flexGrow  = 1,
                flexShrink = 1,
                flexBasis = 0,
                gap       = 2,
                children = {
                    UI.Label {
                        text      = item.name,
                        fontSize  = Theme.fontSize.body,
                        fontColor = C.text,
                        fontWeight = "bold",
                    },
                    UI.Label {
                        text      = item.desc,
                        fontSize  = Theme.fontSize.caption,
                        fontColor = C.textDim,
                    },
                    limitText ~= "" and UI.Label {
                        text      = limitText,
                        fontSize  = Theme.fontSize.caption,
                        fontColor = C.gold,
                    } or nil,
                },
            },
            -- 价格按钮
            Comp.SanButton {
                text    = item.price .. " 元宝",
                variant = "primary",
                width   = 90,
                height  = S.btnSmHeight,
                fontSize = S.btnSmFontSize,
                onClick = function()
                    Modal.Confirm("购买确认",
                        "确定花费 " .. item.price .. " 元宝购买\n"
                        .. item.name .. "?\n\n"
                        .. "内容: " .. rewardText(item.reward),
                        function()
                            if callbacks_.onBuy then
                                callbacks_.onBuy("resource", item.id)
                            end
                        end)
                end,
            },
        },
    }
end

------------------------------------------------------------
-- 礼包卡片
------------------------------------------------------------
local function createGiftCard(pack)
    local shopInfo = Shop.GetShopInfo(gameState_)

    -- 限购状态
    local limitText = ""
    local soldOut = false
    if pack.totalLimit and pack.totalLimit > 0 then
        local bought = shopInfo.total[pack.id] or 0
        if bought >= pack.totalLimit then
            soldOut = true
            limitText = "已售罄"
        else
            limitText = "限购 " .. (pack.totalLimit - bought) .. " 次"
        end
    elseif pack.dailyLimit and pack.dailyLimit > 0 then
        local bought = shopInfo.daily[pack.id] or 0
        if bought >= pack.dailyLimit then
            soldOut = true
            limitText = "今日已购"
        else
            limitText = "今日剩余 " .. (pack.dailyLimit - bought) .. " 次"
        end
    elseif pack.weeklyLimit and pack.weeklyLimit > 0 then
        local bought = shopInfo.weekly[pack.id] or 0
        if bought >= pack.weeklyLimit then
            soldOut = true
            limitText = "本周已购"
        else
            limitText = "本周剩余 " .. (pack.weeklyLimit - bought) .. " 次"
        end
    end

    -- 奖励列表
    local rewardChildren = {}
    for key, amount in pairs(pack.reward) do
        local name = Shop.REWARD_NAMES[key] or key
        local icon = Shop.REWARD_ICONS[key]
        rewardChildren[#rewardChildren + 1] = UI.Panel {
            flexDirection = "row",
            alignItems    = "center",
            gap           = 3,
            children = {
                icon and UI.Panel {
                    width = 16, height = 16,
                    backgroundImage = icon,
                    backgroundFit   = "contain",
                } or nil,
                UI.Label {
                    text      = name .. " x" .. Theme.FormatNumber(amount),
                    fontSize  = Theme.fontSize.caption,
                    fontColor = C.text,
                },
            },
        }
    end

    -- 折扣标签
    local discountPct = pack.origPrice
        and math.floor((1 - pack.price / pack.origPrice) * 100)
        or 0

    return UI.Panel {
        width           = "100%",
        backgroundColor = C.panel,
        borderRadius    = 8,
        borderColor     = soldOut and C.border or C.gold,
        borderWidth     = 1,
        padding         = 10,
        gap             = 6,
        opacity         = soldOut and 0.5 or 1,
        children = {
            -- 标题行
            UI.Panel {
                width         = "100%",
                flexDirection = "row",
                alignItems    = "center",
                justifyContent = "spaceBetween",
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems    = "center",
                        gap           = 6,
                        children = {
                            UI.Label {
                                text      = pack.name,
                                fontSize  = Theme.fontSize.subtitle,
                                fontColor = C.gold,
                                fontWeight = "bold",
                            },
                            discountPct > 0 and UI.Panel {
                                backgroundColor = C.red,
                                borderRadius    = 4,
                                paddingHorizontal = 4,
                                paddingVertical   = 1,
                                children = {
                                    UI.Label {
                                        text      = discountPct .. "%OFF",
                                        fontSize  = 9,
                                        fontColor = { 255, 255, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            } or nil,
                        },
                    },
                    UI.Label {
                        text      = limitText,
                        fontSize  = Theme.fontSize.caption,
                        fontColor = soldOut and C.red or C.textDim,
                    },
                },
            },
            -- 描述
            UI.Label {
                text      = pack.desc,
                fontSize  = Theme.fontSize.caption,
                fontColor = C.textDim,
            },
            -- 奖励列表
            UI.Panel {
                width         = "100%",
                flexDirection = "row",
                flexWrap      = "wrap",
                gap           = 6,
                children      = rewardChildren,
            },
            -- 价格行
            UI.Panel {
                width          = "100%",
                flexDirection  = "row",
                alignItems     = "center",
                justifyContent = "flexEnd",
                gap            = 8,
                children = {
                    pack.origPrice and UI.Label {
                        text      = pack.origPrice .. "",
                        fontSize  = Theme.fontSize.caption,
                        fontColor = C.textDim,
                        textDecoration = "strikethrough",
                    } or nil,
                    Comp.SanButton {
                        text     = soldOut and "已售罄" or (pack.price .. " 元宝"),
                        variant  = soldOut and "secondary" or "gold",
                        width    = 100,
                        height   = S.btnSmHeight,
                        fontSize = S.btnSmFontSize,
                        disabled = soldOut,
                        onClick  = function()
                            if soldOut then return end
                            Modal.Confirm("购买礼包",
                                "确定花费 " .. pack.price .. " 元宝购买\n"
                                .. pack.name .. "?",
                                function()
                                    if callbacks_.onBuy then
                                        callbacks_.onBuy("gift", pack.id)
                                    end
                                end)
                        end,
                    },
                },
            },
        },
    }
end

------------------------------------------------------------
-- 充值档位卡片
------------------------------------------------------------
local function createRechargeCard(tier)
    local shopInfo = Shop.GetShopInfo(gameState_)
    local isFirst  = not shopInfo.firstRC[tier.id]
    local totalGet = tier.yuanbao + (isFirst and tier.firstBonus or 0)

    return UI.Panel {
        width           = "100%",
        flexDirection   = "row",
        alignItems      = "center",
        backgroundColor = C.panel,
        borderRadius    = 8,
        borderColor     = tier.tag ~= "" and C.gold or C.border,
        borderWidth     = 1,
        padding         = 10,
        gap             = 10,
        children = {
            -- 元宝图标
            UI.Panel {
                width  = 40, height = 40,
                backgroundImage = "Textures/icons/icon_yuanbao.png",
                backgroundFit   = "contain",
                flexShrink = 0,
            },
            -- 信息区
            UI.Panel {
                flexGrow  = 1,
                flexShrink = 1,
                flexBasis = 0,
                gap       = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems    = "center",
                        gap           = 6,
                        children = {
                            UI.Label {
                                text      = "元宝 x" .. totalGet,
                                fontSize  = Theme.fontSize.subtitle,
                                fontColor = C.gold,
                                fontWeight = "bold",
                            },
                            tier.tag ~= "" and UI.Panel {
                                backgroundColor = C.red,
                                borderRadius    = 4,
                                paddingHorizontal = 4,
                                paddingVertical   = 1,
                                children = {
                                    UI.Label {
                                        text      = tier.tag,
                                        fontSize  = 9,
                                        fontColor = { 255, 255, 255, 255 },
                                        fontWeight = "bold",
                                    },
                                },
                            } or nil,
                        },
                    },
                    isFirst and UI.Label {
                        text      = "首充双倍! 基础" .. tier.yuanbao .. " + 赠" .. tier.firstBonus,
                        fontSize  = Theme.fontSize.caption,
                        fontColor = C.gold,
                    } or UI.Label {
                        text      = "基础 " .. tier.yuanbao .. " 元宝",
                        fontSize  = Theme.fontSize.caption,
                        fontColor = C.textDim,
                    },
                },
            },
            -- 购买按钮
            Comp.SanButton {
                text    = tier.price .. " 元",
                variant = "gold",
                width   = 80,
                height  = S.btnSmHeight,
                fontSize = S.btnSmFontSize,
                onClick = function()
                    Modal.Confirm("充值确认",
                        "确定充值 " .. tier.price .. " 元?\n"
                        .. "将获得 " .. totalGet .. " 元宝",
                        function()
                            if callbacks_.onBuy then
                                callbacks_.onBuy("recharge", tier.id)
                            end
                        end)
                end,
            },
        },
    }
end

------------------------------------------------------------
-- 刷新内容区
------------------------------------------------------------
function M.RefreshContent()
    if not contentArea_ then return end
    contentArea_:ClearChildren()
    refreshTabHighlight()
    refreshYuanbao()

    if selectedTab_ == 1 then
        -- 资源商店
        for _, item in ipairs(Shop.RESOURCE_ITEMS) do
            contentArea_:AddChild(createResourceCard(item))
        end

    elseif selectedTab_ == 2 then
        -- 礼包
        for _, pack in ipairs(Shop.GIFT_PACKS) do
            contentArea_:AddChild(createGiftCard(pack))
        end

    elseif selectedTab_ == 3 then
        -- 充值
        contentArea_:AddChild(UI.Label {
            text      = "模拟充值 (首充双倍)",
            fontSize  = Theme.fontSize.body,
            fontColor = C.textDim,
            textAlign = "center",
            marginBottom = 4,
        })
        for _, tier in ipairs(Shop.RECHARGE_TIERS) do
            contentArea_:AddChild(createRechargeCard(tier))
        end
    end
end

------------------------------------------------------------
-- 主入口
------------------------------------------------------------

--- 创建商城页面
---@param gameState table
---@param opts table { onBuy: fun(type: string, id: string) }
function M.Create(gameState, opts)
    opts = opts or {}
    callbacks_  = opts
    gameState_  = gameState
    selectedTab_ = 1
    tabButtons_ = {}

    -- 顶栏：元宝余额
    yuanbaoLabel_ = UI.Label {
        text      = "元宝: " .. Theme.FormatNumber(gameState.yuanbao or 0),
        fontSize  = Theme.fontSize.body,
        fontColor = C.gold,
        fontWeight = "bold",
    }

    local topBar = UI.Panel {
        width          = "100%",
        flexDirection  = "row",
        alignItems     = "center",
        justifyContent = "spaceBetween",
        paddingHorizontal = 10,
        paddingVertical   = 6,
        children = {
            UI.Label {
                text      = "商城",
                fontSize  = Theme.fontSize.headline,
                fontColor = C.gold,
                fontWeight = "bold",
            },
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 4,
                children = {
                    UI.Panel {
                        width = 20, height = 20,
                        backgroundImage = "Textures/icons/icon_yuanbao.png",
                        backgroundFit   = "contain",
                    },
                    yuanbaoLabel_,
                },
            },
        },
    }

    -- 内容滚动区
    contentArea_ = UI.Panel {
        width      = "100%",
        flexGrow   = 1,
        flexShrink = 1,
        flexBasis  = 0,
        overflow   = "scroll",
        gap        = 6,
        padding    = 8,
    }

    -- 主布局
    local root = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexDirection = "column",
        overflow      = "hidden",
        children = {
            topBar,
            createTabBar(),
            UI.Divider { color = C.divider, spacing = 0 },
            contentArea_,
        },
    }

    -- 初始加载
    M.RefreshContent()
    return root
end

--- 状态同步后刷新
---@param gameState table
function M.Refresh(gameState)
    gameState_ = gameState
    refreshYuanbao()
    -- 重建当前标签页内容以更新限购状态
    M.RefreshContent()
end

return M
