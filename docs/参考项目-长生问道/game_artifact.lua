-- ============================================================================
-- 《问道长生》法宝操作模块（500级强化 + 升阶 + 分解）
-- 职责：法宝装备/卸下/强化/升阶/分解
-- 设计：Can/Do 模式，服务端权威（GameOps）
-- ============================================================================

local GamePlayer = require("game_player")
local DataItems  = require("data_items")
local GameItems  = require("game_items")

local M = {}
local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 按名称查找法宝
---@param artName string
---@return table|nil
local function FindArtifact(artName)
    local p = GamePlayer.Get()
    if not p then return nil end
    -- 先在未装备列表中查
    for _, a in ipairs(p.artifacts or {}) do
        if a.name == artName then return a end
    end
    -- 再在已装备槽位中查（装备后法宝从 artifacts 移至 equippedItems）
    for _, a in pairs(p.equippedItems or {}) do
        if type(a) == "table" and a.name == artName then return a end
    end
    return nil
end

-- ============================================================================
-- 装备 / 卸下
-- ============================================================================

--- 检查是否可装备
---@param artName string
---@return boolean, string|nil
function M.CanEquip(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local found = FindArtifact(artName)
    if not found then return false, "未拥有该法宝" end
    if found.equipped then return false, "已经装备中" end
    return true, nil
end

--- 装备法宝（同槽位自动卸下旧法宝）
---@param artName string
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoEquip(artName, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end
    local ok, reason = M.CanEquip(artName)
    if not ok then
        if callback then callback(false, reason or "无法装备") end
        return false, reason or "无法装备"
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_equip", {
        playerKey = GameServer.GetServerKey("player"),
        artName   = artName,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local msg = data and data.msg or "装备成功"
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg) end
        else
            local msg = data and data.msg or "装备失败"
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

---@param artName string
---@param callback? fun(ok: boolean, msg: string)
function M.DoUnequip(artName, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end
    local p = GamePlayer.Get()
    if not p then
        if callback then callback(false, "数据未加载") end
        return false, "数据未加载"
    end
    local found = FindArtifact(artName)
    if not found then
        if callback then callback(false, "未拥有该法宝") end
        return false, "未拥有该法宝"
    end
    if not found.equipped then
        if callback then callback(false, "该法宝未装备") end
        return false, "该法宝未装备"
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_unequip", {
        playerKey = GameServer.GetServerKey("player"),
        artName   = artName,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local msg = data and data.msg or "卸下成功"
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg) end
        else
            local msg = data and data.msg or "卸下失败"
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

-- ============================================================================
-- 效果应用（属性计算）
-- ============================================================================

--- 获取强化等级的总增幅百分比（使用新分段表）
---@param level number
---@return number pct
function M.GetEnhancePct(level)
    return DataItems.GetTotalEnhancePct(level - 1)
end

--- 将副属性 type key 映射到玩家属性字段
local STAT_TYPE_TO_FIELD = {
    attack   = "attack",
    defense  = "defense",
    hp       = "hpMax",
    crit     = "crit",
    speed    = "speed",
    dodge    = "dodge",
    hit      = "hit",
    cultSpeed = "cultSpeedBonus",
    elemDmg  = "elemDmgBonus",
}

--- 中文关键字 → 副属性 type key
local KEYWORD_TO_TYPE = {
    ["攻击"]   = "attack",
    ["防御"]   = "defense",
    ["气血"]   = "hp",
    ["暴击"]   = "crit",
    ["速度"]   = "speed",
    ["闪避"]   = "dodge",
    ["命中"]   = "hit",
    ["灵力上限"] = "hp",
}

--- 应用法宝效果（兼容旧 effect 字符串 + 新 mainStat/subStats）
function M.ApplyArtifactEffect(art)
    if not art then return end
    local p = GamePlayer.Get()
    if not p then return end
    local enhancePct = M.GetEnhancePct(art.level or 1)

    -- 新格式：mainStat + subStats
    if art.mainStat then
        local field = STAT_TYPE_TO_FIELD[art.mainStat.type]
        if field then
            local boosted = math.floor(art.mainStat.value * (1 + enhancePct / 100))
            p[field] = (p[field] or 0) + boosted
        end
    end
    if art.subStats then
        for _, sub in ipairs(art.subStats) do
            local field = STAT_TYPE_TO_FIELD[sub.type]
            if field then
                p[field] = (p[field] or 0) + sub.value
            end
        end
    end

    -- 旧格式：effect 字符串（向下兼容）
    if art.effect and not art.mainStat then
        local effects = GameItems.ParseEffect(art.effect)
        for _, e in ipairs(effects) do
            local boosted = math.floor(e.value * (1 + enhancePct / 100))
            M.ApplyStat(p, e.key, boosted)
        end
    end
    GamePlayer.MarkDirty()
end

--- 移除法宝效果（兼容旧 effect 字符串 + 新 mainStat/subStats）
function M.RemoveArtifactEffect(art)
    if not art then return end
    local p = GamePlayer.Get()
    if not p then return end
    local enhancePct = M.GetEnhancePct(art.level or 1)

    -- 新格式
    if art.mainStat then
        local field = STAT_TYPE_TO_FIELD[art.mainStat.type]
        if field then
            local boosted = math.floor(art.mainStat.value * (1 + enhancePct / 100))
            p[field] = (p[field] or 0) - boosted
        end
    end
    if art.subStats then
        for _, sub in ipairs(art.subStats) do
            local field = STAT_TYPE_TO_FIELD[sub.type]
            if field then
                p[field] = (p[field] or 0) - sub.value
            end
        end
    end

    -- 旧格式
    if art.effect and not art.mainStat then
        local effects = GameItems.ParseEffect(art.effect)
        for _, e in ipairs(effects) do
            local boosted = math.floor(e.value * (1 + enhancePct / 100))
            M.ApplyStat(p, e.key, -boosted)
        end
    end
    GamePlayer.MarkDirty()
end

function M.ApplyStat(p, keyword, value)
    local typeKey = KEYWORD_TO_TYPE[keyword]
    if typeKey then
        local field = STAT_TYPE_TO_FIELD[typeKey]
        if field then
            p[field] = (p[field] or 0) + value
            GamePlayer.MarkDirty()
            return
        end
    end
    -- 直接按关键字匹配（兜底）
    if keyword == "攻击" then
        p.attack = (p.attack or 0) + value
    elseif keyword == "防御" then
        p.defense = (p.defense or 0) + value
    elseif keyword == "速度" then
        p.speed = (p.speed or 0) + value
    elseif keyword == "灵力上限" then
        p.mpMax = (p.mpMax or 200) + value
    elseif keyword == "暴击" then
        p.crit = (p.crit or 0) + value
    end
    GamePlayer.MarkDirty()
end

-- ============================================================================
-- 副属性生成（客户端工具函数，服务端 handler 也有对应逻辑）
-- ============================================================================

--- 随机生成副属性列表
---@param quality string 品阶key
---@param count? number 副属性条数（默认按品阶查表）
---@return table[] subStats
function M.GenerateSubStats(quality, count)
    count = count or DataItems.SUB_STAT_COUNTS[quality] or 1
    local pool = {}
    for _, s in ipairs(DataItems.EXTRA_STAT_POOL) do
        pool[#pool + 1] = s
    end
    local subStats = {}
    for _ = 1, count do
        if #pool == 0 then break end
        local idx = math.random(#pool)
        local statType = pool[idx]
        table.remove(pool, idx)
        local minVal, maxVal = DataItems.GetSubStatRange(statType, quality)
        local value = math.random(minVal, maxVal)
        local sub = { type = statType, value = value }
        -- elemDmg 需要随机分配一个元素
        if statType == "elemDmg" then
            local elements = { "metal", "wood", "water", "fire", "earth" }
            sub.element = elements[math.random(#elements)]
        end
        subStats[#subStats + 1] = sub
    end
    return subStats
end

--- 格式化单条副属性为显示文本
---@param sub table { type, value, element? }
---@return string
function M.FormatSubStat(sub)
    local label = DataItems.STAT_LABEL[sub.type] or sub.type
    local isPct = DataItems.STAT_IS_PERCENT[sub.type]
    if sub.type == "elemDmg" and sub.element then
        local elemLabels = { metal = "金", wood = "木", water = "水", fire = "火", earth = "土" }
        label = (elemLabels[sub.element] or "") .. "属性伤害"
    end
    if isPct then
        return label .. "+" .. sub.value .. "%"
    else
        return label .. "+" .. sub.value
    end
end

--- 格式化主属性为显示文本
---@param mainStat table { type, value }
---@return string
function M.FormatMainStat(mainStat)
    if not mainStat then return "" end
    local label = DataItems.STAT_LABEL[mainStat.type] or mainStat.type
    local isPct = DataItems.STAT_IS_PERCENT[mainStat.type]
    if isPct then
        return label .. "+" .. mainStat.value .. "%"
    else
        return label .. "+" .. mainStat.value
    end
end

-- ============================================================================
-- 洗炼（副属性重随）
-- ============================================================================

--- 检查是否可洗炼
---@param artName string
---@return boolean, string|nil
function M.CanReroll(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local art = FindArtifact(artName)
    if not art then return false, "未拥有该法宝" end

    -- 品阶检查
    local quality = art.quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    if not DataItems.CanRerollQuality(quality) then
        return false, "仅仙器及以上品阶可洗炼"
    end

    -- 境界检查
    local realmTier = 1
    if p.realmTier then
        realmTier = p.realmTier
    elseif p.realm then
        local DataRealms = require("data_realms")
        local info = DataRealms.GetByName(p.realm)
        realmTier = info and info.tier or 1
    end
    if realmTier < DataItems.REROLL_MIN_REALM then
        return false, "需达到元婴境界才可洗炼"
    end

    -- 必须有副属性
    if not art.subStats or #art.subStats == 0 then
        return false, "该法宝无副属性"
    end

    -- 材料检查：灵尘
    local lingchenCount = 0
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == "灵尘" then lingchenCount = item.count or 0; break end
    end
    if lingchenCount < DataItems.REROLL_COST.lingchen then
        return false, "灵尘不足（需要" .. DataItems.REROLL_COST.lingchen .. "）"
    end

    -- 灵石
    if (p.lingStone or 0) < DataItems.REROLL_COST.lingshi then
        return false, "灵石不足（需要" .. DataItems.REROLL_COST.lingshi .. "）"
    end

    -- 锁定费用检查（仙石）
    local lockCount = 0
    if art.locked then
        for _, lk in ipairs(art.locked) do
            if lk then lockCount = lockCount + 1 end
        end
    end
    if lockCount > 0 then
        local lockCost = lockCount * DataItems.REROLL_LOCK_COST
        if (p.xianStone or 0) < lockCost then
            return false, "仙石不足（锁定费用" .. lockCost .. "）"
        end
    end

    return true, nil
end

--- 获取洗炼消耗信息（UI展示用）
---@param artName string
---@return table|nil
function M.GetRerollCost(artName)
    local art = FindArtifact(artName)
    if not art then return nil end
    local lockCount = 0
    if art.locked then
        for _, lk in ipairs(art.locked) do
            if lk then lockCount = lockCount + 1 end
        end
    end
    return {
        lingchen  = DataItems.REROLL_COST.lingchen,
        lingshi   = DataItems.REROLL_COST.lingshi,
        lockCount = lockCount,
        lockCost  = lockCount * DataItems.REROLL_LOCK_COST,
    }
end

--- 执行洗炼
---@param artName string
---@param callback? fun(ok: boolean, msg: string)
function M.DoReroll(artName, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanReroll(artName)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法洗炼"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_reroll", {
        playerKey = GameServer.GetServerKey("player"),
        artName   = artName,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local msg = artName .. " 洗炼完成"
            GamePlayer.AddLog("<c=gold>" .. msg .. "</c>")
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "洗炼失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "洗炼中..." })
    return true, nil
end

-- ============================================================================
-- 法宝强化（灵石 + 灵尘 + 天元精魄）
-- ============================================================================

--- 获取法宝最大等级（品质+升阶决定）
---@param art table
---@return number
function M.GetMaxLevel(art)
    local quality = art.quality or "fanqi"
    -- 兼容旧品质key
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    return DataItems.GetMaxLevel(quality, art.ascStage or 0)
end

--- 检查是否可以强化
---@param artName string
---@return boolean, string|nil
function M.CanEnhance(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end

    local art = FindArtifact(artName)
    if not art then return false, "未拥有该法宝" end

    local maxLv = M.GetMaxLevel(art)
    if (art.level or 1) >= maxLv then
        return false, "已达当前强化等级上限（" .. maxLv .. "级）"
    end

    local info = DataItems.GetEnhanceInfo(art.level or 1)
    if not info then return false, "无法获取强化配置" end

    -- 检查灵石
    if (p.lingStone or 0) < info.lingshi then
        return false, "灵石不足（需要" .. info.lingshi .. "）"
    end

    -- 检查灵尘
    local lingchenCount = 0
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == "灵尘" then lingchenCount = item.count or 0; break end
    end
    if lingchenCount < info.lingchen then
        return false, "灵尘不足（需要" .. info.lingchen .. "）"
    end

    -- 仙器+品质需天元精魄
    if info.tianyuan > 0 then
        local quality = art.quality or "fanqi"
        if DataItems.OLD_QUALITY_MAP[quality] then
            quality = DataItems.OLD_QUALITY_MAP[quality]
        end
        if DataItems.NeedsTianyuan(quality) then
            local tyCount = 0
            for _, item in ipairs(p.bagItems or {}) do
                if item.name == "天元精魄" then tyCount = item.count or 0; break end
            end
            if tyCount < info.tianyuan then
                return false, "天元精魄不足（需要" .. info.tianyuan .. "）"
            end
        end
    end

    return true, nil
end

--- 获取强化消耗信息（UI展示用）
---@param artName string
---@return table|nil
function M.GetEnhanceCost(artName)
    local art = FindArtifact(artName)
    if not art then return nil end
    local info = DataItems.GetEnhanceInfo(art.level or 1)
    if not info then return nil end
    -- 是否需要天元精魄
    local quality = art.quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    local needsTianyuan = DataItems.NeedsTianyuan(quality) and info.tianyuan > 0
    return {
        level    = art.level or 1,
        maxLevel = M.GetMaxLevel(art),
        pct      = info.pct,
        lingshi  = info.lingshi,
        lingchen = info.lingchen,
        tianyuan = needsTianyuan and info.tianyuan or 0,
        rate     = info.rate,
    }
end

--- 执行法宝强化
---@param artName string
---@param callback? fun(ok: boolean, msg: string)
---@return boolean, string
function M.DoEnhance(artName, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanEnhance(artName)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法强化"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_enhance", {
        playerKey = GameServer.GetServerKey("player"),
        artName   = artName,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local d = data or {}
            local msg = d.msg or "强化完成"
            GamePlayer.AddLog("<c=gold>" .. msg .. "</c>")
            if callback then callback(true, msg, d.success) end
        else
            local msg = (data and data.msg) or "强化失败"
            if callback then callback(false, msg) end
        end
    end, { loading = true })
    return true, nil
end

-- ============================================================================
-- 法宝升阶
-- ============================================================================

--- 检查是否可升阶
---@param artName string
---@return boolean, string|nil
function M.CanAscend(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local art = FindArtifact(artName)
    if not art then return false, "未拥有该法宝" end

    local quality = art.quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    local ascStage = art.ascStage or 0
    if ascStage >= 3 then return false, "已达最高升阶" end

    -- 需满级
    local maxLv = DataItems.GetMaxLevel(quality, ascStage)
    if (art.level or 1) < maxLv then
        return false, "需达到当前强化上限（" .. maxLv .. "级）"
    end

    local info = DataItems.GetAscensionInfo(quality, ascStage + 1)
    if not info then return false, "该品质不可升阶" end

    -- 灵尘
    local lingchenCount = 0
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == "灵尘" then lingchenCount = item.count or 0; break end
    end
    if lingchenCount < info.lingchen then
        return false, "灵尘不足（需要" .. info.lingchen .. "）"
    end

    -- 灵石
    if (p.lingStone or 0) < info.lingshi then
        return false, "灵石不足（需要" .. info.lingshi .. "）"
    end

    return true, nil
end

--- 获取升阶信息（UI展示用）
---@param artName string
---@return table|nil
function M.GetAscensionInfo(artName)
    local art = FindArtifact(artName)
    if not art then return nil end
    local quality = art.quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    local ascStage = art.ascStage or 0
    if ascStage >= 3 then return nil end
    return DataItems.GetAscensionInfo(quality, ascStage + 1)
end

--- 执行升阶
---@param artName string
---@param callback? fun(ok: boolean, msg: string)
function M.DoAscend(artName, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanAscend(artName)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法升阶"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_ascend", {
        playerKey = GameServer.GetServerKey("player"),
        artName   = artName,
    }, function(ok2, data)
        if ok2 then
            GamePlayer.RefreshDerived()
            local d = data or {}
            if d.success then
                local msg = artName .. " " .. (d.stageName or "升阶") .. "成功！等级上限+" .. tostring(d.extraLevels or 50)
                GamePlayer.AddLog("<c=gold>" .. msg .. "</c>")
                if callback then callback(true, msg) end
            else
                local msg = artName .. " 升阶失败，材料已消耗"
                GamePlayer.AddLog(msg)
                if callback then callback(false, msg) end
            end
        else
            local msg = (data and data.msg) or "升阶失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "升阶中..." })
    return true, nil
end

-- ============================================================================
-- 法宝分解
-- ============================================================================

--- 检查是否可分解
---@param artName string
---@return boolean, string|nil
function M.CanDecompose(artName)
    local p = GamePlayer.Get()
    if not p then return false, "数据未加载" end
    local art = FindArtifact(artName)
    if not art then return false, "未拥有该法宝" end
    if art.equipped then return false, "已装备的法宝不能分解" end
    local quality = art.quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    if not DataItems.DECOMPOSE_YIELD[quality] then
        return false, "该品质无法分解"
    end
    return true, nil
end

--- 获取分解预期产出
---@param artName string
---@return table|nil
function M.GetDecomposeYield(artName)
    local art = FindArtifact(artName)
    if not art then return nil end
    local quality = art.quality or "fanqi"
    if DataItems.OLD_QUALITY_MAP[quality] then
        quality = DataItems.OLD_QUALITY_MAP[quality]
    end
    return DataItems.DECOMPOSE_YIELD[quality]
end

--- 执行分解
---@param artName string
---@param callback? fun(ok: boolean, msg: string)
function M.DoDecompose(artName, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanDecompose(artName)
        if not ok then
            if callback then callback(false, reason) end
            return false, reason or "无法分解"
        end
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_decompose", {
        playerKey = GameServer.GetServerKey("player"),
        artName   = artName,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            local msg = artName .. " 已分解"
            if d.yields then
                local parts = {}
                for k, v in pairs(d.yields) do
                    if v > 0 then parts[#parts + 1] = k .. "x" .. v end
                end
                if #parts > 0 then msg = msg .. "，获得" .. table.concat(parts, "、") end
            end
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "分解失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "分解中..." })
    return true, nil
end

-- ============================================================================
-- 批量分解（按品阶勾选）
-- ============================================================================

--- 预览批量分解：统计选中品阶的未装备法宝数量和总产出
---@param selectedQualities table<string,boolean>  e.g. { fanqi=true, lingbao=true }
---@return number count, table totalYields
function M.PreviewBatchDecompose(selectedQualities)
    local p = GamePlayer.Get()
    if not p then return 0, {} end
    local arts = p.artifacts or {}
    local count = 0
    local totalYields = { lingchen = 0, xianshi = 0, tianyuan = 0, jingxue = 0 }
    for _, art in ipairs(arts) do
        if not art.equipped then
            local quality = art.quality or "fanqi"
            if DataItems.OLD_QUALITY_MAP[quality] then
                quality = DataItems.OLD_QUALITY_MAP[quality]
            end
            if selectedQualities[quality] then
                local yields = DataItems.DECOMPOSE_YIELD[quality]
                if yields then
                    count = count + 1
                    for k, v in pairs(yields) do
                        totalYields[k] = (totalYields[k] or 0) + v
                    end
                end
            end
        end
    end
    return count, totalYields
end

--- 执行批量分解
---@param selectedQualities table<string,boolean>
---@param callback? fun(ok: boolean, msg: string)
function M.DoBatchDecompose(selectedQualities, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return false, onlineErr
    end

    -- 收集品阶列表
    local qualityList = {}
    for q, v in pairs(selectedQualities) do
        if v then qualityList[#qualityList + 1] = q end
    end
    if #qualityList == 0 then
        if callback then callback(false, "未选择品阶") end
        return false, "未选择品阶"
    end

    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("artifact_batch_decompose", {
        playerKey  = GameServer.GetServerKey("player"),
        qualities  = qualityList,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            local msg = "批量分解完成"
            if d.count then msg = msg .. "，共分解 " .. d.count .. " 件" end
            if d.yields then
                local parts = {}
                for k, v in pairs(d.yields) do
                    if v > 0 then parts[#parts + 1] = k .. "x" .. v end
                end
                if #parts > 0 then msg = msg .. "，获得" .. table.concat(parts, "、") end
            end
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "批量分解失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "批量分解中..." })
    return true, nil
end

--- 红点查询：是否有任何法宝可强化/升阶/洗练
---@return boolean
function M.HasUpgradeable()
    local p = GamePlayer.Get()
    if not p then return false end
    for _, art in ipairs(p.artifacts or {}) do
        local name = art.name
        if M.CanEnhance(name) or M.CanAscend(name) or M.CanReroll(name) then
            return true
        end
    end
    return false
end

return M
