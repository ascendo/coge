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

use CoGe::Accessory::genetic_code;
use CoGe::Accessory::Web qw(get_defaults);
use CoGeX;
use Data::Dumper;
use DBI;
use JSON::XS;
use LWP::UserAgent;

use base 'Class::Accessor';
__PACKAGE__->mk_accessors( '_genomic_sequence', 'gst', 'dsg', 'trans_type' ); #_genomic_sequence =>place to store the feature's genomic sequence with no up and down stream stuff

################################################ subroutine header begin ##

=head2 codon_frequency

 Usage     :
 Purpose   :
 Returns   :
 Argument  : gstid - optional
 Throws    :
 Comments  :
           :

See Also   :

=cut

################################################## subroutine header end ##

sub codon_frequency {
	my $self      = shift;
	my %opts      = @_;
	my $gstid     = $opts{gstid};
	my ( $code, $code_type ) = $self->genetic_code;
	my %codon = map { $_ => 0 } keys %$code;
	my $seq = $self->genomic_sequence( gstid => $gstid );
	my $x   = 0;

	while ( $x < CORE::length($seq) ) {
		$codon{ uc( substr( $seq, $x, 3 ) ) }++;
		$x += 3;
	}
	return \%codon, $code_type;
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
		my $dbh = CoGeX->dbconnect(get_defaults())->storage->dbh;
		my $annotation = $dbh->selectrow_arrayref('SELECT annotation FROM feature_annotation WHERE feature_id=' . $self->{id} . ' AND annotation_type_id=10973'); # 10973 is id for annotation type transl_table
		$trans_type = $annotation->[0] if ($annotation);
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
	my $json = elasticsearch_post('coge/features/_search','{"query":{"filtered":{"filter":{"term":' . encode_json(\%opts) . '}}},"size":1000000}');
	my $o = decode_json($json);
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
	my $dbh = CoGeX->dbconnect(get_defaults())->storage->dbh;
	my $genome = $dbh->selectrow_arrayref('SELECT genome_id FROM dataset_connector WHERE dataset_id=' . $self->{dataset});
	my $organism = $dbh->selectrow_arrayref('SELECT organism_id FROM genome WHERE genome_id =' . $genome->[0]);
	my $values = $dbh->selectrow_arrayref('SELECT name,description FROM organism WHERE organism_id =' . $organism->[0]);
	return (name => $values->[0], description => $values->[1]);
}

1;
