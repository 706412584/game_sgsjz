-- ============================================================================
-- 《问道长生》客户端网络模块
-- 职责：远程事件注册、发送封装、服务端回调中转（纯中转，不含业务逻辑）
-- 架构：云变量方案（clientCloud货币 + serverCloud.list寄售 + serverCloud.message邮件）
-- ============================================================================

local Shared       = require("network.shared")
local EVENTS       = Shared.EVENTS
local CloudPolyfill = require("network.cloud_polyfill")
---@diagnostic disable-next-line: undefined-global
local cjson        = cjson

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local connected_        = false
local serverConnection_ = nil
local disconnectCallback_ = nil  -- 断线回调（由 main.lua 注册）
local reconnectCallback_ = nil   -- 重连回调（由 main.lua 注册）
local kickedCallback_    = nil   -- 被踢回调（由 main.lua 注册）
local initialConnected_  = false -- 首次连接是否已完成（Ready+Connected 都触发过才算）
local everDisconnected_  = false -- 是否经历过断线（只有断线后再连上才是重连）
local kicked_            = false -- 是否被踢下线（禁止自动重连回调）

-- ============================================================================
-- 初始化
-- ============================================================================

function M.Init()
    if not IsNetworkMode() then
        print("[ClientNet] 非网络模式，跳过初始化")
        return
    end

    Shared.RegisterClientEvents()

    -- 订阅服务端回复
    SubscribeToEvent(EVENTS.MARKET_DATA,  "HandleMarketData")
    SubscribeToEvent(EVENTS.MAIL_DATA,    "HandleMailData")
    SubscribeToEvent(EVENTS.MAIL_CLAIMED, "HandleMailClaimed")
    SubscribeToEvent(EVENTS.CLOUD_RESP,   "HandleCloudResp")
    SubscribeToEvent(EVENTS.SOCIAL_DATA,  "HandleSocialData")
    SubscribeToEvent(EVENTS.KICKED,       "HandleKicked")
    SubscribeToEvent(EVENTS.SERVER_ONLINE_DATA, "HandleServerOnlineData")
    SubscribeToEvent(EVENTS.GAME_OP_RESP, "HandleGameOpResp")
    SubscribeToEvent(EVENTS.SECT_DATA,   "HandleSectData")

    -- 组队Boss事件
    SubscribeToEvent(EVENTS.BOSS_TEAM_DATA,    "HandleBossTeamData")
    SubscribeToEvent(EVENTS.BOSS_BATTLE_ROUND, "HandleBossBattleRound")
    SubscribeToEvent(EVENTS.BOSS_BATTLE_END,   "HandleBossBattleEnd")

    -- 聊天事件
    SubscribeToEvent(EVENTS.CHAT_MSG,         "HandleChatMsg")
    SubscribeToEvent(EVENTS.CHAT_PRIVATE_MSG, "HandleChatPrivateMsg")
    SubscribeToEvent(EVENTS.CHAT_SYSTEM,      "HandleChatSystem")
    SubscribeToEvent(EVENTS.CHAT_HISTORY,     "HandleChatHistory")
    SubscribeToEvent(EVENTS.CHAT_ONLINE_STATUS, "HandleChatOnlineStatus")
    SubscribeToEvent(EVENTS.CHAT_RECALL_NOTIFY, "HandleChatRecallNotify")
    SubscribeToEvent(EVENTS.CHAT_ANNOUNCE,      "HandleChatAnnounce")

    -- 订阅连接状态
    SubscribeToEvent("ServerReady",        "HandleServerReady")
    SubscribeToEvent("ServerConnected",    "HandleServerConnected")
    SubscribeToEvent("ServerDisconnected", "HandleServerDisconnected")

    -- persistent_world 模式：启动时连接可能已就绪
    local conn = network.serverConnection
    if conn then
        connected_ = true
        serverConnection_ = conn
        print("[ClientNet] 启动时服务器已就绪")

        -- 连接已就绪但 clientCloud 仍为 nil → 注入 polyfill
        ---@diagnostic disable-next-line: undefined-global
        if clientCloud == nil and clientScore == nil then
            M.InjectPolyfill()
        end
    end

    print("[ClientNet] 客户端网络初始化完成")
end

-- ============================================================================
-- 连接状态
-- ============================================================================

function HandleServerReady(eventType, eventData)
    connected_ = true
    initialConnected_ = true
    serverConnection_ = network.serverConnection

    -- 新服务器实例不会发送 kick，清除旧的 kicked 状态
    kicked_ = false

    -- 优先尝试 C++ 原生注入的 clientScore
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil and clientScore ~= nil then
        ---@diagnostic disable-next-line: undefined-global
        clientCloud = clientScore
        print("[ClientNet] ServerReady: clientScore -> clientCloud fallback 成功")
    end

    -- 如果仍然 nil → 注入 polyfill
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud == nil then
        M.InjectPolyfill()
    end

    ---@diagnostic disable-next-line: undefined-global
    print("[ClientNet] ServerReady | clientCloud:", tostring(clientCloud),
          "clientScore:", tostring(clientScore),
          "polyfill:", tostring(M.IsPolyfill()))

    print("[ClientNet] ServerReady 完成，polyfill 已就绪")

    -- 重连成功回调：只有经历过断线且未被踢才触发
    if everDisconnected_ and reconnectCallback_ and not kicked_ then
        print("[ClientNet] 检测到重连成功")
        everDisconnected_ = false
        reconnectCallback_()
    end
end

function HandleServerConnected(eventType, eventData)
    connected_ = true
    initialConnected_ = true
    serverConnection_ = network.serverConnection
    ---@diagnostic disable-next-line: undefined-global
    print("[ClientNet] 已连接服务器 | clientCloud:", tostring(clientCloud),
          "clientScore:", tostring(clientScore))

    -- persistent_world 重连只触发 ServerConnected，ServerReady 不会重复触发。
    -- 必须在此处理全部重连路径。
    if everDisconnected_ and reconnectCallback_ and not kicked_ then
        ---@diagnostic disable-next-line: undefined-global
        if clientCloud ~= nil then
            -- polyfill 仍在（正常路径）
            print("[ClientNet] 重连成功且 polyfill 已就绪，触发重连回调")
            everDisconnected_ = false
            reconnectCallback_()
        else
            -- polyfill 意外丢失（首次连接时注入失败等边界情况），尝试重新注入
            print("[ClientNet] 重连时 clientCloud=nil，尝试重新注入 polyfill")
            M.InjectPolyfill()
            ---@diagnostic disable-next-line: undefined-global
            if clientCloud ~= nil then
                print("[ClientNet] polyfill 补注入成功，触发重连回调")
                everDisconnected_ = false
                reconnectCallback_()
            else
                -- 注入仍失败，保留 everDisconnected_=true，等待 ServerReady 兜底
                print("[ClientNet] polyfill 补注入失败，等待 ServerReady 兜底")
            end
        end
    end
end

function HandleServerDisconnected(eventType, eventData)
    local wasConn = connected_
    connected_ = false
    serverConnection_ = nil
    print("[ClientNet] 与服务器断开连接")

    -- 清理 GameOps 待处理回调
    local okOps, GameOps = pcall(require, "network.game_ops")
    if okOps and GameOps.ClearPending then
        GameOps.ClearPending()
    end

    -- 标记经历过断线（只有首次连接完成后的断线才算）
    if wasConn or initialConnected_ then
        everDisconnected_ = true
    end

    -- 触发断线回调（仅在之前确实已连接的情况下）
    if wasConn and disconnectCallback_ then
        disconnectCallback_()
    end
end

---@return boolean
function M.IsConnected()
    return connected_
end

--- 获取当前用户 ID（TapTap userId）
--- 优先从 polyfill 缓存读取，fallback 从 connection.identity 读取
---@return number userId 未连接或获取失败时返回 0
function M.GetUserId()
    -- 优先从 polyfill 缓存
    if clientCloud and clientCloud.userId and clientCloud.userId ~= 0 then
        return clientCloud.userId
    end
    -- fallback: 从 connection.identity
    if serverConnection_ then
        local ok, val = pcall(function()
            local uid = serverConnection_.identity["user_id"]
            if uid then return uid:GetInt64() end
            return 0
        end)
        if ok and val and val ~= 0 then
            return val
        end
    end
    return 0
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
-- 服务端回调处理（纯中转，延迟 require 避免循环依赖）
-- ============================================================================

--- 寄售操作统一回复
function HandleMarketData(eventType, eventData)
    local GameMarket = require("game_market")
    GameMarket.OnMarketData(eventData)
end

--- 邮件列表
function HandleMailData(eventType, eventData)
    local GameMail = require("game_mail")
    GameMail.OnMailData(eventData)
end

--- 邮件领取结果
function HandleMailClaimed(eventType, eventData)
    local GameMail = require("game_mail")
    GameMail.OnMailClaimed(eventData)
end

--- 云代理回复（转发给 CloudPolyfill）
function HandleCloudResp(eventType, eventData)
    CloudPolyfill.HandleCloudResp(eventData)
end

--- 社交操作回复
function HandleSocialData(eventType, eventData)
    local GameSocial = require("game_social")
    GameSocial.OnSocialData(eventData)
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

--- 区服在线人数数据
function HandleServerOnlineData(eventType, eventData)
    local ServerSelect = require("ui_server_select")
    ServerSelect.OnServerOnlineData(eventData)
end

--- 统一游戏操作回复（转发给 GameOps）
function HandleGameOpResp(eventType, eventData)
    local GameOps = require("network.game_ops")
    GameOps.HandleGameOpResp(eventData)
end

--- 宗门操作回复
function HandleSectData(eventType, eventData)
    local GameSect = require("game_sect")
    GameSect.OnSectData(eventData)
end

--- 组队Boss房间/队伍数据
function HandleBossTeamData(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, tbl = pcall(cjson.decode, dataStr)
    if ok and tbl then
        local GameBoss = require("game_boss")
        GameBoss.OnTeamData(tbl)
    end
end

--- 组队Boss回合数据
function HandleBossBattleRound(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, tbl = pcall(cjson.decode, dataStr)
    if ok and tbl then
        local GameBoss = require("game_boss")
        GameBoss.OnBattleRound(tbl)
    end
end

--- 组队Boss战斗结束
function HandleBossBattleEnd(eventType, eventData)
    local dataStr = eventData["Data"]:GetString()
    local ok, tbl = pcall(cjson.decode, dataStr)
    if ok and tbl then
        local GameBoss = require("game_boss")
        GameBoss.OnBattleEnd(tbl)
    end
end

-- ============================================================================
-- 聊天事件中转（转发给 ui_chat）
-- ============================================================================

--- 公共聊天消息
function HandleChatMsg(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat.OnChatMsg then
        Chat.OnChatMsg(eventData)
    end
end

--- 私聊消息
function HandleChatPrivateMsg(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat.OnChatPrivateMsg then
        Chat.OnChatPrivateMsg(eventData)
    end
end

--- 系统提示
function HandleChatSystem(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat.OnChatSystem then
        Chat.OnChatSystem(eventData)
    end
end

--- 聊天历史推送
function HandleChatHistory(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat.OnChatHistory then
        Chat.OnChatHistory(eventData)
    end
end

--- 在线状态回复
function HandleChatOnlineStatus(eventType, eventData)
    local ok, GameSocial = pcall(require, "game_social")
    if ok and GameSocial.OnOnlineStatus then
        GameSocial.OnOnlineStatus(eventData)
    end
end

--- 消息撤回通知
function HandleChatRecallNotify(eventType, eventData)
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat.OnChatRecallNotify then
        Chat.OnChatRecallNotify(eventData)
    end
end

--- 全服系统公告（富文本）
function HandleChatAnnounce(eventType, eventData)
    local announceType = eventData["Type"]:GetString()
    local text         = eventData["Text"]:GetString()
    local ok, Chat = pcall(require, "ui_chat")
    if ok and Chat.OnAnnounce then
        Chat.OnAnnounce(announceType, text)
    end
end

-- ============================================================================
-- Polyfill 注入
-- ============================================================================

local polyfillInjected_ = false

--- 是否使用了 polyfill
function M.IsPolyfill()
    return polyfillInjected_
end

-- ============================================================================
-- 断线/重连回调注册
-- ============================================================================

--- 注册断线回调（断开连接时触发）
---@param callback fun()
function M.OnDisconnect(callback)
    disconnectCallback_ = callback
end

--- 注册重连回调（重新连接成功时触发）
---@param callback fun()
function M.OnReconnect(callback)
    reconnectCallback_ = callback
end

--- 注册被踢回调（被其他设备顶号时触发）
---@param callback fun(reason: string)
function M.OnKicked(callback)
    kickedCallback_ = callback
end

--- 是否处于被踢状态
---@return boolean
function M.IsKicked()
    return kicked_
end

-- ============================================================================
-- Polyfill 注入
-- ============================================================================

--- 注入 polyfill 到全局 clientCloud
function M.InjectPolyfill()
    if polyfillInjected_ then return end

    -- 获取 userId：从 lobby 或 connection.identity
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
        end
    end

    CloudPolyfill.Setup(userId)

    -- 注入到全局
    ---@diagnostic disable-next-line: undefined-global
    clientCloud = CloudPolyfill
    polyfillInjected_ = true

    print("[ClientNet] clientCloud polyfill 已注入, userId=" .. tostring(userId))
end

return M
