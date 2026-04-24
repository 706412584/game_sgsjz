-- ============================================================================
-- 《问道长生》玩家信息弹窗
-- 职责：点击头像弹出玩家信息卡片，提供私聊/加好友/屏蔽/举报操作
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Router = require("ui_router")
local ChatCommon = require("ui_chat_common")
local Toast = require("ui_toast")
local RT    = require("rich_text")

local M = {}

-- ============================================================================
-- 工具
-- ============================================================================

--- 检查是否是自己
---@param sender table { userId }
---@return boolean
local function isMyself(sender)
    local ok, ClientNet = pcall(require, "network.client_net")
    if not ok then return false end
    return sender.userId == ClientNet.GetUserId()
end

--- 检查是否已是好友
---@param uid number
---@return boolean
local function isFriend(uid)
    local ok, GameSocial = pcall(require, "game_social")
    if not ok then return false end
    local friends = GameSocial.GetFriends()
    for _, f in ipairs(friends) do
        if f.friendUid == uid then return true end
    end
    return false
end

--- 检查是否已屏蔽
---@param uid number
---@return boolean
local function isBlocked(uid)
    local ok, GameBlock = pcall(require, "game_block")
    if not ok then return false end
    return GameBlock.IsBlocked(uid)
end

-- ============================================================================
-- 弹窗构建
-- ============================================================================

--- 显示玩家信息弹窗
---@param sender table { userId, name, gender, realm, avatarIndex }
function M.Show(sender)
    if not sender or not sender.userId then return end

    local self_ = isMyself(sender)
    local friend_ = isFriend(sender.userId)
    local blocked_ = isBlocked(sender.userId)

    -- 操作按钮列表
    local actionButtons = {}

    if not self_ then
        -- 私聊按钮
        actionButtons[#actionButtons + 1] = UI.Panel {
            width = "100%",
            height = 40,
            borderRadius = Theme.radius.sm,
            backgroundColor = Theme.colors.gold,
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function()
                Router.HideOverlayDialog()
                -- 跳转到私聊
                local okChat, Chat = pcall(require, "ui_chat")
                if okChat then
                    -- 设置私聊目标后跳转聊天页
                    Router.EnterState(Router.STATE_CHAT, {
                        privateTarget = { uid = sender.userId, name = sender.name or "???" },
                    })
                end
            end,
            children = {
                UI.Label {
                    text = "私聊",
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = Theme.colors.btnPrimaryText,
                },
            },
        }

        -- 加好友按钮
        actionButtons[#actionButtons + 1] = UI.Panel {
            width = "100%",
            height = 40,
            borderRadius = Theme.radius.sm,
            backgroundColor = friend_ and Theme.colors.bgDark or { 60, 100, 60, 220 },
            justifyContent = "center",
            alignItems = "center",
            cursor = friend_ and nil or "pointer",
            onClick = not friend_ and function()
                local okSocial, GameSocial = pcall(require, "game_social")
                if okSocial then
                    GameSocial.AddFriend(sender.userId)
                    Toast.Show("好友申请已发送")
                    Router.HideOverlayDialog()
                end
            end or nil,
            children = {
                UI.Label {
                    text = friend_ and "已是好友" or "加好友",
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = friend_ and Theme.colors.textSecondary or Theme.colors.textLight,
                },
            },
        }

        -- 屏蔽按钮
        actionButtons[#actionButtons + 1] = UI.Panel {
            width = "100%",
            height = 40,
            borderRadius = Theme.radius.sm,
            backgroundColor = { 80, 40, 40, 200 },
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function()
                local okBlock, GameBlock = pcall(require, "game_block")
                if okBlock then
                    if blocked_ then
                        GameBlock.Unblock(sender.userId)
                        Toast.Show("已取消屏蔽")
                    else
                        GameBlock.Block(sender.userId, sender.name or "???")
                        Toast.Show("已屏蔽该玩家")
                    end
                end
                Router.HideOverlayDialog()
            end,
            children = {
                UI.Label {
                    text = blocked_ and "取消屏蔽" or "屏蔽",
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.dangerLight,
                },
            },
        }

        -- 举报按钮
        actionButtons[#actionButtons + 1] = UI.Panel {
            width = "100%",
            height = 40,
            borderRadius = Theme.radius.sm,
            backgroundColor = { 60, 30, 30, 200 },
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function()
                local okBlock, GameBlock = pcall(require, "game_block")
                if okBlock and GameBlock.Report then
                    GameBlock.Report(sender.userId, sender.name or "???", "聊天举报")
                end
                Toast.Show("举报已提交，感谢反馈")
                Router.HideOverlayDialog()
            end,
            children = {
                UI.Label {
                    text = "举报",
                    fontSize = Theme.fontSize.body,
                    fontColor = { 200, 100, 100, 200 },
                },
            },
        }
    end

    -- 关闭按钮
    actionButtons[#actionButtons + 1] = UI.Panel {
        width = "100%",
        height = 36,
        justifyContent = "center",
        alignItems = "center",
        cursor = "pointer",
        onClick = function()
            Router.HideOverlayDialog()
        end,
        children = {
            UI.Label {
                text = "关闭",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
            },
        },
    }

    -- 弹窗主体
    local dialog = UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 140 },
        onClick = function()
            Router.HideOverlayDialog()
        end,
        children = {
            UI.Panel {
                width = 280,
                backgroundColor = { 35, 30, 25, 240 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = 20,
                gap = 12,
                alignItems = "center",
                onClick = function() end,  -- 阻止冒泡关闭
                children = {
                    -- 头像（大图）
                    ChatCommon.BuildAvatar(sender, 72),
                    -- 名字
                    UI.Label {
                        text = sender.name or "???",
                        fontSize = Theme.fontSize.heading,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    -- 境界
                    RT.Build(sender.realm or "凡人", Theme.fontSize.small, Theme.colors.gold),
                    -- 分割线
                    UI.Panel {
                        width = "80%",
                        height = 1,
                        backgroundColor = Theme.colors.divider,
                    },
                    -- 操作按钮组
                    UI.Panel {
                        width = "100%",
                        gap = 8,
                        children = actionButtons,
                    },
                },
            },
        },
    }

    Router.ShowOverlayDialog(dialog)
end

return M
