-- ============================================================================
-- ui_chat.lua — 客户端聊天模块
-- 职责：聊天日志滚动条(LogBar) + 聊天全页Tab(本服/私聊/好友) + 好友系统
-- 说明：LogBar 替代旧 ui_log 的 CreateLogBar，与游戏日志共享展示区域
--        聊天界面为独立 Tab 页面(Create/Refresh 模式)，由 main.lua Tab 切换
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local Mentor = require("ui_mentor")
local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson

local M = {}

-- ============================================================================
-- 配置
-- ============================================================================

local CHAT_HISTORY_MAX = 200   -- 客户端聊天历史上限
local TICKER_INTERVAL  = 3.0   -- 滚动条轮播间隔(秒)
local TICKER_HEIGHT    = 30    -- 滚动条高度

-- 头像池(根据性别从 Config.Images 选取)
local AVATAR_MALE_KEYS = { "zongmen" }
local AVATAR_FEMALE_KEYS = { "zongmen_f" }

-- ============================================================================
-- 状态
-- ============================================================================

-- 聊天消息缓存: { { channel, sender, text, timestamp, isSystem }, ... }
local chatMessages_ = {}

-- 私聊消息: targetId -> { { sender, text, timestamp }, ... }
local privateMessages_ = {}

-- 好友列表: { { userId, name, gender, addTime, online }, ... }
local friendList_ = {}

-- 好友申请队列: { { fromId, fromName, fromGender, time }, ... }
local friendRequests_ = {}

-- ticker 状态
local logTickerTimer_ = 0
local logTickerIndex_ = 0

-- 日志淡入淡出动画
local LOG_FADE_SPEED    = 3.0   -- alpha 变化速度(每秒)
local logFadeAlpha_     = 1.0   -- 当前透明度 0~1
local logFadeState_     = "idle" -- "idle"|"fadeOut"|"fadeIn"
local logPendingText_   = nil   -- 淡出完成后要显示的文本
local logPendingColor_  = nil
local LOG_STALE_TIME    = 30   -- 日志过期时间(秒): 超过此时间无新消息则淡出
local logLastTime_      = 0    -- 最新日志的时间戳(os.time)
local logStale_         = false -- 日志已过期(已淡出隐藏)

-- 聊天行动态显示
local CHAT_LINE_SHOW_DURATION = 5.0  -- 新消息显示秒数
local chatLineTimer_ = 0             -- 倒计时
local chatLineVisible_ = false       -- 当前是否可见

-- UI 引用 — LogBar
local logBarPanel_ = nil
local logLabel_ = nil        -- 游戏日志标签
local chatLinePanel_ = nil   -- 聊天消息行容器
local chatLineLabel_ = nil   -- 聊天消息标签
local chatIconBtn_ = nil
local unreadCount_ = 0
local unreadBadge_ = nil

-- UI 引用 — 聊天全页
local chatPanel_ = nil           -- 聊天页面根 Panel (Create 返回)
local chatTab_ = "server"        -- 当前频道: "server" | "private" | "friend"
local chatScrollView_ = nil
local chatInput_ = nil
local chatTabBtns_ = {}
local privateChatTarget_ = nil   -- 当前私聊对象 { userId, name }
local chatDirty_ = true          -- 脏标记: 数据变化时设 true, Refresh 重建后设 false

-- ============================================================================
-- 头像工具
-- ============================================================================

--- 根据 userId 和 gender 确定性选取头像 key
---@param userId number
---@param gender string "male"|"female"
---@return string 头像图片路径
local function getAvatarPath(userId, gender)
    local pool = (gender == "female") and AVATAR_FEMALE_KEYS or AVATAR_MALE_KEYS
    local idx = (userId % #pool) + 1
    local key = pool[idx]
    return Config.Images[key] or Config.Images.sanxiu
end

--- 直接设置日志标签文本(无动画)
local function setLogLabelDirect(text, color)
    if not logLabel_ then return end
    logLabel_:SetText(text)
    logLabel_:SetStyle({ fontColor = color or Config.Colors.textSecond })
    logFadeAlpha_ = 1.0
    logFadeState_ = "idle"
end

--- 用淡入淡出动画切换日志文本
local function setLogLabelAnimated(text, color)
    if not logLabel_ then return end
    if logPendingText_ == text then return end
    logPendingText_ = text
    logPendingColor_ = color or Config.Colors.textSecond
    if logFadeState_ == "idle" then
        logFadeState_ = "fadeOut"
    end
end

-- ============================================================================
-- LogBar (替代旧 ui_log 的 CreateLogBar)
-- ============================================================================

--- 创建日志/聊天滚动条（两行：聊天消息行 + 游戏日志行）
---@return table UI.Panel
function M.CreateLogBar()
    -- ===== 聊天消息行（有新消息时动态出现） =====
    chatLineLabel_ = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.jade,
        maxLines = 1,
        whiteSpace = "nowrap",
        flexGrow = 1,
        flexShrink = 1,
    }

    chatLinePanel_ = UI.Panel {
        width = "100%",
        height = 22,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 30, 45, 40, 240 },
        borderTopWidth = 1,
        borderColor = { 60, 100, 80, 120 },
        paddingHorizontal = 6,
        overflow = "hidden",
        gap = 4,
        children = {
            UI.Label {
                text = "[聊天]",
                fontSize = 8,
                fontColor = Config.Colors.jade,
                fontWeight = "bold",
            },
            chatLineLabel_,
        },
    }
    chatLinePanel_:Hide()
    chatLineVisible_ = false

    -- ===== 游戏日志行（始终显示） =====
    logLabel_ = UI.Label {
        text = "等待事件...",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        maxLines = 1,
        whiteSpace = "nowrap",
        flexGrow = 1,
        flexShrink = 1,
    }

    unreadBadge_ = UI.Label {
        text = "",
        fontSize = 7,
        fontColor = { 255, 255, 255, 255 },
        backgroundColor = Config.Colors.red,
        borderRadius = 6,
        width = 12,
        height = 12,
        textAlign = "center",
        lineHeight = 1.2,
    }
    unreadBadge_:Hide()

    chatIconBtn_ = UI.Button {
        text = "聊天",
        fontSize = 8,
        width = 36,
        height = 20,
        paddingHorizontal = 2,
        backgroundColor = { 50, 52, 68, 200 },
        textColor = Config.Colors.jade,
        borderRadius = 4,
        borderWidth = 1,
        borderColor = Config.Colors.jade,
        onClick = function(self)
            if M.tabSwitcherFn then
                M.tabSwitcherFn("chat")
            end
        end,
    }

    local btnContainer = UI.Panel {
        position = "relative",
        onClick = function(self)
            if chatIconBtn_ and chatIconBtn_.props.onClick then
                chatIconBtn_.props.onClick(chatIconBtn_)
            end
        end,
        children = {
            chatIconBtn_,
            UI.Panel {
                position = "absolute",
                right = -4,
                top = -4,
                children = { unreadBadge_ },
            },
        },
    }

    local logLinePanel = UI.Panel {
        width = "100%",
        height = TICKER_HEIGHT,
        flexDirection = "row",
        alignItems = "center",
        backgroundColor = { 20, 22, 32, 240 },
        paddingHorizontal = 6,
        paddingVertical = 1,
        gap = 4,
        overflow = "hidden",
        onClick = function(self)
            print("[Chat] logLinePanel onClick fired!")
        end,
        children = {
            logLabel_,
            btnContainer,
        },
    }

    -- ===== 组合容器 =====
    logBarPanel_ = UI.Panel {
        id = "chat_log_bar",
        width = "100%",
        children = {
            chatLinePanel_,
            logLinePanel,
        },
    }

    -- 订阅新日志事件：用动画切换显示 + 重置轮播计时器
    State.On("log_added", function(log)
        if logLabel_ and log then
            -- 如果之前已过期隐藏, 先恢复可见
            if logStale_ then
                logStale_ = false
                logFadeAlpha_ = 0
                logFadeState_ = "idle"
                logLabel_:SetStyle({ opacity = 0 })
            end
            logLastTime_ = os.time()
            setLogLabelAnimated(log.text, log.color)
            logTickerTimer_ = 0
            logTickerIndex_ = 0
        end
    end)

    return logBarPanel_
end

--- 注册 Tab 切换回调 (main.lua 调用)
---@type function|nil
M.tabSwitcherFn = nil
function M.SetTabSwitcher(fn)
    M.tabSwitcherFn = fn
end

--- 刷新游戏日志行（只显示游戏日志，轮播）
--- 只有 1 条时固定显示不轮播；多条时轮播最近 5 条
--- 日志过期后停止轮播
function M.RefreshLogBar()
    if not logLabel_ then return end
    if logStale_ then return end  -- 已过期, 不再轮播

    local logs = GameCore.logs
    if #logs == 0 then
        setLogLabelDirect("等待事件...", { 100, 100, 110, 150 })
        return
    end

    -- 初始化最新日志时间(首次或重连后)
    if logLastTime_ == 0 then
        logLastTime_ = logs[1].time or os.time()
    end

    -- 日志 <= 2 条时固定显示最新一条，不轮播
    if #logs <= 2 then
        setLogLabelAnimated(logs[1].text, logs[1].color)
        return
    end

    local logCount = math.min(#logs, 5)
    logTickerIndex_ = logTickerIndex_ % logCount + 1
    local log = logs[logTickerIndex_]
    setLogLabelAnimated(log.text, log.color)
end

--- 显示聊天消息行（收到新消息时调用）
---@param text string 显示的文本
---@param color? table 颜色
local function showChatLine(text, color)
    if not chatLinePanel_ or not chatLineLabel_ then return end
    chatLineLabel_:SetText(text)
    if color then
        chatLineLabel_:SetStyle({ fontColor = color })
    end
    chatLinePanel_:Show()
    chatLineVisible_ = true
    chatLineTimer_ = CHAT_LINE_SHOW_DURATION
end

--- 帧更新：驱动日志轮播(含淡入淡出) + 聊天行倒计时隐藏 + 未读角标
---@param dt number
function M.Update(dt)
    -- 日志淡入淡出动画
    if logFadeState_ == "fadeOut" then
        logFadeAlpha_ = logFadeAlpha_ - dt * LOG_FADE_SPEED
        if logFadeAlpha_ <= 0 then
            logFadeAlpha_ = 0
            if logStale_ then
                -- 过期淡出完成, 保持隐藏
                logFadeState_ = "idle"
                logPendingText_ = nil
                logPendingColor_ = nil
            else
                -- 正常切换文本，开始淡入
                if logPendingText_ and logLabel_ then
                    logLabel_:SetText(logPendingText_)
                    logLabel_:SetStyle({ fontColor = logPendingColor_ or Config.Colors.textSecond })
                    logPendingText_ = nil
                    logPendingColor_ = nil
                end
                logFadeState_ = "fadeIn"
            end
        end
        if logLabel_ then
            logLabel_:SetStyle({ opacity = logFadeAlpha_ })
        end
    elseif logFadeState_ == "fadeIn" then
        logFadeAlpha_ = logFadeAlpha_ + dt * LOG_FADE_SPEED
        if logFadeAlpha_ >= 1.0 then
            logFadeAlpha_ = 1.0
            logFadeState_ = "idle"
        end
        if logLabel_ then
            logLabel_:SetStyle({ opacity = logFadeAlpha_ })
        end
    end

    -- 日志过期检测: 超过 LOG_STALE_TIME 秒无新消息 → 淡出隐藏
    if not logStale_ and logLastTime_ > 0 and logFadeState_ == "idle" then
        if os.time() - logLastTime_ >= LOG_STALE_TIME then
            logStale_ = true
            logFadeState_ = "fadeOut"
        end
    end

    -- 游戏日志轮播
    logTickerTimer_ = logTickerTimer_ + dt
    if logTickerTimer_ >= TICKER_INTERVAL then
        logTickerTimer_ = logTickerTimer_ - TICKER_INTERVAL
        M.RefreshLogBar()
    end

    -- 聊天行倒计时隐藏
    if chatLineVisible_ then
        chatLineTimer_ = chatLineTimer_ - dt
        if chatLineTimer_ <= 0 then
            chatLineVisible_ = false
            if chatLinePanel_ then
                chatLinePanel_:Hide()
            end
        end
    end

    -- 未读角标
    if unreadBadge_ then
        if unreadCount_ > 0 then
            unreadBadge_:SetText(unreadCount_ > 9 and "9+" or tostring(unreadCount_))
            unreadBadge_:Show()
        else
            unreadBadge_:Hide()
        end
    end
end

-- ============================================================================
-- 聊天全页 Tab (Create / Refresh 模式)
-- ============================================================================

-- 前置声明（函数体在后面定义）
local refreshChatContent
local refreshChatTabs

--- 检查某 userId 是否已是好友
---@param userId number
---@return boolean
local function isFriend(userId)
    for _, f in ipairs(friendList_) do
        if f.userId == userId then return true end
    end
    return false
end

--- 头像点击弹出玩家信息弹窗（与排行榜样式一致）
---@param sender table { userId, name, gender, playerId, realm }
local function showPlayerPopup(sender)
    local uid = tonumber(sender.userId) or 0
    if uid == 0 then return end
    local myId = tonumber(M.GetMyUserId()) or 0
    if uid == myId then return end -- 不弹自己

    local alreadyFriend = isFriend(uid)
    local gender = sender.gender or "male"
    local genderText = (gender == "female") and "女" or "男"
    local genderColor = (gender == "female") and Config.Colors.pink or Config.Colors.jade
    local avatarPath = getAvatarPath(uid, gender)

    -- 境界等级转名称
    local realmLevel = tonumber(sender.realm) or 0
    local realmName = "炼气"
    if realmLevel >= 1 and Config.Realms[realmLevel] then
        realmName = Config.Realms[realmLevel].name
    end

    local modal = UI.Modal {
        title = "仙友信息",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    -- 信息行组件（与排行榜 showPlayerInfoModal 一致）
    local function infoRow(label, value, valueColor, canCopy)
        local rowChildren = {
            UI.Label {
                text = label .. ":",
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                flexShrink = 0,
            },
            UI.Label {
                text = value,
                fontSize = 9,
                fontColor = valueColor or Config.Colors.textPrimary,
                flexGrow = 1,
                flexShrink = 1,
            },
        }
        if canCopy then
            table.insert(rowChildren, UI.Button {
                text = "复制",
                fontSize = 8,
                height = 20,
                paddingHorizontal = 6,
                borderRadius = 3,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textSecond,
                onClick = function(self)
                    ---@diagnostic disable-next-line: undefined-global
                    ui:SetClipboardText(value)
                    self:SetText("已复制")
                end,
            })
        end
        return UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            gap = 6,
            paddingVertical = 3,
            children = rowChildren,
        }
    end

    -- 操作按钮
    local function actionBtn(label, color, onClick)
        return UI.Button {
            text = label,
            fontSize = 9,
            height = 26,
            flexGrow = 1,
            backgroundColor = { 45, 48, 65, 200 },
            textColor = color,
            borderRadius = 6,
            onClick = function(self)
                modal:Close()
                if onClick then onClick() end
            end,
        }
    end

    local actionChildren = {
        actionBtn("私聊", Config.Colors.jade, function()
            privateChatTarget_ = { userId = uid, name = sender.name or "无名修士" }
            chatTab_ = "private"
            refreshChatTabs()
            refreshChatContent()
        end),
    }
    if alreadyFriend then
        table.insert(actionChildren, actionBtn("已是好友", Config.Colors.textSecond, nil))
    else
        table.insert(actionChildren, actionBtn("加好友", Config.Colors.blue, function()
            M.SendFriendRequest(tostring(uid))
        end))
    end

    -- 师徒按钮
    local myState = State.state
    local myRealm = myState and myState.realmLevel or 0
    local targetRealm = realmLevel
    local MentorCfg = Config.MentorConfig
    -- 检查是否已经是师徒关系
    local isMyMaster = myState and myState.masterId and (tonumber(myState.masterId) == uid)
    local isMyDisciple = false
    if myState then
        for _, d in ipairs(myState.disciples or {}) do
            if tonumber(d.userId) == uid then isMyDisciple = true; break end
        end
    end
    local hasGraduated = myState and myState.hasGraduated
    if isMyMaster or isMyDisciple then
        -- 已是师徒，只展示标识，不展示收徒/拜师按钮
        local relText = isMyMaster and "我的师父" or "我的徒弟"
        table.insert(actionChildren, UI.Panel {
            flexGrow = 1, height = 26,
            backgroundColor = { 40, 55, 40, 200 },
            borderRadius = 6,
            alignItems = "center", justifyContent = "center",
            children = {
                UI.Label {
                    text = "已是师徒（" .. relText .. "）",
                    fontSize = 9,
                    fontColor = Config.Colors.jade,
                },
            },
        })
    elseif hasGraduated then
        -- 已出师，不可再拜师，但仍可收徒
        -- 收徒: 我境界>=元婴 且 对方境界比我低2级以上 且 我没师父 且 徒弟未满
        if myRealm >= MentorCfg.masterMinRealm
           and targetRealm <= (myRealm - MentorCfg.realmGap)
           and not myState.masterId
           and #(myState.disciples or {}) < MentorCfg.maxDisciples then
            table.insert(actionChildren, actionBtn("收徒", Config.Colors.textGold, function()
                GameCore.SendGameAction("mentor_invite", { targetUserId = uid })
            end))
        end
        -- 不显示拜师按钮（已出师）
    else
        -- 收徒: 我境界>=元婴 且 对方境界比我低2级以上 且 我没师父 且 徒弟未满
        if myRealm >= MentorCfg.masterMinRealm
           and targetRealm <= (myRealm - MentorCfg.realmGap)
           and not myState.masterId
           and #(myState.disciples or {}) < MentorCfg.maxDisciples then
            table.insert(actionChildren, actionBtn("收徒", Config.Colors.textGold, function()
                GameCore.SendGameAction("mentor_invite", { targetUserId = uid })
            end))
        end
        -- 拜师: 对方境界>=元婴 且 我境界比对方低2级以上 且 我没师父 且 我没徒弟
        if targetRealm >= MentorCfg.masterMinRealm
           and myRealm <= (targetRealm - MentorCfg.realmGap)
           and not myState.masterId
           and #(myState.disciples or {}) == 0 then
            table.insert(actionChildren, actionBtn("拜师", Config.Colors.purple, function()
                GameCore.SendGameAction("mentor_apply", { targetUserId = uid })
            end))
        end
    end

    local playerId = sender.playerId or ""

    -- 在线状态标签（提前创建，直接引用避免 FindById 失败）
    local onlineLbl = UI.Label {
        text = "...",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        gap = 8,
        padding = 8,
        alignItems = "center",
        children = {
            -- 头像 + 名字
            UI.Panel {
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Panel {
                        width = 40, height = 40,
                        borderRadius = 20,
                        overflow = "hidden",
                        borderWidth = 2,
                        borderColor = genderColor,
                        backgroundImage = avatarPath,
                    },
                    UI.Label {
                        text = sender.name or "无名修士",
                        fontSize = 11,
                        fontWeight = "bold",
                        fontColor = Config.Colors.textPrimary,
                    },
                    UI.Label {
                        text = realmName,
                        fontSize = 9,
                        fontColor = Config.Colors.textGold,
                    },
                    -- 在线状态（直接引用 onlineLbl，不用 FindById）
                    onlineLbl,
                },
            },
            -- 分割线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Config.Colors.border,
            },
            -- 信息列表
            UI.Panel {
                width = "100%",
                gap = 2,
                children = {
                    infoRow("性别", genderText, genderColor),
                    infoRow("境界", realmName, Config.Colors.textGold),
                    infoRow("用户ID", tostring(uid), nil, true),
                    infoRow("角色ID", playerId ~= "" and playerId or "-", nil, playerId ~= ""),
                },
            },
            -- 分割线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Config.Colors.border,
            },
            -- 操作按钮行
            UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 8,
                children = actionChildren,
            },
        },
    })

    -- 在线状态：直接使用 onlineLbl 引用更新
    local function setOnlineLabel(online)
        if online then
            onlineLbl:SetText("在线")
            onlineLbl:SetFontColor(Config.Colors.green)
        else
            onlineLbl:SetText("离线")
            onlineLbl:SetFontColor(Config.Colors.textSecond)
        end
    end

    -- 统一查询在线状态(好友和非好友)
    local function onOnlineResult(data)
        local dataTargetId = tonumber(data.targetId) or 0
        if dataTargetId == uid then
            setOnlineLabel(data.online)
        end
    end
    State.On("online_status_result", onOnlineResult)
    local origClose = modal.props.onClose
    modal.props.onClose = function(self)
        State.Off("online_status_result", onOnlineResult)
        if origClose then origClose(self) else self:Destroy() end
    end

    if alreadyFriend then
        -- 好友：先从本地缓存显示,再发请求获取实时状态
        for _, f in ipairs(friendList_) do
            if f.userId == uid then
                setOnlineLabel(f.online)
                break
            end
        end
    end
    -- 无论好友与否都发服务端查询最新状态
    GameCore.SendGameAction("check_online", { targetId = tostring(uid) })

    modal:Open()
end

--- 创建可点击头像组件
---@param sender table
---@param size number
---@param nameColor table
---@return table UI element
local function createAvatar(sender, size, nameColor)
    local uid = tonumber(sender.userId) or 0
    local avatarPath = getAvatarPath(uid, sender.gender or "male")
    local myId = tonumber(M.GetMyUserId()) or 0
    local clickable = (uid ~= 0 and uid ~= myId)

    return UI.Button {
        backgroundImage = avatarPath,
        backgroundSize = "cover",
        width = size, height = size,
        borderRadius = math.floor(size / 2),
        borderWidth = 1, borderColor = nameColor,
        backgroundColor = { 0, 0, 0, 0 },
        text = "",
        onClick = clickable and function(self) showPlayerPopup(sender) end or nil,
    }
end

--- 创建聊天消息气泡
---@param msg table { sender, text, timestamp, isSystem }
---@param isPrivate boolean
---@return table UI element
local function createChatBubble(msg, isPrivate)
    if msg.isSystem then
        return UI.Panel {
            width = "100%",
            alignItems = "center",
            paddingVertical = 3,
            children = {
                UI.Label {
                    text = "-- " .. msg.text .. " --",
                    fontSize = 9,
                    fontColor = Config.Colors.orange,
                    textAlign = "center",
                },
            },
        }
    end

    local sender = msg.sender or {}
    local myId = tonumber(M.GetMyUserId()) or 0
    local isSelf = (tonumber(sender.userId) == myId)
    local nameColor = isSelf and Config.Colors.jade
        or (sender.gender == "female") and Config.Colors.pink
        or Config.Colors.jade
    local timeStr = ""
    if msg.timestamp and msg.timestamp > 0 then
        timeStr = os.date("%H:%M", msg.timestamp)
    end
    local displayName = isSelf and "我" or (sender.name or "无名修士")
    local bubbleBg = isSelf and Config.Colors.bubbleSelf or Config.Colors.bubbleOther
    local bubbleBorder = isSelf and { 58, 120, 100, 80 } or { 55, 58, 75, 60 }

    -- ========== 私聊模式：左右分列(微信风格) ==========
    if isPrivate then
        local avatarSize = 30
        local avatar = createAvatar(sender, avatarSize, nameColor)

        -- Label 带 whiteSpace="normal" 时内部强制 alignSelf="stretch" 来获取父宽度
        -- 因此不能在 Label 上设 alignSelf，否则宽度为 0
        local contentPanel = UI.Panel {
            flexShrink = 1,
            flexGrow = 1,
            gap = 2,
            children = {
                -- 时间
                (timeStr ~= "") and UI.Label {
                    text = timeStr,
                    fontSize = 7,
                    fontColor = Config.Colors.textSecond,
                    textAlign = isSelf and "right" or "left",
                } or nil,
                -- 气泡：样式直接放在 Label 上，不设 alignSelf（让 stretch 生效）
                UI.Label {
                    text = msg.text,
                    fontSize = 10,
                    fontColor = Config.Colors.textPrimary,
                    whiteSpace = "normal",
                    lineHeight = 1.4,
                    backgroundColor = bubbleBg,
                    borderRadius = 10,
                    borderWidth = 1,
                    borderColor = bubbleBorder,
                    paddingHorizontal = 10,
                    paddingVertical = 6,
                    textAlign = isSelf and "right" or "left",
                },
            },
        }

        return UI.Panel {
            width = "100%",
            flexDirection = "row",
            justifyContent = isSelf and "flex-end" or "flex-start",
            gap = 6,
            paddingVertical = 3,
            paddingHorizontal = 6,
            children = isSelf
                and { contentPanel, avatar }
                or  { avatar, contentPanel },
        }
    end

    -- ========== 公频模式：统一左对齐，颜色区分 ==========
    local avatar = createAvatar(sender, 28, nameColor)

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        gap = 6,
        paddingVertical = 3,
        paddingHorizontal = 6,
        backgroundColor = isSelf and { 35, 55, 50, 60 } or nil,
        borderRadius = isSelf and 6 or 0,
        children = {
            -- 头像(可点击)
            avatar,
            -- 内容
            UI.Panel {
                flexShrink = 1,
                flexGrow = 1,
                gap = 2,
                children = {
                    -- 名字 + 时间
                    UI.Panel {
                        flexDirection = "row",
                        gap = 6,
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = displayName,
                                fontSize = 9,
                                fontColor = isSelf and Config.Colors.jade or nameColor,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = timeStr,
                                fontSize = 7,
                                fontColor = Config.Colors.textSecond,
                            },
                        },
                    },
                    -- 消息文本
                    UI.Label {
                        text = msg.text,
                        fontSize = 10,
                        fontColor = Config.Colors.textPrimary,
                        whiteSpace = "normal",
                        lineHeight = 1.4,
                        backgroundColor = bubbleBg,
                        borderRadius = 8,
                        borderWidth = 1,
                        borderColor = bubbleBorder,
                        paddingHorizontal = 8,
                        paddingVertical = 4,
                    },
                },
            },
        },
    }
end

--- 刷新好友列表内容 (前置声明)
local refreshFriendList

--- 刷新聊天内容区
refreshChatContent = function()
    if not chatScrollView_ then return end

    chatScrollView_:ClearChildren()

    if chatTab_ == "server" then
        if #chatMessages_ == 0 then
            chatScrollView_:AddChild(UI.Label {
                text = "暂无消息，快来聊天吧!",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
                paddingVertical = 20,
            })
        else
            for i = 1, #chatMessages_ do
                chatScrollView_:AddChild(createChatBubble(chatMessages_[i], false))
            end
        end
    elseif chatTab_ == "private" then
        if not privateChatTarget_ then
            chatScrollView_:AddChild(UI.Label {
                text = "从好友列表选择一位好友开始私聊",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
                paddingVertical = 20,
            })
        else
            local msgs = privateMessages_[privateChatTarget_.userId] or {}
            if #msgs == 0 then
                chatScrollView_:AddChild(UI.Label {
                    text = "与 " .. privateChatTarget_.name .. " 暂无消息",
                    fontSize = 10,
                    fontColor = Config.Colors.textSecond,
                    textAlign = "center",
                    width = "100%",
                    paddingVertical = 20,
                })
            else
                for i = 1, #msgs do
                    chatScrollView_:AddChild(createChatBubble(msgs[i], true))
                end
            end
        end
    elseif chatTab_ == "friend" then
        refreshFriendList()
        return
    end

    chatScrollView_:ScrollToBottom()
end

--- 刷新好友列表内容
refreshFriendList = function()
    if not chatScrollView_ then return end

    -- 好友申请区域
    if #friendRequests_ > 0 then
        chatScrollView_:AddChild(UI.Label {
            text = "好友申请 (" .. #friendRequests_ .. ")",
            fontSize = 10,
            fontColor = Config.Colors.orange,
            fontWeight = "bold",
            paddingHorizontal = 6,
            paddingVertical = 4,
        })

        for _, req in ipairs(friendRequests_) do
            local avatarPath = getAvatarPath(req.fromId or 0, req.fromGender or "male")
            chatScrollView_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                paddingHorizontal = 6,
                paddingVertical = 4,
                borderBottomWidth = 1,
                borderColor = { 50, 50, 60, 100 },
                children = {
                    UI.Panel {
                        backgroundImage = avatarPath,
                        backgroundSize = "cover",
                        width = 24,
                        height = 24,
                        borderRadius = 12,
                    },
                    UI.Label {
                        text = req.fromName or "无名修士",
                        fontSize = 10,
                        fontColor = Config.Colors.textPrimary,
                        flexGrow = 1,
                    },
                    UI.Button {
                        text = "接受",
                        fontSize = 8,
                        width = 36,
                        height = 20,
                        backgroundColor = Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            M.ReplyFriendRequest(tostring(req.fromId), true)
                        end,
                    },
                    UI.Button {
                        text = "拒绝",
                        fontSize = 8,
                        width = 36,
                        height = 20,
                        backgroundColor = { 80, 40, 40, 200 },
                        textColor = { 200, 150, 150, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            M.ReplyFriendRequest(tostring(req.fromId), false)
                        end,
                    },
                },
            })
        end
    end

    -- 师徒邀请区域
    local s = State.state
    local mentorInvites = s and s.pendingMentorInvites or {}
    if #mentorInvites > 0 then
        chatScrollView_:AddChild(UI.Label {
            text = "师徒邀请 (" .. #mentorInvites .. ")",
            fontSize = 9,
            fontColor = Config.Colors.purple,
            fontWeight = "bold",
            paddingHorizontal = 6,
            paddingVertical = 4,
        })

        for _, inv in ipairs(mentorInvites) do
            local fromName = inv.fromName or "仙友"
            local invType = inv.inviteType or "recruit"
            local typeLabel = invType == "recruit" and "收徒邀请" or "拜师申请"
            local typeDesc = invType == "recruit"
                and (fromName .. " 想收你为徒")
                or (fromName .. " 想拜你为师")

            chatScrollView_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                paddingHorizontal = 6,
                paddingVertical = 4,
                borderBottomWidth = 1,
                borderColor = { 50, 50, 60, 100 },
                children = {
                    UI.Panel {
                        backgroundImage = getAvatarPath(inv.fromId or 0, "male"),
                        backgroundSize = "cover",
                        width = 24, height = 24,
                        borderRadius = 12,
                    },
                    UI.Panel {
                        flexGrow = 1, gap = 1,
                        children = {
                            UI.Label {
                                text = typeLabel,
                                fontSize = 9,
                                fontColor = Config.Colors.purple,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = typeDesc,
                                fontSize = 9,
                                fontColor = Config.Colors.textPrimary,
                            },
                        },
                    },
                    UI.Button {
                        text = "接受",
                        fontSize = 8,
                        width = 36, height = 20,
                        backgroundColor = Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            GameCore.SendGameAction("mentor_accept", { fromId = inv.fromId })
                            -- 刷新列表
                            if chatTab_ == "friend" then
                                chatScrollView_:ClearChildren()
                                refreshFriendList()
                            end
                        end,
                    },
                    UI.Button {
                        text = "拒绝",
                        fontSize = 8,
                        width = 36, height = 20,
                        backgroundColor = { 80, 40, 40, 200 },
                        textColor = { 200, 150, 150, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            GameCore.SendGameAction("mentor_reject", { fromId = inv.fromId })
                            if chatTab_ == "friend" then
                                chatScrollView_:ClearChildren()
                                refreshFriendList()
                            end
                        end,
                    },
                },
            })
        end
    end

    -- 好友列表
    chatScrollView_:AddChild(UI.Label {
        text = "好友 (" .. #friendList_ .. "/50)",
        fontSize = 10,
        fontColor = Config.Colors.jade,
        fontWeight = "bold",
        paddingHorizontal = 6,
        paddingVertical = 4,
    })

    if #friendList_ == 0 then
        chatScrollView_:AddChild(UI.Label {
            text = "暂无好友，在聊天中点击 [+友] 添加",
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 16,
        })
    else
        local sorted = {}
        for _, f in ipairs(friendList_) do table.insert(sorted, f) end
        table.sort(sorted, function(a, b)
            if a.online ~= b.online then return a.online end
            return (a.name or "") < (b.name or "")
        end)

        for _, friend in ipairs(sorted) do
            local avatarPath = getAvatarPath(friend.userId or 0, friend.gender or "male")
            local statusColor = friend.online and Config.Colors.green or Config.Colors.textSecond
            local statusText = friend.online and "在线" or "离线"
            local function onFriendClick()
                showPlayerPopup({
                    userId = friend.userId,
                    name = friend.name,
                    gender = friend.gender,
                })
            end

            chatScrollView_:AddChild(UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                paddingHorizontal = 6,
                paddingVertical = 5,
                borderBottomWidth = 1,
                borderColor = { 50, 50, 60, 100 },
                children = {
                    -- 头像可点击
                    UI.Button {
                        backgroundImage = avatarPath,
                        backgroundSize = "cover",
                        width = 26,
                        height = 26,
                        borderRadius = 13,
                        borderWidth = 1,
                        borderColor = statusColor,
                        backgroundColor = { 0, 0, 0, 0 },
                        text = "",
                        onClick = function(self) onFriendClick() end,
                    },
                    -- 名字+状态（点击头像即可弹出弹窗，此区域仅展示）
                    UI.Panel {
                        flexGrow = 1,
                        gap = 1,
                        children = {
                            UI.Label {
                                text = friend.name or "未知",
                                fontSize = 10,
                                fontColor = Config.Colors.textPrimary,
                            },
                            UI.Label {
                                text = statusText,
                                fontSize = 8,
                                fontColor = statusColor,
                            },
                        },
                    },
                    UI.Button {
                        text = "私聊",
                        fontSize = 8,
                        width = 36,
                        height = 20,
                        backgroundColor = Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            privateChatTarget_ = { userId = friend.userId, name = friend.name }
                            chatTab_ = "private"
                            refreshChatTabs()
                            refreshChatContent()
                        end,
                    },
                    UI.Button {
                        text = "删除",
                        fontSize = 8,
                        width = 36,
                        height = 20,
                        backgroundColor = { 80, 40, 40, 200 },
                        textColor = { 200, 150, 150, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            M.RemoveFriend(tostring(friend.userId))
                        end,
                    },
                },
            })
        end
    end
end

--- 切换聊天频道 Tab 高亮
refreshChatTabs = function()
    for id, btn in pairs(chatTabBtns_) do
        if id == chatTab_ then
            btn:SetStyle({ backgroundColor = Config.Colors.jade, textColor = { 255, 255, 255, 255 } })
        else
            btn:SetStyle({ backgroundColor = { 50, 52, 68, 200 }, textColor = Config.Colors.textSecond })
        end
    end
end

--- 创建聊天全页 (由 main.lua createPageContainer 调用)
---@return table UI.Panel
function M.Create()
    -- 频道 Tab 栏
    local function makeTabBtn(id, label)
        local btn = UI.Button {
            text = label,
            fontSize = 9,
            height = 24,
            paddingHorizontal = 12,
            backgroundColor = (id == chatTab_) and Config.Colors.jade or { 50, 52, 68, 200 },
            textColor = (id == chatTab_) and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 4,
            onClick = function(self)
                if id == "mentor" then
                    print("[Mentor] 师徒按钮点击")
                    Mentor.ShowMentorModal()
                    return
                end
                chatTab_ = id
                refreshChatTabs()
                refreshChatContent()
                if id == "friend" then
                    M.RequestFriendList()
                end
            end,
        }
        chatTabBtns_[id] = btn
        return btn
    end

    local tabBar = UI.Panel {
        flexDirection = "row",
        gap = 4,
        paddingHorizontal = 8,
        paddingVertical = 4,
        width = "100%",
        backgroundColor = Config.Colors.panel,
        borderBottomWidth = 1,
        borderColor = Config.Colors.border,
        children = {
            makeTabBtn("server",  "本服"),
            makeTabBtn("private", "私聊"),
            makeTabBtn("friend",  "好友"),
            makeTabBtn("mentor",  "师徒"),
        },
    }

    -- 聊天内容区
    chatScrollView_ = UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        scrollY = true,
        showScrollbar = false,
        backgroundColor = { 25, 27, 38, 255 },
        children = {},
    }

    -- 输入区
    chatInput_ = UI.TextField {
        placeholder = "输入消息...",
        fontSize = 10,
        height = 30,
        flexGrow = 1,
        flexShrink = 1,
        borderRadius = 4,
        borderWidth = 1,
        borderColor = Config.Colors.border,
        backgroundColor = { 35, 38, 52, 255 },
        fontColor = Config.Colors.textPrimary,
        paddingHorizontal = 8,
    }

    local sendBtn = UI.Button {
        text = "发送",
        fontSize = 10,
        width = 48,
        height = 30,
        backgroundColor = Config.Colors.jadeDark,
        textColor = { 255, 255, 255, 255 },
        borderRadius = 4,
        onClick = function(self)
            local text = chatInput_:GetText()
            if text == "" then return end
            M.SendChatMessage(text)
            chatInput_:SetText("")
        end,
    }

    local inputBar = UI.Panel {
        flexDirection = "row",
        gap = 4,
        paddingHorizontal = 8,
        paddingVertical = 4,
        width = "100%",
        alignItems = "center",
        borderTopWidth = 1,
        borderColor = Config.Colors.border,
        backgroundColor = Config.Colors.panel,
        children = {
            chatInput_,
            sendBtn,
        },
    }

    chatPanel_ = UI.Panel {
        id = "page_chat",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        children = {
            tabBar,
            chatScrollView_,
            inputBar,
        },
    }

    return chatPanel_
end

--- 刷新聊天页 (Tab 切换 / 定时刷新时调用)
function M.Refresh()
    if not chatPanel_ then return end
    -- 进入聊天页时清零未读
    unreadCount_ = 0
    if not chatDirty_ then return end
    chatDirty_ = false
    refreshChatContent()
end

--- 标记需要刷新(切换Tab或收到新消息时)
function M.MarkDirty()
    chatDirty_ = true
end

-- ============================================================================
-- 网络发送
-- ============================================================================

--- 获取聊天未读消息数
---@return number
function M.GetUnreadCount()
    return unreadCount_ or 0
end

--- 获取本机 userId
---@return number
function M.GetMyUserId()
    -- 优先使用 clientCloud.userId（与排行榜一致，类型可靠）
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud and clientCloud.userId then
        ---@diagnostic disable-next-line: undefined-global
        return tonumber(clientCloud.userId) or 0
    end
    ---@diagnostic disable-next-line: undefined-global
    if lobby and lobby.GetMyUserId then
        ---@diagnostic disable-next-line: undefined-global
        return tonumber(lobby:GetMyUserId()) or 0
    end
    return 0
end

--- 发送公共聊天消息
---@param text string
function M.SendChatMessage(text)
    if not IsNetworkMode or not IsNetworkMode() then
        local sender = {
            userId = 0,
            name = State.GetDisplayName(),
            gender = State.state.playerGender or "male",
            playerId = State.GetPlayerId(),
        }
        M.AddChatMessage("server", sender, text, os.time(), false)
        return
    end

    if chatTab_ == "private" and privateChatTarget_ then
        local data = VariantMap()
        data["TargetId"] = Variant(tostring(privateChatTarget_.userId))
        data["Text"]     = Variant(text)
        local ClientNet = require("network.client_net")
        ClientNet.SendToServer(EVENTS.CHAT_PRIVATE, data)
    else
        local data = VariantMap()
        data["Channel"] = Variant("server")
        data["Text"]    = Variant(text)
        local ClientNet = require("network.client_net")
        ClientNet.SendToServer(EVENTS.CHAT_SEND, data)
    end
end

--- 发送好友申请
---@param targetId string
function M.SendFriendRequest(targetId)
    if not IsNetworkMode or not IsNetworkMode() then return end
    local data = VariantMap()
    data["TargetId"] = Variant(targetId)
    local ClientNet = require("network.client_net")
    ClientNet.SendToServer(EVENTS.FRIEND_REQ_SEND, data)
end

--- 回复好友申请
---@param fromId string
---@param accept boolean
function M.ReplyFriendRequest(fromId, accept)
    if not IsNetworkMode or not IsNetworkMode() then return end
    local data = VariantMap()
    data["FromId"]  = Variant(fromId)
    data["Accept"]  = Variant(accept)
    local ClientNet = require("network.client_net")
    ClientNet.SendToServer(EVENTS.FRIEND_REQ_REPLY, data)

    for i, req in ipairs(friendRequests_) do
        if tostring(req.fromId) == fromId then
            table.remove(friendRequests_, i)
            break
        end
    end

    if chatTab_ == "friend" then
        chatScrollView_:ClearChildren()
        refreshFriendList()
    end
end

--- 删除好友
---@param targetId string
function M.RemoveFriend(targetId)
    if not IsNetworkMode or not IsNetworkMode() then return end
    local data = VariantMap()
    data["TargetId"] = Variant(targetId)
    local ClientNet = require("network.client_net")
    ClientNet.SendToServer(EVENTS.FRIEND_REMOVE, data)
end

--- 请求好友列表
function M.RequestFriendList()
    if not IsNetworkMode or not IsNetworkMode() then return end
    local ClientNet = require("network.client_net")
    ClientNet.SendToServer(EVENTS.FRIEND_LIST_REQ)
end

-- ============================================================================
-- 消息接收(由 client_net.lua 转发调用)
-- ============================================================================

--- 添加聊天消息到本地缓存
---@param channel string
---@param sender table { userId, name, gender, playerId }
---@param text string
---@param timestamp number
---@param isSystem boolean
function M.AddChatMessage(channel, sender, text, timestamp, isSystem)
    table.insert(chatMessages_, {
        channel = channel,
        sender = sender,
        text = text,
        timestamp = timestamp,
        isSystem = isSystem,
    })

    while #chatMessages_ > CHAT_HISTORY_MAX do
        table.remove(chatMessages_, 1)
    end

    chatDirty_ = true
    -- 聊天页打开且在公频 tab 时刷新
    if chatPanel_ and chatTab_ == "server" then
        refreshChatContent()
    end

    -- LogBar 聊天行：显示最新消息
    local prefix = isSystem and "[系统] " or ("[" .. (sender.name or "?") .. "] ")
    local lineColor = isSystem and Config.Colors.orange or Config.Colors.jade
    showChatLine(prefix .. text, lineColor)

    -- 未读计数(聊天页未显示时)
    if not isSystem then
        unreadCount_ = unreadCount_ + 1
    end
end

--- 添加私聊消息到本地缓存
---@param sender table
---@param text string
---@param timestamp number
local function addPrivateMessage(sender, text, timestamp)
    local peerId = sender.userId
    local myId = M.GetMyUserId()
    if peerId == myId then
        if privateChatTarget_ then
            peerId = privateChatTarget_.userId
        else
            return
        end
    end

    if not privateMessages_[peerId] then
        privateMessages_[peerId] = {}
    end
    table.insert(privateMessages_[peerId], {
        sender = sender,
        text = text,
        timestamp = timestamp,
    })

    while #(privateMessages_[peerId]) > CHAT_HISTORY_MAX do
        table.remove(privateMessages_[peerId], 1)
    end

    chatDirty_ = true
    if chatPanel_ and chatTab_ == "private" and privateChatTarget_
        and privateChatTarget_.userId == peerId then
        refreshChatContent()
    end

    -- LogBar 聊天行：显示私聊消息
    local sName = sender.name or "?"
    showChatLine("[私聊] " .. sName .. ": " .. text, Config.Colors.purple)

    unreadCount_ = unreadCount_ + 1
end

--- 公共聊天消息回调
function M.OnChatMsg(eventData)
    local channel    = eventData["Channel"] and eventData["Channel"]:GetString() or "server"
    local senderJson = eventData["SenderJson"] and eventData["SenderJson"]:GetString() or "{}"
    local text       = eventData["Text"] and eventData["Text"]:GetString() or ""
    local timestamp  = eventData["Timestamp"] and eventData["Timestamp"]:GetInt() or os.time()

    local ok, sender = pcall(cjson.decode, senderJson)
    if not ok then
        sender = { userId = 0, name = "?", gender = "male" }
    end

    M.AddChatMessage(channel, sender, text, timestamp, false)
end

--- 私聊消息回调
function M.OnChatPrivateMsg(eventData)
    local senderJson = eventData["SenderJson"] and eventData["SenderJson"]:GetString() or "{}"
    local text       = eventData["Text"] and eventData["Text"]:GetString() or ""
    local timestamp  = eventData["Timestamp"] and eventData["Timestamp"]:GetInt() or os.time()

    local ok, sender = pcall(cjson.decode, senderJson)
    if not ok then sender = { userId = 0, name = "?", gender = "male" } end

    addPrivateMessage(sender, text, timestamp)
end

--- 好友申请回调
function M.OnFriendReqIn(eventData)
    local fromJson = eventData["FromJson"] and eventData["FromJson"]:GetString() or "{}"
    local ok, from = pcall(cjson.decode, fromJson)
    if not ok then return end

    table.insert(friendRequests_, {
        fromId = from.userId or 0,
        fromName = from.name or "无名修士",
        fromGender = from.gender or "male",
        time = os.time(),
    })

    UI.Toast.Show((from.name or "无名修士") .. " 请求添加你为好友")

    chatDirty_ = true
    if chatTab_ == "friend" then
        chatScrollView_:ClearChildren()
        refreshFriendList()
    end
end

--- 好友列表回调
function M.OnFriendListData(eventData)
    local friendsJson = eventData["FriendsJson"] and eventData["FriendsJson"]:GetString() or "[]"
    local ok, list = pcall(cjson.decode, friendsJson)
    if not ok then list = {} end

    friendList_ = list
    chatDirty_ = true

    if chatTab_ == "friend" then
        chatScrollView_:ClearChildren()
        refreshFriendList()
    end
end

--- 好友状态变更回调
function M.OnFriendUpdate(eventData)
    local action  = eventData["Action"] and eventData["Action"]:GetString() or ""
    local success = eventData["Success"] and eventData["Success"]:GetBool() or false
    local msg     = eventData["Msg"] and eventData["Msg"]:GetString() or ""

    if msg ~= "" then
        UI.Toast.Show(msg)
    end

    if success and (action == "req_accepted" or action == "remove") then
        M.RequestFriendList()
    end
end

--- 聊天历史回调（新玩家加入时服务端推送最近消息）
function M.OnChatHistory(eventData)
    local histJson = eventData["HistoryJson"] and eventData["HistoryJson"]:GetString() or "[]"
    local ok, items = pcall(cjson.decode, histJson)
    if not ok or type(items) ~= "table" then
        return
    end

    print("[Chat] OnChatHistory: 收到 " .. #items .. " 条历史消息")

    -- 插入到本地缓存前面（历史在先，新消息在后）
    local oldMessages = chatMessages_
    chatMessages_ = {}
    for _, item in ipairs(items) do
        local senderOk, sender = pcall(cjson.decode, item.senderJson or "{}")
        if not senderOk then sender = { userId = 0, name = "?", gender = "male" } end
        table.insert(chatMessages_, {
            channel = "server",
            sender = sender,
            text = item.text or "",
            timestamp = item.timestamp or 0,
            isSystem = false,
        })
    end
    -- 追加已有的新消息（避免重复推送覆盖实时消息）
    for _, msg in ipairs(oldMessages) do
        table.insert(chatMessages_, msg)
    end

    chatDirty_ = true
    -- 刷新聊天页（如果打开了）
    if chatPanel_ and chatTab_ == "server" then
        refreshChatContent()
    end
end

--- 系统消息回调
function M.OnChatSystem(eventData)
    local text = eventData["Text"] and eventData["Text"]:GetString() or ""
    if text == "" then return end

    M.AddChatMessage("server", { userId = 0, name = "系统" }, text, os.time(), true)
end

-- ============================================================================
-- 换服时清理本地缓存
-- ============================================================================

--- 清空聊天/私聊/好友本地缓存（换服时由 client_net 调用）
function M.ClearLocalCache()
    print("[Chat] ClearLocalCache: 清空本地聊天缓存(换服)")
    chatMessages_    = {}
    privateMessages_ = {}
    friendList_      = {}
    friendRequests_  = {}
    privateChatTarget_ = nil
    unreadCount_     = 0
    chatDirty_       = true

    -- 如果聊天页已打开，立即刷新显示
    if chatPanel_ then
        refreshChatContent()
    end
end

return M
