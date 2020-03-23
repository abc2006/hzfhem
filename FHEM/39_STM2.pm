<<<<<<< HEAD
# $Id: 39_STELLMOTOR.pm 3002 2014-10-03 11:51:00Z Florian Duesterwald $
####################################################################################################
#
#	39_STELLMOTOR.pm
#
#	drive a valve to percent value, based on motor drive time
# V0.1 	start over from STELLMOTOR.pm 
# V0.2	removed all waste
####################################################################################################

package main;
use strict;
use warnings;
use Time::HiRes qw(gettimeofday); 

sub STELLMOTOR_Define($$);
sub STELLMOTOR_Undefine($$);
sub STELLMOTOR_Set($@);
sub STELLMOTOR_Get($@);
sub STELLMOTOR_Notify(@);
sub STELLMOTOR_Attr(@);
sub STELLMOTOR_Calibrate($@);
#}

sub STELLMOTOR_commandSend($$){
	#params: R | L | S
	my ($hash, $cmd)	= @_;
	my $name = $hash->{NAME};
	if($command eq "R"){ 
		CommandSet(undef,AttrVal($name,"STMdevL",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevR",0)." on");
		}
	if($command eq "L"){ 
		CommandSet(undef,AttrVal($name,"STMdevR",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevL",0)." on");
		}
	if($command eq "S"){ #rl first on move, rl last on stop
		CommandSet(undef,AttrVal($name,"STMdevR",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevL",0)." off");
		}
	return;
	}

sub STELLMOTOR_Initialize($){
	my ($hash) = @_;
	$hash->{DefFn}		= "STELLMOTOR_Define";
	$hash->{UndefFn}	= "STELLMOTOR_Undefine";
	$hash->{SetFn}		= "STELLMOTOR_Set";
	$hash->{GetFn}		= "STELLMOTOR_Get";
	$hash->{NotifyFn}	= "STELLMOTOR_Notify";
	$hash->{AttrFn}		= "STELLMOTOR_Attr";
	$hash->{AttrList}	= "disable:0,1 STMmaxTics STMmaxDriveSeconds STMdevL STMdevR STMlastDiffMax STMpollInterval ".$readingFnAttributes;
}

sub STELLMOTOR_Define($$){
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	my $menge = int(@args);
	if (int(@args) < 1) {
	return "Usage: define <name> STELLMOTOR";
	}
	my $name = $args[0];
	$hash->{NOTIFYDEV} = "global";
	
	Log3($name, 3, "STELLMOTOR $name active, type=".$args[2]);
		readingsSingleUpdate($hash, "state", "initialized",1);
	my $position = ReadingsVal($name,"position", "0");
		readingsSingleUpdate($hash, "state", $position,1);
	if(AttrVal($name,"STMdevR","") ne "" && AttrVal($name,"STMdevL","") ne "" && AttrVal($name,"STMmaxTics","") ne "" && AttrVal($name,"STMmaxDriveSeconds","") ne "")
	{
		InternalTimer(gettimeofday() + 120, "STELLMOTOR_GetUpdate", $hash, 0);
	} else  {
		return "missing Attributes";
	}
return;
}
sub STELLMOTOR_Undefine($$){
  my($hash, $name) = @_;
  RemoveInternalTimer($hash);
  return;
}

sub STELLMOTOR_Set($@) {
	my ($hash, @args)	= @_;
	my $name = $hash->{NAME};
	my $setOption = $args[1];
	my $now = gettimeofday();
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	my $locked = ReadingsVal($name,'locked',0);
	if($setOption eq "stop"){
		STELLMOTOR_ImmediateStop($hash);
		Log3($name, 4, "STELLMOTOR $name User submitted Stop Request");
		return;
	}elsif($setOption eq "reset"){
		readingsBeginUpdate($hash);
		## weitere Readings hinzufügen?
		foreach("locked","queue_lastdiff"){
			readingsBulkUpdate($hash, $_ , 0);		
			}
		foreach("state","position"){
			readingsBulkUpdate($hash, $_ , 1);		
			}
		readingsEndUpdate($hash, 1);
		return;
	}elsif($setOption eq "position" && $locked == 0){
	 	if(length($args[2]) && $args[2] =~ /^\d+$/ && $args[2] >=0 && $args[2] <= $STMmaxTics){	
		$TargetTics = $args[2];
		readingsSingleUpdate($hash,"p_target",$args[2],1);
		readingsSingleUpdate($hash,"t_target",$args[2]*($STMmaxDriveSeconds/$STMmaxTics),1);
		}
	}elsif($setOption eq "?"){
		my $usage = "Unknown argument $setOption, choose one of <tba>" . __LINE__;
		return $usage;
	}
	if (IsDisabled($name)) {
		readingsSingleUpdate($hash, "state", "disabled_138", 0); #save requested value to queue and return
		Log3 $name, 4, "STELLMOTOR $name device is disabled";  
		return;
		}
	}
	# Was wissen wir hier: Wir wissen die Zielposition, wo wir hin sollen. 
	#Um Herauszufinden, ob wir rechts oder links bewegen müssen, brauchen wir die aktuelle position
	my $p_actual = ReadingsVal($name, "p_actual",0);
	my $t_actual = ReadingsVal($name, "t_actual",0);
	my $p_target = ReadingsVal($name, "p_target",0);
	my $t_target = ReadingsVal($name, "t_target",0);
	my $t_lastdiff = ReadingsVal($name,'queue_lastdiff',0); 

	## jetzt haben wir die alten positionen und die übrige Differenz. 
	#	
	my $t_totalMove = $t_target - $t_actual + $t_lastdiff;

	if($t_totalMove>0){ $cmd_move = "R"; }
	elsif($t_totalMove<0){ $cmd_move = "L"; }
	
	$t_totalMove=abs($t_totalMove); #be shure to have positive moveCmdTime value
	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	readingsSingleUpdate($hash,"t_lastStart", $now,1);

	readingsSingleUpdate($hash, "t_stop", ($now+$t_totalMove), 1); #set the end time of the move

	my $timestring = strftime "%Y-%m-%d %T",localtime($now + $t_totalMove);
	readingsSingleUpdate($hash,"t_stopHR", $timestring,1);


	STELLMOTOR_commandSend($hash,$directionRL);
	return;
	}
sub STELLMOTOR_ImmediateStop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	if(ReadingsVal($name,'locked', 1)==0){
		return; #no move in progress, nothing to stop
		}
	}

sub STELLMOTOR_Stop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	my $OutType = AttrVal($name,'STMOutType', "dummy");
	if(($OutType ne "PiFace") and ($OutType ne "Gpio") and ($OutType ne "FhemDev") and ($OutType ne "SysCmd")){
		return "OutType is ".$OutType.", please add Attribute STMOutType and choose one of <PiFace|Gpio|FhemDev|SysCmd>";	
		}
	STELLMOTOR_commandSend($hash,"S");
	my $now = gettimeofday();
	my $stopTime = ReadingsVal($name,"stopTime",$now);
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);

	my $lastGuiState = ReadingsVal($name,'state', 1);
	if(!($lastGuiState=~/^\d+$/)){
		Log3($name, 3, "STELLMOTOR $name Stop Problem: lastGuiState:$lastGuiState please report this error L.".__LINE__);
		$lastGuiState=1;
		}
	my $queue_lastdiff = ($stopTime-$now)*$STMmaxTics/$STMmaxDriveSeconds*(
			(ReadingsVal($name,'position', 1)> $lastGuiState
			)?1:-1);
	#recalculate the position and write recalculated value to state
	my($secPerTic)=AttrVal($name, "STMmaxDriveSeconds", 107)/AttrVal($name, "STMmaxTics", 100);  #now we have the time in seconds for 1 tic
	my($posAdjust)= int($queue_lastdiff/$secPerTic);
	my($position)=ReadingsVal($name,'position', "StopError");
	$position-=$posAdjust;
	$queue_lastdiff-=$posAdjust;
	readingsSingleUpdate($hash,'position',$position,1); #update position reading
	#update the readings after stop and post-proc
	readingsSingleUpdate($hash, "queue_lastdiff", $queue_lastdiff, 1); #store time diff for next cmd
	readingsSingleUpdate($hash, "locked", 0, 1); #unlock device
	readingsSingleUpdate($hash, "stopTime", 0, 1); #reset stoptime to zero
	readingsSingleUpdate($hash,'state',$position,1); #update position reading
	if(ReadingsVal($name,'DoResetAtStop', "afterCalibrate") eq "afterCalibrate"){
		readingsSingleUpdate($hash, "DoResetAtStop", gettimeofday(), 1); #set actual time = last calibrate
		if(AttrVal($name,"STMresetOtherDeviceAtCalibrate",0)){
			CommandSet(undef, AttrVal($name,"STMresetOtherDeviceAtCalibrate",0)." reset");
			Log3($name, 4, "STELLMOTOR $name STMresetOtherDeviceAtCalibrate:".AttrVal($name,"STMresetOtherDeviceAtCalibrate",0));
			}
		STELLMOTOR_Set($hash,$name,"reset");
		}
	Log3($name, 4, "STELLMOTOR $name Stop Timing Call: stopTime:$stopTime now:$now queue_lastdiff:$queue_lastdiff");
	}

sub STELLMOTOR_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $STMtimeTolerance = AttrVal($name, "STMtimeTolerance", 0.01);
	my $stopTime = ReadingsVal($name,"stopTime", 0);
	my $now = gettimeofday();
	if(($stopTime ne 0) and (($stopTime-$now)<$STMtimeTolerance)){
		STELLMOTOR_Stop($hash);
		}
	my $command_queue = ReadingsVal($name,"command_queue", 0);
	my $queue_lastdiff = ReadingsVal($name,"queue_lastdiff", 0);
	my $locked = ReadingsVal($name,"locked", 0);
	my $STMlastDiffMax = AttrVal($name, "STMlastDiffMax", 1);
	my $position = ReadingsVal($name,"position", 1);
	if($command_queue>0 and $locked==0){
		Log3($name, 4, "STELLMOTOR $name command_queue Set Call: command_queue:$command_queue");
		readingsSingleUpdate($hash, "command_queue", 0, 1); #remove old value from queue start the drive
		STELLMOTOR_Set($hash,$name,$command_queue);
	}elsif(abs($queue_lastdiff)>$STMlastDiffMax){ 				#start new drive if last diff > 1sec (attr: STMlastDiffMax)
		Log3($name, 4, "STELLMOTOR $name queue_lastdiff over STMlastDiffMax Call: queue_lastdiff:$queue_lastdiff");
		STELLMOTOR_Set($hash,$name,$position);
		}
	my $STMpollInterval = AttrVal($name, "STMpollInterval", 0.1);
	if ($STMpollInterval ne "off") {
		InternalTimer($now) + ($STMpollInterval), "STELLMOTOR_GetUpdate", $hash, 0);
#		STELLMOTOR_Get($hash,"position");
		}
#fetch missing pos.value in state after reboot
	my $lastGuiState = ReadingsVal($name,'state', 1);
	if(!($lastGuiState=~/^\d+$/)){
		Log3($name, 3, "STELLMOTOR $name Stop Problem: lastGuiState:$lastGuiState please report this error L.".__LINE__);
		my $position = ReadingsVal($name,'position', "1");
		readingsSingleUpdate($hash,'state',$position,1); #update position reading
		$lastGuiState=1;
		}
#end debug
	return;
	}
sub STELLMOTOR_Get($@){
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	return "bei get gibts keine Hilfe und keine Optionen";
	}
sub STELLMOTOR_Notify(@) {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME}; 
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED$/,@{$dev->{CHANGED}})){
    Log3($name, 3, "STELLMOTOR $name initialized");
    STELLMOTOR_GetUpdate($hash);    
  }
  return;
}
sub STELLMOTOR_Attr(@) {
	my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};
	return "noattr";
	}

sub STELLMOTOR_Calibrate($@){
#drive to left (or right if attr) for maximum time and call "set reset"
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	return;
	}

1;
