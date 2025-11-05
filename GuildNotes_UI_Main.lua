-- GuildNotes_UI_Main.lua
-- Frame, header, search box, and list rendering WITH paging footer + mouse wheel paging.

local ADDON_NAME, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local UpdateFooter  -- forward declaration

-- Page-based wheel scrolling: move exactly one page per step (no overlaps)
function UI:ScrollOffsetBy(n)
  -- n: positive = next page, negative = previous page (we clamp)
  local per   = math.max(self.visibleRows or 0, 1)
  local keys  = self.sortedKeys or {}
  local total = #keys

  -- total pages
  local totalPages = (total > 0) and math.ceil(total / per) or 0
  if totalPages == 0 then
    self.pageIndex = 0
    self.offset    = 0
    if self.RenderRows then self:RenderRows({}, 0) end
    UpdateFooter(self)
    return
  end

  -- move exactly one page per wheel tick
  local dir = (n or 0)
  if dir > 0 then dir = 1 elseif dir < 0 then dir = -1 else dir = 0 end

  -- clamp page index
  local page = (self.pageIndex or 1) + dir
  if page < 1 then page = 1 end
  if page > totalPages then page = totalPages end
  self.pageIndex = page

  -- page-aligned offset
  self.offset = (page - 1) * per

  -- render & update footer
  if self.RenderRows then self:RenderRows(keys, self.offset) end
  UpdateFooter(self)
end


local function CreateDropdown(parent, items, onSelect, width)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(dd, width or 140)
  UIDropDownMenu_Initialize(dd, function()
    for _,item in ipairs(items) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = (item.icon and ("|T"..item.icon..":16|t ") or "") .. (item.name or item.text or "")
      info.arg1 = item.id
      info.func = function(_, arg1)
        if onSelect then onSelect(arg1) end
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  return dd
end

-- Utils
local function ceildiv(a,b) if b<=0 then return 0 end return math.floor((a + b - 1) / b) end
local function clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

function UpdateFooter(self)
  if not self.pageFooter then return end
  local totalPages = self.totalPages or 0
  local page = self.pageIndex or 0

  if totalPages <= 0 then
    self.pageFooter.pageText:SetText("Page 0 of 0")
    self.pageFooter.prev:Disable()
    self.pageFooter.next:Disable()
    return
  end

  self.pageFooter.pageText:SetText(("Page %d of %d"):format(page, totalPages))
  if page <= 1 then self.pageFooter.prev:Disable() else self.pageFooter.prev:Enable() end
  if page >= totalPages then self.pageFooter.next:Disable() else self.pageFooter.next:Enable() end
end

local function RecomputePages(self)
  local total = self.totalLines or 0
  local per   = self.visibleRows or 0
  self.totalPages = (per > 0) and ceildiv(total, per) or 0
  if self.totalPages == 0 then
    self.pageIndex = 0
  else
    self.pageIndex = math.min(math.max(self.pageIndex or 1, 1), self.totalPages)
  end
end

function UI:Init()
  if self.frame then return end

  local f = CreateFrame("Frame", ADDON_NAME.."Main", UIParent, "BackdropTemplate")
  f:SetSize(980, 470)
  f:SetPoint("CENTER")
  -- Make it draggable
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
  -- f:SetUserPlaced(true)
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

  -- ESC handling on MAIN: close editor first (if open) else close main; do not propagate to Game Menu
  f:EnableKeyboard(true)
  if f.SetPropagateKeyboardInput then f:SetPropagateKeyboardInput(true) end
  f:SetScript("OnKeyDown", function(selfFrame, key)
    if key == "ESCAPE" then
      if selfFrame.SetPropagateKeyboardInput then selfFrame:SetPropagateKeyboardInput(false) end
      if UI.editor and UI.editor:IsShown() then
        UI.editor:Hide()
      else
        selfFrame:Hide()
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
    UI.pageIndex = 1 -- reset to first page on new query
    UI:Refresh()
  end)
  self.searchBox = search

  local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  addBtn:SetSize(120, 22); addBtn:SetText("Add")
  addBtn:Enable(); addBtn:SetPoint("LEFT", search, "RIGHT", 8, 0)
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
        local fs = hdr:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hdr[c.key] = fs
      end
      local fs = hdr[c.key]
      fs:ClearAllPoints()
      fs:SetPoint("LEFT", hdr, "LEFT", x, 0)
      fs:SetWidth(width)
      fs:SetJustifyH("LEFT")
      fs:SetText(c.title or c.key)
      x = x + width + 10
    end
  end
  hdr:SetScript("OnSizeChanged", headerLayout); headerLayout()

  -- Footer (page text centered, arrows on the right)
  local footer = CreateFrame("Frame", ADDON_NAME.."Footer", f)
  footer:SetHeight(24)
  footer:SetPoint("LEFT", f, "LEFT", 12, 0)
  footer:SetPoint("RIGHT", f, "RIGHT", -12, 0)
  footer:SetPoint("BOTTOM", f, "BOTTOM", 0, 12)
  self.pageFooter = footer

  -- Container on right for the arrow buttons (kept fixed-width so text cannot overlap)
  local btnContainer = CreateFrame("Frame", nil, footer)
  btnContainer:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
  btnContainer:SetSize(60, 24) -- 24 + 24 with a little breathing room

  -- Prev button
  local prev = CreateFrame("Button", nil, btnContainer)
  prev:SetSize(24, 24)
  prev:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
  prev:SetNormalTexture("Interface/Buttons/UI-SpellbookIcon-PrevPage-Up")
  prev:SetPushedTexture("Interface/Buttons/UI-SpellbookIcon-PrevPage-Down")
  prev:SetDisabledTexture("Interface/Buttons/UI-SpellbookIcon-PrevPage-Disabled")
  prev:SetScript("OnClick", function()
    if (UI.pageIndex or 1) > 1 then
      UI.pageIndex = UI.pageIndex - 1
      UI:Refresh()
    end
  end)
  footer.prev = prev

  -- Next button
  local nextb = CreateFrame("Button", nil, btnContainer)
  nextb:SetSize(24, 24)
  nextb:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
  nextb:SetNormalTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
  nextb:SetPushedTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Down")
  nextb:SetDisabledTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Disabled")
  nextb:SetScript("OnClick", function()
    if (UI.pageIndex or 0) < (UI.totalPages or 0) then
      UI.pageIndex = UI.pageIndex + 1
      UI:Refresh()
    end
  end)
  footer.next = nextb

  -- Safe text area that automatically shrinks if we add more buttons on the right
  local pageArea = CreateFrame("Frame", nil, footer)
  pageArea:SetPoint("LEFT", footer, "LEFT", 0, 0)
  pageArea:SetPoint("RIGHT", btnContainer, "LEFT", -12, 0) -- keep gap from the arrows
  pageArea:SetHeight(24)

  -- Centered "Page X of Y" text
  local pageText = pageArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageText:SetPoint("CENTER", pageArea, "CENTER", 0, 0)
  pageText:SetJustifyH("CENTER")
  pageText:SetText("Page 0 of 0")
  footer.pageText = pageText

  -- List container above the footer
  local list = CreateFrame("Frame", ADDON_NAME.."List", f)
  list:SetPoint("TOPLEFT", 12, -86)
  list:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 6)
  list:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 6)
  self.list = list

  -- Mouse wheel page scrolling (one full page per notch)
  self.list:EnableMouse(true)
  self.list:EnableMouseWheel(true)
  self.list:SetScript("OnMouseWheel", function(_, delta)
    local page = UI.visibleRows or 1
    if ns and ns.Debug then ns:Debug("Wheel", "delta=", delta, "page=", page, "offset=", UI.offset or 0) end
    if delta > 0 then
      UI:ScrollOffsetBy(-page)   -- up = previous page
    else
      UI:ScrollOffsetBy( page )  -- down = next page
    end
  end)
  footer.prev = prev

  -- Next button
  local nextb = CreateFrame("Button", nil, btnContainer)
  nextb:SetSize(24, 24)
  nextb:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
  nextb:SetNormalTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Up")
  nextb:SetPushedTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Down")
  nextb:SetDisabledTexture("Interface/Buttons/UI-SpellbookIcon-NextPage-Disabled")
  nextb:SetScript("OnClick", function()
    if (UI.pageIndex or 0) < (UI.totalPages or 0) then
      UI.pageIndex = UI.pageIndex + 1
      UI:Refresh()
    end
  end)
  footer.next = nextb

  -- Safe text area that automatically shrinks if we add more buttons on the right
  local pageArea = CreateFrame("Frame", nil, footer)
  pageArea:SetPoint("LEFT", footer, "LEFT", 0, 0)
  pageArea:SetPoint("RIGHT", btnContainer, "LEFT", -12, 0) -- keep gap from the arrows
  pageArea:SetHeight(24)

  -- Centered "Page X of Y" text (replaces the old 2/2 location)
  local pageText = pageArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  pageText:SetPoint("CENTER", pageArea, "CENTER", 0, 0)
  pageText:SetJustifyH("CENTER")
  pageText:SetText("Page 0 of 0")
  footer.pageText = pageText

  -- List container above the footer
  local list = CreateFrame("Frame", ADDON_NAME.."List", f)
  list:SetPoint("TOPLEFT", 12, -86)
  list:SetPoint("BOTTOMLEFT", footer, "TOPLEFT", 0, 6)
  list:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 6)
  self.list = list

  -- Disable wheel scrolling (paging only)
  list:EnableMouseWheel(false)
  list:SetScript("OnMouseWheel", nil)

  self.rows = {}
  self.visibleRows = 0
  self.pageIndex = 1
  self.totalLines = 0
  self.totalPages = 0
  self.offset = 0
  self.sortedKeys = {}

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
  self.pageIndex = 1
  self.offset = 0
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

  -- keep sorted keys for wheel scrolling logic
  self.sortedKeys = keys

  local total = #keys
  self.totalLines = total

  -- (Re)compute pages based on search results and visible rows
  RecomputePages(self)

  -- Compute and clamp pageIndex + offset (page-aligned)
  local per = math.max(self.visibleRows or 0, 1)
  if (self.totalPages or 0) == 0 then
    self.pageIndex = 0
    self.offset    = 0
  else
    if not self.pageIndex or self.pageIndex < 1 then self.pageIndex = 1 end
    if self.pageIndex > self.totalPages then self.pageIndex = self.totalPages end
    self.offset = (self.pageIndex - 1) * per
  end

  -- Render current page
  if self.RenderRows then
    self:RenderRows(keys, self.offset)
  end

  -- Update footer UI
  UpdateFooter(self)
end
