-- ============================================================================
-- 《问道长生》切磋战斗弹窗
-- 职责：接收对手属性 → 简化 PVP 战斗模拟 → 展示逐回合战报 → 上报结算
-- ============================================================================

local UI           = require("urhox-libs/UI")
local Theme        = require("ui_theme")
local Comp         = require("ui_components")
local Router       = require("ui_router")
local GamePlayer   = require("game_player")
local GameSocial   = require("game_social")
local GamePet      = require("game_pet")
local DataFormulas = require("data_formulas")
local Toast        = require("ui_toast")
local RT           = require("rich_text")

local M = {}

-- ============================================================================
-- 简化 PVP 战斗模拟
-- 不含功法/灵宠（纯属性对比 + 随机性），最多 20 回合
-- ============================================================================

---@param enemy table { atk, def, hp, crit, hit, dodge }
---@return boolean win, table[] rounds
local function SimulatePVP(enemy)
    local p = GamePlayer.Get()

    -- 玩家属性（含装备+灵宠加成）
    local petBonus = GamePet.GetCombatBonus()
    local pAtk   = (p.attack or 30) + petBonus.atkBonus
    local pDef   = (p.defense or 10) + petBonus.defBonus
    local pHPMax = (p.hpMax or 800) + petBonus.hpBonus
    local pHP    = pHPMax
    local pCrit  = p.crit or 5
    local pHit   = p.hit or 90
    local pDodge = p.dodge or 5

    -- 对手属性
    local eAtk   = enemy.atk or 30
    local eDef   = enemy.def or 10
    local eHPMax = enemy.hp or 800
    local eHP    = eHPMax
    local eCrit  = enemy.crit or 5
    local eHit   = enemy.hit or 90
    local eDodge = enemy.dodge or 5

    local rounds = {}
    local win = false
    local maxRounds = 20

    for r = 1, maxRounds do
        local round = { num = r }

        -- 玩家攻击
        local pResult = DataFormulas.ResolveAttack(
            { attack = pAtk, hit = pHit, crit = pCrit, skillAtkBonus = 0 },
            { defense = eDef, dodge = eDodge, hp = eHP }
        )
        if pResult.hit then
            eHP = eHP - pResult.damage
            round.playerAction = { hit = true, crit = pResult.crit, damage = pResult.damage }
        else
            round.playerAction = { hit = false, damage = 0 }
        end

        if eHP <= 0 then
            eHP = 0
            round.playerHP = pHP; round.playerHPMax = pHPMax
            round.enemyHP = eHP;  round.enemyHPMax = eHPMax
            round.finished = true; round.win = true
            rounds[#rounds + 1] = round
            win = true; break
        end

        -- 对手攻击
        local eResult = DataFormulas.ResolveAttack(
            { attack = eAtk, hit = eHit, crit = eCrit, skillAtkBonus = 0 },
            { defense = pDef, dodge = pDodge, hp = pHP }
        )
        if eResult.hit then
            pHP = pHP - eResult.damage
            round.enemyAction = { hit = true, crit = eResult.crit, damage = eResult.damage }
        else
            round.enemyAction = { hit = false, damage = 0 }
        end

        if pHP <= 0 then
            pHP = 0
            round.playerHP = pHP; round.playerHPMax = pHPMax
            round.enemyHP = eHP;  round.enemyHPMax = eHPMax
            round.finished = true; round.win = false
            rounds[#rounds + 1] = round
            win = false; break
        end

        round.playerHP = pHP; round.playerHPMax = pHPMax
        round.enemyHP = eHP;  round.enemyHPMax = eHPMax
        rounds[#rounds + 1] = round
    end

    -- 回合用尽 → 比较剩余 HP 占比
    if #rounds >= maxRounds and pHP > 0 and eHP > 0 then
        win = (pHP / pHPMax) >= (eHP / eHPMax)
    end

    return win, rounds
end

-- ============================================================================
-- 战报行
-- ============================================================================

---@param round table
---@param myName string
---@param eName string
---@return string
local function FormatRound(round, myName, eName)
    local parts = {}
    parts[#parts + 1] = "<c=gold>第" .. round.num .. "回合:</c>"

    local pa = round.playerAction
    if pa then
        if pa.hit then
            local critMark = pa.crit and "<c=yellow>[暴击]</c>" or ""
            parts[#parts + 1] = myName .. critMark .. "造成<c=red>" .. pa.damage .. "</c>伤害"
        else
            parts[#parts + 1] = myName .. "<c=gray>攻击未命中</c>"
        end
    end

    local ea = round.enemyAction
    if ea then
        if ea.hit then
            local critMark = ea.crit and "<c=yellow>[暴击]</c>" or ""
            parts[#parts + 1] = eName .. critMark .. "造成<c=orange>" .. ea.damage .. "</c>伤害"
        else
            parts[#parts + 1] = eName .. "<c=gray>攻击未命中</c>"
        end
    end

    return table.concat(parts, "  ")
end

-- ============================================================================
-- 构建切磋弹窗
-- ============================================================================

--- 构建切磋弹窗（在 ui_social 的 Build 中叠加）
---@return table|nil  UI widget 或 nil
function M.BuildChallengeModal()
    local cd = GameSocial.GetChallengeData()
    if not cd then return nil end

    local p = GamePlayer.Get()
    local myName = p and p.name or "我"

    -- 模拟战斗
    local win, rounds = SimulatePVP(cd)

    -- 构建战报列表
    local logChildren = {}
    for _, round in ipairs(rounds) do
        logChildren[#logChildren + 1] = RT.Build(
            FormatRound(round, myName, cd.targetName),
            Theme.fontSize.small,
            Theme.colors.textLight
        )
    end

    -- 最终回合的 HP
    local lastRound = rounds[#rounds]
    local myHP    = lastRound and lastRound.playerHP or 0
    local myHPMax = lastRound and lastRound.playerHPMax or 1
    local eHP     = lastRound and lastRound.enemyHP or 0
    local eHPMax  = lastRound and lastRound.enemyHPMax or 1

    local resultColor = win and Theme.colors.success or Theme.colors.error
    local resultText  = win and "切磋获胜" or "切磋落败"

    local contentWidget = UI.Panel {
        width = "100%", gap = 10,
        children = {
            -- 双方属性对比
            UI.Panel {
                width = "100%", flexDirection = "row",
                justifyContent = "space-around", alignItems = "center",
                children = {
                    -- 我方
                    UI.Panel {
                        alignItems = "center", gap = 2,
                        children = {
                            UI.Label { text = myName, fontSize = Theme.fontSize.body,
                                fontWeight = "bold", fontColor = Theme.colors.textGold },
                            UI.Label { text = "攻:" .. (p.attack or 0) .. " 防:" .. (p.defense or 0),
                                fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                            UI.Label { text = "HP:" .. myHP .. "/" .. myHPMax,
                                fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textLight },
                        },
                    },
                    UI.Label { text = "VS", fontSize = Theme.fontSize.heading,
                        fontWeight = "bold", fontColor = Theme.colors.textSecondary },
                    -- 对手
                    UI.Panel {
                        alignItems = "center", gap = 2,
                        children = {
                            UI.Label { text = cd.targetName, fontSize = Theme.fontSize.body,
                                fontWeight = "bold", fontColor = Theme.colors.textGold },
                            UI.Label { text = "攻:" .. cd.atk .. " 防:" .. cd.def,
                                fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                            UI.Label { text = "HP:" .. eHP .. "/" .. eHPMax,
                                fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textLight },
                        },
                    },
                },
            },
            -- 结果
            UI.Panel {
                width = "100%", alignItems = "center", paddingVertical = 4,
                children = {
                    UI.Label { text = resultText, fontSize = Theme.fontSize.subtitle,
                        fontWeight = "bold", fontColor = resultColor },
                    UI.Label { text = "共 " .. #rounds .. " 回合",
                        fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
                },
            },
            -- 分割线
            UI.Panel { width = "100%", height = 1, backgroundColor = Theme.colors.border },
            -- 战报日志（滚动区域）
            UI.ScrollView {
                width = "100%", maxHeight = 200,
                scrollMultiplier = Theme.scrollSensitivity,
                children = {
                    UI.Panel { width = "100%", gap = 3, children = logChildren },
                },
            },
        },
    }

    local function OnClose()
        -- 上报结算
        GameSocial.SettleChallenge(cd.token, win)
        GameSocial.ClearChallengeData()
        Router.RebuildUI()
    end

    return Comp.Dialog(
        "切磋 - " .. cd.targetName .. " " .. cd.targetRealm,
        contentWidget,
        { { text = "确认", onClick = OnClose, primary = true } },
        { onClose = OnClose }
    )
end

return M
