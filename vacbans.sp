/**
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
 *   voogru - finding the relationship between SteamIDs and friendIDs
 *   StrontiumDog - the fixed function that converts SteamIDs
 *   berni - the original function that converts SteamIDs
 *   Sillium - German translation
 *   jack_wade - Spanish translation
 *   Tournevis_man - French translation
 *   OziOn - Danish translation
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
 *   [*] Fixed missing client name in admin messages
 * Feb 22, 2015 - v.1.4.2:
 *   [*] Fixed handling of incorrect usage of sm_vacbans_whitelist
 *   [*] Changed console commands to admin commands
 * Feb 12, 2015 - v.1.4.1:
 *   [*] Updated sm_vacbans_whitelist to accept new SteamIDs
 *   [+] Added option to alert admins to VAC banned players
 * Feb 07, 2015 - v.1.4.0:
 *   [*] Updated to support SourceMod 1.7
 *   [*] Fixed DataPack operation out of bounds errors
 * Nov 15, 2013 - v.1.3.6:
 *   [*] Fixed DataPack operation out of bounds errors
 * Mar 27, 2013 - v.1.3.5:
 *   [*] Fixed bans firing too early
 * Sep 04, 2011 - v.1.3.4:
 *   [*] Fixed some race conditions
 * Feb 09, 2010 - v.1.3.3:
 *    [+] Added filter for bots on client checks
 * Jul 24, 2009 - v.1.3.2:
 *    [*] Fixed logging error
 * Jul 18, 2009 - v.1.3.1:
 * 	  [*] Removed format from translations to fix odd error
 * May 25, 2009 - v.1.3.0:
 * 	  [+] Added support for other named database configs
 * Apr 13, 2009 - v.1.2.1:
 * 	  [*] Fixed conversion of long SteamIDs (StrontiumDog)
 * Mar 26, 2009 - v.1.2.0:
 * 	  [+] Added whitelist support
 * 	  [*] Changed some messages to reflect the plugin name
 * Mar 19, 2009 - v.1.1.1:
 *    [*] Fixed bans triggering before client is in-game
 * 	  [-] Removed dependency on the regex extension
 * 	  [+] Added logging to vacbans.log for all action settings
 * Feb 23, 2009 - v.1.1.0:
 * 	  [*] Now uses DataPacks instead of files for data storage
 * 	  [+] Added RegEx to scan raw downloaded data
 * 	  [+] Verifies client against original ID after scanning profile
 * 	  [*] Now uses FriendID instead of SteamID for the database keys
 * 	  [*] Various code organization improvements
 * 	  [+] Added command to reset the local cache database
 * Feb 19, 2009 - v.1.0.1:
 * 	  [*] Changed file naming to avoid conflicts
 * Nov 24, 2008 - v.1.0.0:
 * 	  [*] Initial Release
 * 
 */

#include <sourcemod>
#include <socket>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.4.3"
#define DATABASE_VERSION 1

public Plugin myinfo = 
{
	name = "VAC Status Checker",
	author = "Stevo.TVR",
	description = "Looks up VAC status of connecting clients and takes desired action",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org"
}

Database g_hDatabase = null;

ConVar g_hCVDB = null;
ConVar g_hCVCacheTime = null;
ConVar g_hCVAction = null;
ConVar g_hCVDetectVACBans = null;
ConVar g_hCVDetectGameBans = null;
ConVar g_hCVDetectCommunityBans = null;
ConVar g_hCVDetectEconBans = null;

char g_dbConfig[64];

public void OnPluginStart()
{
	LoadTranslations("vacbans.phrases");
	char desc[256];

	Format(desc, sizeof(desc), "%T", "ConVar_Version", LANG_SERVER);
	CreateConVar("sm_vacbans_version", PLUGIN_VERSION, desc, FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

	Format(desc, sizeof(desc), "%T", "ConVar_DB", LANG_SERVER);
	g_hCVDB = CreateConVar("sm_vacbans_db", "storage-local", desc);
	Format(desc, sizeof(desc), "%T", "ConVar_CacheTime", LANG_SERVER);
	g_hCVCacheTime = CreateConVar("sm_vacbans_cachetime", "30", desc, _, true, 0.0);
	Format(desc, sizeof(desc), "%T", "ConVar_Action", LANG_SERVER);
	g_hCVAction = CreateConVar("sm_vacbans_action", "0", desc, _, true, 0.0, true, 3.0);
	Format(desc, sizeof(desc), "%T", "ConVar_Detect_VAC", LANG_SERVER);
	g_hCVDetectVACBans = CreateConVar("sm_vacbans_detect_vac_bans", "1", desc, _, true, 0.0, true, 1.0);
	Format(desc, sizeof(desc), "%T", "ConVar_Detect_Game", LANG_SERVER);
	g_hCVDetectGameBans = CreateConVar("sm_vacbans_detect_game_bans", "0", desc, _, true, 0.0, true, 1.0);
	Format(desc, sizeof(desc), "%T", "ConVar_Detect_Community", LANG_SERVER);
	g_hCVDetectCommunityBans = CreateConVar("sm_vacbans_detect_community_bans", "0", desc, _, true, 0.0, true, 1.0);
	Format(desc, sizeof(desc), "%T", "ConVar_Detect_Econ", LANG_SERVER);
	g_hCVDetectEconBans = CreateConVar("sm_vacbans_detect_econ_bans", "0", desc, _, true, 0.0, true, 1.0);
	AutoExecConfig(true, "vacbans");

	Format(desc, sizeof(desc), "%T", "Command_Reset", LANG_SERVER);
	RegAdminCmd("sm_vacbans_reset", Command_Reset, ADMFLAG_RCON, desc);
	Format(desc, sizeof(desc), "%T", "Command_Whitelist", LANG_SERVER);
	RegAdminCmd("sm_vacbans_whitelist", Command_Whitelist, ADMFLAG_RCON, desc);
}

public void OnConfigsExecuted()
{
	char db[64];
	g_hCVDB.GetString(db, sizeof(db));
	if(!StrEqual(g_dbConfig, db))
	{
		strcopy(g_dbConfig, sizeof(g_dbConfig), db);
		Database.Connect(OnDBConnected, db);
	}
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

			Format(query, sizeof(query), "SELECT * FROM `vacbans_cache` WHERE `steam_id` = '%s' AND (`expire` > %d OR `expire` = 0) LIMIT 1;", steamID, GetTime());
			g_hDatabase.Query(OnQueryPlayerLookup, query, hPack);
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

	if(!StrEqual(responseData, "null", false))
	{
		char parts[4][10];
		int count = ExplodeString(responseData, ",", parts, sizeof(parts), sizeof(parts[]), false);

		int vacBans = count > 0 ? StringToInt(parts[0]) : 0;
		int gameBans = count > 1 ? StringToInt(parts[1]) : 0;
		bool communityBanned = count > 2 ? StringToInt(parts[2]) == 1 : false;
		int econStatus = count > 3 ? StringToInt(parts[3]) : 0;

		HandleClient(client, friendID, vacBans, gameBans, communityBanned, econStatus, false);
	}
	else
	{
		HandleClient(client, friendID, 0, 0, false, 0, false);
	}

	delete hData;
	delete hPack;

	delete hSock;
}

public int OnSocketError(Handle hSock, const int errorType, const int errorNum, DataPack hPack)
{
	LogError("%T", "Error_Socket", LANG_SERVER, errorType, errorNum);

	delete hPack;
	delete hSock;
}

public Action Command_Reset(int client, int args)
{
	g_hDatabase.Query(OnQueryNoOp, "DELETE FROM `vacbans_cache` WHERE `expire` != 0;");
	ReplyToCommand(client, "[SM] %t", "Message_Reset");
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
				Format(query, sizeof(query), "REPLACE INTO `vacbans_cache` (`steam_id`, `expire`) VALUES ('%s', 0);", friendID);
				g_hDatabase.Query(OnQueryNoOp, query);

				ReplyToCommand(client, "[SM] %t", "Message_Whitelist_Added", steamID);

				return Plugin_Handled;
			}
			if(StrEqual(action, "remove"))
			{
				Format(query, sizeof(query), "DELETE FROM `vacbans_cache` WHERE `steam_id` = '%s';", friendID);
				g_hDatabase.Query(OnQueryNoOp, query);

				ReplyToCommand(client, "[SM] %t", "Message_Whitelist_Removed", steamID);

				return Plugin_Handled;
			}
		}
	}
	else
	{
		if(StrEqual(action, "clear"))
		{
			g_hDatabase.Query(OnQueryNoOp, "DELETE FROM `vacbans_cache` WHERE `expire` = 0;");

			ReplyToCommand(client, "[SM] %t", "Message_Whitelist_Cleared");

			return Plugin_Handled;
		}
	}

	ReplyToCommand(client, "%t: sm_vacbans_whitelist <add|remove|clear> [SteamID]", "Message_Usage");
	return Plugin_Handled;
}

void HandleClient(int client, const char[] friendID, int numVACBans, int numGameBans, bool communityBanned, int econStatus, bool fromCache)
{
	if(IsClientAuthorized(client))
	{
		// Check to make sure this is the same client that originally connected
		char clientFriendID[32];
		if(!GetClientAuthId(client, AuthId_SteamID64, clientFriendID, sizeof(clientFriendID)) || !StrEqual(friendID, clientFriendID))
		{
			return;
		}

		int expire = GetTime() + g_hCVCacheTime.IntValue * 86400;

		bool vacBanned = numVACBans > 0 && g_hCVDetectVACBans.BoolValue;
		bool gameBanned = numGameBans > 0 && g_hCVDetectGameBans.BoolValue;
		bool commBanned = communityBanned && g_hCVDetectCommunityBans.BoolValue;
		bool econBanned = econStatus > 0 && g_hCVDetectEconBans.BoolValue;

		if(vacBanned || gameBanned || commBanned || econBanned)
		{
			char reason[32];
			if(vacBanned && numVACBans > 1)
			{
				reason = "VAC_Ban_Plural";
			}
			else if(vacBanned)
			{
				reason = "VAC_Ban";
			}
			else if(gameBanned && numGameBans > 1)
			{
				reason = "Game_Ban_Plural";
			}
			else if(gameBanned)
			{
				reason = "Game_Ban";
			}
			else if(commBanned)
			{
				reason = "Community_Ban";
			}
			else if(econBanned && econStatus > 1)
			{
				reason = "Economy_Ban";
			}
			else if(econBanned)
			{
				reason = "Economy_Probation";
			}

			char commStatusText[16];
			if(communityBanned)
			{
				commStatusText = "Status_Banned";
			}
			else
			{
				commStatusText = "Status_None";
			}

			char econStatusText[24];
			switch(econStatus)
			{
				case 1:
					econStatusText = "Status_Probation";
				case 2:
					econStatusText = "Status_Banned";
				default:
					econStatusText = "Status_None";
			}
			
			switch(g_hCVAction.IntValue)
			{
				case 0:
				{
					char userformat[64];
					Format(userformat, sizeof(userformat), "%L", client);
					LogAction(0, client, "%T", "Log_Banned", LANG_SERVER, userformat, reason);

					ServerCommand("sm_ban #%d 0 \"[VAC Status Checker] %T\"", GetClientUserId(client), "Player_Message", client, "Banned", reason);
				}
				case 1:
				{
					KickClient(client, "[VAC Status Checker] %t", "Player_Message", "Kicked", reason);
				}
				case 2:
				{
					for(int i = 1; i <= MaxClients; i++)
					{
						if(IsClientInGame(i) && !IsFakeClient(i) && CheckCommandAccess(i, "sm_listvac", ADMFLAG_BAN))
						{
							PrintToChat(i, "[VAC Status Checker] [%N] %t", client, "Admin_Message", numVACBans, numGameBans, commStatusText, econStatusText);
						}
					}
				}
			}

			char path[PLATFORM_MAX_PATH];
			BuildPath(Path_SM, path, sizeof(path), "logs/vacbans.log");
			LogToFile(path, "%L %T", client, "Admin_Message", LANG_SERVER, numVACBans, numGameBans, commStatusText, econStatusText);
		}

		if(!fromCache)
		{
			char query[1024];
			Format(query, sizeof(query), "REPLACE INTO `vacbans_cache` VALUES ('%s', %d, %d, %d, %d, %d);", friendID, numVACBans, numGameBans, communityBanned ? 1 : 0, econStatus, expire);
			g_hDatabase.Query(OnQueryNoOp, query);
		}
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

// Threaded DB callbacks
public void OnDBConnected(Database db, const char[] error, any data)
{
	if(db == null)
	{
		SetFailState(error);
	}
	g_hDatabase = db;
	g_hDatabase.Query(OnQueryVersionCheck, "SELECT `version` FROM `vacbans_version`;");
}

public void OnQueryVersionCheck(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null || !results.FetchRow())
	{
		g_hDatabase.Query(OnQueryVersionCreated, "CREATE TABLE IF NOT EXISTS `vacbans_version` (`version` INT(11) NOT NULL);");
		g_hDatabase.Query(OnQueryCacheCreated, "CREATE TABLE IF NOT EXISTS `vacbans_cache` (`steam_id` VARCHAR(64) NOT NULL, `vac_bans` INT(11), `game_bans` INT(11), `community_banned` BOOL, `econ_status` INT(11), `expire` INT(11) NOT NULL, PRIMARY KEY (`steam_id`));");
	}
}

public void OnQueryVersionCreated(Database db, DBResultSet results, const char[] error, any data)
{
	char query[512];
	Format(query, sizeof(query), "INSERT INTO `vacbans_version` VALUES (%d);", DATABASE_VERSION);
	g_hDatabase.Query(OnQueryNoOp, query);
}

public void OnQueryCacheCreated(Database db, DBResultSet results, const char[] error, any data)
{
	g_hDatabase.Query(OnQueryMigrate, "SELECT `steam_id` FROM `vacbans` WHERE `banned` = 0 AND `expire` = 0;");
}

public void OnQueryMigrate(Database db, DBResultSet results, const char[] error, any data)
{
	if(results != null)
	{
		char steamId[32];
		char query[512];
		while(results.FetchRow())
		{
			results.FetchString(0, steamId, sizeof(steamId));
			Format(query, sizeof(query), "INSERT INTO `vacbans_cache` (`steam_id`, `expire`) VALUES ('%s', 0);", steamId);
			g_hDatabase.Query(OnQueryNoOp, query);
		}
		g_hDatabase.Query(OnQueryNoOp, "DROP TABLE `vacbans`;");
	}
}

public void OnQueryPlayerLookup(Database db, DBResultSet results, const char[] error, DataPack data)
{
	bool checked = false;

	data.Reset();
	int client = data.ReadCell();
	char friendID[32];
	data.ReadString(friendID, sizeof(friendID));
	delete data;

	if(results != null)
	{
		if(results.FetchRow())
		{
			checked = true;
			if(results.IsFieldNull(1))
			{
				// Player is whitelisted
				return;
			}
			HandleClient(client, friendID, results.FetchInt(1), results.FetchInt(2), results.FetchInt(3) == 1, results.FetchInt(4), true);
		}
	}

	if(!checked)
	{
		DataPack hPack = new DataPack();
		DataPack hData = new DataPack();
		Handle hSock = SocketCreate(SOCKET_TCP, OnSocketError);

		hPack.WriteCell(client);
		hPack.WriteCell(hData);
		hPack.WriteString(friendID);

		SocketSetArg(hSock, hPack);
		SocketConnect(hSock, OnSocketConnected, OnSocketReceive, OnSocketDisconnected, "dev.stevotvr.com", 80);
	}
}

public void OnQueryNoOp(Database db, DBResultSet results, const char[] error, any data)
{
	// Nothing to do
}

// You're crazy, man...