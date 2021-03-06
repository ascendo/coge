package CoGe::Services::API::Genome;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
use CoGe::Services::Auth qw(init);
use CoGe::Services::Data::Job;
use CoGe::Core::Genome qw(genomecmp);
use CoGe::Core::Storage qw(get_genome_seq);
use CoGe::Accessory::Utils qw(sanitize_name);
use CoGeDBI qw(get_feature_counts);
use Data::Dumper;

sub search { #TODO move search code into reusable function in CoGe::Core::Genome
    my $self = shift;
    my $search_term = $self->stash('term');
    my $fast = $self->param('fast');
    $fast = (defined $fast && ($fast eq '1' || $fast eq 'true'));

    # Validate input
    if (!$search_term or length($search_term) < 3) {
        $self->render(status => 400, json => { error => { Error => 'Search term is shorter than 3 characters' } });
        return;
    }

    # Authenticate user and connect to the database
    my ($db, $user) = CoGe::Services::Auth::init($self);

    # Search genomes
    my $search_term2 = '%' . $search_term . '%';
    my @genomes = $db->resultset("Genome")->search(
        \[
            'genome_id = ? OR name LIKE ? OR description LIKE ?',
            [ 'genome_id', $search_term  ],
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );
    
    # Search organisms
    my @organisms = $db->resultset("Organism")->search(
        \[
            'name LIKE ? OR description LIKE ?',
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );
    
    # Combine matching genomes and organisms, preventing duplicates
    my %unique;
    map { $unique{ $_->id } = $_ } @genomes;
    foreach my $organism (@organisms) {
        map { $unique{ $_->id } = $_ } $organism->genomes;
    }

    # Filter response
    my @filtered = sort genomecmp grep {
        !$_->restricted || (defined $user && $user->has_access_to_genome($_))
    } values %unique;

    # Format response
    my @result;
    if ($fast) {
        @result = map {
          {
            id => int($_->id),
            info => $_->info
          }
        } @filtered;
    }
    else {
        @result = map {
          {
            id => int($_->id),
            name => $_->name,
            description => $_->description,
            link => $_->link,
            version => $_->version,
            info => $_->info,
            organism_id  => int($_->organism->id),
            sequence_type => {
                id => $_->type->id,
                name => $_->type->name,
                description => $_->type->description,
            },
            restricted => $_->restricted ? Mojo::JSON->true : Mojo::JSON->false,
            chromosome_count => int($_->chromosome_count),
            organism => {
                id => int($_->organism->id),
                name => $_->organism->name,
                description => $_->organism->description
            }
          }
        } @filtered;
    }
    
    $self->render(json => { genomes => \@result });
}

sub fetch {
    my $self = shift;
    my $id = int($self->stash('id'));
    
    # Validate input
    unless ($id) {
        $self->render(status => 400, json => {
            error => { Error => "Invalid input"}
        });
        return;
    }

    # Authenticate user and connect to the database
    my ($db, $user) = CoGe::Services::Auth::init($self);

    # Get genome
    my $genome = $db->resultset("Genome")->find($id);
    unless (defined $genome) {
        $self->render(status => 404, json => {
            error => { Error => "Resource not found"}
        });
        return;
    }

    # Verify permission
    unless ( !$genome->restricted || (defined $user && $user->has_access_to_genome($genome)) ) {
        $self->render(json => {
            error => { Auth => "Access denied"}
        }, status => 401);
        return;
    }

    # Format metadata
    my @metadata = map {
        {
            text => $_->annotation,
            link => $_->link,
            type => $_->type->name,
            type_group => $_->type->group
        }
    } $genome->annotations;
    
    # Build chromosome list
    my $chromosomes = $genome->chromosomes_all;
    my $feature_counts = get_feature_counts($db->storage->dbh, $genome->id);
    foreach (@$chromosomes) {
        my $name = $_->{name};
        $_->{gene_count} = int($feature_counts->{$name}{1}{count});
        $_->{CDS_count} = int($feature_counts->{$name}{3}{count});
    }
    
    # Generate response
    $self->render(json => {
        id => int($genome->id),
        name => $genome->name,
        description => $genome->description,
        link => $genome->link,
        version => $genome->version,
        restricted => $genome->restricted ? Mojo::JSON->true : Mojo::JSON->false,
        organism => {
            id => int($genome->organism->id),
            name => $genome->organism->name,
            description => $genome->organism->description
        },
        sequence_type => {
            name => $genome->type->name,
            description => $genome->type->description,
        },
        chromosome_count => int($genome->chromosome_count),
        chromosomes => $chromosomes,
        experiments => [ map { int($_->id) } $genome->experiments ],
        additional_metadata => \@metadata
    });
}

sub sequence {
    my $self   = shift;
    my $gid    = $self->stash('id');
    return unless $gid;
    my $chr    = $self->stash('chr');
    my $start  = $self->param('start');
    my $stop   = $self->param('stop') || $self->param('end');
    my $strand = $self->param('strand');
    print STDERR "Data::Genome::fetch_sequence gid=$gid chr=$chr start=$start stop=$stop\n";

    # Connect to the database
    my ($db, $user, $conf) = CoGe::Services::Auth::init($self);

    # Retrieve genome
    my $genome = $db->resultset('Genome')->find($gid);
    unless ($genome) {
        print STDERR "Data::Sequence::get genome $gid not found in db\n";
        return;
    }

    # Check permissions
    if ( $genome->restricted
        and ( not defined $user or not $user->has_access_to_genome($genome) ) )
    {
        print STDERR "Data::Sequence::get access denied to genome $gid\n";
        return;
    }

    # Force browser to download whole genome as attachment
    if ( (!defined($chr) || $chr eq '') ) {
        my $genome_name = sanitize_name($genome->organism->name);
        $genome_name = 'genome_'.$gid unless $genome_name;
        $self->res->headers->content_disposition("attachment; filename=$genome_name.faa;");
    }

    # Get sequence from file
    $self->render(text => get_genome_seq(
        gid   => $gid,
        chr   => $chr,
        start => $start,
        stop  => $stop,
        strand => $strand
    ));
}

sub add {
    my $self = shift;
    my $data = $self->req->json;
    print STDERR "CoGe::Services::Data::Genome2::add\n", Dumper $data, "\n";

# mdb removed 9/17/15 -- auth is handled by Job::add below, redundant token validation breaks CAS proxyValidate
#    # Authenticate user and connect to the database
#    my ($db, $user, $conf) = CoGe::Services::Auth::init($self);
#
#    # User authentication is required to add experiment
#    unless (defined $user) {
#        $self->render(json => {
#            error => { Auth => "Access denied" }
#        });
#        return;
#    }

    # Valid data items # TODO move into request validation
    unless ($data->{source_data} && @{$data->{source_data}}) {
        $self->render(status => 400, json => {
            error => { Error => "No data items specified" }
        });
        return;
    }
    
    # Marshall incoming payload into format expected by Job Submit.
    # Note: This is kind of a kludge -- is there a better way to do this using
    # Mojolicious routing?
    my $request = {
        type => 'load_genome',
        parameters => $data
    };
    
    return CoGe::Services::Data::Job::add($self, $request);
}

1;
