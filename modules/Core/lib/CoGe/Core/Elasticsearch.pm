package CoGe::Core::Elasticsearch;

BEGIN {
	use Exporter 'import';
	@EXPORT_OK = qw( build_filter build_terms_filter elasticsearch_get elasticsearch_post );
}

use LWP::UserAgent;

################################################ subroutine header begin ##

=head2 build_filter

 Usage     : 
 Purpose   :
 Returns   : JSON for filter
 Argument  : hash of one or more terms
 Throws    :
 Comments  : if more than one term is passed in, an "and" filter will be built

See Also   :

=cut

################################################## subroutine header end ##

sub build_filter {
	my %opts = @_;
	my $size = keys %opts;
	my $json;
	if ($size > 1) {
		$json = '{"and":[';
	}
	my $first = 1;
	for my $key (keys %opts) {
		if ($first) {
			$first = 0;
		} else {
			$json .= ',';
		}
		$json .= '{"term":{"' . $key . '":"' . $opts{$key} . '"}}'; # note: doesn't yet encode string values
	}
	if ($size > 1) {
		$json .= ']}';
	}
	return $json;
}

################################################ subroutine header begin ##

=head2 build_terms_filter

 Usage     : 
 Purpose   :
 Returns   : JSON for a filter of one or more terms 
 Argument  : field, value(s)
 Throws    :
 Comments  : if more than one term is passed in, a "terms" filter will be built, otherwise a "term" filter will be built

See Also   :

=cut

################################################## subroutine header end ##

sub build_terms_filter {
	my $field = shift;
	my $size = @_;

	if ($size == 1) {
		return '{"term":{"' . $field . '":' . shift . '}}';
	}

	my $json = '{"terms":{"' . $field . '":[';
	my $first = 1;
	for my $term (@_) {
		if ($first) {
			$first = 0;
		} else {
			$json .= ',';
		}
		$json .= '"' . $term . '"'; # note: doesn't yet encode values
	}
	$json .= ']}}';
	return $json;
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

1;
