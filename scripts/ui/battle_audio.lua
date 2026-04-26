------------------------------------------------------------
-- ui/battle_audio.lua  —— 战斗音效管理
-- 根据 action 类型和兵种自动播放对应音效
------------------------------------------------------------
local DT = require("data.data_troops")

local M = {}

---@type Scene
local audioScene_
---@type Node
local soundNode_
---@type table<string, Sound>
local soundCache_ = {}

-- 音效文件映射
local SFX = {
    normal_attack = "audio/sfx_normal_attack.ogg",
    skill_cast    = "audio/sfx_skill_cast.ogg",
    war_drum      = "audio/sfx_war_drum.ogg",
    dancer        = "audio/sfx_dancer.ogg",
    -- 策士系
    fire          = "audio/sfx_skill_fire.ogg",
    water         = "audio/sfx_skill_water.ogg",
    thunder       = "audio/sfx_skill_thunder.ogg",
    thorn         = "audio/sfx_skill_thorn.ogg",
    sun           = "audio/sfx_skill_sun.ogg",
    rockfall      = "audio/sfx_skill_rockfall.ogg",
}

-- 兵种 troopKey → 音效 key
local TROOP_SFX_MAP = {
    -- 火系
    fire_strategist     = "fire",
    fire_god            = "fire",
    -- 水系
    water_strategist    = "water",
    flood_strategist    = "water",
    -- 雷系
    thunder_mage        = "thunder",
    thunder_god         = "thunder",
    -- 其他策士
    thorn_mage          = "thorn",
    sun_mage            = "sun",
    rockfall_strategist = "rockfall",
    -- 辅助系
    dancer              = "dancer",
    war_drum            = "war_drum",
    supply              = "dancer",
    medic               = "dancer",
}

------------------------------------------------------------
-- 初始化：预加载所有音效
------------------------------------------------------------
function M.Init()
    soundCache_ = {}
    for key, path in pairs(SFX) do
        local snd = cache:GetResource("Sound", path)
        if snd then
            soundCache_[key] = snd
        else
            print("[BattleAudio] 加载失败: " .. path)
        end
    end
    -- 创建独立 Scene + 音效播放节点（客户端无 scene_ 全局变量）
    if not audioScene_ then
        audioScene_ = Scene()
    end
    soundNode_ = audioScene_:CreateChild("BattleSFX")
end

------------------------------------------------------------
-- 播放指定音效
------------------------------------------------------------
---@param sfxKey string SFX 表中的 key
---@param gain? number 音量 0~1，默认 0.6
local function playSfx(sfxKey, gain)
    local snd = soundCache_[sfxKey]
    if not snd or not soundNode_ then return end
    local src = soundNode_:CreateComponent("SoundSource")
    src.soundType = "Effect"
    src.gain = gain or 0.6
    src.autoRemoveMode = REMOVE_COMPONENT
    src:Play(snd)
end

------------------------------------------------------------
-- 根据 action 和单位信息播放音效
------------------------------------------------------------
---@param action table 战斗 action
---@param unitById table { [id] = unit }
function M.PlayActionSound(action, unitById)
    if not action or not action.actorId then return end
    local unit = unitById[action.actorId]
    if not unit then return end

    local troopKey = unit.troopKey
    local troopCat = unit.troopCat

    if action.type == "skill" then
        -- 战法释放：风呼啸
        playSfx("skill_cast", 0.5)
        return
    end

    if action.type == "counter" then
        -- 反击：普攻音效
        playSfx("normal_attack", 0.5)
        return
    end

    -- 普攻 / 其他
    if action.type == "attack" then
        -- 优先匹配具体兵种音效
        local sfxKey = troopKey and TROOP_SFX_MAP[troopKey]
        if sfxKey then
            playSfx(sfxKey, 0.6)
            -- 战鼓额外播放第二声
            if sfxKey == "war_drum" then
                playSfx("war_drum", 0.55)
            end
            return
        end

        -- 策士/辅助大类 fallback
        if troopCat == DT.CAT_MAGIC then
            playSfx("fire", 0.5)
            return
        end
        if troopCat == DT.CAT_SUPPORT then
            playSfx("dancer", 0.5)
            return
        end

        -- 步兵/骑兵/弓兵/机械 → 普攻撞击
        playSfx("normal_attack", 0.6)
    end
end

------------------------------------------------------------
-- 根据 action.extras 播放辅助效果音效
-- （增怒、减怒等由兵种被动产生的效果）
------------------------------------------------------------
---@param extras table[] action.extras 数组
function M.PlayExtrasSound(extras)
    if not extras then return end
    for _, ex in ipairs(extras) do
        if ex.type == "ally_morale" then
            playSfx("war_drum", 0.55)
        elseif ex.type == "enemy_morale_reduce" then
            playSfx("war_drum", 0.45)
        end
    end
end

------------------------------------------------------------
-- 清理
------------------------------------------------------------
function M.Clear()
    soundNode_ = nil
    audioScene_ = nil
end

return M
