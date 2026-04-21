------------------------------------------------------------
-- network/shared.lua — 三国神将录 网络共享模块
-- 职责：事件常量定义、远程事件注册
-- 两端共享，禁止放业务逻辑
------------------------------------------------------------

local M = {}

------------------------------------------------------------
-- 远程事件名常量
------------------------------------------------------------
M.EVENTS = {
    -- 客户端 → 服务端
    GAME_ACTION     = "GameAction",      -- 游戏操作（Action + Data JSON）
    SERVER_LIST_REQ = "ServerListReq",   -- 请求区服列表
    SERVER_SELECT   = "ServerSelect",    -- 选定区服（ServerId）
    CLIENT_READY    = "ClientReady",     -- 客户端就绪（事件注册完成）
    APP_BG          = "AppBg",           -- 前后台切换（Foreground: bool）

    -- 服务端 → 客户端
    GAME_INIT       = "GameInit",        -- 登录初始化（StateJson）
    GAME_SYNC       = "GameSync",        -- 全量状态同步（StateJson，周期推送）
    GAME_EVT        = "GameEvt",         -- 即时事件推送（Type + DataJson）
    SERVER_LIST_RESP = "ServerListResp", -- 区服列表响应
    KICKED          = "Kicked",          -- 踢下线通知（Reason）
}

------------------------------------------------------------
-- 事件分组：按接收端分类
------------------------------------------------------------

-- 服务端需要接收的事件（客户端发送）
M.SERVER_EVENTS = {
    M.EVENTS.GAME_ACTION,
    M.EVENTS.SERVER_LIST_REQ,
    M.EVENTS.SERVER_SELECT,
    M.EVENTS.CLIENT_READY,
    M.EVENTS.APP_BG,
}

-- 客户端需要接收的事件（服务端发送）
M.CLIENT_EVENTS = {
    M.EVENTS.GAME_INIT,
    M.EVENTS.GAME_SYNC,
    M.EVENTS.GAME_EVT,
    M.EVENTS.SERVER_LIST_RESP,
    M.EVENTS.KICKED,
}

------------------------------------------------------------
-- 注册函数
------------------------------------------------------------

--- 注册服务端事件（server_main.lua 调用）
function M.RegisterServerEvents()
    for _, eventName in ipairs(M.SERVER_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 已注册 " .. #M.SERVER_EVENTS .. " 个服务端事件")
end

--- 注册客户端事件（client_main.lua 调用）
function M.RegisterClientEvents()
    for _, eventName in ipairs(M.CLIENT_EVENTS) do
        network:RegisterRemoteEvent(eventName)
    end
    print("[Shared] 已注册 " .. #M.CLIENT_EVENTS .. " 个客户端事件")
end

return M
