-- ============================================================================
-- 《问道长生》服务器列表配置
-- 定义所有区服信息、状态常量、辅助查询函数
-- ============================================================================

local M = {}

-- ============================================================================
-- 服务器状态常量
-- ============================================================================
M.STATUS_OPEN     = "open"       -- 正常运营（可选择）
M.STATUS_MAINTAIN = "maintain"   -- 维护中（灰色不可选）
M.STATUS_CLOSED   = "closed"     -- 已关闭（不显示）
M.STATUS_MERGED   = "merged"     -- 已合服（显示"已合服至X区"）

-- ============================================================================
-- 静态显示标签（手动配置）
-- ============================================================================
M.TAG_RECOMMEND = "推荐"
M.TAG_NEW       = "新服"
M.TAG_MAINTAIN  = "维护中"

-- ============================================================================
-- 动态状态标签（根据在线人数自动判定，优先级高于静态 tag）
-- 纯展示不阻止进入
-- ============================================================================
M.TAG_SMOOTH = "畅通"    -- < 30人   绿色
M.TAG_GOOD   = "良好"    -- 30-59人  蓝色
M.TAG_BUSY   = "繁忙"    -- 60-94人  橙色
M.TAG_FULL   = "爆满"    -- >= 95人  红色（仍可进入）

-- 在线人数阈值配置
M.ONLINE_THRESHOLDS = {
    { min = 0,  tag = M.TAG_SMOOTH, color = { 76, 175, 80, 255 },  bg = { 76, 175, 80, 40 } },
    { min = 30, tag = M.TAG_GOOD,   color = { 33, 150, 243, 255 }, bg = { 33, 150, 243, 40 } },
    { min = 60, tag = M.TAG_BUSY,   color = { 255, 152, 0, 255 },  bg = { 255, 152, 0, 40 } },
    { min = 95, tag = M.TAG_FULL,   color = { 244, 67, 54, 255 },  bg = { 244, 67, 54, 40 } },
}

--- 根据在线人数获取状态标签和颜色
---@param onlineCount number
---@return string tag
---@return table color {r,g,b,a}
---@return table bg {r,g,b,a}
function M.GetStatusByOnline(onlineCount)
    local n = onlineCount or 0
    local result = M.ONLINE_THRESHOLDS[1]
    for _, t in ipairs(M.ONLINE_THRESHOLDS) do
        if n >= t.min then result = t end
    end
    return result.tag, result.color, result.bg
end

-- ============================================================================
-- 服务器列表
-- id:       唯一标识（不可变，用于数据隔离 key 前缀）
-- name:     显示名称
-- status:   当前状态
-- groupId:  数据组（合服后多个 id 共享同一 groupId）
-- tag:      显示标签
-- mergedTo: 合服目标区名（仅 status="merged" 时有效）
-- ============================================================================
M.servers = {
    {
        id      = 1,
        name    = "问道1区",
        status  = M.STATUS_OPEN,
        groupId = 1,
        tag     = M.TAG_RECOMMEND,
    },
    {
        id      = 2,
        name    = "问道2区",
        status  = M.STATUS_MAINTAIN,
        groupId = 2,
        tag     = M.TAG_MAINTAIN,
    },
    {
        id      = 3,
        name    = "问道3区",
        status  = M.STATUS_MAINTAIN,
        groupId = 3,
        tag     = M.TAG_MAINTAIN,
    },
    {
        id      = 99,
        name    = "[测试服]",
        status  = M.STATUS_OPEN,
        groupId = 99,
        tag     = "测试",
        isTest  = true,  -- 标记为测试服
    },
}

-- 默认服务器 ID（正式环境）
M.DEFAULT_SERVER_ID = 1

-- 测试服务器 ID（调试环境自动选择）
M.TEST_SERVER_ID = 99

-- ============================================================================
-- 辅助函数
-- ============================================================================

--- 根据 ID 获取服务器
---@param id number
---@return table|nil
function M.GetServer(id)
    for _, s in ipairs(M.servers) do
        if s.id == id then return s end
    end
    return nil
end

--- 获取所有可见服务器
--- 调试环境（isDebug=true）：显示全部（测试服排最前）
--- 正式环境（isDebug=false/nil）：隐藏测试服
---@param isDebug? boolean 是否调试环境
---@return table[]
function M.GetVisibleServers(isDebug)
    local result = {}
    -- 调试环境：测试服排最前
    if isDebug then
        for _, s in ipairs(M.servers) do
            if s.status ~= M.STATUS_CLOSED and s.isTest then
                result[#result + 1] = s
            end
        end
    end
    -- 正式服
    for _, s in ipairs(M.servers) do
        if s.status ~= M.STATUS_CLOSED and not s.isTest then
            result[#result + 1] = s
        end
    end
    return result
end

--- 判断服务器是否可选择（仅 open 状态可选）
---@param server table
---@return boolean
function M.IsSelectable(server)
    return server.status == M.STATUS_OPEN
end

--- 获取默认服务器
---@return table
function M.GetDefaultServer()
    return M.GetServer(M.DEFAULT_SERVER_ID)
end

return M
