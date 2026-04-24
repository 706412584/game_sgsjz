-- ============================================================================
-- 《问道长生》炼丹页
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameAlchemy = require("game_alchemy")
local DataItems = require("data_items")
local Toast = require("ui_toast")
local RT    = require("rich_text")

local M = {}

local selectedRecipe = 1

-- ============================================================================
-- 材料槽（显示某丹方所需材料的持有情况）
-- ============================================================================
local function BuildMaterialSlot(matInfo)
    if not matInfo then
        -- 空槽
        return UI.Panel {
            width = 72,
            height = 72,
            borderRadius = Theme.radius.sm,
            backgroundColor = { 40, 35, 28, 120 },
            borderColor = Theme.colors.border,
            borderWidth = 1,
            justifyContent = "center",
            alignItems = "center",
        }
    end

    local enough = matInfo.enough
    return UI.Panel {
        width = 72,
        height = 72,
        borderRadius = Theme.radius.sm,
        backgroundColor = enough and Theme.colors.bgDark or { 60, 30, 30, 150 },
        borderColor = enough and Theme.colors.borderGold or Theme.colors.danger,
        borderWidth = 1,
        justifyContent = "center",
        alignItems = "center",
        gap = 2,
        children = {
            UI.Label {
                text = matInfo.name,
                fontSize = Theme.fontSize.small,
                fontColor = enough and Theme.colors.textLight or Theme.colors.dangerLight,
                textAlign = "center",
            },
            (function()
                local haveColor = enough and "green" or "red"
                return RT.Build(
                    "<c=" .. haveColor .. ">" .. tostring(matInfo.have) .. "</c>/" .. tostring(matInfo.need),
                    Theme.fontSize.tiny, Theme.colors.textSecondary
                )
            end)(),
        },
    }
end

-- ============================================================================
-- 丹方列表项
-- ============================================================================
local function BuildRecipeItem(recipe, idx, isSelected)
    local bg = isSelected and Theme.colors.gold or Theme.colors.bgDark
    local txtColor = isSelected and Theme.colors.btnPrimaryText or Theme.colors.textLight
    local pq = DataItems.PILL_QUALITY[recipe.quality]
    local qualityColor = pq and pq.color or { 180, 180, 180, 255 }
    local qualityLabel = pq and pq.label or "普通"

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        padding = { 10, 12 },
        borderRadius = Theme.radius.sm,
        backgroundColor = bg,
        borderColor = isSelected and Theme.colors.goldDark or Theme.colors.border,
        borderWidth = 1,
        cursor = "pointer",
        onClick = function(self)
            selectedRecipe = idx
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                flexShrink = 1,
                gap = 2,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = recipe.name,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = isSelected and Theme.colors.btnPrimaryText or qualityColor,
                            },
                            UI.Label {
                                text = "[" .. qualityLabel .. "]",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = isSelected and { 80, 70, 50, 200 } or qualityColor,
                            },
                        },
                    },
                    (function()
                        local rate = recipe.rate or 0
                        local rateTag = rate >= 80 and "<c=green>" or (rate >= 50 and "<c=yellow>" or "<c=red>")
                        local mins = math.floor((recipe.time or 900) / 60)
                        local infoStr = "成功率 " .. rateTag .. rate .. "%</c> | " .. mins .. "分钟"
                        if isSelected then
                            return UI.Label {
                                text = "成功率 " .. rate .. "% | " .. mins .. "分钟",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = { 60, 50, 40, 200 },
                            }
                        end
                        return RT.Build(infoStr, Theme.fontSize.tiny, Theme.colors.textSecondary)
                    end)(),
                },
            },
            UI.Label {
                text = isSelected and "已选" or "选择",
                fontSize = Theme.fontSize.small,
                fontColor = isSelected and { 60, 50, 40, 200 } or Theme.colors.gold,
            },
        },
    }
end

-- ============================================================================
-- 炼丹进度条视图（倒计时中展示）
-- ============================================================================
local function BuildAlchemyProgressView(p)
    local prog = GameAlchemy.GetAlchemyProgress()
    if not prog then return UI.Panel {} end

    local remaining = math.max(0, prog.duration - prog.elapsed)
    local mins = math.floor(remaining / 60)
    local secs = math.floor(remaining % 60)
    local timeStr = string.format("%d:%02d", mins, secs)
    local pct = math.floor(prog.progress * 100)
    local pctStr = tostring(pct)

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),
        -- 炼丹炉区域（炼制中状态）
        UI.Panel {
            width = "100%",
            height = 120,
            borderRadius = Theme.radius.lg,
            backgroundColor = Theme.colors.bgDark,
            borderColor = Theme.colors.gold,
            borderWidth = 2,
            justifyContent = "center",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Panel {
                    width = 48,
                    height = 48,
                    backgroundImage = Theme.images.iconAlchemy,
                    backgroundFit = "contain",
                },
                UI.Label {
                    text = "炼丹中...",
                    fontSize = Theme.fontSize.heading,
                    fontWeight = "bold",
                    fontColor = Theme.colors.gold,
                },
                UI.Label {
                    text = prog.recipeName,
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textLight,
                },
            },
        },

        -- 倒计时
        UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 4,
            marginTop = 12,
            children = {
                UI.Label {
                    text = "剩余时间",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = timeStr,
                    fontSize = 32,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textGold,
                },
            },
        },

        -- 进度条
        UI.Panel {
            width = "100%",
            marginTop = 8,
            gap = 4,
            children = {
                -- 进度条轨道
                UI.Panel {
                    width = "100%",
                    height = 20,
                    borderRadius = 10,
                    backgroundColor = { 30, 25, 18, 200 },
                    borderColor = Theme.colors.border,
                    borderWidth = 1,
                    overflow = "hidden",
                    children = {
                        -- 填充条
                        UI.Panel {
                            width = pctStr .. "%",
                            height = "100%",
                            borderRadius = 10,
                            backgroundColor = Theme.colors.gold,
                        },
                    },
                },
                -- 百分比文字
                UI.Panel {
                    width = "100%",
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = pctStr .. "%",
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            fontColor = Theme.colors.textGold,
                        },
                    },
                },
            },
        },

        -- 丹方信息卡片
        Comp.BuildCardPanel(prog.recipeName, {
            UI.Label {
                text = "炼制中，请耐心等待...",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.successLight,
                width = "100%",
            },
            Comp.BuildStatRow("总时长", prog.duration .. "秒"),
            Comp.BuildStatRow("已用时", math.floor(prog.elapsed) .. "秒"),
            Comp.BuildStatRow("进度", pctStr .. "%"),
        }),

        -- 取消按钮
        Comp.BuildSecondaryButton("取消炼制", function()
            local ok, msg = GameAlchemy.CancelAlchemy()
            Toast.Show(msg, { variant = ok and "info" or "error" })
        end),
        UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 4,
            children = {
                UI.Label {
                    text = "取消炼制不消耗材料",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.textSecondary,
                },
            },
        },
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

-- ============================================================================
-- 页面构建
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 炼丹进行中 → 显示进度条视图
    if GameAlchemy.IsAlchemyActive() then
        return BuildAlchemyProgressView(p)
    end

    local recipes = GameAlchemy.GetAllRecipes()
    if #recipes == 0 then
        return Comp.BuildPageShell("home", p, {
            UI.Label {
                text = "暂无可用丹方",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
        }, Router.HandleNavigate)
    end
    if selectedRecipe > #recipes then selectedRecipe = 1 end
    local sel = recipes[selectedRecipe]

    -- 材料持有情况
    local matInfos = GameAlchemy.CheckMaterials(sel.id)
    local matSlots = {}
    for _, mi in ipairs(matInfos) do
        matSlots[#matSlots + 1] = BuildMaterialSlot(mi)
    end

    -- 检查能否炼制
    local canDo, cantReason = GameAlchemy.CanAlchemy(sel.id)

    -- 气运加成提示
    local fortune = p.fortune or "普通"
    local fortuneText = "无"
    if fortune == "小吉" then fortuneText = "+5%"
    elseif fortune == "大吉" then fortuneText = "+10%"
    elseif fortune == "天命" then fortuneText = "+15%"
    elseif fortune == "低迷" then fortuneText = "-5%"
    end

    -- 丹方列表
    local recipeItems = {}
    for i, r in ipairs(recipes) do
        recipeItems[#recipeItems + 1] = BuildRecipeItem(r, i, i == selectedRecipe)
    end

    -- 炼丹等级信息
    local alchemyExp = p.alchemyExp or 0
    local lvInfo = DataItems.GetAlchemyLevel(alchemyExp)
    local expBarPct = 0
    local expText = ""
    if lvInfo.nextExp then
        local cur = alchemyExp - lvInfo.expReq
        local total = lvInfo.nextExp - lvInfo.expReq
        expBarPct = total > 0 and math.floor(cur / total * 100) or 100
        expText = cur .. "/" .. total
    else
        expBarPct = 100
        expText = "已满级"
    end

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),
        -- 炼丹等级栏
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            padding = { 10, 12 },
            borderRadius = Theme.radius.md,
            backgroundColor = Theme.colors.bgDark,
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            gap = 8,
            children = {
                -- 左侧：等级名称
                UI.Panel {
                    gap = 2,
                    children = {
                        UI.Label {
                            text = lvInfo.name,
                            fontSize = Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = "Lv." .. lvInfo.level .. (lvInfo.rateBonus > 0 and ("  成功率+" .. lvInfo.rateBonus .. "%") or ""),
                            fontSize = Theme.fontSize.tiny,
                            fontColor = lvInfo.rateBonus > 0 and Theme.colors.successLight or Theme.colors.textSecondary,
                        },
                    },
                },
                -- 右侧：经验条
                UI.Panel {
                    flexGrow = 1,
                    gap = 2,
                    children = {
                        UI.Panel {
                            width = "100%",
                            height = 10,
                            borderRadius = 5,
                            backgroundColor = { 30, 25, 18, 200 },
                            overflow = "hidden",
                            children = {
                                UI.Panel {
                                    width = tostring(expBarPct) .. "%",
                                    height = "100%",
                                    borderRadius = 5,
                                    backgroundColor = Theme.colors.gold,
                                },
                            },
                        },
                        UI.Panel {
                            width = "100%",
                            alignItems = "flex-end",
                            children = {
                                UI.Label {
                                    text = expText,
                                    fontSize = Theme.fontSize.tiny,
                                    fontColor = Theme.colors.textSecondary,
                                },
                            },
                        },
                    },
                },
            },
        },

        -- 炼丹炉区域
        UI.Panel {
            width = "100%",
            height = 120,
            borderRadius = Theme.radius.lg,
            backgroundColor = Theme.colors.bgDark,
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            justifyContent = "center",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Panel {
                    width = 48,
                    height = 48,
                    backgroundImage = Theme.images.iconAlchemy,
                    backgroundFit = "contain",
                },
                UI.Label {
                    text = "炼 丹 炉",
                    fontSize = Theme.fontSize.heading,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textGold,
                },
                UI.Label {
                    text = "当前: " .. sel.name .. "  成功率 " .. (sel.rate or 0) .. "%",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                },
            },
        },

        -- 材料需求
        Comp.BuildSectionTitle("所需材料"),
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 8,
            children = matSlots,
        },

        -- 丹方详情
        Comp.BuildCardPanel(sel.name, {
            UI.Label {
                text = sel.effect or "",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.successLight,
                width = "100%",
            },
            Comp.BuildStatRow("品质", (DataItems.PILL_QUALITY[sel.quality] and DataItems.PILL_QUALITY[sel.quality].label) or "普通"),
            Comp.BuildStatRow("基础成功率", (sel.rate or 0) .. "%"),
            Comp.BuildStatRow("气运加成", fortuneText, {
                valueColor = fortune == "低迷" and Theme.colors.dangerLight or Theme.colors.successLight
            }),
            Comp.BuildStatRow("炼丹等级加成", lvInfo.rateBonus > 0 and ("+" .. lvInfo.rateBonus .. "%") or "无", {
                valueColor = lvInfo.rateBonus > 0 and Theme.colors.textGold or Theme.colors.textSecondary
            }),
            Comp.BuildStatRow("炼制时间", math.floor((sel.time or 900) / 60) .. "分钟"),
        }),

        -- 开始炼制按钮
        Comp.BuildInkButton(canDo and ("开始炼制 (" .. math.floor((sel.time or 900) / 60) .. "分钟)") or (cantReason or "材料不足"), function()
            if not canDo then
                Toast.Show(cantReason or "无法炼制", { variant = "error" })
                return
            end
            local ok, msg = GameAlchemy.DoAlchemy(sel.id, function(ok2, msg2)
                Toast.Show(msg2, { variant = ok2 and "success" or "error" })
                Router.RebuildUI()
            end)
            if ok then
                Router.RebuildUI()  -- 立即切换到进度条视图
            else
                Toast.Show(msg or "炼制失败", { variant = "error" })
            end
        end, { disabled = not canDo }),

        -- 丹方列表
        Comp.BuildSectionTitle("全部丹方"),
        UI.Panel {
            width = "100%",
            gap = 6,
            children = recipeItems,
        },
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
