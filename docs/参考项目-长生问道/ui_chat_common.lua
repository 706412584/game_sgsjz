-- ============================================================================
-- 《问道长生》聊天公共组件
-- 职责：头像组件、时间格式化、表情解析（后续 P2.1 补充）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local DataChat = require("data_chat")
local RT = require("rich_text")

local M = {}

-- ============================================================================
-- 头像路径解析
-- ============================================================================

--- 根据 sender 信息获取头像图片路径
---@param sender table { gender, avatarIndex }
---@return string
function M.GetAvatarPath(sender)
    local gender = sender and sender.gender or "男"
    local pool = Theme.avatars[gender] or Theme.avatars["男"]
    local idx = (sender and sender.avatarIndex) or 1
    return pool[math.max(1, math.min(idx, #pool))]
end

-- ============================================================================
-- 头像组件
-- ============================================================================

--- 构建可点击头像组件
---@param sender table  { userId, name, gender, realm, avatarIndex }
---@param size number   头像尺寸（像素）
---@param onClick? fun(sender: table)  点击回调
---@return table UI 组件
function M.BuildAvatar(sender, size, onClick)
    size = size or 32
    local avatarPath = M.GetAvatarPath(sender)

    return UI.Panel {
        width = size,
        height = size,
        borderRadius = size / 2,
        overflow = "hidden",
        backgroundImage = avatarPath,
        backgroundFit = "cover",
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = onClick and "pointer" or nil,
        onClick = onClick and function()
            onClick(sender)
        end or nil,
    }
end

-- ============================================================================
-- 时间格式化
-- ============================================================================

--- 将时间戳格式化为友好文本
---@param ts number unix timestamp
---@return string
function M.FormatTime(ts)
    if ts == 0 then return "" end
    local now = os.time()
    local diff = now - ts
    if diff < 60 then return "刚刚" end
    if diff < 3600 then return math.floor(diff / 60) .. "分钟前" end
    if diff < 86400 then return math.floor(diff / 3600) .. "小时前" end
    return math.floor(diff / 86400) .. "天前"
end

-- ============================================================================
-- 表情解析与富文本
-- ============================================================================

--- 解析消息文本中的 [表情名] 标记，拆分为 segments 数组
--- 解析消息中的 [表情名] 标记，委托 RT.Parse（parseEmoji 模式）
--- 每个 segment: { type = "text"|"emoji", value = string }
---@param text string
---@return table[] segments
function M.ParseEmoji(text)
    return RT.Parse(text, nil, { parseEmoji = true, emojiSet = DataChat.EMOJI_SET })
end

--- 构建带表情/颜色标签的聊天消息富文本行（inline 布局）
--- 委托 RT.Build，并传入表情图片/颜色表
---@param text string       消息文本
---@param fontSize number   字体大小
---@param textColor table   普通文本颜色
---@return table UI 组件
function M.BuildRichText(text, fontSize, textColor)
    return RT.Build(text, fontSize, textColor, {
        parseEmoji  = true,
        emojiSet    = DataChat.EMOJI_SET,
        emojiImages = DataChat.EMOJI_IMAGES,
        emojiColors = DataChat.EMOJI_COLORS,
        flexShrink  = 1,
    })
end

-- ============================================================================
-- 系统公告富文本（支持 <font>/<a>/<c=> 标签，委托 RT.Build）
-- ============================================================================

--- 解析公告富文本（<font color=#hex>/<a action="">/<c=name>），委托 RT.Parse
---@param text string
---@return table[] segments
function M.ParseRichText(text)
    return RT.Parse(text, nil, { parseEmoji = true, emojiSet = DataChat.EMOJI_SET })
end

--- 构建系统公告富文本行（支持彩色文字 / 可点击链接）
---@param text string              公告文本
---@param fontSize number          字体大小
---@param defaultColor table       默认文字颜色 {r,g,b,a}
---@param onLinkClick? fun(action: string, params: string)  链接点击回调
---@return table UI 组件
function M.BuildAnnounce(text, fontSize, defaultColor, onLinkClick)
    return RT.Build(text, fontSize, defaultColor, {
        parseEmoji  = true,
        emojiSet    = DataChat.EMOJI_SET,
        emojiImages = DataChat.EMOJI_IMAGES,
        emojiColors = DataChat.EMOJI_COLORS,
        onLink      = onLinkClick,
        flexShrink  = 1,
    })
end

return M
