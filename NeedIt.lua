-- NeedIt: tells you if gear is good for YOUR class + spec.
-- Tooltip verdict (NEED / GREED / PASS) with the reason, weapon-aware scoring,
-- upgrade comparison, markers on bag/vendor items and group-loot roll frames.
NeedItDB = NeedItDB or {}

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats
local GetBagLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink

local function set(...) local t = {} for _, v in ipairs({...}) do t[v] = true end return t end

---------------------------------------------------------------------------
-- Data: what each role values. Weights are "worth per point" (attack power = 1).
---------------------------------------------------------------------------
-- dpsW = weight of melee weapon DPS, rdps = weight of ranged/wand DPS.
local KINDS = {
  MELEE_STR  = { dpsW = 4, rdps = 3, w = { STR=2, AGI=1, AP=1, CRIT=1.2, HIT=1.2, HASTE=1.2, STA=0.2 } },
  MELEE_AGI  = { dpsW = 4, rdps = 3, w = { AGI=2, STR=1, AP=1, CRIT=1.2, HIT=1.2, HASTE=1.2, STA=0.2 } },
  RANGED_AGI = { dpsW = 0.5, rdps = 8, w = { AGI=2, AP=1, CRIT=1.2, HIT=1.2, HASTE=1.2, INT=0.5, MP5=0.3, STA=0.2 } },
  TANK_STR   = { dpsW = 2, rdps = 1, w = { STA=1.5, STR=1, AGI=1, DEF=1.5, DODGE=1.2, PARRY=1.2, BLOCK=0.8, HIT=1, CRIT=0.5, AP=0.3 } },
  FERAL      = { dpsW = 0, rdps = 0, w = { STR=2, AGI=2, AP=1, STA=0.5, CRIT=1.2, HIT=1.2, HASTE=1.2, DODGE=0.5 } },
  CASTER     = { dpsW = 0, rdps = 2, w = { INT=1.5, SP=2.5, SPD=2.5, CRIT=1.2, HIT=1.5, HASTE=1.2, MP5=0.5, SPI=0.5, STA=0.3 } },
  HEALER     = { dpsW = 0, rdps = 2, w = { INT=1.5, SPI=1.2, HEAL=2.5, SP=2, MP5=1.5, CRIT=0.8, HASTE=1, STA=0.3 } },
}

-- Indexed by spec / talent-tree order: {name, kind, options}
-- options: w = weight overrides, dagger = "main"|"avoid", twoHand = "want"|"avoid"
local SPECS = {
  WARRIOR = { {"Arms","MELEE_STR",{twoHand="want"}}, {"Fury","MELEE_STR"}, {"Protection","TANK_STR",{twoHand="avoid"}} },
  PALADIN = { {"Holy","HEALER"}, {"Protection","TANK_STR",{twoHand="avoid"}}, {"Retribution","MELEE_STR",{twoHand="want"}} },
  HUNTER  = { {"Beast Mastery","RANGED_AGI"}, {"Marksmanship","RANGED_AGI"}, {"Survival","RANGED_AGI"} },
  ROGUE   = { {"Assassination","MELEE_AGI",{dagger="main"}}, {"Combat","MELEE_AGI",{dagger="avoid"}}, {"Subtlety","MELEE_AGI",{dagger="main"}} },
  PRIEST  = { {"Discipline","HEALER"}, {"Holy","HEALER"}, {"Shadow","CASTER",{w={SPI=0.8}}} },
  SHAMAN  = { {"Elemental","CASTER"}, {"Enhancement","MELEE_AGI",{w={STR=2,AGI=1.5}}}, {"Restoration","HEALER"} },
  MAGE    = { {"Arcane","CASTER"}, {"Fire","CASTER"}, {"Frost","CASTER"} },
  WARLOCK = { {"Affliction","CASTER"}, {"Demonology","CASTER"}, {"Destruction","CASTER"} },
  DRUID   = { {"Balance","CASTER"}, {"Feral","FERAL"}, {"Restoration","HEALER"} },
}
local DRUID_MODERN = { {"Balance","CASTER"}, {"Feral","FERAL"}, {"Guardian","FERAL"}, {"Restoration","HEALER"} }

-- Spec index to assume before any talent points are spent (typical leveling spec)
local DEFAULT_SPEC = { WARRIOR=1, PALADIN=3, HUNTER=1, ROGUE=2, PRIEST=3, SHAMAN=2, MAGE=3, WARLOCK=1, DRUID=2 }

-- Highest armor type a class can wear (subclass ids: 1 cloth, 2 leather, 3 mail, 4 plate)
local ARMOR = { WARRIOR=4, PALADIN=4, HUNTER=3, SHAMAN=3, ROGUE=2, DRUID=2, PRIEST=1, MAGE=1, WARLOCK=1 }
local ARMOR_NAMES = { "cloth", "leather", "mail", "plate" }
local ARMOR_LEVEL = 40    -- mail/plate classes wear one tier lower until this level

-- Armor type the player can wear right now
local function MaxArmor(class)
  local max = ARMOR[class] or 1
  if max >= 3 and (UnitLevel("player") or 0) < ARMOR_LEVEL then return max - 1 end
  return max
end

-- Classic: only these classes can dual wield (used when CanDualWield() is unavailable)
local DUAL_WIELD = set("WARRIOR","ROGUE","HUNTER")
local BODY_SLOTS = set("INVTYPE_HEAD","INVTYPE_SHOULDER","INVTYPE_CHEST","INVTYPE_ROBE","INVTYPE_WAIST",
  "INVTYPE_LEGS","INVTYPE_FEET","INVTYPE_WRIST","INVTYPE_HAND")

-- Weapon subclass ids: 0 1hAxe 1 2hAxe 2 Bow 3 Gun 4 1hMace 5 2hMace 6 Polearm 7 1hSword 8 2hSword
-- 10 Staff 13 Fist 15 Dagger 16 Thrown 18 Crossbow 19 Wand
local WEAPONS = {
  WARRIOR = set(0,1,2,3,4,5,6,7,8,10,13,15,16,18),
  PALADIN = set(0,1,4,5,6,7,8),
  HUNTER  = set(0,1,2,3,6,7,8,10,13,15,16,18),
  ROGUE   = set(0,2,3,4,7,13,15,16,18),
  PRIEST  = set(4,10,15,19),
  SHAMAN  = set(0,1,4,5,10,13,15),
  MAGE    = set(7,10,15,19),
  WARLOCK = set(7,10,15,19),
  DRUID   = set(4,5,10,13,15),
}
local SHIELD = set("WARRIOR","PALADIN","SHAMAN")
local RANGED_SUB = set(2,3,16,18,19)

local SLOTS = {
  INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3}, INVTYPE_CHEST={5}, INVTYPE_ROBE={5},
  INVTYPE_WAIST={6}, INVTYPE_LEGS={7}, INVTYPE_FEET={8}, INVTYPE_WRIST={9}, INVTYPE_HAND={10},
  INVTYPE_FINGER={11,12}, INVTYPE_TRINKET={13,14}, INVTYPE_CLOAK={15},
  INVTYPE_WEAPON={16,17}, INVTYPE_2HWEAPON={16}, INVTYPE_WEAPONMAINHAND={16},
  INVTYPE_WEAPONOFFHAND={17}, INVTYPE_SHIELD={17}, INVTYPE_HOLDABLE={17},
  INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18}, INVTYPE_THROWN={18}, INVTYPE_RELIC={18},
}

local NAMES = { STR="Strength", AGI="Agility", INT="Intellect", SPI="Spirit", STA="Stamina",
  AP="Attack Power", SP="Spell Power", SPD="Spell Damage", HEAL="Healing", CRIT="Crit", HIT="Hit",
  HASTE="Haste", MP5="MP5", DEF="Defense", DODGE="Dodge", PARRY="Parry", BLOCK="Block" }

local PCT_MULT = 14       -- "+1% crit" is treated as roughly 14 rating points
local EFFECT_VALUE = 40   -- flat worth of a proc / on-use effect line
local PCT_STATS = set("CRIT","HIT","DODGE","PARRY","BLOCK","HASTE")

local COLORS = { NEED="|cff33ff33", GREED="|cffffd100", PASS="|cffff4040", GRAY="|cffaaaaaa" }

---------------------------------------------------------------------------
-- Per-character data (spec override, ignore list, wanted list)
---------------------------------------------------------------------------
local function PlayerClass() local _, token = UnitClass("player") return token end
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end

local function CharData()
  NeedItDB.chars = NeedItDB.chars or {}
  local key = CharKey()
  local d = NeedItDB.chars[key]
  if type(d) == "number" then d = { spec = d } end
  if type(d) ~= "table" then d = {} end
  d.ignore = d.ignore or {}
  d.want = d.want or {}
  NeedItDB.chars[key] = d
  return d
end

local function Opt(name)
  if NeedItDB[name] == nil then return true end
  return NeedItDB[name]
end

local generation = 0
local verdictCache = {}
local function Invalidate() generation = generation + 1 verdictCache = {} end

---------------------------------------------------------------------------
-- Spec detection
---------------------------------------------------------------------------
-- returns index, isModernSpecAPI, source ("manual" | "auto" | "default")
local function DetectSpec()
  local modern = GetSpecialization ~= nil
  local manual = CharData().spec
  if manual then return manual, modern, "manual" end
  if GetSpecialization then
    local ok, i = pcall(GetSpecialization)
    if ok and i then return i, true, "auto" end
  end
  if GetNumTalentTabs and GetTalentTabInfo then
    local best, bestPts = nil, 0
    for i = 1, GetNumTalentTabs() do
      local ok, _, _, pts = pcall(GetTalentTabInfo, i)
      if ok and type(pts) == "number" and pts > bestPts then best, bestPts = i, pts end
    end
    if best then return best, false, "auto" end
  end
  -- No talent points yet (under level 10): assume the usual leveling spec
  local def = DEFAULT_SPEC[PlayerClass()]
  if def then return def, modern, "default" end
end

local specCache
local function GetSpec()
  local class = PlayerClass()
  local idx, modern, source = DetectSpec()
  if not idx then return nil end
  local list = (class == "DRUID" and modern) and DRUID_MODERN or SPECS[class]
  local s = list and list[idx]
  if not s then return nil end
  local key = class .. idx .. source
  if specCache and specCache.key == key then return specCache.spec end
  local kind = KINDS[s[2]]
  local opts = s[3] or {}
  local w = {}
  for k, v in pairs(kind.w) do w[k] = v end
  if opts.w then for k, v in pairs(opts.w) do w[k] = v end end
  local spec = { name = s[1], kind = s[2], w = w, dpsW = kind.dpsW, rdps = kind.rdps,
                 dagger = opts.dagger, twoHand = opts.twoHand, source = source }
  specCache = { key = key, spec = spec }
  return spec
end

---------------------------------------------------------------------------
-- Reading an item (hidden scan tooltip: stat table + tooltip text lines)
---------------------------------------------------------------------------
local function ClassifyKey(k)
  k = k:upper()
  if k:find("STRENGTH") then return "STR" end
  if k:find("AGILITY") then return "AGI" end
  if k:find("INTELLECT") then return "INT" end
  if k:find("SPIRIT") then return "SPI" end
  if k:find("STAMINA") then return "STA" end
  if k:find("ATTACK_POWER") then return "AP" end
  if k:find("HEALING") then return "HEAL" end
  if k:find("SPELL_POWER") then return "SP" end
  if k:find("DAMAGE_DONE") then return "SPD" end
  if k:find("CRIT") then return "CRIT" end
  if k:find("HIT") then return "HIT" end
  if k:find("HASTE") then return "HASTE" end
  if k:find("POWER_REGEN") or k:find("MANA_REGEN") then return "MP5" end
  if k:find("DEFENSE") then return "DEF" end
  if k:find("DODGE") then return "DODGE" end
  if k:find("PARRY") then return "PARRY" end
  if k:find("BLOCK") then return "BLOCK" end
end

local PLUS_PHRASES = {
  { "strength", "STR" }, { "agility", "AGI" }, { "intellect", "INT" }, { "spirit", "SPI" },
  { "stamina", "STA" }, { "spell power", "SP" }, { "attack power", "AP" }, { "healing", "HEAL" },
  { "critical strike", "CRIT" }, { "crit", "CRIT" }, { "hit rating", "HIT" }, { "haste", "HASTE" },
  { "defense", "DEF" }, { "dodge", "DODGE" }, { "parry", "PARRY" }, { "block", "BLOCK" },
  { "mana per 5", "MP5" }, { "mp5", "MP5" },
}

local function Put(vals, stat, v)
  if stat and v and v > (vals[stat] or 0) then vals[stat] = v end
end

local function ParseLine(text, vals)
  local l = text:lower()
  local num, phrase = l:match("^%+(%d+)%s+(.+)$")
  if num then
    for _, p in ipairs(PLUS_PHRASES) do
      if phrase:find(p[1], 1, true) then Put(vals, p[2], tonumber(num)) break end
    end
    return
  end
  local isUse = l:find("^use:") or l:find("^chance on hit:")
  if not (isUse or l:find("^equip:")) then return end
  local proc = isUse or l:find("for %d+ sec") or l:find("when ") or l:find("each time")
                 or l:find("chance to ") and not (l:find("chance to get") or l:find("chance to hit")
                 or l:find("chance to dodge") or l:find("chance to parry") or l:find("chance to block"))
  local n = tonumber(l:match("(%d+%.?%d*)")) or 1
  local pct = l:find("%%") ~= nil
  local function val(stat)
    if proc then return EFFECT_VALUE end
    if pct and PCT_STATS[stat] then return n * PCT_MULT end
    return n
  end
  if l:find("attack power") then Put(vals, "AP", val("AP")) end
  if l:find("damage and healing") then Put(vals, "SP", val("SP"))
  elseif l:find("healing") then Put(vals, "HEAL", val("HEAL"))
  elseif l:find("spell damage") or l:find("damage done by") or l:find("spell power") then Put(vals, "SPD", val("SPD")) end
  if l:find("mana per 5") or l:find("mana every 5") or l:find("mp5") then Put(vals, "MP5", val("MP5")) end
  if l:find("critical strike") or l:find("crit") then Put(vals, "CRIT", val("CRIT")) end
  if l:find("chance to hit") or l:find("hit rating") or l:find("spell hit") then Put(vals, "HIT", val("HIT")) end
  if l:find("haste") then Put(vals, "HASTE", val("HASTE")) end
  if l:find("defense") then Put(vals, "DEF", val("DEF")) end
  if l:find("dodge") then Put(vals, "DODGE", val("DODGE")) end
  if l:find("parry") then Put(vals, "PARRY", val("PARRY")) end
  if l:find("block") then Put(vals, "BLOCK", val("BLOCK")) end
end

local scanTip
local parsedCache = {}

-- returns { vals = {STAT=value}, dps = number, classLine = string|nil } or nil if item data isn't loaded yet
local function ParseItem(link)
  if parsedCache[link] then return parsedCache[link] end
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "NeedItScanTip", UIParent, "GameTooltipTemplate")
  end
  scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  scanTip:ClearLines()
  local ok = pcall(scanTip.SetHyperlink, scanTip, link)
  if not ok then return nil end
  local n = scanTip:NumLines()
  if not n or n < 2 then return nil end

  local vals, dps, classLine = {}, 0, nil
  if GetStats then
    local okS, stats = pcall(GetStats, link)
    if okS and type(stats) == "table" then
      for k, v in pairs(stats) do
        local c = ClassifyKey(k)
        if c and type(v) == "number" then Put(vals, c, v) end
      end
    end
  end
  for i = 2, n do
    local fs = _G["NeedItScanTipTextLeft" .. i]
    local text = fs and fs:GetText()
    if type(text) == "string" then
      ParseLine(text, vals)
      local d = text:lower():match("([%d%.]+)%s+damage per second")
      if d then dps = tonumber(d) or dps end
      if text:find("^Classes:") then classLine = text:upper() end
    end
  end
  local parsed = { vals = vals, dps = dps, classLine = classLine }
  parsedCache[link] = parsed
  return parsed
end

---------------------------------------------------------------------------
-- Scoring
---------------------------------------------------------------------------
local function IsWeapon(classID) return classID == 2 end

-- returns score, goodList, wastedList
local function ScoreItem(parsed, spec, equipLoc, classID, subID)
  local score, good, wasted = 0, {}, {}
  for stat, v in pairs(parsed.vals) do
    local w = spec.w[stat] or 0
    if w > 0 then
      score = score + w * v
      good[#good + 1] = { stat = stat, v = v }
    else
      wasted[#wasted + 1] = stat
    end
  end
  table.sort(good, function(a, b) return a.v * (spec.w[a.stat] or 0) > b.v * (spec.w[b.stat] or 0) end)
  table.sort(wasted)
  if IsWeapon(classID) and parsed.dps > 0 then
    local dw = RANGED_SUB[subID] and spec.rdps or spec.dpsW
    score = score + parsed.dps * dw
  end
  return score, good, wasted
end

-- Weapon style preferences (dagger vs not, 1H vs 2H). Returns multiplier, note
local function WeaponPref(spec, equipLoc, classID, subID)
  if not IsWeapon(classID) then return 1 end
  local mainHand = equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND"
  if spec.dagger == "main" and mainHand then
    if subID == 15 then return 1.15, "dagger suits " .. spec.name end
    return 0.9, spec.name .. " prefers a dagger main hand"
  end
  if spec.dagger == "avoid" and mainHand then
    if subID == 15 then return 0.85, spec.name .. " prefers swords/maces over daggers" end
  end
  if spec.twoHand == "want" then
    if equipLoc == "INVTYPE_2HWEAPON" then return 1.15, "two-hander suits " .. spec.name end
    if mainHand then return 0.9, spec.name .. " prefers two-handers" end
  elseif spec.twoHand == "avoid" and equipLoc == "INVTYPE_2HWEAPON" then
    return 0.5, spec.name .. " uses one-hand + shield"
  end
  return 1
end

local function ItemScore(link, spec)
  local _, _, _, equipLoc, _, classID, subID = GetInstant(link)
  local parsed = ParseItem(link)
  if not parsed then return nil end
  local score = ScoreItem(parsed, spec, equipLoc, classID, subID)
  local mult = WeaponPref(spec, equipLoc, classID, subID)
  return score * mult
end

local function SlotScore(slot, spec)
  local l = GetInventoryItemLink("player", slot)
  if not l then return 0 end
  return ItemScore(l, spec) or 0
end

local function PlayerDualWields()
  if CanDualWield then
    local ok, can = pcall(CanDualWield)
    if ok and can ~= nil then return can and true or false end
  end
  return DUAL_WIELD[PlayerClass()] or false
end

-- Off hand counts as a weapon slot only if it's empty or holds a weapon (not a shield / held item)
local function OffHandIsWeaponSlot()
  local l = GetInventoryItemLink("player", 17)
  if not l then return true end
  local _, _, _, _, _, classID = GetInstant(l)
  return classID == 2
end

-- Score of what you currently wear in the slot(s) this item would replace (worst slot wins)
local function EquippedScore(equipLoc, spec)
  local slots = SLOTS[equipLoc]
  if not slots then return nil end
  -- A two-hander replaces main hand AND off hand
  if equipLoc == "INVTYPE_2HWEAPON" then return SlotScore(16, spec) + SlotScore(17, spec) end
  -- A one-hander only competes for the off hand if you can dual wield and aren't using a shield/held item
  if equipLoc == "INVTYPE_WEAPON" and not (PlayerDualWields() and OffHandIsWeaponSlot()) then
    slots = { 16 }
  end
  local lowest
  for _, s in ipairs(slots) do
    local sc = SlotScore(s, spec)
    if not lowest or sc < lowest then lowest = sc end
  end
  return lowest
end

local function ItemID(link) return tonumber(link and link:match("item:(%d+)")) end

local function FormatGood(good, n)
  local out = {}
  for i = 1, math.min(n or 4, #good) do
    local g = good[i]
    out[#out + 1] = "+" .. math.floor(g.v + 0.5) .. " " .. NAMES[g.stat]
  end
  return table.concat(out, ", ")
end

local function FormatWasted(wasted)
  local out = {}
  for i, s in ipairs(wasted) do out[i] = NAMES[s] end
  return table.concat(out, ", ")
end

---------------------------------------------------------------------------
-- Verdict: returns verdict ("NEED"/"GREED"/"PASS"), headline, detail (may be nil)
---------------------------------------------------------------------------
local function Evaluate(link)
  local class = PlayerClass()
  if not class or not link then return end
  local _, _, _, equipLoc, _, classID, subID = GetInstant(link)
  if not equipLoc or not SLOTS[equipLoc] then return end

  local id = ItemID(link)
  local cd = CharData()
  if id and cd.ignore[id] then return "PASS", "You marked this item as ignored" end
  if id and cd.want[id] then return "NEED", "You marked this item as wanted" end

  -- 1. Can the class physically equip it?
  local isBodyArmor = classID == 4 and BODY_SLOTS[equipLoc] and subID
  if isBodyArmor and subID > (ARMOR[class] or 1) then
    return "PASS", "Your class can't wear this armor type"
  end
  local maxArmor = MaxArmor(class)
  if isBodyArmor and subID > maxArmor then
    return "GREED", "You can't wear " .. ARMOR_NAMES[subID] .. " until level " .. ARMOR_LEVEL
  end
  if classID == 4 and subID == 6 and not SHIELD[class] then return "PASS", "Your class can't use shields" end
  if classID == 2 and WEAPONS[class] and subID and not WEAPONS[class][subID] then
    return "PASS", "Your class can't use this weapon type"
  end

  local parsed = ParseItem(link)
  if not parsed then return nil end
  if parsed.classLine and not parsed.classLine:find(UnitClass("player"):upper(), 1, true) then
    return "PASS", "Restricted to other classes"
  end

  local spec = GetSpec()
  if not spec then return "GREED", "Couldn't detect your spec", "Use /needit spec <number> to set it" end

  local lowerArmor = isBodyArmor and subID > 0 and subID < maxArmor

  local score, good, wasted = ScoreItem(parsed, spec, equipLoc, classID, subID)
  local mult, note = WeaponPref(spec, equipLoc, classID, subID)
  score = score * mult

  local detail = {}
  if #good > 0 then detail[#detail + 1] = "Good: " .. FormatGood(good) end
  if #wasted > 0 then detail[#detail + 1] = "Wasted: " .. FormatWasted(wasted) end
  if note then detail[#detail + 1] = note end
  if equipLoc == "INVTYPE_TRINKET" then detail[#detail + 1] = "Trinket - read the effect too" end
  if spec.source == "default" then detail[#detail + 1] = "No talents yet - assuming " .. spec.name end
  local detailText = #detail > 0 and table.concat(detail, "  |  ") or nil

  if score <= 0 then
    if #wasted > 0 then return "PASS", "Wrong stats for " .. spec.name, detailText end
    return "GREED", "No clear stats for " .. spec.name .. " - check the effect", detailText
  end

  local eq = EquippedScore(equipLoc, spec) or 0
  local upgrade = score > eq * 1.02
  local gainText
  if eq > 0 then
    local pct = math.floor((score / eq - 1) * 100 + 0.5)
    gainText = (pct >= 0 and "+" or "") .. pct .. "% vs equipped"
  else
    gainText = "empty slot"
  end

  if lowerArmor and upgrade then return "GREED", "Better stats, but lower armor type (" .. gainText .. ")", detailText end
  if lowerArmor then return "GREED", "Lower armor type than you can wear", detailText end
  if upgrade then return "NEED", "Upgrade for " .. spec.name .. " (" .. gainText .. ")", detailText end
  return "GREED", "Fits " .. spec.name .. " but not an upgrade (" .. gainText .. ")", detailText
end

-- Cached verdict for bag / vendor / roll markers
local function CachedVerdict(link)
  local hit = verdictCache[link]
  if hit then return hit[1], hit[2] end
  local ok, verdict, headline = pcall(Evaluate, link)
  if ok and verdict then
    verdictCache[link] = { verdict, headline }
    return verdict, headline
  end
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
local function Annotate(tt, link)
  if not tt or not link or tt.__needit == link then return end
  if tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local ok, verdict, headline, detail = pcall(Evaluate, link)
  if not ok or not verdict then return end
  tt.__needit = link
  tt:AddLine(" ")
  tt:AddLine(COLORS[verdict] .. "NeedIt: " .. verdict .. "|r  " .. COLORS.GRAY .. (headline or "") .. "|r", 1, 1, 1, true)
  if detail then tt:AddLine(COLORS.GRAY .. detail .. "|r", 1, 1, 1, true) end
  tt:Show()
end

local function SetupTooltips()
  local tips = { GameTooltip, ItemRefTooltip }
  for _, t in ipairs(tips) do
    if t and t.HookScript then pcall(t.HookScript, t, "OnTooltipCleared", function(self) self.__needit = nil end) end
  end
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      local link = data and (data.hyperlink or (data.id and ("item:" .. data.id)))
      Annotate(tt, link)
    end)
  else
    for _, t in ipairs(tips) do
      if t and t.HookScript then
        t:HookScript("OnTooltipSetItem", function(self)
          local _, link = self:GetItem()
          Annotate(self, link)
        end)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Markers on bag + vendor items, verdict on group-loot rolls
---------------------------------------------------------------------------
local MARK = { NEED = { 0.2, 1, 0.2 }, PASS = { 1, 0.25, 0.25 } }

local function SetMark(btn, verdict)
  local m = btn.needitMark
  if not verdict or not MARK[verdict] then
    if m then m:Hide() end
    return
  end
  if not m then
    m = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    m:SetSize(9, 9)
    m:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 3, 3)
    btn.needitMark = m
  end
  local c = MARK[verdict]
  if m.SetColorTexture then m:SetColorTexture(c[1], c[2], c[3], 1) else m:SetTexture(c[1], c[2], c[3], 1) end
  m:Show()
end

local function EachBagButton(fn)
  local function try(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return end
    if frame.EnumerateValidItems then
      for _, b in frame:EnumerateValidItems() do
        fn(b, (b.GetBagID and b:GetBagID()) or frame:GetID(), b:GetID())
      end
    else
      local name = frame:GetName()
      local n = frame.size or 0
      for j = 1, n do
        local b = _G[name .. "Item" .. j]
        if b then fn(b, frame:GetID(), b:GetID()) end
      end
    end
  end
  for i = 1, 13 do try(_G["ContainerFrame" .. i]) end
  try(_G.ContainerFrameCombinedBags)
end

local function RefreshBags()
  EachBagButton(function(btn, bag, slot)
    local link = GetBagLink(bag, slot)
    local verdict
    if link then verdict = CachedVerdict(link) end
    SetMark(btn, verdict)
  end)
end

local function RefreshMerchant()
  if not (MerchantFrame and MerchantFrame:IsShown() and GetMerchantItemLink) then return end
  local per = MERCHANT_ITEMS_PER_PAGE or 10
  for i = 1, per do
    local btn = _G["MerchantItem" .. i .. "ItemButton"]
    if btn then
      local verdict
      if btn:IsVisible() then
        local idx = ((MerchantFrame.page or 1) - 1) * per + i
        local link = GetMerchantItemLink(idx)
        if link then verdict = CachedVerdict(link) end
      end
      SetMark(btn, verdict)
    end
  end
end

local ROLL_TEXT = { NEED = "Roll NEED", GREED = "Roll GREED", PASS = "PASS" }

local function RefreshRolls()
  if not GetLootRollItemLink then return end
  for i = 1, 4 do
    local f = _G["GroupLootFrame" .. i]
    if f then
      local fs = f.needitText
      if f:IsShown() and f.rollID then
        local link = GetLootRollItemLink(f.rollID)
        local verdict, headline
        if link then verdict, headline = CachedVerdict(link) end
        if verdict then
          if not fs then
            fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("BOTTOM", f, "TOP", 0, 2)
            f.needitText = fs
          end
          fs:SetText(COLORS[verdict] .. "NeedIt: " .. ROLL_TEXT[verdict] .. "|r " .. COLORS.GRAY .. (headline or "") .. "|r")
          fs:Show()
        elseif fs then
          fs:Hide()
        end
      elseif fs then
        fs:Hide()
      end
    end
  end
end

local function RefreshAll()
  if Opt("bags") then pcall(RefreshBags) end
  if Opt("vendor") then pcall(RefreshMerchant) end
  if Opt("rolls") then pcall(RefreshRolls) end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Say(msg) print("|cff33ccffNeedIt:|r " .. msg) end

local function Status()
  local spec = GetSpec()
  local SOURCE = { manual = " (manual)", auto = " (auto)", default = " (no talents yet - leveling default)" }
  Say("Class " .. tostring(PlayerClass()) .. ", spec " .. (spec and spec.name or "unknown")
      .. (spec and SOURCE[spec.source] or ""))
end

local function Help()
  Say("/needit - show detected class and spec")
  Say("/needit spec <number>  |  /needit spec auto - set or reset your spec")
  Say("/needit ignore [item link]  |  /needit unignore [item link] - always PASS an item")
  Say("/needit want [item link]  |  /needit unwant [item link] - always NEED an item")
  Say("/needit bags|vendor|rolls - turn markers on/off")
  Say("Bag markers: green = NEED, red = PASS.")
end

local function ToggleOpt(name)
  NeedItDB[name] = not Opt(name)
  Say(name .. " markers " .. (NeedItDB[name] and "on" or "off"))
  if not NeedItDB[name] then
    -- hide leftover markers
    EachBagButton(function(btn) SetMark(btn, nil) end)
  end
end

SLASH_NEEDIT1 = "/needit"
SlashCmdList["NEEDIT"] = function(msg)
  msg = msg or ""
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = cmd:lower()
  local cd = CharData()
  if cmd == "spec" then
    cd.spec = tonumber(rest)
    specCache = nil
    Invalidate()
    Status()
  elseif cmd == "ignore" or cmd == "unignore" or cmd == "want" or cmd == "unwant" then
    local id = ItemID(rest)
    if not id then Say("Shift-click an item after the command to add its link.") return end
    local list = (cmd == "ignore" or cmd == "unignore") and cd.ignore or cd.want
    local on = (cmd == "ignore" or cmd == "want")
    if on then
      list[id] = true
      if list == cd.ignore then cd.want[id] = nil else cd.ignore[id] = nil end
    else
      list[id] = nil
    end
    Invalidate()
    Say(rest .. " - " .. cmd .. " saved.")
  elseif cmd == "bags" or cmd == "vendor" or cmd == "rolls" then
    ToggleOpt(cmd)
  elseif cmd == "help" or cmd == "?" then
    Help()
  else
    Status()
    Say("Type /needit help for all commands.")
  end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
f:RegisterEvent("CHARACTER_POINTS_CHANGED")
f:RegisterEvent("PLAYER_LEVEL_UP")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    NeedItDB = NeedItDB or {}
    SetupTooltips()
    Say("loaded. Hover gear to see NEED / GREED / PASS. Type /needit help.")
  else
    specCache = nil
    Invalidate()
  end
end)

local elapsed = 0
f:SetScript("OnUpdate", function(_, dt)
  elapsed = elapsed + dt
  if elapsed < 0.5 then return end
  elapsed = 0
  RefreshAll()
end)
