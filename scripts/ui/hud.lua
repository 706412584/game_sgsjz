------------------------------------------------------------
-- ui/hud.lua  —— 三国神将录 顶栏HUD
-- 显示：战力 | 铜钱 | 元宝 | 体力
-- 提供 Update(state) 刷新数值
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

-- 内部引用，用于动态更新
local powerLabel_
local copperBadge_
local yuanbaoBadge_
local staminaBadge_
local hudPanel_
local serverNameLabel_   -- 区服名
local serverDot_         -- 区服状态点
local serverGroup_       -- 区服组容器

------------------------------------------------------------
-- 创建 HUD 顶栏
------------------------------------------------------------
function M.Create()
    -- 战力标签
    powerLabel_ = UI.Label {
        text      = "战力 0",
        fontSize  = Theme.fontSize.subtitle,
        fontColor = C.gold,
        fontWeight = "bold",
    }

    -- 铜钱
    local copperLabel = UI.Label {
        id        = "hud_copper_val",
        text      = "0",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.text,
    }

    -- 元宝
    local yuanbaoLabel = UI.Label {
        id        = "hud_yuanbao_val",
        text      = "0",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.text,
    }

    -- 体力
    local staminaLabel = UI.Label {
        id        = "hud_stamina_val",
        text      = "0/120",
        fontSize  = Theme.fontSize.bodySmall,
        fontColor = C.text,
    }

    -- 保存引用
    copperBadge_  = copperLabel
    yuanbaoBadge_ = yuanbaoLabel
    staminaBadge_ = staminaLabel

    -- 资源组 (右侧)
    local resourceRow = UI.Panel {
        flexDirection = "row",
        alignItems    = "center",
        gap           = 16,
        children = {
            -- 铜钱
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 4,
                children = {
                    UI.Panel {
                        width  = S.hudIconSize, height = S.hudIconSize,
                        backgroundImage = "Textures/icons/icon_copper.png",
                        backgroundFit   = "contain",
                    },
                    copperLabel,
                },
            },
            -- 元宝
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 4,
                children = {
                    UI.Panel {
                        width  = S.hudIconSize, height = S.hudIconSize,
                        backgroundImage = "Textures/icons/icon_yuanbao.png",
                        backgroundFit   = "contain",
                    },
                    yuanbaoLabel,
                },
            },
            -- 体力
            UI.Panel {
                flexDirection = "row",
                alignItems    = "center",
                gap           = 4,
                children = {
                    UI.Panel {
                        width  = S.hudIconSize, height = S.hudIconSize,
                        backgroundImage = "Textures/icons/icon_stamina.png",
                        backgroundFit   = "contain",
                    },
                    staminaLabel,
                },
            },
        },
    }

    -- 区服入口（网络模式下显示）
    serverDot_ = UI.Panel {
        width  = 6,
        height = 6,
        borderRadius = 3,
        backgroundColor = { 76, 175, 80, 255 },
    }
    serverDot_:SetVisible(false)

    serverNameLabel_ = UI.Label {
        text      = "",
        fontSize  = Theme.fontSize.caption,
        fontColor = C.textDim,
    }

    serverGroup_ = UI.Panel {
        flexDirection  = "row",
        alignItems     = "center",
        gap            = 4,
        paddingHorizontal = 6,
        paddingVertical   = 3,
        borderRadius   = 10,
        backgroundColor = { C.panel[1], C.panel[2], C.panel[3], 180 },
        cursor         = "pointer",
        onClick = function()
            local ok, ServerUI = pcall(require, "ui.page_server")
            if ok and ServerUI.ShowServerSelectModal then
                ServerUI.ShowServerSelectModal()
            end
        end,
        children = {
            serverDot_,
            serverNameLabel_,
        },
    }
    serverGroup_:SetVisible(false)

    -- 左侧组：区服 + 战力
    local leftGroup = UI.Panel {
        flexDirection = "row",
        alignItems    = "center",
        gap           = 10,
        children = {
            serverGroup_,
            powerLabel_,
        },
    }

    -- 主 HUD 面板
    hudPanel_ = UI.Panel {
        width               = "100%",
        height              = S.hudHeight,
        flexDirection       = "row",
        alignItems          = "center",
        justifyContent      = "space-between",
        paddingHorizontal   = S.hudPadH,
        backgroundColor     = { C.bg[1], C.bg[2], C.bg[3], 220 },
        borderBottomWidth   = 1,
        borderBottomColor   = C.border,
        children = {
            leftGroup,
            resourceRow,
        },
    }

    return hudPanel_
end

------------------------------------------------------------
-- 更新 HUD 数值
------------------------------------------------------------
--- @param state table { power, copper, yuanbao, stamina, staminaMax }
function M.Update(state)
    if not state then return end

    if powerLabel_ then
        powerLabel_.text = "战力 " .. Theme.FormatNumber(state.power or 0)
    end
    if copperBadge_ then
        copperBadge_.text = Theme.FormatNumber(state.copper or 0)
    end
    if yuanbaoBadge_ then
        yuanbaoBadge_.text = Theme.FormatNumber(state.yuanbao or 0)
    end
    if staminaBadge_ then
        local sta    = state.stamina or 0
        local staMax = state.staminaMax or 120
        staminaBadge_.text = sta .. "/" .. staMax
    end
end

------------------------------------------------------------
-- 更新 HUD 区服显示
------------------------------------------------------------

local STATUS_COLORS = {
    ["open"]  = { 76,  175, 80,  255 },
    ["hot"]   = { 255, 152, 0,   255 },
    ["maint"] = { 244, 67,  54,  255 },
}

--- 设置区服名称和状态（网络模式调用）
---@param serverName string
---@param status? string  "open"|"hot"|"maint"
function M.SetServer(serverName, status)
    if serverGroup_ then
        serverGroup_:SetVisible(true)
    end
    if serverNameLabel_ then
        serverNameLabel_.text = serverName or ""
    end
    if serverDot_ then
        local dotColor = STATUS_COLORS[status or "open"] or STATUS_COLORS["open"]
        serverDot_:SetStyle({ backgroundColor = dotColor })
        serverDot_:SetVisible(true)
    end
end

--- 隐藏区服显示（单机模式）
function M.HideServer()
    if serverGroup_ then
        serverGroup_:SetVisible(false)
    end
end

------------------------------------------------------------
-- 获取 HUD 面板（已创建时直接返回）
------------------------------------------------------------
function M.GetPanel()
    return hudPanel_
end

return M
