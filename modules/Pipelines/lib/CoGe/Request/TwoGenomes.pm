package CoGe::Request::TwoGenomes;

use Moose;
use CoGe::Request::Request;

sub is_valid {
    my $self = shift;
    my $genome_id1 = $self->parameters->{genome_id1};
    return unless $genome_id1;
    my $genome_id2 = $self->parameters->{genome_id2};
    return unless $genome_id2;
    my $genome1 = $self->db->resultset("Genome")->find($genome_id1);
    return unless defined $genome1;
    my $genome2 = $self->db->resultset("Genome")->find($genome_id2);
    return defined $genome2;
}

sub has_access {
    my $self = shift;
    my $genome_id1 = $self->parameters->{genome_id1};
    return unless $genome_id1;
    my $genome_id2 = $self->parameters->{genome_id2};
    return unless $genome_id2;
    my $genome1 = $self->db->resultset("Genome")->find($genome_id1);
    return unless $self->user->has_access_to_genome($genome1);
    my $genome2 = $self->db->resultset("Genome")->find($genome_id2);
    return $self->user->has_access_to_genome($genome2);
}

with qw(CoGe::Request::Request);

1;
