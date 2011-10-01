/*
* 
* Jail
* 
* Description:
* Sends players to a specified location on the map and
* forces them to stay there until released. Not even
* death or a reconnect will allow them to escape!
* 
* 
* Changelog
* Sep 28, 2009 - v.1.0:
* 				[*] Initial Release
* 
*/

#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <adminmenu>

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "Jail",
	author = "Stevo.TVR",
	description = "Forces players to stay in a specified location",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org/"
}

new Handle:g_hTopMenu = INVALID_HANDLE;
new Handle:g_hMapData = INVALID_HANDLE;
new Handle:g_hJailed = INVALID_HANDLE;

new bool:g_bJailed[MAXPLAYERS+1] = {false, ...};
new bool:g_bReady = false;
new Float:g_vOrigin[3], Float:g_vAngle[3];

public OnPluginStart()
{
	RegAdminCmd("sm_jail", Command_Jail, ADMFLAG_KICK, "Jail/Release player");
	RegAdminCmd("sm_jail_saveloc", Command_Saveloc, ADMFLAG_KICK, "Save jail coordinates");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	LoadTranslations("common.phrases");
	LoadTranslations("jail.phrases");
	
	g_hMapData = CreateKeyValues("Jail");
	g_hJailed = CreateTrie();
	
	LoadSaveData();
	
	new Handle:topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(topmenu);
	}
}

public OnMapStart()
{
	decl String:sMap[64];
	GetCurrentMap(sMap, sizeof(sMap));
	
	if(KvJumpToKey(g_hMapData, sMap))
	{
		KvGetVector(g_hMapData, "origin", g_vOrigin);
		KvGetVector(g_hMapData, "angle", g_vAngle);
		KvRewind(g_hMapData);
		g_bReady = true;
	}
	else
	{
		g_bReady = false;
	}
	
	ClearTrie(g_hJailed);
}

public OnClientAuthorized(client, const String:auth[])
{
	new bool:value;
	if(GetTrieValue(g_hJailed, auth, value))
	{
		g_bJailed[client] = true;
	}
}

public OnClientDisconnect(client)
{
	g_bJailed[client] = false;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(g_bJailed[client] && g_bReady)
	{
		TeleportPlayer(client);
	}
}

public Action:Command_Jail(client, args)
{
	if(args < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_jail <player>");
		return Plugin_Handled;
	}
	
	if(!g_bReady)
	{
		ReplyToCommand(client, "[SM] %t", "No coords");
		return Plugin_Handled;
	}
	
	decl String:sTarget[64];
	GetCmdArg(1, sTarget, sizeof(sTarget));
	new target = FindTarget(client, sTarget);
	
	if(target > 0)
	{
		JailPlayer(client, target);
	}
	
	return Plugin_Handled;
}

public Action:Command_Saveloc(client, args)
{
	if(IsClientInGame(client))
	{
		GetClientAbsOrigin(client, g_vOrigin);
		GetClientAbsAngles(client, g_vAngle);
		
		decl String:sMap[64];
		GetCurrentMap(sMap, sizeof(sMap));
		
		KvJumpToKey(g_hMapData, sMap, true);
		KvSetVector(g_hMapData, "origin", g_vOrigin);
		KvSetVector(g_hMapData, "angle", g_vAngle);
		KvRewind(g_hMapData);
		
		LoadSaveData(true);
		
		g_bReady = true;
		
		ReplyToCommand(client, "[SM] %t", "Coords saved", sMap);
		LogAction(client, -1, "\"%L\" saved jail coordinates for map %s", client, sMap);
	}
	
	return Plugin_Handled;
}

JailPlayer(client, target)
{
	if(g_bReady)
	{
		decl String:auth[64], String:sTargetName[MAX_NAME_LENGTH], String:sMessage[128];
		GetClientAuthString(target, auth, sizeof(auth));
		GetClientName(target, sTargetName, sizeof(sTargetName));
		
		if(!g_bJailed[target])
		{
			SetTrieValue(g_hJailed, auth, true);
			g_bJailed[target] = true;
			TeleportPlayer(target);
			
			ShowActivity2(client, "[SM] ", "%t", "Jailed player", sTargetName);
			Format(sMessage, sizeof(sMessage), "\x01[SM] \x03%t", "Jailed");
			SayText2(target, target, sMessage);
			LogAction(client, target, "\"%L\" jailed \"%L\"", client, target);
		}
		else
		{
			RemoveFromTrie(g_hJailed, auth);
			g_bJailed[target] = false;
			
			if(IsPlayerAlive(target))
			{
				DispatchSpawn(target);
			}
			
			ShowActivity2(client, "[SM] ", "%t", "Released player", sTargetName);
			Format(sMessage, sizeof(sMessage), "\x01[SM] \x04%t", "Released");
			SayText2(target, target, sMessage);
			LogAction(client, target, "\"%L\" released \"%L\"", client, target);
		}
	}
}

TeleportPlayer(client)
{
	if(IsPlayerAlive(client))
	{
		TeleportEntity(client, g_vOrigin, g_vAngle, NULL_VECTOR);
	}
}

LoadSaveData(bool:save = false)
{
	decl String:sPath[PLATFORM_MAX_PATH];
	BuildPath(PathType:Path_SM, sPath, sizeof(sPath), "data/jail.txt");
	
	if(save)
	{
		KeyValuesToFile(g_hMapData, sPath);
	}
	else
	{
		if(!FileToKeyValues(g_hMapData, sPath))
		{
			SetFailState("Unable to load map data file");
		}
	}
}

SayText2(client_index, author_index, const String:message[])
{
	new Handle:buffer = StartMessageOne("SayText2", client_index);
	if(buffer != INVALID_HANDLE)
	{
		BfWriteByte(buffer, author_index);
		BfWriteByte(buffer, true);
		BfWriteString(buffer, message);
		EndMessage();
	}
}

/*
* ===================
* Menu Stuff
* ===================
*/
public OnLibraryRemoved(const String:name[])
{
	if(StrEqual(name, "adminmenu")) 
	{
		g_hTopMenu = INVALID_HANDLE;
	}
}

public OnAdminMenuReady(Handle:topmenu)
{
	if(topmenu == g_hTopMenu)
	{
		return;
	}
	
	g_hTopMenu = topmenu;
	
	new TopMenuObject:player_commands = FindTopMenuCategory(g_hTopMenu, ADMINMENU_PLAYERCOMMANDS);

	if(player_commands != INVALID_TOPMENUOBJECT)
	{
		AddToTopMenu(g_hTopMenu, "sm_jail", TopMenuObject_Item, AdminMenu_Jail, player_commands, "sm_jail", ADMFLAG_KICK);
	}
}

DisplayJailMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler_Jail);
	
	decl String:title[100];
	Format(title, sizeof(title), "%t", "Jail menu");
	SetMenuTitle(menu, title);
	SetMenuExitBackButton(menu, true);
	
	AddTargetsToMenu(menu, client, false, false);
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public AdminMenu_Jail(Handle:topmenu, TopMenuAction:action, TopMenuObject:object_id, param, String:buffer[], maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		Format(buffer, maxlength, "%t", "Jail menu");
	}
	else if(action == TopMenuAction_SelectOption)
	{
		DisplayJailMenu(param);
	}
}

public MenuHandler_Jail(Handle:menu, MenuAction:action, param1, param2)
{
	if(action == MenuAction_End)
	{
		CloseHandle(menu);
	}
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack && g_hTopMenu != INVALID_HANDLE)
		{
			DisplayTopMenu(g_hTopMenu, param1, TopMenuPosition_LastCategory);
		}
	}
	else if(action == MenuAction_Select)
	{
		decl String:info[32];
		new userid, target;
		
		GetMenuItem(menu, param2, info, sizeof(info));
		userid = StringToInt(info);

		if(!g_bReady)
		{
			PrintToChat(param1, "[SM] %t", "No coords");
		}
		else if((target = GetClientOfUserId(userid)) == 0)
		{
			PrintToChat(param1, "[SM] %t", "Player no longer available");
		}
		else if(!CanUserTarget(param1, target))
		{
			PrintToChat(param1, "[SM] %t", "Unable to target");
		}
		else
		{
			JailPlayer(param1, target);
		}
	}
}

// WE MUST PUSH LITTLE KART