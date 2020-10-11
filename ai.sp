#pragma semicolon 1
#pragma newdecls required

/* SM Includes */
#include <sourcemod>
#include <sdktools>
#include <sdktools_gamerules>
#define TIME_TO_TICK(%1)    (RoundToNearest((%1) / GetTickInterval()))
#define TICK_TO_TIME(%1)    ((%1) * GetTickInterval())
#define IS_CLIENT(%1)       (1 <= %1 <= MaxClients)
#define ABS(%1) ((%1)>0 ? (%1) : -(%1)) 
/* Plugin Info */
public Plugin myinfo =
{
    name = "Crow Aimbot Detector",
    author = "huoji",
    description = "Analyzes clients to detect aimbots",
    version = "0.0.1",
    url = "http://key08.com/"
};

/* Globals */
#define AIM_ANGLE_CHANGE	15	// Max angle change that a player should snap
#define AIM_BAN_MIN			4		// Minimum number of detections before an auto-ban is allowed
#define AIM_MIN_DISTANCE	50.0	// Minimum distance acceptable for a detection.
Handle g_IgnoreWeapons = INVALID_HANDLE;

float g_fEyeAngles[MAXPLAYERS+1][64][3];

float g_Sensitivity[MAXPLAYERS + 1];
float g_mYaw[MAXPLAYERS + 1];
float g_mPitch[MAXPLAYERS + 1];

int g_iEyeIndex[MAXPLAYERS+1];
int g_iMouse[MAXPLAYERS+1][64][2];
int g_iAimDetections[MAXPLAYERS+1];
int g_iAimbotBan = 0;
int g_iMaxAngleHistory;
int g_cheat = 0;
bool g_bIsShoting[MAXPLAYERS+1][64];
/* Plugin Functions */
public void OnPluginStart()
{
    // Store no more than 300ms worth of angle history.
    if ((g_iMaxAngleHistory = TIME_TO_TICK(0.3)) > sizeof(g_fEyeAngles[]))
    {
        g_iMaxAngleHistory = sizeof(g_fEyeAngles[]);
    }

    // Weapons to ignore when analyzing.
    g_IgnoreWeapons = CreateTrie();

    SetTrieValue(g_IgnoreWeapons, "weapon_knife", 1);
    SetTrieValue(g_IgnoreWeapons, "weapon_taser", 1);

    // Hooks.
    HookEntityOutput("trigger_teleport", "OnEndTouch", Teleport_OnEndTouch);
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEventEx("cs_intermission", Event_Intermission);
    g_cheat = CreateConVar("sm_crowai_cheat", "0", "0 = no cheat , 1 = cheating.", _, true, 0.0, true, 1.0);
    PrintToServer("[CrowAi] Init Success!");
}
void OnFileUploadCallBack(HTTPStatus status, any value)
{
    PrintToServer("Upload complete");
} 
public Action Event_Intermission(Handle event, const char[] name, bool dontBroadcast)
{
    PrintToChatAll("比赛结束!上传反作弊数据中!");
    //upload your saved data 
	return Plugin_Continue;
}
stock bool IsClientNew(int client)
{
    // Client must be ingame.
    return IsFakeClient(client) || GetGameTime() > GetClientTime(client);
}

stock void ZeroVector(float vec[3])
{
    vec[0] = vec[1] = vec[2] = 0.0;
}

stock bool IsVectorZero(const float vec[3])
{
    return vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0;
}

public void OnClientPutInServer(int client)
{
    if (IsClientNew(client))
    {
        g_iAimDetections[client] = 0;
        Aimbot_ClearAngles(client);
    }
}


public void Teleport_OnEndTouch(const char[] output, int caller, int activator, float delay)
{
    /* A client is being teleported in the map. */
    if (IS_CLIENT(activator) && IsClientConnected(activator))
    {
        Aimbot_ClearAngles(activator);
        CreateTimer(0.1 + delay, Timer_ClearAngles, GetClientUserId(activator), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    
    if (IS_CLIENT(client))
    {
        Aimbot_ClearAngles(client);
        CreateTimer(0.1, Timer_ClearAngles, userid, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    char sWeapon[32], dummy;
    //GetEventString(event, "weapon", sWeapon, sizeof(sWeapon));
    event.GetString("weapon", sWeapon, sizeof(sWeapon));

    if (GetTrieValue(g_IgnoreWeapons, sWeapon, dummy))
    {
        return;
    }
    if (GameRules_GetProp("m_bWarmupPeriod") == 1)
    {
         return;
    }
    int victim = GetClientOfUserId(event.GetInt("userid"));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));
    if (IS_CLIENT(attacker) && victim != attacker && IsClientInGame(attacker))
    {
        float vVictim[3], vAttacker[3];
        GetClientAbsOrigin(victim, vVictim);
        GetClientAbsOrigin(attacker, vAttacker);
        if (GetVectorDistance(vVictim, vAttacker) >= AIM_MIN_DISTANCE)
        {
            Aimbot_AnalyzeAngles(attacker);
        }
    }
}

public Action Timer_ClearAngles(Handle timer, any userid)
{
    /* Delayed because the client's angles can sometimes "spin" after being teleported. */
    int client = GetClientOfUserId(userid);
    
    if (IS_CLIENT(client))
    {
        Aimbot_ClearAngles(client);
    }
    
    return Plugin_Stop;
}

public Action Timer_DecreaseCount(Handle timer, any userid)
{
    /* Decrease the detection count by 1. */
    int client = GetClientOfUserId(userid);
    
    if (IS_CLIENT(client) && g_iAimDetections[client])
    {
        g_iAimDetections[client]--;
    }
    
    return Plugin_Stop;
}
int m_iShotsFired(int client)
{
    return GetEntPropEnt(client, Prop_Send, "m_iShotsFired");
}
float m_aimPunchAngleX(int client)
{
    float punch[3];
    GetEntPropVector(client, Prop_Send, "m_aimPunchAngle",punch);
    return punch[0];
}
float m_aimPunchAngleY(int client)
{
    float punch[3];
    GetEntPropVector(client, Prop_Send, "m_aimPunchAngle",punch);
    return punch[1];
}
public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
    g_fEyeAngles[client][g_iEyeIndex[client]] = angles;
    g_iMouse[client][g_iEyeIndex[client]] = mouse;
    g_bIsShoting[client][g_iEyeIndex[client]] = false;
    if(m_iShotsFired(client) > 2)
    {
        g_fEyeAngles[client][g_iEyeIndex[client]][0] += m_aimPunchAngleX(client) * 2;
        g_fEyeAngles[client][g_iEyeIndex[client]][1] += m_aimPunchAngleY(client) * 2;
        g_bIsShoting[client][g_iEyeIndex[client]] = true;
    }
    
    if (++g_iEyeIndex[client] == g_iMaxAngleHistory)
    {
        g_iEyeIndex[client] = 0;
    }
    return Plugin_Continue;
}
public void ConVar_QueryClient(QueryCookie cookie, int client, ConVarQueryResult result, const char[] cvarName, const char[] cvarValue)
{
    if(!IsFakeClient(client))
	{
		if(result == ConVarQuery_Okay)
		{
			if(StrEqual("sensitivity", cvarName))
			{
				g_Sensitivity[client] = StringToFloat(cvarValue);
			}else if(StrEqual("m_yaw", cvarName))
			{
				g_mYaw[client] = StringToFloat(cvarValue);
			}
            else if(StrEqual("m_pitch", cvarName))
			{
				g_mPitch[client] = StringToFloat(cvarValue);
			}
        }
    }
}

void Aimbot_AnalyzeAngles(int client)
{
    if(IsFakeClient(client))
        return;
    /* Analyze the client to see if their angles snapped. */
    float vLastAngles[3], vAngles[3], fAngleDiff,Last_AngleDiff;
    int idx = g_iEyeIndex[client];
    QueryClientConVar(client, "sensitivity", ConVar_QueryClient, client);
	QueryClientConVar(client, "m_yaw", ConVar_QueryClient, client);
    QueryClientConVar(client, "m_pitch", ConVar_QueryClient, client);
    int num_of_detect = 0;
    int num_of_detect_smooth = 0;
    //PrintToChatAll("[CrowAntiCheat] 开始分析 %N",client);
    char steamid[64];
    GetClientAuthId(client, AuthId_SteamID64, steamid, sizeof(steamid));
    char path_name[PLATFORM_MAX_PATH];
    Format(path_name, sizeof(path_name), "addons\\sourcemod\\ai\\ai_%s.csv",steamid);
    bool file_exists = true;
    if(!FileExists(path_name)){
        file_exists = false;
    }
    Handle handle_file = OpenFile(path_name, "a+");
    char file_head[19999];
    if(file_exists == false){
        bool first_meme = false;
        for (int i = 0; i < g_iMaxAngleHistory; i++)
        {
            if (i == 0)
            {
                continue;
            }
            if(first_meme == false){
                first_meme = true;
                Format(file_head, sizeof(file_head), "%d_x,%d_y,%d_diff,%d_mx,%d_my",i,i,i,i,i);
            }else{
                Format(file_head, sizeof(file_head), "%s,%d_x,%d_y,%d_diff,%d_mx,%d_my",file_head,i,i,i,i,i);
            }
           
        }
        WriteFileLine(handle_file, "%s,is_cheat",file_head);
        //PrintToChatAll("max_angle_tick: %d",g_iMaxAngleHistory);
    }
    bool first_meme2 = false;
    char cheat_data[19999];
    for (int i = 0; i < g_iMaxAngleHistory; i++)
    {
        if (idx == g_iMaxAngleHistory)
        {
            idx = 0;
        }
        if (IsVectorZero(g_fEyeAngles[client][idx]))
        {
            break;
        }
        // Nothing to compare on the first iteration.
        if (i == 0)
        {
            vLastAngles = g_fEyeAngles[client][idx];
            idx++;
            continue;
        }
        vAngles = g_fEyeAngles[client][idx];
        fAngleDiff = GetVectorDistance(vLastAngles, vAngles);
        // If the difference is being reported higher than 180, get the 'real' value.
        if (fAngleDiff > 180)
        {
            fAngleDiff = FloatAbs(fAngleDiff - 360);
        }
        
        if (fAngleDiff > AIM_ANGLE_CHANGE)
        {
            PrintToChatAll("[CrowAI] %N rage aimbot skip this data",client);
            CloseHandle(handle_file);
            return;
        }
        int mouse[2];
        mouse = g_iMouse[client][idx];
        if(first_meme2 == false){
            first_meme2 = true;
            Format(cheat_data, sizeof(cheat_data), "%f,%f,%f,%d,%d",g_fEyeAngles[client][idx][0],g_fEyeAngles[client][idx][1],fAngleDiff,mouse[0],mouse[1]);
        }else{
            Format(cheat_data, sizeof(cheat_data), "%s,%f,%f,%f,%d,%d",cheat_data,g_fEyeAngles[client][idx][0],g_fEyeAngles[client][idx][1],fAngleDiff,mouse[0],mouse[1]);
        }
        
        vLastAngles = vAngles;
        Last_AngleDiff = fAngleDiff;
        idx++;
    }
    int is_cheat = GetConVarInt(g_cheat);
    WriteFileLine(handle_file, "%s,%d",cheat_data,is_cheat);
    //PrintToChatAll("[CrowAI] %N 分析完毕",client);
    CloseHandle(handle_file);
}

void Aimbot_ClearAngles(int client)
{
    /* Clear angle history and reset the index. */
    g_iEyeIndex[client] = 0;
    
    for (int i = 0; i < g_iMaxAngleHistory; i++)
    {
        ZeroVector(g_fEyeAngles[client][i]);
        g_iMouse[client][i][0] = 0;
        g_iMouse[client][i][1] = 0;
    }
}
