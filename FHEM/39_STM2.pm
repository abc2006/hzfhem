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

sub STM2_Define($$);
sub STM2_Undefine($$);
sub STM2_Set($@);
sub STM2_Get($@);
sub STM2_Notify(@);
sub STM2_Attr(@);
sub STM2_Calibrate($);

sub STM2_commandSend($$){
	#params: R | L | S
	my ($hash, $cmd)	= @_;
	my $name = $hash->{NAME};
	Log3 $name, 5, "STELLMOTOR $name commandSend cmd $cmd";  
	if($cmd eq "R"){ 
		CommandSet(undef,AttrVal($name,"STMdevL",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevR",0)." on");
		my $deviceL = AttrVal($name,"STMdevL",0)." off";
		my $deviceR = AttrVal($name,"STMdevR",0)." on";
		Log3 $name, 5, "STELLMOTOR $name devL $deviceL";  
		Log3 $name, 5, "STELLMOTOR $name devR $deviceR";  
		}
	if($cmd eq "L"){ 
		CommandSet(undef,AttrVal($name,"STMdevR",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevL",0)." on");
		my $deviceL = AttrVal($name,"STMdevL",0)." on";
		my $deviceR = AttrVal($name,"STMdevR",0)." off";
		Log3 $name, 5, "STELLMOTOR $name devR $deviceR";  
		Log3 $name, 5, "STELLMOTOR $name devL $deviceL";  
		}
	if($cmd eq "S"){ 
		CommandSet(undef,AttrVal($name,"STMdevR",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevL",0)." off");
		my $deviceL = AttrVal($name,"STMdevL",0)." off";
		my $deviceR = AttrVal($name,"STMdevR",0)." off";
		Log3 $name, 5, "STELLMOTOR $name devR $deviceR";  
		Log3 $name, 5, "STELLMOTOR $name devL $deviceL";  
		}
	return;
	}

sub STM2_Initialize($){
	my ($hash) = @_;
	$hash->{DefFn}		= "STM2_Define";
	$hash->{UndefFn}	= "STM2_Undefine";
	$hash->{SetFn}		= "STM2_Set";
	$hash->{GetFn}		= "STM2_Get";
	$hash->{NotifyFn}	= "STM2_Notify";
	$hash->{AttrFn}		= "STM2_Attr";
	$hash->{AttrList}	= "disable:0,1 STMmaxDriveSeconds STMdevL STMdevR STMlastDiffMax STMinterval ".$readingFnAttributes;
}

sub STM2_Define($$){
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
		## braucht man das hier ? 
##	InternalTimer(gettimeofday() + 120, "STM2_GetUpdate", $hash, 0);
return;
}
sub STM2_Undefine($$){
  my($hash, $name) = @_;
  RemoveInternalTimer($hash);
  return;
}

sub STM2_Set($@) {
	my ($hash, @args) = @_;
	my $name = $hash->{NAME};
	my $setOption = $args[1];
	my $now = gettimeofday();
	my $position_target = $args[2];
	my $STMinterval = $hash->{helper}{STMINTERVAL};
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $locked = ReadingsVal($name,'locked',0);
	if ($setOption eq "?"){
		return "Unknown argument ?, choose one of stop:noArg position reset:noArg";
	}
	if (IsDisabled($name)) {
		readingsSingleUpdate($hash, "state", "disabled_138", 0); #save requested value to queue and return
		Log3 $name, 4, "STELLMOTOR $name device is disabled";  
		return;
		}
	if(AttrVal($name,"STMdevR","") eq "" || AttrVal($name,"STMdevL","") eq "" || AttrVal($name,"STMmaxDriveSeconds","") eq "")
	{
		readingsSingleUpdate($hash, "state", "missing Attributes",1);
		return;
	}
	
	if($setOption eq "stop"){
		readingsSingleUpdate($hash,"stop_planned",$now,0);
		Log3($name, 4, "STELLMOTOR $name User submitted Stop Request");
		return;
	}elsif($setOption eq "reset"){
		STM2_commandSend($hash,"S");
		readingsBeginUpdate($hash);
		## weitere Readings hinzufügen?
		foreach("position_actual","position_target","start_actual","stop_planned","locked","diff"){
			readingsBulkUpdate($hash, $_ , 0);		
			}
		foreach("state"){
			readingsBulkUpdate($hash, $_ , "reset");		
			}
		readingsEndUpdate($hash, 1);
		Log3($name, 4, "$name SET: reset");
		return;
	}elsif($setOption eq "position" && $locked == 0){
		Log3($name, 4, "$name set_position_pre_check position_target: $position_target");
		my $var1 = length($position_target) ? "length match" : "no length match";
		my $var2 = $position_target =~ /^\d+$/ ? "regex match":"no regex match";
	      	my $var3 = $position_target >=0 ? "min match" : "no min match";	
	 	my $var4 = $position_target <= $STMmaxDriveSeconds ? "max match":"no max match";
		Log3($name, 5, "$name set_position_pre_check $var1 $var2 $var3 $var4");
	 	if(length($position_target) && $position_target =~ /^\d+$/ && $position_target >=0 && $position_target <= $STMmaxDriveSeconds){	
		readingsSingleUpdate($hash,"position_target",$position_target,1);
		Log3($name, 4, "$name set_position_post_check position_target: $position_target");
		}else{
		Log3($name, 1, "$name set_position_post_check check failed, value not accepted");
		return "Error, see logfile";
		}
	}elsif(ReadingsVal($name,"locked",1) == 1)
	{
		readingsSingleUpdate($hash, "state", "device locked",1);
		return;
	}	# Was wissen wir hier: Wir wissen die Zielposition, wo wir hin sollen. 
	#Um Herauszufinden, ob wir rechts oder links bewegen müssen, brauchen wir die aktuelle position
	my $position_actual = ReadingsVal($name, "position_actual",0);

Log3($name, 4, "$name Set: position_actual: $position_actual");
	Log3($name, 4, "$name Set: position_target: $position_target");
	if($position_target == 0 && $position_actual != 0){
		Log3($name, 4, "$name Set: starting calibration R");
		$hash->{helper}{calibrationSeconds} = abs($position_target-$position_actual)+10; 	
		$hash->{helper}{direction} = "R"; 
		Log3($name, 4, "$name calibrationSeconds $hash->{helper}{calibrationSeconds}");
		STM2_Calibrate($hash);
       		return;
       	}elsif($position_target == $STMmaxDriveSeconds && $position_actual != $STMmaxDriveSeconds){
		Log3($name, 4, "$name Set: starting calibration L");
		$hash->{helper}{calibrationSeconds} = abs($position_target-$position_actual)+10; 	
		$hash->{helper}{direction} = "L"; 
		Log3($name, 4, "$name calibrationSeconds $hash->{helper}{calibrationSeconds}");
		STM2_Calibrate($hash);
		return;
       	}
	if(abs($position_target-$position_actual) < $hash->{helper}{STMlastDiffMax}){
		Log3($name, 4, "$name Set: Differenz ist zu klein, keine Bewegung");
		readingsSingleUpdate($hash,"status", "Differenz zu klein",1);
		return;
	}
	## jetzt haben wir die alten positionen und die übrige Differenz. 
	#save the actual start time position	
	my $totalMove = $position_target - $position_actual;
	Log3($name, 4, "$name Set: totalMove: $totalMove");
	if($totalMove>0){
		$hash->{helper}{direction} = "L"; 
	}elsif($totalMove<0){
		$hash->{helper}{direction} = "R"; 
	}
	readingsSingleUpdate($hash, "direction", $hash->{helper}{direction} ,1);
	# jetzt wissen wir, in welche Richtung der Motor laufen soll.
	$totalMove=abs($totalMove); #be sure to have positive moveCmdTime value
	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	#jetzt wissen wir, bis wann der Motor laufen soll
	readingsSingleUpdate($hash, "stop_planned", ($now+$totalMove), 1); #set the end time of the move
	readingsSingleUpdate($hash, "start_actual", $now, 1); 
	readingsSingleUpdate($hash, "start_history", $now, 1); 
	
	##my $timestring = strftime "%Y-%m-%d %T",localtime($now + $tr_totalMove);
	##readingsSingleUpdate($hash,"ta_stopHR", $timestring,1);
	STM2_commandSend($hash,$hash->{helper}{direction});
	STM2_GetUpdate($hash);    

	return;
	}

sub STM2_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $now = gettimeofday();
	my $STMinterval = $hash->{helper}{STMINTERVAL};
	my $start_actual =  ReadingsVal($name,"start_actual", 0);
	readingsSingleUpdate($hash, "start_actual", $now, 1); 
	my $stop_planned = ReadingsVal($name,"stop_planned", 0);
	my $position_actual =  ReadingsVal($name,"position_actual", 0);
	if($stop_planned == 0){
		Log3($name, 4, "$name stop_planned: $stop_planned, stopzeit fehlerhaft!");
		return;
	}
	#readingsSingleUpdate($hash, "GetUpdate", $now, 1); 
	
	readingsSingleUpdate($hash, "status", "running",1);
	my $diff = $now - $start_actual; ## wie viele Sekunden läuft der Motor schon?  
	readingsSingleUpdate($hash, "diff", $diff, 1); 
				Log3($name, 4, "STM2 $name GetUpdate: diff: $diff");
				Log3($name, 4, "STM2 $name GetUpdate: now: $now");
				Log3($name, 4, "STM2 $name GetUpdate: ta_start: $start_actual");
				Log3($name, 4, "STM2 $name GetUpdate: position_actual_pre: $position_actual");
	if($hash->{helper}{direction} eq "L"){
		$position_actual += $diff;
	}elsif($hash->{helper}{direction} eq "R"){
		$position_actual -= $diff;
	}
	readingsSingleUpdate($hash, "position_actual", $position_actual,1);
	readingsSingleUpdate($hash, "state", int(10*$position_actual)/10,1);
	
				Log3($name, 4, "STM2 $name GetUpdate: diff: $diff");
				Log3($name, 4, "STM2 $name GetUpdate: position_actual_post: $position_actual");
	
	if(($stop_planned ne 0) and (($stop_planned-$now)<$STMinterval)){
		STM2_commandSend($hash,"S");
		Log3($name, 4, "$name getUpdate STOP");
		readingsSingleUpdate($hash, "status", "idle",1);
  		RemoveInternalTimer($hash);
		readingsSingleUpdate($hash, "locked", 0, 1); #lock module for other commands
		return;
	}
	
	InternalTimer($now + $STMinterval, "STM2_GetUpdate", $hash, 0);
	return;
	}

sub STM2_Get($@){
	my ($hash, @a) = @_;
	my $name = $hash->{NAME};
	##return "Unknown argument ?, choose one of stop:noArg position reset:noArg";
	}
sub STM2_Notify(@) {
  my ($hash, $dev) = @_;
  my $name = $hash->{NAME}; 
  if ($dev->{NAME} eq "global" && grep (m/^INITIALIZED$/,@{$dev->{CHANGED}})){
    Log3($name, 3, "STM2 $name initialized");
    STM2_GetUpdate($hash);    
  }
  return;
}
sub STM2_Attr(@) {
	my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};
	$hash->{helper}{STMINTERVAL} = AttrVal($name,"STMinterval",0.5);
	$hash->{helper}{STMlastDiffMax} = AttrVal($name,"STMlastDiffMax",0.5);
	return;
	}

sub STM2_Calibrate($){
#drive to left (or right if attr) for maximum time and call "set reset"
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $now = gettimeofday();
	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	my $timestring = strftime "%Y-%m-%d %T",localtime($now);
	Log3($name, 4, "$name CALIBRATION");
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);

	readingsSingleUpdate($hash, "state", "calibrating", 1); 
	readingsSingleUpdate($hash, "status", "calibrating", 1);

	Log3($name, 4, "$name direction $hash->{helper}{direction}");
	if($hash->{helper}{direction} eq "R"){	
		Log3($name, 4, "$name CALIBRATION R");
		readingsSingleUpdate($hash, "state", "calibrating to 0", 1); 
		STM2_commandSend($hash,"R");
		InternalTimer($now + $hash->{helper}{calibrationSeconds}, "STM2_Calibrate", $hash, 0);
		$hash->{helper}{direction} = "RS";
	}elsif($hash->{helper}{direction} eq "L"){	
		Log3($name, 4, "$name CALIBRATION L");
		readingsSingleUpdate($hash, "state", "calibrating to $STMmaxDriveSeconds", 1); 
		STM2_commandSend($hash,"L");
		InternalTimer($now + $hash->{helper}{calibrationSeconds}, "STM2_Calibrate", $hash, 0);
		$hash->{helper}{direction} = "LS";
	} elsif ($hash->{helper}{direction} eq "RS"){
		Log3($name, 4, "$name CALIBRATION RS");
		STM2_commandSend($hash,"S");
		CommandSet(undef,"$name reset");
		readingsSingleUpdate($hash, "locked", 0, 1); #unlock module for other commands
		readingsSingleUpdate($hash,"calibrated",$timestring,1);
		readingsSingleUpdate($hash, "state", "calibrated", 1); 
		readingsSingleUpdate($hash, "status", "calibrated", 1); 
		$hash->{helper}{direction} = "";
	} elsif ($hash->{helper}{direction} eq "LS"){
		Log3($name, 4, "$name CALIBRATION LS");
		STM2_commandSend($hash,"S");
		readingsSingleUpdate($hash, "locked", 0, 1); #unlock module for other commands
		readingsSingleUpdate($hash,"position_actual","$STMmaxDriveSeconds",1);
		readingsSingleUpdate($hash,"calibrated",$timestring,1);
		readingsSingleUpdate($hash, "state", "calibrated", 1); 
		readingsSingleUpdate($hash, "status", "calibrated", 1); 
		$hash->{helper}{direction} = "";
	}
	return;
	}

1;
