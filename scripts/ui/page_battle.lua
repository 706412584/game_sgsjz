------------------------------------------------------------
-- ui/page_battle.lua  —— 三国神将录 全屏可视化战斗回放
-- 风云天下风格: 顶栏双方指挥官信息 + 战场卡牌 + 底部结果/加速
------------------------------------------------------------
local UI     = require("urhox-libs/UI")
local Theme  = require("ui.theme")
local Comp   = require("ui.components")
local Modal  = require("ui.modal_manager")
local BField = require("ui.battle_field")
local BFX    = require("ui.battle_effects")
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

-- 顶栏兵力条
local allyHpBar_, enemyHpBar_
local allyTotalMaxHp_, enemyTotalMaxHp_
local allyFinalRatio_, enemyFinalRatio_
local totalRounds_

------------------------------------------------------------
-- 顶栏兵力条 — 按回合进度线性插值
------------------------------------------------------------
local function updateTopBarHp()
    if not allyHpBar_ or not enemyHpBar_ then return end
    if totalRounds_ <= 0 then return end
    local progress = math.min(1, currentRound_ / totalRounds_)
    allyHpBar_:SetValue(math.max(0, 1.0 - (1.0 - allyFinalRatio_) * progress))
    enemyHpBar_:SetValue(math.max(0, 1.0 - (1.0 - enemyFinalRatio_) * progress))
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

    local actorId = action.actorId
    if actorId then BField.HighlightUnit(actorId) end

    if action.type == "skill" and action.name and actorId then
        local aPos = BField.GetUnitPos(actorId)
        if aPos then BFX.ShowSkillName(aPos.x, aPos.y - 10, action.name) end
    end

    for i = 1, #targets do
        local tName = targets[i]
        local tUnit = unitByName_[tName]
        if tUnit then
            local tId = tUnit.id
            local pos = BField.GetUnitPos(tId)
            local dmg = damages[i] or 0
            if dmg > 0 and pos then
                local ox = math.random(-15, 15)
                local oy = math.random(-10, 5)
                BFX.ShowDamage(pos.x + ox, pos.y + oy, dmg, isCrit[i])
            end
            local heal = heals[i] or 0
            if heal > 0 and pos then
                BFX.ShowHeal(pos.x, pos.y - 10, heal)
            end
            if killed[i] and pos then
                BFX.ShowKill(pos.x, pos.y + 20, tName)
            end
            BField.UpdateUnit(tId, tUnit.hp, tUnit.maxHp,
                tUnit.morale, tUnit.statuses, tUnit.alive)
        end
    end

    if action.statuses then
        for _, st in ipairs(action.statuses) do
            local sUnit = unitByName_[st.target]
            if sUnit then
                local pos = BField.GetUnitPos(sUnit.id)
                if pos then
                    BFX.ShowStatus(pos.x, pos.y + 15,
                        STATUS_NAMES[st.status] or st.status)
                end
            end
        end
    end
end

local function showStatusTick(tick)
    local tUnit = unitByName_[tick.target]
    if not tUnit then return end
    local pos = BField.GetUnitPos(tUnit.id)
    if tick.type == "burn_tick" and pos then
        BFX.ShowDamage(pos.x, pos.y, tick.damage or 0, false)
    elseif tick.type == "hot_tick" and pos then
        BFX.ShowHeal(pos.x, pos.y, tick.heal or 0)
    end
    BField.UpdateUnit(tUnit.id, tUnit.hp, tUnit.maxHp,
        tUnit.morale, tUnit.statuses, tUnit.alive)
end

local function syncAllUnits()
    for _, u in pairs(unitById_) do
        BField.UpdateUnit(u.id, u.hp, u.maxHp, u.morale, u.statuses, u.alive)
    end
end

------------------------------------------------------------
-- 跳过战斗直接出结果
------------------------------------------------------------
local function skipToEnd()
    if not battleLog_ then return end
    playing_ = false
    syncAllUnits()
    if allyHpBar_ then allyHpBar_:SetValue(allyFinalRatio_) end
    if enemyHpBar_ then enemyHpBar_:SetValue(enemyFinalRatio_) end
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

    -- 兵力统计 (用于顶栏 HP 条插值)
    allyTotalMaxHp_  = 0
    enemyTotalMaxHp_ = 0
    local allyFinalHp, enemyFinalHp = 0, 0
    for _, u in ipairs(log.allies or {}) do
        allyTotalMaxHp_ = allyTotalMaxHp_ + (u.maxHp or 0)
        if u.alive then allyFinalHp = allyFinalHp + math.max(0, u.hp or 0) end
    end
    for _, u in ipairs(log.enemies or {}) do
        enemyTotalMaxHp_ = enemyTotalMaxHp_ + (u.maxHp or 0)
        if u.alive then enemyFinalHp = enemyFinalHp + math.max(0, u.hp or 0) end
    end
    allyFinalRatio_  = allyTotalMaxHp_  > 0
        and (allyFinalHp / allyTotalMaxHp_) or 0
    enemyFinalRatio_ = enemyTotalMaxHp_ > 0
        and (enemyFinalHp / enemyTotalMaxHp_) or 0
    totalRounds_ = log.totalRounds or #(log.rounds or {})

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

    roundTimer_ = roundTimer_ + dt * speed_
    if roundTimer_ < 0.6 then return end
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
            if allyHpBar_ then allyHpBar_:SetValue(allyFinalRatio_) end
            if enemyHpBar_ then enemyHpBar_:SetValue(enemyFinalRatio_) end
            if battleLog_.result then
                Modal.BattleResult(battleLog_.result, onBattleEnd_)
            end
            return
        end

        if roundLabel_ then
            roundLabel_.text = "第 " .. currentRound_ .. " / " .. #rounds .. " 回合"
        end
        syncAllUnits()
        updateTopBarHp()
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
