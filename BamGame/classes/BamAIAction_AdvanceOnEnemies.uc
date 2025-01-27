class BamAIAction_AdvanceOnEnemies extends BamAIAction
	noteditinlinenew;

/** Action responsible for firing */
var BamAIAction_FireAtTarget FiringAction;

/** Whether Pawn should run */
var() bool bRun;

/** Whether pawn should fire while moving */
var() bool bFireDuringWalk;

/** Miniumum duration of this action */
var() float MinDuration;

/** Maximum duration of this action */
var() float MaxDuration;

/** Whether to finish firing action when this one ends */
var() bool bDontFinishFiringAction;

var float OldFDROffset;

/** Selects target to move to and creates firing action if needed */
function OnBegin()
{
	local array<Vector> EnemyLocations;
	local int q, closestIndex;
	local float closestDistance, currentDistance;

	OldFDROffset = Manager.Controller.FinalDestinationDistanceOffset;

	if( !Manager.Controller.IsInCombat() )
	{
		`trace("Controller is not in combat", `yellow);
		Finish();
		return;
	}

	// get enemy location
	EnemyLocations = Manager.Controller.GetEnemyLocations();

	if( EnemyLocations.Length == 0 )
	{
		`trace("Controller has no enemies", `yellow);
		Finish();
		return;
	}

	// if pawn shouldnt run and should fire create firing action
	if( !bRun && bFireDuringWalk )
	{
		FiringAction = class'BamAIAction_FireAtTarget'.static.Create_FireAtTarget();

		if( FiringAction != none )
		{
			Manager.InsertBefore(FiringAction, self);
		}
	}

	SetDuration(RandRange(MinDuration, MaxDuration));

	for(q = 0; q < EnemyLocations.Length; ++q)
	{
		currentDistance = VSizeSq(Manager.Controller.Pawn.Location - EnemyLocations[q]);
		if( closestDistance == 0 || currentDistance < closestDistance )
		{
			closestIndex = q;
			closestDistance = currentDistance;
		}
	}

	// move to closes enemy
	Manager.Controller.InitializeMove(EnemyLocations[closestIndex], Manager.Controller.Pawn.GetCollisionRadius() * 9.0, bRun, FinalDestinationReached);
}

function OnBlocked()
{
	Finish();
	Manager.Controller.UnSubscribe(class'BamSubscribableEvent_FinalDestinationReached', FinalDestinationReached);
}

function OnEnd()
{
	Manager.Controller.SetFinalDestinationDistanceOffset(OldFDROffset);

	// finish firing action
	if( !bDontFinishFiringAction && FiringAction != none )
	{
		FiringAction.Finish();
	}

	// stop moving
	if( !IsBlocked() )
	{
		Manager.Controller.Begin_Idle();
	}
}




function FinalDestinationReached(BamSubscriberParameters params)
{
	if( bIsBlocked )
	{
		return;
	}

	Manager.Controller.Begin_Idle();
	
	if( TimeLeft() > 1 )
	{
		bDontFinishFiringAction = true;
		Finish();
		FiringAction.SetDuration(TimeLeft());
		Manager.PushFront(class'BamAIAction_Strafe'.static.Create_Strafe(TimeLeft(), BSD_RandomLeftRight));
	}
	else
	{
		// delay end
		SetDuration(RandRange(0.5, 1.5));
	}
}





static function BamAIAction_AdvanceOnEnemies Create_AdvanceOnEnemies(optional float inDuration = 0, optional bool inRun = false, optional bool inFireDuringWalk = true)
{
	local BamAIAction_AdvanceOnEnemies action;
	action = new class'BamAIAction_AdvanceOnEnemies';

	action.bRun = inRun;
	action.bFireDuringWalk = inFireDuringWalk;
	action.SetDuration(inDuration);

	return action;
}

DefaultProperties
{
	bIsBlocking=true
	Lanes=(class'BamAIActionLane_Moving')

	bRun=false
	bFireDuringWalk=true

	MinDuration=4.0
	MaxDuration=6.0

	bDontFinishFiringAction=false
}