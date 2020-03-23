<<<<<<< HEAD
# $Id: 39_STELLMOTOR.pm 3002 2014-10-03 11:51:00Z Florian Duesterwald $
####################################################################################################
#
#	39_STELLMOTOR.pm
#
#	drive a valve to percent value, based on motor drive time
#
#	This file is free contribution and not part of fhem.
#	refer to mail a t duesterwald d.o.t info if necessary
#	http://forum.fhem.de/index.php?action=profile;u=6340
#
#	thanks to cwagner for testing and a great documentation of the module:
#	http://www.fhemwiki.de/wiki/STELLMOTOR
#	http://www.fhemwiki.de/wiki/Mischersteuerung
#	
#	for Gpio and for PiFace type you need to have wiringPi installed first
#	at default location: /usr/local/bin/gpio
#	
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
# V3003 STMtimeTolerance should be 0.001 
# V3004 added set value where Value is allowed between 0 and STMmaxTics
# V3005 OutType -> Attribute instead of define and Reading
# V3006 Added reading fir last runtime
# V3007 STMlastdiffmax is now available as float. no safety checks performed!
# V3008 STMmaxTics is now expanded to 360, as there are some motors turning up to 355 degrees
# V3009	tes
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

sub STELLMOTOR_commandSend($@){
	#params: stop or start: R or L drive
	my ($hash, @args)	= @_;
	my $name = $hash->{NAME};
	my $command = $args[0]; #command= R | L | S
	#desired states for start and stop cmds, apply invert to this
	#state  R  L  STOP
	#portRL  1  1  0		#früher:startport
	#portST  1  0  0		#früher:rlport
	my %portRL = (	"R" => 1,
					"L" => 0,
					"S" => 0	);
	my %portST = (	"R" => 1,
					"L" => 1,
					"S" => 0	);

	#wechsel / einzel ? return desired state for both ports at R/L
	my $STMrlType = AttrVal($name, "STMrlType", "einzel");
	if($STMrlType eq "einzel"){
		#change portRL val at R move if attr STMrlType is present (to get zero if type = einzel)
		$portST{"R"}=0;
	}elsif($STMrlType ne "wechsel"){
		Log3($name, 3, "STELLMOTOR $name attr STMrlType has unknown value:".$STMrlType);
		return;
		}
	#invert 1 and zero, maybe needed for funny hardware conditions
	#some funny devices may need other stuff than 0|1 to switch off|on
	my $STMinvertOutVals = AttrVal($name, "STMinvertOut", 0);
	my $STMmapOffCmd = AttrVal($name, "STMmapOffCmd", 0);
	my $STMmapOnCmd = AttrVal($name, "STMmapOnCmd", 0);
	foreach("R","L","S"){
		if($STMinvertOutVals ne "0"){
			$portRL{$_}=($portRL{$_}?0:1); #first do the invert
			$portST{$_}=($portST{$_}?0:1); #first do the invert
			}
		if($STMmapOnCmd ne "0"){
			$portRL{$_}=($portRL{$_}?$STMmapOnCmd:$portRL{$_}); #do the mapping for 0
			$portST{$_}=($portST{$_}?$STMmapOnCmd:$portST{$_}); #do the mapping for 0
			}
		if($STMmapOffCmd ne "0"){
			$portRL{$_}=($portRL{$_}?$portRL{$_}:$STMmapOffCmd); #do the mapping for 0
			$portST{$_}=($portST{$_}?$portST{$_}:$STMmapOffCmd); #do the mapping for 0
			}
		}
	#2014-06-13 debug
	if(AttrVal($name,"STMdebugToLog3",0)){
		foreach("R","L","S"){
			Log3($name, 3, "STELLMOTOR $name debug data for ".$_."=>rl=".$portRL{$_}.",st=".$portST{$_});
			}
		}
	#actual state of the cmd hash data example:
	#state  R  L  STOP
	#portRL  on on off		#früher:startport
	#portST  on off off		#früher:rlport
	#check dev type and exec the commands
	my($cmd,$execRL,$execSTART);
	#define <name> STELLMOTOR <PiFace|Gpio|SysCmd|FhemDev> 
	my $OutType = AttrVal($name, "STMOutType", "dummy");
	if(($OutType eq "PiFace") or ($OutType eq "Gpio")){
		#pif and gpio eigentlich sinnlos, bleiben trotzdem erhalten für DAU und für abwärts-kompatibilität
		#cmd type Gpio / #cmd type PiFace
		$cmd = "/usr/local/bin/gpio";
		my $outPinBase = 0; #gpio pins without recalc
		if($OutType eq "PiFace"){
			$outPinBase = 200; #recalc +200 for the pins
			$cmd .=" -p"; #use -p option for gpio
			}
		my($startport)=AttrVal($name, "STMgpioPortRL", 5);
		my($rlport)=AttrVal($name, "STMgpioPortSTART", 4);
		if($command ne "S"){ #rl first on move, rl last on stop
			$execRL = $cmd." write ".($outPinBase+$rlport)." ".$portRL{$command};
			$execRL = `$execRL`;
			}
		$execSTART = $cmd." write ".($outPinBase+$startport)." ".$portST{$command};
		$execSTART = `$execSTART`;
		if($command eq "S"){ #rl first on move, rl last on stop
			$execRL = $cmd." write ".($outPinBase+$rlport)." ".$portRL{$command};
			$execRL = `$execRL`;
			}
	}elsif($OutType eq "SysCmd"){
		my $STMsysCmdRL = AttrVal($name, "STMsysCmdRL", 0);
		my $STMsysCmdSTART = AttrVal($name, "STMsysCmdSTART", 0);
		if($command ne "S"){ #rl first on move, rl last on stop
			$execRL = $STMsysCmdRL." ".$portRL{$command};
			$execRL = `$execRL`;
			}
		$execSTART = $STMsysCmdSTART." ".$portST{$command};
		$execSTART = `$execSTART`;
		if($command eq "S"){ #rl first on move, rl last on stop
			$execRL = $STMsysCmdRL." ".$portRL{$command};
			$execRL = `$execRL`;
			}
	}elsif($OutType eq "FhemDev"){
		my $STMfhemDevRL = AttrVal($name, "STMfhemDevRL", "Stellmotor2rl");
		if($command ne "S"){ #rl first on move, rl last on stop
			CommandSet(undef,$STMfhemDevRL." ".$portRL{$command});
			}
		my $STMfhemDevSTART = AttrVal($name, "STMfhemDevSTART", "Stellmotor2start");
		CommandSet(undef,$STMfhemDevSTART." ".$portST{$command});
		if($command eq "S"){ #rl first on move, rl last on stop
			CommandSet(undef,$STMfhemDevRL." ".$portRL{$command});
			}
	#2014-06-13 debug
	if(AttrVal($name,"STMdebugToLog3",0)){
		Log3($name, 3, "STELLMOTOR $name debug2 command: set ".$STMfhemDevRL." ".$portRL{$command});
		Log3($name, 3, "STELLMOTOR $name debug2 command: set ".$STMfhemDevSTART." ".$portST{$command});
		}
	}elsif($OutType eq "dummy"){
		Log3($name, 3, "STELLMOTOR $name testing with device type:".$OutType);
		return;
	}else{  #$OutType eq "dummy" or unknown value
		Log3($name, 3, "STELLMOTOR $name unknown device type:".$OutType);
		return;
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
	my($attrlist);
	foreach(_stmAttribs("keys","")){
		$attrlist.=" ".$_;
		if(_stmAttribs("listval",$_) ne "all"){
			if(_stmAttribs("listval",$_)=~/:/){
				$attrlist.=":";
				my($min,$max)=split(/:/,_stmAttribs("listval",$_));
				while($min<$max){
					$attrlist.=$min.",";
					$min++;
					}
				$attrlist.=$max;
			}elsif(_stmAttribs("listval",$_)=~/,/){
				$attrlist.=":"._stmAttribs("listval",$_);
				}
#" disable:0,1 STMmaxTics:10,12,100,1000 STMmaxDriveSeconds " .
			}
		}
	$hash->{AttrList}	= "disable:0,1 ".$readingFnAttributes.$attrlist;
	}
sub STELLMOTOR_Define($$){
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	my $menge = int(@args);
	if (int(@args) < 1) {
	return "Define: to less arguments. Usage:\n" .
#		  "define <name> STELLMOTOR <RL-Out-Port> <Start-Out-Port>";
		  "define <name> STELLMOTOR <PiFace|Gpio|SysCmd|dummy|FhemDev>";
	}
	my $name = $args[0];
	#no need for readingsUpdate as its a Attribute now	
#	readingsSingleUpdate($hash, "OutType", $args[2], 1);
	$hash->{NOTIFYDEV} = "global";
	#if(($args[2] ne "PiFace") and ($args[2] ne "Gpio") and ($args[2] ne "SysCmd") and ($args[2] ne "FhemDev") and ($args[2] ne "dummy")){
	#	return "Define: Err87 unsupported Output Device ".$args[2].". Usage:\n" .
	#		"define <name> STELLMOTOR <PiFace|Gpio|SysCmd|FhemDev>";
	#		}
	Log3($name, 3, "STELLMOTOR $name active, type=".$args[2]);
	readingsSingleUpdate($hash, "state", "initialized",1);
	my $position = ReadingsVal($name,"position", "0");
	readingsSingleUpdate($hash, "state", $position,1);
	#set attr based on device type
	foreach(_stmAttribs("keys","")){
		if(AttrVal($name,$_,"missing") ne "missing"){
			#nothing, only set non-present attr
		}elsif(_stmAttribs("area",$_) eq "global"){
			CommandAttr(undef,$name." ".$_." "._stmAttribs("default",$_));
		}elsif($args[2] eq _stmAttribs("area",$_)){
			CommandAttr(undef,$name." ".$_." "._stmAttribs("default",$_));
			}
		}
	InternalTimer(gettimeofday() + 120, "STELLMOTOR_GetUpdate", $hash, 0);
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
	my $OutType = AttrVal($name,'STMOutType', "dummy");
	my $moveTarget = $args[1];
	my $now = gettimeofday();
	if($moveTarget eq "calibrate"){STELLMOTOR_Calibrate($hash);return;}
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	if($moveTarget eq "stop"){
		STELLMOTOR_ImmediateStop($hash);
		Log3($name, 4, "STELLMOTOR $name User submitted Stop Request");
		return;
	}elsif($moveTarget eq "reset"){
		readingsBeginUpdate($hash);
		foreach(("locked","queue_lastdiff","command_queue")){
			readingsBulkUpdate($hash, $_ , 0);		
			}
		foreach(("state","position")){
			readingsBulkUpdate($hash, $_ , 1);		
			}
		readingsEndUpdate($hash, 1);
		return;
	}elsif($moveTarget eq "position"){
	 	if(length($args[2]) && $args[2] =~ /^\d+$/ && $args[2] >=0 && $args[2] <= $STMmaxTics){	
		$moveTarget = $args[2];
		readingsSingleUpdate($hash,"p_target",$args[2],1) if(AttrVal($name,"STMShowMoreReadings",0));
		readingsSingleUpdate($hash,"t_target",$args[2]*($STMmaxDriveSeconds/$STMmaxTics),1) if(AttrVal($name,"STMShowMoreReadings",0));
		}
	}elsif(($moveTarget eq "?") or ($moveTarget < 1) or ($moveTarget > ($STMmaxTics+1))){
		if($moveTarget eq "0"){$moveTarget.=" (min.value is 1) ";}
		my $usage = "Unknown argument $moveTarget, choose one of calibrate:noArg position reset:noArg stop:noArg";
		foreach(1,2,8,9,10,16,21,27,33,44,50,55,66,77,88,99){ $usage .= " ".$_.":noArg "; }
		return $usage;
	}
	if (IsDisabled($name)) {
		readingsSingleUpdate($hash, "command_queue", $moveTarget, 0); #save requested value to queue and return
		Log3 $name, 4, "STELLMOTOR $name device is disabled - set:".$moveTarget." only in queue.";  
		return;
		}
	my $locked = ReadingsVal($name,'locked',0);
	if ($locked eq 1) {
		if($now - ( ReadingsVal($name,'lastStart',0) + $STMmaxDriveSeconds + 10 ) < 0){
			#check time since last cmd, if < MaxDrvSecs, queue command and return
			readingsSingleUpdate($hash, "command_queue", $moveTarget, 0); #save requested value to queue and return
			return;
			}
		}
#	if(($OutType ne "PiFace") and ($OutType ne "Gpio") and ($OutType ne "FhemDev") and ($OutType ne "OtherOutType")){
	if(($OutType ne "PiFace") and ($OutType ne "Gpio") and ($OutType ne "SysCmd") and ($OutType ne "FhemDev")){
		return "Unknown argument ".$OutType.", choose one of <PiFace|Gpio|FhemDev|SysCmd>";	
		}
	my $actual_state = ReadingsVal($name,'position',1); #Use default 1 to omit error on first use
	readingsSingleUpdate($hash,"d_actual_state",i$actual_state,1) if(AttrVal($name,"STMShowMoreReadings",0));
	
	readingsSingleUpdate($hash,'position',$moveTarget,1); #update position reading
	$moveTarget = $moveTarget + ReadingsVal($name,'queue_lastdiff',0); #add last time diff or old value below 1 Tic
	
	readingsSingleUpdate($hash,"p_target+lastdiff",$moveTarget,1) if(AttrVal($name,"STMShowMoreReadings",0));
	readingsSingleUpdate($hash, "queue_lastdiff", 0, 1);

	readingsSingleUpdate($hash,"t?_lastdiff", 0,1) if(AttrVal($name,"STMShowMoreReadings",0));
	my $moveCmdTime = $moveTarget-$actual_state;

	readingsSingleUpdate($hash,"p_move", $moveCmdTime,1) if(AttrVal($name,"STMShowMoreReadings",0));
	my $STMtimeTolerance = AttrVal($name, "STMtimeTolerance", 0.001);
	if( ((abs($moveCmdTime) - $STMtimeTolerance) <= 1 )){
		readingsSingleUpdate($hash, "queue_lastdiff", $moveCmdTime, 1);
		readingsSingleUpdate($hash,"t?_lastdiff", $moveCmdTime,1) if(AttrVal($name,"STMShowMoreReadings",0));
		return;
		}
	my $directionRL = "L";
	if($moveCmdTime>0){ $directionRL = "R"; }
	Log3($name, 4, "STELLMOTOR $name Set Target:".int($moveTarget)." Cmd:".$moveCmdTime." RL:".$directionRL);
	$moveCmdTime=abs($moveCmdTime); #be shure to have positive moveCmdTime value
	readingsSingleUpdate($hash, "lastRun", $moveCmdTime, 1);
	readingsSingleUpdate($hash,"p_lastDuration", $moveCmdTime,1) if(AttrVal($name,"STMShowMoreReadings",0));

	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	readingsSingleUpdate($hash, "lastStart", $now, 1); #set the actual drive starttime
	readingsSingleUpdate($hash,"t_lastStart", $now,1) if(AttrVal($name,"STMShowMoreReadings",0));


	$moveCmdTime=$moveCmdTime*$STMmaxDriveSeconds/$STMmaxTics;  #now we have the time in seconds the motor must run
	
	readingsSingleUpdate($hash,"t_move", $moveCmdTime,1) if(AttrVal($name,"STMShowMoreReadings",0));

	readingsSingleUpdate($hash, "stopTime", ($now+$moveCmdTime), 1); #set the end time of the move


	readingsSingleUpdate($hash,"t_stop", $now+$moveCmdTime,1) if(AttrVal($name,"STMShowMoreReadings",0));

	my $timestring = strftime "%Y-%m-%d %T",localtime($now + $moveCmdTime);
	readingsSingleUpdate($hash,"t_stopHR", $timestring,1) if(AttrVal($name,"STMShowMoreReadings",0));


	STELLMOTOR_commandSend($hash,$directionRL);
	return;
	}
sub STELLMOTOR_ImmediateStop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	if(ReadingsVal($name,'locked', 1)==0){
		return; #no move in progress, nothing to stop
		}
	my $OutType = AttrVal($name,'STMOutType', "dummy");
	if(($OutType ne "PiFace") and ($OutType ne "Gpio") and ($OutType ne "FhemDev") and ($OutType ne "SysCmd")){
		return "OutType is ".$OutType.", please add Attribute STMOutType and choose one of <PiFace|Gpio|FhemDev|SysCmd>";	
		#return "Unknown argument ".$OutType.", choose one of <PiFace|Gpio|FhemDev|SysCmd>";	
		}
	my $now = gettimeofday();
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	my $lastGuiState = ReadingsVal($name,'state', 1);
	if(!(ReadingsVal($name,'state', "e")=~/^\d+$/)){
		Log3($name, 3, "STELLMOTOR $name Stop Problem: lastGuiState:$lastGuiState please report this error L.".__LINE__);
		readingsSingleUpdate($hash, "state", "1", 1); #debug stuff
		}
	#get direction: +/- position=desired state=last
	my($directionInProgress)=1; #default positive 1=right
	if(ReadingsVal($name,'state', 1)==ReadingsVal($name,'position', 1)){
		return; #no move in progress
	}elsif(ReadingsVal($name,'state', 1)>ReadingsVal($name,'position', 1)){
		$directionInProgress=-1; #left move in progress
	}else{ #right move in progress
		}
	#calc now -> tics-per-sec -> actual pos
	my($progressedTime)=($now-ReadingsVal($name,'lastStart', 1));
	my($secPerTic)=AttrVal($name, "STMmaxDriveSeconds", 107)/AttrVal($name, "STMmaxTics", 100);  #now we have the time in seconds for 1 tic
	my($progressedTics)=($progressedTime/$secPerTic);
	$progressedTics=sprintf("%.0f",$progressedTics);
	#new target = state + (dir 1/-1)*(already progressed tics +1) #round up/down based on direction
	my($newTarget)=ReadingsVal($name,'state', 1)+(($progressedTics+1)*$directionInProgress);
	#update readings: position
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "position" , $newTarget);
	#recalc and set new stopTime
	my($newStopTime)=ReadingsVal($name,'lastStart', 1)+(($progressedTics+1)*$secPerTic);
	readingsBulkUpdate($hash, "stopTime" , $newStopTime);
	#readingsSingleUpdate($hash, "debug_19", "lastGuiState".$lastGuiState, 1); #debug stuff
	readingsEndUpdate($hash, 1);
	#let STELLMOTOR_GetUpdate do the physical stop
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
	my $get = $a[1];
	my @stmgets = (keys(%{$hash->{READINGS}}));
	$get="?" if(!_stm_in_array($get,(@stmgets,"attrHelp","readingsHelp","stmWwiki")));
	my $usage = "Unknown argument $get, choose one of";
	foreach(@stmgets){
		$usage.=" ".$_.":noArg";
		}
	$usage.=" attrHelp:";
	my($first)=0;
	foreach(_stmAttribs("keys","")){
		if($first){
			$usage.=$_;
			$first=0;
		}else{
			$usage.=",".$_;
			}
		}
	$usage.=" readingsHelp:";
	foreach(_stmRdings("keys","")){
		$usage.=$_.",";
		}
	$usage.=" stmWwiki:get,set,readings,attr";
	#check what has been requested?
	if($get eq "attrHelp"){return _stmAttribs("help",$a[2]);}
	if($get eq "readingsHelp"){return _stmRdings("help",$a[2]);}
	if($get eq "stmWwiki"){
		my $bereich = $a[2];
		#bereich "get" "set" "readings" "attr"
		my $wret;
		if($bereich eq "get"){
			$wret=STELLMOTOR_Get($hash,$name,"?");
			$wret=~s/Unknown argument \?, choose one of//g;
			$wret=~s/\s+/\n* /g;
 			$wret=~s/:noArg//g;
			$wret=~s/:/: /g;
			return "extracted usage of get command:\n\n".$wret
		}elsif($bereich eq "set"){
			$wret=STELLMOTOR_Set($hash,$name,"?");
			$wret=~s/Unknown argument \?, choose one of//g;
			$wret=~s/\s+/\n* /g;
			$wret=~s/:noArg//g;
			$wret=~s/:/: /g;
			return "extracted usage of set command:\n\n".$wret;
		}elsif($bereich eq "readings"){
			$wret="\n== Readings ==\nAlle Readings sind auch in fhem durch das kommando get readingsHelp <varname> erklärt, für's \"".
			"schnelle nachschauen zwischendurch\".\n\n{| class=\"wikitable sortable\"\n|-\n! Reading !! (Typ) Default !! Beschreibung\n|-\n";
			foreach(_stmRdings("keys","")){
				$wret.="| ".	$_."|| ("._stmRdings("type",$_).") "._stmRdings("default",$_)." || "._stmRdings("description",$_)."\n|-\n";
				}
			$wret.="\n|}\n\n";
		}elsif($bereich eq "attr"){
			$wret="\n== Attributes ==\nAlle Attributes sind auch in fhem durch das kommando get attrHelp <varname> erklärt, für's \"".
			"schnelle nachschauen zwischendurch\".\n\n{| class=\"wikitable sortable\"\n|-\n! Attribute !! (Typ) Default !! Beschreibung\n|-\n";
			foreach(_stmAttribs("keys","")){
				$wret.="| ".	$_."|| ("._stmAttribs("type",$_).") "._stmAttribs("default",$_)." || "._stmAttribs("description",$_)."\n|-\n";
				}
			$wret.="\n|}\n\n";
		}else{
			return "get Error in Line ".__LINE__;
			}
		return $wret;
		}
	return $usage if $get eq "?";
	my $ret = $get.": ".ReadingsVal($name,$get, "Unknown");
	return $ret;
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
	#validate special attr STMpollInterval
	if ($attrName eq "STMpollInterval") {
		if (!defined $attrVal) {
			RemoveInternalTimer($hash);    
			Log3($name, 4, "STELLMOTOR $name attr [$attrName] deleted");
			CommandDeleteAttr(undef, "$name STMpollInterval");
		} elsif ($attrVal eq "off" || ( $attrVal >= 0.01 and $attrVal <= 600 ) ) {
			Log3($name, 4, "STELLMOTOR $name attribute-value [$attrName] = $attrVal changed");
			STELLMOTOR_GetUpdate($hash);
		} else {
			RemoveInternalTimer($hash);
			Log3($name, 3, "STELLMOTOR $name attribute-value [$attrName] = $attrVal wrong, use seconds >0.01 as float (max 600)");
			}
	#fetch all remaining attribs and just check if data type matches
	} elsif (_stm_in_array($attrName,_stmAttribs("keys"," "))) {
		if (!defined $attrVal){
			CommandDeleteAttr(undef, "$name $attrName");
		} elsif (_stmvalidateAttr($attrName, $attrVal) ) {
			Log3($name, 4, "STELLMOTOR $name attribute-value [$attrName] = $attrVal changed");
		} else {
			CommandDeleteAttr(undef, "$name attrName");
			}
		}
	return;
	}
sub STELLMOTOR_Calibrate($@){
#drive to left (or right if attr) for maximum time and call "set reset"
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = ReadingsVal($name,'STMmaxTics', "100");
	my $OutType = AttrVal($name,'STMOutType', "dummy");
	if(($OutType ne "PiFace") and ($OutType ne "Gpio") and ($OutType ne "FhemDev") and ($OutType ne "SysCmd") and ($OutType ne "dummy")){
		return "OutType is ".$OutType.", please add Attribute STMOutType and choose one of <PiFace|Gpio|FhemDev|SysCmd>";	
		#return "Unknown argument ".$OutType.", choose one of <PiFace|Gpio|FhemDev|SysCmd>";	
		}

my $STMcalibrateDirection = AttrVal($name, "STMcalibrateDirection", "L");
	my $moveTime = 1 + $STMmaxTics; #1 tic more than 100 to be shure to be at pos.1
	Log3($name, 4, "STELLMOTOR $name Calibrate Started, RL:".$STMcalibrateDirection);
	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	readingsSingleUpdate($hash, "lastStart", gettimeofday(), 1); #set the actual drive starttime
	$moveTime=$moveTime*$STMmaxDriveSeconds/$STMmaxTics;  #now we have the time in seconds the motor must run
	readingsSingleUpdate($hash, "stopTime", (gettimeofday()+$moveTime), 1); #set the end time of the move
	readingsSingleUpdate($hash, "DoResetAtStop", "afterCalibrate", 1); #set the end time of the move
	STELLMOTOR_commandSend($hash,AttrVal($name,"STMcalibrateDirection","L"));
	return;
	}

sub _stm_in_array($@){
	my ($search_for,@arr) = @_;
	foreach(@arr){
		return 1 if $_ eq $search_for;
		}
	return 0;
	}
sub _stmvalidateAttr($@){
	#usage: _stmvalidateAttr($attrName, $attrVal)
	my($attrName, $attrVal)=@_;
	#validate special attr and refuse
	if(($attrName eq "STMmaxTics") and ($attrVal<1)){
		return 0;
	}elsif(($attrName eq "STMrlType") and (($attrVal ne "wechsel") and ($attrVal ne "einzel"))){
		return 0;
		}
	my $attrType = _stmAttribs("type",$attrName);
	if($attrType eq "int"){
		return 1 if $attrVal=~/^[-+]?\d+$/;
	}elsif($attrType eq "float"){
		return 1 if $attrVal=~/^[-+]?\d+\.?\d*$/;
	}elsif($attrType eq "string"){
		return 1 if length($attrVal);
	}else{
		return 0;
		}
	}
sub _stmRdings($@){
	#usage: _stmRdings("help","stmVarName")
	# "keys" || "default" || "type" || "help"  ,<keyname>
	my($type,$reqKey)=@_;
	my %rdings = (
"OutType"=>[("PiFace","string","in der device definition festgelegter OutType, DEPRECATED","global","PiFace,Gpio,SysCmd,dummy,FhemDev")],
"state"=>[("active","string","aktuelle position oder fehlermeldung","global","active,error,initialized,0..100")],
"command_queue"=>[("0","int","befehl in der warteschleife","global","0..100")],
"position"=>[("1","int","aktuelle desired position","global","0..100")],
"queue_lastdiff"=>[("0","float","letzte zeitdifferenz","global","float")],
"locked"=>[("0","int","1 während motor gerade läuft","global","0,1")],
"lastStart"=>[("0","float","zeitstempel letzter start des motors","global","float")],
"stopTime"=>[("0","float","zeitstempel nächster stop des motors","global","float")],
"DoResetAtStop"=>[("afterCalibrate","string","temporärwert nur während kalibrierungsphase","global","'',afterCalibrate")],
	);
	if($type eq "keys"){
		return keys(%rdings);
	}elsif($type eq "default"){
		return $rdings{$reqKey}[0];
	}elsif($type eq "type"){
		return $rdings{$reqKey}[1];
	}elsif($type eq "description"){
		return $rdings{$reqKey}[2];
	}elsif($type eq "area"){
		return $rdings{$reqKey}[3];
	}elsif($type eq "listval"){
		return $rdings{$reqKey}[4];
	}elsif($type eq "help"){
		return "readingsHelp for ".$reqKey.":\n default:".$rdings{$reqKey}[0]." type:".$rdings{$reqKey}[1]." listval:".$rdings{$reqKey}[4]
			." \ndescription:".$rdings{$reqKey}[2];
	}else{
		return "_ rdings?";
		}
	}
sub _stmAttribs($@){
	#usage: _stmAttribs("type","stmVarName")
	# "keys" || "default" || "type" || "help"  ,<keyname>
	my($type,$reqKey)=@_;
	my %attribs = (
"STMShowMoreReadings"=>[("0","int","je nach Hardware","global","0,1")],
"STMOutType"=>[("dummy","string","je nach Hardware","global","FhemDev,PiFace,Gpio,SysCmd")],
"STMrlType"=>[("einzel","string","je nach schaltplan, wechsel=start+RL-relais, einzel=R-relais+L-relais","global","wechsel,einzel")],
"STMinvertOut"=>[("0","int","setzen für devices die 0 für start und 1 für stop erwarten","global","0,1")],
"STMmapOffCmd"=>[("0","string","string der im device-command anstatt '0' verwendet wird für stop","global","all")],
"STMmapOnCmd"=>[("0","string","string der im device-command anstatt '1' verwendet wird für start","global","all")],
"STMgpioPortRL"=>[("5","int","piface port oder gpio port für RL oder R relais (bei RL ist 1=R)","PiFaceGpio","0:31")],
"STMgpioPortSTART"=>[("4","int","piface port oder gpio port für START (oder L relais bei 'einzel')","PiFaceGpio","0:31")],
"STMsysCmdRL"=>[("0","string","freies command das für RL an die shell übergeben wird","SysCmd","all")],
"STMsysCmdSTART"=>[("0","string","freies command das für START an die shell übergeben wird","SysCmd","all")],
"STMfhemDevRL"=>[("RelaisRL","string","fhem device name für RL (oder R) aktor","FhemDev","all")],
"STMfhemDevSTART"=>[("RelaisSTART","string","fhem device name für START (oder L) aktor","FhemDev","all")],
"STMmaxDriveSeconds"=>[("107","int","gestoppte Zeit in Sekunden, die der Motor für die Fahrt von 0 bis 100 Prozent braucht","global","all")],
"STMmaxTics"=>[("100","int","Mischerstellung - bei Prozentangaben (PID20) 100, bei Winkelangaben anzupassen","global","1:360")],
"STMtimeTolerance"=>[("0.01","float","stop-time differenzen kleiner als dieser wert werden ignoriert","global","0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.1")],
"STMresetOtherDeviceAtCalibrate"=>[("0","string","zusätzliches fhem device das am ende der kalibrierung 'set ** reset' gesendet bekommt","global","all")],
"STMpollInterval"=>[("0.1","float","Zeitintervall nach dem FHEM prüft, ob die interne Stoppzeit erreicht wurde. Hier sollte möglichst kleiner Wert aein, nur erhöhen falls FHEM zu langsam läuft","global","all")],
"STMcalibrateDirection"=>[("L","string","auf R wird die kalibrierung nach rechts gefahren, default=links","global","L,R")],
"STMlastDiffMax"=>[("1","float","ist die stoppzeit weiter als dieser wert vom Soll entfernt, wird sofort neuer drive gestartet","global","all")],
"STMdebugToLog3"=>[("0","int","jedes gesendete command ins Log schreiben","global","0,1")],
	);
	if($type eq "keys"){
		return keys(%attribs);
	}elsif($type eq "default"){
		return $attribs{$reqKey}[0];
	}elsif($type eq "type"){
		return $attribs{$reqKey}[1];
	}elsif($type eq "description"){
		return $attribs{$reqKey}[2];
	}elsif($type eq "area"){
		return $attribs{$reqKey}[3];
	}elsif($type eq "listval"){
		return $attribs{$reqKey}[4];
	}elsif($type eq "help"){
		return "attrHelp for ".$reqKey.":\n default:".$attribs{$reqKey}[0]." type:".$attribs{$reqKey}[1]." area:".$attribs{$reqKey}[3]
			." \nlistval:".$attribs{$reqKey}[4]
			." \ndescription:".$attribs{$reqKey}[2];
	}else{
		return "_ attribs?";
		}
	}

1;
=======
####################################################################################################
# $Id: 39_STELLMOTOR.pm 3102 2019-03-10 11:51:00Z StephanAugustin $
#
#	39_STELLMOTOR.pm
#
#	drive a valve to percent value, based on motor drive time
#
#	This file is free contribution and not part of fhem.
#	refer to mail a t duesterwald d.o.t info if necessary
#	http://forum.fhem.de/index.php?action=profile;u=6340
#
#	thanks to cwagner for testing and a great documentation of the module:
#	http://www.fhemwiki.de/wiki/STELLMOTOR
#	http://www.fhemwiki.de/wiki/Mischersteuerung
#	
#	for Gpio and for PiFace type you need to have wiringPi installed first
#	at default location: /usr/local/bin/gpio
#	
#	Fhem is free software: you can redistribute it and/or modify
#	it under the terms of the GNU General Public License as published by
#	the Free Software Foundation, either version 2 of the License, or
#	(at your option) any later version.
#
#	Fhem is distributed in the hope that it will be useful,
#	but WITHOUT ANY WARRANTY; without even the implied warranty of
#	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#	GNU General Public License for more details.
#
#	You should have received a copy of the GNU General Public License
#	along with fhem.  If not, see <http://www.gnu.org/licenses/>.
#
# V3003: added support for xternal reset-Device
# still probls V3004 added set <value> where Value is allowed between 0 and STMmaxTics
##done V3005 expanded Value for STMmaxTics to 360, as there are some Motors that use up to 355 degree turning... 
##done V3006 STMlastDiffMax is now available as num Input. However, no safety checks are performed (yet)/ST
## done V3007 added Reading for duration of the last run
## done V3008 Bugfix: STMtimeTolerance should be 0.001 -> Wiki
## done V3009 Added OutType as Attribute...
# V3100 sorted out Tics and Time -> Major change
# V3101 reset changes all readings to "initialized", so that its clear they haven't been used yet
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

sub STELLMOTOR_commandSend($@){
	#params: stop or start: R or L drive
	my ($hash, @args)	= @_;
	my $name = $hash->{NAME};
	my $command = $args[0]; #command= R | L | S
	Log3 $name, 4, "STELLMOTOR $name i bims, 1 commandSend";  
	#desired states for start and stop cmds, apply invert to this
	#state  R  L  STOP
	#portRL  1  1  0		#frÃ¼her:startport
	#portST  1  0  0		#frÃ¼her:rlport
	my %portRL = (	"R" => 1,
					"L" => 0,
					"S" => 0	);
	my %portST = (	"R" => 1,
					"L" => 1,
					"S" => 0	);

	#wechsel / einzel ? return desired state for both ports at R/L
	my $STMrlType = AttrVal($name, "STMrlType", "einzel");
	if($STMrlType eq "einzel"){
		#change portRL val at R move if attr STMrlType is present (to get zero if type = einzel)
		$portST{"R"}=0;
	}elsif($STMrlType ne "wechsel"){
		Log3($name, 3, "STELLMOTOR $name attr STMrlType has unknown value:".$STMrlType);
		return;
		}
	#invert 1 and zero, maybe needed for funny hardware conditions
	#some funny devices may need other stuff than 0|1 to switch off|on
	my $STMinvertOutVals = AttrVal($name, "STMinvertOut", 0);
	my $STMmapOffCmd = AttrVal($name, "STMmapOffCmd", 0);
	my $STMmapOnCmd = AttrVal($name, "STMmapOnCmd", 0);
	foreach("R","L","S"){
		if($STMinvertOutVals ne "0"){
			$portRL{$_}=($portRL{$_}?0:1); #first do the invert
			$portST{$_}=($portST{$_}?0:1); #first do the invert
			}
		if($STMmapOnCmd ne "0"){
			$portRL{$_}=($portRL{$_}?$STMmapOnCmd:$portRL{$_}); #do the mapping for 0
			$portST{$_}=($portST{$_}?$STMmapOnCmd:$portST{$_}); #do the mapping for 0
			}
		if($STMmapOffCmd ne "0"){
			$portRL{$_}=($portRL{$_}?$portRL{$_}:$STMmapOffCmd); #do the mapping for 0
			$portST{$_}=($portST{$_}?$portST{$_}:$STMmapOffCmd); #do the mapping for 0
			}
		}
	#2014-06-13 debug
	if(AttrVal($name,"STMdebugToLog3",0)){
		foreach("R","L","S"){
			Log3($name, 3, "STELLMOTOR $name debug data for ".$_."=>rl=".$portRL{$_}.",st=".$portST{$_});
			}
		}
	#actual state of the cmd hash data example:
	#state  R  L  STOP
	#portRL  on on off		#frÃ¼her:startport
	#portST  on off off		#frÃ¼her:rlport
	#check dev type and exec the commands
	my($cmd,$execRL,$execSTART);
	#define <name> STELLMOTOR <PiFace|Gpio|SysCmd|FhemDev> 
	my $OutType = AttrVal($name, "STMOutType", "dummy");
	if(($OutType eq "PiFace") or ($OutType eq "Gpio")){
		#pif and gpio eigentlich sinnlos, bleiben trotzdem erhalten fÃ¼r DAU und fÃ¼r abwÃ¤rts-kompatibilitÃ¤t
		#cmd type Gpio / #cmd type PiFace
		$cmd = "/usr/local/bin/gpio";
		my $outPinBase = 0; #gpio pins without recalc
		if($OutType eq "PiFace"){
			$outPinBase = 200; #recalc +200 for the pins
			$cmd .=" -p"; #use -p option for gpio
			}
		my($startport)=AttrVal($name, "STMgpioPortRL", 5);
		my($rlport)=AttrVal($name, "STMgpioPortSTART", 4);
		if($command ne "S"){ #rl first on move, rl last on stop
			$execRL = $cmd." write ".($outPinBase+$rlport)." ".$portRL{$command};
			$execRL = `$execRL`;
			}
		$execSTART = $cmd." write ".($outPinBase+$startport)." ".$portST{$command};
		$execSTART = `$execSTART`;
		if($command eq "S"){ #rl first on move, rl last on stop
			$execRL = $cmd." write ".($outPinBase+$rlport)." ".$portRL{$command};
			$execRL = `$execRL`;
			}
	}elsif($OutType eq "SysCmd"){
		my $STMsysCmdRL = AttrVal($name, "STMsysCmdRL", 0);
		my $STMsysCmdSTART = AttrVal($name, "STMsysCmdSTART", 0);
		if($command ne "S"){ #rl first on move, rl last on stop
			$execRL = $STMsysCmdRL." ".$portRL{$command};
			$execRL = `$execRL`;
			}
		$execSTART = $STMsysCmdSTART." ".$portST{$command};
		$execSTART = `$execSTART`;
		if($command eq "S"){ #rl first on move, rl last on stop
			$execRL = $STMsysCmdRL." ".$portRL{$command};
			$execRL = `$execRL`;
			}
	}elsif($OutType eq "FhemDev"){
		my $STMfhemDevRL = AttrVal($name, "STMfhemDevRL", "Stellmotor2rl");
		if($command ne "S"){ #rl first on move, rl last on stop
			CommandSet(undef,$STMfhemDevRL." ".$portRL{$command});
			}
		my $STMfhemDevSTART = AttrVal($name, "STMfhemDevSTART", "Stellmotor2start");
		CommandSet(undef,$STMfhemDevSTART." ".$portST{$command});
		if($command eq "S"){ #rl first on move, rl last on stop
			CommandSet(undef,$STMfhemDevRL." ".$portRL{$command});
			}
	
	InternalTimer(gettimeofday() + 0.5, "STELLMOTOR_GetUpdate", $hash, 0);
	#2014-06-13 debug
	if(AttrVal($name,"STMdebugToLog3",0)){
		Log3($name, 3, "STELLMOTOR $name debug2 command: set ".$STMfhemDevRL." ".$portRL{$command});
		Log3($name, 3, "STELLMOTOR $name debug2 command: set ".$STMfhemDevSTART." ".$portST{$command});
		}
	}elsif($OutType eq "dummy"){
		Log3($name, 3, "STELLMOTOR $name testing with device type:".$OutType);
		return;
	}else{  #$OutType eq "dummy" or unknown value
		Log3($name, 3, "STELLMOTOR $name unknown device type:".$OutType);
		return;
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
	my($attrlist);
	foreach(_stmAttribs("keys","")){
		$attrlist.=" ".$_;
		if(_stmAttribs("listval",$_) ne "all"){
			if(_stmAttribs("listval",$_)=~/:/){
				$attrlist.=":";
				my($min,$max)=split(/:/,_stmAttribs("listval",$_));
				while($min<$max){
					$attrlist.=$min.",";
					$min++;
					}
				$attrlist.=$max;
			}elsif(_stmAttribs("listval",$_)=~/,/){
				$attrlist.=":"._stmAttribs("listval",$_);
				}
#" disable:0,1 STMmaxTics:10,12,100,1000 STMmaxDriveSeconds " .
			}
		}
	$hash->{AttrList}	= "disable:0,1 ".$readingFnAttributes.$attrlist;
	}
sub STELLMOTOR_Define($$){
	my ($hash, $def) = @_;
	my @args = split("[ \t]+", $def);
	my $menge = int(@args);

	if (int(@args) < 1) {
	return "Define: to less arguments. Usage:\n" .
		  "define <name> STELLMOTOR";
	}
	my $name = $args[0];
	$hash->{NOTIFYDEV} = "global";
	readingsSingleUpdate($hash, "state", "initialized",1);
	readingsSingleUpdate($hash, "state", ReadingsVal($name,"state","0"), 1);
	#set attr based on device type
	foreach(_stmAttribs("keys","")){
		if(AttrVal($name,$_,"missing") ne "missing"){
			#nothing, only set non-present attr
		}elsif(_stmAttribs("area",$_) eq "global"){
			CommandAttr(undef,$name." ".$_." "._stmAttribs("default",$_));
		}elsif($args[2] eq _stmAttribs("area",$_)){
			CommandAttr(undef,$name." ".$_." "._stmAttribs("default",$_));
			}
		}
	return;
	}
sub STELLMOTOR_Undefine($$){
  my($hash, $name) = @_;
  RemoveInternalTimer($hash);
  return;
}
###############################################################################################
###############################################################################################
sub STELLMOTOR_Set($@) {
	my ($hash, @args)	= @_;
	my $name = $hash->{NAME};

	if(AttrVal($name, "STMOutType", "dummy") eq "dummy"){
		return "Bitte Attribut STMOutType wÃ¤hlen!";
	}
	my $moveTarget = $args[1];
	if($moveTarget eq "?"){
		my $usage = "Invalid argument $moveTarget, choose one of calibrate:noArg reset:noArg stop:noArg position";
		return $usage;	
	}
	
	Log3 $name, 4, "STELLMOTOR $name #### SET ####";  
	Log3 $name, 4, "STELLMOTOR $name args 0: $args[0]";  
	Log3 $name, 4, "STELLMOTOR $name args 1: $args[1]";  
	Log3 $name, 4, "STELLMOTOR $name args 2: $args[2]";  
	if($moveTarget eq "calibrate"){STELLMOTOR_Calibrate($hash);return;}
	my $p_target;
	my $t_target;
	my $t_lastdiff = ReadingsVal($name,'t_lastdiff',0);
	my $t_actual = ReadingsVal($name, "t_actual", 0);
	my $p_actual = ReadingsVal($name, "p_actual", 0);
	my $t_move;
	my $t_stop;
	my $now = gettimeofday();
	my $STMtimeTolerance = AttrVal($name, "STMtimeTolerance", 0.001);
	my $STMlastDiffMax = AttrVal($name, "STMlastDiffMax", 1); ## lets get lastDiffMax
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	my $status = ReadingsVal($name,'status',0);
	my $locked = ReadingsVal($name,"locked",0);	
	
	if (IsDisabled($name)) {
		readingsSingleUpdate($hash, "status", "disabled", 1); 
		Log3 $name, 4, "STELLMOTOR $name device is disabled";  
		$moveTarget = "?"; #sorge dafÃ¼r, dass kein set ausgefÃ¼hrt wird.
	}
	if($moveTarget eq "stop"){
		STELLMOTOR_ImmediateStop($hash);
		Log3($name, 4, "STELLMOTOR $name User submitted Stop Request");
		return "Feature deactivated";
	}elsif($moveTarget eq "reset"){
		readingsBeginUpdate($hash);
		foreach(("state","t_target","p_target","t_actual","p_actual","t_lastStart","t_lastdiff","t_move","t_now","t_pertic","t_stop","t_stopHR","locked","command_queue","DoResetAtStop","t_lastDuration")){
			readingsBulkUpdate($hash, $_ , 0);		
			}
			readingsBulkUpdate($hash, "status", "reset");
		readingsEndUpdate($hash, 1);
		$hash->{helper}{savepactualduringtherun} = 0;
		$hash->{helper}{savetactualduringtherun} = 0;
		return;
	}elsif($moveTarget eq "position"){
		if(length($args[2]) && $args[2] =~ /^\d+$/ && $args[2] >= 0 && $args[2] <= $STMmaxTics){
			if($locked){
				#device is locked, do nothing
				Log3($name, 4, "STELLMOTOR $name Device is locked, try again later. Your command is discarded");
				return "Device is locked, try again later. Your command is discarded."
			} else{
				readingsSingleUpdate($hash, "status", "order accepted", 1); 
				readingsSingleUpdate($hash, "locked", 1, 1); 
			}
			if($args[2] > $STMmaxTics-1){
				readingsSingleUpdate($hash, "p_target", $STMmaxTics, 1);
				readingsSingleUpdate($hash, "t_target", $STMmaxDriveSeconds, 1);
				STELLMOTOR_commandSend($hash,"R");
				Log3($name, 0, "STELLMOTOR $name calibrating to $STMmaxTics");
				return "calibrating to $STMmaxTics";

			}elsif($args[2] < 1){
				STELLMOTOR_commandSend($hash,"L");
				readingsSingleUpdate($hash, "p_target", 0, 1);
				readingsSingleUpdate($hash, "t_target", 0, 1);
				Log3($name, 0, "STELLMOTOR $name calibrating to 0");
				return "calibrating to 0";

			}else{
			$p_target = $args[2];	## just save the target Position
			readingsSingleUpdate($hash, "p_target", $p_target, 1);
			$t_target = $args[2]*$STMmaxDriveSeconds/$STMmaxTics; ## here we have the wanted position in seconds
			readingsSingleUpdate($hash, "t_target", $t_target, 1);
			readingsSingleUpdate($hash, "t_pertic", $STMmaxDriveSeconds/$STMmaxTics, 1);
			}
		}else {
			return "Value must be between 0 and \$STMmaxTics ($STMmaxTics)";
		}
	}else{
		## Diese Zeile ist besonders wichtig, da aus ihr die Set-befehle abgeleitet werden... 
		Log3 $name, 4, "STELLMOTOR $name Irgendein anderer dÃ¤mlicher Fehler ist aufgetreten. Line:". __LINE__;  
		return;
	}
	# the move time is the target time plus the lastdiff minus the actual time 


	$t_move = $t_target+$t_lastdiff-$t_actual;

	Log3 $name, 4, "STELLMOTOR $name pactual: $p_actual";  
	Log3 $name, 4, "STELLMOTOR $name tactual: $t_actual";  
	Log3 $name, 4, "STELLMOTOR $name tlastdiff: $t_lastdiff";  
	Log3 $name, 4, "STELLMOTOR $name ttarget: $t_target";  
	Log3 $name, 4, "STELLMOTOR $name tmove: $t_move";  

	readingsSingleUpdate($hash, "t_move", $t_move, 1); 
	readingsSingleUpdate($hash, "t_lastmove", $t_move, 1); 
	if( ((abs($t_move) - $STMtimeTolerance) < $STMlastDiffMax  )){
		readingsSingleUpdate($hash, "status", "Abbruch, t_move < STMlastDiffMax", 1);
		readingsSingleUpdate($hash, "locked", 0, 1); 
		Log3 $name, 4, "STELLMOTOR $name tmove: $t_move < lastdiffmax $STMlastDiffMax";  
		return;
		}
	
	readingsSingleUpdate($hash, "status", "running", 1); 
	my $directionRL = $t_move > 0 ? "R":"L";
	Log3($name, 4, "STELLMOTOR $name RL: $directionRL");
	
	readingsSingleUpdate($hash, "t_lastStart", $now, 1); #set the actual drive starttime
	Log3($name, 4, "STELLMOTOR $name tlaststart(now): $now");
	
	
	## make startTime Human-Readable
	my $timestring = strftime "%Y-%m-%d %T",localtime($now);
	readingsSingleUpdate($hash, "t_lastStartHR", $timestring, 1); #set the end time of the move
	
	
	readingsSingleUpdate($hash, "t_lastDuration", $t_move, 1); ## set the run time of the move, just informational for the User
	Log3($name, 4, "STELLMOTOR $name tlastduration(t_move): $t_move");
	
	$t_stop = $now+abs($t_move);
	Log3($name, 4, "STELLMOTOR $name tstop $t_stop");
	
	
	readingsSingleUpdate($hash, "t_stop", ($t_stop), 1); #set the end time of the move
	## make StopTime Human-Readable
	my $timestring = strftime "%Y-%m-%d %T",localtime($t_stop);
	readingsSingleUpdate($hash, "t_stopHR", $timestring, 1); #set the end time of the move
	if($t_actual > 0 && $t_actual < $STMmaxDriveSeconds){
	$hash->{helper}{savetactualduringtherun} = $t_actual;
		Log3($name, 4, "STELLMOTOR $name just saved t_actual: $t_actual");
	}

	if($p_actual > 0 && $p_actual < $STMmaxTics){
	$hash->{helper}{savepactualduringtherun} = $p_actual;
		Log3($name, 4, "STELLMOTOR $name just saved p_actual: $p_actual");
	}

	Log3($name, 4, "STELLMOTOR $name t_saved_actual: $hash->{helper}{savetactualduringtherun}");
	Log3($name, 4, "STELLMOTOR $name t_actual: $t_actual");
	Log3($name, 4, "STELLMOTOR $name p_saved_actual: $hash->{helper}{savepactualduringtherun}");
	Log3($name, 4, "STELLMOTOR $name p_actual: $p_actual");
	STELLMOTOR_commandSend($hash,$directionRL);
	return;
	}

#############################################################################################
#############################################################################################	
sub STELLMOTOR_ImmediateStop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	return "no userstop permitted";	

	if(ReadingsVal($name,'locked', 1)==0){
		return; #no move in progress, nothing to stop
	}
	my $p_target = ReadingsVal($name,'p_target', 0);
	my $t_target = ReadingsVal($name,'t_target', 0);
	my $t_lastdiff = ReadingsVal($name,'t_lastdiff', 0);
	my $t_lastStart = ReadingsVal($name,'t_lastStart', 0);
	my $t_actual = $hash->{helper}{savetactualduringtherun};
	my $p_actual = $hash->{helper}{savepactualduringtherun};
	my $t_move = ReadingsVal($name,"t_move", 0);
	my $t_stop = ReadingsVal($name,"t_stop", 0);
	my $now = gettimeofday();
	my $STMtimeTolerance = AttrVal($name, "STMtimeTolerance", 0.001);
	my $STMlastDiffMax = AttrVal($name, "STMlastDiffMax", 1); ## lets get lastDiffMax
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	my $STMpollInterval = AttrVal($name, "STMpollInterval", 0.1);
	my $secPerTic = $STMmaxDriveSeconds / $STMmaxTics;  #now we have the time in seconds for 1 tic
	my $lastGuiState = ReadingsVal($name,'state', 1);
	Log3($name, 3, "STELLMOTOR $name ImmediateStop Problem: lastGuiState:$lastGuiState please report this error L.".__LINE__);
	
	if(!(ReadingsVal($name,'state', "e")=~/^\d+$/)){
		Log3($name, 3, "STELLMOTOR $name ImmediateStop Problem: lastGuiState:$lastGuiState please report this error L.".__LINE__);
		readingsSingleUpdate($hash, "state", "1", 1); #debug stuff
		$lastGuiState = 1;
		Log3($name, 3, "STELLMOTOR $name ImmediateStop Problem: state ist jetzt 1. L.".__LINE__);
		}
	#get direction: +/- position=desired state=last
	my $directionInProgress =0; #default positive 1=right
	if($lastGuiState > $p_actual){
		$directionInProgress=-1; #left move in progress
	}elsif($lastGuiState < $p_actual){ #right move in progress
		$directionInProgress =1; #default positive 1=right
	}else{
		return "error direction. Line:".__LINE__
	}
	#calc now -> tics-per-sec -> actual pos
	my $progressedTime = $now-$t_lastStart;
	my $progressedTics = $progressedTime/$secPerTic;
	$progressedTics=sprintf("%.0f",$progressedTics);
	#new target = state + (dir 1/-1)*(already progressed tics +1) #round up/down based on direction
	my $newTarget = $lastGuiState+(($progressedTics+1)*$directionInProgress);
	#update reading: position
	#recalc and set new stopTime
	my $newStopTime = ReadingsVal($name,'t_lastStart', 1)+(($progressedTics+1)*$secPerTic);
	#readingsSingleUpdate($hash, "t_stop" , $newStopTime);
	#let STELLMOTOR_GetUpdate do the physical stop
	}
sub STELLMOTOR_Stop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	# send stop command to the Device
	STELLMOTOR_commandSend($hash,"S");
	Log3 $name, 4, "STELLMOTOR $name i bims, 1 stop";  
	my $p_target = ReadingsVal($name,'p_target', 0);
	my $t_target = ReadingsVal($name,'t_target', 0);
	my $t_lastdiff = ReadingsVal($name,'t_lastdiff', 0);
	my $t_lastStart = ReadingsVal($name,'t_lastStart', 0);
	my $t_actual = $hash->{helper}{savetactualduringtherun};
	my $p_actual = $hash->{helper}{savepactualduringtherun};
	my $t_move = ReadingsVal($name,"t_move", 0);
	my $t_stop = ReadingsVal($name,"t_stop", 0);
	my $now = gettimeofday();
	my $STMtimeTolerance = AttrVal($name, "STMtimeTolerance", 0.001);
	my $STMlastDiffMax = AttrVal($name, "STMlastDiffMax", 1); ## lets get lastDiffMax
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	my $STMpollInterval = AttrVal($name, "STMpollInterval", 0.1);
	my $secPerTic = $STMmaxDriveSeconds / $STMmaxTics;  #now we have the time in seconds for 1 tic
	# i still havn't understood the sense of this part
	my $lastGuiState = ReadingsVal($name,'state', 1);
	if(!($lastGuiState=~/^\d+$/)){
		Log3($name, 3, "STELLMOTOR $name Stop Problem: lastGuiState:$lastGuiState please report this error L.".__LINE__);
		$lastGuiState=1;
	}elsif($lastGuiState > $STMmaxTics){
		Log3($name, 3, "STELLMOTOR $name Stop Problem: lastGuiState:$lastGuiState too large! L.".__LINE__);
		$lastGuiState = $lastGuiState>0?1:-1;
	}

	# calculate some values	
	$t_lastdiff = ($t_stop-$now)*($t_target > $lastGuiState?1:-1);
	# just because i can ... 
	readingsSingleUpdate($hash,'t_now',$now,1);
	#recalculate the position and write recalculated value to reading
	$t_actual = $t_target - $t_lastdiff;
	#update position reading
	readingsSingleUpdate($hash,'t_actual',$t_actual,1); 
	#update the readings after stop and post-proc
	#store time diff for next cmd
	readingsSingleUpdate($hash, "t_lastdiff", $t_lastdiff, 1); 
	# calculate position in Tics
	$p_actual = $t_actual / $secPerTic;
	readingsSingleUpdate($hash,'p_actual',$p_actual,1); 
	# set move-reading to 0
	readingsSingleUpdate($hash,'t_move',0 ,1); 
	
	#update state reading with "not so accurate" position
	readingsSingleUpdate($hash,'state',int($p_actual),1); 
	
	Log3($name, 4, "STELLMOTOR $name Stop Timing Call: stopTime:$t_stop now:$now queue_lastdiff:$t_lastdiff");
	## Remove Internal timer. As the Motor is not running anymore now, we don't need to watch excessively for changes until the next set-command
	RemoveInternalTimer($hash);
	readingsSingleUpdate($hash, "status", "idle", 1); 
	#unlock device
	readingsSingleUpdate($hash, "locked", 0, 1); 
	
	}
	###################################################################################
	###################################################################################
sub STELLMOTOR_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	Log3 $name, 4, "STELLMOTOR $name i bims, 1 getUpdate";  
	if (IsDisabled($name)) {
		Log3 $name, 4, "STELLMOTOR $name device is disabled";  
		RemoveInternalTimer($hash);
		readingsSingleUpdate($hash, "status", "disabled", 1); 
		readingsSingleUpdate($hash, "locked", 0, 1); 
		return;
		}
#	my $p_target = ReadingsVal($name,'p_target', 0);
#	my $t_target = ReadingsVal($name,'t_target', 0);
#	my $t_lastdiff = ReadingsVal($name,'t_lastdiff', 0);
	my $t_lastStart = ReadingsVal($name,'t_lastStart', 0);
	my $t_actual = ReadingsVal($name, "t_actual", 0);
	my $p_actual = ReadingsVal($name, "p_actual", 0);
#	my $t_move = ReadingsVal($name,"t_move", 0);
	my $t_stop = ReadingsVal($name,"t_stop", 0);
	my $now = gettimeofday();
	my $p_saved = $hash->{helper}{savepactualduringtherun};
	my $t_saved = $hash->{helper}{savetactualduringtherun};
#	my $STMtimeTolerance = AttrVal($name, "STMtimeTolerance", 0.001);
#	my $STMlastDiffMax = AttrVal($name, "STMlastDiffMax", 1); ## lets get lastDiffMax
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = AttrVal($name, "STMmaxTics", 100);
	my $STMpollInterval = AttrVal($name, "STMpollInterval", 0.1);
	Log3($name, 4, "STELLMOTOR $name tstop $t_stop");
	Log3($name, 4, "STELLMOTOR $name now $now");
	##Log3($name, 4, "STELLMOTOR $name ttarget $t_target");
	## If actual time is larger than stopTime+timeTolerance, stop motor
	if($now > $t_stop){
		STELLMOTOR_Stop($hash);
		Log3($name, 4, "STELLMOTOR $name tstop < now");
		Log3($name, 4, "STELLMOTOR $name tstop $t_stop");
		Log3($name, 4, "STELLMOTOR $name now $now");
		Log3($name, 4, "STELLMOTOR $name Stoppe Motor");
	}else{
		# Start internal Timer to get the updates
		# calc actual position/time of the motor and enter in p/t_actual
		#Die aktuelle Position ist wie folgt zu berechnen: 
		my $factor = ReadingsVal($name,'t_move', 1) >= 0?1:-1;
		Log3($name, 4, "STELLMOTOR $name factor $factor");
		####################
		#t_saved
		Log3($name, 4, "STELLMOTOR $name saved_t_before: $t_saved");
		if($t_saved > $STMmaxDriveSeconds){
			Log3($name, 4, "STELLMOTOR $name value wrong saved_t: $t_saved");
			$hash->{helper}{savetactualduringtherun} = $STMmaxDriveSeconds;
			readingsSingleUpdate($hash,"status","t_saved out of range. resettet. need_calibration",1);
			Log3($name, 4, "value t_saved:_".$t_saved."_ is missing or wrong");
				STELLMOTOR_Stop($hash);
				Log3($name, 4, "STELLMOTOR $name tstop < now");
				Log3($name, 4, "STELLMOTOR $name tstop $t_stop");
				Log3($name, 4, "STELLMOTOR $name now $now");
				Log3($name, 4, "STELLMOTOR $name Stoppe Motor");
		}
		if(!length($t_saved) || $t_saved < 0 || $t_saved eq ""){
			Log3($name, 4, "STELLMOTOR $name value missing or wrong saved_t: $t_saved");
			$hash->{helper}{savetactualduringtherun} = 0;
			readingsSingleUpdate($hash,"status","t_saved out of range. resettet. stopped need_calibration",1);
			Log3($name, 4, "value t_saved:_".$t_saved."_ is missing or wrong");
		}
		Log3($name, 4, "STELLMOTOR $name saved_t_after: $t_saved");
		#...............................................................................
		# t_actual
		Log3($name, 4, "STELLMOTOR $name actual_t_before: $t_actual");
		my $t_actual = $t_saved+(($now-$t_lastStart)*$factor);
		
		if($t_actual > $STMmaxDriveSeconds){
			Log3($name, 4, "STELLMOTOR $name value missing or wrong t_actual: $t_actual");
			$t_actual = $STMmaxDriveSeconds;
			readingsSingleUpdate($hash,"status","t_saved out of range. resettet. need_calibration",1);
			Log3($name, 4, "value t_actual:_".$t_actual."_ is missing or wrong");
				STELLMOTOR_Stop($hash);
				Log3($name, 4, "STELLMOTOR $name tstop < now");
				Log3($name, 4, "STELLMOTOR $name tstop $t_stop");
				Log3($name, 4, "STELLMOTOR $name now $now");
				Log3($name, 4, "STELLMOTOR $name Stoppe Motor");
			Log3($name, 4, "value t_actual:_".$t_actual."_ is missing or wrong");
		}	
		if(!length($t_actual) || $t_actual < 0 || $t_actual eq ""){
			Log3($name, 4, "STELLMOTOR $name value missing or wrong t_actual: $t_actual");
			$t_actual = 0;
			readingsSingleUpdate($hash,"status","t_actual out of range. resettet. need_calibration",1);
			Log3($name, 4, "value t_actual:_".$t_actual."_ is missing or wrong");
		}
		Log3($name, 4, "STELLMOTOR $name readingsUpdate actual_t_recalc: $t_actual");
		#_______________________________________________________
		readingsSingleUpdate($hash,"t_actual",$t_actual,1);

		###################
		#p_saved
		##Log3($name, 4, "STELLMOTOR $name saved_p_before: $p_saved");
		##if(!length($p_saved) || $p_saved < 0 || $p_saved > $STMmaxTics || $p_saved eq ""){
			##Log3($name, 4, "STELLMOTOR $name value missing or wrong saved_p: $p_saved");
			##$hash->{helper}{savepactualduringtherun} = $STMmaxTics;
			##	readingsSingleUpdate($hash,"status","p_saved out of range. resettet. need_calibration",1);
			##	Log3($name, 4, "value p_saved:_".$p_saved."_ is missing or wrong");
			##}
		##Log3($name, 4, "STELLMOTOR $name saved_p_after: $p_saved");
		#...............................................................................
		#p_actual
		##Log3($name, 4, "STELLMOTOR $name actual_p_before: $p_actual");
		##if(!length($p_actual) || $p_actual < 0 || $p_actual > $STMmaxTics || $p_actual eq ""){
			##Log3($name, 4, "STELLMOTOR $name value missing or wrong p_actual: $p_actual");
			##$p_actual = $STMmaxTics;
			##readingsSingleUpdate($hash,"status","p_actual out of range. resettet. need_calibration",1);
			##Log3($name, 4, "value p_actual:_".$p_actual."_ is missing or wrong");
			##}
		my $p_actual = $t_actual*(AttrVal($name,"STMmaxTics",1)/AttrVal($name,"STMmaxDriveSeconds",1));
		# no need to check for values smaller then 0 because its already done above
		Log3($name, 4, "STELLMOTOR $name readingsUpdate actual_p: $p_actual");
		#_______________________________________________________
		readingsSingleUpdate($hash,"p_actual",$p_actual,1);
		
		###############
		#t_stop
		Log3($name, 4, "STELLMOTOR $name t_stop_before: $t_stop");
		if(!length($t_stop) || $t_stop < 0 || $t_stop > $now+$STMmaxDriveSeconds || $t_stop eq ""){
			Log3($name, 4, "STELLMOTOR $name value missing or wrong t_stop: $t_stop");
			#$t_stop = $now;
			readingsSingleUpdate($hash,"t_stop",$now,1);
			readingsSingleUpdate($hash,"t_stopHR","stop-error",1);
			# no need to return as this is the fastest way to stop the Motor
		}
		Log3($name, 4, "STELLMOTOR $name t_stop_after: $t_stop");
		###############

		Log3($name, 4, "STELLMOTOR $name now $now");
		Log3($name, 4, "STELLMOTOR $name laststart $t_lastStart");
		
		
		# at least, start a timer
		InternalTimer($now + ($STMpollInterval), "STELLMOTOR_GetUpdate", $hash, 0);
		Log3($name, 4, "STELLMOTOR $name starte internal timer");
	}

	return;
	}
sub STELLMOTOR_Get($@){
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	my $get = $a[1];
	# Warum werden denn Readings geholt? 
	my @stmgets = (keys(%{$hash->{READINGS}}));
	$get="?" if(!_stm_in_array($get,(@stmgets,"attrHelp","readingsHelp","stmWwiki")));
	my $usage = "Unknown argument $get, choose one of";
	foreach(@stmgets){
		$usage.=" ".$_.":noArg";
		}
	$usage.=" attrHelp:";
	my($first)=0;
	foreach(_stmAttribs("keys","")){
		if($first){
			$usage.=$_;
			$first=0;
		}else{
			$usage.=",".$_;
			}
		}
	$usage.=" readingsHelp:";
	foreach(_stmRdings("keys","")){
		$usage.=$_.",";
		}
	$usage.=" stmWwiki:get,set,readings,attr";
	#check what has been requested?
	if($get eq "attrHelp"){return _stmAttribs("help",$a[2]);}
	if($get eq "readingsHelp"){return _stmRdings("help",$a[2]);}
	if($get eq "stmWwiki"){
		my $bereich = $a[2];
		#bereich "get" "set" "readings" "attr"
		my $wret;
		if($bereich eq "get"){
			$wret=STELLMOTOR_Get($hash,$name,"?");
			$wret=~s/Unknown argument \?, choose one of//g;
			$wret=~s/\s+/\n* /g;
 			$wret=~s/:noArg//g;
			$wret=~s/:/: /g;
			return "extracted usage of get command:\n\n".$wret
		}elsif($bereich eq "set"){
			##$wret=STELLMOTOR_Set($hash,$name,"?");
			$wret=~s/Unknown argument \?, choose one of//g;
			$wret=~s/\s+/\n* /g;
			$wret=~s/:noArg//g;
			$wret=~s/:/: /g;
			return "extracted usage of set command:\n\n".$wret;
		}elsif($bereich eq "readings"){
			$wret="\n== Readings ==\nAlle Readings sind auch in fhem durch das kommando get readingsHelp <varname> erklÃ¤rt, fÃ¼r's \"".
			"schnelle nachschauen zwischendurch\".\n\n{| class=\"wikitable sortable\"\n|-\n! Reading !! (Typ) Default !! Beschreibung\n|-\n";
			foreach(_stmRdings("keys","")){
				$wret.="| ".	$_."|| ("._stmRdings("type",$_).") "._stmRdings("default",$_)." || "._stmRdings("description",$_)."\n|-\n";
				}
			$wret.="\n|}\n\n";
		}elsif($bereich eq "attr"){
			$wret="\n== Attributes ==\nAlle Attributes sind auch in fhem durch das kommando get attrHelp <varname> erklÃ¤rt, fÃ¼r's \"".
			"schnelle nachschauen zwischendurch\".\n\n{| class=\"wikitable sortable\"\n|-\n! Attribute !! (Typ) Default !! Beschreibung\n|-\n";
			foreach(_stmAttribs("keys","")){
				$wret.="| ".	$_."|| ("._stmAttribs("type",$_).") "._stmAttribs("default",$_)." || "._stmAttribs("description",$_)."\n|-\n";
				}
			$wret.="\n|}\n\n";
		}else{
			return "get Error in Line ".__LINE__;
			}
		return $wret;
		}
	return $usage if $get eq "?";
	my $ret = $get.": ".ReadingsVal($name,$get, "Unknown");
	return $ret;
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
	#validate special attr STMpollInterval
	if ($attrName eq "STMpollInterval") {
		if (!defined $attrVal) {
			RemoveInternalTimer($hash);    
			Log3($name, 4, "STELLMOTOR $name attr [$attrName] deleted");
			CommandDeleteAttr(undef, "$name STMpollInterval");
		} elsif ($attrVal eq "off" || ( $attrVal >= 0.01 and $attrVal <= 600 ) ) {
			Log3($name, 4, "STELLMOTOR $name attribute-value [$attrName] = $attrVal changed");
			##STELLMOTOR_GetUpdate($hash);
		} else {
			RemoveInternalTimer($hash);
			Log3($name, 3, "STELLMOTOR $name attribute-value [$attrName] = $attrVal wrong, use seconds >0.01 as float (max 600)");
			}
	#fetch all remaining attribs and just check if data type matches
	} elsif (_stm_in_array($attrName,_stmAttribs("keys"," "))) {
		if (!defined $attrVal){
			CommandDeleteAttr(undef, "$name $attrName");
		} elsif (_stmvalidateAttr($attrName, $attrVal) ) {
			Log3($name, 4, "STELLMOTOR $name attribute-value [$attrName] = $attrVal changed");
		} else {
			CommandDeleteAttr(undef, "$name attrName");
			}
		}
	return;
	}
sub STELLMOTOR_Calibrate($@){
#drive to left (or right if attr) for maximum time and call "set reset"
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	return "function calibrate deactivated";
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $STMmaxTics = ReadingsVal($name,'STMmaxTics', "100");
	
	#lock module for other commands
	readingsSingleUpdate($hash, "locked", 1, 1);
	
	#set the actual drive starttime
	readingsSingleUpdate($hash, "t_lastStart", gettimeofday(), 1); 
	
	#calculate the endtime of the move
	$hash->{helper}{t_stop} = gettimeofday() + $STMmaxDriveSeconds + 5;
	
	#update the end time of the move	
	readingsSingleUpdate($hash, "t_stop", ($hash->{helper}{t_stop}), 1); 
	
	my $timestring = strftime "%Y-%m-%d %T",localtime($hash->{helper}{t_stop});
	readingsSingleUpdate($hash, "t_stopHR", $timestring, 1); 
	#set the calibration info	
	readingsSingleUpdate($hash, "DoResetAtStop", "afterCalibrate", 1); 
	STELLMOTOR_commandSend($hash,AttrVal($name,"STMcalibrateDirection","L"));
	return;
	}

sub _stm_in_array($@){
	my ($search_for,@arr) = @_;
	foreach(@arr){
		return 1 if $_ eq $search_for;
		}
	return 0;
	}
sub _stmvalidateAttr($@){
	#usage: _stmvalidateAttr($attrName, $attrVal)
	my($attrName, $attrVal)=@_;
	#validate special attr and refuse
	if(($attrName eq "STMmaxTics") and ($attrVal<1)){
		return 0;
	}elsif(($attrName eq "STMrlType") and (($attrVal ne "wechsel") and ($attrVal ne "einzel"))){
		return 0;
		}
	my $attrType = _stmAttribs("type",$attrName);
	if($attrType eq "int"){
		return 1 if $attrVal=~/^[-+]?\d+$/;
	}elsif($attrType eq "float"){
		return 1 if $attrVal=~/^[-+]?\d+\.?\d*$/;
	}elsif($attrType eq "string"){
		return 1 if length($attrVal);
	}else{
		return 0;
		}
	}
sub _stmRdings($@){
	#usage: _stmRdings("help","stmVarName")
	# "keys" || "default" || "type" || "help"  ,<keyname>
	my($type,$reqKey)=@_;
	my %rdings = (
"state"=>[("active","string","aktuelle position oder fehlermeldung","global","active,error,initialized,0..100")],
"command_queue"=>[("0","int","befehl in der warteschleife","global","0..100")],
"t_actual"=>[("1","int","aktuelle desired position in sekunden","global","float")],
"p_actual"=>[("1","int","aktuelle desired position in tics","global","float")],
"t_lastdiff"=>[("0","float","letzte ticsdifferenz","global","float")],
"p_target"=>[("0","float","Zielstellung Tics","global","float")],
"t_target"=>[("0","float","Zielstellung Time","global","float")],
"locked"=>[("0","int","1 wÃ¤hrend motor gerade lÃ¤uft","global","0,1")],
"t_lastStart"=>[("0","float","zeitstempel letzter start des motors","global","float")],
"t_lastDuration"=>[("0","float","dauer letzte fahrt des motors","global","float")],
"t_stop"=>[("0","float","zeitstempel nÃ¤chster stop des motors","global","float")],
"t_now"=>[("0","float","zeitstempel now","global","float")],
"t_pertic"=>[("0","float","dauer, bis 1 tic gefahren wurde","global","float")],
"t_move"=>[("0","float","geplante Dauer der Fahrt","global","float")],
"DoResetAtStop"=>[("afterCalibrate","string","temporÃ¤rwert nur wÃ¤hrend kalibrierungsphase","global","'',afterCalibrate")],
	);
	if($type eq "keys"){
		return keys(%rdings);
	}elsif($type eq "default"){
		return $rdings{$reqKey}[0];
	}elsif($type eq "type"){
		return $rdings{$reqKey}[1];
	}elsif($type eq "description"){
		return $rdings{$reqKey}[2];
	}elsif($type eq "area"){
		return $rdings{$reqKey}[3];
	}elsif($type eq "listval"){
		return $rdings{$reqKey}[4];
	}elsif($type eq "help"){
		return "readingsHelp for ".$reqKey.":\n default:".$rdings{$reqKey}[0]." type:".$rdings{$reqKey}[1]." listval:".$rdings{$reqKey}[4]
			." \ndescription:".$rdings{$reqKey}[2];
	}else{
		return "_ rdings?";
		}
	}
sub _stmAttribs($@){
	#usage: _stmAttribs("type","stmVarName")
	# "keys" || "default" || "type" || "help"  ,<keyname>
	my($type,$reqKey)=@_;
	my %attribs = (
"STMrlType"=>[("einzel","string","je nach schaltplan, wechsel=start+RL-relais, einzel=R-relais+L-relais","global","wechsel,einzel")],
"STMOutType"=>[("dummy","string","je nach Hardware","global","FhemDev,PiFace,Gpio")],
"STMinvertOut"=>[("0","int","setzen fÃ¼r devices die 0 fÃ¼r start und 1 fÃ¼r stop erwarten","global","0,1")],
"STMmapOffCmd"=>[("0","string","string der im device-command anstatt '0' verwendet wird fÃ¼r stop","global","all")],
"STMmapOnCmd"=>[("0","string","string der im device-command anstatt '1' verwendet wird fÃ¼r start","global","all")],
"STMgpioPortRL"=>[("5","int","piface port oder gpio port fÃ¼r RL oder R relais (bei RL ist 1=R)","PiFaceGpio","0:31")],
"STMgpioPortSTART"=>[("4","int","piface port oder gpio port fÃ¼r START (oder L relais bei 'einzel')","PiFaceGpio","0:31")],
"STMsysCmdRL"=>[("0","string","freies command das fÃ¼r RL an die shell Ã¼bergeben wird","SysCmd","all")],
"STMsysCmdSTART"=>[("0","string","freies command das fÃ¼r START an die shell Ã¼bergeben wird","SysCmd","all")],
"STMfhemDevRL"=>[("RelaisRL","string","fhem device name fÃ¼r RL (oder R) aktor","FhemDev","all")],
"STMfhemDevSTART"=>[("RelaisSTART","string","fhem device name fÃ¼r START (oder L) aktor","FhemDev","all")],
"STMmaxDriveSeconds"=>[("107","int","gestoppte Zeit in Sekunden, die der Motor fÃ¼r die Fahrt von 0 bis 100 Prozent braucht","global","all")],
"STMmaxTics"=>[("100","int","Mischerstellung - bei Prozentangaben (PID20) 100, bei Winkelangaben anzupassen","global","1:360")],
"STMtimeTolerance"=>[("0.01","float","stop-time differenzen kleiner als dieser wert werden ignoriert","global","0.01,0.02,0.03,0.04,0.05,0.06,0.07,0.08,0.09,0.1")],
"STMresetOtherDeviceAtCalibrate"=>[("0","string","zusÃ¤tzliches fhem device das am ende der kalibrierung 'set ** reset' gesendet bekommt","global","all")],
"STMpollInterval"=>[("0.1","float","Zeitintervall nach dem FHEM prÃ¼ft, ob die interne Stoppzeit erreicht wurde. Hier sollte mÃ¶glichst kleiner Wert aein, nur erhÃ¶hen falls FHEM zu langsam lÃ¤uft","global","all")],
"STMcalibrateDirection"=>[("L","string","auf R wird die kalibrierung nach rechts gefahren, default=links","global","L,R")],
"STMlastDiffMax"=>[("1","float","ist die stoppzeit weiter als dieser wert vom Soll entfernt, wird sofort neuer drive gestartet","global","all")],
"STMdebugToLog3"=>[("0","int","jedes gesendete command ins Log schreiben","global","0,1")],
	);
	if($type eq "keys"){
		return keys(%attribs);
	}elsif($type eq "default"){
		return $attribs{$reqKey}[0];
	}elsif($type eq "type"){
		return $attribs{$reqKey}[1];
	}elsif($type eq "description"){
		return $attribs{$reqKey}[2];
	}elsif($type eq "area"){
		return $attribs{$reqKey}[3];
	}elsif($type eq "listval"){
		return $attribs{$reqKey}[4];
	}elsif($type eq "help"){
		return "attrHelp for ".$reqKey.":\n default:".$attribs{$reqKey}[0]." type:".$attribs{$reqKey}[1]." area:".$attribs{$reqKey}[3]
			." \nlistval:".$attribs{$reqKey}[4]
			." \ndescription:".$attribs{$reqKey}[2];
	}else{
		return "_ attribs?";
		}
	}

1;
>>>>>>> f659910282c1caccd95b22f8efaef349a9254d72
