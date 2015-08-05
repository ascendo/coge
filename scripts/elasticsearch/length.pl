#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;
use Data::Dumper;

print CoGe::Core::Features::get_total_chromosomes_length($ARGV[0]);
