#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use Math::Complex;

use feature qw(switch);

sub compute_median;

#comment
open (CLUSTER_FILE, $ARGV[0]);
#open (CLUSTER_FILE, ">clusters_$event_name");

my $event_clusters = <CLUSTER_FILE>;

my @clusters = split (" ", $event_clusters);



my @cluster_start_time;

foreach (@clusters) {
  my ($start_time) = $_ =~ /^(\d+)\:.+/;
  push (@cluster_start_time, $start_time);
}

my @intervals;


my $prev_cluster = shift(@cluster_start_time);

foreach (@cluster_start_time) {
  my $current_cluster = $_;
  push (@intervals, int($current_cluster-$prev_cluster));
  $prev_cluster = $current_cluster;
}


my ($median, $left_to_median, $right_to_median) = compute_median(\@intervals);



#my @list = (1,2,3,4,5);
#my ($m, $ll, $rr) = compute_median(\@list);
#print "median = $m; ll = $list[$ll], rr = $list[$rr]\n";


#--------------------------------------------------------------------
#----------------IQR approach-----------------------------------------
#--------------------------------------------------------------------

my @sorted_intervals = sort { $a <=> $b } @intervals;
#print Dumper @sorted_intervals;

my @left_intervals = @sorted_intervals[0 .. $left_to_median];
my @right_intervals = @sorted_intervals[$right_to_median .. $#intervals];

my ($Q1,,) = compute_median(\@left_intervals);
my ($Q3,,) = compute_median(\@right_intervals);

my $IQR = $Q3 - $Q1;

print "median = $median\n";
print "IQR = $IQR; Q1 = $Q1; Q3 = $Q3\n";
print "window = [",$Q1 - 1.5*$IQR,"; ",$Q3 + 1.5*$IQR,"]\n";

#my $coeff_dispersion = ($Q3-$Q1) / ($Q3+$Q1);
my $coeff_dispersion = ($Q3-$Q1) / $median;
print "coef of dispersion = $coeff_dispersion\n";

my $num_normal = 0;
my $num_outliers = 0;

my $i=0;
foreach (@intervals) {
  if ( ($_ > $Q3 + 1.5*$IQR || $_ < $Q1 - 1.5*$IQR) ) {
    #print "outlier: $_\n";
    $num_outliers++;
#    print $clusters[$i], "\t interval: $_\n";
  }
  else {
    $num_normal++;
  }
  $i++;
}

print "number of outliers: $num_outliers\n";
print "number of normal: $num_normal\n";


#--------------------------------------------------------------------
#----------------Sn approach-----------------------------------------
#--------------------------------------------------------------------
=pod
my $Sn;
my $MEDi;
my @MEDj;

foreach my $i (0 .. $#intervals) {
  
  my @diffs;
  foreach my $j (0 .. $#intervals) {
    if ($i == $j) { next; }
    push (@diffs, abs($intervals[$i]-$intervals[$j]));
  }
  
  my ($med,,) = compute_median(\@diffs);
  push (@MEDj, $med);
}

($MEDi,,) = compute_median(\@MEDj);
$Sn = $MEDi * 1.1926;

print "median = $median\n";
print "window = [",$median - 3*$Sn,"; ",$median + 3*$Sn,"]\n";

my $num_normal = 0;
my $num_outliers = 0;

my $i=0;
foreach (@intervals) {
  if ( ($_ > $median + 2*$Sn || $_ < $median - 2*$Sn) ) {
    #print "outlier: $_\n";
    $num_outliers++;
#    print $clusters[$i], "\t interval: $_\n";
  }
  else {
    $num_normal++;
  }
  $i++;
}

print "number of outliers: $num_outliers\n";
print "number of normal: $num_normal\n";

=cut

#--------------------------------------------------------------------
#----------------MAD approach-----------------------------------------
#--------------------------------------------------------------------

=pod

my @diffs;
foreach (@intervals) {
  push (@diffs, abs($_-$median));
}

my @sorted_diffs = sort { $a <=> $b } @diffs;


# MAD = Median Absolute deviation
my $mad;
if ($#sorted_diffs % 2) { # even number of elements
  $mad = ($sorted_diffs[$#sorted_diffs/2-1] +
    $sorted_diffs[$#sorted_diffs/2])/2;
}
else { # odd number of elements
  $mad = $sorted_diffs[($#sorted_diffs-1)/2];
}

$mad = $mad*1.48;
print "median = $median; MAD = $mad\n";

print "window = [",$median - 3*$mad,"; ",$median + 3*$mad,"]\n";

my $num_normal = 0;
my $num_outliers = 0;

my $i=0;
foreach (@intervals) {
  if ( ($_ > $median + 3*$mad || $_ < $median - 3*$mad) ) {
    #print "outlier: $_\n";
    $num_outliers++;
    print $clusters[$i], "\t interval: $_\n";
  }
  else {
    $num_normal++;
  }
  $i++;
}

print "number of outliers: $num_outliers\n";
print "number of normal: $num_normal\n";

#=cut


#my $sum = 0;
#foreach (@intervals) {
#  $sum += $_;
#}

=pod
my $mean = $sum/($#intervals+1);

my $variance_temp = 0;
foreach (@intervals) {
  $variance_temp += ($_-$mean)*($_-$mean);
}

my $variance = $variance_temp/$#intervals;

my $stand_dev = sqrt($variance);

print "mean = $mean\n";
print "stand deviation = $stand_dev\n";
print "normal intervals: [",int($mean-$stand_dev),";",int($mean+$stand_dev),"]\n";




=cut





close CLUSTER_FILE;


sub compute_median {

  my @values = @{$_[0]};
  my $size = $#values + 1;

  my @sorted_values = sort { $a <=> $b } @values;
#  print Dumper @sorted_values;
  my $median;
  # indexes left and right to the median
  my $left_to_median;
  my $right_to_median;

  if ($size % 2) { # odd number of elements
    $median = $sorted_values[($size-1)/2];
    $left_to_median = ($size-1)/2 - 1;
    $right_to_median = ($size-1)/2 + 1;
  }
  else { # even number of elements
    $left_to_median = $size/2-1;
    $right_to_median = $size/2;
    $median = ($sorted_values[$left_to_median] +
      $sorted_values[$right_to_median])/2;
  }

  return ($median,$left_to_median,$right_to_median);
}

