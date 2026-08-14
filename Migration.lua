---@type string, Spotlights
local _, Private = ...

---@class SpotlightsMigration
Private.Migration = {}

--- Bump this and add the matching step whenever the shape of SpotlightsSaved changes.
Private.Migration.CurrentVersion = 4

--- The layout defaults.
---
--- A function rather than a shared table: handing the same table to two callers would alias one
--- user's settings onto another's.
---@return SpotlightsLayoutConfig
local function DefaultLayout()
	return {
		orientation = Private.Enum.Orientation.Vertical,
		stride = 5,
		growX = Private.Enum.GrowX.Right,
		growY = Private.Enum.GrowY.Down,
		spacingX = 2,
		spacingY = 2,
		frameWidth = 100,
		frameHeight = 50,

		-- On by default: it never moves a frame out from under a click. Compaction is the opt-in.
		allowGaps = true,

		-- Off by default: the alternative is quietly destroying a grid the user built. Stored with
		-- layout (like `allowGaps`) because it is a grid behaviour the Roster tab surfaces.
		clearOnLeave = false,

		-- Damage alone, because those are the players anyone spotlights: a full raid's tanks and healers
		-- are twenty rows scrolled past on the way to them.
		--
		-- `NONE` on by default, so a group that never ran a role check lists as it always did -- the
		-- difference is that the reason is now on screen and switchable.
		--
		-- All four keys are written, and a deselected role is stored `false` rather than removed. `Filled`
		-- recurses into a table default and fills whatever the stored one lacks, so a hole here would be
		-- read as "missing" and come back at the default -- turning Damage back on every load for the user
		-- who switched it off. It is also what carries `NONE` into a database written before it existed.
		unrosteredRoles = {
			TANK = false,
			HEALER = false,
			DAMAGER = true,
			NONE = true,
		},

		-- Every role off, on the grounds `clearOnLeave` ships off: this one discards slots the user
		-- arranged, and a default that threw any of them away would be a setting nobody asked for.
		--
		-- Every key written, as above, so the shape matches what the panel writes back. No `NONE` here:
		-- declining to list someone is not a reason to take the slot they hold out of the grid.
		autoRemoveRoles = {
			TANK = false,
			HEALER = false,
			DAMAGER = false,
		},
	}
end

--- Where the grid sits, as a **corner-relative point plus an offset** rather than raw coordinates.
---
--- The point is picked from which region of the screen the grid was dropped in, and the offset is
--- measured from that corner, so a position stays in the same *region* across resolutions instead of
--- drifting toward the middle.
---
--- `CENTER` is the default and the one point where both offsets are measured from the screen centre.
---
--- `scale` and `strata` were added later and ship at what the grid already did: unscaled, and the
--- `LOW` the unit frame template used to declare for itself.
---@return SpotlightsPositionConfig
local function DefaultPosition()
	return {
		point = "CENTER",
		x = 0,
		y = 0,
		scale = 1,
		strata = "LOW",
	}
end

--- How a spotlight looks.
---
--- `barTexture` is a LibSharedMedia **key**, never a resolved path: the path a key maps to depends
--- on which addons are loaded, so storing the path breaks when a media pack is removed. Resolution
--- happens at apply time, in `Private.Media`.
---
--- The colour and name fields arrived after the block did, reproducing the hardcoded look that
--- preceded them. Static
--- colours are stored even while class colour is on, so switching it off reveals a chosen colour
--- rather than a blank one. `healthBgColor` is the background shown through unfilled health, used only
--- in static mode; its default is the static bar colour at a fifth (what class mode derives).
---
--- `nameEnabled`, `nameHoverOnly` and `nameStrata` need no version step: every one of them ships at
--- what a database written before them already behaved as, so `Repair` filling them in changes nothing
--- about how an existing profile renders.
---@return SpotlightsAppearanceConfig
local function DefaultAppearance()
	return {
		barTexture = "Blizzard Raid Bar",
		showAbsorb = false,
		frameAlpha = 1,
		outOfRangeAlpha = 0.45,
		deadAlpha = 0.45,
		healthUseClassColor = true,
		healthColorR = 0.1,
		healthColorG = 0.7,
		healthColorB = 0.1,
		healthColorA = 1,
		healthBgColorR = 0.02,
		healthBgColorG = 0.14,
		healthBgColorB = 0.02,
		healthBgColorA = 1,
		nameEnabled = true,
		nameHoverOnly = false,

		--- Not a strata but the absence of one: the name layer sets none of its own and inherits the
		--- container's, which is how every spotlight has always drawn. Anything else would restack an
		--- existing profile the first time it loaded a build that had this field.
		nameStrata = Private.Enum.NameStrataInherit,

		nameUseClassColor = false,
		nameColorR = 1,
		nameColorG = 1,
		nameColorB = 1,
		nameColorA = 1,
		nameFont = "Friz Quadrata TT",
		nameFontSize = 10,
		namePoint = "TOPLEFT",
		nameX = 3,
		nameY = -3,
		healthTextEnabled = false,
		healthTextFormat = "percent",
		healthTextUseClassColor = false,
		healthTextColorR = 0.5,
		healthTextColorG = 0.5,
		healthTextColorB = 0.5,
		healthTextColorA = 1,
		healthTextFont = "Friz Quadrata TT",
		healthTextFontSize = 10,
		healthTextPoint = "CENTER",
		healthTextX = 0,
		healthTextY = 0,
	}
end

--- Exposed so the options panel's per-section reset buttons can write these defaults back. Same
--- fresh-per-call tables the migration and repair use, so a reset cannot alias one build's defaults
--- onto another's.
Private.Migration.DefaultLayout = DefaultLayout
Private.Migration.DefaultAppearance = DefaultAppearance

--- LibSharedMedia's own name for the empty border, and therefore how "no border" is spelled.
---
--- A media key rather than a separate on/off setting, because LSM registers `None` as an empty path
--- and every border dropdown already offers it.
local BORDER_NONE = "None"

--- One aura display drawn as a duration bar.
---
--- The parameters are exactly the fields the feature defaults disagree on; everything else about a bar is
--- the same for both.
---
--- The defaults reproduce the adjacent Prescience addon for the default 100x50 frame: 100px wide by
--- 25px high, pinned to the top left, gold at half alpha. The fixed height keeps the bar off the
--- player's name.
---
--- Width and height are independent pixel dimensions, like the icon display.
---
--- `texture` is a LibSharedMedia key like `appearance.barTexture`. `Solid` is LSM's name for
--- `Interface\Buttons\WHITE8X8`, which is what Prescience draws.
---@param enabled boolean
---@param point AnchorPoint
---@param r number
---@param g number
---@param b number
---@param y number the vertical offset from the anchor, so a feature can nudge its bar off the frame edge
---@return SpotlightsAuraBarConfig
local function DefaultAuraBar(enabled, point, r, g, b, y)
	return {
		enabled = enabled,
		texture = "Solid",
		r = r,
		g = g,
		b = b,
		alpha = 0.5,
		width = 100,
		height = 25,
		point = point,
		x = 0,
		y = y,

		-- Horizontal, which needs no version step for the reason `enabled` and the square block do not:
		-- it is what every bar written before this field already drew, so `Repair` filling it in changes
		-- nothing about how an existing profile renders.
		orientation = Private.Enum.Orientation.Horizontal,

		showIcon = false,
		iconSide = "LEFT",
		borderTexture = BORDER_NONE,
		borderSize = 12,
		borderR = 0,
		borderG = 0,
		borderB = 0,
		borderA = 1,
	}
end

--- One aura display drawn as a spell icon.
---
--- Width and height are independent pixel dimensions, so icons can match non-square frame layouts.
---@param enabled boolean
---@param width number
---@param height number
---@return SpotlightsAuraIconConfig
local function DefaultAuraIcon(enabled, width, height)
	return {
		enabled = enabled,
		width = width,
		height = height,
		alpha = 1,
		showSwipe = true,
		showText = true,

		-- A LibSharedMedia **font** key, and a western one deliberately: `Fetch` answers with the
		-- client's own default for a key it does not know, so a locale that registers different names
		-- gets its correct font. Storing LSM's per-locale default would freeze one client's answer
		-- into a database that syncs across accounts.
		font = "Friz Quadrata TT",
		fontSize = 16,

		point = "BOTTOMRIGHT",
		x = 0,
		y = 0,
		gap = 0,
		borderTexture = "Blizzard Tooltip",
		borderSize = 4,
		borderR = 0,
		borderG = 0,
		borderB = 0,

		-- Opaque, and it has to be *present*: `SetSetting` refuses a field the stored block does not
		-- already have, so an icon without this one silently drops every border-alpha write -- and the
		-- colour picker reads it back as the opacity it opens at. `Repair` fills it into a database
		-- written before it was here, which is why no version step is needed.
		borderA = 1,
	}
end

--- One aura display drawn as a coloured block.
---
--- **Ships disabled for every feature, without exception**, which is the whole of why it needs no
--- version step: `Repair` fills the block into a database written before it existed, and a display that
--- is off changes nothing about how that profile renders.
---
--- One `size` rather than a width and a height -- see `SpotlightsAuraSquareConfig`. 14px is the size the
--- display exists for: too small for an icon's art to be read, large enough to be seen against a health
--- bar. Anchored top right, which is the one free corner once the bar defaults have taken the top left
--- and the icon defaults the bottom right, so all three switched on at once do not land on each other.
---
--- The colour is the feature's own, matching its bar, so a user switching between the two displays gets
--- the same colour rather than a white block. No border by default: at this size a 4px edge is most of
--- the display.
---
--- The duration text ships **off** while the swipe ships on. A square is sized where two digits do not
--- fit, and the swipe is how it says "and this much is left" -- but the font fields are here and
--- populated, because they are build-time and a field the stored block lacks is a write `SetSetting`
--- silently refuses.
---@param point AnchorPoint
---@param r number
---@param g number
---@param b number
---@return SpotlightsAuraSquareConfig
local function DefaultAuraSquare(point, r, g, b)
	return {
		enabled = false,
		size = 14,
		r = r,
		g = g,
		b = b,
		alpha = 1,
		point = point,
		x = 0,
		y = 0,
		showSwipe = true,
		showText = false,
		font = "Friz Quadrata TT",
		fontSize = 10,
		borderTexture = BORDER_NONE,
		borderSize = 4,
		borderR = 0,
		borderG = 0,
		borderB = 0,
		borderA = 1,
	}
end

--- One aura display drawn as a bare countdown.
---
--- **Ships disabled for every feature, without exception**, which is why it needs no version step, exactly
--- as the square does not: `Repair` fills the block into a database written before it existed, and a
--- display that is off changes nothing about how that profile renders.
---
--- No size of its own -- the anchor's rect is derived from `fontSize`, see the `text` entry in `Auras.lua`'s
--- `DISPLAYS`. Anchored bottom left, the corner the other three defaults leave free, so all four switched
--- on at once do not land on each other.
---
--- The colour is the feature's own, matching its bar and its block, so two categories drawing bare numbers
--- at once are still told apart. 16px because the display is *only* the number: the square's 10px is sized
--- to fit inside a block, and this has no block to fit inside.
---@param point AnchorPoint
---@param r number
---@param g number
---@param b number
---@return SpotlightsAuraTextConfig
local function DefaultAuraText(point, r, g, b)
	return {
		enabled = false,
		font = "Friz Quadrata TT",
		fontSize = 16,
		r = r,
		g = g,
		b = b,
		alpha = 1,
		point = point,
		x = 0,
		y = 0,

		-- No border by default, and the fields present even so: they are build-time, and `SetSetting`
		-- silently refuses a write to a field the stored block lacks.
		borderTexture = BORDER_NONE,
		borderSize = 4,
		borderR = 0,
		borderG = 0,
		borderB = 0,
		borderA = 1,
	}
end

--- One feature's set of displays at their shipped values, all freshly built.
---
--- Which one starts on is per-feature: a duration bar is what Prescience wants; an icon with a swipe
--- is what Sense Power wants. Every bar ships anchored **top left**, which is the corner a bar sized
--- against a spotlight is measured from -- at `TOP` a bar narrower or wider than the frame stays
--- centred, so a width dragged to match the frame never lines up with it. Only one bar ships enabled,
--- so nothing overlaps out of the box; two switched on are told apart by their colours.
---
--- Public and split out from `DefaultAuras` so the Reset button has one feature's defaults to write
--- back. Fresh tables every call, so a reset cannot alias one feature's block onto another's.
---
--- Every feature ships **enabled**, which is what makes the field free to add: `Repair` fills it into
--- a database written before it existed, and `true` is what those databases already behaved as. Which
--- displays a feature draws stays the per-display question it was.
---@param featureKey SpotlightsAuraFeatureKey
---@return SpotlightsAuraFeatureConfig
function Private.Migration.DefaultAuraFeature(featureKey)
	if featureKey == "sensePower" or featureKey == "shiftingSands" then
		local icon = DefaultAuraIcon(true, 25, 25)

		icon.point = "RIGHT"

		return {
			enabled = true,
			bar = DefaultAuraBar(false, "TOPLEFT", 0.2, 0.8, 1, 0),
			icon = icon,
			square = DefaultAuraSquare("TOPRIGHT", 0.2, 0.8, 1),
			text = DefaultAuraText("BOTTOMLEFT", 0.2, 0.8, 1),
		}
	end

	if featureKey == "cooldownAuras" or featureKey == "defensiveAuras" then
		return {
			enabled = true,
			bar = DefaultAuraBar(false, "TOPLEFT", 1, 1, 1, 0),
			icon = DefaultAuraIcon(true, 25, 25),

			-- Both stored like every other display's block even though a pooled feature draws icons only,
			-- for the reason its bar block is: the shapes are identical on purpose, and a feature missing
			-- one is a nil index in anything that walks the set.
			square = DefaultAuraSquare("TOPRIGHT", 1, 1, 1),
			text = DefaultAuraText("BOTTOMLEFT", 1, 1, 1),
		}
	end

	return {
		enabled = true,
		bar = DefaultAuraBar(true, "TOPLEFT", 1, 1, 0, -2),
		icon = DefaultAuraIcon(false, 25, 25),
		square = DefaultAuraSquare("TOPRIGHT", 1, 1, 0),
		text = DefaultAuraText("BOTTOMLEFT", 1, 1, 0),
	}
end

--- Every tracked aura, each with every display.
---
--- Every feature carries a full set of displays even though it starts with most of them off: they are
--- meant to be swappable, so the config a user turns *on* has to already exist.
---@return SpotlightsAurasConfig
local function DefaultAuras()
	return {
		prescience = Private.Migration.DefaultAuraFeature("prescience"),
		shiftingSands = Private.Migration.DefaultAuraFeature("shiftingSands"),
		sensePower = Private.Migration.DefaultAuraFeature("sensePower"),
		cooldownAuras = Private.Migration.DefaultAuraFeature("cooldownAuras"),
		defensiveAuras = Private.Migration.DefaultAuraFeature("defensiveAuras"),

		-- Both empty until the user touches something. `cooldowns` records only the built-ins turned
		-- *off*, so an empty table means "every shipped cooldown is on" -- which is why nothing has to
		-- reconcile this against the list in `Auras.lua` when that list grows.
		cooldowns = {},
		custom = {},
		defensives = {},
		defensiveCustom = {},
	}
end

--- One step per version, keyed by the version it *produces*. A step receives the database at
--- version n-1 and leaves it at version n; the runner writes `version` itself.
---
--- Empty at version 1: there is nothing to migrate *to* the initial shape. The runner exists anyway,
--- because retrofitting versioning onto saved data already in the wild is the expensive mistake. The
--- steps for versions 2 through 10 were collapsed before release, since no wild database ever claimed
--- those versions. `Repair` still fills any field a fresh install's blocks would have.
---@type table<integer, fun(db: SpotlightsDB)>
local steps = {
	[2] = function(db)
		db.minimap = db.minimap or { hide = false }
	end,
	[3] = function(db)
		local layout = db.layout or {}
		local width = layout.frameWidth or 100
		local height = layout.frameHeight or 50
		local features = { "prescience", "shiftingSands", "sensePower", "cooldownAuras", "defensiveAuras" }

		for i = 1, #features do
			local feature = db.auras and db.auras[features[i]]
			local bar = feature and feature.bar

			if bar then
				if bar.widthPct ~= nil then
					bar.width = math.max(1, width * bar.widthPct)
				end

				if bar.heightPct ~= nil then
					bar.height = math.max(1, height * bar.heightPct)
				end

				bar.widthPct = nil
				bar.heightPct = nil
			end
		end

		local auras = db.auras or {}
		auras.defensives = auras.defensives or {}
		auras.defensiveCustom = auras.defensiveCustom or {}
		db.auras = auras
	end,
	[4] = function(db)
		db.presets = db.presets or {}
	end,
}

--- Fills in every field `defaults` has and `target` lacks, returning what to store: `target` patched,
--- or `defaults` outright if `target` is not a table.
---
--- Recursive because the aura block is two levels deep where layout and appearance are flat: a
--- feature holds two displays and a display holds its fields.
---
--- A table default always recurses rather than being copied wholesale, so a database missing one
--- field of one display gains it and keeps the eleven around it. Every caller passes a freshly built
--- `defaults`, so nothing here can alias one block onto another.
---@generic T: table
---@param target any
---@param defaults T
---@return T
local function Filled(target, defaults)
	if type(target) ~= "table" then
		return defaults
	end

	for field, value in pairs(defaults) do
		if type(value) == "table" then
			target[field] = Filled(target[field], value)
		elseif target[field] == nil then
			target[field] = value
		end
	end

	return target
end

--- Fills in any field a settings block is missing, replacing the block outright if it is not a table.
---
--- Separate from the migration and run on every load, because they answer different questions. The
--- migration handles *known* shape changes between versions; this handles a database that is nominally
--- current but damaged -- hand-edited SavedVariables, a partial write, or a field added without a
--- version bump. A nil where a number is expected becomes arithmetic on nil deep in the layout maths.
---
--- Field-by-field is right for layout and appearance because each field stands alone. Position is the
--- exception and gets its own repair below.
---@param db SpotlightsDB
---@param key "layout" | "appearance" | "auras" | "minimap" | "presets"
---@param build fun(): table
local function RepairBlock(db, key, build)
	db[key] = Filled(db[key], build())
end

--- Fills in a missing or damaged position block, for the same reasons RepairBlock exists.
---
--- Stricter than RepairBlock's field-by-field fill: *where* the grid sits is only meaningful as a
--- whole, so a partial anchor is replaced rather than patched. `point` is validated against the set
--- CalcPoint can produce, because SetPoint errors outright on an unrecognised one.
---
--- Scale and strata are the exception and are repaired field by field, because neither is part of
--- that anchor: a database written before they existed has a perfectly good position, and throwing
--- it away over a field it could not have had would move the user's grid on first login.
---@param db SpotlightsDB
local function RepairPosition(db)
	local position = db.position

	if
		type(position) ~= "table"
		or type(position.x) ~= "number"
		or type(position.y) ~= "number"
		or not Private.Enum.AnchorPoints[position.point]
	then
		db.position = DefaultPosition()

		return
	end

	local defaults = DefaultPosition()

	-- Zero and negative are rejected rather than clamped to the slider's floor: `SetScale` errors on
	-- them, and a database claiming either was not produced by the slider in the first place.
	if type(position.scale) ~= "number" or position.scale <= 0 then
		position.scale = defaults.scale
	end

	if not Private.Enum.FrameStrata[position.strata] then
		position.strata = defaults.strata
	end
end

--- Validates the one appearance field a field-by-field fill cannot repair.
---
--- `RepairBlock` only replaces nils, and a nil is not the failure mode here: `SetFrameStrata` errors
--- outright on a name it does not know and takes the pass with it, so a hand-edited `nameStrata` has to
--- be checked against the value space rather than merely for presence. The same check `RepairPosition`
--- gives `position.strata`, and separate from it for the same reason it is separate there.
---
--- Runs after `RepairBlock` has guaranteed the block is a table.
---@param db SpotlightsDB
local function RepairNameStrata(db)
	local appearance = db.appearance
	local strata = appearance.nameStrata

	if strata ~= Private.Enum.NameStrataInherit and not Private.Enum.FrameStrata[strata] then
		appearance.nameStrata = DefaultAppearance().nameStrata
	end
end

--- Every repair, in one call, so no caller has to remember the set.
---
--- Adding a settings block means adding it here as well as to CreateDefault and a migration step.
--- Three places, but they answer three different questions -- what a new database contains, what an
--- old one gains, what a damaged one gets back -- and collapsing them would mean a migration that
--- silently repairs, which is how a schema bug becomes undetectable.
---@param db SpotlightsDB
local function Repair(db)
	RepairBlock(db, "layout", DefaultLayout)
	RepairBlock(db, "appearance", DefaultAppearance)
	RepairNameStrata(db)
	RepairBlock(db, "auras", DefaultAuras)
	RepairPosition(db)
	RepairBlock(db, "minimap", function()
		return { hide = false }
	end)

	--- Empty defaults, so this only ever replaces a `presets` that is not a table: the block is a
	--- library the user filled rather than a set of fields we ship, and there is no such thing as a
	--- preset missing from it.
	RepairBlock(db, "presets", function()
		return {}
	end)
end

---@return SpotlightsDB
local function CreateDefault()
	return {
		version = Private.Migration.CurrentVersion,
		slots = {},
		layout = DefaultLayout(),
		position = DefaultPosition(),
		appearance = DefaultAppearance(),
		auras = DefaultAuras(),
		minimap = { hide = false },
		presets = {},
	}
end

--- Brings saved data up to CurrentVersion, replacing it when it is unusable.
---
--- Data from a *newer* version is left untouched and reported rather than downgraded: the user has
--- run a later build on this account, and quietly rewriting their slots to fit an older schema
--- destroys data no reload brings back.
---@param saved SpotlightsDB?
---@return SpotlightsDB db, boolean fresh
function Private.Migration.Run(saved)
	if type(saved) ~= "table" or type(saved.slots) ~= "table" then
		return CreateDefault(), true
	end

	local version = type(saved.version) == "number" and saved.version or 0

	if version > Private.Migration.CurrentVersion then
		Private.Utils.Printf(
			Private.L.Migration.FromTheFuture,
			version,
			Private.Migration.CurrentVersion
		)

		-- Repaired even so: we will not rewrite a future schema, but we still have to *read* it, and a
		-- missing layout field would error on the first geometry pass.
		Repair(saved)

		return saved, false
	end

	for target = version + 1, Private.Migration.CurrentVersion do
		local step = steps[target]

		if step then
			step(saved)
		end

		saved.version = target
	end

	Repair(saved)

	return saved, false
end
