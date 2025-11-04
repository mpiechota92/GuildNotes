-- GuildNotes_UI_Rows.lua
-- Render rows using a simple wheel-driven offset (no FauxScroll).
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

  for _,c in ipairs(UI.COLS) do
    row[c.key] = row:CreateFontString(nil, "OVERLAY", c.key=="name" and "GameFontNormal" or "GameFontHighlight")
  end

  row.statusHit = CreateFrame("Button", nil, row)
  row.statusHit:SetAllPoints(row.status)
  row.statusHit:SetScript("OnEnter", function(self)
    if self.statusCode and ns.StatusLabel then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText(ns:StatusLabel(self.statusCode))
      GameTooltip:Show()
    end
  end)
  row.statusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row:SetScript("OnClick", function(self)
    if self.key and UI.canEdit and UI.OpenEditor then UI:OpenEditor(self.key) end
  end)

  row:SetScript("OnSizeChanged", function(self, w) LayoutColumns(self, w) end)
  LayoutColumns(row, getWidth())

  return row
end

function UI:EnsureRows()
  -- Ensure we have a sensible number of visible rows based on list height.
  if not self.list then return end
  local avail = tonumber(self.list:GetHeight()) or 0
  local rh    = (self.ROW_HEIGHT or 22)
  local needed = math.floor(avail / rh)
  if not needed or needed < 1 then needed = 12 end

  if needed == (self.visibleRows or 0) and self.rows and #self.rows >= needed then return end

  self.rows = self.rows or {}
  for i = (self.visibleRows or 0) + 1, needed do
    local row = CreateRow(self.list, i, function() return UI.list:GetWidth() or 800 end)
    row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -((i-1)*rh))
    row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -((i-1)*rh))
    self.rows[i] = row
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

  -- Make sure container is tall enough for anchors
  self.list:SetHeight(math.max(self.visibleRows or 0, total) * rh)

  local inGroup = ns.GetCurrentGroupNames and ns:GetCurrentGroupNames() or {}

  -- Render a window of size visibleRows starting at offset+1
  for i = 1, (self.visibleRows or 0) do
    local idx = offset + i
    local row = self.rows[i]
    if idx <= total then
      local key = keys[idx]
      local e = (GuildNotes and GuildNotes:GetEntry(key))
             or (GuildNotesDB and GuildNotesDB.notes and GuildNotesDB.notes[key])
             or {}

      row:Show(); row.key = key

      local r,g,b = 1,1,1
      if ns and ns.RGBForClass and e.class then
        local rr,gg,bb = ns:RGBForClass(e.class); if rr then r,g,b = rr,gg,bb end
      end

      local disp = e.name or key:match("^[^-]+") or key
      if inGroup[key] then row.name:SetText("|cff00ff00*|r "..disp) else row.name:SetText(disp) end
      row.name:SetTextColor(r,g,b)

      row.guild:SetText(e.guild or "-")

      -- class helpers (function or table)
      local classIcon   = (type(ns.ClassIcon)   == "function") and ns.ClassIcon(e.class)
                        or (ns.CLASS_ICON and ns.CLASS_ICON[e.class]) or nil
      local classPretty = (type(ns.ClassPretty) == "function") and ns.ClassPretty(e.class)
                        or (ns.CLASS_PRETTY and ns.CLASS_PRETTY[e.class]) or (e.class or "")
      local classText   = (ns.CellWithIcon and ns.CellWithIcon(classIcon, classPretty)) or classPretty
      row.class:SetText(classText)

      -- race helpers
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
