------------------------------------------------------------
-- server_main.lua — 三国神将录 服务端入口
-- 职责：连接管理、身份升级、区服选择、事件路由
-- 业务逻辑在 server_game.lua
------------------------------------------------------------

---@diagnostic disable: undefined-global

local Shared     = require("network.shared")
local EVENTS     = Shared.EVENTS
local ServerGame = require("server_game")

require "LuaScripts/Utilities/Sample"

------------------------------------------------------------
-- Mock graphics (headless 模式)
------------------------------------------------------------
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

------------------------------------------------------------
-- 连接状态
------------------------------------------------------------

---@type table<string, any>    connKey -> Connection
local connections_  = {}
---@type table<string, number> connKey -> userId
local connUserIds_  = {}
---@type table<number, string> userId -> connKey
local userIdToConn_ = {}
---@type table<number, number> userId -> serverId
local userServerId_ = {}

local nextAnonId_ = 10001
local clientReadyReceived_ = {}

-- 区服列表
local serverList_ = {}
local CLOUD_SERVER_LIST_KEY = "server_list"
local GLOBAL_USER_ID = 0

local scene_ = nil

------------------------------------------------------------
-- 入口
------------------------------------------------------------

function Start()
    SampleStart()

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    Shared.RegisterServerEvents()

    -- 连接生命周期
    SubscribeToEvent("ClientConnected",    "HandleClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleClientDisconnected")

    -- 客户端请求
    SubscribeToEvent(EVENTS.CLIENT_READY,    "HandleClientReady")
    SubscribeToEvent(EVENTS.GAME_ACTION,     "HandleGameAction")
    SubscribeToEvent(EVENTS.APP_BG,          "HandleAppBg")
    SubscribeToEvent(EVENTS.SERVER_LIST_REQ, "HandleServerListReq")
    SubscribeToEvent(EVENTS.SERVER_SELECT,   "HandleServerSelect")

    SubscribeToEvent("Update", "HandleUpdate")

    -- 初始化游戏模块
    ServerGame.Init({
        SendToClient = SendToClient,
    })

    LoadServerList()

    print("[Server] 三国神将录 服务端已启动")
    print("[Server] serverCloud: " .. tostring(serverCloud ~= nil))
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    ServerGame.Update(dt)
end

function Stop()
    print("[Server] 服务端关闭, 保存所有在线玩家...")
    ServerGame.SaveAll()
end

------------------------------------------------------------
-- 连接管理
------------------------------------------------------------

--- 从 eventData 提取 userId, 首次连接时自动注册
---@param eventData any
---@return number|nil userId
---@return string|nil connKey
local function GetSender(eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)

    if connUserIds_[connKey] then
        return connUserIds_[connKey], connKey
    end

    -- 新连接: 提取 userId
    local userId
    local identityUid = connection.identity["user_id"]
    if identityUid then
        userId = tonumber(identityUid:GetInt64())
    else
        userId = nextAnonId_
        nextAnonId_ = nextAnonId_ + 1
    end

    -- 踢重复登录
    local oldConnKey = userIdToConn_[userId]
    if oldConnKey and oldConnKey ~= connKey then
        local oldConn = connections_[oldConnKey]
        if oldConn then
            local kickData = VariantMap()
            kickData["Reason"] = Variant("duplicate_login")
            oldConn:SendRemoteEvent(EVENTS.KICKED, true, kickData)
            oldConn:Disconnect(100)
        end
        connections_[oldConnKey] = nil
        connUserIds_[oldConnKey] = nil
        ServerGame.OnPlayerDisconnect(userId)
    end

    connections_[connKey]  = connection
    connUserIds_[connKey]  = userId
    userIdToConn_[userId]  = connKey

    print("[Server] 玩家连接: uid=" .. tostring(userId))
    return userId, connKey
end

------------------------------------------------------------
-- 连接生命周期事件
------------------------------------------------------------

function HandleClientConnected(eventType, eventData)
    local userId = GetSender(eventData)
    print("[Server] ClientConnected: uid=" .. tostring(userId))
end

function HandleClientReady(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local oldUserId = connUserIds_[connKey]
    if not oldUserId then return end

    -- 身份升级
    local identityUid = connection.identity["user_id"]
    if identityUid then
        local realUserId = tonumber(identityUid:GetInt64())
        if realUserId and realUserId ~= oldUserId then
            print("[Server] 身份升级: " .. oldUserId .. " -> " .. realUserId)

            -- 踢真实 ID 的旧连接
            local existKey = userIdToConn_[realUserId]
            if existKey and existKey ~= connKey then
                local existConn = connections_[existKey]
                if existConn then
                    local kd = VariantMap()
                    kd["Reason"] = Variant("duplicate_login")
                    existConn:SendRemoteEvent(EVENTS.KICKED, true, kd)
                    existConn:Disconnect(100)
                end
                connections_[existKey] = nil
                connUserIds_[existKey] = nil
                ServerGame.OnPlayerDisconnect(realUserId)
            end

            -- 清理临时 ID
            userIdToConn_[oldUserId] = nil
            userServerId_[oldUserId] = nil
            clientReadyReceived_[oldUserId] = nil
            ServerGame.ForceRemovePlayer(oldUserId)

            -- 更新映射
            connUserIds_[connKey] = realUserId
            userIdToConn_[realUserId] = connKey
            userServerId_[realUserId] = nil

            print("[Server] 身份升级完成, 等选服: uid=" .. tostring(realUserId))
            return
        end
    end

    -- 正常流程: 数据已加载且已选服 → 重发 GameInit
    local userId = oldUserId
    local sid = userServerId_[userId] or 0
    if ServerGame.IsLoaded(userId) and sid > 0 then
        ServerGame.SendGameInit(userId)
        print("[Server] ClientReady: 重发 GameInit uid=" .. tostring(userId))
    elseif ServerGame.IsLoaded(userId) and sid == 0 then
        print("[Server] ClientReady: 已加载但 sid=0, 等选服 uid=" .. tostring(userId))
    else
        clientReadyReceived_[userId] = true
        print("[Server] ClientReady: 数据加载中, 标记待发 uid=" .. tostring(userId))
    end
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
        ServerGame.OnPlayerDisconnect(userId)
    end
    print("[Server] 玩家断开: uid=" .. tostring(userId))
end

------------------------------------------------------------
-- 向客户端发送
------------------------------------------------------------

---@param userId number
---@param eventName string
---@param data VariantMap
function SendToClient(userId, eventName, data)
    local connKey = userIdToConn_[userId]
    if not connKey then return end
    local conn = connections_[connKey]
    if not conn then return end
    conn:SendRemoteEvent(eventName, true, data)
end

------------------------------------------------------------
-- GAME_ACTION 路由
------------------------------------------------------------

function HandleGameAction(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local action   = eventData["Action"]:GetString()
    local dataJson = eventData["Data"] and eventData["Data"]:GetString() or ""
    ServerGame.HandleAction(userId, action, dataJson)
end

function HandleAppBg(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local fg = eventData["Foreground"]:GetBool()
    if not fg then
        ServerGame.SavePlayer(userId)
    end
end

------------------------------------------------------------
-- 区服管理
------------------------------------------------------------

function LoadServerList()
    if not serverCloud then
        serverList_ = { { id = 1, name = "群雄逐鹿", status = "open" } }
        return
    end
    serverCloud:Get(GLOBAL_USER_ID, CLOUD_SERVER_LIST_KEY, {
        ok = function(values)
            local raw = values and values[CLOUD_SERVER_LIST_KEY]
            if raw and raw ~= "" then
                local ok, list = pcall(cjson.decode, raw)
                if ok and type(list) == "table" then
                    serverList_ = list
                    print("[Server] 加载 " .. #serverList_ .. " 个区服")
                    return
                end
            end
            serverList_ = { { id = 1, name = "群雄逐鹿", status = "open" } }
            SaveServerList()
        end,
        error = function(_, reason)
            print("[Server] 区服加载失败: " .. tostring(reason))
            serverList_ = { { id = 1, name = "群雄逐鹿", status = "open" } }
        end,
    })
end

function SaveServerList()
    if not serverCloud then return end
    serverCloud:Set(GLOBAL_USER_ID, CLOUD_SERVER_LIST_KEY, cjson.encode(serverList_), {
        ok = function() end,
        error = function(_, reason)
            print("[Server] 区服保存失败: " .. tostring(reason))
        end,
    })
end

function HandleServerListReq(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    if not connUserIds_[connKey] then
        GetSender(eventData)
    end
    local data = VariantMap()
    data["ListJson"] = Variant(cjson.encode(serverList_))
    connection:SendRemoteEvent(EVENTS.SERVER_LIST_RESP, true, data)
end

function HandleServerSelect(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    local serverId = eventData["ServerId"]:GetInt()
    local oldSid = userServerId_[userId] or 0
    userServerId_[userId] = serverId
    print("[Server] 选服: uid=" .. tostring(userId)
        .. " " .. oldSid .. " -> " .. serverId)

    if oldSid == serverId and ServerGame.IsLoaded(userId) then
        ServerGame.SendGameInit(userId)
        return
    end

    -- 换区: 先保存旧区, 再加载新区
    local function loadNew()
        ServerGame.LoadPlayer(userId, serverId, function(success)
            if success then
                local ready = clientReadyReceived_[userId]
                clientReadyReceived_[userId] = nil
                ServerGame.SendGameInit(userId)
            else
                local connKey = userIdToConn_[userId]
                local conn = connKey and connections_[connKey]
                if conn then
                    local ed = VariantMap()
                    ed["Reason"] = Variant("load_failed")
                    conn:SendRemoteEvent(EVENTS.KICKED, true, ed)
                end
            end
        end)
    end

    if oldSid ~= 0 and ServerGame.IsLoaded(userId) then
        ServerGame.SavePlayer(userId, function()
            ServerGame.ForceRemovePlayer(userId)
            loadNew()
        end)
    else
        ServerGame.ForceRemovePlayer(userId)
        loadNew()
    end
end
