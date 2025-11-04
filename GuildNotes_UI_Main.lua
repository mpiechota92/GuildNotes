-- GuildNotes_UI_Main.lua
-- Frame, header, search box, and list rendering with simple wheel-driven offset.

local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

local function CreateDropdown(parent, items, onSelect, width)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width or 140)
  UIDropDownMenu_Initialize(dd, function()
    for _,item in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = (item.icon and ("|T"..item.icon..":16|t ") or "") .. (item.name or item.text or "")
      info.arg1 = item.id
      info.func = function(_, arg1)
        UIDropDownMenu_SetText(dd, (item.icon and ("|T"..item.icon..":16|t ") or "") .. (item.name or item.text or ""))
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
    UI.scrollOffset = 0 -- reset to top on new query
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

  -- List container (no ScrollFrame)
  local list = CreateFrame("Frame", ADDON_NAME.."List", f)
  list:SetPoint("TOPLEFT", 12, -86)
  list:SetPoint("BOTTOMRIGHT", -12, 16)
  self.list = list

  -- Wheel to change offset
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(_, delta)
    if not UI.totalLines or not UI.visibleRows then return end
    local maxOffset = math.max(0, UI.totalLines - UI.visibleRows)
    local step = 1
    local newOff = (UI.scrollOffset or 0) + (delta > 0 and -step or step)
    if newOff < 0 then newOff = 0 end
    if newOff > maxOffset then newOff = maxOffset end
    if newOff ~= (UI.scrollOffset or 0) then
      UI.scrollOffset = newOff
      UI:Refresh()
    end
  end)

  self.rows = {}
  self.visibleRows = 0
  self.scrollOffset = 0
  self.totalLines = 0

  -- Keep rows sized when window changes
  list:SetScript("OnSizeChanged", function() UI:EnsureRows(); UI:Refresh() end)
  f:SetScript("OnShow", function() UI:EnsureRows(); UI:Refresh() end)
end

function UI:Toggle()
  if not self.frame then self:Init() end
  if self.frame:IsShown() then self.frame:Hide() else self.frame:Show(); self:Refresh() end
end

function UI:ShowAndFocusSearch(text)
  if not self.frame then self:Init() end
  self.frame:Show()
  self.searchBox:SetText(text or ""); self.searchBox:SetFocus()
  self.scrollOffset = 0
  self:Refresh()
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then return end

  self:EnsureRows()
  if not self.visibleRows or self.visibleRows < 1 then self.visibleRows = 12 end

  local query = ""
  if self.searchBox and self.searchBox:GetText() then
    query = (self.searchBox:GetText():match("^%s*(.-)%s*$")) or ""
  end

  local keys = (self.FetchKeys and self:FetchKeys(query))
           or (GuildNotes and GuildNotes.FilteredKeys and GuildNotes:FilteredKeys(query))
           or {}

  local total = #keys
  self.totalLines = total

  -- clamp scrollOffset to current range
  local maxOffset = math.max(0, total - (self.visibleRows or 0))
  if (self.scrollOffset or 0) > maxOffset then
    self.scrollOffset = maxOffset
  end

  if self.RenderRows then
    self:RenderRows(keys, self.scrollOffset or 0)
  end
end
