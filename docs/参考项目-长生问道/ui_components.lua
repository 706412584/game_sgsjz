-- ============================================================================
-- 《问道长生》公共 UI 组件
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local NVG = require("nvg_manager")
local Toast = require("ui_toast")
local DataItems = require("data_items")
local RT = require("rich_text")

local Comp = {}

-- ============================================================================
-- 颜色标签解析（委托 rich_text.lua 统一解析器）
-- 保持接口不变：返回 { {text, color}, ... }
-- ============================================================================

--- 解析 <c=color>text</c> / <c=#hex>text</c> 标签，返回 segments 数组
---@param text string
---@param defaultColor table
---@return table[] segments { {text, color}, ... }
function Comp.ParseColorTags(text, defaultColor)
    local rawSegs = RT.Parse(text, defaultColor)
    -- 转换为旧格式 { text, color }（兼容现有调用方）
    local out = {}
    for _, seg in ipairs(rawSegs) do
        out[#out + 1] = { text = seg.value, fontColor = seg.color or defaultColor }
    end
    return out
end

--- 判断文本是否包含颜色标签
local function HasColorTag(text)
    return RT.HasTag(text)
end

--- 构建富文本行（支持 <c=color> 标签的横排 Label）
---@param text string
---@param fontSize number
---@param defaultColor table
---@return table UI element
function Comp.BuildRichLabel(text, fontSize, defaultColor)
    if not HasColorTag(text) then
        return UI.Label {
            text = text,
            fontSize = fontSize,
            fontColor = defaultColor,
            width = "100%",
            paddingVertical = 2,
        }
    end
    local segments = Comp.ParseColorTags(text, defaultColor)
    local children = {}
    for _, seg in ipairs(segments) do
        children[#children + 1] = UI.Label {
            text = seg.text,
            fontSize = fontSize,
            fontColor = seg.fontColor,
        }
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        paddingVertical = 2,
        children = children,
    }
end

-- ============================================================================
-- 稀有度/品质颜色（委托 DataItems，兼容新旧 key）
-- ============================================================================
function Comp.GetRarityColor(rarity)
    return DataItems.GetQualityColor(rarity) or Theme.colors.textPrimary
end

-- ============================================================================
-- 底部导航栏（5个页签）- 带粒子动画与缩放反馈
-- activeTab: "home"|"bag"|"map"|"pet"|"more"
-- onNavigate: function(tabKey)
-- ============================================================================

-- ---- 导航栏粒子系统（通过 nvg_manager 调度） ----
local navParticles = {}          -- { [tabKey] = { particles={}, timer=0 } }
local NAV_PARTICLE_COUNT = 12
local navParticleSubscribed = false
local navActiveTab_ = ""         -- 当前激活 tab（供 NanoVG 渲染定位）
local navTabPositions_ = {}      -- { [tabKey] = { cx, cy } } 各 tab 中心（逻辑坐标）
-- 缩放动画状态
local navScaleAnim_ = {}         -- { [tabKey] = { scale, target, vel } }

local function CreateNavParticle(cx, cy)
    local p = {}
    local angle = math.random() * math.pi * 2
    local radius = math.random() * 28 + 12   -- 12~40
    p.x = cx + math.cos(angle) * radius
    p.y = cy + math.sin(angle) * radius
    p.size = math.random() * 2.0 + 0.8
    p.alpha = math.random() * 0.5 + 0.2
    p.alphaSpeed = (math.random() - 0.5) * 0.6
    p.lifetime = math.random() * 1.5 + 0.8
    p.age = 0
    -- 向中心聚拢
    local dx = cx - p.x
    local dy = cy - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dist = 1 end
    local spd = math.random() * 15 + 10
    p.vx = dx / dist * spd
    p.vy = dy / dist * spd
    -- 绿色系粒子
    local v = math.random(1, 3)
    if v == 1 then
        p.r, p.g, p.b = 80, 220, 130
    elseif v == 2 then
        p.r, p.g, p.b = 120, 255, 170
    else
        p.r, p.g, p.b = 200, 255, 220
    end
    return p
end

local function InitNavParticlesForTab(tabKey, cx, cy)
    if navParticles[tabKey] then return end
    local data = { particles = {}, timer = 0 }
    for i = 1, NAV_PARTICLE_COUNT do
        data.particles[i] = CreateNavParticle(cx, cy)
        data.particles[i].age = math.random() * data.particles[i].lifetime * 0.5
    end
    navParticles[tabKey] = data
end

local function UpdateNavParticles(dt)
    for tabKey, data in pairs(navParticles) do
        local pos = navTabPositions_[tabKey]
        if not pos then goto nextTab end
        local cx, cy = pos.cx, pos.cy
        for i, p in ipairs(data.particles) do
            p.age = p.age + dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.alpha = p.alpha + p.alphaSpeed * dt
            if p.alpha > 0.7 then p.alpha = 0.7; p.alphaSpeed = -math.abs(p.alphaSpeed) end
            if p.alpha < 0.05 then p.alpha = 0.05; p.alphaSpeed = math.abs(p.alphaSpeed) end
            local dx = p.x - cx
            local dy = p.y - cy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < 8 then p.alpha = p.alpha * (dist / 8) end
            if p.age >= p.lifetime or dist < 4 then
                data.particles[i] = CreateNavParticle(cx, cy)
            end
        end
        ::nextTab::
    end
    -- 缩放弹簧动画
    for tabKey, anim in pairs(navScaleAnim_) do
        local diff = anim.target - anim.scale
        anim.vel = anim.vel + diff * 120 * dt   -- 弹簧刚度
        anim.vel = anim.vel * (1 - 6 * dt)      -- 阻尼
        anim.scale = anim.scale + anim.vel * dt
    end
end

-- 渲染导航粒子（ctx 由 nvg_manager 传入）
local function RenderNavParticles(ctx)
    for tabKey, data in pairs(navParticles) do
        if tabKey ~= navActiveTab_ then goto skip end
        for _, p in ipairs(data.particles) do
            local fadeAlpha = p.alpha
            local lr = p.age / p.lifetime
            if lr < 0.2 then fadeAlpha = fadeAlpha * (lr / 0.2) end
            if lr > 0.7 then fadeAlpha = fadeAlpha * (1 - (lr - 0.7) / 0.3) end
            local a = math.floor(fadeAlpha * 255)
            if a < 2 then goto cont end
            local glow = p.size * 2.5
            local paint = nvgRadialGradient(ctx,
                p.x, p.y, p.size * 0.2, glow,
                nvgRGBA(p.r, p.g, p.b, math.floor(a * 0.4)),
                nvgRGBA(p.r, p.g, p.b, 0))
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, glow)
            nvgFillPaint(ctx, paint)
            nvgFill(ctx)
            nvgBeginPath(ctx)
            nvgCircle(ctx, p.x, p.y, p.size * 0.4)
            nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, a))
            nvgFill(ctx)
            ::cont::
        end
        ::skip::
    end
end

-- 启停导航粒子（通过 nvg_manager）
function Comp.StartNavParticles()
    if navParticleSubscribed then return end
    navParticleSubscribed = true
    NVG.Register("nav", RenderNavParticles, UpdateNavParticles)
end

function Comp.StopNavParticles()
    if not navParticleSubscribed then return end
    navParticleSubscribed = false
    NVG.Unregister("nav")
    navParticles = {}
end

function Comp.SetNavActiveTab(tabKey)
    navActiveTab_ = tabKey
end

-- ---- 构建导航栏 ----
function Comp.BuildBottomNav(activeTab, onNavigate)
    navActiveTab_ = activeTab

    local RedDot = require("ui_red_dot")
    local navDotKeys = {
        home = RedDot.KEYS.NAV_HOME,
        more = RedDot.KEYS.NAV_MORE,
    }
    local tabs = {
        { key = "home",  label = "角色",  icon = Theme.images.iconHome },
        { key = "bag",   label = "储物",  icon = Theme.images.iconBag },
        { key = "map",   label = "游历",  icon = Theme.images.iconWorldMap },
        { key = "sect",  label = "宗门",  icon = Theme.images.iconSect },
        { key = "social", label = "社交", icon = Theme.images.iconChat },
        { key = "more",  label = "更多",  icon = Theme.images.iconMore },
    }

    -- 计算各 tab 中心位置（逻辑坐标，假设等分屏幕宽度）
    local dpr = graphics:GetDPR()
    local scrW = graphics:GetWidth() / dpr
    local scrH = graphics:GetHeight() / dpr
    local tabW = scrW / #tabs
    for i, tab in ipairs(tabs) do
        local cx = tabW * (i - 0.5)
        local cy = scrH - Theme.bottomNavHeight * 0.5
        navTabPositions_[tab.key] = { cx = cx, cy = cy }
        if tab.key == activeTab then
            InitNavParticlesForTab(tab.key, cx, cy)
            if not navScaleAnim_[tab.key] then
                navScaleAnim_[tab.key] = { scale = 0.8, target = 1.0, vel = 2.0 }
            else
                navScaleAnim_[tab.key].target = 1.0
            end
        end
    end

    local tabChildren = {}
    for i, tab in ipairs(tabs) do
        local isActive = (tab.key == activeTab)
        -- 图标尺寸：选中 36，未选中 32
        local iconSize = isActive and 36 or 32
        -- 字体：选中 14，未选中 12
        local fontSize = isActive and 14 or 12

        local tabPanel = UI.Panel {
            flexGrow = 1,
            height = Theme.bottomNavHeight,
            justifyContent = "center",
            alignItems = "center",
            gap = 4,
            cursor = "pointer",
            onClick = function(self)
                if onNavigate then
                    -- 触发缩放弹簧动画
                    navScaleAnim_[tab.key] = { scale = 1.2, target = 1.0, vel = -1.0 }
                    -- 重置旧 tab 粒子
                    if navActiveTab_ ~= tab.key then
                        navParticles[navActiveTab_] = nil
                    end
                    navActiveTab_ = tab.key
                    local pos = navTabPositions_[tab.key]
                    if pos then
                        navParticles[tab.key] = nil  -- 重新创建
                        InitNavParticlesForTab(tab.key, pos.cx, pos.cy)
                    end
                    onNavigate(tab.key)
                end
            end,
            children = {
                -- 图标
                UI.Panel {
                    width = iconSize,
                    height = iconSize,
                    backgroundImage = tab.icon,
                    backgroundFit = "contain",
                    imageTint = isActive and Theme.colors.navActive or { 160, 155, 140, 180 },
                },
                -- 文字
                UI.Label {
                    text = tab.label,
                    fontSize = fontSize,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.navActive or Theme.colors.textLight,
                },
                -- 选中指示点
                isActive and UI.Panel {
                    width = 4,
                    height = 4,
                    borderRadius = 2,
                    backgroundColor = Theme.colors.navActive,
                    marginTop = 2,
                } or nil,
            },
        }
        -- 红点冒泡包装（非当前 tab 才显示红点）
        local dotKey = navDotKeys[tab.key]
        if dotKey and not isActive then
            tabChildren[i] = Comp.WithRedDot(tabPanel, dotKey, { size = 8, offsetX = -6, offsetY = 4 })
        else
            tabChildren[i] = tabPanel
        end
    end

    return UI.Panel {
        width = "100%",
        height = Theme.bottomNavHeight,
        backgroundColor = Theme.colors.inkBlack,
        borderColor = Theme.colors.borderGold,
        borderWidth = { top = 1 },
        flexDirection = "row",
        children = tabChildren,
    }
end

-- ============================================================================
-- 顶部状态栏
-- data: player 表 { name, gender, avatarIndex, realmName, spiritStone, lingStone, lifespan, lifespanMax, gameYear }
-- ============================================================================
function Comp.BuildTopBar(data)
    -- 头像路径
    local avatarIdx = data.avatarIndex or 1
    local avatarList = Theme.avatars[data.gender] or Theme.avatars["男"]
    local avatarImg = avatarList[avatarIdx] or avatarList[1]

    -- 游戏纪年
    local yearText = "太初" .. tostring(data.gameYear or 1) .. "年"

    -- 寿元
    local lifespanText = tostring(data.lifespan or 0) .. "/" .. tostring(data.lifespanMax or 100)

    -- 标签背景样式：深灰半透明圆角小底
    local tagBg = { 50, 42, 35, 200 }
    local tagRadius = 6
    local tagPadH = 8   -- 水平内边距
    local tagPadV = 3   -- 垂直内边距

    -- 外层栏：贴边全宽
    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.inkBlack,
        borderColor = Theme.colors.borderGold,
        borderWidth = { bottom = 1 },
        -- 内层容器：给文字留边距
        children = {
            UI.Panel {
                width = "100%",
                marginTop = 15,
                paddingLeft = 15,
                paddingRight = 15,
                paddingBottom = 8,
                flexDirection = "row",
                gap = 10,
                alignItems = "center",
                children = {
                    -- 左侧：圆形头像 + 边框
                    UI.Panel {
                        width = 62,
                        height = 62,
                        children = {
                            -- 头像底层（圆形裁切）
                            UI.Panel {
                                position = "absolute",
                                top = 5, left = 5,
                                width = 52,
                                height = 52,
                                borderRadius = 26,
                                overflow = "hidden",
                                backgroundColor = { 45, 36, 28, 255 },
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        height = "100%",
                                        backgroundImage = avatarImg,
                                        backgroundFit = "cover",
                                    },
                                },
                            },
                            -- 头像边框（叠加在头像上方）
                            UI.Panel {
                                position = "absolute",
                                top = 0, left = 0,
                                width = 62,
                                height = 62,
                                backgroundImage = Theme.images.avatarFrame,
                                backgroundFit = "contain",
                            },
                        },
                    },

                    -- 中间：名字 + 标签行
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        gap = 5,
                        children = {
                            -- 名字（无背景）
                            UI.Label {
                                text = data.name,
                                fontSize = Theme.fontSize.subtitle,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            -- 境界 + 寿元 标签行
                            UI.Panel {
                                flexDirection = "row",
                                gap = 6,
                                flexWrap = "wrap",
                                children = {
                                    -- 境界标签
                                    UI.Panel {
                                        backgroundColor = tagBg,
                                        borderRadius = tagRadius,
                                        padding = { tagPadV, tagPadH },
                                        children = {
                                            UI.Label {
                                                text = data.realmName,
                                                fontSize = Theme.fontSize.tiny,
                                                fontColor = Theme.colors.textGold,
                                            },
                                        },
                                    },
                                    -- 寿元标签
                                    UI.Panel {
                                        flexDirection = "row",
                                        gap = 3,
                                        alignItems = "center",
                                        backgroundColor = tagBg,
                                        borderRadius = tagRadius,
                                        padding = { tagPadV, tagPadH },
                                        children = {
                                            UI.Label {
                                                text = "寿",
                                                fontSize = Theme.fontSize.tiny,
                                                fontColor = Theme.colors.textLight,
                                            },
                                            UI.Label {
                                                text = lifespanText,
                                                fontSize = Theme.fontSize.tiny,
                                                fontColor = Theme.colors.textLight,
                                            },
                                        },
                                    },
                                    -- 纪年标签
                                    UI.Panel {
                                        backgroundColor = tagBg,
                                        borderRadius = tagRadius,
                                        padding = { tagPadV, tagPadH },
                                        children = {
                                            UI.Label {
                                                text = yearText,
                                                fontSize = Theme.fontSize.tiny,
                                                fontColor = Theme.colors.accent,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- 右侧：货币纵向
                    UI.Panel {
                        alignItems = "flex-end",
                        gap = 5,
                        children = {
                            -- 仙石标签
                            UI.Panel {
                                flexDirection = "row",
                                gap = 4,
                                alignItems = "center",
                                backgroundColor = tagBg,
                                borderRadius = tagRadius,
                                padding = { tagPadV, tagPadH },
                                children = {
                                    UI.Label {
                                        text = "仙石",
                                        fontSize = Theme.fontSize.tiny,
                                        fontColor = { 140, 125, 105, 255 },
                                    },
                                    UI.Label {
                                        text = tostring(data.spiritStone or 0),
                                        fontSize = Theme.fontSize.small,
                                        fontWeight = "bold",
                                        fontColor = Theme.colors.gold,
                                    },
                                },
                            },
                            -- 灵石标签
                            UI.Panel {
                                flexDirection = "row",
                                gap = 4,
                                alignItems = "center",
                                backgroundColor = tagBg,
                                borderRadius = tagRadius,
                                padding = { tagPadV, tagPadH },
                                children = {
                                    UI.Label {
                                        text = "灵石",
                                        fontSize = Theme.fontSize.tiny,
                                        fontColor = { 140, 125, 105, 255 },
                                    },
                                    UI.Label {
                                        text = tostring(data.lingStone or 0),
                                        fontSize = Theme.fontSize.small,
                                        fontWeight = "bold",
                                        fontColor = Theme.colors.accent,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 墨风主按钮（金色底、黑字）
-- text: 按钮文字
-- onClick: 回调
-- opts: 可选表 { disabled, width, fontSize }
-- ============================================================================
function Comp.BuildInkButton(text, onClick, opts)
    opts = opts or {}
    local disabled = opts.disabled or false
    local btnWidth = opts.width or "80%"
    local btnFlex = opts.flex
    local fs = opts.fontSize or Theme.fontSize.subtitle

    local bgColor = disabled and { 100, 90, 70, 200 } or Theme.colors.gold
    local txtColor = disabled and Theme.colors.textSecondary or (opts.fontColor or Theme.colors.btnPrimaryText)

    return UI.Panel {
        width = btnFlex and nil or btnWidth,
        flex = btnFlex,
        height = 44,
        borderRadius = Theme.radius.md,
        backgroundColor = bgColor,
        justifyContent = "center",
        alignItems = "center",
        alignSelf = "center",
        borderColor = Theme.colors.goldDark,
        borderWidth = 1,
        cursor = disabled and "default" or "pointer",
        onClick = function(self)
            if not disabled and onClick then onClick() end
        end,
        children = {
            UI.Label {
                text = text,
                fontSize = fs,
                fontWeight = "bold",
                fontColor = txtColor,
            },
        },
    }
end

-- ============================================================================
-- 墨风次要按钮（透明底、金色边框、金字）
-- ============================================================================
function Comp.BuildSecondaryButton(text, onClick, opts)
    opts = opts or {}
    local btnWidth = opts.width or "80%"
    local btnFlex = opts.flex
    local fs = opts.fontSize or Theme.fontSize.body

    return UI.Panel {
        width = btnFlex and nil or btnWidth,
        flex = btnFlex,
        height = 40,
        borderRadius = Theme.radius.md,
        backgroundColor = { 40, 35, 30, 180 },
        justifyContent = "center",
        alignItems = "center",
        alignSelf = "center",
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            if onClick then onClick() end
        end,
        children = {
            UI.Label {
                text = text,
                fontSize = fs,
                fontColor = Theme.colors.gold,
            },
        },
    }
end

-- ============================================================================
-- 小型文字按钮（无边框、金色文字）
-- ============================================================================
function Comp.BuildTextButton(text, onClick, opts)
    opts = opts or {}
    local fs = opts.fontSize or Theme.fontSize.body
    local color = opts.fontColor or Theme.colors.gold

    return UI.Panel {
        paddingHorizontal = 8,
        paddingVertical = 4,
        cursor = "pointer",
        onClick = function(self)
            if onClick then onClick() end
        end,
        children = {
            UI.Label {
                text = text,
                fontSize = fs,
                fontColor = color,
            },
        },
    }
end

-- ============================================================================
-- 章节标题（带左侧竖线装饰）
-- ============================================================================
function Comp.BuildSectionTitle(text, opts)
    opts = opts or {}
    local fs = opts.fontSize or Theme.fontSize.heading
    local color = opts.fontColor or Theme.colors.textGold

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        paddingVertical = 4,
        children = {
            -- 竖线装饰
            UI.Panel {
                width = 3,
                height = fs + 4,
                borderRadius = 1,
                backgroundColor = Theme.colors.gold,
            },
            UI.Label {
                text = text,
                fontSize = fs,
                fontWeight = "bold",
                fontColor = color,
            },
        },
    }
end

-- ============================================================================
-- 卡片面板（深色带金色边框的容器）
-- title: 可选标题
-- children: 子元素
-- opts: { padding, gap }
-- ============================================================================
function Comp.BuildCardPanel(title, children, opts)
    opts = opts or {}
    local cardPadding = opts.padding or Theme.spacing.md
    local cardGap = opts.gap or Theme.spacing.sm

    local cardChildren = {}
    if title then
        cardChildren[#cardChildren + 1] = UI.Label {
            text = title,
            fontSize = Theme.fontSize.subtitle,
            fontWeight = "bold",
            fontColor = Theme.colors.textGold,
            marginBottom = Theme.spacing.sm,
        }
        cardChildren[#cardChildren + 1] = UI.Divider {
            orientation = "horizontal",
            thickness = 1,
            fontColor = Theme.colors.divider,
            spacing = 4,
        }
    end

    if children then
        for _, child in ipairs(children) do
            cardChildren[#cardChildren + 1] = child
        end
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = opts.borderColor or Theme.colors.borderGold,
        borderWidth = opts.borderWidth or 1,
        padding = cardPadding,
        gap = cardGap,
        children = cardChildren,
    }
end

-- ============================================================================
-- 日志面板（滚动日志列表）
-- lines: { "日志文字1", "日志文字2", ... }
-- opts: { height, maxLines }
-- ============================================================================
function Comp.BuildLogPanel(lines, opts)
    opts = opts or {}
    local panelHeight = opts.height or 200

    local logChildren = {}
    if opts.autoScrollBottom then
        -- 倒序显示：最新日志在最上面，无需手动滚动即可看到
        for i = #lines, 1, -1 do
            logChildren[#logChildren + 1] = Comp.BuildRichLabel(lines[i], Theme.fontSize.small, Theme.colors.textLight)
        end
    else
        for i, line in ipairs(lines) do
            logChildren[i] = Comp.BuildRichLabel(line, Theme.fontSize.small, Theme.colors.textLight)
        end
    end

    return UI.Panel {
        width = "100%",
        height = panelHeight,
        backgroundColor = { 25, 22, 18, 220 },
        borderRadius = Theme.radius.sm,
        borderColor = Theme.colors.border,
        borderWidth = 1,
        padding = Theme.spacing.sm,
        children = {
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                scrollMultiplier = Theme.scrollSensitivity,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 2,
                        children = logChildren,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 修为进度条（金色）
-- current: 当前修为
-- max: 最大修为
-- ============================================================================
function Comp.BuildCultivationBar(current, max)
    local pct = current / max

    return UI.Panel {
        width = "100%",
        gap = 4,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = "修为",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = current .. " / " .. max,
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textLight,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                height = 10,
                borderRadius = 5,
                backgroundColor = { 50, 45, 35, 255 },
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 5,
                        backgroundColor = Theme.colors.gold,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 属性行（标签: 值）
-- label: 属性名
-- value: 属性值
-- opts: { labelColor, valueColor }
-- ============================================================================
function Comp.BuildStatRow(label, value, opts)
    opts = opts or {}
    local labelColor = opts.labelColor or Theme.colors.textLight
    local valueColor = opts.valueColor or Theme.colors.textLight

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingVertical = 2,
        children = {
            UI.Label {
                text = label,
                fontSize = Theme.fontSize.body,
                fontColor = labelColor,
            },
            UI.Label {
                text = tostring(value),
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = valueColor,
            },
        },
    }
end

-- ============================================================================
-- 水墨分割线
-- ============================================================================
function Comp.BuildInkDivider()
    return UI.Divider {
        orientation = "horizontal",
        thickness = 1,
        fontColor = Theme.colors.divider,
        spacing = 6,
    }
end

-- ============================================================================
-- 聊天动态框（悬浮在底部导航上方，显示实时聊天消息）
-- onOpenChat: 点击聊天按钮的回调
-- ============================================================================
function Comp.BuildChatTicker(onOpenChat)
    -- 懒触发 ChatJoin（首次渲染时发送）
    local okChat, Chat = pcall(require, "ui_chat")
    if okChat and Chat.EnsureJoined then
        Chat.EnsureJoined()
    end

    -- 从 ui_chat 获取最近 3 条世界消息
    local msgs = (okChat and Chat.GetRecentMessages) and Chat.GetRecentMessages(3) or {}
    local showCount = #msgs

    local msgLines = {}
    if showCount == 0 then
        msgLines[1] = UI.Label {
            text = "暂无聊天消息",
            fontSize = 10,
            fontColor = Theme.colors.textSecondary,
            paddingVertical = 4,
        }
    else
        for i = 1, showCount do
            local msg = msgs[i]
            local content = msg.text or ""
            if content == "" then content = "..." end
            local senderName = msg.senderName or "???"
            msgLines[i] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                gap = 4,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "[世界]",
                        fontSize = 9,
                        fontColor = { 180, 160, 100, 200 },
                    },
                    UI.Label {
                        text = senderName,
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = content,
                        fontSize = 10,
                        fontColor = Theme.colors.textLight,
                        flexShrink = 1,
                    },
                },
            }
        end
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 25, 22, 18, 230 },
        borderColor = Theme.colors.border,
        borderWidth = { top = 1 },
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                children = {
                    -- 消息区域（左侧，占满剩余宽度）
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        padding = { 4, 8 },
                        gap = 1,
                        overflow = "hidden",
                        children = msgLines,
                    },
                    -- 聊天按钮（右上角）
                    UI.Panel {
                        width = 44,
                        alignSelf = "flex-start",
                        height = "100%",
                        justifyContent = "center",
                        alignItems = "center",
                        backgroundColor = Theme.colors.gold,
                        cursor = "pointer",
                        onClick = function(self)
                            if onOpenChat then onOpenChat() end
                        end,
                        children = {
                            UI.Panel {
                                width = 22,
                                height = 22,
                                backgroundImage = Theme.images.iconChat,
                                backgroundFit = "contain",
                                imageTint = Theme.colors.inkBlack,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 标准页面容器（带顶栏、聊天动态框和底栏）
-- activeTab: 底部导航选中项
-- playerData: 玩家数据
-- contentChildren: 中间内容子元素
-- onNavigate: 导航回调
-- ============================================================================
-- opts: 可选 { bgImage = "xxx.png" }
function Comp.BuildPageShell(activeTab, playerData, contentChildren, onNavigate, opts)
    local Router = require("ui_router")
    opts = opts or {}

    -- 自动启动导航栏粒子
    Comp.StartNavParticles()

    -- 背景图映射（根据 tab 自动选择）
    local bgMap = {
        home    = Theme.images.bgHome,
        alchemy = Theme.images.bgAlchemy,
        bag     = Theme.images.bgBag,
        sect    = Theme.images.bgSect,
        map     = Theme.images.bgWorldMap,
        explore = Theme.images.bgExplore,
        pet     = Theme.images.bgExplore,
        social  = Theme.images.bgHome,
        more    = Theme.images.bgHome,
        chat    = Theme.images.bgChat,
    }
    local bgImage = opts.bgImage or bgMap[activeTab]

    local rootProps = {
        width = "100%",
        height = "100%",
    }
    if bgImage then
        rootProps.backgroundImage = bgImage
        rootProps.backgroundFit = "cover"
    else
        rootProps.backgroundColor = Theme.colors.bgParchment
    end

    rootProps.children = {
        -- 背景遮罩（有背景图时叠加半透明黑底，让 UI 文字清晰）
        bgImage and UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 15, 12, 10, 140 },
        } or nil,
        -- 顶部状态栏
        Comp.BuildTopBar(playerData),
        -- 中间内容区（可滚动）
        UI.ScrollView {
            width = "100%",
            flexGrow = 1,
            flexBasis = 0,
            scrollY = true,
            showScrollbar = false,
            scrollMultiplier = Theme.scrollSensitivity,
            children = {
                UI.Panel {
                    width = "100%",
                    padding = Theme.spacing.md,
                    gap = Theme.spacing.md,
                    children = contentChildren,
                },
            },
        },
        -- 底部固定区域（不随内容滚动，紧贴在滚动区下方）
        opts.bottomFixed and UI.Panel {
            width = "100%",
            padding = Theme.spacing.sm,
            paddingTop = Theme.spacing.xs,
            paddingBottom = Theme.spacing.xs,
            gap = Theme.spacing.sm,
            backgroundColor = { 20, 16, 12, 200 },
            flexDirection = opts.bottomFixedRow and "row" or "column",
            justifyContent = "center",
            alignItems = "center",
            children = opts.bottomFixed,
        } or nil,
        -- 聊天动态框
        Comp.BuildChatTicker(function()
            Router.EnterState(Router.STATE_CHAT)
        end),
        -- 底部导航
        Comp.BuildBottomNav(activeTab, onNavigate),
        -- 设置弹窗容器（叠在最上层，延迟加载避免循环依赖）
        (function()
            local S = require("ui_settings")
            local vis = S.IsVisible()
            local overlay = UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                pointerEvents = vis and "auto" or "none",
                children = vis and {
                    S.Build(function() S.Hide() end),
                } or {},
            }
            S.BindOverlay(overlay)
            return overlay
        end)(),
    }

    return UI.Panel(rootProps)
end

-- ============================================================================
-- 红点包装器 —— 在任意控件右上角叠加红点/数字角标
-- key: 红点标识（对应 RedDot.KEYS）
-- child: 被包装的 UI 元素
-- opts: { offsetX, offsetY, size } 微调位置和大小
-- ============================================================================
function Comp.WithRedDot(child, key, opts)
    local RedDot = require("ui_red_dot")
    opts = opts or {}
    local dotSize = opts.size or 16
    local offsetX = opts.offsetX or -4
    local offsetY = opts.offsetY or -4

    local visible = RedDot.IsVisible(key)
    local count = RedDot.GetCount(key)

    if not visible then
        return child
    end

    -- 有数字时角标更大
    local showNum = count > 0
    local badgeW = dotSize
    local badgeH = dotSize
    local badgeRadius = dotSize / 2
    if showNum then
        local numStr = count > 99 and "99+" or tostring(count)
        badgeW = math.max(dotSize + 4, #numStr * 7 + 6)
        badgeH = dotSize + 2
        badgeRadius = badgeH / 2
    end

    return UI.Panel {
        children = {
            child,
            -- 红点/角标
            UI.Panel {
                position = "absolute",
                top = offsetY,
                right = offsetX,
                width = badgeW,
                height = badgeH,
                borderRadius = badgeRadius,
                backgroundColor = Theme.colors.danger,
                borderColor = { 30, 25, 20, 255 },
                borderWidth = 1,
                justifyContent = "center",
                alignItems = "center",
                children = showNum and {
                    UI.Label {
                        text = count > 99 and "99+" or tostring(count),
                        fontSize = 8,
                        fontWeight = "bold",
                        fontColor = Theme.colors.white,
                    },
                } or {},
            },
        },
    }
end

-- ============================================================================
-- 带颜色标签的文本行（解析 <c=gold>文字</c> 标签）
-- 用法: Comp.BuildColorText(line, { fontSize = 12, fontColor = {r,g,b,a} })
-- ============================================================================
function Comp.BuildColorText(text, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or Theme.fontSize.tiny
    local defaultColor = opts.fontColor or Theme.colors.textLight
    local width = opts.width or "100%"

    local segments = Toast.ParseColorTags(text, defaultColor)

    -- 单段无颜色标签，直接返回 Label（性能优化）
    if #segments == 1 then
        return UI.Label {
            text = segments[1].text,
            fontSize = fontSize,
            fontColor = segments[1].fontColor,
            width = width,
        }
    end

    -- 多段：横排排列
    local children = {}
    for _, seg in ipairs(segments) do
        children[#children + 1] = UI.Label {
            text = seg.text,
            fontSize = fontSize,
            fontColor = seg.fontColor,
        }
    end
    return UI.Panel {
        width = width,
        flexDirection = "row",
        flexWrap = "wrap",
        children = children,
    }
end

-- ============================================================================
-- 通用弹窗组件
-- 用法:
--   Comp.Dialog(title, content, buttons)
--   Comp.Dialog(nil, content)           -- 无标题
--   Comp.Dialog(title, content, nil)    -- 无按钮
--   Comp.Dialog(title, customWidget)    -- content 为自定义 UI 控件
--   Comp.Dialog(title, content, {
--       { text = "取消", onClick = fn },
--       { text = "确认", onClick = fn, primary = true },
--   })
--
-- title:   string|nil   弹窗标题，nil 则不显示
-- content: string|table 纯文字或自定义 UI 控件（table 视为 UI 元素）
-- buttons: table|nil    按钮数组，nil/空则不显示按钮行
--   每项: { text=string, onClick=fn, primary=bool }
-- opts:    table|nil    可选 { width=300, onClose=fn, closeOnMask=true }
-- ============================================================================
function Comp.Dialog(title, content, buttons, opts)
    opts = opts or {}
    local dlgWidth = opts.width or 360
    local closeOnMask = opts.closeOnMask ~= false  -- 默认 true
    local onClose = opts.onClose

    -- 构建内容区
    local bodyChildren = {}

    -- 标题
    if title and title ~= "" then
        bodyChildren[#bodyChildren + 1] = UI.Label {
            text = title,
            fontSize = Theme.fontSize.heading,
            fontWeight = "bold",
            fontColor = Theme.colors.textGold,
            textAlign = "center",
            width = "100%",
        }
        bodyChildren[#bodyChildren + 1] = Comp.BuildInkDivider()
    end

    -- 内容
    if content then
        if type(content) == "string" then
            bodyChildren[#bodyChildren + 1] = UI.Label {
                text = content,
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textLight,
                width = "100%",
                textAlign = "center",
                paddingVertical = 8,
            }
        else
            -- 自定义 UI 控件
            bodyChildren[#bodyChildren + 1] = content
        end
    end

    -- 按钮行
    if buttons and #buttons > 0 then
        bodyChildren[#bodyChildren + 1] = Comp.BuildInkDivider()
        local btnChildren = {}
        for _, btn in ipairs(buttons) do
            if btn.primary then
                btnChildren[#btnChildren + 1] = Comp.BuildInkButton(btn.text, btn.onClick, { flex = 1 })
            else
                btnChildren[#btnChildren + 1] = Comp.BuildSecondaryButton(btn.text, btn.onClick, { flex = 1 })
            end
        end
        bodyChildren[#bodyChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 10,
            children = btnChildren,
        }
    end

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        zIndex = 100,
        onClick = function(self)
            if closeOnMask and onClose then onClose() end
        end,
        children = {
            UI.Panel {
                width = dlgWidth,
                maxHeight = "80%",
                backgroundColor = { 40, 35, 28, 245 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.sm,
                overflow = "hidden",
                onClick = function(self) end,  -- 阻止穿透
                children = bodyChildren,
            },
        },
    }
end

return Comp
