package CoGe::Core::Features;

BEGIN {
	use Exporter 'import';
	our @EXPORT_OK = qw( get_chromosome_count get_chromosomes get_feature get_features get_features_ids get_features_in_region get_total_chromosomes_length get_type_counts );
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
use CoGe::Core::Elasticsearch qw(build_and_filter build_filter elasticsearch_get elasticsearch_post);
use CoGeX;
use Data::Dumper;
use Encode qw(encode);
use JSON::XS;
use Search::Elasticsearch;

our $DEBUG = 1;

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
	my $index = shift || 'coge'; # optional index name
	
    my $dbh = CoGeX->dbconnect(get_defaults())->storage->dbh;
    my $query = 'SELECT feature_id,feature_type_id,dataset_id,start,stop,strand,chromosome FROM feature WHERE dataset_id=' . $dataset_id;
    my $features = $dbh->prepare($query);
    $features->execute;
    copy_rows($features, $dbh, $index);
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
	my $index = shift || 'coge'; # optional index name
	my $e = Search::Elasticsearch->new();
	
    while (my $feature = $features->fetchrow_arrayref) {
    	my $feature_id = $feature->[0];
    	my $body = { type => int $feature->[1], dataset => int $feature->[2] };
		if ($feature->[3]) {
			$body->{start} = int $feature->[3];
		}
		if ($feature->[4]) {
			$body->{stop} = int $feature->[4];
		}
		if ($feature->[5]) {
			$body->{strand} = int $feature->[5];
		}
		if ($feature->[6]) {
			$body->{chromosome} = $feature->[6];
		}
	    my $db_names = $dbh->prepare('SELECT name,description,primary_name FROM feature_name WHERE feature_id=' . $feature_id);
	    $db_names->execute;
	    my $names;
	    while (my $db_name = $db_names->fetchrow_arrayref) {
	    	my $name = { name => $db_name->[0]};
			if ($db_name->[1]) {
				$name->{description} = $db_name->[1];
			}
			if ($db_name->[2]) {
				$name->{primary} = 1;
			}
			push @$names, $name;
		}
		if ($names) {
			$body->{names} = $names;
		}
	    my $db_locations = $dbh->prepare('SELECT start,stop,strand,chromosome FROM location WHERE feature_id=' . $feature_id);
	    $db_locations->execute;
	    my $locations;
	    while (my $db_location = $db_locations->fetchrow_arrayref) {
			push @$locations, { start => int $db_location->[0], stop => int $db_location->[1], strand => int $db_location->[2], chromosome => $db_location->[3] };
		}
		if ($locations) {
			$body->{locations} = $locations;
		}
	    my $db_annotations = $dbh->prepare('SELECT annotation,annotation_type_id,link FROM feature_annotation WHERE feature_id=' . $feature_id);
	    $db_annotations->execute;
	    my $annotations;
	    while (my $db_annotation = $db_annotations->fetchrow_arrayref) {
			my $annotation = { annotation => $db_annotation->[0], type => int $db_annotation->[1] };
			if ($db_annotation->[2]) {
				$annotation->{link} = $annotation->[2];
			}
			push @$annotations, $annotation;
		}
		if ($annotations) {
			$body->{annotations} = $annotations;
		}
		print $feature_id . ' ';
		
		$e->index( index => $index, type => 'features', id => $feature_id, body => $body );
	}
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

=head2 get_chromosome_count

 Usage     :
 Purpose   :
 Returns   : the number of chromosome features for the dataset
 Argument  : search hash, must contain at least dataset => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosome_count {
	my $search = shift;
	$search->{type} = 4; # 4 is the feature_type_id for chromosomes
	return get_features_count($search);
}

################################################ subroutine header begin ##

=head2 get_chromosomes

 Usage     :
 Purpose   :
 Returns   : array of the chromosome features for the dataset
 Argument  : search hash, must contain at least dataset => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosomes {
	my $search = shift;
	$search->{type} = 4; # 4 is the feature_type_id for chromosomes
	return get_features($search, shift);
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
	my $id = shift;
	my $index = shift || 'coge'; # optional index name
	
	my $json = elasticsearch_get($index . '/features/' . $id . '/_source');
	my $feature = decode_json($json);
	$feature->{id} = $id;
	return bless($feature, 'CoGe::Core::Feature');
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
	my $search = shift;
	my $options = shift;
	my $index = shift || 'coge'; # optional index name
	my $body = {
		query => {
			filtered => {
				filter => build_and_filter($search)
			}
		},
		size => 10000000
	};
	if ($options) {
		$body->{size} = $options->{size} if $options->{size};
		$body->{sort} = $options->{sort} if $options->{sort};
	}
	my $e = Search::Elasticsearch->new();
	my $results = $e->search(
		index => 'coge',
		type => 'features',
		body => $body
	);
	my @hits;
	foreach (@{$results->{hits}->{hits}}) {
		my $feature = $_->{_source};
		$feature->{id} = $_->{_id};
		push(@hits, bless($feature, 'CoGe::Core::Feature'));
	}
	if (!@hits && $DEBUG) {
		print STDERR 'no hits for query: ' . Dumper \$body;
	}
	return wantarray ? @hits : \@hits;
}

################################################ subroutine header begin ##

=head2 get_features_ids

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

sub get_features_ids {
	my $search = shift;
	my $json = elasticsearch_post('coge/features/_search', '{"query":{"filtered":{"filter":' . build_and_filter($search) . '}},"size":10000000}');
	my $o = decode_json($json);
	my @ids;
	foreach (@{$o->{hits}->{hits}}) {
		push (@ids, $_->{_id});
	}
	return \@ids;
}

################################################ subroutine header begin ##

=head2 get_features_count

 Usage     :
 Purpose   :
 Returns   : the number of features of the passed in type for the dataset
 Argument  : search hash, must contain at least dataset => id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_features_count {
	my $e = Search::Elasticsearch->new();
	return $e->count(
		index => 'coge',
		type => 'features',
		body => {
			query => {
				filtered => {
					filter => build_and_filter(shift)
				}
			}
		}
	)->{count};
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
#    my $count_flag = $opts{count} || $opts{COUNT};
    my $ftid       = $opts{ftid};

    if ( ref($ftid) =~ /array/i ) {
        $ftid = undef unless @$ftid;
    }
    my @dsids;
    push @dsids, $dataset_id if $dataset_id;
    if ($genome_id) {
        my $genome = CoGeX->dbconnect(get_defaults())->resultset('Genome')->find($genome_id);
        push @dsids, map { $_->id } $genome->datasets if $genome;
    }
#    if ($count_flag) {
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
		return get_features_count(chromosome => $chr, dataset => \@dsids, -and => [{start => { 'lte' => $stop}}, {stop => { 'gte' => $start }}]);
#    }
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
    my %search = (chromosome => $chr, dataset => \@dsids, -and => [{start => { 'lte' => $stop}}, {stop => { 'gte' => $start }}]);
    $search{type} = $ftid if $ftid;
	my $features =  get_features(%search);
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
	my $e = Search::Elasticsearch->new();
	my $results = $e->search(
		index => 'coge',
		type => 'features',
		body => {
			query => {
				filtered => {
					filter => {
						and => [
							{ term => { dataset => shift } },
							{ term => { type => 4 } } # 4 is feature_type_id of chromosomes
						]
					}
				}
			},
			aggs => {
				length => {
					sum => {
						field => 'stop'
					}
				}
			}
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
	my $e = Search::Elasticsearch->new();
	my $results = $e->search(
		index => 'coge',
		type => 'features',
		search_type => 'count',
		body => {
			query => {
				filtered => {
					filter => build_filter('dataset', shift)
				}
			},
			aggs => {
				count => {
					terms => {
						field => 'type'
					}
				}
			}
		}
	);
	my %counts;
	foreach (@{$results->{aggregations}->{count}->{buckets}}) {
		$counts{$_->{key}} = $_->{doc_count};
	}
	
	return \%counts;
}

1;
