-- ============================================================================
-- 《问道长生》服务端在线人数追踪
-- 职责：跟踪各区服在线连接数，同步到 serverCloud，响应客户端查询
-- 架构：本实例内存计数 + serverCloud 持久化（跨实例可读）
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson  -- 引擎内置全局变量

local M = {}

-- 依赖注入
local ctx_ = nil  -- { SendToClient }

-- 内存中的在线计数（本实例）
---@type table<number, number>  serverId → count
local onlineCounts_ = {}

-- 玩家 → 区服映射（断开时用于递减）
---@type table<number, number>  userId → serverId
local playerServer_ = {}

local TEST_SERVER_ID = 99
local GM_WHITELIST_KEY = "gm_whitelist"
local TEST_WHITELIST_KEY = "test_whitelist"
local BOOTSTRAP_GM_IDS = {
    [10001]     = true, -- 本地默认开发账号
    [529757584] = true, -- 项目作者
}

-- 状态阈值（纯展示，不阻止进入）
local THRESHOLDS = {
    { min = 0,  tag = "畅通", color = { 76, 175, 80 } },    -- 绿色
    { min = 30, tag = "良好", color = { 33, 150, 243 } },   -- 蓝色
    { min = 60, tag = "繁忙", color = { 255, 152, 0 } },    -- 橙色
    { min = 95, tag = "爆满", color = { 244, 67, 54 } },    -- 红色
}

--- 解析 uid 列表，兼容旧数据（JSON 字符串）和新数据（table）
---@param values any
---@return number[]
local function DecodeUidList(values)
    local list = {}
    local seen = {}
    local raw = values

    -- 兼容旧数据：serverCloud 可能存的是 JSON 字符串（旧版 cjson.encode 写入）
    if type(raw) == "string" and raw ~= "" then
        local ok, decoded = pcall(cjson.decode, raw)
        if ok and type(decoded) == "table" then
            raw = decoded
        else
            return list
        end
    end

    if type(raw) ~= "table" then
        return list
    end

    for _, v in ipairs(raw) do
        local uid = tonumber(v)
        if uid and uid > 0 and not seen[uid] then
            seen[uid] = true
            list[#list + 1] = uid
        end
    end
    return list
end

---@param list number[]
---@param userId number
---@return boolean
local function ContainsUid(list, userId)
    for _, uid in ipairs(list or {}) do
        if uid == userId then return true end
    end
    return false
end

---@param key string
---@param callback fun(ok: boolean, list: number[], errMsg: string|nil)
local function LoadWhitelist(key, callback)
    if not serverCloud then
        callback(false, {}, "服务端存储不可用")
        return
    end

    serverCloud:Get(nil, key, {
        ok = function(scores, iscores)
            local raw = nil
            if scores then raw = scores[key] end
            if raw == nil and iscores then raw = iscores[key] end
            callback(true, DecodeUidList(raw), nil)
        end,
        error = function(code, reason)
            callback(false, {}, "读取白名单失败")
        end,
    })
end

---@param key string
---@param list number[]
---@param callback fun(ok: boolean, errMsg: string|nil)
local function SaveWhitelist(key, list, callback)
    if not serverCloud then
        callback(false, "服务端存储不可用")
        return
    end

    serverCloud:Set(nil, key, list or {}, {
        ok = function()
            callback(true, nil)
        end,
        error = function(code, reason)
            callback(false, "保存白名单失败")
        end,
    })
end

---@param userId number
---@param callback fun(ok: boolean, reason: string|nil)
function M.CheckGMAuth(userId, callback)
    if BOOTSTRAP_GM_IDS[userId] then
        callback(true, nil)
        return
    end

    LoadWhitelist(GM_WHITELIST_KEY, function(ok, list, errMsg)
        if not ok then
            callback(false, errMsg or "GM 权限系统不可用")
            return
        end
        if ContainsUid(list, userId) then
            callback(true, nil)
        else
            callback(false, "无 GM 权限")
        end
    end)
end

---@param userId number
---@param callback fun(ok: boolean, reason: string|nil)
local function CheckTestServerAccess(userId, callback)
    -- GM 永远允许进入测试服
    M.CheckGMAuth(userId, function(isGM)
        if isGM then
            callback(true, nil)
            return
        end

        LoadWhitelist(TEST_WHITELIST_KEY, function(ok, list, errMsg)
            if not ok then
                callback(false, errMsg or "测试服白名单不可用")
                return
            end
            if ContainsUid(list, userId) then
                callback(true, nil)
            else
                callback(false, "测试服仅对白名单开放")
            end
        end)
    end)
end

---@param userId number
---@param ok boolean
---@param msg string
---@param serverId number
local function SendJoinResult(userId, ok, msg, serverId)
    if not ctx_ or not ctx_.SendToClient then return end
    local data = VariantMap()
    data["Data"] = Variant(cjson.encode({
        _type = "join",
        ok = ok and true or false,
        msg = msg or "",
        serverId = serverId or 0,
    }))
    ctx_.SendToClient(userId, "ServerOnlineData", data)
end

---@param userId number
---@param action string
---@param payload table
local function SendGMResponse(userId, action, payload)
    if not ctx_ or not ctx_.SendToClient then return end
    local data = VariantMap()
    data["Action"] = Variant(action)
    data["Data"]   = Variant(cjson.encode(payload or {}))
    ctx_.SendToClient(userId, "GMServerOnlineResp", data)
end

---@param key string
---@param targetUid number
---@param add boolean
---@param callback fun(ok: boolean, list: number[], msg: string)
local function UpdateWhitelist(key, targetUid, add, callback)
    if targetUid <= 0 then
        callback(false, {}, "无效 userId")
        return
    end

    LoadWhitelist(key, function(ok, list)
        if not ok then
            callback(false, {}, "读取白名单失败")
            return
        end

        local exists = ContainsUid(list, targetUid)
        if add then
            if not exists then
                list[#list + 1] = targetUid
            end
        else
            local nextList = {}
            for _, uid in ipairs(list) do
                if uid ~= targetUid then
                    nextList[#nextList + 1] = uid
                end
            end
            list = nextList
        end

        SaveWhitelist(key, list, function(saveOk)
            if not saveOk then
                callback(false, list, "保存白名单失败")
                return
            end
            callback(true, list, add and "添加成功" or "移除成功")
        end)
    end)
end

-- ============================================================================
-- 初始化
-- ============================================================================

---@param context table { SendToClient: function }
function M.Init(context)
    ctx_ = context
    print("[ServerOnline] 在线人数追踪模块已初始化")
end

-- ============================================================================
-- 玩家进出
-- ============================================================================

--- 玩家连接时调用（从客户端 identity 中提取 serverId）
---@param userId number
---@param serverId number
function M.PlayerJoin(userId, serverId)
    -- 如果玩家已有记录（重复登录），先清理旧的
    if playerServer_[userId] then
        M.PlayerLeave(userId)
    end

    playerServer_[userId] = serverId
    onlineCounts_[serverId] = (onlineCounts_[serverId] or 0) + 1
    M.SyncToCloud(serverId)
    print("[ServerOnline] 玩家进入: uid=" .. tostring(userId)
        .. " 区服=" .. tostring(serverId)
        .. " 当前在线=" .. tostring(onlineCounts_[serverId]))
end

--- 玩家断开时调用
---@param userId number
function M.PlayerLeave(userId)
    local serverId = playerServer_[userId]
    if not serverId then return end

    onlineCounts_[serverId] = math.max(0, (onlineCounts_[serverId] or 1) - 1)
    playerServer_[userId] = nil
    M.SyncToCloud(serverId)
    print("[ServerOnline] 玩家离开: uid=" .. tostring(userId)
        .. " 区服=" .. tostring(serverId)
        .. " 当前在线=" .. tostring(onlineCounts_[serverId]))
end

-- ============================================================================
-- 云端同步
-- ============================================================================

--- 同步指定区服的在线数到 serverCloud
---@param serverId number
function M.SyncToCloud(serverId)
    if not serverCloud then return end
    local key = "online_s" .. tostring(serverId)
    local count = onlineCounts_[serverId] or 0
    serverCloud:SetInt(nil, key, count, {
        ok = function() end,
        error = function(code, reason)
            print("[ServerOnline] 同步失败: s" .. tostring(serverId)
                .. " code=" .. tostring(code) .. " " .. tostring(reason))
        end,
    })
end

-- ============================================================================
-- 查询
-- ============================================================================

--- 查询所有区服在线人数（从 serverCloud 读取，含其他实例数据）
---@param serverIds number[] 要查询的区服 ID 列表
---@param callback function(result: table<number, number>)
function M.QueryAllOnline(serverIds, callback)
    if not serverCloud then
        callback({})
        return
    end

    local builder = serverCloud:BatchGet(nil)
    for _, sid in ipairs(serverIds) do
        builder:Key("online_s" .. tostring(sid))
    end
    builder:Fetch({
        ok = function(scores, iscores)
            local result = {}
            for _, sid in ipairs(serverIds) do
                local key = "online_s" .. tostring(sid)
                result[sid] = (iscores and iscores[key]) or 0
            end
            callback(result)
        end,
        error = function(code, reason)
            print("[ServerOnline] 查询失败: " .. tostring(code) .. " " .. tostring(reason))
            callback({})
        end,
    })
end

--- 处理客户端请求（统一入口，Action 区分操作）
--- Action = "query" — 查询所有区服在线数（默认）
--- Action = "join"  — 通知服务端玩家进入某区服（ServerId）
---@param userId number
---@param eventData any
function M.HandleReqServerOnline(userId, eventData)
    local action = "query"
    if eventData["Action"] then
        action = eventData["Action"]:GetString()
    end

    if action == "join" then
        -- 玩家通知进入区服
        local serverId = 1
        if eventData["ServerId"] then
            serverId = eventData["ServerId"]:GetInt()
        end
        if serverId == TEST_SERVER_ID then
            CheckTestServerAccess(userId, function(allowed, reason)
                if allowed then
                    M.PlayerJoin(userId, serverId)
                    SendJoinResult(userId, true, "", serverId)
                else
                    print("[ServerOnline] 测试服拒绝进入 uid=" .. tostring(userId) .. " reason=" .. tostring(reason))
                    SendJoinResult(userId, false, reason or "测试服仅对白名单开放", serverId)
                end
            end)
            return
        end

        M.PlayerJoin(userId, serverId)
        SendJoinResult(userId, true, "", serverId)
        return
    end

    -- 默认：查询所有区服在线数
    local serverIds = { 1, 2, 3 }
    M.QueryAllOnline(serverIds, function(result)
        if not ctx_ or not ctx_.SendToClient then return end
        local data = VariantMap()
        data["Data"] = Variant(cjson.encode(result))
        ctx_.SendToClient(userId, "ServerOnlineData", data)
    end)
end

-- ============================================================================
-- 状态标签工具（客户端也可复用此逻辑）
-- ============================================================================

--- 根据在线人数获取状态标签
---@param onlineCount number
---@return string tag
---@return table color {r,g,b}
function M.GetStatusTag(onlineCount)
    local n = onlineCount or 0
    local result = THRESHOLDS[1]
    for _, t in ipairs(THRESHOLDS) do
        if n >= t.min then result = t end
    end
    return result.tag, result.color
end

-- ============================================================================
-- GM 管理接口（预留，供 GM 后台远程调用）
-- ============================================================================

--- [GM] 获取本实例所有区服的在线计数
---@return table<number, number> serverId → count
function M.GM_GetOnlineCounts()
    local copy = {}
    for sid, cnt in pairs(onlineCounts_) do
        copy[sid] = cnt
    end
    return copy
end

--- [GM] 查询指定玩家所在区服
---@param userId number
---@return number|nil serverId 未在线则返回 nil
function M.GM_GetPlayerServer(userId)
    return playerServer_[userId]
end

--- [GM] 获取指定区服的所有在线玩家
---@param serverId number
---@return number[] userId 列表
function M.GM_GetServerPlayers(serverId)
    local players = {}
    for uid, sid in pairs(playerServer_) do
        if sid == serverId then
            players[#players + 1] = uid
        end
    end
    return players
end

--- [GM] 强制玩家离线（清除在线记录，不断连接）
---@param userId number
---@return boolean success
function M.GM_ForcePlayerLeave(userId)
    if not playerServer_[userId] then
        return false
    end
    M.PlayerLeave(userId)
    print("[ServerOnline][GM] 强制下线: uid=" .. tostring(userId))
    return true
end

--- [GM] 手动设置区服在线数（调试/运维用）
---@param serverId number
---@param count number
function M.GM_SetOnlineCount(serverId, count)
    onlineCounts_[serverId] = math.max(0, count)
    M.SyncToCloud(serverId)
    print("[ServerOnline][GM] 手动设置在线数: s" .. tostring(serverId) .. "=" .. tostring(count))
end

--- [GM] 获取全部玩家 → 区服映射快照
---@return table<number, number> userId → serverId
function M.GM_GetAllPlayerMappings()
    local copy = {}
    for uid, sid in pairs(playerServer_) do
        copy[uid] = sid
    end
    return copy
end

--- [GM] 统一远程事件处理入口
--- Action: "get_counts"      → 返回各区服在线数
--- Action: "get_players"     → 返回指定区服的玩家列表（需 ServerId）
--- Action: "player_server"   → 查询玩家所在区服（需 UserId）
--- Action: "force_leave"     → 强制玩家离线（需 UserId）
--- Action: "set_count"       → 手动设置在线数（需 ServerId + Count）
--- Action: "all_mappings"    → 返回全部玩家映射
---@param userId number GM 操作者的 userId
---@param eventData any
function M.HandleGMServerOp(userId, eventData)
    local action = "get_counts"
    if eventData["Action"] then
        action = eventData["Action"]:GetString()
    end

    local result = {}

    if action == "get_counts" then
        result = M.GM_GetOnlineCounts()

    elseif action == "get_players" then
        local serverId = 1
        if eventData["ServerId"] then
            serverId = eventData["ServerId"]:GetInt()
        end
        result = { serverId = serverId, players = M.GM_GetServerPlayers(serverId) }

    elseif action == "player_server" then
        local targetUid = 0
        if eventData["UserId"] then
            targetUid = eventData["UserId"]:GetInt()
        end
        local sid = M.GM_GetPlayerServer(targetUid)
        result = { userId = targetUid, serverId = sid }

    elseif action == "force_leave" then
        local targetUid = 0
        if eventData["UserId"] then
            targetUid = eventData["UserId"]:GetInt()
        end
        local ok = M.GM_ForcePlayerLeave(targetUid)
        result = { userId = targetUid, success = ok }

    elseif action == "set_count" then
        local serverId = 1
        local count = 0
        if eventData["ServerId"] then
            serverId = eventData["ServerId"]:GetInt()
        end
        if eventData["Count"] then
            count = eventData["Count"]:GetInt()
        end
        M.GM_SetOnlineCount(serverId, count)
        result = { serverId = serverId, count = count, success = true }

    elseif action == "all_mappings" then
        result = M.GM_GetAllPlayerMappings()

    elseif action == "get_test_whitelist" then
        LoadWhitelist(TEST_WHITELIST_KEY, function(ok, list, errMsg)
            SendGMResponse(userId, action, {
                success = ok,
                users = list or {},
                msg = ok and "ok" or (errMsg or "读取失败"),
            })
        end)
        return

    elseif action == "add_test_whitelist" then
        local targetUid = eventData["UserId"] and eventData["UserId"]:GetInt() or 0
        UpdateWhitelist(TEST_WHITELIST_KEY, targetUid, true, function(ok, list, msg)
            SendGMResponse(userId, action, {
                success = ok,
                users = list or {},
                msg = msg,
                userId = targetUid,
            })
        end)
        return

    elseif action == "remove_test_whitelist" then
        local targetUid = eventData["UserId"] and eventData["UserId"]:GetInt() or 0
        UpdateWhitelist(TEST_WHITELIST_KEY, targetUid, false, function(ok, list, msg)
            SendGMResponse(userId, action, {
                success = ok,
                users = list or {},
                msg = msg,
                userId = targetUid,
            })
        end)
        return

    elseif action == "get_gm_whitelist" then
        LoadWhitelist(GM_WHITELIST_KEY, function(ok, list, errMsg)
            SendGMResponse(userId, action, {
                success = ok,
                users = list or {},
                msg = ok and "ok" or (errMsg or "读取失败"),
            })
        end)
        return

    elseif action == "add_gm_whitelist" then
        local targetUid = eventData["UserId"] and eventData["UserId"]:GetInt() or 0
        UpdateWhitelist(GM_WHITELIST_KEY, targetUid, true, function(ok, list, msg)
            SendGMResponse(userId, action, {
                success = ok,
                users = list or {},
                msg = msg,
                userId = targetUid,
            })
        end)
        return

    elseif action == "remove_gm_whitelist" then
        local targetUid = eventData["UserId"] and eventData["UserId"]:GetInt() or 0
        UpdateWhitelist(GM_WHITELIST_KEY, targetUid, false, function(ok, list, msg)
            SendGMResponse(userId, action, {
                success = ok,
                users = list or {},
                msg = msg,
                userId = targetUid,
            })
        end)
        return
    end

    SendGMResponse(userId, action, result)
end

---@param userId number
---@param msg string|nil
function M.ReplyGMUnauthorized(userId, msg)
    SendGMResponse(userId, "auth", {
        success = false,
        msg = msg or "无 GM 权限",
    })
end

return M
