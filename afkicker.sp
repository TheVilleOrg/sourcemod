#pragma semicolon 1
#include <sourcemod>

public Plugin:myinfo = 
{
	name = "AFK Kicker",
	author = "Stevo.TVR",
	description = "Kicks clients who are AFK for a certain period",
	version = "1.1",
	url = "http://www.theville.org/"
}

new Handle:sm_afk_enabled = INVALID_HANDLE;
new Handle:sm_afk_maxtime = INVALID_HANDLE;
new Handle:sm_afk_minplayers = INVALID_HANDLE;
new Handle:sm_afk_immunity = INVALID_HANDLE;

new Float:clientAngle[MAXPLAYERS+1];
new clientAFKTime[MAXPLAYERS+1];
new bool:clientAlive[MAXPLAYERS+1];

public OnPluginStart()
{
	sm_afk_enabled = CreateConVar("sm_afk_enabled", "1", "Enable AFK kicker", _, true, 0.0, true, 1.0);
	sm_afk_maxtime = CreateConVar("sm_afk_maxtime", "120", "Time a player must be AFK to be kicked", _, true, 0.0);
	sm_afk_minplayers = CreateConVar("sm_afk_minplayers", "0", "Number of clients that must be on the server before kicking AFK players", _, true, 0.0);
	sm_afk_immunity = CreateConVar("sm_afk_immunity", "1", "Sets whether or not admins are immune to the AFK kicker", _, true, 0.0, true, 1.0);
	AutoExecConfig(true, "afk_kicker");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
}

public OnMapStart()
{
	new maxPlayers = GetMaxClients();
	
	for(new i = 1; i <= maxPlayers; i++)
	{
		clientAFKTime[i] = 0;
		clientAlive[i] = false;
	}
	
	CreateTimer(10.0, Timer_CheckClients, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public OnClientDisconnect(client)
{
	clientAFKTime[client] = 0;
	clientAlive[client] = false;
}

public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	clientAFKTime[client] = 0;
	if(!GetEventBool(event, "dead"))
		clientAlive[client] = true;
}

public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	clientAlive[client] = false;
}

public Action:Timer_CheckClients(Handle:Timer)
{
	if(GetConVarBool(sm_afk_enabled) && GetClientCount(true) >= GetConVarInt(sm_afk_minplayers))
	{
		new maxPlayers = GetMaxClients();
		
		for(new i = 1; i <= maxPlayers; i++)
		{
			if(!IsClientConnected(i) || !IsClientInGame(i) || IsFakeClient(i) || !clientAlive[i] || IsImmune(i))
				continue;
			
			new Float:angle[3];
			GetClientAbsAngles(i, angle);
			if(clientAngle[i] == angle[1])
			{
				clientAFKTime[i] += 10;
				if(clientAFKTime[i] >= GetConVarInt(sm_afk_maxtime))
					KickClient(i, "You were AFK too long");
			}
			else
			{
				clientAFKTime[i] = 0;
				clientAngle[i] = angle[1];
			}
		}
	}
}

public IsImmune(client)
{
	new bool:immune = false;
	if(GetConVarBool(sm_afk_immunity))
	{
		if(((GetUserFlagBits(client) & ADMFLAG_ROOT) == ADMFLAG_ROOT)
			|| ((GetUserFlagBits(client) & ADMFLAG_CUSTOM1) == ADMFLAG_CUSTOM1))
			immune = true;
	}
	return immune;
}