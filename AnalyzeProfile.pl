#!/usr/bin/perl

################################################################################
# AnalyzeProfile.pl - analyzes the storageArrayProfile for disk array 
#   troubleshooting, gives a health check of the array
# RCS Keywords:
#     $Date: 2013-05-08 (Wed, 8 May 2013) $
#   $Source: /home/AnalyzeSCD.pl $
#   $Author: jr186037 $
# $Revision: 1.0.0.0 $
################################################################################

package AnalyzeProfile;

use strict;
use warnings;

#-------------------------------------------------------------------------------

our $VERSION = '1.0.0.0';       # version number
my $DEBUG = 1;                  # for debug mode
my $nohup = 0;                  # for non-interactive mode

# use this to set debug mode command line arguments
if ($DEBUG) { @ARGV = ('-n', 'storageArrayProfile.txt'); }

################################################################################
#                              REVISION SUMMARY
################################################################################
# No revisions to date
################################################################################

#-------------------------------------------------------------------------------


# print_version - prints the version
sub print_version {
    print "\nArray Profile Analyzer - Version $VERSION\n\n";
    return;
}

# print_usage_info - prints the usage information (including version)
sub print_usage_info {
    print_version;
    print "\n  Performs basic analysis of the storage array profile.\n\n";
    print 'Usage: perl AnalyzeProfile.pl [-n|-v|-?|storageArrayProfile.txt]';
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
print "\nReading storageArrayProfile... ";
open(SAP, "<", "$arg") or die("Could not open file: $arg");
print "Done.\nBuilding data structures... ";

# $section - stores the current section we are in or '' if unknown/start
my $section = '';

#
my ($controller_status_a,$controller_status_b,$controller_fw,$controller_type,
    $controller_sn_a,$controller_sn_b,@volumes_a,@volumes_b);

while(<SAP>) {
    chomp;
    # See if we are at a boundary where we need to switch.
    if (1)
    { 
        
    }             
    elsif (1)
    { 
        
    }     
    elsif (1)
    { 
        
    }
    elsif (1)
    {
        
    }
    elsif (1)
    {
        
    }
    if (1)
    {
        
    }
    elsif (1)
    {
        
    }
    elsif(1)
    {
        
    }
}
close(SAP);
print "Done.\n";

#-------------------------------------------------------------------------------

# function - description
sub myfunc
{
    return;
}

#-------------------------------------------------------------------------------

print '-'x79,"\n";

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

C<perl AnalyzeProfile.pl [-n|-?|-v|storageArrayProfile.txt]>

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