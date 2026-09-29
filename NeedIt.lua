-- NeedIt: tooltip verdict (NEED / GREED / PASS) for gear based on class + spec.
NeedItDB = NeedItDB or {}

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetStats = (C_Item and C_Item.GetItemStats) or GetItemStats

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local function set(...) local t = {} for _, v in ipairs({...}) do t[v] = true end return t end

-- Stat "kinds": which stats each role wants (good) and wastes (bad).
local KINDS = {
  MELEE_STR  = { good = set("STR","AP","CRIT","HIT","HASTE","AGI"), bad = set("INT","SPI","SP","HEAL","MP5","DEF","DODGE","PARRY","BLOCK") },
  MELEE_AGI  = { good = set("AGI","STR","AP","CRIT","HIT","HASTE"), bad = set("INT","SPI","SP","HEAL","MP5","DEF","PARRY","BLOCK") },
  RANGED_AGI = { good = set("AGI","AP","CRIT","HIT","HASTE","INT","MP5"), bad = set("SPI","SP","HEAL","DEF","PARRY","BLOCK","DODGE") },
  TANK_STR   = { good = set("STR","STA","DEF","DODGE","PARRY","BLOCK","AGI","HIT"), bad = set("INT","SPI","SP","HEAL","MP5") },
  FERAL      = { good = set("STR","AGI","AP","STA","CRIT","HIT","HASTE","DODGE","DEF"), bad = set("SPI","SP","HEAL","PARRY","BLOCK") },
  CASTER     = { good = set("INT","SP","CRIT","HIT","HASTE","MP5","SPI"), bad = set("STR","AGI","AP","DEF","DODGE","PARRY","BLOCK","HEAL") },
  HEALER     = { good = set("INT","SPI","HEAL","SP","MP5","CRIT","HASTE"), bad = set("STR","AGI","AP","DEF","DODGE","PARRY","BLOCK","HIT") },
}

-- Indexed by spec / talent-tree order
local SPECS = {
  WARRIOR = { {"Arms","MELEE_STR"}, {"Fury","MELEE_STR"}, {"Protection","TANK_STR"} },
  PALADIN = { {"Holy","HEALER"}, {"Protection","TANK_STR"}, {"Retribution","MELEE_STR"} },
  HUNTER  = { {"Beast Mastery","RANGED_AGI"}, {"Marksmanship","RANGED_AGI"}, {"Survival","RANGED_AGI"} },
  ROGUE   = { {"Assassination","MELEE_AGI"}, {"Combat","MELEE_AGI"}, {"Subtlety","MELEE_AGI"} },
  PRIEST  = { {"Discipline","HEALER"}, {"Holy","HEALER"}, {"Shadow","CASTER"} },
  SHAMAN  = { {"Elemental","CASTER"}, {"Enhancement","MELEE_AGI"}, {"Restoration","HEALER"} },
  MAGE    = { {"Arcane","CASTER"}, {"Fire","CASTER"}, {"Frost","CASTER"} },
  WARLOCK = { {"Affliction","CASTER"}, {"Demonology","CASTER"}, {"Destruction","CASTER"} },
  DRUID   = { {"Balance","CASTER"}, {"Feral","FERAL"}, {"Restoration","HEALER"} },
}
local DRUID_MODERN = { {"Balance","CASTER"}, {"Feral","FERAL"}, {"Guardian","FERAL"}, {"Restoration","HEALER"} }

-- Highest armor type a class can wear (subclass ids: 1 cloth, 2 leather, 3 mail, 4 plate)
local ARMOR = { WARRIOR=4, PALADIN=4, HUNTER=3, SHAMAN=3, ROGUE=2, DRUID=2, PRIEST=1, MAGE=1, WARLOCK=1 }
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

local SLOTS = {
  INVTYPE_HEAD={1}, INVTYPE_NECK={2}, INVTYPE_SHOULDER={3}, INVTYPE_CHEST={5}, INVTYPE_ROBE={5},
  INVTYPE_WAIST={6}, INVTYPE_LEGS={7}, INVTYPE_FEET={8}, INVTYPE_WRIST={9}, INVTYPE_HAND={10},
  INVTYPE_FINGER={11,12}, INVTYPE_TRINKET={13,14}, INVTYPE_CLOAK={15},
  INVTYPE_WEAPON={16,17}, INVTYPE_2HWEAPON={16}, INVTYPE_WEAPONMAINHAND={16},
  INVTYPE_WEAPONOFFHAND={17}, INVTYPE_SHIELD={17}, INVTYPE_HOLDABLE={17},
  INVTYPE_RANGED={18}, INVTYPE_RANGEDRIGHT={18}, INVTYPE_THROWN={18}, INVTYPE_RELIC={18},
}

---------------------------------------------------------------------------
-- Player class / spec
---------------------------------------------------------------------------
local function PlayerClass() local _, token = UnitClass("player") return token end

-- manual spec overrides are stored per character (name-realm), not account-wide
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function GetOverride() return NeedItDB.chars and NeedItDB.chars[CharKey()] end
local function SetOverride(n)
  NeedItDB.chars = NeedItDB.chars or {}
  NeedItDB.chars[CharKey()] = n
end

-- returns index, isModernSpecAPI
local function DetectSpec()
  local manual = GetOverride()
  if manual then return manual, (GetSpecialization ~= nil) end
  if GetSpecialization then
    local ok, i = pcall(GetSpecialization)
    if ok and i then return i, true end
  end
  if GetNumTalentTabs and GetTalentTabInfo then
    local best, bestPts = nil, 0
    for i = 1, GetNumTalentTabs() do
      local ok, _, _, pts = pcall(GetTalentTabInfo, i)
      if ok and type(pts) == "number" and pts > bestPts then best, bestPts = i, pts end
    end
    if best then return best, false end
  end
end

local function GetSpec()
  local class = PlayerClass()
  local idx, modern = DetectSpec()
  if not idx then return nil end
  local list = (class == "DRUID" and modern) and DRUID_MODERN or SPECS[class]
  local s = list and list[idx]
  if s then return s[1], KINDS[s[2]] end
end

---------------------------------------------------------------------------
-- Reading an item's stats (stat table + "Equip:" text lines)
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
  if k:find("SPELL_POWER") or k:find("DAMAGE_DONE") then return "SP" end
  if k:find("CRIT") then return "CRIT" end
  if k:find("HIT") then return "HIT" end
  if k:find("HASTE") then return "HASTE" end
  if k:find("POWER_REGEN") or k:find("MANA_REGEN") then return "MP5" end
  if k:find("DEFENSE") then return "DEF" end
  if k:find("DODGE") then return "DODGE" end
  if k:find("PARRY") then return "PARRY" end
  if k:find("BLOCK") then return "BLOCK" end
end

local PLUS_STATS = { strength="STR", agility="AGI", intellect="INT", spirit="SPI", stamina="STA" }

local function ClassifyText(line, found)
  local l = line:lower()
  local plus = l:match("^%+%d+%s+(%a+)")
  if plus and PLUS_STATS[plus] then found[PLUS_STATS[plus]] = true end
  if not (l:find("^equip:") or l:find("^use:") or l:find("^chance on hit:")) then return end
  if l:find("attack power") then found.AP = true end
  if l:find("damage and healing") then found.SP = true found.HEAL = true
  elseif l:find("healing") then found.HEAL = true
  elseif l:find("spell damage") or l:find("spell power") or l:find("damage done by") or l:find("magical spells") then found.SP = true end
  if l:find("mana per 5") or l:find("mana every 5") or l:find("mp5") then found.MP5 = true end
  if l:find("critical strike") or l:find("crit") then found.CRIT = true end
  if l:find("chance to hit") or l:find("hit rating") or l:find("spell hit") then found.HIT = true end
  if l:find("haste") then found.HASTE = true end
  if l:find("defense") then found.DEF = true end
  if l:find("dodge") then found.DODGE = true end
  if l:find("parry") then found.PARRY = true end
  if l:find("block") then found.BLOCK = true end
end

local function ReadStats(tt, link)
  local found = {}
  if GetStats and link then
    local ok, stats = pcall(GetStats, link)
    if ok and type(stats) == "table" then
      for k in pairs(stats) do local c = ClassifyKey(k) if c then found[c] = true end end
    end
  end
  local name = tt:GetName()
  local classLine
  if name then
    for i = 2, tt:NumLines() do
      local fs = _G[name .. "TextLeft" .. i]
      local text = fs and fs:GetText()
      if type(text) == "string" then
        ClassifyText(text, found)
        if text:find("^Classes:") then classLine = text:upper() end
      end
    end
  end
  return found, classLine
end

---------------------------------------------------------------------------
-- Verdict
---------------------------------------------------------------------------
local function EquippedILvl(equipLoc)
  local slots = SLOTS[equipLoc]
  if not slots then return nil end
  local lowest
  for _, s in ipairs(slots) do
    local l = GetInventoryItemLink("player", s)
    local lvl = 0
    if l then lvl = select(4, GetInfo(l)) or 0 end
    if not lowest or lvl < lowest then lowest = lvl end
  end
  return lowest
end

local COLORS = { NEED="|cff33ff33", GREED="|cffffd100", PASS="|cffff4040", GRAY="|cffaaaaaa" }

local function Evaluate(tt, link)
  local class = PlayerClass()
  if not class or not link then return end
  local _, _, _, equipLoc, _, classID, subID = GetInstant(link)
  if not equipLoc or equipLoc == "" or equipLoc == "INVTYPE_BAG" or equipLoc == "INVTYPE_AMMO"
     or equipLoc == "INVTYPE_QUIVER" or equipLoc == "INVTYPE_TABARD" or equipLoc == "INVTYPE_BODY" then return end

  -- 1. Can the class physically equip it?
  if classID == 4 and BODY_SLOTS[equipLoc] and subID and subID > (ARMOR[class] or 1) then
    return "PASS", "Your class can't wear this armor type"
  end
  if classID == 4 and subID == 6 and not SHIELD[class] then return "PASS", "Your class can't use shields" end
  if classID == 2 and WEAPONS[class] and subID and not WEAPONS[class][subID] then
    return "PASS", "Your class can't use this weapon type"
  end

  local found, classLine = ReadStats(tt, link)
  if classLine and not classLine:find(UnitClass("player"):upper(), 1, true) then
    return "PASS", "Restricted to other classes"
  end

  -- 2. Armor type below the best the class could wear
  local lowerArmor = classID == 4 and BODY_SLOTS[equipLoc] and subID and subID > 0 and subID < (ARMOR[class] or 1)

  -- 3. Spec stat fit
  local specName, kind = GetSpec()
  if not kind then return "GREED", "Couldn't detect spec - use /needit spec 1-3" end
  local good, bad = 0, 0
  for stat in pairs(found) do
    if kind.good[stat] then good = good + 1 end
    if kind.bad[stat] then bad = bad + 1 end
  end

  local ilvl = select(4, GetInfo(link)) or 0
  local eq = EquippedILvl(equipLoc)
  local upgrade = eq and ilvl > eq
  local gain = eq and (ilvl - eq) or 0

  if good == 0 and bad > 0 then return "PASS", "Wrong stats for " .. specName end
  if lowerArmor then return "GREED", "Lower armor type than you can wear" end
  if good > 0 and bad == 0 then
    if upgrade then
      return "NEED", "Great for " .. specName .. (eq == 0 and " (empty slot)" or (" (+" .. gain .. " ilvl)"))
    end
    return "GREED", "Fits " .. specName .. " but not an upgrade"
  end
  if good > 0 and bad > 0 then return "GREED", "Mixed stats for " .. specName end
  return "GREED", "No clear stats for " .. specName .. " - check the effect"
end

---------------------------------------------------------------------------
-- Tooltip hooking
---------------------------------------------------------------------------
local function Annotate(tt, link)
  if not tt or not link or tt.__needit == link then return end
  if tt == ShoppingTooltip1 or tt == ShoppingTooltip2 then return end
  local ok, verdict, why = pcall(Evaluate, tt, link)
  if not ok or not verdict then return end
  tt.__needit = link
  tt:AddLine(" ")
  tt:AddLine(COLORS[verdict] .. "NeedIt: " .. verdict .. "|r  " .. COLORS.GRAY .. (why or "") .. "|r", 1, 1, 1, true)
  tt:Show()
end

local function Setup()
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
-- Slash command + startup
---------------------------------------------------------------------------
local function Say(msg) print("|cff33ccffNeedIt:|r " .. msg) end

SLASH_NEEDIT1 = "/needit"
SlashCmdList["NEEDIT"] = function(msg)
  local cmd, arg = (msg or ""):match("^(%S*)%s*(%S*)")
  cmd = cmd:lower()
  if cmd == "spec" then
    local n = tonumber(arg)
    SetOverride(n)
  end
  local name = GetSpec()
  Say("Class " .. tostring(PlayerClass()) .. ", spec " .. tostring(name or "unknown")
      .. (GetOverride() and " (manual)" or " (auto)"))
  Say("Override: /needit spec <number>   Reset: /needit spec auto")
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
  NeedItDB = NeedItDB or {}
  Setup()
  Say("loaded. Hover gear to see NEED / GREED / PASS. Type /needit for info.")
end)
