# $Id: 39_STELLMOTOR.pm 3101 2018-12-18 11:51:00Z Stephan Augustin $
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

	Log3 $name, 4, "STELLMOTOR $name i bims, 1 set";  
	Log3 $name, 4, "STELLMOTOR $name args 0: $args[0]";  
	Log3 $name, 4, "STELLMOTOR $name args 1: $args[1]";  
	Log3 $name, 4, "STELLMOTOR $name args 2: $args[2]";  
	if(AttrVal($name, "STMOutType", "dummy") eq "dummy"){
		return "Bitte Attribut STMOutType wählen!";
	}
#	if($args[1] eq "?"){
#		Log3 $name, 4, "STELLMOTOR $name Programm wird abgebrochen. Line:". __LINE__; 
#	       return "ungueltiger Parameter";	
#	}
	my $moveTarget = $args[1];
	
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
	
	Log3 $name, 4, "STELLMOTOR $name moveTarget $moveTarget";  
	if (IsDisabled($name)) {
		readingsSingleUpdate($hash, "status", "disabled", 1); 
		Log3 $name, 4, "STELLMOTOR $name device is disabled";  
		$moveTarget = "?"; #sorge dafür, dass kein set ausgeführt wird.
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
		
		return;
	}elsif($moveTarget eq "position"){
		if(length($args[2]) && $args[2] =~ /^\d+$/ && $args[2] >= 0 && $args[2] <= $STMmaxTics){
			$p_target = $args[2];	## just save the target Position
			readingsSingleUpdate($hash, "p_target", $p_target, 1);
			$t_target = $args[2]*$STMmaxDriveSeconds/$STMmaxTics; ## here we have the wanted position in seconds
			readingsSingleUpdate($hash, "t_target", $t_target, 1);
			readingsSingleUpdate($hash, "t_pertic", $STMmaxDriveSeconds/$STMmaxTics, 1);
		}else {
			return "Value must be between 0 and \$STMmaxTics ($STMmaxTics)";
		}
	}else{
		## Diese Zeile ist besonders wichtig, da aus ihr die Set-befehle abgeleitet werden... 
		my $usage = "Invalid argument $moveTarget, choose one of calibrate:noArg reset:noArg stop:noArg position";
		Log3 $name, 4, "STELLMOTOR $name Programm wird abgebrochen. Line:". __LINE__;  
		return $usage;
		}
	my $locked = ReadingsVal($name,'locked',0);
	if ($locked) {
		Log3 $name, 4, "STELLMOTOR $name Device is locked";  
		return;
	}
	# the move time is the target time plus the lastdiff minus the actual time 


	$t_move = $t_target+$t_lastdiff-$t_actual;
	Log3 $name, 4, "STELLMOTOR $name tactual: $t_actual";  
	Log3 $name, 4, "STELLMOTOR $name tlastdiff: $t_lastdiff";  
	Log3 $name, 4, "STELLMOTOR $name ttarget: $t_target";  
	Log3 $name, 4, "STELLMOTOR $name tmove: $t_move";  

	readingsSingleUpdate($hash, "t_move", $t_move, 1); 
	if( ((abs($t_move) - $STMtimeTolerance) < $STMlastDiffMax  )){## if t_move is smaller than  STMlastdiffMax queue command
		#readingsSingleUpdate($hash, "t_lastdiff", $hash->{helper}{t_move}, 1); 
		#$hash->{helper}{t_lastdiff} = $hash->{helper}{t_move};
		#$hash->{helper}{t_move} = 0;
		#readingsSingleUpdate($hash, "t_move", $hash->{helper}{t_move}, 1); 
		readingsSingleUpdate($hash, "status", "Abbruch, differenz < STMlastDiffMax", 1); 
		Log3 $name, 4, "STELLMOTOR $name tmove: $t_move < lastdiffmax $STMlastDiffMax";  
		return;
		}
	
	readingsSingleUpdate($hash, "status", "running", 1); 
	my $directionRL = $t_move > 0 ? "R":"L";
	Log3($name, 4, "STELLMOTOR $name Set Target: $t_target");
	Log3($name, 4, "STELLMOTOR $name Cmd: $t_move");
	Log3($name, 4, "STELLMOTOR $name RL: $directionRL");
	
	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	readingsSingleUpdate($hash, "t_lastStart", $now, 1); #set the actual drive starttime
	Log3($name, 4, "STELLMOTOR $name tlaststart: $now");
	
	
	## make startTime Human-Readable
	my $timestring = strftime "%Y-%m-%d %T",localtime($now);
	readingsSingleUpdate($hash, "t_lastStartHR", $timestring, 1); #set the end time of the move
	
	
	readingsSingleUpdate($hash, "t_lastDuration", $t_move, 1); ## set the run time of the move, just informational for the User
	Log3($name, 4, "STELLMOTOR $name tlastduration: $t_move");
	
	$t_stop = $now+abs($t_move);
	Log3($name, 4, "STELLMOTOR $name tstop $t_stop");
	
	
	readingsSingleUpdate($hash, "t_stop", ($t_stop), 1); #set the end time of the move
	## make StopTime Human-Readable
	my $timestring = strftime "%Y-%m-%d %T",localtime($t_stop);
	readingsSingleUpdate($hash, "t_stopHR", $timestring, 1); #set the end time of the move
	if($t_actual > 0 && $t_actual < $STMmaxDriveSeconds){
	$hash->{helper}{savetactualduringtherun} = $t_actual;
	}

	if($p_actual > 0 && $p_actual < $STMmaxTics){
	$hash->{helper}{savepactualduringtherun} = $p_actual;
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
	#unlock device
	readingsSingleUpdate($hash, "locked", 0, 1); 
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
		return;
		}
#	my $p_target = ReadingsVal($name,'p_target', 0);
#	my $t_target = ReadingsVal($name,'t_target', 0);
#	my $t_lastdiff = ReadingsVal($name,'t_lastdiff', 0);
	my $t_lastStart = ReadingsVal($name,'t_lastStart', 0);
#	my $t_actual = ReadingsVal($name, "t_actual", 0);
#	my $t_move = ReadingsVal($name,"t_move", 0);
	my $t_stop = ReadingsVal($name,"t_stop", 0);
	my $now = gettimeofday();
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
		InternalTimer($now + ($STMpollInterval), "STELLMOTOR_GetUpdate", $hash, 0);
		Log3($name, 4, "STELLMOTOR $name starte internal timer");
		# calc actual position/time of the motor and enter in p/t_actual
		#Die aktuelle Position ist wie folgt zu berechnen: 
		#$hash->{helper}{t_actual_old} = $t_actual;	
		#$now -$laststart -> aktuelle Laufzeit
		#readingsSingleUpdate($hash,"t_lastpos",$t_actual,0);
		my $factor = ReadingsVal($name,'t_move', 1) > 0?1:-1;
		Log3($name, 4, "STELLMOTOR $name factor $factor");
		
		if($hash->{helper}{savetactualduringtherun} < 0 || $hash->{helper}{savetactualduringtherun} > $STMmaxDriveSeconds){
			Log3($name, 4, "STELLMOTOR $name saved_t: $hash->{helper}{savetactualduringtherun}");
		}
		my $t_actual = $hash->{helper}{savetactualduringtherun}+(($now-$t_lastStart)*$factor);
		readingsSingleUpdate($hash,"t_actual",$t_actual,1);
		Log3($name, 4, "STELLMOTOR $name t_actual $t_actual");
		if($hash->{helper}{savepactualduringtherun} < 0 || $hash->{helper}{savepactualduringtherun} > $STMmaxTics){
			Log3($name, 4, "STELLMOTOR $name saved_p: $hash->{helper}{savepactualduringtherun}");
		}
			my $p_actual = $t_actual*(AttrVal($name,"STMmaxTics",1)/AttrVal($name,"STMmaxDriveSeconds",1));
		Log3($name, 4, "STELLMOTOR $name p_actual $p_actual");


		readingsSingleUpdate($hash,"p_actual",$p_actual,1);
		Log3($name, 4, "STELLMOTOR $name now $now");
		Log3($name, 4, "STELLMOTOR $name laststart $t_lastStart");
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
"locked"=>[("0","int","1 während motor gerade läuft","global","0,1")],
"t_lastStart"=>[("0","float","zeitstempel letzter start des motors","global","float")],
"t_lastDuration"=>[("0","float","dauer letzte fahrt des motors","global","float")],
"t_stop"=>[("0","float","zeitstempel nächster stop des motors","global","float")],
"t_now"=>[("0","float","zeitstempel now","global","float")],
"t_pertic"=>[("0","float","dauer, bis 1 tic gefahren wurde","global","float")],
"t_move"=>[("0","float","geplante Dauer der Fahrt","global","float")],
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
"STMrlType"=>[("einzel","string","je nach schaltplan, wechsel=start+RL-relais, einzel=R-relais+L-relais","global","wechsel,einzel")],
"STMOutType"=>[("dummy","string","je nach Hardware","global","FhemDev,PiFace,Gpio")],
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
