#!/usr/bin/perl

################################################################################
# AnalyzeSCD.pl - analyzes the stateCaptureData for disk array troubleshooting
# RCS Keywords:
#     $Date: 2013-05-08 (Wed, 8 May 2013) $
#   $Source: /home/AnalyzeSCD.pl $
#   $Author: jr186037 $
# $Revision: 1.1.0.1 $
################################################################################

package AnalyzeSCD;

use strict;
use warnings;

#-------------------------------------------------------------------------------

our $VERSION = '1.1.0.1';       # version number
my $DEBUG = 0;                  # for debug mode
my $nohup = 0;                  # for non-interactive mode

# use this to set debug mode command line arguments
if ($DEBUG) { @ARGV = ('-n', 'stateCaptureData.txt'); }

################################################################################
#                              REVISION SUMMARY
################################################################################
# Fixed in 1.0.0.1:
# - print that no luall/chall were found when that happens
# - correctly handle the case of negative Tick counts
################################################################################
# Fixed in 1.1.0.0:
# - capture/print the exception log
################################################################################
# Fixed in 1.1.0.1:
# - fixed zero days uptime bug = prints 'zero' days
# - fixed documentation for pod2man, pod2html, etc.
################################################################################

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

my $arg = $ARGV[0];    # $arg = command line argument

# if the argument is "-h" or "-?" or "--help" print usage information
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
}
# if the argument is "-v" or "--version" print version
elsif (
    $arg =~ m{^           # at start of string
            (-v|          # match '-v'
            --version)    # or '--version'
            $             # end of string
            }xsim
  )
{
    print_version;
    exit 0;
}
# if the argument is "-n" or "--nohup" run w/o input
elsif ($arg =~ m{^            # at start of string
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

# $uptime_a, $uptime_b, $type, and $fw are the constants holding the 
#   controllers uptime, type, and fw
my ($uptime_a, $uptime_b, $type, $fw);

# @luall_a, @luall_b, @chall_a, @chall_b contain the lines for luall/chall on 
#   controller A and B resptively
my (@luall_a, @luall_b, @chall_a, @chall_b);

# @chall0 and @luall0 are accumulators for the while loop
my (@chall0, @luall0);

# $time tracks the uptime until the controller is determined
my $time;

# %info_a, %info_b contains a hash of a hash with the information from the
#   luall on controller A and controller B respectively. Format is:
#   $info_a{'t#,s##'}->{'type'=>type, 'orp'=>orp, 'count'=>count}
my (%info_a,%info_b);

# @errors_a, @errors_b contain arrays of the errors on controller A and B resp.
my (@errors_a, @errors_b);

# $chall, $luall, $a are flags indicating that we are in a chall or luall and
#   controller A (else controller B)
my ($chall, $luall, $a);

# @exclog_a, @exclog_b are arrays containing the lines for the exception log
#   on controller A and controller B respectively
my (@exclog_a, @exclog_b);

# $exclog is a flag indicating that we are in an exclog section
my $exclog;

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
    elsif ($_ =~ m{->       # match '->'
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
    elsif ($_ =~ m{->            # match '->'
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
    elsif ($_ =~ m{Executing        # match 'Executing'
                   \s               # a space character
                   excLogShow       # 'excLogShow'
                   .+               # anything
                   controller       # 'controller'
                   \s               # a space character
                   ([AB])           # 'A' or 'B' (w/ backref)
                   }xsm)
    {
        $a = $1 =~ m{A}xsm;
        $exclog = 1;
    }
    elsif ($exclog && ($_ =~ m{^        # line starts with
                               Step     # Step
                               }xsm))
   {
        $exclog = 0;
   }
    if ($chall)
    {
        push(@chall0, $_); # record the line
        if ($_ =~ m{Tick        # match 'Tick'
                    \s          # a space
                    (-?\d+)     # a series of digits (with backref)
                                #  with an optional negative sign
                    }xsm)       # should catch 'Tick ##########'
        {
            if ($1 < 0) { $time = int((-$1 + 2**31)/5184000); }
            else { $time = int($1/5184000); }
            if ($time == 0) { $time = 'zero'; }
        }
        elsif ($_ =~ m{^                            # match at start of line
                       (\d+)                        # some digits (w/ bref)
                       -                            # a hyphen
                       ([AB])                       # 'A' or 'B' (with bref)
                       \s+                          # 1 or more spaces
                       (\d+[.]\d+[.]\d+[.]\d+)  # and ##.##.##.## (w/ bref)
                       }xsm)
        {
            $type = $1;             # set controller type (assumed same)
            $fw = $3;               # set firmware version variable
            $a = $2 =~ m/A/xsm;     # set a flag if controller A
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
                push(@errors_a, $4);
            }
            else
            {
                $info_b{$1} = {
                    'type'  => $2,
                    'orp'   => $3,
                    'count' => $4
                };
                push(@errors_b, $4);
            }
        }
    }
    elsif($exclog)
    {
        if ($a) { push(@exclog_a, $_); }
        else { push(@exclog_b, $_); }
    }
}
close(SCD);
print "Done.\n";

#-------------------------------------------------------------------------------

# print_controller_info
sub print_controller_info
{
    if ($type) 
    {
        print "CONTROLLER INFO:\n\n";
        print "Controllers are $type"."s with $fw firmware.\n\n";
        if ($uptime_a) { print "Controller A has been up $uptime_a days.\n"; }
        if ($uptime_b) { print "Controller B has been up $uptime_b days.\n"; }
    }
    else { print "No luall/chall found...\n"; }
    print '-'x79,"\n";
    return;
}

# sum - adds up all the elements of an array
sub sum
{
    my $sum = 0;
    $sum += $_ foreach(@_);
    return $sum;
}

# mean - gets the average of all the elements in an array
sub mean
{
    return sum(@_)/@_;
}

# stdev - gets the standard deviation of an array
sub stdev
{
    my $mean = mean(@_);
    my $sse = 0;
    $sse += ($_ - $mean)*($_ - $mean) foreach(@_);
    return sqrt($sse)/@_;
}

# print_outliers - prints out the possible outliers in the set of data
sub print_outliers
{
    my %outliers;
    if (@errors_a)
    {
        my $mean_a = mean(@errors_a);
        my $stdev_a = stdev(@errors_a);
        if ($stdev_a == 0) { $stdev_a = 1; }
        foreach(keys %info_a)
        {
            my $count = $info_a{$_}->{'count'};
            if ($count >= $mean_a + $stdev_a) { $outliers{$_} = $count; }
        }
    }
    if (@errors_b)
    {
        my $mean_b = mean(@errors_b);
        my $stdev_b = stdev(@errors_b);
        if ($stdev_b == 0) { $stdev_b = 1; }
        foreach(keys %info_b)
        {
            my $count = $info_b{$_}->{'count'};
            if ($count >= $mean_b + $stdev_b)
            {
                if (!$outliers{$_} || 
                   ($outliers{$_} && $count > $outliers{$_}))
                { $outliers{$_} = $count; }
            }
        }
    }
    if (%outliers)
    {
        print "POTENTIAL OUTLIERS:\n\n";
        for my $tray (0 .. 8)
        {
            for my $slot (1 .. 24)
            {
                my $ts = "t$tray,s$slot";
                if ($outliers{$ts})
                { print "  Drive in $ts has ",$outliers{$ts}," errors.\n"; }
            }
        }
    }
    else { print "\nNo outliers were found in the data.\n"; }
    print '-'x79,"\n";
}

sub print_orp_errors
{
    my $no_orp_errors = 1;
    print "ORP ERRORS:\n\n";
    for my $tray (0 .. 8)
    {
        for my $slot (1 .. 24)
        {
            my $ts = "t$tray,s$slot";
            if ($info_a{$ts} && $info_a{$ts}->{'orp'} ne '+++')
            { 
                $no_orp_errors = 0;
                print "$ts has A: ORP = ",$info_a{$ts}->{'orp'},
                ", B: ORP = ",
                ($info_b{$ts} ? $info_b{$ts}->{'orp'} : 'N/A'),"\n";
            }
            elsif ($info_b{$ts} && $info_b{$ts}->{'orp'} ne '+++')
            {
                $no_orp_errors = 0;
                print "$ts has A: ORP = ",
                ($info_a{$ts} ? $info_a{$ts}->{'orp'} : 'N/A'),
                ", B: ORP = ",$info_b{$ts}->{'orp'},"\n";
            }
        }
    }
    if ($no_orp_errors) { print "No ORP errors found.\n"; }
    print '-'x79,"\n";
}

# print_luall_info - prints the luall information
sub print_luall_info
{
    print ' /','-'x48,'\\',"\n";
    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",
            'Drive','Drive','ORP','ORP','Errors','Errors');
    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",
            'Position','Type',' A ',' B ',' on A ',' on B ');
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
                    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",
                    $ts,$drive_type,$orp_a,$orp_b,$count_a,$count_b);
                }
                elsif ($orp_a)
                {
                    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",
                    $ts,$drive_type,$orp_a,'N/A',$count_a,'N/A');
                }
                elsif ($orp_b)
                {
                    printf(" | %-8s | %-5s | %3s | %-3s | %-6s | %-6s |\n",
                    $ts,$drive_type,'N/A',$orp_b,'N/A',$count_b);
                }
            }
        }
    }
    print ' \\','-'x48,'/',"\n";
	print '-'x79,"\n";
    return;
}

# print_luall - prints luall output
sub print_luall
{
    if (@luall_a)
    {
        print "Controller A:\n";
        print "$_\n" foreach(@luall_a);
    }
    if (@luall_b)
    {
        print "Controller B:\n";
        print "$_\n" foreach(@luall_b);
    }
	print '-'x79,"\n";
    return;
}

# print_chall - prints chall output
sub print_chall
{
    if (@chall_a)
    {
        print "Controller A:\n";
        print "$_\n" foreach(@chall_a);
    }
    if (@chall_b)
    {
        print "Controller B:\n";
        print "$_\n" foreach(@chall_b);
    }
	print '-'x79,"\n";
    return;
}

# print_exclog - prints the exception log(s)
sub print_exclog
{
    if (@exclog_a) { print "$_\n" foreach(@exclog_a); }
    if (@exclog_b) { print "$_\n" foreach(@exclog_b); }
}

#-------------------------------------------------------------------------------

print '-'x79,"\n";
print_controller_info;
if (@errors_a || @errors_b) { print_outliers; }
if (%info_a || %info_b)
{
    print_orp_errors;
    print_luall_info;
}

my $input = 'y';
if ($DEBUG) { $input = 'n'; }
if (!$nohup)
{
    print "\n",'-'x79,"\n";
    print 'Print the full chall and luall outputs (y/n)? [default y]  ';
    $input = <STDIN>;
}

if ($input =~ m/^n/xsim)
{
    print "\n";
    exit 0;
}
print "\n";
if(@chall_a || @chall_b) { print_chall; }
print "\n";
if(@luall_a || @luall_b) { print_luall; }
print "\n";
print_exclog;

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

C<perl AnalyzeSCD.pl [-n|-?|-v] stateCaptureData.txt>

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
    Otherwise, the execution was not successful.

=head1 BUGS AND LIMITATIONS

    This program assumes a maximum of 8 trays and 24 slots.
    Manual alteration is required for anything more specific.

=head1 AUTHOR

Jason Michael Runkle <jason.runkle@teradata.com>

=cut

# Local Variables:
#   mode: cperl
#   cperl-indent-level: 4
#   fill-column: 78
#   indent-tabs-mode: nil
#   c-indentation-style: bsd
# End:
# ex: set ts=8 sts=4 sw=4 tw=78 ft=perl expandtab shiftround :
