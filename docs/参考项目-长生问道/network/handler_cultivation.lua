-- ============================================================================
-- 《问道长生》渡劫处理器（服务端权威）
-- 职责：渡劫成功率判定 + 丹药消耗 + 境界提升 + 突破属性加成
-- Actions: tribulation_attempt, advance_sub
-- ============================================================================

local GameServer  = require("game_server")
local DataSkills  = require("data_skills")
local PillsHelper = require("network.pills_helper")

local M = {}
M.Actions = {}

-- 渡劫小游戏令牌（userId → { token, tier, issuedAt }）
-- 防止客户端跳过小游戏直接请求 tribulation_attempt
local pendingTokens_ = {}

-- 渡劫小游戏难度配置（与 data_realms.lua DUJIE_TIERS 保持一致）
local DUJIE_TIERS_CFG = {
    [6]  = { boltCount=15, duration=20, boltSpeed=320, warnTime=1.2, boltW=38, colorHex="8B5CF6", name="三九天劫"   },
    [7]  = { boltCount=20, duration=26, boltSpeed=390, warnTime=1.0, boltW=42, colorHex="6D28D9", name="四九天劫"   },
    [8]  = { boltCount=27, duration=32, boltSpeed=460, warnTime=0.7, boltW=47, colorHex="C4B5FD", name="六九天劫"   },
    [9]  = { boltCount=36, duration=40, boltSpeed=530, warnTime=0.5, boltW=52, colorHex="F59E0B", name="七七天劫"   },
    [10] = { boltCount=50, duration=52, boltSpeed=620, warnTime=0.3, boltW=58, colorHex="DC2626", name="九九归元劫" },
}
-- 小游戏令牌最大有效期（秒）= 最长天劫时间 + 宽限
local TOKEN_MAX_SECS = 75

-- ============================================================================
-- 境界数据（与 data_realms.lua 保持一致）
-- ============================================================================

-- 4 阶小境界（与 data_realms.lua 保持一致）
local SUB_REALMS = { "初期", "中期", "后期", "大圆满" }
local SUB_REALM_MAX = 4  -- 大圆满索引，唯一可发起渡劫的子阶

local REALMS = {
    { tier = 1,  breakRate = 100 },
    { tier = 2,  breakRate = 80 },
    { tier = 3,  breakRate = 65 },
    { tier = 4,  breakRate = 50 },
    { tier = 5,  breakRate = 35 },
    { tier = 6,  breakRate = 22 },
    { tier = 7,  breakRate = 14 },
    { tier = 8,  breakRate = 9 },
    { tier = 9,  breakRate = 6 },
    { tier = 10, breakRate = 3 },
}

local REALM_NAMES = {
    "炼气", "聚灵", "筑基", "金丹", "元婴",
    "化神", "返虚", "合道", "大乘", "渡劫",
}

-- 大境界突破属性增幅（fromTier → 晋升后获得的加成）
local BREAK_BONUS = {
    { atk = 120,   def = 45,   hp = 350,   spd = 3,  crit = 0 },  -- 炼气→聚灵
    { atk = 200,   def = 65,   hp = 550,   spd = 5,  crit = 0 },  -- 聚灵→筑基
    { atk = 350,   def = 95,   hp = 900,   spd = 8,  crit = 1 },  -- 筑基→金丹
    { atk = 600,   def = 160,  hp = 1800,  spd = 12, crit = 1 },  -- 金丹→元婴
    { atk = 1000,  def = 250,  hp = 3200,  spd = 18, crit = 2 },  -- 元婴→化神
    { atk = 1800,  def = 400,  hp = 5500,  spd = 25, crit = 2 },  -- 化神→返虚
    { atk = 3200,  def = 650,  hp = 9000,  spd = 32, crit = 3 },  -- 返虚→合道
    { atk = 5500,  def = 1000, hp = 14000, spd = 40, crit = 3 },  -- 合道→大乘
    { atk = 9000,  def = 1600, hp = 22000, spd = 50, crit = 5 },  -- 大乘→渡劫
}

-- 渡劫失败不再损失修为百分比（丹药已消耗，降境概率是唯一惩罚）
local BREAK_FAIL_COST_PCT = 0

-- ============================================================================
-- 道心门槛（tier=1..10，sub 升阶需要的最低道心值）
-- index 1 = 初→中  index 2 = 中→后  index 3 = 后→大圆满
-- ============================================================================
local DAO_HEART_THRESHOLDS = {
    { 10,   15,   20   },  -- 炼气
    { 30,   40,   50   },  -- 聚灵
    { 60,   70,   80   },  -- 筑基
    { 100,  120,  140  },  -- 金丹
    { 170,  220,  280  },  -- 元婴
    { 350,  450,  560  },  -- 化神
    { 700,  900,  1100 },  -- 返虚
    { 1400, 1700, 2000 },  -- 合道
    { 2500, 3000, 3600 },  -- 大乘
    { 4500, 5500, 6800 },  -- 渡劫
}

-- ============================================================================
-- 小境界升阶属性奖励（tier=1..10，{atk,def,hp} 基础值）
-- 实际倍率：初→中 ×1，中→后 ×2，后→大圆满 ×3
-- ============================================================================
local SUB_BONUS = {
    { atk = 3,   def = 1,   hp = 8    },  -- 炼气
    { atk = 8,   def = 3,   hp = 20   },  -- 聚灵
    { atk = 15,  def = 6,   hp = 40   },  -- 筑基
    { atk = 28,  def = 12,  hp = 80   },  -- 金丹
    { atk = 50,  def = 20,  hp = 150  },  -- 元婴
    { atk = 90,  def = 35,  hp = 280  },  -- 化神
    { atk = 160, def = 60,  hp = 500  },  -- 返虚
    { atk = 280, def = 100, hp = 900  },  -- 合道
    { atk = 480, def = 170, hp = 1500 },  -- 大乘
    { atk = 800, def = 280, hp = 2500 },  -- 渡劫
}

-- ============================================================================
-- 大境界突破必需丹药（targetTier → {name, count}）
-- nil = 无要求（炼气→聚灵新手友好）
-- ============================================================================
local REQUIRED_PILLS = {
    [2]  = nil,
    [3]  = { name = "筑基丹",     count = 2 },
    [4]  = { name = "金丹凝结丹", count = 2 },
    [5]  = { name = "凝婴丹",     count = 3 },
    [6]  = { name = "化神丹",     count = 3 },
    [7]  = { name = "返虚丹",     count = 5 },
    [8]  = { name = "合道丹",     count = 5 },
    [9]  = { name = "大乘丹",     count = 7 },
    [10] = { name = "神游丹",     count = 7 },
    [11] = { name = "仙灵丹",     count = 99 },
}

-- ============================================================================
-- 渡劫失败降小境界概率（tier=6..10 → %）
-- 失败时：消耗丹药（已在成功判定前扣除）+ 有概率从大圆满降为后期
-- ============================================================================
local FAIL_DROP_PROB = {
    [6] = 10,   -- 化神 三九天劫 10%
    [7] = 15,   -- 返虚 四九天劫 15%
    [8] = 20,   -- 合道 六九天劫 20%
    [9] = 30,   -- 大乘 七七天劫 30%
    [10] = 40,  -- 渡劫 九九归元劫 40%
}

-- 灵根觉醒 tier → slot 映射（与 data_spirit_root.lua 保持一致）
local AWAKEN_TIERS = { [5] = 2, [8] = 3 }

-- 灵根类型定义（服务端精简版，用于觉醒）
local BASE_ROOTS = { "gold", "wood", "water", "fire", "earth" }
local COMPOSITE_ROOTS = { "thunder", "yin", "yang", "wind", "ice" }
local ALL_ROOTS = { "gold", "wood", "water", "fire", "earth", "thunder", "yin", "yang", "wind", "ice" }
local COMPOSITE_COMPOSE = {
    thunder = { "fire", "earth" },
    yin     = { "water", "wood" },
    yang    = { "fire", "gold" },
    wind    = { "wood", "gold" },
    ice     = { "water", "earth" },
}
local ROOT_NAMES = {
    gold = "金灵根", wood = "木灵根", water = "水灵根", fire = "火灵根", earth = "土灵根",
    thunder = "雷灵根", yin = "阴灵根", yang = "阳灵根", wind = "风灵根", ice = "冰灵根",
}
local QUALITY_LIST = {
    { id = "waste",  prob = 10 },
    { id = "low",    prob = 30 },
    { id = "mid",    prob = 35 },
    { id = "upper",  prob = 20 },
    { id = "heaven", prob = 5 },
}
local QUALITY_NAMES = {
    waste = "废品", low = "下品", mid = "中品", upper = "上品", heaven = "天品",
}

--- 随机品质
local function RandomQuality()
    local roll = math.random(100)
    local acc = 0
    for _, q in ipairs(QUALITY_LIST) do
        acc = acc + q.prob
        if roll <= acc then return q.id end
    end
    return "mid"
end

--- 获取已有灵根的基础元素集合
local function GetOwnedElements(roots)
    local set = {}
    for _, r in ipairs(roots) do
        local compose = COMPOSITE_COMPOSE[r.type]
        if compose then
            for _, e in ipairs(compose) do set[e] = true end
        else
            set[r.type] = true
        end
    end
    return set
end

--- 尝试觉醒新灵根
---@param playerData table
---@param targetTier number
---@return table|nil newRoot 觉醒的灵根信息
local function TryAwaken(playerData, targetTier)
    local slot = AWAKEN_TIERS[targetTier]
    if not slot then return nil end

    local roots = playerData.spiritRoots
    if not roots or #roots >= slot then return nil end -- 已有足够灵根

    local owned = GetOwnedElements(roots)
    local candidates = {}
    for _, typeId in ipairs(ALL_ROOTS) do
        local compose = COMPOSITE_COMPOSE[typeId]
        local canUse = true
        if compose then
            for _, e in ipairs(compose) do
                if owned[e] then canUse = false; break end
            end
        else
            if owned[typeId] then canUse = false end
        end
        if canUse then candidates[#candidates + 1] = typeId end
    end

    if #candidates == 0 then return nil end
    local chosen = candidates[math.random(1, #candidates)]
    local newRoot = { type = chosen, quality = RandomQuality(), slot = slot }
    roots[#roots + 1] = newRoot
    return newRoot
end

-- 丹药效果映射
local PILL_EFFECTS = {
    ["筑基丹"] = { rateBonus = 20 },
    ["破劫丹"] = { rateBonus = 30 },
    ["清心丹"] = { noHeartLoss = true },
}

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 获取完整境界名
local function GetFullName(tier, sub)
    local name = REALM_NAMES[tier] or "未知"
    return name .. (SUB_REALMS[sub] or "")
end

--- 计算突破成功率
local function CalcBreakRate(targetTier, pillBonus)
    local realm = REALMS[targetTier]
    if not realm then return 0 end
    local rate = realm.breakRate + (pillBonus or 0)
    return math.min(100, math.max(0, rate))
end

--- 应用突破属性加成到玩家数据
local function ApplyBreakBonus(playerData, fromTier)
    local bonus = BREAK_BONUS[fromTier]
    if not bonus then return end

    playerData.attack  = (playerData.attack or 0) + bonus.atk
    playerData.defense = (playerData.defense or 0) + bonus.def
    playerData.hpMax   = (playerData.hpMax or 0) + bonus.hp
    playerData.hp      = (playerData.hp or 0) + bonus.hp
    playerData.speed   = (playerData.speed or 0) + bonus.spd
    playerData.crit    = (playerData.crit or 0) + bonus.crit
end

--- 从 pills 列表中消耗一枚丹药
---@param pills table[]
---@param pillName string
---@return boolean consumed
local function ConsumePill(pills, pillName)
    for i, pill in ipairs(pills) do
        if pill.name == pillName and (pill.count or 0) > 0 then
            pill.count = pill.count - 1
            if pill.count <= 0 then
                table.remove(pills, i)
            end
            return true
        end
    end
    return false
end

--- 检查玩家背包是否有足够数量的丹药
---@param pills table[]
---@param pillName string
---@param count number
---@return boolean
local function HasEnoughPills(pills, pillName, count)
    for _, pill in ipairs(pills) do
        if pill.name == pillName then
            return (pill.count or 0) >= count
        end
    end
    return false
end

--- 批量消耗丹药（count 枚）
---@param pills table[]
---@param pillName string
---@param count number
local function ConsumePillN(pills, pillName, count)
    for i, pill in ipairs(pills) do
        if pill.name == pillName then
            pill.count = (pill.count or 0) - count
            if pill.count <= 0 then
                table.remove(pills, i)
            end
            return
        end
    end
end

--- 应用小境界升阶属性奖励
---@param playerData table
---@param tier number 当前大境界（1-10）
---@param targetSub number 目标小境界索引（2=中期,3=后期,4=大圆满）
local function ApplySubBonus(playerData, tier, targetSub)
    local bonus = SUB_BONUS[tier]
    if not bonus then return end
    -- 倍率：目标sub=2 → ×1, sub=3 → ×2, sub=4 → ×3
    local mult = targetSub - 1
    playerData.attack  = (playerData.attack or 0) + bonus.atk * mult
    playerData.defense = (playerData.defense or 0) + bonus.def * mult
    playerData.hpMax   = (playerData.hpMax or 0) + bonus.hp * mult
    playerData.hp      = math.min(playerData.hp or 0, playerData.hpMax)
end

-- ============================================================================
-- Action: dujie_request — 请求发起渡劫小游戏
-- params: { playerKey: string }
-- 返回: { token: string, tierCfg: table } — 令牌 + 小游戏配置
-- 说明: tier 1~5 无小游戏时直接返回 { skipMiniGame: true }
-- ============================================================================

M.Actions["dujie_request"] = function(userId, params, reply)
    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end
    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            local tier = playerData.tier or 1
            local sub  = playerData.sub or 1

            -- 基础条件校验（与 tribulation_attempt 保持一致）
            if sub < SUB_REALM_MAX then
                reply(false, { msg = "需达到" .. GetFullName(tier, SUB_REALM_MAX) .. "方可渡劫" })
                return
            end
            if tier >= 10 then
                reply(false, { msg = "已达最高境界" })
                return
            end

            local targetTier = tier + 1
            -- 必需丹药预检（不扣除，仅检查）——从独立 key 读取
            local reqPill = REQUIRED_PILLS[targetTier]
            if reqPill then
                PillsHelper.Read(userId, function(pills)
                    if not pills or not HasEnoughPills(pills, reqPill.name, reqPill.count) then
                        reply(false, {
                            msg = string.format("需要 %s ×%d 方可渡劫", reqPill.name, reqPill.count),
                            missingPill  = reqPill.name,
                            missingCount = reqPill.count,
                        })
                        return
                    end
                    -- 丹药充足，继续小游戏/令牌逻辑
                    local dujieConf = DUJIE_TIERS_CFG[tier]
                    if not dujieConf then
                        reply(true, { skipMiniGame = true })
                        return
                    end
                    local token = tostring(userId) .. "_" .. tostring(tier) .. "_" .. tostring(os.time())
                    pendingTokens_[userId] = { token = token, tier = tier, issuedAt = os.time() }
                    local cfgOut = {}
                    for k, v in pairs(dujieConf) do cfgOut[k] = v end
                    cfgOut.tier = tier
                    print("[DujieRequest] 发放令牌 uid=" .. tostring(userId)
                          .. " tier=" .. tostring(tier) .. " name=" .. tostring(dujieConf.name))
                    reply(true, { token = token, tierCfg = cfgOut })
                end, playerKey)
                return
            end

            -- 无需丹药的低阶渡劫
            local dujieConf = DUJIE_TIERS_CFG[tier]
            if not dujieConf then
                reply(true, { skipMiniGame = true })
                return
            end

            local token = tostring(userId) .. "_" .. tostring(tier) .. "_" .. tostring(os.time())
            pendingTokens_[userId] = { token = token, tier = tier, issuedAt = os.time() }
            local cfgOut = {}
            for k, v in pairs(dujieConf) do cfgOut[k] = v end
            cfgOut.tier = tier
            print("[DujieRequest] 发放令牌 uid=" .. tostring(userId)
                  .. " tier=" .. tostring(tier) .. " name=" .. tostring(dujieConf.name))
            reply(true, { token = token, tierCfg = cfgOut })
        end,
        error = function() reply(false, { msg = "读取数据失败" }) end,
    })
end

-- ============================================================================
-- Action: tribulation_attempt — 服务端渡劫
-- params: { playerKey: string, pillNames?: string[], token?: string }
-- 返回: { success: bool, rate, targetTier, targetName, usedPills,
--          bonus?, cultLoss?, playerData (sync) }
-- ============================================================================

M.Actions["tribulation_attempt"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local pillNames = params.pillNames or {}
    local token     = params.token      -- 来自 dujie_request 的防作弊令牌

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores, iscores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            local tier = playerData.tier or 1
            local sub  = playerData.sub or 1

            -- 令牌验证（仅 tier 6~10 需要小游戏，必须持有有效令牌）
            if tier >= 6 and tier <= 10 then
                local pending = pendingTokens_[userId]
                if not pending then
                    reply(false, { msg = "请先发起渡劫小游戏（dujie_request）" })
                    return
                end
                if pending.token ~= tostring(token) then
                    reply(false, { msg = "渡劫令牌无效" })
                    return
                end
                if (os.time() - pending.issuedAt) > TOKEN_MAX_SECS then
                    pendingTokens_[userId] = nil
                    reply(false, { msg = "渡劫令牌已过期，请重新发起渡劫" })
                    return
                end
                pendingTokens_[userId] = nil  -- 消耗令牌（一次性）
            end

            -- 校验：必须在大圆满阶段
            if sub < SUB_REALM_MAX then
                reply(false, { msg = "需达到" .. GetFullName(tier, SUB_REALM_MAX) .. "方可渡劫" })
                return
            end

            -- 校验：最大阶数
            if tier >= 10 then
                reply(false, { msg = "已达最高境界" })
                return
            end

            local targetTier = tier + 1

            -- 从独立 key 读取丹药
            PillsHelper.Read(userId, function(pills, errMsg)
                if not pills then
                    reply(false, { msg = "丹药数据读取失败" })
                    return
                end

                local pillBonus = 0
                local usedPills = {}
                local hasQingxin = false

                -- 校验并消耗必需丹药（无论成功失败均消耗）
                local reqPill = REQUIRED_PILLS[targetTier]
                if reqPill then
                    if not HasEnoughPills(pills, reqPill.name, reqPill.count) then
                        reply(false, {
                            msg = string.format("需要 %s ×%d 方可渡劫", reqPill.name, reqPill.count),
                            missingPill = reqPill.name,
                            missingCount = reqPill.count,
                        })
                        return
                    end
                    ConsumePillN(pills, reqPill.name, reqPill.count)
                    usedPills[#usedPills + 1] = reqPill.name
                end

                -- 消耗可选的辅助丹药并计算加成
                for _, pName in ipairs(pillNames) do
                    local effect = PILL_EFFECTS[pName]
                    if effect then
                        if ConsumePill(pills, pName) then
                            usedPills[#usedPills + 1] = pName
                            if effect.rateBonus then
                                pillBonus = pillBonus + effect.rateBonus
                            end
                            if effect.noHeartLoss then
                                hasQingxin = true
                            end
                        end
                    end
                end

                playerData.pills = nil  -- 从 blob 中清除

                -- 服务端掷骰
                local rate = CalcBreakRate(targetTier, pillBonus)
                local roll = math.random(100)
                local success = roll <= rate

                local cultLoss = 0
                local subDropped = false
                local awakenedRoot = nil
                if success then
                    -- 成功：提升境界 + 属性加成
                    playerData.tier = targetTier
                    playerData.sub  = 1
                    playerData.cultivation = 0
                    ApplyBreakBonus(playerData, tier)
                    -- 重置丹药使用次数
                    playerData.pillUsage = {}
                    -- 悟道解锁检测：境界提升后检查是否有新悟道可解锁
                    for _, dao in ipairs(playerData.daoInsights or {}) do
                        if dao.locked then
                            local def = DataSkills.GetInsight(dao.id)
                            if def and def.unlockTier and targetTier >= def.unlockTier then
                                dao.locked = false
                                print("[Tribulation] 悟道解锁: " .. dao.name .. " tier=" .. targetTier)
                            end
                        end
                    end
                    -- 灵根觉醒检测（元婴 tier=5 → slot2, 合道 tier=8 → slot3）
                    awakenedRoot = TryAwaken(playerData, targetTier)
                    if awakenedRoot then
                        local rName = ROOT_NAMES[awakenedRoot.type] or "未知"
                        local qName = QUALITY_NAMES[awakenedRoot.quality] or "未知"
                        print("[Tribulation] 灵根觉醒: " .. rName .. "-" .. qName
                            .. " slot=" .. awakenedRoot.slot
                            .. " uid=" .. tostring(userId))
                    end
                else
                    -- 失败：丹药已扣除，额外掷骰降小境界
                    local cultivation = playerData.cultivation or 0
                    cultLoss = math.floor(cultivation * BREAK_FAIL_COST_PCT / 100)
                    if cultLoss > 0 then
                        playerData.cultivation = math.max(0, cultivation - cultLoss)
                    end
                    -- 降小境界概率（仅在 T6+ 且当前为大圆满时触发）
                    local dropProb = FAIL_DROP_PROB[tier]
                    if dropProb and playerData.sub >= SUB_REALM_MAX then
                        local dropRoll = math.random(100)
                        if dropRoll <= dropProb then
                            playerData.sub = SUB_REALM_MAX - 1
                            playerData.cultivation = 0
                            subDropped = true
                            print("[Tribulation] 失败降境 tier=" .. tier
                                .. " dropProb=" .. dropProb .. " dropRoll=" .. dropRoll
                                .. " uid=" .. tostring(userId))
                        end
                    end
                end

                -- 先保存独立 pills key，再保存 playerData blob
                PillsHelper.Write(userId, pills, function(pillsOk, pillsErr)
                    if not pillsOk then
                        print("[Tribulation] pills 保存失败: " .. tostring(pillsErr))
                        reply(false, { msg = "丹药数据保存失败" })
                        return
                    end

                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            local targetName = GetFullName(targetTier, 1)
                            print("[Tribulation] " .. (success and "成功" or "失败")
                                .. " tier=" .. tier .. "→" .. targetTier
                                .. " rate=" .. rate .. " roll=" .. roll
                                .. " uid=" .. tostring(userId))

                            -- 构造 sync 字段（同步关键属性到客户端）
                            local syncFields = {
                                tier        = playerData.tier,
                                sub         = playerData.sub,
                                attack      = playerData.attack,
                                defense     = playerData.defense,
                                hp          = playerData.hp,
                                hpMax       = playerData.hpMax,
                                speed       = playerData.speed,
                                crit        = playerData.crit,
                                cultivation = playerData.cultivation,
                                pills       = pills,  -- 从独立 key 读取的最新 pills
                                pillUsage   = playerData.pillUsage,
                                spiritRoots = playerData.spiritRoots,
                                daoInsights = playerData.daoInsights,
                            }

                            -- 觉醒信息（客户端用于 Toast 提示）
                            local awakenInfo = nil
                            if awakenedRoot then
                                awakenInfo = {
                                    type    = awakenedRoot.type,
                                    quality = awakenedRoot.quality,
                                    slot    = awakenedRoot.slot,
                                    name    = (ROOT_NAMES[awakenedRoot.type] or "未知") .. "-" .. (QUALITY_NAMES[awakenedRoot.quality] or "未知"),
                                }
                            end

                            -- 渡劫成功：全服世界播报
                            if success then
                                local pName = playerData.name or "无名道友"
                                local fromName = (REALM_NAMES[tier] or "未知") .. "大圆满"
                                local toName   = targetName
                                local announceText = string.format(
                                    "<font color=#F59E0B>【天道示警】</font>道友 %s 历经 %s，渡劫成功，晋升 <font color=#C4B5FD>%s</font>！",
                                    pName, fromName, toName)
                                local ok2, ChatServer = pcall(require, "network.chat_server")
                                if ok2 and ChatServer and ChatServer.BroadcastSystemAnnounce then
                                    ChatServer.BroadcastSystemAnnounce("tribulation_success", announceText)
                                end
                            end

                            reply(true, {
                                success    = success,
                                rate       = rate,
                                targetTier = targetTier,
                                targetName = targetName,
                                usedPills  = usedPills,
                                hasQingxin = hasQingxin,
                                cultLoss   = not success and cultLoss or nil,
                                subDropped = not success and subDropped or nil,
                                awakened   = awakenInfo,
                            }, syncFields)

                            -- 更新排行榜 iscores
                            local realmKey = GameServer.GetGroupKey("realm")
                            local powerKey = GameServer.GetGroupKey("power")
                            serverCloud:BatchSet(userId)
                                :SetInt(realmKey, (playerData.tier or 1) * 100 + (playerData.sub or 1) * 10)
                                :SetInt(powerKey, math.floor(
                                    (playerData.attack  or 0)
                                    + (playerData.defense or 0) * 0.8
                                    + (playerData.speed   or 0) * 0.5
                                    + (playerData.hpMax   or 0) / 10
                                    + (playerData.mpMax   or 0) / 10
                                ))
                                :Save("rank_update", {
                                    ok    = function() end,
                                    error = function(_, r)
                                        print("[Tribulation] iscores 更新失败 uid=" .. tostring(userId) .. " " .. tostring(r))
                                    end,
                                })
                        end,
                        error = function(code, reason)
                            print("[Tribulation] 保存失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
                            reply(false, { msg = "数据保存失败" })
                        end,
                    })
                end, playerKey) -- PillsHelper.Write
            end, playerKey) -- PillsHelper.Read
        end,
        error = function(code, reason)
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: advance_sub — 小境界晋升
-- params: { playerKey: string }
-- 返回: { targetName: string }  + sync
-- ============================================================================

M.Actions["advance_sub"] = function(userId, params, reply)
    local playerKey = params.playerKey

    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" })
        return
    end

    if not serverCloud then
        reply(false, { msg = "服务端存储不可用" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores, iscores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" })
                return
            end

            local tier = playerData.tier or 1
            local sub  = playerData.sub or 1
            local isImmortal = tier >= 11

            -- 校验：资源是否满（仙人期检查仙气，凡人期检查修为）
            if isImmortal then
                -- 仙气需求：从存档字段中读取（客户端已由 AttachDerived 计算并存入 xianQiMax）
                -- 服务端简单校验：xianQi >= xianQiMax（xianQiMax 须由客户端随 advance_sub 一并上报，或服务端查表）
                -- 当前策略：信任客户端 xianQiMax，服务端仅做非零校验
                local xianQi = playerData.xianQi or 0
                if xianQi <= 0 then
                    reply(false, { msg = "仙气不足" })
                    return
                end
            else
                local cult = playerData.cultivation or 0
                local cultMax = playerData.cultivationMax or 0
                if cult < cultMax then
                    reply(false, { msg = "修为不足" })
                    return
                end
            end

            -- 校验：是否还能晋升小境界（大圆满后需渡劫）
            if sub >= SUB_REALM_MAX then
                reply(false, { msg = "已达大圆满，需渡劫突破" })
                return
            end

            -- 道心门槛检查（凡人期有详细表，仙人期暂沿用默认0）
            local daoHeart = playerData.daoHeart or 0
            local thresholds = DAO_HEART_THRESHOLDS[tier]
            if thresholds then
                -- sub=1→2: thresholds[1], sub=2→3: thresholds[2], sub=3→4: thresholds[3]
                local required = thresholds[sub]
                if required and daoHeart < required then
                    reply(false, {
                        msg = string.format("道心不足（当前 %d，需 %d）", daoHeart, required),
                        daoHeartRequired = required,
                        daoHeartCurrent  = daoHeart,
                    })
                    return
                end
            end

            -- 晋升小境界
            local targetSub = sub + 1
            playerData.sub = targetSub
            -- 仙人期重置仙气，凡人期重置修为
            if isImmortal then
                playerData.xianQi = 0
            else
                playerData.cultivation = 0
            end

            -- 发放小境界属性奖励
            ApplySubBonus(playerData, tier, targetSub)

            -- 小境界突破道心奖励（+5，积累以解锁后续门槛）
            playerData.daoHeart = (playerData.daoHeart or 0) + 5

            local targetName = GetFullName(tier, targetSub)

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    local bonus = SUB_BONUS[tier]
                    local mult  = targetSub - 1
                    print("[AdvanceSub] " .. GetFullName(tier, sub) .. "→" .. targetName
                        .. " daoHeart=" .. daoHeart
                        .. " bonusMult=" .. mult
                        .. " uid=" .. tostring(userId))

                    reply(true, {
                        targetName  = targetName,
                        -- 告知客户端本次奖励数值（用于展示）
                        bonusAtk    = bonus and bonus.atk * mult or 0,
                        bonusDef    = bonus and bonus.def * mult or 0,
                        bonusHp     = bonus and bonus.hp  * mult or 0,
                    }, {
                        tier        = playerData.tier,
                        sub         = playerData.sub,
                        cultivation = playerData.cultivation,
                        xianQi      = playerData.xianQi,
                        attack      = playerData.attack,
                        defense     = playerData.defense,
                        hp          = playerData.hp,
                        hpMax       = playerData.hpMax,
                        daoHeart    = playerData.daoHeart,
                    })

                    -- 更新排行榜 iscores（境界 + 战力，异步不阻塞）
                    local realmKey = GameServer.GetGroupKey("realm")
                    local powerKey = GameServer.GetGroupKey("power")
                    serverCloud:BatchSet(userId)
                        :SetInt(realmKey, (playerData.tier or 1) * 100 + (playerData.sub or 1) * 10)
                        :SetInt(powerKey, math.floor(
                            (playerData.attack  or 0)
                            + (playerData.defense or 0) * 0.8
                            + (playerData.speed   or 0) * 0.5
                            + (playerData.hpMax   or 0) / 10
                            + (playerData.mpMax   or 0) / 10
                        ))
                        :Save("rank_update", {
                            ok    = function() end,
                            error = function(_, r)
                                print("[AdvanceSub] iscores 更新失败 uid=" .. tostring(userId) .. " " .. tostring(r))
                            end,
                        })
                end,
                error = function(code, reason)
                    print("[AdvanceSub] 保存失败 uid=" .. tostring(userId) .. " " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function(code, reason)
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- cult_sync — 客户端定期同步修为/仙气到服务端
-- params: { playerKey, cultivation, xianQi? }
-- 用途：客户端被动修炼每秒累积修为，但网络模式下不自动保存；
--       悟道等服务端操作需要读取最新修为，因此需要定期同步。
-- ============================================================================
M.Actions["cult_sync"] = function(userId, params, reply)
    local playerKey     = params.playerKey
    local clientCult    = tonumber(params.cultivation)
    local clientXianQi  = tonumber(params.xianQi)

    if not playerKey or playerKey == "" then
        return reply(false, { msg = "缺少 playerKey" })
    end
    if not clientCult and not clientXianQi then
        return reply(false, { msg = "无同步数据" })
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                return reply(false, { msg = "玩家数据解析失败" })
            end

            local changed = false

            -- 修为只允许增长（防作弊：客户端不能凭空减少修为）
            if clientCult and clientCult > (playerData.cultivation or 0) then
                playerData.cultivation = clientCult
                changed = true
            end

            -- 仙气同理
            if clientXianQi and clientXianQi > (playerData.xianQi or 0) then
                playerData.xianQi = clientXianQi
                changed = true
            end

            if not changed then
                return reply(true, { msg = "无需同步" })
            end

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    reply(true, { msg = "同步成功" }, {
                        cultivation = playerData.cultivation,
                        xianQi      = playerData.xianQi,
                    })
                end,
                error = function(e)
                    reply(false, { msg = "保存失败: " .. tostring(e) })
                end,
            })
        end,
        error = function(e)
            reply(false, { msg = "读取失败: " .. tostring(e) })
        end,
    })
end

return M
