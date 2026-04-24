-- ============================================================================
-- 《问道长生》区服管理器
-- 负责：选区记忆、数据隔离 key 前缀生成
-- ============================================================================

local DataServers = require("data_servers")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")

local M = {}

-- 当前选中的服务器
---@type table|nil
local currentServer_ = nil

-- 本地存储文件名
local SAVE_FILE = "server_select.dat"

-- ============================================================================
-- 初始化（读取本地记忆的选区，或使用默认）
-- ============================================================================
--- 判断是否为调试环境（Web 平台 = 预览调试）
---@return boolean
function M.IsDebugEnv()
    return PlatformUtils.IsWebPlatform()
end

function M.Init()
    -- 调试环境默认选测试服，正式环境选默认服
    local serverId
    if M.IsDebugEnv() then
        serverId = DataServers.TEST_SERVER_ID
        print("[GameServer] 调试环境，默认测试服 id=" .. tostring(serverId))
    else
        serverId = DataServers.DEFAULT_SERVER_ID
    end

    -- 尝试从本地文件读取上次选择
    ---@diagnostic disable-next-line: undefined-global
    local ok = pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        if fileSystem:FileExists(SAVE_FILE) then
            ---@diagnostic disable-next-line: undefined-global
            local file = File(SAVE_FILE, FILE_READ)
            if file then
                local content = file:ReadString()
                file:Close()
                local id = tonumber(content)
                if id then
                    local saved = DataServers.GetServer(id)
                    if saved and DataServers.IsSelectable(saved) then
                        serverId = id
                    end
                end
            end
        end
    end)

    if not ok then
        print("[GameServer] 本地存储读取失败，使用默认服务器")
    end

    currentServer_ = DataServers.GetServer(serverId) or DataServers.GetDefaultServer()
    print("[GameServer] 当前服务器:", currentServer_.name)
end

-- ============================================================================
-- 保存选区到本地文件
-- ============================================================================
local function SaveSelection()
    if not currentServer_ then return end
    pcall(function()
        ---@diagnostic disable-next-line: undefined-global
        local file = File(SAVE_FILE, FILE_WRITE)
        if file then
            file:WriteString(tostring(currentServer_.id))
            file:Close()
        end
    end)
end

-- ============================================================================
-- 获取 / 设置当前服务器
-- ============================================================================

--- 获取当前服务器（未初始化则自动 Init）
---@return table
function M.GetCurrentServer()
    if not currentServer_ then
        M.Init()
    end
    return currentServer_
end

--- 切换服务器
---@param server table 服务器配置表
function M.SetCurrentServer(server)
    currentServer_ = server
    SaveSelection()
    print("[GameServer] 切换到:", server.name)
end

-- ============================================================================
-- 数据隔离 key 前缀工具
-- ============================================================================

--- 生成当前服务器的数据 key（角色数据等，按区隔离）
--- 例: GetServerKey("player_info") → "s1_player_info"
---@param key string 业务 key
---@return string
function M.GetServerKey(key)
    local s = M.GetCurrentServer()
    return "s" .. s.id .. "_" .. key
end

--- 生成当前服务器组的共享 key（排行榜/交易等，合服后共享）
--- 例: GetGroupKey("ranking") → "g1_ranking"
---@param key string 业务 key
---@return string
function M.GetGroupKey(key)
    local s = M.GetCurrentServer()
    return "g" .. s.groupId .. "_" .. key
end

--- 为指定服务器 ID 生成数据 key
---@param serverId number
---@param key string
---@return string
function M.GetServerKeyById(serverId, key)
    return "s" .. serverId .. "_" .. key
end

return M
