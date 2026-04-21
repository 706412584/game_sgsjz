------------------------------------------------------------
-- ui/components.lua  —— 三国神将录 基础UI组件
-- SanButton / SanCard / HeroAvatar / ResourceBadge / NodeIcon / StarBar
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 1. SanButton  三国风格按钮（使用生成纹理）
------------------------------------------------------------
--- @param props { text, variant?, width?, height?, fontSize?, disabled?, onClick?, flexGrow?, paddingHorizontal?, borderRadius? }
---   variant: "primary"(翡翠绿纹理) | "danger"(红色纹理) | "gold"(金色纹理) | "secondary"(暗银纹理)
function M.SanButton(props)
    props = props or {}
    local variant = props.variant or "primary"

    -- 纹理和颜色映射
    local bgImg, txtColor, tintColor
    if variant == "primary" or variant == "danger" or variant == "gold" then
        bgImg    = "Textures/ui/btn_primary.png"
        txtColor = C.text
        if variant == "danger" then
            tintColor = { 220, 80, 80, 255 }
        elseif variant == "gold" then
            tintColor = { 240, 200, 100, 255 }
        end
    else -- secondary
        bgImg    = "Textures/ui/btn_secondary.png"
        txtColor = C.text
    end

    return UI.Button {
        text                    = props.text or "按钮",
        width                   = props.width,
        height                  = props.height or S.btnHeight,
        fontSize                = props.fontSize or S.btnFontSize,
        fontWeight              = "bold",
        textColor               = txtColor,
        backgroundImage         = bgImg,
        backgroundFit           = "sliced",
        backgroundSlice         = { top = 16, right = 16, bottom = 16, left = 16 },
        imageTint               = tintColor,
        backgroundColor         = { 0, 0, 0, 0 },
        hoverBackgroundColor    = { 255, 255, 255, 20 },
        pressedBackgroundColor  = { 0, 0, 0, 40 },
        borderRadius            = props.borderRadius or S.btnRadius,
        disabled                = props.disabled,
        flexGrow                = props.flexGrow,
        onClick                 = props.onClick,
        paddingHorizontal       = props.paddingHorizontal or 16,
        transition              = "all 0.15s easeOut",
    }
end

------------------------------------------------------------
-- 2. SanCard  三国风格卡片面板
------------------------------------------------------------
--- @param props { title?, width?, height?, padding?, children?, onClick? }
function M.SanCard(props)
    props = props or {}
    local children = {}

    -- 标题栏
    if props.title then
        children[#children + 1] = UI.Label {
            text = props.title,
            fontSize = Theme.fontSize.subtitle,
            fontColor = C.gold,
            fontWeight = "bold",
            marginBottom = 8,
        }
        children[#children + 1] = UI.Divider {
            color = C.divider,
            spacing = 4,
        }
    end

    -- 子内容
    if props.children then
        for _, child in ipairs(props.children) do
            children[#children + 1] = child
        end
    end

    return UI.Panel {
        width               = props.width or "100%",
        height              = props.height,
        backgroundColor     = C.panel,
        borderRadius        = S.cardRadius,
        borderColor         = C.border,
        borderWidth         = 1,
        padding             = props.padding or S.cardPadding,
        flexDirection       = "column",
        children            = children,
        onClick             = props.onClick,
        flexGrow            = props.flexGrow,
        flexShrink          = props.flexShrink,
        margin              = props.margin,
        marginBottom        = props.marginBottom,
    }
end

------------------------------------------------------------
-- 3. HeroAvatar  武将头像
------------------------------------------------------------
--- @param props { heroId, size?, quality?, level?, showLevel? }
function M.HeroAvatar(props)
    props = props or {}
    local size    = props.size or S.heroAvatarMd
    local quality = props.quality or 1
    local qColor  = Theme.QualityColor(quality)

    local children = {}

    -- 等级标签
    if props.showLevel and props.level then
        children[#children + 1] = UI.Label {
            text = "Lv." .. props.level,
            fontSize = 9,
            fontColor = C.text,
            backgroundColor = { 0, 0, 0, 160 },
            borderRadius = 4,
            paddingHorizontal = 3,
            paddingVertical = 1,
            position = "absolute",
            bottom = 2,
            left = 2,
        }
    end

    -- 头像图片路径
    local imgPath = props.heroId
        and ("Textures/heroes/hero_" .. props.heroId .. ".png")
        or nil

    return UI.Panel {
        width           = size,
        height          = size,
        borderRadius    = 6,
        borderColor     = qColor,
        borderWidth     = 2,
        overflow        = "hidden",
        backgroundImage = imgPath,
        backgroundFit   = "cover",
        backgroundColor = C.panelLight,
        children        = children,
        onClick         = props.onClick,
    }
end

------------------------------------------------------------
-- 4. ResourceBadge  资源数值展示（图标+数字）
------------------------------------------------------------
--- @param props { icon, value, color?, fontSize?, iconSize? }
function M.ResourceBadge(props)
    props = props or {}
    local iconSize = props.iconSize or S.hudIconSize

    return UI.Panel {
        flexDirection   = "row",
        alignItems      = "center",
        gap             = 4,
        height          = iconSize + 4,
        children = {
            UI.Panel {
                width           = iconSize,
                height          = iconSize,
                backgroundImage = props.icon,
                backgroundFit   = "contain",
            },
            UI.Label {
                text        = Theme.FormatNumber(props.value or 0),
                fontSize    = props.fontSize or Theme.fontSize.bodySmall,
                fontColor   = props.color or C.text,
            },
        },
    }
end

------------------------------------------------------------
-- 5. NodeIcon  地图节点图标
------------------------------------------------------------
--- @param props { nodeType, stars?, locked?, onClick? }
---   nodeType: "normal"|"elite"|"boss"|"event"|"treasure"
function M.NodeIcon(props)
    props = props or {}
    local nodeType = props.nodeType or "normal"
    local size     = S.nodeIconSize
    local locked   = props.locked
    local stars    = props.stars or 0

    -- 图标路径
    local iconPath = "Textures/icons/icon_node_" .. nodeType .. ".png"

    -- 星级文字
    local starLabel = nil
    if stars > 0 then
        starLabel = UI.Label {
            text = Theme.StarsText(stars),
            fontSize = 8,
            fontColor = C.gold,
            textAlign = "center",
            position = "absolute",
            bottom = -12,
            left = 0,
            width = size,
        }
    end

    return UI.Panel {
        width       = size,
        height      = size + 14,
        alignItems  = "center",
        children = {
            UI.Panel {
                width           = size,
                height          = size,
                backgroundImage = iconPath,
                backgroundFit   = "contain",
                opacity         = locked and 0.35 or 1.0,
                onClick         = (not locked) and props.onClick or nil,
                borderRadius    = 6,
            },
            starLabel,
        },
    }
end

------------------------------------------------------------
-- 6. StarBar  星级条（0-3星）
------------------------------------------------------------
--- @param props { stars, size? }
function M.StarBar(props)
    props = props or {}
    local stars = props.stars or 0
    local size  = props.size or 14

    local children = {}
    for i = 1, 3 do
        children[i] = UI.Label {
            text = i <= stars and "★" or "☆",
            fontSize = size,
            fontColor = i <= stars and C.gold or C.textDim,
        }
    end

    return UI.Panel {
        flexDirection = "row",
        gap = 1,
        children = children,
    }
end

------------------------------------------------------------
-- 7. SanDivider  风格化分割线
------------------------------------------------------------
function M.SanDivider(props)
    props = props or {}
    return UI.Divider {
        color   = props.color or C.divider,
        spacing = props.spacing or 8,
        label   = props.label,
    }
end

return M
