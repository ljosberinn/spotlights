---@type string, Spotlights
local addonName, Private = ...

---@class SpotlightsOptions
Private.Options = {}

--- The window the layout kit lives in.
---
--- Its shape is what the layout kit needs: a fixed content rectangle handed to one node per tab, rather
--- than a scroll child every widget anchors itself into. Window management -- `UISpecialFrames`, the
--- combat close, the reload offer, lazy tab building -- is separate from that and sits here.

--- 780 leaves 710 right of the portrait for the tab strip, and the layout frame puts a pixel between each
--- pair of tabs: 6 * 117 + 5 * 1 = 707, so six tabs fit with the remainder inside the panel rather than
--- clipping its right edge.
--- The height has no arithmetic behind it, unlike the width: it is simply what fits the tallest tab
--- without cramping it. 610 is where a two-column grid with group headings in it clears the 174px
--- preview pane beside it.
local PANEL_WIDTH = 780
local PANEL_HEIGHT = 610
local MAX_TAB_WIDTH = 117

local CONTENT_INSET = 16

--- Where the tab strip starts relative to the panel's left edge, right of the portrait. The content
--- follows the tab system's bottom and so has to know this to land back at `CONTENT_INSET`.
local TAB_STRIP_X = 70
local TAB_STRIP_Y = -26

--- What every tab lays out against. Two ~350 columns with a 26 gutter, or a 196 rail beside a 536 pane.
local CONTENT_WIDTH = PANEL_WIDTH - CONTENT_INSET * 2

--- Between the tab strip's bottom edge and the content.
local CONTENT_GAP = 8

--- One key for the reload prompt wherever it is offered from: `StaticPopup_Show` reuses the dialog
--- already on screen for a given key, so a second key would stack two identical prompts.
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

--- The tabs in strip order, as the key each one's builder registers under. Parallel to the localised
--- names in `Get` below, which are what the strip shows and cannot double as keys: a builder must not
--- have to be found again under a different string in every locale.
---@type string[]
local TAB_KEYS = {
	"general",
	"appearance",
	"grid",
	"auras",
	"roster",
	"importExport",
}

--- What each tab builds, filled by the tab's own file rather than looked up here: a content issue
--- adds a file and a line, and the shell does not learn six file names to find out.
---
--- A key with nothing behind it falls back to the stub below, which is what keeps every tab openable
--- while the content lands one at a time.
---@type table<string, fun(page: Frame): SpotlightsNode>
Private.Options.Builders = {}

--- Stand-in content. The six content issues replace these builders one tab at a time; until then a tab
--- proves it was built and reused by naming itself.
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
--- **An aura display cannot be restyled, only replaced**, and WoW cannot destroy the one it replaces --
--- so a texture or colour change leaves a container and a button behind on every assigned spotlight, for
--- the session. A reload is the only thing that reclaims them, and the only honest moment to mention it
--- is when the user has finished editing.
---
--- On `OnHide` rather than from `SetShown`, because the panel closes three ways and only one goes through
--- `SetShown`: it is in `UISpecialFrames` so Escape hides it directly, and the `PLAYER_REGEN_DISABLED`
--- handler calls `panel:Hide()`. `OnHide` catches all three, and catching the combat one is deliberate --
--- a fight starting is not a reason to silently drop the offer.
---
--- `Private.Auras` owns the "has anything been abandoned" question rather than this file counting its own
--- writes, because the answer includes rebuilds still inside the debounce window.
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

		-- Both answers acknowledge. Escape routes here too, and a dismissal that left the prompt armed
		-- would re-ask on every subsequent close without anything having changed.
		OnCancel = function()
			Private.Auras.AcknowledgeReload()
		end,
	}

	StaticPopup_Show(AURA_RELOAD_POPUP)
end

--- The aura previews are *not* taken down here, unlike the old panel's `OnHide`. They belong to one tab
--- rather than to the window, so the Auras tab turns them on and off from its own page's `OnShow` and
--- `OnHide` -- which the shell hiding fires anyway, and which a tab switch fires too.
local function OnPanelHidden()
	MaybePromptReload()
end

---@return SpotlightsOptionsFrame
local function Get()
	if panel then
		return panel
	end

	local L = Private.L.Settings

	--- `PortraitFrameTemplate`, what `PlayerSpellsFrame` and the rest of the modern panels are built from:
	--- a `NineSlicePanelTemplate` whose `layoutType` the game resolves itself, so the borders follow
	--- Blizzard's current panel art rather than the build we were written against.
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

	--- The portrait, read from the TOC rather than repeated here, so the panel cannot wear a different
	--- face than the addon list and the compartment already show.
	local icon = C_AddOns.GetAddOnMetadata(addonName, "IconTexture")

	if icon then
		panel:SetPortraitToAsset(icon)
	end

	-- UISpecialFrames closes the panel on Escape, the behaviour every other options frame has.
	table.insert(UISpecialFrames, "SpotlightsOptions")

	panel:SetScript("OnHide", OnPanelHidden)

	-- The tab system owns selection, visibility and keyboard/tooltip behaviour. `TabSystemOwnerMixin` is
	-- mixed in here rather than inherited, because the mixin's `OnLoad` is not run for a frame we create
	-- ourselves.
	Mixin(panel, TabSystemOwnerMixin)
	TabSystemOwnerMixin.OnLoad(panel)

	local tabSystem = Private.Node.TabSystem(panel, "TabSystemTopButtonTemplate", {
		maxTabWidth = MAX_TAB_WIDTH,
	})

	-- Right of the portrait, the way SpellBook clears its own icon, and nudged down from the plain 19: the
	-- *selected* tab is drawn emphasised, with its on-top art reaching above the strip's rectangle, so the
	-- strip has to sit low enough that the emphasis clears the title rather than leaking into it.
	tabSystem:SetPoint("TOPLEFT", panel, "TOPLEFT", TAB_STRIP_X, TAB_STRIP_Y)
	panel:SetTabSystem(tabSystem)

	--- The content rectangle every tab draws into.
	---
	--- Its top follows the tab system's bottom instead of restating the strip's height, so a change to the
	--- tab art cannot leave the content in the wrong place; the bottom and right follow the panel, so the
	--- rectangle is the one place the content's size is decided.
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

			--- Built on first selection rather than at panel creation, and reused afterwards. Deferring is
			--- what lets a dropdown read LibSharedMedia's list at open time, so a media pack that loads
			--- after us is still listed.
			if not tab.root then
				local Build = Private.Options.Builders[TAB_KEYS[i]]

				tab.root = Build and Build(tab.page) or BuildStub(tab.page, tab.name)

				-- The one anchor the kit does not set for itself: a container positions its children and
				-- sizes itself, so the root of a tree has to be told where its page begins.
				tab.root:SetPoint("TOPLEFT", tab.page, "TOPLEFT", 0, 0)
			end

			-- Refresh before laying out, over the whole tree, on every selection rather than only the
			-- first: `Refresh` is what decides whether a node is shown, and a tab left in one state and
			-- returned to in another has stale answers to lay out against.
			tab.root:Refresh()
			LayoutActive()
		end)
	end

	--- How a node that changed its own height -- a section the user collapsed -- asks for a fresh pass
	--- without knowing which panel or which pane owns it.
	Private.Node.SetRelayoutHook(Private.Options.Relayout)

	return panel
end

--- Opens or closes the panel.
---
--- Refuses to open in combat rather than opening masked. A panel whose every control is disabled is worse
--- than no panel: it invites the user to conclude the settings are broken, and there is no way to tell
--- "masked because combat" from "masked because bug" by looking at it.
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

--- Opens the panel on a named tab, whatever it was last showing.
---
--- Selecting and showing in one call rather than two, so a right-click on a closed panel does not show
--- the previously active tab and then switch off it.
---
--- The combat guard is here rather than left to `SetShown` so that a *refused* open leaves the
--- remembered tab alone as well: a right-click that silently changed which tab opens next would be a
--- state change with nothing on screen to explain it.
---
--- `TAB_KEYS` stays the only key-to-index mapping in the addon. A caller names a tab; nothing outside
--- this file learns a tab index.
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

--- Re-lays out the active tab, for a node whose *height* changed while what is shown did not: a collapsed
--- section, a list that gained a row.
---
--- Deliberately not a `Refresh`: this is the relayout hook, and a section calling it has already set its
--- body's visibility. Re-reading every control on the tab from here would also undo an edit in progress.
function Private.Options.Relayout()
	if panel and panel:IsShown() then
		LayoutActive()
	end
end

--- Re-reads the active tab and lays it out again. For a setting changed behind the panel's back -- by a
--- slash command, or by the mover's own combat lock.
---
--- Both halves, always in this order: `Refresh` is what hides a node, and laying out against stale
--- visibility either leaves a hole where a hidden node was or anchors one that is not there.
function Private.Options.Refresh()
	local tab = tabs[activeTab]

	if panel and panel:IsShown() and tab and tab.root then
		tab.root:Refresh()
		LayoutActive()
	end
end

--- The window itself, for the one thing a tab cannot anchor inside its own page: the Auras tab's
--- category strip is a *bottom* tab strip, whose art hangs below the frame it belongs to, so it is
--- anchored to the window's bottom edge rather than to the content rectangle. Anchoring it to the page
--- instead would put the shell's content inset in a tab's arithmetic.
---
--- Everything else a tab needs is handed to its builder. This is not a general seam into the shell.
---@return SpotlightsOptionsFrame
function Private.Options.GetFrame()
	return Get()
end

--- Whether the cursor is anywhere over the panel.
---
--- For the drag path, which has two kinds of drop target -- a slot row in this panel, and a cell on the
--- grid -- and no way to tell them apart by geometry alone. The panel is at DIALOG strata and the grid is
--- not, so a panel over the grid hides it; without this, releasing on a dead part of the panel that
--- overlaps a cell would assign to the cell underneath.
---@return boolean
function Private.Options.IsCursorOver()
	return panel ~= nil and Private.Utils.IsCursorOver(panel)
end

Private.Events.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	-- Before the panel, so the picker is gone whether or not the panel opened it. It is a separate
	-- top-level frame and outlives its opener, so closing only the panel leaves a colour wheel floating
	-- over the fight with nothing behind it.
	ColorPickerFrame:Hide()

	if panel and panel:IsShown() then
		panel:Hide()
		Private.Utils.Print(Private.L.Settings.ClosedByCombat)
	end
end)

Private.SlashCommands.Register("options", "Options", function()
	Private.Options.SetShown()
end)
