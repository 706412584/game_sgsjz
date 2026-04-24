-- ============================================================================
-- 《问道长生》物品操作模块
-- 职责：丹药服用、背包整理/出售/使用、效果字符串解析
-- 设计：Can/Do 模式，所有操作先检查后执行
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- 品质 → 出售基础价（新9品阶 + 旧key兼容）
local SELL_PRICE = {
    -- 新品阶key
    fanqi     = 5,
    lingbao   = 15,
    xtlingbao = 50,
    huangqi   = 150,
    diqi      = 500,
    xianqi    = 2000,
    xtxianqi  = 5000,
    shenqi    = 15000,
    xtshenqi  = 50000,
    -- 旧key兼容
    common   = 5,
    uncommon = 15,
    rare     = 50,
    epic     = 150,
    legend   = 500,
    mythic   = 2000,
}

-- ============================================================================
-- 分类查询
-- ============================================================================

--- 获取物品的实际分类（优先用字段，无则推断）
---@param item table
---@return string category, string|nil subType
local function resolveCategory(item)
    if item.category then
        return item.category, item.subType
    end
    local cat, sub = DataItems.InferCategory(item.name)
    -- 顺便回写，减少后续推断
    item.category = cat
    item.subType  = sub
    return cat, sub
end

--- 获取指定分类的背包物品
---@param category string "fabao"|"material"|"item"|"pet"
---@param subTab? string 子分类标签（如 "头戴"、"丹药"）
---@return table[]
function M.GetItemsByCategory(category, subTab)
    local p = GamePlayer.Get()
    if not p then return {} end
    local items = p.bagItems or {}
    local result = {}
    for _, item in ipairs(items) do
        local cat, sub = resolveCategory(item)
        if cat == category then
            -- "全部"标签下过滤掉丹药（丹药在专属丹药页管理）
            if subTab == nil then
                if sub ~= "丹药" then
                    result[#result + 1] = item
                end
            elseif (sub or "") == subTab then
                result[#result + 1] = item
            end
        end
    end
    return result
end

--- 获取各分类的物品数量（用于标签页角标）
---@return table<string, number>
function M.GetCategoryCounts()
    local p = GamePlayer.Get()
    if not p then return {} end
    local counts = {}
    for _, item in ipairs(p.bagItems or {}) do
        local cat, sub = resolveCategory(item)
        -- 丹药在专属丹药页管理，不计入物品分类数量
        if sub ~= "丹药" then
            counts[cat] = (counts[cat] or 0) + 1
        end
    end
    return counts
end

--- 确保背包中所有物品都有 category/subType 字段（兼容旧数据迁移）
function M.MigrateBagCategories()
    local p = GamePlayer.Get()
    if not p then return end
    local changed = false
    for _, item in ipairs(p.bagItems or {}) do
        if not item.category then
            item.category, item.subType = DataItems.InferCategory(item.name)
            changed = true
        end
    end
    if changed then GamePlayer.MarkDirty() end
end

-- ============================================================================
-- 背包容量 & 扩容
-- ============================================================================

--- 获取当前背包容量
---@return number
function M.GetBagCapacity()
    local p = GamePlayer.Get()
    if not p then return DataItems.BAG_EXPAND.initialCapacity end
    return p.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
end

--- 获取当前已用格数
---@return number
function M.GetBagUsed()
    local p = GamePlayer.Get()
    if not p then return 0 end
    return #(p.bagItems or {})
end

--- 获取扩容费用
---@return number cost, string currency
function M.GetExpandCost()
    local cap = M.GetBagCapacity()
    local cost = cap * DataItems.BAG_EXPAND.costPerSlot
    return cost, "灵石"
end

--- 检查是否可以扩容
---@return boolean, string|nil
function M.CanExpandBag()
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local cap = p.bagCapacity or DataItems.BAG_EXPAND.initialCapacity
    if cap >= DataItems.BAG_EXPAND.maxCapacity then
        return false, "已达容量上限(" .. DataItems.BAG_EXPAND.maxCapacity .. "格)"
    end
    local cost = cap * DataItems.BAG_EXPAND.costPerSlot
    if (p.lingStone or 0) < cost then
        return false, "灵石不足(需" .. cost .. ")"
    end
    return true, nil
end

--- 执行扩容
---@param callback? fun(ok: boolean)  服务端响应后的回调（用于刷新UI）
---@return boolean, string
function M.DoExpandBag(callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false) end
        return false, onlineErr
    end

    local ok, reason = M.CanExpandBag()
    if not ok then
        if callback then callback(false) end
        return false, reason or "无法扩容"
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    local Toast = require("ui_toast")
    GameOps.Request("item_expand_bag", {
        playerKey = GameServer.GetServerKey("player"),
    }, function(ok2, data)
        if ok2 then
            GamePlayer.AddLog("<c=gold>背包扩容</c>: " .. (data and data.msg or "扩容成功"))
            Toast.Show(data and data.msg or "扩容成功")
        else
            Toast.Show(data and data.msg or "扩容失败", "error")
        end
        if callback then callback(ok2) end
    end, { loading = true })
    return true, nil
end

function M.IsBagFull()
    return M.GetBagUsed() >= M.GetBagCapacity()
end

-- ============================================================================
-- 物品锁定
-- ============================================================================

--- 切换物品锁定状态
---@param index number
---@return boolean success, string msg
function M.ToggleLock(index)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local item = (p.bagItems or {})[index]
    if not item then return false, "无效的物品索引" end
    item.locked = not (item.locked or false)
    GamePlayer.MarkDirty()
    local state = item.locked and "锁定" or "解锁"
    return true, item.name .. "已" .. state
end

-- ============================================================================
-- 回收面板
-- ============================================================================

--- 获取符合回收条件的物品（按品质筛选，排除已锁定）
---@param selectedQualities table<string, boolean> 如 { common=true, uncommon=true }
---@return table[] items, number totalPrice
function M.GetRecyclableItems(selectedQualities)
    local p = GamePlayer.Get()
    if not p then return {}, 0 end
    local result = {}
    local totalPrice = 0
    for i, item in ipairs(p.bagItems or {}) do
        local rarity = item.rarity or "common"
        if selectedQualities[rarity] and not item.locked then
            result[#result + 1] = { index = i, item = item }
            local unitPrice = SELL_PRICE[rarity] or 5
            totalPrice = totalPrice + unitPrice * (item.count or 1)
        end
    end
    return result, totalPrice
end

--- 执行批量回收（按品质，排除锁定物品）
---@param selectedQualities table<string, boolean>
---@param callback? fun(ok: boolean)  服务端响应后的回调（用于刷新UI）
---@return boolean, string
function M.DoRecycle(selectedQualities, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false) end
        return false, onlineErr
    end

    local p = GamePlayer.Get()
    if not p then
        if callback then callback(false) end
        return false, "数据未加载"
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("item_recycle", {
        playerKey         = GameServer.GetServerKey("player"),
        selectedQualities = selectedQualities,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.AddLog(data and data.msg or "回收完成")
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "回收完成")
        else
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "回收失败", "error")
        end
        if callback then callback(ok2) end
    end, { loading = true })
    return true, nil
end

-- 品质权重（排序用，值越高越靠前；新9品阶 + 旧key兼容）
local QUALITY_WEIGHT = {
    -- 新品阶key
    xtshenqi  = 90,
    shenqi    = 80,
    xtxianqi  = 70,
    xianqi    = 60,
    diqi      = 50,
    huangqi   = 40,
    xtlingbao = 30,
    lingbao   = 20,
    fanqi     = 10,
    -- 旧key兼容
    mythic   = 60,
    legend   = 50,
    epic     = 40,
    rare     = 30,
    uncommon = 20,
    common   = 10,
}

-- ============================================================================
-- 效果字符串解析器
-- 支持格式: "修为+200", "气血+50(永久)", "攻击+10(永久)", "灵力恢复100" 等
-- ============================================================================

--- 解析效果字符串为 { {key, value}, ... }
---@param effectStr string
---@return table[]
function M.ParseEffect(effectStr)
    if not effectStr or effectStr == "" then return {} end
    local results = {}

    -- 模式1: "关键字+数值" 或 "关键字-数值"（如 "修为+200"）
    for keyword, sign, num in effectStr:gmatch("(%D+)([%+%-])(%d+)") do
        -- 去除括号等非中文后缀
        keyword = keyword:match("^(.-)%s*$") or keyword
        local val = tonumber(num) or 0
        if sign == "-" then val = -val end
        results[#results + 1] = { key = keyword, value = val }
    end

    -- 模式2: "灵力恢复100" 格式（关键字+数值，无符号）
    if #results == 0 then
        for keyword, num in effectStr:gmatch("(%D+)(%d+)") do
            keyword = keyword:match("^(.-)%s*$") or keyword
            local val = tonumber(num) or 0
            results[#results + 1] = { key = keyword, value = val }
        end
    end

    return results
end

--- 应用效果到玩家数据
---@param effectStr string
---@return string 应用结果描述
function M.ApplyEffect(effectStr)
    local effects = M.ParseEffect(effectStr)
    if #effects == 0 then return "" end

    local p = GamePlayer.Get()
    if not p then return "" end

    local msgs = {}
    for _, eff in ipairs(effects) do
        local k, v = eff[1], eff[2]
        if k == "修为" then
            GamePlayer.AddCultivation(v)
            msgs[#msgs + 1] = "修为+" .. v
        elseif k == "气血" then
            GamePlayer.HealHP(v)
            msgs[#msgs + 1] = "气血恢复" .. v
        elseif k == "气血上限" then
            p.maxHp = (p.maxHp or 100) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "气血上限+" .. v
        elseif k == "灵力" or k == "灵力恢复" then
            GamePlayer.HealMP(v)
            msgs[#msgs + 1] = "灵力恢复" .. v
        elseif k == "灵石" then
            local GameOps = require("network.game_ops")
            GameOps.Request("currency_add", {
                currency = "lingStone", amount = v, reason = "item_effect",
            })
            msgs[#msgs + 1] = "灵石+" .. v
        elseif k == "攻击" then
            p.attack = (p.attack or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "攻击+" .. v
        elseif k == "防御" then
            p.defense = (p.defense or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "防御+" .. v
        elseif k == "速度" then
            p.speed = (p.speed or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "速度+" .. v
        elseif k == "神识" then
            p.sense = (p.sense or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "神识+" .. v
        elseif k == "悟性" then
            p.wisdom = (p.wisdom or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "悟性+" .. v
        elseif k == "气运" then
            p.fortune = (p.fortune or 0) + v
            GamePlayer.MarkDirty()
            msgs[#msgs + 1] = "气运+" .. v
        elseif k == "寿元" then
            GamePlayer.AddLifespan(v)
            msgs[#msgs + 1] = "寿元+" .. v
        end
    end

    return table.concat(msgs, ", ")
end

-- ============================================================================
-- 丹药服用
-- ============================================================================

--- 检查是否可以服用某丹药
---@param pillName string
---@return boolean, string|nil
function M.CanUsePill(pillName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local pillsList = p.pills or {}

    -- 在 p.pills 中查找
    local found = nil
    for _, pill in ipairs(pillsList) do
        if pill.name == pillName then
            found = pill
            break
        end
    end
    if not found then
        return false, "未拥有该丹药"
    end
    if found.locked then return false, "该丹药暂未解锁" end
    if (found.count or 0) <= 0 then
        return false, "丹药数量不足"
    end

    -- 检查限制丹药的 perRealm 限制
    local def = DataItems.FindPillByName(pillName)
    if def and def.perRealm then
        local usage = GamePlayer.GetPillUsage(pillName)
        if usage >= def.perRealm then
            return false, "本境界已达服用上限(" .. def.perRealm .. "次)"
        end
    end

    return true, nil
end

--- 服用丹药
---@param pillName string
---@return boolean, string
function M.DoUsePill(pillName)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    -- 网络模式：跳过客户端校验，直接走服务端权威验证
    -- 客户端缓存可能滞后于服务端实际数据（竞态/异步导致），
    -- 由服务端 item_use_pill handler 读取 serverCloud 做真实校验
    ---@diagnostic disable-next-line: undefined-global
    if not IsNetworkMode() then
        local ok, reason = M.CanUsePill(pillName)
        if not ok then return false, reason or "无法服用" end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("item_use_pill", {
        playerKey = GameServer.GetServerKey("player"),
        pillName  = pillName,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            GamePlayer.AddLog(data and data.msg or "服用成功")
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "服用成功")
        else
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "服用失败", "error")
        end
        -- 无论成功失败都刷新 UI（同步服务端最新数据到界面）
        local Router = require("ui_router")
        Router.RebuildUI()
    end, { loading = true })
    return true, nil
end

function M.SortBag()
    local p = GamePlayer.Get()
    if not p then return "数据未加载" end

    local items = p.bagItems or {}
    if #items <= 1 then return "背包已整理" end

    table.sort(items, function(a, b)
        local wa = QUALITY_WEIGHT[a.rarity or "common"] or 0
        local wb = QUALITY_WEIGHT[b.rarity or "common"] or 0
        if wa ~= wb then return wa > wb end
        return (a.name or "") < (b.name or "")
    end)

    GamePlayer.MarkDirty()
    return "背包整理完成"
end

--- 检查是否可出售物品
---@param index number
---@return boolean, string|nil
function M.CanSellItem(index)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local items = p.bagItems or {}
    if index < 1 or index > #items then return false, "无效的物品索引" end
    return true, nil
end

--- 出售单件物品
---@param index number
---@param count? number
---@return boolean, string
function M.DoSellItem(index, count)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    local ok, reason = M.CanSellItem(index)
    if not ok then return false, reason or "无法出售" end

    local p = GamePlayer.Get()
    local item = p.bagItems[index]
    local sellCount = math.min(count or 1, item.count or 1)

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("item_sell", {
        playerKey = GameServer.GetServerKey("player"),
        itemIndex = index,
        count     = sellCount,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.AddLog(data and data.msg or "出售成功")
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "出售成功")
        else
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "出售失败", "error")
        end
    end, { loading = true })
    return true, nil
end

function M.PreviewBatchSell(maxQuality)
    local p = GamePlayer.Get()
    if not p then return 0, 0 end
    maxQuality = maxQuality or "uncommon"
    local maxWeight = QUALITY_WEIGHT[maxQuality] or 20
    local items = p.bagItems or {}
    local totalPrice = 0
    local totalCount = 0
    for _, item in ipairs(items) do
        if not item.locked then
            local w = QUALITY_WEIGHT[item.rarity or "common"] or 0
            if w <= maxWeight then
                local unitPrice = SELL_PRICE[item.rarity or "common"] or 5
                local cnt = item.count or 1
                totalPrice = totalPrice + unitPrice * cnt
                totalCount = totalCount + cnt
            end
        end
    end
    return totalCount, totalPrice
end

--- 批量出售指定品质及以下的所有物品
---@param maxQuality? string 最高出售品质key(默认 "uncommon")
---@return boolean, string
function M.DoBatchSell(maxQuality)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    maxQuality = maxQuality or "uncommon"

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("item_batch_sell", {
        playerKey  = GameServer.GetServerKey("player"),
        maxQuality = maxQuality,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.AddLog(data and data.msg or "批量出售完成")
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "批量出售完成")
        else
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "批量出售失败", "error")
        end
    end, { loading = true })
    return true, nil
end

function M.DoUseItem(index)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then return false, onlineErr end

    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local items = p.bagItems or {}
    if index < 1 or index > #items then return false, "无效的物品索引" end

    local item = items[index]

    -- 检查是否是丹药
    local pillDef = DataItems.FindPillByName(item.name)
    if not pillDef then
        return false, item.name .. "无法直接使用"
    end

    -- 走服务端原子操作：背包移除 → 加入pills → 服用
    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("item_use_from_bag", {
        playerKey = GameServer.GetServerKey("player"),
        itemIndex = index,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            GamePlayer.AddLog(data and data.msg or "使用成功")
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "使用成功")
        else
            local Toast = require("ui_toast")
            Toast.Show(data and data.msg or "使用失败", "error")
        end
        local Router = require("ui_router")
        Router.RebuildUI()
    end, { loading = true })
    return true, nil
end

--- 红点查询：是否有任何可使用的丹药
---@return boolean
function M.HasUsablePill()
    local p = GamePlayer.Get()
    if not p then return false end
    for _, pill in ipairs(p.pills or {}) do
        if (pill.count or 0) > 0 then
            local can = M.CanUsePill(pill.name)
            if can then return true end
        end
    end
    return false
end

return M
