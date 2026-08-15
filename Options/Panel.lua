---@type string, Spotlights
local addonName, Private = ...

---@class SpotlightsOptions
Private.Options = {}

--- The window the layout kit lives in: a fixed content rectangle handed to one node per tab, plus the
--- window management -- `UISpecialFrames`, the combat close, the reload offer, lazy tab building.

--- 780 leaves 710 right of the portrait, and the layout frame puts a pixel between each pair of tabs:
--- 6 * 117 + 5 * 1 = 707, so six tabs fit without clipping the panel's right edge. The height is simply
--- what fits the tallest tab.
local PANEL_WIDTH = 780
local PANEL_HEIGHT = 610
local MAX_TAB_WIDTH = 117

local CONTENT_INSET = 16

--- Right of the portrait. The content follows the tab system's bottom and so has to subtract this to land
--- back at `CONTENT_INSET`.
local TAB_STRIP_X = 70
local TAB_STRIP_Y = -26

local CONTENT_WIDTH = PANEL_WIDTH - CONTENT_INSET * 2
local CONTENT_GAP = 8

--- One key wherever the prompt is offered from: `StaticPopup_Show` reuses the dialog already on screen for
--- a given key, so a second key would stack two identical prompts.
local AURA_RELOAD_POPUP = "SPOTLIGHTS_AURA_RELOAD"

---@type SpotlightsOptionsFrame?
local panel

--- One top-level tab: what it is called, and the page and node behind it.
---@class SpotlightsOptionsTab
---@field name string
---@field page Frame the fixed content rectangle this tab draws into
---@field root SpotlightsNode? nil until the tab is first selected

---@type SpotlightsOptionsTab[]
local tabs = {}

local activeTab = 1

--- The tabs in strip order, as the key each one's builder registers under. Parallel to the localised names
--- in `Get`, which cannot double as keys because they differ per locale.
---@type string[]
local TAB_KEYS = {
	"general",
	"appearance",
	"grid",
	"auras",
	"roster",
	"importExport",
}

--- What each tab builds, filled by the tab's own file rather than looked up here, so the shell learns no
--- file names. A key with nothing behind it falls back to the stub below.
---@type table<string, fun(page: Frame): SpotlightsNode>
Private.Options.Builders = {}

--- Stand-in for a tab whose file did not load: it names the tab rather than leaving a blank page.
---@param page Frame
---@param name string
---@return SpotlightsNode
local function BuildStub(page, name)
	return Private.Node.Column(page, { Private.Controls.SubHeading(page, name) })
end

--- Lays the active tab out. Nothing else: the other tabs are hidden, and a hidden node's `Layout` would
--- anchor children against a rectangle the user is not looking at.
local function LayoutActive()
	local tab = tabs[activeTab]

	if tab and tab.root then
		tab.root:Layout(CONTENT_WIDTH)
	end
end

--- Offers a reload if aura frames have been abandoned, and asks at most once per abandonment.
---
--- **An aura display cannot be restyled, only replaced**, and WoW cannot destroy the one it replaces, so a
--- texture or colour change strands a container and a button on every assigned spotlight for the session.
--- A reload is the only thing that reclaims them.
---
--- On `OnHide` rather than from `SetShown`, because the panel also closes via `UISpecialFrames` and via the
--- `PLAYER_REGEN_DISABLED` handler. `Private.Auras` owns the "has anything been abandoned" question,
--- because the answer includes rebuilds still inside the debounce window.
local function MaybePromptReload()
	if not Private.Auras.NeedsReload() then
		return
	end

	local L = Private.L.Settings

	-- Registered at show time rather than at load, so the localisation table is filled by now.
	StaticPopupDialogs[AURA_RELOAD_POPUP] = {
		text = L.ReloadPrompt,
		button1 = L.ReloadNow,
		button2 = L.ReloadLater,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,

		-- Above Blizzard's own dialogs rather than under them, since this can appear as combat starts and
		-- something else may already be on screen.
		preferredIndex = 3,

		OnAccept = function()
			Private.Auras.AcknowledgeReload()
			ReloadUI()
		end,

		-- Both answers acknowledge, Escape included: a dismissal that left the prompt armed would re-ask on
		-- every subsequent close.
		OnCancel = function()
			Private.Auras.AcknowledgeReload()
		end,
	}

	StaticPopup_Show(AURA_RELOAD_POPUP)
end

--- The aura previews are deliberately *not* taken down here: they belong to the Auras tab, which drives
--- them from its own page's `OnShow` and `OnHide`, and the shell hiding fires those anyway.
local function OnPanelHidden()
	MaybePromptReload()
end

---@return SpotlightsOptionsFrame
local function Get()
	if panel then
		return panel
	end

	local L = Private.L.Settings

	--- `PortraitFrameTemplate` resolves its `NineSlicePanelTemplate` `layoutType` itself, so the borders
	--- follow Blizzard's current panel art rather than the build we were written against.
	panel = CreateFrame("Frame", "SpotlightsOptions", UIParent, "PortraitFrameTemplate") --[[@as SpotlightsOptionsFrame]]
	panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	panel:SetPoint("CENTER")
	panel:SetFrameStrata("DIALOG")
	panel:Hide()
	panel:EnableMouse(true)
	panel:SetMovable(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
	panel:SetClampedToScreen(true)

	-- `SetTitle` rather than reaching for the font string: `TitledPanelMixin` keeps it at
	-- `TitleContainer.TitleText`, and depending on where it lives today is how that breaks.
	panel:SetTitle(L.Title)

	--- Read from the TOC rather than repeated here, so the panel cannot wear a different face than the addon
	--- list and the compartment.
	local icon = C_AddOns.GetAddOnMetadata(addonName, "IconTexture")

	if icon then
		panel:SetPortraitToAsset(icon)
	end

	-- UISpecialFrames closes the panel on Escape, the behaviour every other options frame has.
	table.insert(UISpecialFrames, "SpotlightsOptions")

	panel:SetScript("OnHide", OnPanelHidden)

	-- Mixed in rather than inherited, because the mixin's `OnLoad` is not run for a frame we create
	-- ourselves.
	Mixin(panel, TabSystemOwnerMixin)
	TabSystemOwnerMixin.OnLoad(panel)

	local tabSystem = Private.Node.TabSystem(panel, "TabSystemTopButtonTemplate", {
		maxTabWidth = MAX_TAB_WIDTH,
	})

	-- Nudged down from the plain 19 because the selected tab's art reaches above the strip's rectangle and
	-- would otherwise leak into the title.
	tabSystem:SetPoint("TOPLEFT", panel, "TOPLEFT", TAB_STRIP_X, TAB_STRIP_Y)
	panel:SetTabSystem(tabSystem)

	--- The content rectangle every tab draws into. Its top follows the tab system's bottom instead of
	--- restating the strip's height, so a change to the tab art cannot displace the content.
	local contentHost = CreateFrame("Frame", nil, panel)

	contentHost:SetPoint("TOPLEFT", tabSystem, "BOTTOMLEFT", CONTENT_INSET - TAB_STRIP_X, -CONTENT_GAP)
	contentHost:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

	local names = {
		L.TabGeneral,
		L.TabAppearance,
		L.TabGrid,
		L.TabAuras,
		L.TabRoster,
		L.TabImportExport,
	}

	for i = 1, #names do
		local page = CreateFrame("Frame", nil, contentHost)

		page:SetAllPoints(contentHost)

		tabs[i] = {
			name = names[i],
			page = page,
		}

		local tabID = panel:AddNamedTab(names[i], page)

		panel:SetTabCallback(tabID, function()
			activeTab = i

			local tab = tabs[i]

			--- Built on first selection so a dropdown reads LibSharedMedia's list late enough to include a
			--- media pack that loaded after us.
			if not tab.root then
				local Build = Private.Options.Builders[TAB_KEYS[i]]

				tab.root = Build and Build(tab.page) or BuildStub(tab.page, tab.name)

				-- The one anchor the kit does not set for itself: a container positions its children, so
				-- the root has to be told where its page begins.
				tab.root:SetPoint("TOPLEFT", tab.page, "TOPLEFT", 0, 0)
			end

			-- On every selection rather than only the first: a tab left in one state and returned to in
			-- another has stale visibility to lay out against.
			tab.root:Refresh()
			LayoutActive()
		end)
	end

	--- How a node that changed its own height asks for a fresh pass without knowing which pane owns it.
	Private.Node.SetRelayoutHook(Private.Options.Relayout)

	return panel
end

--- Opens or closes the panel. Refuses to open in combat rather than opening masked, which is
--- indistinguishable from broken settings by looking at it.
---@param shown boolean?
function Private.Options.SetShown(shown)
	local frame = Get()

	if shown == nil then
		shown = not frame:IsShown()
	end

	if shown and InCombatLockdown() then
		Private.Utils.Print(Private.L.Settings.CombatRefused)

		return
	end

	frame:SetShown(shown)

	if shown then
		frame:SetTab(activeTab)
	end
end

--- Opens the panel on a named tab, in one call rather than two, so a right-click on a closed panel does not
--- show the previously active tab and then switch off it.
---
--- The combat guard is here rather than left to `SetShown` so that a refused open leaves the remembered tab
--- alone too. `TAB_KEYS` stays the only key-to-index mapping in the addon.
---@param key string
function Private.Options.SelectTab(key)
	if InCombatLockdown() then
		Private.Utils.Print(Private.L.Settings.CombatRefused)

		return
	end

	for i = 1, #TAB_KEYS do
		if TAB_KEYS[i] == key then
			activeTab = i

			break
		end
	end

	Private.Options.SetShown(true)
end

--- Re-lays out the active tab, for a node whose *height* changed while what is shown did not.
---
--- Deliberately not a `Refresh`: a section calling this has already set its body's visibility, and
--- re-reading every control from here would undo an edit in progress.
function Private.Options.Relayout()
	if panel and panel:IsShown() then
		LayoutActive()
	end
end

--- Re-reads the active tab and lays it out again, for a setting changed behind the panel's back -- by a
--- slash command, or by the mover's own combat lock. Both halves, always in this order.
function Private.Options.Refresh()
	local tab = tabs[activeTab]

	if panel and panel:IsShown() and tab and tab.root then
		tab.root:Refresh()
		LayoutActive()
	end
end

--- The window itself, for the one thing a tab cannot anchor inside its own page: the Auras tab's category
--- strip is a *bottom* strip, whose art hangs below the frame it belongs to, so it anchors to the window's
--- bottom edge. Everything else a tab needs is handed to its builder; this is not a general seam.
---@return SpotlightsOptionsFrame
function Private.Options.GetFrame()
	return Get()
end

--- Whether the cursor is anywhere over the panel, so a drag released on a dead part of the panel that
--- overlaps a cell does not assign to the cell underneath.
---
--- Answered from geometry rather than strata, which does not settle it: the panel is at DIALOG, but
--- `position.strata` goes as high as TOOLTIP.
---@return boolean
function Private.Options.IsCursorOver()
	return panel ~= nil and Private.Utils.IsCursorOver(panel)
end

Private.Events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	-- A separate top-level frame that outlives its opener, so closing only the panel would leave a colour
	-- wheel floating over the fight.
	ColorPickerFrame:Hide()

	if panel and panel:IsShown() then
		panel:Hide()
		Private.Utils.Print(Private.L.Settings.ClosedByCombat)
	end
end)

Private.SlashCommands.Register("options", "Options", function()
	Private.Options.SetShown()
end)
