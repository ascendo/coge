#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;
use Data::Dumper;

print CoGe::Core::Features::get_type_count($ARGV[0], $ARGV[1]);
