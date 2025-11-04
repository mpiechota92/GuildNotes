-- Context.lua (safe for Retail & Classic)
local ADDON_NAME, ns = ...

-- Helpers
local function SanitizeFull(full)
  if not full then return nil end
  full = full:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%-$","")
  if full == "" then return nil end
  return full
end
local function NormalizeRaceToken(r)
  if not r then return nil end
  return (r=="Night Elf" or r=="NightElf" or r=="Nightelf") and "NightElf" or r
end
local function ResolveFromUnit(unit)
  if unit and UnitExists(unit) then
    local name, realm = UnitName(unit)
    local full = SanitizeFull(realm and (name.."-"..realm) or name)
    local class = select(2, UnitClass(unit))
    local race  = NormalizeRaceToken(select(2, UnitRace(unit)))
    local guild = GetGuildInfo(unit)
    return full, class, race, guild
  end
  return nil
end
local function ResolveFromGUID(guid)
  if not guid then return nil end
  local _, class, _, race, _, name, realm = GetPlayerInfoByGUID(guid)
  local full = SanitizeFull(name and (realm and (name.."-"..realm) or name) or nil)
  return full, class, NormalizeRaceToken(race), nil
end
local function OpenEditorPrefilled(full, class, race, guild)
  if not GuildNotesUI then return end
  full = SanitizeFull(full); if not full then return end
  if GuildNotesUI.OpenEditorPrefilled then
    GuildNotesUI:OpenEditorPrefilled(full, class, race, guild); return
  end
  if GuildNotesUI.Toggle then GuildNotesUI:Toggle() end
  if GuildNotesUI.OpenEditor then GuildNotesUI:OpenEditor(nil) end
  if GuildNotesUI.nameBox then GuildNotesUI.nameBox:SetText(full) end
  if GuildNotesUI.guildBox then GuildNotesUI.guildBox:SetText(guild or "") end
end

-- Retail Menu API (if present)
do
  if Menu and Menu.ModifyMenu then
    local function AddMenuItem(owner, parent, data)
      parent:CreateDivider()
      parent:CreateButton("Add note", function()
        local full, class, race, guild
        if data and data.playerLocation and C_PlayerInfo and C_PlayerInfo.GetGUIDFromPlayerLocation then
          local guid = C_PlayerInfo.GetGUIDFromPlayerLocation(data.playerLocation)
          if guid then full, class, race, guild = ResolveFromGUID(guid) end
        end
        if (not full) and owner and owner.unit then full, class, race, guild = ResolveFromUnit(owner.unit) end
        if (not full) and data and data.name then full = SanitizeFull(data.name) end
        if full then OpenEditorPrefilled(full, class, race, guild) end
      end)
    end
    local TAGS = {
      "MENU_UNIT_ENEMY_PLAYER", "MENU_UNIT_FRIEND", "MENU_UNIT_PARTY",
      "MENU_UNIT_PLAYER", "MENU_UNIT_RAID_PLAYER", "MENU_CHAT_PLAYER", "MENU_FRIEND",
    }
    for _, tag in ipairs(TAGS) do Menu.ModifyMenu(tag, AddMenuItem) end
  end
end

-- Classic dropdown API (only if present)
do
  if type(_G.UnitPopup_ShowMenu) == "function" and hooksecurefunc then
    local SUPPORTED = {
      PLAYER=true, PARTY=true, RAID_PLAYER=true, FRIEND=true,
      TARGET=true, CHAT_ROSTER=true, BN_FRIEND=true
    }
    local function prefill(name)
      if not GuildNotesUI then return end
      GuildNotesUI:Toggle()
      GuildNotesUI:OpenEditor(nil)
      if GuildNotesUI.nameBox then GuildNotesUI.nameBox:SetText(name or "") end
    end
    hooksecurefunc("UnitPopup_ShowMenu", function(dropdownMenu, which, unit, name)
      if not SUPPORTED[which] then return end
      local targetName = dropdownMenu and dropdownMenu.name or name
      if (not targetName or targetName=="") and unit and UnitExists(unit) then
        targetName = Ambiguate(UnitName(unit), "none")
      end
      if not targetName or targetName=="" then return end
      local info = UIDropDownMenu_CreateInfo()
      info.text = "|TInterface/ICONS/INV_Scroll_03:16|t Add note"
      info.notCheckable = true
      info.func = function() prefill((targetName or ""):gsub("%-.*$","")) end
      UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL or 1)
    end)
  end
end
