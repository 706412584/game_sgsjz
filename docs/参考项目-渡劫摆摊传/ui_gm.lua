-- ============================================================================
-- ui_gm.lua — GM 管理面板 (全页 Tab 版)
-- 仅开发者可见，作为条件注入的第6个 Tab 页
-- ============================================================================
local UI = require("urhox-libs/UI")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local Config = require("data_config")
local State = require("data_state")
local Mail = require("ui_mail")
local ServerSelect = require("ui_server")
local Shared = require("network.shared")
local EVENTS = Shared.EVENTS

local M = {}

-- GM 用户 ID 列表
local GM_USER_IDS = { ["1644503283"] = true, ["529757584"] = true }
local isWeb = PlatformUtils.IsWebPlatform()

-- GM 操作目标区服(默认跟随当前区服)
local gmServerId_ = nil  -- nil = 使用当前区服
local gmServerLabel_ = nil  -- 区服选择器显示标签
local realmBtnPanel_ = nil  -- 区服按钮容器
local realmBtnsBuilt_ = false  -- 区服按钮是否已构建

--- 获取 GM 操作的目标区服 ID
---@return number
local function getGmServerId()
    if gmServerId_ ~= nil then return gmServerId_ end
    return State.state.serverId or 0
end

--- 检查当前用户是否为GM（唯一依据: clientCloud.userId）
---@return boolean
function M.IsDeveloper()
    ---@diagnostic disable-next-line: undefined-global
    local ok, val = pcall(function() return clientCloud and clientCloud.userId end)
    if ok and val and val ~= 0 then
        return GM_USER_IDS[tostring(val)] == true
    end
    return false
end

--- 获取当前用户 ID（供外部使用）
---@return number
function M.GetUserId()
    ---@diagnostic disable-next-line: undefined-global
    local ok, val = pcall(function() return clientCloud and clientCloud.userId end)
    if ok and val then return val end
    return 0
end

-- ========== 内部状态 ==========
local gmPanel = nil
local logLabel = nil
local cdkListPanel = nil
local cdkStatusLabel = nil
local cdkCountInput = nil
local announcementInput = nil
local announcementStatus = nil
local generatedCDKs = {}
-- (邮件奖励选择已移入 showMailModal 弹窗)
local cdkType = "single"  -- "single" | "universal"
local cdkTypeBtns = {}

---@diagnostic disable-next-line: undefined-global
local cjson = cjson  -- 引擎内置全局变量，不能 require

-- ========== GM 快捷操作 ==========

local GameCore = require("game_core")

local GM_ACTIONS = {
    {
        name = "+1000灵石",
        action = function()
            if State.serverMode then
                GameCore.SendGameAction("gm_add", { what = "lingshi", amount = 1000 })
                return "请求已发送..."
            end
            State.AddLingshi(1000)
            return "已添加 1000 灵石"
        end,
    },
    {
        name = "+500修为",
        action = function()
            if State.serverMode then
                GameCore.SendGameAction("gm_add", { what = "xiuwei", amount = 500 })
                return "请求已发送..."
            end
            State.AddXiuwei(500)
            return "已添加 500 修为"
        end,
    },
    {
        name = "材料各+100",
        action = function()
            if State.serverMode then
                GameCore.SendGameAction("gm_add", { what = "materials", amount = 100 })
                return "请求已发送..."
            end
            for _, mat in ipairs(Config.Materials) do
                State.AddMaterial(mat.id, 100)
            end
            return "已添加全部材料各100"
        end,
    },
    {
        name = "商品各+10",
        action = function()
            if State.serverMode then
                GameCore.SendGameAction("gm_add", { what = "products", amount = 10 })
                return "请求已发送..."
            end
            for _, prod in ipairs(Config.Products) do
                State.AddProduct(prod.id, 10)
            end
            return "已添加全部商品各10"
        end,
    },
    {
        name = "+100口碑",
        action = function()
            if State.serverMode then
                GameCore.SendGameAction("gm_add", { what = "reputation", amount = 100 })
                return "请求已发送..."
            end
            State.state.reputation = math.min(1000, (State.state.reputation or 100) + 100)
            State.Emit("reputation_changed", State.state.reputation)
            return "口碑+" .. 100 .. " 当前:" .. State.state.reputation
        end,
    },
}

-- ========== 工具函数 ==========

--- 创建分区卡片
---@param title string
---@param contentChildren table
---@return table UI.Panel
local function createSection(title, contentChildren)
    return UI.Panel {
        width = "100%",
        flexShrink = 0,
        backgroundColor = Config.Colors.panel,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = Config.Colors.border,
        padding = 10,
        gap = 6,
        marginBottom = 8,
        children = {
            UI.Label {
                text = title,
                fontSize = 11,
                fontWeight = "bold",
                fontColor = Config.Colors.textGold,
                width = "100%",
            },
            UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border },
            table.unpack(contentChildren),
        },
    }
end

--- 复制文本到剪贴板
local function copyToClipboard(text, label)
    if isWeb then
        print("[CDK] " .. text)
        if label then
            label:SetText("已输出到F12控制台")
            label:SetStyle({ fontColor = Config.Colors.textGold })
        end
    else
        ---@diagnostic disable-next-line: undefined-global
        pcall(function()
            ---@diagnostic disable-next-line: undefined-global
            ui:SetUseSystemClipboard(true)
            ---@diagnostic disable-next-line: undefined-global
            ui:SetClipboardText(text)
        end)
        if label then
            label:SetText("已复制: " .. text)
            label:SetStyle({ fontColor = Config.Colors.textGreen })
        end
    end
end

-- ========== 各分区构建 ==========

--- 快捷操作分区
local function createQuickActionsSection()
    logLabel = UI.Label {
        text = "就绪",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }

    local actionBtns = {}
    for _, act in ipairs(GM_ACTIONS) do
        table.insert(actionBtns, UI.Button {
            text = act.name,
            fontSize = 10,
            paddingHorizontal = 10,
            height = 28,
            backgroundColor = Config.Colors.panelLight,
            textColor = Config.Colors.textPrimary,
            borderRadius = 4,
            borderWidth = 1,
            borderColor = Config.Colors.border,
            onClick = function(self)
                local msg = act.action()
                logLabel:SetText(msg)
                logLabel:SetStyle({ fontColor = Config.Colors.textGreen })
            end,
        })
    end

    return createSection("快捷操作", {
        UI.Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            gap = 6,
            width = "100%",
            children = actionBtns,
        },
        logLabel,
    })
end

--- 公告设置分区
local function createAnnouncementSection()
    announcementInput = UI.TextField {
        placeholder = "输入公告内容...",
        fontSize = 10,
        width = "100%",
        height = 26,
    }
    announcementStatus = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }

    return createSection("公告设置", {
        UI.Panel {
            flexDirection = "row",
            gap = 4,
            width = "100%",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = { announcementInput },
                },
                UI.Button {
                    text = "发布",
                    fontSize = 9,
                    width = 44,
                    height = 26,
                    backgroundColor = Config.Colors.blue,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 4,
                    onClick = function(self)
                        local text = announcementInput:GetText()
                        if text == "" then
                            announcementStatus:SetText("请输入公告内容")
                            announcementStatus:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        announcementStatus:SetText("发布中...")
                        announcementStatus:SetStyle({ fontColor = Config.Colors.textSecond })
                        State.SaveAnnouncement(text, function(ok)
                            if ok then
                                announcementStatus:SetText("公告已发布!")
                                announcementStatus:SetStyle({ fontColor = Config.Colors.textGreen })
                            else
                                announcementStatus:SetText("发布失败")
                                announcementStatus:SetStyle({ fontColor = Config.Colors.red })
                            end
                        end)
                    end,
                },
                UI.Button {
                    text = "清除",
                    fontSize = 9,
                    width = 44,
                    height = 26,
                    backgroundColor = Config.Colors.panelLight,
                    textColor = Config.Colors.textPrimary,
                    borderRadius = 4,
                    onClick = function(self)
                        State.SaveAnnouncement("", function(ok)
                            if ok then
                                announcementStatus:SetText("公告已清除")
                                announcementStatus:SetStyle({ fontColor = Config.Colors.textGreen })
                            else
                                announcementStatus:SetText("清除失败")
                                announcementStatus:SetStyle({ fontColor = Config.Colors.red })
                            end
                        end)
                    end,
                },
            },
        },
        announcementStatus,
    })
end

--- 刷新CDK列表显示
local function refreshCDKList()
    if not cdkListPanel then return end
    cdkListPanel:ClearChildren()
    for _, code in ipairs(generatedCDKs) do
        cdkListPanel:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            gap = 4,
            paddingVertical = 1,
            children = {
                UI.Label {
                    text = code,
                    fontSize = 9,
                    fontColor = Config.Colors.textGold,
                    flexGrow = 1,
                },
                UI.Button {
                    text = isWeb and "打印" or "复制",
                    fontSize = 8,
                    width = 36,
                    height = 20,
                    backgroundColor = Config.Colors.jadeDark,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 3,
                    onClick = function(self)
                        copyToClipboard(code, cdkStatusLabel)
                    end,
                },
            },
        })
    end
    if cdkStatusLabel then
        cdkStatusLabel:SetText("已生成 " .. #generatedCDKs .. " 个CDK")
        cdkStatusLabel:SetStyle({ fontColor = Config.Colors.textSecond })
    end
end

--- 更新码类型按钮高亮
local function refreshCdkTypeBtns()
    for tp, btn in pairs(cdkTypeBtns) do
        if tp == cdkType then
            btn:SetStyle({ backgroundColor = Config.Colors.jadeDark, textColor = { 255, 255, 255, 255 } })
        else
            btn:SetStyle({ backgroundColor = Config.Colors.panelLight, textColor = Config.Colors.textSecond })
        end
    end
end

--- 自定义CDK资源输入弹窗
local function showCustomCdkModal()
    local Modal = require("urhox-libs/UI/Widgets/Modal")
    local Dropdown = require("urhox-libs/UI/Widgets/Dropdown")

    -- 屏幕较窄时(手机竖屏)使用sm尺寸避免超出屏幕
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local modalSize = logicalW < 500 and "sm" or "md"

    local modal = Modal({
        title = "自定义CDK - 设置奖励",
        size = modalSize,
    })

    -- 可滚动内容容器(解决内容超出弹窗高度无法查看的问题)
    local scrollBody = UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        overflow = "scroll", showScrollbar = false,
        gap = 2,
    }
    modal:AddContent(scrollBody)

    -- 奖励标题输入(兑换成功弹窗显示的名称)
    local titleTf = UI.TextField {
        placeholder = "自定义奖励",
        fontSize = 10,
        height = 24,
        flexGrow = 1,
        flexShrink = 1,
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        width = "100%",
        paddingVertical = 1,
        children = {
            UI.Label { text = "标题", fontSize = 10, fontColor = Config.Colors.textGold, width = 50 },
            titleTf,
        },
    })

    -- 分隔线
    scrollBody:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border, marginVertical = 2 })

    -- 资源输入字段
    local CUSTOM_FIELDS = {
        { id = "lingshi", name = "灵石" },
        { id = "xiuwei",  name = "修为" },
        { id = "lingcao", name = "灵草" },
        { id = "lingzhi", name = "灵芝" },
        { id = "xuantie", name = "玄铁" },
        { id = "yaodan",  name = "药丹" },
        { id = "jingshi", name = "精石" },
    }
    local inputs = {}

    for _, f in ipairs(CUSTOM_FIELDS) do
        local tf = UI.TextField {
            placeholder = "0",
            fontSize = 10,
            height = 24,
            flexGrow = 1,
            flexShrink = 1,
            textAlign = "right",
        }
        inputs[f.id] = tf
        scrollBody:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 6,
            width = "100%",
            paddingVertical = 1,
            children = {
                UI.Label { text = f.name, fontSize = 10, fontColor = Config.Colors.textSecond, width = 50 },
                tf,
            },
        })
    end

    -- 丹药选择行(商品 + 突破丹药)
    local productOptions = { { value = "", label = "不选择" } }
    for _, p in ipairs(Config.Products) do
        table.insert(productOptions, { value = "prod:" .. p.id, label = p.name })
    end
    -- 添加境界突破相关的消耗品(来自Collectibles)
    for _, c in ipairs(Config.Collectibles) do
        if c.type == "consumable" then
            table.insert(productOptions, { value = "coll:" .. c.id, label = c.name .. "(珍)" })
        end
    end
    local productDropdown = Dropdown {
        options = productOptions,
        value = "",
        placeholder = "选择丹药/消耗品",
        fontSize = 10,
        height = 24,
        flexGrow = 1,
        flexShrink = 1,
    }
    local productCountTf = UI.TextField {
        placeholder = "0",
        fontSize = 10,
        height = 24,
        width = 50,
        textAlign = "right",
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        width = "100%",
        paddingVertical = 1,
        children = {
            UI.Label { text = "丹药", fontSize = 10, fontColor = Config.Colors.orange, width = 50 },
            productDropdown,
            productCountTf,
        },
    })

    -- 珍藏物品选择行(永久类收藏品)
    local collectibleOptions = { { value = "", label = "不选择" } }
    for _, c in ipairs(Config.Collectibles) do
        if c.type == "permanent" then
            table.insert(collectibleOptions, { value = c.id, label = c.name })
        end
    end
    local collectibleDropdown = Dropdown {
        options = collectibleOptions,
        value = "",
        placeholder = "选择珍藏",
        fontSize = 10,
        height = 24,
        flexGrow = 1,
        flexShrink = 1,
    }
    local collectibleCountTf = UI.TextField {
        placeholder = "0",
        fontSize = 10,
        height = 24,
        width = 50,
        textAlign = "right",
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        width = "100%",
        paddingVertical = 1,
        children = {
            UI.Label { text = "珍藏", fontSize = 10, fontColor = Config.Colors.jade, width = 50 },
            collectibleDropdown,
            collectibleCountTf,
        },
    })

    -- 分隔线
    scrollBody:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border, marginVertical = 2 })

    -- 数量+类型行
    local countTf = UI.TextField {
        placeholder = "数量(1-50)",
        fontSize = 10,
        width = 80,
        height = 24,
        textAlign = "center",
    }
    local typeLabel = UI.Label {
        text = cdkType == "universal" and "通用码" or "单人码",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
    }

    scrollBody:AddChild(UI.Panel {
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        width = "100%",
        marginTop = 6,
        children = {
            UI.Label { text = "数量", fontSize = 10, fontColor = Config.Colors.textSecond, width = 50 },
            countTf,
            typeLabel,
        },
    })

    -- 底部留白(让最后的内容不被键盘遮挡)
    scrollBody:AddChild(UI.Panel { width = "100%", height = 80 })

    -- 底部按钮
    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 8,
        width = "100%",
    }
    footer:AddChild(UI.Button {
        text = "取消",
        variant = "secondary",
        fontSize = 10,
        onClick = function() modal:Close() end,
    })
    footer:AddChild(UI.Button {
        text = "生成",
        variant = "primary",
        fontSize = 10,
        onClick = function()
            -- 收集自定义奖励
            local customReward = { materials = {} }
            local hasAny = false

            -- 自定义标题
            local titleText = titleTf:GetText()
            if titleText and titleText ~= "" then
                customReward.name = titleText
            end

            for _, f in ipairs(CUSTOM_FIELDS) do
                local v = tonumber(inputs[f.id]:GetText()) or 0
                if v > 0 then
                    hasAny = true
                    if f.id == "lingshi" or f.id == "xiuwei" then
                        customReward[f.id] = math.floor(v)
                    else
                        customReward.materials[f.id] = math.floor(v)
                    end
                end
            end
            -- 清理空 materials
            local hasMat = false
            for _ in pairs(customReward.materials) do hasMat = true; break end
            if not hasMat then customReward.materials = nil end

            -- 收集丹药/消耗品(按前缀区分来源)
            local selVal = productDropdown.props.value
            local selCount = math.floor(tonumber(productCountTf:GetText()) or 0)
            if selVal and selVal ~= "" and selCount > 0 then
                hasAny = true
                if selVal:sub(1, 5) == "prod:" then
                    local prodId = selVal:sub(6)
                    customReward.products = customReward.products or {}
                    customReward.products[prodId] = selCount
                elseif selVal:sub(1, 5) == "coll:" then
                    local collId = selVal:sub(6)
                    customReward.collectibles = customReward.collectibles or {}
                    customReward.collectibles[collId] = selCount
                end
            end

            -- 收集珍藏物品(永久类)
            local collId = collectibleDropdown.props.value
            local collCount = math.floor(tonumber(collectibleCountTf:GetText()) or 0)
            if collId and collId ~= "" and collCount > 0 then
                hasAny = true
                customReward.collectibles = customReward.collectibles or {}
                customReward.collectibles[collId] = (customReward.collectibles[collId] or 0) + collCount
            end

            if not hasAny then
                UI.Toast.Show("请至少填写一项资源数量", { variant = "warning" })
                return
            end

            local count = math.max(1, math.min(50, math.floor(tonumber(countTf:GetText()) or 1)))
            modal:Close()
            if cdkStatusLabel then
                cdkStatusLabel:SetText("正在生成自定义CDK...")
                cdkStatusLabel:SetStyle({ fontColor = Config.Colors.textSecond })
            end
            GameCore.SendGameAction("gm_cdk_create", {
                rewardKey = "CUSTOM",
                cdkType = cdkType,
                count = count,
                customReward = customReward,
            })
        end,
    })
    modal:SetFooter(footer)
    modal:Open()
end

--- 生成结果弹窗(显示兑换码, 可复制)
local function showCdkResultModal(codes, rewardName, typeName)
    local Modal = require("urhox-libs/UI/Widgets/Modal")

    local modal = Modal({
        title = "CDK生成完成",
        size = "sm",
    })

    modal:AddContent(UI.Label {
        text = typeName .. " x" .. #codes .. "  " .. (rewardName or ""),
        fontSize = 10,
        fontColor = Config.Colors.textGold,
        width = "100%",
        marginBottom = 4,
    })

    -- 逐行显示兑换码(可滚动) + 每行可单独复制
    local allText = table.concat(codes, "\n")
    local listPanel = UI.Panel {
        width = "100%",
        height = math.min(160, 8 + #codes * 18),
        overflow = "scroll",
        borderWidth = 1,
        borderColor = "#444444",
        borderRadius = 4,
        padding = 6,
    }
    local function cdkCopy(text, tip)
        ui.useSystemClipboard = true
        ui:SetClipboardText(text)
        if isWeb then
            print("[CDK] " .. text)
            UI.Toast.Show(tip .. " (Web预览请查看控制台)", { variant = "info" })
        else
            UI.Toast.Show(tip, { variant = "success" })
        end
    end
    for _, code in ipairs(codes) do
        local row = UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            marginBottom = 2,
        }
        row:AddChild(UI.Label {
            text = code,
            fontSize = 9,
            fontColor = "#DDDDDD",
            flexGrow = 1,
        })
        row:AddChild(UI.Button {
            text = "复制",
            fontSize = 7,
            height = 16,
            paddingLeft = 4, paddingRight = 4,
            paddingTop = 1, paddingBottom = 1,
            onClick = function()
                cdkCopy(code, "已复制: " .. code)
            end,
        })
        listPanel:AddChild(row)
    end
    modal:AddContent(listPanel)

    -- 底部: 复制全部 + 关闭
    local footer = UI.Panel {
        flexDirection = "row",
        justifyContent = "flex-end",
        gap = 8,
        width = "100%",
    }
    footer:AddChild(UI.Button {
        text = "复制全部",
        variant = "primary",
        fontSize = 10,
        onClick = function()
            cdkCopy(allText, "已复制 " .. #codes .. " 个CDK!")
        end,
    })
    footer:AddChild(UI.Button {
        text = "关闭",
        variant = "secondary",
        fontSize = 10,
        onClick = function() modal:Close() end,
    })
    modal:SetFooter(footer)
    modal:Open()
end

--- CDK批量生成分区（服务端生成）
local function createCDKSection()
    cdkCountInput = UI.TextField {
        placeholder = "数量(1-50)",
        fontSize = 10,
        width = 70,
        height = 26,
        textAlign = "center",
    }

    cdkListPanel = UI.Panel {
        width = "100%",
        gap = 2,
        maxHeight = 150,
        overflow = "scroll",
    }

    cdkStatusLabel = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }

    -- 码类型切换: 单人码 / 通用码
    local typeLabels = { single = "单人码", universal = "通用码" }
    for _, tp in ipairs({ "single", "universal" }) do
        cdkTypeBtns[tp] = UI.Button {
            text = typeLabels[tp],
            fontSize = 9,
            width = 56,
            height = 22,
            borderRadius = 4,
            backgroundColor = tp == cdkType and Config.Colors.jadeDark or Config.Colors.panelLight,
            textColor = tp == cdkType and { 255, 255, 255, 255 } or Config.Colors.textSecond,
            onClick = function(self)
                cdkType = tp
                refreshCdkTypeBtns()
            end,
        }
    end

    -- 生成按钮(每个奖励类型)
    local cdkGenBtns = {}
    for key, reward in pairs(Config.CDKRewards) do
        table.insert(cdkGenBtns, UI.Button {
            text = reward.name,
            fontSize = 9,
            flexGrow = 1,
            height = 26,
            backgroundColor = Config.Colors.purpleDark,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                local countText = cdkCountInput:GetText()
                local count = tonumber(countText) or 1
                count = math.max(1, math.min(50, math.floor(count)))
                cdkStatusLabel:SetText("正在生成...")
                cdkStatusLabel:SetStyle({ fontColor = Config.Colors.textSecond })
                GameCore.SendGameAction("gm_cdk_create", {
                    rewardKey = key,
                    cdkType = cdkType,
                    count = count,
                })
            end,
        })
    end

    -- 自定义CDK按钮
    local customCdkBtn = UI.Button {
        text = "自定义CDK",
        fontSize = 9,
        flexGrow = 1,
        height = 26,
        backgroundColor = Config.Colors.gold,
        textColor = { 30, 30, 30, 255 },
        borderRadius = 4,
        onClick = function(self)
            showCustomCdkModal()
        end,
    }

    -- 全部复制/打印按钮
    local copyAllBtn = UI.Button {
        text = isWeb and "全部打印" or "全部复制",
        fontSize = 9,
        width = 64,
        height = 24,
        backgroundColor = Config.Colors.blue,
        textColor = { 255, 255, 255, 255 },
        borderRadius = 4,
        onClick = function(self)
            if #generatedCDKs == 0 then
                cdkStatusLabel:SetText("没有可操作的CDK")
                cdkStatusLabel:SetStyle({ fontColor = Config.Colors.red })
                return
            end
            if isWeb then
                print("====== CDK 全部 ======")
                for _, c in ipairs(generatedCDKs) do
                    print(c)
                end
                print("======================")
                cdkStatusLabel:SetText("已输出全部到F12控制台")
                cdkStatusLabel:SetStyle({ fontColor = Config.Colors.textGold })
            else
                local allCodes = table.concat(generatedCDKs, "\n")
                ---@diagnostic disable-next-line: undefined-global
                pcall(function()
                    ---@diagnostic disable-next-line: undefined-global
                    ui:SetUseSystemClipboard(true)
                    ---@diagnostic disable-next-line: undefined-global
                    ui:SetClipboardText(allCodes)
                end)
                cdkStatusLabel:SetText("已复制全部 " .. #generatedCDKs .. " 个CDK!")
                cdkStatusLabel:SetStyle({ fontColor = Config.Colors.textGreen })
            end
        end,
    }

    return createSection("CDK 批量生成(服务端)", {
        -- 码类型切换行
        UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            width = "100%",
            children = {
                UI.Label { text = "类型:", fontSize = 9, fontColor = Config.Colors.textSecond },
                cdkTypeBtns["single"],
                cdkTypeBtns["universal"],
                UI.Label {
                    text = "",
                    fontSize = 8,
                    fontColor = Config.Colors.textSecond,
                    flexGrow = 1,
                    textAlign = "right",
                },
            },
        },
        -- 数量+奖励按钮行
        UI.Panel {
            flexDirection = "row",
            flexWrap = "wrap",
            alignItems = "center",
            gap = 4,
            width = "100%",
            children = {
                cdkCountInput,
                customCdkBtn,
                table.unpack(cdkGenBtns),
            },
        },
        UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            width = "100%",
            children = {
                copyAllBtn,
                cdkStatusLabel,
            },
        },
        cdkListPanel,
    })
end

--- 邮件发送弹窗(复用CDK弹窗风格和资源选择)

local function showMailModal()
    local Modal = require("urhox-libs/UI/Widgets/Modal")
    local Dropdown = require("urhox-libs/UI/Widgets/Dropdown")

    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local modalSize = logicalW < 500 and "sm" or "md"

    local modal = Modal({
        title = "发送邮件",
        size = modalSize,
    })

    local scrollBody = UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        overflow = "scroll", showScrollbar = false,
        gap = 2,
    }
    modal:AddContent(scrollBody)

    -- 目标输入
    local targetTf = UI.TextField {
        placeholder = "平台UID/角色ID/角色名(0或留空=全体广播)",
        fontSize = 10, height = 24, width = "100%",
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%", paddingVertical = 1,
        children = {
            UI.Label { text = "目标", fontSize = 10, fontColor = Config.Colors.textGold, width = 50 },
            targetTf,
        },
    })

    -- 标题输入
    local titleTf = UI.TextField {
        placeholder = "邮件标题",
        fontSize = 10, height = 24, flexGrow = 1, flexShrink = 1,
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%", paddingVertical = 1,
        children = {
            UI.Label { text = "标题", fontSize = 10, fontColor = Config.Colors.textGold, width = 50 },
            titleTf,
        },
    })

    -- 内容输入
    local contentTf = UI.TextField {
        placeholder = "邮件内容(可选)",
        fontSize = 10, height = 24, flexGrow = 1, flexShrink = 1,
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%", paddingVertical = 1,
        children = {
            UI.Label { text = "内容", fontSize = 10, fontColor = Config.Colors.textGold, width = 50 },
            contentTf,
        },
    })

    -- 广播范围切换
    local broadcastAll = true
    local scopeBtn = UI.Button {
        text = "广播范围: 全部区服",
        fontSize = 8, width = "100%", height = 22,
        backgroundColor = Config.Colors.jadeDark,
        textColor = { 255, 255, 255, 255 }, borderRadius = 3,
        onClick = function(self)
            broadcastAll = not broadcastAll
            if broadcastAll then
                self:SetText("广播范围: 全部区服")
                self:SetStyle({ backgroundColor = Config.Colors.jadeDark })
            else
                local srvName = "S" .. getGmServerId()
                local srvList = ServerSelect.GetServerList()
                for _, srv in ipairs(srvList) do
                    if srv.id == getGmServerId() then srvName = srv.name; break end
                end
                self:SetText("广播范围: " .. srvName)
                self:SetStyle({ backgroundColor = Config.Colors.orange })
            end
        end,
    }
    scrollBody:AddChild(scopeBtn)

    -- 分隔线
    scrollBody:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border, marginVertical = 2 })

    -- 资源输入字段(复用CDK弹窗)
    local MAIL_FIELDS = {
        { id = "lingshi", name = "灵石" },
        { id = "xiuwei",  name = "修为" },
        { id = "lingcao", name = "灵草" },
        { id = "lingzhi", name = "灵芝" },
        { id = "xuantie", name = "玄铁" },
        { id = "yaodan",  name = "药丹" },
        { id = "jingshi", name = "精石" },
    }
    local inputs = {}
    for _, f in ipairs(MAIL_FIELDS) do
        local tf = UI.TextField {
            placeholder = "0", fontSize = 10, height = 24,
            flexGrow = 1, flexShrink = 1, textAlign = "right",
        }
        inputs[f.id] = tf
        scrollBody:AddChild(UI.Panel {
            flexDirection = "row", alignItems = "center", gap = 6, width = "100%", paddingVertical = 1,
            children = {
                UI.Label { text = f.name, fontSize = 10, fontColor = Config.Colors.textSecond, width = 50 },
                tf,
            },
        })
    end

    -- 丹药/消耗品选择
    local productOptions = { { value = "", label = "不选择" } }
    for _, p in ipairs(Config.Products) do
        table.insert(productOptions, { value = "prod:" .. p.id, label = p.name })
    end
    for _, c in ipairs(Config.Collectibles) do
        if c.type == "consumable" then
            table.insert(productOptions, { value = "coll:" .. c.id, label = c.name .. "(珍)" })
        end
    end
    local productDropdown = Dropdown {
        options = productOptions, value = "", placeholder = "选择丹药/消耗品",
        fontSize = 10, height = 24, flexGrow = 1, flexShrink = 1,
    }
    local productCountTf = UI.TextField {
        placeholder = "0", fontSize = 10, height = 24, width = 50, textAlign = "right",
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%", paddingVertical = 1,
        children = {
            UI.Label { text = "丹药", fontSize = 10, fontColor = Config.Colors.orange, width = 50 },
            productDropdown, productCountTf,
        },
    })

    -- 珍藏物品选择
    local collectibleOptions = { { value = "", label = "不选择" } }
    for _, c in ipairs(Config.Collectibles) do
        if c.type == "permanent" then
            table.insert(collectibleOptions, { value = c.id, label = c.name })
        end
    end
    local collectibleDropdown = Dropdown {
        options = collectibleOptions, value = "", placeholder = "选择珍藏",
        fontSize = 10, height = 24, flexGrow = 1, flexShrink = 1,
    }
    local collectibleCountTf = UI.TextField {
        placeholder = "0", fontSize = 10, height = 24, width = 50, textAlign = "right",
    }
    scrollBody:AddChild(UI.Panel {
        flexDirection = "row", alignItems = "center", gap = 6, width = "100%", paddingVertical = 1,
        children = {
            UI.Label { text = "珍藏", fontSize = 10, fontColor = Config.Colors.jade, width = 50 },
            collectibleDropdown, collectibleCountTf,
        },
    })

    -- 分隔线
    scrollBody:AddChild(UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border, marginVertical = 2 })

    -- 状态提示
    local statusLabel = UI.Label {
        text = "", fontSize = 9, fontColor = Config.Colors.textSecond,
        textAlign = "center", width = "100%",
    }
    scrollBody:AddChild(statusLabel)

    -- 底部留白
    scrollBody:AddChild(UI.Panel { width = "100%", height = 80 })

    -- 注册发送结果回调
    Mail.SetSendResultCallback(function(success, msg)
        if statusLabel then
            statusLabel:SetText(msg or (success and "发送成功" or "发送失败"))
            statusLabel:SetStyle({
                fontColor = success and Config.Colors.textGreen or Config.Colors.red,
            })
        end
    end)

    -- 底部按钮
    local footer = UI.Panel {
        flexDirection = "row", justifyContent = "flex-end", gap = 8, width = "100%",
    }
    footer:AddChild(UI.Button {
        text = "取消", variant = "secondary", fontSize = 10,
        onClick = function() modal:Close() end,
    })
    footer:AddChild(UI.Button {
        text = "发送", variant = "primary", fontSize = 10,
        onClick = function()
            local title = titleTf:GetText()
            if not title or title == "" then
                statusLabel:SetText("请输入邮件标题")
                statusLabel:SetStyle({ fontColor = Config.Colors.red })
                return
            end

            -- 收集多资源奖励(与CDK逻辑相同)
            local reward = { materials = {} }
            for _, f in ipairs(MAIL_FIELDS) do
                local v = tonumber(inputs[f.id]:GetText()) or 0
                if v > 0 then
                    if f.id == "lingshi" or f.id == "xiuwei" then
                        reward[f.id] = math.floor(v)
                    else
                        reward.materials[f.id] = math.floor(v)
                    end
                end
            end
            -- 清理空 materials
            local hasMat = false
            for _ in pairs(reward.materials) do hasMat = true; break end
            if not hasMat then reward.materials = nil end

            -- 丹药/消耗品
            local selVal = productDropdown.props.value
            local selCount = math.floor(tonumber(productCountTf:GetText()) or 0)
            if selVal and selVal ~= "" and selCount > 0 then
                if selVal:sub(1, 5) == "prod:" then
                    local prodId = selVal:sub(6)
                    reward.products = reward.products or {}
                    reward.products[prodId] = selCount
                elseif selVal:sub(1, 5) == "coll:" then
                    local collId = selVal:sub(6)
                    reward.collectibles = reward.collectibles or {}
                    reward.collectibles[collId] = selCount
                end
            end

            -- 珍藏物品
            local collId = collectibleDropdown.props.value
            local collCount = math.floor(tonumber(collectibleCountTf:GetText()) or 0)
            if collId and collId ~= "" and collCount > 0 then
                reward.collectibles = reward.collectibles or {}
                reward.collectibles[collId] = (reward.collectibles[collId] or 0) + collCount
            end

            local targetText = targetTf:GetText()
            local content = contentTf:GetText()
            local isBroadcast = (targetText == "" or targetText == "0")
            local sid = (isBroadcast and broadcastAll) and 0 or getGmServerId()

            local ok = Mail.SendMailFromGM(targetText, title, content, reward, sid)
            if ok then
                statusLabel:SetText("正在发送...")
                statusLabel:SetStyle({ fontColor = Config.Colors.textSecond })
            else
                statusLabel:SetText("发送失败(未连接服务器)")
                statusLabel:SetStyle({ fontColor = Config.Colors.red })
            end
        end,
    })
    modal:SetFooter(footer)
    modal:Open()
end

-- 邮件发送分区: 简化为一个按钮，点击打开弹窗
local function createMailSection()
    local mailStatusLabel = UI.Label {
        text = "", fontSize = 9, fontColor = Config.Colors.textSecond,
        textAlign = "center", width = "100%",
    }
    return createSection("发送邮件", {
        UI.Button {
            text = "打开邮件发送面板",
            fontSize = 10, width = "100%", height = 28,
            backgroundColor = Config.Colors.orange,
            textColor = { 255, 255, 255, 255 }, borderRadius = 4,
            onClick = function() showMailModal() end,
        },
        mailStatusLabel,
    })
end

-- ========== 已发邮件管理 ==========

local gmMailListPanel_ = nil     -- 查询结果容器
local gmMailStatusLabel_ = nil   -- 状态文本
local gmMailTargetInput_ = nil   -- 目标 UID 输入框
local gmMailData_ = {}           -- 查询到的邮件列表

--- 渲染 GM 邮件查询结果
local function renderGmMailList()
    if not gmMailListPanel_ then return end
    gmMailListPanel_:ClearChildren()

    if #gmMailData_ == 0 then
        gmMailListPanel_:AddChild(UI.Label {
            text = "该玩家邮箱为空",
            fontSize = 10,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 10,
        })
        return
    end

    for i, mail in ipairs(gmMailData_) do
        local v = mail.value or {}
        if type(v) == "string" then
            local dok, dval = pcall(cjson.decode, v)
            if dok and type(dval) == "table" then v = dval end
        end
        local title = v.title or "无标题"
        local rewardType = v.rewardType or ""
        local rewardAmt = v.rewardAmt or 0
        local rewardText = ""
        if rewardAmt > 0 then
            local mat = Config.GetMaterialById(rewardType)
            local name = mat and mat.name or rewardType
            if rewardType == "lingshi" then name = "灵石"
            elseif rewardType == "xiuwei" then name = "修为" end
            rewardText = rewardAmt .. " " .. name
        end

        gmMailListPanel_:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            gap = 4,
            paddingVertical = 3,
            paddingHorizontal = 4,
            backgroundColor = (i % 2 == 0) and Config.Colors.panelLight or nil,
            borderRadius = 3,
            children = {
                UI.Label {
                    text = "#" .. i,
                    fontSize = 8,
                    fontColor = Config.Colors.textSecond,
                    width = 22,
                },
                UI.Label {
                    text = title,
                    fontSize = 9,
                    fontColor = Config.Colors.textPrimary,
                    flexGrow = 1,
                    flexShrink = 1,
                },
                rewardText ~= "" and UI.Label {
                    text = rewardText,
                    fontSize = 8,
                    fontColor = Config.Colors.textGreen,
                } or nil,
                UI.Label {
                    text = "ID:" .. tostring(mail.id or "?"),
                    fontSize = 7,
                    fontColor = Config.Colors.textSecond,
                },
            },
        })
    end
end

--- 创建邮件管理分区
local function createMailManageSection()
    gmMailTargetInput_ = UI.TextField {
        placeholder = "平台UID/角色ID/角色名",
        fontSize = 9,
        width = "100%",
        height = 26,
        textAlign = "center",
    }
    gmMailStatusLabel_ = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }
    gmMailListPanel_ = UI.Panel {
        width = "100%",
        gap = 2,
        maxHeight = 160,
        overflow = "scroll",
    }

    return createSection("邮件管理", {
        gmMailTargetInput_,
        UI.Panel {
            flexDirection = "row",
            gap = 4,
            width = "100%",
            children = {
                UI.Button {
                    text = "查询邮箱",
                    fontSize = 9,
                    flexGrow = 1,
                    height = 26,
                    backgroundColor = Config.Colors.blue,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 4,
                    onClick = function(self)
                        local uid = gmMailTargetInput_:GetText()
                        if uid == "" then
                            gmMailStatusLabel_:SetText("请输入目标UID")
                            gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        gmMailStatusLabel_:SetText("查询中...")
                        gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.textSecond })
                        gmMailData_ = {}
                        if gmMailListPanel_ then gmMailListPanel_:ClearChildren() end

                        local ClientNet = require("network.client_net")
                        if not ClientNet.IsConnected() then
                            gmMailStatusLabel_:SetText("未连接服务器")
                            gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        local vm = VariantMap()
                        vm["TargetUid"] = Variant(uid)
                        ClientNet.SendToServer(EVENTS.MAIL_GM_QUERY, vm)
                    end,
                },
                UI.Button {
                    text = "清空邮箱",
                    fontSize = 9,
                    flexGrow = 1,
                    height = 26,
                    backgroundColor = Config.Colors.red,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 4,
                    onClick = function(self)
                        local uid = gmMailTargetInput_:GetText()
                        if uid == "" then
                            gmMailStatusLabel_:SetText("请输入目标UID")
                            gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        UI.Modal.Confirm({
                            title = "确认清空",
                            message = "确认清空 UID " .. uid .. " 的所有邮件?",
                            confirmText = "清空",
                            cancelText = "取消",
                            onConfirm = function()
                                gmMailStatusLabel_:SetText("清空中...")
                                gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.textSecond })

                                local ClientNet = require("network.client_net")
                                if not ClientNet.IsConnected() then
                                    gmMailStatusLabel_:SetText("未连接服务器")
                                    gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                                    return
                                end
                                local vm = VariantMap()
                                vm["TargetUid"] = Variant(uid)
                                ClientNet.SendToServer(EVENTS.MAIL_GM_CLEAR, vm)
                            end,
                        })
                    end,
                },
            },
        },
        gmMailStatusLabel_,
        gmMailListPanel_,
    })
end

-- 广播撤回变量(前置声明，供 OnGmMailResult 引用)
local bcListPanel_ = nil         -- 广播列表容器
local bcStatusLabel_ = nil       -- 状态文本
local bcData_ = {}               -- 广播历史数据

-- ========== GM 邮件回调 ==========

--- GM 邮件查询结果(由 client_net.lua 转发)
function M.OnGmMailList(eventData)
    local jsonStr   = eventData["MailJson"]:GetString()
    local count     = eventData["Count"]:GetInt()
    local targetUid = eventData["TargetUid"]:GetString()

    local ok, list = pcall(cjson.decode, jsonStr)
    if ok and type(list) == "table" then
        gmMailData_ = list
    else
        gmMailData_ = {}
    end

    if gmMailStatusLabel_ then
        gmMailStatusLabel_:SetText("UID " .. targetUid .. " 共 " .. count .. " 封邮件")
        gmMailStatusLabel_:SetStyle({ fontColor = Config.Colors.textGreen })
    end

    renderGmMailList()
end

--- GM 邮件操作结果(gm_query/gm_clear 的 MailResult 转发)
function M.OnGmMailResult(eventData)
    local action  = eventData["Action"]:GetString()
    local success = eventData["Success"]:GetBool()
    local message = eventData["Message"]:GetString()

    if gmMailStatusLabel_ then
        gmMailStatusLabel_:SetText(message)
        gmMailStatusLabel_:SetStyle({
            fontColor = success and Config.Colors.textGreen or Config.Colors.red,
        })
    end

    -- 清空成功后清空列表
    if action == "gm_clear" and success then
        gmMailData_ = {}
        renderGmMailList()
    end

    -- 撤回操作结果: 更新广播撤回面板状态并刷新列表
    if action == "revoke" then
        if bcStatusLabel_ then
            bcStatusLabel_:SetText(message)
            bcStatusLabel_:SetStyle({
                fontColor = success and Config.Colors.textGreen or Config.Colors.red,
            })
        end
        if success then
            -- 撤回成功后自动刷新广播列表
            Mail.FetchBroadcastList()
        end
    end
end

-- ========== 广播撤回管理 ==========

--- 格式化时间戳为可读字符串
local function formatTime(ts)
    if not ts or ts <= 0 then return "?" end
    return os.date("%m-%d %H:%M", ts)
end

--- 渲染广播历史列表
local function renderBroadcastList()
    if not bcListPanel_ then return end
    bcListPanel_:ClearChildren()

    if #bcData_ == 0 then
        bcListPanel_:AddChild(UI.Label {
            text = "暂无广播记录(仅保留7天内)",
            fontSize = 9, fontColor = Config.Colors.textSecond,
            textAlign = "center", width = "100%", paddingVertical = 8,
        })
        return
    end

    for i, bc in ipairs(bcData_) do
        local isRevoked = bc.revoked
        local srvLabel = (bc.serverId == 0) and "全服" or ("S" .. bc.serverId)

        local row = UI.Panel {
            flexDirection = "row", alignItems = "center",
            width = "100%", gap = 4, paddingVertical = 3, paddingHorizontal = 4,
            backgroundColor = isRevoked and { 60, 30, 30, 255 }
                or ((i % 2 == 0) and Config.Colors.panelLight or nil),
            borderRadius = 3,
        }

        row:AddChild(UI.Label {
            text = "#" .. tostring(bc.id),
            fontSize = 8, fontColor = Config.Colors.textSecond, width = 24,
        })
        row:AddChild(UI.Label {
            text = srvLabel,
            fontSize = 8, fontColor = Config.Colors.blue, width = 28,
        })
        row:AddChild(UI.Label {
            text = bc.title or "无标题",
            fontSize = 9, fontColor = isRevoked and Config.Colors.textSecond or Config.Colors.textPrimary,
            flexGrow = 1, flexShrink = 1,
        })
        row:AddChild(UI.Label {
            text = formatTime(bc.timestamp),
            fontSize = 7, fontColor = Config.Colors.textSecond, width = 55,
        })

        if isRevoked then
            row:AddChild(UI.Label {
                text = "已撤回",
                fontSize = 8, fontColor = Config.Colors.red, width = 36,
            })
        else
            local capturedId = bc.id
            row:AddChild(UI.Button {
                text = "撤回", fontSize = 8, height = 20, width = 36,
                backgroundColor = Config.Colors.red,
                textColor = { 255, 255, 255, 255 }, borderRadius = 3,
                onClick = function()
                    UI.Modal.Confirm({
                        title = "确认撤回",
                        message = "撤回广播 #" .. capturedId .. " [" .. (bc.title or "") .. "]?\n未领取的玩家将不再看到此邮件",
                        confirmText = "撤回",
                        cancelText = "取消",
                        onConfirm = function()
                            bcStatusLabel_:SetText("撤回中...")
                            bcStatusLabel_:SetStyle({ fontColor = Config.Colors.textSecond })
                            Mail.RevokeBroadcast(capturedId)
                        end,
                    })
                end,
            })
        end

        bcListPanel_:AddChild(row)
    end
end

--- 创建广播撤回管理分区
local function createBroadcastRevokeSection()
    bcStatusLabel_ = UI.Label {
        text = "", fontSize = 9, fontColor = Config.Colors.textSecond,
        textAlign = "center", width = "100%",
    }
    bcListPanel_ = UI.Panel {
        width = "100%", gap = 2, maxHeight = 180, overflow = "scroll",
    }

    return createSection("广播撤回", {
        UI.Button {
            text = "刷新广播记录",
            fontSize = 10, width = "100%", height = 28,
            backgroundColor = Config.Colors.blue,
            textColor = { 255, 255, 255, 255 }, borderRadius = 4,
            onClick = function()
                bcStatusLabel_:SetText("查询中...")
                bcStatusLabel_:SetStyle({ fontColor = Config.Colors.textSecond })
                bcData_ = {}
                if bcListPanel_ then bcListPanel_:ClearChildren() end
                Mail.FetchBroadcastList()
            end,
        },
        bcStatusLabel_,
        bcListPanel_,
    })
end

--- GM 广播历史列表回调(由 client_net.lua 转发)
function M.OnBroadcastList(eventData)
    local jsonStr = eventData["ListJson"]:GetString()
    local count   = eventData["Count"]:GetInt()

    local ok, list = pcall(cjson.decode, jsonStr)
    if ok and type(list) == "table" then
        bcData_ = list
    else
        bcData_ = {}
    end

    if bcStatusLabel_ then
        bcStatusLabel_:SetText("共 " .. count .. " 条广播记录")
        bcStatusLabel_:SetStyle({ fontColor = Config.Colors.textGreen })
    end

    renderBroadcastList()
end

-- ========== 版本管理 ==========
local versionStatusLabel_ = nil   -- 状态文本
local versionInfoLabel_ = nil     -- 版本信息显示
local versionInput_ = nil         -- 版本号输入框

--- 创建版本管理分区
local function createVersionSection()
    versionStatusLabel_ = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }
    versionInfoLabel_ = UI.Label {
        text = "点击[查询]获取当前版本信息",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        width = "100%",
    }
    versionInput_ = UI.TextField {
        placeholder = "输入最低版本号(如 1.0.42)",
        fontSize = 10,
        width = "100%",
        height = 26,
    }

    return createSection("版本管理", {
        -- 当前版本信息
        versionInfoLabel_,
        -- 查询按钮
        UI.Button {
            text = "查询当前版本设置",
            fontSize = 10,
            width = "100%",
            height = 28,
            backgroundColor = Config.Colors.blue,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                versionStatusLabel_:SetText("查询中...")
                versionStatusLabel_:SetStyle({ fontColor = Config.Colors.textSecond })
                GameCore.SendGameAction("gm_get_version", {})
            end,
        },
        -- 分隔
        UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border, marginTop = 4, marginBottom = 4 },
        -- 设置输入
        versionInput_,
        -- 设置按钮
        UI.Button {
            text = "设置最低版本号",
            fontSize = 10,
            width = "100%",
            height = 28,
            backgroundColor = Config.Colors.orange,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                local ver = versionInput_:GetText()
                if ver == "" then
                    versionStatusLabel_:SetText("请输入版本号")
                    versionStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                    return
                end
                -- 简单格式校验: 至少包含一个点号
                if not ver:match("^%d+%.%d+") then
                    versionStatusLabel_:SetText("版本号格式不正确(如 1.0.42)")
                    versionStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                    return
                end
                UI.Modal.Confirm({
                    title = "确认设置版本号",
                    message = "确定将最低版本号设置为 " .. ver .. " ?\n\n低于此版本的玩家将无法进入游戏,直到更新。",
                    confirmText = "确认设置",
                    cancelText = "取消",
                    onConfirm = function()
                        versionStatusLabel_:SetText("设置中...")
                        versionStatusLabel_:SetStyle({ fontColor = Config.Colors.textSecond })
                        GameCore.SendGameAction("gm_set_version", { version = ver })
                    end,
                })
            end,
        },
        versionStatusLabel_,
    })
end

--- 版本查询结果回调
---@param data table { requiredVersion=string, clientVersion=string }
function M.OnVersionInfo(data)
    local reqVer = data.requiredVersion or ""
    local clientVer = data.clientVersion or Config.VERSION
    if versionInfoLabel_ then
        local text = "客户端版本: v" .. clientVer
        if reqVer ~= "" then
            text = text .. "\n最低要求版本: v" .. reqVer
        else
            text = text .. "\n最低要求版本: 未设置"
        end
        versionInfoLabel_:SetText(text)
        versionInfoLabel_:SetStyle({ fontColor = Config.Colors.textPrimary })
    end
    if versionStatusLabel_ then
        versionStatusLabel_:SetText("查询成功")
        versionStatusLabel_:SetStyle({ fontColor = Config.Colors.textGreen })
    end
end

--- 区服管理分区(仅多人模式)
-- ========== 调试白名单管理 ==========
local debugListPanel_ = nil
local debugInput_ = nil
local debugStatusLabel_ = nil

local function refreshDebugListUI(list)
    if not debugListPanel_ then return end
    debugListPanel_:RemoveAllChildren()
    if not list or #list == 0 then
        debugListPanel_:AddChild(UI.Label {
            text = "(空)", fontSize = 9, fontColor = Config.Colors.textSecond, width = "100%",
        })
        return
    end
    for _, uid in ipairs(list) do
        debugListPanel_:AddChild(UI.Panel {
            flexDirection = "row", width = "100%", alignItems = "center",
            justifyContent = "space-between", height = 22,
            children = {
                UI.Label { text = tostring(uid), fontSize = 9, fontColor = Config.Colors.textPrimary },
                UI.Button {
                    text = "移除", fontSize = 8, height = 18, paddingHorizontal = 6,
                    backgroundColor = Config.Colors.red, textColor = {255,255,255,255},
                    borderRadius = 3,
                    onClick = function(self)
                        GameCore.SendGameAction("gm_debug_remove", { uid = uid })
                    end,
                },
            },
        })
    end
end

local function createDebugWhitelistSection()
    debugStatusLabel_ = UI.Label {
        text = "", fontSize = 9, fontColor = Config.Colors.textSecond,
        textAlign = "center", width = "100%",
    }
    debugInput_ = UI.TextField {
        placeholder = "输入用户 userId",
        fontSize = 10, width = "100%", height = 26,
    }
    debugListPanel_ = UI.Panel {
        width = "100%", gap = 2,
        children = {
            UI.Label { text = "点击[刷新]获取当前名单", fontSize = 9, fontColor = Config.Colors.textSecond, width = "100%" },
        },
    }
    return createSection("调试白名单", {
        UI.Label {
            text = "白名单用户登录后自动显示悬浮调试日志", fontSize = 8,
            fontColor = Config.Colors.textSecond, width = "100%",
        },
        debugInput_,
        UI.Panel {
            flexDirection = "row", width = "100%", gap = 4,
            children = {
                UI.Button {
                    text = "添加", fontSize = 10, flexGrow = 1, height = 28,
                    backgroundColor = Config.Colors.textGreen, textColor = {255,255,255,255},
                    borderRadius = 4,
                    onClick = function(self)
                        local uid = debugInput_:GetText()
                        if uid == "" then
                            debugStatusLabel_:SetText("请输入 userId")
                            debugStatusLabel_:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        GameCore.SendGameAction("gm_debug_add", { uid = uid })
                        debugInput_:SetText("")
                    end,
                },
                UI.Button {
                    text = "刷新名单", fontSize = 10, flexGrow = 1, height = 28,
                    backgroundColor = Config.Colors.blue, textColor = {255,255,255,255},
                    borderRadius = 4,
                    onClick = function(self)
                        GameCore.SendGameAction("gm_debug_list", {})
                    end,
                },
            },
        },
        debugStatusLabel_,
        UI.Panel { width = "100%", height = 1, backgroundColor = Config.Colors.border, marginTop = 4, marginBottom = 4 },
        UI.Label { text = "当前白名单:", fontSize = 9, fontColor = Config.Colors.textSecond, width = "100%" },
        debugListPanel_,
    })
end

--- 调试白名单列表回调
function M.OnDebugList(data)
    local list = data and data.list or {}
    refreshDebugListUI(list)
end

local function createServerSection()
    return createSection("区服管理", {
        UI.Button {
            text = "打开区服管理面板",
            fontSize = 10,
            width = "100%",
            height = 28,
            backgroundColor = Config.Colors.blue,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 4,
            onClick = function(self)
                ServerSelect.ShowGMServerModal()
            end,
        },
    })
end

-- ========== 玩家数据管理 ==========

-- 可编辑字段定义: { key, label, type }
local PLAYER_FIELDS = {
    { key = "playerName",     label = "道号",     editable = false },
    { key = "playerGender",   label = "性别",     editable = false },
    { key = "playerId",       label = "角色ID",   editable = false },
    { key = "serverId",       label = "区服ID",   editable = false },
    { key = "serverName",     label = "区服",     editable = false },
    { key = "lingshi",        label = "灵石",     editable = true,  valType = "int" },
    { key = "xiuwei",         label = "修为",     editable = true,  valType = "int" },
    { key = "stallLevel",     label = "摊位等级", editable = true,  valType = "int" },
    { key = "realmLevel",     label = "境界等级", editable = true,  valType = "int" },
    { key = "totalEarned",    label = "总收入",   editable = true,  valType = "int" },
    { key = "totalSold",      label = "总售出",   editable = true,  valType = "int" },
    { key = "totalCrafted",   label = "总炼丹",   editable = true,  valType = "int" },
    { key = "totalAdWatched", label = "看广告数", editable = true,  valType = "int" },
    { key = "dailyAdDate",    label = "广告日期", editable = true,  valType = "str" },
    { key = "ad_bless",       label = "广告:仙缘", editable = true, valType = "int",
      fromData = function(d) return d.dailyAdCounts and d.dailyAdCounts.bless or 0 end },
    { key = "ad_fortune",     label = "广告:横财", editable = true, valType = "int",
      fromData = function(d) return d.dailyAdCounts and d.dailyAdCounts.fortune or 0 end },
    { key = "ad_aid",         label = "广告:助力", editable = true, valType = "int",
      fromData = function(d) return d.dailyAdCounts and d.dailyAdCounts.aid or 0 end },
    { key = "ad_dungeon_ticket", label = "广告:秘境券", editable = true, valType = "int",
      fromData = function(d) return d.dailyAdCounts and d.dailyAdCounts.dungeon_ticket or 0 end },
    { key = "lifespan",       label = "寿命",     editable = true,  valType = "int" },
    { key = "rebirthCount",   label = "转世次数", editable = true,  valType = "int" },
    { key = "dead",           label = "已死亡",   editable = true,  valType = "bool" },
    { key = "fieldLevel",     label = "灵田等级", editable = false },
    { key = "dujieFreeUses",    label = "渡劫(免费)", editable = true, valType = "int" },
    { key = "dujiePaidUses",    label = "渡劫(付费)", editable = true, valType = "int" },
    { key = "dujieDailyDate",   label = "渡劫日期",   editable = true, valType = "str" },
    { key = "dungeon_lingcao",  label = "秘境:灵草",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonDailyUses and d.dungeonDailyUses.lingcao or 0 end },
    { key = "dungeon_liandan",  label = "秘境:炼丹",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonDailyUses and d.dungeonDailyUses.liandan or 0 end },
    { key = "dungeon_wanbao",   label = "秘境:万宝",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonDailyUses and d.dungeonDailyUses.wanbao or 0 end },
    { key = "dungeon_tianjie",  label = "秘境:天劫",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonDailyUses and d.dungeonDailyUses.tianjie or 0 end },
    { key = "dungeonDailyDate", label = "秘境日期",   editable = true, valType = "str" },
    -- 秘境探险券(广告奖励额外次数)
    { key = "bonus_lingcao",  label = "券:灵草",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonBonusUses and d.dungeonBonusUses.lingcao or 0 end },
    { key = "bonus_liandan",  label = "券:炼丹",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonBonusUses and d.dungeonBonusUses.liandan or 0 end },
    { key = "bonus_wanbao",   label = "券:万宝",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonBonusUses and d.dungeonBonusUses.wanbao or 0 end },
    { key = "bonus_tianjie",  label = "券:天劫",  editable = true, valType = "int",
      fromData = function(d) return d.dungeonBonusUses and d.dungeonBonusUses.tianjie or 0 end },
}

-- 玩家数据状态
local playerDataUid = ""
local playerDataResult = nil  -- 查询到的原始数据
local playerDataInputs = {}   -- key -> TextField 实例
local playerQueryStatus = nil -- 查询行状态文本
local playerDeadToggle = nil  -- dead 字段 Toggle
local playerDataModal = nil   -- 当前弹窗引用
local playerModalStatus = nil -- 弹窗内状态文本

--- 构建玩家数据管理分区
local function createPlayerDataSection()
    local uidInput = UI.TextField {
        placeholder = "平台UID / 角色ID / 角色名",
        fontSize = 10,
        width = "100%",
        height = 26,
        flexGrow = 1,
        flexShrink = 1,
    }

    playerQueryStatus = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }

    return createSection("玩家数据管理", {
        -- 查询行
        UI.Panel {
            flexDirection = "row",
            gap = 4,
            width = "100%",
            alignItems = "center",
            children = {
                UI.Panel {
                    flexGrow = 1,
                    flexShrink = 1,
                    children = { uidInput },
                },
                UI.Button {
                    text = "查询",
                    fontSize = 9,
                    width = 50,
                    height = 26,
                    backgroundColor = Config.Colors.blue,
                    textColor = { 255, 255, 255, 255 },
                    borderRadius = 4,
                    onClick = function(self)
                        local uid = (uidInput:GetText()):match("^%s*(.-)%s*$")
                        if uid == "" then
                            playerQueryStatus:SetText("请输入玩家 UID")
                            playerQueryStatus:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        playerDataUid = uid
                        playerDataResult = nil
                        playerQueryStatus:SetText("查询中...")
                        playerQueryStatus:SetStyle({ fontColor = Config.Colors.textSecond })

                        local ClientNet = require("network.client_net")
                        if not ClientNet.IsConnected() then
                            playerQueryStatus:SetText("未连接服务器")
                            playerQueryStatus:SetStyle({ fontColor = Config.Colors.red })
                            return
                        end
                        local vm = VariantMap()
                        vm["TargetUid"] = Variant(uid)
                        vm["ServerId"] = Variant(getGmServerId())
                        ClientNet.SendToServer(EVENTS.GM_PLAYER_QUERY, vm)
                    end,
                },
            },
        },
        playerQueryStatus,
    })
end

--- 弹窗展示玩家数据(查询结果 + 编辑 + 保存 + 封禁)
local function showPlayerDataModal(data, targetUid)
    local Modal = require("urhox-libs/UI/Widgets/Modal")

    -- 关闭旧弹窗
    if playerDataModal then
        pcall(function() playerDataModal:Close() end)
        playerDataModal = nil
    end

    playerDataInputs = {}
    playerDeadToggle = nil

    -- 自适应弹窗尺寸
    local dpr = graphics:GetDPR()
    local logicalW = graphics:GetWidth() / dpr
    local modalSize = logicalW < 500 and "sm" or "md"

    local modal = Modal({
        title = "玩家数据 - UID " .. targetUid,
        size = modalSize,
    })
    playerDataModal = modal

    -- 弹窗内状态文本
    playerModalStatus = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }

    -- 可滚动内容区
    local scrollBody = UI.Panel {
        width = "100%",
        flexGrow = 1, flexShrink = 1,
        overflow = "scroll", showScrollbar = false,
        gap = 2,
    }
    modal:AddContent(scrollBody)

    -- 字段列表
    for _, field in ipairs(PLAYER_FIELDS) do
        local val = field.fromData and field.fromData(data) or data[field.key]
        local valStr = ""
        if field.formatter then
            valStr = field.formatter(val)
        elseif field.valType == "bool" then
            valStr = val and "true" or "false"
        else
            valStr = tostring(val or "")
        end

        local rowChildren = {
            UI.Label {
                text = field.label,
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                width = 62,
            },
        }

        if not field.editable then
            table.insert(rowChildren, UI.Label {
                text = valStr,
                fontSize = 9,
                fontColor = Config.Colors.textPrimary,
                flexGrow = 1,
            })
        elseif field.valType == "bool" then
            playerDeadToggle = UI.Toggle {
                value = val == true,
                size = 18,
            }
            table.insert(rowChildren, playerDeadToggle)
        else
            local tf = UI.TextField {
                value = valStr,
                fontSize = 9,
                height = 22,
                flexGrow = 1,
                flexShrink = 1,
                textAlign = "right",
            }
            playerDataInputs[field.key] = tf
            table.insert(rowChildren, tf)
        end

        scrollBody:AddChild(UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            gap = 4,
            width = "100%",
            paddingVertical = 1,
            children = rowChildren,
        })
    end

    -- 状态文本
    scrollBody:AddChild(playerModalStatus)

    -- 保存按钮
    scrollBody:AddChild(UI.Button {
        text = "保存修改",
        fontSize = 10,
        width = "100%",
        height = 28,
        marginTop = 4,
        backgroundColor = Config.Colors.orange,
        textColor = { 255, 255, 255, 255 },
        borderRadius = 4,
        onClick = function(self)
            if not playerDataResult or playerDataUid == "" then return end

            local edits = {}
            for _, field in ipairs(PLAYER_FIELDS) do
                if field.editable then
                    if field.valType == "bool" then
                        local newVal = playerDeadToggle and playerDeadToggle:GetValue() or false
                        local oldVal = playerDataResult[field.key] == true
                        if newVal ~= oldVal then
                            edits[field.key] = newVal
                        end
                    elseif field.valType == "int" then
                        local tf = playerDataInputs[field.key]
                        if tf then
                            local newNum = tonumber(tf:GetText())
                            local oldVal = field.fromData and field.fromData(playerDataResult) or playerDataResult[field.key]
                            local oldNum = tonumber(oldVal) or 0
                            if newNum and newNum ~= oldNum then
                                edits[field.key] = math.floor(newNum)
                            end
                        end
                    elseif field.valType == "str" then
                        local tf = playerDataInputs[field.key]
                        if tf then
                            local newStr = tf:GetText()
                            local oldStr = tostring(playerDataResult[field.key] or "")
                            if newStr ~= oldStr then
                                edits[field.key] = newStr
                            end
                        end
                    end
                end
            end

            local hasChange = false
            for _ in pairs(edits) do hasChange = true; break end
            if not hasChange then
                playerModalStatus:SetText("没有修改")
                playerModalStatus:SetStyle({ fontColor = Config.Colors.textSecond })
                return
            end

            playerModalStatus:SetText("保存中...")
            playerModalStatus:SetStyle({ fontColor = Config.Colors.textSecond })

            local ClientNet = require("network.client_net")
            local vm = VariantMap()
            vm["TargetUid"] = Variant(playerDataUid)
            vm["EditJson"] = Variant(cjson.encode(edits))
            vm["ServerId"] = Variant(getGmServerId())
            ClientNet.SendToServer(EVENTS.GM_PLAYER_EDIT, vm)
        end,
    })

    -- 封禁/解封按钮
    local isBanned = data.banned == true
    scrollBody:AddChild(UI.Button {
        text = isBanned and "解封账号" or "封禁账号",
        fontSize = 10,
        width = "100%",
        height = 28,
        marginTop = 4,
        backgroundColor = isBanned and Config.Colors.textGreen or Config.Colors.red,
        textColor = { 255, 255, 255, 255 },
        borderRadius = 4,
        onClick = function(self)
            if not playerDataResult or playerDataUid == "" then return end
            local curBanned = playerDataResult.banned == true
            local action = curBanned and "gm_unban" or "gm_ban"
            local actionLabel = curBanned and "解封" or "封禁"
            UI.Modal.Confirm({
                title = actionLabel .. "确认",
                message = "确定" .. actionLabel .. "玩家 " .. playerDataUid .. " ?\n"
                    .. (curBanned and "解封后玩家可正常登录游戏" or "封禁后玩家将立即被踢出且无法登录"),
                confirmText = "确认",
                cancelText = "取消",
                onConfirm = function()
                    GameCore.SendGameAction(action, { uid = tonumber(playerDataUid) })
                    playerDataResult.banned = not curBanned
                    local newBanned = not curBanned
                    self:SetText(newBanned and "解封账号" or "封禁账号")
                    self:SetStyle({
                        backgroundColor = newBanned and Config.Colors.textGreen or Config.Colors.red,
                    })
                    playerModalStatus:SetText(newBanned and "已发送封禁请求" or "已发送解封请求")
                    playerModalStatus:SetStyle({ fontColor = Config.Colors.textSecond })
                end,
            })
        end,
    })

    modal:Open()
end

-- ========== 服务端回调 ==========

--- 玩家数据查询响应
function M.OnPlayerResp(eventData)
    local success = eventData["Success"]:GetBool()
    local targetUid = eventData["TargetUid"]:GetString()

    if not success then
        if playerQueryStatus then
            playerQueryStatus:SetText("查询失败: 玩家 " .. targetUid .. " 不存在或无数据")
            playerQueryStatus:SetStyle({ fontColor = Config.Colors.red })
        end
        return
    end

    local jsonStr = eventData["DataJson"]:GetString()
    local decOk, data = pcall(cjson.decode, jsonStr)
    if not decOk or type(data) ~= "table" then
        if playerQueryStatus then
            playerQueryStatus:SetText("数据解析失败")
            playerQueryStatus:SetStyle({ fontColor = Config.Colors.red })
        end
        return
    end

    playerDataResult = data
    playerDataUid = targetUid

    if playerQueryStatus then
        playerQueryStatus:SetText("查询成功: UID " .. targetUid)
        playerQueryStatus:SetStyle({ fontColor = Config.Colors.textGreen })
    end

    showPlayerDataModal(data, targetUid)
end

--- 玩家数据编辑响应
function M.OnPlayerEditResp(eventData)
    local success = eventData["Success"]:GetBool()
    local message = eventData["Message"]:GetString()

    -- 弹窗内状态文本反馈
    if playerModalStatus then
        if success then
            playerModalStatus:SetText(message)
            playerModalStatus:SetStyle({ fontColor = Config.Colors.textGreen })
        else
            playerModalStatus:SetText("编辑失败: " .. message)
            playerModalStatus:SetStyle({ fontColor = Config.Colors.red })
        end
    end
    -- 查询行也同步提示
    if playerQueryStatus then
        if success then
            playerQueryStatus:SetText(message)
            playerQueryStatus:SetStyle({ fontColor = Config.Colors.textGreen })
        else
            playerQueryStatus:SetText("编辑失败: " .. message)
            playerQueryStatus:SetStyle({ fontColor = Config.Colors.red })
        end
    end
end

-- ========== 全页接口 ==========

--- 刷新区服按钮列表
local function refreshRealmButtons()
    if not realmBtnPanel_ then return end
    realmBtnPanel_:ClearChildren()

    local srvList = ServerSelect.GetServerList()
    if #srvList == 0 then
        realmBtnPanel_:AddChild(UI.Label {
            text = "区服列表加载中...",
            fontSize = 9,
            fontColor = Config.Colors.textSecond,
            width = "100%",
        })
        realmBtnsBuilt_ = false
        return
    end

    -- 确保 gmServerId_ 有值
    if gmServerId_ == nil then
        gmServerId_ = State.state.serverId or 0
    end

    local allBtns = {}
    for _, srv in ipairs(srvList) do
        local btn = UI.Button {
            text = srv.name,
            fontSize = 8,
            paddingHorizontal = 6,
            height = 22,
            backgroundColor = (srv.id == gmServerId_) and Config.Colors.jadeDark or Config.Colors.panelLight,
            textColor = { 255, 255, 255, 255 },
            borderRadius = 3,
            onClick = function(self)
                gmServerId_ = srv.id
                if gmServerLabel_ then
                    gmServerLabel_:SetText("操作区服: " .. srv.name)
                end
                for _, b in ipairs(allBtns) do
                    b:SetStyle({ backgroundColor = Config.Colors.panelLight })
                end
                self:SetStyle({ backgroundColor = Config.Colors.jadeDark })
            end,
        }
        table.insert(allBtns, btn)
    end

    realmBtnPanel_:AddChild(UI.Panel {
        flexDirection = "row",
        flexWrap = "wrap",
        gap = 4,
        width = "100%",
        children = allBtns,
    })
    realmBtnsBuilt_ = true

    -- 更新标签显示当前选中区服名
    if gmServerLabel_ then
        local curName = "S" .. (gmServerId_ or 0)
        for _, srv in ipairs(srvList) do
            if srv.id == gmServerId_ then curName = srv.name; break end
        end
        gmServerLabel_:SetText("操作区服: " .. curName)
    end
end

--- 构建区服选择器(GM面板顶部)
local function createRealmSelector()
    -- 初始化为当前区服
    gmServerId_ = State.state.serverId or 0

    local currentSrv = ServerSelect.GetSelectedServer()
    local displayText = "操作区服: " .. (currentSrv and currentSrv.name or ("S" .. gmServerId_))

    gmServerLabel_ = UI.Label {
        text = displayText,
        fontSize = 10,
        fontColor = Config.Colors.textGold,
        fontWeight = "bold",
        flexGrow = 1,
        flexShrink = 1,
    }

    realmBtnPanel_ = UI.Panel {
        width = "100%",
        gap = 4,
    }
    realmBtnsBuilt_ = false

    -- 首次构建按钮
    refreshRealmButtons()

    return createSection("操作区服", {
        gmServerLabel_,
        realmBtnPanel_,
    })
end

--- 创建 GM 全页 (同 ui_stall 的 Create() 模式)
---@return table UI.ScrollView
function M.Create()
    local sections = {}

    ---@diagnostic disable-next-line: undefined-global
    local isMultiplayer = IsNetworkMode and IsNetworkMode()

    -- 多人模式下显示区服选择器
    if isMultiplayer then
        table.insert(sections, createRealmSelector())
    end

    table.insert(sections, createQuickActionsSection())
    table.insert(sections, createAnnouncementSection())
    table.insert(sections, createCDKSection())

    if isMultiplayer then
        table.insert(sections, createMailSection())
        table.insert(sections, createMailManageSection())
        table.insert(sections, createBroadcastRevokeSection())
        table.insert(sections, createPlayerDataSection())
        table.insert(sections, createVersionSection())
        table.insert(sections, createServerSection())
        table.insert(sections, createDebugWhitelistSection())
    end

    gmPanel = UI.ScrollView {
        id = "gm_page",
        width = "100%",
        flexGrow = 1,
        flexBasis = 0,
        showScrollbar = false,
        children = {
            UI.Panel {
                width = "100%",
                padding = 8,
                gap = 0,
                children = {
                    -- 页面标题
                    UI.Label {
                        text = "GM 管理面板",
                        fontSize = 14,
                        fontWeight = "bold",
                        fontColor = Config.Colors.red,
                        textAlign = "center",
                        width = "100%",
                        marginBottom = 8,
                    },
                    table.unpack(sections),
                },
            },
        },
    }
    return gmPanel
end

--- 服务端创建 CDK 成功回调
---@param data table { codes={...}, cdkType="single"|"universal", rewardName="..." }
function M.OnCdkCreated(data)
    generatedCDKs = data.codes or {}
    refreshCDKList()
    local typeName = data.cdkType == "universal" and "通用码" or "单人码"
    if cdkStatusLabel then
        cdkStatusLabel:SetText("已生成 " .. #generatedCDKs .. " 个" .. typeName
            .. " (" .. (data.rewardName or "") .. ")")
        cdkStatusLabel:SetStyle({ fontColor = Config.Colors.textGreen })
    end
    -- 弹出结果弹窗
    if #generatedCDKs > 0 then
        showCdkResultModal(generatedCDKs, data.rewardName or "", typeName)
    end
end

--- 刷新 GM 页面 (轻量，大部分内容为事件驱动)
function M.Refresh()
    -- 区服按钮尚未构建 → 检查列表是否已到达，动态刷新
    if not realmBtnsBuilt_ and realmBtnPanel_ then
        local srvList = ServerSelect.GetServerList()
        if #srvList > 0 then
            refreshRealmButtons()
        end
    end

end

return M
