-- ============================================================================
-- 《问道长生》坊市页（商铺 / 寄售坊 / 我的寄售）
-- ============================================================================

local UI = require("urhox-libs/UI")
local Theme = require("ui_theme")
local Comp = require("ui_components")
local RT = require("rich_text")
local Router = require("ui_router")
local GamePlayer = require("game_player")
local GameMarket = require("game_market")
local Toast = require("ui_toast")
local DataItems = require("data_items")
local DataMartialArts = require("data_martial_arts")
local NVG = require("nvg_manager")
local M = {}

-- ============================================================================
-- 模块级状态
-- ============================================================================
local selectedMainTab_ = 1   -- 1=商铺 2=寄售坊 3=我的寄售
local selectedCategory_ = 1  -- 商铺分类索引
local showConfirmModal_ = false
local confirmItem_ = nil     -- 待确认购买的物品（寄售坊用）
local showListModal_ = false -- 上架弹窗
local selectedBagIdx_ = nil  -- 上架弹窗选中的背包物品索引
local listPrice_ = 0         -- 上架定价
local listCount_ = 1         -- 上架数量
local showHistory_ = false   -- 交易记录展开
local showShopBuyModal_ = false  -- 商铺购买确认弹窗
local shopBuyItem_ = nil         -- 商铺待购买物品
local shopBuyCount_ = 1          -- 商铺购买数量
local holdDir_ = 0               -- 长按方向: -1=减, 0=无, 1=加
local holdTimer_ = 0             -- 长按计时
local shopBuyInputMode_ = false  -- 数量是否处于手动输入模式
local HOLD_DELAY = 0.4           -- 长按生效前延迟
local HOLD_RATE  = 0.07          -- 长按连续触发间隔

local currencySynced_ = false  -- 标记是否已同步过货币余额

local MAIN_TABS = { "商铺", "寄售坊", "我的寄售" }

-- 商铺商品（静态配置）
local MARKET_GOODS = {
    {
        category = "丹药",
        items = {
            { name = "培元丹",   price = 50,   currency = "灵石", rarity = "common",   stock = 10, desc = "初级丹药，恢复修为<c=gold>200</c>。" },
            { name = "洗髓丹",   price = 200,  currency = "灵石", rarity = "uncommon", stock = 5,  desc = "洗炼筋骨，永久提升悟性<c=green>+5</c>。" },
            { name = "筑基丹",   price = 30,   currency = "仙石", rarity = "rare",     stock = 1,  desc = "突破筑基境界的关键丹药。" },
            { name = "凝神丹",   price = 120,  currency = "灵石", rarity = "uncommon", stock = 3,  desc = "凝神聚气，提升神识<c=cyan>+20</c>。" },
        },
    },
    {
        category = "法宝",
        items = {
            { name = "紫金铃",   price = 500,  currency = "灵石", rarity = "rare",     stock = 2,  desc = "攻击<c=orange>+25</c>，自带音波攻击。" },
            { name = "玄铁盾",   price = 300,  currency = "灵石", rarity = "uncommon", stock = 3,  desc = "防御<c=green>+30</c>，格挡率大幅提升。" },
            { name = "仙灵扇",   price = 80,   currency = "仙石", rarity = "epic",     stock = 1,  desc = "速度<c=cyan>+40</c>，附带风系法术。" },
        },
    },
    {
        category = "功法",
        items = {
            { name = "冰心诀",   price = 800,  currency = "灵石", grade = "xuan", stock = 1,  desc = "冰系功法，修炼速度<c=cyan>+20%</c>。" },
            { name = "烈焰掌",   price = 400,  currency = "灵石", grade = "ling", stock = 2,  desc = "火系攻击功法，攻击<c=orange>+30</c>。" },
        },
    },
    {
        category = "材料",
        items = {
            { name = "灵草",     price = 20,   currency = "灵石", rarity = "common",   stock = 99, desc = "炼丹基础材料。" },
            { name = "兽骨",     price = 30,   currency = "灵石", rarity = "common",   stock = 50, desc = "炼丹辅材，来自灵兽。" },
            { name = "灵泉水",   price = 80,   currency = "灵石", rarity = "uncommon", stock = 10, desc = "天然灵泉凝结之水。" },
            { name = "天材地宝", price = 50,   currency = "仙石", rarity = "rare",     stock = 2,   desc = "罕见天地灵物，<c=gold>极具价值</c>。" },
            { name = "灵尘",     price = 15,   currency = "灵石", rarity = "common",   stock = 999, desc = "法宝强化专用材料，<c=cyan>装备分解</c>可获得。" },
        },
    },
    {
        category = "礼包",
        items = {
            { name = "灵尘礼包",   price = 120, currency = "灵石", rarity = "uncommon", stock = 99, desc = "强化材料礼包，包含<c=gold>灵尘×10</c>，比单买节省<c=green>20%</c>。", giftItem = "灵尘", giftCount = 10 },
            { name = "灵尘大礼包", price = 550, currency = "灵石", rarity = "rare",     stock = 20, desc = "强化材料大礼包，包含<c=gold>灵尘×50</c>，比单买节省<c=green>27%</c>。", giftItem = "灵尘", giftCount = 50 },
        },
    },
    {
        category = "兑换",
        items = {
            { name = "灵石小包",   price = 1,   currency = "仙石", rarity = "common",   stock = 99, desc = "仙石兑换灵石，获得<c=gold>灵石×100</c>。" },
            { name = "灵石中包",   price = 10,  currency = "仙石", rarity = "uncommon", stock = 99, desc = "仙石兑换灵石，获得<c=gold>灵石×1100</c>，额外赠送<c=green>10%</c>。" },
            { name = "灵石大包",   price = 50,  currency = "仙石", rarity = "rare",     stock = 10, desc = "仙石兑换灵石，获得<c=gold>灵石×6000</c>，额外赠送<c=green>20%</c>。" },
        },
    },
}

-- NPC 卖家（静态配置）
local NPC_SELLERS = {
    { id = 1, name = "云游散人",   realm = "筑基中期" },
    { id = 2, name = "青萝仙子",   realm = "金丹初期" },
    { id = 3, name = "独孤剑客",   realm = "筑基大成" },
    { id = 4, name = "碧落真人",   realm = "金丹中期" },
    { id = 5, name = "风清扬",     realm = "金丹初期" },
    { id = 6, name = "白鹤仙",     realm = "金丹大成" },
}

-- 稀有度颜色（委托 DataItems，兼容新旧 key）
local function getRarityColor(rarity)
    return DataItems.GetQualityColor(rarity) or Theme.colors.textSecondary
end

-- 品质徽标（名字旁边的小标签，如"灵宝""先天灵宝"）
local function BuildQualityBadge(rarity)
    local label = DataItems.GetQualityLabel(rarity)
    local color = getRarityColor(rarity)
    return UI.Panel {
        paddingHorizontal = 5, paddingVertical = 2,
        borderRadius = 3,
        backgroundColor = { color[1], color[2], color[3], 40 },
        borderColor = color, borderWidth = 1,
        children = {
            UI.Label { text = label, fontSize = Theme.fontSize.tiny, fontColor = color },
        },
    }
end

-- 按商铺分类返回商品的 nameColor 和 品阶徽章
-- category: "丹药"|"功法"|"材料"|"礼包"|"法宝"

local function BuildCategoryQualityBadge(item, category)
    if category == "丹药" then
        local pillData = DataItems.FindPillByName(item.name)
        local quality  = pillData and pillData.quality or "xia"
        local pq       = DataItems.PILL_QUALITY[quality] or DataItems.PILL_QUALITY.xia
        return pq.color, UI.Panel {
            paddingHorizontal = 5, paddingVertical = 2, borderRadius = 3,
            backgroundColor = { pq.color[1], pq.color[2], pq.color[3], 40 },
            borderColor = pq.color, borderWidth = 1,
            children = { UI.Label { text = pq.label, fontSize = Theme.fontSize.tiny, fontColor = pq.color } },
        }
    elseif category == "功法" then
        local gradeKey  = item.grade or "fan"
        local gradeInfo = DataMartialArts.GRADE_INFO[gradeKey] or DataMartialArts.GRADE_INFO.fan
        local color     = DataMartialArts.GRADE_COLORS[gradeKey] or DataMartialArts.GRADE_COLORS.fan
        local label     = gradeInfo.name
        return color, UI.Panel {
            paddingHorizontal = 5, paddingVertical = 2, borderRadius = 3,
            backgroundColor = { color[1], color[2], color[3], 40 },
            borderColor = color, borderWidth = 1,
            children = { UI.Label { text = label, fontSize = Theme.fontSize.tiny, fontColor = color } },
        }
    elseif category == "材料" or category == "礼包" then
        -- 材料/礼包不显示品阶徽章
        return Theme.colors.textLight, nil
    else
        -- 法宝：沿用现有法宝品质体系
        local color = DataItems.GetQualityColor(item.rarity)
        return color, BuildQualityBadge(item.rarity)
    end
end

-- ============================================================================
-- 通用：返回行
-- ============================================================================
local function BuildBackRow()
    return UI.Panel {
        width = "100%",
        flexDirection = "row",
        alignItems = "center",
        gap = 8,
        children = {
            UI.Panel {
                paddingHorizontal = 8, paddingVertical = 4, cursor = "pointer",
                onClick = function(self)
                    selectedMainTab_ = 1
                    selectedCategory_ = 1
                    showConfirmModal_ = false
                    showListModal_ = false
                    showShopBuyModal_ = false
                    currencySynced_ = false
                    GamePlayer.OffCurrencyChange("market")
                    Router.EnterState(Router.STATE_HOME)
                end,
                children = {
                    UI.Label { text = "< 返回", fontSize = Theme.fontSize.body, fontColor = Theme.colors.gold },
                },
            },
            UI.Label {
                text = "坊市",
                fontSize = Theme.fontSize.heading, fontWeight = "bold", fontColor = Theme.colors.textGold,
            },
        },
    }
end

-- ============================================================================
-- 通用：主标签栏（商铺 / 寄售坊 / 我的寄售）
-- ============================================================================
local function BuildMainTabs()
    local children = {}
    for i, name in ipairs(MAIN_TABS) do
        local isActive = (i == selectedMainTab_)
        children[#children + 1] = UI.Panel {
            flex = 1,
            paddingVertical = 8,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or { 50, 42, 35, 200 },
            cursor = "pointer",
            alignItems = "center",
            onClick = function(self)
                selectedMainTab_ = i
                showConfirmModal_ = false
                showListModal_ = false
                showShopBuyModal_ = false
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = name,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.tabActiveText or Theme.colors.textLight,
                },
            },
        }
    end
    return UI.Panel {
        width = "100%", flexDirection = "row", gap = 6,
        children = children,
    }
end

-- ============================================================================
-- 通用：货币面板
-- ============================================================================
local function BuildCurrencyBar()
    return Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-around",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 4, alignItems = "center",
                    children = {
                        UI.Label { text = "灵石", fontSize = Theme.fontSize.small, fontColor = { 140, 125, 105, 255 } },
                        UI.Label { text = tostring(GamePlayer.GetCurrency("lingStone")), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.accent },
                    },
                },
                UI.Panel {
                    flexDirection = "row", gap = 4, alignItems = "center",
                    children = {
                        UI.Label { text = "仙石", fontSize = Theme.fontSize.small, fontColor = { 140, 125, 105, 255 } },
                        UI.Label { text = tostring(GamePlayer.GetCurrency("spiritStone")), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.gold },
                    },
                },
            },
        },
    })
end

-- ============================================================================
-- 标签1：商铺（保留原功能）
-- ============================================================================
local function BuildCategoryTabs()
    local goods = MARKET_GOODS
    local tabChildren = {}
    for i, cat in ipairs(goods) do
        local isActive = (i == selectedCategory_)
        tabChildren[#tabChildren + 1] = UI.Panel {
            paddingHorizontal = 12, paddingVertical = 6,
            borderRadius = Theme.radius.sm,
            backgroundColor = isActive and Theme.colors.gold or { 50, 42, 35, 200 },
            cursor = "pointer",
            onClick = function(self)
                selectedCategory_ = i
                Router.RebuildUI()
            end,
            children = {
                UI.Label {
                    text = cat.category,
                    fontSize = Theme.fontSize.body,
                    fontWeight = isActive and "bold" or "normal",
                    fontColor = isActive and Theme.colors.tabActiveText or Theme.colors.textLight,
                },
            },
        }
    end
    return UI.Panel { width = "100%", flexDirection = "row", gap = 8, flexWrap = "wrap", children = tabChildren }
end

local function BuildShopGoodCard(item, category)
    local nameColor, qualityBadge = BuildCategoryQualityBadge(item, category)
    local currencyColor = item.currency == "仙石" and Theme.colors.gold or Theme.colors.accent
    return Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                -- 名字 + 品质徽标
                UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        UI.Label { text = item.name, fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = nameColor },
                        qualityBadge,
                    },
                },
                (function()
                    local stockTag = item.stock > 0 and "<c=green>" or "<c=red>"
                    return RT.Build("库存: " .. stockTag .. tostring(item.stock) .. "</c>", Theme.fontSize.tiny, Theme.colors.textSecondary)
                end)(),
            },
        },
        -- 描述：RT.Build 高亮关键数值
        RT.Build(item.desc, Theme.fontSize.small, Theme.colors.textLight),
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginTop = 4,
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 4, alignItems = "center",
                    children = {
                        UI.Label { text = item.currency, fontSize = Theme.fontSize.small, fontColor = { 140, 125, 105, 255 } },
                        UI.Label { text = tostring(item.price), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = currencyColor },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 16, paddingVertical = 6,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = item.stock > 0 and Theme.colors.gold or { 80, 70, 55, 150 },
                    cursor = item.stock > 0 and "pointer" or "default",
                    onClick = function(self)
                        if item.stock <= 0 then
                            Toast.Show("该商品已售罄", { variant = "error" })
                            return
                        end
                        shopBuyItem_ = item
                        shopBuyCount_ = 1
                        shopBuyInputMode_ = false
                        showShopBuyModal_ = true
                        Router.RebuildUI()
                    end,
                    children = {
                        UI.Label {
                            text = item.stock > 0 and "购买" or "售罄",
                            fontSize = Theme.fontSize.body, fontWeight = "bold",
                            fontColor = item.stock > 0 and Theme.colors.btnPrimaryText or Theme.colors.textSecondary,
                        },
                    },
                },
            },
        },
    }, { borderColor = nameColor })
end

local function BuildShopTab(p)
    local goods = MARKET_GOODS
    local currentCat = goods[selectedCategory_] or goods[1]
    local cards = {}
    for _, item in ipairs(currentCat.items) do
        item.shopCategory = currentCat.category
        cards[#cards + 1] = BuildShopGoodCard(item, currentCat.category)
    end
    local result = { BuildCurrencyBar(), BuildCategoryTabs() }
    for _, c in ipairs(cards) do
        result[#result + 1] = c
    end
    return result
end

-- ============================================================================
-- 标签2：寄售坊
-- ============================================================================
local function GetSellerById(id)
    for _, s in ipairs(NPC_SELLERS) do
        if s.id == id then return s end
    end
    return { name = "未知", realm = "???" }
end

local function BuildTradingCard(listing)
    local nameColor = getRarityColor(listing.rarity)
    -- 兼容服务端结构（sellerUid/desc）和单机结构（sellerId/note/refPrice）
    local seller = listing.sellerUid
        and { name = "玩家#" .. tostring(listing.sellerUid), realm = "" }
        or GetSellerById(listing.sellerId)
    local refPrice = listing.refPrice or listing.price
    local note = listing.note or listing.desc or ""
    local listedTime = listing.listedTime or ""
    local belowMarket = listing.price < refPrice

    return Comp.BuildCardPanel(nil, {
        -- 物品名 + 品质徽标 + 数量
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        UI.Label { text = listing.name, fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = nameColor },
                        BuildQualityBadge(listing.rarity),
                        belowMarket and UI.Panel {
                            paddingHorizontal = 6, paddingVertical = 2,
                            borderRadius = 4,
                            backgroundColor = { 60, 140, 60, 80 },
                            children = {
                                UI.Label { text = "低于市价", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.success },
                            },
                        } or nil,
                    },
                },
                UI.Label { text = "x" .. tostring(listing.stock), fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
            },
        },
        -- 卖家信息
        UI.Panel {
            width = "100%", flexDirection = "row", gap = 6, alignItems = "center",
            children = {
                UI.Label { text = seller.name, fontSize = Theme.fontSize.small, fontColor = Theme.colors.textGold },
                UI.Label { text = seller.realm, fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                UI.Label { text = listedTime, fontSize = Theme.fontSize.tiny, fontColor = { 100, 90, 75, 150 } },
            },
        },
        -- 留言
        (#note > 0) and UI.Label { text = "\"" .. note .. "\"", fontSize = Theme.fontSize.small, fontColor = { 160, 150, 130, 180 } } or nil,
        -- 价格 + 参考价 + 购买
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginTop = 4,
            children = {
                UI.Panel {
                    gap = 2,
                    children = {
                        UI.Panel {
                            flexDirection = "row", gap = 4, alignItems = "center",
                            children = {
                                UI.Label { text = GameMarket.GetCurrencyLabel(listing.currency or "lingStone"), fontSize = Theme.fontSize.small, fontColor = { 140, 125, 105, 255 } },
                                UI.Label { text = tostring(listing.price), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = (listing.currency == "spiritStone") and Theme.colors.gold or Theme.colors.accent },
                            },
                        },
                        UI.Label { text = "参考价: " .. tostring(refPrice), fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 16, paddingVertical = 6,
                    borderRadius = Theme.radius.sm, backgroundColor = Theme.colors.gold,
                    cursor = "pointer",
                    onClick = function(self)
                        confirmItem_ = listing
                        showConfirmModal_ = true
                        Router.RebuildUI()
                    end,
                    children = {
                        UI.Label { text = "购买", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText },
                    },
                },
            },
        },
    }, { borderColor = nameColor })
end

local function BuildTradingPostTab(p)
    -- 网络模式：使用服务端寄售列表；单机模式：空列表
    local listings = {}
    if IsNetworkMode() then
        listings = GameMarket.GetServerListings() or {}
    end
    local result = { BuildCurrencyBar() }
    if #listings == 0 then
        result[#result + 1] = Comp.BuildCardPanel("寄售坊", {
            UI.Label {
                text = IsNetworkMode() and "暂无寄售物品" or "寄售坊需联网使用",
                fontSize = Theme.fontSize.body,
                fontColor = Theme.colors.textSecondary,
                textAlign = "center",
                width = "100%",
                paddingVertical = 40,
            },
        })
    else
        for _, listing in ipairs(listings) do
            result[#result + 1] = BuildTradingCard(listing)
        end
    end
    return result
end

-- ============================================================================
-- 标签3：我的寄售
-- ============================================================================
local function BuildMyListingCard(listing, listingIndex)
    local nameColor = getRarityColor(listing.rarity)
    -- 服务端数据没有 status 字段，默认为 selling
    local status = listing.status or "selling"
    local statusText = status == "selling" and "寄售中" or "已售出"
    local statusColor = status == "selling" and Theme.colors.accent or Theme.colors.success

    return Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        UI.Label { text = listing.name, fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = nameColor },
                        BuildQualityBadge(listing.rarity),
                        UI.Label { text = "x" .. tostring(listing.stock), fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
                    },
                },
                UI.Panel {
                    paddingHorizontal = 8, paddingVertical = 2, borderRadius = 4,
                    backgroundColor = status == "selling" and { 60, 100, 140, 80 } or { 60, 140, 60, 80 },
                    children = {
                        UI.Label { text = statusText, fontSize = Theme.fontSize.tiny, fontColor = statusColor },
                    },
                },
            },
        },
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center", marginTop = 2,
            children = {
                UI.Panel {
                    gap = 2,
                    children = {
                        UI.Panel {
                            flexDirection = "row", gap = 4, alignItems = "center",
                            children = {
                                UI.Label { text = "挂牌价", fontSize = Theme.fontSize.small, fontColor = { 140, 125, 105, 255 } },
                                UI.Label { text = tostring(listing.price) .. " " .. GameMarket.GetCurrencyLabel(listing.currency or "lingStone"), fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = (listing.currency == "spiritStone") and Theme.colors.gold or Theme.colors.accent },
                            },
                        },
                        UI.Label { text = "参考价: " .. tostring(listing.refPrice or listing.price) .. (listing.listedTime and ("  |  " .. listing.listedTime) or ""), fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    },
                },
                status == "selling" and UI.Panel {
                    paddingHorizontal = 12, paddingVertical = 5,
                    borderRadius = Theme.radius.sm,
                    backgroundColor = { 140, 60, 60, 200 },
                    cursor = "pointer",
                    onClick = function(self)
                        if IsNetworkMode() then
                            -- 网络模式：传 listing 对象（含 listId）
                            local ok, msg = GameMarket.DoDelistItem(0, listing)
                            Toast.Show(msg, { variant = ok and "success" or "error" })
                            if ok then
                                -- 刷新我的寄售列表
                                GameMarket.RequestMyListings()
                                Router.RebuildUI()
                            end
                        else
                            -- 单机模式：找到 listing 在 tradingListings 中的索引
                            local p = GamePlayer.Get()
                            if p and p.tradingListings then
                                for li, l in ipairs(p.tradingListings) do
                                    if l == listing then
                                        local ok, msg = GameMarket.DoDelistItem(li)
                                        Toast.Show(msg, { variant = ok and "success" or "error" })
                                        if ok then Router.RebuildUI() end
                                        break
                                    end
                                end
                            end
                        end
                    end,
                    children = {
                        UI.Label { text = "下架", fontSize = Theme.fontSize.small, fontWeight = "bold", fontColor = Theme.colors.textLight },
                    },
                } or nil,
            },
        },
    }, { borderColor = nameColor })
end

local function BuildHistoryRow(record)
    local isSold = record.type == "sold"
    return UI.Panel {
        width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
        paddingVertical = 4,
        borderBottomWidth = 1, borderColor = Theme.colors.divider,
        children = {
            UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center",
                children = {
                    UI.Label {
                        text = isSold and "卖出" or "买入",
                        fontSize = Theme.fontSize.tiny, fontWeight = "bold",
                        fontColor = isSold and Theme.colors.success or Theme.colors.accent,
                    },
                    UI.Label { text = record.name, fontSize = Theme.fontSize.small, fontColor = Theme.colors.textLight },
                },
            },
            UI.Panel {
                flexDirection = "row", gap = 6, alignItems = "center",
                children = {
                    UI.Label {
                        text = (isSold and "+" or "-") .. tostring(record.price) .. (isSold and (" (-" .. tostring(record.fee) .. ")") or ""),
                        fontSize = Theme.fontSize.small, fontWeight = "bold",
                        fontColor = isSold and Theme.colors.success or Theme.colors.accent,
                    },
                    UI.Label { text = record.time, fontSize = Theme.fontSize.tiny, fontColor = { 100, 90, 75, 150 } },
                },
            },
        },
    }
end

local function BuildMyTradeTab(p)
    local config = DataItems.TRADING_POST
    -- 网络模式：使用服务端返回的我的寄售列表；单机模式：玩家数据
    local myListings
    if IsNetworkMode() then
        myListings = GameMarket.GetMyListings() or {}
    else
        myListings = p.tradingListings or {}
    end
    local history = {}
    local activeCount = 0
    local totalPrice = 0
    for _, l in ipairs(myListings) do
        local st = l.status or "selling"
        if st == "selling" then
            activeCount = activeCount + 1
            totalPrice = totalPrice + (l.price or 0) * (l.stock or 1)
        end
    end
    local canList = activeCount < config.maxListings

    local result = {}

    -- 统计面板
    result[#result + 1] = Comp.BuildCardPanel(nil, {
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-around",
            children = {
                UI.Panel {
                    alignItems = "center",
                    children = {
                        UI.Label { text = tostring(activeCount) .. "/" .. tostring(config.maxListings), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.textGold },
                        UI.Label { text = "寄售中", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    },
                },
                UI.Panel {
                    alignItems = "center",
                    children = {
                        UI.Label { text = tostring(totalPrice), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.accent },
                        UI.Label { text = "总挂牌价", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    },
                },
                UI.Panel {
                    alignItems = "center",
                    children = {
                        UI.Label { text = "5~10%", fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.warning },
                        UI.Label { text = "手续费", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary },
                    },
                },
            },
        },
    })

    -- 上架按钮
    result[#result + 1] = UI.Panel {
        width = "100%", alignItems = "center", marginVertical = 4,
        children = {
            UI.Panel {
                paddingHorizontal = 32, paddingVertical = 10,
                borderRadius = Theme.radius.md,
                backgroundColor = canList and Theme.colors.gold or { 80, 70, 55, 150 },
                cursor = canList and "pointer" or "default",
                onClick = function(self)
                    if canList then
                        showListModal_ = true
                        selectedBagIdx_ = nil
                        listPrice_ = 0
                        listCount_ = 1
                        Router.RebuildUI()
                    end
                end,
                children = {
                    UI.Label {
                        text = canList and "上架物品" or ("已达上限 " .. tostring(config.maxListings) .. "/" .. tostring(config.maxListings)),
                        fontSize = Theme.fontSize.body, fontWeight = "bold",
                        fontColor = canList and Theme.colors.btnPrimaryText or Theme.colors.textSecondary,
                    },
                },
            },
        },
    }

    -- 寄售列表
    for i, listing in ipairs(myListings) do
        result[#result + 1] = BuildMyListingCard(listing, i)
    end

    -- 交易记录折叠
    result[#result + 1] = UI.Panel {
        width = "100%", marginTop = 8,
        children = {
            UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                paddingVertical = 6, cursor = "pointer",
                onClick = function(self)
                    showHistory_ = not showHistory_
                    Router.RebuildUI()
                end,
                children = {
                    UI.Label { text = "交易记录", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.textGold },
                    UI.Label { text = showHistory_ and "收起" or "展开", fontSize = Theme.fontSize.small, fontColor = Theme.colors.gold },
                },
            },
        },
    }

    if showHistory_ then
        local histPanel = Comp.BuildCardPanel(nil, {})
        local histChildren = {}
        for _, record in ipairs(history) do
            histChildren[#histChildren + 1] = BuildHistoryRow(record)
        end
        result[#result + 1] = Comp.BuildCardPanel(nil, histChildren)
    end

    return result
end

-- ============================================================================
-- 商铺购买确认弹窗（带数量选择）
-- ============================================================================
local function BuildShopBuyModal()
    if not showShopBuyModal_ or not shopBuyItem_ then return nil end
    local item = shopBuyItem_
    local nameColor, qualityBadge = BuildCategoryQualityBadge(item, item.shopCategory)
    local currencyColor = item.currency == "仙石" and Theme.colors.gold or Theme.colors.accent
    local maxCount = math.max(1, item.stock or 1)
    local totalCost = item.price * shopBuyCount_

    local currKey = item.currency == "仙石" and "spiritStone" or "lingStone"
    local balance = GamePlayer.GetCurrency(currKey)
    local canAfford = balance >= totalCost
    local canBuy = canAfford and shopBuyCount_ >= 1 and shopBuyCount_ <= maxCount

    -- 停止长按的通用回调
    local function stopHold() holdDir_ = 0 end

    -- 构建 children（避免 nil 空洞导致后续元素丢失）
    local bodyChildren = {
        UI.Label { text = "购买确认", fontSize = Theme.fontSize.heading, fontWeight = "bold", fontColor = Theme.colors.textGold, textAlign = "center", width = "100%" },
        Comp.BuildInkDivider(),
        -- 物品名 + 品质徽标 + 库存
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        UI.Label { text = item.name, fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = nameColor },
                        qualityBadge,
                    },
                },
                UI.Label { text = "库存: " .. tostring(item.stock), fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
            },
        },
        -- 物品描述（RT.Build 高亮关键数值）
        RT.Build(item.desc or "", Theme.fontSize.small, Theme.colors.textLight),
        Comp.BuildInkDivider(),
        -- 数量选择：[最少] [-] [数量/输入框] [+] [最多]，点击数量可手动输入
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            children = {
                UI.Label { text = "数量", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                UI.Panel {
                    flexDirection = "row", gap = 6, alignItems = "center",
                    children = {
                        -- 最少
                        UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 4, borderRadius = 4,
                            backgroundColor = { 55, 48, 36, 220 },
                            borderColor = { 120, 100, 70, 120 }, borderWidth = 1,
                            cursor = "pointer",
                            onClick = function()
                                shopBuyCount_ = 1
                                shopBuyInputMode_ = false
                                Router.RebuildUI()
                            end,
                            children = { UI.Label { text = "最少", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary } },
                        },
                        -- 减
                        UI.Panel {
                            paddingHorizontal = 10, paddingVertical = 4, borderRadius = 4,
                            backgroundColor = shopBuyCount_ > 1 and Theme.colors.gold or { 80, 70, 55, 150 },
                            cursor = shopBuyCount_ > 1 and "pointer" or "default",
                            onClick = function()
                                if shopBuyCount_ > 1 then
                                    shopBuyCount_ = shopBuyCount_ - 1
                                    shopBuyInputMode_ = false
                                    Router.RebuildUI()
                                end
                            end,
                            onPointerDown = function() holdDir_ = -1; holdTimer_ = 0 end,
                            onPointerUp = stopHold,
                            children = { UI.Label { text = "-", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                        },
                        -- 数量：输入模式 → TextField；展示模式 → 可点击的数字框
                        (function()
                            local function applyInput(v)
                                local n = tonumber(v)
                                if n then
                                    shopBuyCount_ = math.max(1, math.min(maxCount, math.floor(n)))
                                end
                                shopBuyInputMode_ = false
                                Router.RebuildUI()
                            end
                            if shopBuyInputMode_ then
                                return UI.TextField {
                                    value    = tostring(shopBuyCount_),
                                    width    = 58, height = 32,
                                    fontSize = Theme.fontSize.subtitle,
                                    maxLength = 5,
                                    onChange  = function() end,
                                    onSubmit  = function(self, v) applyInput(v) end,
                                    onBlur    = function(self) applyInput(self.props.value or "") end,
                                }
                            else
                                return UI.Panel {
                                    width = 58, height = 32,
                                    alignItems = "center", justifyContent = "center",
                                    borderRadius = 4,
                                    borderColor = { 120, 100, 70, 120 }, borderWidth = 1,
                                    backgroundColor = { 40, 35, 25, 160 },
                                    cursor = "pointer",
                                    onClick = function()
                                        shopBuyInputMode_ = true
                                        Router.RebuildUI()
                                    end,
                                    children = {
                                        UI.Label {
                                            text = tostring(shopBuyCount_),
                                            fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                                            fontColor = Theme.colors.textLight, textAlign = "center",
                                        },
                                    },
                                }
                            end
                        end)(),
                        -- 加
                        UI.Panel {
                            paddingHorizontal = 10, paddingVertical = 4, borderRadius = 4,
                            backgroundColor = shopBuyCount_ < maxCount and Theme.colors.gold or { 80, 70, 55, 150 },
                            cursor = shopBuyCount_ < maxCount and "pointer" or "default",
                            onClick = function()
                                if shopBuyCount_ < maxCount then
                                    shopBuyCount_ = shopBuyCount_ + 1
                                    shopBuyInputMode_ = false
                                    Router.RebuildUI()
                                end
                            end,
                            onPointerDown = function() holdDir_ = 1; holdTimer_ = 0 end,
                            onPointerUp = stopHold,
                            children = { UI.Label { text = "+", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                        },
                        -- 最多
                        UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 4, borderRadius = 4,
                            backgroundColor = { 55, 48, 36, 220 },
                            borderColor = { 120, 100, 70, 120 }, borderWidth = 1,
                            cursor = "pointer",
                            onClick = function()
                                shopBuyCount_ = maxCount
                                shopBuyInputMode_ = false
                                Router.RebuildUI()
                            end,
                            children = { UI.Label { text = "最多", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.textSecondary } },
                        },
                    },
                },
            },
        },
        -- 单价
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between",
            children = {
                UI.Label { text = "单价", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                UI.Label { text = tostring(item.price) .. " " .. item.currency, fontSize = Theme.fontSize.body, fontColor = currencyColor },
            },
        },
        -- 总价
        UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between",
            children = {
                UI.Label { text = "总价", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.textSecondary },
                UI.Label {
                    text = tostring(totalCost) .. " " .. item.currency,
                    fontSize = Theme.fontSize.subtitle, fontWeight = "bold",
                    fontColor = canAfford and Theme.colors.gold or Theme.colors.danger,
                },
            },
        },
    }

    -- 余额不足提示（条件插入，不产生 nil 空洞）
    if not canAfford then
        bodyChildren[#bodyChildren + 1] = UI.Label {
            text = item.currency .. "不足，当前: " .. tostring(balance),
            fontSize = Theme.fontSize.small, fontColor = Theme.colors.danger,
            width = "100%", textAlign = "center",
        }
    end

    bodyChildren[#bodyChildren + 1] = Comp.BuildInkDivider()

    -- 按钮行
    bodyChildren[#bodyChildren + 1] = UI.Panel {
        width = "100%", flexDirection = "row", gap = 12, justifyContent = "center",
        children = {
            UI.Panel {
                flex = 1, paddingVertical = 10, borderRadius = Theme.radius.sm,
                backgroundColor = { 80, 70, 55, 200 }, alignItems = "center", cursor = "pointer",
                onClick = function(self)
                    showShopBuyModal_ = false
                    shopBuyItem_ = nil
                    holdDir_ = 0
                    shopBuyInputMode_ = false
                    Router.RebuildUI()
                end,
                children = { UI.Label { text = "取消", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } },
            },
            UI.Panel {
                flex = 1, paddingVertical = 10, borderRadius = Theme.radius.sm,
                backgroundColor = canBuy and Theme.colors.gold or { 80, 70, 55, 150 },
                alignItems = "center",
                cursor = canBuy and "pointer" or "default",
                onClick = function(self)
                    if not canBuy then return end
                    holdDir_ = 0
                    local ok, msg = GameMarket.DoBuyGoods(shopBuyItem_, shopBuyCount_)
                    -- 网络模式 DoBuyGoods 立即返回 (true, nil)，异步回调里已有 Toast
                    if msg and msg ~= "" then
                        Toast.Show(msg, { variant = ok and "success" or "error" })
                    end
                    showShopBuyModal_ = false
                    shopBuyItem_ = nil
                    shopBuyInputMode_ = false
                    Router.RebuildUI()
                end,
                children = {
                    UI.Label {
                        text = canBuy and "确认购买" or "无法购买",
                        fontSize = Theme.fontSize.body, fontWeight = "bold",
                        fontColor = canBuy and Theme.colors.btnPrimaryText or Theme.colors.textSecondary,
                    },
                },
            },
        },
    }

    return UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            showShopBuyModal_ = false
            shopBuyItem_ = nil
            holdDir_ = 0
            shopBuyInputMode_ = false
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "82%", maxWidth = 340,
                backgroundColor = { 40, 35, 28, 245 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.sm,
                onClick = function(self) end,
                children = bodyChildren,
            },
        },
    }
end

-- ============================================================================
-- 寄售坊购买确认弹窗
-- ============================================================================
local function BuildConfirmModal()
    if not showConfirmModal_ or not confirmItem_ then return nil end
    local item = confirmItem_
    local seller = item.sellerUid
        and { name = "玩家#" .. tostring(item.sellerUid), realm = "" }
        or GetSellerById(item.sellerId)
    local nameColor = getRarityColor(item.rarity)

    return UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            showConfirmModal_ = false
            confirmItem_ = nil
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "82%", maxWidth = 340,
                backgroundColor = { 40, 35, 28, 245 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.lg,
                gap = Theme.spacing.sm,
                onClick = function(self) end,  -- 阻止穿透
                children = {
                    UI.Label { text = "确认购买", fontSize = Theme.fontSize.heading, fontWeight = "bold", fontColor = Theme.colors.textGold, textAlign = "center", width = "100%" },
                    Comp.BuildInkDivider(),
                    -- 物品信息
                    UI.Panel {
                        width = "100%", gap = 4,
                        children = {
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "物品", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                                    UI.Label { text = item.name .. " x" .. tostring(item.stock), fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = nameColor },
                                },
                            },
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "卖家", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                                    UI.Label { text = seller.name, fontSize = Theme.fontSize.body, fontColor = Theme.colors.textGold },
                                },
                            },
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "单价", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                                    UI.Label { text = tostring(item.price) .. " " .. GameMarket.GetCurrencyLabel(item.currency or "lingStone"), fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = (item.currency == "spiritStone") and Theme.colors.gold or Theme.colors.accent },
                                },
                            },
                            UI.Panel {
                                width = "100%", flexDirection = "row", justifyContent = "space-between",
                                children = {
                                    UI.Label { text = "总价", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                                    UI.Label { text = tostring(item.price * item.stock) .. " " .. GameMarket.GetCurrencyLabel(item.currency or "lingStone"), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.gold },
                                },
                            },
                        },
                    },
                    Comp.BuildInkDivider(),
                    -- 按钮行
                    UI.Panel {
                        width = "100%", flexDirection = "row", gap = 12, justifyContent = "center",
                        children = {
                            UI.Panel {
                                flex = 1, paddingVertical = 10, borderRadius = Theme.radius.sm,
                                backgroundColor = { 80, 70, 55, 200 }, alignItems = "center", cursor = "pointer",
                                onClick = function(self)
                                    showConfirmModal_ = false
                                    confirmItem_ = nil
                                    Router.RebuildUI()
                                end,
                                children = { UI.Label { text = "取消", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } },
                            },
                            UI.Panel {
                                flex = 1, paddingVertical = 10, borderRadius = Theme.radius.sm,
                                backgroundColor = Theme.colors.gold, alignItems = "center", cursor = "pointer",
                                onClick = function(self)
                                    local ok, msg = GameMarket.DoBuyListing(item)
                                    Toast.Show(msg, { variant = ok and "success" or "error" })
                                    showConfirmModal_ = false
                                    confirmItem_ = nil
                                    Router.RebuildUI()
                                end,
                                children = { UI.Label { text = "确认购买", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 上架物品弹窗
-- ============================================================================
local function BuildListModal()
    if not showListModal_ then return nil end
    local pData = GamePlayer.Get()
    local bag = pData and pData.bagItems or {}
    local config = DataItems.TRADING_POST

    -- 可上架物品列表（背包物品 + 法宝）
    local bagChildren = {}
    -- 记录选中物品的货币信息（供定价区域使用）
    local selectedCurrKey_ = "lingStone"
    local selectedItemType_ = "bagItem"

    for i, item in ipairs(bag) do
        local tradable, currKey, tradeReason = GameMarket.GetBagItemTradeInfo(item)
        local isSelected = (selectedItemType_ == "bagItem" and i == selectedBagIdx_)
        local nameColor = tradable and getRarityColor(item.rarity) or { 130, 120, 105, 200 }
        local currLabel = tradable and GameMarket.GetCurrencyLabel(currKey) or ""
        local rowBg = isSelected and { 55, 85, 45, 220 }
                      or (tradable and { 38, 33, 25, 200 } or { 30, 27, 22, 160 })
        bagChildren[#bagChildren + 1] = UI.Panel {
            width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
            paddingVertical = 9, paddingHorizontal = 12,
            marginBottom = 4,
            borderRadius = Theme.radius.sm,
            backgroundColor = rowBg,
            borderWidth = isSelected and 1 or 0,
            borderColor = Theme.colors.gold,
            cursor = tradable and "pointer" or "default",
            onClick = function(self)
                if not tradable then
                    Toast.Show(tradeReason or "该物品不可交易", "error")
                    return
                end
                selectedBagIdx_ = i
                selectedItemType_ = "bagItem"
                selectedCurrKey_ = currKey
                listCount_ = 1
                local refPrices = { common = 25, uncommon = 150, rare = 400, epic = 800, legend = 2000 }
                listPrice_ = refPrices[item.rarity] or 50
                Router.RebuildUI()
            end,
            children = {
                -- 左侧：名称 + 数量
                UI.Panel { flex = 1, flexDirection = "row", alignItems = "center", gap = 8,
                    children = {
                        UI.Label {
                            text = item.name,
                            fontSize = Theme.fontSize.body, fontWeight = "bold",
                            fontColor = nameColor,
                        },
                        UI.Panel {
                            paddingHorizontal = 6, paddingVertical = 2,
                            borderRadius = 8,
                            backgroundColor = { 55, 50, 40, 200 },
                            children = {
                                UI.Label { text = "x" .. tostring(item.count),
                                    fontSize = Theme.fontSize.tiny,
                                    fontColor = tradable and Theme.colors.textSecondary or { 100, 95, 85, 180 } },
                            },
                        },
                    },
                },
                -- 右侧：可交易状态 + 已选标记
                UI.Panel { flexDirection = "row", alignItems = "center", gap = 8,
                    children = {
                        tradable and UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 3,
                            borderRadius = 8,
                            backgroundColor = currKey == "spiritStone" and { 80, 65, 20, 200 } or { 25, 60, 35, 200 },
                            children = {
                                UI.Label { text = currLabel, fontSize = Theme.fontSize.tiny,
                                    fontColor = currKey == "spiritStone" and Theme.colors.textGold or Theme.colors.successLight },
                            },
                        } or UI.Panel {
                            paddingHorizontal = 8, paddingVertical = 3,
                            borderRadius = 8,
                            backgroundColor = { 70, 25, 25, 180 },
                            children = {
                                UI.Label { text = "不可交易", fontSize = Theme.fontSize.tiny, fontColor = Theme.colors.danger },
                            },
                        },
                        isSelected and UI.Label { text = "选中", fontSize = Theme.fontSize.tiny,
                            fontWeight = "bold", fontColor = Theme.colors.textGold } or nil,
                    },
                },
            },
        }
    end

    -- 法宝列表
    local artifacts = pData and pData.artifacts or {}
    if #artifacts > 0 then
        bagChildren[#bagChildren + 1] = UI.Panel {
            width = "100%", paddingVertical = 4, marginTop = 4,
            borderTopWidth = 1, borderColor = Theme.colors.divider,
            children = {
                UI.Label { text = "-- 法宝 --", fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary, textAlign = "center", width = "100%" },
            },
        }
        for ai, art in ipairs(artifacts) do
            local tradable, currKey, tradeReason = GameMarket.GetArtifactTradeInfo(art)
            local isSelected = (selectedItemType_ == "artifact" and ai == selectedBagIdx_)
            local nameColor = tradable and getRarityColor(art.quality) or { 130, 120, 105, 200 }
            local currLabel = tradable and GameMarket.GetCurrencyLabel(currKey) or ""
            local qLabel = DataItems.GetQualityLabel(art.quality) or ""
            local rowBg = isSelected and { 55, 85, 45, 220 }
                          or (tradable and { 38, 33, 25, 200 } or { 30, 27, 22, 160 })
            bagChildren[#bagChildren + 1] = UI.Panel {
                width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                paddingVertical = 9, paddingHorizontal = 12,
                marginBottom = 4,
                borderRadius = Theme.radius.sm,
                backgroundColor = rowBg,
                borderWidth = isSelected and 1 or 0,
                borderColor = Theme.colors.gold,
                cursor = tradable and "pointer" or "default",
                onClick = function(self)
                    if not tradable then
                        Toast.Show(tradeReason or "该法宝不可交易", "error")
                        return
                    end
                    selectedBagIdx_ = ai
                    selectedItemType_ = "artifact"
                    selectedCurrKey_ = currKey
                    listCount_ = 1
                    local refPrices = { fanqi = 100, lingqi = 300, xuanqi = 600, diqi = 1500, tianqi = 3000, xianqi = 8000 }
                    listPrice_ = refPrices[art.quality] or 200
                    Router.RebuildUI()
                end,
                children = {
                    -- 左侧：名称 + 品质 + 装备状态
                    UI.Panel { flex = 1, flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            UI.Label { text = art.name, fontSize = Theme.fontSize.body,
                                fontWeight = "bold", fontColor = nameColor },
                            UI.Panel {
                                paddingHorizontal = 6, paddingVertical = 2,
                                borderRadius = 8,
                                backgroundColor = { 55, 50, 40, 200 },
                                children = {
                                    UI.Label { text = qLabel, fontSize = Theme.fontSize.tiny, fontColor = nameColor },
                                },
                            },
                            art.equipped and UI.Panel {
                                paddingHorizontal = 6, paddingVertical = 2,
                                borderRadius = 8,
                                backgroundColor = { 80, 60, 20, 200 },
                                children = {
                                    UI.Label { text = "装备中", fontSize = Theme.fontSize.tiny,
                                        fontColor = Theme.colors.warning },
                                },
                            } or nil,
                        },
                    },
                    -- 右侧：状态 + 选中
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 8,
                        children = {
                            tradable and UI.Panel {
                                paddingHorizontal = 8, paddingVertical = 3,
                                borderRadius = 8,
                                backgroundColor = currKey == "spiritStone" and { 80, 65, 20, 200 } or { 25, 60, 35, 200 },
                                children = {
                                    UI.Label { text = currLabel, fontSize = Theme.fontSize.tiny,
                                        fontColor = currKey == "spiritStone" and Theme.colors.textGold or Theme.colors.successLight },
                                },
                            } or UI.Panel {
                                paddingHorizontal = 8, paddingVertical = 3,
                                borderRadius = 8,
                                backgroundColor = { 70, 25, 25, 180 },
                                children = {
                                    UI.Label { text = tradeReason or "不可交易", fontSize = Theme.fontSize.tiny,
                                        fontColor = Theme.colors.danger },
                                },
                            },
                            isSelected and UI.Label { text = "选中", fontSize = Theme.fontSize.tiny,
                                fontWeight = "bold", fontColor = Theme.colors.textGold } or nil,
                        },
                    },
                },
            }
        end
    end

    -- 定价区域（仅选中物品后显示）
    local pricingSection = nil
    if selectedBagIdx_ then
        -- 根据选中物品类型获取信息
        local selName, selMaxCount, selCurrKey
        if selectedItemType_ == "artifact" then
            local art = artifacts[selectedBagIdx_]
            selName = art and art.name or "?"
            selMaxCount = 1
            local _, ck = GameMarket.GetArtifactTradeInfo(art)
            selCurrKey = ck or "lingStone"
        else
            local selItem = bag[selectedBagIdx_]
            selName = selItem and selItem.name or "?"
            selMaxCount = selItem and selItem.count or 1
            local _, ck = GameMarket.GetBagItemTradeInfo(selItem)
            selCurrKey = ck or "lingStone"
        end
        local selCurrLabel = GameMarket.GetCurrencyLabel(selCurrKey)
        local selFeeRate = DataItems.GetTradeFeeRate(selCurrKey)
        local fee = math.floor(listPrice_ * listCount_ * selFeeRate)
        local income = listPrice_ * listCount_ - fee

        pricingSection = UI.Panel {
            width = "100%", gap = 6, marginTop = 4,
            padding = Theme.spacing.sm,
            backgroundColor = { 50, 45, 35, 200 },
            borderRadius = Theme.radius.sm,
            children = {
                UI.Label { text = "上架: " .. selName, fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.textGold },
                -- 数量（法宝固定为1）
                selectedItemType_ ~= "artifact" and UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label { text = "数量", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                        UI.Panel {
                            flexDirection = "row", gap = 8, alignItems = "center",
                            children = {
                                UI.Panel {
                                    paddingHorizontal = 10, paddingVertical = 4, borderRadius = 4,
                                    backgroundColor = listCount_ > 1 and Theme.colors.gold or { 80, 70, 55, 150 },
                                    cursor = listCount_ > 1 and "pointer" or "default",
                                    onClick = function(self)
                                        if listCount_ > 1 then listCount_ = listCount_ - 1; Router.RebuildUI() end
                                    end,
                                    children = { UI.Label { text = "-", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                                },
                                UI.Label { text = tostring(listCount_), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.textLight, width = 30, textAlign = "center" },
                                UI.Panel {
                                    paddingHorizontal = 10, paddingVertical = 4, borderRadius = 4,
                                    backgroundColor = listCount_ < selMaxCount and Theme.colors.gold or { 80, 70, 55, 150 },
                                    cursor = listCount_ < selMaxCount and "pointer" or "default",
                                    onClick = function(self)
                                        if listCount_ < selMaxCount then listCount_ = listCount_ + 1; Router.RebuildUI() end
                                    end,
                                    children = { UI.Label { text = "+", fontSize = Theme.fontSize.body, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                                },
                            },
                        },
                    },
                } or nil,
                -- 单价
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between", alignItems = "center",
                    children = {
                        UI.Label { text = "单价(" .. selCurrLabel .. ")", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textSecondary },
                        UI.Panel {
                            flexDirection = "row", gap = 8, alignItems = "center",
                            children = {
                                UI.Panel {
                                    paddingHorizontal = 10, paddingVertical = 4, borderRadius = 4,
                                    backgroundColor = listPrice_ > 1 and Theme.colors.gold or { 80, 70, 55, 150 },
                                    cursor = "pointer",
                                    onClick = function(self)
                                        listPrice_ = math.max(1, listPrice_ - 10)
                                        Router.RebuildUI()
                                    end,
                                    children = { UI.Label { text = "-10", fontSize = Theme.fontSize.small, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                                },
                                UI.Label { text = tostring(listPrice_), fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.accent, width = 50, textAlign = "center" },
                                UI.Panel {
                                    paddingHorizontal = 10, paddingVertical = 4, borderRadius = 4,
                                    backgroundColor = Theme.colors.gold, cursor = "pointer",
                                    onClick = function(self)
                                        listPrice_ = listPrice_ + 10
                                        Router.RebuildUI()
                                    end,
                                    children = { UI.Label { text = "+10", fontSize = Theme.fontSize.small, fontWeight = "bold", fontColor = Theme.colors.btnPrimaryText } },
                                },
                            },
                        },
                    },
                },
                Comp.BuildInkDivider(),
                -- 费用预览
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                    children = {
                        UI.Label { text = "总价", fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
                        UI.Label { text = tostring(listPrice_ * listCount_) .. " " .. selCurrLabel, fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                    children = {
                        UI.Label { text = "手续费(" .. tostring(math.floor(selFeeRate * 100)) .. "%)", fontSize = Theme.fontSize.small, fontColor = Theme.colors.textSecondary },
                        UI.Label { text = "-" .. tostring(fee) .. " " .. selCurrLabel, fontSize = Theme.fontSize.body, fontColor = Theme.colors.danger },
                    },
                },
                UI.Panel {
                    width = "100%", flexDirection = "row", justifyContent = "space-between",
                    children = {
                        UI.Label { text = "预计到手", fontSize = Theme.fontSize.small, fontWeight = "bold", fontColor = Theme.colors.textGold },
                        UI.Label { text = tostring(income) .. " " .. selCurrLabel, fontSize = Theme.fontSize.subtitle, fontWeight = "bold", fontColor = Theme.colors.success },
                    },
                },
            },
        }
    end

    return UI.Panel {
        position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        backgroundColor = { 0, 0, 0, 160 },
        justifyContent = "center", alignItems = "center",
        onClick = function(self)
            showListModal_ = false
            selectedBagIdx_ = nil
            Router.RebuildUI()
        end,
        children = {
            UI.Panel {
                width = "88%", maxWidth = 360, maxHeight = "80%",
                backgroundColor = { 40, 35, 28, 245 },
                borderRadius = Theme.radius.lg,
                borderColor = Theme.colors.borderGold,
                borderWidth = 1,
                padding = Theme.spacing.md,
                gap = Theme.spacing.sm,
                onClick = function(self) end,
                children = {
                    UI.Label { text = "上架物品", fontSize = Theme.fontSize.heading, fontWeight = "bold", fontColor = Theme.colors.textGold, textAlign = "center", width = "100%" },
                    Comp.BuildInkDivider(),
                    -- 背包列表（可滚动）
                    UI.ScrollView {
                        width = "100%", height = selectedBagIdx_ and 150 or 280,
                        scrollMultiplier = Theme.scrollSensitivity,
                        children = bagChildren,
                    },
                    -- 定价区域
                    pricingSection,
                    -- 按钮行
                    UI.Panel {
                        width = "100%", flexDirection = "row", gap = 12, justifyContent = "center", marginTop = 6,
                        children = {
                            UI.Panel {
                                flex = 1, paddingVertical = 10, borderRadius = Theme.radius.sm,
                                backgroundColor = { 80, 70, 55, 200 }, alignItems = "center", cursor = "pointer",
                                onClick = function(self)
                                    showListModal_ = false
                                    selectedBagIdx_ = nil
                                    Router.RebuildUI()
                                end,
                                children = { UI.Label { text = "取消", fontSize = Theme.fontSize.body, fontColor = Theme.colors.textLight } },
                            },
                            UI.Panel {
                                flex = 1, paddingVertical = 10, borderRadius = Theme.radius.sm,
                                backgroundColor = selectedBagIdx_ and Theme.colors.gold or { 80, 70, 55, 150 },
                                alignItems = "center",
                                cursor = selectedBagIdx_ and "pointer" or "default",
                                onClick = function(self)
                                    if selectedBagIdx_ then
                                        local ok, msg
                                        if selectedItemType_ == "artifact" then
                                            ok, msg = GameMarket.DoListArtifact(selectedBagIdx_, listPrice_)
                                        else
                                            ok, msg = GameMarket.DoListItem(selectedBagIdx_, listPrice_, listCount_)
                                        end
                                        Toast.Show(msg, { variant = ok and "success" or "error" })
                                        showListModal_ = false
                                        selectedBagIdx_ = nil
                                        Router.RebuildUI()
                                    end
                                end,
                                children = {
                                    UI.Label {
                                        text = selectedBagIdx_ and "确认上架" or "请选择物品",
                                        fontSize = Theme.fontSize.body, fontWeight = "bold",
                                        fontColor = selectedBagIdx_ and Theme.colors.btnPrimaryText or Theme.colors.textSecondary,
                                    },
                                },
                            },
                        },
                    },
                },
            },
        },
    }
end

-- ============================================================================
-- 构建页面
-- ============================================================================
function M.Build(payload)
    local p = GamePlayer.Get()
    if not p then return UI.Panel { width = "100%", height = "100%" } end

    -- 进入坊市时主动同步货币余额（仅一次）
    if not currencySynced_ and IsNetworkMode() then
        currencySynced_ = true
        -- 注册货币变化监听：灵石/仙石变动时自动刷新坊市 UI
        GamePlayer.OnCurrencyChange("market", function(changedKeys)
            Router.RebuildUI()
        end)
        local GameOps = require("network.game_ops")
        local GameServer = require("game_server")
        GameOps.Request("currency_get", { playerKey = GameServer.GetServerKey("player") }, function(ok2, data)
            if ok2 then
                Router.RebuildUI()
            end
        end)
    end

    -- 根据主标签切换内容
    local tabContent
    if selectedMainTab_ == 1 then
        tabContent = BuildShopTab(p)
    elseif selectedMainTab_ == 2 then
        tabContent = BuildTradingPostTab(p)
    else
        tabContent = BuildMyTradeTab(p)
    end

    local contentChildren = { BuildBackRow(), BuildMainTabs() }
    for _, child in ipairs(tabContent) do
        contentChildren[#contentChildren + 1] = child
    end

    local page = Comp.BuildPageShell("home", p, contentChildren, Router.HandleNavigate)

    -- 弹窗叠加层
    local modal = BuildShopBuyModal() or BuildConfirmModal() or BuildListModal()
    if modal then
        page:AddChild(modal)
    end

    return page
end

-- ============================================================================
-- 长按 +/- 快速加减（注册全局 updater）
-- ============================================================================
NVG.Register("market_hold", nil, function(dt)
    if holdDir_ == 0 or not showShopBuyModal_ or not shopBuyItem_ then
        holdDir_ = 0
        return
    end
    holdTimer_ = holdTimer_ + dt
    if holdTimer_ < HOLD_DELAY then return end
    -- 进入连续触发阶段
    holdTimer_ = holdTimer_ - HOLD_RATE
    local maxCount = math.max(1, shopBuyItem_.stock or 1)
    local changed = false
    if holdDir_ == 1 and shopBuyCount_ < maxCount then
        shopBuyCount_ = shopBuyCount_ + 1
        changed = true
    elseif holdDir_ == -1 and shopBuyCount_ > 1 then
        shopBuyCount_ = shopBuyCount_ - 1
        changed = true
    end
    if changed then Router.RebuildUI() end
end)

return M
