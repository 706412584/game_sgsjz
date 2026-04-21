-- ============================================================================
-- ui_fengshui.lua — 风水阵系统 UI (Modal 弹窗)
-- 5阵位升级 + 称号展示 + 排行榜
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local M = {}

-- ========== 辅助函数 ==========

--- 计算所有阵位总等级
local function getTotalLevel()
    local fs = State.state.fengshui or {}
    local total = 0
    for _, f in ipairs(Config.FengshuiFormations) do
        total = total + (fs[f.id] or 0)
    end
    return total
end

--- 格式化百分比
local function fmtPct(v)
    return string.format("+%.0f%%", v * 100)
end

-- ========== UI 构建 ==========

--- 创建单个阵位卡片
local function createFormationCard(formation)
    local fs = State.state.fengshui or {}
    local lvl = fs[formation.id] or 0
    local isMax = lvl >= Config.FengshuiMaxLevel
    local cost = not isMax and Config.GetFengshuiCost(lvl) or 0
    local bonus = Config.GetFengshuiBonus(lvl)
    local nextBonus = not isMax and Config.GetFengshuiBonus(lvl + 1) or bonus
    local canUpgrade = not isMax and ((State.state.lingshi or 0) >= cost)
    local c = formation.color

    return UI.Panel {
        width = "100%",
        padding = 6,
        gap = 4,
        backgroundColor = { c[1], c[2], c[3], 30 },
        borderRadius = 6,
        borderWidth = 1,
        borderColor = { c[1], c[2], c[3], 80 },
        children = {
            -- 第一行: 阵名 + 等级 + 升级按钮
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                gap = 4,
                children = {
                    UI.Label {
                        text = formation.name .. " Lv." .. lvl .. "/" .. Config.FengshuiMaxLevel,
                        fontSize = 11,
                        fontColor = c,
                        fontWeight = "bold",
                        flexShrink = 1,
                    },
                    UI.Panel { flexGrow = 1 },
                    isMax and UI.Label {
                        text = "已满级",
                        fontSize = 9,
                        fontColor = Config.Colors.jade,
                    } or UI.Button {
                        text = HUD.FormatNumber(cost),
                        fontSize = 9,
                        height = 24,
                        paddingHorizontal = 8,
                        disabled = not canUpgrade,
                        backgroundColor = canUpgrade and { c[1], c[2], c[3], 180 } or { 60, 60, 70, 200 },
                        textColor = canUpgrade and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                        borderRadius = 6,
                        onClick = function(self)
                            GameCore.SendGameAction("fengshui_upgrade", { formationId = formation.id })
                        end,
                    },
                },
            },
            -- 第二行: 加成说明
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = formation.desc,
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = isMax and ("加成 " .. fmtPct(bonus))
                            or ("加成 " .. fmtPct(bonus) .. " -> " .. fmtPct(nextBonus)),
                        fontSize = 9,
                        fontColor = isMax and Config.Colors.jade or Config.Colors.textGold,
                        flexShrink = 0,
                    },
                },
            },
        },
    }
end

--- 创建称号区域
local function createTitleSection()
    local totalLevel = getTotalLevel()
    local titleCfg = Config.GetFengshuiTitle(totalLevel)
    local titleText = titleCfg and titleCfg.title or "无称号"
    local titleColor = titleCfg and titleCfg.color or Config.Colors.textSecond
    local titleBonus = titleCfg and fmtPct(titleCfg.bonus) or "+0%"

    -- 下一称号进度
    local nextTitle = nil
    for _, t in ipairs(Config.FengshuiTitles) do
        if totalLevel < t.totalLevel then
            nextTitle = t
            break
        end
    end

    local children = {
        UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            justifyContent = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = titleText,
                    fontSize = 13,
                    fontColor = titleColor,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "(" .. titleBonus .. " 全局加成)",
                    fontSize = 9,
                    fontColor = Config.Colors.textSecond,
                },
            },
        },
        UI.Label {
            text = "总等级: " .. totalLevel .. " / " .. (Config.FengshuiMaxLevel * #Config.FengshuiFormations),
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
        },
    }

    if nextTitle then
        table.insert(children, UI.Label {
            text = "下一称号: " .. nextTitle.title .. " (需总等级 " .. nextTitle.totalLevel .. ")",
            fontSize = 8,
            fontColor = nextTitle.color,
            textAlign = "center",
        })
    end

    return UI.Panel {
        padding = 6,
        gap = 3,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 6,
        borderWidth = 1,
        borderColor = Config.Colors.borderGold,
        alignItems = "center",
        children = children,
    }
end

--- 创建排行榜跳转按钮(复用主页排行榜)
local function createRankButton()
    local Rank = require("ui_rank")
    return UI.Button {
        text = "查看风水排行榜",
        fontSize = 10,
        height = 30,
        width = "100%",
        borderRadius = 6,
        backgroundColor = Config.Colors.panelLight,
        textColor = Config.Colors.purple,
        borderWidth = 1,
        borderColor = Config.Colors.purple,
        onClick = function(self)
            Rank.ShowRankModal()
        end,
    }
end

-- ========== 公开接口 ==========

--- 打开风水阵弹窗
function M.ShowFengshuiModal()
    -- 构建阵位列表
    local formationCards = {}
    for _, formation in ipairs(Config.FengshuiFormations) do
        table.insert(formationCards, createFormationCard(formation))
    end

    -- 构建内容 children（避免 table.unpack 中间位置截断）
    local contentChildren = {
        createTitleSection(),
        UI.Label {
            text = "阵位升级",
            fontSize = 11,
            fontColor = Config.Colors.textGold,
            fontWeight = "bold",
        },
    }
    for _, card in ipairs(formationCards) do
        table.insert(contentChildren, card)
    end
    -- 排行榜跳转按钮
    table.insert(contentChildren, createRankButton())

    local modal = UI.Modal {
        title = "风水阵",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
        children = {
            UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    UI.Panel {
                        width = "100%",
                        gap = 6,
                        padding = 6,
                        children = contentChildren,
                    },
                },
            },
        },
    }

    modal:Open()

    -- 监听升级事件 → 刷新弹窗
    local unsub
    unsub = State.On("fengshui_upgraded", function()
        if not modal or not modal.node then
            if unsub then unsub() end
            return
        end
        -- 关闭并重新打开刷新
        modal:Destroy()
        if unsub then unsub() end
        M.ShowFengshuiModal()
    end)
end

return M
