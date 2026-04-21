-- ============================================================================
-- main.lua — 渡劫摆摊传 主入口 (竖屏适配版)
-- 负责初始化 UI、组装页面、驱动游戏循环、离线收益、新手引导
-- 布局: HUD → 工具栏 → 内容 → 引导条 → 日志条 → 底部Tab
-- ============================================================================

local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")
local Stall = require("ui_stall")
local Craft = require("ui_craft")
local Upgrade = require("ui_upgrade")
local Ad = require("ui_ad")
local FieldUI = require("ui_field")
local Log = require("ui_log")
local Tutorial = require("game_tutorial")
local Rank = require("ui_rank")
local CDK = require("ui_cdk")
local GM = require("ui_gm")
local Chat = require("ui_chat")
local Settings = require("ui_settings")
local StartScreen = require("ui_start")
local Mail = require("ui_mail")
local ServerSelect = require("ui_server")
local Rebirth = require("ui_rebirth")
local CharCreate = require("ui_character_create")
local XToast = require("ui_toast")
local Bargain = require("ui_bargain")
local Daily = require("ui_daily")
local Dungeon = require("ui_dungeon")
local Dujie = require("game_dujie")
local Tribulation = require("ui_tribulation")
local ClientNet = require("network.client_net")
local Loading = require("ui_loading")
local ReconnectOverlay = require("ui_reconnect")
local Particle = require("ui_particle")
local RedDot = require("ui_reddot")
local Guide = require("ui_guide")
local Encounter = require("game_encounter")
local DebugLog = require("ui_debug_log")


-- ========== 全局变量 ==========
local uiRoot_ = nil
local bgmNode_ = nil
local bgmSource_ = nil

-- 前置声明(enterGameFromStart 在 buildUI 之后定义, 但闭包中引用)
local enterGameFromStart

-- 页面管理
local currentTab = "stall"
local tabPages = {}
local tabButtons = {}

-- UI 刷新节流
local uiRefreshTimer = 0
local UI_REFRESH_INTERVAL = 0.3

-- GM 延迟注入(lobby 就绪后显示)
local gmInjected_ = false
local gmBtnRef_ = nil

-- 离线弹窗兜底定时器: 进入游戏后若 pendingOffline_ 仍未消费则强制弹窗
local offlineFallbackTimer_ = nil   -- nil=未激活, >0=倒计时中
local offlineModalShown_ = false    -- 本次会话是否已弹过离线弹窗
local OFFLINE_FALLBACK_DELAY = 3.0  -- 兜底等待秒数

-- 云加载状态机:
--   "idle"       → 未开始, 等待用户点击"进入游戏"
--   "probe"      → 用轻量 Get 探测云端连接是否真正可用
--   "loading"    → 探测通过, 正在加载完整数据
--   "wait_retry" → 失败, 等待自动重试(从 probe 重新开始)
--   "failed"     → 多次失败, 等待用户手动重试
--   "done"       → 加载完成, 正常游戏
local loadState = "idle"
local cloudLoadTimer = 0
local PROBE_TIMEOUT = 4            -- 探针超时(秒), 短于正式请求
local CLOUD_LOAD_TIMEOUT = 8       -- 正式 BatchGet 超时(秒)
local retryCount = 0
local MAX_AUTO_RETRIES = 5
local AUTO_RETRY_DELAY = 2.0       -- 重试间隔(秒)

-- ========== Tab 定义 (竖屏精简) ==========
local TAB_DEFS = {
    { id = "stall",   label = "摆摊",  icon = "[摊]" },
    { id = "craft",   label = "制作",  icon = "[锤]" },
    { id = "field",   label = "灵田",  icon = "[田]" },
    { id = "upgrade", label = "角色",  icon = "[角]" },
    { id = "ad",      label = "福利",  icon = "[福]" },
    { id = "chat",    label = "聊天",  icon = "[聊]" },
}

local tabActiveColor  = { 75, 80, 95, 255 }
local tabNormalColor  = { 35, 38, 52, 255 }
local tabActiveText   = Config.Colors.textGold
local tabNormalText   = Config.Colors.textSecond

-- ========== Tab 切换逻辑 ==========

---@param tabId string
local function switchTab(tabId)
    -- 新手引导激活时，锁定Tab切换（仅允许引导系统内部切换）
    if not Guide.IsAllowedTabSwitch(tabId) then
        print("[Main] switchTab blocked by Guide: tabId=" .. tostring(tabId))
        return
    end
    if tabId == currentTab then
        print("[Main] switchTab skipped (already on tab): tabId=" .. tostring(tabId))
        return
    end
    currentTab = tabId

    -- 切换到特定页面时标记需要刷新
    if tabId == "ad" then Ad.MarkDirty() end
    if tabId == "chat" then Chat.MarkDirty() end

    -- 打坐粒子特效：角色页显示时开启，离开时关闭
    if tabId == "upgrade" then
        Particle.StartMeditate(0.5, 0.28)
    else
        Particle.StopMeditate()
    end

    for id, page in pairs(tabPages) do
        if id == tabId then
            page:Show()
            YGNodeStyleSetDisplay(page.node, YGDisplayFlex)
        else
            page:Hide()
            YGNodeStyleSetDisplay(page.node, YGDisplayNone)
        end
    end

    for id, btn in pairs(tabButtons) do
        if id == tabId then
            btn:SetStyle({ backgroundColor = tabActiveColor, textColor = tabActiveText })
        else
            btn:SetStyle({ backgroundColor = tabNormalColor, textColor = tabNormalText })
        end
    end

    refreshCurrentPage()
    RedDot.RefreshAll()
end

--- 刷新当前页面
function refreshCurrentPage()
    HUD.Refresh()
    if currentTab == "stall" then
        Stall.Refresh()
    elseif currentTab == "craft" then
        Craft.Refresh()
    elseif currentTab == "field" then
        FieldUI.Refresh()
    elseif currentTab == "upgrade" then
        Upgrade.Refresh()
    elseif currentTab == "ad" then
        Ad.Refresh()
    elseif currentTab == "chat" then
        Chat.Refresh()
    elseif currentTab == "gm" then
        GM.Refresh()
    end
    Chat.RefreshLogBar()
    Tutorial.Refresh()
    RedDot.RefreshAll()
end

-- ========== 离线收益弹窗 ==========

--- 格式化离线收益内容面板
---@param earnings table
---@return table contentPanel
local function buildOfflineContentPanel(earnings, adWatched, adMax)
    local children = {}
    -- 离线时长 + 产率
    local capH = math.floor((GameCore.GetOfflineBaseCap() + adWatched * (select(1, GameCore.GetOfflineAdExtend()))) / 3600)
    table.insert(children, UI.Label {
        text = "你离开了 " .. earnings.minutes .. " 分钟 (上限" .. capH .. "h)",
        fontSize = 12,
        fontColor = Config.Colors.textPrimary,
    })
    table.insert(children, UI.Label {
        text = "离线产率 " .. math.floor(earnings.rate * 100) .. "% (在线可获更多)",
        fontSize = 10,
        fontColor = Config.Colors.orange,
    })

    -- 材料
    local hasAnyMat = false
    local matLabels = {}
    for _, mat in ipairs(Config.Materials) do
        local amt = earnings.materials[mat.id]
        if amt and amt > 0 then
            hasAnyMat = true
            table.insert(matLabels, UI.Label {
                text = mat.name .. " +" .. math.floor(amt),
                fontSize = 10,
                fontColor = mat.color,
            })
        end
    end
    if hasAnyMat then
        table.insert(children, UI.Label {
            text = "-- 剩余材料 --",
            fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4,
        })
        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 6, justifyContent = "center",
            flexWrap = "wrap", children = matLabels,
        })
    end

    -- 制作的商品
    local hasCraft = false
    local craftLabels = {}
    if earnings.crafted then
        for prodId, count in pairs(earnings.crafted) do
            if count > 0 then
                hasCraft = true
                local prodCfg = Config.GetProductById(prodId)
                table.insert(craftLabels, UI.Label {
                    text = (prodCfg and prodCfg.name or prodId) .. " x" .. count,
                    fontSize = 10,
                    fontColor = Config.Colors.blue,
                })
            end
        end
    end
    if hasCraft then
        table.insert(children, UI.Label {
            text = "-- 自动制作 --",
            fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4,
        })
        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 6, justifyContent = "center",
            flexWrap = "wrap", children = craftLabels,
        })
    end

    -- 售卖灵石
    if earnings.soldCount and earnings.soldCount > 0 then
        table.insert(children, UI.Label {
            text = "-- 自动售卖 --",
            fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4,
        })
        table.insert(children, UI.Label {
            text = "售出 " .. earnings.soldCount .. " 件, 获得灵石 " .. math.floor(earnings.lingshi or 0),
            fontSize = 11,
            fontColor = Config.Colors.textGold,
        })
    end

    -- 未售出商品(将入库)
    local hasUnsold = false
    if earnings.unsold then
        for _, count in pairs(earnings.unsold) do
            if count > 0 then hasUnsold = true; break end
        end
    end
    if hasUnsold then
        local unsoldLabels = {}
        for prodId, count in pairs(earnings.unsold) do
            if count > 0 then
                local prodCfg = Config.GetProductById(prodId)
                table.insert(unsoldLabels, UI.Label {
                    text = (prodCfg and prodCfg.name or prodId) .. " x" .. count,
                    fontSize = 10, fontColor = Config.Colors.jade,
                })
            end
        end
        table.insert(children, UI.Label {
            text = "-- 未售出(入库) --",
            fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4,
        })
        table.insert(children, UI.Panel {
            flexDirection = "row", gap = 6, justifyContent = "center",
            flexWrap = "wrap", children = unsoldLabels,
        })
    end

    -- 广告延长提示
    if adWatched < adMax then
        table.insert(children, UI.Label {
            text = "看广告可延长离线时长 (" .. adWatched .. "/" .. adMax .. ")",
            fontSize = 10, fontColor = Config.Colors.purple, marginTop = 6,
        })
    end

    return UI.Panel {
        width = "100%", alignItems = "center", padding = 10, gap = 4,
        children = children,
    }
end

---@param earnings table
local function showOfflineModal(earnings)
    local adExtend, adMax = GameCore.GetOfflineAdExtend()
    local adWatched = math.min(State.state.offlineAdExtend or 0, adMax)
    local offlineRawSeconds = earnings._rawSeconds or 0

    local modal = UI.Modal {
        title = "离线收益",
        size = "sm",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
        onClose = function(self)
            self:Destroy()
        end,
    }

    --- 刷新弹窗内容(广告延长后重新计算)
    local contentSlot = nil
    local footerSlot = nil
    local doubleAdDone = false  -- 双倍广告是否已观看

    local function refreshModal()
        local capSeconds = GameCore.GetOfflineBaseCap() + adWatched * adExtend
        local newEarnings = GameCore.CalculateOfflineEarnings(offlineRawSeconds, capSeconds)
        if not newEarnings then return end
        newEarnings._rawSeconds = offlineRawSeconds
        earnings = newEarnings

        -- 重建内容
        if contentSlot then contentSlot:Destroy() end
        contentSlot = buildOfflineContentPanel(earnings, adWatched, adMax)
        modal:AddContent(contentSlot)

        -- 重建底部
        local footerChildren = {}
        -- 看广告延长按钮
        if adWatched < adMax then
            table.insert(footerChildren, UI.Button {
                text = "+1小时(" .. (adMax - adWatched) .. ")",
                fontSize = 11,
                width = 80, height = 32,
                backgroundColor = Config.Colors.purple,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    Ad.ShowRewardAd(function()
                        adWatched = adWatched + 1
                        State.state.offlineAdExtend = adWatched
                        refreshModal()
                    end, "offline_extend")
                end,
            })
        end
        -- 领取按钮
        local claimBtnSt = nil
        claimBtnSt = UI.Button {
            text = doubleAdDone and "领取双倍" or "领取",
            fontSize = 12,
            width = doubleAdDone and 80 or 68, height = 34,
            backgroundColor = doubleAdDone and Config.Colors.purpleDark or Config.Colors.jadeDark,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 8,
            onClick = function(self)
                local mul = doubleAdDone and 2 or 1
                GameCore.ApplyOfflineEarnings(earnings, mul)
                State.state.offlineAdExtend = 0
                if doubleAdDone then
                    GameCore.AddLog("离线双倍灵石已领取!", Config.Colors.textGold)
                    Tutorial.CompleteOfflineStep()
                else
                    GameCore.AddLog("离线收益已领取", Config.Colors.textGold)
                end
                modal:Close()
                refreshCurrentPage()
            end,
        }
        table.insert(footerChildren, claimBtnSt)
        -- 双倍灵石按钮已隐藏(暂不开放广告双倍功能)
        if footerSlot then footerSlot:Destroy() end
        footerSlot = UI.Panel {
            flexDirection = "row", justifyContent = "center",
            gap = 8, width = "100%",
            children = footerChildren,
        }
        modal:SetFooter(footerSlot)
    end

    refreshModal()
    modal:Open()
end

--- 显示服务端计算的离线收益弹窗
---@param offlineData table 服务端传来的离线数据
local function showServerOfflineModal(offlineData)
    -- 防重复弹窗: 一次会话只弹一次
    if offlineModalShown_ then
        print("[Offline-Diag] showServerOfflineModal SKIPPED (already shown this session)")
        return
    end
    offlineModalShown_ = true
    offlineFallbackTimer_ = nil  -- 取消兜底定时器
    print("[Offline-Diag] showServerOfflineModal CALLED! minutes=" .. tostring(offlineData.minutes)
        .. " hasEarnings=" .. tostring(offlineData.hasEarnings))
    local modal = UI.Modal {
        title = "离线收益",
        size = "sm",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
        onClose = function(self) self:Destroy() end,
    }

    local children = {}
    table.insert(children, UI.Label {
        text = "你离开了 " .. (offlineData.minutes or 0) .. " 分钟",
        fontSize = 12, fontColor = Config.Colors.textPrimary,
    })

    -- 材料
    if offlineData.materials then
        local matLabels = {}
        for matId, amt in pairs(offlineData.materials) do
            if amt > 0 then
                local mat = Config.GetMaterialById(matId)
                table.insert(matLabels, UI.Label {
                    text = (mat and mat.name or matId) .. " +" .. math.floor(amt),
                    fontSize = 10, fontColor = mat and mat.color or Config.Colors.textPrimary,
                })
            end
        end
        if #matLabels > 0 then
            table.insert(children, UI.Label { text = "-- 剩余材料 --", fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4 })
            table.insert(children, UI.Panel { flexDirection = "row", gap = 6, justifyContent = "center", flexWrap = "wrap", children = matLabels })
        end
    end

    -- 制作
    if offlineData.crafted then
        local craftLabels = {}
        for prodId, count in pairs(offlineData.crafted) do
            if count > 0 then
                local prod = Config.GetProductById(prodId)
                table.insert(craftLabels, UI.Label { text = (prod and prod.name or prodId) .. " x" .. count, fontSize = 10, fontColor = Config.Colors.blue })
            end
        end
        if #craftLabels > 0 then
            table.insert(children, UI.Label { text = "-- 自动制作 --", fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4 })
            table.insert(children, UI.Panel { flexDirection = "row", gap = 6, justifyContent = "center", flexWrap = "wrap", children = craftLabels })
        end
    end

    -- 售卖灵石
    if (offlineData.soldCount or 0) > 0 then
        table.insert(children, UI.Label { text = "-- 自动售卖 --", fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 4 })
        table.insert(children, UI.Label {
            text = "售出 " .. offlineData.soldCount .. " 件, 获得灵石 " .. math.floor(offlineData.lingshi or 0),
            fontSize = 11, fontColor = Config.Colors.textGold,
        })
    end

    -- 灵童工作详情
    local sInfo = offlineData.servantInfo
    if sInfo then
        table.insert(children, UI.Label { text = "-- 灵童工作 --", fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 6 })
        table.insert(children, UI.Label {
            text = sInfo.name .. "  工作 " .. (sInfo.minutes or 0) .. " 分钟",
            fontSize = 11, fontColor = Config.Colors.jade,
        })
        if sInfo.speedBonus and sInfo.speedBonus > 0 then
            table.insert(children, UI.Label {
                text = "加速 +" .. math.floor(sInfo.speedBonus * 100) .. "%",
                fontSize = 10, fontColor = Config.Colors.green,
            })
        end
        if sInfo.yields and next(sInfo.yields) then
            local yieldLabels = {}
            for matId, amount in pairs(sInfo.yields) do
                if amount > 0 then
                    local mat = Config.GetMaterialById(matId)
                    local matName = mat and mat.name or matId
                    local matColor = mat and mat.color or Config.Colors.textGreen
                    table.insert(yieldLabels, UI.Label {
                        text = matName .. " +" .. amount,
                        fontSize = 10, fontColor = matColor,
                    })
                end
            end
            if #yieldLabels > 0 then
                table.insert(children, UI.Panel {
                    flexDirection = "row", gap = 6, justifyContent = "center", flexWrap = "wrap",
                    children = yieldLabels,
                })
            end
        end
    end

    -- 傀儡工作详情
    local pInfo = offlineData.puppetInfo
    if pInfo then
        table.insert(children, UI.Label { text = "-- 傀儡工作 --", fontSize = 10, fontColor = Config.Colors.textSecond, marginTop = 6 })
        table.insert(children, UI.Label {
            text = pInfo.name .. "  工作 " .. (pInfo.minutes or 0) .. " 分钟",
            fontSize = 11, fontColor = Config.Colors.purple,
        })
        if pInfo.products and #pInfo.products > 0 then
            local prodText = "指定制作: " .. table.concat(pInfo.products, ", ")
            table.insert(children, UI.Label {
                text = prodText, fontSize = 10, fontColor = Config.Colors.blue,
            })
        end
    end

    local screenH = graphics:GetHeight() / graphics:GetDPR()
    local scrollMaxH = math.floor(screenH * 0.45)
    modal:AddContent(UI.ScrollView {
        scrollY = true, showScrollbar = false,
        width = "100%", maxHeight = scrollMaxH,
        children = {
            UI.Panel {
                width = "100%", alignItems = "center", padding = 10, gap = 4,
                paddingBottom = 150,
                children = children,
            },
        },
    })

    local doubleAdDone = false  -- 标记双倍广告是否已观看

    local function rebuildServerFooter()
        local footerChildren = {}
        -- 领取按钮（发送 GameAction）
        table.insert(footerChildren, UI.Button {
            text = doubleAdDone and "领取双倍" or "领取",
            fontSize = 12,
            width = doubleAdDone and 80 or 68, height = 34,
            backgroundColor = doubleAdDone and Config.Colors.purpleDark or Config.Colors.jadeDark,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 8,
            onClick = function(self)
                local mul = doubleAdDone and 2 or 1
                GameCore.SendGameAction("claim_offline", { doubleMul = mul })
                -- 清除离线数据备份, 防止兜底定时器重复弹窗
                if ClientNet.ClearOfflineBackup then ClientNet.ClearOfflineBackup() end
                if doubleAdDone then
                    GameCore.AddLog("离线双倍灵石已领取!", Config.Colors.textGold)
                    Tutorial.CompleteOfflineStep()
                else
                    GameCore.AddLog("离线收益已领取", Config.Colors.textGold)
                end
                modal:Close()
                refreshCurrentPage()
            end,
        })
        -- 双倍灵石按钮已隐藏(暂不开放广告双倍功能)
        modal:SetFooter(UI.Panel {
            flexDirection = "row", justifyContent = "center", gap = 8, width = "100%",
            children = footerChildren,
        })
    end

    rebuildServerFooter()
    modal:Open()
end

--- 检查并显示离线收益
local function checkOfflineEarnings(source)
    source = source or "unknown"
    print("[Offline-Diag] checkOfflineEarnings(" .. source .. "): serverMode=" .. tostring(State.serverMode)
        .. " pendingOffline_=" .. tostring(ClientNet.pendingOffline_ ~= nil)
        .. " alreadyShown=" .. tostring(offlineModalShown_))
    -- 已弹过就跳过
    if offlineModalShown_ then
        -- 消费掉残留的 pendingOffline_ 防止重复触发
        if ClientNet.pendingOffline_ then ClientNet.TakePendingOffline() end
        return
    end
    -- 服务端权威模式: 使用服务端计算的离线数据
    if State.serverMode then
        local offlineData = ClientNet.TakePendingOffline()
        print("[Offline-Diag] TakePendingOffline(" .. source .. "): hasData=" .. tostring(offlineData ~= nil)
            .. (offlineData and (" hasEarnings=" .. tostring(offlineData.hasEarnings)
                .. " offlineSec=" .. tostring(offlineData.offlineSeconds)) or ""))
        if offlineData then
            showServerOfflineModal(offlineData)
        end
        return
    end

    -- 单机模式: 客户端计算
    if State.state.lastSaveTime <= 0 then
        return
    end

    local now = os.time()
    local offlineSeconds = now - State.state.lastSaveTime
    local adExtend, adMax = GameCore.GetOfflineAdExtend()
    local adWatched = math.min(State.state.offlineAdExtend or 0, adMax)
    local capSeconds = GameCore.GetOfflineBaseCap() + adWatched * adExtend
    local earnings = GameCore.CalculateOfflineEarnings(offlineSeconds, capSeconds)

    if earnings then
        earnings._rawSeconds = offlineSeconds
        showOfflineModal(earnings)
    end
end

-- ========== UI 构建 ==========

--- 创建底部 Tab 栏 (竖屏适配: 底部导航栏风格)
---@return table UI.Panel
local function createTabBar()
    local tabChildren = {}

    for _, def in ipairs(TAB_DEFS) do
        local isActive = (def.id == currentTab)
        local btn = UI.Button {
            text = def.label,
            fontSize = 10,
            fontWeight = "bold",
            minWidth = 64,
            paddingHorizontal = 14,
            height = 34,
            borderRadius = 0,
            backgroundColor = isActive and tabActiveColor or tabNormalColor,
            textColor = isActive and tabActiveText or tabNormalText,
            onClick = function(self)
                switchTab(def.id)
            end,
        }
        tabButtons[def.id] = btn
        -- 绑定红点: 仅制作/灵田/角色/聊天需要红点
        if def.id == "craft" or def.id == "field" or def.id == "upgrade" or def.id == "chat" then
            RedDot.Bind(def.id, btn)
        end
        table.insert(tabChildren, btn)
    end

    local sv = UI.ScrollView {
        id = "tab_bar",
        width = "100%",
        height = 46,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        borderTopWidth = 1,
        borderColor = Config.Colors.border,
        backgroundColor = tabNormalColor,
        paddingTop = 8,
        paddingBottom = 4,
        children = {
            UI.Panel {
                flexDirection = "row",
                height = "100%",
                children = tabChildren,
            },
        },
    }
    -- PC端: 垂直滚轮 → 水平滚动
    local origOnWheel = sv.OnWheel
    sv.OnWheel = function(self, dx, dy)
        origOnWheel(self, dx + dy, 0)
    end
    return sv
end

---@return table UI.Panel
local function createPageContainer()
    local stallPage = Stall.Create()
    local craftPage = Craft.Create()
    local fieldPage = FieldUI.Create()
    local upgradePage = Upgrade.Create()
    local adPage = Ad.Create()

    craftPage:Hide()
    fieldPage:Hide()
    upgradePage:Hide()
    adPage:Hide()

    -- 隐藏页面必须从 Yoga 布局中移除，否则仍占据空间导致事件错乱
    YGNodeStyleSetDisplay(craftPage.node, YGDisplayNone)
    YGNodeStyleSetDisplay(fieldPage.node, YGDisplayNone)
    YGNodeStyleSetDisplay(upgradePage.node, YGDisplayNone)
    YGNodeStyleSetDisplay(adPage.node, YGDisplayNone)

    local chatPage = Chat.Create()
    chatPage:Hide()
    YGNodeStyleSetDisplay(chatPage.node, YGDisplayNone)

    tabPages.stall = stallPage
    tabPages.craft = craftPage
    tabPages.field = fieldPage
    tabPages.upgrade = upgradePage
    tabPages.ad = adPage
    tabPages.chat = chatPage

    local pageChildren = {
        stallPage,
        craftPage,
        fieldPage,
        upgradePage,
        adPage,
        chatPage,
    }

    -- GM 页面(始终创建, 延迟到lobby就绪后判断是否显示)
    local gmPage = GM.Create()
    gmPage:Hide()
    YGNodeStyleSetDisplay(gmPage.node, YGDisplayNone)
    tabPages.gm = gmPage
    table.insert(pageChildren, gmPage)

    return UI.Panel {
        id = "page_container",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        overflow = "hidden",
        children = pageChildren,
    }
end

-- ========== 快捷工具栏 (HUD 下方, 全局可见) ==========

---@param icon string
---@param label string
---@param color table
---@param onClick function
local function createToolbarBtn(icon, label, color, onClick)
    local btnText = (icon ~= "") and (icon .. " " .. label) or label
    return UI.Button {
        text = btnText,
        fontSize = 8,
        height = 20,
        paddingHorizontal = 6,
        backgroundColor = { 40, 42, 54, 255 },
        textColor = color,
        borderRadius = 12,
        borderWidth = 1,
        borderColor = color,
        onClick = function(self) onClick() end,
    }
end

-- ========== 公告弹窗 ==========
local function showAnnouncementModal()
    local modal = UI.Modal {
        title = "公告",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    local contentLabel = UI.Label {
        text = "加载中...",
        fontSize = 11,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        whiteSpace = "normal",
        width = "100%",
        paddingVertical = 20,
    }

    local timeLabel = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "right",
        width = "100%",
    }
    timeLabel:Hide()

    local contentPanel = UI.Panel {
        width = "100%",
        padding = 12,
        gap = 6,
        children = { contentLabel, timeLabel },
    }

    modal:AddContent(contentPanel)
    modal:Open()

    State.LoadAnnouncement(function(text, time)
        if text then
            contentLabel:SetText(text)
            contentLabel:SetStyle({
                fontColor = Config.Colors.textPrimary,
                textAlign = "left",
                fontSize = 12,
                whiteSpace = "normal",
            })
            if time then
                local timeStr = os.date("!%m/%d %H:%M", time)
                timeLabel:SetText("发布于 " .. timeStr)
                timeLabel:Show()
            end
        else
            contentLabel:SetText("暂无公告")
        end
    end)
end

local function createToolbar()
    local isNetwork = IsNetworkMode and IsNetworkMode()
    local btns = {
        createToolbarBtn("", "排行榜", Config.Colors.purple, function()
            Rank.ShowRankModal()
        end),
        createToolbarBtn("", "兑换码", Config.Colors.gold, function()
            CDK.ShowCDKModal()
        end),
    }

    -- 邮箱按钮(仅多人模式)
    if isNetwork then
        local mailBtn = createToolbarBtn("", "邮箱", Config.Colors.orange, function()
            Mail.ShowMailModal()
        end)
        RedDot.Bind("mail", mailBtn)
        table.insert(btns, mailBtn)
    end

    -- 秘境按钮
    local dungeonBtn = createToolbarBtn("", "秘境", Config.Colors.jade, function()
        Dungeon.Open()
    end)
    RedDot.Bind("dungeon", dungeonBtn)
    table.insert(btns, dungeonBtn)

    table.insert(btns, createToolbarBtn("", "公告", Config.Colors.blue, function()
        showAnnouncementModal()
    end))
    table.insert(btns, createToolbarBtn("", "设置", Config.Colors.textSecond, function()
        Settings.ShowSettingsModal()
    end))

    -- GM 按钮(始终创建, 延迟显示)
    gmBtnRef_ = createToolbarBtn("", "GM", Config.Colors.red, function()
        switchTab("gm")
    end)
    gmBtnRef_:Hide()
    table.insert(btns, gmBtnRef_)

    local sv = UI.ScrollView {
        id = "toolbar",
        width = "100%",
        height = 24,
        scrollX = true,
        scrollY = false,
        showScrollbar = false,
        backgroundColor = Config.Colors.panel,
        borderBottomWidth = 1,
        borderColor = Config.Colors.border,
        children = {
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 4,
                paddingHorizontal = 6,
                paddingVertical = 2,
                height = "100%",
                children = btns,
            },
        },
    }
    -- PC端: 垂直滚轮 → 水平滚动（标准鼠标只产生 dy，横向 ScrollView 默认无法滚轮滚动）
    local origOnWheel = sv.OnWheel
    sv.OnWheel = function(self, dx, dy)
        origOnWheel(self, dx + dy, 0)
    end
    return sv
end

--- 竖屏布局: HUD → 工具栏 → 内容 → 引导条 → 日志条 → 底部Tab
local function buildUI()
    -- 先创建开始界面覆盖层(absolute定位, zIndex=900)
    -- 必须在 SetRoot 之前一起传入, 避免首帧闪烁游戏主界面
    local startPanel = StartScreen.Create(function()
        -- 点击"进入游戏"后执行
        enterGameFromStart()
    end)

    uiRoot_ = UI.SafeAreaView {
        id = "root",
        width = "100%",
        height = "100%",
        backgroundColor = Config.Colors.bg,
        children = {
            HUD.Create(),
            createToolbar(),
            createPageContainer(),
            Tutorial.Create(),
            Chat.CreateLogBar(),
            createTabBar(),
            startPanel,  -- 开始界面作为最后一个子元素, absolute+zIndex=900 覆盖在最上层
        },
    }
    UI.SetRoot(uiRoot_)

    -- 设置区服选择插槽(仅多人模式下嵌入)
    if IsNetworkMode and IsNetworkMode() then
        ServerSelect.SetupStartScreenSlot(StartScreen.GetServerSlot())
    end

    -- 初始化新手引导系统
    Guide.Setup({
        container = uiRoot_,
        tabButtons = tabButtons,
        switchTab = switchTab,
    })

    -- 注入 overlay 挂载容器（讨价还价、每日任务弹窗需要挂载到 UI 根节点）
    Bargain.SetContainer(uiRoot_)
    Daily.SetContainer(uiRoot_)
    Dungeon.SetContainer(uiRoot_)
    Dujie.SetContainer(uiRoot_)
    Dujie.Init()
    -- 渡劫 Boss 战 UI (功能10): 注册事件监听
    Tribulation.SetContainer(uiRoot_)
    Tribulation.Init()
end

-- ========== 新手礼包弹窗 ==========

local function showNewbieGiftModal()
    local gift = Config.NewbieGift

    -- 构建奖励列表
    local rewardLabels = {}
    table.insert(rewardLabels, UI.Label {
        text = "+" .. gift.lingshi .. " 灵石",
        fontSize = 14,
        fontColor = Config.Colors.textGold,
        fontWeight = "bold",
    })
    if gift.xiuwei and gift.xiuwei > 0 then
        table.insert(rewardLabels, UI.Label {
            text = "+" .. gift.xiuwei .. " 修为",
            fontSize = 11,
            fontColor = Config.Colors.purple,
        })
    end
    for matId, amt in pairs(gift.materials) do
        local mat = Config.GetMaterialById(matId)
        if mat then
            table.insert(rewardLabels, UI.Label {
                text = "+" .. amt .. " " .. mat.name,
                fontSize = 11,
                fontColor = mat.color,
            })
        end
    end
    for prodId, amt in pairs(gift.products) do
        local prod = Config.GetProductById(prodId)
        if prod then
            table.insert(rewardLabels, UI.Label {
                text = "+" .. amt .. " " .. prod.name,
                fontSize = 11,
                fontColor = prod.color,
            })
        end
    end

    local modal = UI.Modal {
        title = "新手礼包",
        size = "sm",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
        onClose = function(self) self:Destroy() end,
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        alignItems = "center",
        padding = 12,
        gap = 6,
        children = {
            UI.Label {
                text = "欢迎来到修仙界!",
                fontSize = 13,
                fontColor = Config.Colors.textPrimary,
            },
            UI.Label {
                text = "领取新手礼包，开启修仙之旅",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
            },
            UI.Panel {
                gap = 3,
                alignItems = "center",
                paddingVertical = 6,
                children = rewardLabels,
            },
        },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "领取礼包",
                fontSize = 13,
                width = 120,
                height = 36,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    if State.serverMode then
                        -- 服务端权威模式: 发送 GameAction
                        GameCore.SendGameAction("newbie_gift")
                    else
                        -- 单机模式: 本地发放奖励
                        State.AddLingshi(gift.lingshi)
                        if gift.xiuwei then State.AddXiuwei(gift.xiuwei) end
                        for matId, amt in pairs(gift.materials) do
                            State.AddMaterial(matId, amt)
                        end
                        for prodId, amt in pairs(gift.products) do
                            State.AddProduct(prodId, amt)
                        end
                        State.state.newbieGiftClaimed = true
                        GameCore.AddLog("新手礼包已领取!", Config.Colors.textGold)
                        State.Save()
                    end
                    modal:Close()
                    refreshCurrentPage()
                    -- 领取礼包后触发新手引导
                    if not State.state.guideCompleted then
                        Guide.Start()
                    end
                end,
            },
        },
    })

    modal:Open()
end

-- ========== BGM 播放 ==========

local function startBGM()
    if bgmSource_ then return end
    local bgmSound = cache:GetResource("Sound", Config.BGM)
    if not bgmSound then
        print("[Main] BGM resource not found: " .. Config.BGM)
        return
    end
    bgmSound.looped = true
    bgmNode_ = scene_:CreateChild("BGM")
    bgmSource_ = bgmNode_:CreateComponent("SoundSource")
    bgmSource_.soundType = "Music"
    bgmSource_.gain = 0.35
    bgmSource_:Play(bgmSound)
    print("[Main] BGM started")

    -- 注入 BGM 引用给 Settings 模块
    Settings.SetBGMSource(bgmSource_)
end

-- ========== 事件监听 ==========

local function registerStateEvents()
    State.On("stall_upgrade", function(newLevel)
        GameCore.AddLog("摊位升至 Lv." .. newLevel .. "!", Config.Colors.textGold)
        GameCore.PlaySFX("upgrade")
        refreshCurrentPage()
    end)

    State.On("realm_up", function(realmIdx, realmName)
        GameCore.AddLog("突破至【" .. realmName .. "】!", Config.Colors.purple)
        GameCore.PlaySFX("upgrade")
        refreshCurrentPage()
    end)

    State.On("sale_completed", function(info)
        if info and info.product then
            GameCore.AddLog("售出 " .. info.product.name .. " +" .. info.price .. "灵石",
                Config.Colors.textGreen)
        end
    end)

    -- 讨价还价结果
    State.On("bargain_done", function(data)
        Bargain.ShowResult(data)
        refreshCurrentPage()
    end)

    -- 合成完成
    State.On("synthesize_done", function(data)
        refreshCurrentPage()
    end)

    -- 每日任务领取
    State.On("daily_task_claimed", function(data)
        Daily.Refresh()
        refreshCurrentPage()
    end)

    -- 逆活一世: 5%概率续命
    State.On("lifespan_miracle", function()
        GameCore.AddLog("误入禁地, 意外获得续命神药! 延寿百年!", Config.Colors.textGold)
        GameCore.PlaySFX("encounter")
        -- 弹窗提示
        local modal = UI.Modal {
            title = "逆活一世",
            size = "sm",
            closeOnOverlay = true,
            onClose = function(self) self:Destroy() end,
        }
        modal:AddContent(UI.Panel {
            width = "100%",
            alignItems = "center",
            padding = 16,
            gap = 10,
            children = {
                UI.Label {
                    text = "大难不死!",
                    fontSize = 16,
                    fontColor = Config.Colors.textGold,
                    fontWeight = "bold",
                },
                UI.Label {
                    text = "寿元将尽之际，误闯上古禁地，\n意外寻得一枚续命神药!",
                    fontSize = 12,
                    fontColor = Config.Colors.textPrimary,
                    textAlign = "center",
                },
                UI.Label {
                    text = "延寿 100 年",
                    fontSize = 14,
                    fontColor = Config.Colors.orange,
                    fontWeight = "bold",
                },
            },
        })
        modal:SetFooter(UI.Panel {
            width = "100%",
            alignItems = "center",
            children = {
                UI.Button {
                    text = "天命不绝!",
                    fontSize = 12,
                    width = 120,
                    height = 34,
                    backgroundColor = Config.Colors.goldDark,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 8,
                    onClick = function(self)
                        modal:Close()
                    end,
                },
            },
        })
        modal:Open()
        refreshCurrentPage()
    end)

    -- 陨落事件: 寿元归零
    State.On("player_dead", function()
        -- 开始界面可见时跳过弹窗, 进入游戏后由 onEnterAfterLoad_continue 检测 dead 状态处理
        if StartScreen.IsVisible() then return end
        GameCore.AddLog("寿元耗尽, 道消身陨...", Config.Colors.red)
        State.Save()
        -- 弹出陨落/转生界面(serverMode下回调不使用, 转生由服务端处理)
        Rebirth.ShowDeathModal(function(summary)
            -- 仅单机模式走此回调(serverMode在rebirth_done事件中处理)
            GameCore.OnRebirth()
            GameCore.AddLog("第" .. summary.newRebirthCount .. "世开始! 收益加成+"
                .. math.floor((State.GetRebirthBonus() - 1) * 100) .. "%",
                Config.Colors.purple)
            switchTab("stall")
            refreshCurrentPage()
        end)
    end)

    -- 服务端转生完成事件: 刷新客户端UI
    State.On("rebirth_done", function(data)
        GameCore.OnRebirth()
        switchTab("stall")
        refreshCurrentPage()
    end)

    -- 渡劫 Boss 战面板关闭: 刷新升级页(更新按钮状态)
    State.On("tribulation_panel_closed", function()
        refreshCurrentPage()
    end)

    -- 升级页刷新请求(飞升成功后触发)
    State.On("upgrade_panel_refresh", function()
        refreshCurrentPage()
    end)

    -- 飞升成功: 切换到摊位页并刷新
    State.On("ascended", function()
        refreshCurrentPage()
    end)
end

-- ========== 云加载回调 ==========

-- 探针是否已收到响应(防止 ok/error 和 timeout 重复触发)
local probeResponded = false

-- 前置声明(startProbe 和 onProbeOrLoadFailed 互相引用, onEnterAfterLoad 供换服回调使用)
local startProbe
local onProbeOrLoadFailed
local onEnterAfterLoad

--- 检测 clientCloud 是否已就绪（参考问道长生 IsCloudReady）
---@return boolean
local function IsCloudReady()
    ---@diagnostic disable-next-line: undefined-global
    if clientCloud ~= nil then return true end
    ---@diagnostic disable-next-line: undefined-global
    if clientScore ~= nil then
        ---@diagnostic disable-next-line: undefined-global
        clientCloud = clientScore
        print("[Main] clientScore -> clientCloud fallback")
        return true
    end
    -- 网络模式下尝试注入 polyfill
    if IsNetworkMode and IsNetworkMode() and network.serverConnection then
        local cnet = require("network.client_net")
        if not cnet.IsPolyfill() then
            cnet.InjectPolyfill()
        end
        ---@diagnostic disable-next-line: undefined-global
        return clientCloud ~= nil
    end
    return false
end

--- 更新加载遮罩文字（使用 NanoVG Loading 遮罩）
---@param text string
---@param color? table  -- 已弃用，NanoVG 遮罩有统一配色
local function setLoadingText(text, color)
    -- Loading 遮罩显示中时更新文字；未显示则启动
    Loading.ShowNow(text)
end

--- 发起探针请求: 用轻量 Get 测试云端连接是否真正可用
startProbe = function()
    -- ========== 服务端权威模式: 等待 GameInit 事件 ==========
    if State.serverMode then
        print("[Main] startProbe: serverMode=true, gameInitReceived=" .. tostring(ClientNet.IsGameInitReceived())
            .. ", connected=" .. tostring(ClientNet.IsConnected and ClientNet.IsConnected() or "N/A"))
        -- 如果已收到 GameInit（连接快时可能在 startProbe 前就到了）
        if ClientNet.IsGameInitReceived() then
            print("[Main] GameInit already received, entering game")
            onCloudLoaded(true)
            return
        end
        loadState = "wait_connection"
        setLoadingText("正在连接游戏服务器...")
        print("[Main] 服务端权威模式，等待 GameInit 事件... (注册回调)")
        -- 注册回调：GameInit 到达时触发
        ClientNet.OnGameInit(function()
            print("[Main] GameInit received via callback, entering game")
            onCloudLoaded(true)
        end)
        -- 注册换服回调：切换区服后重新走入口流程(角色创建/剧情等)
        ClientNet.OnServerSwitch(function()
            print("[Main] Server switch detected, re-entering game flow")
            -- 如果开始界面还在显示, 不立即执行, 等用户点"进入游戏"按钮后走 enterGameFromStart
            -- pendingOffline_ 已由 HandleGameInit 更新, enterGameFromStart 会读取
            if StartScreen.IsVisible() then
                print("[Main] 开始界面可见, 等待用户点击进入游戏 (pendingOffline="
                    .. tostring(ClientNet.pendingOffline_ ~= nil) .. ")")
                return
            end
            -- 🔴 双保险: 已进入游戏后收到迟到的带离线数据的 GameInit
            -- 直接补弹离线弹窗, 不重走完整入口流程(避免重复初始化副作用)
            if ClientNet.pendingOffline_ then
                print("[Main] Server switch: 已在游戏中, 补弹离线收益")
                checkOfflineEarnings("onServerSwitch")
                return
            end
            onEnterAfterLoad()
        end)
        return
    end

    -- ========== 单机模式: 原有探针逻辑 ==========
    -- 后台匹配模式下 clientCloud 可能还没就绪，轮询等待
    if not IsCloudReady() then
        loadState = "wait_connection"
        setLoadingText("正在连接服务器...")
        print("[Main] clientCloud 尚未就绪，等待轮询...")
        return
    end
    loadState = "probe"
    cloudLoadTimer = 0
    probeResponded = false

    setLoadingText("正在连接云端服务...")

    print("[Main] Probe #" .. (retryCount + 1) .. " sending lightweight Get...")

    -- 轻量探针: 只请求一个 key, 验证连接是否真正可用
    clientCloud:Get("lingshi", {
        ok = function(values, iscores)
            if probeResponded then return end
            probeResponded = true
            print("[Main] Probe OK! Connection is alive, loading full data...")
            -- 探测通过, 立即加载完整数据
            loadState = "loading"
            cloudLoadTimer = 0
            setLoadingText("正在加载云端存档...")
            State.Load(onCloudLoaded)
        end,
        error = function(code, reason)
            if probeResponded then return end
            probeResponded = true
            print("[Main] Probe error: code=" .. tostring(code) .. " reason=" .. tostring(reason))
            -- error 说明连接是通的(服务器回了响应), 也可以继续加载
            loadState = "loading"
            cloudLoadTimer = 0
            setLoadingText("正在加载云端存档...")
            State.Load(onCloudLoaded)
        end,
        timeout = function()
            if probeResponded then return end
            probeResponded = true
            print("[Main] Probe timeout — connection not available")
            onProbeOrLoadFailed()
        end,
    })
end

--- 探针或加载失败后的统一处理
onProbeOrLoadFailed = function()
    retryCount = retryCount + 1
    if retryCount < MAX_AUTO_RETRIES then
        -- 自动重试
        loadState = "wait_retry"
        cloudLoadTimer = 0
        setLoadingText("正在连接云端服务...")
        print("[Main] Will retry in " .. AUTO_RETRY_DELAY .. "s (attempt " .. retryCount .. "/" .. MAX_AUTO_RETRIES .. ")")
    else
        -- 5次全部失败
        loadState = "failed"
        setLoadingText("云端连接失败, 请检查网络后重试")
        print("[Main] All " .. MAX_AUTO_RETRIES .. " retries exhausted")
    end
end

--- 手动重试(重置计数器)
local function manualRetry()
    retryCount = 0
    startProbe()
end

--- 云存档加载完成后 — 剧情/陨落/正常进入的后续流程
local function onEnterAfterLoad_continue()
    print("[Offline-Diag] onEnterAfterLoad_continue: storyPlayed=" .. tostring(State.state.storyPlayed)
        .. " dead=" .. tostring(State.state.dead) .. " pendingOffline=" .. tostring(ClientNet.pendingOffline_ ~= nil)
        .. " alreadyShown=" .. tostring(offlineModalShown_))
    -- 🔴 离线收益: 无论走哪个分支都先检查(剧情/陨落分支以前会跳过导致离线弹窗丢失)
    -- 先弹离线弹窗, 后续流程在弹窗关闭/领取后不受影响
    if ClientNet.pendingOffline_ then
        print("[Offline-Diag] onEnterAfterLoad_continue: 提前检查离线收益(防分支遗漏)")
        checkOfflineEarnings("onEnterAfterLoad_continue")
    end
    -- 兜底定时器已在 enterGameFromStart / onEnterAfterLoad 中提前启动
    -- 此处仅重置倒计时(给更多时间等待 pendingOffline_ 到达)
    if not offlineModalShown_ and offlineFallbackTimer_ then
        offlineFallbackTimer_ = OFFLINE_FALLBACK_DELAY
    end

    -- 首次进入: 播放剧情
    if not State.state.storyPlayed then
        Log.ShowStory(function()
            -- 标记剧情已播放
            State.state.storyPlayed = true
            if State.serverMode then
                GameCore.SendGameAction("story_played")
            end
            GameCore.AddLog("欢迎来到修仙界, 开始你的摆摊之旅!", Config.Colors.textGold)
            refreshCurrentPage()
            if not State.state.newbieGiftClaimed then
                showNewbieGiftModal()
                -- 引导在礼包领取后触发
            elseif not State.state.guideCompleted then
                Guide.Start()
            end
            State.Save()
        end)
    elseif State.state.dead then
        -- 上次陨落后未转生就退出, 重新弹出陨落界面
        GameCore.AddLog("你的肉身已陨...", Config.Colors.red)
        Rebirth.ShowDeathModal(function(summary)
            -- 仅单机模式走此回调(serverMode在rebirth_done事件中处理)
            GameCore.OnRebirth()
            GameCore.AddLog("第" .. summary.newRebirthCount .. "世开始! 收益加成+"
                .. math.floor((State.GetRebirthBonus() - 1) * 100) .. "%",
                Config.Colors.purple)
            switchTab("stall")
            refreshCurrentPage()
        end)
    else
        GameCore.AddLog("云端存档已加载, 继续修仙之路...", Config.Colors.textSecond)
        -- 离线收益已在上方统一检查, 此处不再重复调用
        -- 客户端侧防御: 转世玩家必定已完成引导(兜底服务端迁移)
        if not State.state.guideCompleted and (State.state.rebirthCount or 0) >= 1 then
            State.state.guideCompleted = true
            print("[Main] 客户端兜底修复guideCompleted: rebirthCount=" .. tostring(State.state.rebirthCount))
        end
        -- 老用户回登: 引导未完成则恢复引导
        if not State.state.guideCompleted then
            Guide.Start()
        end
        print("[Main] guide=" .. tostring(Guide.IsActive()) .. " gc=" .. tostring(State.state.guideCompleted))
    end

    Tutorial.SetTabSwitcher(switchTab)
    Chat.SetTabSwitcher(switchTab)
    Tutorial.Init()
    refreshCurrentPage()
end

--- 云存档加载完成后的进入逻辑
onEnterAfterLoad = function()
    print("[Offline-Diag] onEnterAfterLoad: hasName=" .. tostring(State.HasPlayerName())
        .. " pendingOffline=" .. tostring(ClientNet.pendingOffline_ ~= nil))
    -- 🔴 确保兜底定时器已启动(onCloudLoaded 可能绕过 enterGameFromStart 直接调此函数)
    if not offlineModalShown_ and not offlineFallbackTimer_ then
        offlineFallbackTimer_ = OFFLINE_FALLBACK_DELAY
        print("[Offline-Diag] 兜底定时器在 onEnterAfterLoad 启动: " .. OFFLINE_FALLBACK_DELAY .. "s")
    end
    -- ===== 版本检查: 低于服务端最低版本号则弹更新提示 =====
    if ClientNet.requiredVersion_ and ClientNet.requiredVersion_ ~= "" then
        local function parseVer(s)
            local parts = {}
            for n in tostring(s):gmatch("%d+") do parts[#parts + 1] = tonumber(n) end
            return parts
        end
        local cur = parseVer(Config.VERSION)
        local req = parseVer(ClientNet.requiredVersion_)
        local needUpdate = false
        for i = 1, math.max(#cur, #req) do
            local c = cur[i] or 0
            local r = req[i] or 0
            if c < r then needUpdate = true; break
            elseif c > r then break end
        end
        if needUpdate then
            -- GM(开发者)跳过强制更新, 仅提示
            if not ClientNet.isDeveloper_ then
                UI.Modal.Show({
                    title = "版本更新",
                    message = "检测到新版本 v" .. ClientNet.requiredVersion_
                        .. "\n当前版本 v" .. Config.VERSION
                        .. "\n\n请关闭TapTap应用后重新打开游戏完成更新",
                    buttons = {},  -- 无按钮, 不可关闭
                    closeOnOverlay = false,
                })
                print("[Main] 版本过低, 阻断进入游戏: cur=" .. Config.VERSION .. " req=" .. ClientNet.requiredVersion_)
                return  -- 阻断后续流程
            else
                print("[Main] GM跳过版本检查: cur=" .. Config.VERSION .. " req=" .. ClientNet.requiredVersion_)
            end
        end
    end

    -- 通知服务端：玩家已点击"进入游戏"，启动游戏逻辑
    if State.serverMode then
        local ok1, err1 = pcall(GameCore.SendGameAction, "game_start", {})
        if not ok1 then print("[Offline-Diag] ERROR game_start: " .. tostring(err1)) end
    end

    -- 初始化邮箱(仅多人模式下有效; 区服已在 Start() 中提前初始化)
    if IsNetworkMode and IsNetworkMode() then
        local ok2, err2 = pcall(function()
            Mail.Init()
            Mail.FetchMails(false)
        end)
        if not ok2 then print("[Offline-Diag] ERROR Mail.Init/FetchMails: " .. tostring(err2)) end
    end

    print("[Offline-Diag] onEnterAfterLoad: 邮箱/game_start完成, 进入角色检查")

    -- 奇遇系统已在 GameCore.Init() 中初始化，此处不再重复调用

    -- 角色创建检查: 没有道号时强制弹出角色创建面板
    -- 创建完成后继续后续流程(剧情/陨落/正常进入)
    if not State.HasPlayerName() then
        CharCreate.Show(function(name, gender)
            GameCore.AddLog("道号【" .. name .. "】已铭刻于仙界!", Config.Colors.textGold)
            onEnterAfterLoad_continue()
        end)
        return
    end

    print("[Offline-Diag] onEnterAfterLoad: hasName=true, 调用 onEnterAfterLoad_continue")
    onEnterAfterLoad_continue()
end

--- 从开始界面进入游戏后执行的逻辑
enterGameFromStart = function()
    print("[Offline-Diag] enterGameFromStart: loadState=" .. tostring(loadState)
        .. " pendingOffline=" .. tostring(ClientNet.pendingOffline_ ~= nil))
    -- 🔴 在最早时机启动兜底定时器, 不依赖 onEnterAfterLoad_continue 能否被调用
    if not offlineModalShown_ and not offlineFallbackTimer_ then
        offlineFallbackTimer_ = OFFLINE_FALLBACK_DELAY
        print("[Offline-Diag] 兜底定时器在 enterGameFromStart 启动: " .. OFFLINE_FALLBACK_DELAY .. "s")
    end
    -- 延迟转储: 打印 HandleGameInit 期间收集的所有诊断信息(此时调试面板已就绪)
    if ClientNet._offlineDiag and #ClientNet._offlineDiag > 0 then
        for i, d in ipairs(ClientNet._offlineDiag) do
            print("[Offline-Diag] GI#" .. i .. " pending=" .. tostring(d.pendingOffline)
                .. " hasEarn=" .. tostring(d.hasEarnings) .. " offSec=" .. tostring(d.offlineSec))
            print("[Offline-Diag] GI#" .. i .. " isSvrSw=" .. tostring(d.isServerSwitch)
                .. " giRecv=" .. tostring(d.gameInitReceived))
            print("[Offline-Diag] GI#" .. i .. " svr_sid=" .. tostring(d.svr_sid)
                .. " svr_lastSave=" .. tostring(d.svr_lastSave))
            print("[Offline-Diag] GI#" .. i .. " svr_offSec=" .. tostring(d.svr_offlineSec)
                .. " svr_now=" .. tostring(d.svr_now))
            print("[Offline-Diag] GI#" .. i .. " raw=" .. tostring(d.offlineJsonRaw))
        end
        ClientNet._offlineDiag = {}  -- 打印后清空
    else
        print("[Offline-Diag] 无 GameInit 诊断记录(HandleGameInit 可能未触发)")
    end
    if loadState == "done" then
        -- 云端已就绪, 直接进入游戏
        onEnterAfterLoad()
        return
    end

    -- 云端尚未就绪, 显示 NanoVG 加载遮罩等待
    if loadState == "loading" then
        Loading.ShowNow("正在加载云端存档...")
    elseif loadState == "wait_retry" then
        Loading.ShowNow("正在连接云端服务...")
    elseif loadState == "failed" then
        -- 已彻底失败, 重新开始探针
        manualRetry()
    else
        Loading.ShowNow("正在连接云端服务...")
    end
end

--- 尝试关闭加载遮罩（云存档 + 区服列表都就绪才关闭）
function TryDismissLoading()
    if loadState ~= "done" then return end
    -- 联网模式下需要等区服列表到达
    if IsNetworkMode and IsNetworkMode() and not ServerSelect.IsLoaded() then
        Loading.ShowNow("正在获取区服列表...")
        return
    end
    Loading.Stop()
end

---@param success boolean
function onCloudLoaded(success)
    if loadState == "done" then
        return
    end

    if success then
        loadState = "done"

        -- 关闭加载遮罩：需要等区服列表也加载完成（联网模式下）
        TryDismissLoading()

        -- 恢复制作队列
        GameCore.RestoreCraftQueue()

        -- 启动背景音乐
        startBGM()

        -- 恢复音频设置(BGM/SFX 开关)
        Settings.RestoreSettings()

        -- 如果用户已点过"进入游戏"(开始界面已隐藏), 立即进入
        -- 否则保持开始界面可见, 等用户点击"进入游戏"按钮
        if not StartScreen.IsVisible() then
            onEnterAfterLoad()
        end
        -- 开始界面可见时, 等用户点击按钮后走 enterGameFromStart
    else
        print("[Main] Cloud data load failed")
        onProbeOrLoadFailed()
    end
end

-- ========== 生命周期 ==========

function Start()
    graphics.windowTitle = "渡劫摆摊传"

    -- 创建音频宿主场景(SFX/BGM 的 SoundSource 需要挂在 Scene 节点上)
    scene_ = Scene()
    scene_:CreateComponent("Octree")

    UI.Init({
        fonts = {
            { family = "sans", weights = {
                normal = "Fonts/MiSans-Regular.ttf",
            } }
        },
        scale = function()
            local dpr = graphics:GetDPR()
            local shortSide = math.min(graphics.width, graphics.height) / dpr
            -- 竖屏手机短边约360-414 CSS px
            -- scale 越大 → 逻辑分辨率越小 → UI元素在屏幕上越大
            if shortSide < 500 then
                return dpr * 1.15  -- 手机: 放大15%让字号清晰可读
            end
            return dpr
        end,
    })

    -- 移动端 ScrollView 触摸滚动降灵敏: 拖拽衰减 + 惯性加速衰减
    do
        local ScrollView = require("urhox-libs/UI/Widgets/ScrollView")
        local TOUCH_SENSITIVITY = 0.60  -- 拖拽距离缩放(1.0=原始, 越小越不灵敏)
        local TOUCH_FRICTION = 0.88     -- 惯性摩擦力(原始0.95, 越小停得越快)

        local origOnPanMove = ScrollView.OnPanMove
        ScrollView.OnPanMove = function(self, event)
            if not self.state.isDragging then return end
            local dx = self.props.scrollX and -event.totalDeltaX * TOUCH_SENSITIVITY or 0
            local dy = self.props.scrollY and -event.totalDeltaY * TOUCH_SENSITIVITY or 0
            self:SetScroll(self.dragStartScrollX_ + dx, self.dragStartScrollY_ + dy)
            self.state.velocityX = -event.deltaX * TOUCH_SENSITIVITY
            self.state.velocityY = -event.deltaY * TOUCH_SENSITIVITY
        end

        local origUpdate = ScrollView.Update
        ScrollView.Update = function(self, dt)
            -- 替换惯性摩擦力: 在 Update 前手动施加更强摩擦
            local state = self.state
            local isDragging = state.isDragging or self.isDraggingScrollbarV_ or self.isDraggingScrollbarH_
            if not isDragging then
                local ratio = TOUCH_FRICTION / 0.95  -- 相对于原始摩擦的补偿
                state.velocityX = state.velocityX * ratio
                state.velocityY = state.velocityY * ratio
            end
            origUpdate(self, dt)
        end
    end

    -- 初始化修仙国风 Toast 并覆盖 UI.Toast.Show
    XToast.Init()
    UI.Toast.Show = function(message, options)
        return XToast.Show(message, options)
    end

    -- 初始化 NanoVG 加载遮罩、重连遮罩和粒子特效
    Loading.Init()
    ReconnectOverlay.Init()
    Particle.Init()

    -- 初始化客户端网络（网络模式下注册远程事件）
    ClientNet.Init()

    -- 检测服务端权威模式（多人 + persistent_world）
    if IsNetworkMode and IsNetworkMode() then
        State.serverMode = true
        print("[Main] 服务端权威模式已启用")
    end

    -- 注册事件(可在加载前)
    registerStateEvents()

    -- 构建 UI(先用默认状态渲染, 开始界面覆盖在最上层)
    buildUI()

    -- 尽早注册 tab 切换回调, 防止 onEnterAfterLoad_continue 分支出错时漏设
    Chat.SetTabSwitcher(switchTab)
    Tutorial.SetTabSwitcher(switchTab)

    -- 初始化区服模块（事件注册由 client_net 统一管理，区服模块自带重试机制）
    if IsNetworkMode and IsNetworkMode() then
        ServerSelect.Init()
        print("[Main] 区服模块已初始化，自动重试拉取由 ServerSelect.Update() 驱动")
    end

    -- 注册断线/重连/被踢回调（网络模式）
    if IsNetworkMode and IsNetworkMode() then
        ClientNet.OnDisconnect(function()
            if ClientNet.IsKicked() then return end
            print("[Main] 检测到断线，显示重连遮罩")
            ReconnectOverlay.Show()
        end)

        -- 重连超时后用户点击重试: 重置遮罩计时, 引擎自动重连机制会持续尝试
        ReconnectOverlay.OnRetry(function()
            print("[Main] 用户触发重连重试...")
            -- 如果已连上但卡在等 GameInit，重发 CLIENT_READY 信号
            if ClientNet.RetryClientReady() then
                print("[Main] 已重发 CLIENT_READY, 等待 GameInit")
            else
                print("[Main] 等待引擎自动重连...")
            end
            -- 不主动 Disconnect: 引擎内部已在高频自动重连
        end)

        ClientNet.OnReconnect(function()
            print("[Main] 重连成功，隐藏遮罩")
            ReconnectOverlay.Hide()
            XToast.Show("已重新连接服务器", { variant = "success" })
            -- 重置广告等待状态(防止 adWaiting_ 卡死阻塞后续广告交互)
            Ad.ResetAdState()
            -- 保底：重连后再发一次 game_start，防止服务端 runtime 重建后 gameStarted=false
            if State.serverMode then
                GameCore.SendGameAction("game_start", {})
            end
            -- 重发未确认的广告奖励(广告已看完但服务端未确认)
            Ad.RetryPendingAdReward()
            -- 重连后强制保存一次数据确保同步
            if loadState == "done" then
                State.Save()
            end
        end)

        ClientNet.OnKicked(function(reason)
            print("[Main] 被踢下线: reason=" .. tostring(reason))
            ReconnectOverlay.Hide()
            local msg = "您的账号已在其他设备登录，当前连接已断开。"
            if reason == "banned" then
                msg = "您的账号已被封禁，无法登录游戏。如有疑问请联系客服。"
            elseif reason ~= "duplicate_login" then
                msg = "您已被服务器断开连接（" .. tostring(reason) .. "）"
            end
            local modal = UI.Modal {
                title = "连接中断",
                size = "sm",
                closeOnOverlay = false,
                closeOnEscape = false,
                showCloseButton = false,
                onClose = function(self) self:Destroy() end,
            }
            modal:AddContent(UI.Panel {
                width = "100%",
                alignItems = "center",
                padding = 16,
                gap = 10,
                children = {
                    UI.Label {
                        text = msg,
                        fontSize = 12,
                        fontColor = Config.Colors.textPrimary,
                        textAlign = "center",
                    },
                },
            })
            modal:SetFooter(UI.Panel {
                width = "100%",
                alignItems = "center",
                children = {
                    UI.Button {
                        text = "知道了",
                        fontSize = 12,
                        width = 100,
                        height = 34,
                        backgroundColor = Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 8,
                        onClick = function(self) modal:Close() end,
                    },
                },
            })
            modal:Open()
        end)

        -- 前后台切换检测（回到前台时若已断线立即显示重连遮罩）
        SubscribeToEvent("InputFocus", "HandleInputFocus")
    end

    -- 在开始界面就发起云端连接，并显示加载遮罩
    Loading.ShowNow("正在连接云端服务...")
    retryCount = 0
    startProbe()

    SubscribeToEvent("Update", "HandleUpdate")

    print("=== 渡劫摆摊传 启动完成 ===")
end

function Stop()
    State.Save()
    UI.Shutdown()
    print("=== 渡劫摆摊传 已退出 ===")
end

-- ========== 前后台切换检测 ==========

function HandleInputFocus(eventType, eventData)
    local focus = eventData["Focus"]:GetBool()
    local minimized = eventData["Minimized"]:GetBool()
    print("[Main] InputFocus: focus=" .. tostring(focus) .. " minimized=" .. tostring(minimized))

    -- 回到前台 → 网络模式下检测连接状态
    if focus and not minimized then
        if IsNetworkMode() and not ClientNet.IsKicked() and loadState == "done" then
            if not ClientNet.IsConnected() then
                -- 连接确实断了，显示重连遮罩等待引擎自动重连
                if not ReconnectOverlay.IsActive() then
                    print("[Main] 前台恢复，连接已断，显示重连遮罩")
                    ReconnectOverlay.Show()
                end
            elseif ReconnectOverlay.IsActive() then
                -- 连接恢复但遮罩还在: 可能是卡在等 GameInit（CLIENT_READY 未发出）
                print("[Main] 前台恢复，连接正常但遮罩仍在，尝试重发 CLIENT_READY")
                if ClientNet.RetryClientReady() then
                    print("[Main] 已重发 CLIENT_READY, 等待 GameInit 到达后自动隐藏遮罩")
                else
                    -- 连接正常且不在等 GameInit: 用探针确认后隐藏
                    if IsCloudReady() then
                        ---@diagnostic disable-next-line: undefined-global
                        clientCloud:Get("lingshi", {
                            ok = function()
                                print("[Main] 前台探针成功，隐藏遮罩")
                                ReconnectOverlay.Hide()
                            end,
                            error = function()
                                print("[Main] 前台探针 error 但连接通，隐藏遮罩")
                                ReconnectOverlay.Hide()
                            end,
                            timeout = function()
                                print("[Main] 前台探针超时，保持遮罩")
                            end,
                        })
                    end
                end
            end
            -- 连接正常 + 遮罩未显示 → 什么都不做（正常情况）
        end
    end
end

-- ========== 帧更新 ==========

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    local dt = eventData["TimeStep"]:GetFloat()

    -- 云加载未完成
    if loadState ~= "done" then
        if loadState == "probe" then
            -- 探针阶段: 等待轻量 Get 回调, 超时则走失败流程
            cloudLoadTimer = cloudLoadTimer + dt
            if not probeResponded and cloudLoadTimer >= PROBE_TIMEOUT then
                print("[Main] Probe timeout (no callback in " .. PROBE_TIMEOUT .. "s)")
                probeResponded = true
                onProbeOrLoadFailed()
            end
        elseif loadState == "loading" then
            -- 正式加载阶段: 等待 BatchGet 响应
            cloudLoadTimer = cloudLoadTimer + dt
            if cloudLoadTimer >= CLOUD_LOAD_TIMEOUT then
                print("[Main] BatchGet timeout after " .. CLOUD_LOAD_TIMEOUT .. "s")
                onCloudLoaded(false)
            end
        elseif loadState == "wait_retry" then
            -- 自动重试间隔倒计时, 从探针重新开始
            cloudLoadTimer = cloudLoadTimer + dt
            if cloudLoadTimer >= AUTO_RETRY_DELAY then
                startProbe()
            end
        elseif loadState == "wait_connection" then
            if State.serverMode then
                -- 服务端权威模式：GameInit 回调已注册，静等即可
            else
                -- 后台匹配模式：轮询 clientCloud 就绪状态
                if IsCloudReady() then
                    print("[Main] clientCloud 已就绪，发起探针")
                    retryCount = 0
                    startProbe()
                end
            end
        end
        -- "failed" 状态: 等待用户点击重新连接

        -- 加载阶段也需要驱动遮罩动画
        Loading.Update(dt)
        ReconnectOverlay.Update(dt)
        XToast.Update(dt)
        -- 加载阶段也需要驱动区服拉取（选服后才会收到 GameInit）
        ServerSelect.Update(dt)
        return
    end

    -- 🔴 离线弹窗兜底定时器: 防止主链路因任何竞态/时序问题遗漏弹窗
    if offlineFallbackTimer_ then
        offlineFallbackTimer_ = offlineFallbackTimer_ - dt
        if offlineFallbackTimer_ <= 0 then
            offlineFallbackTimer_ = nil
            if not offlineModalShown_ and ClientNet.pendingOffline_ then
                print("[Offline-Diag] FALLBACK TRIGGERED: pendingOffline_ 仍未消费, 强制弹窗!")
                checkOfflineEarnings("fallback_timer")
            elseif not offlineModalShown_ and not ClientNet.pendingOffline_ then
                print("[Offline-Diag] FALLBACK: pendingOffline_ 为 nil, 检查备份数据")
                -- 尝试从备份恢复(HandleGameInit 可能被覆盖了)
                local backup = ClientNet.GetOfflineBackup and ClientNet.GetOfflineBackup()
                if backup and backup.hasEarnings then
                    print("[Offline-Diag] FALLBACK: 使用备份离线数据弹窗!")
                    showServerOfflineModal(backup)
                else
                    print("[Offline-Diag] FALLBACK: 无备份数据, 本次登录无离线收益")
                end
            end
        end
    end

    -- GM 延迟注入: GameInit 到达后检测开发者身份并显示 GM 按钮
    if not gmInjected_ then
        if GM.IsDeveloper() then
            gmInjected_ = true
            if gmBtnRef_ then gmBtnRef_:Show() end
        end
    end
    -- 调试白名单用户启用悬浮日志（独立于 GM 判断，每帧检查直到启用）
    if ClientNet.debugEnabled_ and uiRoot_ and not DebugLog.IsEnabled() then
        DebugLog.Enable(uiRoot_)
    end

    -- 驱动游戏核心逻辑（开始界面可见时不 tick，防止未进入游戏就消耗寿元/触发陨落）
    if not StartScreen.IsVisible() then
        GameCore.Update(dt)
    end

    -- 驱动讨价还价动画
    Bargain.Update(dt)

    -- 驱动渡劫小游戏
    Dujie.Update(dt)

    -- 驱动修仙 Toast 动画
    XToast.Update(dt)

    -- 驱动聊天 ticker 轮播
    Chat.Update(dt)

    -- 驱动邮件拉取超时检测
    Mail.Update(dt)

    -- 驱动广告超时检测 + buff面板刷新
    Ad.Update(dt)

    -- 驱动加载遮罩、重连遮罩和粒子动画
    Loading.Update(dt)
    ReconnectOverlay.Update(dt)
    Particle.Update(dt)
    -- 打坐粒子：每帧跟随角色容器实际位置，适配不同屏幕
    if currentTab == "upgrade" then
        local cx, cy = Upgrade.GetCharCenterRatio()
        Particle.SetMeditateCenter(cx, cy)
    end
    Particle.UpdateMeditate(dt)

    -- 驱动区服拉取重试（连接就绪后自动拉取，直到成功）
    ServerSelect.Update(dt)

    -- 驱动红点刷新
    RedDot.Update(dt)

    -- 驱动新手引导动画
    Guide.Update(dt)

    -- 驱动新手引导检测(进入游戏主页后才运行, 避免开始界面就弹通知)
    if not StartScreen.IsVisible() then
        Tutorial.Update()
    end

    -- 节流刷新 UI
    -- 当有活跃触摸/鼠标按下时跳过刷新，避免 ClearChildren 重建按钮导致
    -- pressedWidget 引用失效、click 事件被丢弃（表现为"需要点两次"）
    uiRefreshTimer = uiRefreshTimer + dt
    if uiRefreshTimer >= UI_REFRESH_INTERVAL then
        local hasActivePointer = input:GetMouseButtonDown(MOUSEB_LEFT) or input.numTouches > 0
        if hasActivePointer then
            -- 指针活跃，延迟到下一轮再刷新（保持计时器不归零）
            uiRefreshTimer = UI_REFRESH_INTERVAL
        else
            uiRefreshTimer = uiRefreshTimer - UI_REFRESH_INTERVAL
            refreshCurrentPage()
        end
    end
end
