-- ============================================================================
-- 《问道长生》坊市交易模块
-- 职责：商铺购买、寄售上架/下架/购买
-- 架构：云变量方案（商铺购买纯本地，寄售购买乐观更新+远程事件）
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")
local GameQuest  = require("game_quest")
local Toast      = require("ui_toast")
---@diagnostic disable-next-line: undefined-global
local cjson      = cjson  -- 引擎内置全局变量，无需 require

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- P3: 物品交易类型判断（双货币支持）
-- ============================================================================

--- 判断背包物品是否可上架 + 使用什么货币
---@param item table bagItems 中的物品 { name, category, subType, rarity, ... }
---@return boolean tradable, string|nil currencyKey, string|nil reason
function M.GetBagItemTradeInfo(item)
    if not item then return false, nil, "无效物品" end
    local cat = item.category or "item"
    local sub = item.subType or ""

    -- 洗灵丹特殊处理
    if item.name == "洗灵丹" then
        return false, nil, "洗灵丹不可交易"
    end

    -- 丹药 → 灵石
    if cat == "item" and sub == "丹药" then
        return DataItems.CheckTradable("pill", nil)
    end

    -- 材料 → 灵石
    if cat == "material" then
        return DataItems.CheckTradable("material", nil)
    end

    -- 其他背包物品暂不可交易
    return false, nil, "该物品不可交易"
end

--- 判断法宝是否可上架 + 使用什么货币
---@param artifact table artifacts 中的法宝
---@return boolean tradable, string|nil currencyKey, string|nil reason
function M.GetArtifactTradeInfo(artifact)
    if not artifact then return false, nil, "无效法宝" end
    if artifact.equipped then return false, nil, "请先卸下装备" end
    local quality = artifact.quality or "fanqi"
    return DataItems.CheckTradable("artifact", quality)
end

--- 判断武学功法是否可上架 + 使用什么货币
---@param art table martialArts 中的武学
---@return boolean tradable, string|nil currencyKey, string|nil reason
function M.GetMartialArtTradeInfo(art)
    if not art then return false, nil, "无效武学" end
    local grade = art.grade or "fan"
    return DataItems.CheckTradable("martialArt", grade)
end

--- 检查仙石交易前置（月卡 + 每日限额）
---@return boolean ok, string|nil reason
function M.CheckSpiritStoneTradeLimit()
    local config = DataItems.TRADING_POST.spiritStoneTrade
    -- 月卡前置（月卡系统未实现，暂时放行）
    -- TODO: 月卡系统实现后对接
    -- if config.requireMonthCard then
    --     local hasCard = GamePlayer.HasMonthCard()
    --     if not hasCard then return false, "仙石交易需开通月卡" end
    -- end

    -- 每日限额检查
    local p = GamePlayer.Get()
    if p then
        local today = os.date("%Y-%m-%d")
        p.spiritStoneTradeLog = p.spiritStoneTradeLog or {}
        if p.spiritStoneTradeLog.date ~= today then
            p.spiritStoneTradeLog = { date = today, count = 0 }
        end
        local limit = config.dailyLimit or 5
        if p.spiritStoneTradeLog.count >= limit then
            return false, "今日仙石交易已达上限(" .. limit .. "笔)"
        end
    end
    return true, nil
end

--- 记录一笔仙石交易（上架或购买后调用）
function M.RecordSpiritStoneTrade()
    local p = GamePlayer.Get()
    if not p then return end
    local today = os.date("%Y-%m-%d")
    p.spiritStoneTradeLog = p.spiritStoneTradeLog or {}
    if p.spiritStoneTradeLog.date ~= today then
        p.spiritStoneTradeLog = { date = today, count = 0 }
    end
    p.spiritStoneTradeLog.count = (p.spiritStoneTradeLog.count or 0) + 1
end

--- 货币key → 中文名
---@param currencyKey string "lingStone"|"spiritStone"
---@return string
function M.GetCurrencyLabel(currencyKey)
    if currencyKey == "spiritStone" then return "仙石" end
    return "灵石"
end

-- ============================================================================
-- 服务端数据缓存
-- ============================================================================

M.serverListings_ = nil   -- 全部寄售列表
M.myListings_     = nil   -- 我的寄售列表

-- ============================================================================
-- 商铺购买（纯本地，不分网络/单机）
-- ============================================================================

---@param item table { name, price, currency, stock, rarity, desc }
---@param count? number
---@return boolean, string|nil
function M.CanBuyGoods(item, count)
    if not item then return false, "无效的商品" end
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    count = count or 1
    if item.stock ~= nil and item.stock >= 0 and item.stock < count then
        return false, "库存不足"
    end

    local totalCost = item.price * count
    local currKey = item.currency == "仙石" and "spiritStone" or "lingStone"
    if GamePlayer.GetCurrency(currKey) < totalCost then
        return false, item.currency .. "不足"
    end

    -- 容量预检查：丹药不占背包格子（存 pills），其余需要背包有空位
    if item.category ~= "丹药" then
        local GameItems = require("game_items")
        if GameItems.IsBagFull() then
            -- 可堆叠物品如果背包已有同名则不占新格子
            local existing = false
            for _, bi in ipairs(p.bagItems or {}) do
                if bi.name == item.name then existing = true; break end
            end
            if not existing then
                return false, "储物戒已满，请先整理背包或扩容后再购买"
            end
        end
    end

    return true, nil
end

---@param item table
---@param count? number
---@return boolean, string
function M.DoBuyGoods(item, count)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    count = count or 1
    if not IsNetworkMode() then
        local ok, reason = M.CanBuyGoods(item, count)
        if not ok then return false, reason or "无法购买" end
    end

    local totalCost = item.price * count
    local currKey = item.currency == "仙石" and "spiritStone" or "lingStone"

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("shop_buy", {
        currency  = currKey,
        cost      = totalCost,
        itemName  = item.name,
        count     = count,
        rarity    = item.rarity or "common",
        desc      = item.desc or "",
        playerKey = GameServer.GetServerKey("player"),
    }, function(ok2, data)
        if ok2 then
            if item.stock and item.stock > 0 then
                item.stock = item.stock - count
            end
            -- 查找是否为法宝（DataItems.ARTIFACTS 表中有定义）
            local artDef = nil
            for _, a in ipairs(DataItems.ARTIFACTS or {}) do
                if a.name == item.name then artDef = a; break end
            end
            if artDef then
                GamePlayer.AddArtifact(artDef)
            elseif item.category == "丹药" then
                -- 丹药：服务端已写入 p.pills 并在 sync 中回传，GameOps.ApplySync 自动更新本地
                -- 不需要 AddItem（否则会多存一份到 bagItems，造成数量不一致）
            elseif item.shopCategory == "礼包" or data.isGiftPack then
                -- 礼包：服务端已写入内容物到 bagItems 并通过 sync 回传
                -- GameOps.ApplySync 自动同步本地，客户端无需额外操作
            else
                GamePlayer.AddItem({ name = item.name, count = count, rarity = item.rarity or "common", desc = item.desc or "" })
            end
            -- 礼包显示内容物提示
            local msg
            if item.shopCategory == "礼包" or data.isGiftPack then
                local giftName  = item.giftItem or "物品"
                local giftTotal = (item.giftCount or 1) * count
                msg = "购买成功：" .. item.name .. "，获得" .. giftName .. "×" .. giftTotal
            else
                msg = "购买成功：" .. item.name .. " x" .. count
            end
            GamePlayer.AddLog(msg)
            GamePlayer.MarkDirty()
            GameQuest.SetMainFlag("purchased", true)
            Toast.Show(msg)
        else
            Toast.Show(data.msg or "购买失败", "error")
        end
    end, { loading = true })
    return true, nil
end

--- 检查背包物品能否上架
---@param itemIndex number 背包索引
---@param price number 定价
---@param count number 数量
---@return boolean ok, string|nil reason, string|nil currencyKey
function M.CanListItem(itemIndex, price, count)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载", nil end

    local config = DataItems.TRADING_POST
    local items = p.bagItems or {}
    if itemIndex < 1 or itemIndex > #items then return false, "无效的物品", nil end

    local item = items[itemIndex]
    if (item.count or 1) < count then return false, "物品数量不足", nil end
    if price <= 0 then return false, "定价必须大于0", nil end

    -- P3: 物品交易类型校验
    local tradable, currKey, tradeReason = M.GetBagItemTradeInfo(item)
    if not tradable then return false, tradeReason or "该物品不可交易", nil end

    -- P3: 仙石交易限制检查
    if currKey == "spiritStone" then
        local limitOk, limitReason = M.CheckSpiritStoneTradeLimit()
        if not limitOk then return false, limitReason, nil end
    end

    -- 寄售栏位检查
    p.tradingListings = p.tradingListings or {}
    local activeCount = 0
    for _, l in ipairs(p.tradingListings) do
        if l.status == "selling" then activeCount = activeCount + 1 end
    end
    if activeCount >= config.maxListings then
        return false, "寄售栏位已满（最多" .. config.maxListings .. "个）", nil
    end

    return true, nil, currKey
end

--- 检查法宝能否上架（P3新增）
---@param artifactIndex number artifacts 数组索引
---@param price number
---@return boolean ok, string|nil reason, string|nil currencyKey
function M.CanListArtifact(artifactIndex, price)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载", nil end

    local config = DataItems.TRADING_POST
    local arts = p.artifacts or {}
    if artifactIndex < 1 or artifactIndex > #arts then return false, "无效的法宝", nil end

    local art = arts[artifactIndex]
    local tradable, currKey, tradeReason = M.GetArtifactTradeInfo(art)
    if not tradable then return false, tradeReason, nil end
    if price <= 0 then return false, "定价必须大于0", nil end

    -- 仙石交易限制
    if currKey == "spiritStone" then
        local limitOk, limitReason = M.CheckSpiritStoneTradeLimit()
        if not limitOk then return false, limitReason, nil end
    end

    -- 栏位检查
    p.tradingListings = p.tradingListings or {}
    local activeCount = 0
    for _, l in ipairs(p.tradingListings) do
        if l.status == "selling" then activeCount = activeCount + 1 end
    end
    if activeCount >= config.maxListings then
        return false, "寄售栏位已满（最多" .. config.maxListings .. "个）", nil
    end

    return true, nil, currKey
end

---@param itemIndex number
---@param price number
---@param count number
---@return boolean, string
function M.DoListItem(itemIndex, price, count)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    local currKey
    if not IsNetworkMode() then
        local ok, reason, ck = M.CanListItem(itemIndex, price, count)
        if not ok then return false, reason or "无法上架" end
        currKey = ck
    else
        -- 网络模式：仅做最基本的参数检查，服务端会做完整验证
        local p = GamePlayer.Get()
        if not p or not p.bagItems or not p.bagItems[itemIndex] then
            return false, "物品不存在"
        end
        local _, ck = M.GetBagItemTradeInfo(p.bagItems[itemIndex])
        currKey = ck or "lingStone"
    end

    local p = GamePlayer.Get()
    local item = p.bagItems[itemIndex]

    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"]   = Variant("list")
    data["ItemName"] = Variant(item.name)
    data["Price"]    = Variant(price)
    data["Count"]    = Variant(count)
    data["Rarity"]   = Variant(item.rarity or "common")
    data["Desc"]     = Variant(item.desc or "")
    data["Currency"] = Variant(currKey or "lingStone")
    data["ItemType"] = Variant("bagItem")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)

    -- 仙石交易记录
    if currKey == "spiritStone" then M.RecordSpiritStoneTrade() end

    -- 注意：不再客户端先行移除物品+SaveCritical
    -- 物品移除由服务端确认后通过 sync 回传
    return true, "上架请求已发送"
end

--- 上架法宝（P3新增）
---@param artifactIndex number
---@param price number
---@return boolean, string
function M.DoListArtifact(artifactIndex, price)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    local currKey
    if not IsNetworkMode() then
        local ok, reason, ck = M.CanListArtifact(artifactIndex, price)
        if not ok then return false, reason or "无法上架" end
        currKey = ck
    else
        -- 网络模式：仅做最基本的参数检查，服务端会做完整验证
        local p = GamePlayer.Get()
        if not p or not p.artifacts or not p.artifacts[artifactIndex] then
            return false, "法宝不存在"
        end
        local _, ck = M.GetArtifactTradeInfo(p.artifacts[artifactIndex])
        currKey = ck or "lingStone"
    end

    local p = GamePlayer.Get()
    local art = p.artifacts[artifactIndex]

    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"]   = Variant("list")
    data["ItemName"] = Variant(art.name)
    data["Price"]    = Variant(price)
    data["Count"]    = Variant(1)
    data["Rarity"]   = Variant(art.quality or "fanqi")
    data["Desc"]     = Variant(DataItems.GetQualityLabel(art.quality) .. " " .. (art.effect or ""))
    data["Currency"] = Variant(currKey or "lingStone")
    data["ItemType"] = Variant("artifact")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)

    -- 仙石交易记录
    if currKey == "spiritStone" then M.RecordSpiritStoneTrade() end

    -- 注意：不再客户端先行移除法宝+SaveCritical
    -- 法宝移除由服务端确认后通过 sync 回传
    return true, "上架请求已发送"
end

function M.DoDelistItem(listingIndex, listing)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    if not listing or not listing.listId then
        return false, "无效的寄售"
    end
    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"] = Variant("delist")
    data["ListId"] = Variant(tostring(listing.listId))
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)
    return true, "下架请求已发送"
end

function M.DoBuyListing(item)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end
    if not item then return false, "无效的物品" end
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    -- P3: 根据 listing 的 currency 字段判断使用哪种货币
    local currKey   = item.currency or "lingStone"
    local feeRate   = DataItems.GetTradeFeeRate(currKey)
    local totalCost = item.price * (item.stock or 1)
    local fee       = math.floor(totalCost * feeRate)
    local finalCost = totalCost + fee
    local currLabel = M.GetCurrencyLabel(currKey)

    local balance = GamePlayer.GetCurrency(currKey)
    if balance < finalCost then
        return false, currLabel .. "不足"
    end
    if not item.listId then return false, "无效的寄售" end

    -- P3: 仙石交易限制检查
    if currKey == "spiritStone" then
        local limitOk, limitReason = M.CheckSpiritStoneTradeLimit()
        if not limitOk then return false, limitReason end
    end

    -- 容量预检查：背包满时拒绝（可堆叠且已有同名物品除外）
    local GameItems = require("game_items")
    if GameItems.IsBagFull() then
        local existing = false
        for _, bi in ipairs(p.bagItems or {}) do
            if bi.name == item.name then existing = true; break end
        end
        if not existing then
            return false, "储物戒已满，请先整理背包或扩容后再购买"
        end
    end

    GamePlayer.AddCurrency(currKey, -finalCost)
    M.AddItemToPlayer(item)
    GamePlayer.MarkDirty()

    -- 仙石交易记录
    if currKey == "spiritStone" then M.RecordSpiritStoneTrade() end

    M.pendingBuy_ = {
        listId    = item.listId,
        finalCost = finalCost,
        currency  = currKey,
        itemName  = item.name,
        itemCount = item.stock or 1,
        rarity    = item.rarity or "common",
        desc      = item.desc or "",
    }

    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"] = Variant("buy")
    data["ListId"] = Variant(tostring(item.listId))
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)

    Toast.Show("购买请求已发送", "info")
    return true, "购买请求已发送"
end

function M.AddItemToPlayer(item)
    local p = GamePlayer.Get()
    if not p then return end

    -- 根据 itemType 字段判断物品类型（优先），回退到 ARTIFACTS 表查找
    local isArtifact = item.itemType == "artifact"
    if not isArtifact and not item.itemType then
        -- 兼容旧数据：无 itemType 字段时查 ARTIFACTS 表
        for _, a in ipairs(DataItems.ARTIFACTS or {}) do
            if a.name == item.name then isArtifact = true; break end
        end
    end

    if isArtifact then
        local artDef = nil
        for _, a in ipairs(DataItems.ARTIFACTS or {}) do
            if a.name == item.name then artDef = a; break end
        end
        if artDef then
            GamePlayer.AddArtifact(artDef)
        end
    else
        local count = item.stock or item.count or 1
        GamePlayer.AddItem({
            name   = item.name,
            count  = count,
            rarity = item.rarity or "common",
            desc   = item.desc or "",
        })
    end
end

-- ============================================================================
-- 请求服务端数据
-- ============================================================================

function M.RequestBrowseListings()
    if not IsNetworkMode() then return end
    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"] = Variant("browse")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)
end

function M.RequestMyListings()
    if not IsNetworkMode() then return end
    local Shared = require("network.shared")
    local ClientNet = require("network.client_net")
    local data = VariantMap()
    data["Action"] = Variant("myList")
    ClientNet.SendToServer(Shared.EVENTS.REQ_MARKET_OP, data)
end

---@return table|nil
function M.GetServerListings()
    return M.serverListings_
end

---@return table|nil
function M.GetMyListings()
    return M.myListings_
end

-- ============================================================================
-- 服务端回调处理（由 client_net.lua 中转调用）
-- ============================================================================

---@param eventData any
function M.OnMarketData(eventData)
    local action  = eventData["Action"]:GetString()
    local success = false
    local msg     = ""

    -- browse / myList 返回的是 Data 字段（JSON 列表）
    if action == "browse" then
        local json = eventData["Data"]:GetString()
        local ok2, listings = pcall(cjson.decode, json)
        if ok2 and type(listings) == "table" then
            M.serverListings_ = listings
            print("[GameMarket] 寄售列表更新, 共 " .. #listings .. " 条")
        end
        require("ui_router").RebuildUI()
        return

    elseif action == "myList" then
        local json = eventData["Data"]:GetString()
        local ok2, listings = pcall(cjson.decode, json)
        if ok2 and type(listings) == "table" then
            M.myListings_ = listings
            print("[GameMarket] 我的寄售更新, 共 " .. #listings .. " 条")
        end
        require("ui_router").RebuildUI()
        return
    end

    -- 其他操作返回 Success + Msg
    success = eventData["Success"]:GetBool()
    msg     = eventData["Msg"]:GetString()

    if action == "list" then
        if success then
            Toast.Show("上架成功", "success")
            GamePlayer.AddLog(msg)
            M.RequestMyListings()
            M.RequestBrowseListings()
        else
            Toast.Show(msg, "error")
        end

    elseif action == "delist" then
        if success then
            -- 退回背包（法宝退回 artifacts，其他退回 bagItems）
            local itemName  = eventData["ItemName"]:GetString()
            local itemCount = eventData["ItemCount"]:GetInt()
            local rarity    = eventData["Rarity"]:GetString()
            local desc      = eventData["Desc"]:GetString()
            local itemType  = eventData["ItemType"]:GetString()
            -- 根据 itemType 判断退回类型
            if itemType == "artifact" then
                local artDef = nil
                for _, a in ipairs(DataItems.ARTIFACTS or {}) do
                    if a.name == itemName then artDef = a; break end
                end
                if artDef then
                    GamePlayer.AddArtifact(artDef)
                end
            else
                for _ = 1, itemCount do
                    GamePlayer.AddItem({
                        name   = itemName,
                        count  = 1,
                        rarity = rarity,
                        desc   = desc,
                    })
                end
            end
            GamePlayer.MarkDirty()
            Toast.Show("下架成功，物品已退回", "success")
            GamePlayer.AddLog("下架<c=gold>" .. itemName .. "</c>，已退回")
        else
            Toast.Show(msg, "error")
        end

    elseif action == "buy" then
        if success then
            -- 乐观更新已完成，确认成功
            local itemName  = eventData["ItemName"]:GetString()
            local itemCount = eventData["ItemCount"]:GetInt()
            M.pendingBuy_ = nil
            Toast.Show("购买成功: <c=gold>" .. itemName .. " x" .. itemCount .. "</c>", "success")
            GamePlayer.AddLog("购买寄售<c=gold>" .. itemName .. "x" .. itemCount .. "</c>")
            GameQuest.SetMainFlag("purchased", true)
        else
            -- 失败：回滚乐观更新
            M.RollbackPendingBuy()
            Toast.Show(msg, "error")
        end

    elseif action == "soldNotify" then
        Toast.Show(msg, "success")
        GamePlayer.AddLog(msg)

    else
        if success then
            Toast.Show(msg, "success")
        else
            Toast.Show(msg, "error")
        end
    end
end

--- 回滚乐观更新（购买失败时调用）
function M.RollbackPendingBuy()
    local pending = M.pendingBuy_
    if not pending then return end

    -- 退币（使用购买时记录的货币类型）
    local currKey = pending.currency or "lingStone"
    GamePlayer.AddCurrency(currKey, pending.finalCost)
    -- 移除物品（法宝从 artifacts 移除，丹药从 pills，其他从 bagItems）
    local p = GamePlayer.Get()
    if p then
        -- 检查是否为法宝
        local isArtifact = false
        for _, a in ipairs(DataItems.ARTIFACTS or {}) do
            if a.name == pending.itemName then isArtifact = true; break end
        end
        if isArtifact then
            local arts = p.artifacts or {}
            for i = #arts, 1, -1 do
                if arts[i].name == pending.itemName then
                    table.remove(arts, i)
                    break
                end
            end
        else
            local pillDef = DataItems.FindPillByName(pending.itemName)
            if pillDef then
                for _, pill in ipairs(p.pills or {}) do
                    if pill.name == pending.itemName then
                        pill.count = (pill.count or 0) - pending.itemCount
                        if pill.count <= 0 then pill.count = 0 end
                        break
                    end
                end
            else
                -- 移除 bagItems 中最后添加的同名物品
                local removed = 0
                local items = p.bagItems or {}
                for i = #items, 1, -1 do
                    if items[i].name == pending.itemName and removed < pending.itemCount then
                        table.remove(items, i)
                        removed = removed + 1
                    end
                end
            end
        end
        GamePlayer.MarkDirty()
    end

    M.pendingBuy_ = nil
    print("[GameMarket] 已回滚乐观更新: " .. pending.itemName)
end

return M
