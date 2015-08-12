package CoGe::Core::Features;

BEGIN {
	use Exporter 'import';
	our @EXPORT_OK =
	  qw( chromosome_exists get_chromosome_count get_chromosome_names get_chromosomes get_feature
	  get_features get_feature_ids get_features_in_region get_features_count
	  get_total_chromosomes_length get_type_counts
	);
}

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

use CoGe::Accessory::Web qw(get_defaults);
use CoGe::Core::Elasticsearch qw(bulk_index get search);
use CoGeX;
use Data::Dumper;
use Encode qw(encode);
use JSON::XS;

our $DEBUG = 1;

################################################ subroutine header begin ##

=head2 chromosome_exists

 Usage     :
 Purpose   :
 Returns   : if the dataset contains the chromosome
 Argument  : hash with dataset_id and chromosome
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub chromosome_exists {
	my %opts = @_;
	return search_exists( 'features',
		{ dataset => $opts{dataset_id}, chromosome => $opts{chromosome} } );
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
	my $index = shift || 'coge';    # optional index name

	my $dbh = CoGeX->dbconnect( get_defaults() )->storage->dbh;
	my $query =
'SELECT feature_id,feature.feature_type_id,name,dataset_id,start,stop,strand,chromosome FROM feature JOIN feature_type ON feature.feature_type_id=feature_type.feature_type_id WHERE dataset_id='
	  . $dataset_id;
	my $features = $dbh->prepare($query);
	$features->execute;
	copy_rows( $features, $dbh, $index );
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
	my $dbh      = shift;
	my $index    = shift || 'coge';                # optional index name

	my @docs;
	my @ids;
	while ( my $feature = $features->fetchrow_arrayref ) {
		my $feature_id = int $feature->[0];
		my $body       = {
			type_id   => int $feature->[1],
			type_name => $feature->[2],
			dataset   => int $feature->[3]
		};
		if ( $feature->[4] ) {
			$body->{start} = int $feature->[4];
		}
		if ( $feature->[5] ) {
			$body->{stop} = int $feature->[5];
		}
		if ( $feature->[6] ) {
			$body->{strand} = int $feature->[6];
		}
		if ( $feature->[7] ) {
			$body->{chromosome} = $feature->[7];
		}
		my $db_names = $dbh->prepare(
'SELECT name,description,primary_name FROM feature_name WHERE feature_id='
			  . $feature_id );
		$db_names->execute;
		my $names;
		while ( my $db_name = $db_names->fetchrow_arrayref ) {
			my $name = { name => $db_name->[0] };
			if ( $db_name->[1] ) {
				$name->{description} = $db_name->[1];
			}
			if ( $db_name->[2] ) {
				$name->{primary} = 1;
			}
			push @$names, $name;
		}
		if ($names) {
			$body->{names} = $names;
		}
		my $db_locations = $dbh->prepare(
'SELECT start,stop,strand,chromosome FROM location WHERE feature_id='
			  . $feature_id );
		$db_locations->execute;
		my $locations;
		while ( my $db_location = $db_locations->fetchrow_arrayref ) {
			push @$locations,
			  {
				start      => int $db_location->[0],
				stop       => int $db_location->[1],
				strand     => int $db_location->[2],
				chromosome => $db_location->[3]
			  };
		}
		if ($locations) {
			$body->{locations} = $locations;
		}
		my $db_annotations = $dbh->prepare(
'SELECT annotation,annotation_type_id,link FROM feature_annotation WHERE feature_id='
			  . $feature_id );
		$db_annotations->execute;
		my $annotations;
		while ( my $db_annotation = $db_annotations->fetchrow_arrayref ) {
			my $annotation = {
				annotation => $db_annotation->[0],
				type       => int $db_annotation->[1]
			};
			if ( $db_annotation->[2] ) {
				$annotation->{link} = $db_annotation->[2];
			}
			push @$annotations, $annotation;
		}
		if ($annotations) {
			$body->{annotations} = $annotations;
		}

		push @docs, $body;
		push @ids, $feature_id;
	}
	bulk_index('features', \@docs, \@ids);
}

################################################ subroutine header begin ##

=head2 dump

 Usage     :
 Purpose   : copy features from db to elasticsearch
 Returns   :
 Argument  : offset (record to start at), [limit (num features to send)]
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub dump {
	my $offset = shift;
	my $limit = shift || 10000;
	my $dbh = CoGeX->dbconnect( get_defaults() )->storage->dbh;

	my $rows = 10000;
	while ( $rows == 10000 ) {
		my $query = 'SELECT feature_id,feature.feature_type_id,name,dataset_id,start,stop,strand,chromosome FROM feature JOIN feature_type ON feature.feature_type_id=feature_type.feature_type_id LIMIT ' . $limit;
		$query .= ' OFFSET ' . $offset if ($offset);
		my $features = $dbh->prepare($query);
		$features->execute;
		copy_rows( $features, $dbh );
		$rows = $features->rows;
		print $offset . ' ' . $rows . "\n";
		$offset += 10000;
	}
}

################################################ subroutine header begin ##

=head2 get_chromosome_count

 Usage     :
 Purpose   :
 Returns   : the number of chromosome features for the dataset
 Argument  : search hash, must contain at least dataset_id => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosome_count {
	my %opts = @_;
	$opts{type_id} = 4;
	return get_features_count(%opts);
}

################################################ subroutine header begin ##

=head2 get_chromosome_names

 Usage     :
 Purpose   :
 Returns   : array of the chromosome names for the dataset
 Argument  : search hash, must contain at least dataset_id => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosome_names {
	my %opts  = @_;
	my $query = query( \%opts );
	$query->{type} = 4;
	my $options = options( \%opts );
	$options->{_source} = 'chromosome';
	my $results = search( 'features', $query, $options );
	my @chromosome_names;
	if ( $results->{hits}->{total} ) {

		foreach ( @{ $results->{hits}->{hits} } ) {
			push @chromosome_names, $_->{_source}->{chromosome};
		}
	}
	else {    # gather chromosome names from all features since none have type 4
		$options->{_source} = 0;
		$options->{args} = { count => { terms => { field => 'chromosome' } } };
		$results = search( 'features', $query, $options );
		foreach ( @{ $results->{aggregations}->{count}->{buckets} } ) {
			push @chromosome_names, $_->{key};
		}
	}
	return wantarray ? @chromosome_names : \@chromosome_names;
}

################################################ subroutine header begin ##

=head2 get_chromosomes

 Usage     :
 Purpose   :
 Returns   : array of the chromosome features for the dataset
 Argument  : search hash, must contain at least dataset_id => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosomes {
	my %opts = @_;
	$opts{type_id} = 4;    # 4 is the feature_type_id for chromosomes
	return get_features(%opts);
}

################################################ subroutine header begin ##

=head2 get_feature

 Usage     : 
 Purpose   :
 Returns   : a single feature
 Argument  : id of the feature you want
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_feature {
	return get( 'features', shift, 'CoGe::Core::Feature' );
}

################################################ subroutine header begin ##

=head2 get_features

 Usage     : 
 Purpose   : get features for a dataset
 Returns   : array of feature hashes
 Argument  : search - hash of fields to query, options (optional) - hash of query options
 Throws    :
 Comments  : for search: dataset - required: id of the dataset
 			 chromosome - optional: to only return features from one chromosome
 			 type - optional: feature_type_id, to only return features of the specified type
 			 for options: size: max number of hits to return
 			 sort: one of or an array ref of field names and/or hashes of field name => 'asc'|'desc'

See Also   :

=cut

################################################## subroutine header end ##

sub get_features {
	my %opts = @_;

	my $results = search( 'features', query( \%opts ), options( \%opts ) );

	my @results;
	foreach ( @{ $results->{hits}->{hits} } ) {
		my $result = $_->{_source};
		$result->{id} = $_->{_id};
		bless( $result, 'CoGe::Core::Feature' );
		push @results, $result;
	}
	return wantarray ? @results : \@results;
}

################################################ subroutine header begin ##

=head2 get_feature_ids

 Usage     : 
 Purpose   : 
 Returns   : array of ids of matching features for a dataset
 Argument  : search - hash of fields to query
 Throws    :
 Comments  : for search: dataset - required: id of the dataset
 			 chromosome - optional: to only return features from one chromosome
 			 type - optional: feature_type_id, to only return features of the specified type

See Also   :

=cut

################################################## subroutine header end ##

sub get_feature_ids {
	my %opts    = @_;
	my $options = options( \%opts );
	$options->{_source} = 0;
	my $results = search( 'features', query( \%opts ), $options );
	my @ids;
	foreach ( @{ $results->{hits}->{hits} } ) {
		push( @ids, $_->{_id} );
	}
	return \@ids;
}

################################################ subroutine header begin ##

=head2 get_features_count

 Usage     :
 Purpose   :
 Returns   : the number of features of the passed in type for the dataset
 Argument  : search hash, must contain at least dataset_id => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_features_count {
	my %opts    = @_;
	my $options = options( \%opts );
	$options->{search_type} = 'count';
	my $results = search( 'features', query( \%opts ), $options );
	warn "get_features_count";
	warn Dumper $results;
}

################################################ subroutine header begin ##

=head2 get_features_in_region

 Usage     : $object->get_features_in_region(start   => $start,
                                             stop    => $stop,
                                             chr     => $chr,
                                             ftid    => $ftid,
                                             dataset_id => $dataset->id(),);

 Purpose   : gets all the features in a specified genomic region
 Returns   : an array or an array_ref of feature objects (wantarray)
 Argument  : start   => genomic start position
             stop    => genomic stop position
             chr     => chromosome
             dataset_id => dataset id in database (obtained from a
                        CoGe::Dataset object)
                        of the dna seq will be returned
             OPTIONAL
             count   => flag to return only the number of features in a region
             ftid    => limit features to those with this feature type id
 Throws    : none
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_features_in_region {
	my %opts = @_;
	my $start =
	     $opts{'start'}
	  || $opts{'START'}
	  || $opts{begin}
	  || $opts{BEGIN};
	$start = 1 unless $start;
	my $stop = $opts{'stop'} || $opts{STOP} || $opts{end} || $opts{END};
	$stop = $start unless defined $stop;
	my $chr = $opts{chr};
	$chr = $opts{chromosome} unless defined $chr;
	my $dataset_id =
	     $opts{dataset}
	  || $opts{dataset_id}
	  || $opts{info_id}
	  || $opts{INFO_ID}
	  || $opts{data_info_id}
	  || $opts{DATA_INFO_ID};
	my $genome_id  = $opts{gid};
	my $count_flag = $opts{count} || $opts{COUNT};
	my $ftid       = $opts{ftid};

	if ( ref($ftid) =~ /array/i ) {
		$ftid = undef unless @$ftid;
	}
	my @dsids;
	push @dsids, $dataset_id if $dataset_id;
	if ($genome_id) {
		my $genome =
		  CoGeX->dbconnect( get_defaults() )->resultset('Genome')
		  ->find($genome_id);
		push @dsids, map { $_->id } $genome->datasets if $genome;
	}
	if ($count_flag) {

		#        return $self->resultset('Feature')->count(
		#            {
		#                "me.chromosome" => $chr,
		#                "me.dataset_id" => [@dsids],
		#                -and            => [
		#                    "me.start" => { "<=" => $stop },
		#                    "me.stop"  => { ">=" => $start },
		#                ],
		#
		#                #  -and=>[
		#                # 	  -or=>[
		#                # 		-and=>[
		#                # 		       "me.stop"=>  {"<=" => $stop},
		#                # 		       "me.stop"=> {">=" => $start},
		#                # 		      ],
		#                # 		-and=>[
		#                # 		       "me.start"=>  {"<=" => $stop},
		#                # 		       "me.start"=> {">=" => $start},
		#                # 		      ],
		#                # 		-and=>[
		#                # 		       "me.start"=>  {"<=" => $start},
		#                # 		       "me.stop"=> {">=" => $stop},
		#                # 		      ],
		#                # 	       ],
		#                # 	 ],
		#            },
		#            {
		#
		#                #						   prefetch=>["locations", "feature_type"],
		#            }
		#        );
		return get_features_count(
			chromosome => $chr,
			dataset_id => \@dsids,
			start      => $start,
			stop       => $stop
		);
	}

	#    my %search = (
	#        "me.chromosome" => $chr,
	#        "me.dataset_id" => [@dsids],
	#        -and            => [
	#            "me.start" => { "<=" => $stop },
	#            "me.stop"  => { ">=" => $start },
	#        ],
	#
	#        # -and=>[
	#        # 	-or=>[
	#        # 	      -and=>[
	#        # 		     "me.stop"=>  {"<=" => $stop},
	#        # 		     "me.stop"=> {">=" => $start},
	#        # 		    ],
	#        # 	      -and=>[
	#        # 		     "me.start"=>  {"<=" => $stop},
	#        # 		     "me.start"=> {">=" => $start},
	#        # 		    ],
	#        # 	      -and=>[
	#        # 		     "me.start"=>  {"<=" => $start},
	#        # 		     "me.stop"=> {">=" => $stop},
	#        # 		    ],
	#        # 	     ],
	#        #      ]
	#    );
	#    $search{"me.feature_type_id"} = { "IN" => $ftid } if $ftid;
	#    my @feats = $self->resultset('Feature')->search(
	#        \%search,
	#        {
	#
	#            #					     prefetch=>["locations", "feature_type"],
	#            #						     order_by=>"me.start",
	#        }
	#    );
	print STDERR "get_features_in_region\n";
	my %search = (
		dataset_id => \@dsids,
		chromosome => $chr,
		start      => $start,
		stop       => $stop
	);
	$search{type} = $ftid if $ftid;
	my $features = get_features(%search);

	#    return wantarray ? @feats : \@feats;
	return wantarray ? @{$features} : $features;
}

# apparently not used
#sub get_features_in_region_split {
#    my $self = shift;
#    my %opts = @_;
#    my $start =
#         $opts{'start'}
#      || $opts{'START'}
#      || $opts{begin}
#      || $opts{BEGIN};
#    $start = 0 unless $start;
#    my $stop = $opts{'stop'} || $opts{STOP} || $opts{end} || $opts{END};
#    $stop = $start unless defined $stop;
#    my $chr = $opts{chr};
#    $chr = $opts{chromosome} unless defined $chr;
#    my $dataset_id =
#         $opts{dataset}
#      || $opts{dataset_id}
#      || $opts{info_id}
#      || $opts{INFO_ID}
#      || $opts{data_info_id}
#      || $opts{DATA_INFO_ID};
#
#    my @startfeats = $self->resultset('Feature')->search(
#        {
#            "me.chromosome" => $chr,
#            "me.dataset_id" => $dataset_id,
#            -and            => [
#                "me.stop" => { ">=" => $start },
#                "me.stop" => { "<=" => $stop },
#            ],
#        },
#        { prefetch => [ "locations", "feature_type" ], }
#    );
#    my @stopfeats = $self->resultset('Feature')->search(
#        {
#            "me.chromosome" => $chr,
#            "me.dataset_id" => $dataset_id,
#            -and            => [
#                "me.start" => { ">=" => $start },
#                "me.start" => { "<=" => $stop },
#            ],
#        },
#        { prefetch => [ "locations", "feature_type" ], }
#    );
#
#    my %seen;
#    my @feats;
#
#    foreach my $f (@startfeats) {
#        if ( not exists $seen{ $f->id() } ) {
#            $seen{ $f->id() } += 1;
#            push( @feats, $f );
#        }
#    }
#
#    foreach my $f (@stopfeats) {
#        if ( not exists $seen{ $f->id() } ) {
#            $seen{ $f->id() } += 1;
#            push( @feats, $f );
#        }
#    }
#
#    return wantarray ? @feats : \@feats;
#}

# apparently not used
################################################# subroutine header begin ##
#
#=head2 count_features_in_region
#
# Usage     : $object->count_features_in_region(start   => $start,
#                                             stop    => $stop,
#                                             chr     => $chr,
#                                             dataset_id => $dataset->id());
#
# Purpose   : counts the features in a specified genomic region
# Returns   : an integer
# Argument  : start   => genomic start position
#             stop    => genomic stop position
#             chr     => chromosome
#             dataset_id => dataset id in database (obtained from a
#                        CoGe::Dataset object)
#                        of the dna seq will be returned
# Throws    : none
# Comments  :
#
#See Also   :
#
#=cut
#
################################################### subroutine header end ##
#
#sub count_features_in_region {
#    my $self = shift;
#    my %opts = @_;
#    return $self->get_features_in_region( %opts, count => 1 );
#}

################################################ subroutine header begin ##

=head2 get_total_chromosomes_length

 Usage     :
 Purpose   :
 Returns   : the sum of the lengths of chromosomes
 Argument  : id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_total_chromosomes_length {
	my $results = search(
		'features',
		{ dataset => shift, type => 4 },
		{
			aggs        => { length => { sum => { field => 'stop' } } },
			search_type => 'count'
		}
	);
	return $results->{aggregations}->{length}->{value};
}

################################################ subroutine header begin ##

=head2 get_type_counts

 Usage     :
 Purpose   : get the counts for each different feature type for one or more datasets
 Returns   : a hash of feature_type_id => count
 Argument  : id(s) of the dataset(s) - required
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_type_counts {
	my $results = search(
		'features',
		{ dataset => shift },
		{
			aggs        => { count => { terms => { field => 'type' } } },
			search_type => 'count'
		}
	);
	my %counts;
	foreach ( @{ $results->{aggregations}->{count}->{buckets} } ) {
		$counts{ $_->{key} } = $_->{doc_count};
	}
	return \%counts;
}

################################################ subroutine header begin ##

=head2 options

 Usage     :
 Purpose   :
 Returns   : the options hash ref to pass to search
 Argument  : hash ref of options for query
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub options {
	my $opts   = shift;
	my $size   = $opts->{size};      # max size of result set
	my $sort   = $opts->{sort};      # optional sorting
	my $source = $opts->{_source};
	my %options;
	$options{size}    = $size   if $size;
	$options{sort}    = $sort   if $sort;
	$options{_source} = $source if $source;
	return \%options;
}

################################################ subroutine header begin ##

=head2 query

 Usage     :
 Purpose   :
 Returns   : the query hash ref to pass to search
 Argument  : hash ref of things to query
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub query {
	my $opts       = shift;
	my $dataset_id = $opts->{dataset_id};  # dataset id or array ref of ids
	my $name       = $opts->{name};        # feature name or array ref of names
	my $annotation = $opts->{annotation};  # annotation string or array ref of strings
	my $type_id    = $opts->{type_id};     # feature type id or array ref of ids
	my $chromosome = $opts->{chromosome} || $opts->{chr};
	my $start      = $opts->{start};
	my $stop       = $opts->{stop};
	my %query;
	$query{dataset}      = $dataset_id if $dataset_id;
	$query{'names.name'} = $name       if $name;
	$query{'annotations.annotation'} = $annotation if $annotation;
	$query{type}         = $type_id    if $type_id;
	$query{chromosome}   = $chromosome if defined $chromosome;

	if ( defined $start ) {
		$stop = $start unless defined $stop;
		$query{start} = { 'lte' => $stop };
		$query{stop}  = { 'gte' => $start };
	}
	return \%query;
}

1;
