---@type string, Spotlights
local _, Private = ...

---@class SpotlightsMigration
Private.Migration = {}

--- Bump this and add the matching step whenever the shape of SpotlightsSaved changes.
Private.Migration.CurrentVersion = 1

--- The layout defaults, and the shape version 2 introduced.
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
	}
end

--- Where the grid sits, as a **corner-relative point plus an offset** rather than raw coordinates,
--- and the shape version 3 introduced.
---
--- The point is picked from which region of the screen the grid was dropped in, and the offset is
--- measured from that corner, so a position stays in the same *region* across resolutions instead of
--- drifting toward the middle.
---
--- `CENTER` is the default and the one point where both offsets are measured from the screen centre.
---@return SpotlightsPositionConfig
local function DefaultPosition()
	return {
		point = "CENTER",
		x = 0,
		y = 0,
	}
end

--- How a spotlight looks, and the shape version 4 introduced.
---
--- `barTexture` is a LibSharedMedia **key**, never a resolved path: the path a key maps to depends
--- on which addons are loaded, so storing the path breaks when a media pack is removed. Resolution
--- happens at apply time, in `Private.Media`.
---
--- The colour and name fields were added by version 8, reproducing the earlier hardcoded look. Static
--- colours are stored even while class colour is on, so switching it off reveals a chosen colour
--- rather than a blank one. `healthBgColor` is the background shown through unfilled health, used only
--- in static mode; its default is the static bar colour at a fifth (what class mode derives).
---@return SpotlightsAppearanceConfig
local function DefaultAppearance()
	return {
		barTexture = "Blizzard Raid Bar",
		showAbsorb = false,
		outOfRangeAlpha = 0.45,
		deadAlpha = 0.45,
		healthUseClassColor = true,
		healthColorR = 0.1,
		healthColorG = 0.7,
		healthColorB = 0.1,
		healthBgColorR = 0.02,
		healthBgColorG = 0.14,
		healthBgColorB = 0.02,
		nameUseClassColor = false,
		nameColorR = 1,
		nameColorG = 1,
		nameColorB = 1,
		nameFont = "Friz Quadrata TT",
		nameFontSize = 10,
		namePoint = "TOPLEFT",
		nameX = 3,
		nameY = -3,
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

--- One aura display drawn as a duration bar, and the shape version 5 introduced.
---
--- The parameters are exactly the fields the two features disagree on; everything else about a bar is
--- the same for both.
---
--- The defaults reproduce the adjacent Prescience addon: full width at *half* the frame's height,
--- pinned to the top, gold at half alpha. Half height also keeps the bar off the player's name.
---
--- `widthPct` and `heightPct` are fractions of the spotlight rather than pixels, because the
--- spotlight is resizable: a stored pixel size would stop matching the first time a slider moved.
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
		widthPct = 1,
		heightPct = 0.5,
		point = point,
		x = 0,
		y = y,
		showIcon = false,
		iconSide = "LEFT",
		borderTexture = BORDER_NONE,
		borderSize = 12,
		borderR = 0,
		borderG = 0,
		borderB = 0,
	}
end

--- One aura display drawn as a spell icon, and the other half of version 5's shape.
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

		point = "CENTER",
		x = 0,
		y = 0,
		borderTexture = BORDER_NONE,
		borderSize = 12,
		borderR = 0,
		borderG = 0,
		borderB = 0,
	}
end

--- One feature's pair of displays at their shipped values, both freshly built.
---
--- Which one starts on is per-feature: a duration bar is what Prescience wants; an icon with a swipe
--- is what Sense Power wants. The two bars would sit on top of each other if both were on, so the
--- second defaults to the bottom edge in a different colour.
---
--- Public and split out from `DefaultAuras` so the Reset button has one feature's defaults to write
--- back. Fresh tables every call, so a reset cannot alias one feature's block onto another's.
---@param featureKey string
---@return SpotlightsAuraFeatureConfig
function Private.Migration.DefaultAuraFeature(featureKey)
	if featureKey == "sensePower" then
		local icon = DefaultAuraIcon(true, 50, 50)

		icon.point = "RIGHT"

		return {
			bar = DefaultAuraBar(false, "BOTTOM", 0.2, 0.8, 1, 0),
			icon = icon,
		}
	end

	return {
		bar = DefaultAuraBar(true, "TOP", 1, 1, 0, -2),
		icon = DefaultAuraIcon(false, 50, 50),
	}
end

--- Both tracked auras, each with both displays, and the shape version 5 introduced.
---
--- Every feature carries a full set of both displays even though it starts with one off: the two are
--- meant to be swappable, so the config a user turns *on* has to already exist.
---@return SpotlightsAurasConfig
local function DefaultAuras()
	return {
		prescience = Private.Migration.DefaultAuraFeature("prescience"),
		sensePower = Private.Migration.DefaultAuraFeature("sensePower"),

		-- Both empty until the user touches something. `cooldowns` records only the built-ins turned
		-- *off*, so an empty table means "every shipped cooldown is on" -- which is why nothing has to
		-- reconcile this against the list in `Auras.lua` when that list grows.
		cooldowns = {},
		custom = {},
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
local steps = {}

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
---@param key "layout" | "appearance" | "auras"
---@param build fun(): table
local function RepairBlock(db, key, build)
	db[key] = Filled(db[key], build())
end

--- Fills in a missing or damaged position block, for the same reasons RepairBlock exists.
---
--- Stricter than RepairBlock's field-by-field fill: a position is only meaningful as a whole, so a
--- partial block is replaced rather than patched. `point` is validated against the set CalcPoint can
--- produce, because SetPoint errors outright on an unrecognised one.
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
	RepairBlock(db, "auras", DefaultAuras)
	RepairPosition(db)
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

	-- Version 0 stands in for "saved before the field existed", walking the same upgrade path as any
	-- other version.
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
