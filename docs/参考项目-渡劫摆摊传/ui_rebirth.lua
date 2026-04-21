-- ============================================================================
-- ui_rebirth.lua — 陨落 + 转生界面
-- 寿元归零后弹出陨落弹窗, 玩家可选择转生重新开始
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local HUD = require("ui_hud")

local M = {}

--- 显示陨落弹窗(寿元归零时触发)
---@param onRebirthDone fun(summary: table) 转生完成后的回调
function M.ShowDeathModal(onRebirthDone)
    local realmIdx = State.GetRealmIndex()
    local realmName = Config.Realms[realmIdx].name

    -- 转生预览数据
    local keepRate = State.GetRebirthKeepRate()
    local keptLingshi = math.floor(State.state.lingshi * keepRate)
    local nextCount = State.state.rebirthCount + 1
    local rb = Config.Rebirth
    local nextBonus = math.min(nextCount * rb.bonusPerRebirth, rb.maxBonus)
    local nextLifespan = Config.Realms[1].lifespan + nextCount * rb.lifespanBonus
    local nextXiuwei = nextCount * rb.xiuweiBonus

    local modal = UI.Modal {
        title = "道消身陨",
        size = "sm",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        alignItems = "center",
        padding = 12,
        gap = 8,
        children = {
            -- 陨落信息
            UI.Label {
                text = "寿元耗尽，魂归天地...",
                fontSize = 14,
                fontColor = Config.Colors.red,
                fontWeight = "bold",
                textAlign = "center",
            },
            UI.Panel {
                width = "100%",
                backgroundColor = Config.Colors.bgLight,
                borderRadius = 8,
                padding = 10,
                gap = 4,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "本世修行",
                        fontSize = 11,
                        fontColor = Config.Colors.textSecond,
                    },
                    UI.Label {
                        text = "境界: " .. realmName,
                        fontSize = 12,
                        fontColor = Config.Colors.purple,
                    },
                    UI.Label {
                        text = "灵石: " .. HUD.FormatNumber(State.state.lingshi),
                        fontSize = 12,
                        fontColor = Config.Colors.textGold,
                    },
                    UI.Label {
                        text = "总售出: " .. HUD.FormatNumber(State.state.totalSold) .. " 件",
                        fontSize = 10,
                        fontColor = Config.Colors.textSecond,
                    },
                    UI.Label {
                        text = "总收入: " .. HUD.FormatNumber(State.state.totalEarned) .. " 灵石",
                        fontSize = 10,
                        fontColor = Config.Colors.textSecond,
                    },
                },
            },
            -- 转生预览
            UI.Panel {
                width = "100%",
                backgroundColor = { 45, 35, 60, 240 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = Config.Colors.purple,
                padding = 10,
                gap = 4,
                children = {
                    UI.Label {
                        text = "转生 (第" .. nextCount .. "世)",
                        fontSize = 13,
                        fontColor = Config.Colors.purple,
                        fontWeight = "bold",
                        textAlign = "center",
                        width = "100%",
                    },
                    UI.Panel { width = "80%", height = 1, backgroundColor = Config.Colors.border, alignSelf = "center" },
                    UI.Label {
                        text = "保留灵石: " .. HUD.FormatNumber(keptLingshi)
                            .. " (" .. math.floor(keepRate * 100) .. "%)",
                        fontSize = 11,
                        fontColor = Config.Colors.textGold,
                    },
                    UI.Label {
                        text = "初始修为: " .. HUD.FormatNumber(nextXiuwei),
                        fontSize = 11,
                        fontColor = Config.Colors.purple,
                    },
                    UI.Label {
                        text = "初始寿元: " .. nextLifespan .. " 年",
                        fontSize = 11,
                        fontColor = Config.Colors.orange,
                    },
                    UI.Label {
                        text = "收益加成: +" .. math.floor(nextBonus * 100) .. "%",
                        fontSize = 11,
                        fontColor = Config.Colors.jade,
                    },
                    UI.Panel { width = "80%", height = 1, backgroundColor = Config.Colors.border, alignSelf = "center", marginTop = 2 },
                    UI.Label {
                        text = "境界重置为炼气，材料/商品/摊位清零",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                        textAlign = "center",
                        width = "100%",
                    },
                },
            },
        },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "踏入轮回，再修一世",
                fontSize = 13,
                width = 180,
                height = 38,
                backgroundColor = Config.Colors.purpleDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    modal:Close()
                    modal:Destroy()
                    if State.serverMode then
                        -- 服务端权威: 发送转生动作, 由服务端处理重置
                        -- 服务端完成后会发 rebirth_done 事件, main.lua 监听处理UI
                        local GameCore = require("game_core")
                        GameCore.SendGameAction("rebirth")
                    else
                        local summary = State.DoRebirth()
                        if onRebirthDone then
                            onRebirthDone(summary)
                        end
                    end
                end,
            },
        },
    })

    modal:Open()
end

return M
