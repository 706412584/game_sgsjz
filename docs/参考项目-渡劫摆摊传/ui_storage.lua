-- ============================================================================
-- ui_storage.lua — 储物系统界面 (Modal弹窗)
-- 三Tab: 材料 / 商品 / 珍藏
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local M = {}

local modal_ = nil
local contentPanel_ = nil
local activeTab_ = "materials"  -- "materials" | "products" | "collectibles"
local pendingCollectibleUse_ = false  -- 防抖：避免重复点击"使用"按钮
local function resetUseFlag_() pendingCollectibleUse_ = false end

-- ========== Tab颜色 ==========
local TAB_ACTIVE_BG   = Config.Colors.jadeDark
local TAB_INACTIVE_BG = { 50, 55, 75, 200 }
local TAB_ACTIVE_TEXT  = { 255, 255, 255, 255 }
local TAB_INACTIVE_TEXT = Config.Colors.textSecond

-- ========== 渲染Tab栏 ==========

local function renderTabs(parent)
    local tabs = {
        { key = "materials",     label = "材料" },
        { key = "products",      label = "商品" },
        { key = "collectibles",  label = "珍藏" },
    }

    local tabRow = UI.Panel {
        flexDirection = "row",
        width = "100%",
        gap = 4,
        marginBottom = 6,
    }

    for _, tab in ipairs(tabs) do
        local isActive = activeTab_ == tab.key
        local tabKey = tab.key
        tabRow:AddChild(UI.Button {
            text = tab.label,
            fontSize = 11,
            height = 28,
            flexGrow = 1,
            backgroundColor = isActive and TAB_ACTIVE_BG or TAB_INACTIVE_BG,
            textColor = isActive and TAB_ACTIVE_TEXT or TAB_INACTIVE_TEXT,
            borderRadius = 6,
            borderWidth = isActive and 1 or 0,
            borderColor = Config.Colors.jade,
            onClick = function()
                if activeTab_ ~= tabKey then
                    activeTab_ = tabKey
                    refreshContent()
                end
            end,
        })
    end

    parent:AddChild(tabRow)
end

-- ========== 材料Tab ==========

local function renderMaterials(parent)
    local s = State.state
    local mats = s.materials or {}
    local isAscended = (s.ascended == true)

    parent:AddChild(UI.Label {
        text = isAscended and "仙界材料" or "材料库存",
        fontSize = 12,
        fontColor = Config.Colors.textGold,
        fontWeight = "bold",
        marginBottom = 4,
    })

    for _, mat in ipairs(Config.Materials) do
        -- 飞升后只显示仙界材料；未飞升只显示凡间材料
        if (mat.celestial == true) ~= isAscended then goto continueMat end
        local count = mats[mat.id] or 0
        local cap = mat.cap or 9999
        local countStr = (count >= 1 and HUD.FormatNumber(math.floor(count)) or "0") .. "/" .. HUD.FormatNumber(cap)

        -- 珍藏加成提示
        local bonusVal = Config.GetCollectibleBonus(s.collectibles or {}, "material_rate_" .. mat.id)
        local bonusText = ""
        if bonusVal > 0 then
            bonusText = " (珍藏+" .. string.format("%.0f", bonusVal * 100) .. "%)"
        end

        parent:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            padding = 8,
            gap = 8,
            backgroundColor = { 45, 50, 70, 230 },
            borderRadius = 8,
            borderWidth = 1,
            borderColor = Config.Colors.border,
            marginBottom = 3,
            children = {
                -- 图标
                UI.Panel {
                    width = 28, height = 28,
                    backgroundImage = Config.Images[mat.id],
                    backgroundFit = "contain",
                },
                -- 名称+产速
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = {
                        UI.Label {
                            text = mat.name,
                            fontSize = 11,
                            fontColor = mat.color or Config.Colors.textPrimary,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = "产速: " .. string.format("%.1f", mat.rate) .. "/分" .. bonusText,
                            fontSize = 8,
                            fontColor = bonusVal > 0 and Config.Colors.textGreen or Config.Colors.textSecond,
                        },
                    },
                },
                -- 数量
                UI.Label {
                    text = countStr,
                    fontSize = 12,
                    fontColor = (math.floor(count) >= cap) and { 255, 80, 80, 255 } or Config.Colors.textGold,
                    fontWeight = "bold",
                },
            },
        })
        ::continueMat::
    end
end

-- ========== 商品Tab ==========

local function renderProducts(parent)
    local s = State.state
    local products = s.products or {}
    local realmLevel = s.realmLevel or 1
    local isAscended = (s.ascended == true)

    parent:AddChild(UI.Label {
        text = isAscended and "仙界商品" or "商品库存",
        fontSize = 12,
        fontColor = Config.Colors.textGold,
        fontWeight = "bold",
        marginBottom = 4,
    })

    local hasAny = false
    for _, prod in ipairs(Config.Products) do
        -- 飞升后只显示仙界商品；未飞升只显示凡间商品
        if (prod.celestial == true) ~= isAscended then goto continueProd end
        local count = products[prod.id] or 0
        local unlocked = realmLevel >= prod.unlockRealm

        if unlocked then
            hasAny = true
            local realmName = Config.Realms[prod.unlockRealm] and Config.Realms[prod.unlockRealm].name or ""
            local cardBg = count > 0 and { 45, 50, 70, 230 } or { 35, 38, 50, 200 }

            parent:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                padding = 8,
                gap = 8,
                backgroundColor = cardBg,
                borderRadius = 8,
                borderWidth = 1,
                borderColor = count > 0 and Config.Colors.border or { 60, 60, 70, 100 },
                marginBottom = 3,
                children = {
                    -- 商品信息
                    UI.Panel {
                        flexGrow = 1,
                        flexShrink = 1,
                        children = {
                            UI.Label {
                                text = prod.name,
                                fontSize = 11,
                                fontColor = count > 0 and Config.Colors.textPrimary or Config.Colors.textSecond,
                                fontWeight = "bold",
                            },
                            UI.Label {
                                text = realmName .. " | 售价: " .. HUD.FormatNumber(prod.price),
                                fontSize = 8,
                                fontColor = Config.Colors.textSecond,
                            },
                        },
                    },
                    -- 数量
                    UI.Label {
                        text = "x" .. count,
                        fontSize = 13,
                        fontColor = count > 0 and Config.Colors.textGold or Config.Colors.textSecond,
                        fontWeight = "bold",
                    },
                },
            })
        end
        ::continueProd::
    end

    if not hasAny then
        parent:AddChild(UI.Label {
            text = "暂无已解锁商品",
            fontSize = 10,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            marginTop = 20,
        })
    end
end

-- ========== 珍藏Tab ==========

local function renderCollectibles(parent)
    local s = State.state
    local collectibles = s.collectibles or {}
    local isAscended = (s.ascended == true)

    parent:AddChild(UI.Label {
        text = "珍藏物品",
        fontSize = 12,
        fontColor = Config.Colors.textGold,
        fontWeight = "bold",
        marginBottom = 4,
    })

    -- 总加成概览
    local bonusSummary = {}
    local bonusNames = {
        material_rate_lingcao = "灵草产量",
        material_rate_lingzhi = "灵纸产量",
        material_rate_xuantie = "玄铁产量",
        sell_price = "商品售价",
        craft_speed = "制作速度",
    }
    for bonusType, bonusName in pairs(bonusNames) do
        local val = Config.GetCollectibleBonus(collectibles, bonusType)
        if val > 0 then
            table.insert(bonusSummary, bonusName .. "+" .. string.format("%.0f", val * 100) .. "%")
        end
    end

    if #bonusSummary > 0 then
        parent:AddChild(UI.Panel {
            width = "100%",
            padding = 6,
            borderRadius = 6,
            backgroundColor = { 40, 50, 45, 200 },
            borderWidth = 1,
            borderColor = Config.Colors.jadeDark,
            marginBottom = 6,
            children = {
                UI.Label {
                    text = "珍藏总加成: " .. table.concat(bonusSummary, "  "),
                    fontSize = 9,
                    fontColor = Config.Colors.textGreen,
                    textAlign = "center",
                    width = "100%",
                },
            },
        })
    end

    -- 物品列表
    local hasAny = false
    for _, cfg in ipairs(Config.Collectibles) do
        local count = collectibles[cfg.id] or 0
        if count > 0 then
            hasAny = true
            local isPerm = cfg.type == "permanent"
            local typeBg = isPerm and { 40, 55, 50, 230 } or { 55, 45, 40, 230 }
            local typeBorder = isPerm and Config.Colors.jadeDark or Config.Colors.goldDark
            local typeLabel = isPerm and "永久" or "消耗"
            local typeColor = isPerm and Config.Colors.textGreen or Config.Colors.orange

            local cardChildren = {}

            -- 第一行: 图标 + 名称 + 类型 + 数量
            table.insert(cardChildren, UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                gap = 6,
                children = {
                    -- 图标
                    UI.Panel {
                        width = 24, height = 24,
                        backgroundImage = cfg.icon,
                        backgroundFit = "contain",
                    },
                    -- 名称
                    UI.Label {
                        text = cfg.name,
                        fontSize = 11,
                        fontColor = cfg.color or Config.Colors.textPrimary,
                        fontWeight = "bold",
                        flexShrink = 1,
                    },
                    -- 类型标记
                    UI.Panel {
                        paddingHorizontal = 4,
                        paddingVertical = 1,
                        backgroundColor = isPerm and { 40, 80, 60, 200 } or { 80, 60, 40, 200 },
                        borderRadius = 4,
                        children = {
                            UI.Label {
                                text = typeLabel,
                                fontSize = 8,
                                fontColor = typeColor,
                            },
                        },
                    },
                    -- 数量
                    UI.Label {
                        text = "x" .. count,
                        fontSize = 12,
                        fontColor = Config.Colors.textGold,
                        fontWeight = "bold",
                    },
                },
            })

            -- 第二行: 描述
            table.insert(cardChildren, UI.Label {
                text = cfg.desc,
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                width = "100%",
            })

            -- 第三行: 效果/加成 + 使用按钮
            local effectRow = UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                gap = 6,
            }

            if isPerm and cfg.bonus then
                -- 只生效1个,不按数量叠加
                local bonusVal = cfg.bonus.value * 100
                effectRow:AddChild(UI.Label {
                    text = "加成: +" .. string.format("%.0f", bonusVal) .. "%" .. (count > 1 and " (多余可出售)" or ""),
                    fontSize = 9,
                    fontColor = Config.Colors.textGreen,
                    flexGrow = 1,
                    flexShrink = 1,
                })
                -- 出售按钮: 永久珍藏需保留至少1个
                if count > 1 then
                    local itemIdCopy = cfg.id
                    local itemName = cfg.name or "物品"
                    local sellPrice = Config.GetCollectibleSellPrice(itemIdCopy)
                    effectRow:AddChild(UI.Button {
                        text = "出售",
                        fontSize = 9,
                        height = 22,
                        paddingHorizontal = 10,
                        backgroundColor = Config.Colors.goldDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function()
                            UI.Modal.Confirm({
                                title = "确认出售",
                                message = "确定出售1个「" .. itemName .. "」?\n可获得 " .. sellPrice .. " 灵石\n(永久珍藏至少保留1个)",
                                confirmText = "确认出售",
                                cancelText = "取消",
                                onConfirm = function()
                                    GameCore.SendGameAction("sell_collectible", { itemId = itemIdCopy, amount = 1 })
                                end,
                            })
                        end,
                    })
                end
            elseif not isPerm then
                effectRow:AddChild(UI.Label {
                    text = cfg.effect == "breakthrough_discount" and "突破材料(自动消耗)" or "可使用",
                    fontSize = 9,
                    fontColor = Config.Colors.textSecond,
                    flexGrow = 1,
                    flexShrink = 1,
                })

                -- 使用按钮(仅非突破材料的消耗品)
                if cfg.effect ~= "breakthrough_discount" then
                    local itemIdCopy = cfg.id
                    effectRow:AddChild(UI.Button {
                        text = "使用",
                        fontSize = 9,
                        height = 22,
                        paddingHorizontal = 10,
                        backgroundColor = Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function()
                            if pendingCollectibleUse_ then return end
                            pendingCollectibleUse_ = true
                            GameCore.SendGameAction("use_collectible", { id = itemIdCopy })
                        end,
                    })
                end
                -- 出售按钮: 消耗品可全部出售
                if count > 0 then
                    local itemIdCopy = cfg.id
                    local itemName = cfg.name or "物品"
                    local sellPrice = Config.GetCollectibleSellPrice(itemIdCopy)
                    effectRow:AddChild(UI.Button {
                        text = "出售",
                        fontSize = 9,
                        height = 22,
                        paddingHorizontal = 10,
                        backgroundColor = Config.Colors.goldDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function()
                            UI.Modal.Confirm({
                                title = "确认出售",
                                message = "确定出售1个「" .. itemName .. "」?\n可获得 " .. sellPrice .. " 灵石",
                                confirmText = "确认出售",
                                cancelText = "取消",
                                onConfirm = function()
                                    GameCore.SendGameAction("sell_collectible", { itemId = itemIdCopy, amount = 1 })
                                end,
                            })
                        end,
                    })
                end
            end

            table.insert(cardChildren, effectRow)

            parent:AddChild(UI.Panel {
                width = "100%",
                padding = 8,
                gap = 3,
                borderRadius = 8,
                backgroundColor = typeBg,
                borderWidth = 1,
                borderColor = typeBorder,
                marginBottom = 4,
                children = cardChildren,
            })
        end
    end

    -- 未拥有的珍藏(灰色预览)
    local previewLabel = UI.Label {
        text = "未获得的珍藏",
        fontSize = 10,
        fontColor = Config.Colors.textSecond,
        marginTop = hasAny and 6 or 0,
        marginBottom = 2,
    }
    local hasPreview = false
    for _, cfg in ipairs(Config.Collectibles) do
        -- 只预览当前阶段（凡间/仙界）的珍藏
        if (cfg.requireAscended == true) ~= isAscended then goto skipPreview1 end
        local count = collectibles[cfg.id] or 0
        if count <= 0 then
            hasPreview = true
        end
        ::skipPreview1::
    end
    if hasPreview then
        parent:AddChild(previewLabel)
    end

    for _, cfg in ipairs(Config.Collectibles) do
        -- 只预览当前阶段（凡间/仙界）的珍藏
        if (cfg.requireAscended == true) ~= isAscended then goto skipPreview2 end
        local count = collectibles[cfg.id] or 0
        if count <= 0 then
            -- 查找掉落秘境
            local sourceDungeon = ""
            for dungeonId, drops in pairs(Config.DungeonDrops) do
                for _, drop in ipairs(drops) do
                    if drop.id == cfg.id then
                        local d = Config.GetDungeonById(dungeonId)
                        sourceDungeon = d and d.name or dungeonId
                        break
                    end
                end
                if sourceDungeon ~= "" then break end
            end

            parent:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                padding = 6,
                gap = 6,
                backgroundColor = { 35, 38, 50, 180 },
                borderRadius = 6,
                borderWidth = 1,
                borderColor = { 60, 60, 70, 80 },
                marginBottom = 2,
                children = {
                    UI.Panel {
                        width = 20, height = 20,
                        backgroundImage = cfg.icon,
                        backgroundFit = "contain",
                        opacity = 0.4,
                    },
                    UI.Label {
                        text = cfg.name,
                        fontSize = 9,
                        fontColor = { 100, 100, 110, 180 },
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = sourceDungeon ~= "" and ("来源: " .. sourceDungeon) or "",
                        fontSize = 8,
                        fontColor = { 80, 80, 90, 150 },
                        flexGrow = 1,
                        textAlign = "right",
                    },
                },
            })
        end
        ::skipPreview2::
    end

    if not hasAny and not hasPreview then
        parent:AddChild(UI.Label {
            text = "暂无珍藏物品\n探索秘境可获得珍藏",
            fontSize = 10,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            marginTop = 20,
        })
    end
end

-- ========== 刷新弹窗内容 ==========

function refreshContent()
    if not contentPanel_ then return end
    pendingCollectibleUse_ = false  -- 刷新时重置使用防抖
    contentPanel_:ClearChildren()

    renderTabs(contentPanel_)

    if activeTab_ == "materials" then
        renderMaterials(contentPanel_)
    elseif activeTab_ == "products" then
        renderProducts(contentPanel_)
    elseif activeTab_ == "collectibles" then
        renderCollectibles(contentPanel_)
    end
end

-- ========== 打开弹窗 ==========

function M.Open()
    if modal_ then
        refreshContent()
        return
    end

    modal_ = UI.Modal {
        title = "储物",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self)
            contentPanel_ = nil
            modal_ = nil
            pendingCollectibleUse_ = false
            State.Off("collectible_changed", refreshContent)
            State.Off("server_sync", refreshContent)
            State.Off("material_changed", refreshContent)
            State.Off("product_changed", refreshContent)
            State.Off("action_fail_received", resetUseFlag_)
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

    -- 监听数据变更
    State.On("collectible_changed", refreshContent)
    State.On("server_sync", refreshContent)
    State.On("material_changed", refreshContent)
    State.On("product_changed", refreshContent)
    State.On("action_fail_received", resetUseFlag_)  -- 失败时重置使用防抖

    modal_:Open()
end

function M.Close()
    if modal_ then
        modal_:Close()
    end
end

return M
