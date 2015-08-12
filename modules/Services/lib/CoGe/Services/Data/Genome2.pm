package CoGe::Services::Data::Genome2;

use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
use CoGe::Services::Auth qw(init);
use CoGe::Services::Data::Job;
use CoGe::Core::Genome qw(search_genomes get_genome);
use CoGeDBI qw(get_feature_counts);
use Data::Dumper;

sub search {
    my $self = shift;
    my $search_term = $self->stash('term');
    my $fast = $self->param('fast');
    $fast = (defined $fast && ($fast eq '1' || $fast eq 'true'));

    # Validate input
    if (!$search_term or length($search_term) < 3) {
        $self->render(json => { error => { Error => 'Search term is shorter than 3 characters' } });
        return;
    }

    # Authenticate user and connect to the database
    my ($db, $user) = CoGe::Services::Auth::init($self);

    # Search genomes (including organism name/desc)
    my @genomes = search_genomes($db, $search_term);

    # Filter response on permissions
    my @filtered = grep {
        !$_->restricted || (defined $user && $user->has_access_to_genome($_))
    } @genomes;

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
    
    @result = sort { $a->{info} cmp $b->{info} } @result;

    $self->render(json => { genomes => \@result });
}

sub fetch {
    my $self = shift;
    my $id = int($self->stash('id'));

    # Authenticate user and connect to the database
    my ($db, $user) = CoGe::Services::Auth::init($self);

    my $genome = get_genome($id);
    unless (defined $genome) {
        $self->render(json => {
            error => { Error => "Item not found"}
        });
        return;
    }

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

sub add {
    my $self = shift;
    my $data = $self->req->json;
    #print STDERR "CoGe::Services::Data::Genome2::add\n", Dumper $data, "\n";

    # Authenticate user and connect to the database
    my ($db, $user, $conf) = CoGe::Services::Auth::init($self);

    # User authentication is required to add experiment
    unless (defined $user) {
        $self->render(json => {
            error => { Auth => "Access denied" }
        });
        return;
    }

    # Valid data items
    unless ($data->{source_data} && @{$data->{source_data}}) {
        $self->render(json => {
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
