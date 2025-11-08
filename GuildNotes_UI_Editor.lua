-- GuildNotes_UI_Editor.lua
-- Simple modal editor (add/edit/delete). Safe to call even if editor is not created yet.

local ADDON_NAME, ns = ...
local UI = ns.UI

local function Trim(s)
  if not s then return "" end
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function FormatStatusText(code)
  local label = (ns.StatusLabel and ns:StatusLabel(code)) or code or "S"
  local icon = (ns.StatusIcon3 and ns:StatusIcon3(code)) or ""
  if icon ~= "" then
    return icon.." "..label
  end
  return label
end

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
  blocker:Hide()
  blocker:SetScript("OnClick", function() end) -- swallow clicks
  self.blocker = blocker

  -- Modal frame
  local ed = CreateFrame("Frame", ADDON_NAME.."Editor", blocker, "BackdropTemplate")

  -- ESC handling on EDITOR only: close editor, do not propagate to main or Game Menu
  ed:EnableKeyboard(true)
  if ed.SetPropagateKeyboardInput then ed:SetPropagateKeyboardInput(false) end
  ed:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Hide() end
  end)

  -- Ensure the blocker is released when editor hides
  ed:SetScript("OnHide", function()
    if UI.blocker then
      UI.blocker:Hide()
      if UI.blocker.EnableMouse then UI.blocker:EnableMouse(false) end
    end
  end)

  -- Confirmation dialogs
  if not StaticPopupDialogs["GNOTES_CONFIRM_SAVE"] then
    StaticPopupDialogs["GNOTES_CONFIRM_SAVE"] = {
      text = "Save changes to this note?",
      button1 = YES, button2 = NO,
      OnAccept = function()
        local UI = ns.UI
        if not UI then return end
        local data = UI:CollectEditorData()
        if not data or data.name == "" then return end
        local payload = {
          guild = data.guild,
          class = data.class,
          race  = data.race,
          status= data.status,
          note  = data.note,
        }
        if GuildNotes and GuildNotes.AddOrEditEntry then
          GuildNotes:AddOrEditEntry(data.name, payload)
        end
        if UI.editor then UI.editor:Hide() end
        if UI.blocker then UI.blocker:Hide() end
        UI.pendingAction = nil
      end,
      OnCancel = function()
        local UI = ns.UI
        if UI then UI.pendingAction = nil end
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
  if not StaticPopupDialogs["GNOTES_CONFIRM_SUBMIT"] then
    StaticPopupDialogs["GNOTES_CONFIRM_SUBMIT"] = {
      text = "A note for %s already exists.\nSubmit your changes for officer review?",
      button1 = SUBMIT or "Submit",
      button2 = CANCEL,
      OnAccept = function(_, playerName)
        local UI = ns.UI
        if not UI then return end
        local data = UI:CollectEditorData()
        if not data or data.name == "" then return end
        local pending = UI.pendingAction or {}
        local target = pending.key or data.name
        if GuildNotes and GuildNotes.SubmitReport then
          GuildNotes:SubmitReport(target, data)
        end
        if UI.editor then UI.editor:Hide() end
        if UI.blocker then UI.blocker:Hide() end
        UI.pendingAction = nil
      end,
      OnCancel = function()
        local UI = ns.UI
        if UI then UI.pendingAction = nil end
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

  -- TAB: Name -> Guild
  self.nameBox:SetScript("OnTabPressed", function()
    if UI.guildBox and UI.guildBox.SetFocus then UI.guildBox:SetFocus() end
  end)
  -- ESC: just unfocus
  self.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  -- Guild
  Label(ed, "Guild", 16, -86)
  local guildBox = CreateFrame("EditBox", nil, ed, "InputBoxTemplate")
  guildBox:SetSize(200, 20); guildBox:SetAutoFocus(false)
  guildBox:SetPoint("TOPLEFT", 16, -104)
  self.guildBox = guildBox

  -- TAB: Guild -> Note
  self.guildBox:SetScript("OnTabPressed", function()
    if UI.noteBox and UI.noteBox.SetFocus then UI.noteBox:SetFocus() end
  end)
  -- ESC: just unfocus
  self.guildBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

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

  -- Status dropdown
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
    local fnt, h = self.metaLabel:GetFont()
    self.metaLabel:SetFont(fnt, h+1)
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

  -- ESC: just unfocus note
  self.noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

  -- Buttons
  local saveBtn = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
  saveBtn:SetSize(96, 22); saveBtn:SetText("Save"); saveBtn:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -16, 14)
  self.saveBtn = saveBtn
  saveBtn:SetScript("OnClick", function()
    local intent = UI:DetermineSaveIntent()
    if not intent or intent.intent == "NONE" then return end
    if intent.intent == "DENY" then
      if intent.message then
        print("|cff88c0d0[GuildNotes]|r", intent.message)
      end
      return
    end
    UI.pendingAction = intent
    if intent.intent == "SUBMIT" then
      StaticPopup_Show("GNOTES_CONFIRM_SUBMIT", intent.displayName or "")
    else
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
  cancelBtn:SetScript("OnClick", function()
    if UI.editor then UI.editor:Hide() end
    if UI.blocker then UI.blocker:Hide() end
  end)
end

function UI:CollectEditorData()
  local name = Trim(self.nameBox and self.nameBox:GetText() or "")
  local guild = Trim(self.guildBox and self.guildBox:GetText() or "")
  local note = self.noteBox and self.noteBox:GetText() or ""
  note = note:gsub("\r\n", "\n"):gsub("\r", "\n")
  return {
    name = name,
    guild = guild,
    class = self.selectedClass,
    race  = self.selectedRace,
    status = self.selectedStatus or "S",
    note = Trim(note),
  }
end

function UI:DetermineSaveIntent()
  local data = self:CollectEditorData()
  if not data or data.name == "" then
    return { intent = "NONE" }
  end
  local key = ns and ns.PlayerKey and ns:PlayerKey(data.name)
  local existing = nil
  if key and GuildNotes and GuildNotes.GetEntry then
    existing = GuildNotes:GetEntry(key)
    -- Ignore deleted entries - treat them as if they don't exist
    if existing and existing._deleted then
      existing = nil
    end
  end
  local canEdit = (self.canEdit ~= false)
  local isEditing = self.currentKey and key and (self.currentKey == key)

  -- If a note already exists for this player:
  -- - If adding new (not editing an opened note) -> always submit for review
  -- - If editing (opened existing note) AND officer -> save directly
  -- - If editing (opened existing note) AND not officer -> submit for review
  if existing then
    if isEditing and canEdit then
      -- Officer editing their own opened note - save directly
      return {
        intent = "SAVE",
        key = key,
        existing = existing,
        displayName = existing.name or data.name,
      }
    else
      -- Adding new note for existing player OR non-officer editing - submit for review
      return {
        intent = "SUBMIT",
        key = key,
        existing = existing,
        displayName = existing.name or data.name,
      }
    end
  end

  -- No existing note - all players can create new notes directly
  return {
    intent = "SAVE",
    key = key,
    existing = nil,
    displayName = data.name,
  }
end

function UI:OpenEditor(key)
  if not self.frame then self:Init() end
  self:EnsureEditor()

  -- Show blocker & capture clicks while editor is open
  if self.blocker then
    self.blocker:Show()
    if self.blocker.EnableMouse then self.blocker:EnableMouse(true) end
  end

  self.editor:Show()
  self.currentKey = key
  self.pendingAction = nil
  self:RecomputePermissions()

  if key and GuildNotes and GuildNotes.GetEntry then
    local canDirectEdit = (self.canEdit ~= false)
    if self.saveBtn then
      self.saveBtn:SetText(canDirectEdit and "Save" or "Submit")
      self.saveBtn:SetEnabled(true)
      self.saveBtn:SetMotionScriptsWhileDisabled(false)
      if not canDirectEdit then
        self.saveBtn:SetScript("OnEnter", function(btn)
          GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
          GameTooltip:AddLine("Submit your update for officer review.")
          GameTooltip:Show()
        end)
        self.saveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      else
        self.saveBtn:SetScript("OnEnter", nil)
        self.saveBtn:SetScript("OnLeave", nil)
      end
    end
    self.deleteBtn:SetShown(canDirectEdit)

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
        self.metaLabel:SetText("By: "..(who or "?").."\nDate: "..when)
      else
        self.metaLabel:SetText("")
      end
    end

  else
    -- Adding a new note - all players can do this
    if self.saveBtn then
      self.saveBtn:SetText("Add")
      self.saveBtn:SetEnabled(true)
      self.saveBtn:SetMotionScriptsWhileDisabled(false)
      self.saveBtn:SetScript("OnEnter", nil)
      self.saveBtn:SetScript("OnLeave", nil)
    end
    if self.metaLabel then self.metaLabel:SetText("") end
    self.deleteBtn:Hide()
    self.nameBox:SetText(""); self.guildBox:SetText("")
    self.noteBox:SetText(""); self.selectedClass=nil; self.selectedRace=nil
    if self.classDrop then UIDropDownMenu_SetText(self.classDrop, "") end
    if self.raceDrop  then UIDropDownMenu_SetText(self.raceDrop,  "") end
    if self.setStatus then self.setStatus("S") end
  end
end

function UI:EnsureReview()
  -- If frame exists, destroy it to force recreation with new layout
  if self.reviewFrame then
    self.reviewFrame:Hide()
    self.reviewFrame = nil
  end
  self:EnsureEditor()

  -- Spacing constants for consistent layout
  local SPACING = 12  -- Standard spacing between elements
  local MARGIN = 16   -- Window margins
  local PANEL_HEIGHT = 200  -- Height of the two main panels
  local NOTE_HEIGHT = 100    -- Height of the note input field
  local SECTION_SPACING = 4  -- Reduced spacing between major sections

  local review = CreateFrame("Frame", ADDON_NAME.."Review", self.blocker, "BackdropTemplate")
  review:SetSize(600, 580)
  review:SetPoint("CENTER")
  review:SetFrameLevel(self.blocker:GetFrameLevel() + 2)
  review:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  review:SetBackdropColor(0,0,0,0.95)
  review:Hide()
  
  -- Make review window movable and link to main window
  review:SetMovable(true)
  review:EnableMouse(true)
  review:RegisterForDrag("LeftButton")
  review:SetClampedToScreen(true)
  review:SetScript("OnDragStart", function(self)
    self:StartMoving()
    -- Also move the main window if it exists
    if UI.frame and UI.frame:IsShown() then
      UI.frame:StartMoving()
    end
  end)
  review:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    -- Also stop moving the main window
    if UI.frame then
      UI.frame:StopMovingOrSizing()
    end
    -- Update main window position to match review window
    if UI.frame then
      local reviewX, reviewY = self:GetCenter()
      local mainX, mainY = UI.frame:GetCenter()
      if reviewX and reviewY and mainX and mainY then
        local offsetX = reviewX - mainX
        local offsetY = reviewY - mainY
        -- Store offset for future positioning
        UI.reviewOffsetX = offsetX
        UI.reviewOffsetY = offsetY
      end
    end
  end)
  
  review:EnableKeyboard(true)
  if review.SetPropagateKeyboardInput then review:SetPropagateKeyboardInput(false) end
  review:SetScript("OnKeyDown", function(selfFrame, key)
    if key == "ESCAPE" then selfFrame:Hide() end
  end)
  review:SetScript("OnHide", function()
    if UI.blocker then
      UI.blocker:Hide()
      if UI.blocker.EnableMouse then UI.blocker:EnableMouse(false) end
    end
    UI.reviewList = nil
    UI.reviewIndex = nil
  end)
  self.reviewFrame = review

  -- Header section
  local title = review:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOPLEFT", MARGIN, -MARGIN)
  title:SetText("GuildNotes — Review Reports")

  local close = CreateFrame("Button", nil, review, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -MARGIN, -MARGIN)
  close:SetScript("OnClick", function() review:Hide() end)

  local queueText = review:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  queueText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -SPACING)
  queueText:SetText("Submission 0 of 0")
  self.reviewQueueText = queueText

  local nameText = review:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  nameText:SetPoint("TOPLEFT", queueText, "BOTTOMLEFT", 0, -SPACING)
  nameText:SetText("")
  nameText:SetJustifyH("LEFT")
  self.reviewName = nameText

  local metaText = review:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  metaText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -4)
  metaText:SetWidth(560)
  metaText:SetJustifyH("LEFT")
  metaText:SetText("")
  self.reviewMeta = metaText

  -- Calculate column dimensions with equal spacing on both sides
  local reviewWidth = 600
  local gapBetweenColumns = SPACING
  -- Make panels narrower to ensure equal spacing on left and right
  local panelPadding = 20  -- Extra padding to make panels narrower
  local totalMargins = MARGIN * 2 + gapBetweenColumns + panelPadding * 2  -- left + gap + right + extra padding
  local columnWidth = math.floor((reviewWidth - totalMargins) / 2)

  -- Create column function with proper alignment
  local function CreateColumn(parent, labelText, ...)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(columnWidth, PANEL_HEIGHT)
    box:SetBackdrop({
      bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = { left = 0, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0,0,0,0.6)
    box:SetPoint(...)

    -- Header aligned to left edge
    local label = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", 6, -SPACING)
    label:SetText(labelText)

    -- Status text aligned with header
    local status = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -SPACING)
    status:SetText("")
    status:SetJustifyH("LEFT")

    -- Note text aligned with header, with proper width
    -- For left panel: reduced spacing, for right panel: normal spacing
    local note = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -SPACING)
    note:SetWidth(columnWidth - 12)
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    note:SetText("")

    return box, status, note
  end

  -- Create the two main panels with different spacing
  -- Left panel: reduced spacing between status and note
  local currentBox, currentStatus, currentNote = CreateColumn(review, "Current Record", "TOPLEFT", metaText, "BOTTOMLEFT", MARGIN, -SPACING)
  self.reviewCurrentStatus = currentStatus
  self.reviewCurrentNote = currentNote
  -- Reduce spacing in left panel between status and note (from 12px to 4px)
  currentNote:SetPoint("TOPLEFT", currentStatus, "BOTTOMLEFT", 0, -4)

  local submittedBox, submittedStatus, submittedNote = CreateColumn(review, "Submitted Report", "LEFT", currentBox, "RIGHT", gapBetweenColumns, 0)
  self.reviewSubmittedStatus = submittedStatus
  
  -- Replace submitted note FontString with EditBox for selectable text
  submittedNote:Hide()
  local submittedNoteBG = CreateFrame("Frame", nil, submittedBox, "BackdropTemplate")
  submittedNoteBG:SetBackdrop({
    bgFile = "Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  submittedNoteBG:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  submittedNoteBG:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  local columnWidth = math.floor((600 - (MARGIN * 2 + gapBetweenColumns + 40)) / 2)
  submittedNoteBG:SetPoint("TOPLEFT", submittedStatus, "BOTTOMLEFT", -2, -18)
  submittedNoteBG:SetPoint("BOTTOMRIGHT", submittedBox, "BOTTOMRIGHT", -6, 6)
  
  local submittedNoteEdit = CreateFrame("EditBox", nil, submittedNoteBG)
  submittedNoteEdit:SetMultiLine(true)
  submittedNoteEdit:SetAutoFocus(false)
  submittedNoteEdit:SetFontObject("GameFontHighlightSmall")
  submittedNoteEdit:SetAllPoints()
  submittedNoteEdit:SetTextInsets(4, 4, 4, 4)
  -- Make it read-only (selectable but not editable)
  submittedNoteEdit:SetScript("OnChar", function(self, text)
    -- Restore original text to prevent editing
    if self._originalText then
      self:SetText(self._originalText)
    end
  end)
  submittedNoteEdit:SetScript("OnTextChanged", function(self, isUserInput)
    if isUserInput and self._originalText then
      -- Restore original text if user tries to edit
      self:SetText(self._originalText)
    end
  end)
  submittedNoteEdit:SetScript("OnEditFocusGained", function(self)
    -- Store original text when focus is gained
    self._originalText = self:GetText()
    self:HighlightText()
  end)
  submittedNoteEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  submittedNoteEdit:EnableMouse(true)
  submittedNoteEdit:SetScript("OnMouseUp", function(self)
    self:SetFocus()
    self:HighlightText()
  end)
  self.reviewSubmittedNote = submittedNoteEdit

  -- Notice message with reduced spacing
  self.reviewNotice = review:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  self.reviewNotice:SetPoint("TOPLEFT", currentBox, "BOTTOMLEFT", 0, -SECTION_SPACING)
  self.reviewNotice:SetWidth(560)
  self.reviewNotice:SetJustifyH("LEFT")
  self.reviewNotice:SetText("")

  -- Edit section with reduced spacing
  local editLabel = review:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  editLabel:SetPoint("TOPLEFT", self.reviewNotice, "BOTTOMLEFT", 0, -SECTION_SPACING)
  editLabel:SetText("Edit before accepting:")

  local statusLabel = review:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  statusLabel:SetPoint("TOPLEFT", editLabel, "BOTTOMLEFT", 0, -SPACING)
  statusLabel:SetText("Status:")

  local statusDrop = CreateFrame("Frame", nil, review, "UIDropDownMenuTemplate")
  statusDrop:SetPoint("TOPLEFT", statusLabel, "BOTTOMLEFT", 0, -4)
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
        UI.reviewSelectedStatus = id
        local lbl = (ns.StatusLabel and ns:StatusLabel(id)) or id
        local icn = (ns.StatusIcon3 and ns:StatusIcon3(id)) or ""
        UIDropDownMenu_SetText(statusDrop, (icn ~= "" and (icn.." ") or "")..lbl)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetWidth(statusDrop, 140)
  self.reviewStatusDrop = statusDrop

  -- Note label and input field with consistent spacing
  local noteLabel = review:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  noteLabel:SetPoint("TOPLEFT", statusDrop, "BOTTOMLEFT", 0, -SPACING)
  noteLabel:SetText("Note:")

  -- Note input field with fixed height
  local noteBG = CreateFrame("Frame", nil, review, "BackdropTemplate")
  noteBG:SetBackdrop({
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  noteBG:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
  noteBG:SetHeight(NOTE_HEIGHT)
  noteBG:SetPoint("TOP", noteLabel, "BOTTOM", 0, -SPACING)
  noteBG:SetPoint("LEFT", review, "LEFT", MARGIN, 0)
  noteBG:SetPoint("RIGHT", review, "RIGHT", -MARGIN, 0)
  -- Ensure height is enforced (set after anchors to prevent override)
  noteBG:SetHeight(NOTE_HEIGHT)

  local noteBox = CreateFrame("EditBox", nil, noteBG)
  noteBox:SetMultiLine(true)
  noteBox:SetAutoFocus(false)
  noteBox:SetFontObject("ChatFontNormal")
  noteBox:SetAllPoints()
  noteBox:SetTextInsets(8, 8, 8, 8)
  noteBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  self.reviewNoteBox = noteBox

  -- Buttons at the bottom with consistent spacing
  local prevBtn = CreateFrame("Button", nil, review, "UIPanelButtonTemplate")
  prevBtn:SetSize(96, 22)
  prevBtn:SetPoint("BOTTOMLEFT", review, "BOTTOMLEFT", MARGIN, MARGIN)
  prevBtn:SetText("< Previous")
  prevBtn:SetScript("OnClick", function() UI:ReviewPrev() end)
  self.reviewPrevBtn = prevBtn

  local nextBtn = CreateFrame("Button", nil, review, "UIPanelButtonTemplate")
  nextBtn:SetSize(96, 22)
  nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", SPACING, 0)
  nextBtn:SetText("Next >")
  nextBtn:SetScript("OnClick", function() UI:ReviewNext() end)
  self.reviewNextBtn = nextBtn

  local rejectBtn = CreateFrame("Button", nil, review, "UIPanelButtonTemplate")
  rejectBtn:SetSize(96, 22)
  rejectBtn:SetPoint("BOTTOMRIGHT", review, "BOTTOMRIGHT", -232, MARGIN)
  rejectBtn:SetText("Reject")
  rejectBtn:SetScript("OnClick", function() UI:RejectCurrentReport() end)
  self.reviewRejectBtn = rejectBtn

  local acceptBtn = CreateFrame("Button", nil, review, "UIPanelButtonTemplate")
  acceptBtn:SetSize(96, 22)
  acceptBtn:SetPoint("LEFT", rejectBtn, "RIGHT", SPACING, 0)
  acceptBtn:SetText("Accept")
  acceptBtn:SetScript("OnClick", function() UI:AcceptCurrentReport() end)
  self.reviewAcceptBtn = acceptBtn

  local closeBtn = CreateFrame("Button", nil, review, "UIPanelButtonTemplate")
  closeBtn:SetSize(96, 22)
  closeBtn:SetPoint("LEFT", acceptBtn, "RIGHT", SPACING, 0)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() review:Hide() end)
  self.reviewCloseBtn = closeBtn
end

function UI:OpenReviewQueue(focusKey)
  if self.canEdit == false then
    print("|cff88c0d0[GuildNotes]|r", "Only officers can review submissions.")
    return
  end
  if not self.frame then self:Init() end
  self:EnsureReview()

  if self.blocker then
    self.blocker:Show()
    if self.blocker.EnableMouse then self.blocker:EnableMouse(true) end
  end
  if self.editor then self.editor:Hide() end

  self.reviewFrame:Show()
  self:ReloadReviewList(focusKey)
end

function UI:ReloadReviewList(focusKey)
  if not self.reviewFrame then return end
  local list = {}
  if GuildNotes and GuildNotes.GetPendingReports then
    list = GuildNotes:GetPendingReports() or {}
  end
  self.reviewList = list
  local total = #list
  if total == 0 then
    print("|cff88c0d0[GuildNotes]|r", "No submissions awaiting review.")
    self.reviewFrame:Hide()
    if self.UpdateReviewButton then self:UpdateReviewButton() end
    return
  end

  local targetIndex = self.reviewIndex or 1
  if focusKey then
    for i,item in ipairs(list) do
      if item.key == focusKey then
        targetIndex = i
        break
      end
    end
  end
  if targetIndex < 1 then targetIndex = 1 end
  if targetIndex > total then targetIndex = total end
  self.reviewIndex = targetIndex
  self:RenderReview()
  if self.UpdateReviewButton then self:UpdateReviewButton() end
end

local function FormatNoteDisplay(note)
  if not note or note == "" then
    return "|cff5e81ac— No note —|r"
  end
  -- Remove history entries (lines starting with [YYYY-MM-DD])
  local lines = {}
  for line in note:gmatch("[^\r\n]+") do
    -- Skip lines that look like history entries: [YYYY-MM-DD] or [YYYY-MM-DD HH:MM]
    if not line:match("^%[%d%d%d%d%-%d%d%-%d%d") then
      table.insert(lines, line)
    end
  end
  if #lines == 0 then
    return "|cff5e81ac— No note —|r"
  end
  return table.concat(lines, "\n")
end

function UI:RenderReview()
  if not self.reviewFrame then return end
  local list = self.reviewList or {}
  local total = #list
  if total == 0 then
    self.reviewFrame:Hide()
    return
  end
  local index = self.reviewIndex or 1
  if index < 1 then index = 1 end
  if index > total then index = total end
  self.reviewIndex = index

  local item = list[index]
  local report = item and item.report or {}
  
  -- Debug: Check if report has note field
  -- print("DEBUG: report.note =", report.note, "type =", type(report.note))
  local entry = nil
  if item and item.key then
    if GuildNotes and GuildNotes.GetEntry then
      entry = GuildNotes:GetEntry(item.key)
    end
    if not entry and ns and ns.db and ns.db.notes then
      entry = ns.db.notes[item.key]
    end
  end
  entry = entry or {}

  local name = entry.name or (item and item.key and item.key:match("^[^-]+")) or (item and item.key) or "Unknown"
  local submittedBy = (report.author or ""):gsub("%-.*$", "")
  local submittedAt = report.ts and date and date("%Y-%m-%d %H:%M", report.ts) or "unknown time"

  if self.reviewName then self.reviewName:SetText(name) end
  if self.reviewQueueText then self.reviewQueueText:SetText(("Submission %d of %d"):format(index, total)) end
  if self.reviewMeta then
    self.reviewMeta:SetText(string.format("Submitted by %s on %s", submittedBy ~= "" and submittedBy or "unknown", submittedAt))
  end

  local existingStatus = (ns.GetStatus and ns:GetStatus(entry)) or entry.status or "S"
  local submittedStatus = report.status or existingStatus
  local severityChanged = ns.StatusSeverity and ns:StatusSeverity(submittedStatus) > ns:StatusSeverity(existingStatus)

  if self.reviewCurrentStatus then
    self.reviewCurrentStatus:SetText("|cffECEFF4"..FormatStatusText(existingStatus).."|r")
  end
  if self.reviewSubmittedStatus then
    local color = severityChanged and "|cffff5555" or "|cffA3BE8C"
    self.reviewSubmittedStatus:SetText(color..FormatStatusText(submittedStatus).."|r")
  end

  -- Current note: show only current note (no history)
  if self.reviewCurrentNote then
    self.reviewCurrentNote:SetTextColor(0.85, 0.88, 0.94)
    self.reviewCurrentNote:SetText(FormatNoteDisplay(entry.note))
  end
  
  -- Submitted note: make it selectable in EditBox (read-only)
  if self.reviewSubmittedNote then
    -- Get the note from the report, checking multiple possible locations
    local rawNote = report.note or ""
    -- Trim whitespace but preserve the note if it has content
    rawNote = rawNote:gsub("^%s+", ""):gsub("%s+$", "")
    
    local displayNote = rawNote
    if displayNote == "" then
      displayNote = "(no note provided)"
    else
      -- Add extra spacing between elements in the note text for better readability
      displayNote = displayNote:gsub("(%S)(%s*)([X?✓])", "%1  %3")  -- Add space before status icons
      displayNote = displayNote:gsub("([X?✓])(%s*)([^%s,])", "%1  %3")  -- Add space after status icons
      -- Remove history entries from submitted note (but only if note has actual content)
      local lines = {}
      for line in displayNote:gmatch("[^\r\n]+") do
        -- Skip lines that look like history entries: [YYYY-MM-DD]
        if not line:match("^%[%d%d%d%d%-%d%d%-%d%d") then
          table.insert(lines, line)
        end
      end
      -- Only show "(no note provided)" if ALL lines were history entries
      -- If there's at least one non-history line, show the filtered note
      if #lines > 0 then
        displayNote = table.concat(lines, "\n")
      else
        -- If all lines were filtered out but original note wasn't empty, show original
        displayNote = rawNote ~= "" and rawNote or "(no note provided)"
      end
    end
    
    self.reviewSubmittedNote:SetText(displayNote)
    -- Store as original text for read-only protection
    self.reviewSubmittedNote._originalText = displayNote
    local color = severityChanged and {1,0.6,0.6} or {0.8,0.85,1}
    self.reviewSubmittedNote:SetTextColor(color[1], color[2], color[3])
  end

  if self.reviewNotice then
    if report.requestedStatus and report.requestedStatus ~= "" and ns:StatusSeverity(report.requestedStatus) < ns:StatusSeverity(existingStatus) then
      self.reviewNotice:SetText("|cffd08770Requested status upgrade was held at current level; review note only.|r")
    else
      self.reviewNotice:SetText("")
    end
  end

  -- Populate edit fields with submitted values (officer can modify)
  if self.reviewStatusDrop then
    local editStatus = submittedStatus or existingStatus
    self.reviewSelectedStatus = editStatus
    local lbl = (ns.StatusLabel and ns:StatusLabel(editStatus)) or editStatus
    local icn = (ns.StatusIcon3 and ns:StatusIcon3(editStatus)) or ""
    UIDropDownMenu_SetText(self.reviewStatusDrop, (icn ~= "" and (icn.." ") or "")..lbl)
  end
  -- Note text field should contain current record's note (not submitted note)
  -- Remove history entries from the note
  if self.reviewNoteBox then
    local currentNote = entry.note and entry.note ~= "" and entry.note or ""
    -- Remove history entries (lines starting with [YYYY-MM-DD])
    local lines = {}
    for line in currentNote:gmatch("[^\r\n]+") do
      -- Skip lines that look like history entries: [YYYY-MM-DD] or [YYYY-MM-DD HH:MM]
      if not line:match("^%[%d%d%d%d%-%d%d%-%d%d") then
        table.insert(lines, line)
      end
    end
    currentNote = table.concat(lines, "\n")
    self.reviewNoteBox:SetText(currentNote)
  end

  if self.reviewPrevBtn then self.reviewPrevBtn:SetEnabled(index > 1) end
  if self.reviewNextBtn then self.reviewNextBtn:SetEnabled(index < total) end
  if self.reviewAcceptBtn then self.reviewAcceptBtn:SetEnabled(true) end
  if self.reviewRejectBtn then self.reviewRejectBtn:SetEnabled(true) end
end

function UI:ReviewPrev()
  if not self.reviewIndex then return end
  if self.reviewIndex <= 1 then return end
  self.reviewIndex = self.reviewIndex - 1
  self:RenderReview()
end

function UI:ReviewNext()
  if not self.reviewIndex or not self.reviewList then return end
  if self.reviewIndex >= #self.reviewList then return end
  self.reviewIndex = self.reviewIndex + 1
  self:RenderReview()
end

function UI:AcceptCurrentReport()
  if not self.reviewList or not self.reviewIndex then return end
  local item = self.reviewList[self.reviewIndex]
  if not item or not item.key or not item.index then return end
  
  -- Get edited values from the UI
  local editedStatus = self.reviewSelectedStatus or item.report.status or "S"
  local editedNote = ""
  if self.reviewNoteBox then
    editedNote = self.reviewNoteBox:GetText() or ""
    editedNote = editedNote:gsub("^%s+", ""):gsub("%s+$", "")
  end
  
  local ok = GuildNotes and GuildNotes.ApplyReport and GuildNotes:ApplyReport(item.key, item.index, editedStatus, editedNote)
  if not ok then
    print("|cff88c0d0[GuildNotes]|r", "Unable to apply report (maybe already processed).")
  else
    print("|cff88c0d0[GuildNotes]|r", "Report accepted with officer modifications.")
  end
  self:ReloadReviewList(item.key)
end

function UI:RejectCurrentReport()
  if not self.reviewList or not self.reviewIndex then return end
  local item = self.reviewList[self.reviewIndex]
  if not item or not item.key or not item.index then return end
  local ok = GuildNotes and GuildNotes.RejectReport and GuildNotes:RejectReport(item.key, item.index)
  if not ok then
    print("|cff88c0d0[GuildNotes]|r", "Unable to reject report (maybe already processed).")
  end
  self:ReloadReviewList(item.key)
end
