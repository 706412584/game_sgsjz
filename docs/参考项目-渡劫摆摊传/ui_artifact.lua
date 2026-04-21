-- ============================================================================
-- ui_artifact.lua — 法宝系统界面 (Modal弹窗)
-- 展示装备槽、法宝列表、炼制/装备/卸下/升阶操作
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local M = {}

local modal_ = nil
local contentPanel_ = nil

-- ========== 工具函数 ==========

--- 获取法宝加成描述文本
---@param art table 法宝配置
---@param level number 等级
---@return string
local function getBonusText(art, level)
    if not art.bonus then return "" end
    local val = art.bonus.value * (level or 1) * 100
    local typeNames = {
        material_rate = "材料产出",
        sell_price = "商品售价",
        craft_speed = "制作速度",
        reputation = "口碑获取",
        lifespan = "寿元消耗减少",
        all = "全属性",
    }
    local name = typeNames[art.bonus.type] or art.bonus.type
    return name .. " +" .. string.format("%.0f", val) .. "%"
end

--- 获取材料需求描述
---@param recipe table {matId = count}
---@return string
local function getRecipeText(recipe)
    local parts = {}
    for matId, count in pairs(recipe) do
        local mat = Config.GetMaterialById(matId)
        local name = mat and mat.name or matId
        table.insert(parts, name .. "x" .. count)
    end
    return table.concat(parts, " ")
end

--- 检查材料是否足够
---@param recipe table
---@return boolean
local function hasEnoughMaterials(recipe)
    for matId, count in pairs(recipe) do
        local have = State.state.materials and State.state.materials[matId] or 0
        if have < count then return false end
    end
    return true
end

--- 法宝品质颜色(根据解锁境界)
---@param unlockRealm number
---@return table
local function getQualityColor(unlockRealm)
    if unlockRealm >= 8 then return { 255, 180, 50, 255 } end   -- 大乘 金色
    if unlockRealm >= 6 then return { 200, 120, 220, 255 } end  -- 炼虚 紫色
    if unlockRealm >= 5 then return { 220, 80, 80, 255 } end    -- 化神 红色
    if unlockRealm >= 4 then return { 80, 160, 230, 255 } end   -- 元婴 蓝色
    if unlockRealm >= 3 then return { 100, 210, 140, 255 } end  -- 金丹 绿色
    return { 200, 200, 200, 255 }                                -- 筑基 白色
end

-- ========== 渲染装备槽 ==========

local function renderEquipSlots(parent)
    local s = State.state
    local maxSlots = Config.GetArtifactSlotCount(s.realmLevel)
    local equipped = s.equippedArtifacts or {}

    -- 标题
    parent:AddChild(UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        width = "100%",
        marginBottom = 4,
        children = {
            UI.Label {
                text = "装备栏 (" .. #equipped .. "/" .. maxSlots .. ")",
                fontSize = 12,
                fontColor = Config.Colors.textGold,
                fontWeight = "bold",
            },
            UI.Label {
                text = "下一槽位: " .. (maxSlots < 3 and
                    (Config.ArtifactSlots[maxSlots + 1] and
                        Config.Realms[Config.ArtifactSlots[maxSlots + 1].realm] and
                        Config.Realms[Config.ArtifactSlots[maxSlots + 1].realm].name or "已满")
                    or "已满"),
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
            },
        },
    })

    -- 槽位行
    local slotRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        gap = 6,
        justifyContent = "center",
        marginBottom = 8,
    }

    for i = 1, 3 do
        local eq = equipped[i]
        local isLocked = i > maxSlots
        local artCfg = eq and Config.GetArtifactById(eq.id) or nil

        local slotColor = isLocked and { 30, 30, 40, 255 } or { 50, 55, 75, 200 }
        local borderCol = isLocked and { 60, 60, 70, 100 }
            or (artCfg and getQualityColor(artCfg.unlockRealm) or Config.Colors.border)

        local slotChildren = {}
        if isLocked then
            table.insert(slotChildren, UI.Label {
                text = "未解锁",
                fontSize = 9,
                fontColor = { 80, 80, 90, 200 },
                textAlign = "center",
            })
        elseif artCfg then
            table.insert(slotChildren, UI.Label {
                text = artCfg.name,
                fontSize = 10,
                fontColor = getQualityColor(artCfg.unlockRealm),
                fontWeight = "bold",
                textAlign = "center",
            })
            table.insert(slotChildren, UI.Label {
                text = (eq.level or 1) .. "阶",
                fontSize = 8,
                fontColor = Config.Colors.textGold,
                textAlign = "center",
            })
            table.insert(slotChildren, UI.Label {
                text = getBonusText(artCfg, eq.level or 1),
                fontSize = 7,
                fontColor = Config.Colors.textGreen,
                textAlign = "center",
            })
            -- 耐久条
            local maxDur = Config.ArtifactDurability.max
            local curDur = eq.durability or maxDur
            local durRatio = curDur / maxDur
            local durColor = durRatio > 0.5 and Config.Colors.jade
                or (durRatio > 0.2 and Config.Colors.textGold or Config.Colors.danger)
            table.insert(slotChildren, UI.Panel {
                width = "90%", height = 5, marginTop = 1,
                backgroundColor = { 30, 30, 40, 200 }, borderRadius = 2, overflow = "hidden",
                children = {
                    UI.Panel {
                        width = math.floor(durRatio * 100) .. "%", height = "100%",
                        backgroundColor = durColor, borderRadius = 2,
                    },
                },
            })
            table.insert(slotChildren, UI.Label {
                text = curDur .. "/" .. maxDur,
                fontSize = 6,
                fontColor = durColor,
                textAlign = "center",
            })
            -- 按钮行: 卸下 + 修复
            local artIdCopy = eq.id
            local btnRow = UI.Panel {
                flexDirection = "column", gap = 2, marginTop = 1, width = "100%", alignItems = "center",
            }
            btnRow:AddChild(UI.Button {
                text = "卸下",
                fontSize = 7,
                height = 16,
                width = "90%",
                paddingHorizontal = 4,
                backgroundColor = { 80, 40, 40, 255 },
                textColor = { 200, 120, 120, 255 },
                borderRadius = 3,
                onClick = function()
                    GameCore.SendGameAction("unequip_artifact", { artId = artIdCopy })
                end,
            })
            if curDur < maxDur then
                btnRow:AddChild(UI.Button {
                    text = "修复",
                    fontSize = 7,
                    height = 16,
                    width = "90%",
                    paddingHorizontal = 4,
                    backgroundColor = Config.Colors.jadeDark,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 3,
                    onClick = function()
                        GameCore.SendGameAction("repair_artifact", { artId = artIdCopy })
                    end,
                })
            end
            table.insert(slotChildren, btnRow)
        else
            table.insert(slotChildren, UI.Label {
                text = "空",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
            })
        end

        slotRow:AddChild(UI.Panel {
            width = 80,
            height = 125,
            backgroundColor = slotColor,
            borderRadius = 8,
            borderWidth = 1,
            borderColor = borderCol,
            justifyContent = "center",
            alignItems = "center",
            padding = 4,
            gap = 1,
            children = slotChildren,
        })
    end

    parent:AddChild(slotRow)
end

-- ========== 渲染法宝列表 ==========

local function renderArtifactList(parent)
    local s = State.state
    local realmLevel = s.realmLevel
    local artifacts = s.artifacts or {}
    local equipped = s.equippedArtifacts or {}
    local maxSlots = Config.GetArtifactSlotCount(realmLevel)

    -- 标题
    parent:AddChild(UI.Label {
        text = "法宝图鉴",
        fontSize = 12,
        fontColor = Config.Colors.textPrimary,
        fontWeight = "bold",
        marginBottom = 4,
    })

    for _, artCfg in ipairs(Config.Artifacts) do
        local artId = artCfg.id
        local owned = artifacts[artId]
        local count = owned and owned.count or 0
        local level = owned and owned.level or 1
        local unlocked = realmLevel >= artCfg.unlockRealm
        local qualColor = getQualityColor(artCfg.unlockRealm)

        -- 检查是否已装备
        local isEquipped = false
        for _, eq in ipairs(equipped) do
            if eq.id == artId then isEquipped = true; break end
        end

        -- 卡片
        local cardBg = unlocked and { 45, 50, 70, 230 } or { 35, 38, 50, 200 }
        local cardBorder = unlocked and qualColor or { 60, 60, 70, 100 }

        local cardChildren = {}

        -- 第1行: 名称 + 等级 + 数量
        local headerChildren = {
            UI.Label {
                text = artCfg.name,
                fontSize = 12,
                fontColor = unlocked and qualColor or { 100, 100, 110, 200 },
                fontWeight = "bold",
                flexShrink = 1,
            },
        }
        if owned then
            table.insert(headerChildren, UI.Label {
                text = level .. "阶",
                fontSize = 9,
                fontColor = Config.Colors.textGold,
                marginLeft = 4,
            })
            table.insert(headerChildren, UI.Label {
                text = "x" .. count,
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                marginLeft = 4,
            })
        end
        if isEquipped then
            table.insert(headerChildren, UI.Label {
                text = "[已装备]",
                fontSize = 9,
                fontColor = Config.Colors.jade,
                marginLeft = 4,
            })
        end
        if not unlocked then
            local realmName = Config.Realms[artCfg.unlockRealm] and Config.Realms[artCfg.unlockRealm].name or ""
            table.insert(headerChildren, UI.Label {
                text = realmName .. "解锁",
                fontSize = 9,
                fontColor = { 120, 80, 80, 200 },
                marginLeft = 4,
            })
        end

        table.insert(cardChildren, UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            children = headerChildren,
        })

        -- 第2行: 描述
        table.insert(cardChildren, UI.Label {
            text = artCfg.desc,
            fontSize = 9,
            fontColor = unlocked and Config.Colors.textSecond or { 80, 80, 90, 180 },
            width = "100%",
        })

        -- 第3行: 加成效果
        table.insert(cardChildren, UI.Label {
            text = "效果: " .. getBonusText(artCfg, owned and level or 1),
            fontSize = 9,
            fontColor = unlocked and Config.Colors.textGreen or { 80, 100, 80, 180 },
        })

        -- 第4行: 操作按钮
        if unlocked then
            local btnRow = UI.Panel {
                flexDirection = "row",
                gap = 6,
                width = "100%",
                marginTop = 2,
            }

            -- 炼制按钮
            local enoughMat = hasEnoughMaterials(artCfg.recipe)
            local enoughLingshi = s.lingshi >= artCfg.lingshiCost
            local canCraft = enoughMat and enoughLingshi

            -- 材料需求提示
            local costParts = {}
            table.insert(costParts, getRecipeText(artCfg.recipe))
            if artCfg.lingshiCost > 0 then
                table.insert(costParts, HUD.FormatNumber(artCfg.lingshiCost) .. "灵石")
            end
            local costText = table.concat(costParts, " + ")

            local craftArtId = artId  -- 闭包捕获
            btnRow:AddChild(UI.Button {
                text = "炼制",
                fontSize = 9,
                height = 22,
                paddingHorizontal = 8,
                backgroundColor = canCraft and Config.Colors.jadeDark or { 50, 55, 65, 200 },
                textColor = canCraft and { 255, 255, 255, 255 } or { 100, 100, 110, 200 },
                borderRadius = 4,
                onClick = function()
                    if not canCraft then
                        UI.Toast.Show("材料或灵石不足: " .. costText, { variant = "warning", duration = 2 })
                        return
                    end
                    GameCore.SendGameAction("craft_artifact", { artId = craftArtId })
                end,
            })

            -- 材料需求文本
            btnRow:AddChild(UI.Label {
                text = costText,
                fontSize = 8,
                fontColor = canCraft and Config.Colors.textSecond or { 120, 80, 80, 200 },
                alignSelf = "center",
                flexShrink = 1,
            })

            table.insert(cardChildren, btnRow)

            -- 装备/升阶按钮行
            local actionRow = UI.Panel {
                flexDirection = "row",
                gap = 6,
                width = "100%",
            }

            if owned and count >= 1 and not isEquipped then
                local equipArtId = artId
                local canEquip = #equipped < maxSlots
                actionRow:AddChild(UI.Button {
                    text = "装备",
                    fontSize = 9,
                    height = 22,
                    paddingHorizontal = 8,
                    backgroundColor = canEquip and Config.Colors.purpleDark or { 50, 55, 65, 200 },
                    textColor = canEquip and { 255, 255, 255, 255 } or { 100, 100, 110, 200 },
                    borderRadius = 4,
                    onClick = function()
                        if not canEquip then
                            UI.Toast.Show("装备栏已满(最多" .. maxSlots .. "个)", { variant = "warning", duration = 2 })
                            return
                        end
                        GameCore.SendGameAction("equip_artifact", { artId = equipArtId })
                    end,
                })
            end

            if owned and count >= 3 then
                local upgradeArtId = artId
                actionRow:AddChild(UI.Button {
                    text = "升阶(3合1)",
                    fontSize = 9,
                    height = 22,
                    paddingHorizontal = 8,
                    backgroundColor = Config.Colors.goldDark,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 4,
                    onClick = function()
                        GameCore.SendGameAction("upgrade_artifact", { artId = upgradeArtId })
                    end,
                })
                actionRow:AddChild(UI.Label {
                    text = count .. "/3 -> " .. (level + 1) .. "阶",
                    fontSize = 8,
                    fontColor = Config.Colors.textGold,
                    alignSelf = "center",
                })
            elseif owned and count > 0 and count < 3 then
                actionRow:AddChild(UI.Label {
                    text = "升阶需" .. (3 - count) .. "个",
                    fontSize = 8,
                    fontColor = Config.Colors.textSecond,
                    alignSelf = "center",
                })
            end

            table.insert(cardChildren, actionRow)
        end

        parent:AddChild(UI.Panel {
            width = "100%",
            padding = 8,
            gap = 3,
            borderRadius = 8,
            backgroundColor = cardBg,
            borderWidth = 1,
            borderColor = cardBorder,
            marginBottom = 4,
            children = cardChildren,
        })
    end
end

-- ========== 总加成面板 ==========

local function renderBonusSummary(parent)
    local equipped = State.state.equippedArtifacts or {}
    if #equipped == 0 then return end

    local bonusTypes = { "material_rate", "sell_price", "craft_speed", "reputation", "lifespan", "all" }
    local typeNames = {
        material_rate = "材料产出", sell_price = "商品售价",
        craft_speed = "制作速度", reputation = "口碑获取",
        lifespan = "寿元减耗", all = "全属性",
    }

    local parts = {}
    for _, bt in ipairs(bonusTypes) do
        local val = Config.GetArtifactBonus(equipped, bt)
        if val > 0 then
            table.insert(parts, typeNames[bt] .. "+" .. string.format("%.0f", val * 100) .. "%")
        end
    end

    if #parts > 0 then
        local summaryChildren = {
            UI.Label {
                text = "法宝总加成: " .. table.concat(parts, "  "),
                fontSize = 9,
                fontColor = Config.Colors.textGreen,
                textAlign = "center",
                width = "100%",
            },
        }
        -- 检查是否有耐久归零的法宝
        local brokenNames = {}
        for _, eq in ipairs(equipped) do
            if (eq.durability or Config.ArtifactDurability.max) <= 0 then
                local art = Config.GetArtifactById(eq.id)
                if art then table.insert(brokenNames, art.name) end
            end
        end
        if #brokenNames > 0 then
            table.insert(summaryChildren, UI.Label {
                text = "损坏: " .. table.concat(brokenNames, ",") .. " (加成失效,请修复)",
                fontSize = 8,
                fontColor = Config.Colors.danger,
                textAlign = "center",
                width = "100%",
            })
        end
        parent:AddChild(UI.Panel {
            width = "100%",
            padding = 6,
            borderRadius = 6,
            backgroundColor = { 40, 50, 45, 200 },
            borderWidth = 1,
            borderColor = Config.Colors.jadeDark,
            marginBottom = 6,
            children = summaryChildren,
        })
    end
end

-- ========== 刷新弹窗内容 ==========

--- 渲染自动修复开关区域
local function renderAutoRepairToggle(parent)
    local s = State.state
    local isOn = s.autoRepairArtifacts or false

    -- 计算当前装备法宝的修复费用预估
    local costHint = ""
    if s.equippedArtifacts and #s.equippedArtifacts > 0 then
        local totalCost = 0
        for _, eq in ipairs(s.equippedArtifacts) do
            totalCost = totalCost + Config.GetArtifactAutoRepairCost(eq.id, eq.level or 1)
        end
        costHint = "  (每次约" .. HUD.FormatNumber(totalCost) .. "灵石)"
    end

    parent:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        paddingHorizontal = 4,
        paddingVertical = 2,
        backgroundColor = { 40, 50, 70, 180 },
        borderRadius = 6,
        children = {
            UI.Toggle {
                label = "自动修复",
                value = isOn,
                onChange = function(self, val)
                    GameCore.SendGameAction("toggle_auto_repair", {})
                end,
            },
            UI.Label {
                text = "耐久<50时消耗灵石修复" .. costHint,
                fontSize = 8,
                fontColor = Config.Colors.textSecond,
                flexShrink = 1,
            },
        },
    })
end

local function refreshContent()
    if not contentPanel_ then return end
    contentPanel_:ClearChildren()
    renderAutoRepairToggle(contentPanel_)
    renderEquipSlots(contentPanel_)
    renderBonusSummary(contentPanel_)
    renderArtifactList(contentPanel_)
end

-- ========== 打开弹窗 ==========

function M.Open()
    if modal_ then
        refreshContent()
        return
    end

    modal_ = UI.Modal {
        title = "法宝",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self)
            contentPanel_ = nil
            modal_ = nil
            State.Off("artifact_changed", refreshContent)
            State.Off("server_sync", refreshContent)
            State.Off("auto_repair_toggled", refreshContent)
            self:Destroy()
        end,
    }

    contentPanel_ = UI.Panel {
        width = "100%",
        padding = 8,
        gap = 4,
    }

    modal_:AddContent(UI.ScrollView {
        width = "100%",
        height = 320,
        scrollY = true,
        showScrollbar = false,
        children = { contentPanel_ },
    })

    refreshContent()

    -- 监听法宝变更和同步
    State.On("artifact_changed", refreshContent)
    State.On("server_sync", refreshContent)
    State.On("auto_repair_toggled", refreshContent)

    modal_:Open()
end

function M.Close()
    if modal_ then
        modal_:Close()
    end
end

return M
