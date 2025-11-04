-- GuildNotes_UI_Editor.lua
-- Editor modal (add/edit, delete)

local ADDON_NAME, ns = ...
local UI = ns.UI

function UI:OpenEditor(key)
  if not self.frame then self:Init() end
  if self.blocker then self.blocker:Show() end
  self.editor:Show()
  self.currentKey = key
  self:RecomputePermissions()
  if key then
    self.saveBtn:SetText("Save")
    self.deleteBtn:SetShown(self.canEdit)
    local e = GuildNotes:GetEntry(key) or {}
    self.nameBox:SetText(e.name or (key:match("^[^-]+") or ""))
    self.guildBox:SetText(e.guild or "")
    self.selectedClass, self.selectedRace = e.class, e.race
    if self.classDrop then
      local cText = ns.CellWithIcon(ns.ClassIcon(e.class), ns.ClassPretty(e.class or ""))
      UIDropDownMenu_SetText(self.classDrop, cText or "")
    end
    if self.raceDrop then
      local rText = ns.CellWithIcon(ns.RaceIcon(e.race),  ns.RacePretty(e.race or ""))
      UIDropDownMenu_SetText(self.raceDrop, rText or "")
    end
    if self.setStatus then self.setStatus(ns:GetStatus(e)) end
    self.noteBox:SetText(e.note or "")
  else
    self.saveBtn:SetText("Add")
    self.deleteBtn:Hide()
    self.nameBox:SetText(""); self.guildBox:SetText("")
    self.noteBox:SetText(""); self.selectedClass=nil; self.selectedRace=nil
    if self.classDrop then UIDropDownMenu_SetText(self.classDrop, "") end
    if self.raceDrop  then UIDropDownMenu_SetText(self.raceDrop,  "") end
    if self.setStatus then self.setStatus("S") end
  end
end
