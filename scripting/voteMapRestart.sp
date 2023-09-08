#include <sourcemod>
#include <sdkhooks>
#include <sdktools_gamerules>
#include <multicolors>
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

#define PLUGIN_VERSION "0.0.1"

ConVar g_cPluginEnabled;
ConVar g_cMapRestartTime;
ConVar g_cVoteThreshold;
ConVar g_cExecutionDisallowTime;

bool g_bPluginEnabled;
float g_fMapRestartTime = 5.0;

int g_iCurrentPlayer;
int g_iVmrCmdVotes;
int g_iRequiredPlayerNum;
float g_fVoteThreshold;
float g_fExecutionDisallowTime;

bool votedPlayers[MAXPLAYERS+1];
bool g_bIsRestarting;
bool g_bExecutionAllowed;

char g_sCurrentMap[128];

public Plugin myinfo =
{
    name = "Vote map restart",
    author = "faketuna",
    description = "Restart map with vote",
    version = PLUGIN_VERSION,
    url = "https://short.f2a.dev/s/github"
};

public void OnPluginStart() {
    LoadTranslations("voteMapRestart.phrases");

    g_cPluginEnabled        = CreateConVar("vmr_enabled", "1", "Enable Disable plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cVoteThreshold        = CreateConVar("vmr_vote_threshold", "0.6", "How many votes requires in vote. (percent)", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cMapRestartTime     = CreateConVar("vmr_map_restart_time", "5.0", "How long to take restarting round when vote passed.");
    g_cExecutionDisallowTime     = CreateConVar("vmr_disallow_time", "60.0", "When elapsed specified time command will be disabled.");

    RegConsoleCmd("sm_vmr", CommandVMR, "");


    g_cPluginEnabled.AddChangeHook(OnCvarsChanged);
    g_cVoteThreshold.AddChangeHook(OnCvarsChanged);
    g_cMapRestartTime.AddChangeHook(OnCvarsChanged);
    g_cExecutionDisallowTime.AddChangeHook(OnCvarsChanged);

    g_iCurrentPlayer = 0;
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientConnected(i)) {
            OnClientConnected(i);
        }
    }
    HookEvent("round_start", OnRoundStart, EventHookMode_Post);
    HookEvent("player_spawn", OnPlayerSpawned, EventHookMode_Post);

    if(StrEqual(g_sCurrentMap, "")) {
        GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
    }
}

public Action CommandVMR(int client, int agrs) {
    if(!g_bPluginEnabled) {
        CPrintToChatAll("Plugin not enabled yet!");
        return Plugin_Handled;
    }

    if (!g_bExecutionAllowed) {
        CReplyToCommand(client, "%t%t", "vmr prefix", "vmr cmd only warmup");
        return Plugin_Handled;
    }

    if (IsFakeClient(client)) {
        CPrintToChatAll("Fake client!");
        return Plugin_Handled;
    }

    if (g_bIsRestarting) {
        CReplyToCommand(client, "%t%t", "vmr prefix", "vmr cmd restarting");
        return Plugin_Handled;
    }

    if (votedPlayers[client]) {
        CReplyToCommand(client, "%t%t", "vmr prefix", "vmr cmd already", g_iVmrCmdVotes, g_iRequiredPlayerNum);
        return Plugin_Handled;
    }
    char name[32];
    GetClientName(client, name, sizeof(name));
    g_iVmrCmdVotes++;
    votedPlayers[client] = true;
    TryRestart();
    CPrintToChatAll("%t%t", "vmr prefix", "vmr cmd wants restart", name, g_iVmrCmdVotes, g_iRequiredPlayerNum);
    return Plugin_Handled;
}

public void OnClientConnected(int client) {
    if(!IsFakeClient(client)) {
        g_iCurrentPlayer++;
        g_iRequiredPlayerNum = RoundToCeil(float(g_iCurrentPlayer) * g_fVoteThreshold);
    }
}

public void OnClientDisconnect(int client) {
    if(!IsFakeClient(client)) {
        g_iCurrentPlayer--;
        g_iRequiredPlayerNum = RoundToCeil(float(g_iCurrentPlayer) * g_fVoteThreshold);
        if(votedPlayers[client]) {
            votedPlayers[client] = false;
            g_iVmrCmdVotes--;
            TryRestart();
        }
    }
}

public Action OnRoundStart(Handle event, const char[] name, bool dontBroadcast) {
    Reset();
    return Plugin_Handled;
}

public void OnPlayerSpawned(Handle event, const char[] name, bool dontBroadcast) {
    if(!g_bPluginEnabled) {
        return;
    }

    int client = GetClientOfUserId(GetEventInt(event, "userid"));

    if(IsFakeClient(client)) {
        return;
    }
    CPrintToChat(client, "%t%t", "vmr prefix", "vmr cmd you can use now");
}

public void OnMapStart() {
    g_bExecutionAllowed = true;
    CreateTimer(g_fExecutionDisallowTime, CommandDisallowTimer, _, TIMER_FLAG_NO_MAPCHANGE);
    GetCurrentMap(g_sCurrentMap, sizeof(g_sCurrentMap));
}

public Action CommandDisallowTimer(Handle timer) {
    g_bExecutionAllowed = false;
    return Plugin_Handled;
}

public void syncValues() {
    g_fMapRestartTime = g_cMapRestartTime.FloatValue;
    g_bPluginEnabled    = g_cPluginEnabled.BoolValue;
    g_fVoteThreshold    = g_cVoteThreshold.FloatValue;
    g_fExecutionDisallowTime = g_cExecutionDisallowTime.FloatValue;
}

public void OnCvarsChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    syncValues();
}

public void OnConfigsExecuted() {
    syncValues();
}

public void Reset() {
    g_bIsRestarting = false;
    g_iVmrCmdVotes = 0;
    for(int i = 1; i <= MaxClients; i++) {
        if(IsClientConnected(i) && !IsFakeClient(i)) {
            votedPlayers[i] = false;
        }
    }
}

public void ReloadMap() {
    CreateTimer(g_fMapRestartTime, ReloadTimer);
}

public Action ReloadTimer(Handle timer) {
    if(StrEqual(g_sCurrentMap, "")) {
        CPrintToChatAll("%t%t", "vmr prefix", "vmr failed to fetch map name");
        return Plugin_Stop;
    }
    ForceChangeLevel(g_sCurrentMap, "Restarting the map because Vote map restart issued.");
    return Plugin_Stop;
}

public void TryRestart() {
    if(g_iVmrCmdVotes >= g_iRequiredPlayerNum && !g_bIsRestarting) {
        g_bIsRestarting = true;
        LogAction(0, -1, "Map reload vote passed! reloading map...");
        CPrintToChatAll("%t%t", "vmr prefix", "vmr vote success", RoundToFloor(g_fMapRestartTime));
        ReloadMap();
    }
}