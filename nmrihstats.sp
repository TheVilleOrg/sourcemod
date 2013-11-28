/*
* 
* Simple NMRiH Stats
* https://forums.alliedmods.net/showthread.php?t=230459
* 
* Description:
* This is a basic point-based stats plugin for No More Room in Hell. Players
* get +1 for each zombie killed and -10 for each death. These values are
* configurable. Also adds rank and top10 commands. Stat data is stored in a
* configurable database.
* 
* 
* Changelog
* Nov 20, 2013 - v.0.1:
* 				[*] Initial Release
* 
*/

#pragma semicolon 1
#include <sourcemod>

#define PLUGIN_VERSION "0.1"
#define DEBUG

public Plugin:myinfo = 
{
	name = "Simple NMRiH Stats",
	author = "Stevo.TVR",
	description = "Basic point-based stats for No More Room in Hell",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?t=230459"
}

new Handle:hDatabase = INVALID_HANDLE;

new Handle:sm_stats_killpoints = INVALID_HANDLE;
new Handle:sm_stats_deathpoints = INVALID_HANDLE;
new Handle:sm_stats_tkpoints = INVALID_HANDLE;
new Handle:sm_stats_startpoints = INVALID_HANDLE;

new clientPoints[MAXPLAYERS+1];
new clientKills[MAXPLAYERS+1];
new clientDeaths[MAXPLAYERS+1];
new totalPlayers;

public OnPluginStart()
{
	decl String:game[16];
	GetGameFolderName(game, sizeof(game));
	if(strcmp(game, "nmrih", false) != 0)
	{
		SetFailState("Unsupported game!");
	}
	
	CreateConVar("sm_nmrihstats_version", PLUGIN_VERSION, "Simple NMRiH Stats version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	sm_stats_killpoints = CreateConVar("sm_stats_killpoints", "1", "Points to award for a zombie kill");
	sm_stats_deathpoints = CreateConVar("sm_stats_deathpoints", "-10", "Points to award for being killed");
	sm_stats_tkpoints = CreateConVar("sm_stats_tkpoints", "-20", "Points to award for killing a teammate");
	sm_stats_startpoints = CreateConVar("sm_stats_startpoints", "0", "Points to give to new players");

	AutoExecConfig(true, "nmrihstats");

	RegConsoleCmd("sm_rank", Command_Rank, "Displays your current rank");
	RegConsoleCmd("sm_top10", Command_Top10, "Lists top 10 players");
	
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("npc_killed", Event_NPCKilled);
	HookEvent("player_changename", Event_ChangeName);
	
	ConnectDatabase();
}

public ConnectDatabase()
{
	new String:db[] = "storage-local";
	if(SQL_CheckConfig("nmrihstats"))
	{
		db = "nmrihstats";
	}
	decl String:error[256];
	hDatabase = SQL_Connect(db, true, error, sizeof(error));
	if(hDatabase == INVALID_HANDLE)
	{
		SetFailState(error);
	}
	
	SQL_TQuery(hDatabase, T_FastQuery, "CREATE TABLE IF NOT EXISTS nmrihstats (steam_id VARCHAR(64) PRIMARY KEY, name TEXT, points INTEGER, kills INTEGER, deaths INTEGER);");
}

public OnMapStart()
{
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientAuthorized(i) && !IsFakeClient(i))
		{
			decl String:query[1024], String:auth[64];
			GetClientAuthString(i, auth, sizeof(auth));
			Format(query, sizeof(query), "SELECT name, points, kills, deaths FROM nmrihstats WHERE steam_id = '%s' LIMIT 1;", auth);
			SQL_TQuery(hDatabase, T_LoadPlayer, query, i);
		}
	}
}

public OnClientAuthorized(client, const String:auth[])
{
	if(IsFakeClient(client))
		return;
	
	decl String:query[1024];
	Format(query, sizeof(query), "SELECT name, points, kills, deaths FROM nmrihstats WHERE steam_id = '%s' LIMIT 1;", auth);
	SQL_TQuery(hDatabase, T_LoadPlayer, query, client);
}

public T_LoadPlayer(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if(!IsClientAuthorized(client) || IsFakeClient(client))
		return;
	
	if(hndl != INVALID_HANDLE)
	{
		decl String:authid[64], String:playername[64];
		GetClientAuthString(client, authid, sizeof(authid));
		GetClientName(client, playername, sizeof(playername));

		if(SQL_FetchRow(hndl))
		{
			decl String:dbname[64];
			SQL_FetchString(hndl, 0, dbname, sizeof(dbname));
			if(strcmp(playername, dbname) != 0)
			{
				UpdatePlayerName(authid, playername);
			}
			
			clientPoints[client] = SQL_FetchInt(hndl, 1);
			clientKills[client] = SQL_FetchInt(hndl, 2);
			clientDeaths[client] = SQL_FetchInt(hndl, 3);
		}
		else
		{
			decl String:query[1024], String:escname[129];
			SQL_EscapeString(hDatabase, playername, escname, sizeof(escname));
			new points = GetConVarInt(sm_stats_startpoints);
			
			Format(query, sizeof(query), "INSERT INTO nmrihstats VALUES ('%s', '%s', %d, 0, 0);", authid, escname, points);
			SQL_TQuery(hDatabase, T_FastQuery, query);
			
			clientPoints[client] = points;
			clientKills[client] = 0;
			clientDeaths[client] = 0;
			
#if defined DEBUG
			LogMessage("Adding player: %L", client);
#endif
		}
	}
}

public Action:Command_Rank(client, args)
{
	SQL_TQuery(hDatabase, T_UpdateTotalQuery, "SELECT COUNT(*) FROM nmrihstats;");
	
	decl String:query[1024];
	Format(query, sizeof(query), "SELECT points FROM nmrihstats WHERE points > %d ORDER BY points ASC;", clientPoints[client]);
	SQL_TQuery(hDatabase, T_RankQuery, query, client);
	
	return Plugin_Handled;
}

public T_UpdateTotalQuery(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if(hndl != INVALID_HANDLE && SQL_FetchRow(hndl))
	{
		totalPlayers = SQL_FetchInt(hndl, 0);
	}
}

public T_RankQuery(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if(hndl == INVALID_HANDLE || !IsClientInGame(client))
		return;
	
	new rank = 1, rankdiff = 0;
	if(SQL_FetchRow(hndl))
	{
		rank = SQL_GetRowCount(hndl) + 1;
		rankdiff = SQL_FetchInt(hndl, 0) - clientPoints[client];
	}
	PrintToChatAll("\x01Player \x04%N\x01 is rank \x04%d\x01 of \x04%d\x01 total tracked player%s with \x04%d\x01 point%s and is \x04%d\x01 point%s away from the next rank.", client, rank, totalPlayers, totalPlayers != 1 ? "s" : "", clientPoints[client], clientPoints[client] != 1 ? "s" : "", rankdiff, rankdiff != 1 ? "s" : "");
}

public Action:Command_Top10(client, args)
{
	SQL_TQuery(hDatabase, T_Top10Query, "SELECT name, points FROM nmrihstats ORDER BY points DESC LIMIT 10;", client);
	
	return Plugin_Handled;
}

public T_Top10Query(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if(hndl == INVALID_HANDLE || !IsClientInGame(client))
		return;
	
	decl String:name[64], String:line[128];
	new i;
	PrintToChat(client, "\x04Top 10 players:");
	while(SQL_FetchRow(hndl))
	{
		SQL_FetchString(hndl, 0, name, sizeof(name));
		Format(line, sizeof(line), "\x04#%d.\x01 %s (%d)", ++i, name, SQL_FetchInt(hndl, 1));
		new Handle:data;
		CreateDataTimer(5.0 - 0.5 * i, Timer_Top10, data);
		WritePackCell(data, client);
		WritePackString(data, line);
	}
}

public Action:Timer_Top10(Handle:timer, Handle:hndl)
{
	ResetPack(hndl);
	new client = ReadPackCell(hndl);
	if(IsClientInGame(client))
	{
		decl String:line[128];
		ReadPackString(hndl, line, sizeof(line));
		PrintToChat(client, line);
	}
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new attacker = GetClientOfUserId(GetEventInt(event, "attacker"));

	if(client == 0 || IsFakeClient(client) || !IsClientAuthorized(client))
		return Plugin_Continue;
	
	if(attacker != 0 && attacker != client && !IsFakeClient(attacker) && IsClientAuthorized(attacker))
	{
		clientPoints[attacker] += GetConVarInt(sm_stats_tkpoints);
		
#if defined DEBUG
		LogMessage("Player %L (%d) %d for killing a teammate", attacker, clientPoints[attacker], GetConVarInt(sm_stats_tkpoints));
#endif
		
		decl String:query[1024], String:authid[64];
		GetClientAuthString(attacker, authid, sizeof(authid));
		Format(query, sizeof(query), "UPDATE nmrihstats SET points = %d WHERE steam_id = '%s';", clientPoints[attacker], authid);
		SQL_TQuery(hDatabase, T_FastQuery, query);
		
		return Plugin_Continue;
	}
	
	clientDeaths[client]++;
	clientPoints[client] += GetConVarInt(sm_stats_deathpoints);
		
#if defined DEBUG
	LogMessage("Player %L (%d) %d for getting killed", client, clientPoints[client], GetConVarInt(sm_stats_deathpoints));
#endif
	
	decl String:query[1024], String:authid[64];
	GetClientAuthString(client, authid, sizeof(authid));
	Format(query, sizeof(query), "UPDATE nmrihstats SET points = %d, deaths = %d WHERE steam_id = '%s';", clientPoints[client], clientDeaths[client], authid);
	SQL_TQuery(hDatabase, T_FastQuery, query);
	
	return Plugin_Continue;
}

public Action:Event_NPCKilled(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetEventInt(event, "killeridx");
	
	if(client == 0 || client > MaxClients || IsFakeClient(client) || !IsClientAuthorized(client))
		return Plugin_Continue;
	
	clientKills[client]++;
	clientPoints[client] += GetConVarInt(sm_stats_killpoints);
		
#if defined DEBUG
	LogMessage("Player %L (%d) %d for killing a zombie", client, clientPoints[client], GetConVarInt(sm_stats_killpoints));
#endif
	
	decl String:query[1024], String:authid[64];
	GetClientAuthString(client, authid, sizeof(authid));
	Format(query, sizeof(query), "UPDATE nmrihstats SET points = %d, kills = %d WHERE steam_id = '%s';", clientPoints[client], clientKills[client], authid);
	SQL_TQuery(hDatabase, T_FastQuery, query);
	
	return Plugin_Continue;
}

public Action:Event_ChangeName(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(client != 0 && !IsFakeClient(client))
	{
		decl String:authid[64], String:playername[64];
		GetClientAuthString(client, authid, sizeof(authid));
		GetEventString(event, "newname", playername, sizeof(playername));
		UpdatePlayerName(authid, playername);
	}
	
	return Plugin_Continue;
}

public T_FastQuery(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	// Nothing to do
}

public UpdatePlayerName(const String:authid[], const String:name[])
{
	decl String:query[1024], String:escname[129];
	SQL_EscapeString(hDatabase, name, escname, sizeof(escname));
	Format(query, sizeof(query), "UPDATE nmrihstats SET name = '%s' WHERE steam_id = '%s';", escname, authid);
	SQL_TQuery(hDatabase, T_FastQuery, query);
	
#if defined DEBUG
	LogMessage("Updating name: %s", name);
#endif
}
