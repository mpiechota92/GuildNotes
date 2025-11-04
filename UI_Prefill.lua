-- UI_Prefill.lua
local ADDON_NAME, ns = ...

GuildNotesUI = GuildNotesUI or {}

if not GuildNotesUI.OpenEditorPrefilled then
  function GuildNotesUI:OpenEditorPrefilled(name, classToken, raceToken, guildName)
    if self.Toggle then self:Toggle() end
    if self.OpenEditor then self:OpenEditor(nil) end
    if self.nameBox and name then self.nameBox:SetText(name) end
    if self.guildBox then self.guildBox:SetText(guildName or "") end
    if classToken and self.classDrop then
      self.selectedClass = classToken
      local icon = classToken and "Interface/ICONS/ClassIcon_"..classToken:sub(1,1)..classToken:sub(2):lower()
      local label = classToken
      if icon then UIDropDownMenu_SetText(self.classDrop, (icon and ("|T"..icon..":16|t ") or "")..(label or "")) end
    end
    if raceToken and self.raceDrop then
      self.selectedRace = raceToken
      UIDropDownMenu_SetText(self.raceDrop, raceToken or "")
    end
    if self.nameBox and self.nameBox.SetFocus then self.nameBox:SetFocus() end
  end
end
