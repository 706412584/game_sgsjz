-- ============================================================================
-- 《问道长生》服务端云变量代理
-- 职责：接收客户端 CloudReq 远程事件，通过 serverCloud 执行后回复 CloudResp
-- 原理：将 clientCloud API 透明代理到 serverCloud（加 userId 参数）
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- 依赖注入（由 server_main.lua 传入）
local deps_ = nil

-- ============================================================================
-- 初始化
-- ============================================================================

---@param deps table { SendToClient }
function M.Init(deps)
    deps_ = deps
    print("[ServerCloudProxy] 云代理初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 回复客户端
---@param userId number
---@param reqId string
---@param success boolean
---@param payload string  JSON 编码的结果
local function Reply(userId, reqId, success, payload)
    local data = VariantMap()
    data["ReqId"]   = Variant(reqId)
    data["Success"] = Variant(success)
    data["Payload"] = Variant(payload or "")
    deps_.SendToClient(userId, EVENTS.CLOUD_RESP, data)
end

--- 错误回复
local function ReplyError(userId, reqId, reason)
    Reply(userId, reqId, false, reason or "未知错误")
end

-- ============================================================================
-- 请求分发
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleCloudReq(userId, eventData)
    if not serverCloud then
        local reqId = eventData["ReqId"]:GetString()
        ReplyError(userId, reqId, "serverCloud 不可用")
        return
    end

    local reqId  = eventData["ReqId"]:GetString()
    local method = eventData["Method"]:GetString()
    local paramsStr = eventData["Params"]:GetString()

    local ok, params = pcall(cjson.decode, paramsStr)
    if not ok then
        ReplyError(userId, reqId, "参数解析失败")
        return
    end

    if method == "Get" then
        M.DoGet(userId, reqId, params)
    elseif method == "Set" then
        M.DoSet(userId, reqId, params)
    elseif method == "SetInt" then
        M.DoSetInt(userId, reqId, params)
    elseif method == "Add" then
        M.DoAdd(userId, reqId, params)
    elseif method == "BatchGet" then
        M.DoBatchGet(userId, reqId, params)
    elseif method == "BatchSet" then
        M.DoBatchSet(userId, reqId, params)
    elseif method == "GetRankList" then
        M.DoGetRankList(userId, reqId, params)
    elseif method == "GetUserRank" then
        M.DoGetUserRank(userId, reqId, params)
    elseif method == "GetRankTotal" then
        M.DoGetRankTotal(userId, reqId, params)
    else
        ReplyError(userId, reqId, "未知方法: " .. tostring(method))
    end
end

-- ============================================================================
-- API 实现
-- ============================================================================

--- Get(key)
function M.DoGet(userId, reqId, params)
    serverCloud:Get(userId, params.key, {
        ok = function(scores, iscores)
            Reply(userId, reqId, true, cjson.encode({
                _type = "get",
                values = scores or {},
                iscores = iscores or {},
            }))
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- Set(key, value)
function M.DoSet(userId, reqId, params)
    serverCloud:Set(userId, params.key, params.value, {
        ok = function()
            Reply(userId, reqId, true, "{}")
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- SetInt(key, value)
function M.DoSetInt(userId, reqId, params)
    serverCloud:SetInt(userId, params.key, params.value, {
        ok = function()
            Reply(userId, reqId, true, "{}")
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- Add(key, delta)
function M.DoAdd(userId, reqId, params)
    serverCloud:Add(userId, params.key, params.delta, {
        ok = function()
            Reply(userId, reqId, true, "{}")
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- BatchGet(keys)
function M.DoBatchGet(userId, reqId, params)
    local builder = serverCloud:BatchGet(userId)
    for _, key in ipairs(params.keys or {}) do
        builder:Key(key)
    end
    builder:Fetch({
        ok = function(scores, iscores)
            Reply(userId, reqId, true, cjson.encode({
                _type = "get",
                values = scores or {},
                iscores = iscores or {},
            }))
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- BatchSet(ops, desc)
function M.DoBatchSet(userId, reqId, params)
    local builder = serverCloud:BatchSet(userId)
    for _, op in ipairs(params.ops or {}) do
        if op.op == "Set" then
            builder:Set(op.key, op.value)
        elseif op.op == "SetInt" then
            builder:SetInt(op.key, op.value)
        elseif op.op == "Add" then
            builder:Add(op.key, op.delta)
        elseif op.op == "Delete" then
            builder:Delete(op.key)
        end
    end
    builder:Save(params.desc or "polyfill_save", {
        ok = function()
            Reply(userId, reqId, true, "{}")
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- GetRankList(key, start, count, orderAsc, otherKeys)
function M.DoGetRankList(userId, reqId, params)
    local key = params.key
    local start = params.start or 0
    local count = params.count or 10
    local orderAsc = params.orderAsc or false
    local otherKeys = params.otherKeys or {}

    local callbackEvents = {
        ok = function(rankList)
            local result = {}
            for idx, item in ipairs(rankList or {}) do
                result[#result + 1] = {
                    userId = item.userId,
                    player = item.userId,
                    iscore = item.iscore or {},
                    score  = item.score or {},
                }
            end

            -- otherKeys 不为空时，逐个用单人 BatchGet(uid) 拉取附加数据
            if #otherKeys > 0 and #result > 0 then
                local pending = #result
                local scoreMap = {}
                for ri, r in ipairs(result) do
                    local uid = r.userId
                    local builder = serverCloud:BatchGet(uid)
                    for _, k in ipairs(otherKeys) do
                        builder:Key(k)
                    end
                    builder:Fetch({
                        ok = function(scores, iscores)
                            scoreMap[uid] = scores or {}
                            pending = pending - 1
                            if pending <= 0 then
                                -- 全部完成，合并数据
                                for _, rr in ipairs(result) do
                                    local extra = scoreMap[rr.userId]
                                    if extra then
                                        for k2, v2 in pairs(extra) do
                                            rr.score[k2] = v2
                                        end
                                    end
                                end
                                Reply(userId, reqId, true, cjson.encode({
                                    _type = "rank_list",
                                    rankList = result,
                                }))
                            end
                        end,
                        error = function(code, reason)
                            pending = pending - 1
                            if pending <= 0 then
                                Reply(userId, reqId, true, cjson.encode({
                                    _type = "rank_list",
                                    rankList = result,
                                }))
                            end
                        end,
                    })
                end
            else
                Reply(userId, reqId, true, cjson.encode({
                    _type = "rank_list",
                    rankList = result,
                }))
            end
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    }

    -- 排行榜查询不传 otherKey（serverCloud 文档未支持），
    -- 改为在回调中用 BatchGet 批量拉取附加数据
    local args = { key, start, count }
    if orderAsc then
        args[#args + 1] = true
    end
    args[#args + 1] = callbackEvents

    serverCloud:GetRankList(table.unpack(args))
end

--- GetUserRank(targetUserId, key)
function M.DoGetUserRank(userId, reqId, params)
    local targetUid = params.targetUserId or userId
    serverCloud:GetUserRank(targetUid, params.key, {
        ok = function(rank, score)
            Reply(userId, reqId, true, cjson.encode({
                _type = "user_rank",
                rank = rank,
                score = score,
            }))
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

--- GetRankTotal(key)
function M.DoGetRankTotal(userId, reqId, params)
    serverCloud:GetRankTotal(params.key, {
        ok = function(total)
            Reply(userId, reqId, true, cjson.encode({
                _type = "rank_total",
                total = total,
            }))
        end,
        error = function(code, reason)
            ReplyError(userId, reqId, tostring(code) .. ": " .. tostring(reason))
        end,
    })
end

return M
