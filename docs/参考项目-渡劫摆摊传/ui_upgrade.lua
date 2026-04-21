-- ============================================================================
-- ui_upgrade.lua — 摊位升级 + 修炼境界 + 角色面板 (紧凑布局)
-- 显式突破机制 + 寿元显示
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local HUD = require("ui_hud")
local Particle = require("ui_particle")
local Guide = require("ui_guide")
local Artifact = require("ui_artifact")


local M = {}

local upgradePanel = nil

--- 创建摊位升级卡片 (紧凑: 标题+按钮同行, 属性单行)
local function createStallUpgradeCard()
    local curLevel = State.state.stallLevel
    local curCfg = Config.StallLevels[curLevel]
    local isMax = curLevel >= #Config.StallLevels
    local nextCfg = not isMax and Config.StallLevels[curLevel + 1] or nil
    local hasDiscount = State.HasUpgradeDiscount()
    local upgradeCost = nextCfg and (hasDiscount and math.floor(nextCfg.cost * 0.7) or nextCfg.cost) or 0
    local canUpgrade = nextCfg and State.state.lingshi >= upgradeCost

    if isMax then
        return UI.Panel {
            padding = 4,
            backgroundColor = Config.Colors.panelLight,
            borderRadius = 6,
            borderWidth = 1,
            borderColor = Config.Colors.borderGold,
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            gap = 4,
            children = {
                UI.Panel {
                    alignItems = "center",
                    children = {
                        UI.Label { text = "摊位 Lv" .. curLevel, fontSize = 10, fontColor = Config.Colors.textGold, fontWeight = "bold" },
                        UI.Label { text = "已达最高等级!", fontSize = 9, fontColor = Config.Colors.jade },
                    },
                },
            },
        }
    end

    local btnText = hasDiscount
        and "升级 " .. HUD.FormatNumber(upgradeCost) .. " 灵石 (-30%)"
        or "升级 " .. HUD.FormatNumber(nextCfg.cost) .. " 灵石"

    return UI.Panel {
        padding = 4,
        gap = 2,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = Config.Colors.borderGold,
        children = {
            -- 标题行: 等级 + 升级按钮
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label { text = "摊位 Lv" .. curLevel, fontSize = 11, fontColor = Config.Colors.textGold, fontWeight = "bold" },
                    UI.Panel { flexGrow = 1 },  -- spacer
                    UI.Button {
                        text = btnText,
                        fontSize = 9,
                        height = 24,
                        paddingHorizontal = 8,
                        disabled = not canUpgrade,
                        backgroundColor = canUpgrade
                            and (hasDiscount and Config.Colors.purpleDark or Config.Colors.jadeDark)
                            or { 60, 60, 70, 200 },
                        textColor = canUpgrade and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                        borderRadius = 8,
                        borderWidth = canUpgrade and 1 or 0,
                        borderColor = canUpgrade and Config.Colors.jade or nil,
                        onClick = function(self)
                            if State.serverMode then
                                local GameCore = require("game_core")
                                GameCore.SendGameAction("stall_upgrade")
                            else
                                local discount = State.HasUpgradeDiscount() and 0.3 or 0
                                if State.UpgradeStall(discount) then
                                    if discount > 0 then
                                        State.UseUpgradeDiscount()
                                    end
                                    local GameCore = require("game_core")
                                    GameCore.AddLog("摊位升级至 Lv" .. State.state.stallLevel .. "!", Config.Colors.jade)
                                    UI.Toast.Show("摊位升级成功!", { variant = "success", duration = 2 })
                                else
                                    UI.Toast.Show("灵石不足!", { variant = "warning", duration = 2 })
                                end
                            end
                        end,
                    },
                },
            },
            -- 属性对比行
            UI.Panel {
                flexDirection = "row",
                gap = 6,
                justifyContent = "center",
                children = {
                    UI.Label {
                        text = "队列 " .. curCfg.queueLimit .. "→" .. nextCfg.queueLimit,
                        fontSize = 8,
                        fontColor = Config.Colors.textSecond,
                    },
                    UI.Label {
                        text = "栏位 " .. curCfg.slots .. "→" .. nextCfg.slots,
                        fontSize = 8,
                        fontColor = Config.Colors.textSecond,
                    },
                    UI.Label {
                        text = "速度 " .. string.format("%.1fx", curCfg.speedMul) .. "→" .. string.format("%.1fx", nextCfg.speedMul),
                        fontSize = 8,
                        fontColor = Config.Colors.textSecond,
                    },
                },
            },
        },
    }
end

--- 显示称号加成详情弹窗
local function showTitleDetailModal()
    local realmTitle = Config.GetRealmTitle(State.state.highestRealmEver or 1)
    local rankTitle = Config.GetRankTitle(State.state.myTodayRank)
    local totalBonus = State.GetTitleBonus()
    local totalPct = math.floor((totalBonus - 1.0) * 100 + 0.5)

    local modal = UI.Modal {
        title = "称号加成",
        size = "sm",
        onClose = function(self) self:Destroy() end,
    }

    local rows = {}

    -- 境界称号
    table.insert(rows, UI.Label {
        text = "-- 境界称号 --",
        fontSize = 10,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    })
    if realmTitle then
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            paddingVertical = 4,
            paddingHorizontal = 6,
            backgroundColor = { 40, 35, 60, 200 },
            borderRadius = 6,
            children = {
                UI.Label {
                    text = realmTitle.title,
                    fontSize = 13,
                    fontColor = realmTitle.color,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "灵石收入 +" .. math.floor(realmTitle.bonus * 100 + 0.5) .. "%",
                    fontSize = 11,
                    fontColor = Config.Colors.textGold,
                },
            },
        })
        table.insert(rows, UI.Label {
            text = "达到对应境界后永久获得，转生不丢失",
            fontSize = 8,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
        })
    else
        table.insert(rows, UI.Label {
            text = "尚未获得（达到筑基境界后解锁）",
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
        })
    end

    -- 分隔
    table.insert(rows, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Config.Colors.border,
        marginVertical = 4,
    })

    -- 排行称号
    table.insert(rows, UI.Label {
        text = "-- 排行称号 --",
        fontSize = 10,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    })
    if rankTitle then
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            paddingVertical = 4,
            paddingHorizontal = 6,
            backgroundColor = { 40, 35, 60, 200 },
            borderRadius = 6,
            children = {
                UI.Label {
                    text = rankTitle.title,
                    fontSize = 13,
                    fontColor = rankTitle.color,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "灵石收入 +" .. math.floor(rankTitle.bonus * 100 + 0.5) .. "%",
                    fontSize = 11,
                    fontColor = Config.Colors.textGold,
                },
            },
        })
        table.insert(rows, UI.Label {
            text = "今日排行第" .. (State.state.myTodayRank or "?") .. "名，每日刷新",
            fontSize = 8,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
        })
    else
        table.insert(rows, UI.Label {
            text = "未上榜（进入今日排行榜前30名可获得）",
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
        })
    end

    -- 分隔
    table.insert(rows, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Config.Colors.border,
        marginVertical = 4,
    })

    -- 排行称号一览表
    table.insert(rows, UI.Label {
        text = "排行称号一览",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    })
    for _, rt in ipairs(Config.RankTitles) do
        local isActive = rankTitle and rankTitle.title == rt.title
        table.insert(rows, UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            width = "100%",
            paddingVertical = 2,
            paddingHorizontal = 6,
            backgroundColor = isActive and { 50, 45, 70, 200 } or nil,
            borderRadius = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    children = {
                        UI.Label {
                            text = isActive and ">" or " ",
                            fontSize = 9, fontColor = Config.Colors.textGold, width = 8,
                        },
                        UI.Label {
                            text = rt.title,
                            fontSize = 10,
                            fontColor = rt.color,
                            fontWeight = isActive and "bold" or nil,
                        },
                        UI.Label {
                            text = "前" .. rt.rank .. "名",
                            fontSize = 8,
                            fontColor = Config.Colors.textSecond,
                        },
                    },
                },
                UI.Label {
                    text = "+" .. math.floor(rt.bonus * 100 + 0.5) .. "%",
                    fontSize = 10,
                    fontColor = Config.Colors.textGold,
                },
            },
        })
    end

    -- 总计
    table.insert(rows, UI.Panel {
        width = "100%", height = 1,
        backgroundColor = Config.Colors.border,
        marginVertical = 4,
    })
    table.insert(rows, UI.Panel {
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 6,
        width = "100%",
        children = {
            UI.Label {
                text = "当前总加成:",
                fontSize = 11,
                fontColor = Config.Colors.textPrimary,
            },
            UI.Label {
                text = totalPct > 0 and ("灵石收入 +" .. totalPct .. "%") or "无加成",
                fontSize = 13,
                fontColor = totalPct > 0 and Config.Colors.textGold or Config.Colors.textSecond,
                fontWeight = "bold",
            },
        },
    })

    modal:AddContent(UI.Panel {
        width = "100%",
        padding = 10,
        gap = 4,
        children = rows,
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "关闭",
                fontSize = 12, width = 60, height = 30,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textPrimary,
                borderRadius = 8,
                onClick = function(self) modal:Close() end,
            },
        },
    })

    modal:Open()
end

--- 创建角色面板(境界+寿元+修为+突破)
local function createCharacterPanel()
    local realmIdx = State.GetRealmIndex()
    local realmCfg = Config.Realms[realmIdx]
    local isMax = realmIdx >= #Config.Realms
    local nextRealm = not isMax and Config.Realms[realmIdx + 1] or nil
    local curXiuwei = realmCfg.xiuwei
    local lifespan = math.floor(State.state.lifespan)

    local realmTitle = Config.GetRealmTitle(State.state.highestRealmEver or 1)
    local rankTitle = Config.GetRankTitle(State.state.myTodayRank)
    local titleBonus = State.GetTitleBonus()
    local bonusPct = math.floor((titleBonus - 1.0) * 100 + 0.5)

    local children = {}

    -- Row 1: 境界名 + 寿元
    table.insert(children, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Label { text = "境界", fontSize = 11, fontColor = Config.Colors.purple, fontWeight = "bold" },
                    UI.Label {
                        text = realmCfg.name .. " (" .. realmIdx .. "/" .. #Config.Realms .. ")",
                        fontSize = 10,
                        fontColor = Config.Colors.textPrimary,
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                children = {
                    UI.Label { text = "寿元:", fontSize = 9, fontColor = Config.Colors.textSecond },
                    UI.Label {
                        text = HUD.FormatNumber(lifespan) .. "年",
                        fontSize = 10,
                        fontColor = lifespan <= 10 and Config.Colors.red or Config.Colors.orange,
                        fontWeight = "bold",
                    },
                },
            },
        },
    })

    -- Row 1.5: 称号展示(可点击查看详情)
    local hasTitles = realmTitle or rankTitle
    if hasTitles then
        local titleParts = {}
        if realmTitle then
            table.insert(titleParts, UI.Label {
                text = realmTitle.title,
                fontSize = 10,
                fontColor = realmTitle.color,
                fontWeight = "bold",
            })
        end
        if rankTitle then
            table.insert(titleParts, UI.Label {
                text = rankTitle.title,
                fontSize = 10,
                fontColor = rankTitle.color,
                fontWeight = "bold",
            })
        end
        if bonusPct > 0 then
            table.insert(titleParts, UI.Label {
                text = "(+" .. bonusPct .. "%)",
                fontSize = 9,
                fontColor = Config.Colors.textGold,
            })
        end
        table.insert(titleParts, UI.Label {
            text = "详情>",
            fontSize = 8,
            fontColor = Config.Colors.blue,
        })

        table.insert(children, UI.Button {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 4,
            width = "100%",
            height = 22,
            backgroundColor = { 40, 35, 60, 150 },
            borderRadius = 4,
            borderWidth = 1,
            borderColor = { 80, 70, 120, 100 },
            onClick = function(self)
                showTitleDetailModal()
            end,
            children = titleParts,
        })
    end

    -- Row 2: 修为进度条
    if nextRealm then
        local progress = (State.state.xiuwei - curXiuwei) / (nextRealm.xiuwei - curXiuwei)
        progress = math.min(1, math.max(0, progress))

        table.insert(children, UI.ProgressBar {
            value = progress,
            height = 8,
            variant = "primary",
            showLabel = true,
        })

        -- Row 3: 修为数值 + 下一境界信息
        table.insert(children, UI.Panel {
            flexDirection = "row",
            justifyContent = "space-between",
            children = {
                UI.Label {
                    text = "修为 " .. HUD.FormatNumber(State.state.xiuwei) .. "/" .. HUD.FormatNumber(nextRealm.xiuwei),
                    fontSize = 8,
                    fontColor = Config.Colors.textSecond,
                },
                UI.Label {
                    text = "下一:" .. nextRealm.name .. " 寿+" .. nextRealm.lifespan .. "年",
                    fontSize = 8,
                    fontColor = Config.Colors.purple,
                    flexShrink = 1,
                    textAlign = "right",
                },
            },
        })

        -- Row 4: 炼化灵石按钮行
        local refineCost, refineGain, canRefine = State.GetRefineInfo()
        local autoRefineOn = State.state.autoRefine
        local refineBtn = UI.Button {
            text = "炼化(" .. HUD.FormatNumber(refineCost) .. "→+" .. HUD.FormatNumber(refineGain) .. "修为)",
            fontSize = 9,
            height = 28,
            flexGrow = 1,
            flexBasis = 0,
            disabled = not canRefine,
            backgroundColor = canRefine and Config.Colors.goldDark or { 60, 60, 70, 200 },
            textColor = canRefine and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 6,
            onClick = function(self)
                if State.serverMode then
                    local GameCore = require("game_core")
                    GameCore.SendGameAction("refine")
                else
                    local ok, cost, gain = State.RefineLingshi()
                    if ok then
                        local GameCore = require("game_core")
                        GameCore.AddLog("炼化灵石! -" .. cost .. "灵石 修为+" .. gain, Config.Colors.textGold)
                        GameCore.AddFloatingText("修为+" .. gain, Config.Colors.purple)
                        Particle.Emit(12, { 220, 180, 60 })
                    else
                        UI.Toast.Show("灵石不足! 需要" .. refineCost .. "灵石", { variant = "warning", duration = 2 })
                    end
                end
                Guide.NotifyAction("refine_btn")
            end,
        }
        -- 注册炼化按钮为引导目标
        Guide.RegisterTarget("refine_btn", refineBtn)
        table.insert(children, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 3,
            marginTop = 2,
            children = {
                refineBtn,
                -- 一键炼化
                UI.Button {
                    text = "一键",
                    fontSize = 9,
                    height = 28,
                    width = 42,
                    disabled = not canRefine,
                    backgroundColor = canRefine and Config.Colors.purpleDark or { 60, 60, 70, 200 },
                    textColor = canRefine and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 6,
                    onClick = function(self)
                        if State.serverMode then
                            local GameCore = require("game_core")
                            GameCore.SendGameAction("refine_batch")
                        else
                            local totalCost, totalGain, count = 0, 0, 0
                            while true do
                                local ok, cost, gain = State.RefineLingshi()
                                if not ok then break end
                                totalCost = totalCost + cost
                                totalGain = totalGain + gain
                                count = count + 1
                                if nextRealm and State.state.xiuwei >= nextRealm.xiuwei then break end
                            end
                            if count > 0 then
                                local GameCore = require("game_core")
                                GameCore.AddLog("一键炼化x" .. count .. "! -" .. HUD.FormatNumber(totalCost) .. "灵石 修为+" .. HUD.FormatNumber(totalGain), Config.Colors.textGold)
                                GameCore.AddFloatingText("修为+" .. HUD.FormatNumber(totalGain), Config.Colors.purple)
                                Particle.Emit(math.min(count * 5, 40), { 180, 130, 220 })
                                UI.Toast.Show("炼化x" .. count .. " 修为+" .. HUD.FormatNumber(totalGain), { variant = "success", duration = 1.5 })
                            else
                                UI.Toast.Show("灵石不足!", { variant = "warning", duration = 2 })
                            end
                        end
                    end,
                },
                -- 自动炼化开关
                UI.Button {
                    text = autoRefineOn and "自动:开" or "自动:关",
                    fontSize = 9,
                    height = 28,
                    width = 52,
                    backgroundColor = autoRefineOn and Config.Colors.jade or { 60, 60, 70, 200 },
                    textColor = autoRefineOn and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 6,
                    borderWidth = 1,
                    borderColor = autoRefineOn and Config.Colors.jade or Config.Colors.border,
                    onClick = function(self)
                        local GameCore = require("game_core")
                        if State.serverMode then
                            GameCore.SendGameAction("toggle_refine")
                        else
                            State.state.autoRefine = not State.state.autoRefine
                            if State.state.autoRefine then
                                GameCore.AddLog("自动炼化已开启", Config.Colors.jade)
                                UI.Toast.Show("自动炼化已开启", { variant = "success", duration = 1.5 })
                            else
                                GameCore.AddLog("自动炼化已关闭", Config.Colors.textSecond)
                                UI.Toast.Show("自动炼化已关闭", { variant = "info", duration = 1.5 })
                            end
                            State.Save()
                        end
                    end,
                },
            },
        })

        -- Row 5: 突破按钮
        local hasBreakDiscount = State.HasUpgradeDiscount()
        local breakCost = hasBreakDiscount and math.floor(nextRealm.breakthroughCost * 0.7) or nextRealm.breakthroughCost
        local canBreak, reason = State.CanBreakthrough()
        local xiuweiEnough = State.state.xiuwei >= nextRealm.xiuwei
        local lingshiEnough = State.state.lingshi >= breakCost

        local costText = HUD.FormatNumber(breakCost) .. "灵石"
        if hasBreakDiscount then
            costText = costText .. " (减免30%)"
        end
        local needDujie = (realmIdx >= Config.DUJIE_MIN_REALM)
        local isTribulationRealm = (realmIdx == 9)  -- 渡劫期: 走 Boss 战流程
        local btnLabel = "突破至" .. nextRealm.name .. "(" .. costText .. ")"
        local statusParts = {}
        if not xiuweiEnough then
            table.insert(statusParts, "修为差" .. HUD.FormatNumber(nextRealm.xiuwei - State.state.xiuwei))
        end
        if not lingshiEnough then
            table.insert(statusParts, "灵石差" .. HUD.FormatNumber(breakCost - State.state.lingshi))
        end

        -- 突破材料需求显示
        local matReqs = Config.BreakthroughMaterials[realmIdx + 1]
        if matReqs then
            local matChildren = {}
            local allMatOk = true
            for _, req in ipairs(matReqs) do
                local have = (State.state.collectibles or {})[req.id] or 0
                local cfg = Config.GetCollectibleById(req.id)
                local name = cfg and cfg.name or req.id
                local enough = have >= req.count
                if not enough then
                    allMatOk = false
                    table.insert(statusParts, name .. "不足(需" .. req.count .. ",有" .. have .. ")")
                end
                table.insert(matChildren, UI.Label {
                    text = name .. " " .. have .. "/" .. req.count,
                    fontSize = 9,
                    fontColor = enough and Config.Colors.textGreen or Config.Colors.red,
                    fontWeight = "bold",
                })
            end
            table.insert(children, UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "center",
                alignItems = "center",
                gap = 12,
                padding = 4,
                backgroundColor = { 50, 40, 60, 200 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 120, 80, 180, 150 },
                marginBottom = 2,
                children = (function()
                    local items = {}
                    table.insert(items, UI.Label {
                        text = "突破材料:",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                    })
                    for _, c in ipairs(matChildren) do
                        table.insert(items, c)
                    end
                    return items
                end)(),
            })
        end

        if isTribulationRealm then
            -- 渡劫期: 专属天劫 Boss 战入口
            local tribActive = State.state.tribulation_active
            local tribWon    = State.state.tribulation_won
            local tribReady  = xiuweiEnough  -- 修为满足即可进入
            local tribBtnText, tribBtnBg
            if tribActive then
                tribBtnText = "继续渡劫"
                tribBtnBg   = { 180, 100, 50, 230 }
            elseif tribWon then
                tribBtnText = "飞升仙界"
                tribBtnBg   = { 180, 140, 40, 230 }
            else
                tribBtnText = tribReady and "挑战天劫" or "挑战天劫(修为不足)"
                tribBtnBg   = tribReady and { 120, 50, 180, 230 } or { 60, 50, 80, 200 }
            end
            table.insert(children, UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                children = {
                    UI.Button {
                        text = tribBtnText,
                        fontSize = 12,
                        height = 34,
                        flexGrow = 1,
                        disabled = not (tribActive or tribWon or tribReady),
                        backgroundColor = tribBtnBg,
                        textColor = (tribActive or tribWon or tribReady)
                            and { 255, 240, 200, 255 } or Config.Colors.textSecond,
                        borderRadius = 6,
                        fontWeight = "bold",
                        onClick = function(self)
                            local Tribulation = require("ui_tribulation")
                            Tribulation.Show()
                        end,
                    },
                },
            })
        else
        table.insert(children, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            children = {
                UI.Button {
                    text = btnLabel,
                    fontSize = 10,
                    height = 28,
                    flexGrow = 1,
                    disabled = not canBreak,
                    backgroundColor = canBreak
                        and (hasBreakDiscount and Config.Colors.purpleDark or Config.Colors.jadeDark)
                        or { 60, 60, 70, 200 },
                    textColor = canBreak and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 6,
                    onClick = function(self)
                        if State.serverMode then
                            local GameCore = require("game_core")
                            if needDujie then
                                -- 先预检查次数和费用,付费时弹确认
                                GameCore.SendGameAction("dujie_check")
                                local function onCheckResult(data)
                                    State.Off("dujie_check_result", onCheckResult)
                                    if data.freeLeft > 0 then
                                        -- 还有免费次数,直接开始
                                        GameCore.SendGameAction("dujie_start")
                                    elseif data.paidLeft > 0 then
                                        -- 免费次数已用完,需付费,弹确认框
                                        UI.Modal.Confirm({
                                            title = "渡劫确认",
                                            message = "今日免费次数已用完\n本次渡劫需消耗 " .. data.retryCost .. " 灵石\n(剩余付费次数: " .. data.paidLeft .. "次)\n\n当前灵石: " .. HUD.FormatNumber(data.lingshi),
                                            confirmText = "确认渡劫",
                                            cancelText = "取消",
                                            onConfirm = function()
                                                GameCore.SendGameAction("dujie_start")
                                            end,
                                        })
                                    else
                                        UI.Toast.Show("今日渡劫次数已用完", { variant = "warning", duration = 2 })
                                    end
                                end
                                State.On("dujie_check_result", onCheckResult)
                            else
                                GameCore.SendGameAction("breakthrough")
                            end
                        else
                            local ok, failReason = State.Breakthrough()
                            if ok then
                                local newRealm = Config.Realms[State.GetRealmIndex()]
                                local GameCore = require("game_core")
                                GameCore.AddLog("突破成功! 晋升" .. newRealm.name .. "!", Config.Colors.textGold)
                                GameCore.AddFloatingText("突破成功! " .. newRealm.name, Config.Colors.textGold)
                                GameCore.PlaySFX("upgrade")
                                Particle.Emit(50, { 255, 200, 80 })
                                Particle.Emit(30, { 160, 100, 255 })
                                UI.Toast.Show("恭喜突破至" .. newRealm.name .. "! 寿元+" .. newRealm.lifespan .. "年", { variant = "success", duration = 3 })
                            else
                                UI.Toast.Show(failReason, { variant = "warning", duration = 2 })
                            end
                        end
                    end,
                },
            },
        })
        end  -- isTribulationRealm

        -- 不足提示
        if #statusParts > 0 then
            table.insert(children, UI.Label {
                text = table.concat(statusParts, ", "),
                fontSize = 8,
                fontColor = Config.Colors.red,
                textAlign = "center",
                width = "100%",
            })
        end
    else
        table.insert(children, UI.Label {
            text = "已达最高境界! 修为:" .. HUD.FormatNumber(State.state.xiuwei),
            fontSize = 11,
            fontColor = Config.Colors.textGold,
            textAlign = "center",
        })
    end

    -- Row 5: 境界列表 (3列网格)
    table.insert(children, UI.Panel {
        marginTop = 3,
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 2,
        children = (function()
            local cells = {}
            for i, realm in ipairs(Config.Realms) do
                local reached = i <= realmIdx
                local isCurrent = i == realmIdx
                table.insert(cells, UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 2,
                    height = 16,
                    width = "32%",
                    paddingHorizontal = 2,
                    backgroundColor = isCurrent and { 60, 50, 90, 200 } or nil,
                    borderRadius = 3,
                    children = {
                        UI.Label {
                            text = reached and "v" or "-",
                            fontSize = 8,
                            fontColor = reached and Config.Colors.jade or Config.Colors.textSecond,
                            width = 8,
                        },
                        UI.Label {
                            text = realm.name,
                            fontSize = 9,
                            fontColor = isCurrent and Config.Colors.textGold or (reached and Config.Colors.textPrimary or Config.Colors.textSecond),
                            flexGrow = 1,
                        },
                        UI.Label {
                            text = HUD.FormatNumber(realm.xiuwei),
                            fontSize = 7,
                            fontColor = Config.Colors.textSecond,
                        },
                    },
                })
            end
            return cells
        end)(),
    })

    -- Row 6: 当前境界解锁说明
    table.insert(children, UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 4,
        paddingVertical = 2,
        children = {
            UI.Label { text = "当前:", fontSize = 8, fontColor = Config.Colors.textSecond },
            UI.Label { text = realmCfg.unlockDesc, fontSize = 8, fontColor = Config.Colors.jade, flexShrink = 1 },
        },
    })

    return UI.Panel {
        padding = 6,
        gap = 3,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = { 100, 80, 160, 120 },
        children = children,
    }
end

function M.Create()
    upgradePanel = UI.Panel {
        id = "upgrade_page",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        padding = 4,
        gap = 4,
        children = {
            UI.Panel { id = "stall_upgrade_container" },
            UI.Panel { id = "char_name_container" },
            UI.Panel { id = "char_actions_container", width = "100%" },
            UI.Panel {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                overflow = "scroll",
                showScrollbar = false,
                children = {
                    UI.Panel {
                        id = "realm_container",
                        width = "100%",
                        paddingBottom = 50,
                    },
                },
            },
        },
    }
    return upgradePanel
end

function M.Refresh()
    if not upgradePanel then return end

    local stallContainer = upgradePanel:FindById("stall_upgrade_container")
    if stallContainer then
        stallContainer:ClearChildren()
        stallContainer:AddChild(createStallUpgradeCard())
    end

    -- 打坐角色图 + 道号（动态刷新）— 带修炼法阵背景
    local charNameContainer = upgradePanel:FindById("char_name_container")
    if charNameContainer then
        charNameContainer:ClearChildren()

        -- 获取当前境界名
        local realmIdx = State.GetRealmIndex()
        local realmCfg = Config.Realms[realmIdx]

        charNameContainer:AddChild(UI.Panel {
            width = "100%",
            alignItems = "center",
            justifyContent = "center",
            overflow = "hidden",
            borderRadius = 10,
            -- 法阵背景图
            backgroundImage = Config.Images.char_realm_bg,
            backgroundFit = "cover",
            paddingVertical = 10,
            gap = 2,
            children = {
                -- 半透明遮罩层，灰蒙蒙的雾气感
                UI.Panel {
                    position = "absolute",
                    width = "100%", height = "100%",
                    backgroundColor = { 30, 28, 40, 170 },
                },
                -- 打坐角色图（放大）
                UI.Panel {
                    backgroundImage = State.state.playerGender == "female"
                        and Config.Images.char_meditate_female
                        or Config.Images.char_meditate,
                    backgroundFit = "contain",
                    width = 130, height = 130,
                },
                -- 道号
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    justifyContent = "center",
                    gap = 4,
                    children = {
                        UI.Label {
                            text = State.HasPlayerName() and State.GetDisplayName() or "无名散修",
                            fontSize = 14,
                            fontColor = Config.Colors.textGold,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = State.state.playerGender == "female" and "女修" or "男修",
                            fontSize = 9,
                            fontColor = State.state.playerGender == "female"
                                and Config.Colors.purple or Config.Colors.jade,
                        },
                    },
                },
                -- 当前境界名（装饰性大字）
                UI.Label {
                    text = realmCfg.name,
                    fontSize = 11,
                    fontColor = { 180, 160, 220, 200 },
                    textAlign = "center",
                },
            },
        })
    end

    -- 角色快捷按钮行 (法宝 + 储物 + 风水 + 丹药)
    local actionsContainer = upgradePanel:FindById("char_actions_container")
    if actionsContainer then
        actionsContainer:ClearChildren()
        actionsContainer:AddChild(UI.Panel {
            flexDirection = "row",
            justifyContent = "center",
            gap = 8,
            width = "100%",
            children = {
                UI.Button {
                    text = "法宝",
                    fontSize = 10,
                    height = 28,
                    paddingHorizontal = 15,
                    backgroundColor = { 60, 45, 90, 230 },
                    textColor = Config.Colors.purple,
                    borderRadius = 8,
                    borderWidth = 1,
                    borderColor = Config.Colors.purple,
                    onClick = function(self)
                        Artifact.Open()
                    end,
                },
                UI.Button {
                    text = "储物",
                    fontSize = 10,
                    height = 28,
                    paddingHorizontal = 15,
                    backgroundColor = { 45, 60, 55, 230 },
                    textColor = Config.Colors.jade,
                    borderRadius = 8,
                    borderWidth = 1,
                    borderColor = Config.Colors.jade,
                    onClick = function(self)
                        local Storage = require("ui_storage")
                        Storage.Open()
                    end,
                },
                UI.Button {
                    text = "风水",
                    fontSize = 10,
                    height = 28,
                    paddingHorizontal = 15,
                    backgroundColor = { 40, 50, 80, 230 },
                    textColor = Config.Colors.blue,
                    borderRadius = 8,
                    borderWidth = 1,
                    borderColor = Config.Colors.blue,
                    onClick = function(self)
                        require("ui_fengshui").ShowFengshuiModal()
                    end,
                },
                UI.Button {
                    text = "聚宝阁",
                    fontSize = 10,
                    height = 28,
                    paddingHorizontal = 15,
                    backgroundColor = { 70, 50, 30, 230 },
                    textColor = Config.Colors.orange,
                    borderRadius = 8,
                    borderWidth = 1,
                    borderColor = Config.Colors.orange,
                    onClick = function(self)
                        require("ui_pill_shop").ShowPillShopModal()
                    end,
                },
            },
        })
    end

    local realmContainer = upgradePanel:FindById("realm_container")
    if realmContainer then
        realmContainer:ClearChildren()
        realmContainer:AddChild(createCharacterPanel())
    end
end

--- 获取角色图中心在屏幕中的比例坐标 (用于打坐粒子定位)
-- @return number cx (0~1), number cy (0~1)  屏幕比例坐标
function M.GetCharCenterRatio()
    if not upgradePanel then return 0.5, 0.33 end
    local container = upgradePanel:FindById("char_name_container")
    if not container then return 0.5, 0.33 end

    local ax, ay = container:GetAbsolutePosition()
    local w, h = container:GetComputedSize()

    local dpr = graphics:GetDPR()
    local sw = graphics:GetWidth() / dpr
    local sh = graphics:GetHeight() / dpr

    if sw <= 0 or sh <= 0 then return 0.5, 0.33 end

    local cx = (ax + w * 0.5) / sw
    local cy = (ay + h * 0.45) / sh  -- 略偏上，对准角色身体中心
    return cx, cy
end

return M
