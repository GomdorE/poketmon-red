"""Export graphics and data from the pokered disassembly into the Godot project.

Usage (from pokered-godot):
    python tools/export_data.py

Reads ../pokered-master (English disassembly) and ../pokered-korean (Korean fork,
used for Hangul font, charmap and translated text). Writes:
    assets/gb/*.png          tile sheets as 8-bit grayscale (0=black ... 255=white)
    assets/gb/korean_font.png 8x16 Hangul glyph atlas, 128 glyphs per row
    assets/data/*.json       charmap, text, maps, tilesets, pokemon, moves, types

PH-INTENT: the Godot side renders Game Boy tiles only. Every pixel and every
string shown in game must come from these exports, never from hand-drawn art,
so that the port stays identical to the original ROM data.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import sys
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent
MASTER = (PROJECT.parent / "pokered-master").resolve()
KOREAN = (PROJECT.parent / "pokered-korean").resolve()
OUT_GB = PROJECT / "assets" / "gb"
OUT_DATA = PROJECT / "assets" / "data"


def log(msg: str) -> None:
    print(msg, flush=True)


# ---------------------------------------------------------------------------
# graphics
# ---------------------------------------------------------------------------

def to_gray(src: Path) -> Image.Image:
    """Return an 8-bit grayscale image with exactly the four GB shades."""
    im = Image.open(src)
    if im.mode == "1":
        im = im.convert("L")
    elif im.mode == "P":
        im = im.convert("RGBA").convert("L")
    elif im.mode != "L":
        im = im.convert("L")
    # snap to 0 / 85 / 170 / 255
    return im.point(lambda v: (round(v / 85) * 85) if v < 255 else 255)


# Tile sheets referenced by tile id are decoded from the raw ROM tile data
# (.2bpp / .1bpp) so that ids used by the original code (tilemaps, OAM lists,
# blocksets, charmap) match. Pictures that are only ever drawn whole stay PNG.
RAW_SHEETS = {
    # splash / intro / title
    "copyright": "gfx/splash/copyright.2bpp",
    "falling_star": "gfx/splash/falling_star.2bpp",
    "gamefreak_logo": "gfx/splash/gamefreak_logo.2bpp",
    "gamefreak_presents": "gfx/splash/gamefreak_presents.2bpp",
    "gengar": "gfx/intro/gengar.2bpp",
    "nidorino_1": "gfx/intro/red_nidorino_1.2bpp",
    "nidorino_2": "gfx/intro/red_nidorino_2.2bpp",
    "nidorino_3": "gfx/intro/red_nidorino_3.2bpp",
    "pokemon_logo": "gfx/title/pokemon_logo.2bpp",
    "red_version": "gfx/title/red_version.1bpp",
    "title_player": "gfx/title/player.2bpp",
    "gamefreak_inc": "gfx/title/gamefreak_inc.2bpp",
    "move_anim_0": "gfx/battle/move_anim_0.2bpp",
    "move_anim_1": "gfx/battle/move_anim_1.2bpp",
    # fonts
    "font": "gfx/font/font.1bpp",
    "font_extra": "gfx/font/font_extra.2bpp",
    "font_battle_extra": "gfx/font/font_battle_extra.2bpp",
    "font_ed": "gfx/font/ED.1bpp",
    # battle
    "battle_hud_1": "gfx/battle/battle_hud_1.1bpp",
    "battle_hud_2": "gfx/battle/battle_hud_2.1bpp",
    "battle_hud_3": "gfx/battle/battle_hud_3.1bpp",
    "balls": "gfx/battle/balls.2bpp",
    "pokedex_tiles": "gfx/pokedex/pokedex.2bpp",
    # emotes
    "heal_machine": "gfx/overworld/heal_machine.2bpp",
    "emote_shock": "gfx/emotes/shock.2bpp",
    "emote_question": "gfx/emotes/question.2bpp",
    "emote_happy": "gfx/emotes/happy.2bpp",
    # animated overworld tiles
    # party menu icons (engine/gfx/mon_icons.asm) and the town map (engine/items/town_map.asm)
    "icon_bug": "gfx/icons/bug.2bpp",
    "icon_plant": "gfx/icons/plant.2bpp",
    "icon_snake": "gfx/icons/snake.2bpp",
    "icon_quadruped": "gfx/icons/quadruped.2bpp",
    "town_map": "gfx/town_map/town_map.2bpp",
    "town_map_cursor": "gfx/town_map/town_map_cursor.1bpp",
    "mon_nest_icon": "gfx/town_map/mon_nest_icon.1bpp",
    "font_p": "gfx/font/P.1bpp",
    "ledge_shadow": "gfx/overworld/shadow.1bpp",
    "town_map_up_arrow": "gfx/town_map/up_arrow.1bpp",
    "boulder_smoke": "gfx/overworld/smoke.2bpp",
    "red_fish_front": "gfx/overworld/red_fish_front.2bpp",
    "red_fish_back": "gfx/overworld/red_fish_back.2bpp",
    "red_fish_side": "gfx/overworld/red_fish_side.2bpp",
    "fishing_rod": "gfx/overworld/fishing_rod.2bpp",
    "cable_ball": "gfx/trade/cable_ball.2bpp",
    "trade_bubble": "gfx/trade/bubble.2bpp",
    "flower1": "gfx/tilesets/flower/flower1.2bpp",
    "flower2": "gfx/tilesets/flower/flower2.2bpp",
    "flower3": "gfx/tilesets/flower/flower3.2bpp",
    # trainer card (StartMenu_TrainerInfo)
    "trainer_info": "gfx/trainer_card/trainer_info.2bpp",
    "badges": "gfx/trainer_card/badges.2bpp",
    "badge_numbers": "gfx/trainer_card/badge_numbers.2bpp",
    "blank_leader_names": "gfx/trainer_card/blank_leader_names.2bpp",
    "circle_tile": "gfx/trainer_card/circle_tile.2bpp",
    # the Game Corner slot machines (engine/slots/slot_machine.asm) and the Rocket Hideout
    # spinner arrows (engine/overworld/spinners.asm)
    "slots_1": "gfx/slots/red_slots_1.2bpp",
    "slots_2": "gfx/slots/red_slots_2.2bpp",
    "spinner_arrows": "gfx/overworld/spinners.2bpp",
}
GRAPHICS = {
    # pics (drawn whole; row-major 8x8 tiles, 7 per row)
    "pic_oak": "gfx/trainers/prof.oak.png",
    "pic_rival1": "gfx/trainers/rival1.png",
    "pic_red": "gfx/player/red.png",
    "pic_red_back": "gfx/player/redb.png",
    "pic_shrink1": "gfx/player/shrink1.png",
    "pic_shrink2": "gfx/player/shrink2.png",
    "pic_ghost": "gfx/battle/ghost.png",   # the unidentified ghost of Pokémon Tower
}


def decode_tiles(path: Path) -> list[list[int]]:
    """Decode a .2bpp or .1bpp file into a list of 64-entry index lists."""
    data = path.read_bytes()
    tiles = []
    if path.suffix == ".1bpp":
        for t in range(len(data) // 8):
            px = []
            for y in range(8):
                b = data[t * 8 + y]
                for x in range(8):
                    px.append(3 if b & (0x80 >> x) else 0)
            tiles.append(px)
    else:
        for t in range(len(data) // 16):
            px = []
            for y in range(8):
                lo = data[t * 16 + y * 2]
                hi = data[t * 16 + y * 2 + 1]
                for x in range(8):
                    px.append(((hi >> (7 - x)) & 1) * 2 + ((lo >> (7 - x)) & 1))
            tiles.append(px)
    return tiles


def tiles_to_image(tiles: list[list[int]], per_row: int = 16) -> Image.Image:
    rows = (len(tiles) + per_row - 1) // per_row
    im = Image.new("L", (per_row * 8, max(1, rows) * 8), 255)
    px = im.load()
    for t, tile in enumerate(tiles):
        ox = (t % per_row) * 8
        oy = (t // per_row) * 8
        for i, v in enumerate(tile):
            px[ox + i % 8, oy + i // 8] = 255 - v * 85
    return im

POKEMON_PICS = [
    "bulbasaur", "charmander", "squirtle", "weedle", "nidoranm", "scyther", "pikachu",
    "clefairy", "rhydon", "abra", "gastly", "ditto", "pidgeotto", "onix", "ponyta",
    "magikarp", "nidorino", "nidorina", "pidgey", "rattata",
]
POKEMON_BACK_PICS = ["bulbasaur", "charmander", "squirtle", "nidorino"]

SPRITES = sorted(p.stem for p in (MASTER / "gfx" / "sprites").glob("*.2bpp"))

TILESET_FILES = {
    "OVERWORLD": ("overworld", "overworld"),
    "REDS_HOUSE_1": ("reds_house", "reds_house"),
    "REDS_HOUSE_2": ("reds_house", "reds_house"),
    "DOJO": ("gym", "gym"),
    "HOUSE": ("house", "house"),
    "MART": ("pokecenter", "pokecenter"),
    "POKECENTER": ("pokecenter", "pokecenter"),
    "GYM": ("gym", "gym"),
    "FOREST_GATE": ("gate", "gate"),
    "GATE": ("gate", "gate"),
    "FOREST": ("forest", "forest"),
    "MUSEUM": ("gate", "gate"),
    "CAVERN": ("cavern", "cavern"),
    "CLUB": ("club", "club"),
    "INTERIOR": ("interior", "interior"),
    "SHIP": ("ship", "ship"),
    "UNDERGROUND": ("underground", "underground"),
    "SHIP_PORT": ("ship_port", "ship_port"),
    "CEMETERY": ("cemetery", "cemetery"),
    "LOBBY": ("lobby", "lobby"),
    "MANSION": ("mansion", "mansion"),
    "FACILITY": ("facility", "facility"),
    "LAB": ("lab", "lab"),
}
TILESET_COLL_LABEL = {
    "OVERWORLD": "Overworld_Coll",
    "REDS_HOUSE_1": "RedsHouse1_Coll",
    "REDS_HOUSE_2": "RedsHouse2_Coll",
    "DOJO": "Dojo_Coll",
    "HOUSE": "House_Coll",
    "MART": "Mart_Coll",
    "POKECENTER": "Pokecenter_Coll",
    "GYM": "Gym_Coll",
    "FOREST_GATE": "ForestGate_Coll",
    "GATE": "Gate_Coll",
    "FOREST": "Forest_Coll",
    "MUSEUM": "Museum_Coll",
    "CAVERN": "Cavern_Coll",
    "CLUB": "Club_Coll",
    "INTERIOR": "Interior_Coll",
    "SHIP": "Ship_Coll",
    "UNDERGROUND": "Underground_Coll",
    "SHIP_PORT": "ShipPort_Coll",
    "CEMETERY": "Cemetery_Coll",
    "LOBBY": "Lobby_Coll",
    "MANSION": "Mansion_Coll",
    "FACILITY": "Facility_Coll",
    "LAB": "Lab_Coll",
}
TILESET_INDEX = {  # order of the Tilesets table (constants/tileset_constants.asm)
    "OVERWORLD": 0, "REDS_HOUSE_1": 1, "MART": 2, "FOREST": 3, "REDS_HOUSE_2": 4, "DOJO": 5,
    "POKECENTER": 6, "GYM": 7, "HOUSE": 8, "FOREST_GATE": 9, "MUSEUM": 10, "UNDERGROUND": 11,
    "GATE": 12, "SHIP": 13, "SHIP_PORT": 14, "CEMETERY": 15, "INTERIOR": 16, "CAVERN": 17,
    "LOBBY": 18, "MANSION": 19, "LAB": 20, "CLUB": 21, "FACILITY": 22, "PLATEAU": 23,
}
TILESET_GRASS = {"OVERWORLD": 0x52, "FOREST": 0x20, "CAVERN": -1, "CLUB": -1, "INTERIOR": -1, "SHIP": -1}
# tileset_headers.asm counter tiles (talking across a counter)
TILESET_COUNTER = {"DOJO": [0x3A], "MART": [0x18, 0x19, 0x1E], "POKECENTER": [0x18, 0x19, 0x1E], "GYM": [0x3A],
                   "FOREST_GATE": [0x17, 0x32], "GATE": [0x17, 0x32], "MUSEUM": [0x17, 0x32],
                   "CLUB": [0x07, 0x17], "CAVERN": [], "INTERIOR": [], "SHIP": [], "CEMETERY": [0x12],
                   "LOBBY": [0x15, 0x36], "MANSION": [], "FACILITY": [0x12], "LAB": []}

MAPS = {
    "PALLET_TOWN": "PalletTown",
    "REDS_HOUSE_1F": "RedsHouse1F",
    "REDS_HOUSE_2F": "RedsHouse2F",
    "OAKS_LAB": "OaksLab",
    "BLUES_HOUSE": "BluesHouse",
    "ROUTE_1": "Route1",
    "ROUTE_21": "Route21",
    "VIRIDIAN_CITY": "ViridianCity",
    "VIRIDIAN_POKECENTER": "ViridianPokecenter",
    "VIRIDIAN_MART": "ViridianMart",
    "VIRIDIAN_SCHOOL_HOUSE": "ViridianSchoolHouse",
    "VIRIDIAN_NICKNAME_HOUSE": "ViridianNicknameHouse",
    "VIRIDIAN_GYM": "ViridianGym",
    "ROUTE_2": "Route2",
    "ROUTE_22": "Route22",
    "VIRIDIAN_FOREST_SOUTH_GATE": "ViridianForestSouthGate",
    "VIRIDIAN_FOREST": "ViridianForest",
    # chapter 3: Viridian Forest north gate, Pewter City and Brock
    "VIRIDIAN_FOREST_NORTH_GATE": "ViridianForestNorthGate",
    "PEWTER_CITY": "PewterCity",
    "PEWTER_GYM": "PewterGym",
    "PEWTER_MART": "PewterMart",
    "PEWTER_POKECENTER": "PewterPokecenter",
    "PEWTER_NIDORAN_HOUSE": "PewterNidoranHouse",
    "PEWTER_SPEECH_HOUSE": "PewterSpeechHouse",
    "MUSEUM_1F": "Museum1F",
    "MUSEUM_2F": "Museum2F",
    # chapter 4: Route 3 through Bill's cape
    "ROUTE_3": "Route3",
    "MT_MOON_POKECENTER": "MtMoonPokecenter",
    "MT_MOON_1F": "MtMoon1F",
    "MT_MOON_B1F": "MtMoonB1F",
    "MT_MOON_B2F": "MtMoonB2F",
    "ROUTE_4": "Route4",
    "CERULEAN_CITY": "CeruleanCity",
    "CERULEAN_POKECENTER": "CeruleanPokecenter",
    "CERULEAN_MART": "CeruleanMart",
    "CERULEAN_GYM": "CeruleanGym",
    "CERULEAN_TRADE_HOUSE": "CeruleanTradeHouse",
    "CERULEAN_TRASHED_HOUSE": "CeruleanTrashedHouse",
    "CERULEAN_BADGE_HOUSE": "CeruleanBadgeHouse",
    "BIKE_SHOP": "BikeShop",
    "ROUTE_24": "Route24",
    "ROUTE_25": "Route25",
    "BILLS_HOUSE": "BillsHouse",
    # chapter 5: Route 9, Route 10 (to the Rock Tunnel entrance) and its Pokémon Center
    "ROUTE_9": "Route9",
    "ROUTE_10": "Route10",
    "ROCK_TUNNEL_POKECENTER": "RockTunnelPokecenter",
    # chapter 5: Routes 5 and 6, their gates, the Underground Path and the Daycare
    "ROUTE_5": "Route5",
    "ROUTE_5_GATE": "Route5Gate",
    "UNDERGROUND_PATH_ROUTE_5": "UndergroundPathRoute5",
    "DAYCARE": "Daycare",
    "UNDERGROUND_PATH_NORTH_SOUTH": "UndergroundPathNorthSouth",
    "UNDERGROUND_PATH_ROUTE_6": "UndergroundPathRoute6",
    "ROUTE_6_GATE": "Route6Gate",
    "ROUTE_6": "Route6",
    # chapter 5: Vermilion City and the S.S. Anne
    "VERMILION_CITY": "VermilionCity",
    "VERMILION_POKECENTER": "VermilionPokecenter",
    "POKEMON_FAN_CLUB": "PokemonFanClub",
    "VERMILION_MART": "VermilionMart",
    "VERMILION_GYM": "VermilionGym",
    "VERMILION_PIDGEY_HOUSE": "VermilionPidgeyHouse",
    "VERMILION_DOCK": "VermilionDock",
    "VERMILION_TRADE_HOUSE": "VermilionTradeHouse",
    "VERMILION_OLD_ROD_HOUSE": "VermilionOldRodHouse",
    "SS_ANNE_1F": "SSAnne1F",
    "SS_ANNE_2F": "SSAnne2F",
    "SS_ANNE_3F": "SSAnne3F",
    "SS_ANNE_B1F": "SSAnneB1F",
    "SS_ANNE_BOW": "SSAnneBow",
    "SS_ANNE_KITCHEN": "SSAnneKitchen",
    "SS_ANNE_CAPTAINS_ROOM": "SSAnneCaptainsRoom",
    "SS_ANNE_1F_ROOMS": "SSAnne1FRooms",
    "SS_ANNE_2F_ROOMS": "SSAnne2FRooms",
    "SS_ANNE_B1F_ROOMS": "SSAnneB1FRooms",
    # chapter 6: Route 11, Diglett's Cave, the east end of Route 2
    "ROUTE_11": "Route11",
    "ROUTE_11_GATE_1F": "Route11Gate1F",
    "ROUTE_11_GATE_2F": "Route11Gate2F",
    "DIGLETTS_CAVE_ROUTE_11": "DiglettsCaveRoute11",
    "DIGLETTS_CAVE": "DiglettsCave",
    "DIGLETTS_CAVE_ROUTE_2": "DiglettsCaveRoute2",
    "ROUTE_2_TRADE_HOUSE": "Route2TradeHouse",
    "ROUTE_2_GATE": "Route2Gate",
    # chapter 6: Rock Tunnel and Lavender Town
    "ROCK_TUNNEL_1F": "RockTunnel1F",
    "ROCK_TUNNEL_B1F": "RockTunnelB1F",
    "LAVENDER_TOWN": "LavenderTown",
    "LAVENDER_POKECENTER": "LavenderPokecenter",
    "LAVENDER_MART": "LavenderMart",
    "NAME_RATERS_HOUSE": "NameRatersHouse",
    "MR_FUJIS_HOUSE": "MrFujisHouse",
    "LAVENDER_CUBONE_HOUSE": "LavenderCuboneHouse",
    "POKEMON_TOWER_1F": "PokemonTower1F",
    "POKEMON_TOWER_2F": "PokemonTower2F",
    # chapter 7: Routes 7 and 8, their Saffron gates, the Underground Path (west-east)
    "ROUTE_7": "Route7",
    "ROUTE_7_GATE": "Route7Gate",
    "UNDERGROUND_PATH_ROUTE_7": "UndergroundPathRoute7",
    "UNDERGROUND_PATH_WEST_EAST": "UndergroundPathWestEast",
    "UNDERGROUND_PATH_ROUTE_8": "UndergroundPathRoute8",
    "ROUTE_8_GATE": "Route8Gate",
    "ROUTE_8": "Route8",
    # chapter 7: Celadon City
    "CELADON_CITY": "CeladonCity",
    "CELADON_MART_1F": "CeladonMart1F",
    "CELADON_MART_2F": "CeladonMart2F",
    "CELADON_MART_3F": "CeladonMart3F",
    "CELADON_MART_4F": "CeladonMart4F",
    "CELADON_MART_5F": "CeladonMart5F",
    "CELADON_MART_ELEVATOR": "CeladonMartElevator",
    "CELADON_MART_ROOF": "CeladonMartRoof",
    "CELADON_MANSION_1F": "CeladonMansion1F",
    "CELADON_MANSION_2F": "CeladonMansion2F",
    "CELADON_MANSION_3F": "CeladonMansion3F",
    "CELADON_MANSION_ROOF": "CeladonMansionRoof",
    "CELADON_MANSION_ROOF_HOUSE": "CeladonMansionRoofHouse",
    "CELADON_POKECENTER": "CeladonPokecenter",
    "CELADON_GYM": "CeladonGym",
    "GAME_CORNER": "GameCorner",
    "GAME_CORNER_PRIZE_ROOM": "GameCornerPrizeRoom",
    "CELADON_DINER": "CeladonDiner",
    "CELADON_CHIEF_HOUSE": "CeladonChiefHouse",
    "CELADON_HOTEL": "CeladonHotel",
    "ROCKET_HIDEOUT_B1F": "RocketHideoutB1F",
    "ROCKET_HIDEOUT_B2F": "RocketHideoutB2F",
    "ROCKET_HIDEOUT_B3F": "RocketHideoutB3F",
    "ROCKET_HIDEOUT_B4F": "RocketHideoutB4F",
    "ROCKET_HIDEOUT_ELEVATOR": "RocketHideoutElevator",
    # chapter 8: Pokémon Tower 3F-7F, Route 12
    "POKEMON_TOWER_3F": "PokemonTower3F",
    "POKEMON_TOWER_4F": "PokemonTower4F",
    "POKEMON_TOWER_5F": "PokemonTower5F",
    "POKEMON_TOWER_6F": "PokemonTower6F",
    "POKEMON_TOWER_7F": "PokemonTower7F",
    "ROUTE_12": "Route12",
    "ROUTE_12_GATE_1F": "Route12Gate1F",
    "ROUTE_12_GATE_2F": "Route12Gate2F",
    "ROUTE_12_SUPER_ROD_HOUSE": "Route12SuperRodHouse",
    # chapter 9: Saffron City, the Fighting Dojo, Sabrina's gym, Silph Co.
    "SAFFRON_CITY": "SaffronCity",
    "SAFFRON_POKECENTER": "SaffronPokecenter",
    "SAFFRON_MART": "SaffronMart",
    "SAFFRON_PIDGEY_HOUSE": "SaffronPidgeyHouse",
    "MR_PSYCHICS_HOUSE": "MrPsychicsHouse",
    "COPYCATS_HOUSE_1F": "CopycatsHouse1F",
    "COPYCATS_HOUSE_2F": "CopycatsHouse2F",
    "FIGHTING_DOJO": "FightingDojo",
    "SAFFRON_GYM": "SaffronGym",
    "SILPH_CO_1F": "SilphCo1F",
    "SILPH_CO_2F": "SilphCo2F",
    "SILPH_CO_3F": "SilphCo3F",
    "SILPH_CO_4F": "SilphCo4F",
    "SILPH_CO_5F": "SilphCo5F",
    "SILPH_CO_6F": "SilphCo6F",
    "SILPH_CO_7F": "SilphCo7F",
    "SILPH_CO_8F": "SilphCo8F",
    "SILPH_CO_9F": "SilphCo9F",
    "SILPH_CO_10F": "SilphCo10F",
    "SILPH_CO_11F": "SilphCo11F",
    "SILPH_CO_ELEVATOR": "SilphCoElevator",
    # chapter 10: Routes 13-18 around Fuchsia City, the Cycling Road and its gates
    "ROUTE_13": "Route13",
    "ROUTE_14": "Route14",
    "ROUTE_15": "Route15",
    "ROUTE_15_GATE_1F": "Route15Gate1F",
    "ROUTE_15_GATE_2F": "Route15Gate2F",
    "ROUTE_16": "Route16",
    "ROUTE_16_GATE_1F": "Route16Gate1F",
    "ROUTE_16_GATE_2F": "Route16Gate2F",
    "ROUTE_16_FLY_HOUSE": "Route16FlyHouse",
    "ROUTE_17": "Route17",
    "ROUTE_18": "Route18",
    "ROUTE_18_GATE_1F": "Route18Gate1F",
    "ROUTE_18_GATE_2F": "Route18Gate2F",
    # chapter 11: Fuchsia City and the Safari Zone
    "FUCHSIA_CITY": "FuchsiaCity",
    "FUCHSIA_MART": "FuchsiaMart",
    "FUCHSIA_BILLS_GRANDPAS_HOUSE": "FuchsiaBillsGrandpasHouse",
    "FUCHSIA_POKECENTER": "FuchsiaPokecenter",
    "WARDENS_HOUSE": "WardensHouse",
    "SAFARI_ZONE_GATE": "SafariZoneGate",
    "FUCHSIA_GYM": "FuchsiaGym",
    "FUCHSIA_MEETING_ROOM": "FuchsiaMeetingRoom",
    "FUCHSIA_GOOD_ROD_HOUSE": "FuchsiaGoodRodHouse",
    "SAFARI_ZONE_EAST": "SafariZoneEast",
    "SAFARI_ZONE_NORTH": "SafariZoneNorth",
    "SAFARI_ZONE_WEST": "SafariZoneWest",
    "SAFARI_ZONE_CENTER": "SafariZoneCenter",
    "SAFARI_ZONE_CENTER_REST_HOUSE": "SafariZoneCenterRestHouse",
    "SAFARI_ZONE_SECRET_HOUSE": "SafariZoneSecretHouse",
    "SAFARI_ZONE_WEST_REST_HOUSE": "SafariZoneWestRestHouse",
    "SAFARI_ZONE_EAST_REST_HOUSE": "SafariZoneEastRestHouse",
    "SAFARI_ZONE_NORTH_REST_HOUSE": "SafariZoneNorthRestHouse",
}


def export_graphics() -> None:
    OUT_GB.mkdir(parents=True, exist_ok=True)
    for name, rel in RAW_SHEETS.items():
        tiles_to_image(decode_tiles(MASTER / rel)).save(OUT_GB / f"{name}.png")
    for name, rel in GRAPHICS.items():
        to_gray(MASTER / rel).save(OUT_GB / f"{name}.png")
    for path in sorted((MASTER / "gfx" / "pokemon" / "front").glob("*.png")):
        to_gray(path).save(OUT_GB / f"mon_{path.stem}.png")
    for path in sorted((MASTER / "gfx" / "pokemon" / "back").glob("*b.png")):
        to_gray(path).save(OUT_GB / f"monb_{path.stem[:-1]}.png")
    for path in sorted((MASTER / "gfx" / "trainers").glob("*.png")):
        to_gray(path).save(OUT_GB / f"pic_trainer_{path.stem}.png")
    for spr in SPRITES:
        # 4 tiles per 16x16 frame: top-left, top-right, bottom-left, bottom-right
        tiles_to_image(decode_tiles(MASTER / f"gfx/sprites/{spr}.2bpp"), 4).save(OUT_GB / f"spr_{spr}.png")
    for key, (gfx, _blk) in TILESET_FILES.items():
        tiles_to_image(decode_tiles(MASTER / f"gfx/tilesets/{gfx}.2bpp")).save(OUT_GB / f"tileset_{gfx}.png")
    # TradingAnimationGraphics: game_boy.2bpp + link_cable.2bpp, loaded at BG tile $31
    trade = decode_tiles(MASTER / "gfx/trade/game_boy.2bpp") + decode_tiles(MASTER / "gfx/trade/link_cable.2bpp")
    tiles_to_image(trade).save(OUT_GB / "trade_gfx.png")
    # water: tile $14 of each tileset with TILEANIM_WATER* rotated by 0..7 pixels
    # (UpdateMovingBgTiles rotates whatever is in VRAM tile $14)
    anims = parse_tileset_anims()
    for key, (gfx, _blk) in TILESET_FILES.items():
        if anims.get(key, 0) == 0:
            continue
        water = decode_tiles(MASTER / f"gfx/tilesets/{gfx}.2bpp")[0x14]
        variants = []
        for shift in range(8):
            variants.append([water[y * 8 + ((x - shift) % 8)] for y in range(8) for x in range(8)])
        tiles_to_image(variants, 8).save(OUT_GB / f"water_anim_{gfx}.png")
    log(f"graphics: {len(RAW_SHEETS)} raw sheets, {len(GRAPHICS)} pics, {len(POKEMON_PICS)} mons, {len(SPRITES)} sprites")


# ---------------------------------------------------------------------------
# charmap and Korean font
# ---------------------------------------------------------------------------

CHARMAP_RE = re.compile(r'^\s*charmap\s+"((?:[^"\\]|\\.)*)",\s*\$([0-9A-Fa-f]+)')


def parse_charmap(path: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = CHARMAP_RE.match(line)
        if not m:
            continue
        token = m.group(1).replace('\\"', '"')
        code = int(m.group(2), 16)
        # keep the first mapping of a token (later Japanese kana duplicates reuse codes)
        if token not in out:
            out[token] = code
    return out


def export_charmap_and_font() -> dict[str, int]:
    charmap = parse_charmap(KOREAN / "constants" / "charmap.asm")
    OUT_DATA.mkdir(parents=True, exist_ok=True)
    (OUT_DATA / "charmap.json").write_text(json.dumps(charmap, ensure_ascii=False, indent=0), encoding="utf-8")

    data = (KOREAN / "data" / "korean" / "korean.1bpp.bin").read_bytes()
    glyph_count = len(data) // 16
    per_row = 128
    rows = (glyph_count + per_row - 1) // per_row
    atlas = Image.new("L", (per_row * 8, rows * 16), 255)
    px = atlas.load()
    for g in range(glyph_count):
        gx = (g % per_row) * 8
        gy = (g // per_row) * 16
        for row in range(16):
            byte = data[g * 16 + row]
            for bit in range(8):
                if byte & (0x80 >> bit):
                    px[gx + bit, gy + row] = 0
    atlas.save(OUT_GB / "korean_font.png")
    log(f"charmap: {len(charmap)} tokens, korean glyphs: {glyph_count}")
    return charmap


# ---------------------------------------------------------------------------
# text
# ---------------------------------------------------------------------------

TEXT_CMDS = {
    "text": "text", "ktext": "text",
    "line": "line", "kline": "line",
    "cont": "cont", "kcont": "cont",
    "para": "para", "kpara": "para",
    "next": "next", "knext": "next",
    "page": "page", "kpage": "page",
}
STR_RE = re.compile(r'"((?:[^"\\]|\\.)*)"')


def parse_text_files(root: Path) -> dict[str, list]:
    files = sorted((root / "data" / "text").glob("*.asm")) + sorted((root / "text").glob("*.asm"))
    files += [root / "data" / "pokemon" / "dex_text.asm"]
    # shared map texts (BoulderText, MartSignText, ... used from map text pointer tables)
    if (root / "home" / "overworld_text.asm").exists():
        files += [root / "home" / "overworld_text.asm"]
    # script-local text labels of the exported maps (text_far + sound_* chains such as
    # PewterGymBrockReceivedBoulderBadgeText); `.local` labels are skipped
    files += [root / "scripts" / f"{n}.asm" for n in MAPS.values() if (root / "scripts" / f"{n}.asm").exists()]
    texts: dict[str, list] = {}
    current: str | None = None
    for f in files:
        try:
            lines = f.read_text(encoding="utf-8").splitlines()
        except UnicodeDecodeError:
            lines = f.read_text(encoding="latin-1").splitlines()
        for raw in lines:
            line = raw.split(";")[0].rstrip()
            if not line.strip():
                continue
            m = re.match(r"^(_?[A-Za-z0-9_.]+)::?\s*$", line)
            if m and not line.startswith(("\t", " ")):
                current = m.group(1)
                if current.startswith(".") or (current in texts and f.parent.name == "scripts"):
                    current = None
                    continue
                texts[current] = []
                continue
            if current is None:
                continue
            parts = line.strip().split(None, 1)
            op = parts[0]
            arg = parts[1] if len(parts) > 1 else ""
            if op in TEXT_CMDS:
                sm = STR_RE.search(arg)
                texts[current].append([TEXT_CMDS[op], sm.group(1) if sm else ""])
            elif op == "korean_text_bytes":
                sm = STR_RE.search(arg)
                texts[current].append(["raw", sm.group(1) if sm else ""])
            elif op == "db":
                sm = STR_RE.search(arg)
                if sm:
                    texts[current].append(["raw", sm.group(1)])
            elif op in ("prompt", "done", "text_end", "text_start", "text_asm", "text_promptbutton", "text_waitbutton"):
                texts[current].append([op, ""])
            elif op == "text_far":
                texts[current].append(["far", arg.strip()])
            elif op == "text_ram":
                texts[current].append(["ram", arg.strip()])
            elif op.startswith("sound_"):
                texts[current].append(["sound", op])
            elif op in ("text_pause", "text_dots", "text_bcd", "text_decimal", "text_num", "text_low", "text_asm"):
                texts[current].append([op, arg.strip()])
    return texts


def export_texts() -> None:
    en = parse_text_files(MASTER)
    ko = parse_text_files(KOREAN)
    (OUT_DATA / "text_en.json").write_text(json.dumps(en, ensure_ascii=False), encoding="utf-8")
    (OUT_DATA / "text_ko.json").write_text(json.dumps(ko, ensure_ascii=False), encoding="utf-8")
    log(f"texts: en {len(en)} labels, ko {len(ko)} labels")


# ---------------------------------------------------------------------------
# maps and tilesets
# ---------------------------------------------------------------------------

def parse_const_list(path: Path, macro: str) -> list[str]:
    names: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split(";")[0]
        m = re.match(rf"^\s*{macro}\s+([A-Z0-9_]+)", line)
        if m:
            names.append(m.group(1))
    return names


def parse_map_sizes() -> dict[str, tuple[int, int]]:
    sizes = {}
    for line in (MASTER / "constants" / "map_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*map_const\s+([A-Z0-9_]+),\s*(\d+),\s*(\d+)", line.split(";")[0])
        if m:
            sizes[m.group(1)] = (int(m.group(2)), int(m.group(3)))
    return sizes


def parse_coll_list(label: str) -> list[int]:
    text = (MASTER / "data" / "tilesets" / "collision_tile_ids.asm").read_text(encoding="utf-8")
    # labels can be stacked (RedsHouse1_Coll:: RedsHouse2_Coll:: coll_tiles ...)
    idx = text.index(f"{label}::")
    rest = text[idx:]
    m = re.search(r"coll_tiles\s*([^\n]*)", rest)
    args = m.group(1).split(";")[0].strip()
    return [int(x.strip().replace("$", ""), 16) for x in args.split(",") if x.strip()]


def parse_tile_id_list(path: Path, label: str, macro: str) -> list[int]:
    """The tile ids under `label`: `macro`/`db` lines, continuing past a "; fallthrough" into
    the next label (FacilityWarpTileIDs -> CemeteryWarpTileIDs -> UndergroundWarpTileIDs)."""
    text = path.read_text(encoding="utf-8")
    anchor = f"{label}:"
    if anchor not in text:
        return []
    out: list[int] = []
    fallthrough = False
    stacked = True   # labels right after a label share its list (.ForestGateWarpTileIDs: .GateWarpTileIDs:)
    for line in text[text.index(anchor):].splitlines()[1:]:
        if re.match(r"^\s*;\s*fallthrough", line):
            fallthrough = True
            continue
        if re.match(r"^\.?\w+:", line):
            if not fallthrough and not stacked:
                break
            fallthrough = False
            stacked = True
            continue
        if line.strip():
            stacked = False
        m = re.match(rf"^\s*(?:{macro}|db)\s+([^\n]*)", line)
        if m:
            args = m.group(1).split(";")[0].strip()
            out += [int(x.strip().replace("$", ""), 16) for x in args.split(",") if x.strip()]
    return out


WARP_LABELS = {
    "OVERWORLD": ".OverworldWarpTileIDs", "REDS_HOUSE_1": ".RedsHouse1WarpTileIDs",
    "REDS_HOUSE_2": ".RedsHouse2WarpTileIDs", "DOJO": ".DojoWarpTileIDs", "HOUSE": ".HouseWarpTileIDs",
    "MART": ".MartWarpTileIDs", "POKECENTER": ".PokecenterWarpTileIDs", "GYM": ".GymWarpTileIDs",
    "FOREST_GATE": ".ForestGateWarpTileIDs", "GATE": ".GateWarpTileIDs", "FOREST": ".ForestWarpTileIDs",
    "MUSEUM": ".MuseumWarpTileIDs",
    "CAVERN": ".CavernWarpTileIDs",
    "CLUB": ".ClubWarpTileIDs",
    "INTERIOR": ".InteriorWarpTileIDs",
    "SHIP": ".ShipWarpTileIDs",
    "UNDERGROUND": ".UndergroundWarpTileIDs",
    "SHIP_PORT": ".ShipPortWarpTileIDs",
    "CEMETERY": ".CemeteryWarpTileIDs",
    "LOBBY": ".LobbyWarpTileIDs",
    "MANSION": ".MansionWarpTileIDs",
    "FACILITY": ".FacilityWarpTileIDs",
    "LAB": ".LabWarpTileIDs",
}
DOOR_LABELS = {"OVERWORLD": ".OverworldDoorTileIDs", "HOUSE": ".HouseDoorTileIDs", "MART": ".MartDoorTileIDs",
               "POKECENTER": ".MartDoorTileIDs", "FOREST": ".ForestDoorTileIDs",
               "FOREST_GATE": ".TilesetMuseumDoorTileIDs", "MUSEUM": ".TilesetMuseumDoorTileIDs",
               "GATE": ".TilesetMuseumDoorTileIDs", "CAVERN": "__none__",
               "CLUB": "__none__", "INTERIOR": "__none__", "SHIP": ".ShipDoorTileIDs", "UNDERGROUND": "__none__", "SHIP_PORT": "__none__", "CEMETERY": "__none__",
               "LOBBY": ".LobbyDoorTileIDs", "MANSION": ".MansionDoorTileIDs", "FACILITY": ".FacilityDoorTileIDs", "LAB": ".LabDoorTileIDs"}


def parse_tileset_anims() -> dict[str, int]:
    """data/tilesets/tileset_headers.asm: tileset -> TILEANIM_NONE (0) / WATER (1) / WATER_FLOWER (2)."""
    out = {}
    kinds = {"TILEANIM_NONE": 0, "TILEANIM_WATER": 1, "TILEANIM_WATER_FLOWER": 2}
    for m in re.finditer(r"^\s*tileset\s+(\w+),.*?(TILEANIM_\w+)", (MASTER / "data" / "tilesets" / "tileset_headers.asm").read_text(encoding="utf-8"), re.M):
        key = re.sub(r"(?<=[a-z])(?=[A-Z0-9])", "_", m.group(1)).upper()
        out[key] = kinds[m.group(2)]
    return out


def export_tilesets() -> None:
    out = {}
    anims = parse_tileset_anims()
    for key, (gfx, blk) in TILESET_FILES.items():
        bst = (MASTER / "gfx" / "blocksets" / f"{blk}.bst").read_bytes()
        blocks = [list(bst[i:i + 16]) for i in range(0, len(bst), 16)]
        out[key] = {
            "gfx": f"tileset_{gfx}",
            "blocks": blocks,
            "collision": parse_coll_list(TILESET_COLL_LABEL[key]),
            "warp_tiles": parse_tile_id_list(MASTER / "data/tilesets/warp_tile_ids.asm", WARP_LABELS[key], "warp_tiles"),
            "door_tiles": parse_tile_id_list(MASTER / "data/tilesets/door_tile_ids.asm", DOOR_LABELS.get(key, "__none__"), "door_tiles"),
            "grass_tile": TILESET_GRASS.get(key, -1),
            "counter_tiles": TILESET_COUNTER.get(key, []),
            "anim": anims.get(key, 0),
        }
    (OUT_DATA / "tilesets.json").write_text(json.dumps(out), encoding="utf-8")
    log(f"tilesets: {list(out)}")


def parse_objects(name: str) -> dict:
    path = MASTER / "data" / "maps" / "objects" / f"{name}.asm"
    res = {"border_block": 0, "warps": [], "bg_events": [], "objects": [], "object_consts": []}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        if not line:
            continue
        m = re.match(r"const_export\s+([A-Z0-9_]+)", line)
        if m:
            res["object_consts"].append(m.group(1))
            continue
        m = re.match(r"db\s+\$?([0-9a-fA-F]+)", line)
        if m and "border" in raw:
            res["border_block"] = int(m.group(1), 16)
            continue
        m = re.match(r"warp_event\s+(\d+),\s*(\d+),\s*([A-Z0-9_]+),\s*(\d+)", line)
        if m:
            res["warps"].append({"x": int(m.group(1)), "y": int(m.group(2)), "map": m.group(3), "warp_id": int(m.group(4))})
            continue
        m = re.match(r"bg_event\s+(\d+),\s*(\d+),\s*([A-Z0-9_]+)", line)
        if m:
            res["bg_events"].append({"x": int(m.group(1)), "y": int(m.group(2)), "text": m.group(3)})
            continue
        m = re.match(r"object_event\s+(\d+),\s*(\d+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+)(?:,\s*([A-Z0-9_]+))?(?:,\s*(\d+))?", line)
        if m:
            res["objects"].append({
                "x": int(m.group(1)), "y": int(m.group(2)), "sprite": m.group(3), "movement": m.group(4),
                "direction": m.group(5), "text": m.group(6), "trainer": machine_item(m.group(7) or ""), "trainer_no": int(m.group(8) or 0),
            })
    return res


def parse_header(name: str) -> dict:
    path = MASTER / "data" / "maps" / "headers" / f"{name}.asm"
    res = {"tileset": "", "connections": []}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"map_header\s+\w+,\s*([A-Z0-9_]+),\s*([A-Z0-9_]+)", line)
        if m:
            res["tileset"] = m.group(2)
        m = re.match(r"connection\s+(\w+),\s*\w+,\s*([A-Z0-9_]+),\s*(-?\d+)", line)
        if m:
            res["connections"].append({"dir": m.group(1), "map": m.group(2), "offset": int(m.group(3))})
    return res


def parse_toggles() -> dict[str, list]:
    """data/maps/toggleable_objects.asm: map -> [[object name, ON?], ...] (OFF = hidden at first)."""
    out: dict[str, list] = {}
    cur = None
    for raw in (MASTER / "data" / "maps" / "toggleable_objects.asm").read_text(encoding="utf-8").splitlines():
        line = raw.split(";")[0].strip()
        m = re.match(r"toggleable_objects_for\s+([A-Z0-9_]+)", line)
        if m:
            cur = m.group(1)
            out[cur] = []
            continue
        m = re.match(r"toggle_object_state\s+([A-Z0-9_]+),\s*(ON|OFF)", line)
        if m and cur:
            out[cur].append([m.group(1), m.group(2) == "ON"])
    return out


def parse_hidden_events() -> dict[str, list]:
    """data/events/hidden_events.asm: map -> [{x, y, func, arg}] (arg = facing or text id)."""
    out: dict[str, list] = {}
    cur = None
    for line in (MASTER / "data" / "events" / "hidden_events.asm").read_text(encoding="utf-8").splitlines():
        code = line.split(";")[0].strip()
        m = re.match(r"hidden_events_for\s+([A-Z0-9_]+)", code)
        if m:
            cur = m.group(1)
            out[cur] = []
            continue
        if cur is None:
            continue
        m = re.match(r"hidden_(event|text_predef)\s+(\d+),\s*(\d+),\s*([A-Za-z0-9_]+),\s*([A-Za-z0-9_+ ]+)", code)
        if m:
            # the argument is a facing, a text id, an item, or "COIN + n" (kept as "COIN+n")
            out[cur].append({"x": int(m.group(2)), "y": int(m.group(3)), "func": m.group(4), "arg": re.sub(r"\s+", "", m.group(5))})
        elif code.startswith("db -1"):
            cur = None
    return out


def parse_trainer_headers(name: str) -> list:
    """scripts/<Map>.asm: `def_trainers N` + `trainer EVENT, range, before, end, after`.
    The flag bit (= the 1-based object index of the trainer sprite) starts at N and counts
    up per header. Text labels are resolved to their text_far targets when the local label
    is a plain `text_far X / text_end` pair; otherwise the local label is kept."""
    path = MASTER / "scripts" / f"{name}.asm"
    if not path.exists():
        return []
    src = path.read_text(encoding="utf-8")
    far = {m.group(1): m.group(2) for m in re.finditer(r"^(\w+):\n\s*text_far\s+(\w+)\n\s*text_end", src, re.M)}
    out = []
    bit = 1
    header = ""
    for raw in src.splitlines():
        line = raw.split(";")[0].rstrip()
        m = re.match(r"^(\w+TrainerHeader\w*):", line)
        if m:
            header = m.group(1)
            continue
        m = re.match(r"^\s*def_trainers(?:\s+(\d+))?", line)
        if m:
            bit = int(m.group(1) or 1)
            continue
        m = re.match(r"^\s*trainer\s+(\w+),\s*(\d+),\s*(\w+),\s*(\w+),\s*(\w+)", line)
        if m:
            out.append({
                "header": header, "sprite": bit, "event": m.group(1), "range": int(m.group(2)),
                "before": far.get(m.group(3), m.group(3)), "end": far.get(m.group(4), m.group(4)),
                "after": far.get(m.group(5), m.group(5)),
            })
            bit += 1
    return out


def parse_text_pointers(name: str) -> dict:
    """scripts/<Map>.asm `dw_const Label, TEXT_ID`: the text pointer table of a map."""
    path = MASTER / "scripts" / f"{name}.asm"
    if not path.exists():
        return {}
    return {m.group(2): m.group(1) for m in re.finditer(r"dw_const\s+(\w+),\s*(TEXT_\w+)", path.read_text(encoding="utf-8"))}


def export_maps() -> None:
    sizes = parse_map_sizes()
    toggles = parse_toggles()
    hidden = parse_hidden_events()
    out = {}
    for const, name in MAPS.items():
        w, h = sizes[const]
        blk = (MASTER / "maps" / f"{name}.blk").read_bytes()
        if name == "UndergroundPathNorthSouth" and len(blk) < w * h:
            # the .blk is 4x23 for a 4x24 map: the ROM reads its last row from the data that
            # follows it in maps.asm (the start of UndergroundPathWestEast.blk)
            blk += (MASTER / "maps" / "UndergroundPathWestEast.blk").read_bytes()[:w * h - len(blk)]
        assert len(blk) == w * h, f"{name}.blk size {len(blk)} != {w}x{h}"
        hdr = parse_header(name)
        obj = parse_objects(name)
        consts = obj.pop("object_consts")
        obj["toggles"] = [[consts.index(n), on] for n, on in toggles.get(const, []) if n in consts]
        obj["hidden_events"] = hidden.get(const, [])
        obj["trainer_headers"] = parse_trainer_headers(name)
        obj["text_pointers"] = parse_text_pointers(name)
        out[const] = {
            "name": name, "width": w, "height": h, "tileset": hdr["tileset"], "connections": hdr["connections"],
            "blocks": list(blk), **obj,
        }
    (OUT_DATA / "maps.json").write_text(json.dumps(out), encoding="utf-8")
    log(f"maps: {list(out)}")


# ---------------------------------------------------------------------------
# pokemon / moves / types
# ---------------------------------------------------------------------------

def parse_names(path: Path, macro_names: tuple[str, ...]) -> list[str]:
    names = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split(";")[0]
        for mac in macro_names:
            m = re.match(rf'^\s*{mac}\s+"((?:[^"\\]|\\.)*)"', line)
            if m:
                names.append(m.group(1))
                break
    return names


def parse_menu_icons() -> list[str]:
    """data/pokemon/menu_icons.asm: one ICON_* per dex number (MonPartyData nybbles)."""
    icons = []
    for line in (MASTER / "data" / "pokemon" / "menu_icons.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*nybble\s+(ICON_[A-Z]+)", line.split(";")[0])
        if m:
            icons.append(m.group(1))
    return icons


def parse_map_consts() -> tuple[dict[str, int], dict[str, int], int]:
    """constants/map_constants.asm: map id per constant, INDOORGROUP_* limits, FIRST_INDOOR_MAP."""
    ids: dict[str, int] = {}
    groups: dict[str, int] = {}
    first_indoor = 0
    value = 0
    for line in (MASTER / "constants" / "map_constants.asm").read_text(encoding="utf-8").splitlines():
        line = line.split(";")[0]
        m = re.match(r"^\s*map_const\s+([A-Z0-9_]+)", line)
        if m:
            ids[m.group(1)] = value
            value += 1
            continue
        m = re.match(r"^\s*end_indoor_group\s+([A-Z0-9_]+)", line)
        if m:
            groups[m.group(1)] = value
            continue
        if re.match(r"^\s*DEF FIRST_INDOOR_MAP EQU const_value", line):
            first_indoor = value
    return ids, groups, first_indoor


def export_town_map() -> None:
    """engine/items/town_map.asm data: compressed tilemap, location entries, cycle order and names."""
    ids, groups, first_indoor = parse_map_consts()
    rle = (MASTER / "gfx" / "town_map" / "town_map.rle").read_bytes()
    tilemap: list[int] = []
    for b in rle:
        if b == 0:
            break
        tilemap.extend([b >> 4] * (b & 0xF))
    external = []
    internal = []
    for line in (MASTER / "data" / "maps" / "town_map_entries.asm").read_text(encoding="utf-8").splitlines():
        line = line.split(";")[0]
        m = re.match(r"^\s*outdoor_map\s+(\d+),\s*(\d+),\s*(\w+)", line)
        if m:
            external.append([int(m.group(1)), int(m.group(2)), m.group(3)])
            continue
        m = re.match(r"^\s*indoor_map\s+([A-Z0-9_]+),\s*(\d+),\s*(\d+),\s*(\w+)", line)
        if m:
            internal.append([groups[m.group(1)], int(m.group(2)), int(m.group(3)), m.group(4)])
    order = []
    for line in (MASTER / "data" / "maps" / "town_map_order.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*db\s+([A-Z0-9_]+)", line.split(";")[0])
        if m:
            order.append(m.group(1))
    names: dict[str, dict[str, str]] = {}
    for root, lang in ((MASTER, "en"), (KOREAN, "ko")):
        for line in (root / "data" / "maps" / "names.asm").read_text(encoding="utf-8").splitlines():
            m = re.match(r'^(\w+):\s*(?:db|korean_text_bytes)\s+"([^"@]*)@?"', line.split(";")[0].strip())
            if m:
                names.setdefault(m.group(1), {})[lang] = m.group(2)
    out = {"tilemap": tilemap, "external": external, "internal": internal, "order": order, "names": names,
           "map_ids": ids, "first_indoor_map": first_indoor}
    (OUT_DATA / "town_map.json").write_text(json.dumps(out, ensure_ascii=False), encoding="utf-8")
    log(f"town map: {len(tilemap)} tiles, {len(external)} outdoor, {len(internal)} indoor entries, {len(order)} locations")


def parse_base_stats(dex_name: str) -> dict:
    path = MASTER / "data" / "pokemon" / "base_stats" / f"{dex_name}.asm"
    txt = path.read_text(encoding="utf-8")
    nums = re.search(r"db\s+(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+)\s*\n\s*;\s*hp", txt)
    types = re.search(r"db\s+([A-Z_]+),\s*([A-Z_]+)\s*;\s*type", txt)
    catch = re.search(r"db\s+(\d+)\s*;\s*catch rate", txt)
    bexp = re.search(r"db\s+(\d+)\s*;\s*base exp", txt)
    moves = re.search(r"db\s+([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+)\s*;\s*level 1 learnset", txt)
    growth = re.search(r"db\s+(GROWTH_[A-Z_]+)", txt)
    tmhm: list[str] = []
    m_tm = re.search(r"tmhm\s+((?:[^\n]*\\\n)*[^\n]*)", txt)
    if m_tm:
        tmhm = re.findall(r"[A-Z][A-Z0-9_]+", m_tm.group(1))
    return {
        "tmhm": tmhm,
        "hp": int(nums.group(1)), "atk": int(nums.group(2)), "def": int(nums.group(3)),
        "spd": int(nums.group(4)), "spc": int(nums.group(5)),
        "types": [types.group(1), types.group(2)],
        "catch_rate": int(catch.group(1)), "base_exp": int(bexp.group(1)),
        "moves": [m for m in moves.groups() if m != "NO_MOVE"],
        "growth": growth.group(1),
    }


def parse_dex_entries() -> dict[str, dict]:
    txt = (MASTER / "data" / "pokemon" / "dex_entries.asm").read_text(encoding="utf-8")
    out = {}
    for m in re.finditer(r"^(\w+)DexEntry:\n\s*db\s+\"([^\"]+)@\"\n\s*db\s+(\d+),(\d+)\n\s*dw\s+(\d+)\n\s*text_far\s+(\w+)", txt, re.M):
        out[m.group(1).upper()] = {
            "species": m.group(2), "height_ft": int(m.group(3)), "height_in": int(m.group(4)),
            "weight": int(m.group(5)), "text": m.group(6),
        }
    return out


def _evos_moves_body(internal_name: str) -> str:
    txt = (MASTER / "data" / "pokemon" / "evos_moves.asm").read_text(encoding="utf-8")
    label = f"{internal_name.title().replace('_', '')}EvosMoves:"
    # labels are CamelCase of the constant (NIDORAN_M -> NidoranMEvosMoves)
    idx = txt.find(label)
    if idx < 0:
        return ""
    body = txt[idx + len(label):]
    end = body.find("EvosMoves:")
    return body[:end] if end >= 0 else body


def parse_evos_moves(internal_name: str) -> list[list]:
    """Level-up learnset from data/pokemon/evos_moves.asm: [[level, MOVE], ...]."""
    body = _evos_moves_body(internal_name)
    if "; Learnset" in body:
        body = body[body.index("; Learnset"):]
    out = []
    for m in re.finditer(r"db\s+(\d+),\s*([A-Z0-9_]+)", body):
        out.append([int(m.group(1)), m.group(2)])
    return out


def parse_evolutions(internal_name: str) -> list[dict]:
    """[{"method": "LEVEL", "level": n, "species": X} | {"method": "ITEM", "item": I, "species": X} | {"method": "TRADE", ...}]"""
    body = _evos_moves_body(internal_name)
    if "; Learnset" in body:
        body = body[:body.index("; Learnset")]
    out = []
    for m in re.finditer(r"db\s+EVOLVE_LEVEL,\s*(\d+),\s*([A-Z0-9_]+)", body):
        out.append({"method": "LEVEL", "level": int(m.group(1)), "species": m.group(2)})
    for m in re.finditer(r"db\s+EVOLVE_ITEM,\s*([A-Z0-9_]+),\s*(\d+),\s*([A-Z0-9_]+)", body):
        out.append({"method": "ITEM", "item": m.group(1), "species": m.group(3)})
    for m in re.finditer(r"db\s+EVOLVE_TRADE,\s*(\d+),\s*([A-Z0-9_]+)", body):
        out.append({"method": "TRADE", "species": m.group(2)})
    return out


PIC_FILE = {"NIDORAN_M": "nidoranm", "NIDORAN_F": "nidoranf", "MR_MIME": "mr.mime"}


def export_pokemon() -> None:
    internal: dict[str, int] = {}
    for line in (MASTER / "constants" / "pokemon_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*const\s+([A-Z0-9_]+)\s*;\s*\$([0-9A-Fa-f]+)", line)
        if m:
            internal[m.group(1)] = int(m.group(2), 16)
    dex_consts = parse_const_list(MASTER / "constants" / "pokedex_constants.asm", "const")  # DEX_BULBASAUR first (1)
    names_en = parse_names(MASTER / "data" / "pokemon" / "names.asm", ("dname",))
    names_ko = parse_names(KOREAN / "data" / "pokemon" / "names.asm", ("kdname", "dname"))
    dex_order = []
    for line in (MASTER / "data" / "pokemon" / "dex_order.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*db\s+(DEX_[A-Z_]+|0)", line.split(";")[0])
        if m:
            dex_order.append(m.group(1))
    dex_entries = parse_dex_entries()
    icons = parse_menu_icons()
    out = {}
    for mon, iid in internal.items():
        if mon.startswith("MISSINGNO") or iid == 0 or iid - 1 >= len(dex_order) or dex_order[iid - 1] == "0":
            continue
        dex_const = dex_order[iid - 1]
        dex = dex_consts.index(dex_const) + 1
        file_name = PIC_FILE.get(mon, dex_const[4:].lower().replace("_", ""))  # DEX_BULBASAUR -> bulbasaur
        stats = parse_base_stats(file_name.replace(".", ""))
        out[mon] = {
            "internal_id": iid, "dex": dex,
            "name_en": names_en[iid - 1], "name_ko": names_ko[iid - 1] if iid - 1 < len(names_ko) else names_en[iid - 1],
            "pic": "mon_" + PIC_FILE.get(mon, file_name),
            "back": "monb_" + PIC_FILE.get(mon, file_name),
            "dex_entry": dex_entries.get(file_name.replace(".", "").upper(), {}),
            "learnset": parse_evos_moves(mon),
            "evolutions": parse_evolutions(mon),
            "icon": icons[dex - 1] if dex - 1 < len(icons) else "ICON_MON",
            **stats,
        }
    (OUT_DATA / "pokemon.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"pokemon: {len(out)}")


# ---------------------------------------------------------------------------
# wild encounters, items, marts, trainers
# ---------------------------------------------------------------------------

def red_only(text: str) -> str:
    out, skip = [], False
    for line in text.splitlines():
        t = line.strip()
        if t.startswith("IF DEF(_BLUE)"):
            skip = True
            continue
        if t.startswith("IF DEF(_RED)"):
            continue
        if t.startswith("ENDC"):
            skip = False
            continue
        if not skip:
            out.append(line)
    return "\n".join(out)


def export_wild() -> None:
    """data/wild/maps/*.asm: grass encounter rate and the 10 [level, species] slots; plus the slot chances."""
    out = {}
    for const, name in MAPS.items():
        path = MASTER / "data" / "wild" / "maps" / f"{name}.asm"
        if not path.exists():
            continue
        txt = red_only(path.read_text(encoding="utf-8"))
        grass = re.search(r"def_grass_wildmons\s+(\d+)(.*?)end_grass_wildmons", txt, re.S)
        rate = int(grass.group(1))
        mons = [[int(a), b] for a, b in re.findall(r"db\s+(\d+),\s*([A-Z0-9_]+)", grass.group(2))]
        entry = {}
        if rate > 0 and mons:
            entry.update({"rate": rate, "grass": mons})
        water = re.search(r"def_water_wildmons\s+(\d+)(.*?)end_water_wildmons", txt, re.S)
        if water:
            wrate = int(water.group(1))
            wmons = [[int(a), b] for a, b in re.findall(r"db\s+(\d+),\s*([A-Z0-9_]+)", water.group(2))]
            if wrate > 0 and wmons:
                entry.update({"water_rate": wrate, "water": wmons})
        if entry:
            out[const] = entry
    chances = []
    total = 0
    for m in re.finditer(r"wild_chance\s+(\d+)", (MASTER / "data" / "wild" / "probabilities.asm").read_text(encoding="utf-8")):
        total += int(m.group(1))
        chances.append(total - 1)
    # data/wild/good_rod.asm and super_rod.asm (map -> its fishing group)
    good = [[int(a), b] for a, b in re.findall(r"db\s+(\d+),\s*([A-Z0-9_]+)", (MASTER / "data" / "wild" / "good_rod.asm").read_text(encoding="utf-8"))]
    sr = (MASTER / "data" / "wild" / "super_rod.asm").read_text(encoding="utf-8")
    groups = {}
    for gm in re.finditer(r"^\.(Group\d+):\n\s*db\s+\d+\n((?:\s*db\s+\d+,\s*[A-Z0-9_]+\n?)+)", sr, re.M):
        groups[gm.group(1)] = [[int(a), b] for a, b in re.findall(r"db\s+(\d+),\s*([A-Z0-9_]+)", gm.group(2))]
    super_rod = {m.group(1): groups[m.group(2)] for m in re.finditer(r"dbw\s+([A-Z0-9_]+),\s*\.(Group\d+)", sr)}
    (OUT_DATA / "wild.json").write_text(json.dumps({"maps": out, "slot_chances": chances,
        "rods": {"good": good, "super": super_rod}}), encoding="utf-8")
    log(f"wild: {list(out)}")


def export_items() -> None:
    consts = parse_const_list(MASTER / "constants" / "item_constants.asm", "const")  # NO_ITEM first
    names_en = parse_names(MASTER / "data" / "items" / "names.asm", ("li",))
    names_ko = parse_names(KOREAN / "data" / "items" / "names.asm", ("kli", "li"))
    prices = [int(m.group(1)) for m in re.finditer(r"bcd3\s+(\d+)", (MASTER / "data" / "items" / "prices.asm").read_text(encoding="utf-8"))]
    keys = [m.group(1) == "TRUE" for m in re.finditer(r"dbit\s+(TRUE|FALSE)", (MASTER / "data" / "items" / "key_items.asm").read_text(encoding="utf-8"))]
    items = {}
    for i in range(1, min(len(names_en), len(prices)) + 1):
        items[consts[i]] = {
            "id": i, "name_en": names_en[i - 1], "name_ko": names_ko[i - 1] if i - 1 < len(names_ko) else names_en[i - 1],
            "price": prices[i - 1], "key": keys[i - 1] if i - 1 < len(keys) else False,
        }
    # TM/HM items (constants/item_constants.asm add_hm / add_tm, data/items/tm_prices.asm)
    machines = re.findall(r"^\s*add_(tm|hm)\s+([A-Z0-9_]+)", (MASTER / "constants" / "item_constants.asm").read_text(encoding="utf-8"), re.M)
    hms = [mv for kind, mv in machines if kind == "hm"]
    tms = [mv for kind, mv in machines if kind == "tm"]
    tm_prices = [int(m.group(1)) * 1000 for m in re.finditer(r"nybble\s+(\d+)", (MASTER / "data" / "items" / "tm_prices.asm").read_text(encoding="utf-8"))]
    hm_base = consts.index("HM01") if "HM01" in consts else 0xC4
    for i, mv in enumerate(hms):
        name = "HM%02d" % (i + 1)
        items[name] = {"id": hm_base + i, "name_en": name, "name_ko": name, "price": 0, "key": True, "move": mv}
    for i, mv in enumerate(tms):
        name = "TM%02d" % (i + 1)
        items[name] = {"id": hm_base + len(hms) + i, "name_en": name, "name_ko": name,
                       "price": tm_prices[i] if i < len(tm_prices) else 0, "key": False, "move": mv}
    (OUT_DATA / "items.json").write_text(json.dumps(items, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"items: {len(items)} (incl. {len(hms)} HM + {len(tms)} TM)")


def export_trades() -> None:
    """data/events/trades.asm (TradeMons, both languages) and the trade movie tilemaps."""
    def parse(root: Path, macro: str) -> list:
        out = []
        txt = (root / "data" / "events" / "trades.asm").read_text(encoding="utf-8")
        for m in re.finditer(r'^\s*npctrade\s+([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*(TRADE_DIALOGSET_[A-Z]+),\s*"([^"]*)"', txt, re.M):
            out.append(list(m.groups()))
        return out
    en = parse(MASTER, "npctrade")
    ko = parse(KOREAN, "npctrade")
    sets = ["TRADE_DIALOGSET_CASUAL", "TRADE_DIALOGSET_EVOLUTION", "TRADE_DIALOGSET_HAPPY"]
    trades = []
    for i, e in enumerate(en):
        trades.append({"give": e[0], "get": e[1], "dialog": sets.index(e[2]), "nick_en": e[3],
                       "nick_ko": ko[i][3] if i < len(ko) else e[3]})
    data = {
        "trades": trades,
        "game_boy_tilemap": list((MASTER / "gfx/trade/game_boy.tilemap").read_bytes()),
        "link_cable_tilemap": list((MASTER / "gfx/trade/link_cable.tilemap").read_bytes()),
    }
    (OUT_DATA / "trade.json").write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
    log(f"trades: {len(trades)}")


def machine_item(name: str) -> str:
    """TM_<MOVE> / HM_<MOVE> (the item constants used by item balls and marts) -> TMnn / HMnn."""
    if not name.startswith(("TM_", "HM_")):
        return name
    machines = re.findall(r"^\s*add_(tm|hm)\s+([A-Z0-9_]+)", (MASTER / "constants" / "item_constants.asm").read_text(encoding="utf-8"), re.M)
    kind = name[:2].lower()
    moves = [mv for k, mv in machines if k == kind]
    mv = name[3:]
    return "%s%02d" % (name[:2], moves.index(mv) + 1) if mv in moves else name


def export_marts() -> None:
    by_name = {v: k for k, v in MAPS.items()}
    out = {}
    for m in re.finditer(r"^(\w+?)Clerk(\d?)Text::\s*\n\s*script_mart\s+([A-Z0-9_, ]+)", (MASTER / "data" / "items" / "marts.asm").read_text(encoding="utf-8"), re.M):
        if m.group(1) in by_name:
            # a map with several clerks (Celadon Mart 2F/5F) gets one list per clerk: MAP_CLERK1, MAP_CLERK2
            key = by_name[m.group(1)] + (("_CLERK" + m.group(2)) if m.group(2) else "")
            out[key] = [machine_item(x.strip()) for x in m.group(3).split(",") if x.strip()]
    (OUT_DATA / "marts.json").write_text(json.dumps(out), encoding="utf-8")
    log(f"marts: {out}")


def export_trainers() -> None:
    classes = parse_const_list(MASTER / "constants" / "trainer_constants.asm", "trainer_const")  # NOBODY first
    names_en = parse_names(MASTER / "data" / "trainers" / "names.asm", ("li",))
    names_ko = parse_names(KOREAN / "data" / "trainers" / "names.asm", ("kli", "li"))
    txt = (MASTER / "data" / "trainers" / "parties.asm").read_text(encoding="utf-8")
    pics = re.findall(r"pic_money\s+(\w+)Pic,\s*(\d+)", (MASTER / "data" / "trainers" / "pic_pointers_money.asm").read_text(encoding="utf-8"))
    pic_files = {p.stem.replace(".", "").lower(): p.stem for p in (MASTER / "gfx" / "trainers").glob("*.png")}
    # data/trainers/ai_pointers.asm: "dbw count, FuncAI" per class (TrainerAI)
    ai_rows = re.findall(r"^\s*dbw\s+(\d+),\s*(\w+)", (MASTER / "data" / "trainers" / "ai_pointers.asm").read_text(encoding="utf-8"), re.M)
    # data/trainers/move_choices.asm: "move_choices [n, ...]" per class (AIEnemyTrainerChooseMoves)
    choice_rows = []
    for line in (MASTER / "data" / "trainers" / "move_choices.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*move_choices\b([^;]*)", line)
        if m:
            choice_rows.append([int(t) for t in re.findall(r"\d+", m.group(1))])
    # data/trainers/special_moves.asm: LoneMoves (by wLoneAttackNo) and TeamMoves (by class)
    special_src = (MASTER / "data" / "trainers" / "special_moves.asm").read_text(encoding="utf-8")
    lone_part = special_src.split("TeamMoves:")[0]
    team_part = special_src.split("TeamMoves:")[1]
    lone_moves = [[int(a), b] for a, b in re.findall(r"^\s*db\s+(\d+),\s*(\w+)", lone_part, re.M)]
    team_moves = {a: b for a, b in re.findall(r"^\s*db\s+([A-Z_]+),\s*(\w+)", team_part, re.M)}
    out = {}
    for i, cls in enumerate(classes[1:], start=1):
        # PSYCHIC_TR is PsychicData; a whole-line match keeps JugglerData apart from UnusedJugglerData
        label = f"{ {'PSYCHIC_TR': 'Psychic'}.get(cls, cls.title().replace('_', '')) }Data:"
        found = re.search(rf"^{label}", txt, re.M)
        idx = found.start() if found else -1
        teams = []
        special = []
        if idx >= 0:
            body = txt[idx + len(label):]
            end = re.search(r"^\w+Data:", body, re.M)
            body = body[:end.start()] if end else body
            for line in body.splitlines():
                line = line.split(";")[0].strip()
                if not line.startswith("db"):
                    continue
                toks = [t.strip() for t in line[2:].split(",")]
                if toks[0] == "$FF":
                    pairs = toks[1:-1]
                    teams.append([[int(pairs[j]), pairs[j + 1]] for j in range(0, len(pairs), 2)])
                    special.append(True)   # ReadTrainer .SpecialTrainer (lone / team moves apply)
                else:
                    level = int(toks[0])
                    teams.append([[level, mon] for mon in toks[1:-1]])
                    special.append(False)
        pic_label, money = pics[i - 1] if i - 1 < len(pics) else ("", 0)
        out[cls] = {
            "id": i, "name_en": names_en[i - 1] if i - 1 < len(names_en) else cls,
            "name_ko": names_ko[i - 1] if i - 1 < len(names_ko) else (names_en[i - 1] if i - 1 < len(names_en) else cls),
            "pic": "pic_trainer_" + pic_files.get(pic_label.lower(), pic_label.lower()),
            "money": int(money), "teams": teams, "special_teams": special,
            "ai_count": int(ai_rows[i - 1][0]), "ai": ai_rows[i - 1][1],
            "move_choices": choice_rows[i - 1], "team_move": team_moves.get(cls, ""),
        }
    out["_lone_moves"] = lone_moves
    (OUT_DATA / "trainers.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"trainers: {len(out)}")


def export_moves_types() -> None:
    move_consts = parse_const_list(MASTER / "constants" / "move_constants.asm", "const")  # NO_MOVE first
    names_en = parse_names(MASTER / "data" / "moves" / "names.asm", ("li",))
    names_ko = parse_names(KOREAN / "data" / "moves" / "names.asm", ("kli", "li"))
    moves = {}
    i = 0
    for line in (MASTER / "data" / "moves" / "moves.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*move\s+([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*(\d+),\s*([A-Z_]+),\s*(\d+),\s*(\d+)", line.split(";")[0])
        if not m:
            continue
        name = m.group(1)
        moves[name] = {
            "id": move_consts.index(name), "effect": m.group(2), "power": int(m.group(3)), "type": m.group(4),
            "accuracy": int(m.group(5)), "pp": int(m.group(6)),
            "name_en": names_en[i], "name_ko": names_ko[i] if i < len(names_ko) else names_en[i],
        }
        i += 1
    (OUT_DATA / "moves.json").write_text(json.dumps(moves, ensure_ascii=False), encoding="utf-8")

    type_consts = {}
    for line in (MASTER / "constants" / "type_constants.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*const\s+([A-Z_]+)\s*;\s*\$([0-9a-fA-F]+)", line)
        if m:
            type_consts[m.group(1)] = int(m.group(2), 16)
    type_names_en = {}
    for line in (MASTER / "data" / "types" / "names.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r'^\.(\w+):\s*db\s+"([^"@]+)@"', line.strip())
        if m:
            type_names_en[m.group(1).upper()] = m.group(2)
    type_names_ko = {}
    for line in (KOREAN / "data" / "types" / "names.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r'^\.(\w+):\s*(?:db|korean_text_bytes)\s+"([^"@]+)@"', line.strip())
        if m:
            type_names_ko[m.group(1).upper()] = m.group(2)
    matchups = []
    for line in (MASTER / "data" / "types" / "type_matchups.asm").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\s*db\s+([A-Z_]+),\s*([A-Z_]+),\s*([A-Z_]+)", line.split(";")[0])
        if m:
            matchups.append([m.group(1), m.group(2), m.group(3)])
    (OUT_DATA / "types.json").write_text(json.dumps({
        "ids": type_consts, "names_en": type_names_en, "names_ko": type_names_ko, "matchups": matchups,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    log(f"moves: {len(moves)}, type matchups: {len(matchups)}")


def main() -> None:
    for p in (MASTER, KOREAN):
        if not p.exists():
            sys.exit(f"missing source repo: {p}")
    export_graphics()
    export_charmap_and_font()
    export_texts()
    export_tilesets()
    export_maps()
    export_pokemon()
    export_moves_types()
    export_wild()
    export_items()
    export_marts()
    export_trades()
    export_trainers()
    export_town_map()
    log("done")


if __name__ == "__main__":
    main()
