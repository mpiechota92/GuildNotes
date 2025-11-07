-- Menu.lua (Classic + Retail safe)
local ADDON_NAME, ns = ...

local function PrefillEditor(name, classToken, raceToken, guildName)
  if not GuildNotesUI then return end
  GuildNotesUI:Toggle()
  GuildNotesUI:OpenEditor(nil)
  if GuildNotesUI.nameBox then GuildNotesUI.nameBox:SetText(name or "") end
  if GuildNotesUI.guildBox then GuildNotesUI.guildBox:SetText(guildName or "") end
  if classToken and GuildNotesUI.classDrop then
    GuildNotesUI.selectedClass = classToken
    local icon = "Interface/ICONS/ClassIcon_"..classToken:sub(1,1)..classToken:sub(2):lower()
    UIDropDownMenu_SetText(GuildNotesUI.classDrop, (icon and ("|T"..icon..":16|t ") or "")..(classToken or ""))
  end
  if raceToken and GuildNotesUI.raceDrop then
    GuildNotesUI.selectedRace = raceToken
    UIDropDownMenu_SetText(GuildNotesUI.raceDrop, raceToken or "")
  end
end

-- Retail API (if available)
if Menu and Menu.ModifyMenu then
  local TAGS = {
    "MENU_UNIT_ENEMY_PLAYER","MENU_UNIT_FRIEND","MENU_UNIT_PARTY",
    "MENU_UNIT_PLAYER","MENU_UNIT_RAID_PLAYER","MENU_CHAT_PLAYER","MENU_FRIEND",
  }
  local function AddRetailItem(owner, parent, data)
    parent:CreateDivider()
    parent:CreateButton("Add note", function()
      local n = (data and data.name) or (data and data.unit and UnitName(data.unit))
      if type(n) == "string" then n = n:gsub("%-.*$","") end
      if n then PrefillEditor(n) end
    end)
  end
  for _, tag in ipairs(TAGS) do Menu.ModifyMenu(tag, AddRetailItem) end
end

-- Classic hook (only if the function exists)
if type(_G.UnitPopup_ShowMenu) == "function" and hooksecurefunc then
  local SUPPORTED = {
    PLAYER=true, PARTY=true, RAID_PLAYER=true, FRIEND=true,
    TARGET=true, CHAT_ROSTER=true, BN_FRIEND=true
  }
  local function AddClassicItem(dropdownMenu, which, unit, name)
    if not SUPPORTED[which] then return end
    local targetName = dropdownMenu and dropdownMenu.name or name
    if (not targetName or targetName=="") and unit and UnitExists(unit) then
      targetName = Ambiguate(UnitName(unit), "none")
    end
    if not targetName or targetName=="" then return end
    local info = UIDropDownMenu_CreateInfo()
    info.text = "|TInterface/ICONS/INV_Scroll_03:16|t Add note"
    info.notCheckable = true
    info.func = function() PrefillEditor((targetName or ""):gsub("%-.*$","")) end
    UIDropDownMenu_AddButton(info, UIDROPDOWNMENU_MENU_LEVEL or 1)
  end
  hooksecurefunc("UnitPopup_ShowMenu", AddClassicItem)
end
