-- ============================================================================
-- 《问道长生》礼包商城页面
-- 三类礼包：新手礼包、境界突破礼包、每周特惠
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameGift   = require("game_gift")
local DataMon    = require("data_monetization")

local M = {}

-- ============================================================================
-- 礼包卡片
-- ============================================================================

--- 构建单个礼包卡片
---@param label string 礼包名称
---@param content table 奖励内容
---@param priceText string 价格文本
---@param canBuy boolean 是否可购买
---@param reason string 不可购买原因
---@param onBuy fun()|nil 购买回调
---@return table
local function BuildGiftCard(label, content, priceText, canBuy, reason, onBuy)
    local contentText = DataMon.FormatGiftContent(content)

    local btnChildren, btnBg, btnClick
    if canBuy then
        btnBg = { 120, 80, 20, 220 }
        btnClick = onBuy
        btnChildren = {
            UI.Label {
                text = priceText,
                fontSize = Theme.fontSize.small,
                fontWeight = "bold",
                fontColor = Theme.colors.gold,
            },
        }
    else
        btnBg = { 60, 55, 50, 150 }
        btnClick = nil
        btnChildren = {
            UI.Label {
                text = reason,
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = canBuy and Theme.colors.gold or Theme.colors.border,
        borderWidth = 1,
        padding = Theme.spacing.md,
        gap = 6,
        children = {
            -- 标题行
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    UI.Label {
                        text = label,
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = canBuy and Theme.colors.textGold or Theme.colors.textSecondary,
                        flexShrink = 1,
                    },
                    -- 购买按钮
                    UI.Panel {
                        minWidth = 80,
                        height = 30,
                        borderRadius = Theme.radius.sm,
                        backgroundColor = btnBg,
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = canBuy and "pointer" or "default",
                        onClick = btnClick and function(self)
                            btnClick()
                        end or nil,
                        children = btnChildren,
                    },
                },
            },
            -- 内容
            UI.Label {
                text = contentText,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
                width = "100%",
            },
        },
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local contentChildren = {
        -- 返回
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),

        Comp.BuildSectionTitle("礼包商城"),
    }

    -- ================================================================
    -- 1. 新手礼包
    -- ================================================================
    local newbieGifts = GameGift.GetNewbieGifts()
    local hasNewbie = false
    for _, g in ipairs(newbieGifts) do
        if g.config.day <= 7 then hasNewbie = true break end
    end

    if hasNewbie then
        local newbieCards = {}
        for _, g in ipairs(newbieGifts) do
            newbieCards[#newbieCards + 1] = BuildGiftCard(
                g.config.label,
                g.config.content,
                g.config.price .. "元",
                g.canBuy,
                g.reason,
                g.canBuy and function()
                    -- RMB 购买需要跳转充值（暂显示提示）
                    local Toast = require("ui_toast")
                    Toast.Show("充值功能开发中，敬请期待")
                end or nil
            )
        end

        contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("新手礼包 (限时7天)", newbieCards)
    end

    -- ================================================================
    -- 2. 境界突破礼包
    -- ================================================================
    local btGifts = GameGift.GetBreakthroughGifts()
    local btCards = {}
    for _, g in ipairs(btGifts) do
        btCards[#btCards + 1] = BuildGiftCard(
            g.config.realm .. "期突破礼包",
            g.config.content,
            g.config.price .. "元",
            g.canBuy,
            g.reason,
            g.canBuy and function()
                local Toast = require("ui_toast")
                Toast.Show("充值功能开发中，敬请期待")
            end or nil
        )
    end

    contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("境界突破礼包 (每种限购1次)", btCards)

    -- ================================================================
    -- 3. 每周特惠
    -- ================================================================
    local weeklyDeals = GameGift.GetWeeklyDeals()
    local weeklyCards = {}
    for _, d in ipairs(weeklyDeals) do
        local cfg = d.config
        local priceText
        if cfg.currency == "spiritStone" then
            priceText = cfg.cost .. "仙石"
        else
            priceText = cfg.cost .. "元"
        end

        weeklyCards[#weeklyCards + 1] = BuildGiftCard(
            cfg.label,
            cfg.content,
            priceText,
            d.canBuy,
            d.reason,
            d.canBuy and function()
                if cfg.currency == "spiritStone" then
                    GameGift.BuyWeeklyDeal(cfg.id, function(ok)
                        if ok then Router.RebuildUI() end
                    end)
                else
                    local Toast = require("ui_toast")
                    Toast.Show("充值功能开发中，敬请期待")
                end
            end or nil
        )
    end

    contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("每周特惠 (每周刷新)", weeklyCards)

    -- 说明
    contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("说明", {
        UI.Label {
            text = "新手礼包：创角后7天内限购，每种仅限1次。",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            width = "100%",
        },
        UI.Label {
            text = "境界突破礼包：达到对应境界后解锁，每种仅限1次。",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            width = "100%",
        },
        UI.Label {
            text = "每周特惠：每周指定日开放，每周限购1次，每周一刷新。",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            width = "100%",
        },
    })

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
