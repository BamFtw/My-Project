class BamAIController extends GameAIController;


struct BamHostilePawnDetectionData
{
	/** Enemy Pawn */
	var Pawn Pawn;
	/** How long this pawn is in view */
	var float SeenFor;
};

struct BamHostilePawnData
{
	/** Enemy Pawn */
	var Pawn Pawn;
	/** Location where Pawn was last spotted */
	var Vector LastSeenLocation;
	/** Time at which Pawn was last spotted */
	var float LastSeenTime;
};

struct BamAIActionContainer
{
	/** Actions class */
	var() class<BamAIAction> Class;
	/** Actions archetype */
	var() editinline BamAIAction Archetype;
};


struct BamSubscribersList
{
	/** class of the event that has to be given to CallSubscribers function */
	var class<BamSubscribableEvent> Event;
	/** List of delegates that will be alled when CallSubscribers is called with correct event class */
	var array<delegate<BamSubscriber> > List;
};

/** List of all event subscribers */
var array<BamSubscribersList> SubscribersLists;


/** Becouse pitch in Rotation variable is set to 0 each tick this one is storing it
 *  and should be used for Aim offset and such things */
var float ViewPitch;
/** Used for smooth pitch transition */
var float DesiredViewPitch;
/** How fast can ViewPitch change */
var float ViewPitchRotationRate;



/** Data of enemies that are in view but aren't detected yet */
var array<BamHostilePawnDetectionData> EnemyDetectionData;

/** for how long pawn must stay in this controllers view to be detected */
var(Detection) float EnemyDetectionDelay;

/** From this distance to EnemyDetectionOuterRadius pawn suffers no detection penalties related to distance,
 *	below it gains up to double detection speed
 */
var(Detection) float EnemyDetectionInnerRadius;

/** Up to this distance from enemy pawn suffers no detection penalties related to distance */
var(Detection) float EnemyDetectionOuterRadius;

/** If distance between pawn and enemy is greater than this, detection cappabilites are halved */
var(Detection) float EnemyDetectionMaxRadius;



/** Reference to game object */
var BamGameInfo Game;

/** Reference to controlled pawn */
var BamAIPawn BPawn;

/** reference to TeamManager this controller belongs to */
var BamActor_TeamManager Team;





/** While in 'Moving' state, how often should pathfinding algorithm be ran */
var(Pathfinding) float PathfindingInterval;

/** Modifier of Pawns collision extent used while testing whether anyting is blocking its way */
var(Pathfinding) float PathfindingFrontCollisionExtentMod;

/** Modifier of Pawns collision radius used while testing whether anyting is blocking its way */
var(Pathfinding) float PathfindingFrontCollisionRadiusMultiplier;

/** Whether pathfinding should analyze closest surroundings while pathfinding */
var(Pathfinding) bool bUseDynamicActorAvoidance;

/** Location on the Pawns path that Pawn is currently heading toward */
var Vector MoveLocation;

/** Location to which Pawn should head while in 'Moving' state */
var protectedwrite Vector FinalDestination;

/** Radius from FinalDestination location that allows for reaching it */
var protectedwrite float FinalDestinationDistanceOffset;

/** Pawns collision radius will be multipleied by this value while checking whether pawn reached its goal */
var(Pathfinding) float FinalDestCollisionRadiusMod;


/** Flag that is used for switching between default and combat actions */
var bool bIsInCombat;

/** Action that is used while unit is out of combat */
var(AIAction) BamAIActionContainer DefaultAction;
/** Action that is used while unit is in combat */
var(AIAction) BamAIActionContainer CombatAction;


/** Class of the action manager that this controller will use */
var(AIAction) class<BamAIActionManager> ActionManagerClass;
/** Reference to action manager that this controller uses */
var BamAIActionManager ActionManager;

/** Class of the need manager that this controller will use */
var(Needs) class<BamNeedManager> NeedManagerClass;
/** Reference to need manager that this controller uses */
var BamNeedManager NeedManager;


/** Actor used as focus point of the Pawn during movement */
var BamActor_MoveFocus MoveFocusActor;
var bool bUseMoveFocusActor;



/** 
 * Delegate used for subscribing to certain events specified in BamSubscribableEvents enum
 * @param params - event parameters
 */
delegate BamSubscriber(BamSubscriberParameters params);



/** Cleanup */
event Destroyed()
{
	`trace("Controller Destroyed", `green);

	if( Team != none )
	{
		Team.Quit(self);
		Team = none;
	}

	SubscribersLists.Length = 0;
	EnemyDetectionData.Length = 0;

	Game = none;
	BPawn = none;
	Pawn = none;

	DefaultAction.Archetype = none;
	CombatAction.Archetype = none;

	ActionManager.Destroyed();
	ActionManager = none;

	NeedManager = none;

	MoveFocusActor.Destroy();

	super.Destroyed();
}

/** Spawns MoveFocusActor and sets the length of SubscribersList */
event PreBeginPlay()
{
	super.PreBeginPlay();
	
	class'Engine'.static.GetEngine().bDisableAILogging = false;
	bAILogging = true;

	MoveFocusActor = Spawn(class'BamActor_MoveFocus', self, , , , , true);
}

/** Caches reference to BamGame object */
event PostBeginPlay()
{
	super.PostBeginPlay();

	Game = BamGameInfo(WorldInfo.Game);
}

/** Spawns managers, sets reference to possessed BamAIPawn, joins team if needed */
event Possess(Pawn inPawn, bool bVehicleTransition)
{
	super.Possess(inPawn, bVehicleTransition);

	BPawn = BamAIPawn(inPawn);

	// if team is none join neutral
	if( Team == none )
	{
		SetTeamManager(Game.NeutralTeam);
	}

	if( SpawnActionManager() )
	{
		ActionManager.PushFront(SpawnDefaultAIAction());
	}

	SpawnNeedManager();
}

/**
 * Creates action manager and sets its contoller reference
 * @return whether manager was successfuly spawned
 */
function bool SpawnNeedManager()
{
	if( NeedManagerClass != none )
	{
		NeedManager = new NeedManagerClass;
	}

	if( NeedManager == none )
	{
		NeedManager = new class'BamNeedManager';
	}

	if( NeedManager == none )
	{
		`trace("Failed to create NeedManager", `red);
		return false;
	}

	NeedManager.Initialize(self);
	return true;
}

/** 
 * Creates action manager and sets its contoller reference
 * @return whether manager was successfuly spawned
 */
function bool SpawnActionManager()
{
	if( ActionManagerClass != none )
	{
		ActionManager = new ActionManagerClass;
	}

	if( ActionManager == none )
	{
		ActionManager = new class'BamAIActionManager';
	}

	if( ActionManager == none )
	{
		`trace("Failed to create ActionManager", `red);
		return false;
	}

	ActionManager.MasterInitialize(self);
	return true;
}

/** Spawns default noncombat action */
function BamAIAction SpawnDefaultAIAction()
{
	if( DefaultAction.Archetype != none )
	{
		return new DefaultAction.Archetype.Class(DefaultAction.Archetype);
	}
	else if( DefaultAction.Class != none )
	{
		return new DefaultAction.Class;
	}

	return none;
}

event Tick(float DeltaTime)
{
	super.Tick(DeltaTime);

	HandleViewPitch(DeltaTime);

	UpdateDetectionData(DeltaTime);
	
	// sets the bIsInCombat flag and spawns combat action
	if( !bIsInCombat && IsInCombat() )
	{
		bIsInCombat = true;
		if( CombatAction.Archetype != none )
		{
			ActionManager.PushFront(new CombatAction.Archetype.Class(CombatAction.Archetype));
		}
		else if( CombatAction.Class != none )
		{
			ActionManager.PushFront(new CombatAction.Class);
		}
		else
		{
			`trace("combat action not set", `red);
		}
	}
	else if( bIsInCombat && !IsInCombat() )
	{
		bIsInCombat = false;
	}

	// tick need mamanger
	if( NeedManager != none )
	{
		NeedManager.MasterTick(DeltaTime);
	}

	// tick action manager
	if( ActionManager != none )
	{
		ActionManager.MasterTick(DeltaTime);
	}
}

/** Updates times the pawns were seen and handles detecting them */
function UpdateDetectionData(float DeltaTime)
{
	local int q;
	local float seenFor, distanceToEnemy;
	local BamHostilePawnData pawnData;

	for(q = 0; q < EnemyDetectionData.Length; ++q)
	{
		// if pawn is bad or already detected remove it from the list
		if( EnemyDetectionData[q].Pawn == none || !EnemyDetectionData[q].Pawn.IsAliveAndWell() || Team.GetEnemyData(EnemyDetectionData[q].Pawn, pawnData) )
		{
			EnemyDetectionData.Remove(q--, 1);
			continue;
		}

		// check if controller can see enemy pawn
		if( CanSee(EnemyDetectionData[q].Pawn) )
		{
			EnemyDetectionData[q].SeenFor += DeltaTime;

			seenFor = EnemyDetectionData[q].SeenFor;

			// if enemy Pawn is BamPawn adjust seen duration by its detectability
			if( BamPawn(EnemyDetectionData[q].Pawn) != none )
			{
				seenFor *= BamPawn(EnemyDetectionData[q].Pawn).Detectability;
			}

			// adjust for controlled Pawns Awareness
			if( BPawn != none )
			{
				seenFor *= BPawn.Awareness;
			}

			// adjust for distance from enemy pawn
			distanceToEnemy = VSize2D(Pawn.Location - EnemyDetectionData[q].Pawn.Location);
			if( distanceToEnemy < EnemyDetectionInnerRadius )
			{
				seenFor *= 2.0 - (distanceToEnemy / EnemyDetectionInnerRadius);
			}
			else if( distanceToEnemy > EnemyDetectionOuterRadius && distanceToEnemy < EnemyDetectionMaxRadius )
			{
				seenFor *= 1.0 - 0.5 * ((distanceToEnemy - EnemyDetectionOuterRadius) / (EnemyDetectionMaxRadius - EnemyDetectionOuterRadius));
			}
			else if( distanceToEnemy > EnemyDetectionMaxRadius )
			{
				seenFor *= 0.5;
			}

			// test if pawn was seen long enough to be detected
			if( seenFor >= EnemyDetectionDelay )
			{
				EnemySpotted(EnemyDetectionData[q].Pawn);
				EnemyDetectionData.Remove(q--, 1);
			}
		}
		else
		{
			// if pawn is not visible tick down seen time
			EnemyDetectionData[q].SeenFor -= DeltaTime;

			// remove if seen time reaches 0
			if( EnemyDetectionData[q].SeenFor <= 0 )
			{
				EnemyDetectionData.Remove(q--, 1);
			}
		}
		
	}
}

/** Smoothly transitions ViewPitch to DesiredViewPitch */
function HandleViewPitch(float DeltaTime)
{
	local float deltaPitch;

	if( ViewPitch != DesiredViewPitch )
	{
		deltaPitch = Abs(DeltaTime * ViewPitchRotationRate);
		
		if( Abs(DesiredViewPitch - ViewPitch) <= deltaPitch )
		{
			ViewPitch = DesiredViewPitch;
		}
		else
		{
			ViewPitch += ((DesiredViewPitch - ViewPitch) < 0 ? -1.0 : 1.0) * deltaPitch;
		}
	}	
}

/** Sets ViewPitch */
function SetViewRotation(Rotator rot)
{
	ViewPitch = rot.Pitch;
	DesiredViewPitch = rot.Pitch;
}

/** Sets DesiredViewPitch */
function SetDesiredViewRotation(Rotator rot)
{
	DesiredViewPitch = rot.Pitch;
}

/** Returns controllers Rotation adjusted by ViewPitch */
function Rotator GetViewRotation()
{
	return MakeRotator(ViewPitch, Rotation.Yaw, 0);
}

/**
 * Called by ProjectileCatcher when hostile Projectile enters it
 * @param pj - projectile that was caught
 * @param PjOwner - owner of caught projectile
 */
function ProjectileCaught(Projectile pj, BamPawn PjOwner)
{
	if( !IsInCombat() && IsPawnHostile(PjOwner) )
	{
		ActionManager.PushFront(class'BamAIAction_Investigate'.static.Create_Investigate(PjOwner.Location));
		ActionManager.BlockActionClass(class'BamAIAction_Investigate', 1.0);
	}
}

/** Calls delegates subscribed to this event */
event HearNoise(float Loudness, Actor NoiseMaker, optional Name NoiseType)
{
	local Pawn heardPawn;

	super.HearNoise(Loudness, NoiseMaker, NoiseType);
	
	// ignore if in combat or heard self
	if( IsInCombat() || NoiseMaker == Pawn || NoiseMaker == Pawn.Weapon )
	{
		return;
	}

	CallSubscribers(class'BamSubscribableEvent_HearNoise', class'BamSubscriberParameters_HearNoise'.static.Create(self, BPawn, Loudness, NoiseMaker, NoiseType));

	// try to get Pawn that mede noise
	if( Pawn(NoiseMaker) != none )
	{
		heardPawn = Pawn(NoiseMaker);
	}
	else if( Weapon(NoiseMaker) != none )
	{
		heardPawn = Pawn(Weapon(NoiseMaker).Owner);
	}


	if( !IsPawnHostile(heardPawn) )
	{
		return;
	}

	ActionManager.PushFront(class'BamAIAction_Investigate'.static.Create_Investigate(heardPawn.Location));
	ActionManager.BlockActionClass(class'BamAIAction_Investigate', 1.0);
}

/** Forwards Seen pawn to SeePawn function */
event SeeMonster(Pawn Seen)
{
	super.SeePlayer(Seen);
	SeePawn(Seen);
}

/** Forwards Seen pawn to SeePawn function */
event SeePlayer(Pawn Seen)
{
	super.SeePlayer(Seen);
	SeePawn(Seen);
}

/** 
 * Called by SeeMonster and SeePlayer, checks if Seen is hostile and adds it to enemies list if needed
 * @param Seen - Pawn that was noticed
 */
function SeePawn(Pawn Seen)
{
	local int q;
	local BamHostilePawnData pawnData;
	local BamHostilePawnDetectionData detectionData;

	// make sure Seen is enemy
	if( Seen == none || !IsPawnHostile(Seen) )
	{
		return;
	}

	// if pawn is already detected update its last seen location and time
	if( Team.GetEnemyData(Seen, pawnData) )
	{
		EnemySpotted(Seen);
		return;
	}

	// check if pawn already is in EnemyDetectionData list
	for(q = 0; q < EnemyDetectionData.Length; ++q)
	{
		if( EnemyDetectionData[q].Pawn == Seen )
		{
			return;
		}
	}

	// if there should be no delay detect immediately
	if( EnemyDetectionDelay <= 0 )
	{
		EnemySpotted(Seen);
	}
	else
	{
		detectionData.Pawn = Seen;
		detectionData.SeenFor = 0;

		EnemyDetectionData.AddItem(detectionData);
	}
}

/** Pawns TakeDamage event calls this one, used for notifying subscribers */
event TakeDamage(int Damage, Controller InstigatedBy, vector HitLocation, vector Momentum, class<DamageType> DamageType, optional TraceHitInfo HitInfo, optional Actor DamageCauser)
{
	CallSubscribers(class'BamSubscribableEvent_TakeDamage', class'BamSubscriberParameters_TakeDamage'.static.Create(self, BPawn, Damage, InstigatedBy, HitLocation, Momentum, DamageType, HitInfo, DamageCauser));
}

/** Returns whether pawn given as parameter is hostile */
function bool IsPawnHostile(Pawn pwn)
{
	if( pwn == none || Team == none )
	{
		return false;
	}

	return Team.IsPawnHostile(pwn);
}

/** 
 * Adds enemy information to EnemyData list or updates it, calls DetectEnemy subscribers 
 * @param pwn - detected enemy pawn
 */
function EnemySpotted(Pawn pwn)
{
	if( Team.EnemySpotted(pwn) )
	{
		CallSubscribers(class'BamSubscribableEvent_DetectEnemy', class'BamSubscriberParameters_DetectEnemy'.static.Create(self, BPawn, pwn));
	}
}

/**
 * Returns whether distance between vectors is smaller or equal to maxDistance
 * @param v1 - first vector to test
 * @param v2 - second vector to test
 * @param maxDistance - maximum distance between v1 and v2 that allow for returning true
 * @return whether distance between vectors is smaller or equal to maxDistance
 */
static function bool CompareVectors2D(Vector v1, Vector v2, optional float maxDistance = 0)
{
	return (Vsize2D(v1 - v2) <= maxDistance);
}

/**
 *  Returns Location of the next Point in the path to the goal that Controlled Pawn should head toward
 *  Checks if anything is blocking path and if so tries to avoid it
 *  @param goal - final destination that should be reached
 */
function Vector FindNavMeshPath(Vector goal)
{
	local int q;
	local float TestMoveDistance, tempDistance;
	local array<Vector> availableMoveLocations;
	local Vector tempDestination, moveLoc, HitLocation, HitNormal, TraceEnd, Extent, TraceEndFinal;
	local Actor HitActor;

	moveLoc = goal;

	if( Pawn == none || !Pawn.IsAliveAndWell() )
	{
		return vect(0,0,0);
	}

	// default nav mesh pathfinding
	if( !NavigationHandle.PointReachable(goal) )
	{
		NavigationHandle.PathConstraintList = none;
		NavigationHandle.PathGoalList = none;
		NavigationHandle.ClearConstraints();

		class'NavMeshPath_Toward'.static.TowardPoint(NavigationHandle, goal);
		class'NavMeshGoal_At'.static.AtLocation(NavigationHandle, goal, Pawn.GetCollisionRadius(), true);

		if( NavigationHandle.FindPath() )
		{
			NavigationHandle.SetFinalDestination(goal);
			if( NavigationHandle.GetNextMoveLocation(tempDestination, Pawn.GetCollisionRadius()) && !CompareVectors2D(Pawn.Location, tempDestination, 16.0) )
			{
				moveLoc = tempDestination;
			}
		}
	}

	// check if there is anything in front of the pawn
	if( bUseDynamicActorAvoidance )
	{
		TestMoveDistance = Pawn.GetCollisionRadius() * PathfindingFrontCollisionRadiusMultiplier;
		if( TestMoveDistance > VSize2D(Pawn.Location - moveLoc) )
		{
			TestMoveDistance = VSize2D(Pawn.Location - moveLoc);
		}

		TraceEnd = moveLoc - Pawn.Location;
		TraceEnd.Z = Pawn.Location.Z;
		TraceEnd = Normal(TraceEnd) * TestMoveDistance;

		Extent = Pawn.GetCollisionExtent() * PathfindingFrontCollisionExtentMod;

		HitActor = Trace(HitLocation, HitNormal, Pawn.Location + TraceEnd, Pawn.Location,  true, Extent);

		// if there is, test if pawn can step to the side
		if( HitActor != none )
		{
			for(q = -2; q < 3; ++q)
			{
				if( q == 0 )
					continue;

				TraceEndFinal = Pawn.Location + (TraceEnd << MakeRotator(0, q * 16384, 0));
				TraceEndFinal.Z = Pawn.Location.Z;
				HitActor = Trace(HitLocation, HitNormal, TraceEndFinal, Pawn.Location,  true, Extent);
				
				if( HitActor == none && NavigationHandle.PointReachable(TraceEndFinal) )
					availableMoveLocations.AddItem(TraceEndFinal);
			}
			
			// if step to the side location was found get the closest one to the goal
			if( availableMoveLocations.Length > 0 )
			{
				tempDistance = 999999999;

				for(q = 0; q < availableMoveLocations.Length; ++q)
				{
					if( Vsize2D(moveLoc - availableMoveLocations[q]) < tempDistance )
					{
						tempDistance = Vsize2D(moveLoc - availableMoveLocations[q]);
						goal = availableMoveLocations[q];
					}
				}

				return goal;
			}
		}
	}

	return moveLoc;
}

/** 
 * Sets reference to team manager adn joins it, quits previous team if needed
 * @param temMgr - team to join
 * @return whether controller successfuly joined team
 */
function bool SetTeamManager(BamActor_TeamManager teamMgr)
{
	if( teamMgr == none && Team == teamMgr )
	{
		return false;
	}

	if( Team != none )
	{
		Team.Quit(self);
	}

	Team = teamMgr;

	Team.Join(self);
	return true;
}

/** Returns whether controller knows about any enemies */
function bool HasEnemies()
{
	return Team.HasEnemies();
}

function bool HasRangedEnemies()
{
	return Team.HasRangedEnemies();
}

/** Returns whether controller is in combat */
event bool IsInCombat(optional bool bForceCheck)
{
	if( Team == none )
	{
		`trace("No team for" @ Pawn, `red);
		return false;
	}
	return Team.IsInCombat();
}

/** Returns list of last known locations of all known enemies */
function array<Vector> GetEnemyLocations()
{
	return Team.GetEnemyLocations();
}

/** Sums all of the enemy LastSeenLocations and returns average of those */
function Vector GetAverageEnemyLocation()
{
	return Team.GetAverageEnemyLocation();
}

/** Returns list of last known locations of all known enemies */
function array<Vector> GetRangedEnemyLocations()
{
	return Team.GetRangedEnemyLocations();
}

/** 
 * Gets data data of the pawn given as param
 * @param enemyPwn - pawn whose data will be returned
 * @param data - pawns info will be set in this struct
 * @return whether pawns data was found
 */
function bool GetEnemyData(Pawn enemyPwn, out BamHostilePawnData data)
{
	return Team.GetEnemyData(enemyPwn, data);
}

/**
 * Changes state to the on given as parameter
 * @return name of the state that was just entered
 */
function name ChangeStateRequest(name stateName)
{
	if( GetStateName() != stateName )
	{
		GotoState(stateName);
	}

	return stateName;
}

/** 
 * State transition to 'Idle'
 * @return name of the state that was just entered
 */
function name Begin_Idle()
{
	return ChangeStateRequest('Idle');
}

/** 
 * State transition to 'Moving' 
 * @return name of the state that was just entered
 */
function name Begin_Moving()
{
	return ChangeStateRequest('Moving');
}

/** Returns whether controller is in idle state */
function bool Is_Idle()
{
	return IsInState('Idle');
}

/** Returns whether controller is in moving state */
function bool Is_Moving()
{
	return IsInState('Moving');
}

/**
 * Initializes move parameters and begins movment
 * @param newFinalDest - location to which pawn should travel
 * @param MaxDistanceOffset - (optional, 0 by default) distance from the FinalDestination that will allow reaching it
 * @param bRun - (optional, false by default) whether Pawn should run or walk
 * @param FDRSub - (optional) delegate (BamSubscriber) that will be called when FinalDestination will be reached
 */
function InitializeMove(Vector newFinalDest, optional float MaxDistanceOffset = 0.0, optional bool bRun = false, optional delegate<BamSubscriber> FDRSub = none)
{
	if( FDRSub != none )
	{
		Subscribe(class'BamSubscribableEvent_FinalDestinationReached', FDRSub);
	}

	BPawn.SetWalking(bRun);
	SetFinalDestination(newFinalDest, MaxDistanceOffset);
	Begin_Moving();
}

/**
 * Sets the location of the FinalDestination
 * @param destination - point that Pawn should try reach
 * @param MaxDistanceOffset - distance from the FinalDestination that will allow reaching it
 */
function SetFinalDestination(Vector destination, optional float MaxDistanceOffset = 0.0)
{
	FinalDestination = destination;
	SetFinalDestinationDistanceOffset(FMax(0, MaxDistanceOffset));
}

/** Sets distance from the FinalDestination that will allow reaching it */
function SetFinalDestinationDistanceOffset(float newOffset)
{
	FinalDestinationDistanceOffset = newOffset;
}

/** Called by 'Moving' state when Pawn gets within CollisionRadius range with FinalDestination, informs active Action about it */
function FinalDestinationReached()
{
	CallSubscribers(class'BamSubscribableEvent_FinalDestinationReached', class'BamSubscriberParameters_FinalDestinationReached'.static.Create(self, BPawn, FinalDestination));
}

/** Stops latent functions and zeroes Pawn movment variables */
function StopMovement()
{
	StopLatentExecution();
	
	if( Pawn != none )
	{
		Pawn.ZeroMovementVariables();
	}
}




/** 
 * Subscribes delegate to an event
 * @param evnt - event that sub will be subscribed to
 * @param sub - delegate to call when event is triggered
 */
function Subscribe(class<BamSubscribableEvent> evnt, delegate<BamSubscriber> sub)
{
	local int idx;

	// check if event is correct and delegate is not none
	if( evnt == none || sub == none )
	{
		return;
	}

	idx = GetSubscribableEventIndex(evnt);
	
	// do not allow duplicates
	if( SubscribersLists[idx].List.Find(sub) != INDEX_NONE )
	{
		return;
	}

	SubscribersLists[idx].List.AddItem(sub);
}

/** 
 * Removes subscribed delegate from the list for specified event
 * @param evnt - event that sub is subscribed to
 * @param sub - delegate to remove
 */
function UnSubscribe(class<BamSubscribableEvent> evnt, delegate<BamSubscriber> sub)
{
	local int idx;

	idx = GetSubscribableEventIndex(evnt);

	// check if event is correct and delegate is not none
	if( idx == INDEX_NONE || sub == none )
	{
		return;
	}

	SubscribersLists[idx].List.RemoveItem(sub);
}

/** 
 * Calls all subscribers of the event given as parameter and passes params object to them.
 * Clears subscribers list for event given as parameter.
 * @param evnt - class of subscriabable event that was triggered
 * @param params - (optional) parameters that will passed to all subscribers
 */
function CallSubscribers(class<BamSubscribableEvent> evnt, optional BamSubscriberParameters params)
{
	local int q, idx;
	local array<delegate<BamSubscriber> > subsList;
	local delegate<BamSubscriber> deleg;

	idx = GetSubscribableEventIndex(evnt);

	// check if event is correct
	if( idx == INDEX_NONE )
	{
		`trace("Wrong event given as parameter" , `red);
		return;
	}

	subsList = SubscribersLists[idx].List;

	for(q = 0; q < subsList.Length; ++q)
	{
		deleg = subsList[q];
		SubscribersLists[idx].List.RemoveItem(deleg);
		deleg(params);
	}
}

/**
 * Returns index of the event in SubscribersLists, if not found creates and adds it to the list
 * @param evnt - class of the subscribable event
 * @return index of the delegates list for the event given as parameter
 */
function int GetSubscribableEventIndex(class<BamSubscribableEvent> evnt)
{
	local BamSubscribersList list;
	local int q;

	if( evnt == none )
	{
		return INDEX_NONE;
	}

	for(q = 0; q < SubscribersLists.Length; ++q)
	{
		if( SubscribersLists[q].Event == evnt )
		{
			return q;
		}
	}

	// event not found, create and add it to the list
	list.Event = evnt;
	SubscribersLists.AddItem(list);

	return (SubscribersLists.Length - 1);
}





/**_______________________________________________________Idle */
auto state Idle
{
	event BeginState(name PreviousStateName)
	{
		StopMovement();
	}
}

/**_______________________________________________________Moving */
state Moving
{
	event EndState(name NextStateName)
	{
		StopMovement();
	}

	event Tick(float DeltaTime)
	{
		local float distToFD, FDRange;
		global.Tick(DeltaTime);

		if( Pawn == none )
		{
			return;
		}

		distToFD = VSize2D(FinalDestination - Pawn.Location);
		FDRange = (Pawn.GetCollisionRadius() * FinalDestCollisionRadiusMod) + FinalDestinationDistanceOffset;

		if( distToFD <= FDRange )
		{
			Begin_Idle();
			SetFinalDestinationDistanceOffset(0);
			FinalDestinationReached();
		}
	}

begin:
	if( Pawn != none )
	{
		SetTimer(PathfindingInterval, false, nameof(StopLatentExecution));
		MoveLocation = FindNavMeshPath(FinalDestination);
		
		if( MoveLocation != vect(0, 0, 0) )
		{
			MoveTo(MoveLocation, bUseMoveFocusActor ? MoveFocusActor : none);
		}
	}

	Sleep(0.01);
	goto('begin');
}


defaultproperties
{
	bIsPlayer=true

	bIsInCombat=false

	PathfindingInterval=0.5
	PathfindingFrontCollisionExtentMod=0.75
	PathfindingFrontCollisionRadiusMultiplier=2.5
	bUseDynamicActorAvoidance=true

	NeedManagerClass=class'BamNeedManager'
	ActionManagerClass=class'BamAIActionManager'

	DefaultAction=(class=class'BamAIAction_Idle',Archetype=none)
	CombatAction=(class=class'BamAIAction_Idle',Archetype=none)

	FinalDestCollisionRadiusMod=1.0

	NavMeshPath_SearchExtent_Modifier=(X=3.0,Y=3.0,Z=0.0)

	EnemyDetectionDelay=1.0

	EnemyDetectionInnerRadius=300.0
	EnemyDetectionOuterRadius=1000.0
	EnemyDetectionMaxRadius=2500.0

	ViewPitch=0
	DesiredViewPitch=0
	ViewPitchRotationRate=32500.0
}