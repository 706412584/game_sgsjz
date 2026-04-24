-- ============================================================================
-- 《问道长生》仙信（邮件）页面
-- 职责：显示未读邮件列表，支持单封领取和一键领取
-- ============================================================================

local UI         = require("urhox-libs/UI")
local Theme      = require("ui_theme")
local Comp       = require("ui_components")
local RT         = require("rich_text")
local Router     = require("ui_router")
local GamePlayer = require("game_player")
local GameMail   = require("game_mail")
local Toast      = require("ui_toast")

local M = {}

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8, paddingVertical = 4, cursor = "pointer",
                onClick = function(self)
                    Router.EnterState(Router.STATE_HOME)
                end,
                children = {
                    UI.Label { text = "< 返回", fontSize = Theme.fontSize.body, fontColor = Theme.colors.gold },
                },
            },
            UI.Label {
                text = "仙信",
                fontSize = Theme.fontSize.heading, fontWeight = "bold", fontColor = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- 单封邮件卡片
-- ============================================================================
local function BuildMailCard(mail)
    local val = mail.value or {}
    local mailType = val.type or "unknown"

    -- 根据类型生成标题和描述
    local title = "仙信"
    local desc  = ""
    local amount = 0

    if mailType == "trade_income" then
        title = "交易收入"
        local itemName  = val.itemName or "物品"
        local itemCount = val.itemCount or 1
        local income    = val.income or 0
        local fee       = val.fee or 0
        amount = income
        desc = "<c=gold>" .. itemName .. "</c> x<c=green>" .. tostring(itemCount)
            .. "</c> 已售出，扣除手续费 <c=orange>" .. tostring(fee) .. "</c> 灵石"
    end

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label { text = title, fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.textGold },
                UI.Label {
                    text = mail.time or "",
                    fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary,
                },
            },
        },
        -- 描述（RT 高亮物品名/数量/手续费）
        RT.Build(desc ~= "" and desc or "  ", Theme.fontSize.small, Theme.colors.textLight),
        -- 附件 + 领取按钮
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginTop = 4,
            children = {
                amount > 0 and UI.Panel {
                    flexDirection = "row", gap = 4, alignItems = "center",
                    children = {
                        UI.Label { text = "附件:", fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
                        RT.Build("<c=gold>" .. tostring(amount) .. "</c> 灵石", Theme.fontSize.body, Theme.colors.textLight),
                    },
                } or UI.Panel {},
                UI.Panel {
                    paddingHorizontal = 16, paddingVertical = 6,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = Theme.colors.gold,
                    cursor = "pointer",
                    onClick = function(self)
                        GameMail.ClaimMail(mail)
                    end,
                    children = {
                        UI.Label { text = "领取", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText },
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local mails = GameMail.GetMails()

    -- 操作栏：刷新 + 一键领取
    local actionBar = UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        marginVertical = 4,
        children = {
            UI.Panel {
                paddingHorizontal = 12, paddingVertical = 6,
                borderRadius = Theme.radius.sm,
                backgroundColor = { 50, 42, 35, 200 },
                cursor = "pointer",
                onClick = function(self)
                    GameMail.RequestUnreadMails()
                    Toast.Show("正在刷新...", "info")
                end,
                children = {
                    UI.Label { text = "刷新", fontSize = Theme.fontSize.body, fontColor = Theme.colors.gold },
                },
            },
            #mails > 0 and UI.Panel {
                paddingHorizontal = 12, paddingVertical = 6,
                borderRadius = Theme.radius.sm,
                backgroundColor = Theme.colors.gold,
                cursor = "pointer",
                onClick = function(self)
                    GameMail.ClaimAll()
                end,
                children = {
                    UI.Label { text = "一键领取", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText },
                },
            } or nil,
        },
    }

    -- 邮件列表或空状态
    local contentChildren = { BuildBackRow(), actionBar }

    if #mails == 0 then
        contentChildren[#contentChildren + 1] = Comp.BuildCardPanel(nil, {
            UI.Label {
                text = IsNetworkMode() and "暂无未读仙信" or "仙信功能需联网使用",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
                textAlign = "center",
                width = "100%",
                paddingVertical = 60,
            },
        })
    else
        for _, mail in ipairs(mails) do
            contentChildren[#contentChildren + 1] = BuildMailCard(mail)
        end
    end

    local page = Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)

    -- 注册邮件变化回调（自动刷新 UI）
    GameMail.SetOnChanged(function()
        Router.RebuildUI()
    end)

    return page
end

return M
