#pragma semicolon 1
#include <sourcemod>

#define PLUGIN_VERSION "1.1.4"

public Plugin:myinfo = 
{
	name = "Map Stats",
	author = "Stevo.TVR",
	description = "Records server population stats for maps",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org"
}

new Handle:hDatabase = INVALID_HANDLE;
new Handle:hTimer = INVALID_HANDLE;
new Handle:hPlayerTrie = INVALID_HANDLE;
new Handle:hSnapshots = INVALID_HANDLE;

new Handle:sm_mapstats_interval = INVALID_HANDLE;

new String:g_mapName[128];
new g_hostip;
new g_hostport;
new g_serverId;
new g_mapId;
new g_userId[MAXPLAYERS+1];
new g_playerJoins;
new g_playerQuits;
new g_mapStartTime;
new bool:g_waitingForPlayers = true;
new bool:g_mapChanging = false;

public OnPluginStart()
{
	CreateConVar("sm_mapstats_version", PLUGIN_VERSION, "Map Stats plugin version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	sm_mapstats_interval = CreateConVar("sm_mapstats_interval", "300.0", "Number of seconds between population snapshots", _, true, 30.0);
	
	HookConVarChange(sm_mapstats_interval, ConVarChanged);
	AutoExecConfig(true, "mapstats");
	
	HookEvent("player_disconnect", Event_PlayerDisconnect);
	
	hPlayerTrie = CreateTrie();
	hSnapshots = CreateArray();
	
	SQL_TConnect(T_DBConnect, "mapstats");
}

public OnConfigsExecuted()
{
	hTimer = CreateTimer(GetConVarFloat(sm_mapstats_interval), Timer_Snapshot, _, TIMER_REPEAT);
}

public ConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
	if(hTimer != INVALID_HANDLE)
	{
		CloseHandle(hTimer);
		hTimer = CreateTimer(GetConVarFloat(sm_mapstats_interval), Timer_Snapshot, _, TIMER_REPEAT);
	}
}

public OnMapStart()
{
	g_mapStartTime = GetTime();
	LoadMap();
}

LoadMap()
{
	if(hDatabase != INVALID_HANDLE)
	{
		decl String:query[512], String:mapName[64];
		GetCurrentMap(mapName, sizeof(mapName));
		SQL_EscapeString(hDatabase, mapName, g_mapName, sizeof(g_mapName));
		Format(query, sizeof(query), "SELECT `id` FROM `mapstats_maps` WHERE `name` = '%s';", g_mapName);
		SQL_TQuery(hDatabase, T_FetchMapId, query);
	}
}

public OnMapEnd()
{
	if(!g_waitingForPlayers)
	{
		SendSummary();
	}
	g_mapId = 0;
	g_mapChanging = true;
	CreateTimer(30.0, Timer_Mapchange);
}

SendSummary()
{
	if(hDatabase != INVALID_HANDLE && g_serverId > 0 && g_mapId > 0)
	{
		new avgPop, num = GetArraySize(hSnapshots);
		if(num > 0)
		{
			for(new i = 0; i < num; i++)
			{
				avgPop += GetArrayCell(hSnapshots, i);
			}
			avgPop /= num;
			
			decl String:query[512];
			Format(query, sizeof(query), "INSERT INTO `mapstats_summary` (`serverid`, `mapid`, `popavg`, `quits`, `joins`, `duration`) VALUES (%d, %d, %d, %d, %d, %d);", g_serverId, g_mapId, avgPop, g_playerQuits, g_playerJoins, GetTime() - g_mapStartTime);
			SQL_TQuery(hDatabase, T_FastQuery, query);
		}
	}
	
	g_playerQuits = 0;
	g_playerJoins = 0;
	ClearTrie(hPlayerTrie);
	ClearArray(hSnapshots);
}

public OnClientAuthorized(client, const String:auth[])
{
	if(g_waitingForPlayers)
	{
		TakeSnapshot(0);
		g_mapStartTime = GetTime();
		g_waitingForPlayers = false;
	}
	
	new uid = GetClientUserId(client);
	if(g_userId[client] != uid)
	{
		g_userId[client] = uid;
		new val;
		if(GetTrieValue(hPlayerTrie, auth, val))
		{
			g_playerQuits--;
		}
		else
		{
			g_playerJoins++;
		}
	}
	
	SetTrieValue(hPlayerTrie, auth, true);
}

public Action:Event_PlayerDisconnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_playerQuits++;
}

public Action:Timer_Snapshot(Handle:Timer)
{
	if(!g_waitingForPlayers && !g_mapChanging)
	{
		new pop = GetRealClientCount();
		if(pop > 0)
		{
			PushArrayCell(hSnapshots, pop);
			TakeSnapshot(pop);
		}
		else
		{
			TakeSnapshot(0);
			SendSummary();
			g_waitingForPlayers = true;
		}
	}
}

public Action:Timer_Mapchange(Handle:Timer)
{
	g_mapChanging = false;
}

TakeSnapshot(pop)
{
	if(hDatabase != INVALID_HANDLE && g_serverId > 0 && g_mapId > 0)
	{
		decl String:query[512];
		Format(query, sizeof(query), "INSERT INTO `mapstats_pop` (`serverid`, `mapid`, `pop`) VALUES (%d, %d, %d);", g_serverId, g_mapId, pop);
		SQL_TQuery(hDatabase, T_FastQuery, query);
	}
}

GetRealClientCount()
{
	new clients = 0;
	for(new i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			clients++;
		}
	}
	return clients;
}

// Threaded DB stuff
public T_DBConnect(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl == INVALID_HANDLE)
	{
		SetFailState(error);
	}
	hDatabase = hndl;
	SQL_TQuery(hndl, T_FastQuery, "CREATE TABLE IF NOT EXISTS `mapstats_servers` (`id` int NOT NULL AUTO_INCREMENT, `ip` varchar(64) NOT NULL, `name` text NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `ip` (`ip`)) ENGINE=InnoDB;");
	SQL_TQuery(hndl, T_FastQuery, "CREATE TABLE IF NOT EXISTS `mapstats_maps` (`id` int NOT NULL AUTO_INCREMENT, `name` varchar(64) NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `name` (`name`)) ENGINE=InnoDB;");
	SQL_TQuery(hndl, T_FastQuery, "CREATE TABLE IF NOT EXISTS `mapstats_pop` (`serverid` int NOT NULL, `mapid` int NOT NULL, `pop` int NOT NULL, `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;");
	SQL_TQuery(hndl, T_FastQuery, "CREATE TABLE IF NOT EXISTS `mapstats_summary` (`serverid` int NOT NULL, `mapid` int NOT NULL, `popavg` int NOT NULL, `quits` int NOT NULL, `joins` int NOT NULL, `duration` int NOT NULL, `time` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;");
	
	g_hostip = GetConVarInt(FindConVar("hostip"));
	g_hostport = GetConVarInt(FindConVar("hostport"));
	
	decl String:query[512];
	Format(query, sizeof(query), "SELECT `id` FROM `mapstats_servers` WHERE `ip` = '%d:%d';", g_hostip, g_hostport);
	SQL_TQuery(hndl, T_FetchServerId, query);
	
	LoadMap();
}

public T_FetchServerId(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	decl String:serverName[256], String:serverNameSafe[512], String:query[1024];
	GetConVarString(FindConVar("hostname"), serverName, sizeof(serverName));	
	SQL_EscapeString(hDatabase, serverName, serverNameSafe, sizeof(serverNameSafe));
	
	if(hndl != INVALID_HANDLE)
	{
		if(SQL_GetRowCount(hndl) > 0)
		{
			if(SQL_FetchRow(hndl))
			{
				g_serverId = SQL_FetchInt(hndl, 0);
				Format(query, sizeof(query), "UPDATE `mapstats_servers` SET `name` = '%s' WHERE `id` = %d;", serverNameSafe, g_serverId);
				SQL_TQuery(hDatabase, T_FastQuery, query);
				return;
			}
		}
	}
	
	Format(query, sizeof(query), "INSERT INTO `mapstats_servers` (`ip`, `name`) VALUES ('%d:%d', '%s');", g_hostip, g_hostport, serverNameSafe);
	SQL_TQuery(hDatabase, T_InsertServer, query);
}

public T_InsertServer(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE && SQL_GetAffectedRows(owner) > 0)
	{
		g_serverId = SQL_GetInsertId(owner);
	}
}

public T_FetchMapId(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE)
	{
		if(SQL_GetRowCount(hndl) > 0)
		{
			if(SQL_FetchRow(hndl))
			{
				g_mapId = SQL_FetchInt(hndl, 0);
				return;
			}
		}
	}
	
	decl String:query[512];
	Format(query, sizeof(query), "INSERT INTO `mapstats_maps` (`name`) VALUES ('%s');", g_mapName);
	SQL_TQuery(hDatabase, T_InsertMap, query);
}

public T_InsertMap(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if(hndl != INVALID_HANDLE && SQL_GetAffectedRows(owner) > 0)
	{
		g_mapId = SQL_GetInsertId(owner);
	}
}

public T_FastQuery(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	// Nothing to do
}