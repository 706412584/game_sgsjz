-- ============================================================================
-- 《问道长生》服务端组队 Boss 模块
-- 职责：房间管理（创建/加入/离开/准备/踢人/开始/列表）+ 服务端自动战斗
-- 架构：裸远程事件（同宗门/聊天），奖励结算走 GameOps handler_boss
-- ============================================================================

local Shared       = require("network.shared")
local EVENTS       = Shared.EVENTS
local DataWorld    = require("data_world")
local DataFormulas = require("data_formulas")
local GameServer   = require("game_server")
---@diagnostic disable-next-line: undefined-global
local cjson        = cjson

local M = {}

---@type table { connections, connUserIds, userIdToConn, SendToClient }
local deps_ = nil

-- ============================================================================
-- 房间数据结构
-- ============================================================================

---@type table<string, table> roomId -> room
local rooms_ = {}

---@type table<number, string> userId -> roomId（快速反查）
local playerRoom_ = {}

--[[
room = {
    id        = "boss_<timestamp>_<uid>",
    areaId    = "yunwu",
    ownerId   = 12345,
    state     = "waiting" | "fighting" | "ended",
    createdAt = os.time(),
    members   = {
        [userId] = {
            userId = 12345,
            name   = "张三",
            ready  = false,
            tier   = 3,
            -- 战斗时填充的属性
            atk = 0, def = 0, hp = 0, hpMax = 0,
            crit = 0, hit = 0, dodge = 0,
            skillAtkBonus = 0,
            damage  = 0,   -- 本场累计伤害（贡献）
        },
    },
    memberOrder = { userId1, userId2, ... },
    boss = {
        name = "xxx", atk = 0, def = 0, hp = 0, hpMax = 0,
    },
    round       = 0,
    roundTimer  = 0,
    pendingSettle = {},  -- 战斗结束后的结算数据
}
]]

local CFG = nil  -- 延迟初始化

local function GetCFG()
    if not CFG then CFG = DataWorld.GetGroupBossConfig() end
    return CFG
end

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init(deps)
    deps_ = deps
    print("[ServerBoss] 组队 Boss 模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 向指定玩家发送 Boss 事件
local function SendTo(userId, eventName, tbl)
    local data = VariantMap()
    data["Data"] = Variant(cjson.encode(tbl))
    deps_.SendToClient(userId, eventName, data)
end

--- 向房间所有成员广播
local function BroadcastRoom(room, eventName, tbl)
    local data = VariantMap()
    data["Data"] = Variant(cjson.encode(tbl))
    for _, uid in ipairs(room.memberOrder) do
        deps_.SendToClient(uid, eventName, data)
    end
end

--- 构建房间快照（发给客户端）
local function BuildTeamSnapshot(room)
    local members = {}
    for _, uid in ipairs(room.memberOrder) do
        local m = room.members[uid]
        members[#members + 1] = {
            userId = m.userId,
            name   = m.name,
            ready  = m.ready,
            tier   = m.tier,
            isOwner = (uid == room.ownerId),
        }
    end
    return {
        roomId    = room.id,
        areaId    = room.areaId,
        ownerId   = room.ownerId,
        state     = room.state,
        members   = members,
        maxPlayers = GetCFG().maxPlayers,
    }
end

--- 广播房间状态更新
local function BroadcastTeamUpdate(room)
    BroadcastRoom(room, EVENTS.BOSS_TEAM_DATA, {
        action = "team_update",
        team   = BuildTeamSnapshot(room),
    })
end

--- 销毁房间
local function DestroyRoom(roomId)
    local room = rooms_[roomId]
    if not room then return end
    for _, uid in ipairs(room.memberOrder) do
        playerRoom_[uid] = nil
    end
    rooms_[roomId] = nil
    print("[ServerBoss] 房间销毁: " .. roomId)
end

--- 获取玩家数据的 serverCloud key
local function PlayerKey(eventData)
    if eventData then
        local ok, val = pcall(function() return eventData["PlayerKey"]:GetString() end)
        if ok and val and val ~= "" then return val end
    end
    return GameServer.GetServerKey("player")
end

-- ============================================================================
-- 统一入口
-- ============================================================================

function M.HandleBossOp(userId, eventData)
    local actionStr = eventData["Action"]:GetString()
    print("[ServerBoss] HandleBossOp: action=" .. tostring(actionStr) .. " userId=" .. tostring(userId) .. " type=" .. type(userId))

    if actionStr == "create" then
        M.OnCreate(userId, eventData)
    elseif actionStr == "join" then
        M.OnJoin(userId, eventData)
    elseif actionStr == "leave" then
        M.OnLeave(userId)
    elseif actionStr == "ready" then
        M.OnReady(userId)
    elseif actionStr == "start" then
        M.OnStart(userId)
    elseif actionStr == "kick" then
        M.OnKick(userId, eventData)
    elseif actionStr == "list" then
        M.OnListRooms(userId)
    else
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, {
            action = "error", msg = "未知操作: " .. tostring(actionStr),
        })
    end
end

-- ============================================================================
-- create — 创建房间
-- ============================================================================

function M.OnCreate(userId, eventData)
    local areaId = eventData["AreaId"]:GetString()
    if not areaId or areaId == "" then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "请选择区域" })
        return
    end

    -- 验证区域存在 Boss
    local areaEnc = DataWorld.GetAreaEncounters(areaId)
    if not areaEnc or not areaEnc.boss then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "该区域没有 Boss" })
        return
    end

    -- 检查是否已在房间中
    if playerRoom_[userId] then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "你已在一个房间中" })
        return
    end

    -- 读取玩家数据获取名字和境界
    local pKey = PlayerKey(eventData)
    serverCloud:Get(userId, pKey, {
        ok = function(scores)
            local pd = scores and scores[pKey]
            if type(pd) ~= "table" then
                SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "角色数据读取失败" })
                return
            end

            -- 检查区域解锁
            local tier = pd.tier or 1
            local sub  = pd.sub or 1
            local unlocked, reason = DataWorld.IsAreaUnlocked(areaId, tier, sub)
            if not unlocked then
                SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = reason or "区域未解锁" })
                return
            end

            local roomId = "boss_" .. tostring(os.time()) .. "_" .. tostring(userId)
            local room = {
                id          = roomId,
                areaId      = areaId,
                ownerId     = userId,
                playerKey   = pKey,
                state       = "waiting",
                createdAt   = os.time(),
                members     = {},
                memberOrder = {},
                boss        = nil,
                round       = 0,
                roundTimer  = 0,
            }

            room.members[userId] = {
                userId = userId,
                name   = pd.name or "无名",
                ready  = false,
                tier   = tier,
            }
            room.memberOrder[1] = userId

            rooms_[roomId] = room
            playerRoom_[userId] = roomId

            print("[ServerBoss] 房间创建: " .. roomId .. " area=" .. areaId .. " owner=" .. tostring(userId) .. " type=" .. type(userId))
            BroadcastTeamUpdate(room)
        end,
        error = function()
            SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "角色数据读取失败" })
        end,
    })
end

-- ============================================================================
-- join — 加入房间
-- ============================================================================

function M.OnJoin(userId, eventData)
    local roomId = eventData["RoomId"]:GetString()
    local room = rooms_[roomId]
    if not room then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "房间不存在" })
        return
    end
    if room.state ~= "waiting" then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "房间已开战，无法加入" })
        return
    end
    if playerRoom_[userId] then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "你已在一个房间中" })
        return
    end
    if #room.memberOrder >= GetCFG().maxPlayers then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "房间已满" })
        return
    end

    local pKey = PlayerKey(eventData)
    serverCloud:Get(userId, pKey, {
        ok = function(scores)
            local pd = scores and scores[pKey]
            if type(pd) ~= "table" then
                SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "角色数据读取失败" })
                return
            end

            -- 检查区域解锁
            local tier = pd.tier or 1
            local sub  = pd.sub or 1
            local unlocked, reason = DataWorld.IsAreaUnlocked(room.areaId, tier, sub)
            if not unlocked then
                SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = reason or "区域未解锁" })
                return
            end

            room.members[userId] = {
                userId = userId,
                name   = pd.name or "无名",
                ready  = false,
                tier   = tier,
            }
            room.memberOrder[#room.memberOrder + 1] = userId
            playerRoom_[userId] = roomId

            print("[ServerBoss] 加入房间: " .. roomId .. " uid=" .. tostring(userId))
            BroadcastTeamUpdate(room)
        end,
        error = function()
            SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "角色数据读取失败" })
        end,
    })
end

-- ============================================================================
-- leave — 离开房间
-- ============================================================================

function M.OnLeave(userId)
    print("[ServerBoss] OnLeave called: userId=" .. tostring(userId) .. " type=" .. type(userId))
    -- 调试：打印 playerRoom_ 所有 key
    local keys = {}
    for k, v in pairs(playerRoom_) do
        keys[#keys + 1] = "  key=" .. tostring(k) .. "(type=" .. type(k) .. ") -> room=" .. tostring(v)
    end
    if #keys > 0 then
        print("[ServerBoss] playerRoom_ 内容:\n" .. table.concat(keys, "\n"))
    else
        print("[ServerBoss] playerRoom_ 为空（没有任何玩家在房间中）")
    end
    local roomId = playerRoom_[userId]
    print("[ServerBoss] playerRoom_[userId] = " .. tostring(roomId))
    if not roomId then
        -- 静默忽略：玩家可能重复点击离开，或房间已被销毁
        print("[ServerBoss] OnLeave: 玩家不在房间中，静默忽略")
        return
    end
    local room = rooms_[roomId]
    if not room then
        playerRoom_[userId] = nil
        return
    end

    M.RemoveFromRoom(room, userId, "leave")
end

--- 从房间移除玩家（通用）
---@param room table
---@param userId number
---@param reason string "leave"|"kick"|"disconnect"
function M.RemoveFromRoom(room, userId, reason)
    room.members[userId] = nil
    for i, uid in ipairs(room.memberOrder) do
        if uid == userId then
            table.remove(room.memberOrder, i)
            break
        end
    end
    playerRoom_[userId] = nil

    -- 先通知被移除的人（必须在销毁房间前发送）
    if reason == "kick" then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "kicked", msg = "你被踢出了房间" })
    elseif reason == "leave" then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "team_disbanded", msg = "已离开房间" })
    end

    -- 如果房间空了，直接销毁
    if #room.memberOrder == 0 then
        DestroyRoom(room.id)
        return
    end

    -- 如果房主离开了，转移房主
    if room.ownerId == userId then
        room.ownerId = room.memberOrder[1]
        print("[ServerBoss] 房主转移: " .. room.id .. " -> uid=" .. tostring(room.ownerId))
    end

    BroadcastTeamUpdate(room)
end

-- ============================================================================
-- ready — 切换准备状态
-- ============================================================================

function M.OnReady(userId)
    local roomId = playerRoom_[userId]
    if not roomId then return end
    local room = rooms_[roomId]
    if not room or room.state ~= "waiting" then return end

    local m = room.members[userId]
    if not m then return end
    m.ready = not m.ready
    BroadcastTeamUpdate(room)
end

-- ============================================================================
-- kick — 踢出成员（仅房主）
-- ============================================================================

function M.OnKick(userId, eventData)
    local roomId = playerRoom_[userId]
    if not roomId then return end
    local room = rooms_[roomId]
    if not room or room.state ~= "waiting" then return end
    if room.ownerId ~= userId then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "只有房主可以踢人" })
        return
    end

    local targetUid = tonumber(eventData["TargetId"]:GetString()) or 0
    if targetUid == 0 or targetUid == userId then return end
    if not room.members[targetUid] then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "目标不在房间中" })
        return
    end

    M.RemoveFromRoom(room, targetUid, "kick")
end

-- ============================================================================
-- list — 获取房间列表
-- ============================================================================

function M.OnListRooms(userId)
    local list = {}
    for _, room in pairs(rooms_) do
        if room.state == "waiting" then
            local areaConf = DataWorld.GetArea(room.areaId)
            local areaEnc  = DataWorld.GetAreaEncounters(room.areaId)
            list[#list + 1] = {
                roomId     = room.id,
                areaId     = room.areaId,
                areaName   = areaConf and areaConf.name or room.areaId,
                bossName   = areaEnc and areaEnc.boss and areaEnc.boss.name or "未知",
                ownerName  = room.members[room.ownerId] and room.members[room.ownerId].name or "?",
                memberCount = #room.memberOrder,
                maxPlayers  = GetCFG().maxPlayers,
            }
        end
    end
    SendTo(userId, EVENTS.BOSS_TEAM_DATA, {
        action = "room_list",
        rooms  = list,
    })
end

-- ============================================================================
-- start — 开始战斗（仅房主，至少 minPlayers 人且全部准备）
-- ============================================================================

function M.OnStart(userId)
    local roomId = playerRoom_[userId]
    if not roomId then return end
    local room = rooms_[roomId]
    if not room or room.state ~= "waiting" then return end
    if room.ownerId ~= userId then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "只有房主可以开始" })
        return
    end

    local cfg = GetCFG()
    local count = #room.memberOrder
    if count < cfg.minPlayers then
        SendTo(userId, EVENTS.BOSS_TEAM_DATA, {
            action = "error", msg = "至少需要 " .. cfg.minPlayers .. " 人才能开始",
        })
        return
    end

    -- 检查所有非房主成员是否准备（房主默认准备）
    for _, uid in ipairs(room.memberOrder) do
        if uid ~= room.ownerId and not room.members[uid].ready then
            SendTo(userId, EVENTS.BOSS_TEAM_DATA, {
                action = "error", msg = "还有队员未准备",
            })
            return
        end
    end

    -- 加载所有玩家属性，然后生成 Boss 并开战
    M.LoadPlayersAndStartBattle(room)
end

-- ============================================================================
-- 加载玩家属性 + 生成 Boss + 开始战斗
-- ============================================================================

function M.LoadPlayersAndStartBattle(room)
    local pKey     = room.playerKey or PlayerKey()
    local pending  = #room.memberOrder
    local failed   = false

    for _, uid in ipairs(room.memberOrder) do
        serverCloud:Get(uid, pKey, {
            ok = function(scores)
                if failed then return end
                local pd = scores and scores[pKey]
                if type(pd) ~= "table" then
                    failed = true
                    BroadcastRoom(room, EVENTS.BOSS_TEAM_DATA, {
                        action = "error", msg = "加载玩家数据失败",
                    })
                    return
                end

                local m = room.members[uid]
                if not m then
                    pending = pending - 1
                    return
                end

                -- 填充战斗属性（playerData 已含装备加成）
                m.atk    = pd.attack or 30
                m.def    = pd.defense or 10
                m.hpMax  = pd.hpMax or 800
                m.hp     = pd.hpMax or 800
                m.crit   = pd.crit or 5
                m.hit    = pd.hit or 90
                m.dodge  = pd.dodge or 5
                m.tier   = pd.tier or 1
                m.damage = 0

                -- 收集功法攻击加成
                local skillBonus = 0
                for _, sk in ipairs(pd.skills or {}) do
                    if sk.combatEffect and sk.combatEffect.atkBonus then
                        skillBonus = skillBonus + (sk.combatEffect.atkBonus or 0)
                    end
                end
                m.skillAtkBonus = skillBonus

                pending = pending - 1
                if pending == 0 then
                    M.BeginBattle(room)
                end
            end,
            error = function()
                if failed then return end
                failed = true
                BroadcastRoom(room, EVENTS.BOSS_TEAM_DATA, {
                    action = "error", msg = "加载玩家数据失败",
                })
            end,
        })
    end
end

--- 生成 Boss 属性并切换为战斗状态
function M.BeginBattle(room)
    local areaEnc = DataWorld.GetAreaEncounters(room.areaId)
    if not areaEnc or not areaEnc.boss then
        BroadcastRoom(room, EVENTS.BOSS_TEAM_DATA, { action = "error", msg = "Boss 数据异常" })
        return
    end

    local boss    = areaEnc.boss
    local combat  = areaEnc.combat or {}
    local cfg     = GetCFG()
    local count   = #room.memberOrder

    -- 计算区域普通怪平均属性作为基底
    local avgAtk, avgDef, avgHP = 0, 0, 0
    for _, c in ipairs(combat) do
        avgAtk = avgAtk + c.baseAtk
        avgDef = avgDef + c.baseDef
        avgHP  = avgHP  + c.baseHP
    end
    local n = math.max(1, #combat)
    avgAtk = avgAtk / n
    avgDef = avgDef / n
    avgHP  = avgHP  / n

    -- 计算队伍平均境界
    local avgTier = 0
    for _, uid in ipairs(room.memberOrder) do
        avgTier = avgTier + (room.members[uid].tier or 1)
    end
    avgTier = avgTier / count

    -- 单人 Boss 基础属性
    local baseAtk = math.floor(avgAtk * (boss.atkMul or 3) * (1 + avgTier * 0.3))
    local baseDef = math.floor(avgDef * (boss.defMul or 2) * (1 + avgTier * 0.2))
    local baseHP  = math.floor(avgHP  * (boss.hpMul or 10) * (1 + avgTier * 0.5))

    -- 组队缩放：HP 随人数增加，攻防微调
    local groupHP  = math.floor(baseHP * (1 + (count - 1) * cfg.hpScale))
    local groupAtk = math.floor(baseAtk * cfg.atkScale)
    local groupDef = math.floor(baseDef * cfg.defScale)

    room.boss = {
        name  = boss.name,
        atk   = groupAtk,
        def   = groupDef,
        hp    = groupHP,
        hpMax = groupHP,
    }
    room.state      = "fighting"
    room.round      = 0
    room.roundTimer = 0

    print("[ServerBoss] 战斗开始: " .. room.id
        .. " boss=" .. boss.name
        .. " hp=" .. groupHP .. " atk=" .. groupAtk .. " def=" .. groupDef
        .. " players=" .. count)

    -- 广播战斗开始
    BroadcastRoom(room, EVENTS.BOSS_TEAM_DATA, {
        action = "battle_start",
        team   = BuildTeamSnapshot(room),
        boss   = {
            name  = room.boss.name,
            hp    = room.boss.hp,
            hpMax = room.boss.hpMax,
            atk   = room.boss.atk,
            def   = room.boss.def,
        },
    })
end

-- ============================================================================
-- 帧更新 — 驱动回合制战斗
-- ============================================================================

function M.Update(dt)
    for roomId, room in pairs(rooms_) do
        if room.state == "fighting" then
            room.roundTimer = room.roundTimer + dt
            if room.roundTimer >= GetCFG().roundInterval then
                room.roundTimer = room.roundTimer - GetCFG().roundInterval
                M.ExecuteRound(room)
            end
        elseif room.state == "waiting" then
            -- 房间超时检查
            if os.time() - room.createdAt > GetCFG().roomTimeout then
                BroadcastRoom(room, EVENTS.BOSS_TEAM_DATA, {
                    action = "team_disbanded", msg = "房间等待超时，已自动解散",
                })
                DestroyRoom(roomId)
            end
        end
    end
end

-- ============================================================================
-- 执行一回合
-- ============================================================================

function M.ExecuteRound(room)
    local cfg  = GetCFG()
    room.round = room.round + 1

    local roundLog = {
        round   = room.round,
        actions = {},
        bossHP  = room.boss.hp,
    }

    -- 1. 每个存活玩家攻击 Boss
    for _, uid in ipairs(room.memberOrder) do
        local m = room.members[uid]
        if m and m.hp > 0 then
            local result = DataFormulas.ResolveAttack(
                { attack = m.atk, hit = m.hit, crit = m.crit, skillAtkBonus = m.skillAtkBonus },
                { defense = room.boss.def, dodge = 0, hp = room.boss.hp }
            )
            if result.hit then
                room.boss.hp = math.max(0, room.boss.hp - result.damage)
                m.damage = m.damage + result.damage
            end
            roundLog.actions[#roundLog.actions + 1] = {
                type   = "player_atk",
                uid    = uid,
                name   = m.name,
                hit    = result.hit,
                crit   = result.crit,
                damage = result.damage,
                bossHP = room.boss.hp,
            }
        end
    end

    -- 检查 Boss 是否死亡
    if room.boss.hp <= 0 then
        roundLog.bossHP = 0
        BroadcastRoom(room, EVENTS.BOSS_BATTLE_ROUND, roundLog)
        M.OnBattleEnd(room, true)
        return
    end

    -- 2. Boss 攻击（随机选一个存活玩家）
    local alive = {}
    for _, uid in ipairs(room.memberOrder) do
        if room.members[uid] and room.members[uid].hp > 0 then
            alive[#alive + 1] = uid
        end
    end

    if #alive > 0 then
        local targetUid = alive[math.random(#alive)]
        local target = room.members[targetUid]
        local result = DataFormulas.ResolveAttack(
            { attack = room.boss.atk, hit = 95, crit = 10, skillAtkBonus = 0 },
            { defense = target.def, dodge = target.dodge, hp = target.hp }
        )
        if result.hit then
            target.hp = math.max(0, target.hp - result.damage)
        end
        roundLog.actions[#roundLog.actions + 1] = {
            type      = "boss_atk",
            targetUid = targetUid,
            targetName = target.name,
            hit       = result.hit,
            crit      = result.crit,
            damage    = result.damage,
            targetHP  = target.hp,
        }
    end

    roundLog.bossHP = room.boss.hp

    -- 广播回合
    BroadcastRoom(room, EVENTS.BOSS_BATTLE_ROUND, roundLog)

    -- 检查所有玩家是否全灭
    local anyAlive = false
    for _, uid in ipairs(room.memberOrder) do
        if room.members[uid] and room.members[uid].hp > 0 then
            anyAlive = true
            break
        end
    end
    if not anyAlive then
        M.OnBattleEnd(room, false)
        return
    end

    -- 检查回合上限
    if room.round >= cfg.maxRounds then
        M.OnBattleEnd(room, false)
    end
end

-- ============================================================================
-- 战斗结束
-- ============================================================================

function M.OnBattleEnd(room, won)
    room.state = "ended"

    local cfg     = GetCFG()
    local areaIdx = DataWorld.AREA_INDEX[room.areaId] or 1

    -- 构建贡献排名
    local contributions = {}
    local totalDamage   = 0
    for _, uid in ipairs(room.memberOrder) do
        local m = room.members[uid]
        if m then
            totalDamage = totalDamage + m.damage
            contributions[#contributions + 1] = {
                userId = uid,
                name   = m.name,
                damage = m.damage,
                tier   = m.tier,
            }
        end
    end
    -- 按伤害降序
    table.sort(contributions, function(a, b) return a.damage > b.damage end)

    -- 广播战斗结束
    local endData = {
        won           = won,
        bossName      = room.boss.name,
        areaId        = room.areaId,
        totalDamage   = totalDamage,
        contributions = contributions,
        rounds        = room.round,
    }
    BroadcastRoom(room, EVENTS.BOSS_BATTLE_END, endData)

    -- 如果胜利，为每个玩家生成结算令牌（通过 GameOps 结算）
    if won then
        local baseLingShi = cfg.rewardLingShi[areaIdx] or 100
        for _, c in ipairs(contributions) do
            local ratio = (totalDamage > 0) and (c.damage / totalDamage) or (1 / #contributions)
            local reward = math.max(1, math.floor(baseLingShi * ratio))

            -- 生成一次性结算令牌
            local token = tostring(c.userId) .. "_boss_" .. tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
            if not room.pendingSettle then room.pendingSettle = {} end
            room.pendingSettle[c.userId] = {
                token     = token,
                reward    = reward,
                damage    = c.damage,
                ratio     = ratio,
                tier      = c.tier,
                areaId    = room.areaId,
                bossName  = room.boss.name,
                expireAt  = os.time() + 120,
            }

            -- 通知每个玩家领取奖励
            SendTo(c.userId, EVENTS.BOSS_BATTLE_END, {
                action       = "settle_ready",
                settleToken  = token,
                reward       = reward,
                damage       = c.damage,
                ratio        = math.floor(ratio * 100),
            })
        end
    end

    -- 延迟销毁房间（给客户端时间展示结果）
    room.destroyAt = os.time() + 30

    print("[ServerBoss] 战斗结束: " .. room.id
        .. " won=" .. tostring(won)
        .. " rounds=" .. room.round
        .. " totalDmg=" .. totalDamage)
end

-- ============================================================================
-- 结算令牌验证（供 handler_boss 调用）
-- ============================================================================

--- 消费结算令牌
---@param userId number
---@param token string
---@return table|nil settleData
---@return string|nil errMsg
function M.ConsumePendingSettle(userId, token)
    for _, room in pairs(rooms_) do
        local ps = room.pendingSettle and room.pendingSettle[userId]
        if ps and ps.token == token then
            if os.time() > ps.expireAt then
                room.pendingSettle[userId] = nil
                return nil, "结算已过期"
            end
            room.pendingSettle[userId] = nil
            return ps, nil
        end
    end
    return nil, "无效的结算令牌"
end

-- ============================================================================
-- 玩家断线清理
-- ============================================================================

function M.CleanupPlayer(userId)
    local roomId = playerRoom_[userId]
    if not roomId then return end
    local room = rooms_[roomId]
    if not room then
        playerRoom_[userId] = nil
        return
    end

    if room.state == "waiting" then
        M.RemoveFromRoom(room, userId, "disconnect")
    else
        -- 战斗中断线：标记 hp=0，不移除（保留贡献记录）
        local m = room.members[userId]
        if m then m.hp = 0 end
        playerRoom_[userId] = nil
        print("[ServerBoss] 战斗中玩家断线: uid=" .. tostring(userId) .. " room=" .. roomId)
    end
end

return M
