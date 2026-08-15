---@meta

---@class Spotlights
--- Localised strings, grouped by module. Values are strings, except a group may hold an enum-keyed
--- map of strings (the nine anchor points), looked up by value rather than named individually.
---@field L table<string, table<string, string | table<string, string>>>
---@field Enum SpotlightsEnums
---@field Utils SpotlightsUtils
---@field Events SpotlightsEvents
---@field FrameConfig SpotlightsFrameConfig
---@field Container SpotlightsContainer
---@field Mover SpotlightsMover
---@field Preview SpotlightsPreview
---@field AuraPreview SpotlightsAuraPreviews
---@field Media SpotlightsMedia
---@field Node SpotlightsNodeKit
---@field Controls SpotlightsControls
---@field PreviewPane SpotlightsPreviewPane
---@field AuraAppearance SpotlightsAuraAppearance
---@field AuraSpells SpotlightsAuraSpells
---@field AuraTracked SpotlightsAuraTracked
---@field Options SpotlightsOptions
---@field Profile SpotlightsProfile
---@field RosterList SpotlightsRosterList
---@field RosterPresets SpotlightsRosterPresets
---@field ContextMenu SpotlightsContextMenu
---@field DragAssign SpotlightsDragAssign
---@field SlotHeader SpotlightsSlotHeader
---@field Migration SpotlightsMigration
---@field Roster SpotlightsRoster
---@field Registry SpotlightsRegistry
---@field Layout SpotlightsLayout
---@field FillOrder SpotlightsFillOrder
---@field NameStyle SpotlightsNameStyle
---@field Auras SpotlightsAuras
---@field ClickCasts SpotlightsClickCasts
---@field SlashCommands SpotlightsSlashCommands
---@field DB SpotlightsDB? nil until ADDON_LOADED has run the migration

--- The three XML templates in `Blizzard_SharedXML/TabSystemTemplates.xml` the tab strips inherit from.
--- Declared here because the WoW API annotations model Lua mixins but not XML templates, so inheriting
--- from one is otherwise an undefined class.
---@class TabSystemTemplate
---@class TabSystemTopButtonTemplate
---@class TabSystemButtonTemplate

--- A button acquired by `TabSystemTemplate` for a top-oriented tab strip.
---@class TabSystemTopButtonFrame : Button, TabSystemTopButtonTemplate

--- A button acquired by `TabSystemTemplate` for a bottom-oriented tab strip.
---
--- `Text` and `SetTabWidth` come from `TabSystemButtonArtTemplate` and are written out because the
--- category strip pads a tab beyond its label to make room for the enable dot beside it.
---@class TabSystemButtonFrame : Button, TabSystemButtonTemplate
---@field Text FontString
---@field SetTabWidth fun(self: TabSystemButtonFrame, width: number)

--- A Lua-created tab system. The button type is selected through `tabTemplate` before `OnLoad` builds
--- the pool, so the two concrete button frame types above describe the pooled children.
---@class SpotlightsTabSystemFrame : Frame, TabSystemTemplate
---@field tabTemplate string
---@field maxTabWidth number? absent for a strip whose tabs may be as wide as their labels
---@field minTabWidth number? absent for a strip whose tabs may be as narrow as their labels
---@field spacing number? between one tab and the next, read by the layout frame under the mixin
---@field AddTab fun(self: SpotlightsTabSystemFrame, tabText: string): integer
---@field GetTabButton fun(self: SpotlightsTabSystemFrame, tabID: integer): TabSystemButtonFrame
---@field SetTabSelectedCallback fun(self: SpotlightsTabSystemFrame, callback: fun(tabID: integer, isUserAction: boolean?): boolean?)
---@field SetTab fun(self: SpotlightsTabSystemFrame, tabID: integer, isUserAction: boolean?) runs the selection callback
---@field SetTabVisuallySelected fun(self: SpotlightsTabSystemFrame, tabID: integer) paints the selection without running the callback
---@field SetTabShown fun(self: SpotlightsTabSystemFrame, tabID: integer, isShown: boolean) takes the tab out of the strip entirely, the rest closing up over it

--- The reworked options window.
---
--- A `PortraitFrameTemplate` with `TabSystemOwnerMixin` mixed in after the fact, which is how a frame
--- created in Lua acquires the tab methods a template's own `OnLoad` would have installed. Written out
--- here because neither half is visible to `CreateFrame`'s return type.
---@class SpotlightsOptionsFrame : Frame
---@field SetTitle fun(self: SpotlightsOptionsFrame, title: string)
---@field SetPortraitToAsset fun(self: SpotlightsOptionsFrame, asset: string)
---@field SetTabSystem fun(self: SpotlightsOptionsFrame, tabSystem: SpotlightsTabSystemFrame)
---@field AddNamedTab fun(self: SpotlightsOptionsFrame, name: string, ...: Frame): integer
---@field SetTabCallback fun(self: SpotlightsOptionsFrame, tabID: integer, callback: fun())
---@field SetTab fun(self: SpotlightsOptionsFrame, tabID: integer, isUserAction: boolean?)

---@class SpotlightsNameStyle
---@field ApplyLayout fun(fontString: FontString, appearance: SpotlightsAppearanceConfig)
---@field EnsureLayer fun(frame: SpotlightsUnitFrame): Frame
---@field ApplyStrata fun(frame: SpotlightsUnitFrame, appearance: SpotlightsAppearanceConfig)
---@field Request fun()

--- One configured grid cell.
---
--- `guid` is the stable key and `name` is what the header matches on; either can be the only one
--- present (a slot for someone outside the group has no GUID, as nothing resolves a name to one).
--- Both self-heal on the next roster rebuild.
---@class SpotlightsSlot
---@field kind SlotKind
---@field guid string?
---@field name string? exactly as the roster scan spelled it — never synthesised

--- Saved slot layouts, by the name the user gave each one.
---
--- Slots only: a preset is a raid composition, and nothing about how the frames look, where they sit
--- or which auras they track belongs in one. Local to this account and deliberately outside the
--- exported profile -- a preset library is a shelf, not a setting.
---
--- A stored slot carries its `kind` and `name` and never a GUID: the GUID a preset saw belongs to the
--- raid it was saved in, and applying one resolves names against the raid it is applied to.
---@alias SpotlightsPresets table<string, SpotlightsSlot[]>

--- One preset as it travels between clients: the library's key and its value together, because a
--- string leaving this account has no library to be keyed by. The name arrives as a suggestion the
--- importer is shown and may overrule, not as the name it will be stored under.
---@class SpotlightsPresetPayload
---@field name string
---@field slots SpotlightsSlot[]

--- What `C_ClickBindings.GetBindingType` answers, as one of `Enum.ClickBindingType`. Aliased here because
--- the generated API annotations declare the enum's *values* without declaring a type to hold one.
---@alias ClickBindingType integer

--- One Spotlights-only click binding.
---
--- Two projections of the same click are stored because neither derives from the other. `prefix` is what
--- the secure lookup reads, built by `SecureButton_GetModifierPrefix` in the fixed `alt-ctrl-shift-` order;
--- `modifiers` is the client's own bitfield, which has no decoder and is the only thing
--- `C_ClickBindings.GetBindingType` will accept. Both are captured from the same click, so they cannot
--- disagree about which keys were held.
---
--- `button` is the button that was **pressed**, not the suffix the binding ends up on -- see
--- `ClickCasts.lua`.
---@class SpotlightsClickCast
---@field button string a `SecureButton_GetButtonSuffix` button name, e.g. `LeftButton` or `Button4`
---@field prefix string
---@field modifiers number
---@field spellID integer stored as the base ID; a talent override is resolved by `CastSpellByID` itself

---@class SpotlightsDB
---@field version integer
---@field slots SpotlightsSlot[]
---@field presets SpotlightsPresets
---@field clickCasts SpotlightsClickCast[]
---@field layout SpotlightsLayoutConfig
---@field position SpotlightsPositionConfig
---@field appearance SpotlightsAppearanceConfig
---@field auras SpotlightsAurasConfig
---@field minimap SpotlightsMinimapConfig

---@class SpotlightsMinimapConfig
---@field hide boolean

--- How a spotlight looks. Uniform across all of them; no per-slot overrides.
---
--- `barTexture` and `nameFont` are LibSharedMedia **keys**, resolved to a path by `Private.Media` at
--- apply time. Never store the resolved path: a key's path depends on what other addons registered,
--- so a stored path is one session's answer frozen in.
---
--- The health bar and the name each carry a class-colour toggle and a static colour beside it. The
--- static colour is stored whether or not it is in use, so toggling class colour off reveals the
--- user's previous choice. The name also carries its own font, size and
--- placement: `namePoint` is the point on the name *and* the point on the spotlight, with `nameX`/`nameY`
--- the offset between them measured right and up -- the same convention the aura displays use.
---@class SpotlightsAppearanceConfig
---@field barTexture string
---@field showAbsorb boolean
---@field frameAlpha number
---@field outOfRangeAlpha number
---@field deadAlpha number
---@field healthUseClassColor boolean
---@field healthColorR number
---@field healthColorG number
---@field healthColorB number
---@field healthColorA number
---@field healthBgColorR number
---@field healthBgColorG number
---@field healthBgColorB number
---@field healthBgColorA number
---@field nameEnabled boolean
---@field nameHoverOnly boolean
---@field nameStrata FrameStrata | "INHERIT" the strata the name layer takes, or that it takes its parent's
---@field nameUseClassColor boolean
---@field nameColorR number
---@field nameColorG number
---@field nameColorB number
---@field nameColorA number
---@field nameFont string
---@field nameFontSize number
---@field namePoint AnchorPoint
---@field nameX number
---@field nameY number
---@field healthTextEnabled boolean
---@field healthTextFormat HealthTextFormat
---@field healthTextUseClassColor boolean
---@field healthTextColorR number
---@field healthTextColorG number
---@field healthTextColorB number
---@field healthTextColorA number
---@field healthTextFont string
---@field healthTextFontSize number
---@field healthTextPoint AnchorPoint
---@field healthTextX number
---@field healthTextY number

--- Tracked auras. Every feature carries an identical shape on purpose: one customisation set pointed
--- at whichever spells the feature watches, so none may grow a field the others lack.
---
--- The three pool tables sit beside the features rather than inside any one of them, keeping that rule
--- true: a spell pool is a list belonging to the aura block, not to a customisation set -- and the
--- cooldown pool is read by two features, `sensePower` and `cooldownAuras`.
---
--- All three are **sparse**, holding only what the user changed. `cooldowns` overrides the built-in
--- list in `Auras.lua` and is only ever written `false`; a built-in absent from it is on, so adding a
--- spell to that list in a later version needs no migration. `customSpells` is the opposite -- empty
--- until the user adds to it -- mapping each ID to its own toggle.
---@class SpotlightsAurasConfig
---@field prescience SpotlightsAuraFeatureConfig
---@field shiftingSands SpotlightsAuraFeatureConfig
---@field sensePower SpotlightsAuraFeatureConfig
---@field cooldownAuras SpotlightsAuraFeatureConfig
---@field defensiveAuras SpotlightsAuraFeatureConfig
---@field customAuras SpotlightsAuraFeatureConfig
---@field cooldowns table<integer, boolean> built-in overrides; only ever `false`, meaning "off"
---@field defensives table<integer, boolean> defensive overrides; absent means the shipped default
---@field customSpells table<integer, boolean> user-added spell IDs, each mapped to its enabled state

--- One aura's four displays, independent of each other and all optional, under one switch for the
--- feature as a whole.
---
--- `enabled` is the feature-level switch behind the category strip's dot, and it **overrides** every
--- display: a feature switched off renders nothing whatever its bar, icon, square and text say, and its
--- containers stop listening for auras. Off is not the same as switching every display off -- that is
--- four decisions the user has to remember to undo, where this is one, and it leaves the display
--- settings exactly as they were for when the feature comes back.
---@class SpotlightsAuraFeatureConfig
---@field enabled boolean
---@field bar SpotlightsAuraBarConfig
---@field icon SpotlightsAuraIconConfig
---@field square SpotlightsAuraSquareConfig
---@field text SpotlightsAuraTextConfig
---@field frameColor SpotlightsAuraFrameColorConfig

--- What every aura display shares, and the half of it that costs nothing to change.
---
--- These four are the fields that reach a live display through its **anchor frame**, which is ours
--- and unrestricted -- unlike texture, colour and the icon toggles, which live below an
--- access-restricted aura button and can only change by building a replacement. `enabled` looks
--- drastic but is the cheapest: one `SetShown` on a frame we own.
---
--- `point` is the point on the display *and* on the spotlight, so the offset is measured from the
--- same corner of both -- the same convention `SpotlightsPositionConfig` uses against UIParent. `x`
--- and `y` always mean right and up.
--- The border fields are the exception to that split but sit here because all three displays draw one
--- the same way. `borderTexture` is a LibSharedMedia **border** key; `None` (LSM's name for the empty
--- path) means "no border", so there is no separate toggle. All six are build-time: a backdrop belongs
--- to a frame under the aura button.
---@class SpotlightsAuraDisplayConfig
---@field enabled boolean
---@field alpha number
---@field point AnchorPoint
---@field x number
---@field y number
---@field borderTexture string
---@field borderSize number
---@field borderR number
---@field borderG number
---@field borderB number
---@field borderA number
---@field gap number?
---@field growDirection SpotlightsAuraGrowDirection?

--- A duration bar with independent pixel dimensions.
---
--- `texture` is a LibSharedMedia key, resolved by `Private.Media` at apply time -- see
--- `SpotlightsAppearanceConfig.barTexture`.
---
--- `showIcon` puts the spell's icon inline at one end of the bar. Both it and `iconSide` are
--- build-time: they shape regions below the aura button.
---
--- `orientation` is which axis the fill runs along, and `Private.Enum.Orientation` rather than a second
--- enum of its own. Build-time as well: `SetOrientation` is a call on the status bar, which lives below
--- the button, not on the anchor frame above it. `iconSide`'s two values name the two *ends* of the bar
--- whichever axis that is -- `LEFT` is the top end of a vertical one.
---
--- `reverseFill` is which end of that axis the fill is anchored to, and a boolean rather than a second
--- enum for the same reason `iconSide` is not one: it composes with the orientation instead of replacing
--- it, so a reversed horizontal bar hangs off its right end and a reversed vertical one off its top.
--- Build-time, like the axis it qualifies.
---@class SpotlightsAuraBarConfig : SpotlightsAuraDisplayConfig
---@field texture string
---@field r number
---@field g number
---@field b number
---@field width number in pixels
---@field height number in pixels
---@field orientation SpotlightsOrientation
---@field reverseFill boolean
---@field showIcon boolean
---@field iconSide "LEFT" | "RIGHT"

--- A spell icon, optionally with a cooldown swipe and remaining duration across it.
---
--- Width and height are independent pixel dimensions.
---
--- `showSwipe` and `showText` are build-time like the bar's icon fields: they decide which regions
--- exist under the button. `font` is a LibSharedMedia **font** key, resolved at apply time; both it
--- and `fontSize` are build-time, as the font string lives under the aura button.
---@class SpotlightsAuraIconConfig : SpotlightsAuraDisplayConfig
---@field width number in pixels
---@field height number in pixels
---@field showSwipe boolean
---@field showText boolean
---@field font string
---@field fontSize number
---@field gap number in pixels between multiple icons
---@field growDirection SpotlightsAuraGrowDirection which way pooled icons flow from the first

--- A coloured block, optionally with a cooldown swipe and remaining duration across it.
---
--- One `size` rather than a width and a height: a square that can be told to be a rectangle is an icon
--- without the art, and the shape is the whole of what this display is. It also keeps the swipe round,
--- which a non-square Cooldown cannot be.
---
--- `r`/`g`/`b` are the block itself. Build-time like the bar's fill colour, and for the same reason:
--- the texture lives below the aura button. The block carries no spell art at all, so the colour is the
--- only thing that tells two squares apart -- and nothing here identifies *which* aura landed, which is
--- why the display is offered for the single-aura features only.
---
--- `showSwipe`, `showText`, `font` and `fontSize` mean what they mean on an icon, and are build-time for
--- the same reason.
---@class SpotlightsAuraSquareConfig : SpotlightsAuraDisplayConfig
---@field size number in pixels, both ways
---@field r number
---@field g number
---@field b number
---@field showSwipe boolean
---@field showText boolean
---@field font string
---@field fontSize number

--- A bare countdown, with nothing under it.
---
--- No `showText`, because the text *is* the display, and no `showSwipe`, because a swipe with nothing
--- under it is a square. The icon and the square draw a countdown too, but both draw it centred on
--- themselves -- so wanting only the number meant switching on an icon and hiding its art, which the
--- panel does not offer.
---
--- No width and no height either: the anchor's rect is derived from `fontSize` (see the `text` entry in
--- `Auras.lua`'s `DISPLAYS`), because measuring the font string is not an option -- its `Text` is a
--- secret aspect from the moment the display is registered.
---
--- `r`/`g`/`b` are the countdown's colour, and build-time despite being the one thing this display draws:
--- `SetDurationText` adds `VertexColor` to the secret aspects, so the colour has to be written before the
--- font string is handed over and can never be written again. `font` and `fontSize` are build-time for
--- the reason they are on the other two -- the font string lives under the aura button.
---@class SpotlightsAuraTextConfig : SpotlightsAuraDisplayConfig
---@field font string
---@field fontSize number
---@field r number
---@field g number
---@field b number

--- A colour worn by the spotlight's health bar for as long as the aura is up.
---
--- Not a recolour of the bar and cannot be: nothing of ours may be told the aura landed, so the only
--- shape available is a texture parented under the aura button -- which the container shows and hides
--- with the aura -- anchored to the health bar instead of to the button's own rect. See
--- `CreateFrameColor`.
---
--- `r`/`g`/`b` are build-time for the bar's and the square's reason: `SetColorTexture` is a call on a
--- texture below the aura button. `alpha` is the anchor's and stays live, which makes the tint's strength
--- the one setting on this display that can be dragged against a live raid.
---
--- **`point`, `x`, `y` and the six border fields are inherited and mean nothing here.** This display's
--- rect is the health bar's, not an offset from the frame, and there is no edge to draw. They are stored
--- and defaulted because `SetSetting` refuses a write to a field the block lacks, and the panel offers
--- no control for any of them.
---@class SpotlightsAuraFrameColorConfig : SpotlightsAuraDisplayConfig
---@field r number
---@field g number
---@field b number

--- Where the grid sits, how big it is drawn and what it stacks against. A corner-relative anchor,
--- never raw coordinates.
---
--- `point` is the frame point on the container *and* the point on UIParent it anchors to, so the
--- offset is measured from the same corner of both -- which survives a resolution change. `x` and
--- `y` always mean right and up, and are in the **container's own units**: at scale 1 those are
--- UIParent units, and at any other scale a stored offset is what the grid moves by at that scale,
--- so scaling reads as the whole grid growing about its anchor rather than sliding across the
--- screen.
---
--- `scale` and `strata` both reach the spotlights through inheritance: every slot header is a child
--- of the container and every spotlight a child of a header, and none of them sets a scale or a
--- strata of its own.
---@class SpotlightsPositionConfig
---@field point AnchorPoint
---@field x number
---@field y number
---@field scale number
---@field strata FrameStrata

--- The nine points CalcPoint can produce. A subset of WoW's anchor points: the four corners,
--- the four edge midpoints, and the centre.
---@alias AnchorPoint
---| "TOPLEFT"
---| "TOP"
---| "TOPRIGHT"
---| "LEFT"
---| "CENTER"
---| "RIGHT"
---| "BOTTOMLEFT"
---| "BOTTOM"
---| "BOTTOMRIGHT"

--- The grid. `stride` is the user's single wrap control: *columns* when filling horizontally,
--- *rows* when filling vertically, which is why it is named neither.
---
--- `allowGaps` governs both departure holes and user-placed spacers: on, slot i is grid cell i
--- forever and nothing moves except by user edit; off, cells are filled by present players in slot
--- order and spacers collapse with them.
---@class SpotlightsLayoutConfig
---@field orientation SpotlightsOrientation
---@field stride integer
---@field growX GrowX
---@field growY GrowY
---@field spacingX number
---@field spacingY number
---@field frameWidth number
---@field frameHeight number
---@field allowGaps boolean
---@field clearOnLeave boolean wipe every configured slot when the kind of group changes
---@field unrosteredRoles table<string, boolean> which roles the Unrostered list offers, keyed by the tokens `UnitGroupRolesAssigned` answers with. A display filter on that list only: nothing here decides who may be spotlighted
---@field autoRemoveRoles table<string, boolean> which roles are kept out of the grid, keyed the same way. Destructive, unlike `unrosteredRoles`: a slot whose player plays one of these is taken out and stays out

--- A header's child button. Every region is declared by our template and every method is the
--- mixin's; nothing here comes from Blizzard but SecureUnitButtonTemplate's OnClick.
---
--- `unit` and `displayedUnit` are mirrored from the header's secure assignment and only ever read
--- from the attribute -- never written back.
---@class SpotlightsUnitFrame : Button
---@field unit string?
---@field displayedUnit string?
---@field spotlightsInitialised boolean?
---@field background Texture
---@field name FontString
---@field healthText FontString
---@field selectionHighlight Texture
---@field healthBar StatusBar
---@field tempMaxHealthLoss StatusBar
---@field spotlightsAbsorbBar StatusBar?
---@field spotlightsNameLayer Frame? the frame the name is drawn in, so `nameStrata` has something to raise
---@field spotlightsHovered boolean? ours, from the hooked OnEnter/OnLeave — never a secret
---@field spotlightsAuras table<string, table<string, SpotlightsAuraDisplay>>? feature key -> display key -> display, built lazily
---@field spotlightsClickCasts table<string, string>? the click-cast attributes this child currently holds, so a removed binding can be cleared from the name it actually took
---@field OnEvent fun(self: SpotlightsUnitFrame, event: string)
---@field OnUnitAttributeChanged fun(self: SpotlightsUnitFrame, value: string?)
---@field UpdateAll fun(self: SpotlightsUnitFrame)
---@field UpdateHealthValues fun(self: SpotlightsUnitFrame)
---@field UpdateHealthColor fun(self: SpotlightsUnitFrame)
---@field UpdateName fun(self: SpotlightsUnitFrame)
---@field UpdateNameStyle fun(self: SpotlightsUnitFrame)
---@field UpdateNameVisibility fun(self: SpotlightsUnitFrame)
---@field UpdateHealthText fun(self: SpotlightsUnitFrame)
---@field UpdateTexture fun(self: SpotlightsUnitFrame)
---@field UpdateSelectionHighlight fun(self: SpotlightsUnitFrame)
---@field UpdateAbsorb fun(self: SpotlightsUnitFrame)
---@field UpdateTempMaxHealthLoss fun(self: SpotlightsUnitFrame)
---@field UpdateRangeAlpha fun(self: SpotlightsUnitFrame)
---@field CreateAbsorbBar fun(self: SpotlightsUnitFrame)
---@field RegisterGlobalEvents fun(self: SpotlightsUnitFrame)

--- The addon-callable surface of `CustomAuraContainerTemplate`, and only the part we use.
---
--- Declared here because the container is a **real API, not a frame to draw into**. Its mixins are
--- sourced `secure` and split across public and forbidden partitions, so the callable list is narrow.
--- `AddAuraSlot` has no inverse: there is no `UnregisterAuraSlot` and a slot key cannot be reused,
--- so a slot added to a container is there for the session.
---
--- `SetAuraSlotCandidateFilters` is the exception, and why the spell pool can be edited at all: a
--- slot's *identity* is fixed for the session, but its accept filters are not. It clears the slot's
--- candidates, revalidates the given table and re-runs the container's aura pass, so the display
--- catches up without a frame being built.
---@class SpotlightsAuraContainer : Frame
---@field GetUnit fun(self: SpotlightsAuraContainer): string
---@field SetUnit fun(self: SpotlightsAuraContainer, unit: string) asserts on a non-string
---@field AddAuraGroup fun(self: SpotlightsAuraContainer, groupKey: string, filterString: string, options: table)
---@field AddAuraSlot fun(self: SpotlightsAuraContainer, slotKey: string, filterString: string, options: table): table
---@field SetAuraGroupCandidateFilters fun(self: SpotlightsAuraContainer, groupKey: string, candidateFilters: table)
---@field SetAuraGroupMaxFrameCount fun(self: SpotlightsAuraContainer, groupKey: string, maxFrameCount: number)
---@field SetAuraGroupLayout fun(self: SpotlightsAuraContainer, groupKey: string, layoutOptions: table)
---@field SetAuraSlotCandidateFilters fun(self: SpotlightsAuraContainer, slotKey: string, candidateFilters: table) asserts on an unknown slot key
---@field SetFlowLayoutAxis fun(self: SpotlightsAuraContainer, layoutAxis: number) asserts on a value outside AnchorUtil.FlowLayoutAxis
---@field SetFlowLayoutAnchorPoint fun(self: SpotlightsAuraContainer, anchorPoint: AnchorPoint)
---@field SetFlowLayoutGrowthDirection fun(self: SpotlightsAuraContainer, horizontal: number, vertical: number) asserts on values outside AnchorUtil.FlowDirection

--- One grow direction spelled out for both paths that place pooled icons: the container's flow layout,
--- and the preview's item-to-item chain. See `GROW_LAYOUTS` in `Auras.lua`.
---@class SpotlightsAuraGrowLayout
---@field axis number an AnchorUtil.FlowLayoutAxis value
---@field anchorPoint AnchorPoint the container corner every element is anchored to
---@field horizontal number an AnchorUtil.FlowDirection value
---@field vertical number an AnchorUtil.FlowDirection value
---@field chainPoint AnchorPoint
---@field chainRelativePoint AnchorPoint
---@field chainX number the sign the gap carries horizontally
---@field chainY number the sign the gap carries vertically

--- The drawable parts of one display, whichever kind it is.
---
--- Every field is optional and most are absent on any given display: a bar has no swipe and an icon
--- has no status bar, and within a kind the optional regions exist only when the settings asked for
--- them -- except on a preview, which builds all of its own so a toggle can flick without a rebuild.
---
--- One flat shape rather than one per kind, because the three functions that touch it (`Style`,
--- `Register`, `Preview`) are dispatched per kind anyway. `text` is the exception to "optional": it is
--- the whole of what the text display draws, so there it is never absent.
---@class SpotlightsAuraRegions
---@field bar StatusBar?
---@field barTrack Texture? the unfilled remainder behind a **preview** bar, so its rect is visible
---@field barIcon Texture? the spell icon inline at one end of a bar
---@field icon Texture?
---@field block Texture? the coloured square, which is the whole of what that display draws
---@field tint Texture? the health bar's colour while the aura is up; anchored outside its own display's rect
---@field swipe Cooldown?
---@field text FontString?
---@field border SpotlightsAuraBorder?

--- A `Frame` inheriting `BackdropTemplate`, which the annotations model as two unrelated types
--- rather than as a frame that gained two methods. Declared here so a border can be both hidden and
--- given a backdrop without a cast at every call.
---@class SpotlightsAuraBorder : Frame
---@field SetBackdrop fun(self: SpotlightsAuraBorder, backdrop: table)
---@field SetBackdropBorderColor fun(self: SpotlightsAuraBorder, r: number, g: number, b: number, a: number?)

--- One fake display in the options preview: same anchor and regions as a live one, with nothing
--- registered and nothing restricted.
---
--- Carries its own `feature` and `display` because a preview is restyled from settings on every
--- control change, and the record is the only thing that knows which settings are its own.
---
--- `slotIndex` is its place in a pooled feature's row, and `spellID` the spell it currently shows --
--- which the pool moves under it, so the art is repainted whenever the two disagree. A feature tracking
--- one spell has one item at index 1, and its spell never changes.
---@class SpotlightsAuraPreview
---@field anchor Frame
---@field regions SpotlightsAuraRegions
---@field feature SpotlightsAuraFeature
---@field display SpotlightsAuraKind
---@field slotIndex integer
---@field spellID integer? the spell its art was last painted for, `nil` until first styled

--- One built display: a bar, an icon, a square or a bare countdown, for one aura, on one spotlight.
---
--- Three frames stacked in a line, drawn by where the **access boundary** falls.
--- `AuraContainerUtil.ApplyAccessRestrictions` stamps `DenyTaintedAccessWhenAurasAreSecret` onto the
--- button the instant `initializeFrame` returns, and that restriction reaches every descendant --
--- not just the regions handed back through `SetDurationBar`, but plain frames of ours the container
--- never saw. So `button` and everything under it is frozen for the session; there is no way to take
--- a slot back off a container and add a better one.
---
--- `anchor` gives every display something above that boundary to hold onto. It is a plain frame of
--- ours, so its point, size, alpha and visibility stay writable forever -- which turns most settings
--- into a live write instead of a rebuild. One anchor per display, not per spotlight, because two
--- displays that move independently need independent rectangles.
---
--- `container` is the only piece both ours to create and load-bearing for the aura API. It is pinned
--- to the anchor by opposing corners, beating the `SetSize(1, 1)` its own flow layout would collapse
--- it to.
---
--- `button` is listed only so a diagnostic can name it. Every widget call on it from our tainted
--- code is refused while auras are secret -- including `HasAnyAccessRestrictions`.
--- `builtWidth` and `builtHeight` are the anchor's rect when the button was built. A bar's inline icon
--- is square and a region cannot be told to be as wide as it is tall, so one of the two was measured
--- then -- the height for a horizontal bar, the width for a vertical one; comparing that axis against
--- the live one tells a resize whether it invalidated that square.
--- `unresolved` is the set of media keys (namespaced by type) LibSharedMedia could not resolve when
--- the button was built, so the display wears a fallback for each. It lets a late registration
--- rebuild only the displays it actually fixes: matching the *stored* key would instead rebuild
--- displays built after the registration -- which were already right -- at the cost of a leaked
--- container and a reload prompt for no visible change.
---@class SpotlightsAuraDisplay
---@field anchor Frame ours, unrestricted, and the only thing a settings change can reach
---@field container SpotlightsAuraContainer
---@field builtWidth number
---@field builtHeight number
---@field unresolved table<string, true>

---@class SpotlightsSlashCommand
---@field name string
---@field descriptionKey string key into L.SlashCommands, resolved lazily at print time
---@field handler fun(args: string)

--- Globals the addon reaches for that the API annotations do not declare, typed so every use site is
--- checked instead of resolving to `unknown`. The set mirrors `Lua.diagnostics.globals` in
--- `.vscode/settings.json`, so a name added to one belongs in the other.
---
--- Every declaration assigns `nil`: this is a meta file, the annotation above each name *is* the
--- declaration, and an empty table would be reported as a class missing its fields.

-- Saved variables

---@type table? absent on a fresh install, and otherwise whatever shape the installed version last wrote
SpotlightsSaved = nil

-- Global strings

---@type string
ACCEPT = ""

---@type string
CANCEL = ""

---@type string
CLICK_BINDING_OPEN_MENU = ""

---@type string
CLICK_BINDING_TARGET_UNIT = ""

---@type string
CLICK_BINDINGS_BINDING_TEXT_FORMAT = ""

---@type string
DAMAGER = ""

---@type string
HEALER = ""

---@type string
LEFT_BUTTON_STRING = ""

---@type string
MIDDLE_BUTTON_STRING = ""

---@type string
NONE = ""

---@type string
OKAY = ""

---@type string
QUESTION_MARK_ICON = ""

---@type string
RIGHT_BUTTON_STRING = ""

---@type string
SEARCH = ""

---@type string
TANK = ""

---@type string
UNKNOWN = ""

-- Colours

---@type colorRGBA
BLACK_FONT_COLOR = nil

---@type colorRGBA
HIGHLIGHT_FONT_COLOR = nil

---@type colorRGBA
NORMAL_FONT_COLOR = nil

--- Keyed by class filename (`WARRIOR`), not by localised class name.
---@type table<string, colorRGBA>
RAID_CLASS_COLORS = nil

-- Constant tables

--- Keyed by the dialog name passed to `StaticPopup_Show`; the value is a dialog definition.
---@type table<string, table>
StaticPopupDialogs = nil

--- Frame *names*, not frames: a name in this list closes on Escape.
---@type string[]
UISpecialFrames = nil

--- Keyed by the uppercase command token; the handler takes the rest of the line.
---@type table<string, fun(args: string, editBox: EditBox)>
SlashCmdList = nil

---@class AuraContainerSortDirection
---@field Normal number
---@field Reverse number

---@type AuraContainerSortDirection
AuraContainerSortDirection = nil

---@class AuraContainerSortMethod
---@field Default number
---@field BigDefensive number
---@field UnitFrameDebuff number
---@field ImportantOnly number
---@field Expiration number
---@field ExpirationOnly number
---@field Name number
---@field NameOnly number
---@field AuraInstanceIDOnly number

---@type AuraContainerSortMethod
AuraContainerSortMethod = nil

---@class TextureKitConstants
---@field SetVisibility boolean
---@field DoNotSetVisibility boolean
---@field UseAtlasSize boolean
---@field IgnoreAtlasSize boolean
---@field AddressModeClamp number
---@field AddressModeWrap number
---@field AddressModeAllowAssetToDetermine number

---@type TextureKitConstants
TextureKitConstants = nil

-- Frames the default UI creates

---@class AddonCompartmentFrame : Frame
---@field RegisterAddon fun(self: AddonCompartmentFrame, addonData: table)

---@type AddonCompartmentFrame
AddonCompartmentFrame = nil

---@class ChatFrame : Frame
---@field AddMessage fun(self: ChatFrame, text: string, r: number?, g: number?, b: number?, messageID: number?)

---@type ChatFrame
DEFAULT_CHAT_FRAME = nil

---@class ColorPickerFrame : Frame
---@field SetupColorPickerAndShow fun(self: ColorPickerFrame, info: table)
---@field GetColorRGB fun(self: ColorPickerFrame): number, number, number
---@field GetColorAlpha fun(self: ColorPickerFrame): number

---@type ColorPickerFrame
ColorPickerFrame = nil

-- Namespaces and mixins, carrying the members the addon uses

---@class AnchorUtilFlowDirection
---@field Left number
---@field Right number
---@field Up number
---@field Down number

---@class AnchorUtilFlowLayoutAxis
---@field Horizontal number
---@field Vertical number

---@class AnchorUtil
---@field FlowDirection AnchorUtilFlowDirection
---@field FlowLayoutAxis AnchorUtilFlowLayoutAxis

---@type AnchorUtil
AnchorUtil = nil

---@class CVarCallbackRegistry : CallbackRegistryMixin
---@field GetCVarValue fun(self: CVarCallbackRegistry, cvar: string): string
---@field GetCVarValueBool fun(self: CVarCallbackRegistry, cvar: string): boolean
---@field GetCVarNumberOrDefault fun(self: CVarCallbackRegistry, cvar: string): number
---@field SetCVarCachable fun(self: CVarCallbackRegistry, cvar: string)

---@type CVarCallbackRegistry
CVarCallbackRegistry = nil

---@class EventUtil
---@field ContinueOnAddOnLoaded fun(addOnName: string, callback: fun())

---@type EventUtil
EventUtil = nil

---@class Menu
---@field ModifyMenu fun(tag: string, callback: fun(owner: any, rootDescription: table, contextData: table?))

---@type Menu
Menu = nil

---@class MinimalSliderWithSteppersMixinEvent
---@field OnValueChanged string

---@class MinimalSliderWithSteppersMixinLabel
---@field Left number
---@field Right number
---@field Top number
---@field Min number
---@field Max number

---@class MinimalSliderWithSteppersMixin
---@field Event MinimalSliderWithSteppersMixinEvent
---@field Label MinimalSliderWithSteppersMixinLabel

---@type MinimalSliderWithSteppersMixin
MinimalSliderWithSteppersMixin = nil

--- `minPixels` defaults to 1 on all four: the point of these over the frame methods is that a value is
--- snapped to a whole physical pixel rather than to a UI unit.
---@class PixelUtil
---@field SetPoint fun(region: Region, point: AnchorPoint, relativeTo: Region, relativePoint: AnchorPoint, offsetX: number?, offsetY: number?, minOffsetXPixels: number?, minOffsetYPixels: number?)
---@field SetSize fun(region: Region, width: number, height: number, minWidthPixels: number?, minHeightPixels: number?)
---@field SetWidth fun(region: Region, width: number, minPixels: number?)
---@field SetHeight fun(region: Region, height: number, minPixels: number?)

---@type PixelUtil
PixelUtil = nil

---@class PlayerUtil
---@field GetCurrentSpecID fun(): integer?

---@type PlayerUtil
PlayerUtil = nil

---@class ScrollUtil
---@field InitScrollFrameWithScrollBar fun(scrollFrame: ScrollFrame, scrollBar: Frame)

---@type ScrollUtil
ScrollUtil = nil

--- Mixed into a Lua-created frame, whose `OnLoad` then builds the tab pool -- see `SpotlightsTabSystemFrame`.
---@class TabSystemMixin
---@field OnLoad fun(self: SpotlightsTabSystemFrame)

---@type TabSystemMixin
TabSystemMixin = nil

---@class TabSystemOwnerMixin
---@field OnLoad fun(self: SpotlightsOptionsFrame)

---@type TabSystemOwnerMixin
TabSystemOwnerMixin = nil

-- Functions

---@type fun(value: number, min: number, max: number): number
Clamp = nil

--- Aliases `CreateSecureFramePool`.
---@type fun(frameType: string, parent: Frame?, template: string?, resetFunc: fun(pool: table, frame: Frame)?, forbidden: boolean?, postCreate: fun(frame: Frame)?, capacity: number?): table
CreateFramePool = nil

--- Takes no arguments, so it can be handed to `OnLeave` directly.
---@type fun()
GameTooltip_Hide = nil

---@type fun(tooltip: GameTooltip, text: string, overrideColor: colorRGBA?, wrap: boolean?)
GameTooltip_SetTitle = nil

---@type fun(modifiers: number): string
GetStringFromModifiers = nil

--- Safe on any value, and the only legal way to ask whether one is secret.
---@type fun(value: any): boolean
issecretvalue = nil

---@type fun(major: string, silent: boolean?): any, number?
LibStub = nil

--- The held modifiers as the client's own bitfield, which is what `C_ClickBindings` accepts.
---@type fun(): number
MakeModifiers = nil

--- Errors under lockdown -- see `SecureHandlers.lua`.
---@type fun(frame: Frame, state: string, values: string)
RegisterStateDriver = nil

---@type fun()
ReloadUI = nil

--- Answers the suffix a click binding takes, which is not always the button that was pressed.
---@type fun(button: string): string
SecureButton_GetButtonSuffix = nil

--- The held modifiers in the fixed `alt-ctrl-shift-` order the secure lookup expects.
---@type fun(frame: Frame?): string
SecureButton_GetModifierPrefix = nil

--- The texture has to exist before this can point it at an atlas.
---@type fun(region: Texture, asset: string, autoSize: boolean?, addressModeU: number?, addressModeV: number?)
SetTextureWithAddressModeOptions = nil

--- Reuses the dialog already on screen for the same `which` rather than stacking a second one.
---@type fun(which: string, text_arg1: any?, text_arg2: any?, data: any?, insertedFrame: Frame?, customOnHideScript: fun()?): Frame?
StaticPopup_Show = nil

--- An `EditBoxOnTextChanged` handler that keeps the accept button disabled while the box is empty.
---@type fun(editBox: EditBox)
StaticPopup_StandardNonEmptyTextHandler = nil

--- Wired by the unit frame template's `OnEnter`, which is what puts the unit in the tooltip. Referenced
--- from XML only, so the LSP never sees a call site.
---@type fun(self: Button)
UnitFrame_OnEnter = nil

--- The `OnLeave` half of the pair above, likewise XML-only.
---@type fun(self: Button)
UnitFrame_OnLeave = nil

--- The result is secret whenever the curve is, so nothing may branch on it.
---@type fun(unit: string, usePredicted: boolean?, curve: any?): any
UnitHealthPercent = nil
