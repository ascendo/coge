package CoGe::Core::Elasticsearch;

use Data::Dumper;
use Devel::StackTrace;
use LWP::UserAgent;
use Search::Elasticsearch;
use ElasticSearch::SearchBuilder;
use CoGe::Accessory::Web qw(get_defaults);

BEGIN {
	use Exporter 'import';
	@EXPORT_OK = qw(bulk_index get search search_exists);
}

our $DEBUG = 1;

################################################ subroutine header begin ##

=head2 _get_settings

 Usage     :
 Purpose   :
 Returns   : index name and url for elasticsearch from config
 Argument  :
 Throws    :
 Comments  : internal sub for this module

See Also   :

=cut

################################################## subroutine header end ##

sub _get_settings {
	my $conf  = get_defaults();
	my $index = $conf->{ELASTICSEARCH_INDEX};
	my $url   = $conf->{ELASTICSEARCH_URL};
	unless ( $index && $url ) {
		warn 'Elasicsearch: ERROR: missing required configuration params!';
		return;
	}
	return ( $url, $index );
}

################################################ subroutine header begin ##

=head2 bulk_index

 Usage     : 
 Purpose   : Bulk index a set of documents
 Returns   : 
 Argument  : 
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub bulk_index {
	my $type = shift;    # type name
	my $docs = shift;    # ref to array of documents
	my $ids = shift;     # array ref of doc ids, optional. will generate ids if not passed in
	return unless ( $type && $docs );
	my ( $url, $index ) = _get_settings();
	my $num_docs = scalar(@$docs);

	# Connect and create helper
	my $es = Search::Elasticsearch->new( nodes => $url );
	my $bulk = $es->bulk_helper(
		index       => $index,
		type        => $type,
		max_count   => 0,        #10_000, # batch size
		max_size    => 0,
		on_conflict => sub {
			my ( $action, $response, $i, $version ) = @_;
			warn 'Elasticsearch::bulk_index CONFLICT';
		},
		on_error => sub {
			my ( $action, $response, $i ) = @_;
			warn 'Elasticsearch::bulk_index ERROR';
			warn Dumper $action;
			warn Dumper $response;
		},

		#        on_success => sub {
		#            my ($action,$response,$i) = @_;
		#            warn 'Elasticsearch::bulk_index SUCCESS';
		#        },
	);

	if ($ids) {
		for (my $i=0; $i<$num_docs; $i++) {
			warn Dumper $docs->[$i];
			$bulk->index({ id => $ids->[$i], source => $docs->[$i]})
		}
	} else {
		# Allocate unique ID's for documents
		my $last_id = get_ids( $type, $num_docs );
		my $id = $last_id - $num_docs + 1;
		# Add documents
		foreach my $source (@$docs) {
			my $doc = {
				id     => $id++,
				source => $source
			};
			$bulk->index($doc);
		}
	}
	my $result = $bulk->flush;
	if (   !$result
		|| !$result->{items}
		|| scalar( @{ $result->{items} } ) != $num_docs )
	{
		warn 'Elasticsearch::bulk_index: ERROR: incomplete load, indexed ',
		  scalar( @{ $result->{items} } ), ', expected ', $num_docs;

		#warn Dumper $result;
		return 0;
	}

	return 1;
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
	my $path    = shift;
	my $content = shift;
	my $req = HTTP::Request->new( POST => 'http://localhost:9200/' . $path );
	$req->header( 'Content-Type' => 'application/json' );
	$req->content($content);
	my $ua  = LWP::UserAgent->new;
	my $res = $ua->request($req);
	if ( !$res->is_success() ) {
		print STDERR "error with elasticsearch_post: $path\n$content\n";
		print STDERR $res->content . "\n";
	}
	return $res->content;
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
	my $type  = shift;
	my $id    = shift;
	my $class = shift;    # optional class name to cast result
	my ( $url, $index ) = _get_settings();

	# Get document
	my $es = Search::Elasticsearch->new( nodes => $url );
	my $doc = $es->get(
		index => $index,
		type  => $type,
		id    => $id
	);

	# Format result
	my $result = $doc->{_source};
	$result->{id} = $doc->{_id};
	bless( $result, $class ) if $class;

	return $result;
}

################################################ subroutine header begin ##

=head2 get_ids

 Usage     : 
 Purpose   : get the next set of ids for new documents of the passed in type
 Returns   : the last new id, so set = [last_id-num_ids+1 .. last_id]
 Argument  : type - name of the document type to get ids for
 			 num_ids - the number of ids you want
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub get_ids {
	my $type    = shift;
	my $num_ids = shift;
	my $json    = elasticsearch_post(
		"sequence/$type/1/_update?fields=iid&retry_on_conflict=5", qq({
		"script": "ctx._source.iid += bulk_size",
		"params": {"bulk_size": $num_ids},
		"lang": "groovy"
	})
	);

	#warn $json if $DEBUG;
	my ($last_id) = $json =~ /\[([^\]]*)\]/;
	return $last_id;
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
	elasticsearch_post(
		'sequence', qq({
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
 })
	);
	print elasticsearch_post( "sequence/$type/1", '{"iid": 0}' );
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
	my $type    = shift;
	my $query   = shift;
	my $options = shift;
	return unless ( $query && $type );

	my ( $url, $index ) = _get_settings();

	# Build query
	my $dsl;
	my $sb = ElasticSearch::SearchBuilder->new();
	$dsl = $sb->filter($query);
	unless ($dsl) {
		warn "Elasticsearch::search: ERROR: invalid query:\n", Dumper $query;
		warn Devel::StackTrace->new->as_string;
		return;
	}
	#warn Dumper $dsl if $DEBUG;

	# Execute query
	my $es = Search::Elasticsearch->new( nodes => $url );
	my $body = { query => { filtered => $dsl } };
	$body->{_source} = $options->{_source} if ( exists $options->{_source} );
	$body->{aggs}    = $options->{aggs}    if ( exists $options->{aggs} );
	my $results = $es->search(
		index       => $index,
		type        => $type,
		size        => $options->{size} || 1_000_000,
		search_type => $options->{search_type} || 'query_then_fetch',
		body        => $body
	);
	unless ($results) {
		warn 'Elasticsearch::search: ERROR: null results';
		return;
	}
	#warn Dumper $results if $DEBUG;

	return $results;
}

################################################ subroutine header begin ##

=head2 search_exists

 Usage     : 
 Purpose   : Search using the given query/type
 Returns   : if the search matches any documents
 Argument  : 
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub search_exists {
	my $type    = shift;
	my $query   = shift;
	my $options = shift;
	return unless ( $query && $type );

	my ( $url, $index ) = _get_settings();

	# Build query
	my $dsl;
	my $sb = ElasticSearch::SearchBuilder->new();
	$dsl = $sb->filter($query);
	unless ($dsl) {
		warn "Elasticsearch::search_exists: ERROR: invalid query:\n", Dumper $query;
		warn Devel::StackTrace->new->as_string;
		return;
	}
	#warn Dumper $dsl if $DEBUG;

	# Execute query
	my $es = Search::Elasticsearch->new( nodes => $url );
	my $body = { query => { filtered => $dsl } };
	my $results = $es->search_exists(
		index       => $index,
		type        => $type,
		body        => $body
	);
	return $results->{exists};
}

1;
