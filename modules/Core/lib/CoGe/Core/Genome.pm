package CoGe::Core::Genome;

use strict;
use warnings;

use Data::Dumper;
use File::Spec::Functions;
use Sort::Versions;

use CoGe::Accessory::TDS qw(write read);
use CoGe::Accessory::Utils;
use CoGe::Core::Storage qw(get_genome_path);

BEGIN {
    our ( @EXPORT, @EXPORT_OK, @ISA, $VERSION );
    require Exporter;

    $VERSION = 0.1;
    @ISA = qw( Exporter );
    @EXPORT = qw( has_statistic get_gc_stats get_noncoding_gc_stats
        get_wobble_histogram get_wobble_gc_diff_histogram get_feature_type_gc_histogram
        fix_chromosome_id search_genomes get_genome );
    @EXPORT_OK = qw(genomecmp);
}

#my @LOCATIONS_PREFETCH = (
#    { "feature_type_id" => 3 },
#    {
#        join => [
#            'locations',
#            { 'dataset' => { 'dataset_connectors' => 'genome' } }
#        ],
#        prefetch => [
#            'locations',
#            { 'dataset' => { 'dataset_connectors' => 'genome' } }
#        ]
#    }
#);

sub genomecmp($$) {
    my ($a, $b) = @_;

    my $namea = $a->name ? $a->name :  "";
    my $nameb = $b->name ? $b->name :  "";
    my $typea = $a->type ? $a->type->id : 0;
    my $typeb = $b->type ? $b->type->id : 0;

    $a->organism->name cmp $b->organism->name
      || versioncmp( $b->version, $a->version )
      || $typea <=> $typeb
      || $namea cmp $nameb
      || $b->id cmp $a->id;
}

sub get_wobble_histogram {
    my $genome = _get_genome_or_exit(@_);
    my $storage_path = _get_histogram_file($genome->id);

    my $data = read($storage_path);
    return $data->{wobble_histogram} if defined $data->{wobble_histogram};

    $data->{wobble_histogram} = _generate_wobble_content($genome);

    # Exit if generate failed
    unless(defined $data->{wobble_histogram}) {
        say STDERR "Genome::get_genome_wobble_content: generate wobble content failed!";
        exit;
    }

    say STDERR "Genome::get_genome_wobble_content: write failed!"
        unless write($storage_path, $data);

    # Return data
    return $data->{wobble_histogram};
}

sub get_feature_type_gc_histogram {
    my $genome = _get_genome_or_exit(shift);
    my $typeid = shift;

    unless (defined $typeid) {
        say STDERR "Genome::get_feature_type_gc_histogram: typeid is not defined!";
        exit;
    }

    my $key = 'feature_type_' . $typeid . '_gc_histogram';

    my $storage_path = _get_histogram_file($genome->id);
    my $data = read($storage_path);
    return $data->{$key} if defined $data->{$key};

    $data->{$key} = _generate_feature_type_gc($genome, $typeid);

    # Exit if generate failed
    unless(defined $data->{$key}) {
        say STDERR "Genome::get_genome_wobble_content: generate wobble content failed!";
        exit;
    }

    say STDERR "Genome::get_genome_wobble_content: write failed!"
        unless write($storage_path, $data);

    # Return data
    return $data->{$key};
}

sub get_wobble_gc_diff_histogram {
    my $genome = _get_genome_or_exit(@_);
    my $storage_path = _get_histogram_file($genome->id);

    my $data = read($storage_path);
    return $data->{wobble_gc_diff_histogram} if defined $data->{wobble_gc_diff_histogram};

    $data->{wobble_gc_diff_histogram} = _generate_wobble_gc_diff($genome);

    # Exit if generate failed
    unless(defined $data->{wobble_gc_diff_histogram}) {
        say STDERR "Genome::get_genome_wobble_content: generate wobble content failed!";
        exit;
    }

    say STDERR "Genome::get_genome_wobble_content: write failed!"
        unless write($storage_path, $data);

    # Return data
    return $data->{wobble_gc_diff_histogram};
}

sub has_statistic {
    my $genome = _get_genome_or_exit(shift);
    my $stat = shift;

    my $storage_path = _get_stats_file($genome->id);
    my $data = read($storage_path);

    return defined $data->{$stat};
}

sub _generate_wobble_content {
    my $genome = shift;
    my $gstid = $genome->type->id;
    my $wobble_content = {};

    my ($at, $gc, $n) = (0) x 3;

    foreach my $ds ($genome->datasets()) {
#        foreach my $feat ($ds->features(@LOCATIONS_PREFETCH)) {
        foreach my $feat ($ds->features( type_id => 3 )) {
            my @gc = $feat->wobble_content( counts => 1 );
            $gc = $gc[0] if $gc[0] && $gc[0] =~ /^\d+$/;
            $at = $gc[1] if $gc[1] && $gc[1] =~ /^\d+$/;
            $n  = $gc[2] if $gc[2] && $gc[2] =~ /^\d+$/;

            my $total = 0;
            $total += $gc[0] if $gc[0];
            $total += $gc[1] if $gc[1];
            $total += $gc[2] if $gc[2];
            my $perc_gc = 100 * $gc[0] / $total if $total;

            $wobble_content->{$feat->id . '_' . $gstid} = {
                at => $at,
                gc => $gc,
                n => $n,
            };

            #skip if no values
            next unless $perc_gc;

            my $node = $wobble_content->{$feat->id . '_' . $gstid};
            $node->{percent_gc} = $perc_gc;
        }
    }

    return $wobble_content;
}

sub get_gc_stats {
    my $genome = _get_genome_or_exit(shift);
    my $storage_path = _get_stats_file($genome->id);

    my $data = read($storage_path);
#    return $data->{gc} if defined $data->{gc};

    $data->{gc} = _generate_gc_stats($genome);

    # Exit if generate failed
    unless(defined $data->{gc}) {
        say STDERR "Genome::get_gc_stats: generate noncoding gc stats failed!";
        exit;
    }

    say STDERR "Genome::get_gc_stats: write failed!"
        unless write($storage_path, $data);

    # Return data
    return $data->{gc};
}

sub get_noncoding_gc_stats {
    my $genome = _get_genome_or_exit(@_);
    my $storage_path = _get_stats_file($genome->id);

    my $data = read($storage_path);
    return $data->{noncoding_gc} if defined $data->{noncoding_gc};

    $data->{noncoding_gc} = _generate_noncoding_gc_stats($genome);

    # Exit if generate failed
    unless(defined $data->{noncoding_gc}) {
        say STDERR "Genome::get_noncoding_gc_stats: generate noncoding gc stats failed!";
        exit;
    }

    say STDERR "Genome::get_noncoding_gc_stats: write failed!"
        unless write($storage_path, $data);

    # Return data
    return $data->{noncoding_gc};
}

#
# Private functions
#
sub _get_genome_or_exit {
    my $genome = shift;

    unless ($genome) {
        say STDERR "Genome::get_genome_wobble_content: genome not specified!";
        exit;
    }

    return $genome;
}

sub _get_histogram_file {
    catfile((get_genome_path(shift), "metadata/histograms.json"));
}

sub _get_stats_file {
    catfile((get_genome_path(shift), "metadata/stats.json"));
}

sub _generate_wobble_gc_diff {
    my $genome = shift;
    my $gstid = $genome->type->id;
    my $data = [];

    foreach my $ds ($genome->datasets) {
#        foreach my $feat ($ds->features(@LOCATIONS_PREFETCH)) {
        foreach my $feat ($ds->features( type_id => 3 )) {
            my @wgc  = $feat->wobble_content();
            my @gc   = $feat->gc_content();
            my $diff = $gc[0] - $wgc[0] if defined $gc[0] && defined $wgc[0];
            push @$data, sprintf( "%.2f", 100 * $diff ) if $diff;
        }
    }

    return $data;
}

sub _generate_feature_type_gc {
    my ($genome, $typeid) = @_;
    my $gstid = $genome->type->id;
    my $gc_content = {};

    my (@items, @datasets);

    push @items, $genome;

    my %seqs; # prefetch the sequences with one call to genomic_sequence (slow for many seqs)
    foreach my $item (@items) {
        map {
            $seqs{$_} = $item->get_genomic_sequence( chr => $_, seq_type => $gstid )
        } $item->chromosome_names;
    }

    my ($at, $gc, $n) = (0) x 3;

#    my @params = (
#        { "feature_type_id" => $typeid },
#        {
#            join => [
#                'locations',
#                { 'dataset' => { 'dataset_connectors' => 'genome' } }
#            ],
#            prefetch => [
#                'locations',
#                { 'dataset' => { 'dataset_connectors' => 'genome' } }
#            ],
#        }
#    );

    foreach my $ds ($genome->datasets) {
#        my @feats = $ds->features(@params);
        my @feats = $ds->features( type_id => $typeid);

        foreach my $feat (@feats) {
            my $seq = substr(
                $seqs{ $feat->chromosome },
                $feat->start - 1,
                $feat->stop - $feat->start + 1
            );

            $feat->genomic_sequence( seq => $seq );
            my @gc = $feat->gc_content( counts => 1 );

            $gc = $gc[0] if $gc[0] =~ /^\d+$/;
            $at = $gc[1] if $gc[1] =~ /^\d+$/;
            $n  = $gc[2] if $gc[2] =~ /^\d+$/;

            my $total = 0;
            $total += $gc[0] if $gc[0];
            $total += $gc[1] if $gc[1];
            $total += $gc[2] if $gc[2];

            my $perc_gc = 100 * $gc[0] / $total if $total;

            $gc_content->{$feat->id . '_' . $gstid} = {
                at => $at,
                gc => $gc,
                n => $n
            };

            #skip if no values
            next unless $perc_gc;
            my $node = $gc_content->{$feat->id . '_' . $gstid};
            $node->{percent_gc} = sprintf( "%.2f", $perc_gc );
        }
    }

    return $gc_content;
}

sub _generate_gc_stats {
    my $genome = shift;
    my $gstid = $genome->type->id;

    my ( $gc, $at, $n, $x ) = (0) x 4;

    foreach my $ds ($genome->datasets) {
	    my %chr = map { $_ => 1 } $ds->chromosome_names;
        foreach my $chr ( keys %chr ) {
            my @gc =
              $ds->percent_gc( chr => $chr, seq_type => $gstid, count => 1 );
            $gc += $gc[0] if $gc[0];
            $at += $gc[1] if $gc[1];
            $n  += $gc[2] if $gc[2];
            $x  += $gc[3] if $gc[3];
        }
    }
    my $total = $gc + $at + $n + $x;
    return unless $total;

    return {
        total => $total,
        gc    => $gc / $total,
        at    => $at / $total,
        n     => $n  / $total,
        x     => $x  / $total,
    };
}

sub _generate_noncoding_gc_stats {
    my $genome = shift;
    my (@items, @datasets);

    my $gstid = $genome->type->id;
    push @items, $genome;
    push @datasets, $genome->datasets;

    my %seqs; # prefetch the sequences with one call to genomic_sequence (slow for many seqs)
    foreach my $item (@items) {
        map {
            $seqs{$_} = $item->get_genomic_sequence( chr => $_, seq_type => $gstid )
        } $item->chromosome_names;
    }

    foreach my $ds (@datasets) {
#        foreach my $feat ($ds->features(@LOCATIONS_PREFETCH)) {
        foreach my $feat ($ds->features( type_id => 3 )) {
            foreach my $loc ( $feat->locs ) {
                if ( $loc->stop > length( $seqs{ $feat->chromosome } ) ) {
                    print STDERR "feature "
                      . $feat->id
                      . " stop exceeds sequence length: "
                      . $loc->stop . " :: "
                      . length( $seqs{ $feat->chromosome } ), "\n";
                }
                substr(
                    $seqs{ $feat->chromosome },
                    $loc->start - 1,
                    ( $loc->stop - $loc->start + 1 )
                ) = "-" x ( $loc->stop - $loc->start + 1 );
            }

            #push @data, sprintf("%.2f",100*$gc[0]/$total) if $total;
        }
    }

    my ( $gc, $at, $n, $x ) = ( 0, 0, 0, 0 );

    foreach my $seq ( values %seqs ) {
        $gc += $seq =~ tr/GCgc/GCgc/;
        $at += $seq =~ tr/ATat/ATat/;
        $n  += $seq =~ tr/nN/nN/;
        $x  += $seq =~ tr/xX/xX/;
    }

    my $total = $gc + $at + $n + $x;
    return unless $total;

    return {
        total => $total,
        gc    => $gc / $total,
        at    => $at / $total,
        n     => $n  / $total,
        x     => $x  / $total,
    };
}

# Used by the load scripts:  load_genome.pl, load_experiment.pl, and load_annotation.pl
# mdb consolidated from load scripts into this module, 2/11/15 COGE-587
sub fix_chromosome_id { 
    my $chr = shift;        # chr id to fix
    my $genome_chr = shift; # optional hash ref of existing chromosome ids for genome
    return unless defined $chr;

    # Fix chromosome identifier
    $chr =~ s/^lcl\|//;
    $chr =~ s/^gi\|//;
    $chr =~ s/chromosome//i;
    $chr =~ s/^chr//i;
    $chr = "0" if $chr =~ /^0+$/; #EL added 2/13/14 chromosome name is 00 (or something like that)
    $chr =~ s/^0+// unless $chr eq '0';
    $chr =~ s/^_+//;
    $chr =~ s/\s+/ /g;
    $chr =~ s/^\s//;
    $chr =~ s/\s$//;
    $chr =~ s/\//_/g; # mdb added 12/17/13 issue 266 - replace '/' with '_'
    $chr =~ s/\|$//;  # mdb added 3/14/14 issue 332 - remove trailing pipes
    $chr =~ s/\|/_/g; # mdb added 8/13/15 - convert pipes to underscore
    $chr =~ s/\(/_/g; # mdb added 2/11/15 COGE-587 - replace '(' with '_'
    $chr =~ s/\)/_/g; # mdb added 2/11/15 COGE-587 - replace ')' with '_'
    $chr =~ s/_+/_/g; # mdb added 8/13/15 - convert multiple underscores to single underscore
    return if ($chr eq '');

    # Convert 'chloroplast' and 'mitochondia' to 'C' and 'M' if needed
    if (defined $genome_chr) {
        if (   $chr =~ /^chloroplast$/i
            && !$genome_chr->{$chr}
            && $genome_chr->{"C"} )
        {
            $chr = "C";
        }
        if (   $chr =~ /^mitochondria$/i
            && !$genome_chr->{$chr}
            && $genome_chr->{"M"} )
        {
            $chr = "M";
        }
    }

    return $chr;
}

sub search_genomes {
    my $db = shift;
    my $search_term = shift;
    
    # Search genomes
    my $search_term2 = '%' . $search_term . '%';
    my @genomes = $db->resultset("Genome")->search(
        \[
            'genome_id = ? OR name LIKE ? OR description LIKE ?',
            [ 'genome_id', $search_term  ],
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );
    
    # Search organisms
    my @organisms = $db->resultset("Organism")->search(
        \[
            'name LIKE ? OR description LIKE ?',
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );
    
    # Combine matching genomes and organisms, preventing duplicates
    my %unique;
    map { $unique{ $_->id } = $_ } @genomes;
    foreach my $organism (@organisms) {
        map { $unique{ $_->id } = $_ } $organism->genomes;
    }
    
    return wantarray ? values %unique : [ values %unique ];
}

sub get_genome {
    my $db = shift;
    my $genome_id = shift;
    
    return $db->resultset("Genome")->find($genome_id)
}

1;
