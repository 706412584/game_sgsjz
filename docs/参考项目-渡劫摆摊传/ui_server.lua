-- ============================================================================
-- ui_server.lua — 区服选择客户端
-- 开始界面区服显示 + GM区服管理弹窗
-- 事件注册由 client_net.lua 统一管理，本模块通过回调接收数据
-- ============================================================================
---@diagnostic disable: undefined-global
local UI = require("urhox-libs/UI")
local Config = require("data_config")

local M = {}

-- 区服数据缓存
local serverList_ = {}
local selectedServer_ = nil   -- { id, name, status }

-- UI 引用
local serverLabel_ = nil      -- 开始界面区服显示标签
local statusDot_   = nil      -- 开始界面状态圆圈
local gmListPanel_ = nil      -- GM 管理面板列表容器

-- 重试机制
local fetchRetryTimer_ = 0
local fetchRetryCount_ = 0
local FETCH_RETRY_INTERVAL = 2.0  -- 每2秒重试一次
local MAX_FETCH_RETRIES = 10      -- 最多重试10次
local fetchPending_ = false       -- 是否正在等待响应
local initialized_ = false

-- 状态颜色
local STATUS_COLORS = {
    ["正常"] = Config.Colors.textGreen,
    ["火爆"] = Config.Colors.orange,
    ["维护"] = Config.Colors.red,
}

-- ========== 初始化 ==========

--- Init 不再注册事件，事件由 client_net.lua 统一管理
--- 只负责启动区服拉取的重试循环
function M.Init()
    if initialized_ then return end
    initialized_ = true
    fetchRetryCount_ = 0
    fetchPending_ = false
    print("[ServerUI] Init() — 区服模块就绪，等待连接后拉取列表")
end

--- 区服列表是否已加载
function M.IsLoaded()
    return #serverList_ > 0
end

-- ========== 发送工具 ==========

---@param eventName string
---@param data? VariantMap
---@return boolean
local function sendToServer(eventName, data)
    local ClientNet = require("network.client_net")
    return ClientNet.SendToServer(eventName, data)
end

--- 通知服务端当前选定的区服
---@param serverId number
local function notifyServerSelect(serverId)
    local Shared = require("network.shared")
    local data = VariantMap()
    data["ServerId"] = Variant(serverId)
    sendToServer(Shared.EVENTS.SERVER_SELECT, data)
    print("[ServerUI] 通知服务端选定区服: serverId=" .. serverId)
end

-- ========== 请求区服列表 ==========

function M.FetchServerList()
    local ClientNet = require("network.client_net")
    if not ClientNet.IsConnected() then
        print("[ServerUI] FetchServerList() — 未连接，跳过")
        return
    end

    local Shared = require("network.shared")
    local ok = sendToServer(Shared.EVENTS.SERVER_LIST_REQ)
    print("[ServerUI] FetchServerList() — 发送请求 result=" .. tostring(ok))

    if ok then
        fetchPending_ = true
        fetchRetryTimer_ = 0
    end
end

-- ========== 帧更新：重试拉取 ==========

--- 由 main.lua 的 HandleUpdate 调用
---@param dt number
function M.Update(dt)
    if not initialized_ then return end

    -- 已有数据或非网络模式，不需要重试
    if #serverList_ > 0 then return end
    if not (IsNetworkMode and IsNetworkMode()) then return end

    local ClientNet = require("network.client_net")
    if not ClientNet.IsConnected() then return end

    -- 超过最大重试次数，停止
    if fetchRetryCount_ >= MAX_FETCH_RETRIES then return end

    fetchRetryTimer_ = fetchRetryTimer_ + dt
    if fetchRetryTimer_ >= FETCH_RETRY_INTERVAL then
        fetchRetryTimer_ = 0
        fetchRetryCount_ = fetchRetryCount_ + 1
        print("[ServerUI] 自动重试拉取区服列表 (" .. fetchRetryCount_ .. "/" .. MAX_FETCH_RETRIES .. ")")
        M.FetchServerList()
    end
end

-- ========== 事件回调（由 client_net.lua 转发） ==========

--- 收到区服列表响应
---@param eventData any
function M.OnServerListResp(eventData)
    local jsonStr = eventData["ServerJson"]:GetString()
    local count   = eventData["Count"]:GetInt()

    print("[ServerUI] 收到区服列表! count=" .. count)

    local ok, list = pcall(cjson.decode, jsonStr)
    if ok and type(list) == "table" then
        serverList_ = list
    else
        serverList_ = {}
    end

    fetchPending_ = false

    -- 自动选择第一个正常区服
    if not selectedServer_ and #serverList_ > 0 then
        for _, srv in ipairs(serverList_) do
            if srv.status == "正常" or srv.status == "火爆" then
                selectedServer_ = srv
                break
            end
        end
        if not selectedServer_ then
            selectedServer_ = serverList_[1]
        end
        -- 通知服务端自动选定的区服
        if selectedServer_ then
            notifyServerSelect(selectedServer_.id)
        end
    end

    M.RefreshServerLabel()

    -- 刷新 GM 管理面板
    if gmListPanel_ then
        M.RenderGMServerList()
    end

    -- 通知 main.lua 尝试关闭加载遮罩
    if TryDismissLoading then
        TryDismissLoading()
    end
end

--- 收到区服操作结果
---@param eventData any
function M.OnServerOpResult(eventData)
    local action  = eventData["Action"]:GetString()
    local success = eventData["Success"]:GetBool()
    local message = eventData["Message"]:GetString()

    print("[ServerUI] Op result: " .. action .. " " .. tostring(success) .. " " .. message)

    if success then
        UI.Toast.Show(message, { variant = "success", duration = 2 })
        -- 刷新列表
        M.FetchServerList()
    else
        UI.Toast.Show("失败: " .. message, { variant = "error", duration = 3 })
    end
end

-- ========== 开始界面区服显示 ==========

--- 获取当前选中的区服
---@return table|nil
function M.GetSelectedServer()
    return selectedServer_
end

--- 获取区服列表(供GM面板使用)
---@return table[]
function M.GetServerList()
    return serverList_
end

--- 刷新开始界面区服标签 + 状态圆圈
function M.RefreshServerLabel()
    if serverLabel_ then
        if selectedServer_ then
            serverLabel_:SetText(selectedServer_.name)
            serverLabel_:SetStyle({ fontColor = { 200, 195, 220, 230 } })
        else
            serverLabel_:SetText("未选择区服")
        end
    end
    -- 刷新状态圆圈颜色
    if statusDot_ then
        if selectedServer_ then
            local c = STATUS_COLORS[selectedServer_.status] or Config.Colors.textPrimary
            statusDot_:SetStyle({ backgroundColor = c })
            statusDot_:Show()
        else
            statusDot_:Hide()
        end
    end
end

--- 创建开始界面区服选择按钮(嵌入 ui_start.lua 的 serverSlot)
---@param slotPanel table 开始界面的区服位置容器
function M.SetupStartScreenSlot(slotPanel)
    if not slotPanel then return end

    -- 状态圆圈（绿=正常 橙=火爆 红=维护）
    statusDot_ = UI.Panel {
        width = 8,
        height = 8,
        borderRadius = 4,
        backgroundColor = Config.Colors.textGreen,
    }
    -- 初始隐藏，等区服数据加载后由 RefreshServerLabel 显示
    statusDot_:Hide()

    serverLabel_ = UI.Label {
        text = "加载区服中...",
        fontSize = 13,
        fontColor = { 210, 205, 190, 230 },
    }

    local selectBtn = UI.Button {
        text = "切换",
        fontSize = 10,
        width = 56,
        height = 26,
        backgroundColor = { 60, 70, 60, 180 },
        textColor = { 210, 200, 170, 255 },
        borderRadius = 13,
        borderWidth = 1,
        borderColor = { 160, 145, 100, 120 },
        onClick = function(self)
            M.ShowServerSelectModal()
        end,
    }

    slotPanel:ClearChildren()
    slotPanel:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        gap = 8,
        children = {
            statusDot_,
            serverLabel_,
            selectBtn,
        },
    })
end

-- ========== 区服选择弹窗(玩家用) ==========

function M.ShowServerSelectModal()
    local modal = UI.Modal {
        title = "选择区服",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    local listPanel = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 6,
    }

    if #serverList_ == 0 then
        listPanel:AddChild(UI.Label {
            text = "暂无可用区服",
            fontSize = 11,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 20,
        })
    else
        for _, srv in ipairs(serverList_) do
            local statusColor = STATUS_COLORS[srv.status] or Config.Colors.textPrimary
            local isSelected = selectedServer_ and selectedServer_.id == srv.id
            local bgColor = isSelected
                and { 40, 65, 50, 255 }
                or Config.Colors.panelLight
            local canJoin = (srv.status ~= "维护")

            listPanel:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                padding = 8,
                borderRadius = 6,
                backgroundColor = bgColor,
                borderWidth = isSelected and 1 or 0,
                borderColor = Config.Colors.jade,
                gap = 6,
                children = {
                    -- 状态圆圈
                    UI.Panel {
                        width = 8,
                        height = 8,
                        borderRadius = 4,
                        backgroundColor = statusColor,
                    },
                    UI.Label {
                        text = srv.name,
                        fontSize = 12,
                        fontColor = Config.Colors.textPrimary,
                        fontWeight = "bold",
                        flexGrow = 1,
                    },
                    UI.Button {
                        text = isSelected and "当前" or (canJoin and "选择" or "维护中"),
                        fontSize = 9,
                        width = 52,
                        height = 24,
                        backgroundColor = isSelected and Config.Colors.jade
                            or (canJoin and Config.Colors.jadeDark or { 60, 60, 60, 255 }),
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            if not canJoin then
                                UI.Toast.Show("该区服正在维护", { variant = "error", duration = 2 })
                                return
                            end
                            selectedServer_ = srv
                            notifyServerSelect(srv.id)
                            M.RefreshServerLabel()
                            modal:Close()
                            UI.Toast.Show("已选择: " .. srv.name, { variant = "success", duration = 2 })
                        end,
                    },
                },
            })
        end
    end

    modal:AddContent(listPanel)
    modal:Open()
end

-- ========== GM 区服管理弹窗（分页） ==========

local GM_PAGE_SIZE = 2     -- 每页显示区服数（卡片含3行按钮，2个卡片适配md弹窗高度）
local gmCurrentPage_ = 1   -- 当前页码
local gmPageLabel_ = nil   -- 页码标签

function M.ShowGMServerModal()
    local Shared = require("network.shared")
    gmCurrentPage_ = 1

    local modal = UI.Modal {
        title = "区服管理 (GM)",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self)
            gmListPanel_ = nil
            gmPageLabel_ = nil
            self:Destroy()
        end,
    }

    -- 添加区服（输入框+按钮同行，节省纵向空间）
    local nameInput = UI.TextField {
        placeholder = "新区名",
        fontSize = 10,
        flexGrow = 1,
        height = 26,
    }

    local addRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        gap = 4,
        children = {
            nameInput,
            UI.Button {
                text = "添加",
                fontSize = 10,
                width = 50,
                height = 26,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 4,
                onClick = function(self)
                    local name = nameInput:GetText()
                    if name == "" then
                        UI.Toast.Show("请输入区服名称", { variant = "error", duration = 2 })
                        return
                    end
                    local data = VariantMap()
                    data["Name"] = Variant(name)
                    sendToServer(Shared.EVENTS.SERVER_ADD, data)
                end,
            },
        },
    }

    -- 区服列表容器
    gmListPanel_ = UI.Panel {
        width = "100%",
        gap = 4,
    }

    -- 分页导航（紧凑行）
    gmPageLabel_ = UI.Label {
        text = "1/1",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
    }

    local pageNav = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        justifyContent = "center",
        width = "100%",
        gap = 8,
        children = {
            UI.Button {
                text = "<",
                fontSize = 9,
                width = 30,
                height = 22,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textPrimary,
                borderRadius = 4,
                onClick = function(self)
                    if gmCurrentPage_ > 1 then
                        gmCurrentPage_ = gmCurrentPage_ - 1
                        M.RenderGMServerList()
                    end
                end,
            },
            gmPageLabel_,
            UI.Button {
                text = ">",
                fontSize = 9,
                width = 30,
                height = 22,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textPrimary,
                borderRadius = 4,
                onClick = function(self)
                    local totalPages = math.max(1, math.ceil(#serverList_ / GM_PAGE_SIZE))
                    if gmCurrentPage_ < totalPages then
                        gmCurrentPage_ = gmCurrentPage_ + 1
                        M.RenderGMServerList()
                    end
                end,
            },
        },
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        padding = 6,
        gap = 4,
        children = {
            addRow,
            gmListPanel_,
            pageNav,
        },
    })

    modal:Open()

    -- 刷新列表
    M.RenderGMServerList()
    M.FetchServerList()
end

--- 渲染 GM 区服管理列表（分页，纵向卡片布局）
function M.RenderGMServerList()
    local Shared = require("network.shared")

    if not gmListPanel_ then return end
    gmListPanel_:ClearChildren()

    local total = #serverList_
    local totalPages = math.max(1, math.ceil(total / GM_PAGE_SIZE))

    -- 修正当前页
    if gmCurrentPage_ > totalPages then gmCurrentPage_ = totalPages end
    if gmCurrentPage_ < 1 then gmCurrentPage_ = 1 end

    -- 更新页码标签
    if gmPageLabel_ then
        gmPageLabel_:SetText(gmCurrentPage_ .. "/" .. totalPages)
    end

    if total == 0 then
        gmListPanel_:AddChild(UI.Label {
            text = "暂无区服",
            fontSize = 11,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 12,
        })
        return
    end

    local STATUS_OPTIONS = { "正常", "火爆", "维护" }
    local startIdx = (gmCurrentPage_ - 1) * GM_PAGE_SIZE + 1
    local endIdx = math.min(startIdx + GM_PAGE_SIZE - 1, total)

    for i = startIdx, endIdx do
        local srv = serverList_[i]
        if not srv then break end
        local statusColor = STATUS_COLORS[srv.status] or Config.Colors.textPrimary

        -- 状态切换按钮（横向排列）
        local statusBtns = {}
        for _, st in ipairs(STATUS_OPTIONS) do
            table.insert(statusBtns, UI.Button {
                text = st,
                fontSize = 8,
                flexGrow = 1,
                height = 20,
                backgroundColor = (srv.status == st)
                    and Config.Colors.jadeDark
                    or Config.Colors.panelLight,
                textColor = (srv.status == st)
                    and { 255, 255, 255, 255 }
                    or Config.Colors.textSecond,
                borderRadius = 3,
                onClick = function(self)
                    local data = VariantMap()
                    data["ServerId"] = Variant(srv.id)
                    data["Status"]   = Variant(st)
                    sendToServer(Shared.EVENTS.SERVER_UPDATE, data)
                end,
            })
        end

        -- 紧凑卡片：名称+操作按钮
        gmListPanel_:AddChild(UI.Panel {
            width = "100%",
            padding = 6,
            gap = 3,
            borderRadius = 4,
            backgroundColor = Config.Colors.panelLight,
            borderWidth = 1,
            borderColor = Config.Colors.border,
            children = {
                -- 第一行：名称 + 状态 + 删除
                UI.Panel {
                    flexDirection = "row",
                    alignItems = "center",
                    width = "100%",
                    children = {
                        UI.Label {
                            text = srv.name,
                            fontSize = 10,
                            fontColor = Config.Colors.textPrimary,
                            fontWeight = "bold",
                            flexGrow = 1,
                        },
                        UI.Label {
                            text = "S" .. srv.id .. " " .. srv.status,
                            fontSize = 8,
                            fontColor = statusColor,
                            marginRight = 4,
                        },
                        UI.Button {
                            text = "删",
                            fontSize = 8,
                            width = 26,
                            height = 18,
                            backgroundColor = { 80, 30, 30, 255 },
                            textColor = Config.Colors.red,
                            borderRadius = 3,
                            onClick = function(self)
                                local data = VariantMap()
                                data["ServerId"] = Variant(srv.id)
                                sendToServer(Shared.EVENTS.SERVER_REMOVE, data)
                            end,
                        },
                    },
                },
                -- 第二行：状态切换按钮
                UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    gap = 3,
                    children = statusBtns,
                },
                -- 第三行：GM 操作按钮
                UI.Panel {
                    flexDirection = "row",
                    width = "100%",
                    gap = 3,
                    children = {
                        UI.Button {
                            text = "重置",
                            fontSize = 8,
                            flexGrow = 1,
                            height = 20,
                            backgroundColor = { 60, 50, 30, 255 },
                            textColor = Config.Colors.orange or { 220, 160, 60, 255 },
                            borderRadius = 3,
                            onClick = function(self)
                                UI.Modal.Confirm({
                                    title = "重置区服数据",
                                    message = "确定重置「" .. srv.name .. "」(S" .. srv.id .. ")的玩家数据?\n(保留角色名和转世记录)",
                                    confirmText = "确认",
                                    cancelText = "取消",
                                    onConfirm = function()
                                        local GameCore = require("game_core")
                                        GameCore.SendGameAction("gm_reset", { sid = srv.id })
                                        UI.Toast.Show("S" .. srv.id .. " 重置请求已发送", { variant = "success", duration = 2 })
                                    end,
                                })
                            end,
                        },
                        UI.Button {
                            text = "清榜",
                            fontSize = 8,
                            flexGrow = 1,
                            height = 20,
                            backgroundColor = { 40, 40, 60, 255 },
                            textColor = { 150, 150, 220, 255 },
                            borderRadius = 3,
                            onClick = function(self)
                                UI.Modal.Confirm({
                                    title = "清空排行榜",
                                    message = "确定清空「" .. srv.name .. "」(S" .. srv.id .. ")的排行榜数据?",
                                    confirmText = "确认",
                                    cancelText = "取消",
                                    onConfirm = function()
                                        local GameCore = require("game_core")
                                        GameCore.SendGameAction("gm_reset_rank", { sid = srv.id })
                                        UI.Toast.Show("S" .. srv.id .. " 排行清空请求已发送", { variant = "success", duration = 2 })
                                    end,
                                })
                            end,
                        },
                        UI.Button {
                            text = "删服",
                            fontSize = 8,
                            flexGrow = 1,
                            height = 20,
                            backgroundColor = { 80, 30, 30, 255 },
                            textColor = { 220, 100, 100, 255 },
                            borderRadius = 3,
                            onClick = function(self)
                                UI.Modal.Confirm({
                                    title = "删除服务端数据",
                                    message = "确定删除「" .. srv.name .. "」(S" .. srv.id .. ")的全部服务端数据?\n(聊天/缓存等，操作不可恢复!)",
                                    confirmText = "确认删除",
                                    cancelText = "取消",
                                    onConfirm = function()
                                        local GameCore = require("game_core")
                                        GameCore.SendGameAction("gm_delete_server", { sid = srv.id })
                                        UI.Toast.Show("S" .. srv.id .. " 删除请求已发送", { variant = "warning", duration = 3 })
                                    end,
                                })
                            end,
                        },
                    },
                },
            },
        })
    end
end

-- ========== 维护踢人通知（由 client_net.lua 转发） ==========

--- 收到区服维护踢人通知
--- 如果当前选中的区服匹配，弹窗提示并走 kicked 流程返回开始界面
---@param eventData any
function M.OnMaintenanceKick(eventData)
    local serverId   = eventData["ServerId"]:GetInt()
    local serverName = eventData["ServerName"]:GetString()

    print("[ServerUI] 维护踢人通知: serverId=" .. serverId .. " name=" .. serverName)

    -- 更新本地缓存中的区服状态
    for _, srv in ipairs(serverList_) do
        if srv.id == serverId then
            srv.status = "维护"
            break
        end
    end

    -- 判断当前选中的区服是否匹配
    if selectedServer_ and selectedServer_.id == serverId then
        -- 当前选中的区服被设为维护 → 弹窗 + 走 kicked 流程
        selectedServer_.status = "维护"
        M.RefreshServerLabel()

        -- 触发 kicked 回调（复用 main.lua 已有的被踢弹窗机制）
        local ClientNet = require("network.client_net")
        -- 不直接调 kickedCallback_（它是 client_net 的私有变量），
        -- 而是通过 HandleKicked 模拟一个被踢事件
        -- 但 HandleKicked 会设置 kicked_=true 导致不能重连
        -- 所以这里直接弹一个独立的弹窗，并显示开始界面让用户重选区服

        local modal = UI.Modal {
            title = "区服维护",
            size = "sm",
            closeOnOverlay = false,
            closeOnEscape = false,
            showCloseButton = false,
            onClose = function(self) self:Destroy() end,
        }
        modal:AddContent(UI.Panel {
            width = "100%",
            alignItems = "center",
            padding = 16,
            gap = 10,
            children = {
                UI.Label {
                    text = "你所在的区服【" .. serverName .. "】已进入维护",
                    fontSize = 12,
                    fontColor = Config.Colors.textPrimary,
                    textAlign = "center",
                },
                UI.Label {
                    text = "请选择其他区服继续游戏",
                    fontSize = 10,
                    fontColor = Config.Colors.textSecond,
                    textAlign = "center",
                },
            },
        })
        modal:SetFooter(UI.Panel {
            width = "100%",
            alignItems = "center",
            children = {
                UI.Button {
                    text = "返回选服",
                    fontSize = 12,
                    width = 100,
                    height = 34,
                    backgroundColor = Config.Colors.jadeDark,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 8,
                    onClick = function(self)
                        modal:Close()
                        -- 清除选中区服，回到开始界面让用户重选
                        selectedServer_ = nil
                        M.RefreshServerLabel()
                        -- 显示开始界面
                        local StartScreen = require("ui_start")
                        StartScreen.Show()
                    end,
                },
            },
        })
        modal:Open()
    else
        -- 不是当前区服，仅刷新 UI 标签
        M.RefreshServerLabel()
        if gmListPanel_ then
            M.RenderGMServerList()
        end
    end
end

return M
