-- ModMux: the Switchboard, a page of the ESC menu (same way of adding a page as Player Trading+, checked in game).
-- Six tabs over one list and a details panel. What a tab shows and what its buttons do comes from ModMuxTabs; this
-- file only draws it and passes the buttons on.

ModMuxFrame = {}
local ModMuxFrame_mt = Class(ModMuxFrame, TabbedMenuFrameElement)

ModMuxFrame.PAGE_NAME = "pageModMux"
ModMuxFrame.ICON_FILENAME = "gui/modMux_tabIcon.dds"
ModMuxFrame.ICON_SIZE = 256
ModMuxFrame.UI_FILENAME = "gui/modMux_ui.dds"
ModMuxFrame.UI_SIZE = 64
ModMuxFrame.DETAIL_LINES = 24
ModMuxFrame.DETAIL_CHARS = 60
ModMuxFrame.REFRESH_MS = 500
-- button slots of ModMuxTabs actions -> input actions
ModMuxFrame.SLOT_ACTIONS = {"MENU_ACCEPT", "MENU_EXTRA_1", "MENU_EXTRA_2", "MENU_ACTIVATE", "MENU_CANCEL", "MENU_EXTRA_3"}
ModMuxFrame.COLORS = {
    good = {0.47, 0.70, 0.06, 1},
    warn = {0.91, 0.69, 0.13, 1},
    bad = {0.89, 0.36, 0.30, 1},
    dim = {0.55, 0.55, 0.55, 1},
}

ModMuxFrame.instance = nil

function ModMuxFrame.new()
    local self = ModMuxFrame:superClass().new(nil, ModMuxFrame_mt)
    self.hasCustomMenuButtons = true
    self.ui = {tab = ModMuxTabs.CONFLICTS, view = ModMuxTabs.VIEW_SIMPLE, showDismissed = false}
    self.model = {rows = {}, columns = {}, globalActions = {}}
    self.selectedId = nil
    self.refreshTimer = 0
    self.actionBySlot = {}
    return self
end

----------------------------------------------------------------------------------------------------------------
-- Adding the page to the ESC menu
----------------------------------------------------------------------------------------------------------------

local function moveToPosition(list, item, position, getItem)
    for i = 1, #list do
        if getItem(list[i]) == item then
            local entry = table.remove(list, i)
            table.insert(list, math.min(position, #list + 1), entry)
            return
        end
    end
end

function ModMuxFrame.getUVs(size)
    return GuiUtils.getUVs({0, 0, size, size}, {size, size})
end

function ModMuxFrame.register()
    if ModMuxFrame.instance ~= nil then
        return
    end
    local inGameMenu = g_gui.screenControllers[InGameMenu]
    if inGameMenu == nil or inGameMenu.pagingElement == nil or inGameMenu.registerPage == nil or inGameMenu.addPageTab == nil then
        Logging.warning("%s the ESC menu can't take new pages, the Switchboard is not added (console: modMux)", ModMux.TAG)
        return
    end

    local frame = ModMuxFrame.new()
    g_gui:loadGui(ModMux.MOD_DIR .. "gui/ModMuxFrame.xml", "ModMuxFrame", frame, true)

    local pageName = ModMuxFrame.PAGE_NAME
    inGameMenu.controlIDs[pageName] = nil
    inGameMenu[pageName] = frame
    inGameMenu.pagingElement:addElement(frame)
    inGameMenu:exposeControlsAsFields(pageName)

    -- right after the finances page, or at the end
    local position = #inGameMenu.pagingElement.elements
    for i, element in ipairs(inGameMenu.pagingElement.elements) do
        if element == inGameMenu.pageFinances then
            position = i + 1
            break
        end
    end
    moveToPosition(inGameMenu.pagingElement.elements, frame, position, function(element) return element end)
    moveToPosition(inGameMenu.pagingElement.pages, frame, position, function(page) return page.element end)
    inGameMenu.pagingElement:updateAbsolutePosition()
    inGameMenu.pagingElement:updatePageMapping()

    inGameMenu:registerPage(frame, position, function()
        return true
    end)
    inGameMenu:addPageTab(frame, ModMux.MOD_DIR .. ModMuxFrame.ICON_FILENAME, ModMuxFrame.getUVs(ModMuxFrame.ICON_SIZE))
    if inGameMenu.pageFrames ~= nil then
        moveToPosition(inGameMenu.pageFrames, frame, position, function(element) return element end)
    end
    inGameMenu:rebuildTabList()

    frame:initialize()
    ModMuxFrame.instance = frame
    print(ModMux.TAG .. " Switchboard page added to the ESC menu")
end

function ModMuxFrame.unregister()
    ModMuxFrame.instance = nil
end

----------------------------------------------------------------------------------------------------------------
-- Frame
----------------------------------------------------------------------------------------------------------------

local function setVisible(element, visible)
    if element ~= nil then
        element:setVisible(visible)
    end
end

local function setText(element, text)
    if element ~= nil then
        element:setText(text or "")
    end
end

local function setColor(element, colorName)
    if element == nil or element.setTextColor == nil then
        return
    end
    if element.mmDefaultColor == nil and element.textColor ~= nil then
        element.mmDefaultColor = {unpack(element.textColor)}
    end
    local c = ModMuxFrame.COLORS[colorName] or element.mmDefaultColor
    if c ~= nil then
        element:setTextColor(c[1], c[2], c[3], c[4])
    end
end

--- every element whose name / id starts with "mmImg_" gets our white image (tinted by its profile)
function ModMuxFrame.applyImages(root)
    if root == nil then
        return
    end
    local filename = ModMux.MOD_DIR .. ModMuxFrame.UI_FILENAME
    local uvs = ModMuxFrame.getUVs(ModMuxFrame.UI_SIZE)
    local function walk(element)
        local key = element.name or element.id
        if type(key) == "string" and key:find("^mmImg_") ~= nil and element.setImageFilename ~= nil and not element.mmImage then
            element:setImageFilename(filename)
            if element.setImageUVs ~= nil then
                element:setImageUVs(nil, unpack(uvs))
            end
            element.mmImage = true
        end
        for _, child in ipairs(element.elements or {}) do
            walk(child)
        end
    end
    walk(root)
end

function ModMuxFrame:initialize()
    self.backButtonInfo = {inputAction = InputAction.MENU_BACK}
    self.buttonInfos = {}
    for slot, actionName in ipairs(ModMuxFrame.SLOT_ACTIONS) do
        local frame = self
        self.buttonInfos[slot] = {inputAction = InputAction[actionName], text = "", callback = function()
            frame:onSlotPressed(slot)
        end}
    end
    if self.headerIcon ~= nil then
        self.headerIcon:setImageFilename(ModMux.MOD_DIR .. ModMuxFrame.ICON_FILENAME)
        self.headerIcon:setImageUVs(nil, unpack(ModMuxFrame.getUVs(ModMuxFrame.ICON_SIZE)))
    end
    if self.mainPaging ~= nil then
        local texts = {}
        for _, key in ipairs(ModMuxTabs.TAB_KEYS) do
            table.insert(texts, ModMux.getText(key))
        end
        self.mainPaging:setTexts(texts)
    end
    self:updateButtons()
end

function ModMuxFrame:onGuiSetupFinished()
    ModMuxFrame:superClass().onGuiSetupFinished(self)
    ModMuxFrame.applyImages(self)
    if self.rowList ~= nil then
        self.rowList:setDataSource(self)
        self.rowList:setDelegate(self)
    end
end

function ModMuxFrame:onFrameOpen(element)
    ModMuxFrame:superClass().onFrameOpen(self)
    -- what the probes saw since the last look
    ModMux.guard("evidence", ModMux.checkEvidence)
    self:showTab(self.ui.tab)
end

function ModMuxFrame:onFrameClose()
    ModMuxFrame:superClass().onFrameClose(self)
end

function ModMuxFrame:update(dt)
    ModMuxFrame:superClass().update(self, dt)
    if self.model.live then
        self.refreshTimer = self.refreshTimer + dt
        if self.refreshTimer >= ModMuxFrame.REFRESH_MS then
            self.refreshTimer = 0
            self:rebuild()
        end
    end
end

--- something outside changed (a HUD scan ended): show it if the page is open
function ModMuxFrame:onDataChanged()
    if self:getIsVisible() then
        self:rebuild()
    end
end

function ModMuxFrame:showTab(tab)
    self.ui.tab = tab
    self.selectedId = nil
    for i, button in ipairs(self.mainTabs or {}) do
        button:setSelected(i == tab)
    end
    if self.mainPaging ~= nil then
        self.mainPaging:setState(tab)
    end
    self:rebuild()
    if self.rowList ~= nil then
        FocusManager:setFocus(self.rowList)
    end
end

function ModMuxFrame:selectedRow()
    for _, row in ipairs(self.model.rows) do
        if row.id == self.selectedId then
            return row
        end
    end
    return nil
end

--- builds the model again and redraws, keeping the selected row
function ModMuxFrame:rebuild()
    self.model = ModMuxTabs.build(self.ui)
    local model = self.model
    for i = 1, 4 do
        if self.colHead ~= nil then
            setText(self.colHead[i], model.columns[i])
        end
    end
    setText(self.subHeader, model.subHeader)
    setText(self.footerText, model.footer)
    setColor(self.footerText, model.footerColor)
    setText(self.emptyText, model.emptyText)
    setVisible(self.emptyText, #model.rows == 0)

    local index = nil
    for i, row in ipairs(model.rows) do
        if row.id == self.selectedId then
            index = i
        end
    end
    if index == nil and #model.rows > 0 then
        index = 1
    end
    self.selectedId = index ~= nil and model.rows[index].id or nil
    if self.rowList ~= nil then
        self.rowList:reloadData()
        if index ~= nil and self.rowList.setSelectedItem ~= nil then
            self.rowList:setSelectedItem(1, index, nil, true)
        end
    end
    self:updateDetail()
    self:updateButtons()
end

--- splits a text into lines of at most `width` characters at spaces
function ModMuxFrame.wrap(text, width)
    local lines = {}
    text = tostring(text or "")
    if text == "" then
        return {""}
    end
    local indent = text:match("^(%s*)") or ""
    local line = ""
    for word in text:gmatch("%S+") do
        if line == "" then
            line = indent .. word
        elseif #line + 1 + #word <= width then
            line = line .. " " .. word
        else
            table.insert(lines, line)
            line = indent .. "  " .. word
        end
        while #line > width do
            table.insert(lines, line:sub(1, width))
            line = indent .. "  " .. line:sub(width + 1)
        end
    end
    table.insert(lines, line)
    return lines
end

function ModMuxFrame.detailLines(row, maxLines, width)
    local lines = {}
    for _, text in ipairs(row ~= nil and row.detail or {}) do
        for _, line in ipairs(ModMuxFrame.wrap(text, width)) do
            table.insert(lines, line)
        end
    end
    if #lines > maxLines then
        local cut = {}
        for i = 1, maxLines - 1 do
            cut[i] = lines[i]
        end
        cut[maxLines] = "..."
        lines = cut
    end
    return lines
end

function ModMuxFrame:updateDetail()
    local row = self:selectedRow()
    setText(self.detailTitle, row ~= nil and row.detailTitle or "")
    local lines = ModMuxFrame.detailLines(row, ModMuxFrame.DETAIL_LINES, ModMuxFrame.DETAIL_CHARS)
    for i = 1, ModMuxFrame.DETAIL_LINES do
        if self.detailLine ~= nil then
            setText(self.detailLine[i], lines[i])
        end
    end
end

function ModMuxFrame:updateButtons()
    if self.buttonInfos == nil then
        return
    end
    local buttons = {self.backButtonInfo}
    self.actionBySlot = {}
    for _, entry in ipairs(ModMuxTabs.actionsFor(self.model, self:selectedRow())) do
        local info = self.buttonInfos[entry.slot]
        if info ~= nil and info.inputAction ~= nil then
            info.text = entry.text
            self.actionBySlot[entry.slot] = entry
            table.insert(buttons, info)
        end
    end
    self.menuButtons = buttons
    self:setMenuButtonInfo(buttons)
    self:setMenuButtonInfoDirty()
end

function ModMuxFrame:onSlotPressed(slot)
    local entry = self.actionBySlot[slot]
    if entry == nil then
        return
    end
    self:handleRequest(entry.run())
    self:rebuild()
end

function ModMuxFrame:handleRequest(request)
    if request == nil then
        return
    end
    local frame = self
    if request.confirm ~= nil then
        YesNoDialog.show(function(_, yes)
            if yes then
                request.onYes()
            end
            frame:rebuild()
        end, self, request.confirm)
    elseif request.askText ~= nil then
        if TextInputDialog == nil or TextInputDialog.show == nil then
            request.onText(request.default)
            return
        end
        TextInputDialog.show(function(_, text, clickOk)
            if clickOk then
                request.onText(text)
            end
            frame:rebuild()
        end, self, request.default, request.askText, request.askText, ModMuxProfiles.MAX_NAME, ModMux.getText("mm_button_save"))
    elseif request.info ~= nil then
        InfoDialog.show(request.info)
    end
end

-- SmoothList data source / delegate

function ModMuxFrame:getNumberOfSections()
    return 1
end

function ModMuxFrame:getNumberOfItemsInSection(list, section)
    return #self.model.rows
end

function ModMuxFrame:populateCellForItemInSection(list, section, index, cell)
    local row = self.model.rows[index]
    if row == nil then
        return
    end
    ModMuxFrame.applyImages(cell)
    for i = 1, 4 do
        local element = cell:getAttribute("c" .. i)
        if element ~= nil then
            element:setText(row.cells[i] or "")
            setColor(element, row.colors ~= nil and row.colors[i] or nil)
        end
    end
end

function ModMuxFrame:onListSelectionChanged(list, section, index)
    local row = self.model.rows[index]
    self.selectedId = row ~= nil and row.id or nil
    self:updateDetail()
    self:updateButtons()
end

-- Tabs

function ModMuxFrame:onClickTab1()
    self:showTab(1)
end

function ModMuxFrame:onClickTab2()
    self:showTab(2)
end

function ModMuxFrame:onClickTab3()
    self:showTab(3)
end

function ModMuxFrame:onClickTab4()
    self:showTab(4)
end

function ModMuxFrame:onClickTab5()
    self:showTab(5)
end

function ModMuxFrame:onClickTab6()
    self:showTab(6)
end

function ModMuxFrame:onClickMainPaging(state)
    if state ~= self.ui.tab then
        self:showTab(state)
    end
end
