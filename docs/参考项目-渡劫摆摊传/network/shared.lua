-- ============================================================================
-- 《渡劫摆摊传》网络共享模块
-- 职责：事件常量定义、远程事件注册
-- 架构：云变量方案（clientCloud → serverCloud 代理 + 邮件）
-- ============================================================================

local M = {}

-- ============================================================================
-- 远程事件名常量
-- ============================================================================

M.EVENTS = {
    -- 客户端 → 服务端
    CLOUD_REQ      = "CloudReq",       -- clientCloud 代理请求（Method + Params JSON）
    MAIL_SEND      = "MailSend",       -- GM发送邮件
    MAIL_FETCH     = "MailFetch",      -- 拉取邮件列表
    MAIL_CLAIM     = "MailClaim",      -- 领取邮件附件（MessageId）
    MAIL_DELETE    = "MailDelete",     -- 删除邮件（MessageId）
    MAIL_GM_QUERY  = "MailGmQuery",   -- GM: 查询指定玩家邮箱（TargetUid）
    MAIL_GM_CLEAR  = "MailGmClear",   -- GM: 清空指定玩家邮箱（TargetUid）
    MAIL_REVOKE    = "MailRevoke",    -- GM: 撤回广播邮件（BroadcastId）
    MAIL_BROADCAST_LIST = "MailBroadcastList", -- GM: 查询广播历史
    SERVER_LIST_REQ  = "ServerListReq",  -- 请求区服列表
    SERVER_ADD       = "ServerAdd",      -- GM: 添加区服
    SERVER_REMOVE    = "ServerRemove",   -- GM: 删除区服
    SERVER_UPDATE    = "ServerUpdate",   -- GM: 更新区服状态
    SERVER_SELECT    = "ServerSelect",   -- 玩家选定区服（ServerId）

    -- 聊天: 客户端 → 服务端
    CHAT_SEND        = "ChatSend",       -- 发送聊天消息（Channel + Text）
    FRIEND_REQ_SEND  = "FriendReqSend",  -- 发送好友申请（TargetId）
    FRIEND_REQ_REPLY = "FriendReqReply", -- 回复好友申请（FromId + Accept）
    FRIEND_REMOVE    = "FriendRemove",   -- 删除好友（TargetId）
    FRIEND_LIST_REQ  = "FriendListReq",  -- 请求好友列表
    CHAT_PRIVATE     = "ChatPrivate",    -- 私聊消息（TargetId + Text）
    GM_WIPE_SERVER   = "GmWipeServer",   -- GM: 清除本服数据
    GM_PLAYER_QUERY  = "GmPlayerQuery",  -- GM: 查询玩家数据（TargetUid）
    GM_PLAYER_EDIT   = "GmPlayerEdit",   -- GM: 编辑玩家数据（TargetUid + EditJson）
    PLAYER_INFO_UPDATE = "PlayerInfoUpdate", -- 客户端主动推送玩家信息（Name + Gender + PlayerId）
    GAME_ACTION = "GameAction",              -- 游戏操作请求（Action + Params JSON）
    APP_BG      = "AppBg",                   -- 前后台切换通知（Foreground: bool）
    CLIENT_READY = "ClientReady",            -- 客户端就绪信号（事件注册完成后发送，服务端收到后发 GameInit）

    -- 服务端 → 客户端
    CLOUD_RESP     = "CloudResp",      -- clientCloud 代理回复（ReqId + Success + Payload JSON）
    MAIL_LIST      = "MailList",       -- 邮件列表（MailJson + Count）
    MAIL_RESULT    = "MailResult",     -- 邮件操作结果（Action + Success + Message）
    MAIL_GM_LIST   = "MailGmList",    -- GM: 查询结果邮件列表（MailJson + Count + TargetUid）
    MAIL_BROADCAST_LIST_RESP = "MailBroadcastListResp", -- GM: 广播历史列表（ListJson + Count）
    KICKED         = "Kicked",         -- 被踢下线通知（Reason: duplicate_login 等）
    MAINTENANCE_KICK = "MaintenanceKick", -- 区服维护踢人通知（ServerId + ServerName）
    SERVER_LIST_RESP = "ServerListResp", -- 区服列表响应
    SERVER_OP_RESULT = "ServerOpResult", -- 区服操作结果

    -- 聊天: 服务端 → 客户端
    CHAT_MSG         = "ChatMsg",        -- 聊天消息广播（Channel + SenderJson + Text + Timestamp）
    CHAT_PRIVATE_MSG = "ChatPrivateMsg", -- 私聊消息（SenderJson + Text + Timestamp）
    FRIEND_REQ_IN    = "FriendReqIn",    -- 收到好友申请（FromJson）
    FRIEND_LIST_DATA = "FriendListData", -- 好友列表（FriendsJson）
    FRIEND_UPDATE    = "FriendUpdate",   -- 好友状态变更（Action + TargetId + Success + Msg）
    CHAT_SYSTEM      = "ChatSystem",     -- 系统消息（Text）
    CHAT_HISTORY     = "ChatHistory",    -- 聊天历史推送（HistoryJson：最近N条消息数组）
    GM_PLAYER_RESP      = "GmPlayerResp",      -- GM: 玩家数据查询结果（Success + DataJson）
    GM_PLAYER_EDIT_RESP = "GmPlayerEditResp",   -- GM: 玩家数据编辑结果（Success + Message）
    GAME_SYNC = "GameSync",                      -- 全量状态同步（StateJson, 2秒周期）
    GAME_INIT = "GameInit",                      -- 登录初始化（StateJson + OfflineJson + CustomersJson + CraftQueueJson）
    GAME_EVT  = "GameEvt",                       -- 即时事件推送（Type + DataJson）
}

-- 服务器需要接收的事件（客户端发送）
M.SERVER_EVENTS = {
    M.EVENTS.CLOUD_REQ,
    M.EVENTS.MAIL_SEND,
    M.EVENTS.MAIL_FETCH,
    M.EVENTS.MAIL_CLAIM,
    M.EVENTS.MAIL_DELETE,
    M.EVENTS.MAIL_GM_QUERY,
    M.EVENTS.MAIL_GM_CLEAR,
    M.EVENTS.MAIL_REVOKE,
    M.EVENTS.MAIL_BROADCAST_LIST,
    M.EVENTS.SERVER_LIST_REQ,
    M.EVENTS.SERVER_ADD,
    M.EVENTS.SERVER_REMOVE,
    M.EVENTS.SERVER_UPDATE,
    M.EVENTS.SERVER_SELECT,
    -- 聊天/好友
    M.EVENTS.CHAT_SEND,
    M.EVENTS.FRIEND_REQ_SEND,
    M.EVENTS.FRIEND_REQ_REPLY,
    M.EVENTS.FRIEND_REMOVE,
    M.EVENTS.FRIEND_LIST_REQ,
    M.EVENTS.CHAT_PRIVATE,
    M.EVENTS.GM_WIPE_SERVER,
    M.EVENTS.GM_PLAYER_QUERY,
    M.EVENTS.GM_PLAYER_EDIT,
    M.EVENTS.PLAYER_INFO_UPDATE,
    M.EVENTS.GAME_ACTION,
    M.EVENTS.APP_BG,
    M.EVENTS.CLIENT_READY,
}

-- 客户端需要接收的事件（服务器发送）
M.CLIENT_EVENTS = {
    M.EVENTS.CLOUD_RESP,
    M.EVENTS.MAIL_LIST,
    M.EVENTS.MAIL_RESULT,
    M.EVENTS.MAIL_GM_LIST,
    M.EVENTS.MAIL_BROADCAST_LIST_RESP,
    M.EVENTS.KICKED,
    M.EVENTS.MAINTENANCE_KICK,
    M.EVENTS.SERVER_LIST_RESP,
    M.EVENTS.SERVER_OP_RESULT,
    -- 聊天/好友
    M.EVENTS.CHAT_MSG,
    M.EVENTS.CHAT_PRIVATE_MSG,
    M.EVENTS.FRIEND_REQ_IN,
    M.EVENTS.FRIEND_LIST_DATA,
    M.EVENTS.FRIEND_UPDATE,
    M.EVENTS.CHAT_SYSTEM,
    M.EVENTS.CHAT_HISTORY,
    M.EVENTS.GM_PLAYER_RESP,
    M.EVENTS.GM_PLAYER_EDIT_RESP,
    M.EVENTS.GAME_SYNC,
    M.EVENTS.GAME_INIT,
    M.EVENTS.GAME_EVT,
}

--- 注册服务器端事件
function M.RegisterServerEvents()
    for _, eventName in ipairs(M.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 已注册 " .. #M.SERVER_EVENTS .. " 个服务端事件")
end

--- 注册客户端事件
function M.RegisterClientEvents()
    for _, eventName in ipairs(M.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 已注册 " .. #M.CLIENT_EVENTS .. " 个客户端事件")
end

return M
