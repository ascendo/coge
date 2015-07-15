package CoGe::Core::Features;

=head1 NAME

CoGe::Core::Features

=head1 SYNOPSIS

provides class for accessing feature data from files (features.json)

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
use CoGeX;
use Data::Dumper;
use DBI;
use JSON::XS;
use LWP::UserAgent;

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
		$json .= '"type":' . $feature->[1] . ',"dataset":' . $feature->[2] . ',"start":' . $feature->[3] . ',"stop":' . $feature->[4] . ',"strand":' . $feature->[5] . ',"chromosome":"' . $feature->[6] . '"';
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
			$json .= '{"name":' . $json_xs->encode($name->[0]);
			if ($name->[1]) {
				$json .= ',"description":' . $json_xs->encode($name->[1]);
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
		$json .= ']}';
		print elasticsearch_post('coge/features/' . $feature_id, $json);
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

=head2 elasticsearch_get

 Usage     : 
 Purpose   : send an elasticsearch GET request
 Returns   : JSON returned by request
 Argument  : path for request URL
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub elasticsearch_get {
	my $path = shift;
	my $req = HTTP::Request->new(GET => 'http://localhost:9200/' . $path);
	my $ua = LWP::UserAgent->new;
	my $res = $ua->request($req);
	return $res->content;
}

################################################ subroutine header begin ##

=head2 elasticsearch_post

 Usage     : 
 Purpose   : send an elasticsearch POST request
 Returns   : JSON returned by request
 Argument  : path for request URL, JSON to send as data for request
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub elasticsearch_post {
	my $path = shift;
	my $content = shift;
	my $req = HTTP::Request->new(POST => 'http://localhost:9200/' . $path);
	$req->header( 'Content-Type' => 'application/json' );
	$req->content($content);
	my $ua = LWP::UserAgent->new;
	my $res = $ua->request($req);
	return $res->content;
}

################################################ subroutine header begin ##

=head2 get_ids

 Usage     : 
 Purpose   : get the next set of ids for new features
 Returns   : the last new id, so set = [last_id-num_ids+1 .. last_id]
 Argument  : num_ids - the number of ids you want
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_ids {
	my $num_ids = shift;
	my $json = elasticsearch_post('sequence/sequence/1/_update?fields=iid&retry_on_conflict=5', qq({
		"script": "ctx._source.iid += bulk_size",
		"params": {"bulk_size": $num_ids},
		"lang": "groovy"
	}));
	return $json =~ /\[([^\]]*)\]/;
}

################################################ subroutine header begin ##

=head2 get_feature_counts

 Usage     :
 Purpose   : get the counts for each different feature type
 Returns   : a hash of feature_type_id => count
 Argument  : dataset_id - required
 			 chromosome - optional, to only return features from one chromosome
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_feature_counts {
	my %opts      = @_;
	my $json_xs = JSON::XS->new->allow_nonref;
	print STDERR $json_xs->encode(\%opts);
	my $json = elasticsearch_post('coge/features/_search','{"query":{"filtered":{"filter":{"term":' . $json_xs->encode(\%opts) . '}}},"size":1000000}');
	my $o = $json_xs->decode($json);
	my %counts;
	foreach (@{$o->{hits}->{hits}}) {
		$counts{$_->{_source}->{type}}++;
	}
	return %counts;
}

################################################ subroutine header begin ##

=head2 get_features

 Usage     : 
 Purpose   : get all features for a dataset
 Returns   : array of feature hashes
 Argument  : dataset_id - required
 			 chromosome - optional, to only return features from one chromosome
 			 type - optional, feature_type_id, to only return features of the specified type
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_features {
	my %opts      = @_;
	my $json_xs = JSON::XS->new->allow_nonref;
	my $json = elasticsearch_post('coge/features/_search','{"query":{"filtered":{"filter":{"term":' . $json_xs->encode(\%opts) . '}}},"size":1000000}');
	my $o = $json_xs->decode($json);
	my @hits;
	foreach (@{$o->{hits}->{hits}}) {
		push (@hits, $_->{_source});
	}
	return @hits;
}

################################################ subroutine header begin ##

=head2 init

 Usage     : 
 Purpose   : create index in elasticsearch
 Returns   : 
 Argument  : 
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub init {
	elasticsearch_post('sequence', q({
     "settings": {
         "number_of_shards": 1,
         "auto_expand_replicas": "0-all"
     },
     "mappings": {
         "sequence": {
             "_all": {"enabled": 0},
             "_type": {"index": "no"},
             "dynamic": "strict",
             "properties": {
                 "iid": {
                     "type": "string",
                     "index": "no"
                 }
             }
         }
     }
 }));
 	elasticsearch_post('sequence/sequence/1','{"iid": 0}');
}

1;
