------------------------------------------------------------
-- ui/page_battle.lua  —— 三国神将录 战斗回放页
-- Phase 2: 适配 battle_engine 输出格式
-- 显示三围/士气条/暴击/状态效果/伤害统计
------------------------------------------------------------
local UI     = require("urhox-libs/UI")
local Theme  = require("ui.theme")
local Comp   = require("ui.components")
local Modal  = require("ui.modal_manager")
local C      = Theme.colors
local S      = Theme.sizes

local M = {}

-- 内部状态
local pagePanel_
local logContainer_
local roundLabel_
local hpBars_ = {}       -- { [unitId] = progressBar }
local moraleBars_ = {}   -- { [unitId] = progressBar }
local statusLabels_ = {} -- { [unitId] = label }
local battleLog_
local currentRound_  = 0
local roundTimer_    = 0
local actionIndex_   = 0
local statusTickIdx_ = 0
local playing_       = false
local speed_         = 1
local speedBtn_
local onBattleEnd_

------------------------------------------------------------
-- 状态效果中文映射
------------------------------------------------------------
local STATUS_NAMES = {
    stun        = "眩晕",
    silence     = "沉默",
    burn        = "灼烧",
    armor_break = "破甲",
    charm       = "混乱",
    freeze      = "冰冻",
    shield      = "护盾",
    hot         = "回血",
    atk_up      = "增攻",
    def_up      = "增防",
    speed_up    = "加速",
}

local STATUS_COLORS = {
    stun        = C.gold,
    silence     = C.mp,
    burn        = C.red,
    armor_break = C.red,
    charm       = C.exp,
    freeze      = C.mp,
    shield      = C.jade,
    hot         = C.hp,
    atk_up      = C.gold,
    def_up      = C.jade,
    speed_up    = C.mp,
}

------------------------------------------------------------
-- 构建单个单位 UI (头像 + HP条 + 士气条)
------------------------------------------------------------
local function createUnitUI(unit, side)
    local nameColor = side == "ally" and C.jade or C.red
    local hpColor   = side == "ally" and C.hp  or C.red

    -- HP 条
    local hpBar = UI.ProgressBar {
        value           = 1.0,
        width           = "100%",
        height          = 5,
        backgroundColor = { 40, 40, 40, 255 },
        borderRadius    = 2,
        fillColor       = hpColor,
    }
    hpBars_[unit.id] = hpBar

    -- 士气条(金色)
    local moraleBar = UI.ProgressBar {
        value           = (unit.morale or 0) / 100,
        width           = "100%",
        height          = 3,
        backgroundColor = { 40, 40, 40, 255 },
        borderRadius    = 1,
        fillColor       = C.morale,
    }
    moraleBars_[unit.id] = moraleBar

    -- 状态标签
    local statusLabel = UI.Label {
        text      = "",
        fontSize  = 7,
        fontColor = C.gold,
        textAlign = "center",
        width     = 70,
        maxLines  = 1,
    }
    statusLabels_[unit.id] = statusLabel

    -- 三围简要显示
    local statsText = ""
    if unit.tong then
        statsText = "统" .. unit.tong .. " 勇" .. unit.yong .. " 智" .. unit.zhi
    end

    return UI.Panel {
        width         = 74,
        alignItems    = "center",
        gap           = 1,
        children = {
            -- 头像
            UI.Panel {
                width           = 44,
                height          = 44,
                borderRadius    = 6,
                backgroundColor = side == "ally" and { 30, 60, 50, 255 } or { 60, 30, 30, 255 },
                borderColor     = nameColor,
                borderWidth     = 1,
                backgroundImage = unit.heroId and ("Textures/heroes/hero_" .. unit.heroId .. ".png") or nil,
                backgroundFit   = "cover",
                justifyContent  = "center",
                alignItems      = "center",
                children = (not unit.heroId) and {
                    UI.Label {
                        text      = string.sub(unit.name, 1, 6),
                        fontSize  = 9,
                        fontColor = C.text,
                        textAlign = "center",
                    },
                } or {},
            },
            -- 名字
            UI.Label {
                text      = unit.name,
                fontSize  = 9,
                fontColor = nameColor,
                textAlign = "center",
                maxLines  = 1,
                width     = 74,
            },
            -- 三围
            statsText ~= "" and UI.Label {
                text      = statsText,
                fontSize  = 7,
                fontColor = C.textDim,
                textAlign = "center",
                width     = 74,
            } or nil,
            -- HP条
            hpBar,
            -- 士气条
            moraleBar,
            -- 状态
            statusLabel,
        },
    }
end

------------------------------------------------------------
-- 构建阵容行
------------------------------------------------------------
local function createFormationRow(units, side)
    local children = {}
    for _, unit in ipairs(units) do
        children[#children + 1] = createUnitUI(unit, side)
    end
    return UI.Panel {
        flexDirection  = "row",
        justifyContent = "center",
        gap            = 4,
        children       = children,
    }
end

------------------------------------------------------------
-- 构建日志行(适配新格式)
------------------------------------------------------------
local function createLogEntry(action)
    local text = ""
    local entryColor = C.textDim

    if action.type == "attack" then
        local targetList = action.targets or {}
        local targetName = #targetList > 0 and targetList[1] or (action.target or "?")
        local dmgList = action.damages or {}
        local dmg = #dmgList > 0 and dmgList[1] or (action.damage or 0)
        local isCrit = action.isCrit and action.isCrit[1]
        local killed = action.killed and action.killed[1]

        text = action.actor .. " 普攻 " .. targetName .. "  " .. dmg
        if isCrit then
            text = text .. " [暴击!]"
            entryColor = C.gold
        end
        if killed then
            text = text .. " [击杀!]"
            entryColor = C.red
        end

    elseif action.type == "skill" then
        local targets = action.targets or {}
        local targetStr = table.concat(targets, "、")
        local damages = action.damages or {}
        local heals = action.heals or {}
        local skillName = action.name or "战法"

        text = action.actor .. " 【" .. skillName .. "】"

        if #targets > 0 then
            text = text .. " → " .. targetStr
        end

        -- 汇总伤害
        local totalDmg = 0
        for _, d in ipairs(damages) do totalDmg = totalDmg + d end
        local totalHeal = 0
        for _, h in ipairs(heals) do totalHeal = totalHeal + h end

        if totalDmg > 0 then
            text = text .. "  伤害" .. totalDmg
        end
        if totalHeal > 0 then
            text = text .. "  治疗" .. totalHeal
            entryColor = C.hp
        end

        -- 暴击检测
        local hasCrit = false
        if action.isCrit then
            for _, c in ipairs(action.isCrit) do
                if c then hasCrit = true; break end
            end
        end
        if hasCrit then
            text = text .. " [暴击!]"
            entryColor = C.gold
        end

        -- 击杀检测
        local hasKill = false
        if action.killed then
            for _, k in ipairs(action.killed) do
                if k then hasKill = true; break end
            end
        end
        if hasKill then
            text = text .. " [击杀!]"
            entryColor = C.red
        end

        -- 状态效果
        if action.statuses and #action.statuses > 0 then
            local statTexts = {}
            for _, st in ipairs(action.statuses) do
                local sName = STATUS_NAMES[st.status] or st.status
                statTexts[#statTexts + 1] = st.target .. "+" .. sName
            end
            text = text .. "  {" .. table.concat(statTexts, ", ") .. "}"
        end

    elseif action.type == "burn_tick" then
        text = action.target .. " 灼烧伤害 " .. (action.damage or 0)
        entryColor = { 255, 120, 50, 255 }

    elseif action.type == "hot_tick" then
        text = action.target .. " 持续回血 +" .. (action.heal or 0)
        entryColor = C.hp

    else
        text = (action.actor or "") .. " " .. (action.type or "行动")
    end

    return UI.Label {
        text       = text,
        fontSize   = Theme.fontSize.bodySmall,
        fontColor  = entryColor,
        whiteSpace = "normal",
        width      = "100%",
        marginBottom = 2,
    }
end

------------------------------------------------------------
-- 更新单位实时状态显示
------------------------------------------------------------
local function updateUnitStates(allUnits)
    for _, u in ipairs(allUnits) do
        -- HP条
        local hpBar = hpBars_[u.id]
        if hpBar then
            hpBar:SetValue(u.alive and math.max(0, u.hp / u.maxHp) or 0)
        end

        -- 士气条
        local mBar = moraleBars_[u.id]
        if mBar then
            mBar:SetValue((u.morale or 0) / 100)
        end

        -- 状态标签
        local sLabel = statusLabels_[u.id]
        if sLabel then
            if u.statuses and next(u.statuses) then
                local parts = {}
                for status, info in pairs(u.statuses) do
                    local sName = STATUS_NAMES[status] or status
                    parts[#parts + 1] = sName .. info.dur
                end
                sLabel.text = table.concat(parts, " ")
            else
                sLabel.text = ""
            end
        end
    end
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建战斗页
---@param log table BattleLog from battle_engine
---@param callbacks table { onBattleEnd = function() }
function M.Create(log, callbacks)
    callbacks    = callbacks or {}
    onBattleEnd_ = callbacks.onBattleEnd
    battleLog_   = log
    currentRound_ = 0
    actionIndex_  = 0
    statusTickIdx_ = 0
    roundTimer_   = 0
    playing_      = true
    speed_        = 1
    hpBars_       = {}
    moraleBars_   = {}
    statusLabels_ = {}

    -- 标题栏
    speedBtn_ = Comp.SanButton({
        text     = "x1",
        variant  = "secondary",
        height   = S.btnSmHeight,
        fontSize = S.btnSmFontSize,
        onClick  = function()
            speed_ = speed_ >= 3 and 1 or speed_ + 1
            if speedBtn_ then speedBtn_.text = "x" .. speed_ end
        end,
    })

    local titleBar = UI.Panel {
        width         = "100%",
        height        = 36,
        flexDirection = "row",
        alignItems    = "center",
        justifyContent = "space-between",
        paddingHorizontal = 12,
        backgroundColor = { C.bg[1], C.bg[2], C.bg[3], 230 },
        children = {
            UI.Label {
                text      = "第" .. (log.map_id or 1) .. "图-节点" .. (log.node_id or 1),
                fontSize  = Theme.fontSize.subtitle,
                fontColor = C.gold,
            },
            UI.Panel {
                flexDirection = "row", gap = 8, alignItems = "center",
                children = { speedBtn_ },
            },
        },
    }

    -- 回合数
    roundLabel_ = UI.Label {
        text      = "准备战斗...",
        fontSize  = Theme.fontSize.body,
        fontColor = C.text,
        textAlign = "center",
        width     = "100%",
        marginVertical = 3,
    }

    -- 分配阵容(前排/后排)
    local allies  = log.allies or {}
    local enemies = log.enemies or {}

    local allyFront, allyBack = {}, {}
    for _, u in ipairs(allies) do
        if u.row == "front" then allyFront[#allyFront + 1] = u
        else allyBack[#allyBack + 1] = u end
    end

    local enemyFront, enemyBack = {}, {}
    for _, u in ipairs(enemies) do
        if u.row == "front" then enemyFront[#enemyFront + 1] = u
        else enemyBack[#enemyBack + 1] = u end
    end

    -- 日志滚动区
    logContainer_ = UI.Panel {
        width         = "100%",
        flexDirection = "column",
        padding       = 4,
    }

    local logScroll = UI.ScrollView {
        flexGrow  = 1,
        flexBasis = 0,
        scrollY   = true,
        padding   = 4,
        children  = { logContainer_ },
    }

    -- 主布局(左右分栏: 战场 | 日志)
    pagePanel_ = UI.Panel {
        width         = "100%",
        flexGrow      = 1,
        flexBasis     = 0,
        flexDirection = "row",
        backgroundColor = C.bg,
        children = {
            -- 左侧: 战场 + 回合
            UI.Panel {
                width         = "42%",
                flexDirection = "column",
                children = {
                    titleBar,

                    -- 战场区域
                    UI.ScrollView {
                        flexGrow  = 1,
                        flexBasis = 0,
                        scrollY   = true,
                        children = {
                            UI.Panel {
                                width    = "100%",
                                padding  = 6,
                                gap      = 4,
                                alignItems = "center",
                                children = {
                                    -- 敌方
                                    UI.Label { text = "敌方", fontSize = Theme.fontSize.caption, fontColor = C.red, marginBottom = 1 },
                                    createFormationRow(enemyBack, "enemy"),
                                    createFormationRow(enemyFront, "enemy"),

                                    -- VS
                                    UI.Panel {
                                        width = 60, height = 20,
                                        justifyContent = "center", alignItems = "center",
                                        marginVertical = 2,
                                        children = {
                                            UI.Label { text = "VS", fontSize = 12, fontColor = C.gold, fontWeight = "bold" },
                                        },
                                    },

                                    -- 我方
                                    createFormationRow(allyFront, "ally"),
                                    createFormationRow(allyBack, "ally"),
                                    UI.Label { text = "我方", fontSize = Theme.fontSize.caption, fontColor = C.jade, marginTop = 1 },
                                },
                            },
                        },
                    },

                    roundLabel_,
                },
            },

            -- 分割线
            UI.Panel {
                width           = 1,
                backgroundColor = C.divider,
            },

            -- 右侧: 日志
            UI.Panel {
                flexGrow      = 1,
                flexBasis     = 0,
                flexDirection = "column",
                children = {
                    UI.Panel {
                        width = "100%",
                        paddingHorizontal = 8, paddingVertical = 4,
                        children = {
                            UI.Label {
                                text      = "战斗日志",
                                fontSize  = Theme.fontSize.subtitle,
                                fontColor = C.text,
                                fontWeight = "bold",
                            },
                        },
                    },
                    Comp.SanDivider({ spacing = 2 }),
                    logScroll,
                },
            },
        },
    }

    return pagePanel_
end

--- 战斗帧更新
---@param dt number
function M.Update(dt)
    if not playing_ or not battleLog_ then return end

    roundTimer_ = roundTimer_ + dt * speed_

    -- 每 0.6 秒播放一个 action
    if roundTimer_ < 0.6 then return end
    roundTimer_ = 0

    local rounds = battleLog_.rounds or {}

    -- 推进回合
    if currentRound_ == 0
       or (actionIndex_ >= #(rounds[currentRound_].actions or {})
           and statusTickIdx_ >= #(rounds[currentRound_].statusTicks or {})) then
        currentRound_ = currentRound_ + 1
        actionIndex_ = 0
        statusTickIdx_ = 0

        if currentRound_ > #rounds then
            -- 战斗结束
            playing_ = false
            if roundLabel_ then
                roundLabel_.text = "战斗结束"
            end

            -- 添加伤害统计到日志
            if battleLog_.result then
                local r = battleLog_.result
                if logContainer_ then
                    logContainer_:AddChild(Comp.SanDivider({ spacing = 4 }))
                    logContainer_:AddChild(UI.Label {
                        text = r.win and "胜利!" or "失败...",
                        fontSize = Theme.fontSize.title,
                        fontColor = r.win and C.gold or C.red,
                        fontWeight = "bold",
                        textAlign = "center",
                        width = "100%",
                        marginBottom = 4,
                    })
                    -- 伤害排行
                    if r.damageStats and #r.damageStats > 0 then
                        logContainer_:AddChild(UI.Label {
                            text = "伤害统计",
                            fontSize = Theme.fontSize.bodySmall,
                            fontColor = C.textDim,
                            marginBottom = 2,
                        })
                        for i, ds in ipairs(r.damageStats) do
                            logContainer_:AddChild(UI.Label {
                                text = i .. ". " .. ds.name .. "  " .. Theme.FormatNumber(ds.damage),
                                fontSize = Theme.fontSize.bodySmall,
                                fontColor = i == 1 and C.gold or C.text,
                            })
                        end
                    end
                    -- 治疗排行
                    if r.healStats and #r.healStats > 0 then
                        logContainer_:AddChild(UI.Label {
                            text = "治疗统计",
                            fontSize = Theme.fontSize.bodySmall,
                            fontColor = C.textDim,
                            marginTop = 4,
                            marginBottom = 2,
                        })
                        for i, hs in ipairs(r.healStats) do
                            logContainer_:AddChild(UI.Label {
                                text = i .. ". " .. hs.name .. "  +" .. Theme.FormatNumber(hs.heal),
                                fontSize = Theme.fontSize.bodySmall,
                                fontColor = i == 1 and C.hp or C.text,
                            })
                        end
                    end
                end

                -- 弹窗结算
                Modal.BattleResult(r, onBattleEnd_)
            end
            return
        end

        if roundLabel_ then
            roundLabel_.text = "第 " .. currentRound_ .. " / " .. #rounds .. " 回合"
        end

        -- 回合分割
        if logContainer_ then
            logContainer_:AddChild(UI.Label {
                text      = "—— 第" .. currentRound_ .. "回合 ——",
                fontSize  = Theme.fontSize.caption,
                fontColor = C.gold,
                textAlign = "center",
                width     = "100%",
                marginVertical = 3,
            })
        end
    end

    local round = rounds[currentRound_]
    local actions = round.actions or {}
    local statusTicks = round.statusTicks or {}

    -- 播放 actions
    if actionIndex_ < #actions then
        actionIndex_ = actionIndex_ + 1
        local action = actions[actionIndex_]

        if action and logContainer_ then
            logContainer_:AddChild(createLogEntry(action))
        end

        -- 更新所有单元状态
        local allUnits = {}
        for _, u in ipairs(battleLog_.allies or {})  do allUnits[#allUnits + 1] = u end
        for _, u in ipairs(battleLog_.enemies or {}) do allUnits[#allUnits + 1] = u end
        updateUnitStates(allUnits)

    elseif statusTickIdx_ < #statusTicks then
        -- 播放状态tick(灼烧/回血)
        statusTickIdx_ = statusTickIdx_ + 1
        local tick = statusTicks[statusTickIdx_]

        if tick and logContainer_ then
            logContainer_:AddChild(createLogEntry(tick))
        end

        -- 更新单元状态
        local allUnits = {}
        for _, u in ipairs(battleLog_.allies or {})  do allUnits[#allUnits + 1] = u end
        for _, u in ipairs(battleLog_.enemies or {}) do allUnits[#allUnits + 1] = u end
        updateUnitStates(allUnits)
    end
end

--- 是否正在播放
function M.IsPlaying()
    return playing_
end

--- 停止战斗
function M.Stop()
    playing_ = false
end

--- 获取页面面板
function M.GetPanel()
    return pagePanel_
end

return M
