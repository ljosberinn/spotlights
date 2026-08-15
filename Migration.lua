---@type string, Spotlights
local _, Private = ...

---@class SpotlightsMigration
Private.Migration = {}

--- Bump this and add the matching step whenever the shape of SpotlightsSaved changes.
Private.Migration.CurrentVersion = 5

--- A function rather than a shared table: handing the same table to two callers would alias one user's
--- settings onto another's.
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

		-- Damage alone, because those are the players anyone spotlights.
		--
		-- **All three keys are written**, and a deselected role is stored `false` rather than removed:
		-- `Filled` recurses into a table default and fills whatever the stored one lacks, so a hole would
		-- read as "missing" and come back at the default.
		unrosteredRoles = {
			TANK = false,
			HEALER = false,
			DAMAGER = true,
		},

		-- Every role off, on `clearOnLeave`'s grounds: this discards slots the user arranged. All three
		-- keys written, as above.
		autoRemoveRoles = {
			TANK = false,
			HEALER = false,
			DAMAGER = false,
		},
	}
end

--- Where the grid sits, as a **corner-relative point plus an offset** rather than raw coordinates: the
--- point is picked from which region of the screen the grid was dropped in, so a position stays in the
--- same region across resolutions instead of drifting toward the middle.
---
--- `scale` and `strata` ship at what the grid already did: unscaled, and the `LOW` the unit frame
--- template used to declare for itself.
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
--- `barTexture` is a LibSharedMedia **key**, never a resolved path: what a key maps to depends on which
--- addons are loaded, so a stored path breaks when a media pack is removed.
---
--- Static colours are stored even while class colour is on, so switching it off reveals a chosen colour
--- rather than a blank one. `healthBgColor` is the background shown through unfilled health, used only
--- in static mode, and defaults to the static bar colour at a fifth (what class mode derives).
---
--- **The rule for every field added here since:** a new one ships at whatever a database written before
--- it already behaved as, so `Repair` filling it in changes nothing and no version step is owed.
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

		-- Not a strata but the absence of one: the name layer sets none of its own and inherits the
		-- container's, which is how every spotlight has always drawn.
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

--- Exposed so the options panel's per-section reset buttons can write these defaults back. The same
--- fresh-per-call tables, so a reset cannot alias one build's defaults onto another's.
Private.Migration.DefaultLayout = DefaultLayout
Private.Migration.DefaultAppearance = DefaultAppearance

--- A media key rather than a separate on/off setting, because LSM registers `None` as an empty path and
--- every border dropdown already offers it.
local BORDER_NONE = "None"

--- **Two rules govern every display default below, and are stated only here.**
---
--- A display that ships *disabled* needs no version step: `Repair` fills its block into a database
--- written before it existed, and a display that is off changes nothing about how that profile renders.
---
--- Every field is present and defaulted even where the panel offers no control for it, because
--- `SetSetting` silently refuses a write to a field the stored block lacks.

--- One aura display drawn as a duration bar. The parameters are exactly the fields the feature defaults
--- disagree on.
---
--- Sized for the default 100x50 frame: full width, and a fixed 25px height that keeps the bar off the
--- player's name. `Solid` is LSM's name for `Interface\Buttons\WHITE8X8`.
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

		-- What every bar written before this field already drew.
		orientation = Private.Enum.Orientation.Horizontal,

		-- The widget default: a bar written before this field drained toward the axis' start.
		reverseFill = false,

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

		-- A LibSharedMedia **font** key, and a western one deliberately: `Fetch` answers with the client's
		-- own default for a key it does not know, so a locale registering different names gets its correct
		-- font. Storing LSM's per-locale default would freeze one client's answer into a synced database.
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

		borderA = 1,
	}
end

--- One aura display drawn as a coloured block. 14px is the size the display exists for: too small for an
--- icon's art to be read, large enough to be seen against a health bar. Anchored top right, the corner
--- the bar and icon defaults leave free, so all three switched on at once do not land on each other.
---
--- The colour is the feature's own, matching its bar, so switching between the two displays gets the
--- same colour rather than a white block. No border, because at this size a 4px edge is most of the
--- display, and no duration text, because two digits do not fit.
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

--- One aura display drawn as a bare countdown. No size of its own -- the anchor's rect is derived from
--- `fontSize`, see the `text` entry in `Auras.lua`'s `DISPLAYS`. Anchored bottom left, the corner the
--- other three defaults leave free.
---
--- The colour is the feature's own, so two categories drawing bare numbers at once are still told apart.
--- 16px because the display is *only* the number, where the square's 10px fits inside a block.
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

		borderTexture = BORDER_NONE,
		borderSize = 4,
		borderR = 0,
		borderG = 0,
		borderB = 0,
		borderA = 1,
	}
end

--- One aura display drawn as a colour over the spotlight's health bar. The colour is the feature's own,
--- so two categories tinting the same bar are still told apart.
---
--- `point`, `x`, `y` and the border fields have nothing to place or edge here: this display's rect is
--- the health bar's rather than an offset from the frame.
---@param r number
---@param g number
---@param b number
---@return SpotlightsAuraFrameColorConfig
local function DefaultAuraFrameColor(r, g, b)
	return {
		enabled = false,
		r = r,
		g = g,
		b = b,

		-- Opaque, because "pick a colour for the health bar" means the bar wearing that colour rather than
		-- being washed toward it. The one setting here that drags live, so showing the class colour
		-- through is to hand.
		alpha = 1,

		point = "CENTER",
		x = 0,
		y = 0,
		borderTexture = BORDER_NONE,
		borderSize = 4,
		borderR = 0,
		borderG = 0,
		borderB = 0,
		borderA = 1,
	}
end

--- One feature's set of displays at their shipped values, all freshly built, so a reset cannot alias one
--- feature's block onto another's.
---
--- Which display starts on is per-feature. Every bar ships anchored **top left**, the corner a bar sized
--- against a spotlight is measured from: at `TOP` a bar narrower or wider than the frame stays centred,
--- so a width dragged to match the frame never lines up with it.
---
--- Every feature ships **enabled**, which is what made the field free to add: `true` is what a database
--- written before it already behaved as.
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
			frameColor = DefaultAuraFrameColor(0.2, 0.8, 1),
		}
	end

	if featureKey == "cooldownAuras" or featureKey == "defensiveAuras" then
		return {
			enabled = true,
			bar = DefaultAuraBar(false, "TOPLEFT", 1, 1, 1, 0),
			icon = DefaultAuraIcon(true, 25, 25),

			-- Stored even though a pooled feature draws icons only: the shapes are identical on purpose,
			-- and a feature missing one is a nil index in anything that walks the set.
			square = DefaultAuraSquare("TOPRIGHT", 1, 1, 1),
			text = DefaultAuraText("BOTTOMLEFT", 1, 1, 1),
			frameColor = DefaultAuraFrameColor(1, 1, 1),
		}
	end

	return {
		enabled = true,
		bar = DefaultAuraBar(true, "TOPLEFT", 1, 1, 0, -2),
		icon = DefaultAuraIcon(false, 25, 25),
		square = DefaultAuraSquare("TOPRIGHT", 1, 1, 0),
		text = DefaultAuraText("BOTTOMLEFT", 1, 1, 0),
		frameColor = DefaultAuraFrameColor(1, 1, 0),
	}
end

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

		-- `cooldowns` records only the built-ins turned *off*, so an empty table means "every shipped
		-- cooldown is on" -- which is why nothing reconciles this against `Auras.lua` when that list grows.
		cooldowns = {},
		custom = {},
		defensives = {},
		defensiveCustom = {},
	}
end

--- One step per version, keyed by the version it *produces*. A step receives the database at version
--- n-1 and leaves it at version n; the runner writes `version` itself.
---
--- Empty at version 1, since there is nothing to migrate *to* the initial shape. The runner exists
--- anyway, because retrofitting versioning onto saved data already in the wild is the expensive mistake.
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
	[5] = function(db)
		db.clickCasts = db.clickCasts or {}
	end,
}

--- Fills in every field `defaults` has and `target` lacks, returning `target` patched or `defaults`
--- outright if `target` is not a table. Recursive because the aura block is two levels deep.
---
--- A table default always recurses rather than being copied wholesale, so a database missing one field
--- of one display gains it and keeps the rest. Every caller passes a freshly built `defaults`, so
--- nothing here can alias one block onto another.
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
--- Separate from the migration and run on every load, because they answer different questions: the
--- migration handles *known* shape changes between versions, this handles a database that is nominally
--- current but damaged. A nil where a number is expected becomes arithmetic on nil deep in the layout
--- maths.
---@param db SpotlightsDB
---@param key "layout" | "appearance" | "auras" | "minimap" | "presets" | "clickCasts"
---@param build fun(): table
local function RepairBlock(db, key, build)
	db[key] = Filled(db[key], build())
end

--- Stricter than `RepairBlock`'s field-by-field fill: *where* the grid sits is only meaningful as a
--- whole, so a partial anchor is replaced rather than patched. `point` is validated against the set
--- `CalcPoint` can produce, because `SetPoint` errors outright on an unrecognised one.
---
--- Scale and strata are repaired field by field, because neither is part of that anchor: throwing away a
--- good position over a field it could not have had would move the user's grid on first login.
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

--- Validates the one appearance field a field-by-field fill cannot repair. `RepairBlock` only replaces
--- nils, and a nil is not the failure mode here: `SetFrameStrata` errors outright on a name it does not
--- know and takes the pass with it, so `nameStrata` is checked against the value space rather than for
--- presence. Runs after `RepairBlock` has guaranteed the block is a table.
---@param db SpotlightsDB
local function RepairNameStrata(db)
	local appearance = db.appearance
	local strata = appearance.nameStrata

	if strata ~= Private.Enum.NameStrataInherit and not Private.Enum.FrameStrata[strata] then
		appearance.nameStrata = DefaultAppearance().nameStrata
	end
end

--- Every repair, in one call. Adding a settings block means adding it here as well as to `CreateDefault`
--- and a migration step: three places, answering what a new database contains, what an old one gains and
--- what a damaged one gets back. Collapsing them would mean a migration that silently repairs, which is
--- how a schema bug becomes undetectable.
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

	-- Empty defaults, so this only ever replaces a `presets` that is not a table: the block is a library
	-- the user filled, and there is no such thing as a preset missing from it.
	RepairBlock(db, "presets", function()
		return {}
	end)

	-- A list the user built, so empty defaults for `presets`' reason. What is *in* it is validated where it
	-- is read: `ClickCasts.ApplyChild` refuses a button the secure templates give no usable suffix.
	RepairBlock(db, "clickCasts", function()
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
		clickCasts = {},
	}
end

--- Brings saved data up to `CurrentVersion`, replacing it when it is unusable. Data from a *newer*
--- version is left untouched and reported rather than downgraded: quietly rewriting a user's slots to
--- fit an older schema destroys data no reload brings back.
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
