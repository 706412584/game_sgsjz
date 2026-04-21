-- ============================================================================
-- ui_field.lua — 灵田页面 UI
-- 田地等级/升级 + 地块网格 + 种植选择 + 一键收获
-- 使用脏标记 + FindById 原地更新, 避免每帧重建导致闪烁
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local Field = require("game_field")
local HUD = require("ui_hud")
local GameCore = require("game_core")
local Guide = require("ui_guide")

local M = {}

-- 灵田状态背景图
local FieldImages = {
    empty    = "image/field_empty_20260409081102.png",
    seeded   = "image/field_seeded_20260409081042.png",
    growing  = "image/field_growing_20260409081044.png",
    mature   = "image/field_mature_20260409081041.png",
    withered = "image/field_withered_20260409081105.png",
    locked   = "image/field_empty_20260409081102.png",  -- 锁定地块复用空地图
}

local fieldPanel = nil
local gridDirty = true  -- 需要完整重建网格
local headerDirty = true -- 需要重建 header
local infoDirty = true   -- 需要重建 info (只建一次)
local servantDirty = true -- 灵童状态条需要重建
local guidePlantRegistered_ = false  -- 是否已注册引导种植按钮

-- 记录每个地块的状态签名, 用于检测结构变化
-- 签名: "empty" | "locked" | "growing_<cropId>" | "harvestable_<cropId>"
local plotSignatures = {}

-- ========== 标记脏 ==========
function M.MarkDirty()
    gridDirty = true
    headerDirty = true
    servantDirty = true
end

-- 监听结构性变化事件
State.On("field_changed", function()
    gridDirty = true
    headerDirty = true
end)
State.On("field_upgraded", function()
    gridDirty = true
    headerDirty = true
    infoDirty = true
end)
State.On("lingshi_changed", function()
    headerDirty = true
    servantDirty = true
end)
State.On("servant_changed", function() servantDirty = true; gridDirty = true end)
State.On("servant_expired", function() servantDirty = true end)

-- ========== 格式化时间 ==========
local function formatTime(sec)
    sec = math.floor(sec)
    if sec >= 60 then
        return math.floor(sec / 60) .. "m" .. (sec % 60) .. "s"
    end
    return sec .. "s"
end

local function formatDuration(sec)
    sec = math.max(0, math.floor(sec))
    local h = math.floor(sec / 3600)
    local m = math.floor((sec % 3600) / 60)
    if h > 0 then return h .. "h" .. m .. "m" end
    if m > 0 then return m .. "m" end
    return sec .. "s"
end

-- ========== 灵童管理弹窗 ==========
local function showServantModal()
    local sv = State.state.fieldServant
    local currentTier = sv and sv.tier or 0
    local expireTime = sv and sv.expireTime or 0
    local isActive = currentTier > 0 and os.time() < expireTime
    local remain = isActive and (expireTime - os.time()) or 0

    local modal = UI.Modal {
        title = "灵童管理",
        size = "sm",
        onClose = function(self) self:Destroy() end,
    }

    local children = {}

    -- 当前状态
    if isActive then
        local cfg = Config.FieldServants[currentTier]
        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6,
            padding = 6, backgroundColor = { 40, 50, 35, 200 },
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
                            text = cfg.name .. (sv.paused and " (已暂停)" or " (工作中)"),
                            fontSize = 11, fontColor = sv.paused and Config.Colors.textSecond or cfg.color, fontWeight = "bold",
                        },
                        UI.Label { text = cfg.desc, fontSize = 8, fontColor = Config.Colors.textSecond },
                        UI.Label { text = "剩余: " .. formatDuration(remain), fontSize = 9, fontColor = Config.Colors.textGold },
                    },
                },
            },
        })
        -- 当前种植作物选择(tier>=2)
        if cfg.abilities.plant then
            local cropId = sv.plantCrop or "lingcao_seed"
            local hasPlotCrops = sv.plotCrops and next(sv.plotCrops) ~= nil
            table.insert(children, UI.Label {
                text = hasPlotCrops and "全局作物 (设置后清除分田配置):" or "自动种植作物:",
                fontSize = 9, fontColor = Config.Colors.textPrimary, marginTop = 4,
            })
            local cropBtns = {}
            for _, crop in ipairs(Config.Crops) do
                local selected = (crop.id == cropId) and not hasPlotCrops
                table.insert(cropBtns, UI.Button {
                    text = crop.icon .. crop.name,
                    fontSize = 9, height = 24, flexGrow = 1, flexBasis = 0,
                    backgroundColor = selected and Config.Colors.jadeDark or Config.Colors.panelLight,
                    textColor = selected and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 4,
                    borderWidth = selected and 1 or 0,
                    borderColor = Config.Colors.jade,
                    onClick = function(self)
                        if State.serverMode then
                            GameCore.SendGameAction("set_servant_crop", { cropId = crop.id })
                        else
                            State.state.fieldServant.plantCrop = crop.id
                            State.state.fieldServant.plotCrops = nil
                            State.Emit("servant_changed")
                        end
                        modal:Close()
                        UI.Toast.Show("种植作物已设为: " .. crop.name, { variant = "success", duration = 2 })
                    end,
                })
            end
            table.insert(children, UI.Panel { flexDirection = "row", gap = 4, children = cropBtns })

            -- 分田种植(tier>=3: 金灵童)
            if currentTier >= 3 then
                local maxPlots = Field.GetMaxPlots()
                table.insert(children, UI.Label {
                    text = "分田种植 (每块田独立选择):",
                    fontSize = 9, fontColor = Config.Colors.textGold, marginTop = 6,
                })
                local plotCrops = sv.plotCrops or {}
                local defaultCrop = sv.plantCrop or "lingcao_seed"
                for pi = 1, maxPlots do
                    local plotCropId = plotCrops[tostring(pi)] or defaultCrop
                    local plotCropCfg = nil
                    for _, c in ipairs(Config.Crops) do
                        if c.id == plotCropId then plotCropCfg = c; break end
                    end
                    local plotRow = UI.Panel {
                        flexDirection = "row", alignItems = "center", gap = 3,
                        paddingVertical = 2, width = "100%",
                    }
                    plotRow:AddChild(UI.Label {
                        text = "田#" .. pi,
                        fontSize = 8, fontColor = Config.Colors.textSecond, width = 28,
                    })
                    for _, crop in ipairs(Config.Crops) do
                        local isPlotSelected = (crop.id == plotCropId) and hasPlotCrops
                        local capturedIdx = pi
                        plotRow:AddChild(UI.Button {
                            text = crop.icon,
                            fontSize = 9, width = 28, height = 22,
                            backgroundColor = isPlotSelected and Config.Colors.jadeDark or Config.Colors.panelLight,
                            textColor = isPlotSelected and { 255, 255, 255, 255 } or crop.color,
                            borderRadius = 3,
                            borderWidth = isPlotSelected and 1 or 0,
                            borderColor = Config.Colors.jade,
                            onClick = function(self)
                                if State.serverMode then
                                    GameCore.SendGameAction("set_plot_crop", { plotIdx = capturedIdx, cropId = crop.id })
                                else
                                    if not State.state.fieldServant.plotCrops then
                                        State.state.fieldServant.plotCrops = {}
                                    end
                                    State.state.fieldServant.plotCrops[tostring(capturedIdx)] = crop.id
                                    State.Emit("servant_changed")
                                end
                                modal:Close()
                                UI.Toast.Show("田#" .. capturedIdx .. " 设为: " .. crop.name, { variant = "success", duration = 2 })
                            end,
                        })
                    end
                    -- 当前选中标签
                    if hasPlotCrops and plotCropCfg then
                        plotRow:AddChild(UI.Label {
                            text = plotCropCfg.name,
                            fontSize = 7, fontColor = Config.Colors.textSecond,
                            marginLeft = 2,
                        })
                    end
                    table.insert(children, plotRow)
                end
            end
        end
        -- 暂停/恢复按钮
        table.insert(children, UI.Button {
            text = sv.paused and "恢复工作" or "暂停工作",
            fontSize = 10, height = 28, width = "100%", marginTop = 6,
            backgroundColor = sv.paused and Config.Colors.jadeDark or { 120, 80, 40, 200 },
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                if State.serverMode then
                    GameCore.SendGameAction("toggle_servant_pause", {})
                else
                    State.state.fieldServant.paused = not State.state.fieldServant.paused
                    State.Emit("servant_changed")
                end
                modal:Close()
                servantDirty = true
                local msg = State.state.fieldServant.paused and "灵童已暂停工作" or "灵童已恢复工作"
                UI.Toast.Show(msg, { variant = "info", duration = 2 })
            end,
        })
    else
        table.insert(children, UI.Label {
            text = "雇佣灵童可自动操作灵田",
            fontSize = 10, fontColor = Config.Colors.textSecond, textAlign = "center",
            marginBottom = 4,
        })
    end

    -- 灵童选项列表
    table.insert(children, UI.Label { text = isActive and "升级/续雇:" or "可雇佣:", fontSize = 10, fontColor = Config.Colors.textPrimary, marginTop = 4 })

    for _, servantCfg in ipairs(Config.FieldServants) do
        local realmOk = State.state.realmLevel >= servantCfg.requiredRealm
        local canAfford = State.state.lingshi >= servantCfg.cost
        local isCurrent = isActive and (currentTier == servantCfg.tier)
        local canHire = realmOk and canAfford

        local btnText
        if isCurrent then btnText = "续雇24h"
        elseif not realmOk then btnText = "需" .. Config.Realms[servantCfg.requiredRealm].name
        else btnText = servantCfg.cost .. "石/日"
        end

        table.insert(children, UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 4,
            padding = 4, backgroundColor = Config.Colors.panelLight,
            borderRadius = 4, borderWidth = 1,
            borderColor = isCurrent and Config.Colors.jade or Config.Colors.border,
            children = {
                UI.Panel {
                    backgroundImage = servantCfg.image, backgroundFit = "contain",
                    width = 28, height = 28, borderRadius = 3,
                },
                UI.Panel {
                    flexGrow = 1, gap = 1,
                    children = {
                        UI.Label { text = servantCfg.name, fontSize = 10, fontColor = servantCfg.color, fontWeight = "bold" },
                        UI.Label { text = servantCfg.desc, fontSize = 7, fontColor = Config.Colors.textSecond },
                    },
                },
                UI.Button {
                    text = btnText,
                    fontSize = 8, height = 22, paddingHorizontal = 6,
                    disabled = not canHire,
                    backgroundColor = canHire and (isCurrent and Config.Colors.jadeDark or Config.Colors.purpleDark) or { 60, 60, 70, 200 },
                    textColor = canHire and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 4,
                    onClick = function(self)
                        -- 实际执行雇佣的函数
                        local function doHire()
                            if State.serverMode then
                                GameCore.SendGameAction("hire_servant", { tier = servantCfg.tier })
                            else
                                if not canAfford then
                                    UI.Toast.Show("灵石不足", { variant = "warning", duration = 2 })
                                    return
                                end
                                State.state.lingshi = State.state.lingshi - servantCfg.cost
                                State.state.fieldServant.tier = servantCfg.tier
                                State.state.fieldServant.expireTime = os.time() + 86400
                                State.Emit("servant_changed")
                                State.Emit("lingshi_changed")
                                GameCore.AddLog("雇佣" .. servantCfg.name .. "! 24h", servantCfg.color)
                            end
                            modal:Close()
                            UI.Toast.Show("已雇佣" .. servantCfg.name .. " (24小时)", { variant = "success", duration = 2 })
                        end
                        -- 切换到不同等级时弹确认框
                        if isActive and not isCurrent then
                            local oldCfg = Config.FieldServants[currentTier]
                            local oldName = oldCfg and oldCfg.name or "当前灵童"
                            local remainStr = formatDuration(remain)
                            UI.Modal.Confirm({
                                title = "确认切换灵童",
                                message = "当前" .. oldName .. "剩余" .. remainStr .. "将失效,\n切换为" .. servantCfg.name .. "需" .. servantCfg.cost .. "灵石,\n确定要切换吗?",
                                confirmText = "确认切换",
                                cancelText = "取消",
                                onConfirm = doHire,
                            })
                        else
                            doHire()
                        end
                    end,
                },
            },
        })
    end

    local dpr = graphics:GetDPR()
    local screenH = graphics:GetHeight() / dpr
    local scrollMaxH = math.floor(screenH * 0.55)

    modal:AddContent(UI.ScrollView {
        width = "100%",
        maxHeight = scrollMaxH,
        scrollY = true,
        showScrollbar = false,
        children = {
            UI.Panel { gap = 4, padding = 4, paddingBottom = (currentTier == 3 and 150 or 25), children = children },
        },
    })
    modal:Open()
end

-- ========== 计算地块签名 ==========
local function getPlotSignature(plotIdx)
    local maxPlots = Field.GetMaxPlots()
    if plotIdx > maxPlots then
        return "locked"
    end
    local plot = State.state.fieldPlots[plotIdx]
    local hasCrop = plot and plot.cropId and plot.cropId ~= ""
    if not hasCrop then
        return "empty"
    end
    local progress = Field.GetProgress(plotIdx)
    if progress >= 1.0 then
        return "harvestable_" .. plot.cropId
    end
    return "growing_" .. plot.cropId
end

-- ========== 地块卡片(完整创建) ==========

---@param plotIdx number
---@return table UIPanel
local function createPlotCard(plotIdx)
    local maxPlots = Field.GetMaxPlots()
    if plotIdx > maxPlots then
        -- 锁定的地块
        return UI.Panel {
            id = "plot_" .. plotIdx,
            width = "48%",
            height = 88,
            borderRadius = 6,
            overflow = "hidden",
            justifyContent = "center",
            alignItems = "center",
            children = {
                -- 背景图(灰暗表示锁定)
                UI.Panel {
                    backgroundImage = FieldImages.locked,
                    backgroundFit = "cover",
                    width = "100%",
                    height = "100%",
                    position = "absolute",
                    top = 0, left = 0,
                    opacity = 0.3,
                },
                -- 半透明遮罩
                UI.Panel {
                    width = "100%", height = "100%",
                    position = "absolute", top = 0, left = 0,
                    backgroundColor = { 0, 0, 0, 120 },
                },
                UI.Label { text = "Lv" .. (plotIdx), fontSize = 11, fontColor = { 180, 180, 180, 200 }, fontWeight = "bold" },
                UI.Label { text = "升级解锁", fontSize = 9, fontColor = { 140, 140, 140, 180 } },
            },
        }
    end

    local plot = State.state.fieldPlots[plotIdx]
    local hasCrop = plot and plot.cropId and plot.cropId ~= ""
    print("[FieldUI] createPlotCard idx=" .. plotIdx
        .. " plot=" .. tostring(plot)
        .. " cropId=" .. tostring(plot and plot.cropId)
        .. " hasCrop=" .. tostring(hasCrop))

    if not hasCrop then
        -- 空地块 - 种植选择
        local seedBtns = {}
        for seedIdx, crop in ipairs(Config.Crops) do
            local seedBtn = UI.Button {
                text = crop.icon .. crop.cost,
                fontSize = 9,
                flexGrow = 1,
                flexBasis = 0,
                height = 26,
                backgroundColor = { 30, 35, 25, 180 },
                textColor = crop.color,
                borderRadius = 4,
                onClick = function(self)
                    local ok, reason = Field.Plant(plotIdx, crop.id)
                    if ok then
                        GameCore.AddLog("种植: " .. crop.name, crop.color)
                    else
                        UI.Toast.Show(reason, { variant = "warning", duration = 2 })
                    end
                    Guide.NotifyAction("plant_btn")
                end,
            }
            -- 第一个空地块的第一个种子按钮注册为引导目标
            if not guidePlantRegistered_ and seedIdx == 1 then
                guidePlantRegistered_ = true
                Guide.RegisterTarget("plant_btn", seedBtn)
            end
            table.insert(seedBtns, seedBtn)
        end

        return UI.Panel {
            id = "plot_" .. plotIdx,
            width = "48%",
            height = 88,
            borderRadius = 6,
            overflow = "hidden",
            justifyContent = "flex-end",
            children = {
                -- 背景图
                UI.Panel {
                    backgroundImage = FieldImages.empty,
                    backgroundFit = "cover",
                    width = "100%",
                    height = "100%",
                    position = "absolute",
                    top = 0, left = 0,
                },
                -- 标题
                UI.Label {
                    text = "空地 #" .. plotIdx,
                    fontSize = 9,
                    fontColor = { 220, 220, 200, 220 },
                    textAlign = "center",
                    width = "100%",
                },
                -- 种植按钮行
                UI.Panel {
                    flexDirection = "row",
                    gap = 3,
                    width = "100%",
                    padding = 4,
                    children = seedBtns,
                },
            },
        }
    end

    -- 有作物 - 显示进度
    local crop = Field.GetCropById(plot.cropId)
    local progress, remain = Field.GetProgress(plotIdx)
    local canHarvest = progress >= 1.0
    local cropName = crop and crop.name or "?"
    local cropColor = crop and crop.color or Config.Colors.textPrimary

    -- 根据进度选择背景图
    local bgImage
    if canHarvest then
        bgImage = FieldImages.mature
    elseif progress < 0.15 then
        bgImage = FieldImages.seeded
    else
        bgImage = FieldImages.growing
    end

    -- 进度条
    local barWidth = math.floor(progress * 100)
    local progressBar = UI.Panel {
        id = "plot_" .. plotIdx .. "_barBg",
        width = "100%",
        height = 6,
        backgroundColor = { 0, 0, 0, 120 },
        borderRadius = 3,
        overflow = "hidden",
        children = {
            UI.Panel {
                id = "plot_" .. plotIdx .. "_bar",
                width = barWidth .. "%",
                height = "100%",
                backgroundColor = canHarvest and Config.Colors.jade or { 100, 200, 255, 255 },
                borderRadius = 3,
            },
        },
    }

    local actionWidget = nil
    if canHarvest then
        actionWidget = UI.Button {
            id = "plot_" .. plotIdx .. "_action",
            text = "收获",
            fontSize = 10,
            paddingHorizontal = 10,
            height = 24,
            backgroundColor = { 40, 120, 60, 220 },
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                local rewards = Field.Harvest(plotIdx)
                if rewards then
                    local parts = {}
                    for matId, amt in pairs(rewards) do
                        local mat = Config.GetMaterialById(matId)
                        if mat then table.insert(parts, mat.name .. "+" .. amt) end
                    end
                    GameCore.AddLog("收获: " .. table.concat(parts, " "), Config.Colors.jade)
                    GameCore.AddFloatingText(table.concat(parts, " "), Config.Colors.jade)
                end
            end,
        }
    else
        actionWidget = UI.Label {
            id = "plot_" .. plotIdx .. "_time",
            text = formatTime(remain),
            fontSize = 10,
            fontColor = { 255, 255, 255, 230 },
            fontWeight = "bold",
        }
    end

    return UI.Panel {
        id = "plot_" .. plotIdx,
        width = "48%",
        height = 88,
        borderRadius = 6,
        overflow = "hidden",
        justifyContent = "flex-end",
        children = {
            -- 状态背景图
            UI.Panel {
                backgroundImage = bgImage,
                backgroundFit = "cover",
                width = "100%",
                height = "100%",
                position = "absolute",
                top = 0, left = 0,
            },
            -- 信息区(底部半透明条)
            UI.Panel {
                width = "100%",
                backgroundColor = { 0, 0, 0, 110 },
                padding = 4,
                gap = 3,
                children = {
                    UI.Panel {
                        flexDirection = "row", alignItems = "center", justifyContent = "space-between",
                        width = "100%",
                        children = {
                            UI.Label {
                                text = (crop and crop.icon or "?") .. " " .. cropName,
                                fontSize = 10,
                                fontColor = { 255, 255, 255, 240 },
                                fontWeight = "bold",
                            },
                            actionWidget,
                        },
                    },
                    progressBar,
                },
            },
        },
    }
end

-- ========== 原地更新进度(不重建卡片) ==========
local function updatePlotProgress(grid, plotIdx)
    local progress, remain = Field.GetProgress(plotIdx)
    local barWidth = math.floor(progress * 100)

    -- 更新进度条宽度
    local bar = grid:FindById("plot_" .. plotIdx .. "_bar")
    if bar then
        bar:SetStyle({ width = barWidth .. "%" })
    end

    -- 更新剩余时间文本
    local timeLabel = grid:FindById("plot_" .. plotIdx .. "_time")
    if timeLabel then
        timeLabel:SetText(formatTime(remain))
    end
end

-- ========== 公开接口 ==========

function M.Create()
    fieldPanel = UI.Panel {
        id = "field_page",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        paddingHorizontal = 4,
        paddingVertical = 2,
        gap = 3,
        children = {
            -- 标题行: 灵田等级 + 升级 + 一键收获
            UI.Panel {
                id = "field_header",
                flexDirection = "row",
                width = "100%",
                alignItems = "center",
                gap = 3,
            },
            -- 灵童状态条
            UI.Panel {
                id = "servant_bar",
                width = "100%",
            },
            -- 地块网格
            UI.Panel {
                id = "field_grid",
                flexDirection = "row",
                flexWrap = "wrap",
                gap = 4,
                width = "100%",
                justifyContent = "space-between",
            },
            -- 种子价格说明 (紧凑底部)
            UI.Panel {
                id = "field_info",
                gap = 1,
                paddingVertical = 1,
            },
        },
    }
    -- 初始标记全部脏
    gridDirty = true
    headerDirty = true
    infoDirty = true
    servantDirty = true
    plotSignatures = {}
    return fieldPanel
end

local lastServantRefresh_ = 0

function M.Refresh()
    if not fieldPanel then return end

    -- 灵童状态条每30秒自动刷新(更新剩余时间)
    local now = os.time()
    if now - lastServantRefresh_ >= 30 then
        lastServantRefresh_ = now
        local sv = State.state.fieldServant
        if sv and sv.tier > 0 then servantDirty = true end
    end

    -- === Header: 只在脏时重建 ===
    if headerDirty then
        headerDirty = false
        local header = fieldPanel:FindById("field_header")
        if header then
            header:ClearChildren()
            local lvl = State.state.fieldLevel
            header:AddChild(UI.Label {
                text = "灵田 Lv." .. lvl .. " (" .. Field.GetMaxPlots() .. "块)",
                fontSize = 11,
                fontColor = Config.Colors.textGold,
                fontWeight = "bold",
                flexGrow = 1,
            })
            -- 升级按钮
            local upgradeCost = Field.GetUpgradeCost()
            if upgradeCost then
                local reqRealm, reqName = Field.GetUpgradeRealmReq()
                local realmOk = not reqRealm or State.state.realmLevel >= reqRealm
                local canAfford = State.state.lingshi >= upgradeCost
                local canUpgrade = realmOk and canAfford
                local btnText = "升级" .. upgradeCost
                if reqRealm and not realmOk then
                    btnText = "需" .. reqName .. "期"
                end
                header:AddChild(UI.Button {
                    text = btnText,
                    fontSize = 8,
                    height = 20,
                    paddingHorizontal = 6,
                    disabled = not canUpgrade,
                    backgroundColor = canUpgrade and Config.Colors.purpleDark or { 60, 60, 70, 200 },
                    textColor = canUpgrade and { 255, 255, 255, 255 } or Config.Colors.textSecond,
                    borderRadius = 4,
                    onClick = function(self)
                        local ok, reason = Field.UpgradeField()
                        if ok then
                            GameCore.AddLog("灵田升级!", Config.Colors.textGold)
                            UI.Toast.Show("灵田升级成功!", { variant = "success", duration = 2 })
                        else
                            UI.Toast.Show(reason, { variant = "warning", duration = 2 })
                        end
                    end,
                })
            else
                header:AddChild(UI.Label {
                    text = "已满级",
                    fontSize = 9,
                    fontColor = Config.Colors.textSecond,
                })
            end
            -- 一键收获
            if Field.HasHarvestable() then
                header:AddChild(UI.Button {
                    text = "一键收",
                    fontSize = 8,
                    height = 20,
                    paddingHorizontal = 5,
                    backgroundColor = Config.Colors.jadeDark,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 4,
                    onClick = function(self)
                        local total = Field.HarvestAll()
                        local parts = {}
                        for matId, amt in pairs(total) do
                            local mat = Config.GetMaterialById(matId)
                            if mat then table.insert(parts, mat.name .. "+" .. amt) end
                        end
                        if #parts > 0 then
                            GameCore.AddLog("一键收获: " .. table.concat(parts, " "), Config.Colors.jade)
                        end
                        -- field_changed 事件会自动标脏
                    end,
                })
            end
        end
    end

    -- === 灵童状态条 ===
    if servantDirty then
        servantDirty = false
        local sbar = fieldPanel:FindById("servant_bar")
        if sbar then
            sbar:ClearChildren()
            local sv = State.state.fieldServant
            local tier = sv and sv.tier or 0
            local isActive = tier > 0 and os.time() < (sv.expireTime or 0)
            if isActive then
                local cfg = Config.FieldServants[tier]
                local remain = sv.expireTime - os.time()
                sbar:AddChild(UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4,
                    paddingHorizontal = 4, paddingVertical = 2,
                    backgroundColor = { 35, 45, 30, 200 },
                    borderRadius = 4, borderWidth = 1, borderColor = cfg.color,
                    children = {
                        UI.Panel {
                            backgroundImage = cfg.image, backgroundFit = "contain",
                            width = 18, height = 18, borderRadius = 3,
                        },
                        UI.Label {
                            text = cfg.name .. (sv.paused and "(停)" or ""),
                            fontSize = 9, fontColor = sv.paused and Config.Colors.textSecond or cfg.color, fontWeight = "bold",
                        },
                        UI.Label { text = formatDuration(remain), fontSize = 8, fontColor = Config.Colors.textGold },
                        UI.Panel { flexGrow = 1 },
                        UI.Button {
                            text = sv.paused and "恢复" or "暂停",
                            fontSize = 8, height = 18, paddingHorizontal = 6,
                            backgroundColor = sv.paused and Config.Colors.jadeDark or { 120, 80, 40, 200 },
                            textColor = { 255, 255, 255, 255 },
                            borderRadius = 3,
                            onClick = function(self)
                                if State.serverMode then
                                    GameCore.SendGameAction("toggle_servant_pause", {})
                                else
                                    State.state.fieldServant.paused = not State.state.fieldServant.paused
                                    State.Emit("servant_changed")
                                end
                                servantDirty = true
                            end,
                        },
                        UI.Button {
                            text = "管理",
                            fontSize = 8, height = 18, paddingHorizontal = 6,
                            backgroundColor = Config.Colors.panelLight,
                            textColor = Config.Colors.textPrimary,
                            borderRadius = 3,
                            onClick = function(self) showServantModal() end,
                        },
                    },
                })
            else
                sbar:AddChild(UI.Button {
                    text = "雇佣灵童 (自动种植/收获)",
                    fontSize = 9, height = 22, width = "100%",
                    backgroundColor = { 45, 55, 40, 180 },
                    textColor = Config.Colors.textSecond,
                    borderRadius = 4, borderWidth = 1,
                    borderColor = { 80, 100, 60, 150 },
                    onClick = function(self) showServantModal() end,
                })
            end
        end
    end

    -- === 地块网格 ===
    local grid = fieldPanel:FindById("field_grid")
    if grid then
        local maxPossible = Config.FieldLevels[#Config.FieldLevels].plots

        -- 检查是否有结构变化(签名改变)
        if not gridDirty then
            for i = 1, maxPossible do
                local newSig = getPlotSignature(i)
                if plotSignatures[i] ~= newSig then
                    gridDirty = true
                    break
                end
            end
        end

        -- 检测是否有新作物变为可收获 → 需要重建(按钮替换文本)
        -- 已包含在签名检测中: growing→harvestable 签名会变

        if gridDirty then
            -- 完整重建
            gridDirty = false
            guidePlantRegistered_ = false  -- 重建时重置引导注册标记
            grid:ClearChildren()
            for i = 1, maxPossible do
                plotSignatures[i] = getPlotSignature(i)
                grid:AddChild(createPlotCard(i))
            end
            -- 结构变化时也刷新 header (一键收获按钮可能出现/消失)
            headerDirty = true
        else
            -- 仅更新进度数值(不重建卡片)
            for i = 1, maxPossible do
                local sig = plotSignatures[i]
                if sig and sig:sub(1, 7) == "growing" then
                    updatePlotProgress(grid, i)
                end
            end
        end
    end

    -- === 底部种子说明 (只建一次) ===
    if infoDirty then
        infoDirty = false
        local info = fieldPanel:FindById("field_info")
        if info then
            info:ClearChildren()
            local speedBonus = Field.GetServantSpeedBonus()
            local parts = {}
            for _, crop in ipairs(Config.Crops) do
                local yieldParts = {}
                for matId, amt in pairs(crop.yield) do
                    local mat = Config.GetMaterialById(matId)
                    if mat then table.insert(yieldParts, mat.name .. "x" .. amt) end
                end
                local actualGrowTime = crop.growTime / (1 + speedBonus)
                local timeStr = formatTime(actualGrowTime)
                if speedBonus > 0 then
                    timeStr = timeStr .. "(加速)"
                end
                table.insert(parts, crop.icon .. crop.name .. ":" .. crop.cost .. "石," .. timeStr .. "→" .. table.concat(yieldParts, ","))
            end
            info:AddChild(UI.Label {
                text = table.concat(parts, "  |  "),
                fontSize = 7,
                fontColor = Config.Colors.textSecond,
            })
        end
    end
end

return M
