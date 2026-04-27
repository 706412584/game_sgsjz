------------------------------------------------------------
-- ui/page_battle.lua  —— 三国神将录 全屏可视化战斗回放
-- 风云天下风格: 顶栏双方指挥官信息 + 战场卡牌 + 底部结果/加速
-- 使用 unitState_ 影子状态跟踪中间 HP，避免一开始就显示最终结果
------------------------------------------------------------
local UI     = require("urhox-libs/UI")
local Theme  = require("ui.theme")
local Comp   = require("ui.components")
local Modal  = require("ui.modal_manager")
local BField = require("ui.battle_field")
local BFX    = require("ui.battle_effects")
local DT     = require("data.data_troops")
local BAudio = require("ui.battle_audio")
local C      = Theme.colors
local S      = Theme.sizes

local M = {}

local STATUS_NAMES = {
    stun = "眩晕", silence = "沉默", burn = "灼烧", armor_break = "破甲",
    charm = "混乱", freeze = "冰冻", shield = "护盾", hot = "回血",
    atk_up = "增攻", def_up = "增防", speed_up = "加速",
}

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------
local pagePanel_
local roundLabel_
local battleLog_
local currentRound_   = 0
local roundTimer_     = 0
local actionIndex_    = 0
local statusTickIdx_  = 0
local playing_        = false
local speed_          = 1
local speedBtn_
local onBattleEnd_
local unitByName_ = {}
local unitById_   = {}

-- 影子状态: 跟踪回放过程中的中间 HP / alive / statuses
-- 初始值 = 满血满活, 随 action 逐步扣减
local unitState_ = {}  -- { [id] = { hp, maxHp, morale, alive, statuses } }

-- 顶栏兵力条
local allyHpBar_, enemyHpBar_
local allyTotalMaxHp_, enemyTotalMaxHp_

------------------------------------------------------------
-- 顶栏兵力条 — 根据影子状态实时聚合
------------------------------------------------------------
local function updateTopBarHp()
    if not allyHpBar_ or not enemyHpBar_ then return end
    local allyHp, enemyHp = 0, 0
    for _, u in ipairs(battleLog_.allies or {}) do
        local st = unitState_[u.id]
        if st and st.alive then
            allyHp = allyHp + math.max(0, st.hp)
        end
    end
    for _, u in ipairs(battleLog_.enemies or {}) do
        local st = unitState_[u.id]
        if st and st.alive then
            enemyHp = enemyHp + math.max(0, st.hp)
        end
    end
    allyHpBar_:SetValue(allyTotalMaxHp_ > 0 and (allyHp / allyTotalMaxHp_) or 0)
    enemyHpBar_:SetValue(enemyTotalMaxHp_ > 0 and (enemyHp / enemyTotalMaxHp_) or 0)
end

------------------------------------------------------------
-- 同步所有单位 UI (用影子状态)
------------------------------------------------------------
local function syncAllUnits()
    for id, st in pairs(unitState_) do
        BField.UpdateUnit(id, st.hp, st.maxHp, st.morale, st.statuses, st.alive)
    end
end

------------------------------------------------------------
-- 特效触发 (伤害/治疗/击杀/技能/状态)
------------------------------------------------------------
local function showActionEffects(action)
    local targets = action.targets or {}
    local damages = action.damages or {}
    local heals   = action.heals or {}
    local isCrit  = action.isCrit or {}
    local killed  = action.killed or {}

    -- 播放音效
    BAudio.PlayActionSound(action, unitById_)

    local actorId = action.actorId
    if actorId then BField.HighlightUnit(actorId) end

    -- 更新攻击者的士气
    if actorId and action.actorMorale then
        local ast = unitState_[actorId]
        if ast then
            ast.morale = action.actorMorale
            BField.UpdateUnit(actorId, ast.hp, ast.maxHp,
                ast.morale, ast.statuses, ast.alive)
        end
    end

    if action.type == "skill" and action.name and actorId then
        local aPos = BField.GetUnitPos(actorId)
        if aPos then BFX.ShowSkillName(aPos.x, aPos.y - 10, action.name) end
        BField.ShowSkillTitle(actorId, action.name)
    end

    -- 反击提示
    if action.type == "counter" and actorId then
        local aPos = BField.GetUnitPos(actorId)
        if aPos then BFX.ShowExtra(aPos.x, aPos.y, "counter", nil) end
    end

    local targetMorales = action.targetMorales or {}

    -- 跟踪暴击: 汇总后在攻击方位置显示横幅
    local hasCrit = false
    local critTotalDmg = 0

    for i = 1, #targets do
        local tName = targets[i]
        local tUnit = unitByName_[tName]
        if tUnit then
            local tId = tUnit.id
            local st  = unitState_[tId]
            local pos = BField.GetUnitPos(tId)

            -- 扣血
            local dmg = damages[i] or 0
            if dmg > 0 then
                if pos then
                    -- 命中特效 (根据攻击者兵种显示元素/物理命中)
                    local actorUnit = actorId and unitById_[actorId]
                    if actorUnit then
                        BFX.ShowHitEffect(pos.x, pos.y,
                            actorUnit.troopKey, actorUnit.troopCat)
                    end
                    local ox = math.random(-15, 15)
                    local oy = math.random(-10, 5)
                    BFX.ShowDamage(pos.x + ox, pos.y + oy, dmg, isCrit[i])
                end
                if st then st.hp = math.max(0, st.hp - dmg) end
                -- 汇总暴击伤害
                if isCrit[i] then
                    hasCrit = true
                    critTotalDmg = critTotalDmg + dmg
                end
            end

            -- 治疗
            local heal = heals[i] or 0
            if heal > 0 then
                if pos then BFX.ShowHeal(pos.x, pos.y - 10, heal) end
                if st then st.hp = math.min(st.maxHp, st.hp + heal) end
            end

            -- 击杀
            if killed[i] then
                if pos then BFX.ShowKill(pos.x, pos.y + 20, tName) end
                if st then st.alive = false; st.hp = 0 end
            elseif st and st.hp <= 0 and st.alive then
                -- 兜底: killed 数组缺失时按 hp 判定死亡
                st.alive = false; st.hp = 0
            end

            -- 同步目标士气
            if st and targetMorales[i] then
                st.morale = targetMorales[i]
            end

            -- 更新卡牌 UI (用影子状态)
            if st then
                BField.UpdateUnit(tId, st.hp, st.maxHp,
                    st.morale, st.statuses, st.alive)
            end
        end
    end

    -- 暴击横幅: 在攻击方位置直接显示（不暂停）
    if hasCrit and actorId then
        local aPos = BField.GetUnitPos(actorId)
        if aPos then
            BFX.ShowCritBanner(aPos.x, aPos.y, critTotalDmg, 0)
        end
    end

    -- 状态效果
    if action.statuses then
        for _, stInfo in ipairs(action.statuses) do
            local sUnit = unitByName_[stInfo.target]
            if sUnit then
                local pos = BField.GetUnitPos(sUnit.id)
                if pos then
                    BFX.ShowStatus(pos.x, pos.y + 15,
                        STATUS_NAMES[stInfo.status] or stInfo.status)
                end
                local st = unitState_[sUnit.id]
                if st then
                    st.statuses[stInfo.status] = { dur = stInfo.dur or 1 }
                end
            end
        end
    end

    -- extras 音效（增怒/减怒等辅助效果）
    BAudio.PlayExtrasSound(action.extras)

    -- extras 特殊机制视觉反馈 (闪避/斩杀/免死/吸血/追击/增怒/减怒/降智/免控)
    if action.extras then
        local troopShownFor = {}  -- 每个单位只显示一次兵种名
        local TROOP_EXTRAS = {
            dodge = true, execute = true, death_immune = true,
            lifesteal = true, pursuit = true, immune_control = true,
        }
        for _, ex in ipairs(action.extras) do
            local exType = ex.type
            -- 确定显示位置：有 target 的显示在目标上，否则显示在攻击者上
            local showUnit = nil
            if ex.target then
                showUnit = unitByName_[ex.target]
            end
            if not showUnit then
                -- 无目标的机制（吸血/免控/增怒/减怒/降智）显示在攻击者上
                showUnit = actorId and unitById_[actorId] or nil
            end
            if showUnit then
                -- 兵种特性触发: 头顶显示兵种名（每单位仅一次）
                if TROOP_EXTRAS[exType] and not troopShownFor[showUnit.id] then
                    local tpName = DT.GetHeroTroopName(showUnit.heroId)
                    if tpName then
                        BField.ShowSkillTitle(showUnit.id, tpName, {120,255,220,255})
                        troopShownFor[showUnit.id] = true
                    end
                end

                local pos = BField.GetUnitPos(showUnit.id)
                if pos then
                    BFX.ShowExtra(pos.x, pos.y, exType, ex)
                end
            end
        end
    end

    -- 全量士气同步：刷新所有受全局士气变化影响的单位黄条
    if action.allMorales then
        for uName, uMorale in pairs(action.allMorales) do
            local u = unitByName_[uName]
            if u then
                local st = unitState_[u.id]
                if st and st.alive then
                    st.morale = uMorale
                    BField.UpdateUnit(u.id, st.hp, st.maxHp,
                        st.morale, st.statuses, st.alive)
                end
            end
        end
    end

    -- 战法释放: 给攻击者卡牌金色闪烁
    if action.type == "skill" and actorId then
        BField.FlashSkillGlow(actorId)
    end

    updateTopBarHp()
end

local function showStatusTick(tick)
    local tUnit = unitByName_[tick.target]
    if not tUnit then return end
    local tId = tUnit.id
    local st  = unitState_[tId]
    local pos = BField.GetUnitPos(tId)

    if tick.type == "burn_tick" and pos then
        BFX.ShowDamage(pos.x, pos.y, tick.damage or 0, false)
        if st then
            st.hp = math.max(0, st.hp - (tick.damage or 0))
            if st.hp <= 0 then st.alive = false end
        end
    elseif tick.type == "hot_tick" and pos then
        BFX.ShowHeal(pos.x, pos.y, tick.heal or 0)
        if st then
            st.hp = math.min(st.maxHp, st.hp + (tick.heal or 0))
        end
    end

    if st then
        BField.UpdateUnit(tId, st.hp, st.maxHp,
            st.morale, st.statuses, st.alive)
    end
    updateTopBarHp()
end

------------------------------------------------------------
-- 跳过战斗直接出结果
------------------------------------------------------------
local function skipToEnd()
    if not battleLog_ then return end
    playing_ = false

    -- 将影子状态设为最终状态
    for _, u in ipairs(battleLog_.allies or {}) do
        local st = unitState_[u.id]
        if st then
            st.hp = u.hp; st.alive = u.alive
            st.morale = u.morale or 0; st.statuses = u.statuses or {}
        end
    end
    for _, u in ipairs(battleLog_.enemies or {}) do
        local st = unitState_[u.id]
        if st then
            st.hp = u.hp; st.alive = u.alive
            st.morale = u.morale or 0; st.statuses = u.statuses or {}
        end
    end

    syncAllUnits()
    updateTopBarHp()
    if roundLabel_ then roundLabel_.text = "战斗结束" end
    if battleLog_.result then
        Modal.BattleResult(battleLog_.result, onBattleEnd_)
    end
end

------------------------------------------------------------
-- 构建顶栏一侧指挥官面板 (头像 + 名字LV + 兵力条)
------------------------------------------------------------
local function createCmdPanel(heroId, name, level, side, hpBar)
    local isAlly = (side == "ally")
    local borderClr = isAlly and C.jade or C.red
    local imgPath = heroId
        and ("Textures/heroes/hero_" .. heroId .. ".png") or nil

    local avatar = UI.Panel {
        width           = 44,
        height          = 44,
        borderRadius    = 6,
        borderColor     = borderClr,
        borderWidth     = 2,
        backgroundImage = imgPath,
        backgroundFit   = "cover",
        backgroundColor = isAlly and { 30, 55, 45, 255 } or { 55, 30, 30, 255 },
    }

    local nameLabel = UI.Label {
        text      = (name or "???") .. " LV:" .. (level or 1),
        fontSize  = 11,
        fontColor = C.text,
        fontWeight = "bold",
        maxLines  = 1,
    }

    local infoStack = UI.Panel {
        flexDirection  = "column",
        justifyContent = "center",
        alignItems     = isAlly and "flex-start" or "flex-end",
        gap            = 3,
        children       = { nameLabel, hpBar },
    }

    if isAlly then
        return UI.Panel {
            flexDirection = "row",
            alignItems    = "center",
            gap           = 6,
            children      = { avatar, infoStack },
        }
    else
        return UI.Panel {
            flexDirection = "row",
            alignItems    = "center",
            gap           = 6,
            children      = { infoStack, avatar },
        }
    end
end

------------------------------------------------------------
-- 公开 API
------------------------------------------------------------

--- 创建战斗页面
---@param log table battleLog from battle_engine / server
---@param callbacks table { onBattleEnd = function() }
function M.Create(log, callbacks)
    callbacks      = callbacks or {}
    onBattleEnd_   = callbacks.onBattleEnd
    battleLog_     = log
    currentRound_  = 0
    actionIndex_   = 0
    statusTickIdx_ = 0
    roundTimer_    = 0
    playing_       = true
    speed_         = 1
    print("[Battle] Create: #rounds=" .. #(log.rounds or {})
        .. " #allies=" .. #(log.allies or {})
        .. " #enemies=" .. #(log.enemies or {}))

    -- 单位映射
    unitByName_ = {}
    unitById_   = {}
    for _, u in ipairs(log.allies or {}) do
        unitByName_[u.name] = u
        unitById_[u.id] = u
    end
    for _, u in ipairs(log.enemies or {}) do
        unitByName_[u.name] = u
        unitById_[u.id] = u
    end

    -- 影子状态: 全员满血开始
    unitState_ = {}
    allyTotalMaxHp_  = 0
    enemyTotalMaxHp_ = 0
    for _, u in ipairs(log.allies or {}) do
        unitState_[u.id] = {
            hp       = u.maxHp,
            maxHp    = u.maxHp,
            morale   = 0,
            alive    = true,
            statuses = {},
        }
        allyTotalMaxHp_ = allyTotalMaxHp_ + (u.maxHp or 0)
    end
    for _, u in ipairs(log.enemies or {}) do
        unitState_[u.id] = {
            hp       = u.maxHp,
            maxHp    = u.maxHp,
            morale   = 0,
            alive    = true,
            statuses = {},
        }
        enemyTotalMaxHp_ = enemyTotalMaxHp_ + (u.maxHp or 0)
    end

    -- 初始化战斗音效
    BAudio.Init()

    -- 自订阅 Update
    SubscribeToEvent("Update", "HandleBattleFrameUpdate")

    -- 屏幕尺寸
    local dpr     = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local panelH  = screenH - S.hudHeight

    -- ====== 顶栏: 左玩家 + 中回合 + 右敌方 ======
    local allyCmd  = (log.allies or {})[1]
    local enemyCmd = (log.enemies or {})[1]

    allyHpBar_ = UI.ProgressBar {
        value           = 1.0,
        width           = 110,
        height          = 8,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 4,
        fillColor       = C.hp,
        transition      = "value 0.5s easeOut",
    }
    enemyHpBar_ = UI.ProgressBar {
        value           = 1.0,
        width           = 110,
        height          = 8,
        backgroundColor = { 20, 20, 20, 200 },
        borderRadius    = 4,
        fillColor       = C.red,
        transition      = "value 0.5s easeOut",
    }

    local allyPanel = createCmdPanel(
        allyCmd and allyCmd.heroId, "玩家",
        allyCmd and allyCmd.level, "ally", allyHpBar_)
    local enemyPanel = createCmdPanel(
        enemyCmd and enemyCmd.heroId, "敌军",
        enemyCmd and enemyCmd.level, "enemy", enemyHpBar_)

    roundLabel_ = UI.Label {
        text       = "准备战斗...",
        fontSize   = 16,
        fontColor  = C.gold,
        fontWeight = "bold",
    }

    local topBar = UI.Panel {
        position  = "absolute",
        top       = 0,
        left      = 0,
        width     = "100%",
        zIndex    = 10,
        flexDirection = "column",
        children  = {
            -- 信息行
            UI.Panel {
                height             = 52,
                width              = "100%",
                flexDirection      = "row",
                alignItems         = "center",
                justifyContent     = "space-between",
                paddingHorizontal  = 10,
                paddingVertical    = 4,
                backgroundColor    = { 15, 12, 8, 220 },
                children           = { allyPanel, roundLabel_, enemyPanel },
            },
            -- 金色装饰线
            UI.Panel {
                width           = "100%",
                height          = 2,
                backgroundColor = C.gold,
            },
        },
    }

    -- ====== 底部: 结果按钮(居中) + 加速按钮(右下) ======
    speedBtn_ = Comp.SanButton {
        text              = "x1",
        variant           = "gold",
        height            = 32,
        fontSize          = 12,
        paddingHorizontal = 14,
        onClick           = function()
            speed_ = speed_ >= 3 and 1 or speed_ + 1
            if speedBtn_ then speedBtn_.text = "x" .. speed_ end
        end,
    }

    local resultBtnWidget = Comp.SanButton {
        text              = "结果",
        variant           = "gold",
        height            = 38,
        fontSize          = 14,
        paddingHorizontal = 28,
        width             = 120,
        onClick           = function() skipToEnd() end,
    }

    local bottomBar = UI.Panel {
        position       = "absolute",
        bottom         = 12,
        left           = 0,
        width          = "100%",
        height         = 50,
        flexDirection  = "row",
        justifyContent = "center",
        alignItems     = "center",
        pointerEvents  = "box-none",
        zIndex         = 10,
        children       = { resultBtnWidget },
    }

    local speedContainer = UI.Panel {
        position = "absolute",
        bottom   = 14,
        right    = 12,
        zIndex   = 10,
        children = { speedBtn_ },
    }

    -- ====== 战场区域 ======
    local fxContainer = UI.Panel {
        position      = "absolute",
        top           = 0,
        left          = 0,
        width         = "100%",
        height        = "100%",
        pointerEvents = "none",
        zIndex        = 5,
    }
    BFX.Init(fxContainer)

    local fieldContainer = UI.Panel {
        width           = "100%",
        height          = "100%",
        backgroundImage = "Textures/backgrounds/bg_battlefield.png",
        backgroundFit   = "cover",
    }
    BField.Create(fieldContainer, log.allies or {}, log.enemies or {},
        screenW, panelH)
    fieldContainer:AddChild(fxContainer)

    -- ====== 主面板 ======
    pagePanel_ = UI.Panel {
        width           = "100%",
        flexGrow        = 1,
        flexBasis       = 0,
        backgroundColor = { 10, 10, 15, 255 },
        children        = {
            fieldContainer,
            topBar,
            bottomBar,
            speedContainer,
        },
    }

    return pagePanel_
end

------------------------------------------------------------
-- 帧更新
------------------------------------------------------------
function M.Update(dt)
    if not playing_ or not battleLog_ then return end
    BFX.Update(dt)
    BField.TickTimers(dt)

    roundTimer_ = roundTimer_ + dt * speed_
    if roundTimer_ < 1.0 then return end
    roundTimer_ = 0

    local rounds = battleLog_.rounds or {}

    -- 推进回合
    if currentRound_ == 0
       or (actionIndex_ >= #(rounds[currentRound_].actions or {})
           and statusTickIdx_ >= #(rounds[currentRound_].statusTicks or {})) then
        currentRound_ = currentRound_ + 1
        actionIndex_  = 0
        statusTickIdx_ = 0

        if currentRound_ > #rounds then
            playing_ = false
            if roundLabel_ then roundLabel_.text = "战斗结束" end
            -- 设为最终状态
            for _, u in ipairs(battleLog_.allies or {}) do
                local st = unitState_[u.id]
                if st then st.hp = u.hp; st.alive = u.alive end
            end
            for _, u in ipairs(battleLog_.enemies or {}) do
                local st = unitState_[u.id]
                if st then st.hp = u.hp; st.alive = u.alive end
            end
            syncAllUnits()
            updateTopBarHp()
            if battleLog_.result then
                Modal.BattleResult(battleLog_.result, onBattleEnd_)
            end
            return
        end

        if roundLabel_ then
            roundLabel_.text = "第 " .. currentRound_ .. " / " .. #rounds .. " 回合"
        end
    end

    local round = rounds[currentRound_]
    local actions     = round.actions or {}
    local statusTicks = round.statusTicks or {}

    if actionIndex_ < #actions then
        actionIndex_ = actionIndex_ + 1
        local action = actions[actionIndex_]
        if action then showActionEffects(action) end
    elseif statusTickIdx_ < #statusTicks then
        statusTickIdx_ = statusTickIdx_ + 1
        local tick = statusTicks[statusTickIdx_]
        if tick then showStatusTick(tick) end
    end
end

function M.IsPlaying()
    return playing_
end

function M.Stop()
    playing_ = false
    BFX.Clear()
    BField.Clear()
    BAudio.Clear()
end

function M.GetPanel()
    return pagePanel_
end

------------------------------------------------------------
-- 自订阅 Update 事件
------------------------------------------------------------
function HandleBattleFrameUpdate(eventType, eventData)
    if not playing_ then return end
    local ok, err = pcall(function()
        local dt = eventData["TimeStep"]:GetFloat()
        M.Update(dt)
    end)
    if not ok then
        print("[Battle] 帧更新出错: " .. tostring(err))
        playing_ = false
    end
end

return M
