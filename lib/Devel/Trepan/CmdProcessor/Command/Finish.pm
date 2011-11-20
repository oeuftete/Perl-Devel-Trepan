# -*- coding: utf-8 -*-
# Copyright (C) 2011 Rocky Bernstein <rocky@cpan.org>
use warnings; no warnings 'redefine';

use rlib '../../../..';

# rlib '../running'
# rlib '../../app/breakpoint' # FIXME: possibly temporary

package Devel::Trepan::CmdProcessor::Command::Finish;

use if !defined @ISA, Devel::Trepan::CmdProcessor::Command ;
use vars qw(@ISA);
unless (defined @ISA) {
    eval "use constant ALIASES    => qw(fin)";
    eval "use constant CATEGORY   => 'running'";
    eval "use constant SHORT_HELP => 'Step to end of current method (step out)'";
}
use strict;
@ISA = @CMD_ISA;
use vars @CMD_VARS;  # Value inherited from parent

our $NAME = set_name();
our $HELP = <<"HELP";
${NAME} [LEVELS]

Continue execution until the program is about to leaving the current
function or switch context via yielding or ending a block which was
yield to. Sometimes this is called 'step out'.

When LEVELS is specified, that many frame levels need to be
popped. The default is 1.  Note that 'yield' and exceptions raised my
reduce the number of stack frames. Also, if a thread is switched, we
stop ignoring levels.

See the break command if you want to stop at a particular point in a
program. In general, '${NAME}', 'step' and 'next' may slow a program down
while 'break' will have less overhead.

HELP

local $NEED_RUNNING = 1;
local $MAX_ARGS     = 1;  # Need at most this many

# This method runs the command
sub run($$) {
    my ($self, $args) = @_;
    my $proc = $self->{proc};
    
    my ($opts, $level_count) = ({}, 0);
    if (scalar @$args != 1) {
	# Form is not "finish" which means "finish 0"
	my $count_str = $args->[1];
	$opts = {
	    msg_on_error => 
		"The '${NAME}' command argument must eval to an integer. Got: ${count_str}",
		min_value => 1
	};
	my $count = $proc->get_an_int($count_str, $opts);
	return unless defined $count;
	$level_count = $count;
    }
    $proc->finish($level_count);
}

unless (caller) {
  # require_relative '../mock'
  # dbgr, cmd = MockDebugger::setup
  # p cmd.run([cmd.name])
}

1;
