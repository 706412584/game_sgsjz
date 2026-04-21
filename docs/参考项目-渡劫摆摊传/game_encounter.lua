-- ============================================================================
-- game_encounter.lua — 随机奇遇事件系统
-- 每 EncounterInterval 秒检测一次，EncounterChance 概率触发
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local HUD = require("ui_hud")

local M = {}

local encounterTimer = 0

--- 权重随机选择奇遇
---@return table encounter
local function randomEncounter()
    local total = 0
    for _, e in ipairs(Config.Encounters) do
        total = total + e.weight
    end
    local roll = math.random() * total
    local accum = 0
    for _, e in ipairs(Config.Encounters) do
        accum = accum + e.weight
        if roll <= accum then return e end
    end
    return Config.Encounters[1]
end

--- 发放奇遇奖励
---@param encounter table
---@return string rewardText
local function applyReward(encounter)
    local parts = {}
    local r = encounter.reward
    -- 奖励随境界缩放: 每提升一个境界+30%
    local realmScale = 1.0 + (State.state.realmLevel - 1) * 0.3
    if r.lingshi then
        local v = math.floor(r.lingshi * realmScale)
        State.AddLingshi(v)
        table.insert(parts, "+" .. v .. " 灵石")
    end
    if r.xiuwei then
        local v = math.floor(r.xiuwei * realmScale)
        State.AddXiuwei(v)
        table.insert(parts, "+" .. v .. " 修为")
    end
    if r.lingcao then
        local v = math.floor(r.lingcao * realmScale)
        State.AddMaterial("lingcao", v)
        table.insert(parts, "+" .. v .. " 灵草")
    end
    if r.lingzhi then
        local v = math.floor(r.lingzhi * realmScale)
        State.AddMaterial("lingzhi", v)
        table.insert(parts, "+" .. v .. " 灵纸")
    end
    if r.xuantie then
        local v = math.floor(r.xuantie * realmScale)
        State.AddMaterial("xuantie", v)
        table.insert(parts, "+" .. v .. " 玄铁")
    end
    return table.concat(parts, ", ")
end

--- 显示奇遇弹窗
---@param encounter table
local function showEncounterModal(encounter)
    local rewardText = applyReward(encounter)

    local modal = UI.Modal {
        title = "奇遇! " .. encounter.name,
        size = "sm",
        closeOnOverlay = false,
        showCloseButton = false,
        onClose = function(self) self:Destroy() end,
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        alignItems = "center",
        padding = 12,
        gap = 8,
        children = {
            UI.Label {
                text = encounter.desc,
                fontSize = 12,
                fontColor = Config.Colors.textPrimary,
                textAlign = "center",
            },
            UI.Label {
                text = rewardText,
                fontSize = 14,
                fontColor = Config.Colors.textGold,
                fontWeight = "bold",
                textAlign = "center",
            },
        },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "收下",
                fontSize = 12,
                width = 80,
                height = 32,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    modal:Close()
                end,
            },
        },
    })

    modal:Open()
end

--- 初始化：服务端模式下监听 encounter_triggered 事件
local inited_ = false
function M.Init()
    if inited_ then return end
    inited_ = true

    if State.serverMode then
        State.On("encounter_triggered", function(data)
            if data and data.name then
                showServerEncounterModal(data)
            end
        end)
    end
end

--- 显示服务端推送的奇遇弹窗（奖励已由服务端发放）
---@param data table {name, desc, rewardText}
local function _showServerEncounterModal(data)
    local modal = UI.Modal {
        title = "奇遇! " .. (data.name or ""),
        size = "sm",
        closeOnOverlay = false,
        showCloseButton = false,
        onClose = function(self) self:Destroy() end,
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        alignItems = "center",
        padding = 12,
        gap = 8,
        children = {
            UI.Label {
                text = data.desc or "",
                fontSize = 12,
                fontColor = Config.Colors.textPrimary,
                textAlign = "center",
            },
            UI.Label {
                text = data.rewardText or "",
                fontSize = 14,
                fontColor = Config.Colors.textGold,
                fontWeight = "bold",
                textAlign = "center",
            },
        },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "收下",
                fontSize = 12,
                width = 80,
                height = 32,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                onClick = function(self)
                    modal:Close()
                end,
            },
        },
    })

    modal:Open()
end
showServerEncounterModal = _showServerEncounterModal

--- 每帧调用，检测是否触发奇遇
---@param dt number
function M.Update(dt)
    -- 服务端模式：奇遇由服务端驱动，客户端不主动触发
    if State.serverMode then return end

    -- 新手引导未完成时不触发
    if State.state.tutorialStep < 6 then return end

    encounterTimer = encounterTimer + dt
    if encounterTimer < Config.EncounterInterval then return end
    encounterTimer = encounterTimer - Config.EncounterInterval

    if math.random() > Config.EncounterChance then return end

    local encounter = randomEncounter()
    State.state.lastEncounterTime = os.time()
    -- 播放奇遇音效(避免循环依赖, 直接播放)
    local sfxPath = Config.SFX and Config.SFX.encounter
    if sfxPath then
        local snd = cache:GetResource("Sound", sfxPath)
        if snd and scene_ then
            local n = scene_:CreateChild("SFX_Encounter")
            local src = n:CreateComponent("SoundSource")
            src.soundType = "Effect"
            src.gain = 0.6
            src.autoRemoveMode = REMOVE_COMPONENT
            src:Play(snd)
        end
    end
    showEncounterModal(encounter)
end

return M
