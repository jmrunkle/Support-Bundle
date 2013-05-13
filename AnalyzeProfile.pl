#!/usr/bin/perl

################################################################################
# AnalyzeProfile.pl - analyzes the storageArrayProfile for disk array 
#   troubleshooting, gives a health check of the array
# RCS Keywords:
#     $Date: 2013-05-10 (Fri, 10 May 2013) $
#   $Source: /home/AnalyzeSCD.pl $
#   $Author: jr186037 $
# $Revision: 1.0.0.0 $
################################################################################

package AnalyzeProfile;

use strict;
use warnings;

#-------------------------------------------------------------------------------

our $VERSION = '1.0.0.0';       # version number
my $DEBUG = 0;                  # for debug mode
my $nohup = 0;                  # for non-interactive mode

# use this to set debug mode command line arguments
if ($DEBUG) { @ARGV = ('-n', 'storageArrayProfile6.txt'); }

################################################################################
#                              REVISION SUMMARY
################################################################################
# Got all the way to the drive channels portion
# Having massive trouble with SAP6.txt (fixed those, yeah!)
################################################################################

#-------------------------------------------------------------------------------


# print_version - prints the version
sub print_version {
    print "Array Profile Analyzer - Version $VERSION\n\n";
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
print_version;
print "Reading storageArrayProfile... ";
open(SAP, "<", "$arg") or die("Could not open file: $arg");
print "Done.\nBuilding data structures... ";

# $section - stores the current section we are in or '' if unknown/start
my $section = '';
# $subsection holds the current subsection within a section
my $subsection = '';

# $damc holds the name of the current DAMC in 'DAMCxxx-yy'
my $damc;

# %controllers holds the controller properties
#   $controllers{'A'}->{'status'=>status,'fw'=>fw,'type'=>type,'sn'=>sn,
#                       'volumes'=>[volumes]}... and similar for B
# $controller indicates whether it's controller A or controller B
my %controllers;
my $controller;

# @volumes holds the volume properties
#   $volumes[#]->{'status'=>status,'type'=type,
#                 'drives'=>[drives],'raid'=>raidlevel}
# $volume holds the name of the current volume
my @volumes;
my $volume;

# @drives holds the following drive properties
# $drives->[tray]->{'slot'}->{'status'=>status,'fw'=>fw}
my @drives;

# @hot_spares holds the hot spare locations
# %hot_spares_inuse indicates if that hot spare is actively in use
my @hot_spares;
my %hot_spares_inuse;

# @channels holds the drive channel properties
#   $channels[#]->{'status'=>status,'port'=>port}
my @channels;

while(<SAP>) {
    chomp;
    # See if we are at a boundary where we need to switch.
    if ($_ =~ m{^               # line starts with
                \s*             # (optional spaces)
                CONTROLLERS-    # 'CONTROLLERS-'
               }xsm)
    { $section = 'controllers'; }
    elsif ($_ =~ m{^          # line starts with
                   \s*        # (optional spaces)
                   VOLUME     # 'VOLUME'
                   \s         # a space
                   GROUPS-    # 'GROUPS-'
                  }xsm)
    { $section = 'volumes'; }
    elsif ($_ =~ m{^           # line starts with
                   STANDARD    # 'STANDARD'
                   \s          # a space
                   VOLUMES-    # 'VOLUMES-'
                  }xsm)
    { $section = ''; }
    elsif ($_ =~ m{^          # line starts with
                   \s*        # (optional spaces)
                   DRIVES-    # 'DRIVES-'
                  }xsm)
    { $section = 'drives'; }
    elsif ($_ =~ m{^            # line starts with
                   \s+          # space(s)
                   DRIVE        # 'DRIVE'
                   \s           # a space
                   CHANNELS:    # 'CHANNELS:'
                  }xsm)
    { $section = ''; }
    elsif ($_ =~ m{^            # line starts with
                   \s*          # (optional spaces)
                   HOT          # 'HOT'
                   \s           # a space
                   SPARE        # 'SPARE'
                   \s           # a space
                   COVERAGE:    # 'COVERAGE:'
                  }xsm)
    { $section = 'hot spares'; }
    elsif ($_ =~ m{^          # line starts with
                   \s+        # space(s)
                   DETAILS    # DETAILS
                   $          # end of line
                  }xsm)
    { $section = ''; $subsection = ''; }
    elsif ($_ =~ m{^
                   PROFILE \s FOR \s STORAGE \s ARRAY:
                   \s
                   (DAMC\d+-\d+-\d+)
                   \s
                  }xsm)
    { $damc = $1; }
    if ($section eq 'controllers')
    {
        if ($_ =~ m{Controller \s in .+ Slot \s [0A]}xsm)
        # if 'Controller in ... Slot [0A]'
        { $controller = 'a'; $subsection = 'controller'; }
        elsif ($_ =~ m{Controller \s in .+ Slot \s [1B]}xsm)
        # if 'Controller in ... Slot [0B]'
        { $controller = 'b'; $subsection = 'controller'; }
        elsif ($subsection eq 'controller' &&
               $_ =~ m{^
                       \s+
                       Status:
                       \s+
                       (\w+)
                      }xsm)
        { $controllers{$controller}->{'status'} = $1; }
        elsif ($subsection eq 'controller' && 
               $_ =~ m{^
                       \s+
                       Firmware
                       \s
                       version:
                       \s+
                       (\d+[.]\d+[.]\d+[.]\d+)
                      }xsm)
        { $controllers{$controller}->{'fw'} = $1; }
        elsif ($subsection eq 'controller' &&
               $_ =~ m{^
                       \s+
                       Board
                       \s
                       ID:
                       \s+
                       (\d+)
                      }xsm)
        { $controllers{$controller}->{'type'} = $1; }
        elsif ($subsection eq 'controller' &&
               $_ =~ m{^
                       \s+
                       Serial
                       \s
                       number:
                       \s+
                       (\w+)
                       \s+
                       $
                      }xsm)
        {
            $controllers{$controller}->{'sn'} = $1;
            $subsection = '';
        }
    }
    elsif ($section eq 'volumes')
    {
        if ($_ =~ m{^
                    \s+
                    Name:
                    \s+
                    (\d+)
                    \s+
                    $
                   }xsm)
        { $subsection = ''; $volume = $1-1; }
        elsif ($_ =~ m{^
                       \s+
                       VOLUME \s GROUP
                       \s
                       (\d+)
                       \s
                       \(RAID\s
                       (\d+)
                       \)}xsm)
        {
            $subsection = '';
            $volume = $1-1;
            $volumes[$volume]->{'raid'} = $2;
        }
        elsif (($_ =~ m{^
                       \s+
                       Status:
                       \s+
                       (\w+)
                       \s+
                       $
                      }xsm) || 
               ($_ =~ m{^
                        \s+
                        Volume \s group \s status:
                        \s+
                        (\w+)
                       }xsm))
        { $volumes[$volume]->{'status'} = $1; }
        elsif ($_ =~ m{^
                       \s+
                       RAID
                       \s
                       level:
                       \s+
                       (\d+)
                       \s+
                       $
                      }xsm)
        { $volumes[$volume]->{'raid'} = $1; }
        elsif ($_ =~ m{^
                       \s+
                       (Media|
                       Drive \s media)
                       \s
                       type:
                       \s+
                       ((\w+\s*)+)
                       $
                      }xsm)
        { $volumes[$volume]->{'type'} = $2; }
        elsif ($_ =~ m{^
                       \s+
                       Associated \s drives
                      }xsm)
        { 
            $subsection = 'associated';
            $volumes[$volume]->{'drives'} = [];
        }
        elsif ($subsection eq 'associated' &&
               $_ =~ m{^
                       \s+
                       (\d+)
                       \s+
                       (\d+)
                      }xsm)
        {
            my ($tray, $slot) = ($1, $2);
            if ($slot < 10) { $slot = "$slot "; }
            $volumes[$volume]->{'drives'} = 
                [@{$volumes[$volume]->{'drives'}}, "$tray,$slot"];
        }
        
    }
    elsif($section eq 'drives')
    {
        if ($_ =~ m{^\s+
                    (\d+),\s+(\d+)
                    \s+
                    (\w+)
                    \s+
                    \S+\s+GB
                    \s+
                    (\w+\s+\w+\s+\w+)
                    \s+
                    \w+
                    \s+
                    \d+\s+Gbps
                    \s+
                    (\S+)
                    \s+
                    (\w+)
                   }xsm)
        { $drives[$1]->{$2} = {
                                  'status' => $3,
                                  'type' => $4,
                                  'product id' => $5,
                                  'fw' => $6
                              }; }
        elsif ($_ =~ m{^\s+
                       (\d+),\s+(\d+)
                       \s+
                       (\w+)
                       \s+
                       \S+\s+GB
                       \s+
                       \d+\s+Gbps
                       \s+
                       (\S+)
                       \s+
                       (\w+)
                      }xsm)
        { $drives[$1]->{$2} = {
                                  'status' => $3,
                                  'product id' => $4,
                                  'fw' => $5
                              }; }
        elsif ($_ =~ m{^\s+
                       (\d+),\s+(\d+)
                       \s+
                       (\w+)
                       \s+
                       \S+\s+GB
                       \s+
                       \w+
                       \s+
                       \d+\s+Gbps
                       \s+
                       (\S+)
                       \s+
                       (\w+)
                      }xsm)
        { $drives[$1]->{$2} = {
                                  'status' => $3,
                                  'product id' => $4,
                                  'fw' => $5
                              }; }
    }
    elsif($section eq 'hot spares') 
    {
        if ($_ =~ m{Total \s hot \s spare \s drives:
                    \s+
                    (\d+)
                   }xsm)
        { if ($1 == 0) { $section = ''; } }
        elsif ($_ =~ m{^
                       \s*
                       Standby \s drive \s at \s
                       tray \s (\d+), \s
                       slot \s (\d+)
                      }xsm)
        { $subsection = ''; push(@hot_spares,[$1,$2]); }
        elsif ($_ =~ m{^
                       \s*
                       In \s use \s drive \s at \s
                       tray \s (\d+), \s
                       slot \s (\d+)
                      }xsm)
        {
            push(@hot_spares,[$1,$2]);
            $hot_spares_inuse{$1}->{$2} = 1;
            $subsection = [$1, $2];
        }
        elsif ($subsection &&
               $_ =~ m{^
                       \s*
                       Sparing \s for \s drive \s at \s
                       tray \s (\d+), \s
                       slot \s (\d+)
                      }xsm)
        { $hot_spares_inuse{$subsection->[0]}->{$subsection->[1]} = [$1, $2]; }
    }
}
close(SAP);
print "Done.\n";

#-------------------------------------------------------------------------------

# print_controller_information - prints out the controller information
sub print_controller_information
{
    print "\nCONTROLLERS\n\n";
    if ($controllers{'a'}->{'type'} && $controllers{'a'}->{'fw'})
    { printf("These are %s controllers with %s FW.\n\n",
           $controllers{'a'}->{'type'},$controllers{'a'}->{'fw'}); }
    elsif ($controllers{'b'}->{'type'} && $controllers{'b'}->{'fw'})
    { printf("These are %s controllers with %s FW.\n\n",
           $controllers{'b'}->{'type'},$controllers{'b'}->{'fw'}); }
    printf("Controller A (%s) is %s.\n",
        ($controllers{'a'}->{'sn'}?$controllers{'a'}->{'sn'}:'No SN'),
        ($controllers{'a'}->{'status'}?$controllers{'a'}->{'status'}:'N/A'));
    printf("Controller B (%s) is %s.\n",
        ($controllers{'b'}->{'sn'}?$controllers{'b'}->{'sn'}:'No SN'),
        ($controllers{'b'}->{'status'}?$controllers{'b'}->{'status'}:'N/A'));
    print "\n",'-'x79,"\n";
    return;
}

# print_volume_information - prints out the volume information
sub print_volume_information
{
    print "\nVOLUMES\n\n";
    print '/','-'x65,'\\',"\n";
    printf("| %-6s |  %-6s  | %-4s | %-5s | %-28s |\n",
           'Volume','Status','RAID','Media','Drives');
    print '|','='x8,'|','='x10,'|','='x6,'|','='x7,'|','='x30,'|',"\n";
    foreach (0 .. $#volumes)
    {
        printf("|   %-3s  | %-8s |  %-2s  |  %-3s  | %-28s |\n",
               $_,$volumes[$_]->{'status'},
               $volumes[$_]->{'raid'},
               ($volumes[$_]->{'type'} ? 
                ($volumes[$_]->{'type'} =~ m{Hard}xsm ? 'HDD' : 'SSD') :
                'N/A'),
               join('  ',@{$volumes[$_]->{'drives'}}));
    }
    print '\\','-'x65,'/',"\n\n";
    print '-'x79,"\n";
    return;
}

# print_drive_information - prints out the drive information
sub print_drive_information
{
    print "\nDRIVES\n\n";
    print '/','-'x56,'\\',"\n";
    printf("| %-5s  |   %-6s   | %-5s |  %-2s  | %-17s |\n",
           'Drive','Status','Media','FW','Product ID');
    print '|','='x8,'|','='x12,'|','='x7,'|','='x6,'|','='x19,'|',"\n";
    for my $tray (0 .. 8)
    {
        for my $slot (1 .. 24)
        {
            if($drives[$tray] && $drives[$tray]->{$slot})
            { printf("|  %-4s  | %-10s |  %-3s  | %-4s | %-17s |\n",
                   "$tray,$slot",
                    $drives[$tray]->{$slot}->{'status'},
                   ($drives[$tray]->{$slot}->{'type'} ?
                     ($drives[$tray]->{$slot}->{'type'} =~ m{Hard}xsm ? 
                     'HDD' : 'SSD' ) : 
                     'N/A'),
                   $drives[$tray]->{$slot}->{'fw'},
                   $drives[$tray]->{$slot}->{'product id'}); }
        }
    }
    print '\\','-'x56,'/',"\n\n";
    print '-'x79,"\n";
    return;
}

# print_hot_spares - prints out the hot spares defined in the disk array
sub print_hot_spares
{
    print "\nGHS DRIVES: ";
    print '(',$_->[0],',',$_->[1],') ' foreach(@hot_spares);
    print "\n\n";
    for my $tray (keys %hot_spares_inuse)
    {
        for my $slot (keys %{$hot_spares_inuse{$tray}})
        {
            print "($tray,$slot) is sparing for (";
            print $hot_spares_inuse{$tray}->{$slot}->[0],',';
            print $hot_spares_inuse{$tray}->{$slot}->[1],")\n";
        }
    }
    print "\n",'-'x79,"\n";
    return;
}

# print_damc - prints out the name of the disk array in question
sub print_damc
{
    print ' 'x35,$damc,"\n";
    print '-'x79,"\n";
    return;
}

#-------------------------------------------------------------------------------

print '-'x79,"\n";
if ($damc) { print_damc; }
if (%controllers) { print_controller_information; }
if (@hot_spares) { print_hot_spares; }
if (@volumes) { print_volume_information; }
if (@drives) { print_drive_information; }

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