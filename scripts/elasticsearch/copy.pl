#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;

CoGe::Core::Features::copy($ARGV[0]);
