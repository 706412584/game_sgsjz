-- ============================================================================
-- ui_log.lua — 开场剧情 Modal
-- 注: LogBar 已迁移至 ui_chat.lua，本模块仅保留 ShowStory
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")

local M = {}

local storyModal = nil

-- ========== 开场剧情 ==========

--- 显示开场剧情
---@param onComplete function 剧情播放完毕回调
function M.ShowStory(onComplete)
    local sceneIndex = 1

    storyModal = UI.Modal {
        title = "",
        size = "sm",
        closeOnOverlay = false,
        closeOnEscape = false,
        showCloseButton = false,
        onClose = function(self)
            self:Destroy()
            storyModal = nil
        end,
    }

    -- 创建内容面板
    local contentPanel = UI.Panel {
        width = "100%",
        alignItems = "center",
        justifyContent = "center",
        padding = 20,
        gap = 16,
        minHeight = 200,
        children = {},
    }

    local sceneTitle = UI.Label {
        id = "story_title",
        text = "",
        fontSize = 18,
        fontColor = Config.Colors.textGold,
        textAlign = "center",
    }

    local sceneText = UI.Label {
        id = "story_text",
        text = "",
        fontSize = 14,
        fontColor = Config.Colors.textPrimary,
        textAlign = "center",
        whiteSpace = "normal",
        lineHeight = 1.6,
    }

    local progressLabel = UI.Label {
        id = "story_progress",
        text = "",
        fontSize = 10,
        fontColor = Config.Colors.textSecond,
        textAlign = "center",
    }

    contentPanel:AddChild(sceneTitle)
    contentPanel:AddChild(sceneText)
    contentPanel:AddChild(progressLabel)

    storyModal:AddContent(contentPanel)

    --- 更新场景内容
    local function updateScene()
        local scene = Config.StoryScenes[sceneIndex]
        if not scene then return end

        sceneTitle:SetText(scene.title)
        sceneText:SetText(scene.text)
        progressLabel:SetText(sceneIndex .. " / " .. #Config.StoryScenes)
    end

    --- 前进
    local function nextScene()
        sceneIndex = sceneIndex + 1
        if sceneIndex > #Config.StoryScenes then
            -- 剧情结束
            storyModal:Close()
            State.state.storyPlayed = true
            if onComplete then onComplete() end
            return
        end
        updateScene()
    end

    -- 底部按钮
    storyModal:SetFooter(UI.Panel {
        flexDirection = "row",
        justifyContent = "space-between",
        width = "100%",
        children = {
            UI.Button {
                text = "跳过",
                fontSize = 11,
                backgroundColor = { 60, 60, 70, 200 },
                textColor = Config.Colors.textSecond,
                height = 32,
                width = 60,
                borderRadius = 6,
                onClick = function(self)
                    storyModal:Close()
                    State.state.storyPlayed = true
                    if onComplete then onComplete() end
                end,
            },
            UI.Button {
                id = "story_next_btn",
                text = "继续",
                fontSize = 12,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                height = 32,
                width = 80,
                borderRadius = 6,
                onClick = function(self)
                    nextScene()
                end,
            },
        },
    })

    updateScene()
    storyModal:Open()
end

return M
