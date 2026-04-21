-- ============================================================================
-- ui_mail.lua — 邮箱系统客户端
-- 拉取/显示/领取/删除邮件，通过远程事件与 mail_server.lua 通信
-- ============================================================================
---@diagnostic disable: undefined-global
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS

local M = {}

-- 邮件缓存
local mailList_ = {}       -- 当前邮件列表
local unreadCount_ = 0     -- 未读数量
local mailModal_ = nil     -- 弹窗引用
local mailListPanel_ = nil -- 列表容器
local badgeLabel_ = nil    -- 红点标签
local fetchPending_ = false  -- 是否正在等待拉取响应
local fetchTimer_ = 0        -- 拉取超时计时器
local FETCH_TIMEOUT = 5      -- 拉取超时(秒)
local sendResultCallback_ = nil -- GM发送结果回调
local claimingIds_ = {}    -- 正在领取中的邮件ID集合，防止重复点击

-- ========== 注册远程事件监听 ==========

function M.Init()
    -- 事件注册由 shared.lua 统一处理，回调由 client_net.lua 转发
    print("[Mail] Client mail module initialized")
end

-- ========== 发送远程事件工具 ==========

local ClientNet = nil  -- 延迟加载避免循环依赖

---@param eventName string
---@param data? VariantMap
local function sendToServer(eventName, data)
    if not ClientNet then ClientNet = require("network.client_net") end
    if not ClientNet.SendToServer(eventName, data) then
        UI.Toast.Show("未连接到服务器", { variant = "error", duration = 2 })
        return false
    end
    return true
end

-- ========== 拉取邮件 ==========

function M.FetchMails(fetchAll)
    local data = VariantMap()
    data["FetchAll"] = Variant(fetchAll or false)
    if sendToServer(EVENTS.MAIL_FETCH, data) then
        fetchPending_ = true
        fetchTimer_ = 0
    end
end

-- ========== 事件处理 ==========

--- 收到邮件列表（由 client_net.lua 转发调用）
function M.OnMailList(eventData)
    fetchPending_ = false
    local jsonStr = eventData["MailJson"]:GetString()
    local count   = eventData["Count"]:GetInt()

    print("[Mail] Received " .. count .. " mails")

    local ok, list = pcall(cjson.decode, jsonStr)
    if ok and type(list) == "table" then
        -- 确保每封邮件的 value 是 table(可能是 JSON 字符串)
        for _, mail in ipairs(list) do
            if type(mail.value) == "string" then
                local dok, dval = pcall(cjson.decode, mail.value)
                if dok and type(dval) == "table" then
                    mail.value = dval
                end
            end
        end
        mailList_ = list
        -- 仅计数未领取的邮件
        unreadCount_ = 0
        for _, m in ipairs(list) do
            if not m.claimed then unreadCount_ = unreadCount_ + 1 end
        end
    else
        print("[Mail] Failed to decode mail JSON")
        mailList_ = {}
        unreadCount_ = 0
    end

    -- 刷新 UI
    M.RefreshBadge()
    if mailListPanel_ then
        M.RenderMailList()
    end
end

--- 收到操作结果（由 client_net.lua 转发调用）
function M.OnMailResult(eventData)
    local action  = eventData["Action"]:GetString()
    local success = eventData["Success"]:GetBool()
    local message = eventData["Message"]:GetString()

    print("[Mail] Result: action=" .. action .. " success=" .. tostring(success) .. " msg=" .. message)

    if action == "new_mail" then
        -- 收到新邮件通知（其他玩家/GM发来），自动刷新邮箱
        print("[Mail] Received new mail notification, auto-refreshing...")
        M.FetchMails(true)
        -- 显示提示
        UI.Toast.Show("收到新邮件", { variant = "info", duration = 2 })
        return
    elseif action == "send" then
        -- GM 发邮件结果
        if success then
            UI.Toast.Show("邮件发送成功", { variant = "success", duration = 2 })
        else
            UI.Toast.Show("发送失败: " .. message, { variant = "error", duration = 3 })
        end
        -- 通知 GM 面板回调
        if sendResultCallback_ then
            sendResultCallback_(success, success and "邮件发送成功" or ("发送失败: " .. message))
        end
    elseif action == "claim" then
        -- 领取邮件结果 (message 是 msgIdStr 字符串)
        local claimedIdStr = message
        -- 无论成功失败，都解除领取锁定（统一用字符串 key）
        claimingIds_[claimedIdStr] = nil
        if success then
            for _, mail in ipairs(mailList_) do
                if tostring(mail.id) == claimedIdStr then
                    if not State.serverMode then
                        -- 单机模式: 本地发放
                        M.ApplyMailReward(mail)
                    end
                    -- 服务端模式: 奖励已由 mail_server 直接发放，客户端仅标记状态
                    mail.claimed = true
                    break
                end
            end
            -- 重新计数未领取邮件
            unreadCount_ = 0
            for _, m in ipairs(mailList_) do
                if not m.claimed then unreadCount_ = unreadCount_ + 1 end
            end
            M.RefreshBadge()
            if mailListPanel_ then
                M.RenderMailList()
            end
        else
            UI.Toast.Show("领取失败", { variant = "error", duration = 2 })
        end
    elseif action == "delete" then
        if success then
            local deletedIdStr = message
            for i, mail in ipairs(mailList_) do
                if tostring(mail.id) == deletedIdStr then
                    table.remove(mailList_, i)
                    break
                end
            end
            -- 重新计数未领取邮件
            unreadCount_ = 0
            for _, m in ipairs(mailList_) do
                if not m.claimed then unreadCount_ = unreadCount_ + 1 end
            end
            M.RefreshBadge()
            if mailListPanel_ then
                M.RenderMailList()
            end
        end
    elseif action == "fetch" then
        -- 拉取邮件失败
        fetchPending_ = false
        if not success then
            print("[Mail] Fetch failed: " .. message)
            if mailListPanel_ then
                if #mailList_ > 0 then
                    M.RenderMailList()
                else
                    mailListPanel_:ClearChildren()
                    mailListPanel_:AddChild(UI.Label {
                        text = "加载失败，请点击刷新重试",
                        fontSize = 11,
                        fontColor = Config.Colors.textSecond,
                        textAlign = "center",
                        width = "100%",
                        paddingVertical = 20,
                    })
                end
            end
        end
    end
end

-- ========== 发放邮件奖励 ==========

---@param mail table { id, value = { title, reward, ... }, time }
function M.ApplyMailReward(mail)
    local v = mail.value
    if not v then return end

    -- 新版多资源奖励
    if v.reward and type(v.reward) == "table" then
        local r = v.reward
        local parts = {}
        if r.lingshi and r.lingshi > 0 then
            State.AddLingshi(r.lingshi)
            table.insert(parts, HUD.FormatNumber(r.lingshi) .. "灵石")
        end
        if r.xiuwei and r.xiuwei > 0 then
            State.AddXiuwei(r.xiuwei)
            table.insert(parts, r.xiuwei .. "修为")
        end
        if r.materials and type(r.materials) == "table" then
            for matId, amount in pairs(r.materials) do
                State.AddMaterial(matId, amount)
                local mat = Config.GetMaterialById(matId)
                table.insert(parts, amount .. (mat and mat.name or matId))
            end
        end
        if r.products and type(r.products) == "table" then
            for prodId, amount in pairs(r.products) do
                State.AddProduct(prodId, amount)
                local p = Config.GetProductById(prodId)
                table.insert(parts, (p and p.name or prodId) .. "x" .. amount)
            end
        end
        if r.collectibles and type(r.collectibles) == "table" then
            for itemId, count in pairs(r.collectibles) do
                if not State.state.collectibles then State.state.collectibles = {} end
                State.state.collectibles[itemId] = (State.state.collectibles[itemId] or 0) + count
                local c = Config.GetCollectibleById(itemId)
                table.insert(parts, (c and c.name or itemId) .. "x" .. count)
            end
        end
        if #parts > 0 then
            GameCore.AddLog("邮件奖励: +" .. table.concat(parts, ", "), Config.Colors.textGold)
        else
            GameCore.AddLog("已领取邮件: " .. (v.title or ""), Config.Colors.textGold)
        end
    else
        -- 兼容旧版单资源邮件
        local rewardType = v.rewardType or ""
        local rewardAmt  = v.rewardAmt or 0

        if rewardAmt <= 0 then
            GameCore.AddLog("已领取邮件: " .. (v.title or ""), Config.Colors.textGold)
        elseif rewardType == "lingshi" then
            State.AddLingshi(rewardAmt)
            GameCore.AddLog("邮件奖励: +" .. HUD.FormatNumber(rewardAmt) .. " 灵石", Config.Colors.textGold)
        elseif rewardType == "xiuwei" then
            State.AddXiuwei(rewardAmt)
            GameCore.AddLog("邮件奖励: +" .. rewardAmt .. " 修为", Config.Colors.purple)
        elseif rewardType == "lingcao" or rewardType == "lingzhi" or rewardType == "xuantie"
            or rewardType == "yaodan" or rewardType == "jingshi" then
            State.AddMaterial(rewardType, rewardAmt)
            local mat = Config.GetMaterialById(rewardType)
            local matName = mat and mat.name or rewardType
            GameCore.AddLog("邮件奖励: +" .. rewardAmt .. " " .. matName, Config.Colors.textGreen)
        else
            GameCore.AddLog("已领取邮件: " .. (v.title or ""), Config.Colors.textGold)
        end
    end

    GameCore.PlaySFX("upgrade")
    State.Save()
end

-- ========== 红点 ==========

function M.RefreshBadge()
    if badgeLabel_ then
        if unreadCount_ > 0 then
            badgeLabel_:SetText(tostring(unreadCount_))
            badgeLabel_:Show()
        else
            badgeLabel_:Hide()
        end
    end
end

--- 获取未读数量
---@return number
function M.GetUnreadCount()
    return unreadCount_
end

-- ========== 邮箱弹窗 ==========

function M.ShowMailModal()
    -- 先拉取最新邮件
    M.FetchMails(true)

    mailModal_ = UI.Modal {
        title = "邮箱",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self)
            mailListPanel_ = nil
            mailModal_ = nil
            self:Destroy()
        end,
    }

    mailListPanel_ = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
        minHeight = 120,
    }

    mailModal_:AddContent(mailListPanel_)

    -- 有缓存数据时先渲染缓存, 同时后台拉取最新; 无缓存则显示加载提示
    if #mailList_ > 0 then
        M.RenderMailList()
    else
        mailListPanel_:AddChild(UI.Label {
            text = "正在加载邮件...",
            fontSize = 11,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 20,
        })
    end

    -- 底部: 刷新 / 一键已读(含领取) / 删除已读
    mailModal_:SetFooter(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 8,
        children = {
            UI.Button {
                text = "刷新",
                fontSize = 10,
                width = 56,
                height = 28,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textPrimary,
                borderRadius = 6,
                onClick = function(self)
                    M.FetchMails(true)
                    UI.Toast.Show("正在刷新...", { variant = "info", duration = 1 })
                end,
            },
            UI.Button {
                text = "一键已读",
                fontSize = 10,
                width = 72,
                height = 28,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 6,
                onClick = function(self)
                    local count = 0
                    for _, mail in ipairs(mailList_) do
                        if not mail.claimed and not claimingIds_[tostring(mail.id)] then
                            claimingIds_[tostring(mail.id)] = true
                            local data = VariantMap()
                            data["MessageId"] = Variant(tostring(mail.id))
                            sendToServer(EVENTS.MAIL_CLAIM, data)
                            count = count + 1
                        end
                    end
                    if count == 0 then
                        UI.Toast.Show("没有未读邮件", { variant = "info", duration = 2 })
                    else
                        UI.Toast.Show("正在领取并标记 " .. count .. " 封邮件...", { variant = "info", duration = 2 })
                        if mailListPanel_ then M.RenderMailList() end
                    end
                end,
            },
            UI.Button {
                text = "删除已读",
                fontSize = 10,
                width = 72,
                height = 28,
                backgroundColor = { 80, 40, 40, 255 },
                textColor = { 200, 120, 120, 255 },
                borderRadius = 6,
                onClick = function(self)
                    local count = 0
                    for _, mail in ipairs(mailList_) do
                        if mail.claimed then
                            local data = VariantMap()
                            data["MessageId"] = Variant(tostring(mail.id))
                            sendToServer(EVENTS.MAIL_DELETE, data)
                            count = count + 1
                        end
                    end
                    if count == 0 then
                        UI.Toast.Show("没有已读邮件可删除", { variant = "info", duration = 2 })
                    else
                        UI.Toast.Show("正在删除 " .. count .. " 封已读邮件...", { variant = "info", duration = 2 })
                    end
                end,
            },
        },
    })

    mailModal_:Open()
end

-- ========== 渲染邮件列表 ==========

function M.RenderMailList()
    if not mailListPanel_ then return end
    mailListPanel_:ClearChildren()

    if #mailList_ == 0 then
        mailListPanel_:AddChild(UI.Label {
            text = "邮箱为空，暂无邮件",
            fontSize = 11,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 20,
        })
        return
    end

    for _, mail in ipairs(mailList_) do
        local v = mail.value or {}
        local title = v.title or "系统邮件"
        local content = v.content or ""

        -- 奖励描述(兼容新旧格式)
        local rewardText = ""
        local hasReward = false
        if v.reward and type(v.reward) == "table" then
            -- 新版多资源奖励
            local r = v.reward
            local parts = {}
            if r.lingshi and r.lingshi > 0 then table.insert(parts, HUD.FormatNumber(r.lingshi) .. "灵石") end
            if r.xiuwei and r.xiuwei > 0 then table.insert(parts, r.xiuwei .. "修为") end
            if r.materials and type(r.materials) == "table" then
                for matId, amount in pairs(r.materials) do
                    local mat = Config.GetMaterialById(matId)
                    table.insert(parts, amount .. (mat and mat.name or matId))
                end
            end
            if r.products and type(r.products) == "table" then
                for prodId, amount in pairs(r.products) do
                    local p = Config.GetProductById(prodId)
                    table.insert(parts, (p and p.name or prodId) .. "x" .. amount)
                end
            end
            if r.collectibles and type(r.collectibles) == "table" then
                for itemId, count in pairs(r.collectibles) do
                    local c = Config.GetCollectibleById(itemId)
                    table.insert(parts, (c and c.name or itemId) .. "x" .. count)
                end
            end
            if #parts > 0 then
                rewardText = "附件: " .. table.concat(parts, ", ")
                hasReward = true
            end
        else
            -- 兼容旧版单资源
            local rewardType = v.rewardType or ""
            local rewardAmt = v.rewardAmt or 0
            if rewardAmt > 0 then
                hasReward = true
                if rewardType == "lingshi" then
                    rewardText = "附件: " .. HUD.FormatNumber(rewardAmt) .. " 灵石"
                elseif rewardType == "xiuwei" then
                    rewardText = "附件: " .. rewardAmt .. " 修为"
                else
                    local mat = Config.GetMaterialById(rewardType)
                    local matName = mat and mat.name or rewardType
                    rewardText = "附件: " .. rewardAmt .. " " .. matName
                end
            end
        end

        local mailItem = UI.Panel {
            width = "100%",
            padding = 8,
            gap = 3,
            borderRadius = 6,
            backgroundColor = Config.Colors.panelLight,
            borderWidth = 1,
            borderColor = Config.Colors.border,
            children = {
                -- 标题行
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "space-between",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {
                            text = title,
                            fontSize = 12,
                            fontColor = Config.Colors.textGold,
                            fontWeight = "bold",
                            flexShrink = 1,
                        },
                        UI.Label {
                            text = mail.time or "",
                            fontSize = 8,
                            fontColor = Config.Colors.textSecond,
                        },
                    },
                },
                -- 内容
                content ~= "" and UI.Label {
                    text = content,
                    fontSize = 10,
                    fontColor = Config.Colors.textPrimary,
                    width = "100%",
                } or nil,
                -- 奖励
                rewardText ~= "" and UI.Label {
                    text = rewardText,
                    fontSize = 10,
                    fontColor = Config.Colors.textGreen,
                } or nil,
                -- 操作按钮
                UI.Panel {
                    flexDirection = "row",
                    justifyContent = "flex-end",
                    gap = 6,
                    width = "100%",
                    marginTop = 4,
                    children = {
                        (mail.claimed or claimingIds_[tostring(mail.id)]) and UI.Label {
                            text = claimingIds_[tostring(mail.id)] and "领取中..." or (hasReward and "已领取" or "已读"),
                            fontSize = 10,
                            fontColor = Config.Colors.textSecond,
                            paddingHorizontal = 6,
                            paddingVertical = 4,
                        } or UI.Button {
                            text = hasReward and "领取" or "标记已读",
                            fontSize = 10,
                            height = 24,
                            paddingHorizontal = 8,
                            backgroundColor = Config.Colors.jadeDark,
                            textColor = { 255, 255, 255, 255 },
                            borderRadius = 4,
                            onClick = function(self)
                                -- 防止重复点击
                                if claimingIds_[tostring(mail.id)] then return end
                                claimingIds_[tostring(mail.id)] = true
                                local d = VariantMap()
                                d["MessageId"] = Variant(tostring(mail.id))
                                sendToServer(EVENTS.MAIL_CLAIM, d)
                                -- 立即刷新UI显示"领取中..."
                                if mailListPanel_ then M.RenderMailList() end
                            end,
                        },
                        UI.Button {
                            text = "删除",
                            fontSize = 10,
                            width = 48,
                            height = 24,
                            backgroundColor = { 80, 40, 40, 255 },
                            textColor = { 200, 120, 120, 255 },
                            borderRadius = 4,
                            onClick = function(self)
                                local d = VariantMap()
                                d["MessageId"] = Variant(tostring(mail.id))
                                sendToServer(EVENTS.MAIL_DELETE, d)
                            end,
                        },
                    },
                },
            },
        }
        mailListPanel_:AddChild(mailItem)
    end
end

-- ========== GM 发邮件接口(供 ui_gm.lua 调用) ==========

---@param targetUid string|number 目标UID(0或空=广播)
---@param title string 邮件标题
---@param content string 邮件内容
---@param reward table 多资源奖励 { lingshi, xiuwei, materials={}, products={}, collectibles={} }
---@param serverId? number 目标区服ID
function M.SendMailFromGM(targetUid, title, content, reward, serverId)
    -- targetUid 可以是字符串: 平台UID / 角色ID / 角色名 / "0"(全体)
    -- reward: table { lingshi, xiuwei, materials={}, products={}, collectibles={} }
    local targetStr = tostring(targetUid or "0")
    local isBroadcast = (targetStr == "" or targetStr == "0")

    -- 将多资源奖励序列化为 JSON 传输
    local rewardJson = ""
    if reward and type(reward) == "table" then
        local ok, encoded = pcall(cjson.encode, reward)
        if ok then rewardJson = encoded end
    end

    local data = VariantMap()
    data["TargetUid"]  = Variant(targetStr)
    data["Title"]      = Variant(title or "系统邮件")
    data["Content"]    = Variant(content or "")
    data["RewardJson"] = Variant(rewardJson)
    data["Broadcast"]  = Variant(isBroadcast)
    data["ServerId"]   = Variant(serverId or 0)

    if not sendToServer(EVENTS.MAIL_SEND, data) then
        return false
    end
    return true
end

--- GM: 撤回广播邮件
---@param broadcastId number 广播ID
---@return boolean
function M.RevokeBroadcast(broadcastId)
    local data = VariantMap()
    data["BroadcastId"] = Variant(broadcastId)
    return sendToServer(EVENTS.MAIL_REVOKE, data)
end

--- GM: 请求广播历史列表
---@return boolean
function M.FetchBroadcastList()
    local data = VariantMap()
    return sendToServer(EVENTS.MAIL_BROADCAST_LIST, data)
end

--- 设置 GM 发送结果回调(供 ui_gm 注册)
---@param cb fun(success: boolean, msg: string)
function M.SetSendResultCallback(cb)
    sendResultCallback_ = cb
end

-- ========== 帧更新: 拉取超时检测 ==========

--- 每帧更新(由 main.lua 的 HandleUpdate 调用)
---@param dt number
function M.Update(dt)
    if not fetchPending_ then return end
    fetchTimer_ = fetchTimer_ + dt
    if fetchTimer_ >= FETCH_TIMEOUT then
        fetchPending_ = false
        print("[Mail] Fetch timeout after " .. FETCH_TIMEOUT .. "s")
        -- 超时后: 如果弹窗打开中, 显示超时提示
        if mailListPanel_ then
            if #mailList_ > 0 then
                -- 有缓存数据, 显示缓存
                M.RenderMailList()
            else
                mailListPanel_:ClearChildren()
                mailListPanel_:AddChild(UI.Label {
                    text = "加载超时，请点击刷新重试",
                    fontSize = 11,
                    fontColor = Config.Colors.textSecond,
                    textAlign = "center",
                    width = "100%",
                    paddingVertical = 20,
                })
            end
        end
    end
end

-- ========== 创建红点标签(供 main.lua 工具栏使用) ==========

---@return table badgeLabel
function M.CreateBadge()
    badgeLabel_ = UI.Label {
        text = "0",
        fontSize = 7,
        fontColor = { 255, 255, 255, 255 },
        fontWeight = "bold",
        backgroundColor = Config.Colors.red,
        borderRadius = 7,
        width = 14,
        height = 14,
        textAlign = "center",
        position = "absolute",
        top = -3,
        right = -3,
    }
    badgeLabel_:Hide()
    return badgeLabel_
end

return M
