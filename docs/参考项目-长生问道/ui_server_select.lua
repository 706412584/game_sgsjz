-- ============================================================================
-- 《问道长生》选服弹窗
-- 全屏遮罩 + 居中面板，展示服务器列表（含在线人数 + 状态标签）
-- 使用与 ui_settings.lua 相同的 Overlay 模式
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local DataServers = require("data_servers")
local GameServer = require("game_server")

local M = {}

-- 弹窗状态
local isVisible_ = false
local activeOverlay_ = nil
local selectedServerId_ = nil   -- 临时选中（确认前）
local onConfirm_ = nil          -- 确认回调
local onClose_ = nil            -- 关闭回调

-- 在线人数缓存 { [serverId] = count }
local onlineData_ = {}
local onlineLoading_ = false

-- ============================================================================
-- 在线人数查询（通过远程事件）
-- ============================================================================

--- 请求服务端返回各区服在线人数
local function QueryOnlineData()
    if not IsNetworkMode() then return end
    local ClientNet = require("network.client_net")
    if not ClientNet.IsConnected() then return end

    onlineLoading_ = true
    local data = VariantMap()
    data["Action"] = Variant("query")
    ClientNet.SendToServer("ReqServerOnline", data)
end

--- 处理服务端返回的在线人数数据
---@param eventData any
function M.OnServerOnlineData(eventData)
    onlineLoading_ = false
    local jsonStr = eventData["Data"] and eventData["Data"]:GetString() or "{}"
    ---@diagnostic disable-next-line: undefined-global
    local ok, decoded = pcall(cjson.decode, jsonStr)
    if ok and type(decoded) == "table" then
        -- join 结果（用于测试服白名单拦截提示）
        if decoded._type == "join" then
            if not decoded.ok then
                local Toast = require("ui_toast")
                local Router = require("ui_router")
                -- 仅在标题页/选服流程中才跳转标题页，避免重连后误跳转
                local st = Router.GetCurrentState()
                if st == Router.STATE_TITLE or M.IsVisible() then
                    Toast.Show(decoded.msg or "无法进入该服务器", { variant = "error" })
                    Router.EnterState(Router.STATE_TITLE)
                else
                    print("[ServerSelect] 收到 join 失败但当前不在标题/选服页，忽略: " .. tostring(decoded.msg))
                end
            end
            return
        end

        -- cjson 的 key 是字符串，转为数字
        onlineData_ = {}
        for k, v in pairs(decoded) do
            onlineData_[tonumber(k) or k] = tonumber(v) or 0
        end
    end
    -- 刷新 UI
    RebuildContent()
end

-- ============================================================================
-- 服务器列表项构建
-- ============================================================================
local function BuildServerRow(server, isSelected, onSelect)
    local isOpen = DataServers.IsSelectable(server)
    local isMerged = (server.status == DataServers.STATUS_MERGED)
    local isMaintain = (server.status == DataServers.STATUS_MAINTAIN)

    -- 在线人数（open 状态默认为 0，确保始终显示动态标签）
    local onlineCount = onlineData_[server.id]
    if isOpen and onlineCount == nil then
        onlineCount = 0
    end

    -- 标签颜色
    local tagText, tagColor, tagBg
    if server.isTest then
        -- 测试服：紫色标签，醒目区分
        tagText = "DEV"
        tagColor = { 200, 140, 255, 255 }
        tagBg = { 160, 100, 230, 80 }
    elseif isMaintain then
        tagText = DataServers.TAG_MAINTAIN
        tagColor = { 140, 130, 110, 200 }
        tagBg = { 140, 130, 110, 30 }
    elseif isOpen then
        -- open 状态始终显示动态状态标签（畅通/良好/繁忙/爆满）
        tagText, tagColor, tagBg = DataServers.GetStatusByOnline(onlineCount)
    else
        tagText = server.tag or ""
        tagColor = { 140, 130, 110, 200 }
        tagBg = { 140, 130, 110, 30 }
    end

    -- 行样式
    local rowBg = isSelected and { 60, 50, 35, 200 } or { 40, 35, 28, 150 }
    local borderColor = isSelected and Theme.colors.gold or Theme.colors.border
    local nameColor = isOpen and Theme.colors.textLight or { 100, 95, 85, 180 }

    -- 在线人数文本
    local onlineLabel = nil
    if isOpen and onlineCount then
        onlineLabel = UI.Label {
            text = tostring(onlineCount) .. "人在线",
            fontSize = Theme.fontSize.tiny,
            fontColor = { 160, 155, 140, 180 },
            marginRight = 8,
        }
    elseif isOpen and onlineLoading_ then
        onlineLabel = UI.Label {
            text = "...",
            fontSize = Theme.fontSize.tiny,
            fontColor = { 120, 115, 105, 140 },
            marginRight = 8,
        }
    end

    -- 动态构建 children（避免 nil 空洞导致 ipairs 提前终止）
    local rowChildren = {}

    -- 选中指示条
    if isSelected then
        table.insert(rowChildren, UI.Panel {
            width = 4, height = 24,
            borderRadius = 2,
            backgroundColor = Theme.colors.gold,
            marginRight = 10,
        })
    else
        table.insert(rowChildren, UI.Panel { width = 14 })
    end

    -- 服务器名
    table.insert(rowChildren, UI.Label {
        text = server.name,
        fontSize = Theme.fontSize.subtitle,
        fontWeight = isSelected and "bold" or "normal",
        fontColor = nameColor,
        flexGrow = 1,
    })

    -- 合服提示（仅合服时显示）
    if isMerged then
        table.insert(rowChildren, UI.Label {
            text = "已合服至" .. (server.mergedTo or ""),
            fontSize = Theme.fontSize.tiny,
            fontColor = { 160, 140, 100, 180 },
            marginRight = 8,
        })
    end

    -- 在线人数
    if onlineLabel then
        table.insert(rowChildren, onlineLabel)
    end

    -- 状态标签
    if tagText and tagText ~= "" then
        table.insert(rowChildren, UI.Panel {
            paddingLeft = 8, paddingRight = 8,
            paddingTop = 3, paddingBottom = 3,
            borderRadius = 4,
            backgroundColor = tagBg,
            children = {
                UI.Label {
                    text = tagText,
                    fontSize = Theme.fontSize.tiny,
                    fontColor = tagColor,
                },
            },
        })
    end

    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        height = 52,
        paddingLeft = 14,
        paddingRight = 14,
        borderRadius = Theme.radius.md,
        backgroundColor = rowBg,
        borderColor = borderColor,
        borderWidth = isSelected and 1 or 0,
        cursor = isOpen and "pointer" or "default",
        onClick = function(self)
            if isOpen and onSelect then onSelect(server.id) end
        end,
        children = rowChildren,
    }
end

-- ============================================================================
-- 内部重建弹窗内容
-- ============================================================================
function RebuildContent()
    if not isVisible_ or not activeOverlay_ then return end
    activeOverlay_:ClearChildren()
    activeOverlay_:AddChild(M.Build())
end

-- ============================================================================
-- 构建弹窗 UI
-- ============================================================================
function M.Build()
    local servers = DataServers.GetVisibleServers(GameServer.IsDebugEnv())
    local current = GameServer.GetCurrentServer()
    if not selectedServerId_ then
        selectedServerId_ = current.id
    end

    -- 服务器列表项
    local serverItems = {}
    for i, server in ipairs(servers) do
        serverItems[i] = BuildServerRow(server, server.id == selectedServerId_, function(id)
            selectedServerId_ = id
            RebuildContent()
        end)
    end

    -- 已选服务器名
    local selServer = DataServers.GetServer(selectedServerId_)
    local selName = selServer and selServer.name or "未选择"

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            M.Hide()
            if onClose_ then onClose_() end
        end,
        children = {
            -- 弹窗面板
            UI.Panel {
                width = "85%",
                maxWidth = 360,
                backgroundColor = { 35, 30, 24, 245 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = 12,
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        children = {
                            UI.Label {
                                text = "选择服务器",
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Panel {
                                width = 32, height = 32, borderRadius = 16,
                                backgroundColor = { 60, 55, 45, 200 },
                                justifyContent = "center",
                                alignItems = "center",
                                cursor = "pointer",
                                onClick = function(self)
                                    M.Hide()
                                    if onClose_ then onClose_() end
                                end,
                                children = {
                                    UI.Label {
                                        text = "X",
                                        fontSize = 16,
                                        fontColor = Theme.colors.textLight,
                                    },
                                },
                            },
                        },
                    },

                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = Theme.colors.divider,
                        spacing = 2,
                    },

                    -- 服务器列表
                    UI.Panel {
                        width = "100%",
                        gap = 6,
                        children = serverItems,
                    },

                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = { 60, 55, 45, 80 },
                        spacing = 2,
                    },

                    -- 底部：已选 + 确认按钮
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        gap = 10,
                        children = {
                            UI.Label {
                                text = "已选: " .. selName,
                                fontSize = Theme.fontSize.body,
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Panel {
                                width = "80%",
                                height = 42,
                                borderRadius = Theme.radius.md,
                                backgroundColor = Theme.colors.gold,
                                borderColor = Theme.colors.goldDark,
                                borderWidth = 1,
                                justifyContent = "center",
                                alignItems = "center",
                                cursor = "pointer",
                                onClick = function(self)
                                    local server = DataServers.GetServer(selectedServerId_)
                                    if server and DataServers.IsSelectable(server) then
                                        GameServer.SetCurrentServer(server)
                                        M.Hide()
                                        if onConfirm_ then onConfirm_(server) end
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = "确认选择",
                                        fontSize = Theme.fontSize.subtitle,
                                        fontWeight = "bold",
                                        fontColor = Theme.colors.btnPrimaryText,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- Overlay 管理（与 ui_settings 同模式）
-- ============================================================================

function M.BindOverlay(overlay)
    activeOverlay_ = overlay
end

--- 显示选服弹窗
---@param onConfirm function|nil 确认回调 function(server)
---@param onClose function|nil   关闭回调
function M.Show(onConfirm, onClose)
    isVisible_ = true
    selectedServerId_ = GameServer.GetCurrentServer().id
    onConfirm_ = onConfirm
    onClose_ = onClose

    -- 请求在线人数数据
    QueryOnlineData()

    if activeOverlay_ then
        activeOverlay_:SetStyle({ pointerEvents = "auto" })
        activeOverlay_:ClearChildren()
        activeOverlay_:AddChild(M.Build())
    end
end

function M.Hide()
    isVisible_ = false
    selectedServerId_ = nil
    if activeOverlay_ then
        activeOverlay_:SetStyle({ pointerEvents = "none" })
        activeOverlay_:ClearChildren()
    end
end

function M.IsVisible()
    return isVisible_
end

--- 获取缓存的在线数据（供 ui_title 使用）
---@return table { [serverId] = count }
function M.GetOnlineData()
    return onlineData_
end

return M
