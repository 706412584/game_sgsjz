-- ============================================================================
-- 《问道长生》历练页 —— AFK 挂机优先 + 逐回合战斗动画
-- 状态机：seeking -> battle -> result -> (自动循环)
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameExplore = require("game_explore")
local DataItems = require("data_items")
local DataWorld = require("data_world")
local Toast = require("ui_toast")
local NVG = require("nvg_manager")

local M = {}

-- 当前页面的区域和难度（由 payload 传入）
local currentAreaId_ = "yunwu"
local currentDifficulty_ = "normal"

-- ============================================================================
-- 页面内状态机
-- ============================================================================
local PHASE_SEEKING = "seeking"   -- 寻敌中（AFK 自动循环）
local PHASE_BATTLE  = "battle"    -- 战斗回合播放中
local PHASE_RESULT  = "result"    -- 战斗结束，展示结果（自动继续）

local battleState_ = {
    phase      = PHASE_SEEKING,
    encounter  = nil,
    monsterImg = nil,
    rounds     = {},
    roundIdx   = 0,
    win        = false,
    summary    = "",
    timer      = 0,
    battleLog  = {},
    settled    = false,
    resultMsg  = "",
    equipDrop  = nil,   -- 掉落装备数据 { name, quality, slot, ... }
}

local ROUND_INTERVAL    = 0.6  -- 回合播放间隔
local RESULT_AUTO_DELAY = 1.5  -- 结果展示后自动继续延迟
local RESULT_EQUIP_DELAY = 3.0 -- 有装备掉落时延长展示时间
local battleUpdateKey_  = "explore_battle"
local resultTimerKey_   = "explore_result_timer"
local STATS_REFRESH_KEY = "explore_stats_refresh"
local pageActive_       = false  -- 页面是否激活

-- ============================================================================
-- 战斗动画系统（飘字 + 闪光 + 音效）
-- ============================================================================
local ANIM_KEY      = "explore_anim"
local animState_    = { floats = {}, flashes = {}, shakes = {} }
local playerShakeX_   = 0      -- 头像抖动水平偏移（由 OnAnimUpdate 驱动）
local shakeWasActive_ = false  -- 上帧是否在抖动（用于尾帧重置）
local animFontLoaded_ = false
local audioScene_   = nil  ---@type Scene
local audioPool_    = {}

--- 初始化 NVG 动画字体（只执行一次，由 OnAnimDraw 传入 ctx）
local function EnsureAnimFont(ctx)
    if animFontLoaded_ then return end
    animFontLoaded_ = true
    if ctx then
        nvgCreateFont(ctx, "sans", "Fonts/MiSans-Regular.ttf")
    end
end

--- 播放战斗音效（异步，不阻塞逻辑）
local function PlayBattleSound(filename)
    if not pageActive_ then return end
    local sound = cache:GetResource("Sound", filename)
    if not sound then return end
    -- 懒建音频场景
    if not audioScene_ then
        audioScene_ = Scene()
    end
    -- 从池中找空闲 SoundSource
    local src = nil
    for _, s in ipairs(audioPool_) do
        if not s:IsPlaying() then src = s; break end
    end
    if not src and #audioPool_ < 4 then
        local n = audioScene_:CreateChild("SndNode")
        src = n:CreateComponent("SoundSource")
        audioPool_[#audioPool_ + 1] = src
    end
    if not src then src = audioPool_[1] end
    if src then
        src.gain = 0.65
        src:Play(sound)
    end
end

--- 触发命中敌方动画（普通攻击 / 暴击）
local function TriggerHitAnim(damage, isCrit)
    if not pageActive_ then return end
    local logW = graphics:GetWidth()  / graphics:GetDPR()
    local logH = graphics:GetHeight() / graphics:GetDPR()
    local ex   = logW * 0.78
    local ey   = logH * 0.23   -- 对准头像圆心

    -- 飘字
    local txt   = isCrit and ("暴击!" .. tostring(damage)) or tostring(damage)
    local color = isCrit and { 255, 200, 60, 255 } or { 255, 90, 90, 255 }
    local size  = isCrit and 22 or 17
    animState_.floats[#animState_.floats + 1] = {
        text     = txt,
        x        = ex + math.random(-20, 20),
        y        = ey,
        vy       = -55,   -- 向上飘
        alpha    = 255,
        elapsed  = 0,
        duration = 0.9,
        color    = color,
        size     = size,
    }
    -- 闪光圆
    animState_.flashes[#animState_.flashes + 1] = {
        x        = ex,
        y        = ey,
        r        = isCrit and 34 or 24,
        alpha    = 180,
        elapsed  = 0,
        duration = 0.25,
        color    = color,
    }
    -- 音效
    if isCrit then
        PlayBattleSound("audio/sfx/battle_crit.ogg")
    else
        PlayBattleSound("audio/sfx/battle_hit.ogg")
    end
end

--- 触发玩家受伤动画
local function TriggerHurtAnim(damage)
    if not pageActive_ then return end
    local logW = graphics:GetWidth()  / graphics:GetDPR()
    local logH = graphics:GetHeight() / graphics:GetDPR()
    local px   = logW * 0.22
    local py   = logH * 0.23  -- 对准头像圆心

    animState_.floats[#animState_.floats + 1] = {
        text     = "-" .. tostring(damage),
        x        = px + math.random(-15, 15),
        y        = py,
        vy       = -50,
        alpha    = 255,
        elapsed  = 0,
        duration = 0.85,
        color    = { 230, 60, 60, 255 },
        size     = 16,
    }
    animState_.flashes[#animState_.flashes + 1] = {
        x        = px,
        y        = py,
        r        = 26,
        alpha    = 160,
        elapsed  = 0,
        duration = 0.22,
        color    = { 230, 60, 60, 255 },
    }
    -- 触发头像抖动（由 OnAnimUpdate 每帧驱动 marginLeft + RebuildUI）
    animState_.shakes[#animState_.shakes + 1] = {
        elapsed  = 0,
        duration = 0.36,
        amp      = 8,
    }
    PlayBattleSound("audio/sfx/battle_hurt.ogg")
end

--- NVG 绘制回调（每帧由 NVG.Register 调用）
local function OnAnimDraw(ctx)
    if not ctx then return end
    EnsureAnimFont(ctx)
    local floats = animState_.floats
    local flashes = animState_.flashes
    -- 绘制闪光圆
    for _, f in ipairs(flashes) do
        local a = math.floor(f.alpha * (1 - f.elapsed / f.duration))
        if a > 0 then
            local c = f.color
            nvgBeginPath(ctx)
            nvgCircle(ctx, f.x, f.y, f.r)
            nvgFillColor(ctx, nvgRGBA(c[1], c[2], c[3], a))
            nvgFill(ctx)
        end
    end
    -- 绘制飘字
    nvgFontFace(ctx, "sans")
    nvgTextAlign(ctx, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, f in ipairs(floats) do
        local a = math.floor(f.alpha * (1 - f.elapsed / f.duration))
        if a > 0 then
            local c = f.color
            nvgFontSize(ctx, f.size)
            nvgFillColor(ctx, nvgRGBA(c[1], c[2], c[3], a))
            nvgText(ctx, f.x, f.y, f.text)
        end
    end
end

--- 动画帧更新回调
local function OnAnimUpdate(dt)
    local alive = {}
    for _, f in ipairs(animState_.floats) do
        f.elapsed = f.elapsed + dt
        f.y       = f.y + f.vy * dt
        if f.elapsed < f.duration then alive[#alive + 1] = f end
    end
    animState_.floats = alive

    local aliveF = {}
    for _, f in ipairs(animState_.flashes) do
        f.elapsed = f.elapsed + dt
        if f.elapsed < f.duration then aliveF[#aliveF + 1] = f end
    end
    animState_.flashes = aliveF

    local aliveS = {}
    for _, f in ipairs(animState_.shakes) do
        f.elapsed = f.elapsed + dt
        if f.elapsed < f.duration then aliveS[#aliveS + 1] = f end
    end
    animState_.shakes = aliveS

    -- 驱动头像抖动：每帧更新 playerShakeX_ 并重建 UI
    if #aliveS > 0 then
        local f = aliveS[1]
        local t = f.elapsed / f.duration
        playerShakeX_ = math.sin(f.elapsed * 44) * f.amp * (1 - t)
        shakeWasActive_ = true
        if pageActive_ then Router.RebuildUI() end
    elseif shakeWasActive_ then
        shakeWasActive_ = false
        playerShakeX_   = 0
        if pageActive_ then Router.RebuildUI() end
    end
end

--- 清空动画状态
local function ClearAnimState()
    animState_.floats  = {}
    animState_.flashes = {}
    animState_.shakes  = {}
    playerShakeX_   = 0
    shakeWasActive_ = false
end

-- ============================================================================
-- 战斗 Update（驱动回合播放）
-- ============================================================================
local function BattleUpdate(dt)
    local s = battleState_
    if s.phase ~= PHASE_BATTLE then return end

    s.timer = s.timer + dt
    if s.timer < ROUND_INTERVAL then return end
    s.timer = s.timer - ROUND_INTERVAL

    s.roundIdx = s.roundIdx + 1
    if s.roundIdx > #s.rounds then
        s.phase = PHASE_RESULT
        if not s.settled then
            s.settled = true
            GameExplore.AFKSettleCombat(s.encounter, s.win, s.summary, function(_, msg, equipDrop)
                s.resultMsg = msg or s.summary
                s.equipDrop = equipDrop
                if pageActive_ then Router.RebuildUI() end
            end)
            s.resultMsg = "结算中..."
        end
        StartResultTimer()
        if pageActive_ then Router.RebuildUI() end
        return
    end

    local round = s.rounds[s.roundIdx]
    local log = s.battleLog
    local pName = "我方"
    local eName = s.encounter.name or "妖"

    -- == 功法触发日志 ==
    if round.skillActions then
        for _, sa in ipairs(round.skillActions) do
            local desc = sa.desc or "发动"
            if sa.type == "damage" then
                log[#log + 1] = "<c=cyan>[" .. sa.name .. "]</c> " .. desc ..
                    "，攻击提升<c=gold>" .. sa.value .. "</c>"
            elseif sa.type == "heal" then
                log[#log + 1] = "<c=cyan>[" .. sa.name .. "]</c> " .. desc ..
                    "，回复<c=green>" .. sa.value .. "</c>气血"
            elseif sa.type == "shield" then
                log[#log + 1] = "<c=cyan>[" .. sa.name .. "]</c> " .. desc ..
                    "，减伤<c=yellow>" .. (sa.value or sa.dmgBonus or "?") .. "</c>"
            elseif sa.type == "buff" then
                local statNames = { dodge = "闪避", attack = "攻击", defense = "防御" }
                local sn = statNames[sa.stat] or sa.stat
                log[#log + 1] = "<c=cyan>[" .. sa.name .. "]</c> " .. desc ..
                    "，" .. sn .. "+<c=yellow>" .. (sa.value or "?") .. "%</c>(" .. (sa.duration or "?") .. "回合)"
            end
        end
    end

    -- == 玩家攻击日志 ==
    local pa = round.playerAction
    if pa then
        if pa.hit then
            local critTag = pa.crit and "<c=gold>[暴击]</c>" or ""
            log[#log + 1] = "第" .. round.num .. "回合: " .. pName ..
                "攻击" .. eName .. critTag .. "，造成<c=red>" .. pa.damage .. "</c>点伤害"
            TriggerHitAnim(pa.damage, pa.crit)
        else
            log[#log + 1] = "第" .. round.num .. "回合: " .. pName ..
                "攻击" .. eName .. "，<c=gray>未命中</c>"
        end
    end

    -- == 灵宠出手日志 ==
    if round.petAction then
        local pet = round.petAction
        if pet.type == "attack" then
            log[#log + 1] = "<c=yellow>[" .. pet.name .. "]</c> " .. pet.skill ..
                "，造成<c=red>" .. pet.damage .. "</c>点伤害"
        elseif pet.type == "heal" then
            log[#log + 1] = "<c=yellow>[" .. pet.name .. "]</c> " .. pet.skill ..
                "，回复<c=green>" .. pet.value .. "</c>气血"
        elseif pet.type == "shield" then
            log[#log + 1] = "<c=yellow>[" .. pet.name .. "]</c> " .. pet.skill ..
                "，护盾减伤<c=yellow>" .. pet.value .. "</c>"
        end
    end

    -- == 敌方攻击日志 ==
    local ea = round.enemyAction
    if ea then
        if ea.hit then
            local critTag = ea.crit and "<c=gold>[暴击]</c>" or ""
            local shieldTag = ea.shielded and "<c=yellow>[护盾]</c>" or ""
            log[#log + 1] = eName .. "反击" .. pName .. critTag .. shieldTag ..
                "，造成<c=red>" .. ea.damage .. "</c>点伤害"
            TriggerHurtAnim(ea.damage)
        else
            log[#log + 1] = eName .. "攻击" .. pName .. "，<c=gray>未命中</c>"
        end
    end

    if round.finished then
        if round.win then
            log[#log + 1] = "<c=gold>--- " .. eName .. "倒下了 ---</c>"
        else
            log[#log + 1] = "<c=red>--- 我方败退 ---</c>"
        end
        s.phase = PHASE_RESULT
        if not s.settled then
            s.settled = true
            GameExplore.AFKSettleCombat(s.encounter, s.win, s.summary, function(_, msg, equipDrop)
                s.resultMsg = msg or s.summary
                s.equipDrop = equipDrop
                if pageActive_ then Router.RebuildUI() end
            end)
            s.resultMsg = "结算中..."
        end
        StartResultTimer()
    end

    if pageActive_ then Router.RebuildUI() end
end

-- ============================================================================
-- 结果自动继续计时器
-- ============================================================================
function StartResultTimer()
    NVG.Unregister(resultTimerKey_)
    local elapsed = 0
    local delay = battleState_.equipDrop and RESULT_EQUIP_DELAY or RESULT_AUTO_DELAY
    NVG.Register(resultTimerKey_, nil, function(dt)
        elapsed = elapsed + dt
        -- 有装备掉落时动态更新延迟（可能回调晚于计时器启动）
        if battleState_.equipDrop and delay < RESULT_EQUIP_DELAY then
            delay = RESULT_EQUIP_DELAY
        end
        if elapsed >= delay then
            NVG.Unregister(resultTimerKey_)
            ReturnToSeeking()
        end
    end)
end

-- ============================================================================
-- 返回寻敌状态
-- ============================================================================
function ReturnToSeeking()
    battleState_.phase = PHASE_SEEKING
    battleState_.encounter = nil
    battleState_.rounds = {}
    battleState_.roundIdx = 0
    battleState_.battleLog = {}
    battleState_.settled = false
    battleState_.resultMsg = ""
    battleState_.equipDrop = nil
    NVG.Unregister(battleUpdateKey_)
    NVG.Unregister(resultTimerKey_)
    NVG.Unregister(ANIM_KEY)
    ClearAnimState()
    if pageActive_ then Router.RebuildUI() end
end

-- ============================================================================
-- 开始战斗播放（由 AFK 回调触发）
-- ============================================================================
local function StartBattle(enc, roundsData, win, summary)
    local s = battleState_
    s.phase = PHASE_BATTLE
    s.encounter = enc
    s.monsterImg = GameExplore.GetMonsterImage(enc)
    s.rounds = roundsData
    s.roundIdx = 0
    s.win = win
    s.summary = summary
    s.timer = 0
    s.battleLog = {}
    s.settled = false
    s.resultMsg = ""

    ClearAnimState()
    NVG.Register(battleUpdateKey_, nil, BattleUpdate)
    NVG.Register(ANIM_KEY, OnAnimDraw, OnAnimUpdate)
    if pageActive_ then Router.RebuildUI() end
end

-- ============================================================================
-- AFK 可视化回调
-- ============================================================================
local function OnAFKCombat(combatData, roundsData, win, summary)
    StartBattle(combatData, roundsData, win, summary)
end

local function OnAFKEvent(msg)
    -- 非战斗事件（采集/无事发生），刷新 UI 显示最新日志
    if pageActive_ then Router.RebuildUI() end
end

local function OnAFKSeekStart()
    -- 开始寻敌，如果当前不是 seeking 状态则切回
    if battleState_.phase ~= PHASE_BATTLE then
        battleState_.phase = PHASE_SEEKING
        if pageActive_ then Router.RebuildUI() end
    end
end

-- ============================================================================
-- 注册/注销视觉回调
-- ============================================================================
local function RegisterVisualCallbacks()
    GameExplore.SetAFKVisualCallbacks({
        onCombat = OnAFKCombat,
        onEvent = OnAFKEvent,
        onSeekStart = OnAFKSeekStart,
    })
end

local function UnregisterVisualCallbacks()
    GameExplore.ClearAFKVisualCallbacks()
    NVG.Unregister(battleUpdateKey_)
    NVG.Unregister(resultTimerKey_)
    NVG.Unregister(ANIM_KEY)
    ClearAnimState()
end

-- ============================================================================
-- HP 条组件
-- ============================================================================
local function BuildHPBar(current, max, label, isEnemy)
    local pct = max > 0 and (current / max) or 0
    if pct < 0 then pct = 0 end
    if pct > 1 then pct = 1 end
    local barColor = isEnemy and Theme.colors.danger or { 80, 180, 80, 255 }
    local hpText = tostring(math.max(0, math.floor(current))) .. "/" .. tostring(math.floor(max))

    return UI.Panel {
        width = "100%",
        gap = 2,
        children = {
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                children = {
                    UI.Label {
                        text = label,
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = isEnemy and Theme.colors.dangerLight or Theme.colors.successLight,
                    },
                    UI.Label {
                        text = hpText,
                        fontSize = 9,
                        fontColor = Theme.colors.textLight,
                    },
                },
            },
            UI.Panel {
                width = "100%",
                height = 8,
                borderRadius = 4,
                backgroundColor = { 40, 35, 30, 200 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(pct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 4,
                        backgroundColor = barColor,
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 战斗场景区
-- ============================================================================
local function BuildBattleScene(p, s)
    local curRound = s.roundIdx > 0 and s.roundIdx <= #s.rounds and s.rounds[s.roundIdx] or nil
    local playerHP = curRound and curRound.playerHP or (p.hp or 800)
    local playerHPMax = curRound and curRound.playerHPMax or (p.hpMax or 800)
    local enemyHP = curRound and curRound.enemyHP or (s.encounter and s.encounter.hp or 100)
    local enemyHPMax = s.encounter and s.encounter.hp or 100

    local roundText = ""
    if s.phase == PHASE_BATTLE then
        roundText = "第 " .. tostring(s.roundIdx) .. " / " .. tostring(#s.rounds) .. " 回合"
    elseif s.phase == PHASE_RESULT then
        roundText = s.win and "胜利" or "败退"
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
        padding = 10,
        gap = 8,
        children = {
            UI.Label {
                text = roundText,
                fontSize = 11,
                fontColor = Theme.colors.textGold,
                textAlign = "center",
                width = "100%",
            },
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "flex-end",
                justifyContent = "space-around",
                children = {
                    UI.Panel {
                        width = "40%",
                        alignItems = "center",
                        gap = 4,
                        marginLeft = math.floor(playerShakeX_),
                        children = {
                            UI.Panel {
                                width = 60, height = 60, borderRadius = 30,
                                overflow = "hidden",
                                backgroundColor = { 45, 36, 28, 255 },
                                borderColor = { 80, 180, 80, 200 },
                                borderWidth = 2,
                                children = {
                                    UI.Panel {
                                        width = "100%", height = "100%",
                                        backgroundImage = avatarImg,
                                        backgroundFit = "cover",
                                    },
                                },
                            },
                            UI.Label {
                                text = p.name or "我",
                                fontSize = 11, fontWeight = "bold",
                                fontColor = Theme.colors.successLight,
                            },
                            BuildHPBar(playerHP, playerHPMax, "气血", false),
                        },
                    },
                    UI.Label {
                        text = "VS",
                        fontSize = 18, fontWeight = "bold",
                        fontColor = Theme.colors.gold,
                        marginBottom = 30,
                    },
                    UI.Panel {
                        width = "40%",
                        alignItems = "center",
                        gap = 4,
                        children = {
                            UI.Panel {
                                width = 60, height = 60, borderRadius = 30,
                                overflow = "hidden",
                                backgroundColor = (s.encounter and s.encounter.isBoss)
                                    and { 50, 40, 15, 255 } or { 50, 25, 25, 255 },
                                borderColor = (s.encounter and s.encounter.isBoss)
                                    and Theme.colors.gold or Theme.colors.dangerLight,
                                borderWidth = (s.encounter and s.encounter.isBoss) and 3 or 2,
                                children = {
                                    s.monsterImg and UI.Panel {
                                        width = "100%", height = "100%",
                                        backgroundImage = s.monsterImg,
                                        backgroundFit = "cover",
                                    } or UI.Label {
                                        text = "妖",
                                        fontSize = 20, fontWeight = "bold",
                                        fontColor = Theme.colors.dangerLight,
                                    },
                                },
                            },
                            UI.Label {
                                text = (s.encounter and s.encounter.isBoss and "[Boss] " or "")
                                    .. (s.encounter and s.encounter.name or "未知"),
                                fontSize = 11, fontWeight = "bold",
                                fontColor = (s.encounter and s.encounter.isBoss)
                                    and Theme.colors.textGold or Theme.colors.dangerLight,
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
-- 战斗日志
-- ============================================================================
local function BuildBattleLog(logLines)
    if #logLines == 0 then
        return UI.Panel {
            width = "100%", height = 60,
            justifyContent = "center", alignItems = "center",
            children = {
                UI.Label {
                    text = "战斗即将开始...",
                    fontSize = Theme.fontSize.small,
                    fontColor = Theme.colors.textSecondary,
                },
            },
        }
    end
    return Comp.BuildLogPanel(logLines, { height = 120, autoScrollBottom = true })
end

-- ============================================================================
-- 装备掉落展示面板
-- ============================================================================
local function BuildEquipDropPanel(equip)
    if not equip then return nil end
    local qColor = DataItems.GetQualityColor(equip.quality or "common")
    local qLabel = DataItems.GetQualityLabel(equip.quality or "common")
    local slotDef = DataItems.GetSlotByKey(equip.slot or "weapon")
    local slotLabel = slotDef and slotDef.label or "装备"

    -- 基础属性行
    local statLines = {}
    if equip.baseAtk and equip.baseAtk > 0 then
        statLines[#statLines + 1] = "攻击 +" .. equip.baseAtk
    end
    if equip.baseDef and equip.baseDef > 0 then
        statLines[#statLines + 1] = "防御 +" .. equip.baseDef
    end
    if equip.baseCrit and equip.baseCrit > 0 then
        statLines[#statLines + 1] = "暴击 +" .. equip.baseCrit
    end
    if equip.baseSpd and equip.baseSpd > 0 then
        statLines[#statLines + 1] = "速度 +" .. equip.baseSpd
    end

    -- 额外属性
    local extraLines = {}
    if equip.extraStats then
        for _, es in ipairs(equip.extraStats) do
            local label = DataItems.STAT_LABEL[es.stat] or es.stat
            extraLines[#extraLines + 1] = label .. " +" .. es.value
        end
    end

    local children = {
        -- 标题行：获得装备
        UI.Label {
            text = "获得装备",
            fontSize = 11,
            fontWeight = "bold",
            fontColor = Theme.colors.textGold,
            textAlign = "center",
            width = "100%",
        },
        -- 装备名 + 品质
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            alignItems = "center",
            gap = 6,
            children = {
                UI.Label {
                    text = "[" .. qLabel .. "]",
                    fontSize = 11,
                    fontWeight = "bold",
                    fontColor = qColor,
                },
                UI.Label {
                    text = equip.name or "未知装备",
                    fontSize = 13,
                    fontWeight = "bold",
                    fontColor = qColor,
                },
            },
        },
        -- 槽位
        UI.Label {
            text = "部位: " .. slotLabel,
            fontSize = 10,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
        },
    }

    -- 基础属性
    if #statLines > 0 then
        children[#children + 1] = UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = "center",
            gap = 10,
            children = (function()
                local items = {}
                for _, line in ipairs(statLines) do
                    items[#items + 1] = UI.Label {
                        text = line,
                        fontSize = 10,
                        fontColor = Theme.colors.textLight,
                    }
                end
                return items
            end)(),
        }
    end

    -- 额外属性（品质加成）
    if #extraLines > 0 then
        children[#children + 1] = UI.Panel {
            width = "100%",
            alignItems = "center",
            gap = 2,
            children = (function()
                local items = {}
                for _, line in ipairs(extraLines) do
                    items[#items + 1] = UI.Label {
                        text = line,
                        fontSize = 10,
                        fontWeight = "bold",
                        fontColor = { 120, 220, 120, 255 },
                    }
                end
                return items
            end)(),
        }
    end

    return UI.Panel {
        width = "100%",
        padding = 8,
        borderRadius = Theme.radius.md,
        backgroundColor = { 40, 35, 20, 220 },
        borderColor = qColor,
        borderWidth = 1,
        alignItems = "center",
        gap = 4,
        children = children,
    }
end

-- ============================================================================
-- 难度颜色
-- ============================================================================
local DIFF_COLORS = {
    normal = { 160, 200, 160 },
    elite  = { 220, 180, 80 },
    hard   = { 220, 80, 80 },
}

-- ============================================================================
-- 区域/难度信息条
-- ============================================================================
local function BuildAreaInfoBar()
    local areaConf = DataWorld.GetArea(currentAreaId_)
    local diffConf = DataWorld.GetDifficulty(currentDifficulty_)
    local areaName = areaConf and areaConf.name or "未知区域"
    local diffName = diffConf and diffConf.name or "普通"
    local diffColor = DIFF_COLORS[currentDifficulty_] or { 180, 180, 180 }

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        paddingLeft = 8, paddingRight = 8,
        paddingTop = 4, paddingBottom = 4,
        backgroundColor = { 30, 25, 20, 180 },
        borderRadius = 4,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = areaName,
                        fontSize = 13,
                        fontWeight = "bold",
                        fontColor = Theme.colors.textGold,
                    },
                    UI.Panel {
                        paddingLeft = 6, paddingRight = 6,
                        paddingTop = 2, paddingBottom = 2,
                        borderRadius = 3,
                        backgroundColor = { diffColor[1], diffColor[2], diffColor[3], 30 },
                        borderColor = diffColor,
                        borderWidth = 1,
                        children = {
                            UI.Label {
                                text = diffName,
                                fontSize = 10,
                                fontWeight = "bold",
                                fontColor = diffColor,
                            },
                        },
                    },
                },
            },
            UI.Label {
                text = "切换",
                fontSize = 11,
                fontColor = Theme.colors.accent,
                cursor = "pointer",
                onClick = function(self)
                    GameExplore.StopAFK("切换区域")
                    UnregisterVisualCallbacks()
                    Router.EnterState(Router.STATE_WORLD_MAP)
                end,
            },
        },
    }
end

-- ============================================================================
-- 时间格式化
-- ============================================================================
local function FormatDuration(seconds)
    local total = math.max(0, math.floor(seconds or 0))
    local h = math.floor(total / 3600)
    local m = math.floor((total % 3600) / 60)
    local s = total % 60
    if h > 0 then
        return string.format("%02d:%02d:%02d", h, m, s)
    end
    return string.format("%02d:%02d", m, s)
end

-- ============================================================================
-- 自动回收设置面板
-- ============================================================================
local AUTO_SELL_OPTIONS = {
    { key = "none",      label = "关闭" },
    { key = "fanqi",     label = "凡器" },
    { key = "lingbao",   label = "灵宝" },
    { key = "xtlingbao", label = "先天灵宝" },
    { key = "huangqi",   label = "皇器" },
}

local function BuildAutoSellPanel()
    local p = GamePlayer.Get()
    local current = (p and p.autoSellBelow) or "none"

    local buttons = {}
    for _, opt in ipairs(AUTO_SELL_OPTIONS) do
        local isActive = (current == opt.key)
        local qColor = opt.key ~= "none" and DataItems.GetQualityColor(opt.key) or Theme.colors.textSecondary
        buttons[#buttons + 1] = UI.Panel {
            paddingHorizontal = 10,
            paddingVertical = 5,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and { qColor[1], qColor[2], qColor[3], 40 } or { 40, 35, 30, 180 },
            borderColor = isActive and qColor or Theme.colors.border,
            borderWidth = isActive and 2 or 1,
            cursor = "pointer",
            onClick = function(self)
                if opt.key == current then return end
                local GameOps    = require("network.game_ops")
                local GameServer = require("game_server")
                GameOps.Request("set_auto_sell", {
                    playerKey     = GameServer.GetServerKey("player"),
                    autoSellBelow = opt.key,
                }, function(ok, data)
                    if ok then
                        Toast.Show(data.msg or "设置成功", { variant = "success" })
                    else
                        Toast.Show((data and data.msg) or "设置失败", { variant = "error" })
                    end
                    Router.RebuildUI()
                end)
            end,
            children = {
                UI.Label {
                    text = opt.label,
                    fontSize = Theme.fontSize.small,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and qColor or Theme.colors.textLight,
                },
            },
        }
    end

    local descText = "关闭"
    if current ~= "none" then
        local ql = DataItems.GetQualityLabel(current)
        descText = ql .. "及以下品质装备将自动回收为灵石"
    end

    return Comp.BuildCardPanel("自动回收", {
        UI.Panel {
            width = "100%",
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 6,
            children = buttons,
        },
        UI.Label {
            text = descText,
            fontSize = Theme.fontSize.tiny,
            fontColor = Theme.colors.textSecondary,
            marginTop = 4,
        },
    })
end

-- ============================================================================
-- AFK 统计面板
-- ============================================================================
local function BuildAFKStatsPanel()
    local afk = GameExplore.GetAFKState()
    local session = afk.session or {}
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 6,
        paddingTop = 4,
        paddingBottom = 4,
        children = {
            UI.Label {
                text = "时长: " .. FormatDuration(session.duration or 0),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
                width = "45%",
            },
            UI.Label {
                text = "战斗: " .. tostring(session.battles or 0) ..
                    " (胜" .. tostring(session.wins or 0) .. "/败" .. tostring(session.losses or 0) .. ")",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
                width = "55%",
            },
            UI.Label {
                text = "采集: " .. tostring(session.gatherEvents or 0),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textLight,
                width = "45%",
            },
            UI.Label {
                text = "灵石: +" .. tostring(session.lingStone or 0),
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.gold,
                width = "55%",
            },
            UI.Label {
                text = "装备: " .. tostring(session.equipDrops or 0),
                fontSize = Theme.fontSize.small,
                fontColor = (session.equipDrops or 0) > 0 and Theme.colors.textGold or Theme.colors.textLight,
                width = "45%",
            },
        },
    }
end

-- ============================================================================
-- 寻敌状态面板
-- ============================================================================
local function BuildSeekingPanel()
    local afk = GameExplore.GetAFKState()
    local seekPct = 0
    if afk.seekDelay and afk.seekDelay > 0 then
        seekPct = math.min(1, (afk.seekTimer or 0) / afk.seekDelay)
    end

    return UI.Panel {
        width = "100%",
        borderRadius = Theme.radius.lg,
        backgroundColor = Theme.colors.bgDark,
        borderColor = Theme.colors.borderGold,
        borderWidth = 1,
        padding = 12,
        gap = 8,
        alignItems = "center",
        children = {
            UI.Label {
                text = afk.active and "搜寻中..." or "待命中",
                fontSize = 14,
                fontWeight = "bold",
                fontColor = Theme.colors.textGold,
            },
            -- 进度条
            UI.Panel {
                width = "80%",
                height = 6,
                borderRadius = 3,
                backgroundColor = { 40, 35, 30, 200 },
                overflow = "hidden",
                children = {
                    UI.Panel {
                        width = tostring(math.floor(seekPct * 100)) .. "%",
                        height = "100%",
                        borderRadius = 3,
                        backgroundColor = Theme.colors.gold,
                    },
                },
            },
            UI.Label {
                text = "灵气探测中，感知周围遭遇...",
                fontSize = Theme.fontSize.small,
                fontColor = Theme.colors.textSecondary,
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

    -- 标记页面激活
    pageActive_ = true

    -- 从 payload 读取区域和难度
    if payload then
        if payload.areaId then currentAreaId_ = payload.areaId end
        if payload.difficulty then currentDifficulty_ = payload.difficulty end
    end

    -- 自动开始挂机（传入区域和难度）
    if not GameExplore.IsAFKActive() then
        local ok, msg = GameExplore.StartAFK(currentAreaId_, currentDifficulty_)
        if not ok then
            Toast.Show(msg or "无法开始挂机", { variant = "error" })
        end
    end

    -- 注册视觉回调
    RegisterVisualCallbacks()

    -- 注册 1 秒周期刷新定时器（仅 SEEKING 阶段，更新时长/进度条）
    NVG.Unregister(STATS_REFRESH_KEY)
    local statsElapsed = 0
    NVG.Register(STATS_REFRESH_KEY, nil, function(dt)
        statsElapsed = statsElapsed + dt
        if statsElapsed >= 1.0 then
            statsElapsed = statsElapsed - 1.0
            if pageActive_ and battleState_.phase == PHASE_SEEKING then
                Router.RebuildUI()
            end
        end
    end)

    -- 注册退出回调（离开页面时清理）
    Router.RegisterExit(Router.STATE_EXPLORE, function()
        pageActive_ = false

        -- 如果战斗动画正在播放且未结算，立即静默结算
        -- 防止 afkState_.pending 永远卡在 true
        local bs = battleState_
        if bs.encounter and not bs.settled and bs.phase == PHASE_BATTLE then
            bs.settled = true
            GameExplore.AFKSettleCombat(bs.encounter, bs.win, bs.summary, function() end)
        end

        UnregisterVisualCallbacks()
        -- 回到寻敌状态（但不停止 AFK）
        bs.phase = PHASE_SEEKING
        bs.encounter = nil
        bs.rounds = {}
        bs.roundIdx = 0
        bs.battleLog = {}
        bs.settled = false
        bs.equipDrop = nil
        NVG.Unregister(battleUpdateKey_)
        NVG.Unregister(resultTimerKey_)
        NVG.Unregister(STATS_REFRESH_KEY)
    end)

    local s = battleState_
    local contentChildren = {}
    local afk = GameExplore.GetAFKState()

    if s.phase == PHASE_SEEKING then
        -- ========================
        -- 寻敌状态
        -- ========================
        contentChildren = {
            Comp.BuildTextButton("< 返回地图", function()
                Router.EnterState(Router.STATE_WORLD_MAP, { noAutoRedirect = true })
            end),
            Comp.BuildSectionTitle("历练挂机"),
            BuildAreaInfoBar(),
            -- 寻敌动画面板
            BuildSeekingPanel(),
            -- AFK 统计
            BuildAFKStatsPanel(),
            -- 查看详细统计按钮
            Comp.BuildSecondaryButton("查看详细统计", function()
                Router.EnterState(Router.STATE_STATS)
            end, { fontSize = Theme.fontSize.small }),
            -- 自动回收设置
            BuildAutoSellPanel(),
            -- 挂机日志（最新在底部，自动滚动）
            Comp.BuildCardPanel("历练记录", {
                Comp.BuildLogPanel(afk.logs or {}, { height = 160, autoScrollBottom = true }),
            }),
        }

    elseif s.phase == PHASE_BATTLE then
        -- ========================
        -- 战斗播放中
        -- ========================
        local isBoss = s.encounter and s.encounter.isBoss
        local battleTitle = isBoss and "Boss战斗中" or "战斗中"
        contentChildren = {
            Comp.BuildSectionTitle(battleTitle),
            BuildAreaInfoBar(),
            BuildBattleScene(p, s),
            Comp.BuildCardPanel("战斗记录", {
                BuildBattleLog(s.battleLog),
            }),
            Comp.BuildSecondaryButton("跳过战斗", function()
                s.roundIdx = #s.rounds
                -- 快进到最后一回合的日志
                local lastRound = s.rounds[#s.rounds]
                if lastRound then
                    if lastRound.finished then
                        if lastRound.win then
                            s.battleLog[#s.battleLog + 1] = "<c=gold>--- " .. (s.encounter.name or "敌") .. "倒下了 ---</c>"
                        else
                            s.battleLog[#s.battleLog + 1] = "<c=red>--- 我方败退 ---</c>"
                        end
                    end
                end
                s.phase = PHASE_RESULT
                if not s.settled then
                    s.settled = true
                    GameExplore.AFKSettleCombat(s.encounter, s.win, s.summary, function(_, msg, equipDrop)
                        s.resultMsg = msg or s.summary
                        s.equipDrop = equipDrop
                        if pageActive_ then Router.RebuildUI() end
                    end)
                    s.resultMsg = "结算中..."
                end
                StartResultTimer()
                Router.RebuildUI()
            end),
        }

    elseif s.phase == PHASE_RESULT then
        -- ========================
        -- 战斗结果（自动继续）
        -- ========================
        local isBossResult = s.encounter and s.encounter.isBoss
        local resultTitle = s.win
            and (isBossResult and "Boss击败" or "战斗胜利")
            or "战斗败退"
        contentChildren = {
            Comp.BuildSectionTitle(resultTitle),
            BuildAreaInfoBar(),
            BuildBattleScene(p, s),
            Comp.BuildCardPanel("战斗记录", {
                BuildBattleLog(s.battleLog),
            }),
            UI.Panel {
                width = "100%",
                padding = Theme.spacing.md,
                borderRadius = Theme.radius.md,
                backgroundColor = s.win and { 30, 50, 30, 200 } or { 50, 25, 25, 200 },
                borderColor = s.win and Theme.colors.successLight or Theme.colors.dangerLight,
                borderWidth = 1,
                alignItems = "center",
                children = {
                    Comp.BuildRichLabel(
                        s.resultMsg or s.summary,
                        Theme.fontSize.body,
                        s.win and Theme.colors.successLight or Theme.colors.dangerLight
                    ),
                },
            },
        }
        -- 装备掉落展示
        if s.equipDrop then
            local equipPanel = BuildEquipDropPanel(s.equipDrop)
            if equipPanel then
                contentChildren[#contentChildren + 1] = equipPanel
            end
        end
        contentChildren[#contentChildren + 1] = UI.Label {
            text = "即将继续探索...",
            fontSize = Theme.fontSize.small,
            fontColor = Theme.colors.textSecondary,
            textAlign = "center",
            width = "100%",
            marginTop = 4,
        }
    end

    -- PHASE_SEEKING: 停止/撤退按钮固定在底部，不随内容滚动
    local shellOpts = {}
    if s.phase == PHASE_SEEKING then
        shellOpts.bottomFixedRow = true
        shellOpts.bottomFixed = {
            afk.active and Comp.BuildSecondaryButton("停止挂机", function()
                local ok2, msg2 = GameExplore.StopAFK("手动停止")
                Toast.Show(msg2, { variant = ok2 and "success" or "error" })
                Router.RebuildUI()
            end, { flex = 1 }) or Comp.BuildInkButton("开始挂机", function()
                local ok2, msg2 = GameExplore.StartAFK(currentAreaId_, currentDifficulty_)
                Toast.Show(msg2, { variant = ok2 and "success" or "error" })
                Router.RebuildUI()
            end, { flex = 1 }),
            Comp.BuildSecondaryButton("撤退", function()
                GameExplore.StopAFK("撤退")
                UnregisterVisualCallbacks()
                Router.EnterState(Router.STATE_WORLD_MAP)
            end, { flex = 1 }),
        }
    end

    return Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate, shellOpts)
end

return M
