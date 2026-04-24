-- ============================================================================
-- 《问道长生》灵宠页面（血脉进化版）
-- 功能：灵宠列表、出战/召回、升级、血脉觉醒、天赋、羁绊、化形、分解
-- 数据模型：UID 实例制，所有操作基于 pet.uid
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GamePet = require("game_pet")
local DataPets = require("data_pets")
local DataItems = require("data_items")
local Toast = require("ui_toast")
local RT    = require("rich_text")

local M = {}

-- 页面状态
local selectedPetUid_ = nil
local showDecomposeConfirm_ = false

-- ============================================================================
-- 元素与共鸣标签
-- ============================================================================
local ELEM_LABELS = { metal = "金", wood = "木", water = "水", fire = "火", earth = "土" }
local ELEM_COLORS = {
    metal = { 255, 215, 0 }, wood = { 34, 180, 34 },
    water = { 30, 144, 255 }, fire = { 255, 80, 20 }, earth = { 160, 130, 80 },
}
local ELEM_RT_COLORS = {
    metal = "yellow", wood = "green", water = "blue", fire = "orange", earth = "gold",
}

-- ============================================================================
-- 血脉标签组件
-- ============================================================================
local function BuildBloodlineTag(bloodline, opts)
    local bl = DataPets.BLOODLINE[bloodline]
    if not bl then return nil end
    local c = bl.color
    return UI.Panel {
        paddingHorizontal = 6, paddingVertical = 1,
        borderRadius = 3,
        backgroundColor = { c[1], c[2], c[3], 40 },
        borderColor = c, borderWidth = 1,
        children = {
            UI.Label {
                text = bl.label,
                fontSize = (opts and opts.fontSize) or 10,
                fontColor = c,
            },
        },
    }
end

-- ============================================================================
-- 灵宠卡片（列表项）
-- ============================================================================
local function BuildPetCard(pet)
    local isSelected = (pet.uid == selectedPetUid_)
    local blColor = pet.bloodlineColor

    -- 觉醒简要标记
    local awakenText = ""
    if pet.awakenStage > 0 then
        local stageInfo = DataPets.AWAKEN_STAGES[pet.awakenStage]
        awakenText = "  " .. (stageInfo and stageInfo.name or ("觉醒+" .. pet.awakenStage))
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        backgroundColor = isSelected and { 200, 168, 85, 30 } or Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = isSelected and Theme.colors.gold or Theme.colors.border,
        borderWidth = isSelected and 2 or 1,
        padding = 10,
        gap = 10,
        cursor = "pointer",
        onClick = function(self)
            selectedPetUid_ = (selectedPetUid_ == pet.uid) and nil or pet.uid
            showDecomposeConfirm_ = false
            Router.RebuildUI()
        end,
        children = {
            -- 头像
            UI.Panel {
                width = 64, height = 64,
                borderRadius = 8,
                backgroundColor = { 25, 22, 18, 200 },
                borderColor = blColor,
                borderWidth = 1,
                justifyContent = "center",
                alignItems = "center",
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = 56, height = 56,
                        backgroundImage = pet.image,
                        backgroundFit = "contain",
                    },
                },
            },
            -- 信息区
            UI.Panel {
                flexGrow = 1, flexShrink = 1,
                gap = 3,
                children = {
                    -- 名字 + 血脉 + 出战标记
                    UI.Panel {
                        flexDirection = "row", gap = 6, alignItems = "center",
                        children = {
                            UI.Label {
                                text = pet.name,
                                fontSize = Theme.fontSize.subtitle,
                                fontWeight = "bold",
                                fontColor = blColor or Theme.colors.textLight,
                            },
                            BuildBloodlineTag(pet.bloodline),
                            pet.isActive and UI.Panel {
                                paddingHorizontal = 6, paddingVertical = 1,
                                borderRadius = 3,
                                backgroundColor = { 100, 200, 100, 40 },
                                children = {
                                    UI.Label {
                                        text = "出战中",
                                        fontSize = 10,
                                        fontColor = Theme.colors.success,
                                    },
                                },
                            } or nil,
                            pet.transformed and UI.Panel {
                                paddingHorizontal = 6, paddingVertical = 1,
                                borderRadius = 3,
                                backgroundColor = { 255, 200, 50, 30 },
                                children = {
                                    UI.Label {
                                        text = "已化形",
                                        fontSize = 10,
                                        fontColor = Theme.colors.gold,
                                    },
                                },
                            } or nil,
                        },
                    },
                    -- 等级 + 觉醒 + 技能 + 元素
                    UI.Label {
                        text = "Lv." .. pet.level .. "/" .. pet.maxLevel
                            .. awakenText
                            .. "  " .. pet.skill
                            .. (pet.element and ("  [" .. (ELEM_LABELS[pet.element] or "") .. "]") or ""),
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textGold,
                    },
                    -- 描述
                    UI.Label {
                        text = pet.desc,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textSecondary,
                        flexShrink = 1,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 天赋面板
-- ============================================================================
local function BuildTalentSection(pet)
    local talents = pet.talents or {}
    if #talents == 0 then return nil end

    local TYPE_LABELS = { combat = "战斗", growth = "成长", explore = "探索", support = "辅助" }
    local TYPE_COLORS = {
        combat  = { 255, 100, 100 },
        growth  = { 100, 200, 100 },
        explore = { 100, 160, 255 },
        support = { 200, 170, 100 },
    }

    local children = {
        UI.Label {
            text = "天赋 (" .. #talents .. ")",
            fontSize = Theme.fontSize.small,
            fontWeight = "bold",
            fontColor = Theme.colors.textGold,
            marginBottom = 2,
        },
    }

    for _, t in ipairs(talents) do
        local tc = TYPE_COLORS[t.type] or Theme.colors.textSecondary
        children[#children + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row", gap = 6, alignItems = "center",
            paddingVertical = 2,
            children = {
                UI.Panel {
                    paddingHorizontal = 4, paddingVertical = 1,
                    borderRadius = 2,
                    backgroundColor = { tc[1], tc[2], tc[3], 30 },
                    children = {
                        UI.Label {
                            text = TYPE_LABELS[t.type] or "?",
                            fontSize = 9,
                            fontColor = tc,
                        },
                    },
                },
                UI.Label {
                    text = t.name,
                    fontSize = Theme.fontSize.small,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textLight,
                },
                UI.Label {
                    text = t.desc,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.textSecondary,
                    flexShrink = 1,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 35, 30, 25, 200 },
        borderRadius = Theme.radius.sm,
        padding = Theme.spacing.sm,
        gap = 2,
        children = children,
    }
end

-- ============================================================================
-- 羁绊面板
-- ============================================================================
local function BuildBondSection(pet)
    local bondInfo = pet.bondInfo
    if not bondInfo then return nil end

    local bondValue = pet.bond or 0
    -- 进度条（到下一级）
    local pctBar = nil
    if bondInfo.nextBondNeeded then
        local range = bondInfo.nextBondNeeded - bondInfo.bondNeeded
        local progress = bondValue - bondInfo.bondNeeded
        local pct = range > 0 and math.min(progress / range, 1) or 0
        pctBar = UI.Panel {
            width = "100%", height = 6,
            borderRadius = 3,
            backgroundColor = { 50, 45, 35, 255 },
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = tostring(math.floor(pct * 100)) .. "%",
                    height = "100%",
                    borderRadius = 3,
                    backgroundColor = { 200, 170, 100, 255 },
                },
            },
        }
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = { 35, 30, 25, 200 },
        borderRadius = Theme.radius.sm,
        padding = Theme.spacing.sm,
        gap = 4,
        children = {
            Comp.BuildStatRow("羁绊", bondInfo.name .. " (Lv." .. bondInfo.level .. ")",
                { valueColor = Theme.colors.gold }),
            bondInfo.statBonus > 0 and Comp.BuildStatRow("属性加成", "+" .. math.floor(bondInfo.statBonus * 100) .. "%",
                { valueColor = Theme.colors.accent }) or nil,
            pctBar,
            bondInfo.nextBondNeeded and UI.Label {
                text = "进度: " .. bondValue .. " / " .. bondInfo.nextBondNeeded,
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
                alignSelf = "flex-end",
            } or UI.Label {
                text = "羁绊已圆满",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.gold,
                alignSelf = "flex-end",
            },
        },
    }
end

-- ============================================================================
-- 分解确认弹窗
-- ============================================================================
local function BuildDecomposeConfirm(pet)
    local yieldInfo = GamePet.GetDecomposeYield(pet.uid)
    local yieldLines = {}
    if yieldInfo then
        if yieldInfo.lingshi and yieldInfo.lingshi > 0 then
            yieldLines[#yieldLines + 1] = "灵石 x" .. yieldInfo.lingshi
        end
        if yieldInfo.jingxue and yieldInfo.jingxue > 0 then
            yieldLines[#yieldLines + 1] = "灵兽精血 x" .. yieldInfo.jingxue
        end
    end
    local yieldText = #yieldLines > 0 and table.concat(yieldLines, "、") or "无"

    return Comp.Dialog(
        "分解确认",
        UI.Panel {
            width = "100%", gap = 8, alignItems = "center",
            children = {
                UI.Label {
                    text = "确定要分解 " .. pet.name .. " 吗？",
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textLight,
                    textAlign = "center",
                },
                UI.Label {
                    text = "此操作不可撤销！",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.danger,
                    textAlign = "center",
                },
                Comp.BuildStatRow("预计获得", yieldText, { valueColor = Theme.colors.gold }),
            },
        },
        {
            { text = "取消", onClick = function()
                showDecomposeConfirm_ = false
                Router.RebuildUI()
            end },
            { text = "确认分解", primary = true, onClick = function()
                showDecomposeConfirm_ = false
                GamePet.DoDecompose(pet.uid, function(ok, msg)
                    Toast.Show(msg, { variant = ok and "success" or "error" })
                    if ok then selectedPetUid_ = nil end
                    Router.RebuildUI()
                end)
            end },
        },
        { onClose = function()
            showDecomposeConfirm_ = false
            Router.RebuildUI()
        end }
    )
end

-- ============================================================================
-- 详情面板
-- ============================================================================
local function BuildDetailPanel(pet)
    local blColor = pet.bloodlineColor

    -- 经验条
    local expBar = nil
    if pet.expMax > 0 then
        local pct = math.min(pet.exp / pet.expMax, 1)
        expBar = UI.Panel {
            width = "100%", gap = 4,
            children = {
                UI.Panel {
                    width = "100%", height = 6,
                    borderRadius = 3,
                    backgroundColor = { 50, 45, 35, 255 },
                    overflow = "hidden",
                    children = {
                        UI.Panel {
                            width = tostring(math.floor(pct * 100)) .. "%",
                            height = "100%",
                            borderRadius = 3,
                            backgroundColor = Theme.colors.accent,
                        },
                    },
                },
                UI.Label {
                    text = "经验: " .. pet.exp .. " / " .. pet.expMax,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.textSecondary,
                    alignSelf = "flex-end",
                },
            },
        }
    end

    -- 觉醒阶段标记
    local awakenTag = nil
    if pet.awakenStage > 0 then
        local stageInfo = DataPets.AWAKEN_STAGES[pet.awakenStage]
        awakenTag = UI.Panel {
            paddingHorizontal = 6, paddingVertical = 1,
            borderRadius = 3,
            backgroundColor = { 255, 200, 50, 30 },
            children = {
                UI.Label {
                    text = stageInfo and stageInfo.name or ("觉醒+" .. pet.awakenStage),
                    fontSize = 10,
                    fontColor = Theme.colors.gold,
                },
            },
        }
    end

    -- 共鸣信息
    local resText = ""
    local res = pet.resonance
    if res and res.matchCount > 0 then
        resText = res.label
        if res.combatPct > 0 then
            resText = resText .. "(战斗+" .. math.floor(res.combatPct * 100) .. "%"
            if res.expPct > 0 then
                resText = resText .. " 经验+" .. math.floor(res.expPct * 100) .. "%"
            end
            resText = resText .. ")"
        end
    end
    local elemLabel = ELEM_LABELS[pet.element] or pet.element or "无"
    local elemColor = ELEM_COLORS[pet.element] or Theme.colors.textSecondary
    local resColor = (res and res.matchCount >= 2) and Theme.colors.gold
        or (res and res.matchCount == 1) and Theme.colors.accent
        or Theme.colors.textSecondary

    -- 境界压制提示
    local realmCapNote = nil
    if pet.realmCap < pet.bloodlineCap then
        realmCapNote = UI.Label {
            text = "境界压制: 等级上限" .. pet.realmCap .. " (血脉上限" .. pet.bloodlineCap .. ")",
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.warning,
        }
    end

    -- 右侧信息区
    local infoChildren = {
        -- 名字 + 等级
        UI.Panel {
            flexDirection = "row", gap = 6, alignItems = "center",
            flexWrap = "wrap",
            children = {
                UI.Label {
                    text = pet.name,
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textLight,
                },
                UI.Label {
                    text = "Lv." .. pet.level .. "/" .. pet.maxLevel,
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.accent,
                },
                BuildBloodlineTag(pet.bloodline),
                awakenTag,
            },
        },
        -- 定位 + 技能
        UI.Label {
            text = pet.role .. "  |  " .. pet.skill,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textGold,
        },
        -- 元素 + 共鸣
        (function()
            local elemRtColor = ELEM_RT_COLORS[pet.element] or "gray"
            local richStr = "属性: <c=" .. elemRtColor .. ">" .. elemLabel .. "</c>"
                .. (#resText > 0 and (" | " .. resText) or "")
            return RT.Build(richStr, Theme.fontSize.small, resColor)
        end)(),
        -- 描述
        UI.Label {
            text = pet.desc,
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textSecondary,
            flexShrink = 1,
        },
    }
    if realmCapNote then
        infoChildren[#infoChildren + 1] = realmCapNote
    end
    if expBar then
        infoChildren[#infoChildren + 1] = expBar
    end

    -- 升级信息
    local canLevelUp, luReason = GamePet.CanLevelUp(pet.uid)
    local lvCost = GamePet.GetLevelUpCost(pet.uid)
    local levelUpInfo = nil
    if lvCost then
        levelUpInfo = UI.Panel {
            width = "100%",
            backgroundColor = { 35, 30, 25, 200 },
            borderRadius = Theme.radius.sm,
            padding = Theme.spacing.sm,
            gap = 4,
            children = {
                UI.Label {
                    text = "升级消耗",
                    fontSize = Theme.fontSize.small,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textGold,
                },
                Comp.BuildStatRow("灵石", tostring(lvCost.lingshi), { valueColor = Theme.colors.accent }),
                Comp.BuildStatRow("灵兽精血", tostring(lvCost.jingxue), { valueColor = Theme.colors.accent }),
                not canLevelUp and UI.Label {
                    text = luReason or "",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.danger,
                } or nil,
            },
        }
    end

    -- 觉醒信息
    local canAwaken, awkReason = GamePet.CanAwaken(pet.uid)
    local awkInfo = GamePet.GetAwakenInfo(pet.uid)
    local awakenInfo = nil
    if awkInfo then
        local curStageName = pet.awakenStage > 0
            and (DataPets.AWAKEN_STAGES[pet.awakenStage] and DataPets.AWAKEN_STAGES[pet.awakenStage].name or ("+" .. pet.awakenStage))
            or "未觉醒"
        awakenInfo = UI.Panel {
            width = "100%",
            backgroundColor = { 35, 30, 25, 200 },
            borderRadius = Theme.radius.sm,
            padding = Theme.spacing.sm,
            gap = 4,
            children = {
                UI.Label {
                    text = "血脉觉醒 (" .. curStageName .. " -> " .. awkInfo.name .. ")",
                    fontSize = Theme.fontSize.small,
                    fontWeight = "bold",
                    fontColor = Theme.colors.gold,
                },
                Comp.BuildStatRow("灵石", tostring(awkInfo.lingshi), { valueColor = Theme.colors.accent }),
                Comp.BuildStatRow("灵兽精血", tostring(awkInfo.jingxue), { valueColor = Theme.colors.accent }),
                Comp.BuildStatRow("成功率", tostring(awkInfo.rate) .. "%", { valueColor = Theme.colors.textGold }),
                Comp.BuildStatRow("等级上限", "+" .. awkInfo.extraLevels, { valueColor = Theme.colors.gold }),
                Comp.BuildStatRow("属性加成", "+" .. math.floor(awkInfo.statBonus * 100) .. "%", { valueColor = Theme.colors.gold }),
                awkInfo.unlockTalent and UI.Label {
                    text = "觉醒成功将解锁一个新天赋槽位",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.successLight,
                } or nil,
                not canAwaken and UI.Label {
                    text = awkReason or "",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.danger,
                } or nil,
            },
        }
    elseif pet.awakenStage >= pet.maxAwakenStage then
        awakenInfo = UI.Panel {
            width = "100%", padding = 6,
            children = {
                UI.Label {
                    text = "已达觉醒圆满（" .. pet.maxAwakenStage .. "阶）",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.gold,
                    textAlign = "center",
                },
            },
        }
    end

    -- 化形信息
    local transformInfo = nil
    if pet.canTransform then
        if pet.transformed then
            transformInfo = UI.Panel {
                width = "100%", padding = 6,
                children = {
                    UI.Label {
                        text = "已化形",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.gold,
                        textAlign = "center",
                    },
                },
            }
        else
            local canTf, tfReason = GamePet.CanTransform(pet.uid)
            local req = DataPets.TRANSFORM_REQUIRE
            transformInfo = UI.Panel {
                width = "100%",
                backgroundColor = { 35, 30, 25, 200 },
                borderRadius = Theme.radius.sm,
                padding = Theme.spacing.sm,
                gap = 4,
                children = {
                    UI.Label {
                        text = "化形",
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = Theme.colors.gold,
                    },
                    Comp.BuildStatRow("灵石", tostring(req.lingshi), { valueColor = Theme.colors.accent }),
                    Comp.BuildStatRow("灵兽精血", tostring(req.jingxue), { valueColor = Theme.colors.accent }),
                    Comp.BuildStatRow("要求觉醒", "圆满", { valueColor = Theme.colors.textGold }),
                    Comp.BuildStatRow("要求羁绊", "Lv." .. req.minBondLevel .. "+", { valueColor = Theme.colors.textGold }),
                    not canTf and UI.Label {
                        text = tfReason or "",
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.danger,
                    } or nil,
                },
            }
        end
    end

    -- ==================== 操作按钮 ====================
    local actionButtons = {}
    -- 出战/召回
    actionButtons[#actionButtons + 1] = UI.Panel {
        flexGrow = 1,
        children = {
            Comp.BuildInkButton(
                pet.isActive and "召回" or "出战",
                function()
                    local newUid = pet.isActive and "" or pet.uid
                    GamePet.DoSetActive(newUid, function(ok, msg)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        Router.RebuildUI()
                    end)
                end,
                { width = "100%", fontSize = Theme.fontSize.body }
            ),
        },
    }
    -- 升级
    actionButtons[#actionButtons + 1] = UI.Panel {
        flexGrow = 1,
        children = {
            Comp.BuildInkButton("升级", function()
                if not canLevelUp then
                    Toast.Show(luReason or "无法升级", { variant = "error" })
                    return
                end
                GamePet.DoLevelUp(pet.uid, function(ok, msg)
                    Toast.Show(msg, { variant = ok and "success" or "error" })
                    Router.RebuildUI()
                end)
            end, { width = "100%", fontSize = Theme.fontSize.body, disabled = not canLevelUp }),
        },
    }

    -- 第二行按钮
    local actionButtons2 = {}
    -- 觉醒
    if awkInfo then
        actionButtons2[#actionButtons2 + 1] = UI.Panel {
            flexGrow = 1,
            children = {
                Comp.BuildInkButton("觉醒", function()
                    if not canAwaken then
                        Toast.Show(awkReason or "无法觉醒", { variant = "error" })
                        return
                    end
                    GamePet.DoAwaken(pet.uid, function(ok, msg)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        Router.RebuildUI()
                    end)
                end, { width = "100%", fontSize = Theme.fontSize.body, disabled = not canAwaken }),
            },
        }
    end
    -- 化形
    if pet.canTransform and not pet.transformed then
        local canTf = GamePet.CanTransform(pet.uid)
        actionButtons2[#actionButtons2 + 1] = UI.Panel {
            flexGrow = 1,
            children = {
                Comp.BuildInkButton("化形", function()
                    if not canTf then
                        Toast.Show("尚未满足化形条件", { variant = "error" })
                        return
                    end
                    GamePet.DoTransform(pet.uid, function(ok, msg)
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                        Router.RebuildUI()
                    end)
                end, { width = "100%", fontSize = Theme.fontSize.body, disabled = not canTf }),
            },
        }
    end
    -- 分解
    local canDecompose, decReason = GamePet.CanDecompose(pet.uid)
    actionButtons2[#actionButtons2 + 1] = UI.Panel {
        flexGrow = 1,
        children = {
            Comp.BuildSecondaryButton("分解", function()
                if not canDecompose then
                    Toast.Show(decReason or "无法分解", { variant = "error" })
                    return
                end
                showDecomposeConfirm_ = true
                Router.RebuildUI()
            end, { width = "100%" }),
        },
    }

    -- ==================== 组装详情 ====================
    local detailChildren = {
        -- 头部：横向排列
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            gap = 12,
            alignItems = "flex-start",
            children = {
                -- 头像
                UI.Panel {
                    width = 72, height = 72,
                    borderRadius = 10,
                    backgroundColor = { 25, 22, 18, 200 },
                    borderColor = blColor, borderWidth = 2,
                    justifyContent = "center", alignItems = "center",
                    overflow = "hidden",
                    flexShrink = 0,
                    children = {
                        UI.Panel {
                            width = 60, height = 60,
                            backgroundImage = pet.image,
                            backgroundFit = "contain",
                        },
                    },
                },
                -- 右侧信息
                UI.Panel {
                    flexGrow = 1, flexShrink = 1,
                    gap = 3,
                    children = infoChildren,
                },
            },
        },
        -- 操作按钮行1
        UI.Panel {
            width = "100%",
            flexDirection = "row", gap = 8,
            marginTop = 4,
            children = actionButtons,
        },
    }

    -- 操作按钮行2
    if #actionButtons2 > 0 then
        detailChildren[#detailChildren + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row", gap = 8,
            children = actionButtons2,
        }
    end

    -- 升级消耗信息
    if levelUpInfo then
        detailChildren[#detailChildren + 1] = levelUpInfo
    end

    -- 觉醒信息
    if awakenInfo then
        detailChildren[#detailChildren + 1] = awakenInfo
    end

    -- 天赋
    local talentSection = BuildTalentSection(pet)
    if talentSection then
        detailChildren[#detailChildren + 1] = talentSection
    end

    -- 羁绊
    local bondSection = BuildBondSection(pet)
    if bondSection then
        detailChildren[#detailChildren + 1] = bondSection
    end

    -- 化形
    if transformInfo then
        detailChildren[#detailChildren + 1] = transformInfo
    end

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = Theme.colors.gold,
        borderWidth = 1,
        padding = Theme.spacing.sm,
        gap = Theme.spacing.xs or 4,
        children = detailChildren,
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local allPets = GamePet.GetAllPets()
    local ownedCount = #allPets

    -- 按血脉等级排序（高血脉靠前），出战的排最前
    table.sort(allPets, function(a, b)
        if a.isActive ~= b.isActive then return a.isActive end
        local ra = DataPets.BLOODLINE_RANK[a.bloodline] or 0
        local rb = DataPets.BLOODLINE_RANK[b.bloodline] or 0
        if ra ~= rb then return ra > rb end
        if a.awakenStage ~= b.awakenStage then return a.awakenStage > b.awakenStage end
        if a.level ~= b.level then return a.level > b.level end
        return (a.name or "") < (b.name or "")
    end)

    local contentChildren = {
        Comp.BuildTextButton("< 返回", function()
            Router.EnterState(Router.STATE_HOME)
        end),
        Comp.BuildSectionTitle("灵宠仙阁"),
        UI.Label {
            text = "已拥有 " .. ownedCount .. " 只灵宠，探索时有概率捕获新灵宠",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            marginBottom = 4,
        },
    }

    -- 选中灵宠的详情面板
    local selectedPet = nil
    if selectedPetUid_ then
        for _, pet in ipairs(allPets) do
            if pet.uid == selectedPetUid_ then
                selectedPet = pet
                break
            end
        end
        if selectedPet then
            contentChildren[#contentChildren + 1] = BuildDetailPanel(selectedPet)
        else
            selectedPetUid_ = nil
        end
    end

    -- 灵宠列表
    contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
        "全部灵宠 (" .. ownedCount .. ")"
    )
    -- 动态计算列表最大高度：屏幕逻辑高度 - 固定UI占用
    local dpr = graphics:GetDPR()
    local scrH = graphics:GetHeight() / dpr
    local fixedH = Theme.topBarHeight + Theme.bottomNavHeight + 160  -- 顶栏+底栏+标题/说明/间距
    local detailH = selectedPet and 350 or 0  -- 详情面板高度
    local petListH = math.max(200, scrH - fixedH - detailH)

    local petCards = {}
    for _, pet in ipairs(allPets) do
        petCards[#petCards + 1] = BuildPetCard(pet)
    end
    if #petCards > 0 then
        contentChildren[#contentChildren + 1] = UI.ScrollView {
            width = "100%",
            maxHeight = petListH,
            showScrollbar = false,
            children = {
                UI.Panel {
                    width = "100%",
                    gap = 6,
                    children = petCards,
                },
            },
        }
    end

    if ownedCount == 0 then
        contentChildren[#contentChildren + 1] = UI.Label {
            text = "暂无灵宠，去探索世界捕获灵宠吧！",
            fontSize = Theme.fontSize.body,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            paddingVertical = 20,
        }
    end

    local pageShell = Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)

    -- 分解确认弹窗叠加层
    if showDecomposeConfirm_ and selectedPet then
        return UI.Panel {
            width = "100%", height = "100%",
            children = {
                pageShell,
                BuildDecomposeConfirm(selectedPet),
            },
        }
    end

    return pageShell
end

return M
