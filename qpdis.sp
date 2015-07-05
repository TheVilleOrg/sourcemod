#pragma semicolon 1
#include <sourcemod>

public Plugin:myinfo = 
{
	name = "Quickplay Disabler",
	author = "Stevo.TVR",
	description = "Disables Quickplay at the specified player count",
	version = "1.0",
	url = "http://www.theville.org/"
}

new Handle:sm_qp_enabled = INVALID_HANDLE;
new Handle:sm_qp_maxplayers = INVALID_HANDLE;

public OnPluginStart()
{
	sm_qp_enabled = CreateConVar("sm_qp_enabled", "1", "Enable Quickplay", _, true, 0.0, true, 1.0);
	sm_qp_maxplayers = CreateConVar("sm_qp_maxplayers", "22", "Number of players at which to disable Quickplay", _, true, 0.0);
	AutoExecConfig(true, "qpdis");
}

public OnClientPutInServer(client)
{
	CheckLimit();
}

public OnClientDisconnect_Post(client)
{
	CheckLimit();
}

CheckLimit()
{
	new bool:enabled = false;
	if(GetConVarBool(sm_qp_enabled))
	{
		enabled = GetClientCount() < GetConVarInt(sm_qp_maxplayers);
	}
	
	SetConVarInt(FindConVar("tf_server_identity_disable_quickplay"), enabled ? 0 : 1);
}
