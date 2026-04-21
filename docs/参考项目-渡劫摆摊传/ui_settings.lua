-- ============================================================================
-- ui_settings.lua — 设置弹窗
-- BGM/SFX 开关 + 玩家ID显示/复制
-- ============================================================================
local UI = require("urhox-libs/UI")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local ServerSelect = require("ui_server")
local StartScreen = require("ui_start")

local M = {}

-- ========== 设置弹窗 ==========

function M.ShowSettingsModal()
    local modal = UI.Modal {
        title = "设置",
        size = "sm",
        onClose = function(self) self:Destroy() end,
    }

    -- BGM 开关
    local bgmEnabled = State.state.bgmEnabled ~= false  -- 默认开启
    local bgmToggle = UI.Toggle {
        value = bgmEnabled,
        label = "背景音乐",
        onChange = function(self, checked)
            State.state.bgmEnabled = checked
            M.SetBGMEnabled(checked)
            State.Save()
        end,
    }

    -- SFX 开关
    local sfxEnabled = State.state.sfxEnabled ~= false  -- 默认开启
    local sfxToggle = UI.Toggle {
        value = sfxEnabled,
        label = "游戏音效",
        onChange = function(self, checked)
            State.state.sfxEnabled = checked
            GameCore.SetSFXEnabled(checked)
            State.Save()
        end,
    }

    -- 玩家 ID + 用户 ID
    local playerId = State.GetPlayerId()
    local GM = require("ui_gm")
    local userIdVal = GM.GetUserId()
    local userIdStr = (userIdVal ~= 0) and tostring(userIdVal) or "未获取"

    local copyResultLabel = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textGreen,
        height = 14,
    }

    local qqCopyResult = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.textGreen,
        height = 14,
    }

    modal:AddContent(UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        showScrollbar = false,
        children = { UI.Panel {
        width = "100%",
        padding = 12,
        gap = 8,
        children = {
            -- 音频设置
            UI.Label {
                text = "-- 音频 --",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
            },
            bgmToggle,
            sfxToggle,

            -- 分割
            UI.Panel {
                width = "100%",
                height = 1,
                backgroundColor = Config.Colors.border,
                marginVertical = 2,
            },

            -- 玩家信息
            UI.Label {
                text = "-- 玩家信息 --",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
            },
            -- 道号
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "道号: " .. State.GetDisplayName(),
                        fontSize = 12,
                        fontColor = Config.Colors.textGold,
                        fontWeight = "bold",
                        flexGrow = 1,
                        flexShrink = 1,
                    },
                    UI.Label {
                        text = State.state.playerGender == "female" and "女侠" or "少侠",
                        fontSize = 9,
                        fontColor = State.state.playerGender == "female"
                            and Config.Colors.purple or Config.Colors.jade,
                    },
                },
            },
            -- 当前区服
            M._buildServerRow(),
            -- 玩家 ID
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 6,
                children = {
                    UI.Label {
                        text = "角色ID: " .. playerId,
                        fontSize = 10,
                        fontColor = Config.Colors.textSecond,
                        flexGrow = 1,
                    },
                    UI.Button {
                        text = "复制",
                        fontSize = 9,
                        width = 48,
                        height = 24,
                        backgroundColor = Config.Colors.jadeDark,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function(self)
                            if PlatformUtils.IsWebPlatform() then
                                copyResultLabel:SetText("请手动记录 ID")
                                copyResultLabel:SetStyle({ fontColor = Config.Colors.textGold })
                                return
                            end
                            ---@diagnostic disable-next-line: undefined-global
                            pcall(function()
                                ---@diagnostic disable-next-line: undefined-global
                                ui:SetUseSystemClipboard(true)
                                ---@diagnostic disable-next-line: undefined-global
                                ui:SetClipboardText(playerId)
                            end)
                            copyResultLabel:SetText("已复制!")
                            copyResultLabel:SetStyle({ fontColor = Config.Colors.textGreen })
                        end,
                    },
                },
            },
            copyResultLabel,
            -- 用户 ID（平台 userId）
            UI.Label {
                text = "用户ID: " .. userIdStr,
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
            },

            -- 分割
            UI.Panel {
                width = "100%",
                height = 1,
                backgroundColor = Config.Colors.border,
                marginVertical = 2,
            },

            -- QQ群信息
            UI.Label {
                text = "-- 加入社区 --",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
            },
            UI.Label {
                text = "QQ群: 1098193873",
                fontSize = 13,
                fontColor = Config.Colors.textGold,
                textAlign = "center",
                width = "100%",
            },
            UI.Button {
                text = "复制群号",
                fontSize = 12,
                width = "100%",
                height = 34,
                backgroundColor = Config.Colors.blue,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 6,
                onClick = function(self)
                    local qqGroupNumber = "1098193873"
                    local copied = false
                    pcall(function()
                        ---@diagnostic disable-next-line: undefined-global
                        ui:SetUseSystemClipboard(true)
                        ---@diagnostic disable-next-line: undefined-global
                        ui:SetClipboardText(qqGroupNumber)
                        copied = true
                    end)
                    if copied then
                        qqCopyResult:SetText("已复制群号，打开QQ搜索加入!")
                        qqCopyResult:SetStyle({ fontColor = Config.Colors.textGreen })
                    else
                        qqCopyResult:SetText("请手动搜索群号: " .. qqGroupNumber)
                        qqCopyResult:SetStyle({ fontColor = Config.Colors.textGold })
                    end
                end,
            },
            qqCopyResult,

            -- 版本号
            UI.Panel {
                width = "100%",
                height = 1,
                backgroundColor = Config.Colors.border,
                marginVertical = 2,
            },
            UI.Label {
                text = "v" .. Config.VERSION,
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
            },
        },
    } },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        flexDirection = "row",
        justifyContent = "center",
        gap = 12,
        children = {
            UI.Button {
                text = "退出游戏",
                fontSize = 12,
                width = 80,
                height = 30,
                backgroundColor = Config.Colors.red,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    UI.Modal.Confirm({
                        title = "退出游戏",
                        message = "确定退出游戏?\n将返回开始界面",
                        confirmText = "确定",
                        cancelText = "取消",
                        onConfirm = function()
                            modal:Close()
                            -- 断开网络连接
                            local ClientNet = require("network.client_net")
                            if ClientNet.IsConnected() then
                                ClientNet.Disconnect()
                            end
                            -- 返回开始界面
                            StartScreen.Show()
                        end,
                    })
                end,
            },
            UI.Button {
                text = "关闭",
                fontSize = 12,
                width = 60,
                height = 30,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textPrimary,
                borderRadius = 8,
                onClick = function(self) modal:Close() end,
            },
        },
    })

    modal:Open()
end

-- ========== BGM 控制 (由 main.lua 注入) ==========
---@type SoundSource|nil
M._bgmSource = nil

--- 注入 BGM 音源引用(由 main.lua 调用)
---@param source SoundSource|nil
function M.SetBGMSource(source)
    M._bgmSource = source
end

--- 设置 BGM 开关
---@param enabled boolean
function M.SetBGMEnabled(enabled)
    if M._bgmSource then
        M._bgmSource.gain = enabled and 0.35 or 0
    end
end

--- 从存档恢复设置
function M.RestoreSettings()
    -- BGM
    local bgmEnabled = State.state.bgmEnabled ~= false
    M.SetBGMEnabled(bgmEnabled)
    -- SFX
    local sfxEnabled = State.state.sfxEnabled ~= false
    GameCore.SetSFXEnabled(sfxEnabled)
end

-- ========== 内部构建辅助 ==========

--- 构建设置弹窗中的区服显示行
function M._buildServerRow()
    local srv = ServerSelect.GetSelectedServer()
    local serverChildren = {}
    if srv then
        local sColor = Config.Colors.textSecond
        local st = srv.status
        if st == "正常" then
            sColor = Config.Colors.textGreen
        elseif st == "火爆" then
            sColor = Config.Colors.orange
        elseif st == "维护" then
            sColor = Config.Colors.red
        end
        table.insert(serverChildren, UI.Label {
            text = "区服: " .. srv.name,
            fontSize = 12,
            fontColor = Config.Colors.textPrimary,
            flexGrow = 1,
            flexShrink = 1,
        })
        table.insert(serverChildren, UI.Label {
            text = st,
            fontSize = 10,
            fontColor = sColor,
        })
    else
        table.insert(serverChildren, UI.Label {
            text = "区服: 未选择",
            fontSize = 12,
            fontColor = Config.Colors.textSecond,
            flexGrow = 1,
        })
    end
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 6,
        children = serverChildren,
    }
end

return M
