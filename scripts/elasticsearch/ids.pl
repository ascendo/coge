#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Elasticsearch;

print CoGe::Core::Elasticsearch::get_ids('features',10);
