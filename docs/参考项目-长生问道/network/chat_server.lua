-- ============================================================================
-- 《问道长生》服务端聊天模块
-- 职责：公共聊天转发（区服隔离）+ 私聊转发 + 频率限制 + 聊天历史持久化
-- 架构：聊天历史持久化到 serverCloud（userId=0 全局共享，按区服 key 隔离）
-- ============================================================================

---@diagnostic disable: undefined-global

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

local CHAT_HISTORY_MAX      = 100     -- 环形缓冲上限
local HISTORY_PUSH_COUNT    = 20      -- 新玩家推送最近条数
local RATE_COOLDOWN         = 2.0     -- 两条消息最短间隔(秒)
local RATE_WINDOW           = 10.0    -- 滑窗时间(秒)
local RATE_MAX_IN_WINDOW    = 5       -- 滑窗内最大消息数
local MAX_MSG_LENGTH        = 120     -- 单条消息最大字符数
local CLOUD_CHAT_KEY_PREFIX = "chat_hist_s"
local GLOBAL_UID            = 0       -- 全局共享数据 userId
local SAVE_THROTTLE         = 5.0    -- 脏数据保存节流(秒)
local RECALL_TIME_LIMIT     = 120     -- 撤回时间限制(秒)

-- ============================================================================
-- 状态
-- ============================================================================

local chatHistory_    = {}   -- serverId -> { {senderJson, text, timestamp, msgId, userId}, ... }
local historyLoaded_  = {}   -- serverId -> boolean
local saveDirty_      = {}   -- serverId -> boolean
local saveTimer_      = 0
local msgIdCounter_   = 0    -- 消息 ID 自增计数器

local playerInfo_     = {}   -- userId -> { name, gender, realm, serverId }
local rateLimit_      = {}   -- userId -> { lastTime, windowStart, countInWindow }
local pendingPush_    = {}   -- serverId -> { userId, ... }

-- 外部注入
local SendToClient_
local GetOnlineUsers_

-- ============================================================================
-- 初始化
-- ============================================================================

---@param opts table { SendToClient, GetOnlineUsers }
function M.Init(opts)
    SendToClient_   = opts.SendToClient
    GetOnlineUsers_ = opts.GetOnlineUsers
    print("[ChatServer] 聊天服务已初始化")
end

-- ============================================================================
-- 玩家信息
-- ============================================================================

local function getSenderJson(userId)
    local info = playerInfo_[userId]
    if not info then
        return cjson.encode({ userId = userId, name = "无名修士", gender = "男", realm = "凡人" })
    end
    return cjson.encode({
        userId      = userId,
        name        = info.name or "无名修士",
        gender      = info.gender or "男",
        realm       = info.realm or "凡人",
        avatarIndex = info.avatarIndex or 1,
    })
end

local function getUserServerId(userId)
    local info = playerInfo_[userId]
    return info and info.serverId or 0
end

-- ============================================================================
-- 频率限制
-- ============================================================================

---@return boolean, string|nil
local function checkRateLimit(userId)
    local now = os.time()
    local rl = rateLimit_[userId]
    if not rl then
        rateLimit_[userId] = { lastTime = now, windowStart = now, countInWindow = 1 }
        return true
    end
    if (now - rl.lastTime) < RATE_COOLDOWN then
        return false, "发言太快，请稍后再试"
    end
    if (now - rl.windowStart) > RATE_WINDOW then
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
-- 聊天历史持久化
-- ============================================================================

function M.LoadChatHistory(serverId)
    if not serverId or serverId == 0 then return end
    if historyLoaded_[serverId] then return end

    if not serverCloud then
        historyLoaded_[serverId] = true
        chatHistory_[serverId] = chatHistory_[serverId] or {}
        return
    end

    local key = CLOUD_CHAT_KEY_PREFIX .. tostring(serverId)
    serverCloud:Get(GLOBAL_UID, key, {
        ok = function(values)
            local raw = values and values[key]
            if raw then
                -- 兼容旧数据：可能是 JSON 字符串（旧版 cjson.encode 写入）
                if type(raw) == "string" and raw ~= "" then
                    local ok2, decoded = pcall(cjson.decode, raw)
                    chatHistory_[serverId] = (ok2 and type(decoded) == "table") and decoded or {}
                elseif type(raw) == "table" then
                    chatHistory_[serverId] = raw
                else
                    chatHistory_[serverId] = {}
                end
            else
                chatHistory_[serverId] = chatHistory_[serverId] or {}
            end
            historyLoaded_[serverId] = true
            M.FlushPendingPush(serverId)
        end,
        error = function()
            chatHistory_[serverId] = chatHistory_[serverId] or {}
            historyLoaded_[serverId] = true
            M.FlushPendingPush(serverId)
        end,
    })
end

---@param serverId number
---@param msg table
local function addToHistory(serverId, msg)
    local hist = chatHistory_[serverId]
    if not hist then
        chatHistory_[serverId] = {}
        hist = chatHistory_[serverId]
    end
    hist[#hist + 1] = msg
    while #hist > CHAT_HISTORY_MAX do
        table.remove(hist, 1)
    end
    saveDirty_[serverId] = true
end

local function saveDirtyHistories()
    if not serverCloud then return end
    for serverId, dirty in pairs(saveDirty_) do
        if dirty then
            local hist = chatHistory_[serverId] or {}
            local key = CLOUD_CHAT_KEY_PREFIX .. tostring(serverId)
            serverCloud:Set(GLOBAL_UID, key, hist, {
                ok = function() end,
                error = function(_, reason)
                    print("[ChatServer] 保存失败 s=" .. tostring(serverId) .. ": " .. tostring(reason))
                end,
            })
            saveDirty_[serverId] = false
        end
    end
    saveTimer_ = 0
end

--- 帧更新：驱动脏数据保存节流
---@param dt number
function M.Update(dt)
    local hasDirty = false
    for _, d in pairs(saveDirty_) do
        if d then hasDirty = true; break end
    end
    if hasDirty then
        saveTimer_ = saveTimer_ + dt
        if saveTimer_ >= SAVE_THROTTLE then
            saveDirtyHistories()
        end
    end
end

-- ============================================================================
-- 聊天历史推送
-- ============================================================================

---@param userId number
function M.SendChatHistory(userId)
    local serverId = getUserServerId(userId)
    if serverId == 0 then return end

    if not historyLoaded_[serverId] then
        M.LoadChatHistory(serverId)
    end
    -- 历史尚未加载完成 → 加入待发队列
    if not historyLoaded_[serverId] then
        if not pendingPush_[serverId] then pendingPush_[serverId] = {} end
        pendingPush_[serverId][#pendingPush_[serverId] + 1] = userId
        return
    end

    local hist = chatHistory_[serverId] or {}
    if #hist == 0 then return end

    local startIdx = math.max(1, #hist - HISTORY_PUSH_COUNT + 1)
    local items = {}
    for i = startIdx, #hist do
        items[#items + 1] = hist[i]
    end

    local data = VariantMap()
    data["HistoryJson"] = Variant(cjson.encode(items))
    SendToClient_(userId, EVENTS.CHAT_HISTORY, data)
    print("[ChatServer] 推送历史: uid=" .. tostring(userId) .. " count=" .. #items)
end

---@param serverId number
function M.FlushPendingPush(serverId)
    local pending = pendingPush_[serverId]
    if not pending or #pending == 0 then return end
    for _, uid in ipairs(pending) do
        M.SendChatHistory(uid)
    end
    pendingPush_[serverId] = nil
end

-- ============================================================================
-- 事件处理
-- ============================================================================

--- 玩家加入聊天（注册信息 + 推送历史）
---@param userId number
---@param eventData any
function M.HandleChatJoin(userId, eventData)
    local serverId = tonumber(eventData["ServerId"] and eventData["ServerId"]:GetString() or "0") or 0
    local name   = eventData["Name"]   and eventData["Name"]:GetString()   or "无名修士"
    local gender = eventData["Gender"] and eventData["Gender"]:GetString() or "男"
    local realm  = eventData["Realm"]  and eventData["Realm"]:GetString()  or "凡人"
    local avatarIndex = tonumber(eventData["AvatarIndex"] and eventData["AvatarIndex"]:GetString() or "1") or 1

    playerInfo_[userId] = { name = name, gender = gender, realm = realm, serverId = serverId, avatarIndex = avatarIndex }
    print("[ChatServer] 玩家加入聊天: uid=" .. tostring(userId) .. " " .. name .. " s=" .. tostring(serverId))

    if serverId ~= 0 then
        M.SendChatHistory(userId)
    end
end

--- 公共聊天
---@param userId number
---@param eventData any
function M.HandleChatSend(userId, eventData)
    local text = eventData["Text"] and eventData["Text"]:GetString() or ""
    if text == "" then return end
    if #text > MAX_MSG_LENGTH then text = text:sub(1, MAX_MSG_LENGTH) end

    local ok, reason = checkRateLimit(userId)
    if not ok then
        local d = VariantMap()
        d["Text"] = Variant(reason)
        SendToClient_(userId, EVENTS.CHAT_SYSTEM, d)
        return
    end

    local serverId  = getUserServerId(userId)
    local timestamp = os.time()
    local senderJson = getSenderJson(userId)

    -- 生成消息 ID
    msgIdCounter_ = msgIdCounter_ + 1
    local msgId = tostring(userId) .. "_" .. tostring(timestamp) .. "_" .. tostring(msgIdCounter_)

    -- 存入区服隔离的历史
    if serverId ~= 0 then
        addToHistory(serverId, { senderJson = senderJson, text = text, timestamp = timestamp, msgId = msgId, userId = userId })
    end

    -- 广播给同区服在线玩家
    local data = VariantMap()
    data["SenderJson"] = Variant(senderJson)
    data["Text"]       = Variant(text)
    data["Timestamp"]  = Variant(timestamp)
    data["MsgId"]      = Variant(msgId)

    if serverId ~= 0 and GetOnlineUsers_ then
        for _, uid in ipairs(GetOnlineUsers_()) do
            if getUserServerId(uid) == serverId then
                SendToClient_(uid, EVENTS.CHAT_MSG, data)
            end
        end
    end
end

--- 私聊
---@param userId number
---@param eventData any
function M.HandleChatPrivate(userId, eventData)
    local targetId = tonumber(eventData["TargetId"] and eventData["TargetId"]:GetString() or "0") or 0
    local text     = eventData["Text"] and eventData["Text"]:GetString() or ""
    if targetId == 0 or text == "" then return end
    if #text > MAX_MSG_LENGTH then text = text:sub(1, MAX_MSG_LENGTH) end

    local ok, reason = checkRateLimit(userId)
    if not ok then
        local d = VariantMap()
        d["Text"] = Variant(reason)
        SendToClient_(userId, EVENTS.CHAT_SYSTEM, d)
        return
    end

    local timestamp  = os.time()
    local senderJson = getSenderJson(userId)
    local targetInfo = playerInfo_[targetId]
    local targetName = targetInfo and targetInfo.name or "未知"

    local data = VariantMap()
    data["SenderJson"]  = Variant(senderJson)
    data["TargetId"]    = Variant(tostring(targetId))
    data["TargetName"]  = Variant(targetName)
    data["Text"]        = Variant(text)
    data["Timestamp"]   = Variant(timestamp)

    -- 发送给目标
    SendToClient_(targetId, EVENTS.CHAT_PRIVATE_MSG, data)
    -- 回显给发送者（用于 UI 显示）
    if targetId ~= userId then
        SendToClient_(userId, EVENTS.CHAT_PRIVATE_MSG, data)
    end

    print("[ChatServer] 私聊 " .. tostring(userId) .. " -> " .. tostring(targetId))
end

-- ============================================================================
-- 在线状态查询
-- ============================================================================

--- 查询指定 uid 列表的在线状态
---@param userId number  请求者
---@param eventData any
function M.HandleChatQueryOnline(userId, eventData)
    local json = eventData["UidListJson"] and eventData["UidListJson"]:GetString() or "[]"
    local ok2, uidList = pcall(cjson.decode, json)
    if not ok2 or type(uidList) ~= "table" then return end

    local status = {}
    for _, uid in ipairs(uidList) do
        local uidNum = tonumber(uid)
        if uidNum then
            status[tostring(uidNum)] = playerInfo_[uidNum] ~= nil
        end
    end

    local data = VariantMap()
    data["StatusJson"] = Variant(cjson.encode(status))
    SendToClient_(userId, EVENTS.CHAT_ONLINE_STATUS, data)
end

-- ============================================================================
-- 消息撤回
-- ============================================================================

--- 撤回消息（仅限自己的消息，2分钟内）
---@param userId number
---@param eventData any
function M.HandleChatRecall(userId, eventData)
    local msgId = eventData["MsgId"] and eventData["MsgId"]:GetString() or ""
    if msgId == "" then return end

    local serverId = getUserServerId(userId)
    if serverId == 0 then return end

    local hist = chatHistory_[serverId]
    if not hist then return end

    -- 在历史中查找消息
    local now = os.time()
    local found = false
    for i = #hist, 1, -1 do
        local msg = hist[i]
        if msg.msgId == msgId then
            -- 校验：必须是自己发的
            if msg.userId ~= userId then
                local d = VariantMap()
                d["Text"] = Variant("只能撤回自己的消息")
                SendToClient_(userId, EVENTS.CHAT_SYSTEM, d)
                return
            end
            -- 校验：2分钟内
            if (now - (msg.timestamp or 0)) > RECALL_TIME_LIMIT then
                local d = VariantMap()
                d["Text"] = Variant("消息已超过2分钟，无法撤回")
                SendToClient_(userId, EVENTS.CHAT_SYSTEM, d)
                return
            end
            -- 从历史中删除
            table.remove(hist, i)
            saveDirty_[serverId] = true
            found = true
            break
        end
    end

    if not found then
        local d = VariantMap()
        d["Text"] = Variant("消息不存在或已被撤回")
        SendToClient_(userId, EVENTS.CHAT_SYSTEM, d)
        return
    end

    -- 广播撤回通知给同区服玩家
    local data = VariantMap()
    data["MsgId"]    = Variant(msgId)
    data["ServerId"] = Variant(tostring(serverId))

    if GetOnlineUsers_ then
        for _, uid in ipairs(GetOnlineUsers_()) do
            if getUserServerId(uid) == serverId then
                SendToClient_(uid, EVENTS.CHAT_RECALL_NOTIFY, data)
            end
        end
    end

    print("[ChatServer] 消息撤回 uid=" .. tostring(userId) .. " msgId=" .. msgId)
end

-- ============================================================================
-- 全服系统公告（世界播报）
-- ============================================================================

--- 向所有在线玩家广播系统公告（如渡劫成功、BOSS 击杀等）
---@param announceType string 公告类型标签（"tribulation_success" / "boss_kill" / ...）
---@param text string         公告正文（支持 <font color=#RRGGBB>xxx</font> 富文本标签）
function M.BroadcastSystemAnnounce(announceType, text)
    if not GetOnlineUsers_ then return end
    local data = VariantMap()
    data["Type"] = Variant(announceType or "system")
    data["Text"] = Variant(text or "")

    for _, uid in ipairs(GetOnlineUsers_()) do
        SendToClient_(uid, EVENTS.CHAT_ANNOUNCE, data)
    end
    print("[ChatServer] 全服公告 type=" .. tostring(announceType)
          .. " text=" .. tostring(text):sub(1, 80))
end

-- ============================================================================
-- 玩家连接/断开
-- ============================================================================

---@param userId number
function M.OnPlayerDisconnect(userId)
    rateLimit_[userId]  = nil
    playerInfo_[userId] = nil  -- 清理在线状态，确保 OnQueryOnline 准确
end

return M
