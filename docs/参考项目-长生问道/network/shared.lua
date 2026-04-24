-- ============================================================================
-- 《问道长生》网络共享模块
-- 职责：事件常量定义、远程事件注册
-- 架构：云变量方案（clientCloud货币 + serverCloud.list寄售 + serverCloud.message邮件）
-- ============================================================================

local M = {}

-- ============================================================================
-- 远程事件名常量
-- ============================================================================

M.EVENTS = {
    -- 客户端 → 服务端
    REQ_MARKET_OP     = "ReqMarketOp",      -- 统一寄售操作（Action: browse/myList/list/delist/buy）
    REQ_MAIL_FETCH    = "ReqMailFetch",      -- 拉取未读邮件
    REQ_MAIL_CLAIM    = "ReqMailClaim",      -- 领取邮件（MessageId）
    CLOUD_REQ         = "CloudReq",          -- clientCloud 代理请求（Method + Params JSON）
    REQ_SOCIAL_OP     = "ReqSocialOp",       -- 社交操作（Action: add_friend/accept_friend/...）
    REQ_SERVER_ONLINE = "ReqServerOnline",   -- 区服在线（Action: query/join）
    REQ_GM_SERVER_OP  = "ReqGMServerOp",     -- [GM] 区服管理操作（含 gm/test 白名单维护）
    REQ_GAME_OP       = "ReqGameOp",         -- 统一游戏操作（Action + Params JSON）
    REQ_SECT_OP       = "ReqSectOp",         -- 宗门操作（Action: create/join/leave/kick/...）
    REQ_BOSS_OP       = "ReqBossOp",         -- 组队Boss操作（Action: create/join/leave/ready/start/kick/list）

    -- 聊天（C→S）
    CHAT_JOIN         = "ChatJoin",          -- 加入聊天（ServerId, Name, Gender, Realm）
    CHAT_SEND         = "ChatSend",          -- 公共聊天（Text）
    CHAT_PRIVATE      = "ChatPrivate",       -- 私聊（TargetId, Text）
    CHAT_QUERY_ONLINE = "ChatQueryOnline",   -- 查询在线状态（UidListJson: "[uid1,uid2,...]"）
    CHAT_RECALL       = "ChatRecall",        -- 撤回消息（MsgId）

    -- 服务端 → 客户端
    MARKET_DATA           = "MarketData",           -- 统一寄售回复（Action + Data/Success/Msg）
    MAIL_DATA             = "MailData",             -- 邮件列表（JSON）
    MAIL_CLAIMED          = "MailClaimed",          -- 领取结果（Success + MessageId）
    CLOUD_RESP            = "CloudResp",            -- clientCloud 代理回复（ReqId + Success + Payload JSON）
    SOCIAL_DATA           = "SocialData",           -- 社交数据回复（Action + Data/Success/Msg）
    KICKED                = "Kicked",               -- 被踢下线通知（Reason: duplicate_login 等）
    SERVER_ONLINE_DATA    = "ServerOnlineData",     -- 各区服在线人数数据（Data JSON）
    GM_SERVER_ONLINE_RESP = "GMServerOnlineResp",   -- [GM] 区服管理回复（Action + Data JSON）
    GAME_OP_RESP          = "GameOpResp",           -- 统一游戏操作回复（Action + Ok + Data JSON + Sync JSON）
    SECT_DATA             = "SectData",             -- 宗门数据回复（Action + Success + Msg + Data）

    -- 组队Boss（S→C）
    BOSS_TEAM_DATA    = "BossTeamData",     -- 房间状态推送（Action: team_update/team_disbanded/kicked/room_list）
    BOSS_BATTLE_ROUND = "BossBattleRound",  -- 回合广播（Data JSON: 回合战斗数据）
    BOSS_BATTLE_END   = "BossBattleEnd",    -- 战斗结束广播（Data JSON: 胜败+贡献）

    -- 聊天（S→C）
    CHAT_MSG          = "ChatMsg",           -- 公共消息广播（SenderJson, Text, Timestamp）
    CHAT_PRIVATE_MSG  = "ChatPrivateMsg",    -- 私聊消息（SenderJson, TargetId, TargetName, Text, Timestamp）
    CHAT_SYSTEM       = "ChatSystem",        -- 系统提示（Text）
    CHAT_HISTORY      = "ChatHistory",       -- 聊天历史推送（HistoryJson）
    CHAT_ONLINE_STATUS = "ChatOnlineStatus", -- 在线状态回复（StatusJson: "{uid: true/false, ...}"）
    CHAT_RECALL_NOTIFY = "ChatRecallNotify", -- 撤回通知（MsgId, ServerId）
    CHAT_ANNOUNCE      = "ChatAnnounce",     -- 全服系统公告（Type, Text），如渡劫成功世界播报
}

-- 服务器需要接收的事件（客户端发送）
M.SERVER_EVENTS = {
    M.EVENTS.REQ_MARKET_OP,
    M.EVENTS.REQ_MAIL_FETCH,
    M.EVENTS.REQ_MAIL_CLAIM,
    M.EVENTS.CLOUD_REQ,
    M.EVENTS.REQ_SOCIAL_OP,
    M.EVENTS.REQ_SERVER_ONLINE,
    M.EVENTS.REQ_GM_SERVER_OP,
    M.EVENTS.REQ_GAME_OP,
    M.EVENTS.REQ_SECT_OP,
    M.EVENTS.REQ_BOSS_OP,
    M.EVENTS.CHAT_JOIN,
    M.EVENTS.CHAT_SEND,
    M.EVENTS.CHAT_PRIVATE,
    M.EVENTS.CHAT_QUERY_ONLINE,
    M.EVENTS.CHAT_RECALL,
}

-- 客户端需要接收的事件（服务器发送）
M.CLIENT_EVENTS = {
    M.EVENTS.MARKET_DATA,
    M.EVENTS.MAIL_DATA,
    M.EVENTS.MAIL_CLAIMED,
    M.EVENTS.CLOUD_RESP,
    M.EVENTS.SOCIAL_DATA,
    M.EVENTS.KICKED,
    M.EVENTS.SERVER_ONLINE_DATA,
    M.EVENTS.GM_SERVER_ONLINE_RESP,
    M.EVENTS.GAME_OP_RESP,
    M.EVENTS.SECT_DATA,
    M.EVENTS.BOSS_TEAM_DATA,
    M.EVENTS.BOSS_BATTLE_ROUND,
    M.EVENTS.BOSS_BATTLE_END,
    M.EVENTS.CHAT_MSG,
    M.EVENTS.CHAT_PRIVATE_MSG,
    M.EVENTS.CHAT_SYSTEM,
    M.EVENTS.CHAT_HISTORY,
    M.EVENTS.CHAT_ONLINE_STATUS,
    M.EVENTS.CHAT_RECALL_NOTIFY,
    M.EVENTS.CHAT_ANNOUNCE,
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
