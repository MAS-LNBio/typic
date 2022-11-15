#!/usr/bin/perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Copyright 2022 Guilherme P. Telles.


use File::Copy;
use File::Touch;
use File::Basename;

use Scalar::Util qw(looks_like_number);
use Time::HiRes qw(usleep);

use LWP::Simple;
use LWP::UserAgent;

use XML::LibXML;
use Chart::Clicker;
use Chart::Clicker::Renderer::Point;
use Excel::Writer::XLSX;

use Statistics::Regression;

use Getopt::Long;
Getopt::Long::Configure('bundling');


$| = 1;
$" = ', ';

$idsf = '';
$ecof = '';

$agnosticf = '';
$peptidesf = '';
$evidencef = '';
$groupsf = '';

$srmf = '';
$digest = 0;
$enzyme = 'trypsin';

$proteomef = '';
$contf = '';
$patlas = '';
$irtf = '';

$outd = '';
$datad = '';

$update = 0;
$nofigures = 0;
$peplen = '7,25';
$colors = '2AAF0F,DED837,DE3737';
$verb = 0;
$help = 0;

if (@ARGV == 0) {
  $help = 1;
}

$st = GetOptions('i=s' => \$idsf,
		 'v=s' => \$ecof,
		 'p=s' => \$peptidesf,
		 'e=s' => \$evidencef,
		 'g=s' => \$groupsf,
		 't=s' => \$agnosticf,
		 's=s' => \$srmf,
		 'd' => \$digest,
		 'z=s' => \$enzyme,
		 'f=s' => \$proteomef,
		 'c=s' => \$contf,		 
		 'r=s' => \$irtf,
		 'a=s' => \$patlas,
		 'o=s' => \$outd,
		 'w=s' => \$datad,
		 'u' => \$update,
		 'n' => \$nofigures,
		 'l=s' => \$peplen,
		 'k=s' => \$colors,
		 'q' => \$verb,
		 'h|help' => \$help);


if (!$st || @ARGV != 0 || $help) {
  $help = 1;
}


if ($help) {
  print<<_END_;
Usage: typic.pl -i file -v file [options] 

 -i   A text file with UniProt protein IDs separated by blanks. 
 -v   An Evidence Ontology file in OBO format. 

options for data on samples in MaxQuant format:
 -p   A MaxQuant peptides file.
 -e   A MaxQuant evidence file. Must be used with -p. 
 -g   A tsv file with experimental groups.

options for data on samples in agnostic format:
 -t   An agnostic input file. 
 -g   A tsv file with experimental groups.

options related to the experiment:
 -z   Select digestion enzyme among: 
      trypsin ((K or R) not P), trypsin_kr (K or R),
      argc (R), chymotrypsin ((F, Y, W, M or L) not (M or P)), lysc (K),
      gluc_de (D or E), gluc_d (D), gluc_e (E).
      The default is: -z trypsin

options for other sources of peptides:
 -s   Include peptides from an SRM Atlas build file. 
 -d   Include peptides from in-silico digestion (no misses).

options for other sources of data:
 -f   A proteome file in fasta format. 
 -c   A contaminants file in fasta format. 
 -r   A tsv file with retention times for iRT peptides.
 -a   Add data from a PeptideAtlas build.

output options:
 -o   The output directory. Defaults to the current working directory.
 -w   A directory where UniProt and PeptideAtlas files will be read from and saved to.
      If not set, data downloaded from UniProt and PeptideAtlas are written to 
      the current working directory and removed.
 -u   Update data previously downloaded from UniProt and PeptideAtlas.
      Local data will be replaced even if the updating download fails.
 -n   Do not generate quantitative nor RT plots.
 -l   The interval of lengths of peptides included in the output.
      The default is [7,25]: -l 7,25
 -k   A triplet of RGB hexadecimal values for ranking colors.  
      The default is green, yellow, red: -k 2AAF0F,DED837,DE3737 
 -q   Refrain from printing progress messages.

 -h   This usage reminder.
_END_

  exit(2);
}
elsif ($help) {
  exit(2);
}


(!$idsf) and abend('You must provide an IDs file.');

(!$ecof || !-e $ecof) and abend('You must provide an Evidence Ontology file in OBO format.');

@colors = split(/,/,$colors);
(@colors != 3) and abend('Invalid colors.');
for $c (@colors) {
  (hex($c) > 16777215) and abend('Invalid colors.'); 
}

($minlen,$maxlen) = split(/,/,$peplen);
($minlen && !$maxlen) and ($maxlen = 2147483647);
(!$minlen || $minlen <= 0 || $minlen > $maxlen) and
  abend('The length interval is invalid');

($peptidesf && $agnosticf) and abend('Maxquant and agnostic input are exclusive.');

(!$peptidesf && $evidencef) and
  abend('Maxquant evidence file must be given with a peptides file.');

($groupsf && !$peptidesf && !$agnosticf) and
  abend('Groups file must be given with MaxQuant or agnostic input.');

if ($outd) {
  (!-d $outd) and abend("The output directory $outd doesn't exist.");
}
else {
  $outd = '.';
}

(!$agnosticf && !$peptidesf && !$srmf) and ($digest = 1);

@del = ();
if (!$datad) {
  $datad = '.';
  $clean = 1;
}
else {
  (!-d $datad) and abend("The data directory $datad doesn't exist.");
  $clean = 0;
}
  
$outd =~ s/\/$//;
$datad =~ s/\/$//;

%enzyme =  ('argc' => ['R',''], 'chymotrypsin' => ['FYWML','MP'],
	    'gluc_de' => ['DE',''], 'gluc_d' => ['D',''], 'gluc_e' => ['E',''],
	    'lysc' => ['K',''], 'trypsin' => ['KR','P'], 'trypsin_kr' => ['KR','']);

(!exists($enzyme{$enzyme})) and abend("Invalid digestion enzyme.");

$verb = !$verb;

### Load protein ids:
@prots = read_words($idsf);
(@prots == 0) and abend("There are no IDs in $idsf.");

$verb and print 'Will process ', scalar @prots, " protein accession numbers in $idsf.\n"; 


### Load experimental condition ontology to parse features in uniprot xml:
($ecoref,$econamesref) = obo_load_forest($ecof);


### Load proteome:
if ($proteomef) {
  @pome = ff_load($proteomef,0,0,\&genbank_tag);
  $verb and print 'Proteome file has ', scalar @pome, " sequences.\n"; 

  $nogn = 0;
  for ($i=0; $i<@pome; $i++) {
    if ($pome[$i]{header} !~ / GN=([^ ]*) /) {
      $nogn++;
    }
  }
}


### Load quantitative data in %sample, a hash protein-id => array.
# The array has data items on the peptides of the protein, sequentially.
# The number of data items for each peptide will differ among
# agnostic, agnostic with samples and MaxQuant.
# For instance, for data in the agnostic format the array will have
# three data items for each peptide:
# Q9UBG3 => CVTEGQGDR,633550,1484.75,EFLVLVFK,2183060,6111.48,TEGNCTALTR,889058,2010.51
# The number of data items of each peptide will be $samplew.
%sample = (); 
$samplew = 0;

# The name and number of samples:
@smpids = ();
$nsmps = 0;

# A hash peptide => array with RT and MS count, for MQ with evidence only:
%rts = ();

# The regression coeficients:
@smp_theta = ();


### Load data from a file in agnostic format without quantitativa data per sample:
#
# Protein accession | Peptide sequence | Retention time | Quantitative Information 
# id,id,...,id | string | number | number
#
# or in agnostic format with quantitativa data per sample, that has one or more
# columns after "Quantitative Information" whose headers are the sample names.

if ($agnosticf) {
  @smpids = csv_read_row($agnosticf,"\t",'"',0);

  if (@smpids == 4) {
    %in = csv_read_columns($agnosticf,'\t','"',
			   'Protein accession',
			   'Peptide sequence','Retention time','Quantitative information');
    $samplew = 3;

    # Add every id in 'Protein accession' as a key in %sample:
    foreach $accs (keys(%in)) {
      foreach $acc (split(/\s*,\s*/,$accs)) {
	$acc = uc($acc);
	push(@{$sample{$acc}}, @{$in{$accs}});
      }
    }

    # Evaluate regression on sample RTs:
    $r = Statistics::Regression->new("sample",["intercept","slope"]);
  
    foreach $acc (keys(%sample)) {
      @dat = @{$sample{$acc}};
      for ($j=0; $j<@dat; $j+=3) {
	$rt = $dat[$j+1];
	$hi = hydrophobicity_index($dat[$j]);
	$r->include($rt,[1.0,$hi]);
      }
    }
    
    if ($r->n() > 5) {
      #$r->print();
      @smp_theta = $r->theta();
    }
  }
  else {
    for ($i=0; $i<4; $i++) {
      shift(@smpids);
    }
    
    $nsmps = @smpids;
    $samplew = 3+$nsmps;

    %in = csv_read_columns($agnosticf,"\t",'"',
			   'Protein accession',
			   'Peptide sequence','Retention time','Quantitative information',@smpids);

    # Add every id in 'Protein accession' as a key in %sample:
    foreach $accs (keys(%in)) {
      foreach $acc (split(/\s*,\s*/,$accs)) {
	$acc = uc($acc);
	push(@{$sample{$acc}}, @{$in{$accs}});
      }
    }

    # Evaluate regression on sample RTs:
    $r = Statistics::Regression->new("sample",["intercept","slope"]);
  
    foreach $acc (keys(%sample)) {
      @dat = @{$sample{$acc}};
      for ($j=0; $j<@dat; $j+=3+@smpids) {
	$rt = $dat[$j+1];
	$hi = hydrophobicity_index($dat[$j]);
	$r->include($rt,[1.0,$hi]);
      }
    }

    if ($r->n() > 5) {
      #$r->print();
      @smp_theta = $r->theta();
    }
  }

  $verb and print 'Agnostic file refers to ', scalar keys %sample, " proteins.\n"; 
}


### Load data from MaxQuant files:
elsif ($peptidesf) {

  # Get the headers of columns having sample intensities, those
  # between Intensity and Reverse:
  @cols = csv_read_row($peptidesf,"\t",'"',0);
  @smpids = ();
  @icols = ();

  for ($i=0; $cols[$i] ne 'Intensity'; $i++) {
    ;
  }
  for ($i++; $cols[$i] ne 'Reverse'; $i++) { 
    push(@smpids,(split(/ /,$cols[$i],2))[1]);
    push(@icols,$cols[$i]);
  }
  
  $nsmps = @smpids;

  %sample = csv_read_columns($peptidesf,"\t",'"',
			     'Leading razor protein',
			     'Sequence','Unique (Groups)','Unique (Proteins)','Intensity',@icols);
  $samplew = 4+$nsmps;

  # From evidence file, for each peptide get retention time and MS/MS count:
  if ($evidencef) {
    %rts = csv_read_columns($evidencef,"\t",'"',
			    'Sequence',
			    'Retention time','MS/MS count');
    
    # Evaluate regression on sample RTs:
    $r = Statistics::Regression->new("sample", ["intercept", "slope"]);
    
    foreach $pep (keys(%rts)) {
      $rt = 0;
      for ($j=0; $j<@{$rts{$pep}}; $j+=2) {
	$rt += $rts{$pep}[$j];
      }
      if ($rt > 0) {
	$rt /= (@{$rts{$pep}} / 2);
	$hi = hydrophobicity_index($pep);
	$r->include($rt, [1.0, $hi]);
      }
    }
    if ($r->n() > 5) {
      #$r->print();
      @smp_theta = $r->theta();
    }
  }

  $verb and print 'MaxQuant files refers to ', scalar keys %sample, " proteins.\n"; 
}



### Load groups file:
if ($groupsf) {
  %aux = read_keys_values($groupsf,'\t',1);

  # If there are excess sample ids in %aux, drop them.  If there are missing ones, abort.
  %groups = ();
  @abend = ();
    
  for $id (@smpids) {
    if (exists($aux{$id})) {
      $groups{$id} = $aux{$id};
    }
    else {
      push(@abend,$id);
    }
  }
  if (@abend) {
    abend("Group" . (@abend>1?'s':'') . " @abend " . (@abend>1?'are':'is') . " not in $groupsf.");
  }
}


### Load data from SRM-Atlas file into a hash ACC => array-of-peptide-sequences:
%srm = ();

if ($srmf) {
  %srm = csv_read_columns($srmf,"\t",'"','Prot_acc','sequence');
  
  # In SRM Atlas non-unique peptides have multiple accs separated by a period.
  # Split such multiple accessions and add peptides to each accession
  # entry %srm, and add them to a hash of non-uniqueness:
  @srmk = keys(%srm);
  %nonuniqsrm = ();
  
  for ($i=0; $i<@srmk; $i++) {
    if ($srmk[$i] =~ /\./) {
      @aux = split(/\./,$srmk[$i]);
      
      for ($j=0; $j<@aux; $j++) {
	if (!exists($srm{$aux[$j]})) {
	  $srm{$aux[$j]} = [ () ];
	}
	
	push(@{$srm{$aux[$j]}} , @{$srm{$srmk[$i]}});
      }
      
      %aux = map { $_ , 1 } @{$srm{$srmk[$i]}};
      
      foreach (keys(%aux)) {
	$nonuniqsrm{$_} = $aux{$_};
      }
      
      delete($srm{$srmk[$i]});
    }
  }
  
  $verb and print 'SRM Atlas file has ', scalar keys %srm, " proteins.\n"; 
}


### Load a fasta file with contaminants into an AoH:
@cont = ();

if ($contf) {
  @cont = ff_load($contf,0,0,\&genbank_tag);
  $verb and print 'Contaminants file has ', scalar @cont, " sequences.\n"; 
}


### Load a file with iRT experimental retention times and evaluate
### regression coefficients:
@irt_theta = ();

if ($irtf) {
  %irts = read_keys_values($irtf,'\t',1);

  $r = Statistics::Regression->new("irt",["intercept","slope"]);

  foreach $k (keys(%irts)) {
    $hi = hydrophobicity_index($k);
    $r->include($irts{$k},[1.0,$hi]);
  }

  @irt_theta = $r->theta();
}

### For each protein, download UniProt entry, add peptides from
### quantitative data, from SRM Atlas and from digestion
### and load uniprot features.  For each of its peptides, determine
### location in gene, uniqueness, its uniprot features, and hydro
### index etc.  Then write data to an xlsx.

$iplotsh = 0;

$id = 0;
foreach $prot (@prots) {
  $id++;
  $verb and print "$id: $prot\n";

  $protaka = '';
  $unif = "$datad/$prot.xml";
  $unifaka = "$datad/$prot-aka.xml";
  $failf = "$datad/$prot-fail.xml";
  $uprot = 1;
  
  ### Download UniProt xml or use local files:
  if ((!-f $unif && !-f $unifaka) || $update) {

    (-f $unif) && unlink($unif);
    (-f $unifaka) && unlink($unifaka);
    (-f $failf) && unlink($failf);

    $down = uprot_download_xml($prot,$datad);

    if ($down eq 'fail') {
      $verb and print " unable to download from UniProt\n";
      $clean && push(@del,$failf);
      $uprot = 0;
    }
    elsif ($down ne $prot) {
      $unif = $unifaka;
      $protaka = $prot;
      $prot = $down;
      $clean && push(@del,($unif,$unifaka));
      $verb and print " downloaded from UniProt as $down\n";
    }
    else {
      $clean && push(@del,$unif);
      $verb and print " downloaded from UniProt\n";
    }
  }
  else {
    if (-f $failf) {
      $verb and print " previous download attempt from UniProt failed\n";
      $uprot = 0;
    }
    elsif (-f $unifaka) {
      $unif = $unifaka;
      %aux = uprot_get_basic($unif);
      $protaka = $prot;
      $prot = $aux{synonyms}[0];
      $verb and print " UniProt data already stored locally\n";
    }
    else {
      $verb and print " UniProt data already stored locally\n";
    }      
  }      

  
  ### Data on the protein will be gathered in a HoH that maps each
  ### peptide sequence to its attributes in an inner hash:
  %H = ();

  # The number of peps in the protein that came from a sample:
  $npepsmp = 0; 

  # The peptides that have intensity and their intensities, for quartile evaluation:
  @P = ();
  @I = ();

  ### Add peptides from samples given in agnostic format:
  if ($agnosticf && %sample && exists($sample{$prot})) {

    # An empty HoHoL for intensity values of each peptide x sample:
    %intseries = ();
    
    %peps = ();
    for ($i=0; $i<@{$sample{$prot}}; $i+=$samplew) {
      $pep = uc($sample{$prot}[$i]);
      (length($pep) < $minlen || length($pep) > $maxlen) and next;
      $peps{$pep} = 1;
    }
    @peps = keys(%peps);

    if (!$nofigures && $samplew > 3) {
      foreach $pep (@peps) {
	$intseries{$pep} = { () };
	for ($j=0; $j<@smpids; $j++) {
	  $intseries{$pep}{$smpids[$j]} = [ () ];
	}
      }
    }

    # Collect intensities and RT in %sample.
    # If a peptide occurs more than once for a protein, the peptide
    # intensity will be the average and the retention time will be the median.  
    # Out-of-range intensities will be set to 0. Out-of-range RTs will be discarded.
    for ($i=0; $i<@{$sample{$prot}}; $i+=$samplew) {
      $pep = uc(@{$sample{$prot}}[$i]);

      (length($pep) < $minlen || length($pep) > $maxlen) and next;

      $rt = @{$sample{$prot}}[$i+1];
      $int = @{$sample{$prot}}[$i+2];

      if (!$nofigures && $samplew > 3) {
	for ($j=3; $j<$samplew; $j++) {
	  push(@{$intseries{$pep}{$smpids[$j-3]}},$sample{$prot}[$i+$j]);
	}
      }

      if (exists($H{$pep})) {
	($int < 0) and ($int = 0);
	push(@{$H{$pep}{int}},$int);
	push(@{$H{$pep}{rt}},$rt);
      }
      else {
	%h = ();
	$npepsmp++;
	$h{src} = 'sample';
	$h{sco} = 0;
	$h{nzi} = '-';
	$h{int} = [ ($int) ];
	$h{rt} = [ ($rt) ];
	$H{$pep} = { %h };
      }
    }

    foreach $pep (@peps) {
      if (@{$H{$pep}{rt}}) {
	$med = median(\@{$H{$pep}{rt}});
	$H{$pep}{rt} = $med;
      }
      else {
	$H{$pep}{rt} = '-';
      }
      
      ($int,$_) = avg_var(\@{$H{$pep}{int}});
      $H{$pep}{int} = $int;
      push(@P,$pep);
      push(@I,$int);
    }

    if (!$nofigures && $samplew > 3) {
      foreach $pep (@peps) {
	for ($j=0; $j<@smpids; $j++) {
	  ($int,$_) = avg_var(\@{$intseries{$pep}{$smpids[$j]}});
	  $intseries{$pep}{$smpids[$j]} = $int;
	}
      }

      if ($groupsf) {
	$iplotsh = intensity_plots('AGNOSTIC',$protaka?$protaka:$prot,\%intseries,\%groups,$outd);
      }
      else {
	$iplotsh = intensity_plots('AGNOSTIC',$protaka?$protaka:$prot,\%intseries,undef,$outd);
      }
    }
  }
  
  ### Add peptides from samples given in MaxQuant format:
  elsif ($peptidesf && %sample && exists($sample{$prot})) {
   
    @peps = ();
    for ($i=0; $i<@{$sample{$prot}}; $i+=$samplew) {
      $pep = uc($sample{$prot}[$i]);
      (length($pep) < $minlen || length($pep) > $maxlen) and next;
      push(@peps,$pep);
    }

    # The intensity of each peptide across samples will be recorded
    # into a HoH that will be used to plot them:
    %intseries = ();

    if (!$nofigures) {
      foreach $pep (@peps) {
	$intseries{$pep} = { () };
	for ($j=0; $j<@smpids; $j++) {
	  $intseries{$pep}{$smpids[$j]} = 0;
	}
      }
    }
    
    for ($i=0; $i<@{$sample{$prot}}; $i+=$samplew) {
      %h = ();

      $pep = uc(@{$sample{$prot}}[$i]);
      (length($pep) < $minlen || length($pep) > $maxlen) and next;
      $h{mqunqgrp} = @{$sample{$prot}}[$i+1];
      $h{mqunqpro} = @{$sample{$prot}}[$i+2];
      $h{int} = @{$sample{$prot}}[$i+3];
      ($h{int} < 0) and ($h{int} = 0);
      push(@P,$pep);
      push(@I,$h{int});

      if (!$nofigures) {
	$h{nzi} = 0;
	for ($j=4; $j<$samplew; $j++) {
	  if ($sample{$prot}[$i+$j] != 0) {
	    $h{nzi}++;
	    $intseries{$pep}{$smpids[$j-4]} = $sample{$prot}[$i+$j];
	  }
	}

	if ($groupsf) {
	  $iplotsh = intensity_plots('MQ',$protaka?$protaka:$prot,\%intseries,\%groups,$outd);
	}
	else {
	  $iplotsh = intensity_plots('MQ',$protaka?$protaka:$prot,\%intseries,undef,$outd);
	}
      }
      else {
	$h{nzi} = 0;
	for ($j=4; $j<$samplew; $j++) {
	  if ($sample{$prot}[$i+$j] != 0) {
	    $h{nzi}++;
	  }
	}
      }
	
      # RT and MS-count:
      if (exists($rts{$pep})) {
	@aux = ();
	$maxmsc = 0;
	  
	for ($j=0; $j<@{$rts{$pep}}; $j+=2) {
	  push(@aux,$rts{$pep}[$j]);
	  if ($maxmsc < $rts{$pep}[$j+1]) {
	    $maxmsc = $rts{$pep}[$j+1];
	  }
	}
	
	$h{rt} = median(\@aux);
	$h{mscount} = $maxmsc;
      }
      else {
	$h{rt} = '-';
	$h{mscount} = '-';
      }
            
      $h{src} = 'sample';
      $npepsmp++;
      $H{$pep} = { %h };
    }
  }

  if (@I) {
    @index = sort { $I[$a] <=> $I[$b] } 0..@I-1;
    @I = @I[@index];
    @P = @P[@index];
  }

  ### Add peptides from SRM Atlas:
  $nsrm = 0;
  if (exists($srm{$prot})) { 
    for ($i=0; $i<@{$srm{$prot}}; $i+=1) {
      $pep = uc(@{$srm{$prot}}[$i]);
      (length($pep) < $minlen || length($pep) > $maxlen) and next;
      if (!exists($H{$pep})) {
	%h = ();
	$h{src} = 'SRM Atlas';
	$h{int} = '-';
	$h{nzi} = '-';
	$h{rt} = '-';

	$H{$pep} = { %h };
      }
      else {
	$H{$pep}{src} = 'sample, SRM Atlas';
      }
      $nsrm++;
    }
  }

  # If protein is an isoform, also add peptides from SRM basic form:
  if ($prot =~ /-/) {
    @aux = split(/-/,$prot);
    $aka = $aux[0];

    if (exists($srm{$aka})) { 
      for ($i=0; $i<@{$srm{$aka}}; $i+=1) {
	$pep = uc(@{$srm{$aka}}[$i]);
	(length($pep) < $minlen || length($pep) > $maxlen) and next;
	if (!exists($H{$pep})) {
	  %h = ();
	  $h{src} = "SRM Atlas ($aka)";
	  $h{int} = '-';
	  $h{nzi} = '-';
	  $h{rt} = '-';
	  
	  $H{$pep} = { %h };
	}
	else {
	  $H{$pep}{src} = "sample,SRM Atlas ($aka)";
	}
	$nsrm++;
      }
    }
  }

  if ($srmf && $nsrm == 0) {
    $verb and print " no SRM Atlas entry for $prot\n";
  }
  
  
  ### Load protein fasta:
  $fasta = uc(uprot_get_fasta($unif));
  
  
  ### Add peptides from digestion, if not incuded already.
  ### For such peps, also add coordinates:
  if ($digest && $fasta) {

    ($f,$p) = digest($fasta,@{$enzyme{$enzyme}});
    @frag = @{$f};
    @pos = @{$p};
    
    for ($i=0; $i<@frag; $i+=1) {
      $pep = uc($frag[$i]);
      (length($pep) < $minlen || length($pep) > $maxlen) and next;

      if (!exists($H{$pep})) {
	%h = ();
	$h{src} = "in-silico $enzyme digestion";
	$h{int} = '-';
	$h{nzi} = '-';
	$h{rt} = '-';
	$h{beg} = $pos[$i] + 1;
	$h{end} = $pos[$i] + length($pep);
	$h{mat} = 'exact';
	
	$H{$pep} = { %h };
      }
      else {
	if ($H{$pep}{src} eq "in-silico $enzyme digestion") {
	  $H{$pep}{mat} = 'exact, multiple times';
	}
      }
    }
  }


  ### Load UniProt features:
  @feat = uprot_get_features($unif,$ecoref,$econamesref);

  
  ### Summon data on each peptide:
  @peptides = sort(keys(%H));

  foreach $pep (@peptides) {

    # Get coordinates via string matching (for sample and SRM peptides):
    if (!exists($H{$pep}{beg})) {
      $_ = $fasta;
      m/$pep/g;
      $p = pos();
      
      if (defined($p)) {
	$H{$pep}{beg} = $p - length($pep) + 1;
	$H{$pep}{end} = $p;
	$H{$pep}{mat} = 'exact';
      }
      else {
	%A = sgma_alignment($fasta,$pep,\%aa2index,\@blosum62,-10,-1);
	$H{$pep}{beg} = $A{sfirst}+1;
	$H{$pep}{end} = $A{slast}+1;
	$H{$pep}{mat} = "inexact, spaces: $A{tspaces} mismatches: $A{mismatches}";
      }
    }

    # Get flanking AAs, namely, first, last, previous and next amino acids:
    $H{$pep}{faa} = substr($pep,0,1);
    $H{$pep}{laa} = substr($pep,-1);
    $H{$pep}{paa} = $H{$pep}{beg} > 1 ? substr($fasta,$H{$pep}{beg}-2,1) : '-';
    $H{$pep}{naa} = $H{$pep}{end} < length($fasta) ? substr($fasta,$H{$pep}{end},1) : '-';

    # Intensity quartile:
    if ($H{$pep}{int} ne '-' && @P) {
      $i = 0;
      while ($P[$i] ne $pep) {
	$i++;
      }
      
      $H{$pep}{q} = int(4*$i/@I) + 1;
      ($H{$pep}{q} > 4) and ($H{$pep}{q} = 4);
    }
    
    # UniProt features:
    foreach (@feat) {
      %f = %{$_};
      $type = lc($f{type});
      $descr = lc($f{description});

      if ($type eq 'disulfide bond' ||
	  $type eq 'modified residue' || 
	  $type eq 'signal peptide' || 
	  $type eq 'glycosylation site' ||
	  ($type eq 'chain' && $descr eq 'ubiquitin') || 
	  ($type eq 'domain' && $descr =~ /^ubiquitin-like/)) {

	@cfeat = split(/-/,$f{at});
	$cfeat[1] = defined($cfeat[1]) ? $cfeat[1] : $cfeat[0];

	if (($H{$pep}{beg} <= $cfeat[0] && $cfeat[1] <= $H{$pep}{end}) ||
	    ($cfeat[0] <= $H{$pep}{end} && $H{$pep}{end} <= $cfeat[1]) ||
	    ($cfeat[0] <= $H{$pep}{beg} && $H{$pep}{beg} <= $cfeat[1])) {

	  $type =~ s/ $//g;
	  $type =~ s/,/;/g;
	  $descr =~ s/ $//g;
	  $descr =~ s/,/;/g;
	  
	  if (!exists($H{$pep}{fea})) {
	    $H{$pep}{fea} = "$f{at} $type $descr";
	    $H{$pep}{exp} = ($f{experimental} ? '' : 'non-') . 'experimental evidence';
	  }
	  else {
	    $H{$pep}{fea} .= ", $f{at} $type $descr";
	    $H{$pep}{exp} .= ($f{experimental} ? ', ' : ', non-') . 'experimental evidence';
	  }
	}
      }
    }

    # Number of sequences of the proteome where the peptide occurs and the first 5 tags.
    # Genes of the proteome where the peptide occurs and the first 5 tags.
    @tags = ();
    %genes = ();
    
    for ($i=0; $i<@pome; $i++) {
      if ($pome[$i]{seq} =~ /$pep/) {
	push(@tags,$pome[$i]{tag});
	
	if ($pome[$i]{header} =~ / GN=([^ ]*) /) {
	  $gene = uc($1);
	}
	else {
	  $gene = 'missing';
	}
	if (!exists($genes{$gene})) {
	  $genes{$gene} = 1;
	}
	else {
	  $genes{$gene} += 1;
	}
      }
    }

    $H{$pep}{pomeocc} = scalar @tags;

    if (@tags > 5) {
      $H{$pep}{pometags} = "@tags[0..4], ...";
    }
    elsif (@tags > 0) {
      $H{$pep}{pometags} = "@tags";
    }
    else {
      $H{$pep}{pometags} = '-';
    }

    @aux = sort(keys(%genes));
    $H{$pep}{geneocc} = scalar @aux;

    if (@aux > 5) {
      $H{$pep}{genetags} = "@aux[0..4], ...";
    }
    elsif (@aux > 0) {
      $H{$pep}{genetags} = "@aux";
    }
    else {
      $H{$pep}{genetags} = '-';
    }

    # Number of contaminants where the peptide occurs:
    $occ = 0;
    for ($i=0; $i<@cont; $i++) {
      if ($cont[$i]{seq} =~ /$pep/) {
	$occ++;
      }
    }
    $H{$pep}{contocc} = $occ;

    # Methionines:
    $occ = 0;
    $pos = '';
    $_ = $pep;
    while (m/M/g) {
      $pos .= pos() . ', ';
      $occ++;
    }

    $H{$pep}{metocc} = $occ;
    $pos =~ s/, $//;
    $H{$pep}{metpos} = $pos;

    # Missing cleavages:
    $at = $enzyme{$enzyme}[0];
    $at =~ s/(?=.)(?<=.)/\|/g;
    $after = $enzyme{$enzyme}[1];

    $occ = 0;
    $pos = '';
    $_= $pep;
    while (m/($at)/g) {
      $p = pos();
      if (index($after,substr($_,$p,1)) == -1) {
	$pos .= "$1 at $p, ";
	$occ++;
      }
    }

    $H{$pep}{missocc} = $occ;
    $pos =~ s/, $//;
    $H{$pep}{misspos} = $pos;

    # Hydrophobicity index:
    $H{$pep}{hyd} = hydrophobicity_index($pep);

    # Data from Peptide Atlas:
    if ($patlas && ($H{$pep}{src} =~ /sample/ || $H{$pep}{src} =~ /SRM/)) {
      $patlasf = "$datad/" . substr($pep,0,240) . '.html';
      $clean && push(@del,$patlasf);
      $new = 0;
      $status = '';
      
      $verb and print " $pep";
      
      if (!-e $patlasf || $update) {
        $new = 1;
        sleep(1);
        $url = 'https://db.systemsbiology.net/sbeams/cgi/PeptideAtlas/GetPeptide?' .
	  'atlas_build_id=' . $patlas .
	  '&searchWithinThis=Peptide+Sequence' .
	  '&searchForThis=' . $pep . '&action=QUERY';
	
	$ct = get $url;
	if (defined $ct) {
	  open(PEP,">",$patlasf);
	  print PEP $ct;
	  close(PEP);
	  
	  if ($ct =~ m/Peptide\s+not\s+found.\s+Please\s+check\s+selections\s+and\s+try\s+again./) {
	    ($verb) and print ", not found in PepetideAtlas\n";
	    $status = 'peptide not found in PepetideAtlas';
	  }
	  else {
	    ($verb) and print ", downloaded from PepetideAtlas\n";
	    $status = 'downloaded';
	  }
	}
	else {
	  ($verb) and print ", unable to download from PepetideAtlas\n";
	  $status = 'failed';
	}
      }

      
      $instruments = '';
      %instr = ();
      
      if (-e $patlasf) {
	open(PEP,'<',$patlasf);
	$nopep = 0;
	$hasexp = 0;
	$intab = 0;
	while (<PEP>) {
	  /Peptide\s+not\s+found.\s+Please\s+check\s+selections\s+and\s+try\s+again./ && do {
	  $nopep = 1;
	  if (!$new) {
	    ($verb) and print ", previously not found in PeptideAtlas\n";
	    $status = 'peptide not found in PepetideAtlas';
	  }
	  last;
	  };
	  
	  /\>\s*Observed\s+in\s+Experiments\s*\</ && do {
	    $hasexp = 1;
	  };
	  
	  $hasexp && /\<TBODY\>/ && do {
	    $intab = 1;
	  };
	  
	  $intab && /\<TR / && do {
	    for ($i=0; $i<3; $i++) {
	      <PEP>;
	    }
	    $_ = <PEP>;
	    />([^<]*)</;
	    $r = $1;

	    if (looks_like_number($r)) {
	      $_ = <PEP>;
	      />([^<]*)</;
	      $r = $1;
	    }
	    if ($r) {
	      $instruments .= $r;
	      $instr{$r}++;
	    }
	  };
	}
	
	if (!$nopep && !$new) {
	  ($verb) and print ", already stored locally\n";
	  $status = 'downloaded';
	}
	close(PEP);
      }
      else {
	($verb) and print ", unable to download from Pepetide Atlas\n";
	$status = 'failed';
      }
      
      if ($instruments) {
	delete($instr{''});
	@aux = sort(keys(%instr));
	$H{$pep}{instruments} = "@aux";
      }
      else {
	$H{$pep}{instruments} = $status;
      }
    }
    else {
      $H{$pep}{instruments} = '-';
    }
  }

  
  ### Write output:
  $outf = $protaka ? "$outd/$protaka" : "$outd/$prot";

  $greenrgb = '#' . $colors[0];
  $grayrgb = '#' . $colors[1];
  $redrgb = '#' . $colors[2];
  
  $xx = Excel::Writer::XLSX->new("$outf.xlsx");
  $xx->set_optimization();
  
  $rightf = $xx->add_format();
  $rightf->set_align('right');

  $plainf = $xx->add_format();
  $plainf->set_align('vcenter');
  $plainf->set_align('left');

  $boldf = $xx->add_format();
  $boldf->set_bold();

  $greenlf = $xx->add_format();
  $greenlf->set_bg_color($greenrgb);
  $greenlf->set_align('left');

  $greenrf = $xx->add_format();
  $greenrf->set_bg_color($greenrgb);
  $greenrf->set_align('right');

  $redrf = $xx->add_format();
  $redrf->set_bg_color($redrgb);
  $redrf->set_align('right');

  $redlf = $xx->add_format();
  $redlf->set_bg_color($redrgb);
  $redlf->set_align('left');

  $grayrf = $xx->add_format();
  $grayrf->set_bg_color($grayrgb);
  $grayrf->set_align('right');

  $graylf = $xx->add_format();
  $graylf->set_bg_color($grayrgb);
  $graylf->set_align('left');

  $floatf = $xx->add_format();
  $floatf->set_num_format('0.000');
  

  ### Write sht1 (peptides) and evaluate peptides rank:
  $sht1 = $xx->add_worksheet('peptides');

  @W = ();
  push(@W,('Protein','Peptide','Length','Position','Source of peptide identification'));
  ($peptidesf) and push(@W,('Intensity','Intensity quartile'));
  ($agnosticf) and push(@W,('Quantitative information','Q.i. quartile'));
  
  ($peptidesf) and push(@W,'Samples with valid intensity value');
  ($evidencef) and push(@W,'MQ MS/MS count');
  ($peptidesf) and push(@W,('MQ Unique (Groups)','MQ Unique (Proteins)'));
  ($proteomef) and push(@W,('Occurrences in proteome sequences','IDs of proteome sequences',
			    'Occurrences in gene sequences','IDs of gene sequences'));
  ($uprot) and push(@W,('PTMs','PTM evidences'));
  ($contf) and push(@W,('Occurrences in contaminant sequences'));
  push(@W,('Methionines','Methionine positions','Missing cleavages','Missing cleavage positions'));
  ($agnosticf || $evidencef) and push(@W,'Retention time');
  push(@W,'Hydrophobicity index');
  (@smp_theta) and push(@W,('Theoretical retention time (wrt samples)'));
  (@irt_theta) and push(@W,('Theoretical retention time (wrt iRT)'));

  ($uprot) and push(@W,('Previous aa'));
  push(@W,('First aa','Last aa'));
  ($uprot) and push(@W,('Next aa'));

  ($patlas && ($peptidesf || $agnosticf || $srmf)) and
    push(@W,'Instruments reported in PeptideAtlas experiments (from sample or SRM Atlas)');
  
  %figpos = ();

  $sht1->write_row(0,0,\@W,$boldf);

  for ($j=0; $j<@W; $j++) {
    $sht1->set_column($j,$j,length($W[$j]));
  }
  
  $r = 1;
  $c = 0;
  $p = 1;

  %rt_exp = ();  # Peptides and their experimental RTs.
  %rt_irt = ();  # Peptides and their IRT theoretical RTs.
  %rt_smp = ();  # peptides and their sample theoretical RTs.
  
  @ranks = ();
  
  foreach $pep (@peptides) {

    %h = %{$H{$pep}};

    $rank = '';

    $sht1->write($r,$c++,$protaka ? $protaka : $prot);
   
    if (!$nofigures && $samplew > 3 &&
	((!$protaka && -f "$outd/$prot-$pep.png") || ($protaka && -f "$outd/$protaka-$pep.png"))) {      
      $figpos{$pep} = $p;
      $sht1->write_url($r,$c++,'internal:plots!A'.$p,undef,$pep);
      $p += int($iplotsh / 20) + 2;
    }
    else {
      $sht1->write($r,$c++,$pep);
    }
    
    $l = length($pep);
    $sht1->write($r,$c++,$l);
    $sht1->write($r,$c++,"$h{beg}-$h{end} $h{mat}");
    $sht1->write($r,$c++,$h{src});

    $fromsmp = ($h{src} =~ /sample/ ? 1 : 0);
    if ($fromsmp) {
      $rank .= '0';
    }
    elsif ($h{src} eq 'SRM Atlas') {
      $rank .= '1';
    }
    else {
      $rank .= '2';
    }
	 
    if ($agnosticf || $peptidesf) {
      if ($fromsmp) {
	$sht1->write($r,$c++,$h{int},$rightf);      

	if ($h{int} ne '-') {
	  $sht1->write($r,$c++,$h{q},$rightf);
	  $rank .= $h{q}>=3 ? 0 : 1;
	}
	else {
	  $sht1->write($r,$c++,'-',$rightf);      
	  $rank .= '2';
	}
      }
      else {
	$sht1->write($r,$c++,'-',$rightf);
	$sht1->write($r,$c++,'-',$rightf);
	$rank .= '2';
      }
    }
	
    if ($peptidesf) {
      if ($fromsmp) {
	$sht1->write($r,$c++,$h{nzi});
	$rank .= ($h{nzi} eq '-' || $h{nzi} == 0 ? '2' : '0');
	
	($evidencef) and ($sht1->write($r,$c++,$h{mscount}));
	
	$sht1->write($r,$c++,$h{mqunqgrp},$rightf);
	$rank .= ($h{mqunqgrp} eq 'yes' ? '0' : '2');
	
	$sht1->write($r,$c++,$h{mqunqpro},$rightf);
	$rank .= ($h{mqunqpro} eq 'yes' ? '0' : '2');
      }
      else {
	$sht1->write($r,$c++,'-',$rightf);
	($evidencef) and (	$sht1->write($r,$c++,'-',$rightf));
	$sht1->write($r,$c++,'-',$rightf);
	$sht1->write($r,$c++,'-',$rightf);
	$rank .= '111';
      }
    }
    
    if ($proteomef) { 
      $rank .= $h{pomeocc} > 1 ? '2' : '1';

      # Occurrences in proteome sequences:
      $sht1->write($r,$c++,$h{pomeocc});
      $sht1->write($r,$c++,$h{pometags});

      # Occurrences in proteome genes:
      $sht1->write($r,$c++,$h{geneocc});
      $sht1->write($r,$c++,$h{genetags});
    }
    
    # UniProt features:
    if ($uprot) {
      if (exists($h{fea})) {
	$sht1->write($r,$c++,$h{fea});
	$sht1->write($r,$c++,$h{exp});
	$rank .= '2';
      }
      else {
	$sht1->write($r,$c++,'-');      
	$sht1->write($r,$c++,'-');
	$rank .= '0';
      }
    }
    
    # Occurrence in contaminants:
    ($contf) and $sht1->write($r,$c++,$h{contocc});
    
    # Methionines:
    $sht1->write($r,$c++,$h{metocc});
    $sht1->write($r,$c++,$h{metocc} ? $h{metpos} : '-',$rightf);
    $rank .= $h{metocc} == 0 ? '0': '2';

    # Missing cleavages:
    $sht1->write($r,$c++,$h{missocc});
    $sht1->write($r,$c++,$h{missocc} ? $h{misspos} : '-',$rightf);
    $rank .= $h{missocc} == 0 ? '0': '2';

    # RT. Add them to hashes for plotting:
    if ($agnosticf || $evidencef) {
      $sht1->write($r,$c++,$h{rt},$rightf);
      $rt_exp{$pep} = $h{rt};
    }
      
    # Hydrophobicity index:
    $sht1->write($r,$c++,$h{hyd},$floatf);      

    # Evaluate theoretical RTs and add them to hashes for plotting:
    if (@smp_theta) {
      $rt_smp{$pep} = $h{hyd}*$smp_theta[1]+$smp_theta[0];
      $sht1->write($r,$c++,$rt_smp{$pep},$floatf);
    }    

    if (@irt_theta) {
      $rt_irt{$pep} = $h{hyd}*$irt_theta[1]+$irt_theta[0];
      $sht1->write($r,$c++,$rt_irt{$pep},$floatf);
    }
    
    # Predecessor, first, last and successor AAs:
    ($uprot) and ($sht1->write($r,$c++,$h{paa},$rightf));
    $sht1->write($r,$c++,$h{faa},$rightf);
    $sht1->write($r,$c++,$h{laa},$rightf);
    ($uprot) and ($sht1->write($r,$c++,$h{naa},$rightf));

    if ($enzyme =~ /^trypsin/) {
      if ($h{faa} eq 'D' || $h{faa} eq 'E') {
	$rank .= '2';
      }
      else {
	$rank .= '0';
      }

      if ($uprot) {
	if ($h{naa} eq 'D' || $h{naa} eq 'E') {
	  $rank .= '2';
	}
	else {
	  $rank .= '0';
	}
      }
    }
    
    ($patlas && ($peptidesf || $agnosticf || $srmf)) and $sht1->write($r,$c++,$h{instruments});

    push(@ranks,$rank);
    
    $r++;
    $c=0;
  }


  $sht1->freeze_panes(1,2);
  
  # Sort on ranks:
  @index = sort { $ranks[$a] cmp $ranks[$b] } 0..$#ranks;
  @peptides = @peptides[@index];
  @ranks = @ranks[@index];

  
  ### Write Ranking, sht2:
  $sht2 = $xx->add_worksheet('ranking');
  $p = @peptides+1;

  @W = ();
  push(@W,('Protein','Peptide','Length','Source of peptide identification'));
  ($peptidesf) and push(@W,'Intensity quartile');
  ($agnosticf) and push(@W,'Q.i. quartile');
  
  if ($peptidesf) {
    push(@W,('Samples with valid intensity value',
	     'MQ Unique (Groups)','MQ Unique (Proteins)'));
  }
  elsif ($proteomef) { 
    push(@W,'Occurrences in proteome sequences');
  }
  
  ($uprot) and push(@W,('PTMs','PTM evidences'));

  push(@W,('Methionines','Missing cleavages'));
  
  if ($enzyme =~ /^trypsin/) {
    push(@W,('First aa'));
    ($uprot) and push(@W,('Next aa'));
  }
  
  ($patlas && ($peptidesf || $agnosticf || $srmf)) and
    push(@W,'Instruments reported in PeptideAtlas experiments (from sample or SRM Atlas)');

  
  $sht2->write_row(0,0,\@W,$boldf);

  $r = 1;
  $c = 0;
  foreach $pep (@peptides) {
    %h = %{$H{$pep}};
    
    $sht2->write($r,$c++,$protaka ? $protaka : $prot);

    if (exists($figpos{$pep})) {
      $sht2->write_url($r,$c++,'internal:figures!A'.$figpos{$pep},undef,$pep);
    }
    else {
      $sht2->write($r,$c++,$pep);
    }

    $sht2->write($r,$c++,length($pep));

    if ($h{src} =~ /sample/) {
      $sht2->write($r,$c++,$h{src},$greenlf);
    }
    elsif ($h{src} eq 'SRM Atlas') {
      $sht2->write($r,$c++,$h{src},$graylf);
    }
    else {
      $sht2->write($r,$c++,$h{src},$redlf);
    }
    
    if ($agnosticf || $peptidesf) {
      if ($h{src} =~ /sample/) {
	if ($h{int} ne '-') {
	  if ($h{q} >= 3) {
	    $sht2->write($r,$c++,$h{q},$greenrf);
	  }
	  else {
	    $sht2->write($r,$c++,$h{q},$redrf);
	  }
	}
	else {
	  $sht2->write($r,$c++,'-',$grayrf);      
	}
      }
      else {
	$sht2->write($r,$c++,'-',$grayrf);
      }
    }
	
    if ($peptidesf) {
      if ($h{src} =~ /sample/) {
	if ($h{nzi} eq '-' || $h{nzi} == 0) {
	  $sht2->write($r,$c++,$h{nzi},$redrf);
	}
	else {
	  $sht2->write($r,$c++,$h{nzi},$greenrf);
	}
	
	$sht2->write($r,$c++,$h{mqunqgrp},($h{mqunqgrp} eq 'yes' ? $greenrf : $redrf));
	$sht2->write($r,$c++,$h{mqunqpro},($h{mqunqpro} eq 'yes' ? $greenrf : $redrf));
      }
      else {
	$sht2->write($r,$c++,'-',$grayrf);
	$sht2->write($r,$c++,'-',$grayrf);
	$sht2->write($r,$c++,'-',$grayrf);
      }
    }
    elsif ($proteomef) {
      $sht2->write($r,$c++,$h{pomeocc},$h{pomeocc} > 1 ? $redrf : $greenrf);
    }

    if ($uprot) {
      if (exists($h{fea})) {
	$sht2->write($r,$c++,$h{fea},$redlf);
	$sht2->write($r,$c++,$h{exp},$redlf);
      }
      else {
	$sht2->write($r,$c++,'-',$greenrf);      
	$sht2->write($r,$c++,'-',$greenrf);      
      }
    }
    
    $sht2->write($r,$c++,$h{metocc},$h{metocc} == 0 ? $greenrf : $redrf);
    $sht2->write($r,$c++,$h{missocc},$h{missocc} == 0 ? $greenrf : $redrf);

    if ($enzyme =~ /^trypsin/) {
      if ($h{faa} eq 'D' || $h{faa} eq 'E') {
	$sht2->write($r,$c++,$h{faa},$redrf);
      }
      else {
	$sht2->write($r,$c++,$h{faa},$greenrf);
      }

      if ($uprot) {
	if ($h{naa} eq 'D' || $h{naa} eq 'E') {
	  $sht2->write($r,$c++,$h{naa},$redrf);
	}
	else {
	  $sht2->write($r,$c++,$h{naa},$greenrf);
	}
      }
    }
    
    ($patlas && ($peptidesf || $agnosticf || $srmf)) and $sht2->write($r,$c++,$h{instruments});
    
    $r++;
    $c=0;
  }
  $sht2->freeze_panes(1,2);
  
  ### Figures:
  if (!$nofigures) {

    if ($samplew > 3) {
      $sh = $xx->add_worksheet('plots');
      foreach $pep (sort(keys(%figpos))) {
	$file = $protaka ? "$outd/$protaka-$pep.png" : "$outd/$prot-$pep.png";
	$sh->insert_image("A$figpos{$pep}",$file);
      }
    }

    if (@smp_theta || @irt_theta) {

      # Keep only the top 10 peptides in ranking:
      %aux = map { $_ => 1 } @peptides[0..9];

      for $k (keys(%rt_exp)) {
	if (!exists($aux{$k})) {
	  delete($rt_exp{$k});
	  delete($rt_smp{$k});
	  delete($rt_irt{$k});
	}
      }
      
      rt_plots(\%rt_exp,\%rt_smp,\%rt_irt,$protaka?$protaka:$prot,$outd);

      $filesmp = $protaka ? "$outd/$protaka-sample-rt.png" : "$outd/$prot-sample-rt.png";
      $fileirt = $protaka ? "$outd/$protaka-irt-rt.png" : "$outd/$prot-irt-rt.png";
      
      if (-e $filesmp || -e $fileirt) {
	$sh = $xx->add_worksheet('RT-plots');
	$row = 1;
	if (-e $filesmp) {
	  $sh->insert_image('A1',$filesmp);
	  $row += 25;
	}
      	if (-e $fileirt) {
	  $sh->insert_image("A$row",$fileirt);
	}
      }
    }
  }

  ### Attributes and ranking glossary:
  $dirname = dirname(__FILE__);
  $sht1 = $xx->add_worksheet('attributes-glossary');
  $sht2 = $xx->add_worksheet('ranking-glossary');
  if ($peptidesf) {
    include_tsv($sht1,"$dirname/glossary-mq-attributes.csv",$plainf,$boldf);
    include_tsv($sht2,"$dirname/glossary-mq-ranking.csv",$plainf,$boldf);
    $r = 30;
  }
  elsif ($agnosticf) {
    include_tsv($sht1,"$dirname/glossary-agn-attributes.csv",$plainf,$boldf);
    include_tsv($sht2,"$dirname/glossary-agn-ranking.csv",$plainf,$boldf);
    $r = 23;
  }
  else {
    include_tsv($sht1,"$dirname/glossary-bas-attributes.csv",$plainf,$boldf);
    include_tsv($sht2,"$dirname/glossary-bas-ranking.csv",$plainf,$boldf);
    $r = 17;
  }

  $sht2->write($r++,0,"Color map",$boldf);
  $sht2->write($r,0,"Most favorable",$greenlf);
  $sht2->write($r++,1,"default color: green");
  $sht2->write($r,0,"Kind of favorable/Neutral",$graylf);
  $sht2->write($r++,1,"default color: yellow");
  $sht2->write($r,0,"Least favorable",$redlf);
  $sht2->write($r,1,"default color: red");
    
  ### Metadata:
  $sh = $xx->add_worksheet('metadata');

  $r = 0;
  $c = 0;

  @W = ();

  if ($uprot) {
    if ($protaka) {
      push(@W,"$protaka (aka $prot): ".length($fasta).' aa');
    }
    else {
      push(@W,"$prot: ".length($fasta).' aa');
    }
  }
  else {
    push(@W,"$prot: unable to download from UniProt");
  }

    
  push(@W,scalar(@peptides).' peptides');
  
  if ($peptidesf) {
    push(@W,"Peptides file: $peptidesf (" . (-s $peptidesf) . " bytes)"); 
    ($evidencef) and push(@W,"Evidence file: $evidencef (" . (-s $evidencef) . " bytes)");  
    push(@W,"$nsmps samples");    
    push(@W,"$npepsmp peptides in samples");
    push(@W,"Intensities in samples: minimum is $I[0], maximum is $I[-1]");
  }

  if ($agnosticf) {
    push(@W,"Agnostic file: $agnosticf (" . (-s $agnosticf) . " bytes)");  
    push(@W,"$npepsmp peptides in samples");
    push(@W,"Q.I. in samples: minimum is $I[0], maximum is $I[-1]");
  }

  if ($srmf) {
    push(@W,"SRM Atlas file: $srmf (".scalar(keys %srm).' proteins)');
    ($nsrm == 0) and push(@W,"No SRM Atlas entry for $prot");
  }

  ($digest) and push(@W,"in-silico digestion with $enzyme");
  ($proteomef) and push(@W,"Proteome file: $proteomef (".scalar @pome.' sequences)');
  ($contf) and push(@W,"Contaminants file: $contf (".scalar @cont.' sequences)'); 
  ($irtf) and  push(@W,"iRTs file: $irtf"); 
  ($patlas) and  push(@W,"Data from PeptideAtlas build $patlas");

  $sh->write_col(0,0,\@W);

  $xx->close();
  undef($xx);
  
  # Remove plot files:
  if (!$nofigures) {
    foreach $pep (sort(keys(%figpos))) {
      $file = $protaka ? "$outd/$protaka-$pep.png" : "$outd/$prot-$pep.png";
      unlink($file);
    }
    
    (-e "$outd/$prot-sample-rt.png") && unlink("$outd/$prot-sample-rt.png");
    (-e "$outd/$protaka-sample-rt.png") && unlink("$outd/$protaka-sample-rt.png");
    (-e "$outd/$prot-irt-rt.png") && unlink("$outd/$prot-irt-rt.png");
    (-e "$outd/$protaka-irt-rt.png") && unlink("$outd/$protaka-irt-rt.png");
  }

  $verb and print "done\n";
}

if ($clean) {
  for $f (@del) {
    unlink($f);
  }
}

$verb and print "finished.\n";
exit(0);



################################################################################
# array-of-strings read_words($filename)
#
# Read words from a file.  A word is any string separated be one or
# more blanks.
#
# If # occurs in a line, the content from # to the end of the line is
# discarded.
#
# Return an array of strings with the trimmed words. If the file may
# not be opened then it dies with an error message.

sub read_words {

  my $fname = shift;
  
  my $fh;
  open($fh,'<',$fname) or abend("Unable to open $fname, $!");

  my @words = ();

  while (<$fh>) {
    chomp;
    $_ = (split(/#/,$_,2))[0];
    /^\s*$/ && next;

    my @aux = split(/\s+/,$_);
    for (my $i=0; $i<@aux; $i++) {
      push(@words,$aux[$i]);
    }
  }
  
  close($fh);

  return @words;
}



################################################################################
# hash read_keys_values($filename, $separator, $skip-lines)
#
# Read a file with lines in format ^\s*key\s*=\s*value\s* and return a
# hash with pairs key=>value.
#
# If '#' occurs in a line, line contents from '#' to the end of the
# line is discarded.
#
# If a separator is given, then it is used instead of '='.  
# If skip-lines is given, that number of lines at the file head are
# not loaded.
#
# Keys and values are trimmed for blanks on both ends.
#
# Empty keys and empty values are allowed.  Multiply defined keys
# retain the last value in file order.
#
# If an error occurs while opening the file then it dies.

sub read_keys_values {

  my $fname = shift;
  my $sep = shift;
  my $skip = shift;

  (!defined $sep) and ($sep = '=');
  (!defined $skip) and ($skip = 0);

  open(my $FILE,'<',$fname) or abend("Unable to open $fname, $!");

  while ($skip && !eof $FILE) {
    $_ = <$FILE>;
    $skip--;
  }

  my %hash = ();

  while (<$FILE>) {
    chomp;
    $_ = (split(/#/,$_,2))[0];
    (/^\s*$/) && next;
    my ($key,$value) = split(/$sep/,$_,2);
    $key =~ s/^\s+//;
    $key =~ s/\s+$//;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    $hash{$key} = $value;
  }

  close($FILE);

  return %hash;
}



################################################################################
# array csv_read_row($filename, $delimiter, $quote, $k)
#
# Return an array with the fields in the k-th row of a csv file.
# The first row is at offset 0.
# Values are trimmed for blanks and quote at both ends.
# It dies if the file may not be read.

sub csv_read_row {

  my $csvf = shift;
  my $delim = shift;
  my $quote = shift;
  my $k = shift;

  open(my $fh,"<",$csvf) or abend("Unable to read from $csvf.");

  my $line = '';
  do {
    $line = <$fh>;
  } until ($. == $k+1 || eof);
  
  if ($. < $k+1) {
    return ();
  }
  
  close($fh);

  return split_line($line,$delim,$quote,1);
}


  
################################################################################
# hoa csv_read_columns($filename, 
#                      $delimiter, $quote,
#                      $key-column-header, @value-columns-headers)
#
# Create a hash-of-arrays having one key for each row of key-column.
# For key there will be an array having the value-columns in each row,
# in the order given in value-columns.  Values are trimmed for blanks
# and quote at both ends.  Capitalization is ignored for column
# headers.
#
# For instance, if test1.csv contents is
#
# name,qty,year,price,dct
# john,2,2001,10,0
# mary,3,1999,20,2
# john,5,2002,15,0
# peter,4,2003,18,1
#
# Then invoking csv_read_columns('test1.csv',',', '"','name','price','qty')
#
# will produce a hoa having
#
# mary => (20, 3) 
# peter => (18, 4) 
# john => (10, 2, 15, 5) 

sub csv_read_columns {

  my $fname = shift;
  my $delim = shift;
  my $quote = shift;
  my $key = lc(shift);
  my @values = @_;

  open(my $fh,"<",$fname) or abend("Unable to read from $fname.");

  # Get the index of key and values columns:
  $_ = <$fh>;
  my @aux = split_line(lc($_),$delim,$quote,1);
  
  my $k = @aux;
  my @v = ();
  my ($i, $j);
  
  for ($i=0; $i<@aux; $i++) {
    if ($aux[$i] eq $key) {
      $k = $i;
    }
  }
  ($k == @aux) and abend("Column '$key' is missing from $fname.");
  
  for ($j=0; $j<@values; $j++) {
    my $value = lc($values[$j]);
    for ($i=0; $i<@aux; $i++) {
      if ($aux[$i] eq $value) {
	push(@v,$i);
	last;
      }
    }
    ($i == @aux) and abend("Column '$values[$j]' is missing from $fname.");
  }

  # Read rows:
  my %col = ();
  
  while (<$fh>) {
    @aux = split_line($_,$delim,$quote,1);
    $key = $aux[$k];
    for ($j=0; $j<@v; $j++) {
      push(@{$col{$key}},$aux[$v[$j]]);
    }
  }
  
  close($fh);

  return %col;
}



################################################################################
# array split_line($line, $delimiter, $quote, $trim)
#
# Split a line in each delimiter, except those enclosed in quotes.
# Return an array of line fields. Both ends may be trimmed for blanks
# (not enclosed in quotes) and quotes.
#
# delimiter may be undef and defaults to ,
# quote may be undef and defaults to "
# trim may be undef and defaults to 1

sub split_line {
  
  my $line = shift;
  my $delim = shift;
  my $quote = shift;
  my $trim = shift;

  chomp($line);
    
  (!defined($delim)) && ($delim = ',');
  (!defined($quote)) && ($quote = '"');
  (!defined($trim)) && ($trim = 1);
  
  my @rip = ();
  my @s = split(/$delim/,$line,-1);

  for (my $i=0; $i<@s-1; $i++) {
    if ($s[$i] =~ /$quote/ && $s[$i] !~ /$quote[^$quote]*$quote/) {
      my $j = $i+1;
      while ($j<@s && $s[$j] !~ /$quote/) {
	$s[$i] .= "$delim$s[$j]";
	push(@rip,$j);
	$j++;
      }
      $s[$i] .= "$delim$s[$j]";
      push(@rip,$j);
      $i = $j;
    }
  }

  for (my $i=$#rip; $i>=0; $i--) {
    splice(@s,$rip[$i],1);
  }

  if ($trim) {
    for (my $i=0; $i<@s; $i++) {
      $s[$i] =~ s/^\s*$quote?//;
      $s[$i] =~ s/$quote?\s*$//;
    }
  }
  
  return @s;
}



################################################################################
# float hydrophobicity_index($protein)
#
# Evaluate the hydrophobicity index described by:
# Krokhin OV et al.  An improved model for prediction of retention
# times of tryptic peptides in ion pair reversed-phase HPLC, Mol Cell
# Proteomics, 3(9), 908-919, 2004.

sub hydrophobicity_index {

  $_ = uc(shift);
  s/\s+//g;

  my @s = split(//);

  my %t = ('W' => 11.0, 'F' => 10.5, 'L' =>  9.6, 'I' =>  8.4, 'M' =>  5.8, 
	   'V' =>  5.0, 'Y' =>  4.0, 'A' =>  0.8, 'T' =>  0.4, 'P' =>  0.2, 
	   'E' =>  0.0, 'D' => -0.5, 'C' => -0.8, 'S' => -0.8, 'Q' => -0.9, 
	   'G' => -0.9, 'N' => -1.2, 'R' => -1.3, 'H' => -1.3, 'K' => -1.9);

  my $n = length($_);

  my $sumrc = 0;
  for my $aa (keys(%t)) {
    $sumrc += $t{$aa};
  }

  my $avgrc = $sumrc/20;
  
  my $kl = 1;
  if ($n < 10) {
    $kl -= 0.027*(10-$n);
  }
  if ($n > 20) {
    $kl -= 0.014*($n-20);
  }

  my $sum = 0;
  for (my $i=0; $i<@s; $i++) {
    !exists($t{$s[$i]}) and print "hydrophobicity_index: unknow symbol $s[$i]\n";
    $sum += $t{$s[$i]};
  }

  my $h;
  if (@s > 2) {
    $h = $kl * ($sum + 0.42*($avgrc-$t{$s[0]}) + 0.22*($avgrc-$t{$s[1]}) +
		0.05*($avgrc-$t{$s[2]}));
  }
  else {
    $h = $kl * $sum;
  }
  
  if ($h >= 38) {
    $h -= 0.3*($h-38);
  }

  return $h;
}



################################################################################
# (\@peptides,\@positions) digest_trypsin($sequence,$at,$notfollowed)
#
# Split a sequence of aminoacids after (C-terminus) of any aminoacid in at
# (string) that are not followed by and aminoacid in notfollowed (string).
#
# Return a reference to an array of strings, one for each peptide,
# and a reference to an array of the starting position of each peptide.

sub digest {

  my $t = uc(shift);
  my $at = shift;
  my $after = shift;

  my @pos = (); # The digestion positions.

  $at =~ s/(?=.)(?<=.)/\|/g;

  $_= "#$t"; 
  while (m/$at/g) {
    my $p = pos()-1;
    if (index($after,substr($_,$p+1,1)) == -1) {
      push(@pos,$p);
    }
  }

  my @frag = (); # The fragments.

  unshift(@pos,0);
  ($pos[@pos-1] < length($t)) and push(@pos,length($t));
  
  for ($i=0; $i<@pos-1; $i++) {
    $s = substr($t,$pos[$i],$pos[$i+1]-$pos[$i]);
    push(@frag,$s);
  }

  pop(@pos);
  
  return (\@frag,\@pos);
}

  

######################################################################
# array-of-hashes ff_load($filename, $min_length, $max_length, &tag-function)
#
# Load a fasta file of molecular sequences into an array of hashes
# with the form:
#
# @fasta[]->{header} is the fasta header.
#           {tag}    is the fasta tag.
#           {seq}    is the molecular or quality sequence.
#
# This function (i) removes ^>\s* and \s*$ from headers and (ii)
# captalizes letters and removes spaces and newlines from sequences.
#
# $min_length: sequences with less than min_length letters are not
# loaded.  If undefined or 0 then the filter is not applied.
#
# $max_length: sequences with more than max_length letters are not
# loaded.  If undefined or 0 then the filter is not applied.
#
# tag-function: a reference to a function that extracts a tag from a
# fasta header. If undefined, first_word_tag() is used.
#
# It dies if the fasta file can't be open.

sub ff_load {

  my $file = shift;
  my $minlen = shift;
  my $maxlen = shift;
  my $tagfunc = shift;

  (!defined($minlen)) && ($minlen = 0);
  (!defined($minlen)) && ($minlen = 0);
  (!defined($tagfunc)) && ($tagfunc = \&first_word_tag);

  open(my $FASTA,"<",$file) or abend("Unable to open $file.");

  my @fasta = ();

  # Drop anything prior to the first line starting with >:
  while (<$FASTA>) {
    /^>/ && do {
      seek($FASTA,-length($_),1);
      last;
    }
  }

  my $i = -1;
  while (<$FASTA>) {

    chomp;
    
    /^>/ && do {
      if ($i > -1) {
	my $l = length($fasta[$i]{seq});
	if (($minlen > 0 && $l < $minlen) || ($maxlen > 0 && $l > $maxlen)) {
	  $i--;
	}
      }

      $i++;

      s/^\s*//;
      s/\s+$//;
      
      $fasta[$i] = { () };
      $fasta[$i]{header} = $_;
      $fasta[$i]{tag} = &$tagfunc($_);
      $fasta[$i]{seq} = '';
      next;
    };

    s/\s//g;
    $fasta[$i]{seq} .= uc($_);
  }

  if ($i > -1) {
    my $l = length($fasta[$i]{seq});
    if (($minlen > 0 && $l < $minlen) || ($maxlen > 0 && $l > $maxlen)) {
      pop(@fasta);
    }
  }
  
  close($FASTA);

  return @fasta;
}                        



################################################################################
# string genbank_tag($header)
#
# Extract a GenBank accession number in a fasta header. 
#
# It returns the leftmost match with the first pattern in the ordered
# list bellow.  If none matches, it returns ''.
# 
# 1) GenBank Version sequence identifier 
#    gb|[A-Z]{2}[0-9]{6}(.[0-9]+)?| or GB|[A-Z]{2}[0-9]{6}(.[0-9]+)?| or
#    gb|[A-Z]{3}[0-9]{5}(.[0-9]+)?| or GB|[A-Z]{3}[0-9]{5}(.[0-9]+)?|.
# 2) Genbank GI sequence identifier 
#    gi|[0-9]+| or GI|[0-9]+|. 
# 3) RefSeq sequence identifier 
#    ref|[A-Z]{2}_[A-Z]*[0-9]+| or REF|[A-Z]{2}_[A-Z]*[0-9]+|.
# 4) SP sequence identifier 
#    sp|.+| or SP|.+| 
# 5) TR sequence identifier 
#    tr|.+| or TR|.+| 
# 6) The first word.

sub genbank_tag {

  $_ = shift;
  /gb\|([A-Z]{2}\d{6}(\.\d+)?)\|/i and return $1;
  /gb\|([A-Z]{3}\d{5}(\.\d+)?)\|/i and return $1;
  /gi\|(\d+)\|/i and (return $1);
  /ref\|([A-Z]{2}\_[A-Z]*\d+)\|/i and return $1;
  /sp\|([^\|]+)\|/i and return $1;
  /tr\|([^\|]+)\|/i and return $1;
  /([\w\-]+)/ and return $1;

  return '';
}



################################################################################
# (hash-ref,hash-ref) obo_load_forest($obo-file)
#
# Return a reference to a hash that contains the tree as term-id => is_a
# and a reference to a hash that maps term-id => name.

sub obo_load_forest {

  my $filename = shift;

  my $OBO;
  open($OBO,"<",$filename) or abend("Unable to open $filename");

  my %tree = ();
  my %name = ();
  my $id = '';
  my $isa = '';

  while (<$OBO>) {

    chomp;
    
    /^\[Term\]$/ && do {
      if ($id) {
	$tree{$id} = $isa;
	$isa = '';
      }
      next;
    };

    /^id:\s*([0-9A-Za-z:]+)\s*/ && do {
      $id = $1;
      next;
    };

    /^is_obsolete: true$/ && do {
      $id = '';
    };

    $id && /^name: (.*)$/ && do {
      $name{$id} = $1;
    };
    
    !$isa && /^is_a:\s*([0-9A-Za-z:]+)\s*/ && do {
      $isa = $1;
      next;
    }
  }

  close($OBO);
  #print "$_ $tree{$_}\n" for (keys %tree);

  return (\%tree,\%name);
}



################################################################################
# obo_descends(\%tree,$id,$name)
#
# Return 1 if id descends from name in tree, and return 0 otherwise.

sub obo_descends {

  my $ref = shift;
  my $id = shift;
  my $from = shift;
  
  my %tree = %{$ref};

  while ($id) {
    $id = $tree{$id};
    if ($id eq $from) {
      return 1;
    }
  }
  
  return 0;
}



################################################################################
# hash uprot_get_basic($xml-file)
#
# Return a hash having
#  {name} => string
#  {proteinfullname} => string
#  {gene} => string
#  {synonyms} => array of strings
  
sub uprot_get_basic {

  my $fname = shift;
  
  my $dom = XML::LibXML->load_xml(location => $fname);
  my $xpc = XML::LibXML::XPathContext->new($dom);
  $xpc->registerNs('up','http://uniprot.org/uniprot');

  my %data = ();
  
  my @nodes = $xpc->findnodes('/up:entry/up:name');
  $data{name} = (@nodes ? ($nodes[0])->to_literal() : '');

  @nodes = $xpc->findnodes('/up:entry/up:protein/up:recommendedName/up:fullName');
  $data{proteinfullname} = (@nodes ? ($nodes[0])->to_literal() : '');

  @nodes = $xpc->findnodes('/up:entry/up:gene/up:name');
  $data{gene} = (@nodes ? ($nodes[0])->to_literal() : '');

  $data{synonyms} = [ () ];
  foreach my $acc ($xpc->findnodes('/up:entry/up:accession')) {
    push(@{$data{synonyms}},$acc->to_literal());
  }

  return %data;
}




################################################################################
# string uprot_get_fasta($xml-file)

sub uprot_get_fasta {

  my $filename = shift;

  (-e $filename && -r $filename && -s $filename) or return '';

  # Process xml:
  my $dom = XML::LibXML->load_xml(location => $filename);
  my $xpc = XML::LibXML::XPathContext->new($dom);
  $xpc->registerNs('up','http://uniprot.org/uniprot');

  my $fasta = $xpc->findnodes('/up:entry/up:sequence');

  return $fasta->to_literal();
}



################################################################################
# array-of-hashes uprot_get_features($xml-file, \%eco-forest, \%eco-names) 
#
# Get features from UniProt XML.  Return an array of hashes with fields
# type, description, at, evidence, experimental (0 or 1).
  
sub uprot_get_features {

  my $filename = shift;
  my $forestr = shift;
  my $namesr = shift;

  (-e $filename && -r $filename && -s $filename) or return ();

  my %forest = %{$forestr};
  my %names = %{$namesr};  


  # Process xml:
  my $dom = XML::LibXML->load_xml(location => $filename);
  my $xpc = XML::LibXML::XPathContext->new($dom);
  $xpc->registerNs('up','http://uniprot.org/uniprot');

  
  # Collect data on evidences in parallel arrays:
  my @evcode = ();  # the evidence ECO code
  my @evsrc = ();   # the source description string, 'no source' if none
  my @evisref = (); # if crossref, the number of the other evidence, otherwise 0

  $evcode[0] = '';
  $evsrc[0] = '';
  $evisref[0] = '';

  foreach my $ev ($xpc->findnodes('/up:entry/up:evidence')) {
    my $type = $ev->findnodes('./@type');
    my $key = $ev->findnodes('./@key');
    $evcode[$key] = $type;

    my @srcs = $xpc->findnodes('./up:source',$ev);

    if (@srcs) {
      my $ref = $srcs[0]->findnodes('./@ref');	
      if ($ref) {
	$evsrc[$key] = $ref;
	$evisref[$key] = 1;
      }
      else {
	$evsrc[$key] = '';
	$evisref[$key] = 0;
	
	my @dbs = $xpc->findnodes('./up:dbReference',$srcs[0]);
	my $dbtype = $dbs[0]->findnodes('./@type');
	my $dbid = $dbs[0]->findnodes('./@id');

	$evsrc[$key] = "$dbtype $dbid";
      }
    }
    else {
      $evsrc[$key] = "no source";
      $evisref[$key] = 0;
    }
  }

  # Unfold crossrefs in evidence arrays:
  for (my $i=0; $i<@evcode; $i++) {
    if ($evisref[$i] && int($evsrc[$i]) < scalar(@evcode)) {
      $evisref[$i] = $evsrc[$i];
      $evsrc[$i] = $evsrc[$evsrc[$i]];
    }
    else {
      $evisref[$i] = 0;
    }
  }
  
  
  # Process features:
  my @F = ();
  
  foreach my $feat ($xpc->findnodes('/up:entry/up:feature')) {

    my %f = ();

    $f{type} = $feat->findnodes('./@type');
    $f{description} = $feat->findnodes('./@description');
    my $evidence = $feat->findnodes('./@evidence');

    # Location:
    my $p = $xpc->findnodes('./up:location/up:position/@position',$feat);
    if ($p) {
      $f{at} = "$p";
    }
    else {
      my $p = $xpc->findnodes('./up:location/up:begin/@position',$feat);
      my $q = $xpc->findnodes('./up:location/up:end/@position',$feat);
      $f{at} = "$p-$q";
    }

    # Check if evidence is experimental:
    $f{experimental} = 0;

    if ($evidence) {
      my @aux = split(/ /,$evidence);
      for (my $i=0; $i<@aux; $i++) {
	if (obo_descends(\%forest,$evcode[$aux[$i]],'ECO:0000006')) {
	  $f{evidence} = "$evcode[$aux[$i]] $evsrc[$aux[$i]] $names{$evcode[$aux[$i]]}";
	  $f{experimental} = 1;
	  last;
	}
      }
      
      if ($f{experimental} == 0) {
	$f{evidence} = "$evcode[$aux[0]] $evsrc[$aux[0]] $names{$evcode[$aux[0]]}";
      }
    }
    else {
      $f{evidence} = '';
    }
    
    push(@F, { %f } );    
  }

  return @F;
}



################################################################################
# number median(\@data)

sub median {
  my $r = shift;
  my @a = sort {$a <=> $b} @{$r};

  my $n = @a;
  if ($n % 2) {
    return $a[int($n/2)];
  }
  else {
    return ($a[$n/2-1] + $a[$n/2])/2;
  }
}



################################################################################
sub log2 {
  my $n = shift;
  return $n <= 0 ? 0 : log($n)/log(2);
}



################################################################################
sub log10 {
  my $n = shift;
  return $n <= 0 ? 0 : log($n)/log(10);
}



################################################################################
# rt_plots(\%RT_exp, \%RT_smp, \%RT_irt, $prot, $dir)
#
# Plot retention times for each peptide of a protein.  Experimental
# RTs and theoretical RTs based on sample go in a plot, theoretical
# RTs based on iRTs retention times go in another plot.
#
# %RT_exp has the experimental RTs, peptide => RT.
# %RT_smp has the theoretical RTs wrt samples, peptide => RT.
# %RT_exp has the experimental RTs wrt iRTs, peptide => RT.
# $prot is the protein accession.
# $dir is the output directory.

sub rt_plots {

  my $RT = shift;
  my %rt_exp = %{$RT};

  $RT = shift;
  my %rt_smp = %{$RT};
  
  $RT = shift;
  my %rt_irt = %{$RT};

  my $prot = shift;
  my $dir = shift;

  for my $k (keys(%rt_exp)) {
    if ($rt_exp{$k} eq '-') {
      delete($rt_exp{$k})
    }
  }

  my $blue = Graphics::Color::RGB->new(red => 0, green => 0, blue => 1);
  my $orange = Graphics::Color::RGB->new(red => 0.88, green => 0.58, blue => 0.19);
  
  # Plot of experimental RTs and theoretical RTs interpolated on experimental RTs:
  if (scalar(keys(%rt_exp)) > 0 || scalar(keys(%rt_smp)) > 0) {

    # @xlabs will have the sorted retention times. @ylabs will have
    # the peptides sorted wrt @xlabs.
    my @xlabs = ();
    my @ylabs = ();

    for my $pep (keys(%rt_exp)) {
      push(@xlabs,$rt_exp{$pep});
      push(@ylabs,$pep);
    }
    for my $pep (keys(%rt_smp)) {
      push(@xlabs,$rt_smp{$pep});
      push(@ylabs,$pep);
    }

    my @index = sort { $xlabs[$a] <=> $xlabs[$b] } 0..$#xlabs;
    @xlabs = @xlabs[@index];
    my @aux = @ylabs[@index];

    # Build @ylabs by removing duplicates from @aux:
    @ylabs = ();
    for (my $i=0; $i<@aux; $i++) {
      my $k;
      for ($k=0; $k<@ylabs; $k++) {
	if ($aux[$i] eq $ylabs[$k]) {
	  last;
	}
      }
      if ($k == @ylabs) {
	push(@ylabs,$aux[$i]);
      }
    }

    my $k = 0;
    my %p2y = map { $_, $k++ } @ylabs;
    
    my @colors = ($orange,$blue);
    my @series = ();
    my @legend = ();
      
    if (keys(%rt_smp)) {
      my @x = ();
      my @y = ();
      
      for my $pep (keys(%rt_smp)) {
	my $time = $rt_smp{$pep};
	push(@x,$time);
	push(@y,$p2y{$pep});
      }

      if (@x) {
	my $s2 = Chart::Clicker::Data::Series->new({keys => \@x,
						    values => \@y,
						    name => 'Theoretical RT w.r.t sample'});
	push(@series,$s2);
	push(@legend,"theo");
      }
    }

    if (keys(%rt_exp)) {
      my @x = ();
      my @y = ();
      
      for my $pep (keys(%rt_exp)) {
	my $time = $rt_exp{$pep};
	push(@x,$time);
	push(@y,$p2y{$pep});
      }

      if (@x) {
	my $s1 = Chart::Clicker::Data::Series->new({keys => \@x,
						    values => \@y,
						    name => 'Experimental RT'});
	push(@series,$s1);
	push(@legend,'exp');
      }
    }
    
    my $maxl = 0;
    foreach my $pep (@ylabs) {
      (length($pep) > $maxl) and ($maxl = length($pep));
    }

    my $w = @xlabs*20;
    ($w < 600) and ($w = 600);
    $w += $maxl*8;
    
    my $cc = Chart::Clicker->new(width => $w, height => 300+12*@ylabs, format => 'png');
    
    $cc->title->text("$prot - top 10 peptides in ranking");
    $cc->title->font->size(20);
    $cc->title->padding->top(15);
    $cc->title->padding->bottom(15);
    $cc->legend->visible(1);
    $cc->legend->font->weight('bold');
    $cc->color_allocator->colors(\@colors);
    $cc->add_to_datasets(Chart::Clicker::Data::DataSet->new(series => \@series));
    
    my $cxt = $cc->get_context('default');
    
    my $y = Chart::Clicker::Axis->new(orientation => 'vertical',
				      position => 'left',
				      tick_label_angle => 0);
    
    $y->{tick_values} = [0..@ylabs];
    $y->{tick_labels} = \@ylabs;
    $y->range(Chart::Clicker::Data::Range->new(lower => -1, upper => @ylabs+0.25));
    $y->label_font->size(12);
    $cxt->{range_axis} = $y;
    
    my $x = Chart::Clicker::Axis->new(orientation => 'horizontal',
				      position => 'left',
				      #staggered => 1,
				      fudge_amount => 0.05,
				      tick_label_angle => 270*3.1416/180);
     
    $x->{tick_values} = \@xlabs;
    
    for (my $i=0; $i<@xlabs; $i++) {
      $xlabs[$i] = sprintf("%.2f",$xlabs[$i]);
    }
    
    $x->{tick_labels} = \@xlabs;
    $x->range(Chart::Clicker::Data::Range->new(lower => $xlabs[0], upper => $xlabs[-1]));
    $x->label_font->size(12);
    $x->label('minutes');
    $cxt->{domain_axis} = $x;
    
    $cxt->renderer(Chart::Clicker::Renderer::Point->new);
    $cxt->renderer->shape(Geometry::Primitive::Circle->new({radius => 5}));
    
    $cc->write_output("$dir/$prot-sample-rt.png"); 
 }

  
  # Plot theoretical RTs interpolated on IRTs:
  if (scalar(keys(%rt_irt)) > 0) {

    my @ylabs = ();
    my @times  = ();
    my @xlabs = ();
    my $min = 10000;
    my $max = 0;
    my $maxl = 0;
    
    for my $k (keys(%rt_irt)) {
      my $time = $rt_irt{$k};
      push(@ylabs,$k);
      push(@xlabs,sprintf("%.2f",$time));
      push(@times,$time);
      
      ($time < $min) and ($min = $time);
      ($max < $time) and ($max = $time);
      (length($k) > $maxl) and ($maxl = length($k));
    }
    
    my @index = sort { $times[$a] <=> $times[$b] } 0..$#times;
    @ylabs = @ylabs[@index];
    @xlabs = @xlabs[@index];
    @times = @times[@index];
    
    my @colors = ($orange);

    my @series = ();
    my $s1 = Chart::Clicker::Data::Series->new({keys => \@times,
						values => [0..$#times],
						name => 'Theoretical RT w.r.t. iRTs'});
    push(@series,$s1);

    my @legend = ();
    push(@legend,'irt');
    
    my $w = @xlabs*20;
    ($w < 600) and ($w = 600);
    $w += $maxl*8;
    
    my $cc = Chart::Clicker->new(width => $w, height => 300+12*@ylabs, format => 'png');
    $cc->title->text("$prot - top 10 peptides in ranking");
    $cc->title->font->size(20);
    $cc->title->padding->top(15);
    $cc->title->padding->bottom(15);
    $cc->legend->visible(1);
    $cc->legend->font->weight('bold');
    $cc->color_allocator->colors(\@colors);
    $cc->add_to_datasets(Chart::Clicker::Data::DataSet->new(series => \@series));
    
    my $cxt = $cc->get_context('default');
    
    my $y = Chart::Clicker::Axis->new(orientation => 'vertical',
				      position => 'left',
				      tick_label_angle => 0);
    
    $y->{tick_values} = [0..@ylabs-1];
    $y->{tick_labels} = \@ylabs;
    $y->range(Chart::Clicker::Data::Range->new(lower => -1, upper => @ylabs+0.25));
    $y->label_font->size(12);
    $cxt->{range_axis} = $y;
    
    my $x = Chart::Clicker::Axis->new(orientation => 'horizontal',
				      position => 'left',
				      #staggered => 1,
				      fudge_amount => 0.05,
				      tick_label_angle => 270*3.1416/180);
     
    $x->{tick_values} = \@times;
    $x->{tick_labels} = \@xlabs;
    $x->range(Chart::Clicker::Data::Range->new(lower => $min, upper => $max));
    $x->label_font->size(12);
    $x->label('minutes');
    $cxt->{domain_axis} = $x;

    $cxt->renderer(Chart::Clicker::Renderer::Point->new);
    $cxt->renderer->shape(Geometry::Primitive::Circle->new({radius => 5}));
    
    $cc->write_output("$dir/$prot-irt-rt.png");
  }
    
}



################################################################################
# int intensity_plots($src, $prot, \%sample-intensities, \%groups, $dir)
#
# Plot intensities for each peptide of a protein across samples.
#
# $src is either 'MQ' or 'AGNOSTIC'
# $prot is the protein ACC.
# %sample-intensities is a HoH with the intensity of each peptide
#   in every sample.  That is, peptide => { sample => intensity }.
# %groups is a hash sample => group.
# $dir is the output directory.
#
# Return the height of figures in pixels. 

sub intensity_plots {

  my $src = shift;
  my $prot = shift;
  my $smps = shift;
  my $grps = shift;
  my $dir = shift;

  # An array of peptides:
  my @peptides = keys %{$smps};
  my $npeps = @peptides;

  # An array of sample names:
  my @smpids = keys %{$smps->{$peptides[0]}};
  @smpids = sort(@smpids);
  my $nsmps = @smpids;

  my %unitgrp = ();
  if (!defined $grps) {
    %unitgrp = map { $_ , "G1" } @smpids;
    $grps = \%unitgrp;
  }

  my $gray = Graphics::Color::RGB->new(red => 0.50, green => 0.50, blue => 0.50);
  my $red = Graphics::Color::RGB->new(red => 0.85, green => 0.09, blue => 0.09);
  my $green = Graphics::Color::RGB->new(red => 0.3, green => 0.7, blue => 0.3);
  my $blue = Graphics::Color::RGB->new(red => 0, green => 0, blue => 1);
  my $orange = Graphics::Color::RGB->new(red => 0.88, green => 0.58, blue => 0.19);
  my $lblue = Graphics::Color::RGB->new(red => 0.5, green => 0.7, blue => 1);
  my $lgreen = Graphics::Color::RGB->new(red => 0.3, green => 0.9, blue => 0.3);


  # An array @groups of groups,
  # an array @acc of accumulated group sizes,
  # and a hash %sample_index s.t. sample-name => group-index:
  my %hash = map { $_ , 1 } values(%{$grps});
  my @groups = sort(keys(%hash));
  my $ngroups = @groups;
  
  my %aux = ();
  for (my $i=0; $i<$ngroups; $i++) {
    $aux{$groups[$i]} = $i;
  }

  my %sample_index = ();
  my @group_sizes = ();

  for (keys(%{$grps})) {
    $sample_index{$_} = $aux{$grps->{$_}};
    $group_sizes[$aux{$grps->{$_}}]++;
  }

  # The accumulated sizes of groups:
  my @acc = @group_sizes;
  for (my $i=1; $i<$ngroups; $i++) {
    $acc[$i] += $acc[$i-1];
  }
  unshift(@acc,0);

  # An array that indicates the group to which column in @smpids belongs:
  my @order = (); 
  for my $sample (@smpids) { 
    if (!exists $sample_index{$sample}) {
      print "Unknown group for $sample\n";
      exit(1);
    }
    
    push(@order,$sample_index{$sample});
  }
  
  # An array of sample labels by groups, in the same relative
  # order they appear in smpids.  That array will label the x axis ticks:
  my @aux = ();
  for (my $i=0; $i<$ngroups; $i++) {
    $aux[$i] = [ () ];
  }

  for my $sample (@smpids) { 
    push(@{$aux[$sample_index{$sample}]},$sample);
  }

  my @xlabs = ();
  for (my $i=0; $i<$ngroups; $i++) {
    push(@xlabs,@{$aux[$i]});
  }

  # An identity array:
  my @ident = 0..$#order; 
  
  # Add a series for each peptide of $prot. These are the gray points:
  my @series = ();
  my @all = ();
  my $k = 0;

  my $max = 0; # maximum intensity
  
  for my $pep (@peptides) {

    for (my $i=0; $i<$ngroups; $i++) {
      for (my $j=0; $j<@smpids; $j++) {
	if ($order[$j] == $i) {
	  my $int = $smps->{$pep}{$smpids[$j]};
	  push(@{$all[$k]},log10($int));
	  if ($max < $int) {
	    $max = $int;
	  }
	}
      }
    }

    my $series = Chart::Clicker::Data::Series->new({keys => \@ident,
						    values => $all[$k],
						    name => ''});
    push(@series,$series);
    $k++;
  }

  # Color and legend arrays:
  my @colors = ();
  my @legend = ();

  for (my $i=0; $i<$npeps; $i++) {
    push(@colors,$gray);
  }
  push(@colors,($red,$blue,$green,$orange,$lblue,$lgreen));


  ($max == 0) and ($max = 10);
  $max = log10($max);

  my @ylabs = (0);
  for (my $i=1; $i<=$max; $i++) {
    my $num = 10**$i;
    while ($num =~ s/(\d+)(\d\d\d)/$1\,$2/) {};
    push(@ylabs,$num);
  }

  # The heigth and width of figures:
  my $w = 700;
  (@xlabs > 10) and ($w = @xlabs * 20 + 200);

  my $h = 0;
  for my $l (@xlabs) {
    (length($l) > $h) and ($h = length($l));
  }
  $h = $h*8 + 350;
  ($h < 400) and ($h = 400);
  
  # For each peptide, add its colored series and write a points plot to file:
  for my $pep (@peptides) {
    
    # Divide intensities for pep into a series for each group:
    my @ints = ();
    for (my $i=0; $i<$ngroups; $i++) {
      $ints[$i] = [ () ];
    }
    
    for (my $j=0; $j<$nsmps; $j++) {
      push(@{$ints[$order[$j]]},log10($smps->{$pep}{$smpids[$j]}));
    }

    for (my $i=0; $i<$ngroups; $i++) {
      my $series = Chart::Clicker::Data::Series->new({keys => [ ($acc[$i]..$acc[$i+1]-1) ],
						      values => $ints[$i]});
      
      if ($ngroups > 1) {
	push(@legend,"$groups[$i]");
	$series->name("$groups[$i]");
      }
      else {
	$series->name('');
      }
      push(@series,$series);
    }
    
    my $cc = Chart::Clicker->new(width => $w, height => $h, format => 'png');

    $cc->title->text("$pep - $prot");
    $cc->title->font->size(20);
    $cc->title->padding->top(15);
    $cc->title->padding->bottom(15);
    $cc->legend->visible($ngroups > 1 ? 1 : 0);
    $cc->legend->font->weight('bold');
    $cc->color_allocator->colors(\@colors);
    
    my $ds = Chart::Clicker::Data::DataSet->new(series => \@series);
    $cc->add_to_datasets($ds);

    my $x = Chart::Clicker::Axis->new(orientation => 'horizontal',
				      position => 'left',
				      tick_label_angle => 275*3.1416/180);
    $x->{tick_values} = [0..$#xlabs];
    $x->{tick_labels} = \@xlabs;
    $x->range(Chart::Clicker::Data::Range->new(lower => -1, upper => @xlabs+0.25));
    $x->label_font->size(12);

    my $cxt = $cc->get_context('default');

    $cxt->{domain_axis} = $x;

    $cxt->range_axis->tick_values([0..$#ylabs]);
    $cxt->range_axis->tick_labels(\@ylabs);

    my $s = 12/300;
    $cxt->range_axis->range(Chart::Clicker::Data::Range->new(min => -$s*$max, max => (1+$s)*$max));
    $cxt->range_axis->label($src eq 'MQ' ? 'intensity' : 'quantitative information');
    
    $cxt->renderer(Chart::Clicker::Renderer::Point->new);
    $cxt->renderer->shape(Geometry::Primitive::Circle->new({radius => 6}));
    
    $cc->write_output("$dir/$prot-$pep.png");
    
    for (my $i=0; $i<$ngroups; $i++) {
      pop(@series);
      pop(@legend);
    }

    # Break circular refs in $cc:
    undef($cc->{component_list}->{components});
    undef($cc->{legend}->{component_list}->{components});
    undef($cc->{plot});
    undef($cc->{contexts}->{default});
    undef($cc->{legend}->{clicker});
    undef($cc->{marker_overlay}->{clicker});
    undef($cc);

    # use Data::Dumper;
    # print Dumper($cc);
    # use Devel::Cycle;
    # find_cycle($cc);
  }

  return $h;
}



################################################################################
# sub include_tsv($sheet, $tsv-filename, $plain-format, $bold-format)
#
# Copy contents of tsf to a xlsx sheet.

sub include_tsv {

  my $sht = shift;
  my $csvf = shift;
  my $plainf = shift;
  my $boldf = shift;

  my ($i, $j);
 
  my $fh;
  if (!open($fh,'<',$csvf)) {
    $sht->write_string(0,0,"File $csvf is missing");
    return;
  }
  
  my @width = ();
  
  $_ = <$fh>;
  chomp;
  my @line = split(/\t/,$_);
  $sht->write_row(0,0,\@line,$boldf);
  
  for ($j=0; $j<@line; $j++) {
    $width[$j] = length($line[$j]);
  }
  
  $i = 1;

  while (<$fh>) {
    chomp;
    if (/^\s*$/) {
      $i++;
      next;
    }

    @line = split(/\t/,$_);

    for ($j=0; $j<@line; $j++) {
      if ($line[$j] =~ /^\s*$/) {
	;
      }
      elsif ($line[$j] =~ /mergerow\{(\d+)\}\s*(.*)/) {
	$sht->merge_range($i,$j,$i+$1-1,$j,$2,$plainf);
	my $l = length($2);
	($width[$j] < $l) and ($width[$j] = $l);
      }
      elsif ($line[$j] =~ /mergecol\{(\d+)\}\s*(.*)/) {
	$sht->merge_range($i,$j,$i,$j+$1-1,$2,$plainf);
	$j += $1-1;
	my $l = length($2);
	($width[$j] < $l) and ($width[$j] = $l);
      }
      else {
	$sht->write($i,$j,$line[$j],$plainf);
	my $l = length($line[$j]);
	($width[$j] < $l) and ($width[$j] = $l);
      }
    }

    $i++;
  }

  for ($j=0; $j<@width; $j++) {
    $sht->set_column($j,$j,int($width[$j]>100 ? $width[$j]*0.85 : $width[$j]));
  }
  
  close($fh);
}



###########################################################################
# ($avg,$var) = avg_var(\@data)
#
# Average and sample variance.  This is a stable algorithm, as eqs 15
# and 16 on page 216 of The Art of Computer Programming, D.E. Knuth,
# V2, 2ed, 1973.

sub avg_var {

  my $A = shift;
  my $n = scalar(@$A);

  ($n==0) && return (0,0);
  ($n==1) && return ($A->[0],0);

  my $mCurr = $A->[0];
  my $sCurr = 0;
  my $vCurr = 0;

  for (my $i=1; $i<$n; $i++) {
    my $mPrev = $mCurr;
    my $sPrev = $sCurr;
    
    $mCurr = $mPrev + ($A->[$i] - $mPrev) / ($i+1);
    $sCurr = $sPrev + ($A->[$i] - $mPrev) * ($A->[$i] - $mCurr);
    $vCurr = $sCurr / $i;
  }

  return ($mCurr,$vCurr);
}



### Data for alignments:
%aa2index = ( 'A'=>0,'R'=>1,'N'=>2,'D'=>3,'C'=>4,'Q'=>5,'E'=>6,'G'=>7,'H'=>8,'I'=>9,
	      'L'=>10,'K'=>11,'M'=>12,'F'=>13,'P'=>14,'S'=>15,'T'=>16,
	      'W'=>17,'Y'=>18,'V'=>19,'B'=>20,'Z'=>21,'X'=>22,'*'=>23 );

@blosum62 = ( [  4,-1,-2,-2, 0,-1,-1, 0,-2,-1,-1,-1,-1,-2,-1, 1, 0,-3,-2, 0,-2,-1, 0,-4 ],
	      [ -1, 5, 0,-2,-3, 1, 0,-2, 0,-3,-2, 2,-1,-3,-2,-1,-1,-3,-2,-3,-1, 0,-1,-4 ],
	      [ -2, 0, 6, 1,-3, 0, 0, 0, 1,-3,-3, 0,-2,-3,-2, 1, 0,-4,-2,-3, 3, 0,-1,-4 ],
	      [ -2,-2, 1, 6,-3, 0, 2,-1,-1,-3,-4,-1,-3,-3,-1, 0,-1,-4,-3,-3, 4, 1,-1,-4 ],
	      [  0,-3,-3,-3, 9,-3,-4,-3,-3,-1,-1,-3,-1,-2,-3,-1,-1,-2,-2,-1,-3,-3,-2,-4 ],
	      [ -1, 1, 0, 0,-3, 5, 2,-2, 0,-3,-2, 1, 0,-3,-1, 0,-1,-2,-1,-2, 0, 3,-1,-4 ],
	      [ -1, 0, 0, 2,-4, 2, 5,-2, 0,-3,-3, 1,-2,-3,-1, 0,-1,-3,-2,-2, 1, 4,-1,-4 ],
	      [  0,-2, 0,-1,-3,-2,-2, 6,-2,-4,-4,-2,-3,-3,-2, 0,-2,-2,-3,-3,-1,-2,-1,-4 ],
	      [ -2, 0, 1,-1,-3, 0, 0,-2, 8,-3,-3,-1,-2,-1,-2,-1,-2,-2, 2,-3, 0, 0,-1,-4 ],
	      [ -1,-3,-3,-3,-1,-3,-3,-4,-3, 4, 2,-3, 1, 0,-3,-2,-1,-3,-1, 3,-3,-3,-1,-4 ],
	      [ -1,-2,-3,-4,-1,-2,-3,-4,-3, 2, 4,-2, 2, 0,-3,-2,-1,-2,-1, 1,-4,-3,-1,-4 ],
	      [ -1, 2, 0,-1,-3, 1, 1,-2,-1,-3,-2, 5,-1,-3,-1, 0,-1,-3,-2,-2, 0, 1,-1,-4 ],
	      [ -1,-1,-2,-3,-1, 0,-2,-3,-2, 1, 2,-1, 5, 0,-2,-1,-1,-1,-1, 1,-3,-1,-1,-4 ],
	      [ -2,-3,-3,-3,-2,-3,-3,-3,-1, 0, 0,-3, 0, 6,-4,-2,-2, 1, 3,-1,-3,-3,-1,-4 ],
	      [ -1,-2,-2,-1,-3,-1,-1,-2,-2,-3,-3,-1,-2,-4, 7,-1,-1,-4,-3,-2,-2,-1,-2,-4 ],
	      [  1,-1, 1, 0,-1, 0, 0, 0,-1,-2,-2, 0,-1,-2,-1, 4, 1,-3,-2,-2, 0, 0, 0,-4 ],
	      [  0,-1, 0,-1,-1,-1,-1,-2,-2,-1,-1,-1,-1,-2,-1, 1, 5,-2,-2, 0,-1,-1, 0,-4 ],
	      [ -3,-3,-4,-4,-2,-2,-3,-2,-2,-3,-2,-3,-1, 1,-4,-3,-2,11, 2,-3,-4,-3,-2,-4 ],
	      [ -2,-2,-2,-3,-2,-1,-2,-3, 2,-1,-1,-2,-1, 3,-3,-2,-2, 2, 7,-1,-3,-2,-1,-4 ],
	      [  0,-3,-3,-3,-1,-2,-2,-3,-3, 3, 1,-2, 1,-1,-2,-2, 0,-3,-1, 4,-3,-2,-1,-4 ],
	      [ -2,-1, 3, 4,-3, 0, 1,-1, 0,-3,-4, 0,-3,-3,-2, 0,-1,-4,-3,-3, 4, 1,-1,-4 ],
	      [ -1, 0, 0, 1,-3, 3, 4,-2, 0,-3,-3, 1,-1,-3,-1, 0,-1,-3,-2,-2, 1, 4,-1,-4 ],
	      [  0,-1,-1,-1,-2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-2, 0, 0,-2,-1,-1,-1,-1,-1,-4 ],
	      [ -4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4,-4, 1 ] );



################################################################################
# %A = sgma_alignment($s, $t, \%index, \@matrix, $h, $g);
#
# Semi-global alignment with affine gap cost function.
#
# s and t are the uppercase sequences.
# index is a hash that maps each symbol in s or t to a row/column in the matrix.
# matrix is a substitution square matrix.
# The cost of a gap with k spaces is h + g*k.
#
# Return a hash with: s, t, length, score, matches, mismatches,
# sspaces, tspaces, sgaps, tgaps, sfirst, slast, tfirst, tlast

sub sgma_alignment {

  my @s = split(//,shift);
  my @t = split(//,shift);
  my $I = shift;
  my $S = shift;
  my $h = shift;
  my $g = shift;
  
  my $n = @s;
  my $m = @t;

  my ($i, $j);

  my $MINF = -(~0>>1)-1;
  
  my @A = ();
  my @B = ();
  my @C = ();
 
  for ($i=0; $i<=$n; $i++) {
    $A[$i] = [ () ];
    $B[$i] = [ () ];
    $C[$i] = [ () ];
  }

  # Fill:
  for ($i=1; $i<$n+1; $i++) {
    $A[$i][0] = $MINF;
    $B[$i][0] = $MINF;
    $C[$i][0] = 0;  # h + g*i;
  }

  for ($j=1; $j<$m+1; $j++) {
    $A[0][$j] = $MINF;
    $B[0][$j] = 0; # h + g*j;
    $C[0][$j] = $MINF;
  }

  $A[0][0] = 0;
  $B[0][0] = $MINF;
  $C[0][0] = $MINF;

  for ($i=1; $i<$n+1; $i++) {
    for ($j=1; $j<$m+1; $j++) {
      $A[$i][$j] = $S->[$I->{$s[$i-1]}][$I->{$t[$j-1]}] +
	           max3($A[$i-1][$j-1], $B[$i-1][$j-1], $C[$i-1][$j-1]);
      $B[$i][$j] = max3($h+$g+$A[$i][$j-1], $g+$B[$i][$j-1], $h+$g+$C[$i][$j-1]);
      $C[$i][$j] = max3($h+$g+$A[$i-1][$j], $h+$g+$B[$i-1][$j], $g+$C[$i-1][$j]);
    }
  }

  my $max = $MINF;
  my ($M, $maxi, $maxj);
  
  for ($i=0; $i<=$n; $i++) {
    if ($A[$i][$m] > $max) { $maxi = $i; $maxj = $m; $max = $A[$i][$m]; $M = \@A; }
    if ($B[$i][$m] > $max) { $maxi = $i; $maxj = $m; $max = $B[$i][$m]; $M = \@B; }
  }

  for ($j=0; $j<=$m; $j++) {
    if ($A[$n][$j] > $max) { $maxi = $n; $maxj = $j; $max = $A[$n][$j]; $M = \@A; }
    if ($C[$n][$j] > $max) { $maxi = $n; $maxj = $j; $max = $C[$n][$j]; $M = \@C; }
  }
  
  # Score and alignment:
  my %L = ();
  $L{score} = $M->[$maxi][$maxj];
  $L{matches} = 0;
  $L{mismatches} = 0;
  $L{sspaces} = 0;
  $L{tspaces} = 0;
  $L{sgaps} = 0;
  $L{tgaps} = 0;
  
  my $x = '';
  my $y = '';
  
  # Right tail:
  $L{slast} = $n-1;
  $L{tlast} = $m-1;

  if ($maxj < $m) {
    $L{sgaps}++;
    $L{tlast} = $maxj-1;
  }
  for ($j=$m; $j>$maxj; $j--) {
    $x = '-' . $x;
    $y = $t[$j-1] . $y;
  }
  
  if ($maxi < $n) {
    $L{tgaps}++;
    $L{slast} = $maxi-1;
  }
  for ($i=$n; $i>$maxi; $i--) {
    $x = $s[$i-1] . $x;
    $y = '-' . $y;
  }
  
  while ($i>0 && $j>0) {

    if ($M == \@A) {
       my $k = $S->[$I->{$s[$i-1]}][$I->{$t[$j-1]}];
      
      if ($A[$i][$j] == $A[$i-1][$j-1] + $k) {
        ;
      }
      elsif ($A[$i][$j] == $B[$i-1][$j-1] + $k) {
        $M = \@B;
      }
      else { # if (A[$i][$j] == C[$i-1][$j-1] + $S->[$I->{$s[$i-1]}][$I->{$t[$j-1]}])
        $M = \@C;
      }
      
      $x = $s[$i-1] . $x;
      $y = $t[$j-1] . $y;
      if ($s[$i-1] ne $t[$j-1]) {
        $L{mismatches}++;
      }
      else {
        $L{matches}++;
      }
      $i--;
      $j--;
    }

    elsif ($M == \@B) {
      if ($B[$i][$j] == $h+$g+$A[$i][$j-1]) {
        $M = \@A;
        $L{sgaps}++;
      }
      elsif ($B[$i][$j] == $h+$g+$C[$i][$j-1]) {
        $M = \@C;
        $L{sgaps}++;
      }

      $x = '-' . $x;
      $y = $t[$j-1] . $y;
      $j--;
      $L{sspaces}++;
    }

    else { # M == C
      if ($C[$i][$j] == $h+$g+$A[$i-1][$j]) {
        $M = \@A;
        $L{tgaps}++;
      }
      if ($C[$i][$j] == $h+$g+$B[$i-1][$j]) {
        $M = \@B;
        $L{tgaps}++;
      }

      $x = $s[$i-1] . $x;
      $y = '-' . $y;
      $i--;
      $L{tspaces}++;
    }
  }

  # Left tail:
  $L{sfirst} = 0;
  $L{tfirst} = 0;

  if ($i>0) {
    $L{tgaps}++;
    $L{sfirst} = $i;
    
    while ($i>0) {
      $x = $s[$i-1] . $x;
      $y = '-' . $y;
      $i--;
    }
  }

  if ($j>0) {
    $L{sgaps}++;
    $L{tfirst} = $j;

    while ($j>0) {
      $x = '-' . $x;
      $y = $t[$j-1] . $y;
      $j--;
    }
  }

  $L{length} = length($x);
  $L{s} = $x;
  $L{t} = $y;

  return %L;
}



sub max3 {

  my $x = shift;
  my $y = shift;
  my $z = shift;
  
  return ($x > $y ? ($x > $z ? $x : $z) : ($y > $z ? $y : $z));
}


sub abend {

  my $m = shift;
  ($m) and print "Error: $m\n";
  print "finished.\n";
  exit(1);
}

  

################################################################################
# array-of-strings uprot_download_synonyms($accession)
#
# Try to download a list of synonyms from UniProt.  On success it
# returns an array of strings, on failure it returns an empty array.
#
# This function became ackward after www.uniprot.org/uploadlists
# stopped working because the new service returns a full json, not a
# neat table as before.

sub uprot_download_synonyms {

  my $acc = shift;
      
  my $url = 'https://rest.uniprot.org/idmapping/run/';
  my $params = { from => 'UniProtKB_AC-ID', to => 'UniRef100', ids => "$acc" };
  my $agent = LWP::UserAgent->new(agent => 'libwww-perl gpt@ic.unicamp.br');
  push(@{$agent->requests_redirectable},'POST');
  my $response = $agent->post($url,$params);

  my $id = $response->content;

  if ($id =~ /\{\"jobId\"\:\"(\w+)\"\}/) {
    $id = $1;
  }
  else {
    return ();
  }

  usleep(250000);

  $url = "https://rest.uniprot.org/idmapping/status/$id";
  $agent = LWP::UserAgent->new(agent => 'libwww-perl gpt@ic.unicamp.br');
  push(@{$agent->requests_redirectable},'GET');
  $response = $agent->get($url);

  while ($response->content =~ /\{\"jobStatus\":\"RUNNING\"\}/) {
    usleep(250000);
    $response = $agent->get($response->base);
  }

  if ($response->content =~ /\"accessions\"\:\[([^\]]*)\]/) {
    my @accs = split(/,/,$1);
    for (my $i=0; $i<@accs; $i++) {
      $accs[$i] =~ s/\"//g;
    }
    return @accs;
  }

  return ();
}



################################################################################
# string uprot_download_xml($accession,$directory)
#
# Download a UniProt entry by accession as xml.
# If it fails, try to download a synonym entry.
# If it fails again, create a placeholder file.
#
# On success, if the entry itself was downloaded then it saves the
# entry as $directory/$accession.xml and returns $accession.
# If a synonym was downloaded, it saves the entry as
# $directory/$accession-aka.xml and also as $directory/X.xml, where X
# is the synonym accession, and returns X.
#
# On failure, it creates an empty file $directory/$accession-fail.xml
# and returns 'fail'.
#
# The directory defaults to the cwd. It dies on file operations failure.

sub uprot_download_xml {

  my $acc = shift;
  my $dir = shift;

  !defined($dir) && ($dir = '.');
  
  my $unif = "$dir/$acc.xml";
  my $akaf = "$dir/$acc-aka.xml";
  my $failf = "$dir/$acc-fail.xml";

  my $retry = 0;
  
  while (1) {
    # Try downloading xml:
    my $url = "https://www.ebi.ac.uk/proteins/api/proteins/$acc";
    my $agent = LWP::UserAgent->new(agent => 'libwww-perl gpt@ic.unicamp.br');
    my $response = $agent->get("$url", 'Accept'=>'application/xml');
    usleep(10000);

    while (my $wait = $response->header('Retry-After')) {
      sleep($wait);
      $response = $agent->get($response->base);
    }
  
    if ($response->is_success) {
      open(my $fh,">",$unif) || abend("Unable to write to $unif.\n");
      print $fh $response->content."\n";
      close($fh);
      
      if ($retry) {
	copy($unif, $akaf) or abend(": $!");
      }

      return $acc;
    }
    else {
      if (!$retry) {
	# Try getting a synonym acc. On success, retry a download. On failure, give up:    
	my @syn = uprot_download_synonyms($acc);

	my $i = 0;
	while ($i < @syn && $syn[0] eq $acc) {
	  $i++;
	}
	
	if ($i < @syn) {
	  $acc = $syn[$i];
	  $unif = "$dir/$acc.xml";
	  $retry = 1;
	  next;
	}
      }

      # Failed in getting a synonym or downloading using a synonym acc:
      touch($failf);
      return 'fail';
    }
  }
}
