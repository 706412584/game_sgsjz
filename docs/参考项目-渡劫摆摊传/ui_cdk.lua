-- ============================================================================
-- ui_cdk.lua — CDK 兑换码系统
-- 格式: DJBT-XXXX-XXXX，客户端校验 + 防重复
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local HUD = require("ui_hud")
local GameCore = require("game_core")

local M = {}

-- ========== CDK 校验 ==========

--- DJBX33A hash
---@param s string
---@return number
local function djb2Hash(s)
    local h = 5381
    for i = 1, #s do
        h = ((h << 5) + h + string.byte(s, i)) & 0xFFFFFFFF
    end
    return h
end

--- 校验 CDK 格式和校验和
--- 格式: DJBT-XXXX-XXXX (大写字母+数字)
---@param code string
---@return boolean valid
---@return string? rewardKey
function M.ValidateCDK(code)
    code = code:upper():gsub("%s", "")
    -- 格式检查
    local prefix, part1, part2 = code:match("^(%u+)-(%w+)-(%w+)$")
    if not prefix or prefix ~= Config.CDK_PREFIX then
        return false, nil
    end
    if #part1 ~= 4 or #part2 ~= 4 then
        return false, nil
    end

    -- 从 part2 最后一位提取校验字符
    local payload = prefix .. part1 .. part2:sub(1, 3)
    local checkChar = part2:sub(4, 4)
    local hash = djb2Hash(payload)
    local expectedCheck = string.char(string.byte("A") + (hash % 26))

    if checkChar ~= expectedCheck then
        return false, nil
    end

    -- 查找奖励 key: 使用 part1 的前几个字符映射
    -- 简单映射: 遍历 CDKRewards 看是否有匹配
    for key, _ in pairs(Config.CDKRewards) do
        if part1:sub(1, #key) == key or part1 == key:sub(1, 4) then
            return true, key
        end
    end

    -- 默认给第一个奖励
    for key, _ in pairs(Config.CDKRewards) do
        return true, key
    end

    return false, nil
end

--- 兑换 CDK
---@param code string
---@return boolean success
---@return string message
---@return table|nil reward  兑换成功时返回奖励配置对象
function M.RedeemCDK(code)
    code = code:upper():gsub("%s", "")

    -- 检查是否已兑换
    for _, used in ipairs(State.state.redeemedCDKs) do
        if used == code then
            return false, "该兑换码已使用", nil
        end
    end

    local valid, rewardKey = M.ValidateCDK(code)
    if not valid then
        return false, "无效的兑换码", nil
    end

    local reward = Config.CDKRewards[rewardKey]
    if not reward then
        return false, "奖励不存在", nil
    end

    -- 发放奖励
    if reward.lingshi then State.AddLingshi(reward.lingshi) end
    if reward.xiuwei then State.AddXiuwei(reward.xiuwei) end
    if reward.materials then
        for matId, amount in pairs(reward.materials) do
            State.AddMaterial(matId, amount)
        end
    end
    if reward.adFree and reward.adFreeDays then
        State.ActivateAdFree(reward.adFreeDays)
    end

    -- 记录已兑换
    table.insert(State.state.redeemedCDKs, code)
    State.Save()

    return true, reward.name .. " 兑换成功!", reward
end

--- 生成合法 CDK (供 GM 使用)
---@param rewardKey string
---@return string code
function M.GenerateCDK(rewardKey)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local function randChar()
        local idx = math.random(1, #chars)
        return chars:sub(idx, idx)
    end

    local part1 = rewardKey:sub(1, 4)
    while #part1 < 4 do part1 = part1 .. randChar() end
    part1 = part1:upper()

    local part2_prefix = randChar() .. randChar() .. randChar()
    local payload = Config.CDK_PREFIX .. part1 .. part2_prefix
    local hash = djb2Hash(payload)
    local checkChar = string.char(string.byte("A") + (hash % 26))
    local part2 = part2_prefix .. checkChar

    return Config.CDK_PREFIX .. "-" .. part1 .. "-" .. part2
end

-- ========== CDK 弹窗 ==========

function M.ShowCDKModal()
    local modal = UI.Modal {
        title = "兑换码",
        size = "sm",
        onClose = function(self) self:Destroy() end,
    }

    local resultLabel = UI.Label {
        id = "cdk_result",
        text = "输入兑换码领取奖励",
        fontSize = 10,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
        width = "100%",
    }

    local cdkInput = UI.TextField {
        id = "cdk_input",
        placeholder = "DJBT-XXXX-XXXX",
        fontSize = 14,
        width = "100%",
        height = 36,
        textAlign = "center",
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        padding = 12,
        gap = 10,
        alignItems = "center",
        children = {
            cdkInput,
            resultLabel,
        },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 10,
        children = {
            UI.Button {
                text = "兑换",
                fontSize = 12,
                width = 80,
                height = 32,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    local code = cdkInput:GetText()
                    if not code or code == "" then
                        resultLabel:SetText("请输入兑换码")
                        resultLabel:SetStyle({ fontColor = Config.Colors.red })
                        return
                    end
                    -- 多人模式: 走服务端验证和发放
                    if State.serverMode then
                        GameCore.SendGameAction("gm_cdk", { code = code })
                        resultLabel:SetText("兑换中...")
                        resultLabel:SetStyle({ fontColor = Config.Colors.textSecond })
                        return
                    end
                    -- 单机模式: 本地校验
                    local ok, msg, reward = M.RedeemCDK(code)
                    resultLabel:SetText(msg)
                    resultLabel:SetStyle({
                        fontColor = ok and Config.Colors.textGreen or Config.Colors.red,
                    })
                    if ok and reward then
                        M.ShowRewardModal(reward)
                    end
                end,
            },
            UI.Button {
                text = "关闭",
                fontSize = 12,
                width = 60,
                height = 32,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textPrimary,
                borderRadius = 8,
                onClick = function(self)
                    modal:Close()
                end,
            },
        },
    })

    modal:Open()
end

-- ========== 奖励详情弹窗 ==========

--- 兑换成功后展示奖励内容
---@param reward table CDKRewards 配置项 { name, lingshi, xiuwei, materials }
function M.ShowRewardModal(reward)
    local rewardModal = UI.Modal {
        title = "兑换成功",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    -- 构建奖励列表
    local rewardItems = {}

    if reward.lingshi and reward.lingshi > 0 then
        table.insert(rewardItems, UI.Label {
            text = "+" .. HUD.FormatNumber(reward.lingshi) .. " 灵石",
            fontSize = 14,
            fontColor = Config.Colors.textGold,
            fontWeight = "bold",
        })
    end

    if reward.xiuwei and reward.xiuwei > 0 then
        table.insert(rewardItems, UI.Label {
            text = "+" .. reward.xiuwei .. " 修为",
            fontSize = 12,
            fontColor = Config.Colors.purple,
        })
    end

    if reward.materials then
        for matId, amount in pairs(reward.materials) do
            local mat = Config.GetMaterialById(matId)
            if mat and amount > 0 then
                table.insert(rewardItems, UI.Label {
                    text = "+" .. amount .. " " .. mat.name,
                    fontSize = 11,
                    fontColor = mat.color,
                })
            end
        end
    end

    if reward.adFree and reward.adFreeDays then
        table.insert(rewardItems, UI.Label {
            text = "免广告特权 " .. reward.adFreeDays .. "天",
            fontSize = 13,
            fontColor = Config.Colors.gold,
            fontWeight = "bold",
        })
    end

    -- 丹药奖励
    if reward.products and type(reward.products) == "table" then
        for prodId, amount in pairs(reward.products) do
            local prod = Config.GetProductById(prodId)
            if prod and amount > 0 then
                table.insert(rewardItems, UI.Label {
                    text = "+" .. amount .. " " .. prod.name,
                    fontSize = 12,
                    fontColor = prod.color,
                })
            end
        end
    end

    -- 珍藏物品奖励
    if reward.collectibles and type(reward.collectibles) == "table" then
        for itemId, count in pairs(reward.collectibles) do
            local coll = Config.GetCollectibleById(itemId)
            if coll and count > 0 then
                table.insert(rewardItems, UI.Label {
                    text = "+" .. count .. " " .. coll.name,
                    fontSize = 12,
                    fontColor = coll.color,
                })
            end
        end
    end

    rewardModal:AddContent(UI.Panel {
        width = "100%",
        alignItems = "center",
        padding = 16,
        gap = 8,
        children = {
            UI.Label {
                text = reward.name or "兑换礼包",
                fontSize = 15,
                fontColor = Config.Colors.textGold,
                fontWeight = "bold",
            },
            UI.Panel {
                gap = 4,
                alignItems = "center",
                paddingVertical = 6,
                children = rewardItems,
            },
            UI.Label {
                text = "奖励已发放至账户",
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
            },
        },
    })

    rewardModal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "好的",
                fontSize = 12,
                width = 80,
                height = 32,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    rewardModal:Close()
                end,
            },
        },
    })

    rewardModal:Open()
end

return M
