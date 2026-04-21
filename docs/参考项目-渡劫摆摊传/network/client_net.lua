-- ============================================================================
-- 《渡劫摆摊传》客户端网络模块
-- 职责：远程事件注册、发送封装、服务端回调中转（纯中转，不含业务逻辑）
-- 架构：云变量方案（clientCloud → serverCloud 代理）
-- ============================================================================

local Shared       = require("network.shared")
local EVENTS       = Shared.EVENTS
local CloudPolyfill = require("network.cloud_polyfill")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local connected_        = false
local serverConnection_ = nil
local disconnectCallback_ = nil  -- 断线回调（由 main.lua 注册）
local reconnectCallback_ = nil   -- 重连回调（由 main.lua 注册）
local kickedCallback_    = nil   -- 被踢回调（由 main.lua 注册）
local initialConnected_  = false -- 首次连接是否已完成
local everDisconnected_  = false -- 是否经历过断线
local kicked_            = false -- 是否被踢下线
local pendingReconnect_  = false -- 连接已恢复但等待 GameInit 到达才算真正重连成功
local clientReadySent_   = false -- 本次重连周期是否已发送 CLIENT_READY（防重复）
local myUserId_          = nil   -- 服务端通过 GameInit 告知的当前用户 ID (string)
M.isDeveloper_           = false -- 服务端通过 GameInit 告知是否为开发者
M.debugEnabled_          = false -- 服务端通过 GameInit 告知是否开启调试面板

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init()
    if not IsNetworkMode() then
        print("[ClientNet] 非网络模式，跳过初始化")
        return
    end

    print("[ClientNet] Init 开始: 注册远程事件...")
    Shared.RegisterClientEvents()
    print("[ClientNet] Init: 远程事件注册完成，开始订阅事件处理函数...")

    -- 订阅服务端回复
    SubscribeToEvent(EVENTS.CLOUD_RESP,     "HandleCloudResp")
    SubscribeToEvent(EVENTS.MAIL_LIST,      "HandleMailList")
    SubscribeToEvent(EVENTS.MAIL_RESULT,    "HandleMailResult")
    SubscribeToEvent(EVENTS.MAIL_GM_LIST,   "HandleMailGmList")
    SubscribeToEvent(EVENTS.MAIL_BROADCAST_LIST_RESP, "HandleMailBroadcastListResp")
    SubscribeToEvent(EVENTS.KICKED,         "HandleKicked")
    SubscribeToEvent(EVENTS.SERVER_LIST_RESP, "HandleServerListResp")
    SubscribeToEvent(EVENTS.SERVER_OP_RESULT, "HandleServerOpResult")
    SubscribeToEvent(EVENTS.MAINTENANCE_KICK, "HandleMaintenanceKick")

    -- 游戏状态同步(服务端权威模式)
    SubscribeToEvent(EVENTS.GAME_SYNC,  "HandleGameSync")
    SubscribeToEvent(EVENTS.GAME_INIT,  "HandleGameInit")
    SubscribeToEvent(EVENTS.GAME_EVT,   "HandleGameEvt")
    print("[ClientNet] Init: GameInit/GameSync/GameEvt 事件已订阅")

    -- GM 玩家数据管理
    SubscribeToEvent(EVENTS.GM_PLAYER_RESP,      "HandleGmPlayerResp")
    SubscribeToEvent(EVENTS.GM_PLAYER_EDIT_RESP, "HandleGmPlayerEditResp")

    -- 聊天/好友事件
    SubscribeToEvent(EVENTS.CHAT_MSG,         "HandleChatMsg")
    SubscribeToEvent(EVENTS.CHAT_PRIVATE_MSG, "HandleChatPrivateMsg")
    SubscribeToEvent(EVENTS.FRIEND_REQ_IN,    "HandleFriendReqIn")
    SubscribeToEvent(EVENTS.FRIEND_LIST_DATA, "HandleFriendListData")
    SubscribeToEvent(EVENTS.FRIEND_UPDATE,    "HandleFriendUpdate")
    SubscribeToEvent(EVENTS.CHAT_SYSTEM,      "HandleChatSystem")
    SubscribeToEvent(EVENTS.CHAT_HISTORY,     "HandleChatHistory")

    -- 订阅连接状态
    SubscribeToEvent("ServerReady",        "HandleServerReady")
    SubscribeToEvent("ServerConnected",    "HandleServerConnected")
    SubscribeToEvent("ServerDisconnected", "HandleServerDisconnected")

    -- persistent_world 模式：启动时连接可能已就绪
    local conn = network.serverConnection
    if conn then
        connected_ = true
        serverConnection_ = conn
        print("[ClientNet] 启动时服务器已就绪, conn=" .. tostring(conn))

        ---@diagnostic disable-next-line: undefined-global
        if clientCloud == nil and clientScore == nil then
            M.InjectPolyfill()
        end

        -- 连接已就绪：发送 CLIENT_READY 信号，通知服务端可以发 GameInit
        local vm = VariantMap()
        conn:SendRemoteEvent(EVENTS.CLIENT_READY, true, vm)
        print("[ClientNet] 已发送 CLIENT_READY 信号（启动时连接已就绪）")
    else
        print("[ClientNet] 启动时服务器连接尚未就绪, 等待 ServerConnected 事件")
    end

    print("[ClientNet] 客户端网络初始化完成, connected=" .. tostring(connected_))
end

-- ============================================================================
-- 连接状态
-- ============================================================================

function HandleServerReady(eventType, eventData)
    connected_ = true
    initialConnected_ = true
    serverConnection_ = network.serverConnection

    ---@diagnostic disable-next-line: undefined-global
    print("[ClientNet] ServerReady | kicked=" .. tostring(kicked_))

    -- 被封禁后保持连接不断开，仅阻止后续流程
    if kicked_ then
        print("[ClientNet] 已收到封禁通知，保持连接但不执行后续流程")
        return
    end

    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil and clientScore ~= nil then
        ---@diagnostic disable-next-line: undefined-global
        clientCloud = clientScore
        print("[ClientNet] ServerReady: clientScore -> clientCloud fallback 成功")
    end

    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil then
        M.InjectPolyfill()
    end

    ---@diagnostic disable-next-line: undefined-global
    print("[ClientNet] ServerReady | clientCloud:", tostring(clientCloud),
          "polyfill:", tostring(M.IsPolyfill()))

    -- 重连时重新发送 CLIENT_READY 信号，通知服务端重发 GameInit
    -- 否则服务端不知道客户端已恢复，不会推送 GameInit，导致重连遮罩永远不消失
    if everDisconnected_ and serverConnection_ then
        pendingReconnect_ = true
        everDisconnected_ = false
        clientReadySent_ = true
        local vm = VariantMap()
        serverConnection_:SendRemoteEvent(EVENTS.CLIENT_READY, true, vm)
        print("[ClientNet] 连接恢复(ServerReady), 已重发 CLIENT_READY, 等待 GameInit 确认重连成功")
    elseif everDisconnected_ then
        pendingReconnect_ = true
        everDisconnected_ = false
        print("[ClientNet] 连接恢复(ServerReady), 但 serverConnection_ 为 nil, 等待 GameInit")
    end
end

function HandleServerConnected(eventType, eventData)
    connected_ = true
    initialConnected_ = true
    serverConnection_ = network.serverConnection
    ---@diagnostic disable-next-line: undefined-global
    print("[ClientNet] 已连接服务器 | clientCloud:", tostring(clientCloud) .. " kicked=" .. tostring(kicked_))

    -- 被封禁后保持连接不断开，仅阻止后续流程
    if kicked_ then
        print("[ClientNet] 已收到封禁通知，保持连接但不执行后续流程")
        return
    end

    -- 发送 CLIENT_READY 信号（仅在本周期尚未发送时）
    -- 重连场景下 HandleServerReady 通常先于 HandleServerConnected 触发并已发送,
    -- 此处跳过避免服务端收到重复 CLIENT_READY 导致多次 GameInit / UI 重建
    if serverConnection_ and not clientReadySent_ then
        clientReadySent_ = true
        local vm = VariantMap()
        serverConnection_:SendRemoteEvent(EVENTS.CLIENT_READY, true, vm)
        print("[ClientNet] 已发送 CLIENT_READY 信号（ServerConnected）")
    elseif clientReadySent_ then
        print("[ClientNet] CLIENT_READY 已由 ServerReady 发送, 跳过重复发送（ServerConnected）")
    end

    -- 重连标记：等 GameInit 到达后再触发回调
    if everDisconnected_ then
        pendingReconnect_ = true
        everDisconnected_ = false
        print("[ClientNet] 连接恢复(ServerConnected), 等待 GameInit 确认重连成功")
    end
end

function HandleServerDisconnected(eventType, eventData)
    local wasConn = connected_
    connected_ = false
    serverConnection_ = nil
    print("[ClientNet] 与服务器断开连接, kicked=" .. tostring(kicked_))

    -- 再次断线时清除待确认的重连标记和发送标志
    pendingReconnect_ = false
    clientReadySent_ = false

    -- 被踢下线时不设置 everDisconnected_，阻止自动重连流程
    if kicked_ then
        return
    end

    if wasConn or initialConnected_ then
        everDisconnected_ = true
    end

    if wasConn and disconnectCallback_ then
        disconnectCallback_()
    end
end

---@return boolean
function M.IsConnected()
    return connected_
end

--- 主动断开与服务器的连接
function M.Disconnect()
    if serverConnection_ then
        serverConnection_:Disconnect(0)
    end
    connected_ = false
    serverConnection_ = nil
end

-- ============================================================================
-- 发送远程事件
-- ============================================================================

---@param eventName string
---@param data? any VariantMap
---@return boolean
function M.SendToServer(eventName, data)
    if not connected_ or not serverConnection_ then
        print("[ClientNet] 未连接服务器，无法发送: " .. eventName)
        return false
    end
    data = data or VariantMap()
    serverConnection_:SendRemoteEvent(eventName, true, data)
    return true
end

-- ============================================================================
-- 服务端回调处理
-- ============================================================================

--- 云代理回复（转发给 CloudPolyfill）
function HandleCloudResp(eventType, eventData)
    CloudPolyfill.HandleCloudResp(eventData)
end

--- 邮件列表
function HandleMailList(eventType, eventData)
    local ok, Mail = pcall(require, "ui_mail")
    if ok and Mail and Mail.OnMailList then
        Mail.OnMailList(eventData)
    end
end

--- 邮件操作结果
function HandleMailResult(eventType, eventData)
    local ok, Mail = pcall(require, "ui_mail")
    if ok and Mail and Mail.OnMailResult then
        Mail.OnMailResult(eventData)
    end
    local action = eventData["Action"]:GetString()
    -- GM 邮件操作结果也转发给 ui_gm
    if action == "gm_query" or action == "gm_clear" then
        local ok2, GM = pcall(require, "ui_gm")
        if ok2 and GM and GM.OnGmMailResult then
            GM.OnGmMailResult(eventData)
        end
    end
end

--- 被踢下线通知
function HandleKicked(eventType, eventData)
    local reason = eventData["Reason"] and eventData["Reason"]:GetString() or "unknown"
    print("[ClientNet] 被服务器踢下线: reason=" .. reason)
    kicked_ = true
    if kickedCallback_ then
        kickedCallback_(reason)
    end
end

--- 区服列表响应
function HandleServerListResp(eventType, eventData)
    print("[ClientNet] 收到区服列表响应")
    local ok, ServerSelect = pcall(require, "ui_server")
    if ok and ServerSelect and ServerSelect.OnServerListResp then
        ServerSelect.OnServerListResp(eventData)
    end
end

--- 区服操作结果
function HandleServerOpResult(eventType, eventData)
    print("[ClientNet] 收到区服操作结果")
    local ok, ServerSelect = pcall(require, "ui_server")
    if ok and ServerSelect and ServerSelect.OnServerOpResult then
        ServerSelect.OnServerOpResult(eventData)
    end
end

--- 区服维护踢人通知
function HandleMaintenanceKick(eventType, eventData)
    print("[ClientNet] 收到区服维护踢人通知")
    local ok, ServerSelect = pcall(require, "ui_server")
    if ok and ServerSelect and ServerSelect.OnMaintenanceKick then
        ServerSelect.OnMaintenanceKick(eventData)
    end
end

--- 公共聊天消息
function HandleChatMsg(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnChatMsg then
        Chat.OnChatMsg(eventData)
    end
end

--- 私聊消息
function HandleChatPrivateMsg(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnChatPrivateMsg then
        Chat.OnChatPrivateMsg(eventData)
    end
end

--- 收到好友申请
function HandleFriendReqIn(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnFriendReqIn then
        Chat.OnFriendReqIn(eventData)
    end
end

--- 好友列表数据
function HandleFriendListData(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnFriendListData then
        Chat.OnFriendListData(eventData)
    end
end

--- 好友状态变更
function HandleFriendUpdate(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnFriendUpdate then
        Chat.OnFriendUpdate(eventData)
    end
end

--- 聊天系统消息
function HandleChatSystem(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnChatSystem then
        Chat.OnChatSystem(eventData)
    end
end

--- GM 邮件查询结果
function HandleMailGmList(eventType, eventData)
    local ok, GM = pcall(require, "ui_gm")
    if ok and GM and GM.OnGmMailList then
        GM.OnGmMailList(eventData)
    end
end

--- GM 广播历史列表响应
function HandleMailBroadcastListResp(eventType, eventData)
    local ok, GM = pcall(require, "ui_gm")
    if ok and GM and GM.OnBroadcastList then
        GM.OnBroadcastList(eventData)
    end
end

--- GM 玩家数据查询响应
function HandleGmPlayerResp(eventType, eventData)
    local ok, GM = pcall(require, "ui_gm")
    if ok and GM and GM.OnPlayerResp then
        GM.OnPlayerResp(eventData)
    end
end

--- GM 玩家数据编辑响应
function HandleGmPlayerEditResp(eventType, eventData)
    local ok, GM = pcall(require, "ui_gm")
    if ok and GM and GM.OnPlayerEditResp then
        GM.OnPlayerEditResp(eventData)
    end
end

--- 聊天历史（新玩家加入时服务端推送）
function HandleChatHistory(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat and Chat.OnChatHistory then
        Chat.OnChatHistory(eventData)
    end
end

-- ============================================================================
-- 游戏状态同步（服务端权威模式）
-- ============================================================================

local cjson = cjson  ---@diagnostic disable-line: undefined-global

local gameSyncCount_ = 0
--- 游戏全量状态同步（周期性推送）
function HandleGameSync(eventType, eventData)
    gameSyncCount_ = gameSyncCount_ + 1
    if gameSyncCount_ <= 3 then
        print("[ClientNet] HandleGameSync #" .. gameSyncCount_ .. " (前3次打印)")
    end
    local stateJson = eventData["StateJson"]:GetString()
    local ok, stateTable = pcall(cjson.decode, stateJson)
    if not ok or not stateTable then
        print("[ClientNet] GameSync decode error")
        return
    end
    local State = require("data_state")
    State.ApplyServerSync(stateTable)
end

--- 游戏登录初始化
function HandleGameInit(eventType, eventData)
    print("[ClientNet] >>> HandleGameInit 被调用! <<<")
    local stateJson = eventData["StateJson"]:GetString()
    local offlineJson = eventData["OfflineJson"]:GetString()
    local customersJson = eventData["CustomersJson"]:GetString()
    local craftQueueJson = eventData["CraftQueueJson"]:GetString()
    print("[ClientNet] GameInit 数据长度: state=" .. #stateJson .. " offline=" .. #offlineJson
        .. " customers=" .. #customersJson .. " craftQueue=" .. #craftQueueJson)

    local ok1, stateTable = pcall(cjson.decode, stateJson)
    local ok2, offlineData = pcall(cjson.decode, offlineJson)
    local ok3, customersData = pcall(cjson.decode, customersJson)
    local ok4, craftQueueData = pcall(cjson.decode, craftQueueJson)

    if not ok1 or not stateTable then
        print("[ClientNet] GameInit StateJson decode error: " .. tostring(stateTable))
        return
    end
    print("[ClientNet] GameInit decode ok, playerName=" .. tostring(stateTable.playerName))

    -- 提取服务端传来的 UserId 和开发者标记
    local userIdVar = eventData["UserId"]
    if userIdVar then
        myUserId_ = userIdVar:GetString()
    end
    local isDevVar = eventData["IsDev"]
    if isDevVar then
        M.isDeveloper_ = isDevVar:GetBool()
    end
    local debugVar = eventData["DebugEnabled"]
    if debugVar then
        M.debugEnabled_ = debugVar:GetBool()
    end

    -- 版本检查: 服务端下发最低版本号
    local reqVerVar = eventData["RequiredVersion"]
    if reqVerVar then
        M.requiredVersion_ = reqVerVar:GetString()
    else
        M.requiredVersion_ = nil
    end

    local State = require("data_state")
    local GameCore = require("game_core")

    -- 换服检测：对比 serverId 是否变化（而非仅凭 gameInitReceived_）
    -- 重连时 serverId 不变，不应清缓存；换服时 serverId 变化才清
    local isServerSwitch = false
    if M.gameInitReceived_ then
        local oldServerId = State.state and State.state.serverId or 0
        local newServerId = type(stateTable.serverId) == "number" and stateTable.serverId or 0
        if newServerId ~= oldServerId then
            isServerSwitch = true
            print("[ClientNet] 检测到换服(serverId " .. tostring(oldServerId) .. " -> " .. tostring(newServerId) .. ")，清理本地缓存")
            local okChat, Chat = pcall(require, "ui_chat")
            if okChat and Chat and Chat.ClearLocalCache then
                Chat.ClearLocalCache()
            end
        else
            print("[ClientNet] 再次收到 GameInit 但 serverId 未变(" .. tostring(newServerId) .. ")，判定为重连，保留聊天缓存")
        end
    end

    -- 应用完整状态
    State.ApplyServerInit(stateTable)

    -- 恢复顾客和制作队列显示
    GameCore.InitFromServer(
        ok3 and customersData or {},
        ok4 and craftQueueData or {}
    )

    -- 恢复秘境探险状态(重连)
    local dungeonJson = eventData["DungeonJson"] and eventData["DungeonJson"]:GetString() or ""
    if dungeonJson ~= "" then
        local okD, dungeonData = pcall(cjson.decode, dungeonJson)
        GameCore.InitDungeonFromServer(okD and dungeonData or nil)
    else
        GameCore.InitDungeonFromServer(nil)
    end

    -- 存储离线收益待领取（由 main.lua 读取并弹窗）
    local newOffline = (ok2 and offlineData and offlineData.hasEarnings) and offlineData or nil
    M.pendingOffline_ = newOffline
    -- 🔴 备份: 首次收到有效离线数据时保存一份, 防止后续 GameInit 覆盖
    if newOffline and not M._offlineBackup then
        M._offlineBackup = newOffline
        print("[ClientNet] 离线数据备份已保存: minutes=" .. tostring(newOffline.minutes))
    end
    -- 存储诊断信息(延迟打印，避免被调试面板初始化前吞掉)
    local diag = ok2 and offlineData and offlineData._diag
    M._offlineDiag = M._offlineDiag or {}
    table.insert(M._offlineDiag, {
        time = os.time(),
        pendingOffline = M.pendingOffline_ ~= nil,
        hasEarnings = offlineData and offlineData.hasEarnings,
        offlineSec = offlineData and offlineData.offlineSeconds,
        isServerSwitch = isServerSwitch,
        gameInitReceived = M.gameInitReceived_,
        svr_sid = diag and diag.sid,
        svr_lastSave = diag and diag.lastSaveTime,
        svr_offlineSec = diag and diag.offlineSec,
        svr_now = diag and diag.now,
        offlineJsonRaw = offlineJson and string.sub(offlineJson, 1, 200),
    })

    -- 通知 main.lua 初始化完成
    local wasAlreadyReceived = M.gameInitReceived_  -- 是否已收过 GameInit（身份升级判断）
    M.gameInitReceived_ = true
    if M.onGameInitCallback_ then
        print("[ClientNet] GameInit: 触发 onGameInitCallback_")
        M.onGameInitCallback_()
        M.onGameInitCallback_ = nil
    elseif isServerSwitch and M.onServerSwitchCallback_ then
        print("[ClientNet] GameInit: 换服 - 触发 onServerSwitchCallback_")
        M.onServerSwitchCallback_()
    elseif wasAlreadyReceived and M.onServerSwitchCallback_ then
        -- 身份升级等场景: 已收过 GameInit、非换服非重连，但需重新走入口流程
        print("[ClientNet] GameInit: 重新初始化(身份升级) - 触发 onServerSwitchCallback_")
        M.onServerSwitchCallback_()
    else
        print("[ClientNet] GameInit: 无回调（main.lua 尚未注册 OnGameInit）")
    end

    -- 重连场景：GameInit 到达说明服务端数据已同步，现在才算真正重连成功
    if pendingReconnect_ then
        pendingReconnect_ = false
        clientReadySent_ = false
        print("[ClientNet] GameInit 到达, 重连确认成功")
        if reconnectCallback_ then
            reconnectCallback_()
        end
    end

    print("[ClientNet] GameInit applied, offline=" .. tostring(M.pendingOffline_ ~= nil))
end

--- 游戏即时事件
function HandleGameEvt(eventType, eventData)
    local evtType = eventData["Type"]:GetString()
    local dataJson = eventData["DataJson"]:GetString()
    local ok, data = pcall(cjson.decode, dataJson)
    if not ok then data = {} end

    local GameCore = require("game_core")
    GameCore.HandleServerEvent(evtType, data)
end

-- ============================================================================
-- 玩家信息推送（角色创建/改名后主动通知服务端）
-- ============================================================================

--- 向服务端推送玩家信息（道号/性别/角色ID）
---@param name string
---@param gender string
---@param playerId string
function M.SendPlayerInfo(name, gender, playerId)
    if not connected_ then return end
    local vm = VariantMap()
    vm["Name"]     = Variant(name or "")
    vm["Gender"]   = Variant(gender or "male")
    vm["PlayerId"] = Variant(playerId or "")
    M.SendToServer(Shared.EVENTS.PLAYER_INFO_UPDATE, vm)
    print("[ClientNet] 推送玩家信息: name=" .. (name or ""))
end

-- ============================================================================
-- Polyfill 注入
-- ============================================================================

local polyfillInjected_ = false

function M.IsPolyfill()
    return polyfillInjected_
end

--- 注入 polyfill 到全局 clientCloud
function M.InjectPolyfill()
    if polyfillInjected_ then return end

    -- 获取 userId：优先 lobby，fallback 从 serverConnection.identity 获取
    local userId = 0
    ---@diagnostic disable-next-line: undefined-global
    if lobby and lobby.GetMyUserId then
        ---@diagnostic disable-next-line: undefined-global
        userId = lobby:GetMyUserId()
    end
    -- fallback: 从 serverConnection.identity 获取（persistent_world 模式）
    if userId == 0 and serverConnection_ then
        local ok, val = pcall(function()
            local uid = serverConnection_.identity["user_id"]
            if uid then return uid:GetInt64() end
            return 0
        end)
        if ok and val and val ~= 0 then
            userId = val
            print("[ClientNet] identity fallback userId=" .. tostring(userId))
        end
    end

    CloudPolyfill.Setup(userId)

    ---@diagnostic disable-next-line: undefined-global
    clientCloud = CloudPolyfill
    polyfillInjected_ = true

    print("[ClientNet] clientCloud polyfill 已注入, userId=" .. tostring(userId))
end

-- ============================================================================
-- 断线/重连/被踢回调注册
-- ============================================================================

---@param callback fun()
function M.OnDisconnect(callback)
    disconnectCallback_ = callback
end

---@param callback fun()
function M.OnReconnect(callback)
    reconnectCallback_ = callback
end

---@param callback fun(reason: string)
function M.OnKicked(callback)
    kickedCallback_ = callback
end

---@return boolean
function M.IsKicked()
    return kicked_
end

--- 重试重连：如果已连接但 GameInit 未到达，重发 CLIENT_READY
---@return boolean 是否重发了信号
function M.RetryClientReady()
    -- 用户主动重试（超时点击或前台恢复触发），允许强制重发
    -- 与 ServerReady/ServerConnected 自动防重复不同，这里是显式重试
    if connected_ and serverConnection_ and pendingReconnect_ then
        clientReadySent_ = true
        local vm = VariantMap()
        serverConnection_:SendRemoteEvent(EVENTS.CLIENT_READY, true, vm)
        print("[ClientNet] RetryClientReady: 重发 CLIENT_READY 信号")
        return true
    end
    return false
end

-- ============================================================================
-- GameInit 回调与离线数据（服务端权威模式）
-- ============================================================================

M.gameInitReceived_ = false
M.pendingOffline_ = nil
M.onGameInitCallback_ = nil
M.onServerSwitchCallback_ = nil

--- 注册 GameInit 到达回调（如果已到达则立即调用）
---@param callback fun()
function M.OnGameInit(callback)
    if M.gameInitReceived_ then
        print("[ClientNet] OnGameInit: 已收到过 GameInit，立即执行回调")
        callback()
    else
        print("[ClientNet] OnGameInit: GameInit 尚未到达，注册回调等待")
        M.onGameInitCallback_ = callback
    end
end

--- 注册换服回调(持久，每次换服都会触发)
---@param callback fun()
function M.OnServerSwitch(callback)
    M.onServerSwitchCallback_ = callback
end

--- 是否已收到 GameInit
---@return boolean
function M.IsGameInitReceived()
    return M.gameInitReceived_
end

--- 获取服务端传来的当前用户 ID（string 或 nil）
---@return string|nil
function M.GetMyUserId()
    return myUserId_
end

--- 服务端是否判定当前用户为开发者
---@return boolean
function M.IsDeveloper()
    return M.isDeveloper_ == true
end

--- 获取并消费待领取的离线收益数据
---@return table|nil offlineData
function M.TakePendingOffline()
    local data = M.pendingOffline_
    M.pendingOffline_ = nil
    print("[ClientNet] TakePendingOffline: hasData=" .. tostring(data ~= nil)
        .. (data and (", hasEarnings=" .. tostring(data.hasEarnings)
            .. ", offlineSec=" .. tostring(data.offlineSeconds)) or ""))
    return data
end

--- 获取离线数据备份（兜底用，不清除备份）
---@return table|nil
function M.GetOfflineBackup()
    return M._offlineBackup
end

--- 清除离线数据备份（领取成功后调用）
function M.ClearOfflineBackup()
    M._offlineBackup = nil
end

return M
