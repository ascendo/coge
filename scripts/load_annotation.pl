#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use CoGeX;
use Getopt::Long;
use File::Path;
use File::Basename;
use File::Spec::Functions qw( catdir catfile );
use File::Touch;
use URI::Escape;
use URI::Escape::JavaScript qw(unescape);
use CoGe::Accessory::Web qw(get_defaults);
use CoGe::Accessory::Utils qw( commify units );
use List::Util qw( min max );
use Benchmark;

my $t1 = new Benchmark;

my $GO          = 1;
my $DEBUG       = 1;
my $DB_BATCH_SZ = 50 * 1000;
use vars qw($staging_dir $result_dir $data_file
  $name $description $link $version $restricted
  $gid $source_name $user_name $config $allow_all_chr
  $host $port $db $user $pass $P);

GetOptions(
    "staging_dir=s" => \$staging_dir,
    "result_dir=s"  => \$result_dir,     # results path
    "data_file=s"   => \$data_file,      # data file (JS escape)
    "name=s"        => \$name,           # experiment name (JS escaped)
    "desc=s"        => \$description,    # experiment description (JS escaped)
    "link=s"        => \$link,           # experiment description (JS escaped)
    "version=s"     => \$version,        # experiment version (JS escaped)
    "restricted=i"  => \$restricted,     # experiment restricted flag
    "gid=s"         => \$gid,            # genome id
    "source_name=s" => \$source_name,    # data source name (JS escaped)
    "user_name=s"   => \$user_name,      # user name
    "config=s"      => \$config,         # configuration file

    # Optional Flags
    "allow_all_chr=i" => \$allow_all_chr # Allow non-existent chromosomes
);

# Open log file
$| = 1;
die unless ($staging_dir);
mkpath($staging_dir); # make sure this exists
my $logfile = "$staging_dir/log.txt";
open( my $log, ">>$logfile" ) or die "Error opening log file $logfile";
$log->autoflush(1);

# Process and verify parameters
$data_file   = unescape($data_file);
$name        = unescape($name);
$description = unescape($description);
$link        = unescape($link);
$version     = unescape($version);
$source_name = unescape($source_name);
$restricted  = '0' if ( not defined $restricted );

if ($user_name eq 'public') {
	print $log "log: error: not logged in\n";
    exit(-1);
}

# Load config file
unless ($config) {
    print $log "log: error: can't find config file\n";
    print STDERR "can't find config file\n";
    exit(-1);
}
$P    = CoGe::Accessory::Web::get_defaults($config);
$db   = $P->{DBNAME};
$host = $P->{DBHOST};
$port = $P->{DBPORT};
$user = $P->{DBUSER};
$pass = $P->{DBPASS};

# Validate the data file
print $log "log: Validating data file ...\n";
unless ( -e $data_file ) {
    print $log "log: can't find data file\n";
    exit(-1);
}

# Connect to database
my $connstr = "dbi:mysql:dbname=$db;host=$host;port=$port;";
my $coge = CoGeX->connect( $connstr, $user, $pass );
unless ($coge) {
    print $log "log: couldn't connect to database\n";
    exit(-1);
}

# Retrieve user (for verification now and used at end for logging)
my $user = $coge->resultset('User')->find( { user_name => $user_name } );
unless ($user) {
    print $log "log: error finding user '$user_name'\n";
    exit(-1);
}

# Retrieve genome
my $genome = $coge->resultset('Genome')->find( { genome_id => $gid } );
unless ($genome) {
    print $log "log: error finding genome id$gid\n";
    exit(-1);
}

# Get list of chromosomes for genome
my %valid_chrs = map { $_ => 1 } $genome->chromosomes;

# Some defaults to check for in names and annotations
my @check_names = (
    "ID",           "name",   "Name",     "Alias",
    "gene",         "Parent", "Locus_id", "ID_converter",
    "Gene_symbols", "gene_id",
);
my %check_names = map { $_ => 1 } @check_names;

my @skip_attr =
  ( "Link_to", "References", "Sequence_download", "transcript_id", );
my %skip_attr = map { $_ => 1 } @skip_attr;

my @anno_names = (
    "Source",
    "Note",
    "NIAS_FLcDNA",
    "Comment",
    "GO",
    "ORF_evidence",    # can we link to SGD?
    "Transcript_evidence",
    "Status",
    "InterPro",
    "Description",
    "Function",
    "Derives_from",
);
my %anno_names = map { $_ => 1 } @anno_names;

my @skip_names_re = qw(
  :five_prime
  :three_prime
  :exon
  \.exon
  :utr
  \.utr
  _utr
  :cds
  \.cds
  cds\.
  :hsp
  \.hsp

  intron
  _E\d
);

my %data;
my %annos;
my %seen_types;
my %seen_attr;

# Load GFF file into %data
#TODO copy gff file into staging directory to read from instead of upload directory
unless ( process_gff_file() ) {
    print $log "log: error: no annotations found, perhaps your file is missing required information, please check the <a href='http://genomevolution.org/wiki/index.php/GFF_ingestion'>documentation</a>\n";
    exit(-1);
}

# Create gene annotations if none present in GFF file
unless ( $seen_types{gene} ) {
    print $log "log: Creating gene entities\n";
    foreach my $chr_loc ( keys %data ) {
      name: foreach my $name ( keys %{ $data{$chr_loc} } ) {
            my ( $chr, $start, $stop, $strand );
            my %names;
            my $name = $data{$chr_loc}{$name};
            foreach my $type ( keys %$name ) {
                map { $names{$_} = 1 } keys %{ $name->{$type}{names} };
                foreach my $loc ( @{ $name->{$type}{loc} } ) {
                    next name if $type eq "gene";
                    $start = $loc->{start} unless $start;
                    $start = $loc->{start} if $loc->{start} < $start;
                    $stop = $loc->{stop} unless $stop;
                    $stop   = $loc->{stop}   if $loc->{stop} > $stop;
                    $strand = $loc->{strand} if $loc->{strand};
                    $strand = 1 unless (defined $strand); # mdb added 11/7/13 issue 248 - set default strand to '+'
                    $chr    = $loc->{chr};
                }
                foreach my $loc ( @{ $name->{$type}{loc} } ) {
                    $loc->{strand} = $strand;
                }
            }
            $name->{gene}{loc} = [
                {
                    start  => $start,
                    stop   => $stop,
                    strand => $strand,
                    chr    => $chr,
                }
            ];
            $name->{gene}{names} = \%names;
            $seen_types{gene}++;
        }
    }
}

print $log "log: Annotation types:\n", join(
    "\n",
    map {
        "log: &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;" . $_ . "\t"
          . commify( $seen_types{$_} )
      } sort keys %seen_types
  ),
  "\n";
print $log "log: Data types:\n", join(
    "\n",
    map {
        "log: &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;" . $_ . "\t"
          . commify( $seen_attr{$_} )
      } sort keys %seen_attr
  ),
  "\n";

my $t2 = new Benchmark;

################################################################################
# If we've made it this far without error then we can feel confident about
# the input data.  Now we can go ahead and create the db entities.
################################################################################

# Create datasource
my $datasource = $coge->resultset('DataSource')->find_or_create( { name => $source_name, description => "" } );
unless ($datasource) {
    print $log "log: error creating data source\n";
    exit(-1);
}

# Create dataset
my $dataset = $coge->resultset('Dataset')->create(
    {
        data_source_id => $datasource->id,
        name           => basename($data_file),
        description    => $description,
        link           => $link,
        version        => $version,
        restricted     => $restricted,
    }
);
unless ($dataset) {
    print $log "log: error creating dataset\n";
    exit(-1);
}

#TODO set link field if loaded from FTP
print $log "dataset id: " . $dataset->id . "\n";

my $dsconn = $coge->resultset('DatasetConnector')->find_or_create( { dataset_id => $dataset->id, genome_id => $genome->id } );
unless ($dsconn) {
    print $log "log: error creating dataset connector\n";
    exit(-1);
}

my %anno_types;    # hash to store annotation type objects
my %feat_types;    # store feature type objects

# Count total annotations to load -- mdb added 1/8/14, issue 260
my $total_annot = 0;
foreach my $chr_loc ( keys %data ) {
    foreach my $name ( keys %{ $data{$chr_loc} } ) {
        foreach my $feat_type ( keys %{ $data{$chr_loc}{$name} } ) {
        	foreach ( @{$data{$chr_loc}{$name}{$feat_type}{loc}} ) {
        		$total_annot++;
        	}
        }
    }
}

print $log "log: Loading database ...\n";
my $loaded_annot = 0;
my @loc_buffer;     # buffer for bulk inserts into Location table
my @anno_buffer;    # buffer for bulk inserts into FeatureAnnotation table
my @name_buffer;    # buffer for bulk inserts into FeatureName table
    foreach my $chr_loc ( sort { $a cmp $b } keys %data ) {
        foreach my $name ( sort { $a cmp $b } keys %{ $data{$chr_loc} } ) {
        	my $pctLoaded = int( 100 * $loaded_annot / $total_annot );
            print $log "log: Loaded " . commify($loaded_annot) . " annotations (" . ( $pctLoaded ? $pctLoaded : '<1' ) . "%)\n\n"
              if ( $loaded_annot and ( $loaded_annot % 1000 ) == 0 );
            
            foreach my $feat_type ( sort { $a cmp $b } keys %{ $data{$chr_loc}{$name} } ) {
                print $log "\n" if $DEBUG;
                
                my ($start, $stop, $strand, $chr);
                my $loc = $data{$chr_loc}{$name}{$feat_type}{loc};
                if (@$loc) {
                    $start    = min map { $_->{start} } @$loc;
                    $stop     = max map { $_->{stop}  } @$loc;
                    ($strand) = map { $_->{strand} } @$loc;
                    ($chr)    = map { $_->{chr}    } @$loc;
                }
                else { # mdb added else 4/8/14 issue 358 - no locations (e.g. tRNA w/o parent)
                    my $coords = $data{$chr_loc}{$name}{$feat_type}{coords};
                    $start  = $coords->{start};
                    $stop   = $coords->{stop};
                    $strand = $coords->{strand};
                    $chr    = $coords->{chr};
                }
                
                $feat_types{$feat_type} = $coge->resultset('FeatureType')->find_or_create( { name => $feat_type } )
                  if $GO && !$feat_types{$feat_type};
                my $feat_type_obj = $feat_types{$feat_type};

                print $log "Creating feature of type $feat_type\n" if $DEBUG;

                # mdb added check 4/8/14 issue 358
                unless (defined $start and defined $stop and defined $chr) {
                    print $log "log: error: feature '", (defined $name ? $name : ''), "' missing coordinates", "\n";
                    print $log Dumper $data{$chr_loc}{$name}{$feat_type}, "\n";
                    exit(-1);
                }
                
                #TODO this could be batched by nesting location & other inserts, see http://search.cpan.org/~abraxxa/DBIx-Class-0.08209/lib/DBIx/Class/ResultSet.pm#populate
                my $feat = $dataset->add_to_features(
                    {
                        feature_type_id => $feat_type_obj->id,
                        start           => $start,
                        stop            => $stop,
                        chromosome      => $chr,
                        strand          => $strand
                    }
                ) if $GO;

                my $featid = $feat ? $feat->id : "no_go";
                my %seen_locs;
                my $loc_count = 0;
                foreach my $loc ( sort { $a->{start} <=> $b->{start} } @$loc ) {
                    my ($start, $stop) = ($loc->{start}, $loc->{stop});
                    $loc_count++;
                    next if $feat_type eq "gene" && $loc_count > 1; #only use the first one as this will be the full length of the gene.  Stupid hack
                    next if $seen_locs{$start}{$stop};
                    $seen_locs{$start}{$stop} = 1;
                    print $log "Adding location $chr:(" . $start . "-" . $stop . ", $strand)\n" if $DEBUG;
                    $loaded_annot++;
                    batch_add_async(
                        \@loc_buffer,
                        'Location',
                        {
                            feature_id => $feat->id,
                            chromosome => $loc->{chr},
                            start      => $loc->{start},
                            stop       => $loc->{stop},
                            strand     => $loc->{strand}
                        }
                    ) if $GO;
                }
                
                my %names =
                  map { $_ => 1 }
                  keys %{ $data{$chr_loc}{$name}{$feat_type}{names} };
                my %seen_annos; #hash to store annotations so duplicates aren't added

                master_names: foreach my $tmp ( keys %names ) {
                    foreach my $re (@skip_names_re) {
                        next master_names if $tmp =~ /$re/i;
                    }
                    my $master = 0;
                    $master = 1 if $tmp eq $name;
                    print $log "Adding name $tmp to feature ", $featid,
                      ( $master ? " (MASTER)" : '' ), "\n"
                      if $DEBUG;

                    batch_add_async(
                        \@name_buffer,
                        'FeatureName',
                        {    #my $feat_name = $feat->add_to_feature_names({
                            feature_id   => $feat->id,
                            name         => $tmp,
                            primary_name => $master
                        }
                    ) if $GO;

                    if ( $annos{$tmp} ) {
                        foreach my $anno ( keys %{ $annos{$tmp} } ) {
                            next unless $anno;
                            next if $seen_annos{$anno};
                            $seen_annos{$anno} = 1;
                            my $type_name = $annos{$tmp}{$anno}{type} || "Note";
                            my ($anno_type) = $anno_types{$type_name};
                            unless ($anno_type) {
                                ($anno_type) = $coge->resultset('AnnotationType')->find_or_create( { name => $type_name } );
                                $anno_types{$type_name} = $anno_type;
                            }
                            my $link = $annos{$tmp}{$anno}{link};
                            print $log "Adding annotation ($type_name): $anno\n" . ( $link ? "\tlink: $link" : '' ) . "\n" if $DEBUG;
                            batch_add_async(
                                \@anno_buffer,
                                'FeatureAnnotation',
                                {
                                    feature_id         => $feat->id,
                                    annotation_type_id => $anno_type->id,
                                    annotation         => $anno,
                                    link               => $link
                                }
                            ) if $GO && $anno;
                        }
                    }
                }
            }
        }
    }

# Flush insert buffers
batch_add( \@loc_buffer,  'Location' );
batch_add( \@name_buffer, 'FeatureName' );
batch_add( \@anno_buffer, 'FeatureAnnotation' );
print $log "log: " . commify($loaded_annot) . " annotations loaded\n";

my $t3 = new Benchmark;
print $log "Time to parse: "
  . timestr( timediff( $t2, $t1 ) )
  . ", Time to load: "
  . timestr( timediff( $t3, $t2 ) ) . "\n";
  
# Save result document
if ($result_dir) {
    mkpath($result_dir);
    CoGe::Accessory::TDS::write(
        catfile($result_dir, '1'),
        {
            genome_id  => int($gid),
            dataset_id => int($dataset->id)
        }
    );
}

# Yay!
CoGe::Accessory::Web::log_history(
    db          => $coge,
    user_id     => $user->id,
    page        => "LoadAnnotation",
    description => 'load dataset id' . $dataset->id,
    link        => 'GenomeView.pl?gid=' . $genome->id
);

# Create "log.done" file to indicate completion to JEX
my $logdonefile = "$staging_dir/log.done";
touch($logdonefile);

print $log "log: All done!";
close($log);

exit;

#-------------------------------------------------------------------------------
sub batch_add {
    my $buffer     = shift;
    my $table_name = shift;
    my $item       = shift;

    if ( defined $buffer ) {
        push @$buffer, $item if ( defined $item );
        if ( @$buffer >= $DB_BATCH_SZ or not defined $item ) {
            print $log "Populate $table_name " . @$buffer . "\n";
            $coge->resultset($table_name)->populate($buffer) if (@$buffer);
            @$buffer = ();
        }
    }
}

sub batch_add_async {
#  batch_add(@_);
#  return;
    my $buffer     = shift;
    my $table_name = shift;
    my $item       = shift;

    if ( defined $buffer ) {
        push @$buffer, $item if ( defined $item );
        if ( @$buffer >= $DB_BATCH_SZ or not defined $item ) {
            print $log "Async populate $table_name " . @$buffer . "\n";
            if ( !defined( my $child_pid = fork() ) ) {
	      print STDERR "Cannot fork: $!";
	      batch_add(@_);
	      return;
	    }
	    elsif ( $child_pid == 0 ) {
	      print $log "child running to populate $table_name\n";
	      $coge->resultset($table_name)->populate($buffer) if (@$buffer);
	      exit;
	    }
            @$buffer = ();
        }
    }
}

sub process_gff_file {
    print $log "process_gff_file: $data_file\n";

    open( my $in, $data_file ) || die "can't open $data_file for reading: $!";

    my $line_num   = 0;
    my $gene_count = 0;
    my $last_RNA   = "mRNA"; #storage for the last RNA type seen.  For converting exons to appropriate RNA type.
    while ( my $line = <$in> ) {
        $line_num++;
        next if $line =~ /^#/;
        next if $line =~ /^Error/;
        chomp $line;
        next unless $line;
        print $log "log: Processed " . commify($line_num) . " lines\n"
          unless $line_num % 100000;

        my @line = split( /\t/, $line );
        if ( @line != 9 ) {
            print $log "log: error:  Incorrect format (too many columns) at line $line_num\n";
            return 0;
        }
        my ($chr, $type, $start, $stop, $strand, $attr) = ($line[0], $line[2], $line[3], $line[4], $line[6], $line[8]);

        # Ignore these types
        #next if $type eq "";
        next if $type eq "clone";
        next if $type eq "intron";
        next if $type eq "chromosome";
        next if $type eq "start_codon";
        next if $type eq "stop_codon";
#        next if $type eq "transcript";
        next if $type eq "protein";

        # Process and check chromosomes
        #$chr =~ s/ig_//;
        $chr =~ s/%.*//;
        $chr =~ s/chromosome//i;
        $chr =~ s/^chr//i;
        $chr =~ s/^_//i;
	    $chr = "0" if $chr =~ /^0+$/; #EL added 2/13/14 to catch chromosomes with names like "00"
        $chr =~ s/^0//g unless $chr eq '0';
        ($chr) = split( /\s+/, $chr );
        unless ( $valid_chrs{$chr} ) {
            print $log "log: error:  Chromosome '$chr' does not exist in the dataset.\n";
            next if ($allow_all_chr);
            return 0;
        }

        $type = "mRNA" if $type eq "transcript";
        # In many GFF files, the mRNA is what CoGe calls a Gene (the full extent
        # of the transcribed sequence including introns and exons.  Instead,
        # what the GFF calls an exon is really the transcribed mRNA.  In this
        # cases, we want to hold the mRNA information to link to Parents and
        # whatever annotation it contains, but don't want to actually add the
        # location.  We will change the feature type to something weird that
        # can be handled downstream correctly -- specifically the locations
        if ( $type =~ /([mt]RNA)/ ) { # mdb changed from /(.*RNA.*)/, 9/3/13 issue 198
            $last_RNA = $type;
            $type     = "$1_no_locs";
        }
        $type = $last_RNA if $type eq "exon";
        $type = $last_RNA if $type eq "five_prime_UTR";
        $type = $last_RNA if $type eq "three_prime_UTR";

        $seen_types{$type}++;

        my %names;
        my $name;
        my ( $parent, $id );
        foreach my $item ( split( /;/, $attr ) ) {
            $item =~ s/"//g;
            $item =~ s/^\s+//;
            $item =~ s/\s+$//;
            next unless $item;

            my ( $key, $value ) = ( split( /[\s=]/, $item, 2 ) );
            $seen_attr{$key}++;
            $parent = $value if $key eq "Parent";
            $id     = $value if $key eq "ID";
            next if $skip_attr{$key};

            if ( $check_names{$key} ) {
              outer:
                foreach my $item ( split( /,/, $value ) ) {
                    $names{$item} = 1;

                    # these nexts will skip from using the primary name as the ID to the Parent name
                    foreach my $re (@skip_names_re) {
                        next outer if $item =~ /$re/i;
                    }
                    $name = $item unless $name;
                    if ( $item =~ /^LOC_/ ) {
                        my $tmp = $item;
                        $tmp =~ s/^LOC_//;
                        $names{$tmp} = 1;
                    }
		            $name =~ s/_cds_\d+$//i;
		            $name =~ s/_exon_\d+$//i;
                }
            }
            next unless $name; # no name, don't know what to do!
            $value = uri_unescape($value); # remove URL formatting
            $annos{$name}{$value} = { type => $key } if $anno_names{$key};
        }
        next unless $name; # no name, don't know what to do!

        if    ( $strand =~ /-/ )  { $strand = -1; }
        elsif ( $strand =~ /\./ ) { $strand = 0;  }
        else                      { $strand = 1;  } # mdb changed 11/7/13 issue 248 - made '+' strand the default

        my @types = ($type);
        #push @types, "CDS" if $add_cds && $type eq "mRNA";
        # phytozome replications of CDS to mRNA
        #push @types, "mRNA" if $type eq "CDS";
        #push @types, "mRNA" if $type =~ /UTR/;
        # replicate mRNA to gene
        #push @types, "gene" if $type eq "mRNA";

        foreach my $tmp (@types) {
            my $tmp_name = $name;
            my $type     = $tmp;
            $type =~ s/_no_locs//;
            $tmp_name = $parent if $type eq "gene" && $parent; # ugly hack
            #print join ("\t", $name, $tmp_name),"\n";

            # initialize data structure
            $data{$chr}{$tmp_name}{$type} = {}
              unless $data{$chr}{$tmp_name}{$type};
            foreach my $n ( keys %names ) {
                $data{$chr}{$tmp_name}{$type}{names}{$n} = 1;
            }
            
            # mdb added 4/8/14 issue 358 - save location for later
            if ($tmp =~ /_no_locs/) {
                $data{$chr}{$tmp_name}{$type}{coords} =
                  {
                    start  => $start,
                    stop   => $stop,
                    strand => $strand,
                    chr    => $chr
                };
            }
            
            next if ($tmp =~ /_no_locs/); # skip adding locations for things like mRNA
            push @{ $data{$chr}{$tmp_name}{$type}{loc} },
              {
                start  => $start,
                stop   => $stop,
                strand => $strand,
                chr    => $chr
              };
        }
        $total_annot++;
    }

    close($in);
    print $log "log: Processed " . commify($line_num) . " total lines\n";
    return $total_annot;
}
