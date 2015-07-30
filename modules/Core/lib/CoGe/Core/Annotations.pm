package CoGe::Core::Annotations;

=head1 NAME

CoGe::Core::Annotations

=head1 SYNOPSIS

provides class for accessing feature annotations data from Elasticsearch

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

sub annotation {
	my $self = shift;
	return $self->{annotation};
}

sub link {
	my $self = shift;
	return $self->{link};
}

################################################ subroutine header begin ##

=head2 type

 Usage     :
 Purpose   :
 Returns   : the type object for this annotation
 Argument  :
 Throws    :
 Comments  :

See Also   :

=cut

################################################## subroutine header end ##

sub type {
	my $self = shift;
	return $self->{_type} if $self->{_type};

	$self->{_type} = CoGeX->dbconnect(get_defaults())->resultset('AnnotationType')->find($self->{type});
	return $self->{_type};
}

1;
