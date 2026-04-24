-- ============================================================================
-- 《问道长生》洞府主页（打坐修炼 + 灵气粒子 + 横向功能栏）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameCultivation = require("game_cultivation")
local Settings = require("ui_settings")
local Toast = require("ui_toast")

local NVG = require("nvg_manager")
local RedDot = require("ui_red_dot")
local DataItems = require("data_items")
local GameItems  = require("game_items")
local GameOps      = require("network.game_ops")
local GameServer   = require("game_server")
local GameArtifact = require("game_artifact")

local M = {}

-- 新手礼包是否已触发（避免重复）
local newbieGiftShown_ = false

-- 机缘弹窗状态
local showChancePopup_ = false
local showAttrPopup_ = false

-- ============================================================================
-- 灵气粒子系统（NanoVG）—— 向中心聚拢效果（通过 nvg_manager 调度）
-- ============================================================================
local particles = {}
local MAX_PARTICLES = 30
local particleInited = false
local screenW, screenH = 720, 1280
-- 聚拢目标（打坐角色中心，约屏幕上方 1/3 处）
local targetX, targetY = 360, 340

-- 修炼状态文本轮换
local meditateTexts = { "吐纳灵气中…", "修炼中…", "凝神静修中…", "感悟天道中…" }
local meditateTextIdx = 1
local textTimer = 0

-- 初始化单个粒子
local function CreateParticle()
    local p = {}
    -- 从屏幕边缘随机位置生成
    local side = math.random(1, 4)
    if side == 1 then     -- 上方
        p.x = math.random() * screenW
        p.y = -10
    elseif side == 2 then -- 下方
        p.x = math.random() * screenW
        p.y = screenH * 0.7 + math.random() * (screenH * 0.3)
    elseif side == 3 then -- 左侧
        p.x = -10
        p.y = math.random() * screenH * 0.6
    else                  -- 右侧
        p.x = screenW + 10
        p.y = math.random() * screenH * 0.6
    end
    p.size = math.random() * 2.5 + 1.0              -- 1.0~3.5
    p.alpha = math.random() * 0.3 + 0.1             -- 0.1~0.4
    p.alphaSpeed = (math.random() - 0.5) * 0.2
    p.lifetime = math.random() * 5 + 4              -- 4~9 秒
    p.age = 0
    p.speed = math.random() * 40 + 30               -- 30~70 px/s
    -- 方向指向打坐角色中心（带随机偏移增加自然感）
    local dx = targetX + (math.random() - 0.5) * 60 - p.x
    local dy = targetY + (math.random() - 0.5) * 60 - p.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then dist = 1 end
    p.vx = dx / dist * p.speed
    p.vy = dy / dist * p.speed
    -- 颜色变体
    local ct = math.random(1, 3)
    if ct == 1 then
        p.r, p.g, p.b = 200, 168, 85    -- 金色灵气
    elseif ct == 2 then
        p.r, p.g, p.b = 120, 180, 220   -- 青蓝灵气
    else
        p.r, p.g, p.b = 220, 215, 200   -- 白色灵气
    end
    return p
end

-- 初始化粒子池
local function InitParticles()
    if particleInited then return end
    particleInited = true
    screenW = graphics:GetWidth() / graphics:GetDPR()
    screenH = graphics:GetHeight() / graphics:GetDPR()
    targetX = screenW * 0.5
    targetY = screenH * 0.28
    for i = 1, MAX_PARTICLES do
        particles[i] = CreateParticle()
        particles[i].age = math.random() * particles[i].lifetime * 0.5
    end
end

-- 更新粒子
local function UpdateParticles(dt)
    for i, p in ipairs(particles) do
        p.age = p.age + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        p.alpha = p.alpha + p.alphaSpeed * dt
        if p.alpha > 0.45 then p.alpha = 0.45; p.alphaSpeed = -math.abs(p.alphaSpeed) end
        if p.alpha < 0.05 then p.alpha = 0.05; p.alphaSpeed = math.abs(p.alphaSpeed) end

        -- 接近中心时加速消散
        local dx = p.x - targetX
        local dy = p.y - targetY
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist < 40 then
            p.alpha = p.alpha * (dist / 40)
        end

        -- 超出生命或到达中心则重置
        if p.age >= p.lifetime or dist < 15 then
            particles[i] = CreateParticle()
        end
    end

    -- 修炼文本轮换
    textTimer = textTimer + dt
    if textTimer >= 4.0 then
        textTimer = 0
        meditateTextIdx = meditateTextIdx % #meditateTexts + 1
    end
end

-- 渲染粒子（ctx 由 nvg_manager 传入）
local function RenderParticles(ctx)
    for _, p in ipairs(particles) do
        local fadeAlpha = p.alpha
        local lifeRatio = p.age / p.lifetime
        if lifeRatio < 0.15 then
            fadeAlpha = fadeAlpha * (lifeRatio / 0.15)
        end
        if lifeRatio > 0.8 then
            fadeAlpha = fadeAlpha * (1.0 - (lifeRatio - 0.8) / 0.2)
        end
        local a = math.floor(fadeAlpha * 255)
        if a < 2 then goto continue end

        local glowSize = p.size * 3.0
        local paint = nvgRadialGradient(ctx,
            p.x, p.y, p.size * 0.3, glowSize,
            nvgRGBA(p.r, p.g, p.b, math.floor(a * 0.35)),
            nvgRGBA(p.r, p.g, p.b, 0))
        nvgBeginPath(ctx)
        nvgCircle(ctx, p.x, p.y, glowSize)
        nvgFillPaint(ctx, paint)
        nvgFill(ctx)

        nvgBeginPath(ctx)
        nvgCircle(ctx, p.x, p.y, p.size * 0.5)
        nvgFillColor(ctx, nvgRGBA(p.r, p.g, p.b, a))
        nvgFill(ctx)

        ::continue::
    end
end

-- ============================================================================
-- 启停粒子系统（通过 nvg_manager）
-- ============================================================================
local homeRegistered = false

function M.StartParticles()
    if homeRegistered then return end
    homeRegistered = true
    NVG.Register("home", RenderParticles, function(dt)
        InitParticles()
        UpdateParticles(dt)
    end)
end

function M.StopParticles()
    if not homeRegistered then return end
    homeRegistered = false
    NVG.Unregister("home")
end

-- ============================================================================
-- 悬浮快捷按钮数据
-- ============================================================================
local floatingLeft = {
    { name = "签到", icon = Theme.images.iconQuest,   state = Router.STATE_SIGNIN },
    { name = "月卡", icon = Theme.images.iconRanking,  state = Router.STATE_MONTHCARD },
    { name = "福利", icon = Theme.images.iconMarket,   state = Router.STATE_GIFT },
    { name = "坊市", icon = Theme.images.iconMarket,   state = Router.STATE_MARKET },
    { name = "仙信", icon = Theme.images.iconMarket,   state = Router.STATE_MAIL },
}

local floatingRight = {
    { name = "充值", icon = Theme.images.iconRanking,  state = Router.STATE_RECHARGE },
    { name = "炼丹", icon = Theme.images.iconAlchemy,  state = Router.STATE_ALCHEMY },
    { name = "机缘", icon = Theme.images.iconExplore,  onClick = function()
        showChancePopup_ = true
        Router.RebuildUI()
    end },
    { name = "试炼", icon = Theme.images.iconTrial,    state = Router.STATE_TRIAL, dotKey = RedDot.KEYS.MORE_TRIAL },
    { name = "任务", icon = Theme.images.iconQuest,    state = Router.STATE_QUEST },
}

--- 构建单个悬浮按钮
---@param feat table { name, icon, state }
---@return table UI element
local function BuildFloatingBtn(feat)
    return UI.Panel {
        width = 48,
        height = 52,
        alignItems = "center",
        justifyContent = "center",
        gap = 2,
        borderRadius = Theme.radius.md,
        backgroundColor = { 25, 22, 18, 190 },
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            if feat.onClick then
                feat.onClick()
            else
                Router.EnterState(feat.state)
            end
        end,
        children = {
            UI.Panel {
                width = 24,
                height = 24,
                backgroundImage = feat.icon,
                backgroundFit = "contain",
                imageTint = Theme.colors.gold,
            },
            UI.Label {
                text = feat.name,
                fontSize = 9,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- 洞府功能按钮数据（角色自身相关）
-- ============================================================================
local homeFeatures = {
    { name = "属性",  icon = Theme.images.iconHome,    desc = "查看角色属性", action = "attr_popup",            dotKey = RedDot.KEYS.HOME_ATTR },
    { name = "功法",  icon = Theme.images.iconExplore,  desc = "修炼功法",    state = Router.STATE_SKILL,       dotKey = RedDot.KEYS.HOME_SKILL },
    { name = "悟道",  icon = Theme.images.iconSect,     desc = "参悟大道",    state = Router.STATE_DAO,         dotKey = RedDot.KEYS.HOME_DAO },
    { name = "渡劫",  icon = Theme.images.iconTrial,    desc = "突破境界",    state = Router.STATE_TRIBULATION, dotKey = RedDot.KEYS.HOME_TRIBULATION },
    { name = "丹药",  icon = Theme.images.iconBag,      desc = "服用丹药",    state = Router.STATE_PILL,        dotKey = RedDot.KEYS.HOME_PILL },
    { name = "灵宠",  icon = Theme.images.iconPet,      desc = "灵宠伙伴",    state = Router.STATE_PET,         dotKey = RedDot.KEYS.NAV_PET },
}

-- ============================================================================
-- 构建单个功能按钮（底部横向栏）
-- ============================================================================
local function BuildHomeFeatureBtn(feat)
    local btn = UI.Panel {
        width = 72,
        height = 80,
        alignItems = "center",
        justifyContent = "center",
        gap = 4,
        borderRadius = Theme.radius.md,
        backgroundColor = { 35, 30, 25, 160 },
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            if feat.action == "attr_popup" then
                showAttrPopup_ = true
                Router.RebuildUI()
            elseif feat.state then
                Router.EnterState(feat.state)
            end
        end,
        children = {
            UI.Panel {
                width = 32,
                height = 32,
                backgroundImage = feat.icon,
                backgroundFit = "contain",
                imageTint = Theme.colors.gold,
            },
            UI.Label {
                text = feat.name,
                fontSize = 11,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
        },
    }
    -- 红点包装
    if feat.dotKey then
        return Comp.WithRedDot(btn, feat.dotKey)
    end
    return btn
end

-- ============================================================================
-- 法宝槽位选择弹窗（点击槽位后显示的独立覆盖层）
-- ============================================================================
local STAT_TYPE_LABEL = {
    attack  = "攻击", defense = "防御", speed   = "速度",
    crit    = "暴击率", dodge   = "闪避率", hp      = "气血",
    hpMax   = "气血上限", mp      = "灵力",  mpMax   = "灵力上限",
    hit     = "命中", cultSpd = "修炼速", wisdom  = "悟性",
}

local BuildFabaoSlotOverlay  -- 前向声明，供 BuildEquippedItemInfoOverlay 引用

--- 操作行（强化/升阶/洗炼 通用布局）
local function BuildOpRow(label, hint, canDo, btnText, onClick)
    local labelColor = canDo and Theme.colors.textGold or Theme.colors.textSecondary
    local hintColor  = canDo and Theme.colors.textLight or Theme.colors.danger
    local btn = canDo
        and Comp.BuildInkButton(btnText, onClick,
            { width = 60, fontSize = Theme.fontSize.small })
        or  Comp.BuildSecondaryButton(btnText, function()
                Toast.Show(hint, { variant = "warning" })
            end, { width = 60, fontSize = Theme.fontSize.small })
    return UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between", alignItems = "center",
        paddingVertical = 4,
        children = {
            UI.Panel { flex = 1, gap = 2, children = {
                UI.Label { text = label, fontSize = Theme.fontSize.body,
                    fontWeight = "bold", fontColor = labelColor },
                UI.Label { text = hint,  fontSize = Theme.fontSize.tiny,
                    fontColor = hintColor },
            }},
            btn,
        },
    }
end

--- 已装备法宝详情弹窗（有装备时点击槽位显示属性 + 操作）
local function BuildEquippedItemInfoOverlay(slotDef, item, equippedItems)
    local qDef    = DataItems.QUALITY[item.quality]
    local qColor  = qDef and qDef.color or Theme.colors.textLight
    local qLabel  = qDef and qDef.label or ""
    local artName = item.name or ""

    -- 强化/升阶/洗炼 可用性
    local canEnh, enhErr = GameArtifact.CanEnhance(artName)
    local canAsc, ascErr = GameArtifact.CanAscend(artName)
    local canRol, rolErr = GameArtifact.CanReroll(artName)
    local costInfo       = GameArtifact.GetEnhanceCost(artName)
    local enhanceLv      = item.level or 1
    local ascStage       = item.ascStage or 0
    local maxLv          = costInfo and costInfo.maxLevel or enhanceLv

    -- 属性行
    local statRows = {}
    if (item.baseAtk or 0) > 0 then
        statRows[#statRows + 1] = Comp.BuildStatRow("攻击", "+" .. item.baseAtk,
            { valueColor = { 255, 150, 100, 255 } })
    end
    if (item.baseDef or 0) > 0 then
        statRows[#statRows + 1] = Comp.BuildStatRow("防御", "+" .. item.baseDef,
            { valueColor = { 100, 200, 255, 255 } })
    end
    if item.mainStat then
        local stLabel = STAT_TYPE_LABEL[item.mainStat.type] or item.mainStat.type or ""
        statRows[#statRows + 1] = Comp.BuildStatRow(stLabel, "+" .. (item.mainStat.value or 0),
            { valueColor = Theme.colors.textGold })
    end
    if item.subStats then
        for _, ss in ipairs(item.subStats) do
            local stLabel = STAT_TYPE_LABEL[ss.type] or ss.type or ""
            statRows[#statRows + 1] = Comp.BuildStatRow(stLabel, "+" .. (ss.value or 0),
                { valueColor = Theme.colors.textSecondary })
        end
    end
    if #statRows == 0 then
        statRows[#statRows + 1] = UI.Label {
            text = "暂无属性数据",
            fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary,
        }
    end

    -- 操作区行
    local enhHint = canEnh
        and (costInfo and ("消耗：灵石" .. costInfo.lingshi .. " 灵尘" .. costInfo.lingchen) or "")
        or  (enhErr or "当前无法强化")
    local opRows = {
        BuildOpRow(
            "强化  Lv." .. enhanceLv .. " / " .. maxLv,
            enhHint, canEnh, "强化",
            function()
                GameArtifact.DoEnhance(artName, function(ok, msg)
                    Toast.Show(msg or (ok and "强化成功" or "强化失败"),
                        { variant = ok and "success" or "error" })
                    Router.HideOverlayDialog()
                    Router.RebuildUI()
                end)
            end
        ),
    }
    -- 升阶（未满 3 阶才显示）
    if ascStage < 3 then
        local ascHint = canAsc
            and ("第" .. ascStage .. "阶 → 第" .. (ascStage + 1) .. "阶")
            or  (ascErr or "当前无法升阶")
        opRows[#opRows + 1] = BuildOpRow(
            "升阶  当前第" .. ascStage .. "阶",
            ascHint, canAsc, "升阶",
            function()
                GameArtifact.DoAscend(artName, function(ok, msg)
                    Toast.Show(msg or (ok and "升阶成功" or "升阶失败"),
                        { variant = ok and "success" or "error" })
                    Router.HideOverlayDialog()
                    Router.RebuildUI()
                end)
            end
        )
    end
    -- 洗炼（有副属性才显示）
    if item.subStats and #item.subStats > 0 then
        local rolHint = canRol and "随机重掷副属性" or (rolErr or "当前无法洗炼")
        opRows[#opRows + 1] = BuildOpRow(
            "洗炼",
            rolHint, canRol, "洗炼",
            function()
                GameArtifact.DoReroll(artName, function(ok, msg)
                    Toast.Show(msg or (ok and "洗炼完成" or "洗炼失败"),
                        { variant = ok and "success" or "error" })
                    if ok then Router.RebuildUI() end
                end)
                Router.HideOverlayDialog()
            end
        )
    end

    local content = UI.Panel {
        width = "100%", gap = 10,
        children = {
            -- 名称 + 品质 + 部位
            UI.Panel {
                width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                paddingBottom = 4,
                children = {
                    UI.Label { text = item.name or slotDef.label,
                        fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                        fontColor = qColor },
                    UI.Label { text = qLabel,
                        fontSize = Theme.fontSize.small, fontColor = qColor },
                    UI.Label { text = "·" .. slotDef.label,
                        fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                },
            },
            -- 装备属性
            Comp.BuildCardPanel("装备属性", statRows),
            -- 强化/升阶/洗炼
            Comp.BuildCardPanel("法宝操作", opRows),
            -- 卸下 / 更换
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 8,
                justifyContent = "flex-end",
                children = {
                    Comp.BuildSecondaryButton("卸下", function()
                        GameOps.Request("equip_remove", {
                            playerKey = GameServer.GetServerKey("player"),
                            slot = slotDef.slot,
                        }, function(ok, data)
                            Toast.Show(data and data.msg or (ok and "已卸下" or "卸下失败"),
                                { variant = ok and "success" or "error" })
                            if ok then Router.RebuildUI() end
                        end)
                        Router.HideOverlayDialog()
                    end, { width = 72, fontSize = Theme.fontSize.small }),
                    Comp.BuildInkButton("更换", function()
                        Router.ShowOverlayDialog(BuildFabaoSlotOverlay(slotDef, equippedItems))
                    end, { width = 72, fontSize = Theme.fontSize.small }),
                },
            },
        },
    }
    return Comp.Dialog(slotDef.label .. " 法宝详情", content, {}, {
        onClose = function() Router.HideOverlayDialog() end,
        width = "92%",
    })
end

BuildFabaoSlotOverlay = function(slotDef, equippedItems)
    local p = GamePlayer.Get()
    if not p then return nil end
    local items      = GameItems.GetItemsByCategory("fabao", slotDef.label)
    local allBagItems = p.bagItems or {}
    local curEquip   = equippedItems and equippedItems[slotDef.slot]

    local rows = {}

    -- 当前穿戴的法宝
    if curEquip then
        local qDef = DataItems.QUALITY[curEquip.quality]
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            paddingHorizontal = 10, paddingVertical = 8,
            backgroundColor = { 35, 50, 30, 200 },
            borderRadius = Theme.radius.sm,
            borderColor = { 80, 200, 100, 180 }, borderWidth = 1,
            children = {
                UI.Panel {
                    flex = 1, gap = 2,
                    children = {
                        UI.Label {
                            text = "[已穿] " .. (curEquip.name or ""),
                            fontSize = Theme.fontSize.body, fontWeight = "bold",
                            fontColor = qDef and qDef.color or Theme.colors.textLight,
                        },
                        UI.Label {
                            text = (qDef and qDef.label or "") .. " · " .. slotDef.label,
                            fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary,
                        },
                    },
                },
                Comp.BuildSecondaryButton("卸下", function()
                    GameOps.Request("equip_remove", {
                        playerKey = GameServer.GetServerKey("player"),
                        slot = slotDef.slot,
                    }, function(ok, data)
                        Toast.Show(data and data.msg or (ok and "已卸下" or "卸下失败"),
                            { variant = ok and "success" or "error" })
                        if ok then Router.RebuildUI() end
                    end)
                    Router.HideOverlayDialog()
                end, { width = 60, fontSize = Theme.fontSize.small }),
            },
        }
    end

    -- 背包候选法宝列表
    if #items == 0 then
        rows[#rows + 1] = UI.Label {
            text = "背包中暂无" .. slotDef.label .. "部位法宝",
            fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary,
            textAlign = "center", width = "100%", paddingVertical = 20,
        }
    else
        for _, item in ipairs(items) do
            local bagIdx = 0
            for i, bi in ipairs(allBagItems) do
                if bi == item then bagIdx = i; break end
            end
            local qDef = DataItems.QUALITY[item.quality]
            local statParts = {}
            if (item.baseAtk or 0) > 0 then statParts[#statParts + 1] = "攻+" .. item.baseAtk end
            if (item.baseDef or 0) > 0 then statParts[#statParts + 1] = "防+" .. item.baseDef end
            if item.mainStat then
                local stLabel = STAT_TYPE_LABEL[item.mainStat.type] or item.mainStat.type or ""
                statParts[#statParts + 1] = stLabel .. "+" .. (item.mainStat.value or 0)
            end
            local statStr = #statParts > 0 and table.concat(statParts, "  ") or (qDef and qDef.label or "")
            local capturedIdx = bagIdx
            rows[#rows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                paddingHorizontal = 10, paddingVertical = 8,
                backgroundColor = { 30, 26, 20, 180 },
                borderRadius = Theme.radius.sm,
                borderColor = qDef and qDef.color or Theme.colors.border, borderWidth = 1,
                children = {
                    UI.Panel {
                        flex = 1, gap = 2,
                        children = {
                            UI.Label {
                                text = item.name or "",
                                fontSize = Theme.fontSize.body, fontWeight = "bold",
                                fontColor = qDef and qDef.color or Theme.colors.textLight,
                            },
                            UI.Label {
                                text = statStr,
                                fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                    Comp.BuildInkButton("穿戴", function()
                        GameOps.Request("equip_wear", {
                            playerKey = GameServer.GetServerKey("player"),
                            bagIndex  = capturedIdx,
                        }, function(ok, data)
                            Toast.Show(data and data.msg or (ok and "穿戴成功" or "穿戴失败"),
                                { variant = ok and "success" or "error" })
                            if ok then Router.RebuildUI() end
                        end)
                        Router.HideOverlayDialog()
                    end, { width = 60, fontSize = Theme.fontSize.small }),
                },
            }
        end
    end

    local content = UI.ScrollView {
        width = "100%", maxHeight = 400,
        scrollY = true, showScrollbar = false,
        scrollMultiplier = Theme.scrollSensitivity or 1.5,
        children = { UI.Panel { width = "100%", gap = 6, children = rows } },
    }
    return Comp.Dialog(slotDef.label .. " 法宝选择", content, {}, {
        onClose = function() Router.HideOverlayDialog() end,
        width = "92%",
    })
end

-- ============================================================================
-- 装备槽位图标（环绕打坐图）
-- ============================================================================

--- 构建单个装备槽位图标
local function BuildEquipSlot(slotKey, equippedItems)
    local slotDef = DataItems.GetSlotByKey(slotKey)
    if not slotDef then return nil end
    local item = equippedItems and equippedItems[slotKey]
    local hasItem = item ~= nil
    local borderColor = Theme.colors.border
    local labelColor = Theme.colors.textSecondary
    if hasItem and item.quality then
        local qDef = DataItems.QUALITY[item.quality]
        if qDef then
            borderColor = qDef.color
            labelColor = qDef.color
        end
    end
    return UI.Panel {
        width = 62, height = 76,
        alignItems = "center", justifyContent = "center",
        gap = 3,
        borderRadius = Theme.radius.md,
        backgroundColor = { 25, 22, 18, hasItem and 200 or 120 },
        borderColor = borderColor,
        borderWidth = hasItem and 2 or 1,
        cursor = "pointer",
        onClick = function(self)
            if hasItem then
                Router.ShowOverlayDialog(BuildEquippedItemInfoOverlay(slotDef, item, equippedItems))
            else
                Router.ShowOverlayDialog(BuildFabaoSlotOverlay(slotDef, equippedItems))
            end
        end,
        children = {
            UI.Panel {
                width = 40, height = 40,
                alignItems = "center", justifyContent = "center",
                borderRadius = 8,
                backgroundColor = hasItem and { 40, 35, 28, 255 } or { 30, 26, 20, 150 },
                children = {
                    UI.Label {
                        text = slotDef.label,
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = labelColor,
                    },
                },
            },
            UI.Label {
                text = hasItem and (item.name or slotDef.label) or "空",
                fontSize = 9,
                fontColor = labelColor,
                textAlign = "center",
            },
        },
    }
end

-- ============================================================================
-- 属性弹窗
-- ============================================================================

-- 动态属性颜色：根据数值高低返回对应档位颜色
local STAT_TIERS = {
    --              低       中        高
    hp      = { 300,    700,     4000  },  -- 800=高(绿), 300以下=低(红)
    mp      = { 100,    190,     1000  },  -- 200=高(绿), 100以下=低(红)
    attack  = { 35,     120,     500 },    -- 63=中
    defense = { 25,     80,      350 },    -- 30=中
    speed   = { 18,     60,      220 },    -- 30=中
    crit    = { 6,      18,      40 },     -- 10%=中
    dodge   = { 5,      15,      30 },     -- 3%=低（警示红）
    wisdom  = { 45,     100,     220 },
    cultSpd = { 3,      15,      60 },
}
local TIER_COLORS = {
    { 255, 115, 85,  255 },   -- 低：亮珊瑚红（警示）
    { 180, 210, 240, 255 },   -- 中：淡钢蓝（区别于默认白色文字）
    { 100, 230, 145, 255 },   -- 高：亮翠绿
    { 255, 215, 70,  255 },   -- 超高：亮金黄
}

--- 根据属性名和数值获取动态颜色
local function GetStatColor(statKey, value)
    local tiers = STAT_TIERS[statKey]
    if not tiers then return TIER_COLORS[2] end
    if value < tiers[1] then return TIER_COLORS[1] end
    if value < tiers[2] then return TIER_COLORS[2] end
    if value < tiers[3] then return TIER_COLORS[3] end
    return TIER_COLORS[4]
end

-- 气运/道心等文本属性的颜色映射
local FORTUNE_COLORS = {
    ["低迷"] = TIER_COLORS[1], ["普通"] = TIER_COLORS[2],
    ["小吉"] = TIER_COLORS[3], ["大吉"] = TIER_COLORS[4],
    ["天命"] = { 255, 100, 60, 255 },
}
local DAOHEART_COLORS = {
    ["不稳"] = TIER_COLORS[1], ["稳固"] = TIER_COLORS[2],
    ["坚定"] = TIER_COLORS[3], ["不动"] = TIER_COLORS[4],
}

local function BuildAttrPopup(p)
    local eqB = GamePlayer.GetEquippedBonus()
    local artB = GamePlayer.GetArtifactBonus()
    local sectB = GamePlayer.GetSectBonus()

    local function FmtStat(total, eqVal, artVal, sectVal, suffix)
        suffix = suffix or ""
        local parts = {}
        if (eqVal or 0) > 0 then parts[#parts + 1] = "装备+" .. eqVal end
        if (artVal or 0) > 0 then parts[#parts + 1] = "法宝+" .. artVal end
        if (sectVal or 0) > 0 then parts[#parts + 1] = "宗门+" .. sectVal end
        if #parts > 0 then
            return total .. suffix .. " (" .. table.concat(parts, " ") .. ")"
        end
        return total .. suffix
    end

    local rate = GameCultivation.GetPerSec()
    local rateStr = string.format("%.1f/秒", rate)

    -- 打坐图路径
    local meditateImg = (Theme.meditateChars[p.gender] or Theme.meditateChars["男"])[p.avatarIndex or 1]
        or (p.gender == "女" and Theme.images.meditateCharF or Theme.images.meditateChar)

    -- 用 ScrollView 包裹，避免内容超出弹窗高度不可见
    local content = UI.ScrollView {
        width = "100%",
        maxHeight = 480,
        scrollY = true,
        showScrollbar = false,
        scrollMultiplier = Theme.scrollSensitivity,
        children = {
            UI.Panel {
                width = "100%",
                gap = 8,
                children = {
                    -- 角色信息头
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        paddingVertical = 4,
                        children = {
                            UI.Label {
                                text = p.name or "无名",
                                fontSize = Theme.fontSize.subtitle,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Label {
                                text = p.realmName or "练气初期",
                                fontSize = Theme.fontSize.small,
                                fontColor = Theme.colors.gold,
                            },
                        },
                    },
                    -- 打坐图 + 装备槽位环绕
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        alignItems = "center",
                        justifyContent = "center",
                        gap = 6,
                        children = {
                            -- 左侧装备槽（头戴、身穿）
                            UI.Panel {
                                gap = 6,
                                alignItems = "center",
                                children = {
                                    BuildEquipSlot("head", p.equippedItems),
                                    BuildEquipSlot("body", p.equippedItems),
                                },
                            },
                            -- 打坐图片
                            UI.Panel {
                                width = 140,
                                height = 140,
                                backgroundImage = meditateImg,
                                backgroundFit = "contain",
                            },
                            -- 右侧装备槽（手持、饰品、鞋子）
                            UI.Panel {
                                gap = 6,
                                alignItems = "center",
                                children = {
                                    BuildEquipSlot("weapon", p.equippedItems),
                                    BuildEquipSlot("accessory", p.equippedItems),
                                    BuildEquipSlot("shoes", p.equippedItems),
                                },
                            },
                        },
                    },
                    -- 寿元
                    Comp.BuildStatRow("寿元", (p.lifespan or 0) .. "/" .. (p.lifespanMax or 100),
                        { valueColor = GetStatColor("hp", p.lifespanMax or 100) }),
                    -- 战斗属性
                    Comp.BuildCardPanel("战斗属性", {
                        Comp.BuildStatRow("气血", (p.hp or 0) .. "/" .. (p.hpMax or 0),
                            { valueColor = GetStatColor("hp", p.hpMax or 0) }),
                        Comp.BuildStatRow("灵力", (p.mp or 0) .. "/" .. (p.mpMax or 0),
                            { valueColor = GetStatColor("mp", p.mpMax or 0) }),
                        Comp.BuildStatRow("攻击", FmtStat(p.attack or 0, eqB.attack, artB.attack, sectB.attack),
                            { valueColor = GetStatColor("attack", p.attack or 0) }),
                        Comp.BuildStatRow("防御", FmtStat(p.defense or 0, eqB.defense, artB.defense, nil),
                            { valueColor = GetStatColor("defense", p.defense or 0) }),
                        Comp.BuildStatRow("速度", FmtStat(p.speed or 0, eqB.speed, artB.speed, sectB.speed),
                            { valueColor = GetStatColor("speed", p.speed or 0) }),
                        Comp.BuildStatRow("暴击", FmtStat(p.crit or 0, eqB.crit, artB.crit, nil, "%"),
                            { valueColor = GetStatColor("crit", p.crit or 0) }),
                        Comp.BuildStatRow("闪避", FmtStat(p.dodge or 0, eqB.dodge, 0, nil, "%"),
                            { valueColor = GetStatColor("dodge", p.dodge or 0) }),
                    }),
                    -- 修真属性
                    Comp.BuildCardPanel("修真属性", {
                        Comp.BuildStatRow("悟性", tostring(p.wisdom or 0),
                            { valueColor = GetStatColor("wisdom", p.wisdom or 0) }),
                        Comp.BuildStatRow("气运", p.fortune or "未知",
                            { valueColor = FORTUNE_COLORS[p.fortune] or TIER_COLORS[2] }),
                        Comp.BuildStatRow("道心", p.daoHeart or "未知",
                            { valueColor = DAOHEART_COLORS[p.daoHeart] or TIER_COLORS[2] }),
                        Comp.BuildStatRow("修炼速度", rateStr,
                            { valueColor = GetStatColor("cultSpd", rate) }),
                    }),
                },
            },
        },
    }

    return Comp.Dialog("角色属性", content, {}, {
        onClose = function()
            showAttrPopup_ = false
            Router.RebuildUI()
        end,
        width = "92%",
    })
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then
        print("[Home] 警告: 玩家数据为空")
        return UI.Panel { width = "100%", height = "100%" }
    end
    payload = payload or {}

    -- 新手礼包 Toast（首次进入主页时触发）
    if payload.newPlayer and not newbieGiftShown_ then
        newbieGiftShown_ = true
        -- 延迟显示新手礼包 Toast 序列
        Toast.ShowSequence({
            "获得大能传承: 灵石 x500",
            "获得大能传承: 仙石 x10",
            "获得大能传承: 基础吐纳功法 x1",
            "获得大能传承: 新手法宝 碎星剑 x1",
            "获得大能传承: 筑基丹 x1",
        }, 0.5)
    end

    -- 启动修炼系统 + 灵气粒子 + 导航栏粒子
    if not GameCultivation.IsRunning() then
        GameCultivation.ApplyOfflineGains()
        GameCultivation.Start()
    end
    M.StartParticles()
    Comp.StartNavParticles()

    -- 修为进度百分比（守卫：仙人期 cultivationMax=0 时显示 100%；溢出时最多 100%）
    local cultPct = (p.cultivationMax and p.cultivationMax > 0)
        and math.min(100, math.floor(p.cultivation / p.cultivationMax * 100))
        or 100

    -- 横向功能按钮列表
    local featureBtns = {}
    for _, feat in ipairs(homeFeatures) do
        featureBtns[#featureBtns + 1] = BuildHomeFeatureBtn(feat)
    end

    -- 悬浮按钮列表
    local leftBtns = {}
    for _, feat in ipairs(floatingLeft) do
        leftBtns[#leftBtns + 1] = BuildFloatingBtn(feat)
    end
    local rightBtns = {}
    for _, feat in ipairs(floatingRight) do
        rightBtns[#rightBtns + 1] = BuildFloatingBtn(feat)
    end

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgHome,
        backgroundFit = "cover",
        children = {
            -- 背景遮罩
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 15, 12, 10, 120 },
            },

            -- 顶部状态栏
            Comp.BuildTopBar(p),

            -- ========== 左侧悬浮按钮（每日福利） ==========
            UI.Panel {
                position = "absolute",
                left = 35,
                top = Theme.topBarHeight + 8,
                paddingTop = 35,
                gap = 10,
                zIndex = 10,
                children = leftBtns,
            },

            -- ========== 右侧悬浮按钮（核心玩法） ==========
            UI.Panel {
                position = "absolute",
                right = 35,
                top = Theme.topBarHeight + 8,
                paddingTop = 35,
                gap = 10,
                zIndex = 10,
                children = rightBtns,
            },

            -- 中间内容区
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                alignItems = "center",
                children = {
                    -- 上方弹性留白（与下方配合实现垂直居中）
                    UI.Panel { flexGrow = 1 },

                    -- ========== 打坐角色区域 ==========
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        children = {
                            -- 打坐图片（根据性别+头像索引选择对应变体）
                            UI.Panel {
                                width = 220,
                                height = 220,
                                backgroundImage = (Theme.meditateChars[p.gender] or Theme.meditateChars["男"])[p.avatarIndex or 1]
                                    or (p.gender == "女" and Theme.images.meditateCharF or Theme.images.meditateChar),
                                backgroundFit = "contain",
                            },
                            -- 修炼状态文字
                            UI.Label {
                                text = meditateTexts[meditateTextIdx],
                                fontSize = Theme.fontSize.body,
                                fontColor = Theme.colors.accent,
                                marginTop = 4,
                            },
                            -- 修为进度条
                            UI.Panel {
                                width = "70%",
                                marginTop = 8,
                                gap = 4,
                                children = {
                                    UI.Panel {
                                        width = "100%",
                                        flexDirection = "row",
                                        justifyContent = "space-between",
                                        children = {
                                            UI.Label {
                                                text = "修为 " .. p.realmName,
                                                fontSize = Theme.fontSize.small,
                                                fontColor = Theme.colors.textGold,
                                            },
                                            UI.Label {
                                                text = p.cultivation .. "/" .. p.cultivationMax .. "  (" .. cultPct .. "%)",
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
                                                width = tostring(cultPct) .. "%",
                                                height = "100%",
                                                borderRadius = 5,
                                                backgroundColor = Theme.colors.gold,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- ========== 突破 / 升级按钮（日志上方，半宽居中） ==========
                    (function()
                        local canTrib = GameCultivation.CanTribulation()
                        local canSub, subReason, subExtra = GameCultivation.CanAdvanceSub()

                        -- 判断是否因道心不足导致小境界晋升被锁
                        local daoHeartBlocking = false
                        local daoHeartInfo = nil
                        if not canTrib and not canSub then
                            local pd = GamePlayer.Get()
                            if pd then
                                local cult    = pd.cultivation or 0
                                local maxCult = pd.cultivationMax or 0
                                if cult >= maxCult and subReason == "dao_heart" then
                                    daoHeartBlocking = true
                                    daoHeartInfo = subExtra -- { required, current }
                                end
                            end
                        end

                        if not canTrib and not canSub and not daoHeartBlocking then
                            return UI.Panel {}
                        end

                        local isTrib   = canTrib
                        local isGrayed = daoHeartBlocking

                        local btnLabel  = isTrib and "渡  劫" or "境界突破"
                        local btnBg     = isGrayed and { 55, 50, 45, 200 }
                                          or (isTrib and { 180, 60, 30, 230 } or Theme.colors.gold)
                        local btnText   = isGrayed and { 110, 100, 85, 200 }
                                          or (isTrib and { 255, 220, 190, 255 } or Theme.colors.btnPrimaryText)
                        local btnBorder = isGrayed and { 75, 65, 55, 160 }
                                          or (isTrib and { 220, 100, 60, 255 } or Theme.colors.goldDark)

                        local hintText = nil
                        if isGrayed and daoHeartInfo then
                            hintText = "道心不足（" .. (daoHeartInfo.current or 0)
                                       .. " / " .. (daoHeartInfo.required or 0) .. "）"
                        end

                        return UI.Panel {
                            width = "46%",
                            marginTop = 8,
                            alignItems = "center",
                            children = {
                                UI.Panel {
                                    width = "100%",
                                    height = 40,
                                    borderRadius = Theme.radius.md,
                                    backgroundColor = btnBg,
                                    borderColor = btnBorder,
                                    borderWidth = 1,
                                    justifyContent = "center",
                                    alignItems = "center",
                                    cursor = isGrayed and nil or "pointer",
                                    onClick = isGrayed and nil or function(self)
                                        if isTrib then
                                            GameCultivation.DoTribulation(nil, function(ok, msg)
                                                Toast.Show(msg, { variant = ok and "success" or "error" })
                                                Router.RebuildUI()
                                            end)
                                        else
                                            GameCultivation.AdvanceSub(function(ok, msg)
                                                Toast.Show(msg, { variant = ok and "success" or "error" })
                                                Router.RebuildUI()
                                            end)
                                        end
                                    end,
                                    children = {
                                        UI.Label {
                                            text = btnLabel,
                                            fontSize = Theme.fontSize.body,
                                            fontWeight = "bold",
                                            fontColor = btnText,
                                        },
                                    },
                                },
                                hintText and UI.Label {
                                    text = hintText,
                                    fontSize = 10,
                                    fontColor = { 210, 170, 80, 240 },
                                    marginTop = 3,
                                } or UI.Panel {},
                            },
                        }
                    end)(),

                    -- ========== 修行日志（紧凑版） ==========
                    UI.Panel {
                        width = "90%",
                        marginTop = 6,
                        backgroundColor = { 25, 22, 18, 180 },
                        borderRadius = Theme.radius.md,
                        borderColor = Theme.colors.border,
                        borderWidth = 1,
                        padding = Theme.spacing.sm,
                        children = {
                            UI.Panel {
                                width = "100%",
                                height = 100,
                                children = {
                                    UI.ScrollView {
                                        width = "100%",
                                        height = "100%",
                                        scrollY = true,
                                        showScrollbar = false,
                                        scrollMultiplier = Theme.scrollSensitivity,
                                        children = {
                                            UI.Panel {
                                                width = "100%",
                                                gap = 2,
                                                children = (function()
                                                    local logs = {}
                                                    for i, line in ipairs(p.cultivationLogs or {}) do
                                                        logs[i] = Comp.BuildColorText(line, {
                                                            fontSize = Theme.fontSize.tiny,
                                                            fontColor = Theme.colors.textLight,
                                                        })
                                                    end
                                                    return logs
                                                end)(),
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- 弹性留白
                    UI.Panel { flexGrow = 1 },

                    -- ========== 横向功能按钮栏 ==========
                    UI.Panel {
                        width = "100%",
                        paddingHorizontal = 8,
                        marginBottom = 4,
                        children = {
                            UI.ScrollView {
                                width = "100%",
                                height = 90,
                                scrollX = true,
                                scrollY = false,
                                showScrollbar = false,
                                scrollMultiplier = Theme.scrollSensitivity,
                                children = {
                                    UI.Panel {
                                        flexDirection = "row",
                                        flexShrink = 0,
                                        gap = 8,
                                        paddingHorizontal = 4,
                                        paddingVertical = 4,
                                        children = featureBtns,
                                    },
                                },
                            },
                        },
                    },
                },
            },

            -- 聊天动态框
            Comp.BuildChatTicker(function()
                Router.EnterState(Router.STATE_CHAT)
            end),

            -- 底部导航
            Comp.BuildBottomNav("home", Router.HandleNavigate),

            -- 弹窗层（统一收集，避免 nil 空洞导致后续元素被跳过）
            (function()
                if showChancePopup_ then
                    return Comp.Dialog("机缘",
                        UI.Panel {
                            width = "100%",
                            gap = 12,
                            children = {
                                -- 历练入口
                                UI.Panel {
                                    width = "100%",
                                    flexDirection = "row",
                                    alignItems = "center",
                                    gap = 12,
                                    padding = 12,
                                    borderRadius = Theme.radius.md,
                                    backgroundColor = Theme.colors.bgDark,
                                    borderColor = Theme.colors.borderGold,
                                    borderWidth = 1,
                                    cursor = "pointer",
                                    onClick = function(self)
                                        showChancePopup_ = false
                                        Router.EnterState(Router.STATE_EXPLORE)
                                    end,
                                    children = {
                                        UI.Panel {
                                            width = 36, height = 36,
                                            backgroundImage = Theme.images.iconExplore,
                                            backgroundFit = "contain",
                                            imageTint = Theme.colors.gold,
                                        },
                                        UI.Panel {
                                            flexGrow = 1,
                                            children = {
                                                UI.Label {
                                                    text = "历练探索",
                                                    fontSize = Theme.fontSize.body,
                                                    fontWeight = "bold",
                                                    fontColor = Theme.colors.textGold,
                                                },
                                                UI.Label {
                                                    text = "挂机修炼，获取资源与机缘",
                                                    fontSize = Theme.fontSize.small,
                                                    fontColor = Theme.colors.textSecondary,
                                                },
                                            },
                                        },
                                    },
                                },
                                -- 排行榜入口
                                UI.Panel {
                                    width = "100%",
                                    flexDirection = "row",
                                    alignItems = "center",
                                    gap = 12,
                                    padding = 12,
                                    borderRadius = Theme.radius.md,
                                    backgroundColor = Theme.colors.bgDark,
                                    borderColor = Theme.colors.borderGold,
                                    borderWidth = 1,
                                    cursor = "pointer",
                                    onClick = function(self)
                                        showChancePopup_ = false
                                        Router.EnterState(Router.STATE_RANKING)
                                    end,
                                    children = {
                                        UI.Panel {
                                            width = 36, height = 36,
                                            backgroundImage = Theme.images.iconRanking,
                                            backgroundFit = "contain",
                                            imageTint = Theme.colors.gold,
                                        },
                                        UI.Panel {
                                            flexGrow = 1,
                                            children = {
                                                UI.Label {
                                                    text = "天骄排行",
                                                    fontSize = Theme.fontSize.body,
                                                    fontWeight = "bold",
                                                    fontColor = Theme.colors.textGold,
                                                },
                                                UI.Label {
                                                    text = "查看各榜单排名",
                                                    fontSize = Theme.fontSize.small,
                                                    fontColor = Theme.colors.textSecondary,
                                                },
                                            },
                                        },
                                    },
                                },
                            },
                        }
                    , {}, {
                        onClose = function()
                            showChancePopup_ = false
                            Router.RebuildUI()
                        end,
                    })
                elseif showAttrPopup_ then
                    return BuildAttrPopup(p)
                end
                return nil
            end)(),

            -- 设置弹窗容器（叠在最上层）
            (function()
                local vis = Settings.IsVisible()
                local overlay = UI.Panel {
                    position = "absolute",
                    top = 0, left = 0, right = 0, bottom = 0,
                    pointerEvents = vis and "auto" or "none",
                    children = vis and {
                        Settings.Build(function() Settings.Hide() end),
                    } or {},
                }
                Settings.BindOverlay(overlay)
                return overlay
            end)(),
        },
    }
end

return M
