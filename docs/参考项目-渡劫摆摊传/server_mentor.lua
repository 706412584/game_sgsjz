-- ============================================================================
-- server_mentor.lua — 师徒系统服务端逻辑
-- 职责：拜师邀请/接受/拒绝/解除/出师检测/修为分成
-- 改造：邀请持久化到目标 state.pendingMentorInvites，支持离线收取
-- ============================================================================

---@diagnostic disable: undefined-global

local Config = require("data_config")
local cjson = cjson

local M = {}

-- ========== 依赖注入(由 server_game.Init 传入) ==========
local SendToClient_ = nil
local PlayerMgr_ = nil
local EVENTS_ = nil
local sendEvt_ = nil  -- function(userId, evtType, data)

local MC = Config.MentorConfig

-- ========== 初始化 ==========
function M.Init(deps)
    SendToClient_ = deps.SendToClient
    PlayerMgr_ = deps.PlayerMgr
    EVENTS_ = deps.EVENTS
    sendEvt_ = deps.sendEvt
end

-- ========== 工具函数 ==========

local function getDiscipleCount(s)
    if not s.disciples then return 0 end
    return #s.disciples
end

local function findDisciple(masterState, discipleUserId)
    if not masterState.disciples then return nil, 0 end
    for i, d in ipairs(masterState.disciples) do
        if d.userId == discipleUserId then
            return d, i
        end
    end
    return nil, 0
end

--- 兜底新字段(老存档兼容)
local function ensureMentorFields(s)
    if s.disciples == nil then s.disciples = {} end
    if s.mentorXiuweiEarned == nil then s.mentorXiuweiEarned = 0 end
    if s.graduatedCount == nil then s.graduatedCount = 0 end
    if s.masterRealmAtBind == nil then s.masterRealmAtBind = 0 end
    if s.masterName == nil then s.masterName = "" end
    if s.pendingMentorInvites == nil then s.pendingMentorInvites = {} end
    if s.mentorGiftCount == nil then s.mentorGiftCount = 0 end
    if s.mentorGiftDate == nil then s.mentorGiftDate = "" end
    -- 出师相关：已出师标记（徒弟身上）、已出师徒弟列表（师父身上）
    if s.hasGraduated == nil then s.hasGraduated = false end
    if s.graduatedDisciples == nil then s.graduatedDisciples = {} end
    -- 出师历史（徒弟身上）：记录最后一位师父信息，弹窗展示用
    if s.lastMasterName == nil then s.lastMasterName = "" end
    if s.lastMasterId == nil then s.lastMasterId = nil end
end

--- 获取北京时间日期 key (UTC+8)
local function getBJDateKey()
    return os.date("!%Y-%m-%d", os.time() + 8 * 3600)
end

--- 检查 pendingMentorInvites 中是否已有来自 fromId 的邀请
local function hasPendingFrom(s, fromId)
    for _, inv in ipairs(s.pendingMentorInvites or {}) do
        if inv.fromId == fromId then return true end
    end
    return false
end

--- 清理过期邀请(从 state 中移除超时条目)
local function cleanExpired(s)
    if not s.pendingMentorInvites then return end
    local now = os.time()
    local i = 1
    while i <= #s.pendingMentorInvites do
        if now - (s.pendingMentorInvites[i].timestamp or 0) > MC.inviteExpireSec then
            table.remove(s.pendingMentorInvites, i)
        else
            i = i + 1
        end
    end
end

--- 从 pendingMentorInvites 中移除指定 fromId 的邀请
local function removeInviteFrom(s, fromId)
    if not s.pendingMentorInvites then return nil end
    for i, inv in ipairs(s.pendingMentorInvites) do
        if inv.fromId == fromId then
            return table.remove(s.pendingMentorInvites, i)
        end
    end
    return nil
end

-- ========== ACTION HANDLERS ==========

--- 师父主动收徒 (inviteType = "recruit")
--- 邀请写入目标 state，对方在线则实时推送
function M.HandleInvite(userId, s, rt, params)
    ensureMentorFields(s)
    local targetId = params and tonumber(params.targetUserId or params.targetId)
    if not targetId or targetId == 0 then
        return sendEvt_(userId, "action_fail", { msg = "无效的目标玩家" })
    end
    if targetId == userId then
        return sendEvt_(userId, "action_fail", { msg = "不能收自己为徒" })
    end

    -- 验证师父境界
    if s.realmLevel < MC.masterMinRealm then
        local realmName = Config.Realms[MC.masterMinRealm] and Config.Realms[MC.masterMinRealm].name or "元婴"
        return sendEvt_(userId, "action_fail", { msg = "境界不足,需达到" .. realmName .. "期" })
    end

    -- 验证徒弟数量
    if getDiscipleCount(s) >= MC.maxDisciples then
        return sendEvt_(userId, "action_fail", { msg = "徒弟已满(最多" .. MC.maxDisciples .. "人)" })
    end

    -- 自己不能有师父(师父不能同时是别人的徒弟)
    if s.masterId then
        return sendEvt_(userId, "action_fail", { msg = "你已拜师,不能同时收徒" })
    end

    -- 尝试读取目标 state(在线才有)
    local targetState = PlayerMgr_.GetState(targetId)

    -- 如果目标在线，做更多校验
    if targetState then
        ensureMentorFields(targetState)
        if targetState.masterId then
            return sendEvt_(userId, "action_fail", { msg = "对方已有师父" })
        end
        if targetState.realmLevel > s.realmLevel - MC.realmGap then
            return sendEvt_(userId, "action_fail", { msg = "对方境界过高,需低于你" .. MC.realmGap .. "个境界" })
        end
        -- 检查是否对方已是自己的徒弟
        local _, idx = findDisciple(s, targetId)
        if idx > 0 then
            return sendEvt_(userId, "action_fail", { msg = "对方已是你的徒弟" })
        end
        -- 已从本师父门下出师的徒弟不可重复收徒
        for _, gd in ipairs(s.graduatedDisciples or {}) do
            if tonumber(gd.userId) == targetId then
                return sendEvt_(userId, "action_fail", { msg = "该仙友曾是你的徒弟且已出师，缘分已尽" })
            end
        end
        -- 已出师的玩家不可再次以徒弟身份被收
        if targetState.hasGraduated then
            return sendEvt_(userId, "action_fail", { msg = "该仙友已出师，不可再次拜师" })
        end
        -- 清理过期邀请
        cleanExpired(targetState)
        -- 检查重复邀请
        if hasPendingFrom(targetState, userId) then
            return sendEvt_(userId, "action_fail", { msg = "已发送过邀请，等待对方回复" })
        end
        -- 写入目标 state
        table.insert(targetState.pendingMentorInvites, {
            fromId = userId,
            fromName = s.playerName or "无名仙人",
            fromRealm = s.realmLevel,
            inviteType = "recruit",  -- 师父收徒
            timestamp = os.time(),
        })
        PlayerMgr_.SetDirty(targetId)
        -- 实时通知目标
        sendEvt_(targetId, "mentor_invite_received", {
            fromId = userId,
            fromName = s.playerName or "无名仙人",
            fromRealm = s.realmLevel,
            fromRealmName = Config.Realms[s.realmLevel] and Config.Realms[s.realmLevel].name or "未知",
            inviteType = "recruit",
        })
    else
        -- 目标离线：用 serverCloud.message 写入离线邀请
        if serverCloud then
            local inviteData = {
                fromId = userId,
                fromName = s.playerName or "无名仙人",
                fromRealm = s.realmLevel,
                inviteType = "recruit",
                timestamp = os.time(),
            }
            serverCloud.message:Send(userId, "mentorInvite", targetId, inviteData, {
                ok = function(errorCode, errorDesc)
                    if errorCode == 0 or errorCode == nil then
                        print("[Mentor] 离线收徒邀请已存: target=" .. tostring(targetId))
                    else
                        print("[Mentor] 离线收徒邀请失败: " .. tostring(errorDesc))
                    end
                end,
            })
        else
            return sendEvt_(userId, "action_fail", { msg = "对方不在线且离线邮箱不可用" })
        end
    end

    sendEvt_(userId, "mentor_result", { msg = "收徒邀请已发送" })
    print("[Mentor] 收徒邀请: " .. tostring(userId) .. " → " .. tostring(targetId))
end

--- 徒弟主动拜师 (inviteType = "apply")
--- 写入目标(师父)的 state.pendingMentorInvites
function M.HandleApply(userId, s, rt, params)
    ensureMentorFields(s)
    local targetId = params and tonumber(params.targetUserId or params.targetId)
    if not targetId or targetId == 0 then
        return sendEvt_(userId, "action_fail", { msg = "无效的目标玩家" })
    end
    if targetId == userId then
        return sendEvt_(userId, "action_fail", { msg = "不能拜自己为师" })
    end

    -- 自己已有师父
    if s.masterId then
        return sendEvt_(userId, "action_fail", { msg = "你已有师父" })
    end

    -- 已出师的徒弟不可再次拜师
    if s.hasGraduated then
        return sendEvt_(userId, "action_fail", { msg = "你已出师，无法再次拜师" })
    end

    -- 自己有徒弟,不能同时拜师
    if getDiscipleCount(s) > 0 then
        return sendEvt_(userId, "action_fail", { msg = "你已有徒弟,不能同时拜师" })
    end

    local targetState = PlayerMgr_.GetState(targetId)

    if targetState then
        ensureMentorFields(targetState)
        -- 目标境界不够
        if targetState.realmLevel < MC.masterMinRealm then
            return sendEvt_(userId, "action_fail", { msg = "对方境界不足,无法拜师" })
        end
        -- 境界差不够
        if s.realmLevel > targetState.realmLevel - MC.realmGap then
            return sendEvt_(userId, "action_fail", { msg = "你的境界与对方差距不足" .. MC.realmGap .. "个境界" })
        end
        -- 对方徒弟已满
        if getDiscipleCount(targetState) >= MC.maxDisciples then
            return sendEvt_(userId, "action_fail", { msg = "对方徒弟已满" })
        end
        -- 对方自己有师父
        if targetState.masterId then
            return sendEvt_(userId, "action_fail", { msg = "对方已拜师,不能同时收徒" })
        end
        cleanExpired(targetState)
        if hasPendingFrom(targetState, userId) then
            return sendEvt_(userId, "action_fail", { msg = "已发送过申请，等待对方回复" })
        end
        -- 写入目标 state
        table.insert(targetState.pendingMentorInvites, {
            fromId = userId,
            fromName = s.playerName or "无名修士",
            fromRealm = s.realmLevel,
            inviteType = "apply",  -- 徒弟申请拜师
            timestamp = os.time(),
        })
        PlayerMgr_.SetDirty(targetId)
        -- 实时通知
        sendEvt_(targetId, "mentor_invite_received", {
            fromId = userId,
            fromName = s.playerName or "无名修士",
            fromRealm = s.realmLevel,
            fromRealmName = Config.Realms[s.realmLevel] and Config.Realms[s.realmLevel].name or "未知",
            inviteType = "apply",
        })
    else
        -- 目标离线
        if serverCloud then
            local inviteData = {
                fromId = userId,
                fromName = s.playerName or "无名修士",
                fromRealm = s.realmLevel,
                inviteType = "apply",
                timestamp = os.time(),
            }
            serverCloud.message:Send(userId, "mentorInvite", targetId, inviteData, {
                ok = function(errorCode, errorDesc)
                    if errorCode == 0 or errorCode == nil then
                        print("[Mentor] 离线拜师申请已存: target=" .. tostring(targetId))
                    else
                        print("[Mentor] 离线拜师申请失败: " .. tostring(errorDesc))
                    end
                end,
            })
        else
            return sendEvt_(userId, "action_fail", { msg = "对方不在线且离线邮箱不可用" })
        end
    end

    sendEvt_(userId, "mentor_result", { msg = "拜师申请已发送" })
    print("[Mentor] 拜师申请: " .. tostring(userId) .. " → " .. tostring(targetId))
end

--- 接受邀请 (收徒邀请 → 我成为徒弟; 拜师申请 → 我接受为徒弟)
function M.HandleAccept(userId, s, rt, params)
    ensureMentorFields(s)
    local fromId = params and tonumber(params.fromId)
    if not fromId or fromId == 0 then
        return sendEvt_(userId, "action_fail", { msg = "无效的邀请来源" })
    end

    cleanExpired(s)
    local invite = removeInviteFrom(s, fromId)
    if not invite then
        return sendEvt_(userId, "action_fail", { msg = "没有该玩家的待处理邀请(可能已过期)" })
    end
    PlayerMgr_.SetDirty(userId)

    local inviteType = invite.inviteType or "recruit"

    -- 确定谁是师父、谁是徒弟
    local masterId, discipleId, masterState, discipleState
    if inviteType == "recruit" then
        -- 对方(fromId)是师父,我(userId)是徒弟
        masterId = fromId
        discipleId = userId
        discipleState = s
        masterState = PlayerMgr_.GetState(masterId)
    else
        -- 对方(fromId)是申请拜师的徒弟,我(userId)是师父
        masterId = userId
        discipleId = fromId
        masterState = s
        discipleState = PlayerMgr_.GetState(discipleId)
    end

    -- 再次验证条件
    if not masterState then
        return sendEvt_(userId, "action_fail", { msg = "对方不在线,请稍后再试" })
    end
    ensureMentorFields(masterState)

    if inviteType == "recruit" then
        -- 我是徒弟
        if discipleState.masterId then
            return sendEvt_(userId, "action_fail", { msg = "你已有师父" })
        end
        if masterState.realmLevel < MC.masterMinRealm then
            return sendEvt_(userId, "action_fail", { msg = "对方境界已不满足条件" })
        end
        if getDiscipleCount(masterState) >= MC.maxDisciples then
            return sendEvt_(userId, "action_fail", { msg = "对方徒弟已满" })
        end
        if discipleState.realmLevel > masterState.realmLevel - MC.realmGap then
            return sendEvt_(userId, "action_fail", { msg = "境界差不满足条件" })
        end
    else
        -- 我是师父，对方申请拜师
        if not discipleState then
            return sendEvt_(userId, "action_fail", { msg = "对方不在线,请稍后再试" })
        end
        ensureMentorFields(discipleState)
        if masterState.masterId then
            return sendEvt_(userId, "action_fail", { msg = "你已拜师,不能同时收徒" })
        end
        if masterState.realmLevel < MC.masterMinRealm then
            return sendEvt_(userId, "action_fail", { msg = "你的境界不满足收徒条件" })
        end
        if getDiscipleCount(masterState) >= MC.maxDisciples then
            return sendEvt_(userId, "action_fail", { msg = "你的徒弟已满" })
        end
        if discipleState.masterId then
            return sendEvt_(userId, "action_fail", { msg = "对方已有师父" })
        end
        if discipleState.realmLevel > masterState.realmLevel - MC.realmGap then
            return sendEvt_(userId, "action_fail", { msg = "对方境界已不满足条件" })
        end
    end

    -- 建立师徒关系
    local now = os.time()

    -- 徒弟侧
    discipleState.masterId = masterId
    discipleState.masterName = masterState.playerName or "无名仙人"
    discipleState.masterRealmAtBind = masterState.realmLevel
    PlayerMgr_.SetDirty(discipleId)

    -- 师父侧
    table.insert(masterState.disciples, {
        userId = discipleId,
        name = discipleState.playerName or "无名修士",
        realmAtBind = discipleState.realmLevel,
        masterRealmAtBind = masterState.realmLevel,  -- 师父拜师时境界(用于出师目标)
        acceptTime = now,
    })
    PlayerMgr_.SetDirty(masterId)

    -- 通知双方
    local masterRealmName = Config.Realms[masterState.realmLevel] and Config.Realms[masterState.realmLevel].name or "未知"
    sendEvt_(discipleId, "mentor_bound", {
        role = "disciple",
        masterId = masterId,
        masterName = masterState.playerName or "无名仙人",
        masterRealm = masterState.realmLevel,
        masterRealmName = masterRealmName,
        masterRealmAtBind = masterState.realmLevel,
        msg = "拜师成功! 师父: " .. (masterState.playerName or "无名仙人"),
    })
    sendEvt_(masterId, "mentor_bound", {
        role = "master",
        discipleId = discipleId,
        discipleName = discipleState.playerName or "无名修士",
        discipleRealm = discipleState.realmLevel,
        msg = (discipleState.playerName or "无名修士") .. " 成为你的徒弟!",
    })

    print("[Mentor] 师徒关系建立: 师父=" .. tostring(masterId) .. " 徒弟=" .. tostring(discipleId))
end

--- 拒绝邀请
function M.HandleReject(userId, s, rt, params)
    ensureMentorFields(s)
    local fromId = params and tonumber(params.fromId)
    if not fromId or fromId == 0 then
        return sendEvt_(userId, "action_fail", { msg = "无效的邀请来源" })
    end

    cleanExpired(s)
    local invite = removeInviteFrom(s, fromId)
    if not invite then
        return sendEvt_(userId, "action_fail", { msg = "没有该玩家的待处理邀请" })
    end
    PlayerMgr_.SetDirty(userId)

    -- 通知对方(如果在线)
    sendEvt_(fromId, "mentor_rejected", {
        name = s.playerName or "无名修士",
        msg = (s.playerName or "无名修士") .. " 拒绝了你的" .. (invite.inviteType == "recruit" and "收徒" or "拜师") .. "邀请",
    })
    sendEvt_(userId, "mentor_result", { msg = "已拒绝邀请" })
end

--- 解除师徒关系(师父或徒弟均可发起)
function M.HandleDismiss(userId, s, rt, params)
    ensureMentorFields(s)
    local action = params and params.action or ""

    if action == "leave" then
        -- 徒弟主动离开
        if not s.masterId then
            return sendEvt_(userId, "action_fail", { msg = "你没有师父" })
        end
        local masterId = s.masterId
        local masterState = PlayerMgr_.GetState(masterId)
        if masterState then
            ensureMentorFields(masterState)
            for i, d in ipairs(masterState.disciples) do
                if d.userId == userId then
                    table.remove(masterState.disciples, i)
                    break
                end
            end
            PlayerMgr_.SetDirty(masterId)
            sendEvt_(masterId, "mentor_dismissed", {
                role = "master",
                targetName = s.playerName or "无名修士",
                msg = (s.playerName or "无名修士") .. " 离开了师门",
            })
        end
        s.masterId = nil
        s.masterName = ""
        s.masterRealmAtBind = 0
        PlayerMgr_.SetDirty(userId)
        sendEvt_(userId, "mentor_dismissed", {
            role = "disciple",
            msg = "你已离开师门",
        })
    else
        -- 师父踢出徒弟
        local targetId = params and tonumber(params.discipleUserId or params.targetId)
        if not targetId then
            return sendEvt_(userId, "action_fail", { msg = "无效的目标徒弟" })
        end
        local _, idx = findDisciple(s, targetId)
        if idx == 0 then
            return sendEvt_(userId, "action_fail", { msg = "对方不是你的徒弟" })
        end
        local discipleName = s.disciples[idx].name
        table.remove(s.disciples, idx)
        PlayerMgr_.SetDirty(userId)

        local discipleState = PlayerMgr_.GetState(targetId)
        if discipleState then
            ensureMentorFields(discipleState)
            discipleState.masterId = nil
            discipleState.masterName = ""
            discipleState.masterRealmAtBind = 0
            PlayerMgr_.SetDirty(targetId)
            sendEvt_(targetId, "mentor_dismissed", {
                role = "disciple",
                msg = "你已被逐出师门",
            })
        end
        sendEvt_(userId, "mentor_dismissed", {
            role = "master",
            targetName = discipleName,
            msg = discipleName .. " 已被逐出师门",
        })
    end

    print("[Mentor] 师徒关系解除: userId=" .. tostring(userId))
end

--- 查询师徒信息(含待处理邀请)
function M.HandleQuery(userId, s, rt, params)
    ensureMentorFields(s)
    cleanExpired(s)

    local info = {
        masterId = s.masterId,
        masterName = s.masterName or "",
        masterRealmAtBind = s.masterRealmAtBind or 0,
        disciples = {},
        mentorXiuweiEarned = s.mentorXiuweiEarned or 0,
        graduatedCount = s.graduatedCount or 0,
        maxDisciples = MC.maxDisciples,
        masterMinRealm = MC.masterMinRealm,
        realmGap = MC.realmGap,
        speedBonus = MC.discipleSpeedBonus,
        shareRatio = MC.masterShareRatio,
        -- 待处理邀请列表
        pendingInvites = s.pendingMentorInvites or {},
    }

    if s.disciples then
        for _, d in ipairs(s.disciples) do
            local dState = PlayerMgr_.GetState(d.userId)
            table.insert(info.disciples, {
                userId = d.userId,
                name = dState and dState.playerName or d.name,
                realmAtBind = d.realmAtBind,
                masterRealmAtBind = d.masterRealmAtBind or 0,
                currentRealm = dState and dState.realmLevel or 0,
                acceptTime = d.acceptTime,
                online = dState ~= nil,
            })
        end
    end

    if s.masterId then
        local mState = PlayerMgr_.GetState(s.masterId)
        if mState then
            info.masterCurrentRealm = mState.realmLevel
            info.masterOnline = true
        else
            info.masterCurrentRealm = 0
            info.masterOnline = false
        end
    end

    sendEvt_(userId, "mentor_info", info)
end

-- ========== 修为分成 ==========

function M.DistributeToMaster(discipleUserId, discipleState, xiuweiAmount)
    if not discipleState.masterId then return end
    if xiuweiAmount <= 0 then return end

    local share = math.floor(xiuweiAmount * MC.masterShareRatio)
    if share <= 0 then return end

    local masterId = discipleState.masterId
    local masterState = PlayerMgr_.GetState(masterId)

    if masterState then
        ensureMentorFields(masterState)
        masterState.xiuwei = masterState.xiuwei + share
        masterState.mentorXiuweiEarned = (masterState.mentorXiuweiEarned or 0) + share
        PlayerMgr_.SetDirty(masterId)
    else
        if serverCloud then
            serverCloud:BatchSet(masterId)
                :Incr("mentorPendingXiuwei", share)
                :Save("mentor_share", {
                    ok = function() end,
                    err = function(e) print("[Mentor] 离线分成保存失败: " .. tostring(e)) end,
                })
        end
    end
end

function M.ApplyDiscipleBonus(s, baseAmount)
    if s.masterId then
        return math.floor(baseAmount * (1 + MC.discipleSpeedBonus))
    end
    return baseAmount
end

-- ========== 出师处理 ==========

function M.HandleGraduation(discipleUserId, discipleState)
    ensureMentorFields(discipleState)
    local masterId = discipleState.masterId
    if not masterId then return end

    local rewardDisciple = MC.graduationRewardDisciple
    local rewardMaster = MC.graduationRewardMaster
    local discipleName = discipleState.playerName or "无名修士"

    -- 出师前先保存历史信息（用于弹窗展示）
    discipleState.lastMasterId   = masterId
    discipleState.lastMasterName = discipleState.masterName or ""
    discipleState.xiuwei = discipleState.xiuwei + rewardDisciple
    discipleState.masterId = nil
    discipleState.masterName = ""
    discipleState.masterRealmAtBind = 0
    discipleState.hasGraduated = true  -- 标记已出师，不可再次拜师
    PlayerMgr_.SetDirty(discipleUserId)

    sendEvt_(discipleUserId, "mentor_graduated", {
        role = "disciple",
        reward = rewardDisciple,
        msg = "恭喜出师! 获得修为奖励 " .. rewardDisciple,
    })

    local masterState = PlayerMgr_.GetState(masterId)
    if masterState then
        ensureMentorFields(masterState)
        for i, d in ipairs(masterState.disciples) do
            if d.userId == discipleUserId then
                table.remove(masterState.disciples, i)
                break
            end
        end
        masterState.xiuwei = masterState.xiuwei + rewardMaster
        masterState.mentorXiuweiEarned = (masterState.mentorXiuweiEarned or 0) + rewardMaster
        masterState.graduatedCount = (masterState.graduatedCount or 0) + 1
        -- 记录出师徒弟，防止重复收徒
        table.insert(masterState.graduatedDisciples, {
            userId = discipleUserId,
            name = discipleName,
            graduatedAt = os.time(),
        })
        PlayerMgr_.SetDirty(masterId)

        sendEvt_(masterId, "mentor_graduated", {
            role = "master",
            discipleName = discipleName,
            reward = rewardMaster,
            msg = discipleName .. " 出师! 获得修为奖励 " .. rewardMaster,
        })
    else
        if serverCloud then
            serverCloud:BatchSet(masterId)
                :Incr("mentorPendingXiuwei", rewardMaster)
                :Incr("mentorGraduatedCount", 1)
                :Save("mentor_graduation", {
                    ok = function() end,
                    err = function(e) print("[Mentor] 出师奖励保存失败: " .. tostring(e)) end,
                })
        end
    end

    print("[Mentor] 出师: 徒弟=" .. tostring(discipleUserId) .. " 师父=" .. tostring(masterId))
end

--- 徒弟手动申请出师（客户端触发）
function M.HandleGraduationRequest(userId, s, rt, params)
    ensureMentorFields(s)
    if not s.masterId then
        return sendEvt_(userId, "action_fail", { msg = "你没有师父" })
    end
    -- 检查出师条件：当前境界 >= 拜师时师父境界 - 1
    local masterRealmAtBind = s.masterRealmAtBind or 0
    local target = math.max(masterRealmAtBind - 1, 1)
    if (s.realmLevel or 1) < target then
        local realmName = Config.Realms[target] and Config.Realms[target].name or ("境界" .. target)
        return sendEvt_(userId, "action_fail", { msg = "境界未达出师要求，需达到" .. realmName })
    end
    M.HandleGraduation(userId, s)
end

-- ========== 上线结算 ==========

--- 玩家上线时: 1)结算离线分成 2)合并离线邀请到state
function M.SettleOfflineMentorRewards(userId, s)
    ensureMentorFields(s)
    if not serverCloud then return end

    -- 1) 离线修为分成
    serverCloud:Get(userId, "mentorPendingXiuwei", {
        ok = function(values)
            local pending = values and tonumber(values["mentorPendingXiuwei"]) or 0
            if pending > 0 then
                s.xiuwei = s.xiuwei + pending
                s.mentorXiuweiEarned = (s.mentorXiuweiEarned or 0) + pending
                PlayerMgr_.SetDirty(userId)
                serverCloud:BatchSet(userId)
                    :SetInt("mentorPendingXiuwei", 0)
                    :Save("mentor_settle_clear", {
                        ok = function() end,
                        err = function(e) print("[Mentor] 清零离线分成失败: " .. tostring(e)) end,
                    })
                sendEvt_(userId, "mentor_offline_settle", { xiuwei = pending })
            end
        end,
        err = function(e)
            print("[Mentor] 读取离线分成失败: " .. tostring(e))
        end,
    })

    -- 2) 离线出师计数
    serverCloud:Get(userId, "mentorGraduatedCount", {
        ok = function(values)
            local count = values and tonumber(values["mentorGraduatedCount"]) or 0
            if count > 0 then
                s.graduatedCount = (s.graduatedCount or 0) + count
                PlayerMgr_.SetDirty(userId)
                serverCloud:BatchSet(userId)
                    :SetInt("mentorGraduatedCount", 0)
                    :Save("mentor_grad_clear", {
                        ok = function() end,
                        err = function(e) print("[Mentor] 清零出师计数失败: " .. tostring(e)) end,
                    })
            end
        end,
        err = function(e)
            print("[Mentor] 读取出师计数失败: " .. tostring(e))
        end,
    })

    -- 3) 合并离线邀请队列到 state (使用 message API)
    serverCloud.message:Get(userId, "mentorInvite", false, {
        ok = function(messages)
            if not messages or #messages == 0 then return end
            local now = os.time()
            for _, msg in ipairs(messages) do
                local inv = msg.value
                if type(inv) == "table" and inv.fromId then
                    -- 未过期且不重复
                    if (now - (inv.timestamp or 0)) <= MC.inviteExpireSec
                       and not hasPendingFrom(s, inv.fromId) then
                        table.insert(s.pendingMentorInvites, inv)
                    end
                end
                -- 标记已读并删除
                if msg.message_id then
                    serverCloud.message:MarkRead(msg.message_id)
                    serverCloud.message:Delete(msg.message_id)
                end
            end
            PlayerMgr_.SetDirty(userId)
            -- 推送待处理列表
            if #s.pendingMentorInvites > 0 then
                sendEvt_(userId, "mentor_pending_list", {
                    invites = s.pendingMentorInvites,
                })
            end
        end,
        err = function(e)
            print("[Mentor] 读取离线邀请消息失败: " .. tostring(e))
        end,
    })

    -- 4) 如果state中已有未过期邀请(上次存盘留下的),也推送
    cleanExpired(s)
    if #s.pendingMentorInvites > 0 then
        PlayerMgr_.SetDirty(userId)
        sendEvt_(userId, "mentor_pending_list", {
            invites = s.pendingMentorInvites,
        })
    end
end

-- ========== 师父赠送法宝/珍藏给徒弟 ==========

local GIFT_DAILY_MAX = 3  -- 每日最多赠送3次

--- 师父赠送法宝或珍藏给徒弟（每次限1个，每日3次）
--- params: { discipleId = xxx, giftType = "artifact"|"collectible", itemId = "xxx" }
function M.HandleGift(userId, s, rt, params)
    ensureMentorFields(s)

    local disciples = s.disciples or {}
    if #disciples == 0 then
        return sendEvt_(userId, "action_fail", { msg = "你还没有徒弟" })
    end

    -- 每日次数检查(北京时间0点重置)，次数记在师父身上
    local today = getBJDateKey()
    if s.mentorGiftDate ~= today then
        s.mentorGiftDate = today
        s.mentorGiftCount = 0
    end
    if s.mentorGiftCount >= GIFT_DAILY_MAX then
        return sendEvt_(userId, "action_fail", { msg = "今日赠送次数已用完(每日" .. GIFT_DAILY_MAX .. "次)" })
    end

    local discipleId = tonumber(params and params.discipleId) or 0  -- 保持数字类型
    local giftType   = params and params.giftType or ""
    local itemId     = params and params.itemId or ""
    if discipleId == 0 or giftType == "" or itemId == "" then
        return sendEvt_(userId, "action_fail", { msg = "赠送参数无效" })
    end

    -- 验证对方是自己的徒弟
    local isDisciple = false
    for _, d in ipairs(disciples) do
        if tonumber(d.userId) == discipleId then
            isDisciple = true
            break
        end
    end
    if not isDisciple then
        return sendEvt_(userId, "action_fail", { msg = "对方不是你的徒弟" })
    end

    -- 获取徒弟状态(需在线)
    local discipleState = PlayerMgr_.GetState(discipleId)
    if not discipleState then
        return sendEvt_(userId, "action_fail", { msg = "徒弟不在线，无法赠送" })
    end
    ensureMentorFields(discipleState)

    local itemName = itemId

    if giftType == "artifact" then
        -- 法宝赠送：检查师父库存
        if not s.artifacts or not s.artifacts[itemId] or (s.artifacts[itemId].count or 0) < 1 then
            return sendEvt_(userId, "action_fail", { msg = "你没有该法宝" })
        end
        -- 已装备的不能赠送
        if s.equippedArtifacts then
            for _, eq in ipairs(s.equippedArtifacts) do
                if eq.id == itemId then
                    return sendEvt_(userId, "action_fail", { msg = "已装备的法宝不能赠送，请先卸下" })
                end
            end
        end
        -- 扣除师父库存(每次1个)
        s.artifacts[itemId].count = s.artifacts[itemId].count - 1
        if s.artifacts[itemId].count <= 0 then s.artifacts[itemId] = nil end
        -- 增加到徒弟库存
        if not discipleState.artifacts then discipleState.artifacts = {} end
        if not discipleState.artifacts[itemId] then
            discipleState.artifacts[itemId] = { count = 0, level = 1 }
        end
        discipleState.artifacts[itemId].count = discipleState.artifacts[itemId].count + 1
        local artCfg = Config.GetArtifactById and Config.GetArtifactById(itemId)
        if artCfg then itemName = artCfg.name end

    elseif giftType == "collectible" then
        -- 珍藏赠送：检查师父库存
        if not s.collectibles or (s.collectibles[itemId] or 0) < 1 then
            return sendEvt_(userId, "action_fail", { msg = "你没有该珍藏物品" })
        end
        -- 扣除师父库存(每次1个)
        s.collectibles[itemId] = s.collectibles[itemId] - 1
        if s.collectibles[itemId] <= 0 then s.collectibles[itemId] = nil end
        -- 增加到徒弟库存
        if not discipleState.collectibles then discipleState.collectibles = {} end
        discipleState.collectibles[itemId] = (discipleState.collectibles[itemId] or 0) + 1
        local colCfg = Config.GetCollectibleById and Config.GetCollectibleById(itemId)
        if colCfg then itemName = colCfg.name end
    else
        return sendEvt_(userId, "action_fail", { msg = "未知的赠送类型" })
    end

    -- 扣次数
    s.mentorGiftCount = s.mentorGiftCount + 1
    PlayerMgr_.SetDirty(userId)
    PlayerMgr_.SetDirty(discipleId)

    -- 通知双方
    local masterName  = s.playerName or "无名修士"
    local discipleName = discipleState.playerName or "无名修士"
    sendEvt_(userId, "mentor_gift_result", {
        ok  = true,
        msg = "成功向徒弟 " .. discipleName .. " 赠送了 " .. itemName,
        remaining = GIFT_DAILY_MAX - s.mentorGiftCount,
    })
    sendEvt_(discipleId, "mentor_gift_received", {
        fromName  = masterName,
        itemName  = itemName,
        giftType  = giftType,
        itemId    = itemId,
        msg       = "师父 " .. masterName .. " 赠送了 " .. itemName,
    })

    print("[Mentor] 赠送: " .. tostring(userId) .. " → " .. discipleId .. " " .. itemId)
end

return M
