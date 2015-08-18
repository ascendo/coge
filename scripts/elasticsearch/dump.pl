#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;

select((select(STDOUT), $|=1)[0]);

CoGe::Core::Features::dump(1, 0); # offset, limit
