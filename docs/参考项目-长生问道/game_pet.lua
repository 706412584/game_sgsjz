-- ============================================================================
-- 《问道长生》灵宠系统（血脉进化 + 境界压制 + 天赋 + 羁绊 + 化形）
-- 职责：灵宠升级、觉醒、出战/召回、分解、战斗加成、羁绊、化形
-- 设计：Can/Do 模式，服务端权威（GameOps）
-- ============================================================================

local GamePlayer     = require("game_player")
local DataPets       = require("data_pets")
local DataItems      = require("data_items")
local DataSpiritRoot = require("data_spirit_root")

local M = {}

-- ============================================================================
-- 灵宠 element → 灵根基础五行映射
-- ============================================================================
local PET_ELEM_TO_ROOT = {
    metal = "gold", wood = "wood", water = "water", fire = "fire", earth = "earth",
}

local function EnsureOnlineMode()
    if IsNetworkMode() then return true end
    return false, "当前版本仅支持联网模式"
end

-- ============================================================================
-- 内部工具
-- ============================================================================

--- 确保灵宠数据结构（兼容旧数据自动迁移）
---@return table|nil
local function EnsurePetData()
    local p = GamePlayer.Get()
    if not p then return nil end
    if not p.pets then p.pets = {} end
    if p.activePetUid == nil then p.activePetUid = "" end

    -- 旧 activePetId → activePetUid
    if p.activePetId and p.activePetId ~= 0 and p.activePetUid == "" then
        for _, pet in ipairs(p.pets) do
            if pet.uid and pet.templateId == p.activePetId then
                p.activePetUid = pet.uid
                break
            end
        end
        p.activePetId = nil
        GamePlayer.MarkDirty()
    end

    -- 旧品质格式 → 新血脉格式（逐条迁移）
    local migrated = false
    for i, pet in ipairs(p.pets) do
        if DataPets.IsOldFormat(pet) then
            p.pets[i] = DataPets.MigratePetData(pet)
            migrated = true
        end
    end
    if migrated then
        GamePlayer.MarkDirty()
    end

    return p
end

--- 按 uid 查找玩家拥有的灵宠
---@param p table
---@param uid string
---@return table|nil petData, number|nil idx
local function FindPetByUid(p, uid)
    if not uid or uid == "" then return nil, nil end
    for i, pet in ipairs(p.pets) do
        if pet.uid == uid then return pet, i end
    end
    return nil, nil
end

--- 获取灵宠模板定义（从 data_pets）
---@param templateId number
---@return table|nil
local function GetTemplate(templateId)
    return DataPets.GetPet(templateId)
end

--- 获取灵宠最大等级（血脉 + 觉醒 + 境界压制）
---@param bloodline string
---@param awakenStage number
---@return number maxLevel, number bloodlineCap, number realmCap
local function GetMaxLevel(bloodline, awakenStage)
    local p = GamePlayer.Get()
    local tier = p and p.tier or 1
    return DataPets.GetMaxLevel(bloodline, awakenStage or 0, tier)
end

-- ============================================================================
-- 灵根共鸣系统（保留 V2 逻辑）
-- ============================================================================

--- 收集玩家灵根覆盖的基础五行元素集合
local function CollectPlayerElements(spiritRoots)
    local set = {}
    for _, r in ipairs(spiritRoots) do
        local t = DataSpiritRoot.TYPES[r.type]
        if t then
            if t.compose then
                for _, e in ipairs(t.compose) do set[e] = true end
            else
                set[r.type] = true
            end
        end
    end
    return set
end

--- 计算灵宠与玩家灵根的共鸣等级
---@param petElement string
---@param spiritRoots table[]
---@return number matchCount, number combatPct, number expPct
function M.CalcResonance(petElement, spiritRoots)
    if not petElement or not spiritRoots or #spiritRoots == 0 then
        return 0, 0, 0
    end
    local rootElem = PET_ELEM_TO_ROOT[petElement]
    if not rootElem then return 0, 0, 0 end

    local matchCount = 0
    for _, r in ipairs(spiritRoots) do
        local t = DataSpiritRoot.TYPES[r.type]
        if t then
            if t.compose then
                for _, e in ipairs(t.compose) do
                    if e == rootElem then matchCount = matchCount + 1; break end
                end
            else
                if r.type == rootElem then matchCount = matchCount + 1 end
            end
        end
    end

    if matchCount >= 2 then
        return matchCount, 0.20, 0.15
    elseif matchCount == 1 then
        return matchCount, 0.10, 0
    end
    return 0, 0, 0
end

-- ============================================================================
-- 内部工具：构建灵宠完整信息
-- ============================================================================

--- 构建单只灵宠的完整展示数据
---@param pet table 原始存储数据
---@param p table 玩家数据
---@return table|nil
local function BuildPetInfo(pet, p)
    local def = GetTemplate(pet.templateId)
    if not def then return nil end

    local bloodline = pet.bloodline or def.bloodline or "fanshou"
    local awakenStage = pet.awakenStage or 0
    local level = pet.level or 1
    local maxLv, blCap, realmCap = GetMaxLevel(bloodline, awakenStage)
    local lvInfo = DataItems.GetPetLevelInfo(level)

    -- 共鸣
    local mc, cp, ep = 0, 0, 0
    local resLabel = "无共鸣"
    local roots = p.spiritRoots or {}
    if def.element and #roots > 0 then
        mc, cp, ep = M.CalcResonance(def.element, roots)
        if mc >= 2 then resLabel = "高级共鸣"
        elseif mc == 1 then resLabel = "初级共鸣" end
    end

    -- 天赋
    local talents = {}
    for _, tid in ipairs(pet.talents or {}) do
        local tdef = DataPets.TALENT_MAP[tid]
        if tdef then talents[#talents + 1] = tdef end
    end

    -- 羁绊
    local bondInfo = DataPets.GetBondLevel(pet.bond or 0)

    -- 血脉信息
    local blInfo = DataPets.BLOODLINE[bloodline]

    return {
        uid         = pet.uid,
        templateId  = pet.templateId,
        name        = def.name,
        bloodline   = bloodline,
        bloodlineLabel = blInfo and blInfo.label or "未知",
        bloodlineColor = blInfo and blInfo.color or { 180, 180, 180, 255 },
        role        = def.role,
        skill       = def.skill,
        image       = pet.transformed and (def.transformImage or def.image) or def.image,
        desc        = def.desc,
        element     = def.element,
        level       = level,
        exp         = pet.exp or 0,
        expMax      = (lvInfo and level < maxLv) and lvInfo.expNeeded or 0,
        maxLevel    = maxLv,
        bloodlineCap = blCap,
        realmCap    = realmCap,
        awakenStage = awakenStage,
        maxAwakenStage = blInfo and blInfo.awakenStages or 2,
        isActive    = (p.activePetUid == pet.uid),
        combatStats = def.combatStats,
        resonance   = { matchCount = mc, combatPct = cp, expPct = ep, label = resLabel },
        talents     = talents,
        talentIds   = pet.talents or {},
        bond        = pet.bond or 0,
        bondInfo    = bondInfo,
        transformed = pet.transformed or false,
        canTransform = blInfo and blInfo.canTransform or false,
        -- 兼容旧 UI 读 quality
        quality     = bloodline,
    }
end

-- ============================================================================
-- 公开接口：查询
-- ============================================================================

--- 获取全部已拥有灵宠
---@return table[]
function M.GetAllPets()
    local p = EnsurePetData()
    if not p then return {} end
    local result = {}
    for _, pet in ipairs(p.pets) do
        local info = BuildPetInfo(pet, p)
        if info then result[#result + 1] = info end
    end
    return result
end

--- 获取当前出战灵宠信息
---@return table|nil
function M.GetActivePet()
    local p = EnsurePetData()
    if not p or not p.activePetUid or p.activePetUid == "" then return nil end
    local pet = FindPetByUid(p, p.activePetUid)
    if not pet then return nil end
    return BuildPetInfo(pet, p)
end

--- 获取单只灵宠详情
---@param uid string
---@return table|nil
function M.GetPetByUid(uid)
    local p = EnsurePetData()
    if not p then return nil end
    local pet = FindPetByUid(p, uid)
    if not pet then return nil end
    return BuildPetInfo(pet, p)
end

--- 获取拥有的灵宠数量
---@return number
function M.GetOwnedCount()
    local p = EnsurePetData()
    if not p then return 0 end
    return #p.pets
end

--- 获取出战灵宠共鸣信息（UI展示用）
---@return table
function M.GetResonanceInfo()
    local info = { matchCount = 0, combatPct = 0, expPct = 0, resonanceLabel = "无共鸣" }
    local active = M.GetActivePet()
    if not active then return info end
    info.matchCount = active.resonance.matchCount
    info.combatPct  = active.resonance.combatPct
    info.expPct     = active.resonance.expPct
    info.resonanceLabel = active.resonance.label
    return info
end

--- 获取灵宠战斗加成（含灵根共鸣 + 羁绊加成）
---@return table { atkBonus, defBonus, hpBonus, spdBonus }
function M.GetCombatBonus()
    local base = { atkBonus = 0, defBonus = 0, hpBonus = 0, spdBonus = 0 }
    local active = M.GetActivePet()
    if not active then return base end

    local blInfo = DataPets.BLOODLINE[active.bloodline]
    local mul = blInfo and blInfo.powerMul or 1.0
    local lv = active.level or 1

    if active.role == "攻击" then
        base.atkBonus = math.floor(lv * 2.5 * mul)
    elseif active.role == "防御" then
        base.defBonus = math.floor(lv * 2.0 * mul)
        base.hpBonus  = math.floor(lv * 12 * mul)
    elseif active.role == "辅助" then
        base.spdBonus = math.floor(lv * 1.5 * mul)
        base.atkBonus = math.floor(lv * 1.0 * mul)
    end

    -- 觉醒属性加成
    local awakenBonus = 0
    for i = 1, (active.awakenStage or 0) do
        local stg = DataPets.AWAKEN_STAGES[i]
        if stg then awakenBonus = awakenBonus + stg.statBonus end
    end
    if awakenBonus > 0 then
        base.atkBonus = math.floor(base.atkBonus * (1 + awakenBonus))
        base.defBonus = math.floor(base.defBonus * (1 + awakenBonus))
        base.hpBonus  = math.floor(base.hpBonus  * (1 + awakenBonus))
        base.spdBonus = math.floor(base.spdBonus * (1 + awakenBonus))
    end

    -- 羁绊加成
    local bondBonus = active.bondInfo and active.bondInfo.statBonus or 0
    if bondBonus > 0 then
        base.atkBonus = math.floor(base.atkBonus * (1 + bondBonus))
        base.defBonus = math.floor(base.defBonus * (1 + bondBonus))
        base.hpBonus  = math.floor(base.hpBonus  * (1 + bondBonus))
        base.spdBonus = math.floor(base.spdBonus * (1 + bondBonus))
    end

    -- 灵根共鸣加成
    if active.resonance.combatPct > 0 then
        base.atkBonus = math.floor(base.atkBonus * (1 + active.resonance.combatPct))
        base.defBonus = math.floor(base.defBonus * (1 + active.resonance.combatPct))
        base.hpBonus  = math.floor(base.hpBonus  * (1 + active.resonance.combatPct))
        base.spdBonus = math.floor(base.spdBonus * (1 + active.resonance.combatPct))
    end

    -- 天赋加成
    for _, t in ipairs(active.talents or {}) do
        local eff = t.effect or {}
        if eff.atkPct then base.atkBonus = math.floor(base.atkBonus * (1 + eff.atkPct)) end
        if eff.defPct then base.defBonus = math.floor(base.defBonus * (1 + eff.defPct)) end
        if eff.spdPct then base.spdBonus = math.floor(base.spdBonus * (1 + eff.spdPct)) end
    end

    return base
end

-- ============================================================================
-- 公开接口：升级（消耗灵兽精血 + 灵石，受境界压制）
-- ============================================================================

--- 检查是否可升级
---@param uid string
---@return boolean, string|nil
function M.CanLevelUp(uid)
    local p = EnsurePetData()
    if not p then return false, "数据未加载" end
    local pet = FindPetByUid(p, uid)
    if not pet then return false, "未拥有此灵宠" end

    local bloodline = pet.bloodline or "fanshou"
    local maxLv = GetMaxLevel(bloodline, pet.awakenStage or 0)
    if (pet.level or 1) >= maxLv then
        -- 区分是血脉上限还是境界压制
        local _, blCap, rCap = GetMaxLevel(bloodline, pet.awakenStage or 0)
        if rCap <= blCap then
            return false, "境界压制（提升修为可解锁更高等级）"
        end
        return false, "已达血脉等级上限（" .. maxLv .. "级）"
    end

    local lvInfo = DataItems.GetPetLevelInfo(pet.level or 1)
    if not lvInfo then return false, "等级数据异常" end

    -- 检查灵兽精血
    local jingxueCount = 0
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == "灵兽精血" then jingxueCount = item.count or 0; break end
    end
    if jingxueCount < lvInfo.jingxue then
        return false, "灵兽精血不足（需要" .. lvInfo.jingxue .. "）"
    end

    -- 检查灵石
    if (p.lingStone or 0) < lvInfo.lingshi then
        return false, "灵石不足（需要" .. lvInfo.lingshi .. "）"
    end

    return true, nil
end

--- 执行升级（走 GameOps）
---@param uid string
---@param callback? fun(ok: boolean, msg: string)
function M.DoLevelUp(uid, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanLevelUp(uid)
        if not ok then
            if callback then callback(false, reason or "无法升级") end
            return
        end
    end
    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("pet_level_up", {
        playerKey = GameServer.GetServerKey("player"),
        petUid    = uid,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            local msg = (d.petName or "灵宠") .. " 升至Lv." .. tostring(d.newLevel or "?")
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "升级失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "升级中..." })
end

--- 升级所需材料信息（UI展示用）
---@param uid string
---@return table|nil { level, expNeeded, lingshi, jingxue }
function M.GetLevelUpCost(uid)
    local p = EnsurePetData()
    if not p then return nil end
    local pet = FindPetByUid(p, uid)
    if not pet then return nil end
    return DataItems.GetPetLevelInfo(pet.level or 1)
end

-- ============================================================================
-- 公开接口：血脉觉醒（替代旧升阶）
-- ============================================================================

--- 检查是否可觉醒
---@param uid string
---@return boolean, string|nil
function M.CanAwaken(uid)
    local p = EnsurePetData()
    if not p then return false, "数据未加载" end
    local pet = FindPetByUid(p, uid)
    if not pet then return false, "未拥有此灵宠" end

    local bloodline = pet.bloodline or "fanshou"
    local blInfo = DataPets.BLOODLINE[bloodline]
    if not blInfo then return false, "未知血脉" end

    local awakenStage = pet.awakenStage or 0
    if awakenStage >= blInfo.awakenStages then
        return false, "已达觉醒圆满"
    end

    -- 需满当前等级上限才能觉醒
    local maxLv = GetMaxLevel(bloodline, awakenStage)
    if (pet.level or 1) < maxLv then
        return false, "需要达到当前等级上限（" .. maxLv .. "级）"
    end

    local info = DataPets.GetAwakenInfo(bloodline, awakenStage + 1)
    if not info then return false, "觉醒数据异常" end

    -- 检查灵兽精血
    local jingxueCount = 0
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == "灵兽精血" then jingxueCount = item.count or 0; break end
    end
    if jingxueCount < info.jingxue then
        return false, "灵兽精血不足（需要" .. info.jingxue .. "）"
    end

    -- 检查灵石
    if (p.lingStone or 0) < info.lingshi then
        return false, "灵石不足（需要" .. info.lingshi .. "）"
    end

    return true, nil
end

--- 获取觉醒信息（UI展示用）
---@param uid string
---@return table|nil
function M.GetAwakenInfo(uid)
    local p = EnsurePetData()
    if not p then return nil end
    local pet = FindPetByUid(p, uid)
    if not pet then return nil end
    local bloodline = pet.bloodline or "fanshou"
    local awakenStage = pet.awakenStage or 0
    local blInfo = DataPets.BLOODLINE[bloodline]
    if not blInfo or awakenStage >= blInfo.awakenStages then return nil end
    return DataPets.GetAwakenInfo(bloodline, awakenStage + 1)
end

--- 执行觉醒（走 GameOps）
---@param uid string
---@param callback? fun(ok: boolean, msg: string)
function M.DoAwaken(uid, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanAwaken(uid)
        if not ok then
            if callback then callback(false, reason or "无法觉醒") end
            return
        end
    end
    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("pet_awaken", {
        playerKey = GameServer.GetServerKey("player"),
        petUid    = uid,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            if d.success then
                local msg = (d.petName or "灵宠") .. " " .. (d.stageName or "觉醒") .. "成功！"
                if d.newTalent then
                    local tdef = DataPets.TALENT_MAP[d.newTalent]
                    if tdef then msg = msg .. "领悟天赋【" .. tdef.name .. "】" end
                end
                GamePlayer.AddLog(msg)
                if callback then callback(true, msg) end
            else
                local msg = (d.petName or "灵宠") .. " 觉醒失败，材料已消耗"
                if callback then callback(false, msg) end
            end
        else
            local msg = (data and data.msg) or "觉醒失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "觉醒中..." })
end

-- 兼容旧 API：CanAscend → CanAwaken，GetAscensionInfo → GetAwakenInfo，DoAscend → DoAwaken
M.CanAscend = M.CanAwaken
M.GetAscensionInfo = M.GetAwakenInfo
M.DoAscend = M.DoAwaken

-- ============================================================================
-- 公开接口：分解
-- ============================================================================

--- 检查是否可分解
---@param uid string
---@return boolean, string|nil
function M.CanDecompose(uid)
    local p = EnsurePetData()
    if not p then return false, "数据未加载" end
    local pet = FindPetByUid(p, uid)
    if not pet then return false, "未拥有此灵宠" end
    if p.activePetUid == uid then
        return false, "出战中的灵宠不能分解"
    end
    local bloodline = pet.bloodline or "fanshou"
    local yield = DataPets.DECOMPOSE_YIELD[bloodline]
    if not yield then return false, "该血脉无法分解" end
    return true, nil
end

--- 获取分解预期产出
---@param uid string
---@return table|nil
function M.GetDecomposeYield(uid)
    local p = EnsurePetData()
    if not p then return nil end
    local pet = FindPetByUid(p, uid)
    if not pet then return nil end
    local bloodline = pet.bloodline or "fanshou"
    return DataPets.DECOMPOSE_YIELD[bloodline]
end

--- 执行分解（走 GameOps）
---@param uid string
---@param callback? fun(ok: boolean, msg: string)
function M.DoDecompose(uid, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanDecompose(uid)
        if not ok then
            if callback then callback(false, reason or "无法分解") end
            return
        end
    end
    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("pet_decompose", {
        playerKey = GameServer.GetServerKey("player"),
        petUid    = uid,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            local msg = (d.petName or "灵宠") .. " 已分解"
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
end

-- ============================================================================
-- 公开接口：化形
-- ============================================================================

--- 检查是否可化形
---@param uid string
---@return boolean, string|nil
function M.CanTransform(uid)
    local p = EnsurePetData()
    if not p then return false, "数据未加载" end
    local pet = FindPetByUid(p, uid)
    if not pet then return false, "未拥有此灵宠" end
    if pet.transformed then return false, "已化形" end

    local bloodline = pet.bloodline or "fanshou"
    local bondInfo = DataPets.GetBondLevel(pet.bond or 0)
    local ok, reason = DataPets.CanTransform(bloodline, pet.awakenStage or 0, bondInfo.level)
    if not ok then return false, reason end

    -- 检查材料
    local req = DataPets.TRANSFORM_REQUIRE
    local jingxueCount = 0
    for _, item in ipairs(p.bagItems or {}) do
        if item.name == "灵兽精血" then jingxueCount = item.count or 0; break end
    end
    if jingxueCount < req.jingxue then
        return false, "灵兽精血不足（需要" .. req.jingxue .. "）"
    end
    if (p.lingStone or 0) < req.lingshi then
        return false, "灵石不足（需要" .. req.lingshi .. "）"
    end

    return true, nil
end

--- 执行化形（走 GameOps）
---@param uid string
---@param callback? fun(ok: boolean, msg: string)
function M.DoTransform(uid, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return
    end
    -- 网络模式：跳过客户端校验，由服务端做权威验证
    if not IsNetworkMode() then
        local ok, reason = M.CanTransform(uid)
        if not ok then
            if callback then callback(false, reason or "无法化形") end
            return
        end
    end
    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("pet_transform", {
        playerKey = GameServer.GetServerKey("player"),
        petUid    = uid,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            local msg = (d.petName or "灵宠") .. " 化形成功！"
            if d.transformName then msg = msg .. "化身为【" .. d.transformName .. "】" end
            GamePlayer.AddLog(msg)
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "化形失败"
            if callback then callback(false, msg) end
        end
    end, { loading = "化形中..." })
end

-- ============================================================================
-- 公开接口：出战 / 召回
-- ============================================================================

--- 设置出战灵宠
---@param uid string  传 "" 表示召回
---@param callback? fun(ok: boolean, msg: string)
function M.DoSetActive(uid, callback)
    local onlineOk, onlineErr = EnsureOnlineMode()
    if not onlineOk then
        if callback then callback(false, onlineErr) end
        return
    end
    local p = EnsurePetData()
    if not p then
        if callback then callback(false, "数据未加载") end
        return
    end
    if uid ~= "" then
        local pet = FindPetByUid(p, uid)
        if not pet then
            if callback then callback(false, "未拥有此灵宠") end
            return
        end
    end
    local GameOps = require("network.game_ops")
    local GameServer = require("game_server")
    GameOps.Request("pet_set_active", {
        playerKey = GameServer.GetServerKey("player"),
        petUid    = uid,
    }, function(ok2, data)
        if ok2 then
            local d = data or {}
            local msg = d.msg or (uid == "" and "灵宠已召回" or "灵宠已出战")
            if uid ~= "" then GamePlayer.AddLog(msg) end
            if callback then callback(true, msg) end
        else
            local msg = (data and data.msg) or "操作失败"
            if callback then callback(false, msg) end
        end
    end, { loading = uid == "" and "召回中..." or "出战中..." })
end

-- ============================================================================
-- 兼容旧接口
-- ============================================================================

--- CanFeed → CanLevelUp
function M.CanFeed(petIdOrUid, _itemName)
    local uid = type(petIdOrUid) == "string" and petIdOrUid or ""
    if uid == "" then return false, "请使用新版灵宠升级" end
    return M.CanLevelUp(uid)
end

--- DoFeed → DoLevelUp
function M.DoFeed(petIdOrUid, _itemName, callback)
    local uid = type(petIdOrUid) == "string" and petIdOrUid or ""
    if uid == "" then
        if callback then callback(false, "请使用新版灵宠升级") end
        return false, "请使用新版灵宠升级"
    end
    M.DoLevelUp(uid, callback)
    return true, "请求已发送"
end

--- 获取灵宠可喂养物品列表（兼容旧UI）
function M.GetFeedableItems()
    return {}
end

-- ============================================================================
-- 数据迁移
-- ============================================================================

--- 检查灵宠数据是否需要迁移
---@return boolean
function M.NeedsMigration()
    local p = GamePlayer.Get()
    if not p or not p.pets or #p.pets == 0 then return false end
    -- 旧格式: 没有 uid 或 没有 bloodline（有 quality）
    local first = p.pets[1]
    return first.uid == nil or DataPets.IsOldFormat(first)
end

--- 迁移旧灵宠数据
---@param oldPets table[]
---@return table[]
function M.MigrateOldPets(oldPets)
    local newPets = {}
    for i, old in ipairs(oldPets) do
        if not old.uid then
            -- 极旧格式：没有 uid
            local def = GetTemplate(old.id or old.templateId)
            if def then
                local quality = old.quality or def.quality or def.bloodline or "fanqi"
                local bloodline = DataPets.QUALITY_TO_BLOODLINE[quality] or def.bloodline or "fanshou"
                local bl = DataPets.BLOODLINE[bloodline]
                local talentSlots = bl and bl.talentSlots or 1
                newPets[#newPets + 1] = {
                    uid         = "pet_migrated_" .. tostring(old.id or old.templateId) .. "_" .. tostring(i),
                    templateId  = old.id or old.templateId,
                    bloodline   = bloodline,
                    level       = old.level or 1,
                    exp         = old.exp or 0,
                    awakenStage = 0,
                    talents     = DataPets.RollTalents(talentSlots),
                    bond        = 0,
                    transformed = false,
                }
            end
        elseif DataPets.IsOldFormat(old) then
            newPets[#newPets + 1] = DataPets.MigratePetData(old)
        else
            newPets[#newPets + 1] = old
        end
    end
    return newPets
end

-- ============================================================================
-- 红点查询
-- ============================================================================

--- 是否有任何灵宠可升级
---@return boolean
function M.HasLevelUpReady()
    local p = EnsurePetData()
    if not p then return false end
    for _, pet in ipairs(p.pets or {}) do
        if pet.uid then
            local can = M.CanLevelUp(pet.uid)
            if can then return true end
        end
    end
    return false
end

--- 是否有任何灵宠可觉醒
---@return boolean
function M.HasAwakenReady()
    local p = EnsurePetData()
    if not p then return false end
    for _, pet in ipairs(p.pets or {}) do
        if pet.uid then
            local can = M.CanAwaken(pet.uid)
            if can then return true end
        end
    end
    return false
end

return M
