#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;
use List::Util qw(max min);
use POSIX qw(floor ceil);

use feature qw(switch);

sub do_similarity_matrix;
sub compute_novelty;
sub otsu;
sub compute_confidence;

#comment
open (EVENT_FILE, $ARGV[0]);
my ($event_name) = $ARGV[0] =~ /\/(\w+)$/; 
open (CLUSTER_FILE, ">clusters/clusters_$event_name");

my $event_occurences = <EVENT_FILE>;

my @occurences = split (" ", $event_occurences);


# get rid of the first two and the last elements of @occurences array
# i.e. the name of the event and the "[" "]"
shift @occurences;
shift @occurences;
pop @occurences;

#my @reduced = @occurences;
my @reduced = @occurences[0..6200];
#my @reduced = @occurences[0..800];
#my @reduced = @occurences[100 .. 113];


#------------------------------------------
my @Ti;

foreach (@reduced) {

  my ($start,$end) = $_ =~ m/(\d+):(\d+);/g;
  my $middle_time = int($start + ($end - $start)/2);

  push(@Ti,$middle_time);
}

#------------------------------------------

my $max_confidence = -100;
my @best_borders;

foreach my $K (100, 1000, 10000, 100000, 1000000) {
  my @S = do_similarity_matrix($K, \@Ti);
  my @novelty_1 = compute_novelty( $#Ti-1, \@S);
#  print "------------$K-----------\n";
  
  my ($threshold, @novelty) = otsu(\@novelty_1);

# ------------- choose the best resolution K ------------
  my ($confidence, @b) = compute_confidence( \@novelty, \@S, $threshold);

  
  if ($confidence > $max_confidence) {
    @best_borders = @b;
    $max_confidence = $confidence;
  }

#  print "confidence = $confidence\n"; 
}

#print "\nbest confidence = $max_confidence\n";
#print "best borders:\n";
#print Dumper @best_borders;

# ------------- print clusters ---------------------------

foreach my $i (0 .. $#best_borders-1) {
  my $current_border = $best_borders[$i];
  my $next_border = $best_borders[$i+1];

  my ($start) = ($reduced[$current_border] =~ /(\d+):\d+;/);
  my ($end) = ($reduced[$next_border-1] =~ m/\d+:(\d+);/);

  print CLUSTER_FILE "$start:$end; ";
#  print "$start:$end ";

}




#------------------------------------------

sub do_similarity_matrix {

  my $K = $_[0];
  my @Ti = @{$_[1]};

# similarity matrix S
  my @S;

# zero-padding matrix S 
  my @zero_array = map { 0 } 0..$#Ti+2;
  push(@S, [@zero_array]);

  foreach (@Ti) {
    my $current = $_;
    my @distances;
    foreach (@Ti) {
      my $val = 1/(exp(abs($current - $_)/$K));
      push(@distances,$val);
    }
    # zeros for padding
    push(@S,[0,@distances,0]);
  }

# zero-padding matrix S 
  push(@S, [@zero_array]);

  return @S;
}

sub compute_novelty {
  my $num_elem = $_[0]; 
  my @S = @{$_[1]};

# using the 4x4 kernel
  my @g = (
    [ 0.1,  0.5, -0.5, -0.1],
    [ 0.5,   1,   -1,  -0.5],
    [-0.5,  -1,    1,   0.5],
    [-0.1, -0.5,  0.5,  0.1]
  );

  my @novelty;

  foreach my $i (1 .. $num_elem) {
    my $novelty_i = 0;
    foreach my $l (-1 .. 2) {
      foreach my $m (-1 .. 2) {
        $novelty_i += $S[$i+$m][$i+$l]*$g[$m+1][$l+1];       
      }
    }
    push(@novelty,$novelty_i);
  }

  return @novelty;
}


sub otsu {

  my @novelty = @{$_[0]};

 #----create "buckets" corresponding to the gray levels in Otsu's method 
  
  my $min_novelty = min (@novelty);
#  print "min elem = $min_novelty\n";
  # truncate $min_novelty to 0.1 precision
  my $floor_min_novelty = int($min_novelty*10)/10;
#  print "floor min elem = $floor_min_novelty\n";

  my $max_novelty = max (@novelty);

  # !!!!!!!-------------------------------------
  # make the first element always start a new cluster
  # so we just add a big novelty score in the beginning to represent a
  # fake big novelty score for the very first element
  unshift(@novelty,$max_novelty);
#  print Dumper @novelty;

#  print "max elem = $max_novelty\n";
  # ceil $max_novelty to 0.1 precision
  my $ceil_max_novelty = int(($max_novelty+0.1)*10)/10;
#  print "ceil max elem = $ceil_max_novelty\n";

  my %buckets;
  for (my $i = $floor_min_novelty; $i < $ceil_max_novelty; $i += 0.1) {
    $buckets{$i} = 0;
  }

  # calculate the number of novelty scores in each bucket
  # using the same trick to truncate novelty score with 0.1 precision
  map { $buckets{int($_*10)/10} += 1  } @novelty;

  #my %buckets = %{$_[0]};
  # total number of novelty scores
  my $total = $#novelty + 1;

#  print Dumper \%buckets;
  #------------OTSU's method------------------------

  my $sum;
  for (my $t = $floor_min_novelty; $t < $ceil_max_novelty; $t += 0.1) {
    $sum += $t * $buckets{$t};
#    print "[$t,",$t+0.1,"]: $buckets{$t}\n";
  }

  my $sumB = 0;
  my $wB = 0;
  my $wF = 0;

  my $varMax = 0;
  my $threshold;

  for (my $t = $floor_min_novelty; $t < $ceil_max_novelty; $t += 0.1) {
    
    $wB += $buckets{$t};
#    if ($wB == 0) { next; }

    $wF = $total - $wB;
    if ($wF == 0) { last; }

    $sumB += $t * $buckets{$t};

    my $mB = $sumB / $wB;          # Mean Background
    my $mF = ($sum - $sumB) / $wF; # Mean Foreground

    my $variance_between = $wB * $wF * ($mB - $mF) * ($mB - $mF); 

#    print "t = $t; total = $total; wB = $wB; wF = $wF; variance between = $variance_between\n";

    if ($variance_between > $varMax) {
      $varMax = $variance_between;
      $threshold = $t;
    }
  }

  # in order to use correctly
  $threshold = $threshold + 0.1;

#  print "threshold = ",$threshold,"\n";

  return ($threshold, @novelty);
}


sub compute_confidence {
  
  my @novelty = @{$_[0]};
  my @S = @{$_[1]};
  my $threshold = $_[2];

# array of cluster boundaries
  my @b; 

  foreach my $i (0 .. $#novelty) {
    if ($novelty[$i] >= $threshold) {
      push(@b, $i);
#      print "cluster starts here:",$reduced[$i],"\n";
    }
  }

  my $confidence = 0;
  
  # WCS - within cluster similarity
  # BCD - between cluster dissimilarity

  # calculate the WCS
  foreach my $l (0 .. $#b-1) {

    my $confidence_onelem = 0;
    my $confidence_sevelem = 0;

    # process one-element clusters
    if ($b[$l] == $b[$l+1]-1) { # check if one-element cluster
      #$confidence_onelem = $S[$b[$l]+1][$b[$l]+1]; # WCS += 1
      # $S[$b[$l]+1] cause the first row/column of S are zeros
      $confidence_onelem = 0; 
    }  
    # process several-element clusters
    else {
      foreach my $i ($b[$l] .. $b[$l+1]-1) {
        foreach my $j ($b[$l] .. $b[$l+1]-1) {
          if ($i != $j) {
            $confidence_sevelem += $S[$i+1][$j+1]; 
          }
        }
      }

      my $num_elem_in_cluster = ($b[$l+1] - $b[$l])*($b[$l+1] - $b[$l])
      - ($b[$l+1]-$b[$l]); # do not count the diagonal elements
      $confidence_sevelem = $confidence_sevelem/$num_elem_in_cluster;
    }

    $confidence += ($confidence_onelem + $confidence_sevelem);
  }


  # calculate the BCD
  foreach my $l (0 .. $#b-2) {

    my $confidence_1 = 0; # this and next cluster are one-element
    my $confidence_2 = 0; # this is one-element; next one - no
    my $confidence_3 = 0; # this is multi-element; next one one-element
    my $confidence_4 = 0; # this and next cluster are multi-element

    # process one-element clusters
    if ($b[$l] == $b[$l+1]-1) { # check if one-element cluster
      if ($b[$l+1] == $b[$l+2]-1) { # if the next cluster is also one-element
        $confidence_1 = $S[$b[$l]+1][$b[$l+1]+1]; 
      }
      else { # if the next cluster is multi-element
        foreach my $j ($b[$l+1] .. $b[$l+2]-1) {
          $confidence_2 += $S[$b[$l]+1][$j+1];
        }
        $confidence_2 = $confidence_2/(1*($b[$l+2] - $b[$l+1]));
      }

    }  
    else { # process several-element clusters
      if ($b[$l+1] == $b[$l+2]-1) { # if the next cluster is one-element
        foreach my $i ($b[$l] .. $b[$l+1]-1) {
          $confidence_3 += $S[$i+1][$b[$l+1]+1];
        }
        $confidence_3 = $confidence_3/(1*($b[$l+1] - $b[$l]));
      }
      else { #if the next cluster is also multi-element
        foreach my $i ($b[$l] .. $b[$l+1]-1) {
          foreach my $j ($b[$l+1] .. $b[$l+2]-1) {
            $confidence_4 += $S[$i+1][$j+1]; 
          }
        }

        $confidence_4 = $confidence_4/(($b[$l+1]-$b[$l])*($b[$l+2]-$b[$l+1]));
        
      }

    }
 
    $confidence = $confidence - ($confidence_1+$confidence_2+$confidence_3+$confidence_4);
  }

  return ($confidence, @b);
}


  #--------- print out the similarity matrix --------------

=pod
foreach (@S) {
  my $line = $_;
  foreach (@$line) {
    printf(" %.2f", $_);
  }
  print "\n";
}
=cut


  #--------- print out the clusters --------------


