class BamAIAction_CoverPopOut extends BamAIAction_Cover
	noteditinlinenew;

var BamAIAction_FireAtTarget FiringAction;

var bool bUnclaimImmediately;

function OnBegin()
{
	super.OnBegin();
	
	if( CoverData.Cover == none  )
	{
		`trace("Cover is none", `red);
		Finish();
		return;
	}

	if( FindGoodSpot() )
	{
		SetDuration(CoverData.GetCoverPopOutDuration());

		CoverData.SucceededPopOut();

		CoverData.UnclaimedCover();
		
		if( bUnclaimImmediately )
		{
			UnclaimCover();
		}
	}
	else
	{
		CoverData.FailedPopOut();
	}

	FiringAction = class'BamAIAction_FireAtTarget'.static.Create_FireAtTarget(, TimeLeft());
	if( FiringAction != none )
	{
		Manager.PushFront(FiringAction);
	}
	else
	{
		`trace("Failed to create fire action", `red);
	}
}

function OnEnd()
{
	Manager.Controller.UnSubscribe(class'BamSubscribableEvent_FinalDestinationReached', FinalDestinationReached);

	if( !bIsBlocked )
	{
		if( !bUnclaimImmediately )
		{
			UnclaimCover();
		}

		Manager.PushFront(class'BamAIAction_CoverInit'.static.Create_CoverInit(CoverData));
	}

	if( FiringAction != none )
	{
		FiringAction.Finish();
	}
}

function OnUnBlocked()
{
	Manager.Controller.Subscribe(class'BamSubscribableEvent_FinalDestinationReached', FinalDestinationReached);
}

function OnBlocked()
{
	Manager.Controller.UnSubscribe(class'BamSubscribableEvent_FinalDestinationReached', FinalDestinationReached);
}


function UnclaimCover()
{
	if( CoverData.Cover != none ) 
	{
		CoverData.Cover.UnClaim();
	}
}

function bool FindGoodSpot()
{
	local Vector CoverDir, CoverLeft, CoverRight, /**CoverUp,*/ Extent, Offset, SelectedLocation;
	local array<Vector> Results, EnemyLocations;
	local float distPct;
	local int q;

	if( Manager.Controller == none || Manager.Controller.Pawn == none )
		return false;

	EnemyLocations = Manager.Controller.GetEnemyLocations();

	// test cover loaction
	if( CoverData.Cover.CanPopUp() )
	{
		if( IsPopLocationViable(CoverData.Cover.Location, EnemyLocations) )
		{
			Manager.Controller.Subscribe(class'BamSubscribableEvent_FinalDestinationReached', FinalDestinationReached);
			Manager.Controller.FinalDestinationReached();
			bUnclaimImmediately = false;
			// if cover location is valid select it and ignore the sides
			return true;
		}
	}

	bUnclaimImmediately = true;

	CoverDir = Vector(CoverData.Cover.Rotation);
	Extent = Manager.Controller.Pawn.GetCollisionExtent() * 0.75;

	// test left side
	if( CoverData.Cover.CanPopLeft() )
	{
		CoverLeft = (CoverDir << MakeRotator(0, 16384,0)) * CoverData.MaxPopOutDistance;

		for(distPct = 0.25; distPct < 1.1; distPct += 0.25)
		{
			Offset = distPct * CoverLeft;
			if( TracePopLocation(Offset, Extent) )
			{
				Results.AddItem(CoverData.Cover.Location + Offset);
			}
		}
	}

	// test right side
	if( CoverData.Cover.CanPopRight() )
	{
		CoverRight = (CoverDir << MakeRotator(0, -16384,0)) * CoverData.MaxPopOutDistance;

		for(distPct = 0.25; distPct < 1.1; distPct += 0.25)
		{
			Offset = distPct * CoverRight;
			if( TracePopLocation(Offset, Extent) )
			{
				Results.AddItem(CoverData.Cover.Location + Offset);
			}
		}	
	}

	if( Results.Length == 0 )
	{
		`trace("Failed to find pop out location", `yellow);
		CoverData.FailedPopOut();
		Finish();
		return false;
	}
	
	for(q = 0; q < Results.Length; ++q)
	{
		if( !IsPopLocationViable(Results[q], EnemyLocations) )
		{
			Results.Remove(q--, 1);
		}
	}

	if( Results.Length == 0 )
	{
		`trace("All found pop out locations were bad", `yellow);
		CoverData.FailedPopOut();
		Finish();
		return false;
	}

	SelectedLocation = Results[Rand(Results.Length)];

	Manager.Controller.InitializeMove(SelectedLocation, 0, false, FinalDestinationReached);

	return true;
}

/** 
 * Returns whether location given as parameter has clear line of sight to any of the enemy location given as parameter
 * @param loc - 
 * @param enemyLoc - locations of the enemies
 */
function bool IsPopLocationViable(Vector loc, array<Vector> enemyLoc)
{
	local int q;
	local Vector viewPoint, HitLocation, HitNormal;
	local float collisionHeight;

	if( Manager.Controller == none || Manager.Controller.Pawn == none )
		return false;

	collisionHeight = Manager.Controller.Pawn.GetCollisionHeight();

	// find the ground point
	Manager.Controller.Pawn.Trace(HitLocation, HitNormal, loc + vect(0,0,-2) * collisionHeight, loc, false);

	if( HitLocation == vect(0,0,0) )
	{
		viewPoint = loc;
	}
	else
	{
		// add view offset to ground point
		viewPoint = HitLocation + vect(0,0,1) * (collisionHeight + Manager.Controller.Pawn.EyeHeight);
	}

	// test if location allows to hit at least one enemy
	for(q = 0; q < enemyLoc.Length; ++q)
	{
		if( Manager.Controller.Pawn.FastTrace(enemyLoc[q], viewPoint) )
		{
			return true;
		}
	}

	return false;
}
 
 /** Returns whether the way to (Cover.Location + Offset) is clear */
function bool TracePopLocation(Vector Offset, Vector Extent)
{
	local Vector HitLocation, HitNormal;
	CoverData.Cover.Trace(HitLocation, HitNormal, CoverData.Cover.Location + Offset, CoverData.Cover.Location, false, Extent);
	return (HitLocation == vect(0,0,0));
}

function FinalDestinationReached(BamSubscriberParameters params)
{
	if( bIsBlocked )
		return;

	Manager.Controller.UnSubscribe(class'BamSubscribableEvent_FinalDestinationReached', FinalDestinationReached);
	Manager.Controller.Begin_Idle();
}







static function BamAIAction_CoverPopOut Create_CoverPopOut(BamCoverActionData CovData)
{
	local BamAIAction_CoverPopOut act;
	act = new class'BamAIAction_CoverPopOut';
	act.CoverData = CovData;
	return act;
}


DefaultProperties
{
	Lanes=(class'BamAIActionLane_Moving',class'BamAIActionLane_Covering')
	bIsBlocking=true
}