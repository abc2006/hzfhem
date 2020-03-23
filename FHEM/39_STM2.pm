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
sub STM2_Calibrate($@);

sub STM2_commandSend($$){
	#params: R | L | S
	my ($hash, $cmd)	= @_;
	my $name = $hash->{NAME};
	if($cmd eq "R"){ 
		CommandSet(undef,AttrVal($name,"STMdevL",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevR",0)." on");
		}
	if($cmd eq "L"){ 
		CommandSet(undef,AttrVal($name,"STMdevR",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevL",0)." on");
		}
	if($cmd eq "S"){ 
		CommandSet(undef,AttrVal($name,"STMdevR",0)." off");
		CommandSet(undef,AttrVal($name,"STMdevL",0)." off");
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
	$hash->{AttrList}	= "disable:0,1 STMmaxDriveSeconds STMdevL STMdevR STMlastDiffMax STMpollInterval ".$readingFnAttributes;
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
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $locked = ReadingsVal($name,'locked',0);
	if(AttrVal($name,"STMdevR","") eq "" && AttrVal($name,"STMdevL","") eq "" && AttrVal($name,"STMmaxDriveSeconds","") eq "")
	{
		readingsSingleUpdate($hash, "state", "missing Attributes",1);
		return;
	}
	if($setOption eq "stop"){
		STM2_Stop($hash);
		Log3($name, 4, "STELLMOTOR $name User submitted Stop Request");
		return;
	}elsif($setOption eq "reset"){
		STM2_Stop($hash);
		readingsBeginUpdate($hash);
		## weitere Readings hinzufügen?
		foreach("position","locked","td_lastdiff","tr_stop","ta_stopHR","tr_target","tr_actual","ta_lastStart","ta_stop","tr_start"){
			readingsBulkUpdate($hash, $_ , 0);		
			}
		foreach("state"){
			readingsBulkUpdate($hash, $_ , "reset");		
			}
		readingsEndUpdate($hash, 1);
		return;
	}elsif($setOption eq "position" && $locked == 0){
	 	if(length($args[2]) && $args[2] =~ /^\d+$/ && $args[2] >=0 && $args[2] <= $STMmaxDriveSeconds){	
		readingsSingleUpdate($hash,"tr_target",$args[2],1);
		Log3($name, 4, "$name set_position tr_target: $args[2]");
		}
	}elsif ($setOption eq "?"){
		return "Unknown argument ?, choose one of stop:noArg position reset:noArg";
	}
	if (IsDisabled($name)) {
		readingsSingleUpdate($hash, "state", "disabled_138", 0); #save requested value to queue and return
		Log3 $name, 4, "STELLMOTOR $name device is disabled";  
		return;
		}
	# Was wissen wir hier: Wir wissen die Zielposition, wo wir hin sollen. 
	#Um Herauszufinden, ob wir rechts oder links bewegen müssen, brauchen wir die aktuelle position
	my $tr_actual = ReadingsVal($name, "tr_actual",0);
	my $tr_target = ReadingsVal($name, "tr_target",0);
	my $td_lastdiff = ReadingsVal($name,'td_lastdiff',0); 

	Log3($name, 4, "$name Set: tr_actual: $tr_actual");
	Log3($name, 4, "$name Set: tr_target: $tr_target");
	Log3($name, 4, "$name Set: td_lastdiff: $td_lastdiff");
	## jetzt haben wir die alten positionen und die übrige Differenz. 
	readingsSingleUpdate($hash,"tr_start", $tr_actual,1);
	#save the actual start time position	
	my $tr_totalMove = $tr_target - $tr_actual + $td_lastdiff;
	Log3($name, 4, "$name Set: tr_totalMove: $tr_totalMove");
	my $cmd_move;
	if($tr_totalMove>0){ $cmd_move = "R"; }
	elsif($tr_totalMove<0){ $cmd_move = "L"; }
	readingsSingleUpdate($hash, "state", $cmd_move ,1);
	# jetzt wissen wir, in welche Richtung der Motor laufen soll.
	$tr_totalMove=abs($tr_totalMove); #be shure to have positive moveCmdTime value
	readingsSingleUpdate($hash, "locked", 1, 1); #lock module for other commands
	readingsSingleUpdate($hash,"ta_lastStart", $now,1);
	#jetzt wissen wir, bis wann der Motor laufen soll
	readingsSingleUpdate($hash, "ta_stop", ($now+$tr_totalMove), 1); #set the end time of the move

	my $timestring = strftime "%Y-%m-%d %T",localtime($now + $tr_totalMove);
	readingsSingleUpdate($hash,"ta_stopHR", $timestring,1);
	STM2_commandSend($hash,$cmd_move);
	STM2_GetUpdate($hash);    

	return;
	}
sub STM2_ImmediateStop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	if(ReadingsVal($name,'locked', 1)==0){
		return; #no move in progress, nothing to stop
		}
	}

sub STM2_Stop($@){
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
  	RemoveInternalTimer($hash);
	STM2_commandSend($hash,"S");
	my $now = gettimeofday();
	my $ta_stop = ReadingsVal($name,"ta_stop",$now);
	my $ta_lastStart = ReadingsVal($name,"ta_lastStart",$now);
	my $tr_start = ReadingsVal($name,"tr_start","0");
	my $STMmaxDriveSeconds = AttrVal($name, "STMmaxDriveSeconds", 107);
	my $td_diff = $now-$ta_stop;
	readingsSingleUpdate($hash,'td_lastdiff',$td_diff,1); #update position reading
	readingsSingleUpdate($hash, "locked", 0, 1); #unlock module for other commands
	my $timeitranactually = $ta_stop-$ta_lastStart;
	my $timeitreachedactually = $tr_start + $timeitranactually;
	Log3($name, 4, "$name Stop: timeitranactually: $timeitranactually");
	Log3($name, 4, "$name Stop: timeitreachedactually: $timeitreachedactually");

	readingsSingleUpdate($hash,'tr_actual',$timeitreachedactually,1); #update position reading
		

}

sub STM2_GetUpdate($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $ta_stop = ReadingsVal($name,"ta_stop", 0);
	my $ta_lastStart =  ReadingsVal($name,"ta_lastStart", 0);
	my $now = gettimeofday();
	my $tr_actual = ReadingsVal($name, "tr_actual",0);
	if($ta_stop == 0){
		Log3($name, 4, "$name ta_stop: $ta_stop, stopzeit fehlerhaft!");
		return;
	}
	readingsSingleUpdate($hash, "GetUpdate", $now, 1); 
	Log3($name, 4, "$name getUpdate ta_stop: $ta_stop");
	Log3($name, 4, "$name getUpdate now: $now");
	Log3($name, 4, "$name getUpdate ta_stop - now:" . ($ta_stop-$now));
	if(($ta_stop ne 0) and (($ta_stop-$now)<1)){
		STM2_Stop($hash);
		Log3($name, 4, "$name getUpdate STOP");
		return;
	}
	my $tr_run = $now - $ta_lastStart; ## wie viele Sekunden läuft der Motor schon?  
	Log3($name, 4, "STM2 $name getUpdate tr_run: $tr_run");
	readingsSingleUpdate($hash, "tr_run", $tr_run, 1); 
	my $tr_actual = $tr_actual + $tr_run; ## start + delta = aktuelle zeitposition
	Log3($name, 4, "STM2 $name getUpdate tr_actual: $tr_actual");
	readingsSingleUpdate($hash, "tr_actual", $tr_actual, 1); 
	
	InternalTimer($now + 0.5, "STM2_GetUpdate", $hash, 0);
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
    Log3($name, 3, "STELLMOTOR $name initialized");
    STM2_GetUpdate($hash);    
  }
  return;
}
sub STM2_Attr(@) {
	my ($cmd, $name, $attrName, $attrVal) = @_;
	my $hash = $defs{$name};
	return;
	}

sub STM2_Calibrate($@){
#drive to left (or right if attr) for maximum time and call "set reset"
	my ($hash,$option) = @_;
	my $name = $hash->{NAME};
	return;
	}

1;
