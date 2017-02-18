/*
* 
* VAC Status Checker
* http://forums.alliedmods.net/showthread.php?t=80942
* 
* Description:
* Looks up VAC Status of connecting clients using the Steam
* Community and takes the desired action. Useful for admins who want to
* block access to people caught cheating on another engine.
* 
* Requires Socket Extension by sfPlayer
* (http://forums.alliedmods.net/showthread.php?t=67640)
* 
* Credits:
* 	voogru - finding the relationship between SteamIDs and friendIDs
*   StrontiumDog - the fixed function that converts SteamIDs
* 	berni - the original function that converts SteamIDs
* 	Sillium - German translation
* 	jack_wade - Spanish translation
* 	Tournevis_man - French translation
* 	OziOn - Danish translation
*   danielsumi - Portuguese translation
*   Archangel_Dm - Russian translation
*   lhffan - Swedish translation
*   ZuCChiNi - Turkish translation
*   allienaded - Finnish translation
*   Wilczek - Polish translation
*   r3dw3r3w0lf - admin alert code
* 
* Changelog
* Mar 08, 2015 - v.1.4.3:
*               [*] Fixed missing client name in admin messages
* Feb 22, 2015 - v.1.4.2:
*               [*] Fixed handling of incorrect usage of sm_vacbans_whitelist
*               [*] Changed console commands to admin commands
* Feb 12, 2015 - v.1.4.1:
*               [*] Updated sm_vacbans_whitelist to accept new SteamIDs
*               [+] Added option to alert admins to VAC banned players
* Feb 07, 2015 - v.1.4.0:
*               [*] Updated to support SourceMod 1.7
*               [*] Fixed DataPack operation out of bounds errors
* Nov 15, 2013 - v.1.3.6:
*               [*] Fixed DataPack operation out of bounds errors
* Mar 27, 2013 - v.1.3.5:
*               [*] Fixed bans firing too early
* Sep 04, 2011 - v.1.3.4:
*               [*] Fixed some race conditions
* Feb 09, 2010 - v.1.3.3:
* 				[+] Added filter for bots on client checks
* Jul 24, 2009 - v.1.3.2:
* 				[*] Fixed logging error
* Jul 18, 2009 - v.1.3.1:
* 				[*] Removed format from translations to fix odd error
* May 25, 2009 - v.1.3.0:
* 				[+] Added support for other named database configs
* Apr 13, 2009 - v.1.2.1:
* 				[*] Fixed conversion of long SteamIDs (StrontiumDog)
* Mar 26, 2009 - v.1.2.0:
* 				[+] Added whitelist support
* 				[*] Changed some messages to reflect the plugin name
* Mar 19, 2009 - v.1.1.1:
* 				[*] Fixed bans triggering before client is in-game
* 				[-] Removed dependency on the regex extension
* 				[+] Added logging to vacbans.log for all action settings
* Feb 23, 2009 - v.1.1.0:
* 				[*] Now uses DataPacks instead of files for data storage
* 				[+] Added RegEx to scan raw downloaded data
* 				[+] Verifies client against original ID after scanning profile
* 				[*] Now uses FriendID instead of SteamID for the database keys
* 				[*] Various code organization improvements
* 				[+] Added command to reset the local cache database
* Feb 19, 2009 - v.1.0.1:
* 				[*] Changed file naming to avoid conflicts
* Nov 24, 2008 - v.1.0.0:
* 				[*] Initial Release
* 
*/

#include <sourcemod>
#include <socket>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.4.3"

public Plugin myinfo = 
{
	name = "VAC Status Checker",
	author = "Stevo.TVR",
	description = "Looks up VAC status of connecting clients and takes desired action",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org"
}

Database hDatabase = null;

ConVar sm_vacbans_db = null;
ConVar sm_vacbans_cachetime = null;
ConVar sm_vacbans_action = null;

public void OnPluginStart()
{
	CreateConVar("sm_vacbans_version", PLUGIN_VERSION, "VAC Ban Checker plugin version", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	sm_vacbans_db = CreateConVar("sm_vacbans_db", "storage-local", "The named database config to use for caching");
	sm_vacbans_cachetime = CreateConVar("sm_vacbans_cachetime", "30", "How long in days before re-checking the same client for VAC status", _, true, 0.0);
	sm_vacbans_action = CreateConVar("sm_vacbans_action", "0", "Action to take on VAC banned clients (0 = ban, 1 = kick, 2 = alert admins, 3 = log only)", _, true, 0.0, true, 3.0);
	AutoExecConfig(true, "vacbans");
	
	RegAdminCmd("sm_vacbans_reset", Command_Reset, ADMFLAG_RCON, "Clears the local vacbans SQLite database");
	RegAdminCmd("sm_vacbans_whitelist", Command_Whitelist, ADMFLAG_RCON, "Controls the vacbans whitelist");
	
	LoadTranslations("vacbans.phrases");
}

public void OnConfigsExecuted()
{
	char db[64];
	sm_vacbans_db.GetString(db, sizeof(db));
	Database.Connect(T_DBConnect, db);
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		char query[1024];
		char steamID[32];
		
		if(GetClientAuthId(client, AuthId_SteamID64, steamID, sizeof(steamID)))
		{
			DataPack hPack = new DataPack();
			hPack.WriteCell(client);
			hPack.WriteString(steamID);
			
			Format(query, sizeof(query), "SELECT * FROM `vacbans` WHERE `steam_id` = '%s' AND (`expire` > %d OR `expire` = 0) LIMIT 1;", steamID, GetTime());
			hDatabase.Query(T_PlayerLookup, query, hPack);
		}
	}
}

public int OnSocketConnected(Handle hSock, DataPack hPack)
{
	char friendID[32];
	char requestStr[128];
	
	hPack.Reset();
	hPack.ReadCell();
	hPack.ReadCell();
	hPack.ReadString(friendID, sizeof(friendID));
	
	Format(requestStr, sizeof(requestStr), "GET /vacbans/v1/check/%s HTTP/1.0\r\nHost: %s\r\nConnection: close\r\n\r\n", friendID, "dev.stevotvr.com");
	SocketSend(hSock, requestStr);
}

public int OnSocketReceive(Handle hSock, const char[] receiveData, const int dataSize, DataPack hPack)
{
	hPack.Reset();
	hPack.ReadCell();
	DataPack hData = hPack.ReadCell();
	
	hData.WriteString(receiveData);
}

public int OnSocketDisconnected(Handle hSock, DataPack hPack)
{
	hPack.Reset();
	int client = hPack.ReadCell();
	DataPack hData = hPack.ReadCell();
	
	hData.Reset();
	char responseData[512];
	char buffer[512];
	while(hData.IsReadable()) {
		hData.ReadString(buffer, sizeof(buffer));
		StrCat(responseData, sizeof(responseData), buffer);
	}
	char responseParts[2][32];
	if(ExplodeString(responseData, "\r\n\r\n", responseParts, sizeof(responseParts), sizeof(responseParts[])) > 1)
	{
		responseData = responseParts[1];
	}
	TrimString(responseData);

	char friendID[32];
	hPack.ReadString(friendID, sizeof(friendID));

	PrintToServer(responseData);

	if(!StrEqual(responseData, "null", false))
	{
		char parts[4][10];
		int count = ExplodeString(responseData, ",", parts, sizeof(parts), sizeof(parts[]), false);
		
		if(count >= 1)
		{
			HandleClient(client, friendID, StringToInt(parts[0]) > 0);
			PrintToServer("banned: %d", StringToInt(parts[0]));
		}
		else
		{
			HandleClient(client, friendID, false);
		}
	}
	else
	{
		HandleClient(client, friendID, false);
	}

	delete hData;
	delete hPack;

	delete hSock;
}

public int OnSocketError(Handle hSock, const int errorType, const int errorNum, DataPack hPack)
{
	LogError("Socket error %d (errno %d)", errorType, errorNum);
	
	delete hPack;
	delete hSock;
}

public Action Command_Reset(int client, int args)
{
	hDatabase.Query(T_FastQuery, "DELETE FROM `vacbans` WHERE `expire` != 0;");
	ReplyToCommand(client, "[SM] Local VAC Status Checker cache has been reset.");
	return Plugin_Handled;
}

public Action Command_Whitelist(int client, int args)
{
	char argString[72];
	char action[8];
	char steamID[64];
	char friendID[64];
	
	GetCmdArgString(argString, sizeof(argString));
	int pos = BreakString(argString, action, sizeof(action));
	if(pos > -1)
	{
		strcopy(steamID, sizeof(steamID), argString[pos]);
		
		if(GetFriendID(steamID, friendID, sizeof(friendID)))
		{
			char query[1024];
			if(StrEqual(action, "add"))
			{
				Format(query, sizeof(query), "REPLACE INTO `vacbans` VALUES('%s', '0', '0');", friendID);
				hDatabase.Query(T_FastQuery, query);
				
				ReplyToCommand(client, "[SM] %s added to the VAC Status Checker whitelist.", steamID);
				
				return Plugin_Handled;
			}
			if(StrEqual(action, "remove"))
			{
				Format(query, sizeof(query), "DELETE FROM `vacbans` WHERE `steam_id` = '%s';", friendID);
				hDatabase.Query(T_FastQuery, query);
				
				ReplyToCommand(client, "[SM] %s removed from the VAC Status Checker whitelist.", steamID);
				
				return Plugin_Handled;
			}
		}
	}
	else
	{
		if(StrEqual(action, "clear"))
		{
			hDatabase.Query(T_FastQuery, "DELETE FROM `vacbans` WHERE `expire` = 0;");
			
			ReplyToCommand(client, "[SM] VAC Status Checker whitelist cleared.");
			
			return Plugin_Handled;
		}
	}
	
	ReplyToCommand(client, "Usage: sm_vacbans_whitelist <add|remove|clear> [SteamID]");
	return Plugin_Handled;
}

void HandleClient(int client, const char[] friendID, bool vacBanned)
{
	if(IsClientAuthorized(client))
	{
		// Check to make sure this is the same client that originally connected
		char clientFriendID[32];
		if(!GetClientAuthId(client, AuthId_SteamID64, clientFriendID, sizeof(clientFriendID)) || !StrEqual(friendID, clientFriendID))
		{
			return;
		}
		
		int banned = 0;
		int expire = GetTime() + (GetConVarInt(sm_vacbans_cachetime)*86400);
		int action = GetConVarInt(sm_vacbans_action);
		
		if(vacBanned)
		{
			banned = 1;
			switch(action)
			{
				case 0:
				{
					char userformat[64];
					Format(userformat, sizeof(userformat), "%L", client);
					LogAction(0, client, "%s %T", userformat, "Banned_Server", LANG_SERVER);
					
					ServerCommand("sm_ban #%d 0 \"[VAC Status Checker] %T\"", GetClientUserId(client), "Banned", client);
				}
				case 1:
				{
					KickClient(client, "[VAC Status Checker] %t", "Kicked");
				}
				case 2:
				{
					for (int i = 1; i <= MaxClients; i++)
					{
						if (IsClientInGame(i) && !IsFakeClient(i) && CheckCommandAccess(i, "sm_listvac", ADMFLAG_BAN))
						{
							PrintToChat(i, "[VAC Status Checker] %N has VAC bans on record.", client);
						}
					}
				}
			}
			char path[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, path, sizeof(path), "logs/vacbans.log");
			LogToFile(path, "Player %L is VAC Banned", client);
		}
		
		char query[1024];
		Format(query, sizeof(query), "REPLACE INTO `vacbans` VALUES('%s', '%d', '%d');", friendID, banned, expire);
		hDatabase.Query(T_FastQuery, query);
	}
}

bool GetFriendID(char[] AuthID, char[] FriendID, int size)
{
	char toks[3][18];
	int parts = ExplodeString(AuthID, ":", toks, sizeof(toks), sizeof(toks[]));
	int iFriendID;
	if(parts == 3)
	{
		if(StrContains(toks[0], "STEAM_", false) >= 0)
		{
			int iServer = StringToInt(toks[1]);
			int iAuthID = StringToInt(toks[2]);
			iFriendID = (iAuthID*2) + 60265728 + iServer;
		}
		else if(StrEqual(toks[0], "[U", false))
		{
			ReplaceString(toks[2], sizeof(toks[]), "]", "");
			int iAuthID = StringToInt(toks[2]);
			iFriendID = iAuthID + 60265728;
		}
		else
		{
			FriendID[0] = '\0';
			return false;
		}
	}
	else if(strlen(toks[0]) == 17 && IsCharNumeric(toks[0][0]))
	{
		strcopy(FriendID, size, AuthID);
		return true;
	}
	else
	{
		FriendID[0] = '\0';
		return false;
	}

	if (iFriendID >= 100000000)
	{
		int upper = 765611979;
		char temp[12], carry[12];
		
		Format(temp, sizeof(temp), "%d", iFriendID);
		Format(carry, 2, "%s", temp);
		int icarry = StringToInt(carry[0]);
		upper += icarry;

		Format(temp, sizeof(temp), "%d", iFriendID);
		Format(FriendID, size, "%d%s", upper, temp[1]);
	}
	else
	{
		Format(FriendID, size, "765611979%d", iFriendID);
	}

	return true;
}

// Threaded DB stuff
public void T_DBConnect(Database hndl, const char[] error, any data)
{
	if(hndl == null)
	{
		SetFailState(error);
	}
	hDatabase = hndl;
	hDatabase.Query(T_FastQuery, "CREATE TABLE IF NOT EXISTS `vacbans` (`steam_id` VARCHAR(64) NOT NULL, `banned` BOOL NOT NULL, `expire` INT(11) NOT NULL, PRIMARY KEY (`steam_id`));");
}

public void T_PlayerLookup(Database owner, DBResultSet hQuery, const char[] error, DataPack hPack)
{
	bool checked = false;
	
	hPack.Reset();
	int client = hPack.ReadCell();
	char friendID[32];
	hPack.ReadString(friendID, sizeof(friendID));
	delete hPack;
	
	if(hQuery != null)
	{
		if(hQuery.RowCount > 0)
		{
			checked = true;
			while(hQuery.FetchRow())
			{
				if(hQuery.FetchInt(1) > 0)
				{
					HandleClient(client, friendID, true);
				}
			}
		}
	}
	
	if(!checked)
	{
		DataPack hPack2 = new DataPack();
		DataPack hData = new DataPack();
		Handle hSock = SocketCreate(SOCKET_TCP, OnSocketError);
		
		hPack2.WriteCell(client);
		hPack2.WriteCell(hData);
		hPack2.WriteString(friendID);
		
		SocketSetArg(hSock, hPack2);
		SocketConnect(hSock, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "dev.stevotvr.com", 80);
	}
}

public void T_FastQuery(Database owner, DBResultSet hndl, const char[] error, any data)
{
	// Nothing to do
}

// You're crazy, man...