-- ============================================================================
-- 《问道长生》世界聊天 UI
-- 职责：世界聊天消息列表构建
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Common = require("ui_chat_common")

local M = {}

local RECALL_TIME_LIMIT = 120  -- 与服务端保持一致（秒）

-- ============================================================================
-- 单条消息行
-- ============================================================================

--- 构建世界聊天消息行
---@param msg table { sender, senderName, text, timestamp, msgId }
---@param onAvatarClick? fun(sender: table)
---@param myUserId? number 当前用户ID，用于判断是否显示撤回按钮
---@return table UI 组件
function M.BuildMsgRow(msg, onAvatarClick, myUserId)
    -- 全服公告：特殊样式渲染
    if msg.isAnnounce then
        return UI.Panel {
            width = "100%",
            flexDirection = "column",
            paddingVertical   = 6,
            paddingHorizontal = 10,
            marginVertical    = 3,
            backgroundColor   = { 60, 38, 8, 190 },
            borderRadius      = 4,
            children = {
                Common.BuildAnnounce(
                    msg.richText or "",
                    Theme.fontSize.small,
                    Theme.colors.textLight
                ),
            },
        }
    end

    local realm = msg.sender and msg.sender.realm or ""
    local realmLabel = realm ~= "" and ("[" .. realm .. "]") or ""

    -- 判断是否可以撤回：自己的消息 + 2分钟内 + 有 msgId
    local canRecall = false
    if myUserId and msg.sender and msg.sender.userId == myUserId
       and msg.msgId and msg.msgId ~= "" then
        local elapsed = os.time() - (msg.timestamp or 0)
        canRecall = elapsed <= RECALL_TIME_LIMIT
    end

    local rowChildren = {
        -- 头像
        Common.BuildAvatar(msg.sender, 32, onAvatarClick),
        -- 发送者名字
        UI.Label {
            text = msg.senderName,
            fontSize = Theme.fontSize.body,
            fontWeight = "bold",
            fontColor = Theme.colors.textGold,
        },
        -- 境界标签
        realmLabel ~= "" and UI.Label {
            text = realmLabel,
            fontSize = Theme.fontSize.small,
            fontColor = { 140, 125, 105, 200 },
        } or nil,
        -- 内容（支持表情高亮）
        Common.BuildRichText(msg.text, Theme.fontSize.body, Theme.colors.textLight),
        -- 时间
        UI.Label {
            text = Common.FormatTime(msg.timestamp),
            fontSize = 9,
            fontColor = Theme.colors.textSecondary,
        },
    }

    -- 撤回按钮
    if canRecall then
        rowChildren[#rowChildren + 1] = UI.Panel {
            paddingHorizontal = 4,
            paddingVertical = 1,
            borderRadius = 3,
            backgroundColor = { 80, 60, 50, 150 },
            cursor = "pointer",
            onClick = function()
                local ok, Chat = pcall(require, "ui_chat")
                if ok and Chat.RecallMessage then
                    Chat.RecallMessage(msg.msgId)
                end
            end,
            children = {
                UI.Label {
                    text = "撤回",
                    fontSize = 9,
                    fontColor = { 200, 160, 120, 200 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        paddingVertical = 4,
        paddingHorizontal = 8,
        alignItems = "center",
        children = rowChildren,
    }
end

-- ============================================================================
-- 消息列表
-- ============================================================================

--- 构建世界聊天消息列表区域
---@param messages table[]  消息数组
---@param onAvatarClick? fun(sender: table)
---@param myUserId? number 当前用户ID
---@return table UI 组件
function M.BuildMessageList(messages, onAvatarClick, myUserId)
    local msgChildren = {}
    if #messages == 0 then
        msgChildren[1] = UI.Label {
            text = "暂无消息，快来发送第一条吧",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
            paddingVertical = 40,
        }
    else
        for _, msg in ipairs(messages) do
            msgChildren[#msgChildren + 1] = M.BuildMsgRow(msg, onAvatarClick, myUserId)
        end
    end

    return UI.ScrollView {
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
    }
end

return M
