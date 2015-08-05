#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;

select((select(STDOUT), $|=1)[0]);

#CoGe::Core::Features::init();
CoGe::Core::Features::dump(10000000000,1214366);
