﻿-- This addon is in Alpha status and is probably not usable

Routes = LibStub("AceAddon-3.0"):NewAddon("Routes", "AceConsole-3.0", "AceEvent-3.0")
local Routes = Routes
local L = LibStub("AceLocale-3.0"):GetLocale("Routes", false)
local BZ = LibStub("LibBabble-Zone-3.0"):GetUnstrictLookupTable()
local BZR = LibStub("LibBabble-Zone-3.0"):GetReverseLookupTable()
local G = {} -- was Graph-1.0, but we removed the dependency



-- database defaults
local db
local defaults = {
	global = {
		routes = {
			['*'] = { -- zone name
				['*'] = { -- route name
					route           = {},    -- point, point, point
					color           = nil,   -- defaults to db.defaults.color if nil
					width           = nil,   -- defaults to db.defaults.width if nil
					width_minimap   = nil,   -- defaults to db.defaults.width_minimap if nil
					width_battlemap = nil,   -- defaults to db.defaults.width_battlemap if nil
					hidden          = false, -- boolean
					looped          = 1,     -- looped? 1 is used (instead of true) because initial early code used 1 inside route creation code
					visible         = true,  -- visible?
					length          = 0,     -- length
					source          = {
						['**'] = {         -- Database
							['**'] = false -- Node
						},
					},
				},
			},
		},
		defaults = {            --    r,    g,    b,   a
			color           = {   1, 0.75, 0.75,   1 },
			hidden_color    = {   1,    1,    1, 0.5 },
			width           = 35,
			width_minimap   = 30,
			width_battlemap = 15,
			show_hidden     = false,
			update_distance = 1,
			fake_point      = -1,
			fake_data       = 'dummy',
			draw_minimap    = 1,
			draw_worldmap   = 1,
			draw_battlemap  = 1,
			tsp = {
				initial_pheromone  = 0,     -- Initial pheromone trail value
				alpha              = 1,     -- Likelihood of ants to follow pheromone trails (larger value == more likely)
				beta               = 6,     -- Likelihood of ants to choose closer nodes (larger value == more likely)
				local_decay        = 0.2,   -- Governs local trail decay rate [0, 1]
				local_update       = 0.4,   -- Amount of pheromone to reinforce local trail update by
				global_decay       = 0.2,   -- Governs global trail decay rate [0, 1]
				twoopt_passes      = 3,		-- Number of times to perform 2-opt passes
				two_point_five_opt = false, -- Perform optimized 2-opt pass
			},
		},
	}
}

-- localize some globals
local pairs, ipairs, next = pairs, ipairs, next
local tinsert, tremove = tinsert, tremove
local floor = floor
local WorldMapButton = WorldMapButton

-- other locals we use
local zoneNames = {} -- cache of zones names by continent and zoned id from WowAPI


------------------------------------------------------------------------------------------------------
-- General event functions

function Routes:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("RoutesDB", defaults)
	db = self.db.global

	-- Initialize zone names into a table
	for index, zname in ipairs({GetMapZones(1)}) do
		zoneNames[100 + index] = zname;
	end
	for index, zname in ipairs({GetMapZones(2)}) do
		zoneNames[200 + index] = zname;
	end
	for index, zname in ipairs({GetMapZones(3)}) do
		zoneNames[300 + index] = zname;
	end
end

function Routes:OnEnable()
	self:RegisterEvent("WORLD_MAP_UPDATE", "DrawWorldmapLines")
end

function Routes:OnDisable()
	-- Ace3 unregisters all events and hooks for us on disable
end

------------------------------------------------------------------------------------------------------
-- Core Routes functions

--[[ Our coordinate format for Routes
Warning: These are convenience functions, most of the :getXY() and :getID()
code are inlined in critical code paths in various functions, changing
the coord storage format requires changing the inlined code in numerous
locations in addition to these 2 functions
]]
function Routes:getID(x, y)
	return floor(x * 10000 + 0.5) * 10000 + floor(y * 10000 + 0.5)
end
function Routes:getXY(id)
	return floor(id / 10000) / 10000, (id % 10000) / 10000
end

function Routes:DrawWorldmapLines()
	-- setup locals
	local zone = zoneNames[GetCurrentMapContinent()*100 + GetCurrentMapZone()]
	if BZR[zone] then zone = BZR[zone] end
	local BattlefieldMinimap = BattlefieldMinimap  -- local reference if it exists
	local fh, fw = WorldMapButton:GetHeight(), WorldMapButton:GetWidth()
	local bfh, bfw  -- BattlefieldMinimap height and width
	local defaults = db.defaults

	-- clear all the lines
	G:HideLines(WorldMapButton)
	if (BattlefieldMinimap) then
		-- The Blizzard addon "Blizzard_BattlefieldMinimap" is loaded
		G:HideLines(BattlefieldMinimap)
		bfh, bfw = BattlefieldMinimap:GetHeight(), BattlefieldMinimap:GetWidth()
	end

	-- check for conditions not to draw the world map lines
	if not zone then return end -- player is not viewing a zone map of a continent
	local flag1 = defaults.draw_worldmap and WorldMapFrame:IsShown() -- Draw worldmap lines?
	local flag2 = defaults.draw_battlemap and BattlefieldMinimap and BattlefieldMinimap:IsShown() -- Draw battlemap lines?
	if (not flag1) and (not flag2) then	return end 	-- Nothing to draw

	for route_name, route_data in pairs( db.routes[zone] ) do
		if type(route_data) == "table" and type(route_data.route) == "table" and #route_data.route > 1 then
			local width = route_data.width or defaults.width
			local halfwidth = route_data.width_battlemap or defaults.width_battlemap
			local color = route_data.color or defaults.color

			if (not route_data.hidden and (route_data.visible or not defaults.use_auto_showhide)) or defaults.show_hidden then
				if route_data.hidden then color = defaults.hidden_color end
				local last_point
				local sx, sy
				if route_data.looped then
					last_point = route_data.route[ #route_data.route ]
					sx, sy = floor(last_point / 10000) / 10000, (last_point % 10000) / 10000
					sy = (1 - sy)
				end
				for i = 1, #route_data.route do
					local point = route_data.route[i]
					if point == defaults.fake_point then
						point = nil
					end
					if last_point and point then
						local ex, ey = floor(point / 10000) / 10000, (point % 10000) / 10000
						ey = (1 - ey)
						if (flag1) then
							G:DrawLine(WorldMapButton, sx*fw, sy*fh, ex*fw, ey*fh, width, color , "OVERLAY")
						end
						if (flag2) then
							G:DrawLine(BattlefieldMinimap, sx*bfw, sy*bfh, ex*bfw, ey*bfh, halfwidth, color , "OVERLAY")
						end
						sx, sy = ex, ey
					end
					last_point = point
				end
			end
		end
	end
end



------------------------------------------------------------------------------------------------------
-- The following function is used with permission from Daniel Stephens <iriel@vigilance-committee.org>
-- with reference to TaxiFrame.lua in Blizzard's UI and Graph-1.0 Ace2 library (by Cryect) which I now
-- maintain after porting it to LibGraph-2.0 LibStub library -- Xinhuan
local TAXIROUTE_LINEFACTOR = 128/126; -- Multiplying factor for texture coordinates
local TAXIROUTE_LINEFACTOR_2 = TAXIROUTE_LINEFACTOR / 2; -- Half of that

-- T        - Texture
-- C        - Canvas Frame (for anchoring)
-- sx,sy    - Coordinate of start of line
-- ex,ey    - Coordinate of end of line
-- w        - Width of line
-- relPoint - Relative point on canvas to interpret coords (Default BOTTOMLEFT)
function G:DrawLine(C, sx, sy, ex, ey, w, color, layer)
	local relPoint = "BOTTOMLEFT"
	
	if not C.Routes_Lines then
		C.Routes_Lines={}
		C.Routes_Lines_Used={}
	end

	local T = tremove(C.Routes_Lines) or C:CreateTexture(nil, "ARTWORK")
	T:SetTexture("Interface\\AddOns\\Routes\\line")
	tinsert(C.Routes_Lines_Used,T)

	T:SetDrawLayer(layer or "ARTWORK")

	T:SetVertexColor(color[1],color[2],color[3],color[4]);
	-- Determine dimensions and center point of line
	local dx,dy = ex - sx, ey - sy;
	local cx,cy = (sx + ex) / 2, (sy + ey) / 2;

	-- Normalize direction if necessary
	if (dx < 0) then
		dx,dy = -dx,-dy;
	end

	-- Calculate actual length of line
	local l = sqrt((dx * dx) + (dy * dy));

	-- Sin and Cosine of rotation, and combination (for later)
	local s,c = -dy / l, dx / l;
	local sc = s * c;

	-- Calculate bounding box size and texture coordinates
	local Bwid, Bhgt, BLx, BLy, TLx, TLy, TRx, TRy, BRx, BRy;
	if (dy >= 0) then
		Bwid = ((l * c) - (w * s)) * TAXIROUTE_LINEFACTOR_2;
		Bhgt = ((w * c) - (l * s)) * TAXIROUTE_LINEFACTOR_2;
		BLx, BLy, BRy = (w / l) * sc, s * s, (l / w) * sc;
		BRx, TLx, TLy, TRx = 1 - BLy, BLy, 1 - BRy, 1 - BLx; 
		TRy = BRx;
	else
		Bwid = ((l * c) + (w * s)) * TAXIROUTE_LINEFACTOR_2;
		Bhgt = ((w * c) + (l * s)) * TAXIROUTE_LINEFACTOR_2;
		BLx, BLy, BRx = s * s, -(l / w) * sc, 1 + (w / l) * sc;
		BRy, TLx, TLy, TRy = BLx, 1 - BRx, 1 - BLx, 1 - BLy;
		TRx = TLy;
	end

	-- Set texture coordinates and anchors
	T:ClearAllPoints();
	T:SetTexCoord(TLx, TLy, BLx, BLy, TRx, TRy, BRx, BRy);
	T:SetPoint("BOTTOMLEFT", C, relPoint, cx - Bwid, cy - Bhgt);
	T:SetPoint("TOPRIGHT",   C, relPoint, cx + Bwid, cy + Bhgt);
	T:Show()
	return T
end

function G:HideLines(C)
	if C.Routes_Lines then
		for i = #C.Routes_Lines_Used, 1, -1 do
			C.Routes_Lines_Used[i]:Hide()
			tinsert(C.Routes_Lines,tremove(C.Routes_Lines_Used))
		end
	end
end

-- vim: ts=4 noexpandtab