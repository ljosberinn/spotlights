---@type string, Spotlights
local _, Private = ...

---@class SpotlightsMedia
Private.Media = {}

local LSM = LibStub("LibSharedMedia-3.0")

local STATUSBAR = LSM.MediaType.STATUSBAR
local BORDER = LSM.MediaType.BORDER
local FONT = LSM.MediaType.FONT

--- Re-exported so other modules can name a medium type without reaching into LibSharedMedia --
--- `Private.Auras` tells a border named `Steel` from a statusbar named `Steel`.
Private.Media.StatusBarType = STATUSBAR
Private.Media.BorderType = BORDER
Private.Media.FontType = FONT

--- Resolves a stored key to a texture path, at apply time and never before.
---
--- A key maps to a path only in the context of loaded addons, so resolving once and storing the
--- result freezes one session's answer: uninstall the media pack and the saved path points at a
--- missing file, with no key left to fall back from.
---
--- `Fetch` falls back to LSM's default for an unknown key, so a database naming a removed texture
--- degrades to Blizzard's bar rather than erroring.
---@param key string
---@return string path
function Private.Media.StatusBar(key)
	return LSM:Fetch(STATUSBAR, key)
end

--- Every registered statusbar key, sorted. The options frame's texture list. LSM's own table, so
--- treat it as read-only.
---@return string[]
function Private.Media.StatusBarList()
	return LSM:List(STATUSBAR)
end

--- Whether a key is currently registered, which is not whether it is *stored*. A database may name
--- a texture from an addon not loaded this session; the setting is kept and `StatusBar` resolves it
--- to the default until the addon returns.
---@param key string
---@return boolean
function Private.Media.IsRegistered(key)
	return LSM:IsValid(STATUSBAR, key) and true or false
end

--- Resolves a stored border key to an edge-texture path, at apply time and never before.
---
--- Same key/path indirection as `StatusBar`. Borders differ in one way: LSM registers `None` as an
--- **empty path**, making "no border" a media choice rather than a separate on/off setting. A
--- caller must check for it, since `SetBackdrop` errors on a backdrop with neither background nor
--- edge.
---@param key string
---@return string path
function Private.Media.Border(key)
	return LSM:Fetch(BORDER, key)
end

--- Every registered border key, sorted. LSM's own table, so treat it as read-only.
---@return string[]
function Private.Media.BorderList()
	return LSM:List(BORDER)
end

--- Whether a border key is currently registered, which is not whether it is *stored*. See
--- `IsRegistered` above.
---@param key string
---@return boolean
function Private.Media.IsBorderRegistered(key)
	return LSM:IsValid(BORDER, key) and true or false
end

--- Resolves a stored font key to a font file path, at apply time and never before.
---
--- Same indirection as `StatusBar`. Fonts have one wrinkle: LSM's *default* font differs by locale,
--- and the keys it registers differ with it -- so a database naming `Friz Quadrata TT` on a Korean
--- client names nothing, and `Fetch` answers with that client's default rather than erroring. That
--- is why the stored default can be a western key without stranding anyone.
---@param key string
---@return string path
function Private.Media.Font(key)
	return LSM:Fetch(FONT, key)
end

--- Every registered font key, sorted. LSM's own table, so treat it as read-only.
---@return string[]
function Private.Media.FontList()
	return LSM:List(FONT)
end

--- Whether a font key is currently registered, which is not whether it is *stored*. See
--- `IsRegistered` above.
---@param key string
---@return boolean
function Private.Media.IsFontRegistered(key)
	return LSM:IsValid(FONT, key) and true or false
end

--- Re-applies textures when another addon registers new media.
---
--- Load order is not ours to control: an addon registering the very texture the user selected may
--- load after us, by which point `Fetch` has fallen back to the default. Without this the user's
--- choice silently reverts until the next reload, which then appears to fix it.
LSM.RegisterCallback(Private.Media, "LibSharedMedia_Registered", function(_, mediatype, key)
	if mediatype ~= STATUSBAR and mediatype ~= BORDER and mediatype ~= FONT then
		return
	end

	local db = Private.DB

	if not db then
		return
	end

	-- Aura displays first: they need more than a re-texture. A `StatusBar` under an aura button is
	-- access-restricted the moment the button is built, so a fallback texture resolved at build
	-- time can only be replaced by a new button. For the health bar below, this is merely the
	-- difference between now and the next reload.
	--
	-- Handed to `Private.Auras` rather than decided here: matching the stored key is not enough. A
	-- display built *after* this registration already resolved the key correctly, and rebuilding it
	-- abandons a container and arms the reload prompt to change nothing. Which displays fell back on
	-- this key is a fact about each built display, which lives there.
	Private.Auras.OnMediaRegistered(mediatype, key)

	if mediatype ~= STATUSBAR then
		return
	end

	local appearance = db.appearance

	if not appearance or appearance.barTexture ~= key then
		return
	end

	Private.SlotHeader.ForEachChild(function(child)
		child:UpdateTexture()
	end)

	Private.Preview.Restyle()
end)
