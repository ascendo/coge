package CoGe::Core::Notebook;
use v5.14;
use strict;
use warnings;
use Data::Dumper qw(Dumper);

use CoGeX;

our %ITEM_TYPE;

BEGIN {
    our (@ISA, $VERSION, @EXPORT);
    require Exporter;

    $VERSION = 0.0.1;
    @ISA = qw(Exporter);
    @EXPORT = qw( create_notebook search_notebooks add_items_to_notebook load_notebook notebookcmp %ITEM_TYPE );

    my $node_types = CoGeX::node_types();

    %ITEM_TYPE = (    # content/toc types   # FIXME doesn't belong here, and also view constants and database constants
        all                 => 100,
        mine                => 101,
        shared              => 102,
        activity            => 103,
        trash               => 104,
        activity_viz        => 105,
        activity_analyses   => 106,
        user                => $node_types->{user},
        group               => $node_types->{group},
        notebook            => $node_types->{list},
        genome              => $node_types->{genome},
        experiment          => $node_types->{experiment}
    );
}

sub load_notebook {
    my %opts = @_;
    my $db = $opts{db};
    my $id = $opts{id};
    my $user = $opts{user}; # optional database user object
    return unless $db and $id;

	my $notebook = $db->resultset('List')->find($id);
	unless ($notebook) {
    	print STDERR "error reading notebook from db in CoGe::Core::Notebook::load_notebook\n";
		return undef;
	}

	if ($user) { # check permissions if user specified
		if ($notebook->restricted && !$user->has_access_to_list($notebook)) {
	    	print STDERR "attempt to load notebook without user permissions in CoGe::Core::Notebook::load_notebook\n";
			return undef;
		}
	}

	return $notebook;	
}

sub search_notebooks {
    my %opts = @_;
    my $db = $opts{db};
    my $search_term = $opts{search_term}; # id value, or keyword in name/description
    my $user = $opts{user}; # optional database user object
    return unless $db and $search_term;
    my $include_deleted = $opts{include_deleted}; # optional boolean flag

    # Search genomes
    my $search_term2 = '%' . $search_term . '%';
    my @notebooks = $db->resultset("List")->search(
        \[
            'list_id = ? OR name LIKE ? OR description LIKE ?',
            [ 'list_id',     $search_term  ],
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );

    # Filter result by permissions
    my @filtered = grep {
        (!$_->deleted || $include_deleted) &&
        (!$_->restricted || (defined $user && $user->has_access_to_list($_)))
    } @notebooks;

    return \@filtered;
}

sub create_notebook {
    my %opts = @_;
    my $db      = $opts{db}; #FIXME use add_to_* functions to create new connectors and remove this param
    my $user    = $opts{user};
    my $name    = $opts{name};
    my $desc    = $opts{desc};
    my $type_id = $opts{type_id};
    my $page    = $opts{page};
    return unless ($name and $type_id and $db and $user);
    my $items = $opts{item_list}; # optional
    return if ( $user->is_public );

    # Create the new list
    my $notebook = $db->resultset('List')->create(
        {
            name         => $name,
            description  => $desc,
            list_type_id => $type_id,
            creator_id   => $user->id,
            restricted   => 1
        }
    );
    return unless $notebook;

    # Set user as owner
    my $conn = $db->resultset('UserConnector')->create(
        {
            parent_id   => $user->id,
            parent_type => 5,           #FIXME hardcoded to "user"
            child_id    => $notebook->id,
            child_type  => 1,           #FIXME hardcoded to "list"
            role_id     => 2            #FIXME hardcoded to "owner"
        }
    );
    return unless $conn;

    # Add selected items to new notebook
    add_items_to_notebook( user => $user, db => $db, notebook => $notebook, item_list => $items)
      if ($items);

    # Record in log
    if ($page) {
        CoGe::Accessory::Web::log_history(
            db          => $db,
            user_id     => $user->id,
            page        => "$page",
            description => 'create notebook id' . $notebook->id,
            parent_id   => $notebook->id,
            parent_type => 1 #FIXME magic number
        );
    }

    return $notebook;
}

sub add_items_to_notebook {
    my %opts = @_;
    my $db       = $opts{db}; #FIXME use add_to_* functions to create new connectors and remove this param
    my $user     = $opts{user};     # user object
    my $notebook = $opts{notebook}; # notebook object
    my $items    = $opts{item_list}; # array ref to array refs of item_id, item_type
    return unless ($db and $notebook and $user and $items);
    #print STDERR "add_items_to_notebook\n";
    
    # Check permissions
    return unless $user->has_access_to_list($notebook);

    # Create connections for each item
    foreach (@$items) {
        my ( $item_id, $item_type ) = @$_;
        return unless ( $item_id and $item_type );
        $item_type = $ITEM_TYPE{$item_type} if ($item_type eq 'genome' or $item_type eq 'experiment');
        return unless ( $item_type eq $ITEM_TYPE{genome} or $item_type eq $ITEM_TYPE{experiment});

        #TODO check access permission on each item

        #print STDERR "add_items_to_notebook $item_id $item_type\n";

        my $conn = $db->resultset('ListConnector')->find_or_create(
            {
                parent_id   => $notebook->id,
                child_id    => $item_id,
                child_type  => $item_type
            }
        );
        return unless $conn;
    }

    return 1;
}

sub notebookcmp($$) {
    my ($a, $b) = $_;

    my $namea = "";
    my $nameb = "";

    $namea = $a->name if defined $a and $a->name;
    $nameb = $b->name if defined $b and $b->name;

    $namea cmp $nameb;
}

1;
