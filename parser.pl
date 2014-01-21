#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

use feature qw(switch);

sub format_events;
sub handle_Interrupt;
sub handle_ContextSwitch;
sub handle_Tracepoint;

#comment
open (TRACE_FILE, $ARGV[0]);
open (EVENTS_FILE, ">output_events");

# variables declared with 'my' outside of any block is global for all
# the blocks and subroutines
my $line_count = 0;

my $current_time = 0;
my %events;

# we start from idle state
my $currently_executing_process_CPU0 = "Process1757(mttd)";
#my $currently_executing_process_CPU0 = "Process1760(sshd)";
my $currently_executing_process_CPU1 = "Process0";
#my $currently_executing_process_CPU1 = "Process1750(ts_record)";

my $process_start_time_CPU0 = "0";
my $process_start_time_CPU1 = "0";

while (my $line = <TRACE_FILE>) {
  print "$line";
  
  $line_count++;
  # ignore the first line in the trace file
  if ($line_count == 1) { next; }

  # remove "\n" from each line
  chomp($line);
  # remove the last delimiter "," from each line
  chop($line);

  # last argument -1 defines that the trailing empty matches are
  # preserved. Normally, they're discarded.
  my @fields = split (",", $line, -1);

  given($fields[4]) {
    when ("Interrupt") {
      handle_Interrupt(@fields);
    }
    when ("__switch_to") {
      handle_ContextSwitch(@fields);
    }
    when ("SoftIRQ") {
      # SoftIRQs have the same format as Interrupts
      handle_Interrupt(@fields); 
    }
    default { # tracepoint
      handle_Tracepoint(\@fields,$line_count); 
    }
  }
}

format_events();

close TRACE_FILE;
close EVENTS_FILE;

#---------------SUBROUTINES------------------------------------

sub handle_Tracepoint {

  my @target_fields = @{$_[0]};
  my $line_number = $_[1];

  # parsing the fields
  my $start_time = $target_fields[0];
  my $end_time = $target_fields[1];
  my $duration = $target_fields[2];
  my $active_time = $target_fields[3];
  my $tracepoint_name = $target_fields[4];
  my $context = $target_fields[5];
  my $cpu = $target_fields[7];

  # bug fix 1
  if ($tracepoint_name =~ m/^\d/) {
    $active_time = $target_fields[3].$target_fields[4]; 
    $tracepoint_name = $target_fields[5];
    $context = $target_fields[6];
  }
  # bug fix 2. ignore events that has empty active_time field
  if ($active_time eq "") {
    return;  
  }

  $context =~ s/\s//g;
  $context =~ s/\(|\)//g;
  # construction of the events name
  my $event_name = $tracepoint_name."(".$context.")";

  if (!exists $events{$event_name}) {
    $events{$event_name} = ();
  }


  # if duration == active time, nothing special should be done
  if ($active_time eq $duration) {
    # just put it in the @events array
    push(@{$events{$event_name}}, "$start_time\:$end_time");
    return;
  }
  
  # if duration != active time, the special treatment is needed in order
  # to find the chunks of time when the tracepoint was active


  # we ll need to read again the trace file to process forward the lines
  # in order to find the active chunks
  open (TRACE_FILE_SEARCH_FORWARD, $ARGV[0]);

  my $line;
  while ( $line = <TRACE_FILE_SEARCH_FORWARD>) {
    # looking for the line we ve stopped at
    next unless $. == $line_number;

    last;  # Exit from the loop. Weve found the line we need
  }

  while ( $line = <TRACE_FILE_SEARCH_FORWARD>) {
    
    chomp($line);
    chop($line);
    my @fields = split (",", $line, -1);

    # case when active_time != duration only because of interrupts
    if ($fields[0] > $end_time) {
      push(@{$events{$event_name}}, "$start_time\:$end_time");
      close TRACE_FILE_SEARCH_FORWARD;
      return;
    }

    # the tracepoint's context was switched off the first time or switched off again
    if ( ($fields[4] eq "__switch_to") && ($fields[6] eq $target_fields[5]) ) {
      #push new active chunk to events hash
      push(@{$events{$event_name}}, "$start_time\:$fields[0]");
    }
    # the tracepoint's context was switched in again
    elsif ( ($fields[4] eq "__switch_to") && ($fields[5] eq $target_fields[5]) ) {
      # memorize the start_time of the new active chunk
      $start_time = $fields[0]; 
    }

  }
  print "sould never be printed\n";
  close TRACE_FILE_SEARCH_FORWARD;
    
}

sub handle_Interrupt {

  my @fields = @_;

  # parsing the 'Context' field
  my $context = $fields[5];
  # remove all whitespace characters
  $context =~ s/\s//g;

  # parsing part that depends on the event type
  if ($fields[4] eq "Interrupt") {
    # remove 'GIC' from the event s name (all Interrupts have it)
    $context =~ s/GIC//g;
  }
  elsif ($fields[4] eq "SoftIRQ") {
  }

  # saving the CPU number
  my $cpu = $fields[7];
  # construction of the event s name
  my $event_name = $context.":".$cpu;

  #construction of the event s start and end time
  my $start_time = $fields[0];
  my $end_time = $fields[1];
  
  if (!exists $events{$event_name}) {
    $events{$event_name} = ();
  }

  push(@{$events{$event_name}}, "$start_time\:$end_time");
}

sub handle_ContextSwitch {

  my @fields = @_;

  # parsing the 'Context' and 'Previous Context' fields
  my $context = $fields[5];
  my $prev_context = $fields[6];
  # remove all whitespace characters
  $context =~ s/\s//g;
  $prev_context =~ s/\s//g;
  # add "Process" so the event is identified as a process
  $context = "Process".$context;
  $prev_context = "Process".$prev_context;

  # saving the CPU number
  my $cpu = $fields[7];

  given($cpu) {
    when ("0") {
      ($process_start_time_CPU0, $currently_executing_process_CPU0) =
      __handle_ContextSwitch($process_start_time_CPU0,
        $currently_executing_process_CPU0, $context, $prev_context,
        $fields[0]);
    }
    when ("1") {
      ($process_start_time_CPU1, $currently_executing_process_CPU1) =
      __handle_ContextSwitch($process_start_time_CPU1,
        $currently_executing_process_CPU1, $context, $prev_context,
        $fields[0]);
    }
    default {
      print "This should never be printed\n";
    }
  }

}

sub __handle_ContextSwitch {

  my ($process_start_time, $currently_executing_process, $context,
    $prev_context, $time) = @_;

  # just a sanity check 
  if ($prev_context ne $currently_executing_process) {
    print "$prev_context $currently_executing_process error!\n";
  }

  # we don't care about idle state. Thus, when it is switched out we
  # don't need to add it to the %events
  if ($prev_context ne "Process0") {
    my $process_end_time = $time;

    if (!exists $events{$prev_context}) {
      $events{$prev_context} = ();
    }

    push(@{$events{$prev_context}}, "$process_start_time\:$process_end_time"); 

  }

  # switched-in process s start time == switched-out process s end
  # time
  $process_start_time = $time;

  # now it s the $context that is executing on the CPU{N}
  $currently_executing_process = $context;

  return ($process_start_time, $currently_executing_process);
}

sub format_events {

  foreach my $name (keys %events) {
    print EVENTS_FILE "$name: [ ";
    foreach my $active_period (@{$events{$name}}) {
      print EVENTS_FILE "$active_period; ";
    }
    print EVENTS_FILE "]\n";
  }
}


