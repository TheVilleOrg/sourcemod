#pragma semicolon 1
#include <sourcemod>
#include <tf2_stocks>

#define PLUGIN_VERSION "1.0"

public Plugin:myinfo =
{
	name = "Set Heads",
	author = "StevoTVR",
	description = "Sets all Demos' heads to 4.",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org"
}

new Handle:sm_setheads_enable = INVALID_HANDLE;

public OnPluginStart()
{
	sm_setheads_enable = CreateConVar("sm_setheads_enable", "0", "Enable head count enforcement");
	HookEvent("player_spawn", Event_PlayerSpawn);
}
public Action:Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	if(GetConVarBool(sm_setheads_enable))
	{
		new client = GetClientOfUserId(GetEventInt(event, "userid"));
		CreateTimer(0.25, Timer_SetHeadsDelay, client);
	}
	return Plugin_Continue;
}
public Action:Timer_SetHeadsDelay(Handle:timer, any:client)
{
	if (IsClientInGame(client))
	{
		new TFClassType:class = TF2_GetPlayerClass(client);
		if(class == TFClass_DemoMan)
		{
			SetEntData(client, FindSendPropInfo("CTFPlayer", "m_iDecapitations"), 4, 4, true);
			SetEntData(client, FindSendPropInfo("CTFPlayer", "m_iHealth"), 210, 4, true);
			SetEntDataFloat(client, FindSendPropInfo("CTFPlayer", "m_flMaxspeed"), 370.0, true);
		}
	}
}