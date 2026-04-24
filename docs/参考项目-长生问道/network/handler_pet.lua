-- ============================================================================
-- 《问道长生》灵宠处理器（服务端权威 · 血脉进化体系）
-- Actions: pet_try_capture, pet_level_up, pet_awaken, pet_decompose,
--          pet_set_active, pet_transform
-- 兼容旧 Actions: pet_ascend → pet_awaken, pet_feed → pet_level_up
-- ============================================================================

local M = {}
M.Actions = {}

local DataPets  = require("data_pets")
local DataWorld = require("data_world")
local DataItems = require("data_items")

-- ============================================================================
-- 内部工具
-- ============================================================================

local uidCounter_ = 0
local function GenPetUid()
    uidCounter_ = uidCounter_ + 1
    return "pet_" .. tostring(os.time()) .. "_" .. tostring(uidCounter_) .. "_" .. tostring(math.random(1000, 9999))
end

local function FindPetByUid(pets, uid)
    if not uid or uid == "" then return nil, nil end
    for i, pet in ipairs(pets) do
        if pet.uid == uid then return pet, i end
    end
    return nil, nil
end

--- 迁移旧数据（quality → bloodline, ascStage → awakenStage）
local function MigrateIfNeeded(playerData)
    if not playerData.pets or #playerData.pets == 0 then return false end
    local migrated = false

    -- 极旧格式：没有 uid
    if playerData.pets[1].uid == nil then
        local newPets = {}
        for _, old in ipairs(playerData.pets) do
            local def = DataPets.GetPet(old.id) or DataWorld.GetPet(old.id)
            if def then
                local bloodline = def.bloodline or DataPets.QUALITY_TO_BLOODLINE[def.quality or "fanqi"] or "fanshou"
                local bl = DataPets.BLOODLINE[bloodline]
                newPets[#newPets + 1] = {
                    uid         = GenPetUid(),
                    templateId  = old.id,
                    bloodline   = bloodline,
                    level       = old.level or 1,
                    exp         = old.exp or 0,
                    awakenStage = 0,
                    talents     = DataPets.RollTalents(bl and bl.talentSlots or 1),
                    bond        = 0,
                    transformed = false,
                }
            end
        end
        playerData.pets = newPets
        if playerData.activePetId and playerData.activePetId ~= 0 then
            for _, pet in ipairs(newPets) do
                if pet.templateId == playerData.activePetId then
                    playerData.activePetUid = pet.uid
                    break
                end
            end
        end
        playerData.activePetId = nil
        if not playerData.activePetUid then playerData.activePetUid = "" end
        migrated = true
    end

    -- 旧品质格式：有 quality 无 bloodline
    for i, pet in ipairs(playerData.pets) do
        if DataPets.IsOldFormat(pet) then
            playerData.pets[i] = DataPets.MigratePetData(pet)
            migrated = true
        end
    end

    return migrated
end

--- 按血脉加权随机
local function RollBloodline(rates)
    local total = 0
    for _, w in pairs(rates) do total = total + w end
    local r = math.random(1, math.max(total, 1))
    local acc = 0
    for _, key in ipairs(DataPets.BLOODLINE_ORDER) do
        local w = rates[key] or 0
        if w > 0 then
            acc = acc + w
            if r <= acc then return key end
        end
    end
    return "fanshou"
end

--- 按血脉随机选模板
local function PickPetTemplate(bloodline)
    local candidates = DataPets.GetPetsByBloodline(bloodline)
    if #candidates == 0 then
        -- 降级查找相邻血脉
        local rank = DataPets.BLOODLINE_RANK[bloodline] or 1
        for _, pet in ipairs(DataPets.PETS) do
            local r = DataPets.BLOODLINE_RANK[pet.bloodline] or 1
            if math.abs(r - rank) <= 1 then
                candidates[#candidates + 1] = pet
            end
        end
    end
    if #candidates == 0 then return nil end
    return candidates[math.random(#candidates)]
end

local function ConsumeItem(bagItems, itemName, count)
    for i, item in ipairs(bagItems) do
        if item.name == itemName and (item.count or 0) >= count then
            item.count = item.count - count
            if item.count <= 0 then table.remove(bagItems, i) end
            return true
        end
    end
    return false
end

local function AddItem(bagItems, itemName, count)
    for _, item in ipairs(bagItems) do
        if item.name == itemName then
            item.count = (item.count or 0) + count
            return
        end
    end
    bagItems[#bagItems + 1] = { name = itemName, count = count }
end

-- ============================================================================
-- Action: pet_try_capture — 捕获灵宠（血脉概率 + 随机天赋）
-- ============================================================================
M.Actions["pet_try_capture"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local areaId = params.areaId
    if not playerKey or not areaId then
        reply(false, { error = "missing params" })
        return
    end

    local captureRate = DataWorld.PET_CAPTURE_RATES[areaId] or 10
    if math.random(100) > captureRate then
        reply(true, { captured = false, reason = "miss" })
        return
    end

    local areaIndex = DataWorld.AREA_INDEX[areaId] or 1
    local bloodlineRates = DataPets.GetCaptureRates(areaIndex)
    local bloodline = RollBloodline(bloodlineRates)

    local template = PickPetTemplate(bloodline)
    if not template then
        reply(true, { captured = false, reason = "no_candidate" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = (scores and scores[playerKey]) or {}
            if type(playerData) ~= "table" then playerData = {} end
            if not playerData.pets then playerData.pets = {} end
            if not playerData.bagItems then playerData.bagItems = {} end
            MigrateIfNeeded(playerData)

            local bl = DataPets.BLOODLINE[bloodline]
            local talentSlots = bl and bl.talentSlots or 1
            local talents = DataPets.RollTalents(talentSlots)

            local newPet = {
                uid         = GenPetUid(),
                templateId  = template.id,
                bloodline   = bloodline,
                level       = 1,
                exp         = 0,
                awakenStage = 0,
                talents     = talents,
                bond        = 0,
                transformed = false,
            }
            playerData.pets[#playerData.pets + 1] = newPet

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    local blLabel = bl and bl.label or "未知"
                    reply(true, {
                        captured       = true,
                        petUid         = newPet.uid,
                        petId          = template.id,
                        petName        = template.name,
                        bloodline      = bloodline,
                        bloodlineLabel = blLabel,
                        talents        = talents,
                    }, {
                        pets = playerData.pets,
                    })
                end,
                error = function(err)
                    reply(false, { error = "save_failed: " .. tostring(err) })
                end,
            })
        end,
        error = function(err)
            reply(false, { error = "read_failed: " .. tostring(err) })
        end,
    })
end

-- ============================================================================
-- Action: pet_level_up — 升级（境界压制校验）
-- ============================================================================
M.Actions["pet_level_up"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local petUid    = params.petUid
    if not playerKey or not petUid then
        reply(false, { error = "missing params" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = (scores and scores[playerKey]) or {}
            if type(playerData) ~= "table" then playerData = {} end
            if not playerData.pets then playerData.pets = {} end
            if not playerData.bagItems then playerData.bagItems = {} end
            MigrateIfNeeded(playerData)

            local pet = FindPetByUid(playerData.pets, petUid)
            if not pet then
                reply(false, { msg = "未拥有此灵宠" })
                return
            end

            local bloodline = pet.bloodline or "fanshou"
            local ownerTier = playerData.tier or 1
            local maxLv = DataPets.GetMaxLevel(bloodline, pet.awakenStage or 0, ownerTier)
            local level = pet.level or 1
            if level >= maxLv then
                reply(false, { msg = "已达等级上限" })
                return
            end

            local lvInfo = DataItems.GetPetLevelInfo(level)
            if not lvInfo then
                reply(false, { msg = "等级数据异常" })
                return
            end

            if not ConsumeItem(playerData.bagItems, "灵兽精血", lvInfo.jingxue) then
                reply(false, { msg = "灵兽精血不足" })
                return
            end

            local lingStone = playerData.lingStone or 0
            if lingStone < lvInfo.lingshi then
                AddItem(playerData.bagItems, "灵兽精血", lvInfo.jingxue)
                reply(false, { msg = "灵石不足" })
                return
            end

            pet.level = level + 1
            -- 出战中升级增加羁绊
            if playerData.activePetUid == petUid then
                pet.bond = (pet.bond or 0) + DataPets.BOND_PER_LEVEL_UP
            end
            local newLingStone = lingStone - lvInfo.lingshi

            serverCloud.money:Cost(userId, "lingStone", lvInfo.lingshi, {
                ok = function()
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            local def = DataPets.GetPet(pet.templateId)
                            reply(true, {
                                petUid   = petUid,
                                petName  = def and def.name or "灵宠",
                                newLevel = pet.level,
                            }, {
                                pets      = playerData.pets,
                                bagItems  = playerData.bagItems,
                                lingStone = newLingStone,
                            })
                        end,
                        error = function(err)
                            reply(false, { error = "save_failed: " .. tostring(err) })
                        end,
                    })
                end,
                error = function(err)
                    AddItem(playerData.bagItems, "灵兽精血", lvInfo.jingxue)
                    pet.level = level
                    reply(false, { msg = "灵石扣除失败" })
                end,
            })
        end,
        error = function(err)
            reply(false, { error = "read_failed: " .. tostring(err) })
        end,
    })
end

-- ============================================================================
-- Action: pet_awaken — 血脉觉醒（替代旧升阶）
-- ============================================================================
M.Actions["pet_awaken"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local petUid    = params.petUid
    if not playerKey or not petUid then
        reply(false, { error = "missing params" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = (scores and scores[playerKey]) or {}
            if type(playerData) ~= "table" then playerData = {} end
            if not playerData.pets then playerData.pets = {} end
            if not playerData.bagItems then playerData.bagItems = {} end
            MigrateIfNeeded(playerData)

            local pet = FindPetByUid(playerData.pets, petUid)
            if not pet then
                reply(false, { msg = "未拥有此灵宠" })
                return
            end

            local bloodline = pet.bloodline or "fanshou"
            local blInfo = DataPets.BLOODLINE[bloodline]
            if not blInfo then
                reply(false, { msg = "未知血脉" })
                return
            end

            local awakenStage = pet.awakenStage or 0
            if awakenStage >= blInfo.awakenStages then
                reply(false, { msg = "已达觉醒圆满" })
                return
            end

            -- 需满级
            local ownerTier = playerData.tier or 1
            local maxLv = DataPets.GetMaxLevel(bloodline, awakenStage, ownerTier)
            if (pet.level or 1) < maxLv then
                reply(false, { msg = "需达到等级上限才能觉醒" })
                return
            end

            local info = DataPets.GetAwakenInfo(bloodline, awakenStage + 1)
            if not info then
                reply(false, { msg = "觉醒数据异常" })
                return
            end

            -- 扣灵兽精血
            if not ConsumeItem(playerData.bagItems, "灵兽精血", info.jingxue) then
                reply(false, { msg = "灵兽精血不足（需要" .. info.jingxue .. "）" })
                return
            end

            -- 天赋加成：觉醒成功率
            local rate = info.rate
            for _, tid in ipairs(pet.talents or {}) do
                local tdef = DataPets.TALENT_MAP[tid]
                if tdef and tdef.effect and tdef.effect.awakenRateBonus then
                    rate = math.min(100, rate + math.floor(info.rate * tdef.effect.awakenRateBonus))
                end
            end

            local success = math.random(100) <= rate
            local newTalent = nil

            if success then
                pet.awakenStage = awakenStage + 1
                pet.bond = (pet.bond or 0) + DataPets.BOND_PER_AWAKEN

                -- 解锁天赋槽位
                if info.unlockTalent then
                    local existing = pet.talents or {}
                    local rolled = DataPets.RollTalents(1, existing)
                    if #rolled > 0 then
                        newTalent = rolled[1]
                        pet.talents = pet.talents or {}
                        pet.talents[#pet.talents + 1] = newTalent
                    end
                end
            end

            serverCloud.money:Cost(userId, "lingStone", info.lingshi, {
                ok = function()
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            local def = DataPets.GetPet(pet.templateId)
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    reply(true, {
                                        petUid       = petUid,
                                        petName      = def and def.name or "灵宠",
                                        success      = success,
                                        stageName    = info.name,
                                        newAwakenStage = pet.awakenStage,
                                        newTalent    = newTalent,
                                    }, {
                                        pets      = playerData.pets,
                                        bagItems  = playerData.bagItems,
                                        lingStone = moneys and moneys["lingStone"] or 0,
                                    })
                                end,
                                error = function()
                                    reply(true, {
                                        petUid = petUid, success = success,
                                        petName = def and def.name or "灵宠",
                                        stageName = info.name,
                                        newAwakenStage = pet.awakenStage,
                                        newTalent = newTalent,
                                    }, { pets = playerData.pets, bagItems = playerData.bagItems })
                                end,
                            })
                        end,
                        error = function(err)
                            reply(false, { error = "save_failed: " .. tostring(err) })
                        end,
                    })
                end,
                error = function(err)
                    AddItem(playerData.bagItems, "灵兽精血", info.jingxue)
                    if success then pet.awakenStage = awakenStage end
                    reply(false, { msg = "灵石扣除失败" })
                end,
            })
        end,
        error = function(err)
            reply(false, { error = "read_failed: " .. tostring(err) })
        end,
    })
end

-- 兼容旧 pet_ascend
M.Actions["pet_ascend"] = M.Actions["pet_awaken"]

-- ============================================================================
-- Action: pet_decompose — 分解（按血脉返还）
-- ============================================================================
M.Actions["pet_decompose"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local petUid    = params.petUid
    if not playerKey or not petUid then
        reply(false, { error = "missing params" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = (scores and scores[playerKey]) or {}
            if type(playerData) ~= "table" then playerData = {} end
            if not playerData.pets then playerData.pets = {} end
            if not playerData.bagItems then playerData.bagItems = {} end
            MigrateIfNeeded(playerData)

            local pet, idx = FindPetByUid(playerData.pets, petUid)
            if not pet or not idx then
                reply(false, { msg = "未拥有此灵宠" })
                return
            end

            if playerData.activePetUid == petUid then
                reply(false, { msg = "出战中的灵宠不能分解" })
                return
            end

            local bloodline = pet.bloodline or "fanshou"
            local yield = DataPets.DECOMPOSE_YIELD[bloodline]
            if not yield then
                reply(false, { msg = "该血脉无法分解" })
                return
            end

            local def = DataPets.GetPet(pet.templateId)
            local petName = def and def.name or "灵宠"

            table.remove(playerData.pets, idx)

            local yields = {}
            if yield.jingxue and yield.jingxue > 0 then
                AddItem(playerData.bagItems, "灵兽精血", yield.jingxue)
                yields["灵兽精血"] = yield.jingxue
            end

            -- 灵石通过 money API
            if yield.lingshi and yield.lingshi > 0 then
                serverCloud.money:Add(userId, "lingStone", yield.lingshi, {
                    ok = function()
                        serverCloud:Set(userId, playerKey, playerData, {
                            ok = function()
                                serverCloud.money:Get(userId, {
                                    ok = function(moneys)
                                        yields["灵石"] = yield.lingshi
                                        reply(true, { petName = petName, yields = yields }, {
                                            pets = playerData.pets,
                                            bagItems = playerData.bagItems,
                                            lingStone = moneys and moneys["lingStone"] or 0,
                                        })
                                    end,
                                    error = function()
                                        yields["灵石"] = yield.lingshi
                                        reply(true, { petName = petName, yields = yields }, {
                                            pets = playerData.pets, bagItems = playerData.bagItems,
                                        })
                                    end,
                                })
                            end,
                            error = function(err)
                                reply(false, { error = "save_failed: " .. tostring(err) })
                            end,
                        })
                    end,
                    error = function(err)
                        reply(false, { error = "money_add_failed: " .. tostring(err) })
                    end,
                })
            else
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        reply(true, { petName = petName, yields = yields }, {
                            pets = playerData.pets, bagItems = playerData.bagItems,
                        })
                    end,
                    error = function(err)
                        reply(false, { error = "save_failed: " .. tostring(err) })
                    end,
                })
            end
        end,
        error = function(err)
            reply(false, { error = "read_failed: " .. tostring(err) })
        end,
    })
end

-- ============================================================================
-- Action: pet_set_active — 出战/召回
-- ============================================================================
M.Actions["pet_set_active"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local petUid    = params.petUid
    if not playerKey or petUid == nil then
        reply(false, { error = "missing params" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = (scores and scores[playerKey]) or {}
            if type(playerData) ~= "table" then playerData = {} end
            if not playerData.pets then playerData.pets = {} end
            MigrateIfNeeded(playerData)

            if petUid == "" or petUid == 0 then
                playerData.activePetUid = ""
                playerData.activePetId = nil
                serverCloud:Set(userId, playerKey, playerData, {
                    ok = function()
                        reply(true, { petUid = "" }, { activePetUid = "" })
                    end,
                    error = function(err)
                        reply(false, { error = "save_failed: " .. tostring(err) })
                    end,
                })
                return
            end

            local pet = FindPetByUid(playerData.pets, petUid)
            if not pet then
                reply(false, { msg = "未拥有此灵宠" })
                return
            end

            playerData.activePetUid = petUid
            playerData.activePetId = nil
            local def = DataPets.GetPet(pet.templateId)
            local petName = def and def.name or "灵宠"

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    reply(true, {
                        petUid = petUid,
                        msg = petName .. "已出战",
                    }, { activePetUid = petUid })
                end,
                error = function(err)
                    reply(false, { error = "save_failed: " .. tostring(err) })
                end,
            })
        end,
        error = function(err)
            reply(false, { error = "read_failed: " .. tostring(err) })
        end,
    })
end

-- ============================================================================
-- Action: pet_transform — 化形（神兽/鸿蒙 + 满觉醒 + 高羁绊）
-- ============================================================================
M.Actions["pet_transform"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local petUid    = params.petUid
    if not playerKey or not petUid then
        reply(false, { error = "missing params" })
        return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = (scores and scores[playerKey]) or {}
            if type(playerData) ~= "table" then playerData = {} end
            if not playerData.pets then playerData.pets = {} end
            if not playerData.bagItems then playerData.bagItems = {} end
            MigrateIfNeeded(playerData)

            local pet = FindPetByUid(playerData.pets, petUid)
            if not pet then
                reply(false, { msg = "未拥有此灵宠" })
                return
            end

            if pet.transformed then
                reply(false, { msg = "已化形" })
                return
            end

            local bloodline = pet.bloodline or "fanshou"
            local bondInfo = DataPets.GetBondLevel(pet.bond or 0)
            local ok, reason = DataPets.CanTransform(bloodline, pet.awakenStage or 0, bondInfo.level)
            if not ok then
                reply(false, { msg = reason })
                return
            end

            local req = DataPets.TRANSFORM_REQUIRE
            if not ConsumeItem(playerData.bagItems, "灵兽精血", req.jingxue) then
                reply(false, { msg = "灵兽精血不足（需要" .. req.jingxue .. "）" })
                return
            end

            pet.transformed = true

            serverCloud.money:Cost(userId, "lingStone", req.lingshi, {
                ok = function()
                    serverCloud:Set(userId, playerKey, playerData, {
                        ok = function()
                            local def = DataPets.GetPet(pet.templateId)
                            serverCloud.money:Get(userId, {
                                ok = function(moneys)
                                    reply(true, {
                                        petUid        = petUid,
                                        petName       = def and def.name or "灵宠",
                                        transformName = def and def.transformName or nil,
                                    }, {
                                        pets      = playerData.pets,
                                        bagItems  = playerData.bagItems,
                                        lingStone = moneys and moneys["lingStone"] or 0,
                                    })
                                end,
                                error = function()
                                    reply(true, {
                                        petUid = petUid,
                                        petName = def and def.name or "灵宠",
                                        transformName = def and def.transformName or nil,
                                    }, { pets = playerData.pets, bagItems = playerData.bagItems })
                                end,
                            })
                        end,
                        error = function(err)
                            reply(false, { error = "save_failed: " .. tostring(err) })
                        end,
                    })
                end,
                error = function(err)
                    AddItem(playerData.bagItems, "灵兽精血", req.jingxue)
                    pet.transformed = false
                    reply(false, { msg = "灵石扣除失败" })
                end,
            })
        end,
        error = function(err)
            reply(false, { error = "read_failed: " .. tostring(err) })
        end,
    })
end

-- ============================================================================
-- 兼容旧 pet_feed
-- ============================================================================
M.Actions["pet_feed"] = function(userId, params, reply)
    if params.petUid then
        return M.Actions["pet_level_up"](userId, params, reply)
    end
    reply(false, { msg = "请更新客户端版本" })
end

return M
