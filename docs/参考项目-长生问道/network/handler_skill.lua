-- ============================================================================
-- 《问道长生》功法处理器（V2 服务端权威）
-- 职责：修炼功法升级/切换 + 武学升级/装备/卸下
-- Actions: cult_art_train, cult_art_switch,
--          martial_art_train, martial_art_equip, martial_art_unequip
-- ============================================================================

local DataCultArts    = require("data_cultivation_arts")
local DataMartialArts = require("data_martial_arts")

local M = {}
M.Actions = {}

-- ============================================================================
-- Action: cult_art_train — 修炼功法升级
-- params: { playerKey }
-- ============================================================================

M.Actions["cult_art_train"] = function(userId, params, reply)
    local playerKey = params.playerKey
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" }); return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" }); return
            end

            local cultArt = playerData.cultivationArt
            if not cultArt or not cultArt.id then
                reply(false, { msg = "未装备修炼功法" }); return
            end

            local artDef = DataCultArts.GetArt(cultArt.id)
            if not artDef then
                reply(false, { msg = "功法数据异常" }); return
            end

            local level = cultArt.level or 1
            if level >= #DataCultArts.LEVELS then
                reply(false, { msg = "功法已达最高等级" }); return
            end

            local nextLv = DataCultArts.GetLevel(level + 1)
            if not nextLv then
                reply(false, { msg = "无法获取升级配置" }); return
            end
            if (playerData.wisdom or 0) < nextLv.wisdomReq then
                reply(false, { msg = "悟性不足" }); return
            end

            cultArt.level = level + 1

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[CultArtTrain] " .. cultArt.id
                        .. " -> Lv." .. cultArt.level
                        .. " uid=" .. tostring(userId))
                    reply(true, {
                        msg = artDef.name .. "升级至Lv." .. cultArt.level,
                        newLevel = cultArt.level,
                    }, { cultivationArt = playerData.cultivationArt })
                end,
                error = function(_, reason)
                    print("[CultArtTrain] 保存失败: " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: cult_art_switch — 切换修炼功法
-- params: { playerKey, artId }
-- ============================================================================

M.Actions["cult_art_switch"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artId = params.artId
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" }); return
    end
    if not artId or artId == "" then
        reply(false, { msg = "缺少 artId" }); return
    end

    local artDef = DataCultArts.GetArt(artId)
    if not artDef then
        reply(false, { msg = "功法不存在" }); return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" }); return
            end

            -- 阵营检查
            local canUse, msg = DataCultArts.CanUse(playerData.race or "human", artId)
            if not canUse then
                reply(false, { msg = msg }); return
            end

            -- 境界检查
            local tier = playerData.tier or 1
            if artDef.realmMin and tier < artDef.realmMin then
                reply(false, { msg = "境界不足，需达到" .. (artDef.realmMin) .. "阶" }); return
            end

            -- 解锁检查（initial 类型始终可用，drop 类型需已解锁）
            local unlockedCultArts = playerData.unlockedCultArts or {}
            if not DataCultArts.IsUnlocked(artDef, unlockedCultArts) then
                reply(false, { msg = "该功法尚未解锁" }); return
            end

            -- 已装备检查
            local cultArt = playerData.cultivationArt
            if cultArt and cultArt.id == artId then
                reply(false, { msg = "已装备该功法" }); return
            end

            -- 切换（等级重置为 1）
            playerData.cultivationArt = { id = artId, level = 1 }

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[CultArtSwitch] -> " .. artId
                        .. " uid=" .. tostring(userId))
                    reply(true, {
                        msg = "切换修炼功法：" .. artDef.name,
                    }, { cultivationArt = playerData.cultivationArt })
                end,
                error = function(_, reason)
                    print("[CultArtSwitch] 保存失败: " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: martial_art_train — 武学升级
-- params: { playerKey, artId }
-- ============================================================================

M.Actions["martial_art_train"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artId = params.artId
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" }); return
    end
    if not artId or artId == "" then
        reply(false, { msg = "缺少 artId" }); return
    end

    local artDef = DataMartialArts.GetArt(artId)
    if not artDef then
        reply(false, { msg = "武学不存在" }); return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" }); return
            end

            local ma = playerData.martialArts
            if not ma then
                reply(false, { msg = "无武学数据" }); return
            end

            -- 查找拥有的武学
            local found = nil
            for _, owned in ipairs(ma.owned or {}) do
                if owned.id == artId then found = owned; break end
            end
            if not found then
                reply(false, { msg = "未拥有该武学" }); return
            end

            local level = found.level or 1
            if level >= (artDef.maxLevel or 10) then
                reply(false, { msg = "武学已达最高等级" }); return
            end

            local nextLv = DataMartialArts.GetLevel(level + 1)
            if not nextLv then
                reply(false, { msg = "无法获取升级配置" }); return
            end
            if (playerData.wisdom or 0) < nextLv.wisdomReq then
                reply(false, { msg = "悟性不足" }); return
            end

            found.level = level + 1

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[MartialArtTrain] " .. artId
                        .. " -> Lv." .. found.level
                        .. " uid=" .. tostring(userId))
                    reply(true, {
                        msg = artDef.name .. "升级至Lv." .. found.level,
                        newLevel = found.level,
                    }, { martialArts = playerData.martialArts })
                end,
                error = function(_, reason)
                    print("[MartialArtTrain] 保存失败: " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: martial_art_equip — 装备武学
-- params: { playerKey, artId, slot? }
-- ============================================================================

M.Actions["martial_art_equip"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local artId = params.artId
    local slot = params.slot
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" }); return
    end
    if not artId or artId == "" then
        reply(false, { msg = "缺少 artId" }); return
    end

    local artDef = DataMartialArts.GetArt(artId)
    if not artDef then
        reply(false, { msg = "武学不存在" }); return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" }); return
            end

            local ma = playerData.martialArts
            if not ma then
                reply(false, { msg = "无武学数据" }); return
            end

            -- 检查拥有
            local found = false
            for _, owned in ipairs(ma.owned or {}) do
                if owned.id == artId then found = true; break end
            end
            if not found then
                reply(false, { msg = "未拥有该武学" }); return
            end

            -- 品阶境界检查
            local canEquip, eqMsg = DataMartialArts.CanEquip(playerData.tier or 1, artId)
            if not canEquip then
                reply(false, { msg = eqMsg }); return
            end

            -- 已装备检查
            local equipped = ma.equipped or {}
            for i = 1, DataMartialArts.MAX_EQUIPPED do
                if equipped[i] == artId then
                    reply(false, { msg = "已装备该武学" }); return
                end
            end

            -- 确定槽位
            local targetSlot = slot
            if targetSlot then
                if targetSlot < 1 or targetSlot > DataMartialArts.MAX_EQUIPPED then
                    reply(false, { msg = "无效槽位" }); return
                end
            else
                -- 自动查找空槽
                for i = 1, DataMartialArts.MAX_EQUIPPED do
                    if not equipped[i] then targetSlot = i; break end
                end
                if not targetSlot then
                    reply(false, { msg = "装备栏已满" }); return
                end
            end

            -- 确保 equipped 数组足够长
            while #equipped < DataMartialArts.MAX_EQUIPPED do
                equipped[#equipped + 1] = false  -- JSON null 占位
            end
            equipped[targetSlot] = artId
            ma.equipped = equipped

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[MartialArtEquip] slot" .. targetSlot
                        .. " = " .. artId
                        .. " uid=" .. tostring(userId))
                    reply(true, {
                        msg = "装备武学：" .. artDef.name,
                        slot = targetSlot,
                    }, { martialArts = playerData.martialArts })
                end,
                error = function(_, reason)
                    print("[MartialArtEquip] 保存失败: " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

-- ============================================================================
-- Action: martial_art_unequip — 卸下武学
-- params: { playerKey, slot }
-- ============================================================================

M.Actions["martial_art_unequip"] = function(userId, params, reply)
    local playerKey = params.playerKey
    local slot = params.slot
    if not playerKey or playerKey == "" then
        reply(false, { msg = "缺少 playerKey" }); return
    end
    if not slot or slot < 1 or slot > DataMartialArts.MAX_EQUIPPED then
        reply(false, { msg = "无效槽位" }); return
    end

    serverCloud:Get(userId, playerKey, {
        ok = function(scores)
            local playerData = scores and scores[playerKey]
            if type(playerData) ~= "table" then
                reply(false, { msg = "玩家数据解析失败" }); return
            end

            local ma = playerData.martialArts
            if not ma then
                reply(false, { msg = "无武学数据" }); return
            end

            local equipped = ma.equipped or {}
            if not equipped[slot] then
                reply(false, { msg = "该槽位无武学" }); return
            end

            local removedId = equipped[slot]
            local artDef = DataMartialArts.GetArt(removedId)
            equipped[slot] = false  -- JSON null 占位
            ma.equipped = equipped

            serverCloud:Set(userId, playerKey, playerData, {
                ok = function()
                    print("[MartialArtUnequip] slot" .. slot
                        .. " cleared (" .. tostring(removedId) .. ")"
                        .. " uid=" .. tostring(userId))
                    reply(true, {
                        msg = "已卸下武学" .. (artDef and ("：" .. artDef.name) or ""),
                        slot = slot,
                    }, { martialArts = playerData.martialArts })
                end,
                error = function(_, reason)
                    print("[MartialArtUnequip] 保存失败: " .. tostring(reason))
                    reply(false, { msg = "数据保存失败" })
                end,
            })
        end,
        error = function()
            reply(false, { msg = "读取数据失败" })
        end,
    })
end

return M
