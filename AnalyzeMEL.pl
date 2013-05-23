#!/usr/bin/perl

################################################################################
# AnalyzeMEL.pl - analyzes a MEL for disk array troubleshooting
# RCS Keywords:
#     $Date: 2013-05-13 (Mon, 13 May 2013) $
#   $Source: /home/AnalyzeMEL.pl $
#   $Author: jr186037 $
# $Revision: 1.0.1.1 $
################################################################################

package SupportBundle::AnalyzeMEL;

use strict;
use warnings;

#-------------------------------------------------------------------------------

our $VERSION = '1.0.1.1';       # version number
my $DEBUG = 0;                  # to be used for debugging
my $nohup = 0;                  # for use in non-interactive mode
my $MAXTRAY = 9;                # maximum number of trays
my $MAXSLOT = 24;               # maximum number of slots

# use this to set debug mode command line arguments
if ($DEBUG) { @ARGV = ('-n', 'majorEventLog.txt'); }

################################################################################
#                              REVISION SUMMARY
################################################################################
# Fixed in 1.0.0.1:
# - very minor printing adjustments (new line changes)
################################################################################
# Fixed in 1.0.1.0:
# - incorporated finding of PI errors in URS timeline
################################################################################
# Fixed in 1.0.1.1:
# - Fixed a slight issue in the checking of controller resets
################################################################################

#-------------------------------------------------------------------------------

# print_version - prints the version
sub print_version {
    print "MEL Analyzer - Version $VERSION\n\n";
    return;
}

# print_usage_info - prints the usage information (including version)
sub print_usage_info {
    print_version;
    print "\n  Performs basic analysis of a MEL. "
          . "Includes summary for controller and URS.\n\n";
    print 'Usage: perl AnalyzeMEL.pl [-n|-v|-?|majorEventLog.txt]';
    print "\n    -n, --nohup      Run without user input and print to STDOUT";
    print "\n    -v, --version    Print version number and exit";
    print "\n    -h, --help, -?   Print usage information and exit\n\n";
    return;
}

#-------------------------------------------------------------------------------

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
print_version;
print "Reading MEL... ";
open(MEL, "<", "$arg") or die("Could not open file: $arg");
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

while(<MEL>) {
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
            if ($type =~ m/Volume/xsm &&
                $desc =~ m{(Unreadable|                 # URS errors
                           Protection\sinformation)     # PI errors
                          }xsm)
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
close(MEL);
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
            my $desc = @$_[1];
            if ($desc =~ m{Unreadable}xsm) { $desc = 'URS'.(substr $desc, 30); }
            else { $desc = 'Protection information mismatch'; }
            my $vol = substr @$_[2], 20;
            printf("%-24s%-42s%-12s\n", $time, $desc, $vol);
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
            my $controller = ($loca =~ m/slot \s [A1]/xsim ? 
                              'Controller A': 
                              'Controller B');
            printf("%-24s%-42s%-12s\n", $time, $desc, $controller);
        }
    } else
    {
        print "No major controller events!\n";
    }
}

# print_drive_summary - prints the summary of all drive errors (it's crazy)
sub print_drive_summary
{
    print "DRIVE SUMMARY:\n\n";
    for my $tray (0 .. $MAXTRAY)
    {
        for my $slot (0 .. $MAXSLOT)
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
                    my $time = substr $drive_errors{$loca}->{$desc}->{'time'}, 
                                      11;
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
print "\n",'-'x79,"\n";

my $input = 'yes';
if (!$nohup)
{
    print 'Print the drive summary (y/n)? [default y]  ';
    $input = <STDIN>;
    print '-'x79,"\n";
}

if ($input =~ m/^n/xsim)
{
    print "\n";
    exit 0;
}
print_drive_summary;
print "\n";

1;

__END__

#-------------------------------------------------------------------------------

=pod

=head1 NAME

    SupportBundle::AnalyzeMEL.pl - Analyzes a MEL for disk array troubleshooting

=head1 VERSION

    This documentation refers to SupportBundle::AnalyzeMEL.pl version 1.0.0.0.

=head1 DESCRIPTION

    This program parses through a Major Event Log (MEL) searching for critical
    issues (such as URS conditions) or controller problems and prints them out 
    in an ordered table form so that the reader can look through it easily.

=head1 USAGE

    C<perl AnalyzeMEL.pl [-n|-v|-?|majorEventLog.txt]>

=head1 OPTIONS

=over 4

=item C<-n>, C<--nohup>

    Run without user input and print to STDOUT

=item C<-v>, C<--version>

    Print version number and exit

=item C<-h>, C<--help>, C<-?>

    Print usage information and exit

=back

=head1 EXIT STATUS

    If the program exited successfully, it will exit with a code of 0.
    All other exit codes indicate an error.

=head1 BUGS AND LIMITATIONS

    This program assumes a maximum of 9 trays and 24 slots.
    Manual alteration is required for anything more specific.

=head1 AUTHOR

    Jason Michael Runkle <jason.runkle@teradata.com>

=cut