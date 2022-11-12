#!/usr/bin/perl -w
# This file is part of Typic version 6.
# 2022 Guilherme P. Telles.

# A Tk dispatcher for typic.pl.

use Tk;
use Tk::widgets qw/LabEntry ROText/;
use Tk::NoteBook;
use base qw/Tk::Frame/;

use IO::Handle;

use File::HomeDir;
use File::Basename;
use Cwd qw(cwd);

use lib dirname (__FILE__);

if (($^O eq 'MSWin32' || $^O eq 'cygwin')) {
  require tkexwin;
}
else {
  require tkexcmd;
}


$cwd = File::HomeDir->my_home; #cwd();

$mqaccsf = '';
$agnaccsf = '';
$ecof = '';
$agnosticf = '';
$peptidesf = '';
$evidencef = '';
$groupsf = '';
$digest = 0;
$srmf = '';
$proteomef = '';
$contf = '';
$irtsf = '';
$outd = '';
$datad = '';
$patlas = 1;
$pabuild = 526;
$pepslen = '7,25';
$colors = '2AAF0F,DED837,DE3737';
$update = 0;
$plots = 1;
$enzyme = 'Trypsin';

@enzyme = ('Trypsin', 'Arg-C', 'Chymotrypsin', 'Glu-C DE', 'Glu-C D',
	   'Glu-C E', 'Lys-C', 'Trypsin KR');

%enzyme = ('Trypsin' => 'trypsin', 'Arg-C' => 'argc',
	   'Chymotrypsin' => 'chymotrypsin', 'Glu-C DE' => 'gluc_de',
	   'Glu-C D' => 'gluc_d', 'Glu-C E' => 'gluc_e',
	   'Lys-C' => 'lysc', 'Trypsin KR' => 'trypsin_kr');

$mw = MainWindow->new();
#print $mw->fontActual(fontname);

$mw->geometry("600x480+200+200");
$mw->optionAdd('*font', 'Arial 10');

$book = $mw->NoteBook()->pack( -fill=>'both',-expand=>1 );

$agn = $book->add( "agn",-label=>"agnostic input" );
$mq = $book->add( "mq",-label=>"MaxQuant input" );
$out = $book->add( "out",-label=>"Output options"); #,-state=>'disabled' );
$abt = $book->add( "about",-label=>"about"); #, -state=>'disabled' );

$tvl = 40;


######################################################################
$fa = $agn->Frame();
$r = 0;

$l = $fa->Label(-text => "Uniprot IDs file: *",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$agnaccsf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [ \&select_file,\$cwd,\$agnaccsf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Agnostic data file:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$agnosticf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [ \&select_file,\$cwd,\$agnosticf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Groups file:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$groupsf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$groupsf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Enzyme:",-anchor => 'e');
$f = $fa->Frame();

for ($i=0; $i<4; $i++) {
  $_ = "$enzyme[$i]";
  $f->Radiobutton(-text => $_, -variable => \$enzyme, -value => $_)->pack(-side => 'left');
}
  
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "",-anchor => 'e');
$f = $fa->Frame();

for (; $i < @enzyme; $i++) {
  $_ = "$enzyme[$i]";
  $f->Radiobutton(-text => $_, -variable => \$enzyme, -value => $_)->pack(-side => 'left');
}

$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);


$l = $fa->Label(-text => "Include in-silico digestion:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Checkbutton(-variable => \$digest)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "SRM Atlas file:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$srmf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [ \&select_file,\$cwd,\$srmf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Proteome fasta file:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$proteomef,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [ \&select_file,\$cwd,\$proteomef ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Contaminants fasta file:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$contf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [ \&select_file,\$cwd,\$contf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Add data from PeptdideAtlas:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Checkbutton(-variable => \$patlas)->pack(-side => 'left');
$f->Label(-text => "build:",-anchor => 'e')->pack(-side => 'left');
$f->Entry(-textvariable => \$pabuild,-width => 8)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "iRTs file:",-anchor => 'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$irtsf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$irtsf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fa->Label(-text => "Evidence Ontology file: *",-anchor=>'e');
$f = $fa->Frame(); 
$f->Entry(-textvariable => \$ecof,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$ecof ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$fa->place(-relx => 0.5,-anchor => "center",-rely => 0.5);


################################################################################
$fm = $mq->Frame();
$r = 0;

$l = $fm->Label(-text => "Uniprot IDs file: *",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$mqaccsf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$mqaccsf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Peptides file: *",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$peptidesf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$peptidesf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Evidence file: ",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$evidencef,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$evidencef ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Groups file:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$groupsf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$groupsf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Enzyme:",-anchor => 'e');
$f = $fm->Frame();

for ($i=0; $i<4; $i++) {
  $_ = "$enzyme[$i]";
  $f->Radiobutton(-text => $_, -variable => \$enzyme, -value => $_)->pack(-side => 'left');
}
  
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "",-anchor => 'e');
$f = $fm->Frame();

for (; $i < @enzyme; $i++) {
  $_ = "$enzyme[$i]";
  $f->Radiobutton(-text => $_, -variable => \$enzyme, -value => $_)->pack(-side => 'left');
}

$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Include in-silico digestion:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Checkbutton(-variable => \$digest)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "SRM Atlas file:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$srmf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$srmf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Proteome fasta file:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$proteomef,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$proteomef ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Contaminants fasta file:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$contf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$contf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Add data from PeptdideAtlas:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Checkbutton(-variable => \$patlas)->pack(-side => 'left');
$f->Label(-text => "build:",-anchor => 'e')->pack(-side => 'left');
$f->Entry(-textvariable => \$pabuild,-width => 8)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "iRTs file:",-anchor => 'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$irtsf,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$irtsf ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fm->Label(-text => "Evidence Ontology file: *",-anchor=>'e');
$f = $fm->Frame(); 
$f->Entry(-textvariable => \$ecof,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_file,\$cwd,\$ecof ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

#$fm->pack(-side => 'top',-pady => 20);
$fm->place(-relx => 0.5,-anchor => "center",-rely => 0.5);


################################################################################
$fo = $out->Frame();
$r = 0;

$l = $fo->Label(-text => "Output folder:",-anchor => 'e');
$f = $fo->Frame(); 
$f->Entry(-textvariable => \$outd,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_dir,\$cwd,\$outd ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fo->Label(-text => "Peptide length range:",-anchor => 'e');
$f = $fo->Frame(); 
$f->Entry(-textvariable => \$pepslen,-width => 8)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fo->Label(-text => "Include plots:",-anchor => 'e');
$f = $fo->Frame(); 
$f->Checkbutton(-variable => \$plots)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fo->Label(-text => "Ranking colors:");
$f = $fo->Frame(); 
$f->Entry(-textvariable => \$colors,-width => 25)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fo->Label(-text => "Downloaded data folder:");
$f = $fo->Frame(); 
$f->Entry(-textvariable => \$datad,-width => $tvl)->pack(-side => 'left');
$f->Button(-text => "...",-command => [\&select_dir,\$cwd,\$datad ])->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$l = $fo->Label(-text => "Update downloaded data:");
$f = $fo->Frame(); 
$f->Checkbutton(-variable => \$update)->pack(-side => 'left');
$l->grid(-sticky =>'e',-column => 0,-row => $r);
$f->grid(-sticky =>'w',-column => 1,-row => $r++);

$fo->place(-relx => 0.5,-anchor => "center",-rely => 0.5);


################################################################################
$about = q{
Typic is a program that collects data from multiple sources and
produces a ranking of the peptides of a protein to support the
selection of proteotypic peptides.  Proteotypic peptides are those
peptides that uniquely identify a protein and are consistently
identified when a sample with a protein mixture is analyzed in an
LC/MS experiment.

Refer to typic-manual.txt for a description of Typic arguments.
};

$txt = $abt->Scrolled("Text",-scrollbars => 'oe')->pack(-expand => 1,-fill => 'both');
$txt->configure(-font => [ -family => 'Arial', -size => 10 ]);
$txt->insert('end',$about);



################################################################################
$out->ExCmd('-command',\&command_builder)->pack();

MainLoop;



sub select_file {

  my $dir = shift;
  my $file = shift;

  #my @types =
  #     (["Log files", [qw/.txt .log/]],
  #      ["All files",		'*'],);
  #$$file = $mw->getOpenFile(-filetypes => \@types);

  $$file = $mw->getOpenFile(-initialdir => $$dir);
}



sub select_dir {

  my $dir = shift;
  my $sdir = shift;
  
  $$sdir = $mw->chooseDirectory(-initialdir => $$dir);
}



sub command_builder {

  my $dirname = dirname(__FILE__);

  my $cmd = "perl $dirname/typic.pl ";
  
  if ($agnaccsf && !$mqaccsf) {
    $cmd .= "-i $agnaccsf ";
    ($agnosticf) and ($cmd .= "-t $agnosticf ");
    ($groupsf) and ($cmd .= "-g $groupsf ");
  }

  if ($mqaccsf && !$agnaccsf) {
    $cmd .= "-i $mqaccsf ";
    ($peptidesf) and ($cmd .= "-p $peptidesf ");
    ($evidencef) and ($cmd .= "-e $evidencef ");
    ($groupsf) and ($cmd .= "-g $groupsf ");
  }
    
  ($ecof) and ($cmd .= "-v $ecof ");

  ($digest) and ($cmd .= "-d ");
  $cmd .= "-z $enzyme{$enzyme} ";
  
  ($srmf) and ($cmd .= "-s $srmf ");
  ($proteomef) and ($cmd .= "-f $proteomef ");
  ($contf ne '') and ($cmd .= "-c $contf ");
  ($irtsf) and ($cmd .= "-r $irtsf ");
  ($patlas) and ($cmd .= "-a $pabuild ");
  ($outd) and ($cmd .= "-o $outd ");
  ($datad) and ($cmd .= "-w $datad ");
  ($update) and ($cmd .= "-u ");
  (!$plots) and ($cmd .= "-n ");
  ($pepslen) and ($cmd .= "-l $pepslen ");
  ($colors) and ($cmd .= "-k $colors ");

  #$id = $book->raised();
  #print "$id $cmd\n";

  return $cmd;
}
