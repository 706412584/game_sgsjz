-- ============================================================================
-- 《问道长生》客户端游戏操作请求管理
-- 职责：封装 REQ_GAME_OP 发送 + GAME_OP_RESP 回调分发 + 自动 ApplySync
-- 用法：GameOps.Request("currency_cost", { currency="lingStone", amount=100 }, callback)
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- ============================================================================
-- 回调管理（按 reqId 匹配）
-- ============================================================================

local reqIdCounter_    = 0
---@type table<number, { action: string, callback: fun(ok: boolean, data: table, sync: table|nil)|nil }>
local pendingCallbacks_ = {}

-- ============================================================================
-- 发送请求
-- ============================================================================

--- 发送游戏操作请求
---@param action string   Action 名称（如 "currency_cost", "shop_buy"）
---@param params table    请求参数
---@param callback? fun(ok: boolean, data: table, sync: table|nil)  回调（可选）
---@param opts? { loading?: boolean|string }  选项：loading=true 显示加载遮罩
---@return number reqId
function M.Request(action, params, callback, opts)
    opts = opts or {}

    reqIdCounter_ = reqIdCounter_ + 1
    local reqId = reqIdCounter_

    pendingCallbacks_[reqId] = {
        action   = action,
        callback = callback,
    }

    -- 显示加载遮罩
    if opts.loading then
        local Loading = require("ui_loading")
        local msg = type(opts.loading) == "string" and opts.loading or nil
        Loading.Start(msg)
    end

    -- 构造 VariantMap
    local vm = VariantMap()
    vm["Action"] = Variant(action)
    vm["ReqId"]  = Variant(reqId)
    vm["Params"] = Variant(cjson.encode(params or {}))

    local ClientNet = require("network.client_net")
    local sent = ClientNet.SendToServer(EVENTS.REQ_GAME_OP, vm)
    if not sent then
        -- 发送失败，直接回调
        pendingCallbacks_[reqId] = nil
        if opts.loading then
            local Loading = require("ui_loading")
            Loading.Stop()
        end
        if callback then
            callback(false, { msg = "网络未连接" })
        end
    end

    return reqId
end

-- ============================================================================
-- 响应处理（由 client_net.lua 中转调用）
-- ============================================================================

---@param eventData any
function M.HandleGameOpResp(eventData)
    local action   = eventData["Action"]:GetString()
    local ok       = eventData["Ok"]:GetBool()
    local dataStr  = eventData["Data"]:GetString()
    local syncStr  = eventData["Sync"] and eventData["Sync"]:GetString() or nil
    local reqId    = eventData["ReqId"] and eventData["ReqId"]:GetInt() or 0

    -- 解析 JSON
    local data = {}
    if dataStr and dataStr ~= "" then
        local s, d = pcall(cjson.decode, dataStr)
        if s then data = d end
    end

    local sync = nil
    if syncStr and syncStr ~= "" then
        local s, d = pcall(cjson.decode, syncStr)
        if s then sync = d end
    end

    -- 自动 ApplySync（无论回调是否存在）
    if ok and sync then
        local GamePlayer = require("game_player")
        if GamePlayer.ApplySync then
            GamePlayer.ApplySync(sync)
        end
        -- 数据变更后刷新红点
        local okRD, GameRedDot = pcall(require, "game_red_dot")
        if okRD and GameRedDot.RefreshAll then
            GameRedDot.RefreshAll()
        end
    end

    -- 停止加载遮罩
    local Loading = require("ui_loading")
    Loading.Stop()

    -- 查找并执行回调
    if reqId > 0 and pendingCallbacks_[reqId] then
        local entry = pendingCallbacks_[reqId]
        pendingCallbacks_[reqId] = nil
        if entry.callback then
            entry.callback(ok, data, sync)
        end
    else
        -- reqId 为 0 或找不到：尝试按 action 匹配最早的 pending
        for id, entry in pairs(pendingCallbacks_) do
            if entry.action == action then
                pendingCallbacks_[id] = nil
                if entry.callback then
                    entry.callback(ok, data, sync)
                end
                break
            end
        end
    end
end

-- ============================================================================
-- 超时清理（可选，防止内存泄漏）
-- ============================================================================

--- 清理所有待处理回调（断线重连时调用）
function M.ClearPending()
    local count = 0
    for id, entry in pairs(pendingCallbacks_) do
        count = count + 1
        if entry.callback then
            entry.callback(false, { msg = "连接已断开" })
        end
    end
    pendingCallbacks_ = {}
    -- 强制重置 Loading 状态（引用计数一起清零）
    local Loading = require("ui_loading")
    Loading.ForceStop()
    if count > 0 then
        print("[GameOps] 清理了 " .. count .. " 个待处理回调")
    end
end

return M
