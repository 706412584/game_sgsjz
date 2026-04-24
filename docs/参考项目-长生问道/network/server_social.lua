-- ============================================================================
-- 《问道长生》服务端社交模块
-- 职责：好友申请/同意/拒绝/解除/赠送好感
-- 存储：serverCloud.list 存好友关系，serverCloud.message 存好友申请
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
local DataSocial = require("data_social")
---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- ============================================================================
-- 依赖注入（由 server_main.lua 调用）
-- ============================================================================

---@type table { connections, connUserIds, userIdToConn, SendToClient }
local deps_ = nil

---@param deps table
function M.Init(deps)
    deps_ = deps
    print("[ServerSocial] 社交模块初始化完成")
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 统一回复客户端
---@param userId number
---@param action string
---@param success boolean
---@param msg string
---@param extra table|nil
local function Reply(userId, action, success, msg, extra)
    local data = VariantMap()
    data["Action"]  = Variant(action)
    data["Success"] = Variant(success)
    data["Msg"]     = Variant(msg)
    if extra then
        for k, v in pairs(extra) do
            data[k] = v
        end
    end
    deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
end

-- ============================================================================
-- 统一入口
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleSocialOp(userId, eventData)
    local action = eventData["Action"]:GetString()

    if action == DataSocial.ACTION.ADD_FRIEND then
        M.OnAddFriend(userId, eventData)
    elseif action == DataSocial.ACTION.ACCEPT_FRIEND then
        M.OnAcceptFriend(userId, eventData)
    elseif action == DataSocial.ACTION.REJECT_FRIEND then
        M.OnRejectFriend(userId, eventData)
    elseif action == DataSocial.ACTION.REJECT_ALL then
        M.OnRejectAll(userId)
    elseif action == DataSocial.ACTION.REMOVE_FRIEND then
        M.OnRemoveFriend(userId, eventData)
    elseif action == DataSocial.ACTION.SEND_GIFT then
        M.OnSendGift(userId, eventData)
    elseif action == DataSocial.ACTION.GET_FRIENDS then
        M.OnGetFriends(userId)
    elseif action == DataSocial.ACTION.GET_PENDING then
        M.OnGetPending(userId)
    -- 道侣
    elseif action == DataSocial.ACTION.PROPOSE_COUPLE then
        M.OnProposeDaoCouple(userId, eventData)
    elseif action == DataSocial.ACTION.COUPLE_PRACTICE then
        M.OnCouplePractice(userId, eventData)
    elseif action == DataSocial.ACTION.COUPLE_LEVELUP then
        M.OnCoupleLevelUp(userId, eventData)
    -- 师徒
    elseif action == DataSocial.ACTION.PROPOSE_MASTER then
        M.OnProposeMaster(userId, eventData)
    elseif action == DataSocial.ACTION.MASTER_TEACH then
        M.OnMasterTeach(userId, eventData)
    -- 切磋
    elseif action == DataSocial.ACTION.CHALLENGE then
        M.OnChallenge(userId, eventData)
    elseif action == DataSocial.ACTION.CHALLENGE_SETTLE then
        M.OnChallengeSettle(userId, eventData)
    else
        Reply(userId, action or "unknown", false, "未知社交操作")
    end
end

-- ============================================================================
-- 好友申请：通过 serverCloud.message 发送申请
-- 申请方 → message → 目标方
-- key = "friend_req"
-- value = { fromUid, fromName, fromRealm, relation, timestamp }
-- ============================================================================

function M.OnAddFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "add_friend", false, "服务端存储不可用")
        return
    end

    local targetUidStr = eventData["TargetUid"]:GetString()
    local targetUid    = tonumber(targetUidStr)
    local senderName   = eventData["SenderName"]:GetString()
    local senderRealm  = eventData["SenderRealm"]:GetString()

    if not targetUid or targetUid == userId then
        Reply(userId, "add_friend", false, "无效的目标玩家")
        return
    end

    -- 检查是否已经是好友（查自己的好友列表）
    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            for _, item in ipairs(list or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    Reply(userId, "add_friend", false, "对方已经是你的好友")
                    return
                end
            end

            -- 检查好友上限
            if #(list or {}) >= DataSocial.RELATION_CONFIG.friend.maxCount then
                Reply(userId, "add_friend", false, "好友数量已达上限")
                return
            end

            -- 发送好友申请消息给目标玩家
            local reqValue = {
                fromUid   = userId,
                fromName  = senderName,
                fromRealm = senderRealm,
                relation  = "friend",
                timestamp = os.time(),
            }

            serverCloud.message:Send(userId, "friend_req", targetUid, reqValue, {
                ok = function(errorCode, errorDesc)
                    if errorCode == 0 or errorCode == nil then
                        print("[ServerSocial] 好友申请 " .. tostring(userId) .. " → " .. tostring(targetUid))
                        Reply(userId, "add_friend", true, "好友申请已发送")

                        -- 如果目标在线，通知刷新待处理列表
                        Reply(targetUid, "pending_notify", true, "你收到了一条好友申请")
                    else
                        Reply(userId, "add_friend", false, "申请发送失败: " .. tostring(errorDesc))
                    end
                end,
            })
        end,
        error = function(code, reason)
            Reply(userId, "add_friend", false, "查询好友列表失败")
        end,
    })
end

-- ============================================================================
-- 同意好友申请
-- 1. 读取 message，获取申请者 uid
-- 2. 双方各加一条 friends list item
-- 3. 删除 message
-- ============================================================================

function M.OnAcceptFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "accept_friend", false, "服务端存储不可用")
        return
    end

    local messageIdStr = eventData["MessageId"]:GetString()
    local messageId    = tonumber(messageIdStr) or 0
    -- 申请者信息由客户端从 pending list 传来
    local fromUid      = tonumber(eventData["FromUid"]:GetString()) or 0
    local fromName     = eventData["FromName"]:GetString()
    local fromRealm    = eventData["FromRealm"]:GetString()
    local myName       = eventData["MyName"]:GetString()
    local myRealm      = eventData["MyRealm"]:GetString()

    if fromUid == 0 then
        Reply(userId, "accept_friend", false, "无效的申请信息")
        return
    end

    -- 先检查自己好友是否已满
    serverCloud.list:Get(userId, "friends", {
        ok = function(myFriends)
            if #(myFriends or {}) >= DataSocial.RELATION_CONFIG.friend.maxCount then
                Reply(userId, "accept_friend", false, "你的好友数量已达上限")
                return
            end

            -- 检查对方好友是否已满
            serverCloud.list:Get(fromUid, "friends", {
                ok = function(otherFriends)
                    if #(otherFriends or {}) >= DataSocial.RELATION_CONFIG.friend.maxCount then
                        Reply(userId, "accept_friend", false, "对方好友数量已达上限")
                        return
                    end

                    -- 检查是否已有好友关系（防重复）
                    for _, item in ipairs(myFriends or {}) do
                        if (item.value or {}).friendUid == fromUid then
                            -- 已有关系，只需删除消息
                            if messageId > 0 then
                                serverCloud.message:MarkRead(messageId)
                                serverCloud.message:Delete(messageId)
                            end
                            Reply(userId, "accept_friend", false, "你们已经是好友了")
                            return
                        end
                    end

                    -- 双方互加好友
                    local now = os.time()

                    -- 我方记录
                    serverCloud.list:Add(userId, "friends", {
                        friendUid   = fromUid,
                        friendName  = fromName,
                        friendRealm = fromRealm,
                        relation    = "friend",
                        favor       = 0,
                        createdAt   = now,
                    })

                    -- 对方记录
                    serverCloud.list:Add(fromUid, "friends", {
                        friendUid   = userId,
                        friendName  = myName,
                        friendRealm = myRealm,
                        relation    = "friend",
                        favor       = 0,
                        createdAt   = now,
                    })

                    -- 删除申请消息
                    if messageId > 0 then
                        serverCloud.message:MarkRead(messageId)
                        serverCloud.message:Delete(messageId)
                    end

                    print("[ServerSocial] 好友建立 " .. tostring(userId) .. " <-> " .. tostring(fromUid))
                    Reply(userId, "accept_friend", true, "已成为好友")
                    Reply(fromUid, "friend_accepted", true, myName .. " 接受了你的好友申请")
                end,
                error = function()
                    Reply(userId, "accept_friend", false, "查询对方好友列表失败")
                end,
            })
        end,
        error = function()
            Reply(userId, "accept_friend", false, "查询好友列表失败")
        end,
    })
end

-- ============================================================================
-- 拒绝好友申请
-- ============================================================================

function M.OnRejectFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "reject_friend", false, "服务端存储不可用")
        return
    end

    local messageIdStr = eventData["MessageId"]:GetString()
    local messageId = tonumber(messageIdStr) or 0

    if messageId > 0 then
        serverCloud.message:MarkRead(messageId)
        serverCloud.message:Delete(messageId)
    end

    Reply(userId, "reject_friend", true, "已拒绝该申请")
end

-- ============================================================================
-- 一键拒绝全部
-- ============================================================================

function M.OnRejectAll(userId)
    if not serverCloud then
        Reply(userId, "reject_all", false, "服务端存储不可用")
        return
    end

    serverCloud.message:Get(userId, "friend_req", false, {
        ok = function(messages)
            local count = 0
            for _, msg in ipairs(messages or {}) do
                serverCloud.message:MarkRead(msg.message_id)
                serverCloud.message:Delete(msg.message_id)
                count = count + 1
            end
            Reply(userId, "reject_all", true, "已拒绝全部 " .. count .. " 条申请")
        end,
        error = function()
            Reply(userId, "reject_all", false, "获取申请列表失败")
        end,
    })
end

-- ============================================================================
-- 解除好友关系
-- 双向删除 friends list item
-- ============================================================================

function M.OnRemoveFriend(userId, eventData)
    if not serverCloud then
        Reply(userId, "remove_friend", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    if targetUid == 0 then
        Reply(userId, "remove_friend", false, "无效的目标玩家")
        return
    end

    -- 删除我方记录
    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            for _, item in ipairs(list or {}) do
                if (item.value or {}).friendUid == targetUid then
                    serverCloud.list:Delete(item.list_id)
                    break
                end
            end

            -- 删除对方记录
            serverCloud.list:Get(targetUid, "friends", {
                ok = function(otherList)
                    for _, item in ipairs(otherList or {}) do
                        if (item.value or {}).friendUid == userId then
                            serverCloud.list:Delete(item.list_id)
                            break
                        end
                    end
                    print("[ServerSocial] 解除好友 " .. tostring(userId) .. " <-> " .. tostring(targetUid))
                    Reply(userId, "remove_friend", true, "已解除好友关系")
                    Reply(targetUid, "friend_removed", true, "好友关系已被解除")
                end,
                error = function()
                    -- 对方删除失败不影响主流程
                    Reply(userId, "remove_friend", true, "已解除好友关系")
                end,
            })
        end,
        error = function()
            Reply(userId, "remove_friend", false, "操作失败")
        end,
    })
end

-- ============================================================================
-- 赠送礼物（增加好感度）
-- ============================================================================

function M.OnSendGift(userId, eventData)
    if not serverCloud then
        Reply(userId, "send_gift", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    local giftId    = eventData["GiftId"]:GetString()

    if targetUid == 0 then
        Reply(userId, "send_gift", false, "无效的目标玩家")
        return
    end

    -- 查找礼物配置
    local giftConfig = nil
    for _, g in ipairs(DataSocial.FAVOR_GIFTS) do
        if g.id == giftId then
            giftConfig = g
            break
        end
    end
    if not giftConfig then
        Reply(userId, "send_gift", false, "无效的礼物")
        return
    end

    local today = os.date("%Y-%m-%d")
    local giftCost = math.max(0, math.floor(tonumber(giftConfig.price) or 0))

    -- 更新我方好友记录的好感度（含扣费与每日上限校验）
    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            local found = false
            for _, item in ipairs(list or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    found = true

                    local usedToday = 0
                    if val.giftDate == today then
                        usedToday = tonumber(val.giftCount) or 0
                    end
                    if usedToday >= DataSocial.DAILY_GIFT_LIMIT then
                        Reply(userId, "send_gift", false,
                            "今日已赠送" .. DataSocial.DAILY_GIFT_LIMIT .. "次，请明日再来")
                        break
                    end

                    local function ApplyGift(balance)
                        val.favor = (val.favor or 0) + giftConfig.favor
                        val.giftDate = today
                        val.giftCount = usedToday + 1
                        serverCloud.list:Modify(item.list_id, val)

                        -- 同步更新对方记录中对我的好感度
                        serverCloud.list:Get(targetUid, "friends", {
                            ok = function(otherList)
                                for _, otherItem in ipairs(otherList or {}) do
                                    local otherVal = otherItem.value or {}
                                    if otherVal.friendUid == userId then
                                        otherVal.favor = (otherVal.favor or 0) + giftConfig.favor
                                        serverCloud.list:Modify(otherItem.list_id, otherVal)
                                        break
                                    end
                                end
                            end,
                        })

                        local msg = "赠送" .. giftConfig.name .. "成功，好感+" .. giftConfig.favor
                        if giftCost > 0 then
                            msg = msg .. "，消耗灵石" .. giftCost
                        end
                        Reply(userId, "send_gift", true, msg, {
                            TargetUid = Variant(tostring(targetUid)),
                            NewFavor  = Variant(val.favor),
                            DailyUsed = Variant(val.giftCount),
                            DailyLimit = Variant(DataSocial.DAILY_GIFT_LIMIT),
                            Balance   = Variant(balance or -1),
                        })
                        Reply(targetUid, "gift_received", true,
                            "收到好友赠送的" .. giftConfig.name .. "，好感+" .. giftConfig.favor)
                    end

                    if giftCost > 0 then
                        serverCloud.money:Cost(userId, "lingStone", giftCost, {
                            ok = function()
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        ApplyGift((moneys and moneys["lingStone"]) or 0)
                                    end,
                                    error = function()
                                        ApplyGift(nil)
                                    end,
                                })
                            end,
                            error = function(code, reason)
                                Reply(userId, "send_gift", false, "灵石不足，无法赠送")
                            end,
                        })
                    else
                        ApplyGift(nil)
                    end
                    break
                end
            end
            if not found then
                Reply(userId, "send_gift", false, "对方不是你的好友")
            end
        end,
        error = function()
            Reply(userId, "send_gift", false, "操作失败")
        end,
    })
end

-- ============================================================================
-- 获取好友列表
-- ============================================================================

function M.OnGetFriends(userId)
    if not serverCloud then
        Reply(userId, "get_friends", false, "服务端存储不可用")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(list)
            local friends = {}
            for _, item in ipairs(list or {}) do
                local val = item.value or {}
                -- 过滤掉自己（双向存储可能产生自引用记录）
                if val.friendUid ~= userId then
                    val.listId = item.list_id
                    friends[#friends + 1] = val
                end
            end

            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.FRIEND_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant(cjson.encode(friends))
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
        error = function(code, reason)
            -- 首次查询可能无数据，不视为错误，返回空列表
            print("[ServerSocial] 好友列表查询异常(当作空): " .. tostring(reason))
            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.FRIEND_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant("[]")
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
    })
end

-- ============================================================================
-- 获取待处理好友申请
-- ============================================================================

function M.OnGetPending(userId)
    if not serverCloud then
        Reply(userId, "get_pending", false, "服务端存储不可用")
        return
    end

    serverCloud.message:Get(userId, "friend_req", false, {
        ok = function(messages)
            local pending = {}
            for _, msg in ipairs(messages or {}) do
                local val = msg.value or {}
                val.messageId = msg.message_id
                pending[#pending + 1] = val
            end

            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.PENDING_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant(cjson.encode(pending))
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
        error = function(code, reason)
            -- 首次查询可能无消息，不视为错误，返回空列表
            print("[ServerSocial] 申请列表查询异常(当作空): " .. tostring(reason))
            local data = VariantMap()
            data["Action"]  = Variant(DataSocial.RESP_ACTION.PENDING_LIST)
            data["Success"] = Variant(true)
            data["Msg"]     = Variant("")
            data["Data"]    = Variant("[]")
            deps_.SendToClient(userId, EVENTS.SOCIAL_DATA, data)
        end,
    })
end

-- ============================================================================
-- 道侣：申请结为道侣
-- 要求：双方为好友、好感 >= 1000、双方均无道侣
-- ============================================================================

function M.OnProposeDaoCouple(userId, eventData)
    if not serverCloud then
        Reply(userId, "propose_couple", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    if targetUid == 0 or targetUid == userId then
        Reply(userId, "propose_couple", false, "无效的目标玩家")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            local myRec, myListId = nil, nil
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.relation == "dao_couple" then
                    Reply(userId, "propose_couple", false, "你已有道侣")
                    return
                end
                if val.friendUid == targetUid then
                    myRec = val
                    myListId = item.list_id
                end
            end

            if not myRec then
                Reply(userId, "propose_couple", false, "对方不是你的好友")
                return
            end
            if myRec.relation ~= "friend" then
                Reply(userId, "propose_couple", false, "当前关系不允许结为道侣")
                return
            end
            local reqFavor = DataSocial.RELATION_CONFIG.dao_couple.requireFavor
            if (myRec.favor or 0) < reqFavor then
                Reply(userId, "propose_couple", false,
                    "好感度不足 " .. reqFavor .. "，当前 " .. (myRec.favor or 0))
                return
            end

            -- 检查对方是否已有道侣
            serverCloud.list:Get(targetUid, "friends", {
                ok = function(otherList)
                    local otherRec, otherListId = nil, nil
                    for _, item in ipairs(otherList or {}) do
                        local val = item.value or {}
                        if val.relation == "dao_couple" then
                            Reply(userId, "propose_couple", false, "对方已有道侣")
                            return
                        end
                        if val.friendUid == userId then
                            otherRec = val
                            otherListId = item.list_id
                        end
                    end

                    -- 双方升级为道侣
                    local coupleInit = {
                        relation = "dao_couple", intimacy = 0,
                        coupleLevel = 1, practiceDate = "", practiceCount = 0,
                    }
                    for k, v in pairs(coupleInit) do myRec[k] = v end
                    serverCloud.list:Modify(myListId, myRec)

                    if otherRec and otherListId then
                        for k, v in pairs(coupleInit) do otherRec[k] = v end
                        serverCloud.list:Modify(otherListId, otherRec)
                    end

                    print("[ServerSocial] 道侣结成 " .. userId .. " <-> " .. targetUid)
                    Reply(userId, "propose_couple", true,
                        "恭喜与 " .. (myRec.friendName or "好友") .. " 结为道侣！")
                    Reply(targetUid, "couple_formed", true,
                        (otherRec and otherRec.friendName or "好友") .. " 与你结为道侣！")
                end,
                error = function()
                    Reply(userId, "propose_couple", false, "查询对方信息失败")
                end,
            })
        end,
        error = function()
            Reply(userId, "propose_couple", false, "查询好友列表失败")
        end,
    })
end

-- ============================================================================
-- 道侣：道侣修炼
-- 消耗灵石 = tier * 550，每日上限 5 次，35% 几率 +5 亲密度
-- ============================================================================

function M.OnCouplePractice(userId, eventData)
    if not serverCloud then
        Reply(userId, "couple_practice", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    local myTier    = math.max(1, tonumber(eventData["MyTier"]:GetString()) or 1)

    if targetUid == 0 then
        Reply(userId, "couple_practice", false, "无效的目标")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            local myRec, myListId = nil, nil
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    myRec = val; myListId = item.list_id; break
                end
            end

            if not myRec or myRec.relation ~= "dao_couple" then
                Reply(userId, "couple_practice", false, "对方不是你的道侣")
                return
            end

            -- 每日次数限制
            local today = os.date("%Y-%m-%d")
            local usedToday = 0
            if myRec.practiceDate == today then
                usedToday = tonumber(myRec.practiceCount) or 0
            end
            if usedToday >= DataSocial.DAO_COUPLE_DAILY_PRACTICE then
                Reply(userId, "couple_practice", false,
                    "今日修炼次数已满(" .. DataSocial.DAO_COUPLE_DAILY_PRACTICE .. "次)")
                return
            end

            -- 扣灵石
            local cost = myTier * DataSocial.DAO_COUPLE_COST_PER_TIER
            serverCloud.money:Cost(userId, "lingStone", cost, {
                ok = function()
                    -- 35% 几率 +5 亲密度
                    local intimacyGain = 0
                    if math.random() < DataSocial.DAO_COUPLE_INTIMACY_CHANCE then
                        intimacyGain = DataSocial.DAO_COUPLE_INTIMACY_GAIN
                    end

                    myRec.intimacy = (myRec.intimacy or 0) + intimacyGain
                    myRec.practiceDate = today
                    myRec.practiceCount = usedToday + 1
                    serverCloud.list:Modify(myListId, myRec)

                    -- 同步对方亲密度
                    if intimacyGain > 0 then
                        serverCloud.list:Get(targetUid, "friends", {
                            ok = function(otherList)
                                for _, item in ipairs(otherList or {}) do
                                    local val = item.value or {}
                                    if val.friendUid == userId then
                                        val.intimacy = (val.intimacy or 0) + intimacyGain
                                        serverCloud.list:Modify(item.list_id, val)
                                        break
                                    end
                                end
                            end,
                        })
                    end

                    -- 获取余额后回复
                    serverCloud.money:Get(userId, {
                        ok = function(moneys)
                            local balance = (moneys and moneys["lingStone"]) or 0
                            local lvInfo = DataSocial.GetCoupleLevel(myRec.intimacy)
                            local msg = "道侣修炼完成，消耗灵石" .. cost
                            if intimacyGain > 0 then
                                msg = msg .. "，亲密度+" .. intimacyGain
                            end
                            Reply(userId, "couple_practice", true, msg, {
                                Intimacy    = Variant(myRec.intimacy),
                                IntGain     = Variant(intimacyGain),
                                CoupleLevel = Variant(lvInfo.level),
                                CultBonus   = Variant(tostring(lvInfo.cultivateBonus)),
                                DailyUsed   = Variant(myRec.practiceCount),
                                DailyLimit  = Variant(DataSocial.DAO_COUPLE_DAILY_PRACTICE),
                                Balance     = Variant(balance),
                            })
                        end,
                        error = function()
                            Reply(userId, "couple_practice", true, "修炼完成")
                        end,
                    })
                end,
                error = function()
                    Reply(userId, "couple_practice", false,
                        "灵石不足(需要" .. cost .. ")")
                end,
            })
        end,
        error = function()
            Reply(userId, "couple_practice", false, "查询失败")
        end,
    })
end

-- ============================================================================
-- 道侣：确认亲密等级提升
-- 当亲密度达到下一等级阈值时，由客户端发起确认升级
-- ============================================================================

function M.OnCoupleLevelUp(userId, eventData)
    if not serverCloud then
        Reply(userId, "couple_levelup", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    if targetUid == 0 then
        Reply(userId, "couple_levelup", false, "无效的目标")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            local myRec, myListId = nil, nil
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    myRec = val; myListId = item.list_id; break
                end
            end

            if not myRec or myRec.relation ~= "dao_couple" then
                Reply(userId, "couple_levelup", false, "对方不是你的道侣")
                return
            end

            local curStored = tonumber(myRec.coupleLevel) or 1
            local lvInfo = DataSocial.GetCoupleLevel(myRec.intimacy or 0)

            if lvInfo.level <= curStored then
                Reply(userId, "couple_levelup", false,
                    "亲密度不足，无法升级(当前Lv." .. curStored .. ")")
                return
            end

            -- 更新我方
            myRec.coupleLevel = lvInfo.level
            serverCloud.list:Modify(myListId, myRec)

            -- 更新对方
            serverCloud.list:Get(targetUid, "friends", {
                ok = function(otherList)
                    for _, item in ipairs(otherList or {}) do
                        local val = item.value or {}
                        if val.friendUid == userId then
                            val.coupleLevel = lvInfo.level
                            serverCloud.list:Modify(item.list_id, val)
                            break
                        end
                    end
                end,
            })

            local bonusPct = math.floor(lvInfo.cultivateBonus * 100)
            Reply(userId, "couple_levelup", true,
                "道侣等级提升至 Lv." .. lvInfo.level .. "，修炼加成 " .. bonusPct .. "%", {
                CoupleLevel = Variant(lvInfo.level),
                CultBonus   = Variant(tostring(lvInfo.cultivateBonus)),
                NextReq     = Variant(lvInfo.nextReq or -1),
            })
            Reply(targetUid, "couple_levelup_notify", true,
                "道侣等级提升至 Lv." .. lvInfo.level)
        end,
        error = function()
            Reply(userId, "couple_levelup", false, "查询失败")
        end,
    })
end

-- ============================================================================
-- 师徒：申请拜师
-- 要求：好感 >= 500、师傅 tier >= 4、师傅徒弟 < 3、双方无已有师徒关系
-- role: "master" 或 "disciple" 表示发起者的身份
-- ============================================================================

function M.OnProposeMaster(userId, eventData)
    if not serverCloud then
        Reply(userId, "propose_master", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    local myTier    = tonumber(eventData["MyTier"]:GetString()) or 1
    local targetTier = tonumber(eventData["TargetTier"]:GetString()) or 1
    local role       = eventData["Role"]:GetString()  -- "disciple"=我拜师, "master"=我收徒

    if targetUid == 0 or targetUid == userId then
        Reply(userId, "propose_master", false, "无效的目标玩家")
        return
    end

    -- 判定师傅是谁
    local masterUid, discipleUid, masterTier
    if role == "disciple" then
        masterUid = targetUid; discipleUid = userId; masterTier = targetTier
    else
        masterUid = userId; discipleUid = targetUid; masterTier = myTier
    end

    local cfg = DataSocial.MASTER_DISCIPLE
    if masterTier < cfg.masterMinRealm then
        Reply(userId, "propose_master", false, "师傅境界不足(需结丹以上)")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            -- 检查好友关系和好感
            local myRec, myListId = nil, nil
            local myMasterCount = 0  -- 我已有的师徒数
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    myRec = val; myListId = item.list_id
                end
                if val.relation == "master_disciple" then
                    myMasterCount = myMasterCount + 1
                end
            end

            if not myRec then
                Reply(userId, "propose_master", false, "对方不是你的好友")
                return
            end
            if myRec.relation ~= "friend" then
                Reply(userId, "propose_master", false, "当前关系不允许建立师徒")
                return
            end
            local reqFavor = DataSocial.RELATION_CONFIG.master_disciple.requireFavor
            if (myRec.favor or 0) < reqFavor then
                Reply(userId, "propose_master", false,
                    "好感度不足 " .. reqFavor .. "，当前 " .. (myRec.favor or 0))
                return
            end

            -- 检查师傅的徒弟数量
            serverCloud.list:Get(masterUid, "friends", {
                ok = function(masterList)
                    local discipleCount = 0
                    for _, item in ipairs(masterList or {}) do
                        local val = item.value or {}
                        if val.relation == "master_disciple" and val.masterRole == "master" then
                            discipleCount = discipleCount + 1
                        end
                    end
                    if discipleCount >= cfg.maxDisciples then
                        Reply(userId, "propose_master", false,
                            "师傅徒弟已满(" .. cfg.maxDisciples .. "人)")
                        return
                    end

                    -- 获取对方好友列表找到对应记录
                    serverCloud.list:Get(targetUid, "friends", {
                        ok = function(otherList)
                            local otherRec, otherListId = nil, nil
                            for _, item in ipairs(otherList or {}) do
                                local val = item.value or {}
                                if val.friendUid == userId then
                                    otherRec = val; otherListId = item.list_id
                                end
                            end

                            -- 我方记录
                            myRec.relation = "master_disciple"
                            myRec.masterRole = role  -- "disciple" 或 "master"
                            myRec.teachDate = ""
                            serverCloud.list:Modify(myListId, myRec)

                            -- 对方记录
                            if otherRec and otherListId then
                                otherRec.relation = "master_disciple"
                                otherRec.masterRole = (role == "master") and "disciple" or "master"
                                otherRec.teachDate = ""
                                serverCloud.list:Modify(otherListId, otherRec)
                            end

                            local myLabel = role == "disciple" and "拜师" or "收徒"
                            print("[ServerSocial] 师徒建立 " .. userId .. " <-> " .. targetUid)
                            Reply(userId, "propose_master", true,
                                myLabel .. "成功！")
                            Reply(targetUid, "master_formed", true,
                                (otherRec and otherRec.friendName or "好友") .. " 与你建立师徒关系！")
                        end,
                        error = function()
                            Reply(userId, "propose_master", false, "查询对方失败")
                        end,
                    })
                end,
                error = function()
                    Reply(userId, "propose_master", false, "查询失败")
                end,
            })
        end,
        error = function()
            Reply(userId, "propose_master", false, "查询好友列表失败")
        end,
    })
end

-- ============================================================================
-- 师徒：传功（师傅消耗修为，徒弟获得 × 1.5）
-- 冷却 3600 秒
-- ============================================================================

function M.OnMasterTeach(userId, eventData)
    if not serverCloud then
        Reply(userId, "master_teach", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    local myXiuwei  = tonumber(eventData["MyXiuwei"]:GetString()) or 0

    if targetUid == 0 then
        Reply(userId, "master_teach", false, "无效的目标")
        return
    end

    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            local myRec, myListId = nil, nil
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    myRec = val; myListId = item.list_id; break
                end
            end

            if not myRec or myRec.relation ~= "master_disciple" then
                Reply(userId, "master_teach", false, "对方不是你的师徒")
                return
            end
            if myRec.masterRole ~= "master" then
                Reply(userId, "master_teach", false, "只有师傅可以传功")
                return
            end

            -- 冷却检查
            local cfg = DataSocial.MASTER_DISCIPLE
            local now = os.time()
            local lastTeach = tonumber(myRec.teachDate) or 0
            if now - lastTeach < cfg.teachCooldown then
                local remain = cfg.teachCooldown - (now - lastTeach)
                local mins = math.ceil(remain / 60)
                Reply(userId, "master_teach", false,
                    "传功冷却中，还需 " .. mins .. " 分钟")
                return
            end

            -- 消耗修为量 = 当前修为的 10%（至少 100）
            local costXiuwei = math.max(100, math.floor(myXiuwei * 0.1))
            local gainXiuwei = math.floor(costXiuwei * cfg.teachEfficiency)

            -- 更新传功时间
            myRec.teachDate = tostring(now)
            serverCloud.list:Modify(myListId, myRec)

            Reply(userId, "master_teach", true,
                "传功成功！消耗修为 " .. costXiuwei .. "，徒弟获得 " .. gainXiuwei, {
                CostXiuwei = Variant(costXiuwei),
                GainXiuwei = Variant(gainXiuwei),
                TargetUid  = Variant(tostring(targetUid)),
            })
            Reply(targetUid, "master_teach_received", true,
                "师傅传功，获得修为 " .. gainXiuwei, {
                GainXiuwei = Variant(gainXiuwei),
            })
        end,
        error = function()
            Reply(userId, "master_teach", false, "查询失败")
        end,
    })
end

-- ============================================================================
-- 切磋：获取对手战斗数据 → 客户端模拟战斗 → 上报结果结算好感
-- ============================================================================

--- 切磋请求阶段：服务端读取对手属性并返回
function M.OnChallenge(userId, eventData)
    if not serverCloud then
        Reply(userId, "challenge", false, "服务端存储不可用")
        return
    end

    local targetUid = tonumber(eventData["TargetUid"]:GetString()) or 0
    if targetUid == 0 or targetUid == userId then
        Reply(userId, "challenge", false, "无效的目标")
        return
    end

    -- 检查好友关系
    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            local myRec = nil
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    myRec = val; break
                end
            end
            if not myRec then
                Reply(userId, "challenge", false, "对方不是你的好友")
                return
            end

            -- 冷却检查
            local now = os.time()
            local lastChallenge = tonumber(myRec.challengeDate) or 0
            local cd = DataSocial.CHALLENGE.cooldown
            if now - lastChallenge < cd then
                local remain = cd - (now - lastChallenge)
                Reply(userId, "challenge", false,
                    "切磋冷却中，还需 " .. remain .. " 秒")
                return
            end

            -- 读取对手 playerData（playerKey 从客户端传入，fallback 到服务端本地）
            local playerKey
            do
                local ok2, val = pcall(function() return eventData["PlayerKey"]:GetString() end)
                if ok2 and val and val ~= "" then
                    playerKey = val
                else
                    local GameServer = require("game_server")
                    playerKey = GameServer.GetServerKey("player")
                end
            end

            serverCloud:Get(targetUid, playerKey, {
                ok = function(scores)
                    local targetData = scores and scores[playerKey]
                    if type(targetData) ~= "table" then
                        Reply(userId, "challenge", false, "读取对手数据失败")
                        return
                    end

                    -- 提取对手战斗属性
                    local oAtk   = targetData.attack or 30
                    local oDef   = targetData.defense or 10
                    local oHP    = targetData.hpMax or 800
                    local oCrit  = targetData.crit or 5
                    local oHit   = targetData.hit or 90
                    local oDodge = targetData.dodge or 5
                    local oName  = targetData.name or "未知"
                    local oRealm = targetData.realmName or "凡人"

                    -- 生成切磋令牌
                    local token = tostring(userId) .. "_c_" .. tostring(now)
                        .. "_" .. tostring(math.random(100000, 999999))
                    -- 存到模块内存
                    M._pendingChallenge = M._pendingChallenge or {}
                    M._pendingChallenge[userId] = {
                        token     = token,
                        targetUid = targetUid,
                        expireAt  = now + 120,
                    }

                    Reply(userId, "challenge", true, "", {
                        TargetUid   = Variant(tostring(targetUid)),
                        TargetName  = Variant(oName),
                        TargetRealm = Variant(oRealm),
                        TargetAtk   = Variant(oAtk),
                        TargetDef   = Variant(oDef),
                        TargetHP    = Variant(oHP),
                        TargetCrit  = Variant(oCrit),
                        TargetHit   = Variant(oHit),
                        TargetDodge = Variant(oDodge),
                        Token       = Variant(token),
                    })
                end,
                error = function(code, reason)
                    Reply(userId, "challenge", false, "读取对手数据失败: " .. tostring(reason))
                end,
            })
        end,
        error = function()
            Reply(userId, "challenge", false, "查询好友列表失败")
        end,
    })
end

--- 切磋结算阶段：客户端上报胜负 → 更新好感 + 冷却
function M.OnChallengeSettle(userId, eventData)
    if not serverCloud then
        Reply(userId, "challenge_settle", false, "服务端存储不可用")
        return
    end

    local token = eventData["Token"]:GetString()
    local win   = eventData["Win"]:GetString() == "true"

    M._pendingChallenge = M._pendingChallenge or {}
    local pending = M._pendingChallenge[userId]
    M._pendingChallenge[userId] = nil

    if not pending then
        Reply(userId, "challenge_settle", false, "无待结算切磋")
        return
    end
    if token ~= pending.token then
        Reply(userId, "challenge_settle", false, "令牌无效")
        return
    end
    if os.time() > pending.expireAt then
        Reply(userId, "challenge_settle", false, "切磋已过期")
        return
    end

    local targetUid = pending.targetUid
    local favorGain = win and DataSocial.CHALLENGE.winFavor or DataSocial.CHALLENGE.loseFavor

    -- 更新双方好感和冷却
    serverCloud.list:Get(userId, "friends", {
        ok = function(myList)
            for _, item in ipairs(myList or {}) do
                local val = item.value or {}
                if val.friendUid == targetUid then
                    val.favor = (val.favor or 0) + favorGain
                    val.challengeDate = tostring(os.time())
                    serverCloud.list:Modify(item.list_id, val)
                    break
                end
            end
            -- 对方好感也增加
            serverCloud.list:Get(targetUid, "friends", {
                ok = function(otherList)
                    for _, item in ipairs(otherList or {}) do
                        local val = item.value or {}
                        if val.friendUid == userId then
                            val.favor = (val.favor or 0) + favorGain
                            val.challengeDate = tostring(os.time())
                            serverCloud.list:Modify(item.list_id, val)
                            break
                        end
                    end
                end,
            })

            local resultText = win and "切磋获胜" or "切磋落败"
            Reply(userId, "challenge_settle", true,
                resultText .. "，好感+" .. favorGain, {
                FavorGain = Variant(favorGain),
                Win       = Variant(win),
            })
            -- 通知对方
            local otherResult = win and "切磋落败" or "切磋获胜"
            Reply(targetUid, "challenge_notify", true,
                otherResult .. "，好感+" .. favorGain, {
                FavorGain = Variant(favorGain),
            })
        end,
        error = function()
            Reply(userId, "challenge_settle", false, "查询失败")
        end,
    })
end

return M
