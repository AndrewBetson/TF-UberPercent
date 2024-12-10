// SPDX-FileCopyrightText: © Andrew Betson
// SPDX-License-Identifier: MIT

#include <sourcemod>
#include <dhooks>
#include <tf2>
#include <tf2_stocks>

#include <morecolors>

#pragma semicolon 1
#pragma newdecls required

#if !defined PLUGIN_VERSION
	#define PLUGIN_VERSION "1.0.0"
#endif // !defined PLUGIN_VERSION

DHookSetup gDetour_CTFPlayer_SpeakConceptIfAllowed;

ConVar gCVarEnabled;
bool gEnabled;

ConVar gCVarAlmostReadyPct;
float gAlmostReadyPct;

public Plugin myinfo =
{
	name		= "[TF2] ÜberCharge Percentage",
	description	= "Replaces Medic's \"ÜberCharge Ready\" voice subtitle with TF2C's ÜberCharge % ones",
	author		= "Andrew \"andrewb\" Betson",
	version		= PLUGIN_VERSION,
	url			= "https://www.github.com/AndrewBetson/TF-UberPercent/"
};

public void OnPluginStart()
{
	LoadTranslations( "uber_percent.phrases" );

	Handle MyGameData = LoadGameConfigFile( "uber_percent.games" );
	if ( !MyGameData )
	{
		SetFailState( "Failed to load uber_percent gamedata." );
	}

	gDetour_CTFPlayer_SpeakConceptIfAllowed = DHookCreateFromConf( MyGameData, "CTFPlayer::SpeakConceptIfAllowed" );
	if ( !DHookEnableDetour( gDetour_CTFPlayer_SpeakConceptIfAllowed, false, Detour_CTFPlayer_SpeakConceptIfAllowed ) )
	{
		SetFailState( "Failed to detour CTFPlayer::SpeakConceptIfAllowed, tell Andrew to update the signatures." );
	}

	gCVarEnabled = CreateConVar(
		"up_enabled",
		"1",
		"Whether the ÜberCharge Percentage plugin is enabled or not",
		FCVAR_NONE,
		true, 0.0,
		true, 1.0
	);
	gCVarEnabled.AddChangeHook( ConVar_Enabled );

	gCVarAlmostReadyPct = CreateConVar(
		"up_almost_ready_pct",
		"0.85",
		"Amount of ÜberCharge needed to use the \"almost ready\" callout instead of the \"not ready\" one",
		FCVAR_NONE,
		true, 0.01,
		true, 1.00
	);
	gCVarAlmostReadyPct.AddChangeHook( ConVar_AlmostReadyPct );

	AutoExecConfig( true, "uber_percent" );

	gEnabled = gCVarEnabled.BoolValue;
	gAlmostReadyPct = gCVarAlmostReadyPct.FloatValue;
}

void ConVar_Enabled( ConVar CVar, const char[] OldValue, const char[] NewValue )
{
	gEnabled = view_as< bool >( StringToInt( NewValue ) );
}

void ConVar_AlmostReadyPct( ConVar CVar, const char[] OldValue, const char[] NewValue )
{
	float NewPct = StringToFloat( NewValue );
	if ( NewPct > 0.0 )
	{
		gAlmostReadyPct = NewPct;
	}
}

public MRESReturn Detour_CTFPlayer_SpeakConceptIfAllowed( int This, DHookReturn Return, DHookParam Params )
{
	if ( !gEnabled )
	{
		return MRES_Ignored;
	}

	if ( TF2_GetPlayerClass( This ) != TFClass_Medic )
	{
		return MRES_Ignored;
	}

	int Concept = Params.Get( 1 );
	if ( Concept != 26 ) // TLK_PLAYER_CHARGEREADY
	{
		return MRES_Ignored;
	}

	// As far as I'm concerned this is a bug fix!
	// No Medigun? No Medigun-specific voice command!!!
	int MedigunHandle = GetEntPropEnt( This, Prop_Send, "m_hMyWeapons", 1 );
	if ( MedigunHandle == -1 )
	{
		Return.Value = false;
		return MRES_Supercede;
	}

	float UberPercent = GetEntPropFloat( MedigunHandle, Prop_Send, "m_flChargeLevel" );
	int RealUberPercent = RoundToFloor( UberPercent * 100.0 );
	TFTeam Team = TF2_GetClientTeam( This );

	if ( UberPercent < gAlmostReadyPct )
	{
		Return.Value = true;
		PrintToTeam( Team, This, "{teamcolor}%t %N{default}: %t", "UP_VoicePrefix", This, "UP_ChargeNotReady", RealUberPercent, "%%%" );
	}
	else if ( UberPercent < 1.0 )
	{
		Return.Value = true;
		PrintToTeam( Team, This, "{teamcolor}%t %N{default}: %t", "UP_VoicePrefix", This, "UP_ChargeAlmostReady", RealUberPercent, "%%%" );
	}
	else
	{
		PrintToTeam( Team, This, "{teamcolor}%t %N{default}: %t", "UP_VoicePrefix", This, "UP_ChargeReady", "%%%" );
		return MRES_Ignored;
	}

	return MRES_Supercede;
}

void PrintToTeam( TFTeam Team, int Client, const char[] Msg, any ... )
{
	int Len = strlen( Msg ) + 255;
	char[] FormattedMsg = new char[ Len ];
	VFormat( FormattedMsg, Len, Msg, 4 );

	for ( int i = 1; i <= MaxClients; i++ )
	{
		if ( !IsClientInGame( i ) )
		{
			continue;
		}
		if ( IsFakeClient( i ) )
		{
			continue;
		}
		if ( TF2_GetClientTeam( i ) != Team )
		{
			continue;
		}

		CPrintToChatEx( i, Client, FormattedMsg );
	}
}
