package CoGe::Core::Organism;

use strict;
use warnings;

use Data::Dumper;

BEGIN {
    our ( @EXPORT, @EXPORT_OK, @ISA, $VERSION );
    require Exporter;
    $VERSION = 0.1;
    @ISA = qw( Exporter );
    @EXPORT = qw( search_organisms get_organism add_organism );
}

sub search_organisms {
    my $db = shift;
    my $search_term = shift;
    
    my $search_term2 = '%' . $search_term . '%';
    my @organisms = $db->resultset("Organism")->search(
        \[
            'organism_id = ? OR name LIKE ? OR description LIKE ?',
            [ 'organism_id', $search_term  ],
            [ 'name',        $search_term2 ],
            [ 'description', $search_term2 ]
        ]
    );
    
    return wantarray ? @organisms : \@organisms;
}

sub get_organism {
    my $db = shift;
    my $organism_id = shift;
    
    return $db->resultset("Organism")->find($organism_id);
}

sub add_organism {
    my $db = shift;
    my $name = shift;
    my $desc = shift;
    
    return $db->resultset('Organism')->find_or_create( { name => $name, description => $desc } )
}

1;
