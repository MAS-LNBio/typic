#!/usr/bin/perl -w 
# This file is part of Typic version 6.
# 2022 Guilherme P. Telles.

# Heavily based on the example in C.3 of Mastering Perl/Tk,
# S. Lidie and N. Walsh, 2002.

package Tk::ExCmd;

use Tk;
use IO::Handle;
use Tk::widgets qw/LabEntry ROText/;
use Tk::NoteBook;
use base qw/Tk::Frame/;

use warnings;

Construct Tk::Widget 'ExCmd';



sub Populate {

  my ($self, $args) = @_;
  #print $self->id(), " ", $self->name(), " ", $self->pathname($self->id()), "\n";
  
  my $thecommand = %$args{-command};
  delete $args->{-command};
  
  $self->SUPER::Populate($args);

  my $fb = $self->parent()->Frame();
  my $run = $fb->Button(-text => 'Run');
  my $quit = $fb->Button(-text => 'Quit', -command => sub { $self->_getout(); });

  $run->pack(-side => 'left',-padx => 10,-pady => 5);
  $quit->pack(-side => 'right',-padx => 10,-pady => 5);
  $fb->place(-relx => 0.5,-anchor=>'center',-rely => 0.85);

  $self->OnDestroy([ $self => '_getout' ]);
  $self->{-finish} = 0;
  $self->{-command} = $thecommand;

  my $sw = $self->Toplevel(-title => "typic execution results");
  $sw->withdraw( );
  my $l = $sw->Label(-text => 'Execution:',-anchor => 'w');
  my $t = $sw->Scrolled('ROText',-scrollbars => 'osoe',-wrap => 'none',-height => 10);
  my $b = $sw->Button(-text => "ok", -command => sub { $sw->withdraw(); });

  $l->pack(-expand => 1,-fill => 'both');
  $t->pack(-expand => 1,-fill => 'x',-pady => 5);
  $b->pack(-side => 'bottom',-pady => 10);

  $self->Advertise('run' => $run);
  $self->Advertise('exec' => $sw);
  $self->Advertise('text' => $t);
  
  $self->_reset_run_button();
} 



sub _flash_run {

  my ($self, $option, $val1, $val2, $interval) = @_;

  if ($self->{-finish} == 0) {
    $self->Subwidget('run')->configure($option => $val1);
    $self->idletasks;
    $self->after($interval, [ \&_flash_run, $self, $option, $val2, $val1, $interval ]);
  }
}



sub _read_stdout {

  my ($self) = @_;
  
  if ($self->{-finish}) {
    $self->kill();
  } 
  else {
    my $h = $self->{-handle};
    if (sysread $h, $_, 4096) {
      my $t = $self->Subwidget('text');
      $t->insert('end', $_);
      $t->yview('end');
    } 
    else {
      $self->{-finish} = 1;
    }
  }
} 



sub _reset_run_button {

  my ($self) = @_;

  my $run = $self->Subwidget('run');
  my $run_bg = ($run->configure(-background))[3];
  $run->configure(
    -text       => 'Run',
    -relief     => 'raised',
    -background => $run_bg,
    -state      => 'normal',
    -command    => [ sub { my ($self) = @_;
			  $self->{-finish} = 0;
			  $self->Subwidget('run')->configure(
			    -text   => 'Working...',
			    -relief => 'sunken',
			    -state  => 'disabled'
			    );
			  $self->execute(); },
		    $self ],
    );
} 



sub _getout {

  my ($self,$args) = @_;

  defined($self->{-pid}) and kill('TERM',$self->{-pid});
  exit(0);
}



sub execute {

  my ($self) = @_;
  
  my $h = IO::Handle->new;
  (!defined $h) and die("IO::Handle->new: failed $!\n");
  $h->autoflush(1);

  $self->{-handle} = $h;
  
  $self->{-pid} = open($h, $self->{-command}->() . ' 2>&1 |');
  
  if (!defined $self->{-pid}) {
    $self->Subwidget('text')->insert('end', $self->{-command} . ": $!\n");
    $self->kill();
    return;
  }
  
  $self->fileevent($h, 'readable' => [ \&_read_stdout, $self ]);
  
  my $run = $self->Subwidget('run');
  $run->configure(
    -text    => 'Cancel',
    -relief  => 'raised',
    -state   => 'normal',
    -command => [ \&kill, $self ],
    );

  my $sw = $self->Subwidget('exec');
  $sw->deiconify();
  $sw->raise();
  
  my $text = $self->Subwidget('text');
  $text->delete("1.0", 'end');
  
  my $run_bg = ($run->configure(-background))[3];
  $self->_flash_run('-background', $run_bg, 'darkgray', 500);
} 



sub kill {

  my ($self) = @_;

  $self->{-finish} = 1;
  !defined($self->{-handle}) and return;

  defined($self->{-pid}) and kill('TERM',$self->{-pid});

  $self->fileevent($self->{-handle}, 'readable' => ''); 
  close($self->{-handle});

  $self->_reset_run_button();
} 
