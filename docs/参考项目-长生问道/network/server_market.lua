-- ============================================================================
-- 《问道长生》服务端寄售坊模块
-- 职责：serverCloud.list 寄售管理、购买发邮件通知卖家
-- 架构：云变量方案（不管货币，购买后通过 serverCloud.message 发邮件）
-- ============================================================================

local Shared = require("network.shared")
local EVENTS = Shared.EVENTS
---@diagnostic disable-next-line: undefined-global
local cjson  = cjson  -- 引擎内置全局变量，无需 require

local M = {}

-- ============================================================================
-- 状态
-- ============================================================================

-- 寄售聚合表：所有在线卖家的寄售物品（内存缓存，重启后重建）
-- allListings_[listId] = { listId, sellerUid, name, price, stock, rarity, desc }
local allListings_ = {}

-- P3: 双货币手续费率（与 data_items.TRADING_POST.feeRates 一致）
local FEE_RATES = {
    lingStone   = 0.05,  -- 灵石 5%
    spiritStone = 0.10,  -- 仙石 10%
}
local CURRENCY_LABELS = {
    lingStone   = "灵石",
    spiritStone = "仙石",
}

-- ============================================================================
-- 初始化（由 server_main.lua 调用）
-- ============================================================================

---@param deps table { connections, connUserIds, userIdToConn, SendToClient }
function M.Init(deps)
    M.deps = deps
    print("[ServerMarket] 寄售坊服务端初始化完成")
end

--- 玩家上线时加载其寄售列表到聚合表
---@param userId number
function M.LoadPlayerListings(userId)
    if not serverCloud then return end

    serverCloud.list:Get(userId, "market", {
        ok = function(list)
            if not list or #list == 0 then return end
            for _, item in ipairs(list) do
                local val = item.value or {}
                allListings_[item.list_id] = {
                    listId    = item.list_id,
                    sellerUid = userId,
                    name      = val.name or "未知",
                    price     = val.price or 0,
                    stock     = val.stock or 1,
                    rarity    = val.rarity or "common",
                    desc      = val.desc or "",
                    currency  = val.currency or "lingStone",
                    itemType  = val.itemType or "bagItem",
                }
            end
            print("[ServerMarket] 加载玩家 " .. tostring(userId) .. " 的 " .. #list .. " 条寄售")
        end,
        error = function(code, reason)
            print("[ServerMarket] 加载寄售失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
        end,
    })
end

--- 玩家下线时从聚合表移除其寄售
---@param userId number
function M.UnloadPlayerListings(userId)
    for listId, listing in pairs(allListings_) do
        if listing.sellerUid == userId then
            allListings_[listId] = nil
        end
    end
end

-- ============================================================================
-- 工具函数
-- ============================================================================

--- 聚合表转 JSON 数组
---@return string
local function EncodeAllListings()
    local arr = {}
    for _, listing in pairs(allListings_) do
        arr[#arr + 1] = listing
    end
    return cjson.encode(arr)
end

--- 指定玩家的寄售列表 JSON
---@param userId number
---@return string
local function EncodeMyListings(userId)
    local arr = {}
    for _, listing in pairs(allListings_) do
        if listing.sellerUid == userId then
            arr[#arr + 1] = listing
        end
    end
    return cjson.encode(arr)
end

--- 统一回复客户端
---@param userId number
---@param action string
---@param success boolean
---@param msg string
---@param extra table|nil  额外字段
local function Reply(userId, action, success, msg, extra)
    local data = VariantMap()
    data["Action"]  = Variant(action)
    data["Success"] = Variant(success)
    data["Msg"]     = Variant(msg)
    if extra then
        for k, v in pairs(extra) do
            data[k] = v
        end
    end
    M.deps.SendToClient(userId, EVENTS.MARKET_DATA, data)
end

-- ============================================================================
-- 统一入口（由 server_main.lua 调用）
-- ============================================================================

---@param userId number
---@param eventData any
function M.HandleMarketOp(userId, eventData)
    local action = eventData["Action"]:GetString()

    if action == "browse" then
        M.OnBrowse(userId)
    elseif action == "myList" then
        M.OnMyList(userId)
    elseif action == "list" then
        M.OnList(userId, eventData)
    elseif action == "delist" then
        M.OnDelist(userId, eventData)
    elseif action == "buy" then
        M.OnBuy(userId, eventData)
    else
        Reply(userId, action or "unknown", false, "未知操作")
    end
end

-- ============================================================================
-- 操作实现
-- ============================================================================

--- 浏览全部寄售
function M.OnBrowse(userId)
    local data = VariantMap()
    data["Action"] = Variant("browse")
    data["Data"]   = Variant(EncodeAllListings())
    M.deps.SendToClient(userId, EVENTS.MARKET_DATA, data)
end

--- 我的寄售
function M.OnMyList(userId)
    local data = VariantMap()
    data["Action"] = Variant("myList")
    data["Data"]   = Variant(EncodeMyListings(userId))
    M.deps.SendToClient(userId, EVENTS.MARKET_DATA, data)
end

--- 上架物品
function M.OnList(userId, eventData)
    local itemName = eventData["ItemName"]:GetString()
    local price    = eventData["Price"]:GetInt()
    local count    = eventData["Count"]:GetInt()
    local rarity   = eventData["Rarity"]:GetString()
    local desc     = eventData["Desc"]:GetString()
    local currency = eventData["Currency"]:GetString()
    local itemType = eventData["ItemType"]:GetString()

    -- 兼容旧客户端：无 Currency 字段时默认灵石
    if currency == "" then currency = "lingStone" end
    if itemType == "" then itemType = "bagItem" end

    if price <= 0 or count <= 0 then
        Reply(userId, "list", false, "无效的上架参数")
        return
    end

    if not serverCloud then
        Reply(userId, "list", false, "服务端存储不可用")
        return
    end

    local listingValue = {
        name     = itemName,
        price    = price,
        stock    = count,
        rarity   = rarity,
        desc     = desc,
        currency = currency,
        itemType = itemType,
    }
    local listId = serverCloud.list:Add(userId, "market", listingValue)

    allListings_[listId] = {
        listId    = listId,
        sellerUid = userId,
        name      = itemName,
        price     = price,
        stock     = count,
        rarity    = rarity,
        desc      = desc,
        currency  = currency,
        itemType  = itemType,
    }

    local currLabel = CURRENCY_LABELS[currency] or "灵石"
    print("[ServerMarket] 上架 uid=" .. tostring(userId) .. " " .. itemName .. "x" .. count
        .. " 单价" .. price .. currLabel)

    Reply(userId, "list", true, "上架成功", {
        ListId = Variant(tostring(listId)),
    })
end

--- 下架物品
function M.OnDelist(userId, eventData)
    local listIdStr = eventData["ListId"]:GetString()
    local listId = tonumber(listIdStr) or 0

    local listing = allListings_[listId]
    if not listing then
        Reply(userId, "delist", false, "寄售物品不存在")
        return
    end
    if listing.sellerUid ~= userId then
        Reply(userId, "delist", false, "只能下架自己的物品")
        return
    end

    serverCloud.list:Delete(listId)
    allListings_[listId] = nil

    print("[ServerMarket] 下架 uid=" .. tostring(userId) .. " listId=" .. tostring(listId))

    Reply(userId, "delist", true, "下架成功", {
        ItemName  = Variant(listing.name),
        ItemCount = Variant(listing.stock),
        Rarity    = Variant(listing.rarity),
        Desc      = Variant(listing.desc),
        ItemType  = Variant(listing.itemType or "bagItem"),
    })
end

--- 购买寄售物品
--- 流程：验证 listing → 删除 listing → 发邮件给卖家 → 回复买家
--- 买家扣币由客户端本地完成（乐观更新），服务端不管货币
function M.OnBuy(buyerUid, eventData)
    local listIdStr = eventData["ListId"]:GetString()
    local listId = tonumber(listIdStr) or 0

    local listing = allListings_[listId]
    if not listing then
        Reply(buyerUid, "buy", false, "该物品已被购买或下架")
        return
    end
    if listing.sellerUid == buyerUid then
        Reply(buyerUid, "buy", false, "不能购买自己的寄售")
        return
    end
    if not serverCloud then
        Reply(buyerUid, "buy", false, "服务端存储不可用")
        return
    end

    -- P3: 根据 listing 的 currency 决定费率
    local currKey      = listing.currency or "lingStone"
    local feeRate      = FEE_RATES[currKey] or 0.05
    local currLabel    = CURRENCY_LABELS[currKey] or "灵石"
    local totalCost    = listing.price * listing.stock
    local fee          = math.floor(totalCost * feeRate)
    local sellerIncome = totalCost - fee

    -- 1. 删除寄售
    serverCloud.list:Delete(listId)
    allListings_[listId] = nil

    -- 2. 给卖家发放货币收入
    serverCloud.money:Add(listing.sellerUid, currKey, sellerIncome, {
        ok = function()
            print("[ServerMarket] 卖家收入已到账 seller=" .. tostring(listing.sellerUid)
                .. " +" .. sellerIncome .. currLabel)
        end,
        error = function(code, reason)
            print("[ServerMarket] 卖家入账失败 seller=" .. tostring(listing.sellerUid)
                .. " code=" .. tostring(code) .. " " .. tostring(reason))
        end,
    })

    -- 3. 发邮件给卖家（serverCloud.message）
    local mailValue = {
        type       = "trade_income",
        itemName   = listing.name,
        itemCount  = listing.stock,
        rarity     = listing.rarity,
        totalPrice = totalCost,
        fee        = fee,
        income     = sellerIncome,
        currency   = currKey,
        buyerUid   = buyerUid,
    }
    serverCloud.message:Send(buyerUid, "trade", listing.sellerUid, mailValue, {
        ok = function(errorCode, errorDesc)
            if errorCode == 0 or errorCode == nil then
                print("[ServerMarket] 交易邮件已发送 seller=" .. tostring(listing.sellerUid)
                    .. " 收入" .. sellerIncome .. currLabel)
            else
                print("[ServerMarket] 邮件发送异常 code=" .. tostring(errorCode))
            end
        end,
    })

    -- 4. 回复买家（不等邮件回调，listing 已删即算成功）
    print("[ServerMarket] 购买成功 buyer=" .. tostring(buyerUid)
        .. " item=" .. listing.name .. " cost=" .. (totalCost + fee) .. currLabel)

    Reply(buyerUid, "buy", true, "购买成功", {
        ItemName  = Variant(listing.name),
        ItemCount = Variant(listing.stock),
        Rarity    = Variant(listing.rarity),
        Desc      = Variant(listing.desc),
        TotalCost = Variant(totalCost + fee),
    })

    -- 5. 通知卖家（如果在线）
    Reply(listing.sellerUid, "soldNotify", true,
        "你的" .. listing.name .. "已售出，" .. sellerIncome .. currLabel .. "已发送到邮箱")
end

return M
