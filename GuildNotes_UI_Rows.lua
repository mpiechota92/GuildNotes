-- GuildNotes_UI_Rows.lua
-- Rows, columns, list rendering and scroll handling

local ADDON_NAME, ns = ...
local UI = ns.UI

UI.ROW_HEIGHT = 22
UI.COLS = {
  { key="name",   title="Name",   width=160 },
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
    local font = row[c.key]
    font:ClearAllPoints()
    font:SetPoint("LEFT", row, "LEFT", x, 0)
    font:SetWidth(w)
    font:SetJustifyH("LEFT")
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
  row:SetScript("OnEnter", function(self)
    self.bg:Show()
    if self.key then
      local e = GuildNotes:GetEntry(self.key)
      if e and not e._deleted then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
        local st = ns:GetStatus(e)
        GameTooltip:AddLine(ns:StatusLabel(st).." "..ns:StatusIcon3(st), 1,1,1)
        if e.note and e.note ~= "" then
          local firstLine = e.note:gsub("\r\n","\n"):gsub("\r","\n"):match("([^\n]+)")
          if firstLine then GameTooltip:AddLine(firstLine, .9,.9,.9, true) end
        end
        GameTooltip:Show()
      end
    end
  end)
  row:SetScript("OnLeave", function(self) self.bg:Hide(); GameTooltip:Hide() end)

  for _,c in ipairs(UI.COLS) do
    row[c.key] = row:CreateFontString(nil, "OVERLAY", c.key=="name" and "GameFontNormal" or "GameFontHighlight")
  end

  row.statusHit = CreateFrame("Button", nil, row)
  row.statusHit:SetAllPoints(row.status)
  row.statusHit:SetScript("OnEnter", function(self)
    if self.statusCode then
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      GameTooltip:SetText(ns:StatusLabel(self.statusCode))
      GameTooltip:Show()
    end
  end)
  row.statusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

  row:SetScript("OnClick", function(self)
    if self.key and (UI.canEdit) then UI:OpenEditor(self.key) end
  end)

  row:SetScript("OnSizeChanged", function(self, w) LayoutColumns(self, w) end)
  LayoutColumns(row, getWidth())

  return row
end

function UI:EnsureRows()
  if not self.scroll then return end
  local avail = math.max(0, self.scroll:GetHeight() or 0)
  local needed = math.max(1, math.floor(avail / UI.ROW_HEIGHT))
  if needed == (self.visibleRows or 0) then return end
  self.rows = self.rows or {}
  for i = (self.visibleRows or 0) + 1, needed do
    local row = CreateRow(self.list, i, function() return UI.list:GetWidth() or 800 end)
    row:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -((i-1)*UI.ROW_HEIGHT))
    row:SetPoint("TOPRIGHT", self.list, "TOPRIGHT", 0, -((i-1)*UI.ROW_HEIGHT))
    self.rows[i] = row
  end
  for i = needed + 1, #self.rows do if self.rows[i] then self.rows[i]:Hide() end end
  self.visibleRows = needed
end

function UI:RenderRows(keys)
  local total = #keys
  self.totalLines = total
  self.list:SetHeight(math.max(self.visibleRows or 0, total) * UI.ROW_HEIGHT)

  local offset = FauxScrollFrame_GetOffset(self.scroll)
  local maxOffset = math.max(0, total - (self.visibleRows or 0))
  if offset > maxOffset then
    offset = maxOffset
    FauxScrollFrame_SetOffset(self.scroll, offset)
  end

  FauxScrollFrame_Update(self.scroll, total, (self.visibleRows or 0), UI.ROW_HEIGHT)

  local inGroup = ns.GetCurrentGroupNames and ns:GetCurrentGroupNames() or {}

  for i=1, (self.visibleRows or 0) do
    local idx = i + offset
    local row = self.rows[i]
    if idx <= total then
      local key = keys[idx]
      local e = GuildNotes:GetEntry(key) or {}
      row:Show(); row.key = key

      local r,g,b = 1,1,1
      if ns and ns.RGBForClass and e.class then
        local rr,gg,bb = ns:RGBForClass(e.class)
        if rr then r,g,b = rr,gg,bb end
      end
      local disp = e.name or key:match("^[^-]+") or key
      if inGroup[key] then
        row.name:SetText("|cff00ff00*|r "..disp)
      else
        row.name:SetText(disp)
      end
      row.name:SetTextColor(r,g,b)

      row.guild:SetText(e.guild or "-")
      row.class:SetText(ns.CellWithIcon(ns.ClassIcon(e.class), ns.ClassPretty(e.class)))
      row.race:SetText(ns.CellWithIcon(ns.RaceIcon(e.race),  ns.RacePretty(e.race)))
      local st = ns and ns.GetStatus and ns:GetStatus(e) or (e.safe==false and "A" or "S")
      row.status:SetText(ns and ns.StatusIcon3 and ns:StatusIcon3(st) or "")
      row.statusHit.statusCode = st

      ns.TruncateToWidth(row.note, e.note or "", row.note:GetWidth())
    else
      row:Hide()
    end
  end
end
