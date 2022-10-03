#!/usr/bin/perl -w
# A web interface to typic.
# This file is part of Typic version 6.
# 2022 Guilherme P. Telles.

use strict;

use CGI qw(:standard -no_xhtml);
use CGI::Carp 'fatalsToBrowser';
$CGI::LIST_CONTEXT_WARN = 0; 
$CGI::POST_MAX = 200e6; # bytes

use Encode;
use Fcntl ':flock';
use Time::Local;
use Archive::Zip qw(:ERROR_CODES :CONSTANTS);

$ecof = 'typic-data/eco.obo';  # -v for typic.pl
$datad = 'typic-data';         # -w for typic.pl

$jobsf = 'typic.jobs';

$| = 1; 
umask(0007);

if (request_method() eq 'POST') {
  my $action = param('action');
  
  if (!$action) {
    form();
  }
  elsif ($action eq 'agnostic') {
    subm_job();
  }
  elsif ($action eq 'maxquant') {
    subm_job();
  }
}
else {
  form();
}
exit(0);



################################################################################
sub form {

  print_html_start();

  my $popts = load_select("slct-proteomes.txt");
  my $copts = load_select("slct-contaminants.txt");
  my $sopts = load_select("slct-srms.txt");
  my $iopts = load_select("slct-irts.txt");

  my $help = load_file("help.html");
  my $about = load_file("about.html");
  

  my %title = titles();

  foreach $key (keys(%title)) {
      $_ = $title{$key};
      s/\\n\s*/\n/g;
      $title{$key} = $_;
  }
  
  
  print <<END;

<script type="text/javascript" src="typic.js"></script>
<noscript><div class="f95"><p>Javascript must be enabled in your browser.</div></noscript>

<div class="f95">
<h1>typic</h1>

<div class="tab">
  <button class="tablinks" onclick="opentab(event,'agnostic')" id="deftab">agnostic input</button>
  <button class="tablinks" onclick="opentab(event,'maxquant')">MaxQuant input</button>
  <button class="tablinks" onclick="opentab(event,'help')">help</button>
  <button class="tablinks" onclick="opentab(event,'about')">about</button>
</div>


<div id="agnostic" class="tabcontent">

<form name="typicform" action="typic.cgi" method="POST" enctype="multipart/form-data">
<table cellspacing=5 border=0>

<tr>
<td>Uniprot IDs file: * &nbsp;&nbsp;</td>
<td><input type="file" name="idsf" id="idsf" title="$title{ACCs}"></td>
</tr>

<tr>
<td>LC/MS data file: &nbsp;&nbsp;</td>
<td><input type="file" name="agnf" id="agnf" title="$title{agnostic}"></td>
</tr>

<tr>
<td>SRM Atlas build: &nbsp;&nbsp;</td>
<td><select name="srmf" id="srmf" title="$title{srmatlas}">
<option value="">None</option>
$sopts
</select></td>
</tr>

<tr>
<td>Digest (trypsin/P): &nbsp;&nbsp;</td>
<td><input type="checkbox" id="digest" name="digest" title="$title{digest}"></td>
</tr>

<tr>
<td>Proteome: &nbsp;&nbsp;</td>
<td><select name="protf" id="protf" title="$title{proteome}">
<option value="">None</option>
$popts
</select>
or upload <input type="file" name="protuf" id="protuf" title="$title{proteomeu}">
</td>
</tr>

<tr>
<td>Contaminants: &nbsp;&nbsp;</td>
<td><select name="contsf" id="contsf" title="$title{contaminants}">
<option value="">None</option>
$copts
</select>
or upload <input type="file" name="contsuf" id="contsuf" title="$title{contaminantsu}">
</td>
</tr>

<tr>
<td>iRTs file: &nbsp;&nbsp;</td>
<td><select name="irtsf" id="irtsf" title="$title{irts}">
<option value="">None</option>
$iopts
</select>
or upload <input type="file" name="irtsuf" id="irtsuf" title="$title{irtsu}"></td>
</tr>

<tr>
<td>Include all peptides: &nbsp;&nbsp;</td>
<td><input type="checkbox" id="allpeps" name="allpeps" title="$title{allpeps}"></td>
</tr>

<tr>
<td>Alternative colors: &nbsp;&nbsp;</td>
<td><input type="checkbox" id="colors" name="colors" title="$title{colors}"></td>
</tr>

<tr>
<td>Your email: *</td>
<td><input type="text" name="email" size="35" maxlength="120" title="$title{email}"></td>
</tr>

<input type="hidden" name="action" value="agnostic">

<tr>
<td></td>
<td><input type="submit" class="button" name="subm" value="Submit"
onclick="javascript:wrap(\'sub\')"></td>
</td>
</tr>
</table>

</form>

<hr>
</div>


<div id="maxquant" class="tabcontent">

<form name="mqform" action="typic.cgi" method="POST" enctype="multipart/form-data">
<table cellspacing=5 border=0>

<tr>
<td>Uniprot IDs file: * &nbsp;&nbsp;</td>
<td><input type="file" name="idsf" id="idsf" title="$title{ACCs}"></td>
</tr>

<tr>
<td>Peptides file: * &nbsp;&nbsp;</td>
<td><input type="file" name="peptidesf" id="peptidesf" title="$title{peptides}"></td>
</tr>

<tr>
<td>Evidence file: &nbsp;&nbsp;</td>
<td><input type="file" name="evidencef" id="evidencef" title="$title{evidence}"></td>
</tr>

<tr>
<td>Groups file: &nbsp;&nbsp;</td>
<td><input type="file" name="groupsf" id="groupsf" title="$title{groups}"></td>
</tr>

<tr>
<td>SRM Atlas build: &nbsp;&nbsp;</td>
<td><select name="srmf" id="srmf" title="$title{srmatlas}">
<option value="">None</option>
$sopts
</select></td>
</tr>

<tr>
<td>Digest (trypsin/P): &nbsp;&nbsp;</td>
<td><input type="checkbox" id="digest" name="digest" title="$title{digest}"></td>
</tr>

<tr>
<td>Proteome: &nbsp;&nbsp;</td>
<td><select name="protf" id="protf" title="$title{proteome}">
<option value="">None</option>
$popts
</select>
or upload <input type="file" name="protuf" id="protuf" title="$title{proteomeu}">
</td>
</tr>

<tr>
<td>Contaminants: &nbsp;&nbsp;</td>
<td><select name="contsf" id="contsf" title="$title{contaminants}">
<option value="">None</option>
$copts
</select>
or upload <input type="file" name="contsuf" id="contsuf" title="$title{contaminantsu}">
</td>
</tr>

<tr>
<td>iRTs file: &nbsp;&nbsp;</td>
<td><select name="irtsf" id="irtsf" title="$title{irts}">
<option value="">None</option>
$iopts
</select>
or upload <input type="file" name="irtsuf" id="irtsuf" title="$title{irtsu}"></td>
</tr>

<tr>
<td>Include all peptides: &nbsp;&nbsp;</td>
<td><input type="checkbox" id="allpeps" name="allpeps" title="$title{allpeps}"></td>
</tr>

<tr>
<td>Alternative colors: &nbsp;&nbsp;</td>
<td><input type="checkbox" id="colors" name="colors" title="$title{colors}"></td>
</tr>

<tr>
<td>Your email: *</td>
<td><input type="text" name="email" size="35" maxlength="120" title="$title{email}"></td>
</tr>

<input type="hidden" name="action" value="maxquant">

<tr>
<td></td>
<td><input type="submit" class="button" name="subm" value="Submit"
onclick="javascript:wrap(\'sub\')"></td>
</td>
</tr>
</table>

</form>

<hr>
</div>


<div id="help" class="tabcontent">
$help
</div>


<div id="about" class="tabcontent">
$about
</div>

</div>

<script>document.getElementById("deftab").click();</script>

END

  print end_html();
}



################################################################################
sub subm_job {

  print_html_start();

  my $input_type = param('action');

  my $idsf = param('idsf');
  (!$idsf) and abort("You must upload a file with Uniprot IDs.");

  my $agnf = '';
  my $peptidesf = '';
  my $evidencef = '';
  my $groupsf = '';
  
  if ($input_type eq "agnostic") {
    $agnf = param('agnf');
    #(!$agnf) and abort("You must upload a file with LC/MS data.");
  }
  else {
    $peptidesf = param('peptidesf');
    $evidencef = param('evidencef');
    $groupsf = param('groupsf');
    (!$peptidesf) and abort("You must upload a peptdes file.");
  }

  my $srmf = param('srmf');

  my $digest = param('digest');

  my $protf = param('protf');
  my $protuf = param('protuf');

  my $contsf = param('contsf');
  my $contsuf = param('contsuf');

  my $irtsf = param('irtsf');
  my $irtsuf = param('irtsuf');

  my $allpeps = param('allpeps');
  
  my $colors = param('colors');
  
  my $email = param('email');
  (!$email) and abort("You must fill your email in.");

  $email =~ s/\s*,\s*/,/g;
  
  (!$email || $email !~ /.+@.+/) and abort("You must fill your email in.");

  my @emails = split(/,/,$email);
  for my $m (@emails) {
    ($m !~ /.+@.+/) and abort("Invalid email address.");
  }
  
  my @set = ('0'..'9','A'..'Z','a'..'z');
  my $jobid = join('',map $set[rand @set], 1..32);
  
  mkdir($jobid,0770) or abort("subm mkdir " . cwd() . " $jobid $!");
  
  save_cgi_file('idsf',$jobid);

  if ($input_type eq "agnostic") {
    ($agnf) and ($agnf = save_cgi_file('agnf',$jobid));
  }
  else {
    ($peptidesf) and ($peptidesf = save_cgi_file('peptidesf',$jobid));
    ($evidencef) and ($evidencef = save_cgi_file('evidencef',$jobid));
    ($groupsf) and save_cgi_file('groupsf',$jobid);
  }
  
  if (!$protf && $protuf) {
    $protf = save_cgi_file('protuf',$jobid);
    $protf = "$jobid/$protf";
  }  
  
  if (!$contsf && $contsuf) {
    $contsf = save_cgi_file('contsuf',$jobid);
    $contsf = "$jobid/$contsf";
  }  

  if (!$irtsf && $irtsuf) {
    $irtsf = save_cgi_file('irtsuf',$jobid);
    $irtsf = "$jobid/$irtsf";
  }  

  my $cmd = "-i $jobid/$idsf -v $ecof -o $jobid -w $datad -a ";

  if ($input_type eq "agnostic") {
    ($agnf) and ($cmd .= "-t $jobid/$agnf ");
  }
  else {
    $cmd .= "-p $jobid/$peptidesf ";
    ($evidencef) and ($cmd .= "-e $jobid/$evidencef ");
    ($groupsf) and ($cmd .= "-g $jobid/$groupsf ");
  }

  ($digest) and ($cmd .= '-d ');
  ($srmf) and ($cmd .= "-s $srmf ");
  ($contsf) and ($cmd .= "-c $contsf ");
  ($protf) and ($cmd .= "-f $protf ");
  ($irtsf) and ($cmd .= "-r $irtsf ");
  ($allpeps) and ($cmd .= '-l 4,10000 ');
  ($colors) and ($cmd .= '-k E1DAAE,FF934F,CC2D35');
  
  open(my $fh,'>>',$jobsf) or abort("subm open $jobsf $!");
  flock($fh,LOCK_EX) or abort("subm lock $jobsf $!");
  
  print $fh "$jobid $email ", format_epoch(time), " $cmd\n";
  
  flock($fh,LOCK_UN) or abort("subm unlock $jobsf $!");
  close($fh);

  print "The system will send an email to $email when the processing is finished.";
  print '<hr><a href="typic.cgi">typic</a></div>';

  logger("$email job $jobid queued --- $cmd");
  
  print end_html();
}



################################################################################
# abort($message)
#
# Print message, write to log and exit.

sub abort {

  my $mess = shift;

  print "<p>$mess<hr></form></div></div></body></html>";
  logger($mess);

  exit(1);
}



################################################################################
# string format_epoch($seconds)
#
# Format seconds from epoch as aaaa/mm/dd hh:mm:ss.

sub format_epoch {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime( shift );

  return sprintf("%04.0f/%02.0f/%02.0f %02.0f:%02.0f:%02.0f",
                 $year+1900,$mon+1,$mday,$hour,$min,$sec);
}



################################################################################
sub print_html_start {

  print header();
  print start_html(-title=>'typic', 
		   -style=>{-src=>['typic.css']},
		   -head=>[Link({-rel=>'icon',-type=>'image/png',-href=>'icon.png'})]);
  print '<div class="f95">';
}



################################################################################
sub print_html_end {

  print '</div>';
  print end_html();
}



################################################################################
# string load_select($filename)
#
# Build options for an html select element from a text file having two
# columns separated by a space, value and option in this order.

sub load_select {

  my $file = shift;
  
  open(my $IN,'<',$file) or abort("load_select open $file $!");

  my $opt = '';
  while (<$IN>) {
    /^\s*$/ && next;
    my @aux = split(/ /,$_,2);

    $aux[0] =~ s/^\s+//;
    $aux[0] =~ s/\s+$//;
    $aux[1] =~ s/^\s+//;
    $aux[1] =~ s/\s+$//;

    $opt .= "<option value=\"$aux[0]\">$aux[1]</option>";
  }
  close($IN);

  return $opt;
}



################################################################################
# filename save_cgi_file($id, $directory)
#
# Retrieve a filename from CGI by its id and save it in directory.
# Return the filename as returned by param($id).

sub save_cgi_file {

  my $par = shift;
  my $dir = shift;
  
  my $fname = param($par);
  
  if ($fname ne '') {

    $fname =~ s/\s/_/g;
    open(my $loch,">","$dir/$fname") or abort("save_cgi_file open $dir/$fname $!");
    
    my ($bytes, $buffer);
    my $remh = upload($par);

    while ($bytes = read($remh,$buffer,1024)) {
        print $loch $buffer;
    }
    
    !defined($bytes) and abort("save_cgi_file download $par $!");
    
    close($loch);
    close($remh);
    
    if ($fname =~ /\.zip$/) {
      my $zip = Archive::Zip->new();
      my $st = $zip->read("$dir/$fname");
      ($st != AZ_OK) and abort("unable to read $fname.");
      
      my @members = $zip->memberNames();
      (@members > 1) and abort("zip file $fname must have a single file.");

      my $fz = $members[0];
      my $fl = (split(/\//,$fz))[-1];

      $st = $zip->extractMemberWithoutPaths($fz,"$dir/$fl");
      ($st != AZ_OK) and abort("unable to extract $fz from $fl.");
      chmod 0664,"$dir/$fl";
      $fname = $fl;
    }
  }

  return $fname;
}



################################################################################
# print_html_file($path, $file)
#
# Print an html file to stdout, encoding image files in base64.
# If an error occurs while opening a file then it invokes abort.

sub print_html_file {

  my $path = shift;
  my $file = shift;

  ($path) and ($path = "$path/");

  open(my $HTML,'<',"$path$file") or abort("print_html_file open $path$file $!");

  while (<$HTML>) {
    /<img / && / src=\"([^\"]*)\"/ && do {
   
      my $fig = $1;
      my $type = (split(/\./,$fig))[-1];

      ($fig !~ /^\//) and ($fig = "$path$fig");

      open(my $FIG,'<',$fig) or abort("print_html_file open $fig $!");
      
      binmode($FIG);
      my $image = do { local $/; <$FIG> };
      close($FIG);
      
      my $enc = encode_base64($image);

      s{ src=\"([^\"]*)\"}{ src=\"data:image/${type};base64,${enc}\"};
    };

    print $_;
  }

  close($HTML);
}



################################################################################
# logger($message)
#
# Add an entry to typic.log.

sub logger {

  my $mess = shift;

  my $LOG;
  if (!open($LOG,'>>','typic.log')) {
    print "<p>Open typic.log: $! <hr><a href=\"typic.cgi\">typic</a></div></body></html>";
    exit(1);
  }
  if (!flock($LOG,LOCK_EX)) {
    print "<p>Lock typic.log: $! <hr><a href=\"typic.cgi\">typic</a></div></body></html>";
    exit(1);
  }
  seek($LOG,0,2);

  printf $LOG "%s cgi %s port %s %s\n",
              format_epoch(time),$ENV{REMOTE_ADDR},$ENV{REMOTE_PORT},encode("ASCII",$mess);

  flock($LOG,LOCK_UN);
  close($LOG);
}



################################################################################
# string load_file($file)
#
# Load a file into a string.
#
# If an error occurs while opening the file then it invokes abort().

sub load_file {

  my $file = shift;

  open(my $FILE,'<',$file) or abort("load_file: open $file: $!");

  my $buf = '';
  while (<$FILE>) {
    $buf .= $_;
  }

  close($FILE);

  return $buf;
}



################################################################################
sub titles {

  my %H = ('ACCs' => 'A text file with Uniprot protein identifiers separated by blanks (spaces, tabs or newlines).',
	   'agnostic' => 'A file with data on samples.',
	   'peptides' => 'A MaxQuant peptides file.\n If provided, an evidence file must also be given.\n You may upload a zip archive with a single file.',
	   'evidence' => 'A MaxQuant evidence file.\n If provided, a peptides file must also be given.\n You may upload a zip archive with a single file.',
	   'groups' => 'A file with the group of each sample.\nIf provided, the file must be in tab-separated values format and must contain two columns: Sample and Group.',
	   'proteome' => 'The reference proteome.',
	   'proteomeu' => 'A fasta file with peptide sequences.\n You may upload a zip archive with a single file.',
	   'srmatlas' => 'An SRM Atlas build.',
	   'digest' => 'Digest each protein (trypsin, no misses) and include each peptide.',
	   'contaminants' => 'Contaminant sequences.',
	   'contaminantsu' => 'A fasta file with peptide sequences.\n You may upload a zip archive with a single file.',
	   'irts' => 'Retention times for iRTs.',
	   'irtsu' => 'A file with the retention times of iRTs.\nIf provided, the file must be in tab-separated values format and have two columns: Peptide sequence and Retention time.',
	   'allpeps' => 'Include all peptides with at least 4 AAs, not only those with length between 7 and 25.',
	   'colors' => 'Use alternative colors instead of green, yellow and red.',
	   'email' => 'A list of email addresses separated by commas.');
  
  return %H;
}
