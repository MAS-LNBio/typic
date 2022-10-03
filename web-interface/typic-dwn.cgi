#!/usr/bin/perl -w
# A cgi to deliver the results of typic.
# This file is part of Typic version 6.
# 2022 Guilherme P. Telles.

use CGI qw(:standard -no_xhtml);
use CGI::Carp 'fatalsToBrowser';
$CGI::LIST_CONTEXT_WARN = 0; 
$CGI::DISABLE_UPLOADS = 1;

use Encode;
use Fcntl ':flock';
use Time::Local;

$doned = 'finished';

$id = param('id');
$file = "$doned/$id.zip";
($id && -f $file) or abort("You must provide a valid identifier.");

print "Content-Type:application/x-download\nContent-Disposition:attachment;filename=$file\n\n";  
open($FILE,'<',$file) or abort("typic-dwn open $file $!");
binmode $FILE;
while (<$FILE>) {
  print $_;
}
close($FILE);

exit(0);



################################################################################
# abort($message)
#
# Print message, write to log and exit.

sub abort {

  my $mess = shift;

  print header();
  print start_html(-title=>'typic', 
		   -style=>{-src=>['typic.css']},
		   -head=>[Link({-rel=>'icon',-type=>'image/png',-href=>'icon.png'})]);

  print '<script type="text/javascript" src="typic.js"></script>';
  print '<div class="f85">';
  print '<h1>typic &alpha;</h1>';
  logger($mess);
  print "<p>$mess<hr></form></div></div></body></html>";

  exit(1);
}



################################################################################
# string format_epoch($seconds)
#
# Format seconds from epoch as aaaa/mm/dd hh:mm:ss.

sub format_epoch {

  my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(shift);

  return sprintf("%04.0f/%02.0f/%02.0f %02.0f:%02.0f:%02.0f",
                 $year+1900,$mon+1,$mday,$hour,$min,$sec);
}



################################################################################
# logger($message)
#
# Add an entry to typic.log.

sub logger {

  my $mess = shift;

  my $LOG;
  if (!open($LOG,'>>','typic.log')) {
    print "<p>Open typic.log: $!. <hr><a href=\"typic.cgi\">typic</a></div></body></html>";
    exit(1);
  }
  if (!flock($LOG,LOCK_EX)) {
    print "<p>Lock typic.log: $!. <hr><a href=\"typic.cgi\">typic</a></div></body></html>";
    exit(1);
  }
  seek($LOG,0,2);

  printf $LOG "%s %s port %s %s\n",
              format_epoch(time),$ENV{REMOTE_ADDR},$ENV{REMOTE_PORT},encode("ASCII",$mess);

  flock($LOG,LOCK_UN);
  close($LOG);
}
