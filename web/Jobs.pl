#! /usr/bin/perl -w
use v5.10;
use strict;

use CGI;
use Digest::MD5 qw(md5_base64);

use HTML::Template;
use JSON::XS;

# CoGe packages
use CoGeX;
use CoGe::Accessory::Jex;
use CoGe::Accessory::Web;

no warnings 'redefine';

our ( $P, $PAGE_TITLE, $USER, $BASEFILE, $coge, %FUNCTION, $FORM, $YERBA,
    $LINK );

$PAGE_TITLE = 'Jobs';

$FORM = new CGI;
( $coge, $USER, $P, $LINK ) = CoGe::Accessory::Web->init(
    cgi        => $FORM,
    page_title => $PAGE_TITLE
);

$YERBA =
  CoGe::Accessory::Jex->new( host => $P->{JOBSERVER}, port => $P->{JOBPORT} );

%FUNCTION = (
    cancel_job   => \&cancel_job,
    schedule_job => \&schedule_job,
    get_jobs     => \&get_jobs_for_user,
);

CoGe::Accessory::Web->dispatch( $FORM, \%FUNCTION, \&gen_html );

sub get_jobs_for_user {
    my @jobs;

    if ( $USER->is_admin ) {
        @jobs =
          $coge->resultset('Job')
          ->search( undef, { order_by => { -desc => 'job_id' } } );
    }
    elsif ( $USER->is_public ) {
        @jobs =
          $coge->resultset('Job')
          ->search( { user_id => 0 }, { order_by => 'job_id ASC', } );
    }
    else {
        @jobs = $USER->jobs->search( { user_id => $USER->id },
            { order_by => { -desc => 'job_id' } } );
    }

    my %users = map { $_->user_id => $_->name } $coge->resultset('User')->all;
    my @job_items;

    foreach (@jobs) {
        push @job_items,
          {
            id        => int( $_->id ),
            link      => $_->link,
            tool      => $_->page,
            status    => $_->status_description,
            started   => $_->start_time,
            completed => $_->end_time ? $_->end_time : '',
            elapsed   => $_->elapsed_time(),
            user      => $_->user_id ? $users{ $_->user_id } : 'public',
          };
    }

    return encode_json( \@job_items );
}

sub gen_html {
    my $html;
    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . 'generic_page.tmpl' );
    $template->param( HELP => "/wiki/index.php?title=$PAGE_TITLE" );
    my $name = $USER->user_name;
    $name = $USER->first_name if $USER->first_name;
    $name .= " " . $USER->last_name if $USER->first_name && $USER->last_name;
    $template->param( USER => $name );
    $template->param(
        TITLE      => qq{},
        PAGE_TITLE => $PAGE_TITLE,
        PAGE_LINK  => $LINK,
        LOGO_PNG   => "$PAGE_TITLE-logo.png"
    );
    $template->param( LOGON => 1 ) unless $USER->user_name eq "public";
    $template->param( BODY => gen_body() );
    $template->param( ADJUST_BOX => 1 );
    $html .= $template->output;
}

sub gen_body {
    if ( $USER->is_public ) {
        my $template =
          HTML::Template->new( filename => $P->{TMPLDIR} . "$PAGE_TITLE.tmpl" );
        $template->param( PAGE_NAME => "$PAGE_TITLE.pl" );
        $template->param( LOGIN     => 1 );
        return $template->output;
    }

    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . "$PAGE_TITLE.tmpl" );
    $template->param( PAGE_NAME  => "$PAGE_TITLE.pl" );
    $template->param( MAIN       => 1 );
    $template->param( ADMIN_AREA => 1 ) if $USER->is_admin;
    return $template->output;
}

sub cancel_job {
    my $job_id = _check_job_args(@_);
    my $job    = _get_validated_job($job_id);

    return encode_json( {} ) unless defined($job);

    my $status = $YERBA->get_status( $job->id );

    if ( $status =~ /scheduled|running|notfound/i ) {
        $job->update( { status => 3, end_time => \'current_timestamp' } );
        return encode_json( $YERBA->terminate( $job->id ) );
    }
    else {
        return encode_json( {} );
    }

}

sub schedule_job {
    my $job_id = _check_job_args(@_);
    my $job    = _get_validated_job($job_id);

    return "fail" unless defined($job);
    return "true";
}

sub cmp_by_start_time {
    my $job1 = shift;
    my $job2 = shift;

    $job1->start_time cmp $job2->start_time;
}

# private functions

sub _get_validated_job {
    my $job_id = shift;
    my $job    = $coge->resultset('Job')->find($job_id);

    if ( ( not defined($job) || $job->user_id == $USER->id )
        && not $USER->is_admin )
    {
        say STDERR "Job.pl: job $job->id expected user id "
          . "$job->user_id but received $USER->id";
        return;
    }

    return $job;
}

sub _check_job_args {
    my %args   = @_;
    my $job_id = $args{job};

    if ( not defined($job_id) ) {
        say STDERR "Job.pl: a job id was not given to cancel_job.";
    }

    return $job_id;
}
