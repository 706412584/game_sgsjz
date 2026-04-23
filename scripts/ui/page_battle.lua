------------------------------------------------------------
-- ui/page_battle.lua  —— 三国神将录 全屏可视化战斗回放
-- 全屏战场底图 + absolute 武将卡牌 + 浮动伤害特效
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

-- 状态效果中文映射(用于特效显示)
local STATUS_NAMES = {
    stun = "眩晕", silence = "沉默", burn = "灼烧", armor_break = "破甲",
    charm = "混乱", freeze = "冰冻", shield = "护盾", hot = "回血",
    atk_up = "增攻", def_up = "增防", speed_up = "加速",
}

-- 内部状态
local pagePanel_
local roundLabel_
local battleLog_
local currentRound_  = 0
local roundTimer_    = 0
local actionIndex_   = 0
local statusTickIdx_ = 0
local playing_       = false
local speed_         = 1
local speedBtn_
local onBattleEnd_

-- 所有单位映射 (name -> BattleUnit)
local unitByName_ = {}
local unitById_   = {}

------------------------------------------------------------
-- 查找目标并触发伤害/治疗特效
------------------------------------------------------------
local function showActionEffects(action)
    local targets = action.targets or {}
    local damages = action.damages or {}
    local heals   = action.heals or {}
    local isCrit  = action.isCrit or {}
    local killed  = action.killed or {}

    -- 高亮行动者
    local actorId = action.actorId
    if actorId then
        BField.HighlightUnit(actorId)
    end

    -- 技能名
    if action.type == "skill" and action.name and actorId then
        local aPos = BField.GetUnitPos(actorId)
        if aPos then
            BFX.ShowSkillName(aPos.x, aPos.y - 10, action.name)
        end
    end

    -- 遍历目标
    for i = 1, #targets do
        local tName = targets[i]
        local tUnit = unitByName_[tName]
        if tUnit then
            local tId = tUnit.id
            local pos = BField.GetUnitPos(tId)

            -- 伤害数字
            local dmg = damages[i] or 0
            if dmg > 0 and pos then
                -- 随机偏移避免重叠
                local ox = math.random(-15, 15)
                local oy = math.random(-10, 5)
                BFX.ShowDamage(pos.x + ox, pos.y + oy, dmg, isCrit[i])
            end

            -- 治疗数字
            local heal = heals[i] or 0
            if heal > 0 and pos then
                BFX.ShowHeal(pos.x, pos.y - 10, heal)
            end

            -- 击杀
            if killed[i] and pos then
                BFX.ShowKill(pos.x, pos.y + 20, tName)
            end

            -- 更新单位状态
            BField.UpdateUnit(tId, tUnit.hp, tUnit.maxHp, tUnit.morale, tUnit.statuses, tUnit.alive)
        end
    end

    -- 状态效果文字
    if action.statuses then
        for _, st in ipairs(action.statuses) do
            local sUnit = unitByName_[st.target]
            if sUnit then
                local pos = BField.GetUnitPos(sUnit.id)
                if pos then
                    local sName = STATUS_NAMES[st.status] or st.status
                    BFX.ShowStatus(pos.x, pos.y + 15, sName)
                end
            end
        end
    end
end

------------------------------------------------------------
-- 处理 statusTick (灼烧/回血)
------------------------------------------------------------
local function showStatusTick(tick)
    local tName = tick.target
    local tUnit = unitByName_[tName]
    if not tUnit then return end

    local tId = tUnit.id
    local pos = BField.GetUnitPos(tId)

    if tick.type == "burn_tick" and pos then
        BFX.ShowDamage(pos.x, pos.y, tick.damage or 0, false)
    elseif tick.type == "hot_tick" and pos then
        BFX.ShowHeal(pos.x, pos.y, tick.heal or 0)
    end

    BField.UpdateUnit(tId, tUnit.hp, tUnit.maxHp, tUnit.morale, tUnit.statuses, tUnit.alive)
end

------------------------------------------------------------
-- 更新所有单位视觉状态(回合开始时同步)
------------------------------------------------------------
local function syncAllUnits()
    for _, u in pairs(unitById_) do
        BField.UpdateUnit(u.id, u.hp, u.maxHp, u.morale, u.statuses, u.alive)
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

    print("[Battle] Create: #rounds=" .. #(log.rounds or {})
        .. " #allies=" .. #(log.allies or {})
        .. " #enemies=" .. #(log.enemies or {})
        .. " playing=" .. tostring(playing_))

    -- 建立名字/ID映射
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

    -- 自订阅 Update
    SubscribeToEvent("Update", "HandleBattleFrameUpdate")

    -- 屏幕尺寸
    local dpr = graphics:GetDPR()
    local screenW = graphics:GetWidth() / dpr
    local screenH = graphics:GetHeight() / dpr
    local panelH = screenH - S.hudHeight

    -- 速度按钮
    speedBtn_ = Comp.SanButton({
        text     = "x1",
        variant  = "secondary",
        height   = 30,
        fontSize = 11,
        paddingHorizontal = 10,
        onClick  = function()
            speed_ = speed_ >= 3 and 1 or speed_ + 1
            if speedBtn_ then speedBtn_.text = "x" .. speed_ end
        end,
    })

    -- 回合标签
    roundLabel_ = UI.Label {
        text      = "准备战斗...",
        fontSize  = Theme.fontSize.subtitle,
        fontColor = C.gold,
        fontWeight = "bold",
    }

    -- 顶栏 (absolute, 半透明)
    local topBar = UI.Panel {
        position        = "absolute",
        top             = 0,
        left            = 0,
        width           = "100%",
        height          = 36,
        flexDirection   = "row",
        alignItems      = "center",
        justifyContent  = "space-between",
        paddingHorizontal = 12,
        backgroundColor = { 0, 0, 0, 160 },
        zIndex          = 10,
        children = {
            roundLabel_,
            speedBtn_,
        },
    }

    -- 特效容器
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

    -- 战场容器 (背景图 + 卡牌)
    local fieldContainer = UI.Panel {
        width           = "100%",
        height          = "100%",
        backgroundImage = "Textures/backgrounds/bg_battlefield.png",
        backgroundFit   = "cover",
    }

    -- 布局武将卡牌
    BField.Create(fieldContainer, log.allies or {}, log.enemies or {}, screenW, panelH)

    -- 特效容器加到战场上层
    fieldContainer:AddChild(fxContainer)

    -- 主面板
    pagePanel_ = UI.Panel {
        width           = "100%",
        flexGrow        = 1,
        flexBasis       = 0,
        backgroundColor = { 10, 10, 15, 255 },
        children = {
            fieldContainer,
            topBar,
        },
    }

    return pagePanel_
end

--- 战斗帧更新
function M.Update(dt)
    if not playing_ or not battleLog_ then return end

    -- 更新特效
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
        actionIndex_ = 0
        statusTickIdx_ = 0

        if currentRound_ > #rounds then
            -- 战斗结束
            playing_ = false
            if roundLabel_ then
                roundLabel_.text = "战斗结束"
            end

            if battleLog_.result then
                Modal.BattleResult(battleLog_.result, onBattleEnd_)
            end
            return
        end

        if roundLabel_ then
            roundLabel_.text = "第 " .. currentRound_ .. " / " .. #rounds .. " 回合"
        end

        -- 同步一次所有单位状态
        syncAllUnits()
    end

    local round = rounds[currentRound_]
    local actions = round.actions or {}
    local statusTicks = round.statusTicks or {}

    -- 播放 actions
    if actionIndex_ < #actions then
        actionIndex_ = actionIndex_ + 1
        local action = actions[actionIndex_]
        if action then
            showActionEffects(action)
        end
    elseif statusTickIdx_ < #statusTicks then
        statusTickIdx_ = statusTickIdx_ + 1
        local tick = statusTicks[statusTickIdx_]
        if tick then
            showStatusTick(tick)
        end
    end
end

--- 是否正在播放
function M.IsPlaying()
    return playing_
end

--- 停止战斗
function M.Stop()
    playing_ = false
    BFX.Clear()
    BField.Clear()
end

--- 获取页面面板
function M.GetPanel()
    return pagePanel_
end

------------------------------------------------------------
-- 自订阅 Update
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
