-- ============================================================================
-- 《渡劫摆摊传》客户端入口
-- 多人模式时由引擎加载此文件（project.json → entry@client）
-- 职责：加载 main.lua 并委托 Start/Stop
-- ============================================================================

require "main"

-- 构建校验器要求入口文件包含 Start() 函数声明
-- require "main" 后全局 Start/Stop 已注册，先保存引用再覆盖以通过校验
local _mainStart = Start
local _mainStop = Stop

function Start()
    _mainStart()
end

function Stop()
    if _mainStop then _mainStop() end
end
