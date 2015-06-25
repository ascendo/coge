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

=head2 new

 Usage     :
 Purpose   :
 Returns   : newly instantiated object for this class
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub new {
	my ($class) = @_;
	my $self = {};
	return bless $self, $class;
}

################################################ subroutine header begin ##

=head2 count

 Usage     :
 Purpose   :
 Returns   : number of chromosomes for the genome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub count {
	my $self = shift;
	while ($self->next) {
	}
	return $self->{lines};
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
	my $json_encoder = JSON::XS->new->allow_nonref;
    my $dbh = CoGeX->dbconnect(get_defaults())->storage->dbh;
    my $query = 'SELECT feature_id,feature_type_id,dataset_id,start,stop,strand,chromosome FROM feature LIMIT ' . $limit;
    if ($offset) {
    	$query .= ' OFFSET ' . $offset;
    }
    my $features = $dbh->prepare($query);
    $features->execute;
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
			$json .= '{"name":' . $json_encoder->encode($name->[0]);
			if ($name->[1]) {
				$json .= ',"description":' . $json_encoder->encode($name->[1]);
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

=head2 find

 Usage     : 
 Purpose   : iterates through list and stops when matching chromosome is found
 Returns   : 1 if found, 0 otherwise
 Argument  : name of chromosome to find (required)
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub find {
	my $self = shift;
	my $name = shift;
	while ($self->next) {
		if ($name eq $self->name) {
			return 1;
		}
	}
	return 0;
}

sub get_dataset_features {
	my $dataset_id = shift;
	print "dataset_id: $dataset_id\n";
	my $json = elasticsearch_post('coge/features/_search','{"query":{"filtered":{"filter":{"term":{"dataset":' .  $dataset_id . '}}}}}}');
	my $o = JSON::XS->new->decode($json);
	print Dumper $o;
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

=head2 length

 Usage     :
 Purpose   : 
 Returns   : length of current chromosome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub length {
	my $self = shift;
	return $self->{tokens}[1];
}

################################################ subroutine header begin ##

=head2 lengths

 Usage     :
 Purpose   : 
 Returns   : array of lengths of all chromosomes for the genome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub lengths {
	my $self = shift;
	my @a;
	while ($self->next) {
		push @a, $self->length;
	}
    return wantarray ? @a : \@a;
}

################################################ subroutine header begin ##

=head2 name

 Usage     :
 Purpose   : 
 Returns   : name of current chromosome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub name {
	my $self = shift;
	my $name = $self->{tokens}[0];
	my $index = index($name, '|');
	if ($index != -1) {
		$name = substr($name, $index + 1);
	}
	return $name;
}

################################################ subroutine header begin ##

=head2 names

 Usage     :
 Purpose   : 
 Returns   : array of names of all chromosomes for the genome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub names {
	my $self = shift;
	my @a;
	while ($self->next) {
		push @a, $self->name;
	}
    return wantarray ? @a : \@a;
}

################################################ subroutine header begin ##

=head2 next

 Usage     :
 Purpose   : set the current chromosome to be the next one in the list
 Returns   : 1 if new chromosome is current, 0 if no more chromosomes available
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub next {
	my $self = shift;
	if (!$self->{fh}) {
		print STDERR caller . "\n";
	}
	my $line = readline($self->{fh});
	if ($line) {
		my @tokens = split('\t', $line);
		@{$self->{tokens}} = @tokens;
		$self->{lines}++;
		return 1;
	}
	close($self->{fh});
	$self->{fh} = 0;
	return 0;
}

################################################ subroutine header begin ##

=head2 offset

 Usage     :
 Purpose   : 
 Returns   : offset of current chromosome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub offset {
	my $self = shift;
	return $self->{tokens}[2];
}

################################################ subroutine header begin ##

=head2 total_length

 Usage     :
 Purpose   : 
 Returns   : length of all chromosomes for the genome
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub total_length {
	my $self = shift;
	my $length = 0;
	while ($self->next) {
		$length += $self->length;
	}
    return $length;
}

1;
