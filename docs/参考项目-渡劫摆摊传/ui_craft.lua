-- ============================================================================
-- ui_craft.lua — 商品制作页面 (无滚动紧凑布局)
-- 优化: 结构/值分离 — 仅境界变化时重建控件, 数值变化时就地更新文本/样式
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local Guide = require("ui_guide")
local Images = Config.Images

local M = {}

local craftPanel = nil
local guideCraftRegistered_ = false  -- 本次 Refresh 是否已注册引导按钮
local puppetDirty = true

State.On("puppet_changed", function() puppetDirty = true end)
State.On("puppet_expired", function() puppetDirty = true end)
State.On("lingshi_changed", function() puppetDirty = true end)

--- 获取制作加速倍率(法宝+珍藏)
local function getCraftSpeedMul()
    local s = State.state
    return 1.0 + Config.GetArtifactBonus(s.equippedArtifacts or {}, "craft_speed")
        + Config.GetCollectibleBonus(s.collectibles or {}, "craft_speed")
end

-- ========== 脏检查签名 ==========
local lastMatSig_ = ""
local lastProdSig_ = ""
local lastSynthSig_ = ""
local lastQueueSig_ = ""

-- 结构签名: 仅境界/解锁状态变化时才需完整重建
local lastMatStructKey_ = ""
local lastProdStructKey_ = ""
local lastSynthStructKey_ = ""

-- 控件引用缓存: 数值变化时就地更新, 避免 ClearChildren 重建导致闪屏
local matStockLabels_ = {}   -- {[matId] = label}
local prodRowRefs_ = {}      -- {[prodId] = {stockLabel, matLabel, btn1, btn5, row}}
local synthRowRefs_ = {}     -- {[recipeId] = {inputLabel, btn1, btn5, row}}

local function getMatSignature()
    local parts = { tostring(State.GetRealmIndex()) }
    for _, mat in ipairs(Config.Materials) do
        parts[#parts + 1] = tostring(math.floor(State.state.materials[mat.id] or 0))
    end
    return table.concat(parts, ",")
end

local function getProdSignature()
    local parts = { tostring(State.GetRealmIndex()) }
    for _, prod in ipairs(Config.Products) do
        parts[#parts + 1] = tostring(math.floor(State.state.materials[prod.materialId] or 0))
            .. ":" .. tostring(math.floor(State.state.products[prod.id] or 0))
    end
    return table.concat(parts, ",")
end

local function getSynthSignature()
    local parts = { tostring(State.GetRealmIndex()) }
    for _, recipe in ipairs(Config.SynthesisRecipes) do
        for _, inp in ipairs(recipe.inputs) do
            parts[#parts + 1] = tostring(math.floor(State.state.materials[inp.id] or 0))
        end
    end
    return table.concat(parts, ",")
end

local function getQueueSignature()
    local parts = {}
    for _, task in ipairs(GameCore.craftQueue) do
        parts[#parts + 1] = task.productId .. ":" .. math.floor(task.remainTime)
    end
    return table.concat(parts, ",")
end

-- ========== 格式化时长 ==========
local function formatDuration(sec)
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return h .. "h" .. m .. "m" end
    if m > 0 then return m .. "m" end
    return sec .. "s"
end

-- ========== 傀儡管理弹窗 ==========
local function showPuppetModal()
    local pp = State.state.craftPuppet
    local isActive = pp and pp.active and os.time() < (pp.expireTime or 0)
    local remain = isActive and (pp.expireTime - os.time()) or 0
    local cfg = Config.CraftPuppet

    local modal = UI.Modal {
        title = "炼器傀儡",
        size = "fullscreen",
        onClose = function(self) self:Destroy() end,
    }

    local children = {}

    -- 当前状态
    if isActive then
        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            padding = 6, backgroundColor = { 45, 40, 35, 200 },
            borderRadius = 6, borderWidth = 1, borderColor = cfg.color,
            children = {
                UI.Panel {
                    backgroundImage = cfg.image, backgroundFit = "contain",
                    width = 36, height = 36, borderRadius = 4,
                },
                UI.Panel {
                    flexGrow = 1, gap = 2,
                    children = {
                        UI.Label {
                            text = cfg.name .. (pp.paused and " (已暂停)" or " (工作中)"),
                            fontSize = 11, fontColor = pp.paused and Config.Colors.textSecond or cfg.color, fontWeight = "bold",
                        },
                        UI.Label { text = cfg.desc, fontSize = 8, fontColor = Config.Colors.textSecond },
                        UI.Label { text = "剩余: " .. formatDuration(remain), fontSize = 9, fontColor = Config.Colors.textGold },
                    },
                },
            },
        })

        -- 自动制作商品选择
        table.insert(children, UI.Label { text = "自动制作商品:", fontSize = 9, fontColor = Config.Colors.textPrimary, marginTop = 4 })
        local currentProducts = pp.products or {}
        local prodSet = {}
        for _, pid in ipairs(currentProducts) do prodSet[pid] = true end

        for _, prod in ipairs(Config.Products) do
            local realmOk = State.state.realmLevel >= prod.unlockRealm
            if realmOk then
                local selected = prodSet[prod.id] == true
                local rowPanel, toggleBtn

                local function updateRowStyle(sel)
                    if rowPanel then
                        rowPanel:SetStyle({
                            backgroundColor = sel and { 40, 55, 40, 200 } or Config.Colors.panelLight,
                            borderColor = sel and Config.Colors.jade or Config.Colors.border,
                        })
                    end
                    if toggleBtn then
                        toggleBtn:SetText(sel and "已选" or "选择")
                        toggleBtn:SetStyle({
                            backgroundColor = sel and Config.Colors.jadeDark or Config.Colors.panelLight,
                            textColor = sel and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                        })
                    end
                end

                toggleBtn = UI.Button {
                    text = selected and "已选" or "选择",
                    fontSize = 8, height = 20, paddingHorizontal = 6,
                    backgroundColor = selected and Config.Colors.jadeDark or Config.Colors.panelLight,
                    textColor = selected and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 3,
                    onClick = function(self)
                        local nowSelected = prodSet[prod.id] == true
                        if nowSelected then
                            for i, pid in ipairs(currentProducts) do
                                if pid == prod.id then table.remove(currentProducts, i); break end
                            end
                            prodSet[prod.id] = nil
                        else
                            table.insert(currentProducts, prod.id)
                            prodSet[prod.id] = true
                        end
                        if State.serverMode then
                            GameCore.SendGameAction("set_puppet_products", { products = currentProducts })
                        else
                            State.state.craftPuppet.products = currentProducts
                            State.Emit("puppet_changed")
                        end
                        updateRowStyle(not nowSelected)
                    end,
                }

                rowPanel = UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    paddingHorizontal = 4, paddingVertical = 2,
                    backgroundColor = selected and { 40, 55, 40, 200 } or Config.Colors.panelLight,
                    borderRadius = 4, borderWidth = 1,
                    borderColor = selected and Config.Colors.jade or Config.Colors.border,
                    children = {
                        (function()
                            local imgSrc = (prod.image and Images[prod.image]) or (prod.icon and prod.icon:find("/") and prod.icon)
                            return imgSrc
                                and UI.Panel { backgroundImage = imgSrc, backgroundFit = "contain", width = 16, height = 16 }
                                or  UI.Label { text = prod.icon or "?", fontSize = 10, fontColor = prod.color }
                        end)(),
                        UI.Label { text = prod.name, fontSize = 9, fontColor = Config.Colors.textPrimary, flexGrow = 1 },
                        UI.Label { text = prod.price .. "石", fontSize = 8, fontColor = Config.Colors.textGold },
                        toggleBtn,
                    },
                }
                table.insert(children, rowPanel)
            end
        end
        -- 制作模式切换
        local curMode = pp.craftMode or "priority"
        local modeLabel = curMode == "roundrobin" and "轮询均衡" or "优先排满"
        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            marginTop = 6, paddingHorizontal = 4, paddingVertical = 3,
            backgroundColor = Config.Colors.panelLight, borderRadius = 4,
            children = {
                UI.Label { text = "排队模式:", fontSize = 9, fontColor = Config.Colors.textSecond },
                (function()
                    local modeBtn, modeDesc
                    modeBtn = UI.Button {
                        text = modeLabel,
                        fontSize = 9, height = 22, paddingHorizontal = 8,
                        backgroundColor = curMode == "roundrobin" and Config.Colors.blue or Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 3,
                        onClick = function(self)
                            local newMode = curMode == "roundrobin" and "priority" or "roundrobin"
                            if State.serverMode then
                                GameCore.SendGameAction("set_puppet_mode", { mode = newMode })
                            else
                                State.state.craftPuppet.craftMode = newMode
                                State.Emit("puppet_changed")
                            end
                            curMode = newMode
                            puppetDirty = true
                            local modeText = newMode == "roundrobin" and "轮询均衡" or "优先排满"
                            modeBtn:SetText(modeText)
                            modeBtn:SetStyle({
                                backgroundColor = newMode == "roundrobin" and Config.Colors.blue or Config.Colors.jadeDark,
                            })
                            modeDesc:SetText(newMode == "roundrobin" and "多商品交替排列" or "排满第一个再排下一个")
                            UI.Toast.Show("排队模式: " .. modeText, { variant = "info", duration = 2 })
                        end,
                    }
                    modeDesc = UI.Label {
                        text = curMode == "roundrobin" and "多商品交替排列" or "排满第一个再排下一个",
                        fontSize = 7, fontColor = Config.Colors.textSecond, flexShrink = 1,
                    }
                    return modeBtn, modeDesc
                end)(),
            },
        })
        -- 暂停/恢复按钮
        table.insert(children, UI.Button {
            text = pp.paused and "恢复工作" or "暂停工作",
            fontSize = 10, height = 28, width = "100%", marginTop = 6,
            backgroundColor = pp.paused and Config.Colors.jadeDark or { 120, 80, 40, 200 },
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                if State.serverMode then
                    GameCore.SendGameAction("toggle_puppet_pause", {})
                else
                    State.state.craftPuppet.paused = not State.state.craftPuppet.paused
                    State.Emit("puppet_changed")
                end
                modal:Close()
                puppetDirty = true
                local msg = State.state.craftPuppet.paused and "傀儡已暂停工作" or "傀儡已恢复工作"
                UI.Toast.Show(msg, { variant = "info", duration = 2 })
            end,
        })
    else
        -- 未雇佣状态
        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            padding = 6, backgroundColor = Config.Colors.panelLight,
            borderRadius = 6,
            children = {
                UI.Panel {
                    backgroundImage = cfg.image, backgroundFit = "contain",
                    width = 36, height = 36, borderRadius = 4, opacity = 0.6,
                },
                UI.Panel {
                    flexGrow = 1, gap = 2,
                    children = {
                        UI.Label { text = cfg.name, fontSize = 11, fontColor = cfg.color, fontWeight = "bold" },
                        UI.Label { text = cfg.desc, fontSize = 8, fontColor = Config.Colors.textSecond },
                        UI.Label { text = "费用: " .. cfg.cost .. "灵石/24小时", fontSize = 9, fontColor = Config.Colors.textGold },
                        UI.Label { text = "需" .. Config.Realms[cfg.requiredRealm].name .. "期解锁", fontSize = 8, fontColor = Config.Colors.textSecond },
                    },
                },
            },
        })
    end

    -- 雇佣/续雇按钮
    local realmOk = State.state.realmLevel >= cfg.requiredRealm
    local canAfford = State.state.lingshi >= cfg.cost
    local canHire = realmOk and canAfford

    local btnText
    if not realmOk then btnText = "需" .. Config.Realms[cfg.requiredRealm].name .. "期"
    elseif isActive then btnText = "续雇24h (" .. cfg.cost .. "石)"
    else btnText = "雇佣 (" .. cfg.cost .. "石/日)"
    end

    table.insert(children, UI.Button {
        text = btnText,
        fontSize = 10, height = 28, width = "100%", marginTop = 6,
        disabled = not canHire,
        backgroundColor = canHire and Config.Colors.purpleDark or { 60, 60, 70, 200 },
        textColor = canHire and { 255, 255, 255, 255 } or Config.Colors.textSecond,
        borderRadius = 4,
        onClick = function(self)
            if State.serverMode then
                GameCore.SendGameAction("hire_puppet", {})
            else
                if not canAfford then
                    UI.Toast.Show("灵石不足", { variant = "warning", duration = 2 })
                    return
                end
                State.state.lingshi = State.state.lingshi - cfg.cost
                State.state.craftPuppet.active = true
                State.state.craftPuppet.expireTime = os.time() + 86400
                State.Emit("puppet_changed")
                State.Emit("lingshi_changed")
                GameCore.AddLog("雇佣" .. cfg.name .. "! 24h", cfg.color)
            end
            modal:Close()
            UI.Toast.Show("已雇佣" .. cfg.name .. " (24小时)", { variant = "success", duration = 2 })
        end,
    })

    modal:AddContent(UI.Panel { gap = 4, padding = 4, overflow = "scroll", flexShrink = 1, children = children })
    modal:Open()
end

--- 创建材料芯片 (返回 panel 和 stockLabel 引用，用于就地更新)
---@param mat table
---@return table panel, table stockLabel
local function createMaterialChip(mat)
    local stock = State.state.materials[mat.id] or 0
    local stockLabel = UI.Label {
        text = tostring(math.floor(stock)),
        fontSize = 9,
        fontColor = Config.Colors.textGreen,
    }
    local chip = UI.Panel {
        flexGrow = 1,
        flexBasis = "30%",
        minWidth = 70,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 4,
        alignItems = "center",
        justifyContent = "center",
        paddingVertical = 2,
        gap = 0,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                children = {
                    (mat.image and Images[mat.image])
                        and UI.Panel { backgroundImage = Images[mat.image], backgroundFit = "contain", width = 14, height = 14 }
                        or  UI.Label { text = mat.icon, fontSize = 10, fontColor = mat.color },
                    UI.Label { text = mat.name, fontSize = 9, fontColor = Config.Colors.textPrimary },
                },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                children = {
                    stockLabel,
                    UI.Label {
                        text = mat.rate > 0 and ("+" .. mat.rate .. "/m") or "合成",
                        fontSize = 7,
                        fontColor = mat.rate > 0 and Config.Colors.textSecond or Config.Colors.purple,
                    },
                },
            },
        },
    }
    return chip, stockLabel
end

--- 统一提取商品材料信息（兼容普通商品 materialId/materialCost 和仙界商品 materials 数组）
---@param prod table
---@return string matId, number matCost, number matStock, string matName, boolean canCraft, boolean canCraft5
local function getProdMatInfo(prod)
    local matId, matCost, matStock, matName
    local canCraft, canCraft5 = true, true
    if prod.materialId then
        -- 普通商品
        matId   = prod.materialId
        matCost = prod.materialCost or 1
        matStock = State.state.materials[matId] or 0
        local cfg = Config.GetMaterialById(matId)
        matName = cfg and cfg.name or matId
        canCraft  = matStock >= matCost
        canCraft5 = matStock >= matCost * 5
    elseif prod.materials then
        -- 仙界商品（多材料数组）
        local firstMat = prod.materials[1] or {}
        matId   = firstMat.id or ""
        matCost = firstMat.count or 1
        matStock = State.state.materials[matId] or 0
        local cfg = Config.GetMaterialById(matId)
        matName = cfg and cfg.name or matId
        -- 检查所有材料是否满足（1x 和 5x）
        for _, m in ipairs(prod.materials) do
            local stock = State.state.materials[m.id] or 0
            local cost  = m.count or 1
            if stock < cost   then canCraft  = false end
            if stock < cost*5 then canCraft5 = false end
        end
        -- 如果有多种材料，matName 显示第一种
        if #prod.materials > 1 then
            local parts = {}
            for _, m in ipairs(prod.materials) do
                local c = Config.GetMaterialById(m.id)
                table.insert(parts, (c and c.name or m.id) .. "x" .. (m.count or 1))
            end
            matName = table.concat(parts, "+")
            matCost = nil  -- 多材料时不显示单一数量
        end
    else
        matId = ""; matCost = 1; matStock = 0; matName = "?"
        canCraft = false; canCraft5 = false
    end
    return matId, matCost, matStock, matName, canCraft, canCraft5
end

--- 创建商品紧凑行 (返回 panel 和 refs 表, 用于就地更新)
---@param prod table
---@param prodIndex number
---@return table panel, table refs
local function createProductRow(prod, prodIndex)
    local realmIdx = State.GetRealmIndex()
    local isUnlocked = realmIdx >= (prod.unlockRealm or 1)
    local matId, matCost, matStock, matName, _canCraft, _canCraft5 = getProdMatInfo(prod)
    local prodStock = State.state.products[prod.id] or 0
    local canCraft  = isUnlocked and _canCraft
    local canCraft5 = isUnlocked and _canCraft5

    local refs = { isUnlocked = isUnlocked }

    local prodStockLabel = UI.Label {
        text = "x" .. math.floor(prodStock),
        fontSize = 8,
        fontColor = Config.Colors.textGreen,
    }
    refs.stockLabel = prodStockLabel

    local rightChildren = {}
    if isUnlocked then
        local speedMul = getCraftSpeedMul()
        local displayTime = math.ceil(prod.craftTime / speedMul)
        local timeStr = displayTime .. "s"
        if speedMul > 1.001 then
            timeStr = timeStr .. "(加速)"
        end
        local matLabel = UI.Label {
            text = matName .. (matCost and ("x" .. matCost) or "") .. " " .. timeStr,
            fontSize = 7,
            fontColor = canCraft and Config.Colors.textGreen or Config.Colors.red,
        }
        refs.matLabel = matLabel
        table.insert(rightChildren, matLabel)

        local craftBtn = UI.Button {
            text = "x1",
            fontSize = 8,
            width = 24,
            height = 18,
            disabled = not canCraft,
            backgroundColor = canCraft and Config.Colors.jadeDark or { 60, 60, 70, 200 },
            textColor = canCraft and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 3,
            onClick = function(self)
                local ok, reason = GameCore.StartCraft(prod.id)
                if not ok then
                    UI.Toast.Show(reason or "制作失败", { variant = "warning", duration = 2 })
                end
                Guide.NotifyAction("craft_btn")
            end,
        }
        refs.btn1 = craftBtn
        if not guideCraftRegistered_ then
            guideCraftRegistered_ = true
            Guide.RegisterTarget("craft_btn", craftBtn)
        end
        table.insert(rightChildren, craftBtn)

        local craftBtn5 = UI.Button {
            text = "x5",
            fontSize = 8,
            width = 24,
            height = 18,
            disabled = not canCraft5,
            backgroundColor = canCraft5 and Config.Colors.purpleDark or { 60, 60, 70, 200 },
            textColor = canCraft5 and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 3,
            onClick = function(self)
                local made, reason = GameCore.BatchCraft(prod.id, 5)
                if made > 0 then
                    UI.Toast.Show("批量制作 " .. prod.name .. " x" .. made, { variant = "success", duration = 2 })
                else
                    UI.Toast.Show(reason or "制作失败", { variant = "warning", duration = 2 })
                end
            end,
        }
        refs.btn5 = craftBtn5
        table.insert(rightChildren, craftBtn5)
    else
        table.insert(rightChildren, UI.Label {
            text = "需" .. Config.Realms[prod.unlockRealm].name,
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
        })
    end

    local rowPanel = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 3,
        height = 24,
        paddingHorizontal = 4,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 4,
        borderWidth = 1,
        borderColor = canCraft and Config.Colors.jade or Config.Colors.border,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                flexGrow = 1,
                flexShrink = 1,
                children = {
                    (function()
                        local imgSrc = (prod.image and Images[prod.image]) or (prod.icon and prod.icon:find("/") and prod.icon)
                        return imgSrc
                            and UI.Panel { backgroundImage = imgSrc, backgroundFit = "contain", width = 16, height = 16 }
                            or  UI.Label { text = prod.icon or "?", fontSize = 10, fontColor = prod.color }
                    end)(),
                    UI.Label {
                        text = prod.name,
                        fontSize = 9,
                        fontColor = isUnlocked and Config.Colors.textPrimary or Config.Colors.textSecond,
                    },
                    prodStockLabel,
                },
            },
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 2,
                children = rightChildren,
            },
        },
    }
    refs.row = rowPanel
    return rowPanel, refs
end

--- 就地更新商品行数值 (不重建控件)
---@param prod table
---@param refs table
local function updateProductRow(prod, refs)
    if not refs or not refs.isUnlocked then return end
    local matId, matCost, matStock, matName, canCraft, canCraft5 = getProdMatInfo(prod)
    local prodStock = State.state.products[prod.id] or 0

    refs.stockLabel:SetText("x" .. math.floor(prodStock))
    refs.matLabel:SetStyle({
        fontColor = canCraft and Config.Colors.textGreen or Config.Colors.red,
    })
    refs.btn1:SetStyle({
        backgroundColor = canCraft and Config.Colors.jadeDark or { 60, 60, 70, 200 },
        textColor = canCraft and { 255, 255, 255, 255 } or Config.Colors.textSecond,
    })
    refs.btn1.props.disabled = not canCraft
    refs.btn5:SetStyle({
        backgroundColor = canCraft5 and Config.Colors.purpleDark or { 60, 60, 70, 200 },
        textColor = canCraft5 and { 255, 255, 255, 255 } or Config.Colors.textSecond,
    })
    refs.btn5.props.disabled = not canCraft5
    refs.row:SetStyle({
        borderColor = canCraft and Config.Colors.jade or Config.Colors.border,
    })
end

--- 创建合成行 (返回 panel 和 refs 表, 用于就地更新)
---@param recipe table
---@return table panel, table refs
local function createSynthRow(recipe)
    local realmIdx = State.GetRealmIndex()
    local unlocked = realmIdx >= recipe.unlockRealm

    -- 计算可合成数量
    local maxCount = 99
    for _, inp in ipairs(recipe.inputs) do
        local have = State.state.materials[inp.id] or 0
        maxCount = math.min(maxCount, math.floor(have / inp.amount))
    end
    local canSynth = unlocked and maxCount > 0

    -- 输入材料描述
    local inputParts = {}
    for _, inp in ipairs(recipe.inputs) do
        local mat = Config.GetMaterialById(inp.id)
        local matName = mat and mat.name or nil
        if not matName then
            local synthRecipe = Config.GetSynthesisRecipeById(inp.id)
            matName = synthRecipe and synthRecipe.name or inp.id
        end
        local have = State.state.materials[inp.id] or 0
        table.insert(inputParts, matName .. "x" .. inp.amount
            .. "(" .. math.floor(have) .. ")")
    end
    local outMat = Config.GetMaterialById(recipe.output.id)
    local outName = outMat and outMat.name or recipe.name

    local refs = { unlocked = unlocked }

    local titleLabel = UI.Label {
        text = recipe.name .. " -> " .. outName .. "x" .. recipe.output.amount,
        fontSize = 9,
        fontColor = unlocked and Config.Colors.textPrimary or Config.Colors.textSecond,
    }

    local inputLabel = UI.Label {
        text = table.concat(inputParts, " + "),
        fontSize = 7,
        fontColor = canSynth and Config.Colors.textGreen or Config.Colors.textSecond,
    }
    refs.inputLabel = inputLabel

    local rowChildren = {
        UI.Panel {
            flexGrow = 1, flexShrink = 1,
            children = { titleLabel, inputLabel },
        },
    }

    if unlocked then
        local btn1 = UI.Button {
            text = canSynth and "x1" or "不足",
            fontSize = 8, width = 28, height = 18,
            disabled = not canSynth,
            backgroundColor = canSynth and Config.Colors.jadeDark or { 60, 60, 70, 200 },
            textColor = canSynth and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 3,
            onClick = function()
                local curMax = 99
                for _, inp in ipairs(recipe.inputs) do
                    local h = State.state.materials[inp.id] or 0
                    curMax = math.min(curMax, math.floor(h / inp.amount))
                end
                if curMax <= 0 then
                    UI.Toast.Show("材料不足", { variant = "warning", duration = 2 })
                    return
                end
                GameCore.Synthesize(recipe.id, 1)
                UI.Toast.Show("合成 " .. recipe.name .. " x1", { variant = "info", duration = 1.5 })
            end,
        }
        refs.btn1 = btn1
        table.insert(rowChildren, btn1)

        -- x5 按钮始终创建(避免结构变化), 不可用时隐藏样式
        local btn5 = UI.Button {
            text = "x5",
            fontSize = 8, width = 28, height = 18,
            disabled = maxCount < 5,
            backgroundColor = maxCount >= 5 and Config.Colors.purpleDark or { 60, 60, 70, 200 },
            textColor = maxCount >= 5 and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            borderRadius = 3,
            onClick = function()
                local curMax = 99
                for _, inp in ipairs(recipe.inputs) do
                    local h = State.state.materials[inp.id] or 0
                    curMax = math.min(curMax, math.floor(h / inp.amount))
                end
                if curMax < 5 then
                    UI.Toast.Show("材料不足", { variant = "warning", duration = 2 })
                    return
                end
                GameCore.Synthesize(recipe.id, 5)
                UI.Toast.Show("合成 " .. recipe.name .. " x5", { variant = "info", duration = 1.5 })
            end,
        }
        refs.btn5 = btn5
        table.insert(rowChildren, btn5)
    else
        table.insert(rowChildren, UI.Label {
            text = "需" .. Config.Realms[recipe.unlockRealm].name,
            fontSize = 8, fontColor = Config.Colors.textSecond,
        })
    end

    local rowPanel = UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 3,
        height = 24,
        paddingHorizontal = 4,
        backgroundColor = Config.Colors.panelLight,
        borderRadius = 4,
        borderWidth = 1,
        borderColor = canSynth and Config.Colors.jade or Config.Colors.border,
        children = rowChildren,
    }
    refs.row = rowPanel
    return rowPanel, refs
end

--- 就地更新合成行数值
---@param recipe table
---@param refs table
local function updateSynthRow(recipe, refs)
    if not refs or not refs.unlocked then return end

    local maxCount = 99
    for _, inp in ipairs(recipe.inputs) do
        local have = State.state.materials[inp.id] or 0
        maxCount = math.min(maxCount, math.floor(have / inp.amount))
    end
    local canSynth = maxCount > 0

    -- 更新输入材料文本
    local inputParts = {}
    for _, inp in ipairs(recipe.inputs) do
        local mat = Config.GetMaterialById(inp.id)
        local matName = mat and mat.name or nil
        if not matName then
            local sr = Config.GetSynthesisRecipeById(inp.id)
            matName = sr and sr.name or inp.id
        end
        local have = State.state.materials[inp.id] or 0
        table.insert(inputParts, matName .. "x" .. inp.amount
            .. "(" .. math.floor(have) .. ")")
    end
    refs.inputLabel:SetText(table.concat(inputParts, " + "))
    refs.inputLabel:SetStyle({
        fontColor = canSynth and Config.Colors.textGreen or Config.Colors.textSecond,
    })

    refs.btn1:SetText(canSynth and "x1" or "不足")
    refs.btn1:SetStyle({
        backgroundColor = canSynth and Config.Colors.jadeDark or { 60, 60, 70, 200 },
        textColor = canSynth and { 255, 255, 255, 255 } or Config.Colors.textSecond,
    })
    refs.btn1.props.disabled = not canSynth

    refs.btn5:SetStyle({
        backgroundColor = maxCount >= 5 and Config.Colors.purpleDark or { 60, 60, 70, 200 },
        textColor = maxCount >= 5 and { 255, 255, 255, 255 } or Config.Colors.textSecond,
    })
    refs.btn5.props.disabled = maxCount < 5

    refs.row:SetStyle({
        borderColor = canSynth and Config.Colors.jade or Config.Colors.border,
    })
end

--- 创建队列条目 (极紧凑)
---@param task CraftTask
local function createQueueRow(task)
    local prodCfg = Config.GetProductById(task.productId)
    local progress = 1.0 - (task.remainTime / task.totalTime)

    return UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 3,
        height = 20,
        paddingHorizontal = 4,
        backgroundColor = { 50, 55, 75, 220 },
        borderRadius = 3,
        children = {
            UI.Label {
                text = prodCfg and prodCfg.name or "?",
                fontSize = 9,
                fontColor = Config.Colors.textPrimary,
                width = 42,
            },
            UI.ProgressBar {
                value = progress,
                flexGrow = 1,
                flexBasis = 0,
                height = 5,
                variant = "primary",
            },
            UI.Label {
                text = string.format("%.0fs", task.remainTime),
                fontSize = 8,
                fontColor = Config.Colors.textGold,
                width = 26,
                textAlign = "right",
            },
        },
    }
end

-- ========== 重置所有缓存(Create/页面切换时) ==========
local function resetCaches()
    lastMatSig_ = ""
    lastProdSig_ = ""
    lastSynthSig_ = ""
    lastQueueSig_ = ""
    lastMatStructKey_ = ""
    lastProdStructKey_ = ""
    lastSynthStructKey_ = ""
    matStockLabels_ = {}
    prodRowRefs_ = {}
    synthRowRefs_ = {}
    puppetDirty = true
end

function M.Create()
    resetCaches()
    craftPanel = UI.Panel {
        id = "craft_page",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        overflow = "scroll", showScrollbar = false,
        paddingHorizontal = 4,
        paddingVertical = 2,
        gap = 2,
        children = {
            -- 傀儡状态条
            UI.Panel { id = "puppet_bar", width = "100%" },
            -- 材料区 (横向可换行)
            UI.Label { text = "材料仓库", fontSize = 10, fontColor = Config.Colors.textPrimary },
            UI.Panel { id = "material_row", flexDirection = "row", flexWrap = "wrap", gap = 3 },
            -- 商品制作 (固定高度可滚动)
            UI.Label { text = "商品制作", fontSize = 10, fontColor = Config.Colors.textPrimary },
            UI.Panel { id = "craft_product_list", gap = 2, height = 130, overflow = "scroll", showScrollbar = false },
            -- 材料合成
            UI.Panel {
                flexDirection = "row", alignItems = "center", gap = 4,
                children = {
                    UI.Label { id = "synth_title", text = "材料合成", fontSize = 10, fontColor = Config.Colors.textPrimary, flexGrow = 1 },
                    UI.Button {
                        id = "synth_all_btn",
                        text = "一键合成",
                        fontSize = 8, height = 18, paddingHorizontal = 6,
                        backgroundColor = Config.Colors.purpleDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 3,
                        onClick = function()
                            GameCore.SynthesizeAll()
                        end,
                    },
                },
            },
            UI.Panel { id = "synth_list", gap = 2, maxHeight = 120, overflow = "scroll", showScrollbar = false },
            -- 制作队列
            UI.Label { id = "craft_queue_title", text = "制作中 (0)", fontSize = 10, fontColor = Config.Colors.textPrimary },
            UI.Panel {
                id = "craft_queue_list",
                gap = 2,
            },
        },
    }
    return craftPanel
end

local lastPuppetRefresh_ = 0

function M.Refresh()
    if not craftPanel then return end
    -- 傀儡状态条每30秒自动刷新
    local now = os.time()
    if now - lastPuppetRefresh_ >= 30 then
        lastPuppetRefresh_ = now
        local pp = State.state.craftPuppet
        if pp and pp.active then puppetDirty = true end
    end

    -- === 傀儡状态条 ===
    if puppetDirty then
        puppetDirty = false
        local pbar = craftPanel:FindById("puppet_bar")
        if pbar then
            pbar:ClearChildren()
            local pp = State.state.craftPuppet
            local isActive = pp and pp.active and os.time() < (pp.expireTime or 0)
            local cfg = Config.CraftPuppet
            if isActive then
                local remain = pp.expireTime - os.time()
                local prodNames = {}
                for _, pid in ipairs(pp.products or {}) do
                    local p = Config.GetProductById(pid)
                    if p then table.insert(prodNames, p.name) end
                end
                local prodText = #prodNames > 0 and table.concat(prodNames, "/") or "未配置"
                pbar:AddChild(UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    paddingHorizontal = 4, paddingVertical = 2,
                    backgroundColor = { 45, 40, 35, 200 },
                    borderRadius = 4, borderWidth = 1, borderColor = cfg.color,
                    children = {
                        UI.Panel {
                            backgroundImage = cfg.image, backgroundFit = "contain",
                            width = 18, height = 18, borderRadius = 3,
                        },
                        UI.Label {
                            text = cfg.name .. (pp.paused and "(停)" or ""),
                            fontSize = 9, fontColor = pp.paused and Config.Colors.textSecond or cfg.color, fontWeight = "bold",
                        },
                        UI.Label { text = prodText, fontSize = 7, fontColor = Config.Colors.textSecond, flexShrink = 1 },
                        UI.Label { text = formatDuration(remain), fontSize = 8, fontColor = Config.Colors.textGold },
                        UI.Panel { flexGrow = 1 },
                        UI.Button {
                            text = pp.paused and "恢复" or "暂停",
                            fontSize = 8, height = 18, paddingHorizontal = 6,
                            backgroundColor = pp.paused and Config.Colors.jadeDark or { 120, 80, 40, 200 },
                            textColor = { 255, 255, 255, 255 },
                            borderRadius = 3,
                            onClick = function(self)
                                if State.serverMode then
                                    GameCore.SendGameAction("toggle_puppet_pause", {})
                                else
                                    State.state.craftPuppet.paused = not State.state.craftPuppet.paused
                                    State.Emit("puppet_changed")
                                end
                                puppetDirty = true
                            end,
                        },
                        UI.Button {
                            text = "管理",
                            fontSize = 8, height = 18, paddingHorizontal = 6,
                            backgroundColor = Config.Colors.panelLight,
                            textColor = Config.Colors.textPrimary,
                            borderRadius = 3,
                            onClick = function(self) showPuppetModal() end,
                        },
                    },
                })
            else
                pbar:AddChild(UI.Button {
                    text = "雇佣炼器傀儡 (自动制作商品)",
                    fontSize = 9, height = 22, width = "100%",
                    backgroundColor = { 50, 45, 40, 180 },
                    textColor = Config.Colors.textSecond,
                    borderRadius = 4, borderWidth = 1,
                    borderColor = { 100, 80, 60, 150 },
                    onClick = function(self) showPuppetModal() end,
                })
            end
        end
    end

    -- === 材料区 ===（结构/值分离: 境界变化重建, 数值变化就地更新）
    -- 结构签名包含境界+哪些材料有库存(购买新材料后需重建显示)
    local matStructParts = { tostring(State.GetRealmIndex()) }
    for _, mat in ipairs(Config.Materials) do
        if (State.state.materials[mat.id] or 0) > 0 then
            matStructParts[#matStructParts + 1] = mat.id
        end
    end
    local matStructKey = table.concat(matStructParts, ",")
    local matSig = getMatSignature()

    if matStructKey ~= lastMatStructKey_ then
        -- 结构变化: 完整重建 + 缓存引用
        lastMatStructKey_ = matStructKey
        lastMatSig_ = matSig
        matStockLabels_ = {}
        local matRow = craftPanel:FindById("material_row")
        if matRow then
            matRow:ClearChildren()
            local realmIdx = State.GetRealmIndex()
            for _, mat in ipairs(Config.Materials) do
                local show = mat.rate > 0
                if not show then
                    local recipe = Config.GetSynthesisRecipeById(mat.id)
                    local unlockRealm = recipe and recipe.unlockRealm or 3
                    show = realmIdx >= unlockRealm
                end
                -- 已拥有库存的材料也显示(如从聚宝阁购买)
                if not show then
                    show = (State.state.materials[mat.id] or 0) > 0
                end
                if show then
                    local chip, stockLabel = createMaterialChip(mat)
                    matRow:AddChild(chip)
                    matStockLabels_[mat.id] = stockLabel
                end
            end
        end
    elseif matSig ~= lastMatSig_ then
        -- 值变化: 就地更新库存文本, 不重建控件
        lastMatSig_ = matSig
        for matId, label in pairs(matStockLabels_) do
            local stock = State.state.materials[matId] or 0
            label:SetText(tostring(math.floor(stock)))
        end
    end

    -- === 商品列表 ===（结构/值分离）
    local prodStructKey = tostring(State.GetRealmIndex())
    local prodSig = getProdSignature()

    if prodStructKey ~= lastProdStructKey_ then
        -- 结构变化: 完整重建 + 缓存引用
        lastProdStructKey_ = prodStructKey
        lastProdSig_ = prodSig
        prodRowRefs_ = {}
        guideCraftRegistered_ = false
        local prodList = craftPanel:FindById("craft_product_list")
        if prodList then
            prodList:ClearChildren()
            for i, prod in ipairs(Config.Products) do
                local row, refs = createProductRow(prod, i)
                prodList:AddChild(row)
                prodRowRefs_[prod.id] = refs
            end
        end
    elseif prodSig ~= lastProdSig_ then
        -- 值变化: 就地更新文本/样式
        lastProdSig_ = prodSig
        for _, prod in ipairs(Config.Products) do
            local refs = prodRowRefs_[prod.id]
            updateProductRow(prod, refs)
        end
    end

    -- === 合成区域 ===（结构/值分离）
    local synthStructKey = tostring(State.GetRealmIndex())
    local synthSig = getSynthSignature()

    if synthStructKey ~= lastSynthStructKey_ then
        -- 结构变化: 完整重建 + 缓存引用
        lastSynthStructKey_ = synthStructKey
        lastSynthSig_ = synthSig
        synthRowRefs_ = {}
        local synthList = craftPanel:FindById("synth_list")
        if synthList then
            synthList:ClearChildren()
            for _, recipe in ipairs(Config.SynthesisRecipes) do
                local row, refs = createSynthRow(recipe)
                synthList:AddChild(row)
                synthRowRefs_[recipe.id] = refs
            end
        end
    elseif synthSig ~= lastSynthSig_ then
        -- 值变化: 就地更新文本/样式
        lastSynthSig_ = synthSig
        for _, recipe in ipairs(Config.SynthesisRecipes) do
            local refs = synthRowRefs_[recipe.id]
            updateSynthRow(recipe, refs)
        end
    end

    -- === 制作队列 ===（签名脏检查，仅秒级变化时重建）
    local queueSig = getQueueSignature()
    if queueSig ~= lastQueueSig_ then
        lastQueueSig_ = queueSig
        local queueTitle = craftPanel:FindById("craft_queue_title")
        if queueTitle then
            queueTitle:SetText("制作中 (" .. #GameCore.craftQueue .. ")")
        end
        local queueList = craftPanel:FindById("craft_queue_list")
        if queueList then
            queueList:ClearChildren()
            if #GameCore.craftQueue == 0 then
                queueList:AddChild(UI.Label {
                    text = "暂无制作任务",
                    fontSize = 9,
                    fontColor = Config.Colors.textSecond,
                    textAlign = "center",
                    paddingVertical = 4,
                })
            else
                for _, task in ipairs(GameCore.craftQueue) do
                    queueList:AddChild(createQueueRow(task))
                end
            end
        end
    end
end

return M
