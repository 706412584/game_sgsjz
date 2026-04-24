-- ============================================================================
-- 《问道长生》货币处理器
-- 职责：灵石/仙石的增减由 serverCloud.money 原子操作保障
-- Actions: currency_add, currency_cost, shop_buy
-- ============================================================================

local GameServer   = require("game_server")
local DataItems    = require("data_items")
local PillsHelper  = require("network.pills_helper")

local M = {}
M.Actions = {}

-- ============================================================================
-- 服务端商品价格表（从 data_items.MARKET_GOODS 构建索引）
-- key = itemName, value = { price, currency("lingStone"|"spiritStone"), stock }
-- ============================================================================

local SHOP_CATALOG = {}
for _, g in ipairs(DataItems.MARKET_GOODS) do
    SHOP_CATALOG[g.name] = {
        price    = g.price,
        currency = g.currency == "仙石" and "spiritStone" or "lingStone",
        stock    = g.stock,
        category = g.category,
    }
end

-- 法宝名称 → 定义（用于购买法宝时写入 playerData.artifacts）
local ARTIFACT_BY_NAME = {}
for _, a in ipairs(DataItems.ARTIFACTS or {}) do
    ARTIFACT_BY_NAME[a.name] = a
end

-- 丹药名称 → 定义（用于购买丹药时写入 playerData.pills）
local PILL_BY_NAME = {}
local _pillLists = {
    DataItems.PILLS_COMMON or {},
    DataItems.PILLS_LIMITED or {},
    DataItems.PILLS_BREAKTHROUGH or {},
    DataItems.PILLS_REQUIRED_BREAK or {},
}
for _, lst in ipairs(_pillLists) do
    for _, p in ipairs(lst) do
        if p.name then PILL_BY_NAME[p.name] = p end
    end
end

-- 礼包内容表（服务端发货时写入 bagItems）
-- key = 礼包名, value = { { name, count } ... }
local GIFT_PACK_CONTENTS = {
    ["灵尘礼包"]   = { { name = "灵尘", count = 10 } },
    ["灵尘大礼包"] = { { name = "灵尘", count = 50 } },
}

-- 兑换内容表（仙石→灵石）
-- key = 商品名, value = { currency, amount }
local EXCHANGE_CONTENTS = {
    ["灵石小包"] = { currency = "lingStone", amount = 100 },
    ["灵石中包"] = { currency = "lingStone", amount = 1100 },
    ["灵石大包"] = { currency = "lingStone", amount = 6000 },
}

-- ============================================================================
-- 货币 key 白名单
-- ============================================================================

local CURRENCY_KEYS = {
    lingStone   = true,  -- 灵石
    spiritStone = true,  -- 仙石
}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取玩家区服前缀的货币 key（直接用原始 key，money 不需要区服前缀）
---@param currency string "lingStone"|"spiritStone"
---@return string
local function MoneyKey(currency)
    return currency
end

-- ============================================================================
-- 旧角色货币迁移（scores → money 子系统）
-- 旧角色的灵石/仙石存储在 scores 的 playerData 表中，
-- 新架构使用 serverCloud.money 独立子系统，需一次性迁移。
-- ============================================================================

--- 检查并迁移旧角色货币（幂等：已迁移则跳过）
---@param userId any
---@param playerKey string 区服前缀的 player key（如 "s99_player"）
---@param callback fun(ok: boolean)
local function EnsureCurrencyMigrated(userId, playerKey, callback)
    -- 先查 money 余额
    serverCloud.money:Get(userId, {
        ok = function(moneys)
            local lingBal = (moneys and moneys["lingStone"]) or 0
            local spiritBal = (moneys and moneys["spiritStone"]) or 0
            -- 如果已有余额，视为已迁移
            if lingBal > 0 or spiritBal > 0 then
                callback(true)
                return
            end
            -- 余额都为 0，检查 scores 中是否有旧数据
            serverCloud:Get(userId, playerKey, {
                ok = function(scores, iscores)
                    local playerData = scores and scores[playerKey]
                    if type(playerData) ~= "table" then
                        -- 无旧数据，无需迁移
                        callback(true)
                        return
                    end
                    local oldLing   = playerData.lingStone or 0
                    local oldSpirit = playerData.spiritStone or 0
                    if oldLing <= 0 and oldSpirit <= 0 then
                        callback(true)
                        return
                    end
                    -- 迁移：将旧值 Add 到 money 子系统
                    local pending = 0
                    local failed = false
                    local function tryFinish()
                        pending = pending - 1
                        if pending <= 0 then
                            if not failed then
                                print("[Currency] 旧角色货币迁移完成 uid=" .. tostring(userId)
                                    .. " ling=" .. oldLing .. " spirit=" .. oldSpirit)
                            end
                            callback(not failed)
                        end
                    end
                    if oldLing > 0 then
                        pending = pending + 1
                        serverCloud.money:Add(userId, "lingStone", math.floor(oldLing), {
                            ok = function() tryFinish() end,
                            error = function() failed = true; tryFinish() end,
                        })
                    end
                    if oldSpirit > 0 then
                        pending = pending + 1
                        serverCloud.money:Add(userId, "spiritStone", math.floor(oldSpirit), {
                            ok = function() tryFinish() end,
                            error = function() failed = true; tryFinish() end,
                        })
                    end
                    if pending == 0 then callback(true) end
                end,
                error = function()
                    -- 读 scores 失败，不阻塞正常流程
                    callback(true)
                end,
            })
        end,
        error = function()
            -- money:Get 失败，不阻塞
            callback(true)
        end,
    })
end

-- ============================================================================
-- Action: currency_add — 增加货币（奖励发放等）
-- params: { currency: string, amount: number, reason?: string }
-- ============================================================================

M.Actions["currency_add"] = function(userId, params, reply)
    local currency = params.currency
    local amount   = params.amount
    local reason   = params.reason or "unknown"

    if not CURRENCY_KEYS[currency] then
        reply(false, { msg = "无效的货币类型: " .. tostring(currency) })
        return
    end
    if type(amount) ~= "number" or amount <= 0 then
        reply(false, { msg = "金额必须为正整数" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    local key = MoneyKey(currency)
    serverCloud.money:Add(userId, key, math.floor(amount), {
        ok = function()
            -- 查询最新余额回传
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    local balance = moneys and moneys[key] or 0
                    print("[Currency] Add " .. currency .. " +" .. amount
                        .. " uid=" .. tostring(userId) .. " reason=" .. reason
                        .. " balance=" .. balance)
                    reply(true, {
                        currency = currency,
                        amount   = amount,
                        balance  = balance,
                    }, {
                        [currency] = balance,
                    })
                end,
                error = function(code, reason2)
                    -- Add 成功但查余额失败，仍返回成功（数据已持久化）
                    print("[Currency] Add ok but Get failed: " .. tostring(reason2))
                    reply(true, { currency = currency, amount = amount })
                end,
            })
        end,
        error = function(code, reason2)
            print("[Currency] Add failed uid=" .. tostring(userId) .. " " .. tostring(reason2))
            reply(false, { msg = "增加" .. currency .. "失败: " .. tostring(reason2) })
        end,
    })
end

-- ============================================================================
-- Action: currency_cost — 扣除货币（购买、升级消耗等）
-- params: { currency: string, amount: number, reason?: string }
-- ============================================================================

M.Actions["currency_cost"] = function(userId, params, reply)
    local currency = params.currency
    local amount   = params.amount
    local reason   = params.reason or "unknown"

    if not CURRENCY_KEYS[currency] then
        reply(false, { msg = "无效的货币类型: " .. tostring(currency) })
        return
    end
    if type(amount) ~= "number" or amount <= 0 then
        reply(false, { msg = "金额必须为正整数" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    local key = MoneyKey(currency)
    serverCloud.money:Cost(userId, key, math.floor(amount), {
        ok = function()
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    local balance = moneys and moneys[key] or 0
                    print("[Currency] Cost " .. currency .. " -" .. amount
                        .. " uid=" .. tostring(userId) .. " reason=" .. reason
                        .. " balance=" .. balance)
                    reply(true, {
                        currency = currency,
                        amount   = amount,
                        balance  = balance,
                    }, {
                        [currency] = balance,
                    })
                end,
                error = function()
                    reply(true, { currency = currency, amount = amount })
                end,
            })
        end,
        error = function(code, reason2)
            print("[Currency] Cost failed uid=" .. tostring(userId) .. " " .. tostring(reason2))
            reply(false, { msg = currency == "lingStone" and "灵石不足" or "仙石不足" })
        end,
    })
end

-- ============================================================================
-- Action: shop_buy — 商店购买（服务端验价 + 扣币）
-- params: { itemName: string, count?: number }
-- 服务端从 SHOP_CATALOG 查询真实价格和货币类型，忽略客户端传入的 cost/currency
-- ============================================================================

M.Actions["shop_buy"] = function(userId, params, reply)
    local itemName = params.itemName
    local count    = params.count or 1

    if not itemName or itemName == "" then
        reply(false, { msg = "无效的商品名称" })
        return
    end
    if type(count) ~= "number" or count < 1 then
        reply(false, { msg = "购买数量无效" })
        return
    end
    count = math.floor(count)

    -- 服务端查表获取真实价格（拒绝不在商品表中的物品）
    local catalog = SHOP_CATALOG[itemName]
    if not catalog then
        print("[Currency] ShopBuy 拒绝: 商品不在价格表中 item=" .. itemName
            .. " uid=" .. tostring(userId))
        reply(false, { msg = "商品不存在: " .. itemName })
        return
    end

    local currency = catalog.currency
    local cost     = catalog.price * count

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    local key = MoneyKey(currency)
    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    -- 内部：扣币成功后发送回复（丹药写入 p.pills，法宝写入 p.artifacts）
    local function DoReplyAfterCost(sync)
        -- 兑换：仙石→灵石，服务端增加目标货币
        if catalog.category == "兑换" then
            local ex = EXCHANGE_CONTENTS[itemName]
            if not ex then
                reply(true, { itemName = itemName, count = count, cost = cost, currency = currency }, sync)
                return
            end
            local addAmount = ex.amount * count
            serverCloud.money:Add(userId, ex.currency, math.floor(addAmount), {
                ok = function()
                    serverCloud.money:Get(userId, {
                        ok = function(moneys)
                            local newSync = sync or {}
                            for k2 in pairs(CURRENCY_KEYS) do
                                newSync[k2] = (moneys and moneys[k2]) or 0
                            end
                            print("[Currency] Exchange " .. itemName .. "x" .. count
                                .. " -> " .. ex.currency .. "+" .. addAmount
                                .. " uid=" .. tostring(userId))
                            reply(true, {
                                itemName = itemName, count = count,
                                cost = cost, currency = currency,
                                exchangeAmount = addAmount,
                                exchangeCurrency = ex.currency,
                                balance = newSync[currency],
                            }, newSync)
                        end,
                        error = function()
                            reply(true, { itemName = itemName, count = count, cost = cost, currency = currency, exchangeAmount = addAmount }, sync)
                        end,
                    })
                end,
                error = function(code, reason2)
                    print("[Currency] Exchange Add failed: " .. tostring(reason2))
                    -- 仙石已扣但灵石加失败，仍返回成功（扣款不可回滚），客户端提示异常
                    reply(true, { itemName = itemName, count = count, cost = cost, currency = currency, exchangeFailed = true }, sync)
                end,
            })
            return
        end

        -- 丹药：独立 key 读写（不再走 playerData blob）
        if catalog.category == "丹药" then
            local pillDef = PILL_BY_NAME[itemName]
            local quality = pillDef and pillDef.quality or "xia"
            PillsHelper.Read(userId, function(pills, errMsg)
                if not pills then
                    print("[Currency] ShopBuy 丹药读取失败: " .. tostring(errMsg))
                    reply(true, { itemName = itemName, count = count, cost = cost, currency = currency }, sync)
                    return
                end
                -- 堆叠同名丹药
                local found = false
                for _, pill in ipairs(pills) do
                    if pill.name == itemName then
                        pill.count = (pill.count or 0) + count
                        found = true; break
                    end
                end
                if not found then
                    pills[#pills + 1] = {
                        name    = itemName,
                        count   = count,
                        quality = quality,
                        desc    = pillDef and pillDef.effect or "",
                        effect  = pillDef and pillDef.effect or "",
                    }
                end
                PillsHelper.Write(userId, pills, function(ok)
                    if ok then
                        print("[Currency] ShopBuy 丹药已写入: " .. itemName .. "x" .. count)
                    else
                        print("[Currency] ShopBuy 丹药写入失败")
                    end
                    local newSync = sync or {}
                    newSync.pills = pills
                    reply(true, {
                        itemName = itemName, count = count,
                        cost = cost, currency = currency,
                        balance = newSync[currency],
                    }, newSync)
                end, playerKey)
            end, playerKey)
            return
        end

        -- 礼包：服务端写入 bagItems（灵尘等内容物），不发礼包本身
        if catalog.category == "礼包" then
            local contents = GIFT_PACK_CONTENTS[itemName]
            if not contents then
                -- 未知礼包降级处理
                reply(true, { itemName = itemName, count = count, cost = cost, currency = currency, balance = sync and sync[currency] }, sync)
                return
            end
            serverCloud:Get(userId, playerKey, {
                ok = function(scores)
                    local pd = scores and scores[playerKey]
                    if type(pd) ~= "table" then
                        reply(true, { itemName = itemName, count = count, cost = cost, currency = currency }, sync)
                        return
                    end
                    pd.bagItems = pd.bagItems or {}
                    local bagCap = pd.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
                    for _, slot in ipairs(contents) do
                        local totalCount = slot.count * count
                        local found = false
                        for _, bi in ipairs(pd.bagItems) do
                            if bi.name == slot.name then
                                bi.count = (bi.count or 0) + totalCount
                                found = true; break
                            end
                        end
                        if not found then
                            -- 容量防护：新物品槽位不够则跳过（不中断整个礼包）
                            if #pd.bagItems >= bagCap then
                                print("[Currency] bag_full skip gift item " .. slot.name
                                    .. " uid=" .. tostring(userId))
                            else
                                pd.bagItems[#pd.bagItems + 1] = { name = slot.name, count = totalCount }
                            end
                        end
                    end
                    serverCloud:Set(userId, playerKey, pd, {
                        ok = function()
                            print("[Currency] ShopBuy 礼包写入: " .. itemName .. "x" .. count)
                            local newSync = sync or {}
                            newSync.bagItems = pd.bagItems
                            reply(true, {
                                itemName = itemName, count = count,
                                cost = cost, currency = currency,
                                balance = newSync[currency],
                                isGiftPack = true,
                            }, newSync)
                        end,
                        error = function()
                            reply(true, { itemName = itemName, count = count, cost = cost, currency = currency }, sync)
                        end,
                    })
                end,
                error = function()
                    reply(true, { itemName = itemName, count = count, cost = cost, currency = currency }, sync)
                end,
            })
            return
        end

        local artDef = ARTIFACT_BY_NAME[itemName]
        if not artDef or catalog.category ~= "法宝" then
            -- 其他类型（非丹药非法宝），直接回复
            reply(true, {
                itemName = itemName,
                count    = count,
                rarity   = params.rarity or "common",
                desc     = params.desc or "",
                cost     = cost,
                currency = currency,
                balance  = sync and sync[currency],
            }, sync)
            return
        end
        -- 法宝：读 playerData → 插入 artifacts → 写回
        serverCloud:Get(userId, playerKey, {
            ok = function(scores)
                local pd = scores and scores[playerKey]
                if type(pd) ~= "table" then
                    -- 读取失败仍回复成功（钱已扣），客户端本地也会添加
                    print("[Currency] ShopBuy 法宝写入失败: playerData 不存在")
                    reply(true, {
                        itemName = itemName, count = count,
                        cost = cost, currency = currency,
                    }, sync)
                    return
                end
                pd.artifacts = pd.artifacts or {}
                -- 去重检查
                local exists = false
                for _, a in ipairs(pd.artifacts) do
                    if a.name == artDef.name then exists = true; break end
                end
                if not exists then
                    local quality = artDef.quality or "fanqi"
                    if DataItems.OLD_QUALITY_MAP and DataItems.OLD_QUALITY_MAP[quality] then
                        quality = DataItems.OLD_QUALITY_MAP[quality]
                    end
                    pd.artifacts[#pd.artifacts + 1] = {
                        name     = artDef.name,
                        quality  = quality,
                        slot     = artDef.slot or "weapon",
                        effect   = artDef.effect or "",
                        desc     = artDef.desc or "",
                        level    = 1,
                        ascStage = 0,
                        equipped = false,
                    }
                end
                serverCloud:Set(userId, playerKey, pd, {
                    ok = function()
                        print("[Currency] ShopBuy 法宝已写入: " .. itemName)
                        reply(true, {
                            itemName = itemName, count = count,
                            rarity = artDef.quality or "common",
                            desc = artDef.desc or "",
                            cost = cost, currency = currency,
                            balance = sync and sync[currency],
                        }, sync)
                    end,
                    error = function()
                        -- 写入失败仍回复成功（钱已扣）
                        print("[Currency] ShopBuy 法宝写入 Set 失败")
                        reply(true, {
                            itemName = itemName, count = count,
                            cost = cost, currency = currency,
                        }, sync)
                    end,
                })
            end,
            error = function()
                print("[Currency] ShopBuy 法宝写入 Get 失败")
                reply(true, {
                    itemName = itemName, count = count,
                    cost = cost, currency = currency,
                }, sync)
            end,
        })
    end

    -- 执行购买（扣币 + 发货）
    local function ProceedBuy()
        serverCloud.money:Cost(userId, key, math.floor(cost), {
            ok = function()
                -- 扣币成功，查询所有货币最新余额（同步两种货币给客户端）
                serverCloud.money:Get(userId, {
                    ok = function(moneys)
                        local sync = {}
                        for k2 in pairs(CURRENCY_KEYS) do
                            sync[k2] = (moneys and moneys[k2]) or 0
                        end
                        local balance = sync[currency] or 0
                        print("[Currency] ShopBuy " .. itemName .. "x" .. count
                            .. " cost=" .. cost .. " " .. currency
                            .. " uid=" .. tostring(userId)
                            .. " balance=" .. balance)
                        DoReplyAfterCost(sync)
                    end,
                    error = function()
                        -- 扣币成功但查余额失败
                        DoReplyAfterCost(nil)
                    end,
                })
            end,
            error = function(code, reason)
                local currName = currency == "lingStone" and "灵石" or "仙石"
                print("[Currency] ShopBuy failed uid=" .. tostring(userId) .. " " .. tostring(reason))
                reply(false, { msg = currName .. "不足" })
            end,
        })
    end

    -- 限量库存商品：先校验今日剩余配额，再扣币
    if catalog.stock and catalog.stock > 0 then
        serverCloud:Get(userId, playerKey, {
            ok = function(scores)
                local pd = scores and scores[playerKey]
                if type(pd) ~= "table" then
                    -- 读取失败视为首次购买，不阻塞
                    ProceedBuy()
                    return
                end
                local today = os.date("%Y-%m-%d")
                if pd.shopStockDate ~= today then
                    pd.shopStock    = {}
                    pd.shopStockDate = today
                end
                local bought = (pd.shopStock or {})[itemName] or 0
                if bought + count > catalog.stock then
                    reply(false, {
                        msg = string.format("今日限购%d件，已购%d件", catalog.stock, bought),
                    })
                    return
                end
                -- 先写入计数（防止并发超购），再扣币发货
                pd.shopStock             = pd.shopStock or {}
                pd.shopStock[itemName]   = bought + count
                serverCloud:Set(userId, playerKey, pd, {
                    ok    = function() ProceedBuy() end,
                    error = function()
                        -- 写入失败不阻塞购买（容忍极小概率超购）
                        print("[Currency] ShopBuy 库存写入失败，仍继续扣币 uid=" .. tostring(userId))
                        ProceedBuy()
                    end,
                })
            end,
            error = function()
                -- 读取失败不阻塞
                ProceedBuy()
            end,
        })
    else
        ProceedBuy()
    end
end

-- ============================================================================
-- Action: currency_get — 查询余额
-- params: {} (无需参数)
-- ============================================================================

M.Actions["currency_get"] = function(userId, params, reply)
    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        -- 向后兼容：如果客户端未传 playerKey，降级到服务端本地 key
        playerKey = GameServer.GetServerKey("player")
    end

    -- 先确保旧角色货币已迁移
    EnsureCurrencyMigrated(userId, playerKey, function()
        serverCloud.money:Get(userId, {
            ok = function(moneys)
                local result = {}
                for k in pairs(CURRENCY_KEYS) do
                    result[k] = (moneys and moneys[MoneyKey(k)]) or 0
                end
                reply(true, result, result)
            end,
            error = function(code, reason)
                reply(false, { msg = "查询余额失败: " .. tostring(reason) })
            end,
        })
    end)
end

-- ============================================================================
-- Action: currency_migrate — 手动触发旧角色货币迁移
-- params: {} (无需参数)
-- ============================================================================

M.Actions["currency_migrate"] = function(userId, params, reply)
    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        playerKey = GameServer.GetServerKey("player")
    end

    EnsureCurrencyMigrated(userId, playerKey, function(ok)
        if ok then
            -- 迁移完成，返回最新余额
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    local result = {}
                    for k in pairs(CURRENCY_KEYS) do
                        result[k] = (moneys and moneys[MoneyKey(k)]) or 0
                    end
                    reply(true, result, result)
                end,
                error = function()
                    reply(true, { msg = "迁移完成，余额查询失败" })
                end,
            })
        else
            reply(false, { msg = "货币迁移失败" })
        end
    end)
end

return M
