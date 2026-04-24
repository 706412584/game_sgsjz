-- ============================================================================
-- 《问道长生》聊天输入区
-- 职责：输入框 + 发送按钮（后续 P2.1 追加表情面板）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Toast = require("ui_toast")
local DataChat = require("data_chat")

local M = {}

-- 表情面板展开状态（模块级共享）
local emojiPanelOpen_ = false

-- ============================================================================
-- 输入区域组件
-- ============================================================================

--- 构建表情选择面板（5列网格）
---@param onSelect fun(emojiName: string)  选择回调
---@return table UI 组件
local function BuildEmojiPanel(onSelect)
    local COLS = 5
    local rows = {}
    local row = {}

    for i, name in ipairs(DataChat.EMOJI_LIST) do
        local imgPath = DataChat.EMOJI_IMAGES[name]
        local cellContent
        if imgPath then
            cellContent = UI.Panel {
                width = 28,
                height = 28,
                backgroundImage = imgPath,
                backgroundFit = "contain",
            }
        else
            cellContent = UI.Label {
                text = "[" .. name .. "]",
                fontSize = 12,
                fontWeight = "bold",
                fontColor = DataChat.EMOJI_COLORS[name] or { 255, 210, 60, 255 },
            }
        end
        row[#row + 1] = UI.Panel {
            width = "20%",
            height = 40,
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function()
                onSelect(name)
            end,
            children = {
                cellContent,
                UI.Label {
                    text = name,
                    fontSize = 8,
                    fontColor = Theme.colors.textSecondary,
                },
            },
        }
        if #row >= COLS or i == #DataChat.EMOJI_LIST then
            rows[#rows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = row,
            }
            row = {}
        end
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 30, 25, 20, 240 },
        borderColor = Theme.colors.borderGold,
        borderWidth = { top = 1 },
        padding = 6,
        gap = 2,
        children = rows,
    }
end

-- 模块级文本缓存：确保闭包中始终能取到最新值
local currentText_ = ""

--- 构建聊天输入区域（含表情按钮 + 表情面板）
---@param opts table
---  placeholder: string  占位文本
---  inputText: string    当前输入文本
---  onChangeText: fun(text: string)  文本变更回调
---  onSend: fun(text: string)        发送回调
---@return table UI 组件
function M.BuildInputArea(opts)
    -- 每次 Build 同步外部传入的最新文本
    currentText_ = opts.inputText or ""

    local children = {}

    -- 表情面板（展开时显示）
    if emojiPanelOpen_ then
        children[#children + 1] = BuildEmojiPanel(function(emojiName)
            local newText = currentText_ .. "[" .. emojiName .. "]"
            currentText_ = newText
            if opts.onChangeText then
                opts.onChangeText(newText)
            end
            -- 不关闭面板，方便连续选择多个表情
            local okRouter, Router = pcall(require, "ui_router")
            if okRouter and Router.RebuildUI then Router.RebuildUI() end
        end)
    end

    -- 输入行
    children[#children + 1] = UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        padding = { 8, 12 },
        backgroundColor = Theme.colors.inkBlack,
        borderColor = Theme.colors.borderGold,
        borderWidth = { top = 1 },
        alignItems = "center",
        children = {
            -- 表情按钮
            UI.Panel {
                width = 36,
                height = 36,
                borderRadius = Theme.radius.sm,
                backgroundColor = emojiPanelOpen_ and Theme.colors.gold or { 60, 55, 45, 200 },
                justifyContent = "center",
                alignItems = "center",
                cursor = "pointer",
                onClick = function()
                    emojiPanelOpen_ = not emojiPanelOpen_
                    local okRouter, Router = pcall(require, "ui_router")
                    if okRouter and Router.RebuildUI then Router.RebuildUI() end
                end,
                children = {
                    UI.Label {
                        text = "表情",
                        fontSize = 10,
                        fontColor = emojiPanelOpen_ and Theme.colors.btnPrimaryText or Theme.colors.textLight,
                    },
                },
            },
            -- 输入框
            UI.TextField {
                flexGrow = 1,
                placeholder = opts.placeholder or "输入消息...",
                fontSize = Theme.fontSize.body,
                value = currentText_,
                onChange = function(self, v)
                    currentText_ = v  -- 同步模块级缓存
                    if opts.onChangeText then
                        opts.onChangeText(v)
                    end
                end,
            },
            -- 发送按钮
            UI.Panel {
                width = 60,
                height = 36,
                borderRadius = Theme.radius.sm,
                backgroundColor = Theme.colors.gold,
                justifyContent = "center",
                alignItems = "center",
                cursor = "pointer",
                onClick = function(self)
                    local text = currentText_  -- 使用模块级缓存，始终最新
                    if text == "" then
                        Toast.Show("请输入消息内容")
                        return
                    end
                    if opts.onSend then
                        opts.onSend(text)
                    end
                    currentText_ = ""
                    emojiPanelOpen_ = false
                end,
                children = {
                    UI.Label {
                        text = "发送",
                        fontSize = Theme.fontSize.body,
                        fontWeight = "bold",
                        fontColor = Theme.colors.btnPrimaryText,
                    },
                },
            },
        },
    }

    return UI.Panel {
        width = "100%",
        children = children,
    }
end

return M
