-- GuildNotes_UI_Editor.lua
-- Simple modal editor (add/edit/delete). Safe to call even if editor is not created yet.

local ADDON_NAME, ns = ...
local UI = ns.UI

-- build the modal lazily
function UI:EnsureEditor()
  if self.editor then return end
  if not self.frame then self:Init() end

  -- Screen blocker
  local blocker = CreateFrame("Button", ADDON_NAME.."EditorBlocker", self.frame, "BackdropTemplate")
  blocker:SetAllPoints(self.frame)
  blocker:SetFrameLevel(self.frame:GetFrameLevel() + 5)
  blocker:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
  blocker:EnableMouse(true)
  if blocker.SetBackdropColor then blocker:SetBackdropColor(0,0,0,0.7) end
  blocker:SetBackdropColor(0, 0, 0, 0.40)
  blocker:Hide()
  blocker:SetScript("OnClick", function() end) -- swallow clicks
  self.blocker = blocker

  -- Modal frame
  local ed = CreateFrame("Frame", ADDON_NAME.."Editor", blocker, "BackdropTemplate")

-- Confirmation dialogs
if not StaticPopupDialogs["GNOTES_CONFIRM_SAVE"] then
  StaticPopupDialogs["GNOTES_CONFIRM_SAVE"] = {
    text = "Save changes to this note?",
    button1 = YES, button2 = NO,
    OnAccept = function()
      local UI = ns.UI
      local name = UI.nameBox and UI.nameBox:GetText() or ""
      if name == "" then return end
      local data = {
        name  = name,
        guild = UI.guildBox and UI.guildBox:GetText() or "",
        class = UI.selectedClass,
        race  = UI.selectedRace,
        status= UI.selectedStatus or "S",
        note  = UI.noteBox and UI.noteBox:GetText() or "",
      }
      if GuildNotes and GuildNotes.AddOrEditEntry then
        GuildNotes:AddOrEditEntry(name, data)
      end
      if UI.editor then UI.editor:Hide() end
      if UI.blocker then UI.blocker:Hide() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end
if not StaticPopupDialogs["GNOTES_CONFIRM_DELETE"] then
  StaticPopupDialogs["GNOTES_CONFIRM_DELETE"] = {
    text = "Delete this note?",
    button1 = YES, button2 = NO,
    OnAccept = function()
      local UI = ns.UI
      if not UI.currentKey then return end
      if GuildNotes and GuildNotes.DeleteEntry then
        GuildNotes:DeleteEntry(UI.currentKey)
      end
      if UI.editor then UI.editor:Hide() end
      if UI.blocker then UI.blocker:Hide() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
end
  ed:SetSize(520, 360)
  ed:SetPoint("CENTER")
  ed:SetFrameLevel(blocker:GetFrameLevel() + 1)
  ed:SetBackdrop({
    bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=14,
    insets={left=3,right=3,top=3,bottom=3}
  })
  ed:SetBackdropColor(0,0,0,0.95)
  ed:Hide()
  self.editor = ed

  local title = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("GuildNotes — Edit Entry")

  local function Label(parent, text, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetText(text)
    return fs
  end

  -- LEFT COLUMN -----------------------------

  -- Name
  Label(ed, "Name", 16, -40)
  local nameBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
  nameBox:SetSize(200, 20); nameBox:SetAutoFocus(false)
  nameBox:SetPoint("TOPLEFT", 16, -58)
  self.nameBox = nameBox

  -- Guild
  Label(ed, "Guild", 16, -86)
  local guildBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
  guildBox:SetSize(200, 20); guildBox:SetAutoFocus(false)
  guildBox:SetPoint("TOPLEFT", 16, -104)
  self.guildBox = guildBox

  -- Class dropdown
  Label(ed, "Class", 16, -132)
  local classDrop = CreateFrame("Frame", nil, ed, "UIDropDownMenuTemplate")
  classDrop:SetPoint("TOPLEFT", 6, -148)
  local classItems = {}
  for key,pretty in pairs(ns.CLASS_PRETTY or {}) do
    table.insert(classItems, {id=key, text=pretty})
  end
  table.sort(classItems, function(a,b) return a.text < b.text end)
  UIDropDownMenu_Initialize(classDrop, function()
    for _,item in ipairs(classItems) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = item.text
      info.arg1 = item.id
      info.func = function(_, id)
        UI.selectedClass = id
        UIDropDownMenu_SetText(classDrop, ns.ClassPretty and ns.ClassPretty(id) or id)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  self.classDrop = classDrop

  -- Race dropdown
  Label(ed, "Race", 16, -176)
  local raceDrop = CreateFrame("Frame", nil, ed, "UIDropDownMenuTemplate")
  raceDrop:SetPoint("TOPLEFT", 6, -192)
  local raceItems = {}
  for key,pretty in pairs(ns.RACE_PRETTY or {}) do
    table.insert(raceItems, {id=key, text=pretty})
  end
  table.sort(raceItems, function(a,b) return a.text < b.text end)
  UIDropDownMenu_Initialize(raceDrop, function()
    for _,item in ipairs(raceItems) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = item.text
      info.arg1 = item.id
      info.func = function(_, id)
        UI.selectedRace = id
        UIDropDownMenu_SetText(raceDrop, ns.RacePretty and ns.RacePretty(id) or id)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  self.raceDrop = raceDrop

  -- Status dropdown (includes new Skull/Griefer)
  Label(ed, "Status", 16, -220)
  local statusDrop = CreateFrame("Frame", nil, ed, "UIDropDownMenuTemplate")
  statusDrop:SetPoint("TOPLEFT", 6, -236)
  local statusItems = {
    {id="G"}, {id="S"}, {id="C"}, {id="A"}, {id="K"}, 
  }
  UIDropDownMenu_Initialize(statusDrop, function()
    for _,item in ipairs(statusItems) do
      local label = (ns.StatusLabel and ns:StatusLabel(item.id)) or item.id
      local icon  = (ns.StatusIcon3 and ns:StatusIcon3(item.id)) or ""
      local info = UIDropDownMenu_CreateInfo()
      info.text = (icon ~= "" and (icon.." ") or "") .. label
      info.arg1 = item.id
      info.func = function(_, id)
        UI.selectedStatus = id
        local lbl = (ns.StatusLabel and ns:StatusLabel(id)) or id
        local icn = (ns.StatusIcon3 and ns:StatusIcon3(id)) or ""
        UIDropDownMenu_SetText(statusDrop, (icn ~= "" and (icn.." ") or "")..lbl)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  self.statusDrop = statusDrop

-- Author / Updated (read-only info)
local metaLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
metaLabel:SetPoint("TOPLEFT", 16, -268)
metaLabel:SetText("")
self.metaLabel = metaLabel
    if self.metaLabel.SetJustifyH then self.metaLabel:SetJustifyH("LEFT") end
    if self.metaLabel.SetWidth then self.metaLabel:SetWidth(360) end
    if self.metaLabel.SetFont then
      local f, h = self.metaLabel:GetFont()
      self.metaLabel:SetFont(f, h+1)
    end
  self.setStatus = function(status)
    UI.selectedStatus = status
    local lbl = (ns.StatusLabel and ns:StatusLabel(status)) or status
    local icn = (ns.StatusIcon3 and ns:StatusIcon3(status)) or ""
    UIDropDownMenu_SetText(statusDrop, (icn ~= "" and (icn.." ") or "")..lbl)
  end

  -- RIGHT COLUMN ----------------------------

  -- Note area (label ABOVE the box)
  local noteBG = CreateFrame("Frame", nil, ed, "BackdropTemplate")
  noteBG:SetBackdrop({ edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
  noteBG:SetBackdropBorderColor(0.3,0.3,0.3,1)
  noteBG:SetPoint("TOPLEFT", ed, "TOPLEFT", 260, -58)
  noteBG:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -16, 54)

  local noteLabel = ed:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  noteLabel:SetPoint("BOTTOMLEFT", noteBG, "TOPLEFT", 0, 4)
  noteLabel:SetText("Note")

  local note = CreateFrame("EditBox", nil, noteBG)
  note:SetMultiLine(true); note:SetAutoFocus(false)
  note:SetFontObject("ChatFontNormal")
  note:SetAllPoints()
  note:SetTextInsets(8,8,8,8)
  self.noteBox = note

  -- Buttons
  local saveBtn = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
  saveBtn:SetSize(96, 22); saveBtn:SetText("Save"); saveBtn:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -16, 14)
  self.saveBtn = saveBtn
  saveBtn:SetScript("OnClick", function()
    local isEdit = (UI.currentKey ~= nil)
    if isEdit then
      StaticPopup_Show("GNOTES_CONFIRM_SAVE")
    else
      -- Even for Add, ask to confirm as requested
      StaticPopup_Show("GNOTES_CONFIRM_SAVE")
    end
  end)

  local deleteBtn = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
  deleteBtn:SetSize(96, 22); deleteBtn:SetText("Delete")
  deleteBtn:SetPoint("RIGHT", saveBtn, "LEFT", -8, 0)
  self.deleteBtn = deleteBtn
  deleteBtn:SetScript("OnClick", function()
    StaticPopup_Show("GNOTES_CONFIRM_DELETE")
  end)

  local cancelBtn = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
  cancelBtn:SetSize(96, 22); cancelBtn:SetText("Cancel")
  cancelBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -8, 0)
  cancelBtn:SetScript("OnClick", function() UI.editor:Hide(); UI.blocker:Hide() end)
end

function UI:OpenEditor(key)
  if not self.frame then self:Init() end
  self:EnsureEditor()

  if self.blocker then self.blocker:Show() end
  self.editor:Show()
  self.currentKey = key
  self:RecomputePermissions()
  if self.saveBtn then self.saveBtn:SetEnabled(self.canEdit ~= false) end

  if key and GuildNotes and GuildNotes.GetEntry then
    self.saveBtn:SetText("Save")
    self.saveBtn:SetText("Save")
    self.deleteBtn:SetShown(self.canEdit)

    local e = GuildNotes:GetEntry(key) or {}

    self.nameBox:SetText(e.name or (key:match("^[^-]+") or key))
    self.guildBox:SetText(e.guild or "")

    -- Keep internal selections for Save()
    self.selectedClass = e.class
    self.selectedRace  = e.race

    -- Class dropdown: icon + pretty (if available)
    if self.classDrop then
      local pretty = (ns.ClassPretty and ns.ClassPretty(e.class)) or (e.class or "")
      local icon   = (ns.CLASS_ICON and ns.CLASS_ICON[e.class]) or (ns.ClassIcon and ns.ClassIcon(e.class))
      local text   = ((icon and ("|T"..icon..":16|t ")) or "") .. pretty
      UIDropDownMenu_SetText(self.classDrop, text)
    end

    -- Race dropdown: icon + pretty (if available)
    if self.raceDrop then
      local pretty = (ns.RacePretty and ns.RacePretty(e.race)) or (e.race or "")
      local icon   = (ns.RACE_ICON and ns.RACE_ICON[e.race]) or (ns.RaceIcon and ns.RaceIcon(e.race))
      local text   = ((icon and ("|T"..icon..":16|t ")) or "") .. pretty
      UIDropDownMenu_SetText(self.raceDrop, text)
    end

    if self.setStatus then
      self.setStatus(ns.GetStatus and ns:GetStatus(e) or e.status or "S")
    end
    self.noteBox:SetText(e.note or "")

if self.metaLabel then
  local author = e.author or ""
  local updated = e.updated and (date and date("!%Y-%m-%d %H:%M", e.updated) or tostring(e.updated)) or ""
  if author ~= "" or updated ~= "" then
    local who = (author ~= "" and (author:gsub("%-.*$", ""))) or "unknown"
    local when = (updated ~= "" and updated) or ""
    local sep = (who ~= "" and when ~= "" and " • ") or ""
      self.metaLabel:SetText("By: "..(who or "?").."\nDate: "..when)
  else
    self.metaLabel:SetText("")
  end
end

  else
    self.saveBtn:SetText("Add"); if self.saveBtn then self.saveBtn:SetEnabled(true) end
    if self.metaLabel then self.metaLabel:SetText("") end
    self.deleteBtn:Hide()
    self.nameBox:SetText(""); self.guildBox:SetText("")
    self.noteBox:SetText(""); self.selectedClass=nil; self.selectedRace=nil
    if self.classDrop then UIDropDownMenu_SetText(self.classDrop, "") end
    if self.raceDrop  then UIDropDownMenu_SetText(self.raceDrop,  "") end
    if self.setStatus then self.setStatus("S") end
  end
end