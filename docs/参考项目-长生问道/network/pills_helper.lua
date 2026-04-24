-- ============================================================================
-- pills_helper.lua — 丹药独立 key 读写工具
-- ============================================================================
-- pills 数据从 playerData blob 中拆出，使用独立 serverCloud key (s{n}_pills)。
-- 所有 handler 统一通过此模块读写 pills，避免 blob 全量读-改-写竞态。
-- ============================================================================

local M = {}

--- 从 playerKey 推导 pillsKey（替换后缀 _player → _pills）
--- 例: "s99_player" → "s99_pills", "s1_player" → "s1_pills"
---@param playerKey? string 如果传入则从中推导，否则 fallback 到 GameServer
---@return string
function M.PillsKey(playerKey)
    if playerKey then
        return playerKey:gsub("_player$", "_pills")
    end
    -- fallback：如果没传 playerKey（向后兼容）
    local GameServer = require("game_server")
    return GameServer.GetServerKey("pills")
end

--- 读取玩家丹药列表
---@param userId number
---@param callback fun(pills: table|nil, errMsg: string|nil)
---@param playerKey? string 从客户端 params 传来的 playerKey，用于推导 pillsKey
function M.Read(userId, callback, playerKey)
    local key = M.PillsKey(playerKey)
    serverCloud:Get(userId, key, {
        ok = function(scores)
            local pills = scores and scores[key]
            if pills == nil then
                -- 首次：尚无独立 key，返回空 table（迁移由 MigrateIfNeeded 处理）
                callback({})
            elseif type(pills) == "table" then
                callback(pills)
            else
                -- 兜底：数据格式异常
                print("[PillsHelper] Read 格式异常, uid=" .. tostring(userId)
                    .. " type=" .. type(pills))
                callback({})
            end
        end,
        error = function(code, reason)
            print("[PillsHelper] Read 失败, uid=" .. tostring(userId)
                .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
            callback(nil, "pills 数据读取失败")
        end,
    })
end

--- 写入玩家丹药列表
---@param userId number
---@param pills table
---@param callback fun(ok: boolean, errMsg: string|nil)
---@param playerKey? string 从客户端 params 传来的 playerKey，用于推导 pillsKey
function M.Write(userId, pills, callback, playerKey)
    local key = M.PillsKey(playerKey)
    serverCloud:Set(userId, key, pills, {
        ok = function()
            callback(true)
        end,
        error = function(code, reason)
            print("[PillsHelper] Write 失败, uid=" .. tostring(userId)
                .. " code=" .. tostring(code) .. " reason=" .. tostring(reason))
            callback(false, "pills 数据写入失败")
        end,
    })
end

--- 迁移：如果独立 key 为空但 playerData.pills 有数据，则迁移
--- 由 server_game 在首次加载时调用
---@param userId number
---@param playerData table
---@param callback fun()
---@param playerKey? string 从客户端 params 传来的 playerKey，用于推导 pillsKey
function M.MigrateIfNeeded(userId, playerData, callback, playerKey)
    local key = M.PillsKey(playerKey)
    serverCloud:Get(userId, key, {
        ok = function(scores)
            local existing = scores and scores[key]
            if existing ~= nil then
                -- 独立 key 已有数据，无需迁移
                callback()
                return
            end
            -- 独立 key 为空，检查 playerData 中是否有 pills
            local oldPills = playerData.pills
            if type(oldPills) == "table" and #oldPills > 0 then
                print("[PillsHelper] 迁移 pills, uid=" .. tostring(userId)
                    .. " count=" .. #oldPills)
                -- 写入独立 key
                serverCloud:Set(userId, key, oldPills, {
                    ok = function()
                        -- 迁移成功，清除 playerData 中的 pills
                        local pKey = playerKey
                        if not pKey then
                            local GameServer = require("game_server")
                            pKey = GameServer.GetServerKey("player")
                        end
                        playerData.pills = nil
                        serverCloud:Set(userId, pKey, playerData, {
                            ok = function()
                                print("[PillsHelper] 迁移完成并清理 blob, uid=" .. tostring(userId))
                                callback()
                            end,
                            error = function()
                                -- blob 清理失败不阻塞（下次还会尝试，但独立 key 已有数据不会重复迁移）
                                print("[PillsHelper] 迁移后 blob 清理失败, uid=" .. tostring(userId))
                                callback()
                            end,
                        })
                    end,
                    error = function()
                        print("[PillsHelper] 迁移写入失败, uid=" .. tostring(userId))
                        callback()
                    end,
                })
            else
                -- 没有旧数据需要迁移
                callback()
            end
        end,
        error = function()
            print("[PillsHelper] 迁移检查失败, uid=" .. tostring(userId))
            callback()
        end,
    })
end

return M
