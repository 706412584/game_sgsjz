-- ============================================================================
-- server_manager.lua — 区服管理服务端
-- 使用 serverCloud 存储区服列表，GM 可增删改状态
-- ============================================================================
---@diagnostic disable: undefined-global

local M = {}

-- ========== 事件名 ==========
M.EVENTS = {
    -- 客户端 → 服务端
    SERVER_LIST_REQ  = "ServerListReq",   -- 请求区服列表
    SERVER_ADD       = "ServerAdd",       -- GM添加区服
    SERVER_REMOVE    = "ServerRemove",    -- GM删除区服
    SERVER_UPDATE    = "ServerUpdate",    -- GM修改区服状态
    -- 服务端 → 客户端
    SERVER_LIST_RESP = "ServerListResp",  -- 返回区服列表
    SERVER_OP_RESULT = "ServerOpResult",  -- 操作结果
}

-- 区服数据(运行时缓存)
local serverList_ = {}
-- 格式: { { id = 1, name = "仙域一区", status = "正常" }, ... }

-- 连接管理(复用 mail_server 的连接, 或独立管理)
local connections_ = {}    -- connKey -> connection
local connUserIds_ = {}    -- connKey -> userId

-- GM 用户 ID 列表
local GM_USER_IDS = { [1644503283] = true, [529757584] = true }

-- serverCloud key
local SERVERS_KEY = "server_list"
-- 全局数据使用特殊用户ID(serverCloud API 要求 userId)
local GLOBAL_USER_ID = 0

-- ========== 注册远程事件 ==========
function M.RegisterEvents()
    for _, eventName in pairs(M.EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[ServerMgr] Remote events registered")
end

-- ========== 初始化 ==========
function M.Init()
    M.RegisterEvents()

    -- 监听事件
    SubscribeToEvent("ClientConnected", "HandleSvrClientConnected")
    SubscribeToEvent("ClientDisconnected", "HandleSvrClientDisconnected")
    SubscribeToEvent(M.EVENTS.SERVER_LIST_REQ, "HandleServerListReq")
    SubscribeToEvent(M.EVENTS.SERVER_ADD,      "HandleServerAdd")
    SubscribeToEvent(M.EVENTS.SERVER_REMOVE,   "HandleServerRemove")
    SubscribeToEvent(M.EVENTS.SERVER_UPDATE,   "HandleServerUpdate")

    -- 加载持久化的区服列表
    M.LoadServerList()

    print("[ServerMgr] Initialized")
end

-- ========== 连接管理 ==========

function HandleSvrClientConnected(eventType, eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local userId = 0
    local identityUid = connection.identity["user_id"]
    if identityUid then
        userId = identityUid:GetInt64()
    end
    connections_[connKey] = connection
    connUserIds_[connKey] = userId
end

function HandleSvrClientDisconnected(eventType, eventData)
    local connection = eventData:GetPtr("Connection", "Connection")
    local connKey = tostring(connection)
    connections_[connKey] = nil
    connUserIds_[connKey] = nil
end

-- ========== 持久化 ==========

--- 从 serverCloud 加载区服列表
function M.LoadServerList()
    serverCloud:Get(GLOBAL_USER_ID, SERVERS_KEY, {
        ok = function(values, iscores)
            if values and values[SERVERS_KEY] then
                -- cjson 是引擎内置全局变量，直接使用
                local ok, data = pcall(cjson.decode, values[SERVERS_KEY])
                if ok and type(data) == "table" then
                    serverList_ = data
                    print("[ServerMgr] Loaded " .. #serverList_ .. " servers from cloud")
                else
                    print("[ServerMgr] Failed to decode server list, using defaults")
                    M.CreateDefaultServers()
                end
            else
                print("[ServerMgr] No server list in cloud, creating defaults")
                M.CreateDefaultServers()
            end
        end,
        error = function(code, reason)
            print("[ServerMgr] Load error: " .. tostring(code) .. " " .. tostring(reason))
            M.CreateDefaultServers()
        end,
    })
end

--- 创建默认区服
function M.CreateDefaultServers()
    serverList_ = {
        { id = 1, name = "仙域一区", status = "正常" },
        { id = 2, name = "灵山二区", status = "正常" },
    }
    M.SaveServerList()
end

--- 保存区服列表到 serverCloud
function M.SaveServerList()
    -- cjson 是引擎内置全局变量，直接使用
    local jsonStr = cjson.encode(serverList_)
    serverCloud:Set(GLOBAL_USER_ID, SERVERS_KEY, jsonStr, {
        ok = function()
            print("[ServerMgr] Server list saved to cloud")
        end,
        error = function(code, reason)
            print("[ServerMgr] Save error: " .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

-- ========== 工具函数 ==========

---@param eventData table
---@return userdata|nil conn
---@return number userId
---@return string connKey
local function extractConn(eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local userId = connUserIds_[connKey]
    return connection, userId, connKey
end

local function sendResult(conn, action, success, message)
    local data = VariantMap()
    data["Action"]  = Variant(action)
    data["Success"] = Variant(success)
    data["Message"] = Variant(message or "")
    conn:SendRemoteEvent(M.EVENTS.SERVER_OP_RESULT, true, data)
end

--- 获取下一个可用的区服 ID
---@return number
local function nextServerId()
    local maxId = 0
    for _, srv in ipairs(serverList_) do
        if srv.id > maxId then maxId = srv.id end
    end
    return maxId + 1
end

-- ========== 请求区服列表 ==========

function HandleServerListReq(eventType, eventData)
    local conn, userId, connKey = extractConn(eventData)
    if not conn then return end

    -- cjson 是引擎内置全局变量，直接使用
    local jsonStr = cjson.encode(serverList_)
    local data = VariantMap()
    data["ServerJson"] = Variant(jsonStr)
    data["Count"]      = Variant(#serverList_)
    conn:SendRemoteEvent(M.EVENTS.SERVER_LIST_RESP, true, data)
    print("[ServerMgr] Sent server list to uid=" .. tostring(userId))
end

-- ========== GM: 添加区服 ==========

function HandleServerAdd(eventType, eventData)
    local conn, userId = extractConn(eventData)
    if not userId or not GM_USER_IDS[userId] then
        if conn then sendResult(conn, "add", false, "无权限") end
        return
    end

    local name = eventData["Name"]:GetString()
    if name == "" then
        sendResult(conn, "add", false, "名称不能为空")
        return
    end

    local newServer = {
        id = nextServerId(),
        name = name,
        status = "正常",
    }
    table.insert(serverList_, newServer)
    M.SaveServerList()
    sendResult(conn, "add", true, "已添加: " .. name .. " (ID:" .. newServer.id .. ")")
    print("[ServerMgr] Added server: " .. name)
end

-- ========== GM: 删除区服 ==========

function HandleServerRemove(eventType, eventData)
    local conn, userId = extractConn(eventData)
    if not userId or not GM_USER_IDS[userId] then
        if conn then sendResult(conn, "remove", false, "无权限") end
        return
    end

    local serverId = eventData["ServerId"]:GetInt()
    for i, srv in ipairs(serverList_) do
        if srv.id == serverId then
            table.remove(serverList_, i)
            M.SaveServerList()
            sendResult(conn, "remove", true, "已删除区服 ID:" .. serverId)
            print("[ServerMgr] Removed server ID:" .. serverId)
            return
        end
    end
    sendResult(conn, "remove", false, "未找到区服 ID:" .. serverId)
end

-- ========== GM: 修改区服状态 ==========

function HandleServerUpdate(eventType, eventData)
    local conn, userId = extractConn(eventData)
    if not userId or not GM_USER_IDS[userId] then
        if conn then sendResult(conn, "update", false, "无权限") end
        return
    end

    local serverId  = eventData["ServerId"]:GetInt()
    local newStatus = eventData["Status"]:GetString()

    for _, srv in ipairs(serverList_) do
        if srv.id == serverId then
            srv.status = newStatus
            M.SaveServerList()
            sendResult(conn, "update", true, srv.name .. " 状态已改为: " .. newStatus)
            print("[ServerMgr] Updated server " .. srv.name .. " → " .. newStatus)
            return
        end
    end
    sendResult(conn, "update", false, "未找到区服 ID:" .. serverId)
end

-- ========== Update(预留) ==========
function M.Update(dt)
end

return M
