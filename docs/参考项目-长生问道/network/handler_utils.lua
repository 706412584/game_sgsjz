-- ============================================================================
-- 《问道长生》服务端公共工具
-- 职责：效果解析、效果应用、派生属性刷新、售价常量
-- 说明：由各 handler 模块 require，不注册到 handlerModules 数组
-- ============================================================================

local M = {}

-- ============================================================================
-- 品质售价常量（与客户端 game_items.lua 保持一致）
-- ============================================================================
M.SELL_PRICE = {
    -- 新品阶 key（与 data_items.lua 保持一致）
    fanqi     = 5,
    lingbao   = 15,
    xtlingbao = 50,
    huangqi   = 150,
    diqi      = 500,
    xianqi    = 2000,
    xtxianqi  = 5000,
    shenqi    = 15000,
    xtshenqi  = 50000,
    -- 旧品阶 key（兼容存量数据）
    common    = 5,
    uncommon  = 15,
    rare      = 50,
    epic      = 150,
    legend    = 500,
    mythic    = 2000,
}

-- ============================================================================
-- 效果字符串解析器（移植自 game_items.lua ParseEffect）
-- 支持格式: "修为+200", "气血+50(永久)", "攻击+10, 速度+5" 等
-- ============================================================================

---@param effectStr string
---@return table[] { {key=string, value=number}, ... }
function M.ParseEffect(effectStr)
    if not effectStr or effectStr == "" then return {} end
    local results = {}

    -- 模式1: "关键字+数值" 或 "关键字-数值"
    for keyword, sign, num in effectStr:gmatch("(%D+)([%+%-])(%d+)") do
        -- 去掉前导标点/空格（处理 "攻击+10, 速度+5" 中第二词条前的 ", "）
        keyword = keyword:match("^[%p%s]*(.-)%s*$") or keyword
        local val = tonumber(num) or 0
        if sign == "-" then val = -val end
        results[#results + 1] = { key = keyword, value = val }
    end

    -- 模式2: "灵力恢复100" 格式（无符号）
    if #results == 0 then
        for keyword, num in effectStr:gmatch("(%D+)(%d+)") do
            keyword = keyword:match("^[%p%s]*(.-)%s*$") or keyword
            local val = tonumber(num) or 0
            results[#results + 1] = { key = keyword, value = val }
        end
    end

    return results
end

-- ============================================================================
-- 效果应用到 playerData（服务端版，直接修改 table）
-- ============================================================================

--- 安全取数值：防止 serverCloud 返回的字段是 string 类型
---@param val any
---@param default number
---@return number
local function safeNum(val, default)
    return tonumber(val) or default
end

---@param playerData table
---@param effectStr string
---@return string effectMsg, table[] moneyRewards -- moneyRewards: { {currency=string, amount=number}, ... }
function M.ApplyEffectToData(playerData, effectStr)
    local effects = M.ParseEffect(effectStr)
    if #effects == 0 then return "", {} end

    local msgs = {}
    local moneyRewards = {}
    for _, e in ipairs(effects) do
        local k, v = e.key, e.value
        if k == "修为" then
            playerData.cultivation = safeNum(playerData.cultivation, 0) + v
            msgs[#msgs + 1] = "修为+" .. v
        elseif k == "气血" or k == "气血恢复" then
            playerData.hp = math.min(
                safeNum(playerData.hpMax, 800),
                safeNum(playerData.hp, 0) + v
            )
            msgs[#msgs + 1] = "气血恢复+" .. v
        elseif k == "气血上限" then
            playerData.hpMax = safeNum(playerData.hpMax, 800) + v
            msgs[#msgs + 1] = "气血上限+" .. v
        elseif k == "灵力" or k == "灵力恢复" then
            playerData.mp = math.min(
                safeNum(playerData.mpMax, 200),
                safeNum(playerData.mp, 0) + v
            )
            msgs[#msgs + 1] = "灵力恢复" .. v
        elseif k == "灵石" then
            moneyRewards[#moneyRewards + 1] = { currency = "lingStone", amount = v }
            msgs[#msgs + 1] = "灵石+" .. v
        elseif k == "攻击" then
            playerData.attack = safeNum(playerData.attack, 0) + v
            msgs[#msgs + 1] = "攻击+" .. v
        elseif k == "防御" then
            playerData.defense = safeNum(playerData.defense, 0) + v
            msgs[#msgs + 1] = "防御+" .. v
        elseif k == "速度" then
            playerData.speed = safeNum(playerData.speed, 0) + v
            msgs[#msgs + 1] = "速度+" .. v
        elseif k == "神识" then
            playerData.sense = safeNum(playerData.sense, 0) + v
            msgs[#msgs + 1] = "神识+" .. v
        elseif k == "悟性" then
            playerData.wisdom = safeNum(playerData.wisdom, 0) + v
            msgs[#msgs + 1] = "悟性+" .. v
        elseif k == "气运" then
            playerData.fortune = safeNum(playerData.fortune, 0) + v
            msgs[#msgs + 1] = "气运+" .. v
        elseif k == "寿元" then
            playerData.lifespan = safeNum(playerData.lifespan, 0) + v
            playerData.gameYear = safeNum(playerData.gameYear, 1) + v
            msgs[#msgs + 1] = "寿元+" .. v
        elseif k == "灵力上限" then
            playerData.mpMax = safeNum(playerData.mpMax, 200) + v
            msgs[#msgs + 1] = "灵力上限+" .. v
        elseif k == "暴击" then
            playerData.crit = safeNum(playerData.crit, 0) + v
            msgs[#msgs + 1] = "暴击+" .. v
        elseif k == "全属性" then
            playerData.attack  = safeNum(playerData.attack, 0) + v
            playerData.defense = safeNum(playerData.defense, 0) + v
            playerData.speed   = safeNum(playerData.speed, 0) + v
            playerData.sense   = safeNum(playerData.sense, 0) + v
            playerData.wisdom  = safeNum(playerData.wisdom, 0) + v
            msgs[#msgs + 1] = "全属性+" .. v
        elseif k == "道心" then
            playerData.daoHeart = safeNum(playerData.daoHeart, 0) + v
            msgs[#msgs + 1] = "道心+" .. v
        end
    end

    return table.concat(msgs, ", "), moneyRewards
end

-- ============================================================================
-- 异步发放货币奖励（链式调用 money:Add，完成后执行回调）
-- ============================================================================

---@param userId any
---@param moneyRewards table[] { {currency=string, amount=number}, ... }
---@param callback fun(balances: table|nil) -- balances: { lingStone=N, spiritStone=N }
function M.GrantMoneyRewards(userId, moneyRewards, callback)
    if #moneyRewards == 0 then
        callback(nil)
        return
    end

    local idx = 0
    local function doNext()
        idx = idx + 1
        if idx > #moneyRewards then
            -- 所有货币发放完毕，查询最新余额
            serverCloud.money:Get(userId, {
                ok = function(moneys)
                    local balances = {}
                    for _, mr in ipairs(moneyRewards) do
                        balances[mr.currency] = (moneys and moneys[mr.currency]) or 0
                    end
                    callback(balances)
                end,
                error = function()
                    callback(nil)
                end,
            })
            return
        end

        local mr = moneyRewards[idx]
        serverCloud.money:Add(userId, mr.currency, mr.amount, {
            ok = function() doNext() end,
            error = function(code, reason)
                print("[GrantMoneyRewards] money:Add " .. mr.currency .. " 失败: " .. tostring(reason))
                doNext()
            end,
        })
    end

    doNext()
end

-- ============================================================================
-- 派生属性重算（服务端版，与客户端 AttachDerived 对齐）
-- 注意：服务端不需要 realmName/cultivationMax/lifespanMax/power 这些展示字段
-- 但 sync 给客户端后客户端的 AttachDerived 会自动补充
-- ============================================================================

---@param playerData table
function M.RefreshDerived(playerData)
    -- 服务端目前不需要计算派生字段
    -- 客户端 ApplySync 后会自动调用 AttachDerived
    -- 预留接口以便将来扩展
end

-- ============================================================================
-- 法宝强化增幅百分比计算（移植自 game_artifact.lua GetEnhancePct）
-- ============================================================================

---@param level number
---@param enhanceTable table[] DataItems.ENHANCE_TABLE
---@return number pct
function M.GetEnhancePct(level, enhanceTable)
    if level <= 1 then return 0 end
    local total = 0
    for lv = 1, level - 1 do
        local info = enhanceTable[lv]
        if info then total = total + info.pct end
    end
    return total
end

-- ============================================================================
-- 法宝效果应用/移除到 playerData（装备/卸下时用）
-- ============================================================================

---@param playerData table
---@param art table 法宝数据
---@param enhanceTable table[] DataItems.ENHANCE_TABLE
---@param sign number 1=应用, -1=移除
function M.ApplyArtifactEffectToData(playerData, art, enhanceTable, sign)
    if not art or not art.effect then return end
    local enhancePct = M.GetEnhancePct(art.level or 1, enhanceTable)
    local effects = M.ParseEffect(art.effect)
    for _, e in ipairs(effects) do
        local boosted = math.floor(e.value * (1 + enhancePct / 100))
        local delta = boosted * sign
        local k = e.key
        if k == "攻击" then
            playerData.attack = (playerData.attack or 0) + delta
        elseif k == "防御" then
            playerData.defense = (playerData.defense or 0) + delta
        elseif k == "速度" then
            playerData.speed = (playerData.speed or 0) + delta
        elseif k == "灵力上限" then
            playerData.mpMax = (playerData.mpMax or 200) + delta
        elseif k == "暴击" then
            playerData.crit = (playerData.crit or 0) + delta
        end
    end
end

-- ============================================================================
-- 装备属性应用/移除（穿戴/脱下时用）
-- 装备数据格式: { baseAtk, baseDef, baseCrit, baseSpd, extraStats = { {stat, value}, ... } }
-- ============================================================================

--- 将装备属性加到/从 playerData 上
---@param playerData table
---@param equip table 装备数据
---@param sign number 1=穿戴(加), -1=脱下(减)
function M.ApplyEquipStatsToData(playerData, equip, sign)
    if not equip then return end
    -- 基础属性
    if (equip.baseAtk or 0) ~= 0 then
        playerData.attack = (playerData.attack or 0) + equip.baseAtk * sign
    end
    if (equip.baseDef or 0) ~= 0 then
        playerData.defense = (playerData.defense or 0) + equip.baseDef * sign
    end
    if (equip.baseCrit or 0) ~= 0 then
        playerData.crit = (playerData.crit or 0) + equip.baseCrit * sign
    end
    if (equip.baseSpd or 0) ~= 0 then
        playerData.speed = (playerData.speed or 0) + equip.baseSpd * sign
    end
    -- 附加属性
    for _, es in ipairs(equip.extraStats or {}) do
        local stat = es.stat
        local val  = (es.value or 0) * sign
        if stat == "attack" then
            playerData.attack = (playerData.attack or 0) + val
        elseif stat == "defense" then
            playerData.defense = (playerData.defense or 0) + val
        elseif stat == "hp" then
            playerData.hpMax = (playerData.hpMax or 800) + val
            if sign > 0 then
                playerData.hp = math.min(playerData.hpMax, (playerData.hp or 0) + val)
            else
                playerData.hp = math.min(playerData.hpMax, playerData.hp or 0)
            end
        elseif stat == "crit" then
            playerData.crit = (playerData.crit or 0) + val
        elseif stat == "speed" then
            playerData.speed = (playerData.speed or 0) + val
        elseif stat == "dodge" then
            playerData.dodge = (playerData.dodge or 0) + val
        elseif stat == "hit" then
            playerData.hit = (playerData.hit or 0) + val
        end
    end
end

return M
