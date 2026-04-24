-- ============================================================================
-- 《问道长生》音频管理器
-- 统一管理 BGM 和音效的播放、暂停、音量、开关
-- ============================================================================

local M = {}

-- 状态
local audioScene = nil
local bgmNode    = nil
local bgmSource  = nil
local sfxNode    = nil

-- 设置（默认开启）
local musicEnabled = true
local sfxEnabled   = true
local musicVolume  = 0.55
local sfxVolume    = 0.55

-- 当前 BGM 路径
local currentBGM = ""
local bgmPaused = false
local bgmPausedByFocus = false  -- 切后台导致的暂停（与手动暂停区分）

-- ============================================================================
-- 初始化（在 Start 中调用一次）
-- ============================================================================
function M.Init()
    if audioScene then return end
    audioScene = Scene()
    bgmNode = audioScene:CreateChild("BGM")
    sfxNode = audioScene:CreateChild("SFX")

    -- 切后台自动暂停音频，回前台自动恢复
    SubscribeToEvent("InputFocus", "HandleAudioInputFocus")
end

--- 应用焦点变化处理（切后台/回前台）
---@param eventType string
---@param eventData InputFocusEventData
function HandleAudioInputFocus(eventType, eventData)
    local hasFocus = eventData:GetBool("Focus")
    local isMinimized = eventData:GetBool("Minimized")

    if not hasFocus or isMinimized then
        -- 切后台：暂停所有音频
        if bgmSource and bgmSource.playing and not bgmPaused then
            bgmSource:SetGain(0)
            bgmPausedByFocus = true
        end
    else
        -- 回前台：恢复音频
        if bgmPausedByFocus then
            if bgmSource and musicEnabled then
                bgmSource:SetGain(musicVolume)
            end
            bgmPausedByFocus = false
        end
    end
end

-- ============================================================================
-- BGM 控制
-- ============================================================================

--- 播放背景音乐
---@param path string 资源路径，如 "audio/bgm_meditation.ogg"
---@param volume? number 可选音量 0~1
function M.PlayBGM(path, volume)
    if not bgmNode then return end
    if volume then musicVolume = volume end
    currentBGM = path

    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("[AudioManager] BGM not found: " .. path)
        return
    end
    sound.looped = true

    -- 复用或创建 SoundSource
    if not bgmSource then
        bgmSource = bgmNode:CreateComponent("SoundSource")
        bgmSource.soundType = SOUND_MUSIC
    end
    bgmSource:SetGain(musicEnabled and musicVolume or 0)
    bgmSource:Play(sound)
end

--- 停止背景音乐
function M.StopBGM()
    if bgmSource then
        bgmSource:Stop()
    end
    currentBGM = ""
end

--- 暂停背景音乐（可恢复）
function M.PauseBGM()
    if bgmSource and bgmSource.playing then
        bgmSource:SetGain(0)
        bgmPaused = true
    end
end

--- 恢复背景音乐
function M.ResumeBGM()
    if bgmSource and bgmPaused then
        bgmSource:SetGain(musicEnabled and musicVolume or 0)
        bgmPaused = false
    end
end

--- 背景音乐是否正在播放
---@return boolean
function M.IsBGMPlaying()
    return bgmSource ~= nil and bgmSource.playing and not bgmPaused
end

--- 设置音乐开关
---@param enabled boolean
function M.SetMusicEnabled(enabled)
    musicEnabled = enabled
    if bgmSource then
        bgmSource:SetGain(enabled and musicVolume or 0)
    end
end

--- 获取音乐开关状态
---@return boolean
function M.IsMusicEnabled()
    return musicEnabled
end

--- 设置音乐音量
---@param vol number 0~1
function M.SetMusicVolume(vol)
    musicVolume = vol
    if bgmSource and musicEnabled then
        bgmSource:SetGain(vol)
    end
end

--- 获取音乐音量
---@return number
function M.GetMusicVolume()
    return musicVolume
end

-- ============================================================================
-- 音效控制
-- ============================================================================

--- 播放一次性音效
---@param path string 资源路径
---@param volume? number 可选音量 0~1
function M.PlaySFX(path, volume)
    if not sfxEnabled then return end
    if not sfxNode then return end

    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    sound.looped = false

    local source = sfxNode:CreateComponent("SoundSource")
    source.soundType = SOUND_EFFECT
    source:SetGain(volume or sfxVolume)
    source.autoRemoveMode = REMOVE_COMPONENT
    source:Play(sound)
end

-- 循环音效（氛围音）管理
local loopSources = {}  -- { [key] = SoundSource }

--- 播放循环音效（氛围音），同一 key 不会重复创建
---@param key string 唯一标识
---@param path string 资源路径
---@param volume? number 可选音量 0~1
function M.PlayLoop(key, path, volume)
    if not sfxNode then return end
    if loopSources[key] then return end  -- 已在播放

    local sound = cache:GetResource("Sound", path)
    if not sound then return end
    sound.looped = true

    local source = sfxNode:CreateComponent("SoundSource")
    source.soundType = SOUND_EFFECT
    source:SetGain(volume or sfxVolume * 0.7)
    source:Play(sound)
    loopSources[key] = source
end

--- 停止循环音效
---@param key string
function M.StopLoop(key)
    local source = loopSources[key]
    if source then
        source:Stop()
        sfxNode:RemoveComponent(source)
        loopSources[key] = nil
    end
end

--- 停止所有循环音效
function M.StopAllLoops()
    for k, source in pairs(loopSources) do
        source:Stop()
        sfxNode:RemoveComponent(source)
    end
    loopSources = {}
end

--- 设置音效开关
---@param enabled boolean
function M.SetSFXEnabled(enabled)
    sfxEnabled = enabled
end

--- 获取音效开关状态
---@return boolean
function M.IsSFXEnabled()
    return sfxEnabled
end

--- 设置音效音量
---@param vol number 0~1
function M.SetSFXVolume(vol)
    sfxVolume = vol
end

--- 获取音效音量
---@return number
function M.GetSFXVolume()
    return sfxVolume
end

return M
