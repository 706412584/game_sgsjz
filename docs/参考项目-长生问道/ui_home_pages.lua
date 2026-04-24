-- ============================================================================
-- 《问道长生》洞府子页面（属性/功法/法宝/悟道/渡劫/丹药）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameCultivation = require("game_cultivation")
local GameItems = require("game_items")
local Toast = require("ui_toast")
local DataItems = require("data_items")
local DataRealms = require("data_realms")
local GameSkill = require("game_skill")
local DataCultArts = require("data_cultivation_arts")
local DataMartialArts = require("data_martial_arts")
local GameArtifact = require("game_artifact")
local GameDao = require("game_dao")
local DataRace = require("data_race")
local DataSpiritRoot = require("data_spirit_root")
local RT = require("rich_text")

local M = {}

-- ============================================================================
-- 四档属性颜色系统（低灰/中白/高金/极紫）
-- bonus 比例越高，颜色越醒目
-- ============================================================================
local STAT_TIER_COLORS = {
    peak = { 167, 139, 250, 255 },   -- 极: 紫 (加成 >= 100%)
    high = { 230, 195, 100, 255 },   -- 高: 金 (加成 >= 50%)
    mid  = { 215, 210, 200, 255 },   -- 中: 白 (加成 >= 20%)
    low  = { 120, 115, 105, 200 },   -- 低: 灰 (加成 < 20%)
}

--- 根据属性总值与各项加成，返回对应颜色档
---@return table {r,g,b,a}
local function StatValueColor(total, ...)
    local bonuses = 0
    for _, v in ipairs({...}) do bonuses = bonuses + (v or 0) end
    if bonuses <= 0 then return STAT_TIER_COLORS.mid end  -- 无加成：中档白色
    local base = (total or 0) - bonuses
    if base <= 0 then return STAT_TIER_COLORS.high end
    local ratio = bonuses / base
    if ratio >= 1.0 then return STAT_TIER_COLORS.peak end
    if ratio >= 0.5 then return STAT_TIER_COLORS.high end
    if ratio >= 0.2 then return STAT_TIER_COLORS.mid end
    return STAT_TIER_COLORS.low
end

-- ============================================================================
-- 通用：返回按钮
-- ============================================================================
local function BuildBackRow(title, backState)
    backState = backState or Router.STATE_HOME
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8,
                paddingVertical = 4,
                cursor = "pointer",
                onClick = function(self)
                    Router.EnterState(backState)
                end,
                children = {
                    UI.Label {
                        text = "< 返回",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = title,
                fontSize = Theme.fontSize.heading,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- 通用：品质颜色
-- ============================================================================
local function GetQualityColor(q)
    return DataItems.GetQualityColor(q)
end

-- ============================================================================
-- 页面1：属性
-- ============================================================================
function M.BuildAttr(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 装备/法宝/宗门加成明细
    local eqB   = GamePlayer.GetEquippedBonus()
    local artB  = GamePlayer.GetArtifactBonus()
    local sectB = GamePlayer.GetSectBonus()

    --- 标签组件（仿主页顶部境界/寿元标签风格）
    local tagBg = { 50, 42, 35, 220 }
    local tagRadius = 8
    local function BuildTag(label, value, opts)
        opts = opts or {}
        return UI.Panel {
            flexDirection = "row",
            gap = 4,
            alignItems = "center",
            backgroundColor = opts.bg or tagBg,
            borderRadius = tagRadius,
            borderColor = opts.borderColor or Theme.colors.borderGold,
            borderWidth = 1,
            paddingVertical = 4,
            paddingHorizontal = 10,
            children = {
                UI.Label {
                    text = label,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = { 140, 125, 105, 255 },
                },
                UI.Label {
                    text = tostring(value),
                    fontSize = Theme.fontSize.small,
                    fontWeight = "bold",
                    fontColor = opts.fontColor or Theme.colors.textGold,
                },
            },
        }
    end

    --- 生成带加成明细的属性值文本
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

    -- 灵根展示文本
    local spiritRootText = "未知"
    if p.spiritRoots and #p.spiritRoots > 0 then
        local parts = {}
        for _, r in ipairs(p.spiritRoots) do
            parts[#parts + 1] = DataSpiritRoot.GetDisplayName(r)
        end
        spiritRootText = table.concat(parts, " / ")
    end

    -- 修炼速度
    local rate, coupleBonus = GameCultivation.GetPerSec()
    local rateStr = string.format("%.1f/秒", rate)
    local rateParts = {}
    if coupleBonus > 0 then
        rateParts[#rateParts + 1] = string.format("道侣+%d%%", math.floor(coupleBonus * 100 + 0.5))
    end
    if (sectB.cultivationSpeed or 0) > 0 then
        rateParts[#rateParts + 1] = string.format("宗门+%d%%", math.floor(sectB.cultivationSpeed * 100 + 0.5))
    end
    if #rateParts > 0 then
        rateStr = rateStr .. " (" .. table.concat(rateParts, " ") .. ")"
    end

    -- 寿元进度
    local lifePct = 0
    if (p.lifespanMax or 0) > 0 then
        lifePct = math.floor((p.lifespan or 0) / p.lifespanMax * 100)
    end

    -- 头像路径
    local avatarIdx = p.avatarIndex or 1
    local avatarList = Theme.avatars and (Theme.avatars[p.gender] or Theme.avatars["男"])
    local avatarImg = avatarList and (avatarList[avatarIdx] or avatarList[1])

    -- 打坐图路径
    local meditateChars = Theme.meditateChars
    local meditateImg = meditateChars
        and (meditateChars[p.gender] or meditateChars["男"])
        and (meditateChars[p.gender] or meditateChars["男"])[avatarIdx]
        or (p.gender == "女" and Theme.images.meditateCharF or Theme.images.meditateChar)

    -- ================================================================
    -- 构建内容
    -- ================================================================
    local contentChildren = {
        BuildBackRow("角色属性"),

        -- === 角色概览区（打坐图 + 核心标签） ===
        UI.Panel {
            width = "100%",
            alignItems = "center",
            paddingVertical = 8,
            gap = 8,
            children = {
                -- 打坐图片
                UI.Panel {
                    width = 150,
                    height = 150,
                    backgroundImage = meditateImg,
                    backgroundFit = "contain",
                },
                -- 道号
                UI.Label {
                    text = p.name or "无名",
                    fontSize = Theme.fontSize.heading,
                    fontWeight = "bold",
                    fontColor = Theme.colors.textGold,
                },
                -- 核心标签行
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    flexWrap = "wrap",
                    gap = 6,
                    justifyContent = "center",
                    children = {
                        BuildTag("境界", p.realmName or "练气初期", { fontColor = Theme.colors.gold }),
                        BuildTag("寿", (p.lifespan or 0) .. "/" .. (p.lifespanMax or 100),
                            { fontColor = lifePct < 25 and Theme.colors.dangerLight or Theme.colors.textPrimary }),
                        BuildTag("种族", DataRace.GetRace(p.race).name, { fontColor = DataRace.GetRace(p.race).color }),
                        BuildTag("灵根", spiritRootText, { fontColor = Theme.colors.accent }),
                    },
                },
            },
        },

        -- === 战斗属性 ===
        Comp.BuildCardPanel("战斗属性", {
            Comp.BuildStatRow("气血", (p.hp or 0) .. " / " .. (p.hpMax or 0)
                .. ((sectB.hpMax or 0) > 0 and (" (宗门+" .. sectB.hpMax .. ")") or ""),
                { valueColor = Theme.colors.dangerLight }),
            Comp.BuildStatRow("灵力", (p.mp or 0) .. " / " .. (p.mpMax or 0),
                { valueColor = Theme.colors.accent }),
            Comp.BuildStatRow("攻击", FmtStat(p.attack or 0, eqB.attack, artB.attack, sectB.attack),
                { valueColor = StatValueColor(p.attack, eqB.attack, artB.attack, sectB.attack) }),
            Comp.BuildStatRow("防御", FmtStat(p.defense or 0, eqB.defense, artB.defense, nil),
                { valueColor = StatValueColor(p.defense, eqB.defense, artB.defense) }),
            Comp.BuildStatRow("速度", FmtStat(p.speed or 0, eqB.speed, artB.speed, sectB.speed),
                { valueColor = StatValueColor(p.speed, eqB.speed, artB.speed, sectB.speed) }),
            Comp.BuildStatRow("暴击", FmtStat(p.crit or 0, eqB.crit, artB.crit, nil, "%"),
                { valueColor = StatValueColor(p.crit, eqB.crit, artB.crit) }),
            Comp.BuildStatRow("闪避", FmtStat(p.dodge or 0, eqB.dodge, 0, nil, "%"),
                { valueColor = StatValueColor(p.dodge, eqB.dodge) }),
            Comp.BuildStatRow("命中", FmtStat(p.hit or 0, eqB.hit, 0, nil, "%"),
                { valueColor = StatValueColor(p.hit, eqB.hit) }),
        }),

        -- === 修真属性 ===
        Comp.BuildCardPanel("修真属性", {
            Comp.BuildStatRow("悟性", tostring(p.wisdom or 0), { valueColor = Theme.colors.gold }),
            Comp.BuildStatRow("气运", p.fortune or "未知", { valueColor = Theme.colors.gold }),
            Comp.BuildStatRow("道心", p.daoHeart or "未知", { valueColor = Theme.colors.gold }),
            Comp.BuildStatRow("神识", tostring(p.sense or 0), { valueColor = Theme.colors.gold }),
            Comp.BuildStatRow("修炼速度", rateStr, { valueColor = Theme.colors.successLight }),
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

-- ============================================================================
-- 页面2：功法（V2 拆分：修炼功法 + 武学功法）
-- ============================================================================

-- 属性颜色映射
local ELEMENT_COLORS = {
    metal   = { 200, 200, 220, 255 },
    wood    = { 80,  180, 80,  255 },
    water   = { 80,  140, 220, 255 },
    fire    = { 220, 80,  60,  255 },
    earth   = { 180, 150, 80,  255 },
    thunder = { 200, 180, 60,  255 },
    ice     = { 120, 200, 240, 255 },
    wind    = { 100, 200, 160, 255 },
    yin     = { 160, 100, 200, 255 },
    yang    = { 240, 200, 80,  255 },
}

--- 武学品阶彩色徽章（grade key: fan/ling/xuan/di/tian/xian）
local function BuildMartialGradeBadge(grade, gradeName)
    local c = DataMartialArts.GRADE_COLORS[grade] or DataMartialArts.GRADE_COLORS["fan"]
    return UI.Panel {
        paddingHorizontal = 5, paddingVertical = 1, borderRadius = 3,
        backgroundColor = { c[1], c[2], c[3], 35 },
        borderColor = c, borderWidth = 1,
        children = {
            UI.Label { text = gradeName or "?", fontSize = Theme.fontSize.tiny, fontColor = c },
        },
    }
end

--- 修炼功法卡片
local function BuildCultArtCard()
    local info = GameSkill.GetCultArtInfo()
    if not info then
        return Comp.BuildCardPanel("修炼功法", {
            UI.Label {
                text = "未装备修炼功法",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
        })
    end

    local pct = math.floor(info.level / info.maxLevel * 100)
    local canTrain, trainReason = GameSkill.CanTrainCultArt()
    local factionLabel = info.faction == "righteous" and "正道"
                      or info.faction == "demonic" and "魔道"
                      or "通用"

    return Comp.BuildCardPanel("修炼功法", {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 8, alignItems = "center",
                    children = {
                        UI.Label {
                            text = info.name,
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            fontColor = Theme.colors.textGold,
                        },
                        UI.Label {
                            text = "[" .. factionLabel .. "]",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.accent,
                        },
                    },
                },
                UI.Label {
                    text = "Lv." .. info.level .. "/" .. info.maxLevel,
                    fontSize = Theme.fontSize.small,
                    fontWeight = "bold",
                    fontColor = Theme.colors.gold,
                },
            },
        },
        -- 描述
        UI.Label {
            text = info.desc,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textLight,
        },
        -- 修炼加成
        UI.Label {
            text = "修炼加成: +" .. string.format("%.0f%%", info.bonus * 100),
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.successLight,
        },
        -- 等级进度条
        UI.Panel {
            width = "100%", height = 6, borderRadius = 3,
            backgroundColor = { 50, 45, 35, 255 }, overflow = "hidden",
            children = {
                UI.Panel {
                    width = tostring(pct) .. "%", height = "100%",
                    borderRadius = 3, backgroundColor = Theme.colors.gold,
                },
            },
        },
        -- 操作按钮行
        UI.Panel {
            width = "100%",
            flexDirection = "column",
            marginTop = 4,
            gap = 4,
            children = {
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    gap = 8,
                    children = {
                        Comp.BuildSecondaryButton("修炼", function()
                            GameSkill.DoTrainCultArt(function(ok, msg)
                                Router.RebuildUI()
                            end)
                        end, {
                            width = 72, fontSize = Theme.fontSize.small,
                            bg = canTrain and nil or { 60, 55, 45, 255 },
                        }),
                        Comp.BuildSecondaryButton("切换", function()
                            -- 显示可用的修炼功法列表
                            M._showCultArtPicker = not M._showCultArtPicker
                            Router.RebuildUI()
                        end, { width = 72, fontSize = Theme.fontSize.small }),
                    },
                },
                -- 不可修炼时显示原因提示
                (not canTrain and trainReason) and UI.Label {
                    text = trainReason,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = { 180, 100, 80, 255 },
                    textAlign = "right",
                    width = "100%",
                } or nil,
            },
        },
    })
end

--- 修炼功法选择列表
local function BuildCultArtPicker()
    if not M._showCultArtPicker then return nil end
    local p = GamePlayer.Get()
    if not p then return nil end

    local race = p.race or "human"
    local tier = p.tier or 1
    local unlockedCultArts = p.unlockedCultArts or {}
    local allArts = DataCultArts.GetAvailable(race, tier, unlockedCultArts)
    local currentId = p.cultivationArt and p.cultivationArt.id or nil

    local rows = {}
    for _, art in ipairs(allArts) do
        local isCurrent = (art.id == currentId)
        local canUse, msg = DataCultArts.CanUse(race, art.id)
        rows[#rows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingVertical = 6,
            borderBottomWidth = 1,
            borderColor = Theme.colors.border,
            children = {
                UI.Panel {
                    flexShrink = 1, gap = 2,
                    children = {
                        UI.Label {
                            text = art.name,
                            fontSize = Theme.fontSize.body,
                            fontWeight = "bold",
                            fontColor = isCurrent and Theme.colors.gold or Theme.colors.textLight,
                        },
                        UI.Label {
                            text = art.desc,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        },
                    },
                },
                isCurrent
                    and UI.Label {
                        text = "当前",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.gold,
                    }
                    or (canUse
                        and Comp.BuildSecondaryButton("选择", function()
                            GameSkill.DoSwitchCultArt(art.id, function(ok, _)
                                M._showCultArtPicker = false
                                Router.RebuildUI()
                            end)
                        end, { width = 60, fontSize = Theme.fontSize.small })
                        or UI.Label {
                            text = msg or "不可用",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        }),
            },
        }
    end

    return Comp.BuildCardPanel("选择修炼功法", rows)
end

--- 武学装备槽
local function BuildMartialArtSlots()
    local slots = GameSkill.GetEquippedMartialArts()
    local slotRows = {}

    for i = 1, DataMartialArts.MAX_EQUIPPED do
        local info = slots[i]
        if info then
            local elemColor = ELEMENT_COLORS[info.element] or Theme.colors.textLight
            slotRows[#slotRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 6,
                borderBottomWidth = 1,
                borderColor = Theme.colors.border,
                children = {
                    UI.Panel {
                        flexShrink = 1, gap = 2,
                        children = {
                            UI.Panel {
                                flexDirection = "row", gap = 6, alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = info.name,
                                        fontSize = Theme.fontSize.body,
                                        fontWeight = "bold",
                                        fontColor = elemColor,
                                    },
                                    UI.Label {
                                        text = info.elementName,
                                        fontSize = Theme.fontSize.tiny,
                                        fontColor = elemColor,
                                    },
                                    BuildMartialGradeBadge(info.grade, info.gradeName),
                                },
                            },
                            UI.Label {
                                text = "Lv." .. info.level .. "/" .. info.maxLevel
                                    .. "  伤害:" .. string.format("%.0f%%", info.baseDamage * 100),
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                    Comp.BuildSecondaryButton("卸下", function()
                        GameSkill.DoUnequipMartialArt(i, function(ok, _)
                            if ok then Router.RebuildUI() end
                        end)
                    end, { width = 56, fontSize = Theme.fontSize.tiny }),
                },
            }
        else
            slotRows[#slotRows + 1] = UI.Panel {
                width = "100%",
                paddingVertical = 8,
                alignItems = "center",
                borderBottomWidth = 1,
                borderColor = Theme.colors.border,
                children = {
                    UI.Label {
                        text = "[ 空槽位 " .. i .. " ]",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                    },
                },
            }
        end
    end

    return Comp.BuildCardPanel("武学装备 (" .. #slotRows .. "/" .. DataMartialArts.MAX_EQUIPPED .. ")", slotRows)
end

--- 已拥有武学列表
local function BuildMartialArtList()
    local ownedArts = GameSkill.GetOwnedMartialArts()
    if #ownedArts == 0 then
        return Comp.BuildCardPanel("已拥有武学", {
            UI.Label {
                text = "暂无武学，可通过探索或坊市获取。",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
        })
    end

    local p = GamePlayer.Get()
    local spiritRoots = p and p.spiritRoots or {}

    local rows = {}
    for _, art in ipairs(ownedArts) do
        local elemColor = ELEMENT_COLORS[art.element] or Theme.colors.textLight
        local canTrain, trainReason = GameSkill.CanTrainMartialArt(art.id)
        local isEquipped = art.equippedSlot ~= nil
        local matchLv = DataMartialArts.GetSpiritRootMatchLevel(spiritRoots, art.element)
        local matchText = matchLv == 2 and "双灵根" or matchLv == 1 and "单灵根" or nil

        rows[#rows + 1] = UI.Panel {
            width = "100%",
            paddingVertical = 6,
            borderBottomWidth = 1,
            borderColor = Theme.colors.border,
            gap = 4,
            children = {
                -- 第一行：名称 + 等级
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    children = {
                        UI.Panel {
                            flexDirection = "row", gap = 6, alignItems = "center",
                            children = {
                                UI.Label {
                                    text = art.name,
                                    fontSize = Theme.fontSize.body,
                                    fontWeight = "bold",
                                    fontColor = elemColor,
                                },
                                UI.Label {
                                    text = art.elementName,
                                    fontSize = Theme.fontSize.tiny,
                                    fontColor = elemColor,
                                },
                                BuildMartialGradeBadge(art.grade, art.gradeName),
                                matchText and UI.Label {
                                    text = matchText,
                                    fontSize = Theme.fontSize.tiny,
                                    fontColor = Theme.colors.gold,
                                } or nil,
                            },
                        },
                        UI.Label {
                            text = "Lv." .. art.level .. "/" .. art.maxLevel,
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            fontColor = Theme.colors.gold,
                        },
                    },
                },
                -- 第二行：描述 + 伤害
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "space-between",
                    children = {
                        UI.Label {
                            text = art.desc,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                            flexShrink = 1,
                        },
                        UI.Label {
                            text = string.format("%.0f%%", art.baseDamage * 100),
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textLight,
                        },
                    },
                },
                -- 第三行：操作按钮
                UI.Panel {
                    width = "100%",
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    gap = 8,
                    children = {
                        isEquipped
                            and UI.Label {
                                text = "装备中(槽" .. art.equippedSlot .. ")",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.successLight,
                            }
                            or Comp.BuildSecondaryButton("装备", function()
                                GameSkill.DoEquipMartialArt(art.id, nil, function(ok, _)
                                    if ok then Router.RebuildUI() end
                                end)
                            end, { width = 56, fontSize = Theme.fontSize.tiny }),
                        Comp.BuildSecondaryButton("修炼", function()
                            GameSkill.DoTrainMartialArt(art.id, function(ok, _)
                                if ok then Router.RebuildUI() end
                            end)
                        end, {
                            width = 56, fontSize = Theme.fontSize.tiny,
                            bg = canTrain and nil or { 60, 55, 45, 255 },
                        }),
                    },
                },
            },
        }
    end

    return Comp.BuildCardPanel("已拥有武学", rows)
end

function M.BuildSkill(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local cardList = {
        BuildBackRow("功法"),
        BuildCultArtCard(),
        BuildCultArtPicker(),
        BuildMartialArtSlots(),
        BuildMartialArtList(),
    }

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 页面3：法宝
-- ============================================================================
-- 模块级状态：分解确认 / 洗炼确认 / 批量分解 / 法宝信息弹窗
M._decompArtName = nil
M._rerollArtName = nil
M._showBatchDecomp = false
M._batchDecompQualities = nil  -- nil = 未初始化，会在打开时创建
M._selectedArtName = nil       -- 当前打开信息弹窗的法宝名

-- 通用：构建法宝属性展示（卡片和弹窗复用）
local function BuildArtifactStatsSection(art, qColor)
    local maxLv = GameArtifact.GetMaxLevel(art) or art.maxLevel or 100
    local pct = math.floor((art.level or 1) / maxLv * 100)
    local ascStage = art.ascStage or 0
    local children = {}

    -- 描述
    children[#children + 1] = UI.Label {
        text = art.desc,
        fontSize = Theme.fontSize.small,
        fontColor = Theme.colors.textLight,
    }

    -- 效果（V2 mainStat + subStats / 旧 effect 兼容）
    if art.mainStat then
        local statChildren = {}
        statChildren[#statChildren + 1] = UI.Label {
            text = "主属性: " .. GameArtifact.FormatMainStat(art.mainStat),
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.successLight,
        }
        if art.subStats and #art.subStats > 0 then
            statChildren[#statChildren + 1] = UI.Label {
                text = "副属性:",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.accent,
                marginTop = 2,
            }
            for _, sub in ipairs(art.subStats) do
                statChildren[#statChildren + 1] = UI.Label {
                    text = "  " .. GameArtifact.FormatSubStat(sub),
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textLight,
                }
            end
        end
        children[#children + 1] = UI.Panel { width = "100%", gap = 1, children = statChildren }
    else
        children[#children + 1] = UI.Label {
            text = "效果: " .. (art.effect or "无"),
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.successLight,
        }
    end

    -- 等级条
    children[#children + 1] = UI.Panel {
        width = "100%", flexDirection = "row", gap = 8, alignItems = "center",
        children = {
            UI.Label {
                text = "Lv." .. (art.level or 1) .. "/" .. maxLv,
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
            },
            UI.Panel {
                flexGrow = 1, height = 6, borderRadius = 3,
                backgroundColor = { 50, 45, 35, 255 }, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(pct) .. "%", height = "100%",
                        borderRadius = 3, backgroundColor = qColor,
                    },
                },
            },
        },
    }

    -- 升阶信息
    if ascStage < 3 then
        local ascInfo = GameArtifact.GetAscensionInfo(art.name)
        children[#children + 1] = UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, alignItems = "center",
            children = {
                UI.Label {
                    text = "升阶: " .. ascStage .. "/3",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.textSecondary,
                },
                ascInfo and UI.Label {
                    text = "下阶: " .. ascInfo.name .. " (成功率" .. ascInfo.rate .. "%)",
                    fontSize = Theme.fontSize.tiny,
                    fontColor = Theme.colors.accent,
                } or nil,
            },
        }
    else
        children[#children + 1] = UI.Label {
            text = "升阶: 已满阶 3/3",
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.gold,
        }
    end

    return UI.Panel { width = "100%", gap = 6, children = children }
end

-- 前向声明（BuildArtifactCard 的 onClick 在运行时调用它，此时已完成赋值）
local BuildArtifactInfoPopup

--- 法宝列表卡片（精简版，点击唤出详情弹窗）
local function BuildArtifactCard(art)
    local qualityLabel = DataItems.GetQualityLabel(art.quality) or art.quality
    local ascStage = art.ascStage or 0
    local ascLabel = ascStage > 0 and (" +" .. ascStage) or ""
    local qColor = GetQualityColor(art.quality)
    local maxLv = GameArtifact.GetMaxLevel(art) or art.maxLevel or 100
    local pct = math.floor((art.level or 1) / maxLv * 100)

    return UI.Panel {
        width = "100%",
        backgroundColor = Theme.colors.bgDark,
        borderRadius = Theme.radius.md,
        borderColor = qColor,
        borderWidth = 1,
        padding = Theme.spacing.md,
        gap = Theme.spacing.sm,
        cursor = "pointer",
        onClick = function(self)
            Router.ShowOverlayDialog(BuildArtifactInfoPopup(art.name))
        end,
        children = {
            -- 标题行
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-between", alignItems = "center",
                children = {
                    UI.Panel {
                        flexShrink = 1, flexDirection = "row", gap = 6, alignItems = "center",
                        children = {
                            UI.Label {
                                text = art.name,
                                fontSize = Theme.fontSize.subtitle,
                                fontWeight = "bold",
                                fontColor = qColor,
                            },
                            UI.Label {
                                text = "[" .. qualityLabel .. ascLabel .. "]",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = qColor,
                            },
                        },
                    },
                    art.equipped and UI.Panel {
                        paddingHorizontal = 8, paddingVertical = 2,
                        borderRadius = Theme.radius.sm,
                        backgroundColor = { 80, 160, 80, 60 },
                        borderColor = Theme.colors.successLight, borderWidth = 1,
                        children = {
                            UI.Label {
                                text = "装备中",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.successLight,
                            },
                        },
                    } or UI.Label {
                        text = "Lv." .. (art.level or 1),
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.gold,
                    },
                },
            },
            -- 主属性概览（一行）
            art.mainStat and UI.Label {
                text = GameArtifact.FormatMainStat(art.mainStat),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.successLight,
            } or UI.Label {
                text = "效果: " .. (art.effect or "无"),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.successLight,
            },
            -- 等级条
            UI.Panel {
                width = "100%", flexDirection = "row", gap = 8, alignItems = "center",
                children = {
                    UI.Label {
                        text = "Lv." .. (art.level or 1) .. "/" .. maxLv,
                        fontSize = Theme.fontSize.tiny,
                        fontColor = Theme.colors.textSecondary,
                    },
                    UI.Panel {
                        flexGrow = 1, height = 4, borderRadius = 2,
                        backgroundColor = { 50, 45, 35, 255 }, overflow = "hidden",
                        children = {
                            UI.Panel {
                                width = tostring(pct) .. "%", height = "100%",
                                borderRadius = 2, backgroundColor = qColor,
                            },
                        },
                    },
                },
            },
            -- 底部提示
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "flex-end",
                children = {
                    UI.Label {
                        text = "点击查看详情 >",
                        fontSize = Theme.fontSize.tiny,
                        fontColor = { 120, 115, 105, 180 },
                    },
                },
            },
        },
    }
end

--- 法宝信息专用弹窗（包含全部操作功能）
BuildArtifactInfoPopup = function(artName)
    if not artName then return nil end
    local p = GamePlayer.Get()
    if not p then return nil end

    -- 在玩家法宝列表中找到该法宝
    local art = nil
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then art = a; break end
    end
    if not art then return nil end

    local qualityLabel = DataItems.GetQualityLabel(art.quality) or art.quality
    local ascStage = art.ascStage or 0
    local ascLabel = ascStage > 0 and (" +" .. ascStage) or ""
    local qColor = GetQualityColor(art.quality)

    local canAsc, ascReason = GameArtifact.CanAscend(art.name)
    local canReroll, rerollReason = (art.mainStat and art.subStats)
        and GameArtifact.CanReroll(art.name) or false, nil
    local canDec = GameArtifact.CanDecompose(art.name)

    local function closePopup()
        Router.HideOverlayDialog()
    end

    local function afterOp(ok, msg)
        Toast.Show(msg, { variant = ok and "success" or "error" })
        Router.HideOverlayDialog()
        Router.RebuildUI()
    end

    -- 操作按钮区
    local btnRow1 = {}
    -- 装备 / 卸下
    btnRow1[#btnRow1 + 1] = Comp.BuildSecondaryButton(
        art.equipped and "卸下" or "装备",
        function()
            if art.equipped then
                GameArtifact.DoUnequip(art.name, function(ok, msg)
                    afterOp(ok, msg)
                end)
            else
                GameArtifact.DoEquip(art.name, function(ok, msg)
                    afterOp(ok, msg)
                end)
            end
        end,
        { width = 72, fontSize = Theme.fontSize.small }
    )
    -- 炼化（强化）
    btnRow1[#btnRow1 + 1] = Comp.BuildSecondaryButton("炼化", function()
        GameArtifact.DoEnhance(art.name, function(ok, msg, success)
            if success then
                afterOp(true, msg)
            elseif ok then
                -- ok=true 但 success=false/nil 表示强化失败（材料已消耗）
                afterOp(false, msg)
            else
                afterOp(false, msg)
            end
        end)
    end, { width = 72, fontSize = Theme.fontSize.small })
    -- 升阶
    btnRow1[#btnRow1 + 1] = Comp.BuildSecondaryButton("升阶", function()
        if not canAsc then
            Toast.Show(ascReason or "无法升阶", { variant = "error" })
            return
        end
        GameArtifact.DoAscend(art.name, function(ok, msg)
            afterOp(ok, msg)
        end)
    end, {
        width = 72,
        fontSize = Theme.fontSize.small,
        bg = canAsc and Theme.colors.accent or nil,
    })

    -- 第二行按钮：洗炼 / 分解
    local btnRow2 = {}
    if art.mainStat and art.subStats then
        btnRow2[#btnRow2 + 1] = Comp.BuildSecondaryButton("洗炼", function()
            if not canReroll then
                Toast.Show(rerollReason or "无法洗炼", { variant = "error" })
                return
            end
            M._rerollArtName = art.name
            Router.RebuildUI()
        end, {
            width = 72,
            fontSize = Theme.fontSize.small,
            bg = canReroll and { 140, 80, 200, 255 } or nil,
        })
    end
    if canDec then
        btnRow2[#btnRow2 + 1] = Comp.BuildSecondaryButton("分解", function()
            M._decompArtName = art.name
            Router.RebuildUI()
        end, { width = 72, fontSize = Theme.fontSize.small })
    end

    local popupContent = UI.ScrollView {
        width = "100%", maxHeight = 440,
        scrollY = true, showScrollbar = false,
        scrollMultiplier = Theme.scrollSensitivity,
        children = {
            UI.Panel {
                width = "100%", gap = 10,
                children = {
                    -- 标题行（名称 + 品质标签）
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between", alignItems = "center",
                        children = {
                            UI.Panel {
                                flexShrink = 1, flexDirection = "row",
                                gap = 6, alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = art.name,
                                        fontSize = Theme.fontSize.heading,
                                        fontWeight = "bold",
                                        fontColor = qColor,
                                    },
                                    UI.Label {
                                        text = "[" .. qualityLabel .. ascLabel .. "]",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = qColor,
                                    },
                                },
                            },
                            art.equipped and UI.Panel {
                                paddingHorizontal = 8, paddingVertical = 3,
                                borderRadius = Theme.radius.sm,
                                backgroundColor = { 80, 160, 80, 60 },
                                borderColor = Theme.colors.successLight, borderWidth = 1,
                                children = {
                                    UI.Label {
                                        text = "装备中",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = Theme.colors.successLight,
                                    },
                                },
                            } or nil,
                        },
                    },
                    -- 分割线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = Theme.colors.divider,
                    },
                    -- 全部属性详情
                    BuildArtifactStatsSection(art, qColor),
                    -- 分割线
                    UI.Panel {
                        width = "100%", height = 1,
                        backgroundColor = Theme.colors.divider,
                    },
                    -- 操作按钮行1
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "center", gap = 8, flexWrap = "wrap",
                        children = btnRow1,
                    },
                    -- 操作按钮行2（洗炼/分解）
                    #btnRow2 > 0 and UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "center", gap = 8, flexWrap = "wrap",
                        children = btnRow2,
                    } or nil,
                },
            },
        },
    }

    return Comp.Dialog("法宝详情", popupContent, {}, {
        onClose = closePopup,
        width = "92%",
    })
end

--- 分解确认对话框
local function BuildDecomposeConfirm()
    local artName = M._decompArtName
    if not artName then return nil end

    local yieldInfo = GameArtifact.GetDecomposeYield(artName)
    local yieldParts = {}
    if yieldInfo then
        local labelMap = { lingchen = "灵尘", xianshi = "仙石", tianyuan = "天元精魄", jingxue = "灵兽精血" }
        for _, k in ipairs({ "lingchen", "xianshi", "tianyuan", "jingxue" }) do
            if (yieldInfo[k] or 0) > 0 then
                yieldParts[#yieldParts + 1] = (labelMap[k] or k) .. " x" .. yieldInfo[k]
            end
        end
    end
    local yieldText = #yieldParts > 0 and table.concat(yieldParts, "、") or "无"

    return Comp.Dialog({
        title = "确认分解",
        children = {
            UI.Label {
                text = "确定要分解法宝 [" .. artName .. "] 吗？",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textLight,
            },
            UI.Label {
                text = "分解后不可恢复。",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.dangerLight,
                marginTop = 4,
            },
            UI.Label {
                text = "预计获得: " .. yieldText,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.gold,
                marginTop = 4,
            },
        },
        confirmText = "分解",
        cancelText = "取消",
        onConfirm = function()
            GameArtifact.DoDecompose(artName, function(ok, msg)
                Toast.Show(msg, { variant = ok and "success" or "error" })
                M._decompArtName = nil
                Router.HandleNavigate("home_artifact")
            end)
        end,
        onCancel = function()
            M._decompArtName = nil
            Router.RebuildUI()
        end,
    })
end

--- 洗炼确认对话框
local function BuildRerollConfirm()
    local artName = M._rerollArtName
    if not artName then return nil end

    local costInfo = GameArtifact.GetRerollCost(artName)
    local costParts = {}
    if costInfo then
        if (costInfo.lingchen or 0) > 0 then
            costParts[#costParts + 1] = "灵尘 x" .. costInfo.lingchen
        end
        if (costInfo.lingStone or 0) > 0 then
            costParts[#costParts + 1] = "灵石 x" .. costInfo.lingStone
        end
        if (costInfo.spiritStone or 0) > 0 then
            costParts[#costParts + 1] = "仙石 x" .. costInfo.spiritStone .. "（锁定费用）"
        end
    end
    local costText = #costParts > 0 and table.concat(costParts, "、") or "无"

    return Comp.Dialog({
        title = "洗炼副属性",
        children = {
            UI.Label {
                text = "将重新随机生成未锁定的副属性。",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textLight,
            },
            UI.Label {
                text = "消耗: " .. costText,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.gold,
                marginTop = 4,
            },
            UI.Label {
                text = "锁定副属性需额外消耗仙石。",
                fontSize = Theme.fontSize.tiny,
                fontColor = Theme.colors.textSecondary,
                marginTop = 2,
            },
        },
        confirmText = "洗炼",
        cancelText = "取消",
        onConfirm = function()
            GameArtifact.DoReroll(artName, function(ok, msg)
                Toast.Show(msg, { variant = ok and "success" or "error" })
                M._rerollArtName = nil
                Router.HandleNavigate("home_artifact")
            end)
        end,
        onCancel = function()
            M._rerollArtName = nil
            Router.RebuildUI()
        end,
    })
end

--- 批量分解确认对话框（品阶勾选）
local function BuildBatchDecomposeConfirm()
    if not M._showBatchDecomp then return nil end

    -- 初始化勾选状态（仅保留有分解产出的品阶）
    if not M._batchDecompQualities then
        M._batchDecompQualities = {}
        for _, qKey in ipairs(DataItems.QUALITY_ORDER) do
            if DataItems.DECOMPOSE_YIELD[qKey] then
                M._batchDecompQualities[qKey] = false
            end
        end
    end
    local sel = M._batchDecompQualities

    -- 预览当前勾选的分解结果
    local previewCount, previewYields = GameArtifact.PreviewBatchDecompose(sel)

    -- 勾选行
    local checkRows = {}
    for _, qKey in ipairs(DataItems.QUALITY_ORDER) do
        if DataItems.DECOMPOSE_YIELD[qKey] then
            local qLabel = DataItems.GetQualityLabel(qKey) or qKey
            local qColor = GetQualityColor(qKey)
            local isOn = sel[qKey] or false
            checkRows[#checkRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 4,
                cursor = "pointer",
                onClick = function(self)
                    sel[qKey] = not sel[qKey]
                    Router.RebuildUI()
                end,
                children = {
                    UI.Panel {
                        flexDirection = "row", gap = 8, alignItems = "center",
                        children = {
                            -- 勾选框
                            UI.Panel {
                                width = 20, height = 20,
                                borderRadius = 4,
                                borderWidth = 2,
                                borderColor = isOn and Theme.colors.gold or Theme.colors.border,
                                backgroundColor = isOn and Theme.colors.gold or { 30, 25, 20, 255 },
                                justifyContent = "center",
                                alignItems = "center",
                                children = isOn and {
                                    UI.Label {
                                        text = "V",
                                        fontSize = 12,
                                        fontWeight = "bold",
                                        fontColor = Theme.colors.btnPrimaryText,
                                    },
                                } or {},
                            },
                            UI.Label {
                                text = qLabel,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = qColor,
                            },
                        },
                    },
                    -- 单件产出提示
                    (function()
                        local y = DataItems.DECOMPOSE_YIELD[qKey]
                        local parts = {}
                        if (y.lingchen or 0) > 0 then parts[#parts + 1] = "灵尘x" .. y.lingchen end
                        if (y.xianshi or 0) > 0 then parts[#parts + 1] = "仙石x" .. y.xianshi end
                        if (y.jingxue or 0) > 0 then parts[#parts + 1] = "精血x" .. y.jingxue end
                        return UI.Label {
                            text = table.concat(parts, " "),
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        }
                    end)(),
                },
            }
        end
    end

    -- 汇总信息
    local labelMap = { lingchen = "灵尘", xianshi = "仙石", tianyuan = "天元精魄", jingxue = "灵兽精血" }
    local yieldParts = {}
    for _, k in ipairs({ "lingchen", "xianshi", "tianyuan", "jingxue" }) do
        if (previewYields[k] or 0) > 0 then
            yieldParts[#yieldParts + 1] = (labelMap[k] or k) .. " x" .. previewYields[k]
        end
    end
    local yieldText = #yieldParts > 0 and table.concat(yieldParts, "  ") or "无"

    return Comp.Dialog({
        title = "批量分解法宝",
        children = {
            UI.Label {
                text = "勾选要分解的法宝品阶（已装备法宝不会被分解）：",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
            },
            UI.Panel {
                width = "100%", gap = 2, marginTop = 4,
                children = checkRows,
            },
            -- 分隔线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Theme.colors.border,
                marginVertical = 8,
            },
            -- 汇总
            UI.Label {
                text = "将分解 " .. previewCount .. " 件法宝",
                fontSize = Theme.fontSize.body,
                fontWeight = "bold",
                fontColor = previewCount > 0 and Theme.colors.textLight or Theme.colors.textSecondary,
            },
            UI.Label {
                text = "预计获得: " .. yieldText,
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.gold,
                marginTop = 2,
            },
        },
        confirmText = previewCount > 0 and ("分解 " .. previewCount .. " 件") or "无可分解",
        cancelText = "取消",
        onConfirm = function()
            if previewCount <= 0 then
                Toast.Show("没有可分解的法宝", { variant = "error" })
                return
            end
            GameArtifact.DoBatchDecompose(sel, function(ok, data)
                local msg = ok
                    and ("批量分解完成，分解了 " .. (data.count or 0) .. " 件法宝")
                    or  (data and data.msg or "批量分解失败")
                Toast.Show(msg, { variant = ok and "success" or "error" })
                M._showBatchDecomp = false
                M._batchDecompQualities = nil
                Router.HandleNavigate("home_artifact")
            end)
        end,
        onCancel = function()
            M._showBatchDecomp = false
            M._batchDecompQualities = nil
            Router.RebuildUI()
        end,
    })
end

function M.BuildArtifact(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local arts = p.artifacts or {}
    local equipped = p.equippedItems or {}

    local cardList = { BuildBackRow("法宝") }

    -- 已穿戴装备区（来自储物页穿戴的装备）
    local hasEquipped = false
    for _, _ in pairs(equipped) do hasEquipped = true; break end
    if hasEquipped then
        local equipSlots = {}
        for _, slotDef in ipairs(DataItems.EQUIP_SLOTS) do
            local eq = equipped[slotDef.slot]
            local qColor = eq and DataItems.GetQualityColor(eq.quality or "common") or { 60, 55, 45, 200 }
            equipSlots[#equipSlots + 1] = UI.Panel {
                width = "18%",
                aspectRatio = 1,
                borderRadius = Theme.radius.sm,
                backgroundColor = eq and { 50, 45, 35, 255 } or { 35, 30, 25, 200 },
                borderColor = qColor,
                borderWidth = 1,
                justifyContent = "center",
                alignItems = "center",
                gap = 1,
                children = {
                    UI.Label {
                        text = eq and eq.name or slotDef.label,
                        fontSize = 9,
                        fontWeight = eq and "bold" or "normal",
                        fontColor = eq and Theme.colors.textLight or { 80, 75, 65, 200 },
                        textAlign = "center",
                    },
                    eq and UI.Label {
                        text = DataItems.GetQualityLabel(eq.quality or "common"),
                        fontSize = 7,
                        fontColor = qColor,
                    } or nil,
                },
            }
        end
        cardList[#cardList + 1] = Comp.BuildCardPanel("已装备(储物)", {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 4,
                justifyContent = "center",
                children = equipSlots,
            },
        })
    end

    if #arts == 0 and not hasEquipped then
        cardList[#cardList + 1] = Comp.BuildCardPanel(nil, {
            UI.Label {
                text = "暂无法宝，可前往坊市购买或游历获取。",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
        })
    else
        for _, art in ipairs(arts) do
            cardList[#cardList + 1] = BuildArtifactCard(art)
        end
    end

    -- 批量分解按钮（至少有 1 件未装备法宝时显示）
    if #arts > 0 then
        local hasUnequipped = false
        for _, art in ipairs(arts) do
            if not art.equipped then hasUnequipped = true; break end
        end
        if hasUnequipped then
            cardList[#cardList + 1] = UI.Panel {
                width = "100%",
                alignItems = "flex-end",
                marginBottom = 4,
                children = {
                    Comp.BuildSecondaryButton("批量分解", function()
                        M._showBatchDecomp = true
                        M._batchDecompQualities = nil
                        Router.RebuildUI()
                    end, {
                        width = 100,
                        fontSize = Theme.fontSize.small,
                        bg = Theme.colors.accent,
                    }),
                },
            }
        end
    end

    -- 分解确认对话框
    local decompDialog = BuildDecomposeConfirm()
    if decompDialog then
        cardList[#cardList + 1] = decompDialog
    end

    -- 洗炼确认对话框
    local rerollDialog = BuildRerollConfirm()
    if rerollDialog then
        cardList[#cardList + 1] = rerollDialog
    end

    -- 批量分解确认对话框
    local batchDecompDialog = BuildBatchDecomposeConfirm()
    if batchDecompDialog then
        cardList[#cardList + 1] = batchDecompDialog
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 页面4：悟道
-- ============================================================================
local function BuildDaoCard(dao, p)
    local isLocked  = dao.locked
    local isMastered = (dao.progress or 0) >= (dao.maxProgress or 100)
    local pct       = isMastered and 100 or math.floor((dao.progress or 0) / (dao.maxProgress or 100) * 100)
    local freeRemain = GameDao.GetFreeRemain()
    local cost      = (not isLocked and not isMastered) and GameDao.GetMeditateCost(dao.name) or 0
    local isFree    = freeRemain > 0 and not isLocked and not isMastered
    local canAfford = isFree or cost == 0 or ((p.cultivation or 0) >= cost)

    local function fmtNum(n)
        if n >= 10000 then return string.format("%.1f万", n / 10000) end
        return tostring(n)
    end

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Label {
                    text = dao.name,
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                },
                UI.Label {
                    text = isLocked and "未解锁" or (isMastered and "已悟透" or (pct .. "%")),
                    fontSize = Theme.fontSize.small,
                    fontColor = isMastered and Theme.colors.successLight
                        or (isLocked and Theme.colors.textSecondary or Theme.colors.gold),
                },
            },
        },
        -- 描述
        UI.Label {
            text = dao.desc,
            fontSize = Theme.fontSize.small,
            fontColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
            whiteSpace = "normal",
        },
        -- 奖励
        UI.Label {
            text = "悟透奖励: " .. (dao.reward or ""),
            fontSize = Theme.fontSize.small,
            fontColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.successLight,
        },
        -- 进度条
        not isLocked and UI.Panel {
            width = "100%",
            height = 8,
            borderRadius = 4,
            backgroundColor = { 50, 45, 35, 255 },
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = tostring(pct) .. "%",
                    height = "100%",
                    borderRadius = 4,
                    backgroundColor = isMastered and Theme.colors.successLight or Theme.colors.gold,
                },
            },
        } or nil,
        -- 操作行：消耗修为 + 参悟按钮
        not isLocked and not isMastered and UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            marginTop = 6,
            children = {
                -- 消耗提示
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 4,
                    children = isFree and {
                        UI.Label {
                            text = "免费参悟",
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            fontColor = Theme.colors.successLight,
                        },
                        UI.Label {
                            text = "（剩余" .. freeRemain .. "次）",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        },
                    } or {
                        UI.Label {
                            text = "消耗修为",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        },
                        UI.Label {
                            text = fmtNum(cost),
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            fontColor = canAfford and Theme.colors.textGold or { 255, 90, 70, 255 },
                        },
                        not canAfford and UI.Label {
                            text = "（不足）",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = { 255, 90, 70, 200 },
                        } or nil,
                    },
                },
                -- 参悟按钮
                Comp.BuildSecondaryButton(isFree and "免费参悟" or "参悟", function()
                    local ok, msg = GameDao.DoMeditate(dao.name)
                    if not ok then
                        Toast.Show(msg or "无法参悟", { variant = "error" })
                    end
                end, {
                    width = 90,
                    fontSize = Theme.fontSize.small,
                    disabled = not canAfford,
                }),
            },
        } or nil,
        -- 已悟透提示
        isMastered and UI.Label {
            text = "此道已悟透，奖励已生效",
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.successLight,
            textAlign = "center",
            width = "100%",
            paddingTop = 4,
        } or nil,
    })
end

function M.BuildDao(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local insights = p.daoInsights or {}

    local cardList = { BuildBackRow("悟道") }

    -- 每日悟道统计面板
    local freeRemain, freeTotal = GameDao.GetFreeRemain()
    local daoGained, daoCap = GameDao.GetDailyDaoProgress()
    local daoPct = daoCap > 0 and math.min(100, math.floor(daoGained / daoCap * 100)) or 0
    cardList[#cardList + 1] = Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = {
                        UI.Label {
                            text = "每日免费",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        },
                        UI.Label {
                            text = freeRemain .. "/" .. freeTotal,
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            fontColor = freeRemain > 0 and Theme.colors.successLight or Theme.colors.textSecondary,
                        },
                    },
                },
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    gap = 6,
                    children = {
                        UI.Label {
                            text = "今日道心",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.textSecondary,
                        },
                        UI.Label {
                            text = daoGained .. "/" .. daoCap,
                            fontSize = Theme.fontSize.small,
                            fontWeight = "bold",
                            fontColor = daoGained >= daoCap and { 255, 180, 60, 255 } or Theme.colors.textGold,
                        },
                    },
                },
            },
        },
        -- 道心进度条
        UI.Panel {
            width = "100%",
            height = 6,
            borderRadius = 3,
            backgroundColor = { 50, 45, 35, 255 },
            marginTop = 4,
            overflow = "hidden",
            children = {
                UI.Panel {
                    width = tostring(daoPct) .. "%",
                    height = "100%",
                    borderRadius = 3,
                    backgroundColor = daoGained >= daoCap and { 255, 180, 60, 255 } or Theme.colors.gold,
                },
            },
        },
    })

    if #insights == 0 then
        cardList[#cardList + 1] = Comp.BuildCardPanel(nil, {
            UI.Label {
                text = "尚未开始参悟大道，修为提升后可解锁悟道。",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
            },
        })
    else
        for _, dao in ipairs(insights) do
            cardList[#cardList + 1] = BuildDaoCard(dao, p)
        end
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 页面5：渡劫
-- ============================================================================
function M.BuildTribulation(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local tier = p.tier or 1
    local sub  = p.sub or 1
    local canSub, subReason, subExtra = GameCultivation.CanAdvanceSub()
    local canTrib, tribReason = GameCultivation.CanTribulation()

    -- 判断当前阶段：小境界突破 or 渡劫
    -- sub: 1=初期 2=中期 3=后期 4=大圆满；只有大圆满(sub=4)才需要渡劫
    local isSubBreak = (sub < 4)  -- 非大圆满期 → 小境界突破
    local currentRealm = DataRealms.GetFullName(tier, sub)
    local nextRealm
    if isSubBreak then
        nextRealm = DataRealms.GetFullName(tier, sub + 1)
    elseif tier < 10 then
        nextRealm = DataRealms.GetFullName(tier + 1, 1)
    else
        nextRealm = "已至巅峰"
    end

    -- 渡劫条件
    local cultMet = (p.cultivation or 0) >= (p.cultivationMax or 0)
    local reqs = {
        { label = "修为", current = p.cultivation or 0, need = p.cultivationMax or 0, met = cultMet },
    }
    if not isSubBreak then
        reqs[#reqs + 1] = { label = "境界", current = DataRealms.GetFullName(tier, sub), need = DataRealms.GetFullName(tier, 4), met = (sub >= 4) }
    end

    local reqRows = {}
    for _, req in ipairs(reqs) do
        local valText
        if type(req.current) == "number" then
            valText = req.current .. " / " .. req.need
        else
            valText = tostring(req.current) .. " (" .. tostring(req.need) .. ")"
        end
        reqRows[#reqRows + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            paddingVertical = 2,
            children = {
                UI.Label {
                    text = req.label,
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = valText,
                    fontSize = Theme.fontSize.body,
                    fontWeight = "bold",
                    fontColor = req.met and Theme.colors.successLight or Theme.colors.dangerLight,
                },
            },
        }
    end

    -- 天劫信息（仅渡劫时显示）
    local tribInfoCard = nil
    local tribInfo = GameCultivation.GetTribulationInfo()
    if not isSubBreak and tribInfo then
        tribInfoCard = Comp.BuildCardPanel("天劫信息", {
            Comp.BuildStatRow("劫难类型", tribInfo.name, { valueColor = Theme.colors.dangerLight }),
            Comp.BuildStatRow("成功率", tribInfo.successRate .. "%", {
                valueColor = tribInfo.successRate >= 70 and Theme.colors.successLight or Theme.colors.warning,
            }),
            Comp.BuildStatRow("突破奖励", "全属性大幅提升", { valueColor = Theme.colors.gold }),
        })
    end

    -- 突破辅助丹药选择（仅渡劫时显示）
    local breakPills = {}
    local pillSelectCard = nil
    if not isSubBreak then
        breakPills = GameCultivation.GetBreakthroughPills()
    end
    -- 用模块级表记录选中状态（按丹药名 → bool）
    M._selectedPills = M._selectedPills or {}

    if not isSubBreak and #breakPills > 0 then
        local pillRows = {}
        local totalBonus = 0
        for _, bp in ipairs(breakPills) do
            local isOn = M._selectedPills[bp.name] or false
            if isOn then
                if bp.name == "筑基丹" then totalBonus = totalBonus + 20
                elseif bp.name == "破劫丹" then totalBonus = totalBonus + 30
                end
            end
            pillRows[#pillRows + 1] = UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                paddingVertical = 4,
                children = {
                    UI.Panel {
                        flexShrink = 1,
                        gap = 2,
                        children = {
                            UI.Label {
                                text = bp.name .. " x" .. bp.count,
                                fontSize = Theme.fontSize.body,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textLight,
                            },
                            UI.Label {
                                text = bp.effect,
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.successLight,
                            },
                        },
                    },
                    Comp.BuildSecondaryButton(isOn and "已选用" or "使用", function()
                        M._selectedPills[bp.name] = not M._selectedPills[bp.name]
                        Router.EnterState(Router.STATE_TRIBULATION)
                    end, {
                        width = 70,
                        fontSize = Theme.fontSize.small,
                        bg = isOn and Theme.colors.gold or nil,
                        textColor = isOn and Theme.colors.btnPrimaryText or nil,
                    }),
                },
            }
        end
        if totalBonus > 0 and tribInfo then
            pillRows[#pillRows + 1] = UI.Panel {
                width = "100%",
                paddingTop = 4,
                borderTopWidth = 1,
                borderColor = Theme.colors.border,
                children = {
                    UI.Label {
                        text = "丹药加成后成功率: " .. math.min(100, tribInfo.successRate + totalBonus) .. "%",
                        fontSize = Theme.fontSize.small,
                        fontWeight = "bold",
                        fontColor = Theme.colors.gold,
                    },
                },
            }
        end
        pillSelectCard = Comp.BuildCardPanel("突破辅助丹药", pillRows)
    end

    local allMet = isSubBreak and canSub or canTrib
    local btnText = isSubBreak and "突破" or "开始渡劫"
    if not allMet then btnText = "条件不足" end

    local contentChildren = {
        BuildBackRow(isSubBreak and "突破" or "渡劫"),

        -- 当前境界
        Comp.BuildCardPanel("境界突破", {
            UI.Panel {
                width = "100%",
                alignItems = "center",
                gap = 8,
                paddingVertical = 8,
                children = {
                    UI.Label {
                        text = currentRealm,
                        fontSize = Theme.fontSize.title,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = "▼",
                        fontSize = Theme.fontSize.heading,
                        fontColor = Theme.colors.gold,
                    },
                    UI.Label {
                        text = nextRealm,
                        fontSize = Theme.fontSize.title,
                        fontWeight = "bold",
                        fontColor = Theme.colors.gold,
                    },
                },
            },
        }),

        -- 突破/渡劫条件
        Comp.BuildCardPanel(isSubBreak and "突破条件" or "渡劫条件", reqRows),

        -- 天劫信息
        tribInfoCard,

        -- 突破丹药选择
        pillSelectCard,

        -- 操作按钮
        UI.Panel {
            width = "100%",
            alignItems = "center",
            marginTop = 8,
            children = {
                Comp.BuildInkButton(btnText, function()
                    if isSubBreak then
                        if canSub then
                            GameCultivation.AdvanceSub(function(ok, msg)
                                Toast.Show(msg, { variant = ok and "success" or "error" })
                                M._selectedPills = {}
                                Router.EnterState(Router.STATE_TRIBULATION)
                            end)
                        else
                            local toastMsg = subReason
                            if subReason == "dao_heart" and subExtra then
                                toastMsg = string.format("道心不足（当前 %d，需 %d）", subExtra.current, subExtra.required)
                            end
                            Toast.Show(toastMsg or "突破条件不足", { variant = "error" })
                        end
                    else
                        if canTrib then
                            M._showTribConfirm = true
                            Router.RebuildUI()
                        else
                            Toast.Show(tribReason or "渡劫条件不足", { variant = "error" })
                        end
                    end
                end, { disabled = not allMet }),
            },
        },
    }

    local pageShell = Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)

    -- 渡劫确认弹窗
    if M._showTribConfirm and not isSubBreak and tribInfo then
        local rateColor = tribInfo.successRate >= 70 and Theme.colors.successLight or Theme.colors.warning
        local confirmOverlay = UI.Panel {
            position = "absolute",
            top = 0, left = 0, right = 0, bottom = 0,
            backgroundColor = { 0, 0, 0, 160 },
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Panel {
                    width = "85%",
                    backgroundColor = Theme.colors.bgCard,
                    borderRadius = Theme.radius.lg,
                    borderColor = Theme.colors.dangerLight,
                    borderWidth = 2,
                    padding = 20,
                    gap = 12,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = "渡劫确认",
                            fontSize = Theme.fontSize.heading,
                            fontWeight = "bold",
                            fontColor = Theme.colors.dangerLight,
                        },
                        Comp.BuildStatRow("劫难类型", tribInfo.name, { valueColor = Theme.colors.dangerLight }),
                        Comp.BuildStatRow("成功率", tribInfo.successRate .. "%", { valueColor = rateColor }),
                        UI.Label {
                            text = "渡劫失败将受到重创，修为倒退，确定要渡劫吗？",
                            fontSize = Theme.fontSize.body,
                            fontColor = Theme.colors.warning,
                            textAlign = "center",
                            marginTop = 4,
                        },
                        UI.Panel {
                            width = "100%",
                            flexDirection = "row",
                            justifyContent = "center",
                            gap = 20,
                            marginTop = 8,
                            children = {
                                Comp.BuildInkButton("取消", function()
                                    M._showTribConfirm = false
                                    Router.RebuildUI()
                                end, { width = 100, variant = "secondary" }),
                                Comp.BuildInkButton("确认渡劫", function()
                                    M._showTribConfirm = false
                                    local pillNames = {}
                                    for name, on in pairs(M._selectedPills or {}) do
                                        if on then pillNames[#pillNames + 1] = name end
                                    end
                                    GameCultivation.DoTribulation(
                                        #pillNames > 0 and pillNames or nil,
                                        function(ok, msg)
                                            Toast.Show(msg, { variant = ok and "success" or "error" })
                                            M._selectedPills = {}
                                            Router.EnterState(Router.STATE_TRIBULATION)
                                        end
                                    )
                                end, { width = 120 }),
                            },
                        },
                    },
                },
            },
        }
        return UI.Panel {
            width = "100%", height = "100%",
            children = { pageShell, confirmOverlay },
        }
    end

    return pageShell
end

-- ============================================================================
-- 页面6：丹药
-- ============================================================================
local function BuildPillCard(pill)
    if not pill then return nil end
    local count = pill.count or 0
    -- 网络模式：始终显示"服用"按钮，由服务端做权威校验
    -- 客户端缓存可能滞后（pills count=0 但服务端实际 >0），不做客户端拦截
    ---@diagnostic disable-next-line: undefined-global
    local isOnline = IsNetworkMode()

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "space-between",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row",
                    gap = 6,
                    alignItems = "center",
                    children = {
                        UI.Label {
                            text = pill.name,
                            fontSize = Theme.fontSize.subtitle,
                            fontWeight = "bold",
                            fontColor = DataItems.GetPillQualityColor(pill.quality),
                        },
                        -- 只在能解析为中文品阶时才显示
                        DataItems.PILL_QUALITY[pill.quality] and UI.Label {
                            text = "[" .. DataItems.PILL_QUALITY[pill.quality].label .. "]",
                            fontSize = Theme.fontSize.tiny,
                            fontColor = DataItems.GetPillQualityColor(pill.quality),
                        } or nil,
                    },
                },
                UI.Label {
                    text = "x" .. count,
                    fontSize = Theme.fontSize.subtitle,
                    fontWeight = "bold",
                    fontColor = count > 0 and Theme.colors.gold or Theme.colors.textSecondary,
                },
            },
        },
        -- 描述
        UI.Label {
            text = pill.desc,
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textLight,
        },
        -- 效果
        UI.Label {
            text = "效果: " .. (pill.effect or pill.desc or ""),
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.successLight,
        },
        -- 操作：网络模式始终显示"服用"，服务端校验；单机按本地数量判断
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "flex-end",
            marginTop = 4,
            children = {
                (isOnline or count > 0)
                    and Comp.BuildSecondaryButton("服用", function()
                        local ok, msg = GameItems.DoUsePill(pill.name)
                        if not ok then
                            Toast.Show(msg or "无法服用", "error")
                        end
                    end, { width = 80, fontSize = Theme.fontSize.small })
                    or UI.Label {
                        text = "数量不足",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                    },
            },
        },
    })
end

function M.BuildPill(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end
    local ownedPills = p.pills or {}

    -- 建立 name → owned pill 的映射表
    local ownedMap = {}
    for _, pill in ipairs(ownedPills) do
        ownedMap[pill.name] = pill
    end

    -- 合并所有丹方定义 + 玩家拥有数量
    local allCategories = {
        { title = "常用丹药",     list = DataItems.PILLS_COMMON },
        { title = "限制丹药",     list = DataItems.PILLS_LIMITED },
        { title = "突破辅助丹药", list = DataItems.PILLS_BREAKTHROUGH },
    }

    local cardList = { BuildBackRow("丹药") }

    for _, cat in ipairs(allCategories) do
        local catCards = {}
        for _, def in ipairs(cat.list) do
            local owned = ownedMap[def.name]
            local count = owned and (owned.count or 0) or 0
            if count > 0 then
                local pill = {
                    name    = def.name,
                    quality = owned and owned.quality or def.quality,
                    effect  = def.effect,
                    desc    = def.effect,
                    count   = count,
                }
                catCards[#catCards + 1] = BuildPillCard(pill)
            end
        end
        -- 有丹药时才显示分类标题
        if #catCards > 0 then
            cardList[#cardList + 1] = UI.Panel {
                width = "100%", paddingLeft = 4, paddingTop = 8, paddingBottom = 2,
                children = {
                    UI.Label {
                        text = cat.title,
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                        fontWeight = "bold",
                    },
                },
            }
            for _, card in ipairs(catCards) do
                cardList[#cardList + 1] = card
            end
        end
    end

    return Comp.BuildPageShell("home", p, cardList, Router.HandleNavigate)
end

-- ============================================================================
-- 战斗统计页面
-- ============================================================================
function M.BuildStats(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local stats = p.afkStats or {}

    -- 格式化时长
    local totalSec = stats.totalAfkTime or 0
    local hours = math.floor(totalSec / 3600)
    local mins  = math.floor((totalSec % 3600) / 60)
    local timeStr = hours > 0
        and (hours .. "小时" .. mins .. "分")
        or  (mins .. "分钟")

    -- 胜率
    local totalBattles = stats.totalBattles or 0
    local totalWins    = stats.totalWins or 0
    local winRate = totalBattles > 0
        and (math.floor(totalWins / totalBattles * 100) .. "%")
        or  "暂无"

    local contentChildren = {
        BuildBackRow("战斗统计", Router.STATE_EXPLORE),

        -- 总览卡片
        Comp.BuildCardPanel("生涯总览", {
            Comp.BuildStatRow("总战斗次数", tostring(totalBattles)),
            Comp.BuildStatRow("胜利", tostring(totalWins), {
                valueColor = Theme.colors.successLight,
            }),
            Comp.BuildStatRow("失败", tostring(stats.totalLosses or 0), {
                valueColor = Theme.colors.dangerLight,
            }),
            Comp.BuildStatRow("胜率", winRate, {
                valueColor = Theme.colors.textGold,
            }),
            Comp.BuildStatRow("Boss击杀", tostring(stats.bossKills or 0), {
                valueColor = Theme.colors.gold,
            }),
        }),

        -- 收获卡片
        Comp.BuildCardPanel("累计收获", {
            Comp.BuildStatRow("累计灵石", tostring(stats.totalLingStone or 0), {
                valueColor = Theme.colors.textGold,
            }),
            Comp.BuildStatRow("装备掉落", tostring(stats.totalEquipDrops or 0)),
            Comp.BuildStatRow("材料掉落", tostring(stats.totalMatDrops or 0)),
            Comp.BuildStatRow("采集次数", tostring(stats.totalGather or 0)),
        }),

        -- 自动回收卡片
        Comp.BuildCardPanel("自动回收", {
            Comp.BuildStatRow("回收装备数", tostring(stats.totalAutoSold or 0)),
            Comp.BuildStatRow("回收灵石", tostring(stats.totalAutoSoldLingStone or 0), {
                valueColor = Theme.colors.textGold,
            }),
        }),

        -- 挂机卡片
        Comp.BuildCardPanel("挂机数据", {
            Comp.BuildStatRow("累计挂机", timeStr),
        }),
    }

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
