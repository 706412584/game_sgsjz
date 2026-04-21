-- ============================================================================
-- ui_hud.lua — 顶部 HUD (灵石/修为/摊位等级)
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
---@type table
local Daily = nil
local function getDaily()
    if not Daily then Daily = require("ui_daily") end
    return Daily
end

local RedDot = require("ui_reddot")
local Images = Config.Images

local M = {}

local hudPanel = nil
local lingshiLabel = nil
local xiuweiLabel = nil
local xiuweiBar = nil
local realmLabel = nil
local stallLabel = nil

function M.Create()
    hudPanel = UI.Panel {
        id = "hud",
        width = "100%",
        height = 36,
        flexDirection = "row",
        alignItems = "center",
        paddingHorizontal = 8,
        paddingVertical = 2,
        gap = 5,
        backgroundColor = Config.Colors.panel,
        borderBottomWidth = 1,
        borderColor = Config.Colors.borderGold,
        children = {
            -- 灵石
            UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                gap = 3,
                children = {
                    UI.Panel { backgroundImage = Images.lingshi, backgroundFit = "contain", width = 14, height = 14 },
                    UI.Label {
                        id = "hud_lingshi",
                        text = "0",
                        fontSize = 12,
                        fontColor = Config.Colors.textGold,
                    },
                },
            },
            -- 分隔
            UI.Panel { width = 1, height = 16, backgroundColor = Config.Colors.border },
            -- 修为+境界+称号
            UI.Panel {
                flexGrow = 1,
                flexShrink = 1,
                gap = 1,
                children = {
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        gap = 2,
                        children = {
                            UI.Panel { backgroundImage = Images.xiuwei, backgroundFit = "contain", width = 12, height = 12 },
                            UI.Label {
                                id = "hud_realm",
                                text = "炼气",
                                fontSize = 10,
                                fontColor = Config.Colors.purple,
                            },

                        },
                    },
                    UI.ProgressBar {
                        id = "hud_xiuwei_bar",
                        value = 0,
                        height = 4,
                        variant = "primary",
                    },
                },
            },
            -- 分隔
            UI.Panel { width = 1, height = 16, backgroundColor = Config.Colors.border },
            -- 口碑 + 任务按钮
            UI.Panel {
                alignItems = "center",
                gap = 2,
                children = {
                    UI.Panel {
                        onClick = function() M.ShowReputationModal() end,
                        children = {
                            UI.Label {
                                id = "hud_reputation",
                                text = "口碑:无名",
                                fontSize = 8,
                                fontColor = Config.Colors.textGold,
                            },
                        },
                    },
                    UI.Button {
                        id = "hud_daily_btn",
                        text = "任务",
                        fontSize = 8,
                        height = 18,
                        paddingHorizontal = 6,
                        backgroundColor = { 60, 50, 30, 255 },
                        textColor = Config.Colors.textGold,
                        borderRadius = 4,
                        borderWidth = 1,
                        borderColor = Config.Colors.borderGold,
                        onClick = function() getDaily().Open() end,
                    },
                },
            },
            -- 分隔
            UI.Panel { width = 1, height = 16, backgroundColor = Config.Colors.border },
            -- 寿元 + 摊位 + 转生
            UI.Panel {
                alignItems = "flex-end",
                gap = 1,
                children = {
                    UI.Label {
                        id = "hud_rebirth",
                        text = "",
                        fontSize = 8,
                        fontColor = Config.Colors.purple,
                    },
                    UI.Label {
                        id = "hud_lifespan",
                        text = "寿100年",
                        fontSize = 9,
                        fontColor = Config.Colors.orange,
                    },
                    UI.Label {
                        id = "hud_stall",
                        text = "摊Lv1",
                        fontSize = 9,
                        fontColor = Config.Colors.jade,
                    },
                },
            },
        },
    }

    -- 绑定任务按钮红点
    local dailyBtn = hudPanel:FindById("hud_daily_btn")
    if dailyBtn then
        RedDot.Bind("daily", dailyBtn)
    end

    return hudPanel
end

function M.Refresh()
    if not hudPanel then return end

    local root = hudPanel

    -- 灵石
    local lbl = root:FindById("hud_lingshi")
    if lbl then
        lbl:SetText(M.FormatNumber(State.state.lingshi))
    end

    -- 境界
    local realmIdx = State.GetRealmIndex()
    local realmCfg = Config.Realms[realmIdx]
    local realmLbl = root:FindById("hud_realm")
    if realmLbl then
        realmLbl:SetText(realmCfg.name)
    end

    -- 修为进度条(基于下一境界突破门槛)
    local nextRealmIdx = realmIdx < #Config.Realms and (realmIdx + 1) or nil
    local nextXiuwei = nextRealmIdx and Config.Realms[nextRealmIdx].xiuwei or nil
    local curRealmXiuwei = realmCfg.xiuwei
    local xiuweiBarLocal = root:FindById("hud_xiuwei_bar")
    if xiuweiBarLocal then
        if nextXiuwei then
            local progress = (State.state.xiuwei - curRealmXiuwei) / (nextXiuwei - curRealmXiuwei)
            xiuweiBarLocal:SetValue(math.min(1, math.max(0, progress)))
        else
            xiuweiBarLocal:SetValue(1.0)
        end
    end

    -- 转生次数
    local rebirthLbl = root:FindById("hud_rebirth")
    if rebirthLbl then
        local rc = State.state.rebirthCount or 0
        if rc > 0 then
            rebirthLbl:SetText("第" .. (rc + 1) .. "世")
            rebirthLbl:Show()
        else
            rebirthLbl:SetText("")
            rebirthLbl:Hide()
        end
    end

    -- 寿元
    local lifespanLbl = root:FindById("hud_lifespan")
    if lifespanLbl then
        local ls = math.floor(State.state.lifespan)
        if ls >= 10000 then
            lifespanLbl:SetText("寿" .. M.FormatNumber(ls) .. "年")
        else
            lifespanLbl:SetText("寿" .. ls .. "年")
        end
        -- 寿元低时变红
        if ls <= 10 then
            lifespanLbl:SetStyle({ fontColor = Config.Colors.red })
        elseif ls <= 30 then
            lifespanLbl:SetStyle({ fontColor = Config.Colors.orange })
        else
            lifespanLbl:SetStyle({ fontColor = Config.Colors.orange })
        end
    end

    -- 摊位
    local stallLbl = root:FindById("hud_stall")
    if stallLbl then
        stallLbl:SetText("摊Lv" .. State.state.stallLevel)
    end

    -- 口碑等级
    local repLbl = root:FindById("hud_reputation")
    if repLbl then
        local repLevel = Config.GetReputationLevel(State.state.reputation or 100)
        repLbl:SetText("口碑:" .. repLevel.name)
        repLbl:SetStyle({ fontColor = repLevel.color or Config.Colors.textGold })
    end

    -- 每日任务红点由 RedDot 系统统一管理，无需手动刷新
end

-- ========== 口碑加成弹窗 ==========
function M.ShowReputationModal()
    local rep = State.state.reputation or 100
    local curLevel = Config.GetReputationLevel(rep)

    local modal = UI.Modal {
        title = "口碑详情",
        size = "sm",
        onClose = function(self) self:Destroy() end,
    }

    local rows = {}

    -- 当前口碑值
    table.insert(rows, UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        alignItems = "center",
        width = "100%",
        paddingVertical = 4,
        paddingHorizontal = 6,
        backgroundColor = { 40, 35, 25, 200 },
        borderRadius = 6,
        children = {
            UI.Label { text = "当前口碑", fontSize = 11, fontColor = Config.Colors.textSecond },
            UI.Label {
                text = curLevel.name .. "  (" .. rep .. "/" .. Config.REPUTATION_MAX .. ")",
                fontSize = 11, fontWeight = "bold",
                fontColor = curLevel.color or Config.Colors.textGold,
            },
        },
    })

    -- 当前加成
    table.insert(rows, UI.Label {
        text = "-- 当前加成 --", fontSize = 10,
        fontColor = Config.Colors.textSecond, textAlign = "center", width = "100%",
        marginTop = 6,
    })

    -- 售价加成
    local pricePct = math.floor(curLevel.priceBonus * 100 + 0.5)
    table.insert(rows, UI.Panel {
        flexDirection = "row", justifyContent = "space-between", width = "100%",
        paddingVertical = 2, paddingHorizontal = 6,
        children = {
            UI.Label { text = "售价加成", fontSize = 10, fontColor = Config.Colors.textPrimary },
            UI.Label {
                text = pricePct > 0 and ("+" .. pricePct .. "%") or "无",
                fontSize = 10, fontColor = pricePct > 0 and Config.Colors.textGold or Config.Colors.textSecond,
            },
        },
    })

    -- 顾客权重加成
    if curLevel.custBonus and next(curLevel.custBonus) then
        for ctId, bonus in pairs(curLevel.custBonus) do
            local ctName = ctId
            for _, ct in ipairs(Config.CustomerTypes) do
                if ct.id == ctId then ctName = ct.name; break end
            end
            table.insert(rows, UI.Panel {
                flexDirection = "row", justifyContent = "space-between", width = "100%",
                paddingVertical = 2, paddingHorizontal = 6,
                children = {
                    UI.Label { text = ctName .. "出现率", fontSize = 10, fontColor = Config.Colors.textPrimary },
                    UI.Label { text = "+" .. bonus, fontSize = 10, fontColor = Config.Colors.jade },
                },
            })
        end
    else
        table.insert(rows, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            paddingVertical = 2, paddingHorizontal = 6,
            children = {
                UI.Label { text = "顾客加成", fontSize = 10, fontColor = Config.Colors.textPrimary },
                UI.Label { text = "无", fontSize = 10, fontColor = Config.Colors.textSecond },
            },
        })
    end

    -- 等级列表
    table.insert(rows, UI.Label {
        text = "-- 口碑等级一览 --", fontSize = 10,
        fontColor = Config.Colors.textSecond, textAlign = "center", width = "100%",
        marginTop = 6,
    })

    for _, lvl in ipairs(Config.ReputationLevels) do
        local isCur = (lvl.threshold == curLevel.threshold)
        local bonusTexts = {}
        if lvl.priceBonus > 0 then
            table.insert(bonusTexts, "售价+" .. math.floor(lvl.priceBonus * 100 + 0.5) .. "%")
        end
        if lvl.custBonus then
            for ctId, bonus in pairs(lvl.custBonus) do
                local ctName = ctId
                for _, ct in ipairs(Config.CustomerTypes) do
                    if ct.id == ctId then ctName = ct.name; break end
                end
                table.insert(bonusTexts, ctName .. "+" .. bonus)
            end
        end
        local bonusStr = #bonusTexts > 0 and table.concat(bonusTexts, ", ") or "无加成"

        table.insert(rows, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            paddingVertical = 3, paddingHorizontal = 6,
            backgroundColor = isCur and { 60, 50, 20, 180 } or { 0, 0, 0, 0 },
            borderRadius = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", alignItems = "center", gap = 4, flexShrink = 1,
                    children = {
                        UI.Label {
                            text = lvl.name,
                            fontSize = 10, fontWeight = isCur and "bold" or "normal",
                            fontColor = lvl.color or Config.Colors.textPrimary,
                        },
                        UI.Label {
                            text = "(" .. lvl.threshold .. ")",
                            fontSize = 8, fontColor = Config.Colors.textSecond,
                        },
                    },
                },
                UI.Label {
                    text = bonusStr, fontSize = 9,
                    fontColor = isCur and Config.Colors.textGold or Config.Colors.textSecond,
                    flexShrink = 1,
                },
            },
        })
    end

    -- 口碑获取说明
    table.insert(rows, UI.Label {
        text = "-- 口碑变动规则 --", fontSize = 10,
        fontColor = Config.Colors.textSecond, textAlign = "center", width = "100%",
        marginTop = 6,
    })
    local gain = Config.ReputationGain
    local rules = {
        { "满足顾客需求", "+" .. gain.matched, Config.Colors.jade },
        { "卖出非需求物品", "+" .. gain.unmatched, Config.Colors.textSecond },
        { "顾客超时离开", tostring(gain.timeout), Config.Colors.red },
        { "连续满足" .. gain.streakAt .. "位", "+" .. gain.streakBonus, Config.Colors.textGold },
    }
    for _, r in ipairs(rules) do
        table.insert(rows, UI.Panel {
            flexDirection = "row", justifyContent = "space-between", width = "100%",
            paddingVertical = 2, paddingHorizontal = 6,
            children = {
                UI.Label { text = r[1], fontSize = 9, fontColor = Config.Colors.textPrimary },
                UI.Label { text = r[2], fontSize = 9, fontColor = r[3] },
            },
        })
    end

    modal:AddContent(UI.ScrollView {
        width = "100%", maxHeight = 320,
        children = {
            UI.Panel {
                width = "100%", gap = 3, padding = 4,
                children = rows,
            },
        },
    })

    modal:SetFooter(UI.Panel {
        flexDirection = "row", justifyContent = "center", width = "100%",
        children = {
            UI.Button {
                text = "关闭", variant = "secondary", width = 80,
                onClick = function() modal:Close() end,
            },
        },
    })

    modal:Open()
end

--- 数字格式化
---@param n number
---@return string
function M.FormatNumber(n)
    n = math.floor(n)
    if n >= 100000000 then
        return string.format("%.1f亿", n / 100000000)
    elseif n >= 1000000 then
        return string.format("%.1f万", n / 10000)
    elseif n >= 1000 then
        local s = tostring(n)
        -- 加千分位
        local result = ""
        local len = #s
        for i = 1, len do
            result = result .. s:sub(i, i)
            if (len - i) % 3 == 0 and i < len then
                result = result .. ","
            end
        end
        return result
    end
    return tostring(n)
end

return M
