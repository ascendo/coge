#! /usr/bin/perl -w

use strict;
use CGI;
use CGI::Ajax;
use CoGe::Accessory::LogUser;
use CoGe::Accessory::Web;
use CoGeX;
use CoGeX::Feature;
use CoGeX::Dataset;
use HTML::Template;
use CoGe::Genome;
use Text::Wrap qw($columns &wrap);
use Data::Dumper;
use POSIX;

$ENV{PATH} = "/opt/apache/CoGe/";

use vars qw( $TEMPDIR $TEMPURL $FORM $USER $DATE $DB $coge);

$TEMPDIR = "/opt/apache/CoGe/tmp";
$TEMPURL = "/CoGe/tmp";
$DATE = sprintf( "%04d-%02d-%02d %02d:%02d:%02d",
		sub { ($_[5]+1900, $_[4]+1, $_[3]),$_[2],$_[1],$_[0] }->(localtime));
($USER) = CoGe::Accessory::LogUser->get_user();
$DB = new CoGe::Genome;
$FORM = new CGI;

my $connstr = 'dbi:mysql:dbname=genomes;host=biocon;port=3306';
$coge = CoGeX->connect($connstr, 'cnssys', 'CnS' );

my $pj = new CGI::Ajax(
		       gen_html=>\&gen_html,
		       get_seq=>\&get_seq,
		       gen_title=>\&gen_title,
		       find_feats=>\&find_feats,
		       parse_url=>\&parse_url,
		       generate_feat_info=>\&generate_feat_info,
			);
$pj->js_encode_function('escape');
print $pj->build_html($FORM, \&gen_html);
#print $FORM->header;
#print gen_html();

sub gen_html
  {
    my $html;
    unless ($USER)
      {
		$html = login();
      }
    else
     {
    my $form = $FORM;
    my $featid = $form->param('featid');
    my $rc = $form->param('rc');
    my $pro;
    my ($title) = gen_title(protein=>$pro, rc=>$rc);
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/generic_page.tmpl');
    $template->param(TITLE=>'Sequence Viewer');
    $template->param(HELP=>'SeqView');
    $template->param(USER=>$USER);
    $template->param(DATE=>$DATE);
    $template->param(LOGO_PNG=>"SeqView-logo.png");
    $template->param(BOX_NAME=>qq{<DIV id="box_name">$title</DIV>});
    $template->param(BODY=>gen_body());
    $template->param(POSTBOX=>gen_foot());
    #if($featid)
     #{$template->param(CLOSE=>1);}
    #print STDERR gen_foot()."\n";
    $html .= $template->output;
    }
    return $html;
  }

sub gen_body
  {
    my $form = $FORM;
    my $featid = $form->param('featid') || 0;
    my $chr = $form->param('chr');
    my $dsid = $form->param('dsid');
    my $feat_name = $form->param('featname');
    my $rc = $form->param('rc');
    my $pro = $form->param('pro');   
    my $upstream = $form->param('upstream') || 0;
    my $downstream = $form->param('downstream') || 0;
    my $start = $form->param('start');
    my $stop = $form->param('stop');
    my $seq;
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/SeqView.tmpl');
    $template->param(JS=>1);
    $template->param(SEQ_BOX=>1);
    if ($featid)
    {
   		$template->param(FEATID=>$featid);
    	$template->param(FEATNAME=>$feat_name);
    	$template->param(FEAT_INFO=>qq{<td valign=top><input type=button value="Get Feature Info" onClick="generate_feat_info(['args__$featid'],[display_feat_info])"><br><div id=feature_info style="display:none"></div>});
    }
    else
    {
		$template->param(FEATID=>'false');
    }
    $template->param(DSID=>$dsid);
    $template->param(CHR=>$chr);
    my $html = $template->output;
    return $html;
  }
 
sub check_strand
{
    my %opts = @_;
    my $strand = $opts{'strand'} || 1;
    my $rc = $opts{'rc'} || 0;
    #print STDERR Dumper \%opts;
    if ($rc==1)
    {
        if ($strand =~ /-/)
          {
            $strand = "1";
          }
        else
          {
            $strand = "-1";
          }
      }
     elsif ($strand =~ /-/)
     {
       $strand =~ s/^\-$/-1/;
     }
     else 
     {
       $strand =~ s/^\+$/1/;
     }
    return $strand;
}

sub get_seq
  {
    my %opts = @_;
    my $add_to_seq = $opts{'add'};
    my $featid = $opts{'featid'} || 0;
    $featid = 0 if $featid eq "undefined"; #javascript funkiness
    my $pro = $opts{'pro'};
    #my $pro = 1;
    my $rc = $opts{'rc'} || 0;
    my $chr = $opts{'chr'};
    my $dsid = $opts{'dsid'};
    my $feat_name = $opts{'featname'};
    my $upstream = $opts{'upstream'};
    my $downstream = $opts{'downstream'};
    my $start = $opts{'start'};
    my $stop = $opts{'stop'};
    #print STDERR Dumper \%opts;
    #my $change_strand = $opts{'changestrand'} || 0;
    if($add_to_seq){
      $start = $upstream if $upstream;
      $stop = $downstream if $downstream;
    }
    #print $rc;
    my $strand;
    my $seq;
    my $fasta;
    my $fasta_no_html;
    #print STDERR Dumper \%opts;
    if ($featid)
    {
		my $feat = $coge->resultset('Feature')->find($featid);
		$strand = $feat->strand;
		$strand = check_strand(strand=>$strand, rc=>$rc);		
		$fasta = ">".$feat->org->name."(v".$feat->version.")".", Name: ".$feat_name.", Type: ".$feat->type->name.", Location: ".$feat->genbank_location_string.", Chromosome: ".$chr.", Strand: ".$strand."\n";
    }
    else
    {
		my $ds = $coge->resultset("Dataset")->find($dsid);
		$strand = $rc == 0 ? 1 : -1;
		$fasta = ">".$ds->organism->name.", Location: ".$start."-".$stop.", Chromosome: ".$chr.", Strand: ".$strand."\n";
		$fasta_no_html = ">".$ds->organism->name.", Location: ".$start."-".$stop.", Chromosome: ".$chr;
    }
    
    if ($pro)
    {
		$seq .= get_prot_seq_for_feat($featid);
    }
    else
    {
      	$seq .= get_dna_seq_for_feat (featid=>$featid,
      				    			  dsid=>$dsid, 
      				    			  rc=>$rc, 
      						 	      upstream=>$upstream,
      				  				  downstream=>$downstream, 
      				 				  start=>$start,
      				  				  stop=>$stop,
      								  chr=>$chr,
      				  				  fasta=>$fasta_no_html);
       if($featid)
   	   {
    	  if ($rc)
     	  {
      		  $seq = color(seq=>$seq, upstream=>$downstream, downstream=>$upstream);
      	  }
       	  else
       	  {
        	  $seq = color(seq=>$seq, upstream=>$upstream, downstream=>$downstream);
          }
       }
    }
     #print length($seq);
     $columns = 80;
     $seq = join ("\n", wrap('','',$seq));
     $seq = ($fasta. $seq) unless ($rc==2);
    #print STDERR "$seq\n";
    return $seq;
  }
  
sub gen_foot
  {
    my $form = $FORM;
    my $featid = $form->param('featid');
    my $chr = $form->param('chr');
    my $dsid = $form->param('dsid');
    my $feat_name = $form->param('featname');
    my $rc = $form->param('rc');
    my $pro = $form->param('pro');
    my $upstream = $form->param('upstream') || 0;
    my $downstream = $form->param('downstream') || 0;
    my $start = $form->param('start');
    my $stop = $form->param('stop');
    my $feat = $coge->resultset('Feature')->find($featid);
    my $strand;
    my $DNAButton;
    my $RCButton;
    my $PROButton;
    my @button_loop;
    $strand = $featid ? $feat->strand : $form->param('strand');
    my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/SeqView.tmpl');
    $template->param(BOTTOM_BUTTONS=>1);
    #print STDERR $featid if $featid;
   # print STDERR "nuthin" unless $featid;
    $template->param(ADDITION=>1);
    if ($featid){
	  $template->param(PROTEIN=>'Protein Sequence');
      $template->param(PRO_RC=>0);
      $template->param(PRO_PRO=>1);
      $template->param(EXTEND=>"Extend Sequence");
      $template->param(UPSTREAM=>"UPSTREAM: ");
      $template->param(UPVALUE=>$upstream);
      $template->param(DOWNSTREAM=>"DOWNSTREAM: ");
      $template->param(DOWNVALUE=>$downstream);
      $template->param(FEATURE=>1);
    }
    else{
      $template->param(PROTEIN=>'Six Frame Translation');
      $template->param(PRO_RC=>2);
      $template->param(PRO_PRO=>0);
      $template->param(FIND_FEATS=>1);
      $template->param(RANGE=>1);
      $template->param(EXTEND=>"Sequence Range");
      $template->param(UPSTREAM=>"START: ");
      $template->param(UPVALUE=>$start);
      $template->param(DOWNSTREAM=>"STOP: ");
      $template->param(DOWNVALUE=>$stop);
      $template->param(ADD_EXTRA=>1);
      $template->param(RANGE=>1);      
      }
   $template->param(REST=>1);
   #print STDERR $template->output."\n";
   my $html = $template->output;
   return $html;
  }
    
sub get_dna_seq_for_feat
  {
    my %opts = @_;
    my $featid = $opts{featid};
    my $dsid = $opts{dsid};
    my $rc = $opts{rc} || 0;
    my $upstream = $opts{upstream};
    my $downstream = $opts{downstream};
    my $start = $opts{start};
    my $stop = $opts{stop};
    my $chr = $opts{chr};
    my $fasta = $opts{fasta};
    my $seq;
   # print STDERR Dumper \%opts;
#    print STDERR "dsid;$dsid\n";
    if ($featid)
      {
		my $feat = $coge->resultset('Feature')->find($featid);
	    return "Unable to retrieve Feature object for id: $featid" unless ref($feat) =~ /Feature/i;
		$seq = $feat->genomic_sequence(upstream=>$upstream, downstream=>$downstream);
      }
    else
      {
		$seq = $DB->get_genomic_sequence(start=>$start,
					 stop=>$stop,
					 chr=>$chr,
					 dataset_id=>$dsid);
      }
    #    print STDERR "Done\n";
    if ($rc==1)
      {$seq = reverse_complement($seq);}
    elsif ($rc==2)
      {$seq = sixframe(seq=>$seq, fasta=>$fasta);}
    #$columns = 80;
    #$seq = join ("\n", wrap('','',$seq));
    return $seq;
  }
  
sub reverse_complement
  {
    my $seq = shift;
    $seq = reverse $seq;
    $seq =~ tr/ATCG/TAGC/;
    return $seq;
  }

sub get_prot_seq_for_feat
  {
    my $featid = shift;
    #print STDERR "featid: ", $featid, "\n";
    my $feat = $coge->resultset('Feature')->find($featid);
    my ($seq) = $feat->protein_sequence;
    $seq = "No sequence available" unless $seq;
    #print $seq;
    $columns = 60;
    $seq = join ("\n", wrap('','',$seq));
    return $seq;
  }

sub color
    {
      my %opts = @_;
      my $seq = $opts{'seq'};
#       my $rc = $opts{'rc'};
      my $upstream = $opts{'upstream'};
      my $downstream = $opts{'downstream'};
      my $up;
      my $down;
      my $main;
      my $nl1;
      $nl1 = 0;
      $up = substr($seq, 0, $upstream);
      while ($up=~/\n/g)
      	{$nl1++;}
      my $check = substr($seq, $upstream, $nl1);

      $nl1++ if $check =~ /\n/;
      $upstream += $nl1;
      $up = substr($seq, 0, $upstream);
      
      my $nl2 = 0;
      $down = substr($seq, ((length $seq)-($downstream)), length $seq);
      while ($down=~/\n/g)
      	{$nl2++;}
      $check = substr($seq, ((length $seq)-($downstream+$nl2)), $nl2);
      
      $nl2++ if $check =~ /\n/;
      $downstream += $nl2;
      $down = substr($seq, ((length $seq)-($downstream)), $downstream);
	   
	 $up = lc($up);
	 $down = lc($down);

# 	   unless ($rc)
#       {
#       $down = qq{<u>$down</u>};
#       $up = qq{<u>$up</u>};
#       }
#       else
#       {
#       $down = qq{<u>$down</u>};
#       $up = qq{<u>$up</u>};
#       }
      $main = substr($seq, $upstream, (((length $seq)) - ($downstream+$upstream)));
	  $main = uc($main);
      $seq = join("", $up, $main, $down);
      return $seq;
    }
    
sub gen_title
    {
      my %opts = @_;
      #print STDERR Dumper \@_;
      my $rc = $opts{'rc'} || 0;
      my $pro = $opts{'pro'};
      my $title;
      unless ($pro)
      {
       if ($rc == 2)
        {$title = "Six Frame Translation";}
       elsif ($rc == 1)
        {$title = "Reverse Complement";}
       else
        {$title = "DNA Sequence";}
      }
      else
      {
       $title = "Protein Sequence";
      }
      #print STDERR $title, "\n";
      return $title;
    }

sub sixframe
	{
	  my %opts = @_;
	  my $seq = $opts{seq};
	  my $fasta = $opts{fasta};
	  my $key;
	  my $sixframe;
      my $sequence = $DB->get_feat_obj->frame6_trans(seq=>$seq);
      #print STDERR Dumper ($sequence);
      foreach $key (sort {abs($a) <=> abs($b) || $b <=> $a} keys %$sequence)
      {
      	  $seq = join ("\n", wrap('','',$sequence->{$key}));
      	  $sixframe .= qq/$fasta Frame $key\n$seq\n/;
      }
      return $sixframe;
    }
	
sub find_feats
{
	#print STDERR "Here";
	my %opts = @_;
	my $start = $opts{'start'};
	my $stop = $opts{'stop'};
	my $chr = $opts{'chr'};
	my $dsid = $opts{'dsid'};
	my $template = HTML::Template->new(filename=>'/opt/apache/CoGe/tmpl/SeqView.tmpl');
	my $html = `$ENV{PATH}/FeatAnno.pl start=$start stop=$stop ds=$dsid chr=$chr`;
	$html = substr($html, (44), length($html));
        $template->param(FEATUREBOX=>1);
        $template->param(LISTFEATURES=>$html);
        #$template->param(FEATTABLE=>qq{style = "overflow: auto; height: 300px;"});
        $html = $template->output;
        return $html;
}

sub generate_feat_info
  {
    my $featid = shift;
    my ($feat) = $coge->resultset("Feature")->find($featid);
    unless (ref($feat) =~ /Feature/i)
    {
      return "Unable to retrieve Feature object for id: $featid";
    }
    my $html = qq{<a href="#" onClick="\$('#feature_info').slideToggle(pageObj.speed);" style="float: right;"><img src='/CoGe/picts/delete.png' width='16' height='16' border='0'></a>};
    $html .= $feat->annotation_pretty_print_html();
    return $html;
  }
