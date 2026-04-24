-- ============================================================================
-- 《问道长生》组队 Boss 客户端状态缓存
-- 职责：缓存房间/战斗数据、提供发送操作的 API、管理回调
-- 设计：纯数据层，不依赖 UI
-- ============================================================================

local Shared    = require("network.shared")
local EVENTS    = Shared.EVENTS
local ClientNet = require("network.client_net")
local GameOps   = require("network.game_ops")
local GameServer = require("game_server")
---@diagnostic disable-next-line: undefined-global
local cjson     = cjson

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

---@type table|nil 当前房间快照 { roomId, areaId, ownerId, state, members, maxPlayers }
local teamData_ = nil

---@type table|nil 当前 Boss 状态 { name, hp, hpMax, atk, def }
local bossData_ = nil

---@type table[] 战斗回合日志（按顺序追加）
local roundLogs_ = {}

---@type table|nil 战斗结果 { won, bossName, areaId, totalDamage, contributions, rounds }
local battleResult_ = nil

---@type table|nil 结算令牌 { settleToken, reward, damage, ratio }
local settleInfo_ = nil

---@type boolean 是否正在结算中
local settling_ = false

---@type table[] 房间列表缓存
local roomList_ = {}

-- ============================================================================
-- 回调注册（UI 层可注册/注销）
-- ============================================================================

---@type table<string, fun(...)> 事件回调
local callbacks_ = {}

--- 注册回调
---@param event string  "team_update"|"battle_start"|"battle_round"|"battle_end"|"settle_ready"|"settle_done"|"room_list"|"error"|"kicked"|"disbanded"
---@param fn fun(...)
function M.On(event, fn)
    callbacks_[event] = fn
end

--- 注销回调
---@param event string
function M.Off(event)
    callbacks_[event] = nil
end

--- 注销全部回调
function M.OffAll()
    callbacks_ = {}
end

local function Fire(event, ...)
    local fn = callbacks_[event]
    if fn then fn(...) end
end

-- ============================================================================
-- 查询接口
-- ============================================================================

function M.GetTeam()       return teamData_     end
function M.GetBoss()       return bossData_     end
function M.GetRoundLogs()  return roundLogs_    end
function M.GetBattleResult() return battleResult_ end
function M.GetSettleInfo() return settleInfo_   end
function M.GetRoomList()   return roomList_     end
function M.IsSettling()    return settling_     end

--- 是否在房间中
function M.InRoom()
    return teamData_ ~= nil
end

--- 是否在战斗中
function M.InBattle()
    return teamData_ ~= nil and teamData_.state == "fighting"
end

--- 是否是房主
function M.IsOwner()
    if not teamData_ then return false end
    local uid = ClientNet.GetUserId()
    return teamData_.ownerId == uid
end

-- ============================================================================
-- 操作 API（发送到服务端）
-- ============================================================================

local function SendBossOp(action, extra)
    local vm = VariantMap()
    vm["Action"] = Variant(action)
    vm["PlayerKey"] = Variant(GameServer.GetServerKey("player"))
    if extra then
        for k, v in pairs(extra) do
            vm[k] = Variant(v)
        end
    end
    ClientNet.SendToServer(EVENTS.REQ_BOSS_OP, vm)
end

--- 创建房间
---@param areaId string
function M.Create(areaId)
    SendBossOp("create", { AreaId = areaId })
end

--- 加入房间
---@param roomId string
function M.Join(roomId)
    SendBossOp("join", { RoomId = roomId })
end

--- 离开房间
function M.Leave()
    SendBossOp("leave")
end

--- 切换准备状态
function M.Ready()
    SendBossOp("ready")
end

--- 开始战斗（房主）
function M.Start()
    SendBossOp("start")
end

--- 踢人（房主）
---@param targetId number
function M.Kick(targetId)
    SendBossOp("kick", { TargetId = tostring(targetId) })
end

--- 获取房间列表
function M.ListRooms()
    SendBossOp("list")
end

-- ============================================================================
-- 奖励结算（走 GameOps）
-- ============================================================================

--- 提交结算令牌领取奖励
---@param callback? fun(ok: boolean, data: table)
function M.Settle(callback)
    if not settleInfo_ or settling_ then return end
    settling_ = true

    local pKey = GameServer.GetServerKey("player")
    GameOps.Request("boss_settle", {
        settleToken = settleInfo_.settleToken,
        playerKey   = pKey,
    }, function(ok, data, sync)
        settling_ = false
        settleInfo_ = nil  -- 已消费
        Fire("settle_done", ok, data)
        if callback then callback(ok, data) end
    end, { loading = "结算中..." })
end

-- ============================================================================
-- 网络事件处理（由 client_net 调用）
-- ============================================================================

--- 处理 BOSS_TEAM_DATA 事件
---@param tbl table 反序列化后的数据
function M.OnTeamData(tbl)
    local action = tbl.action
    print("[GameBoss] OnTeamData: action=" .. tostring(action) .. " msg=" .. tostring(tbl.msg))

    if action == "team_update" then
        teamData_ = tbl.team
        Fire("team_update", teamData_)

    elseif action == "battle_start" then
        teamData_ = tbl.team
        bossData_ = tbl.boss
        roundLogs_ = {}
        battleResult_ = nil
        settleInfo_ = nil
        Fire("battle_start", teamData_, bossData_)

    elseif action == "room_list" then
        roomList_ = tbl.rooms or {}
        Fire("room_list", roomList_)

    elseif action == "error" then
        Fire("error", tbl.msg or "操作失败")

    elseif action == "kicked" then
        teamData_ = nil
        bossData_ = nil
        roundLogs_ = {}
        battleResult_ = nil
        settleInfo_ = nil
        Fire("kicked", tbl.msg or "你被踢出了房间")

    elseif action == "team_disbanded" then
        teamData_ = nil
        bossData_ = nil
        roundLogs_ = {}
        battleResult_ = nil
        settleInfo_ = nil
        Fire("disbanded", tbl.msg or "房间已解散")
    end
end

--- 处理 BOSS_BATTLE_ROUND 事件
---@param tbl table
function M.OnBattleRound(tbl)
    roundLogs_[#roundLogs_ + 1] = tbl
    -- 更新 Boss HP
    if bossData_ and tbl.bossHP then
        bossData_.hp = tbl.bossHP
    end
    -- 更新队友 HP
    if teamData_ and tbl.actions then
        for _, act in ipairs(tbl.actions) do
            if act.type == "boss_atk" and act.targetHP and teamData_.members then
                for _, m in ipairs(teamData_.members) do
                    if m.userId == act.uid then
                        m.hp = act.targetHP
                        break
                    end
                end
            end
        end
    end
    Fire("battle_round", tbl)
end

--- 处理 BOSS_BATTLE_END 事件
---@param tbl table
function M.OnBattleEnd(tbl)
    if tbl.action == "settle_ready" then
        -- 个人结算令牌
        settleInfo_ = {
            settleToken = tbl.settleToken,
            reward      = tbl.reward,
            damage      = tbl.damage,
            ratio       = tbl.ratio,
        }
        Fire("settle_ready", settleInfo_)
    else
        -- 战斗结束广播
        battleResult_ = {
            won           = tbl.won,
            bossName      = tbl.bossName,
            areaId        = tbl.areaId,
            totalDamage   = tbl.totalDamage,
            contributions = tbl.contributions,
            rounds        = tbl.rounds,
        }
        if teamData_ then
            teamData_.state = "ended"
        end
        Fire("battle_end", battleResult_)
    end
end

-- ============================================================================
-- 清理
-- ============================================================================

--- 完全重置状态（断线/切服时调用）
function M.Reset()
    teamData_     = nil
    bossData_     = nil
    roundLogs_    = {}
    battleResult_ = nil
    settleInfo_   = nil
    settling_     = false
    roomList_     = {}
    callbacks_    = {}
end

return M
