-- GuildNotes_UI_Main.lua
-- Frame construction, header, search, scrolling, and Refresh orchestration

local ADDON_NAME, ns = ...
local UI = ns.UI

-- === Fallback search if UI:FetchKeys isn't available (load-order safe) ===
local function NormalizeKeys(t)
  if type(t) ~= 'table' then return {} end
  if #t > 0 then return t end
  local out = {}
  for k, v in pairs(t) do
    if type(k) == 'string' and (v == true or v == 1) then
      table.insert(out, k)
    elseif type(v) == 'string' then
      table.insert(out, v)
    elseif type(v) == 'table' and v.key then
      table.insert(out, v.key)
    end
  end
  return out
end

local function FallbackFetchKeys(query)
  local queryTrim = (query or ""):match("^%s*(.-)%s*$") or ""
  local q = string.lower(queryTrim)
  if not GuildNotes then return {} end
  local all = {}
  if GuildNotes.AllKeys then
    all = NormalizeKeys(GuildNotes:AllKeys())
  elseif GuildNotes.FilteredKeys then
    all = NormalizeKeys(GuildNotes:FilteredKeys(""))
  else
    return {}
  end
  if q == "" then return all end
  local out = {}
  for _, key in ipairs(all) or {} do
    local e = GuildNotes:GetEntry(key)
    if e and not e._deleted then
      local name   = ns.SafeLower(e.name or (key:match("^[^-]+") or key))
      local guild  = ns.SafeLower(e.guild)
      local class  = ns.SafeLower(e.class or "")
      local classL = ns.SafeLower((ns.CLASS_PRETTY[e.class] or e.class or ""))
      local race   = ns.SafeLower(e.race or "")
      local raceL  = ns.SafeLower((ns.RACE_PRETTY[e.race] or e.race or ""))
      local note   = ns.SafeLower(e.note)
      local author = ns.SafeLower(e.author)
      local statL  = ns.SafeLower(ns.StatusLabel and ns:StatusLabel(ns:GetStatus(e)) or "")
      if name:find(q,1,true) or guild:find(q,1,true) or class:find(q,1,true) or classL:find(q,1,true)
         or race:find(q,1,true) or raceL:find(q,1,true) or note:find(q,1,true)
         or author:find(q,1,true) or statL:find(q,1,true) then
        table.insert(out, key)
      end
    end
  end
  if (#out == 0) and (#q <= 1) then return all end
  return out
end


local function CreateDropdown(parent, items, onSelect, width)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width or 140)
  UIDropDownMenu_Initialize(dd, function()
    for _,item in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = "|T"..item.icon..":16|t "..item.name
      info.arg1 = item.id
      info.func = function(_, arg1)
        UIDropDownMenu_SetText(dd, "|T"..item.icon..":16|t "..item.name)
        onSelect(arg1)
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  return dd
end

function UI:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", ADDON_NAME.."Main", UIParent, "BackdropTemplate")
  f:SetSize(980, 470)
  f:SetPoint("CENTER")
  f:SetBackdrop({
    bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=14,
    insets={left=3,right=3,top=3,bottom=3}
  })
  f:SetBackdropColor(0,0,0,0.96)
  f:SetFrameStrata("HIGH")
  f:SetClampedToScreen(true)
  f:Hide()
  self.frame = f

  -- ESC handling
  f:EnableKeyboard(true)
  if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      if UI.editor and UI.editor:IsShown() then
        UI.editor:Hide()
      else
        self:Hide()
      end
    end
  end)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  title:SetPoint("TOPLEFT", 12, -12); title:SetText("GuildNotes")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 4, 4)

  local search = CreateFrame("EditBox", ADDON_NAME.."SearchBox", f, "InputBoxTemplate")
  search:SetSize(320, 20); search:SetAutoFocus(false); search:SetPoint("TOPLEFT", 12, -34)
  search:SetScript("OnTextChanged", function()
    if UI.scroll then FauxScrollFrame_SetOffset(UI.scroll, 0) end
    UI:Refresh()
  end)
  self.searchBox = search

  local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  addBtn:SetSize(120, 22); addBtn:SetText("Add"); addBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
  addBtn:SetScript("OnClick", function() UI:OpenEditor(nil) end)
  self.addBtn = addBtn

  -- Header
  local hdr = CreateFrame("Frame", nil, f)
  hdr:SetHeight(22)
  hdr:SetPoint("TOPLEFT", 12, -62)
  hdr:SetPoint("TOPRIGHT", -12, -62)
  self.header = hdr

  local function headerLayout()
    local w = hdr:GetWidth()
    local fixed = 0
    for i=1,#UI.COLS-1 do fixed = fixed + UI.COLS[i].width + (i>1 and 10 or 0) end
    fixed = fixed + 10
    local flex = math.max(120, (w or 800) - fixed)
    local x = 0
    for _,c in ipairs(UI.COLS) do
      local width = (c.width=="flex") and flex or c.width
      if not hdr[c.key] then
        hdr[c.key] = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hdr[c.key]:SetJustifyH("LEFT")
        hdr[c.key]:SetText(c.title)
      end
      hdr[c.key]:ClearAllPoints()
      hdr[c.key]:SetPoint("LEFT", x, 0)
      hdr[c.key]:SetWidth(width)
      x = x + width + 10
    end
  end
  hdr:SetScript("OnSizeChanged", headerLayout); headerLayout()

  -- Scroll area
  local sf = CreateFrame("ScrollFrame", ADDON_NAME.."ScrollFrame", f, "FauxScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -86)
  sf:SetPoint("BOTTOMRIGHT", -28, 16)
  self.scroll = sf

  local list = CreateFrame("Frame", nil, sf)
  list:SetSize(sf:GetWidth(), UI.ROW_HEIGHT)
  sf:SetScrollChild(list)
  self.list = list

  self.rows = {}
  self.visibleRows = 0
  self.totalLines = 0

  -- Scroll behavior
  sf:SetScript("OnVerticalScroll", function(selfSF, arg)
    FauxScrollFrame_OnVerticalScroll(selfSF, arg, UI.ROW_HEIGHT, function() UI:Refresh() end)
  end)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(selfSF, delta)
    local offset = FauxScrollFrame_GetOffset(selfSF)
    local maxOffset = math.max(0, (UI.totalLines or 0) - (UI.visibleRows or 0))
    if delta > 0 then offset = math.max(0, offset - 1) else offset = math.min(maxOffset, offset + 1) end
    FauxScrollFrame_SetOffset(selfSF, offset)
    FauxScrollFrame_Update(selfSF, UI.totalLines or 0, UI.visibleRows or 0, UI.ROW_HEIGHT)
    UI:Refresh()
  end)

  sf:SetScript("OnSizeChanged", function() UI:EnsureRows(); UI:Refresh() end)
  f:SetScript("OnShow", function() UI:DeferredRefresh() end)

  -- Modal blocker + editor
  local blocker = CreateFrame("Frame", ADDON_NAME.."Blocker", UIParent, "BackdropTemplate")
  blocker:SetAllPoints(UIParent); blocker:SetFrameStrata("DIALOG"); blocker:EnableMouse(true); blocker:Hide()
  self.blocker = blocker

  local editor = CreateFrame("Frame", ADDON_NAME.."Editor", blocker, "BackdropTemplate")
  editor:SetSize(760, 320)
  editor:SetPoint("CENTER")
  editor:SetBackdrop({
    bgFile="Interface/DialogFrame/UI-DialogBox-Background",
    edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=14,
    insets={left=3,right=3,top=3,bottom=3}
  })
  editor:SetBackdropColor(0,0,0,1); editor:SetFrameStrata("DIALOG"); editor:SetToplevel(true); editor:SetClampedToScreen(true)
  editor:EnableMouse(true); editor:Hide()
  self.editor = editor

  editor:EnableKeyboard(true)
  if editor.SetPropagateKeyboardInput then editor:SetPropagateKeyboardInput(false) end
  editor:SetScript("OnKeyDown", function(self, key) if key == "ESCAPE" then self:Hide() end end)
  editor:SetScript("OnHide", function() if UI.blocker then UI.blocker:Hide() end end)

  local elabel = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  elabel:SetPoint("TOPLEFT", 12, -12); elabel:SetText("Add / Edit Player Note")

  local nameBox = CreateFrame("EditBox", ADDON_NAME.."NameBox", editor, "InputBoxTemplate")
  nameBox:SetSize(240, 20); nameBox:SetPoint("TOPLEFT", 12, -44); nameBox:SetAutoFocus(false)
  self.nameBox = nameBox

  local guildLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  guildLabel:SetPoint("LEFT", nameBox, "RIGHT", 12, 0); guildLabel:SetText("Guild:")

  local guildBox = CreateFrame("EditBox", ADDON_NAME.."GuildBox", editor, "InputBoxTemplate")
  guildBox:SetSize(300, 20); guildBox:SetPoint("LEFT", guildLabel, "RIGHT", 6, 0); guildBox:SetAutoFocus(false)
  self.guildBox = guildBox

  local classLbl = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  classLbl:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", 0, -10); classLbl:SetText("Class:")
  local classDrop = CreateDropdown(editor, {
    {id="WARRIOR", name="Warrior", icon=ns.CLASS_ICON.WARRIOR},
    {id="PALADIN", name="Paladin", icon=ns.CLASS_ICON.PALADIN},
    {id="HUNTER",  name="Hunter",  icon=ns.CLASS_ICON.HUNTER},
    {id="ROGUE",   name="Rogue",   icon=ns.CLASS_ICON.ROGUE},
    {id="PRIEST",  name="Priest",  icon=ns.CLASS_ICON.PRIEST},
    {id="MAGE",    name="Mage",    icon=ns.CLASS_ICON.MAGE},
    {id="WARLOCK", name="Warlock", icon=ns.CLASS_ICON.WARLOCK},
    {id="DRUID",   name="Druid",   icon=ns.CLASS_ICON.DRUID},
  }, function(val) UI.selectedClass = val end, 200)
  classDrop:SetPoint("LEFT", classLbl, "RIGHT", 6, 0)

  local raceLbl = editor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  raceLbl:SetPoint("LEFT", classDrop, "RIGHT", 18, 0); raceLbl:SetText("Race:")
  local raceDrop = CreateDropdown(editor, {
    {id="Human",    name="Human",     icon=ns.RACE_ICON.Human},
    {id="Dwarf",    name="Dwarf",     icon=ns.RACE_ICON.Dwarf},
    {id="NightElf", name="Night Elf", icon=ns.RACE_ICON.NightElf},
    {id="Gnome",    name="Gnome",     icon=ns.RACE_ICON.Gnome},
  }, function(val) UI.selectedRace = val end, 200)
  raceDrop:SetPoint("LEFT", raceLbl, "RIGHT", 6, 0)
  self.classDrop, self.raceDrop = classDrop, raceDrop

  local rbGreat = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
  rbGreat.text:SetText("Great player"); rbGreat:SetPoint("TOPLEFT", classLbl, "BOTTOMLEFT", 0, -8)
  local rbSafe  = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
  rbSafe.text:SetText("Safe"); rbSafe:SetPoint("LEFT", rbGreat.text, "RIGHT", 32, 0)
  local rbCaut  = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
  rbCaut.text:SetText("Be cautious"); rbCaut:SetPoint("LEFT", rbSafe.text, "RIGHT", 32, 0)
  local rbAvoid = CreateFrame("CheckButton", nil, editor, "UICheckButtonTemplate")
  rbAvoid.text:SetText("Avoid"); rbAvoid:SetPoint("LEFT", rbCaut.text, "RIGHT", 32, 0)
  local function setStatus(s)
    UI.selectedStatus = s
    rbGreat:SetChecked(s=="G"); rbSafe:SetChecked(s=="S"); rbCaut:SetChecked(s=="C"); rbAvoid:SetChecked(s=="A")
  end
  rbGreat:SetScript("OnClick", function() setStatus("G") end)
  rbSafe:SetScript("OnClick",  function() setStatus("S") end)
  rbCaut:SetScript("OnClick",  function() setStatus("C") end)
  rbAvoid:SetScript("OnClick", function() setStatus("A") end)
  setStatus("S"); self.setStatus = setStatus

  local noteScroll = CreateFrame("ScrollFrame", ADDON_NAME.."NoteScroll", editor, "UIPanelScrollFrameTemplate")
  noteScroll:SetPoint("TOPLEFT", rbGreat, "BOTTOMLEFT", 0, -8)
  noteScroll:SetPoint("RIGHT", -28, 0)
  noteScroll:SetHeight(180)
  local noteBox = CreateFrame("EditBox", ADDON_NAME.."NoteBox", editor, "InputBoxTemplate")
  noteBox:SetMultiLine(true); noteBox:SetAutoFocus(false)
  noteBox:SetWidth(760 - 28 - 16); noteBox:SetHeight(360)
  noteBox:SetPoint("TOPLEFT", noteScroll, "TOPLEFT", 4, -4)
  noteScroll:SetScrollChild(noteBox)
  self.noteBox = noteBox

  local saveBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  saveBtn:SetSize(120, 22); saveBtn:SetPoint("BOTTOMRIGHT", -12, 10); saveBtn:SetText("Add")
  self.saveBtn = saveBtn

  local cancelBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  cancelBtn:SetSize(80, 22); cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -10, 0); cancelBtn:SetText("Close")
  cancelBtn:SetScript("OnClick", function() editor:Hide() end)

  local deleteBtn = CreateFrame("Button", nil, editor, "UIPanelButtonTemplate")
  deleteBtn:SetSize(90, 22); deleteBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0); deleteBtn:SetText("Delete"); deleteBtn:Hide()
  deleteBtn:SetScript("OnClick", function()
    if not UI.canEdit then return end
    if UI.currentKey then
      StaticPopupDialogs["GUILDNOTES_CONFIRM_DELETE"] = {
        text = "Delete note for %s?",
        button1 = "Delete", button2 = "Cancel",
        OnAccept = function() GuildNotes:DeleteEntry(UI.currentKey); editor:Hide() end,
        timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
      }
      StaticPopup_Show("GUILDNOTES_CONFIRM_DELETE", UI.currentKey:match("^[^-]+") or UI.currentKey)
    end
  end)
  self.deleteBtn = deleteBtn

  saveBtn:SetScript("OnClick", function()
    local name = UI.nameBox and UI.nameBox:GetText() or ""
    name = (name or ""):gsub("^%s+",""):gsub("%s+$","")
    if name == "" then UIErrorsFrame:AddMessage("Enter a player name", 1,0,0); return end
    if #name > 12 then name = name:sub(1,12) end
    local guildText = UI.guildBox and UI.guildBox:GetText() or ""
    if #guildText > 24 then guildText = guildText:sub(1,24) end

    local entry = {
      name   = name,
      guild  = guildText,
      class  = UI.selectedClass,
      race   = UI.selectedRace,
      status = UI.selectedStatus or "S",
      safe   = (UI.selectedStatus ~= "A"),
      note   = UI.noteBox and UI.noteBox:GetText() or "",
      updated= (GetServerTime and GetServerTime()) or time(),
      author = UnitName("player"),
    }
    if GuildNotes and GuildNotes.AddOrEditEntry then
      GuildNotes:AddOrEditEntry(name, entry)
      print("|cff88c0d0GuildNotes:|r "..(UI.currentKey and "Updated" or "Added").." note for", name)
    end
    editor:Hide()
  end)
end

-- Orchestration
function UI:DeferredRefresh()
  if not self.frame or not self.frame:IsShown() then return end
  C_Timer.After(0, function()
    if not GuildNotesUI.frame or not GuildNotesUI.frame:IsShown() then return end
    FauxScrollFrame_SetOffset(GuildNotesUI.scroll, 0)
    GuildNotesUI:EnsureRows()
    GuildNotesUI:Refresh()
  end)
end

function UI:Toggle()
  if not self.frame then self:Init() end
  if self.frame:IsShown() then
    self.frame:Hide()
  else
    self.frame:Show()
    self:DeferredRefresh()
  end
end

function UI:ShowAndFocusSearch(text)
  if not self.frame then self:Init() end
  self.frame:Show()
  self.searchBox:SetText(text or ""); self.searchBox:SetFocus(); self:DeferredRefresh()
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end
  self:EnsureRows()

  local query = ""
  if self.searchBox and self.searchBox:GetText() then
    query = (self.searchBox:GetText():match("^%s*(.-)%s*$")) or ""
  end

  local fetch = self.FetchKeys or function(_, q) return FallbackFetchKeys(q) end
  local keys = fetch(self, query)
  self:RenderRows(keys)
end
