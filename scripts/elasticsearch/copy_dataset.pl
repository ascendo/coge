#!/usr/bin/env perl
use strict;
use warnings;

use lib 'perl5';
use CoGe::Core::Features;

my $dataset_id = shift;
my $index = shift || 'coge'; # optional index name

CoGe::Core::Features::copy_dataset($dataset_id, $index);
