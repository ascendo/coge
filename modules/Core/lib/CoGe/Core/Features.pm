package CoGe::Core::Features;

BEGIN {
	use Exporter 'import';
	our @EXPORT_OK = qw( get_chromosome_count get_feature get_features get_total_chromosomes_length get_type_counts );
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
use CoGe::Core::Elasticsearch qw(build_filter build_terms_filter elasticsearch_get elasticsearch_post);
use CoGeX;
use Data::Dumper;
use Encode qw(encode);
use JSON::XS;

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
 Argument  : id of the dataset
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosome_count {
	return get_type_count(shift, 4); # 4 is the feature_type_id for chromosomes
}

################################################ subroutine header begin ##

=head2 get_chromosomes

 Usage     :
 Purpose   :
 Returns   : array of the chromosome features for the dataset
 Argument  : id of the dataset, options - optional hash passed on to get_features
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_chromosomes {
	my $search = { dataset => shift, type => 4 }; # 4 is the feature_type_id for chromosomes
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
	my $json = elasticsearch_get('coge/features/' . shift);
	my $o = decode_json($json);
	my $feature = $o->{_source};
	$feature->{id} = $o->{_id};
	return bless($feature, 'CoGe::Core::Feature');
}

################################################ subroutine header begin ##

=head2 get_features

 Usage     : 
 Purpose   : get all features for a dataset
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
	my $data '{';
	my $size = 10000000;

	if ($options) {
		$size = $options->{size} if $options->{size};
		if ($options->{sort}) {
			my $sort = encode_json($options->{sort});
			if (substr($sort, 0, 1) ne '[') {
				$sort = '[' . $sort . ']';
			}
			$data .= '"sort":' . $sort . ',';
		}
	}
	$data .= '"query":{"filtered":{"filter":' . build_filter($search) . '}},"size":' . $size . '}';
	my $json = elasticsearch_post('coge/features/_search?search_type=scan&scroll=1m', $data);
	my $o = decode_json($json);
	$json = elasticsearch_post('_search/scroll?scroll=1m', $o->{_scroll_id});
	$o = decode_json($json);
	my @hits;
	foreach (@{$o->{hits}->{hits}}) {
		my $feature = $_->{_source};
		$feature->{id} = $_->{_id};
		push (@hits, bless($feature, 'CoGe::Core::Feature'));
	}
	my $hits = @hits;
	return @hits;
}

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
	my $search = { dataset => shift, type => 4 }; # 4 is feature_type_id of chromosomes
	my $json = elasticsearch_post('coge/features/_search?search_type=count','{"query":{"filtered":{"filter":' . build_filter($search) . '}},"aggs":{"length":{"sum":{"field":"stop"}}}}');
	my $o = decode_json($json);
	return $o->{aggregations}->{length}->{value};
}

################################################ subroutine header begin ##

=head2 get_type_count

 Usage     :
 Purpose   :
 Returns   : the number of features of the passed in type for the dataset
 Argument  : id of the dataset, type id
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_type_count {
	my $search = { dataset => shift, type => shift };
	my $json = elasticsearch_post('coge/features/_search?search_type=count','{"query":{"filtered":{"filter":' . build_filter($search) . '}}}');
	my $o = decode_json($json);
	return $o->{hits}->{total};
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
	my $json = elasticsearch_post('coge/features/_search?search_type=count','{"query":{"filtered":{"filter":' . build_terms_filter('dataset', @_) . '}},"aggs":{"count":{"terms":{"field":"type"}}}}');
	my $o = decode_json($json);
	my %counts;
	foreach (@{$o->{aggregations}->{count}->{buckets}}) {
		$counts{$_->{key}} = $_->{doc_count};
	}
	return %counts;
}

1;
