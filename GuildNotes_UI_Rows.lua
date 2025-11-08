-- GuildNotes_UI_Rows.lua
-- Row rendering and tooltip with "GuildNote: <icon> <label>"

local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

UI.ROW_HEIGHT = 22
UI.COLS = {
  { key="name",   title="Name",   width=180 },
  { key="guild",  title="Guild",  width=210 },
  { key="class",  title="Class",  width=120 },
  { key="race",   title="Race",   width=110 },
  { key="status", title="Status", width=70  },
  { key="note",   title="Note",   width="flex" },
}

local function LayoutColumns(row, parentWidth)
  local fixed = 0
  for i=1,#UI.COLS-1 do fixed = fixed + UI.COLS[i].width + (i>1 and 10 or 0) end
  fixed = fixed + 10
  local flex = math.max(120, (parentWidth or 800) - fixed)

  local x = 0
  for _,c in ipairs(UI.COLS) do
    local w = (c.width == "flex") and flex or c.width
    local fs = row[c.key]
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x, 0)
    fs:SetWidth(w)
    fs:SetJustifyH("LEFT")
    x = x + w + 10
  end
end

local function CreateRow(parent, i, getWidth)
  local row = CreateFrame("Button", ADDON_NAME.."Row"..i, parent)
  row:SetHeight(UI.ROW_HEIGHT)
  row:SetPoint("LEFT", 0, 0)
  row:SetPoint("RIGHT", 0, 0)

  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(1,1,1,0.06)
  row.bg:Hide()
  row:SetScript("OnEnter", function(self) self.bg:Show() end)
  row:SetScript("OnLeave", function(self) self.bg:Hide(); GameTooltip:Hide() end)

  -- Columns
  for _,c in ipairs(UI.COLS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row[c.key] = fs
  end
  LayoutColumns(row, getWidth())
  -- NOTE column tooltip (full note, wrapped) – only on the note cell
  local noteFS = row.note
  noteFS:EnableMouse(true)
  noteFS:SetScript("OnEnter", function(self)
  local key = row.key
  if not key then return end
    local e = (GuildNotes and GuildNotes:GetEntry(key))
         or (GuildNotesDB and GuildNotesDB.notes and GuildNotesDB.notes[key])
         or {}
    if not e or not e.note or e.note == "" then return end

    -- Remove history entries from the note (lines starting with [YYYY-MM-DD])
    local noteText = e.note
    local lines = {}
    for line in noteText:gmatch("[^\r\n]+") do
      -- Skip lines that look like history entries: [YYYY-MM-DD] or [YYYY-MM-DD HH:MM]
      if not line:match("^%[%d%d%d%d%-%d%d%-%d%d") then
        table.insert(lines, line)
      end
    end
    local displayNote = #lines > 0 and table.concat(lines, "\n") or "(no note)"
    if displayNote == "" or displayNote == "(no note)" then
      return -- Don't show tooltip if no note content after filtering
    end

    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Note", 1, 0.82, 0)
    GameTooltip:AddLine(displayNote, 1, 1, 1, true) -- true = wrap long notes
    GameTooltip:Show()
  end)
  noteFS:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row:SetScript("OnSizeChanged", function(selfW) LayoutColumns(selfW, getWidth()) end)

  -- Tooltip with status ICON + label, prefixed by "GuildNote:"
  row:SetScript("OnEnter", function(selfW)
    selfW.bg:Show()
    if MouseIsOver(row.note) then return end
    if not selfW.key then return end
    local e = GuildNotes and GuildNotes:GetEntry(selfW.key) or {}
    if not e or e._deleted then return end

    GameTooltip:SetOwner(selfW, "ANCHOR_CURSOR")

    local name = e.name or selfW.key:match("^[^-]+") or selfW.key
    GameTooltip:AddLine(name, 1, 0.82, 0)
    if e.guild and e.guild ~= "" then
      GameTooltip:AddLine("<"..e.guild..">", 1, 0.5, 1)
    end

    local classPretty = (ns.ClassPretty and ns.ClassPretty(e.class)) or (e.class or "")
    local racePretty  = (ns.RacePretty  and ns.RacePretty(e.race )) or (e.race  or "")
    local crLine = (classPretty ~= "" or racePretty ~= "") and (string.format("%s %s", racePretty, classPretty):gsub("^%s+",""):gsub("%s+$","")) or nil
    if crLine and crLine ~= "" then GameTooltip:AddLine(crLine, 1, 1, 1) end

    local st    = ns.GetStatus and ns:GetStatus(e) or (e.status or "S")
    local icon  = ns.StatusIcon3 and ns:StatusIcon3(st) or ""
    local label = ns.StatusLabel and ns:StatusLabel(st) or st
    GameTooltip:AddLine(("GuildNote: %s%s"):format(icon ~= "" and (icon.." ") or "", label), 1, 1, 1)

    GameTooltip:Show()
  end)

  
-- Click to edit / context menu (officers only)
-- Store the original handler so we can restore it for officers
local originalClickHandler = function(self, button)
  -- Double-check permissions (in case they changed)
  if GuildNotesUI and GuildNotesUI.canEdit == false then
    return
  end
  if not self.key or not GuildNotesUI then return end
  if button == "RightButton" then
    -- open the default UnitPopup menu item we injected (Menu.lua adds it)
    if UnitPopup_ShowMenu then
      local nameOnly = (self.key:match("^[^-]+") or self.key)
      -- Fake a menu for the player name; our Menu.lua hook will add "Add note"
      ToggleDropDownMenu(1, nil, nil, self, 0, 0)
    else
      -- fallback: open editor
      GuildNotesUI:OpenEditor(self.key)
    end
  else
    -- Left click: open editor for this key
    GuildNotesUI:OpenEditor(self.key)
  end
end
row:RegisterForClicks("AnyUp")
row:SetScript("OnMouseUp", originalClickHandler)
row._originalClickHandler = originalClickHandler  -- Store for later restoration
return row
end

function UI:EnsureRows()
  if not self.list then return end
  local h = self.list:GetHeight() or 0
  local rh = (self.ROW_HEIGHT or 22)
  local needed = math.max(1, math.floor(h / rh))

  for i = 1, needed do
    if not self.rows[i] then
      self.rows[i] = CreateRow(self.list, i, function() return self.list:GetWidth() end)
      if i == 1 then
        self.rows[i]:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, 0)
      else
        self.rows[i]:SetPoint("TOPLEFT", self.rows[i-1], "BOTTOMLEFT", 0, -2)
      end
    end
  end
  for i = needed + 1, #self.rows do
    if self.rows[i] then self.rows[i]:Hide() end
  end
  self.visibleRows = needed
end

function UI:RenderRows(keys, offset)
  offset = math.max(0, tonumber(offset) or 0)
  local total = #keys
  local rh    = (self.ROW_HEIGHT or 22)

  self.list:SetHeight(math.max(self.visibleRows or 0, total) * rh)

  local inGroup = ns.GetCurrentGroupNames and ns:GetCurrentGroupNames() or {}

  for i = 1, (self.visibleRows or 0) do
    local idx = offset + i
    local row = self.rows[i]
    if idx <= total then
      local key = keys[idx]
      local e = (GuildNotes and GuildNotes:GetEntry(key))
             or (GuildNotesDB and GuildNotesDB.notes and GuildNotesDB.notes[key])
             or {}
      row:Show(); row.key = key
      
      -- Disable row clicks for non-officers (but keep hover for tooltips)
      local canEdit = (GuildNotesUI and GuildNotesUI.canEdit ~= false)
      if not canEdit then
        -- Replace click handler with a no-op for non-officers
        row:SetScript("OnMouseUp", function() end)
        row:RegisterForClicks()  -- Unregister clicks
      else
        -- Restore original click handler for officers
        if row._originalClickHandler then
          row:SetScript("OnMouseUp", row._originalClickHandler)
        end
        row:RegisterForClicks("AnyUp")  -- Ensure clicks are registered
      end

      local r,g,b = 1,1,1
      if ns and ns.RGBForClass and e.class then
        local rr,gg,bb = ns:RGBForClass(e.class); if rr then r,g,b = rr,gg,bb end
      end

      local disp = e.name or key:match("^[^-]+") or key
      if inGroup[key] then row.name:SetText("|cff00ff00*|r "..disp) else row.name:SetText(disp) end
      row.name:SetTextColor(r,g,b)

      row.guild:SetText(e.guild or "-")

      local classIcon   = (type(ns.ClassIcon)   == "function") and ns.ClassIcon(e.class)
                        or (ns.CLASS_ICON and ns.CLASS_ICON[e.class]) or nil
      local classPretty = (type(ns.ClassPretty) == "function") and ns.ClassPretty(e.class)
                        or (ns.CLASS_PRETTY and ns.CLASS_PRETTY[e.class]) or (e.class or "")
      local classText   = (ns.CellWithIcon and ns.CellWithIcon(classIcon, classPretty)) or classPretty
      row.class:SetText(classText)

      local raceIcon    = (type(ns.RaceIcon)    == "function") and ns.RaceIcon(e.race)
                        or (ns.RACE_ICON and ns.RACE_ICON[e.race]) or nil
      local racePretty  = (type(ns.RacePretty)  == "function") and ns.RacePretty(e.race)
                        or (ns.RACE_PRETTY and ns.RACE_PRETTY[e.race]) or (e.race or "")
      local raceText    = (ns.CellWithIcon and ns.CellWithIcon(raceIcon, racePretty)) or racePretty
      row.race:SetText(raceText)

      local st = ns and ns.GetStatus and ns:GetStatus(e) or (e.safe==false and "A" or "S")
      row.status:SetText(ns and ns.StatusIcon3 and ns:StatusIcon3(st) or "")

      if ns.TruncateToWidth then
        ns.TruncateToWidth(row.note, e.note or "", row.note:GetWidth())
      else
        row.note:SetText(e.note or "")
      end
    else
      row:Hide()
    end
  end
end
