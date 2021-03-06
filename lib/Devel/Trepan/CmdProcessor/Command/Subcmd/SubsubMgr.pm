# -*- coding: utf-8 -*-
# Copyright (C) 2011, 2013 Rocky Bernstein <rocky@cpan.org>

use warnings; no warnings 'redefine';

use rlib '../../../../..';
package Devel::Trepan::CmdProcessor::Command::SubsubcmdMgr;
no warnings 'redefine';

use File::Basename;
use File::Spec;

## FIXME core is not exporting properly.
use Devel::Trepan::CmdProcessor::Command::Subcmd::Core;

use strict;
## FIXME: @SUBCMD_ISA and @SUBCMD_VARS should come from Core.
use vars qw(@ISA @EXPORT $HELP $NAME @ALIASES
            @SUBCMD_ISA @SUBCMD_VARS);
@ISA = qw(Devel::Trepan::CmdProcessor::Command::Subcmd);
use vars @SUBCMD_VARS;  # Value inherited from parent

use constant MIN_ARGS   => 0;
use constant MAX_ARGS   => undef;
use constant NEED_STACK => 0;

#   attr_accessor :subcmds   # Trepan::Subcmd
#   attr_reader   :name      # Name of command
#   attr_reader   :last_args # Last arguments seen

# Initialize show subcommands. Note: instance variable name
# has to be setcmds ('set' + 'cmds') for subcommand completion
# to work.
sub new($$$)
{
    my ($class, $parent, $name) = @_;
    my @prefix = split('::', $class);
    shift @prefix; shift @prefix; shift @prefix; shift @prefix;
    my $self = {
        subcmds => {},
        name    => $name,
        proc    => $parent->{proc},
        parent  => $parent,
        prefix  => \@prefix,
        cmd_str => join(' ', map {lc $_} @prefix)
    };
    # Initialization
    my $parent_name = ucfirst $parent->{name};
    my $base_prefix="Devel::Trepan::CmdProcessor::Command::$parent_name";
    my $excluded_cmd_vars = {'$HELP' => 1,
                             '$NAME'=>2};
    for my $field (@Devel::Trepan::CmdProcessor::Command::Subcmd::SUBCMD_VARS) {
        next if exists $excluded_cmd_vars->{$field} &&
            $excluded_cmd_vars->{$field} == 2;
        my $sigil = substr($field, 0, 1);
        my $new_field = index('$@', $sigil) >= 0 ? substr($field, 1) : $field;
        if ($sigil eq '$') {
            my $lc_field = lc $new_field;
            $self->{$lc_field} = eval "\$${class}::${new_field}";
        }
    }
    my @ary = eval "${class}::ALIASES()";
    $self->{aliases} = @ary ? [@ary] : [];
    no strict 'refs';
    my $short_help = eval "${class}::SHORT_HELP()";
    $self->{short_help} = $short_help if $short_help;
    bless $self, $class;
    $self->load_debugger_subsubcommands($parent);
    $self;
}

# Create an instance of each of the debugger subcommands. Commands are
# found by importing files in the directory 'name' + '_Subcmd'. Some
# files are excluded via an array set in initialize.  For each of the
# remaining files, we 'require' them and scan for class names inside
# those files and for each class name, we will create an instance of
# that class. The set of TrepanCommand class instances form set of
# possible debugger commands.
sub load_debugger_subsubcommands($$)
{
    my ($self,$parent) = @_;
    $self->{cmd_names}     = ();
    $self->{subcmd_names}  = ();
    $self->{cmd_basenames} = ();
    my $cmd_dir = dirname(__FILE__);
    my $parent_name = ucfirst $self->{name};
    my $cmd_name    = $self->{prefix}[0];
    my @path = ($cmd_dir, '..', "${cmd_name}_Subcmd",
                $parent_name . '_Subcmd');
    my $subcmd_dir = File::Spec->catfile(@path);
    if (-d $subcmd_dir) {
        my @files = glob(File::Spec->catfile($subcmd_dir, '*.pm'));
        for my $pm (@files) {
            my $basename = basename($pm, '.pm');
            my $item = sprintf("%s::%s::%s",
                               ucfirst($cmd_name),
                               ucfirst($parent_name),
                               ucfirst($basename));
            if (-d File::Spec->catfile(dirname($pm), $basename . '_Subcmd')) {
                push @{$self->{subcmd_names}}, $item;
            } else {
                push @{$self->{cmd_names}}, $item;
                push @{$self->{cmd_basenames}}, $basename;
            }
	    my $rc=0;
            eval{require "$pm"; $rc=1};
            if ($rc eq 'Skip me!') {
                ;
            } elsif ($rc) {
                $self->setup_subsubcommand($parent, $item, $basename);
            } else {
                my $proc = $parent->{proc};
                $proc->errmsg("Trouble reading ${pm}:");
                $proc->errmsg($@);
            }
        }
    }
}

sub setup_subsubcommand($$$$)
{
    my ($self, $parent, $cmd_prefix, $name) = @_;
    my $parent_name = $parent->{name};
    my $cmd_obj;
    my $cmd_name = lc $name;
    my $new_cmd = "\$cmd_obj=Devel::Trepan::CmdProcessor::Command::" .
        "${cmd_prefix}->new(\$self, '$cmd_name'); 1";
    if (eval $new_cmd) {
        # Add to hash of commands, and list of subcmds
        $self->{subcmds}{$cmd_name} = $cmd_obj;
        $self->add($cmd_obj, $cmd_name);
    } else {
        my $proc = $parent->{proc};
        $proc->errmsg("Error instantiating ${cmd_prefix}");
        $proc->errmsg($@);
    }

}

# Find subcmd in self->subcmds
sub lookup($$;$)
{
    my ($self, $subcmd_prefix, $use_regexp) = @_;
    $use_regexp = 0 if scalar @_ < 3;
    my $compare;
    if (!$self->{proc}{settings}{abbrev}) {
        $compare = sub($) { my $name = shift; $name eq $subcmd_prefix};
    } elsif ($use_regexp) {
        $compare = sub($) { my $name = shift; $name =~ /^${subcmd_prefix}/};
    } else {
        $compare = sub($) {
            my $name = shift; 0 == index($name, $subcmd_prefix)
        };
    }
    my @candidates = ();
    while (my ($subcmd_name, $subcmd) = each %{$self->{subcmds}}) {
        if ($compare->($subcmd_name)) {
            push @candidates, $subcmd;
        }

    }
    if (scalar @candidates == 1) {
        return $candidates[0];
    }
    return undef;
}

# Show short help for a subcommand.
sub short_help($$$;$)
{
    my ($self, $subcmd_cb, $subcmd_name, $label) = @_;
    $label = 0 unless defined $label;
    my $entry = $self->lookup($subcmd_name);
    if ($entry) {
        my $prefix = '';
        $prefix = $entry->{name} if $label;
        if (exist $entry->{short_help}) {
            $prefix .= ' -- ' if $prefix;
            $self->{proc}->msg($prefix . $entry->{short_help});
        }
    } else {
        $self->{proc}->undefined_subcmd($self->{cmd_str}, $subcmd_name);
    }
}

# Add subcmd to the available subcommands for this object.
# It will have the supplied docstring, and subcmd_cb will be called
# when we want to run the command. min_len is the minimum length
# allowed to abbreviate the command. in_list indicates with the
# show command will be run when giving a list of all sub commands
# of this object. Some commands have long output like "show commands"
# so we might not want to show that.
sub add($$;$)
{
    my ($self, $subcmd_cb, $subcmd_name) = @_;
    $subcmd_name ||= $subcmd_cb->{name};

    # We keep a list of subcommands to assist command completion
    push @{$self->{cmdlist}}, $subcmd_name;
}

# FIXME: remove this completely.
# help for subcommands
# Note: format of help is compatible with ddd.
sub help($$)
{
    my ($self, $args) = @_;
    if (scalar @$args <= 3) {
        # "help cmd subcmd". Give the general help for the command part.
        return $self->{help};
    }

    my $subcmd_name = $args->[3];
    my @help_text = ();
    my $subcmds_ref = $self->{subcmds};
    my @subcmds     = $self->list();

    if ('*' eq $subcmd_name) {
        @help_text = (sprintf("B<List of subcommands for command I<%s>:>",
                             $self->{cmd_str}));

        my $subcmds = $self->{parent}->columnize_commands(\@subcmds);
        chomp $subcmds;
        push @help_text, $subcmds;
	# Double carriage return because of perlpod
        return join("\n\n", @help_text);
    }

    # "help cmd subcmd". Give help specific for that subcommand.
    my $cmd = $self->lookup($subcmd_name, 0);
    if (defined $cmd) {
        if ($cmd->can("help")) {
            return $cmd->help($args);
        } else {
            return $cmd->{help};
        }
    } else {
        my $proc = $self->{proc};
        my @matches = sort(grep /^${subcmd_name}/, @subcmds);
        my $name = $self->{cmd_str};
	print "HI!\n";
        if (0 == scalar @matches) {
            $proc->errmsg("No ${name} subcommands found matching /^{$subcmd_name}/. Try \"help\" $name.");
            return undef;
        } elsif (1 == scalar @matches) {
            $args->[-1] = $matches[0];
            $self->help($args);
        } else {
            @help_text = ("Subcommands of \"$name\" matching /^${subcmd_name}/:");
            my @sort_matches = sort @matches;
            push @help_text, $self->{parent}{cmd}->columnize_commands(\@sort_matches);
            return @help_text;
        }
    }
}

sub list($) {
    my $self = shift;
    sort keys %{$self->{subcmds}};
}

#   # Return an Array of subcommands that can start with +arg+. If none
#   # found we just return +arg+.
#   # FIXME: Not used any more?
#   sub complete(prefix)
#     Trepan::Complete.complete_token(@subcmds.subcmds.keys, prefix)
#   }

sub complete_token_with_next($)
{
    my ($self, $prefix) = @_;
    my $subcmds = $self->{subcmds};
    return Devel::Trepan::Complete::complete_token_with_next($subcmds,
                                                             $prefix);
  }

sub run($$)
{
    my ($self, $args) = @_;
    $self->{last_args} = $args;
    # require Enbugger; Enbugger->stop;
    my $args_len = scalar @$args;
    if ($args_len < 3 || $args_len == 3 && $args->[-1] eq '*') {
        $self->{proc}->summary_list($self->{cmd_str}, $self->{subcmds});
        return 0;
    }

    my $subcmd_prefix = $args->[2];
    # We were given: cmd subcmd  subcmd ...
    # Run that.
    my $subcmd = $self->lookup($subcmd_prefix);
    if ($subcmd) {
        if ($self->{proc}->ok_for_running($subcmd, $subcmd->{cmd_str},
                                          $args_len-3)) {
            $subcmd->run($args);
        }
    } else {
        $self->{proc}->undefined_subcmd($self->{name}, $subcmd_prefix);
    }
}

unless(caller) {
    # Demo it.
    require Devel::Trepan::CmdProcessor;
    require Devel::Trepan::CmdProcessor::Command::Set;
    my $proc = Devel::Trepan::CmdProcessor->new(undef, 'bogus');
    my $set_cmd = Devel::Trepan::CmdProcessor::Command::Set->new($proc, 'Set');
    my $mgr = __PACKAGE__->new($proc, $set_cmd);
    print $mgr, "\n";
    print join(', ', %{$mgr->{subcmds}}), "\n";
    $set_cmd->lookup('a');
}

1;
