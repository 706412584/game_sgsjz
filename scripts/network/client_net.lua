------------------------------------------------------------
-- network/client_net.lua — 三国神将录 客户端网络模块
-- 职责：远程事件订阅、发送封装、服务端回调中转
-- 纯中转层，不含业务逻辑
------------------------------------------------------------

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS

local M = {}

------------------------------------------------------------
-- 连接状态
------------------------------------------------------------

local connected_         = false   -- 当前是否已连接
local serverConnection_  = nil     -- Connection 对象
local initialConnected_  = false   -- 是否曾经连接成功过
local everDisconnected_  = false   -- 是否经历过断线
local kicked_            = false   -- 是否被踢下线
local pendingReconnect_  = false   -- 等 GameInit 到达才算重连成功
local clientReadySent_   = false   -- 本次周期是否已发 CLIENT_READY

------------------------------------------------------------
-- 回调注册（由 client_main.lua 设置）
------------------------------------------------------------

local disconnectCallback_  = nil   ---@type fun()|nil
local reconnectCallback_   = nil   ---@type fun()|nil
local kickedCallback_      = nil   ---@type fun(reason:string)|nil

M.gameInitReceived_        = false
M.onGameInitCallback_      = nil   ---@type fun()|nil
M.onServerSwitchCallback_  = nil   ---@type fun()|nil

------------------------------------------------------------
-- 初始化
------------------------------------------------------------

function M.Init()
    if not IsNetworkMode() then
        print("[ClientNet] 非网络模式，跳过初始化")
        return
    end

    print("[ClientNet] Init: 注册远程事件...")
    Shared.RegisterClientEvents()

    -- 订阅服务端 → 客户端事件
    SubscribeToEvent(EVENTS.GAME_INIT,       "HandleGameInit")
    SubscribeToEvent(EVENTS.GAME_SYNC,       "HandleGameSync")
    SubscribeToEvent(EVENTS.GAME_EVT,        "HandleGameEvt")
    SubscribeToEvent(EVENTS.SERVER_LIST_RESP, "HandleServerListResp")
    SubscribeToEvent(EVENTS.KICKED,          "HandleKicked")

    -- 订阅连接生命周期
    SubscribeToEvent("ServerReady",        "HandleServerReady")
    SubscribeToEvent("ServerConnected",    "HandleServerConnected")
    SubscribeToEvent("ServerDisconnected", "HandleServerDisconnected")

    -- persistent_world: 启动时连接可能已就绪
    local conn = network.serverConnection
    if conn then
        connected_ = true
        serverConnection_ = conn
        print("[ClientNet] 启动时服务器已就绪")
        M._sendClientReady()
    else
        print("[ClientNet] 等待 ServerConnected 事件...")
    end

    print("[ClientNet] 初始化完成")
end

------------------------------------------------------------
-- 内部：发送 CLIENT_READY
------------------------------------------------------------

function M._sendClientReady()
    if not serverConnection_ then return end
    if clientReadySent_ then return end
    clientReadySent_ = true
    local vm = VariantMap()
    serverConnection_:SendRemoteEvent(EVENTS.CLIENT_READY, true, vm)
    print("[ClientNet] 已发送 CLIENT_READY")
end

------------------------------------------------------------
-- 连接生命周期
------------------------------------------------------------

function HandleServerReady(eventType, eventData)
    connected_ = true
    initialConnected_ = true
    serverConnection_ = network.serverConnection
    print("[ClientNet] ServerReady, kicked=" .. tostring(kicked_))

    if kicked_ then return end

    -- 重连 → 重发 CLIENT_READY
    if everDisconnected_ then
        pendingReconnect_ = true
        everDisconnected_ = false
        clientReadySent_ = false
    end
    M._sendClientReady()
end

function HandleServerConnected(eventType, eventData)
    connected_ = true
    initialConnected_ = true
    serverConnection_ = network.serverConnection
    print("[ClientNet] ServerConnected, kicked=" .. tostring(kicked_))

    if kicked_ then return end

    M._sendClientReady()

    if everDisconnected_ then
        pendingReconnect_ = true
        everDisconnected_ = false
    end
end

function HandleServerDisconnected(eventType, eventData)
    local wasConn = connected_
    connected_ = false
    serverConnection_ = nil
    clientReadySent_ = false
    pendingReconnect_ = false
    print("[ClientNet] ServerDisconnected, kicked=" .. tostring(kicked_))

    if kicked_ then return end

    if wasConn or initialConnected_ then
        everDisconnected_ = true
    end
    if wasConn and disconnectCallback_ then
        disconnectCallback_()
    end
end

------------------------------------------------------------
-- 公开 API: 连接状态
------------------------------------------------------------

---@return boolean
function M.IsConnected()
    return connected_
end

---@return boolean
function M.IsKicked()
    return kicked_
end

------------------------------------------------------------
-- 公开 API: 发送远程事件
------------------------------------------------------------

--- 向服务端发送远程事件
---@param eventName string  事件名（Shared.EVENTS.*）
---@param data? VariantMap
---@return boolean
function M.SendToServer(eventName, data)
    if not connected_ or not serverConnection_ then
        print("[ClientNet] 未连接，无法发送: " .. eventName)
        return false
    end
    data = data or VariantMap()
    serverConnection_:SendRemoteEvent(eventName, true, data)
    return true
end

--- 发送 GAME_ACTION 便捷封装
---@param action string   Action 名称
---@param payload? table  数据表（自动 JSON 编码）
---@return boolean
function M.SendAction(action, payload)
    local vm = VariantMap()
    vm["Action"] = Variant(action)
    if payload then
        vm["Data"] = Variant(cjson.encode(payload))
    end
    return M.SendToServer(EVENTS.GAME_ACTION, vm)
end

------------------------------------------------------------
-- 服务端 → 客户端事件处理
------------------------------------------------------------

local gameSyncCount_ = 0

--- 全量状态同步（周期推送）
function HandleGameSync(eventType, eventData)
    gameSyncCount_ = gameSyncCount_ + 1
    if gameSyncCount_ <= 3 then
        print("[ClientNet] HandleGameSync #" .. gameSyncCount_)
    end
    local stateJson = eventData["StateJson"]:GetString()
    local ok, stateTable = pcall(cjson.decode, stateJson)
    if not ok or not stateTable then
        print("[ClientNet] GameSync decode error")
        return
    end
    local State = require("data.data_state")
    State.ApplyServerSync(stateTable)
end

--- 登录初始化
function HandleGameInit(eventType, eventData)
    print("[ClientNet] >>> HandleGameInit <<<")
    local stateJson = eventData["StateJson"]:GetString()
    print("[ClientNet] GameInit 数据长度: " .. #stateJson)

    local ok, stateTable = pcall(cjson.decode, stateJson)
    if not ok or not stateTable then
        print("[ClientNet] GameInit decode error: " .. tostring(stateTable))
        return
    end

    -- 换服检测
    local State = require("data.data_state")
    local isServerSwitch = false
    if M.gameInitReceived_ and State.state then
        local oldSid = State.state.serverId or 0
        local newSid = stateTable.serverId or 0
        if newSid ~= oldSid then
            isServerSwitch = true
            print("[ClientNet] 换服: " .. oldSid .. " -> " .. newSid)
        end
    end

    -- 应用完整状态
    State.ApplyServerInit(stateTable)

    -- 触发回调
    local wasReceived = M.gameInitReceived_
    M.gameInitReceived_ = true

    if M.onGameInitCallback_ then
        print("[ClientNet] 触发 onGameInitCallback_")
        M.onGameInitCallback_()
        M.onGameInitCallback_ = nil
    elseif isServerSwitch and M.onServerSwitchCallback_ then
        print("[ClientNet] 触发 onServerSwitchCallback_ (换服)")
        M.onServerSwitchCallback_()
    elseif wasReceived and M.onServerSwitchCallback_ then
        print("[ClientNet] 触发 onServerSwitchCallback_ (身份升级)")
        M.onServerSwitchCallback_()
    end

    -- 重连确认
    if pendingReconnect_ then
        pendingReconnect_ = false
        clientReadySent_ = false
        print("[ClientNet] 重连确认成功")
        if reconnectCallback_ then
            reconnectCallback_()
        end
    end
end

--- 即时事件推送
function HandleGameEvt(eventType, eventData)
    local evtType = eventData["Type"]:GetString()
    local dataJson = eventData["DataJson"]:GetString()
    local ok, data = pcall(cjson.decode, dataJson)
    if not ok then data = {} end
    print("[ClientNet] GameEvt: " .. evtType)

    -- 转发到业务模块（后续由 client_main.lua 注册处理器）
    if M.onGameEvtCallback_ then
        M.onGameEvtCallback_(evtType, data)
    end
end

--- 区服列表响应
function HandleServerListResp(eventType, eventData)
    print("[ClientNet] 收到区服列表")
    if M.onServerListCallback_ then
        local json = eventData["ListJson"]:GetString()
        local ok, list = pcall(cjson.decode, json)
        M.onServerListCallback_(ok and list or {})
    end
end

--- 被踢下线
function HandleKicked(eventType, eventData)
    local reason = eventData["Reason"]
        and eventData["Reason"]:GetString() or "unknown"
    print("[ClientNet] 被踢: " .. reason)
    kicked_ = true
    if kickedCallback_ then
        kickedCallback_(reason)
    end
end

------------------------------------------------------------
-- 回调注册 API
------------------------------------------------------------

--- GameInit 到达回调（已到达则立即执行）
---@param callback fun()
function M.OnGameInit(callback)
    if M.gameInitReceived_ then
        callback()
    else
        M.onGameInitCallback_ = callback
    end
end

--- 换服回调（持久，每次换服触发）
---@param callback fun()
function M.OnServerSwitch(callback)
    M.onServerSwitchCallback_ = callback
end

--- 断线回调
---@param callback fun()
function M.OnDisconnect(callback)
    disconnectCallback_ = callback
end

--- 重连回调
---@param callback fun()
function M.OnReconnect(callback)
    reconnectCallback_ = callback
end

--- 被踢回调
---@param callback fun(reason:string)
function M.OnKicked(callback)
    kickedCallback_ = callback
end

--- GameEvt 转发回调
---@param callback fun(evtType:string, data:table)
function M.OnGameEvt(callback)
    M.onGameEvtCallback_ = callback
end

--- 区服列表回调
---@param callback fun(list:table)
function M.OnServerList(callback)
    M.onServerListCallback_ = callback
end

--- 是否已收到 GameInit
---@return boolean
function M.IsGameInitReceived()
    return M.gameInitReceived_
end

--- 主动重试：重发 CLIENT_READY
---@return boolean
function M.RetryClientReady()
    if connected_ and serverConnection_ and pendingReconnect_ then
        clientReadySent_ = false
        M._sendClientReady()
        print("[ClientNet] 重试 CLIENT_READY")
        return true
    end
    return false
end

return M
