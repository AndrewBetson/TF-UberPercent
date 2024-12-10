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
	#define PLUGIN_VERSION "1.1.0"
#endif // !defined PLUGIN_VERSION

DHookSetup gDetour_CTFPlayer_SpeakConceptIfAllowed;

ConVar gCVarEnabled;
bool gEnabled;

ConVar gCVarAlmostReadyPct;
float gAlmostReadyPct;

char UBER_NOT_READY_SOUNDS[][] =
{
	"vo/medic_jeers01.mp3",
	"vo/medic_jeers04.mp3",
	"vo/medic_jeers05.mp3",
	"vo/medic_jeers12.mp3"
};

char UBER_ALMOST_READY_SOUNDS[][] =
{
	"vo/medic_incoming01.mp3",
	"vo/medic_incoming02.mp3",
	"vo/medic_incoming03.mp3"
};

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

	AddNormalSoundHook( SndHook_UberChargeReady );

	for ( int i = 0; i < 3; i++ )
	{
		PrecacheSound( UBER_NOT_READY_SOUNDS[ i ] );
	}

	for ( int i = 0; i < 2; i++ )
	{
		PrecacheSound( UBER_ALMOST_READY_SOUNDS[ i ] );
	}

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

public Action SndHook_UberChargeReady(
	int Clients[ MAXPLAYERS ], int &NumClients, char Sound[ PLATFORM_MAX_PATH ],
	int &Entity, int &Channel, float &Volume, int &Level, int &Pitch, int &Flags,
	char SoundEntry[ PLATFORM_MAX_PATH ], int &Seed
)
{
	if ( !gEnabled )
	{
		return Plugin_Continue;
	}

	if ( Entity > MAXPLAYERS )
	{
		return Plugin_Continue;
	}

	if ( TF2_GetPlayerClass( Entity ) != TFClass_Medic )
	{
		return Plugin_Continue;
	}

	if (
		strcmp( Sound, "vo/medic_AutoChargeReady01.mp3" ) != 0 &&
		strcmp( Sound, "vo/medic_AutoChargeReady02.mp3" ) != 0 &&
		strcmp( Sound, "vo/medic_AutoChargeReady03.mp3" ) != 0
	)
	{
		return Plugin_Continue;
	}

	int MedigunHandle = GetEntPropEnt( Entity, Prop_Send, "m_hMyWeapons", 1 );
	float UberPercent = GetEntPropFloat( MedigunHandle, Prop_Send, "m_flChargeLevel" );

	if ( UberPercent < gAlmostReadyPct )
	{
		int SoundToPlay = GetRandomInt( 0, 3 );
		strcopy( Sound, PLATFORM_MAX_PATH, UBER_NOT_READY_SOUNDS[ SoundToPlay ] );

		return Plugin_Changed;
	}
	else if ( UberPercent < 1.0 )
	{
		int SoundToPlay = GetRandomInt( 0, 2 );
		strcopy( Sound, PLATFORM_MAX_PATH, UBER_ALMOST_READY_SOUNDS[ SoundToPlay ] );

		return Plugin_Changed;
	}

	return Plugin_Continue;
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
		PrintToTeam( Team, This, "{teamcolor}%t %N{default}: %t", "UP_VoicePrefix", This, "UP_ChargeNotReady", RealUberPercent, "%%%" );
	}
	else if ( UberPercent < 1.0 )
	{
		PrintToTeam( Team, This, "{teamcolor}%t %N{default}: %t", "UP_VoicePrefix", This, "UP_ChargeAlmostReady", RealUberPercent, "%%%" );
	}
	else
	{
		PrintToTeam( Team, This, "{teamcolor}%t %N{default}: %t", "UP_VoicePrefix", This, "UP_ChargeReady", "%%%" );
		return MRES_Ignored;
	}

	return MRES_Ignored;
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
