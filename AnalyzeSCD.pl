#!/usr/bin/perl

################################################################################
# AnalyzeSCD.pl - analyzes the stateCaptureData for disk array troubleshooting
# RCS Keywords:
#     $Date: 2013-05-03 (Fri, 3 May 2013) $
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

# $uptime_a, $uptime_b, $type, $fw_a, $fw_b are the constants holding the 
#   controllers uptime, type, and fw
my ($uptime_a, $uptime_b, $type, $fw);

# @luall_a, @luall_b, @chall_a, @chall_b contain the lines for luall/chall on 
#   controller A and B resptively
my (@luall_a, @luall_b, @chall_a, @chall_b);

# @chall0 and @luall0 are accumulators for the while loop
my (@chall0, @luall0);

# $time tracks the uptime until the controller is determined
my $time;

# %info_a, %info_b contains a hash of a hash with the information from the luall
#   on controller A and controller B respectively. Format is:
#   $info_a{'t#,s##'}->{'type'=>type, 'orp'=>orp, 'count'=>count}
my (%info_a,%info_b);

# $chall, $luall, $a are flags indicating that we are in a chall or luall and
#   controller A (else controller B)
my ($chall, $luall, $a);

while(<SCD>) {
    chomp;
    # See if we are at a boundary where we need to switch.
    if ($_ =~ m{->          # match '->'
                \s          # a space
                chall       # 'chall'
                \s          # another space
                0           # and a zero
                }xsm)       # should catch '-> chall 0'
    { 
        $chall = 1;         # turn the chall flag on
        @chall0 = ();       # reset chall0 accumulator
    }             
    elsif ($_ =~ m{->       # mathc '->'
                   \s       # a space
                   luall    # 'luall'
                   \s       # another space
                   0        # and a zero
                   }xsm)    # should catch '-> luall 0'
    { 
        $chall = 0;         # turn off chall flag
        if ($a)
        {
            @chall_a = @chall0;
        }
        else
        {
            @chall_b = @chall0;
        }
        $luall = 1;         # turn luall flag on
        @luall0 = ();       # reset luall0 accumulator
    }     
    elsif ($_ =~ m{->            # mathc '->'
                   \s            # a space
                   iditnall      # 'iditnall'
                   \s            # another space
                   0             # and a zero
                   }xsm)    # should catch '-> iditnall 0'
    { 
        $luall = 0;     # turn off luall flag
        if ($a)
        {
            @luall_a = @luall0;
        }
        else
        {
            @luall_b = @luall0;
        }
    }
    if ($chall)
    {
        push(@chall0, $_); # record the line
        if ($_ =~ m{Tick        # match 'Tick'
                    \s          # a space
                    (\d+)       # a series of digits (with backref)
                    }xsm)       # should catch 'Tick ##########'
        {
            $time = int($1/5184000);
        }
        elsif ($_ =~ m{^                              # match at start of line
                       (\d+)                          # some digits (w/ bref)
                       -                              # a hyphen
                       ([AB])                         # 'A' or 'B' (with bref)
                       \s+                            # 1 or more spaces
                       (\d\d[.]\d\d[.]\d\d[.]\d\d)    # and ##.##.##.## (w/ bref)
                       }xsm)
        {
            $type = $1;             # set controller type (assumed same)
            $a = $2 =~ m/A/xsm;     # set a flag if controller A
            $fw = $3;               # set firmware version variable
            if ($a)
            {
                $uptime_a = $time;
            }
            else
            {
                $uptime_b = $time;
            }
        }
    }
    elsif ($luall)
    {
        push(@luall0, $_); # record the line
        if ($_ =~ m{^               # match at start of line
                    [\sd><]+        # one or more spaces or d's or >'s or <'s
                    \w+             # non-space(s)
                    \s+             # space(s)
                    (t\d,s\d+)      # 't#,s##' (w/ backref)
                    \s+             # space(s)
                    (SASdr|FCdr)    # 'SASdr' or 'FCdr' (w/ backref)
                    \s+             # space(s)
                    :               # a colon
                    ([+\-d]+)       # a combo of '+', '-', and 'd'
                    \s+             # space(s)
                    :               # a colon
                    \s+             # space(s)
                    .               # any character (should be * or +)
                    \s+             # space(s)
                    .               # any character (should be * or +)
                    \s+             # space(s)
                    :               # a colon
                    \s+\d+          # space(s) followed by digit(s)
                    \s+\d+          # space(s) followed by digit(s)
                    \s+\d+          # space(s) followed by digit(s)
                    \s+\d+          # space(s) followed by digit(s)
                    \s+             # space(s)
                    (\d+)           # digit(s) (w/ backref)
                    }xsm)
        # should match: ' 00010000 t0,s1 FCdr :+++ : + * : 16 0 0 82337 4'

        {
            if ($a)
            {
                $info_a{$1} = {
                    'type'  => $2,
                    'orp'   => $3,
                    'count' => $4
                };
            }
            else
            {
                $info_b{$1} = {
                    'type'  => $2,
                    'orp'   => $3,
                    'count' => $4
                };
            }
        }
    }
}
close(SCD);
print "Done.\n\n";

#-------------------------------------------------------------------------------

# print_controller_info
sub print_controller_info
{
    if ($type) 
    {
        print "Controllers are $type"."s with $fw firmware.\n\n";
        if ($uptime_a)
        {
            print "Controller A has been up $uptime_a days.\n";
        }
        if ($uptime_b)
        {
            print "Controller B has been up $uptime_b days.\n";
        }
    }
}

# print_luall - prints luall for controller A
sub print_luall
{
    print substr($_, 0, 79),"\n" foreach(@luall_a);
    print substr($_, 0, 79),"\n" foreach(@luall_b);
    return;
}

# print_chall - prints chall for controller A
sub print_chall
{
    print substr($_, 0, 79),"\n" foreach(@chall_a);
    print substr($_, 0, 79),"\n" foreach(@chall_b);
    return;
}

# print_luall_info - prints the luall information
sub print_luall_info
{
    print ' /','-'x48,'\\',"\n";
    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",'Drive','Drive','ORP','ORP','Errors','Errors');
    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",'Position','Type',' A ',' B ',' on A ',' on B ');
    print ' |','-'x48,,'|',"\n";
    for my $tray (0 .. 8)
    {
        for my $slot (1 .. 24)
        {
            my $ts = "t$tray,s$slot";
            my ($drive_type, $orp_a, $count_a, $orp_b, $count_b);
            if ($info_a{$ts})
            {
                $drive_type = $info_a{$ts}->{'type'};
                $orp_a = $info_a{$ts}->{'orp'};
                $count_a = $info_a{$ts}->{'count'};
            }
            if ($info_b{$ts})
            {
                $drive_type = $info_b{$ts}->{'type'};
                $orp_b = $info_b{$ts}->{'orp'};
                $count_b = $info_b{$ts}->{'count'};
            }
            if ($drive_type)
            {
                if ($orp_a && $orp_b)
                {
                    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",$ts,$drive_type,$orp_a,$orp_b,$count_a,$count_b);
                }
                elsif ($orp_a)
                {
                    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",$ts,$drive_type,$orp_a,'N/A',$count_a,'N/A');
                }
                elsif ($orp_b)
                {
                    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",$ts,$drive_type,'N/A',$orp_b,'N/A',$count_b);
                }
            }
        }
    }
    print ' \\','-'x48,'/',"\n";
    return;
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
            # if ($drive_errors{$loca})
            # {
                # my $total_errors = 0;
                # print "Drive in $loca has the following errors:\n";
                # for my $desc (keys %{$drive_errors{$loca}})
                # {
                    # my $count = $drive_errors{$loca}->{$desc}->{'count'};
                    # $total_errors += $count;
                    # my $time = substr $drive_errors{$loca}->{$desc}->{'time'}, 11;
                    # $desc = substr $desc, 13, 51;
                    # printf("  %-5s %-51s%-20s\n", $count, $desc, $time);
                # }
                # print "TOTAL ERRORS: $total_errors\n";
                # print '-'x79,"\n";
            # }
        }
    }
    return;
}

#-------------------------------------------------------------------------------

print '-'x79,"\n";
print_controller_info;
print "\n";
print_luall_info;
print "\n";
print_chall;
print "\n";
print_luall;

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
