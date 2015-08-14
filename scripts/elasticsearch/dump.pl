#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;

select((select(STDOUT), $|=1)[0]);

CoGe::Core::Features::dump(935215,0); # offset, limit
