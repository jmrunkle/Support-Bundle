#!/usr/bin/perl

################################################################################
# AnalyzeSCD.pl - analyzes the stateCaptureData for disk array troubleshooting
# RCS Keywords:
#     $Date: 2013-05-02 (Thr, 2 May 2013) $
#   $Source: /home/AnalyzeSCD.pl $
#   $Author: jr186037 $
# $Revision: 1.0.0.0 $
################################################################################

package AnalyzeSCD;

use strict;
use warnings;

#-------------------------------------------------------------------------------

our $VERSION = '1.0.0.0';       # version number
my $DEBUG = 1;                  # for debug mode
my $nohup = 0;                  # for non-interactive mode

#-------------------------------------------------------------------------------

# print_version - prints the version
sub print_version {
    print "\nState Capture Analyzer - Version $VERSION\n\n";
    return;
}

# print_usage_info - prints the usage information (including version)
sub print_usage_info {
    print_version;
    print "\n  Performs basic analysis of state capture data.\n\n";
    print 'Usage: perl AnalyzeSCD.pl [-n|-v|-?|stateCaptureData.txt]';
    print "\n    -n, --nohup      Run without user input and print to STDOUT";
    print "\n    -v, --version    Print version number and exit";
    print "\n    -h, --help, -?   Print usage information and exit\n\n";
    return;
}

#-------------------------------------------------------------------------------

if ($DEBUG) { @ARGV = ('-n', 'stateCaptureData.txt'); }
my $arg = $ARGV[0];    # $arg = command line argument

# if the argument is "-v" or "--version" print version
if (
    ( !$arg ) || (
        $arg =~ m{^      # at start of string
              (-h|       # match '-h'
              -[?]|      # or '-?'
              --help)    # or '--help'
              $          # end of string
              }xsim
    )
  )
{
    print_usage_info;
    exit 0;
# if the argument is "-h" or "-?" or "--help" print usage information
} elsif (
    $arg =~ m{^           # at start of string
            (-v|          # match '-v'
            --version)    # or '--version'
            $             # end of string
            }xsim
  )
{
    print_version;
    exit 0;
} elsif ($arg =~ m{^            # at start of string
                   (-n|         # match '-n'
                   --nohup)     # or '--nohup'
                   $            # end of string
                   }xsim)
{
    $nohup = 1;
    $arg = $ARGV[1];
}

#-------------------------------------------------------------------------------

# read the MEL lines, format into appropriate data structures as necessary
# format into errors array
print "\nReading stateCaptureData... ";
open(SCD, "<", "$arg") or die("Could not open file: $arg");
print "Done.\nBuilding data structures... ";

# @all_errors holds all the errors in the array regardless of type
my @all_errors = ();

# @current_error holds the current error information in the following format:
# [ 1. Date, 2. Description, 3. Type, 4. Location ]
my @current_error = ();

# %drive_errors holds a hash of all the drive errors in the following format:
# $drive_errors{"location"}->{"description"}->('time'=>time,'count'=>count)
my %drive_errors = ();

# @controller_timeline holds an array summary of major controller events.
# Format is: [ 1. Date, 2. Description, 3. Location ]
my @controller_timeline = ();

# @urs_timeline holds an array summary of URS events.
# Format is: [ 1. Date, 2. Description, 3. Location ]
my @urs_timeline = ();

# $first is a constant which indicates if this is the first pass
my $first = 1;

while(<SCD>) {
    chomp;
    # Date indicates a new error
    if ($_ =~ m/^Date/xsim)
    {
        # if not the first error
        if (!$first)
        {
            # extract some useful bindings for simplicity
            my ($time, $desc, $type, $loca) = @current_error;
            # if this is a drive component
            if ($type =~ m/Drive/xsm)
            {
                $loca = substr $loca, 20;    # remove 'Component location : '
                # if this error has been seen before
                if ($drive_errors{$loca} &&
                    $drive_errors{$loca}->{$desc})
                {
                    $drive_errors{$loca}->{$desc}->{'count'} += 1;
                # or if it has not been seen before
                } else
                {
                    # set time of most recent occurence
                    $drive_errors{$loca}->{$desc}->{'time'} = $time;
                    # set counts of this specific error to 1
                    $drive_errors{$loca}->{$desc}->{'count'} = 1;
                }
            }
            # if this is a special controller error -> controller timeline
            if ($type =~ m/Controller/xsm &&
                $desc =~ m{(start-of-day|    # start of day events
                            parity|          # memory parity errors
                            persistent|      # persistent issues
                            reset)           # controller resets
                            }xsim)
            {
                push(@controller_timeline, [$time, $desc, $loca]);
            }
            # if this is a URS condition -> urs timeline
            if ($desc =~ m/Unreadable/xsm)
            {
                push(@urs_timeline, [$time, $desc, $loca]);
            }
        }
        push(@all_errors, [@current_error]);    # add error to all errors
        @current_error = ($_);                  # start new error
    # also track Description, Component type, and Component location lines
    } elsif ($_ =~ m{^
                     (Description|      # 'Description' line
                     Component)         # 'Component (type|location)'
                     }xsm)
    {
        $first = 0;                             # flag no longer first
        push(@current_error, $_);               # append element to error
    }
}
push(@all_errors, [@current_error]);            # add the last error
close(SCD);
print "Done.\n\n";

#-------------------------------------------------------------------------------

# print_urs_timeline - prints the URS summary timeline
sub print_urs_timeline
{
    print "\nURS SUMMARY:\n\n";
    if (@urs_timeline)
    {
        foreach (@urs_timeline) 
        {
            my $time = substr @$_[0], 11;
            my $desc = substr @$_[1], 30;
            my $vol = substr @$_[2], 20;
            printf("%-24s%-42s%-12s\n", $time, "URS".$desc, $vol);
        }
    } else
    {
        print "No URS events!\n"
    }
}

# print_controller_timeline - prints the controller summary timeline
sub print_controller_timeline
{
    print "\nCONTROLLER SUMMARY:\n\n";
    if (@controller_timeline)
    {
        foreach (@controller_timeline)
        {
            my $time = substr @$_[0], 11;
            my $desc = substr @$_[1], 13;
            my $loca = substr @$_[2], 20;
            my $controller = ($loca =~ m/slot [A0]/xsim ? 'Controller A': 'Controller B');
            printf("%-24s%-42s%-12s\n", $time, $desc, $controller);
        }
        print "\n";
    } else
    {
        print "No major controller events!\n";
    }
}

# print_drive_summary - prints the summary of all drive errors (it's crazy)
sub print_drive_summary
{
    print "DRIVE SUMMARY:\n\n";
    for my $tray (0 .. 8)
    {
        for my $slot (0 .. 24)
        {
            my $loca = "Tray $tray, Slot $slot";
            if ($drive_errors{$loca})
            {
                my $total_errors = 0;
                print "Drive in $loca has the following errors:\n";
                for my $desc (keys %{$drive_errors{$loca}})
                {
                    my $count = $drive_errors{$loca}->{$desc}->{'count'};
                    $total_errors += $count;
                    my $time = substr $drive_errors{$loca}->{$desc}->{'time'}, 11;
                    $desc = substr $desc, 13, 51;
                    printf("  %-5s %-51s%-20s\n", $count, $desc, $time);
                }
                print "TOTAL ERRORS: $total_errors\n";
                print '-'x79,"\n";
            }
        }
    }
}

#-------------------------------------------------------------------------------

print '-'x79,"\n";
print_urs_timeline;
print "\n",'-'x79,"\n";
print_controller_timeline;

my $input = 'yes';
if (!$nohup)
{
    print "\n",'-'x79,"\n";
    print 'Print the drive summary (y/n)? [default y]  ';
    $input = <STDIN>;
}

if ($input =~ m/^n/xsim)
{
    print "\n";
    exit 0;
}
print '-'x79,"\n";
print_drive_summary;
print "\n";

1;

__END__

#-------------------------------------------------------------------------------

=pod

=for stopwords RCS

=head1 NAME

AnalyzeSCD.pl - Analyzes stateCaptureData for disk array troubleshooting

=head1 DESCRIPTION

This program parses through the stateCaptureData checking error counts and
statistical variation so that support associates can quickly parse through
the oceans of information contained in this file.

=head1 USAGE

C<perl AnalyzeSCD.pl 

=head1 REQUIRED ARGUMENTS

Required arguments...

=head1 OPTIONS

=over 4

=item C<option 1>

FILLER

=item C<option 2>

FILLER

=item C<option 3>

FILLER

=back

=head1 DIAGNOSTICS

Diagnostics...

=head1 EXIT STATUS

Exit Status...

=head1 CONFIGURATION

Config...

=head1 DEPENDENCIES

Dependencies...

=head1 INCOMPATIBILITIES

Incompatibilities...

=head1 BUGS AND LIMITATIONS

Bugs and Limits...

=head1 AUTHOR

Jason Michael Runkle <jason.runkle@teradata.com>

=head1 LICENSE AND COPYRIGHT

None.

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
#   indent-tabs-mode: nil
#   c-indentation-style: bsd
# End:
# ex: set ts=8 sts=4 sw=4 tw=78 ft=perl expandtab shiftround :
