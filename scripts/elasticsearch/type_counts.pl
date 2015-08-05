#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;
use Data::Dumper;

print Dumper CoGe::Core::Features::get_type_counts($ARGV[0]);
