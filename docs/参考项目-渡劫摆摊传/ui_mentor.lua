--- ui_mentor.lua — 师徒面板 (Modal)
--- 显示师父/徒弟关系、待处理邀请、出师进度、解除师徒

local UI = require("urhox-libs/UI")
local Config = require("data_config")
local State = require("data_state")
local GameCore = require("game_core")
local HUD = require("ui_hud")

local M = {}

-- ========== 辅助函数 ==========

local function getRealmName(level)
    local r = Config.Realms[level]
    return r and r.name or ("境界" .. tostring(level))
end

local function divider()
    return UI.Panel {
        width = "100%", height = 1,
        backgroundColor = { 80, 85, 110, 120 },
        marginTop = 4, marginBottom = 4,
    }
end

local function infoRow(label, value, valueColor, valueId)
    return UI.Panel {
        width = "100%", flexDirection = "row",
        justifyContent = "space-between",
        paddingLeft = 4, paddingRight = 4,
        children = {
            UI.Label {
                text = label,
                fontSize = 9,
                fontColor = Config.Colors.textSecond,
            },
            UI.Label {
                id = valueId,
                text = tostring(value),
                fontSize = 9,
                fontColor = valueColor or Config.Colors.text,
                fontWeight = "bold",
            },
        },
    }
end

-- ========== 待处理邀请区块 ==========

local function buildPendingSection(s, modal)
    local invites = s.pendingMentorInvites or {}
    if #invites == 0 then return nil end

    local children = {}
    table.insert(children, UI.Label {
        text = "-- 待处理邀请 (" .. #invites .. ") --",
        fontSize = 10, fontWeight = "bold",
        fontColor = Config.Colors.warning,
        textAlign = "center", width = "100%",
    })

    for _, inv in ipairs(invites) do
        local fromName = inv.fromName or "仙友"
        local fromRealm = inv.fromRealm or 0
        local invType = inv.inviteType or "recruit"
        local typeLabel = invType == "recruit" and "收徒邀请" or "拜师申请"
        local typeDesc = invType == "recruit"
            and (fromName .. " 想收你为徒")
            or (fromName .. " 想拜你为师")

        local card = UI.Panel {
            width = "100%", gap = 2, padding = 5,
            backgroundColor = { 50, 45, 30, 180 },
            borderRadius = 6, marginTop = 2,
            children = {
                UI.Panel {
                    width = "100%", flexDirection = "row",
                    justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label {
                            text = typeLabel,
                            fontSize = 9,
                            fontColor = Config.Colors.warning,
                            fontWeight = "bold",
                        },
                        UI.Label {
                            text = getRealmName(fromRealm),
                            fontSize = 9,
                            fontColor = Config.Colors.purple,
                        },
                    },
                },
                UI.Label {
                    text = typeDesc,
                    fontSize = 9,
                    fontColor = Config.Colors.text,
                    width = "100%",
                },
                UI.Panel {
                    flexDirection = "row", gap = 8, width = "100%",
                    justifyContent = "flex-end", marginTop = 2,
                    children = {
                        UI.Button {
                            text = "拒绝",
                            fontSize = 8, height = 22,
                            paddingHorizontal = 10,
                            backgroundColor = { 80, 40, 40, 200 },
                            textColor = Config.Colors.warning,
                            borderRadius = 4,
                            onClick = function()
                                GameCore.SendGameAction("mentor_reject", { fromId = inv.fromId })
                                modal:Close()
                            end,
                        },
                        UI.Button {
                            text = "同意",
                            fontSize = 8, height = 22,
                            paddingHorizontal = 10,
                            backgroundColor = Config.Colors.jade,
                            textColor = { 255, 255, 255, 255 },
                            borderRadius = 4,
                            onClick = function()
                                GameCore.SendGameAction("mentor_accept", { fromId = inv.fromId })
                                modal:Close()
                            end,
                        },
                    },
                },
            },
        }
        table.insert(children, card)
    end

    return UI.Panel {
        width = "100%", gap = 2, padding = 5,
        backgroundColor = { 45, 40, 25, 180 },
        borderRadius = 8,
        children = children,
    }
end

-- ========== 师父信息区块 ==========

local function buildMasterSection(s, modal)
    local children = {}

    table.insert(children, UI.Label {
        text = "-- 我的师父 --",
        fontSize = 10, fontWeight = "bold",
        fontColor = Config.Colors.textGold,
        textAlign = "center", width = "100%",
    })

    if s.masterId and s.masterId ~= "" then
        -- 当前有师父，显示师徒信息和功能按钮
        table.insert(children, infoRow("师父", s.masterName or "未知", Config.Colors.jade))
        table.insert(children, infoRow("拜师时师父境界", getRealmName(s.masterRealmAtBind or 0), Config.Colors.purple))
        local graduationTarget = math.max((s.masterRealmAtBind or 99) - 1, 1)
        table.insert(children, infoRow("出师目标", getRealmName(graduationTarget), Config.Colors.textGold))
        table.insert(children, infoRow("当前境界", getRealmName(s.realmLevel or 1), Config.Colors.jade))

        local target = graduationTarget
        local current = s.realmLevel or 1
        local progressText = current >= target and "已达成" or (current .. "/" .. target)
        local progressColor = current >= target and Config.Colors.jade or Config.Colors.warning
        table.insert(children, infoRow("出师进度", progressText, progressColor))

        -- 出师条件达成时显示出师按钮
        if current >= target then
            table.insert(children, UI.Button {
                text = "申请出师",
                fontSize = 9, height = 24, width = "60%",
                backgroundColor = Config.Colors.jade,
                textColor = { 10, 20, 10, 255 },
                borderRadius = 6, marginTop = 6,
                alignSelf = "center",
                onClick = function()
                    UI.Modal.Confirm({
                        title = "申请出师",
                        message = "境界已达出师要求！\n出师后将离开师门并获得修为奖励，\n且无法再次拜师，确认出师？",
                        confirmText = "确认出师",
                        cancelText = "取消",
                        onConfirm = function()
                            GameCore.SendGameAction("mentor_graduate", {})
                            -- 立即关闭弹窗，等服务端事件刷新状态
                            if modal then modal:Close() end
                        end,
                    })
                end,
            })
        end

        table.insert(children, UI.Label {
            text = "拜师加成: 修炼速度+10%",
            fontSize = 8, fontColor = Config.Colors.jade,
            textAlign = "center", width = "100%", marginTop = 4,
        })

        table.insert(children, UI.Button {
            text = "离开师门",
            fontSize = 9, height = 24, width = "60%",
            backgroundColor = { 120, 50, 50, 200 },
            textColor = Config.Colors.warning,
            borderRadius = 6, marginTop = 6,
            alignSelf = "center",
            onClick = function()
                UI.Modal.Confirm({
                    title = "离开师门",
                    message = "确定要离开师门吗?\n离开后将失去修炼加成",
                    confirmText = "确定离开",
                    cancelText = "取消",
                    onConfirm = function()
                        GameCore.SendGameAction("mentor_dismiss", { action = "leave" })
                        if modal then modal:Close() end
                    end,
                })
            end,
        })
    elseif s.hasGraduated then
        -- 已出师，展示出师历史记录（无操作按钮）
        table.insert(children, UI.Panel {
            width = "100%", padding = 8, marginTop = 4,
            backgroundColor = { 40, 50, 40, 160 },
            borderRadius = 6,
            gap = 4,
            children = {
                UI.Label {
                    text = "已出师",
                    fontSize = 10, fontWeight = "bold",
                    fontColor = Config.Colors.jade,
                    textAlign = "center", width = "100%",
                },
                infoRow("前任师父",
                    (s.lastMasterName and s.lastMasterName ~= "") and s.lastMasterName or "未知",
                    Config.Colors.textGold),
                infoRow("说明", "出师后不可再次拜师", Config.Colors.textSecond),
            },
        })
    else
        -- 无师父且未出师，提示如何拜师
        table.insert(children, UI.Label {
            text = "暂无师父",
            fontSize = 9, fontColor = Config.Colors.textSecond,
            textAlign = "center", width = "100%", marginTop = 4,
        })
        table.insert(children, UI.Label {
            text = "在聊天中点击高境界玩家可申请拜师",
            fontSize = 9, fontColor = Config.Colors.textSecond,
            textAlign = "center", width = "100%", marginTop = 2,
        })
    end

    return UI.Panel {
        width = "100%", gap = 3, padding = 6,
        backgroundColor = { 35, 38, 55, 180 },
        borderRadius = 8,
        children = children,
    }
end

-- ========== 徒弟列表区块 ==========

local function buildDiscipleSection(s, modal, onlineLabels, giftBtnRefs)
    local children = {}

    table.insert(children, UI.Label {
        text = "-- 我的徒弟 (" .. #(s.disciples or {}) .. "/" .. Config.MentorConfig.maxDisciples .. ") --",
        fontSize = 10, fontWeight = "bold",
        fontColor = Config.Colors.textGold,
        textAlign = "center", width = "100%",
    })

    local disciples = s.disciples or {}
    if #disciples == 0 then
        table.insert(children, UI.Label {
            text = "暂无徒弟",
            fontSize = 9, fontColor = Config.Colors.textSecond,
            textAlign = "center", width = "100%", marginTop = 4,
        })
        local myRealm = s.realmLevel or 0
        if myRealm >= Config.MentorConfig.masterMinRealm then
            table.insert(children, UI.Label {
                text = "在聊天中点击低境界玩家可收徒",
                fontSize = 9, fontColor = Config.Colors.textSecond,
                textAlign = "center", width = "100%", marginTop = 2,
            })
        else
            table.insert(children, UI.Label {
                text = "境界达到" .. getRealmName(Config.MentorConfig.masterMinRealm) .. "后可收徒",
                fontSize = 9, fontColor = Config.Colors.warning,
                textAlign = "center", width = "100%", marginTop = 2,
            })
        end
    else
        -- 计算今日剩余赠送次数(师父侧)
        local bjDateKey = os.date("!%Y-%m-%d", os.time() + 8 * 3600)
        local giftRemain = 3
        if (s.mentorGiftDate or "") == bjDateKey then
            giftRemain = math.max(3 - (s.mentorGiftCount or 0), 0)
        end

        for _, d in ipairs(disciples) do
            local dName = d.name or "未知"
            local dRealmAtBind = d.realmAtBind or 0
            local dOnline = d.online
            -- 提取赠送按钮为变量，便于后续动态刷新次数
            local giftBtn = UI.Button {
                text = "赠送(" .. giftRemain .. "/3)",
                fontSize = 8, height = 20,
                paddingLeft = 8, paddingRight = 8,
                backgroundColor = (giftRemain > 0) and Config.Colors.purple or { 70, 70, 70, 200 },
                textColor = { 255, 255, 255, 255 },
                borderRadius = 4,
                onClick = function()
                    if giftRemain <= 0 then
                        UI.Toast.Show("今日赠送次数已用完(每日3次)", { variant = "warning", duration = 2 })
                        return
                    end
                    M.ShowGiftModal(s, d.userId, dName)
                end,
            }
            if giftBtnRefs then
                table.insert(giftBtnRefs, { widget = giftBtn, userId = d.userId, name = dName })
            end
            local card = UI.Panel {
                width = "100%", gap = 2, padding = 6,
                backgroundColor = { 45, 48, 65, 150 },
                borderRadius = 6, marginTop = 2,
                children = {
                    UI.Panel {
                        width = "100%", flexDirection = "row",
                        justifyContent = "space-between",
                        children = {
                            UI.Label {
                                text = dName,
                                fontSize = 9, fontWeight = "bold",
                                fontColor = Config.Colors.jade,
                            },
                            UI.Panel {
                                flexDirection = "row", gap = 4,
                                children = {
                                    giftBtn,
                                    UI.Button {
                                        text = "逐出",
                                        fontSize = 8, height = 20,
                                        paddingLeft = 8, paddingRight = 8,
                                        backgroundColor = { 100, 40, 40, 200 },
                                        textColor = Config.Colors.warning,
                                        borderRadius = 4,
                                        onClick = function()
                                            UI.Modal.Confirm({
                                                title = "逐出师门",
                                                message = "确定将 " .. dName .. " 逐出师门吗?",
                                                confirmText = "确定",
                                                cancelText = "取消",
                                                onConfirm = function()
                                                    GameCore.SendGameAction("mentor_dismiss", {
                                                        action = "kick",
                                                        discipleUserId = d.userId,
                                                    })
                                                    modal:Close()
                                                end,
                                            })
                                        end,
                                    },
                                },
                            },
                        },
                    },
                    (function()
                        local lbl = UI.Label {
                            text = "查询中...",
                            fontSize = 9, fontWeight = "bold",
                            fontColor = Config.Colors.textSecond,
                        }
                        if onlineLabels then
                            onlineLabels[tostring(d.userId)] = lbl
                        end
                        return UI.Panel {
                            width = "100%", flexDirection = "row",
                            justifyContent = "space-between",
                            paddingLeft = 4, paddingRight = 4,
                            children = {
                                UI.Label { text = "在线状态", fontSize = 9, fontColor = Config.Colors.textSecond },
                                lbl,
                            },
                        }
                    end)(),
                    infoRow("拜师时徒弟境界", getRealmName(dRealmAtBind), Config.Colors.textSecond),
                    infoRow("拜师时师父境界", getRealmName(d.masterRealmAtBind or 0), Config.Colors.purple),
                    infoRow("出师目标", "徒弟达到" .. getRealmName(math.max((d.masterRealmAtBind or 99) - 1, 1)), Config.Colors.textGold),
                },
            }
            table.insert(children, card)
        end
    end

    table.insert(children, divider())
    table.insert(children, infoRow("累计徒弟分成", HUD.FormatNumber(s.mentorXiuweiEarned or 0) .. " 修为", Config.Colors.jade))
    table.insert(children, infoRow("已出师徒弟", tostring(s.graduatedCount or 0) .. " 人", Config.Colors.textGold))

    return UI.Panel {
        width = "100%", gap = 3, padding = 6,
        backgroundColor = { 35, 38, 55, 180 },
        borderRadius = 8,
        children = children,
    }
end

-- ========== 规则说明区块 ==========

local function buildRulesSection()
    local cfg = Config.MentorConfig
    return UI.Panel {
        width = "100%", gap = 2, padding = 6,
        backgroundColor = { 35, 38, 55, 180 },
        borderRadius = 8,
        children = {
            UI.Label {
                text = "-- 师徒规则 --",
                fontSize = 10, fontWeight = "bold",
                fontColor = Config.Colors.textGold,
                textAlign = "center", width = "100%",
            },
            UI.Label {
                text = "  师父境界需达到" .. getRealmName(cfg.masterMinRealm)
                    .. "\n  徒弟境界需低于师父" .. cfg.realmGap .. "个大境界"
                    .. "\n  每人最多收" .. cfg.maxDisciples .. "个徒弟"
                    .. "\n  徒弟修炼速度+" .. math.floor(cfg.discipleSpeedBonus * 100) .. "%"
                    .. "\n  师父获得徒弟修为的" .. math.floor(cfg.masterShareRatio * 100) .. "%"
                    .. "\n  徒弟境界达到拜师时师父境界前一级即出师"
                    .. "\n  出师奖励: 师父" .. HUD.FormatNumber(cfg.graduationRewardMaster) .. "修为"
                    .. " / 徒弟" .. HUD.FormatNumber(cfg.graduationRewardDisciple) .. "修为"
                    .. "\n  支持离线发送邀请,对方上线后可查看",
                fontSize = 8,
                fontColor = Config.Colors.textSecond,
                width = "100%",
            },
        },
    }
end

-- ========== 公开接口 ==========

function M.ShowMentorModal()
    local s = State.state
    if not s then return end

    local onlineLabels = {}  -- { [tostring(userId)] = labelWidget }
    local giftBtnRefs  = {}  -- { { widget, userId, name } }

    -- 在线状态回调(复用 check_online，直接用 label 引用更新)
    local function onOnlineResult(data)
        local key = tostring(data.targetId)
        local lbl = onlineLabels[key]
        if lbl then
            if data.online then
                lbl:SetText("在线")
                lbl:SetFontColor(Config.Colors.jade)
            else
                lbl:SetText("离线")
                lbl:SetFontColor(Config.Colors.textSecond)
            end
        end
    end

    -- 赠送结果回调：实时刷新赠送按钮次数
    local function onGiftResult(data)
        if not data.ok then return end
        local remaining = data.remaining or 0
        for _, ref in ipairs(giftBtnRefs) do
            ref.widget:SetText("赠送(" .. remaining .. "/3)")
            if remaining > 0 then
                ref.widget:SetStyle({ backgroundColor = Config.Colors.purple })
                ref.widget.props.onClick = function()
                    M.ShowGiftModal(s, ref.userId, ref.name)
                end
            else
                ref.widget:SetStyle({ backgroundColor = { 70, 70, 70, 200 } })
                ref.widget.props.onClick = function()
                    UI.Toast.Show("今日赠送次数已用完(每日3次)", { variant = "warning", duration = 2 })
                end
            end
        end
    end

    local modal = UI.Modal {
        title = "师徒系统",
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self)
            State.Off("online_status_result", onOnlineResult)
            State.Off("mentor_gift_result", onGiftResult)
            self:Destroy()
        end,
    }

    local sections = {}

    -- 待处理邀请(优先显示在最上面)
    local pendingPanel = buildPendingSection(s, modal)
    if pendingPanel then
        table.insert(sections, pendingPanel)
    end

    table.insert(sections, buildMasterSection(s, modal))
    table.insert(sections, buildDiscipleSection(s, modal, onlineLabels, giftBtnRefs))
    table.insert(sections, buildRulesSection())

    local contentPanel = UI.Panel {
        width = "100%", gap = 6, padding = 4,
        children = sections,
    }

    modal:AddContent(UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        children = { contentPanel },
    })

    State.On("online_status_result", onOnlineResult)
    State.On("mentor_gift_result", onGiftResult)
    modal:Open()

    -- 查询各徒弟在线状态
    for _, d in ipairs(s.disciples or {}) do
        GameCore.SendGameAction("check_online", { targetId = tostring(d.userId) })
    end

    -- 查询最新师徒信息
    GameCore.SendGameAction("mentor_query", {})
end

-- ========== 赠送弹窗 ==========

--- discipleId: 目标徒弟userId, discipleName: 徒弟名称(用于显示)
function M.ShowGiftModal(s, discipleId, discipleName)
    local modal = UI.Modal {
        title = "赠送给 " .. (discipleName or "徒弟"),
        size = "sm",
        closeOnOverlay = true,
        onClose = function(self) self:Destroy() end,
    }

    -- 收集师父自己可赠送的物品
    local items = {}

    -- 法宝：未装备且数量>=1
    local equipped = {}
    for _, eq in ipairs(s.equippedArtifacts or {}) do
        equipped[eq.id] = true
    end
    for artId, artData in pairs(s.artifacts or {}) do
        if (artData.count or 0) > 0 and not equipped[artId] then
            local cfg = Config.GetArtifactById(artId)
            if cfg then
                table.insert(items, {
                    giftType = "artifact",
                    id = artId,
                    name = cfg.name,
                    desc = cfg.desc,
                    count = artData.count,
                    color = Config.Colors.orange,
                    tag = "法宝",
                })
            end
        end
    end

    -- 珍藏：数量>=1
    for itemId, cnt in pairs(s.collectibles or {}) do
        if (cnt or 0) > 0 then
            local cfg = Config.GetCollectibleById(itemId)
            if cfg then
                table.insert(items, {
                    giftType = "collectible",
                    id = itemId,
                    name = cfg.name,
                    desc = cfg.desc,
                    count = cnt,
                    color = cfg.color or Config.Colors.jade,
                    tag = "珍藏",
                })
            end
        end
    end

    local children = {}
    if #items == 0 then
        table.insert(children, UI.Label {
            text = "你没有可赠送的法宝或珍藏",
            fontSize = 9, fontColor = Config.Colors.textSecond,
            textAlign = "center", width = "100%", marginTop = 10,
        })
    else
        table.insert(children, UI.Label {
            text = "每次赠送1个，每日共3次（含所有徒弟）",
            fontSize = 8, fontColor = Config.Colors.textSecond,
            textAlign = "center", width = "100%",
        })
        for _, item in ipairs(items) do
            table.insert(children, UI.Panel {
                width = "100%", flexDirection = "row",
                alignItems = "center", justifyContent = "space-between",
                padding = 6, marginTop = 2,
                backgroundColor = { 45, 48, 65, 150 },
                borderRadius = 6,
                children = {
                    UI.Panel {
                        flexShrink = 1, gap = 1,
                        children = {
                            UI.Panel {
                                flexDirection = "row", gap = 4, alignItems = "center",
                                children = {
                                    UI.Label {
                                        text = "[" .. item.tag .. "]",
                                        fontSize = 9, fontColor = Config.Colors.textSecond,
                                    },
                                    UI.Label {
                                        text = item.name,
                                        fontSize = 9, fontWeight = "bold",
                                        fontColor = item.color,
                                    },
                                    UI.Label {
                                        text = "x" .. item.count,
                                        fontSize = 9, fontColor = Config.Colors.textSecond,
                                    },
                                },
                            },
                            UI.Label {
                                text = item.desc,
                                fontSize = 8, fontColor = Config.Colors.textSecond,
                                width = "100%",
                            },
                        },
                    },
                    UI.Button {
                        text = "赠送",
                        fontSize = 9, height = 26,
                        paddingHorizontal = 12,
                        backgroundColor = Config.Colors.purple,
                        textColor = { 255, 255, 255, 255 },
                        borderRadius = 4,
                        onClick = function()
                            UI.Modal.Confirm({
                                title = "确认赠送",
                                message = "赠送 " .. item.name .. " x1 给徒弟 " .. (discipleName or "") .. "?\n赠送后无法取回",
                                confirmText = "赠送",
                                cancelText = "取消",
                                onConfirm = function()
                                    GameCore.SendGameAction("mentor_gift", {
                                        discipleId = discipleId,
                                        giftType   = item.giftType,
                                        itemId     = item.id,
                                    })
                                    modal:Close()
                                end,
                            })
                        end,
                    },
                },
            })
        end
    end

    modal:AddContent(UI.ScrollView {
        width = "100%",
        flexGrow = 1,
        flexShrink = 1,
        children = { UI.Panel {
            width = "100%", gap = 4, padding = 4,
            children = children,
        }},
    })

    modal:Open()
end

return M
