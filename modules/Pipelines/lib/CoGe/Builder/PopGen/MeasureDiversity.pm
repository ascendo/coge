package CoGe::Builder::PopGen::MeasureDiversity;

use Moose;
with qw(CoGe::Builder::Buildable);

use CoGe::Core::Storage qw(get_experiment_files);
use CoGe::Builder::PopGen::SummaryStats qw(build);

sub get_name {
    #my $self = shift;
    return 'Measure Expression';
}

sub build {
    my $self = shift;
    
    # Validate inputs
    my $eid = $self->params->{eid} || $self->params->{experiment_id};
    return unless $eid;
    #return unless $self->params->{diversity_params};
    
    # Get experiment
    my $experiment = $self->db->resultset('Experiment')->find($eid);
    return unless $experiment;
    my $genome = $experiment->genome;
    
    # Get input file
    my $vcf_file = get_experiment_files($experiment->id, $experiment->data_type)->[0];
    
    #
    # Build workflow steps
    #
    my @tasks;
    
    # Add expression analysis workflow
    my $workflow = CoGe::Builder::PopGen::SummaryStats::build(
        user => $self->user,
        wid => $self->workflow->id,
        genome => $genome,
        input_file => $vcf_file,
        params => $self->params->{diversity_params}
    );
    push @tasks, @{$workflow->{tasks}};
        
    $self->workflow->add_jobs(\@tasks);
    
    return 1;
}

1;