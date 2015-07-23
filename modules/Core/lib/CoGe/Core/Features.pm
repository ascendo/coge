package CoGe::Core::Features;

use Exporter 'import';
@EXPORT_OK = qw(get_features get_type_counts);
  
=head1 NAME

CoGe::Core::Features

=head1 SYNOPSIS

provides class for accessing feature data from Elasticsearch

=head1 DESCRIPTION

=head1 AUTHOR

Sean Davey

=head1 COPYRIGHT

The full text of the license can be found in the
LICENSE file included with this module.

=head1 SEE ALSO

=cut

use strict;
use warnings;

use CoGe::Accessory::genetic_code;
use CoGe::Accessory::Web qw(get_defaults);
use CoGe::Core::Elasticsearch qw(build_filter elasticsearch_get elasticsearch_post);
use CoGeX;
use Data::Dumper;
use DBI;
use Encode qw(encode);
use JSON::XS;

use base 'Class::Accessor';
__PACKAGE__->mk_accessors( '_genomic_sequence', 'gst', 'dsg', 'trans_type' ); #_genomic_sequence =>place to store the feature's genomic sequence with no up and down stream stuff

################################################ subroutine header begin ##

=head2 clean_locations

 Usage     : $self->clean_locations
 Purpose   : returns wantarray of location objects.  Checks them for consistency due to some bad loads where locations had bad starts, stops, chromosomes and strands

 Returns   : returns wantarray of location ojects
 Argument  : none
 Throws    :
 Comments  : 

See Also   :

=cut

################################################## subroutine header end ##

sub clean_locations {
	my $self = shift;
	my @locs;
	foreach my $loc (@{$self->{locations}}) {
		next if $loc->{strand} ne $self->{strand};
		next if $loc->{chromosome} ne $self->{chromosome};
		next if $loc->{start} < $self->{start} || $loc->{start} > $self->{stop};
		next if $loc->{stop} < $self->{start} || $loc->{stop} > $self->{stop};
		push @locs, $loc;
	} 
	return wantarray ? @locs : \@locs;
}

################################################ subroutine header begin ##

=head2 codon_frequency

 Usage     :
 Purpose   :
 Returns   :
 Argument  :
 Throws    :
 Comments  :
           :

See Also   :

=cut

################################################## subroutine header end ##

sub codon_frequency {
	my $self      = shift;
	my %opts      = @_;
	my $counts    = $opts{counts};
	my $code      = $opts{code};
	my $code_type = $opts{code_type};
	my $gstid     = $opts{gstid};
	( $code, $code_type ) = $self->genetic_code unless $code;
	my %codon = map { $_ => 0 } keys %$code;
	my $seq = $self->genomic_sequence( gstid => $gstid );
	my $x   = 0;

	while ( $x < CORE::length($seq) ) {
		$codon{ uc( substr( $seq, $x, 3 ) ) }++;
		$x += 3;
	}
	if ($counts) {
		return \%codon, $code_type;
	} else {
		my $total = 0;
		foreach ( values %codon ) {
			$total += $_;
		}
		foreach my $codon ( keys %codon ) {
			$codon{$codon} = sprintf( "%.4f", ( $codon{$codon} / $total ) );
		}
		return ( \%codon, $code_type );
	}
}

################################################ subroutine header begin ##

=head2 copy

 Usage     :
 Purpose   : copy a particular dataset from the database to elasticsearch
 Returns   :
 Argument  : dataset_id
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub copy {
	my $dataset_id = shift;
    my $dbh = CoGeX->dbconnect(get_defaults())->storage->dbh;
    my $query = 'SELECT feature_id,feature_type_id,dataset_id,start,stop,strand,chromosome FROM feature WHERE dataset_id=' . $dataset_id;
    my $features = $dbh->prepare($query);
    $features->execute;
    copy_rows($features, $dbh);
}

################################################ subroutine header begin ##

=head2 copy_rows

 Usage     :
 Purpose   : copy features from database rows to elasticsearch
 Returns   :
 Argument  : features - database rows to copy
 			 dbh - database handle
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub copy_rows {
	my $features = shift;
	my $dbh = shift;
	my $json_xs = JSON::XS->new->allow_nonref;
    while (my $feature = $features->fetchrow_arrayref) {
    	my $feature_id = $feature->[0];
		my $json = '{';
		$json .= '"type":' . $feature->[1] . ',"dataset":' . $feature->[2];
		if ($feature->[3]) {
			$json .= ',"start":' . $feature->[3];
		}
		if ($feature->[4]) {
			$json .= ',"stop":' . $feature->[4];
		}
		if ($feature->[5]) {
			$json .= ',"strand":' . $feature->[5];
		}
		if ($feature->[6]) {
			$json .= ',"chromosome":"' . $feature->[6] . '"';
		}
	    my $names = $dbh->prepare('SELECT name,description,primary_name FROM feature_name WHERE feature_id=' . $feature_id);
	    $names->execute;
		$json .= ',"names":[';
		my $first = 1;
	    while (my $name = $names->fetchrow_arrayref) {
			if ($first) {
				$first = 0;
			} else {
				$json .= ',';
			}
			$json .= '{"name":' . $json_xs->encode(encode("UTF-8", $name->[0]));
			if ($name->[1]) {
				$json .= ',"description":' . $json_xs->encode(encode("UTF-8", $name->[1]));
			}
			if ($name->[2]) {
				$json .= ',"primary":true';
			};
			$json .= '}';
		}
		$json .= '],"locations":[';
	    my $locations = $dbh->prepare('SELECT start,stop,strand,chromosome FROM location WHERE feature_id=' . $feature_id);
	    $locations->execute;
		$first = 1;
	    while (my $location = $locations->fetchrow_arrayref) {
			if ($first) {
				$first = 0;
			} else {
				$json .= ',';
			}
			$json .= '{"start":' . $location->[0] . ',"stop":' . $location->[1] . ',"strand":' . $location->[2] . ',"chromosome":"' . $location->[3] . '"}';
		}
		$json .= '],"annotations":[';
	    my $annotations = $dbh->prepare('SELECT annotation,annotation_type_id,link FROM feature_annotation WHERE feature_id=' . $feature_id);
	    $annotations->execute;
		$first = 1;
	    while (my $annotation = $annotations->fetchrow_arrayref) {
			if ($first) {
				$first = 0;
			} else {
				$json .= ',';
			}
			$json .= '{"annotation":' . $json_xs->encode(encode("UTF-8", $annotation->[0])) . ',"type":' . $annotation->[1];
			if ($annotation->[2]) {
				$json .= ',"link":' . $json_xs->encode(encode("UTF-8", $annotation->[2]));
			}
			$json .= '}';
		}
		$json .= ']}';
		print $feature_id . ' ';
		elasticsearch_post('coge/features/' . $feature_id, $json);
	}
	
}

################################################ subroutine header begin ##

=head2 dataset

 Usage     :
 Purpose   :
 Returns   : the dataset object for this feature
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub dataset {
	my $self = shift;
	return $self->{_dataset} if $self->{_dataset};

	$self->{_dataset} = CoGeX->dbconnect(get_defaults())->resultset('Dataset')->find($self->{dataset});
	return $self->{_dataset};
}

################################################ subroutine header begin ##

=head2 dump

 Usage     :
 Purpose   : copy features from db to elasticsearch
 Returns   :
 Argument  : limit (num features to send), [offset (record to start at)]
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub dump {
	my $limit = shift;
	my $offset = shift;
    my $dbh = CoGeX->dbconnect(get_defaults())->storage->dbh;
    my $query = 'SELECT feature_id,feature_type_id,dataset_id,start,stop,strand,chromosome FROM feature LIMIT ' . $limit;
    if ($offset) {
    	$query .= ' OFFSET ' . $offset;
    }
    my $features = $dbh->prepare($query);
    $features->execute;
    copy_rows($features, $dbh);
}

################################################ subroutine header begin ##

=head2 genetic_code

 Usage     :
 Purpose   :
 Returns   :
 Argument  :
 Throws    :
 Comments  :
           :

See Also   :

=cut

################################################## subroutine header end ##

sub genetic_code {
	my $self       = shift;
	my %opts       = @_;
	my $trans_type = $opts{trans_type};
	$trans_type = $self->trans_type unless $trans_type;
	unless ($trans_type) {
		foreach my $annotation (@{$self->{annotations}}) {
			if ($annotation->{type} == 10973) { # 10973 is id for annotation type transl_table
				$trans_type = $annotation->{annotation};
				last;
			}
		}
	}

	unless ($trans_type) {
		my $org_name = $self->organism->name;
		my $org_desc = $self->organism->description;
		$trans_type = 4  if $org_desc =~ /Mycoplasma/;
		$trans_type = 11 if $org_desc =~ /Bacteria/;
		$trans_type = 11
		  if $org_name =~ /plastid/i || $org_name =~ /chloroplast/i;
		$trans_type = 15 if $org_desc =~ /Blepharisma/;
		$trans_type = 6  if $org_desc =~ /Ciliate/;
		$trans_type = 6  if $org_desc =~ /Dasycladacean/;
		$trans_type = 6  if $org_desc =~ /Hexamitidae/;
		$trans_type = 10 if $org_desc =~ /Euploitid/;
		$trans_type = 22
		  if $org_desc =~ /Scenedesmus/ && $org_name =~ /mitochondri/i;
		$trans_type = 9
		  if $org_desc =~ /Echinodermata/ && $org_name =~ /mitochondri/i;
		$trans_type = 2
		  if $org_desc =~ /Vertebra/ && $org_name =~ /mitochondri/i;
		$trans_type = 5
		  if $org_desc !~ /Vertebra/
		  && $org_desc =~ /Metazoa/
		  && $org_name =~ /mitochondri/;
		$trans_type = 13
		  if $org_desc =~ /Ascidiacea/ && $org_name =~ /mitochondri/i;
		$trans_type = 13
		  if $org_desc =~ /Thraustochytrium/ && $org_name =~ /mitochondri/i;
		$trans_type = 16
		  if $org_desc =~ /Chlorophyta/ && $org_name =~ /mitochondri/i;
		$trans_type = 21
		  if $org_desc =~ /Trematoda/ && $org_name =~ /mitochondri/i;
		$trans_type = 3 if $org_desc =~ /Fungi/ && $org_name =~ /mitochondri/i;
		$trans_type = 1 unless $trans_type;
	}
	$self->trans_type($trans_type);
	my $code = code($trans_type);
	return ( $code->{code}, $code->{name} );
}

################################################ subroutine header begin ##

=head2 genomic_sequence

 Usage     : my $genomic_seq = $feat->genomic_sequence
 Purpose   : gets the genomic seqence for a feature
 Returns   : a string
 Argument  : 
 Comments  :
See Also   : CoGe

=cut

################################################## subroutine header end ##

sub genomic_sequence {
	my $self   = shift;
	my %opts   = @_;
	my $up     = $opts{up} || $opts{upstream} || $opts{left};
	my $down   = $opts{down} || $opts{downstream} || $opts{right};
	my $debug  = $opts{debug};
	my $gstid  = $opts{gstid};
	my $seq    = $opts{seq};
	my $dsgid  = $opts{dsgid};
	my $genome = $opts{genome}; #genome object
	my $dataset = $opts{dataset}; #dataset object
	my $server = $opts{server}; #used for passing in server name from which to retrieve sequence from web-script CoGe/GetSequence.pl
	my $rel = $opts{rel};
    #print STDERR "up: $up, down: $down\n";
    #have a full sequence? -- pass it in and the locations will be parsed out of it!
	if ( !$up && !$down && $self->_genomic_sequence ) {
		return $self->_genomic_sequence;
	}

	$dataset = $self->dataset() unless $dataset && ref($dataset) =~ /dataset/i;
	my @sequences;
	my %locs =
	  map { ( $_->{start}, $_->{stop} ) }
	  $self->clean_locations();
	  ; #in case a mistake happened when loading locations and there are multiple ones with the same start
	 #print STDERR Dumper \%locs, "\n";
	my @locs = map { [ $_, $locs{$_} ] } sort { $a <=> $b } keys %locs;
	( $up, $down ) = ( $down, $up )
	  if ( $self->{strand} =~ /-/ )
	  && !$rel
	  ; #must switch these if we are on the - strand unless we are using relative position;
	if ($up) {
		my $start = $locs[0][0] - $up;
		$start = 1 if $start < 1;
		$locs[0][0] = $start;
	}
	if ($down) {
		my $stop = $locs[-1][1] + $down;
		$locs[-1][1] = $stop;
	}
	my $chr      = $self->{chromosome};
	my $start    = $locs[0][0];
	my $stop     = $locs[-1][1];
	my $full_seq = $seq ? $seq : $dataset->get_genomic_sequence(
		chr    => $chr,
		start  => $start,
		stop   => $stop,
		debug  => $debug,
		gstid  => $gstid,
		gid    => $dsgid,
        genome => $genome,
		server => $server,
	);

	if ($full_seq) {
	    my $full_seq_length = CORE::length($full_seq);
		foreach my $loc (@locs) {
			if ( $loc->[0] - $start + $loc->[1] - $loc->[0] + 1 > $full_seq_length )
			{
				print STDERR "#" x 20, "\n",
    	            "Error in feature->genomic_sequence, Sequence retrieved is smaller than the length of the exon being parsed! \n",
    	            "Organism: ", $self->organism->name, "\n",
    	            "Dataset: ",  $self->dataset->name,  "\n",
    	            "Locations data-structure: ", Dumper \@locs,
    	            "Retrieved sequence length: ",
    	            $full_seq_length, "\n",
    	            #$full_seq, "\n",
    	            "Feature object information: ",
    				Dumper {
        				chromosome        => $chr,
        				skip_length_check => 1,
        				start             => $start,
        				stop              => $stop,
        				dataset           => $dataset->id,
        				feature           => $self->id
    				},
    	            "#" x 20, "\n";
			}

			my $sub_seq = substr( $full_seq, $loc->[0] - $start, $loc->[1] - $loc->[0] + 1 );
			next unless $sub_seq;
			
			if ( $self->{strand} == -1 ) {
				unshift @sequences, $self->reverse_complement($sub_seq);
			}
			else {
				push @sequences, $sub_seq;
			}
		}
	}
	
	my $outseq = join( "", @sequences );
	if ( !$up && !$down ) {
		$self->_genomic_sequence($outseq);
	}
	
	return $outseq;
}

################################################ subroutine header begin ##

=head2 get_features

 Usage     : 
 Purpose   : get all features for a dataset
 Returns   : array of feature hashes
 Argument  : dataset - required, id of the dataset
 			 chromosome - optional, to only return features from one chromosome
 			 type - optional, feature_type_id, to only return features of the specified type
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_features {
	my %opts = @_;
	my $json = elasticsearch_post('coge/features/_search?search_type=scan&scroll=1m', '{"query":{"filtered":{"filter":' . build_filter(%opts) . '}},"size":1000000}');
	my $o = decode_json($json);
	$json = elasticsearch_post('_search/scroll?scroll=1m', $o->{_scroll_id});
	$o = decode_json($json);
	my @hits;
	foreach (@{$o->{hits}->{hits}}) {
		my $feature = $_->{_source};
		$feature->{id} = $_->{_id};
		push (@hits, bless $feature);
	}
	return @hits;
}

################################################ subroutine header begin ##

=head2 get_type_counts

 Usage     :
 Purpose   : get the counts for each different feature type
 Returns   : a hash of feature_type_id => count
 Argument  : dataset - required, id of the dataset
 			 chromosome - optional, to only return features from one chromosome
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_type_counts {
	my %opts = @_;
	my $json = elasticsearch_post('coge/features/_search?search_type=count','{"query":{"filtered":{"filter":{"term":' . encode_json(\%opts) . '}}},"aggs":{"count":{"terms":{"field":"type"}}}}');
	my $o = decode_json($json);
	my %counts;
	foreach (@{$o->{aggregations}->{count}->{buckets}}) {
		$counts{$_->{key}} = $_->{doc_count};
	}
	return %counts;
}

################################################ subroutine header begin ##

=head2 organism

 Usage     : 
 Purpose   :
 Returns   : 
 Argument  : 
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub organism {
	my $self = shift;
	return $self->{_organism} if $self->{_organism};

	my $db = CoGeX->dbconnect(get_defaults());
	my $dbh = $db->storage->dbh;
	my $genome_id = $dbh->selectrow_arrayref('SELECT genome_id FROM dataset_connector WHERE dataset_id=' . $self->{dataset});
	my $organism_id = $dbh->selectrow_arrayref('SELECT organism_id FROM genome WHERE genome_id =' . $genome_id->[0]);
	$self->{_organism} = $db->resultset('Organism')->find($organism_id->[0]);
	return $self->{_organism};
}

################################################ subroutine header begin ##

=head2 reverse_complement

 Usage     :
 Purpose   :
 Returns   :
 Argument  :
 Throws    :
 Comments  :
           :

See Also   :

=cut

################################################## subroutine header end ##

sub reverse_complement {
	my $self = shift;
	my $seq  = shift;    # || $self->genomic_sequence;
	if ( ref($self) =~ /Feature/ ) {
		$seq = $self->genomic_sequence
		  unless $seq;    #self seq unless we have a seq
	}
	else                  #we were passed a sequence without invoking self
	{
		$seq = $self unless $seq;
	}
	my $rcseq = reverse($seq);
	$rcseq =~ tr/ATCGatcg/TAGCtagc/;
	return $rcseq;
}

1;
