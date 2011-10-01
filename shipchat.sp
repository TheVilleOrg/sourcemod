#pragma semicolon 1
#include <sourcemod>

public Plugin:myinfo = 
{
	name = "TheShip Chat",
	author = "Stevo.TVR",
	description = "Converts chat in TheShip to regular chat that plugins recognize",
	version = "1.1",
	url = "http://www.theville.org"
}

#define CHAT_SYMBOL '@'
#define SILENT_TRIGGER '!'

public OnPluginStart()
{
	RegConsoleCmd("say", Command_Say);
}

public Action:Command_Say(client, args)
{
	new String:text[192], String:prefix[8], startidx;
	
	if (GetCmdArgString(text, sizeof(text)) < 1 || client == 0)
	{
		return Plugin_Continue;
	}
	
	StripQuotes(text);
	startidx = SplitString(text, " ", prefix, sizeof(prefix));

	if(StrEqual(prefix, "/p", true))
	{
		FakeClientCommandEx(client, "say %s", text[startidx]);
		if(text[startidx] == CHAT_SYMBOL || text[startidx] == SILENT_TRIGGER)
			return Plugin_Handled;
	}
	else if(StrEqual(prefix, "/t", true) || StrEqual(prefix, "/i/s", true))
	{
		FakeClientCommandEx(client, "say_team %s", text[startidx]);
		if(text[startidx] == CHAT_SYMBOL || text[startidx] == SILENT_TRIGGER)
			return Plugin_Handled;
	}
	
	return Plugin_Continue;
}