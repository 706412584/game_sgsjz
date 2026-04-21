-- ============================================================================
-- mail_server.lua — 邮件系统服务端
-- 处理邮件发送(GM)、邮件拉取、标记已读、删除
-- 通过远程事件与客户端通信
-- ============================================================================
---@diagnostic disable: undefined-global

local PlayerMgr = nil  -- 延迟加载，避免循环依赖

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS

local M = {}

-- 连接管理
local serverConnections_ = {}   -- connKey -> connection
local connectionUserIds_ = {}   -- connKey -> userId (number)

-- GM 用户 ID(与 ui_gm.lua 一致)
local GM_USER_IDS = { [1644503283] = true, [529757584] = true }

-- 邮件消息类型 key
local MAIL_KEY = "mail"

-- 广播日志(内存，用于离线玩家上线后补发)
local broadcastLog_ = {}       -- { [id] = { id, senderUid, mailData, serverId, timestamp } }
local nextBroadcastId_ = 1
local BROADCAST_TTL = 7 * 86400  -- 广播记录保留7天
local cleanupTimer_ = 0
local revokedBroadcasts_ = {}  -- { [broadcastId] = true } 已撤回的广播ID集合

--- 向在线目标玩家推送"有新邮件"通知，使其客户端自动刷新邮箱
---@param targetUid number
local function notifyNewMail(targetUid)
    -- 在 serverConnections_ 中查找目标玩家的连接
    for ck, uid in pairs(connectionUserIds_) do
        if uid == targetUid then
            local targetConn = serverConnections_[ck]
            if targetConn then
                sendResult(targetConn, "new_mail", true, "")
            end
            break
        end
    end
end

-- ========== 初始化 ==========
function M.Init()
    -- 事件已由 shared.lua 统一注册，此处仅订阅处理函数
    -- 注意：CLIENT_READY 和 ClientDisconnected 由 server_main.lua 统一订阅，
    -- 通过 M.OnClientReady / M.OnClientDisconnected 回调，避免覆盖 server_main 的 handler
    SubscribeToEvent(EVENTS.MAIL_SEND,      "HandleMailSend")
    SubscribeToEvent(EVENTS.MAIL_FETCH,     "HandleMailFetch")
    SubscribeToEvent(EVENTS.MAIL_CLAIM,     "HandleMailClaim")
    SubscribeToEvent(EVENTS.MAIL_DELETE,    "HandleMailDelete")
    SubscribeToEvent(EVENTS.MAIL_GM_QUERY,  "HandleMailGmQuery")
    SubscribeToEvent(EVENTS.MAIL_GM_CLEAR,  "HandleMailGmClear")
    SubscribeToEvent(EVENTS.MAIL_REVOKE,    "HandleMailRevoke")
    SubscribeToEvent(EVENTS.MAIL_BROADCAST_LIST, "HandleMailBroadcastList")

    print("[MailServer] Initialized")
end

-- ========== 连接管理（由 server_main.lua 调用） ==========

--- 客户端就绪回调（由 server_main.lua HandleClientReady 调用）
function M.OnClientReady(connection)
    local connKey = tostring(connection)

    -- 提取 userId（必须 tonumber，GetInt64 可能返回 userdata）
    local userId = 0
    local identityUid = connection.identity["user_id"]
    if identityUid then
        userId = tonumber(identityUid:GetInt64()) or 0
    end

    -- 清理同一 userId 的旧连接（防止身份升级/重连导致重复条目）
    for ck, uid in pairs(connectionUserIds_) do
        if uid == userId and ck ~= connKey then
            print("[MailServer] Removing stale connection for userId=" .. tostring(userId) .. " oldKey=" .. ck)
            serverConnections_[ck] = nil
            connectionUserIds_[ck] = nil
        end
    end

    serverConnections_[connKey] = connection
    connectionUserIds_[connKey] = userId
    print("[MailServer] Client ready: userId=" .. tostring(userId))
end

--- 客户端断开回调（由 server_main.lua HandleClientDisconnected 调用）
function M.OnClientDisconnected(connection)
    local connKey = tostring(connection)
    local userId = connectionUserIds_[connKey] or 0
    serverConnections_[connKey] = nil
    connectionUserIds_[connKey] = nil
    print("[MailServer] Client disconnected: userId=" .. tostring(userId))
end

-- ========== 工具函数 ==========

--- 向指定连接发送操作结果
---@param conn userdata Connection
---@param action string 操作名
---@param success boolean
---@param message string
local function sendResult(conn, action, success, message)
    local data = VariantMap()
    data["Action"] = Variant(action)
    data["Success"] = Variant(success)
    data["Message"] = Variant(message or "")
    conn:SendRemoteEvent(EVENTS.MAIL_RESULT, true, data)
end

--- 从事件数据中提取连接和用户信息
---@param eventData table
---@return userdata|nil connection
---@return number userId
local function getConnAndUser(eventData)
    local connection = eventData["Connection"]:GetPtr("Connection")
    local connKey = tostring(connection)
    local userId = connectionUserIds_[connKey]
    return connection, userId, connKey
end

-- ========== 工具: 解析目标玩家 ==========

--- 将输入(可能是 playerId / 角色名 / userId)解析为真实的平台 userId
---@param inputStr string 输入字符串
---@return number|nil resolvedUid 解析后的平台 userId, 失败返回nil
local function resolveTargetUid(inputStr)
    if not PlayerMgr then PlayerMgr = require("server_player") end
    inputStr = tostring(inputStr)
    -- 遍历在线玩家, 匹配 playerId 或角色名
    for _, pid in ipairs(PlayerMgr.GetAllPlayerIds()) do
        local ps = PlayerMgr.GetState(pid)
        if ps and (ps.playerId == inputStr or ps.playerName == inputStr) then
            print("[MailServer] Resolved input=" .. inputStr .. " -> userId=" .. tostring(pid))
            return pid
        end
    end
    -- 未匹配到, 尝试作为数字 userId（支持离线玩家的平台UID）
    local num = tonumber(inputStr)
    if num and num > 0 then
        print("[MailServer] Resolved input=" .. inputStr .. " -> userId=" .. tostring(num) .. " (numeric fallback)")
        return num
    end
    return nil
end

-- ========== GM 发送邮件 ==========

function HandleMailSend(eventType, eventData)
    local conn, senderUid, connKey = getConnAndUser(eventData)
    if not senderUid then
        print("[MailServer] MailSend: unknown connection")
        return
    end

    -- 权限检查: 仅 GM 可发送
    if not GM_USER_IDS[senderUid] then
        print("[MailServer] MailSend: unauthorized userId=" .. tostring(senderUid))
        sendResult(conn, "send", false, "无权限")
        return
    end

    -- 延迟加载 PlayerMgr
    if not PlayerMgr then PlayerMgr = require("server_player") end

    -- 解析邮件数据 — TargetUid 现在是字符串(支持 角色ID/角色名/平台UID)
    local rawTarget  = eventData["TargetUid"]:GetString()
    local title      = eventData["Title"]:GetString()
    local content    = eventData["Content"]:GetString()
    local rewardJson = eventData["RewardJson"]:GetString()
    local broadcast  = eventData["Broadcast"]:GetBool()
    local serverId   = eventData["ServerId"]:GetInt()

    -- 解析多资源奖励 JSON
    local reward = nil
    if rewardJson and rewardJson ~= "" then
        local ok, decoded = pcall(cjson.decode, rewardJson)
        if ok and type(decoded) == "table" then
            reward = decoded
        else
            print("[MailServer] Failed to decode rewardJson: " .. tostring(rewardJson))
        end
    end

    -- 非广播时, 用 resolveTargetUid 解析角色ID/角色名/平台UID
    local targetUid = nil
    if not broadcast then
        targetUid = resolveTargetUid(rawTarget)
        if not targetUid then
            print("[MailServer] MailSend: cannot resolve target=" .. tostring(rawTarget))
            sendResult(conn, "send", false, "未找到该玩家: " .. rawTarget .. " (离线玩家请用平台UID)")
            return
        end
    end

    local mailData = {
        title      = title,
        content    = content,
        reward     = reward,        -- 多资源奖励 table
        senderName = "系统",
        sendTime   = os.time(),
        serverId   = serverId,  -- 记录目标区服，供客户端过滤
    }

    print("[MailServer] Sending mail: senderUid=" .. tostring(senderUid)
        .. " title=" .. title .. " reward=" .. tostring(rewardJson)
        .. " broadcast=" .. tostring(broadcast)
        .. " rawTarget=" .. tostring(rawTarget) .. " resolvedUid=" .. tostring(targetUid)
        .. " serverId=" .. tostring(serverId)
        .. " sameAsSender=" .. tostring(targetUid == senderUid))

    if broadcast then
        -- 生成广播ID并嵌入邮件数据(用于撤回过滤)
        local bcId = nextBroadcastId_
        nextBroadcastId_ = nextBroadcastId_ + 1
        mailData.broadcastId = bcId

        -- 本服全体: 发送给指定区服的所有在线玩家
        -- 先收集去重的 userId 列表（防止同一 userId 多个 connKey 导致重复发送）
        local uniqueUids = {}  -- uid -> true
        for ck, uid in pairs(connectionUserIds_) do
            if uid and uid ~= 0 then
                uniqueUids[uid] = true
            end
        end

        local sentCount = 0
        local totalCount = 0
        for uid, _ in pairs(uniqueUids) do
            -- 按区服过滤: 只发给目标区服玩家
            local playerSid = PlayerMgr.GetServerId(uid) or 0
            if serverId == 0 or playerSid == serverId then
                totalCount = totalCount + 1
                local capturedUid = uid  -- 闭包捕获
                -- Send(ownerUid, key, senderUid, data): 第1参数是收件人
                serverCloud.message:Send(capturedUid, MAIL_KEY, senderUid, mailData, {
                    ok = function(errorCode, errorDesc)
                        if errorCode == 0 or errorCode == nil then
                            sentCount = sentCount + 1
                            print("[MailServer] Broadcast mail sent to uid=" .. tostring(capturedUid))
                            -- 通知该玩家自动刷新邮箱
                            notifyNewMail(capturedUid)
                        else
                            print("[MailServer] Broadcast mail failed for uid=" .. tostring(capturedUid)
                                .. " code=" .. tostring(errorCode) .. " desc=" .. tostring(errorDesc))
                        end
                    end,
                    error = function(code, reason)
                        print("[MailServer] Broadcast mail error for uid=" .. tostring(capturedUid)
                            .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
                    end,
                })
            end
        end
        -- 记录广播日志，用于离线玩家上线后补发
        broadcastLog_[bcId] = {
            id        = bcId,
            senderUid = senderUid,
            mailData  = mailData,
            serverId  = serverId,
            timestamp = os.time(),
        }
        print("[MailServer] Broadcast logged: bcId=" .. bcId .. " serverId=" .. tostring(serverId))

        local srvLabel = serverId > 0 and ("S" .. serverId) or "全服"
        sendResult(conn, "send", true, srvLabel .. "邮件已发送(在线" .. totalCount .. "人, 离线玩家上线后自动补发)")
    else
        -- 定向邮件: 发给指定玩家
        -- Send(ownerUid, key, senderUid, data): 第1参数是收件人(owner)，第3参数是发件人标记
        serverCloud.message:Send(targetUid, MAIL_KEY, senderUid, mailData, {
            ok = function(errorCode, errorDesc)
                if errorCode == 0 or errorCode == nil then
                    print("[MailServer] Mail sent to uid=" .. tostring(targetUid))
                    sendResult(conn, "send", true, "邮件已发给UID:" .. tostring(targetUid))
                    -- 通知目标玩家（如果在线）自动刷新邮箱
                    notifyNewMail(targetUid)
                else
                    print("[MailServer] Mail send failed: code=" .. tostring(errorCode))
                    sendResult(conn, "send", false, "发送失败: " .. tostring(errorDesc))
                end
            end,
            error = function(code, reason)
                print("[MailServer] Mail send error: " .. tostring(code) .. " " .. tostring(reason))
                sendResult(conn, "send", false, "发送错误: " .. tostring(reason))
            end,
        })
    end
end

-- ========== 拉取邮件 ==========

--- 将 messages 数组转换为可序列化的邮件列表
---@param messages table[]
---@param claimed boolean 是否已领取(已读=已领取)
---@return table[]
---@param messages table[] API 返回的消息列表
---@param claimed boolean 是否已领取
---@param filterServerId? number 按区服过滤: nil=不过滤, 其他=只保留 serverId==0 或匹配的邮件
local function messagesToMailList(messages, claimed, filterServerId)
    local list = {}
    for _, msg in ipairs(messages) do
        -- msg.value 可能是 table 也可能是 JSON string(取决于积分服实现)
        local val = msg.value
        if type(val) == "string" then
            local ok, decoded = pcall(cjson.decode, val)
            if ok and type(decoded) == "table" then
                val = decoded
            end
        end
        -- 撤回过滤: 跳过已撤回的广播邮件
        if type(val) == "table" and val.broadcastId then
            if revokedBroadcasts_[val.broadcastId] then
                goto continue
            end
        end
        -- 区服过滤: 只显示全服邮件(serverId==0)、本区服邮件、或无区服标记的定向邮件
        if filterServerId then
            local mailSid = (type(val) == "table" and type(val.serverId) == "number") and val.serverId or nil
            if mailSid and mailSid ~= 0 and mailSid ~= filterServerId then
                goto continue  -- 跳过其他区服的邮件
            end
        end
        table.insert(list, {
            id       = tostring(msg.message_id),  -- 转字符串避免 cjson 大整数精度丢失
            value    = val,
            time     = msg.time,
            claimed  = claimed or false,
        })
        ::continue::
    end
    return list
end

--- 发送邮件列表给客户端
---@param conn userdata Connection
---@param mailList table[]
local function sendMailList(conn, mailList)
    local jsonStr = cjson.encode(mailList)
    local data = VariantMap()
    data["MailJson"] = Variant(jsonStr)
    data["Count"]    = Variant(#mailList)
    conn:SendRemoteEvent(EVENTS.MAIL_LIST, true, data)
end

function HandleMailFetch(eventType, eventData)
    local conn, userId, connKey = getConnAndUser(eventData)
    if not userId then
        print("[MailServer] MailFetch: unknown connection")
        return
    end

    local fetchAll = eventData["FetchAll"]:GetBool()
    -- 获取玩家当前区服，用于过滤非本区服的广播邮件
    local playerSid = PlayerMgr.GetServerId(userId) or 0
    print("[MailServer] Fetching mail for uid=" .. tostring(userId) .. " fetchAll=" .. tostring(fetchAll) .. " playerSid=" .. tostring(playerSid))

    if not fetchAll then
        -- 仅拉取未领取邮件: read=false(未读=未领取)
        serverCloud.message:Get(userId, MAIL_KEY, false, {
            ok = function(messages)
                if not messages then messages = {} end
                local filtered = messagesToMailList(messages, false, playerSid)
                print("[MailServer] Found " .. #messages .. " unclaimed mails, " .. #filtered .. " after realm filter for uid=" .. tostring(userId))
                sendMailList(conn, filtered)
            end,
            error = function(code, reason)
                print("[MailServer] Fetch error: " .. tostring(code) .. " " .. tostring(reason))
                sendResult(conn, "fetch", false, "拉取邮件失败: " .. tostring(reason))
            end,
        })
    else
        -- 拉取全部邮件: 未读(未领取) + 已读(已领取)
        serverCloud.message:Get(userId, MAIL_KEY, false, {
            ok = function(unreadMsgs)
                if not unreadMsgs then unreadMsgs = {} end
                serverCloud.message:Get(userId, MAIL_KEY, true, {
                    ok = function(readMsgs)
                        if not readMsgs then readMsgs = {} end
                        -- 未领取在前，已领取在后（按区服过滤）
                        local allList = messagesToMailList(unreadMsgs, false, playerSid)
                        local claimedList = messagesToMailList(readMsgs, true, playerSid)
                        for _, item in ipairs(claimedList) do
                            table.insert(allList, item)
                        end
                        print("[MailServer] Found " .. #unreadMsgs .. " unclaimed + " .. #readMsgs .. " claimed mails, " .. #allList .. " after realm filter for uid=" .. tostring(userId))
                        sendMailList(conn, allList)
                    end,
                    error = function(code, reason)
                        print("[MailServer] Fetch read mails error: " .. tostring(code) .. " " .. tostring(reason))
                        sendMailList(conn, messagesToMailList(unreadMsgs, false, playerSid))
                    end,
                })
            end,
            error = function(code, reason)
                print("[MailServer] Fetch error: " .. tostring(code) .. " " .. tostring(reason))
                sendResult(conn, "fetch", false, "拉取邮件失败: " .. tostring(reason))
            end,
        })
    end
end

-- ========== 领取(标记已读) ==========

-- 服务端已领取防重集合: { [messageId] = true }
local claimedSet_ = {}

function HandleMailClaim(eventType, eventData)
    local conn, userId, connKey = getConnAndUser(eventData)
    if not userId then return end

    local msgIdStr = eventData["MessageId"]:GetString()
    print("[MailServer] Claiming mail: uid=" .. tostring(userId) .. " msgId=" .. msgIdStr)

    -- 服务端防重: 同一消息只允许领取一次（统一用字符串 key）
    if claimedSet_[msgIdStr] then
        print("[MailServer] Already claimed (server dedup): " .. msgIdStr)
        sendResult(conn, "claim", false, "已领取过")
        return
    end

    -- 先拉取该玩家的未读消息，确认 messageId 确实存在且未读
    serverCloud.message:Get(userId, MAIL_KEY, false, {
        ok = function(messages)
            if not messages then messages = {} end
            -- 查找目标消息（统一转 string 比较，避免类型不匹配）
            local found = nil
            for _, msg in ipairs(messages) do
                if tostring(msg.message_id) == msgIdStr then
                    found = msg
                    break
                end
            end
            if not found then
                print("[MailServer] Claim rejected: msgId=" .. msgIdStr .. " not in unread list (count=" .. #messages .. ", already claimed or not exist)")
                sendResult(conn, "claim", false, "邮件已领取或不存在")
                return
            end
            -- 二次防重(Get回调可能延迟)
            if claimedSet_[msgIdStr] then
                print("[MailServer] Already claimed (race condition): " .. msgIdStr)
                sendResult(conn, "claim", false, "已领取过")
                return
            end
            claimedSet_[msgIdStr] = true

            -- 标记已读（使用 API 返回的原始 message_id，保持类型一致）
            serverCloud.message:MarkRead(found.message_id, {
                ok = function(errCode, errDesc)
                    print("[MailServer] Mail claimed (marked read): " .. msgIdStr)

                    -- 在服务端直接发放奖励(防止客户端伪造 mail_reward)
                    local val = found.value
                    if type(val) == "string" then
                        local dok, dval = pcall(cjson.decode, val)
                        if dok and type(dval) == "table" then val = dval end
                    end
                    if type(val) == "table" then
                        if not PlayerMgr then PlayerMgr = require("server_player") end
                        local GameServer = require("server_game")
                        if val.reward and type(val.reward) == "table" then
                            -- 新版多资源奖励
                            GameServer.ApplyMailReward(userId, nil, nil, val.title or "邮件", val.reward)
                        else
                            -- 兼容旧版单资源邮件
                            local rewardType = val.rewardType or ""
                            local rewardAmt  = tonumber(val.rewardAmt) or 0
                            if rewardAmt > 0 then
                                GameServer.ApplyMailReward(userId, rewardType, rewardAmt, val.title or "邮件")
                            end
                        end
                    end

                    sendResult(conn, "claim", true, msgIdStr)
                end,
                error = function(code, reason)
                    -- MarkRead 失败，撤销防重标记
                    claimedSet_[msgIdStr] = nil
                    print("[MailServer] MarkRead error: " .. tostring(code) .. " " .. tostring(reason))
                    sendResult(conn, "claim", false, "领取失败")
                end,
            })
        end,
        error = function(code, reason)
            print("[MailServer] Claim check error: " .. tostring(code) .. " " .. tostring(reason))
            sendResult(conn, "claim", false, "领取校验失败")
        end,
    })
end

-- ========== 删除邮件 ==========

function HandleMailDelete(eventType, eventData)
    local conn, userId, connKey = getConnAndUser(eventData)
    if not userId then return end

    local msgIdStr = eventData["MessageId"]:GetString()
    print("[MailServer] Deleting mail: uid=" .. tostring(userId) .. " msgId=" .. msgIdStr)

    -- 先 Get 未读+已读找到真实的 message_id（API 返回 number），再用原始值调 Delete
    -- 避免客户端字符串与 API 类型不一致
    serverCloud.message:Get(userId, MAIL_KEY, false, {
        ok = function(unreadMsgs)
            if not unreadMsgs then unreadMsgs = {} end
            serverCloud.message:Get(userId, MAIL_KEY, true, {
                ok = function(readMsgs)
                    if not readMsgs then readMsgs = {} end
                    -- 合并搜索
                    local found = nil
                    for _, msg in ipairs(unreadMsgs) do
                        if tostring(msg.message_id) == msgIdStr then found = msg; break end
                    end
                    if not found then
                        for _, msg in ipairs(readMsgs) do
                            if tostring(msg.message_id) == msgIdStr then found = msg; break end
                        end
                    end
                    if not found then
                        print("[MailServer] Delete: msgId=" .. msgIdStr .. " not found in mailbox")
                        sendResult(conn, "delete", false, "邮件不存在")
                        return
                    end
                    -- 使用 API 原始 message_id 调用 Delete
                    serverCloud.message:Delete(found.message_id, {
                        ok = function(result, errCode2, errDesc2)
                            print("[MailServer] Mail deleted: " .. msgIdStr)
                            sendResult(conn, "delete", true, msgIdStr)
                        end,
                        error = function(code, reason)
                            print("[MailServer] Delete error: " .. tostring(code) .. " " .. tostring(reason))
                            sendResult(conn, "delete", false, "删除失败")
                        end,
                    })
                end,
                error = function(code, reason)
                    print("[MailServer] Delete fetch read error: " .. tostring(reason))
                    sendResult(conn, "delete", false, "删除失败")
                end,
            })
        end,
        error = function(code, reason)
            print("[MailServer] Delete fetch error: " .. tostring(reason))
            sendResult(conn, "delete", false, "删除失败")
        end,
    })
end

-- ========== GM 查询指定玩家邮箱 ==========

function HandleMailGmQuery(eventType, eventData)
    local conn, senderUid, connKey = getConnAndUser(eventData)
    if not senderUid then return end

    -- 权限检查
    if not GM_USER_IDS[senderUid] then
        sendResult(conn, "gm_query", false, "无权限")
        return
    end

    -- 支持字符串输入: 平台UID / 角色ID / 角色名
    local rawInput = eventData["TargetUid"]:GetString()
    if rawInput == "" then rawInput = tostring(eventData["TargetUid"]:GetInt64()) end
    local targetUid = resolveTargetUid(rawInput)
    if not targetUid then
        sendResult(conn, "gm_query", false, "未找到该玩家(离线玩家请使用平台UID)")
        return
    end
    print("[MailServer] GM querying mail for uid=" .. tostring(targetUid) .. " (input=" .. rawInput .. ")")

    -- 拉取未读 + 已读
    serverCloud.message:Get(targetUid, MAIL_KEY, false, {
        ok = function(unreadMsgs)
            if not unreadMsgs then unreadMsgs = {} end
            serverCloud.message:Get(targetUid, MAIL_KEY, true, {
                ok = function(readMsgs)
                    if not readMsgs then readMsgs = {} end
                    local allList = messagesToMailList(unreadMsgs, false)
                    local readList = messagesToMailList(readMsgs, true)
                    for _, item in ipairs(readList) do
                        table.insert(allList, item)
                    end
                    print("[MailServer] GM found " .. #allList .. " mails for uid=" .. tostring(targetUid))
                    local jsonStr = cjson.encode(allList)
                    local data = VariantMap()
                    data["MailJson"]   = Variant(jsonStr)
                    data["Count"]      = Variant(#allList)
                    data["TargetUid"]  = Variant(tostring(targetUid))
                    conn:SendRemoteEvent(EVENTS.MAIL_GM_LIST, true, data)
                end,
                error = function(code, reason)
                    -- 已读失败，返回未读部分
                    local list = messagesToMailList(unreadMsgs, false)
                    local jsonStr = cjson.encode(list)
                    local data = VariantMap()
                    data["MailJson"]   = Variant(jsonStr)
                    data["Count"]      = Variant(#list)
                    data["TargetUid"]  = Variant(tostring(targetUid))
                    conn:SendRemoteEvent(EVENTS.MAIL_GM_LIST, true, data)
                end,
            })
        end,
        error = function(code, reason)
            print("[MailServer] GM query error: " .. tostring(code) .. " " .. tostring(reason))
            sendResult(conn, "gm_query", false, "查询失败: " .. tostring(reason))
        end,
    })
end

-- ========== GM 清空指定玩家邮箱 ==========

function HandleMailGmClear(eventType, eventData)
    local conn, senderUid, connKey = getConnAndUser(eventData)
    if not senderUid then return end

    -- 权限检查
    if not GM_USER_IDS[senderUid] then
        sendResult(conn, "gm_clear", false, "无权限")
        return
    end

    -- 支持字符串输入: 平台UID / 角色ID / 角色名
    local rawInput = eventData["TargetUid"]:GetString()
    if rawInput == "" then rawInput = tostring(eventData["TargetUid"]:GetInt64()) end
    local targetUid = resolveTargetUid(rawInput)
    if not targetUid then
        sendResult(conn, "gm_clear", false, "未找到该玩家(离线玩家请使用平台UID)")
        return
    end
    print("[MailServer] GM clearing mail for uid=" .. tostring(targetUid) .. " (input=" .. rawInput .. ")")

    -- 先拉取全部邮件，再逐个删除
    serverCloud.message:Get(targetUid, MAIL_KEY, false, {
        ok = function(unreadMsgs)
            if not unreadMsgs then unreadMsgs = {} end
            serverCloud.message:Get(targetUid, MAIL_KEY, true, {
                ok = function(readMsgs)
                    if not readMsgs then readMsgs = {} end
                    local allMsgs = {}
                    for _, m in ipairs(unreadMsgs) do table.insert(allMsgs, m) end
                    for _, m in ipairs(readMsgs) do table.insert(allMsgs, m) end

                    if #allMsgs == 0 then
                        sendResult(conn, "gm_clear", true, "该玩家邮箱已为空")
                        return
                    end

                    local total = #allMsgs
                    local deleted = 0
                    local failed = 0
                    for _, msg in ipairs(allMsgs) do
                        serverCloud.message:Delete(msg.message_id, {
                            ok = function()
                                deleted = deleted + 1
                                if deleted + failed >= total then
                                    sendResult(conn, "gm_clear", true,
                                        "已清空 " .. deleted .. " 封邮件" ..
                                        (failed > 0 and ("，" .. failed .. " 封失败") or ""))
                                end
                            end,
                            error = function()
                                failed = failed + 1
                                if deleted + failed >= total then
                                    sendResult(conn, "gm_clear", failed < total,
                                        "已清空 " .. deleted .. " 封邮件，" .. failed .. " 封失败")
                                end
                            end,
                        })
                    end
                end,
                error = function(code, reason)
                    sendResult(conn, "gm_clear", false, "清空失败: " .. tostring(reason))
                end,
            })
        end,
        error = function(code, reason)
            sendResult(conn, "gm_clear", false, "清空失败: " .. tostring(reason))
        end,
    })
end

-- ========== 离线玩家上线补发广播邮件 ==========

--- 玩家加载完成后调用，补发该玩家缺失的广播邮件
---@param userId number
function M.OnPlayerLoaded(userId)
    if not PlayerMgr then PlayerMgr = require("server_player") end
    local s = PlayerMgr.GetState(userId)
    if not s then return end

    local lastId = s.lastBroadcastId or 0
    local playerSid = PlayerMgr.GetServerId(userId) or 0
    local sentCount = 0

    -- 遍历广播日志，补发 id > lastBroadcastId 的记录（跳过已撤回的）
    for bcId, record in pairs(broadcastLog_) do
        if bcId > lastId and not revokedBroadcasts_[bcId] then
            -- 区服过滤: serverId==0 表示全服，否则只发给对应区服
            if record.serverId == 0 or playerSid == record.serverId then
                local capturedBcId = bcId  -- 闭包捕获
                -- Send(ownerUid, key, senderUid, data): 第1参数是收件人
                serverCloud.message:Send(userId, MAIL_KEY, record.senderUid, record.mailData, {
                    ok = function(errorCode, errorDesc)
                        if errorCode == 0 or errorCode == nil then
                            print("[MailServer] Broadcast catch-up sent: bcId=" .. capturedBcId .. " uid=" .. tostring(userId))
                            -- 通知玩家有新邮件
                            notifyNewMail(userId)
                        end
                    end,
                    error = function(code, reason)
                        print("[MailServer] Broadcast catch-up error: bcId=" .. capturedBcId .. " uid=" .. tostring(userId)
                            .. " " .. tostring(reason))
                    end,
                })
                sentCount = sentCount + 1
            end
        end
    end

    -- 更新玩家的 lastBroadcastId 为当前最大值
    if nextBroadcastId_ - 1 > lastId then
        s.lastBroadcastId = nextBroadcastId_ - 1
        PlayerMgr.SetDirty(userId)
    end

    if sentCount > 0 then
        print("[MailServer] OnPlayerLoaded: uid=" .. tostring(userId)
            .. " caught up " .. sentCount .. " broadcast mails (lastId " .. lastId .. " -> " .. s.lastBroadcastId .. ")")
    end
end

-- ========== Update: 清理过期广播日志 ==========
function M.Update(dt)
    cleanupTimer_ = cleanupTimer_ + dt
    if cleanupTimer_ < 300 then return end  -- 每5分钟清理一次
    cleanupTimer_ = 0

    local now = os.time()
    local removed = 0
    for bcId, record in pairs(broadcastLog_) do
        if now - record.timestamp > BROADCAST_TTL then
            broadcastLog_[bcId] = nil
            revokedBroadcasts_[bcId] = nil  -- 同步清理撤回记录
            removed = removed + 1
        end
    end
    if removed > 0 then
        print("[MailServer] Cleaned up " .. removed .. " expired broadcast records")
    end
end

-- ========== GM 撤回广播邮件 ==========

function HandleMailRevoke(eventType, eventData)
    local conn, senderUid = getConnAndUser(eventData)
    if not senderUid then return end

    if not GM_USER_IDS[senderUid] then
        sendResult(conn, "revoke", false, "无权限")
        return
    end

    local bcId = eventData["BroadcastId"]:GetInt()
    if bcId <= 0 then
        sendResult(conn, "revoke", false, "无效的广播ID")
        return
    end

    if not broadcastLog_[bcId] then
        sendResult(conn, "revoke", false, "广播记录不存在(可能已过期)")
        return
    end

    if revokedBroadcasts_[bcId] then
        sendResult(conn, "revoke", false, "该广播已撤回")
        return
    end

    revokedBroadcasts_[bcId] = true
    print("[MailServer] Broadcast revoked: bcId=" .. bcId .. " by uid=" .. tostring(senderUid))
    sendResult(conn, "revoke", true, "广播 #" .. bcId .. " 已撤回(未领取的将不再显示)")
end

-- ========== GM 查询广播历史 ==========

function HandleMailBroadcastList(eventType, eventData)
    local conn, senderUid = getConnAndUser(eventData)
    if not senderUid then return end

    if not GM_USER_IDS[senderUid] then
        sendResult(conn, "broadcast_list", false, "无权限")
        return
    end

    local list = {}
    for bcId, record in pairs(broadcastLog_) do
        table.insert(list, {
            id        = bcId,
            title     = record.mailData.title or "",
            content   = record.mailData.content or "",
            serverId  = record.serverId,
            timestamp = record.timestamp,
            revoked   = revokedBroadcasts_[bcId] or false,
        })
    end
    -- 按 id 降序排列(最新的在前)
    table.sort(list, function(a, b) return a.id > b.id end)

    local jsonStr = cjson.encode(list)
    local data = VariantMap()
    data["ListJson"] = Variant(jsonStr)
    data["Count"]    = Variant(#list)
    conn:SendRemoteEvent(EVENTS.MAIL_BROADCAST_LIST_RESP, true, data)
    print("[MailServer] Broadcast list sent: " .. #list .. " records to uid=" .. tostring(senderUid))
end

return M
