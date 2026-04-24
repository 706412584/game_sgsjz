-- ============================================================================
-- 《问道长生》统一富文本系统 rich_text.lua
-- 全项目共用，替换各模块的碎片化实现
--
-- 支持标签：
--   <c=name>文字</c>             命名颜色 (gold/red/green/blue/white/gray/yellow/purple/orange/cyan)
--   <c=#RRGGBB>文字</c>          Hex 颜色
--   <font color=#RRGGBB>文字</font>  传统语法（向后兼容，ui_chat_common.BuildAnnounce 使用）
--   <a action="xxx" params="yyy">文字</a>  可点击链接
--   [表情名]                     表情（仅 parseEmoji=true 时解析）
-- ============================================================================

local UI = require("urhox-libs/UI")
local M  = {}

-- ============================================================================
-- 命名颜色预设（可被外部读取：RT.TAG_COLORS）
-- ============================================================================
M.TAG_COLORS = {
    gold   = { 230, 195, 100, 255 },
    red    = { 200,  90,  90, 255 },
    green  = { 100, 180, 100, 255 },
    blue   = { 130, 180, 240, 255 },
    white  = { 255, 255, 255, 255 },
    gray   = { 100,  90,  75, 200 },
    yellow = { 240, 220, 100, 255 },
    purple = { 167, 139, 250, 255 },
    orange = { 249, 115,  22, 255 },
    cyan   = { 100, 220, 200, 255 },
}

-- ============================================================================
-- 内部工具
-- ============================================================================
local function ParseHex(hex)
    if not hex then return nil end
    hex = hex:gsub("^#", "")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not r then return nil end
    return { r, g, b, 255 }
end

local function ResolveColor(name)
    if not name then return nil end
    if name:sub(1, 1) == "#" then return ParseHex(name) end
    return M.TAG_COLORS[name]
end

-- ============================================================================
-- RT.HasTag — 快速检测是否含富文本标签（避免无谓重绘）
-- ============================================================================
---@param text string
---@return boolean
function M.HasTag(text)
    if not text or text == "" then return false end
    return text:find("<c=",   1, true) ~= nil
        or text:find("<font", 1, true) ~= nil
        or text:find("<a ",   1, true) ~= nil
end

-- ============================================================================
-- RT.Parse — 解析富文本，返回 segments 数组
--
-- segment 类型说明：
--   { type="text",    value="...",  color={r,g,b,a} }       普通文字
--   { type="colored", value="...",  color={r,g,b,a} }       带颜色文字
--   { type="link",    value="...",  action="...", params="..." }  可点击链接
--   { type="emoji",   value="emojiName" }                   表情（parseEmoji=true 时）
-- ============================================================================
---@param text string
---@param defaultColor? table  {r,g,b,a}，nil 时为白色
---@param opts? { parseEmoji?: boolean, emojiSet?: table }
---@return table[] segments
function M.Parse(text, defaultColor, opts)
    local segments = {}
    if not text or text == "" then return segments end
    defaultColor = defaultColor or { 255, 255, 255, 255 }
    opts = opts or {}
    local parseEmoji = opts.parseEmoji
    local emojiSet   = opts.emojiSet

    local pos = 1
    local len = #text

    while pos <= len do
        -- 查找各类标签起始位置，取最近的
        local cStart  = text:find("<c=",  pos, true)
        local fStart  = text:find("<font", pos, true)
        local aStart  = text:find("<a ",  pos, true)
        local emStart = parseEmoji and text:find("%[", pos) or nil

        local first, kind = len + 1, nil
        if cStart  and cStart  < first then first, kind = cStart,  "c"     end
        if fStart  and fStart  < first then first, kind = fStart,  "font"  end
        if aStart  and aStart  < first then first, kind = aStart,  "link"  end
        if emStart and emStart < first then first, kind = emStart, "emoji" end

        if not kind then
            -- 剩余全为普通文本
            local tail = text:sub(pos)
            if tail ~= "" then
                segments[#segments + 1] = { type = "text", value = tail, color = defaultColor }
            end
            break
        end

        -- 标签前的普通文本
        if first > pos then
            segments[#segments + 1] = { type = "text", value = text:sub(pos, first - 1), color = defaultColor }
        end

        -- ---- <c=name> 或 <c=#RRGGBB> ----
        if kind == "c" then
            local colorEnd = text:find(">", first + 3, true)
            if not colorEnd then
                segments[#segments + 1] = { type = "text", value = text:sub(first), color = defaultColor }
                break
            end
            local colorName = text:sub(first + 3, colorEnd - 1)
            local tagColor  = ResolveColor(colorName) or defaultColor
            local closeStart = text:find("</c>", colorEnd + 1, true)
            if not closeStart then
                local rest = text:sub(colorEnd + 1)
                if rest ~= "" then
                    segments[#segments + 1] = { type = "colored", value = rest, color = tagColor }
                end
                break
            end
            local inner = text:sub(colorEnd + 1, closeStart - 1)
            if inner ~= "" then
                segments[#segments + 1] = { type = "colored", value = inner, color = tagColor }
            end
            pos = closeStart + 4   -- 跳过 </c>

        -- ---- <font color=#hex>text</font>（兼容旧系统公告）----
        elseif kind == "font" then
            local _, colorEnd, colorAttr = text:find("<font%s+color=([^>]*)>", first)
            if not colorEnd then
                segments[#segments + 1] = { type = "text", value = text:sub(first), color = defaultColor }
                break
            end
            local tagColor  = ResolveColor(colorAttr) or defaultColor
            local closeStart, closeEnd = text:find("</font>", colorEnd + 1, true)
            if not closeStart then
                local rest = text:sub(colorEnd + 1)
                if rest ~= "" then
                    segments[#segments + 1] = { type = "colored", value = rest, color = tagColor }
                end
                break
            end
            local inner = text:sub(colorEnd + 1, closeStart - 1)
            if inner ~= "" then
                segments[#segments + 1] = { type = "colored", value = inner, color = tagColor }
            end
            pos = closeEnd + 1

        -- ---- <a action="..." params="...">text</a> ----
        elseif kind == "link" then
            -- action 在前
            local _, matchEnd, action, params, content =
                text:find('<a%s+action="([^"]*)"[^>]*params="([^"]*)"[^>]*>(.-)</a>', first)
            if not matchEnd then
                -- params 在前
                local _, me2, p2, a2, c2 =
                    text:find('<a%s+params="([^"]*)"[^>]*action="([^"]*)"[^>]*>(.-)</a>', first)
                matchEnd, params, action, content = me2, p2, a2, c2
            end
            if not matchEnd then
                segments[#segments + 1] = { type = "text", value = text:sub(first), color = defaultColor }
                break
            end
            segments[#segments + 1] = {
                type   = "link",
                value  = content or "",
                action = action  or "",
                params = params  or "",
            }
            pos = matchEnd + 1

        -- ---- [表情名] ----
        elseif kind == "emoji" then
            local s, e, emojiName = text:find("%[([^%]]+)%]", first)
            if not s then
                segments[#segments + 1] = { type = "text", value = text:sub(first), color = defaultColor }
                break
            end
            if emojiSet and emojiSet[emojiName] then
                segments[#segments + 1] = { type = "emoji", value = emojiName }
            else
                segments[#segments + 1] = { type = "text", value = text:sub(s, e), color = defaultColor }
            end
            pos = e + 1
        end
    end

    return segments
end

-- ============================================================================
-- RT.Build — 构建内联富文本 UI 行（flexRow + flexWrap）
-- ============================================================================
---@param text string
---@param fontSize number
---@param defaultColor table  {r,g,b,a}
---@param opts? {
--     parseEmoji?  boolean,
--     emojiSet?    table,    -- DataChat.EMOJI_SET
--     emojiImages? table,    -- DataChat.EMOJI_IMAGES
--     emojiColors? table,    -- DataChat.EMOJI_COLORS
--     onLink?      fun(action:string, params:string),
--     flexShrink?  number,
-- }
---@return table UI component
function M.Build(text, fontSize, defaultColor, opts)
    opts        = opts or {}
    local segs  = M.Parse(text, defaultColor, opts)
    local onLink = opts.onLink

    -- 快速路径：仅一段纯文本
    if #segs == 1 and segs[1].type == "text" then
        return UI.Label {
            text       = text,
            fontSize   = fontSize,
            color      = defaultColor,
            flexShrink = opts.flexShrink or 1,
        }
    end

    local emojiSize  = math.floor((fontSize or 14) * 1.4)
    local linkColor  = { 100, 180, 255, 255 }
    local children   = {}

    for _, seg in ipairs(segs) do
        if seg.type == "text" or seg.type == "colored" then
            children[#children + 1] = UI.Label {
                text       = seg.value,
                fontSize   = fontSize,
                color      = seg.color or defaultColor,
                flexShrink = 1,
            }

        elseif seg.type == "link" then
            children[#children + 1] = UI.Panel {
                flexDirection = "column",
                children = {
                    UI.Label {
                        text       = seg.value,
                        fontSize   = fontSize,
                        color      = linkColor,
                        cursor     = onLink and "pointer" or nil,
                        onClick    = onLink and function()
                            onLink(seg.action, seg.params)
                        end or nil,
                    },
                    -- 下划线装饰
                    UI.Panel { width = "100%", height = 1, backgroundColor = linkColor },
                },
            }

        elseif seg.type == "emoji" then
            local imgPath = opts.emojiImages and opts.emojiImages[seg.value]
            if imgPath then
                children[#children + 1] = UI.Panel {
                    width            = emojiSize,
                    height           = emojiSize,
                    backgroundImage  = imgPath,
                    backgroundFit    = "contain",
                }
            else
                children[#children + 1] = UI.Label {
                    text       = "[" .. seg.value .. "]",
                    fontSize   = fontSize,
                    fontWeight = "bold",
                    color      = (opts.emojiColors and opts.emojiColors[seg.value])
                                 or { 255, 210, 60, 255 },
                }
            end
        end
    end

    return UI.Panel {
        flexDirection = "row",
        flexWrap      = "wrap",
        flexShrink    = opts.flexShrink or 1,
        alignItems    = "center",
        children      = children,
    }
end

return M
