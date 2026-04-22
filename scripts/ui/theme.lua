------------------------------------------------------------
-- ui/theme.lua  —— 三国神将录 主题色 & UI 常量
-- 夜蓝底 + 金色标题 + 翡翠绿按钮 + 7级品质色
------------------------------------------------------------
local UI = require("urhox-libs/UI")

local M = {}

------------------------------------------------------------
-- 1. 色板
------------------------------------------------------------
M.colors = {
    -- 主色调
    bg          = { 26,  33,  48,  255 },   -- #1A2130 夜蓝底
    panel       = { 42,  51,  72,  255 },   -- #2A3348 深面板
    panelLight  = { 55,  65,  90,  255 },   -- 浅面板（悬停/子面板）
    jade        = { 79,  184, 159, 255 },   -- #4FB89F 翡翠绿（主按钮）
    jadeHover   = { 65,  160, 138, 255 },   -- 翡翠绿悬停
    jadePressed = { 52,  140, 120, 255 },   -- 翡翠绿按下
    gold        = { 229, 168, 74,  255 },   -- #E5A84A 金橙（标题/强调）
    goldDim     = { 190, 140, 60,  255 },   -- 暗金
    red         = { 217, 79,  79,  255 },   -- #D94F4F 血红（危险/HP）
    redDim      = { 180, 60,  60,  255 },

    -- 文字
    text        = { 220, 225, 235, 255 },   -- 主文字
    textDim     = { 140, 150, 170, 255 },   -- 次文字
    textGold    = { 229, 168, 74,  255 },   -- 金色文字

    -- 边框 / 分割线
    border      = { 70,  80,  105, 255 },
    borderLight = { 90,  100, 125, 255 },
    divider     = { 60,  70,  95,  180 },

    -- 遮罩
    overlay     = { 0,   0,   0,   160 },

    -- 功能色
    hp          = { 76,  175, 80,  255 },   -- 血量绿
    mp          = { 33,  150, 243, 255 },   -- 蓝量蓝
    exp         = { 156, 39,  176, 255 },   -- 经验紫
    morale      = { 255, 193, 7,   255 },   -- 士气黄
    stamina     = { 76,  175, 80,  255 },   -- 体力绿

    -- 阵营 / 势力（预留）
    faction_wei = { 33,  150, 243, 255 },   -- 魏-蓝
    faction_shu = { 76,  175, 80,  255 },   -- 蜀-绿
    faction_wu  = { 255, 87,  34,  255 },   -- 吴-橙
    faction_qun = { 156, 39,  176, 255 },   -- 群-紫
}

------------------------------------------------------------
-- 2. 品质色 (白/绿/蓝/紫/橙/红/金)
------------------------------------------------------------
M.qualityColors = {
    [1] = { 180, 180, 180, 255 },   -- 白
    [2] = { 76,  175, 80,  255 },   -- 绿
    [3] = { 33,  150, 243, 255 },   -- 蓝
    [4] = { 156, 39,  176, 255 },   -- 紫
    [5] = { 255, 152, 0,   255 },   -- 橙
    [6] = { 244, 67,  54,  255 },   -- 红
    [7] = { 255, 215, 0,   255 },   -- 金
}

M.qualityNames = { "白", "绿", "蓝", "紫", "橙", "红", "金" }

------------------------------------------------------------
-- 3. 星级色
------------------------------------------------------------
M.starColors = {
    [0] = { 100, 100, 100, 255 },   -- 未获得
    [1] = { 180, 180, 180, 255 },   -- ★
    [2] = { 229, 168, 74,  255 },   -- ★★
    [3] = { 255, 215, 0,   255 },   -- ★★★
}

------------------------------------------------------------
-- 4. 尺寸 & 间距常量（基准像素，配合 UI.Scale.DEFAULT）
------------------------------------------------------------
M.sizes = {
    -- HUD
    hudHeight       = 48,
    hudIconSize     = 28,
    hudPadH         = 12,

    -- Tab 底栏
    tabBarHeight    = 56,
    tabIconSize     = 24,

    -- 弹窗
    modalMaxWidth   = 480,
    modalPadding    = 20,
    modalRadius     = 12,
    modalTitleSize  = 18,

    -- 卡片
    cardRadius      = 8,
    cardPadding     = 12,

    -- 按钮（标准）
    btnHeight       = 44,
    btnRadius       = 8,
    btnFontSize     = 15,

    -- 按钮（紧凑，列表内/行内操作）
    btnSmHeight     = 40,
    btnSmFontSize   = 12,

    -- 头像
    heroAvatarSm    = 48,
    heroAvatarMd    = 64,
    heroAvatarLg    = 96,

    -- 节点
    nodeIconSize    = 40,
}

------------------------------------------------------------
-- 5. 字号
------------------------------------------------------------
M.fontSize = {
    display     = 24,
    headline    = 18,
    title       = 16,
    subtitle    = 14,
    body        = 13,
    bodySmall   = 12,
    caption     = 10,
}

------------------------------------------------------------
-- 6. ExtendTheme 生成引擎兼容主题对象
------------------------------------------------------------
M.uiTheme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
    colors = {
        primary         = M.colors.jade,
        secondary       = M.colors.gold,
        success         = M.colors.hp,
        error           = M.colors.red,
        warning         = M.colors.gold,
        background      = M.colors.bg,
        surface         = M.colors.panel,
        text            = M.colors.text,
        textSecondary   = M.colors.textDim,
        border          = M.colors.border,
    },
})

------------------------------------------------------------
-- 7. 便捷方法
------------------------------------------------------------

--- 返回品质色 {r,g,b,a}
---@param quality integer 1-7 (Theme 内部索引)
function M.QualityColor(quality)
    return M.qualityColors[quality] or M.qualityColors[1]
end

--- 返回英雄品质色 (自动处理 data_heroes 品质偏移)
--- data_heroes quality: 3=紫,4=橙,5=红,6=金 → theme index +1
---@param heroQuality integer data_heroes 中的 quality 值
function M.HeroQualityColor(heroQuality)
    return M.qualityColors[(heroQuality or 0) + 1] or M.qualityColors[1]
end

--- 返回星级字符串 "★★★"
---@param stars integer 0-3
function M.StarsText(stars)
    if stars <= 0 then return "☆☆☆" end
    local s = ""
    for i = 1, stars do s = s .. "★" end
    for i = stars + 1, 3 do s = s .. "☆" end
    return s
end

--- 返回星级对应颜色
---@param star integer 0-6
function M.StarColor(star)
    if star <= 1 then return M.starColors[1] end
    if star <= 3 then return M.starColors[2] end
    return M.starColors[3]
end

--- 格式化大数字: 12345 -> "1.2万"
---@param n number
function M.FormatNumber(n)
    if n >= 100000000 then
        return string.format("%.1f亿", n / 100000000)
    elseif n >= 10000 then
        return string.format("%.1f万", n / 10000)
    else
        return tostring(math.floor(n))
    end
end

return M
