class BamGameInfo extends SimpleGame;

/** Reference to players team */
var BamActor_TeamManager PlayerTeam;

/** Reference to neutral team */
var BamActor_TeamManager NeutralTeam;


/** Copy of default function with one extra check */
function Killed(Controller Killer, Controller KilledPlayer, Pawn KilledPawn, class<DamageType> damageType)
{
	if( KilledPlayer != None && KilledPlayer.bIsPlayer && KilledPlayer.PlayerReplicationInfo != none /* added check */ )
	{
		KilledPlayer.PlayerReplicationInfo.IncrementDeaths();
		KilledPlayer.PlayerReplicationInfo.SetNetUpdateTime(FMin(KilledPlayer.PlayerReplicationInfo.NetUpdateTime, WorldInfo.TimeSeconds + 0.3 * FRand()));
		BroadcastDeathMessage(Killer, KilledPlayer, damageType);
	}

	if( KilledPlayer != None )
	{
		ScoreKill(Killer, KilledPlayer);
	}

	DiscardInventory(KilledPawn, Killer);
	NotifyKilled(Killer, KilledPlayer, KilledPawn, damageType);
}


/** Caches references to player and neutral teams */
event PreBeginPlay()
{
	super.PreBeginPlay();
	GetDefaultTeams();
}

/** Finds player and neutral team managers on the map, if not found creates them */
function GetDefaultTeams()
{
	local BamActor_TeamManager tm;
	local bool bPlayerTeamFound, bNeutralTeamFound;

	bPlayerTeamFound = false;
	bNeutralTeamFound = false;

	// go through all TeamManagers on the map and find Player and Neutral teams
	foreach class'WorldInfo'.static.GetWorldInfo().AllActors(class'BamActor_TeamManager', tm)
	{
		if( !bPlayerTeamFound && tm.bIsPlayerTeam && NeutralTeam != tm )
		{
			`trace("Found player team" @ tm @ tm.TeamName, `green);
			PlayerTeam = tm;
			bPlayerTeamFound = true;
		}

		if( !bNeutralTeamFound && tm.bIsNeutralTeam && PlayerTeam != tm )
		{
			`trace("Found neutral team" @ tm @ tm.TeamName, `green);
			NeutralTeam = tm;
			bPlayerTeamFound = true;
		}
	}

	// if player team was not found create it
	if( PlayerTeam == none )
	{
		`trace("Player team not found. Creating it.", `yellow);
		PlayerTeam = CreateTeam("PlayerTeam");
	}

	// if neutral team was not found create it
	if( NeutralTeam == none )
	{
		`trace("Neutral team not found. Creating it.", `yellow);
		NeutralTeam = CreateTeam("NeutralTeam");
	}
}

/**
 * Spawns team manager
 * @param teamName name of the team used for easy identification
 * @param teamClass class of team manager
 * @param teamMembers controllers that belong to this team
 */
function BamActor_TeamManager CreateTeam(string teamName, optional class<BamActor_TeamManager> teamClass = class'BamActor_TeamManager', optional array<BamAIController> teamMembers)
{
	local BamActor_TeamManager team;
	local int q;

	if( teamClass == none )
	{
		return none;
	}

	team = Spawn(teamClass);

	team.TeamName = (Len(teamName) == 0 ? string(team.Name) : teamName);

	for(q = 0; q < teamMembers.Length; ++q)
	{
		team.Join(teamMembers[q]);
	}

	return team;
}

/** Kills Pawns by dealing damage to them */
exec function BamKillPawns()
{
	local BamPawn pwn;

	foreach WorldInfo.AllPawns(class'BamPawn', pwn)
	{
		if( GetALocalPlayerController().Pawn != pwn )
		{
			pwn.TakeDamage(9999999, GetALocalPlayerController(), vect(0,0,0), vect(0,0,0), class'DamageType');
		}
	}
}


defaultproperties
{
	HUDType=class'BamHUD'
	DefaultPawnClass=class'BamPlayerPawn'
	PlayerControllerClass=class'BamPlayerController'
}