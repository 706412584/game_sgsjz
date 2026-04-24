-- ============================================================================
-- 《问道长生》客户端社交逻辑
-- 职责：发送社交请求、缓存好友/申请数据、对外暴露状态查询接口
-- ============================================================================

local Shared     = require("network.shared")
local EVENTS     = Shared.EVENTS
local ClientNet  = require("network.client_net")
local DataSocial = require("data_social")
local Toast      = require("ui_toast")
local GamePlayer = require("game_player")
---@diagnostic disable-next-line: undefined-global
local cjson      = cjson

local M = {}

-- ============================================================================
-- 缓存数据
-- ============================================================================

local friends_    = {}    -- 好友列表 { friendUid, friendName, friendRealm, relation, favor, ... }
local pending_    = {}    -- 待处理申请 { fromUid, fromName, fromRealm, messageId, ... }
local onRefresh_  = nil   -- UI 刷新回调 function()
local onlineStatus_ = {} -- uid(string) -> boolean 在线状态缓存

-- ============================================================================
-- 注册 UI 刷新回调
-- ============================================================================

---@param fn fun()
function M.SetRefreshCallback(fn)
    onRefresh_ = fn
end

local function NotifyRefresh()
    if onRefresh_ then
        onRefresh_()
    end
end

-- ============================================================================
-- 数据访问
-- ============================================================================

---@return table[]
function M.GetFriends()
    return friends_
end

---@return table[]
function M.GetPending()
    return pending_
end

---@return number
function M.GetFriendCount()
    return #friends_
end

---@return number
function M.GetPendingCount()
    return #pending_
end

-- ============================================================================
-- 在线状态查询
-- ============================================================================

--- 查询一组 uid 的在线状态（发送到服务端）
---@param uidList number[]
function M.RequestOnlineStatus(uidList)
    if not uidList or #uidList == 0 then return end
    local data = VariantMap()
    data["UidListJson"] = Variant(cjson.encode(uidList))
    ClientNet.SendToServer(Shared.EVENTS.CHAT_QUERY_ONLINE, data)
end

--- 服务端在线状态回复处理（由 client_net.lua 中转调用）
---@param eventData any
function M.OnOnlineStatus(eventData)
    local json = eventData["StatusJson"] and eventData["StatusJson"]:GetString() or "{}"
    local ok2, statusMap = pcall(cjson.decode, json)
    if ok2 and type(statusMap) == "table" then
        for uid, online in pairs(statusMap) do
            onlineStatus_[tostring(uid)] = online
        end
    end
    NotifyRefresh()
end

--- 查询某个 uid 是否在线（从本地缓存读取）
---@param uid number|string
---@return boolean
function M.IsOnline(uid)
    return onlineStatus_[tostring(uid)] == true
end

-- ============================================================================
-- 发送请求到服务端（统一通过 ReqSocialOp 事件）
-- ============================================================================

---@param action string
---@param extra table|nil
---@return boolean
local function SendSocialOp(action, extra)
    local GameServer = require("game_server")
    local data = VariantMap()
    data["Action"] = Variant(action)
    data["PlayerKey"] = Variant(GameServer.GetServerKey("player"))
    if extra then
        for k, v in pairs(extra) do
            data[k] = Variant(tostring(v))
        end
    end
    return ClientNet.SendToServer(EVENTS.REQ_SOCIAL_OP, data)
end

-- ============================================================================
-- 对外操作接口
-- ============================================================================

--- 请求好友列表
function M.RequestFriends()
    SendSocialOp(DataSocial.ACTION.GET_FRIENDS)
end

--- 请求待处理申请列表
function M.RequestPending()
    SendSocialOp(DataSocial.ACTION.GET_PENDING)
end

--- 发送好友申请
---@param targetUid number|string
function M.AddFriend(targetUid)
    local p = GamePlayer.Get()
    if not p then
        Toast.Show("数据未加载", { variant = "error" })
        return
    end
    SendSocialOp(DataSocial.ACTION.ADD_FRIEND, {
        TargetUid  = targetUid,
        SenderName = p.name or "无名",
        SenderRealm = p.realmName or "凡人",
    })
end

--- 同意好友申请
---@param pendingItem table { messageId, fromUid, fromName, fromRealm }
function M.AcceptFriend(pendingItem)
    local p = GamePlayer.Get()
    if not p then return end
    SendSocialOp(DataSocial.ACTION.ACCEPT_FRIEND, {
        MessageId = pendingItem.messageId or 0,
        FromUid   = pendingItem.fromUid or 0,
        FromName  = pendingItem.fromName or "",
        FromRealm = pendingItem.fromRealm or "",
        MyName    = p.name or "无名",
        MyRealm   = p.realmName or "凡人",
    })
end

--- 拒绝好友申请
---@param pendingItem table { messageId }
function M.RejectFriend(pendingItem)
    SendSocialOp(DataSocial.ACTION.REJECT_FRIEND, {
        MessageId = pendingItem.messageId or 0,
    })
end

--- 一键拒绝全部
function M.RejectAll()
    SendSocialOp(DataSocial.ACTION.REJECT_ALL)
end

--- 解除好友关系
---@param targetUid number|string
function M.RemoveFriend(targetUid)
    SendSocialOp(DataSocial.ACTION.REMOVE_FRIEND, {
        TargetUid = targetUid,
    })
end

--- 赠送礼物
---@param targetUid number|string
---@param giftId string
function M.SendGift(targetUid, giftId)
    SendSocialOp(DataSocial.ACTION.SEND_GIFT, {
        TargetUid = targetUid,
        GiftId    = giftId,
    })
end

-- ============================================================================
-- 道侣操作接口
-- ============================================================================

--- 申请结为道侣
---@param targetUid number|string
function M.ProposeDaoCouple(targetUid)
    SendSocialOp(DataSocial.ACTION.PROPOSE_COUPLE, {
        TargetUid = targetUid,
    })
end

--- 道侣修炼
---@param targetUid number|string
function M.CouplePractice(targetUid)
    local p = GamePlayer.Get()
    if not p then
        Toast.Show("数据未加载", { variant = "error" })
        return
    end
    SendSocialOp(DataSocial.ACTION.COUPLE_PRACTICE, {
        TargetUid = targetUid,
        MyTier    = p.realmTier or 1,
    })
end

--- 道侣亲密等级提升
---@param targetUid number|string
function M.CoupleLevelUp(targetUid)
    SendSocialOp(DataSocial.ACTION.COUPLE_LEVELUP, {
        TargetUid = targetUid,
    })
end

--- 获取道侣信息（从好友列表中查找 relation == "dao_couple"）
---@return table|nil  道侣好友记录
function M.GetDaoCouple()
    for _, f in ipairs(friends_) do
        if f.relation == "dao_couple" then
            return f
        end
    end
    return nil
end

-- ============================================================================
-- 师徒操作接口
-- ============================================================================

--- 申请拜师（我为徒弟）
---@param targetUid number|string
---@param targetTier number  对方境界 tier
function M.ProposeMasterAsDisciple(targetUid, targetTier)
    local p = GamePlayer.Get()
    if not p then Toast.Show("数据未加载", { variant = "error" }); return end
    SendSocialOp(DataSocial.ACTION.PROPOSE_MASTER, {
        TargetUid  = targetUid,
        MyTier     = p.realmTier or 1,
        TargetTier = targetTier or 1,
        Role       = "disciple",
    })
end

--- 申请收徒（我为师傅）
---@param targetUid number|string
---@param targetTier number
function M.ProposeMasterAsMaster(targetUid, targetTier)
    local p = GamePlayer.Get()
    if not p then Toast.Show("数据未加载", { variant = "error" }); return end
    SendSocialOp(DataSocial.ACTION.PROPOSE_MASTER, {
        TargetUid  = targetUid,
        MyTier     = p.realmTier or 1,
        TargetTier = targetTier or 1,
        Role       = "master",
    })
end

--- 传功（师傅向徒弟传功）
---@param targetUid number|string
function M.MasterTeach(targetUid)
    local p = GamePlayer.Get()
    if not p then Toast.Show("数据未加载", { variant = "error" }); return end
    SendSocialOp(DataSocial.ACTION.MASTER_TEACH, {
        TargetUid = targetUid,
        MyXiuwei  = p.xiuwei or 0,
    })
end

--- 获取师傅（如有）
---@return table|nil
function M.GetMaster()
    for _, f in ipairs(friends_) do
        if f.relation == "master_disciple" and f.masterRole == "disciple" then
            return f
        end
    end
    return nil
end

--- 获取徒弟列表
---@return table[]
function M.GetDisciples()
    local result = {}
    for _, f in ipairs(friends_) do
        if f.relation == "master_disciple" and f.masterRole == "master" then
            result[#result + 1] = f
        end
    end
    return result
end

-- ============================================================================
-- 切磋操作接口
-- ============================================================================

--- 请求切磋（服务端返回对手属性）
---@param targetUid number|string
function M.RequestChallenge(targetUid)
    SendSocialOp(DataSocial.ACTION.CHALLENGE, {
        TargetUid = targetUid,
    })
end

--- 切磋结算
---@param token string
---@param win boolean
function M.SettleChallenge(token, win)
    SendSocialOp(DataSocial.ACTION.CHALLENGE_SETTLE, {
        Token = token,
        Win   = tostring(win),
    })
end

-- 切磋数据缓存（由 OnSocialData 写入）
local challengeData_ = nil

--- 获取当前切磋对手数据
---@return table|nil { targetName, targetRealm, atk, def, hp, crit, hit, dodge, token }
function M.GetChallengeData()
    return challengeData_
end

--- 清除切磋缓存
function M.ClearChallengeData()
    challengeData_ = nil
end

-- ============================================================================
-- 服务端回复处理（由 client_net.lua 中转调用）
-- ============================================================================

---@param eventData any
function M.OnSocialData(eventData)
    local action  = eventData:GetString("Action")
    local success = eventData:GetBool("Success")
    local msg     = eventData:GetString("Msg")  -- 可能为空字符串（列表回复没有 Msg 字段）

    -- 好友列表回复
    if action == DataSocial.RESP_ACTION.FRIEND_LIST then
        if success then
            local jsonStr = eventData["Data"]:GetString()
            friends_ = cjson.decode(jsonStr) or {}
            print("[GameSocial] 收到好友列表: " .. #friends_ .. " 人")
        end
        NotifyRefresh()
        return
    end

    -- 待处理申请列表回复
    if action == DataSocial.RESP_ACTION.PENDING_LIST then
        if success then
            local jsonStr = eventData["Data"]:GetString()
            pending_ = cjson.decode(jsonStr) or {}
            print("[GameSocial] 收到待处理申请: " .. #pending_ .. " 条")
        end
        NotifyRefresh()
        return
    end

    -- 道侣修炼回复 — 同步余额
    if action == "couple_practice" and success then
        local balance = eventData:GetInt("Balance")
        if balance >= 0 then
            GamePlayer.SyncField("lingStone", balance)
        end
    end

    -- 送礼回复 — 同步灵石余额
    if action == "send_gift" and success then
        local balance = eventData:GetInt("Balance")
        if balance >= 0 then
            GamePlayer.SyncField("lingStone", balance)
        end
        -- 刷新好友列表以更新好感显示
        M.RequestFriends()
    end

    -- 切磋请求回复 → 缓存对手数据
    if action == "challenge" and success then
        challengeData_ = {
            targetUid   = eventData:GetString("TargetUid"),
            targetName  = eventData:GetString("TargetName"),
            targetRealm = eventData:GetString("TargetRealm"),
            atk   = eventData:GetInt("TargetAtk"),
            def   = eventData:GetInt("TargetDef"),
            hp    = eventData:GetInt("TargetHP"),
            crit  = eventData:GetInt("TargetCrit"),
            hit   = eventData:GetInt("TargetHit"),
            dodge = eventData:GetInt("TargetDodge"),
            token = eventData:GetString("Token"),
        }
        NotifyRefresh()
        return
    end

    -- 切磋结算成功 → 刷新好友
    if action == "challenge_settle" and success then
        M.RequestFriends()
    end
    -- 被切磋通知 → 刷新好友
    if action == "challenge_notify" and success then
        M.RequestFriends()
    end

    -- 操作结果（通用 Toast）
    if msg and msg ~= "" then
        Toast.Show(msg, { variant = success and "success" or "error" })
    end

    -- 操作成功后刷新数据
    if success then
        if action == "accept_friend" or action == "remove_friend"
            or action == "friend_accepted" or action == "friend_removed" then
            M.RequestFriends()
        end
        if action == "accept_friend" or action == "reject_friend"
            or action == "reject_all" then
            M.RequestPending()
        end
        -- 收到礼物或好友接受通知 → 刷新列表
        if action == "gift_received" or action == "pending_notify" then
            M.RequestFriends()
            M.RequestPending()
        end
        -- 道侣相关操作成功 → 刷新好友列表
        if action == "propose_couple" or action == "couple_formed"
            or action == "couple_practice" or action == "couple_levelup"
            or action == "couple_levelup_notify" then
            M.RequestFriends()
        end
        -- 师徒相关操作成功 → 刷新好友列表
        if action == "propose_master" or action == "master_formed"
            or action == "master_teach" or action == "master_teach_received" then
            M.RequestFriends()
        end
    end

    -- 传功回复 — 同步修为变化
    if action == "master_teach" and success then
        local costXiuwei = tonumber(eventData:GetString("CostXiuwei")) or 0
        if costXiuwei > 0 then
            local p = GamePlayer.Get()
            if p then
                GamePlayer.SyncField("xiuwei", math.max(0, (p.xiuwei or 0) - costXiuwei))
            end
        end
    end
    if action == "master_teach_received" and success then
        local gainXiuwei = tonumber(eventData:GetString("GainXiuwei")) or 0
        if gainXiuwei > 0 then
            local p = GamePlayer.Get()
            if p then
                GamePlayer.SyncField("xiuwei", (p.xiuwei or 0) + gainXiuwei)
            end
        end
    end
end

return M
