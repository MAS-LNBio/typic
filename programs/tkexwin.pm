#!/usr/bin/perl -w 
# This file is part of Typic version 6.
# 2022 Guilherme P. Telles.

# After the example in C.3 of S. Lidie and N. Walsh, Mastering Perl/Tk, 2002.
# Execute typic.pl in blocking mode as Windows don't support fileevent.
# Maybe some other solution, like threads, may enable non-blocking
# execution, but I will not try do find it.

package ExCmd;

use Tk;
use Tk::widgets qw/LabEntry ROText/;
use Tk::NoteBook;
use base qw/Tk::Frame/;

use warnings;

Construct Tk::Widget 'ExCmd';



sub Populate {

  my ($self, $args) = @_;

  my $thecommand = %$args{-command};
  delete $args->{-command};

  $self->SUPER::Populate($args);

  my $p = $self->parent();
  my $fb = $p->Frame();
  my $run = $fb->Button(-text => 'Run');
  my $quit = $fb->Button(-text => "Exit", -command => sub { $self->_getout(); });

  $run->pack(-side => 'left',-padx => 10,-pady => 5);
  $quit->pack(-side => 'right',-padx => 10,-pady => 5);
  $fb->place(-relx => 0.5,-anchor=>'center',-rely => 0.85);
  
  $self->Advertise('run' => $run);
  $self->Advertise('quit' => $quit);

  $self->OnDestroy([ $self => '_getout' ]);
  $self->{-command} = $thecommand;
  
  my $run_bg = ($run->configure(-background))[3];
  $run->configure(
    -text       => 'Run',
    -relief     => 'raised',
    -background => $run_bg,
    -state      => 'normal',
    -command    => [ sub { my ($self) = @_; $self->execute(); }, $self ],
    );
} 



sub _getout {

  my ($self,$args) = @_;

  defined($self->{-pid}) and kill('TERM',$self->{-pid});
  exit(0);
}



sub _reset_buttons {

  my ($self) = @_;
  
  my $run = $self->Subwidget('run');
				     
  $run->configure(
    -text    => 'Run',
    -relief  => 'raised',
    -state   => 'normal',
    );
  
  my $quit = $self->Subwidget('quit');
  $quit->configure(
    -text    => 'Exit',
    -relief  => 'raised',
    -state   => 'normal',
    );
  
  $self->idletasks;
}



sub execute {

  my ($self) = @_;

  my $run = $self->Subwidget('run');
  $run->configure(
    -text    => 'Running...',
    -relief  => 'sunken',
    -state   => 'normal',
    );

  my $quit = $self->Subwidget('quit');
  $quit->configure(
    -text    => 'Exit',
    -relief  => 'raised',
    -state   => 'disabled',
    );

  $self->idletasks;

  $self->{-pid} = open(my $h, $self->{-command}->() . " 1>typic-$$.tmp 2>&1 |");
  
  if (!defined $self->{-pid}) {
    $self->Subwidget('text')->insert('end', $self->{-command} . ": $!\n");
    $self->kill();
    return;
  }
  
  waitpid($self->{-pid},0);

  my $sw = $self->Toplevel(-title => "typic execution results");
  my $l = $sw->Label(-text => 'Execution:',-anchor => 'w')->pack(-expand => 1,-fill => 'both');
  my $t = $sw->Scrolled('ROText',-scrollbars => 'osoe',-wrap => 'none',-height => 10);
  $t->pack(-expand => 1,-fill => 'x',-pady => 5);

  $b = $sw->Button(-text => "ok",
		   -command => sub { $sw->withdraw(); $self->_reset_buttons(); });
  $b->pack(-side => 'bottom',-pady => 10);

  $t->delete("1.0", 'end');
  open(my $fh,"<","typic-$$.tmp");

  while (<$fh>) {
    $t->insert('end', $_);
  }
  $t->yview('begin');

  close($fh);
  unlink("typic-$$.tmp");
} 



sub kill {

  my ($self) = @_;
  defined($self->{-pid}) and kill('TERM',$self->{-pid});
} 



1;
