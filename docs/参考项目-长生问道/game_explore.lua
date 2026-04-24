-- ============================================================================
-- 《问道长生》探索模块
-- 职责：继续探索（随机遭遇 + 简易回合战斗）
-- 设计：Can/Do 模式
-- ============================================================================

local GamePlayer      = require("game_player")
local DataItems       = require("data_items")
local DataFormulas    = require("data_formulas")
local DataWorld       = require("data_world")
local DataMartialArts = require("data_martial_arts")
local GameQuest       = require("game_quest")
local GamePet         = require("game_pet")
local GameBattlePass  = require("game_battlepass")

local M = {}
local AFK_UPDATE_KEY = "explore_afk"
local AFK_LOG_LIMIT = 20

-- 当前挂机区域和难度（由 StartAFK 传入）
local selectedArea_ = "yunwu"
local selectedDifficulty_ = "normal"

local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

local afkState_ = {
    active = false,
    pending = false,
    seekTimer = 0,
    seekDelay = 0,
    session = nil,
    logs = {},
}

-- AFK 可视化回调：当 UI 页面激活时，战斗交给 UI 播放动画
-- onCombat(combatData, roundsData, win, summary) → 由 UI 播放回合动画
-- onEvent(msg) → 非战斗事件通知 UI 刷新
-- onSeekStart() → 开始寻敌时通知 UI
local afkVisualCb_ = nil

--- 设置 AFK 可视化回调（UI 页面进入时调用）
function M.SetAFKVisualCallbacks(cbs)
    afkVisualCb_ = cbs
end

--- 清除 AFK 可视化回调（UI 页面离开时调用）
function M.ClearAFKVisualCallbacks()
    afkVisualCb_ = nil
end

local function NewAFKSession()
    return {
        startTs = os.time(),
        duration = 0,
        battles = 0,
        wins = 0,
        losses = 0,
        lingStone = 0,
        gatherEvents = 0,
        equipDrops = 0,
        matDrops = 0,
    }
end

local function AppendAFKLog(text)
    local logs = afkState_.logs
    logs[#logs + 1] = text
    while #logs > AFK_LOG_LIMIT do
        table.remove(logs, 1)
    end
end

local function CopyTable(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do
        if type(v) == "table" then
            out[k] = CopyTable(v)
        else
            out[k] = v
        end
    end
    return out
end

local function SyncAFKStatsToPlayer()
    local p = GamePlayer.Get()
    local s = afkState_.session
    if not p or not s then return end
    p.afkStats = p.afkStats or {
        totalAfkTime = 0,
        totalBattles = 0,
        totalWins = 0,
        totalLosses = 0,
        totalLingStone = 0,
        totalGather = 0,
        totalEquipDrops = 0,
        totalMatDrops = 0,
        lastSession = {},
    }
    p.afkStats.totalAfkTime = (p.afkStats.totalAfkTime or 0) + math.floor(s.duration or 0)
    p.afkStats.totalBattles = (p.afkStats.totalBattles or 0) + (s.battles or 0)
    p.afkStats.totalWins = (p.afkStats.totalWins or 0) + (s.wins or 0)
    p.afkStats.totalLosses = (p.afkStats.totalLosses or 0) + (s.losses or 0)
    p.afkStats.totalLingStone = (p.afkStats.totalLingStone or 0) + (s.lingStone or 0)
    p.afkStats.totalGather = (p.afkStats.totalGather or 0) + (s.gatherEvents or 0)
    p.afkStats.totalEquipDrops = (p.afkStats.totalEquipDrops or 0) + (s.equipDrops or 0)
    p.afkStats.totalMatDrops = (p.afkStats.totalMatDrops or 0) + (s.matDrops or 0)
    p.afkStats.lastSession = CopyTable(s)

    -- 网络模式下通过 GameOps 仅保存 afkStats，避免 force Save 整个 playerData
    -- 覆盖服务端已修改的 pills/bagItems 等字段（竞态写覆盖根因修复）
    if IsNetworkMode() then
        local GameOps    = require("network.game_ops")
        local GameServer = require("game_server")
        GameOps.Request("save_afk_stats", {
            playerKey = GameServer.GetServerKey("player"),
            afkStats  = p.afkStats,
        }, function(ok2, data)
            if not ok2 then
                print("[Explore] afkStats 保存失败: " .. tostring(data and data.msg))
            end
        end)
    else
        GamePlayer.Save(nil, true)
    end
end

local function AddLingStoneDelta(before)
    local s = afkState_.session
    if not s then return end
    local after = GamePlayer.GetCurrency("lingStone")
    local delta = after - (before or after)
    if delta > 0 then
        s.lingStone = (s.lingStone or 0) + delta
    end
end

--- AFK 战斗结算（由 UI 播放完动画后调用）
function M.AFKSettleCombat(enc, win, summary, callback)
    local s = afkState_
    if not s.active then
        if callback then callback(false, "挂机已停止") end
        return
    end
    M.SettleCombat(enc, win, summary, function(ok2, settleMsg, equipDrop)
        if s.session then
            local beforeStone = GamePlayer.GetCurrency("lingStone")
            AddLingStoneDelta(beforeStone)
            -- 累计装备掉落数
            if equipDrop then
                s.session.equipDrops = (s.session.equipDrops or 0) + 1
            end
        end
        AppendAFKLog(settleMsg or summary)
        s.pending = false
        if callback then callback(ok2, settleMsg, equipDrop) end
    end)
end

local function SetNextSeekDelay()
    afkState_.seekDelay = math.random(3, 5)
    afkState_.seekTimer = 0
end

--- 获取当前挂机区域ID
function M.GetSelectedArea()
    return selectedArea_
end

--- 获取当前挂机难度ID
function M.GetSelectedDifficulty()
    return selectedDifficulty_
end

--- 获取当前区域配置
function M.GetSelectedAreaConfig()
    return DataWorld.GetArea(selectedArea_)
end

--- 获取当前难度配置
function M.GetSelectedDifficultyConfig()
    return DataWorld.GetDifficulty(selectedDifficulty_)
end

-- ============================================================================
-- 简易回合战斗（返回逐回合数据，供 UI 动态播放）
-- ============================================================================

--- 检查功法触发条件
---@param trigger string 触发类型
---@param roundNum number 当前回合
---@param pHP number 当前气血
---@param pHPMax number 最大气血
---@return boolean
local function CheckSkillTrigger(trigger, roundNum, pHP, pHPMax)
    if trigger == "every_3" then return roundNum % 3 == 0
    elseif trigger == "every_4" then return roundNum % 4 == 0
    elseif trigger == "every_5" then return roundNum % 5 == 0
    elseif trigger == "hp_low" then return pHP < pHPMax * 0.3
    end
    return false
end

--- 执行一次战斗，返回 win, summary, rounds, attrSummary
--- 整合：装备加成（已含在 playerData）、灵宠属性加成 + 回合出手、功法战斗效果
---@param enemy table { name, atk, def, hp }
---@return boolean win, string summary, table roundsData, table attrSummary
local function RunCombat(enemy)
    local p = GamePlayer.Get()

    -- ====== 1. 总属性（playerData 已含装备+法宝加成，由服务端烘焙） ======
    local totalAtk   = p.attack or 30
    local totalDef   = p.defense or 10
    local totalHP    = p.hpMax or 800
    local totalCrit  = p.crit or 5
    local totalHit   = p.hit or 90
    local totalDodge = p.dodge or 5

    -- 装备/法宝加成明细（仅用于 UI 展示拆分，不影响战斗计算）
    local equipBonus    = GamePlayer.GetEquippedBonus()
    local artifactBonus = GamePlayer.GetArtifactBonus()

    -- ====== 2. 灵宠属性加成 ======
    local petBonus = GamePet.GetCombatBonus()
    local pAtk   = totalAtk + petBonus.atkBonus
    local pDef   = totalDef + petBonus.defBonus
    local pHPMax = totalHP + petBonus.hpBonus
    local pHP    = math.min(p.hp or pHPMax, pHPMax)
    local pCrit  = totalCrit
    local pHit   = totalHit
    local pDodge = totalDodge

    -- ====== 3. 收集已装备武学的战斗效果（V2 武学系统） ======
    local activeSkills = {}
    local ma = p.martialArts
    if ma then
        local equipped = ma.equipped or {}
        local owned = ma.owned or {}
        for i = 1, DataMartialArts.MAX_EQUIPPED do
            local artId = equipped[i]
            if artId then
                local artDef = DataMartialArts.GetArt(artId)
                if artDef then
                    -- 查找等级
                    local level = 1
                    for _, o in ipairs(owned) do
                        if o.id == artId then level = o.level or 1; break end
                    end
                    local lvConf = DataMartialArts.GetLevel(level)
                    -- 灵根伤害倍率
                    local rootMultiplier = DataMartialArts.GetDamageMultiplier(
                        p.spiritRoots or {}, artDef.element
                    )
                    activeSkills[#activeSkills + 1] = {
                        name = artDef.name,
                        artId = artId,
                        effect = artDef.effect,
                        element = artDef.element,
                        baseDamage = artDef.baseDamage,
                        level = level,
                        multiplier = lvConf and lvConf.multiplier or 1.0,
                        rootMultiplier = rootMultiplier,
                        trigger = artDef.trigger,
                        cooldown = artDef.cooldown,
                        lastUsedRound = -99,
                    }
                end
            end
        end
    end

    -- ====== 4. 灵宠战斗出手数据 ======
    local activePet = GamePet.GetActivePet()
    local petCombat = nil
    if activePet then
        local petDef = DataWorld.GetPet(activePet.id)
        if petDef and petDef.combatStats then
            petCombat = {
                name = activePet.name,
                skill = activePet.skill,
                stats = petDef.combatStats,
                level = activePet.level or 1,
                lastUsedRound = -99,
            }
        end
    end

    -- ====== 5. 属性汇总（供 UI 展示明细） ======
    local skillNames = {}
    for _, sk in ipairs(activeSkills) do
        skillNames[#skillNames + 1] = sk.name .. " Lv." .. sk.level
    end
    -- 真实基础属性 = 总属性 - 装备加成 - 法宝加成
    local pureBaseAtk = totalAtk - equipBonus.attack - artifactBonus.attack
    local pureBaseDef = totalDef - equipBonus.defense - artifactBonus.defense
    local pureBaseHP  = totalHP - (equipBonus.hp or 0)
    local attrSummary = {
        -- 纯基础（不含装备/法宝）
        baseAtk = pureBaseAtk, baseDef = pureBaseDef, baseHP = pureBaseHP,
        -- 装备加成
        equipAtkBonus = equipBonus.attack, equipDefBonus = equipBonus.defense,
        equipHpBonus  = equipBonus.hp, equipCritBonus = equipBonus.crit,
        equipSpdBonus = equipBonus.speed, equipDodgeBonus = equipBonus.dodge,
        equipHitBonus = equipBonus.hit,
        -- 法宝加成
        artAtkBonus = artifactBonus.attack, artDefBonus = artifactBonus.defense,
        artCritBonus = artifactBonus.crit, artSpdBonus = artifactBonus.speed,
        -- 灵宠加成
        petAtkBonus = petBonus.atkBonus, petDefBonus = petBonus.defBonus,
        petHpBonus  = petBonus.hpBonus,
        -- 最终总值（含灵宠）
        totalAtk = pAtk, totalDef = pDef, totalHP = pHPMax,
        -- 功法/灵宠信息
        skills  = skillNames,
        petName = activePet and activePet.name or nil,
        petSkill = activePet and activePet.skill or nil,
    }

    -- ====== 6. 战斗循环 ======
    local eHP    = enemy.hp
    local eHPMax = enemy.hp
    local eAtk   = enemy.atk
    local eAtkBase = enemy.atk  -- 原始攻击力（用于 freeze/dispel 计算基准）
    local eDef   = enemy.def

    local roundsData = {}
    local roundNum   = 0
    local maxRounds  = 20
    local win        = false
    local finished   = false

    -- 状态效果跟踪
    local playerBuffs  = {}  -- { [stat] = { value, remaining } }
    local enemyDebuffs = {}  -- { [type] = { remaining, value, ... } }
    local enemyDoTs    = {}  -- { { type, dmgPerRound, remaining, name } }
    local enemyStunned = false  -- 本回合敌方是否被眩晕

    while roundNum < maxRounds and not finished do
        roundNum = roundNum + 1
        local round = {
            num = roundNum,
            playerAction = nil,
            enemyAction  = nil,
            skillActions = {},
            dotActions   = {},
            petAction    = nil,
            playerHP    = 0,
            playerHPMax = pHPMax,
            enemyHP     = 0,
            enemyHPMax  = eHPMax,
            finished    = false,
            win         = false,
        }

        -- == 回合开始：DoT 伤害 tick（burn/poison） ==
        enemyStunned = false
        local dotDamageTotal = 0
        for i = #enemyDoTs, 1, -1 do
            local dot = enemyDoTs[i]
            if dot.remaining > 0 then
                local dotDmg = math.max(1, math.floor(pAtk * dot.dmgPerRound))
                eHP = eHP - dotDmg
                dotDamageTotal = dotDamageTotal + dotDmg
                dot.remaining = dot.remaining - 1
                round.dotActions[#round.dotActions + 1] = {
                    name = dot.name, type = dot.type, damage = dotDmg,
                    remaining = dot.remaining,
                }
            end
            if dot.remaining <= 0 then
                table.remove(enemyDoTs, i)
            end
        end

        -- == 检查 DoT 击杀 ==
        if eHP <= 0 then
            eHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = true
            roundsData[#roundsData + 1] = round
            win = true; finished = true
            goto continueLoop
        end

        -- == 检查眩晕状态（stun debuff） ==
        local stunDebuff = enemyDebuffs["stun"]
        if stunDebuff and stunDebuff.remaining > 0 then
            enemyStunned = true
        end

        -- == 计算当前 buff 加成 ==
        local buffDodge = 0
        local buffDef = 0
        for stat, buff in pairs(playerBuffs) do
            if stat == "dodge" then buffDodge = buff.value end
            if stat == "defense" then buffDef = buff.value end
        end

        -- == 计算 freeze debuff 对敌方攻击的削弱 ==
        local freezeAtkReduce = 0
        local freezeDebuff = enemyDebuffs["freeze"]
        if freezeDebuff and freezeDebuff.remaining > 0 then
            freezeAtkReduce = freezeDebuff.value or 0
        end
        -- entangle 在简易回合制中也作为攻击削弱
        local entangleDebuff = enemyDebuffs["entangle"]
        if entangleDebuff and entangleDebuff.remaining > 0 then
            freezeAtkReduce = freezeAtkReduce + (entangleDebuff.value or 0)
        end
        -- dispel 的持续攻击削弱
        local dispelDebuff = enemyDebuffs["dispel"]
        if dispelDebuff and dispelDebuff.remaining > 0 then
            freezeAtkReduce = freezeAtkReduce + (dispelDebuff.value or 0)
        end

        -- == 武学触发（回合开始阶段） ==
        local skillAtkBonus = 0
        local shieldReduction = 0
        local lifestealPct = 0
        for _, sk in ipairs(activeSkills) do
            local ce = sk.effect
            local canUse = CheckSkillTrigger(sk.trigger, roundNum, pHP, pHPMax)
            if canUse and (roundNum - sk.lastUsedRound) < sk.cooldown then
                canUse = false
            end
            if canUse then
                sk.lastUsedRound = roundNum
                local rootMul = sk.rootMultiplier or 1.0
                -- 获取灵根效果增幅
                local matchLv = DataMartialArts.GetSpiritRootMatchLevel(
                    p.spiritRoots or {}, sk.element
                )
                local amplify = DataMartialArts.GetEffectAmplify(sk.element, matchLv)

                if ce.type == "damage" then
                    -- 纯伤害：baseDamage * 等级倍率 * 灵根倍率
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "damage",
                        element = sk.element,
                        value = math.floor(dmgBonus * 100) .. "%",
                    }

                elseif ce.type == "burn" then
                    -- 灼烧 DoT + 即时伤害
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local dotDmg = ce.dmgPerRound * sk.multiplier + (amplify.dmgAdd or 0)
                    local dur = (ce.duration or 2) + (amplify.durationAdd or 0)
                    -- 添加/刷新 DoT
                    enemyDoTs[#enemyDoTs + 1] = {
                        type = "burn", dmgPerRound = dotDmg,
                        remaining = dur, name = sk.name,
                    }
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "burn",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        dotPct = math.floor(dotDmg * 100) .. "%",
                        duration = dur,
                    }

                elseif ce.type == "poison" then
                    -- 毒素 DoT + 即时伤害
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local dotDmg = ce.dmgPerRound * sk.multiplier + (amplify.dmgAdd or 0)
                    local dur = (ce.duration or 3) + (amplify.durationAdd or 0)
                    enemyDoTs[#enemyDoTs + 1] = {
                        type = "poison", dmgPerRound = dotDmg,
                        remaining = dur, name = sk.name,
                    }
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "poison",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        dotPct = math.floor(dotDmg * 100) .. "%",
                        duration = dur,
                    }

                elseif ce.type == "entangle" then
                    -- 缠绕：降低敌方攻击 + 少量伤害
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local reduce = ce.speedReduce * sk.multiplier
                    local dur = (ce.duration or 2) + (amplify.durationAdd or 0)
                    enemyDebuffs["entangle"] = { remaining = dur, value = reduce }
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "entangle",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        reduce = math.floor(reduce * 100) .. "%",
                        duration = dur,
                    }

                elseif ce.type == "shield" then
                    -- 水盾：减少受到的伤害
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local shieldVal = ce.shieldPct * sk.multiplier + (amplify.shieldAdd or 0)
                    shieldReduction = math.max(shieldReduction, shieldVal)
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "shield",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        value = math.floor(shieldVal * 100) .. "%",
                    }

                elseif ce.type == "defense_buff" then
                    -- 防御增强：提升防御 + 减伤免疫
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local defVal = math.floor(pDef * ce.defBonus * sk.multiplier)
                    local immunity = ce.immunity + (amplify.immunityAdd or 0)
                    local dur = (ce.duration or 3)
                    playerBuffs["defense"] = { value = defVal, remaining = dur }
                    shieldReduction = math.max(shieldReduction, immunity)
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "defense_buff",
                        element = sk.element,
                        defBonus = defVal,
                        immunity = math.floor(immunity * 100) .. "%",
                        duration = dur,
                    }

                elseif ce.type == "stun" then
                    -- 眩晕：概率使敌方跳过攻击
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local chance = ce.chance + (amplify.chanceAdd or 0)
                    local dur = ce.duration or 1
                    local stunned = math.random() < chance
                    if stunned then
                        enemyDebuffs["stun"] = { remaining = dur, value = 1 }
                        enemyStunned = true
                    end
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "stun",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        chance = math.floor(chance * 100) .. "%",
                        stunned = stunned,
                    }

                elseif ce.type == "freeze" then
                    -- 冰冻：降低敌方攻击力
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local reduce = ce.atkReduce * sk.multiplier + (amplify.slowAdd or 0)
                    local dur = (ce.duration or 2)
                    enemyDebuffs["freeze"] = { remaining = dur, value = reduce }
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "freeze",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        atkReduce = math.floor(reduce * 100) .. "%",
                        duration = dur,
                    }

                elseif ce.type == "dodge_buff" then
                    -- 闪避提升
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local dodgeVal = math.floor((ce.dodgeBonus + (amplify.dodgeAdd or 0)) * 100)
                    local dur = (ce.duration or 2)
                    playerBuffs["dodge"] = { value = dodgeVal, remaining = dur }
                    buffDodge = dodgeVal
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "dodge_buff",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        dodgeBonus = dodgeVal, duration = dur,
                    }

                elseif ce.type == "lifesteal" then
                    -- 生命窃取：攻击时回血
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    lifestealPct = math.max(lifestealPct,
                        ce.stealPct * sk.multiplier + (amplify.stealAdd or 0))
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "lifesteal",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        stealPct = math.floor(lifestealPct * 100) .. "%",
                    }

                elseif ce.type == "dispel" then
                    -- 驱散：降低敌方攻击 + 即时伤害
                    local dmgBonus = sk.baseDamage * sk.multiplier * rootMul
                    skillAtkBonus = skillAtkBonus + dmgBonus
                    local reduce = ce.atkReduce * sk.multiplier + (amplify.atkReduceAdd or 0)
                    enemyDebuffs["dispel"] = { remaining = 2, value = reduce }
                    round.skillActions[#round.skillActions + 1] = {
                        name = sk.name, type = "dispel",
                        element = sk.element,
                        dmgBonus = math.floor(dmgBonus * 100) .. "%",
                        atkReduce = math.floor(reduce * 100) .. "%",
                    }
                end
            end
        end

        -- == 玩家攻击 ==
        local pResult = DataFormulas.ResolveAttack(
            { attack = pAtk, hit = pHit, crit = pCrit, skillAtkBonus = skillAtkBonus },
            { defense = eDef, dodge = 0, hp = eHP }
        )
        if pResult.hit then
            eHP = eHP - pResult.damage
            -- 生命窃取回血
            if lifestealPct > 0 then
                local stealAmt = math.max(1, math.floor(pResult.damage * lifestealPct))
                pHP = math.min(pHPMax, pHP + stealAmt)
                round.playerAction = { hit = true, crit = pResult.crit,
                    damage = pResult.damage, lifesteal = stealAmt }
            else
                round.playerAction = { hit = true, crit = pResult.crit,
                    damage = pResult.damage }
            end
        else
            round.playerAction = { hit = false, crit = false, damage = 0 }
        end

        -- == 灵宠出手（玩家攻击后） ==
        if petCombat then
            local cs = petCombat.stats
            if roundNum % cs.interval == 0 then
                petCombat.lastUsedRound = roundNum
                local lvScale = 1 + (petCombat.level - 1) * 0.1
                if cs.action == "attack" then
                    local petDmg = math.max(1, math.floor(pAtk * cs.damagePct * lvScale))
                    eHP = eHP - petDmg
                    round.petAction = { type = "attack", name = petCombat.name,
                        skill = petCombat.skill, damage = petDmg }
                elseif cs.action == "heal" then
                    local healAmt = math.max(1, math.floor(pHPMax * cs.healPct * lvScale))
                    pHP = math.min(pHPMax, pHP + healAmt)
                    round.petAction = { type = "heal", name = petCombat.name,
                        skill = petCombat.skill, value = healAmt }
                elseif cs.action == "shield" then
                    shieldReduction = math.max(shieldReduction, cs.shieldPct * lvScale)
                    round.petAction = { type = "shield", name = petCombat.name,
                        skill = petCombat.skill, value = math.floor(cs.shieldPct * lvScale * 100) .. "%" }
                end
            end
        end

        -- == 检查敌方是否阵亡 ==
        if eHP <= 0 then
            eHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = true
            roundsData[#roundsData + 1] = round
            win = true; finished = true
            goto continueLoop
        end

        -- == 敌方攻击（含眩晕跳过、护盾减伤、buff 闪避、freeze 削弱） ==
        if enemyStunned then
            -- 眩晕状态：敌方跳过本回合攻击
            round.enemyAction = { hit = false, crit = false, damage = 0, stunned = true }
        else
            local effectiveEAtk = math.max(1, math.floor(eAtkBase * (1 - freezeAtkReduce)))
            local effectiveDodge = pDodge + buffDodge
            local effectiveDef = pDef + buffDef
            local eResult = DataFormulas.ResolveAttack(
                { attack = effectiveEAtk, hit = 85, crit = 5, skillAtkBonus = 0 },
                { defense = effectiveDef, dodge = effectiveDodge, hp = pHP }
            )
            if eResult.hit then
                local dmg = eResult.damage
                if shieldReduction > 0 then
                    dmg = math.max(1, math.floor(dmg * (1 - shieldReduction)))
                end
                pHP = pHP - dmg
                round.enemyAction = { hit = true, crit = eResult.crit, damage = dmg,
                    shielded = shieldReduction > 0 }
            else
                round.enemyAction = { hit = false, crit = false, damage = 0 }
            end
        end

        -- == Debuff/Buff 持续时间递减 ==
        for stat, buff in pairs(playerBuffs) do
            buff.remaining = buff.remaining - 1
            if buff.remaining <= 0 then playerBuffs[stat] = nil end
        end
        for dtype, debuff in pairs(enemyDebuffs) do
            debuff.remaining = debuff.remaining - 1
            if debuff.remaining <= 0 then enemyDebuffs[dtype] = nil end
        end

        -- == 检查玩家是否阵亡 ==
        if pHP <= 0 then
            pHP = 0
            round.playerHP = pHP; round.enemyHP = eHP
            round.finished = true; round.win = false
            roundsData[#roundsData + 1] = round
            win = false; finished = true
            goto continueLoop
        end

        round.playerHP = pHP; round.enemyHP = eHP
        roundsData[#roundsData + 1] = round
        ::continueLoop::
    end

    local summary
    if win then
        summary = "战胜" .. enemy.name .. "（" .. #roundsData .. "回合）"
    elseif finished then
        summary = "败于" .. enemy.name .. "（" .. #roundsData .. "回合）"
    else
        summary = "与" .. enemy.name .. "僵持不下，被迫撤退"
    end

    return win, summary, roundsData, attrSummary
end

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 检查是否可以继续探索
---@return boolean, string|nil
function M.CanExplore()
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    if (p.hp or 0) <= 0 then return false, "气血耗尽，无法探索" end
    -- 区域解锁检查
    local unlocked, reason = DataWorld.IsAreaUnlocked(selectedArea_, p.tier or 1, p.sub or 1)
    if not unlocked then return false, reason end
    return true, nil
end

--- 执行战斗遭遇（返回详细战斗数据）
---@param enc table 遭遇数据（combat 类型）
---@return boolean win, string summary, table roundsData
function M.DoCombat(enc)
    return RunCombat(enc)
end

--- 结算战斗结果（发放奖励或扣血）
---@param enc table 遭遇数据
---@param win boolean 是否胜利
---@param summary string 战斗摘要
---@param callback? fun(ok: boolean, msg: string)
---@return boolean ok, string msg
function M.SettleCombat(enc, win, summary, callback)
    local onlineOk, onlineReason = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineReason or "需要联网模式") end
        return false, onlineReason or "需要联网模式"
    end

    GameQuest.SetMainFlag("explored", true)

    local GameOps    = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("explore_settle", {
        playerKey    = GameServer.GetServerKey("player"),
        win          = win,
        encName      = enc.name or "enemy",
        settleToken  = enc.settleToken or "",
    }, function(ok2, data)
        if ok2 then
            if win then
                GameQuest.NotifyAction("kill_monster", 1)
                -- 探索胜利增加通行证经验
                GameBattlePass.AddExp("exploreWin")
            end
            local msg = (data and data.msg) or summary
            GamePlayer.AddLog(msg)
            if data and data.petCaptured and data.petMsg then
                GamePlayer.AddLog(data.petMsg)
                msg = msg .. " " .. data.petMsg
            end
            -- 装备掉落处理
            local equipDrop = data and data.equipDrop or nil
            if equipDrop and data.equipMsg then
                GamePlayer.AddLog(data.equipMsg)
                msg = msg .. " " .. data.equipMsg
            end
            -- 自动卖处理
            if data and data.autoSold and data.autoSoldMsg then
                GamePlayer.AddLog(data.autoSoldMsg)
                msg = msg .. " " .. data.autoSoldMsg
            end
            -- 道心奖励
            if data and data.daoGain and data.daoGain > 0 and data.daoMsg then
                GamePlayer.AddLog(data.daoMsg)
                msg = msg .. " " .. data.daoMsg
            end
            if callback then callback(win, msg, equipDrop) end
        else
            local Toast = require("ui_toast")
            local err = (data and (data.msg or data.error)) or "结算失败"
            Toast.Show(err, "error")
            if callback then callback(false, err) end
        end
    end)
    return true, summary .. "..."
end
function M.DoExplore(callback)
    local onlineOk, onlineReason = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineReason or "需要联网模式") end
        return false, onlineReason or "需要联网模式"
    end

    local ok, reason = M.CanExplore()
    if not ok then
        if callback then callback(false, reason or "无法探索") end
        return false, reason or "无法探索"
    end

    local GameOps    = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("explore_encounter", {
        playerKey  = GameServer.GetServerKey("player"),
        areaId     = selectedArea_,
        difficulty = selectedDifficulty_,
    }, function(ok2, data)
        if not ok2 then
            local Toast = require("ui_toast")
            local err = (data and (data.msg or data.error)) or "探索失败"
            Toast.Show(err, "error")
            if callback then callback(false, err) end
            return
        end

        GameQuest.SetMainFlag("explored", true)
        local encType = data.encounterType

        if encType == "nothing" then
            local msg = "四处探索，无事发生"
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg, "nothing") end
        elseif encType == "gather" then
            local dropName  = data.dropName or "物品"
            local dropCount = data.dropCount or 1
            local encName   = data.encounterName or "资源"
            if dropName == "灵草" then
                GameQuest.NotifyAction("gather_herb", dropCount)
            end
            local msg = "发现" .. encName .. "，获得" .. dropName .. "x" .. dropCount
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg, "gather") end
        elseif encType == "combat" then
            local enemy = data.enemy
            if callback then callback(true, "遭遇" .. (enemy.name or "敌人"), "combat", enemy) end
        else
            if callback then callback(false, "未知遭遇类型") end
        end
    end, { loading = "探索中..." })
    return true, "请求已发送"
end
function M.GetMonsterImage(enc)
    local Theme = require("ui_theme")
    local monsters = Theme.monsters
    -- 根据遭遇的 tierMin 匹配最接近的怪物图（兜底防 nil）
    local tierMin = enc.tierMin or 1
    local tierMax = enc.tierMax or tierMin
    local tierAvg = math.floor((tierMin + tierMax) / 2)
    local bestIdx = 1
    local bestDiff = 999
    for i, m in ipairs(monsters) do
        local diff = math.abs(m.level - tierAvg * 5)
        if diff < bestDiff then
            bestDiff = diff
            bestIdx = i
        end
    end
    -- 加入随机偏移以增加多样性
    local offset = math.random(-2, 2)
    local finalIdx = math.max(1, math.min(#monsters, bestIdx + offset))
    return monsters[finalIdx].image
end

function M.IsAFKActive()
    return afkState_.active
end

function M.GetAFKState()
    return {
        active = afkState_.active,
        pending = afkState_.pending,
        seekDelay = afkState_.seekDelay,
        seekTimer = afkState_.seekTimer,
        session = CopyTable(afkState_.session or {}),
        logs = CopyTable(afkState_.logs or {}),
    }
end

--- 开始挂机历练
---@param areaId? string 区域ID，默认 "yunwu"
---@param difficulty? string 难度ID，默认 "normal"
function M.StartAFK(areaId, difficulty)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        return false, onlineErr
    end
    if afkState_.active then
        return false, "已在挂机中"
    end
    -- 设置区域和难度
    selectedArea_ = areaId or selectedArea_ or "yunwu"
    selectedDifficulty_ = difficulty or selectedDifficulty_ or "normal"
    local ok, reason = M.CanExplore()
    if not ok then
        return false, reason or "无法挂机"
    end
    afkState_.active = true
    afkState_.pending = false
    afkState_.session = NewAFKSession()
    afkState_.logs = {}
    SetNextSeekDelay()
    local areaConf = DataWorld.GetArea(selectedArea_)
    local diffConf = DataWorld.GetDifficulty(selectedDifficulty_)
    local areaName = areaConf and areaConf.name or selectedArea_
    local diffName = diffConf and diffConf.name or selectedDifficulty_
    AppendAFKLog("开始挂机历练 - " .. areaName .. "(" .. diffName .. ")")
    local NVG = require("nvg_manager")
    NVG.Register(AFK_UPDATE_KEY, nil, function(dt)
        M.UpdateAFK(dt)
    end)
    return true, "挂机已开始"
end

function M.StopAFK(reason)
    if not afkState_.active then
        return false, "当前未挂机"
    end
    afkState_.active = false
    afkState_.pending = false
    local NVG = require("nvg_manager")
    NVG.Unregister(AFK_UPDATE_KEY)
    if reason and reason ~= "" then
        AppendAFKLog("挂机结束: " .. reason)
    else
        AppendAFKLog("挂机已停止")
    end
    SyncAFKStatsToPlayer()
    return true, reason or "挂机已停止"
end

local function RunLocalGather(enc)
    local min = enc.dropCount[1]
    local max = enc.dropCount[2]
    local count = math.random(min, max)
    GamePlayer.AddItem({
        name = enc.drop,
        count = count,
        rarity = "common",
        desc = "探索获得",
    })
    if enc.drop == "灵草" then
        GameQuest.NotifyAction("gather_herb", count)
    end
    return "发现<c=gold>" .. enc.name .. "</c>，获得<c=yellow>" .. enc.drop .. "x" .. count .. "</c>", count
end

function M.UpdateAFK(dt)
    local s = afkState_
    if not s.active then return end
    local onlineOk = EnsureOnlineMode()
    if not onlineOk then
        M.StopAFK("需要联网模式")
        return
    end

    if s.session then
        s.session.duration = (s.session.duration or 0) + dt
    end

    if s.pending then return end

    local ok, reason = M.CanExplore()
    if not ok then
        M.StopAFK(reason or "气血不足")
        local Toast = require("ui_toast")
        Toast.Show(reason or "气血不足", { variant = "error" })
        return
    end

    s.seekTimer = (s.seekTimer or 0) + dt
    if s.seekTimer < (s.seekDelay or 3) then
        return
    end

    SetNextSeekDelay()
    s.pending = true
    local beforeStone = GamePlayer.GetCurrency("lingStone")

    -- 通知 UI 开始寻敌
    if afkVisualCb_ and afkVisualCb_.onSeekStart then
        afkVisualCb_.onSeekStart()
    end

    M.DoExplore(function(ok2, msg, encType, combatData)
        if not s.active then
            s.pending = false
            return
        end
        if not ok2 then
            AppendAFKLog(msg or "探索失败")
            s.pending = false
            M.StopAFK(msg or "探索失败")
            return
        end

        if encType == "combat" and combatData then
            if s.session then
                s.session.battles = (s.session.battles or 0) + 1
            end
            local win, summary, roundsData = M.DoCombat(combatData)
            if s.session then
                if win then
                    s.session.wins = (s.session.wins or 0) + 1
                else
                    s.session.losses = (s.session.losses or 0) + 1
                end
            end

            -- 如果 UI 注册了可视化回调，交给 UI 播放动画
            if afkVisualCb_ and afkVisualCb_.onCombat then
                afkVisualCb_.onCombat(combatData, roundsData, win, summary)
                -- pending 由 UI 在播放完动画并调用 AFKSettleCombat 后重置
                return
            end

            -- 无可视化回调（UI 不在历练页），静默结算
            M.SettleCombat(combatData, win, summary, function(_, settleMsg, equipDrop)
                AddLingStoneDelta(beforeStone)
                if equipDrop and s.session then
                    s.session.equipDrops = (s.session.equipDrops or 0) + 1
                end
                AppendAFKLog(settleMsg or summary)
                s.pending = false
            end)
            return
        end

        if encType == "gather" and s.session then
            s.session.gatherEvents = (s.session.gatherEvents or 0) + 1
        end
        AddLingStoneDelta(beforeStone)
        AppendAFKLog(msg or "探索完成")
        s.pending = false

        -- 通知 UI 非战斗事件
        if afkVisualCb_ and afkVisualCb_.onEvent then
            afkVisualCb_.onEvent(msg or "探索完成")
        end
    end)
end
return M
