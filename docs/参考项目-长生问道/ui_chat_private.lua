-- ============================================================================
-- 《问道长生》私聊 UI
-- 职责：私聊联系人列表 + 私聊消息列表
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Common = require("ui_chat_common")
local GameSocial = require("game_social")

local M = {}

-- ============================================================================
-- 私聊消息行
-- ============================================================================

--- 构建私聊消息行（气泡样式）
---@param msg table { sender, senderName, text, timestamp, isMine }
---@param onAvatarClick? fun(sender: table)
---@return table UI 组件
function M.BuildMsgRow(msg, onAvatarClick)
    local isMine = msg.isMine
    local nameColor = isMine and Theme.colors.accent or Theme.colors.textGold
    local bubbleBg = isMine and { 60, 90, 60, 200 } or { 50, 45, 40, 200 }

    local bubbleContent = UI.Panel {
        maxWidth = "70%",
        backgroundColor = bubbleBg,
        borderRadius = Theme.radius.sm,
        padding = { 6, 10 },
        gap = 2,
        children = {
            UI.Label {
                text = msg.senderName,
                fontSize = 9,
                fontColor = nameColor,
            },
            Common.BuildRichText(msg.text, Theme.fontSize.small, Theme.colors.textLight),
        },
    }

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = isMine and "flex-end" or "flex-start",
        paddingVertical = 3,
        paddingHorizontal = 8,
        gap = 6,
        alignItems = "flex-start",
        children = isMine and {
            bubbleContent,
            Common.BuildAvatar(msg.sender, 28),
        } or {
            Common.BuildAvatar(msg.sender, 28, onAvatarClick),
            bubbleContent,
        },
    }
end

-- ============================================================================
-- 联系人列表
-- ============================================================================

--- 构建联系人列表项
---@param contact table { uid, name, lastMsg, lastTime }
---@param onSelect fun(contact: table)
---@return table UI 组件
local function BuildContactRow(contact, onSelect)
    local isOnline = GameSocial.IsOnline(contact.uid)

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 10,
        paddingVertical = 10,
        paddingHorizontal = 12,
        alignItems = "center",
        borderColor = Theme.colors.border,
        borderWidth = { bottom = 1 },
        cursor = "pointer",
        onClick = function()
            onSelect(contact)
        end,
        children = {
            -- 在线状态圆点
            UI.Panel {
                width = 8, height = 8,
                borderRadius = 4,
                backgroundColor = isOnline and { 80, 200, 80, 255 } or { 100, 100, 100, 180 },
            },
            -- 名字
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = contact.name,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Label {
                                text = isOnline and "在线" or "离线",
                                fontSize = 9,
                                fontColor = isOnline and { 80, 200, 80, 255 } or Theme.colors.textSecondary,
                            },
                        },
                    },
                    contact.lastMsg ~= "" and UI.Label {
                        text = contact.lastMsg,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textSecondary,
                    } or nil,
                },
            },
            -- 时间
            contact.lastTime > 0 and UI.Label {
                text = Common.FormatTime(contact.lastTime),
                fontSize = 9,
                fontColor = Theme.colors.textSecondary,
            } or nil,
        },
    }
end

--- 构建联系人列表区域
---@param contacts table[]  { {uid, name, lastMsg, lastTime}, ... }
---@param onSelect fun(contact: table)
---@return table UI 组件
function M.BuildContactList(contacts, onSelect)
    if #contacts == 0 then
        return UI.Panel {
            width = "100%",
            padding = 20,
            alignItems = "center",
            children = {
                UI.Label {
                    text = "暂无私聊对象，可从好友列表发起私聊",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textSecondary,
                    textAlign = "center",
                },
            },
        }
    end

    local rows = {}
    for _, c in ipairs(contacts) do
        rows[#rows + 1] = BuildContactRow(c, onSelect)
    end

    return UI.Panel {
        width = "100%",
        children = rows,
    }
end

-- ============================================================================
-- 私聊消息列表（带标题栏）
-- ============================================================================

--- 构建私聊消息区域（含标题栏 + 消息列表）
---@param targetName string  对方名字
---@param messages table[]   消息数组
---@param onBack fun()       返回联系人列表
---@param onAvatarClick? fun(sender: table)
---@return table UI 组件
function M.BuildChatArea(targetName, messages, onBack, onAvatarClick)
    local msgChildren = {}
    if #messages == 0 then
        msgChildren[1] = UI.Label {
            text = "暂无消息记录，发送第一条消息吧",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
            paddingVertical = 40,
        }
    else
        for _, msg in ipairs(messages) do
            msgChildren[#msgChildren + 1] = M.BuildMsgRow(msg, onAvatarClick)
        end
    end

    return UI.Panel {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        children = {
            -- 私聊对象标题栏
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                backgroundColor = { 40, 35, 30, 220 },
                padding = { 8, 12 },
                alignItems = "center",
                gap = 8,
                borderColor = Theme.colors.border,
                borderWidth = { bottom = 1 },
                children = {
                    -- 返回按钮
                    UI.Panel {
                        width = 32, height = 32,
                        justifyContent = "center",
                        alignItems = "center",
                        cursor = "pointer",
                        onClick = onBack,
                        children = {
                            UI.Label {
                                text = "<",
                                fontSize = Theme.fontSize.heading,
                                fontColor = Theme.colors.gold,
                            },
                        },
                    },
                    UI.Label {
                        text = targetName,
                        fontSize = Theme.fontSize.subtitle,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                },
            },
            -- 消息列表
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                scrollMultiplier = Theme.scrollSensitivity,
                backgroundColor = Theme.colors.bgDark,
                children = {
                    UI.Panel {
                        width = "100%",
                        padding = Theme.spacing.sm,
                        gap = 2,
                        children = msgChildren,
                    },
                },
            },
        },
    }
end

return M
