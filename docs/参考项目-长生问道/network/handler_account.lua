-- ============================================================================
-- 《问道长生》账号/角色管理处理器
-- 职责：删除角色时清理服务端 money 等无法通过 polyfill BatchSet 清除的资源
-- Actions: delete_character
-- ============================================================================

local M = {}
M.Actions = {}

-- ============================================================================
-- Action: delete_character — 清除角色关联的 serverCloud.money
-- params: {} (无需参数，userId 由网关自动提供)
-- ============================================================================

M.Actions["delete_character"] = function(userId, params, reply)
    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    -- 查询当前余额
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            local pending = 0
            local failed = false

            local function TryFinish()
                pending = pending - 1
                if pending <= 0 then
                    if failed then
                        reply(false, { msg = "部分货币清零失败" })
                    else
                        reply(true, { msg = "角色货币已清零" },
                            { lingStone = 0, spiritStone = 0 })
                    end
                end
            end

            -- 需要清零的货币列表
            local currencies = { "lingStone", "spiritStone" }
            for _, key in ipairs(currencies) do
                local balance = (moneys and moneys[key]) or 0
                if balance > 0 then
                    pending = pending + 1
                    serverCloud.money:Cost(userId, key, balance, {
                        ok = function()
                            print("[Account] 已清零 " .. key .. " (" .. balance .. ") uid=" .. tostring(userId))
                            TryFinish()
                        end,
                        error = function(code, reason)
                            print("[Account] 清零 " .. key .. " 失败: " .. tostring(reason))
                            failed = true
                            TryFinish()
                        end,
                    })
                end
            end

            -- 如果所有余额都已为 0，直接完成
            if pending == 0 then
                print("[Account] 角色货币已为 0，无需清零 uid=" .. tostring(userId))
                reply(true, { msg = "角色货币已清零" },
                    { lingStone = 0, spiritStone = 0 })
            end
        end,
        error = function(code, reason)
            print("[Account] 查询余额失败: " .. tostring(reason))
            reply(false, { msg = "查询余额失败: " .. tostring(reason) })
        end,
    })
end

return M
