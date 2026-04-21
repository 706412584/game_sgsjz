-- ============================================================================
-- 《渡劫摆摊传》服务端入口
-- 职责：连接管理 + serverCloud 云代理 + serverCloud.message 邮件中转
-- 架构：云变量方案（薄服务端，不管货币/游戏逻辑）
-- ============================================================================

---@diagnostic disable: undefined-global
-- cjson 是引擎内置全局变量，无需 require

local Shared           = require("network.shared")
local EVENTS           = Shared.EVENTS
local ServerCloudProxy = require("network.server_cloud_proxy")
local ChatServer       = require("network.chat_server")
local PlayerMgr        = require("server_player")
local GameServer       = require("server_game")
local MailServer       = require("mail_server")

require "LuaScripts/Utilities/Sample"

-- GM 用户 ID 列表（与 server_manager.lua / mail_server.lua 一致）
local GM_USER_IDS = { [1644503283] = true, [529757584] = true }

-- 区服列表（内存缓存，持久化到 serverCloud）
local serverList_ = {}
local CLOUD_SERVER_LIST_KEY = "server_list"

-- 角色ID原子计数器（从 1000001 起步，避免与旧6位随机ID冲突）
local CLOUD_NEXT_PLAYER_ID_KEY = "next_player_id"
local NEXT_PLAYER_ID_START = 1000001
local nextPlayerId_ = NEXT_PLAYER_ID_START

-- ============================================================================
-- Mock graphics（headless 模式）
-- ============================================================================

if GetGraphics() == nil then
    local mg = {
        SetWindowIcon = function() end,
        SetWindowTitleAndIcon = function() end,
        GetWidth  = function() return 1920 end,
        GetHeight = function() return 1080 end,
    }
    function GetGraphics() return mg end
    graphics = mg
    console  = { background = {} }
    function GetConsole() return console end
    debugHud = {}
    function GetDebugHud() return debugHud end
end

-- ============================================================================
-- 状态
-- ============================================================================

---@type table<string, any>    connKey -> Connection
local connections_  = {}
---@type table<string, number> connKey -> userId
local connUserIds_  = {}
---@type table<number, string> userId -> connKey（反查）
local userIdToConn_ = {}
---@type table<number, number> userId -> serverId（玩家选定的区服）
local userServerId_ = {}
local scene_ = nil
local playerInfoLoaded_ = {}  -- 已成功加载到真实名称的 userId 集合
local nextAnonId_ = 10001     -- 无 identity 时的自增匿名 ID
local bannedCache_ = {}       -- 封禁用户缓存 { [userId] = true }，阻止反复重连
local clientReadyReceived_ = {} -- { [userId] = true } 标记已收到 CLIENT_READY 但 LoadPlayer 未完成

-- ============================================================================
-- 入口
-- ============================================================================

function Start()
    SampleStart()

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 注册远程事件（包含区服事件，由 shared.lua 统一管理）
    Shared.RegisterServerEvents()

    -- 订阅客户端请求
    SubscribeToEvent(EVENTS.CLOUD_REQ,      "HandleCloudReq")
    SubscribeToEvent("ClientConnected",     "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected",  "HandleClientDisconnected")

    -- 订阅区服管理请求
    SubscribeToEvent(EVENTS.SERVER_LIST_REQ, "HandleServerListReq")
    SubscribeToEvent(EVENTS.SERVER_ADD,      "HandleServerAdd")
    SubscribeToEvent(EVENTS.SERVER_REMOVE,   "HandleServerRemove")
    SubscribeToEvent(EVENTS.SERVER_UPDATE,   "HandleServerUpdate")
    SubscribeToEvent(EVENTS.SERVER_SELECT,   "HandleServerSelect")

    -- GM 操作
    SubscribeToEvent(EVENTS.GM_WIPE_SERVER,   "HandleGmWipeServer")
    SubscribeToEvent(EVENTS.GM_PLAYER_QUERY,  "HandleGmPlayerQuery")
    SubscribeToEvent(EVENTS.GM_PLAYER_EDIT,   "HandleGmPlayerEdit")

    -- 玩家信息主动推送（角色创建/改名后客户端发来）
    SubscribeToEvent(EVENTS.PLAYER_INFO_UPDATE, "HandlePlayerInfoUpdate")

    -- 游戏操作事件
    SubscribeToEvent(EVENTS.GAME_ACTION, "HandleGameAction")
    SubscribeToEvent(EVENTS.APP_BG,      "HandleAppBg")
    SubscribeToEvent(EVENTS.CLIENT_READY, "HandleClientReady")

    -- 初始化云代理模块（clientCloud polyfill 后端）
    ServerCloudProxy.Init({
        SendToClient = SendToClient,
    })

    -- 初始化聊天服务器
    ChatServer.Init({
        SendToClient   = SendToClient,
        BroadcastToAll = BroadcastToAll,
        GetOnlineUsers = GetOnlineUsers,
        GetUserServerId = function(userId)
            return userServerId_[userId] or 0
        end,
    })

    -- 初始化游戏服务器（权威逻辑）
    GameServer.Init({
        SendToClient = SendToClient,
        PlayerMgr    = PlayerMgr,
        EVENTS       = EVENTS,
        GetConnection = function(userId)
            local ck = userIdToConn_[userId]
            return ck and connections_[ck] or nil
        end,
        AllocatePlayerId = AllocatePlayerId,
        GetServerName = GetServerName,
        OnBanned = function(userId)
            bannedCache_[userId] = true
            print("[Server] 封禁缓存已记录: uid=" .. tostring(userId))
        end,
        OnUnbanned = function(userId)
            bannedCache_[userId] = nil
            print("[Server] 封禁缓存已清除: uid=" .. tostring(userId))
        end,
    })

    -- 初始化邮件服务器
    MailServer.Init()

    -- 订阅聊天/好友请求
    SubscribeToEvent(EVENTS.CHAT_SEND,        "HandleChatSend")
    SubscribeToEvent(EVENTS.CHAT_PRIVATE,     "HandleChatPrivate")
    SubscribeToEvent(EVENTS.FRIEND_REQ_SEND,  "HandleFriendReqSend")
    SubscribeToEvent(EVENTS.FRIEND_REQ_REPLY, "HandleFriendReqReply")
    SubscribeToEvent(EVENTS.FRIEND_REMOVE,    "HandleFriendRemove")
    SubscribeToEvent(EVENTS.FRIEND_LIST_REQ,  "HandleFriendListReq")

    -- 加载区服列表（从 serverCloud 或默认初始化）
    LoadServerList()

    -- 加载角色ID计数器
    LoadNextPlayerId()

    -- 订阅帧更新（驱动 ChatServer 节流保存等）
    SubscribeToEvent("Update", "HandleUpdate")

    print("[Server] 《渡劫摆摊传》服务端已启动（云变量方案 + 云代理 + 聊天）")
    print("[Server] serverCloud available: " .. tostring(serverCloud ~= nil))
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    ChatServer.Update(dt)
    GameServer.Update(dt)
    PlayerMgr.UpdateAll(dt)
end

function Stop()
    print("[Server] 服务端关闭，开始保存所有在线玩家数据...")
    -- 服务端关闭时立即保存所有在线玩家的脏数据
    local allIds = PlayerMgr.GetAllPlayerIds()
    local count = 0
    for _, userId in ipairs(allIds) do
        local state = PlayerMgr.GetState(userId)
        if state then
            -- 先保存制作队列到 state（与 OnPlayerDisconnect 逻辑一致）
            GameServer.OnPlayerDisconnect(userId)
            -- 标记脏并保存
            PlayerMgr.SetDirty(userId)
            PlayerMgr.SavePlayer(userId)
            count = count + 1
        end
    end
    print("[Server] 服务端关闭，已触发 " .. count .. " 个玩家的数据保存")
end

-- ============================================================================
-- 连接管理
-- ============================================================================

--- 从 eventData 提取 userId 和 connKey
---@param eventData any
---@return number|nil userId
---@return string|nil connKey
local function GetSender(eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)

    -- 新连接：注册
    if not connUserIds_[connKey] then
        print("[Server] GetSender: 新连接 connKey=" .. connKey)
        local hasIdentity = false
        local userId
        local identityUid = connection.identity["user_id"]
        if identityUid then
            -- tonumber 确保 userId 是 Lua number，避免 Int64 userdata 作为 table key 按引用比较
            userId = tonumber(identityUid:GetInt64())
            hasIdentity = true
        else
            -- 无 identity（调试模式）：每个连接分配唯一匿名 ID，避免互相踢
            userId = nextAnonId_
            nextAnonId_ = nextAnonId_ + 1
        end
        print("[Server] GetSender: userId=" .. tostring(userId) .. " hasIdentity=" .. tostring(hasIdentity))

        -- 同一 userId 已有旧连接 → 踢掉旧连接（双设备登录）
        local oldConnKey = userIdToConn_[userId]
        if oldConnKey and oldConnKey ~= connKey then
            local oldConn = connections_[oldConnKey]
            if oldConn then
                -- 先通知旧客户端被踢
                local kickData = VariantMap()
                kickData["Reason"] = Variant("duplicate_login")
                oldConn:SendRemoteEvent(EVENTS.KICKED, true, kickData)
                print("[Server] 踢掉旧连接: userId=" .. tostring(userId) .. " oldKey=" .. oldConnKey)
                -- 延迟断开旧连接（给事件发送留时间）
                oldConn:Disconnect(100)
            end
            -- 清理旧连接数据
            connections_[oldConnKey] = nil
            connUserIds_[oldConnKey] = nil
            -- 🔴 修复竞态: 主动保存旧会话脏数据并清理 PlayerMgr，
            -- 避免 HandleClientDisconnected 因 connUserIds_ 已清而跳过 RemovePlayer
            if PlayerMgr.IsLoaded(userId) then
                GameServer.OnPlayerDisconnect(userId)
                PlayerMgr.RemovePlayer(userId)
                print("[Server] 踢旧连接: 已保存并清理旧会话数据 uid=" .. tostring(userId))
            end
        end

        connections_[connKey]  = connection
        connUserIds_[connKey]  = userId
        userIdToConn_[userId]  = connKey

        -- 连接时立即从云端加载玩家信息（修复"无名修士"问题）
        UpdatePlayerInfoFromCloud(userId)

        -- 通知聊天服务器玩家上线（预加载好友, 聊天历史在 CLIENT_READY 后推送）
        ChatServer.OnPlayerConnect(userId, true)  -- skipHistory=true

        -- 加载玩家游戏状态（服务端权威）
        -- 注意：此处只预加载数据和初始化运行时，不发 GameInit
        -- GameInit 由 HandleClientReady 统一发送（等身份升级完成后）
        print("[Server] GetSender: 开始加载玩家数据 uid=" .. tostring(userId))
        PlayerMgr.LoadPlayer(userId, function(success, state, hasCloudData)
            -- 防御：身份可能已升级，此 userId 可能已不属于当前连接
            if connUserIds_[connKey] ~= userId then
                print("[Server] LoadPlayer 回调: uid=" .. tostring(userId)
                    .. " 身份已升级，丢弃临时数据")
                if PlayerMgr.IsLoaded(userId) then
                    PlayerMgr.ForceRemovePlayer(userId)
                end
                return
            end
            if success then
                print("[Server] LoadPlayer 回调: 成功 uid=" .. tostring(userId))
                SyncPlayerInfoFromState(userId, state)
                -- 预加载阶段不发 GameInit，等 HandleClientReady 身份升级后再发
                -- 仅当 HandleClientReady 已执行（clientReadyReceived_）时才补发
                local readyReceived = clientReadyReceived_[userId] or false
                clientReadyReceived_[userId] = nil
                -- 🔴 修复离线弹窗: sid=0 时禁止发 GameInit（数据不含正确区服的离线收益）
                -- HandleServerSelect 选服后会用正确 sid 重新 LoadPlayer 并发 GameInit
                local sid = userServerId_[userId] or 0
                local shouldSendInit = readyReceived and (sid > 0)
                if readyReceived and sid == 0 then
                    print("[Server] GetSender: readyReceived 但 sid=0, 延迟 GameInit 到选服后 uid=" .. tostring(userId))
                end
                GameServer.OnPlayerLoaded(userId, shouldSendInit)
                MailServer.OnPlayerLoaded(userId)
            else
                print("[Server] LoadPlayer 回调: 失败! uid=" .. tostring(userId))
                -- 通知客户端加载失败，让客户端显示重试提示而不是永远卡住
                local conn = connections_[connKey]
                if conn then
                    local errData = VariantMap()
                    errData["Reason"] = Variant("load_failed")
                    conn:SendRemoteEvent(EVENTS.KICKED, true, errData)
                    print("[Server] 已通知客户端加载失败，可重试: uid=" .. tostring(userId))
                end
            end
        end)

        print("[Server] 玩家连接: userId=" .. tostring(userId) .. " connKey=" .. connKey)
    else
        print("[Server] GetSender: 已知连接 connKey=" .. connKey .. " userId=" .. tostring(connUserIds_[connKey]))
    end

    return connUserIds_[connKey], connKey
end

--- 客户端连接时主动注册（打破 serverMode 下客户端等待 GameInit 的死锁）
function HandleClientConnected(eventType, eventData)
    print("[Server] >>> HandleClientConnected 触发 <<<")
    local userId = GetSender(eventData)
    print("[Server] HandleClientConnected: GetSender 返回 userId=" .. tostring(userId))
end

--- 客户端就绪信号：客户端事件注册完成后发来，确保 GameInit 不会因竞态丢失
--- 此时 identity 已可用，可进行身份升级
function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local oldUserId = connUserIds_[connKey]
    if not oldUserId then
        print("[Server] HandleClientReady: connKey 不匹配, 忽略")
        return
    end

    -- 尝试从 identity 获取真实 userId（ClientConnected 时可能还不可用）
    local identityUid = connection.identity["user_id"]
    if identityUid then
        local realUserId = tonumber(identityUid:GetInt64())
        if realUserId and realUserId ~= oldUserId then
            print("[Server] HandleClientReady: 身份升级 " .. tostring(oldUserId) .. " → " .. tostring(realUserId))

            -- 真实 userId 已有旧连接 → 踢掉旧连接（双设备登录）
            local existingConnKey = userIdToConn_[realUserId]
            if existingConnKey and existingConnKey ~= connKey then
                local existingConn = connections_[existingConnKey]
                if existingConn then
                    local kickData = VariantMap()
                    kickData["Reason"] = Variant("duplicate_login")
                    existingConn:SendRemoteEvent(EVENTS.KICKED, true, kickData)
                    existingConn:Disconnect(100)
                    print("[Server] 身份升级踢掉旧连接: realUid=" .. tostring(realUserId))
                end
                connections_[existingConnKey] = nil
                connUserIds_[existingConnKey] = nil
            end

            -- 🔴 修复竞态: 旧连接被踢后 HandleClientDisconnected 因 connUserIds_ 已清
            -- 而跳过 RemovePlayer，导致脏数据丢失且 userServerId_ 残留。
            -- 必须在此处主动保存旧会话数据并清理 PlayerMgr 状态。
            if PlayerMgr.IsLoaded(realUserId) then
                GameServer.OnPlayerDisconnect(realUserId)
                PlayerMgr.RemovePlayer(realUserId)
                print("[Server] 身份升级: 已保存并清理旧会话数据 realUid=" .. tostring(realUserId))
            end
            -- 清理旧会话的区服映射，确保 HandleServerSelect 不会因
            -- oldServerId == serverId 而早退跳过数据加载
            userServerId_[realUserId] = nil

            -- 清理旧临时 ID 的映射
            userIdToConn_[oldUserId] = nil
            userServerId_[oldUserId] = nil
            clientReadyReceived_[oldUserId] = nil

            -- 如果旧临时 ID 有已加载的玩家数据，强制丢弃（不保存到 serverCloud）
            if PlayerMgr.IsLoaded(oldUserId) then
                PlayerMgr.ForceRemovePlayer(oldUserId)
            end

            -- 更新映射为真实 userId
            connUserIds_[connKey] = realUserId
            userIdToConn_[realUserId] = connKey

            -- 封禁缓存检查：已知被封禁的用户发送封禁通知，不加载数据
            if bannedCache_[realUserId] then
                print("[Server] 封禁缓存命中, 发送封禁通知(不断开): uid=" .. tostring(realUserId))
                local kickData = VariantMap()
                kickData["Reason"] = Variant("banned")
                connection:SendRemoteEvent(EVENTS.KICKED, true, kickData)
                return
            end

            -- 身份升级阶段: 不加载 serverId=0 的玩家数据到内存
            -- 避免 serverId=0 数据被误保存覆盖区服存档
            -- 实际数据加载由 HandleServerSelect 选服后触发（加载正确区服数据）
            ChatServer.OnPlayerConnect(realUserId, true)
            print("[Server] 身份升级完成(不加载数据,等选服): realUid=" .. tostring(realUserId))
            -- 通知邮件服务器（用真实 userId 的连接）
            MailServer.OnClientReady(connection)
            return
        end
    end

    -- 无需身份升级，正常流程
    local userId = oldUserId
    print("[Server] >>> HandleClientReady: uid=" .. tostring(userId)
        .. " playerLoaded=" .. tostring(PlayerMgr.IsLoaded(userId)))
    -- 玩家数据已加载 → 立即(重新)发送 GameInit
    -- 注册 post-init 回调：确保 CHAT_HISTORY 在 GAME_INIT 之后发送
    GameServer.SetPostInitCallback(userId, function()
        ChatServer.SendChatHistory(userId)
    end)
    local sid = userServerId_[userId] or 0
    if PlayerMgr.IsLoaded(userId) and sid > 0 then
        -- 重连/已选服场景：runtime 已存在但 gameStarted 可能为 false，需恢复
        local rt = GameServer.GetRuntime(userId)
        if rt and not rt.gameStarted then
            rt.gameStarted = true
            print("[Server] HandleClientReady: 重连恢复 gameStarted=true uid=" .. tostring(userId))
        end
        GameServer.SendGameInit(userId)
        print("[Server] HandleClientReady: 重新发送 GameInit uid=" .. tostring(userId))
    elseif PlayerMgr.IsLoaded(userId) and sid == 0 then
        -- 🔴 数据已加载但未选服(sid=0): 不发 GameInit, 等 HandleServerSelect
        print("[Server] HandleClientReady: 已加载但 sid=0, 等选服后发 GameInit uid=" .. tostring(userId))
    else
        -- 标记：LoadPlayer 回调完成时需要补发 GameInit
        clientReadyReceived_[userId] = true
        print("[Server] HandleClientReady: 数据加载中, 标记待发 GameInit uid=" .. tostring(userId))
    end

    -- 通知邮件服务器客户端就绪
    MailServer.OnClientReady(connection)
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData:GetPtr("Connection", "Connection")
    local connKey = tostring(connection)
    local userId = connUserIds_[connKey]

    connections_[connKey]  = nil
    connUserIds_[connKey]  = nil
    if userId then
        userIdToConn_[userId] = nil
        userServerId_[userId] = nil
        clientReadyReceived_[userId] = nil
        ChatServer.OnPlayerDisconnect(userId)
        -- 游戏状态：保存制作队列 + 标记脏 + 持久化 + 清理
        GameServer.OnPlayerDisconnect(userId)
        PlayerMgr.RemovePlayer(userId)
    end

    -- 通知邮件服务器客户端断开
    MailServer.OnClientDisconnected(connection)

    print("[Server] 玩家断开: userId=" .. tostring(userId))
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 向指定玩家发送远程事件
---@param userId number
---@param eventName string
---@param data any VariantMap
function SendToClient(userId, eventName, data)
    local connKey = userIdToConn_[userId]
    if not connKey then
        print("[Server] SendToClient 失败: userId=" .. tostring(userId) .. " event=" .. eventName .. " 原因=无connKey")
        return false
    end
    local conn = connections_[connKey]
    if not conn then
        print("[Server] SendToClient 失败: userId=" .. tostring(userId) .. " event=" .. eventName .. " 原因=无conn对象")
        return false
    end
    conn:SendRemoteEvent(eventName, true, data)
    if eventName == "GameInit" or eventName == "GameSync" or eventName == "FriendReqIn" or eventName == "FriendUpdate" then
        print("[Server] SendToClient 成功: userId=" .. tostring(userId) .. " event=" .. eventName)
    end
end

--- 广播远程事件给所有在线玩家
---@param eventName string
---@param data any VariantMap
function BroadcastToAll(eventName, data)
    for connKey, conn in pairs(connections_) do
        conn:SendRemoteEvent(eventName, true, data)
    end
end

--- 获取所有在线玩家 userId 列表
---@return number[]
function GetOnlineUsers()
    local users = {}
    for uid, _ in pairs(userIdToConn_) do
        table.insert(users, uid)
    end
    return users
end

-- ============================================================================
-- 请求处理：游戏操作（服务端权威）
-- ============================================================================

function HandleGameAction(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local action     = eventData["Action"]:GetString()
    local paramsJson = eventData["Params"]:GetString()
    GameServer.HandleGameAction(userId, action, paramsJson)
end

function HandleAppBg(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local foreground = eventData["Foreground"]:GetBool()
    GameServer.HandleAppBg(userId, foreground)
end

-- ============================================================================
-- 请求处理：云代理（clientCloud polyfill 后端）
-- ============================================================================

function HandleCloudReq(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerCloudProxy.HandleCloudReq(userId, eventData)
end

-- ============================================================================
-- 区服管理
-- ============================================================================

local GLOBAL_USER_ID = 0  -- 全局共享数据用 userId=0

-- ============================================================================
-- 角色ID原子计数器
-- ============================================================================

--- 从 serverCloud 加载下一个角色ID
function LoadNextPlayerId()
    if not serverCloud then
        print("[Server] serverCloud 不可用，使用默认角色ID计数器: " .. nextPlayerId_)
        return
    end
    serverCloud:Get(GLOBAL_USER_ID, CLOUD_NEXT_PLAYER_ID_KEY, {
        ok = function(values)
            local raw = values and values[CLOUD_NEXT_PLAYER_ID_KEY]
            if raw and raw ~= "" then
                local num = tonumber(raw)
                if num and num >= NEXT_PLAYER_ID_START then
                    nextPlayerId_ = num
                end
            end
            print("[Server] 角色ID计数器已加载: nextPlayerId=" .. nextPlayerId_)
        end,
        error = function(code, reason)
            print("[Server] 角色ID计数器加载失败: " .. tostring(reason) .. "，使用默认值: " .. nextPlayerId_)
        end,
    })
end

--- 分配一个新的唯一角色ID（同步返回，异步持久化）
---@return string playerId 新分配的角色ID字符串
function AllocatePlayerId()
    local id = nextPlayerId_
    nextPlayerId_ = nextPlayerId_ + 1
    -- 异步持久化到 serverCloud
    if serverCloud then
        serverCloud:Set(GLOBAL_USER_ID, CLOUD_NEXT_PLAYER_ID_KEY, tostring(nextPlayerId_), {
            ok = function() end,
            error = function(code, reason)
                print("[Server] 角色ID计数器保存失败: " .. tostring(reason))
            end,
        })
    end
    print("[Server] 分配角色ID: " .. tostring(id) .. " (下一个: " .. nextPlayerId_ .. ")")
    return tostring(id)
end

--- 根据 serverId 获取区服名称
---@param serverId number
---@return string
function GetServerName(serverId)
    for _, srv in ipairs(serverList_) do
        if srv.id == serverId then return srv.name end
    end
    return ""
end

-- ============================================================================
-- 区服管理
-- ============================================================================

--- 加载区服列表（从 serverCloud 或初始化默认区服）
function LoadServerList()
    if serverCloud then
        serverCloud:Get(GLOBAL_USER_ID, CLOUD_SERVER_LIST_KEY, {
            ok = function(values)
                local jsonStr = values and values[CLOUD_SERVER_LIST_KEY]
                if jsonStr and jsonStr ~= "" then
                    local ok, list = pcall(cjson.decode, jsonStr)
                    if ok and type(list) == "table" then
                        serverList_ = list
                        print("[Server] 从云端加载 " .. #serverList_ .. " 个区服")
                        return
                    end
                end
                -- 云端无数据，初始化默认区服
                InitDefaultServers()
            end,
            error = function(code, reason)
                print("[Server] 云端区服加载失败: " .. tostring(reason) .. "，使用默认区服")
                InitDefaultServers()
            end,
        })
    else
        -- serverCloud 不可用，直接用默认区服
        InitDefaultServers()
    end
end

--- 初始化默认区服
function InitDefaultServers()
    serverList_ = {
        { id = 1, name = "太虚境·一服", status = "正常" },
    }
    SaveServerList()
    print("[Server] 已初始化默认区服")
end

--- 持久化区服列表到 serverCloud
function SaveServerList()
    if serverCloud then
        serverCloud:Set(GLOBAL_USER_ID, CLOUD_SERVER_LIST_KEY, cjson.encode(serverList_), {
            ok = function() end,
            error = function(code, reason)
                print("[Server] 区服列表保存失败: " .. tostring(reason))
            end,
        })
    end
end

--- 向指定连接发送区服列表
---@param connection any
local function sendServerListToConn(connection)
    local data = VariantMap()
    data["ServerJson"] = Variant(cjson.encode(serverList_))
    data["Count"]      = Variant(#serverList_)
    connection:SendRemoteEvent(EVENTS.SERVER_LIST_RESP, true, data)
end

--- 向指定连接发送操作结果
---@param connection any
---@param action string
---@param success boolean
---@param message string
local function sendOpResult(connection, action, success, message)
    local data = VariantMap()
    data["Action"]  = Variant(action)
    data["Success"] = Variant(success)
    data["Message"] = Variant(message)
    connection:SendRemoteEvent(EVENTS.SERVER_OP_RESULT, true, data)
end

-- ========== 区服事件处理 ==========

function HandleServerListReq(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)

    -- 确保连接已注册
    if not connUserIds_[connKey] then
        GetSender(eventData)
    end

    print("[Server] 收到区服列表请求 connKey=" .. connKey)
    sendServerListToConn(connection)
end

function HandleServerAdd(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local name = eventData["Name"]:GetString()

    if name == "" then
        sendOpResult(connection, "add", false, "区服名称不能为空")
        return
    end

    -- 生成新 ID
    local maxId = 0
    for _, srv in ipairs(serverList_) do
        if srv.id > maxId then maxId = srv.id end
    end

    local newServer = {
        id = maxId + 1,
        name = name,
        status = "正常",
    }
    table.insert(serverList_, newServer)
    SaveServerList()

    print("[Server] 新增区服: " .. name .. " id=" .. newServer.id)
    sendOpResult(connection, "add", true, "已添加区服: " .. name)
end

function HandleServerRemove(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local serverId = eventData["ServerId"]:GetInt()

    for i, srv in ipairs(serverList_) do
        if srv.id == serverId then
            table.remove(serverList_, i)
            SaveServerList()
            print("[Server] 删除区服 id=" .. serverId)
            sendOpResult(connection, "remove", true, "已删除区服")
            return
        end
    end

    sendOpResult(connection, "remove", false, "区服不存在")
end

function HandleServerUpdate(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local serverId = eventData["ServerId"]:GetInt()
    local status   = eventData["Status"]:GetString()

    for _, srv in ipairs(serverList_) do
        if srv.id == serverId then
            local oldStatus = srv.status
            srv.status = status
            SaveServerList()
            print("[Server] 更新区服 id=" .. serverId .. " status=" .. status)
            sendOpResult(connection, "update", true, "已更新区服状态")

            -- 设为维护时：精准踢出选定了该区服的非 GM 玩家
            if status == "维护" and oldStatus ~= "维护" then
                local kickData = VariantMap()
                kickData["ServerId"]   = Variant(serverId)
                kickData["ServerName"] = Variant(srv.name)

                local kickCount = 0
                for uid, sid in pairs(userServerId_) do
                    if sid == serverId and not GM_USER_IDS[tonumber(uid)] then
                        local connKey = userIdToConn_[uid]
                        local conn = connKey and connections_[connKey]
                        if conn then
                            conn:SendRemoteEvent(EVENTS.MAINTENANCE_KICK, true, kickData)
                            kickCount = kickCount + 1
                        end
                    end
                end
                print("[Server] 区服维护精准踢人: serverId=" .. serverId
                    .. " name=" .. srv.name .. " kicked=" .. kickCount .. " (GM excluded)")
            end
            return
        end
    end

    sendOpResult(connection, "update", false, "区服不存在")
end

function HandleServerSelect(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local serverId = eventData["ServerId"]:GetInt()
    local oldServerId = userServerId_[userId] or 0
    userServerId_[userId] = serverId
    print("[Server] 玩家选定区服: userId=" .. tostring(userId)
        .. " 旧区=" .. oldServerId .. " -> 新区=" .. serverId)

    -- 区服没变, 仅更新映射
    if oldServerId == serverId then return end

    -- 换区 → 重置玩家信息缓存，让 ChatServer 获取新区的道号
    playerInfoLoaded_[userId] = nil

    -- 区服切换: 先保存旧区数据, 再加载新区数据, 最后重发 GameInit
    local function loadNewRealm()
        PlayerMgr.SetServerId(userId, serverId)
        PlayerMgr.LoadPlayer(userId, function(success, state, hasCloudData)
            if success then
                -- 云存档验证：明确区分老玩家(有云存档)和新玩家(无云存档)
                if hasCloudData then
                    print("[Server] 云存档验证通过: userId=" .. tostring(userId)
                        .. " serverId=" .. serverId
                        .. " name=" .. tostring(state.playerName)
                        .. " playerId=" .. tostring(state.playerId))
                else
                    print("[Server] 该区服无云存档(新玩家): userId=" .. tostring(userId)
                        .. " serverId=" .. serverId .. " 将创建新角色")
                end
                state.serverId = serverId
                SyncPlayerInfoFromState(userId, state)
                -- 注册 post-init 回调：确保 CHAT_HISTORY 在 GAME_INIT 之后发送
                GameServer.SetPostInitCallback(userId, function()
                    ChatServer.SendChatHistory(userId)
                end)
                GameServer.OnPlayerLoaded(userId)
                MailServer.OnPlayerLoaded(userId)
                print("[Server] 换服加载完成: userId=" .. tostring(userId) .. " serverId=" .. serverId
                    .. " hasCloudData=" .. tostring(hasCloudData))
            else
                print("[Server] 换服加载失败: userId=" .. tostring(userId))
                -- 通知客户端换服加载失败
                local connKey = userIdToConn_[userId]
                local conn = connKey and connections_[connKey]
                if conn then
                    local errData = VariantMap()
                    errData["Reason"] = Variant("load_failed")
                    conn:SendRemoteEvent(EVENTS.KICKED, true, errData)
                end
            end
        end)
    end

    if oldServerId ~= 0 and PlayerMgr.GetState(userId) then
        -- 保存旧区数据后再加载新区
        -- 🔴 竞态保护：捕获旧 state 引用，防止回调延迟时误删新会话数据
        local oldStateRef = PlayerMgr.GetState(userId)
        PlayerMgr.SavePlayer(userId, function()
            -- 仅当 state 引用未变时才清理（新 LoadPlayer 可能已替换）
            if PlayerMgr.GetState(userId) == oldStateRef then
                PlayerMgr.ForceRemovePlayer(userId)
            else
                print("[Server] 换服保存回调: 新会话已加载, 跳过 ForceRemove uid=" .. tostring(userId))
            end
            loadNewRealm()
        end)
    else
        -- 首次选区 / 旧区无数据: 丢弃内存中无前缀数据, 加载新区
        if PlayerMgr.GetState(userId) then
            PlayerMgr.ForceRemovePlayer(userId)
        end
        loadNewRealm()
    end
end

-- ============================================================================
-- 聊天/好友事件处理（委托给 ChatServer 模块）
-- ============================================================================

function HandleChatSend(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end

    -- 首次聊天时尝试从 serverCloud 获取玩家信息并缓存
    UpdatePlayerInfoFromCloud(userId)

    ChatServer.HandleChatSend(userId, eventData)
end

function HandleChatPrivate(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleChatPrivate(userId, eventData)
end

function HandleFriendReqSend(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleFriendReqSend(userId, eventData)
end

function HandleFriendReqReply(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleFriendReqReply(userId, eventData)
end

function HandleFriendRemove(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleFriendRemove(userId, eventData)
end

function HandleFriendListReq(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleFriendListReq(userId)
end

-- ============================================================================
-- GM: 清除本服数据
-- ============================================================================

function HandleGmWipeServer(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local connection = eventData["Connection"]:GetPtr("Connection")

    print("[Server] GM清除本服数据请求: userId=" .. tostring(userId))

    -- 1. 清除 ChatServer 内存数据（聊天历史、玩家信息缓存、好友缓存等）
    ChatServer.WipeAllData()

    -- 2. 清除区服列表（重置为默认区服）
    InitDefaultServers()

    -- 3. 清除玩家信息加载缓存（允许重新从云端获取）
    playerInfoLoaded_ = {}

    -- 4. 清除 serverCloud 中持久化的区服列表
    if serverCloud then
        serverCloud:Set(GLOBAL_USER_ID, CLOUD_SERVER_LIST_KEY, "", {
            ok = function()
                print("[Server] 云端区服列表已清除")
            end,
            error = function(code, reason)
                print("[Server] 云端区服列表清除失败: " .. tostring(reason))
            end,
        })
    end

    -- 5. 回复客户端
    sendOpResult(connection, "wipe_server", true, "本服数据已清除(聊天记录/区服列表/缓存)")

    -- 6. 广播系统消息通知所有在线玩家
    local sysData = VariantMap()
    sysData["Text"] = Variant("管理员已重置服务器数据，部分功能可能需要重新加载")
    BroadcastToAll(EVENTS.CHAT_SYSTEM, sysData)
end

-- ============================================================================
-- GM: 查询玩家数据
-- ============================================================================

--- 查询玩家的所有已知云数据
function HandleGmPlayerQuery(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local connection = eventData["Connection"]:GetPtr("Connection")

    -- GM 权限校验: 优先用 identity 真实 ID，fallback 用 GetSender 的 userId
    local realUid = userId
    local identityUid = connection.identity["user_id"]
    if identityUid then
        realUid = identityUid:GetInt64()
    end
    if not GM_USER_IDS[tonumber(realUid)] then
        print("[Server] 非GM用户尝试查询玩家数据: " .. tostring(realUid) .. " (sender=" .. tostring(userId) .. ")")
        return
    end

    local targetUid = eventData["TargetUid"]:GetString()
    local gmServerId = eventData["ServerId"] and eventData["ServerId"]:GetInt() or 0

    -- 支持通过 playerId / 角色名 / 平台UID 反查: 遍历在线玩家匹配
    local targetNum = tonumber(targetUid)
    local foundOnline = false
    if targetUid ~= "" then
        for _, pid in ipairs(PlayerMgr.GetAllPlayerIds()) do
            local ps = PlayerMgr.GetState(pid)
            if ps and (ps.playerId == targetUid or ps.playerName == targetUid) then
                targetNum = pid
                foundOnline = true
                print("[Server] GM: input=" .. targetUid .. " matched online player -> userId=" .. tostring(pid))
                break
            end
        end
    end

    if not targetNum then
        local resp = VariantMap()
        resp["Success"] = Variant(false)
        resp["TargetUid"] = Variant(targetUid or "")
        resp["DataJson"] = Variant(cjson.encode({ error = "非数字ID且未匹配到在线玩家，离线玩家请使用平台UID查询" }))
        SendToClient(userId, EVENTS.GM_PLAYER_RESP, resp)
        return
    end

    print("[Server] GM查询玩家数据: input=" .. targetUid .. " resolved userId=" .. tostring(targetNum) .. " online=" .. tostring(foundOnline))

    -- 在线玩家且查询的区服与其当前区服一致时,直接读内存
    local useOnlinePath = false
    if foundOnline and PlayerMgr.IsLoaded(targetNum) then
        local s = PlayerMgr.GetState(targetNum)
        if s then
            local playerRealmId = s.serverId or (userServerId_[targetNum] or 0)
            -- gmServerId==0 表示未指定,跟随玩家当前区服; 否则必须匹配
            if gmServerId == 0 or gmServerId == playerRealmId then
                useOnlinePath = true
            end
        end
    end

    if useOnlinePath then
        local s = PlayerMgr.GetState(targetNum)
        if s then
            local sid = s.serverId or (userServerId_[targetNum] or 0)
            local result = {
                playerName   = s.playerName or "",
                playerGender = s.playerGender or "",
                playerId     = s.playerId or "",
                serverId     = sid,
                serverName   = GetServerName(sid),
                lingshi        = s.lingshi or 0,
                xiuwei         = s.xiuwei or 0,
                totalEarned    = s.totalEarned or 0,
                totalSold      = s.totalSold or 0,
                totalCrafted   = s.totalCrafted or 0,
                totalAdWatched = s.totalAdWatched or 0,
                stallLevel     = s.stallLevel or 1,
                realmLevel     = s.realmLevel or 1,
                lifespan     = s.lifespan or 100,
                rebirthCount = s.rebirthCount or 0,
                dead         = s.dead or false,
                fieldLevel   = s.fieldLevel or 1,
                materials    = s.materials or {},
                products     = s.products or {},
                -- 渡劫次数
                dujieFreeUses = s.dujieFreeUses or 0,
                dujiePaidUses = s.dujiePaidUses or 0,
                dujieDailyDate = s.dujieDailyDate or "",
                -- 秘境次数
                dungeonDailyUses = s.dungeonDailyUses or {},
                dungeonDailyDate = s.dungeonDailyDate or "",
                dungeonBonusUses = s.dungeonBonusUses or {},
                -- 每日广告次数
                dailyAdDate    = s.dailyAdDate or "",
                dailyAdCounts  = s.dailyAdCounts or {},
                online       = true,
                banned       = false,
            }
            -- 查询封禁状态后再返回
            local function sendOnlineResult(bannedVal)
                result.banned = (bannedVal == "true")
                local resp = VariantMap()
                resp["Success"] = Variant(true)
                resp["TargetUid"] = Variant(tostring(targetNum))
                resp["DataJson"] = Variant(cjson.encode(result))
                SendToClient(userId, EVENTS.GM_PLAYER_RESP, resp)
            end
            if serverCloud then
                serverCloud:BatchGet(targetNum)
                    :Key("banned")
                    :Fetch({
                        ok = function(scores)
                            local rawVal = scores and scores["banned"]
                            print("[GM_QUERY] online banned check uid=" .. tostring(targetNum) .. " rawVal=" .. tostring(rawVal) .. " type=" .. type(rawVal or "nil") .. " scores=" .. tostring(cjson.encode(scores or {})))
                            sendOnlineResult(rawVal or "")
                        end,
                        error = function(code, reason)
                            print("[GM_QUERY] online banned check ERROR uid=" .. tostring(targetNum) .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
                            sendOnlineResult("")
                        end,
                    })
            else
                sendOnlineResult("")
            end
            return
        end
    end

    if not serverCloud then
        local resp = VariantMap()
        resp["Success"] = Variant(false)
        resp["TargetUid"] = Variant(targetUid)
        resp["DataJson"] = Variant("")
        SendToClient(userId, EVENTS.GM_PLAYER_RESP, resp)
        return
    end

    -- 查询所有已知 key(使用GM指定的区服前缀)
    local rk = function(base) return PlayerMgr.RealmKey(base, gmServerId) end

    -- 提取为函数，支持反向索引解析后以正确 userId 查云端
    local function doOfflineCloudQuery(resolvedUid)
        print("[Server] GM查询玩家数据(cloud): input=" .. targetUid .. " resolved userId=" .. tostring(resolvedUid))
        serverCloud:BatchGet(resolvedUid)
            :Key(rk("lingshi"))
            :Key(rk("xiuwei"))
            :Key(rk("totalEarned"))
            :Key(rk("totalSold"))
            :Key(rk("totalCrafted"))
            :Key(rk("totalAdWatched"))
            :Key(rk("stallLevel"))
            :Key(rk("realmLevel"))
            :Key(rk("gameState"))
            :Key(rk("playerName"))
            :Key(rk("playerGender"))
            :Key(rk("playerId"))
            :Key("banned")
            :Fetch({
                ok = function(scores, iscores)
                    scores = scores or {}
                    iscores = iscores or {}

                    -- 解析 gameState JSON(带区服前缀)
                    local gsRaw = scores[rk("gameState")]
                    local gameState = {}
                    if gsRaw and gsRaw ~= "" then
                        local decOk, gs = pcall(cjson.decode, gsRaw)
                        if decOk and type(gs) == "table" then
                            gameState = gs
                        end
                    end

                    local offlineSid = gmServerId
                    local result = {
                        playerName   = scores[rk("playerName")] or "",
                        playerGender = scores[rk("playerGender")] or "",
                        playerId     = scores[rk("playerId")] or "",
                        serverId     = offlineSid,
                        serverName   = GetServerName(offlineSid),
                        lingshi        = iscores[rk("lingshi")] or 0,
                        xiuwei         = iscores[rk("xiuwei")] or 0,
                        totalEarned    = iscores[rk("totalEarned")] or 0,
                        totalSold      = iscores[rk("totalSold")] or 0,
                        totalCrafted   = iscores[rk("totalCrafted")] or 0,
                        totalAdWatched = iscores[rk("totalAdWatched")] or 0,
                        stallLevel     = iscores[rk("stallLevel")] or 1,
                        realmLevel     = iscores[rk("realmLevel")] or 1,
                        lifespan     = gameState.lifespan or 100,
                        rebirthCount = gameState.rebirthCount or 0,
                        dead         = gameState.dead or false,
                        fieldLevel   = gameState.fieldLevel or 1,
                        materials    = gameState.materials or {},
                        products     = gameState.products or {},
                        dujieFreeUses = gameState.dujieFreeUses or 0,
                        dujiePaidUses = gameState.dujiePaidUses or 0,
                        dujieDailyDate = gameState.dujieDailyDate or "",
                        dungeonDailyUses = gameState.dungeonDailyUses or {},
                        dungeonDailyDate = gameState.dungeonDailyDate or "",
                        dungeonBonusUses = gameState.dungeonBonusUses or {},
                        dailyAdDate    = gameState.dailyAdDate or "",
                        dailyAdCounts  = gameState.dailyAdCounts or {},
                        banned       = (scores["banned"] == "true"),
                    }

                    print("[GM_QUERY] offline uid=" .. tostring(resolvedUid) .. " playerName=" .. tostring(result.playerName))

                    -- playerName 为空且关键数值均为默认值 → 无数据
                    if (result.playerName == "") and (result.lingshi == 0) and (result.xiuwei == 0) then
                        local resp = VariantMap()
                        resp["Success"] = Variant(false)
                        resp["TargetUid"] = Variant(targetUid)
                        resp["DataJson"] = Variant(cjson.encode({ error = "该玩家在此区服无角色数据" }))
                        SendToClient(userId, EVENTS.GM_PLAYER_RESP, resp)
                        return
                    end

                    local resp = VariantMap()
                    resp["Success"] = Variant(true)
                    resp["TargetUid"] = Variant(tostring(resolvedUid))
                    resp["DataJson"] = Variant(cjson.encode(result))
                    SendToClient(userId, EVENTS.GM_PLAYER_RESP, resp)
                end,
                error = function(code, reason)
                    print("[Server] GM查询玩家数据失败: " .. tostring(reason))
                    local resp = VariantMap()
                    resp["Success"] = Variant(false)
                    resp["TargetUid"] = Variant(targetUid)
                    resp["DataJson"] = Variant("")
                    SendToClient(userId, EVENTS.GM_PLAYER_RESP, resp)
                end,
            })
    end

    -- 未在线时先查角色ID反向索引（pid2uid_），解析真实平台UID
    -- 适用场景：GM 输入角色ID（如 1000001）而非平台UID
    if not foundOnline and targetUid ~= "" then
        serverCloud:Get(GLOBAL_USER_ID, "pid2uid_" .. targetUid, {
            ok = function(values)
                local resolvedUid = tonumber(values and values["pid2uid_" .. targetUid])
                if resolvedUid then
                    print("[Server] GM: 角色ID反查成功: " .. targetUid .. " -> uid=" .. tostring(resolvedUid))
                    doOfflineCloudQuery(resolvedUid)
                else
                    doOfflineCloudQuery(targetNum)
                end
            end,
            error = function()
                doOfflineCloudQuery(targetNum)
            end,
        })
    else
        doOfflineCloudQuery(targetNum)
    end
end

-- ============================================================================
-- GM: 编辑玩家数据
-- ============================================================================

--- 编辑指定玩家的云数据
function HandleGmPlayerEdit(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local connection = eventData["Connection"]:GetPtr("Connection")

    -- GM 权限校验: 优先用 identity 真实 ID
    local realUid = userId
    local identityUid = connection.identity["user_id"]
    if identityUid then
        realUid = identityUid:GetInt64()
    end
    if not GM_USER_IDS[tonumber(realUid)] then
        print("[Server] 非GM用户尝试编辑玩家数据: " .. tostring(realUid) .. " (sender=" .. tostring(userId) .. ")")
        return
    end

    local targetUid = eventData["TargetUid"]:GetString()
    local editJson  = eventData["EditJson"]:GetString()
    local gmServerId = eventData["ServerId"] and eventData["ServerId"]:GetInt() or 0

    -- 支持 playerId / 角色名 / 平台UID 反查
    local targetNum = tonumber(targetUid)
    if targetUid ~= "" then
        for _, pid in ipairs(PlayerMgr.GetAllPlayerIds()) do
            local ps = PlayerMgr.GetState(pid)
            if ps and (ps.playerId == targetUid or ps.playerName == targetUid) then
                targetNum = pid
                print("[Server] GM编辑: input=" .. targetUid .. " matched -> userId=" .. tostring(pid))
                break
            end
        end
    end

    if not targetNum or not editJson or editJson == "" then
        local resp = VariantMap()
        resp["Success"] = Variant(false)
        resp["Message"] = Variant(not targetNum and "未找到该玩家(离线玩家请使用平台UID)" or "参数无效")
        SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
        return
    end

    local decOk, edits = pcall(cjson.decode, editJson)
    if not decOk or type(edits) ~= "table" then
        local resp = VariantMap()
        resp["Success"] = Variant(false)
        resp["Message"] = Variant("JSON解析失败")
        SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
        return
    end

    if not serverCloud then
        local resp = VariantMap()
        resp["Success"] = Variant(false)
        resp["Message"] = Variant("serverCloud不可用")
        SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
        return
    end

    print("[Server] GM编辑玩家数据: targetUid=" .. targetUid .. " edits=" .. editJson)

    -- iscore 字段列表
    local ISCORE_SET = {
        lingshi = true, xiuwei = true, totalEarned = true, totalSold = true,
        totalCrafted = true, totalAdWatched = true, stallLevel = true, realmLevel = true,
    }
    -- gameState 内可编辑字段
    local GS_FIELDS = {
        lifespan = true, rebirthCount = true, dead = true,
        dujieFreeUses = true, dujiePaidUses = true, dujieDailyDate = true,
        dungeonDailyDate = true,
        -- 秘境各副本次数(拆分字段, 保存时合并到 dungeonDailyUses table)
        dungeon_lingcao = true, dungeon_liandan = true,
        dungeon_wanbao = true, dungeon_tianjie = true,
        -- 秘境探险券(广告奖励额外次数, 合并到 dungeonBonusUses table)
        bonus_lingcao = true, bonus_liandan = true,
        bonus_wanbao = true, bonus_tianjie = true,
        -- 每日广告次数(拆分字段, 合并到 dailyAdCounts table)
        dailyAdDate = true,
        ad_bless = true, ad_fortune = true, ad_aid = true, ad_dungeon_ticket = true,
    }

    -- 分离 iscore 和 gameState 修改
    local iscoreEdits = {}
    local gsEdits = {}
    for k, v in pairs(edits) do
        if ISCORE_SET[k] then
            iscoreEdits[k] = tonumber(v) or 0
        elseif GS_FIELDS[k] then
            gsEdits[k] = v
        end
    end

    -- 将 dungeon_xxx / bonus_xxx / ad_xxx 拆分字段合并回对应 table
    local DUNGEON_PREFIX = "dungeon_"
    local dungeonEdits = {}
    local BONUS_PREFIX = "bonus_"
    local bonusEdits = {}
    local AD_PREFIX = "ad_"
    local adEdits = {}
    for k, v in pairs(gsEdits) do
        if k:sub(1, #DUNGEON_PREFIX) == DUNGEON_PREFIX then
            local dungeonId = k:sub(#DUNGEON_PREFIX + 1)
            dungeonEdits[dungeonId] = tonumber(v) or 0
            gsEdits[k] = nil  -- 从 gsEdits 移除, 不直接写 state
        elseif k:sub(1, #BONUS_PREFIX) == BONUS_PREFIX then
            local dungeonId = k:sub(#BONUS_PREFIX + 1)
            bonusEdits[dungeonId] = tonumber(v) or 0
            gsEdits[k] = nil
        elseif k:sub(1, #AD_PREFIX) == AD_PREFIX then
            local adKey = k:sub(#AD_PREFIX + 1)
            adEdits[adKey] = tonumber(v) or 0
            gsEdits[k] = nil
        end
    end
    local hasDungeonEdits = false
    for _ in pairs(dungeonEdits) do hasDungeonEdits = true; break end
    local hasBonusEdits = false
    for _ in pairs(bonusEdits) do hasBonusEdits = true; break end
    local hasAdEdits = false
    for _ in pairs(adEdits) do hasAdEdits = true; break end

    -- 将拆分字段应用到 state 的辅助函数
    local function applyNestedEdits(s)
        if hasDungeonEdits then
            if type(s.dungeonDailyUses) ~= "table" then s.dungeonDailyUses = {} end
            for did, cnt in pairs(dungeonEdits) do
                s.dungeonDailyUses[did] = cnt
            end
        end
        if hasBonusEdits then
            if type(s.dungeonBonusUses) ~= "table" then s.dungeonBonusUses = {} end
            for did, cnt in pairs(bonusEdits) do
                s.dungeonBonusUses[did] = cnt
            end
        end
        if hasAdEdits then
            if type(s.dailyAdCounts) ~= "table" then s.dailyAdCounts = {} end
            for adKey, cnt in pairs(adEdits) do
                s.dailyAdCounts[adKey] = cnt
            end
        end
    end

    -- === 在线玩家：直接修改内存状态 ===
    if PlayerMgr.IsLoaded(targetNum) then
        local s = PlayerMgr.GetState(targetNum)
        if s then
            for k, v in pairs(iscoreEdits) do s[k] = v end
            for k, v in pairs(gsEdits) do s[k] = v end
            applyNestedEdits(s)
            PlayerMgr.SetDirty(targetNum)
            PlayerMgr.SavePlayer(targetNum)
            -- 立即同步给客户端
            local vm = VariantMap()
            vm["StateJson"] = Variant(cjson.encode(s))
            SendToClient(targetNum, EVENTS.GAME_SYNC, vm)
        end
        local resp = VariantMap()
        resp["Success"] = Variant(true)
        resp["Message"] = Variant("数据已修改(在线玩家)")
        SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
        return
    end

    -- === 离线玩家：走 serverCloud 读写(使用GM指定区服前缀) ===
    local rk = function(base) return PlayerMgr.RealmKey(base, gmServerId) end

    -- 先写 iscore 字段(带区服前缀)
    local hasIscoreEdits = false
    local batch = serverCloud:BatchSet(targetNum)
    for k, v in pairs(iscoreEdits) do
        batch:SetInt(rk(k), math.floor(v))
        hasIscoreEdits = true
    end

    -- 如果有 gameState 字段要修改，需要 read-modify-write
    local hasGsEdits = next(gsEdits) ~= nil

    if hasGsEdits then
        -- 先读取现有 gameState(带区服前缀)
        local gsKey = rk("gameState")
        serverCloud:Get(targetNum, gsKey, {
            ok = function(scores)
                scores = scores or {}
                local gsRaw = scores[gsKey]
                local gameState = {}
                if gsRaw and gsRaw ~= "" then
                    local ok2, gs = pcall(cjson.decode, gsRaw)
                    if ok2 and type(gs) == "table" then
                        gameState = gs
                    end
                end

                -- 合并修改
                for k, v in pairs(gsEdits) do
                    gameState[k] = v
                end
                applyNestedEdits(gameState)

                -- 写回 gameState(带区服前缀)
                local gsJson = cjson.encode(gameState)
                serverCloud:Set(targetNum, gsKey, gsJson, {
                    ok = function()
                        -- 再保存 iscore
                        if hasIscoreEdits then
                            batch:Save("GM edit iscores", {
                                ok = function()
                                    local resp = VariantMap()
                                    resp["Success"] = Variant(true)
                                    resp["Message"] = Variant("数据已保存")
                                    SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
                                end,
                                error = function(code, reason)
                                    local resp = VariantMap()
                                    resp["Success"] = Variant(false)
                                    resp["Message"] = Variant("iscore保存失败: " .. tostring(reason))
                                    SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
                                end,
                            })
                        else
                            local resp = VariantMap()
                            resp["Success"] = Variant(true)
                            resp["Message"] = Variant("数据已保存")
                            SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
                        end
                    end,
                    error = function(code, reason)
                        local resp = VariantMap()
                        resp["Success"] = Variant(false)
                        resp["Message"] = Variant("gameState保存失败: " .. tostring(reason))
                        SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
                    end,
                })
            end,
            error = function(code, reason)
                local resp = VariantMap()
                resp["Success"] = Variant(false)
                resp["Message"] = Variant("读取gameState失败: " .. tostring(reason))
                SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
            end,
        })
    elseif hasIscoreEdits then
        -- 只有 iscore 修改
        batch:Save("GM edit iscores", {
            ok = function()
                local resp = VariantMap()
                resp["Success"] = Variant(true)
                resp["Message"] = Variant("数据已保存")
                SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
            end,
            error = function(code, reason)
                local resp = VariantMap()
                resp["Success"] = Variant(false)
                resp["Message"] = Variant("保存失败: " .. tostring(reason))
                SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
            end,
        })
    else
        local resp = VariantMap()
        resp["Success"] = Variant(true)
        resp["Message"] = Variant("无有效修改")
        SendToClient(userId, EVENTS.GM_PLAYER_EDIT_RESP, resp)
    end
end

-- ============================================================================
-- 玩家信息主动推送（角色创建/改名后客户端发来）
-- ============================================================================

function HandlePlayerInfoUpdate(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end

    local name     = eventData["Name"]:GetString()
    local gender   = eventData["Gender"]:GetString()
    local playerId = eventData["PlayerId"]:GetString()

    if name ~= "" then
        ChatServer.UpdatePlayerInfo(userId, {
            name     = name,
            gender   = gender ~= "" and gender or "male",
            playerId = playerId ~= "" and playerId or "000000",
            realm    = 0,
        })
        playerInfoLoaded_[userId] = true
        print("[Server] 玩家信息主动更新: userId=" .. tostring(userId) .. " name=" .. name)
    end
end

-- ============================================================================
-- 玩家信息同步（从 serverCloud 获取道号/性别等信息供聊天显示）
-- ============================================================================

--- 从 serverCloud 加载玩家信息并缓存到 ChatServer
--- 如果获取到的名称是默认值（玩家尚未保存），允许下次重试
---@param userId number
--- 从已加载的 state 直接同步玩家信息到 ChatServer（最可靠路径）
---@param userId number
---@param state table
function SyncPlayerInfoFromState(userId, state)
    if not state then return end
    local name = state.playerName
    local hasRealName = (name ~= nil and name ~= "")
    ChatServer.UpdatePlayerInfo(userId, {
        name     = hasRealName and name or "无名修士",
        gender   = state.playerGender or "male",
        playerId = state.playerId or "000000",
        realm    = state.realmLevel or 0,
    })
    if hasRealName then
        playerInfoLoaded_[userId] = true
    end
end

function UpdatePlayerInfoFromCloud(userId)
    if playerInfoLoaded_[userId] then
        return
    end

    if not serverCloud then
        return
    end

    -- 获取玩家当前区服ID，使用区服前缀 key 查询
    local sid = userServerId_[userId] or 0
    local rk = function(base) return PlayerMgr.RealmKey(base, sid) end

    -- 必须使用 BatchGet 查询多个 key（serverCloud:Get 只支持单个 key）
    -- playerName/playerGender/playerId 由 clientCloud:Set() 写入 → 在 scores
    -- realmLevel 由 clientCloud:SetInt() 写入 → 在 iscores
    serverCloud:BatchGet(userId)
        :Key(rk("playerName"))
        :Key(rk("playerGender"))
        :Key(rk("playerId"))
        :Key(rk("realmLevel"))
        :Fetch({
            ok = function(scores, iscores)
                scores = scores or {}
                iscores = iscores or {}
                local name = scores[rk("playerName")]
                local hasRealName = (name ~= nil and name ~= "")
                ChatServer.UpdatePlayerInfo(userId, {
                    name     = hasRealName and name or "无名修士",
                    gender   = scores[rk("playerGender")] or "male",
                    playerId = scores[rk("playerId")] or "000000",
                    realm    = tonumber(iscores[rk("realmLevel")]) or 0,
                })
                -- 只有获取到真实名称后才标记为已加载，否则允许下次重试
                if hasRealName then
                    playerInfoLoaded_[userId] = true
                end
            end,
            error = function(code, reason)
                print("[Server] 获取玩家信息失败: uid=" .. tostring(userId)
                    .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
            end,
        })
end
