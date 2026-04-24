-- ============================================================================
-- 《问道长生》邮件系统逻辑层
-- 职责：邮件数据管理、领取逻辑、未读计数
-- 架构：serverCloud.message 存储，客户端通过远程事件请求
-- ============================================================================

local GamePlayer = require("game_player")
local Toast      = require("ui_toast")
---@diagnostic disable-next-line: undefined-global
local cjson      = cjson  -- 引擎内置全局变量，无需 require

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

---@type table[]|nil  邮件列表缓存
local mails_ = nil

---@type number  未读邮件数
local unreadCount_ = 0

---@type function|nil  邮件数据变化回调（UI 用）
local onChanged_ = nil

-- ============================================================================
-- 公开接口
-- ============================================================================

--- 注册数据变化回调
---@param fn function
function M.SetOnChanged(fn)
    onChanged_ = fn
end

--- 获取邮件列表
---@return table[]
function M.GetMails()
    return mails_ or {}
end

--- 获取未读邮件数
---@return number
function M.GetUnreadCount()
    return unreadCount_
end

--- 请求拉取未读邮件（发远程事件给服务端）
function M.RequestUnreadMails()
    if not IsNetworkMode() then return end
    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MAIL_FETCH, VariantMap())
end

--- 领取单封邮件
---@param mail table { message_id, value }
function M.ClaimMail(mail)
    if not mail or not mail.message_id then return end
    if not IsNetworkMode() then return end

    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["MessageId"] = Variant(tostring(mail.message_id))
    ClientNet.SendToServer(Shared.EVENTS.REQ_MAIL_CLAIM, data)
end

--- 领取全部邮件
function M.ClaimAll()
    local list = M.GetMails()
    for _, mail in ipairs(list) do
        M.ClaimMail(mail)
    end
end

-- ============================================================================
-- 服务端回调处理（由 client_net.lua 中转调用）
-- ============================================================================

--- 收到邮件列表
---@param eventData any
function M.OnMailData(eventData)
    local json = eventData["Data"]:GetString()
    local ok, messages = pcall(cjson.decode, json)
    if ok and type(messages) == "table" then
        mails_ = messages
        unreadCount_ = #messages
        print("[GameMail] 收到 " .. #messages .. " 封邮件")
    else
        mails_ = {}
        unreadCount_ = 0
        print("[GameMail] 邮件解析失败")
    end
    if onChanged_ then onChanged_() end
end

--- 收到邮件领取结果
---@param eventData any
function M.OnMailClaimed(eventData)
    local success   = eventData["Success"]:GetBool()
    local msgIdStr  = eventData["MessageId"]:GetString()
    local msg       = eventData["Msg"]:GetString()
    local msgId     = tonumber(msgIdStr) or 0

    if success then
        -- 从缓存找到对应邮件，提取附件
        local claimedMail = nil
        if mails_ then
            for i, m in ipairs(mails_) do
                if m.message_id == msgId then
                    claimedMail = m
                    table.remove(mails_, i)
                    break
                end
            end
        end
        unreadCount_ = math.max(0, (mails_ and #mails_) or 0)

        -- 将邮件附件加入玩家数据
        if claimedMail and claimedMail.value then
            local val = claimedMail.value
            if val.type == "trade_income" then
                -- 交易收入：加灵石到本地 clientCloud
                local income = val.income or 0
                if income > 0 then
                    GamePlayer.AddCurrency("lingStone", income)
                    GamePlayer.MarkDirty()
                    Toast.Show("领取 " .. income .. " 灵石", "success")
                    GamePlayer.AddLog("领取交易收入<c=gold>" .. income .. "灵石</c>（" .. (val.itemName or "") .. "）")
                end
            end
        else
            Toast.Show(msg, "success")
        end

        print("[GameMail] 领取成功 msgId=" .. msgIdStr)
    else
        Toast.Show(msg or "领取失败", "error")
        print("[GameMail] 领取失败 msgId=" .. msgIdStr .. " " .. tostring(msg))
    end

    if onChanged_ then onChanged_() end
end

return M
