#include <sourcemod>
#pragma semicolon 1

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo = 
{
	name = "Team Balancer",
	author = "Stevo.TVR",
	description = "Keeps the teams even",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org/"
}

#define TEAM1 1
#define TEAM2 2

new Handle:sm_tb_enabled = INVALID_HANDLE;
new Handle:sm_tb_limitteams = INVALID_HANDLE;
new Handle:sm_tb_immunity = INVALID_HANDLE;

new bool:active = false;
new bool:playerDead[MAXPLAYERS+1];

public OnPluginStart()
{
	CreateConVar("sm_teambalancer_version", PLUGIN_VERSION, "Insurgency Team Balancer version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	sm_tb_enabled = CreateConVar("sm_tb_enabled", "1", "Enable team balancing", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	sm_tb_limitteams = CreateConVar("sm_tb_limitteams", "1", "Maximum difference between team counts", FCVAR_PLUGIN, true, 0.0);
	sm_tb_immunity = CreateConVar("sm_tb_immunity", "1", "Make admins immune to team balancing", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	AutoExecConfig(true, "teambalancer");
	
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	CreateTimer(10.0, Timer_CheckTeams, _, TIMER_REPEAT);
}

public OnMapStart()
{
	new maxPlayers = GetMaxClients();
	for(new i = 1; i <= maxPlayers; i++)
		playerDead[i] = true;
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	playerDead[client] = true;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	playerDead[client] = false;
}

public Action:Timer_CheckTeams(Handle:Timer)
{
	if(!GetConVarBool(sm_tb_enabled) || active)
		return;
	
	if(findUnevenTeam())
	{
		active = true;
		PrintToChatAll("Teams will auto-balance in 5 seconds...");
		CreateTimer(4.0, triggerBalance);
	}
}

public Action:triggerBalance(Handle:Timer)
{
	CreateTimer(1.0, balanceTeams, _, TIMER_REPEAT);
}

public Action:balanceTeams(Handle:Timer)
{
	new team = findUnevenTeam();
	if(team)
	{
		new maxPlayers = GetMaxClients();
//		new arrayPlayers[maxPlayers];
		
//		for(new i = 1; i <= maxPlayers; i++)
//			arrayPlayers[i] = GetClientUserId(i);
		
//		SortIntegers(arrayPlayers, maxPlayers, Sort_Descending);
		
		for(new i = 1; i <= maxPlayers; i++)
		{
			if(IsClientConnected(i) && IsClientInGame(i) && playerDead[i] && !IsImmune(i))
			{
				if(GetClientTeam(i) == team)
				{
					switchPlayerTeam(i);
					active = false;
					return Plugin_Stop;
				}
			}
		}
	} else {
		active = false;
		return Plugin_Stop;
	}
	return Plugin_Continue;
}

public switchPlayerTeam(client)
{
	new team = GetClientTeam(client);
	
	if(team == TEAM1)
		ChangeClientTeam(client, TEAM2);
	
	if(team == TEAM2)
		ChangeClientTeam(client, TEAM1);
}

public findUnevenTeam()
{
	new team1 = 0;
	new team2 = 0;
	new maxPlayers = GetMaxClients();
	
	for(new i = 1; i <= maxPlayers; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			new clientTeam = GetClientTeam(i);
			
			if(clientTeam == TEAM1)
				team1++;
			
			if(clientTeam == TEAM2)
				team2++;
		}
	}
	
	if((team1 - team2) > GetConVarInt(sm_tb_limitteams))
		return TEAM1;
	
	if((team2 - team1) > GetConVarInt(sm_tb_limitteams))
		return TEAM2;
	
	return false;
}

public IsImmune(client)
{
	new bool:immune = false;
	if(GetConVarBool(sm_tb_immunity))
	{
		if(((GetUserFlagBits(client) & ADMFLAG_ROOT) == ADMFLAG_ROOT)
			|| ((GetUserFlagBits(client) & ADMFLAG_CUSTOM1) == ADMFLAG_CUSTOM1))
			immune = true;
	}
	return immune;
}