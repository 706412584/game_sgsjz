-- ============================================================================
-- ui_rank.lua — 仙界排行榜 (3维度: 灵石/修为/总收入)
-- 基于 clientCloud GetRankList + GetUserNickname
-- ============================================================================
local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local M = {}

-- ========== 头像(与 ui_chat.lua 一致) ==========
local AVATAR_MALE_KEYS = { "zongmen" }
local AVATAR_FEMALE_KEYS = { "zongmen_f" }

--- 根据 userId+gender 确定性选取头像路径
---@param userId number
---@param gender string "male"|"female"
---@return string
local function getAvatarPath(userId, gender)
    local pool = (gender == "female") and AVATAR_FEMALE_KEYS or AVATAR_MALE_KEYS
    local idx = (userId % #pool) + 1
    local key = pool[idx]
    return Config.Images[key] or Config.Images.sanxiu
end

-- ========== 区服 key 前缀(与 server_player.lua 一致) ==========
--- 根据当前区服生成带后缀的存储 key
---@param baseKey string
---@return string
local function realmKey(baseKey)
    local sid = State.state.serverId
    if not sid or sid == 0 then return baseKey end
    return baseKey .. "_" .. tostring(sid)
end

-- ========== 排行榜维度 ==========
--- 获取排行榜 Tab 列表(今日榜 key 随日期变化, 自动加区服前缀)
---@return table[]
local function getRankTabs()
    local todayKey = realmKey("earned_" .. State.GetTodayKey())
    return {
        { key = todayKey,                  label = "今日榜",   unit = "灵石" },
        { key = realmKey("lingshi"),       label = "灵石榜",   unit = "灵石" },
        { key = realmKey("realmLevel"),    label = "境界榜",   unit = "境界",  formatValue = function(v)
            local realm = Config.Realms[v]
            return realm and realm.name or ("Lv." .. v)
        end },
        { key = realmKey("totalEarned"),   label = "总收入榜", unit = "灵石" },
        { key = realmKey("fengshuiLevel"), label = "风水榜",   unit = "等级",  formatValue = function(v)
            return "Lv." .. v
        end },
    }
end

-- 前三名颜色
local RANK_COLORS = {
    Config.Colors.textGold,   -- #1 金
    { 200, 200, 210, 255 },   -- #2 银
    { 205, 145, 80, 255 },    -- #3 铜
}

-- ========== 玩家信息弹窗 ==========

--- 显示玩家信息弹窗
---@param entry table { userId, nickname, gender, playerId, lingshi, realmLevel, rank, value }
local function showPlayerInfoModal(entry)
    local gender = entry.gender or "male"
    local genderText = (gender == "female") and "女" or "男"
    local genderColor = (gender == "female") and Config.Colors.pink or Config.Colors.jade
    local avatarPath = getAvatarPath(entry.userId or 0, gender)

    -- 境界名称
    local realmName = "炼气"
    local rl = entry.realmLevel or 1
    local realm = Config.Realms[rl]
    if realm then realmName = realm.name end

    local modal = UI.Modal {
        title = "仙友信息",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    -- 信息行组件
    ---@param label string
    ---@param value string
    ---@param valueColor table|nil
    ---@param canCopy boolean|nil
    local function infoRow(label, value, valueColor, canCopy)
        local rowChildren = {
            UI.Label {
                text = label .. ":",
                fontSize = 10,
                fontColor = Config.Colors.textSecond,
                flexShrink = 0,
            },
            UI.Label {
                text = value,
                fontSize = 10,
                fontColor = valueColor or Config.Colors.textPrimary,
                flexGrow = 1,
                flexShrink = 1,
            },
        }
        if canCopy then
            table.insert(rowChildren, UI.Button {
                text = "复制",
                fontSize = 8,
                height = 20,
                paddingHorizontal = 6,
                borderRadius = 3,
                backgroundColor = Config.Colors.panelLight,
                textColor = Config.Colors.textSecond,
                onClick = function(self)
                    ---@diagnostic disable-next-line: undefined-global
                    ui:SetClipboardText(value)
                    self:SetText("已复制")
                end,
            })
        end
        return UI.Panel {
            flexDirection = "row",
            alignItems = "center",
            width = "100%",
            gap = 6,
            paddingVertical = 3,
            children = rowChildren,
        }
    end

    modal:AddContent(UI.Panel {
        width = "100%",
        gap = 8,
        padding = 8,
        alignItems = "center",
        children = {
            -- 头像 + 名字
            UI.Panel {
                alignItems = "center",
                gap = 6,
                children = {
                    -- 头像(圆形)
                    UI.Panel {
                        width = 52, height = 52,
                        borderRadius = 26,
                        overflow = "hidden",
                        borderWidth = 2,
                        borderColor = genderColor,
                        backgroundImage = avatarPath,
                    },
                    -- 道号
                    UI.Label {
                        text = entry.nickname or "未知",
                        fontSize = 13,
                        fontWeight = "bold",
                        fontColor = Config.Colors.textPrimary,
                    },
                    -- 排名+境界
                    UI.Label {
                        text = "#" .. (entry.rank or "?") .. "  " .. realmName,
                        fontSize = 10,
                        fontColor = Config.Colors.textGold,
                    },
                    -- 在线状态
                    UI.Label {
                        id = "online_status_label",
                        text = "...",
                        fontSize = 9,
                        fontColor = Config.Colors.textSecond,
                    },
                },
            },
            -- 分割线
            UI.Panel {
                width = "100%", height = 1,
                backgroundColor = Config.Colors.border,
            },
            -- 信息列表
            UI.Panel {
                width = "100%",
                gap = 2,
                children = {
                    infoRow("性别", genderText, genderColor),
                    infoRow("境界", realmName, Config.Colors.textGold),
                    infoRow("用户ID", tostring(entry.userId or ""), nil, true),
                    infoRow("角色ID", entry.playerId ~= "" and entry.playerId or "-", nil, entry.playerId ~= ""),
                },
            },
        },
    })

    -- 异步查询在线状态
    local targetId = tonumber(entry.userId) or 0
    if targetId > 0 then
        local function onOnlineResult(data)
            if tonumber(data.targetId) == targetId then
                local lbl = modal:FindById("online_status_label")
                if lbl then
                    if data.online then
                        lbl:SetText("在线")
                        lbl:SetFontColor(Config.Colors.green)
                    else
                        lbl:SetText("离线")
                        lbl:SetFontColor(Config.Colors.textSecond)
                    end
                end
            end
        end
        State.On("online_status_result", onOnlineResult)
        modal.props.onClose = function(self)
            State.Off("online_status_result", onOnlineResult)
            self:Destroy()
        end
        GameCore.SendGameAction("check_online", { targetId = tostring(targetId) })
    end

    modal:Open()
end

-- ========== 排行榜弹窗 ==========

function M.ShowRankModal()
    local RANK_TABS = getRankTabs()
    local currentKey = RANK_TABS[1].key
    local currentFormatValue = nil  -- 当前 tab 的自定义格式化函数
    local rankListPanel = nil
    local myRankLabel = nil
    local tabBtns = {}

    local modal = UI.Modal {
        title = "仙界排行榜",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    -- 刷新 Tab 样式
    local function refreshTabStyles()
        for _, tab in ipairs(RANK_TABS) do
            local btn = tabBtns[tab.key]
            if btn then
                if tab.key == currentKey then
                    btn:SetStyle({
                        backgroundColor = Config.Colors.jadeDark,
                    })
                else
                    btn:SetStyle({
                        backgroundColor = Config.Colors.panelLight,
                    })
                end
            end
        end
    end

    -- 今日榜 key (用于判断当前 tab 是否是今日榜)
    local todayTabKey = RANK_TABS[1].key

    -- 构建称号前缀文本
    -- 排行称号(天命/先驱等)只在今日榜显示; 境界称号在所有榜显示
    ---@param entry table {rank, realmLevel, ...}
    ---@return string prefix 称号文本(可能为空)
    ---@return table|nil color 称号颜色
    local function buildTitlePrefix(entry)
        local parts = {}
        local titleColor = nil

        -- 排行称号: 仅在今日榜 tab 才显示
        if currentKey == todayTabKey then
            local rankTitle = Config.GetRankTitle(entry.rank)
            if rankTitle then
                table.insert(parts, rankTitle.title)
                titleColor = rankTitle.color
            end
        end

        -- 境界称号: 所有榜都显示(基于 realmLevel)
        local rl = entry.realmLevel or 1
        local realmTitle = Config.GetRealmTitle(rl)
        if realmTitle then
            table.insert(parts, realmTitle.title)
            if not titleColor then
                titleColor = realmTitle.color
            end
        end

        if #parts == 0 then
            return "", nil
        end
        return "【" .. table.concat(parts, "·") .. "】", titleColor
    end

    -- 渲染排行列表
    ---@param entries table[]
    local function renderList(entries)
        if not rankListPanel then return end
        rankListPanel:ClearChildren()

        if #entries == 0 then
            rankListPanel:AddChild(UI.Label {
                text = "暂无数据，快去摆摊吧!",
                fontSize = 11,
                fontColor = Config.Colors.textSecond,
                textAlign = "center",
                width = "100%",
                paddingVertical = 20,
            })
            return
        end

        for _, entry in ipairs(entries) do
            local rankColor = RANK_COLORS[entry.rank] or Config.Colors.textPrimary
            local bgColor = entry.isMe
                and { 50, 75, 55, 220 }
                or Config.Colors.panelLight
            local gender = entry.gender or "male"
            local avatarPath = getAvatarPath(entry.userId or 0, gender)

            -- 构建称号前缀
            local prefix, prefixColor = buildTitlePrefix(entry)
            local nameChildren = {}
            if prefix ~= "" then
                table.insert(nameChildren, UI.Label {
                    text = prefix,
                    fontSize = 9,
                    fontColor = prefixColor or Config.Colors.textGold,
                })
            end
            table.insert(nameChildren, UI.Label {
                text = entry.nickname .. (entry.isMe and " (我)" or ""),
                fontSize = 10,
                fontColor = entry.isMe and Config.Colors.jade or Config.Colors.textPrimary,
                flexShrink = 1,
            })

            rankListPanel:AddChild(UI.Panel {
                flexDirection = "row",
                alignItems = "center",
                width = "100%",
                paddingHorizontal = 6,
                paddingVertical = 4,
                gap = 4,
                backgroundColor = bgColor,
                borderRadius = 4,
                borderWidth = entry.isMe and 1 or 0,
                borderColor = entry.isMe and Config.Colors.jade or { 0, 0, 0, 0 },
                children = {
                    -- 排名
                    UI.Label {
                        text = "#" .. entry.rank,
                        fontSize = 11,
                        fontColor = rankColor,
                        fontWeight = entry.rank <= 3 and "bold" or "normal",
                        width = 22,
                    },
                    -- 头像(可点击)
                    UI.Button {
                        width = 28, height = 28,
                        borderRadius = 14,
                        padding = 0,
                        overflow = "hidden",
                        backgroundImage = avatarPath,
                        borderWidth = 1,
                        borderColor = (gender == "female") and Config.Colors.pink or Config.Colors.jadeDark,
                        onClick = function(self)
                            showPlayerInfoModal(entry)
                        end,
                    },
                    -- 称号+昵称
                    UI.Panel {
                        flexDirection = "row",
                        alignItems = "center",
                        flexGrow = 1,
                        flexShrink = 1,
                        gap = 1,
                        overflow = "hidden",
                        children = nameChildren,
                    },
                    -- 数值
                    UI.Label {
                        text = currentFormatValue and currentFormatValue(entry.value) or HUD.FormatNumber(entry.value),
                        fontSize = 11,
                        fontColor = Config.Colors.textGold,
                        fontWeight = "bold",
                    },
                },
            })
        end
    end

    -- 加载排行榜数据
    local function fetchAndDisplay()
        if not rankListPanel then return end

        -- 显示加载中
        rankListPanel:ClearChildren()
        rankListPanel:AddChild(UI.Label {
            text = "加载中...",
            fontSize = 11,
            fontColor = Config.Colors.textSecond,
            textAlign = "center",
            width = "100%",
            paddingVertical = 20,
        })
        if myRankLabel then
            myRankLabel:SetText("查询中...")
        end

        -- 刷新自己的今日排名缓存(供称号加成使用)
        State.RefreshMyTodayRank()

        -- 获取排行榜 top 20, 附带额外字段
        local extraRealmLevel = realmKey("realmLevel")
        local extraPlayerName = realmKey("playerName")
        local extraPlayerGender = realmKey("playerGender")
        local extraPlayerId = realmKey("playerId")
        local extraLingshi = realmKey("lingshi")

        clientCloud:GetRankList(currentKey, 0, 20, {
            ok = function(rankList)
                if not rankListPanel then return end

                local entries = {}
                for i, item in ipairs(rankList) do
                    -- playerName/playerGender/playerId 通过 Set() 存储, 在 item.score 中
                    local pName = item.score and item.score[extraPlayerName] or nil
                    if type(pName) ~= "string" or pName == "" then
                        pName = nil
                    end
                    local pGender = item.score and item.score[extraPlayerGender] or nil
                    if type(pGender) ~= "string" or pGender == "" then
                        pGender = "male"
                    end
                    local pId = item.score and item.score[extraPlayerId] or nil
                    if type(pId) ~= "string" then pId = "" end

                    table.insert(entries, {
                        rank = i,
                        userId = item.userId,
                        value = item.iscore[currentKey] or 0,
                        realmLevel = item.iscore[extraRealmLevel] or 1,
                        lingshi = item.iscore[extraLingshi] or 0,
                        isMe = (item.userId == clientCloud.userId),
                        nickname = pName or ("玩家" .. tostring(item.userId)),
                        gender = pGender,
                        playerId = pId,
                    })
                end

                -- 自己的数据用本地最新
                for _, entry in ipairs(entries) do
                    if entry.isMe then
                        if State.HasPlayerName() then
                            entry.nickname = State.GetDisplayName()
                        end
                        entry.gender = State.state.playerGender or entry.gender
                        entry.playerId = State.GetPlayerId() or entry.playerId
                        entry.lingshi = math.floor(State.state.lingshi or entry.lingshi)
                    end
                end

                -- 过滤无效条目：没有道号且分数为0的不显示
                local filtered = {}
                for _, entry in ipairs(entries) do
                    if entry.isMe or entry.value ~= 0 or not string.find(entry.nickname, "^玩家%d+$") then
                        table.insert(filtered, entry)
                    end
                end
                -- 重新编排排名序号
                for i, entry in ipairs(filtered) do
                    entry.rank = i
                end

                renderList(filtered)
            end,
            error = function(code, reason)
                if not rankListPanel then return end
                rankListPanel:ClearChildren()
                rankListPanel:AddChild(UI.Label {
                    text = "加载失败",
                    fontSize = 11,
                    fontColor = Config.Colors.red,
                    textAlign = "center",
                    width = "100%",
                    paddingVertical = 20,
                })
            end,
        }, extraRealmLevel, extraPlayerName, extraPlayerGender, extraPlayerId, extraLingshi)

        -- 查询自己的排名
        clientCloud:GetUserRank(clientCloud.userId, currentKey, {
            ok = function(rank, scoreValue)
                if not myRankLabel then return end
                if rank then
                    local valueStr = currentFormatValue and currentFormatValue(scoreValue or 0) or HUD.FormatNumber(scoreValue or 0)
                    myRankLabel:SetText("我的排名: #" .. rank .. "  " .. valueStr)
                else
                    myRankLabel:SetText("我的排名: 未上榜")
                end
            end,
            error = function()
                if myRankLabel then
                    myRankLabel:SetText("排名查询失败")
                end
            end,
        })
    end

    -- ========== 构建 UI ==========

    -- Tab 按钮
    local tabChildren = {}
    for _, tab in ipairs(RANK_TABS) do
        local btn = UI.Button {
            text = tab.label,
            fontSize = 10,
            flexGrow = 1,
            height = 26,
            borderRadius = 4,
            backgroundColor = Config.Colors.panelLight,
            textColor = { 255, 255, 255, 255 },
            onClick = function(self)
                currentKey = tab.key
                currentFormatValue = tab.formatValue
                refreshTabStyles()
                fetchAndDisplay()
            end,
        }
        tabBtns[tab.key] = btn
        table.insert(tabChildren, btn)
    end

    -- 排行列表容器
    rankListPanel = UI.Panel {
        width = "100%",
        gap = 3,
    }

    -- 我的排名标签
    myRankLabel = UI.Label {
        text = "查询中...",
        fontSize = 10,
        fontColor = Config.Colors.jade,
        textAlign = "center",
        width = "100%",
    }

    -- 组装内容
    modal:AddContent(UI.Panel {
        width = "100%",
        gap = 6,
        padding = 4,
        children = {
            -- Tab 行
            UI.Panel {
                flexDirection = "row",
                width = "100%",
                gap = 4,
                children = tabChildren,
            },
            -- 排行列表(可滚动)
            UI.ScrollView {
                width = "100%",
                height = 280,
                children = { rankListPanel },
            },
            -- 我的排名
            UI.Panel {
                width = "100%",
                paddingVertical = 4,
                borderTopWidth = 1,
                borderColor = Config.Colors.border,
                alignItems = "center",
                children = { myRankLabel },
            },
        },
    })

    refreshTabStyles()
    modal:Open()
    fetchAndDisplay()
end

return M
