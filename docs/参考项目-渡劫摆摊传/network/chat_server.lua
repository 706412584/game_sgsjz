-- ============================================================================
-- 《渡劫摆摊传》服务端聊天模块
-- 职责：聊天消息转发(本服/全服/私聊) + 好友系统 + 频率限制
-- 架构：聊天历史持久化到 serverCloud + 好友关系持久化
-- ============================================================================

---@diagnostic disable: undefined-global

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

local CHAT_HISTORY_MAX    = 100    -- 服务端聊天历史环形缓冲大小
local RATE_COOLDOWN       = 2.0    -- 两条消息最短间隔(秒)
local RATE_WINDOW         = 10.0   -- 滑窗时间(秒)
local RATE_MAX_IN_WINDOW  = 5      -- 滑窗内最大消息数
local MAX_MSG_LENGTH      = 120    -- 单条消息最大字符数
local MAX_FRIENDS         = 50     -- 好友上限
local CLOUD_FRIENDS_KEY   = "friends_json"  -- serverCloud 好友列表 key
local CLOUD_CHAT_HIST_PREFIX = "chat_hist_s" -- serverCloud 聊天历史 key 前缀（拼接 serverId）
local GLOBAL_USER_ID      = 0      -- 全局共享数据用 userId=0

-- ============================================================================
-- 状态
-- ============================================================================

-- 聊天历史: serverId -> { {sender, text, timestamp}, ... }
local chatHistory_ = {}

-- 玩家信息缓存: userId -> { name, gender, playerId, realm }
local playerInfoCache_ = {}

-- 频率限制: userId -> { lastTime, windowStart, countInWindow }
local rateLimit_ = {}

-- 好友列表缓存: userId -> { [friendId] = { name, gender, addTime } }
local friendsCache_ = {}

-- 好友申请队列: userId -> { { fromId, fromName, fromGender, time }, ... }
local pendingRequests_ = {}

-- 外部注入的函数
local SendToClient_     -- function(userId, eventName, variantMap)
local BroadcastToAll_   -- function(eventName, variantMap)
local GetOnlineUsers_   -- function() -> { userId1, userId2, ... }
local GetUserServerId_  -- function(userId) -> serverId (number)

-- 持久化状态（按区服隔离）
local historyLoaded_  = {}     -- serverId -> boolean
local saveDirty_      = {}     -- serverId -> boolean（需要保存的区服）
local saveTimer_      = 0      -- 保存节流计时器
local SAVE_THROTTLE   = 5.0   -- 保存节流间隔(秒)

-- ============================================================================
-- 初始化
-- ============================================================================

---@param opts table { SendToClient, BroadcastToAll, GetOnlineUsers, GetUserServerId }
function M.Init(opts)
    SendToClient_    = opts.SendToClient
    BroadcastToAll_  = opts.BroadcastToAll
    GetOnlineUsers_  = opts.GetOnlineUsers
    GetUserServerId_ = opts.GetUserServerId

    -- 聊天历史按区服按需加载，不再在 Init 中统一加载
    print("[ChatServer] 聊天服务器已初始化（区服隔离模式）")
end

-- ============================================================================
-- 聊天历史持久化
-- ============================================================================

--- 从 serverCloud 加载指定区服的聊天历史
---@param serverId number
function M.LoadChatHistory(serverId)
    if not serverId or serverId == 0 then return end

    -- 已加载过则跳过
    if historyLoaded_[serverId] then return end

    if not serverCloud then
        print("[ChatServer] LoadChatHistory: serverCloud不可用，跳过 s=" .. tostring(serverId))
        historyLoaded_[serverId] = true
        chatHistory_[serverId] = chatHistory_[serverId] or {}
        return
    end

    local cloudKey = CLOUD_CHAT_HIST_PREFIX .. tostring(serverId)
    print("[ChatServer] LoadChatHistory: 从云端加载 s=" .. tostring(serverId) .. " key=" .. cloudKey)
    serverCloud:Get(GLOBAL_USER_ID, cloudKey, {
        ok = function(values)
            local jsonStr = values and values[cloudKey]
            if jsonStr and jsonStr ~= "" then
                local ok, list = pcall(cjson.decode, jsonStr)
                if ok and type(list) == "table" then
                    chatHistory_[serverId] = list
                    print("[ChatServer] LoadChatHistory: s=" .. tostring(serverId)
                        .. " 已加载 " .. #list .. " 条历史消息")
                else
                    print("[ChatServer] LoadChatHistory: s=" .. tostring(serverId) .. " JSON解析失败")
                    chatHistory_[serverId] = chatHistory_[serverId] or {}
                end
            else
                print("[ChatServer] LoadChatHistory: s=" .. tostring(serverId) .. " 云端无历史数据")
                chatHistory_[serverId] = chatHistory_[serverId] or {}
            end
            historyLoaded_[serverId] = true
            -- 补发等待队列中的历史推送
            M.FlushPendingHistoryPush(serverId)
        end,
        error = function(code, reason)
            print("[ChatServer] LoadChatHistory: s=" .. tostring(serverId)
                .. " 加载失败 code=" .. tostring(code) .. " reason=" .. tostring(reason))
            chatHistory_[serverId] = chatHistory_[serverId] or {}
            historyLoaded_[serverId] = true
            M.FlushPendingHistoryPush(serverId)
        end,
    })
end

--- 保存所有脏区服的聊天历史到 serverCloud
local function saveDirtyHistories()
    if not serverCloud then return end

    for serverId, dirty in pairs(saveDirty_) do
        if dirty then
            local hist = chatHistory_[serverId] or {}
            local cloudKey = CLOUD_CHAT_HIST_PREFIX .. tostring(serverId)
            local jsonStr = cjson.encode(hist)
            serverCloud:Set(GLOBAL_USER_ID, cloudKey, jsonStr, {
                ok = function()
                    print("[ChatServer] SaveChatHistory: s=" .. tostring(serverId)
                        .. " 已保存 " .. #hist .. " 条")
                end,
                error = function(code, reason)
                    print("[ChatServer] SaveChatHistory: s=" .. tostring(serverId)
                        .. " 失败 " .. tostring(reason))
                end,
            })
            saveDirty_[serverId] = false
        end
    end
    saveTimer_ = 0
end

--- 标记某区服聊天历史需要保存（节流处理）
---@param serverId number
local function markHistoryDirty(serverId)
    saveDirty_[serverId] = true
end

--- 帧更新：驱动节流保存
---@param dt number
function M.Update(dt)
    -- 检查是否有脏数据
    local hasDirty = false
    for _, dirty in pairs(saveDirty_) do
        if dirty then hasDirty = true; break end
    end
    if hasDirty then
        saveTimer_ = saveTimer_ + dt
        if saveTimer_ >= SAVE_THROTTLE then
            saveDirtyHistories()
        end
    end
end

-- ============================================================================
-- 玩家信息管理
-- ============================================================================

--- 注册/更新玩家信息(玩家连接时从 identity 或首次聊天时获取)
---@param userId number
---@param info table { name, gender, playerId, realm }
function M.UpdatePlayerInfo(userId, info)
    playerInfoCache_[userId] = info
end

--- 获取玩家信息 JSON 字符串
---@param userId number
---@return string
local function getPlayerInfoJson(userId)
    local info = playerInfoCache_[userId]
    if not info then
        return cjson.encode({
            userId = userId,
            name = "无名修士",
            gender = "male",
            playerId = "000000",
        })
    end
    local name = info.name or "无名修士"
    return cjson.encode({
        userId = userId,
        name = name,
        gender = info.gender or "male",
        playerId = info.playerId or "000000",
        realm = info.realm,
    })
end

-- ============================================================================
-- 频率限制
-- ============================================================================

---@param userId number
---@return boolean ok
---@return string? reason
local function checkRateLimit(userId)
    local now = os.time()
    local rl = rateLimit_[userId]
    if not rl then
        rateLimit_[userId] = { lastTime = now, windowStart = now, countInWindow = 1 }
        return true
    end

    -- 冷却检查
    if (now - rl.lastTime) < RATE_COOLDOWN then
        return false, "发言太快，请稍后再试"
    end

    -- 滑窗检查
    if (now - rl.windowStart) > RATE_WINDOW then
        -- 重置窗口
        rl.windowStart = now
        rl.countInWindow = 1
    else
        rl.countInWindow = rl.countInWindow + 1
        if rl.countInWindow > RATE_MAX_IN_WINDOW then
            return false, "发言过于频繁，请稍后再试"
        end
    end

    rl.lastTime = now
    return true
end

-- ============================================================================
-- 聊天历史(环形缓冲)
-- ============================================================================

---@param serverId number
---@param msg table { senderJson, text, timestamp }
local function addToHistory(serverId, msg)
    local hist = chatHistory_[serverId]
    if not hist then
        chatHistory_[serverId] = {}
        hist = chatHistory_[serverId]
    end
    table.insert(hist, msg)
    -- 超过上限时移除最早的
    while #hist > CHAT_HISTORY_MAX do
        table.remove(hist, 1)
    end
    -- 标记需要持久化（节流保存）
    markHistoryDirty(serverId)
end

-- ============================================================================
-- 聊天消息处理
-- ============================================================================

--- 处理公共聊天消息(本服/全服 → 按区服隔离)
---@param userId number
---@param eventData any
function M.HandleChatSend(userId, eventData)
    local channel = eventData["Channel"] and eventData["Channel"]:GetString() or "server"
    local text = eventData["Text"] and eventData["Text"]:GetString() or ""

    -- 校验
    if text == "" then return end
    if #text > MAX_MSG_LENGTH then
        text = string.sub(text, 1, MAX_MSG_LENGTH)
    end

    -- 频率限制
    local ok, reason = checkRateLimit(userId)
    if not ok then
        -- 发送系统提示给发送者
        local data = VariantMap()
        data["Text"] = Variant(reason)
        SendToClient_(userId, EVENTS.CHAT_SYSTEM, data)
        return
    end

    local senderServerId = GetUserServerId_ and GetUserServerId_(userId) or 0
    local timestamp = os.time()
    local senderJson = getPlayerInfoJson(userId)

    -- 存入区服隔离的历史
    if senderServerId ~= 0 then
        addToHistory(senderServerId, {
            senderJson = senderJson,
            text = text,
            timestamp = timestamp,
        })
    end

    -- 广播给同区服的在线玩家
    local data = VariantMap()
    data["Channel"]    = Variant(channel)
    data["SenderJson"] = Variant(senderJson)
    data["Text"]       = Variant(text)
    data["Timestamp"]  = Variant(timestamp)

    if senderServerId ~= 0 and GetOnlineUsers_ and GetUserServerId_ then
        for _, uid in ipairs(GetOnlineUsers_()) do
            if GetUserServerId_(uid) == senderServerId then
                SendToClient_(uid, EVENTS.CHAT_MSG, data)
            end
        end
    else
        -- 降级：广播所有人
        BroadcastToAll_(EVENTS.CHAT_MSG, data)
    end

    print("[ChatServer] [s=" .. tostring(senderServerId) .. "] userId=" .. tostring(userId) .. ": " .. text)
end

--- 处理私聊消息
---@param userId number
---@param eventData any
function M.HandleChatPrivate(userId, eventData)
    local targetIdStr = eventData["TargetId"] and eventData["TargetId"]:GetString() or ""
    local text = eventData["Text"] and eventData["Text"]:GetString() or ""
    local targetId = tonumber(targetIdStr) or 0

    if targetId == 0 or text == "" then return end
    if #text > MAX_MSG_LENGTH then
        text = string.sub(text, 1, MAX_MSG_LENGTH)
    end

    -- 频率限制
    local ok, reason = checkRateLimit(userId)
    if not ok then
        local data = VariantMap()
        data["Text"] = Variant(reason)
        SendToClient_(userId, EVENTS.CHAT_SYSTEM, data)
        return
    end

    local timestamp = os.time()
    local senderJson = getPlayerInfoJson(userId)

    -- 发送给目标玩家
    local data = VariantMap()
    data["SenderJson"] = Variant(senderJson)
    data["Text"]       = Variant(text)
    data["Timestamp"]  = Variant(timestamp)
    SendToClient_(targetId, EVENTS.CHAT_PRIVATE_MSG, data)

    -- 也发一份给发送者自己(显示在私聊窗口)
    if targetId ~= userId then
        SendToClient_(userId, EVENTS.CHAT_PRIVATE_MSG, data)
    end

    print("[ChatServer] [私聊] " .. tostring(userId) .. " → " .. tostring(targetId) .. ": " .. text)
end

-- ============================================================================
-- 好友系统
-- ============================================================================

--- 从 serverCloud 加载好友列表
---@param userId number
---@param callback fun(friends: table)
local function loadFriends(userId, callback)
    -- 优先用缓存
    if friendsCache_[userId] then
        callback(friendsCache_[userId])
        return
    end

    if not serverCloud then
        friendsCache_[userId] = {}
        callback({})
        return
    end

    serverCloud:Get(userId, CLOUD_FRIENDS_KEY, {
        ok = function(values)
            local jsonStr = values and values[CLOUD_FRIENDS_KEY]
            local friends = {}
            if jsonStr and jsonStr ~= "" then
                local ok2, parsed = pcall(cjson.decode, jsonStr)
                if ok2 and type(parsed) == "table" then
                    friends = parsed
                end
            end
            friendsCache_[userId] = friends
            callback(friends)
        end,
        error = function()
            friendsCache_[userId] = {}
            callback({})
        end,
    })
end

--- 保存好友列表到 serverCloud
---@param userId number
local function saveFriends(userId)
    local friends = friendsCache_[userId] or {}
    if serverCloud then
        serverCloud:Set(userId, CLOUD_FRIENDS_KEY, cjson.encode(friends), {
            ok = function() end,
            error = function(code, reason)
                print("[ChatServer] 好友列表保存失败 uid=" .. tostring(userId) .. ": " .. tostring(reason))
            end,
        })
    end
end

--- 获取好友数量
---@param userId number
---@return number
local function getFriendCount(userId)
    local friends = friendsCache_[userId] or {}
    local count = 0
    for _ in pairs(friends) do count = count + 1 end
    return count
end

--- 发送好友列表给客户端
---@param userId number
local function sendFriendList(userId)
    loadFriends(userId, function(friends)
        -- 补充在线状态
        local onlineUsers = GetOnlineUsers_()
        local onlineSet = {}
        for _, uid in ipairs(onlineUsers) do
            onlineSet[uid] = true
        end

        local friendList = {}
        for fidStr, fdata in pairs(friends) do
            local fid = tonumber(fidStr) or 0
            local entry = {
                userId = fid,
                name = fdata.name or "未知",
                gender = fdata.gender or "male",
                addTime = fdata.addTime or 0,
                online = onlineSet[fid] and true or false,
            }
            table.insert(friendList, entry)
        end

        local data = VariantMap()
        data["FriendsJson"] = Variant(cjson.encode(friendList))
        SendToClient_(userId, EVENTS.FRIEND_LIST_DATA, data)
    end)
end

--- 处理请求好友列表
---@param userId number
function M.HandleFriendListReq(userId)
    sendFriendList(userId)
end

--- 处理发送好友申请
---@param userId number
---@param eventData any
function M.HandleFriendReqSend(userId, eventData)
    local targetIdStr = eventData["TargetId"] and eventData["TargetId"]:GetString() or ""
    local targetId = tonumber(targetIdStr) or 0

    print("[ChatServer] 好友申请入口: userId=" .. tostring(userId) .. " targetIdStr=" .. targetIdStr .. " targetId=" .. tostring(targetId))

    if targetId == 0 then
        print("[ChatServer] 好友申请拒绝: targetId=0 无效")
        return
    end
    if targetId == userId then
        print("[ChatServer] 好友申请拒绝: targetId==userId=" .. tostring(userId) .. " 不能加自己")
        return
    end

    -- 检查是否已是好友
    loadFriends(userId, function(myFriends)
        if myFriends[tostring(targetId)] then
            local data = VariantMap()
            data["Action"]  = Variant("req_send")
            data["TargetId"] = Variant(targetIdStr)
            data["Success"] = Variant(false)
            data["Msg"]     = Variant("已经是好友了")
            SendToClient_(userId, EVENTS.FRIEND_UPDATE, data)
            return
        end

        -- 检查好友上限
        if getFriendCount(userId) >= MAX_FRIENDS then
            local data = VariantMap()
            data["Action"]  = Variant("req_send")
            data["TargetId"] = Variant(targetIdStr)
            data["Success"] = Variant(false)
            data["Msg"]     = Variant("好友数量已达上限")
            SendToClient_(userId, EVENTS.FRIEND_UPDATE, data)
            return
        end

        -- 记录申请到目标玩家的待处理队列
        if not pendingRequests_[targetId] then
            pendingRequests_[targetId] = {}
        end

        -- 避免重复申请
        for _, req in ipairs(pendingRequests_[targetId]) do
            if req.fromId == userId then
                local data = VariantMap()
                data["Action"]  = Variant("req_send")
                data["TargetId"] = Variant(targetIdStr)
                data["Success"] = Variant(false)
                data["Msg"]     = Variant("已发送过申请，请等待对方回复")
                SendToClient_(userId, EVENTS.FRIEND_UPDATE, data)
                return
            end
        end

        local senderInfo = playerInfoCache_[userId] or {}
        table.insert(pendingRequests_[targetId], {
            fromId = userId,
            fromName = senderInfo.name or "无名修士",
            fromGender = senderInfo.gender or "male",
            time = os.time(),
        })

        -- 通知目标玩家收到好友申请
        local notifyData = VariantMap()
        notifyData["FromJson"] = Variant(getPlayerInfoJson(userId))
        SendToClient_(targetId, EVENTS.FRIEND_REQ_IN, notifyData)

        -- 反馈给发送者
        local data = VariantMap()
        data["Action"]  = Variant("req_send")
        data["TargetId"] = Variant(targetIdStr)
        data["Success"] = Variant(true)
        data["Msg"]     = Variant("好友申请已发送")
        SendToClient_(userId, EVENTS.FRIEND_UPDATE, data)

        print("[ChatServer] 好友申请: " .. tostring(userId) .. " → " .. tostring(targetId))
    end)
end

--- 处理好友申请回复
---@param userId number
---@param eventData any
function M.HandleFriendReqReply(userId, eventData)
    local fromIdStr = eventData["FromId"] and eventData["FromId"]:GetString() or ""
    local accept = eventData["Accept"] and eventData["Accept"]:GetBool() or false
    local fromId = tonumber(fromIdStr) or 0

    if fromId == 0 then return end

    -- 从待处理队列中移除
    local requests = pendingRequests_[userId]
    if requests then
        for i, req in ipairs(requests) do
            if req.fromId == fromId then
                table.remove(requests, i)
                break
            end
        end
    end

    if accept then
        -- 双向添加好友
        loadFriends(userId, function(myFriends)
            loadFriends(fromId, function(theirFriends)
                local myInfo = playerInfoCache_[userId] or {}
                local theirInfo = playerInfoCache_[fromId] or {}
                local now = os.time()

                myFriends[tostring(fromId)] = {
                    name = theirInfo.name or "无名修士",
                    gender = theirInfo.gender or "male",
                    addTime = now,
                }
                theirFriends[tostring(userId)] = {
                    name = myInfo.name or "无名修士",
                    gender = myInfo.gender or "male",
                    addTime = now,
                }

                friendsCache_[userId] = myFriends
                friendsCache_[fromId] = theirFriends
                saveFriends(userId)
                saveFriends(fromId)

                -- 通知双方
                local data1 = VariantMap()
                data1["Action"]  = Variant("req_accepted")
                data1["TargetId"] = Variant(tostring(fromId))
                data1["Success"] = Variant(true)
                data1["Msg"]     = Variant("已添加好友: " .. (theirInfo.name or "无名修士"))
                SendToClient_(userId, EVENTS.FRIEND_UPDATE, data1)

                local data2 = VariantMap()
                data2["Action"]  = Variant("req_accepted")
                data2["TargetId"] = Variant(tostring(userId))
                data2["Success"] = Variant(true)
                data2["Msg"]     = Variant((myInfo.name or "无名修士") .. " 接受了你的好友申请")
                SendToClient_(fromId, EVENTS.FRIEND_UPDATE, data2)

                print("[ChatServer] 好友建立: " .. tostring(userId) .. " ↔ " .. tostring(fromId))
            end)
        end)
    else
        -- 拒绝
        local data = VariantMap()
        data["Action"]  = Variant("req_rejected")
        data["TargetId"] = Variant(tostring(userId))
        data["Success"] = Variant(true)
        data["Msg"]     = Variant("对方拒绝了你的好友申请")
        SendToClient_(fromId, EVENTS.FRIEND_UPDATE, data)
    end
end

--- 处理删除好友
---@param userId number
---@param eventData any
function M.HandleFriendRemove(userId, eventData)
    local targetIdStr = eventData["TargetId"] and eventData["TargetId"]:GetString() or ""
    local targetId = tonumber(targetIdStr) or 0

    if targetId == 0 then return end

    loadFriends(userId, function(myFriends)
        if not myFriends[tostring(targetId)] then
            local data = VariantMap()
            data["Action"]  = Variant("remove")
            data["TargetId"] = Variant(targetIdStr)
            data["Success"] = Variant(false)
            data["Msg"]     = Variant("对方不在好友列表中")
            SendToClient_(userId, EVENTS.FRIEND_UPDATE, data)
            return
        end

        -- 双向删除
        myFriends[tostring(targetId)] = nil
        friendsCache_[userId] = myFriends
        saveFriends(userId)

        loadFriends(targetId, function(theirFriends)
            theirFriends[tostring(userId)] = nil
            friendsCache_[targetId] = theirFriends
            saveFriends(targetId)
        end)

        local data = VariantMap()
        data["Action"]  = Variant("remove")
        data["TargetId"] = Variant(targetIdStr)
        data["Success"] = Variant(true)
        data["Msg"]     = Variant("已删除好友")
        SendToClient_(userId, EVENTS.FRIEND_UPDATE, data)

        print("[ChatServer] 好友删除: " .. tostring(userId) .. " × " .. tostring(targetId))
    end)
end

-- ============================================================================
-- 聊天历史推送
-- ============================================================================

local CHAT_HISTORY_PUSH_COUNT = 20  -- 新玩家推送最近条数

-- 等待历史加载完成后推送的待发队列: serverId -> { userId, ... }
local pendingHistoryPush_ = {}

--- 推送最近聊天历史给指定玩家（自动获取玩家所在区服）
---@param userId number
function M.SendChatHistory(userId)
    local serverId = GetUserServerId_ and GetUserServerId_(userId) or 0
    if serverId == 0 then
        print("[ChatServer] SendChatHistory: uid=" .. tostring(userId) .. " 无区服信息，跳过")
        return
    end

    -- 确保该区服历史已触发加载
    if not historyLoaded_[serverId] then
        M.LoadChatHistory(serverId)
    end

    -- 历史尚未从云端加载完成 → 加入待发队列
    if not historyLoaded_[serverId] then
        print("[ChatServer] SendChatHistory: s=" .. tostring(serverId)
            .. " 历史尚未加载，uid=" .. tostring(userId) .. " 加入待发队列")
        if not pendingHistoryPush_[serverId] then
            pendingHistoryPush_[serverId] = {}
        end
        table.insert(pendingHistoryPush_[serverId], userId)
        return
    end

    local hist = chatHistory_[serverId] or {}
    print("[ChatServer] SendChatHistory: uid=" .. tostring(userId)
        .. " s=" .. tostring(serverId)
        .. " historyTotal=" .. #hist
        .. " pushMax=" .. CHAT_HISTORY_PUSH_COUNT)
    if #hist == 0 then
        print("[ChatServer] SendChatHistory: s=" .. tostring(serverId) .. " 历史为空，不推送")
        return
    end

    local startIdx = math.max(1, #hist - CHAT_HISTORY_PUSH_COUNT + 1)
    local items = {}
    for i = startIdx, #hist do
        table.insert(items, hist[i])
    end

    local jsonStr = cjson.encode(items)
    print("[ChatServer] SendChatHistory: uid=" .. tostring(userId)
        .. " s=" .. tostring(serverId)
        .. " pushCount=" .. #items .. " jsonLen=" .. #jsonStr)

    local data = VariantMap()
    data["HistoryJson"] = Variant(jsonStr)
    SendToClient_(userId, EVENTS.CHAT_HISTORY, data)

    print("[ChatServer] SendChatHistory: 已调用 SendToClient_")
end

--- 补发指定区服待发队列中的历史推送（该区服历史加载完成后调用）
---@param serverId number
function M.FlushPendingHistoryPush(serverId)
    local pending = pendingHistoryPush_[serverId]
    if not pending or #pending == 0 then return end
    print("[ChatServer] FlushPendingHistoryPush: s=" .. tostring(serverId)
        .. " 补发 " .. #pending .. " 个玩家")
    for _, uid in ipairs(pending) do
        M.SendChatHistory(uid)
    end
    pendingHistoryPush_[serverId] = nil
end

-- ============================================================================
-- 玩家上线/下线
-- ============================================================================

--- 玩家上线时加载好友缓存 (聊天历史由 CLIENT_READY 触发推送)
---@param userId number
---@param skipHistory boolean|nil 是否跳过聊天历史推送(默认false)
function M.OnPlayerConnect(userId, skipHistory)
    print("[ChatServer] OnPlayerConnect: uid=" .. tostring(userId) .. " skipHistory=" .. tostring(skipHistory))
    -- 预加载好友列表
    loadFriends(userId, function() end)
    -- 推送最近聊天历史(兼容旧调用方)
    if not skipHistory then
        M.SendChatHistory(userId)
    end
end

--- 玩家下线时清理
---@param userId number
function M.OnPlayerDisconnect(userId)
    rateLimit_[userId] = nil
    pendingRequests_[userId] = nil
    -- 不清除 friendsCache_ 和 playerInfoCache_，减少重连时的云端请求
end

--- GM: 清除所有服务端内存数据（聊天历史、玩家信息缓存、好友缓存、频率限制）
function M.WipeAllData()
    -- 清除云端持久化的所有区服聊天历史
    if serverCloud then
        for serverId, _ in pairs(chatHistory_) do
            local cloudKey = CLOUD_CHAT_HIST_PREFIX .. tostring(serverId)
            serverCloud:Set(GLOBAL_USER_ID, cloudKey, "", {
                ok = function()
                    print("[ChatServer] 云端聊天历史已清除: s=" .. tostring(serverId))
                end,
                error = function(code, reason)
                    print("[ChatServer] 云端聊天历史清除失败: s=" .. tostring(serverId)
                        .. " " .. tostring(reason))
                end,
            })
        end
    end
    chatHistory_ = {}
    historyLoaded_ = {}
    saveDirty_ = {}
    playerInfoCache_ = {}
    rateLimit_ = {}
    friendsCache_ = {}
    pendingRequests_ = {}
    pendingHistoryPush_ = {}
    print("[ChatServer] 所有内存数据已清除")
end

return M
