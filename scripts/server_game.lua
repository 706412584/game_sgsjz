------------------------------------------------------------
-- server_game.lua — 三国神将录 服务端游戏逻辑
-- 职责：玩家数据加载/保存、GAME_ACTION 处理、状态同步
-- 由 server_main.lua require 并调用
------------------------------------------------------------

---@diagnostic disable: undefined-global

local State   = require("data.data_state")
local Battle  = require("data.battle_engine")
local Shared  = require("network.shared")
local EVENTS  = Shared.EVENTS

local M = {}

------------------------------------------------------------
-- 内部状态
------------------------------------------------------------

---@type table<number, table>    userId -> state
local players_     = {}
---@type table<number, boolean>  userId -> dirty
local dirty_       = {}
---@type table<number, number>   userId -> saveTimer (秒)
local saveTimers_  = {}
---@type table<number, number>   userId -> serverId
local serverId_    = {}

local SAVE_INTERVAL = 30  -- 脏数据周期保存（秒）

--- server_main 注入的回调
---@type fun(userId: number, eventName: string, data: VariantMap)
local SendToClient_ = nil

------------------------------------------------------------
-- 区服 key 工具
------------------------------------------------------------

--- 生成带区服后缀的存储 key
---@param baseKey string
---@param sid number|nil
---@return string
local function realmKey(baseKey, sid)
    if not sid or sid == 0 then return baseKey end
    return baseKey .. "_" .. tostring(sid)
end

------------------------------------------------------------
-- 公开接口 (server_main 调用)
------------------------------------------------------------

--- 初始化
---@param deps table { SendToClient: fun }
function M.Init(deps)
    SendToClient_ = deps.SendToClient
    print("[ServerGame] 初始化完成")
end

--- 每帧更新: 周期保存脏数据
---@param dt number
function M.Update(dt)
    for userId, _ in pairs(players_) do
        saveTimers_[userId] = (saveTimers_[userId] or 0) + dt
        if saveTimers_[userId] >= SAVE_INTERVAL and dirty_[userId] then
            saveTimers_[userId] = 0
            M.SavePlayer(userId)
        end
    end
end

--- 关服时保存所有在线玩家
function M.SaveAll()
    for userId, _ in pairs(players_) do
        if dirty_[userId] then
            M.SavePlayer(userId)
        end
    end
    print("[ServerGame] SaveAll 完成")
end

--- 玩家是否已加载
---@param userId number
---@return boolean
function M.IsLoaded(userId)
    return players_[userId] ~= nil
end

------------------------------------------------------------
-- 加载 / 保存
------------------------------------------------------------

--- 从 serverCloud 加载玩家数据
---@param userId number
---@param serverId number
---@param callback fun(success: boolean)
function M.LoadPlayer(userId, serverId, callback)
    serverId_[userId] = serverId

    if not serverCloud then
        -- 无云服务: 使用默认状态
        local state = State.CreateDefaultState()
        players_[userId] = state
        dirty_[userId]   = false
        saveTimers_[userId] = 0
        print("[ServerGame] 无 serverCloud, 使用默认状态 uid=" .. tostring(userId))
        callback(true)
        return
    end

    local sid = serverId
    local saveKey  = realmKey("save", sid)
    local powerKey = realmKey("power", sid)
    local stageKey = realmKey("stage", sid)

    serverCloud:BatchGet(userId)
        :Key(saveKey)
        :Key(powerKey)
        :Key(stageKey)
        :Fetch({
            ok = function(scores, iscores)
                scores  = scores  or {}
                iscores = iscores or {}

                local state = nil
                local raw = scores[saveKey]
                if raw and raw ~= "" then
                    local decOk, decoded = pcall(cjson.decode, raw)
                    if decOk and type(decoded) == "table" then
                        state = decoded
                    end
                end

                if not state then
                    -- 新玩家
                    state = State.CreateDefaultState()
                    print("[ServerGame] 新玩家, 创建默认状态 uid=" .. tostring(userId))
                else
                    print("[ServerGame] 加载存档成功 uid=" .. tostring(userId)
                        .. " power=" .. tostring(state.power))
                end

                -- 补丁兼容旧存档
                state.inventory = state.inventory or {}
                state.inventory.exp_wine = state.inventory.exp_wine or 0
                state.inventory.star_stone = state.inventory.star_stone or 0
                state.inventory.breakthrough = state.inventory.breakthrough or 0
                state.inventory.awaken_stone = state.inventory.awaken_stone or 0
                state.recruitPool = state.recruitPool or {}
                state.lastStaminaTime = state.lastStaminaTime or 0
                state.nodeStars = state.nodeStars or {}
                state.clearedMaps = state.clearedMaps or {}
                state.jianghun = state.jianghun or 0
                state.zhaomuling = state.zhaomuling or 0
                state.lineup = state.lineup or {
                    formation = "feng_shi", front = {}, back = {}
                }
                for _, h in pairs(state.heroes or {}) do
                    if h.star == nil then h.star = 1 end
                    if h.fragments == nil then h.fragments = 0 end
                end

                players_[userId]    = state
                dirty_[userId]      = false
                saveTimers_[userId]  = 0
                callback(true)
            end,
            error = function(code, reason)
                print("[ServerGame] 加载失败 uid=" .. tostring(userId)
                    .. " reason=" .. tostring(reason))
                callback(false)
            end,
        })
end

--- 保存玩家数据到 serverCloud
---@param userId number
---@param callback? fun()
function M.SavePlayer(userId, callback)
    local state = players_[userId]
    if not state then
        if callback then callback() end
        return
    end

    if not serverCloud then
        dirty_[userId] = false
        if callback then callback() end
        return
    end

    state.lastSaveTime = os.time()

    local sid = serverId_[userId] or 0
    local saveKey  = realmKey("save", sid)
    local powerKey = realmKey("power", sid)
    local stageKey = realmKey("stage", sid)

    local jsonStr = cjson.encode(state)

    -- 计算最远关卡编号: mapId * 100 + clearedNodes
    local stageValue = (state.currentMap or 1) * 100
    for nodeId = 1, 24 do
        local key = tostring(state.currentMap) .. "_" .. tostring(nodeId)
        if state.nodeStars[key] and state.nodeStars[key] > 0 then
            stageValue = stageValue + 1
        end
    end

    serverCloud:BatchSet(userId)
        :Set(saveKey, jsonStr)
        :SetInt(powerKey, math.floor(state.power or 0))
        :SetInt(stageKey, stageValue)
        :Save("server_save", {
            ok = function()
                dirty_[userId] = false
                print("[ServerGame] 保存成功 uid=" .. tostring(userId)
                    .. " size=" .. #jsonStr .. "B")
                if callback then callback() end
            end,
            error = function(code, reason)
                print("[ServerGame] 保存失败 uid=" .. tostring(userId)
                    .. " " .. tostring(reason))
                if callback then callback() end
            end,
        })
end

--- 向客户端推送 GAME_INIT (完整状态)
---@param userId number
function M.SendGameInit(userId)
    local state = players_[userId]
    if not state or not SendToClient_ then return end
    local data = VariantMap()
    data["StateJson"] = Variant(cjson.encode(state))
    SendToClient_(userId, EVENTS.GAME_INIT, data)
    print("[ServerGame] SendGameInit uid=" .. tostring(userId))
end

--- 向客户端推送 GAME_SYNC (同步变更后状态)
---@param userId number
local function sendSync(userId)
    local state = players_[userId]
    if not state or not SendToClient_ then return end
    local data = VariantMap()
    data["StateJson"] = Variant(cjson.encode(state))
    SendToClient_(userId, EVENTS.GAME_SYNC, data)
end

--- 向客户端推送 GAME_EVT (即时事件)
---@param userId number
---@param evtType string
---@param evtData table|nil
local function sendEvt(userId, evtType, evtData)
    if not SendToClient_ then return end
    local data = VariantMap()
    data["Type"]     = Variant(evtType)
    data["DataJson"] = Variant(cjson.encode(evtData or {}))
    SendToClient_(userId, EVENTS.GAME_EVT, data)
end

------------------------------------------------------------
-- 玩家断线 / 强制移除
------------------------------------------------------------

--- 玩家断线: 保存并移除
---@param userId number
function M.OnPlayerDisconnect(userId)
    if not players_[userId] then return end
    if dirty_[userId] then
        M.SavePlayer(userId, function()
            players_[userId]    = nil
            dirty_[userId]      = nil
            saveTimers_[userId]  = nil
            serverId_[userId]    = nil
            print("[ServerGame] 断线保存并移除 uid=" .. tostring(userId))
        end)
    else
        players_[userId]    = nil
        dirty_[userId]      = nil
        saveTimers_[userId]  = nil
        serverId_[userId]    = nil
        print("[ServerGame] 断线移除 uid=" .. tostring(userId))
    end
end

--- 强制移除(不保存, 用于身份升级丢弃临时数据)
---@param userId number
function M.ForceRemovePlayer(userId)
    if not players_[userId] then return end
    players_[userId]    = nil
    dirty_[userId]      = nil
    saveTimers_[userId]  = nil
    -- 不清 serverId_，换服流程可能需要
    print("[ServerGame] 强制移除(不保存) uid=" .. tostring(userId))
end

------------------------------------------------------------
-- GAME_ACTION 处理
------------------------------------------------------------

--- Action 路由表
---@type table<string, fun(userId: number, params: table)>
local ACTION_HANDLERS = {}

--- 主入口: 分发 action
---@param userId number
---@param action string
---@param dataJson string
function M.HandleAction(userId, action, dataJson)
    local state = players_[userId]
    if not state then
        print("[ServerGame] HandleAction: 玩家未加载 uid=" .. tostring(userId))
        return
    end

    local params = {}
    if dataJson and dataJson ~= "" then
        local ok, decoded = pcall(cjson.decode, dataJson)
        if ok and type(decoded) == "table" then
            params = decoded
        end
    end

    local handler = ACTION_HANDLERS[action]
    if handler then
        handler(userId, params)
    else
        print("[ServerGame] 未知 action: " .. tostring(action))
    end
end

------------------------------------------------------------
-- Action 实现
------------------------------------------------------------

--- game_start: 进入游戏（体力恢复等）
ACTION_HANDLERS["game_start"] = function(userId, params)
    local state = players_[userId]
    State.UpdateStamina(state)
    dirty_[userId] = true
    sendSync(userId)
end

--- battle: 发起战斗
ACTION_HANDLERS["battle"] = function(userId, params)
    local state = players_[userId]
    local mapId    = params.mapId or 1
    local nodeId   = params.nodeId or 1
    local nodeType = params.nodeType or "normal"

    -- 体力检查
    State.UpdateStamina(state)
    local staminaCost = 6
    if state.stamina < staminaCost then
        sendEvt(userId, "error", { msg = "体力不足" })
        return
    end
    state.stamina = state.stamina - staminaCost

    -- 执行战斗
    local battleLog = Battle.QuickBattle(state, mapId, nodeId, nodeType)

    -- 应用奖励
    local rewards = {}
    if battleLog.result and battleLog.result.win then
        rewards = State.ApplyBattleRewards(state, battleLog)
    end

    dirty_[userId] = true

    -- 推送战斗结果事件
    sendEvt(userId, "battle_result", {
        win         = battleLog.result.win,
        stars       = battleLog.result.stars,
        rounds      = battleLog.rounds,
        totalRounds = battleLog.totalRounds,
        damageStats = battleLog.result.damageStats,
        healStats   = battleLog.result.healStats,
        allyAlive   = battleLog.result.allyAlive,
        enemyAlive  = battleLog.result.enemyAlive,
        drops       = battleLog.result.drops,
        rewards     = rewards,
        mapId       = mapId,
        nodeId      = nodeId,
    })

    -- 同步最新状态
    sendSync(userId)
end

--- use_exp_wine: 使用经验酒
ACTION_HANDLERS["use_exp_wine"] = function(userId, params)
    local state = players_[userId]
    local heroId = params.heroId
    local count  = params.count or 1
    if not heroId then
        sendEvt(userId, "error", { msg = "缺少 heroId" })
        return
    end

    local ok, msg = State.UseExpWine(state, heroId, count)
    dirty_[userId] = true

    sendEvt(userId, "action_result", {
        action  = "use_exp_wine",
        success = ok,
        msg     = msg,
    })
    sendSync(userId)
end

--- star_up: 英雄升星
ACTION_HANDLERS["star_up"] = function(userId, params)
    local state = players_[userId]
    local heroId = params.heroId
    if not heroId then
        sendEvt(userId, "error", { msg = "缺少 heroId" })
        return
    end

    local ok, msg = State.StarUp(state, heroId)
    dirty_[userId] = true

    sendEvt(userId, "action_result", {
        action  = "star_up",
        success = ok,
        msg     = msg,
    })
    sendSync(userId)
end

--- recruit: 招募
ACTION_HANDLERS["recruit"] = function(userId, params)
    local state = players_[userId]
    local ok, heroId, info = State.DoRecruit(state)
    dirty_[userId] = true

    sendEvt(userId, "recruit_result", {
        success = ok,
        heroId  = heroId,
        info    = info,
    })
    sendSync(userId)
end

--- compose_hero: 碎片合成
ACTION_HANDLERS["compose_hero"] = function(userId, params)
    local state = players_[userId]
    local heroId = params.heroId
    if not heroId then
        sendEvt(userId, "error", { msg = "缺少 heroId" })
        return
    end

    local ok, msg = State.ComposeHero(state, heroId)
    dirty_[userId] = true

    sendEvt(userId, "action_result", {
        action  = "compose_hero",
        success = ok,
        msg     = msg,
    })
    sendSync(userId)
end

--- set_lineup: 设置阵容
ACTION_HANDLERS["set_lineup"] = function(userId, params)
    local state = players_[userId]

    -- 验证阵容有效性
    local front = params.front or {}
    local back  = params.back or {}
    if #front > 2 or #back > 3 then
        sendEvt(userId, "error", { msg = "阵容人数超限" })
        return
    end

    -- 验证英雄存在且已激活（level > 0）
    local allIds = {}
    for _, hid in ipairs(front) do
        if not state.heroes[hid] or state.heroes[hid].level <= 0 then
            sendEvt(userId, "error", { msg = "英雄不可用: " .. tostring(hid) })
            return
        end
        if allIds[hid] then
            sendEvt(userId, "error", { msg = "英雄重复: " .. tostring(hid) })
            return
        end
        allIds[hid] = true
    end
    for _, hid in ipairs(back) do
        if not state.heroes[hid] or state.heroes[hid].level <= 0 then
            sendEvt(userId, "error", { msg = "英雄不可用: " .. tostring(hid) })
            return
        end
        if allIds[hid] then
            sendEvt(userId, "error", { msg = "英雄重复: " .. tostring(hid) })
            return
        end
        allIds[hid] = true
    end

    state.lineup.formation = params.formation or state.lineup.formation
    state.lineup.front = front
    state.lineup.back  = back

    -- 重算战力
    State.RecalcPower(state)
    dirty_[userId] = true

    sendEvt(userId, "action_result", {
        action  = "set_lineup",
        success = true,
        msg     = "阵容已更新",
    })
    sendSync(userId)
end

return M
