------------------------------------------------------------
-- ui/page_server.lua  —— 三国神将录 区服选择模块
-- 职责：区服列表拉取/重试、开始界面区服显示、选服弹窗
-- 事件注册由 client_net.lua 统一管理，本模块通过回调接收
------------------------------------------------------------
local UI    = require("urhox-libs/UI")
local Theme = require("ui.theme")
local Comp  = require("ui.components")
local Modal = require("ui.modal_manager")
local C     = Theme.colors
local S     = Theme.sizes

local M = {}

------------------------------------------------------------
-- 状态
------------------------------------------------------------
local serverList_     = {}       -- 区服列表缓存
local selectedServer_ = nil      -- 当前选中 { id, name, status }
local initialized_    = false

-- UI 引用
local serverLabel_    = nil      -- 开始界面区服名标签
local statusDot_      = nil      -- 开始界面状态圆圈

-- 重试机制
local fetchRetryTimer_ = 0
local fetchRetryCount_ = 0
local FETCH_RETRY_INTERVAL = 2.0
local MAX_FETCH_RETRIES    = 10

-- 回调
local onServerReady_ = nil       ---@type fun()|nil 选服完成回调

-- 状态颜色
local STATUS_COLORS = {
    ["open"]   = { 76,  175, 80,  255 },   -- 绿
    ["hot"]    = { 255, 152, 0,   255 },   -- 橙
    ["maint"]  = { 244, 67,  54,  255 },   -- 红
}
local STATUS_NAMES = {
    ["open"]   = "正常",
    ["hot"]    = "火爆",
    ["maint"]  = "维护",
}

------------------------------------------------------------
-- 初始化
------------------------------------------------------------

function M.Init()
    if initialized_ then return end
    initialized_ = true
    fetchRetryCount_ = 0
    print("[ServerUI] Init - 区服模块就绪")
end

--- 区服列表是否已加载
---@return boolean
function M.IsLoaded()
    return #serverList_ > 0
end

--- 获取当前选中区服
---@return table|nil
function M.GetSelectedServer()
    return selectedServer_
end

--- 注册选服完成回调
---@param callback fun()
function M.OnServerReady(callback)
    onServerReady_ = callback
end

------------------------------------------------------------
-- 发送工具
------------------------------------------------------------

---@param eventName string
---@param data? VariantMap
---@return boolean
local function sendToServer(eventName, data)
    local ClientNet = require("network.client_net")
    return ClientNet.SendToServer(eventName, data)
end

--- 通知服务端选定区服
---@param serverId number
local function notifyServerSelect(serverId)
    local Shared = require("network.shared")
    local data = VariantMap()
    data["ServerId"] = Variant(serverId)
    sendToServer(Shared.EVENTS.SERVER_SELECT, data)
    print("[ServerUI] 通知服务端选服: sid=" .. serverId)
end

------------------------------------------------------------
-- 拉取区服列表
------------------------------------------------------------

function M.FetchServerList()
    local ClientNet = require("network.client_net")
    if not ClientNet.IsConnected() then return end

    local Shared = require("network.shared")
    sendToServer(Shared.EVENTS.SERVER_LIST_REQ)
    print("[ServerUI] 发送区服列表请求")
end

------------------------------------------------------------
-- 帧更新：重试拉取
------------------------------------------------------------

---@param dt number
function M.Update(dt)
    if not initialized_ then return end
    if #serverList_ > 0 then return end

    local ClientNet = require("network.client_net")
    if not ClientNet.IsConnected() then return end
    if fetchRetryCount_ >= MAX_FETCH_RETRIES then return end

    fetchRetryTimer_ = fetchRetryTimer_ + dt
    if fetchRetryTimer_ >= FETCH_RETRY_INTERVAL then
        fetchRetryTimer_ = 0
        fetchRetryCount_ = fetchRetryCount_ + 1
        print("[ServerUI] 重试拉取区服 ("
            .. fetchRetryCount_ .. "/" .. MAX_FETCH_RETRIES .. ")")
        M.FetchServerList()
    end
end

------------------------------------------------------------
-- 事件回调（由 client_net.lua 转发）
------------------------------------------------------------

--- 收到区服列表响应
---@param list table[]
function M.OnServerListResp(list)
    print("[ServerUI] 收到区服列表: " .. #list .. " 个")
    serverList_ = list

    -- 自动选择第一个可用区服
    if not selectedServer_ and #serverList_ > 0 then
        for _, srv in ipairs(serverList_) do
            if srv.status ~= "maint" then
                selectedServer_ = srv
                break
            end
        end
        if not selectedServer_ then
            selectedServer_ = serverList_[1]
        end
        -- 通知服务端
        if selectedServer_ then
            notifyServerSelect(selectedServer_.id)
        end
    end

    M.RefreshServerLabel()

    -- 通知开始界面可以进入
    if selectedServer_ and onServerReady_ then
        onServerReady_()
    end
end

------------------------------------------------------------
-- 开始界面区服显示
------------------------------------------------------------

--- 刷新开始界面区服标签
function M.RefreshServerLabel()
    if serverLabel_ then
        if selectedServer_ then
            local statusName = STATUS_NAMES[selectedServer_.status]
                or selectedServer_.status or ""
            serverLabel_.text = selectedServer_.name
        else
            serverLabel_.text = "加载中..."
        end
    end
    if statusDot_ then
        if selectedServer_ then
            local dotColor = STATUS_COLORS[selectedServer_.status]
                or { 76, 175, 80, 255 }
            statusDot_:SetStyle({ backgroundColor = dotColor })
            statusDot_:SetVisible(true)
        else
            statusDot_:SetVisible(false)
        end
    end
end

--- 在开始界面的区服插槽中嵌入区服控件
---@param slotPanel table 开始界面的区服容器
function M.SetupStartScreenSlot(slotPanel)
    if not slotPanel then return end

    statusDot_ = UI.Panel {
        width  = 8,
        height = 8,
        borderRadius = 4,
        backgroundColor = { 76, 175, 80, 255 },
    }
    statusDot_:SetVisible(false)

    serverLabel_ = UI.Label {
        text      = "加载中...",
        fontSize  = 13,
        fontColor = C.textDim,
    }

    local selectBtn = Comp.SanButton {
        text     = "切换",
        variant  = "secondary",
        height   = 26,
        fontSize = 10,
        paddingHorizontal = 12,
        borderRadius = 13,
        onClick = function()
            M.ShowServerSelectModal()
        end,
    }

    slotPanel:ClearChildren()
    slotPanel:AddChild(UI.Panel {
        flexDirection  = "row",
        alignItems     = "center",
        justifyContent = "center",
        gap            = 8,
        children = {
            statusDot_,
            serverLabel_,
            selectBtn,
        },
    })
end

------------------------------------------------------------
-- 区服选择弹窗
------------------------------------------------------------

function M.ShowServerSelectModal()
    local contentChildren = {}

    if #serverList_ == 0 then
        contentChildren[#contentChildren + 1] = UI.Label {
            text      = "暂无可用区服",
            fontSize  = Theme.fontSize.body,
            fontColor = C.textDim,
            textAlign = "center",
            width     = "100%",
            paddingVertical = 20,
        }
    else
        for _, srv in ipairs(serverList_) do
            local statusColor = STATUS_COLORS[srv.status]
                or { 76, 175, 80, 255 }
            local statusName = STATUS_NAMES[srv.status]
                or srv.status or ""
            local isSelected = selectedServer_
                and selectedServer_.id == srv.id
            local canJoin = (srv.status ~= "maint")

            local bgColor = isSelected
                and { 40, 55, 70, 255 }
                or  C.panelLight

            local btnText = isSelected and "当前"
                or (canJoin and "选择" or "维护中")
            local btnVariant = isSelected and "primary"
                or (canJoin and "secondary" or "secondary")

            contentChildren[#contentChildren + 1] = UI.Panel {
                flexDirection  = "row",
                alignItems     = "center",
                width          = "100%",
                padding        = 10,
                borderRadius   = 6,
                backgroundColor = bgColor,
                borderWidth    = isSelected and 1 or 0,
                borderColor    = C.jade,
                gap            = 8,
                marginBottom   = 4,
                children = {
                    -- 状态圆圈
                    UI.Panel {
                        width  = 8,
                        height = 8,
                        borderRadius = 4,
                        backgroundColor = statusColor,
                    },
                    -- 区服名
                    UI.Label {
                        text       = srv.name,
                        fontSize   = Theme.fontSize.body,
                        fontColor  = C.text,
                        fontWeight = "bold",
                        flexGrow   = 1,
                    },
                    -- 状态文字
                    UI.Label {
                        text      = statusName,
                        fontSize  = Theme.fontSize.caption,
                        fontColor = statusColor,
                    },
                    -- 选择按钮
                    Comp.SanButton {
                        text     = btnText,
                        variant  = btnVariant,
                        height   = 28,
                        fontSize = 10,
                        paddingHorizontal = 10,
                        disabled = isSelected or not canJoin,
                        onClick = function()
                            if not canJoin then
                                Modal.Alert("提示", "该区服正在维护")
                                return
                            end
                            selectedServer_ = srv
                            notifyServerSelect(srv.id)
                            M.RefreshServerLabel()
                            Modal.Close()
                            -- 触发选服完成回调
                            if onServerReady_ then
                                onServerReady_()
                            end
                        end,
                    },
                },
            }
        end
    end

    Modal.Show({
        title   = "选择区服",
        width   = 400,
        content = function()
            return UI.Panel {
                width     = "100%",
                maxHeight = 300,
                overflow  = "scroll",
                gap       = 2,
                children  = contentChildren,
            }
        end,
        buttons = {},
    })
end

------------------------------------------------------------
-- 重置（换服/断线后）
------------------------------------------------------------

function M.ResetSelection()
    selectedServer_ = nil
    fetchRetryCount_ = 0
    fetchRetryTimer_ = 0
    serverList_ = {}
    M.RefreshServerLabel()
end

--- 获取当前选中区服的名称
---@return string
function M.GetSelectedName()
    if selectedServer_ then
        return selectedServer_.name or ""
    end
    return ""
end

--- 获取当前选中区服的状态
---@return string
function M.GetSelectedStatus()
    if selectedServer_ then
        return selectedServer_.status or "open"
    end
    return "open"
end

return M
