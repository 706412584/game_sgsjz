-- ============================================================================
-- 《渡劫摆摊传》clientCloud Polyfill
-- 职责：在多人模式下模拟 clientCloud API，通过远程事件代理到服务端 serverCloud
-- 原理：客户端构造请求 → RemoteEvent → 服务端 serverCloud 执行 → RemoteEvent 回复
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- ============================================================================
-- 请求队列（回调管理）
-- ============================================================================

local reqIdCounter_ = 0
local pendingCallbacks_ = {}  -- reqId -> { ok, error, timeout }

--- 生成唯一请求 ID
---@return string
local function NextReqId()
    reqIdCounter_ = reqIdCounter_ + 1
    return tostring(reqIdCounter_)
end

--- 发送云代理请求
---@param method string  API 方法名（如 "Get", "Set", "BatchGet" 等）
---@param params table   参数表
---@param events table|nil  回调 { ok, error }
local function SendCloudReq(method, params, events)
    local conn = network.serverConnection
    if not conn then
        print("[CloudPolyfill] 未连接服务器，无法发送: " .. method)
        if events and events.error then
            events.error(-1, "未连接服务器")
        end
        return
    end

    local reqId = NextReqId()
    if events then
        pendingCallbacks_[reqId] = events
    end

    local data = VariantMap()
    data["ReqId"]  = Variant(reqId)
    data["Method"] = Variant(method)
    data["Params"] = Variant(cjson.encode(params))
    conn:SendRemoteEvent(EVENTS.CLOUD_REQ, true, data)
end

-- ============================================================================
-- 服务端回复处理
-- ============================================================================

--- 处理服务端 CloudResp 回复（由 client_net.lua 中转调用）
---@param eventData any
function M.HandleCloudResp(eventData)
    local reqId   = eventData["ReqId"]:GetString()
    local success = eventData["Success"]:GetBool()
    local payload = eventData["Payload"]:GetString()

    local cb = pendingCallbacks_[reqId]
    pendingCallbacks_[reqId] = nil
    if not cb then return end

    if success then
        if cb.ok then
            local ok2, result = pcall(cjson.decode, payload)
            if ok2 then
                if result._type == "get" then
                    cb.ok(result.values or {}, result.iscores or {})
                elseif result._type == "rank_list" then
                    cb.ok(result.rankList or {})
                elseif result._type == "user_rank" then
                    cb.ok(result.rank, result.score)
                elseif result._type == "rank_total" then
                    cb.ok(result.total or 0)
                else
                    cb.ok()
                end
            else
                cb.ok()
            end
        end
    else
        if cb.error then
            local code = -1
            local reason = payload or "未知错误"
            cb.error(code, reason)
        end
    end
end

-- ============================================================================
-- clientCloud 兼容 API（单个操作）
-- ============================================================================

function M.Get(self, key, events)
    SendCloudReq("Get", { key = key }, events)
end

function M.Set(self, key, value, events)
    SendCloudReq("Set", { key = key, value = value }, events)
end

function M.SetInt(self, key, value, events)
    SendCloudReq("SetInt", { key = key, value = value }, events)
end

function M.Add(self, key, delta, events)
    SendCloudReq("Add", { key = key, delta = delta }, events)
end

-- ============================================================================
-- BatchGet 构建器
-- ============================================================================

local BatchGetBuilder = {}
BatchGetBuilder.__index = BatchGetBuilder

function BatchGetBuilder:Key(key)
    self.keys[#self.keys + 1] = key
    return self
end

function BatchGetBuilder:Fetch(events)
    SendCloudReq("BatchGet", { keys = self.keys }, events)
end

function M.BatchGet(self)
    local builder = setmetatable({ keys = {} }, BatchGetBuilder)
    return builder
end

-- ============================================================================
-- BatchSet 构建器
-- ============================================================================

local BatchSetBuilder = {}
BatchSetBuilder.__index = BatchSetBuilder

function BatchSetBuilder:Set(key, value)
    self.ops[#self.ops + 1] = { op = "Set", key = key, value = value }
    return self
end

function BatchSetBuilder:SetInt(key, value)
    self.ops[#self.ops + 1] = { op = "SetInt", key = key, value = value }
    return self
end

function BatchSetBuilder:Add(key, delta)
    self.ops[#self.ops + 1] = { op = "Add", key = key, delta = delta }
    return self
end

function BatchSetBuilder:Delete(key)
    self.ops[#self.ops + 1] = { op = "Delete", key = key }
    return self
end

function BatchSetBuilder:Save(description, events)
    SendCloudReq("BatchSet", { ops = self.ops, desc = description }, events)
end

function M.BatchSet(self)
    local builder = setmetatable({ ops = {} }, BatchSetBuilder)
    return builder
end

-- ============================================================================
-- 排行榜 API
-- ============================================================================

function M.GetRankList(self, key, start, count, ...)
    local args = { ... }
    local orderAsc = false
    local events = nil
    local otherKeys = {}

    local idx = 1
    if type(args[idx]) == "boolean" then
        orderAsc = args[idx]
        idx = idx + 1
    end
    if type(args[idx]) == "table" then
        events = args[idx]
        idx = idx + 1
    end
    while idx <= #args do
        otherKeys[#otherKeys + 1] = args[idx]
        idx = idx + 1
    end

    SendCloudReq("GetRankList", {
        key = key, start = start, count = count,
        orderAsc = orderAsc, otherKeys = otherKeys,
    }, events)
end

function M.GetUserRank(self, userId, key, events)
    SendCloudReq("GetUserRank", {
        targetUserId = userId, key = key,
    }, events)
end

function M.GetRankTotal(self, key, events)
    SendCloudReq("GetRankTotal", { key = key }, events)
end

-- ============================================================================
-- 属性
-- ============================================================================

M.userId  = 0
M.mapName = ""

--- 初始化 polyfill（设置 userId 等属性）
---@param userId number
function M.Setup(userId)
    M.userId = userId
    print("[CloudPolyfill] 已初始化, userId=" .. tostring(userId))
end

return M
