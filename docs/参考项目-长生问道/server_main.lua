-- ============================================================================
-- 《问道长生》服务端入口
-- 职责：连接管理 + serverCloud.list 寄售中转 + serverCloud.message 邮件中转
--       + 聊天系统 + 统一游戏网关
-- 架构：云变量方案（薄服务端，不管货币）
-- ============================================================================

local Shared           = require("network.shared")
local EVENTS           = Shared.EVENTS
local ServerMarket     = require("network.server_market")
local ServerSocial     = require("network.server_social")
local ServerCloudProxy = require("network.server_cloud_proxy")
local ServerOnline     = require("network.server_online")
local ServerGame       = require("network.server_game")
local ChatServer       = require("network.chat_server")
local ServerSect       = require("network.server_sect")
local ServerBoss       = require("network.server_boss")

require "LuaScripts/Utilities/Sample"

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

---@type table<string, any>   connKey -> Connection
local connections_  = {}
---@type table<string, number> connKey -> userId
local connUserIds_  = {}
---@type table<number, string> userId -> connKey（反查）
local userIdToConn_ = {}

local scene_ = nil

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 向指定玩家发送远程事件
---@param userId number
---@param eventName string
---@param data any VariantMap
function SendToClient(userId, eventName, data)
    local connKey = userIdToConn_[userId]
    if not connKey then return end
    local conn = connections_[connKey]
    if not conn then return end
    conn:SendRemoteEvent(eventName, true, data)
end

--- 获取所有在线用户 ID 列表
---@return number[]
local function GetOnlineUsers()
    local users = {}
    for _, uid in pairs(connUserIds_) do
        users[#users + 1] = uid
    end
    return users
end

--- 向所有在线玩家广播
---@param eventName string
---@param data any VariantMap
local function BroadcastToAll(eventName, data)
    for _, conn in pairs(connections_) do
        conn:SendRemoteEvent(eventName, true, data)
    end
end

-- ============================================================================
-- 入口
-- ============================================================================

function Start()
    SampleStart()

    scene_ = Scene()
    scene_:CreateComponent("Octree")

    -- 注册远程事件
    Shared.RegisterServerEvents()

    -- 订阅连接事件
    SubscribeToEvent(EVENTS.REQ_MARKET_OP,  "HandleReqMarketOp")
    SubscribeToEvent(EVENTS.REQ_MAIL_FETCH, "HandleReqMailFetch")
    SubscribeToEvent(EVENTS.REQ_MAIL_CLAIM, "HandleReqMailClaim")
    SubscribeToEvent(EVENTS.CLOUD_REQ,      "HandleCloudReq")
    SubscribeToEvent(EVENTS.REQ_SOCIAL_OP,  "HandleReqSocialOp")
    SubscribeToEvent(EVENTS.REQ_SERVER_ONLINE, "HandleReqServerOnline")
    SubscribeToEvent(EVENTS.REQ_GM_SERVER_OP, "HandleReqGMServerOp")
    SubscribeToEvent(EVENTS.REQ_GAME_OP,    "HandleReqGameOp")
    SubscribeToEvent(EVENTS.REQ_SECT_OP,   "HandleReqSectOp")
    SubscribeToEvent(EVENTS.REQ_BOSS_OP,   "HandleReqBossOp")
    SubscribeToEvent("ClientDisconnected",  "HandleClientDisconnected")

    -- 聊天事件
    SubscribeToEvent(EVENTS.CHAT_JOIN,    "HandleChatJoin")
    SubscribeToEvent(EVENTS.CHAT_SEND,    "HandleChatSend")
    SubscribeToEvent(EVENTS.CHAT_PRIVATE, "HandleChatPrivate")
    SubscribeToEvent(EVENTS.CHAT_QUERY_ONLINE, "HandleChatQueryOnline")
    SubscribeToEvent(EVENTS.CHAT_RECALL, "HandleChatRecall")

    -- 帧更新
    SubscribeToEvent("Update", "HandleUpdate")

    -- 初始化寄售坊模块
    ServerMarket.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化社交模块
    ServerSocial.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化云代理模块（clientCloud polyfill 后端）
    ServerCloudProxy.Init({
        SendToClient = SendToClient,
    })

    -- 初始化在线人数追踪模块
    ServerOnline.Init({
        SendToClient = SendToClient,
    })

    -- 初始化统一游戏网关
    ServerGame.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化宗门模块
    ServerSect.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化组队Boss模块
    ServerBoss.Init({
        connections    = connections_,
        connUserIds    = connUserIds_,
        userIdToConn   = userIdToConn_,
        SendToClient   = SendToClient,
    })

    -- 初始化聊天模块
    ChatServer.Init({
        SendToClient   = SendToClient,
        GetOnlineUsers = GetOnlineUsers,
    })

    print("[Server] 《问道长生》服务端已启动（云变量方案 + 云代理 + 游戏网关 + 聊天）")
    print("[Server] serverCloud available: " .. tostring(serverCloud ~= nil))
end

function Stop()
    print("[Server] 服务端关闭")
end

-- ============================================================================
-- 帧更新
-- ============================================================================

function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()
    ChatServer.Update(dt)
    ServerBoss.Update(dt)
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
        local userId = 10001
        local identityUid = connection.identity["user_id"]
        if identityUid then
            userId = identityUid:GetInt64()
        end

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
            ServerMarket.UnloadPlayerListings(userId)
        end

        connections_[connKey]  = connection
        connUserIds_[connKey]  = userId
        userIdToConn_[userId]  = connKey
        print("[Server] 玩家连接: userId=" .. tostring(userId))

        -- 加载玩家寄售到聚合表
        ServerMarket.LoadPlayerListings(userId)
    end

    return connUserIds_[connKey], connKey
end

function HandleClientDisconnected(eventType, eventData)
    local connection = eventData:GetPtr("Connection", "Connection")
    local connKey = tostring(connection)
    local userId = connUserIds_[connKey]

    connections_[connKey]  = nil
    connUserIds_[connKey]  = nil
    if userId then
        userIdToConn_[userId] = nil
        ServerMarket.UnloadPlayerListings(userId)
        ServerOnline.PlayerLeave(userId)
        ServerGame.CleanupPlayer(userId)
        ServerBoss.CleanupPlayer(userId)
        ChatServer.OnPlayerDisconnect(userId)
    end

    print("[Server] 玩家断开: userId=" .. tostring(userId))
end

-- ============================================================================
-- 请求处理：寄售操作（统一入口）
-- ============================================================================

function HandleReqMarketOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerMarket.HandleMarketOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：社交操作（统一入口）
-- ============================================================================

function HandleReqSocialOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerSocial.HandleSocialOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：宗门操作（统一入口）
-- ============================================================================

function HandleReqSectOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerSect.HandleSectOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：组队Boss操作（统一入口）
-- ============================================================================

function HandleReqBossOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerBoss.HandleBossOp(userId, eventData)
end

-- ============================================================================
-- 请求处理：区服在线人数
-- ============================================================================

function HandleReqServerOnline(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerOnline.HandleReqServerOnline(userId, eventData)
end

-- ============================================================================
-- 请求处理：[GM] 区服管理
-- ============================================================================

function HandleReqGMServerOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerOnline.CheckGMAuth(userId, function(ok, reason)
        if ok then
            ServerOnline.HandleGMServerOp(userId, eventData)
        else
            print("[Server] GM 权限拒绝 uid=" .. tostring(userId) .. " reason=" .. tostring(reason))
            ServerOnline.ReplyGMUnauthorized(userId, reason)
        end
    end)
end

-- ============================================================================
-- 请求处理：统一游戏操作（server_game 网关）
-- ============================================================================

function HandleReqGameOp(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ServerGame.HandleGameOp(userId, eventData)
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
-- 请求处理：聊天
-- ============================================================================

function HandleChatJoin(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleChatJoin(userId, eventData)
end

function HandleChatSend(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleChatSend(userId, eventData)
end

function HandleChatPrivate(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleChatPrivate(userId, eventData)
end

function HandleChatQueryOnline(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleChatQueryOnline(userId, eventData)
end

function HandleChatRecall(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end
    ChatServer.HandleChatRecall(userId, eventData)
end

-- ============================================================================
-- 请求处理：邮件
-- ============================================================================

--- 拉取未读邮件
function HandleReqMailFetch(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end

    if not serverCloud then
        print("[Server] serverCloud 不可用，无法拉取邮件")
        return
    end

    serverCloud.message:Get(userId, "trade", false, {
        ok = function(messages)
            ---@diagnostic disable-next-line: undefined-global
            local cjson = cjson
            local data = VariantMap()
            data["Data"] = Variant(cjson.encode(messages or {}))
            SendToClient(userId, EVENTS.MAIL_DATA, data)
            print("[Server] 发送 " .. #(messages or {}) .. " 封邮件给 uid=" .. tostring(userId))
        end,
        error = function(code, reason)
            print("[Server] 邮件拉取失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
            local data = VariantMap()
            data["Data"] = Variant("[]")
            SendToClient(userId, EVENTS.MAIL_DATA, data)
        end,
    })
end

--- 领取邮件（标记已读 + 删除）
function HandleReqMailClaim(eventType, eventData)
    local userId = GetSender(eventData)
    if not userId then return end

    local messageIdStr = eventData["MessageId"]:GetString()
    local messageId = tonumber(messageIdStr) or 0

    if not serverCloud or messageId == 0 then
        local data = VariantMap()
        data["Success"]   = Variant(false)
        data["MessageId"] = Variant(messageIdStr)
        data["Msg"]       = Variant("无效的邮件")
        SendToClient(userId, EVENTS.MAIL_CLAIMED, data)
        return
    end

    serverCloud.message:MarkRead(messageId)
    serverCloud.message:Delete(messageId)

    local data = VariantMap()
    data["Success"]   = Variant(true)
    data["MessageId"] = Variant(messageIdStr)
    data["Msg"]       = Variant("领取成功")
    SendToClient(userId, EVENTS.MAIL_CLAIMED, data)

    print("[Server] 邮件领取 uid=" .. tostring(userId) .. " msgId=" .. messageIdStr)
end
