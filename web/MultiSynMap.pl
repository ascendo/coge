#!/usr/bin/perl -w
use v5.10;
use strict;
no warnings 'redefine';
umask(0);


use CoGeX;
use CoGe::Accessory::Jex;
use CoGe::Accessory::Workflow;
use CoGe::Accessory::Web;
use CoGe::Accessory::Utils qw( commify );
use CGI;
use CGI::Carp 'fatalsToBrowser';
use CGI::Ajax;
use DBIxProfiler;
use Data::Dumper;
use HTML::Template;
use JSON::XS;
use LWP::Simple;
use LWP::UserAgent;
use Parallel::ForkManager;
use GD;
use File::Path;
use Mail::Mailer;
use Benchmark;
use DBI;
use POSIX;
use Sort::Versions;

our (
    $P,            $DEBUG,         $DIR,            $URL,
    $SERVER,       $USER,          $FORM,           $coge,
    $cogeweb,      $PAGE_NAME,     $FORMATDB,       $BLAST,
    $TBLASTX,      $BLASTN,        $BLASTP,         $LASTZ,
    $LAST,         $DATADIR,       $FASTADIR,       $BLASTDBDIR,
    $DIAGSDIR,     $MAX_PROC,      $DAG_TOOL,       $PYTHON,
    $PYTHON26,     $TANDEM_FINDER, $RUN_DAGCHAINER, $EVAL_ADJUST,
    $FIND_NEARBY,  $DOTPLOT,       $SVG_DOTPLOT,    $NWALIGN,
    $QUOTA_ALIGN,  $CLUSTER_UTILS, $BLAST2RAW,      $BASE_URL,
    $BLAST2BED,    $SYNTENY_SCORE, $TEMPDIR,        $TEMPURL,
    $ALGO_LOOKUP,  $GZIP,          $GUNZIP,         %FUNCTIONS,
    $YERBA,        $GENE_ORDER,    $PAGE_TITLE,     $KSCALC,
    $GEN_FASTA,    $RUN_ALIGNMENT, $RUN_COVERAGE,   $GEVO_LINKS,
    $PROCESS_DUPS, $DOTPLOT_DOTS,
);

$DEBUG = 0;
$|     = 1;    # turn off buffering

$FORM       = new CGI;
$PAGE_TITLE = "MultiSynMap";
$PAGE_NAME  = "$PAGE_TITLE.pl";

( $coge, $USER, $P ) = CoGe::Accessory::Web->init(
    cgi => $FORM,
    page_title => $PAGE_TITLE,
);

$YERBA = CoGe::Accessory::Jex->new( host => $P->{JOBSERVER}, port => $P->{JOBPORT} );

$ENV{PATH} = join ":",
  (
    $P->{COGEDIR}, $P->{BINDIR}, $P->{BINDIR} . "SynMap",
    "/usr/bin", "/usr/local/bin"
  );
$ENV{BLASTDB}    = $P->{BLASTDB};
$ENV{BLASTMAT}   = $P->{BLASTMATRIX};
$ENV{PYTHONPATH} = "/opt/apache/CoGe/bin/dagchainer_bp";

$BASE_URL = $P->{SERVER};
$DIR      = $P->{COGEDIR};
$URL      = $P->{URL};
$SERVER   = $P->{SERVER};
$TEMPDIR  = $P->{TEMPDIR} . "SynMap";
$TEMPURL  = $P->{TEMPURL} . "SynMap";
$FORMATDB = $P->{FORMATDB};
$MAX_PROC = $P->{MAX_PROC};
$BLAST    = $P->{BLAST} . " -a " . $MAX_PROC . " -K 80 -m 8 -e 0.0001";
my $blast_options = " -num_threads $MAX_PROC -evalue 0.0001 -outfmt 6";
$TBLASTX = $P->{TBLASTX} . $blast_options;
$BLASTN  = $P->{BLASTN} . $blast_options;
$BLASTP  = $P->{BLASTP} . $blast_options;
$LASTZ =
    $P->{PYTHON} . " "
  . $P->{MULTI_LASTZ}
  . " -A $MAX_PROC --path="
  . $P->{LASTZ};
$LAST =
    $P->{MULTI_LAST}
  . " -a $MAX_PROC --path="
  . $P->{LAST_PATH};
# mdb removed 9/20/13 issue 213
#  . " --dbpath="
#  . $P->{LASTDB};
$GZIP          = $P->{GZIP};
$GUNZIP        = $P->{GUNZIP};
$KSCALC        = $P->{KSCALC};
$GEN_FASTA     = $P->{GEN_FASTA};
$RUN_ALIGNMENT = $P->{RUN_ALIGNMENT};
$RUN_COVERAGE  = $P->{RUN_COVERAGE};
$PROCESS_DUPS  = $P->{PROCESS_DUPS};
$GEVO_LINKS =  $P->{GEVO_LINKS};
$DOTPLOT_DOTS = $P->{DOTPLOT_DOTS};

#in the web form, each sequence search algorithm has a unique number.  This table identifies those and adds appropriate options
$ALGO_LOOKUP = {
    0 => {
        algo => $BLASTN . " -task megablast",    #megablast
        opt             => "MEGA_SELECT",  #select option for html template file
        filename        => "megablast",
        displayname     => "MegaBlast",
        html_select_val => 0,
        formatdb        => 1,
    },
    1 => {
        algo     => $BLASTN . " -task dc-megablast",   #discontinuous megablast,
        opt      => "DCMEGA_SELECT",
        filename => "dcmegablast",
        displayname     => "Discontinuous MegaBlast",
        html_select_val => 1,
        formatdb        => 1,
    },
    2 => {
        algo            => $BLASTN . " -task blastn",    #blastn
        opt             => "BLASTN_SELECT",
        filename        => "blastn",
        displayname     => "BlastN",
        html_select_val => 2,
        formatdb        => 1,
    },
    3 => {
        algo            => $TBLASTX,                     #tblastx
        opt             => "TBLASTX_SELECT",
        filename        => "tblastx",
        displayname     => "TBlastX",
        html_select_val => 3,
        formatdb        => 1,
    },
    4 => {
        algo            => $LASTZ,                       #lastz
        opt             => "LASTZ_SELECT",
        filename        => "lastz",
        displayname     => "(B)lastZ",
        html_select_val => 4,
    },
    5 => {
        algo            => $BLASTP . " -task blastp",    #blastn
        opt             => "BLASTP_SELECT",
        filename        => "blastp",
        displayname     => "BlastP",
        html_select_val => 5,
        formatdb        => 1,
    },
    6 => {
        algo            => $LAST,                        #last
        opt             => "LAST_SELECT",
        filename        => "last",
        displayname     => "Last",
        html_select_val => 6,
    },
};

$DATADIR  = $P->{DATADIR};
$DIAGSDIR = $P->{DIAGSDIR};
$FASTADIR = $P->{FASTADIR};

mkpath( $FASTADIR,    1, 0777 );
mkpath( $DIAGSDIR,    1, 0777 );    # mdb added 7/9/12
mkpath( $P->{LASTDB}, 1, 0777 );    # mdb added 7/9/12
$BLASTDBDIR = $P->{BLASTDB};

$PYTHON        = $P->{PYTHON};                         #this was for python2.5
$PYTHON26      = $P->{PYTHON};
$DAG_TOOL      = $P->{DAG_TOOL};
$BLAST2BED     = $P->{BLAST2BED};
$GENE_ORDER    = $DIR . "/bin/SynMap/gene_order.py";
$TANDEM_FINDER = $P->{TANDEM_FINDER}
  . " -d 5 -s -r"
  ; #-d option is the distance (in genes) between dups -- not sure if the -s and -r options are needed -- they create dups files based on the input file name

#$RUN_DAGHAINER = $DIR."/bin/dagchainer/DAGCHAINER/run_DAG_chainer.pl -E 0.05 -s";
$RUN_DAGCHAINER = $PYTHON26 . " " . $P->{DAGCHAINER};
$EVAL_ADJUST    = $P->{EVALUE_ADJUST};

$FIND_NEARBY = $P->{FIND_NEARBY}
  . " -d 20"
  ; #the parameter here is for nucleotide distances -- will need to make dynamic when gene order is selected -- 5 perhaps?

#programs to run Haibao Tang's quota_align program for merging diagonals and mapping coverage
$QUOTA_ALIGN   = $P->{QUOTA_ALIGN};     #the program
$CLUSTER_UTILS = $P->{CLUSTER_UTILS};   #convert dag output to quota_align input
$BLAST2RAW     = $P->{BLAST2RAW};       #find local duplicates
$SYNTENY_SCORE = $P->{SYNTENY_SCORE};

$DOTPLOT     = $P->{DOTPLOT} . " -cf " . $ENV{COGE_HOME} . 'coge.conf';
$SVG_DOTPLOT = $P->{SVG_DOTPLOT};

#$CONVERT_TO_GENE_ORDER = $DIR."/bin/SynMap/convert_to_gene_order.pl";
#$NWALIGN = $DIR."/bin/nwalign-0.3.0/bin/nwalign";
$NWALIGN = $P->{NWALIGN};

my %ajax = CoGe::Accessory::Web::ajax_func();

#$ajax{read_log}=\&read_log_test;
#print $pj->build_html( $FORM, \&gen_html );
#print "Content-Type: text/html\n\n";print gen_html($FORM);

%FUNCTIONS = (
    get_orgs               => \&get_orgs,
    get_genome_info        => \&get_genome_info,
    get_previous_analyses  => \&get_previous_analyses,
    get_pair_info          => \&get_pair_info,
    check_address_validity => \&check_address_validity,
    generate_basefile      => \&generate_basefile,
    gen_dsg_menu           => \&gen_dsg_menu,
    get_dsg_gc             => \&get_dsg_gc,
    %ajax,
);

my $pj = new CGI::Ajax(%FUNCTIONS);
if ( $FORM->param('jquery_ajax') ) {
    my %args  = $FORM->Vars;
    my $fname = $args{'fname'};

    #print STDERR Dumper \%args;
    if ( $fname and defined $FUNCTIONS{$fname} ) {
        if ( $args{args} ) {
            my @args_list = split( /,/, $args{args} );
            print $FORM->header, $FUNCTIONS{$fname}->(@args_list);
        }
        else {
            print $FORM->header, $FUNCTIONS{$fname}->(%args);
        }
    }
}
else {
    $pj->js_encode_function('escape');
    print $pj->build_html( $FORM, \&gen_html );

    #   print $FORM->header; print gen_html();
}

################################################################################
# Web functions
################################################################################

sub read_log_test {
    my %args    = @_;
    my $logfile = $args{logfile};
    my $prog    = $args{prog};
    return unless $logfile;
    $logfile .= ".log" unless $logfile =~ /log$/;
    $logfile = $TEMPDIR . "/$logfile" unless $logfile =~ /^$TEMPDIR/;
    return unless -r $logfile;
    my $str;
    open( IN, $logfile );

    while (<IN>) {
        $str .= $_;
    }
    close IN;
    return $str;
}

sub gen_html {
    my $html;
    my ($body) = gen_body();
    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . 'generic_page.tmpl' );
    $template->param( PAGE_TITLE => 'SynMap' );
    $template->param( TITLE      => 'Whole Genome Synteny' );
    $template->param( HEAD       => qq{} );
    my $name = $USER->user_name;
    $name = $USER->first_name if $USER->first_name;
    $name .= " " . $USER->last_name if $USER->first_name && $USER->last_name;
    $template->param( USER => $name );

    $template->param( LOGON => 1 ) unless $USER->user_name eq "public";

    #$template->param(ADJUST_BOX=>1);
    $template->param( LOGO_PNG => "SynMap-logo.png" );
    $template->param( BODY     => $body );
    $template->param( HELP     => "/wiki/index.php?title=SynMap" );
    $html .= $template->output;
    return $html;
}

sub gen_body {
    my $form = shift || $FORM;
    my $template =
      HTML::Template->new( filename => $P->{TMPLDIR} . 'MultiSynMap.tmpl' );

    $template->param( MAIN => 1 );

    #$template->param( EMAIL       => $USER->email )  if $USER->email;

    my $master_width = $FORM->param('w') || 0;
    $template->param( MWIDTH => $master_width );

    #set search algorithm on web-page
    if ( defined( $FORM->param('b') ) ) {
        $template->param(
            $ALGO_LOOKUP->{ $FORM->param('b') }{opt} => "selected" );
    }
    else {
        $template->param( $ALGO_LOOKUP->{6}{opt} => "selected" );
    }
    my ( $D, $A, $Dm, $gm, $dt, $dupdist, $cscore );
    $D  = $FORM->param('D');
    $A  = $FORM->param('A');
    $Dm = $FORM->param('Dm');
    $gm = $FORM->param('gm');
    $gm //= 40;
    $dt     = $FORM->param('dt');
    $cscore = $FORM->param('csco');
    $cscore //= 0;
    $dupdist = $FORM->param('tdd');

#   $cvalue = $FORM->param('c');       #different c value than the one for cytology.  But if you get that, you probably shouldn't be reading this code

    my $display_dagchainer_settings;
    if ( $D && $A && $dt ) {
        my $type;
        if ( $dt =~ /gene/i ) {
            $type = " genes";
            $template->param( 'DAG_GENE_SELECT' => 'checked' );
        }
        else {
            $type = " bp";
            $template->param( 'DAG_DISTANCE_SELECT' => 'checked' );
        }
        $display_dagchainer_settings =
          qq{display_dagchainer_settings([$D,$A, '$gm', $Dm],'$type');};
    }
    else {
        $template->param( 'DAG_GENE_SELECT' => 'checked' );
        $display_dagchainer_settings = qq{display_dagchainer_settings();};
    }

    #   $cvalue = 4 unless defined $cvalue;
    #   $template->param( 'CVALUE'                      => $cvalue );
    $dupdist = 10 unless defined $dupdist;
    $template->param( 'DUPDIST' => $dupdist );
    $template->param( 'CSCORE'  => $cscore );
    $template->param(
        'DISPLAY_DAGCHAINER_SETTINGS' => $display_dagchainer_settings );
    $template->param( 'MIN_CHR_SIZE' => $FORM->param('mcs') )
      if $FORM->param('mcs');

    #will the program automatically run?
    my $autogo = $FORM->param('autogo');
    $autogo = 0 unless defined $autogo;
    $template->param( AUTOGO => $autogo );

#if the page is loading with genomes, there will be a check for whether the genome is rest
#populate organism menus
    my $error = 0;

    for ( my $i = 1 ; $i <= 1 ; $i++ ) {
        my $dsgid = 0;
        $dsgid = $form->param( 'dsgid' . $i )
          if $form->param( 'dsgid' . $i );    #old method for specifying genome
        $dsgid = $form->param( 'gid' . $i )
          if $form->param( 'gid' . $i );      #new method for specifying genome
        my $feattype_param = $FORM->param( 'ft' . $i )
          if $FORM->param( 'ft' . $i );
        my $name = $FORM->param( 'name' . $i ) if $FORM->param( 'name' . $i );
        my $org_menu = gen_org_menu(
            dsgid          => $dsgid,
            num            => $i,
            feattype_param => $feattype_param,
            name           => $name
        );
        $template->param( "ORG_MENU" . $i => $org_menu );

        my ($dsg) = $coge->resultset('Genome')->find($dsgid);

        if($dsgid > 0 and !$USER->has_access_to_genome($dsg)) {
            $error = 1;
        }
    }

    if ($error) {
        $template->param("error" => 'The genome was not found or is restricted.');
    }

    #set ks for coloring syntenic dots
    if ( $FORM->param('ks') ) {
        if ( $FORM->param('ks') eq 1 ) {
            $template->param( KS1 => "selected" );
        }
        elsif ( $FORM->param('ks') eq 2 ) {
            $template->param( KS2 => "selected" );
        }
        elsif ( $FORM->param('ks') eq 3 ) {
            $template->param( KS3 => "selected" );
        }
    }
    else {
        $template->param( KS0 => "selected" );
    }

    #set color_scheme
    my $cs = 1;
    $cs = $FORM->param('cs') if defined $FORM->param('cs');
    $template->param( "CS" . $cs => "selected" );

    #set codeml min and max
    my $codeml_min;
    $codeml_min = $FORM->param('cmin') if defined $FORM->param('cmin');
    my $codeml_max;
    $codeml_max = $FORM->param('cmax') if defined $FORM->param('cmax');
    $template->param( 'CODEML_MIN' => $codeml_min ) if defined $codeml_min;
    $template->param( 'CODEML_MAX' => $codeml_max ) if defined $codeml_max;
    my $logks;
    $logks = $FORM->param('logks') if defined $FORM->param('logks');
    $logks = 1 unless defined $logks;    #turn on by default if not specified
    $template->param( 'LOGKS' => "checked" ) if defined $logks && $logks;

    #show non syntenic dots:  on by default
    my $snsd = 0;
    $snsd = $FORM->param('snsd') if ( defined $FORM->param('snsd') );
    $template->param( 'SHOW_NON_SYN_DOTS' => 'checked' ) if $snsd;

    #are the axes flipped?
    my $flip = 0;
    $flip = $FORM->param('flip') if ( defined $FORM->param('flip') );
    $template->param( 'FLIP' => 'checked' ) if $flip;

    #are the chromosomes labeled?
    my $clabel = 1;
    $clabel = $FORM->param('cl') if ( defined $FORM->param('cl') );
    $template->param( 'CHR_LABEL' => 'checked' ) if $clabel;

    #are the chromosomes labeled?
    my $skip_rand = 1;
    $skip_rand = $FORM->param('sr') if ( defined $FORM->param('sr') );
    $template->param( 'SKIP_RAND' => 'checked' ) if $skip_rand;

    #what is the sort for chromosome display?
    my $chr_sort_order = "S";
    $chr_sort_order = $FORM->param('cso') if ( defined $FORM->param('cso') );
    if ( $chr_sort_order =~ /N/i ) {
        $template->param( 'CHR_SORT_NAME' => 'selected' );
    }
    elsif ( $chr_sort_order =~ /S/i ) {
        $template->param( 'CHR_SORT_SIZE' => 'selected' );
    }

    #set axis metric for dotplot
    if ( $FORM->param('ct') ) {
        if ( $FORM->param('ct') eq "inv" ) {
            $template->param( 'COLOR_TYPE_INV' => 'selected' );
        }
        elsif ( $FORM->param('ct') eq "diag" ) {
            $template->param( 'COLOR_TYPE_DIAG' => 'selected' );
        }
    }
    else {
        $template->param( 'COLOR_TYPE_NONE' => 'selected' );
    }
    if ( $FORM->param('am') && $FORM->param('am') =~ /g/i ) {
        $template->param( 'AXIS_METRIC_GENE' => 'selected' );
    }
    else {
        $template->param( 'AXIS_METRIC_NT' => 'selected' );
    }

    #axis relationship:  will dotplot be forced into a square?
    if ( $FORM->param('ar') && $FORM->param('ar') =~ /s/i ) {
        $template->param( 'AXIS_RELATIONSHIP_S' => 'selected' );
    }
    else {
        $template->param( 'AXIS_RELATIONSHIP_R' => 'selected' );
    }

    #merge diags algorithm
    if ( $FORM->param('ma') ) {
        $template->param( QUOTA_MERGE_SELECT => 'selected' )
          if $FORM->param('ma') eq "1";
        $template->param( DAG_MERGE_SELECT => 'selected' )
          if $FORM->param('ma') eq "2";
    }
    if ( $FORM->param('da') ) {
        if ( $FORM->param('da') eq "1" ) {
            $template->param( QUOTA_ALIGN_SELECT => 'selected' );
        }
    }
    my $depth_org_1_ratio = 1;
    $depth_org_1_ratio = $FORM->param('do1') if $FORM->param('do1');
    $template->param( DEPTH_ORG_1_RATIO => $depth_org_1_ratio );
    my $depth_org_2_ratio = 1;
    $depth_org_2_ratio = $FORM->param('do2') if $FORM->param('do2');
    $template->param( DEPTH_ORG_2_RATIO => $depth_org_2_ratio );
    my $depth_overlap = 40;
    $depth_overlap = $FORM->param('do') if $FORM->param('do');
    $template->param( DEPTH_OVERLAP => $depth_overlap );

    $template->param( 'BOX_DIAGS' => "checked" ) if $FORM->param('bd');
    my $spa = $FORM->param('sp') if $FORM->param('sp');
    $template->param( 'SYNTENIC_PATH' => "checked" ) if $spa;
    $template->param( 'SHOW_NON_SYN' => "checked" ) if $spa && $spa =~ /2/;
    $template->param( 'SPA_FEW_SELECT'  => "selected" ) if $spa && $spa > 0;
    $template->param( 'SPA_MORE_SELECT' => "selected" ) if $spa && $spa < 0;
    $template->param(beta => 1) if $FORM->param("beta");

    my $file = $form->param('file');
    if ($file) {
        my $results = read_file($file);
        $template->param( RESULTS => $results );
    }

#place to store fids that are passed into SynMap to highlight that pair in the dotplot (if present)
    my $fid1 = 0;
    $fid1 = $FORM->param('fid1') if $FORM->param('fid1');

    $template->param( 'FID1' => $fid1 );
    my $fid2 = 0;
    $fid2 = $FORM->param('fid2') if $FORM->param('fid2');
    $template->param( 'FID2'      => $fid2 );
    $template->param( 'PAGE_NAME' => $PAGE_NAME );
    $template->param( 'TEMPDIR'   => $TEMPDIR );
    return $template->output;
}

sub gen_org_menu {
    my %opts           = @_;
    my $oid            = $opts{oid};
    my $num            = $opts{num};
    my $name           = $opts{name};
    my $desc           = $opts{desc};
    my $dsgid          = $opts{dsgid};
    my $feattype_param = $opts{feattype_param};
    $feattype_param = 1 unless $feattype_param;

    $name = "Search" unless $name;
    $desc = "Search" unless $desc;

    my ($dsg) = $coge->resultset('Genome')->find($dsgid);
    my $menu_template =
      HTML::Template->new( filename => $P->{TMPLDIR} . 'partials/organism_menu.tmpl' );
    $menu_template->param( ORG_MENU => 1 );
    $menu_template->param( NUM      => $num );
    $menu_template->param( ORG_NAME => $name );
    $menu_template->param( ORG_DESC => $desc );

    if ($dsg and $USER->has_access_to_genome($dsg)) {
        my $org = $dsg->organism;
        $oid = $org->id;


        my ( $dsg_info, $feattype_menu, $message ) = get_genome_info(
            dsgid    => $dsgid,
            org_num  => $num,
            feattype => $feattype_param
        );

        $menu_template->param( DSG_INFO       => $dsg_info );
        $menu_template->param( FEATTYPE_MENU  => $feattype_menu );
        $menu_template->param( GENOME_MESSAGE => $message );
    }  else {
        $oid = 0;
        $dsgid = 0;
    }

    $menu_template->param(
        'ORG_LIST' => get_orgs( name => $name, i => $num, oid => $oid ) );

    my ($dsg_menu) = gen_dsg_menu( oid => $oid, dsgid => $dsgid, num => $num );
    $menu_template->param( DSG_MENU => $dsg_menu );

    return $menu_template->output;
}

sub gen_dsg_menu {
    my $t1    = new Benchmark;
    my %opts  = @_;
    my $oid   = $opts{oid};
    my $num   = $opts{num};
    my $dsgid = $opts{dsgid};
    my @dsg_menu;
    my $message;
    my $org_name;

    my @genomes;

    #    print STDERR join ("\n", map {$_->id} $USER->genomes),"\n";
    foreach my $dsg (
        $coge->resultset('Genome')->search(
            { organism_id => $oid },
            {
                prefetch => ['genomic_sequence_type'],
                join     => ['genomic_sequence_type']
            }
        )
      )
    {
        my $name;
        my $has_cds = 0;

        if ( $dsg->restricted && !$USER->has_access_to_genome($dsg) ) {
            next unless $dsgid && $dsg->id == $dsgid;
            $name = "Restricted";
        }
    elsif ($dsg->deleted)
      {
        if ($dsgid && $dsgid == $dsg->id)
          {
        $name = "DELETED: ".$dsg->type->name . " (v" . $dsg->version . ",id" . $dsg->id . ")";
          }
        else
          {
        next;
          }
      }
        else {
            $name .= $dsg->name . ": " if $dsg->name;
            $name .=
              $dsg->type->name . " (v" . $dsg->version . ",id" . $dsg->id . ")";
            $org_name = $dsg->organism->name unless $org_name;
            foreach my $ft (
                $coge->resultset('FeatureType')->search(
                    {
                        genome_id            => $dsg->id,
                        'me.feature_type_id' => 3
                    },
                    {
                        join =>
                          { features => { dataset => 'dataset_connectors' } },
                        rows => 1,
                    }
                )
              )
            {
                $has_cds = 1;
            }
        }
        push @dsg_menu, [ $dsg->id, $name, $dsg, $has_cds ];

        my $cds = $has_cds ? JSON::true : JSON::false;
        push @genomes, {
            id => $dsg->id,
            name => $name,
            cds => $cds,
            restricted => $dsg->restricted
        };
    }

    return encode_json({ genomes => \@genomes });

    my $dsg_menu = qq{
   <select id=dsgid$num onChange="\$('#dsg_info$num').html('<div class=dna_small class=loading class=small>loading. . .</div>'); get_genome_info(['args__dsgid','dsgid$num','args__org_num','args__$num'],[handle_dsg_info])">
};
    foreach (
        sort {
                 versioncmp( $b->[2]->version, $a->[2]->version )
              || $a->[2]->type->id <=> $b->[2]->type->id
              || $b->[3] cmp $a->[3]
        } @dsg_menu
      )
    {
        my ( $numt, $name ) = @$_;
        my $selected = " selected" if $dsgid && $numt == $dsgid;
        $selected = " " unless $selected;
        $numt = 0 if $name eq "Restricted";
        $dsg_menu .= qq{
   <OPTION VALUE=$numt $selected>$name</option>
};
    }
    $dsg_menu .= "</select>";
    my $t2 = new Benchmark;
    my $time = timestr( timediff( $t2, $t1 ) );

    #    print STDERR qq{
    #-----------------
    #sub gen_dsg_menu runtime:  $time
    #-----------------
    #};
    return ( $dsg_menu, $message );

}

sub read_file {
    my $file = shift;

    my $html;
    open( IN, $TEMPDIR . $file ) || die "can't open $file for reading: $!";
    while (<IN>) {
        $html .= $_;
    }
    close IN;
    return $html;
}

sub get_orgs {
    my %opts = @_;
    my $name = $opts{name};
    my $desc = $opts{desc};
    my $oid  = $opts{oid};
    my $i    = $opts{i};
    my @db;

    #get rid of trailing white-space
    $name =~ s/^\s+//g if $name;
    $name =~ s/\s+$//g if $name;
    $desc =~ s/^\s+//g if $desc;
    $desc =~ s/\s+$//g if $desc;

    $name = ""
      if $name && $name =~ /Search/;    #need to clear to get full org count
    $desc = ""
      if $desc && $desc =~ /Search/;    #need to clear to get full org count
    my $org_count;
    if ($oid) {
        my $org = $coge->resultset("Organism")->find($oid);
        $name = $org->name if $org;
        push @db, $org if $name;
    }
    elsif ($name) {
        @db =
          $coge->resultset("Organism")
          ->search( { name => { like => "%" . $name . "%" } } );
    }
    elsif ($desc) {
        @db =
          $coge->resultset("Organism")
          ->search( { description => { like => "%" . $desc . "%" } } );
    }
    else {
        $org_count = $coge->resultset("Organism")->count;
    }

    my @organisms;

    for my $organism (@db) {
        push @organisms, {
            id => $organism->id,
            name => $organism->name
        };
    };

    return encode_json({ organisms => \@organisms });

    my @opts;
    foreach my $item ( sort { uc( $a->name ) cmp uc( $b->name ) } @db ) {
        my $option = "<OPTION value=\"" . $item->id . "\"";
        $option .= " selected" if $oid && $oid == $item->id;
        $option .= ">" . $item->name . " (id" . $item->id . ")</OPTION>";
        push @opts, $option;

    }
    $org_count = scalar @opts unless $org_count;
    my $html;
    $html .=
        qq{<FONT CLASS ="small">Organism count: }
      . $org_count
      . qq{</FONT>\n<BR>\n};
    unless ( @opts && ( $name || $desc ) ) {
        $html .= qq{<input type = hidden name="org_id$i" id="org_id$i">};
        return $html;
    }

    $html .=
qq{<SELECT id="org_id$i" SIZE="5" MULTIPLE onChange="get_genome_info_chain($i)" >\n};
    $html .= join( "\n", @opts );
    $html .= "\n</SELECT>\n";
    $html =~ s/OPTION/OPTION SELECTED/ unless $oid;
    return $html;
}

sub get_genome_info {
    my $t1       = new Benchmark;
    my %opts     = @_;
    my $dsgid    = $opts{dsgid};
    my $org_num  = $opts{org_num};
    my $feattype = $opts{feattype};
    $feattype = 1 unless defined $feattype;
    return " ", " ", " " unless $dsgid;
    my $html_dsg_info;

#my ($dsg) = $coge->resultset("Genome")->find({genome_id=>$dsgid},{join=>['organism','genomic_sequences'],prefetch=>['organism','genomic_sequences']});
    my ($dsg) = $coge->resultset("Genome")->find( { genome_id => $dsgid },
        { join => 'organism', prefetch => 'organism' } );
    return " ", " ", " " unless $dsg;
    my $org     = $dsg->organism;
    my $orgname = $org->name;
    $orgname =
        "<a href=\"OrganismView.pl?oid="
      . $org->id
      . "\" target=_new>$orgname</a>";
    my $org_desc;
    if ( $org->description ) {
        $org_desc = join(
            "; ",
            map {
                    qq{<span class=link onclick="\$('#org_desc}
                  . qq{$org_num').val('$_').focus();search_bar('org_desc$org_num'); timing('org_desc$org_num')">$_</span>}
              } split /\s*;\s*/,
            $org->description
        );
    }
    my $i = 0;

    my (
        $percent_gc, $percent_at, $percent_n, $percent_x, $chr_length,
        $chr_count,  $plasmid,    $contig,    $scaffold
    ) = get_dsg_info($dsg);
    my ($ds) = $dsg->datasets;
    my $link = $ds->data_source->link;
    $link = $BASE_URL unless $link;
    $link = "http://" . $link unless $link && $link =~ /^http/;
    $html_dsg_info .= qq{<table class=small>};
    $html_dsg_info .= qq{<tr><td>Genome Information:</td><td class="link" onclick=window.open('GenomeInfo.pl?gid=$dsgid')>}.$dsg->info.qq{</td></tr>};
    $html_dsg_info .= qq{<tr><td>Organism:</td><td>$orgname</td></tr>};
    $html_dsg_info .= qq{<tr><td>Taxonomy:</td><td>$org_desc</td></tr>};
    $html_dsg_info .= "<tr><td>Name: <td>" . $dsg->name if $dsg->name;
    $html_dsg_info .= "<tr><td>Description: <td>" . $dsg->description
      if $dsg->description;
    $html_dsg_info .=
        "<tr><td>Source:  <td><a href="
      . $link
      . " target=_new>"
      . $ds->data_source->name . "</a>";

    #$html_dsg_info .= $dsg->chr_info(summary=>1);
    $html_dsg_info .= "<tr><td>Dataset: <td>" . $ds->name;
    $html_dsg_info .= ": " . $ds->description if $ds->description;
    $html_dsg_info .= "<tr><td>Chromosome count: <td>" . commify($chr_count);
    if ( $percent_gc > 0 ) {
        $html_dsg_info .=
"<tr><td>DNA content: <td>GC: $percent_gc%, AT: $percent_at%, N: $percent_n%, X: $percent_x%";
    }
    else {
        $html_dsg_info .=
qq{<tr><td>DNA content: <td id=gc_content$org_num class='link' onclick="get_gc($dsgid, 'gc_content$org_num')">Click to retrieve};
    }
    $html_dsg_info .= "<tr><td>Total length: <td>" . commify($chr_length);
    $html_dsg_info .= "<tr><td>Contains plasmid" if $plasmid;
    $html_dsg_info .= "<tr><td>Contains contigs" if $contig;
    $html_dsg_info .= "<tr><td>Contains scaffolds" if $scaffold;
    $html_dsg_info .= qq{<tr class="alert"><td>Restricted:</td><td>Yes} if $dsg->restricted;
    $html_dsg_info .= "</table>";
    if ( $dsg->restricted && !$USER->has_access_to_genome($dsg) ) {
        $html_dsg_info = "Restricted";
    }
    if ($dsg->deleted)
      {
    $html_dsg_info = "<span class=alert>This genome has been deleted and cannot be used in this analysis.</span>  <a href=GenomeInfo.pl?gid=$dsgid target=_new>More information</a>.";
      }
    my $t2 = new Benchmark;
    my $time = timestr( timediff( $t2, $t1 ) );

    #    print STDERR qq{
    #-----------------
    #sub get_genome_info runtime:  $time
    #-----------------
    #};

    my $message;

    #create feature type menu
    my $has_cds;

    foreach my $ft (
        $coge->resultset('FeatureType')->search(
            {
                genome_id            => $dsg->id,
                'me.feature_type_id' => 3
            },
            {
                join => { features => { dataset => 'dataset_connectors' } },
                rows => 1,
            }
        )
      )
    {
        $has_cds = 1;
    }

    my ( $cds_selected, $genomic_selected ) = ( " ", " " );
    $cds_selected     = "selected" if $feattype eq 1 || $feattype eq "CDS";
    $genomic_selected = "selected" if $feattype eq 2 || $feattype eq "genomic";

    my $feattype_menu =
      qq{<select id="feat_type$org_num" name ="feat_type$org_num">#};
    $feattype_menu .= qq{<OPTION VALUE=1 $cds_selected>CDS</option>}
      if $has_cds;
    $feattype_menu .= qq{<OPTION VALUE=2 $genomic_selected>genomic</option>};
    $feattype_menu .= "</select>";
    $message = "<span class='small alert'>No Coding Sequence in Genome</span>"
      unless $has_cds;

    return $html_dsg_info, $feattype_menu, $message, $chr_length, $org_num,
      $dsg->organism->name, $dsg->genomic_sequence_type_id;
}

sub get_previous_analyses {

    #FIXME:  THis whole sub needs updating or removal!  Lyons 6/12/13
    my %opts = @_;
    my $oid1 = $opts{oid1};
    my $oid2 = $opts{oid2};
    return unless $oid1 && $oid2;
    my ($org1) = $coge->resultset('Organism')->find($oid1);
    my ($org2) = $coge->resultset('Organism')->find($oid2);
    return
      if ( $USER->user_name =~ /public/i
        && ( $org1->restricted || $org2->restricted ) );
    my ($org_name1) = $org1->name;
    my ($org_name2) = $org2->name;
    ( $oid1, $org_name1, $oid2, $org_name2 ) =
      ( $oid2, $org_name2, $oid1, $org_name1 )
      if ( $org_name2 lt $org_name1 );

    my $tmp1 = $org_name1;
    my $tmp2 = $org_name2;
    foreach my $tmp ( $tmp1, $tmp2 ) {
        $tmp =~ s/\///g;
        $tmp =~ s/\s+/_/g;
        $tmp =~ s/\(//g;
        $tmp =~ s/\)//g;
        $tmp =~ s/://g;
        $tmp =~ s/;//g;
        $tmp =~ s/#/_/g;
        $tmp =~ s/'//g;
        $tmp =~ s/"//g;
    }

    my $dir = $tmp1 . "/" . $tmp2;
    $dir = "$DIAGSDIR/" . $dir;
    my $sqlite = 0;
    my @items;
    if ( -d $dir ) {
        opendir( DIR, $dir );
        while ( my $file = readdir(DIR) ) {
            $sqlite = 1 if $file =~ /sqlite$/;
            next unless $file =~ /\.aligncoords/;    #$/\.merge$/;
            my ( $D, $g, $A ) = $file =~ /D(\d+)_g(\d+)_A(\d+)/;
            my ($Dm) = $file =~ /Dm(\d+)/;
            my ($gm) = $file =~ /gm(\d+)/;
            my ($ma) = $file =~ /ma(\d+)/;
            $Dm = " " unless defined $Dm;
            $gm = " " unless defined $gm;
            $ma = 0   unless $ma;
            my $merge_algo;
            $merge_algo = "DAGChainer" if $ma && $ma == 2;

            if ( $ma && $ma == 1 ) {
                $merge_algo = "Quota Align";
                $gm         = " ";
            }
            unless ($ma) {
                $merge_algo = "--none--";
                $gm         = " ";
                $Dm         = " ";
            }

            #       $Dm = 0 unless $Dm;
            #       $gm = 0 unless $gm;
            next unless ( $D && $g && $A );

            my ($blast) = $file =~
              /^[^\.]+\.[^\.]+\.([^\.]+)/;    #/blastn/ ? "BlastN" : "TBlastX";
            my $select_val;
            foreach my $item ( values %$ALGO_LOOKUP ) {
                if ( $item->{filename} eq $blast ) {
                    $blast      = $item->{displayname};
                    $select_val = $item->{html_select_val};
                }
            }
            my ( $dsgid1, $dsgid2, $type1, $type2 ) =
              $file =~ /^(\d+)_(\d+)\.(\w+)-(\w+)/;
            $type1 = "CDS" if $type1 eq "protein";
            $type2 = "CDS" if $type2 eq "protein";

            #           print STDERR $file,"\n";
            #           my ($repeat_filter) = $file =~ /_c(\d+)/;
            next unless ( $dsgid1 && $dsgid2 && $type1 && $type2 );
            my ($dupdist) = $file =~ /tdd(\d+)/;
            my %data = (

           #                                    repeat_filter => $repeat_filter,
                tdd        => $dupdist,
                D          => $D,
                g          => $g,
                A          => $A,
                Dm         => $Dm,
                gm         => $gm,
                ma         => $ma,
                merge_algo => $merge_algo,
                blast      => $blast,
                dsgid1     => $dsgid1,
                dsgid2     => $dsgid2,
                select_val => $select_val
            );
            my $geneorder = $file =~ /\.go/;
            my $dsg1 = $coge->resultset('Genome')->find($dsgid1);
            next unless $dsg1;
            next
              if ( $dsg1->restricted && !$USER->has_access_to_genome($dsg1) );
            my ($ds1) = $dsg1->datasets;
            my $dsg2 = $coge->resultset('Genome')->find($dsgid2);
            next unless $dsg2;
            next
              if ( $dsg2->restricted && !$USER->has_access_to_genome($dsg2) );
            my ($ds2) = $dsg2->datasets;
            $data{dsg1} = $dsg1;
            $data{dsg2} = $dsg2;
            $data{ds1}  = $ds1;
            $data{ds2}  = $ds2;
            my $genome1;
            $genome1 .= $dsg1->name if $dsg1->name;
            $genome1 .= ": "        if $genome1;
            $genome1 .= $ds1->data_source->name;
            my $genome2;
            $genome2 .= $dsg2->name if $dsg2->name;
            $genome2 .= ": "        if $genome2;
            $genome2 .= $ds2->data_source->name;
            $data{genome1}    = $genome1;
            $data{genome2}    = $genome2;
            $data{type_name1} = $type1;
            $data{type_name2} = $type2;
            $type1 = $type1 eq "CDS" ? 1 : 2;
            $type2 = $type2 eq "CDS" ? 1 : 2;
            $data{type1}   = $type1;
            $data{type2}   = $type2;
            $data{dagtype} = $geneorder ? "Ordered genes" : "Distance";
            push @items, \%data;
        }
        closedir(DIR);
    }
    return unless @items;
    my $size = scalar @items;
    $size = 8 if $size > 8;
    my $html;
    my $prev_table = qq{<table id=prev_table class="small resultborder">};
    $prev_table .= qq{<THEAD><TR><TH>}
      . join( "<TH>",
        qw(Org1 Genome1 Ver1 Genome%20Type1 Sequence%20Type1 Org2 Genome2 Ver2 Genome%20Type2 Sequence%20type2 Algo Dist%20Type Dup%20Dist Ave%20Dist(g) Max%20Dist(D) Min%20Pairs(A))
      ) . "</THEAD><TBODY>\n";
    my %seen;

    foreach my $item (
        sort { $b->{dsgid1} <=> $a->{dsgid1} || $b->{dsgid2} <=> $a->{dsgid2} }
        @items )
    {
        my $val = join( "_",
            $item->{g},          $item->{D},       $item->{A},
            $oid1,               $item->{dsgid1},  $item->{type1},
            $oid2,               $item->{dsgid2},  $item->{type2},
            $item->{select_val}, $item->{dagtype}, $item->{tdd} );
        next if $seen{$val};
        $seen{$val} = 1;
        $prev_table .=
          qq{<TR class=feat onclick="update_params('$val')" align=center><td>};
        my $ver1 = $item->{dsg1}->version;
        $ver1 = "0" . $ver1 if $ver1 =~ /^\./;
        my $ver2 = $item->{dsg2}->version;
        $ver2 = "0" . $ver2 if $ver2 =~ /^\./;
        $prev_table .= join( "<td>",
            $item->{dsg1}->organism->name, $item->{genome1},
            $ver1,                         $item->{dsg1}->type->name,
            $item->{type_name1},           $item->{dsg2}->organism->name,
            $item->{genome2},              $ver2,
            $item->{dsg2}->type->name,     $item->{type_name2},
            $item->{blast},                $item->{dagtype},
            $item->{tdd},                  $item->{g},
            $item->{D},                    $item->{A} )
          . "\n";
    }
    $prev_table .= qq{</TBODY></table>};
    $html .= $prev_table;
    $html .=
"<br><span class=small>Synonymous substitution rates previously calculated</span>"
      if $sqlite;
    return "$html";
}

sub get_dsg_info {
    my $dsg       = shift;
    my $length    = 0;
    my $chr_count = 0;

    $length = $dsg->length;    #$rs->first->get_column('total_length');
    $chr_count = $dsg->genomic_sequences->count();
    my ( $gc, $at, $n, $x ) = ( 0, 0, 0, 0 );
    if ( $chr_count < 100 && $length < 50000000 ) {
        ( $gc, $at, $n, $x ) = get_dsg_gc( dsg => $dsg );
    }
    my ( $plasmid, $contig, $scaffold ) = get_chr_types( dsg => $dsg );
    return $gc, $at, $n, $x, $length, $chr_count, $plasmid, $contig, $scaffold;
}

sub get_dsg_gc {
    my %opts  = @_;
    my $dsg   = $opts{dsg};
    my $dsgid = $opts{dsgid};
    my $text  = $opts{text};
    $dsg = $coge->resultset('Genome')->find($dsgid) if $dsgid;
    my ( $gc, $at, $n, $x ) = $dsg->percent_gc;
    $gc *= 100;
    $at *= 100;
    $n  *= 100;
    $x  *= 100;

    if ($text) {
        return "GC: $gc%, AT: $at%, N: $n%, X: $x%";
    }
    else {
        return ( $gc, $at, $n, $x );
    }
}

sub get_chr_types {
    my %opts  = @_;
    my $dsg   = $opts{dsg};
    my $dsgid = $opts{dsgid};
    $dsg = $coge->resultset('Genome')->find($dsgid) if $dsgid;
    my $plasmid  = 0;
    my $contig   = 0;
    my $scaffold = 0;
    my @gs       = $dsg->genomic_sequences;
    if ( @gs > 100 ) {
        return ( 0, 1, 0 );
    }
    foreach my $chr ( map { $_->chromosome } @gs ) {
        $plasmid  = 1 if !$plasmid  && $chr =~ /plasmid/i;
        $contig   = 1 if !$contig   && $chr =~ /contig/i;
        $scaffold = 1 if !$scaffold && $chr =~ /scaffold/i;
    }
    return ( $plasmid, $contig, $scaffold );
}

sub get_pair_info {
    my @anno;
    foreach my $fid (@_) {
        unless ( $fid =~ /^\d+$/ ) {
            push @anno, $fid . "<br>genomic";
            next;
        }
        my $feat = $coge->resultset('Feature')->find($fid);

#       my $anno     = "Name: " . join( ", ", map { "<a class=\"data link\" href=\"$URL/FeatView.pl?accn=" . $_ . "\" target=_new>" . $_ . "</a>" } $feat->names );
#       my $location = "Chr " . $feat->chromosome . " ";
#       $location .= commify( $feat->start ) . " - " . commify( $feat->stop );

        #   $location .=" (".$feat->strand.")";
        #       push @anno, $location . "<br>" . $anno;
        push @anno, $feat->annotation_pretty_print_html;
    }
    return unless @anno;
    my $output =
        "<table class=small valign=top>"
      . join( "\n", ( map { "<tr><td>" . $_ . "</td></tr>" } @anno ) )
      . "</table>";
    my $URL = $P->{URL};
    $output =~ s/window\.open\('(.*?)'\)/window.open('$URL$1')/g;
    return $output;
}

sub gen_org_name {
    my %opts      = @_;
    my $dsgid     = $opts{dsgid};
    my $feat_type = $opts{feat_type} || 1;
    my $write_log = $opts{write_log} || 0;
    my ($dsg) = $coge->resultset('Genome')->search( { genome_id => $dsgid },
        { join => 'organism', prefetch => 'organism' } );

    my $org_name = $dsg->organism->name;
    my $title =
        $org_name . " (v"
      . $dsg->version
      . ", dsgid"
      . $dsgid . ") "
      . $feat_type;
    $title =~ s/(`|')//g;

    if ($write_log) {
        CoGe::Accessory::Web::write_log( "Generated organism name:",
            $cogeweb->logfile );
        CoGe::Accessory::Web::write_log( " " x (2) . $title,
            $cogeweb->logfile );
        CoGe::Accessory::Web::write_log( "", $cogeweb->logfile );
    }
    return ( $org_name, $title );
}

sub print_debug {
    my %args = @_;

    if ( defined( $args{enabled} ) && defined( $args{msg} ) && $args{enabled} )
    {
        say STDERR "DEBUG: $args{msg}";
    }
}

sub add_reverse_match {
    my %opts   = @_;
    my $infile = $opts{infile};
    $/ = "\n";
    open( IN, $infile );
    my $stuff;
    my $skip = 0;
    while (<IN>) {
        chomp;
        s/^\s+//;
        $skip = 1
          if /GEvo\.pl/
        ; #GEvo links have been added, this file was generated on a previous run.  Skip!
        last if ($skip);
        next unless $_;
        my @line = split /\s+/;
        if (/^#/) {
            my $chr1 = $line[2];
            my $chr2 = $line[4];
            $chr1 =~ s/^a//;
            $chr2 =~ s/^b//;
            next if $chr1 eq $chr2;
            $line[2] = "b" . $chr2;
            $line[4] = "a" . $chr1;
            $stuff .= join( " ", @line ) . "\n";
            next;
        }
        my $chr1 = $line[0];
        my $chr2 = $line[4];
        $chr1 =~ s/^a//;
        $chr2 =~ s/^b//;
        next if $chr1 eq $chr2;
        my @tmp1 = @line[ 1 .. 3 ];
        my @tmp2 = @line[ 5 .. 7 ];
        @line[ 1 .. 3 ] = @tmp2;
        @line[ 5 .. 7 ] = @tmp1;
        $line[0]        = "a" . $chr2;
        $line[4]        = "b" . $chr1;
        $stuff .= join( "\t", @line ) . "\n";
    }
    return if $skip;
    close IN;
    open( OUT, ">>$infile" );
    print OUT $stuff;
    close OUT;

}

sub check_address_validity {
    my $address = shift;
    return 'valid' unless $address;
    my $validity =
      $address =~
/^[_a-zA-Z0-9-]+(\.[_a-zA-Z0-9-]+)*@[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*\.(([0-9]{1,3})|([a-zA-Z]{2,3})|(aero|coop|info|museum|name))$/
      ? 'valid'
      : 'invalid';
    return $validity;
}
