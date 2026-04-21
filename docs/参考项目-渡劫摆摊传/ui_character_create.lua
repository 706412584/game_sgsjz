-- ============================================================================
-- ui_character_create.lua — 角色创建弹窗 (道号 + 性别)
-- 首次进入游戏时弹出，选择性别和输入道号
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")

local M = {}

-- ========== 随机仙侠名生成器 ==========

local SURNAME_LIST = {
    "云", "风", "月", "星", "霜", "雪", "霞", "岚",
    "凌", "楚", "慕", "苏", "叶", "沐", "白", "青",
    "紫", "玄", "墨", "萧", "顾", "陆", "谢", "江",
    "韩", "林", "柳", "秦", "唐", "宋", "花", "上官",
}

local MALE_NAMES = {
    "无极", "天行", "长歌", "九霄", "清玄", "逸仙",
    "鸿影", "尘风", "御剑", "破晓", "玄渡", "离尘",
    "惊鸿", "归尘", "凌云", "渡劫", "不凡", "千机",
    "飞羽", "孤鹤", "傲天", "明轩", "子墨", "寒光",
    "重明", "念安", "辰逸", "清河", "一尘", "归一",
}

local FEMALE_NAMES = {
    "若雪", "灵犀", "幽兰", "清婉", "凝烟", "梦蝶",
    "落霞", "素心", "婉清", "画屏", "如烟", "碧瑶",
    "紫嫣", "冰凌", "倾城", "念卿", "月瑶", "飞雪",
    "轻吟", "含烟", "怜星", "梨落", "盼夏", "初雪",
    "锦书", "晴岚", "妙音", "霓裳", "玉露", "瑶光",
}

--- 生成一个随机仙侠名
---@param gender string "male"|"female"
---@return string
local function generateRandomName(gender)
    local surnames = SURNAME_LIST
    local names = gender == "female" and FEMALE_NAMES or MALE_NAMES
    local s = surnames[math.random(#surnames)]
    local n = names[math.random(#names)]
    return s .. n
end

-- ========== 角色创建弹窗 ==========

--- 显示角色创建弹窗
---@param onComplete fun(name: string, gender: string) 创建完成回调
function M.Show(onComplete)
    local selectedGender = "male"
    local inputName = generateRandomName("male")

    local modal = UI.Modal {
        title = "道号拜帖",
        size = "sm",
        closeOnOverlay = false,  -- 强制完成，不可跳过
        showCloseButton = false,
    }

    -- 性别选择按钮引用
    local maleBtn, femaleBtn
    local nameInput

    -- 刷新性别按钮样式
    local function refreshGenderBtns()
        if maleBtn then
            maleBtn:SetStyle({
                backgroundColor = selectedGender == "male"
                    and Config.Colors.jadeDark or Config.Colors.panelLight,
                borderColor = selectedGender == "male"
                    and Config.Colors.jade or Config.Colors.border,
            })
        end
        if femaleBtn then
            femaleBtn:SetStyle({
                backgroundColor = selectedGender == "female"
                    and Config.Colors.purpleDark or Config.Colors.panelLight,
                borderColor = selectedGender == "female"
                    and Config.Colors.purple or Config.Colors.border,
            })
        end
    end

    maleBtn = UI.Button {
        text = "少侠 (男)",
        fontSize = 12,
        flexGrow = 1,
        flexBasis = 0,
        height = 36,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = Config.Colors.jade,
        backgroundColor = Config.Colors.jadeDark,
        textColor = { 255, 255, 255, 255 },
        onClick = function(self)
            selectedGender = "male"
            refreshGenderBtns()
        end,
    }

    femaleBtn = UI.Button {
        text = "女侠 (女)",
        fontSize = 12,
        flexGrow = 1,
        flexBasis = 0,
        height = 36,
        borderRadius = 8,
        borderWidth = 1,
        borderColor = Config.Colors.border,
        backgroundColor = Config.Colors.panelLight,
        textColor = { 255, 255, 255, 255 },
        onClick = function(self)
            selectedGender = "female"
            refreshGenderBtns()
        end,
    }

    nameInput = UI.TextField {
        value = inputName,
        placeholder = "请输入道号(2-6字)",
        fontSize = 13,
        width = "100%",
        height = 36,
        borderRadius = 8,
        onChange = function(self, text)
            inputName = text
        end,
    }

    -- 随机名按钮
    local randomBtn = UI.Button {
        text = "随机道号",
        fontSize = 10,
        width = 72,
        height = 28,
        borderRadius = 6,
        backgroundColor = Config.Colors.panelLight,
        textColor = Config.Colors.textGold,
        borderWidth = 1,
        borderColor = Config.Colors.borderGold,
        onClick = function(self)
            inputName = generateRandomName(selectedGender)
            if nameInput and nameInput.SetValue then
                nameInput:SetValue(inputName)
            end
        end,
    }

    -- 提示文字
    local tipLabel = UI.Label {
        text = "",
        fontSize = 9,
        fontColor = Config.Colors.red,
        height = 14,
        textAlign = "center",
        width = "100%",
    }

    modal:AddContent(UI.Panel {
        width = "100%",
        padding = 12,
        gap = 10,
        children = {
            -- 欢迎文字
            UI.Label {
                text = "踏入修仙界，先留下道号",
                fontSize = 12,
                fontColor = Config.Colors.textGold,
                textAlign = "center",
                width = "100%",
            },

            -- 分割
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Config.Colors.border,
            },

            -- 性别选择
            UI.Label {
                text = "选择身份",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
            },
            UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 8,
                children = { maleBtn, femaleBtn },
            },

            -- 分割
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Config.Colors.border,
            },

            -- 道号输入
            UI.Label {
                text = "取一个道号",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
            },
            nameInput,
            UI.Panel {
                flexDirection = "row",
                justifyContent = "space-between",
                alignItems = "center",
                width = "100%",
                children = {
                    tipLabel,
                    randomBtn,
                },
            },
        },
    })

    modal:SetFooter(UI.Panel {
        width = "100%",
        alignItems = "center",
        children = {
            UI.Button {
                text = "踏入仙途",
                fontSize = 14,
                width = "100%",
                height = 40,
                backgroundColor = Config.Colors.jadeDark,
                textColor = { 255, 255, 255, 255 },
                borderRadius = 8,
                borderWidth = 1,
                borderColor = Config.Colors.jade,
                onClick = function(self)
                    -- 验证道号
                    local name = inputName or ""
                    -- 去除首尾空格
                    name = name:match("^%s*(.-)%s*$") or ""

                    if #name == 0 then
                        tipLabel:SetText("请输入道号")
                        return
                    end

                    -- UTF-8 字符计数
                    local charCount = 0
                    for _ in name:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                        charCount = charCount + 1
                    end

                    if charCount < 2 then
                        tipLabel:SetText("道号至少2个字")
                        return
                    end
                    if charCount > 6 then
                        tipLabel:SetText("道号最多6个字")
                        return
                    end

                    -- 保存角色信息（playerId 由服务端分配，客户端不再生成）
                    State.state.playerName = name
                    State.state.playerGender = selectedGender
                    State.Save()

                    -- 多人模式下同步玩家信息到服务端
                    ---@diagnostic disable-next-line: undefined-global
                    if IsNetworkMode and IsNetworkMode() then
                        -- 1. 通过 GameAction 持久化到服务端 gameState（下次登录不再弹创建弹窗）
                        local GameCore = require("game_core")
                        GameCore.SendGameAction("player_info", {
                            name = name,
                            gender = selectedGender,
                        })
                        -- 2. 推送玩家信息给聊天服务（解决聊天显示"无名修士"问题）
                        local ClientNet = require("network.client_net")
                        ClientNet.SendPlayerInfo(name, selectedGender, State.state.playerId)
                    end

                    modal:Close()
                    modal:Destroy()

                    if onComplete then
                        onComplete(name, selectedGender)
                    end
                end,
            },
        },
    })

    modal:Open()
end

return M
