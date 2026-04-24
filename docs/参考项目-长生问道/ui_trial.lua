-- ============================================================================
-- 《问道长生》试炼场页 —— 战斗过程可视化
-- 状态机：list -> battle -> fight_result -> (下一场 or final) -> list
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameTrial = require("game_trial")
local GameDaoTrial = require("game_dao_trial")
local Toast = require("ui_toast")
local NVG = require("nvg_manager")

local M = {}

-- ============================================================================
-- 状态常量
-- ============================================================================
local PHASE_LIST            = "list"
local PHASE_BATTLE          = "battle"
local PHASE_FIGHT_RESULT    = "fight_result"
local PHASE_FINAL           = "final"
local PHASE_HONGCHEN        = "hongchen"         -- 红尘历练：场景+选项
local PHASE_HONGCHEN_RESULT = "hongchen_result"  -- 红尘历练：结果

-- ============================================================================
-- 模块状态
-- ============================================================================
local state_ = {
    phase        = PHASE_LIST,
    -- PrepareChallenge 返回的完整结果
    challengeResult = nil,
    -- 当前场次索引
    fightIdx     = 0,
    -- 当前场次回合播放索引
    roundIdx     = 0,
    timer        = 0,
    battleLog    = {},
    -- 结算后的信息
    settled      = false,
    settleMsg    = "",
    -- 道心试炼类型标记（用于区分结算调用）
    isDaoTrial   = false,
    -- 红尘历练状态
    hongchenScene  = nil,   -- 当前场景
    hongchenResult = nil,   -- 服务端结果
}

local ROUND_INTERVAL = 0.5
local FIGHT_PAUSE    = 1.0   -- 场次间停顿
local UPDATE_KEY     = "trial_battle"

-- ============================================================================
-- 辅助：获取当前场次数据
-- ============================================================================
local function CurFight()
    local r = state_.challengeResult
    if not r then return nil end
    return r.fights[state_.fightIdx]
end

-- ============================================================================
-- 辅助：场次标签文本
-- ============================================================================
local function FightLabel()
    local r = state_.challengeResult
    if not r then return "" end
    local f = CurFight()
    if not f then return "" end
    if r.type == "闯关" then
        return "第" .. f.floor .. "层"
    elseif r.type == "生存" then
        return "第" .. f.floor .. "波"
    elseif r.type == "限时" then
        return "第" .. state_.fightIdx .. "只"
    end
    return ""
end

-- ============================================================================
-- 战斗 Update 回调
-- ============================================================================
local function BattleUpdate(dt)
    local s = state_
    if s.phase ~= PHASE_BATTLE then return end

    s.timer = s.timer + dt
    if s.timer < ROUND_INTERVAL then return end
    s.timer = s.timer - ROUND_INTERVAL

    local fight = CurFight()
    if not fight then
        s.phase = PHASE_FIGHT_RESULT
        Router.RebuildUI()
        return
    end

    s.roundIdx = s.roundIdx + 1
    if s.roundIdx > #fight.rounds then
        s.phase = PHASE_FIGHT_RESULT
        Router.RebuildUI()
        return
    end

    local round = fight.rounds[s.roundIdx]
    local pName = "我方"
    local eName = fight.enemy.name or "妖"

    -- 玩家行动日志
    local pa = round.playerAction
    if pa then
        if pa.hit then
            local critTag = pa.crit and "<c=gold>[暴击]</c>" or ""
            s.battleLog[#s.battleLog + 1] = "R" .. round.num .. ": " .. pName ..
                "击" .. eName .. critTag .. " <c=red>-" .. pa.damage .. "</c>"
        else
            s.battleLog[#s.battleLog + 1] = "R" .. round.num .. ": " .. pName ..
                "击" .. eName .. " <c=gray>未中</c>"
        end
    end

    -- 敌方行动日志
    local ea = round.enemyAction
    if ea then
        if ea.hit then
            local critTag = ea.crit and "<c=gold>[暴击]</c>" or ""
            s.battleLog[#s.battleLog + 1] = eName .. "反击" .. critTag ..
                " <c=red>-" .. ea.damage .. "</c>"
        else
            s.battleLog[#s.battleLog + 1] = eName .. "攻击 <c=gray>未中</c>"
        end
    end

    -- 回合结束
    if round.finished then
        if round.win then
            s.battleLog[#s.battleLog + 1] = "<c=gold>--- " .. eName .. " 倒下 ---</c>"
        else
            s.battleLog[#s.battleLog + 1] = "<c=red>--- 我方败退 ---</c>"
        end
        s.phase = PHASE_FIGHT_RESULT
    end

    Router.RebuildUI()
end

-- ============================================================================
-- 开始挑战
-- ============================================================================
local function StartChallenge(trialId)
    local result, err = GameTrial.PrepareChallenge(trialId)
    if not result then
        Toast.Show(err or "挑战失败", { variant = "error" })
        return
    end

    state_.phase = PHASE_BATTLE
    state_.challengeResult = result
    state_.fightIdx = 1
    state_.roundIdx = 0
    state_.timer = 0
    state_.battleLog = { "<c=gold>--- " .. result.trialName .. " 开始 ---</c>" }
    state_.settled = false
    state_.settleMsg = ""

    -- 添加首场提示
    local firstFight = result.fights[1]
    if firstFight then
        state_.battleLog[#state_.battleLog + 1] = "<c=yellow>" .. FightLabel() ..
            ": VS " .. firstFight.enemy.name .. "</c>"
    end

    NVG.Register(UPDATE_KEY, nil, BattleUpdate)
    Router.RebuildUI()
end

-- ============================================================================
-- 内部：执行结算（区分普通试炼和道心试炼）
-- ============================================================================
local function DoSettle(r)
    local s = state_
    if s.isDaoTrial then
        -- 心魔挑战走 GameDaoTrial.SettleXinmo
        s.settleMsg = "心魔挑战结算中..."
        GameDaoTrial.SettleXinmo(function(ok, data)
            if ok then
                s.settleMsg = data and data.summary or "心魔挑战完成"
                -- 存储 daoGain 到 challengeResult 供 PHASE_FINAL 展示
                if r and data then
                    r.daoGain = data.daoGain or 0
                    r.daoWin  = data.win
                end
            else
                s.settleMsg = data and data.msg or "结算失败"
            end
            Router.RebuildUI()
        end)
        return true, s.settleMsg
    else
        return GameTrial.SettleChallenge(r)
    end
end

-- ============================================================================
-- 推进到下一场或最终结算
-- ============================================================================
local function AdvanceOrSettle()
    local s = state_
    local r = s.challengeResult
    if not r then return end

    local curFight = CurFight()
    -- 如果当前场失败，直接结算
    if curFight and not curFight.win then
        s.phase = PHASE_FINAL
        if not s.settled then
            s.settled = true
            local ok, msg = DoSettle(r)
            s.settleMsg = msg
        end
        Router.RebuildUI()
        return
    end

    -- 还有下一场？
    if s.fightIdx < #r.fights then
        s.fightIdx = s.fightIdx + 1
        s.roundIdx = 0
        s.timer = 0
        s.phase = PHASE_BATTLE
        local fight = CurFight()
        if fight then
            s.battleLog[#s.battleLog + 1] = "<c=yellow>" .. FightLabel() ..
                ": VS " .. fight.enemy.name .. "</c>"
        end
        Router.RebuildUI()
    else
        -- 所有场次完成
        s.phase = PHASE_FINAL
        if not s.settled then
            s.settled = true
            local ok, msg = DoSettle(r)
            s.settleMsg = msg
        end
        Router.RebuildUI()
    end
end

-- ============================================================================
-- 跳过全部战斗
-- ============================================================================
local function SkipAll()
    local s = state_
    local r = s.challengeResult
    if not r then return end

    -- 生成所有剩余日志
    for fi = s.fightIdx, #r.fights do
        local fight = r.fights[fi]
        if fi > s.fightIdx or s.roundIdx == 0 then
            s.battleLog[#s.battleLog + 1] = "<c=yellow>" ..
                (r.type == "闯关" and ("第" .. fight.floor .. "层") or
                 r.type == "生存" and ("第" .. fight.floor .. "波") or
                 ("第" .. fi .. "只")) ..
                ": VS " .. fight.enemy.name .. "</c>"
        end
        if fight.win then
            s.battleLog[#s.battleLog + 1] = "<c=gold>击败 " .. fight.enemy.name .. "</c>"
        else
            s.battleLog[#s.battleLog + 1] = "<c=red>败于 " .. fight.enemy.name .. "</c>"
        end
    end

    s.fightIdx = #r.fights
    s.roundIdx = r.fights[s.fightIdx] and #r.fights[s.fightIdx].rounds or 0
    s.phase = PHASE_FINAL
    if not s.settled then
        s.settled = true
        local ok, msg = DoSettle(r)
        s.settleMsg = msg
    end
    Router.RebuildUI()
end

-- ============================================================================
-- 道心试炼：开始心魔挑战
-- ============================================================================
local function StartDaoXinmo()
    local result, err = GameDaoTrial.PrepareXinmo()
    if not result then
        Toast.Show(err or "无法进行心魔挑战", { variant = "error" })
        return
    end

    state_.phase = PHASE_BATTLE
    state_.challengeResult = result
    state_.isDaoTrial = true
    state_.fightIdx = 1
    state_.roundIdx = 0
    state_.timer = 0
    state_.battleLog = { "<c=gold>--- 心魔挑战 开始 ---</c>" }
    state_.settled = false
    state_.settleMsg = ""

    local firstFight = result.fights[1]
    if firstFight then
        state_.battleLog[#state_.battleLog + 1] = "<c=yellow>VS " .. firstFight.enemy.name .. "</c>"
    end

    NVG.Register(UPDATE_KEY, nil, BattleUpdate)
    Router.RebuildUI()
end

-- ============================================================================
-- 道心试炼：开始红尘历练
-- ============================================================================
local function StartHongchen()
    local ok, reason = GameDaoTrial.CanChallenge("hongchen")
    if not ok then
        Toast.Show(reason or "无法进行红尘历练", { variant = "error" })
        return
    end

    local scene = GameDaoTrial.GetRandomScene()
    if not scene then
        Toast.Show("场景数据异常", { variant = "error" })
        return
    end

    state_.phase = PHASE_HONGCHEN
    state_.hongchenScene = scene
    state_.hongchenResult = nil
    Router.RebuildUI()
end

-- ============================================================================
-- 道心试炼：提交红尘选择
-- ============================================================================
local function SubmitHongchenChoice(optionIdx)
    GameDaoTrial.SettleHongchen(optionIdx, function(ok2, data)
        if ok2 then
            state_.hongchenResult = data
            state_.phase = PHASE_HONGCHEN_RESULT
        else
            Toast.Show(data and data.msg or "红尘历练失败", { variant = "error" })
            state_.phase = PHASE_LIST
        end
        Router.RebuildUI()
    end)
end

-- ============================================================================
-- 重置状态
-- ============================================================================
local function ResetState()
    state_.phase = PHASE_LIST
    state_.challengeResult = nil
    state_.fightIdx = 0
    state_.roundIdx = 0
    state_.battleLog = {}
    state_.settled = false
    state_.settleMsg = ""
    state_.isDaoTrial = false
    state_.hongchenScene = nil
    state_.hongchenResult = nil
    NVG.Unregister(UPDATE_KEY)
end

-- ============================================================================
-- UI 组件：HP 条
-- ============================================================================
local function BuildHPBar(current, max, label, isEnemy)
    local pct = max > 0 and (current / max) or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local barColor = isEnemy and Theme.colors.danger or { 80, 180, 80, 255 }
    local hpText = tostring(math.max(0, math.floor(current))) .. "/" .. tostring(math.floor(max))

    return UI.Panel {
        width = "100%", gap = 2,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = label, fontSize = 10, fontWeight = "bold",
                        fontColor = isEnemy and Theme.colors.dangerLight or Theme.colors.successLight,
                    },
                    UI.Label {
                        text = hpText, fontSize = 9,
                        fontColor = Theme.colors.textLight,
                    },
                },
            },
            UI.Panel {
                width = "100%", height = 8, borderRadius = 4,
                backgroundColor = { 40, 35, 30, 200 }, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%", borderRadius = 4,
                        backgroundColor = barColor,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- UI 组件：战斗场景（双方对峙）
-- ============================================================================
local function BuildBattleScene(p)
    local s = state_
    local fight = CurFight()
    if not fight then return UI.Panel { width = "100%" } end

    local curRound = s.roundIdx > 0 and s.roundIdx <= #fight.rounds and fight.rounds[s.roundIdx] or nil
    local playerHP = curRound and curRound.playerHP or (p.hp or 800)
    local playerHPMax = curRound and curRound.playerHPMax or (p.hpMax or 800)
    local enemyHP = curRound and curRound.enemyHP or fight.enemy.hp
    local enemyHPMax = fight.enemy.hp

    local roundText = ""
    if s.phase == PHASE_BATTLE then
        roundText = FightLabel() .. "  回合 " .. tostring(s.roundIdx) .. "/" .. tostring(#fight.rounds)
    elseif s.phase == PHASE_FIGHT_RESULT then
        roundText = FightLabel() .. (fight.win and "  胜利" or "  败退")
    elseif s.phase == PHASE_FINAL then
        roundText = FightLabel() .. (fight.win and "  胜利" or "  败退")
    end

    local avatarIdx = p.avatarIndex or 1
    local avatarList = Theme.avatars[p.gender] or Theme.avatars["男"]
    local avatarImg = avatarList[avatarIdx] or avatarList[1]

    return UI.Panel {
        width = "100%",
        borderRadius = Theme.radius.lg,
        backgroundColor = Theme.colors.bgDark,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        padding = 10, gap = 6,
        children = {
            UI.Label {
                text = roundText, fontSize = 11,
                fontColor = Theme.colors.textGold,
                textAlign = "center", width = "100%",
            },
            UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "flex-end", justifyContent = "space-around",
                children = {
                    -- 玩家
                    UI.Panel {
                        width = "40%", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel {
                                width = 56, height = 56, borderRadius = 28, overflow = "hidden",
                                backgroundColor = { 45, 36, 28, 255 },
                                borderColor = { 80, 180, 80, 200 }, borderWidth = 2,
                                children = {
                                    UI.Panel {
                                        width = "100%", height = "100%",
                                        backgroundImage = avatarImg, backgroundFit = "cover",
                                    },
                                },
                            },
                            UI.Label {
                                text = p.name or "我", fontSize = 10, fontWeight = "bold",
                                fontColor = Theme.colors.successLight,
                            },
                            BuildHPBar(playerHP, playerHPMax, "气血", false),
                        },
                    },
                    UI.Label {
                        text = "VS", fontSize = 16, fontWeight = "bold",
                        fontColor = Theme.colors.gold, marginBottom = 24,
                    },
                    -- 怪物
                    UI.Panel {
                        width = "40%", alignItems = "center", gap = 4,
                        children = {
                            UI.Panel {
                                width = 56, height = 56, borderRadius = 28, overflow = "hidden",
                                backgroundColor = { 50, 25, 25, 255 },
                                borderColor = Theme.colors.dangerLight, borderWidth = 2,
                                children = {
                                    fight.monsterImg and UI.Panel {
                                        width = "100%", height = "100%",
                                        backgroundImage = fight.monsterImg, backgroundFit = "cover",
                                    } or UI.Label {
                                        text = "妖", fontSize = 18, fontWeight = "bold",
                                        fontColor = Theme.colors.dangerLight,
                                    },
                                },
                            },
                            UI.Label {
                                text = fight.enemy.name, fontSize = 10, fontWeight = "bold",
                                fontColor = Theme.colors.dangerLight,
                            },
                            BuildHPBar(enemyHP, enemyHPMax, "气血", true),
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- UI 组件：进度条（几场/共几场）
-- ============================================================================
local function BuildProgressBar()
    local s = state_
    local r = s.challengeResult
    if not r then return UI.Panel { width = "100%" } end

    local total = #r.fights
    local current = s.fightIdx

    local dots = {}
    for i = 1, total do
        local fight = r.fights[i]
        local dotColor
        if i < current then
            dotColor = fight.win and Theme.colors.success or Theme.colors.danger
        elseif i == current then
            dotColor = Theme.colors.gold
        else
            dotColor = { 60, 55, 45, 150 }
        end
        dots[#dots + 1] = UI.Panel {
            width = 10, height = 10, borderRadius = 5,
            backgroundColor = dotColor,
        }
    end

    -- 如果场次过多，只显示文字
    if total > 15 then
        return UI.Panel {
            width = "100%", alignItems = "center",
            children = {
                UI.Label {
                    text = "进度: " .. current .. " / " .. total,
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textGold,
                },
            },
        }
    end

    return UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "center", gap = 4,
        flexWrap = "wrap", paddingVertical = 4,
        children = dots,
    }
end

-- ============================================================================
-- 难度星级
-- ============================================================================
local TRIAL_DIFFICULTY = {
    wanyao  = 2,
    mijing  = 3,
    shengsi = 4,
    xianmo  = 5,
}

local function BuildDifficultyStars(trialId)
    local level = TRIAL_DIFFICULTY[trialId] or 2
    local stars = {}
    for i = 1, 5 do
        stars[#stars + 1] = UI.Label {
            text = i <= level and "*" or "-",
            fontSize = Theme.fontSize.small,
            fontColor = i <= level and Theme.colors.gold or { 80, 70, 55, 120 },
        }
    end
    return UI.Panel { flexDirection = "row", gap = 2, children = stars }
end

-- ============================================================================
-- 试炼卡片（列表用）
-- ============================================================================
local function BuildTrialCard(trial)
    local isLocked = not trial.unlocked

    local typeColors = {
        ["闯关"] = Theme.colors.accent,
        ["限时"] = Theme.colors.warning,
        ["生存"] = Theme.colors.danger,
    }

    local rewardText = ""
    if trial.rewards then
        rewardText = table.concat(trial.rewards, "  ")
    end

    local requirementText = ""
    if trial.unlockTier then
        local DataRealms = require("data_realms")
        local realm = DataRealms.GetRealm(trial.unlockTier)
        requirementText = realm and realm.name or ("境界" .. trial.unlockTier)
    end

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 8, alignItems = "center",
                    children = {
                        UI.Label {
                            text = trial.name,
                            fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                            fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                        },
                        UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 2,
                            borderRadius = Theme.radius.sm,
                            backgroundColor = { 50, 42, 35, 200 },
                            children = {
                                UI.Label {
                                    text = trial.type, fontSize = Theme.fontSize.tiny,
                                    fontColor = typeColors[trial.type] or Theme.colors.textLight,
                                },
                            },
                        },
                    },
                },
                BuildDifficultyStars(trial.id),
            },
        },
        -- 描述
        UI.Label {
            text = trial.desc, fontSize = Theme.fontSize.small,
            fontColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
            width = "100%",
        },
        -- 进度/解锁
        isLocked and UI.Panel {
            width = "100%", flexDirection = "row", gap = 4, alignItems = "center",
            children = {
                UI.Label {
                    text = "解锁条件:", fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = requirementText, fontSize = Theme.fontSize.small,
                    fontWeight = "bold", fontColor = Theme.colors.danger,
                },
            },
        } or UI.Label {
            text = trial.progressText, fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.accent, width = "100%",
        },
        -- 奖励 + 挑战按钮
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            marginTop = 4,
            children = {
                UI.Panel {
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = "奖励: " .. rewardText,
                            fontSize = Theme.fontSize.tiny,
                            fontColor = Theme.colors.goldLight,
                        },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 16, paddingVertical = 6,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = isLocked and { 80, 70, 55, 150 } or Theme.colors.gold,
                    cursor = isLocked and "default" or "pointer",
                    onClick = function(self)
                        if isLocked then
                            Toast.Show("试炼未解锁，需要达到" .. requirementText, { variant = "error" })
                            return
                        end
                        StartChallenge(trial.id)
                    end,
                    children = {
                        UI.Label {
                            text = isLocked and "未解锁" or "挑战",
                            fontSize = Theme.fontSize.body, fontWeight = "bold",
                            fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.btnPrimaryText,
                        },
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 道心试炼卡片（列表用）
-- ============================================================================
local function BuildDaoTrialCard(trial)
    local isLocked = not trial.unlocked
    local noRemain = trial.dailyRemain <= 0

    local typeColors = {
        ["心魔"] = { 180, 80, 80, 255 },
        ["红尘"] = { 120, 160, 80, 255 },
    }

    local requirementText = ""
    if trial.unlockTier then
        local DataRealms = require("data_realms")
        local realm = DataRealms.GetRealm(trial.unlockTier)
        requirementText = realm and realm.name or ("境界" .. trial.unlockTier)
    end

    local rewardDesc = ""
    if trial.type == "心魔" then
        local p = GamePlayer.Get()
        local tier = p and p.tier or 1
        local expected = (trial.baseReward or 3) + (trial.bonusPerTier or 1) * tier
        rewardDesc = "道心+" .. expected .. "（胜）/ 道心+1（败）"
    else
        rewardDesc = "道心+0~3（取决于选择）"
    end

    local btnDisabled = isLocked or noRemain

    return Comp.BuildCardPanel(nil, {
        -- 标题行
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 8, alignItems = "center",
                    children = {
                        UI.Label {
                            text = trial.name,
                            fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                            fontColor = isLocked and Theme.colors.textSecondary or Theme.colors.textGold,
                        },
                        UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 2,
                            borderRadius = Theme.radius.sm,
                            backgroundColor = { 50, 42, 35, 200 },
                            children = {
                                UI.Label {
                                    text = trial.type, fontSize = Theme.fontSize.tiny,
                                    fontColor = typeColors[trial.type] or Theme.colors.textLight,
                                },
                            },
                        },
                    },
                },
                UI.Label {
                    text = trial.dailyRemain .. "/" .. trial.dailyLimit,
                    fontSize = Theme.fontSize.small,
                    fontColor = noRemain and Theme.colors.danger or Theme.colors.accent,
                },
            },
        },
        -- 描述
        UI.Label {
            text = trial.desc, fontSize = Theme.fontSize.small,
            fontColor = isLocked and { 100, 90, 75, 150 } or Theme.colors.textLight,
            width = "100%",
        },
        -- 解锁/奖励信息
        isLocked and UI.Panel {
            width = "100%", flexDirection = "row", gap = 4, alignItems = "center",
            children = {
                UI.Label {
                    text = "解锁条件:", fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textSecondary,
                },
                UI.Label {
                    text = requirementText, fontSize = Theme.fontSize.small,
                    fontWeight = "bold", fontColor = Theme.colors.danger,
                },
            },
        } or UI.Label {
            text = "奖励: " .. rewardDesc, fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.goldLight, width = "100%",
        },
        -- 按钮
        UI.Panel {
            width = "100%", flexDirection = "row",
            justifyContent = "flex-end", marginTop = 4,
            children = {
                UI.Panel {
                    paddingHorizontal = 16, paddingVertical = 6,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = btnDisabled and { 80, 70, 55, 150 } or Theme.colors.gold,
                    cursor = btnDisabled and "default" or "pointer",
                    onClick = function(self)
                        if isLocked then
                            Toast.Show("需要达到" .. requirementText .. "才能解锁", { variant = "error" })
                            return
                        end
                        if noRemain then
                            Toast.Show("今日次数已用尽", { variant = "error" })
                            return
                        end
                        if trial.id == "xinmo" then
                            StartDaoXinmo()
                        elseif trial.id == "hongchen" then
                            StartHongchen()
                        end
                    end,
                    children = {
                        UI.Label {
                            text = isLocked and "未解锁" or (noRemain and "已用尽" or "挑战"),
                            fontSize = Theme.fontSize.body, fontWeight = "bold",
                            fontColor = btnDisabled and Theme.colors.textSecondary or Theme.colors.btnPrimaryText,
                        },
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 红尘历练：场景 UI
-- ============================================================================
local function BuildHongchenScene()
    local scene = state_.hongchenScene
    if not scene then return UI.Panel { width = "100%" } end

    local optionChildren = {}
    for i, opt in ipairs(scene.options) do
        optionChildren[#optionChildren + 1] = UI.Panel {
            width = "100%",
            paddingHorizontal = 12, paddingVertical = 10,
            borderRadius = Theme.radius.md,
            backgroundColor = { 45, 40, 32, 220 },
            borderColor = Theme.colors.borderGold,
            borderWidth = 1,
            cursor = "pointer",
            onClick = function(self)
                SubmitHongchenChoice(i)
            end,
            children = {
                UI.Label {
                    text = opt.text,
                    fontSize = Theme.fontSize.body,
                    fontColor = Theme.colors.textGold,
                },
            },
        }
    end

    local panelChildren = {
        -- 场景描述
        Comp.BuildCardPanel("红尘一景", {
            UI.Label {
                text = scene.desc,
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textLight,
                width = "100%",
            },
        }),
        -- 提示
        UI.Label {
            text = "选择你的做法：",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            width = "100%",
        },
    }
    -- 逐个插入选项（避免 table.unpack 不在末尾导致截断）
    for _, child in ipairs(optionChildren) do
        panelChildren[#panelChildren + 1] = child
    end

    return UI.Panel {
        width = "100%", gap = 10,
        children = panelChildren,
    }
end

-- ============================================================================
-- 红尘历练：结果 UI
-- ============================================================================
local function BuildHongchenResult()
    local data = state_.hongchenResult
    if not data then return UI.Panel { width = "100%" } end

    local gainColor = (data.daoGain or 0) > 0 and Theme.colors.successLight or Theme.colors.textSecondary

    return UI.Panel {
        width = "100%", gap = 10,
        children = {
            -- 场景回顾
            Comp.BuildCardPanel("红尘历练", {
                UI.Label {
                    text = data.sceneDesc or "",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textSecondary,
                    width = "100%",
                },
            }),
            -- 选择与结果
            UI.Panel {
                width = "100%", padding = Theme.spacing.md,
                borderRadius = Theme.radius.md,
                backgroundColor = { 35, 45, 35, 220 },
                borderColor = gainColor,
                borderWidth = 1, gap = 8,
                children = {
                    UI.Label {
                        text = "你的选择: " .. (data.chosenText or ""),
                        fontSize = Theme.fontSize.body, fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Label {
                        text = data.resultMsg or "",
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.textLight,
                    },
                    UI.Label {
                        text = "道心 +" .. (data.daoGain or 0),
                        fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                        fontColor = gainColor,
                        textAlign = "center", width = "100%",
                    },
                    UI.Label {
                        text = "今日剩余次数: " .. (data.remain or 0),
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                        textAlign = "center", width = "100%",
                    },
                },
            },
            -- 返回按钮
            Comp.BuildInkButton("返回试炼列表", function()
                ResetState()
                Router.RebuildUI()
            end),
        },
    }
end

-- ============================================================================
-- 返回行
-- ============================================================================
local function BuildBackRow(backTarget, backLabel)
    return UI.Panel {
        width = "100%", flexDirection = "row",
        alignItems = "center", gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8, paddingVertical = 4,
                cursor = "pointer",
                onClick = function(self)
                    if backTarget == "list" then
                        ResetState()
                        Router.RebuildUI()
                    else
                        Router.EnterState(Router.STATE_HOME)
                    end
                end,
                children = {
                    UI.Label {
                        text = "< " .. (backLabel or "返回"),
                        fontSize = Theme.fontSize.body,
                        fontColor = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = "试炼场",
                fontSize = Theme.fontSize.heading, fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- Build 主函数
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    local s = state_
    local contentChildren = {}

    -- ==================================================================
    -- PHASE_LIST
    -- ==================================================================
    if s.phase == PHASE_LIST then
        contentChildren[#contentChildren + 1] = BuildBackRow("more", "返回")

        -- 普通试炼
        local trials = GameTrial.GetAllTrials()
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle("试炼列表")
        for _, trial in ipairs(trials) do
            contentChildren[#contentChildren + 1] = BuildTrialCard(trial)
        end

        -- 道心试炼
        local daoTrials = GameDaoTrial.GetAllDaoTrials()
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle("道心试炼")
        for _, dt in ipairs(daoTrials) do
            contentChildren[#contentChildren + 1] = BuildDaoTrialCard(dt)
        end

    -- ==================================================================
    -- PHASE_BATTLE
    -- ==================================================================
    elseif s.phase == PHASE_BATTLE then
        local r = s.challengeResult
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "放弃")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
            r and (r.trialName .. " - 战斗中") or "战斗中"
        )
        contentChildren[#contentChildren + 1] = BuildProgressBar()
        -- 跳过按钮放在进度条下方（顶部可见区域），避免因每0.5s重绘导致滚动重置后按钮消失
        contentChildren[#contentChildren + 1] = Comp.BuildSecondaryButton("跳过全部", function()
            SkipAll()
        end)
        contentChildren[#contentChildren + 1] = BuildBattleScene(p)
        contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("战斗记录", {
            (#s.battleLog > 0) and Comp.BuildLogPanel(s.battleLog, { height = 120 })
            or UI.Label {
                text = "战斗即将开始...",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
            },
        })

    -- ==================================================================
    -- PHASE_FIGHT_RESULT
    -- ==================================================================
    elseif s.phase == PHASE_FIGHT_RESULT then
        local r = s.challengeResult
        local fight = CurFight()
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "放弃")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
            r and (r.trialName .. " - " .. FightLabel()) or "战斗结果"
        )
        contentChildren[#contentChildren + 1] = BuildProgressBar()

        -- 本场结果提示（在按钮上方，简洁展示）
        if fight then
            contentChildren[#contentChildren + 1] = UI.Panel {
                width = "100%", padding = 8,
                borderRadius = Theme.radius.md,
                backgroundColor = fight.win and { 30, 50, 30, 200 } or { 50, 25, 25, 200 },
                borderColor = fight.win and Theme.colors.successLight or Theme.colors.dangerLight,
                borderWidth = 1, alignItems = "center",
                children = {
                    UI.Label {
                        text = fight.win and (FightLabel() .. " 通过") or (FightLabel() .. " 失败"),
                        fontSize = Theme.fontSize.body, fontWeight = "bold",
                        fontColor = fight.win and Theme.colors.successLight or Theme.colors.dangerLight,
                    },
                },
            }
        end

        -- 按钮：放在顶部可见区域（进度条下方），无需滚动即可点击
        local hasNext = fight and fight.win and s.fightIdx < #r.fights
        if hasNext then
            contentChildren[#contentChildren + 1] = Comp.BuildInkButton("下一场", function()
                AdvanceOrSettle()
            end)
            contentChildren[#contentChildren + 1] = Comp.BuildSecondaryButton("跳过全部", function()
                SkipAll()
            end)
        else
            contentChildren[#contentChildren + 1] = Comp.BuildInkButton("查看结算", function()
                AdvanceOrSettle()
            end)
        end

        -- 战斗场景置于按钮下方（可选查看，不影响操作）
        contentChildren[#contentChildren + 1] = BuildBattleScene(p)

    -- ==================================================================
    -- PHASE_HONGCHEN（红尘历练：场景选择）
    -- ==================================================================
    elseif s.phase == PHASE_HONGCHEN then
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "返回列表")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle("红尘历练")
        contentChildren[#contentChildren + 1] = BuildHongchenScene()

    -- ==================================================================
    -- PHASE_HONGCHEN_RESULT（红尘历练：结果展示）
    -- ==================================================================
    elseif s.phase == PHASE_HONGCHEN_RESULT then
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "返回列表")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle("红尘历练 - 结果")
        contentChildren[#contentChildren + 1] = BuildHongchenResult()

    -- ==================================================================
    -- PHASE_FINAL
    -- ==================================================================
    elseif s.phase == PHASE_FINAL then
        local r = s.challengeResult
        contentChildren[#contentChildren + 1] = BuildBackRow("list", "返回列表")
        contentChildren[#contentChildren + 1] = Comp.BuildSectionTitle(
            r and (r.trialName .. " - 结算") or "试炼结算"
        )
        contentChildren[#contentChildren + 1] = BuildProgressBar()

        -- 战斗日志
        contentChildren[#contentChildren + 1] = Comp.BuildCardPanel("战斗记录", {
            Comp.BuildLogPanel(s.battleLog, { height = 140 }),
        })

        -- 总结信息
        local finalSuccess = s.isDaoTrial and (r and r.daoWin) or (r and r.cleared and r.cleared > 0)
        contentChildren[#contentChildren + 1] = UI.Panel {
            width = "100%", padding = Theme.spacing.md,
            borderRadius = Theme.radius.md,
            backgroundColor = finalSuccess and { 30, 50, 30, 200 } or { 50, 25, 25, 200 },
            borderColor = finalSuccess and Theme.colors.successLight or Theme.colors.dangerLight,
            borderWidth = 1, alignItems = "center", gap = 6,
            children = {
                Comp.BuildRichLabel(
                    s.settleMsg ~= "" and s.settleMsg or "挑战结束",
                    Theme.fontSize.body,
                    finalSuccess and Theme.colors.successLight or Theme.colors.dangerLight
                ),
                r and UI.Label {
                    text = s.isDaoTrial
                        and ("道心 +" .. (r.daoGain or 0))
                        or ("通过: " .. r.cleared .. " 场  |  灵石: +" .. r.reward),
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.goldLight,
                } or nil,
            },
        }

        contentChildren[#contentChildren + 1] = Comp.BuildInkButton("返回试炼列表", function()
            ResetState()
            Router.RebuildUI()
        end)
    end

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)
end

return M
