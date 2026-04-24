-- ============================================================================
-- 《问道长生》聊天页主控
-- 职责：状态管理、路由注册、事件回调分发、对外接口
-- 子模块：ui_chat_common / ui_chat_world / ui_chat_private / ui_chat_input
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson  -- 引擎内置全局变量，无需 require

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameServer = require("game_server")
local GameSocial = require("game_social")
local Toast = require("ui_toast")

-- 子模块
local ChatCommon  = require("ui_chat_common")
local ChatWorld   = require("ui_chat_world")
local ChatPrivate = require("ui_chat_private")
local ChatInput   = require("ui_chat_input")

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local activeChannel_ = "世界"   -- "世界" | "私聊"
local worldMessages_ = {}       -- { {sender, senderName, text, timestamp}, ... }
local privateChats_  = {}       -- targetId -> { {sender, senderName, text, timestamp, isMine}, ... }
local privateTarget_ = nil      -- 当前私聊对象 { uid, name }
local inputText_     = ""       -- 输入框文本
local joined_        = false    -- 是否已发送 ChatJoin
local MAX_WORLD_MSGS = 100
local MAX_PRIVATE_MSGS = 50

-- ============================================================================
-- ChatJoin 管理
-- ============================================================================

function M.EnsureJoined()
    if joined_ then return end
    local p = GamePlayer.Get()
    if not p then return end

    local ClientNet = require("network.client_net")
    if not ClientNet.IsConnected() then return end

    local server = GameServer.GetCurrentServer()
    local serverId = server and server.id or 0
    if serverId == 0 then return end

    local Shared = require("network.shared")
    local data = VariantMap()
    data["ServerId"]    = Variant(tostring(serverId))
    data["Name"]        = Variant(p.name or "无名修士")
    data["Gender"]      = Variant(p.gender or "男")
    data["Realm"]       = Variant(p.realmName or "凡人")
    data["AvatarIndex"] = Variant(tostring(p.avatarIndex or 1))
    ClientNet.SendToServer(Shared.EVENTS.CHAT_JOIN, data)

    joined_ = true
    print("[Chat] ChatJoin 已发送 serverId=" .. tostring(serverId))
end

function M.ResetJoined()
    joined_ = false
end

-- ============================================================================
-- 发送消息
-- ============================================================================

local function sendWorldMessage(text)
    if text == "" then return end
    local ClientNet = require("network.client_net")
    local Shared = require("network.shared")
    local data = VariantMap()
    data["Text"] = Variant(text)
    ClientNet.SendToServer(Shared.EVENTS.CHAT_SEND, data)
end

local function sendPrivateMessage(targetId, text)
    if text == "" or not targetId then return end
    local ClientNet = require("network.client_net")
    local Shared = require("network.shared")
    local data = VariantMap()
    data["TargetId"] = Variant(tostring(targetId))
    data["Text"]     = Variant(text)
    ClientNet.SendToServer(Shared.EVENTS.CHAT_PRIVATE, data)
end

-- ============================================================================
-- 服务端回调
-- ============================================================================

function M.OnChatMsg(eventData)
    local senderJson = eventData["SenderJson"] and eventData["SenderJson"]:GetString() or "{}"
    local text       = eventData["Text"]       and eventData["Text"]:GetString()       or ""
    local timestamp  = eventData["Timestamp"]  and eventData["Timestamp"]:GetInt()      or 0

    local ok, sender = pcall(cjson.decode, senderJson)
    if not ok then sender = { name = "???" } end

    -- 屏蔽过滤：不显示已屏蔽玩家的消息
    local okBlock, GameBlock = pcall(require, "game_block")
    if okBlock and sender.userId and GameBlock.IsBlocked(sender.userId) then
        return
    end

    local msgId = eventData["MsgId"] and eventData["MsgId"]:GetString() or ""

    worldMessages_[#worldMessages_ + 1] = {
        sender     = sender,
        senderName = sender.name or "???",
        text       = text,
        timestamp  = timestamp,
        msgId      = msgId,
    }
    while #worldMessages_ > MAX_WORLD_MSGS do
        table.remove(worldMessages_, 1)
    end

    if Router.GetCurrentState and Router.GetCurrentState() == Router.STATE_CHAT then
        Router.RebuildUI()
    end
end

function M.OnChatPrivateMsg(eventData)
    local senderJson = eventData["SenderJson"] and eventData["SenderJson"]:GetString() or "{}"
    local targetId   = tonumber(eventData["TargetId"]   and eventData["TargetId"]:GetString()   or "0") or 0
    local targetName = eventData["TargetName"] and eventData["TargetName"]:GetString() or "未知"
    local text       = eventData["Text"]       and eventData["Text"]:GetString()       or ""
    local timestamp  = eventData["Timestamp"]  and eventData["Timestamp"]:GetInt()      or 0

    local ok, sender = pcall(cjson.decode, senderJson)
    if not ok then sender = { userId = 0, name = "???" } end

    local ClientNet = require("network.client_net")
    local myId = ClientNet.GetUserId()
    local isMine = (sender.userId == myId)
    local otherUid  = isMine and targetId or (sender.userId or 0)
    local otherName = isMine and targetName or (sender.name or "???")

    if not privateChats_[otherUid] then
        privateChats_[otherUid] = {}
    end
    local chat = privateChats_[otherUid]
    chat[#chat + 1] = {
        sender     = sender,
        senderName = sender.name or "???",
        text       = text,
        timestamp  = timestamp,
        isMine     = isMine,
        otherName  = otherName,
    }
    while #chat > MAX_PRIVATE_MSGS do
        table.remove(chat, 1)
    end

    if Router.GetCurrentState and Router.GetCurrentState() == Router.STATE_CHAT then
        Router.RebuildUI()
    end
end

function M.OnChatSystem(eventData)
    local text = eventData["Text"] and eventData["Text"]:GetString() or ""
    if text ~= "" then
        Toast.Show(text)
    end
end

--- 撤回通知：从消息列表中移除对应消息，显示提示
function M.OnChatRecallNotify(eventData)
    local msgId = eventData["MsgId"] and eventData["MsgId"]:GetString() or ""
    if msgId == "" then return end

    -- 在世界消息中查找并移除
    for i = #worldMessages_, 1, -1 do
        if worldMessages_[i].msgId == msgId then
            local name = worldMessages_[i].senderName or "???"
            table.remove(worldMessages_, i)
            Toast.Show(name .. " 撤回了一条消息")
            break
        end
    end

    if Router.GetCurrentState and Router.GetCurrentState() == Router.STATE_CHAT then
        Router.RebuildUI()
    end
end

--- 全服系统公告（富文本）
---@param announceType string  公告类型（如 "tribulation_success"）
---@param text string          富文本内容（含 <font> 等标签）
function M.OnAnnounce(announceType, text)
    if not text or text == "" then return end
    -- Toast 提示（保持简短）
    Toast.Show("天道示警：收到全服公告")
    -- 注入到世界消息列表
    worldMessages_[#worldMessages_ + 1] = {
        isAnnounce  = true,
        richText    = text,
        timestamp   = os.time(),
        announceType = announceType,
    }
    while #worldMessages_ > MAX_WORLD_MSGS do
        table.remove(worldMessages_, 1)
    end
    if Router.GetCurrentState and Router.GetCurrentState() == Router.STATE_CHAT then
        Router.RebuildUI()
    end
end

--- 发送撤回请求
---@param msgId string 消息 ID
function M.RecallMessage(msgId)
    if not msgId or msgId == "" then return end
    local ClientNet = require("network.client_net")
    local Shared = require("network.shared")
    local data = VariantMap()
    data["MsgId"] = Variant(msgId)
    ClientNet.SendToServer(Shared.EVENTS.CHAT_RECALL, data)
end

function M.OnChatHistory(eventData)
    local historyJson = eventData["HistoryJson"] and eventData["HistoryJson"]:GetString() or "[]"
    local ok, items = pcall(cjson.decode, historyJson)
    if not ok or type(items) ~= "table" then return end

    local okBlock, GameBlock = pcall(require, "game_block")
    for _, item in ipairs(items) do
        local okS, sender = pcall(cjson.decode, item.senderJson or "{}")
        if not okS then sender = { name = "???" } end
        -- 屏蔽过滤
        local blocked = okBlock and sender.userId and GameBlock.IsBlocked(sender.userId)
        if not blocked then
            worldMessages_[#worldMessages_ + 1] = {
                sender     = sender,
                senderName = sender.name or "???",
                text       = item.text or "",
                timestamp  = item.timestamp or 0,
                msgId      = item.msgId or "",
            }
        end
    end
    while #worldMessages_ > MAX_WORLD_MSGS do
        table.remove(worldMessages_, 1)
    end

    if Router.GetCurrentState and Router.GetCurrentState() == Router.STATE_CHAT then
        Router.RebuildUI()
    end
    print("[Chat] 收到历史消息 " .. #items .. " 条")
end

-- ============================================================================
-- 对外数据接口
-- ============================================================================

---@param count number
---@return table[]
function M.GetRecentMessages(count)
    count = count or 3
    local result = {}
    local start = math.max(1, #worldMessages_ - count + 1)
    for i = start, #worldMessages_ do
        result[#result + 1] = worldMessages_[i]
    end
    return result
end

-- ============================================================================
-- 私聊联系人数据
-- ============================================================================

local function getPrivateContacts()
    local contacts = {}
    local seen = {}

    for uid, msgs in pairs(privateChats_) do
        if #msgs > 0 then
            local last = msgs[#msgs]
            contacts[#contacts + 1] = {
                uid      = uid,
                name     = last.otherName or last.senderName or "???",
                lastMsg  = last.text or "",
                lastTime = last.timestamp or 0,
            }
            seen[uid] = true
        end
    end

    local friends = GameSocial.GetFriends()
    for _, f in ipairs(friends) do
        if not seen[f.friendUid] then
            contacts[#contacts + 1] = {
                uid      = f.friendUid,
                name     = f.friendName or "???",
                lastMsg  = "",
                lastTime = 0,
            }
        end
    end

    table.sort(contacts, function(a, b) return a.lastTime > b.lastTime end)
    return contacts
end

-- ============================================================================
-- 头像点击回调（P1.1 接入 PlayerPopup）
-- ============================================================================

local function onAvatarClick(sender)
    -- P1.1 将在此接入 ui_player_popup.lua
    local okPop, PlayerPopup = pcall(require, "ui_player_popup")
    if okPop and PlayerPopup.Show then
        PlayerPopup.Show(sender)
    end
end

-- ============================================================================
-- UI 构建
-- ============================================================================

function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 从 payload 设置私聊目标（由 PlayerPopup 跳转传入）
    if payload and payload.privateTarget then
        activeChannel_ = "私聊"
        privateTarget_ = payload.privateTarget
    end

    M.EnsureJoined()

    -- 频道按钮
    local channels = { "世界", "私聊" }
    local channelBtns = {}
    for i, ch in ipairs(channels) do
        local isActive = (ch == activeChannel_)
        channelBtns[i] = UI.Panel {
            flexGrow = 1,
            height = 36,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or Theme.colors.transparent,
            justifyContent = "center",
            alignItems = "center",
            cursor = "pointer",
            onClick = function(self)
                activeChannel_ = ch
                privateTarget_ = nil
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = ch,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.tabActiveText or Theme.colors.textLight,
                },
            },
        }
    end

    -- 中间内容区
    local ClientNet = require("network.client_net")
    local myUserId = ClientNet.GetUserId()

    local contentArea
    if activeChannel_ == "世界" then
        contentArea = ChatWorld.BuildMessageList(worldMessages_, onAvatarClick, myUserId)
    else
        -- 进入私聊频道时查询好友在线状态
        if not privateTarget_ then
            local contacts = getPrivateContacts()
            -- 收集联系人 uid 列表，查询在线状态
            local uidList = {}
            for _, c in ipairs(contacts) do
                uidList[#uidList + 1] = c.uid
            end
            if #uidList > 0 then
                GameSocial.RequestOnlineStatus(uidList)
            end
            contentArea = UI.ScrollView {
                width = "100%",
                flexGrow = 1,
                flexBasis = 0,
                scrollY = true,
                showScrollbar = true,
                scrollMultiplier = Theme.scrollSensitivity,
                backgroundColor = Theme.colors.bgDark,
                children = {
                    ChatPrivate.BuildContactList(contacts, function(c)
                        privateTarget_ = { uid = c.uid, name = c.name }
                        Router.RebuildUI()
                    end),
                },
            }
        else
            local chat = privateChats_[privateTarget_.uid] or {}
            contentArea = ChatPrivate.BuildChatArea(
                privateTarget_.name,
                chat,
                function()
                    privateTarget_ = nil
                    Router.RebuildUI()
                end,
                onAvatarClick
            )
        end
    end

    -- 输入区
    local showInput = (activeChannel_ == "世界") or (activeChannel_ == "私聊" and privateTarget_ ~= nil)
    local inputArea = showInput and ChatInput.BuildInputArea({
        placeholder = activeChannel_ == "私聊"
            and ("发消息给 " .. (privateTarget_ and privateTarget_.name or ""))
            or "输入消息...",
        inputText = inputText_,
        onChangeText = function(v)
            inputText_ = v
        end,
        onSend = function(text)
            if activeChannel_ == "世界" then
                sendWorldMessage(text)
            elseif activeChannel_ == "私聊" and privateTarget_ then
                sendPrivateMessage(privateTarget_.uid, text)
            end
            inputText_ = ""
            Router.RebuildUI()
        end,
    }) or nil

    return UI.Panel {
        width = "100%",
        height = "100%",
        backgroundImage = Theme.images.bgChat,
        backgroundFit = "cover",
        children = {
            UI.Panel {
                position = "absolute",
                top = 0, left = 0, right = 0, bottom = 0,
                backgroundColor = { 15, 12, 10, 160 },
            },
            Comp.BuildTopBar(p),
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                backgroundColor = Theme.colors.inkBlack,
                padding = { 4, 8 },
                gap = 4,
                children = channelBtns,
            },
            contentArea,
            inputArea,
            Comp.BuildBottomNav("chat", Router.HandleNavigate),
        },
    }
end

return M
