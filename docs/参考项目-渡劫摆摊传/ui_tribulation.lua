-- ============================================================================
-- ui_tribulation.lua — 渡劫天劫 Boss 战 UI
-- 功能10: 渡劫期玩家挑战天劫 Boss，5轮战斗，可攻击/防御
-- ============================================================================
local UI     = require("urhox-libs/UI")
local Config = require("data_config")
local State  = require("data_state")
local HUD    = require("ui_hud")

local M = {}

---@type table|nil  挂载容器（由 main.lua 通过 SetContainer 注入）
local container_  = nil
---@type table|nil  当前 Boss 数据快照
local bossData_   = nil
---@type string     "idle"|"active"|"win"|"fail"
local phase_      = "idle"
---@type table[]    战斗日志列表
local combatLog_  = {}
---@type table|nil  面板根节点
local panel_      = nil
---@type boolean
local visible_    = false
---@type table|nil  当前轮随机事件 {id,name,desc}
local curEvent_   = nil
---@type boolean    豁命一击后标志（下轮boss双倍）
local allinNext_  = false

-- ============================================================ 辅助 ====

local function getBossConfig()
    return Config.TribulationBoss
end

--- 向战斗日志追加条目（最多保留8条）
---@param text string
---@param color table
local function appendLog(text, color)
    table.insert(combatLog_, { text = text, color = color or Config.Colors.textPrimary })
    if #combatLog_ > 8 then table.remove(combatLog_, 1) end
end

-- ============================================================ 渲染组件 ====

--- 渲染 Boss HP 血心
---@param hp number 当前血量
---@param maxHp number 最大血量
local function buildHpRow(hp, maxHp)
    hp = hp or 0
    local hearts = {}
    for i = 1, maxHp do
        local filled = i <= hp
        table.insert(hearts, UI.Panel {
            width = 22, height = 22,
            borderRadius = 11,
            borderWidth = 2,
            borderColor = filled and { 220, 80, 80, 255 } or { 80, 50, 50, 200 },
            backgroundColor = filled and { 200, 50, 50, 220 } or { 40, 20, 20, 180 },
            justifyContent = "center",
            alignItems = "center",
            children = {
                UI.Label {
                    text = filled and "O" or "X",
                    fontSize = 10,
                    fontColor = filled and { 255, 200, 200, 255 } or { 100, 60, 60, 200 },
                    fontWeight = "bold",
                },
            },
        })
    end
    return UI.Panel {
        flexDirection = "row",
        justifyContent = "center",
        alignItems = "center",
        gap = 6,
        width = "100%",
        children = hearts,
    }
end

--- 渲染单条战斗日志
---@param entry table
local function buildLogEntry(entry)
    return UI.Label {
        text = entry.text,
        fontSize = 9,
        fontColor = entry.color,
        width = "100%",
        textAlign = "center",
    }
end

--- 渲染完整面板
local function buildPanel()
    print("[Tribulation] buildPanel() start, phase_=" .. tostring(phase_))
    local boss  = getBossConfig()
    print("[Tribulation] boss=" .. tostring(boss))
    local hp    = State.state.tribulation_hp
    local round = State.state.tribulation_round
    local maxHp = boss and boss.maxHp  or 5
    local maxRd = boss and boss.rounds or 5
    local rdNames = boss and boss.roundNames or {}
    local rdName  = (round and (rdNames[round] or ("第" .. tostring(round) .. "劫"))) or ""
    print("[Tribulation] hp=" .. tostring(hp) .. " round=" .. tostring(round) .. " maxHp=" .. tostring(maxHp))
    local lingshi = State.state.lingshi or 0
    local attackCost = boss and boss.attackCost or 50000
    local canAttack  = lingshi >= attackCost
    local hasArtifact = #(State.state.equippedArtifacts or {}) > 0
    print("[Tribulation] lingshi=" .. tostring(lingshi) .. " canAttack=" .. tostring(canAttack))

    -- 战斗日志区
    local logChildren = {}
    if #combatLog_ == 0 then
        table.insert(logChildren, UI.Label {
            text = "战斗尚未开始...",
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
        })
    else
        for _, entry in ipairs(combatLog_) do
            table.insert(logChildren, buildLogEntry(entry))
        end
    end

    -- 豁命一击费用（用于按钮显示）
    local allInCost = boss and math.floor(boss.attackCost * (boss.allInCostMul or 3)) or 150000
    local canAllIn  = lingshi >= allInCost

    -- 底部按钮区（根据阶段）
    local bottomChildren = {}
    if phase_ == "active" then
        table.insert(bottomChildren, UI.Button {
            text = "攻击 (-" .. HUD.FormatNumber(attackCost) .. ")",
            height = 36,
            flexGrow = 1,
            disabled = not canAttack,
            backgroundColor = canAttack and { 180, 50, 50, 230 } or { 60, 40, 40, 180 },
            textColor = canAttack and { 255, 220, 220, 255 } or Config.Colors.textSecond,
            borderRadius = 8,
            fontSize = 11,
            fontWeight = "bold",
            onClick = function()
                local GameCore = require("game_core")
                GameCore.SendGameAction("tribulation_action", { type = "attack" })
            end,
        })
        table.insert(bottomChildren, UI.Button {
            text = hasArtifact and "防御(法宝)" or "防御(无宝)",
            height = 36,
            flexGrow = 1,
            disabled = not hasArtifact,
            backgroundColor = hasArtifact and { 50, 80, 180, 230 } or { 40, 40, 60, 180 },
            textColor = hasArtifact and { 200, 220, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 8,
            fontSize = 11,
            fontWeight = "bold",
            onClick = function()
                local GameCore = require("game_core")
                GameCore.SendGameAction("tribulation_action", { type = "defend" })
            end,
        })
        table.insert(bottomChildren, UI.Button {
            text = "豁命(-" .. HUD.FormatNumber(allInCost) .. ")",
            height = 36,
            flexGrow = 1,
            disabled = not canAllIn,
            backgroundColor = canAllIn and { 160, 110, 20, 230 } or { 60, 50, 30, 180 },
            textColor = canAllIn and { 255, 240, 160, 255 } or Config.Colors.textSecond,
            borderRadius = 8,
            fontSize = 10,
            fontWeight = "bold",
            onClick = function()
                local GameCore = require("game_core")
                GameCore.SendGameAction("tribulation_action", { type = "all_in" })
            end,
        })
    elseif phase_ == "win" then
        table.insert(bottomChildren, UI.Button {
            text = "飞升仙界",
            height = 40,
            flexGrow = 1,
            backgroundColor = { 180, 140, 40, 230 },
            textColor = { 255, 240, 180, 255 },
            borderRadius = 8,
            fontSize = 14,
            fontWeight = "bold",
            onClick = function()
                local GameCore = require("game_core")
                GameCore.SendGameAction("ascend")
            end,
        })
        table.insert(bottomChildren, UI.Button {
            text = "关闭",
            height = 40,
            width = 80,
            backgroundColor = { 60, 60, 70, 200 },
            textColor = Config.Colors.textSecond,
            borderRadius = 8,
            fontSize = 11,
            onClick = function() M.Hide() end,
        })
    elseif phase_ == "fail" then
        table.insert(bottomChildren, UI.Button {
            text = "关闭",
            height = 40,
            flexGrow = 1,
            backgroundColor = { 60, 60, 70, 200 },
            textColor = Config.Colors.textPrimary,
            borderRadius = 8,
            fontSize = 11,
            onClick = function() M.Hide() end,
        })
    else -- idle
        table.insert(bottomChildren, UI.Button {
            text = "挑战天劫",
            height = 40,
            flexGrow = 1,
            backgroundColor = { 120, 50, 180, 230 },
            textColor = { 240, 210, 255, 255 },
            borderRadius = 8,
            fontSize = 13,
            fontWeight = "bold",
            onClick = function()
                local GameCore = require("game_core")
                GameCore.SendGameAction("tribulation_start")
            end,
        })
        table.insert(bottomChildren, UI.Button {
            text = "关闭",
            height = 40,
            width = 80,
            backgroundColor = { 60, 60, 70, 200 },
            textColor = Config.Colors.textSecond,
            borderRadius = 8,
            fontSize = 11,
            onClick = function() M.Hide() end,
        })
    end

    -- 主面板
    print("[Tribulation] buildPanel() building outer panel...")
    local outerPanel = UI.Panel {
        position = "absolute",
        left = 0, top = 0, right = 0, bottom = 0,
        zIndex = 100,
        justifyContent = "center",
        alignItems = "center",
        backgroundColor = { 0, 0, 0, 180 },
        children = {
            UI.Panel {
                width = 320,
                backgroundColor = { 15, 10, 25, 245 },
                borderRadius = 12,
                borderWidth = 2,
                borderColor = { 140, 80, 200, 200 },
                padding = 14,
                gap = 10,
                children = {
                    -- 标题
                    UI.Label {
                        text = phase_ == "win"  and "天劫已破！" or
                               phase_ == "fail" and "渡劫失败" or
                               "挑战天劫",
                        fontSize = 16,
                        fontColor = phase_ == "win"  and Config.Colors.textGold or
                                    phase_ == "fail" and Config.Colors.red or
                                    { 200, 160, 255, 255 },
                        fontWeight = "bold",
                        textAlign = "center",
                        width = "100%",
                    },
                    -- 轮次信息（active/win/fail 时显示）
                    phase_ ~= "idle" and UI.Label {
                        text = phase_ == "active" and (rdName .. " (" .. round .. "/" .. maxRd .. ")")
                            or (phase_ == "win" and "成功通过全部天劫！" or "天劫已至末路"),
                        fontSize = 10,
                        fontColor = Config.Colors.textSecond,
                        textAlign = "center",
                        width = "100%",
                    } or UI.Label {
                        text = "渡劫期修炼者方可挑战",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                        textAlign = "center",
                        width = "100%",
                    },
                    -- Boss HP 血心
                    buildHpRow(hp, maxHp),
                    -- 随机事件横幅（active 时展示）
                    (phase_ == "active" and curEvent_) and UI.Panel {
                        width = "100%",
                        backgroundColor = { 80, 50, 10, 220 },
                        borderRadius = 6,
                        borderWidth = 1,
                        borderColor = { 200, 160, 60, 200 },
                        padding = 6,
                        gap = 2,
                        children = {
                            UI.Label {
                                text = "天劫异象: " .. curEvent_.name,
                                fontSize = 10,
                                fontColor = { 255, 220, 100, 255 },
                                fontWeight = "bold",
                                textAlign = "center",
                                width = "100%",
                            },
                            UI.Label {
                                text = curEvent_.desc,
                                fontSize = 8,
                                fontColor = { 220, 180, 80, 220 },
                                textAlign = "center",
                                width = "100%",
                            },
                        },
                    } or UI.Panel { height = 0 },
                    -- 豁命一击惩罚警告
                    (phase_ == "active" and allinNext_) and UI.Label {
                        text = "警告：下轮天劫反击双倍！",
                        fontSize = 9,
                        fontColor = { 255, 80, 80, 255 },
                        fontWeight = "bold",
                        textAlign = "center",
                        width = "100%",
                    } or UI.Panel { height = 0 },
                    -- 分割线
                    UI.Panel { height = 1, width = "100%", backgroundColor = { 80, 60, 120, 150 } },
                    -- 战斗日志
                    UI.Panel {
                        width = "100%",
                        minHeight = 80,
                        backgroundColor = { 10, 8, 18, 200 },
                        borderRadius = 6,
                        padding = 8,
                        gap = 3,
                        children = logChildren,
                    },
                    -- 玩家灵石
                    UI.Panel {
                        flexDirection = "row",
                        justifyContent = "center",
                        alignItems = "center",
                        gap = 6,
                        children = {
                            UI.Label { text = "灵石:", fontSize = 10, fontColor = Config.Colors.textSecond },
                            UI.Label {
                                text = HUD.FormatNumber(lingshi),
                                fontSize = 11,
                                fontColor = Config.Colors.textGold,
                                fontWeight = "bold",
                            },
                            phase_ == "active" and UI.Label {
                                text = "(攻击费 " .. HUD.FormatNumber(attackCost) .. ")",
                                fontSize = 8,
                                fontColor = Config.Colors.textSecond,
                            } or UI.Label { text = "", fontSize = 8 },
                        },
                    },
                    -- 操作按钮区
                    UI.Panel {
                        flexDirection = "row",
                        width = "100%",
                        gap = 8,
                        children = bottomChildren,
                    },
                },
            },
        },
    }
    print("[Tribulation] buildPanel() outerPanel=" .. tostring(outerPanel))
    return outerPanel
end

-- ============================================================ 公开 API ====

--- 重建并挂载面板
local function rebuild()
    print("[Tribulation] rebuild() visible_=" .. tostring(visible_) .. " container_=" .. tostring(container_))
    if not visible_ then return end
    if not container_ then
        print("[Tribulation] rebuild() ERROR: container_ is nil, call SetContainer first")
        return
    end
    if panel_ then
        UI.PopOverlay(panel_)
        container_:RemoveChild(panel_)
        panel_ = nil
    end
    local ok, err = pcall(function()
        panel_ = buildPanel()
    end)
    if not ok then
        print("[Tribulation] rebuild() buildPanel ERROR: " .. tostring(err))
        return
    end
    print("[Tribulation] rebuild() panel_=" .. tostring(panel_))
    container_:AddChild(panel_)
    UI.PushOverlay(panel_)
    print("[Tribulation] rebuild() done, AddChild+PushOverlay called")
end

--- 显示 Boss 战 UI
function M.Show()
    visible_ = true
    -- 判断当前阶段
    print("[Tribulation] M.Show() ascended=" .. tostring(State.state.ascended)
        .. " tribulation_won=" .. tostring(State.state.tribulation_won)
        .. " tribulation_active=" .. tostring(State.state.tribulation_active))
    if State.state.ascended then
        visible_ = false
        print("[Tribulation] M.Show() already ascended, abort")
        return
    end
    if State.state.tribulation_won and not State.state.tribulation_active then
        phase_ = "win"
    elseif State.state.tribulation_active then
        phase_ = "active"
    else
        phase_ = "idle"
        combatLog_ = {}
        curEvent_  = nil
        allinNext_ = false
    end
    print("[Tribulation] M.Show() phase_=" .. tostring(phase_))
    rebuild()
end

--- 设置挂载容器（main.lua 初始化时调用）
function M.SetContainer(container)
    container_ = container
end

--- 隐藏 Boss 战 UI
function M.Hide()
    visible_ = false
    if container_ and panel_ then
        UI.PopOverlay(panel_)
        container_:RemoveChild(panel_)
        panel_ = nil
    end
    -- 通知 upgrade panel 刷新按钮状态
    State.Emit("tribulation_panel_closed")
end

--- 是否正在显示
---@return boolean
function M.IsVisible()
    return visible_
end

-- ============================================================ 事件监听 ====

--- 初始化（在 main.lua 中调用一次）
function M.Init()
    -- 解析服务端 log 条目追加到战斗日志
    local function applyLog(log)
        for _, entry in ipairs(log or {}) do
            if entry.type == "boss_heal" then
                appendLog("天劫蓄力回复 " .. (entry.heal or 1) .. " 点血量！", { 180, 80, 200, 255 })
            elseif entry.type == "attack" then
                local tag = entry.isHeavy and "[重击]" or ""
                appendLog("你发动攻击" .. tag .. "！天劫受创 " .. (entry.dmg or 0) .. " 点", Config.Colors.red)
            elseif entry.type == "all_in" then
                appendLog("豁命一击！天劫受创 " .. (entry.dmg or 0) .. " 点", { 255, 200, 60, 255 })
            elseif entry.type == "defend" then
                appendLog("举法宝防御！天劫伤害减半", { 100, 160, 255, 255 })
            elseif entry.type == "boss_skip" then
                appendLog("天地归寂——天劫未能反击！", { 160, 220, 160, 255 })
            elseif entry.type == "boss_heavy" then
                appendLog("天劫怒击！灵石损失 " .. (entry.dmg or 0) .. " 倍", { 255, 120, 60, 255 })
            elseif entry.type == "boss_normal" then
                appendLog("天劫反击，灵石损失 " .. (entry.dmg or 0) .. " 倍", { 220, 120, 50, 255 })
            elseif entry.type == "boss_attack" then
                appendLog("损失灵石 -" .. HUD.FormatNumber(entry.lingshiLoss or 0), { 200, 100, 60, 255 })
            end
        end
    end

    -- Boss战启动：服务端返回当前状态
    State.On("tribulation_state_changed", function(data)
        phase_     = "active"
        bossData_  = data
        curEvent_  = data.curEvent
        allinNext_ = false
        local rdName = (data.roundNames and data.roundNames[data.round or 1]) or "初劫"
        appendLog("天劫启动！" .. rdName .. " 开始", { 200, 160, 255, 255 })
        if curEvent_ then
            appendLog("天劫异象: " .. curEvent_.name .. " — " .. curEvent_.desc, { 255, 200, 80, 255 })
        end
        rebuild()
    end)

    -- 每轮结算
    State.On("tribulation_round_ended", function(data)
        phase_     = "active"
        curEvent_  = data.nextEvent
        allinNext_ = data.allinNext or false
        applyLog(data.log)
        local rdName = (data.roundNames and data.roundNames[data.round]) or ("第" .. (data.round or "?") .. "劫")
        appendLog("进入" .. rdName .. "...", Config.Colors.purple)
        if curEvent_ then
            appendLog("天劫异象: " .. curEvent_.name .. " — " .. curEvent_.desc, { 255, 200, 80, 255 })
        end
        if allinNext_ then
            appendLog("豁命余威未散，天劫将双倍反击！", { 255, 80, 80, 255 })
        end
        rebuild()
    end)

    -- Boss 击败（胜利）
    State.On("tribulation_win", function(data)
        phase_     = "win"
        curEvent_  = nil
        allinNext_ = false
        applyLog(data.log)
        appendLog("天劫已破！渡劫成功！", Config.Colors.textGold)
        rebuild()
    end)

    -- Boss 战失败
    State.On("tribulation_fail", function(data)
        phase_     = "fail"
        curEvent_  = nil
        allinNext_ = false
        applyLog(data.log)
        if data.penalty and data.penalty > 0 then
            appendLog("渡劫失败！罚没灵石 -" .. HUD.FormatNumber(data.penalty), Config.Colors.red)
        else
            appendLog("渡劫失败！", Config.Colors.red)
        end
        rebuild()
    end)

    -- 飞升成功后自动关闭
    State.On("ascended", function()
        visible_ = false
        local root = UI.GetRoot()
        if root and panel_ then
            root:RemoveChild(panel_)
            panel_ = nil
        end
        State.Emit("upgrade_panel_refresh")
    end)

    -- action_fail 时刷新（灵石不足等）
    State.On("action_fail_received", function(data)
        if visible_ then
            appendLog("操作失败: " .. (data.msg or "未知错误"), Config.Colors.red)
            rebuild()
        end
    end)
end

return M
