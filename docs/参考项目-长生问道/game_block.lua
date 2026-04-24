-- ============================================================================
-- 《问道长生》屏蔽/举报模块
-- 职责：本地屏蔽列表管理（clientCloud 持久化）、举报记录、消息过滤判断
-- ============================================================================

---@diagnostic disable-next-line: undefined-global
local cjson = cjson

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

local BLOCK_KEY = "block_list"   -- clientCloud 存储 key
local blockList_ = {}            -- uid(number) -> { name, time }
local loaded_ = false

-- ============================================================================
-- 初始化：从 clientCloud 加载屏蔽列表
-- ============================================================================

function M.Load()
    if loaded_ then return end
    ---@diagnostic disable-next-line: undefined-global
    if not clientCloud then
        loaded_ = true
        return
    end
    ---@diagnostic disable-next-line: undefined-global
    clientCloud:Get(BLOCK_KEY, {
        ok = function(values)
            local json = values and values[BLOCK_KEY]
            if json and type(json) == "string" and json ~= "" then
                local ok2, data = pcall(cjson.decode, json)
                if ok2 and type(data) == "table" then
                    blockList_ = {}
                    for uid, info in pairs(data) do
                        blockList_[tonumber(uid) or 0] = info
                    end
                end
            end
            loaded_ = true
            print("[GameBlock] 屏蔽列表已加载, 共 " .. M.GetBlockCount() .. " 人")
        end,
        error = function()
            loaded_ = true
            print("[GameBlock] 屏蔽列表加载失败，使用空列表")
        end,
    })
end

-- ============================================================================
-- 持久化保存
-- ============================================================================

local function save()
    ---@diagnostic disable-next-line: undefined-global
    if not clientCloud then return end
    -- 转换为字符串 key 的 table 用于 JSON 序列化
    local data = {}
    for uid, info in pairs(blockList_) do
        data[tostring(uid)] = info
    end
    ---@diagnostic disable-next-line: undefined-global
    clientCloud:Set(BLOCK_KEY, cjson.encode(data), {
        ok = function() end,
        error = function(_, reason)
            print("[GameBlock] 保存失败: " .. tostring(reason))
        end,
    })
end

-- ============================================================================
-- 对外接口
-- ============================================================================

--- 判断是否已屏蔽某玩家
---@param uid number
---@return boolean
function M.IsBlocked(uid)
    return blockList_[tonumber(uid) or 0] ~= nil
end

--- 屏蔽某玩家
---@param uid number
---@param name? string
function M.Block(uid, name)
    uid = tonumber(uid) or 0
    if uid == 0 then return end
    blockList_[uid] = {
        name = name or "???",
        time = os.time(),
    }
    save()
    print("[GameBlock] 已屏蔽: " .. tostring(uid) .. " " .. (name or ""))
end

--- 取消屏蔽
---@param uid number
function M.Unblock(uid)
    uid = tonumber(uid) or 0
    blockList_[uid] = nil
    save()
    print("[GameBlock] 已取消屏蔽: " .. tostring(uid))
end

--- 获取屏蔽列表
---@return table  uid -> { name, time }
function M.GetBlockList()
    return blockList_
end

--- 获取屏蔽数量
---@return number
function M.GetBlockCount()
    local count = 0
    for _ in pairs(blockList_) do
        count = count + 1
    end
    return count
end

--- 举报玩家（仅本地记录日志 + Toast，后续可接入服务端）
---@param uid number
---@param name string
---@param reason string
function M.Report(uid, name, reason)
    print("[GameBlock] 举报: uid=" .. tostring(uid) .. " name=" .. (name or "???") .. " reason=" .. (reason or ""))
    -- 后续可通过远程事件提交到服务端
end

return M
