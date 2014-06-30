#!/usr/bin/perl -w

use strict;
use CoGeX;
use CoGe::Accessory::Web;
use CoGe::Accessory::LogUser;
use Data::Dumper;
use Text::Wrap;
use CGI;
use IO::Compress::Gzip;
use File::Path;

$|++;

use vars
  qw($FORM $P $DBNAME $DBHOST $DBPORT $DBUSER $DBPASS $connstr $coge $FASTADIR $URL $DIR $USER $COOKIE_NAME);

$FORM = new CGI;
$P    = CoGe::Accessory::Web::get_defaults();

$FASTADIR = $P->{FASTADIR};
$DIR      = $P->{COGEDIR};
$URL      = $P->{URL};
mkpath( $FASTADIR, 1, 0777 );
unless (-r $FASTADIR) {
	print $FORM->header;
	print "Access denied to $FASTADIR\n";
	exit;
}

$DBNAME = $P->{DBNAME};
$DBHOST = $P->{DBHOST};
$DBPORT = $P->{DBPORT};
$DBUSER = $P->{DBUSER};
$DBPASS = $P->{DBPASS};
$connstr =
  "dbi:mysql:dbname=" . $DBNAME . ";host=" . $DBHOST . ";port=" . $DBPORT;
$coge = CoGeX->connect( $connstr, $DBUSER, $DBPASS );
unless ($coge) {
	print $FORM->header;
	print "Failed to connect to database\n";
	exit;
}

$COOKIE_NAME = $P->{COOKIE_NAME};
my ($cas_ticket) = $FORM->param('ticket');
$USER = undef;
($USER) = CoGe::Accessory::Web->login_cas(
    ticket   => $cas_ticket,
    coge     => $coge,
    this_url => $FORM->url()
) if ($cas_ticket);
($USER) = CoGe::Accessory::LogUser->get_user(
    cookie_name => $COOKIE_NAME,
    coge        => $coge
) unless $USER;

my $dsgid = $FORM->param('dsgid');
my $dsid  = $FORM->param('dsid');
my $ftid  = $FORM->param('ftid');
my $prot  = $FORM->param('p');
unless ( $dsgid || $dsid ) {
    print $FORM->header;
    print "No genome or dataset id specified.\n";
    exit;
}
unless ($ftid) {
    print $FORM->header;
    print "No feature type id specified.\n";
    exit;
}

my ( $dsg, $ds );
($dsg) = $coge->resultset('Genome')->search( { "me.genome_id" => $dsgid },
    { join => 'genomic_sequences', prefetch => 'genomic_sequences' } )
  if $dsgid;
$ds = $coge->resultset('Dataset')->find($dsid) if $dsid;

($dsg) = $ds->genomes if $ds;

if ( !$USER->has_access_to_genome($dsg) ) {
    print $FORM->header;
    print "Permission denied";
    exit;
}

my $ft = $coge->resultset('FeatureType')->find($ftid);
my $file_name;
$file_name .= $dsgid  if $dsgid;
$file_name .= $dsid   if $dsid;
$file_name .= "-" . $ft->name;
$file_name .= "-prot" if $prot;
$file_name .= ".fasta";

print qq{Content-Type: application/force-download
Content-Disposition: attachment; filename="$file_name"

};

my $count = 1;
my @feats;
if ($ds) {
    @feats = $ds->features( { feature_type_id => $ftid } );
}
else {
    @feats = $dsg->features( { feature_type_id => $ftid } );
}

my $org = $dsg->organism->name;

foreach my $feat (@feats) {
    my ($chr) = $feat->chromosome;    #=~/(\d+)/;
    my $name;

    eval {{
        foreach my $n ( $feat->names ) {
            $name = $n;
            last unless $name =~ /\s/;
        }
        $name =~ s/\s+/_/g;
        my $title = join( "||",
            $org,              $chr,      $feat->start,
            $feat->stop,       $name,     $feat->strand,
            $feat->type->name, $feat->id, $count );
        my $seq;
        if ($prot) {
            my (@seqs) = $feat->protein_sequence( dsgid => $dsg->id );
            next unless scalar @seqs;
            next if scalar @seqs > 1;    #didn't find the correct reading frame;
            next unless $seqs[0] =~ /[^x]/i;
            $seq = $seqs[0];
        }
        else {
            $seq = $feat->genomic_sequence;
        }
        $title = ">" . $title . "\n";

        print $title, $seq, "\n";

        $count++;
    }};

    if ($@) {
        say STDERR "DOWNLOAD ABORTED: $file_name";
        last;
    }
}
