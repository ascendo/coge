package CoGe::Core::Elasticsearch;

use Data::Dumper;
use LWP::UserAgent;
use Search::Elasticsearch;
use ElasticSearch::SearchBuilder;
use CoGe::Accessory::Web qw(get_defaults);

BEGIN {
    use Exporter 'import';
    @EXPORT_OK = qw( 
        build_and_filter build_filter elasticsearch_get elasticsearch_post 
        search get
    );
}

our $DEBUG = 1;

################################################ subroutine header begin ##

=head2 build_and_filter

 Usage     : 
 Purpose   :
 Returns   : JSON for filter
 Argument  : hash of one or more terms
 Throws    :
 Comments  : if more than one term is passed in, an "and" filter will be built

See Also   :

=cut

################################################## subroutine header end ##

sub build_and_filter {
	return build_filters_filter('and', shift);
}

################################################ subroutine header begin ##

=head2 build_filter

 Usage     : 
 Purpose   :
 Returns   : JSON for a filter of one or more terms 
 Argument  : field, value(s)
 Throws    :
 Comments  : if more than one term is passed in, a "terms" filter will be built, otherwise a boolean, range or "term" filter will be built

See Also   :

=cut

################################################## subroutine header end ##

sub build_filter {
	my $field = shift;
	my $value = shift;
	if (ref($value) eq 'ARRAY') {
		if (scalar @{$value} == 1) {
			return { term => { $field => $value->[0] } };
		}
		return { terms => { $field => $value } };
	}
	if (ref($value) eq 'HASH') {
		return { range => { $field => $value}};
	}
	if ($field eq 'and') {
		return build_filters_filter('and', $value);
	}
	if ($field eq 'not') {
		my @keys = keys %$value;
		my $key = $keys[0];
		return {not => build_filter($key, $value->{$key}) };
	}
	if ($field eq 'or') {
		return build_filters_filter('or', $value);
	}
	return { term => { $field => $value } };
}

################################################ subroutine header begin ##

=head2 build_filters_filter

 Usage     : 
 Purpose   :
 Returns   : JSON for filter
 Argument  : type - string ('and','or',etc)
             hash of one or more filters
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub build_filters_filter {
	my $type = shift;
	my $filters = shift;
	my $array;
	my $json = '{"' . $type . '":[';
	for my $key (keys %$filters) {
		push @$array, build_filter($key, $filters->{$key});
	}
	return { $type => $array };
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
	if (!$res->is_success()) {
		print STDERR "error with elasticsearch_post: $path\n$content\n";
		print STDERR $res->content . "\n";
	}
	return $res->content;
}

################################################ subroutine header begin ##

=head2 get_ids

 Usage     : 
 Purpose   : get the next set of ids for new features
 Returns   : the last new id, so set = [last_id-num_ids+1 .. last_id]
 Argument  : type - name of the document type to get ids for
 			 num_ids - the number of ids you want
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_ids {
	my $type = shift;
	my $num_ids = shift;
	my $json = elasticsearch_post("sequence/$type/1/_update?fields=iid&retry_on_conflict=5", qq({
		"script": "ctx._source.iid += bulk_size",
		"params": {"bulk_size": $num_ids},
		"lang": "groovy"
	}));
	return $json =~ /\[([^\]]*)\]/;
}

################################################ subroutine header begin ##

=head2 init_ids

 Usage     : 
 Purpose   : initialize id system for a document type
 Returns   : 
 Argument  : type - name of document type that will use ids
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub init_ids {
	my $type = shift;
	elasticsearch_post('sequence', qq({
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
 	print elasticsearch_post("sequence/$type/1",'{"iid": 0}');
}

################################################ subroutine header begin ##

=head2 search

 Usage     : 
 Purpose   : Search using the given query/type
 Returns   : 
 Argument  : 
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##
sub search {
    my $type  = shift;
    my $query = shift;
    my $class = shift; # optional class name to cast result
    return unless ($query && $type);
    
    # Get configuration settings
    my $index = get_defaults()->{ELASTICSEARCH_INDEX};
    my $url = get_defaults()->{ELASTICSEARCH_URL};
    unless ($index && $url) {
        warn 'Elasicsearch::search: ERROR: missing required configuration params!';
        return;
    }
    
    # Build query
    my $sb = ElasticSearch::SearchBuilder->new();
    my $dsl = $sb->filter($query);
    unless ($dsl) {
        warn "Elasticsearch::search: ERROR: invalid query:\n", Dumper $query;
        return;
    }
    
    # Execute query
    my $es = Search::Elasticsearch->new(nodes => $url);
    my $results = $es->search(
        index  => $index,
        type   => $type,
        scroll => '1m', #FIXME is this correct/necessary?
        body   => $dsl
    );
    unless ($results) {
        warn 'Elasticsearch::search: ERROR: null results';
        return;
    }    
    
    # Format results
    my @results;
    foreach (@{$results->{hits}->{hits}}) {
        my $result = $_->{_source};
        $result->{id} = $_->{_id};
        bless($result, $class) if $class;
        push @results, $result;
    }
    
    return wantarray ? @results : \@results;
}

################################################ subroutine header begin ##

=head2 get

 Usage     : 
 Purpose   : Get document by ID
 Returns   : 
 Argument  : 
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get {
    my $type = shift;
    my $id = shift;
    my $class = shift; # optional class name to cast result
    
    # Get configuration settings
    my $index = get_defaults()->{ELASTICSEARCH_INDEX};
    my $url = get_defaults()->{ELASTICSEARCH_URL};
    unless ($index && $url) {
        warn 'Elasicsearch::search: ERROR: missing required configuration params!';
        return;
    }
    
    # Get document
    my $es = Search::Elasticsearch->new(nodes => $url);
    my $doc = $es->get(
        index   => $index,
        type    => $type,
        id      => $id
    );
    
    # Format result
    my $result = $doc->{_source};
    $result->{id} = $doc->{_id};
    bless($result, $class) if $class;
    
    return $result;
}

1;
