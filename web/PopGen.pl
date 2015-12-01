#! /usr/bin/perl -w
use strict;
use CoGe::Accessory::Web;
use CGI;
use Data::Dumper;
use File::Spec::Functions qw( catfile );
use HTML::Template;
use JSON::XS;
use POSIX;
no warnings 'redefine';

use vars qw($CONF $USER $FORM $DB $PAGE_TITLE $LINK);

$PAGE_TITLE = 'PopGen';

$| = 1;    # turn off buffering

$FORM = new CGI;

my $export = $FORM->Vars->{'export'};
if ($export) {
	my $file = catfile($ENV{COGE_HOME}, 'data', 'popgen', $FORM->Vars->{'eid'}, 'sumstats.tsv');
	my $type = $FORM->Vars->{'type'};
	my $chr = $FORM->Vars->{'chr'};
	my @columns = map {substr $_, 3} split ',', $export;

	print "Content-Disposition: attachment; filename=PopGen.txt\n\n";
	my $in_type = 0;
	open my $fh, '<', $file;
	while (my $row = <$fh>) {
		chomp $row;
		if (substr($row, 0, 1) eq '#') {
			return if $in_type;
			my @tokens = split '\t', $row;
			$in_type = 1 if (substr($tokens[0], 1) eq $type);
			$row = <$fh>;
			chomp $row;
		}
		if ($in_type) {
			my @tokens = split '\t', $row;
			my $line;
			foreach (@columns) {
				$line .= "\t" if $line;
				$line .= $tokens[$_] if ($tokens[$_]);
			}
			print $line . "\n";
		}
	}
	return;
}

( $DB, $USER, $CONF, $LINK ) = CoGe::Accessory::Web->init(
    cgi => $FORM,
    page_title => $PAGE_TITLE
);

print $FORM->header, gen_html();

sub gen_html {
    my $template = HTML::Template->new( filename => $CONF->{TMPLDIR} . 'generic_page.tmpl' );
    $template->param( PAGE_TITLE => $PAGE_TITLE,
		              TITLE      => $PAGE_TITLE,
    				  PAGE_LINK  => $LINK,
				      HOME       => $CONF->{SERVER},
                      HELP       => $PAGE_TITLE,
                      WIKI_URL   => $CONF->{WIKI_URL} || '',
                      ADJUST_BOX => 1,
    				  ADMIN_ONLY => $USER->is_admin,
                      CAS_URL    => $CONF->{CAS_URL} || '',
                      USER       => $USER->display_name || ''
    );
    $template->param( LOGON => 1 ) unless ($USER->user_name eq "public");
    $template->param( BODY => gen_body() );

    return $template->output;
}

sub gen_body {
    if (!$FORM->Vars->{'eid'}) {
        return 'eid url parameter not set';
    }
    my $template = HTML::Template->new( filename => $CONF->{TMPLDIR} . "$PAGE_TITLE.tmpl" );
    return $template->output;
}
