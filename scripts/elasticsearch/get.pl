#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;
use Data::Dumper;

my @hits = CoGe::Core::Features::get_features({dataset_id => $ARGV[0]});
print Dumper @hits;
print scalar @hits;

#my %counts = CoGe::Core::Features::get_type_counts(dataset => $ARGV[0]);
#print Dumper \%counts;
#print scalar keys %counts;
