-- ============================================================================
-- 《问道长生》设置弹窗
-- 提供音乐/音效开关 + 音量滑块
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Audio = require("audio_manager")
local GamePlayer = require("game_player")
local GameServer = require("game_server")

local M = {}

-- 弹窗是否显示
local isVisible = false
local confirmDelete_ = false  -- 二次确认状态

-- 当前绑定的 overlay 容器（供 Show/Hide 直接操作）
local activeOverlay_ = nil

-- ============================================================================
-- 构建音频控制区块（开关 + 音量滑块）
-- label: 标签文字
-- enabled: 当前开关状态
-- volume: 当前音量 0~1
-- onToggle: function(newEnabled)
-- onVolume: function(newVolume)  -- newVolume: 0~100 整数
-- ============================================================================
local function BuildAudioSection(label, enabled, volume, onToggle, onVolume)
    local dotColor = enabled and Theme.colors.navActive or { 100, 90, 75, 200 }
    local volPercent = math.floor(volume * 100 + 0.5)

    return UI.Panel {
        width = "100%",
        gap = 8,
        paddingVertical = 10,
        children = {
            -- 第一行：标签 + 开关
            UI.Panel {
                width = "100%",
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                children = {
                    -- 左侧标签
                    UI.Panel {
                        flexDirection = "row",
                        gap = 8,
                        alignItems = "center",
                        children = {
                            UI.Panel {
                                width = 8, height = 8, borderRadius = 4,
                                backgroundColor = dotColor,
                            },
                            UI.Label {
                                text = label,
                                fontSize = Theme.fontSize.body,
                                fontColor = Theme.colors.textLight,
                            },
                        },
                    },
                    -- 右侧开关
                    UI.Panel {
                        width = 52, height = 26, borderRadius = 13,
                        backgroundColor = enabled and { 60, 160, 100, 255 } or { 60, 55, 45, 255 },
                        borderColor = enabled and Theme.colors.navActive or Theme.colors.border,
                        borderWidth = 1,
                        cursor = "pointer",
                        flexDirection = "row",
                        alignItems = "center",
                        padding = { 0, 2 },
                        onClick = function(self)
                            if onToggle then onToggle(not enabled) end
                        end,
                        children = {
                            enabled and UI.Panel { flexGrow = 1 } or nil,
                            UI.Panel {
                                width = 20, height = 20, borderRadius = 10,
                                backgroundColor = enabled and Theme.colors.white or { 140, 130, 110, 255 },
                            },
                            (not enabled) and UI.Panel { flexGrow = 1 } or nil,
                        },
                    },
                },
            },
            -- 第二行：音量滑块（仅开启时显示）
            enabled and UI.Panel {
                width = "100%",
                flexDirection = "row",
                alignItems = "center",
                gap = 8,
                paddingLeft = 16,
                children = {
                    UI.Label {
                        text = "音量",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textSecondary,
                        width = 28,
                    },
                    UI.Slider {
                        flex = 1,
                        height = 28,
                        min = 0,
                        max = 100,
                        value = volPercent,
                        onChange = function(self, value)
                            if onVolume then onVolume(value) end
                        end,
                    },
                    UI.Label {
                        text = volPercent .. "%",
                        fontSize = Theme.fontSize.small,
                        fontColor = Theme.colors.textLight,
                        width = 36,
                        textAlign = "right",
                    },
                },
            } or nil,
        },
    }
end

-- ============================================================================
-- 构建设置弹窗（全屏遮罩 + 居中面板）
-- onClose: 关闭回调
-- ============================================================================
function M.Build(onClose)
    isVisible = true

    local musicOn  = Audio.IsMusicEnabled()
    local sfxOn    = Audio.IsSFXEnabled()
    local musicVol = Audio.GetMusicVolume()
    local sfxVol   = Audio.GetSFXVolume()

    local function rebuild()
        if not isVisible then return end
        local Router = require("ui_router")
        Router.RebuildUI()
    end

    return UI.Panel {
        position = "absolute",
        top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center",
        alignItems = "center",
        onClick = function(self)
            isVisible = false
            if onClose then onClose() end
        end,
        children = {
            -- 弹窗面板
            UI.Panel {
                width = "82%",
                maxWidth = 340,
                backgroundColor = { 40, 35, 28, 245 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = 2,
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    -- 标题栏
                    UI.Panel {
                        width = "100%",
                        flexDirection = "row",
                        justifyContent = "space-between",
                        alignItems = "center",
                        marginBottom = 6,
                        children = {
                            UI.Label {
                                text = "设置",
                                fontSize = Theme.fontSize.heading,
                                fontWeight = "bold",
                                fontColor = Theme.colors.textGold,
                            },
                            UI.Panel {
                                width = 32, height = 32, borderRadius = 16,
                                backgroundColor = { 60, 55, 45, 200 },
                                justifyContent = "center",
                                alignItems = "center",
                                cursor = "pointer",
                                onClick = function(self)
                                    isVisible = false
                                    if onClose then onClose() end
                                end,
                                children = {
                                    UI.Label {
                                        text = "✕",
                                        fontSize = 16,
                                        fontColor = Theme.colors.textLight,
                                    },
                                },
                            },
                        },
                    },

                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = Theme.colors.divider,
                        spacing = 4,
                    },

                    -- 背景音乐（开关 + 音量）
                    BuildAudioSection("背景音乐", musicOn, musicVol,
                        function(newState)
                            Audio.SetMusicEnabled(newState)
                            rebuild()
                        end,
                        function(value)
                            Audio.SetMusicVolume(value / 100)
                        end
                    ),

                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = { 60, 55, 45, 80 },
                        spacing = 0,
                    },

                    -- 游戏音效（开关 + 音量）
                    BuildAudioSection("游戏音效", sfxOn, sfxVol,
                        function(newState)
                            Audio.SetSFXEnabled(newState)
                            rebuild()
                        end,
                        function(value)
                            Audio.SetSFXVolume(value / 100)
                        end
                    ),

                    UI.Divider {
                        orientation = "horizontal",
                        thickness = 1,
                        fontColor = { 60, 55, 45, 80 },
                        spacing = 4,
                    },

                    -- 删除角色（测试用）
                    (not confirmDelete_) and UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        marginTop = 4,
                        children = {
                            UI.Panel {
                                paddingLeft = 16, paddingRight = 16,
                                paddingTop = 8, paddingBottom = 8,
                                borderRadius = Theme.radius.md,
                                backgroundColor = { 80, 30, 30, 180 },
                                borderColor = { 160, 60, 60, 200 },
                                borderWidth = 1,
                                cursor = "pointer",
                                onClick = function(self)
                                    confirmDelete_ = true
                                    rebuild()
                                end,
                                children = {
                                    UI.Label {
                                        text = "删除角色（测试用）",
                                        fontSize = Theme.fontSize.small,
                                        fontColor = { 200, 100, 100, 255 },
                                    },
                                },
                            },
                        },
                    } or UI.Panel {
                        width = "100%",
                        gap = 8,
                        alignItems = "center",
                        marginTop = 4,
                        children = {
                            UI.Label {
                                text = "确定删除角色？数据将被清空！",
                                fontSize = Theme.fontSize.small,
                                fontColor = { 220, 80, 80, 255 },
                                textAlign = "center",
                            },
                            UI.Panel {
                                flexDirection = "row",
                                gap = 12,
                                children = {
                                    -- 确认删除
                                    UI.Panel {
                                        paddingLeft = 20, paddingRight = 20,
                                        paddingTop = 8, paddingBottom = 8,
                                        borderRadius = Theme.radius.md,
                                        backgroundColor = { 180, 40, 40, 220 },
                                        cursor = "pointer",
                                        onClick = function(self)
                                            confirmDelete_ = false
                                            -- 清空云端所有关联 key（player/pills/排行榜/货币）
                                            local playerKey = GameServer.GetServerKey("player")
                                            local pillsKey  = GameServer.GetServerKey("pills")
                                            local realmKey  = GameServer.GetGroupKey("realm")
                                            local powerKey  = GameServer.GetGroupKey("power")
                                            local wealthKey = GameServer.GetGroupKey("wealth")
                                            local function doReset()
                                                GamePlayer.Reset()
                                                isVisible = false
                                                if activeOverlay_ then
                                                    activeOverlay_:SetStyle({ pointerEvents = "none" })
                                                    activeOverlay_:ClearChildren()
                                                end
                                                local Router = require("ui_router")
                                                Router.EnterState(Router.STATE_TITLE)
                                            end
                                            ---@diagnostic disable-next-line: undefined-global
                                            if clientCloud then
                                                -- 1) BatchSet 清空 player/pills/排行榜
                                                ---@diagnostic disable-next-line: undefined-global
                                                clientCloud:BatchSet()
                                                    :Set(playerKey, {})
                                                    :Set(pillsKey, {})
                                                    :Delete(realmKey)
                                                    :Delete(powerKey)
                                                    :Delete(wealthKey)
                                                    :Save("delete_character", {
                                                        ok = function()
                                                            print("[Settings] 角色数据+排行榜已清空")
                                                        end,
                                                        error = function(code, reason)
                                                            print("[Settings] BatchSet清空失败:", code, reason)
                                                        end,
                                                    })
                                                -- 2) GameOps 清零货币（money 无法通过 BatchSet 操作）
                                                local GameOps = require("network.game_ops")
                                                GameOps.Request("delete_character", {}, function(ok, data)
                                                    if ok then
                                                        print("[Settings] 角色货币已清零")
                                                    else
                                                        print("[Settings] 货币清零失败:", data and data.msg or "unknown")
                                                    end
                                                    doReset()
                                                end)
                                            else
                                                doReset()
                                            end
                                        end,
                                        children = {
                                            UI.Label {
                                                text = "确认删除",
                                                fontSize = Theme.fontSize.small,
                                                fontWeight = "bold",
                                                fontColor = { 255, 220, 220, 255 },
                                            },
                                        },
                                    },
                                    -- 取消
                                    UI.Panel {
                                        paddingLeft = 20, paddingRight = 20,
                                        paddingTop = 8, paddingBottom = 8,
                                        borderRadius = Theme.radius.md,
                                        backgroundColor = { 60, 55, 45, 200 },
                                        borderColor = Theme.colors.border,
                                        borderWidth = 1,
                                        cursor = "pointer",
                                        onClick = function(self)
                                            confirmDelete_ = false
                                            rebuild()
                                        end,
                                        children = {
                                            UI.Label {
                                                text = "取消",
                                                fontSize = Theme.fontSize.small,
                                                fontColor = Theme.colors.textLight,
                                            },
                                        },
                                    },
                                },
                            },
                        },
                    },

                    -- 版本信息
                    UI.Panel {
                        width = "100%",
                        alignItems = "center",
                        marginTop = 10,
                        children = {
                            UI.Label {
                                text = "《问道长生》v0.1.0",
                                fontSize = Theme.fontSize.tiny,
                                fontColor = Theme.colors.textSecondary,
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 状态查询
-- ============================================================================
function M.IsVisible()
    return isVisible
end

function M.SetVisible(v)
    isVisible = v
end

-- ============================================================================
-- 全局 overlay 管理（避免 Router.RebuildUI）
-- ============================================================================

--- 绑定一个 overlay 容器，供 Show/Hide 动态操作
function M.BindOverlay(overlay)
    activeOverlay_ = overlay
end

--- 显示设置弹窗（通过 ClearChildren + AddChild 更新绑定的 overlay）
function M.Show()
    isVisible = true
    if activeOverlay_ then
        activeOverlay_:SetStyle({ pointerEvents = "auto" })
        activeOverlay_:ClearChildren()
        activeOverlay_:AddChild(M.Build(function()
            M.Hide()
        end))
    end
end

--- 隐藏设置弹窗
function M.Hide()
    isVisible = false
    if activeOverlay_ then
        activeOverlay_:SetStyle({ pointerEvents = "none" })
        activeOverlay_:ClearChildren()
    end
end

return M
