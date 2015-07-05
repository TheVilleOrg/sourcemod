/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod Nextmap Plugin
 * Adds sm_nextmap cvar for changing map and nextmap chat trigger.
 *
 * SourceMod (C)2004-2014 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include <sourcemod>
#include "include/nextmap.inc"

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = 
{
	name = "Nextmap w/ Population Limits",
	author = "AlliedModders LLC/StevoTVR",
	description = "Provides nextmap and sm_nextmap, with population limits",
	version = SOURCEMOD_VERSION,
	url = "http://www.sourcemod.net/"
};

int g_MapPos = -1;
int g_NextMapPos = -1;
ArrayList g_MapList = null;
ArrayList g_MapLimits = null;

int g_CurrentMapStartTime;

bool g_NextMapLock;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	char game[128];
	GetGameFolderName(game, sizeof(game));

	if (StrEqual(game, "left4dead", false)
			|| StrEqual(game, "dystopia", false)
			|| StrEqual(game, "synergy", false)
			|| StrEqual(game, "left4dead2", false)
			|| StrEqual(game, "garrysmod", false)
			|| StrEqual(game, "swarm", false)
			|| StrEqual(game, "dota", false)
			|| StrEqual(game, "bms", false)
			|| GetEngineVersion() == Engine_Insurgency)
	{
		strcopy(error, err_max, "Nextmap is incompatible with this game");
		return APLRes_SilentFailure;
	}
	
	DisablePlugin("nextmap");
	DisablePlugin("mapchooser");
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("nextmap.phrases");
	LoadTranslations("mapchooser.phrases");
	
	int size = ByteCountToCells(PLATFORM_MAX_PATH);
	g_MapList = new ArrayList(size);
	g_MapLimits = new ArrayList(2);

	RegAdminCmd("sm_maphistory", Command_MapHistory, ADMFLAG_CHANGEMAP, "Shows the most recent maps played");
	RegAdminCmd("sm_setnextmap", Command_SetNextmap, ADMFLAG_CHANGEMAP, "sm_setnextmap <map>");
	RegConsoleCmd("listmaps", Command_List);
	
	CreateTimer(60.0, Timer_Update, _, TIMER_REPEAT);
}

public void OnMapStart()
{
	g_CurrentMapStartTime = GetTime();
	g_NextMapLock = false;
}
 
public void OnConfigsExecuted()
{
	ReadMapCycle();
	g_MapPos = -1;
}

public Action Command_List(int client, int args) 
{
	PrintToConsole(client, "Map Cycle:");
	
	int mapCount = g_MapList.Length;
	char mapName[PLATFORM_MAX_PATH];
	int limits[2];
	for (int i = 0; i < mapCount; i++)
	{
		g_MapList.GetString(i, mapName, sizeof(mapName));
		g_MapLimits.GetArray(i, limits);
		int min = limits[0];
		int max = limits[1] > 0 ? limits[1] : MaxClients;
		PrintToConsole(client, "%s (%i - %i pl.)", mapName, min, max);
	}
 
	return Plugin_Handled;
}

public Action Command_SetNextmap(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setnextmap <map>");
		return Plugin_Handled;
	}

	char map[PLATFORM_MAX_PATH];
	GetCmdArg(1, map, sizeof(map));

	if (!IsMapValid(map))
	{
		ReplyToCommand(client, "[SM] %t", "Map was not found", map);
		return Plugin_Handled;
	}

	ShowActivity(client, "%t", "Changed Next Map", map);
	LogAction(client, -1, "\"%L\" changed nextmap to \"%s\"", client, map);

	SetNextMap(map);
	g_NextMapLock = true;

	return Plugin_Handled;
}

public Action Timer_Update(Handle timer)
{
	if (!g_NextMapLock)
		FindAndSetNextMap();
}
  
void FindAndSetNextMap()
{
	int mapCount = g_MapList.Length;
	char mapName[PLATFORM_MAX_PATH];
	
	if (g_MapPos == -1)
	{
		char current[PLATFORM_MAX_PATH];
		GetCurrentMap(current, sizeof(current));

		for (int i = 0; i < mapCount; i++)
		{
			g_MapList.GetString(i, mapName, sizeof(mapName));
			if (strcmp(current, mapName, false) == 0)
			{
				g_MapPos = i;
				break;
			}
		}
		
		if (g_MapPos == -1)
			g_MapPos = 0;
	}
	
	g_NextMapPos = g_MapPos;
	if (mapCount > 1)
	{
		int pop = GetClientCount();
		int limits[2];
		int nextMap = g_NextMapPos + 1;
		
		if (nextMap >= mapCount)
			nextMap = 0;
		
		while (nextMap != g_MapPos)
		{
			g_MapLimits.GetArray(nextMap, limits);
			
			if (limits[0] <= pop && (limits[1] == 0 || limits[1] >= pop))
			{
				break;
			}
			
			nextMap++;
			
			if (nextMap >= mapCount)
				nextMap = 0;
		}
		
		g_NextMapPos = nextMap;
	}
	
	g_MapList.GetString(g_NextMapPos, mapName, sizeof(mapName));
	SetNextMap(mapName);
}

void ReadMapCycle()
{
	char fileName[PLATFORM_MAX_PATH];
	if (!FindMapCycle(fileName, sizeof(fileName)))
	{
		LogError("FATAL: Cannot load map cycle. Nextmap not loaded.");
		SetFailState("Mapcycle Not Found");
	}
	
	File mapCycle = OpenFile(fileName, "r", true);
	if (mapCycle != null)
	{
		g_MapList.Clear();
		
		char line[PLATFORM_MAX_PATH];
		char entry[3][PLATFORM_MAX_PATH];
		int limits[2];
		while (mapCycle.ReadLine(line, sizeof(line)))
		{
			// format: map_name [min_players] [max_players]
			int num = ExplodeString(line, " ", entry, sizeof(entry), sizeof(entry[]));
			
			// add map name
			TrimString(entry[0]);
			g_MapList.PushString(entry[0]);
			
			// add population limits for map entry
			limits[0] = num > 1 ? StringToInt(entry[1]) : 0;
			limits[1] = num > 2 ? StringToInt(entry[2]) : 0;
			g_MapLimits.PushArray(limits);
		}
		
		mapCycle.Close();
	}
}

bool FindMapCycle(char[] buffer, int maxlength)
{
	char path[PLATFORM_MAX_PATH];
	char fileName[PLATFORM_MAX_PATH];
	ConVar mapCycleFile = FindConVar("mapcyclefile");
	mapCycleFile.GetString(fileName, sizeof(fileName));
	
	Format(path, sizeof(path), "cfg/%s", fileName);
	if (!FileExists(path, true))
	{
		Format(path, sizeof(path), "%s", fileName);
		if (!FileExists(path, true))
		{
			Format(path, sizeof(path), "cfg/mapcycle_default.txt");
			if (!FileExists(path, true))
				return false;
		}
	}
	
	strcopy(buffer, maxlength, path);
	return true;
}

public Action Command_MapHistory(int client, int args)
{
	int mapCount = GetMapHistorySize();
	
	char mapName[PLATFORM_MAX_PATH];
	char changeReason[100];
	char timeString[100];
	char playedTime[100];
	int startTime;
	
	int lastMapStartTime = g_CurrentMapStartTime;
	
	PrintToConsole(client, "%t:\n", "Map History");
	PrintToConsole(client, "%t : %t : %t : %t", "Map", "Started", "Played Time", "Reason");
	
	GetCurrentMap(mapName, sizeof(mapName));
	PrintToConsole(client, "%02i. %s (%t)", 0, mapName, "Current Map");
	
	for (int i=0; i<mapCount; i++)
	{
		GetMapHistory(i, mapName, sizeof(mapName), changeReason, sizeof(changeReason), startTime);

		FormatTimeDuration(timeString, sizeof(timeString), GetTime() - startTime);
		FormatTimeDuration(playedTime, sizeof(playedTime), lastMapStartTime - startTime);
		
		PrintToConsole(client, "%02i. %s : %s %t : %s : %s", i+1, mapName, timeString, "ago", playedTime, changeReason);
		
		lastMapStartTime = startTime;
	}

	return Plugin_Handled;
}

int FormatTimeDuration(char[] buffer, int maxlen, int time)
{
	int days = time / 86400;
	int hours = (time / 3600) % 24;
	int minutes = (time / 60) % 60;
	int seconds =  time % 60;
	
	if (days > 0)
	{
		return Format(buffer, maxlen, "%id %ih %im", days, hours, (seconds >= 30) ? minutes+1 : minutes);
	}
	else if (hours > 0)
	{
		return Format(buffer, maxlen, "%ih %im", hours, (seconds >= 30) ? minutes+1 : minutes);		
	}
	else if (minutes > 0)
	{
		return Format(buffer, maxlen, "%im", (seconds >= 30) ? minutes+1 : minutes);		
	}
	else
	{
		return Format(buffer, maxlen, "%is", seconds);		
	}
}

// Taken from SourceBans
bool DisablePlugin(const char[] file)
{
	char sNewPath[PLATFORM_MAX_PATH + 1];
	char sOldPath[PLATFORM_MAX_PATH + 1];
	BuildPath(Path_SM, sNewPath, sizeof(sNewPath), "plugins/disabled/%s.smx", file);
	BuildPath(Path_SM, sOldPath, sizeof(sOldPath), "plugins/%s.smx", file);
	
	// If plugins/<file>.smx does not exist, ignore
	if(!FileExists(sOldPath))
		return false;
	
	// If plugins/disabled/<file>.smx exists, delete it
	if(FileExists(sNewPath))
		DeleteFile(sNewPath);
	
	// Unload plugins/<file>.smx and move it to plugins/disabled/<file>.smx
	ServerCommand("sm plugins unload %s", file);
	RenameFile(sNewPath, sOldPath);
	LogMessage("plugins/%s.smx was unloaded and moved to plugins/disabled/%s.smx", file, file);
	return true;
}
