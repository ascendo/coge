package CoGeX::Result::Genome;

# Created by DBIx::Class::Schema::Loader v0.03009 @ 2006-12-01 18:13:38

use strict;
use warnings;
use base 'DBIx::Class::Core';
use CoGeX::ResultSet::Genome;
use File::Spec::Functions;
use Data::Dumper;
use Text::Wrap;
use POSIX;
use Carp;
use LWP::Simple;

=head1 NAME

CoGeX::Genome

=head1 SYNOPSIS

This object uses the DBIx::Class to define an interface to the C<genome> table in the CoGe database.

=head1 DESCRIPTION

=head1 USAGE

 use CoGeX;

=head1 METHODS

=cut

my $node_types = CoGeX::node_types();

__PACKAGE__->table("genome");
__PACKAGE__->add_columns(
	"genome_id",
	{
		data_type     => "INT",
		default_value => undef,
		is_nullable   => 0,
		size          => 11
	},
	"name",
	{
		data_type     => "VARCHAR",
		default_value => "",
		is_nullable   => 0,
		size          => 200
	},
	"description",
	{
		data_type     => "VARCHAR",
		default_value => undef,
		is_nullable   => 1,
		size          => 255,
	},
	"version",
	{
		data_type     => "VARCHAR",
		default_value => undef,
		is_nullable   => 0,
		size          => 50,
	},
	"organism_id",
	{ data_type => "INT", default_value => 0, is_nullable => 0, size => 11 },
	"genomic_sequence_type_id",
	{ data_type => "INT", default_value => 0, is_nullable => 0, size => 11 },
	"file_path",
	{
		data_type     => "VARCHAR",
		default_value => undef,
		is_nullable   => 0,
		size          => 255,
	},
	"restricted",
	{ data_type => "int", default_value => "0", is_nullable => 0, size => 1 },
	"access_count",
	{ data_type => "int", default_value => "0", is_nullable => 1, size => 10 },
	"message",
	{
		data_type     => "text",
		default_value => undef,
		is_nullable   => 1,
	},
	"link",
	{
		data_type     => "text",
		default_value => undef,
		is_nullable   => 1,
	},
	"deleted",
	{ data_type => "int", default_value => "0", is_nullable => 0, size => 1 },
);

__PACKAGE__->set_primary_key("genome_id");
__PACKAGE__->has_many("dataset_connectors" => "CoGeX::Result::DatasetConnector", 'genome_id');
__PACKAGE__->has_many("genomic_sequences" => "CoGeX::Result::GenomicSequence", 'genome_id');
__PACKAGE__->belongs_to("organism" => "CoGeX::Result::Organism", 'organism_id');
__PACKAGE__->belongs_to("genomic_sequence_type" => "CoGeX::Result::GenomicSequenceType", 'genomic_sequence_type_id');
__PACKAGE__->has_many( # parent lists
	'list_connectors' => 'CoGeX::Result::ListConnector', 
	{'foreign.child_id' => 'self.genome_id'},
	{ where => [ -and => [ child_type => $node_types->{genome} ] ] } );
__PACKAGE__->has_many( # parent users
	'user_connectors' => 'CoGeX::Result::UserConnector', 
	{ "foreign.child_id" => "self.genome_id" }, 
	{ where => [ -and => [ parent_type => $node_types->{user}, child_type => $node_types->{genome} ] ] } );
__PACKAGE__->has_many( # parent groups
	'group_connectors' => 'CoGeX::Result::UserConnector', 
	{ "foreign.child_id" => "self.genome_id" }, 
	{ where => [ -and => [ parent_type => $node_types->{group}, child_type => $node_types->{genome} ] ] } ); 	
__PACKAGE__->has_many("experiments" => "CoGeX::Result::Experiment", "genome_id");

sub desc {
	return shift->description(@_);
}


################################################ subroutine header begin ##

=head2 lists

 Usage     : $self->lists
 Purpose   : Get lists that contain this genome
 Returns   : array or array ref of parent lists
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub lists {    
	my $self = shift;
	my @lists = ();

	foreach	my $conn ( $self->list_connectors )
	{
		my $list = $conn->parent_list;
		push @lists, $list if ($list);
	}

	return wantarray ? @lists : \@lists;
}

#sub groups {
#	my $self = shift;
#	my %opts = @_;
#
#	my @groups = ();
#	foreach my $conn ( $self->group_connectors )
#	{
#		push @groups, $conn->parent;
#	}
#
#	return wantarray ? @groups : \@groups;
#}
#
#sub users {
#	my $self = shift;
#	my %opts = @_;
#	my $exclude_groups = $opts{exclude_groups};
#
#	my %users;
#	foreach	( $self->user_connectors )
#	{
#		$users{$_->parent_id} = $_->user;
#	}
#	foreach my $group ( $self->groups )
#	{
#		map { $users{$_->id} = $_ } $group->users;
#	}
#
#	return wantarray ? values %users : [ values %users ];
#}

################################################ subroutine header begin ##

=head2 datasets

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub datasets {
	my $self = shift;
	my %opts = @_;
	my $chr  = $opts{chr};
	$chr = $opts{chromosome} unless defined $chr;
	my $restricted = $opts{restricted};
	
	my @datasets;
	foreach my $dsc ( $self->dataset_connectors() ) {
		my $ds = $dsc->dataset;
		next if ($restricted and not $ds->restricted);
		
		if ( defined $chr ) {
			#foreach my $ds_chr ($dsc->dataset->chromosomes) {
			#	print STDERR $ds_chr,"\n";
			#	return $dsc->dataset if $ds_chr eq $chr;
			return $ds if $ds->has_chromosome( chr => $chr );
			#}
		}
		else {
			push @datasets, $ds;
		}
	}
	return wantarray ? @datasets : \@datasets;
}

################################################ subroutine header begin ##

=head2 get_genomic_sequence

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub get_genomic_sequence {
	my $self = shift;
	my %opts = @_;

	#  print STDERR "Genome: sub get_genomic_sequence\n";
	#  print STDERR Dumper \%opts;
	my $start = $opts{start} || $opts{begin};
	my $stop  = $opts{stop}  || $opts{end};
	my $chr   = $opts{chr};
	$chr = $opts{chromosome} unless defined $chr;
	$chr = "1" unless defined $chr;
	my $strand = $opts{strand};
	my $debug  = $opts{debug};
	my $str    = "";
	return
	  if ( defined $start && defined $stop && $start < 1 && $stop < 1 )
	  ;    #asking for sequence beyond the start
	$start = 1 unless $start;
	my $last = $self->sequence_length($chr);
	$stop = $last unless $stop;
	$stop  = $last if $stop > $last;
	$start = $last if $start > $last;
	return
	  if ( $start > $last && $stop > $last )
	  ;    #asking for sequence beyond the end;
	return if $start > $last && $stop > $last;    #outside of chromosome
	return if $start < 1     && $stop < 1;

	if ( defined $start && defined $stop ) {
		$start = 1 if $start < 1;
		$stop = $start unless $stop;
		return undef unless ( $start =~ /^\d+$/ and $stop =~ /^\d+$/ );
		( $start, $stop ) = ( $stop, $start ) if $stop < $start;
	}
	else {
		warn "missing parameters in sub get_genomic_sequence\n";
		warn Dumper \%opts;
		return;
	}

	#  my ($seq) = $self->genomic_sequences({chromosome=>$chr});
	my $file = $self->file_path();
	unless ( -r $file ) {
		warn "Dataset group id: "
		  . $self->id
		  . " does not have a valid sequence file: $file!\n";
	}
	return $self->get_seq(
		chr    => $chr,
		start  => $start,
		stop   => $stop,
		strand => $strand,
		debug  => $debug
	);
}

################################################ subroutine header begin ##

=head2 get_seq

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub get_seq {
	my $self = shift;
	my %opts = @_;
	my $chr = $opts{chr};
	$chr = $opts{chromosome} unless defined $chr;
	$chr =~ s/gi\|//;
	$chr =~ s/lcl\|//;
	my $debug  = $opts{debug};
	my $start  = $opts{start};
	my $stop   = $opts{stop} || $opts{end};
	my $strand = $opts{strand};
	my $IN     = $opts{file_handle};
	my $server = $opts{server}; #option for specifying a server for retrieving sequences if local sequences do not exist.
	#$server = "http://genomevolution.org" unless $server;
	#$server .= "/CoGe/GetSequence.pl" unless $server =~ /coge\/GetSequence\.pl/i;
	$server = "http://geco.iplantcollaborative.org/mbomhoff/CoGe/GetSequence.pl";
	$strand = 1 unless defined $strand;
	( $start, $stop ) = ( $stop, $start ) if $start && $stop && $start > $stop;
	my $file = $self->file_path;
	$file =~ s/\/[^\/]*\.faa$//;
	$file .= "/chr/$chr";
	my $seq;
	my $close = 1; #flag for determining of the filehandle is to be closed.  Set to 0 if a file_handle was passed in

	if ($IN) {
		$close = 0;
	}
	else {
		unless ( -r $file ) {
			warn qq{!!!!!!!!!!!!!! $file does not exist for get_seq to extract sequence};
			return;
		
# mdb removed 2/19/13, get() causes deep recursion from call to this routine in GetSequence.pl	
#			#make this call a script at synteny/CoGe to retrieve the sequence.
#			my $url = $server;
#			$url .= "?" unless $server =~ /\?$/;
#			$url .= "dsgid=" . $self->id;
#			$url .= ";chr=" . $chr if defined $chr;
#			$url .= ";start=" . $start if $start;
#			$url .= ";stop=" . $stop if $stop;
#			$url .= ";strand=" . $strand if $strand;

#			if (
#				$ENV{SERVER_NAME}
#				&& (   $ENV{SERVER_NAME} eq "synteny.cnr.berkeley.edu"
#					|| $ENV{SERVER_NAME} eq "genomevolution.org" )
#			  )
#			{
#				warn qq{
###############
#MAJOR ERROR:  $file does not exist!
#This sequence file does not exist on the sequence server.  Please check the source of the sequence!
###############
#	      };
#				return (0);
#			}
#			else {
#				warn qq{!!!! retrieving sequence from $url};
#				return get($url);
#			}
		}
		open( $IN, $file );
	}
	if ( $start && $stop ) {
		seek( $IN, $start - 1, 0 );
		read( $IN, $seq, $stop - $start + 1 );
	}
	else {
		$seq = <$IN>;
	}
	close($IN) if $close;    #close filehand
	$seq = $self->reverse_complement($seq) if $strand =~ /-/;

#    if (length ($seq) ne abs($stop-$start+1))
#      {
#	print STDERR "Warning from Genome sub get_seq!  Sequence retrieved is not the same than sequence requested!\n";
#	print STDERR "Length of sequence: ", length($seq),"\n";
#	print STDERR "Requested: $start - $stop (", ($stop-$start+1),")\n";
#
#      }
	return $seq;
}

sub get_seq_fastacmd    #using fastacmd to get the sequence
{
	my $self = shift;
	my %opts = @_;

	#    use Data::Dumper;
	#    print STDERR Dumper \%opts;
	my $fastacmd = $opts{fastacmd} || '/usr/bin/fastacmd';
	my $blastdb  = $opts{blastdb}  || $opts{db};
	my $seqid    = $opts{seqid};
	$seqid = $opts{chr}        unless defined $seqid;
	$seqid = $opts{chromosome} unless defined $seqid;    # chr
	($seqid) = $seqid =~ /^(.*)$/;                       #make taint happy
	my $debug = $opts{debug};
	my $start = $opts{start};
	($start) = $start =~ /(\d+)/ if $start;
	my $stop = $opts{stop} || $opts{end};
	($stop) = $stop =~ /(\d+)/ if $stop;
	my $cmd = "$fastacmd -d $blastdb -s \"$seqid\" ";

	if ( $start && $stop ) {
		$cmd .= "-L " . $start . "," . $stop . " ";
	}
	if (   $opts{reverse_complement}
		|| $opts{rc}
		|| ( $opts{strand} && $opts{strand} =~ /-/ ) )
	{
		$cmd .= "-S 2";
	}
	print STDERR $cmd, "\n" if $debug;

	#    open(FASTA, $cmd . "|") || die "can't run $cmd";
	# get rid of the header line...
	#    <FASTA>;
	#    my $seq = join ("",<FASTA>);
	#    close FASTA;
	my $seq;
	foreach my $line ( split /\n/, `$cmd` ) {
		next if $line =~ /^>/;
		$seq .= $line;
	}
	$seq =~ s/\n//g;
	print STDERR "No sequence returned: ", $cmd, "\n" unless $seq;
	return $seq;
}

################################################ subroutine header begin ##

=head2 get_genome_sequence

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub get_genome_sequence {
	return shift->get_genomic_sequence(@_);
}

################################################ subroutine header begin ##

=head2 genomic_sequence

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub genomic_sequence {
	return shift->get_genomic_sequence(@_);
}

################################################## subroutine header start ##

=head2 sequence_length

 Usage     : my $last = $genome_seq_obj->sequence_length($chr);
 Purpose   : gets the last genomic sequence position for a dataset given a chromosome
 Returns   : an integer that refers to the last position in the genomic sequence refered
             to by a dataset given a chromosome
 Argument  : string => chromsome for which the last position is sought
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub sequence_length
{
	my $self = shift;
	my $chr  = shift;
	return unless defined $chr;
	my ($item) = $self->genomic_sequences( { chromosome => "$chr", }, );
	unless ($item) {
		print STDERR "Genome::sequence_length: unable to get genomic_sequence object for chr '$chr' genome_id '" . $self->id . "'\n";
		return;
	}
	my $stop = $item->sequence_length;
	unless ($stop) {
		warn "No genomic sequence for ", $self->name, " for chr $chr\n";
		return;
	}
	return $stop;
}

sub last_chromosome_position {
	shift->sequence_length(@_);
}

################################################ subroutine header begin ##

=head2 sequence_type

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub sequence_type {
	shift->genomic_sequence_type(@_);
}

################################################ subroutine header begin ##

=head2 type

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub type {
	shift->genomic_sequence_type(@_);
}

################################################ subroutine header begin ##

=head2 get_chromosomes

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub get_chromosomes {
	my $self = shift;
	my @data = map { $_->chromosome } sort { $b->sequence_length <=> $a->sequence_length } $self->genomic_sequences();
	return wantarray ? @data : \@data;
}

################################################ subroutine header begin ##

=head2 chromosomes

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub chromosomes {
	my $self = shift;
	$self->get_chromosomes(@_);
}

################################################ subroutine header begin ##

=head2 percent_gc

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub percent_gc {
	my $self     = shift;
	my %opts     = @_;
	my $count    = $opts{count};
	my $sent_chr = $opts{chr};
	my @chr;
	push @chr, $sent_chr if $sent_chr;
	my $gc     = 0;
	my $at     = 0;
	my $n      = 0;
	my $x      = 0;
	my $length = 0;
	unless ($sent_chr) {

		foreach my $chr ( $self->get_chromosomes ) {
			push @chr, $chr;
		}
	}
	foreach my $chr (@chr) {
		my $seq = $self->genomic_sequence( chr => $chr );
		$length += length $seq;
		$gc     += $seq =~ tr/GCgc/GCgc/;
		$at     += $seq =~ tr/ATat/ATat/;
		$n      += $seq =~ tr/nN/nN/;
		$x      += $seq =~ tr/xX/xX/;
	}
	return unless $length;
	return ( $gc, $at, $n, $x ) if $count;
	return sprintf( "%.4f", $gc / $length ), sprintf( "%.4f", $at / $length ),
	  sprintf( "%.4f", $n / $length ), sprintf( "%.4f", $x / $length );
}

################################################ subroutine header begin ##

=head2 fasta

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
            col      =>   number of sequence characters per line (default 100)
            chr_name =>   fasta header contains only the chromosome name (default 0)
            start    =>  start position (default 1)
            stop     =>  stop position  (default $self->sequence_legnth($chr)
            chr      =>  chromosome for which to get sequence (default:  whatever $self->get_chromosomes gets first)
            rc       =>  generate the reverse complement (default: 0)
            prot     =>  translate to protein, will do 6 frame automatically if it is not in a proper reading frame (default: 0)

 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub fasta {
	my $self = shift;
	my %opts = @_;
	my $col  = $opts{col};

	#$col can be set to zero so we want to test for defined variable
	$col = $opts{column} unless defined $col;
	$col = $opts{wrap}   unless defined $col;
	$col = 100           unless defined $col;
	my $chr_name = $opts{chr_name};   #makes header contain only chromosome name
	my $chr      = $opts{chr};
	($chr) = $self->get_chromosomes unless defined $chr;
	my $strand = $opts{strand} || 1;
	my $start  = $opts{start}  || 1;
	$start = 1 if $start < 1;
	my $stop = $opts{stop} || $self->sequence_length($chr);
	my $prot = $opts{prot};
	my $rc   = $opts{rc};
	$strand = -1 if $rc;
	my $seq =
	  $self->genomic_sequence( start => $start, stop => $stop, chr => $chr );
	$stop = $start + length($seq) - 1 if $stop > $start + length($seq) - 1;
	my $head;

	if ($chr_name) {
		$head .= ">" . $chr;
	}
	else {
		$head .= ">" . $self->organism->name;
		$head .= $self->name if $self->name;
		$head .= ", " . $self->description if $self->description;
		$head .= " (v"
		  . $self->version . ")"
		  . ", Location: "
		  . $start . "-"
		  . $stop
		  . " (length: "
		  . ( $stop - $start + 1 )
		  . "), Chromosome: "
		  . $chr
		  . ", Strand: "
		  . $strand;
	}

	$Text::Wrap::columns = $col;
	my $fasta;

	$seq = $self->reverse_complement($seq) if $rc;
	if ($prot) {
		my $trans_type = $self->trans_type;
		my $feat       = new CoGeX::Feature;
		my ( $seqs, $type ) =
		  $feat->frame6_trans( seq => $seq, trans_type => $trans_type );
		foreach my $frame ( sort { length($a) <=> length($b) || $a cmp $b }
			keys %$seqs )
		{
			$seq = $seqs->{$frame};
			$seq = $self->reverse_complement($seq) if $rc;
			$seq = join( "\n", wrap( "", "", $seq ) ) if $col;
			$fasta .= $head . " $type frame $frame\n" . $seq . "\n";
		}
	}
	else {
		$seq = join( "\n", wrap( "", "", $seq ) ) if $col;
		$fasta = $head . "\n" . $seq . "\n";
	}
	return $fasta;
}

################################################ subroutine header begin ##

=head2 gff

 Usage     : $dsg->gff(print=>1)
 Purpose   : generating a gff file for a genome from all the datasets it contains
 Returns   : a string
 Argument  : name_re     =>    regular expression for only displaying features containing a name that matches
             print       =>    print the gff file as the lines are retrieved
             annos       =>    print annotations as well (takes longer)
             cds         =>    Only print CDS gene features (skip all ncRNA and other features).  Will print genes, mRNA, and CDS entries
             id_type     =>    Specify if the GFF entry IDs are going to be unique numbers or unique names.
             unique_parent_annotations => Flag to NOT print redundant annotations in children entries.  E.g. if parent has an annotation, a child will not have that annotation
             name_unique =>   Flag for specifying that the name tag of an entry will be unique
 Throws    : 
 Comments  : 

See Also   : dataset->gff

=cut

################################################## subroutine header end ##

sub gff {
	my $self                      = shift;
	my %opts                      = @_;
	my $name_re                   = $opts{name_re};
	my $debug                     = $opts{debug};
	my $print                     = $opts{print};
	my $annos                     = $opts{annos};
	my $cds                       = $opts{cds};    #only print CDS gene features
	my $unique_parent_annotations =
	  $opts{unique_parent_annotations}; #parent annotations are NOT propogated to children
	my $id_type =
	  $opts{id_type};    #type of ID (name, num):  unique number; unique name
	$id_type = "name" unless defined $id_type;

	my $name_unique =
	  $opts{name_unique}; #flag for making Name tag of output unique by appending type and occurrence to feature name
	my $output;           #store the goodies
	$output .= "##gff-version\t3\n";
	$output .= "##Generate by CoGe\n";
	$output .= "##Organism name: " . $self->organism->name . "\n";
	$output .= "##Organism desc: " . $self->organism->description . "\n"
	  if $self->organism->description;
	$output .= "##Version: " . $self->version . "\n";
	$output .= "##CoGe Genome ID (dsgid): " . $self->id . "\n";
	$output .= "##\n";
	$output .= "##\n";
	print $output if $print;
	my $id = 0;

	foreach my $ds ( $self->datasets ) {
		my $tmp;
		( $tmp, $id ) = $ds->gff(
			name_re                   => $name_re,
			debug                     => $debug,
			print                     => $print,
			annos                     => $annos,
			no_gff_head               => 1,
			id                        => $id,
			cds                       => $cds,
			name_unique               => $name_unique,
			id_type                   => $id_type,
			unique_parent_annotations => $unique_parent_annotations
		);
		$output .= $tmp;
	}
	return $output;
}

################################################ subroutine header begin ##

=head2 trans_type

 Usage     : 

 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub trans_type {
	my $self = shift;
	foreach my $ds ( $self->datasets() ) {
		my $type = $ds->trans_type();
		return $type if $type;
	}
	return 1;    #universal genetic code type;
}

################################################ subroutine header begin ##

=head2 reverse_complement

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub reverse_complement {
	my $self  = shift;
	my $seq   = shift;           # || $self->genomic_sequence;
	my $rcseq = reverse($seq);
	$rcseq =~ tr/ATCGatcg/TAGCtagc/;
	return $rcseq;
}

################################################ subroutine header begin ##

################################################ subroutine header begin ##

=head2 get_path

 Usage     : 
 Purpose   : This method determines the correct directory structure for storing
 			the sequence files for a dataset group.
 Returns   : 
 Argument  : 
 Throws    : none
 Comments  : The idea is to build a dir structure that holds large amounts of
 			files, and is easy to lookup based on genome ID number.
			The strucuture is three levels of directorys, and each dir holds
			1000 files and/or directorys.
			Thus:
			./0/0/0/ will hold files 0-999
			./0/0/1/ will hold files 1000-1999
			./0/0/2/ will hold files 2000-2999
			./0/1/0 will hold files 1000000-1000999
			./level0/level1/level2/

See Also   : 

=cut

################################################## subroutine header end ##

sub get_path {
	my $self      = shift;
	my $genome_id = $self->id;
	my $level0    = floor( $genome_id / 1000000000 ) % 1000;
	my $level1    = floor( $genome_id / 1000000 ) % 1000;
	my $level2    = floor( $genome_id / 1000 ) % 1000;
	my $path      =
	  catdir( $level0, $level1, $level2, $genome_id )
	  ; #adding genome_id for final directory.  blast's formatdb will be run on the faa file and this will help keep that stuff organized
	return $path;
}

sub chr_info {
	my $self    = shift;
	my %opts    = @_;
	my $summary = $opts{summary};

	#    print STDERR Dumper \%opts;
	my $html;
	my $total_length;
	my @gs = sort {
		$a->chromosome =~ /(\d+)/ <=> $b->chromosome =~ /(\d+)/
		  || $a->chromosome cmp $b->chromosome
	} $self->genomic_sequences;
	my $chr_num = scalar @gs;
	my $count   = 0;
	my $chr_list;
	foreach my $gs (@gs) {
		my $chr    = $gs->chromosome;
		my $length = $gs->sequence_length;
		$total_length += $length;
		$length = $self->commify($length);
		$chr_list .= qq{$chr:  $length bp<br>};
		$count++;
	}
	$html .=
	    qq{Chromosome count: $chr_num<br>}
	  . qq{Total length: }
	  . $self->commify($total_length) . " bp";
	$html .= "<br>" . qq{-----------<br>Chr:   (length)<br>} . $chr_list
	  unless $summary;
	return $html;
}
############################################### subroutine header begin ##

=head2 length

 Usage     : $self->length
 Purpose   : get total length of sequence in dataset group
 Returns   : number
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub length {
	my $self = shift;
	my $rs   = $self->genomic_sequences(
		{},
		{
			select => [ { sum => 'sequence_length' } ],
			as     => ['total_length']
			,    # remember this 'as' is for DBIx::Class::ResultSet not SQL
		}
	);
	my $total_length = $rs->first->get_column('total_length');
	return $total_length;
}

############################################### subroutine header begin ##

=head2 chromosome_count

 Usage     : $self->chromosome_count
 Purpose   : get count of chromosomes in the dataset group
 Returns   : number
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub chromosome_count {
	return shift->genomic_sequences->count();
}

################################################ subroutine header begin ##

=head2 features

 Usage     : $self->features
 Purpose   : run through associated datasets and get their features
 Returns   : array of feature objects
 Argument  : 
 Throws    : 
 Comments  : 

See Also   : 

=cut

################################################## subroutine header end ##

sub features {
	my $self = shift;
	my @feats;
	foreach my $ds ( $self->datasets ) {
		my @tmp = $ds->features(@_);
		push @feats, @tmp;
	}
	return wantarray ? @feats : \@feats;
}

sub translation_type {
	my $self = shift;
	foreach my $ds ( $self->datasets ) {
		my $trans_type = $ds->translation_type;
		return $trans_type if $trans_type;
	}
}

sub commify {
	my $self = shift;
	my $text = reverse $_[0];
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $text;
}

sub distinct_feature_type_ids {
	my $self = shift;
	my %opts = @_;
	my %ids  =
	  map { $_ => 1 } map { $_->distinct_feature_type_ids } $self->datasets;
	return wantarray ? keys %ids : [ keys %ids ];
}

sub source {
	my $self = shift;
	my %sources;
	foreach my $ds ( $self->datasets ) {
		$sources{ $ds->data_source->id } = $ds->data_source;
	}
	return wantarray ? values %sources : [ values %sources ];
}

################################################ subroutine header begin ##

=head2 info

 Usage     : $self->info
 Purpose   : returns a string of information about the genome.  

 Returns   : returns a string
 Argument  : none
 Throws    : 
 Comments  : To be used to quickly generate a string about the genome

See Also   : 

=cut

################################################## subroutine header end ##

sub info {
	my $self = shift;
	my $info;
	$info .= "&reg; " if $self->restricted;
	$info .= $self->organism->name if $self->organism;
	$info .= " (".$self->name.")" if $self->name;
	$info .= ": ".$self->description if $self->description;
	$info .= " (v".$self->version.", id".$self->id. ")";
	$info .= ': ' . $self->genomic_sequence_type->name if $self->genomic_sequence_type;	
	return $info;
}

############################################### subroutine header begin ##

=head2 info_html

 Usage     : 
 Purpose   : provides quick information about the genome wrapped with a link to LIstView
 Returns   : a string
 Argument  : 
 Throws    : 
 Comments  : name, description, restricted, type
           : 

See Also   : 

=cut

################################################## subroutine header end ##

sub info_html
{
	my $self = shift;
	my $info = $self->info;
	return qq{<span class=link onclick='window.open("OrganismView.pl?gid=} .$self->id. qq{")'>} . $info . "</span>";
}

############################################### subroutine header begin ##

=head2 date

 Usage     : 
 Purpose   : returns load data from first dataset entry
 Returns   : a string
 Argument  : 
 Throws    : 
 Comments  :

See Also   : 

=cut

################################################## subroutine header end ##

sub date
{
	my $self = shift;
	my ($ds) = $self->datasets;
	return $ds ? $ds->date : '';
}

=head1 BUGS


=head1 SUPPORT


=head1 AUTHORS

 Eric Lyons
 Brent Pedersen
 Daniel Hembry

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

=cut

1;
